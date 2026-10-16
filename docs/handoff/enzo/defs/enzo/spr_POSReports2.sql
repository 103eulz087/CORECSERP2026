

CREATE PROCEDURE [dbo].[spr_POSReports2]
    @parmbrcode       varchar(5),
    @datefrom         date,
    @dateto           date,
    @parmprocessby    varchar(20),
    @parmoption       int,
    @parmpercashier   bit,
    @parmispermachine bit,
    @parmmachinename  varchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @dateToPlus date = DATEADD(day, 1, @dateto);
-- reusable predicate via inline logic
    DECLARE @useMachine bit = @parmispermachine;
    DECLARE @useCashier bit = @parmpercashier;
	IF (@parmoption = 1)
	BEGIN
		SELECT
			Category,
			SUM(QtySold)            AS QtySold,
			SUM(TotalAmount)        AS TotalAmount,
			isVat
		FROM dbo.POSSalesSummary2
		WHERE BranchCode = @parmbrcode
		  AND DateOrder >= @datefrom
		  AND DateOrder <  @dateToPlus
		  AND (@useMachine = 0 OR MachineUsed = @parmmachinename)
		  AND (@useCashier = 0 OR ProcessedBy = @parmprocessby)
		GROUP BY Category, isVat
	END
	ELSE IF (@parmoption = 2)
	BEGIN
		SELECT
			isVat,
			SUM(TotalAmount) AS TotalAmount
		FROM dbo.POSSalesSummary2
		WHERE BranchCode = @parmbrcode
		  AND DateOrder >= @datefrom
		  AND DateOrder <  @dateToPlus
		  AND (@useMachine = 0 OR MachineUsed = @parmmachinename)
		  AND (@useCashier = 0 OR ProcessedBy = @parmprocessby)
		GROUP BY isVat
	END
	ELSE IF (@parmoption = 3)
	BEGIN
		SELECT
			a.ProductCode,
			a.Category,
			a.Description,
			SUM(a.QtySold) AS Qty,
			a.Cost,
			b.SellingPrice,
			SUM(a.QtySold * a.Cost) AS TotalCost,
			SUM(a.SubTotal)         AS TotalAmount,
			SUM(a.SubTotal) - SUM(a.QtySold * a.Cost) AS Profit,
			a.isVat
		FROM dbo.POSSalesSummary2 a
		INNER JOIN dbo.Products b
			ON a.BranchCode = b.BranchCode
		   AND a.ProductCode = b.ProductCode
		WHERE a.BranchCode = @parmbrcode
		  AND a.DateOrder >= @datefrom
		  AND a.DateOrder <  @dateToPlus
		  AND (@useMachine = 0 OR a.MachineUsed = @parmmachinename)
		  AND (@useCashier = 0 OR a.ProcessedBy = @parmprocessby)
		GROUP BY
			a.ProductCode, a.Category, a.Description,
			a.isVat, b.SellingPrice, a.Cost
	END
	ELSE IF (@parmoption = 4)
	BEGIN
		SELECT *
		FROM dbo.SalesTransactionSummary2
		WHERE BranchCode = @parmbrcode
		  AND DateOpen >= @datefrom
		  AND DateOpen <  @dateToPlus
		  AND (@useMachine = 0 OR MachineUsed = @parmmachinename)
		  AND (@useCashier = 0 OR UserID = @parmprocessby)
	END
	ELSE IF (@parmoption = 6)
	BEGIN
		SELECT
			DateExecute, BranchCode, CounterNo, MachineUsed,
			BeginningBalance, Credit, EndingBalance,
			BeginningSINo, EndingSINo,
			SoldItems, ReturnedItems,
			TotalCashSales, TotalCreditSales,
			TotalSales, TotalNetSales,
			VatExemptSale, VatableSale, VatInput,
			ExecuteBy
		FROM dbo.POSZReadingTransactions2
		WHERE BranchCode = @parmbrcode
		  AND DateExecute >= @datefrom
		  AND DateExecute <  @dateToPlus
		  AND (@useMachine = 0 OR MachineUsed = @parmmachinename)
		ORDER BY DateExecute
	END
	ELSE IF (@parmoption IN (7,8,9))
	BEGIN
		DECLARE @DiscountType varchar(20) =
			CASE @parmoption
				WHEN 7 THEN 'SENIOR'
				WHEN 8 THEN 'PWD'
				WHEN 9 THEN 'REGULAR'
			END;

		SELECT *
		FROM dbo.SalesDiscount2
		WHERE DiscountType = @DiscountType
		  AND isErrorCorrect = 0
		  AND BranchCode = @parmbrcode
		  AND DateExecute >= @datefrom
		  AND DateExecute <  @dateToPlus
		  AND (@useMachine = 0 OR MachineUsed = @parmmachinename)
		  AND (@useCashier = 0 OR Cashier = @parmprocessby)
	END
END
