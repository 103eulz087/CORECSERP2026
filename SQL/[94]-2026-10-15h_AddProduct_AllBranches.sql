/* ================================================================
   [94] 2026-10-15h  Add Product: the new product goes to EVERY branch
   ================================================================
   User (2026-10-15): HOFormsDevEx/ProductsDevEx › Add used to put a new product
   in every branch; on PRODUCTION a new product now exists in 888 only.

   Cause: the screen inserts the 888 row only (string-built INSERT INTO
   Products VALUES ('888', ...)); the copy to the other branches was done by the
   AFTER INSERT trigger dbo.trg_insProduct, which is DISABLED on DEV, STAGING and
   PRODUCTION (same text everywhere, last altered 2026-04-27). Products added
   since then exist in 888 only: PRODUCTION 16036 PORK DRIPLOSS; STAGING 16036,
   16037 PORK PATA HIND; DEV none.
   The trigger is left as it is (disabled; who disabled it and why is not
   recorded). It also has a bug: it copies 20 of the 22 columns, not isVat or
   ProdType, so its copies would have no VAT flag / product type.

   RULE: a product is the same at every branch (PRODUCTION 2026-10-15: no
   product differs by branch in isVat, ProdType or SellingPrice; no NULLs).
   NEW dbo.spu_AddProductAllBranches: one transaction
     - per-product applock (PRODUCT:<code>, 59703): a double click can't add twice
     - refused 59701 when the product code already exists at any branch
     - ONE INSERT of the product for every branch in dbo.Branches, all 22
       columns (so a re-enabled trg_insProduct finds every row present and adds
       nothing, and its missing columns can't matter)
     - the HistoryLogs row the screen used to write ("Add New Product with
       Description name of ... and Product Code=...", branch 888)
     - post-check 59702: the product is at every branch
   The screen (C# of 2026-10-15) calls it with parameters instead of the
   string-built INSERT. ProdType stays 3 as the screen always wrote it.

   DATA: every product that exists at 888 but not at some branch is copied from
   its 888 row to the missing branches; the inserted keys are kept in
   dbo.Products_BranchBackfill_20261015 (to undo: delete those rows).

   One transaction; re-runnable (the proc is renamed to _OLD_<run> if present;
   the backfill only adds what is missing). Run in ONE connection, no open
   transaction. The new exe needs this proc; the old exe keeps working (it still
   adds 888 only).
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET LOCK_TIMEOUT 10000;
GO

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[94] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.Products', 'U') IS NULL OR OBJECT_ID('dbo.Branches', 'U') IS NULL OR OBJECT_ID('dbo.HistoryLogs', 'U') IS NULL
     OR COL_LENGTH('dbo.Products', 'isVat') IS NULL OR COL_LENGTH('dbo.Products', 'ProdType') IS NULL
BEGIN
    RAISERROR('[94] stopped: Products (with isVat / ProdType) / Branches / HistoryLogs not found in this database.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Branches WHERE BranchCode = '888')
BEGIN
    RAISERROR('[94] stopped: branch 888 is not in dbo.Branches.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[94] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
IF OBJECT_ID('dbo.spu_AddProductAllBranches', 'P') IS NOT NULL
BEGIN
    DECLARE @old SYSNAME = 'spu_AddProductAllBranches_OLD_' + FORMAT(SYSDATETIME(), 'MMddyyyyHHmmss');
    EXEC sp_rename 'dbo.spu_AddProductAllBranches', @old;
END
GO

------------------------------------------------------------------
-- 1. The proc
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE dbo.spu_AddProductAllBranches
    @ProductCode         VARCHAR(50),
    @Description         VARCHAR(100),
    @LongDescription     VARCHAR(300),
    @LandingCost         MONEY,
    @SellingPrice        MONEY,
    @ProductCategoryCode INT,
    @Price1              MONEY,
    @Price2              MONEY,
    @Price3              MONEY,
    @Price4              MONEY,
    @isRegular           BIT,
    @isPrice1            BIT,
    @isPrice2            BIT,
    @isPrice3            BIT,
    @isPrice4            BIT,
    @isDiscount          BIT,
    @haveBarcode         BIT,
    @Barcode             VARCHAR(150),
    @ReOrderLevel        FLOAT,
    @isVat               BIT,
    @ProdType            TINYINT = 3,
    @UserID              VARCHAR(50)
AS
/*
    Adds a new product to EVERY branch (dbo.Branches) in one statement, plus the HistoryLogs row of the Products screen.
    Returns one row: BranchesAdded. Refuses 59701 (code already exists), 59703 (another add of the same code is running),
    59702 (post-check). Caller: HOFormsDevEx/ProductsDevEx (Add). [94] 2026-10-15.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Code VARCHAR(50) = LTRIM(RTRIM(ISNULL(@ProductCode, '')));
    DECLARE @Added INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Code = ''
            THROW 59700, 'Product Code is required.', 1;

        DECLARE @Lock INT, @LockName NVARCHAR(255) = N'PRODUCT:' + @Code;
        EXEC @Lock = sp_getapplock @Resource = @LockName, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
        IF @Lock < 0
            THROW 59703, 'This product code is being added by someone else right now. Please try again.', 1;

        IF EXISTS (SELECT 1 FROM dbo.Products WITH (UPDLOCK, HOLDLOCK) WHERE ProductCode = @Code)
            THROW 59701, 'Product Code Already Exist', 1;

        INSERT INTO dbo.Products
            (BranchCode, ProductCode, [Description], LongDescription, LandingCost, SellingPrice, ProductCategoryCode,
             Price1, Price2, Price3, Price4, isRegular, isPrice1, isPrice2, isPrice3, isPrice4,
             isDiscount, haveBarcode, Barcode, ReOrderLevel, isVat, ProdType)
        SELECT b.BranchCode, @Code, @Description, @LongDescription, @LandingCost, @SellingPrice, @ProductCategoryCode,
               @Price1, @Price2, @Price3, @Price4, @isRegular, @isPrice1, @isPrice2, @isPrice3, @isPrice4,
               @isDiscount, @haveBarcode, @Barcode, @ReOrderLevel, @isVat, @ProdType
        FROM dbo.Branches AS b;
        SET @Added = @@ROWCOUNT;

        INSERT INTO dbo.HistoryLogs (UserID, DateExecute, ActionLogs, BranchCode)
        VALUES (@UserID, GETDATE(),
                LEFT('Add New Product with Description name of ' + ISNULL(@Description, '') + ' and Product Code=' + @Code + ' ', 500),
                '888');

        IF EXISTS (SELECT 1 FROM dbo.Branches AS b
                   WHERE NOT EXISTS (SELECT 1 FROM dbo.Products AS p WHERE p.BranchCode = b.BranchCode AND p.ProductCode = @Code))
            THROW 59702, 'Add Product post-check failed: the product is not at every branch; nothing was saved.', 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT @Added AS BranchesAdded;
END
GO

------------------------------------------------------------------
-- 2. Backfill: products at 888 but missing at some branch
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
IF OBJECT_ID('dbo.spu_AddProductAllBranches', 'P') IS NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[94] stopped: spu_AddProductAllBranches was not created; everything rolled back.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID('dbo.Products_BranchBackfill_20261015', 'U') IS NULL
    CREATE TABLE dbo.Products_BranchBackfill_20261015
    (
        BranchCode  VARCHAR(10)  NOT NULL,
        ProductCode VARCHAR(50)  NOT NULL,
        Description VARCHAR(100) NULL,
        InsertedAt  DATETIME2(0) NOT NULL CONSTRAINT DF_ProdBF94_At DEFAULT (SYSDATETIME()),
        InsertedBy  SYSNAME      NOT NULL CONSTRAINT DF_ProdBF94_By DEFAULT (SUSER_SNAME())
    );
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
INSERT INTO dbo.Products
    (BranchCode, ProductCode, [Description], LongDescription, LandingCost, SellingPrice, ProductCategoryCode,
     Price1, Price2, Price3, Price4, isRegular, isPrice1, isPrice2, isPrice3, isPrice4,
     isDiscount, haveBarcode, Barcode, ReOrderLevel, isVat, ProdType)
OUTPUT inserted.BranchCode, inserted.ProductCode, inserted.[Description]
    INTO dbo.Products_BranchBackfill_20261015 (BranchCode, ProductCode, Description)
SELECT b.BranchCode, p.ProductCode, p.[Description], p.LongDescription, p.LandingCost, p.SellingPrice, p.ProductCategoryCode,
       p.Price1, p.Price2, p.Price3, p.Price4, p.isRegular, p.isPrice1, p.isPrice2, p.isPrice3, p.isPrice4,
       p.isDiscount, p.haveBarcode, p.Barcode, p.ReOrderLevel, p.isVat, p.ProdType
FROM dbo.Products AS p
CROSS JOIN dbo.Branches AS b
WHERE p.BranchCode = '888'
  AND b.BranchCode <> '888'
  AND NOT EXISTS (SELECT 1 FROM dbo.Products AS x WHERE x.BranchCode = b.BranchCode AND x.ProductCode = p.ProductCode);
PRINT '[94] product rows copied to missing branches: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
GO

------------------------------------------------------------------
-- 3. Post-check, then commit
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF OBJECT_ID('dbo.spu_AddProductAllBranches', 'P') IS NULL
    SET @msg = N'spu_AddProductAllBranches is missing';
ELSE IF EXISTS (SELECT 1 FROM dbo.Products AS p CROSS JOIN dbo.Branches AS b
                WHERE p.BranchCode = '888'
                  AND NOT EXISTS (SELECT 1 FROM dbo.Products AS x WHERE x.BranchCode = b.BranchCode AND x.ProductCode = p.ProductCode))
    SET @msg = N'a product of 888 is still missing at a branch';

IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[94] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59898, @msg, 1;
END

COMMIT TRANSACTION;
PRINT '[94] committed: spu_AddProductAllBranches; products backfilled to every branch.';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
