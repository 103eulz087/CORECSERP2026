SET NOCOUNT ON;
PRINT '=== Conversion: Destination/Output product dropdown for SearchLookUpEdit (HOFormsDevEx/ConversionPerBarcode.cs) ===';
GO

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-23
-- Description: Product dropdown source for Conversion's Destination/Output
--              product SearchLookUpEdit -- replaces the old "..." button ->
--              HOForms.SearchProducts popup flow (more steps than picking
--              from a SearchLookUpEdit, same pattern already used for the
--              Source "Select Product (FIFO)" dropdown).
--
--              Reads dbo.Products, not dbo.Inventory: destination products
--              are not limited to what's currently in stock -- the
--              conversion itself creates new Inventory lots for them.
--              BranchCode is hardcoded to '888' because that's the same
--              master-catalog branch spu_PostConversionBarcode already reads
--              (dbo.Products WHERE BranchCode = '888') when resolving the
--              output product's category/VAT class -- keeping this dropdown
--              on that same catalog avoids offering a product here that the
--              posting SP can't resolve.
-- =============================================
IF OBJECT_ID('dbo.sp_GetProductsForConversionOutputDropdown', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetProductsForConversionOutputDropdown', 'sp_GetProductsForConversionOutputDropdown_OLD_08232026150000';
GO

CREATE PROCEDURE dbo.sp_GetProductsForConversionOutputDropdown
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.ProductCode,
        p.Description,
        CONCAT(p.ProductCode, ' - ', p.Description) AS DisplayText
    FROM dbo.Products AS p WITH (NOLOCK)
    WHERE p.BranchCode = '888'
    ORDER BY p.Description;
END
GO

PRINT 'DEPLOYMENT COMPLETE: sp_GetProductsForConversionOutputDropdown.';
