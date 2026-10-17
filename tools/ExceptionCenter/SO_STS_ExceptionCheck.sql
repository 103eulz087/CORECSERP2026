/* ================================================================
   Exception Center: Sales Order + STS lifecycle health check
   ================================================================
   READ-ONLY. Safe to run any time, on DEV or STAGING (temp tables only).
   Run it after every change to a Sales Order / STS procedure, and on a
   schedule (daily while the system is new, then weekly).

   Result set 1 = one row per check: how many exceptions, what it means,
                  what to do. A healthy database shows Found = 0 everywhere
                  (INFO rows are only for reading).
   Result set 2 = the exception rows themselves (one row per PO / lot / ticket).

   @FromDate limits the checks that compare money to activity on or after
   that date. Older history has known gaps from before the 2026-10-01 fixes
   (see docs/CLAUDE_WORKLOG.md, Features 14 / 15); widen the date only to
   look at them on purpose. Stock checks (X01, X03) always cover everything;
   the In Transit checks (T01-T04) use @StsFromDate (all STS since go-live).

   When a new failure mode is found, add a check here (next free code in
   its group) and record it in docs/CLAUDE_WORKLOG.md.
   ================================================================ */
SET NOCOUNT ON;

DECLARE @FromDate    DATE = '2026-10-02';   -- money checks: activity on or after this date (first full day on the 2026-10-01 fixes)
DECLARE @StsFromDate DATE = '2026-08-01';   -- In Transit checks (T01-T04): money stuck in transit matters whenever it started
DECLARE @VatRuleDate DATE = '2026-10-02';   -- GL is all VAT-exempt from this date (client rule)
DECLARE @Tol         DECIMAL(18,2) = 0.05;  -- rounding tolerance

IF OBJECT_ID('tempdb..#X') IS NOT NULL DROP TABLE #X;
CREATE TABLE #X (
    CheckCode VARCHAR(5)    NOT NULL,
    PONumber  VARCHAR(20)   NULL,
    Ref       VARCHAR(60)   NULL,      -- lot / ticket / invoice / customer
    Expected  DECIMAL(18,2) NULL,
    Actual    DECIMAL(18,2) NULL,
    Detail    VARCHAR(400)  NULL
);

-- accounts from the mapping (never hard-coded)
DECLARE @TransitVat   VARCHAR(50) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'IT-HO-VAT'   AND DebitCredit = 'D' AND IsActive = 1 ORDER BY Seq);
DECLARE @TransitVatEx VARCHAR(50) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'IT-HO-VATEX' AND DebitCredit = 'D' AND IsActive = 1 ORDER BY Seq);
DECLARE @ARAcct       VARCHAR(50) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'SI-VATEX'    AND DebitCredit = 'D' AND AmountType = 'GROSS' AND IsActive = 1 ORDER BY Seq);
DECLARE @COSAcct      VARCHAR(50) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'SI-VATEX'    AND DebitCredit = 'D' AND AmountType = 'COST'  AND IsActive = 1 ORDER BY Seq);

------------------------------------------------------------------
-- X. STOCK (Sales Order and STS share these tables)
------------------------------------------------------------------
-- X01 cancelled / returned line still holding live lots = stock never went back to the source branch
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'X01', f.PONumber, 'lot ' + CAST(f.SequenceReferenceNumber AS VARCHAR(20)), 0, f.QtyDelivered,
       CASE WHEN t.PONumber IS NOT NULL THEN 'STS' ELSE 'SO' END + ' line ' + CAST(dd.SeqNo AS VARCHAR(10)) + ' ' + dd.ProductNo
       + CASE WHEN dd.isCancelled = 1 THEN ' cancelled' ELSE ' returned' END + '; qty still out of the lot'
FROM dbo.InventoryDeliveryFIFO f
INNER JOIN dbo.DeliveryDetails dd ON dd.DeliveryNo = f.DeliveryNo AND dd.PONumber = f.PONumber AND dd.SeqNo = f.DevDetSeqNo
LEFT JOIN dbo.TransferOrderSummary t ON t.PONumber = f.PONumber
WHERE f.isErrorCorrect = 0 AND (dd.isCancelled = 1 OR dd.isReturned = 1);

-- X02 the qty put back by cancel / return differs from what left the lots (activity since @FromDate)
;WITH Back AS (
    SELECT dd.PONumber, SUM(f.QtyDelivered) AS LeftQty
    FROM dbo.InventoryDeliveryFIFO f
    INNER JOIN dbo.DeliveryDetails dd ON dd.DeliveryNo = f.DeliveryNo AND dd.PONumber = f.PONumber AND dd.SeqNo = f.DevDetSeqNo
    WHERE f.isErrorCorrect = 1 AND dd.isCancelled = 1
      AND dd.DateTimeUpdated >= @FromDate
    GROUP BY dd.PONumber),
Led AS (   -- old cancel 'STS CANCEL ITEM PO#' (sales and STS), Sales V2 cancel 'SO CANCEL ITEM PO#' (2026-10-02c)
    SELECT x.PONumber, SUM(x.QtyIN) AS InQty
    FROM (SELECT CASE WHEN l.Remarks LIKE 'STS CANCEL ITEM PO#%' THEN SUBSTRING(l.Remarks, LEN('STS CANCEL ITEM PO#') + 1, 20)
                      ELSE SUBSTRING(l.Remarks, LEN('SO CANCEL ITEM PO#') + 1, 20) END AS PONumber, l.QtyIN
          FROM dbo.InventoryLedger l
          WHERE (l.Remarks LIKE 'STS CANCEL ITEM PO#%' OR l.Remarks LIKE 'SO CANCEL ITEM PO#%') AND l.DateProcessed >= @FromDate) AS x
    GROUP BY x.PONumber)
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'X02', b.PONumber, 'cancel', b.LeftQty, ISNULL(l.InQty, 0), 'cancelled lines: qty taken from lots vs qty put back (stock ledger)'
FROM Back b LEFT JOIN Led l ON l.PONumber = b.PONumber
WHERE ABS(b.LeftQty - ISNULL(l.InQty, 0)) > 0.001;

;WITH Ret AS (
    SELECT r.PONumber, SUM(r.ActualQty) AS RetQty
    FROM dbo.ReturnedOrderDetails r
    WHERE r.DateProcessed >= @FromDate
    GROUP BY r.PONumber),
