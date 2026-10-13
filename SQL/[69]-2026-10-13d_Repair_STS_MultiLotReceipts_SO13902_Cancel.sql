/* ================================================================
   [69] 2026-10-13d - Repair: 3 STS receipts that booked one lot of a multi-lot line (T05 / T02),
                      and SO 13902's cancelled line whose stock never went back (X01). Data only.
   ================================================================
   Exception Center findings (STAGING since 10-01, PRODUCTION 10-13), all from before the fixes:

   A. STS receipts on the old receive screen (one row per lot; only the first lot was received,
      the rest skipped as "duplicate PONumber + Barcode"; fixed by [25] / [26] / [34]):
        PO 11911 line 1 13025 (branch 012): shipped 2,034.310 kg from 124 lots, received 4.750
        PO 11913 line 2 13025 (branch 012): shipped 1,002.600 kg from  58 lots, received 11.100
        PO 14100 line 1 13025 (branch 005): shipped 2,506.800 kg from 146 lots, received 19.800
      The rest of each line is still in head-office In Transit and missing from branch stock.
      Repair = what spu_PostSTSReceiveFromFIFO + sp_ConfirmBranchRecievedOrderJFC would have written for
      the rest of the line, per batch (ShipmentNo + ReferenceCode + cost) of the lots not yet received:
        * branch Inventory row (receiving branch, batch ShipmentNo / ReferenceCode / cost, line barcode,
          DateReceived = the original receipt date),
        * ReceivedOrderDetails row, InventoryLedger row 'STS RCVD ITEM PO#<po>' (ProcessedBy 'REPAIR [69]'),
        * DeliveryDetails ActualQty = QtyDelivered / Variance 0; DeliverySummary and ReceiveOrderSummary totals,
        * GL, under the ORIGINAL receipt reference and date (so the PO keeps one receipt, T03):
            IT-BR-VATEX on the receiving branch: DR branch inventory / CR In Transit, at qty x batch cost;
            the few cents the old receipt left (it valued its lot at the line's 2-dp cost) go to
            STS-SHORT-VATEX / STS-OVER-VATEX on 888, as the confirm proc does.
        * PO 14100 only: its 10-01 receipt (a day before the all-VAT-exempt rule) credited VAT In Transit
          101040101 with 34,434.00 for the TVP line, while head office shipped it through VAT-exempt
          In Transit 101040102. The receipt ticket also moves that between the two In Transit accounts,
          so both end at 0 (not just their sum).
      Accounts come from JournalEntryMapping (IT-BR-VATEX, STS-SHORT/OVER-VATEX; VAT / VAT-exempt
      In Transit = the IT-HO-VAT / IT-HO-VATEX debit accounts).

   B. SO 13902 line 2 (14016, 1,500 kg), cancelled 10-01 18:06 on the old cancel proc (before [19]):
      only lot 30784 (660 kg) was restored; lot 30778 (840 kg, FIFO row 23561) was not. GL is right
      (the sale ticket costs only live lines). Repair = what sp_CancelDeliveryFIFOJFC does per lot:
      ledger row 'STS CANCEL ITEM PO#13902', Available += 840, IsStock = 1, FIFO row flagged restored.

   Every expected value is checked first (the line still looks exactly like the bug left it, a single
   receipt branch / reference, no lot pushed above its quantity); if anything differs, nothing changes.
   Post-check: per PO both In Transit accounts 0, every ticket balanced, received qty = shipped qty;
   no live FIFO row on a cancelled line of 13902; no lot above its quantity.
   Backups of the rows it updates: Repair69_Backup_*. One transaction. A re-run stops at the start.

   BEFORE PRODUCTION: confirm with branches 012 and 005 that the full quantities arrived.
   ================================================================ */

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

IF OBJECT_ID('dbo.Repair69_Backup_DeliveryDetails', 'U') IS NOT NULL
    THROW 59990, 'This script has been run here before (Repair69_Backup_DeliveryDetails exists).', 1;

DECLARE @User VARCHAR(30) = 'REPAIR [69]';
DECLARE @Lines TABLE (PONumber VARCHAR(10) NOT NULL, SeqNo INT NOT NULL, PRIMARY KEY (PONumber, SeqNo));
INSERT INTO @Lines VALUES ('11911', 1), ('11913', 2), ('14100', 1);

