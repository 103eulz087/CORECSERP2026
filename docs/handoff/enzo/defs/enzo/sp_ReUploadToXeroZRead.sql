CREATE PROCEDURE [dbo].[sp_ReUploadToXeroZRead] --exec sp_ReUploadToXero '03/01/2026','04/07/2026'
    @StartDate DATE,
    @EndDate   DATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON; -- Guarantees automatic rollback if a timeout or error occurs
	BEGIN TRY
	BEGIN TRAN;

	SET @StartDate = '2026-03-01';
	SET @EndDate = '2028-03-01';	
	
	IF OBJECT_ID('tempdb..#BranchNotUploaded') IS NOT NULL DROP TABLE #BranchNotUploaded;
		
	 CREATE TABLE #BranchNotUploaded (
        DateOrder DATE,
        BranchCode VARCHAR(50) COLLATE SQL_Latin1_General_CP1_CI_AS,
        MachineUsed VARCHAR(50) COLLATE SQL_Latin1_General_CP1_CI_AS,
        NextDay DATE -- Used for super-fast index scanning
    );
	
	-------------------------------------------------------------
    -- UPLOADED SALES SUMMARY WITHOUT ZREAD TRANSACTION REPORT
    -----------------------------------------------------------
    INSERT INTO #BranchNotUploaded (DateOrder, BranchCode, MachineUsed, NextDay)
    SELECT DISTINCT 
        a.DateOrder, 
        a.BranchCode, 
        a.MachineUsed,
        DATEADD(day, 1, a.DateOrder) -- Pre-calculate tomorrow's date for range joins
    FROM CORECSERP_001.dbo.POSSalesSummary a WITH(NOLOCK)
    WHERE a.DateOrder BETWEEN @StartDate AND @EndDate
      AND a.BranchCode NOT IN ('888','000') --HRI NOT INCLUDED
      AND NOT EXISTS (
          SELECT 1
          FROM ITCOREPOSENZO.dbo.POSZReadingTransactions b WITH(NOLOCK)
          WHERE a.DateOrder = b.DateExecute
            AND a.BranchCode = b.BranchCode COLLATE SQL_Latin1_General_CP1_CI_AS
            AND a.MachineUsed = b.MachineUsed COLLATE SQL_Latin1_General_CP1_CI_AS
      );
	  --SELECT * FROM #BranchNotUploaded
    -- Create an index on the temp table to make the deletes/inserts lightning fast
    CREATE CLUSTERED INDEX CIX_TempBranch ON #BranchNotUploaded(DateOrder, BranchCode, MachineUsed);
	--SELECT * FROM  #BranchNotUploaded

	   DELETE t  --DELETE IF EXISTS
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
        -- 4. AFTER INSERTED TO ZREAD TABLE IN ITCOREPOSENZO DB, UPDATE POSSALESSUMMARY AGAIN
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
			isUpload=0,
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
        WHERE p.isUpload = 1; --SINCE IT IS ALREADY UPLOADED
          --AND p.TranDate IS NULL;

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