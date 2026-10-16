/* ================================================================
   [NN] YYYY-MM-DDx  <Short title>
   ================================================================
   User (YYYY-MM-DD): <what was asked, in their words>.
   User decisions: <each decision, dated>.

   RULES
   - <the business rule this script enforces, one per line>

   Measured first (read-only): DEV <…> / STAGING <…> / PRODUCTION <…>.
   Guard: <objects> = their live texts (whitespace-insensitive SHA-256, identical on DEV / STAGING / PRODUCTION
   YYYY-MM-DD). Needs: <earlier scripts>. One transaction with a post-check; backups _OLD_MMddyyyyHHmmss.
   Exe: <old exe keeps working? new exe needs this script?>. Web v2: <anything a second client must know>.
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
    RAISERROR('[NN] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.<PatchedProc>')) LIKE '%[[]NN]%'   -- or: OBJECT_ID('dbo.<NewObject>') IS NOT NULL
BEGIN
    RAISERROR('[NN] already applied in this database; nothing changed.', 10, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.<Prerequisite>') IS NULL
BEGIN
    RAISERROR('[NN] stopped: needs [MM] (<object> missing); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.<PatchedProc>')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '<64-hex hash of the DEV text before this script>'
BEGIN
    RAISERROR('[NN] stopped: <PatchedProc> is not the text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[NN] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
GO

------------------------------------------------------------------
-- 1. New table (re-runnable)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
IF OBJECT_ID('dbo.<NewTable>', 'U') IS NULL
    CREATE TABLE dbo.<NewTable>
    (
        <Id>        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_<NewTable> PRIMARY KEY,
        <Columns>,
        CreatedBy   VARCHAR(100) NOT NULL,
        CreatedDate DATETIME     NOT NULL CONSTRAINT DF_<NewTable>_Date DEFAULT (GETDATE())
    );
GO

------------------------------------------------------------------
-- 2. New proc (full text)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE dbo.<NewProc>
(
    @<Param> VARCHAR(20),
    @User    VARCHAR(100)
)
AS
/*  [NN] YYYY-MM-DD. <what it does, its refusals and their codes>. Error handling per
    docs/standards/2026-10-14_Posting_Proc_Error_Handling.md. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- guards: THROW only
        -- writes
        -- post-check

        COMMIT TRANSACTION;
        SELECT 1 AS Status, '<message>' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

------------------------------------------------------------------
-- 3. Anchor patch of a long live proc
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.<PatchedProc>'));
DECLARE @nl NCHAR(2) = NCHAR(13) + NCHAR(10);
DECLARE @p TABLE (n INT IDENTITY, Anchor NVARCHAR(400), Repl NVARCHAR(MAX));
INSERT INTO @p (Anchor, Repl) VALUES
 (N'<one exact line of the live text>',
  CAST(N'' AS NVARCHAR(MAX)) + N'<new line(s)>   -- [NN]' + @nl
  + N'<one exact line of the live text>');
DECLARE @i INT = 1, @a NVARCHAR(400), @r NVARCHAR(MAX), @cnt INT, @m NVARCHAR(400);
WHILE @i <= (SELECT MAX(n) FROM @p)
BEGIN
    SELECT @a = Anchor, @r = Repl FROM @p WHERE n = @i;
    SET @cnt = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @a, N''))) / DATALENGTH(@a);
    IF @cnt <> 1
    BEGIN
        SET @m = N'[NN] <PatchedProc> anchor ' + CAST(@i AS NVARCHAR(5)) + N' found ' + CAST(@cnt AS NVARCHAR(5)) + N' times.';
        THROW 59898, @m, 1;
    END
    SET @def = REPLACE(@def, @a, @r);
    SET @i += 1;
END
EXEC sp_rename 'dbo.<PatchedProc>', '<PatchedProc>_OLD_MMddyyyyHHmmss';
EXEC (@def);
GO

------------------------------------------------------------------
-- N. Post-check, then commit
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF OBJECT_ID('dbo.<NewProc>', 'P') IS NULL
    SET @msg = N'<NewProc> was not created';
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.<PatchedProc>')) NOT LIKE '%[[]NN]%'
    SET @msg = N'<PatchedProc> is not the [NN] text';
ELSE IF OBJECT_ID('dbo.<PatchedProc>_OLD_MMddyyyyHHmmss', 'P') IS NULL
    SET @msg = N'a backup is missing';

IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[NN] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59897, @msg, 1;
END

COMMIT TRANSACTION;
PRINT '[NN] committed: <summary>.';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
