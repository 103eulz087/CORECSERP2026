
CREATE PROCEDURE [dbo].[sp_AddBranchOrderHRI] 
	@parmdevno varchar(20),
	@parmrefno varchar(10),
	@parmpono varchar(10), 
	@parmprodcatcode varchar(10),
	@parmprodcode varchar(10),
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

		-- 2. Get Product Info
		SELECT @productname = Description, @isvatablenew = ISNULL(isVat,0)
		FROM Products WITH(NOLOCK)
		WHERE ProductCode = @parmprodcode AND BranchCode = @parmorigin;

		-- ISNULL is critical here. If the item has never been in the warehouse, SUM returns NULL!
		SELECT @invqty = ISNULL(SUM(Available), 0)
		FROM Inventory WITH(NOLOCK)
		WHERE Branch = @parmorigin AND Available > 0 AND isStock = 1 AND Product = @parmprodcode AND IsWarehouse = 1;

		-- =========================================================================
		-- 🛑 THE TRAP: INSUFFICIENT INVENTORY CHECK
		-- =========================================================================
		IF @invqty < @parmqty
		BEGIN
			-- Formats a clean message: "Insufficient Stocks! Requested: 5.000, Available: 2.000."
			DECLARE @CustomError NVARCHAR(4000) = 'Insufficient Stocks for ' + ISNULL(@productname, @parmprodcode) + '! You requested ' + CAST(CAST(@parmqty AS INT) AS VARCHAR) + ', but only ' + CAST(CAST(@invqty AS INT) AS VARCHAR) + ' are available.';
			
			-- Severity 16 forces SQL to jump instantly to the BEGIN CATCH block below
			RAISERROR(@CustomError, 16, 1); 
		END
	 
		SELECT @specialpriceamount = ISNULL(SellingPrice,0)  FROM PurchaseOrderDetails 
		WHERE PONumber =@parmpono and ProductCode = @parmprodcode ;
		-- 4. FIFO Processing & Delivery Details 
		SELECT @parminvsettings = isFIFO FROM InventorySettings;  
		
		
			SELECT @devseqno = ISNULL(MAX(SeqNo),0) FROM DeliveryDetails WITH(NOLOCK)
			WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono;

			declare @devdetsqno int 
			set @devdetsqno=@devseqno+1;
			-- Execute FIFO Mapping
			EXEC sp_FiFoMappingHRI @parmeffectivitydate, @parmorigin, @parmbranchcode, @parmprodcode, @parmqty, @parmdevno, @parmpono, @devdetsqno;
			
			INSERT INTO [dbo].[DeliveryDetails] (
					[SeqNo], [DeliveryNo], [PONumber], [ReferenceNumber], [ProductNo], [BarcodeNo],
					[ProductName], [QtyDelivered], [ActualQty], [Variance], [Cost], [SellingPrice],
					[Status], [isVat], [ProcessedBy], [isSettled], [isCreditMemo], [isReturned],isCancelled
				)
				SELECT
					@devseqno + 1, @parmdevno, @parmpono, @parmrefno, @parmprodcode, @parmbarcode,
					@productname, @parmqty, @parmqty, 0, 0, ISNULL(@specialpriceamount,0),
					'PENDING', @isvatablenew, @preparedby, 0, 0, 0,0;
		
		-- 5. Delivery Summary Logic (FIXED: Changed IF EXISTS to IF NOT EXISTS)
		IF NOT EXISTS (SELECT TOP(1) PONumber FROM DeliverySummary WHERE PONumber = @parmpono AND DeliveryNo = @parmdevno)
		BEGIN
			DECLARE @totalitem int, @totalqtydelivered decimal(18,3);
				
			SELECT @totalitem = ISNULL(COUNT(*),0), @totalqtydelivered = ISNULL(SUM(QtyDelivered),0) 
			FROM DeliveryDetails 
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
