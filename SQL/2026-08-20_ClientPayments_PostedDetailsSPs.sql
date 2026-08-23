SET NOCOUNT ON;
PRINT '=== ClientPaymentsDevExAcctg: FullyPaid Invoice tab - View/Edit Details support ===';
GO

-- =============================================================
-- CONTEXT: ClientPaymentsDevExAcctg.cs "FullyPaid Invoice" tab is being
-- rebuilt to match AddExpenseDevExFrm's "Posted Expenses" UX (View Details /
-- Edit Details, no Copy - this is just a recorded client payment).
--
-- Per CLAUDE.md Known Bug Pattern #4 ("once a payment has touched a
-- posting, fall back to the reversal SP instead of editing"): a Client
-- Payment IS the thing that touches TransactionChargeSales/ClientLedger/
-- TicketMaster/BankStatementRecon the moment sp_AddPaymentClient runs, so
-- "Edit" here means reverse (via the already-existing, already-tested
-- sp_ReversePaymentClient) + re-enter as a fresh payment through the
-- existing Confirm Payment flow - NOT an in-place delete-and-repost.
--
-- These two new SPs are pure SELECT support for that flow: list posted
-- payments for View/Edit picking, and pull one payment's full detail
-- (header + reconstructed per-invoice lines) for the popup and for
-- pre-filling the Entry tab after reversal. Neither touches
-- sp_AddPaymentClient or sp_ReversePaymentClient, which are unchanged.
-- =============================================================

