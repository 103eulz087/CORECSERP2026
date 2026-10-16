
CREATE    PROCEDURE [dbo].[sp_AddBranchInventoryBatch]
    @PONumber VARCHAR(10),
    @BranchCode VARCHAR(10),
    @ReceivedBy VARCHAR(40),
    @Items dbo.InventoryItemType READONLY
AS
BEGIN
    SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @TranCounter INT = @@TRANCOUNT;
	IF @TranCounter > 0
		SAVE TRANSACTION AddBatchSave;
	ELSE
		BEGIN TRANSACTION;

    BEGIN TRY
        -- Step 1: Separate new and existing items
        DECLARE @NewItems TABLE (
            ProductCode CHAR(5),
            Barcode VARCHAR(60),
            Qty DECIMAL(15,3),
            Cost DECIMAL(18,2),
            SellingPrice DECIMAL(18,2),
            IsScan BIT,
            ProductName VARCHAR(150),
            IsVat BIT
        );

        INSERT INTO @NewItems (ProductCode, Barcode, Qty, Cost, SellingPrice, IsScan, ProductName, IsVat)
        SELECT 
            I.ProductCode, I.Barcode, I.Qty, D.Cost , I.SellingPrice, I.IsScan,
            D.ProductName, D.IsVat
        FROM @Items I
        JOIN DeliveryDetails D WITH(NOLOCK) 
            ON D.ProductNo = I.ProductCode 
            AND I.Barcode = D.BarcodeNo 
            AND D.PONumber = @PONumber
            AND D.isCancelled=0
        WHERE NOT EXISTS (
            SELECT 1 FROM ReceivedOrderDetails R WITH(NOLOCK)
            WHERE R.PONumber = @PONumber AND R.ProductCode = I.ProductCode
        );

        -- Step 2: Insert new items
        INSERT INTO ReceivedOrderDetails (SeqNo, PONumber, ProductCode, ProductName, Barcode, Qty, Cost, SellingPrice, IsVat)
        SELECT 
            ISNULL((SELECT MAX(SeqNo) FROM ReceivedOrderDetails WITH(NOLOCK) WHERE PONumber = @PONumber), 0) + ROW_NUMBER() OVER (ORDER BY ProductCode),
            @PONumber, ProductCode, ProductName, Barcode, Qty, Cost, SellingPrice, IsVat
        FROM @NewItems;

        -- Step 3: Insert into InventoryLedger
        INSERT INTO InventoryLedger
        SELECT 
            SequenceReferenceNumber, @BranchCode, @BranchCode, GETDATE(), ProductNo, Description,
            0, QtyDelivered, 0, QtyDelivered, Cost, 'STS RCVD ITEM PO#' + PONumber, @ReceivedBy
        FROM InventoryDeliveryFIFO WITH(NOLOCK)
        WHERE PONumber = @PONumber AND BranchCode = @BranchCode
          AND ProductNo IN (SELECT ProductCode FROM @Items);

        -- Step 4: Update or insert ReceiveOrderSummary
        DECLARE @TotalItem INT, @TotalKilo FLOAT;

        SELECT @TotalItem = ISNULL(COUNT(*), 0), @TotalKilo = ISNULL(SUM(Qty), 0)
        FROM ReceivedOrderDetails WITH(NOLOCK)
        WHERE PONumber = @PONumber;

        IF EXISTS (SELECT 1 FROM ReceiveOrderSummary WITH(NOLOCK) WHERE PONumber = @PONumber)
        BEGIN
            UPDATE ReceiveOrderSummary
            SET TotalItem = @TotalItem, TotalKilo = @TotalKilo
            WHERE PONumber = @PONumber;
        END
        ELSE
        BEGIN
            INSERT INTO ReceiveOrderSummary (PONumber, BranchCode, TotalKilo, TotalItem, DateReceived, ReceivedBy)
            VALUES (@PONumber, @BranchCode, @TotalKilo, @TotalItem, GETDATE(), @ReceivedBy);
        END

        IF @TranCounter = 0
			COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @TranCounter = 0
			ROLLBACK TRANSACTION;
		ELSE
			IF XACT_STATE() <> -1
				ROLLBACK TRANSACTION AddBatchSave;

		DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
		RAISERROR (@ErrorMessage, 16, 1);
    END CATCH
END
