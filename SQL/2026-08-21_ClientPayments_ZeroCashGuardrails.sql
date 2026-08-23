SET NOCOUNT ON;
PRINT '=== sp_AddPaymentClient: zero-net-cash guardrails (EWT-only / discount-only postings) ===';
GO

-- =============================================================
-- CONTEXT: ClientPaymentsDevExAcctg.cs is being changed so Debit GL Code /
-- Control No / CR No are only mandatory when the payment being submitted has
-- a real net cash amount (totalAmtPaid > 0). Scenario: an invoice was
-- already partially paid (net cash) weeks ago; the client's 2307 form only
-- arrives later, so a separate, later payment records ONLY the EWT amount
-- against the remaining balance - net cash for that transaction is exactly
-- 0, so there is no bank/cash leg to post and no receipt reference to give.
--
-- Investigated dbo.JournalEntryMapping (Origin='OR') before changing
-- anything: every mnemonic's {BANK} leg (AmountType NET/NET_OFFSET/
-- NET_OVERPAY) is UNCONDITIONAL - it is present in #Computed even when its
-- computed Amount is 0. Today that is harmless only because Debit GL Code is
-- currently mandatory in the UI, so @BankGLCode always resolves to a real
-- account. Once the UI relaxes that requirement for zero-cash postings,
-- @BankGLCode can resolve blank ('') and this SP would otherwise insert a
-- TicketDetails row with AccountCode='' - a phantom, unreferenceable GL leg.
--
-- Proven safe to just drop zero-amount legs instead of trying to resolve a
-- fallback account: GROSS can never be 0 (this SP already THROWs on
-- @Gross = 0), and every deduction leg (EWT/Discount/Offset/Overpay MIRROR
-- legs) is gated by its own HasX/> 0 condition, so it is never selected into
-- #Computed at 0 to begin with. The ONLY leg that can organically compute to
-- exactly 0 is the {BANK}-mapped NET/NET_OFFSET/NET_OVERPAY leg - exactly
-- the one we want gone when there's no cash movement.
--
-- Three changes, all additive/subtractive - no change to amounts computed,
-- to the mnemonic matrix, or to how TransactionChargeSales/ClientLedger are
-- updated:
--   1. Guardrail: THROW if a real net cash amount has nowhere to post
--      (defense-in-depth - the UI already blocks this, this protects the SP
--      itself against any other/future caller).
--   2. Skip zero-amount legs when inserting into TicketDetails.
--   3. Skip the BankStatementRecon DIT insert (and the header lookup that
--      feeds it) when there's no cash to reconcile.
-- sp_ReversePaymentClient needs NO changes - it only mirrors whatever is
-- already sitting in TicketDetails/BankStatementRecon for a ReferenceNumber,
-- so if a zero leg/DIT was never posted there is nothing to reverse.
-- =============================================================

