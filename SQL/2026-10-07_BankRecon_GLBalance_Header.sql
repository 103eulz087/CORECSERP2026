/* ================================================================
   2026-10-07: Bank Recon -- right header, GL ending balance, one set of figures
   ================================================================
   AccountingDevEx/BankReconFormV2. Bugs found on DEV (2026-10-07):
     1. sp_BankRecon_GetPeriod's header query returned EVERY header up to the
        picked period (no order); the form took the first row, so picking
        September worked on July's header (101020101) -- Save, the figures and
        Lock all hit the wrong month. A month with no header reused an older one.
     2. GL Book Balance was the month's NET MOVEMENT (tickets inside the month),
        while the bank statement balance is an ENDING balance: they could never
        agree (101020107 Aug: 1,633,317.18 shown vs 5,240,580.42 GL balance).
     3. It was computed only on Save (a new month showed 0.00; later postings
        were left out), and only for the header's own branch.
     4. Lock's "difference must be 0" check used that stored figure, only the
        month's own DIT / OC (not open items carried from earlier months) and no
        bank-side items -- not the formula the screen shows.

   User decisions (2026-10-07):
     * GL Book Balance = the bank GL account's CUMULATIVE balance at period end
       (opening balance + every posting dated on or before PeriodEnd).
     * ALL branches' postings to the account count (one bank account, one statement).

   Now:
     dbo.fn_BankRecon_GLBalance (NEW)  the GL balance, same rule as
         sp_rpt_TrialBalanceRealTime (TicketDate < PeriodEnd + 1 day, no status filter).
     dbo.fn_BankRecon_Figures (NEW)    every figure of one header, the screen's formula:
         Adjusted Bank = Bank Statement + open DIT - open OC
         Adjusted Book = GL Book Balance + open BCM - open BDM / BC / NSF / ADB
         Difference    = Adjusted Bank - Adjusted Book
         Open items = uncleared, from this header and every earlier header of the
         same branch + account (carried forward), reversed / voided left out.
         GL Book Balance is LIVE while the period is open, the stored snapshot once LOCKED.
     sp_BankRecon_GetPeriod   header = exactly @PeriodEnd (the form creates a missing
                              one); GLBookBalance / Adjusted / Difference from the function.
                              Patched by exact anchors; item queries unchanged.
     sp_BankRecon_SaveHeader  stores the bank balance + a GL snapshot; same parameters.
     sp_BankRecon_LockPeriod  checks the function's Difference; stores the GL snapshot it
                              locks with; same parameters and error numbers (93004 / 93005).

   No table changes. Backups: _OLD_10072026120000. One transaction; the last
   batch commits only if every object exists and uses the new functions.
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
    DECLARE @old SYSNAME = @Obj + N'_OLD_10072026120000', @full NVARCHAR(300) = N'dbo.' + @Obj;
    EXEC sp_rename @full, @old;
    EXEC (@def);
    IF OBJECT_ID(@full) IS NULL
    BEGIN
        SET @msg = @Obj + N' was not recreated.';
        THROW 59962, @msg, 1;
    END
END
GO

------------------------------------------------------------------
-- 1. GL balance of a bank account at period end
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE FUNCTION dbo.fn_BankRecon_GLBalance (@AccountCode VARCHAR(20), @PeriodEnd DATE)
RETURNS TABLE
AS
/*
    Cumulative GL balance (Debit - Credit) of @AccountCode on @PeriodEnd: the
    opening balance plus every posting dated on or before that day, all
    branches (user, 2026-10-07). Same date / status rule as sp_rpt_TrialBalanceRealTime.
*/
RETURN
    SELECT CAST(ISNULL(SUM(ISNULL(td.Debit, 0) - ISNULL(td.Credit, 0)), 0) AS DECIMAL(18,2)) AS GLBalance
    FROM dbo.TicketDetails AS td
    WHERE td.AccountCode = @AccountCode
      AND td.TicketDate < DATEADD(DAY, 1, CAST(@PeriodEnd AS DATETIME));
GO

