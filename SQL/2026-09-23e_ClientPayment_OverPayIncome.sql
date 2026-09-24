-- 2026-09-23: ClientPaymentsDevExAcctg.cs -- second overpayment flavor.
--
-- CONTEXT: the existing OverPay column always credits 20115 (Customer
-- Advances/Overpayments -- a liability the customer can later draw down via
-- OffsetAmount, see SQL/2026-09-23_CustomerOverpaymentCredit.sql). That
-- covers "overpay now, apply to a future invoice" but not "overpay now,
-- this excess is never coming back -- recognize it as revenue immediately."
--
-- DECISION (confirmed with user): new column OverPayIncome, credits 404
-- (OTHER INCOME -- already exists in COA, was OverPay's account before the
-- 09-23 retarget), mutually exclusive with OverPay (and, structurally,
-- with Offset too -- see the guard comment in sp_AddPaymentClient below).
--
-- Shape mirrors OverPay exactly at every layer:
--   - splist_ARAccounts: new zero-initialized placeholder column, same as
--     OverPay's own placeholder.
--   - ARPaymentDetails.PaymentType = 'OVERPAYINCOME' (own tag, distinct
--     from 'OVERPAY' -- sp_GetCustomerAvailableCredit only sums 'OVERPAY'/
--     'OFFSET', so OverPayIncome is automatically excluded from Available
--     Credit with no change needed there).
--   - JournalEntryMapping: 4 new mnemonics mirroring the OR-OVERPAY family
--     (OR-OVERPAY, OR-EWT-OVERPAY, OR-DISC-OVERPAY, OR-EWT-DISC-OVERPAY),
--     crediting 404 instead of 20115.
--   - sp_AddPaymentClient: new @OverPayIncome variable/mnemonic branches/
--     amount-type mappings, structurally mutually exclusive with
--     Offset/Overpay (see guard comment).
--   - sp_GetClientPaymentDetails: OverPayIncome added to the per-invoice
--     "Lines" result set (View Details / Edit-and-repost prefill), folded
--     into SuggestedAmountPaid the same additive way OverPay already is.
--
-- Deliberately NOT touched: TransactionChargeSales.AdvancePayment (only
-- OVERPAY increments it -- AdvancePayment represents a refundable/
-- offsettable balance, and OverPayIncome is neither).
--
-- REVISION (same day, sp-reviewer finding): OR-EWT-DISC-OVERPAYINCOME's
-- Seq4 AR-Trade leg was originally mirrored from the pre-existing
-- OR-EWT-DISC-OVERPAY row using AmountType 'GROSS-OVERPAY'/
-- 'GROSS-OVERPAYINCOME' (= Gross - Overpay/OverPayIncome). That does NOT
-- balance: Debit side = NET_OVERPAY(INCOME) + EWT + Discount = Gross +
-- Overpay(Income) + Services, but Credit side = (Gross-Overpay(Income)) +
-- Overpay(Income) + Services = Gross + Services -- off by exactly the
-- Overpay(Income) amount. Reproduced live on CORECSERP_002_DEV with a
-- rolled-back test (EWT=100, Discount=50, Overpay=200 on a 4500 invoice):
-- THROW 91002 'Debit = 4700.00, Credit = 4500.00'. This is a PRE-EXISTING
-- bug in OR-EWT-DISC-OVERPAY (predates today, never previously exercised
-- since nobody had combined EWT+Discount+Overpay before) -- fails safe
-- (rolls back, no bad posting) but blocks a legitimate combination. Fixed
-- both the new OR-EWT-DISC-OVERPAYINCOME (INSERT below corrected to plain
-- 'GROSS') and the pre-existing OR-EWT-DISC-OVERPAY (UPDATE in section 1b)
-- to use plain 'GROSS' like every other mnemonic's AR-Trade leg. Re-tested
-- both combinations after the fix -- both now balance and post correctly.
--
-- Deploy to CORECSERP_002_DEV first; mirror to CORECSJFC2026_STAGING only
-- after confirming with the user, per project convention.

