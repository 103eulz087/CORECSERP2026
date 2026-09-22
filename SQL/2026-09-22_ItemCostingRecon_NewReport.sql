/* ================================================================
   ITEM COSTING RECON -- new report (Reporting/ItemCostingReconReport.cs)
   ================================================================
   Purpose: for one PO ShipmentNo, show exactly how spu_PostExpenseV2
   incorporated cost into Inventory.Cost, one linked expense at a time,
   so a user can reconcile the final landed cost instead of having to
   manually cross-reference ExpenseSummary/ExpenseMaster/Inventory.

   MECHANISM (verified live against CORECSERP_002_DEV, ShipmentNo 11010,
   which reproduces the user's worked example exactly):
     spu_PostExpenseV2, when @isLinkedToPO=1, does:
         @invsumQty = SUM(Inventory.Quantity) WHERE ShipmentNo=@ShipmentNo
         UPDATE Inventory SET Cost = Cost + (@TotalAmount / @invsumQty)
         WHERE ShipmentNo = @ShipmentNo
     i.e. EVERY linked SINGLE-mode expense (including the base AP invoice
     for the goods themselves -- it is posted the same way as freight/
     customs/brokerage/packaging here) adds Amount/ShipmentTotalOrderedQty
     to every lot's cost, uniformly across the whole shipment.

   SCOPE CHECK: grepped every proc/function in this DB referencing
   isLinkedToPO -- only spu_PostExpenseV2 (and its edit wrapper
   sp_EditSingleExpense, which just re-invokes it) ever do this. There is
   no BATCH-mode equivalent today, so PostingMode='SINGLE' is the
   complete set of cost-incorporating expenses, not an arbitrary filter.

   Two result sets (Reporting ps skill convention):
     sp_rpt_ItemCostingRecon_Header  -- one row: PO/shipment summary +
                                        total incorporated cost + variance
                                        against the live Inventory.Cost.
     sp_rpt_ItemCostingRecon_Detail  -- one row per linked SINGLE-mode
                                        expense, with its derived
                                        per-unit cost contribution and a
                                        running total (window function,
                                        ROWS UNBOUNDED PRECEDING so a
                                        same-day tie doesn't corrupt it).

   Deploy to CORECSERP_002_DEV first; mirror to CORECSJFC2026_STAGING
   only after confirming with the user, per project convention.
   ================================================================ */

-- ----------------------------------------------------------------
-- 1. Header
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_ItemCostingRecon_Header', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_ItemCostingRecon_Header', 'sp_rpt_ItemCostingRecon_Header_OLD_20260922130000';
GO

CREATE PROCEDURE dbo.sp_rpt_ItemCostingRecon_Header
(
    @ShipmentNo VARCHAR(10)
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Scalar, not an inner-joined CTE (sp-reviewer catch 2026-09-22): a
    -- shipment can have linked SINGLE expenses posted before Inventory
    -- ever gets rows for it (not yet received / fully written off to
    -- zero qty). Joining ExpenseSummary to a qty-derived CTE would drop
    -- those expenses out of the count/total entirely instead of
    -- surfacing them as an un-reconciled 0-qty case.
    DECLARE @TotalQty DECIMAL(18,3) =
        (SELECT SUM(Quantity) FROM dbo.Inventory WHERE ShipmentNo = @ShipmentNo);

    ;WITH ShipmentCost AS (
        SELECT MIN(Cost) AS MinCost, MAX(Cost) AS MaxCost
        FROM dbo.Inventory
        WHERE ShipmentNo = @ShipmentNo
    ),
    Incorporated AS (
        SELECT
            SUM(CAST(es.Amount AS DECIMAL(18,4)) / NULLIF(@TotalQty, 0)) AS TotalCostIncorporated,
            COUNT(*) AS ExpenseCount
        FROM dbo.ExpenseSummary es
        WHERE es.ShipmentNo = @ShipmentNo
          AND es.PostingMode = 'SINGLE'
    )
    SELECT
        p.ShipmentNo,
        p.SupplierID,
        p.SupplierName,
        p.BranchCode,
        p.Status,
        p.OrderType,
        p.DateOrder,
        CAST(ISNULL(@TotalQty, 0) AS DECIMAL(18,3))              AS TotalQty,
        CAST(ISNULL(sc.MinCost, 0) AS DECIMAL(18,4))             AS CurrentMinCost,
        CAST(ISNULL(sc.MaxCost, 0) AS DECIMAL(18,4))             AS CurrentMaxCost,
        CAST(ISNULL(i.TotalCostIncorporated, 0) AS DECIMAL(18,4)) AS TotalCostIncorporated,
        ISNULL(i.ExpenseCount, 0)                                AS LinkedExpenseCount,
        CAST(ISNULL(sc.MaxCost, 0) - ISNULL(i.TotalCostIncorporated, 0) AS DECIMAL(18,4)) AS Variance,
        -- Tolerance instead of exact equality (sp-reviewer catch): the
        -- live Cost column accumulates via a sequence of separate
        -- UPDATE ... SET Cost = Cost + (...) statements, one per posted
        -- expense, so immaterial rounding drift against this report's
        -- own end-to-end DECIMAL(18,4) sum is expected, not an error.
        -- Computed once here so SQL and UI can't disagree on the verdict.
        CAST(CASE WHEN ABS(ISNULL(sc.MaxCost, 0) - ISNULL(i.TotalCostIncorporated, 0)) <= 0.01
                  THEN 1 ELSE 0 END AS BIT) AS IsMatched
    FROM dbo.view_POSUMMARYREP p
    CROSS JOIN ShipmentCost sc
    CROSS JOIN Incorporated i
    WHERE p.ShipmentNo = @ShipmentNo;
END
GO

-- ----------------------------------------------------------------
-- 2. Detail -- one row per linked SINGLE-mode expense, with running total
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_ItemCostingRecon_Detail', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_ItemCostingRecon_Detail', 'sp_rpt_ItemCostingRecon_Detail_OLD_20260922130000';
GO

CREATE PROCEDURE dbo.sp_rpt_ItemCostingRecon_Detail
(
    @ShipmentNo VARCHAR(10)
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TotalQty DECIMAL(18,3) =
        (SELECT SUM(Quantity) FROM dbo.Inventory WHERE ShipmentNo = @ShipmentNo);

    SELECT
        es.ReferenceNumber,
        es.InvoiceNo,
        es.SupplierID,
        ISNULL(s.SupplierName, es.SupplierID) AS SupplierName,
        es.ExpenseDate,
        es.Description AS Remarks,
        CAST(es.Amount AS DECIMAL(18,2)) AS Amount,
        CAST(es.Amount / NULLIF(@TotalQty, 0) AS DECIMAL(18,4)) AS CostDerived,
        CAST(
            SUM(es.Amount / NULLIF(@TotalQty, 0)) OVER (
                ORDER BY es.ExpenseDate, es.ReferenceNumber
                ROWS UNBOUNDED PRECEDING)
        AS DECIMAL(18,4)) AS RunningTotal
    FROM dbo.ExpenseSummary es
    LEFT JOIN dbo.Supplier s ON s.SupplierKey = es.SupplierID
    WHERE es.ShipmentNo = @ShipmentNo
      AND es.PostingMode = 'SINGLE'
    ORDER BY es.ExpenseDate, es.ReferenceNumber;
END
GO