-- accounts (JournalEntryMapping)
DECLARE @AcBrInv   VARCHAR(30) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'IT-BR-VATEX'     AND DebitCredit = 'D' AND IsActive = 1 ORDER BY Seq),
        @AcTransit VARCHAR(30) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'IT-BR-VATEX'     AND DebitCredit = 'C' AND IsActive = 1 ORDER BY Seq),
        @AcTrVatEx VARCHAR(30) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'IT-HO-VATEX'     AND DebitCredit = 'D' AND IsActive = 1 ORDER BY Seq),
        @AcTrVat   VARCHAR(30) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'IT-HO-VAT'       AND DebitCredit = 'D' AND IsActive = 1 ORDER BY Seq),
        @AcShortDr VARCHAR(30) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'STS-SHORT-VATEX' AND DebitCredit = 'D' AND IsActive = 1 ORDER BY Seq),
        @AcShortCr VARCHAR(30) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'STS-SHORT-VATEX' AND DebitCredit = 'C' AND IsActive = 1 ORDER BY Seq),
        @AcOverDr  VARCHAR(30) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'STS-OVER-VATEX'  AND DebitCredit = 'D' AND IsActive = 1 ORDER BY Seq),
        @AcOverCr  VARCHAR(30) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'STS-OVER-VATEX'  AND DebitCredit = 'C' AND IsActive = 1 ORDER BY Seq);
IF @AcBrInv IS NULL OR @AcTransit IS NULL OR @AcTrVatEx IS NULL OR @AcTrVat IS NULL OR @AcShortDr IS NULL OR @AcShortCr IS NULL OR @AcOverDr IS NULL OR @AcOverCr IS NULL
    THROW 59991, 'A JournalEntryMapping row (IT-BR-VATEX / IT-HO-VAT / IT-HO-VATEX / STS-SHORT-VATEX / STS-OVER-VATEX) is missing.', 1;
IF @AcTransit <> @AcTrVatEx
    THROW 59991, 'IT-BR-VATEX credits a different In Transit account than IT-HO-VATEX debits; check the mapping before repairing.', 1;

BEGIN TRANSACTION;

-- the same per-PO locks the STS and Sales Order writers take
DECLARE @lk INT, @res NVARCHAR(255), @po VARCHAR(10);
DECLARE lc CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT PONumber FROM @Lines;
OPEN lc; FETCH NEXT FROM lc INTO @po;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @res = N'STSTRANSIT:' + @po;
    EXEC @lk = sp_getapplock @Resource = @res, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 30000;
    IF @lk < 0 THROW 59992, 'Could not lock a transfer (a receive or return is in progress). Nothing changed.', 1;
    FETCH NEXT FROM lc INTO @po;
END
CLOSE lc; DEALLOCATE lc;
EXEC dbo.sp_SOOrder_Lock @PONumber = '13902';

------------------------------------------------------------------
-- A1. the lines, as the bug left them
------------------------------------------------------------------
CREATE TABLE #R69Line (
    PONumber VARCHAR(10) NOT NULL, SeqNo INT NOT NULL, DeliveryNo VARCHAR(20) NULL, ProductNo VARCHAR(20) NULL, ProductName VARCHAR(150) NULL,
    BarcodeNo VARCHAR(120) NULL, IsVat BIT NULL, SellingPrice DECIMAL(18,2) NULL, ShipQty DECIMAL(18,3) NULL, nLots INT NULL,
    RcvRows INT NULL, RcvQty DECIMAL(18,3) NULL, RcvRef VARCHAR(50) NULL, RcvFifo BIGINT NULL,
    RcvBranch VARCHAR(10) NULL, nRcvBranch INT NULL, RcvTicketRef VARCHAR(30) NULL, nRcvRef INT NULL, RcvDate DATE NULL,
    DevStatus VARCHAR(20) NULL, HasFixedLedger BIT NULL, Problem VARCHAR(300) NULL);
INSERT INTO #R69Line (PONumber, SeqNo, DeliveryNo, ProductNo, BarcodeNo, ShipQty, nLots, DevStatus)
SELECT l.PONumber, l.SeqNo, dd.DeliveryNo, dd.ProductNo, dd.BarcodeNo,
       (SELECT SUM(f.QtyDelivered) FROM dbo.InventoryDeliveryFIFO f WHERE f.PONumber = dd.PONumber AND f.DeliveryNo = dd.DeliveryNo AND f.DevDetSeqNo = dd.SeqNo AND f.isErrorCorrect = 0),
       (SELECT COUNT(*) FROM dbo.InventoryDeliveryFIFO f WHERE f.PONumber = dd.PONumber AND f.DeliveryNo = dd.DeliveryNo AND f.DevDetSeqNo = dd.SeqNo AND f.isErrorCorrect = 0),
       (SELECT TOP 1 d.Status FROM dbo.DeliverySummary d WHERE d.PONumber = dd.PONumber ORDER BY d.DeliveryNo DESC)
