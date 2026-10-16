-- =============================================
-- =============================================
CREATE    PROCEDURE [dbo].[sp_CreditMemo]
    @parmpono varchar(10),
    @parmuser varchar(30),
    @parmstat varchar(30),
    @Lines    dbo.tt_CreditMemoLines READONLY
AS
BEGIN
    SET NOCOUNT ON;
    -- XACT_ABORT OFF (default) -- sp_PostCompoundTicketSales is called inside this
    -- transaction; rollback is managed explicitly in CATCH (same rationale documented
    -- in sp_ConfirmOrder for nested-SP calls).

    DECLARE
        @custkey                CHAR(8),
        @custname                VARCHAR(100),
        @custbranch              CHAR(3),
        @effectivitydate         DATE,
        @invoiceno               VARCHAR(20),
        @Particulars             VARCHAR(6999),
        @totaldiscount           MONEY,
        @totaldiscountvatable    MONEY,
        @totaldiscountvatexempt  MONEY,
        @totalvatablesales       MONEY,
        @totalvatoutput          MONEY,
        @totalvatcost            MONEY,
        @totalvatexcost          MONEY,
        @ticketnumvat            VARCHAR(10) = ' ',
        @ticketnumvatex          VARCHAR(10) = ' ';

    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM @Lines)
            THROW 59002, 'No lines submitted for this Credit Memo.', 1;

        UPDATE dd
           SET dd.ActualQty    = l.ActualQty,
               dd.Variance     = dd.QtyDelivered - l.ActualQty,
               dd.isCreditMemo = 1
        FROM DeliveryDetails dd
        JOIN @Lines l
          ON dd.SeqNo     = l.SeqNo
         AND dd.ProductNo = l.ProductNo
        WHERE dd.PONumber = @parmpono
          AND dd.isCreditMemo = 0 
          AND dd.isReturned = 0;  -- don't allow credit memos on returned items (legacy guard)

        SELECT dd.DeliveryNo, dd.ReferenceNumber, dd.SeqNo, dd.ProductNo, dd.ProductName,
               dd.QtyDelivered, dd.ActualQty, dd.Variance, dd.SellingPrice, dd.Cost, dd.isVat
        INTO #CMBatch
        FROM DeliveryDetails dd
        JOIN @Lines l
          ON dd.SeqNo     = l.SeqNo
         AND dd.ProductNo = l.ProductNo
        WHERE dd.PONumber = @parmpono
          AND ISNULL(dd.Variance, 0) <> 0
          AND NOT EXISTS (
              SELECT 1 FROM CreditMemo cm
              WHERE cm.PONumber         = dd.PONumber
                AND cm.ProductCode      = dd.ProductNo
                AND cm.DeliveryNo       = dd.DeliveryNo
                AND cm.ReferenceNumber  = dd.ReferenceNumber
                AND cm.SeqNo            = dd.SeqNo
          )
          AND dd.isReturned = 0;  -- don't allow credit memos on returned items (legacy guard)

        IF NOT EXISTS (SELECT 1 FROM #CMBatch)
            THROW 59001, 'No new Credit Memo variance to process for this PO (already processed, or ActualQty unchanged).', 1;

        -- ── Keep DeliverySummary in sync (whole-PO recompute; cheap, always correct) ─
        UPDATE DeliverySummary
           SET TotalActualQty         = (SELECT SUM(ActualQty) FROM DeliveryDetails WHERE PONumber=@parmpono AND isReturned=0),
               TotalVarianceVat       = (SELECT SUM(Variance) FROM DeliveryDetails WHERE PONumber=@parmpono AND isVat=1 AND isReturned=0),
               TotalVarianceVatExempt = (SELECT SUM(Variance) FROM DeliveryDetails WHERE PONumber=@parmpono AND isVat=0 AND isReturned=0)
         WHERE PONumber = @parmpono;

        -- ── Batch totals (this run only) ───────────────────────────────────
        SELECT
            @totaldiscount          = SUM(ISNULL(Variance*SellingPrice,0)),
            @totaldiscountvatable   = SUM(CASE WHEN isVat=1 THEN ISNULL(Variance*SellingPrice,0) ELSE 0 END),
            @totaldiscountvatexempt = SUM(CASE WHEN isVat=0 THEN ISNULL(Variance*SellingPrice,0) ELSE 0 END),
            @totalvatcost           = SUM(CASE WHEN isVat=1 THEN ISNULL(Variance*Cost,0) ELSE 0 END),
            @totalvatexcost         = SUM(CASE WHEN isVat=0 THEN ISNULL(Variance*Cost,0) ELSE 0 END)
        FROM #CMBatch;

        SET @totalvatablesales = ISNULL(@totaldiscountvatable,0) / 1.12;
        SET @totalvatoutput    = @totalvatablesales * 0.12;

        SELECT @custkey = Customer, @effectivitydate = EffectivityDate
        FROM PurchaseOrderSummary WHERE PONumber = @parmpono;

        SELECT @invoiceno = InvoiceNo FROM DeliverySummary WHERE PONumber = @parmpono;

        SELECT @custbranch = BranchCode, @custname = CustomerName
        FROM Customers WHERE CustomerKey = @custkey;

        SET @custbranch = '888';

        SET @Particulars =
            'CREDIT MEMO | Customer: ' + ISNULL(@custname,'')
            + ' | PO: ' + @parmpono
            + ' | Invoice: ' + ISNULL(@invoiceno,'');

        --IF @parmstat = 'DELIVERED'
        --BEGIN
        --    -- ── VATable reversal: mirror-reverses SI-VAT ───────────────────
        --    IF ISNULL(@totaldiscountvatable,0) <> 0
        --    BEGIN
        --        DECLARE @AmtCMVat dbo.tt_AmountBreakdown;
        --        DECLARE @TokCMVat dbo.tt_TokenResolution;
        --        DECLARE @FlgCMVat dbo.tt_ConditionFlags;

        --        INSERT @AmtCMVat VALUES
        --            ('GROSS', ROUND(@totaldiscountvatable,2)),
        --            ('NET',   ROUND(@totalvatablesales,2)),
        --            ('VAT',   ROUND(@totalvatoutput,2)),
        --            ('VATEX', 0),
        --            ('COST',  ROUND(ISNULL(@totalvatcost,0),2));

        --        INSERT @FlgCMVat VALUES ('HasVAT', 1), ('HasVATEX', 0);

        --        EXEC [dbo].[sp_PostCompoundTicketSales]
        --            @Mnemonic        = 'CM-CLIENT-VAT',
        --            @TicketDate      = @effectivitydate,
        --            @BranchCode      = @custbranch,
        --            @ReferenceNumber = @parmpono,
        --            @ReferenceKey    = @invoiceno,
        --            @Particulars     = @Particulars,
        --            @Owner           = @custname,
        --            @PreparedBy      = @parmuser,
        --            @Status          = 'POSTED',
        --            @Amounts         = @AmtCMVat,
        --            @Tokens          = @TokCMVat,
        --            @Flags           = @FlgCMVat,
        --            @LedgerType      = NULL;   -- ClientLedger written below (Credit side)

        --        SELECT TOP 1 @ticketnumvat = TicketNumber
        --        FROM TicketMaster
        --        WHERE ReferenceNumber = @parmpono AND Mnemonic = 'CM-CLIENT-VAT'
        --        ORDER BY TRY_CAST(TicketNumber AS INT) DESC;

        --        DECLARE @TRNVat DECIMAL(7,0);
        --        SELECT @TRNVat = ISNULL(MAX(TRN_SEQ_NO),0)+1 FROM ClientLedger WHERE AccountID = @custkey;

        --        INSERT INTO ClientLedger
        --            (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch,
        --             Description, TransCode, TransactionDate, ReferenceNumber, ReferenceKey,
        --             InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, ORNumber,
        --             TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
        --        VALUES
        --            (@TRNVat, @custkey, @custkey, @effectivitydate, @custbranch,
        --             @Particulars, 'CM-CLIENT-VAT', @effectivitydate, @parmpono, @invoiceno,
        --             @invoiceno, 0, 0, ROUND(@totaldiscountvatable,2), 0, @invoiceno,
        --             @parmuser, '*', 'Credit Memo', ROUND(@totaldiscountvatable,2), 0, @ticketnumvat);
        --    END;

        --    -- ── VAT-exempt reversal: mirror-reverses SI-VATEX ───────────────
        --    IF ISNULL(@totaldiscountvatexempt,0) <> 0
        --    BEGIN
        --        DECLARE @AmtCMVatEx dbo.tt_AmountBreakdown;
        --        DECLARE @TokCMVatEx dbo.tt_TokenResolution;
        --        DECLARE @FlgCMVatEx dbo.tt_ConditionFlags;

        --        INSERT @AmtCMVatEx VALUES
        --            ('GROSS', ROUND(@totaldiscountvatexempt,2)),
        --            ('COST',  ROUND(ISNULL(@totalvatexcost,0),2));

        --        EXEC [dbo].[sp_PostCompoundTicketSales]
        --            @Mnemonic        = 'CM-CLIENT-VATEX',
        --            @TicketDate      = @effectivitydate,
        --            @BranchCode      = @custbranch,
        --            @ReferenceNumber = @parmpono,
        --            @ReferenceKey    = @invoiceno,
        --            @Particulars     = @Particulars,
        --            @Owner           = @custname,
        --            @PreparedBy      = @parmuser,
        --            @Status          = 'POSTED',
        --            @Amounts         = @AmtCMVatEx,
        --            @Tokens          = @TokCMVatEx,
        --            @Flags           = @FlgCMVatEx,
        --            @LedgerType      = NULL;

        --        SELECT TOP 1 @ticketnumvatex = TicketNumber
        --        FROM TicketMaster
        --        WHERE ReferenceNumber = @parmpono AND Mnemonic = 'CM-CLIENT-VATEX'
        --        ORDER BY TRY_CAST(TicketNumber AS INT) DESC;

        --        DECLARE @TRNVatEx DECIMAL(7,0);
        --        SELECT @TRNVatEx = ISNULL(MAX(TRN_SEQ_NO),0)+1 FROM ClientLedger WHERE AccountID = @custkey;

        --        INSERT INTO ClientLedger
        --            (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch,
        --             Description, TransCode, TransactionDate, ReferenceNumber, ReferenceKey,
        --             InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, ORNumber,
        --             TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
        --        VALUES
        --            (@TRNVatEx, @custkey, @custkey, @effectivitydate, @custbranch,
        --             @Particulars, 'CM-CLIENT-VATEX', @effectivitydate, @parmpono, @invoiceno,
        --             @invoiceno, 0, 0, ROUND(@totaldiscountvatexempt,2), 0, @invoiceno,
        --             @parmuser, '*', 'Credit Memo', ROUND(@totaldiscountvatexempt,2), 0, @ticketnumvatex);
        --    END;
        --END
        --ELSE
        --BEGIN
        --    -- Not yet confirmed: sp_ConfirmOrder hasn't posted anything for this PO
        --    -- yet, so there is nothing to reverse -- ledger note only (matches legacy).
        --    IF ISNULL(@totaldiscount,0) <> 0
        --    BEGIN
        --        DECLARE @TRNPre DECIMAL(7,0);
        --        SELECT @TRNPre = ISNULL(MAX(TRN_SEQ_NO),0)+1 FROM ClientLedger WHERE AccountID = @custkey;

        --        INSERT INTO ClientLedger
        --            (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch,
        --             Description, TransCode, TransactionDate, ReferenceNumber, ReferenceKey,
        --             InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, ORNumber,
        --             TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
        --        VALUES
        --            (@TRNPre, @custkey, @custkey, CAST(GETDATE() AS date), @custbranch,
        --             'Credit Memo Adjustment (pre-confirm)', 'ADJ', CAST(GETDATE() AS date),
        --             @parmpono, @parmpono, 'NON', 0, 0, ROUND(@totaldiscount,2), 0, 'NON',
        --             @parmuser, '*', 'Credit Memo', ROUND(@totaldiscount,2), 0, ' ');
        --    END;
        --END;

        ---- ── AR adjustment (delta, not overwrite; SUM fixes the multi-row crash) ─
        --UPDATE TransactionChargeSales
        --   SET DiscountAmount = ISNULL(DiscountAmount,0) + ISNULL(@totaldiscount,0),
        --       Balance        = Balance - ISNULL(@totaldiscount,0)
        -- WHERE CustomerKey = @custkey
        --   AND ReferenceNo = @parmpono
        --   AND InvoiceNo   = @invoiceno;

        -- ── Audit trail (also drives the re-run guard above on future calls) ──
        INSERT INTO CreditMemo
            (PONumber, ProductCode, Description, Qty, ActualQty, Variance,
             SellingPrice, TotalAmount, DiscountAmount, TicketRefNo, DateAdded, ExecuteBy,
             DeliveryNo, ReferenceNumber, SeqNo)
        SELECT
            @parmpono, ProductNo, ProductName, QtyDelivered, ActualQty, Variance,
            SellingPrice, (ActualQty*SellingPrice), (Variance*SellingPrice),
            CASE WHEN isVat=1 THEN @ticketnumvat ELSE @ticketnumvatex END,
            CAST(GETDATE() AS date), @parmuser,
            DeliveryNo, ReferenceNumber, SeqNo
        FROM #CMBatch;

        DROP TABLE IF EXISTS #CMBatch;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        DROP TABLE IF EXISTS #CMBatch;

        DECLARE @EMsg  NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ESev  INT            = ERROR_SEVERITY();
        DECLARE @ESt   INT            = ERROR_STATE();
        DECLARE @ELine INT            = ERROR_LINE();
        DECLARE @EProc NVARCHAR(128)  = ISNULL(ERROR_PROCEDURE(), 'sp_CreditMemo');
        RAISERROR('Error in %s (line %d): %s', @ESev, @ESt, @EProc, @ELine, @EMsg);
    END CATCH;
END;