-- Same-day draft amendment: sp_AddPaymentClient_OLD_08212026 already holds
-- the ORIGINAL pre-2026-08-21 version from the first deployment of this
-- file today. This file has since been revised (negative-@BankCash guard
-- added) before ever touching real data, so re-running just replaces
-- today's still-draft version in place rather than stacking a second,
-- redundant backup - re-renaming to the same _OLD_08212026 suffix would
-- collide with that first backup.
IF OBJECT_ID('dbo.sp_AddPaymentClient_OLD_08212026', 'P') IS NULL
    AND OBJECT_ID('dbo.sp_AddPaymentClient', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_AddPaymentClient', 'sp_AddPaymentClient_OLD_08212026';
ELSE IF OBJECT_ID('dbo.sp_AddPaymentClient', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_AddPaymentClient;
GO

-- ============================================================
--  sp_AddPaymentClient
--  Project : CORECSJFC2026
-- ============================================================
-- CHANGELOG:
-- [1]-[8] see sp_AddPaymentClient_OLD_08212026 (prior "FINAL VERSION",
--     2026-06-27 base + 2026-08-02 NetOverpay fix) for full history.
--
-- 2026-08-21: [9] Zero-net-cash guardrails (see file header comment above):
--     THROW if real cash has no GL account to post to; skip zero-amount
--     legs in TicketDetails; skip the BankStatementRecon DIT insert when
--     there's no cash to reconcile. Supports EWT-only/discount-only
--     postings (e.g. recording a 2307-backed EWT weeks after the cash
--     portion of an invoice was already paid) without leaving a
--     blank-account or phantom $0 row in the ledger.
-- ============================================================
CREATE PROCEDURE [dbo].[sp_AddPaymentClient]
    @PaymentHeaderID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRAN;

    -------------------------------------------------------
    -- 1. LOAD HEADER
    -------------------------------------------------------
    DECLARE
        @custkey      CHAR(8),
        @refno        VARCHAR(20),
        @date         DATE,
        @remarks      VARCHAR(500),
        @preparedby   VARCHAR(50),
        @custname     VARCHAR(100),
        @BankGLCode   VARCHAR(20),
        @PayType      VARCHAR(30),

        -- Raw amounts from ARPaymentDetails
        @Gross    DECIMAL(18,2),
        @GrossOverpay    DECIMAL(18,2),
        @EWT      DECIMAL(18,2),
        @Discount DECIMAL(18,2),
        @Offset   DECIMAL(18,2),   -- advance deposit applied (reduces cash)
        @Overpay  DECIMAL(18,2),   -- excess cash received (goes to Other Income)

        -- Net cash variants - different direction for each scenario
        @Net         DECIMAL(18,2),  -- plain: Gross - EWT - Discount
        @NetOffset   DECIMAL(18,2),  -- with offset:  Gross - EWT - Discount - Offset
        @NetOverpay  DECIMAL(18,2),  -- with overpay: Gross - EWT - Discount + Overpay

        -- Active net for bank recon DIT (resolved after mnemonic is known)
        @BankCash    DECIMAL(18,2),

        @Origin   VARCHAR(10) = 'OR',
        @Mnemonic VARCHAR(50),
        @TicketNo BIGINT;

    SELECT
        @custkey    = CustomerKey,
        @refno      = ReferenceNo,
        @date       = PaymentDate,
        @remarks    = Remarks,
        @preparedby = CreatedBy,
        @PayType    = PaymentType
    FROM PaymentHeader
    WHERE PaymentHeaderID = @PaymentHeaderID;

    IF @custkey IS NULL
    BEGIN
        ROLLBACK;
        THROW 92000, 'PaymentHeader not found.', 1;
    END

    SELECT @custname = CustomerName
    FROM Customers
    WHERE CustomerKey = @custkey;


    -- Resolve bank GL code from cheque; default to cash in bank
    --SELECT TOP 1 @BankGLCode = CreditGLCode
    --FROM TransactionCheque
    --WHERE PaymentHeaderID = @PaymentHeaderID
    --  AND CreditGLCode IS NOT NULL;

    SELECT TOP 1 @BankGLCode = DebitGLCode
    FROM dbo.ARPaymentDetails
    WHERE PaymentHeaderID = @PaymentHeaderID
      AND PaymentType='INVOICE PAYMENT';

    IF @BankGLCode IS NULL
        SET @BankGLCode = '';

    -------------------------------------------------------
    -- 2. COMPUTE AMOUNTS
    -------------------------------------------------------
    SELECT
        @Gross   = ISNULL(SUM(CASE WHEN PaymentType = 'INVOICE PAYMENT' THEN Amount ELSE 0 END), 0),
        @EWT     = ISNULL(SUM(CASE WHEN PaymentType = 'EWT'             THEN Amount ELSE 0 END), 0),
        @Discount= ISNULL(SUM(CASE WHEN PaymentType = 'DISCOUNT'        THEN Amount ELSE 0 END), 0),
        @Offset  = ISNULL(SUM(CASE WHEN PaymentType = 'OFFSET'          THEN Amount ELSE 0 END), 0),
        @Overpay = ISNULL(SUM(CASE WHEN PaymentType = 'OVERPAY'         THEN Amount ELSE 0 END), 0)
    FROM ARPaymentDetails
    WHERE PaymentHeaderID = @PaymentHeaderID;



    IF @Gross = 0
    BEGIN
        ROLLBACK;
        THROW 92001, 'No INVOICE PAYMENT rows found for this PaymentHeaderID.', 1;
    END

    -- Guard: Offset and Overpay are mutually exclusive
    IF @Offset > 0 AND @Overpay > 0
    BEGIN
        ROLLBACK;
        THROW 92003, 'Offset and Overpayment cannot both have values in the same payment.', 1;
    END

    SET @GrossOverpay = @Gross-@Overpay;
    -- Compute all three net variants upfront
    SET @Net        = @Gross - @EWT - @Discount;                  -- base (no offset/overpay)
    SET @NetOffset  = @Gross - @EWT - @Discount - @Offset;        -- client pays less
    SET @NetOverpay = @Gross - @EWT - @Discount + @Overpay;       -- client pays more

    -- BankCash = what actually hits the bank account this transaction
    SET @BankCash =
        CASE
            WHEN @Offset  > 0 THEN @NetOffset
            WHEN @Overpay > 0 THEN @NetOverpay
            ELSE @Net
        END;

    -------------------------------------------------------
    -- 2b. GUARDRAILS
    --
    -- (a) Real cash needs a real GL account. Defense-in-depth -
    --     ClientPaymentsDevExAcctg.cs's confirmPayment() only requires Debit
    --     GL Code when totalAmtPaid > 0, so this should already be non-blank
    --     by the time it gets here - this catches any other/future caller
    --     that bypasses that UI check.
    -- (b) Deductions can't exceed Gross. Nothing upstream (this SP or the
    --     grid's RecalculateRow(), which only clamps the *displayed*
    --     AmountPaid, not the raw ewt/discount/offset values actually saved)
    --     stops EWT+Discount(+Offset) from exceeding Gross. If that happens
    --     @BankCash goes negative, and without this check the {BANK} leg
    --     would post as a negative Debit - arithmetically balanced (so the
    --     step-5 check wouldn't catch it) but a corrupted GL line for any
    --     report assuming Debit >= 0.
    -------------------------------------------------------
    IF @BankCash <> 0 AND LTRIM(RTRIM(ISNULL(@BankGLCode, ''))) = ''
    BEGIN
        ROLLBACK;
        THROW 92004, 'Debit GL Code (Bank/Cash account) is required when a net amount is being paid.', 1;
    END

    IF @BankCash < 0
    BEGIN
        ROLLBACK;
        THROW 92005, 'EWT/Discount/Offset total exceeds the amount being settled - deductions cannot exceed Gross.', 1;
    END

    -------------------------------------------------------
    -- 3. DETERMINE MNEMONIC
    -- Full 12-scenario matrix covering all combinations.
    -- Offset and Overpay are mutually exclusive (guarded above).
    -------------------------------------------------------
    SET @Mnemonic =
        CASE
            -- EWT + Discount combinations
            WHEN @EWT > 0 AND @Discount > 0 AND @Overpay > 0 THEN 'OR-EWT-DISC-OVERPAY'
            WHEN @EWT > 0 AND @Discount > 0 AND @Offset  > 0 THEN 'OR-EWT-DISC-OFFSET'
            WHEN @EWT > 0 AND @Discount > 0                   THEN 'OR-EWT-DISC'
            -- EWT only combinations
            WHEN @EWT > 0 AND @Overpay > 0                    THEN 'OR-EWT-OVERPAY'
            WHEN @EWT > 0 AND @Offset  > 0                    THEN 'OR-EWT-OFFSET'
            WHEN @EWT > 0                                      THEN 'OR-EWT'
            -- Discount only combinations
            WHEN @Discount > 0 AND @Overpay > 0               THEN 'OR-DISC-OVERPAY'
            WHEN @Discount > 0 AND @Offset  > 0               THEN 'OR-DISC-OFFSET'
            WHEN @Discount > 0                                 THEN 'OR-DISC'
            -- Offset or Overpay alone
            WHEN @Overpay > 0                                  THEN 'OR-OVERPAY'
            WHEN @Offset  > 0                                  THEN 'OR-OFFSET'
            -- Plain collection
            ELSE                                                    'OR-COLL'
        END;

    -------------------------------------------------------
    -- 4. LOAD JOURNAL MAPPING INTO #Computed
    -------------------------------------------------------
    IF OBJECT_ID('tempdb..#Computed') IS NOT NULL
        DROP TABLE #Computed;

    SELECT
        M.Seq,
        M.DebitCredit,
        AccountCode =
            CASE
                WHEN M.AccountCode = '{BANK}' THEN @BankGLCode
                ELSE M.AccountCode
            END,
        Amount =
            CASE M.AmountType
                WHEN 'GROSS'       THEN @Gross
                WHEN 'GROSS-OVERPAY'       THEN @GrossOverpay
                WHEN 'NET'         THEN @Net           -- base: no offset/overpay
                WHEN 'NET_OFFSET'  THEN @NetOffset      -- with advance deposit
                WHEN 'NET_OVERPAY' THEN @NetOverpay     -- with excess cash
                WHEN 'EWT'         THEN @EWT
                WHEN 'OFFSET'      THEN @Offset         -- DR Advances from Customers
                WHEN 'OVERPAY'     THEN @Overpay        -- CR Other Income
                WHEN 'MIRROR'      THEN
                    CASE M.ConditionFlag
                        WHEN 'HasDiscount' THEN @Discount
                        WHEN 'HasOffset'   THEN @Offset
                        WHEN 'HasEWT'      THEN @EWT
                        ELSE 0
                    END
                ELSE 0
            END
    INTO #Computed
    FROM JournalEntryMapping M
    WHERE M.Origin   = @Origin
      AND M.Mnemonic = @Mnemonic
      AND M.IsActive = 1
      AND (
          M.IsConditional = 0
          OR (M.ConditionFlag = 'HasEWT'      AND @EWT      > 0)
          OR (M.ConditionFlag = 'HasDiscount' AND @Discount > 0)
          OR (M.ConditionFlag = 'HasOffset'   AND @Offset   > 0)
          OR (M.ConditionFlag = 'HasOverpay'  AND @Overpay  > 0)
      );

    IF NOT EXISTS (SELECT 1 FROM #Computed)
    BEGIN
        ROLLBACK;
        THROW 92002, 'No active JournalEntryMapping found. Verify Mnemonic is seeded.', 1;
    END

    -------------------------------------------------------
    -- 5. VALIDATE BALANCE (DR must equal CR)
    -------------------------------------------------------
    DECLARE @Debit  DECIMAL(18,2),
            @Credit DECIMAL(18,2);

    SELECT
        @Debit  = ISNULL(SUM(CASE WHEN DebitCredit = 'D' THEN Amount ELSE 0 END), 0),
        @Credit = ISNULL(SUM(CASE WHEN DebitCredit = 'C' THEN Amount ELSE 0 END), 0)
    FROM #Computed;

    IF @Debit <> @Credit
    BEGIN
        -- Expose computed values for easier diagnosis
        SELECT
            'BALANCE ERROR'  AS ErrorType,
            @Mnemonic        AS Mnemonic,
            @Gross           AS Gross,
            @EWT             AS EWT,
            @Discount        AS Discount,
            @Offset          AS Offset,
            @Overpay         AS Overpay,
            @Net             AS Net,
            @NetOffset       AS NetOffset,
            @NetOverpay      AS NetOverpay,
            @Debit           AS TotalDebit,
            @Credit          AS TotalCredit;
        SELECT * FROM #Computed ORDER BY Seq;

        ROLLBACK;
        DECLARE @ErrMsg NVARCHAR(200);
        SET @ErrMsg = 'Validation failed: Debit = ' + CAST(@Debit AS NVARCHAR(50))
                    + ', Credit = ' + CAST(@Credit AS NVARCHAR(50));

        THROW 91002, @ErrMsg, 1;
        --THROW 91002, 'Validation failed: Debit and Credit not balanced.'+@Debit+' '+@Credit, 1;
    END

    -------------------------------------------------------
    -- 6. UPDATE TransactionChargeSales
    --
    -- AmountPaid = net cash received per invoice.
    --   = gross_i - ewt_i - discount_i - offset_i
    --   (overpay does NOT come from the invoice - it is extra
    --    cash, so it is included in net cash via @BankCash
    --    but NOT in the per-invoice AmountPaid derivation.
    --    The invoice is fully settled by its gross amount.)
    --
    -- OffsetAmount is NOT updated on TCS.
    --   Reason: Offset clears a liability (Advances from Customers).
    --   The invoice balance is settled by AmountPaid + EWT + Discount
    --   only. OffsetAmount column on TCS is reserved for future use
    --   or left at 0.
    --
    -- Overpay is NOT stored on TCS either.
    --   Reason: It goes to Other Income via GL only. The invoice
    --   is settled in full by its gross - overpay is separate.
    -------------------------------------------------------

    -- AmountPaid per invoice = gross_i - ewt_i - discount_i
    -- (offset subtracted if applicable, overpay not subtracted)
    UPDATE T
    SET T.AmountPaid = T.AmountPaid +
        (
            -- gross for this invoice
            ISNULL((SELECT SUM(D.Amount) FROM ARPaymentDetails D
                    WHERE D.PaymentHeaderID = @PaymentHeaderID
                      AND D.InvoiceNo       = T.InvoiceNo
                      AND D.PaymentType     = 'INVOICE PAYMENT'), 0)
            -- minus EWT withheld
          - ISNULL((SELECT SUM(D.Amount) FROM ARPaymentDetails D
                    WHERE D.PaymentHeaderID = @PaymentHeaderID
                      AND D.InvoiceNo       = T.InvoiceNo
                      AND D.PaymentType     = 'EWT'), 0)
            -- minus discount granted
          - ISNULL((SELECT SUM(D.Amount) FROM ARPaymentDetails D
                    WHERE D.PaymentHeaderID = @PaymentHeaderID
                      AND D.InvoiceNo       = T.InvoiceNo
                      AND D.PaymentType     = 'DISCOUNT'), 0)
            -- minus offset applied (advance deposit reduces cash collected)
          - ISNULL((SELECT SUM(D.Amount) FROM ARPaymentDetails D
                    WHERE D.PaymentHeaderID = @PaymentHeaderID
                      AND D.InvoiceNo       = T.InvoiceNo
                      AND D.PaymentType     = 'OFFSET'), 0)
          --+ ISNULL((SELECT SUM(D.Amount) FROM ARPaymentDetails D
          --          WHERE D.PaymentHeaderID = @PaymentHeaderID
          --            AND D.InvoiceNo       = T.InvoiceNo
          --            AND D.PaymentType     = 'OVERPAY'), 0)
            -- NOTE: OVERPAY intentionally excluded here.
            -- Overpay is extra cash beyond the invoice - not part of
            -- settling the invoice itself. It goes to Other Income only.
        )
    FROM TransactionChargeSales T
    WHERE EXISTS (
        SELECT 1 FROM ARPaymentDetails D
        WHERE D.PaymentHeaderID = @PaymentHeaderID
          AND D.InvoiceNo       = T.InvoiceNo
          AND D.PaymentType     = 'INVOICE PAYMENT'
    );

    -- EWT per invoice
    UPDATE T
    SET T.EWTAmount = ISNULL(T.EWTAmount, 0) + D.Amount
    FROM TransactionChargeSales T
    JOIN ARPaymentDetails D ON T.InvoiceNo = D.InvoiceNo
    WHERE D.PaymentHeaderID = @PaymentHeaderID
      AND D.PaymentType     = 'EWT';

    -- Discount per invoice
    UPDATE T
    SET T.DiscountAmount = ISNULL(T.DiscountAmount, 0) + D.Amount
    FROM TransactionChargeSales T
    JOIN ARPaymentDetails D ON T.InvoiceNo = D.InvoiceNo
    WHERE D.PaymentHeaderID = @PaymentHeaderID
      AND D.PaymentType     = 'DISCOUNT';

     -- Offset per invoice --include by eulz
    UPDATE T
    SET T.OffsetAmount = ISNULL(T.OffsetAmount, 0) + D.Amount
    FROM TransactionChargeSales T
    JOIN ARPaymentDetails D ON T.InvoiceNo = D.InvoiceNo
    WHERE D.PaymentHeaderID = @PaymentHeaderID
      AND D.PaymentType     = 'OFFSET';

      -- Offset per invoice --include by eulz
    UPDATE T
    SET T.AdvancePayment = ISNULL(T.AdvancePayment, 0) + D.Amount
    FROM TransactionChargeSales T
    JOIN ARPaymentDetails D ON T.InvoiceNo = D.InvoiceNo
    WHERE D.PaymentHeaderID = @PaymentHeaderID
      AND D.PaymentType     = 'OVERPAY';

    -- NOTE: No UPDATE for OFFSET on TCS (liability clearance, not invoice deduction)
    -- NOTE: No UPDATE for OVERPAY on TCS (Other Income only, not invoice deduction)

    -------------------------------------------------------
    -- 7. RECALCULATE BALANCE
    --
    -- Balance = TotalAmount - (AmountPaid + EWTAmount + DiscountAmount)
    -- Offset and Overpay deliberately excluded - they do not
    -- represent deductions from the invoice face value.
    -------------------------------------------------------
    UPDATE T
    SET T.Balance =
        --(T.TotalAmount + ISNULL(T.AdvancePayment,0)) - (
        (T.TotalAmount) - (
            ISNULL(T.AmountPaid,    0) +
            ISNULL(T.EWTAmount,     0) +
            ISNULL(T.DiscountAmount,0) +
            ISNULL(T.OffsetAmount,0)      --Added by Eulz
        )
    FROM TransactionChargeSales T
    WHERE EXISTS (
        SELECT 1 FROM ARPaymentDetails D
        WHERE D.PaymentHeaderID = @PaymentHeaderID
          AND D.InvoiceNo       = T.InvoiceNo
    );

    -------------------------------------------------------
    -- 8. UPDATE PAYSTATUS
    -------------------------------------------------------
    UPDATE T
    SET T.PayStatus =
        CASE
            WHEN T.Balance <= 0 THEN 'FULLYPAID'
            WHEN T.AmountPaid > 0
              OR T.EWTAmount     > 0
              OR T.DiscountAmount> 0 THEN 'PARTIAL'
            ELSE 'UNPAID'
        END
    FROM TransactionChargeSales T
    WHERE EXISTS (
        SELECT 1 FROM ARPaymentDetails D
        WHERE D.PaymentHeaderID = @PaymentHeaderID
          AND D.InvoiceNo       = T.InvoiceNo
    );

    -------------------------------------------------------
    -- 9. TICKET MASTER
    -------------------------------------------------------
    EXEC GetTicketNumber @TicketNo OUTPUT;

    INSERT INTO TicketMaster--SELECT TOP(1) * FROM TicketMaster
    (
        TicketDate, SupplementaryNumber, BranchCode, Origin,
        TicketNumber, ReferenceNumber, ReferenceKey,
        Owner, Particulars, EnteredBy,
        CheckedBy, ApprovedBy, Status, Mnemonic, Product
    )
    VALUES
    (
        @date, 0, '888', '888',
        @TicketNo, @refno, @refno,
        @custname, @Mnemonic + ' ENTRY', @preparedby,
        '*', '*', 'UPDATED', NULL, @remarks
    );

    -------------------------------------------------------
    -- 10. TICKET DETAILS
    --
    -- WHERE Amount <> 0 (2026-08-21): drop legs that compute to exactly
    -- zero - see file header comment for why this is always safe (only the
    -- {BANK}-mapped NET/NET_OFFSET/NET_OVERPAY leg can organically be 0;
    -- GROSS and every conditional deduction leg cannot be selected at 0).
    -- Without this, a zero-net-cash posting (EWT-only, discount-only, etc.)
    -- with no Debit GL Code entered would insert a TicketDetails row with
    -- AccountCode=''.
    -------------------------------------------------------
    INSERT INTO TicketDetails
    (
        TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
        TicketNumber, ReferenceNumber,
        AccountCode, Debit, Credit, CostCenter
    )
    SELECT
        @date, 0, '888', @refno,
        @TicketNo, @refno,
        AccountCode,
        CASE WHEN DebitCredit = 'D' THEN Amount ELSE 0 END,
        CASE WHEN DebitCredit = 'C' THEN Amount ELSE 0 END,
        ' '
    FROM #Computed
    WHERE Amount <> 0
    ORDER BY Seq;

    -------------------------------------------------------
    -- 11. SELECT * FROM CLIENTLEDGER
    -- Posts one row per invoice for the gross amount settled.
    -- Overpay is NOT posted here - it has no invoice linkage.
    -------------------------------------------------------
    INSERT INTO ClientLedger
    (
        TRN_SEQ_NO, AccountKey, AccountID,
        PostingDate, InitiatingBranch, Description,
        TransCode, TransactionDate,
        ReferenceNumber, ReferenceKey, InvoiceNo,
        Debit, Credit, BeginningBalance, EndingBalance,
        ORNumber, TransactedBy, ApprovedBy,
        Remarks, TotalAmount, ErrorCorrectTag, TicketReference
    )
    SELECT
        ROW_NUMBER() OVER (ORDER BY D.InvoiceNo)
          + ISNULL((SELECT MAX(TRN_SEQ_NO) FROM ClientLedger WHERE AccountKey = @custkey), 0),
        @custkey, @custkey,
        @date, '888', @remarks,
        @Mnemonic, @date,
        @refno, '', D.InvoiceNo,
        0, D.Amount, 0, 0,
        @refno, @preparedby, '*',
        @remarks, D.Amount, 0, @TicketNo
    FROM (
        SELECT InvoiceNo, SUM(Amount) AS Amount
        FROM ARPaymentDetails
        WHERE PaymentHeaderID = @PaymentHeaderID
          AND PaymentType     = 'INVOICE PAYMENT'
        GROUP BY InvoiceNo
    ) D;

    -------------------------------------------------------
    -- 12. BANK RECON - AUTO-INSERT DEPOSIT IN TRANSIT (DIT)
    --
    -- FIX: call sp_BankRecon_GetOrCreateHeader first so that
    -- HeaderID is always populated on the inserted row.
    -- Credit card excluded - merchant acquirer handles settlement.
    --
    -- AND @BankCash <> 0 (2026-08-21): a zero-net-cash posting has nothing
    -- to deposit and nothing to reconcile - skip both the header
    -- lookup/create and the DIT insert entirely rather than recording a $0
    -- DIT row (which would also carry AccountCode = @BankGLCode = '' when
    -- no Debit GL Code was entered).
    -------------------------------------------------------
   IF @PayType IN ('CASH', 'CHECK', 'ONLINE', 'ADVANCEPAYMENT') AND @BankCash <> 0
    BEGIN
        -- FIX: pre-compute period end into a variable
        -- EOMONTH() cannot be used inline in EXEC named params
        DECLARE @PeriodEnd     DATE = EOMONTH(@date);
        DECLARE @ReconHeaderID INT;

        EXEC sp_BankRecon_GetOrCreateHeader
            @BranchCode  = '888',
            @AccountCode = @BankGLCode,
            @PeriodEnd   = @PeriodEnd,      -- variable, not EOMONTH(@date)
            @CreatedBy   = @preparedby,
            @HeaderID    = @ReconHeaderID OUTPUT;
        --SELECT * FROM BankStatementRecon
        INSERT INTO BankStatementRecon
        (
            HeaderID,
            BranchCode, AccountCode, PeriodEnd,
            ItemType, ItemDate, Payee,
            ReferenceNo, Amount,
            IsResolved, ResolvedDate,
            SourceModule, SourceRef, ResolvedReason,
            CreatedBy, CreatedDate
        )
        VALUES
        (
            @ReconHeaderID,
            '888',
            @BankGLCode,
            @PeriodEnd,                     -- same variable
            'DIT',
            @date,
            'CLIENT COLLECTION - ' + ISNULL(@custname, @custkey),
            @refno,
            @BankCash,
            0,
            ' ',
            'AR-PAYMENT',
            @refno,
            ' ',
            @preparedby,
            GETDATE()
        );

        IF @ReconHeaderID IS NULL
        BEGIN
            ROLLBACK;
            THROW 92000, 'BankReconHeader not found.', 1;
        END

    END

    -------------------------------------------------------
    COMMIT;
END
GO

PRINT 'DEPLOYMENT COMPLETE: sp_AddPaymentClient now guards against zero-net-cash postings with no GL account.';
