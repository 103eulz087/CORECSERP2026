/* ================================================================
   2026-10-08e: Bank Recon - an item already cleared is never moved silently
   ================================================================
   Follow-up to 2026-10-08c (needs it), from the sp-reviewer / ui-form-reviewer
   passes of 2026-10-08.

   In 08c, ticking an item on an earlier month's screen that had been cleared in a
   LATER month (it shows as open there, "Cleared In: Sep 2026 (later)") moved its
   clearing month back without a word; Select All / a batch tick could pull every
   September clearing back into August. Now:
     * sp_BankRecon_ResolveItem refuses it (93013: "cleared in <month>; open that
       period and mark it uncleared first");
     * sp_BankRecon_BulkResolveItems leaves every already-cleared item as it is
       (the count it returns doesn't include them).
   Also: with no @PeriodEnd (older exe) the clearing month is the item's own period
   as stored, not its EOMONTH (no difference today: every header is a month end).
   Same parameters. Backups _OLD_10082026220000. One transaction with a post-check.
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
    DECLARE @old SYSNAME = @Obj + N'_OLD_10082026220000', @full NVARCHAR(300) = N'dbo.' + @Obj;
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
IF COL_LENGTH('dbo.BankStatementRecon', 'ClearedPeriodEnd') IS NULL
   OR OBJECT_ID('dbo.sp_BankRecon_ResolveItem_OLD_10082026220000', 'P') IS NOT NULL
BEGIN
    RAISERROR('Run 2026-10-08c first, and run this script only once.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
INSERT INTO #Patch (Obj, OldText, NewText) VALUES
(N'sp_BankRecon_ResolveItem',
 N'    DECLARE @P DATE = EOMONTH(ISNULL(@PeriodEnd, @OwnPeriod));',
 N'    DECLARE @P DATE = CASE WHEN @PeriodEnd IS NULL THEN @OwnPeriod ELSE EOMONTH(@PeriodEnd) END;   -- 2026-10-08e: older exe = the own period as stored'),
(N'sp_BankRecon_ResolveItem',
 N'    IF @IsResolved = 0 AND @PeriodEnd IS NOT NULL AND @Cleared <> @P',
 N'    -- 2026-10-08e: an item cleared in a later month is not moved silently; unclear it in that month first
    IF @IsResolved = 1 AND @WasResolved = 1 AND @Cleared > @P
    BEGIN
        SET @msg = N''This item was cleared in the '' + CONVERT(NVARCHAR(10), @Cleared, 120) + N'' period. Open that period and mark it uncleared first.'';
        THROW 93013, @msg, 1;
    END

    IF @IsResolved = 0 AND @PeriodEnd IS NOT NULL AND @Cleared <> @P'),

(N'sp_BankRecon_BulkResolveItems',
 N'    month are touched (an item cleared in a later month moves to this month).',
 N'    month and not cleared in any month are touched (2026-10-08e: an item cleared in a later
    month is left as it is; it is not counted).'),
(N'sp_BankRecon_BulkResolveItems',
 N'               EOMONTH(ISNULL(@PeriodEnd, H.PeriodEnd)) AS P,',
 N'               CASE WHEN @PeriodEnd IS NULL THEN H.PeriodEnd ELSE EOMONTH(@PeriodEnd) END AS P,   -- 2026-10-08e'),
(N'sp_BankRecon_BulkResolveItems',
 N'        DELETE FROM #Sel WHERE OldCleared <= P;   -- already cleared as of that month: nothing to do',
 N'        DELETE FROM #Sel WHERE OldCleared < ''9999-12-31'';   -- 2026-10-08e: already cleared in any month: left as is (no silent move)'),

(N'sp_BankRecon_ResolveAutoDebitItem',
 N'    DECLARE @P DATE = EOMONTH(ISNULL(@PeriodEnd, @OwnPeriod));',
 N'    DECLARE @P DATE = CASE WHEN @PeriodEnd IS NULL THEN @OwnPeriod ELSE EOMONTH(@PeriodEnd) END;   -- 2026-10-08e');
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'sp_BankRecon_ResolveItem';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'sp_BankRecon_BulkResolveItems';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'sp_BankRecon_ResolveAutoDebitItem';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_BankRecon_ResolveItem')) NOT LIKE '%93013%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_BankRecon_BulkResolveItems')) NOT LIKE '%2026-10-08e%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_BankRecon_ResolveAutoDebitItem')) NOT LIKE '%2026-10-08e%'
BEGIN
    RAISERROR('Post-check failed; rolled back.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
COMMIT TRANSACTION;
PRINT 'Bank Recon: no silent move of cleared items (backups _OLD_10082026220000).';
GO
SET NOEXEC OFF;
GO
