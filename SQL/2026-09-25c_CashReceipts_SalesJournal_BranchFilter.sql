/* ================================================================
   2026-09-25c: POS/POSSalesReportDevEx.cs -- Cash Receipts & Sales
   Journal tab: branch filter + OFFSET deducted from receipts.
   ================================================================
   REQUEST:
     1. Branch filter on both reports. A global admin can choose any
        branch (or all branches); anyone else is locked to
        Login.assignedBranch (the form hides the dropdown).
     2. Cash Receipts: InvoicePaymentAmount was SUM(INVOICE PAYMENT +
        OVERPAY + OFFSET). OFFSET and EWT must now be DEDUCTED:
            INVOICE PAYMENT + OVERPAY - OFFSET - EWT
        (OFFSET = customer credit applied instead of cash; EWT = tax the
        customer withheld. INVOICE PAYMENT is stored GROSS, so neither is
        money received in this collection. Same netting as
        SuggestedAmountPaid in 2026-08-20_ClientPayments_PostedDetailsSPs.sql.
        EwtAmount is still returned as its own column.)

   BRANCH SOURCE:
     - Sales Journal: the invoice's own BranchCode (already in the function).
     - Cash Receipts: PaymentHeader/ARPaymentDetails have no BranchCode, so
       it uses Customers.BranchCode. Checked on STAGING: the customer's
       branch equals the paid invoice's TransactionChargeSales.BranchCode
       on every one of 3,057 payment rows where the invoice can be matched,
       and 6 rows can't be matched by invoice at all - so the customer's
       branch is the complete, equivalent source. Added as a BranchCode
       output column (last) so an all-branches view shows it.

   @parmbranchcode: NULL, '' or 'ALL' = every branch (same 'ALL'
   convention as funcview_CustomerSalesHistory on this form).

   Only caller of both functions: POS/POSSalesReportDevEx.cs (grepped).
   Live definitions BEFORE this change differed between databases:
     - funcview_CustomerSalesJournal: identical on DEV and STAGING.
     - funcview_CustomerCashReceipts InvoicePaymentAmount:
         DEV     = INVOICE PAYMENT + OVERPAY            (no OFFSET)
         STAGING = INVOICE PAYMENT + OVERPAY + OFFSET   (OFFSET added, not deducted)
       Both become INVOICE PAYMENT + OVERPAY - OFFSET - EWT. First DEV run
       (OFFSET only) verified: total dropped by exactly 1 x OFFSET (4,500.00
       over 5 payments). On STAGING the OFFSET drop will be 2 x OFFSET for
       non-reversed rows (17,500.00 x 2 = 35,000.00). EWT deduction added
       later the same day - re-verify on DEV: new total = previous total
       - SUM(EwtAmount).
   Reversed collections stay excluded via ARPaymentDetails.ErrorTag = 1
   (checked: every REVERSED PaymentHeader's rows carry ErrorTag 1).

   NOT changed: funcview_CustomerSalesJournal still returns Amount /
   CustomerCreditLimit as FORMAT()-ed text (pre-existing; CLAUDE.md notes
   this). OVERPAYINCOME and SERVICES rows are not part of
   InvoicePaymentAmount (unchanged; asked the user).

   Deploy to CORECSERP_002_DEV first; mirror to CORECSJFC2026_STAGING only
   after confirming with the user.
   ================================================================ */

-- ----------------------------------------------------------------
-- 1. funcview_CustomerCashReceipts
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.funcview_CustomerCashReceipts') IS NOT NULL
    EXEC sp_rename 'dbo.funcview_CustomerCashReceipts', 'funcview_CustomerCashReceipts_OLD_09252026150000';
GO

CREATE FUNCTION [dbo].[funcview_CustomerCashReceipts]
(
    @datefrom       DATE,
    @dateto         DATE,
    @dateFilterType CHAR(1),        -- 'I' = ARPaymentDetails.InvoiceDate, 'P' = PaymentHeader.PaymentDate
    @parmbranchcode VARCHAR(10)     -- NEW 2026-09-25c: NULL / '' / 'ALL' = all branches
)
RETURNS TABLE
AS
RETURN
(
        WITH aa AS
        (
            SELECT
                apd.PaymentHeaderID,
                apd.CustomerKey,
                apd.DebitGLCode,
                apd.InvoiceNo,
                apd.InvoiceDate,
                -- CHANGED 2026-09-25c: OFFSET and EWT are deducted (non-cash).
                SUM(CASE WHEN apd.PaymentType IN ('INVOICE PAYMENT', 'OVERPAY') THEN apd.Amount
                         WHEN apd.PaymentType IN ('OFFSET', 'EWT')              THEN -apd.Amount
                         ELSE 0 END) AS InvoicePaymentAmount,
                SUM(CASE WHEN apd.PaymentType = 'EWT' THEN apd.Amount ELSE 0 END) AS EwtAmount,
                SUM(CASE WHEN apd.PaymentType = 'DISCOUNT' THEN apd.Amount ELSE 0 END) AS DiscountAmount
            FROM ARPaymentDetails apd
            WHERE (apd.ErrorTag IS NULL OR apd.ErrorTag <> 1)
              AND (
                    (@dateFilterType = 'I'
                     AND apd.InvoiceDate >= @datefrom
                     AND apd.InvoiceDate < DATEADD(DAY, 1, @dateto))
                 OR (@dateFilterType = 'P'
                     AND EXISTS (
                            SELECT 1
                            FROM PaymentHeader ph
                            WHERE ph.PaymentHeaderID = apd.PaymentHeaderID
                              AND ph.PaymentDate >= @datefrom
                              AND ph.PaymentDate < DATEADD(DAY, 1, @dateto)
                         ))
                  )
            GROUP BY
                apd.PaymentHeaderID,
                apd.CustomerKey,
                apd.DebitGLCode,
                apd.InvoiceNo,
                apd.InvoiceDate
        )
        SELECT a.CustomerKey, b.InvoiceDate, c.CustomerName, a.ControlNo, d.Description AS Bank, a.PaymentDate, a.CRNo,
               a.TotalAmount,
               b.InvoicePaymentAmount,
               b.InvoiceNo,
               b.EwtAmount,
               b.DiscountAmount,
               a.PaymentType, c.AccountOfficer AS SalesPerson,
               c.BranchCode                               -- NEW 2026-09-25c
        FROM PaymentHeader a
        INNER JOIN aa b
            ON a.PaymentHeaderID = b.PaymentHeaderID
        INNER JOIN Customers c
            ON a.CustomerKey = c.CustomerKey
        INNER JOIN ChartOfAccounts d
            ON b.DebitGLCode = d.AccountCode
        WHERE (NULLIF(LTRIM(RTRIM(ISNULL(@parmbranchcode, ''))), '') IS NULL
               OR @parmbranchcode = 'ALL'
               OR c.BranchCode = @parmbranchcode)
);
GO

