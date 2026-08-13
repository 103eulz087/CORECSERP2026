SET NOCOUNT ON;
PRINT '=== STS Return Stock (StocksOrder.cs executeErrorCorrect): reversal GL ticket for confirmed transfers ===';
GO

-- =============================================
-- CONTEXT: sp_ConfirmBranchOrderSTS (called from AddBranchOrderSTS.cs's
-- ConfirmBranchOrder(), the "Save" button) books an IT-HO-VAT / IT-HO-VATEX
-- ticket (DR {DUE_FROM_BRANCH} / CR Inventory) when an STS transfer is
-- confirmed. StocksOrder.cs's executeErrorCorrect() already refunds the
-- physical inventory (sp_CancelDelivery / sp_CancelDeliveryFIFOJFC) when
-- stock is returned after that point (bad weather, damaged goods, etc.) --
-- but nothing reversed the GL side, so the books kept showing the transfer
-- as if it fully happened even after some/all of it was returned.
--
-- New mnemonics ITR-HO-VAT / ITR-HO-VATEX mirror IT-HO-VAT / IT-HO-VATEX
-- with Debit/Credit swapped -- same accounts, opposite direction.
-- =============================================

IF NOT EXISTS (SELECT 1 FROM JournalEntryMapping WHERE Mnemonic = 'ITR-HO-VAT')
BEGIN
    INSERT INTO JournalEntryMapping
        (Origin, Mnemonic, Description, Seq, DebitCredit, AccountCode, IsConditional, IsAmountFromSource, IsActive, AmountType, ConditionFlag, BranchCode)
    VALUES
        ('IT', 'ITR-HO-VAT', 'Inventory Transfer Return HO to Branch - VAT (HO)', 1, 'C', '{DUE_FROM_BRANCH}', 0, 1, 1, 'GROSS', NULL, NULL),
        ('IT', 'ITR-HO-VAT', 'Inventory Transfer Return HO to Branch - VAT (HO)', 2, 'D', '101040202', 0, 1, 1, 'GROSS', NULL, NULL);
END

IF NOT EXISTS (SELECT 1 FROM JournalEntryMapping WHERE Mnemonic = 'ITR-HO-VATEX')
BEGIN
    INSERT INTO JournalEntryMapping
        (Origin, Mnemonic, Description, Seq, DebitCredit, AccountCode, IsConditional, IsAmountFromSource, IsActive, AmountType, ConditionFlag, BranchCode)
    VALUES
        ('IT', 'ITR-HO-VATEX', 'Inventory Transfer Return HO to Branch - VAT Exempt (HO)', 1, 'C', '101040102', 0, 1, 1, 'GROSS', NULL, NULL),
        ('IT', 'ITR-HO-VATEX', 'Inventory Transfer Return HO to Branch - VAT Exempt (HO)', 2, 'D', '101040201', 0, 1, 1, 'GROSS', NULL, NULL);
END
GO

-- =============================================
-- Author:      Eulz Avancena (original); added 2026-08-11
-- Description: Wraps the existing sp_CancelDelivery / sp_CancelDeliveryFIFOJFC
--              (unchanged, still the single source of truth for the actual
--              inventory refund + DeliveryDetails cleanup) and adds a GL
--              reversal ticket on top, scoped to exactly what THIS call
--              refunded -- not the whole PO's return history, so returning
--              specific items now and the rest later (staged, per the
--              "return all or return by specific item" checkbox UI) reverses
--              the correct partial amount each time, not the full original
--              ticket every time.
--
--              Only posts a reversal if the STS transfer was actually
--              confirmed (TransferOrderSummary.isProcess=1) -- if it was
--              never confirmed, sp_ConfirmBranchOrderSTS never booked a
--              ticket in the first place, so there is nothing to reverse.
-- =============================================
IF OBJECT_ID('dbo.sp_ReverseSTSInventoryTransfer', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_ReverseSTSInventoryTransfer;
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
    @parmdevseqno    INT
AS
BEGIN
    SET XACT_ABORT OFF;
    -- XACT_ABORT OFF -- sp_CancelDelivery/sp_CancelDeliveryFIFOJFC and
    -- sp_PostCompoundTicket are called inside this transaction; rollback is
    -- managed explicitly in CATCH (same nested-SP rationale documented in
    -- sp_ConfirmOrder / sp_CreditMemo / sp_ReturnSalesOrder).
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ── Snapshot which FIFO layers are still un-corrected BEFORE the
        --    refund, in the same scope sp_CancelDelivery itself uses.
        --    Keyed on SequenceNumber (the real identity column) -- NOT
        --    SequenceReferenceNumber, which is just a FK to the underlying
        --    Inventory layer and can repeat across many unrelated
        --    deliveries/products that drew from the same layer. Joining on
        --    that instead of the true identity pulled in already-corrected
        --    rows from completely unrelated deliveries and wildly inflated
        --    the reversal amount -- caught by testing against real data. ──
        SELECT SequenceNumber
        INTO #BeforeSnapshot
        FROM InventoryDeliveryFIFO
        WHERE DeliveryNo = @parmdevno
          AND PONumber = @parmpono
          AND BranchCode = @parmbranchcode
          AND ProductNo = @parmprodno
          AND isErrorCorrect = 0;

        -- ── Delegate the actual inventory refund + DeliveryDetails cleanup
        --    to the existing, already-correct cancel SP -- no logic
        --    duplicated here, including FIFO-vs-scan-mode handling ──
        DECLARE @companyname VARCHAR(50);
        SELECT TOP 1 @companyname = CompanyName FROM CompanyProfile;

        IF @companyname = 'JFC'
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

        DROP TABLE IF EXISTS #BeforeSnapshot;
        DROP TABLE IF EXISTS #JustCorrected;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        DROP TABLE IF EXISTS #BeforeSnapshot;
        DROP TABLE IF EXISTS #JustCorrected;

        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrSev INT = ERROR_SEVERITY();
        RAISERROR(@ErrMsg, @ErrSev, 1);
    END CATCH
END
GO

PRINT 'DEPLOYMENT COMPLETE: ITR-HO-VAT/ITR-HO-VATEX mnemonics, sp_ReverseSTSInventoryTransfer.';
