-- =============================================
-- Author: Eulz Avancena (original); modified 2026-09-01
-- Description: Adds a "ServicesAmount" charge to Client Payments
--              (ClientPaymentsDevExAcctg.cs) -- an additional fee (e.g.
--              cutting fee) billed to the client ON TOP OF the invoice
--              amount being collected, credited to a DIFFERENT AR account
--              than the invoice itself.
--
--              Confirmed example:
--                Invoice Amount = 1000, Services Amount = 200, Total Pay = 1200
--                Debit  Cash In Bank                    = 1200
--                Credit Accounts Receivable - Trade      = 1000  (unchanged, existing GROSS leg)
--                Credit Accounts Receivable - Others     =  200  (NEW)
--
--              ServicesAmount is NOT a deduction from the invoice (unlike
--              EWT/Discount/Offset) -- it doesn't touch
--              TransactionChargeSales.Balance/PayStatus or ClientLedger
--              (those stay invoice-settlement-only, exactly as today). It
--              only adds to the cash actually collected (@Net/@NetOffset/
--              @NetOverpay -- and therefore the {BANK} debit leg and the
--              BankStatementRecon DIT amount, both of which derive from
--              those) and adds one new Credit leg to AR-Others.
--
--              Implemented as a cross-cutting IsConditional=1/
--              ConditionFlag='HasServices' row added to EVERY existing
--              active OR-* Mnemonic (12), rather than a new Mnemonic
--              combination per existing convention -- Services can occur
--              alongside ANY existing EWT/Discount/Offset/Overpay
--              combination without multiplying the mnemonic matrix.
--
--              OR-COLL's existing {BANK} debit row (MappingID 65) is
--              changed from AmountType='GROSS' to 'NET' -- @Net reduces to
--              exactly @Gross when there is no EWT/Discount/Services (i.e.
--              today's behavior is unchanged for every existing OR-COLL
--              posting), but this is required for OR-COLL to pick up
--              Services at all, since that's the exact "no other
--              deductions" scenario the confirmed example describes.
-- =============================================

-------------------------------------------------------------------
-- 1. splist_ARAccounts: add ServicesAmount (editable grid column,
--    defaults to 0, same shape as EWTAmount/DiscountAmount/OffsetAmount)
-------------------------------------------------------------------
-- Idempotent rename guard (sp-reviewer finding) -- if this exact script is
-- ever re-run in the same session, the plain "rename if exists" below would
-- try to rename the already-renamed backup a second time and collide with
-- itself. Same double-guard pattern used elsewhere this session
-- (2026-08-24_sp_rpt_TrialBalanceWithDate_FixDebitCreditSplit.sql).
IF OBJECT_ID('dbo.splist_ARAccounts_OLD_09012026220000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.splist_ARAccounts', 'P') IS NOT NULL
        DROP PROCEDURE dbo.splist_ARAccounts;
