/* ================================================================
   2026-10-03b: Sales Invoice view (JFC) -- qty / amount no longer multiplied by
                the number of lots a line was taken from
   ================================================================
   spview_SalesInvoiceJFC (Orders/POForApproval.cs printSalesInvoice -- For Delivery
   and Delivered tabs; HOForms/ViewForDeliveryDetails.cs; POS/POSConfirmPaymentResto.cs)
   joined each DeliveryDetails line to its InventoryDeliveryFIFO rows (one per lot)
   and then added up the LINE's QtyDelivered: a line taken from 2 lots showed twice
   its qty and amount, from 7 lots 7 times (STAGING PO 14196: 102 kg shown as 714).
   Display / print only -- the posted sale (DeliveryDetails, tickets, invoice
   balance) is not affected.

   Now: each live lot row contributes ITS OWN qty, so a line split over two
   ReferenceCodes shows two rows that add up to the line. Same columns as before
   (Cnt, Quantity, Unit, ProductName, Price, Amount, isVat).
   Also: a product's SalesOrderDiscounts amount was subtracted once per
   ReferenceCode row; it is now subtracted once per product (on its first row,
   which carries the "Less Discount" label).

   No parameter change; works with the current exe. Backup
   spview_SalesInvoiceJFC_OLD_10032026160000. One transaction.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

DECLARE @pre NVARCHAR(200) =
    CASE WHEN OBJECT_ID('dbo.spview_SalesInvoiceJFC') IS NULL
              THEN N'dbo.spview_SalesInvoiceJFC not found.'
         WHEN OBJECT_ID('dbo.spview_SalesInvoiceJFC_OLD_10032026160000') IS NOT NULL
              THEN N'Already applied (backup spview_SalesInvoiceJFC_OLD_10032026160000 exists).' END;
IF @pre IS NOT NULL
BEGIN
    RAISERROR(@pre, 16, 1);
    SET NOEXEC ON;
    RETURN;
END
BEGIN TRANSACTION;
EXEC sp_rename 'dbo.spview_SalesInvoiceJFC', 'spview_SalesInvoiceJFC_OLD_10032026160000';
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
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
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
COMMIT TRANSACTION;
GO

SET NOEXEC OFF;
IF OBJECT_ID('dbo.spview_SalesInvoiceJFC_OLD_10032026160000') IS NULL
    PRINT 'NOT APPLIED -- see the first error above; nothing was changed.';
ELSE
    PRINT 'Applied.';
