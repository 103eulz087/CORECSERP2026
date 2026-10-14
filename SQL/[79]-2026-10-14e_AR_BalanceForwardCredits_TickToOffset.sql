/* ================================================================
   [79] 2026-10-14 - AR: balance-forward credits listed one by one and ticked against new invoices
   ================================================================
   User + accountant 2026-10-14 (Feature 9): the negative balance-forward rows of TransactionChargeSales (Peachtree
   credits loaded at go-live, 205 rows / 145 customers / -2,079,610.34 on PRODUCTION, none touched yet) are unidentified
   credits on their side. They must stay visible ONE BY ONE (not summed into Available Credit) so a customer can trace a
   credit by invoice, and staff tick them against a new invoice: invoice 1,000 + credit -300 ticked = pay 700.
   Balance-forward only: new overpayments keep the Overpay / OverPayIncome / Offset columns, EWT and discount keep theirs.
   The opening AR is already net of these credits, so applying one moves no GL account: cash 700 = CR AR 700.

   A balance-forward credit = a TransactionChargeSales row with a negative TotalAmount (the system never writes one).

   1. splist_ARAccounts: optional @IncludeCredits BIT = 0. With 1, the open credits are listed after the invoices,
      InvoiceType 'BF CREDIT', Balance negative. Without it, the same rows as before (the older HOFormsDevEx screen).
   2. sp_AddPaymentClient: a ticked credit arrives as an INVOICE PAYMENT line with a NEGATIVE Amount (the credit used),
      so @Gross, the invoice updates, the ledger and the reversal all work on the existing formulas.
        92010  a negative line not on an open balance-forward credit of this customer
        92011  any other line on a credit row (payment, EWT, discount, offset, overpay, services)
        92012  more than what is left of the credit, read now under UPDLOCK (stale screen / used by another payment)
        92014  credits ticked > invoices ticked (the amount to pay can't go below 0)
        92001  now allows a payment that nets to 0 because credits cover the invoices
      A credits-only payment (net 0) posts no ticket and no DIT. Ledger: a credit used is a DEBIT on the customer
      (Description 'BF CREDIT <invoice> APPLIED - ...'). PayStatus: Balance 0 = FULLYPAID; a credit with some left
      stays UNPAID / PARTIAL (else it would drop out of the list); everything else as before.
   3. sp_ReversePaymentClient: the same PayStatus rule (a credit given back by a reversal stays open instead of turning
      FULLYPAID at -300 and disappearing); no reversal ticket number for a payment that had no ticket.

   The three procs were byte-identical on DEV, STAGING and PRODUCTION on 2026-10-14; the script stops unless each one is
   still that original (SHA-256 below). Backups _OLD_10142026190000. One transaction; a failed step rolls everything back.
   Needs the new exe to be used (it sends @IncludeCredits and the negative lines); the old exe works as before.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- 0. prerequisite: the originals ---------------------------------------------------------------------------------------------
IF CHARINDEX('[79]', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentClient'))) > 0
BEGIN
    RAISERROR('[79] already applied here; nothing to do.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF ISNULL(CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentClient'))), 1), '')
          <> '0xFC510EE0A14A3655898D0C7F5B94AA766E3A46AF64A44C25DF8EE8979DF67E6D'
     OR ISNULL(CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient'))), 1), '')
          <> '0x41DB8AF196C524C19797C9DDFC8ADC77E315929858F4F5E5B116BFE098827FC8'
     OR ISNULL(CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', OBJECT_DEFINITION(OBJECT_ID('dbo.splist_ARAccounts'))), 1), '')
          <> '0x25332A297768F5FBF2B76AEEFF54EE0827C3C463F643B1BACD6B43144F4AD6D5'
     OR OBJECT_ID('dbo.sp_AddPaymentClient_OLD_10142026190000') IS NOT NULL
     OR OBJECT_ID('dbo.sp_ReversePaymentClient_OLD_10142026190000') IS NOT NULL
     OR OBJECT_ID('dbo.splist_ARAccounts_OLD_10142026190000') IS NOT NULL
BEGIN
    RAISERROR('[79] stopped, nothing changed: sp_AddPaymentClient / sp_ReversePaymentClient / splist_ARAccounts is not the 2026-10-14 original here (or a backup _OLD_10142026190000 already exists). Compare before applying.', 16, 1);
    SET NOEXEC ON;
END
GO

BEGIN TRANSACTION;
GO

EXEC sp_rename 'dbo.sp_AddPaymentClient', 'sp_AddPaymentClient_OLD_10142026190000';
EXEC sp_rename 'dbo.sp_ReversePaymentClient', 'sp_ReversePaymentClient_OLD_10142026190000';
EXEC sp_rename 'dbo.splist_ARAccounts', 'splist_ARAccounts_OLD_10142026190000';
GO

-- 1. splist_ARAccounts --------------------------------------------------------------------------------------------------------

CREATE PROCEDURE [dbo].[splist_ARAccounts]
	@parmcustkey varchar(100),
	@IncludeCredits BIT = 0   -- [79] 1 = also list the open balance-forward credits (InvoiceType 'BF CREDIT')
AS
/*  [79] 2026-10-14: with @IncludeCredits = 1 (Client Payments, AccountingDevEx) the open balance-forward credits are listed
    too, one row each, Balance negative, after the invoices. A balance-forward credit = a row with a negative TotalAmount
    (Peachtree credits loaded at go-live; the system itself never writes a negative invoice). Without the parameter
    (HOFormsDevEx/ClientPaymentsDevEx, older exe) the rows and columns are as before (now sorted by date). */
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
		OverPayIncome decimal(12,2),
		ServicesAmount decimal(12,2),
		InvoiceType varchar(15)
	)

	truncate table #temptemp
	insert into #temptemp
		(TransactionDate, OrderNo, InvoiceNo, InvoiceAmount, Balance,
		 EWTAmount, DiscountAmount, OffsetAmount, OverPay, OverPayIncome, ServicesAmount, InvoiceType)
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
	CAST(0 AS DECIMAL(12,2)) as OverPayIncome,
	CAST(0 AS DECIMAL(12,2)) as ServicesAmount,
	'SALES'
	FROM TransactionChargeSales
	WHERE (PayStatus='UNPAID' OR PayStatus='PARTIAL')
	AND Balance > 0
	and CustomerKey=@parmcustkey

	-- [79] open balance-forward credits
	IF @IncludeCredits = 1
		insert into #temptemp
			(TransactionDate, OrderNo, InvoiceNo, InvoiceAmount, Balance,
			 EWTAmount, DiscountAmount, OffsetAmount, OverPay, OverPayIncome, ServicesAmount, InvoiceType)
		SELECT
		CAST(TransactionDate as date),
		ReferenceNo,
		InvoiceNo,
		TotalAmount,
		Balance,
		0, 0, 0, 0, 0, 0,
		'BF CREDIT'
		FROM TransactionChargeSales
		WHERE (PayStatus='UNPAID' OR PayStatus='PARTIAL')
		AND TotalAmount < 0
		AND Balance < 0
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
		OverPayIncome,
		ServicesAmount,
		'' as Remarks
	FROM #temptemp
	ORDER BY CASE WHEN InvoiceType = 'BF CREDIT' THEN 1 ELSE 0 END, TransactionDate, InvoiceNo   -- [79] invoices first, then the credits

