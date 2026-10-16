
CREATE PROCEDURE [dbo].[sp_GetInventoryForStockOutDropdown]
    @BranchCode VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        i.Product AS ProductCode,
        MAX(i.Description) AS Description,
        SUM(i.Available) AS Available,
        CONCAT(i.Product, ' - ', MAX(i.Description)) AS DisplayText
    FROM dbo.Inventory AS i WITH (NOLOCK)
    WHERE i.Branch = @BranchCode
      AND i.IsStock = 1
      AND i.Available > 0
      AND i.IsWarehouse = 1
    GROUP BY i.Product
    ORDER BY MAX(i.Description);
END
