/* ================================================================
   2026-10-02d: funcview_ForDeliveryDetails / funcview_ProcessOrderItemsSales
                one row per line, with the line's lot ReferenceCode
   ================================================================
   The user's 2026-10-02 edits (STAGING 14:14 / 14:43, DEV 15:10) fixed the
   duplicate rows: the "RT" versions joined InventoryDeliveryFIFO, so a line
   taken from two lots showed twice (and its amount twice). Their fix keeps
   one FIFO row per line (ROW_NUMBER ... rn = 1). Same idea here, plus:

   1. funcview_ProcessOrderItemsSales keeps BarcodeNo. The edited version
      dropped it, but Orders/AddBranchOrder.cs (Print Barcode / Print All)
      and Orders/AddBranchOrderSTS.cs (JFC: Cancel line @parmbarcode, Return
      by barcode, printing) read gridView2 "BarcodeNo" -> null reference.
   2. funcview_ForDeliveryDetails shows returned lines again (the edited
      version required a live FIFO row, and a return marks all of a line's
      rows corrected: STAGING 9 returned lines / 3 orders, e.g. PO 14055,
      vanished from Confirm Order, Client Show Items and PO for Approval).
   3. A line is never dropped for lack of a FIFO row: the ReferenceCode comes
      from OUTER APPLY (live lot first, same order as the user's version),
      matched on DeliveryNo too.
   Columns and their order are the user's versions (+ BarcodeNo in the
   process view). SellingPrice / TotalAmount stay FORMAT()-ed strings as
   before, because the screens bind them that way.

   Backups: <name>_OLD_10022026170000.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.funcview_ForDeliveryDetails_OLD_10022026170000') IS NOT NULL
   OR OBJECT_ID('dbo.funcview_ProcessOrderItemsSales_OLD_10022026170000') IS NOT NULL
    THROW 59870, 'Backups <name>_OLD_10022026170000 already exist (already applied?).', 1;
EXEC sp_rename 'dbo.funcview_ForDeliveryDetails', 'funcview_ForDeliveryDetails_OLD_10022026170000';
EXEC sp_rename 'dbo.funcview_ProcessOrderItemsSales', 'funcview_ProcessOrderItemsSales_OLD_10022026170000';
GO

CREATE FUNCTION dbo.funcview_ForDeliveryDetails
(
    @parmpono VARCHAR(10)
)
RETURNS TABLE
AS
/*
    Lines of a sales order for Confirm Order / Client Show Items / PO for Approval:
    one row per non-cancelled line, returned lines included (isReturned shows it),
    with the ReferenceCode of the line's lot (live lot first).
*/
RETURN
(
    SELECT dd.SeqNo, dd.ProductNo, dd.ProductName, lot.ReferenceCode,
           dd.QtyDelivered, dd.ActualQty,
           FORMAT(dd.SellingPrice, 'N', 'en-US')                AS SellingPrice,
           FORMAT(dd.ActualQty * dd.SellingPrice, 'N', 'en-US') AS TotalAmount,
           dd.ProcessedBy, dd.isCreditMemo, dd.isReturned
    FROM dbo.DeliveryDetails AS dd
    OUTER APPLY (SELECT TOP (1) i.ReferenceCode
                 FROM dbo.InventoryDeliveryFIFO AS f
                 INNER JOIN dbo.Inventory AS i ON i.SequenceNumber = f.SequenceReferenceNumber
                 WHERE f.PONumber = dd.PONumber AND f.DeliveryNo = dd.DeliveryNo AND f.DevDetSeqNo = dd.SeqNo
                 ORDER BY CASE WHEN f.isErrorCorrect = 0 THEN 0 ELSE 1 END, f.SequenceReferenceNumber) AS lot
    WHERE dd.PONumber = @parmpono
      AND dd.isCancelled = 0
);
GO

CREATE FUNCTION dbo.funcview_ProcessOrderItemsSales
(
    @parmpono VARCHAR(10)
)
RETURNS TABLE
AS
/*
    Lines being processed (delivery still PENDING) for Orders/AddBranchOrder and,
    for JFC, Orders/AddBranchOrderSTS: one row per active line, with BarcodeNo
    (both forms print it, and the STS form cancels / returns by it) and the
    ReferenceCode of the line's live lot.
*/
RETURN
(
    SELECT dd.SeqNo, dd.ProductNo, dd.ProductName, dd.BarcodeNo, lot.ReferenceCode,
           dd.QtyDelivered, dd.ActualQty,
           FORMAT(dd.SellingPrice, 'N', 'en-US')                AS SellingPrice,
           FORMAT(dd.ActualQty * dd.SellingPrice, 'N', 'en-US') AS TotalAmount,
           dd.ProcessedBy, dd.isCreditMemo, dd.isReturned
    FROM dbo.DeliveryDetails AS dd
    OUTER APPLY (SELECT TOP (1) i.ReferenceCode
                 FROM dbo.InventoryDeliveryFIFO AS f
                 INNER JOIN dbo.Inventory AS i ON i.SequenceNumber = f.SequenceReferenceNumber
                 WHERE f.PONumber = dd.PONumber AND f.DeliveryNo = dd.DeliveryNo AND f.DevDetSeqNo = dd.SeqNo
                   AND f.isErrorCorrect = 0
                 ORDER BY f.SequenceReferenceNumber) AS lot
    WHERE dd.PONumber = @parmpono
      AND dd.isCancelled = 0
      AND dd.isReturned = 0
      AND EXISTS (SELECT 1 FROM dbo.DeliverySummary AS c
                  WHERE c.PONumber = dd.PONumber AND c.DeliveryNo = dd.DeliveryNo AND c.Status = 'PENDING')
);
GO

SELECT name, CONVERT(VARCHAR(19), modify_date, 120) AS modified
FROM sys.objects
WHERE name LIKE 'funcview_ForDeliveryDetails%' OR name LIKE 'funcview_ProcessOrderItemsSales%'
ORDER BY name;