END

GO

-- 2. sp_AddPaymentClient ------------------------------------------------------------------------------------------------------

CREATE PROCEDURE [dbo].[sp_AddPaymentClient]
    @PaymentHeaderID INT
AS
/*  [79] 2026-10-14: balance-forward credits (user + accountant). A balance-forward row of TransactionChargeSales with a
    negative TotalAmount (Peachtree credits loaded at go-live; the system itself never writes a negative invoice) can be
    ticked against new invoices. Its line is an INVOICE PAYMENT with a NEGATIVE Amount (the credit used), so @Gross is
    already net of it: invoice 1,000 + credit -300 = cash 700 = CR AR 700 (the opening AR is net of these credits).
    Rules 92010-92014 below; a credits-only payment (net 0) posts no ticket and no DIT; a part-used credit stays open
    (PayStatus PARTIAL). Overpay / EWT / discount / offset keep their own columns: not allowed on a credit row. */
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
        @EWT      DECIMAL(18,2),
        @Discount DECIMAL(18,2),
        @Offset   DECIMAL(18,2),   -- advance deposit applied (reduces cash)
        @Overpay  DECIMAL(18,2),   -- excess cash received, carried forward as customer credit (20115)
        @OverPayIncome DECIMAL(18,2), -- excess cash received, declared immediately as Other Income (404) -- NOT carried forward
        @Services DECIMAL(18,2),   -- additional fee billed to client (e.g. cutting fee) -- goes to AR-Others

        -- Net cash variants - different direction for each scenario
        @Net         DECIMAL(18,2),  -- plain: Gross - EWT - Discount [+ Services]
        @NetOffset   DECIMAL(18,2),  -- with offset:  Gross - EWT - Discount - Offset [+ Services]
        @NetOverpay  DECIMAL(18,2),  -- with overpay: Gross - EWT - Discount + Overpay [+ Services]
        @NetOverpayIncome DECIMAL(18,2), -- with overpay-as-income: Gross - EWT - Discount + OverPayIncome [+ Services]

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
        @OverPayIncome = ISNULL(SUM(CASE WHEN PaymentType = 'OVERPAYINCOME' THEN Amount ELSE 0 END), 0),
        @Services = ISNULL(SUM(CASE WHEN PaymentType = 'SERVICES'        THEN Amount ELSE 0 END), 0)
    FROM ARPaymentDetails
    WHERE PaymentHeaderID = @PaymentHeaderID;



    -- [79] balance-forward credits ticked in this payment (negative INVOICE PAYMENT lines), as a positive total
    DECLARE @BFCredit DECIMAL(18,2) =
        ISNULL((SELECT -SUM(Amount) FROM ARPaymentDetails
                WHERE PaymentHeaderID = @PaymentHeaderID AND PaymentType = 'INVOICE PAYMENT' AND Amount < 0), 0);

    IF @Gross = 0 AND @BFCredit = 0   -- [79] invoices fully covered by credits net to 0 and are allowed
    BEGIN
        ROLLBACK;
        THROW 92001, 'No INVOICE PAYMENT rows found for this PaymentHeaderID.', 1;
    END

    IF @Gross < 0   -- [79]
    BEGIN
        ROLLBACK;
        THROW 92014, 'The balance-forward credits ticked are more than the invoices ticked. Use less of a credit (the amount to pay cannot go below 0).', 1;
    END

    -- Guard: Offset, Overpay, and OverPayIncome are pairwise mutually
    -- exclusive -- each one selects a different, non-overlapping branch of
    -- the Mnemonic matrix below (Offset draws down 20115, Overpay credits
    -- 20115, OverPayIncome credits 404). Combining any two would make the
    -- Mnemonic CASE silently pick just one branch and drop the other leg's
    -- JournalEntryMapping rows entirely -- an unbalanced/wrong posting with
    -- no error surfaced until (at best) the DR<>CR check further down. This
    -- is a structural requirement of the mnemonic-matrix design, not just
    -- the Overpay/OverPayIncome business rule it was originally written for.
    IF (CASE WHEN @Offset > 0 THEN 1 ELSE 0 END
      + CASE WHEN @Overpay > 0 THEN 1 ELSE 0 END
      + CASE WHEN @OverPayIncome > 0 THEN 1 ELSE 0 END) > 1
    BEGIN
        ROLLBACK;
        THROW 92003, 'Offset, Overpayment, and Overpay-as-Income cannot be combined in the same payment -- choose only one.', 1;
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

    -- [79] balance-forward credit lines: checked against the credit rows read now, under UPDLOCK (Known Bug #10),
    -- never against the screen's figures. Applies to every line on a credit row and to every negative line.
    IF EXISTS (SELECT 1 FROM ARPaymentDetails D
               WHERE D.PaymentHeaderID = @PaymentHeaderID AND D.PaymentType = 'INVOICE PAYMENT' AND D.Amount < 0)
       OR EXISTS (SELECT 1 FROM ARPaymentDetails D
                  JOIN TransactionChargeSales T ON T.InvoiceNo = D.InvoiceNo AND T.ReferenceNo = D.PONumber AND T.CustomerKey = @custkey
                  WHERE D.PaymentHeaderID = @PaymentHeaderID AND T.TotalAmount < 0)
    BEGIN
        DECLARE @bfInv VARCHAR(100), @bfMsg NVARCHAR(400);

        IF OBJECT_ID('tempdb..#BF') IS NOT NULL DROP TABLE #BF;
        SELECT D.InvoiceNo, D.PONumber,
               SUM(CASE WHEN D.PaymentType = 'INVOICE PAYMENT' THEN D.Amount ELSE 0 END)                     AS Applied,
               SUM(CASE WHEN D.PaymentType = 'INVOICE PAYMENT' AND D.Amount < 0 THEN 1 ELSE 0 END)           AS NegLines,
               SUM(CASE WHEN D.PaymentType = 'INVOICE PAYMENT' AND D.Amount < 0 THEN 0 ELSE 1 END)           AS OtherLines
        INTO #BF
        FROM ARPaymentDetails D
        WHERE D.PaymentHeaderID = @PaymentHeaderID
        GROUP BY D.InvoiceNo, D.PONumber;

        -- fresh read of the rows, locked until COMMIT
        IF OBJECT_ID('tempdb..#BFRow') IS NOT NULL DROP TABLE #BFRow;
        SELECT b.InvoiceNo, b.PONumber, b.Applied, b.NegLines, b.OtherLines,
               T.TotalAmount, T.Balance, T.PayStatus, CAST(CASE WHEN T.InvoiceNo IS NULL THEN 0 ELSE 1 END AS BIT) AS Found
        INTO #BFRow
        FROM #BF b
        LEFT JOIN TransactionChargeSales T WITH (UPDLOCK, HOLDLOCK)
               ON T.InvoiceNo = b.InvoiceNo AND T.ReferenceNo = b.PONumber AND T.CustomerKey = @custkey;

        -- 92010: a negative line must be on an open balance-forward credit of this customer
        SELECT TOP 1 @bfInv = InvoiceNo FROM #BFRow
        WHERE NegLines > 0
          AND (Found = 0 OR TotalAmount >= 0 OR Balance >= 0 OR ISNULL(PayStatus, '') NOT IN ('UNPAID', 'PARTIAL'))
        ORDER BY InvoiceNo;
        IF @bfInv IS NOT NULL
        BEGIN
            ROLLBACK;
            SET @bfMsg = N'Invoice ' + @bfInv + N' is not an open balance-forward credit of this customer, so it cannot be applied as a credit.';
            THROW 92010, @bfMsg, 1;
        END

        -- 92011: on a credit row only the credit itself is applied (no payment, EWT, discount, offset, overpay, services)
        SELECT TOP 1 @bfInv = InvoiceNo FROM #BFRow
        WHERE Found = 1 AND TotalAmount < 0 AND OtherLines > 0
        ORDER BY InvoiceNo;
        IF @bfInv IS NOT NULL
        BEGIN
            ROLLBACK;
            SET @bfMsg = N'Balance-forward credit ' + @bfInv + N' can only be ticked as a credit; payment, EWT, discount, offset, overpay and services go on the invoice being paid.';
            THROW 92011, @bfMsg, 1;
        END

        -- 92012: no more than what is left of the credit now (both negative: Applied below Balance = too much)
        SELECT TOP 1 @bfInv = InvoiceNo FROM #BFRow
        WHERE Found = 1 AND TotalAmount < 0 AND Applied < Balance
        ORDER BY InvoiceNo;
        IF @bfInv IS NOT NULL
        BEGIN
            -- message first: the ROLLBACK drops #BFRow (created inside the transaction)
            SELECT @bfMsg = N'Balance-forward credit ' + InvoiceNo + N' has only ' + CONVERT(NVARCHAR(30), CAST(-Balance AS MONEY), 1)
                          + N' left, but ' + CONVERT(NVARCHAR(30), CAST(-Applied AS MONEY), 1)
                          + N' was applied (it may have been used by another payment). Reload the customer and try again.'
            FROM #BFRow WHERE InvoiceNo = @bfInv;
            ROLLBACK;
            THROW 92012, @bfMsg, 1;
        END
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

    -- Compute all net variants upfront -- Services adds to every variant
    -- since it is real additional cash the client pays, regardless of which
    -- other deduction/addition combination is in play.
    SET @Net        = @Gross - @EWT - @Discount + @Services;                  -- base (no offset/overpay)
    SET @NetOffset  = @Gross - @EWT - @Discount - @Offset + @Services;        -- client pays less
    SET @NetOverpay = @Gross - @EWT - @Discount + @Overpay + @Services;       -- client pays more
    SET @NetOverpayIncome = @Gross - @EWT - @Discount + @OverPayIncome + @Services; -- client pays more, excess is income

    -- BankCash = what actually hits the bank account this transaction
    SET @BankCash =
        CASE
            WHEN @Offset  > 0 THEN @NetOffset
            WHEN @Overpay > 0 THEN @NetOverpay
            WHEN @OverPayIncome > 0 THEN @NetOverpayIncome
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
    -- (EXCLUDING Services and Overpay/OverPayIncome, all of which are
    -- additive cash with no invoice-settlement meaning) separately, before
    -- Services ever gets a chance to offset it.
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
    -- can no longer actually go negative (Services/Overpay/OverPayIncome
    -- are the only terms separating @BankCash from
    -- @InvoiceNetExclServices, and all are always >= 0), but keep it
    -- rather than trust that invariant silently.
    IF @BankCash < 0
    BEGIN
        ROLLBACK;
        THROW 92005, 'EWT/Discount/Offset total exceeds the amount being settled - deductions cannot exceed Gross.', 1;
    END

    -------------------------------------------------------
    -- 3. DETERMINE MNEMONIC
    -- Full scenario matrix covering all combinations. Services is
    -- deliberately NOT part of this matrix -- see file header comment;
    -- it applies as a cross-cutting conditional row on every mnemonic.
    -------------------------------------------------------
    SET @Mnemonic =
        CASE
            -- EWT + Discount combinations
            WHEN @EWT > 0 AND @Discount > 0 AND @Overpay > 0       THEN 'OR-EWT-DISC-OVERPAY'
            WHEN @EWT > 0 AND @Discount > 0 AND @OverPayIncome > 0 THEN 'OR-EWT-DISC-OVERPAYINCOME'
            WHEN @EWT > 0 AND @Discount > 0 AND @Offset  > 0       THEN 'OR-EWT-DISC-OFFSET'
            WHEN @EWT > 0 AND @Discount > 0                         THEN 'OR-EWT-DISC'
            -- EWT only combinations
            WHEN @EWT > 0 AND @Overpay > 0                          THEN 'OR-EWT-OVERPAY'
            WHEN @EWT > 0 AND @OverPayIncome > 0                    THEN 'OR-EWT-OVERPAYINCOME'
            WHEN @EWT > 0 AND @Offset  > 0                          THEN 'OR-EWT-OFFSET'
            WHEN @EWT > 0                                            THEN 'OR-EWT'
            -- Discount only combinations
            WHEN @Discount > 0 AND @Overpay > 0                     THEN 'OR-DISC-OVERPAY'
            WHEN @Discount > 0 AND @OverPayIncome > 0               THEN 'OR-DISC-OVERPAYINCOME'
            WHEN @Discount > 0 AND @Offset  > 0                     THEN 'OR-DISC-OFFSET'
            WHEN @Discount > 0                                       THEN 'OR-DISC'
            -- Offset/Overpay/OverPayIncome alone
            WHEN @Overpay > 0                                        THEN 'OR-OVERPAY'
            WHEN @OverPayIncome > 0                                  THEN 'OR-OVERPAYINCOME'
            WHEN @Offset  > 0                                        THEN 'OR-OFFSET'
            -- Plain collection
            ELSE                                                          'OR-COLL'
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
                WHEN 'NET'         THEN @Net           -- base: no offset/overpay
                WHEN 'NET_OFFSET'  THEN @NetOffset      -- with advance deposit
                WHEN 'NET_OVERPAY' THEN @NetOverpay     -- with excess cash
                WHEN 'NET_OVERPAYINCOME' THEN @NetOverpayIncome -- with excess cash declared as income
                WHEN 'EWT'         THEN @EWT
                WHEN 'OFFSET'      THEN @Offset         -- DR Customer Advances / Overpayments (20115)
                WHEN 'OVERPAY'     THEN @Overpay        -- CR Customer Advances / Overpayments (20115)
                WHEN 'OVERPAYINCOME' THEN @OverPayIncome -- CR Other Income (404)
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
          OR (M.ConditionFlag = 'HasOverpayIncome' AND @OverPayIncome > 0)
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
            @OverPayIncome   AS OverPayIncome,
            @Services        AS Services,
            @Net             AS Net,
            @NetOffset       AS NetOffset,
            @NetOverpay      AS NetOverpay,
            @NetOverpayIncome AS NetOverpayIncome,
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
          AND T.ReferenceNo     = D.PONumber
          AND D.PaymentType     = 'INVOICE PAYMENT'
          AND T.CustomerKey     = @custkey
    );

    -- EWT per invoice
    UPDATE T
    SET T.EWTAmount = ISNULL(T.EWTAmount, 0) + D.Amount
    FROM TransactionChargeSales T
    JOIN ARPaymentDetails D ON T.InvoiceNo = D.InvoiceNo
    AND T.ReferenceNo=D.PONumber
    WHERE D.PaymentHeaderID = @PaymentHeaderID
      AND T.CustomerKey     = @custkey
      AND D.PaymentType     = 'EWT';

    -- Discount per invoice
    UPDATE T
    SET T.DiscountAmount = ISNULL(T.DiscountAmount, 0) + D.Amount
    FROM TransactionChargeSales T
    JOIN ARPaymentDetails D ON T.InvoiceNo = D.InvoiceNo
    AND T.ReferenceNo=D.PONumber
    WHERE D.PaymentHeaderID = @PaymentHeaderID
      AND T.CustomerKey     = @custkey
      AND D.PaymentType     = 'DISCOUNT';

     -- Offset per invoice --include by eulz
    UPDATE T
    SET T.OffsetAmount = ISNULL(T.OffsetAmount, 0) + D.Amount
    FROM TransactionChargeSales T
    JOIN ARPaymentDetails D ON T.InvoiceNo = D.InvoiceNo
    AND T.ReferenceNo=D.PONumber
    WHERE D.PaymentHeaderID = @PaymentHeaderID
      AND T.CustomerKey     = @custkey
      AND D.PaymentType     = 'OFFSET';

      -- Offset per invoice --include by eulz
      -- NOTE (2026-09-23): deliberately PaymentType='OVERPAY' only, not
      -- 'OVERPAYINCOME' -- AdvancePayment represents a refundable/
      -- offsettable balance the customer can still draw down; OverPayIncome
      -- is recognized straight to revenue and is neither refundable nor
      -- offsettable, so it must not inflate this column.
    UPDATE T
    SET T.AdvancePayment = ISNULL(T.AdvancePayment, 0) + D.Amount
    FROM TransactionChargeSales T
    JOIN ARPaymentDetails D ON T.InvoiceNo = D.InvoiceNo
    AND T.ReferenceNo=D.PONumber
    WHERE D.PaymentHeaderID = @PaymentHeaderID
      AND T.CustomerKey     = @custkey
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
          AND T.ReferenceNo=D.PONumber
          AND T.CustomerKey     = @custkey
    );

    -------------------------------------------------------
    -- 8. UPDATE PAYSTATUS
    -------------------------------------------------------
    UPDATE T
    SET T.PayStatus =
        CASE
            WHEN T.Balance = 0 THEN 'FULLYPAID'
            -- [79] a balance-forward credit with some left stays open (else it would drop out of the list)
            WHEN T.TotalAmount < 0 THEN CASE WHEN ISNULL(T.AmountPaid, 0) <> 0 THEN 'PARTIAL' ELSE 'UNPAID' END
            WHEN T.Balance < 0 THEN 'FULLYPAID'
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
          AND T.ReferenceNo=D.PONumber
          AND T.CustomerKey     = @custkey
    );

    -------------------------------------------------------
    -- 9. TICKET MASTER
    -------------------------------------------------------
    -- [79] a payment settled only with balance-forward credits moves no cash and no GL account (the opening AR is
    -- already net of the credits): no ticket. The ledger rows below still record it, with no ticket reference.
    IF @Debit <> 0
    BEGIN
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
    END   -- [79] IF @Debit <> 0

    -------------------------------------------------------
    -- 11. CLIENTLEDGER
    -- Posts one row per invoice for the gross amount settled.
    -- Services (like Overpay/OverPayIncome) has no invoice linkage -- NOT
    -- posted here.
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
        -- [79] a balance-forward credit used (negative line) is a DEBIT on the customer: it takes the credit off
        @date, '888', CASE WHEN D.Amount < 0 THEN LEFT('BF CREDIT ' + D.InvoiceNo + ' APPLIED - ' + ISNULL(@remarks, ''), 150) ELSE @remarks END,
        @Mnemonic, @date,
        @refno, '', D.InvoiceNo,
        CASE WHEN D.Amount < 0 THEN -D.Amount ELSE 0 END, CASE WHEN D.Amount > 0 THEN D.Amount ELSE 0 END, 0, 0,
        @refno, @preparedby, '*',
        CASE WHEN D.Amount < 0 THEN 'BF CREDIT APPLIED' ELSE @remarks END, ABS(D.Amount), 0, @TicketNo
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
            CreatedBy, CreatedDate, ControlNo   -- 2026-10-02e
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
            GETDATE(),
            (SELECT NULLIF(LTRIM(RTRIM(ControlNo)), '') FROM dbo.PaymentHeader WHERE PaymentHeaderID = @PaymentHeaderID)   -- 2026-10-02e: the payment's control number
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

