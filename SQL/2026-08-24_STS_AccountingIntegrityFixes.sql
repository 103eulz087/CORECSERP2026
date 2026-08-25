SET NOCOUNT ON;
PRINT '=== STS (Stock Transfer) accounting-integrity fixes: unified reversal, receiving reversal support, approval gates ===';
GO

/* ================================================================================
   Context: assessment of the STS branch-transfer module (2026-08-24) found:
     1. Two divergent "return dispatched stock" code paths -- AddBranchOrderSTS.cs's
        own Return button called sp_CancelDelivery/sp_CancelDeliveryFIFOJFC/
        sp_CancelDeliveryByBarcode directly (no GL reversal), while the "For
        Delivery" tab's error-correct path called sp_ReverseSTSInventoryTransfer
        (which DOES post a GL reversal ticket). Depending on which screen a user
        used, the books and physical inventory could diverge.
     2. DeliverySummary.Status never gets corrected off FOR DELIVERY/PENDING when
        every line for a dispatch ends up cancelled/returned -- confirmed via
        repo-wide grep, no code path ever writes RETURNED/CANCELLED/DELIVERED.
     3. Receiving (ReceivedSTSBatchMode.cs): the "select which items arrived"
        checkbox selection was wired to a different, invisible grid than the one
        actually shown to the user, AND the submission loop ignored selection
        state entirely -- every row was received in full regardless of checkbox
        state. Unchecked/undelivered items had zero server-side effect: no
        Inventory restore at origin, no return record, no isReturned flag --
        permanently unaccounted-for stock.
     4. No server-side check that a Transfer Order is APPROVED before it can be
        dispatched/confirmed -- only a UI-tab filter.

   Fix strategy: extend the ALREADY-CORRECT sp_ReverseSTSInventoryTransfer (adds
   the GL reversal + now also the DeliverySummary.Status correction) and route
   every return/cancel/not-received path through it, instead of three divergent
   call sites. sp_CancelDelivery / sp_CancelDeliveryFIFOJFC / sp_CancelDeliveryByBarcode
   / sp_ConfirmBranchRecievedOrder(/JFC) are NOT sourced in this repo -- they are
   only ever called here as black boxes, exactly as the pre-existing code already
   did; nothing about their internals is assumed beyond what the existing code
   already assumed.
   ================================================================================ */