Led AS (
    SELECT SUBSTRING(l.Remarks, LEN('SO RETURN PO#') + 1, 20) AS PONumber, SUM(l.QtyIN) AS InQty
    FROM dbo.InventoryLedger l
    WHERE l.Remarks LIKE 'SO RETURN PO#%' AND l.DateProcessed >= @FromDate
    GROUP BY SUBSTRING(l.Remarks, LEN('SO RETURN PO#') + 1, 20))
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'X02', r.PONumber, 'return', r.RetQty, ISNULL(l.InQty, 0), 'sales return: billed qty returned vs qty put back (stock ledger)'
FROM Ret r LEFT JOIN Led l ON l.PONumber = r.PONumber
WHERE ABS(r.RetQty - ISNULL(l.InQty, 0)) > 0.001
  AND EXISTS (SELECT 1 FROM dbo.PurchaseOrderSummary p WHERE p.PONumber = r.PONumber);

-- X03 impossible lot quantity
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'X03', NULL, 'lot ' + CAST(i.SequenceNumber AS VARCHAR(20)), i.Quantity, i.Available,
       i.Branch + ' ' + i.Product + ' ' + ISNULL(i.ShipmentNo, '') + CASE WHEN i.Available < 0 THEN ': Available below 0' ELSE ': Available above Quantity' END
FROM dbo.Inventory i
WHERE i.Available < -0.001 OR i.Available > i.Quantity + 0.001;

-- X04 live sold / shipped lot cost no longer equals the lot's cost (cost changed after the sale) — INFO
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'X04', f.PONumber, 'lot ' + CAST(f.SequenceReferenceNumber AS VARCHAR(20)), i.Cost, f.Cost,
       f.ProductNo + ' qty ' + CAST(CAST(f.QtyDelivered AS DECIMAL(18,3)) AS VARCHAR(30)) + '; cost effect '
       + CAST(CAST(f.QtyDelivered * (i.Cost - f.Cost) AS DECIMAL(18,2)) AS VARCHAR(30))
FROM dbo.InventoryDeliveryFIFO f
INNER JOIN dbo.Inventory i ON i.SequenceNumber = f.SequenceReferenceNumber
WHERE f.isErrorCorrect = 0 AND f.Cost <> i.Cost AND f.DateProcessed >= @FromDate;

-- X05 a partly returned line (2026-10-04 split) whose live lot qty no longer equals its delivered qty
IF OBJECT_ID('dbo.SalesReturnLog', 'U') IS NOT NULL
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'X05', dd.PONumber, 'line ' + CAST(dd.SeqNo AS VARCHAR(10)), dd.QtyDelivered, ISNULL(f.Qty, 0),
       dd.ProductNo + ': delivered qty vs live lot qty after a partial return'
FROM dbo.DeliveryDetails dd
OUTER APPLY (SELECT SUM(CAST(x.QtyDelivered AS DECIMAL(18,3))) AS Qty FROM dbo.InventoryDeliveryFIFO x
             WHERE x.PONumber = dd.PONumber AND x.DeliveryNo = dd.DeliveryNo AND x.DevDetSeqNo = dd.SeqNo AND x.isErrorCorrect = 0) f
WHERE dd.isCancelled = 0 AND dd.isReturned = 0
  AND EXISTS (SELECT 1 FROM dbo.SalesReturnLog l WHERE l.IsPartial = 1 AND l.PONumber = dd.PONumber AND l.DeliveryNo = dd.DeliveryNo AND l.SourceSeqNo = dd.SeqNo)
  AND ABS(dd.QtyDelivered - ISNULL(f.Qty, 0)) > 0.001;

------------------------------------------------------------------
-- S. SALES ORDER
------------------------------------------------------------------
IF OBJECT_ID('tempdb..#SO') IS NOT NULL DROP TABLE #SO;
SELECT p.PONumber, p.Status, p.Customer
INTO #SO
FROM dbo.PurchaseOrderSummary p
WHERE p.EffectivityDate >= @FromDate
   OR EXISTS (SELECT 1 FROM dbo.TicketMaster tm WHERE tm.ReferenceNumber = p.PONumber AND tm.TicketDate >= @FromDate
                AND (tm.Mnemonic LIKE 'SI-%' OR tm.Mnemonic LIKE 'SO-%'));

-- S01 confirmed order without exactly one invoice, or without a sales ticket
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'S01', s.PONumber, NULL, 1, x.nInv,
       'DELIVERED order: invoices found = ' + CAST(x.nInv AS VARCHAR(10)) + ', SI tickets found = ' + CAST(x.nTk AS VARCHAR(10))
FROM #SO s
CROSS APPLY (SELECT (SELECT COUNT(*) FROM dbo.TransactionChargeSales c WHERE c.ReferenceNo = s.PONumber) AS nInv,
                    (SELECT COUNT(*) FROM dbo.TicketMaster tm WHERE tm.ReferenceNumber = s.PONumber AND tm.Mnemonic LIKE 'SI-%' AND tm.Status = 'POSTED') AS nTk) x
WHERE s.Status = 'DELIVERED' AND (x.nInv <> 1 OR x.nTk = 0);

-- S02 invoice balance does not follow its own columns
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'S02', c.ReferenceNo, c.InvoiceNo,
       ISNULL(c.TotalAmount, 0) - ISNULL(c.AmountPaid, 0) - ISNULL(c.EWTAmount, 0) - ISNULL(c.DiscountAmount, 0) - ISNULL(c.OffsetAmount, 0),
       c.Balance, 'Balance <> TotalAmount - AmountPaid - EWT - Discount - Offset (' + ISNULL(c.PayStatus, '') + ')'
FROM dbo.TransactionChargeSales c
INNER JOIN #SO s ON s.PONumber = c.ReferenceNo
WHERE ABS(ISNULL(c.Balance, 0) - (ISNULL(c.TotalAmount, 0) - ISNULL(c.AmountPaid, 0) - ISNULL(c.EWTAmount, 0)
          - ISNULL(c.DiscountAmount, 0) - ISNULL(c.OffsetAmount, 0))) > @Tol;

-- S03 the order's AR in the GL (sale - credit memos - returns) differs from the invoice
--     expected = TotalAmount - DiscountAmount + AdvancePayment (excess moved to customer credit)
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'S03', c.ReferenceNo, c.InvoiceNo,
       ISNULL(c.TotalAmount, 0) - ISNULL(c.DiscountAmount, 0) + ISNULL(c.AdvancePayment, 0), g.AR,
       'GL AR on SI / SO-CM / SO-RET tickets vs invoice (TotalAmount - Discount + AdvancePayment)'
