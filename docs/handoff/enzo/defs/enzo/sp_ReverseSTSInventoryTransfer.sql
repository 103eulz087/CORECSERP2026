

CREATE     PROCEDURE [dbo].[sp_ReverseSTSInventoryTransfer]
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

            --IF @totalcostvat > 0
            --BEGIN
            --    DECLARE @AmtsVAT dbo.tt_AmountBreakdown, @TokVAT dbo.tt_TokenResolution, @FlgVAT dbo.tt_ConditionFlags;
            --    INSERT @AmtsVAT VALUES ('GROSS', @totalcostvat);
            --    SET @Particulars = 'Inventory Transfer RETURN - PO#' + @parmpono + ' (from Branch ' + @parmbranchcode + ') - VATable';

            --    EXEC [dbo].[sp_PostCompoundTicket]
            --        @Mnemonic        = 'ITR-HO-VAT',
            --        @TicketDate      = @effectivitydate,
            --        @BranchCode      = '888',
            --        @ReferenceNumber = @outrefnum,
            --        @ReferenceKey    = @parmpono,
            --        @Particulars     = @Particulars,
            --        @Owner           = 'CS IN TRANSIT',
            --        @PreparedBy      = @preparedby,
            --        @Amounts         = @AmtsVAT,
            --        @Tokens          = @TokVAT,
            --        @Flags           = @FlgVAT,
            --        @LedgerType      = NULL,
            --        @LedgerEntityID  = NULL,
            --        @LedgerInvoiceNo = NULL,
            --        @LedgerBatchRef  = @parmpono,
            --        @LedgerSeqRef    = 1;
            --END

            --IF @totalcostvatex > 0
            --BEGIN
            --    DECLARE @AmtsVE dbo.tt_AmountBreakdown, @TokVE dbo.tt_TokenResolution, @FlgVE dbo.tt_ConditionFlags;
            --    INSERT @AmtsVE VALUES ('GROSS', @totalcostvatex);
            --    SET @Particulars = 'Inventory Transfer RETURN - PO#' + @parmpono + ' (from Branch ' + @parmbranchcode + ') - VAT Exempt';

            --    EXEC [dbo].[sp_PostCompoundTicket]
            --        @Mnemonic        = 'ITR-HO-VATEX',
            --        @TicketDate      = @effectivitydate,
            --        @BranchCode      = '888',
            --        @ReferenceNumber = @outrefnum,
            --        @ReferenceKey    = @parmpono,
            --        @Particulars     = @Particulars,
            --        @Owner           = 'CS IN TRANSIT',
            --        @PreparedBy      = @preparedby,
            --        @Amounts         = @AmtsVE,
            --        @Tokens          = @TokVE,
            --        @Flags           = @FlgVE,
            --        @LedgerType      = NULL,
            --        @LedgerEntityID  = NULL,
            --        @LedgerInvoiceNo = NULL,
            --        @LedgerBatchRef  = @parmpono,
            --        @LedgerSeqRef    = 2;
            --END
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
            SET Status = case when status = 'DELIVERED' then 'RETURNED'
			else Status end
            WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono
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
