
CREATE PROCEDURE dbo.spview_SalesInvoiceJFC
    @parmpono VARCHAR(10)
AS
/*
    Sales invoice lines for a sales order (JFC). One row per product, price,
    VAT flag and lot ReferenceCode:
      Cnt       = lines (scans) in the row
      Quantity  = the qty taken from those lots (a line split over two
                  ReferenceCodes appears in two rows that add up to the line)
      Amount    = Quantity x price, less the product's discount once (first row)
    Callers: Orders/POForApproval.cs (printSalesInvoice), HOForms/ViewForDeliveryDetails.cs,
             POS/POSConfirmPaymentResto.cs.
    2026-10-03b: qty came from the line once per lot (doubled for a 2-lot line).
*/
BEGIN
    SET NOCOUNT OFF;

    WITH Lots AS (
        SELECT a.SeqNo,
               a.ProductNo,
               a.ProductName,
               a.SellingPrice,
               a.isVat,
               ISNULL(c.ReferenceCode, ' ')          AS ReferenceCode,
               CAST(b.QtyDelivered AS DECIMAL(18,3)) AS Qty
        FROM dbo.DeliveryDetails AS a
        INNER JOIN dbo.InventoryDeliveryFIFO AS b
                ON a.PONumber = b.PONumber
               AND a.DeliveryNo = b.DeliveryNo
               AND a.ProductNo = b.ProductNo
               AND a.SeqNo = b.DevDetSeqNo
               AND b.isErrorCorrect = 0
        LEFT OUTER JOIN dbo.Inventory AS c
                ON b.SequenceReferenceNumber = c.SequenceNumber
        WHERE a.PONumber = @parmpono
          AND a.isCancelled = 0
    ),
    Disc AS (
        SELECT ProductCode, MAX(DiscountAmount) AS DiscountAmount, MAX(Percentage) AS Percentage
        FROM dbo.SalesOrderDiscounts
        WHERE PONumber = @parmpono
        GROUP BY ProductCode
    ),
    G AS (
        SELECT l.ProductNo,
               l.ProductName,
               l.SellingPrice,
               l.isVat,
               l.ReferenceCode,
               COUNT(DISTINCT l.SeqNo)                       AS Cnt,
               SUM(l.Qty)                                    AS Quantity,
               SUM(l.Qty * ISNULL(l.SellingPrice, 0))        AS Gross,
               ROW_NUMBER() OVER (PARTITION BY l.ProductNo
                                  ORDER BY l.ReferenceCode, l.SellingPrice, l.isVat) AS ProdRow
        FROM Lots AS l
        GROUP BY l.ProductNo, l.ProductName, l.SellingPrice, l.isVat, l.ReferenceCode
    )
    SELECT g.Cnt,
           g.Quantity,
           'Kg' AS Unit,
           CASE WHEN g.ProdRow = 1 AND ISNULL(d.DiscountAmount, 0) <> 0
                    THEN '(' + g.ReferenceCode + ') ' + g.ProductName
                         + ' (Less Discount @' + CAST(d.Percentage AS VARCHAR(10)) + '%)'
                ELSE '(' + g.ReferenceCode + ') ' + g.ProductName
           END AS ProductName,
           FORMAT(g.SellingPrice, 'N', 'en-US') AS Price,
           FORMAT(g.Gross - CASE WHEN g.ProdRow = 1 THEN ISNULL(d.DiscountAmount, 0) ELSE 0 END, 'N', 'en-US') AS Amount,
           g.isVat
    FROM G AS g
    LEFT OUTER JOIN Disc AS d
            ON d.ProductCode = g.ProductNo
    ORDER BY g.ProductName, g.ReferenceCode;
END
