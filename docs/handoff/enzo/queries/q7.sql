SET NOCOUNT ON;
DECLARE @d DATE = DATEADD(DAY,-30,CAST(GETDATE() AS DATE));
SELECT 'Inventory' t, IsWarehouse, CASE WHEN Available>0 THEN 'Available>0' ELSE 'Available<=0' END avail, COUNT(*) n, CAST(SUM(Available) AS DECIMAL(18,3)) qty, COUNT(DISTINCT Branch) branches
FROM dbo.Inventory GROUP BY IsWarehouse, CASE WHEN Available>0 THEN 'Available>0' ELSE 'Available<=0' END ORDER BY 2,3;
SELECT Branch, SUM(CASE WHEN IsWarehouse=1 AND Available>0 THEN 1 ELSE 0 END) wh1_lots, SUM(CASE WHEN IsWarehouse=0 AND Available>0 THEN 1 ELSE 0 END) wh0_lots,
 SUM(CASE WHEN IsWarehouse IS NULL AND Available>0 THEN 1 ELSE 0 END) whnull_lots FROM dbo.Inventory GROUP BY Branch ORDER BY Branch;
SELECT (SELECT COUNT(*) FROM dbo.Branches) branches, (SELECT COUNT(DISTINCT ProductCode) FROM dbo.Products) products, (SELECT COUNT(*) FROM dbo.Products) product_rows,
 (SELECT COUNT(*) FROM dbo.TicketMaster) ticketmaster, (SELECT COUNT(*) FROM dbo.TicketDetails) ticketdetails, (SELECT MIN(TicketDate) FROM dbo.TicketMaster) tm_min, (SELECT MAX(TicketDate) FROM dbo.TicketMaster) tm_max,
 (SELECT COUNT(*) FROM dbo.ChartOfAccounts) coa, OBJECT_ID('dbo.JournalEntryMapping') jem_obj, OBJECT_ID('dbo.GLPeriodLock') glpl_obj;
SELECT CASE WHEN Barcode IS NULL OR LTRIM(RTRIM(Barcode))='' THEN 'blank' WHEN Barcode LIKE 'A01%' THEN 'A01' WHEN Barcode LIKE 'B01%' THEN 'B01' WHEN Barcode LIKE 'C01%' THEN 'C01' WHEN Barcode LIKE 'D01%' THEN 'D01'
 WHEN LEN(Barcode)=19 AND Barcode NOT LIKE '%[^0-9]%' THEN '19-digit' ELSE LEFT(Barcode,3)+'... len '+CAST(LEN(Barcode) AS VARCHAR) END pat,
 COUNT(*) lots, SUM(CASE WHEN Available>0 THEN 1 ELSE 0 END) live_lots
FROM dbo.Inventory GROUP BY CASE WHEN Barcode IS NULL OR LTRIM(RTRIM(Barcode))='' THEN 'blank' WHEN Barcode LIKE 'A01%' THEN 'A01' WHEN Barcode LIKE 'B01%' THEN 'B01' WHEN Barcode LIKE 'C01%' THEN 'C01' WHEN Barcode LIKE 'D01%' THEN 'D01'
 WHEN LEN(Barcode)=19 AND Barcode NOT LIKE '%[^0-9]%' THEN '19-digit' ELSE LEFT(Barcode,3)+'... len '+CAST(LEN(Barcode) AS VARCHAR) END ORDER BY lots DESC;
