SET NOCOUNT ON;
SELECT OBJECT_NAME(object_id) tbl, name FROM sys.identity_columns WHERE OBJECT_NAME(object_id) IN ('InventoryLedger','Inventory','InventoryLedgerDeduct','InventoryINMonthEnd');
IF OBJECT_ID('tempdb..#v') IS NOT NULL DROP TABLE #v;
SELECT SequenceNumber, Product, Barcode, Quantity, Available FROM Inventory WHERE Branch='888' AND ReferenceCode LIKE 'INVIN-%' AND DateReceived >= '2026-09-01';
SELECT TOP 0 1 x;
SELECT LEFT(Remarks, 22) rem, COUNT(*) n, SUM(QtyOut) qout, SUM(QtyIN) qin
FROM InventoryLedger l
WHERE l.SequenceRefNum IN (SELECT CAST(SequenceNumber AS varchar(30)) FROM Inventory WHERE Branch='888' AND ReferenceCode LIKE 'INVIN-%')
GROUP BY LEFT(Remarks, 22) ORDER BY n DESC;
SELECT TOP 5 * FROM InventoryLedger ORDER BY SequenceNumber DESC;
