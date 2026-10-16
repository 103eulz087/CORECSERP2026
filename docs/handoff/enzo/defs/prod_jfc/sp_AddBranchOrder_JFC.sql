
CREATE PROCEDURE [dbo].[sp_AddBranchOrder_JFC] 
	@parmdevno varchar(20),
	@parmrefno varchar(10),
	@parmpono varchar(10), 
	@parmprodcatcode varchar(10),
	@parmprodcode varchar(10),
	@parmshipmentno varchar(10),
	@parmqty decimal(18,3), -- Using Decimal instead of Float
	@parmbarcode varchar(50),
	@parmbranchcode varchar(10),
	@parmorigin varchar(10),
	@preparedby varchar(30),
	@parmsourceseqno varchar(20),
	@parmbarcodescanning bit
AS
BEGIN  
	SET NOCOUNT ON;
	
	BEGIN TRY
		BEGIN TRAN;
		
		DECLARE @productname varchar(100);
		DECLARE @qtyrequested decimal(18,3) = @parmqty; 
		DECLARE @parmeffectivitydate date;
		DECLARE @isvatablenew bit;
		DECLARE @specialpriceamount decimal(18,2); 
		DECLARE @custkey char(8);
		DECLARE @devseqno int;
		DECLARE @parminvsettings bit;
		DECLARE @invqty decimal(18,3);

		-- 1. Get Effectivity Date
		SELECT @parmeffectivitydate = EffectivityDate 
		FROM TransferOrderSummary WITH(NOLOCK)
		WHERE PONumber = @parmpono;
		
		IF @parmeffectivitydate IS NULL
		BEGIN 
			SET @parmeffectivitydate = GETDATE(); -- Meaningful fallback
		END
		-- 2. Get Product Info & Inventory
		SELECT @productname = Description, @isvatablenew = isVat
		FROM Products WITH(NOLOCK)
		WHERE ProductCode = @parmprodcode AND BranchCode = @parmorigin;

		-- ISNULL is critical here. If the item has never been in the warehouse, SUM returns NULL!
		SELECT @invqty = ISNULL(SUM(Available), 0)
		FROM Inventory WITH(NOLOCK)
		WHERE Branch = @parmorigin AND ShipmentNo=@parmshipmentno AND Available > 0 AND Product = @parmprodcode;

		-- =========================================================================
		-- 🛑 THE TRAP: INSUFFICIENT INVENTORY CHECK
		-- =========================================================================
		IF @invqty < @parmqty
		BEGIN
			-- Formats a clean message: "Insufficient Stocks! Requested: 5.000, Available: 2.000."
			DECLARE @CustomError NVARCHAR(4000) = 'Insufficient Stocks for ' + ISNULL(@productname, @parmprodcode) + '! You requested ' + CAST(CAST(@parmqty AS INT) AS VARCHAR) + ', but only ' + CAST(CAST(@invqty AS INT) AS VARCHAR) + ' are availables.';
			
			-- Severity 16 forces SQL to jump instantly to the BEGIN CATCH block below
			RAISERROR(@CustomError, 16, 1); 
		END

		IF @isvatablenew is null
		BEGIN
			DECLARE @CustomError1 NVARCHAR(4000) = 'Product is no identification either VAT OR NON VAT' + ISNULL(@productname, @parmprodcode);
			-- Severity 16 forces SQL to jump instantly to the BEGIN CATCH block below
			RAISERROR(@CustomError1, 16, 1); 
		END
		-- =========================================================================

		-- 3. Pricing Logic
		IF @parmbranchcode = @parmorigin
		BEGIN
			SELECT @custkey = Customer FROM PurchaseOrderSummary WITH(NOLOCK) WHERE PONumber = @parmpono;
			
			SELECT @specialpriceamount = SpecialPriceAmount FROM CustomerProductSetting WITH(NOLOCK)
			WHERE ProductCode = @parmprodcode AND CustomerKey = @custkey;
			
			IF (@specialpriceamount = 0 OR @specialpriceamount IS NULL)
			BEGIN
				SELECT @specialpriceamount = SellingPrice FROM Products WITH(NOLOCK)
				WHERE ProductCode = @parmprodcode AND BranchCode = @parmorigin;
			END
		END

		-- 4. FIFO Processing & Delivery Details  
	 
		 
			--SELECT @devseqno = ISNULL(MAX(SeqNo)+1,0) FROM DeliveryDetails WITH(NOLOCK)
			--WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono AND ProductNo = @parmprodcode;-- and BarcodeNo=@parmbarcode;

			
		 
			SELECT @devseqno = ISNULL(MAX(DevDetSeqNo)+1,0) FROM InventoryDeliveryFIFO WITH(NOLOCK)
			WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono --AND ProductNo = @parmprodcode;-- and BarcodeNo=@parmbarcode;

			 
			-- Execute FIFO Mapping
			EXEC sp_FiFoMappingSTS_JFC @parmeffectivitydate, @parmorigin, @parmbranchcode, @parmprodcode,@parmshipmentno, @parmqty, @parmdevno, @parmpono, @devseqno; 
			
			INSERT INTO [dbo].[DeliveryDetails] (
				[SeqNo], [DeliveryNo], [PONumber], [ReferenceNumber], [ProductNo], [BarcodeNo],
				[ProductName], [QtyDelivered], [ActualQty], [Variance], [Cost], [SellingPrice],
				[Status], [isVat], [ProcessedBy], [isSettled], [isCreditMemo], [isReturned], isCancelled, DateTimeAdded, DateTimeUpdated
			)
			SELECT
				@devseqno, @parmdevno, @parmpono, @parmrefno, @parmprodcode, @parmbarcode,
				@productname, @parmqty, @parmqty, 0, 0, ISNULL(@specialpriceamount,0),
				'PENDING', @isvatablenew, @preparedby, 0, 0, 0, 0, GETDATE(), '';
	 
		
		-- 5. Delivery Summary Logic
		IF NOT EXISTS (SELECT TOP(1) PONumber FROM DeliverySummary WITH(UPDLOCK, HOLDLOCK) WHERE PONumber = @parmpono AND DeliveryNo = @parmdevno)
		BEGIN
			DECLARE @totalitem int, @totalqtydelivered decimal(18,3);
				
			SELECT @totalitem = ISNULL(COUNT(*),0), @totalqtydelivered = ISNULL(SUM(QtyDelivered),0) 
			FROM DeliveryDetails WITH(NOLOCK)
			WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono;
				
			INSERT INTO [dbo].[DeliverySummary] (
				[DeliveryNo], [PONumber], [ReferenceNumber], [InvoiceNo], [BranchCode],
				[TotalItem], [TotalQtyDelivered], [TotalActualQty], [TotalVarianceVat], [TotalVarianceVatExempt],
				[EffectivityDate], [Status], [DateAdded], [PreparedBy], [isSettled], [isInvoiceUpdate]
			)
			SELECT		
				@parmdevno, @parmpono, @parmrefno, @parmrefno, @parmbranchcode,
				@totalitem, @totalqtydelivered, 0, 0, 0,
				@parmeffectivitydate, 'PENDING', GETDATE(), @preparedby, 0, 0;
		END

		COMMIT TRAN;
	END TRY
	BEGIN CATCH
		-- The RAISERROR drops us right here. We cancel the transaction cleanly!
		IF @@TRANCOUNT > 0
			ROLLBACK TRAN;
			
		-- Force the error back to C#
		DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH
END