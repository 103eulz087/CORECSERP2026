-- 2026-09-22: sp_GetPostedSingleExpenses -- surface PO linkage on the Posted
-- Expenses report (AddExpenseDevExFrm.cs), so the grid can show which posted
-- expenses are linked to a PO and let the user drill into that PO's details.
--
-- Adds:
--   - es.ShipmentNo to the result set ('' / blank = not linked to a PO,
--     matching the same convention sp_GetSingleExpenseDetails already uses
--     for its BlockedReason logic).
--   - @POLinkedOnly BIT = 0 optional filter param.
--
-- No other columns/behavior changed. Amount/Balance/AmountPaid stay DECIMAL
-- per the 2026-09-14 fix (SQL/2026-09-14c_GetPostedSingleExpenses_NumericColumns.sql).

IF OBJECT_ID('dbo.sp_GetPostedSingleExpenses', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetPostedSingleExpenses', 'sp_GetPostedSingleExpenses_OLD_20260922120000';
GO

/* ================================================================
   POST SINGLE EXPENSE — Posted Expenses tab support
   Read-only listing/detail SPs, safe to build independent of
   spu_PostExpenseV2's internals since they only SELECT.

   2026-09-14: Amount/Balance/AmountPaid returned as DECIMAL, not
   FORMAT()-ed VARCHAR.
   2026-09-22: added ShipmentNo (PO link) + @POLinkedOnly filter --
   AddExpenseDevExFrm.cs LoadPostedExpenses() / BtnViewPODetails_Click.
   ================================================================ */
CREATE   PROCEDURE [dbo].[sp_GetPostedSingleExpenses]
(
    @DateFrom     DATE = NULL,
    @DateTo       DATE = NULL,
    @BranchCode   VARCHAR(5) = NULL,   -- NULL = all branches
    @POLinkedOnly BIT = 0              -- 1 = only expenses linked to a PO
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        es.ReferenceNumber,
        es.InvoiceNo,
        es.SupplierID,
        s.SupplierName,
        MIN(em.BranchCode) AS BranchCode,   -- SINGLE mode is one branch per posting
        br.BranchName,
        es.ExpenseDate,
        es.Description AS Remarks,
        CAST(es.Amount AS DECIMAL(18,2)) AS Amount,
        CAST(es.Balance AS DECIMAL(18,2)) AS Balance,
        CAST(es.AmountPaid AS DECIMAL(18,2)) AS AmountPaid,
        es.Status,
        MIN(em.TicketReference) AS TicketNumber,
        es.ShipmentNo
    FROM ExpenseSummary es
    JOIN Supplier s ON s.SupplierKey = es.SupplierID
    JOIN ExpenseMaster em
      ON em.ReferenceNumber = es.ReferenceNumber
     AND em.InvoiceNo = es.InvoiceNo
     AND em.BatchReferenceID = es.BatchReferenceID
    JOIN Branches br ON em.BranchCode=br.BranchCode
    WHERE es.PostingMode = 'SINGLE'
      AND (@DateFrom IS NULL OR es.ExpenseDate >= @DateFrom)
      AND (@DateTo IS NULL OR es.ExpenseDate <= @DateTo)
      AND (@BranchCode IS NULL OR em.BranchCode = @BranchCode)
      AND (@POLinkedOnly = 0 OR LTRIM(RTRIM(ISNULL(es.ShipmentNo,''))) <> '')
    GROUP BY es.ReferenceNumber, es.InvoiceNo, es.SupplierID, s.SupplierName,
             es.ExpenseDate, es.Description, es.Amount, es.Balance, es.AmountPaid, es.Status, br.BranchName, es.ShipmentNo
    ORDER BY es.ExpenseDate DESC, es.ReferenceNumber DESC;
END
GO
