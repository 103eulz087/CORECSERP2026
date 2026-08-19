SET NOCOUNT ON;
PRINT '=== sp_ConfirmBranchOrderSTS: guard against confirming an empty delivery ===';
GO

-- =============================================
-- BUG: Confirming a branch STS delivery order that has zero line items in
-- DeliveryDetails (e.g. Save/F10 hit with nothing scanned -- @parmbarcode=''
-- in the repro that surfaced this) makes:
--     SELECT @totalitem = COUNT(*), @totalqtydelivered = SUM(QtyDelivered)
--     FROM DeliveryDetails WHERE DeliveryNo=@parmdevno AND PONumber=@parmpono ...
-- return @totalqtydelivered = NULL (SUM over zero rows), which then gets
-- inserted straight into DeliverySummary.TotalQtyDelivered -- a NOT NULL
-- column -- raising:
--     Msg 515: Cannot insert the value NULL into column
--     'TotalQtyDelivered', table 'dbo.DeliverySummary'; column does not
--     allow nulls.
-- Confirmed live via repro (rolled back, nothing committed) with
-- @parmdevno='5244', @parmpono='4440' -- zero matching DeliveryDetails rows.
--
-- FIX (two layers, same pattern already used elsewhere in this SP for
-- @overalltotalcostnonvat/@overalltotalcostwithvat):
--   1. Early validation -- reject confirmation up front with a clear
--      message if the delivery has no line items at all, instead of
--      failing deep inside a NOT NULL insert with a cryptic constraint
--      error. Placed before any FIFO/costing work runs.
--   2. ISNULL(...,0) defense-in-depth wrap on @totalitem/@totalqtydelivered
--      right after the aggregate, in case this SP is ever reached with an
--      empty set through some other path.
-- Everything else in the SP is unchanged from the current live version.
-- =============================================

