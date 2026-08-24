SET NOCOUNT ON;
PRINT '=== funcview_TransferOrderDetailsSTS: add ProductCategoryCode column (AddBranchOrderSTSBatchMode.cs Local Pork/Chicken/Beef disable) ===';
GO

-- =============================================
-- WHY: AddBranchOrderSTSBatchMode.cs needs to gray out / block selection of
-- rows whose product belongs to category 10 (LocalPork), 11 (LocalChicken),
-- or 12 (LocalBeef) -- this batch-mode screen has no barcode-scan/FIFO setup
-- for those. The function already joins dbo.ProductCategory and exposes the
-- category's Description as "Category", but not the raw
-- ProductCategoryCode the C# side needs to match against. Adding it here
-- rather than re-deriving the code from the Description string in C# --
-- codes are the stable identifier, descriptions can be renamed.
--
-- SAFE / ADDITIVE ONLY: every current caller of this function
-- (AddBranchOrderSTSBatchMode.cs, POForApprovalSTS.cs, ReceivedSTS.cs,
-- ViewBranchOrderSTS.cs) does `SELECT * FROM funcview_TransferOrderDetailsSTS(...)`
-- with no explicit column list, so appending one more output column does
-- not break any of them.
-- =============================================
IF OBJECT_ID('dbo.funcview_TransferOrderDetailsSTS_OLD_08242026170000', 'IF') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.funcview_TransferOrderDetailsSTS', 'IF') IS NOT NULL
        DROP FUNCTION dbo.funcview_TransferOrderDetailsSTS;
END
ELSE IF OBJECT_ID('dbo.funcview_TransferOrderDetailsSTS', 'IF') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.funcview_TransferOrderDetailsSTS', 'funcview_TransferOrderDetailsSTS_OLD_08242026170000';
END
GO

CREATE FUNCTION [dbo].[funcview_TransferOrderDetailsSTS]
(
    @parmbranchcode char(3),
    @parmpono varchar(10)
)
RETURNS TABLE
AS
RETURN
(
    WITH Lines AS (
        SELECT
            a.PONumber,
            a.SeqNo,
            a.ProductCode,
            a.Qty AS RequestedQty,
            a.Units
        FROM dbo.TransferOrderDetails AS a
        WHERE a.PONumber = @parmpono
    ),
    ProductTotals AS (
        SELECT ProductCode, SUM(RequestedQty) AS TotalRequestedQty
        FROM Lines
        GROUP BY ProductCode
    ),
    Inv AS (
        SELECT
            i.Product,
            SUM(i.Available) AS AvailableInv
        FROM dbo.Inventory AS i
        WHERE i.Branch = @parmbranchcode
          AND i.IsWarehouse = 1
          AND i.Available > 0
        GROUP BY i.Product
    )
    SELECT
        r.PONumber,
        r.SeqNo,
        pc.Description AS Category,
        p.ProductCategoryCode,
        r.ProductCode,
        CONCAT(r.ProductCode,' - ',p.Description) AS Product,
        p.Description AS ProductName,
        p.Barcode,
        r.RequestedQty AS QtyRequested,
        COALESCE(inv.AvailableInv, 0) AS AvailableInv,
        ISNULL(r.RequestedQty,0) AS ApprovedQty,
        ISNULL(r.RequestedQty,0) AS Qty,
        CASE
            WHEN COALESCE(inv.AvailableInv, 0) = 0 THEN 'NO INVENTORY'
            WHEN COALESCE(inv.AvailableInv, 0) < pt.TotalRequestedQty THEN 'NEGATIVE INVENTORY'
            ELSE 'PASSED'
        END AS Status
    FROM Lines AS r
    JOIN ProductTotals AS pt
      ON pt.ProductCode = r.ProductCode
    JOIN dbo.Products AS p
      ON p.ProductCode = r.ProductCode
     AND p.BranchCode  = @parmbranchcode
    LEFT JOIN Inv AS inv
      ON inv.Product = r.ProductCode
    LEFT JOIN dbo.ProductCategory AS pc
      ON pc.ProductCategoryID = p.ProductCategoryCode
);
GO

PRINT 'DEPLOYMENT COMPLETE: funcview_TransferOrderDetailsSTS now exposes ProductCategoryCode.';
