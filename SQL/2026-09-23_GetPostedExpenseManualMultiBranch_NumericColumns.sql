-- 2026-09-23: sp_GetPostedExpenseManualMultiBranch -- Amount/Balance/
-- AmountPaid must be numeric, not FORMAT()-ed VARCHAR, so the Posted
-- Expense tab's grid (ExpenseManualMultiBranchFrm.cs LoadPostedExpenses())
-- can right-align/sort/sum them. Same fix already applied this session to
-- sp_GetPostedSingleExpenses, sp_GetSupplierVoucherDetails, and
-- sp_GetReversibleSupplierVouchers -- see CLAUDE.md's "Reporting
-- Quantity/Amount columns must be numeric" convention.
--
-- Only caller confirmed (grepped the whole repo): ExpenseManualMultiBranchFrm.cs.
-- ExpenseDate is already native DATE (no SQL change needed there -- only
-- the grid's DisplayFormat was missing, fixed in the C# side).

IF OBJECT_ID('dbo.sp_GetPostedExpenseManualMultiBranch', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetPostedExpenseManualMultiBranch', 'sp_GetPostedExpenseManualMultiBranch_OLD_09232026000000';
GO

/* ----------------------------------------------------------------
   sp_GetPostedExpenseManualMultiBranch - list for Posted tab
   ---------------------------------------------------------------- */
CREATE PROCEDURE [dbo].[sp_GetPostedExpenseManualMultiBranch]
(
    @DateFrom DATE = NULL,
    @DateTo   DATE = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        es.ReferenceNumber, es.InvoiceNo, es.SupplierID, s.SupplierName,
        es.ExpenseDate, es.Description AS Remarks,
        CAST(es.Amount AS DECIMAL(18,2)) AS Amount,
        CAST(es.Balance AS DECIMAL(18,2)) AS Balance,
        CAST(es.AmountPaid AS DECIMAL(18,2)) AS AmountPaid,
        es.Status,
        COUNT(DISTINCT em.BranchCode) AS BranchCount
    FROM ExpenseSummary es
    JOIN Supplier s ON s.SupplierKey = es.SupplierID
    LEFT JOIN ExpenseMaster em
      ON em.ReferenceNumber = es.ReferenceNumber AND em.InvoiceNo = es.InvoiceNo
     AND em.BatchReferenceID = es.BatchReferenceID
    WHERE es.PostingMode = 'MULTI-MANUAL'
      AND (@DateFrom IS NULL OR es.ExpenseDate >= @DateFrom)
      AND (@DateTo IS NULL OR es.ExpenseDate <= @DateTo)
    GROUP BY es.ReferenceNumber, es.InvoiceNo, es.SupplierID, s.SupplierName,
             es.ExpenseDate, es.Description, es.Amount, es.Balance, es.AmountPaid, es.Status
    ORDER BY es.ExpenseDate DESC, es.ReferenceNumber DESC;
END
GO