FROM dbo.TransactionChargeSales c
INNER JOIN #SO s ON s.PONumber = c.ReferenceNo
CROSS APPLY (SELECT ISNULL(SUM(td.Debit - td.Credit), 0) AS AR
             FROM dbo.TicketMaster tm
             INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
             WHERE tm.ReferenceNumber = c.ReferenceNo AND td.AccountCode = @ARAcct
               AND (tm.Mnemonic LIKE 'SI-%' OR tm.Mnemonic LIKE 'SO-CM-%' OR tm.Mnemonic LIKE 'SO-RET-%')) g
WHERE s.Status = 'DELIVERED'
  AND ABS(g.AR - (ISNULL(c.TotalAmount, 0) - ISNULL(c.DiscountAmount, 0) + ISNULL(c.AdvancePayment, 0))) > @Tol;

-- S04 sales ticket cost of sales differs from the invoice's COGS rows
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'S04', s.PONumber, NULL, x.Cogs, x.TkCost, 'SI ticket cost of sales vs TransactionChargeSalesDetails COGS rows'
FROM #SO s
CROSS APPLY (SELECT (SELECT ISNULL(SUM(d.TotalAmount), 0) FROM dbo.TransactionChargeSalesDetails d
                     WHERE d.ReferenceNo = s.PONumber AND d.TransCode LIKE 'COGS-%') AS Cogs,
                    (SELECT ISNULL(SUM(td.Debit), 0) FROM dbo.TicketMaster tm
                     INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
                     WHERE tm.ReferenceNumber = s.PONumber AND tm.Mnemonic LIKE 'SI-%'
                       AND td.AccountCode IN (SELECT AccountCode FROM dbo.JournalEntryMapping
                                              WHERE Mnemonic IN ('SI-VAT', 'SI-VATEX') AND AmountType = 'COST' AND DebitCredit = 'D')) AS TkCost) x
WHERE s.Status = 'DELIVERED' AND ABS(x.Cogs - x.TkCost) > @Tol;

-- S05 status out of step: order vs delivery header
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'S05', s.PONumber, d.DeliveryNo, NULL, NULL, 'order status ' + ISNULL(s.Status, '') + ' but delivery status ' + ISNULL(d.Status, '')
FROM #SO s
INNER JOIN dbo.DeliverySummary d ON d.PONumber = s.PONumber
WHERE CASE WHEN s.Status = 'DELIVERED' THEN 1 ELSE 0 END <> CASE WHEN d.Status IN ('DELIVERED', 'RETURNED') THEN 1 ELSE 0 END   -- a fully returned order keeps PO DELIVERED
  -- 2026-10-05: fully returned BEFORE confirm (never invoiced) is valid: delivery RETURNED, order keeps its pre-confirm status
  AND NOT (d.Status = 'RETURNED' AND ISNULL(s.Status, '') <> 'DELIVERED'
           AND NOT EXISTS (SELECT 1 FROM dbo.TransactionChargeSales c WHERE c.ReferenceNo = s.PONumber));