FROM @Lines l
LEFT JOIN dbo.DeliveryDetails dd ON dd.PONumber = l.PONumber AND dd.SeqNo = l.SeqNo AND dd.isCancelled = 0 AND dd.isReturned = 0;

UPDATE x SET RcvRows = r.n, RcvQty = r.Qty, RcvRef = r.Ref, ProductName = r.PName, IsVat = r.IsVat, SellingPrice = r.SP
FROM #R69Line x
CROSS APPLY (SELECT COUNT(*) AS n, SUM(rt.Qty) AS Qty, MAX(rt.ReferenceCode) AS Ref, MAX(rt.ProductName) AS PName,
                    CAST(MAX(CAST(ISNULL(rt.IsVat, 0) AS INT)) AS BIT) AS IsVat, MAX(ISNULL(rt.SellingPrice, 0)) AS SP
             FROM dbo.ReceivedOrderDetails rt WHERE rt.PONumber = x.PONumber AND rt.ProductCode = x.ProductNo AND rt.Barcode = x.BarcodeNo) r;

UPDATE x SET RcvFifo = (SELECT TOP 1 f.SequenceNumber FROM dbo.InventoryDeliveryFIFO f
                        LEFT JOIN dbo.Inventory src ON src.SequenceNumber = f.SequenceReferenceNumber
                        WHERE f.PONumber = x.PONumber AND f.DeliveryNo = x.DeliveryNo AND f.DevDetSeqNo = x.SeqNo AND f.isErrorCorrect = 0
                          AND ABS(f.QtyDelivered - x.RcvQty) < 0.001
                        ORDER BY CASE WHEN LEFT(ISNULL(src.ReferenceCode, ''), 20) = ISNULL(x.RcvRef, '') THEN 0 ELSE 1 END, f.SequenceNumber),
             HasFixedLedger = CASE WHEN EXISTS (SELECT 1 FROM dbo.InventoryLedger lg WHERE lg.Remarks = 'STS RCVD ITEM PO#' + x.PONumber AND lg.Product = x.ProductNo) THEN 1 ELSE 0 END,
             nRcvBranch = (SELECT COUNT(DISTINCT tm.BranchCode) FROM dbo.TicketMaster tm WHERE tm.ReferenceKey = x.PONumber AND tm.Mnemonic LIKE 'IT-BR-%'),
             nRcvRef    = (SELECT COUNT(DISTINCT tm.ReferenceNumber) FROM dbo.TicketMaster tm WHERE tm.ReferenceKey = x.PONumber AND tm.Mnemonic LIKE 'IT-BR-%'),
             RcvBranch  = (SELECT MAX(tm.BranchCode) FROM dbo.TicketMaster tm WHERE tm.ReferenceKey = x.PONumber AND tm.Mnemonic LIKE 'IT-BR-%'),
             RcvTicketRef = (SELECT MAX(tm.ReferenceNumber) FROM dbo.TicketMaster tm WHERE tm.ReferenceKey = x.PONumber AND tm.Mnemonic LIKE 'IT-BR-%'),
             RcvDate    = (SELECT MAX(CAST(tm.TicketDate AS DATE)) FROM dbo.TicketMaster tm WHERE tm.ReferenceKey = x.PONumber AND tm.Mnemonic LIKE 'IT-BR-%')
FROM #R69Line x;

UPDATE #R69Line SET Problem =
    CASE WHEN DeliveryNo IS NULL THEN 'line not found (or cancelled / returned)'
         WHEN ISNULL(DevStatus, '') <> 'DELIVERED' THEN 'transfer not marked received'
         WHEN nLots < 2 THEN 'line is not a multi-lot line'
         WHEN ISNULL(RcvRows, 0) <> 1 THEN 'not exactly one receipt row for the line (already repaired or received again?)'
         WHEN HasFixedLedger = 1 THEN 'the line already has STS RCVD ITEM ledger rows (received by the fixed proc)'
         WHEN RcvFifo IS NULL THEN 'the received qty is not one lot''s qty'
         WHEN RcvQty >= ShipQty - 0.001 THEN 'the line is already fully received'
         WHEN nRcvBranch <> 1 OR nRcvRef <> 1 THEN 'not exactly one receipt branch / reference'
    END;

