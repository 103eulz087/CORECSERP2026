/* ================================================================
   2026-09-30c: ClientLedger / ClientAccounts -- recalc trigger + JELO'S PLACE fix
   ================================================================
   Audit (2026-09-30, docs/CLAUDE_WORKLOG.md Feature 12): the client ledger
   is sound (0 bad-math rows, no cross-account overwrite, AR totals tie),
   except JELO'S PLACE, which has two accounts:
     00007479 (branch 011, R- invoices) and 00009065 (branch 006, T_ invoices).
     * BF invoice T_036537 (136,338.20) was moved to 00009065 by editing its
       AccountKey; AccountID still says 00007479 and nothing was recomputed
       (InsertClientLedger fires on INSERT only).
     * BF invoice T_036293 (307,929.20) is still on 00007479, although
       TransactionChargeSales and its payment (OR-EWT, ref 26199) are on
       00009065.
   After both are on 00009065, each account equals its open invoices in
   TransactionChargeSales.

   This script (same pattern as 2026-09-30b for SupplierLedger):
     A. Backs up ClientLedger and ClientAccounts (created only if missing).
     B. JELO'S PLACE (user-approved 2026-09-30): moves the T_036293 BF row to
        00009065 at the next free TRN_SEQ_NO, and sets AccountID = 00009065 on
        both moved rows. Idempotent: does nothing if already moved.
     C. Recomputes every BeginningBalance / EndingBalance from Debit / Credit
        in TRN_SEQ_NO order (Ending = Beginning + Debit - Credit) and sets
        ClientAccounts.AccountBalance to each account's total. Only rows that
        differ are written (on 2026-09-30 that is just the two JELO'S PLACE
        accounts). Debit / Credit amounts are NOT changed.
     D. Replaces the trigger: InsertClientLedger -> InsertClientLedger_OLD_09302026190000
        (DISABLED); new trg_ClientLedger_Recalc (AFTER INSERT, UPDATE, DELETE)
        recomputes the whole chain of every account touched -- including
        both the old and the new account when a row is moved -- and its
        ClientAccounts balance. CashWalletBalance is not touched.

   Deploy to COREX001 (DEV) first, then CORECSJFC2026_STAGING (user-approved).
   ================================================================ */

-- ----------------------------------------------------------------
-- A. Backups
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.ClientLedger_Backup_20260930', 'U') IS NULL
    SELECT * INTO dbo.ClientLedger_Backup_20260930 FROM dbo.ClientLedger;
GO
IF OBJECT_ID('dbo.ClientAccounts_Backup_20260930', 'U') IS NULL
    SELECT * INTO dbo.ClientAccounts_Backup_20260930 FROM dbo.ClientAccounts;
GO

