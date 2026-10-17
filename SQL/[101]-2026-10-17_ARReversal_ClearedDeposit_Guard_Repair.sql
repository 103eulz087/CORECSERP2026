/* ================================================================
   [101] 2026-10-17  AR payment reversal: a deposit already ticked as cleared in Bank Recon
   ================================================================
   User (2026-10-17): the accountant can't balance PNB PESO (101020111) August: "ControlNo. H2608-26-A,
   O-CR 011421 has been doubled on the list" (= O-CR-011241, digits swapped; no CR 011421 exists).
   User decision (2026-10-17): "go ahead build both" = repair the doubled item + stop it from happening again.

   WHAT HAPPENED (PRODUCTION, read-only):
     10-08 15:41  payment ref 38760 (BOHOL BEE FARM, 3,300.00, O-CR-011241, control no. H2608-26-A) -> DIT ReconID 6377
     10-16        the accountant ticks 6377 CLEARED (August)
     10-17 09:31  Client Payments > Edit Payment reverses 38760 (sp_ReversePaymentClient) and re-keys it as 45337
                  -> DIT ReconID 7925, which the accountant also ticks
     sp_ReversePaymentClient voids the payment's deposit only while it is OPEN (IsResolved = 0), so 6377 stayed CLEARED
     for a payment that no longer exists. GL, invoice O-013232 and the client ledger count the 3,300 once; the recon
     list counted it twice: batch H2608-26-A on screen 106,273.45 vs GL 102,973.45.
     The other repeated CR of the batch (O-CR-011234, refs 29297 -> 38798) is right: reversed before the tick, its
     item is REVERSED and hidden.

   RULES
   - An AR payment whose deposit is already ticked as cleared in Bank Recon can't be reversed (93030, names the
     reference, amount, control no. and month). The accountant unticks it first; the reversal then voids it as
     before, and the re-keyed payment's deposit is ticked instead. Same rule as a voucher's cleared cheque (60402).
     The check reads the item WITH (UPDLOCK, HOLDLOCK), so a tick can't slip in between the check and the void
     (same lock order as sp_BankRecon_ResolveItem: recon row, then header). It sits before the first write and
     runs before the 93028 lock check. It matches ReferenceNo AND SourceRef (the index seek; step 12 matches
     SourceRef only): every AR-PAYMENT item has ReferenceNo = SourceRef on DEV / STAGING / PRODUCTION (7,008 /
     7,008 / 7,023 items, 0 differ, 10-17). A zero-amount item never blocks.
   - Repair: a CLEARED AR-PAYMENT deposit of a REVERSED payment (no live payment under that reference) becomes
     ResolvedReason 'REVERSED', exactly what the reversal writes for an open one. IsResolved, ResolvedDate,
     ResolvedBy and ClearedPeriodEnd are kept (they record the old tick). fn_BankRecon_Figures: an item cleared
     in its OWN month gives the same figures before and after (it was not open in any month; a REVERSED one is
     never open), so only the list / summary / batch totals drop the extra line. An item cleared in a LATER month
     also leaves the open list of the months from its own month up to the one before it was cleared (right: the
     reversal ticket is dated like the payment, so the GL nets to 0 there); such rows say so in the Note column.
     An item with a LOCKED month at or after its own is SKIPPED and listed (no locked figure moves). The scan
     holds its rows under UPDLOCK + HOLDLOCK for the short transaction: run it when nobody is ticking.
     Backup table BankRecon_ReversedARCleared_Backup_20261017; UpdatedBy 'REPAIR [101]'.

   Measured first (2026-10-17, read-only): rows the repair would change: DEV 0 / STAGING 0 / PRODUCTION 1
   (ReconID 6377, cleared in its own month); nothing LOCKED on 101020111; no AR item cleared in a later month
   than its own on any tier. sp_ReversePaymentClient = the [88] text, hash 81B60676... on
   DEV / STAGING / PRODUCTION; anchor found once. Same gap, no rows today, NOT changed here: cash-advance reversal
   (sp_ReverseCashAdvanceEntry) and cheque cancel (sp_CancelledChequesCS -> sp_BankRecon_VoidOC) also void open
   items only; BankRecon_GLvsRecon_Check.sql section 7 watches all three.
   Guard: sp_ReversePaymentClient = its live text (whitespace-insensitive SHA-256). Needs: [88].
   One transaction with a post-check; backup sp_ReversePaymentClient_OLD_10172026120000.
   Exe: no change; the old and new exe show the proc's message ("Reversal failed: ..."). Web v2: the same rule
   applies to any client that reverses an AR payment.
   Run in ONE connection with no open transaction.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET LOCK_TIMEOUT 10000;
GO

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[101] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.sp_ReversePaymentClient', 'P') IS NULL
BEGIN
    RAISERROR('[101] stopped: sp_ReversePaymentClient does not exist in this database; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient')) LIKE '%[[]101]%'
BEGIN
    RAISERROR('[101] already applied in this database; nothing changed.', 10, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.sp_ReversePaymentClient_OLD_10172026120000') IS NOT NULL
     OR OBJECT_ID('dbo.BankRecon_ReversedARCleared_Backup_20261017', 'U') IS NOT NULL
BEGIN
    RAISERROR('[101] stopped: its backup proc or backup table already exists; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient')) NOT LIKE '%93028%'
BEGIN
    RAISERROR('[101] stopped: needs [88] (sp_ReversePaymentClient has no 93028 lock check); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '81B606765AF305B3E2F8DCE800DF8619E36C83962500DA439F81E710CAA30343'
BEGIN
    RAISERROR('[101] stopped: sp_ReversePaymentClient is not the text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[101] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
GO

------------------------------------------------------------------
-- 1. Repair: cleared deposits of reversed AR payments -> REVERSED
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
IF OBJECT_ID('tempdb..#Fix101') IS NOT NULL DROP TABLE #Fix101;

SELECT r.ReconID, r.AccountCode, r.BranchCode, r.ReferenceNo, r.Amount, r.ControlNo, r.ResolvedBy,
       CONVERT(VARCHAR(10), hb.PeriodEnd, 120) AS OwnMonth,
       CONVERT(VARCHAR(10), COALESCE(r.ClearedPeriodEnd, hb.PeriodEnd), 120) AS ClearedIn,
       CASE WHEN COALESCE(r.ClearedPeriodEnd, hb.PeriodEnd) > hb.PeriodEnd
            THEN 'cleared in a later month: leaves the open list of ' + CONVERT(VARCHAR(7), hb.PeriodEnd, 120) + ' up to the month before '
                 + CONVERT(VARCHAR(7), r.ClearedPeriodEnd, 120)
            ELSE 'cleared in its own month: figures unchanged' END AS Note,
       CASE WHEN EXISTS (SELECT 1 FROM dbo.BankReconHeader h WITH (HOLDLOCK)
                         WHERE h.BranchCode = hb.BranchCode AND h.AccountCode = hb.AccountCode
                           AND h.Status = 'LOCKED' AND h.PeriodEnd >= hb.PeriodEnd)
            THEN 'SKIPPED (locked month)' ELSE 'FIXED' END AS Result
INTO #Fix101
FROM dbo.BankStatementRecon AS r WITH (UPDLOCK, HOLDLOCK)
INNER JOIN dbo.BankReconHeader AS hb ON hb.HeaderID = r.HeaderID
INNER JOIN dbo.PaymentHeader AS ph ON ph.ReferenceNo = r.SourceRef AND ph.ReferenceNo = r.ReferenceNo
WHERE r.SourceModule = 'AR-PAYMENT' AND r.ItemType = 'DIT'
  AND r.IsResolved = 1
  AND ISNULL(r.ResolvedReason, '') <> 'REVERSED' AND ISNULL(r.ResolvedReason, '') NOT LIKE 'VOIDED%'
  AND ph.Status = 'REVERSED'
  AND NOT EXISTS (SELECT 1 FROM dbo.PaymentHeader AS p2 WHERE p2.ReferenceNo = ph.ReferenceNo AND ISNULL(p2.Status, '') <> 'REVERSED');

SELECT b.*
INTO dbo.BankRecon_ReversedARCleared_Backup_20261017
FROM dbo.BankStatementRecon AS b
WHERE b.ReconID IN (SELECT f.ReconID FROM #Fix101 AS f WHERE f.Result = 'FIXED');

UPDATE b
SET ResolvedReason  = 'REVERSED',
    UpdatedBy       = 'REPAIR [101]',
    DateTimeUpdated = GETDATE(),
    Remarks         = LEFT(LTRIM(ISNULL(b.Remarks, '') + ' [101] 2026-10-17: payment reversed after this deposit was ticked (cleared by '
                      + ISNULL(b.ResolvedBy, '?') + ')'), 500)
FROM dbo.BankStatementRecon AS b
INNER JOIN #Fix101 AS f ON f.ReconID = b.ReconID AND f.Result = 'FIXED';

SELECT * FROM #Fix101 ORDER BY ReconID;
DECLARE @fixed INT = (SELECT COUNT(*) FROM #Fix101 WHERE Result = 'FIXED'),
        @skipped INT = (SELECT COUNT(*) FROM #Fix101 WHERE Result <> 'FIXED');
PRINT '[101] repair: ' + CAST(@fixed AS VARCHAR(10)) + ' item(s) fixed, ' + CAST(@skipped AS VARCHAR(10)) + ' skipped.';
DROP TABLE #Fix101;
GO

------------------------------------------------------------------
-- 2. sp_ReversePaymentClient: refuse a deposit already ticked as cleared (anchor patch)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient'));
DECLARE @nl NCHAR(2) = NCHAR(13) + NCHAR(10);
DECLARE @a NVARCHAR(400) = N'    SET @reversalRef = LEFT(@refno + ''-REV'', 22);';
DECLARE @r NVARCHAR(MAX), @cnt INT, @m NVARCHAR(400);

SET @r = CAST(N'' AS NVARCHAR(MAX)) + @a + @nl
    + @nl
    + N'    -- [101] 2026-10-17: a deposit already ticked as cleared in Bank Recon is refused (93030). The void in step 12 closes' + @nl
    + N'    --       open items only, so a cleared one stayed CLEARED, the re-keyed payment''s deposit was ticked too and the bank side' + @nl
    + N'    --       counted the money twice (PRODUCTION 2026-10-17: O-CR-011241, refs 38760 -> 45337, PNB PESO August).' + @nl
    + N'    --       The accountant unticks it first; the reversal then voids it. UPDLOCK + HOLDLOCK: no tick between this check and step 12.' + @nl
    + N'    --       ReferenceNo + SourceRef: the index seek; every AR-PAYMENT item has ReferenceNo = SourceRef (all tiers, 10-17).' + @nl
    + N'    DECLARE @clearedMsg NVARCHAR(2048), @clearedFound BIT = 0;' + @nl
    + N'    SELECT TOP (1) @clearedFound = 1,' + @nl
    + N'           @clearedMsg = N''Cannot reverse: the deposit of payment '' + ISNULL(@refno, N''?'') + N'' ('' + ISNULL(FORMAT(b.Amount, ''N2''), N''?'')' + @nl
    + N'               + N'', control no. '' + ISNULL(NULLIF(b.ControlNo, ''''), N''-'') + N'') is already ticked as cleared in Bank Recon (month '' + ISNULL(CONVERT(NVARCHAR(7), COALESCE(b.ClearedPeriodEnd, h.PeriodEnd), 120), N''?'')' + @nl
    + N'               + N''). Ask the accountant to untick it first (or reopen that month if it is locked), then reverse; after the payment is entered again, its new deposit is ticked instead.''' + @nl
    + N'    FROM dbo.BankStatementRecon AS b WITH (UPDLOCK, HOLDLOCK)' + @nl
    + N'    LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID' + @nl
    + N'    WHERE b.ReferenceNo = @refno AND b.SourceModule = ''AR-PAYMENT'' AND b.SourceRef = @refno AND b.ItemType = ''DIT''' + @nl
    + N'      AND b.IsResolved = 1 AND b.Amount <> 0' + @nl
    + N'      AND ISNULL(b.ResolvedReason, '''') <> ''REVERSED'' AND ISNULL(b.ResolvedReason, '''') NOT LIKE ''VOIDED%''' + @nl
    + N'    ORDER BY b.ReconID;' + @nl
    + N'    IF @clearedFound = 1' + @nl
    + N'        THROW 93030, @clearedMsg, 1;';

SET @cnt = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @a, N''))) / DATALENGTH(@a);
IF @cnt <> 1
BEGIN
    SET @m = N'[101] sp_ReversePaymentClient anchor found ' + CAST(@cnt AS NVARCHAR(5)) + N' times.';
    THROW 59898, @m, 1;
END
SET @def = REPLACE(@def, @a, @r);

-- marker in the header comment as well
SET @a = N'BEGIN' + NCHAR(10) + N'    SET NOCOUNT ON;';
IF (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @a, N''))) / DATALENGTH(@a) <> 1
    SET @a = N'BEGIN' + @nl + N'    SET NOCOUNT ON;';
SET @cnt = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @a, N''))) / DATALENGTH(@a);
IF @cnt <> 1
BEGIN
    SET @m = N'[101] sp_ReversePaymentClient anchor BEGIN / SET NOCOUNT found ' + CAST(@cnt AS NVARCHAR(5)) + N' times.';
    THROW 59898, @m, 1;
END
SET @def = REPLACE(@def, @a,
      CAST(N'' AS NVARCHAR(MAX)) + N'/*  [101] 2026-10-17: refused (93030) when the payment''s deposit is already ticked as cleared in Bank Recon. */' + @nl + @a);

