SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#d') IS NOT NULL DROP TABLE #d;
SELECT i.SequenceNumber, i.Branch, LTRIM(RTRIM(i.Barcode)) bc, i.ReferenceCode, i.Quantity, i.Available, i.DateReceived,
       CASE WHEN i.ReferenceCode LIKE 'INVIN-%' THEN 'INVIN' WHEN i.ReferenceCode LIKE 'INVCOUNT%' THEN 'INVCOUNT'
            ELSE LEFT(i.ReferenceCode, 4) END rk
INTO #d FROM Inventory i
WHERE i.Branch='888' AND LTRIM(RTRIM(i.Barcode)) IN (SELECT LTRIM(RTRIM(Barcode)) FROM Inventory WHERE Branch='888' AND ISNULL(LTRIM(RTRIM(Barcode)),'')<>'' GROUP BY LTRIM(RTRIM(Barcode)) HAVING COUNT(*)>1);
SELECT LEFT(bc,3) pfx, rk, COUNT(*) rows_, SUM(CASE WHEN Available>0 THEN 1 ELSE 0 END) live, SUM(Available) avail FROM #d GROUP BY LEFT(bc,3), rk ORDER BY rows_ DESC;
-- groups without INVIN: how do the rows differ?
SELECT TOP 12 d.* FROM #d d WHERE bc IN (SELECT TOP 4 bc FROM #d GROUP BY bc HAVING SUM(CASE WHEN rk='INVIN' THEN 1 ELSE 0 END)=0 ORDER BY bc) ORDER BY bc, SequenceNumber;
-- references to INVIN rows in history tables
SELECT 'InventoryLedger' t, COUNT(*) n FROM InventoryLedger WHERE SequenceNumber IN (SELECT SequenceNumber FROM #d WHERE rk='INVIN')
UNION ALL SELECT 'InventoryLedgerDeduct', COUNT(*) FROM InventoryLedgerDeduct WHERE InventorySequenceNumber IN (SELECT SequenceNumber FROM #d WHERE rk='INVIN')
UNION ALL SELECT 'InventoryDeliveryFIFO', COUNT(*) FROM InventoryDeliveryFIFO WHERE SequenceNumber IN (SELECT SequenceNumber FROM #d WHERE rk='INVIN')
UNION ALL SELECT 'ConversionFIFO', COUNT(*) FROM ConversionFIFO WHERE SequenceNumber IN (SELECT SequenceNumber FROM #d WHERE rk='INVIN')
UNION ALL SELECT 'InventoryBranchTransferFIFO', COUNT(*) FROM InventoryBranchTransferFIFO WHERE SequenceNumber IN (SELECT SequenceNumber FROM #d WHERE rk='INVIN')
UNION ALL SELECT 'StockOutBarcodeDetails', COUNT(*) FROM StockOutBarcodeDetails WHERE InventorySeqNo IN (SELECT SequenceNumber FROM #d WHERE rk='INVIN')
UNION ALL SELECT 'SalesLedgerFIFO', COUNT(*) FROM SalesLedgerFIFO WHERE SequenceNumber IN (SELECT SequenceNumber FROM #d WHERE rk='INVIN')
UNION ALL SELECT 'ConversionSummary.Source', COUNT(*) FROM ConversionSummary WHERE SourceSequenceNumber IN (SELECT SequenceNumber FROM #d WHERE rk='INVIN');
