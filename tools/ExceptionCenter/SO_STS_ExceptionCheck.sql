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
WHERE CASE WHEN s.Status = 'DELIVERED' THEN 1 ELSE 0 END <> CASE WHEN d.Status IN ('DELIVERED', 'RETURNED') THEN 1 ELSE 0 END;   -- a fully returned order keeps PO DELIVERED

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
('S01', 'Sales',  'CRITICAL', 'Confirmed order without exactly one invoice, or without a sales ticket.', 'Check sp_ConfirmOrder ran fully for that PO.'),
('S02', 'Sales',  'HIGH',     'Invoice Balance does not follow its own columns.', 'The next payment will compute a wrong balance; fix AmountPaid / Balance first.'),
('S03', 'Sales',  'HIGH',     'AR in the GL for the order (sale - credit memo - return) differs from the invoice.', 'Look for a missing / duplicate SI, SO-CM or SO-RET ticket.'),
('S04', 'Sales',  'HIGH',     'Cost of sales on the sales ticket differs from the invoice COGS rows.', 'Check the line cost at Save and any later re-costing.'),
('S05', 'Sales',  'MEDIUM',   'Order and delivery header disagree on DELIVERED.', 'Check whether confirm or a manual edit stopped half-way.'),
('T01', 'STS',    'CRITICAL', 'Saved transfer: head-office In Transit differs from the cost of the stock actually shipped.', 'Run spu_STS_SyncInTransit for the PO after fixing the cause (duplicate Save, missed return).'),
('T02', 'STS',    'CRITICAL', 'Received transfer: In Transit did not clear to 0.', 'Look for a missing receipt, short/over ticket or a receipt on the wrong PO.'),
('T03', 'STS',    'CRITICAL', 'Transfer received more than once (two IT-BR tickets).', 'Reverse the duplicate receipt and its branch stock.'),
('T04', 'STS',    'HIGH',     'Received status and receipt ticket disagree.', 'Check the receive screen''s three calls finished (they are not atomic).'),
('T05', 'STS',    'CRITICAL', 'A multi-lot line was received as exactly one lot''s qty (the rest skipped as duplicates).', 'Complete the receipt for the remaining qty (branch stock, IT-BR); the 2026-10-02 fix stops new cases.'),
('G01', 'GL',     'CRITICAL', 'A Sales / STS ticket does not balance (DR <> CR).', 'Check the mnemonic''s mapping rows.'),
('G02', 'GL',     'HIGH',     'A VAT ticket was posted after the all-VAT-exempt rule.', 'Something is still on an old procedure version or a manual entry.');

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
