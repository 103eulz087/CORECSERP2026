-- ============================================================================
-- funcview_CustomerSalesInvoiceDetails
-- ============================================================================
-- New detail-level data source for POSSalesReportDevEx's "SalesTransactionSummary"
-- tab -> "Details" radio button, which is being converted to a Master-Detail grid:
--   Master  = dbo.funcview_CustomerSalesHistoryDetails (unchanged, one row per
--             Customer+Invoice, sourced from BatchSalesSummary)
--   Detail  = this new function (one row per line item within that invoice)
--
-- NOT a modification of the existing dbo.funcview_CustomerSalesJournal, even
-- though this is modeled on its shape/join chain per the user's request --
-- that function is still actively used by POSSalesReportDevEx's separate
-- Cash Receipts Book / Sales Journal section (simpleButton2_Click ->
-- populateSalesJournal()) and must not change. Per CLAUDE.md convention, this
-- new report gets its own dedicated SQL object instead of a shared/mutated one.
--
-- Relation-key note (CLAUDE.md known bug pattern #7, same shape applied to a
-- new key): verified live that DeliverySummary.InvoiceNo is NOT globally
-- unique -- several InvoiceNo values repeat across DIFFERENT BranchCodes
-- (e.g. '1' spans 3 branches, '112233' spans 2). A bare Invoice/InvoiceNo
-- join between master and detail would silently pull another branch's line
-- items into a customer's invoice detail. Also verified live that
-- BatchSalesSummary.Invoice and DeliverySummary.InvoiceNo are the same value
-- space (join matches branch + PONumber/DeliveryNo chain on every sampled
-- row), and that InventoryDeliveryFIFO.BranchCode never disagrees with
-- BatchSalesSummary.BranchCode for the same invoice (checked live, zero
-- mismatches). Fix: this function exposes a composite InvoiceKey =
-- BranchCode+'|'+InvoiceNo, and the C# side derives the same composite key
-- from the master's output to relate the two grids safely.
--
-- Customer lookup fix (sp-reviewer finding, verified live): the original
-- draft reached Customers via a LEFT JOIN TransactionChargeSales -> INNER
-- JOIN Customers ON TransactionChargeSales.CustomerKey. Because the
-- following join was INNER, any row where TransactionChargeSales had no
-- match was silently dropped entirely -- and live data showed only 5 of 405
-- distinct POs in InventoryDeliveryFIFO actually have a matching
-- TransactionChargeSales row (that table is scoped to charge/AR-style
-- transactions specifically, not sales in general). That would have deleted
-- ~99% of line items from the Details grid. Fixed by reaching Customers via
-- BatchSalesSummary instead (BranchCode+Invoice -> CustomerNo -> Customers),
-- the same reliable path the master function already trusts -- verified live
-- that (BranchCode, Invoice) is unique in BatchSalesSummary (no fan-out
-- risk) and covers 402 of the same 405 POs. TransactionChargeSales is kept
-- as a LEFT JOIN purely for the optional PayStatus column (legitimately NULL
-- for a cash sale that never created a charge-sales record -- not a bug).
-- Known limitation: the residual 3/405 POs with no BatchSalesSummary row
-- (likely legacy/manually-entered deliveries never invoiced through the
-- batch POS flow) will not appear in this report; flagged here rather than
-- silently unaddressed.
--
-- Credit-memo overcounting fix (sp-reviewer finding, verified live): a
-- DeliveryDetails line with isCreditMemo=1 carries its full ActualQty/Amount
-- at the LINE level, but InventoryDeliveryFIFO can hold MULTIPLE per-lot FIFO
-- rows for that same line (confirmed live: one line fanned out across 50
-- FIFO lots). Copying the reference function's (funcview_CustomerSalesJournal)
-- logic verbatim would have emitted that line's full Amount/QtyDelivered once
-- per FIFO lot, inflating footer sums by that many times. Fixed by keeping
-- the per-lot fan-out only for ordinary (non-credit-memo) sale rows, where
-- a.QtyDelivered genuinely is the per-lot portion, and collapsing credit-memo
-- rows to exactly one row per DeliveryDetails line via ROW_NUMBER().
--
-- Unlike funcview_CustomerSalesJournal, Amount/Cost/CostOfSalesAmount are
-- kept as real DECIMAL here (not FORMAT()-ed to nvarchar) so the grid's
-- footer-sum summaries work; display formatting is applied in the grid
-- column, not in SQL.
-- ============================================================================

