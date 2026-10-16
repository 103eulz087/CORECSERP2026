

CREATE PROCEDURE [dbo].[spr_POSReports]
    @parmbrcode       varchar(5),
    @datefrom         varchar(10),
    @dateto           varchar(10),
    @parmprocessby    varchar(20) = NULL,
    @parmoption       int,
    @parmpercashier   bit = 0,
    @parmispermachine bit = 0,
    @parmmachinename  varchar(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    -------------------------------------------------------------------------
    -- 1) Normalize/validate dates once (avoid repeated CAST in WHERE)
    -------------------------------------------------------------------------
    DECLARE @FromDate date = TRY_CONVERT(date, @datefrom, 120);
    DECLARE @ToDate   date = TRY_CONVERT(date, @dateto, 120);

    IF @FromDate IS NULL SET @FromDate = TRY_CONVERT(date, @datefrom);
    IF @ToDate   IS NULL SET @ToDate   = TRY_CONVERT(date, @dateto);

    IF (@FromDate IS NULL OR @ToDate IS NULL)
        THROW 50000, 'Invalid @datefrom/@dateto. Expect a valid date (e.g., yyyy-mm-dd).', 1;

    -- inclusive end-date range handling:
    DECLARE @ToDateExclusive date = DATEADD(day, 1, @ToDate);

    -------------------------------------------------------------------------
    -- 2) Optional filters (avoid branching explosion)
    -------------------------------------------------------------------------
    DECLARE @UseMachine bit =
        IIF(@parmispermachine = 1 AND NULLIF(LTRIM(RTRIM(@parmmachinename)), '') IS NOT NULL, 1, 0);

    DECLARE @UseCashier bit =
        IIF(@parmpercashier = 1 AND NULLIF(LTRIM(RTRIM(@parmprocessby)), '') IS NOT NULL, 1, 0);

    -------------------------------------------------------------------------
    -- 3) Option routing (1 query per option)
    -------------------------------------------------------------------------

    -------------------------------------------------------------------------
    -- (1) GROUPCATEGORY
    -------------------------------------------------------------------------
    IF @parmoption = 1
    BEGIN
        SELECT
            Category,
            SUM(QtySold) AS QtySold,
            SUM(CONVERT(money, TotalAmount)) AS TotalAmount,
            isVat
        FROM dbo.POSSalesSummary WITH (NOLOCK)
        WHERE BranchCode = @parmbrcode
          AND DateOrder >= @FromDate
          AND DateOrder <  @ToDateExclusive
          AND (@UseMachine = 0 OR MachineUsed = @parmmachinename)
          AND (@UseCashier = 0 OR ProcessedBy = @parmprocessby)
        GROUP BY Category, isVat
        OPTION (RECOMPILE);

        RETURN;
    END

    -------------------------------------------------------------------------
    -- (2) FULLTRANSACTION
    -------------------------------------------------------------------------
    IF @parmoption = 2
    BEGIN
        SELECT
            SUM(CONVERT(money, TotalAmount)) AS TotalAmount,
            isVat
        FROM dbo.POSSalesSummary WITH (NOLOCK)
        WHERE BranchCode = @parmbrcode
          AND DateOrder >= @FromDate
          AND DateOrder <  @ToDateExclusive
          AND (@UseMachine = 0 OR MachineUsed = @parmmachinename)
          AND (@UseCashier = 0 OR ProcessedBy = @parmprocessby)
        GROUP BY isVat
        OPTION (RECOMPILE);

        RETURN;
    END

    -------------------------------------------------------------------------
    -- (3) GROUPITEM
    -------------------------------------------------------------------------
    IF @parmoption = 3
    BEGIN
        SELECT
            a.ProductCode,
            a.Category,
            a.Description,
            SUM(a.QtySold) AS Qty,
            a.Cost,
            b.SellingPrice,
            SUM(a.QtySold) * a.Cost AS TotalCost,
            SUM(CONVERT(money, a.SubTotal)) AS TotalAmount,
            SUM(CONVERT(money, a.SubTotal)) - (SUM(a.QtySold) * a.Cost) AS Profit,
            a.isVat
        FROM dbo.POSSalesSummary a WITH (NOLOCK)
        INNER JOIN dbo.Products b WITH (NOLOCK)
            ON  a.BranchCode  = b.BranchCode
            AND a.ProductCode = b.ProductCode
        WHERE a.BranchCode = @parmbrcode
          AND a.DateOrder >= @FromDate
          AND a.DateOrder <  @ToDateExclusive
          AND (@UseMachine = 0 OR a.MachineUsed = @parmmachinename)
          AND (@UseCashier = 0 OR a.ProcessedBy = @parmprocessby)
        GROUP BY
            a.ProductCode, a.Category, a.Description, a.isVat,
            b.SellingPrice, a.Cost
        OPTION (RECOMPILE);

        RETURN;
    END

    -------------------------------------------------------------------------
    -- (4) CASHIERSALES  (kept SELECT * to preserve report shape)
    -------------------------------------------------------------------------
    IF @parmoption = 4
    BEGIN
        SELECT *
        FROM dbo.SalesTransactionSummary WITH (NOLOCK)
        WHERE BranchCode = @parmbrcode
          AND DateOpen >= @FromDate
          AND DateOpen <  @ToDateExclusive
          AND (@UseMachine = 0 OR MachineUsed = @parmmachinename)
          AND (@UseCashier = 0 OR UserID = @parmprocessby)
        OPTION (RECOMPILE);

        RETURN;
    END

    -------------------------------------------------------------------------
    -- (5) XREAD  (TransactionDate appears to be stored in a char/date-like format in older logic)
    -- If TransactionDate is truly date/datetime in your DB, replace this with the DateOpen-style filter.
    -------------------------------------------------------------------------
    IF @parmoption = 5
    BEGIN
        SELECT *
        FROM dbo.SalesTransactionSummary WITH (NOLOCK)
        WHERE BranchCode = @parmbrcode
          AND DateOpen >= @FromDate
          AND DateOpen <  @ToDateExclusive
          AND (@UseMachine = 0 OR MachineUsed = @parmmachinename)
          AND (@UseCashier = 0 OR UserID = @parmprocessby)
        OPTION (RECOMPILE);

        RETURN;
    END

    -------------------------------------------------------------------------
    -- (6) ZREAD (explicit columns maintained from your script)
    -------------------------------------------------------------------------
    IF @parmoption = 6
    BEGIN
        SELECT
            DateExecute, BranchCode, CounterNo, MachineUsed, BeginningBalance, Credit, EndingBalance,
            BeginningSINo, EndingSINo, BeginningReturnTransNo, EndingReturnTransNo, SoldItems, ReturnedItems,
            SCDiscItems, PWDDiscItems, TotalCashSales, TotalCreditSales, TotalSales, TotalReturnedSales,
            TotalSCDiscount, TotalPWDDiscount, TotalRegDiscount, VatExemptSale, VatableSale, VatInput,
            VatAdjustment, TotalNetSales, ExecuteBy
        FROM dbo.POSZReadingTransactions WITH (NOLOCK)
        WHERE BranchCode = @parmbrcode
          AND DateExecute >= @FromDate
          AND DateExecute <  @ToDateExclusive
          AND (@UseMachine = 0 OR MachineUsed = @parmmachinename)
        ORDER BY DateExecute ASC
        OPTION (RECOMPILE);

        RETURN;
    END

    -------------------------------------------------------------------------
    -- (7) SENIOR
    -------------------------------------------------------------------------
    IF @parmoption = 7
    BEGIN
        SELECT *
        FROM dbo.SalesDiscount WITH (NOLOCK)
        WHERE DiscountType = 'SENIOR'
          AND isErrorCorrect = 0
          AND BranchCode = @parmbrcode
          AND DateExecute >= @FromDate
          AND DateExecute <  @ToDateExclusive
          AND (@UseMachine = 0 OR MachineUsed = @parmmachinename)
          AND (@UseCashier = 0 OR Cashier = @parmprocessby)
        OPTION (RECOMPILE);

        RETURN;
    END

    -------------------------------------------------------------------------
    -- (8) PWD
    -------------------------------------------------------------------------
    IF @parmoption = 8
    BEGIN
        SELECT *
        FROM dbo.SalesDiscount WITH (NOLOCK)
        WHERE DiscountType = 'PWD'
          AND isErrorCorrect = 0
          AND BranchCode = @parmbrcode
          AND DateExecute >= @FromDate
          AND DateExecute <  @ToDateExclusive
          AND (@UseMachine = 0 OR MachineUsed = @parmmachinename)
          AND (@UseCashier = 0 OR Cashier = @parmprocessby)
        OPTION (RECOMPILE);

        RETURN;
    END

    -------------------------------------------------------------------------
    -- (9) REGULAR
    -------------------------------------------------------------------------
    IF @parmoption = 9
    BEGIN
        SELECT *
        FROM dbo.SalesDiscount WITH (NOLOCK)
        WHERE DiscountType = 'REGULAR'
          AND isErrorCorrect = 0
          AND BranchCode = @parmbrcode
          AND DateExecute >= @FromDate
          AND DateExecute <  @ToDateExclusive
          AND (@UseMachine = 0 OR MachineUsed = @parmmachinename)
          AND (@UseCashier = 0 OR Cashier = @parmprocessby)
        OPTION (RECOMPILE);

        RETURN;
    END

    -------------------------------------------------------------------------
    -- (10) MERCHANT
    -- Uses COALESCE(TransactionDate, DateAdded) to handle your inconsistent date usage.
    -------------------------------------------------------------------------
    IF @parmoption = 10
    BEGIN
        SELECT *
        FROM dbo.POSMerchantTransactions WITH (NOLOCK)
        WHERE BranchCode = @parmbrcode
          AND COALESCE(CAST(TransactionDate AS datetime2), CAST(DateAdded AS datetime2)) >= CAST(@FromDate AS datetime2)
          AND COALESCE(CAST(TransactionDate AS datetime2), CAST(DateAdded AS datetime2)) <  CAST(@ToDateExclusive AS datetime2)
          AND (@UseMachine = 0 OR MachineUsed = @parmmachinename)
          AND (@UseCashier = 0 OR AddedBy = @parmprocessby)
        OPTION (RECOMPILE);

        RETURN;
    END

    -------------------------------------------------------------------------
    -- (11) REFUND
    -------------------------------------------------------------------------
    IF @parmoption = 11
    BEGIN
        SELECT
            a.BranchCode, a.ReturnTransactionNo, a.OrderNo, a.TransactionNo,
            b.TotalReturnedAmount, a.DateExecute, a.ExecuteBy, a.MachineUsed
        FROM dbo.POSReturnTransaction a WITH (NOLOCK)
        INNER JOIN dbo.BatchSalesSummary b WITH (NOLOCK)
            ON  a.OrderNo     = b.ReferenceNo
            AND a.BranchCode  = b.BranchCode
            AND a.MachineUsed = b.MachineUsed
        WHERE a.BranchCode = @parmbrcode
          AND a.DateExecute >= @FromDate
          AND a.DateExecute <  @ToDateExclusive
          AND (@UseMachine = 0 OR a.MachineUsed = @parmmachinename)
          AND (@UseCashier = 0 OR a.ExecuteBy = @parmprocessby)
        OPTION (RECOMPILE);

        RETURN;
    END

    -------------------------------------------------------------------------
    -- (12) CREDITCARD
    -------------------------------------------------------------------------
    IF @parmoption = 12
    BEGIN
        SELECT *
        FROM dbo.POSCreditCardTransactions WITH (NOLOCK)
        WHERE BranchCode = @parmbrcode
          AND TransactionDate >= @FromDate
          AND TransactionDate <  @ToDateExclusive
          AND (@UseMachine = 0 OR MachineUsed = @parmmachinename)
          AND (@UseCashier = 0 OR ProcessedBy = @parmprocessby)
        OPTION (RECOMPILE);

        RETURN;
    END

    -------------------------------------------------------------------------
    -- (13) SALESSUMMARY (supports per-machine AND branch-wide)
    -------------------------------------------------------------------------
    IF @parmoption = 13
    BEGIN
        SELECT
            DateExecute,
            BeginningSINo as FromSI,
            EndingSINo as ToSI,
            EndingBalance as NetAmount,
            TotalSCDiscount as SC,
            TotalPWDDiscount as PWD,
            TotalDiscount as Others,
            TotalReturnedSales as Refund,
            VatAdjustment,
            EndingBalance + TotalSCDiscount + TotalPWDDiscount + TotalDiscount + TotalReturnedSales + VatAdjustment as TotalIncome,
            0 as OtherIncome,
            EndingBalance + TotalSCDiscount + TotalPWDDiscount + TotalDiscount + TotalReturnedSales + VatAdjustment as GrossAmount,
            VatableSale as VATableSales,
            TotalVatSales as VATAmount,
            VatExemptSale as VATExempt,
            ZeroRatedSale as ZeroRated,
            TotalVatSales as VATPayable,
            0 as SalesOverrun,
            VatableSale + VatExemptSale + ZeroRatedSale as TotalSales,
            CounterNo,
            MachineUsed
        FROM dbo.POSZReadingTransactions WITH (NOLOCK)
        WHERE BranchCode = @parmbrcode
          AND DateExecute >= @FromDate
          AND DateExecute <  @ToDateExclusive
          AND (@UseMachine = 0 OR MachineUsed = @parmmachinename)
        OPTION (RECOMPILE);

        RETURN;
    END

    -------------------------------------------------------------------------
    -- (14) SALESIN
    -------------------------------------------------------------------------
    IF @parmoption = 14
    BEGIN
        SELECT *
        FROM dbo.SalesIN WITH (NOLOCK)
        WHERE BranchCode = @parmbrcode
          AND SalesDate >= @FromDate
          AND SalesDate <  @ToDateExclusive
          AND (@UseMachine = 0 OR MachineUsed = @parmmachinename)
        OPTION (RECOMPILE);

        RETURN;
    END

    -------------------------------------------------------------------------
    -- (15) ACTIVITYLOGS
    -------------------------------------------------------------------------
    IF @parmoption = 15
    BEGIN
        SELECT BranchCode, TransactionNo, Type, DateAdded, MachineUsed, ExecuteBy
        FROM dbo.POSTransaction WITH (NOLOCK)
        WHERE BranchCode = @parmbrcode
          AND DateAdded >= @FromDate
          AND DateAdded <  @ToDateExclusive
          AND (@UseMachine = 0 OR MachineUsed = @parmmachinename)
        OPTION (RECOMPILE);

        RETURN;
    END

    -------------------------------------------------------------------------
    -- Unknown option
    -------------------------------------------------------------------------
    --THROW 50001, 'Invalid @parmoption supplied to spr_POSReports.', 1;
END