-- =============================================
-- Author: Eulz Avancena (original, 2026-08-11); extended 2026-08-24
-- Description: Reverses a dispatched STS line (refund physical inventory +
--              GL reversal ticket when the transfer was confirmed). Delegates
--              the actual refund to the existing cancel SPs -- unchanged
--              behavior for existing callers.
-- CHANGELOG 2026-08-24:
--   [1] @parmbarcode (optional) added -- when supplied, delegates to
--       sp_CancelDeliveryByBarcode instead of sp_CancelDelivery/
--       sp_CancelDeliveryFIFOJFC, so barcode-mode returns (previously called
--       directly from AddBranchOrderSTS.cs's returnOrderByBarcode(), with NO
--       GL reversal at all) now go through the same reversal-ticket logic as
--       every other return path.
--   [2] After the refund, if DeliveryDetails has no remaining line for this
--       DeliveryNo/PONumber with isReturned=0 AND isCancelled=0 (the "still
--       active" convention already used elsewhere in this codebase, e.g.
--       AddBranchOrderSTS.cs's own Save-guard, spr_STSSummary), DeliverySummary
--       .Status is corrected to RETURNED. Previously nothing ever moved it off
--       FOR DELIVERY/PENDING once a dispatch was fully cancelled/returned.
--   Both changes are additive; existing callers (StocksOrder.cs's
--   executeErrorCorrect()) are unaffected -- @parmbarcode defaults to NULL and
--   the status correction only fires once nothing is left, same result as
--   before for a partial return.
-- =============================================
IF OBJECT_ID('dbo.sp_ReverseSTSInventoryTransfer_OLD_08242026120000', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ReverseSTSInventoryTransfer_OLD_08242026120000;
GO
IF OBJECT_ID('dbo.sp_ReverseSTSInventoryTransfer', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_ReverseSTSInventoryTransfer', 'sp_ReverseSTSInventoryTransfer_OLD_08242026120000';
GO

CREATE PROCEDURE [dbo].[sp_ReverseSTSInventoryTransfer]
    @parmdevno       VARCHAR(20),
    @parmrefno       VARCHAR(10),
    @parmpono        VARCHAR(10),
    @parmprodno      VARCHAR(20),
    @parmqty         DECIMAL(18,3),
    @parmbranchcode  VARCHAR(10),
    @parmorigin      VARCHAR(10),
    @preparedby      VARCHAR(30),
    @parmdevseqno    INT,
    @parmbarcode     VARCHAR(100) = NULL
AS
BEGIN
    SET XACT_ABORT OFF;
    -- XACT_ABORT OFF -- sp_CancelDelivery/sp_CancelDeliveryFIFOJFC/
    -- sp_CancelDeliveryByBarcode and sp_PostCompoundTicket are called inside
    -- this transaction; rollback is managed explicitly in CATCH (same
    -- nested-SP rationale documented in sp_ConfirmOrder / sp_CreditMemo /
    -- sp_ReturnSalesOrder).
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ── Snapshot which FIFO layers are still un-corrected BEFORE the
        --    refund, in the same scope sp_CancelDelivery itself uses.
        --    Keyed on SequenceNumber (the real identity column) -- NOT
        --    SequenceReferenceNumber, which is just a FK to the underlying
        --    Inventory layer and can repeat across many unrelated
        --    deliveries/products that drew from the same layer. ──
        SELECT SequenceNumber
        INTO #BeforeSnapshot
        FROM InventoryDeliveryFIFO
        WHERE DeliveryNo = @parmdevno
          AND PONumber = @parmpono
          AND BranchCode = @parmbranchcode
          AND ProductNo = @parmprodno
          AND isErrorCorrect = 0;

        -- ── Delegate the actual inventory refund + DeliveryDetails cleanup
        --    to the existing, already-correct cancel SPs -- no logic
        --    duplicated here, including FIFO-vs-scan-vs-barcode handling ──
        DECLARE @companyname VARCHAR(50);
        SELECT TOP 1 @companyname = CompanyName FROM CompanyProfile;

        IF @parmbarcode IS NOT NULL AND LEN(@parmbarcode) > 0
        BEGIN
            EXEC dbo.sp_CancelDeliveryByBarcode
                @parmbranchcode = @parmbranchcode, @parmorigin = @parmorigin,
                @parmdevno = @parmdevno, @parmrefno = @parmrefno, @parmpono = @parmpono,
                @parmbarcode = @parmbarcode, @preparedby = @preparedby;
        END
        ELSE IF @companyname = 'JFC'
        BEGIN
            EXEC dbo.sp_CancelDeliveryFIFOJFC
                @parmdevno = @parmdevno, @parmrefno = @parmrefno, @parmpono = @parmpono,
                @parmprodno = @parmprodno, @parmqty = @parmqty, @parmbranchcode = @parmbranchcode,
                @parmorigin = @parmorigin, @preparedby = @preparedby, @parmdevseqno = @parmdevseqno;
        END
        ELSE
        BEGIN
            EXEC dbo.sp_CancelDelivery
                @parmdevno = @parmdevno, @parmrefno = @parmrefno, @parmpono = @parmpono,
                @parmprodno = @parmprodno, @parmqty = @parmqty, @parmbranchcode = @parmbranchcode,
                @parmorigin = @parmorigin, @preparedby = @preparedby, @parmdevseqno = @parmdevseqno;
        END

        -- ── Delta: exactly which layers THIS call just flipped to corrected.
        --    Works whether the underlying SP refunded one scan (non-FIFO) or
        --    every not-yet-corrected layer for this product/delivery (FIFO). ──
        SELECT f.SequenceNumber, f.TotalCost, f.isVat
        INTO #JustCorrected
        FROM InventoryDeliveryFIFO f
        INNER JOIN #BeforeSnapshot b ON f.SequenceNumber = b.SequenceNumber
        WHERE f.isErrorCorrect = 1;

        DECLARE @wasProcessed BIT;
        SELECT @wasProcessed = isProcess FROM TransferOrderSummary WHERE PONumber = @parmpono;

        IF ISNULL(@wasProcessed, 0) = 1 AND EXISTS (SELECT 1 FROM #JustCorrected)
        BEGIN
            DECLARE @totalcostvat MONEY, @totalcostvatex MONEY, @effectivitydate DATE;

            SELECT
                @totalcostvat   = ISNULL(SUM(CASE WHEN isVat = 1 THEN TotalCost ELSE 0 END), 0),
                @totalcostvatex = ISNULL(SUM(CASE WHEN isVat = 0 THEN TotalCost ELSE 0 END), 0)
            FROM #JustCorrected;

            SELECT TOP 1 @effectivitydate = EffectivityDate FROM TransferOrderSummary WHERE PONumber = @parmpono;
            SET @effectivitydate = ISNULL(@effectivitydate, CAST(GETDATE() AS DATE));

            DECLARE @outrefnum VARCHAR(10), @Particulars VARCHAR(400);
            EXEC GetReferenceNumber @outrefnum OUTPUT;

            IF @totalcostvat > 0
            BEGIN
                DECLARE @AmtsVAT dbo.tt_AmountBreakdown, @TokVAT dbo.tt_TokenResolution, @FlgVAT dbo.tt_ConditionFlags;
                INSERT @AmtsVAT VALUES ('GROSS', @totalcostvat);
                SET @Particulars = 'Inventory Transfer RETURN - PO#' + @parmpono + ' (from Branch ' + @parmbranchcode + ') - VATable';

                EXEC [dbo].[sp_PostCompoundTicket]
                    @Mnemonic        = 'ITR-HO-VAT',
                    @TicketDate      = @effectivitydate,
                    @BranchCode      = '888',
                    @ReferenceNumber = @outrefnum,
                    @ReferenceKey    = @parmpono,
                    @Particulars     = @Particulars,
                    @Owner           = 'CS IN TRANSIT',
                    @PreparedBy      = @preparedby,
                    @Amounts         = @AmtsVAT,
                    @Tokens          = @TokVAT,
                    @Flags           = @FlgVAT,
                    @LedgerType      = NULL,
                    @LedgerEntityID  = NULL,
                    @LedgerInvoiceNo = NULL,
                    @LedgerBatchRef  = @parmpono,
                    @LedgerSeqRef    = 1;
            END

            IF @totalcostvatex > 0
            BEGIN
                DECLARE @AmtsVE dbo.tt_AmountBreakdown, @TokVE dbo.tt_TokenResolution, @FlgVE dbo.tt_ConditionFlags;
                INSERT @AmtsVE VALUES ('GROSS', @totalcostvatex);
                SET @Particulars = 'Inventory Transfer RETURN - PO#' + @parmpono + ' (from Branch ' + @parmbranchcode + ') - VAT Exempt';

                EXEC [dbo].[sp_PostCompoundTicket]
                    @Mnemonic        = 'ITR-HO-VATEX',
                    @TicketDate      = @effectivitydate,
                    @BranchCode      = '888',
                    @ReferenceNumber = @outrefnum,
                    @ReferenceKey    = @parmpono,
                    @Particulars     = @Particulars,
                    @Owner           = 'CS IN TRANSIT',
                    @PreparedBy      = @preparedby,
                    @Amounts         = @AmtsVE,
                    @Tokens          = @TokVE,
                    @Flags           = @FlgVE,
                    @LedgerType      = NULL,
                    @LedgerEntityID  = NULL,
                    @LedgerInvoiceNo = NULL,
                    @LedgerBatchRef  = @parmpono,
                    @LedgerSeqRef    = 2;
            END
        END

        -- ── NEW: correct the header status once nothing is left to
        --    deliver/return for this dispatch. Idempotent (WHERE Status <>
        --    'RETURNED'); fires regardless of whether the dispatch was ever
        --    confirmed (PENDING) or already FOR DELIVERY, matching the
        --    explicit ask: "if there are no more items it should be
        --    returned status." ──
        IF NOT EXISTS (
            SELECT 1 FROM DeliveryDetails
            WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono
              AND isReturned = 0 AND isCancelled = 0
        )
        BEGIN
            UPDATE DeliverySummary
            SET Status = 'RETURNED'
            WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono
              AND Status <> 'RETURNED';
        END

        DROP TABLE IF EXISTS #BeforeSnapshot;
        DROP TABLE IF EXISTS #JustCorrected;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        DROP TABLE IF EXISTS #BeforeSnapshot;
        DROP TABLE IF EXISTS #JustCorrected;

        -- Bare THROW (not RAISERROR) preserves the original error number --
        -- callers distinguishing failure reasons (e.g. this proc's own
        -- callers, or future ones) get the real error, not a generic 50000.
        THROW;
    END CATCH
END
GO

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-24
-- Description: Read-only source for ReceivedSTSBatchMode.cs's grid --
--              replaces funcview_ReceivedSTS(...) (not sourced anywhere in
--              this repo, unknown/unverifiable column shape). Only lines
--              still awaiting resolution (not already cancelled/returned)
--              are returned, so a previously-resolved line can't be
--              re-submitted as received or re-flagged as not-received.
--              Inline TVF (not a procedure) so the C# side can load it the
--              same "SELECT * FROM dbo.funcview_...(@p)" way every other
--              STS grid in this module already does (funcview_TransferOrderDetailsSTS,
--              funcview_ReceivedSTS), including HelperFunction's async
--              wait-dialog wrapper.
-- =============================================
IF OBJECT_ID('dbo.funcview_DeliveryDetailsForReceiving_OLD_08242026120000', 'IF') IS NOT NULL
    DROP FUNCTION dbo.funcview_DeliveryDetailsForReceiving_OLD_08242026120000;
GO
IF OBJECT_ID('dbo.funcview_DeliveryDetailsForReceiving', 'IF') IS NOT NULL
    EXEC sp_rename 'dbo.funcview_DeliveryDetailsForReceiving', 'funcview_DeliveryDetailsForReceiving_OLD_08242026120000';
GO

CREATE FUNCTION [dbo].[funcview_DeliveryDetailsForReceiving]
(
    @PONumber VARCHAR(10)
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        SeqNo,
        DeliveryNo,
        PONumber,
        ReferenceNumber,
        ProductNo,
        ProductName,
        BarcodeNo,
        QtyDelivered,
        ActualQty,
        Cost,
        SellingPrice,
        isVat
    FROM dbo.DeliveryDetails
    WHERE PONumber = @PONumber
      AND isReturned = 0
      AND isCancelled = 0
);
GO

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-24
-- Description: sp_ConfirmBranchOrderSTS -- same body as
--              SQL\2026-08-17_ConfirmBranchOrderSTS_EmptyDeliveryGuard.sql
--              (the current live version), plus a new gate: refuses to
--              confirm/GL-post a delivery whose Transfer Order request was
--              never APPROVED. This is a server-side backstop -- previously
--              "must be Approved before dispatch" was enforced only by which
--              UI tab a user happened to be looking at (POForApprovalSTS.cs's
--              client-side view filters), not by the database.
--              NOTE: this does not fully close the gap -- dbo.sp_AddBranchOrder
--              (called per line, both from the batch loop and directly from
--              AddBranchOrderSTS.cs's non-batch add path) is not sourced
--              anywhere in this repo, so a line could still theoretically be
--              added/inventory-deducted before this confirm-time gate is
--              reached. This gate stops the transaction from ever being
--              finalized/GL-posted, which is the point of no return that
--              matters most; closing the line-add moment itself requires
--              sp_AddBranchOrder's current body.
-- =============================================
IF OBJECT_ID('dbo.sp_ConfirmBranchOrderSTS_OLD_08242026120000', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ConfirmBranchOrderSTS_OLD_08242026120000;
GO
IF OBJECT_ID('dbo.sp_ConfirmBranchOrderSTS', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_ConfirmBranchOrderSTS', 'sp_ConfirmBranchOrderSTS_OLD_08242026120000';
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

        -- ── NEW: refuse to confirm/GL-post a delivery whose request was
        --    never approved (see header note above). ──
        DECLARE @transferStatus VARCHAR(30);
        SELECT @transferStatus = Status FROM TransferOrderSummary WHERE PONumber = @parmpono;
        IF @transferStatus IS NULL OR @transferStatus <> 'APPROVED'
            THROW 58162, 'Cannot confirm: this Transfer Order request has not been approved.', 1;

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

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-24
-- Description: sp_AddBranchOrderBatch -- same body as
--              SQL\2026-08-18_TransferItemType_AddSeqNo.sql (the current live
--              version), plus the same APPROVED gate as sp_ConfirmBranchOrderSTS
--              above. Reported via the existing @SkippedItems result set
--              (all lines skipped with a clear reason) rather than a hard
--              THROW, to match this proc's own established
--              isolate-and-report-per-row design instead of aborting the
--              whole call differently from how it already behaves for other
--              per-row failures.
-- =============================================
IF OBJECT_ID('dbo.sp_AddBranchOrderBatch_OLD_08242026120000', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_AddBranchOrderBatch_OLD_08242026120000;
GO
IF OBJECT_ID('dbo.sp_AddBranchOrderBatch', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_AddBranchOrderBatch', 'sp_AddBranchOrderBatch_OLD_08242026120000';
GO

CREATE PROCEDURE [dbo].[sp_AddBranchOrderBatch]
    @TransferItems dbo.TransferItemType READONLY,
    @PONumber      VARCHAR(10),
    @DeliveryNo    VARCHAR(10),
    @ReferenceNo   VARCHAR(10),
    @BranchCode    VARCHAR(10),
    @PreparedBy    VARCHAR(50) = 'system'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SkippedItems TABLE (
        ProductCode VARCHAR(10),
        ProductName VARCHAR(100),
        SeqNo       DECIMAL(3,0),
        Reason      VARCHAR(400)
    );

    -- ── NEW: refuse the whole batch (reported per-row, not a hard THROW --
    --    matches this proc's own per-row skip/report design) if the request
    --    was never approved. ──
    DECLARE @transferStatus VARCHAR(30);
    SELECT @transferStatus = Status FROM TransferOrderSummary WHERE PONumber = @PONumber;
    IF @transferStatus IS NULL OR @transferStatus <> 'APPROVED'
    BEGIN
        INSERT INTO @SkippedItems (ProductCode, ProductName, SeqNo, Reason)
        SELECT ProductCode, ProductName, SeqNo, 'Transfer Order request is not APPROVED.'
        FROM @TransferItems;

        SELECT ProductCode, ProductName, SeqNo, Reason FROM @SkippedItems;
        RETURN;
    END

    DECLARE @OriginCode VARCHAR(10);

    SELECT @OriginCode = BranchCode FROM TransferOrderSummary WHERE PONumber = @PONumber;

    DECLARE @Item TABLE (
        RowID               INT IDENTITY(1,1),
        ProductCategoryCode VARCHAR(10),
        ProductCode         VARCHAR(10),
        ProductName         VARCHAR(100),
        Qty                 DECIMAL(9,3),
        SeqNo               DECIMAL(3,0)
    );

    INSERT INTO @Item (ProductCategoryCode, ProductCode, ProductName, Qty, SeqNo)
    SELECT ProductCategoryCode, ProductCode, ProductName, Qty, SeqNo
    FROM @TransferItems;

    DECLARE @i INT = 1, @max INT = (SELECT COUNT(*) FROM @Item);
    WHILE @i <= @max
    BEGIN
        DECLARE @prodcatcode VARCHAR(10), @prodcode VARCHAR(10), @prodname VARCHAR(100), @qty DECIMAL(9,3), @seqno DECIMAL(3,0);
        SELECT @prodcatcode = ProductCategoryCode, @prodcode = ProductCode, @prodname = ProductName, @qty = Qty, @seqno = SeqNo
        FROM @Item WHERE RowID = @i;

        BEGIN TRY
            EXEC dbo.sp_AddBranchOrder
                @DeliveryNo, @ReferenceNo, @PONumber,
                @prodcatcode, @prodcode, @qty, '',
                @BranchCode, @OriginCode, @PreparedBy, '', 0;
        END TRY
        BEGIN CATCH
            INSERT INTO @SkippedItems (ProductCode, ProductName, SeqNo, Reason)
            VALUES (@prodcode, @prodname, @seqno, ERROR_MESSAGE());
        END CATCH

        SET @i += 1;
    END

    SELECT ProductCode, ProductName, SeqNo, Reason FROM @SkippedItems;
END
GO

PRINT 'DEPLOYMENT COMPLETE: sp_ReverseSTSInventoryTransfer (barcode mode + status correction), funcview_DeliveryDetailsForReceiving, sp_ConfirmBranchOrderSTS (+approval gate), sp_AddBranchOrderBatch (+approval gate).';
