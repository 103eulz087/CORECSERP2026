SET NOCOUNT ON;
PRINT '=== funcview_CustomerCashReceipts: return numeric amounts instead of FORMAT()-string ===';
GO
EXEC sp_rename 'dbo.funcview_CustomerCashReceipts', 'funcview_CustomerCashReceipts_OLD_08072026153402';
GO
SET QUOTED_IDENTIFIER ON;
GO
-- =============================================
-- Author:      2026-08-07
-- Description: Customer cash receipts, PaymentHeader joined to a per-invoice breakdown of
--              INVOICE PAYMENT / EWT / DISCOUNT from ARPaymentDetails. Used by
--              POS/POSSalesReportDevEx.cs's LoadCustomerCashReceipts().
--
-- CHANGELOG FROM funcview_CustomerCashReceipts (legacy, now
-- funcview_CustomerCashReceipts_OLD_08072026153402):
--   [1] TotalAmount / InvoicePaymentAmount / EwtAmount / DiscountAmount are now returned as
--       their native numeric type (money/decimal) instead of FORMAT(x,'N2') text. The old
--       version pre-formatted these as display strings, which meant DevExpress GridView could
--       never SUM them for a group summary (SummaryItemType.Sum needs a numeric column) --
--       blocking the ControlNo grouping + totals added in LoadCustomerCashReceipts(). Display
--       formatting ("15,000.00") is now applied grid-side via
--       Classes.DevXGridViewSettings.ShowFooterTotal(), which already formats as "{0:n2}" --
--       same visual result, but summable.
--
-- The previous version is preserved as funcview_CustomerCashReceipts_OLD_08072026153402.
-- =============================================
CREATE FUNCTION [dbo].[funcview_CustomerCashReceipts]
(
    @datefrom DATE,
    @dateto DATE
)
RETURNS TABLE
AS
RETURN
(
        WITH aa AS
        (
            SELECT
                PaymentHeaderID,
                CustomerKey,
                DebitGLCode,
                InvoiceNo,
                InvoiceDate,
                SUM(CASE WHEN PaymentType = 'INVOICE PAYMENT' THEN Amount ELSE 0 END) AS InvoicePaymentAmount,
                SUM(CASE WHEN PaymentType = 'EWT' THEN Amount ELSE 0 END) AS EwtAmount,
                SUM(CASE WHEN PaymentType = 'DISCOUNT' THEN Amount ELSE 0 END) AS DiscountAmount
            FROM
                ARPaymentDetails
                WHERE InvoiceDate >= @datefrom AND InvoiceDate < DATEADD(DAY,1,@dateto)
            GROUP BY
                PaymentHeaderID,
                CustomerKey,
                DebitGLCode,
                InvoiceNo,
                InvoiceDate
        )
        SELECT a.CustomerKey,c.CustomerName,a.ControlNo,d.Description as Bank,a.PaymentDate,a.CRNo,
               a.TotalAmount,
               b.InvoicePaymentAmount,
               b.InvoiceNo,b.InvoiceDate,
               b.EwtAmount,
               b.DiscountAmount,
               a.PaymentType,c.AccountOfficer as SalesPerson
        FROM PaymentHeader a
        INNER JOIN aa b
            ON a.PaymentHeaderID=b.PaymentHeaderID
        INNER JOIN Customers c
            ON a.CustomerKey=c.CustomerKey
        INNER JOIN ChartOfAccounts d
            ON b.DebitGLCode=d.AccountCode
);
GO
PRINT 'DEPLOYMENT COMPLETE: funcview_CustomerCashReceipts rewritten, original preserved as funcview_CustomerCashReceipts_OLD_08072026153402.';
