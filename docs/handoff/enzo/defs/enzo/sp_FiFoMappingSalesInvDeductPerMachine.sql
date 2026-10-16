
CREATE PROCEDURE [dbo].[sp_FiFoMappingSalesInvDeductPerMachine]  --exec [sp_FiFoMappingSalesInvDeduct] '03/24/2026','035','','','2'
    @parmtransdate DATE,
    @parmbranchcode CHAR(3),
   @parmmachineused varchar(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON; -- FIXED: Guarantees full rollback if a severe error occurs
    
    -- 1. #Temp tables for massive speed boosts (FIXED: Floats to Decimals)
    CREATE TABLE #SalesSummary (
        rowno INT IDENTITY(1,1) PRIMARY KEY,
        SeqNo BIGINT,
        Branch CHAR(3) collate SQL_Latin1_General_CP1_CI_AS,
        DateOrder DATE,
        ParentProduct CHAR(5) collate SQL_Latin1_General_CP1_CI_AS,
        ChildProduct CHAR(5) collate SQL_Latin1_General_CP1_CI_AS,
        QtyBase DECIMAL(18,3), 
        QtySold DECIMAL(18,3),
        TempCost DECIMAL(18,3)
    );

    BEGIN TRY
        BEGIN TRAN;
       
        --IF EXISTS (SELECT 1 
        --            FROM dbo.ConversionSummary WITH(NOLOCK)
        --            WHERE BranchCode=@parmbranchcode 
        --            AND CAST(DateConverted as date)=CAST(GETDATE() as date)
        --            AND isConfirm=0 and isErrorCorrect=0
        --            )
        --BEGIN
        --    RAISERROR('You still have Pending/For Confirmation Conversion', 16, 1);
        --    -- ROLLBACK TRAN handled in CATCH block due to RAISERROR severity 16
        --END
		
		--IF NOT EXISTS (SELECT 1 
  --                  FROM dbo.POSSalesSummary WITH(NOLOCK)
  --                  WHERE BranchCode=@parmbranchcode 
		--			and MachineUsed=@parmmachineused
  --                  AND CAST(DateOrder as date)=@parmtransdate
  --                  )
  --      BEGIN
  --          RAISERROR('No Sales Item uploaded.. Please coordinate your cashier to upload it', 16, 1);
  --          -- ROLLBACK TRAN handled in CATCH block due to RAISERROR severity 16
  --      END
        -- 2. Populate Sales Data
       INSERT INTO #SalesSummary (SeqNo, Branch, DateOrder, ParentProduct, QtySold)
            SELECT SalesID, BranchCode, DateOrder, ProductCode, QtySold
            FROM POSSalesSummary WITH(NOLOCK)
            WHERE ISNULL(isUpload, 0) = 0 
              AND DateOrder = @parmtransdate 
			  and MachineUsed=@parmmachineused
              AND BranchCode = @parmbranchcode;

        -- 3. Apply BOM/Child Mapping
        UPDATE S
        SET S.ChildProduct = M.ChildProductCode,
            S.QtyBase = M.Quantity
        FROM #SalesSummary S
        INNER JOIN InventoryMapping M ON S.ParentProduct = M.ParentProductCode;

        UPDATE #SalesSummary 
        SET ChildProduct = ParentProduct, QtyBase = 1 
        WHERE ChildProduct IS NULL;

        ----------------------------------------------------------------
        CREATE TABLE #TempResults (
            ProductCode CHAR(5),
            ProductName VARCHAR(250),
            QtySold DECIMAL(18,3),
            Available DECIMAL(18,3),
            Variance DECIMAL(18,3),
            Status VARCHAR(20),
			MachineUsed varchar(20)
        );

        -- Execute Analysis
        INSERT INTO #TempResults
        EXEC [dbo].[sp_AnalyzePerMachine] @parmbranchcode,@parmmachineused, @parmtransdate;
		
        INSERT INTO InventorySalesAnalysisPerMachine (BranchCode, DateExecute, ProductCode, ProductName, QtySold, Qtyinv, Status,MachineUsed)
        SELECT @parmbranchcode, @parmtransdate, ProductCode, ProductName, QtySold, Available, Status, @parmmachineused
        FROM #TempResults;

        DROP TABLE #TempResults;
        ----------------------------------------------------------------

        -- 4. THE FIFO LOOP
        DECLARE @CurrentRow INT = 1;
        DECLARE @MaxRow INT = (SELECT ISNULL(MAX(rowno),0) FROM #SalesSummary);
        
        DECLARE @LoopSeqNo BIGINT, @LoopProduct CHAR(5), @LoopQty DECIMAL(18,3);
        DECLARE @CostOutput DECIMAL(18,2), @SellingPrice DECIMAL(18,2); -- FIXED to Decimals

        WHILE (@CurrentRow <= @MaxRow)
        BEGIN
            SELECT 
                @LoopSeqNo = SeqNo,
                @LoopProduct = ChildProduct,
                @LoopQty = (QtyBase * QtySold)
            FROM #SalesSummary 
            WHERE rowno = @CurrentRow;

            SELECT TOP(1) @SellingPrice = SellingPrice 
            FROM Products WITH(NOLOCK) 
            WHERE BranchCode = @parmbranchcode AND ProductCode = @LoopProduct;

            -- EXECUTE ENGINE
            EXEC dbo.sp_SalesQtyToInventoryQtyEODSalesInvDeductPerMachine 
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

        -- 5. POST-PROCESSING
        
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
       

        UPDATE ReInventoryMonitoring 
        SET isDeducted = 1, DateTimeDeducted = @parmtransdate
        WHERE BranchCode = @parmbranchcode AND DateExecute = @parmtransdate;

        INSERT INTO HistoryLogs (UserID, DateExecute, ActionLogs, BranchCode) 
        VALUES ('System', GETDATE(), 'Deduct Inventory LateUpload', @parmbranchcode);

        COMMIT TRAN;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 
            ROLLBACK TRAN;
            
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH;

    -- Safe cleanup (using IF OBJECT_ID is a good habit)
    IF OBJECT_ID('tempdb..#SalesSummary') IS NOT NULL DROP TABLE #SalesSummary;
END;
