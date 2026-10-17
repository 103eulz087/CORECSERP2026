/* ================================================================
   [100] 2026-10-16  Each user's DevExpress skin (theme), remembered per account
   ================================================================
   User (2026-10-16): users pick a skin from the ribbon gallery (Main), and after
   logging out and opening the app again they have to pick it again. Save the pick
   on their user account so it applies when they log in, on any PC.
   User decision: every database remembers its own picks (PRODUCTION, STAGING and
   DEV each keep theirs). A user with no saved pick keeps the app's default:
   WXI Compact on PRODUCTION, Black on any other database (Program.cs).

   New objects only (nothing existing is changed; no backup needed):
     - table dbo.UserUIPreference: one row per UserID (= Users.UserID), the skin
       name and its palette (blank = the skin's default palette), who / when;
     - dbo.sp_UserUIPreference_Get @UserID: the saved skin + palette (no row = none);
     - dbo.spu_UserUIPreference_Save @UserID, @SkinName, @PaletteName: insert or
       update the user's row; refused 59731 for an unknown user, 59732 for a blank
       skin name. Only the exe's ribbon skin gallery calls it.
   Callers: Classes/UserSkinPreference.cs (Login, Main).
   Re-runnable: each object is created only when missing. Read / write of display
   preferences only; no posting, no GL.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[100] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.Users', 'U') IS NULL
BEGIN
    RAISERROR('[100] stopped: dbo.Users does not exist in this database; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[100] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
GO

IF OBJECT_ID('dbo.UserUIPreference', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserUIPreference
    (
        UserID       VARCHAR(50)  NOT NULL CONSTRAINT PK_UserUIPreference PRIMARY KEY,
        SkinName     VARCHAR(100) NOT NULL,
        PaletteName  VARCHAR(100) NULL,
        ModifiedDate DATETIME     NOT NULL CONSTRAINT DF_UserUIPreference_ModifiedDate DEFAULT (GETDATE()),
        ModifiedHost VARCHAR(128) NULL
    );
    PRINT '[100] table dbo.UserUIPreference created.';
END
ELSE
    PRINT '[100] table dbo.UserUIPreference already there.';
GO

IF OBJECT_ID('dbo.sp_UserUIPreference_Get', 'P') IS NULL
EXEC ('
CREATE PROCEDURE dbo.sp_UserUIPreference_Get
    @UserID VARCHAR(50)
AS
/*
    [100] 2026-10-16: the user''s saved skin + palette; no row = nothing saved (the app keeps its default).
    Callers: Classes/UserSkinPreference.cs (after a successful login).
*/
BEGIN
    SET NOCOUNT ON;
    SELECT p.SkinName,
           ISNULL(p.PaletteName, '''') AS PaletteName
    FROM dbo.UserUIPreference AS p
    WHERE p.UserID = LTRIM(RTRIM(@UserID));
END;');
GO

IF OBJECT_ID('dbo.spu_UserUIPreference_Save', 'P') IS NULL
EXEC ('
CREATE PROCEDURE dbo.spu_UserUIPreference_Save
    @UserID      VARCHAR(50),
    @SkinName    VARCHAR(100),
    @PaletteName VARCHAR(100) = NULL
AS
/*
    [100] 2026-10-16: remembers the skin a user picked in the ribbon gallery (insert or update their row).
    59731 unknown user, 59732 blank skin name.
    Callers: Classes/UserSkinPreference.cs (Main, ribbon skin gallery click).
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @uid VARCHAR(50) = LTRIM(RTRIM(@UserID));
        DECLARE @skin VARCHAR(100) = NULLIF(LTRIM(RTRIM(@SkinName)), '''');
        DECLARE @palette VARCHAR(100) = NULLIF(LTRIM(RTRIM(@PaletteName)), '''');

        IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE UserID = @uid)
            THROW 59731, ''Unknown user: the skin was not saved.'', 1;
        IF @skin IS NULL
            THROW 59732, ''No skin name given: nothing saved.'', 1;

        UPDATE dbo.UserUIPreference WITH (UPDLOCK, SERIALIZABLE)
        SET SkinName = @skin,
            PaletteName = @palette,
            ModifiedDate = GETDATE(),
            ModifiedHost = LEFT(HOST_NAME(), 128)
        WHERE UserID = @uid;

        IF @@ROWCOUNT = 0
            INSERT INTO dbo.UserUIPreference (UserID, SkinName, PaletteName, ModifiedDate, ModifiedHost)
            VALUES (@uid, @skin, @palette, GETDATE(), LEFT(HOST_NAME(), 128));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;');
GO

DECLARE @msg NVARCHAR(400);
IF OBJECT_ID('dbo.UserUIPreference', 'U') IS NULL
    SET @msg = N'[100] post-check failed: table dbo.UserUIPreference is missing.';
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_UserUIPreference_Get')) NOT LIKE N'%[[]100]%'
    SET @msg = N'[100] post-check failed: dbo.sp_UserUIPreference_Get is not the [100] text.';
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.spu_UserUIPreference_Save')) NOT LIKE N'%[[]100]%'
    SET @msg = N'[100] post-check failed: dbo.spu_UserUIPreference_Save is not the [100] text.';
IF @msg IS NOT NULL
    RAISERROR(@msg, 16, 1);
ELSE
    PRINT '[100] done: dbo.UserUIPreference, dbo.sp_UserUIPreference_Get, dbo.spu_UserUIPreference_Save.';
GO
SET NOEXEC OFF;
GO
