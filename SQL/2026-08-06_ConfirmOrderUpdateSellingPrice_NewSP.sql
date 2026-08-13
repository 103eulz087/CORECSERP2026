SET NOCOUNT ON;
PRINT '=== sp_UpdateDeliverySellingPrice: new SP for ConfirmOrderUpdateSPriceDevEx.cs ===';
GO
IF OBJECT_ID('dbo.sp_UpdateDeliverySellingPrice') IS NOT NULL
    DROP PROCEDURE dbo.sp_UpdateDeliverySellingPrice;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- =============================================
-- Author:      2026-08-06
-- Description: Updates the selling price for a delivery line (or every line
--              on the PO sharing the same product, when @parmapplytoall=1)
--              while the order is being reviewed on the Confirm Order screen
--              -- i.e. BEFORE sp_ConfirmOrder has posted anything to GL.
--              Called from HOFormsDevEx/ConfirmOrderUpdateSPriceDevEx.cs,
--              invoked via ConfirmOrderDevEx.cs's "Update Selling Price"
--              context menu (gridView2).
--
-- WHY: by the time a PO reaches this screen, the selling price is already
--      duplicated across three tables -- DeliveryDetails (populated at
--      warehouse processing), PurchaseOrderDetails (the original order
--      line), and InventoryDeliveryFIFO (the FIFO allocation for this
--      delivery). The prior C# only updated DeliveryDetails via
--      Database.ExecuteQuery, leaving PurchaseOrderDetails and
--      InventoryDeliveryFIFO holding the stale price. This SP updates all
--      three together, in one transaction.
--
-- TRAP: refuses the update entirely (no partial apply) if ANY targeted
--       DeliveryDetails line already has isCreditMemo=1 or isReturned=1.
--       Those lines already have downstream records (CreditMemo /
--       ReturnedOrderDetails, and -- once DELIVERED -- GL tickets) computed
--       against the price as it stood when they were processed; changing
--       DeliveryDetails.SellingPrice afterward would silently desynchronize
--       those records from the price actually billed/reversed.
-- =============================================
CREATE PROCEDURE [dbo].[sp_UpdateDeliverySellingPrice]
    @parmpono          varchar(10),
    @parmseqno         decimal(10,0) = NULL,
    @parmprodname      varchar(100),
    @parmsellingprice  decimal(12,2),
    @parmapplytoall    bit,
    @parmuser          varchar(50)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF @parmapplytoall = 0 AND @parmseqno IS NULL
            THROW 59201, 'SeqNo is required when not applying to all matching lines.', 1;

        IF @parmsellingprice IS NULL OR @parmsellingprice <= 0
            THROW 59202, 'Selling price must be greater than zero.', 1;

        -- ── Scope: the exact line, or every line on this PO with the same product ─
        SELECT SeqNo, ProductNo, isCreditMemo, isReturned
        INTO #TargetLines
        FROM DeliveryDetails
        WHERE PONumber = @parmpono
          AND (
                (@parmapplytoall = 1 AND ProductName = @parmprodname)
             OR (@parmapplytoall = 0 AND SeqNo = @parmseqno)
              );

        IF NOT EXISTS (SELECT 1 FROM #TargetLines)
            THROW 59203, 'No matching delivery line(s) found for this PO.', 1;

        -- ── Trap: block outright if any targeted line already has an adjustment ─
        IF EXISTS (SELECT 1 FROM #TargetLines WHERE ISNULL(isCreditMemo,0)=1 OR ISNULL(isReturned,0)=1)
        BEGIN
            DECLARE @BlockedSeq VARCHAR(20);
            SELECT TOP 1 @BlockedSeq = CAST(SeqNo AS VARCHAR(20))
            FROM #TargetLines WHERE ISNULL(isCreditMemo,0)=1 OR ISNULL(isReturned,0)=1;

            DECLARE @BlockMsg NVARCHAR(400) =
                'Cannot update Selling Price: line SeqNo ' + @BlockedSeq + ' already has a Credit Memo or has been Returned.';
            THROW 59204, @BlockMsg, 1;
        END;

        -- ── DeliveryDetails (the line(s) themselves) ────────────────────────
        UPDATE dd
           SET dd.SellingPrice = @parmsellingprice
        FROM DeliveryDetails dd
        JOIN #TargetLines t ON dd.PONumber = @parmpono AND dd.SeqNo = t.SeqNo;

        -- ── PurchaseOrderDetails (the original order line -- matched by
        -- product, not SeqNo: PurchaseOrderDetails.SeqNo is a different
        -- numbering domain than DeliveryDetails.SeqNo) ──────────────────────
        UPDATE pod
           SET pod.SellingPrice = @parmsellingprice
        FROM PurchaseOrderDetails pod
        WHERE pod.PONumber = @parmpono
          AND pod.ProductCode IN (SELECT DISTINCT ProductNo FROM #TargetLines);

        -- ── InventoryDeliveryFIFO (the FIFO allocation for this delivery) ───
        UPDATE fifo
           SET fifo.SellingPrice = @parmsellingprice,
               fifo.TotalAmount  = fifo.QtyDelivered * @parmsellingprice
        FROM InventoryDeliveryFIFO fifo
        JOIN #TargetLines t ON fifo.PONumber = @parmpono AND fifo.DevDetSeqNo = t.SeqNo;

        DECLARE @branchcode VARCHAR(5);
        SELECT @branchcode = BranchCode FROM PurchaseOrderSummary WHERE PONumber = @parmpono;

        INSERT INTO HistoryLogs
        VALUES (
            @parmuser, GETDATE(),
            'UPDATED SELLING PRICE PO#: ' + @parmpono + ' Product: ' + @parmprodname
            + ' NewPrice: ' + CAST(@parmsellingprice AS VARCHAR(20))
            + CASE WHEN @parmapplytoall = 1
                   THEN ' (applied to all matching lines)'
                   ELSE ' (SeqNo ' + CAST(@parmseqno AS VARCHAR(20)) + ')' END,
            @branchcode
        );

        DROP TABLE IF EXISTS #TargetLines;
        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        DROP TABLE IF EXISTS #TargetLines;

        DECLARE @EMsg  NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ESev  INT            = ERROR_SEVERITY();
        DECLARE @ESt   INT            = ERROR_STATE();
        DECLARE @ELine INT            = ERROR_LINE();
        DECLARE @EProc NVARCHAR(128)  = ISNULL(ERROR_PROCEDURE(), 'sp_UpdateDeliverySellingPrice');
        RAISERROR('Error in %s (line %d): %s', @ESev, @ESt, @EProc, @ELine, @EMsg);
    END CATCH
END
GO
PRINT 'DEPLOYMENT COMPLETE: sp_UpdateDeliverySellingPrice created.';
