-- Adds an explicit @dateFilterType parameter to funcview_CustomerCashReceipts so the caller
-- (POSSalesReportDevEx's Cash Receipts Book tab) can choose whether @datefrom/@dateto filters
-- against ARPaymentDetails.InvoiceDate ('I') or PaymentHeader.PaymentDate ('P'), instead of the
-- prior hardcoded PaymentDate-only behavior (SQL/2026-09-11_CustomerCashReceipts_PaymentDateFilter.sql).
--
-- Both branches live in one WHERE clause (can't use IF/branching -- this is a single-statement
-- inline TVF) gated by @dateFilterType, each still sargable on its own date column when that
-- branch is the one actually selected. This does mean the optimizer has to plan for both
-- possibilities rather than one guaranteed predicate; acceptable here given ARPaymentDetails/
-- PaymentHeader's current low row counts in this system (single/low-hundreds range) and this
-- being a manually-triggered report, not a hot path -- flagged for db-perf-tuner attention if
-- that data volume ever changes materially.
IF OBJECT_ID('dbo.funcview_CustomerCashReceipts', 'IF') IS NOT NULL
    EXEC sp_rename 'dbo.funcview_CustomerCashReceipts', 'funcview_CustomerCashReceipts_OLD_09112026140000';
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE FUNCTION [dbo].[funcview_CustomerCashReceipts]
(
    @datefrom DATE,
    @dateto DATE,
    @dateFilterType CHAR(1)   -- 'I' = ARPaymentDetails.InvoiceDate, 'P' = PaymentHeader.PaymentDate
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
                SUM(CASE WHEN apd.PaymentType = 'INVOICE PAYMENT' THEN apd.Amount ELSE 0 END) AS InvoicePaymentAmount,
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
               a.PaymentType, c.AccountOfficer AS SalesPerson
        FROM PaymentHeader a
        INNER JOIN aa b
            ON a.PaymentHeaderID = b.PaymentHeaderID
        INNER JOIN Customers c
            ON a.CustomerKey = c.CustomerKey
        INNER JOIN ChartOfAccounts d
            ON b.DebitGLCode = d.AccountCode
);
GO
