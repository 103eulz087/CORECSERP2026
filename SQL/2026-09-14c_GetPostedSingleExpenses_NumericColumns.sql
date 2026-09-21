-- 2026-09-14: sp_GetPostedSingleExpenses -- Amount/Balance/AmountPaid must be numeric
--
-- BUG (reported): sorting the "Balance" column in AddExpenseDevExFrm.cs's Posted Expenses
-- grid sorted alphabetically instead of by value (e.g. "100.00" sorts before "20.00" as
-- text). Root cause: this proc returned Amount/Balance/AmountPaid via FORMAT(...,'N2'),
-- i.e. as VARCHAR -- exactly the anti-pattern flagged in CLAUDE.md's "Reporting
-- Quantity/Amount columns must be numeric" convention. The grid is bound straight from
-- this proc's DataTable with no column remapping, so the string type flowed straight
-- into the DevExpress grid column, which then sorts as text.
--
-- Fix: return them as DECIMAL(18,2) here; format is now applied client-side on the grid
-- column (AddExpenseDevExFrm.cs LoadPostedExpenses(), same convention as this project's
-- other report grids). Checked: this proc has exactly one caller (AddExpenseDevExFrm.cs,
-- straight DataTable bind, no column read by name elsewhere), so this is a safe type
-- change with no other call site to break.

IF OBJECT_ID('dbo.sp_GetPostedSingleExpenses', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetPostedSingleExpenses', 'sp_GetPostedSingleExpenses_OLD_09142026172608';
GO

/* ================================================================
   POST SINGLE EXPENSE — Posted Expenses tab support
   Read-only listing/detail SPs, safe to build independent of
   spu_PostExpenseV2's internals since they only SELECT.

   2026-09-14: Amount/Balance/AmountPaid returned as DECIMAL, not
   FORMAT()-ed VARCHAR -- a formatted string can't sort or sum
   correctly in a DevExpress grid column. See
   SQL/2026-09-14c_GetPostedSingleExpenses_NumericColumns.sql.
   ================================================================ */
CREATE   PROCEDURE [dbo].[sp_GetPostedSingleExpenses]
(
    @DateFrom   DATE = NULL,
    @DateTo     DATE = NULL,
    @BranchCode VARCHAR(5) = NULL   -- NULL = all branches
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
        MIN(em.TicketReference) AS TicketNumber
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
    GROUP BY es.ReferenceNumber, es.InvoiceNo, es.SupplierID, s.SupplierName,
             es.ExpenseDate, es.Description, es.Amount, es.Balance, es.AmountPaid, es.Status, br.BranchName
    ORDER BY es.ExpenseDate DESC, es.ReferenceNumber DESC;
END
GO
