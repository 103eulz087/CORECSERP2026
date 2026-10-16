
CREATE PROCEDURE [dbo].[sp_ConfirmBranchRecievedOrder] 
	@parmdevno varchar(20), 
	@parmpono varchar(10),
	@parmbarcode varchar(30),
	@parmbranchcode varchar(10), 
	@preparedby varchar(30) 
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	
	-- =========================================================================
	-- THE SAFEPOINT
	-- =========================================================================
	DECLARE @TranCounter INT = @@TRANCOUNT;
	IF @TranCounter > 0
		SAVE TRANSACTION ConfirmRcvdSave;
	ELSE
		BEGIN TRANSACTION;

	BEGIN TRY
		-- 1. Insert into Inventory from Received Order Details

		IF NOT EXISTS (SELECT 1 FROM [Inventory] WITH(NOLOCK) WHERE Branch = @parmbranchcode and ReferenceCode='rcv-' + @parmpono and DateReceived=CAST(GETDATE() as date))
        BEGIN
			
				INSERT INTO [Inventory] (
					[Branch], [ShipmentNo], [PalletNo], [BatchCode], [DateReceived],
					[Product], [Description], [Barcode], [TipWeight], [Quantity],
					[Cost], [Available], [IsStock], [IsVat], [IsWarehouse],
					[ReferenceCode], [LastMovementDate], [isProcess], [isSource], [isConversion]
				) 
				SELECT 
					@parmbranchcode, ' ', ' ', ' ', GETDATE(),
					ProductCode, ProductName, Barcode, 0, Qty,
					Cost, Qty, 1, IsVat, 1,
					'rcv-' + PONumber, GETDATE(), 0, 1, 0
				FROM ReceivedOrderDetails WITH(NOLOCK) 
				WHERE PONumber = @parmpono;
        END
        
		-- 2. Update Delivery Details Status
		UPDATE dt 
		SET dt.Status = 'DELIVERED',
			dt.ActualQty = rt.Qty,
			dt.Variance = (dt.QtyDelivered - rt.Qty)
		FROM DeliveryDetails dt
		INNER JOIN ReceivedOrderDetails rt
			ON dt.PONumber = rt.PONumber
			AND dt.BarcodeNo = rt.Barcode
			AND dt.ProductNo = rt.ProductCode
		WHERE dt.PONumber = @parmpono;  

		-- 3. Calculate Totals instantly without Temp Tables!
		DECLARE @totalactualqty2 FLOAT = 0, @totalvariancevat FLOAT = 0, @totalvariancevatexempt FLOAT = 0;

		SELECT 
			@totalactualqty2 = ISNULL(SUM(ActualQty), 0),
			@totalvariancevat = ISNULL(SUM(CASE WHEN isVat = 1 THEN ABS(Variance) ELSE 0 END), 0),
			@totalvariancevatexempt = ISNULL(SUM(CASE WHEN isVat = 0 THEN ABS(Variance) ELSE 0 END), 0)
		FROM DeliveryDetails WITH(NOLOCK)
		WHERE PONumber = @parmpono;

		-- 4. Update Summaries
		UPDATE DeliverySummary 
		SET TotalActualQty = @totalactualqty2,
			TotalVarianceVat = @totalvariancevat,
			TotalVarianceVatExempt = @totalvariancevatexempt,
			Status = 'DELIVERED'
		WHERE PONumber = @parmpono; 
		
		UPDATE TransferOrderSummary 
		SET Status = 'DELIVERED' 
		WHERE PONumber = @parmpono; 
		
		UPDATE ReceiveOrderSummary 
		SET TotalItem = (SELECT ISNULL(COUNT(PONumber), 0) FROM ReceivedOrderDetails WITH(NOLOCK) WHERE PONumber = @parmpono),
			TotalKilo = (SELECT ISNULL(SUM(Qty), 0) FROM ReceivedOrderDetails WITH(NOLOCK) WHERE PONumber = @parmpono)
		WHERE PONumber = @parmpono;

		-- 5. Write History Log (FIXED: Used @preparedby instead of the unassigned @username)
		INSERT INTO HistoryLogs (UserID, DateExecute, ActionLogs, BranchCode)
		VALUES (@preparedby, GETDATE(), 'Received/Confirm Order with PONumber=' + @parmpono, @parmbranchcode);

		IF @TranCounter = 0
			COMMIT TRANSACTION;

	END TRY
	BEGIN CATCH
		IF @TranCounter = 0
			ROLLBACK TRANSACTION;
		ELSE
			IF XACT_STATE() <> -1
				ROLLBACK TRANSACTION ConfirmRcvdSave;

		-- Pass the error explicitly back to C# so you never get blind-sided again!
		DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH
END