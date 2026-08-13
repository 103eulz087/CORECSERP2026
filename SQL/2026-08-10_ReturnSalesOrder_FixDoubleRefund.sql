SET NOCOUNT ON;
PRINT '=== sp_ReturnSalesOrder: fix double-refunding inventory on staged/partial returns ===';
GO
EXEC sp_rename 'dbo.sp_ReturnSalesOrder', 'sp_ReturnSalesOrder_OLD_08102026';
GO
SET QUOTED_IDENTIFIER ON;
GO
-- =============================================
-- Author:      Eulz Avancena (original); rewritten 2026-08-10
-- Description: Handles item-level Sales Order returns from the "For Delivery"
--              tab's Return Order screen (Orders/ReturnSalesOrder.cs). Supports
--              staged/partial returns -- a user can return some items now and
--              the rest later in a separate call (return-all-or-by-item via
--              checkboxes, per the screen's design).
--
-- CHANGELOG FROM sp_ReturnSalesOrder (legacy, now sp_ReturnSalesOrder_OLD_08102026):
--   [BUG] Step 4 (inventory refund) recomputed which DeliveryDetails lines to
--   refund from "ALL rows where isReturned=1 for this PONumber" -- a set that
--   only grows across calls. On a SECOND (or later) staged return for the same
--   PO, that re-included every PREVIOUSLY returned line too, so their FIFO
--   layers got flagged/refunded AGAIN and Inventory.Available was inflated by
--   an extra copy of each earlier return's quantity, every time. A single
--   full return didn't show it, since there was nothing already returned to
--   double up on the first time around, but any staged return sequence
--   corrupted stock counts silently.
--   FIX: Step 4 now scopes strictly to #NewReturns (this call's lines only),
--   matching the same "isErrorCorrect=0" double-refund guard already used by
--   sp_CancelDelivery for the equivalent STS scenario.
-- =============================================
CREATE PROCEDURE [dbo].[sp_ReturnSalesOrder]
    @parmbranchcode   char(3),
    @parmpono         varchar(10),
    @parmdevno        varchar(10),
    @parmuser         varchar(50),
    @parmreturnstatus varchar(30),
    @parmreason       varchar(930),
    @parmmachinename  varchar(50),
    @Lines            dbo.tt_ReturnSalesOrderLines READONLY
AS
BEGIN
    SET XACT_ABORT OFF;
    -- XACT_ABORT OFF (not ON) -- sp_PostCompoundTicketSales is called inside
    -- this transaction for the DELIVERED path; rollback is managed explicitly
    -- in CATCH (same rationale documented in sp_ConfirmOrder / sp_CreditMemo
    -- for nested-SP calls).
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
            INSERT INTO ReturnedOrderSummary (PONumber, InvoiceNo, BranchCode, TotalItem, TotalQtyDelivered, TotalAmount, EffectivityDate, DateAdded, PreparedBy, ReturnType, Reason)
            VALUES (@parmpono, @invoiceno, @parmbranchcode, @Ret_TotalItem, @Ret_TotalQty, @Ret_TotalAmt, @effectivitydate, GETDATE(), @parmuser, ' ', @parmreason);
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
        SET TotalItemSold = @Del_TotalItem,
            TotalItemReturned = @Ret_TotalItem,
            TotalQtyDelivered = @Del_TotalQty,
            TotalActualQty = @Del_TotalActual,
            Status = CASE WHEN @Del_TotalItem = 0
                        THEN 'RETURNED'
                     ELSE 'DELIVERED'
                     END
        WHERE PONumber = @parmpono;

        ---------------------------------------------------------------------------
        -- 4. UPDATE INVENTORY FIFO & MASTER INVENTORY
        --
        -- Scoped strictly to #NewReturns (THIS call's lines) -- not "every
        -- DeliveryDetails row that's isReturned=1 for this PO", which would
        -- re-include lines already refunded by an earlier staged return call
        -- and double-refund them. isErrorCorrect=0 guard mirrors the same
        -- fix already applied to sp_CancelDelivery for STS returns.
        ---------------------------------------------------------------------------
        UPDATE fifo
        SET fifo.isErrorCorrect = 1
        FROM InventoryDeliveryFIFO fifo
        INNER JOIN #NewReturns nr
            ON fifo.PONumber = nr.PONumber
           AND fifo.DevDetSeqNo = nr.SeqNo
        WHERE fifo.isErrorCorrect = 0;

        UPDATE inv
        SET inv.IsStock = 1,
            inv.Available = inv.Available + refund.QtyRefund
        FROM Inventory inv
        INNER JOIN (
            SELECT fifo.SequenceReferenceNumber, SUM(fifo.QtyDelivered) AS QtyRefund
            FROM InventoryDeliveryFIFO fifo
            INNER JOIN #NewReturns nr
                ON fifo.PONumber = nr.PONumber
               AND fifo.DevDetSeqNo = nr.SeqNo
            GROUP BY fifo.SequenceReferenceNumber
        ) refund ON inv.SequenceNumber = refund.SequenceReferenceNumber;

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
            SELECT @Charge_Total = ISNULL(TotalAmount,0)
            FROM ReturnedOrderSummary WITH(NOLOCK)
            WHERE PONumber = @parmpono AND BranchCode = @parmbranchcode;

            UPDATE TransactionChargeSales
            SET TotalAmount = TotalAmount-@Charge_Total,
                Balance = TotalAmount-@Charge_Total,
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
PRINT 'DEPLOYMENT COMPLETE: sp_ReturnSalesOrder rewritten, original preserved as sp_ReturnSalesOrder_OLD_08102026.';