-- ----------------------------------------------------------------
-- B + C. JELO'S PLACE correction, then the one-time recompute
--        (the old trigger is INSERT-only, so these UPDATEs don't fire it)
-- ----------------------------------------------------------------
SET XACT_ABORT ON;
BEGIN TRANSACTION;

    DECLARE @From CHAR(8) = '00007479', @To CHAR(8) = '00009065';
    DECLARE @ToID VARCHAR(30) = (SELECT AccountID FROM dbo.ClientAccounts WHERE AccountKey = @To);

    IF @ToID IS NULL
        THROW 59950, 'ClientAccounts row for 00009065 (JELO''S PLACE, branch 006) not found - aborting.', 1;

    -- B1. move the T_036293 balance-forward row to 00009065 (next free sequence number)
    IF (SELECT COUNT(*) FROM dbo.ClientLedger WHERE AccountKey = @From AND InvoiceNo = 'T_036293' AND TransCode = 'BF') = 1
    BEGIN
        DECLARE @NewSeq DECIMAL(7) = (SELECT ISNULL(MAX(TRN_SEQ_NO), 0) + 1 FROM dbo.ClientLedger WHERE AccountKey = @To);

        UPDATE dbo.ClientLedger
        SET AccountKey = @To, AccountID = @ToID, TRN_SEQ_NO = @NewSeq
        WHERE AccountKey = @From AND InvoiceNo = 'T_036293' AND TransCode = 'BF';

        SELECT 'B1 moved T_036293 to 00009065' AS step, @@ROWCOUNT AS rows_;
    END
    ELSE
        SELECT 'B1 T_036293 not on 00007479 (already moved?) - skipped' AS step, 0 AS rows_;

    -- B2. rows filed under 00009065 but still carrying another AccountID (the T_036537 move)
    UPDATE dbo.ClientLedger
    SET AccountID = @ToID
    WHERE AccountKey = @To AND RTRIM(AccountID) <> RTRIM(@ToID);

    SELECT 'B2 AccountID corrected on 00009065 rows' AS step, @@ROWCOUNT AS rows_;

    -- C1. recompute every chain
    ;WITH C AS
    (
        SELECT cl.AccountKey, cl.TRN_SEQ_NO, cl.AccountID,
               ISNULL(cl.Debit, 0) - ISNULL(cl.Credit, 0) AS Net,
               SUM(ISNULL(cl.Debit, 0) - ISNULL(cl.Credit, 0)) OVER (
                   PARTITION BY cl.AccountKey ORDER BY cl.TRN_SEQ_NO
                   ROWS UNBOUNDED PRECEDING) AS RunEnd
        FROM dbo.ClientLedger cl
    )
    UPDATE cl
    SET cl.BeginningBalance = c.RunEnd - c.Net,
        cl.EndingBalance    = c.RunEnd
    FROM dbo.ClientLedger cl
    INNER JOIN C c ON c.AccountKey = cl.AccountKey AND c.TRN_SEQ_NO = cl.TRN_SEQ_NO AND c.AccountID = cl.AccountID
    WHERE ISNULL(cl.BeginningBalance, -999999999999) <> c.RunEnd - c.Net
       OR ISNULL(cl.EndingBalance,    -999999999999) <> c.RunEnd;

    SELECT 'C1 ledger rows corrected' AS step, @@ROWCOUNT AS rows_;

    -- C2. account balances = total of the account's entries
    ;WITH F AS
    (
        SELECT AccountKey, SUM(ISNULL(Debit, 0) - ISNULL(Credit, 0)) AS Bal
        FROM dbo.ClientLedger
        GROUP BY AccountKey
    )
    UPDATE ca
    SET ca.AccountBalance = f.Bal
    FROM dbo.ClientAccounts ca
    INNER JOIN F f ON f.AccountKey = ca.AccountKey
    WHERE ISNULL(ca.AccountBalance, -999999999999) <> f.Bal;

    SELECT 'C2 account balances corrected' AS step, @@ROWCOUNT AS rows_;

COMMIT TRANSACTION;
GO

-- ----------------------------------------------------------------
-- D. Trigger: rename + disable the old one, create the recalc trigger
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.InsertClientLedger', 'TR') IS NOT NULL
    EXEC sp_rename 'dbo.InsertClientLedger', 'InsertClientLedger_OLD_09302026190000';
GO
-- A renamed trigger stays active -- disable the backup so it can't double-post.
IF OBJECT_ID('dbo.InsertClientLedger_OLD_09302026190000', 'TR') IS NOT NULL
    DISABLE TRIGGER dbo.InsertClientLedger_OLD_09302026190000 ON dbo.ClientLedger;
GO
IF OBJECT_ID('dbo.trg_ClientLedger_Recalc', 'TR') IS NOT NULL
    EXEC sp_rename 'dbo.trg_ClientLedger_Recalc', 'trg_ClientLedger_Recalc_OLD_09302026190000';
GO
IF OBJECT_ID('dbo.trg_ClientLedger_Recalc_OLD_09302026190000', 'TR') IS NOT NULL
    DISABLE TRIGGER dbo.trg_ClientLedger_Recalc_OLD_09302026190000 ON dbo.ClientLedger;
GO

CREATE TRIGGER dbo.trg_ClientLedger_Recalc
ON dbo.ClientLedger
AFTER INSERT, UPDATE, DELETE
AS
/*
    Replaces InsertClientLedger (INSERT-only). For every account whose rows
    were inserted, updated, deleted or moved (both the old and the new
    AccountKey), recomputes the WHOLE chain (Ending = Beginning + Debit -
    Credit, TRN_SEQ_NO order) and sets ClientAccounts.AccountBalance to the
    account's total. PK_ClientLedger is clustered on AccountKey, so each
    account's chain is a seek. Its own UPDATE doesn't re-fire it
    (RECURSIVE_TRIGGERS is OFF; the nest-level guard covers it if that changes).
    CashWalletBalance is not touched.
*/
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL(@@PROCID) > 1 RETURN;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    DECLARE @K TABLE (AccountKey CHAR(8) NOT NULL PRIMARY KEY);
    INSERT INTO @K (AccountKey)
    SELECT AccountKey FROM inserted
    UNION
    SELECT AccountKey FROM deleted;

    ;WITH C AS
    (
        SELECT cl.AccountKey, cl.TRN_SEQ_NO, cl.AccountID,
               ISNULL(cl.Debit, 0) - ISNULL(cl.Credit, 0) AS Net,
               SUM(ISNULL(cl.Debit, 0) - ISNULL(cl.Credit, 0)) OVER (
                   PARTITION BY cl.AccountKey ORDER BY cl.TRN_SEQ_NO
                   ROWS UNBOUNDED PRECEDING) AS RunEnd
        FROM dbo.ClientLedger cl
        WHERE cl.AccountKey IN (SELECT AccountKey FROM @K)
    )
    UPDATE cl
    SET cl.BeginningBalance = c.RunEnd - c.Net,
        cl.EndingBalance    = c.RunEnd
    FROM dbo.ClientLedger cl
    INNER JOIN C c ON c.AccountKey = cl.AccountKey AND c.TRN_SEQ_NO = cl.TRN_SEQ_NO AND c.AccountID = cl.AccountID
    WHERE ISNULL(cl.BeginningBalance, -999999999999) <> c.RunEnd - c.Net
       OR ISNULL(cl.EndingBalance,    -999999999999) <> c.RunEnd;

    UPDATE ca
    SET ca.AccountBalance = ISNULL(f.Bal, 0)
    FROM dbo.ClientAccounts ca
    INNER JOIN @K k ON k.AccountKey = ca.AccountKey
    OUTER APPLY (SELECT SUM(ISNULL(cl.Debit, 0) - ISNULL(cl.Credit, 0)) AS Bal
                 FROM dbo.ClientLedger cl WHERE cl.AccountKey = k.AccountKey) f;
END
GO
