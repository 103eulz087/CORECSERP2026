SET NOCOUNT ON;
PRINT '=== ENZODEV funcview_TransferOrderDetailsSTS: add synthetic SeqNo for TVP compatibility ===';
GO

-- =============================================
-- CONTEXT: dbo.TransferItemType / sp_AddBranchOrderBatch were just extended
-- (dev/staging, see SQL/2026-08-18_TransferItemType_AddSeqNo.sql) to carry a
-- real per-line SeqNo end-to-end, so AddBranchOrderSTSBatchMode.cs's
-- executeTransfer() can dedupe/skip-match by an actually-unique key instead
-- of ProductCode (which can legitimately repeat across lines on dev/staging's
-- per-line grid). The C# side now unconditionally reads a "SeqNo" grid
-- column and sends it in the TVP.
--
-- ENZODEV's funcview_TransferOrderDetailsSTS is a genuinely different,
-- deliberate design -- it aggregates TransferOrderDetails by ProductCode
-- (GROUP BY a.ProductCode, a.PONumber; SeqNo is explicitly commented out of
-- the source CTE: "--a.SeqNo,"), showing one row per product per PO, not one
-- row per line. This is NOT being changed here -- rewriting it to per-line
-- grain like dev's version would alter what every screen using this
-- function shows (POForApprovalSTS.cs, ReceivedSTS.cs, this batch-mode
-- screen), which is a much bigger change than requested.
--
-- FIX: add a synthetic SeqNo via ROW_NUMBER() over the already-aggregated
-- result set. Since each output row here is already unique per ProductCode
-- (by construction of the GROUP BY), this ROW_NUMBER is stable and unique
-- per row for the lifetime of a single function call -- it satisfies the
-- new TVP contract without changing any existing aggregation/display
-- behavior. Every other column is untouched.
-- =============================================

IF OBJECT_ID('dbo.funcview_TransferOrderDetailsSTS_OLD_08182026172650', 'IF') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.funcview_TransferOrderDetailsSTS', 'IF') IS NOT NULL
        DROP FUNCTION dbo.funcview_TransferOrderDetailsSTS;
END
ELSE IF OBJECT_ID('dbo.funcview_TransferOrderDetailsSTS', 'IF') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.funcview_TransferOrderDetailsSTS', 'funcview_TransferOrderDetailsSTS_OLD_08182026172650';
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
    WITH Req AS (
    SELECT
        a.PONumber,
        a.ProductCode,
        SUM(a.Qty) AS RequestedQty,
        MAX(a.Units) AS Units
    FROM dbo.TransferOrderDetails AS a
    WHERE a.PONumber = @parmpono
    GROUP BY a.ProductCode,a.PONumber
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
    ROW_NUMBER() OVER (ORDER BY r.ProductCode) AS SeqNo,
    r.PONumber,
    pc.Description AS Category,
    r.ProductCode,
    p.Description AS ProductName,
    p.Barcode,
    r.RequestedQty AS QtyRequested,
    r.RequestedQty AS Qty,
    COALESCE(inv.AvailableInv, 0) AS AvailableInv,
    CASE
        WHEN COALESCE(inv.AvailableInv, 0) = 0 THEN 'NO INVENTORY'
        WHEN COALESCE(inv.AvailableInv, 0) < r.RequestedQty THEN 'NEGATIVE INVENTORY'
        ELSE 'PASSED'
    END AS Status
FROM Req AS r
JOIN dbo.Products AS p
  ON p.ProductCode = r.ProductCode
 AND p.BranchCode  = @parmbranchcode
LEFT JOIN Inv AS inv
  ON inv.Product = r.ProductCode
LEFT JOIN dbo.ProductCategory AS pc
  ON pc.ProductCategoryID = p.ProductCategoryCode
);
GO

PRINT 'DEPLOYMENT COMPLETE: funcview_TransferOrderDetailsSTS (ENZODEV) now exposes a synthetic SeqNo, aggregation/display behavior unchanged.';
