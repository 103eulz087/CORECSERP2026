-- 2026-09-23: view_POSUMMARYREP -- TotalQty/TotalCost/TotalActualCost must
-- be numeric, not FORMAT()-ed NVARCHAR, so grids bound to this view (VIEWPO.cs's
-- FOR APPROVAL/APPROVED/FOR CONFIRMATION/CONFIRMED tabs, all four bound via
-- SELECT * through LoadGrid) can right-align/sort/sum them. Same anti-pattern
-- already fixed several times this session in various SPs -- this is the
-- first time it's in a VIEW rather than a proc, so it has much wider reach.
--
-- CONSUMER CHECK (grepped every .cs file referencing view_POSUMMARYREP,
-- 9 files total) before making this change:
--   - ViewLinkedPODetailsFrm.cs, ItemCostingReconReport.cs: read TotalActualCost/
--     TotalQty via Convert.ToDecimal(...)/a typed reader helper -- already
--     worked against the FORMAT()-ed string (Convert.ToDecimal parses a
--     thousands-separated string fine in en-US culture) and works unchanged
--     against a native decimal.
--   - VIEWPO.cs's showServicesForConfirmation() (Services/OrderType='S' tab,
--     NOT one of the four Products tabs this change targets) reads TotalCost
--     via .ToString() into a plain display textbox (CONFIRMPO.txtamountpayable)
--     -- still works, just loses the thousands-separator cosmetically (e.g.
--     "907500.00" instead of "907,500.00"); not a crash, not in either of the
--     two out-of-scope-but-checked callers' critical paths.
--   - All other consumers (AddExpenseDevExFrm.cs x2, PostExpenseDevExFrm.cs,
--     PrimalCutCosting.cs, PurchaseOrderRepDevEx.cs, AddExpenseDevExFrmTest.cs)
--     only reference ShipmentNo/SupplierName/other non-numeric columns from
--     this view -- unaffected.
-- No consumer parses these columns as strings (Substring/Split/LIKE) or
-- concatenates them into further SQL text, so the type change is safe.
--
-- TotalItems is already a native DECIMAL in this view (not changed here) --
-- only the C# grid-side numeric format was missing for it, fixed in VIEWPO.cs.

IF OBJECT_ID('dbo.view_POSUMMARYREP', 'V') IS NOT NULL
    EXEC sp_rename 'dbo.view_POSUMMARYREP', 'view_POSUMMARYREP_OLD_09232026020000';
GO

CREATE VIEW [dbo].[view_POSUMMARYREP]
AS
    SELECT  a.ShipmentNo,
            a.BranchCode,
            a.SupplierID,
            b.SupplierName,
            a.TargetDate,
            a.TotalItems,
            CAST(a.TotalQty AS DECIMAL(18,3))        AS TotalQty,
            CAST(a.TotalCost AS DECIMAL(18,2))        AS TotalCost,
            CAST(a.TotalActualCost AS DECIMAL(18,2))  AS TotalActualCost,
            a.Status,
            a.DateOrder,
            UPPER(a.OrderedBy) AS OrderedBy,
            a.ApprovedDate,
            UPPER(a.ApprovedBy) AS ApprovedBy,
            a.ReceivedDate,
            UPPER(a.ReceivedBy) AS ReceivedBy,
            a.Remarks
            ,a.OrderType
            ,a.ReceivedDate as ConfirmedDate
            ,UPPER(a.ReceivedBy) AS ConfirmedBy
    FROM POSUMMARY as a
    INNER JOIN Supplier as b
    ON a.SupplierID=b.SupplierID
GO
