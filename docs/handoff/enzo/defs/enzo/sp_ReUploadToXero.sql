CREATE PROCEDURE [dbo].[sp_ReUploadToXero] --exec sp_ReUploadToXero '03/01/2026','04/07/2026'
    @StartDate DATE,
    @EndDate   DATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON; -- Guarantees automatic rollback if a timeout or error occurs
	SET @StartDate = '2026-03-01';
	SET @EndDate = '2028-03-01';
    ------------------------------------------------------------
    -- STEP 1: PREPARE DATA (OUTSIDE THE TRANSACTION!)
    ------------------------------------------------------------
    -- By building the temp table before we lock the database, we save massive amounts of time.
    IF OBJECT_ID('tempdb..#BranchNotUploaded') IS NOT NULL DROP TABLE #BranchNotUploaded;

    -- CRITICAL FIX: Explicitly set the collation on the temp table to match your destination DB.
    -- This prevents the need for COLLATE in your JOINs and restores your indexes!
    CREATE TABLE #BranchNotUploaded (
        DateOrder DATE,
        BranchCode VARCHAR(50) COLLATE SQL_Latin1_General_CP1_CI_AS,
        MachineUsed VARCHAR(50) COLLATE SQL_Latin1_General_CP1_CI_AS,
        NextDay DATE -- Used for super-fast index scanning
    );

    INSERT INTO #BranchNotUploaded (DateOrder, BranchCode, MachineUsed, NextDay)
    SELECT DISTINCT 
        a.DateOrder, 
        a.BranchCode, 
        a.MachineUsed,
        DATEADD(day, 1, a.DateOrder) -- Pre-calculate tomorrow's date for range joins
    FROM CORECSERP_001.dbo.POSSalesSummary a WITH(NOLOCK)
    WHERE a.DateOrder BETWEEN @StartDate AND @EndDate
      AND a.BranchCode NOT IN ('888','000')
      AND NOT EXISTS (
          SELECT 1
          FROM ITCOREPOSENZO.dbo.POSSalesSummary b WITH(NOLOCK)
          WHERE a.DateOrder = b.DateOrder
            AND a.BranchCode = b.BranchCode COLLATE SQL_Latin1_General_CP1_CI_AS
            AND a.MachineUsed = b.MachineUsed COLLATE SQL_Latin1_General_CP1_CI_AS
      );

    -- Create an index on the temp table to make the deletes/inserts lightning fast
    CREATE CLUSTERED INDEX CIX_TempBranch ON #BranchNotUploaded(DateOrder, BranchCode, MachineUsed);

    ------------------------------------------------------------
    -- STEP 2: EXECUTE CHANGES
    ------------------------------------------------------------
    BEGIN TRY
        -- Start the transaction ONLY when we are ready to write data
        BEGIN TRANSACTION;

        ------------------------------------------------------------
        -- 1. SYNC POSZReadingTransactions
        ------------------------------------------------------------
        DELETE t
        FROM ITCOREPOSENZO.dbo.POSZReadingTransactions t
        JOIN #BranchNotUploaded u
          -- CRITICAL FIX: SARGable date range instead of CAST(). This uses your index!
          ON t.DateExecute >= u.DateOrder AND t.DateExecute < u.NextDay
         AND t.BranchCode = u.BranchCode COLLATE SQL_Latin1_General_CP1_CI_AS
         AND t.MachineUsed = u.MachineUsed COLLATE SQL_Latin1_General_CP1_CI_AS;

        INSERT INTO ITCOREPOSENZO.dbo.POSZReadingTransactions (
            BranchCode, CounterNo, TransactionNo, MachineUsed, BeginningBalance,
            Debit, Credit, EndingBalance, BeginningSINo, EndingSINo,
            BeginningReturnTransNo, EndingReturnTransNo, SoldItems, CancelledItems,
            VoidItems, ReturnedItems, VatItems, DiscountItems, SCDiscItems,
            PWDDiscItems, RegDiscItems, TotalCashSales, TotalCreditSales, TotalSales,
            TotalCancelledSales, TotalVoidSales, TotalReturnedSales, TotalDiscount,
            TotalSCDiscount, TotalPWDDiscount, TotalRegDiscount, TotalVatSales,
            VatExemptSale, VatableSale, VatInput, ZeroRatedSale, VatAdjustment,
            DateExecute, ExecuteBy, TotalNetSales, isUpload
        )
        SELECT
            s.BranchCode, s.CounterNo, s.TransactionNo, s.MachineUsed, s.BeginningBalance,
            s.Debit, s.Credit, s.EndingBalance, s.BeginningSINo, s.EndingSINo,
            s.BeginningReturnTransNo, s.EndingReturnTransNo, s.SoldItems, s.CancelledItems,
            s.VoidItems, s.ReturnedItems, s.VatItems, s.DiscountItems, s.SCDiscItems,
            s.PWDDiscItems, s.RegDiscItems, s.TotalCashSales, s.TotalCreditSales, s.TotalSales,
            s.TotalCancelledSales, s.TotalVoidSales, s.TotalReturnedSales, s.TotalDiscount,
            s.TotalSCDiscount, s.TotalPWDDiscount, s.TotalRegDiscount, s.TotalVatSales,
            s.VatExemptSale, s.VatableSale, s.VatInput, s.ZeroRatedSale, s.VatAdjustment,
            s.DateExecute, s.ExecuteBy, s.TotalNetSales, 0
        FROM CORECSERP_001.dbo.POSZReadingTransactions s WITH(NOLOCK)
        JOIN #BranchNotUploaded u
          ON s.DateExecute >= u.DateOrder AND s.DateExecute < u.NextDay
         AND s.BranchCode = u.BranchCode
         AND s.MachineUsed = u.MachineUsed;

        ------------------------------------------------------------
        -- 2. SYNC SalesDiscount
        ------------------------------------------------------------
        DELETE t
        FROM ITCOREPOSENZO.dbo.SalesDiscount t
        JOIN #BranchNotUploaded u
          ON t.DateExecute >= u.DateOrder AND t.DateExecute < u.NextDay
         AND t.BranchCode = u.BranchCode COLLATE SQL_Latin1_General_CP1_CI_AS
         AND t.MachineUsed = u.MachineUsed COLLATE SQL_Latin1_General_CP1_CI_AS;

        INSERT INTO ITCOREPOSENZO.dbo.SalesDiscount (
            BranchCode, TransactionNo, OrderNo, CashierTransNo, DiscountType,
            DiscountAmount, VatAdjustment, DiscName, DiscIDNo, DiscRemarks,
            Cashier, MachineUsed, DateExecute, isErrorCorrect, VatExemptAdj,
            DiscountPercentage, VatableSalesDiscAmount, VatDiscAmount, VatExDiscAmount
        )
        SELECT
            s.BranchCode, s.TransactionNo, s.OrderNo, s.CashierTransNo, s.DiscountType,
            s.DiscountAmount, s.VatAdjustment, s.DiscName, s.DiscIDNo, s.DiscRemarks,
            s.Cashier, s.MachineUsed, s.DateExecute, s.isErrorCorrect, s.VatExemptAdj,
            s.DiscountPercentage, s.VatableSalesDiscAmount, s.VatDiscAmount, s.VatExDiscAmount
        FROM CORECSERP_001.dbo.SalesDiscount s WITH(NOLOCK)
        JOIN #BranchNotUploaded u
          ON s.DateExecute >= u.DateOrder AND s.DateExecute < u.NextDay
         AND s.BranchCode = u.BranchCode
         AND s.MachineUsed = u.MachineUsed;

        ------------------------------------------------------------
        -- 3. SYNC POSSalesSummary
        ------------------------------------------------------------
       -- CHECK IF UPDATE IS NEEDED BEFORE EXECUTING
		IF EXISTS (
			SELECT 1
			FROM [dbo].POSSalesSummary aa
			INNER JOIN (
				SELECT a.ProductCode,
					   a.Description,
					   b.Description AS Category,
					   a.isVat
				FROM [dbo].Products a
				INNER JOIN [dbo].ProductCategory b
					ON a.ProductCategoryCode = b.ProductCategoryID
				WHERE a.BranchCode = '888' 
				
			) bb
			ON aa.ProductCode = bb.ProductCode COLLATE SQL_Latin1_General_CP1_CI_AS
			WHERE  aa.DateOrder BETWEEN @StartDate AND @EndDate
				AND ISNULL(aa.Category, '') COLLATE SQL_Latin1_General_CP1_CI_AS
				<> ISNULL(bb.Category, '') COLLATE SQL_Latin1_General_CP1_CI_AS
		)
		BEGIN
			-- Records exist - proceed with update
			WITH proddesccat AS (
						SELECT a.ProductCode,
							   a.Description,
							   b.Description AS Category,
							   a.isVat
						FROM [dbo].Products a
						INNER JOIN [dbo].ProductCategory b
							ON a.ProductCategoryCode = b.ProductCategoryID
						WHERE a.BranchCode = '888'
			)
			UPDATE aa
				SET aa.Category = bb.Category,aa.isVat=bb.isVat
				FROM [dbo].POSSalesSummary aa
					INNER JOIN proddesccat bb
					ON aa.ProductCode = bb.ProductCode COLLATE SQL_Latin1_General_CP1_CI_AS
				WHERE aa.DateOrder BETWEEN @StartDate AND @EndDate
					AND ISNULL(aa.Category, '') COLLATE SQL_Latin1_General_CP1_CI_AS
					<> ISNULL(bb.Category, '') COLLATE SQL_Latin1_General_CP1_CI_AS;
		END



        DELETE t
        FROM ITCOREPOSENZO.dbo.POSSalesSummary t
        JOIN #BranchNotUploaded u
          ON t.DateOrder = u.DateOrder -- Since POSSalesSummary.DateOrder is already a DATE, straight '=' is fine
         AND t.BranchCode = u.BranchCode COLLATE SQL_Latin1_General_CP1_CI_AS
         AND t.MachineUsed = u.MachineUsed COLLATE SQL_Latin1_General_CP1_CI_AS;

        INSERT INTO ITCOREPOSENZO.dbo.POSSalesSummary (
            BranchCode, ProductCode, Description, Category, ProcessedBy,
            QtySold, Subtotal, TotalAmount, Status, isVat, DateOrder,
            isUpload, MachineUsed, Cost
        )
        SELECT
            s.BranchCode, s.ProductCode, s.Description, s.Category, s.ProcessedBy,
            s.QtySold, s.Subtotal, s.TotalAmount, s.Status, s.isVat, s.DateOrder,
            0, s.MachineUsed, s.Cost
        FROM CORECSERP_001.dbo.POSSalesSummary s WITH(NOLOCK)
        JOIN #BranchNotUploaded u
          ON s.DateOrder = u.DateOrder
         AND s.BranchCode = u.BranchCode
         AND s.MachineUsed = u.MachineUsed;

        ------------------------------------------------------------
        -- 4. UPDATE XERO INTEGRATION FIELDS
        ------------------------------------------------------------
        UPDATE p
        SET InvoiceNo = CONCAT(RIGHT(b.BeginningSINo,6),'-',RIGHT(b.EndingSINo,6),'_',REPLACE(CONVERT(varchar,p.DateOrder,101),'/','')),
            TaxType = CASE WHEN p.isVat=1 THEN 'TAX003' ELSE 'TAX013' END,
            TranDate = CONVERT(varchar,p.DateOrder,101),
            AccountCode = g.Groups,
            TotalDiscount = ISNULL(b.TotalSCDiscount + b.TotalPWDDiscount + b.TotalRegDiscount,0.00),
            VatAdjustment = ISNULL(b.VatAdjustment,0.00),
            VatDiscAmount = (
                -- Optimized subquery
                SELECT ISNULL(SUM(d.VatDiscAmount),0.00)
                FROM ITCOREPOSENZO.dbo.SalesDiscount d WITH(NOLOCK)
                WHERE d.BranchCode = p.BranchCode COLLATE SQL_Latin1_General_CP1_CI_AS
                  AND d.DateExecute >= p.DateOrder AND d.DateExecute < DATEADD(day, 1, p.DateOrder)
                  AND d.MachineUsed = p.MachineUsed COLLATE SQL_Latin1_General_CP1_CI_AS
            ),
            ItemCode = g.ItemCode
        FROM ITCOREPOSENZO.dbo.POSSalesSummary p
        JOIN #BranchNotUploaded u
          ON p.DateOrder = u.DateOrder
         AND p.BranchCode = u.BranchCode COLLATE SQL_Latin1_General_CP1_CI_AS
         AND p.MachineUsed = u.MachineUsed COLLATE SQL_Latin1_General_CP1_CI_AS
        LEFT JOIN ITCOREPOSENZO.dbo.GroupCategory g WITH(NOLOCK) ON g.Description = p.Category
        LEFT JOIN ITCOREPOSENZO.dbo.POSZReadingTransactions b WITH(NOLOCK)
               ON p.BranchCode = b.BranchCode COLLATE SQL_Latin1_General_CP1_CI_AS
              AND p.DateOrder = CAST(b.DateExecute AS DATE) 
              AND p.MachineUsed = b.MachineUsed COLLATE SQL_Latin1_General_CP1_CI_AS
        WHERE p.isUpload = 0
          AND p.TranDate IS NULL;

        ------------------------------------------------------------
        -- 5. UPDATE MONITORING TABLE
        ------------------------------------------------------------
        DECLARE @nullcount bigint;

        SELECT @nullcount = COUNT(*)
        FROM ITCOREPOSENZO.dbo.POSSalesSummary p WITH(NOLOCK)
        JOIN #BranchNotUploaded u
          ON p.DateOrder = u.DateOrder
         AND p.BranchCode = u.BranchCode COLLATE SQL_Latin1_General_CP1_CI_AS
         AND p.MachineUsed = u.MachineUsed COLLATE SQL_Latin1_General_CP1_CI_AS
        WHERE p.TotalDiscount IS NULL;

        IF EXISTS (SELECT 1 FROM ITCOREPOSENZO.dbo.UpdateFieldMonitoring WITH(UPDLOCK, HOLDLOCK))
            UPDATE ITCOREPOSENZO.dbo.UpdateFieldMonitoring
            SET LastExecute = GETDATE(), RowNumber = @nullcount;
        ELSE
            INSERT INTO ITCOREPOSENZO.dbo.UpdateFieldMonitoring(LastExecute, RowNumber, RowNotUpdated, DateExecute)
            VALUES (GETDATE(), @nullcount, 0, CONVERT(varchar,GETDATE(),101));

        ------------------------------------------------------------
        -- Commit if all succeeded
        ------------------------------------------------------------
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE(), @ErrSeverity INT = ERROR_SEVERITY();
        RAISERROR(@ErrMsg, @ErrSeverity, 1);
    END CATCH
END