

CREATE VIEW [dbo].[view_MonthEndReInventoryReport] 

AS 
WITH Combined AS
(
    -- First query
    SELECT 
        a.ID,
        a.[Branch],
        b.[ShipmentNo],
        b.[PalletNo],
        b.[DateReceived],
        b.[ExpiryDate],
        b.[Product],
        b.[Description],
        a.[Barcode],
        b.[Quantity],
        b.[Cost],
        b.[Quantity] AS Available,
        a.[IsWarehouse],
        a.AddedBy,
        a.DateAdded,
        a.UpdatedBy,
        a.DateUpdated
    FROM dbo.[InventoryINMonthEnd] a WITH (NOLOCK)
    INNER JOIN dbo.Inventory b WITH (NOLOCK)
        ON a.Barcode = b.Barcode
       AND a.Branch = b.Branch
       AND b.ReferenceCode NOT LIKE 'INVIN%'

    UNION ALL

    -- Second query
    SELECT 
        a.ID,
        a.[Branch],
        '' AS [ShipmentNo],
        '' AS [PalletNo],
        a.[DateReceived],
        a.[ExpiryDate],
        a.[Product],
        a.[Description],
        a.[Barcode],
        a.[Quantity],
        a.[Cost],
        a.[Quantity] AS Available,
        a.[IsWarehouse],
        a.EncodeBy AS AddedBy,
        a.DateEncode AS DateAdded,
        '' AS UpdatedBy,
        GETDATE() AS DateUpdated
    FROM TempInventoryIN a
    WHERE a.DateEncode >= '2026-07-31'
)
SELECT *
FROM Combined;

