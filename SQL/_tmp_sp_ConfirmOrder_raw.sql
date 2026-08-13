
CREATE PROCEDURE [dbo].[sp_ConfirmOrder]
    @parmdevno       VARCHAR(20),
    @parmpono        VARCHAR(10),
    @preparedby      VARCHAR(30),
    @parmzerorated   BIT,
    @parmmachinename VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    -- NOTE: XACT_ABORT OFF (default) — we manage rollback explicitly in CATCH.
    -- XACT_ABORT ON would doom the transaction on any inner SP error,
    -- causing subsequent writes to fail with error 3930 "cannot write to log".
    -- With nested SP calls (sp_PostCompoundTicket), explicit CATCH is safer.

    DECLARE
        @custkey         CHAR(8),
        @custname        VARCHAR(100),
        @effectivitydate DATE,
        @invoicenumber   VARCHAR(10),
        @paymenttype     VARCHAR(30),
        @notes           VARCHAR(500),
        @term            INT,
        @parmbranchcode  CHAR(3),
        @refno           VARCHAR(10),
        @ticketnum       VARCHAR(20),
        @totalAmount     DECIMAL(18,2),
        @totalDiscount   DECIMAL(18,2),
        @totalVAT        DECIMAL(18,2),
        @totalVATSub     DECIMAL(18,2),
        @totalVATExempt  DECIMAL(18,2),
        @netAR           DECIMAL(18,2),
        @totalVATEXCost  DECIMAL(18,2),   -- SUM(QtySold*Cost) for VATEX items → COST leg
        @totalVATCost    DECIMAL(18,2),   -- SUM(QtySold*Cost) for VAT items   → COST leg
        @Particulars     VARCHAR(6999);

    BEGIN TRY
        BEGIN TRAN;

        -- ── Step 1: Fetch BranchCode ─────────────────────────────────
        SELECT @parmbranchcode = BranchCode
        FROM   PurchaseOrderSummary WHERE PONumber = @parmpono;

        -- ── Guard: prevent double-confirmation of same PO ──────────────
        -- If BatchSalesSummary already has this PO it was confirmed before.
        -- Duplicate run would cause PK violations on TransactionChargeSales
        -- and BatchSalesSummary → doomed transaction → error 3930.
        IF EXISTS (SELECT 1 FROM BatchSalesSummary
                   WHERE ReferenceNo=@parmpono AND BranchCode=@parmbranchcode)
            THROW 58001, 'This PO has already been confirmed. Cannot confirm twice.', 1;

        -- ── Step 2: Status updates ────────────────────────────────────
        UPDATE PurchaseOrderSummary SET Status='DELIVERED',DateApproved=GETDATE() WHERE PONumber=@parmpono;
        UPDATE DeliverySummary      SET Status='DELIVERED' WHERE PONumber=@parmpono;

        UPDATE dd SET
            dd.Status   = 'DELIVERED',
            dd.Variance = dd.QtyDelivered - ISNULL(dd.ActualQty, 0)
        FROM DeliveryDetails dd
        WHERE dd.DeliveryNo = @parmdevno AND dd.PONumber = @parmpono;

        -- ── Step 3: Fetch header info ──────────────────────────────────
        SELECT TOP 1
            @effectivitydate = EffectivityDate,
            @invoicenumber   = InvoiceNo
        FROM DeliverySummary WHERE PONumber = @parmpono;

        SELECT @custkey=Customer, @paymenttype=PaymentType, @notes=Notes
        FROM   PurchaseOrderSummary WHERE PONumber=@parmpono;

        SELECT @custname=CustomerName,@term = ISNULL(Term, 0) FROM Customers WHERE CustomerKey=@custkey;

        -- ── Step 4: BatchSalesDetails ─────────────────────────────────
        -- FIX A: ISNULL on ActualQty, SellingPrice, Cost — prevents NULL
        -- propagation into SubTotal, TaxTotal, TotalAmount columns.
        INSERT INTO BatchSalesDetails (
            BranchCode, ReferenceNo, CashierTransNo, ProductCode, CategoryCode,
            Barcode, Description, Cost, OriginalSellingPrice, SellingPrice,
            QtySold, PrevQty, UnitMeasure, DiscountRate, DiscountTotal,
            ChargeRate, ChargeTotal, TaxRate, TaxTotal, SubTotal, Income,
            isHold, isConfirmed, isCancelled, isVoid, isErrorCorrect, isVat,
            HoldBy, CancelledBy, VoidBy, ProcessedBy,
            TotalAmount, Status, DateOrder, isUpload, isPosted, isCosting, MachineUsed
        )
        SELECT
            @parmbranchcode,
            @parmpono,
            99999,
            dd.ProductNo,
            ISNULL(p.ProductCategoryCode, ''),
            ISNULL(dd.BarcodeNo, ''),
            dd.ProductName,
            ISNULL(dd.Cost, 0),                          -- FIX A
            ISNULL(dd.SellingPrice, 0),                  -- FIX A
            ISNULL(dd.SellingPrice, 0),                  -- FIX A
            ISNULL(dd.ActualQty, 0),                     -- FIX A
            0,
            'Kg',
            0,
            -- Credit memo variance adjustments
            CASE WHEN ISNULL(dd.Variance,0) > 0 AND dd.isCreditMemo=1
                 THEN ROUND(dd.Variance * ISNULL(dd.SellingPrice,0), 2) ELSE 0 END,
            0,
            CASE WHEN ISNULL(dd.Variance,0) < 0 AND dd.isCreditMemo=1
                 THEN ROUND(ABS(dd.Variance) * ISNULL(dd.SellingPrice,0), 2) ELSE 0 END,
            CASE WHEN dd.isVat=1 THEN 0.12 ELSE 0 END,
            -- TaxTotal: VAT portion from tax-inclusive selling price
            CASE WHEN dd.isVat=1
                 THEN ROUND((ISNULL(dd.ActualQty,0) * ISNULL(dd.SellingPrice,0)) / 1.12 * 0.12, 2)
                 ELSE 0 END,
            -- SubTotal: VAT-exclusive base
            CASE WHEN dd.isVat=1
                 THEN ROUND((ISNULL(dd.ActualQty,0) * ISNULL(dd.SellingPrice,0)) / 1.12, 2)
                 ELSE ROUND(ISNULL(dd.ActualQty,0) * ISNULL(dd.SellingPrice,0), 2) END,
            0,  -- Income (margin — computed separately if needed)
            0, 1, 0, 0, 0,
            ISNULL(dd.isVat, 0),
            '', '', '',
            @preparedby,
            -- TotalAmount: always the gross (ActualQty × SellingPrice)
            ROUND(ISNULL(dd.ActualQty,0) * ISNULL(dd.SellingPrice,0), 2),
            'SOLD',
            @effectivitydate,
            0, 0, 0, ''
        FROM DeliveryDetails dd
        LEFT JOIN Products p ON dd.ProductNo = p.ProductCode
                             AND p.BranchCode = @parmbranchcode
        WHERE dd.DeliveryNo = @parmdevno
          AND dd.PONumber   = @parmpono
          AND ISNULL(dd.isReturned, 0) = 0;

        -- ── Step 5: BatchSalesSummary (single-step) ────────────────────
        INSERT INTO [dbo].[BatchSalesSummary] (
            BranchCode, ReferenceNo, CashierTransNo, CustomerNo, Invoice,
            TotalItem, TotalItemSold,
            TotalTax, TotalKilos, TotalAmount, SubTotal,
            TotalVATSale, TotalVATExemptSale, TotalVatableSale, ZeroRatedSale,
            PaymentType, Transdate, PreparedBy, MachineUsed,
            Status, isUpload, isPosted
        )
        SELECT
            @parmbranchcode, @parmpono, 99999, @custkey, @invoicenumber,
            COUNT(*), COUNT(*),
            ISNULL(SUM(TaxTotal), 0),
            ISNULL(SUM(QtySold), 0),
            ISNULL(SUM(TotalAmount), 0),
            ISNULL(SUM(SubTotal), 0),
            -- TotalVATSale = the VAT tax amount collected
            ISNULL(SUM(CASE WHEN isVat=1 THEN TaxTotal ELSE 0 END), 0),
            -- TotalVATExemptSale = full amount of exempt items
            ISNULL(SUM(CASE WHEN isVat=0 THEN TotalAmount ELSE 0 END), 0),
            -- TotalVatableSale = VAT-exclusive base of vatable items
            ISNULL(SUM(CASE WHEN isVat=1 THEN SubTotal ELSE 0 END), 0),
            -- ZeroRatedSale (fix: SubTotal is already VAT-exclusive, no extra /1.12)
            ISNULL(SUM(CASE WHEN isVat=1 AND @parmzerorated=1 THEN SubTotal ELSE 0 END), 0),
            @paymenttype, @effectivitydate, @preparedby, @parmmachinename,
            'SOLD', 1, 0
        FROM BatchSalesDetails
        WHERE ReferenceNo=@parmpono AND BranchCode=@parmbranchcode;

        -- Capture totals for AR + GL ticket
        SELECT
            @totalAmount    = ISNULL(TotalAmount, 0),
            @totalDiscount  = ISNULL(TotalDiscountAmount, 0),
            @totalVAT       = ISNULL(TotalVATSale, 0),
            @totalVATSub    = ISNULL(TotalVatableSale, 0),
            @totalVATExempt = ISNULL(TotalVATExemptSale, 0)
        FROM BatchSalesSummary
        WHERE ReferenceNo=@parmpono AND BranchCode=@parmbranchcode;

        SET @netAR = @totalAmount - @totalDiscount;

        -- Capture COST totals for the COST legs in JournalEntryMapping
        -- (Seq 3: DR COS / Seq 4: CR Inventory — both use AmountType='COST')
        SELECT
            @totalVATEXCost = ISNULL(SUM(CASE WHEN isVat=0 OR isVat IS NULL
                                          THEN ROUND(QtySold * ISNULL(Cost,0), 2)
                                          ELSE 0 END), 0),
            @totalVATCost   = ISNULL(SUM(CASE WHEN isVat=1
                                          THEN ROUND(QtySold * ISNULL(Cost,0), 2)
                                          ELSE 0 END), 0)
        FROM BatchSalesDetails
        WHERE ReferenceNo = @parmpono
          AND BranchCode  = @parmbranchcode;

        -- ── Step 6: TransactionChargeSalesDetails ─────────────────────
        -- PURPOSE: Product-level sales reporting detail.
        --   One row per product per TRANSACTION TYPE — not per JEM leg.
        --   The GL double-entry (DR/CR) is handled by sp_PostCompoundTicket.
        --   This table is for sales analysis reports only.
        --
        -- WHY NOT JOIN JournalEntryMapping:
        --   JEM has N legs per mnemonic. Joining to it multiplies product rows
        --   by the leg count (2 products × 2 VATEX legs = 4 identical-looking rows).
        --   TransactionChargeSalesDetails has no DebitCredit column — DR and CR
        --   legs of the same VATEX item produce rows with the same amount, which
        --   looks like duplication. Using purpose-built TransCodes avoids this.
        --
        -- ROW COUNTS PER PRODUCT:
        --   VATEX item → 2 rows: SI-VATEX (revenue) + COGS-VATEX (cost)
        --   VAT item   → 3 rows: SI-VAT (base) + SI-VAT-OUT (tax) + COGS-VAT (cost)
        --   Discount   → 1 extra row per product if DiscountTotal > 0
        INSERT INTO TransactionChargeSalesDetails (
            SeqNo, BranchCode, ReferenceNo, InvoiceNo, TransactionDate,
            Product, Quantity, Cost, SellingPrice, TotalAmount,
            SKU, TransCode, Type, ErrorTag
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY bsd.ProductCode, t.SortOrder),
            @parmbranchcode,
            @parmpono,
            @invoicenumber,
            @effectivitydate,
            bsd.ProductCode,
            bsd.QtySold,
            bsd.Cost,
            bsd.SellingPrice,
            t.Amount,
            bsd.Barcode,
            t.TransCode,
            t.TransType,
            0
        FROM BatchSalesDetails bsd
        -- Purpose-built transaction types per product
        -- No JOIN to JEM — these codes are fixed for this reporting table
        CROSS APPLY (
            -- ── VATEX items: 2 rows ───────────────────────────────────────
            -- SELECT...WHERE is valid here; VALUES()...WHERE is NOT (Msg 156)
            SELECT 1, 'SI-VATEX',   'SALES VAT EXEMPT',
                   bsd.TotalAmount
            WHERE (bsd.isVat = 0 OR bsd.isVat IS NULL)
              AND bsd.TotalAmount > 0
            UNION ALL
            SELECT 2, 'COGS-VATEX', 'COST OF SALES VATEX',
                   ROUND(bsd.QtySold * ISNULL(bsd.Cost, 0), 2)
            WHERE (bsd.isVat = 0 OR bsd.isVat IS NULL)
              AND ROUND(bsd.QtySold * ISNULL(bsd.Cost, 0), 2) > 0

            UNION ALL
            -- ── VAT items: 3 rows ─────────────────────────────────────────
            SELECT 1, 'SI-VAT',     'SALES VAT',
                   bsd.SubTotal
            WHERE bsd.isVat = 1
              AND bsd.SubTotal > 0
            UNION ALL
            SELECT 2, 'SI-VAT-OUT', 'VAT OUTPUT TAX',
                   bsd.TaxTotal
            WHERE bsd.isVat = 1
              AND bsd.TaxTotal > 0
            UNION ALL
            SELECT 3, 'COGS-VAT',   'COST OF SALES VAT',
                   ROUND(bsd.QtySold * ISNULL(bsd.Cost, 0), 2)
            WHERE bsd.isVat = 1
              AND ROUND(bsd.QtySold * ISNULL(bsd.Cost, 0), 2) > 0

            UNION ALL
            -- ── Discount row: only when credit memo variance applies ───────
            SELECT 4, 'SI-DISC',    'DISCOUNT',
                   bsd.DiscountTotal
            WHERE bsd.DiscountTotal > 0
        ) t (SortOrder, TransCode, TransType, Amount)
        WHERE bsd.ReferenceNo = @parmpono
          AND bsd.BranchCode  = @parmbranchcode;

        -- ── Step 7: Reference numbers ──────────────────────────────────
        EXEC GetReferenceNumber @refno OUTPUT;

        -- ── Step 8: TransactionChargeSales (AR invoice) ────────────────
        INSERT INTO [dbo].[TransactionChargeSales] (
            CustomerKey, BranchCode, TransactionDate, ReferenceNo, InvoiceNo,
            TotalAmount, PaymentType, Balance, AmountPaid, PayStatus, DueDate, Remarks
        )
        VALUES (
            @custkey, @parmbranchcode, @effectivitydate,
            @parmpono,    -- consistent key: PO number as AR reference
            @invoicenumber,
            @netAR, @paymenttype, @netAR, 0,
            'UNPAID', DATEADD(DAY, @term, @effectivitydate),
            @notes
        );

        -- ── Step 9: GL Tickets via sp_PostCompoundTicket ───────────────
        -- ClientLedger is now written INSIDE sp_PostCompoundTicket
        -- when @LedgerType='CLIENT' — NOT written here anymore.
        -- (FIX D: removed direct ClientLedger INSERT from this SP)
        SET @Particulars =
            'SALES INVOICE | Customer: ' + ISNULL(@custname,'')
            + ' | PO: '      + @parmpono
            + ' | Invoice: ' + ISNULL(@invoicenumber,'')
            + CASE WHEN LEN(ISNULL(@notes,''))>0
                   THEN ' | '+LEFT(@notes,150) ELSE '' END;

        -- SI-VAT ticket (only if there are vatable items)
        IF @totalVATSub > 0 OR @totalVAT > 0
        BEGIN
            DECLARE @AmtVAT  dbo.tt_AmountBreakdown;
            DECLARE @TokVAT  dbo.tt_TokenResolution;
            DECLARE @FlgVAT  dbo.tt_ConditionFlags;

            INSERT @AmtVAT VALUES
                ('GROSS',  @totalVATSub + @totalVAT),  -- Seq1 DR AR (revenue)
                ('NET',    @totalVATSub),               -- Seq2 CR Sales VAT excl
                ('VAT',    @totalVAT),                  -- Seq3 CR Output VAT
                ('VATEX',  0),
                ('COST',   @totalVATCost);              -- DR COS + CR Inventory (COGS)

            -- {AR}, {SALES}, {VATOUT} must exist in your JournalEntryMapping
            -- or be resolved via a branch GL account lookup.
            -- Adjust the hardcoded fallback codes to match your COA.
            INSERT @TokVAT VALUES
                ('{AR}',     '101030101'),   -- AR Trade — adjust to your COA
                ('{SALES}',  '401'),         -- Sales VAT revenue account
                ('{VATOUT}', '20201');       -- Output VAT payable

            INSERT @FlgVAT VALUES
                ('HasVAT',      1),
                ('HasVATEX',    0),
                ('IsZeroRated', CASE WHEN @parmzerorated=1 THEN 1 ELSE 0 END);

            EXEC [dbo].[sp_PostCompoundTicketSales]
                @Mnemonic        = 'SI-VAT',
                @TicketDate      = @effectivitydate,
                @BranchCode      = @parmbranchcode,
                @ReferenceNumber = @parmpono,
                @ReferenceKey    = @invoicenumber,
                @Particulars     = @Particulars,
                @Owner           = @custname,
                @PreparedBy      = @preparedby,
                @Status          = 'POSTED',
                @Amounts         = @AmtVAT,
                @Tokens          = @TokVAT,
                @Flags           = @FlgVAT,
                @LedgerType      = 'CLIENT',    -- writes ClientLedger inside SP
                @LedgerEntityID  = @custkey,
                @LedgerInvoiceNo = @invoicenumber,
                @LedgerBatchRef  = 0,
                @LedgerSeqRef    = 0;
        END;

        -- SI-VATEX ticket (only if there are exempt items)
        IF @totalVATExempt > 0
        BEGIN
            DECLARE @AmtVATEX dbo.tt_AmountBreakdown;
            DECLARE @TokVATEX dbo.tt_TokenResolution;
            DECLARE @FlgVATEX dbo.tt_ConditionFlags;

            INSERT @AmtVATEX VALUES
                ('GROSS',  @totalVATExempt),     -- Seq1 DR AR + Seq2 CR Sales (revenue)
                ('NET',    @totalVATExempt),
                ('VAT',    0),
                ('VATEX',  @totalVATExempt),
                ('COST',   @totalVATEXCost);      -- Seq3 DR COS + Seq4 CR Inventory (COGS)

            INSERT @TokVATEX VALUES
                ('{AR}',      '101030101'),  -- AR Trade
                ('{SALESEX}', '401');        -- Sales VATEX — use 402 if separate

            INSERT @FlgVATEX VALUES
                ('HasVAT',      0),
                ('HasVATEX',    1),
                ('IsZeroRated', 0);

            EXEC [dbo].[sp_PostCompoundTicketSales]
                @Mnemonic        = 'SI-VATEX',
                @TicketDate      = @effectivitydate,
                @BranchCode      = @parmbranchcode,
                @ReferenceNumber = @parmpono,
                @ReferenceKey    = @invoicenumber,
                @Particulars     = @Particulars,
                @Owner           = @custname,
                @PreparedBy      = @preparedby,
                @Status          = 'POSTED',
                @Amounts         = @AmtVATEX,
                @Tokens          = @TokVATEX,
                @Flags           = @FlgVATEX,
                @LedgerType      = 'CLIENT',
                @LedgerEntityID  = @custkey,
                @LedgerInvoiceNo = @invoicenumber,
                @LedgerBatchRef  = 0,
                @LedgerSeqRef    = 0;
        END;

        -- ── Step 10: Mark PO processed ─────────────────────────────────
        UPDATE PurchaseOrderSummary SET isProcess=1 WHERE PONumber=@parmpono;

        COMMIT TRAN;

    END TRY
    BEGIN CATCH
        -- XACT_STATE()=-1: doomed (constraint/fatal error) → must ROLLBACK
        -- XACT_STATE()= 1: active → ROLLBACK cleanly
        -- XACT_STATE()= 0: already rolled back → nothing to do
        IF XACT_STATE() <> 0
            ROLLBACK TRAN;

        -- Re-raise the original error with full detail for the caller / SSMS
        DECLARE @EMsg  NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ESev  INT            = ERROR_SEVERITY();
        DECLARE @ESt   INT            = ERROR_STATE();
        DECLARE @ELine INT            = ERROR_LINE();
        DECLARE @EProc NVARCHAR(128)  = ISNULL(ERROR_PROCEDURE(), 'sp_ConfirmOrder');
        RAISERROR('Error in %s (line %d): %s', @ESev, @ESt, @EProc, @ELine, @EMsg);
    END CATCH;
END;
