SET NOCOUNT ON;
PRINT '=== sp_ReturnSalesOrder: TVP-driven lines + reversal-ticket rewrite ===';
GO
EXEC sp_rename 'dbo.sp_ReturnSalesOrder', 'sp_ReturnSalesOrder_OLD_08052026132558';
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Lines the caller (Orders/ReturnSalesOrder.cs) wants returned this run: one
-- row per checked grid row. Replaces the C# per-row
-- "INSERT INTO ReturnedOrderDetails VALUES ('...')" loop, which built the
-- statement by string concatenation (SQL-injection-prone) and ran OUTSIDE
-- this SP's transaction -- see CHANGELOG [1].
IF TYPE_ID('dbo.tt_ReturnSalesOrderLines') IS NULL
    CREATE TYPE dbo.tt_ReturnSalesOrderLines AS TABLE
    (
        SeqNo         decimal(10,0)  NOT NULL,
        ProductNo     varchar(20)    NOT NULL,
        ProductName   varchar(100)   NOT NULL,
        BarcodeNo     varchar(30)    NULL,
        QtyDelivered  decimal(10,3)  NOT NULL,
        Cost          decimal(12,2)  NOT NULL,
        SellingPrice  decimal(12,2)  NOT NULL,
        ActualQty     decimal(10,3)  NOT NULL,
        Variance      float          NULL,
        isVat         bit            NULL
    );
GO
-- Traceability for the reversal ticket posted below (see CHANGELOG [2]) --
-- mirrors the TicketRefNo audit trail added to the CreditMemo table in the
-- sp_CreditMemo rewrite (SQL/2026-08-05_CreditMemo_ReversalTicket_Rewrite.sql).
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.ReturnedOrderSummary') AND name = 'TicketRefNoVAT')
    ALTER TABLE dbo.ReturnedOrderSummary ADD TicketRefNoVAT varchar(10) NULL, TicketRefNoVATEX varchar(10) NULL;
