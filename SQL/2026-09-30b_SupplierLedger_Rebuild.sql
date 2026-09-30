/* ================================================================
   2026-09-30b: SupplierLedger / SupplierAccounts -- rebuild + recalc trigger
   ================================================================
   Audit (2026-09-30, docs/CLAUDE_WORKLOG.md Feature 11): on STAGING 403 of
   1,416 ledger rows break Ending = Beginning + Credit - Debit, 82 of 87
   suppliers are affected, and 36 SupplierAccounts balances are wrong
   (total 829.47M vs 856.13M). Causes:
     1. Historical cross-supplier overwrite: rows with the same TRN_SEQ_NO
        carry the SAME EndingBalance across different suppliers (an older
        trigger / outside script; the 2026-07-13 trigger itself tested
        correct), then propagated down each chain.
     2. InsertSupplierLedger fires on INSERT only: edit procs that DELETE
        ledger rows (sp_EditSingleExpense, sp_EditApprovedExpense,
        sp_EditExpenseManualMultiBranch) never recompute later rows or the
        account.
     3. 11 SupplierAccounts rows were created (at 0.00) after their ledger
        rows, so the INSERT trigger had no account row to update.
     4. sp_ReverseApprovedExpense tagged ErrorCorrectTag by TRN_SEQ_NO only,
        also tagging other suppliers' rows.

   This script:
     A. Backs up SupplierLedger and SupplierAccounts (created only if missing).
     B. Rebuilds every row's BeginningBalance / EndingBalance from the
        supplier's own Debit / Credit in TRN_SEQ_NO order (same order and
        rule as the trigger), and sets SupplierAccounts.AccountBalance to each
        supplier's final balance (creating the account row if missing).
        Debit / Credit amounts are NOT changed -- they are trusted as-is.
     C. Replaces the trigger: InsertSupplierLedger is renamed to
        InsertSupplierLedger_OLD_09302026180000 and DISABLED; the new
        trg_SupplierLedger_Recalc (AFTER INSERT, UPDATE, DELETE) recomputes
        the whole chain of every supplier touched, plus its account.
     D. Re-creates sp_ReverseApprovedExpense with the supplier-scoped tag
        (one statement changed; rest identical to the live proc).

   Balances follow entry order (TRN_SEQ_NO), not PostingDate, exactly as
   before -- a back-dated entry is placed at the end of the chain.
   Deploy to COREX001 (DEV) first; STAGING only after the user confirms.
   ================================================================ */

-- ----------------------------------------------------------------
-- A. Backups
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.SupplierLedger_Backup_20260930', 'U') IS NULL
    SELECT * INTO dbo.SupplierLedger_Backup_20260930 FROM dbo.SupplierLedger;
GO
IF OBJECT_ID('dbo.SupplierAccounts_Backup_20260930', 'U') IS NULL
    SELECT * INTO dbo.SupplierAccounts_Backup_20260930 FROM dbo.SupplierAccounts;
GO

