-- funcview_CustomerCashReceipts (used by POSSalesReportDevEx's "Cash Receipts Book" tab,
-- LoadCustomerCashReceipts) filtered its @datefrom/@dateto range against ARPaymentDetails.
-- InvoiceDate -- the invoice being paid, not the payment itself. Requested change: filter
-- by PaymentHeader.PaymentDate instead, so the report reflects payments received within
-- the selected date range regardless of when the underlying invoice was dated. Rewrite is
-- based on the LIVE object definition pulled directly from CORECSERP_002_DEV via
-- OBJECT_DEFINITION() on 2026-09-11 -- not the repo's 2026-08-07 tracked migration, which
-- turned out not to reflect what's actually deployed (that script's FORMAT()-removal on
-- TotalAmount/InvoicePaymentAmount was apparently never applied, or was later reverted;
-- see the numeric-column fix below, which re-applies it against the true current state).
--
-- The date filter moves into the aa CTE as an EXISTS predicate against PaymentHeader
-- (rather than just adding it to the outer WHERE, or an INNER JOIN) so it stays sargable
-- on PaymentDate, the aggregation only ever touches rows that will actually qualify, and
-- -- unlike a JOIN -- it can never fan out ARPaymentDetails rows before the SUM/GROUP BY
-- even if PaymentHeaderID somehow stopped being unique on PaymentHeader (verified it
-- currently is PaymentHeader's PK, so a JOIN would also have been safe today, but EXISTS
-- doesn't depend on that staying true).
--
-- Incidental fixes, both against the confirmed-live version:
-- 1. ErrorTag operator precedence: the live WHERE was
--      InvoiceDate >= @datefrom AND InvoiceDate < DATEADD(DAY,1,@dateto) AND ErrorTag IS NULL OR ErrorTag <> 1
--    AND binds tighter than OR, so this was actually
--      (date range AND ErrorTag IS NULL) OR (ErrorTag <> 1)
--    Under ANSI_NULLS, "ErrorTag <> 1" is UNKNOWN (not TRUE) when ErrorTag IS NULL, so this
--    didn't let every NULL-ErrorTag row bypass the date filter -- only rows with an
--    explicit non-NULL, non-1 ErrorTag value did. Still a real bug: those rows should have
--    been date-filtered too. Fixed by parenthesizing (ErrorTag IS NULL OR ErrorTag <> 1)
--    as its own condition, ANDed with the (now EXISTS-based) date filter.
-- 2. TotalAmount/InvoicePaymentAmount were FORMAT()-ed to VARCHAR in the live function --
--    exactly the anti-pattern CLAUDE.md calls out by name (a formatted-string column can't
--    be summed by a DevExpress grid footer). POSSalesReportDevEx.cs's LoadCustomerCashReceipts
--    (the only caller) already adds a GridGroupSummaryItem Sum + numeric DisplayFormat for
--    both columns, i.e. the C# side already assumes these are numeric -- so the live
--    FORMAT()-ed version has been silently breaking those two per-ControlNo group totals.
--    Returned as native MONEY here, matching how EwtAmount/DiscountAmount were already
--    returned (unformatted) in the same live function.
IF OBJECT_ID('dbo.funcview_CustomerCashReceipts', 'IF') IS NOT NULL
    EXEC sp_rename 'dbo.funcview_CustomerCashReceipts', 'funcview_CustomerCashReceipts_OLD_09112026100000';
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

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
              AND EXISTS (
                    SELECT 1
                    FROM PaymentHeader ph
                    WHERE ph.PaymentHeaderID = apd.PaymentHeaderID
                      AND ph.PaymentDate >= @datefrom
                      AND ph.PaymentDate < DATEADD(DAY, 1, @dateto)
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
