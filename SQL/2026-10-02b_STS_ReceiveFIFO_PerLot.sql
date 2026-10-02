/* ================================================================
   2026-10-02b: STS FIFO receive — receipt and branch stock per LOT
   ================================================================
   Needs 2026-10-02_STS_ReceiveFIFO_OneRowPerLine.sql (the receive screen
   shows one row per line).

   User rule (2026-10-02, DEV PO 13727): a line shipped from several lots
   (30 kg = 17.52 from lot 12 / shipment 00012 / ref ...24064 + 12.48 from
   lot 13 / shipment 00013 / ref ...24176) must be received the same way the
   stock ledger shipped it: one ReceivedOrderDetails row and one branch
   Inventory row PER LOT, each with that lot's ReferenceCode, ShipmentNo and
   cost, so the branch can trace (and later deduct) by ReferenceCode /
   ShipmentNo. It wrote one row per line under the largest lot.

   spu_PostSTSReceiveFromFIFO, per line (rows sent for the same line are
   added up first):
     - skip if the line was already received (PONumber + Barcode, as before);
     - the received qty fills the line's live lots in dispatch order
       (InventoryDeliveryFIFO.SequenceNumber); a short receipt comes off the
       last lot(s), an over receipt goes on the last lot;
     - per lot with qty > 0: branch Inventory row (ShipmentNo / ReferenceCode
       / cost of the source lot, the line's barcode), ReceivedOrderDetails row
       (ReferenceCode of the lot, lot cost), InventoryLedger row
       'STS RCVD ITEM PO#<po>' (QtyIN at the branch, like the other receive
       screen writes);
     - DeliveryDetails.ActualQty = the line's received qty.
   Received cost is now exact per lot (no average-cost rounding).
   A line whose branch row was pre-created by the (unused) Dispatch Per
   Barcode module keeps the old single-row update.

   Same parameters and result set; no exe change.
   Backup: spu_PostSTSReceiveFromFIFO_OLD_10022026140000.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.spu_PostSTSReceiveFromFIFO_OLD_10022026140000', 'P') IS NOT NULL
    THROW 59770, 'Backup spu_PostSTSReceiveFromFIFO_OLD_10022026140000 already exists (already applied?).', 1;
IF CHARINDEX(N'2026-10-02: one row per line', OBJECT_DEFINITION(OBJECT_ID('dbo.spu_PostSTSReceiveFromFIFO'))) = 0
    THROW 59771, 'Run 2026-10-02_STS_ReceiveFIFO_OneRowPerLine.sql first.', 1;
EXEC sp_rename 'dbo.spu_PostSTSReceiveFromFIFO', 'spu_PostSTSReceiveFromFIFO_OLD_10022026140000';
GO

CREATE PROCEDURE dbo.spu_PostSTSReceiveFromFIFO
    @PONumber   VARCHAR(10),
    @BranchCode VARCHAR(10),
    @ReceivedBy VARCHAR(50),
    @Lines      dbo.tt_STSReceiveFIFOLines READONLY
AS
/*
    Receives the checked STS lines into the branch, per source LOT
    (2026-10-02b): one ReceivedOrderDetails row, one branch Inventory row and
    one InventoryLedger row per lot the line was shipped from, each carrying
    that lot's ReferenceCode / ShipmentNo / cost. The line's received qty fills
    its lots in dispatch order; a shortage comes off the last lot(s).

    Returns: one result set -- (SeqNo, Barcode, Reason) for lines skipped
             (already received, or no live lot).
    Callers: HOFormsDevEx/ReceivedSTSBatchModeFIFO.cs (first of its 3 calls;
             sp_ConfirmBranchRecievedOrderJFC then posts IT-BR / STS-SHORT).
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @SkippedLines TABLE (SeqNo INT, Barcode VARCHAR(120), Reason VARCHAR(200));

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM @Lines)
        BEGIN
            SELECT SeqNo, Barcode, Reason FROM @SkippedLines;
            RETURN;
        END

        BEGIN TRANSACTION;

        -- the per-PO lock every STS writer shares (2026-10-01f)
        DECLARE @LockResult INT, @RcvLockRes NVARCHAR(255) = N'STSTRANSIT:' + @PONumber;
        EXEC @LockResult = sp_getapplock
            @Resource = @RcvLockRes, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 30000;
        IF @LockResult < 0
            THROW 58170, 'Could not acquire a lock on this delivery -- another receive is already in progress. Please try again.', 1;

        DECLARE @SeqNo INT, @DeliveryNo VARCHAR(20), @ProductCode VARCHAR(50),
                @Barcode VARCHAR(120), @ActualQty DECIMAL(18,3), @SellingPrice DECIMAL(18,4),
                @ProductName VARCHAR(50), @LineIsVat BIT;

        DECLARE @Lot TABLE (
            FifoSeq INT PRIMARY KEY, LotSeq INT, ShipmentNo VARCHAR(10), ReferenceCode VARCHAR(20),
            LotQty DECIMAL(18,3), LotCost DECIMAL(18,4), RcvQty DECIMAL(18,3), IsLast BIT);

        DECLARE line_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT SeqNo, DeliveryNo, ProductCode, Barcode, SUM(ActualQty), MAX(SellingPrice)
            FROM @Lines GROUP BY SeqNo, DeliveryNo, ProductCode, Barcode;

        OPEN line_cur;
        FETCH NEXT FROM line_cur INTO @SeqNo, @DeliveryNo, @ProductCode, @Barcode, @ActualQty, @SellingPrice;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SELECT @ProductName = NULL, @LineIsVat = NULL;
            DELETE FROM @Lot;

            -- already received (PONumber + Barcode; ReceivedOrderDetails has no DeliveryNo / line number)
            IF EXISTS (SELECT 1 FROM dbo.ReceivedOrderDetails WHERE PONumber = @PONumber AND Barcode = @Barcode)
            BEGIN
                INSERT INTO @SkippedLines (SeqNo, Barcode, Reason)
                VALUES (@SeqNo, @Barcode, 'Already received (duplicate PONumber+Barcode).');
                FETCH NEXT FROM line_cur INTO @SeqNo, @DeliveryNo, @ProductCode, @Barcode, @ActualQty, @SellingPrice;
                CONTINUE;
            END

            SELECT @ProductName = dd.ProductName, @LineIsVat = ISNULL(dd.isVat, 0)
            FROM dbo.DeliveryDetails AS dd
            WHERE dd.SeqNo = @SeqNo AND dd.PONumber = @PONumber AND dd.DeliveryNo = @DeliveryNo;

            -- the line's live lots, in dispatch order, with the received qty spread over them
            ;WITH F AS (
                SELECT f.SequenceNumber AS FifoSeq, f.SequenceReferenceNumber AS LotSeq,
                       src.ShipmentNo, src.ReferenceCode,
                       CAST(f.QtyDelivered AS DECIMAL(18,3)) AS LotQty, CAST(f.Cost AS DECIMAL(18,4)) AS LotCost,
                       SUM(CAST(f.QtyDelivered AS DECIMAL(18,3))) OVER (ORDER BY f.SequenceNumber ROWS UNBOUNDED PRECEDING) AS RunQty,
                       ROW_NUMBER() OVER (ORDER BY f.SequenceNumber DESC) AS RevNo
                FROM dbo.InventoryDeliveryFIFO AS f
                INNER JOIN dbo.Inventory AS src ON src.SequenceNumber = f.SequenceReferenceNumber
                WHERE f.DeliveryNo = @DeliveryNo AND f.PONumber = @PONumber AND f.DevDetSeqNo = @SeqNo AND f.isErrorCorrect = 0)
            INSERT INTO @Lot (FifoSeq, LotSeq, ShipmentNo, ReferenceCode, LotQty, LotCost, RcvQty, IsLast)
            SELECT FifoSeq, LotSeq, ShipmentNo, ReferenceCode, LotQty, LotCost,
                   CASE WHEN RunQty <= @ActualQty THEN LotQty
                        WHEN RunQty - LotQty < @ActualQty THEN @ActualQty - (RunQty - LotQty)
                        ELSE 0 END,
                   CASE WHEN RevNo = 1 THEN 1 ELSE 0 END
            FROM F;

            IF NOT EXISTS (SELECT 1 FROM @Lot)
            BEGIN
                INSERT INTO @SkippedLines (SeqNo, Barcode, Reason)
                VALUES (@SeqNo, @Barcode, 'No source FIFO lot found for this line -- cannot attribute ReferenceCode.');
                FETCH NEXT FROM line_cur INTO @SeqNo, @DeliveryNo, @ProductCode, @Barcode, @ActualQty, @SellingPrice;
                CONTINUE;
            END

            -- over receipt: the extra goes on the last lot
            UPDATE @Lot SET RcvQty = RcvQty + (@ActualQty - (SELECT SUM(LotQty) FROM @Lot))
            WHERE IsLast = 1 AND @ActualQty > (SELECT SUM(LotQty) FROM @Lot);

            -- a branch row pre-created by the (unused) Dispatch Per Barcode module: old single-row update
            IF EXISTS (SELECT 1 FROM dbo.Inventory WHERE Branch = @BranchCode AND ShipmentNo = @DeliveryNo
                         AND Product = @ProductCode AND Barcode = @Barcode)
            BEGIN
                UPDATE dst
                SET dst.ReferenceCode    = (SELECT TOP (1) ReferenceCode FROM @Lot ORDER BY LotQty DESC, FifoSeq),
                    dst.Available        = ISNULL(dst.Available, 0) + (@ActualQty - ISNULL(dst.Quantity, 0)),
                    dst.Quantity         = @ActualQty,
                    dst.LastMovementDate = GETDATE()
                FROM dbo.Inventory AS dst WITH (UPDLOCK, ROWLOCK)
                WHERE dst.Branch = @BranchCode AND dst.ShipmentNo = @DeliveryNo
                  AND dst.Product = @ProductCode AND dst.Barcode = @Barcode;
            END
            ELSE
            BEGIN
                INSERT INTO dbo.Inventory
                    (Branch, ShipmentNo, PalletNo, BatchCode, DateReceived, ExpiryDate, Product, Description, Barcode,
                     TipWeight, Quantity, Cost, Available, QtyBigBlue, IsStock, IsVat, IsWarehouse, ReferenceCode,
                     LastMovementDate, isProcess, isSource, isConversion)
                SELECT @BranchCode, l.ShipmentNo, 0, 0, GETDATE(), NULL, @ProductCode, @ProductName, @Barcode,
                       l.RcvQty, l.RcvQty, ROUND(l.LotCost, 2), l.RcvQty, 0, 1, @LineIsVat, 1, l.ReferenceCode,
                       GETDATE(), 0, 0, 0
                FROM @Lot AS l
                WHERE l.RcvQty > 0
                ORDER BY l.FifoSeq;
            END

            -- receipt rows, one per lot (SeqNo = per-PO MAX + 1, safe under the lock)
            INSERT INTO dbo.ReceivedOrderDetails
                (SeqNo, PONumber, ProductCode, ProductName, Barcode, Qty, Cost, SellingPrice, IsVat, ReferenceCode)
            SELECT ISNULL((SELECT MAX(SeqNo) FROM dbo.ReceivedOrderDetails WHERE PONumber = @PONumber), 0)
                       + ROW_NUMBER() OVER (ORDER BY l.FifoSeq),
                   @PONumber, @ProductCode, @ProductName, @Barcode, l.RcvQty,
                   ROUND(l.LotCost, 2), ISNULL(@SellingPrice, 0), @LineIsVat, l.ReferenceCode
            FROM @Lot AS l
            WHERE l.RcvQty > 0;

            -- branch stock ledger, one row per lot (same shape as the other receive screen)
            INSERT INTO dbo.InventoryLedger
                (SequenceRefNum, OriginBranch, DestinationBranch, DateProcessed, Product, Description,
                 BegQty, QtyIN, QtyOut, EndQty, Cost, Remarks, ProcessedBy)
            SELECT l.LotSeq, @BranchCode, @BranchCode, GETDATE(), @ProductCode, @ProductName,
                   0, l.RcvQty, 0, l.RcvQty, l.LotCost, 'STS RCVD ITEM PO#' + @PONumber, @ReceivedBy
            FROM @Lot AS l
            WHERE l.RcvQty > 0;

            UPDATE dbo.DeliveryDetails
            SET ActualQty = @ActualQty
            WHERE SeqNo = @SeqNo AND PONumber = @PONumber AND DeliveryNo = @DeliveryNo;

            FETCH NEXT FROM line_cur INTO @SeqNo, @DeliveryNo, @ProductCode, @Barcode, @ActualQty, @SellingPrice;
        END

        CLOSE line_cur;
        DEALLOCATE line_cur;

        COMMIT TRANSACTION;

        SELECT SeqNo, Barcode, Reason FROM @SkippedLines;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'line_cur') >= 0
            CLOSE line_cur;
        IF CURSOR_STATUS('local', 'line_cur') = -1
            DEALLOCATE line_cur;
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

SELECT name, CONVERT(VARCHAR(19), modify_date, 120) AS modified
FROM sys.objects WHERE name LIKE 'spu_PostSTSReceiveFromFIFO%' ORDER BY name;
