/* ================================================================
   [107] 2026-10-17f  Inventory IN > Manual Selection: a Reference Code field
   ================================================================
   User (2026-10-17): "in InventoryIN Manual Entry can you add additional one field for ReferenceCode".
   Screen: ReInventoryIn (Inventory IN), tab "Manual Selection": New -> lines staged in TempInventoryIN by
   sp_StageManualEntryForReInventoryIN -> Save = sp_CommitReInventoryINManualEntry (Inventory rows). Until now every
   lot it created got ReferenceCode 'INVIN-<batch id>' (no field).

   RULES
   - TempInventoryIN.ReferenceCode VARCHAR(100) NULL (new, last column; = Inventory.ReferenceCode's size). Nothing
     inserts into TempInventoryIN without a column list (checked: the stage proc and POSInventoryIN name their columns;
     the upload / analyzer procs only read it).
   - sp_StageManualEntryForReInventoryIN: optional @parmreferencecode VARCHAR(100) = NULL, stored trimmed (blank = NULL).
     An old exe that doesn't send it works as before.
   - sp_CommitReInventoryINManualEntry: Inventory.ReferenceCode = the line's code, else 'INVIN-<batch id>' as before.
   - funcview_InventoryINManualEntry (SELECT * of TempInventoryIN, the tab's grid) is refreshed so it returns the column.
   - The Barcode Scanning tab and the other Inventory IN procs are not changed (not asked).

   Measured first (2026-10-17): the three objects hash-identical on DEV / STAGING / PRODUCTION; TempInventoryIN has
   22 rows (15 not done) on DEV / STAGING, 46 (39) on PRODUCTION; Inventory.ReferenceCode VARCHAR(100).
   Guard: the two procs' live hashes. Backups _OLD_10172026230000. Full recreate from the live text (exact-once patches).
   Exe: the old exe works on it (blank code = INVIN-<batch>); the new exe has the field and sends it.
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
    RAISERROR('[107] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.TempInventoryIN', 'U') IS NULL OR OBJECT_ID('dbo.sp_StageManualEntryForReInventoryIN', 'P') IS NULL
     OR OBJECT_ID('dbo.sp_CommitReInventoryINManualEntry', 'P') IS NULL OR OBJECT_ID('dbo.funcview_InventoryINManualEntry') IS NULL
BEGIN
    RAISERROR('[107] stopped: an Inventory IN manual-entry object is missing; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_StageManualEntryForReInventoryIN')), N'') LIKE '%[[]107]%'
BEGIN
    RAISERROR('[107] already applied in this database; nothing changed.', 10, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.sp_StageManualEntryForReInventoryIN_OLD_10172026230000') IS NOT NULL OR OBJECT_ID('dbo.sp_CommitReInventoryINManualEntry_OLD_10172026230000') IS NOT NULL
BEGIN
    RAISERROR('[107] stopped: a backup _OLD_10172026230000 already exists; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_StageManualEntryForReInventoryIN')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '4D394020F455DCB9826F713E1AD2A32753AB0B45D48B0D99B635DA363F797FA1'
     OR CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CommitReInventoryINManualEntry')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '439CDBF5ADD361B0E8105E8FAC57FDCD35E3BFE3E7CBB2052184274B405019A3'
BEGIN
    RAISERROR('[107] stopped: a manual-entry proc is not the text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[107] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
GO

IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
IF COL_LENGTH('dbo.TempInventoryIN', 'ReferenceCode') IS NULL
    ALTER TABLE dbo.TempInventoryIN ADD ReferenceCode VARCHAR(100) NULL;   -- [107]
GO

IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.sp_StageManualEntryForReInventoryIN', 'sp_StageManualEntryForReInventoryIN_OLD_10172026230000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE   PROCEDURE [dbo].[sp_StageManualEntryForReInventoryIN]
(
    @parmid       INT,
    @parmbranch   VARCHAR(5),
    @parmdatereceived date,
    @parmexpirydate date,
    @parmproductcode varchar(5),
    @parmbarcode  VARCHAR(120),
    @parmqty decimal(12,3),
    @parmcost decimal(12,2),
    @parmiswarehouse bit,
    @parmuser     VARCHAR(50),
    @parmreferencecode VARCHAR(100) = NULL   -- [107] 2026-10-17: the Reference Code typed on the screen (blank = INVIN-<batch> at Save)
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
   
        declare @prodname varchar(250),@isvat bit
        SELECT @prodname=Description,@isvat=isVat FROM Products WHERE BranchCode=@parmbranch and ProductCode=@parmproductcode
        ---------------------------------------------------------------------
        -- Idempotency Check SELECT * FROM TempInventoryIN
        -- If barcode already staged for this document, do nothing.
        ---------------------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM dbo.TempInventoryIN
            WHERE ID = @parmid
              AND Barcode = @parmbarcode
        )
        BEGIN
            COMMIT TRANSACTION;
            RETURN;
        END;

        ---------------------------------------------------------------------
        -- Remove Existing Record (if any)
        ---------------------------------------------------------------------
        DELETE FROM dbo.TempInventoryIN
        WHERE ID = @parmid
          AND Barcode = @parmbarcode;

        ---------------------------------------------------------------------
        -- Insert Staging Record
        ---------------------------------------------------------------------
        ---------------------------------------------------------------------
        -- Create New Re-Inventory Snapshot select * FROM TempInventoryIN
        ---------------------------------------------------------------------
        INSERT INTO dbo.TempInventoryIN
        (
            ID,
            Branch,
            DateReceived,
            ExpiryDate,
            Product,
            Description,
            Barcode,
            Quantity,
            Cost,
            isWarehouse,
            IsVat,
            isDone,
            DateEncode,
            EncodeBy,
            ReferenceCode   -- [107]
        )
        SELECT
            @parmid,
            @parmbranch,
            @parmdatereceived,
            @parmexpirydate,
            @parmproductcode,
            @prodname,
            @parmbarcode,
            @parmqty,
            @parmcost,
            @parmiswarehouse,
            @isvat,
            0,
            GETDATE(),
            @parmuser,
            NULLIF(LTRIM(RTRIM(@parmreferencecode)), '');   -- [107]

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        DECLARE @Msg NVARCHAR(2048);

        SET @Msg = ERROR_MESSAGE();

        RAISERROR(@Msg, 16, 1);
    END CATCH
END;
GO

IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.sp_CommitReInventoryINManualEntry', 'sp_CommitReInventoryINManualEntry_OLD_10172026230000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE   PROCEDURE [dbo].[sp_CommitReInventoryINManualEntry]
(
    @parmid INT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        

        ---------------------------------------------------------------------
        -- Create New Re-Inventory Snapshot SELECT TOP 1 * FROM Inventory SELECT TOP 1 * FROM TempInventoryIN
        ---------------------------------------------------------------------
        INSERT INTO dbo.Inventory
        (
            Branch,
            ShipmentNo,
            PalletNo,
            BatchCode,
            DateReceived,
            ExpiryDate,
            Product,
            Description,
            Barcode,
            Quantity,
            Cost,
            Available,
            IsStock,
            IsVat, 
            IsWarehouse,
            ReferenceCode,
            isProcess,
            isSource,
            isConversion
        )
        SELECT
            Branch,--Branch,
            ' ',--ShipmentNo,
            0,--PalletNo,
            '',--BatchCode,
            DateReceived,--DateReceived,
            ExpiryDate,--ExpiryDate,
            Product,--Product,
            Description,--Description,
            Barcode,--Barcode,
            Quantity,--Quantity,
            Cost,--Cost,
            Quantity,--Available,
            1,--IsStock,
            isVat,--IsVat, 
            isWarehouse,--IsWarehouse,
            ISNULL(NULLIF(LTRIM(RTRIM(ReferenceCode)), ''), 'INVIN-'+ CAST(@parmid as varchar(5))),--ReferenceCode: [107] the one typed on the line, else INVIN-<batch> as before
            1,--isProcess,
            1,--isSource,
            0--isConversion
        FROM dbo.TempInventoryIN  WITH (NOLOCK)
        WHERE ID = @parmid;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END;
GO

-- the tab's grid function is SELECT * of TempInventoryIN: its column list is fixed when it was created, so refresh it
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_refreshsqlmodule 'dbo.funcview_InventoryINManualEntry';
GO

IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF COL_LENGTH('dbo.TempInventoryIN', 'ReferenceCode') IS NULL
    SET @msg = N'TempInventoryIN.ReferenceCode is missing';
ELSE IF ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_StageManualEntryForReInventoryIN')), N'') NOT LIKE '%@parmreferencecode%'
     OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CommitReInventoryINManualEntry')), N'') NOT LIKE '%[[]107]%'
    SET @msg = N'a proc is not the [107] text';
ELSE IF OBJECT_ID('dbo.sp_StageManualEntryForReInventoryIN_OLD_10172026230000', 'P') IS NULL OR OBJECT_ID('dbo.sp_CommitReInventoryINManualEntry_OLD_10172026230000', 'P') IS NULL
    SET @msg = N'a backup is missing';
ELSE IF NOT EXISTS (SELECT 1 FROM sys.dm_exec_describe_first_result_set(N'SELECT * FROM dbo.funcview_InventoryINManualEntry(0)', NULL, 0) WHERE name = 'ReferenceCode')
    SET @msg = N'funcview_InventoryINManualEntry does not return ReferenceCode';

IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[107] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59897, @msg, 1;
END

COMMIT TRANSACTION;
PRINT '[107] committed: Inventory IN > Manual Selection keeps a Reference Code per line (blank = INVIN-<batch id> as before).';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
