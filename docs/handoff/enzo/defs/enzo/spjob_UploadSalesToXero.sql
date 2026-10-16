--SERVES AS DAILY TRANSACTION UPLOAD exec spjob_UploadSalesToXero '2026-05-25'
CREATE PROC [dbo].[spjob_UploadSalesToXero]
	@parmdate date
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON; -- Automatically rolls back transaction if a severe error occurs

	BEGIN TRY
		BEGIN TRAN;

		---------------------------------------------------------------------------
		--HRI --SERVE AS DAILY SWEEPER, UPLOAD ALL SALES ITEMS IF isUpload=0
		---------------------------------------------------------------------------
		DELETE FROM POSSalesSummary WHERE BranchCode='000' AND isUpload=0 --DateOrder=@parmdate   
					 
		INSERT INTO [dbo].[POSSalesSummary] ([BranchCode],[ProductCode],[Description],[Category]
				   ,[ProcessedBy],[QtySold],[Subtotal],[TotalAmount],[Status],[isVat],[DateOrder]
				   ,[isUpload],[MachineUsed],[Cost])
		 SELECT LTRIM(RTRIM(a.BranchCode)) as BranchCode,LTRIM(RTRIM(a.ProductCode)) as ProductCode
			,LTRIM(RTRIM(a.Description)) as Description,LTRIM(RTRIM(b.Description))  as Category
			,LTRIM(RTRIM(a.ProcessedBy)) as ProcessedBy,SUM(a.QtySold) as QtySold
			,SUM(a.SubTotal) as Subtotal,SUM(a.TotalAmount) as  TotalAmount 
			,LTRIM(RTRIM(a.Status)) as Status,LTRIM(RTRIM(b.isVat)) as isVat
			,CAST(a.DateOrder as date) as DateOrder,0,LTRIM(RTRIM(a.MachineUsed)) as MachineUsed
			,SUM(a.QtySold*isnull(a.Cost,0)) / SUM(nullif(a.QtySold,0)) as AverageCost
			FROM BatchSalesDetails as a
				INNER JOIN ProductCategory as b 
				ON a.CategoryCode=b.ProductCategoryID
			WHERE a.BranchCode='000' --003
			AND a.Status='SOLD'
			AND a.isUpload=0
			--AND a.ProcessedBy=@parmclosedby--'12/16/2019'
			--AND CAST(a.DateOrder as date)=@parmdate
			GROUP BY a.BranchCode ,a.ProductCode,a.ProcessedBy,a.Description,a.Status --,a.isUpload
					,b.Description,b.isVat,a.MachineUsed,CAST(a.DateOrder as date)
			ORDER BY CAST(a.DateOrder as date)
		
		UPDATE BatchSalesDetails 
		SET isUpload=1
		WHERE BranchCode='000' and Status='SOLD' and isUpload=0
		---------------------------------------------------------------------------
		-- 1. SYNC POSZReadingTransactions
		---------------------------------------------------------------------------
		DELETE FROM [ITCOREPOSENZO].[dbo].[POSZReadingTransactions] 
		WHERE CAST(DateExecute as date) = @parmdate;

		INSERT INTO [ITCOREPOSENZO].[dbo].[POSZReadingTransactions] (
			[BranchCode], [CounterNo], [TransactionNo], [MachineUsed], [BeginningBalance], 
			[Debit], [Credit], [EndingBalance], [BeginningSINo], [EndingSINo], 
			[BeginningReturnTransNo], [EndingReturnTransNo], [SoldItems], [CancelledItems], 
			[VoidItems], [ReturnedItems], [VatItems], [DiscountItems], [SCDiscItems], 
			[PWDDiscItems], [RegDiscItems], [TotalCashSales], [TotalCreditSales], [TotalSales], 
			[TotalCancelledSales], [TotalVoidSales], [TotalReturnedSales], [TotalDiscount], 
			[TotalSCDiscount], [TotalPWDDiscount], [TotalRegDiscount], [TotalVatSales], 
			[VatExemptSale], [VatableSale], [VatInput], [ZeroRatedSale], [VatAdjustment], 
			[DateExecute], [ExecuteBy], [TotalNetSales], [isUpload]
		)
		SELECT 
			[BranchCode], [CounterNo], [TransactionNo], [MachineUsed], [BeginningBalance], 
			[Debit], [Credit], [EndingBalance], [BeginningSINo], [EndingSINo], 
			[BeginningReturnTransNo], [EndingReturnTransNo], [SoldItems], [CancelledItems], 
			[VoidItems], [ReturnedItems], [VatItems], [DiscountItems], [SCDiscItems], 
			[PWDDiscItems], [RegDiscItems], [TotalCashSales], [TotalCreditSales], [TotalSales], 
			[TotalCancelledSales], [TotalVoidSales], [TotalReturnedSales], [TotalDiscount], 
			[TotalSCDiscount], [TotalPWDDiscount], [TotalRegDiscount], [TotalVatSales], 
			[VatExemptSale], [VatableSale], [VatInput], [ZeroRatedSale], [VatAdjustment], 
			[DateExecute], [ExecuteBy], [TotalNetSales], 0
		FROM [dbo].[POSZReadingTransactions] WITH(NOLOCK)  
		WHERE CAST(DateExecute as date) = @parmdate;

		---------------------------------------------------------------------------
		-- 2. SYNC SalesDiscount
		---------------------------------------------------------------------------
		DELETE FROM [ITCOREPOSENZO].[dbo].[SalesDiscount] 
		WHERE CAST(DateExecute as date) = @parmdate;

		INSERT INTO [ITCOREPOSENZO].[dbo].[SalesDiscount] (
			[BranchCode], [TransactionNo], [OrderNo], [CashierTransNo], [DiscountType], 
			[DiscountAmount], [VatAdjustment], [DiscName], [DiscIDNo], [DiscRemarks], 
			[Cashier], [MachineUsed], [DateExecute], [isErrorCorrect], [VatExemptAdj], 
			[DiscountPercentage], [VatableSalesDiscAmount], [VatDiscAmount], [VatExDiscAmount]
		)
		SELECT
			[BranchCode], [TransactionNo], [OrderNo], [CashierTransNo], [DiscountType], 
			[DiscountAmount], [VatAdjustment], [DiscName], [DiscIDNo], [DiscRemarks], 
			[Cashier], [MachineUsed], [DateExecute], [isErrorCorrect], [VatExemptAdj], 
			[DiscountPercentage], [VatableSalesDiscAmount], [VatDiscAmount], [VatExDiscAmount]
		FROM [dbo].[SalesDiscount] WITH(NOLOCK)  
		WHERE CAST(DateExecute as date) = @parmdate;

		---------------------------------------------------------------------------
		-- 3. SYNC POSSalesSummary (FIXED MISSING DB PREFIX)
		---------------------------------------------------------------------------
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
			WHERE CAST(aa.DateOrder AS date) = @parmdate
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
				WHERE CAST(aa.DateOrder AS date) = @parmdate
					AND ISNULL(aa.Category, '') COLLATE SQL_Latin1_General_CP1_CI_AS
					<> ISNULL(bb.Category, '') COLLATE SQL_Latin1_General_CP1_CI_AS;
		END



		DELETE FROM [ITCOREPOSENZO].[dbo].[POSSalesSummary] 
		WHERE CAST(DateOrder as date) = @parmdate;

		INSERT INTO [ITCOREPOSENZO].[dbo].[POSSalesSummary] (
			[BranchCode], [ProductCode], [Description], [Category], [ProcessedBy], 
			[QtySold], [Subtotal], [TotalAmount], [Status], [isVat], [DateOrder], 
			[isUpload], [MachineUsed], [Cost]
		)
		SELECT 
			[BranchCode], [ProductCode], [Description], [Category], [ProcessedBy], 
			[QtySold], [Subtotal], [TotalAmount], [Status], [isVat], [DateOrder], 
			0, [MachineUsed], [Cost]
		FROM [dbo].[POSSalesSummary] WITH(NOLOCK) 
		WHERE CAST(DateOrder as date) = @parmdate;   

		---------------------------------------------------------------------------
		-- 4. UPDATE XERO INTEGRATION FIELDS
		---------------------------------------------------------------------------
		DECLARE @update bigint = 0, 
				@nullcount bigint = 0, 
				@checknullcount bigint = 0;
	 
		SELECT TOP(1) @update = COUNT(LastExecute) FROM [ITCOREPOSENZO].[dbo].UpdateFieldMonitoring WITH(NOLOCK);
		
		-- FIXED: ISNULL check changed to standard IS NULL
		SELECT TOP(1) @nullcount = COUNT(BranchCode) 
		FROM [ITCOREPOSENZO].[dbo].POSSalesSummary WITH(NOLOCK) 
		WHERE TotalDiscount IS NULL 
		  AND CAST(DateOrder as date) = @parmdate;

		IF(@nullcount > 0)
		BEGIN
			-- FIXED: Used alias "p" in the UPDATE clause to prevent cross-join corruption
			UPDATE p 
			SET InvoiceNo = Concat(RIGHT(b.BeginningSINo, 6),'-',RIGHT(b.EndingSINo, 6),'_',Replace(convert(varchar, p.DateOrder, 101),'/','')),
				TaxType = CASE WHEN p.isvat = 1 THEN 'TAX003' ELSE 'TAX013' END,
				TranDate = convert(varchar, p.DateOrder, 101),
				AccountCode = g.Groups,
				TotalDiscount = ISNULL((b.TotalSCDiscount + b.TotalPWDDiscount + b.TotalRegDiscount),0.00),
				VatAdjustment = ISNULL(b.VatAdjustment,0.00),
				-- FIXED: Added ITCOREPOSENZO prefix to the subquery
				VatDiscAmount = (SELECT top(1) ISNULL(sum(VatDiscAmount),0.00) 
								 FROM [ITCOREPOSENZO].[dbo].SalesDiscount d WITH(NOLOCK)
								 WHERE d.branchcode = p.branchcode AND d.DateExecute = p.DateOrder AND d.machineused = p.machineused),
				ItemCode = g.ItemCode
			FROM [ITCOREPOSENZO].[dbo].POSSalesSummary p 
			LEFT JOIN [ITCOREPOSENZO].[dbo].GroupCategory g WITH(NOLOCK) ON g.Description = p.Category
			LEFT JOIN [ITCOREPOSENZO].[dbo].POSZReadingTransactions b WITH(NOLOCK) ON p.BranchCode = b.BranchCode 
				AND p.DateOrder = b.DateExecute
				AND p.MachineUsed = b.MachineUsed
			WHERE CAST(p.DateOrder as date) = @parmdate 
			  AND p.isUpload = 0 
			  AND p.TranDate IS NULL;
		END

		---------------------------------------------------------------------------
		-- 5. UPDATE MONITORING TABLE
		---------------------------------------------------------------------------
		IF(@update > 1)
		BEGIN
			-- Note: If this table has multiple rows, this updates ALL of them. 
			-- Usually this table should only have 1 config row.
			UPDATE [ITCOREPOSENZO].[dbo].UpdateFieldMonitoring 
			SET LastExecute = GETDATE(), RowNumber = @nullcount;
		END
		ELSE
		BEGIN
			INSERT INTO [ITCOREPOSENZO].[dbo].UpdateFieldMonitoring(LastExecute, RowNumber, RowNotUpdated, DateExecute)
			SELECT @parmdate, @nullcount, @checknullcount, convert(varchar, GETDATE(), 101);
		END

		COMMIT TRAN;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
			ROLLBACK TRAN;
			
		-- This throws the error back to the SQL Agent Job so you get a red 'Failed' alert
		THROW; 
	END CATCH
END