END
ELSE IF OBJECT_ID('dbo.splist_ARAccounts', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.splist_ARAccounts', 'splist_ARAccounts_OLD_09012026220000';
END
GO

-- The original proc was created with QUOTED_IDENTIFIER ON; force it
-- explicitly so a redeploy via a tool whose default session has it OFF
-- (e.g. sqlcmd) doesn't silently flip it -- same footgun hit and documented
-- earlier this session in the Conversion module's SQL files.
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE [dbo].[splist_ARAccounts]
	@parmcustkey varchar(100)
AS
BEGIN
	SET NOCOUNT ON;

	create table #temptemp
	(
		TransactionDate date,
		OrderNo varchar(10),
		InvoiceNo varchar(100),
		InvoiceAmount decimal(12,2),
		Balance decimal(12,2),
		EWTAmount decimal(12,2),
		DiscountAmount decimal(12,2),
		OffsetAmount decimal(12,2),
		OverPay decimal(12,2),
		ServicesAmount decimal(12,2),
		InvoiceType varchar(15)
	)

	truncate table #temptemp
	insert into #temptemp
		(TransactionDate, OrderNo, InvoiceNo, InvoiceAmount, Balance,
		 EWTAmount, DiscountAmount, OffsetAmount, OverPay, ServicesAmount, InvoiceType)
	SELECT
	CAST(TransactionDate as date) as TransactionDate,
	ReferenceNo,
	InvoiceNo,
	TotalAmount,
	Balance,
	CAST(0 AS DECIMAL(12,2)) as EWTAmount,
	CAST(0 AS DECIMAL(12,2)) as DiscountAmount,
	CAST(0 AS DECIMAL(12,2)) as OffsetAmount,
	CAST(0 AS DECIMAL(12,2)) as OverPay,
	CAST(0 AS DECIMAL(12,2)) as ServicesAmount,
	'SALES'
	FROM TransactionChargeSales
	WHERE (PayStatus='UNPAID' OR PayStatus='PARTIAL')
	AND Balance > 0
	and CustomerKey=@parmcustkey

	declare @term int
	select @term=Term FROM Customers where CustomerKey=@parmcustkey
	Select
		CAST(0 AS BIT) AS Pay,
		TransactionDate,
		DATEADD(DAY,ISNULL(@term,0),TransactionDate) as DueDate,
		OrderNo ,
		InvoiceNo,
		InvoiceType,
		InvoiceAmount,
		Balance,
		CAST(0 AS DECIMAL(12,2)) as AmountPaid,
		EWTAmount,
		DiscountAmount,
		OffsetAmount,
		OverPay,
		ServicesAmount,
		'' as Remarks
	FROM #temptemp

END
GO

-------------------------------------------------------------------
-- 2. sp_AddPaymentClient: self-accumulate @Services from ARPaymentDetails,
--    fold it into the net-cash variants, expose it as an AmountType in the
--    #Computed mapping resolution.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.sp_AddPaymentClient_OLD_09012026220000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.sp_AddPaymentClient', 'P') IS NOT NULL
        DROP PROCEDURE dbo.sp_AddPaymentClient;
END
ELSE IF OBJECT_ID('dbo.sp_AddPaymentClient', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.sp_AddPaymentClient', 'sp_AddPaymentClient_OLD_09012026220000';
END
GO

-- Original proc was created with QUOTED_IDENTIFIER OFF -- pin it explicitly
-- (rather than relying on the deploy tool's default) so this stays true on
-- any future redeploy regardless of what tool runs this script.
SET QUOTED_IDENTIFIER OFF;
SET ANSI_NULLS ON;
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
                WHEN 'OFFSET'      THEN @Offset         -- DR Advances from Customers
                WHEN 'OVERPAY'     THEN @Overpay        -- CR Other Income
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
        '*', '*', 'UPDATED', NULL, @remarks
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

-------------------------------------------------------------------
-- 3. JournalEntryMapping seed data
-------------------------------------------------------------------

-- OR-COLL's {BANK} debit leg must use NET (=Gross when no EWT/Discount/
-- Services, i.e. unchanged for every existing posting) instead of a hardcoded
-- GROSS, so it picks up Services in the plain-collection case.
--
-- sp-reviewer finding: targeted by (Origin, Mnemonic, AccountCode,
-- DebitCredit) rather than a bare MappingID literal -- a hardcoded surrogate
-- key is fragile across environments (CORECSJFC2026_STAGING may have seeded
-- JournalEntryMapping independently, where MappingID 65 might not even be
-- OR-COLL's {BANK} row) and would silently no-op with 0 rows affected. The
-- @@ROWCOUNT check catches that instead of failing silently.
UPDATE dbo.JournalEntryMapping
SET AmountType = 'NET'
WHERE Origin = 'OR' AND Mnemonic = 'OR-COLL' AND AccountCode = '{BANK}' AND DebitCredit = 'D';

IF @@ROWCOUNT <> 1
BEGIN
    ROLLBACK; -- no-op if not in a transaction; safe either way
    THROW 92100, 'Expected exactly one OR-COLL {BANK} debit row in JournalEntryMapping to update -- found a different count. Verify seed data before continuing.', 1;
END

-- One new conditional Credit-to-AR-Others row per existing active mnemonic.
-- Guarded so re-running this script (e.g. against a second environment, or
-- a partial-failure retry) doesn't duplicate these 12 rows -- the rename
-- guards above only protect the two stored procedures, not this seed data.
IF NOT EXISTS (SELECT 1 FROM dbo.JournalEntryMapping WHERE Origin = 'OR' AND ConditionFlag = 'HasServices')
BEGIN
INSERT INTO dbo.JournalEntryMapping
    (Origin, Mnemonic, Description, Seq, DebitCredit, AccountCode, AccountDescription,
     IsConditional, IsAmountFromSource, IsActive, Notes, AmountType, ConditionFlag, BranchCode)
VALUES
    ('OR', 'OR-COLL',              'Collection - Official Receipt',                      3, 'C', '101030103', 'ACCOUNTS RECEIVABLE - OTHERS', 1, 1, 1, 'Services amount (e.g. cutting fee) charged to client, additional to the invoice', 'SERVICES', 'HasServices', NULL),
    ('OR', 'OR-DISC',              'Collection with Sales Discount',                     4, 'C', '101030103', 'ACCOUNTS RECEIVABLE - OTHERS', 1, 1, 1, 'Services amount (e.g. cutting fee) charged to client, additional to the invoice', 'SERVICES', 'HasServices', NULL),
    ('OR', 'OR-DISC-OFFSET',       'Collection with Discount and Advance Offset',        5, 'C', '101030103', 'ACCOUNTS RECEIVABLE - OTHERS', 1, 1, 1, 'Services amount (e.g. cutting fee) charged to client, additional to the invoice', 'SERVICES', 'HasServices', NULL),
    ('OR', 'OR-DISC-OVERPAY',      'Collection with Discount and Overpayment',           5, 'C', '101030103', 'ACCOUNTS RECEIVABLE - OTHERS', 1, 1, 1, 'Services amount (e.g. cutting fee) charged to client, additional to the invoice', 'SERVICES', 'HasServices', NULL),
    ('OR', 'OR-EWT',               'Collection with Client EWT',                         4, 'C', '101030103', 'ACCOUNTS RECEIVABLE - OTHERS', 1, 1, 1, 'Services amount (e.g. cutting fee) charged to client, additional to the invoice', 'SERVICES', 'HasServices', NULL),
    ('OR', 'OR-EWT-DISC',          'Collection with EWT and Discount',                   5, 'C', '101030103', 'ACCOUNTS RECEIVABLE - OTHERS', 1, 1, 1, 'Services amount (e.g. cutting fee) charged to client, additional to the invoice', 'SERVICES', 'HasServices', NULL),
    ('OR', 'OR-EWT-DISC-OFFSET',   'Collection with EWT, Discount and Advance Offset',   6, 'C', '101030103', 'ACCOUNTS RECEIVABLE - OTHERS', 1, 1, 1, 'Services amount (e.g. cutting fee) charged to client, additional to the invoice', 'SERVICES', 'HasServices', NULL),
    ('OR', 'OR-EWT-DISC-OVERPAY',  'Collection with EWT, Discount and Overpayment',      6, 'C', '101030103', 'ACCOUNTS RECEIVABLE - OTHERS', 1, 1, 1, 'Services amount (e.g. cutting fee) charged to client, additional to the invoice', 'SERVICES', 'HasServices', NULL),
    ('OR', 'OR-EWT-OFFSET',        'Collection with EWT and Advance Offset',             5, 'C', '101030103', 'ACCOUNTS RECEIVABLE - OTHERS', 1, 1, 1, 'Services amount (e.g. cutting fee) charged to client, additional to the invoice', 'SERVICES', 'HasServices', NULL),
    ('OR', 'OR-EWT-OVERPAY',       'Collection with EWT and Overpayment',                5, 'C', '101030103', 'ACCOUNTS RECEIVABLE - OTHERS', 1, 1, 1, 'Services amount (e.g. cutting fee) charged to client, additional to the invoice', 'SERVICES', 'HasServices', NULL),
    ('OR', 'OR-OFFSET',            'Collection with Offset/Advance',                     4, 'C', '101030103', 'ACCOUNTS RECEIVABLE - OTHERS', 1, 1, 1, 'Services amount (e.g. cutting fee) charged to client, additional to the invoice', 'SERVICES', 'HasServices', NULL),
    ('OR', 'OR-OVERPAY',           'Collection with Overpayment only',                   4, 'C', '101030103', 'ACCOUNTS RECEIVABLE - OTHERS', 1, 1, 1, 'Services amount (e.g. cutting fee) charged to client, additional to the invoice', 'SERVICES', 'HasServices', NULL);
END

-------------------------------------------------------------------
-- 4. sp_GetClientPaymentDetails: the "lines" result set (3rd SELECT) feeds
--    PrefillEntryFromReversedPayment() in ClientPaymentsDevExAcctg.cs for
--    the reverse-and-re-enter edit flow. Without ServicesAmount here, an
--    edited payment that originally had a services fee would silently lose
--    it on re-entry -- ServicesAmount would prefill to 0 while
--    SuggestedAmountPaid (if left unadjusted) would no longer match what
--    was actually entered before.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.sp_GetClientPaymentDetails_OLD_09012026220000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.sp_GetClientPaymentDetails', 'P') IS NOT NULL
        DROP PROCEDURE dbo.sp_GetClientPaymentDetails;
END
ELSE IF OBJECT_ID('dbo.sp_GetClientPaymentDetails', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.sp_GetClientPaymentDetails', 'sp_GetClientPaymentDetails_OLD_09012026220000';
END
GO

-- Original proc was created with QUOTED_IDENTIFIER OFF -- pin it explicitly,
-- same reasoning as sp_AddPaymentClient above.
SET QUOTED_IDENTIFIER OFF;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE dbo.sp_GetClientPaymentDetails
(
    @PaymentHeaderID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Header
    SELECT
        ph.PaymentHeaderID,
        ph.CustomerKey,
        ph.ReferenceNo,
        ph.ControlNo,
        ph.CRNo,
        ph.PaymentType,
        ph.TotalAmount,
        ph.PaymentDate,
        ph.Remarks,
        ph.CreatedBy,
        ph.CreatedDate,
        ph.Status,
        apd.DebitGLCode,
        apd.CreditGLCode,
        tc.CheckNo,
        tc.CheckName,
        tc.CheckBankName,
        tc.CheckAmount,
        tc.CheckDate,
        ton.BankRefNumber,
        ton.BankName,
        ton.DateDeposit,
        CASE WHEN ph.Status = 'REVERSED' THEN 'Already Reversed' ELSE NULL END AS BlockedReason
    FROM dbo.PaymentHeader ph
    OUTER APPLY (
        SELECT TOP 1 a.DebitGLCode, a.CreditGLCode
        FROM dbo.ARPaymentDetails a
        WHERE a.PaymentHeaderID = ph.PaymentHeaderID
        ORDER BY CASE WHEN a.PaymentType = 'INVOICE PAYMENT' THEN 0 ELSE 1 END, a.InvoiceNo
    ) apd
    OUTER APPLY (
        SELECT TOP 1 t.CheckNo, t.CheckName, t.CheckBankName, t.CheckAmount, t.CheckDate
        FROM dbo.TransactionCheque t
        WHERE t.PaymentHeaderID = ph.PaymentHeaderID
        ORDER BY t.SequenceNo
    ) tc
    OUTER APPLY (
        SELECT TOP 1 o.BankRefNumber, o.BankName, o.DateDeposit
        FROM dbo.TransactionOnline o
        WHERE o.PaymentHeaderID = ph.PaymentHeaderID
        ORDER BY o.SequenceNumber
    ) ton
    WHERE ph.PaymentHeaderID = @PaymentHeaderID;

    -- GL Entries
    SELECT
        td.AccountCode,
        coa.Description AS AccountTitle,
        td.Debit,
        td.Credit
    FROM dbo.TicketDetails td
    JOIN dbo.ChartOfAccounts coa ON coa.AccountCode = td.AccountCode
    WHERE td.ReferenceNumber = (SELECT ReferenceNo FROM dbo.PaymentHeader WHERE PaymentHeaderID = @PaymentHeaderID)
    ORDER BY td.Debit DESC, td.Credit DESC;

    -- Lines, one row per invoice - GrossAmount/EWT/Discount/Offset/OverPay/
    -- ServicesAmount are the raw components; SuggestedAmountPaid
    -- reconstructs the net cash figure using the same formula
    -- InsertARPaymentDetails/RecalculateRow used to derive it in the first
    -- place (paid = gross - ewt - disc - offset + overpay + services), so
    -- pre-fill shows what was actually entered before.
    SELECT
        InvoiceNo,
        PONumber AS OrderNo,
        MAX(InvoiceDate) AS TransactionDate,
        SUM(CASE WHEN PaymentType = 'INVOICE PAYMENT' THEN Amount ELSE 0 END) AS GrossAmount,
        SUM(CASE WHEN PaymentType = 'EWT'              THEN Amount ELSE 0 END) AS EWTAmount,
        SUM(CASE WHEN PaymentType = 'DISCOUNT'          THEN Amount ELSE 0 END) AS DiscountAmount,
        SUM(CASE WHEN PaymentType = 'OFFSET'            THEN Amount ELSE 0 END) AS OffsetAmount,
        SUM(CASE WHEN PaymentType = 'OVERPAY'           THEN Amount ELSE 0 END) AS OverPay,
        SUM(CASE WHEN PaymentType = 'SERVICES'          THEN Amount ELSE 0 END) AS ServicesAmount,
        SUM(CASE WHEN PaymentType = 'INVOICE PAYMENT' THEN Amount ELSE 0 END)
          - SUM(CASE WHEN PaymentType = 'EWT'      THEN Amount ELSE 0 END)
          - SUM(CASE WHEN PaymentType = 'DISCOUNT' THEN Amount ELSE 0 END)
          - SUM(CASE WHEN PaymentType = 'OFFSET'   THEN Amount ELSE 0 END)
          + SUM(CASE WHEN PaymentType = 'OVERPAY'  THEN Amount ELSE 0 END)
          + SUM(CASE WHEN PaymentType = 'SERVICES' THEN Amount ELSE 0 END) AS SuggestedAmountPaid
    FROM dbo.ARPaymentDetails
    WHERE PaymentHeaderID = @PaymentHeaderID
    GROUP BY InvoiceNo, PONumber
    ORDER BY InvoiceNo;
END
GO

PRINT 'DEPLOYMENT COMPLETE: splist_ARAccounts (+ServicesAmount), sp_AddPaymentClient (+SERVICES cash/GL handling), JournalEntryMapping (+12 HasServices credit rows, OR-COLL debit switched to NET), sp_GetClientPaymentDetails (+ServicesAmount in reversal/edit prefill).';
