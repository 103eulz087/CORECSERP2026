-- 2026-09-23: sp_AddPaymentClient -- reject an Offset that exceeds the
-- customer's actual available overpayment credit.
--
-- sp-reviewer finding on 2026-09-23_CustomerOverpaymentCredit.sql:
-- sp_GetCustomerAvailableCredit is read-only/display-only, and nothing
-- server-side ever enforced it -- a user could type an OffsetAmount with no
-- prior OVERPAY history at all (or larger than what's actually available)
-- and it would post straight through, silently drawing the new 20115
-- CUSTOMER ADVANCES / OVERPAYMENTS liability account below zero (recording
-- that credit was consumed which was never actually granted). Not a
-- hypothetical -- the only guard today is "Offset and Overpay cannot both
-- have values in the same payment" (mutual exclusivity), nothing about
-- "Offset cannot exceed prior accumulated Overpay".
--
-- FIX: re-derive the customer's available credit fresh, under UPDLOCK/
-- HOLDLOCK, EXCLUDING this PaymentHeaderID's own rows (already inserted by
-- the caller before this SP runs -- this is the credit available BEFORE
-- this payment's own draw), and THROW if @Offset would exceed it. Same
-- Known Bug Pattern #10 shape already used this session in
-- sp_AddPaymentSupplierCompound_V2's overpayment guard: never trust a
-- cached/UI-side number, re-derive from a fresh locked read at the point
-- that actually matters.
--
-- Also fixes sp_GetCustomerAvailableCredit itself (both flagged by the same
-- review): ph.Status <> 'REVERSED' silently drops any row where Status is
-- NULL (three-valued logic) -- changed to ISNULL(ph.Status,'') <> 'REVERSED'.
-- Added an explicit PaymentType IN ('OVERPAY','OFFSET') filter for clarity/
-- scan reduction (was previously implicit via the CASE zeroing out other
-- rows -- same result, clearer intent).
--
-- Deploy to CORECSERP_002_DEV first; mirror to CORECSJFC2026_STAGING only
-- after confirming with the user, per project convention.

-- ----------------------------------------------------------------
-- 1. sp_GetCustomerAvailableCredit -- NULL-safety + explicit filter
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_GetCustomerAvailableCredit', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetCustomerAvailableCredit', 'sp_GetCustomerAvailableCredit_OLD_09232026050000';
GO

CREATE PROCEDURE dbo.sp_GetCustomerAvailableCredit
(
    @CustomerKey CHAR(8)
)
AS
/*
    Running unapplied-overpayment balance for one customer:
        SUM(OVERPAY amounts) - SUM(OFFSET amounts already applied),
    across non-reversed PaymentHeader rows only. No dedicated tracking
    table -- ARPaymentDetails/PaymentHeader already carry everything
    needed. ISNULL(ph.Status,'') <> 'REVERSED' (not a bare <>) so a NULL
    Status can't silently three-valued-logic its way out of the WHERE.
    Always returns exactly one row (0.00 when the customer has never
    overpaid), even when no matching rows exist.
    Caller: ClientPaymentsDevExAcctg.cs (customer-select refresh). NOTE:
    sp_AddPaymentClient's own Offset guard does NOT call this proc -- it
    duplicates the identical SUM(OVERPAY)-SUM(OFFSET) formula inline
    (needs its own EXCLUDING-this-PaymentHeaderID clause, which a shared
    call here can't parameterize). The two are independently maintained;
    keep both in sync by hand if this formula ever changes.
*/
BEGIN
    SET NOCOUNT ON;

    SELECT
        ISNULL(SUM(CASE WHEN apd.PaymentType = 'OVERPAY' THEN apd.Amount ELSE 0 END), 0)
      - ISNULL(SUM(CASE WHEN apd.PaymentType = 'OFFSET'  THEN apd.Amount ELSE 0 END), 0)
        AS AvailableCredit
    FROM dbo.PaymentHeader ph
    JOIN dbo.ARPaymentDetails apd ON apd.PaymentHeaderID = ph.PaymentHeaderID
    WHERE ph.CustomerKey = @CustomerKey
      AND ISNULL(ph.Status, '') <> 'REVERSED'
      AND apd.PaymentType IN ('OVERPAY', 'OFFSET');
END
GO

-- ----------------------------------------------------------------
-- 2. sp_AddPaymentClient -- add the Offset-vs-available-credit guard
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_AddPaymentClient', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_AddPaymentClient', 'sp_AddPaymentClient_OLD_09232026050000';
GO

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
        @Services DECIMAL(18,2),   -- additional fee billed to client (e.g. cutting fee) -- goes to AR-Others

        -- Net cash variants - different direction for each scenario
        @Net         DECIMAL(18,2),  -- plain: Gross - EWT - Discount [+ Services]
        @NetOffset   DECIMAL(18,2),  -- with offset:  Gross - EWT - Discount - Offset [+ Services]
        @NetOverpay  DECIMAL(18,2),  -- with overpay: Gross - EWT - Discount + Overpay [+ Services]

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
        @Gross    = ISNULL(SUM(CASE WHEN PaymentType = 'INVOICE PAYMENT' THEN Amount ELSE 0 END), 0),
        @EWT      = ISNULL(SUM(CASE WHEN PaymentType = 'EWT'             THEN Amount ELSE 0 END), 0),
        @Discount = ISNULL(SUM(CASE WHEN PaymentType = 'DISCOUNT'        THEN Amount ELSE 0 END), 0),
        @Offset   = ISNULL(SUM(CASE WHEN PaymentType = 'OFFSET'          THEN Amount ELSE 0 END), 0),
        @Overpay  = ISNULL(SUM(CASE WHEN PaymentType = 'OVERPAY'         THEN Amount ELSE 0 END), 0),
        @Services = ISNULL(SUM(CASE WHEN PaymentType = 'SERVICES'        THEN Amount ELSE 0 END), 0)
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

    -- NEW: serialize per-customer before touching the credit pool at all.
    -- sp-reviewer finding: locking scattered PaymentHeader rows (excluding
    -- our own @PaymentHeaderID) only avoided a race by accident of the
    -- current caller always running insert+post+commit on one open
    -- SqlTransaction -- two concurrent submissions for the same customer
    -- would each need the other's still-locked row, forcing a deadlock
    -- (safe for the ledger, but surfaces a raw SQL error to the user
    -- instead of a clean serialized wait) and stops protecting at all if a
    -- future caller ever splits insert/post into separate committed steps.
    -- A single named resource lock is correct regardless of calling
    -- convention. Acquired unconditionally (not just when @Offset>0),
    -- since an OVERPAY posting also needs to serialize against a
    -- concurrent OFFSET read for the same customer. @LockOwner='Transaction'
    -- auto-releases on this proc's COMMIT/ROLLBACK -- no explicit release needed.
    DECLARE @LockResult INT;
    EXEC @LockResult = sp_getapplock
        @Resource = @custkey,
        @LockMode = 'Exclusive',
        @LockOwner = 'Transaction',
        @LockTimeout = 10000;

    IF @LockResult < 0
    BEGIN
        ROLLBACK;
        THROW 92007, 'Could not acquire a lock for this customer''s payment (another payment for the same customer is in progress). Please try again.', 1;
    END

    -- Offset cannot exceed the customer's actual available credit.
    -- sp-reviewer finding (2026-09-23): sp_GetCustomerAvailableCredit is
    -- read-only/display-only -- nothing enforced it server-side, so an
    -- Offset with no real Overpay behind it (or larger than what's
    -- available) used to post straight through and draw account 20115
    -- below zero. Known Bug Pattern #10: re-derive from a fresh read here
    -- rather than trust the UI's cached label -- the sp_getapplock above
    -- is what makes this read race-free now, not row-level locking.
    -- Computed EXCLUDING this PaymentHeaderID's own rows (already inserted
    -- by the caller before this SP runs) -- this is the credit available
    -- BEFORE this payment's own draw.
    IF @Offset > 0
    BEGIN
        DECLARE @PriorAvailableCredit DECIMAL(18,2);

        SELECT @PriorAvailableCredit =
            ISNULL(SUM(CASE WHEN apd.PaymentType = 'OVERPAY' THEN apd.Amount ELSE 0 END), 0)
          - ISNULL(SUM(CASE WHEN apd.PaymentType = 'OFFSET'  THEN apd.Amount ELSE 0 END), 0)
        FROM PaymentHeader ph
        JOIN ARPaymentDetails apd ON apd.PaymentHeaderID = ph.PaymentHeaderID
        WHERE ph.CustomerKey = @custkey
          AND ISNULL(ph.Status, '') <> 'REVERSED'
          AND ph.PaymentHeaderID <> @PaymentHeaderID
          AND apd.PaymentType IN ('OVERPAY', 'OFFSET');

        IF @Offset > ISNULL(@PriorAvailableCredit, 0)
        BEGIN
            ROLLBACK;
            DECLARE @OffsetMsg VARCHAR(400) = 'Offset amount (' + CAST(@Offset AS VARCHAR(30))
                + ') exceeds this customer''s available overpayment credit (' + CAST(ISNULL(@PriorAvailableCredit,0) AS VARCHAR(30)) + ').';
            THROW 92006, @OffsetMsg, 1;
        END
    END

    SET @GrossOverpay = @Gross-@Overpay;
    -- Compute all three net variants upfront -- Services adds to every
    -- variant since it is real additional cash the client pays, regardless
    -- of which other deduction/addition combination is in play.
    SET @Net        = @Gross - @EWT - @Discount + @Services;                  -- base (no offset/overpay)
    SET @NetOffset  = @Gross - @EWT - @Discount - @Offset + @Services;        -- client pays less
    SET @NetOverpay = @Gross - @EWT - @Discount + @Overpay + @Services;       -- client pays more

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
    -- sp-reviewer finding (2026-09-01): @BankCash now includes +@Services,
    -- which can MASK an over-deduction on the invoice itself -- e.g.
    -- Gross=1000, EWT=900, Discount=200 (deductions of 1100 already exceed
    -- the 1000 invoice) plus Services=200 nets @BankCash to +100, silently
    -- passing the old "@BankCash < 0" check even though the invoice-level
    -- deduction is invalid. Step 6 below then writes a NEGATIVE AmountPaid
    -- to a real TransactionChargeSales row. Guard the invoice-only net
    -- (EXCLUDING Services and Overpay, both of which are additive cash with
    -- no invoice-settlement meaning) separately, before Services ever gets
    -- a chance to offset it.
    -------------------------------------------------------
    DECLARE @InvoiceNetExclServices DECIMAL(18,2) =
        CASE
            WHEN @Offset > 0 THEN @Gross - @EWT - @Discount - @Offset
            ELSE @Gross - @EWT - @Discount
        END;

    IF @InvoiceNetExclServices < 0
    BEGIN
        ROLLBACK;
        THROW 92005, 'EWT/Discount/Offset total exceeds the amount being settled - deductions cannot exceed Gross.', 1;
    END

    IF @BankCash <> 0 AND LTRIM(RTRIM(ISNULL(@BankGLCode, ''))) = ''
    BEGIN
        ROLLBACK;
        THROW 92004, 'Debit GL Code (Bank/Cash account) is required when a net amount is being paid.', 1;
    END

    -- Retained as defense-in-depth -- with the guard above in place this
    -- can no longer actually go negative (Services/Overpay are the only
    -- terms separating @BankCash from @InvoiceNetExclServices, and both are
    -- always >= 0), but keep it rather than trust that invariant silently.
    IF @BankCash < 0
    BEGIN
        ROLLBACK;
        THROW 92005, 'EWT/Discount/Offset total exceeds the amount being settled - deductions cannot exceed Gross.', 1;
    END

    -------------------------------------------------------
    -- 3. DETERMINE MNEMONIC
    -- Full 12-scenario matrix covering all combinations. Services is
    -- deliberately NOT part of this matrix -- see file header comment;
    -- it applies as a cross-cutting conditional row on every mnemonic.
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
                WHEN 'OFFSET'      THEN @Offset         -- DR Customer Advances / Overpayments (20115)
                WHEN 'OVERPAY'     THEN @Overpay        -- CR Customer Advances / Overpayments (20115)
                WHEN 'SERVICES'    THEN @Services       -- CR AR-Others -- additional fee charged to client
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
          OR (M.ConditionFlag = 'HasServices' AND @Services > 0)
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
        SELECT
            'BALANCE ERROR'  AS ErrorType,
            @Mnemonic        AS Mnemonic,
            @Gross           AS Gross,
            @EWT             AS EWT,
            @Discount        AS Discount,
            @Offset          AS Offset,
            @Overpay         AS Overpay,
            @Services        AS Services,
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
    END

    -------------------------------------------------------
    -- 6. UPDATE TransactionChargeSales
    --
    -- Services is deliberately EXCLUDED from all of this section -- it is
    -- an additional charge billed to the client, not a deduction from or
    -- settlement of the invoice itself. The invoice's own Balance/PayStatus
    -- must move exactly as it did before Services existed.
    -------------------------------------------------------
    UPDATE T
    SET T.AmountPaid = T.AmountPaid +
        (
            ISNULL((SELECT SUM(D.Amount) FROM ARPaymentDetails D
                    WHERE D.PaymentHeaderID = @PaymentHeaderID
                      AND D.InvoiceNo       = T.InvoiceNo
                      AND D.PaymentType     = 'INVOICE PAYMENT'), 0)
          - ISNULL((SELECT SUM(D.Amount) FROM ARPaymentDetails D
                    WHERE D.PaymentHeaderID = @PaymentHeaderID
                      AND D.InvoiceNo       = T.InvoiceNo
                      AND D.PaymentType     = 'EWT'), 0)
          - ISNULL((SELECT SUM(D.Amount) FROM ARPaymentDetails D
                    WHERE D.PaymentHeaderID = @PaymentHeaderID
                      AND D.InvoiceNo       = T.InvoiceNo
                      AND D.PaymentType     = 'DISCOUNT'), 0)
          - ISNULL((SELECT SUM(D.Amount) FROM ARPaymentDetails D
                    WHERE D.PaymentHeaderID = @PaymentHeaderID
                      AND D.InvoiceNo       = T.InvoiceNo
                      AND D.PaymentType     = 'OFFSET'), 0)
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

    -------------------------------------------------------
    -- 7. RECALCULATE BALANCE
    -------------------------------------------------------
    UPDATE T
    SET T.Balance =
        (T.TotalAmount) - (
            ISNULL(T.AmountPaid,    0) +
            ISNULL(T.EWTAmount,     0) +
            ISNULL(T.DiscountAmount,0) +
            ISNULL(T.OffsetAmount,0)
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

    INSERT INTO TicketMaster
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
        '*', '*', 'UPDATED', @Mnemonic, @remarks
    );

    -------------------------------------------------------
    -- 10. TICKET DETAILS
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
    -- 11. CLIENTLEDGER
    -- Posts one row per invoice for the gross amount settled.
    -- Services (like Overpay) has no invoice linkage -- NOT posted here.
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
    -------------------------------------------------------
   IF @PayType IN ('CASH', 'CHECK', 'ONLINE', 'ADVANCEPAYMENT') AND @BankCash <> 0
    BEGIN
        DECLARE @PeriodEnd     DATE = EOMONTH(@date);
        DECLARE @ReconHeaderID INT;

        EXEC sp_BankRecon_GetOrCreateHeader
            @BranchCode  = '888',
            @AccountCode = @BankGLCode,
            @PeriodEnd   = @PeriodEnd,
            @CreatedBy   = @preparedby,
            @HeaderID    = @ReconHeaderID OUTPUT;

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
            @PeriodEnd,
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