-- S06 (2026-10-14, script [80]) an invoice no. with more than one row (a returned PO re-invoiced under the same no., or
--     another customer's row): a row's paid amount differs from its own payment lines (invoice + PO + customer, payments
--     not reversed). The payment proc before 2026-09-23 23:40 and the reversal proc before [80] matched by invoice no. only
--     and moved other rows (X-009660, C-048113, E2608-01-A on PRODUCTION). All dates: the set is small.
;WITH multi AS (SELECT InvoiceNo FROM dbo.TransactionChargeSales GROUP BY InvoiceNo HAVING COUNT(*) > 1),
pay AS (SELECT d.CustomerKey, d.InvoiceNo, d.PONumber,
               SUM(CASE d.PaymentType WHEN 'INVOICE PAYMENT' THEN d.Amount WHEN 'EWT' THEN -d.Amount
                                      WHEN 'DISCOUNT' THEN -d.Amount WHEN 'OFFSET' THEN -d.Amount ELSE 0 END) AS Paid
        FROM dbo.ARPaymentDetails d
        INNER JOIN dbo.PaymentHeader ph ON ph.PaymentHeaderID = d.PaymentHeaderID
        WHERE ISNULL(ph.Status, '') <> 'REVERSED' AND d.InvoiceNo IN (SELECT InvoiceNo FROM multi)
        GROUP BY d.CustomerKey, d.InvoiceNo, d.PONumber)
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'S06', c.ReferenceNo, c.InvoiceNo, ISNULL(p.Paid, 0), c.AmountPaid,
       'customer ' + c.CustomerKey + ': paid on the row vs its own payment lines (' + ISNULL(c.PayStatus, '') + ', balance '
       + CONVERT(VARCHAR(30), c.Balance) + ')'
FROM dbo.TransactionChargeSales c
INNER JOIN multi m ON m.InvoiceNo = c.InvoiceNo
LEFT JOIN pay p ON p.CustomerKey = c.CustomerKey AND p.InvoiceNo = c.InvoiceNo AND p.PONumber = c.ReferenceNo
WHERE ABS(ISNULL(c.AmountPaid, 0) - ISNULL(p.Paid, 0)) > @Tol
  AND (p.InvoiceNo IS NOT NULL OR ISNULL(c.TotalAmount, 0) = 0 OR ISNULL(c.AmountPaid, 0) < 0);   -- a row paid outside payment lines (cash sale) is not a finding

-- S07 (2026-10-15, script [87], hardening H5) a customer whose account balance differs from the sum of its invoice balances
--     (every TransactionChargeSales row, credits included). The payment proc settles invoices under lock and the ledger trigger
--     recomputes the account, so the two must agree; a hand edit of a Balance, or a payment posted outside the proc, breaks it.
--     All customers, all dates (the set is small: 0 on every tier on 2026-10-15).
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'S07', NULL, c.AccountKey, ISNULL(i.SumBalance, 0), ISNULL(c.AccountBalance, 0),
       'customer ' + c.AccountKey + ': account balance vs the sum of its ' + CONVERT(VARCHAR(10), ISNULL(i.RowCnt, 0)) + ' invoice rows (' + ISNULL(c.AccountName, '') + ')'
FROM dbo.ClientAccounts c
LEFT JOIN (SELECT CustomerKey, SUM(ISNULL(Balance, 0)) AS SumBalance, COUNT(*) AS RowCnt FROM dbo.TransactionChargeSales GROUP BY CustomerKey) i ON i.CustomerKey = c.AccountKey
WHERE ABS(ISNULL(c.AccountBalance, 0) - ISNULL(i.SumBalance, 0)) > @Tol;

-- S08 (2026-10-15, script [87], hardening H5) an invoice row whose Balance does not follow its own columns, ALL rows and dates
--     (S02 covers the sales orders in scope only). Since [87] a payment on such a row is refused (92016) instead of silently
--     resetting the balance, so a drifted row blocks that customer's collections until it is corrected.
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'S08', c.ReferenceNo, c.InvoiceNo,
       ISNULL(c.TotalAmount, 0) - ISNULL(c.AmountPaid, 0) - ISNULL(c.EWTAmount, 0) - ISNULL(c.DiscountAmount, 0) - ISNULL(c.OffsetAmount, 0),
       c.Balance, 'customer ' + c.CustomerKey + ': Balance <> TotalAmount - AmountPaid - EWT - Discount - Offset (' + ISNULL(c.PayStatus, '') + ')'
FROM dbo.TransactionChargeSales c
WHERE ABS(ISNULL(c.Balance, 0) - (ISNULL(c.TotalAmount, 0) - ISNULL(c.AmountPaid, 0) - ISNULL(c.EWTAmount, 0)
          - ISNULL(c.DiscountAmount, 0) - ISNULL(c.OffsetAmount, 0))) > @Tol;

-- S09 (2026-10-15, script [89]) a sales-order delivery whose DeliverySummary counters differ from its lines. Rule (same as
--     dbo.fn_SODelivery_LiveTotals, written out here so the check also runs where [89] is not installed): TotalItem = lines
--     not cancelled, TotalItemSold = of those not returned, TotalItemReturned = of those returned, TotalQtyDelivered =
--     their QtyDelivered, TotalActualQty = ActualQty of the lines not cancelled and not returned. Before [89] most rows show
--     here (TotalItemSold / TotalItemReturned NULL, TotalActualQty 0); after it, 0 unless the triggers are disabled.
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'S09', s.PONumber, 'delivery ' + s.DeliveryNo, a.Item, s.TotalItem,
       'stored item/sold/returned/qty/actual ' + CONCAT(s.TotalItem, '/', s.TotalItemSold, '/', s.TotalItemReturned, '/', s.TotalQtyDelivered, '/', s.TotalActualQty)
       + ' vs lines ' + CONCAT(a.Item, '/', a.Sold, '/', a.Ret, '/', a.Qty, '/', a.Act)
FROM dbo.DeliverySummary s
CROSS APPLY (SELECT COUNT(*) AS Item,
                    ISNULL(SUM(CASE WHEN ISNULL(d.isReturned, 0) = 0 THEN 1 ELSE 0 END), 0) AS Sold,
                    ISNULL(SUM(CASE WHEN ISNULL(d.isReturned, 0) = 1 THEN 1 ELSE 0 END), 0) AS Ret,
                    CAST(ISNULL(SUM(d.QtyDelivered), 0) AS DECIMAL(18,3)) AS Qty,
                    CAST(ISNULL(SUM(CASE WHEN ISNULL(d.isReturned, 0) = 0 THEN ISNULL(d.ActualQty, 0) ELSE 0 END), 0) AS DECIMAL(18,3)) AS Act
             FROM dbo.DeliveryDetails d
             WHERE d.DeliveryNo = s.DeliveryNo AND d.PONumber = s.PONumber AND ISNULL(d.isCancelled, 0) = 0) a
WHERE s.PONumber IS NOT NULL
  AND EXISTS (SELECT 1 FROM dbo.PurchaseOrderSummary p WHERE p.PONumber = s.PONumber)
  AND NOT EXISTS (SELECT 1 FROM dbo.TransferOrderSummary t WHERE t.PONumber = s.PONumber)
  AND (   ISNULL(s.TotalItem, -1) <> a.Item OR ISNULL(s.TotalItemSold, -1) <> a.Sold OR ISNULL(s.TotalItemReturned, -1) <> a.Ret
       OR s.TotalQtyDelivered <> a.Qty OR ISNULL(s.TotalActualQty, -1) <> a.Act);

-- S10 (2026-10-17, script [104]) a posted AR payment whose Other Collections lines (PaymentType 'OTHER COLLECTION') are
--     not carried by its own GL ticket (Mnemonic OR-% + ReferenceKey = the reference): the ticket's credit on the line's
--     account must be at least the lines' total (the same account can also get a mapping leg, e.g. 404 overpay income),
--     and the line must have no invoice link (PONumber '#OTHER'). 0 rows before any Other Collections payment exists.
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'S10', NULL, h.ReferenceNo, l.Amt, ISNULL(k.Net, 0),
       'customer ' + h.CustomerKey + ', account ' + ISNULL(l.CreditGLCode, '(blank)') + ': Other Collections lines vs the payment ticket'
       + CASE WHEN l.Linked > 0 THEN ' (a line is linked to a PO)' ELSE '' END
FROM dbo.PaymentHeader h
INNER JOIN (SELECT PaymentHeaderID, CreditGLCode, SUM(Amount) AS Amt,
                   SUM(CASE WHEN ISNULL(PONumber, '') <> '#OTHER' THEN 1 ELSE 0 END) AS Linked
            FROM dbo.ARPaymentDetails
            WHERE PaymentType = 'OTHER COLLECTION' AND ISNULL(ErrorTag, 0) = 0
            GROUP BY PaymentHeaderID, CreditGLCode) l ON l.PaymentHeaderID = h.PaymentHeaderID
OUTER APPLY (SELECT SUM(td.Credit - td.Debit) AS Net
             FROM dbo.TicketMaster tm
             INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.ReferenceNumber = tm.ReferenceNumber
             WHERE tm.ReferenceNumber = h.ReferenceNo AND tm.ReferenceKey = h.ReferenceNo AND tm.Mnemonic LIKE 'OR-%'
               AND td.AccountCode = l.CreditGLCode) k
WHERE ISNULL(h.Status, '') <> 'REVERSED'
  AND (l.Linked > 0 OR ISNULL(k.Net, 0) < l.Amt - @Tol);

-- S11 (2026-10-18, script [110]) a CR recorded as cancelled (CancelledCollectionReceipt) is also on a live AR payment of
--     the same branch (customer's branch; same series + number, fn_rpt_DocNoSplit). spu_RecordCancelledCR refuses this
--     and Client Payments checks before posting, but the payment insert itself has no database guard (a trigger on
--     PaymentHeader would break the screens' OUTPUT clause), so an old exe / another writer can still do it. Skipped
--     until [110] is installed.
IF OBJECT_ID('dbo.CancelledCollectionReceipt', 'U') IS NOT NULL
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'S11', NULL, ph.ReferenceNo, 0, ph.TotalAmount,
       'CR ' + ph.CRNo + ' (branch ' + c.BranchCode + ', customer ' + ph.CustomerKey + ') was recorded as CANCELLED on '
       + CONVERT(CHAR(10), x.CRDate, 23) + ' (' + x.Reason + ', by ' + x.RecordedBy + ')'
FROM dbo.CancelledCollectionReceipt x
CROSS APPLY dbo.fn_rpt_DocNoSplit(x.CRNo) xs
INNER JOIN dbo.Customers c ON c.BranchCode = x.BranchCode
INNER JOIN dbo.PaymentHeader ph ON ph.CustomerKey = c.CustomerKey AND ISNULL(ph.Status, '') <> 'REVERSED'
CROSS APPLY dbo.fn_rpt_DocNoSplit(ph.CRNo) ps
WHERE CASE WHEN ps.SeqNo IS NULL THEN 'X:' + UPPER(ps.CleanNo) ELSE ps.Series + ':' + CAST(ps.SeqNo AS VARCHAR(20)) END
    = CASE WHEN xs.SeqNo IS NULL THEN 'X:' + UPPER(xs.CleanNo) ELSE xs.Series + ':' + CAST(xs.SeqNo AS VARCHAR(20)) END;

------------------------------------------------------------------
-- T. STS (transfers)
------------------------------------------------------------------
IF OBJECT_ID('tempdb..#ST') IS NOT NULL DROP TABLE #ST;
SELECT t.PONumber, ISNULL(t.isProcess, 0) AS isProcess,
       (SELECT TOP 1 d.Status FROM dbo.DeliverySummary d WHERE d.PONumber = t.PONumber ORDER BY d.DeliveryNo DESC) AS DevStatus
INTO #ST
FROM dbo.TransferOrderSummary t
WHERE t.EffectivityDate >= @StsFromDate
   OR EXISTS (SELECT 1 FROM dbo.TicketMaster tm WHERE tm.ReferenceKey = t.PONumber AND tm.TicketDate >= @StsFromDate
                AND (tm.Mnemonic LIKE 'IT-%' OR tm.Mnemonic LIKE 'ITR-%' OR tm.Mnemonic LIKE 'STS-%'));

IF OBJECT_ID('tempdb..#Tr') IS NOT NULL DROP TABLE #Tr;
SELECT s.PONumber, s.isProcess, s.DevStatus,
       (SELECT ISNULL(SUM(f.TotalCost), 0) FROM dbo.InventoryDeliveryFIFO f
        WHERE f.PONumber = s.PONumber AND f.isErrorCorrect = 0) AS LiveCost,
       (SELECT ISNULL(SUM(td.Debit - td.Credit), 0) FROM dbo.TicketMaster tm
        INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
        WHERE tm.ReferenceKey = s.PONumber AND tm.BranchCode = '888' AND td.AccountCode IN (@TransitVat, @TransitVatEx)
          AND (tm.Mnemonic LIKE 'IT-HO-%' OR tm.Mnemonic LIKE 'ITR-HO-%')) AS HOTransit,
       (SELECT ISNULL(SUM(td.Debit - td.Credit), 0) FROM dbo.TicketMaster tm
        INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
        WHERE tm.ReferenceKey = s.PONumber AND td.AccountCode IN (@TransitVat, @TransitVatEx)
          AND (tm.Mnemonic LIKE 'IT-%' OR tm.Mnemonic LIKE 'ITR-%' OR tm.Mnemonic LIKE 'STS-%')) AS AllTransit,
       (SELECT COUNT(DISTINCT tm.ReferenceNumber) FROM dbo.TicketMaster tm   -- one receipt = one reference (VAT + VATEX tickets share it)
        WHERE tm.ReferenceKey = s.PONumber AND tm.Mnemonic LIKE 'IT-BR-%') AS nReceipts
INTO #Tr
FROM #ST s;

-- T01 saved, not yet received: head office In Transit <> cost of the live lots
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'T01', PONumber, NULL, LiveCost, HOTransit, 'saved transfer: HO In Transit vs live FIFO cost (duplicate Save, missed return, cost change)'
FROM #Tr
WHERE isProcess = 1 AND ISNULL(DevStatus, '') <> 'DELIVERED' AND ABS(LiveCost - HOTransit) > @Tol;

-- T02 received: In Transit for the PO did not clear to 0 (all branches)
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'T02', PONumber, NULL, 0, AllTransit, 'received transfer: In Transit left over after receipt + short / over'
FROM #Tr
WHERE DevStatus = 'DELIVERED' AND ABS(AllTransit) > @Tol;

-- T03 received more than once
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'T03', PONumber, NULL, 1, nReceipts, 'more than one IT-BR receipt ticket for the transfer'
FROM #Tr
WHERE nReceipts > 1;

-- T04 received transfer with no receipt ticket, or a receipt ticket on a transfer not marked received
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'T04', PONumber, DevStatus, NULL, nReceipts,
       CASE WHEN DevStatus = 'DELIVERED' THEN 'marked received but no IT-BR receipt ticket' ELSE 'IT-BR receipt ticket but delivery not marked received' END
FROM #Tr
WHERE (DevStatus = 'DELIVERED' AND nReceipts = 0 AND LiveCost > 0) OR (ISNULL(DevStatus, '') <> 'DELIVERED' AND nReceipts > 0);

-- T05 a line taken from several lots was received as exactly one lot's qty
--     (the receive screen listed one row per lot and skipped the rest as duplicates; fixed 2026-10-02)
;WITH L AS (
    SELECT dd.PONumber, dd.SeqNo, dd.ProductNo, dd.BarcodeNo,
           SUM(f.QtyDelivered) AS ShipQty, SUM(f.TotalCost) AS ShipCost, COUNT(*) AS nLots
    FROM dbo.DeliveryDetails dd
    INNER JOIN dbo.InventoryDeliveryFIFO f ON f.DeliveryNo = dd.DeliveryNo AND f.PONumber = dd.PONumber AND f.DevDetSeqNo = dd.SeqNo AND f.isErrorCorrect = 0
    INNER JOIN #ST s ON s.PONumber = dd.PONumber
    WHERE dd.isCancelled = 0 AND dd.isReturned = 0
    GROUP BY dd.PONumber, dd.SeqNo, dd.ProductNo, dd.BarcodeNo
    HAVING COUNT(*) > 1)
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'T05', L.PONumber, 'line ' + CAST(L.SeqNo AS VARCHAR(10)) + ' ' + L.ProductNo, L.ShipQty, r.RcvQty,
       CAST(L.nLots AS VARCHAR(10)) + ' lots shipped, received qty = one lot''s qty; not booked: '
       + CAST(CAST(L.ShipQty - r.RcvQty AS DECIMAL(18,3)) AS VARCHAR(30)) + ' qty'
FROM L
CROSS APPLY (SELECT SUM(x.Qty) AS RcvQty FROM dbo.ReceivedOrderDetails x
             WHERE x.PONumber = L.PONumber AND x.ProductCode = L.ProductNo AND ISNULL(x.Barcode, '') = ISNULL(L.BarcodeNo, '')) r
WHERE r.RcvQty < L.ShipQty - 0.001
  -- receipts by the fixed proc (2026-10-02b) write 'STS RCVD ITEM' ledger rows; the buggy ones never did,
  -- so a genuine short that happens to equal one lot is not flagged
  AND NOT EXISTS (SELECT 1 FROM dbo.InventoryLedger lg WHERE lg.Remarks = 'STS RCVD ITEM PO#' + L.PONumber AND lg.Product = L.ProductNo)
  AND EXISTS (SELECT 1 FROM dbo.InventoryDeliveryFIFO f2
              WHERE f2.PONumber = L.PONumber AND f2.DevDetSeqNo = L.SeqNo AND f2.isErrorCorrect = 0
                AND ABS(f2.QtyDelivered - r.RcvQty) < 0.001);

-- T06 (2026-10-14, hardening H4 / script [85]) branch received rows on a transfer that is not DELIVERED: the receive
--     screen's three steps used to commit one by one (receive, return the unticked rows, confirm), so a failed confirm
--     left the branch stock received, the transfer FOR DELIVERY and In Transit not cleared. spu_STS_ReceiveTransfer does
--     the three in one transaction; a hit now means an old exe or a hand edit.
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'T06', r.PONumber, ISNULL(d.Status, '?'), NULL, r.TotalItem,
       'received rows (' + CONVERT(VARCHAR(10), r.DateReceived, 120) + ', ' + CAST(r.TotalItem AS VARCHAR(10)) + ' lines) on a transfer still ' + ISNULL(d.Status, '?') + ': the receipt was never confirmed'
FROM dbo.ReceiveOrderSummary r
INNER JOIN dbo.DeliverySummary d ON d.PONumber = r.PONumber
WHERE EXISTS (SELECT 1 FROM dbo.TransferOrderSummary t WHERE t.PONumber = r.PONumber)
  AND d.Status <> 'DELIVERED';

------------------------------------------------------------------
-- G. GL tickets of these modules
------------------------------------------------------------------
-- G01 unbalanced ticket
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'G01', MAX(ISNULL(NULLIF(tm.ReferenceKey, ''), tm.ReferenceNumber)), CAST(tm.TicketNumber AS VARCHAR(20)) + ' / ' + tm.BranchCode,
       SUM(td.Debit), SUM(td.Credit), MAX(tm.Mnemonic) + ' DR <> CR'
FROM dbo.TicketMaster tm
INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
WHERE tm.TicketDate >= @FromDate
  AND (tm.Mnemonic LIKE 'SI-%' OR tm.Mnemonic LIKE 'SO-%' OR tm.Mnemonic LIKE 'IT-%' OR tm.Mnemonic LIKE 'ITR-%' OR tm.Mnemonic LIKE 'STS-%')
GROUP BY tm.TicketNumber, tm.BranchCode
HAVING ABS(SUM(td.Debit) - SUM(td.Credit)) > 0.005;

-- G03 (2026-10-14, hardening H1 / script [83]) any ticket of any module that does not balance, per ticket number (its legs
--     may sit under several branches); the cross-branch expense (EXP-MANUAL-CROSS-BR) posts one ticket per branch and
--     balances per reference, so it is grouped by reference. All dates. The writers now refuse such a ticket (50022);
--     this keeps watching every other writer and hand-made rows.
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'G03', ISNULL(x.Ref, ''), x.Key1, 0, CAST(x.Diff AS DECIMAL(18,2)), ISNULL(x.Mnemonic, '?') + ' DR - CR = ' + FORMAT(x.Diff, 'N2')
FROM (
    SELECT CAST(td.TicketNumber AS VARCHAR(20)) AS Key1, MAX(tm.ReferenceNumber) AS Ref, MAX(tm.Mnemonic) AS Mnemonic, SUM(td.Debit) - SUM(td.Credit) AS Diff
    FROM dbo.TicketDetails td
    LEFT JOIN (SELECT TicketNumber, MAX(Mnemonic) AS Mnemonic, MAX(ReferenceNumber) AS ReferenceNumber FROM dbo.TicketMaster GROUP BY TicketNumber) tm ON tm.TicketNumber = td.TicketNumber
    WHERE ISNULL(tm.Mnemonic, '') <> 'EXP-MANUAL-CROSS-BR'
    GROUP BY td.TicketNumber
    HAVING ABS(SUM(td.Debit) - SUM(td.Credit)) > 0.005
    UNION ALL
    SELECT 'ref ' + tm.ReferenceNumber, tm.ReferenceNumber, 'EXP-MANUAL-CROSS-BR', SUM(td.Debit) - SUM(td.Credit)
    FROM dbo.TicketMaster tm
    INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
    WHERE tm.Mnemonic = 'EXP-MANUAL-CROSS-BR'
    GROUP BY tm.ReferenceNumber
    HAVING ABS(SUM(td.Debit) - SUM(td.Credit)) > 0.005
) x;

-- G04 (2026-10-14, hardening H2 / script [85]) an AR payment reversal that mirrored another document: a reversal ticket
--     with more than one master row (two documents under one reversal ticket number), or a 'REVERSAL ENTRY' ledger row
--     on a customer other than the payment's, or not OR-coded. All dates. sp_ReversePaymentClient mirrors only the
--     payment's own ticket since [85]; this keeps watching the history and hand-made rows.
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'G04', ph.ReferenceNo, 'ticket ' + CAST(x.TicketNumber AS VARCHAR(20)), 1, x.nMasters,
       'AR reversal ticket with ' + CAST(x.nMasters AS VARCHAR(10)) + ' master rows: another document under the payment''s reference was mirrored'
FROM (SELECT tm.TicketNumber, tm.ReferenceNumber, COUNT(*) AS nMasters
      FROM dbo.TicketMaster tm
      WHERE tm.Status = 'REVERSED' AND tm.Mnemonic IS NULL AND tm.Particulars LIKE 'REVERSAL: %'
      GROUP BY tm.TicketNumber, tm.ReferenceNumber
      HAVING COUNT(*) > 1) x
INNER JOIN dbo.PaymentHeader ph ON ph.ReferenceNo = x.ReferenceNumber AND ph.Status = 'REVERSED'
UNION ALL
SELECT 'G04', ph.ReferenceNo, 'customer ' + cl.AccountKey + ' / ' + cl.TransCode, NULL, cl.Debit - cl.Credit,
       'AR reversal ledger row ' + CASE WHEN cl.AccountKey <> ph.CustomerKey THEN 'on another customer (the payer is ' + ph.CustomerKey + ')' ELSE 'not OR-coded' END
FROM dbo.ClientLedger cl
INNER JOIN dbo.PaymentHeader ph ON ph.ReferenceNo = cl.ReferenceNumber AND ph.Status = 'REVERSED'
WHERE cl.Remarks = 'REVERSAL ENTRY'
  AND (cl.AccountKey <> ph.CustomerKey OR cl.TransCode NOT LIKE 'OR-%');

-- G05 (2026-10-15, script [96]) a reversed Single Expense or Manual JV that is not fully undone: its original + reversal
--     tickets don't net to 0 per branch / account, the expense still owes something or isn't CANCELLED, or a reversed JV
--     still has a live bank recon item. All dates. Skipped where [96] isn't installed (dynamic SQL: the log tables are new).
IF OBJECT_ID('dbo.ExpenseSingleReversal', 'U') IS NOT NULL AND OBJECT_ID('dbo.ManualJournalVoucherReversal', 'U') IS NOT NULL
    EXEC (N'
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT ''G05'', r.ReferenceNumber, ''expense '' + r.InvoiceNo + '' / '' + td.BranchCode + '' '' + td.AccountCode, 0, SUM(td.Debit) - SUM(td.Credit),
       ''reversed expense: original ticket '' + r.OriginalTicketNumber + '' + reversal '' + r.ReversalTicketNumber + '' do not net to 0 on this account''
FROM dbo.ExpenseSingleReversal r
INNER JOIN dbo.TicketDetails td ON td.TicketNumber IN (r.OriginalTicketNumber, r.ReversalTicketNumber)
                               AND td.ReferenceNumber = r.ReferenceNumber AND td.ReferenceKey = r.InvoiceNo
GROUP BY r.ReferenceNumber, r.InvoiceNo, r.OriginalTicketNumber, r.ReversalTicketNumber, td.BranchCode, td.AccountCode
HAVING ABS(SUM(td.Debit) - SUM(td.Credit)) > 0.005
UNION ALL
SELECT ''G05'', r.ReferenceNumber, ''expense '' + r.InvoiceNo, 0, ISNULL(es.Balance, 0),
       ''reversed expense still '' + ISNULL(es.Status, ''(missing)'') + '' with balance '' + FORMAT(ISNULL(es.Balance, 0), ''N2'')
FROM dbo.ExpenseSingleReversal r
LEFT JOIN dbo.ExpenseSummary es ON es.ReferenceNumber = r.ReferenceNumber AND es.InvoiceNo = r.InvoiceNo AND es.SupplierID = r.SupplierID
WHERE es.ReferenceNumber IS NULL OR ISNULL(es.Status, '''') <> ''CANCELLED'' OR ABS(ISNULL(es.Balance, 0)) > 0.005
UNION ALL
SELECT ''G05'', r.ReferenceNo, ''JV '' + td.BranchCode + '' '' + td.AccountCode, 0, SUM(td.Debit) - SUM(td.Credit),
       ''reversed journal voucher: original + reversal ticket '' + r.ReversalTicketNumber + '' do not net to 0 on this account''
FROM dbo.ManualJournalVoucherReversal r
INNER JOIN dbo.TicketDetails td ON td.ReferenceNumber = r.ReferenceNo
       AND (td.TicketNumber = r.ReversalTicketNumber OR td.TicketNumber IN (SELECT v.TicketNumber FROM dbo.ManualJournalVoucher v WHERE v.ReferenceNo = r.ReferenceNo))
GROUP BY r.ReferenceNo, r.ReversalTicketNumber, td.BranchCode, td.AccountCode
HAVING ABS(SUM(td.Debit) - SUM(td.Credit)) > 0.005
UNION ALL
SELECT ''G05'', r.ReferenceNo, ''recon item '' + CAST(b.ReconID AS VARCHAR(20)), 0, b.Amount,
       ''reversed journal voucher still has a live '' + b.ItemType + '' item on '' + b.AccountCode
FROM dbo.ManualJournalVoucherReversal r
INNER JOIN dbo.BankStatementRecon b ON b.ReferenceNo = r.ReferenceNo AND b.SourceModule = ''MANUAL-JV'' AND b.SourceRef = r.ReferenceNo
WHERE ISNULL(b.ResolvedReason, '''') <> ''REVERSED'' AND ISNULL(b.ResolvedReason, '''') NOT LIKE ''VOIDED%'';');

-- G02 VAT posting after the all-VAT-exempt rule
INSERT #X (CheckCode, PONumber, Ref, Expected, Actual, Detail)
SELECT 'G02', ISNULL(NULLIF(tm.ReferenceKey, ''), tm.ReferenceNumber), CAST(tm.TicketNumber AS VARCHAR(20)) + ' / ' + tm.BranchCode,
       0, NULL, tm.Mnemonic + ' dated ' + CONVERT(VARCHAR(10), tm.TicketDate, 120) + ': the GL must be all VAT-exempt'
FROM dbo.TicketMaster tm
WHERE tm.TicketDate >= @VatRuleDate
  AND tm.Mnemonic IN ('SI-VAT', 'SO-CM-VAT', 'SO-RET-VAT', 'SO-SHRINK-VAT', 'IT-HO-VAT', 'ITR-HO-VAT', 'IT-BR-VAT',
                      'STS-SHORT-VAT', 'STS-OVER-VAT', 'CM-CLIENT-VAT');

------------------------------------------------------------------
-- Output
------------------------------------------------------------------
DECLARE @Info TABLE (CheckCode VARCHAR(5), Area VARCHAR(12), Severity VARCHAR(8), Meaning VARCHAR(300), Action VARCHAR(300));
INSERT @Info VALUES
('X01', 'Stock', 'CRITICAL', 'A cancelled or returned line still holds stock taken from a lot: the stock never went back to the source branch.', 'Restore the lots (cancel/return proc) before anything else posts on that PO.'),
('X02', 'Stock', 'CRITICAL', 'Qty put back by a cancel or return differs from what was taken / billed.', 'Compare the line''s FIFO rows with the stock-ledger rows for that PO.'),
('X03', 'Stock', 'CRITICAL', 'A lot shows Available below 0 or above its Quantity.', 'Trace the lot''s stock ledger; usually a double restore or a missed deduction.'),
('X04', 'Stock', 'INFO',     'A sold / shipped lot''s cost changed after the sale (cost finalized later).', 'Decide: re-cost the sale (like 2026-10-01d) or leave for a manual month-end entry.'),
('X05', 'Stock', 'CRITICAL', 'A partly returned line''s live lot qty differs from its delivered qty (the split went wrong).', 'Compare the line and its split-off twin (SalesReturnLog) with their InventoryDeliveryFIFO rows.'),
('S01', 'Sales',  'CRITICAL', 'Confirmed order without exactly one invoice, or without a sales ticket.', 'Check sp_ConfirmOrder ran fully for that PO.'),
('S02', 'Sales',  'HIGH',     'Invoice Balance does not follow its own columns.', 'The next payment will compute a wrong balance; fix AmountPaid / Balance first.'),
('S03', 'Sales',  'HIGH',     'AR in the GL for the order (sale - credit memo - return) differs from the invoice.', 'Look for a missing / duplicate SI, SO-CM or SO-RET ticket.'),
('S04', 'Sales',  'HIGH',     'Cost of sales on the sales ticket differs from the invoice COGS rows.', 'Check the line cost at Save and any later re-costing.'),
('S05', 'Sales',  'MEDIUM',   'Order and delivery header disagree on DELIVERED.', 'Check whether confirm or a manual edit stopped half-way.'),
('S06', 'Sales',  'HIGH',     'Invoice no. with several rows: a row''s paid amount differs from its own payment lines.', 'A payment / reversal moved another row of the same invoice no.; correct the row (see script [80]) and check the screen showed the real invoice.'),
('S07', 'Sales',  'HIGH',     'A customer''s account balance differs from the sum of its invoice balances.', 'Find the invoice row edited by hand or the payment posted outside sp_AddPaymentClient ([87] refuses a hand-set balance, 92016); correct the row and let the ledger trigger recompute the account.'),
('S08', 'Sales',  'HIGH',     'An invoice row''s Balance does not follow its own columns (all rows, all dates).', 'Correct the row (AmountPaid / EWT / Discount / Offset / Balance) from its payment lines; until then sp_AddPaymentClient refuses a payment on it (92016, since [87]).'),
('S09', 'Sales',  'MEDIUM',   'A sales-order delivery''s counters (items / sold / returned / qty / actual qty) differ from its lines.', 'Since [89] the triggers keep them in step: check trg_DeliveryDetails_SOTotals / trg_DeliverySummary_SOTotals are enabled; a one-row UPDATE of any counter on the delivery puts it back.'),
('S10', 'Sales',  'HIGH',     'An AR payment''s Other Collections lines are not carried by its GL ticket, or a line is linked to an invoice ([104]).', 'Compare the payment''s ARPaymentDetails OTHER COLLECTION lines with its OR ticket; since [104] sp_AddPaymentClient refuses this (92022 / 92024), so a row here came from a hand edit or another writer: reverse the payment and post it again.'),
('S11', 'Sales',  'HIGH',     'A CR recorded as cancelled ([110]) is also on a live AR payment of the same branch.', 'Check the paper receipt: if the CR was really used, correct the cancelled record (Client Payments › Cancelled CR… › Edit); if it was really spoiled, reverse the payment and post it again with its real CR no.'),
('T01', 'STS',    'CRITICAL', 'Saved transfer: head-office In Transit differs from the cost of the stock actually shipped.', 'Run spu_STS_SyncInTransit for the PO after fixing the cause (duplicate Save, missed return).'),
('T02', 'STS',    'CRITICAL', 'Received transfer: In Transit did not clear to 0.', 'Look for a missing receipt, short/over ticket or a receipt on the wrong PO.'),
('T03', 'STS',    'CRITICAL', 'Transfer received more than once (two IT-BR tickets).', 'Reverse the duplicate receipt and its branch stock.'),
('T04', 'STS',    'HIGH',     'Received status and receipt ticket disagree.', 'Check the receive screen''s three calls finished (they are not atomic).'),
('T05', 'STS',    'CRITICAL', 'A multi-lot line was received as exactly one lot''s qty (the rest skipped as duplicates).', 'Complete the receipt for the remaining qty (branch stock, IT-BR); the 2026-10-02 fix stops new cases.'),
('T06', 'STS',    'HIGH',     'Branch received rows on a transfer that is not DELIVERED: the receipt was never confirmed (no IT-BR ticket, In Transit not cleared).', 'Confirm the receipt (sp_ConfirmBranchRecievedOrderJFC) or undo the received rows; since [85] the receive screen posts the three steps in one transaction.'),
('G01', 'GL',     'CRITICAL', 'A Sales / STS ticket does not balance (DR <> CR).', 'Check the mnemonic''s mapping rows.'),
('G02', 'GL',     'HIGH',     'A VAT ticket was posted after the all-VAT-exempt rule.', 'Something is still on an old procedure version or a manual entry.'),
('G03', 'GL',     'CRITICAL', 'A GL ticket of any module does not balance (DR <> CR), all dates.', 'The compound writers refuse this since [83]; find the writer or the hand edit behind the ticket and correct it with a balancing entry.'),
('G04', 'GL',     'CRITICAL', 'An AR payment reversal mirrored another document under the same reference (a second master on the reversal ticket, or a reversal ledger row on another customer).', 'Reverse the extra ticket lines / ledger row with a correcting entry; sp_ReversePaymentClient mirrors only the payment''s own ticket since [85].'),
('G05', 'GL',     'CRITICAL', 'A reversed Single Expense / Manual JV ([96]) is not fully undone: original + reversal don''t net to 0 on an account, the expense still owes or isn''t CANCELLED, or the JV keeps a live bank recon item.', 'Compare the two tickets line by line and the expense / recon rows with spu_ReverseSingleExpense / spu_ReverseManualJournalVoucher; correct with a balancing entry, never by deleting the reversal.');

SELECT i.CheckCode, i.Area, i.Severity, COUNT(x.CheckCode) AS Found, i.Meaning, i.Action
FROM @Info i
LEFT JOIN #X x ON x.CheckCode = i.CheckCode
GROUP BY i.CheckCode, i.Area, i.Severity, i.Meaning, i.Action
ORDER BY CASE i.Severity WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END, i.CheckCode;

SELECT x.CheckCode, i.Severity, x.PONumber, x.Ref, x.Expected, x.Actual,
       CAST(ISNULL(x.Actual, 0) - ISNULL(x.Expected, 0) AS DECIMAL(18,2)) AS Difference, x.Detail
FROM #X x
INNER JOIN @Info i ON i.CheckCode = x.CheckCode
ORDER BY CASE i.Severity WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END, x.CheckCode, x.PONumber;