-- 3. sp_ReversePaymentClient --------------------------------------------------------------------------------------------------

-- ============================================================
-- sp_ReversePaymentClient — sync Balance formula with SP above
--
-- Only change from previous version: Balance recalculation
-- now excludes OffsetAmount (matching Step 7 above).
-- All other reversal logic unchanged.
-- ============================================================
CREATE PROCEDURE [dbo].[sp_ReversePaymentClient]
    @PaymentHeaderID INT,
    @ReversedBy      VARCHAR(50)
AS
/*  [79] 2026-10-14: PayStatus keeps a balance-forward credit (negative TotalAmount) open when its use is reversed (it
    used to become FULLYPAID at Balance <= 0 and drop out of the payment list); a payment settled only with credits has
    no ticket, so no reversal ticket number is taken for it. Everything else unchanged. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRAN;

    -------------------------------------------------------
    -- 1. VALIDATE
    -------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1 FROM PaymentHeader WHERE PaymentHeaderID = @PaymentHeaderID
    )
    BEGIN
        ROLLBACK;
        THROW 60000, 'PaymentHeader not found.', 1;
    END

    IF EXISTS (
        SELECT 1 FROM PaymentHeader
        WHERE PaymentHeaderID = @PaymentHeaderID AND Status = 'REVERSED'
    )
    BEGIN
        ROLLBACK;
        THROW 60001, 'Transaction already reversed.', 1;
    END

    -------------------------------------------------------
    -- 2. LOAD HEADER
    -------------------------------------------------------
    DECLARE
        @custkey     CHAR(8),
        @refno       VARCHAR(20),
        @reversalRef VARCHAR(22),
        @paymentDate DATE,
        @remarks     VARCHAR(500);

    SELECT
        @custkey = CustomerKey,
        @refno   = ReferenceNo,
        @paymentDate = PaymentDate,
        @remarks = 'REVERSAL of ' + ReferenceNo
    FROM PaymentHeader
    WHERE PaymentHeaderID = @PaymentHeaderID;

    SET @reversalRef = LEFT(@refno + '-REV', 22);

    -------------------------------------------------------
    -- 3. REVERSE AmountPaid (net cash per invoice)
    -------------------------------------------------------
    UPDATE T
    SET T.AmountPaid = T.AmountPaid -
        (
            ISNULL((SELECT SUM(D.Amount) FROM ARPaymentDetails D
                    WHERE D.PaymentHeaderID = @PaymentHeaderID
                      AND D.InvoiceNo = T.InvoiceNo
                      AND D.PaymentType = 'INVOICE PAYMENT'), 0)
          - ISNULL((SELECT SUM(D.Amount) FROM ARPaymentDetails D
                    WHERE D.PaymentHeaderID = @PaymentHeaderID
                      AND D.InvoiceNo = T.InvoiceNo
                      AND D.PaymentType = 'EWT'), 0)
          - ISNULL((SELECT SUM(D.Amount) FROM ARPaymentDetails D
                    WHERE D.PaymentHeaderID = @PaymentHeaderID
                      AND D.InvoiceNo = T.InvoiceNo
                      AND D.PaymentType = 'DISCOUNT'), 0)
          - ISNULL((SELECT SUM(D.Amount) FROM ARPaymentDetails D
                    WHERE D.PaymentHeaderID = @PaymentHeaderID
                      AND D.InvoiceNo = T.InvoiceNo
                      AND D.PaymentType = 'OFFSET'), 0)
        )
    FROM TransactionChargeSales T
    WHERE EXISTS (
        SELECT 1 FROM ARPaymentDetails D
        WHERE D.PaymentHeaderID = @PaymentHeaderID
          AND D.InvoiceNo = T.InvoiceNo
          AND D.PaymentType = 'INVOICE PAYMENT'
    );

    -- Reverse EWT
    UPDATE T
    SET T.EWTAmount = ISNULL(T.EWTAmount, 0) - P.Amount
    FROM TransactionChargeSales T
    JOIN ARPaymentDetails P ON T.InvoiceNo = P.InvoiceNo
    WHERE P.PaymentHeaderID = @PaymentHeaderID
      AND P.PaymentType     = 'EWT';

    -- Reverse Discount
    UPDATE T
    SET T.DiscountAmount = ISNULL(T.DiscountAmount, 0) - P.Amount
    FROM TransactionChargeSales T
    JOIN ARPaymentDetails P ON T.InvoiceNo = P.InvoiceNo
    WHERE P.PaymentHeaderID = @PaymentHeaderID
      AND P.PaymentType     = 'DISCOUNT';

        -- Reverse Offset --Added By eulz
    UPDATE T
    SET T.OffsetAmount = ISNULL(T.OffsetAmount, 0) - P.Amount
    FROM TransactionChargeSales T
    JOIN ARPaymentDetails P ON T.InvoiceNo = P.InvoiceNo
    WHERE P.PaymentHeaderID = @PaymentHeaderID
      AND P.PaymentType     = 'OFFSET';

    UPDATE ARPaymentDetails 
    SET ErrorTag=1
    WHERE PaymentHeaderID=@PaymentHeaderID

    -- NOTE: No reversal needed for OFFSET or OVERPAY on TCS
    -- (neither was written to TCS during posting)

    -------------------------------------------------------
    -- 4. RECALCULATE BALANCE (same formula as posting SP)
    -------------------------------------------------------
    UPDATE T
    SET T.Balance =
        T.TotalAmount - (
            ISNULL(T.AmountPaid,    0) +
            ISNULL(T.EWTAmount,     0) +
            ISNULL(T.DiscountAmount,0) + 
            ISNULL(T.OffsetAmount,0)        --Added by Eulz
        )
    FROM TransactionChargeSales T
    WHERE EXISTS (
        SELECT 1 FROM ARPaymentDetails P
        WHERE P.PaymentHeaderID = @PaymentHeaderID
          AND P.InvoiceNo = T.InvoiceNo
    );

    -------------------------------------------------------
    -- 5. UPDATE PAYSTATUS (same logic as posting SP)
    -------------------------------------------------------
    UPDATE T
    SET T.PayStatus =
        CASE
            WHEN T.Balance = 0 THEN 'FULLYPAID'
            -- [79] a balance-forward credit given back stays open
            WHEN T.TotalAmount < 0 THEN CASE WHEN ISNULL(T.AmountPaid, 0) <> 0 THEN 'PARTIAL' ELSE 'UNPAID' END
            WHEN T.Balance < 0 THEN 'FULLYPAID'
            WHEN T.AmountPaid    > 0
              OR T.EWTAmount     > 0
              OR T.DiscountAmount> 0 THEN 'PARTIAL'
            ELSE 'UNPAID'
        END
    FROM TransactionChargeSales T
    WHERE EXISTS (
        SELECT 1 FROM ARPaymentDetails P
        WHERE P.PaymentHeaderID = @PaymentHeaderID
          AND P.InvoiceNo = T.InvoiceNo
    );

    -------------------------------------------------------
    -- 6. GET REVERSAL TICKET NUMBER
    -------------------------------------------------------
    DECLARE @ReversalTicketNo BIGINT;
    IF EXISTS (SELECT 1 FROM TicketMaster WHERE ReferenceNumber = @refno)   -- [79] credits-only payments have no ticket
        EXEC GetTicketNumber @ReversalTicketNo OUTPUT;

    -------------------------------------------------------
    -- 7. REVERSAL TICKET MASTER
    -------------------------------------------------------
    INSERT INTO TicketMaster
    (
        TicketDate, SupplementaryNumber, BranchCode, Origin,
        TicketNumber, ReferenceNumber, ReferenceKey,
        Owner, Particulars, EnteredBy,
        CheckedBy, ApprovedBy, Status, Mnemonic, Product
    )
    SELECT
        @paymentDate, 0, '888', '888',
        @ReversalTicketNo, @refno, TM.ReferenceKey,
        TM.Owner, 'REVERSAL: ' + TM.Particulars,
        @ReversedBy, '*', '*', 'REVERSED', NULL, @remarks
    FROM TicketMaster TM
    WHERE TM.ReferenceNumber = @refno;

    -------------------------------------------------------
    -- 8. REVERSE TICKET DETAILS (swap DR/CR)
    -------------------------------------------------------
    INSERT INTO TicketDetails
    (
        TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
        TicketNumber, ReferenceNumber,
        AccountCode, Debit, Credit, CostCenter
    )
    SELECT
        @paymentDate, 0, TD.BranchCode, TD.ReferenceKey,
        @ReversalTicketNo, @refno,
        TD.AccountCode,
        TD.Credit,  -- swapped
        TD.Debit,   -- swapped
        TD.CostCenter
    FROM TicketDetails TD
    WHERE TD.ReferenceNumber = @refno;

    -------------------------------------------------------
    -- 9. REVERSE CLIENT LEDGER --SELECT * FROM ClientLedger
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
        ROW_NUMBER() OVER (ORDER BY CL.InvoiceNo)
          + ISNULL((SELECT MAX(TRN_SEQ_NO) FROM ClientLedger WHERE AccountKey = @custkey), 0),
        CL.AccountKey, CL.AccountID,
        GETDATE(), CL.InitiatingBranch, @remarks,
        CL.TransCode, CL.TransactionDate,   -- 2026-10-09c: the reversed row's date (was the reversal day)
        @refno, CL.ReferenceKey, CL.InvoiceNo,
        CL.Credit, CL.Debit,  -- swapped
        0, 0,
        CL.ORNumber, @ReversedBy, '*',
        'REVERSAL ENTRY',
        CL.TotalAmount * -1, 0,
        @ReversalTicketNo
    FROM ClientLedger CL
    WHERE CL.ReferenceNumber = @refno;

    -------------------------------------------------------
    -- 10. MARK HEADER AS REVERSED
    -------------------------------------------------------
    UPDATE PaymentHeader
    SET Status       = 'REVERSED',
        ReversedBy   = @ReversedBy,
        ReversedDate = GETDATE()
    WHERE PaymentHeaderID = @PaymentHeaderID;

    -------------------------------------------------------
    -- 11. FLAG PAYMENT METHOD TABLES
    -------------------------------------------------------
    UPDATE TransactionCashCollection
    SET isErrorCorrect = 1
    WHERE PaymentHeaderID = @PaymentHeaderID;

    UPDATE TransactionCheque
    SET Remarks = 'REVERSED'
    WHERE PaymentHeaderID = @PaymentHeaderID;

    UPDATE TransactionOnline
    SET Remarks = 'REVERSED'
    WHERE PaymentHeaderID = @PaymentHeaderID;

    --UPDATE TransactionCreditCard
    --SET Remarks = 'REVERSED'
    --WHERE PaymentHeaderID = @PaymentHeaderID;

    -------------------------------------------------------
    -- 12. VOID DIT IN BANK RECON
    --
    -- Matches by SourceRef + SourceModule — works correctly
    -- regardless of HeaderID since SourceRef = @refno is unique.
    -- ResolvedReason = 'REVERSED' for audit trail.
    -------------------------------------------------------
    UPDATE BankStatementRecon
    SET IsResolved     = 1,
        ResolvedDate   = GETDATE(),
        ResolvedReason = 'REVERSED'
    WHERE SourceRef    = @refno
      AND SourceModule = 'AR-PAYMENT'
      AND ItemType     = 'DIT'
      AND IsResolved   = 0;

    -------------------------------------------------------
    COMMIT;
END

GO

-- post-check: the three new procs carry [79], the three backups exist
IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentClient')) NOT LIKE '%[[]79]%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient')) NOT LIKE '%[[]79]%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.splist_ARAccounts')) NOT LIKE '%[[]79]%'
   OR OBJECT_ID('dbo.sp_AddPaymentClient_OLD_10142026190000') IS NULL
   OR OBJECT_ID('dbo.sp_ReversePaymentClient_OLD_10142026190000') IS NULL
   OR OBJECT_ID('dbo.splist_ARAccounts_OLD_10142026190000') IS NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[79] post-check failed; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
GO

SET NOEXEC OFF;
GO
SELECT name, CONVERT(VARCHAR(16), modify_date, 120) AS Modified FROM sys.objects
WHERE name IN ('sp_AddPaymentClient', 'sp_ReversePaymentClient', 'splist_ARAccounts')
   OR name LIKE '%[_]OLD[_]10142026190000' ORDER BY name;
GO
