/* ================================================================
   [95] 2026-10-15i  Account Officers maintenance (Admin Tools › Account Officers)
   ================================================================
   User (2026-10-15): a CRUD screen for dbo.AccountOfficers (the agents shown in
   the customer screens' Account Officer dropdown), under Admin Tools.

   FACTS (PRODUCTION, read-only, 2026-10-15):
   - dbo.AccountOfficers (AccountID VARCHAR(15), AccountOfficerName VARCHAR(50)),
     14 rows, IDs '1'..'14', no primary key, no index, no trigger, no duplicate
     names.
   - The link to a customer is the NAME: Customers.AccountOfficer VARCHAR(50)
     holds AccountOfficerName (CustomersInfoDevEx and CustomersInfoV2DevEx both
     save the name; Leah Banibane alone has 2,961 customers). No other live table
     stores it (CUSTOMER$ / JFCCUSTOMER$$ / Customers_0902 / _0905 / BackupJFC /
     FORLOADING are import or backup copies). No proc reads AccountOfficers.
   RULES (procs below; the screen HOFormsDevEx/AccountOfficersDevEx calls them):
     - name required, trimmed, at most 50 characters; unique (case-insensitive)
     - a new officer gets the next number as AccountID (MAX numeric + 1)
     - a RENAME renames the officer on every customer that has the old name, in
       the same transaction (otherwise those customers lose their agent)
     - a DELETE is refused while customers have the officer (move them first)
     - one applock 'ACCOUNTOFFICERS' serializes the writers
   Error numbers 59710-59716. New objects only; no table change. One
   transaction; re-runnable (existing objects of the same names are renamed to
   _OLD_<run>). Run in ONE connection, no open transaction.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET LOCK_TIMEOUT 10000;
GO

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[95] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.AccountOfficers', 'U') IS NULL OR COL_LENGTH('dbo.AccountOfficers', 'AccountOfficerName') IS NULL
     OR COL_LENGTH('dbo.Customers', 'AccountOfficer') IS NULL
BEGIN
    RAISERROR('[95] stopped: AccountOfficers / Customers.AccountOfficer not found in this database.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[95] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
DECLARE @sfx VARCHAR(30) = '_OLD_' + FORMAT(SYSDATETIME(), 'MMddyyyyHHmmss'), @old SYSNAME;
IF OBJECT_ID('dbo.sp_AccountOfficer_List', 'P') IS NOT NULL
BEGIN SET @old = 'sp_AccountOfficer_List' + @sfx; EXEC sp_rename 'dbo.sp_AccountOfficer_List', @old; END
IF OBJECT_ID('dbo.spu_AccountOfficer_Save', 'P') IS NOT NULL
BEGIN SET @old = 'spu_AccountOfficer_Save' + @sfx; EXEC sp_rename 'dbo.spu_AccountOfficer_Save', @old; END
IF OBJECT_ID('dbo.spu_AccountOfficer_Delete', 'P') IS NOT NULL
BEGIN SET @old = 'spu_AccountOfficer_Delete' + @sfx; EXEC sp_rename 'dbo.spu_AccountOfficer_Delete', @old; END
GO

------------------------------------------------------------------
-- 1. List
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE dbo.sp_AccountOfficer_List
AS
/*
    Returns: one row per account officer: AccountID, AccountOfficerName, Customers (how many customers have the officer,
    matched by name as the customer screens store it), sorted by the numeric ID.
    Caller: HOFormsDevEx/AccountOfficersDevEx. [95] 2026-10-15.
*/
BEGIN
    SET NOCOUNT ON;

    SELECT a.AccountID, a.AccountOfficerName, ISNULL(c.Customers, 0) AS Customers
    FROM dbo.AccountOfficers AS a
    OUTER APPLY (SELECT COUNT(*) AS Customers FROM dbo.Customers AS cu WHERE cu.AccountOfficer = a.AccountOfficerName) AS c
    ORDER BY CASE WHEN TRY_CAST(a.AccountID AS INT) IS NULL THEN 1 ELSE 0 END, TRY_CAST(a.AccountID AS INT), a.AccountID;
END
GO

------------------------------------------------------------------
-- 2. Save (add / rename)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
IF OBJECT_ID('dbo.sp_AccountOfficer_List', 'P') IS NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[95] stopped: sp_AccountOfficer_List was not created; everything rolled back.', 16, 1);
    SET NOEXEC ON;
END
GO
CREATE PROCEDURE dbo.spu_AccountOfficer_Save
    @AccountID   VARCHAR(15) = NULL,   -- NULL / '' = a new officer
    @OfficerName VARCHAR(50),
    @UserID      VARCHAR(50) = NULL
