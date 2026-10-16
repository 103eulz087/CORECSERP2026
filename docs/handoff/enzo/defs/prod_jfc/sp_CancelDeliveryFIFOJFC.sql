CREATE PROCEDURE dbo.sp_CancelDeliveryFIFOJFC
    @parmdevno varchar(20),
    @parmrefno varchar(10),
    @parmpono varchar(10),
    @parmprodno varchar(20),
    @parmqty decimal(18,3),
    @parmbranchcode varchar(10),
    @parmorigin varchar(10),
    @preparedby varchar(30),
    @parmdevseqno int
AS
/*
    Cancels one delivery line before confirm and puts back EVERY lot its scan
    consumed (InventoryDeliveryFIFO rows of DeliveryNo + PONumber + line),
    one InventoryLedger row per lot. Refuses when no active lot rows are found
    (the old version marked the line cancelled and restored nothing) and when
    the line is already DELIVERED (use Return instead).
    Callers: Orders/AddBranchOrder.cs (sales order), sp_ReverseSTSInventoryTransfer (STS).
    Same parameters as before.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @TranCounter INT = @@TRANCOUNT;
    IF @TranCounter > 0 SAVE TRANSACTION CancelDeliverySave; ELSE BEGIN TRANSACTION;
    EXEC dbo.sp_SOOrder_Lock @PONumber = @parmpono;   -- 2026-10-02c: the per-order lock every Sales Order writer shares
    BEGIN TRY
        IF EXISTS (SELECT 1 FROM dbo.DeliveryDetails
                   WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono AND SeqNo = @parmdevseqno AND Status = 'DELIVERED')
            THROW 59421, 'This line is already confirmed (DELIVERED). Use Return instead of Cancel.', 1;

        DECLARE @Lots TABLE (FifoSeq BIGINT PRIMARY KEY, Lot BIGINT, Qty DECIMAL(18,3), Cost DECIMAL(18,4), Descr VARCHAR(400));
        INSERT INTO @Lots (FifoSeq, Lot, Qty, Cost, Descr)
        SELECT f.SequenceNumber, f.SequenceReferenceNumber, ISNULL(f.QtyDelivered, 0), ISNULL(f.Cost, 0), f.Description
        FROM dbo.InventoryDeliveryFIFO AS f WITH (UPDLOCK, ROWLOCK)
        WHERE f.DeliveryNo = @parmdevno
          AND f.PONumber = @parmpono
          AND f.BranchCode = @parmbranchcode
          AND f.ProductNo = @parmprodno
          AND f.DevDetSeqNo = @parmdevseqno
          AND f.isErrorCorrect = 0;

        IF NOT EXISTS (SELECT 1 FROM @Lots)
        BEGIN
            DECLARE @NoLotMsg NVARCHAR(400) = N'Nothing to restore for PO ' + @parmpono + N' line ' + CAST(@parmdevseqno AS NVARCHAR(10))
                + N' (delivery ' + @parmdevno + N', branch ' + @parmbranchcode + N', product ' + @parmprodno
                + N'): no active FIFO rows. The line was not cancelled. Check the branch passed in.';
            THROW 59422, @NoLotMsg, 1;
        END

        IF EXISTS (SELECT 1 FROM @Lots l WHERE NOT EXISTS (SELECT 1 FROM dbo.Inventory i WHERE i.SequenceNumber = l.Lot))
            THROW 59423, 'A lot this line was taken from no longer exists in Inventory. Nothing was cancelled.', 1;

        -- ledger first (needs the balance before the update), one row per lot
        INSERT INTO dbo.InventoryLedger
            (SequenceRefNum, OriginBranch, DestinationBranch, DateProcessed, Product,
             Description, BegQty, QtyIn, QtyOut, EndQty, Cost, Remarks, ProcessedBy)
        SELECT l.Lot, @parmorigin, @parmbranchcode, GETDATE(), @parmprodno,
               l.Descr, ISNULL(i.Available, 0), l.Qty, 0, ISNULL(i.Available, 0) + l.Qty, l.Cost,
               'STS CANCEL ITEM PO#' + @parmpono, @preparedby
        FROM (SELECT Lot, SUM(Qty) AS Qty, MAX(Cost) AS Cost, MAX(Descr) AS Descr FROM @Lots GROUP BY Lot) AS l
        LEFT JOIN dbo.Inventory AS i WITH (UPDLOCK, ROWLOCK) ON i.SequenceNumber = l.Lot;

        UPDATE i
        SET i.Available = ISNULL(i.Available, 0) + l.Qty,
            i.IsStock = 1
        FROM dbo.Inventory AS i
        INNER JOIN (SELECT Lot, SUM(Qty) AS Qty FROM @Lots GROUP BY Lot) AS l ON l.Lot = i.SequenceNumber;

        UPDATE f SET f.isErrorCorrect = 1
        FROM dbo.InventoryDeliveryFIFO AS f
        INNER JOIN @Lots AS l ON l.FifoSeq = f.SequenceNumber;

        UPDATE dbo.DeliveryDetails
        SET isCancelled = 1, DateTimeUpdated = GETDATE()
        WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono AND SeqNo = @parmdevseqno;

        UPDATE dbo.DeliverySummary
        SET TotalItem = (SELECT ISNULL(COUNT(*),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono),
            TotalQtyDelivered = (SELECT ISNULL(SUM(QtyDelivered),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isCancelled = 0 AND isReturned = 0),
            TotalItemSold = (SELECT ISNULL(COUNT(*),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isCancelled = 0 AND isReturned = 0),
            TotalItemReturned = (SELECT ISNULL(COUNT(*),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isReturned = 1),
            Status = CASE WHEN Status = 'FOR DELIVERY' THEN 'FOR DELIVERY' ELSE 'PENDING' END
        WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono;

        IF @TranCounter = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @TranCounter = 0 BEGIN IF XACT_STATE() <> 0 ROLLBACK TRANSACTION; END
        ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION CancelDeliverySave;
        THROW;
    END CATCH
END