IF OBJECT_ID('dbo.sp_ConfirmBranchOrderSTS_OLD_08172026114208', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.sp_ConfirmBranchOrderSTS', 'P') IS NOT NULL
        DROP PROCEDURE dbo.sp_ConfirmBranchOrderSTS;
END
ELSE IF OBJECT_ID('dbo.sp_ConfirmBranchOrderSTS', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.sp_ConfirmBranchOrderSTS', 'sp_ConfirmBranchOrderSTS_OLD_08172026114208';
END
GO

CREATE PROCEDURE [dbo].[sp_ConfirmBranchOrderSTS]
(
    @parmdevno           VARCHAR(20),
    @parmrefno           VARCHAR(10),
    @parmeffectivitydate DATE,
    @parmpono            VARCHAR(10),
    @parmbarcode         VARCHAR(50),
    @parmbranchcode      VARCHAR(10),
    @parmorigin          VARCHAR(10), -- not used
    @preparedby          VARCHAR(30)
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @username VARCHAR(50);
        SELECT @username = dbo.func_getUsername(@preparedby);

        -- ── Empty-delivery guard: reject up front rather than blowing up
        --    later on a NULL SUM() inserted into a NOT NULL column. ──────
        IF NOT EXISTS (
            SELECT 1 FROM DeliveryDetails
            WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono
              AND isReturned = 0 AND isCancelled = 0
        )
            THROW 58161, 'Cannot confirm: no line items found for this delivery. Add at least one product before confirming.', 1;

        -- ── FIFO cost recalculation for this delivery ──
        DECLARE @ProductCosting TABLE (
            ProductCode VARCHAR(10),
            Qty         FLOAT,
            Cost        MONEY,
            TotalCost   MONEY
        );

        INSERT INTO @ProductCosting (ProductCode, Qty, Cost, TotalCost)
        SELECT I.ProductNo,
               SUM(I.QtyDelivered),
               SUM(I.Cost),
               SUM(I.TotalCost)
        FROM InventoryDeliveryFIFO I
        WHERE I.PONumber = @parmpono AND I.DeliveryNo = @parmdevno and I.isErrorCorrect=0
        GROUP BY I.ProductNo;

        UPDATE dd
		SET dd.Cost =  isnull(i.Cost,0)
		FROM DeliveryDetails dd
		INNER JOIN InventoryDeliveryFIFO i
			ON dd.PONumber=i.PONumber
			and dd.SeqNo=i.DevDetSeqNo
			and dd.ProductNo=i.ProductNo
			and i.isErrorCorrect=0
		WHERE dd.PONumber = @parmpono
		AND dd.DeliveryNo = @parmdevno;

        SELECT TOP (1) @parmeffectivitydate = EffectivityDate
        FROM TransferOrderSummary WITH (NOLOCK)
        WHERE PONumber = @parmpono;

        DECLARE @totalitem INT, @totalqtydelivered FLOAT;
        SELECT @totalitem = COUNT(*), @totalqtydelivered = SUM(QtyDelivered)
        FROM DeliveryDetails
        WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono  and isReturned=0 and isCancelled=0;

        SET @totalitem         = ISNULL(@totalitem, 0);
        SET @totalqtydelivered = ISNULL(@totalqtydelivered, 0);

        -- ── DeliverySummary header (insert first time, update thereafter) ──
        IF NOT EXISTS (SELECT 1 FROM DeliverySummary WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono)
        BEGIN
            INSERT INTO [dbo].[DeliverySummary]
                ([DeliveryNo],[PONumber],[ReferenceNumber],[InvoiceNo],[BranchCode],
                 [TotalItem],[TotalQtyDelivered],[TotalActualQty],[TotalVarianceVat],
                 [TotalVarianceVatExempt],[EffectivityDate],[Status],[DateAdded],
                 [PreparedBy],[isSettled],[isInvoiceUpdate])
            VALUES
                (@parmdevno, @parmpono, @parmrefno, @parmrefno, @parmbranchcode,
                 @totalitem, @totalqtydelivered, 0, 0,
                 0, @parmeffectivitydate, 'FOR DELIVERY', GETDATE(),
                 @preparedby, 0, 0);
        END
        ELSE
        BEGIN
            UPDATE DeliverySummary
            SET TotalItem = (SELECT ISNULL(COUNT(*),0) FROM DeliveryDetails WHERE PONumber=@parmpono),
                TotalQtyDelivered = (SELECT ISNULL(SUM(QtyDelivered),0) FROM DeliveryDetails WHERE PONumber=@parmpono and isCancelled=0 and isReturned=0),
                TotalItemSold = (SELECT ISNULL(COUNT(*),0) FROM DeliveryDetails WHERE PONumber=@parmpono and isCancelled=0 and isReturned=0),
                TotalItemReturned = (SELECT ISNULL(COUNT(*),0) FROM DeliveryDetails WHERE PONumber=@parmpono and isReturned=0),
                Status = 'FOR DELIVERY'
            WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono;
        END

        -- ── totals for the ticket amounts (also tells us whether each leg is needed) ──
        DECLARE @overalltotalcostnonvat MONEY, @overalltotalcostwithvat MONEY;

        SELECT @overalltotalcostnonvat  = SUM(CASE WHEN IsVat = '0' THEN ISNULL(TotalCost,0) END),
               @overalltotalcostwithvat = SUM(CASE WHEN IsVat = '1' THEN ISNULL(TotalCost,0) END)
        FROM InventoryDeliveryFIFO
        WHERE BranchCode = @parmbranchcode
          AND PONumber = @parmpono
          AND DeliveryNo = @parmdevno
          AND isErrorCorrect=0;

        SET @overalltotalcostnonvat  = ISNULL(@overalltotalcostnonvat, 0);
        SET @overalltotalcostwithvat = ISNULL(@overalltotalcostwithvat, 0);

        -- ── this SP is always the HO shipping-out side. @parmbranchcode is the
        --    DESTINATION branch (used above only to filter InventoryDeliveryFIFO /
        --    DeliveryDetails for that branch's leg of a multi-branch PO) - the
        --    ticket itself always books to HO's own ledger, branch '888',
        --    same as the original hardcoded TicketMaster inserts. The receiving
        --    branch's own entries are posted separately, by
        --    sp_ConfirmBranchRecievedOrder, when that branch confirms receipt. ──
        DECLARE @TicketBranchCode VARCHAR(10) = '888';
        DECLARE @MnemonicVAT      VARCHAR(20) = 'IT-HO-VAT';
        DECLARE @MnemonicVATEX    VARCHAR(20) = 'IT-HO-VATEX';

        DECLARE @outrefnum VARCHAR(10), @Particulars VARCHAR(400);
        EXEC GetReferenceNumber @outrefnum OUTPUT;

        SET @Particulars = 'Inventory Transfer Out - PO#' + @parmpono + ' (to Branch ' + @parmbranchcode + ')- VATable';

        IF @overalltotalcostwithvat > 0
        BEGIN
            DECLARE @AmtsVAT dbo.tt_AmountBreakdown, @TokVAT dbo.tt_TokenResolution, @FlgVAT dbo.tt_ConditionFlags;
            INSERT @AmtsVAT VALUES ('GROSS', @overalltotalcostwithvat);

            EXEC [dbo].[sp_PostCompoundTicket]
                @Mnemonic        = @MnemonicVAT,
                @TicketDate      = @parmeffectivitydate,
                @BranchCode      = @TicketBranchCode,
                @ReferenceNumber = @outrefnum,
                @ReferenceKey    = @parmpono,
                @Particulars     = @Particulars,
                @Owner           = 'CS IN TRANSIT',
                @PreparedBy      = @username,
                @Amounts         = @AmtsVAT,
                @Tokens          = @TokVAT,
                @Flags           = @FlgVAT,
                @LedgerType      = NULL,
                @LedgerEntityID  = NULL,
                @LedgerInvoiceNo = NULL,
                @LedgerBatchRef  = @parmpono,
                @LedgerSeqRef    = 1;
        END

        IF @overalltotalcostnonvat > 0
        BEGIN
            DECLARE @AmtsVE dbo.tt_AmountBreakdown, @TokVE dbo.tt_TokenResolution, @FlgVE dbo.tt_ConditionFlags;
            INSERT @AmtsVE VALUES ('GROSS', @overalltotalcostnonvat);
             SET @Particulars = 'Inventory Transfer Out - PO#' + @parmpono + ' (to Branch ' + @parmbranchcode + ')- VAT Exempt';

            EXEC [dbo].[sp_PostCompoundTicket]
                @Mnemonic        = @MnemonicVATEX,
                @TicketDate      = @parmeffectivitydate,
                @BranchCode      = @TicketBranchCode,
                @ReferenceNumber = @outrefnum,
                @ReferenceKey    = @parmpono,
                @Particulars     = @Particulars,
                @Owner           = 'CS IN TRANSIT',
                @PreparedBy      = @username,
                @Amounts         = @AmtsVE,
                @Tokens          = @TokVE,
                @Flags           = @FlgVE,
                @LedgerType      = NULL,
                @LedgerEntityID  = NULL,
                @LedgerInvoiceNo = NULL,
                @LedgerBatchRef  = @parmpono,
                @LedgerSeqRef    = 2;
        END

        UPDATE TransferOrderSummary
        SET isProcess = '1'
        WHERE PONumber = @parmpono;

        INSERT INTO HistoryLogs
        VALUES (@preparedby, GETDATE(), 'Commissary Process Order with PONumber=' + @parmpono, @parmbranchcode);

        COMMIT TRANSACTION;

        SELECT 1 AS Status, 'Order confirmed and posted.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

PRINT 'DEPLOYMENT COMPLETE: sp_ConfirmBranchOrderSTS now rejects confirming a delivery with zero line items instead of failing on a NULL SUM() insert.';
