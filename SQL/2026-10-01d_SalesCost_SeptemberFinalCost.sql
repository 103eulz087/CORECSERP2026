/* ================================================================
   2026-10-01d: September sales orders -> re-cost at the finalized lot cost
   ================================================================
   One-off data fix for STAGING (CORECSJFC2026_STAGING).

   The September sales were caught up before the lot costs were final.
   Inventory.Cost is now final, so every sales-order FIFO row whose Cost
   differs from its lot's Cost is re-costed, together with every copy
   of that cost:
     1. InventoryDeliveryFIFO   Cost, TotalCost (= QtyDelivered * Cost)
     2. DeliveryDetails         Cost (weighted live-lot cost of the line;
                                only lines already saved, Cost <> 0)
     3. InventoryLedger         Cost on the sale's stock-out row
                                (Remarks 'STS IN-TRANSIT PO#-<po>', same lot)
     4. BatchSalesDetails       Cost                    } confirmed
     5. TransactionChargeSalesDetails COGS-* rows       } orders
     6. TicketDetails           the SI-VAT / SI-VATEX ticket's COST legs
                                (DR 501/502, CR 101040201/202 from JEM),
                                changed by new - old ROUND(QtySold * Cost, 2)
   Not touched: AR, invoice amounts, ClientLedger, payments (cost only),
   cancelled FIFO rows (isErrorCorrect = 1), August orders (manual ticket),
   STS transfers.

   Scope: PurchaseOrderSummary.EffectivityDate in [@DateFrom, @DateTo).
   Backups: CostFix_20261001_<table> (the rows before the change).
   Stops (THROW, nothing changed) when a confirmed line can't be matched
   one-to-one, or a ticket's COST legs don't equal its COGS rows.
   Re-runnable: once costs agree, nothing is in scope.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @DateFrom DATE = '2026-09-01',
        @DateTo   DATE = '2026-10-01';   -- exclusive

------------------------------------------------------------------
-- 1. Scope: live FIFO rows of sales orders whose cost differs
------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Fifo') IS NOT NULL DROP TABLE #Fifo;
SELECT a.DeliveryNo, a.PONumber, a.DevDetSeqNo, a.ProductNo, a.SequenceReferenceNumber AS LotSeq,
       a.QtyDelivered, CAST(a.Cost AS DECIMAL(18,4)) AS OldCost, CAST(b.Cost AS DECIMAL(18,4)) AS NewCost
INTO #Fifo
FROM dbo.InventoryDeliveryFIFO AS a
INNER JOIN dbo.Inventory AS b
    ON b.SequenceNumber = a.SequenceReferenceNumber
INNER JOIN dbo.PurchaseOrderSummary AS c
    ON c.PONumber = a.PONumber
WHERE a.isErrorCorrect = 0
  AND c.EffectivityDate >= @DateFrom
  AND c.EffectivityDate <  @DateTo
  AND a.Cost <> b.Cost;

SELECT 'fifo rows to re-cost' AS step, PONumber, DeliveryNo, DevDetSeqNo, ProductNo, LotSeq, QtyDelivered,
       OldCost, NewCost, CAST(QtyDelivered * (NewCost - OldCost) AS DECIMAL(18,2)) AS CostChange
FROM #Fifo ORDER BY PONumber, DevDetSeqNo;

IF NOT EXISTS (SELECT 1 FROM #Fifo)
BEGIN
    PRINT 'Nothing to correct.';
    RETURN;
END

------------------------------------------------------------------
-- 2. Lines touched, and their cost after the fix
--    (weighted over the line's live lots, with the new lot costs)
------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Line') IS NOT NULL DROP TABLE #Line;
SELECT dd.DeliveryNo, dd.PONumber, dd.SeqNo, dd.ProductNo, dd.Cost AS OldLineCost,
       CAST(ROUND(SUM(f.QtyDelivered * ISNULL(fx.NewCost, f.Cost)) / NULLIF(SUM(f.QtyDelivered), 0), 4) AS DECIMAL(18,4)) AS NewLineCost
INTO #Line
FROM dbo.DeliveryDetails AS dd
INNER JOIN dbo.InventoryDeliveryFIFO AS f
    ON f.DeliveryNo = dd.DeliveryNo AND f.PONumber = dd.PONumber AND f.DevDetSeqNo = dd.SeqNo AND f.isErrorCorrect = 0
LEFT JOIN #Fifo AS fx
    ON fx.DeliveryNo = f.DeliveryNo AND fx.PONumber = f.PONumber AND fx.DevDetSeqNo = f.DevDetSeqNo AND fx.LotSeq = f.SequenceReferenceNumber
WHERE EXISTS (SELECT 1 FROM #Fifo x WHERE x.DeliveryNo = dd.DeliveryNo AND x.PONumber = dd.PONumber AND x.DevDetSeqNo = dd.SeqNo)
  AND dd.isCancelled = 0
GROUP BY dd.DeliveryNo, dd.PONumber, dd.SeqNo, dd.ProductNo, dd.Cost;

------------------------------------------------------------------
-- 3. Confirmed orders: the sales line, its COGS row and its ticket
------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Sale') IS NOT NULL DROP TABLE #Sale;
SELECT l.PONumber, bsd.BranchCode, l.ProductNo, ISNULL(bsd.isVat, 0) AS isVat, bsd.QtySold,
       CAST(bsd.Cost AS DECIMAL(18,4)) AS OldCost, l.NewLineCost AS NewCost,
       CAST(ROUND(bsd.QtySold * bsd.Cost, 2) AS DECIMAL(18,2))          AS OldCogs,
       CAST(ROUND(bsd.QtySold * l.NewLineCost, 2) AS DECIMAL(18,2))     AS NewCogs,
       (SELECT COUNT(*) FROM dbo.BatchSalesDetails b2
         WHERE b2.ReferenceNo = l.PONumber AND b2.BranchCode = bsd.BranchCode AND b2.ProductCode = l.ProductNo) AS nBsd,
       (SELECT COUNT(*) FROM #Line l2 WHERE l2.PONumber = l.PONumber AND l2.ProductNo = l.ProductNo) AS nLine
INTO #Sale
FROM #Line AS l
INNER JOIN dbo.BatchSalesDetails AS bsd
    ON bsd.ReferenceNo = l.PONumber AND bsd.ProductCode = l.ProductNo
INNER JOIN dbo.PurchaseOrderSummary AS c
    ON c.PONumber = l.PONumber AND c.Status = 'DELIVERED';

IF EXISTS (SELECT 1 FROM #Sale WHERE nBsd <> 1 OR nLine <> 1)
BEGIN
    SELECT 'NOT one-to-one' AS problem, * FROM #Sale WHERE nBsd <> 1 OR nLine <> 1;
    THROW 59701, 'A confirmed order has the same product on more than one line; correct it by hand.', 1;
END

-- ticket per order and VAT class, with the accounts of its COST legs
IF OBJECT_ID('tempdb..#Tk') IS NOT NULL DROP TABLE #Tk;
SELECT s.PONumber, s.BranchCode, s.isVat,
       CASE s.isVat WHEN 1 THEN 'SI-VAT' ELSE 'SI-VATEX' END AS Mnemonic,
       SUM(s.NewCogs - s.OldCogs) AS Delta,
       CAST(NULL AS INT)         AS TicketNumber,
       CAST(NULL AS INT)         AS nTickets,
       CAST(NULL AS VARCHAR(50)) AS AcctDr,
       CAST(NULL AS VARCHAR(50)) AS AcctCr
INTO #Tk
FROM #Sale AS s
GROUP BY s.PONumber, s.BranchCode, s.isVat;

UPDATE t SET
    t.nTickets     = (SELECT COUNT(*) FROM dbo.TicketMaster tm
                      WHERE tm.ReferenceNumber = t.PONumber AND tm.BranchCode = t.BranchCode
                        AND tm.Mnemonic = t.Mnemonic AND tm.Status = 'POSTED'),
    t.TicketNumber = (SELECT MAX(tm.TicketNumber) FROM dbo.TicketMaster tm
                      WHERE tm.ReferenceNumber = t.PONumber AND tm.BranchCode = t.BranchCode
                        AND tm.Mnemonic = t.Mnemonic AND tm.Status = 'POSTED'),
    t.AcctDr       = (SELECT TOP 1 j.AccountCode FROM dbo.JournalEntryMapping j
                      WHERE j.Mnemonic = t.Mnemonic AND j.AmountType = 'COST' AND j.DebitCredit = 'D' AND j.IsActive = 1 ORDER BY j.Seq),
    t.AcctCr       = (SELECT TOP 1 j.AccountCode FROM dbo.JournalEntryMapping j
                      WHERE j.Mnemonic = t.Mnemonic AND j.AmountType = 'COST' AND j.DebitCredit = 'C' AND j.IsActive = 1 ORDER BY j.Seq)
FROM #Tk AS t;

IF EXISTS (SELECT 1 FROM #Tk WHERE nTickets <> 1 OR AcctDr IS NULL OR AcctCr IS NULL)
BEGIN
    SELECT 'ticket not found once' AS problem, * FROM #Tk WHERE nTickets <> 1 OR AcctDr IS NULL OR AcctCr IS NULL;
    THROW 59702, 'A confirmed order has no single POSTED sales ticket (or its COST accounts are not mapped).', 1;
END

-- each ticket's COST legs must equal the COGS rows of its order before the change
IF OBJECT_ID('tempdb..#TkCheck') IS NOT NULL DROP TABLE #TkCheck;
SELECT t.PONumber, t.TicketNumber, t.Mnemonic, t.Delta,
       (SELECT SUM(td.Debit)  FROM dbo.TicketDetails td WHERE td.TicketNumber = t.TicketNumber AND td.BranchCode = t.BranchCode AND td.AccountCode = t.AcctDr) AS LegDr,
       (SELECT SUM(td.Credit) FROM dbo.TicketDetails td WHERE td.TicketNumber = t.TicketNumber AND td.BranchCode = t.BranchCode AND td.AccountCode = t.AcctCr) AS LegCr,
       (SELECT COUNT(*)       FROM dbo.TicketDetails td WHERE td.TicketNumber = t.TicketNumber AND td.BranchCode = t.BranchCode AND td.AccountCode IN (t.AcctDr, t.AcctCr)) AS nLegs,
       (SELECT SUM(x.TotalAmount) FROM dbo.TransactionChargeSalesDetails x
         WHERE x.ReferenceNo = t.PONumber AND x.BranchCode = t.BranchCode AND x.ErrorTag = 0
           AND x.TransCode = CASE t.isVat WHEN 1 THEN 'COGS-VAT' ELSE 'COGS-VATEX' END) AS CogsRows
INTO #TkCheck
FROM #Tk AS t;

SELECT 'tickets to adjust' AS step, * FROM #TkCheck ORDER BY PONumber;

IF EXISTS (SELECT 1 FROM #TkCheck WHERE nLegs <> 2 OR LegDr <> LegCr OR LegDr <> ISNULL(CogsRows, -1))
BEGIN
    SELECT 'ticket does not match its COGS rows' AS problem, * FROM #TkCheck
    WHERE nLegs <> 2 OR LegDr <> LegCr OR LegDr <> ISNULL(CogsRows, -1);
    THROW 59703, 'A sales ticket''s COST legs differ from its COGS rows; check it before re-costing.', 1;
END

------------------------------------------------------------------
-- 4. Apply
------------------------------------------------------------------
BEGIN TRANSACTION;

    IF OBJECT_ID('dbo.CostFix_20261001_FIFO') IS NOT NULL
        THROW 59704, 'Backup tables CostFix_20261001_* already exist; rename them before running again.', 1;

    SELECT f.* INTO dbo.CostFix_20261001_FIFO
    FROM dbo.InventoryDeliveryFIFO f
    WHERE EXISTS (SELECT 1 FROM #Fifo x WHERE x.DeliveryNo = f.DeliveryNo AND x.PONumber = f.PONumber
                    AND x.DevDetSeqNo = f.DevDetSeqNo AND x.LotSeq = f.SequenceReferenceNumber) AND f.isErrorCorrect = 0;
    SELECT dd.* INTO dbo.CostFix_20261001_DeliveryDetails
    FROM dbo.DeliveryDetails dd
    WHERE EXISTS (SELECT 1 FROM #Line l WHERE l.DeliveryNo = dd.DeliveryNo AND l.PONumber = dd.PONumber AND l.SeqNo = dd.SeqNo);
    SELECT il.* INTO dbo.CostFix_20261001_InventoryLedger
    FROM dbo.InventoryLedger il
    WHERE il.QtyOut > 0
      AND EXISTS (SELECT 1 FROM #Fifo x WHERE x.LotSeq = il.SequenceRefNum AND il.Remarks = 'STS IN-TRANSIT PO#-' + x.PONumber);
    SELECT b.* INTO dbo.CostFix_20261001_BatchSalesDetails
    FROM dbo.BatchSalesDetails b
    WHERE EXISTS (SELECT 1 FROM #Sale s WHERE s.PONumber = b.ReferenceNo AND s.BranchCode = b.BranchCode AND s.ProductNo = b.ProductCode);
    SELECT x.* INTO dbo.CostFix_20261001_TCSD
    FROM dbo.TransactionChargeSalesDetails x
    WHERE x.TransCode IN ('COGS-VAT', 'COGS-VATEX')
      AND EXISTS (SELECT 1 FROM #Sale s WHERE s.PONumber = x.ReferenceNo AND s.BranchCode = x.BranchCode AND s.ProductNo = x.Product);
    SELECT td.* INTO dbo.CostFix_20261001_TicketDetails
    FROM dbo.TicketDetails td
    WHERE EXISTS (SELECT 1 FROM #Tk t WHERE t.TicketNumber = td.TicketNumber AND t.BranchCode = td.BranchCode);

    -- 1. FIFO rows
    UPDATE f SET
        f.Cost      = x.NewCost,
        f.TotalCost = f.QtyDelivered * x.NewCost
    FROM dbo.InventoryDeliveryFIFO f
    INNER JOIN #Fifo x
        ON x.DeliveryNo = f.DeliveryNo AND x.PONumber = f.PONumber AND x.DevDetSeqNo = f.DevDetSeqNo AND x.LotSeq = f.SequenceReferenceNumber
    WHERE f.isErrorCorrect = 0;

    -- 2. delivery lines already saved (unsaved lines get their cost at Save)
    UPDATE dd SET dd.Cost = l.NewLineCost
    FROM dbo.DeliveryDetails dd
    INNER JOIN #Line l ON l.DeliveryNo = dd.DeliveryNo AND l.PONumber = dd.PONumber AND l.SeqNo = dd.SeqNo
    WHERE ISNULL(dd.Cost, 0) <> 0;

    -- 3. stock-out rows of the sale
    UPDATE il SET il.Cost = x.NewCost
    FROM dbo.InventoryLedger il
    INNER JOIN #Fifo x ON x.LotSeq = il.SequenceRefNum AND il.Remarks = 'STS IN-TRANSIT PO#-' + x.PONumber
    WHERE il.QtyOut > 0;

    -- 4. sales lines
    UPDATE b SET b.Cost = s.NewCost
    FROM dbo.BatchSalesDetails b
    INNER JOIN #Sale s ON s.PONumber = b.ReferenceNo AND s.BranchCode = b.BranchCode AND s.ProductNo = b.ProductCode;

    -- 5. COGS rows
    UPDATE x SET x.Cost = s.NewCost, x.TotalAmount = s.NewCogs
    FROM dbo.TransactionChargeSalesDetails x
    INNER JOIN #Sale s ON s.PONumber = x.ReferenceNo AND s.BranchCode = x.BranchCode AND s.ProductNo = x.Product
    WHERE x.TransCode = CASE s.isVat WHEN 1 THEN 'COGS-VAT' ELSE 'COGS-VATEX' END;

    -- 6. ticket COST legs
    UPDATE td SET td.Debit = td.Debit + t.Delta
    FROM dbo.TicketDetails td
    INNER JOIN #Tk t ON t.TicketNumber = td.TicketNumber AND t.BranchCode = td.BranchCode AND td.AccountCode = t.AcctDr
    WHERE t.Delta <> 0;

    UPDATE td SET td.Credit = td.Credit + t.Delta
    FROM dbo.TicketDetails td
    INNER JOIN #Tk t ON t.TicketNumber = td.TicketNumber AND t.BranchCode = td.BranchCode AND td.AccountCode = t.AcctCr
    WHERE t.Delta <> 0;

    -- every adjusted ticket still balances and still equals its COGS rows
    IF EXISTS (
        SELECT 1 FROM #Tk t
        CROSS APPLY (SELECT SUM(td.Debit) AS Dr, SUM(td.Credit) AS Cr FROM dbo.TicketDetails td
                     WHERE td.TicketNumber = t.TicketNumber AND td.BranchCode = t.BranchCode) bal
        WHERE ABS(bal.Dr - bal.Cr) > 0.001)
        THROW 59705, 'An adjusted ticket is out of balance.', 1;

    IF EXISTS (
        SELECT 1 FROM #Tk t
        WHERE (SELECT SUM(td.Debit) FROM dbo.TicketDetails td WHERE td.TicketNumber = t.TicketNumber AND td.BranchCode = t.BranchCode AND td.AccountCode = t.AcctDr)
           <> (SELECT SUM(x.TotalAmount) FROM dbo.TransactionChargeSalesDetails x
                WHERE x.ReferenceNo = t.PONumber AND x.BranchCode = t.BranchCode AND x.ErrorTag = 0
                  AND x.TransCode = CASE t.isVat WHEN 1 THEN 'COGS-VAT' ELSE 'COGS-VATEX' END))
        THROW 59706, 'An adjusted ticket no longer equals its COGS rows.', 1;

COMMIT TRANSACTION;

------------------------------------------------------------------
-- 5. Result
------------------------------------------------------------------
SELECT 'tickets adjusted' AS step, t.PONumber, t.TicketNumber, t.Mnemonic, t.AcctDr, t.AcctCr, t.Delta AS CostChange
FROM #Tk t ORDER BY t.PONumber;

SELECT 'total' AS step, CAST(SUM(Delta) AS DECIMAL(18,2)) AS CostChangeOnTickets,
       (SELECT CAST(SUM(QtyDelivered * (NewCost - OldCost)) AS DECIMAL(18,2)) FROM #Fifo) AS CostChangeOnFifo
FROM #Tk;

-- must be empty: September sales-order FIFO rows still off their lot cost
SELECT 'still different (must be empty)' AS step, a.PONumber, a.ProductNo, a.Cost, b.Cost AS LotCost
FROM dbo.InventoryDeliveryFIFO a
INNER JOIN dbo.Inventory b ON b.SequenceNumber = a.SequenceReferenceNumber
INNER JOIN dbo.PurchaseOrderSummary c ON c.PONumber = a.PONumber
WHERE a.isErrorCorrect = 0 AND c.EffectivityDate >= @DateFrom AND c.EffectivityDate < @DateTo AND a.Cost <> b.Cost;
