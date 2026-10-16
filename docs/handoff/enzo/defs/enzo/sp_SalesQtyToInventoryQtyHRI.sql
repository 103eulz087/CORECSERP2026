
CREATE PROCEDURE [dbo].[sp_SalesQtyToInventoryQtyHRI]  
	@parmSeqNo bigint OUTPUT, 
	@parmorigin char(3),
	@parmBranch char(3),
	@parmProduct char(5),
	@parmRunningQtySold decimal(18,3),
	@parmsellingprice decimal(18,2),   
	@parmdevno varchar(10),
	@parmpono varchar(10),
	@parmdevdetseqno int,
	@TotalCost decimal(18,3) OUTPUT    
AS
BEGIN
	SET NOCOUNT ON;
	
	-- =========================================================================
	-- THE SAFEPOINT: modular transaction handling
	-- =========================================================================
	DECLARE @TranCounter INT = @@TRANCOUNT;
	IF @TranCounter > 0
		SAVE TRANSACTION FIFODeductSave;
	ELSE
		BEGIN TRANSACTION;

	BEGIN TRY
		DECLARE @iSeqNo bigint, @iQty decimal(18,3), @iAvailable decimal(18,3), @iCost decimal(18,3);	
		DECLARE @ProductDescription varchar(max);
		DECLARE @RunningQtySold decimal(18,3) = @parmRunningQtySold;
		
		SET @TotalCost = ISNULL(@TotalCost, 0);
		
		WHILE (0 < @RunningQtySold)
		BEGIN
			SET @iSeqNo = NULL; 
			
			-- =========================================================================
			-- THE ATOMIC POP: Grabs the oldest row and deducts it in one microsecond!
			-- =========================================================================
			;WITH OldestInventoryBatch AS (
				SELECT TOP(1) SequenceNumber, Available, Quantity, Cost, Description, ReferenceCode
				FROM Inventory WITH (UPDLOCK, ROWLOCK) 
				WHERE ISNULL(Available, Quantity) > 0 
				  AND Branch = @parmorigin 
				  AND Product = @parmProduct 
				  AND IsWarehouse = 1
				ORDER BY SequenceNumber ASC 
			)
			UPDATE OldestInventoryBatch 
			SET @iSeqNo = SequenceNumber,
				@iQty = ISNULL(Available, Quantity),
				@iAvailable = IIF(@RunningQtySold >= ISNULL(Available, Quantity), 0, ISNULL(Available, Quantity) - @RunningQtySold),
				@iCost = ISNULL(Cost, 0),
				@ProductDescription = Description,
				Available = IIF(@RunningQtySold >= ISNULL(Available, Quantity), 0, ISNULL(Available, Quantity) - @RunningQtySold);
			-- If the CTE couldn't find any more inventory, break the loop!
			IF (@iSeqNo IS NULL) 
			BEGIN
				BREAK; 
			END
			
			DECLARE @QtyDeducted decimal(18,3) = (@iQty - @iAvailable);

			-- =========================================================================
			-- WRITE TO LEDGERS
			-- =========================================================================
			INSERT INTO InventoryDeliveryFIFO (
				DeliveryNo, PONumber, BranchCode, ProductNo, Description, 
				QtyDelivered, Cost, TotalCost, DateProcessed, DevDetSeqNo, 
				SequenceReferenceNumber, isVat, isErrorCorrect 
			)
			VALUES (
				@parmdevno, @parmpono, @parmBranch, @parmProduct, @ProductDescription, 
				@QtyDeducted, @iCost, (@QtyDeducted * @iCost), GETDATE(),@parmdevdetseqno,
				@iSeqNo, 0, 0
			);

			INSERT INTO InventoryLedger (
				SequenceRefNum, OriginBranch, DestinationBranch, DateProcessed, Product, 
				Description, BegQty, QtyIn, QtyOut, EndQty, Cost, 
				Remarks, ProcessedBy
			)
			VALUES (
				@iSeqNo, @parmorigin, @parmBranch, GETDATE(), @parmProduct, 
				@ProductDescription, @iQty, 0, @QtyDeducted, @iAvailable, @iCost, 
				'STS IN-TRANSIT PO#-' + @parmpono, 'System'
			);

			-- =========================================================================
			-- MATH RECALCULATION FOR NEXT LOOP
			-- =========================================================================
			SET @RunningQtySold = (@RunningQtySold - @iQty);
			SET @TotalCost = @TotalCost + (@iCost * @QtyDeducted);
			SET @parmSeqNo = @iSeqNo;
			
		END; -- END OF WHILE LOOP

		-- Safely commit ONLY if we are the ones who started the transaction!
		IF @TranCounter = 0
			COMMIT TRANSACTION;

	END TRY
	BEGIN CATCH
		-- Safely rollback without destroying the parent stored procedure!
		IF @TranCounter = 0
			ROLLBACK TRANSACTION;
		ELSE
			IF XACT_STATE() <> -1
				ROLLBACK TRANSACTION FIFODeductSave;
				
		-- Bubble the exact error message back up to C#
		DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH
END;