-- ----------------------------------------------------------------
-- 1. JournalEntryMapping -- 4 new mnemonics, mirroring OR-OVERPAY family
-- ----------------------------------------------------------------
INSERT INTO dbo.JournalEntryMapping
    (Origin, Mnemonic, Description, Seq, DebitCredit, AccountCode, AccountDescription, IsConditional, IsAmountFromSource, IsActive, AmountType, ConditionFlag)
VALUES
    -- OR-OVERPAYINCOME (mirrors OR-OVERPAY, credits 404 instead of 20115)
    ('OR', 'OR-OVERPAYINCOME', 'Collection with Overpayment declared as Other Income only', 1, 'D', '{BANK}',    'Cash in Bank',                  0, 1, 1, 'NET_OVERPAYINCOME', NULL),
    ('OR', 'OR-OVERPAYINCOME', 'Collection with Overpayment declared as Other Income only', 2, 'C', '101030101', 'ACCOUNTS RECEIVABLE - TRADE',    0, 1, 1, 'GROSS', NULL),
    ('OR', 'OR-OVERPAYINCOME', 'Collection with Overpayment declared as Other Income only', 3, 'C', '404',       'OTHER INCOME',                  1, 1, 1, 'OVERPAYINCOME', 'HasOverpayIncome'),
    ('OR', 'OR-OVERPAYINCOME', 'Collection with Overpayment declared as Other Income only', 4, 'C', '101030103', 'ACCOUNTS RECEIVABLE - OTHERS',   1, 1, 1, 'SERVICES', 'HasServices'),

    -- OR-EWT-OVERPAYINCOME
    ('OR', 'OR-EWT-OVERPAYINCOME', 'Collection with EWT and Overpayment declared as Other Income', 1, 'D', '{BANK}',    'Cash in Bank',                       0, 1, 1, 'NET_OVERPAYINCOME', NULL),
    ('OR', 'OR-EWT-OVERPAYINCOME', 'Collection with EWT and Overpayment declared as Other Income', 2, 'D', '1010504',   'PREPAID CORPORATE INCOME TAX (CWTAX)', 1, 1, 1, 'EWT', 'HasEWT'),
    ('OR', 'OR-EWT-OVERPAYINCOME', 'Collection with EWT and Overpayment declared as Other Income', 3, 'C', '101030101', 'ACCOUNTS RECEIVABLE - TRADE',         0, 1, 1, 'GROSS', NULL),
    ('OR', 'OR-EWT-OVERPAYINCOME', 'Collection with EWT and Overpayment declared as Other Income', 4, 'C', '404',       'OTHER INCOME',                       1, 1, 1, 'OVERPAYINCOME', 'HasOverpayIncome'),
    ('OR', 'OR-EWT-OVERPAYINCOME', 'Collection with EWT and Overpayment declared as Other Income', 5, 'C', '101030103', 'ACCOUNTS RECEIVABLE - OTHERS',        1, 1, 1, 'SERVICES', 'HasServices'),

    -- OR-DISC-OVERPAYINCOME
    ('OR', 'OR-DISC-OVERPAYINCOME', 'Collection with Discount and Overpayment declared as Other Income', 1, 'D', '{BANK}',    'Cash in Bank',                 0, 1, 1, 'NET_OVERPAYINCOME', NULL),
    ('OR', 'OR-DISC-OVERPAYINCOME', 'Collection with Discount and Overpayment declared as Other Income', 2, 'D', '40103',     'SALES DISCOUNT',               1, 1, 1, 'MIRROR', 'HasDiscount'),
    ('OR', 'OR-DISC-OVERPAYINCOME', 'Collection with Discount and Overpayment declared as Other Income', 3, 'C', '101030101', 'ACCOUNTS RECEIVABLE - TRADE',   0, 1, 1, 'GROSS', NULL),
    ('OR', 'OR-DISC-OVERPAYINCOME', 'Collection with Discount and Overpayment declared as Other Income', 4, 'C', '404',       'OTHER INCOME',                 1, 1, 1, 'OVERPAYINCOME', 'HasOverpayIncome'),
    ('OR', 'OR-DISC-OVERPAYINCOME', 'Collection with Discount and Overpayment declared as Other Income', 5, 'C', '101030103', 'ACCOUNTS RECEIVABLE - OTHERS', 1, 1, 1, 'SERVICES', 'HasServices'),

    -- OR-EWT-DISC-OVERPAYINCOME
    ('OR', 'OR-EWT-DISC-OVERPAYINCOME', 'Collection with EWT, Discount and Overpayment declared as Other Income', 1, 'D', '{BANK}',    'Cash in Bank',                       0, 1, 1, 'NET_OVERPAYINCOME', NULL),
    ('OR', 'OR-EWT-DISC-OVERPAYINCOME', 'Collection with EWT, Discount and Overpayment declared as Other Income', 2, 'D', '1010504',   'PREPAID CORPORATE INCOME TAX (CWTAX)', 1, 1, 1, 'EWT', 'HasEWT'),
    ('OR', 'OR-EWT-DISC-OVERPAYINCOME', 'Collection with EWT, Discount and Overpayment declared as Other Income', 3, 'D', '40103',     'SALES DISCOUNT',                     1, 1, 1, 'MIRROR', 'HasDiscount'),
    ('OR', 'OR-EWT-DISC-OVERPAYINCOME', 'Collection with EWT, Discount and Overpayment declared as Other Income', 4, 'C', '101030101', 'ACCOUNTS RECEIVABLE - TRADE',         0, 1, 1, 'GROSS', NULL),
    ('OR', 'OR-EWT-DISC-OVERPAYINCOME', 'Collection with EWT, Discount and Overpayment declared as Other Income', 5, 'C', '404',       'OTHER INCOME',                       1, 1, 1, 'OVERPAYINCOME', 'HasOverpayIncome'),
    ('OR', 'OR-EWT-DISC-OVERPAYINCOME', 'Collection with EWT, Discount and Overpayment declared as Other Income', 6, 'C', '101030103', 'ACCOUNTS RECEIVABLE - OTHERS',        1, 1, 1, 'SERVICES', 'HasServices');