EXEC sp_rename 'dbo.sp_ReversePaymentClient', 'sp_ReversePaymentClient_OLD_10172026120000';
EXEC (@def);
GO

------------------------------------------------------------------
-- 3. Post-check, then commit
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF OBJECT_ID('dbo.sp_ReversePaymentClient', 'P') IS NULL
    SET @msg = N'sp_ReversePaymentClient is missing';
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient')) NOT LIKE '%THROW 93030%'
     OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient')) NOT LIKE '%[[]101]%'
    SET @msg = N'sp_ReversePaymentClient is not the [101] text';
ELSE IF CHARINDEX('THROW 93030', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient')))
        > CHARINDEX('UPDATE T', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient')))
    SET @msg = N'the 93030 guard is not before the first write of sp_ReversePaymentClient';
ELSE IF OBJECT_ID('dbo.sp_ReversePaymentClient_OLD_10172026120000', 'P') IS NULL
    SET @msg = N'the backup proc is missing';
ELSE IF OBJECT_ID('dbo.BankRecon_ReversedARCleared_Backup_20261017', 'U') IS NULL
    SET @msg = N'the backup table is missing';
ELSE IF (SELECT COUNT(*) FROM dbo.BankRecon_ReversedARCleared_Backup_20261017)
        <> (SELECT COUNT(*) FROM dbo.BankStatementRecon AS b
            INNER JOIN dbo.BankRecon_ReversedARCleared_Backup_20261017 AS k ON k.ReconID = b.ReconID
            WHERE b.ResolvedReason = 'REVERSED' AND b.UpdatedBy = 'REPAIR [101]'
              AND b.IsResolved = k.IsResolved AND b.Amount = k.Amount
              AND ISNULL(b.ClearedPeriodEnd, '19000101') = ISNULL(k.ClearedPeriodEnd, '19000101'))
    SET @msg = N'a repaired item is not as intended';
ELSE IF EXISTS (SELECT 1
                FROM dbo.BankStatementRecon AS r
                INNER JOIN dbo.BankReconHeader AS hb ON hb.HeaderID = r.HeaderID
                INNER JOIN dbo.PaymentHeader AS ph ON ph.ReferenceNo = r.SourceRef AND ph.ReferenceNo = r.ReferenceNo
                WHERE r.SourceModule = 'AR-PAYMENT' AND r.ItemType = 'DIT' AND r.IsResolved = 1
                  AND ISNULL(r.ResolvedReason, '') <> 'REVERSED' AND ISNULL(r.ResolvedReason, '') NOT LIKE 'VOIDED%'
                  AND ph.Status = 'REVERSED'
                  AND NOT EXISTS (SELECT 1 FROM dbo.PaymentHeader AS p2 WHERE p2.ReferenceNo = ph.ReferenceNo AND ISNULL(p2.Status, '') <> 'REVERSED')
                  AND NOT EXISTS (SELECT 1 FROM dbo.BankReconHeader AS h
                                  WHERE h.BranchCode = hb.BranchCode AND h.AccountCode = hb.AccountCode
                                    AND h.Status = 'LOCKED' AND h.PeriodEnd >= hb.PeriodEnd))
    SET @msg = N'a cleared deposit of a reversed payment is still there';

IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[101] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59897, @msg, 1;
END

DECLARE @repaired INT = (SELECT COUNT(*) FROM dbo.BankRecon_ReversedARCleared_Backup_20261017);
COMMIT TRANSACTION;
PRINT '[101] committed: sp_ReversePaymentClient refuses a cleared deposit (93030); '
    + CAST(@repaired AS VARCHAR(10)) + ' cleared deposit(s) of reversed payments repaired.';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
