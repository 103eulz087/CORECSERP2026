
CREATE PROCEDURE [dbo].[sp_FiFoMappingHRI]  
	@parmtransdate date,
	@parmorigin char(3),
	@parmbranchcode char(3),
	@parmprodcode char(5),
	@parmqty decimal(18,3),
	@parmdevno varchar(10),
	@parmpono varchar(10),
	@parmdevdetseqno int
AS
BEGIN
	SET NOCOUNT ON; 

	-- Safely handle nested transactions! 
	-- If the parent SP already started a transaction, we don't want to break it.
	DECLARE @TranCounter INT = @@TRANCOUNT;
	IF @TranCounter > 0
		SAVE TRANSACTION ProcedureSave;
	ELSE
		BEGIN TRANSACTION;

	BEGIN TRY
		----------------------------------------------------
		DECLARE @SeqNo bigint = NULL;
		DECLARE @ChildProduct char(5);
		DECLARE @RunningQtySold decimal(18,3);
		DECLARE @TotalCost decimal(18,3);
		DECLARE @sprice decimal(18,2);
		
		-- 1. Create a clean table variable to hold the items to deduct
		DECLARE @tblSalesSummary TABLE(
			rowno int identity(1,1),
			ChildProduct [char](5) NULL,
			QtyToDeduct [decimal](18,3) NULL,
			TempCost [decimal](18,3) NULL
		);
	
		-- =========================================================================
		-- 2. THE BOM EXPANSION (Fast IF/ELSE replaces the messy CTE)
		-- =========================================================================
		IF EXISTS (SELECT 1 FROM InventoryMapping WITH(NOLOCK) WHERE ParentProductCode = @parmprodcode)
		BEGIN
			-- It's a Combo Meal! Insert all the child ingredients.
			INSERT INTO @tblSalesSummary (ChildProduct, QtyToDeduct)
			SELECT 
				ChildProductCode, 
				(Quantity * @parmqty) -- Multiply the recipe amount by the quantity ordered
			FROM InventoryMapping WITH(NOLOCK)
			WHERE ParentProductCode = @parmprodcode;
		END
		ELSE
		BEGIN
			-- It's just a normal single product! Insert it as-is.
			INSERT INTO @tblSalesSummary (ChildProduct, QtyToDeduct)
			VALUES (@parmprodcode, @parmqty);
		END
	
		-- =========================================================================
		-- 3. THE CLEAN WHILE LOOP
		-- =========================================================================
		DECLARE @MinID INT = 1, @MaxID INT;
		SELECT @MaxID = MAX(rowno) FROM @tblSalesSummary;
		
		WHILE @MinID <= @MaxID
		BEGIN
			-- Grab the current item from our list
			SELECT 
				@ChildProduct = ChildProduct,
				@RunningQtySold = QtyToDeduct
			FROM @tblSalesSummary 
			WHERE rowno = @MinID;
				
			-- Get the selling price
			SELECT TOP 1 @sprice = ISNULL(SellingPrice, 0) 
			FROM Products WITH(NOLOCK) 
			WHERE BranchCode = @parmbranchcode AND ProductCode = @ChildProduct;
				
			-- Execute the actual FIFO Deduction for this specific child product
			EXEC dbo.sp_SalesQtyToInventoryQtyHRI
				@SeqNo OUTPUT, 
				@parmorigin, 
				@parmbranchcode, 
				@ChildProduct, 
				@RunningQtySold, 
				@sprice, 
				@parmdevno, 
				@parmpono, 
				@parmdevdetseqno,
				@TotalCost OUTPUT;
				
			-- Save the cost back to the temp table (if needed later)
			UPDATE @tblSalesSummary 
			SET TempCost = @TotalCost
			WHERE rowno = @MinID;
			
			-- Move to the next ingredient
			SET @MinID += 1; 
		END;
		
		-- Safely commit ONLY if we started the transaction ourselves
		IF @TranCounter = 0
			COMMIT TRANSACTION;
			
	END TRY
	BEGIN CATCH
		-- Safely rollback without crashing the parent SP!
		IF @TranCounter = 0
			ROLLBACK TRANSACTION;
		ELSE
			IF XACT_STATE() <> -1
				ROLLBACK TRANSACTION ProcedureSave;
			
		-- Bubble the error up to the parent procedure
		DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH
END;