CREATE FUNCTION dbo.funcview_CustomerSalesInvoiceDetails
(
    @BranchCode CHAR(3),
    @datefrom   DATE,
    @dateto     DATE
)
RETURNS TABLE
AS
RETURN
(
    WITH FIFOLines AS
    (
        SELECT
            a.BranchCode,
            a.PONumber,
            d.InvoiceNo,
            d.DateAdded AS InvoiceDate,
            CASE WHEN c.isCreditMemo = 1 THEN c.ActualQty
                 WHEN c.isReturned = 1 THEN 0
                 ELSE a.QtyDelivered END AS QtyDelivered,
            b.ReferenceCode AS ItemID,
            a.ProductNo,
            a.Description,
            c.SellingPrice AS UnitPrice,
            CASE WHEN c.isCreditMemo = 1 THEN (c.SellingPrice * c.ActualQty)
                 WHEN c.isReturned = 1 THEN 0
                 ELSE (c.SellingPrice * a.QtyDelivered) END AS Amount,
            c.Cost,
            CASE WHEN c.isCreditMemo = 1 THEN (c.Cost * c.ActualQty)
                 ELSE (c.Cost * a.QtyDelivered) END AS CostOfSalesAmount,
            c.isReturned,
            c.isCreditMemo,
            -- Only meaningful/used for isCreditMemo=1 rows -- collapses the
            -- per-FIFO-lot fan-out down to exactly one row per DeliveryDetails
            -- line so its line-level ActualQty/Amount isn't counted N times.
            ROW_NUMBER() OVER (
                PARTITION BY c.PONumber, c.DeliveryNo, c.ProductNo, c.SeqNo
                ORDER BY a.SequenceReferenceNumber
            ) AS LotRowNum
        FROM dbo.InventoryDeliveryFIFO a
        INNER JOIN dbo.Inventory b
            ON a.SequenceReferenceNumber = b.SequenceNumber
        INNER JOIN dbo.DeliveryDetails c
            ON a.PONumber = c.PONumber
            AND a.DeliveryNo = c.DeliveryNo
            AND a.ProductNo = c.ProductNo
            AND a.DevDetSeqNo = c.SeqNo
            AND c.isCancelled = 0
        INNER JOIN dbo.DeliverySummary d
            ON d.PONumber = c.PONumber
            AND d.DeliveryNo = c.DeliveryNo
        WHERE (@BranchCode = 'ALL' OR a.BranchCode = @BranchCode)
    )
    SELECT
        cu.CustomerKey,
        cu.CustomerID,
        cu.CustomerName,
        a.BranchCode,
        CONCAT(a.BranchCode, ' - ', br.BranchName) AS Branch,
        a.InvoiceNo,
        a.BranchCode + '|' + ISNULL(a.InvoiceNo, '') AS InvoiceKey,
        CAST(a.InvoiceDate AS DATE) AS InvoiceDate,
        a.PONumber,
        CONCAT(a.ProductNo, ' - ', a.Description) AS Product,
        a.QtyDelivered,
        a.UnitPrice,
        a.Amount,
        a.Cost,
        a.CostOfSalesAmount,
        tcs.PayStatus,
        cu.AccountOfficer,
        a.isCreditMemo,
        a.isReturned
    FROM FIFOLines a
    INNER JOIN dbo.BatchSalesSummary bss
        ON bss.BranchCode = a.BranchCode
        AND bss.Invoice = a.InvoiceNo
    INNER JOIN dbo.Customers cu
        ON bss.CustomerNo = cu.CustomerKey
    LEFT OUTER JOIN dbo.TransactionChargeSales tcs
        ON a.BranchCode = tcs.BranchCode
        AND a.PONumber = tcs.ReferenceNo
    INNER JOIN dbo.Branches br
        ON a.BranchCode = br.BranchCode
    WHERE a.InvoiceDate >= @datefrom
        AND a.InvoiceDate < DATEADD(DAY, 1, @dateto)
        AND (a.isCreditMemo = 0 OR a.LotRowNum = 1)
);
GO
