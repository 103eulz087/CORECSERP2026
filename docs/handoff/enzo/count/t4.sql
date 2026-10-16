SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#p') IS NOT NULL DROP TABLE #p;
-- pairs: each INVIN row at 888 with its original (same barcode, not INVIN, not stsfifo)
SELECT c.SequenceNumber cSeq, o.SequenceNumber oSeq, LTRIM(RTRIM(c.Barcode)) bc, c.Product, c.Quantity cQty, c.Available cAvail,
       o.Quantity oQty, o.Available oAvail, c.Cost cCost, o.Cost oCost, c.DateReceived cDate, o.DateReceived oDate, c.IsWarehouse cWh, o.IsWarehouse oWh
INTO #p
FROM Inventory c
OUTER APPLY (SELECT TOP 1 * FROM Inventory o WHERE o.Branch='888' AND LTRIM(RTRIM(o.Barcode))=LTRIM(RTRIM(c.Barcode))
             AND ISNULL(o.ReferenceCode,'') NOT LIKE 'INVIN-%' AND ISNULL(o.ReferenceCode,'') <> 'stsfifo' ORDER BY o.SequenceNumber) o
WHERE c.Branch='888' AND c.ReferenceCode LIKE 'INVIN-%';
SELECT COUNT(*) invin_rows, COUNT(DISTINCT bc) barcodes, SUM(CASE WHEN oSeq IS NULL THEN 1 ELSE 0 END) no_original,
       SUM(CASE WHEN oAvail > 0 THEN 1 ELSE 0 END) original_live, SUM(CASE WHEN cAvail > 0 THEN 1 ELSE 0 END) copy_live,
       SUM(CASE WHEN cCost <> oCost THEN 1 ELSE 0 END) cost_diff, SUM(CASE WHEN cQty <> oQty THEN 1 ELSE 0 END) qty_diff,
       SUM(CASE WHEN cWh <> oWh THEN 1 ELSE 0 END) wh_diff
FROM #p;
SELECT 'FIFO rows on copy' k, COUNT(*) n FROM InventoryDeliveryFIFO f JOIN #p ON f.SequenceReferenceNumber = #p.cSeq
UNION ALL SELECT 'POS deduct rows on copy', COUNT(*) FROM InventoryLedgerDeduct d JOIN #p ON d.InventorySequenceNumber = #p.cSeq
UNION ALL SELECT 'ledger rows on copy', COUNT(*) FROM InventoryLedger l JOIN #p ON l.SequenceRefNum = CAST(#p.cSeq AS varchar(30))
UNION ALL SELECT 'stock out rows on copy', COUNT(*) FROM StockOutBarcodeDetails s JOIN #p ON s.InventorySeqNo = #p.cSeq
UNION ALL SELECT 'conversion src on copy', COUNT(*) FROM ConversionSummary s JOIN #p ON s.SourceSequenceNumber = #p.cSeq
UNION ALL SELECT 'FIFO rows on original', COUNT(*) FROM InventoryDeliveryFIFO f JOIN #p ON f.SequenceReferenceNumber = #p.oSeq
UNION ALL SELECT 'POS deduct on original', COUNT(*) FROM InventoryLedgerDeduct d JOIN #p ON d.InventorySequenceNumber = #p.oSeq;
-- barcodes with more than one INVIN copy
SELECT COUNT(*) barcodes_multi_copy FROM (SELECT bc FROM #p GROUP BY bc HAVING COUNT(*) > 1) x;
