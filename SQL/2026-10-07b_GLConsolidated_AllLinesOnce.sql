/* ================================================================
   2026-10-07b: GL Consolidated report -- every ticket line once, reversals included
   ================================================================
   sp_rpt_GeneralLedger_WithRunningBal (AccountingReportsForm / V2 "GL Consolidated").
   Found 2026-10-07 while checking Bank Recon's GL Book Balance (101020101 Aug:
   STAGING report -15,779,218.29 vs recon / ledger -15,933,885.11; DEV gap -76,676.62):

     1. It dropped tickets with Status 'REVERSED'. That status is on the REVERSAL
        entry (e.g. ticket 13803 "REVERSAL: OR-DISC ENTRY"); the original OR ticket
        it cancels stays 'UPDATED'. So a reversed client payment kept counting.
        (Statuses in use: POSTED / UPDATED / REVERSED; no VOID / CANCELLED.)
     2. It joined lines to TicketMaster on TicketNumber + ReferenceNumber, without
        BranchCode. A cross-branch manual JV has one master per branch with the same
        number + reference, so its lines counted once per master (JV 14607, 14612).
        A line with no matching master was dropped.

   Now amounts come from TicketDetails alone (each line once, every status), the
   same rule as sp_rpt_TrialBalanceRealTime and the Bank Recon GL balance; the
   master only supplies the reference / particulars (same branch first). So the
   ending balance = Trial Balance (Real-Time) = Bank Recon GL Book Balance.
   Parameters and result columns unchanged. Backup: _OLD_10072026150000.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
BEGIN TRANSACTION;
CREATE TABLE #Patch (Id INT IDENTITY PRIMARY KEY, Obj SYSNAME NOT NULL, OldText NVARCHAR(MAX) NOT NULL, NewText NVARCHAR(MAX) NOT NULL);
GO

CREATE PROCEDURE #ApplyPatch @Obj SYSNAME
AS
BEGIN
    DECLARE @def NVARCHAR(MAX) = REPLACE(OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + @Obj)), NCHAR(13) + NCHAR(10), NCHAR(10));
    DECLARE @msg NVARCHAR(400);
    IF @def IS NULL
    BEGIN
        SET @msg = N'Cannot read the definition of ' + @Obj + N'; nothing changed.';
        THROW 59963, @msg, 1;
    END
    IF EXISTS (SELECT 1 FROM #Patch WHERE Obj = @Obj
               AND (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, OldText, N''))) / DATALENGTH(OldText) <> 1)
    BEGIN
        SET @msg = @Obj + N' text differs from the expected version (an anchor is missing or repeated); nothing changed.';
        THROW 59964, @msg, 1;
    END
    DECLARE @o NVARCHAR(MAX), @n NVARCHAR(MAX);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT OldText, NewText FROM #Patch WHERE Obj = @Obj ORDER BY Id;
    OPEN c; FETCH NEXT FROM c INTO @o, @n;
    WHILE @@FETCH_STATUS = 0 BEGIN SET @def = REPLACE(@def, @o, @n); FETCH NEXT FROM c INTO @o, @n; END
    CLOSE c; DEALLOCATE c;
    DECLARE @old SYSNAME = @Obj + N'_OLD_10072026150000', @full NVARCHAR(300) = N'dbo.' + @Obj;
    EXEC sp_rename @full, @old;
    EXEC (@def);
    IF OBJECT_ID(@full) IS NULL
    BEGIN
        SET @msg = @Obj + N' was not recreated.';
        THROW 59965, @msg, 1;
    END
END
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
INSERT #Patch (Obj, OldText, NewText) VALUES
-- beginning balance: every line once, every status
(N'sp_rpt_GeneralLedger_WithRunningBal',
 N'    FROM TicketDetails TD
    JOIN TicketMaster  TM ON TD.TicketNumber    = TM.TicketNumber
                          AND TD.ReferenceNumber = TM.ReferenceNumber
    WHERE CAST(TD.TicketDate AS DATE) < @DateFrom
      AND TM.Status NOT IN (''VOID'',''CANCELLED'',''REVERSED'')
      AND (@BranchCode IS NULL OR TD.BranchCode = @BranchCode)
    GROUP BY TD.AccountCode;',
 N'    FROM TicketDetails TD   -- 2026-10-07b: lines alone (no master join, no status filter): each line once, reversals included
    WHERE CAST(TD.TicketDate AS DATE) < @DateFrom
      AND (@BranchCode IS NULL OR TD.BranchCode = @BranchCode)
    GROUP BY TD.AccountCode;'),
-- period transactions: same; the master (same branch first) only gives reference / particulars
(N'sp_rpt_GeneralLedger_WithRunningBal',
 N'           ReferenceNo      = TM.ReferenceNumber,',
 N'           ReferenceNo      = COALESCE(TM.ReferenceNumber, TD.ReferenceNumber),'),
(N'sp_rpt_GeneralLedger_WithRunningBal',
 N'    INTO #Transactions
    FROM TicketDetails TD
    JOIN TicketMaster  TM ON TD.TicketNumber    = TM.TicketNumber
                          AND TD.ReferenceNumber = TM.ReferenceNumber
    WHERE CAST(TD.TicketDate AS DATE) BETWEEN @DateFrom AND @DateTo
      AND TM.Status NOT IN (''VOID'',''CANCELLED'',''REVERSED'')
      AND (@BranchCode IS NULL OR TD.BranchCode = @BranchCode);',
 N'    INTO #Transactions
    FROM TicketDetails TD   -- 2026-10-07b: lines alone (each once, reversals included); master for the description only
    OUTER APPLY (SELECT TOP (1) M.ReferenceNumber, M.Particulars
                 FROM TicketMaster M
                 WHERE M.TicketNumber = TD.TicketNumber
                 ORDER BY CASE WHEN M.BranchCode = TD.BranchCode THEN 0
                               WHEN M.ReferenceNumber = TD.ReferenceNumber THEN 1 ELSE 2 END) TM
    WHERE CAST(TD.TicketDate AS DATE) BETWEEN @DateFrom AND @DateTo
      AND (@BranchCode IS NULL OR TD.BranchCode = @BranchCode);');
EXEC #ApplyPatch N'sp_rpt_GeneralLedger_WithRunningBal';
GO

IF @@TRANCOUNT = 0
    RAISERROR('An earlier step failed and its transaction was rolled back; nothing was changed.', 16, 1);
ELSE IF OBJECT_ID('dbo.sp_rpt_GeneralLedger_WithRunningBal', 'P') IS NULL
     OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_rpt_GeneralLedger_WithRunningBal')) LIKE '%NOT IN (''VOID'',''CANCELLED'',''REVERSED'')%'
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('NOT APPLIED: the report is missing or still on the old version; everything was rolled back.', 16, 1);
END
ELSE
BEGIN
    COMMIT TRANSACTION;
    PRINT 'Applied.';
END
GO
SET NOEXEC OFF;
GO