SELECT PONumber, SeqNo, ProductNo, ShipQty, RcvQty, nLots, RcvBranch, RcvTicketRef, RcvDate, ISNULL(Problem, 'OK') AS [Check] FROM #R69Line ORDER BY PONumber;
IF EXISTS (SELECT 1 FROM #R69Line WHERE Problem IS NOT NULL)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 59993, 'A line is not as expected (see the Check column); nothing was changed.', 1;
END

------------------------------------------------------------------
-- A2. the batches still to receive (every live lot of the line except the one received)
------------------------------------------------------------------
CREATE TABLE #R69Batch (
    PONumber VARCHAR(10) NOT NULL, SeqNo INT NOT NULL, ShipmentNo VARCHAR(50) NOT NULL, ReferenceCode VARCHAR(50) NOT NULL,
    BatchCost DECIMAL(18,4) NOT NULL, Qty DECIMAL(18,3) NOT NULL, FirstFifo BIGINT NOT NULL, FirstLot BIGINT NOT NULL,
    Value DECIMAL(18,2) NOT NULL);
INSERT INTO #R69Batch
SELECT x.PONumber, x.SeqNo, ISNULL(src.ShipmentNo, ''), ISNULL(src.ReferenceCode, ''), CAST(f.Cost AS DECIMAL(18,4)),
       CAST(SUM(f.QtyDelivered) AS DECIMAL(18,3)), MIN(f.SequenceNumber), MIN(f.SequenceReferenceNumber), 0
FROM #R69Line x
INNER JOIN dbo.InventoryDeliveryFIFO f ON f.PONumber = x.PONumber AND f.DeliveryNo = x.DeliveryNo AND f.DevDetSeqNo = x.SeqNo
       AND f.isErrorCorrect = 0 AND f.SequenceNumber <> x.RcvFifo
INNER JOIN dbo.Inventory src ON src.SequenceNumber = f.SequenceReferenceNumber
GROUP BY x.PONumber, x.SeqNo, ISNULL(src.ShipmentNo, ''), ISNULL(src.ReferenceCode, ''), CAST(f.Cost AS DECIMAL(18,4));
UPDATE #R69Batch SET Value = ROUND(Qty * ROUND(BatchCost, 2), 2);   -- = sp_ConfirmBranchRecievedOrderJFC: ROUND(Qty * Cost, 2), Cost 2 dp