GO

-- ----------------------------------------------------------------
-- 1b. Fix pre-existing OR-EWT-DISC-OVERPAY balance bug (see revision note
--     above). Idempotent-safe: WHERE clause only matches the broken shape,
--     so a second run correctly matches 0 rows.
-- ----------------------------------------------------------------
UPDATE dbo.JournalEntryMapping
SET AmountType = 'GROSS'
WHERE Origin = 'OR' AND Mnemonic = 'OR-EWT-DISC-OVERPAY' AND Seq = 4
  AND DebitCredit = 'C' AND AccountCode = '101030101' AND AmountType = 'GROSS-OVERPAY';

IF NOT EXISTS (
    SELECT 1 FROM dbo.JournalEntryMapping
    WHERE Origin = 'OR' AND Mnemonic = 'OR-EWT-DISC-OVERPAY' AND Seq = 4
      AND DebitCredit = 'C' AND AccountCode = '101030101' AND AmountType = 'GROSS'
)
    THROW 50000, 'OR-EWT-DISC-OVERPAY Seq=4 AR-Trade leg is not GROSS after this script -- investigate before proceeding.', 1;
GO

-- ----------------------------------------------------------------
-- 1c. ClientLedger.TransCode was VARCHAR(20) -- too narrow for the new
--     mnemonic names ('OR-EWT-DISC-OVERPAYINCOME' = 25 chars,
--     'OR-DISC-OVERPAYINCOME' = 21 chars both exceed it). sp_AddPaymentClient
--     writes @Mnemonic straight into this column (Step 11/ClientLedger
--     insert) with no length guard, so this silently truncated rather than
--     erroring -- caught live via a genuine SQL truncation error on the
--     EWT+Discount+OverPayIncome retest, not by inspection. Widened to
--     VARCHAR(50) to match TicketMaster.Mnemonic's own width, which already
--     holds the same @Mnemonic values with headroom for any future
--     combination. Pure additive width change -- no data loss, no existing
--     value affected.
-- ----------------------------------------------------------------
ALTER TABLE dbo.ClientLedger ALTER COLUMN TransCode VARCHAR(50) NULL;
GO

