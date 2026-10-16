 
CREATE    PROC [dbo].[spr_STSSummary]
    @parmpono VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @isSTS BIT = CASE
        WHEN EXISTS (SELECT 1 FROM TransferOrderSummary WHERE PONumber = @parmpono) THEN 1
        ELSE 0
    END;

    -- Temp table
    CREATE TABLE #temptable (
        SeqNo BIGINT,
        BranchCode CHAR(3),
        PONumber VARCHAR(10),
        ProductCode CHAR(5),
        ProductName VARCHAR(100),
        Qty DECIMAL(10,3),
        Unit VARCHAR(10),
        SellingPrice DECIMAL(10,2),
        Cost DECIMAL(10,2),
        TotalAmount DECIMAL(10,2),
        Description VARCHAR(250),
        BarcodeNo VARCHAR(35),
        Dispatch DECIMAL(10,3),
        Received DECIMAL(10,3)
    );

    IF @isSTS = 1
    BEGIN
        -- Genuine STS transfer
        INSERT INTO #temptable
        SELECT
            dd.SeqNo,
            a.InitiatingBranch,
            a.PONumber,
            dd.ProductNo,
            dd.ProductName,
            b.Qty,
            b.Units,
            d.SellingPrice,
            0,
            dd.QtyDelivered * d.SellingPrice,
            c.Description,
            d.Barcode,
            dd.QtyDelivered,
            0
        FROM TransferOrderSummary a
        INNER JOIN DeliveryDetails dd
            ON a.PONumber COLLATE SQL_Latin1_General_CP1_CI_AS = dd.PONumber
            AND dd.isCancelled = 0
            AND dd.isReturned = 0
        INNER JOIN Products d ON dd.ProductNo = d.ProductCode AND d.BranchCode = a.BranchCode COLLATE SQL_Latin1_General_CP1_CI_AS
        INNER JOIN ProductCategory c ON c.ProductCategoryID = d.ProductCategoryCode
        INNER JOIN TransferOrderDetails b
            ON a.PONumber COLLATE SQL_Latin1_General_CP1_CI_AS = b.PONumber
            AND b.ProductCode = dd.ProductNo
        WHERE a.PONumber COLLATE SQL_Latin1_General_CP1_CI_AS = @parmpono;
    END
    ELSE
    BEGIN
        -- Regular Products sales order
        INSERT INTO #temptable
        SELECT
            dd.SeqNo,
            a.BranchCode,
            a.PONumber,
            dd.ProductNo,
            dd.ProductName,
            b.Qty,
            b.Units,
            d.SellingPrice,
            0,
            dd.QtyDelivered * d.SellingPrice,
            c.Description,
            d.Barcode,
            dd.QtyDelivered,
            0
        FROM PurchaseOrderSummary a
        INNER JOIN PurchaseOrderDetails b ON a.PONumber = b.PONumber
        INNER JOIN DeliveryDetails dd ON a.PONumber = dd.PONumber
            AND dd.isReturned = 0
            AND dd.isCancelled = 0
        INNER JOIN Products d ON b.ProductCode COLLATE SQL_Latin1_General_CP1_CI_AS = d.ProductCode COLLATE SQL_Latin1_General_CP1_CI_AS AND d.BranchCode = a.BranchCode COLLATE SQL_Latin1_General_CP1_CI_AS
        INNER JOIN ProductCategory c ON c.ProductCategoryID = d.ProductCategoryCode
        WHERE a.PONumber = @parmpono;
    END

    -- Update Received
    UPDATE t
    SET t.Received = r.Qty
    FROM #temptable t
    INNER JOIN ReceivedOrderDetails r ON r.PONumber COLLATE SQL_Latin1_General_CP1_CI_AS = t.PONumber COLLATE SQL_Latin1_General_CP1_CI_AS
        AND r.ProductCode COLLATE SQL_Latin1_General_CP1_CI_AS = t.ProductCode COLLATE SQL_Latin1_General_CP1_CI_AS;

    -- Update Cost
    UPDATE t
    SET t.Cost = i.Cost
    FROM #temptable t
    INNER JOIN InventoryDeliveryFIFO i
        ON i.PONumber COLLATE SQL_Latin1_General_CP1_CI_AS = t.PONumber COLLATE SQL_Latin1_General_CP1_CI_AS
        AND t.SeqNo = i.DevDetSeqNo
        AND i.ProductNo COLLATE SQL_Latin1_General_CP1_CI_AS = t.ProductCode COLLATE SQL_Latin1_General_CP1_CI_AS;

    -- Final output
    SELECT
        SeqNo,
        ProductCode,
        ProductName,
        BarcodeNo,
        Qty AS QtyReq,
        Dispatch AS QtyDispatch,
        Qty - Dispatch AS Variance,
        Cost,
        FORMAT(Dispatch * Cost, 'N', 'en-us') AS TotalCost,
        '' AS Received
    FROM #temptable
    ORDER BY ProductName ASC;
END