GO
-- =============================================
-- Author:      (original modernized version, undated header); rewritten 2026-08-05
-- Description: Sales Return (Orders/ReturnSalesOrder.cs). Lets a user return
--              all or selected DeliveryDetails lines on a PO -- usable even
--              BEFORE Confirm Order, because Inventory is already deducted
--              at order-processing time (this SP restores it via
--              InventoryDeliveryFIFO/Inventory regardless of confirm status).
--              When the order was already confirmed (@parmreturnstatus=
--              'DELIVERED'), sp_ConfirmOrder has already booked SI-VAT/
--              SI-VATEX GL tickets -- this SP now books the mirror-reversal
--              via CM-CLIENT-VAT / CM-CLIENT-VATEX (same mnemonics and
--              sp_PostCompoundTicketSales engine as the sp_CreditMemo
--              rewrite), so the return is reflected on the books, not just
--              in the warehouse and the AR sub-ledger.
--
-- CHANGELOG FROM sp_ReturnSalesOrder (legacy, now sp_ReturnSalesOrder_OLD_08052026132558):
--   [1] @Lines TVP added (dbo.tt_ReturnSalesOrderLines). The old version
--       relied on the caller (C#) to INSERT INTO ReturnedOrderDetails one row
--       at a time via string-concatenated SQL, BEFORE calling this SP -- two
--       problems: (a) SQL-injection-shaped code (values interpolated
--       directly into the statement text) though in practice values were
--       DevExpress grid cells, not free-typed user input; (b) those INSERTs
--       ran in their own auto-committed connection, outside this SP's
--       transaction -- if the SP later failed and rolled back, the
--       ReturnedOrderDetails rows already committed by C# were orphaned:
--       present in the return-detail table but with none of the downstream
--       effects (DeliveryDetails.isReturned, Inventory restore, GL) actually
--       applied. Now the SP inserts the lines itself, inside its own
--       transaction, so the whole return is atomic.
--   [2] Reversal ticket entries added for the @parmreturnstatus='DELIVERED'
--       path. The old version updated TransactionChargeSales' cash-basis
--       Balance directly from TransactionChargeSalesDetails (a safe, already
--       correct full recompute -- left unchanged here) but never reversed
--       the GL ticket sp_ConfirmOrder posted (TicketMaster/TicketDetails)
--       or wrote anything to ClientLedger -- so a return processed after
--       Confirm Order left AR/Sales/Output VAT/COGS overstated at the GL
--       level even though the physical Inventory.Available quantity was
--       already restored (step 4, unchanged). Posts through the same
--       CM-CLIENT-VAT / CM-CLIENT-VATEX JournalEntryMapping mnemonics the
--       sp_CreditMemo rewrite uses -- a Sales Return and a Credit Memo are
--       the same accounting event from GL's point of view, so no new
--       mnemonics were needed. Skipped entirely when @parmreturnstatus <>
--       'DELIVERED', because sp_ConfirmOrder hasn't posted anything yet for
--       this SP to reverse (matches the existing TransactionChargeSales
--       guard).
--   [3] Re-run safety for the new GL section. Only the DeliveryDetails rows
--       actually inserted THIS call (captured via the [1] INSERT's OUTPUT
--       into #NewReturns) drive the reversal-ticket totals -- not every
--       historical row in ReturnedOrderDetails for the PO (steps 2/3/5/6/7
--       correctly use the full history; that's an intentional full
--       recompute, not a bug). Otherwise a second Return call on the same PO
--       (e.g. a different item returned later) would re-sum and re-post GL
--       entries for items already reversed in an earlier call.
--   [4] ReturnedOrderSummary widened with TicketRefNoVAT/TicketRefNoVATEX
--       (nullable) so a posted reversal ticket is traceable from the return
--       record.
--
-- The previous version is preserved as sp_ReturnSalesOrder_OLD_08052026132558.
-- =============================================
CREATE PROCEDURE [dbo].[sp_ReturnSalesOrder]
    @parmbranchcode   char(3),
    @parmpono         varchar(10),
    @parmdevno        varchar(10),
    @parmuser         varchar(50),
    @parmreturnstatus varchar(30),
    @parmmachinename  varchar(50),
    @Lines            dbo.tt_ReturnSalesOrderLines READONLY
AS
BEGIN
    SET XACT_ABORT OFF;
    -- XACT_ABORT OFF (not ON, unlike the prior version) -- sp_PostCompoundTicketSales
    -- is now called inside this transaction for the DELIVERED path; rollback is
    -- managed explicitly in CATCH (same rationale documented in sp_ConfirmOrder /
    -- sp_CreditMemo for nested-SP calls).
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM @Lines)
            THROW 59101, 'No lines submitted for this Sales Return.', 1;

        ---------------------------------------------------------------------------
        -- 1. GET INVOICE / CUSTOMER INFO
        ---------------------------------------------------------------------------
        DECLARE @invoiceno VARCHAR(20), @effectivitydate DATE, @custkey CHAR(8), @custname VARCHAR(100);

        SELECT @invoiceno = InvoiceNo,
               @effectivitydate = EffectivityDate
        FROM DeliverySummary WITH(NOLOCK)
        WHERE PONumber = @parmpono;

        SELECT @custkey = Customer FROM PurchaseOrderSummary WITH(NOLOCK) WHERE PONumber = @parmpono;
        SELECT @custname = CustomerName FROM Customers WITH(NOLOCK) WHERE CustomerKey = @custkey;

        ---------------------------------------------------------------------------
        -- 1b. INSERT NEW RETURN LINES (TVP-driven, idempotent -- see CHANGELOG [1])
        ---------------------------------------------------------------------------
        -- Only DeliveryDetails rows not already returned are accepted -- a
        -- resubmitted/duplicate row is silently skipped rather than
        -- double-inserted (this is what makes a re-run of this SP safe).
        SELECT l.SeqNo, @parmpono AS PONumber, l.ProductNo, l.ProductName, l.BarcodeNo,
               l.QtyDelivered, l.Cost, l.SellingPrice, l.ActualQty, l.Variance, l.isVat,
               @parmuser AS ProcessedBy, CAST(GETDATE() AS date) AS DateProcessed
        INTO #NewReturns
        FROM @Lines l
        JOIN DeliveryDetails dd
          ON dd.PONumber = @parmpono
         AND dd.SeqNo = l.SeqNo
         AND dd.ProductNo = l.ProductNo
         AND ISNULL(dd.BarcodeNo,'') = ISNULL(l.BarcodeNo,'')
        WHERE ISNULL(dd.isReturned,0) = 0;

        IF NOT EXISTS (SELECT 1 FROM #NewReturns)
            THROW 59102, 'No new lines to return for this PO (already returned).', 1;

        INSERT INTO ReturnedOrderDetails
            (SeqNo, PONumber, ProductNo, ProductName, BarcodeNo, QtyDelivered,
             Cost, SellingPrice, ActualQty, Variance, isVat, ProcessedBy, DateProcessed)
        SELECT SeqNo, PONumber, ProductNo, ProductName, BarcodeNo, QtyDelivered,
               Cost, SellingPrice, ActualQty, Variance, isVat, ProcessedBy, DateProcessed
        FROM #NewReturns;

        ---------------------------------------------------------------------------
        -- 2. UPSERT RETURNED ORDER SUMMARY (Optimized single-pass scan)
        ---------------------------------------------------------------------------
        DECLARE @Ret_TotalItem INT = 0,
                @Ret_TotalQty DECIMAL(18,2) = 0,
                @Ret_TotalAmt DECIMAL(18,2) = 0;

        SELECT @Ret_TotalItem = COUNT(*),
               @Ret_TotalQty = ISNULL(SUM(QtyDelivered), 0),
               @Ret_TotalAmt = ISNULL(SUM(QtyDelivered * SellingPrice), 0)
        FROM ReturnedOrderDetails WITH(NOLOCK)
        WHERE PONumber = @parmpono;

        IF NOT EXISTS (SELECT 1 FROM ReturnedOrderSummary WITH(UPDLOCK) WHERE PONumber = @parmpono)
        BEGIN
            INSERT INTO ReturnedOrderSummary (PONumber, InvoiceNo, BranchCode, TotalItem, TotalQtyDelivered, TotalAmount, EffectivityDate, DateAdded, PreparedBy, ReturnType)
            VALUES (@parmpono, @invoiceno, @parmbranchcode, @Ret_TotalItem, @Ret_TotalQty, @Ret_TotalAmt, @effectivitydate, GETDATE(), @parmuser, ' ');
        END
        ELSE
        BEGIN
            UPDATE ReturnedOrderSummary
            SET TotalItem = @Ret_TotalItem,
                TotalQtyDelivered = @Ret_TotalQty,
                TotalAmount = @Ret_TotalAmt
            WHERE PONumber = @parmpono;
        END

        ---------------------------------------------------------------------------
        -- 3. UPDATE DELIVERY DETAILS & SUMMARY
        ---------------------------------------------------------------------------
        UPDATE a
        SET a.isReturned = 1
        FROM DeliveryDetails a
        INNER JOIN ReturnedOrderDetails b
            ON a.PONumber = b.PONumber
            AND a.ProductNo = b.ProductNo
            AND a.BarcodeNo = b.BarcodeNo
            AND a.SeqNo = b.SeqNo
        WHERE a.PONumber = @parmpono;

        -- Optimized single-pass scan for Delivery Summary
        DECLARE @Del_TotalItem INT = 0,
                @Del_TotalQty DECIMAL(18,2) = 0,
                @Del_TotalActual DECIMAL(18,2) = 0;

        SELECT @Del_TotalItem = ISNULL(COUNT(*), 0),
               @Del_TotalQty = ISNULL(SUM(QtyDelivered), 0),
               @Del_TotalActual = ISNULL(SUM(ActualQty), 0)
        FROM DeliveryDetails WITH(NOLOCK)
        WHERE PONumber = @parmpono AND isReturned = 0;

        UPDATE DeliverySummary
        SET TotalItem = @Del_TotalItem,
            TotalQtyDelivered = @Del_TotalQty,
            TotalActualQty = @Del_TotalActual
        WHERE PONumber = @parmpono;

        ---------------------------------------------------------------------------
        -- 4. UPDATE INVENTORY FIFO & MASTER INVENTORY
        ---------------------------------------------------------------------------
        UPDATE InventoryDeliveryFIFO
        SET isErrorCorrect = 1
        WHERE DevDetSeqNo IN (
            SELECT SeqNo FROM DeliveryDetails WHERE PONumber = @parmpono AND isReturned = 1
        ) AND PONumber = @parmpono;

        UPDATE Inventory
        SET IsStock = 1,
            Available = (SELECT ISNULL(SUM(QtyDelivered), 0)
                         FROM InventoryDeliveryFIFO
                         WHERE PONumber = @parmpono
                         AND Inventory.SequenceNumber = SequenceReferenceNumber)
        WHERE SequenceNumber IN (
            SELECT SequenceReferenceNumber FROM InventoryDeliveryFIFO WHERE PONumber = @parmpono
        );

        ---------------------------------------------------------------------------
        -- 5. UPDATE BATCH SALES DETAILS
        ---------------------------------------------------------------------------
        UPDATE BatchSalesDetails
        SET isCancelled = 1
        WHERE ReferenceNo = @parmpono
          AND BranchCode = @parmbranchcode
          AND Barcode IN (SELECT BarcodeNo FROM ReturnedOrderDetails WHERE PONumber = @parmpono);

        ---------------------------------------------------------------------------
        -- 6. UPDATE BATCH SALES SUMMARY (The 12-Subquery Fix)
        ---------------------------------------------------------------------------
        DECLARE @userid VARCHAR(20), @cashiertransno INT, @cashiertransdate CHAR(8);
        SELECT @userid = UserID FROM Users WITH(NOLOCK) WHERE FullName = @parmuser;
        SET @cashiertransdate = dbo.func_ConvertDateTimeToChar('DATE', GETDATE());

        SELECT @cashiertransno = CashierTransNo
        FROM SalesTransactionSummary WITH(NOLOCK)
        WHERE BranchCode = @parmbranchcode
          AND MachineUsed = @parmmachinename
          AND UserID = @userid
          AND TransactionDate = @cashiertransdate;

        -- Pre-calculate all 12 metrics in ONE highly efficient table scan
        DECLARE @B_ItemRet INT = 0, @B_Item INT = 0, @B_ItemSold INT = 0, @B_VatItems INT = 0;
        DECLARE @B_RetAmt DECIMAL(18,2)=0, @B_Tax DECIMAL(18,2)=0, @B_Kilos DECIMAL(18,2)=0;
        DECLARE @B_SubTotal DECIMAL(18,2)=0, @B_Amt DECIMAL(18,2)=0, @B_VatSale DECIMAL(18,2)=0;
        DECLARE @B_VatExempt DECIMAL(18,2)=0, @B_Vatable DECIMAL(18,2)=0;

        SELECT
            @B_ItemRet = SUM(CASE WHEN isCancelled=1 AND isVoid=0 THEN 1 ELSE 0 END),
            @B_Item = SUM(CASE WHEN isCancelled=0 AND isVoid=0 THEN 1 ELSE 0 END),
            @B_ItemSold = SUM(CASE WHEN isCancelled=0 AND isVoid=0 THEN 1 ELSE 0 END),
            @B_VatItems = SUM(CASE WHEN isVat=1 AND isCancelled=0 AND isVoid=0 THEN 1 ELSE 0 END),
            @B_RetAmt = SUM(CASE WHEN isCancelled=1 AND isVoid=0 THEN TotalAmount ELSE 0 END),
            @B_Tax = SUM(CASE WHEN isCancelled=0 AND isVoid=0 THEN TaxTotal ELSE 0 END),
            @B_Kilos = SUM(CASE WHEN isCancelled=0 AND isVoid=0 THEN QtySold ELSE 0 END),
            @B_SubTotal = SUM(CASE WHEN isCancelled=0 AND isVoid=0 THEN SubTotal ELSE 0 END),
            @B_Amt = SUM(CASE WHEN isCancelled=0 AND isVoid=0 THEN TotalAmount ELSE 0 END),
            @B_VatSale = SUM(CASE WHEN isCancelled=0 AND isVoid=0 THEN TaxTotal ELSE 0 END),
            @B_VatExempt = SUM(CASE WHEN isVat=0 AND isCancelled=0 AND isVoid=0 THEN TotalAmount ELSE 0 END),
            @B_Vatable = SUM(CASE WHEN isVat=1 AND isCancelled=0 AND isVoid=0 THEN SubTotal ELSE 0 END)
        FROM BatchSalesDetails WITH(NOLOCK)
        WHERE ReferenceNo = @parmpono AND BranchCode = @parmbranchcode;

        -- Now apply all 12 variables instantly!
        UPDATE BatchSalesSummary
        SET TotalItemReturned = ISNULL(@B_ItemRet,0),
            TotalItem = ISNULL(@B_Item,0),
            TotalItemSold = ISNULL(@B_ItemSold,0),
            TotalVatableItems = ISNULL(@B_VatItems,0),
            TotalReturnedAmount = ISNULL(@B_RetAmt,0),
            TotalTax = ISNULL(@B_Tax,0),
            TotalKilos = ISNULL(@B_Kilos,0),
            SubTotal = ISNULL(@B_SubTotal,0),
            TotalAmount = ISNULL(@B_Amt,0),
            TotalVATSale = ISNULL(@B_VatSale,0),
            TotalVATExemptSale = ISNULL(@B_VatExempt,0),
            TotalVatableSale = ISNULL(@B_Vatable,0)
        WHERE ReferenceNo = @parmpono AND BranchCode = @parmbranchcode AND CashierTransNo = @cashiertransno;

        ---------------------------------------------------------------------------
        -- 7. UPDATE TRANSACTION CHARGE SALES + POST REVERSAL TICKETS (If Delivered)
        ---------------------------------------------------------------------------
        IF @parmreturnstatus = 'DELIVERED'
        BEGIN
            UPDATE TransactionChargeSalesDetails
            SET ErrorTag = 1
            WHERE ReferenceNo = @parmpono AND BranchCode = @parmbranchcode
              AND SKU IN (SELECT BarcodeNo FROM ReturnedOrderDetails WHERE PONumber = @parmpono);

            -- Single-pass calculation
            DECLARE @Charge_Total DECIMAL(18,2) = 0;
            SELECT @Charge_Total = ISNULL(SUM(TotalAmount), 0)
            FROM TransactionChargeSalesDetails WITH(NOLOCK)
            WHERE ReferenceNo = @parmpono AND BranchCode = @parmbranchcode AND ErrorTag = 0;

            UPDATE TransactionChargeSales
            SET TotalAmount = @Charge_Total,
                Balance = @Charge_Total,
                PayStatus = 'UNPAID'
            WHERE ReferenceNo = @parmpono AND BranchCode = @parmbranchcode;

            -- ── Reversal GL tickets (this run's #NewReturns only -- see CHANGELOG [2]/[3]) ─
            DECLARE
                @totalgrossvat    MONEY, @totalgrossvatex MONEY,
                @totalnetvat      MONEY, @totalvatoutput   MONEY,
                @totalcostvat     MONEY, @totalcostvatex   MONEY,
                @Particulars      VARCHAR(6999),
                @ticketnumvat     VARCHAR(10) = ' ',
                @ticketnumvatex   VARCHAR(10) = ' ';

            SELECT
                @totalgrossvat   = SUM(CASE WHEN isVat=1 THEN ISNULL(QtyDelivered*SellingPrice,0) ELSE 0 END),
                @totalgrossvatex = SUM(CASE WHEN isVat=0 THEN ISNULL(QtyDelivered*SellingPrice,0) ELSE 0 END),
                @totalcostvat    = SUM(CASE WHEN isVat=1 THEN ISNULL(QtyDelivered*Cost,0) ELSE 0 END),
                @totalcostvatex  = SUM(CASE WHEN isVat=0 THEN ISNULL(QtyDelivered*Cost,0) ELSE 0 END)
            FROM #NewReturns;

            SET @totalnetvat    = ISNULL(@totalgrossvat,0) / 1.12;
            SET @totalvatoutput = @totalnetvat * 0.12;

            SET @Particulars =
                'SALES RETURN | Customer: ' + ISNULL(@custname,'')
                + ' | PO: ' + @parmpono
                + ' | Invoice: ' + ISNULL(@invoiceno,'');

            IF ISNULL(@totalgrossvat,0) <> 0
            BEGIN
                DECLARE @AmtRetVat dbo.tt_AmountBreakdown;
                DECLARE @TokRetVat dbo.tt_TokenResolution;
                DECLARE @FlgRetVat dbo.tt_ConditionFlags;

                INSERT @AmtRetVat VALUES
                    ('GROSS', ROUND(@totalgrossvat,2)),
                    ('NET',   ROUND(@totalnetvat,2)),
                    ('VAT',   ROUND(@totalvatoutput,2)),
                    ('VATEX', 0),
                    ('COST',  ROUND(ISNULL(@totalcostvat,0),2));

                INSERT @FlgRetVat VALUES ('HasVAT', 1), ('HasVATEX', 0);

                EXEC [dbo].[sp_PostCompoundTicketSales]
                    @Mnemonic        = 'CM-CLIENT-VAT',
                    @TicketDate      = @effectivitydate,
                    @BranchCode      = @parmbranchcode,
                    @ReferenceNumber = @parmpono,
                    @ReferenceKey    = @invoiceno,
                    @Particulars     = @Particulars,
                    @Owner           = @custname,
                    @PreparedBy      = @parmuser,
                    @Status          = 'POSTED',
                    @Amounts         = @AmtRetVat,
                    @Tokens          = @TokRetVat,
                    @Flags           = @FlgRetVat,
                    @LedgerType      = NULL;   -- ClientLedger written below (Credit side)

                SELECT TOP 1 @ticketnumvat = TicketNumber
                FROM TicketMaster
                WHERE ReferenceNumber = @parmpono AND Mnemonic = 'CM-CLIENT-VAT'
                ORDER BY TRY_CAST(TicketNumber AS INT) DESC;

                DECLARE @TRNRetVat DECIMAL(7,0);
                SELECT @TRNRetVat = ISNULL(MAX(TRN_SEQ_NO),0)+1 FROM ClientLedger WHERE AccountID = @custkey;

                INSERT INTO ClientLedger
                    (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch,
                     Description, TransCode, TransactionDate, ReferenceNumber, ReferenceKey,
                     InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, ORNumber,
                     TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
                VALUES
                    (@TRNRetVat, @custkey, @custkey, @effectivitydate, @parmbranchcode,
                     @Particulars, 'CM-CLIENT-VAT', @effectivitydate, @parmpono, @invoiceno,
                     @invoiceno, 0, 0, ROUND(@totalgrossvat,2), 0, @invoiceno,
                     @parmuser, '*', 'Sales Return', ROUND(@totalgrossvat,2), 0, @ticketnumvat);

                UPDATE ReturnedOrderSummary SET TicketRefNoVAT = @ticketnumvat WHERE PONumber = @parmpono;
            END;

            IF ISNULL(@totalgrossvatex,0) <> 0
            BEGIN
                DECLARE @AmtRetVatEx dbo.tt_AmountBreakdown;
                DECLARE @TokRetVatEx dbo.tt_TokenResolution;
                DECLARE @FlgRetVatEx dbo.tt_ConditionFlags;

                INSERT @AmtRetVatEx VALUES
                    ('GROSS', ROUND(@totalgrossvatex,2)),
                    ('COST',  ROUND(ISNULL(@totalcostvatex,0),2));

                EXEC [dbo].[sp_PostCompoundTicketSales]
                    @Mnemonic        = 'CM-CLIENT-VATEX',
                    @TicketDate      = @effectivitydate,
                    @BranchCode      = @parmbranchcode,
                    @ReferenceNumber = @parmpono,
                    @ReferenceKey    = @invoiceno,
                    @Particulars     = @Particulars,
                    @Owner           = @custname,
                    @PreparedBy      = @parmuser,
                    @Status          = 'POSTED',
                    @Amounts         = @AmtRetVatEx,
                    @Tokens          = @TokRetVatEx,
                    @Flags           = @FlgRetVatEx,
                    @LedgerType      = NULL;

                SELECT TOP 1 @ticketnumvatex = TicketNumber
                FROM TicketMaster
                WHERE ReferenceNumber = @parmpono AND Mnemonic = 'CM-CLIENT-VATEX'
                ORDER BY TRY_CAST(TicketNumber AS INT) DESC;

                DECLARE @TRNRetVatEx DECIMAL(7,0);
                SELECT @TRNRetVatEx = ISNULL(MAX(TRN_SEQ_NO),0)+1 FROM ClientLedger WHERE AccountID = @custkey;

                INSERT INTO ClientLedger
                    (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch,
                     Description, TransCode, TransactionDate, ReferenceNumber, ReferenceKey,
                     InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, ORNumber,
                     TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
                VALUES
                    (@TRNRetVatEx, @custkey, @custkey, @effectivitydate, @parmbranchcode,
                     @Particulars, 'CM-CLIENT-VATEX', @effectivitydate, @parmpono, @invoiceno,
                     @invoiceno, 0, 0, ROUND(@totalgrossvatex,2), 0, @invoiceno,
                     @parmuser, '*', 'Sales Return', ROUND(@totalgrossvatex,2), 0, @ticketnumvatex);

                UPDATE ReturnedOrderSummary SET TicketRefNoVATEX = @ticketnumvatex WHERE PONumber = @parmpono;
            END;
        END

        DROP TABLE IF EXISTS #NewReturns;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        DROP TABLE IF EXISTS #NewReturns;

        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE(), @ErrSeverity INT = ERROR_SEVERITY();
        RAISERROR(@ErrMsg, @ErrSeverity, 1);
    END CATCH
END
GO
PRINT 'DEPLOYMENT COMPLETE: sp_ReturnSalesOrder rewritten, original preserved as sp_ReturnSalesOrder_OLD_08052026132558.';
