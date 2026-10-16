CREATE PROCEDURE [dbo].[sp_FiFoMappingSalesInvDeductForJobs]  
    @parmtransdate DATE,
    @parmbranchcode CHAR(3),
    @parmprodcode CHAR(5),
    @parmqty FLOAT,
    @parmoption CHAR(1) -- 1: Manual, 2: Batch Upload
AS
BEGIN
    SET NOCOUNT ON;
    
    -- 1. Use #Temp tables instead of @Table variables for massive speed boosts
    CREATE TABLE #SalesSummary (
        rowno INT IDENTITY(1,1) PRIMARY KEY,
        SeqNo BIGINT,
        Branch CHAR(3) collate SQL_Latin1_General_CP1_CI_AS,
        DateOrder DATE,
        ParentProduct CHAR(5) collate SQL_Latin1_General_CP1_CI_AS,
        ChildProduct CHAR(5) collate SQL_Latin1_General_CP1_CI_AS,
        QtyBase FLOAT,
        QtySold FLOAT,
        TempCost FLOAT
    );

    BEGIN TRY
        BEGIN TRAN;
		 
     --   IF EXISTS (SELECT 1 
					--FROM dbo.ConversionSummary 
					--WHERE BranchCode=@parmbranchcode 
					--AND CAST(DateConverted as date)=CAST(GETDATE() as date)
					--AND isConfirm=0 and isErrorCorrect=0
					--)
     --   BEGIN
     --       RAISERROR('You still have Pending/For Confirmation Conversion', 16, 1);
     --       ROLLBACK TRAN;
     --       SELECT 2 AS status, 'Error: Pending Conversion' AS message;
     --       RETURN;
     --   END
        -- 2. Populate Sales Data
        IF (@parmoption = 2)
        BEGIN
            INSERT INTO #SalesSummary (SeqNo, Branch, DateOrder, ParentProduct, QtySold)
            SELECT SalesID, BranchCode, DateOrder, ProductCode, QtySold
            FROM POSSalesSummary WITH(NOLOCK)
            WHERE ISNULL(isUpload, 0) = 0 
              AND DateOrder = @parmtransdate 
              AND BranchCode = @parmbranchcode;
        END
        ELSE IF (@parmoption = 1)
        BEGIN
            INSERT INTO #SalesSummary (SeqNo, Branch, ParentProduct, QtySold)
            VALUES (0, @parmbranchcode, @parmprodcode, @parmqty);
        END;

        -- 3. Apply BOM/Child Mapping (If Applicable)
        -- (Simplified your CTE logic here to directly update the temp table)
        UPDATE S
        SET S.ChildProduct = M.ChildProductCode,
            S.QtyBase = M.Quantity
        FROM #SalesSummary S
        INNER JOIN InventoryMapping M ON S.ParentProduct = M.ParentProductCode;

        -- Set defaults for non-mapped items
        UPDATE #SalesSummary 
        SET ChildProduct = ParentProduct, QtyBase = 1 
        WHERE ChildProduct IS NULL;

		----------------------------------------------------------------
		
		CREATE TABLE #TempResults (
			ProductCode VARCHAR(20),
			ProductName VARCHAR(250),
			QtySold DECIMAL(18,3),
			Available DECIMAL(18,3),
			Variance DECIMAL(18,3),
			Status VARCHAR(20)
		)
		-- 2. Execute and capture
		INSERT INTO #TempResults
		EXEC [dbo].[sp_Analyze] @parmbranchcode, @parmtransdate

		-- 3. Move from Temp to your Permanent table with the extra info (Branch & Date)
		INSERT INTO InventorySalesAnalysis (BranchCode, DateExecute, ProductCode, ProductName, QtySold, Qtyinv, Status)
		SELECT @parmbranchcode, @parmtransdate, ProductCode, ProductName, QtySold, Available, Status
		FROM #TempResults

		-- 4. Clean up
		DROP TABLE #TempResults

		----------------------------------------------------------------

        -- 4. HIGH-SPEED VALIDATION: Do we have enough stock?
        --IF EXISTS (
        --    SELECT 1
        --    FROM (
        --        -- Total Required
        --        SELECT ChildProduct, SUM(QtyBase * QtySold) AS TotalRequired
        --        FROM #SalesSummary GROUP BY ChildProduct
        --    ) Req
        --    LEFT JOIN (
        --        -- Total Available
        --        SELECT Product, SUM(Available) AS TotalAvailable
        --        FROM Inventory WITH(NOLOCK)
        --        WHERE Branch = @parmbranchcode AND Available > 0
        --        GROUP BY Product
        --    ) Inv ON Req.ChildProduct = Inv.Product
        --    WHERE ISNULL(Inv.TotalAvailable, 0) < Req.TotalRequired
        --)
        --BEGIN
        --    RAISERROR('Insufficient inventory detected. Deduction aborted to prevent negative stock.', 16, 1);
        --    ROLLBACK TRAN;
        --    RETURN;
        --END;

        -- 5. THE FIFO LOOP
        DECLARE @CurrentRow INT = 1;
        DECLARE @MaxRow INT = (SELECT MAX(rowno) FROM #SalesSummary);
        
        DECLARE @LoopSeqNo BIGINT, @LoopProduct CHAR(5), @LoopQty FLOAT;
        DECLARE @CostOutput FLOAT, @SellingPrice MONEY;

        WHILE (@CurrentRow <= @MaxRow)
        BEGIN
            SELECT 
                @LoopSeqNo = SeqNo,
                @LoopProduct = ChildProduct,
                @LoopQty = (QtyBase * QtySold)
            FROM #SalesSummary 
            WHERE rowno = @CurrentRow;

            -- Get Selling Price
            SELECT TOP(1) @SellingPrice = SellingPrice 
            FROM Products WITH(NOLOCK) 
            WHERE BranchCode = @parmbranchcode AND ProductCode = @LoopProduct;

            -- EXECUTE ENGINE
            EXEC dbo.sp_SalesQtyToInventoryQtyEODSalesInvDeduct 
                @parmSeqNo = @LoopSeqNo, 
                @parmBranch = @parmbranchcode, 
                @parmProduct = @LoopProduct, 
                @parmRunningQtySold = @LoopQty, 
                @parmsellingprice = @SellingPrice, 
                @TotalCost = @CostOutput OUTPUT;

            -- Save Cost Back
            UPDATE #SalesSummary SET TempCost = @CostOutput WHERE rowno = @CurrentRow;

            SET @CurrentRow = @CurrentRow + 1;
        END;

        -- 6. POST-PROCESSING
        IF (@parmoption = 2)
        BEGIN
            -- Update POSSalesSummary with averaged costs
            UPDATE POS
            SET POS.isUpload = 1
               
            FROM POSSalesSummary POS
            INNER JOIN (
                SELECT SeqNo 
                FROM #SalesSummary GROUP BY SeqNo
            ) S ON POS.SalesID = S.SeqNo;

               update a SET a.Cost=isnull(b.Cost,0),a.isUpload=1
            from dbo.POSSalesSummary a
            inner join dbo.InventoryLedgerDeduct b
	            on a.BranchCode=b.Branch
	            and a.SalesID=b.SalesID
            WHERE a.BranchCode=@parmbranchcode
            and a.DateOrder=@parmtransdate
        END;

        UPDATE ReInventoryMonitoring SET isDeducted = 1,DateTimeDeducted=GETDATE()  
        WHERE BranchCode = @parmbranchcode AND DateExecute = @parmtransdate;

		INSERT INTO HistoryLogs (UserID,DateExecute,ActionLogs,BranchCode) 
		VALUES('System',GETDATE(),'Deduct Inventory',@parmbranchcode)
            

        COMMIT TRAN;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH;

    DROP TABLE #SalesSummary;
END;