/* ================================================================
   2026-10-02: STS FIFO receive — one row per line (multi-lot lines)
   ================================================================
   Bug (DEV PO 13721, 2026-10-02): a line taken from two lots (100 kg
   = 68.55 from lot 100 + 31.45 from lot 101) showed as TWO rows on the
   receive screen (HOFormsDevEx/ReceivedSTSBatchModeFIFO, rows from
   funcview_InventoryDeliveryFIFOForReceiving, one per FIFO lot). Both rows
   carry the line's barcode, so spu_PostSTSReceiveFromFIFO received the
   first (68.55) and skipped the second as "duplicate PONumber+Barcode";
   the receipt then booked the missing 31.45 kg as STS-SHORT (a loss).
   Everything else in the receive is per line (duplicate guard, branch
   stock row, DeliveryDetails.ActualQty, "not received" return), so only
   the list was wrong.

   1. funcview_InventoryDeliveryFIFOForReceiving: one row per line, qty =
      the line's live lots added up; source ReferenceCode / ShipmentNo /
      Branch from the line's largest lot. Same columns, so no exe change.
      Also matches f.DeliveryNo (it matched PO + SeqNo only).
   2. spu_PostSTSReceiveFromFIFO (text patch, exact anchors):
      - adds up rows sent for the same line (a screen opened before this
        fix still receives the whole line);
      - resets the per-line variables (DECLARE inside the loop kept the
        previous line's lot when a line had none);
      - source lot = the line's largest lot (was TOP 1 without ORDER BY),
        matched on DeliveryNo too.

   Backups: <name>_OLD_10022026110000. Re-run stops at the "already applied" check.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

PRINT 'Database: ' + DB_NAME();

IF OBJECT_ID('dbo.funcview_InventoryDeliveryFIFOForReceiving') IS NULL OR OBJECT_ID('dbo.spu_PostSTSReceiveFromFIFO', 'P') IS NULL
    THROW 59760, 'funcview_InventoryDeliveryFIFOForReceiving / spu_PostSTSReceiveFromFIFO not found.', 1;

IF CHARINDEX(N'2026-10-02: one row per line', OBJECT_DEFINITION(OBJECT_ID('dbo.spu_PostSTSReceiveFromFIFO'))) > 0
    THROW 59761, 'Already applied (spu_PostSTSReceiveFromFIFO carries the 2026-10-02 note).', 1;

IF OBJECT_ID('dbo.funcview_InventoryDeliveryFIFOForReceiving_OLD_10022026110000') IS NOT NULL
   OR OBJECT_ID('dbo.spu_PostSTSReceiveFromFIFO_OLD_10022026110000') IS NOT NULL
    THROW 59762, 'A backup named <name>_OLD_10022026110000 already exists.', 1;

-- the proc's replacements (each must match exactly once)
IF OBJECT_ID('tempdb..#P') IS NOT NULL DROP TABLE #P;
CREATE TABLE #P (Id INT IDENTITY PRIMARY KEY, OldText NVARCHAR(MAX), NewText NVARCHAR(MAX));
INSERT #P (OldText, NewText) VALUES
(N'SELECT SeqNo, DeliveryNo, ProductCode, Barcode, ActualQty, SellingPrice FROM @Lines;',
 N'SELECT SeqNo, DeliveryNo, ProductCode, Barcode, SUM(ActualQty), MAX(SellingPrice)   -- 2026-10-02: one row per line, even when a screen sends one row per lot
            FROM @Lines GROUP BY SeqNo, DeliveryNo, ProductCode, Barcode;'),
(N'@LineCost DECIMAL(10,2), @LineIsVat BIT, @ShipmentNo VARCHAR(10), @InvSeqNo int;',
 N'@LineCost DECIMAL(10,2), @LineIsVat BIT, @ShipmentNo VARCHAR(10), @InvSeqNo int;
            -- 2026-10-02: DECLARE inside the loop keeps the previous line''s values; reset them per line
            SELECT @SourceReferenceCode = NULL, @ProductName = NULL, @LineCost = NULL, @LineIsVat = NULL, @ShipmentNo = NULL, @InvSeqNo = NULL;'),
(N'ON f.DevDetSeqNo = dd.SeqNo AND f.PONumber = dd.PONumber AND f.isErrorCorrect = 0',
 N'ON f.DevDetSeqNo = dd.SeqNo AND f.PONumber = dd.PONumber AND f.DeliveryNo = dd.DeliveryNo AND f.isErrorCorrect = 0'),
(N'WHERE dd.SeqNo = @SeqNo AND dd.PONumber = @PONumber AND dd.DeliveryNo = @DeliveryNo;',
 N'WHERE dd.SeqNo = @SeqNo AND dd.PONumber = @PONumber AND dd.DeliveryNo = @DeliveryNo
            ORDER BY f.QtyDelivered DESC, f.SequenceReferenceNumber;   -- 2026-10-02: the line''s largest lot, same as the receive screen shows');

DECLARE @def NVARCHAR(MAX) = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.spu_PostSTSReceiveFromFIFO')), NCHAR(13) + NCHAR(10), NCHAR(10));

IF EXISTS (SELECT 1 FROM #P WHERE (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, OldText, N''))) / DATALENGTH(OldText) <> 1)
BEGIN
    SELECT OldText, (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, OldText, N''))) / DATALENGTH(OldText) AS Matches
    FROM #P WHERE (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, OldText, N''))) / DATALENGTH(OldText) <> 1;
    THROW 59763, 'spu_PostSTSReceiveFromFIFO text differs from the version this script was written for; nothing changed.', 1;
END

DECLARE @old NVARCHAR(MAX), @new NVARCHAR(MAX);
DECLARE rc CURSOR LOCAL FAST_FORWARD FOR SELECT OldText, NewText FROM #P ORDER BY Id;
OPEN rc; FETCH NEXT FROM rc INTO @old, @new;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @def = REPLACE(@def, @old, @new);
    FETCH NEXT FROM rc INTO @old, @new;
END
CLOSE rc; DEALLOCATE rc;

DECLARE @fn NVARCHAR(MAX) = N'
CREATE FUNCTION dbo.funcview_InventoryDeliveryFIFOForReceiving
(
    @PONumber VARCHAR(10)
)
RETURNS TABLE
AS
/*
    Rows for the STS FIFO receive screen (HOFormsDevEx/ReceivedSTSBatchModeFIFO):
    ONE ROW PER LINE still to receive (2026-10-02; it was one row per FIFO lot,
    so a line taken from two lots showed twice and the second row was skipped
    as a duplicate). QtyDelivered / ActualQty = the line''s live lots added up.
    Source* columns = the line''s largest lot (same lot spu_PostSTSReceiveFromFIFO
    stamps on the branch stock row).
    Callers: Orders/ReceivedSTS.cs -> ReceivedSTSBatchModeFIFO.
*/
RETURN
(
    SELECT
        dd.SeqNo,
        dd.DeliveryNo,
        dd.PONumber,
        dd.ReferenceNumber,
        dd.ProductNo,
        dd.ProductName,
        dd.BarcodeNo,
        q.QtyDelivered,
        q.QtyDelivered AS ActualQty,
        dd.Cost,
        dd.SellingPrice,
        dd.isVat,
        src.ReferenceCode AS SourceReferenceCode,
        src.ShipmentNo    AS SourceShipmentNo,
        src.Branch        AS SourceBranch
    FROM dbo.DeliveryDetails AS dd
    CROSS APPLY (SELECT CAST(SUM(f.QtyDelivered) AS DECIMAL(18,3)) AS QtyDelivered
                 FROM dbo.InventoryDeliveryFIFO AS f
                 WHERE f.DeliveryNo = dd.DeliveryNo AND f.PONumber = dd.PONumber
                   AND f.DevDetSeqNo = dd.SeqNo AND f.isErrorCorrect = 0) AS q
    CROSS APPLY (SELECT TOP (1) i.ReferenceCode, i.ShipmentNo, i.Branch
                 FROM dbo.InventoryDeliveryFIFO AS f
                 INNER JOIN dbo.Inventory AS i ON i.SequenceNumber = f.SequenceReferenceNumber
                 WHERE f.DeliveryNo = dd.DeliveryNo AND f.PONumber = dd.PONumber
                   AND f.DevDetSeqNo = dd.SeqNo AND f.isErrorCorrect = 0
                 ORDER BY f.QtyDelivered DESC, f.SequenceReferenceNumber) AS src
    WHERE dd.PONumber = @PONumber
      AND dd.isReturned = 0
      AND dd.isCancelled = 0
      AND q.QtyDelivered IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM dbo.ReceivedOrderDetails AS r
          WHERE r.PONumber = dd.PONumber AND r.Barcode = dd.BarcodeNo
      )
);';

BEGIN TRANSACTION;
    EXEC sp_rename 'dbo.funcview_InventoryDeliveryFIFOForReceiving', 'funcview_InventoryDeliveryFIFOForReceiving_OLD_10022026110000';
    EXEC (@fn);
    EXEC sp_rename 'dbo.spu_PostSTSReceiveFromFIFO', 'spu_PostSTSReceiveFromFIFO_OLD_10022026110000';
    EXEC (@def);
COMMIT TRANSACTION;

SELECT name, type_desc, CONVERT(VARCHAR(19), modify_date, 120) AS modified
FROM sys.objects
WHERE name LIKE 'funcview_InventoryDeliveryFIFOForReceiving%' OR name LIKE 'spu_PostSTSReceiveFromFIFO%'
ORDER BY name;
