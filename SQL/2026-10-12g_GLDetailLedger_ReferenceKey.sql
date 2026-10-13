/* ================================================================
   2026-10-12g - GL Detail Ledger: show the ReferenceKey after PostingDate
   ================================================================
   User 2026-10-12: Accounting Reports (HOFormsDevEx/AccountingReportsFormV2) > GL Detail Ledger should show the
   tickets' ReferenceKey right after PostingDate.

   sp_rpt_GLDetailLedgerRealTime returns one row per day (the day's postings summed, with its TicketNumbers
   listed), so the new column ReferenceKey lists that day's distinct TicketMaster.ReferenceKey values, comma-
   separated and sorted, the same way as TicketNumbers. It is the 2nd column of both the opening row (NULL) and
   the daily rows, so the screen (which shows the result's columns in order) puts it after PostingDate; no exe
   change. Same ticket join as the TicketNumbers / Particulars list. Nothing else changes (amounts, balances,
   summary). Anchor patch; backup sp_rpt_GLDetailLedgerRealTime_OLD_10122026233000.

   One transaction with a post-check. Run on DEV, then STAGING, then PRODUCTION (user).
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
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
        THROW 59960, @msg, 1;
    END
    IF EXISTS (SELECT 1 FROM #Patch WHERE Obj = @Obj
               AND (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, OldText, N''))) / DATALENGTH(OldText) <> 1)
    BEGIN
        SET @msg = @Obj + N' text differs from the expected version (an anchor is missing or repeated); nothing changed.';
        THROW 59961, @msg, 1;
    END
    DECLARE @o NVARCHAR(MAX), @n NVARCHAR(MAX);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT OldText, NewText FROM #Patch WHERE Obj = @Obj ORDER BY Id;
    OPEN c; FETCH NEXT FROM c INTO @o, @n;
    WHILE @@FETCH_STATUS = 0 BEGIN SET @def = REPLACE(@def, @o, @n); FETCH NEXT FROM c INTO @o, @n; END
    CLOSE c; DEALLOCATE c;
    DECLARE @old SYSNAME = @Obj + N'_OLD_10122026233000', @full NVARCHAR(300) = N'dbo.' + @Obj;
    EXEC sp_rename @full, @old;
    EXEC (@def);
    IF OBJECT_ID(@full) IS NULL
    BEGIN
        SET @msg = @Obj + N' was not recreated.';
        THROW 59962, @msg, 1;
    END
END
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
IF OBJECT_ID('dbo.sp_rpt_GLDetailLedgerRealTime_OLD_10122026233000', 'P') IS NOT NULL
BEGIN
    RAISERROR('This script has been run here before (sp_rpt_GLDetailLedgerRealTime_OLD_10122026233000 exists).', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

DECLARE @LF NCHAR(1) = NCHAR(10);
-- opening row: the column, empty
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_rpt_GLDetailLedgerRealTime',
    N'         CAST(@DateFrom AS DATE)        AS PostingDate' + @LF,
    N'         CAST(@DateFrom AS DATE)        AS PostingDate' + @LF +
    N'        ,CAST(NULL AS VARCHAR(MAX))     AS ReferenceKey      -- 2026-10-12g' + @LF);
-- daily rows: the day's reference keys, right after PostingDate
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_rpt_GLDetailLedgerRealTime',
    N'         rb.PostingDate' + @LF +
    N'        ,0                              AS SupplementaryNumber',
    N'         rb.PostingDate' + @LF +
    N'        ,rk.ReferenceKey                                     -- 2026-10-12g: the day''s ReferenceKeys' + @LF +
    N'        ,0                              AS SupplementaryNumber');
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_rpt_GLDetailLedgerRealTime',
    N'    ) tm_agg' + @LF +
    N'    ORDER BY rb.PostingDate;',
    N'    ) tm_agg' + @LF +
    N'    -- 2026-10-12g: the day''s distinct TicketMaster.ReferenceKey values, sorted (same tickets as TicketNumbers)' + @LF +
    N'    OUTER APPLY' + @LF +
    N'    (' + @LF +
    N'        SELECT STRING_AGG(CAST(k.ReferenceKey AS VARCHAR(MAX)), '', '') WITHIN GROUP (ORDER BY k.ReferenceKey) AS ReferenceKey' + @LF +
    N'        FROM' + @LF +
    N'        (' + @LF +
    N'            SELECT DISTINCT LTRIM(RTRIM(tm.ReferenceKey)) AS ReferenceKey' + @LF +
    N'            FROM TicketDetails td' + @LF +
    N'            INNER JOIN TicketMaster tm' + @LF +
    N'                ON  tm.TicketDate          = td.TicketDate' + @LF +
    N'                AND tm.SupplementaryNumber = td.SupplementaryNumber' + @LF +
    N'                AND tm.BranchCode          = td.BranchCode' + @LF +
    N'                AND tm.TicketNumber        = td.TicketNumber' + @LF +
    N'            WHERE (@BranchCode IS NULL OR td.BranchCode = @BranchCode)' + @LF +
    N'              AND td.AccountCode         = @AccountCode' + @LF +
    N'              AND td.TicketDate          = rb.PostingDate' + @LF +
    N'              AND NULLIF(LTRIM(RTRIM(tm.ReferenceKey)), '''') IS NOT NULL' + @LF +
    N'        ) k' + @LF +
    N'    ) rk' + @LF +
    N'    ORDER BY rb.PostingDate;');
EXEC #ApplyPatch N'sp_rpt_GLDetailLedgerRealTime';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

IF OBJECT_ID('dbo.sp_rpt_GLDetailLedgerRealTime', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_rpt_GLDetailLedgerRealTime_OLD_10122026233000', 'P') IS NULL
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_rpt_GLDetailLedgerRealTime')) NOT LIKE '%rk.ReferenceKey%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_rpt_GLDetailLedgerRealTime')) NOT LIKE '%AS ReferenceKey      -- 2026-10-12g%'
BEGIN
    RAISERROR('Post-check failed; rolled back.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
COMMIT TRANSACTION;
PRINT 'GL Detail Ledger: ReferenceKey added after PostingDate.';
GO
SET NOEXEC OFF;
GO