AS
/*
    Adds an account officer (next numeric AccountID) or renames one. A rename also renames the officer on every customer
    that has the old name (Customers.AccountOfficer stores the name). Returns one row: AccountID, AccountOfficerName,
    CustomersUpdated, Action (ADDED / RENAMED / UNCHANGED).
    Refuses: 59710 name required / too long, 59711 another officer has the name, 59713 the officer to rename does not
    exist, 59716 busy. Caller: HOFormsDevEx/AccountOfficersDevEx. [95] 2026-10-15.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Name VARCHAR(100) = LTRIM(RTRIM(ISNULL(@OfficerName, '')));
    DECLARE @Id VARCHAR(15) = NULLIF(LTRIM(RTRIM(ISNULL(@AccountID, ''))), '');
    DECLARE @OldName VARCHAR(50), @Updated INT = 0, @Action VARCHAR(10);

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Lock INT;
        EXEC @Lock = sp_getapplock @Resource = N'ACCOUNTOFFICERS', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
        IF @Lock < 0
            THROW 59716, 'Account officers are being changed by someone else right now. Please try again.', 1;

        IF @Name = ''
            THROW 59710, 'The account officer''s name is required.', 1;
        IF LEN(@Name) > 50
            THROW 59710, 'The account officer''s name can have at most 50 characters.', 1;

        IF EXISTS (SELECT 1 FROM dbo.AccountOfficers
                   WHERE UPPER(LTRIM(RTRIM(AccountOfficerName))) = UPPER(@Name)
                     AND (@Id IS NULL OR ISNULL(AccountID, '') <> @Id))
            THROW 59711, 'Another account officer already has this name.', 1;

        IF @Id IS NULL
        BEGIN
            SELECT @Id = CAST(ISNULL(MAX(TRY_CAST(AccountID AS INT)), 0) + 1 AS VARCHAR(15)) FROM dbo.AccountOfficers;
            INSERT INTO dbo.AccountOfficers (AccountID, AccountOfficerName) VALUES (@Id, @Name);
            SET @Action = 'ADDED';
        END
        ELSE
        BEGIN
            SELECT @OldName = AccountOfficerName FROM dbo.AccountOfficers WHERE AccountID = @Id;
            IF @@ROWCOUNT = 0
                THROW 59713, 'This account officer no longer exists (refresh the list).', 1;

            IF ISNULL(@OldName, '') = @Name
                SET @Action = 'UNCHANGED';
            ELSE
            BEGIN
                UPDATE dbo.AccountOfficers SET AccountOfficerName = @Name WHERE AccountID = @Id;
                -- the customers carry the name: they follow the rename
                UPDATE dbo.Customers SET AccountOfficer = @Name WHERE AccountOfficer = @OldName;
                SET @Updated = @@ROWCOUNT;
                SET @Action = 'RENAMED';
            END
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT @Id AS AccountID, @Name AS AccountOfficerName, @Updated AS CustomersUpdated, @Action AS Action;
END
GO

------------------------------------------------------------------
-- 3. Delete
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
IF OBJECT_ID('dbo.spu_AccountOfficer_Save', 'P') IS NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[95] stopped: spu_AccountOfficer_Save was not created; everything rolled back.', 16, 1);
    SET NOEXEC ON;
END
GO
CREATE PROCEDURE dbo.spu_AccountOfficer_Delete
    @AccountID VARCHAR(15),
    @UserID    VARCHAR(50) = NULL
AS
/*
    Deletes an account officer that no customer has. Refuses: 59713 not found, 59712 customers still have the officer
    (move them to another officer first), 59716 busy. Caller: HOFormsDevEx/AccountOfficersDevEx. [95] 2026-10-15.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Id VARCHAR(15) = LTRIM(RTRIM(ISNULL(@AccountID, ''))), @Name VARCHAR(50), @Count INT, @msg NVARCHAR(300);

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Lock INT;
        EXEC @Lock = sp_getapplock @Resource = N'ACCOUNTOFFICERS', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
        IF @Lock < 0
            THROW 59716, 'Account officers are being changed by someone else right now. Please try again.', 1;

        SELECT @Name = AccountOfficerName FROM dbo.AccountOfficers WHERE AccountID = @Id;
        IF @@ROWCOUNT = 0
            THROW 59713, 'This account officer no longer exists (refresh the list).', 1;

        SELECT @Count = COUNT(*) FROM dbo.Customers WITH (UPDLOCK, HOLDLOCK) WHERE AccountOfficer = @Name;
        IF @Count > 0
        BEGIN
            SET @msg = CONCAT(@Count, ' customer(s) still have ', @Name, ' as account officer. Move them to another officer first.');
            THROW 59712, @msg, 1;
        END

        DELETE FROM dbo.AccountOfficers WHERE AccountID = @Id;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT @Id AS AccountID, @Name AS AccountOfficerName, 'DELETED' AS Action;
END
GO

------------------------------------------------------------------
-- 4. Post-check, then commit
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF OBJECT_ID('dbo.sp_AccountOfficer_List', 'P') IS NULL OR OBJECT_ID('dbo.spu_AccountOfficer_Save', 'P') IS NULL
   OR OBJECT_ID('dbo.spu_AccountOfficer_Delete', 'P') IS NULL
    SET @msg = N'a proc was not created';
IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[95] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59899, @msg, 1;
END
COMMIT TRANSACTION;
PRINT '[95] committed: sp_AccountOfficer_List, spu_AccountOfficer_Save, spu_AccountOfficer_Delete.';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
