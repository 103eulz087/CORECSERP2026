SET NOCOUNT ON;
;WITH b AS (
  SELECT Branch, LTRIM(RTRIM(Barcode)) bc, COUNT(*) n,
         SUM(CASE WHEN ReferenceCode LIKE 'INVIN-%' THEN 1 ELSE 0 END) ninv,
         SUM(CASE WHEN Available > 0 THEN 1 ELSE 0 END) nlive
  FROM Inventory WHERE ISNULL(LTRIM(RTRIM(Barcode)),'') <> '' GROUP BY Branch, LTRIM(RTRIM(Barcode)) HAVING COUNT(*) > 1)
SELECT Branch, COUNT(*) barcodes, SUM(n) rows_, SUM(CASE WHEN ninv>0 THEN 1 ELSE 0 END) with_invin,
       SUM(CASE WHEN nlive>1 THEN 1 ELSE 0 END) two_live, MAX(n) maxrows
FROM b GROUP BY Branch ORDER BY barcodes DESC;
-- INVIN rows by count month
SELECT LEFT(CONVERT(varchar(10),DateReceived,120),7) mon, COUNT(*) rows_, SUM(Quantity) qty, SUM(Available) avail,
       SUM(CASE WHEN Available < Quantity THEN 1 ELSE 0 END) partly_used, SUM(CASE WHEN Available=0 THEN 1 ELSE 0 END) used_up
FROM Inventory WHERE ReferenceCode LIKE 'INVIN-%' GROUP BY LEFT(CONVERT(varchar(10),DateReceived,120),7) ORDER BY 1;
