CREATE FUNCTION dbo.funcview_BranchInventoryIN
(    
    @parmbranchcode char(3)
)
RETURNS TABLE
AS
RETURN
(
    WITH stockInv AS
    (
        SELECT Branch, Product, SUM(Available) AS Qty
        FROM Inventory
        WHERE Branch = @parmbranchcode
          AND Available > 0
        GROUP BY Branch, Product
    )
    SELECT
        a.BranchCode,
        c.Description AS Category,
        a.ProductCode,
        a.Description,
        ISNULL(b.Qty, 0) AS Ending,
        CAST(0 AS decimal(9,3)) AS NewQty,
        ISNULL(b.Qty, 0) AS Variance
    FROM Products a
    INNER JOIN ProductCategory c
        ON a.ProductCategoryCode = c.ProductCategoryID
    LEFT JOIN stockInv b
        ON a.BranchCode = b.Branch
       AND a.ProductCode = b.Product
    WHERE a.BranchCode = @parmbranchcode
);