-- =============================================================
-- sp_GetPostedClientPayments
-- =============================================================
IF OBJECT_ID('dbo.sp_GetPostedClientPayments', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetPostedClientPayments;
GO

CREATE PROCEDURE dbo.sp_GetPostedClientPayments
(
    @CustomerKey CHAR(8),
    @DateFrom    DATE = NULL,
    @DateTo      DATE = NULL   -- INCLUSIVE upper bound; NULL = no upper bound.
                               -- The +1-day exclusive conversion happens here,
                               -- not in the caller, so a future caller can't
                               -- get the boundary wrong by passing a plain
                               -- inclusive date (sp-reviewer finding).
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ph.PaymentHeaderID,
        ph.CustomerKey,
        ph.ReferenceNo,
        ph.ControlNo,
        ph.CRNo,
        ph.PaymentType,
        ph.TotalAmount,
        ph.PaymentDate,
        ph.Remarks,
        ph.CreatedBy,
        ph.CreatedDate,
        ph.Status,
        ph.ReversedBy,
        ph.ReversedDate,
        CASE WHEN ph.Status = 'REVERSED' THEN 'Already Reversed' ELSE NULL END AS BlockedReason
    FROM dbo.PaymentHeader ph
    WHERE ph.CustomerKey = @CustomerKey
      AND (@DateFrom IS NULL OR ph.PaymentDate >= @DateFrom)
      AND (@DateTo   IS NULL OR ph.PaymentDate <  DATEADD(DAY, 1, @DateTo))
    ORDER BY ph.PaymentDate DESC, ph.PaymentHeaderID DESC;
END
GO

-- =============================================================
-- sp_GetClientPaymentDetails
-- Result set 1: header (payment-method fields resolved via LEFT JOIN,
--   whichever table matches PaymentType is populated, others NULL).
-- Result set 2: one row per invoice this payment touched, amounts
--   pivoted back out of ARPaymentDetails into the Entry grid's shape.
-- =============================================================
IF OBJECT_ID('dbo.sp_GetClientPaymentDetails', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetClientPaymentDetails;
GO

CREATE PROCEDURE dbo.sp_GetClientPaymentDetails
(
    @PaymentHeaderID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Header
    -- sp-reviewer finding: the original LEFT JOIN to ARPaymentDetails
    -- filtered on PaymentType='INVOICE PAYMENT' fans a header out to one
    -- row per invoice before TOP 1/ORDER BY collapsed it back down - only
    -- correct because every ARPaymentDetails row for a header happens to
    -- carry the same Debit/CreditGLCode today (an unenforced convention in
    -- InsertDetail(), not a constraint). It also went NULL if a header had
    -- zero INVOICE PAYMENT rows. OUTER APPLY fixes both: each sub-select is
    -- independently TOP-1-with-ORDER-BY, so PaymentHeader can never fan out
    -- regardless of how many ARPaymentDetails/TransactionCheque/
    -- TransactionOnline rows exist, and GL codes resolve from ANY detail
    -- row for the header, not just INVOICE PAYMENT ones.
    SELECT
        ph.PaymentHeaderID,
        ph.CustomerKey,
        ph.ReferenceNo,
        ph.ControlNo,
        ph.CRNo,
        ph.PaymentType,
        ph.TotalAmount,
        ph.PaymentDate,
        ph.Remarks,
        ph.CreatedBy,
        ph.CreatedDate,
        ph.Status,
        apd.DebitGLCode,
        apd.CreditGLCode,
        tc.CheckNo,
        tc.CheckName,
        tc.CheckBankName,
        tc.CheckAmount,
        tc.CheckDate,
        ton.BankRefNumber,
        ton.BankName,
        ton.DateDeposit,
        CASE WHEN ph.Status = 'REVERSED' THEN 'Already Reversed' ELSE NULL END AS BlockedReason
    FROM dbo.PaymentHeader ph
    OUTER APPLY (
        SELECT TOP 1 a.DebitGLCode, a.CreditGLCode
        FROM dbo.ARPaymentDetails a
        WHERE a.PaymentHeaderID = ph.PaymentHeaderID
        ORDER BY CASE WHEN a.PaymentType = 'INVOICE PAYMENT' THEN 0 ELSE 1 END, a.InvoiceNo
    ) apd
    OUTER APPLY (
        SELECT TOP 1 t.CheckNo, t.CheckName, t.CheckBankName, t.CheckAmount, t.CheckDate
        FROM dbo.TransactionCheque t
        WHERE t.PaymentHeaderID = ph.PaymentHeaderID
        ORDER BY t.SequenceNo
    ) tc
    OUTER APPLY (
        SELECT TOP 1 o.BankRefNumber, o.BankName, o.DateDeposit
        FROM dbo.TransactionOnline o
        WHERE o.PaymentHeaderID = ph.PaymentHeaderID
        ORDER BY o.SequenceNumber
    ) ton
    WHERE ph.PaymentHeaderID = @PaymentHeaderID;

    -- GL Entries - the actual posted ticket lines for this payment (same
    -- source pattern as sp_GetSingleExpenseDetails' Table[1]: TicketDetails
    -- joined to ChartOfAccounts), not a reconstruction. This is what the
    -- FullyPaid Invoice tab's details grid shows on View Details.
    SELECT
        td.AccountCode,
        coa.Description AS AccountTitle,
        td.Debit,
        td.Credit
    FROM dbo.TicketDetails td
    JOIN dbo.ChartOfAccounts coa ON coa.AccountCode = td.AccountCode
    WHERE td.ReferenceNumber = (SELECT ReferenceNo FROM dbo.PaymentHeader WHERE PaymentHeaderID = @PaymentHeaderID)
    ORDER BY td.Debit DESC, td.Credit DESC;

    -- Lines, one row per invoice - GrossAmount/EWT/Discount/Offset/OverPay
    -- are the raw components; SuggestedAmountPaid reconstructs the net
    -- cash figure using the same formula InsertARPaymentDetails used to
    -- derive gross in the first place (gross = paid + ewt + disc + offset
    -- - overpay), so pre-fill shows what was actually entered before.
    SELECT
        InvoiceNo,
        PONumber AS OrderNo,
        MAX(InvoiceDate) AS TransactionDate,
        SUM(CASE WHEN PaymentType = 'INVOICE PAYMENT' THEN Amount ELSE 0 END) AS GrossAmount,
        SUM(CASE WHEN PaymentType = 'EWT'              THEN Amount ELSE 0 END) AS EWTAmount,
        SUM(CASE WHEN PaymentType = 'DISCOUNT'          THEN Amount ELSE 0 END) AS DiscountAmount,
        SUM(CASE WHEN PaymentType = 'OFFSET'            THEN Amount ELSE 0 END) AS OffsetAmount,
        SUM(CASE WHEN PaymentType = 'OVERPAY'           THEN Amount ELSE 0 END) AS OverPay,
        SUM(CASE WHEN PaymentType = 'INVOICE PAYMENT' THEN Amount ELSE 0 END)
          - SUM(CASE WHEN PaymentType = 'EWT'      THEN Amount ELSE 0 END)
          - SUM(CASE WHEN PaymentType = 'DISCOUNT' THEN Amount ELSE 0 END)
          - SUM(CASE WHEN PaymentType = 'OFFSET'   THEN Amount ELSE 0 END)
          + SUM(CASE WHEN PaymentType = 'OVERPAY'  THEN Amount ELSE 0 END) AS SuggestedAmountPaid
    FROM dbo.ARPaymentDetails
    WHERE PaymentHeaderID = @PaymentHeaderID
    GROUP BY InvoiceNo, PONumber
    ORDER BY InvoiceNo;
END
GO

PRINT 'DEPLOYMENT COMPLETE: sp_GetPostedClientPayments, sp_GetClientPaymentDetails created.';