-- ----------------------------------------------------------------
-- B. One-time rebuild (the old trigger is INSERT-only, so these UPDATEs
--    don't fire it; the new trigger is created afterwards)
-- ----------------------------------------------------------------
SET XACT_ABORT ON;
BEGIN TRANSACTION;

    ;WITH C AS
    (
        SELECT sl.SupplierKey, sl.TRN_SEQ_NO,
               ISNULL(sl.Credit, 0) - ISNULL(sl.Debit, 0) AS Net,
               SUM(ISNULL(sl.Credit, 0) - ISNULL(sl.Debit, 0)) OVER (
                   PARTITION BY sl.SupplierKey ORDER BY sl.TRN_SEQ_NO
                   ROWS UNBOUNDED PRECEDING) AS RunEnd
        FROM dbo.SupplierLedger sl
    )
    UPDATE sl
    SET sl.BeginningBalance = c.RunEnd - c.Net,
        sl.EndingBalance    = c.RunEnd
    FROM dbo.SupplierLedger sl
    INNER JOIN C c ON c.SupplierKey = sl.SupplierKey AND c.TRN_SEQ_NO = sl.TRN_SEQ_NO
    WHERE ISNULL(sl.BeginningBalance, -999999999999) <> c.RunEnd - c.Net
       OR ISNULL(sl.EndingBalance,    -999999999999) <> c.RunEnd;

    SELECT 'B1 ledger rows corrected' AS step, @@ROWCOUNT AS rows_;

    ;WITH F AS
    (
        SELECT SupplierKey, SUM(ISNULL(Credit, 0) - ISNULL(Debit, 0)) AS Bal
        FROM dbo.SupplierLedger
        GROUP BY SupplierKey
    )
    UPDATE sa
    SET sa.AccountBalance = f.Bal
    FROM dbo.SupplierAccounts sa
    INNER JOIN F f ON f.SupplierKey = sa.SupplierKey
    WHERE ISNULL(sa.AccountBalance, -999999999999) <> f.Bal;

    SELECT 'B2 account balances corrected' AS step, @@ROWCOUNT AS rows_;

    ;WITH F AS
    (
        SELECT SupplierKey, SUM(ISNULL(Credit, 0) - ISNULL(Debit, 0)) AS Bal
        FROM dbo.SupplierLedger
        GROUP BY SupplierKey
    )
    INSERT INTO dbo.SupplierAccounts (SupplierKey, SupplierID, SupplierName, AccountStatus, AccountBalance, LastMovementDate)
    SELECT f.SupplierKey, s.SupplierID, s.SupplierName, 'Active', f.Bal, GETDATE()
    FROM F f
    INNER JOIN dbo.Supplier s ON s.SupplierKey = f.SupplierKey
    WHERE NOT EXISTS (SELECT 1 FROM dbo.SupplierAccounts sa WHERE sa.SupplierKey = f.SupplierKey);

    SELECT 'B3 missing account rows created' AS step, @@ROWCOUNT AS rows_;

COMMIT TRANSACTION;
GO

-- ----------------------------------------------------------------
-- C. Trigger: rename + disable the old one, create the recalc trigger
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.InsertSupplierLedger', 'TR') IS NOT NULL
    EXEC sp_rename 'dbo.InsertSupplierLedger', 'InsertSupplierLedger_OLD_09302026180000';
GO
-- A renamed trigger stays active -- disable the backup so it can't double-post.
IF OBJECT_ID('dbo.InsertSupplierLedger_OLD_09302026180000', 'TR') IS NOT NULL
    DISABLE TRIGGER dbo.InsertSupplierLedger_OLD_09302026180000 ON dbo.SupplierLedger;
GO
IF OBJECT_ID('dbo.trg_SupplierLedger_Recalc', 'TR') IS NOT NULL
    EXEC sp_rename 'dbo.trg_SupplierLedger_Recalc', 'trg_SupplierLedger_Recalc_OLD_09302026180000';
GO
IF OBJECT_ID('dbo.trg_SupplierLedger_Recalc_OLD_09302026180000', 'TR') IS NOT NULL
    DISABLE TRIGGER dbo.trg_SupplierLedger_Recalc_OLD_09302026180000 ON dbo.SupplierLedger;
GO

CREATE TRIGGER dbo.trg_SupplierLedger_Recalc
ON dbo.SupplierLedger
AFTER INSERT, UPDATE, DELETE
AS
/*
    Replaces InsertSupplierLedger (INSERT-only). For every supplier whose
    rows were inserted, updated or deleted, recomputes the WHOLE chain
    (BeginningBalance / EndingBalance in TRN_SEQ_NO order from Debit /
    Credit) and sets SupplierAccounts.AccountBalance to the final balance
    (creating the account row if it's missing). Recomputing the whole chain
    (a supplier has at most a few hundred rows) makes edits, deletions and
    hand-edited balances self-heal. Its own UPDATE doesn't re-fire it
    (RECURSIVE_TRIGGERS is OFF; the nest-level guard covers it if that changes).
*/
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL(@@PROCID) > 1 RETURN;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    DECLARE @K TABLE (SupplierKey CHAR(6) NOT NULL PRIMARY KEY);
    INSERT INTO @K (SupplierKey)
    SELECT SupplierKey FROM inserted
    UNION
    SELECT SupplierKey FROM deleted;

    ;WITH C AS
    (
        SELECT sl.SupplierKey, sl.TRN_SEQ_NO,
               ISNULL(sl.Credit, 0) - ISNULL(sl.Debit, 0) AS Net,
               SUM(ISNULL(sl.Credit, 0) - ISNULL(sl.Debit, 0)) OVER (
                   PARTITION BY sl.SupplierKey ORDER BY sl.TRN_SEQ_NO
                   ROWS UNBOUNDED PRECEDING) AS RunEnd
        FROM dbo.SupplierLedger sl
        WHERE sl.SupplierKey IN (SELECT SupplierKey FROM @K)
    )
    UPDATE sl
    SET sl.BeginningBalance = c.RunEnd - c.Net,
        sl.EndingBalance    = c.RunEnd
    FROM dbo.SupplierLedger sl
    INNER JOIN C c ON c.SupplierKey = sl.SupplierKey AND c.TRN_SEQ_NO = sl.TRN_SEQ_NO
    WHERE ISNULL(sl.BeginningBalance, -999999999999) <> c.RunEnd - c.Net
       OR ISNULL(sl.EndingBalance,    -999999999999) <> c.RunEnd;

    DECLARE @F TABLE (SupplierKey CHAR(6) NOT NULL PRIMARY KEY, Bal MONEY NOT NULL);
    INSERT INTO @F (SupplierKey, Bal)
    SELECT k.SupplierKey, ISNULL(SUM(ISNULL(sl.Credit, 0) - ISNULL(sl.Debit, 0)), 0)
    FROM @K k
    LEFT JOIN dbo.SupplierLedger sl ON sl.SupplierKey = k.SupplierKey
    GROUP BY k.SupplierKey;

    UPDATE sa
    SET sa.AccountBalance   = f.Bal,
        sa.LastMovementDate = GETDATE()
    FROM dbo.SupplierAccounts sa
    INNER JOIN @F f ON f.SupplierKey = sa.SupplierKey;

    INSERT INTO dbo.SupplierAccounts (SupplierKey, SupplierID, SupplierName, AccountStatus, AccountBalance, LastMovementDate)
    SELECT f.SupplierKey, s.SupplierID, s.SupplierName, 'Active', f.Bal, GETDATE()
    FROM @F f
    INNER JOIN dbo.Supplier s ON s.SupplierKey = f.SupplierKey
    WHERE NOT EXISTS (SELECT 1 FROM dbo.SupplierAccounts sa WHERE sa.SupplierKey = f.SupplierKey);
END
GO

-- ----------------------------------------------------------------
-- D. sp_ReverseApprovedExpense -- supplier-scoped ErrorCorrectTag
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_ReverseApprovedExpense', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_ReverseApprovedExpense', 'sp_ReverseApprovedExpense_OLD_09302026180000';
GO

CREATE   PROCEDURE [dbo].[sp_ReverseApprovedExpense]
(
    @parmrefno      VARCHAR(10),
    @parminvoiceno  VARCHAR(150),
    @parmsupplierid VARCHAR(100),
    @parmreason     VARCHAR(300),
    @parmuser       VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE
            @supplierkey    VARCHAR(15),
            @parmbatchrefno BIGINT,
            @curStatus      VARCHAR(20),
            @curAmountPaid  DECIMAL(18,2);

        SELECT @supplierkey = SupplierKey FROM Supplier WHERE SupplierID = @parmsupplierid;

        SELECT
            @parmbatchrefno = BatchReferenceID,
            @curStatus      = Status,
            @curAmountPaid  = ISNULL(AmountPaid, 0)
        FROM ExpenseSummary
        WHERE SupplierID = @parmsupplierid
          AND ReferenceNumber = @parmrefno
          AND InvoiceNo = @parminvoiceno;

        IF @parmbatchrefno IS NULL
            THROW 57001, 'Expense not found for the given Reference/Invoice/Supplier.', 1;

        IF @curStatus <> 'POSTED'
            THROW 57002, 'Only POSTED (approved, unpaid) expenses can be error-corrected via this procedure.', 1;

        IF @curAmountPaid > 0
            THROW 57003, 'This expense already has a payment applied - reverse/cancel the payment first before error-correcting the approval.', 1;

        -- ── Reverse tickets: one reversal ticket per original branch ticket
        --    posted by sp_GenerateExpenseTicketsCompound (Origin='EXP',
        --    ReferenceNumber=refno, ReferenceKey=InvoiceNo) ──
        IF OBJECT_ID('tempdb..#RevTickets') IS NOT NULL DROP TABLE #RevTickets;

        SELECT
            ROW_NUMBER() OVER (ORDER BY TicketNumber) AS RowNum,
            TicketNumber, TicketDate, SupplementaryNumber, BranchCode,
            Origin, ReferenceKey, Owner, Particulars, CheckedBy, ApprovedBy, Status, Mnemonic
        INTO #RevTickets
        FROM TicketMaster
        WHERE  ReferenceNumber  = @parmrefno
          AND ReferenceKey     = @parminvoiceno;

        DECLARE @row INT = 1, @maxrow INT, @oldTicket VARCHAR(20), @newTicket VARCHAR(20), @revBranch VARCHAR(5);
        SELECT @maxrow = COUNT(*) FROM #RevTickets;

        IF @maxrow = 0
            THROW 57004, 'No posted tickets found for this expense - nothing to reverse.', 1;

        -- NEW: records each branch's new reversal TicketNumber as it's
        -- generated, so the SupplierLedger reversal (below, AFTER the loop)
        -- can look up the right ticket per branch without re-querying a
        -- table it's also inserting into.
        IF OBJECT_ID('tempdb..#TicketMap') IS NOT NULL DROP TABLE #TicketMap;
        CREATE TABLE #TicketMap (BranchCode VARCHAR(5), NewTicket VARCHAR(20));

        WHILE @row <= @maxrow
        BEGIN
            SELECT @oldTicket = TicketNumber, @revBranch = BranchCode FROM #RevTickets WHERE RowNum = @row;
            EXEC GetTicketNumber @newTicket OUTPUT;

            INSERT INTO TicketMaster
                (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber,
                 ReferenceNumber, ReferenceKey, Owner, Particulars,
                 EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
            SELECT
                CAST(GETDATE() as date), SupplementaryNumber, BranchCode, Origin, @newTicket,
                @parmrefno, ReferenceKey, Owner, '(REVERSAL) ' + Particulars,
                @parmuser, CheckedBy, ApprovedBy, Status, Mnemonic, 'REVERSAL'
            FROM #RevTickets WHERE RowNum = @row;

            -- Debit/Credit swapped to offset the original entry
            INSERT INTO TicketDetails
                (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                 TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
            SELECT
                CAST(GETDATE() as date), SupplementaryNumber, BranchCode, ReferenceKey,
                @newTicket, @parmrefno, AccountCode, Credit, Debit, CostCenter
            FROM TicketDetails
            WHERE TicketNumber       = @oldTicket
              AND ReferenceNumber    = @parmrefno
              AND ReferenceKey       = @parminvoiceno;

            INSERT INTO #TicketMap (BranchCode, NewTicket) VALUES (@revBranch, @newTicket);

            SET @row += 1;
        END;
        DROP TABLE #RevTickets;

        -- ═══════════════════════════════════════════════════════════════
        -- SupplierLedger reversal - moved OUT of the loop and done as ONE
        -- set-based step, driven by a frozen snapshot (#OrigLedgerRows)
        -- instead of repeatedly re-querying SupplierLedger itself.
        --
        -- BUG THIS FIXES: the previous per-branch-loop version selected
        -- FROM SupplierLedger WHERE ErrorCorrectTag=1 inside the same loop
        -- that was INSERTing new ErrorCorrectTag=1 rows into that same
        -- table. Each iteration's INSERT...SELECT excluded only its own
        -- about-to-be-inserted row (TicketReference <> @newTicket) - it
        -- did NOT exclude reversal rows inserted by EARLIER iterations,
        -- which also carried ErrorCorrectTag=1. So iteration 2 re-matched
        -- and re-reversed iteration 1's reversal row, iteration 3 re-
        -- matched iterations 1 AND 2's rows, and so on - compounding
        -- growth instead of one row per branch (3 branches -> 21 rows).
        --
        -- Fix: snapshot the exact original rows to reverse into a temp
        -- table BEFORE any INSERT happens. The reversal INSERT then reads
        -- from that static snapshot, never from SupplierLedger directly -
        -- so it can never re-match anything it (or a prior iteration)
        -- just inserted, regardless of how many branches are involved.
        -- ═══════════════════════════════════════════════════════════════
        IF OBJECT_ID('tempdb..#OrigLedgerRows') IS NOT NULL DROP TABLE #OrigLedgerRows;

        SELECT
            L.TRN_SEQ_NO, L.SupplierKey, L.SupplierID, L.Description, L.TransCode,
            L.ReferenceKey, L.InvoiceNo, L.Credit, L.TotalAmount, L.BatchReferenceID,
            tm.NewTicket
        INTO #OrigLedgerRows
        FROM SupplierLedger L
        JOIN #TicketMap tm ON L.ReferenceKey = CAST(@parmbatchrefno AS VARCHAR(40)) + '-' + tm.BranchCode
        WHERE (L.SupplierID = @supplierkey OR L.SupplierID = @parmsupplierid OR L.SupplierKey = @supplierkey)
          AND L.ReferenceNumber  = @parmrefno
          AND L.BatchReferenceID = @parmbatchrefno
          AND L.ErrorCorrectTag  = 0;

        IF (SELECT COUNT(*) FROM #OrigLedgerRows) <> @maxrow
            THROW 57005, 'SupplierLedger row count does not match ticket count - aborting to avoid a partial/incorrect reversal. Check for stale ErrorCorrectTag data.', 1;

        -- FIX 2026-09-30: flag ONLY this supplier's original rows. TRN_SEQ_NO is a per-supplier
        -- counter, so matching on it alone also tagged every OTHER supplier's row with the
        -- same sequence number as error-corrected.
        UPDATE L
        SET L.ErrorCorrectTag = 1
        FROM SupplierLedger L
        INNER JOIN #OrigLedgerRows o
                ON o.TRN_SEQ_NO  = L.TRN_SEQ_NO
               AND o.SupplierKey = L.SupplierKey;

        -- FIX: dbo.func_getLastID(SupplierID) computes MAX(TRN_SEQ_NO)+1.
        -- Called inline per-row inside a multi-row INSERT...SELECT (below),
        -- it can't see sibling rows being built in the SAME statement -
        -- every row in the batch would get the SAME (duplicate) TRN_SEQ_NO,
        -- which then breaks the ledger trigger's JOIN (ambiguous match on
        -- a non-unique key), corrupting Beginning/EndingBalance for BOTH
        -- rows. Call it ONCE here, then assign strictly increasing values
        -- across the batch via ROW_NUMBER() - same fix pattern already
        -- used in sp_PostExpense's @baseSeq + ROW_NUMBER() ExpenseMaster
        -- insert.
        DECLARE @baseTrnSeq INT = dbo.func_getLastID(@supplierkey);

        INSERT INTO [dbo].[SupplierLedger]
            (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate,
             Description, TransCode, TransactionDate, ReferenceNumber,
             ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance,
             TransactedBy, ApprovedBy, TotalAmount, PaymentType,
             ErrorCorrectTag, TicketReference, BatchReferenceID)
        SELECT
            @baseTrnSeq + ROW_NUMBER() OVER (ORDER BY o.TRN_SEQ_NO) - 1,
            o.SupplierKey, o.SupplierID,
            GETDATE(), '(REVERSAL) ' + ISNULL(o.Description,''), o.TransCode,
            GETDATE(), @parmrefno, o.ReferenceKey, o.InvoiceNo,
            0, o.Credit, 0, 0,
            @parmuser, '*', o.TotalAmount, 'REVERSAL',
            1, o.NewTicket, o.BatchReferenceID
        FROM #OrigLedgerRows o;

        DROP TABLE #TicketMap;
        DROP TABLE #OrigLedgerRows;

        -- ── Undo the EWT-at-accrual effect (if any) so re-approval starts
        --    from the pre-approval balance ──
        DECLARE @ewtPostedAtThisApproval DECIMAL(18,2);
        SELECT @ewtPostedAtThisApproval = ISNULL(SUM(EWTAmount), 0)
        FROM ExpenseMaster
        WHERE SupplierID       = @supplierkey
          AND BatchReferenceID = @parmbatchrefno
          AND InvoiceNo        = @parminvoiceno
          AND IsEWTPostedAtAccrual = 1;

        UPDATE ExpenseSummary
        SET Balance         = ISNULL(Balance, 0) + @ewtPostedAtThisApproval,
            EWTWithheld     = 0,
            Status          = 'CANCELLED',
            UpdatedBy       = @parmuser,
            DateTimeUpdated = GETDATE()
        WHERE SupplierID       = @parmsupplierid
          AND ReferenceNumber  = @parmrefno
          AND InvoiceNo        = @parminvoiceno;

        UPDATE ExpenseMaster
        SET IsEWTPostedAtAccrual = 0,
            Status               = 'CANCELLED'
        WHERE SupplierID       = @supplierkey
          AND BatchReferenceID = @parmbatchrefno
          AND InvoiceNo        = @parminvoiceno;

        INSERT INTO ExpenseApprovalReversalAudit
            (ReferenceNumber, InvoiceNo, SupplierID, Reason, ReversedBy, ReversedDate)
        VALUES
            (@parmrefno, @parminvoiceno, @parmsupplierid, @parmreason, @parmuser, GETDATE());

        COMMIT TRAN;

        SELECT 1 AS Status, 'Expense approval reversed - status returned to FOR APPROVAL.' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH;
END;

GO