------------------------------------------------------------------
-- 2. All figures of one header (the screen's formula)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE FUNCTION dbo.fn_BankRecon_Figures (@HeaderID INT)
RETURNS TABLE
AS
/*
    The reconciliation of one header, exactly as BankReconFormV2 shows it:
      Adjusted Bank = BankStatementBal + open DIT - open OC
      Adjusted Book = GLBookBalance + open BCM - open BDM / BC / NSF / ADB
      Difference    = Adjusted Bank - Adjusted Book   (0 = reconciled)
    Open = not cleared, from this header and every earlier one of the same
    branch + account (items carry forward until cleared), reversed / voided out.
    GLBookBalance: live (fn_BankRecon_GLBalance) while open, the stored snapshot once LOCKED.
*/
RETURN
    SELECT
        H.HeaderID,
        f.GLBookBalance,
        f.BankStatementBal,
        o.OpenDIT, o.OpenOC, o.OpenBCM, o.OpenBankDebits,
        CAST(f.BankStatementBal + o.OpenDIT - o.OpenOC AS DECIMAL(18,2))                         AS AdjustedBankBalance,
        CAST(f.GLBookBalance + o.OpenBCM - o.OpenBankDebits AS DECIMAL(18,2))                     AS AdjustedBookBalance,
        CAST((f.BankStatementBal + o.OpenDIT - o.OpenOC) - (f.GLBookBalance + o.OpenBCM - o.OpenBankDebits) AS DECIMAL(18,2)) AS Difference
    FROM dbo.BankReconHeader AS H
    CROSS APPLY dbo.fn_BankRecon_GLBalance(H.AccountCode, H.PeriodEnd) AS gl
    CROSS APPLY (SELECT CAST(CASE WHEN H.Status = 'LOCKED' THEN ISNULL(H.GLBookBalance, 0) ELSE gl.GLBalance END AS DECIMAL(18,2)) AS GLBookBalance,
                        CAST(ISNULL(H.BankStatementBal, 0) AS DECIMAL(18,2)) AS BankStatementBal) AS f
    CROSS APPLY (SELECT
                     CAST(ISNULL(SUM(CASE WHEN B.ItemType = 'DIT' THEN B.Amount END), 0) AS DECIMAL(18,2)) AS OpenDIT,
                     CAST(ISNULL(SUM(CASE WHEN B.ItemType = 'OC'  THEN B.Amount END), 0) AS DECIMAL(18,2)) AS OpenOC,
                     CAST(ISNULL(SUM(CASE WHEN B.ItemType = 'BCM' THEN B.Amount END), 0) AS DECIMAL(18,2)) AS OpenBCM,
                     CAST(ISNULL(SUM(CASE WHEN B.ItemType IN ('BDM', 'BC', 'NSF', 'ADB') THEN B.Amount END), 0) AS DECIMAL(18,2)) AS OpenBankDebits
                 FROM dbo.BankStatementRecon AS B
                 INNER JOIN dbo.BankReconHeader AS HX ON HX.HeaderID = B.HeaderID
                 WHERE HX.BranchCode = H.BranchCode AND HX.AccountCode = H.AccountCode AND HX.PeriodEnd <= H.PeriodEnd
                   AND ISNULL(B.IsResolved, 0) = 0
                   AND ISNULL(B.ResolvedReason, '') <> 'REVERSED' AND ISNULL(B.ResolvedReason, '') NOT LIKE 'VOIDED%') AS o
    WHERE H.HeaderID = @HeaderID;
GO

------------------------------------------------------------------
-- 3. sp_BankRecon_GetPeriod: this month's header, figures from the function
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
INSERT #Patch (Obj, OldText, NewText) VALUES
(N'sp_BankRecon_GetPeriod',
 N'        H.PeriodEnd, H.BankStatementBal, H.GLBookBalance, H.Status, H.Remarks,',
 N'        H.PeriodEnd, H.BankStatementBal, fig.GLBookBalance, H.Status, H.Remarks,   -- 2026-10-07: GL ending balance (live while open)'),
(N'sp_BankRecon_GetPeriod',
 N'        H.BankStatementBal + ISNULL(DIT.TotalDIT, 0) - ISNULL(OC.TotalOC, 0) AS AdjustedBankBalance,
        H.GLBookBalance - (H.BankStatementBal + ISNULL(DIT.TotalDIT, 0) - ISNULL(OC.TotalOC, 0)) AS Difference,
        CASE WHEN H.GLBookBalance = (H.BankStatementBal + ISNULL(DIT.TotalDIT, 0) - ISNULL(OC.TotalOC, 0))
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsReconciled',
 N'        fig.AdjustedBankBalance, fig.AdjustedBookBalance, fig.Difference,
        fig.OpenDIT, fig.OpenOC, fig.OpenBCM, fig.OpenBankDebits,
        CASE WHEN fig.Difference = 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsReconciled'),
(N'sp_BankRecon_GetPeriod',
 N'    LEFT JOIN dbo.ChartOfAccounts AS CA ON CA.AccountCode = H.AccountCode',
 N'    LEFT JOIN dbo.ChartOfAccounts AS CA ON CA.AccountCode = H.AccountCode
    OUTER APPLY dbo.fn_BankRecon_Figures(H.HeaderID) AS fig'),
(N'sp_BankRecon_GetPeriod',
 N'    WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd <= @PeriodEnd;',
 N'    WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd = @PeriodEnd;   -- 2026-10-07: this month''s header only (was <=, the form took an older one)');
EXEC #ApplyPatch N'sp_BankRecon_GetPeriod';
GO

------------------------------------------------------------------
-- 4. sp_BankRecon_SaveHeader (same parameters)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC sp_rename 'dbo.sp_BankRecon_SaveHeader', 'sp_BankRecon_SaveHeader_OLD_10072026120000';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE PROCEDURE dbo.sp_BankRecon_SaveHeader
    @HeaderID         INT,
    @BankStatementBal DECIMAL(18,2),
    @Remarks          VARCHAR(500),
    @UpdatedBy        VARCHAR(50)
AS
/*
    Saves the bank statement ending balance of an open period and a snapshot of
    the GL ending balance (fn_BankRecon_GLBalance: cumulative, all branches).
    The screen itself always shows the live GL balance while the period is open.
    2026-10-07: was the month's net movement, own branch only.
*/
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM dbo.BankReconHeader WHERE HeaderID = @HeaderID AND Status = 'LOCKED')
        THROW 93001, 'This period is locked and cannot be edited.', 1;

    DECLARE @GLBal DECIMAL(18,2);
    SELECT @GLBal = gl.GLBalance
    FROM dbo.BankReconHeader AS H
    CROSS APPLY dbo.fn_BankRecon_GLBalance(H.AccountCode, H.PeriodEnd) AS gl
    WHERE H.HeaderID = @HeaderID;

    UPDATE dbo.BankReconHeader
    SET BankStatementBal = @BankStatementBal,
        GLBookBalance    = ISNULL(@GLBal, 0),
        Remarks          = @Remarks,
        LastUpdatedBy    = @UpdatedBy,
        LastUpdatedDate  = GETDATE()
    WHERE HeaderID = @HeaderID;

    -- updated header for the form
    SELECT H.HeaderID, H.BranchCode, H.AccountCode, CA.Description AS AccountName, H.PeriodEnd,
           H.BankStatementBal, fig.GLBookBalance, H.Status, H.Remarks,
           fig.OpenDIT AS TotalDIT, fig.OpenOC AS TotalOC,
           fig.AdjustedBankBalance, fig.AdjustedBookBalance, fig.Difference
    FROM dbo.BankReconHeader AS H
    LEFT JOIN dbo.ChartOfAccounts AS CA ON CA.AccountCode = H.AccountCode
    OUTER APPLY dbo.fn_BankRecon_Figures(H.HeaderID) AS fig
    WHERE H.HeaderID = @HeaderID;
END
GO

------------------------------------------------------------------
-- 5. sp_BankRecon_LockPeriod (same parameters / errors)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC sp_rename 'dbo.sp_BankRecon_LockPeriod', 'sp_BankRecon_LockPeriod_OLD_10072026120000';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE PROCEDURE dbo.sp_BankRecon_LockPeriod
    @HeaderID   INT,
    @LockedBy   VARCHAR(50),
    @StrictMode BIT = 1   -- 1 = must be fully reconciled to lock
AS
/*
    Locks a reconciled period. Strict mode checks the same Difference the screen
    shows (fn_BankRecon_Figures: open items carried forward, bank-side items, live
    GL ending balance). The GL balance it locks with is stored, so a locked period
    keeps its figures even if the GL changes later.
    2026-10-07: checked a stale stored GL figure, this month's DIT / OC only, no bank-side items.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

    DECLARE @Status VARCHAR(20);
    SELECT @Status = Status FROM dbo.BankReconHeader WITH (UPDLOCK, HOLDLOCK) WHERE HeaderID = @HeaderID;
    IF @Status = 'LOCKED'
        THROW 93004, 'Period is already locked.', 1;

    DECLARE @Diff DECIMAL(18,2), @GL DECIMAL(18,2);
    SELECT @Diff = fig.Difference, @GL = fig.GLBookBalance
    FROM dbo.fn_BankRecon_Figures(@HeaderID) AS fig;

    IF @StrictMode = 1 AND ISNULL(@Diff, 0) <> 0
        THROW 93005, 'Cannot lock: reconciliation difference is not zero. Resolve all outstanding items first.', 1;

    UPDATE dbo.BankReconHeader
    SET Status        = 'LOCKED',
        GLBookBalance = ISNULL(@GL, GLBookBalance),   -- the figure it was locked with
        LockedBy      = @LockedBy,
        LockedDate    = GETDATE()
    WHERE HeaderID = @HeaderID;

    COMMIT TRANSACTION;
END
GO

------------------------------------------------------------------
-- 6. Commit only if everything is in place
------------------------------------------------------------------
IF @@TRANCOUNT = 0
    RAISERROR('An earlier step failed and its transaction was rolled back; nothing was changed.', 16, 1);
ELSE IF OBJECT_ID('dbo.fn_BankRecon_GLBalance', 'IF') IS NULL OR OBJECT_ID('dbo.fn_BankRecon_Figures', 'IF') IS NULL
     OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_BankRecon_GetPeriod'))   NOT LIKE '%fn_BankRecon_Figures%'
     OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_BankRecon_SaveHeader'))  NOT LIKE '%fn_BankRecon_GLBalance%'
     OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_BankRecon_LockPeriod'))  NOT LIKE '%fn_BankRecon_Figures%'
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('NOT APPLIED: an object is missing or still on the old version; everything was rolled back.', 16, 1);
END
ELSE
BEGIN
    COMMIT TRANSACTION;
    PRINT 'Applied.';
END
GO
SET NOEXEC OFF;
GO