SELECT 'PurchaseOrderSummary (SO/PO, Dateadded)' t, COUNT(*) n FROM dbo.PurchaseOrderSummary WHERE Dateadded>=@d
UNION ALL SELECT 'POSUMMARY (supplier PO, DateOrder)', COUNT(*) FROM dbo.POSUMMARY WHERE DateOrder>=@d
UNION ALL SELECT 'DeliverySummary (DateAdded)', COUNT(*) FROM dbo.DeliverySummary WHERE DateAdded>=@d
UNION ALL SELECT 'DeliverySummary sales (PO in PurchaseOrderSummary)', COUNT(*) FROM dbo.DeliverySummary d WHERE DateAdded>=@d AND EXISTS(SELECT 1 FROM dbo.PurchaseOrderSummary p WHERE p.PONumber=d.PONumber) AND NOT EXISTS(SELECT 1 FROM dbo.TransferOrderSummary x WHERE x.PONumber=d.PONumber)
UNION ALL SELECT 'DeliverySummary STS (PO in TransferOrderSummary)', COUNT(*) FROM dbo.DeliverySummary d WHERE DateAdded>=@d AND EXISTS(SELECT 1 FROM dbo.TransferOrderSummary x WHERE x.PONumber=d.PONumber)
UNION ALL SELECT 'TransferOrderSummary (Dateadded)', COUNT(*) FROM dbo.TransferOrderSummary WHERE Dateadded>=@d
UNION ALL SELECT 'ReceiveOrderSummary (DateReceived)', COUNT(*) FROM dbo.ReceiveOrderSummary WHERE DateReceived>=@d
UNION ALL SELECT 'TransferInventorySummary branch transfer (DateAdded)', COUNT(*) FROM dbo.TransferInventorySummary WHERE DateAdded>=@d
UNION ALL SELECT 'ReceiveTransferInventorySummary (DateReceived)', COUNT(*) FROM dbo.ReceiveTransferInventorySummary WHERE DateReceived>=@d
UNION ALL SELECT 'TransferBatch (CreatedAt)', COUNT(*) FROM dbo.TransferBatch WHERE CreatedAt>=@d
UNION ALL SELECT 'InventoryLedger (DateProcessed)', COUNT(*) FROM dbo.InventoryLedger WHERE DateProcessed>=@d
UNION ALL SELECT 'ConversionSummary (DateConverted)', COUNT(*) FROM dbo.ConversionSummary WHERE DateConverted>=@d
UNION ALL SELECT 'StockOutBarcodeSummary (DateAdded)', COUNT(*) FROM dbo.StockOutBarcodeSummary WHERE DateAdded>=@d
UNION ALL SELECT 'StockOutDetails (DateEncode)', COUNT(*) FROM dbo.StockOutDetails WHERE DateEncode>=@d
UNION ALL SELECT 'InventoryIN (DateReceived)', COUNT(*) FROM dbo.InventoryIN WHERE DateReceived>=@d
UNION ALL SELECT 'BatchSalesSummary (Transdate)', COUNT(*) FROM dbo.BatchSalesSummary WHERE Transdate>=@d
UNION ALL SELECT 'POSSalesSummary (DateOrder)', COUNT(*) FROM dbo.POSSalesSummary WHERE DateOrder>=@d
UNION ALL SELECT 'ReturnedOrderSummary (DateAdded)', COUNT(*) FROM dbo.ReturnedOrderSummary WHERE DateAdded>=@d
UNION ALL SELECT 'TicketMaster (TicketDate)', COUNT(*) FROM dbo.TicketMaster WHERE TicketDate>=@d
UNION ALL SELECT 'TransactionChargeSales (all)', COUNT(*) FROM dbo.TransactionChargeSales
UNION ALL SELECT 'InventoryBranchTransferFIFO (DateAdded)', COUNT(*) FROM dbo.InventoryBranchTransferFIFO WHERE DateAdded>=@d;
SELECT TOP 10 Mnemonic, COUNT(*) n, MIN(TicketDate) mn, MAX(TicketDate) mx FROM dbo.TicketMaster GROUP BY Mnemonic ORDER BY n DESC;
SELECT InventoryType=ISNULL(CAST(IsWarehouse AS VARCHAR),'NULL'), Branch, COUNT(*) n FROM dbo.Inventory WHERE Available>0 AND Branch='888' GROUP BY IsWarehouse, Branch;
