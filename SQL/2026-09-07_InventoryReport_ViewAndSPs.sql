-- =============================================
-- Author: Eulz Avancena; 2026-09-07
-- Description: New Inventory Viewing/Report module (Reporting/InventoryReport.cs).
--   1. view_InventoryReport -- readable, joined presentation layer over dbo.Inventory.
--      Deliberately built as a VIEW (not baked into a proc) so columns can be added,
--      removed, or hidden later without touching the filtering SPs below.
--        - BranchName joined from dbo.Branches.
--        - ProductCategoryDescription joined from dbo.Products/dbo.ProductCategory,
--          using the BranchCode='888' master-catalog convention already established
--          elsewhere in this codebase (Products is keyed by BranchCode+ProductCode,
--          and '888' Head Office holds the authoritative product definitions).
--        - LocationLabel: IsWarehouse only means anything for HeadOffice (Branch='888')
--          per business rule -- 1 = 'Warehouse', 0 = 'Third-Party Storage'; NULL for
--          every other branch, where the flag isn't meaningful.
--        - ConversionStatusLabel: readable text for isConversion.
--   2. sp_rpt_InventoryReport_Detail / sp_rpt_InventoryReport_Summary -- parameterized
--      filtering wrappers over the view (a plain view can't take parameters). Both
--      default @IsStockOnly=1 (only currently-live lots) since "inventory per branch"
--      means current position, not full history; callers can pass 0 to include
--      exhausted/consumed lots for audit purposes.
-- =============================================

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-------------------------------------------------------------------
-- 1. view_InventoryReport
-------------------------------------------------------------------
IF OBJECT_ID('dbo.view_InventoryReport', 'V') IS NOT NULL
    DROP VIEW dbo.view_InventoryReport;
GO

CREATE VIEW dbo.view_InventoryReport
AS
SELECT
    I.SequenceNumber,
    I.Branch,
    B.BranchName,
    I.ShipmentNo,
    I.PalletNo,
    I.BatchCode,
    I.DateReceived,
    I.ExpiryDate,
    I.Product,
    I.Description,
    P.Description AS ProductMasterDescription,
    PC.Description AS ProductCategoryDescription,
    I.Barcode,
    I.TipWeight,
    I.Quantity,
    I.Cost,
    I.Available,
    -- ISNULL'd: Available/Cost can genuinely be NULL on some lots (every other query
    -- in this codebase that reads these two columns defensively wraps them, e.g.
    -- SQL\2026-08-03_InventoryQtyAdjustment_SimplifiedSignature.sql), and an
    -- un-wrapped NULL*NULL here would silently vanish from SUM(AvailableValue) in
    -- the Summary SP below with no visible error.
    (ISNULL(I.Available, 0) * ISNULL(I.Cost, 0)) AS AvailableValue,
    I.QtyBigBlue,
    I.IsStock,
    I.IsVat,
    I.IsWarehouse,
    CASE
        WHEN I.Branch = '888' AND I.IsWarehouse = 1 THEN 'Warehouse'
        WHEN I.Branch = '888' AND I.IsWarehouse = 0 THEN 'Third-Party Storage'
        ELSE NULL
    END AS LocationLabel,
    I.ReferenceCode,
    I.LastMovementDate,
    I.isProcess,
    I.isSource,
    I.isConversion,
    CASE WHEN I.isConversion = 1 THEN 'Converted Item' ELSE 'Original/Unconverted' END AS ConversionStatusLabel
FROM dbo.Inventory I
LEFT JOIN dbo.Branches B ON B.BranchCode = I.Branch
LEFT JOIN dbo.Products P ON P.ProductCode = I.Product AND P.BranchCode = '888'
LEFT JOIN dbo.ProductCategory PC ON PC.ProductCategoryID = P.ProductCategoryCode;
GO

-------------------------------------------------------------------
-- 2. sp_rpt_InventoryReport_Detail -- per-row/per-barcode view.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_InventoryReport_Detail', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_rpt_InventoryReport_Detail;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE dbo.sp_rpt_InventoryReport_Detail
    @Branch       VARCHAR(5)  = NULL,
    @IsWarehouse  BIT         = NULL,
    @IsConversion BIT         = NULL,
    @ProductCode  VARCHAR(10) = NULL,
    @DateFrom     DATE        = NULL,
    @DateTo       DATE        = NULL,
    @IsStockOnly  BIT         = 1
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM dbo.view_InventoryReport
    WHERE (@Branch IS NULL OR Branch = @Branch)
      AND (@IsWarehouse IS NULL OR IsWarehouse = @IsWarehouse)
      AND (@IsConversion IS NULL OR isConversion = @IsConversion)
      AND (@ProductCode IS NULL OR Product = @ProductCode)
      AND (@DateFrom IS NULL OR DateReceived >= @DateFrom)
      AND (@DateTo IS NULL OR DateReceived <= @DateTo)
      AND (@IsStockOnly = 0 OR IsStock = 1)
    ORDER BY DateReceived DESC, SequenceNumber DESC;
END
GO

-------------------------------------------------------------------
-- 3. sp_rpt_InventoryReport_Summary -- grouped sum/count rollup.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_InventoryReport_Summary', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_rpt_InventoryReport_Summary;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE dbo.sp_rpt_InventoryReport_Summary
    @Branch       VARCHAR(5)  = NULL,
    @IsWarehouse  BIT         = NULL,
    @IsConversion BIT         = NULL,
    @ProductCode  VARCHAR(10) = NULL,
    @DateFrom     DATE        = NULL,
    @DateTo       DATE        = NULL,
    @IsStockOnly  BIT         = 1
AS
BEGIN
    SET NOCOUNT ON;

    -- Grouped by the master-catalog ProductMasterDescription/ProductCategoryDescription
    -- (both invariant per Product code, via the view's Products/ProductCategory join) --
    -- NOT the per-lot Inventory.Description snapshot, which is copied onto each row at
    -- receipt/adjustment time and can drift if the catalog description was edited after
    -- older lots were already received. Grouping by that per-lot value would silently
    -- fragment one product's totals across two or more summary rows.
    SELECT
        Branch,
        BranchName,
        Product,
        Description       = MAX(ProductMasterDescription),
        ProductCategoryDescription,
        LocationLabel,
        ConversionStatusLabel,
        LotCount        = COUNT(*),
        TotalQuantity   = SUM(ISNULL(Quantity, 0)),
        TotalAvailable  = SUM(ISNULL(Available, 0)),
        TotalValue      = SUM(AvailableValue)
    FROM dbo.view_InventoryReport
    WHERE (@Branch IS NULL OR Branch = @Branch)
      AND (@IsWarehouse IS NULL OR IsWarehouse = @IsWarehouse)
      AND (@IsConversion IS NULL OR isConversion = @IsConversion)
      AND (@ProductCode IS NULL OR Product = @ProductCode)
      AND (@DateFrom IS NULL OR DateReceived >= @DateFrom)
      AND (@DateTo IS NULL OR DateReceived <= @DateTo)
      AND (@IsStockOnly = 0 OR IsStock = 1)
    GROUP BY Branch, BranchName, Product, ProductCategoryDescription, LocationLabel, ConversionStatusLabel
    ORDER BY Branch, Product;
END
GO

PRINT 'DEPLOYMENT COMPLETE: view_InventoryReport, sp_rpt_InventoryReport_Detail, sp_rpt_InventoryReport_Summary.';
