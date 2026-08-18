SET NOCOUNT ON;
PRINT '=== funcview_TransferOrderDetailsSTS: restore ProductCode/QtyRequested/Qty columns dropped by an untracked rewrite ===';
GO

-- =============================================
-- BUG: three separate forms that all consume this function --
-- AddBranchOrderSTSBatchMode.cs, POForApprovalSTS.cs, ReceivedSTS.cs -- read
-- columns named ProductCode, QtyRequested, and/or Qty from its result set
-- (grid columns are auto-bound by Database.display(), no manual mapping).
-- The currently-live function does not have ANY of those three columns --
-- it outputs RequestedQty/ApprovedQty instead and folds ProductCode into
-- ProductName as "CODE - Description". Since GridView.GetRowCellValue on a
-- nonexistent field silently returns null (not an error), this doesn't
-- throw -- it just silently reads 0/blank everywhere, which is exactly why
-- AddBranchOrderSTSBatchMode.cs's negative-inventory skip-filter added
-- today never actually triggered (requested always read as 0), and why
-- ReceivedSTS.cs's Columns["Qty"] / POForApprovalSTS.cs's
-- Columns["QtyRequested"] group-summary wiring were silently targeting a
-- column that doesn't exist.
--
-- This function was ALREADY fixed once, twice same day even --
-- SQL/2026-08-09_ApproveTransferOrder_ApprovedQty.sql then
-- SQL/2026-08-09_ApproveTransferOrder_SeqNoGranularity.sql -- both of which
-- correctly exposed r.ProductCode and aliased RequestedQty AS QtyRequested.
-- Some later change replaced it with the current shape directly against
-- the database, with no SQL/ migration script recording it (grep confirms
-- no other SQL/ file references this function) -- an untracked regression,
-- not a deliberate later design.
--
-- FIX: restore the 2026-08-09 SeqNoGranularity shape (per-line grain, still
-- the more correct design per that file's own reasoning -- same product can
-- legitimately appear on multiple TransferOrderDetails lines with
-- different quantities), and additionally alias a literal `Qty` column
-- (ReceivedSTS.cs and AddBranchOrderSTSBatchMode.cs both read this name;
-- neither prior version had it) alongside the pre-existing `ApprovedQty`,
-- kept for backward compatibility even though no current caller reads it
-- by that name.
-- =============================================

IF OBJECT_ID('dbo.funcview_TransferOrderDetailsSTS_OLD_08182026132940', 'IF') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.funcview_TransferOrderDetailsSTS', 'IF') IS NOT NULL
        DROP FUNCTION dbo.funcview_TransferOrderDetailsSTS;
END
ELSE IF OBJECT_ID('dbo.funcview_TransferOrderDetailsSTS', 'IF') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.funcview_TransferOrderDetailsSTS', 'funcview_TransferOrderDetailsSTS_OLD_08182026132940';
END
GO

CREATE FUNCTION [dbo].[funcview_TransferOrderDetailsSTS]
(
    @parmbranchcode char(3),
    @parmpono varchar(10)
)
RETURNS TABLE
AS
RETURN
(
    WITH Lines AS (
        SELECT
            a.PONumber,
            a.SeqNo,
            a.ProductCode,
            a.Qty AS RequestedQty,
            a.Units
        FROM dbo.TransferOrderDetails AS a
        WHERE a.PONumber = @parmpono
    ),
    ProductTotals AS (
        SELECT ProductCode, SUM(RequestedQty) AS TotalRequestedQty
        FROM Lines
        GROUP BY ProductCode
    ),
    Inv AS (
        SELECT
            i.Product,
            SUM(i.Available) AS AvailableInv
        FROM dbo.Inventory AS i
        WHERE i.Branch = @parmbranchcode
          AND i.IsWarehouse = 1
          AND i.Available > 0
        GROUP BY i.Product
    )
    SELECT
        r.PONumber,
        r.SeqNo,
        pc.Description AS Category,
        r.ProductCode,
        CONCAT(r.ProductCode,' - ',p.Description) AS Product,
        p.Description AS ProductName,
        p.Barcode,
        r.RequestedQty AS QtyRequested,
        COALESCE(inv.AvailableInv, 0) AS AvailableInv,
        ISNULL(r.RequestedQty,0) AS ApprovedQty,
        ISNULL(r.RequestedQty,0) AS Qty,
        CASE
            WHEN COALESCE(inv.AvailableInv, 0) = 0 THEN 'NO INVENTORY'
            WHEN COALESCE(inv.AvailableInv, 0) < pt.TotalRequestedQty THEN 'NEGATIVE INVENTORY'
            ELSE 'PASSED'
        END AS Status
    FROM Lines AS r
    JOIN ProductTotals AS pt
      ON pt.ProductCode = r.ProductCode
    JOIN dbo.Products AS p
      ON p.ProductCode = r.ProductCode
     AND p.BranchCode  = @parmbranchcode
    LEFT JOIN Inv AS inv
      ON inv.Product = r.ProductCode
    LEFT JOIN dbo.ProductCategory AS pc
      ON pc.ProductCategoryID = p.ProductCategoryCode
);
GO

PRINT 'DEPLOYMENT COMPLETE: funcview_TransferOrderDetailsSTS restored with ProductCode/QtyRequested/Qty columns.';
