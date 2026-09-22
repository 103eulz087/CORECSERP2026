-- 2026-09-22: sp_GetSupplierVoucherDetails -- Invoice Legs' Amount must be
-- numeric, not FORMAT()-ed VARCHAR.
--
-- Context: SupplierVoucherReversalFrm.cs's "View Details" popup is being
-- reworked so its "Invoice Legs" tab presents like SupplierPaymentDevEx.cs's
-- INVOICES tab (N2 numeric formatting + a footer sum on Amount). A
-- FORMAT()-ed string column can't sort or sum correctly in a DevExpress grid
-- column -- same anti-pattern flagged in CLAUDE.md's "Reporting
-- Quantity/Amount columns must be numeric" convention, same fix already
-- applied to sp_GetPostedSingleExpenses (2026-09-14c).
--
-- Per user decision (2026-09-22): this is a UI/formatting-only fix, NOT the
-- addition of ActualCost/EWTAmount/DiscountAmount columns -- APPaymentDetails
-- doesn't persist those per-invoice-leg values today (confirmed by tracing
-- sp_AddPaymentSupplierCompound_V2: it computes them into GL ticket lines
-- and discards them, never inserting into APPaymentDetails), and adding that
-- capture was explicitly declined for this change. Only the existing Amount
-- column's TYPE is fixed here -- no new data, no schema change.
--
-- Second result set (Full GL Detail: Debit/Credit) is untouched -- out of
-- scope for this change (only the Invoice Legs tab was in scope), left as
-- FORMAT()-ed VARCHAR same as before.

IF OBJECT_ID('dbo.sp_GetSupplierVoucherDetails', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetSupplierVoucherDetails', 'sp_GetSupplierVoucherDetails_OLD_09222026180000';
GO

CREATE PROCEDURE dbo.sp_GetSupplierVoucherDetails
(
    @SupplierID      VARCHAR(50),
    @ReferenceNumber VARCHAR(10)
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Invoice-level breakdown (only has rows when an invoice leg exists)
    SELECT
        InvoiceNo, BranchCode, InvoiceDate,
        CAST(Amount AS DECIMAL(18,2)) AS Amount,
        PaymentType, PaymentMethod, TicketNumber
    FROM APPaymentDetails
    WHERE ReferenceNumber = @ReferenceNumber AND SupplierID = @SupplierID
    ORDER BY InvoiceNo;

    -- Full GL picture - every leg posted under this reference number,
    -- across whichever branches/tickets it touched (invoice leg,
    -- manual/cash-advance leg, or both, all show up here together)
    SELECT
        td.BranchCode, td.TicketNumber, td.AccountCode,
        coa.Description AS AccountTitle, FORMAT(td.Debit,'N2') AS Debit, FORMAT(td.Credit,'N2') AS Credit
    FROM TicketDetails td
    LEFT JOIN ChartOfAccounts coa ON coa.AccountCode = td.AccountCode
    WHERE td.ReferenceNumber = @ReferenceNumber
    ORDER BY td.BranchCode, td.Debit DESC, td.Credit DESC;
END
GO