IF EXISTS (SELECT 1 FROM #R69Line x WHERE ABS(x.ShipQty - x.RcvQty - (SELECT SUM(b.Qty) FROM #R69Batch b WHERE b.PONumber = x.PONumber AND b.SeqNo = x.SeqNo)) > 0.001)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 59994, 'The remaining lots do not add up to shipped - received for a line; nothing was changed.', 1;
END

------------------------------------------------------------------
-- backups (rows this script updates)
------------------------------------------------------------------
SELECT dd.* INTO dbo.Repair69_Backup_DeliveryDetails FROM dbo.DeliveryDetails dd
WHERE dd.PONumber IN ('11911', '11913', '14100', '13902');
SELECT ds.* INTO dbo.Repair69_Backup_DeliverySummary FROM dbo.DeliverySummary ds WHERE ds.PONumber IN ('11911', '11913', '14100');
SELECT rs.* INTO dbo.Repair69_Backup_ReceiveOrderSummary FROM dbo.ReceiveOrderSummary rs WHERE rs.PONumber IN ('11911', '11913', '14100');
SELECT f.* INTO dbo.Repair69_Backup_InventoryDeliveryFIFO FROM dbo.InventoryDeliveryFIFO f WHERE f.PONumber = '13902';
SELECT i.* INTO dbo.Repair69_Backup_Inventory FROM dbo.Inventory i WHERE i.SequenceNumber = 30778;

------------------------------------------------------------------
-- A3. branch stock, receipt rows, stock ledger (as spu_PostSTSReceiveFromFIFO, per batch)
------------------------------------------------------------------
INSERT INTO dbo.Inventory
    (Branch, ShipmentNo, PalletNo, BatchCode, DateReceived, ExpiryDate, Product, Description, Barcode,
     TipWeight, Quantity, Cost, Available, QtyBigBlue, IsStock, IsVat, IsWarehouse, ReferenceCode,
     LastMovementDate, isProcess, isSource, isConversion)
SELECT x.RcvBranch, b.ShipmentNo, 0, 0, x.RcvDate, NULL, x.ProductNo, x.ProductName, x.BarcodeNo,
       b.Qty, b.Qty, ROUND(b.BatchCost, 2), b.Qty, 0, 1, x.IsVat, 1, b.ReferenceCode,
       GETDATE(), 0, 0, 0
FROM #R69Batch b INNER JOIN #R69Line x ON x.PONumber = b.PONumber AND x.SeqNo = b.SeqNo
WHERE b.Qty > 0
ORDER BY b.PONumber, b.FirstFifo;

INSERT INTO dbo.ReceivedOrderDetails
    (SeqNo, PONumber, ProductCode, ProductName, Barcode, Qty, Cost, SellingPrice, IsVat, ReferenceCode)
SELECT ISNULL((SELECT MAX(r.SeqNo) FROM dbo.ReceivedOrderDetails r WHERE r.PONumber = b.PONumber), 0)
           + ROW_NUMBER() OVER (PARTITION BY b.PONumber ORDER BY b.FirstFifo),
       b.PONumber, x.ProductNo, LEFT(x.ProductName, 50), x.BarcodeNo, b.Qty, ROUND(b.BatchCost, 2), ISNULL(x.SellingPrice, 0), x.IsVat,
       LEFT(b.ReferenceCode, 20)
FROM #R69Batch b INNER JOIN #R69Line x ON x.PONumber = b.PONumber AND x.SeqNo = b.SeqNo
WHERE b.Qty > 0;

INSERT INTO dbo.InventoryLedger
    (SequenceRefNum, OriginBranch, DestinationBranch, DateProcessed, Product, Description,
     BegQty, QtyIN, QtyOut, EndQty, Cost, Remarks, ProcessedBy)
SELECT b.FirstLot, x.RcvBranch, x.RcvBranch, GETDATE(), x.ProductNo, x.ProductName,
       0, b.Qty, 0, b.Qty, b.BatchCost, 'STS RCVD ITEM PO#' + b.PONumber, @User
FROM #R69Batch b INNER JOIN #R69Line x ON x.PONumber = b.PONumber AND x.SeqNo = b.SeqNo
WHERE b.Qty > 0
ORDER BY b.PONumber, b.FirstFifo;

UPDATE dd SET dd.ActualQty = dd.QtyDelivered, dd.Variance = 0
FROM dbo.DeliveryDetails dd INNER JOIN #R69Line x ON x.PONumber = dd.PONumber AND x.DeliveryNo = dd.DeliveryNo AND x.SeqNo = dd.SeqNo;

-- header totals (as sp_ConfirmBranchRecievedOrderJFC)
UPDATE ds
SET TotalActualQty         = t.ActQty,
    TotalVarianceVat       = t.VarVat,
    TotalVarianceVatExempt = t.VarVatEx
FROM dbo.DeliverySummary ds
CROSS APPLY (SELECT ISNULL(SUM(d.ActualQty), 0) AS ActQty,
                    ISNULL(SUM(CASE WHEN d.isVat = 1 THEN ABS(d.Variance) ELSE 0 END), 0) AS VarVat,
                    ISNULL(SUM(CASE WHEN d.isVat = 0 THEN ABS(d.Variance) ELSE 0 END), 0) AS VarVatEx
             FROM dbo.DeliveryDetails d WHERE d.PONumber = ds.PONumber AND d.isCancelled = 0 AND d.isReturned = 0) t
WHERE ds.PONumber IN (SELECT PONumber FROM #R69Line);

UPDATE rs SET TotalKilo = (SELECT ISNULL(SUM(r.Qty), 0) FROM dbo.ReceivedOrderDetails r WHERE r.PONumber = rs.PONumber)
FROM dbo.ReceiveOrderSummary rs WHERE rs.PONumber IN (SELECT PONumber FROM #R69Line);

------------------------------------------------------------------
-- A4. GL: receipt of the rest (+ 14100's VAT -> VAT-exempt In Transit), then the rounding residue
------------------------------------------------------------------
CREATE TABLE #R69Legs (PONumber VARCHAR(10), Kind CHAR(1), BranchCode VARCHAR(10), AccountCode VARCHAR(30), Amount DECIMAL(18,2));  -- Amount > 0 = debit
DECLARE @T TABLE (PONumber VARCHAR(10) PRIMARY KEY, NewValue DECIMAL(18,2), TrVatEx DECIMAL(18,2), TrVat DECIMAL(18,2), Residue DECIMAL(18,2));
INSERT INTO @T (PONumber, NewValue, TrVatEx, TrVat)
SELECT x.PONumber,
       (SELECT SUM(b.Value) FROM #R69Batch b WHERE b.PONumber = x.PONumber),
       (SELECT ISNULL(SUM(td.Debit - td.Credit), 0) FROM dbo.TicketMaster tm INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
        WHERE tm.ReferenceKey = x.PONumber AND td.AccountCode = @AcTrVatEx AND (tm.Mnemonic LIKE 'IT-%' OR tm.Mnemonic LIKE 'ITR-%' OR tm.Mnemonic LIKE 'STS-%')),
       (SELECT ISNULL(SUM(td.Debit - td.Credit), 0) FROM dbo.TicketMaster tm INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
        WHERE tm.ReferenceKey = x.PONumber AND td.AccountCode = @AcTrVat AND (tm.Mnemonic LIKE 'IT-%' OR tm.Mnemonic LIKE 'ITR-%' OR tm.Mnemonic LIKE 'STS-%'))
FROM (SELECT DISTINCT PONumber FROM #R69Line) x;
-- what is left on VAT-exempt In Transit after the receipt and the VAT reclass = the old receipt's rounding
UPDATE @T SET Residue = TrVatEx + TrVat - NewValue;

IF EXISTS (SELECT 1 FROM @T WHERE ABS(Residue) > 5.00)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 59995, 'After the repair a PO would still have more than 5.00 in In Transit; the data is not as expected. Nothing changed.', 1;
END

-- receipt ticket (receiving branch): DR branch inventory / CR In Transit; 14100: DR VAT In Transit / CR VAT-exempt In Transit
INSERT INTO #R69Legs SELECT t.PONumber, 'R', x.RcvBranch, @AcBrInv,     t.NewValue  FROM @T t CROSS APPLY (SELECT TOP 1 RcvBranch FROM #R69Line WHERE PONumber = t.PONumber) x;
INSERT INTO #R69Legs SELECT t.PONumber, 'R', x.RcvBranch, @AcTransit,  -t.NewValue  FROM @T t CROSS APPLY (SELECT TOP 1 RcvBranch FROM #R69Line WHERE PONumber = t.PONumber) x;
INSERT INTO #R69Legs SELECT t.PONumber, 'R', x.RcvBranch, @AcTrVat,    -t.TrVat     FROM @T t CROSS APPLY (SELECT TOP 1 RcvBranch FROM #R69Line WHERE PONumber = t.PONumber) x WHERE t.TrVat <> 0;
INSERT INTO #R69Legs SELECT t.PONumber, 'R', x.RcvBranch, @AcTrVatEx,   t.TrVat     FROM @T t CROSS APPLY (SELECT TOP 1 RcvBranch FROM #R69Line WHERE PONumber = t.PONumber) x WHERE t.TrVat <> 0;
-- rounding residue (888), as the confirm proc's short / over
INSERT INTO #R69Legs SELECT PONumber, 'S', '888', @AcShortDr,  Residue FROM @T WHERE Residue >=  0.01;
INSERT INTO #R69Legs SELECT PONumber, 'S', '888', @AcShortCr, -Residue FROM @T WHERE Residue >=  0.01;
INSERT INTO #R69Legs SELECT PONumber, 'O', '888', @AcOverDr,  -Residue FROM @T WHERE Residue <= -0.01;
INSERT INTO #R69Legs SELECT PONumber, 'O', '888', @AcOverCr,   Residue FROM @T WHERE Residue <= -0.01;

DECLARE @Tk TABLE (PONumber VARCHAR(10), Kind CHAR(1), TicketNumber BIGINT);
DECLARE @k CHAR(1), @br VARCHAR(10), @tn BIGINT, @ref VARCHAR(30), @dt DATE, @mn VARCHAR(30), @part VARCHAR(400);
DECLARE tc CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT PONumber, Kind, BranchCode FROM #R69Legs ORDER BY PONumber, Kind;
OPEN tc; FETCH NEXT FROM tc INTO @po, @k, @br;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT TOP 1 @ref = RcvTicketRef, @dt = RcvDate FROM #R69Line WHERE PONumber = @po;
    SET @mn = CASE @k WHEN 'R' THEN 'IT-BR-VATEX' WHEN 'S' THEN 'STS-SHORT-VATEX' ELSE 'STS-OVER-VATEX' END;
    SET @part = CASE @k WHEN 'R' THEN 'Inventory Transfer In - PO#' + @po + ' (' + @br + ') - VAT Exempt - repair [69]: rest of the multi-lot line the 2026-10-01 receipt did not book'
                        WHEN 'S' THEN 'Short receipt - PO#' + @po + ' (Branch 888) - VAT Exempt - repair [69]: rounding of the 2026-10-01 receipt'
                        ELSE 'Over receipt - PO#' + @po + ' (Branch 888) - VAT Exempt - repair [69]: rounding of the 2026-10-01 receipt' END;
    EXEC GetTicketNumber @tn OUTPUT;
    INSERT INTO dbo.TicketMaster
        (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber, ReferenceNumber, ReferenceKey,
         Owner, Particulars, EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
    VALUES (@dt, 0, @br, 'IT', @tn, @ref, @po, 'CS IN TRANSIT', @part, @User, '*', '*', 'POSTED', @mn, '');
    INSERT INTO dbo.TicketDetails
        (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey, TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
    SELECT @dt, 0, @br, @po, @tn, @ref, g.AccountCode,
           CASE WHEN g.Net > 0 THEN g.Net ELSE 0 END, CASE WHEN g.Net < 0 THEN -g.Net ELSE 0 END, @br
    FROM (SELECT AccountCode, SUM(Amount) AS Net FROM #R69Legs WHERE PONumber = @po AND Kind = @k GROUP BY AccountCode) g
    WHERE g.Net <> 0;
    INSERT INTO @Tk VALUES (@po, @k, @tn);
    FETCH NEXT FROM tc INTO @po, @k, @br;
END
CLOSE tc; DEALLOCATE tc;

------------------------------------------------------------------
-- B. SO 13902: put back what the old cancel left out of lot 30778
------------------------------------------------------------------
CREATE TABLE #R69Fifo (FifoSeq BIGINT, Lot BIGINT, Qty DECIMAL(18,3), Cost DECIMAL(18,4), Descr VARCHAR(400), Branch VARCHAR(10), Product VARCHAR(20));
INSERT INTO #R69Fifo
SELECT f.SequenceNumber, f.SequenceReferenceNumber, f.QtyDelivered, f.Cost, f.Description, f.BranchCode, f.ProductNo
FROM dbo.InventoryDeliveryFIFO f
INNER JOIN dbo.DeliveryDetails dd ON dd.DeliveryNo = f.DeliveryNo AND dd.PONumber = f.PONumber AND dd.SeqNo = f.DevDetSeqNo
WHERE f.PONumber = '13902' AND f.isErrorCorrect = 0 AND (dd.isCancelled = 1 OR dd.isReturned = 1);

IF (SELECT COUNT(*) FROM #R69Fifo) <> 1
   OR NOT EXISTS (SELECT 1 FROM #R69Fifo WHERE Lot = 30778 AND ABS(Qty - 840) < 0.001 AND Product = '14016')
BEGIN
    ROLLBACK TRANSACTION;
    THROW 59996, 'SO 13902: expected exactly one live FIFO row on a cancelled line (lot 30778, 840 of 14016); nothing was changed.', 1;
END
IF EXISTS (SELECT 1 FROM #R69Fifo r INNER JOIN dbo.Inventory i ON i.SequenceNumber = r.Lot WHERE ISNULL(i.Available, 0) + r.Qty > ISNULL(i.Quantity, 0) + 0.001)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 59997, 'SO 13902: restoring 840 would push lot 30778 above its quantity (already restored?); nothing was changed.', 1;
END

INSERT INTO dbo.InventoryLedger
    (SequenceRefNum, OriginBranch, DestinationBranch, DateProcessed, Product, Description, BegQty, QtyIn, QtyOut, EndQty, Cost, Remarks, ProcessedBy)
SELECT r.Lot, i.Branch, r.Branch, GETDATE(), r.Product, r.Descr, ISNULL(i.Available, 0), r.Qty, 0, ISNULL(i.Available, 0) + r.Qty, r.Cost,
       'STS CANCEL ITEM PO#13902', @User
FROM #R69Fifo r INNER JOIN dbo.Inventory i ON i.SequenceNumber = r.Lot;

UPDATE i SET i.Available = ISNULL(i.Available, 0) + r.Qty, i.IsStock = 1, i.LastMovementDate = GETDATE()
FROM dbo.Inventory i INNER JOIN #R69Fifo r ON r.Lot = i.SequenceNumber;

UPDATE f SET f.isErrorCorrect = 1
FROM dbo.InventoryDeliveryFIFO f INNER JOIN #R69Fifo r ON r.FifoSeq = f.SequenceNumber;

------------------------------------------------------------------
-- post-check
------------------------------------------------------------------
DECLARE @bad NVARCHAR(2000);
SELECT @bad = STRING_AGG(CAST(x.PONumber + ': ' + x.Why AS NVARCHAR(MAX)), '; ')
FROM (
    -- both In Transit accounts at 0
    SELECT t.PONumber, 'In Transit ' + a.AccountCode + ' = ' + CAST(a.Bal AS VARCHAR(30)) AS Why
    FROM @T t
    CROSS APPLY (SELECT td.AccountCode, SUM(td.Debit - td.Credit) AS Bal
                 FROM dbo.TicketMaster tm INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
                 WHERE tm.ReferenceKey = t.PONumber AND td.AccountCode IN (@AcTrVat, @AcTrVatEx)
                   AND (tm.Mnemonic LIKE 'IT-%' OR tm.Mnemonic LIKE 'ITR-%' OR tm.Mnemonic LIKE 'STS-%')
                 GROUP BY td.AccountCode) a
    WHERE ABS(a.Bal) >= 0.005
    UNION ALL
    -- every ticket of the PO balanced
    SELECT tm.ReferenceKey, 'ticket ' + CAST(tm.TicketNumber AS VARCHAR(20)) + ' DR <> CR'
    FROM dbo.TicketMaster tm INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
    WHERE tm.ReferenceKey IN (SELECT PONumber FROM @T)
    GROUP BY tm.ReferenceKey, tm.TicketNumber HAVING ABS(SUM(td.Debit) - SUM(td.Credit)) >= 0.005
    UNION ALL
    -- received qty = shipped qty on the repaired lines, one receipt reference per PO
    SELECT x.PONumber, 'line ' + CAST(x.SeqNo AS VARCHAR(10)) + ' received ' + CAST((SELECT SUM(r.Qty) FROM dbo.ReceivedOrderDetails r WHERE r.PONumber = x.PONumber AND r.ProductCode = x.ProductNo AND r.Barcode = x.BarcodeNo) AS VARCHAR(30))
    FROM #R69Line x
    WHERE ABS(x.ShipQty - (SELECT SUM(r.Qty) FROM dbo.ReceivedOrderDetails r WHERE r.PONumber = x.PONumber AND r.ProductCode = x.ProductNo AND r.Barcode = x.BarcodeNo)) > 0.001
       OR (SELECT COUNT(DISTINCT tm.ReferenceNumber) FROM dbo.TicketMaster tm WHERE tm.ReferenceKey = x.PONumber AND tm.Mnemonic LIKE 'IT-BR-%') <> 1
    UNION ALL
    -- SO 13902: no live FIFO row on a cancelled / returned line
    SELECT '13902', 'live FIFO row ' + CAST(f.SequenceNumber AS VARCHAR(20)) + ' on a cancelled line'
    FROM dbo.InventoryDeliveryFIFO f
    INNER JOIN dbo.DeliveryDetails dd ON dd.DeliveryNo = f.DeliveryNo AND dd.PONumber = f.PONumber AND dd.SeqNo = f.DevDetSeqNo
    WHERE f.PONumber = '13902' AND f.isErrorCorrect = 0 AND (dd.isCancelled = 1 OR dd.isReturned = 1)
    UNION ALL
    -- no lot above its quantity (the lots touched)
    SELECT 'lot ' + CAST(i.SequenceNumber AS VARCHAR(20)), 'Available ' + CAST(i.Available AS VARCHAR(30)) + ' > Quantity ' + CAST(i.Quantity AS VARCHAR(30))
    FROM dbo.Inventory i WHERE i.SequenceNumber = 30778 AND i.Available > i.Quantity + 0.001
) x;
IF @bad IS NOT NULL
BEGIN
    SET @bad = N'Post-check failed; nothing was changed: ' + @bad;
    ROLLBACK TRANSACTION;
    THROW 59998, @bad, 1;
END

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;

-- result
SELECT t.PONumber, t.NewValue AS ReceivedNow, t.TrVat AS VatTransitMoved, t.Residue AS RoundingResidue,
       (SELECT STRING_AGG(CAST(k.Kind AS VARCHAR(1)) + ':' + CAST(k.TicketNumber AS VARCHAR(20)), ', ') FROM @Tk k WHERE k.PONumber = t.PONumber) AS Tickets
FROM @T t ORDER BY t.PONumber;
SELECT b.PONumber, COUNT(*) AS Batches, SUM(b.Qty) AS QtyReceivedNow FROM #R69Batch b GROUP BY b.PONumber ORDER BY b.PONumber;