-- ----------------------------------------------------------------
-- 2. funcview_CustomerSalesJournal
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.funcview_CustomerSalesJournal') IS NOT NULL
    EXEC sp_rename 'dbo.funcview_CustomerSalesJournal', 'funcview_CustomerSalesJournal_OLD_09252026150000';
GO

CREATE FUNCTION [dbo].[funcview_CustomerSalesJournal]
(
    @datefrom       DATE,
    @dateto         DATE,
    @parmbranchcode VARCHAR(10)     -- NEW 2026-09-25c: NULL / '' / 'ALL' = all branches
)
RETURNS TABLE
AS
RETURN
(

    WITH zzz AS (
        SELECT
            a.BranchCode,
            a.PONumber,
            d.InvoiceNo,
            d.EffectivityDate as InvoiceDate,
            --a.QtyDelivered,
            case when c.isCreditMemo=1 then c.ActualQty when c.isReturned=1 then 0 else a.QtyDelivered end as QtyDelivered,
            b.ReferenceCode AS ItemID,
            a.ProductNo,
            a.Description,
            c.SellingPrice AS UnitPrice,
            --(c.SellingPrice * a.QtyDelivered) AS Amount,
            case when c.isCreditMemo=1 then (c.SellingPrice * c.ActualQty) when c.isReturned=1 then 0 else (c.SellingPrice * a.QtyDelivered) end as Amount,
            a.QtyDelivered AS StockingQty,
            c.Cost,
            (c.Cost * a.QtyDelivered) AS CostOfSalesAmount,
            c.isReturned,
            c.isCreditMemo
        FROM dbo.InventoryDeliveryFIFO a
        INNER JOIN dbo.Inventory b
            ON a.SequenceReferenceNumber = b.SequenceNumber
            --and a.isErrorCorrect=0
        INNER JOIN dbo.DeliveryDetails c
            ON a.PONumber = c.PONumber
            AND a.DeliveryNo = c.DeliveryNo
            AND a.ProductNo = c.ProductNo
            AND a.DevDetSeqNo = c.SeqNo
            AND c.isCancelled=0
        INNER JOIN dbo.DeliverySummary d
            ON d.PONumber = c.PONumber
            AND d.DeliveryNo = c.DeliveryNo
        -- NEW 2026-09-25c: branch filter applied early (before the joins below)
        WHERE (NULLIF(LTRIM(RTRIM(ISNULL(@parmbranchcode, ''))), '') IS NULL
               OR @parmbranchcode = 'ALL'
               OR a.BranchCode = @parmbranchcode)
    )
    SELECT
        c.CustomerKey,
        c.CustomerID,
        c.CustomerName,
        --c.CustomerEmail,
        --c.CustomerContactNo,
        --c.CustomerAddress,
        --c.Term,
        --c.TinNo,
        FORMAT(CAST(a.InvoiceDate AS DATE),'yyyy-MM-dd') AS InvoiceDate,
        a.InvoiceNo,
        CONCAT(a.BranchCode,' - ',br.BranchName) AS Branch,
        a.PONumber,
        --a.ItemID,
        CONCAT(a.ProductNo,' - ',a.Description) AS Product,
        --a.ProductNo,
        --a.Description,
        a.QtyDelivered,
        a.UnitPrice,
        FORMAT(a.Amount,'N2') AS Amount,
        --a.StockingQty,
        b.PayStatus,
        c.AccountOfficer,
        FORMAT(c.CustomerCreditLimit,'N2') AS CustomerCreditLimit,
        a.isCreditMemo,
        a.isReturned
        --a.Cost,
        --FORMAT(a.CostOfSalesAmount,'N2') AS CostOfSalesAmount
    FROM zzz a
    LEFT OUTER JOIN dbo.TransactionChargeSales b
        ON a.BranchCode = b.BranchCode
        AND a.PONumber = b.ReferenceNo
    INNER JOIN dbo.Customers c
        ON b.CustomerKey = c.CustomerKey
    INNER JOIN dbo.Branches br
        ON a.BranchCode = br.BranchCode
    WHERE     a.InvoiceDate >= @datefrom
            AND a.InvoiceDate < DATEADD(DAY,1,@dateto)
);
GO