-- ----------------------------------------------------------------
-- 2. splist_ARAccounts -- new OverPayIncome placeholder column
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.splist_ARAccounts', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.splist_ARAccounts', 'splist_ARAccounts_OLD_09232026080000';
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

END
GO

-- ----------------------------------------------------------------
-- 3. sp_GetClientPaymentDetails -- OverPayIncome in the Lines result set
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_GetClientPaymentDetails', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetClientPaymentDetails', 'sp_GetClientPaymentDetails_OLD_09232026080000';
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
    -- OverPayIncome/ServicesAmount are the raw components; SuggestedAmountPaid
    -- reconstructs the net cash figure using the same formula
    -- InsertARPaymentDetails/RecalculateRow used to derive it in the first
    -- place (paid = gross - ewt - disc - offset + overpay + overpayincome +
    -- services), so pre-fill shows what was actually entered before.
    SELECT
        InvoiceNo,
        PONumber AS OrderNo,
        MAX(InvoiceDate) AS TransactionDate,
        SUM(CASE WHEN PaymentType = 'INVOICE PAYMENT' THEN Amount ELSE 0 END) AS GrossAmount,
        SUM(CASE WHEN PaymentType = 'EWT'              THEN Amount ELSE 0 END) AS EWTAmount,
        SUM(CASE WHEN PaymentType = 'DISCOUNT'          THEN Amount ELSE 0 END) AS DiscountAmount,
        SUM(CASE WHEN PaymentType = 'OFFSET'            THEN Amount ELSE 0 END) AS OffsetAmount,
        SUM(CASE WHEN PaymentType = 'OVERPAY'           THEN Amount ELSE 0 END) AS OverPay,
        SUM(CASE WHEN PaymentType = 'OVERPAYINCOME'     THEN Amount ELSE 0 END) AS OverPayIncome,
        SUM(CASE WHEN PaymentType = 'SERVICES'          THEN Amount ELSE 0 END) AS ServicesAmount,
        SUM(CASE WHEN PaymentType = 'INVOICE PAYMENT' THEN Amount ELSE 0 END)
          - SUM(CASE WHEN PaymentType = 'EWT'      THEN Amount ELSE 0 END)
          - SUM(CASE WHEN PaymentType = 'DISCOUNT' THEN Amount ELSE 0 END)
          - SUM(CASE WHEN PaymentType = 'OFFSET'   THEN Amount ELSE 0 END)
          + SUM(CASE WHEN PaymentType = 'OVERPAY'  THEN Amount ELSE 0 END)
          + SUM(CASE WHEN PaymentType = 'OVERPAYINCOME' THEN Amount ELSE 0 END)
          + SUM(CASE WHEN PaymentType = 'SERVICES' THEN Amount ELSE 0 END) AS SuggestedAmountPaid
    FROM dbo.ARPaymentDetails
    WHERE PaymentHeaderID = @PaymentHeaderID
    GROUP BY InvoiceNo, PONumber
    ORDER BY InvoiceNo;
END
GO

-- ----------------------------------------------------------------
-- 4. sp_AddPaymentClient -- OverPayIncome leg, mutually exclusive with
--    Offset/Overpay
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_AddPaymentClient', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_AddPaymentClient', 'sp_AddPaymentClient_OLD_09232026090000';
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



    IF @Gross = 0
    BEGIN
        ROLLBACK;
        THROW 92001, 'No INVOICE PAYMENT rows found for this PaymentHeaderID.', 1;
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
      -- NOTE (2026-09-23): deliberately PaymentType='OVERPAY' only, not
      -- 'OVERPAYINCOME' -- AdvancePayment represents a refundable/
      -- offsettable balance the customer can still draw down; OverPayIncome
      -- is recognized straight to revenue and is neither refundable nor
      -- offsettable, so it must not inflate this column.
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
