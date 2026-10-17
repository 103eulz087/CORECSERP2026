/* ================================================================
   [104] 2026-10-17c  Client Payments: Other Collections (second tab next to Invoices)
   ================================================================
   User (2026-10-17): "put that inside the tab like we have NewTab for INVOICES and REVENUE ... the Revenue Tab is just
   like free mapping gl entry like cash advance in the supplier": clients with long-term debts and no invoice pay in
   parts, and the payment must reach Cash Receipts and the ledger with its control no. / CR no. Example SLERS
   (00001802): their balance-forward credits (C-000900 -1,146,104.62 and 7 smaller, -1,167,002.54 in all) were really
   interest; Peachtree closes them by ticking the credit and putting the same amount to other income.
   User decisions (2026-10-17): the tab is "Other Collections" (not "Revenue"); interest goes to OTHER INCOME (404);
   booked in the payment's own month (current income, no prior-period adjustment); everyone with access to Client
   Payments may use it; SLERS' C-049060 120,000 / C-049734 50,000 are interest billed through Sales (left as they are).
   Approved-account list not specified: seeded 404 OTHER INCOME, 403 INTEREST INCOME, 101030103 AR - OTHERS, kept in
   JournalEntryMapping (Origin 'OR', Mnemonic 'OR-OTHERCOLL'); IsActive = 0 removes one, a new row adds one.

   RULES
   - An Other Collections line = an ARPaymentDetails row of PaymentType 'OTHER COLLECTION', PONumber '#OTHER',
     CreditGLCode = the account, InvoiceNo = the line's remarks, Amount > 0 (92020), on an allowed account (92021),
     never linked to an invoice (92022). The same PaymentHeader / control no. / CR no. / ticket / DIT as the invoices.
   - Cash received = invoices settled - EWT - discount - offset + overpay + services + Other Collections (the NET legs
     of the OR mapping all include it); one credit leg per Other Collections account; the DIT is that cash.
   - Other Collections settle no invoice and write no client-ledger row (the customer's ledger stays = open invoices).
   - Balance-forward credits ticked may exceed the invoices only when Other Collections lines cover the rest
     (92014: invoices + credits + Other Collections < 0); then no EWT / discount / offset / overpay / services (92023).
     The AR leg that comes out negative is booked as a debit: SLERS credit 1,146,104.62 + Other Income line =
     DR 101030101 / CR 404 1,146,104.62, no cash, no DIT; the credit row closes and the ledger gets its debit ([79]).
   - A payment header posts once: refused 92025 when it is reversed or its own OR ticket (Mnemonic OR-% + ReferenceKey)
     or its ledger rows (customer + TransCode OR-%) already exist (an Other Collections-only payment has no invoice
     check that would stop a second run). One bank account per payment: 92026 when the invoice / Other Collections
     lines name different banks. Measured: 0 payments with two banks, 0 references with two live OR tickets, any tier.
   - Other Collections lines never touch an invoice row (the #BF grouping and the step 7 / 8 recalculations skip them).
   - Post-check 92024 (payments with Other Collections): the staged Other Collections legs = the lines, and the GL
     ticket = the staged legs account by account.
   - sp_GetClientPaymentDetails' header never returns an Other Collections account as the payment's CreditGLCode.
   - sp_GetClientPaymentDetails: set 3 (invoice lines) leaves the Other Collections lines out; new set 4 lists them
     (account, title, amount, remarks, bank). funcview_CustomerCashReceipts counts them as cash.
   - Reversal (sp_ReversePaymentClient) unchanged: it mirrors the payment's whole ticket, flags every line, gives the
     credits back and voids the DIT ([101] / [103] guards apply).

   Measured first (2026-10-17, read-only): the three objects hash-identical on DEV / STAGING / PRODUCTION
   (sp_AddPaymentClient F0EB95BB… = the [88] text; sp_GetClientPaymentDetails 7BE031A7…; funcview_CustomerCashReceipts
   73FC8EF1…); 0 'OTHER COLLECTION' lines and 0 '#OTHER' PO numbers anywhere; no TransactionChargeSales row with
   ReferenceNo '#OTHER' or ''; no OR-OTHERCOLL mapping rows; COA 404 / 403 / 101030103 present on every tier.
   Error codes 92020-92024 unused on every tier.
   Guard: the three live hashes. Needs: [88] (the guarded text). Full recreate of each (rename to
   _OLD_10172026200000 + CREATE with the full new text, generated from the live text by exact-once replacements).
   Exe: the old exe works unchanged on it (no Other Collections lines are sent; set 4 is ignored). **The new exe needs
   [104]** for the Other Collections tab (it reads the allowed accounts and sends the new lines); without it the tab
   says so and stays empty. Web v2: write Other Collections lines exactly as above (PONumber '#OTHER').
   Run in ONE connection with no open transaction.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET LOCK_TIMEOUT 10000;
GO

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[104] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.sp_AddPaymentClient', 'P') IS NULL OR OBJECT_ID('dbo.sp_GetClientPaymentDetails', 'P') IS NULL
     OR OBJECT_ID('dbo.funcview_CustomerCashReceipts') IS NULL
BEGIN
    RAISERROR('[104] stopped: sp_AddPaymentClient, sp_GetClientPaymentDetails or funcview_CustomerCashReceipts does not exist here; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentClient')) LIKE '%[[]104]%'
BEGIN
    RAISERROR('[104] already applied in this database; nothing changed.', 10, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.sp_AddPaymentClient_OLD_10172026200000') IS NOT NULL
     OR OBJECT_ID('dbo.sp_GetClientPaymentDetails_OLD_10172026200000') IS NOT NULL
     OR OBJECT_ID('dbo.funcview_CustomerCashReceipts_OLD_10172026200000') IS NOT NULL
BEGIN
    RAISERROR('[104] stopped: a backup _OLD_10172026200000 already exists; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentClient')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> 'F0EB95BB90156FE385D25773693FA71229EAA8C760EDF21634D01F6440AB6E8B'
BEGIN
    RAISERROR('[104] stopped: sp_AddPaymentClient is not the text this script was written against (the [88] text); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetClientPaymentDetails')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '7BE031A7C348C6CE91C95C60AEEFD87A75EEE7A8738D0C85A1E8A34B665192F2'
BEGIN
    RAISERROR('[104] stopped: sp_GetClientPaymentDetails is not the text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.funcview_CustomerCashReceipts')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '73FC8EF1920A13D234EC9C8318BB5FA4DFF18C4F02842359D30F20D06ABF78ED'
BEGIN
    RAISERROR('[104] stopped: funcview_CustomerCashReceipts is not the text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF EXISTS (SELECT 1 FROM dbo.ARPaymentDetails WHERE PaymentType = 'OTHER COLLECTION' OR PONumber = '#OTHER')
BEGIN
    RAISERROR('[104] stopped: Other Collections lines already exist here (written outside this script); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[104] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
GO

------------------------------------------------------------------
-- 1. The allowed accounts (JournalEntryMapping Origin 'OR', Mnemonic 'OR-OTHERCOLL')
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
IF NOT EXISTS (SELECT 1 FROM dbo.JournalEntryMapping WHERE Origin = 'OR' AND Mnemonic = 'OR-OTHERCOLL')
    INSERT INTO dbo.JournalEntryMapping
        (Origin, Mnemonic, Description, Seq, DebitCredit, AccountCode, AccountDescription,
         IsConditional, IsAmountFromSource, IsActive, Notes, AmountType, ConditionFlag, BranchCode)
    SELECT 'OR', 'OR-OTHERCOLL', 'Client Payments - Other Collections: allowed credit account', v.Seq, 'C', v.AccountCode, c.Description,
           0, 1, 1, '[104] 2026-10-17: an account staff may pick on the Other Collections tab; IsActive = 0 removes it from the list',
           'OTHER', NULL, NULL
    FROM (VALUES (CAST(1 AS TINYINT), '404'), (CAST(2 AS TINYINT), '403'), (CAST(3 AS TINYINT), '101030103')) AS v (Seq, AccountCode)
    INNER JOIN dbo.ChartOfAccounts AS c ON c.AccountCode = v.AccountCode;
GO

------------------------------------------------------------------
-- 2. sp_AddPaymentClient (full text: the [88] text + the [104] changes)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.sp_AddPaymentClient', 'sp_AddPaymentClient_OLD_10172026200000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
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
/*  [104] 2026-10-17: Other Collections (Client Payments' second tab). A line of PaymentType 'OTHER COLLECTION'
    (PONumber '#OTHER', CreditGLCode = the account, InvoiceNo = its remarks) is cash credited straight to a GL account
    the accountant allowed: JournalEntryMapping Origin 'OR' / Mnemonic 'OR-OTHERCOLL', active, in the COA (92021).
    It settles no invoice and writes no client-ledger row; it adds to the cash (NET) like Services. It may also cover
    balance-forward credits ticked beyond the invoices (SLERS: credit -1,146,104.62 + Other Income 1,146,104.62 = no
    cash; GL DR AR / CR 404): a leg that comes out negative is booked on the other side. Rules 92020-92024. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRAN;
    BEGIN TRY   -- [84] guards THROW only; the CATCH rolls back

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
        @Other    DECIMAL(18,2),   -- [104] Other Collections lines: cash credited straight to an allowed GL account

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
        THROW 92000, 'PaymentHeader not found.', 1;
    END

    SELECT @custname = CustomerName
    FROM Customers
    WHERE CustomerKey = @custkey;

    SELECT TOP 1 @BankGLCode = DebitGLCode
    FROM dbo.ARPaymentDetails
    WHERE PaymentHeaderID = @PaymentHeaderID
      AND PaymentType IN ('INVOICE PAYMENT', 'OTHER COLLECTION')   -- [104] a payment of Other Collections only has no invoice line
    ORDER BY CASE WHEN PaymentType = 'INVOICE PAYMENT' THEN 0 ELSE 1 END;

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
        @Services = ISNULL(SUM(CASE WHEN PaymentType = 'SERVICES'        THEN Amount ELSE 0 END), 0),
        @Other    = ISNULL(SUM(CASE WHEN PaymentType = 'OTHER COLLECTION' THEN Amount ELSE 0 END), 0)   -- [104]
    FROM ARPaymentDetails
    WHERE PaymentHeaderID = @PaymentHeaderID;



    -- [79] balance-forward credits ticked in this payment (negative INVOICE PAYMENT lines), as a positive total
    DECLARE @BFCredit DECIMAL(18,2) =
        ISNULL((SELECT -SUM(Amount) FROM ARPaymentDetails
                WHERE PaymentHeaderID = @PaymentHeaderID AND PaymentType = 'INVOICE PAYMENT' AND Amount < 0), 0);

    IF @Gross = 0 AND @BFCredit = 0 AND @Other = 0   -- [79] invoices fully covered by credits net to 0 are allowed; [104] so are Other Collections alone
    BEGIN
        THROW 92001, 'No INVOICE PAYMENT rows found for this PaymentHeaderID.', 1;
    END

    -- [104] Other Collections lines: a positive amount, no invoice link, on an account the accountant allowed
    IF EXISTS (SELECT 1 FROM ARPaymentDetails WHERE PaymentHeaderID = @PaymentHeaderID AND PaymentType = 'OTHER COLLECTION'
               AND (Amount IS NULL OR Amount <= 0))
        THROW 92020, 'An Other Collections line has no amount (or a negative one). Enter the amount received, or remove the line. Nothing was posted.', 1;
    IF EXISTS (SELECT 1 FROM ARPaymentDetails WHERE PaymentHeaderID = @PaymentHeaderID AND PaymentType = 'OTHER COLLECTION'
               AND ISNULL(PONumber, '') <> '#OTHER')
        THROW 92022, 'An Other Collections line is linked to an invoice (PO no.); Other Collections settle no invoice. Nothing was posted.', 1;
    DECLARE @ocFound BIT = 0, @ocMsg NVARCHAR(400);
    SELECT TOP (1) @ocFound = 1,
           @ocMsg = N'Account ' + ISNULL(NULLIF(LTRIM(RTRIM(D.CreditGLCode)), ''), N'(blank)')
                  + N' is not on the list of accounts allowed for Other Collections. Pick an allowed account. Nothing was posted.'
    FROM ARPaymentDetails D
    WHERE D.PaymentHeaderID = @PaymentHeaderID AND D.PaymentType = 'OTHER COLLECTION'
      AND NOT EXISTS (SELECT 1 FROM JournalEntryMapping M
                      INNER JOIN ChartOfAccounts C ON C.AccountCode = M.AccountCode
                      WHERE M.Origin = 'OR' AND M.Mnemonic = 'OR-OTHERCOLL' AND M.IsActive = 1 AND M.AccountCode = D.CreditGLCode)
    ORDER BY D.CreditGLCode;
    IF @ocFound = 1 THROW 92021, @ocMsg, 1;

    IF @Gross + @Other < 0   -- [79]; [104] Other Collections lines may cover the credits too
    BEGIN
        THROW 92014, 'The balance-forward credits ticked are more than the invoices and Other Collections ticked. Use less of a credit (the amount to pay cannot go below 0).', 1;
    END

    -- [104] credits larger than the invoices: only Other Collections lines cover the rest. EWT / discount / offset /
    --       overpay / services belong on an invoice being paid, and their GL legs assume a positive Gross.
    IF @Gross < 0 AND (@EWT <> 0 OR @Discount <> 0 OR @Offset <> 0 OR @Overpay <> 0 OR @OverPayIncome <> 0 OR @Services <> 0)
        THROW 92023, 'The balance-forward credits ticked are more than the invoices ticked, and only Other Collections lines can cover the rest: remove EWT, discount, offset, overpay and services from this payment. Nothing was posted.', 1;

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
        THROW 92007, 'Could not acquire a lock for this customer''s payment (another payment for the same customer is in progress). Please try again.', 1;
    END

    -- [104] a payment header is posted once. An Other Collections-only payment has no invoice check that would stop a
    --       second run, so: refused when the header is reversed, or its own OR ticket (Mnemonic OR-% + ReferenceKey,
    --       Known Bug #12) or its ledger rows (customer + TransCode OR-%) already exist. 0 such cases on any tier.
    IF EXISTS (SELECT 1 FROM PaymentHeader WHERE PaymentHeaderID = @PaymentHeaderID AND ISNULL(Status, '') = 'REVERSED')
       OR EXISTS (SELECT 1 FROM TicketMaster WHERE ReferenceNumber = @refno AND ReferenceKey = @refno AND Mnemonic LIKE 'OR-%')
       OR EXISTS (SELECT 1 FROM ClientLedger WHERE ReferenceNumber = @refno AND AccountKey = @custkey AND TransCode LIKE 'OR-%')
        THROW 92025, 'This payment was already posted (or reversed): its GL entry or ledger rows exist. Nothing was posted again.', 1;

    -- [104] one payment = one bank account: every invoice and Other Collections line names the same bank (the screen
    --       sends one; a second client could send several, and the cash leg and the DIT would go to one of them)
    IF (SELECT COUNT(DISTINCT LTRIM(RTRIM(DebitGLCode))) FROM ARPaymentDetails
        WHERE PaymentHeaderID = @PaymentHeaderID AND PaymentType IN ('INVOICE PAYMENT', 'OTHER COLLECTION')
          AND NULLIF(LTRIM(RTRIM(DebitGLCode)), '') IS NOT NULL) > 1
        THROW 92026, 'The lines of this payment name different bank accounts; one payment is deposited to one bank account. Nothing was posted.', 1;

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
          AND D.PaymentType <> 'OTHER COLLECTION'   -- [104] settles no invoice
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
            SET @bfMsg = N'Invoice ' + @bfInv + N' is not an open balance-forward credit of this customer, so it cannot be applied as a credit.';
            THROW 92010, @bfMsg, 1;
        END

        -- 92011: on a credit row only the credit itself is applied (no payment, EWT, discount, offset, overpay, services)
        SELECT TOP 1 @bfInv = InvoiceNo FROM #BFRow
        WHERE Found = 1 AND TotalAmount < 0 AND OtherLines > 0
        ORDER BY InvoiceNo;
        IF @bfInv IS NOT NULL
        BEGIN
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
            THROW 92012, @bfMsg, 1;
        END
    END

    -- [87] H5: every invoice of this payment is read NOW, under lock, and compared with the settlement sent (Known Bug #10).
    --      The screen's Balance is never trusted: another payment may have settled the invoice since the grid loaded.
    --      The lines are added up per invoice first, then each invoice row is read once (UPDLOCK, held to COMMIT; the
    --      customer applock above serializes payments, so no range lock is needed for a row that is not there).
    IF OBJECT_ID('tempdb..#H5') IS NOT NULL DROP TABLE #H5;
    SELECT D.InvoiceNo, D.PONumber, D.Settled,
           CASE WHEN T.InvoiceNo IS NULL THEN 0 ELSE 1 END AS Found,
           ISNULL(T.TotalAmount, 0) AS TotalAmount, ISNULL(T.Balance, 0) AS Balance,
           ISNULL(T.AmountPaid, 0) + ISNULL(T.EWTAmount, 0) + ISNULL(T.DiscountAmount, 0) + ISNULL(T.OffsetAmount, 0) AS Components
    INTO #H5
    FROM (SELECT InvoiceNo, PONumber, SUM(CASE WHEN PaymentType = 'INVOICE PAYMENT' THEN Amount ELSE 0 END) AS Settled
          FROM ARPaymentDetails
          WHERE PaymentHeaderID = @PaymentHeaderID AND PaymentType IN ('INVOICE PAYMENT', 'EWT', 'DISCOUNT', 'OFFSET')
          GROUP BY InvoiceNo, PONumber) D
    LEFT JOIN TransactionChargeSales T WITH (UPDLOCK, ROWLOCK)
           ON T.InvoiceNo = D.InvoiceNo AND T.ReferenceNo = D.PONumber AND T.CustomerKey = @custkey;

    DECLARE @h5Msg NVARCHAR(400);
    SELECT TOP 1 @h5Msg = N'Invoice ' + InvoiceNo + N' is not an invoice of this customer (invoice no. + PO). Reload the customer and try again. Nothing was posted.'
    FROM #H5 WHERE Found = 0 ORDER BY InvoiceNo;
    IF @h5Msg IS NOT NULL THROW 92015, @h5Msg, 1;
    SELECT TOP 1 @h5Msg = N'Invoice ' + InvoiceNo + N': its balance does not follow its paid / EWT / discount / offset amounts (it was set by hand). Correct the invoice row first; the payment would have reset the balance. Nothing was posted.'
    FROM #H5 WHERE ABS(Balance - (TotalAmount - Components)) > 0.005 ORDER BY InvoiceNo;
    IF @h5Msg IS NOT NULL THROW 92016, @h5Msg, 1;
    SELECT TOP 1 @h5Msg = N'Invoice ' + InvoiceNo + N': ' + CONVERT(NVARCHAR(30), CAST(Settled AS MONEY), 1) + N' is being settled but only '
                        + CONVERT(NVARCHAR(30), CAST(Balance AS MONEY), 1) + N' is owed now (another payment may have been posted since the list was loaded). Reload the customer and try again. Nothing was posted.'
    FROM #H5 WHERE TotalAmount >= 0 AND ROUND(Settled - Balance, 2) > 0 ORDER BY InvoiceNo;
    IF @h5Msg IS NOT NULL THROW 92017, @h5Msg, 1;

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
            DECLARE @OffsetMsg VARCHAR(400) = 'Offset amount (' + CAST(@Offset AS VARCHAR(30))
                + ') exceeds this customer''s available overpayment credit (' + CAST(ISNULL(@PriorAvailableCredit,0) AS VARCHAR(30)) + ').';
            THROW 92006, @OffsetMsg, 1;
        END
    END

    -- Compute all net variants upfront -- Services adds to every variant
    -- since it is real additional cash the client pays, regardless of which
    -- other deduction/addition combination is in play.
    -- [104] + @Other: Other Collections lines are cash received too, like Services
    SET @Net        = @Gross - @EWT - @Discount + @Services + @Other;                  -- base (no offset/overpay)
    SET @NetOffset  = @Gross - @EWT - @Discount - @Offset + @Services + @Other;        -- client pays less
    SET @NetOverpay = @Gross - @EWT - @Discount + @Overpay + @Services + @Other;       -- client pays more
    SET @NetOverpayIncome = @Gross - @EWT - @Discount + @OverPayIncome + @Services + @Other; -- client pays more, excess is income

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

    IF @InvoiceNetExclServices < 0 AND @Gross >= 0   -- [104] credits beyond the invoices: checked above (92014 / 92023)
    BEGIN
        THROW 92005, 'EWT/Discount/Offset total exceeds the amount being settled - deductions cannot exceed Gross.', 1;
    END

    IF @BankCash <> 0 AND LTRIM(RTRIM(ISNULL(@BankGLCode, ''))) = ''
    BEGIN
        THROW 92004, 'Debit GL Code (Bank/Cash account) is required when a net amount is being paid.', 1;
    END

    -- Retained as defense-in-depth -- with the guard above in place this
    -- can no longer actually go negative (Services/Overpay/OverPayIncome
    -- are the only terms separating @BankCash from
    -- @InvoiceNetExclServices, and all are always >= 0), but keep it
    -- rather than trust that invariant silently.
    IF @BankCash < 0
    BEGIN
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
        THROW 92002, 'No active JournalEntryMapping found. Verify Mnemonic is seeded.', 1;
    END

    -- [104] Other Collections: one credit leg per account (the bank leg already includes them through NET). Then a leg
    --       that came out negative (credits ticked beyond the invoices: CR AR -x) is booked on the other side (DR AR x);
    --       the DR = CR check below is unchanged by the swap.
    INSERT INTO #Computed (Seq, DebitCredit, AccountCode, Amount)
    SELECT CAST(200 + ROW_NUMBER() OVER (ORDER BY D.CreditGLCode) AS TINYINT), 'C', D.CreditGLCode, SUM(D.Amount)
    FROM ARPaymentDetails D
    WHERE D.PaymentHeaderID = @PaymentHeaderID AND D.PaymentType = 'OTHER COLLECTION'
    GROUP BY D.CreditGLCode;

    UPDATE #Computed
    SET DebitCredit = CASE DebitCredit WHEN 'D' THEN 'C' ELSE 'D' END,
        Amount      = -Amount
    WHERE Amount < 0;

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
          AND D.PaymentType     <> 'OTHER COLLECTION'   -- [104] settles no invoice
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
          AND D.PaymentType     <> 'OTHER COLLECTION'   -- [104] settles no invoice
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

        -- [88] H7: a payment whose deposit would count in a LOCKED reconciliation month (its own, or a later locked one) is refused
        DECLARE @LockedP DATE = (SELECT MIN(PeriodEnd) FROM dbo.BankReconHeader WITH (HOLDLOCK)
                                 WHERE BranchCode = '888' AND AccountCode = @BankGLCode AND Status = 'LOCKED' AND PeriodEnd >= @PeriodEnd);
        IF @LockedP IS NOT NULL
        BEGIN
            DECLARE @LockedMsg NVARCHAR(400) = N'Bank reconciliation of account ' + ISNULL(@BankGLCode, N'') + N' is locked for the month ending ' + CONVERT(NVARCHAR(10), @LockedP, 120) + N'. A payment dated ' + CONVERT(NVARCHAR(10), @date, 120) + N' would change that reconciliation: use a date in an open month after it, or have the period unlocked. Nothing was posted.';
            THROW 93022, @LockedMsg, 1;
        END

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
            THROW 92000, 'BankReconHeader not found.', 1;
        END

    END

    -------------------------------------------------------
    -- [104] post-check (payments with Other Collections lines): the staged Other Collections legs add up to the lines,
    --       and the GL ticket equals the staged legs account by account (nothing dropped, nothing extra)
    IF @Other <> 0
       AND (@TicketNo IS NULL
            OR ISNULL((SELECT SUM(CASE WHEN DebitCredit = 'C' THEN Amount ELSE -Amount END) FROM #Computed WHERE Seq >= 200), 0) <> @Other
            OR EXISTS (SELECT 1
                       FROM (SELECT AccountCode, SUM(CASE WHEN DebitCredit = 'C' THEN Amount ELSE -Amount END) AS Net
                             FROM #Computed WHERE Amount <> 0 GROUP BY AccountCode) S
                       FULL JOIN (SELECT TD.AccountCode, SUM(TD.Credit - TD.Debit) AS Net
                                  FROM TicketDetails TD
                                  WHERE TD.TicketNumber = CAST(@TicketNo AS VARCHAR(50)) AND TD.ReferenceNumber = @refno
                                  GROUP BY TD.AccountCode) K ON K.AccountCode = S.AccountCode
                       WHERE ABS(ISNULL(S.Net, 0) - ISNULL(K.Net, 0)) > 0.005))
        THROW 92024, 'Post-check: the GL entry does not match the payment lines (Other Collections); nothing was posted.', 1;

    COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;   -- [84]
        THROW;
    END CATCH
END
GO

------------------------------------------------------------------
-- 3. sp_GetClientPaymentDetails (set 4 = Other Collections lines)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.sp_GetClientPaymentDetails', 'sp_GetClientPaymentDetails_OLD_10172026200000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
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
        -- [104] an Other Collections line's CreditGLCode is its own account, not the payment's: never returned here
        SELECT TOP 1 a.DebitGLCode, CASE WHEN a.PaymentType = 'OTHER COLLECTION' THEN NULL ELSE a.CreditGLCode END AS CreditGLCode
        FROM dbo.ARPaymentDetails a
        WHERE a.PaymentHeaderID = ph.PaymentHeaderID
        ORDER BY CASE WHEN a.PaymentType = 'INVOICE PAYMENT' THEN 0 WHEN a.PaymentType = 'OTHER COLLECTION' THEN 2 ELSE 1 END, a.InvoiceNo
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
      AND ISNULL(PONumber, '') <> '#OTHER'   -- [104] Other Collections lines: the 4th result set
    GROUP BY InvoiceNo, PONumber
    ORDER BY InvoiceNo;

    -- [104] 2026-10-17: Other Collections lines (an exe before [104] reads the first three result sets only)
    SELECT D.CreditGLCode AS AccountCode, ISNULL(coa.Description, '') AS AccountTitle, D.Amount,
           D.InvoiceNo AS Remarks, D.DebitGLCode
    FROM dbo.ARPaymentDetails D
    LEFT JOIN dbo.ChartOfAccounts coa ON coa.AccountCode = D.CreditGLCode
    WHERE D.PaymentHeaderID = @PaymentHeaderID AND D.PaymentType = 'OTHER COLLECTION'
    ORDER BY D.CreditGLCode, D.InvoiceNo;
END
GO

------------------------------------------------------------------
-- 4. funcview_CustomerCashReceipts (Other Collections = cash received)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.funcview_CustomerCashReceipts', 'funcview_CustomerCashReceipts_OLD_10172026200000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE FUNCTION [dbo].[funcview_CustomerCashReceipts]
(
    @datefrom       DATE,
    @dateto         DATE,
    @dateFilterType CHAR(1),        -- 'I' = ARPaymentDetails.InvoiceDate, 'P' = PaymentHeader.PaymentDate select * FROM ARPaymentDetails
    @parmbranchcode VARCHAR(10)     -- NEW 2026-09-25c: NULL / '' / 'ALL' = all branches
)
RETURNS TABLE
AS
RETURN
(
        WITH aa AS
        (
            SELECT
                apd.PaymentHeaderID,
                apd.CustomerKey,
                apd.DebitGLCode,
                apd.InvoiceNo,
                apd.InvoiceDate,
                -- CHANGED 2026-09-25c: OFFSET and EWT are deducted (non-cash).
                -- [104] 2026-10-17: Other Collections lines are cash received too (their InvoiceNo holds the line's remarks)
                SUM(CASE WHEN apd.PaymentType IN ('INVOICE PAYMENT', 'OVERPAY','OVERPAYINCOME','SERVICES','OTHER COLLECTION') THEN apd.Amount
                         WHEN apd.PaymentType IN ('OFFSET', 'EWT','DISCOUNT')              THEN -apd.Amount
                         ELSE 0 END) AS InvoicePaymentAmount,
                SUM(CASE WHEN apd.PaymentType = 'EWT' THEN apd.Amount ELSE 0 END) AS EwtAmount,
                SUM(CASE WHEN apd.PaymentType = 'DISCOUNT' THEN apd.Amount ELSE 0 END) AS DiscountAmount
            FROM ARPaymentDetails apd
            WHERE (apd.ErrorTag IS NULL OR apd.ErrorTag <> 1)
              AND (
                    (@dateFilterType = 'I'
                     AND apd.InvoiceDate >= @datefrom
                     AND apd.InvoiceDate < DATEADD(DAY, 1, @dateto))
                 OR (@dateFilterType = 'P'
                     AND EXISTS (
                            SELECT 1
                            FROM PaymentHeader ph
                            WHERE ph.PaymentHeaderID = apd.PaymentHeaderID
                              AND ph.PaymentDate >= @datefrom
                              AND ph.PaymentDate < DATEADD(DAY, 1, @dateto)
                         ))
                  )
            GROUP BY
                apd.PaymentHeaderID,
                apd.CustomerKey,
                apd.DebitGLCode,
                apd.InvoiceNo,
                apd.InvoiceDate
        )
        SELECT a.CustomerKey, b.InvoiceDate, c.CustomerName, a.ControlNo, d.Description AS Bank, a.PaymentDate, a.CRNo,
               a.TotalAmount,
               b.InvoicePaymentAmount,
               b.InvoiceNo,
               b.EwtAmount,
               b.DiscountAmount,
               a.PaymentType, c.AccountOfficer AS SalesPerson,
               c.BranchCode                               -- NEW 2026-09-25c
        FROM PaymentHeader a
        INNER JOIN aa b
            ON a.PaymentHeaderID = b.PaymentHeaderID
        INNER JOIN Customers c
            ON a.CustomerKey = c.CustomerKey
        INNER JOIN ChartOfAccounts d
            ON b.DebitGLCode = d.AccountCode
        WHERE (NULLIF(LTRIM(RTRIM(ISNULL(@parmbranchcode, ''))), '') IS NULL
               OR @parmbranchcode = 'ALL'
               OR c.BranchCode = @parmbranchcode)
);
GO

------------------------------------------------------------------
-- 5. Post-check, then commit
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentClient')), N'') NOT LIKE '%[[]104]%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentClient')), N'') NOT LIKE '%THROW 92026%'
    SET @msg = N'sp_AddPaymentClient is not the [104] text';
ELSE IF ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetClientPaymentDetails')), N'') NOT LIKE '%[[]104]%'
    SET @msg = N'sp_GetClientPaymentDetails is not the [104] text';
ELSE IF ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.funcview_CustomerCashReceipts')), N'') NOT LIKE '%[[]104]%'
    SET @msg = N'funcview_CustomerCashReceipts is not the [104] text';
ELSE IF OBJECT_ID('dbo.sp_AddPaymentClient_OLD_10172026200000', 'P') IS NULL
     OR OBJECT_ID('dbo.sp_GetClientPaymentDetails_OLD_10172026200000', 'P') IS NULL
     OR OBJECT_ID('dbo.funcview_CustomerCashReceipts_OLD_10172026200000') IS NULL
    SET @msg = N'a backup is missing';
ELSE IF (SELECT COUNT(*) FROM dbo.JournalEntryMapping WHERE Origin = 'OR' AND Mnemonic = 'OR-OTHERCOLL' AND IsActive = 1) < 1
    SET @msg = N'no allowed Other Collections account';

IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[104] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59897, @msg, 1;
END

COMMIT TRANSACTION;
PRINT '[104] committed: Other Collections lines in sp_AddPaymentClient, set 4 in sp_GetClientPaymentDetails, Cash Receipts; allowed accounts 404 / 403 / 101030103.';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
