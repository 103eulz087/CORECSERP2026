/* ================================================================
   [104] TEST SCRIPT - Client Payments: Other Collections
   ================================================================
   Run in SSMS on DEV or STAGING AFTER [104] is applied. Every test runs inside BEGIN TRAN ... ROLLBACK, so nothing is
   left behind; the last result sets show PASS / BUG SHOWN / SKIP / FAIL per test. Do NOT run on PRODUCTION.
   The procs print their own result sets (sp_GetClientPaymentDetails in OC2: 4 sets); read the "Seq Test Result" set.

   Fixtures picked automatically (first result set shows them):
     - INVOICE: an open AR invoice (UNPAID, nothing paid, a single row under its invoice no.) whose customer has a
       ClientAccounts row; newest first                                         (OC1a-c, OC2, OC3, OC6a, refusals)
     - PAIR:    a customer with an open balance-forward credit (TotalAmount < 0, nothing used, at least 2.00) and an
       open invoice at least as large as the credit, both single rows           (OC1d, R-92023)
     - CREDIT:  the largest open balance-forward credit (nothing used, single row, at least 2.00) of a customer with a
       ClientAccounts row (on a production copy: SLERS 00001802 / C-000900)      (OC4, OC5, OC6b, R-92014, BUG-OC4)
     - ACC2:    the first active Other Collections account other than 404 (403) (OC3, R-92021b)
   Optional @Pick... variables below force one record. Missing fixture -> that test shows SKIP.
   Bank account used: 101020101 (its 888 recon month of today must not be LOCKED). Test reference 99921 and the
   control no. TEST104 / CR no. TEST104-CR must be unused (checked first).

   Cases
     OC0   install: [104] markers, backups, mapping rows; OC0b the new refusals sit before the first write
     OC1a-d old = new footprint (invoice row, ticket, lines, client ledger, DIT, account) for ordinary payments:
           plain full, EWT + discount, overpay as income, balance-forward credit + invoice
     OC2   Other Collections only, cash: DR bank / CR 404, DIT = amount with the control no., no ledger row, no invoice
           touched, Cash Receipts = amount (old function: 0), details set 3 leaves it out, set 4 lists it
     OC3   invoice + Other Collections line (ACC2) in one payment: one ticket, bank = invoice + other, DIT = total
     OC4   SLERS-style: whole BF credit + Other Collections 404 for the same amount: DR 101030101 / CR 404, no DIT,
           credit FULLYPAID 0, ledger debit row, account up by the credit
     OC5   part of the credit + a smaller Other line: credit PARTIAL, still listed by splist_ARAccounts @IncludeCredits=1
     OC6a  OC2 reversed (sp_ReversePaymentClient): ticket mirrored, DIT voided, Cash Receipts empty, accounts net 0
     OC6b  OC4 reversed: ticket mirrored, credit back UNPAID, ledger net 0, account back
     OC7   whole BF credit + a LARGER Other line: cash left over = DR bank = DIT, DR AR = the credit, CR 404 = the line
     D1    details header of an Other-only payment: CreditGLCode NULL, DebitGLCode = the bank (OC3: the invoice's AR)
     R-*   refusals 92020 (0 / negative), 92021 (bank account; mapping row deactivated in the tx), 92022 (real PO),
           92014 (credit beyond invoices + other), 92023 (credit beyond the invoices + EWT),
           92025 (the same header posted a second time: Other-only and invoice payment), 92026 (two banks on the lines)
     BUG-* the pre-[104] proc refuses OC2 (92001) and OC4 (92014)
   Not covered: the 92024 post-check (unreachable through the proc's own legs).
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT OFF;   -- the tests catch the refusals themselves

DECLARE @PickInvoice VARCHAR(50) = NULL;   -- optional: invoice no. of the INVOICE fixture
DECLARE @PickCredit  VARCHAR(50) = NULL;   -- optional: invoice no. of the CREDIT fixture (a negative balance-forward row)

DECLARE @r TABLE (Seq INT IDENTITY, Test VARCHAR(120), Result VARCHAR(12), Detail VARCHAR(1000));
DECLARE @bank VARCHAR(20) = '101020101', @ar VARCHAR(20) = '101030101', @today DATE = CAST(GETDATE() AS DATE);
DECLARE @ref1 VARCHAR(20) = '99921', @ctl VARCHAR(30) = 'TEST104', @crno VARCHAR(20) = 'TEST104-CR';
DECLARE @err INT, @msg NVARCHAR(2048), @n INT, @tc INT, @rows INT, @sig0 VARCHAR(MAX), @sig VARCHAR(MAX), @def NVARCHAR(MAX), @defD NVARCHAR(MAX);
DECLARE @ph TABLE (ID INT);
DECLARE @phid INT, @k INT, @kmax INT, @cid VARCHAR(12), @cname VARCHAR(120), @kind VARCHAR(10), @exp INT, @mapoff VARCHAR(20), @ccust CHAR(8), @run VARCHAR(3);
DECLARE @hdrCnt0 INT, @hdrCnt1 INT, @twice BIT, @dDeb VARCHAR(20), @dCrd VARCHAR(20), @dCrdOld VARCHAR(20), @dDefOK BIT;
-- fixtures
DECLARE @cust CHAR(8), @inv VARCHAR(50), @po VARCHAR(10), @amt DECIMAL(18,2), @invDate DATE;
DECLARE @bcust CHAR(8), @binv VARCHAR(50), @bpo VARCHAR(10), @bamt DECIMAL(18,2), @bdate DATE, @cinv VARCHAR(50), @cpo VARCHAR(10), @cbal DECIMAL(18,2), @cdate DATE;
DECLARE @scust CHAR(8), @sinv VARCHAR(50), @spo VARCHAR(10), @sbal DECIMAL(18,2), @sdate DATE, @sname VARCHAR(150);
DECLARE @acc2 VARCHAR(20);
DECLARE @fx TABLE (c CHAR(8), i VARCHAR(50), p VARCHAR(10));
-- case definitions: one header + its lines (the rows the Client Payments screen writes)
DECLARE @hdr TABLE (Ord INT IDENTITY, CaseID VARCHAR(12), Name VARCHAR(120), Kind VARCHAR(10), Cust CHAR(8), PayType VARCHAR(30), Total DECIMAL(18,2), ExpectErr INT NULL, MapOff VARCHAR(20) NULL, Twice BIT NOT NULL DEFAULT 0);   -- Twice = post the same header twice
DECLARE @spec TABLE (CaseID VARCHAR(12), Ln INT, PO VARCHAR(10), Inv VARCHAR(50), InvDate DATE, Amt DECIMAL(18,2), PType VARCHAR(20), CrGL VARCHAR(20), DebGL VARCHAR(20) NULL);   -- DebGL NULL = the test bank
DECLARE @fp TABLE (CaseID VARCHAR(12), Run VARCHAR(3), Item VARCHAR(10), Val VARCHAR(MAX));
-- per-case readings
DECLARE @oamt DECIMAL(18,2) = 1234.56, @oamt3 DECIMAL(18,2) = 500.00, @u DECIMAL(18,2), @xtra DECIMAL(18,2);
DECLARE @a0 DECIMAL(18,2), @a1 DECIMAL(18,2), @t0 VARCHAR(400), @t1 VARCHAR(400), @sb0 DECIMAL(18,2), @sb1 DECIMAL(18,2);
DECLARE @nTM INT, @nTMrev INT, @mn VARCHAR(50), @nTD INT, @dr DECIMAL(18,2), @cr DECIMAL(18,2), @lines VARCHAR(2000);
DECLARE @vBank DECIMAL(18,2), @vAR DECIMAL(18,2), @v404 DECIMAL(18,2), @vAcc2 DECIMAL(18,2), @nz INT;
DECLARE @nD INT, @dAmt DECIMAL(18,2), @dCtl VARCHAR(30), @dRes INT, @dWhy VARCHAR(100), @dAcc VARCHAR(20);
DECLARE @nCL INT, @clD DECIMAL(18,2), @clC DECIMAL(18,2), @clDesc VARCHAR(300);
DECLARE @crN INT, @crAmt DECIMAL(18,2), @crOldN INT, @crOld DECIMAL(18,2);
DECLARE @s3 INT, @s3old INT, @s4 INT, @s4amt DECIMAL(18,2), @s4t VARCHAR(150), @defOK BIT, @detErr VARCHAR(400);
DECLARE @iPaid DECIMAL(18,2), @iBal DECIMAL(18,2), @iStat VARCHAR(20), @st VARCHAR(20);
DECLARE @sl TABLE (Pay BIT, TransactionDate DATE, DueDate DATE, OrderNo VARCHAR(10), InvoiceNo VARCHAR(100), InvoiceType VARCHAR(15), InvoiceAmount DECIMAL(12,2),
                   Balance DECIMAL(12,2), AmountPaid DECIMAL(12,2), EWTAmount DECIMAL(12,2), DiscountAmount DECIMAL(12,2), OffsetAmount DECIMAL(12,2),
                   OverPay DECIMAL(12,2), OverPayIncome DECIMAL(12,2), ServicesAmount DECIMAL(12,2), Remarks VARCHAR(100));
DECLARE @slN INT, @slBal DECIMAL(18,2), @slType VARCHAR(15);

------------------------------------------------------------------
-- OC0 install check
------------------------------------------------------------------
SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentClient'));
IF @def NOT LIKE '%[[]104]%' OR @def NOT LIKE '%THROW 92024%' OR @def NOT LIKE '%THROW 92025%' OR @def NOT LIKE '%THROW 92026%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentClient_OLD_10172026200000')) LIKE '%[[]104]%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetClientPaymentDetails')) NOT LIKE '%[[]104]%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.funcview_CustomerCashReceipts')) NOT LIKE '%[[]104]%'
   OR OBJECT_ID('dbo.sp_AddPaymentClient_OLD_10172026200000', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_GetClientPaymentDetails_OLD_10172026200000', 'P') IS NULL
   OR OBJECT_ID('dbo.funcview_CustomerCashReceipts_OLD_10172026200000') IS NULL
   OR NOT EXISTS (SELECT 1 FROM dbo.JournalEntryMapping WHERE Origin = 'OR' AND Mnemonic = 'OR-OTHERCOLL' AND AccountCode = '404' AND IsActive = 1)
BEGIN
    INSERT @r VALUES ('OC0 install check', 'FAIL', '[104] v2 is not installed (marker, THROW 92024 / 92025 / 92026, a pre-[104] backup _OLD_10172026200000 or the active 404 OR-OTHERCOLL mapping row is missing)');
    SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
    RETURN;
END
INSERT @r VALUES ('OC0 install check', 'PASS', CONCAT('[104] markers in the 3 objects, 3 backups present; active Other Collections accounts: ',
    (SELECT STRING_AGG(AccountCode, ', ') WITHIN GROUP (ORDER BY Seq) FROM dbo.JournalEntryMapping WHERE Origin = 'OR' AND Mnemonic = 'OR-OTHERCOLL' AND IsActive = 1)));
INSERT @r VALUES ('OC0b the new refusals sit before the proc''s first write (UPDATE T)',
    CASE WHEN CHARINDEX('THROW 92020', @def) > 0 AND CHARINDEX('THROW 92021', @def) > 0 AND CHARINDEX('THROW 92022', @def) > 0
              AND CHARINDEX('THROW 92023', @def) > 0 AND CHARINDEX('THROW 92014', @def) > 0
              AND CHARINDEX('THROW 92020', @def) < CHARINDEX('UPDATE T', @def) AND CHARINDEX('THROW 92021', @def) < CHARINDEX('UPDATE T', @def)
              AND CHARINDEX('THROW 92022', @def) < CHARINDEX('UPDATE T', @def) AND CHARINDEX('THROW 92023', @def) < CHARINDEX('UPDATE T', @def)
              AND CHARINDEX('THROW 92014', @def) < CHARINDEX('UPDATE T', @def)
              AND CHARINDEX('THROW 92025', @def) > 0 AND CHARINDEX('THROW 92026', @def) > 0
              AND CHARINDEX('THROW 92025', @def) < CHARINDEX('UPDATE T', @def) AND CHARINDEX('THROW 92026', @def) < CHARINDEX('UPDATE T', @def)
              AND CHARINDEX('THROW 92025', @def) < CHARINDEX('THROW 92017', @def) THEN 'PASS' ELSE 'FAIL' END,
    CONCAT('positions: 92020 ', CHARINDEX('THROW 92020', @def), ', 92022 ', CHARINDEX('THROW 92022', @def), ', 92021 ', CHARINDEX('THROW 92021', @def),
           ', 92014 ', CHARINDEX('THROW 92014', @def), ', 92023 ', CHARINDEX('THROW 92023', @def), ', 92025 ', CHARINDEX('THROW 92025', @def),
           ', 92026 ', CHARINDEX('THROW 92026', @def), ' (before 92017 at ', CHARINDEX('THROW 92017', @def), '), first write UPDATE T ', CHARINDEX('UPDATE T', @def)));

------------------------------------------------------------------
-- fixtures
------------------------------------------------------------------
SELECT TOP (1) @cust = T.CustomerKey, @inv = T.InvoiceNo, @po = T.ReferenceNo, @amt = T.TotalAmount, @invDate = T.TransactionDate
FROM dbo.TransactionChargeSales T
WHERE T.PayStatus = 'UNPAID' AND T.TotalAmount > 0 AND T.Balance = T.TotalAmount
  AND ISNULL(T.AmountPaid, 0) = 0 AND ISNULL(T.EWTAmount, 0) = 0 AND ISNULL(T.DiscountAmount, 0) = 0 AND ISNULL(T.OffsetAmount, 0) = 0
  AND (SELECT COUNT(*) FROM dbo.TransactionChargeSales x WHERE x.InvoiceNo = T.InvoiceNo) = 1
  AND EXISTS (SELECT 1 FROM dbo.ClientAccounts c WHERE c.AccountKey = T.CustomerKey)
  AND (@PickInvoice IS NULL OR T.InvoiceNo = @PickInvoice)
ORDER BY T.TransactionDate DESC, T.InvoiceNo;

SELECT TOP (1) @bcust = i.CustomerKey, @binv = i.InvoiceNo, @bpo = i.ReferenceNo, @bamt = i.TotalAmount, @bdate = i.TransactionDate,
       @cinv = c.InvoiceNo, @cpo = c.ReferenceNo, @cbal = -c.Balance, @cdate = c.TransactionDate
FROM dbo.TransactionChargeSales c
INNER JOIN dbo.TransactionChargeSales i ON i.CustomerKey = c.CustomerKey AND i.TotalAmount > 0 AND i.Balance = i.TotalAmount AND i.PayStatus = 'UNPAID'
       AND ISNULL(i.AmountPaid, 0) = 0 AND ISNULL(i.EWTAmount, 0) = 0 AND ISNULL(i.DiscountAmount, 0) = 0 AND ISNULL(i.OffsetAmount, 0) = 0
WHERE c.TotalAmount < 0 AND c.Balance = c.TotalAmount AND ISNULL(c.AmountPaid, 0) = 0 AND c.PayStatus = 'UNPAID'
  AND c.Balance <= -2 AND -c.Balance <= i.TotalAmount
  AND (SELECT COUNT(*) FROM dbo.TransactionChargeSales x WHERE x.InvoiceNo = i.InvoiceNo) = 1
  AND (SELECT COUNT(*) FROM dbo.TransactionChargeSales x WHERE x.InvoiceNo = c.InvoiceNo) = 1
  AND EXISTS (SELECT 1 FROM dbo.ClientAccounts a WHERE a.AccountKey = c.CustomerKey)
ORDER BY i.TransactionDate DESC, i.InvoiceNo, c.InvoiceNo;

SELECT TOP (1) @scust = c.CustomerKey, @sinv = c.InvoiceNo, @spo = c.ReferenceNo, @sbal = -c.Balance, @sdate = c.TransactionDate
FROM dbo.TransactionChargeSales c
WHERE c.TotalAmount < 0 AND c.Balance = c.TotalAmount AND c.PayStatus = 'UNPAID' AND c.Balance <= -2
  AND ISNULL(c.AmountPaid, 0) = 0 AND ISNULL(c.EWTAmount, 0) = 0 AND ISNULL(c.DiscountAmount, 0) = 0 AND ISNULL(c.OffsetAmount, 0) = 0
  AND (SELECT COUNT(*) FROM dbo.TransactionChargeSales x WHERE x.InvoiceNo = c.InvoiceNo) = 1
  AND EXISTS (SELECT 1 FROM dbo.ClientAccounts a WHERE a.AccountKey = c.CustomerKey)
  AND (@PickCredit IS NULL OR c.InvoiceNo = @PickCredit)
ORDER BY c.TotalAmount, c.InvoiceNo;
SELECT @sname = CustomerName FROM dbo.Customers WHERE CustomerKey = @scust;

SELECT TOP (1) @acc2 = M.AccountCode
FROM dbo.JournalEntryMapping M INNER JOIN dbo.ChartOfAccounts C ON C.AccountCode = M.AccountCode
WHERE M.Origin = 'OR' AND M.Mnemonic = 'OR-OTHERCOLL' AND M.IsActive = 1 AND M.AccountCode NOT IN ('404', @bank, @ar)
ORDER BY M.Seq;

IF EXISTS (SELECT 1 FROM dbo.PaymentHeader WHERE ReferenceNo = @ref1 OR ControlNo = @ctl OR CRNo = @crno)
   OR EXISTS (SELECT 1 FROM dbo.ARPaymentDetails WHERE ReferenceNo = @ref1)
   OR EXISTS (SELECT 1 FROM dbo.TicketMaster WHERE ReferenceNumber = @ref1)
   OR EXISTS (SELECT 1 FROM dbo.TicketDetails WHERE ReferenceNumber = @ref1)
   OR EXISTS (SELECT 1 FROM dbo.ClientLedger WHERE ReferenceNumber = @ref1)
   OR EXISTS (SELECT 1 FROM dbo.BankStatementRecon WHERE ReferenceNo = @ref1 OR SourceRef = @ref1)
   OR EXISTS (SELECT 1 FROM dbo.TransactionChargeSales WHERE ReferenceNo = @ref1)
BEGIN
    INSERT @r VALUES ('fixtures', 'ERROR', 'test reference 99921 (or control no. TEST104 / CR no. TEST104-CR) is in use here; change @ref1 / @ctl / @crno');
    SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
    RETURN;
END
IF EXISTS (SELECT 1 FROM dbo.GLPeriodLock WHERE LockedThroughDate >= @today)
BEGIN
    INSERT @r VALUES ('fixtures', 'ERROR', 'the GL is closed through today; the postings would be refused (59900)');
    SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
    RETURN;
END
IF EXISTS (SELECT 1 FROM dbo.BankReconHeader WHERE BranchCode = '888' AND AccountCode = @bank AND Status = 'LOCKED' AND PeriodEnd >= EOMONTH(@today))
BEGIN
    INSERT @r VALUES ('fixtures', 'ERROR', 'the bank reconciliation of 101020101 is locked for this month (or later); the deposits would be refused (93022)');
    SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
    RETURN;
END

SELECT 'fixtures' AS what, @cust AS inv_customer, @inv AS invoice, @po AS po, @amt AS amount,
       @bcust AS pair_customer, @binv AS pair_invoice, @bamt AS pair_amount, @cinv AS pair_credit, @cbal AS pair_credit_amt,
       @scust AS credit_customer, @sname AS credit_name, @sinv AS credit_invoice, @spo AS credit_po, @sbal AS credit_amt, @acc2 AS second_account;

IF @cust IS NULL AND @bcust IS NULL AND @scust IS NULL
BEGIN
    INSERT @r VALUES ('fixtures', 'SKIP', 'no open AR invoice and no open balance-forward credit here: nothing to test');
    GOTO Report;
END

INSERT @fx SELECT @cust, @inv, @po WHERE @cust IS NOT NULL;
INSERT @fx SELECT @bcust, @binv, @bpo WHERE @bcust IS NOT NULL;
INSERT @fx SELECT @bcust, @cinv, @cpo WHERE @bcust IS NOT NULL;
INSERT @fx SELECT @scust, @sinv, @spo WHERE @scust IS NOT NULL;

-- fixture signature: the fixture rows, their customers' accounts and the mapping rows (compared after every refusal and at the end)
SELECT @sig0 = CONCAT(
    (SELECT STRING_AGG(CONCAT(t.CustomerKey, ':', t.InvoiceNo, ':', t.AmountPaid, ':', t.Balance, ':', t.PayStatus, ':', ISNULL(t.EWTAmount, 0), ':', ISNULL(t.DiscountAmount, 0), ':', ISNULL(t.OffsetAmount, 0), ':', ISNULL(t.AdvancePayment, 0)), ',')
            WITHIN GROUP (ORDER BY t.CustomerKey, t.InvoiceNo)
     FROM dbo.TransactionChargeSales t WHERE EXISTS (SELECT 1 FROM @fx f WHERE f.c = t.CustomerKey AND f.i = t.InvoiceNo AND f.p = t.ReferenceNo)), '|',
    (SELECT STRING_AGG(CONCAT(a.AccountKey, ':', a.AccountBalance), ',') WITHIN GROUP (ORDER BY a.AccountKey) FROM dbo.ClientAccounts a WHERE a.AccountKey IN (SELECT c FROM @fx)), '|',
    (SELECT STRING_AGG(CONCAT(m.AccountCode, ':', CAST(m.IsActive AS INT)), ',') WITHIN GROUP (ORDER BY m.Seq) FROM dbo.JournalEntryMapping m WHERE m.Origin = 'OR' AND m.Mnemonic = 'OR-OTHERCOLL'));
SELECT @hdrCnt0 = COUNT(*) FROM dbo.BankReconHeader WHERE BranchCode = '888' AND AccountCode = @bank AND PeriodEnd = EOMONTH(@today);

------------------------------------------------------------------
-- case definitions
------------------------------------------------------------------
IF @cust IS NOT NULL
BEGIN
    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total) VALUES ('OC1a', 'OC1a plain full payment old = new', 'SAME', @cust, 'CASH', @amt);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('OC1a', 1, @po, @inv, @invDate, @amt, 'INVOICE PAYMENT', @ar);

    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total) VALUES ('OC1b', 'OC1b EWT + discount old = new', 'SAME', @cust, 'CASH', @amt - ROUND(@amt * 0.01, 2) - 10);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('OC1b', 1, @po, @inv, @invDate, @amt, 'INVOICE PAYMENT', @ar), ('OC1b', 2, @po, @inv, @invDate, ROUND(@amt * 0.01, 2), 'EWT', @ar),
                        ('OC1b', 3, @po, @inv, @invDate, 10, 'DISCOUNT', @ar);

    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total) VALUES ('OC1c', 'OC1c overpay as income old = new', 'SAME', @cust, 'CASH', @amt + 100);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('OC1c', 1, @po, @inv, @invDate, @amt, 'INVOICE PAYMENT', @ar), ('OC1c', 2, @po, @inv, @invDate, 100, 'OVERPAYINCOME', @ar);

    -- OC2 / OC6a: Other Collections only, cash
    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total) VALUES ('OC2', 'OC2', 'OWN', @cust, 'CASH', @oamt);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('OC2', 1, '#OTHER', 'TEST104 INTEREST', @today, @oamt, 'OTHER COLLECTION', '404');

    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total, ExpectErr) VALUES ('BUG-OC2', 'BUG-OC2 old proc refuses an Other Collections-only payment (92001)', 'BUGOLD', @cust, 'CASH', @oamt, 92001);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('BUG-OC2', 1, '#OTHER', 'TEST104 INTEREST', @today, @oamt, 'OTHER COLLECTION', '404');

    -- refusals
    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total, ExpectErr) VALUES ('R-92020a', 'R-92020a Other Collections line of 0.00 (with an invoice) refused 92020', 'REFUSE', @cust, 'CASH', @amt, 92020);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('R-92020a', 1, @po, @inv, @invDate, @amt, 'INVOICE PAYMENT', @ar), ('R-92020a', 2, '#OTHER', 'TEST104', @today, 0, 'OTHER COLLECTION', '404');
    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total, ExpectErr) VALUES ('R-92020b', 'R-92020b negative Other Collections line refused 92020', 'REFUSE', @cust, 'CASH', -50, 92020);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('R-92020b', 1, '#OTHER', 'TEST104', @today, -50, 'OTHER COLLECTION', '404');
    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total, ExpectErr) VALUES ('R-92021a', 'R-92021a account not on the list (the bank account 101020101) refused 92021', 'REFUSE', @cust, 'CASH', 100, 92021);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('R-92021a', 1, '#OTHER', 'TEST104', @today, 100, 'OTHER COLLECTION', @bank);
    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total, ExpectErr) VALUES ('R-92022', 'R-92022 Other Collections line with a real PO no. refused 92022', 'REFUSE', @cust, 'CASH', 100, 92022);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('R-92022', 1, @po, 'TEST104', @today, 100, 'OTHER COLLECTION', '404');
    -- 92025: the same header posted twice in one transaction (the second call is refused and rolls back both)
    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total, ExpectErr, Twice) VALUES ('R-92025a', 'R-92025a Other-only payment posted a second time refused 92025', 'REFUSE', @cust, 'CASH', @oamt, 92025, 1);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('R-92025a', 1, '#OTHER', 'TEST104 INTEREST', @today, @oamt, 'OTHER COLLECTION', '404');
    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total, ExpectErr, Twice) VALUES ('R-92025b', 'R-92025b invoice payment posted a second time refused 92025 (before 92017)', 'REFUSE', @cust, 'CASH', @amt, 92025, 1);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('R-92025b', 1, @po, @inv, @invDate, @amt, 'INVOICE PAYMENT', @ar);
    -- 92026: invoice line on 101020101, Other Collections line on 101020102
    IF EXISTS (SELECT 1 FROM dbo.ChartOfAccounts WHERE AccountCode = '101020102')
    BEGIN
        INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total, ExpectErr) VALUES ('R-92026', 'R-92026 invoice line bank 101020101 + Other line bank 101020102 refused 92026', 'REFUSE', @cust, 'CASH', @amt + 100, 92026);
        INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL, DebGL) VALUES ('R-92026', 1, @po, @inv, @invDate, @amt, 'INVOICE PAYMENT', @ar, @bank),
                                                                                 ('R-92026', 2, '#OTHER', 'TEST104', @today, 100, 'OTHER COLLECTION', '404', '101020102');
    END
    IF @acc2 IS NOT NULL
    BEGIN
        INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total) VALUES ('OC3', 'OC3', 'OWN', @cust, 'CASH', @amt + @oamt3);
        INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('OC3', 1, @po, @inv, @invDate, @amt, 'INVOICE PAYMENT', @ar), ('OC3', 2, '#OTHER', 'TEST104 OTHER', @today, @oamt3, 'OTHER COLLECTION', @acc2);
        INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total, ExpectErr, MapOff) VALUES ('R-92021b', CONCAT('R-92021b mapping row ', @acc2, ' deactivated in the tx: that account refused 92021'), 'REFUSE', @cust, 'CASH', 100, 92021, @acc2);
        INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('R-92021b', 1, '#OTHER', 'TEST104', @today, 100, 'OTHER COLLECTION', @acc2);
    END
END
IF @bcust IS NOT NULL
BEGIN
    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total) VALUES ('OC1d', 'OC1d balance-forward credit + invoice old = new', 'SAME', @bcust, 'CASH', @bamt - @cbal);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('OC1d', 1, @bpo, @binv, @bdate, @bamt, 'INVOICE PAYMENT', @ar), ('OC1d', 2, @cpo, @cinv, @cdate, -@cbal, 'INVOICE PAYMENT', @ar);
    -- 92023: invoice 1.00 + EWT 0.01, the whole credit, Other Collections for the rest (Gross < 0 with an EWT line)
    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total, ExpectErr) VALUES ('R-92023', 'R-92023 credit beyond the invoices with an EWT line refused 92023', 'REFUSE', @bcust, 'CASH', 0, 92023);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('R-92023', 1, @bpo, @binv, @bdate, 1.00, 'INVOICE PAYMENT', @ar), ('R-92023', 2, @bpo, @binv, @bdate, 0.01, 'EWT', @ar),
                        ('R-92023', 3, @cpo, @cinv, @cdate, -@cbal, 'INVOICE PAYMENT', @ar), ('R-92023', 4, '#OTHER', 'TEST104', @today, @cbal - 1.00, 'OTHER COLLECTION', '404');
END
IF @scust IS NOT NULL
BEGIN
    SET @u = ROUND(@sbal / 2, 2);
    -- OC4 / OC6b: the whole credit + Other Income for the same amount (no cash)
    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total) VALUES ('OC4', 'OC4', 'OWN', @scust, 'CASH', 0);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('OC4', 1, @spo, @sinv, @sdate, -@sbal, 'INVOICE PAYMENT', @ar), ('OC4', 2, '#OTHER', 'TEST104 INTEREST', @today, @sbal, 'OTHER COLLECTION', '404');
    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total, ExpectErr) VALUES ('BUG-OC4', 'BUG-OC4 old proc refuses the credit + Other Income payment (92014)', 'BUGOLD', @scust, 'CASH', 0, 92014);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('BUG-OC4', 1, @spo, @sinv, @sdate, -@sbal, 'INVOICE PAYMENT', @ar), ('BUG-OC4', 2, '#OTHER', 'TEST104 INTEREST', @today, @sbal, 'OTHER COLLECTION', '404');
    -- OC5: part of the credit
    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total) VALUES ('OC5', 'OC5', 'OWN', @scust, 'CASH', 0);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('OC5', 1, @spo, @sinv, @sdate, -@u, 'INVOICE PAYMENT', @ar), ('OC5', 2, '#OTHER', 'TEST104 INTEREST', @today, @u, 'OTHER COLLECTION', '404');
    -- OC7: the whole credit + an Other line 1,000.00 larger (cash left over)
    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total) VALUES ('OC7', 'OC7', 'OWN', @scust, 'CASH', 1000);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('OC7', 1, @spo, @sinv, @sdate, -@sbal, 'INVOICE PAYMENT', @ar), ('OC7', 2, '#OTHER', 'TEST104 INTEREST', @today, @sbal + 1000, 'OTHER COLLECTION', '404');
    -- 92014: the whole credit, Other Collections 1.00 short
    INSERT @hdr (CaseID, Name, Kind, Cust, PayType, Total, ExpectErr) VALUES ('R-92014', 'R-92014 credit more than invoices + Other Collections refused 92014', 'REFUSE', @scust, 'CASH', 0, 92014);
    INSERT @spec (CaseID, Ln, PO, Inv, InvDate, Amt, PType, CrGL) VALUES ('R-92014', 1, @spo, @sinv, @sdate, -@sbal, 'INVOICE PAYMENT', @ar), ('R-92014', 2, '#OTHER', 'TEST104', @today, @sbal - 1.00, 'OTHER COLLECTION', '404');
END

------------------------------------------------------------------
-- OC1a-d old = new footprints (ordinary payments: no Other Collections line)
------------------------------------------------------------------
IF @cust IS NULL INSERT @r VALUES ('OC1a-c ordinary payments old = new', 'SKIP', 'no open single-row AR invoice here');
IF @bcust IS NULL INSERT @r VALUES ('OC1d balance-forward credit + invoice old = new', 'SKIP', 'no customer with an open balance-forward credit and an open invoice here');
SELECT @kmax = MAX(Ord), @k = 0 FROM @hdr;
WHILE @k < @kmax
BEGIN
    SET @k += 1;
    SELECT @cid = CaseID, @cname = Name, @kind = Kind, @ccust = Cust FROM @hdr WHERE Ord = @k;
    IF @kind <> 'SAME' CONTINUE;
    SET @run = 'old';
    WHILE @run IS NOT NULL
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            DELETE @ph;
            INSERT INTO dbo.PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
            OUTPUT INSERTED.PaymentHeaderID INTO @ph
            SELECT Cust, @ref1, @ctl, @crno, PayType, Total, @today, 'TEST104', 'TEST104' FROM @hdr WHERE CaseID = @cid;
            SELECT @phid = ID FROM @ph;
            INSERT INTO dbo.ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
            SELECT @phid, @ccust, @ref1, PO, Inv, InvDate, Amt, PType, 'PAYMENT', ISNULL(DebGL, @bank), CrGL, '' FROM @spec WHERE CaseID = @cid ORDER BY Ln;
            IF @run = 'old' EXEC dbo.sp_AddPaymentClient_OLD_10172026200000 @PaymentHeaderID = @phid;
            ELSE            EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @phid;
            INSERT @fp SELECT @cid, @run, 'TCS', STRING_AGG(CONCAT(t.InvoiceNo, ':', t.AmountPaid, ':', t.Balance, ':', t.PayStatus, ':', ISNULL(t.EWTAmount, 0), ':', ISNULL(t.DiscountAmount, 0), ':', ISNULL(t.OffsetAmount, 0), ':', ISNULL(t.AdvancePayment, 0)), ',') WITHIN GROUP (ORDER BY t.InvoiceNo)
                       FROM dbo.TransactionChargeSales t WHERE t.CustomerKey = @ccust AND EXISTS (SELECT 1 FROM @spec s WHERE s.CaseID = @cid AND s.Inv = t.InvoiceNo AND s.PO = t.ReferenceNo);
            INSERT @fp SELECT @cid, @run, 'TKM', CONCAT(COUNT(*), '|', STRING_AGG(CONCAT(Mnemonic, ':', Status, ':', BranchCode, ':', Particulars), ',') WITHIN GROUP (ORDER BY Mnemonic)) FROM dbo.TicketMaster WHERE ReferenceNumber = @ref1;
            INSERT @fp SELECT @cid, @run, 'TKD', CONCAT(COUNT(*), '|', SUM(td.Debit), '|', SUM(td.Credit), '|', STRING_AGG(CONCAT(td.AccountCode, ':', td.Debit, ':', td.Credit), ',') WITHIN GROUP (ORDER BY td.AccountCode, td.Debit, td.Credit))
                       FROM dbo.TicketMaster tm INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode WHERE tm.ReferenceNumber = @ref1;
            INSERT @fp SELECT @cid, @run, 'CL', CONCAT(COUNT(*), '|', STRING_AGG(CONCAT(TransCode, ':', InvoiceNo, ':', Debit, ':', Credit, ':', Description, ':', Remarks), ',') WITHIN GROUP (ORDER BY InvoiceNo, Debit, Credit))
                       FROM dbo.ClientLedger WHERE ReferenceNumber = @ref1 AND AccountKey = @ccust;
            INSERT @fp SELECT @cid, @run, 'DIT', CONCAT(COUNT(*), '|', STRING_AGG(CONCAT(ItemType, ':', AccountCode, ':', Amount, ':', ControlNo, ':', CAST(IsResolved AS INT), ':', PeriodEnd), ',') WITHIN GROUP (ORDER BY ItemType))
                       FROM dbo.BankStatementRecon WHERE SourceRef = @ref1 AND SourceModule = 'AR-PAYMENT';
            INSERT @fp SELECT @cid, @run, 'ACCT', CAST(AccountBalance AS VARCHAR(40)) FROM dbo.ClientAccounts WHERE AccountKey = @ccust;
        END TRY
        BEGIN CATCH
            INSERT @r VALUES (CONCAT(@cname, ' (', @run, ' proc)'), 'ERROR', LEFT(CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE()), 1000));
        END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
    END
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE CaseID = @cid AND Run = 'old' EXCEPT SELECT Item, Val FROM @fp WHERE CaseID = @cid AND Run = 'new') x;
    INSERT @r VALUES (@cname,
        CASE WHEN @n = 0 AND (SELECT COUNT(*) FROM @fp WHERE CaseID = @cid AND Run = 'new') = 6 AND (SELECT COUNT(*) FROM @fp WHERE CaseID = @cid AND Run = 'old') = 6
                  AND (SELECT Val FROM @fp WHERE CaseID = @cid AND Run = 'new' AND Item = 'TKD') NOT LIKE '0|%' THEN 'PASS' ELSE 'FAIL' END,
        LEFT(CONCAT(@n, ' of 6 footprint rows differ (old ', (SELECT COUNT(*) FROM @fp WHERE CaseID = @cid AND Run = 'old'), ' / new ', (SELECT COUNT(*) FROM @fp WHERE CaseID = @cid AND Run = 'new'),
                    ' rows); ticket ', (SELECT Val FROM @fp WHERE CaseID = @cid AND Run = 'new' AND Item = 'TKD'),
                    '; invoice rows ', (SELECT Val FROM @fp WHERE CaseID = @cid AND Run = 'new' AND Item = 'TCS'),
                    '; DIT ', (SELECT Val FROM @fp WHERE CaseID = @cid AND Run = 'new' AND Item = 'DIT')), 1000));
END

------------------------------------------------------------------
-- OC2 Other Collections only, cash (new proc)
------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM @hdr WHERE CaseID = 'OC2') INSERT @r VALUES ('OC2 Other Collections only: DR bank / CR 404, DIT, no ledger, Cash Receipts, details sets', 'SKIP', 'no INVOICE fixture (its customer is used)');
ELSE
BEGIN
    SET @cid = 'OC2'; SET @ccust = @cust; SELECT @detErr = NULL;
    BEGIN TRAN;
    BEGIN TRY
        SELECT @t0 = CONCAT(COUNT(*), '|', SUM(Balance), '|', SUM(AmountPaid)) FROM dbo.TransactionChargeSales WHERE CustomerKey = @ccust;
        SELECT @a0 = AccountBalance FROM dbo.ClientAccounts WHERE AccountKey = @ccust;
        DELETE @ph;
        INSERT INTO dbo.PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
        OUTPUT INSERTED.PaymentHeaderID INTO @ph
        SELECT Cust, @ref1, @ctl, @crno, PayType, Total, @today, 'TEST104', 'TEST104' FROM @hdr WHERE CaseID = @cid;
        SELECT @phid = ID FROM @ph;
        INSERT INTO dbo.ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
        SELECT @phid, @ccust, @ref1, PO, Inv, InvDate, Amt, PType, 'PAYMENT', ISNULL(DebGL, @bank), CrGL, '' FROM @spec WHERE CaseID = @cid ORDER BY Ln;
        EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @phid;

        SELECT @nTM = COUNT(*), @mn = MAX(Mnemonic) FROM dbo.TicketMaster WHERE ReferenceNumber = @ref1;
        SELECT @nTD = COUNT(*), @dr = SUM(td.Debit), @cr = SUM(td.Credit),
               @vBank = SUM(CASE WHEN td.AccountCode = @bank THEN td.Debit - td.Credit ELSE 0 END),
               @v404  = SUM(CASE WHEN td.AccountCode = '404' THEN td.Credit - td.Debit ELSE 0 END),
               @lines = STRING_AGG(CONCAT(td.AccountCode, ' DR ', td.Debit, ' CR ', td.Credit), ', ') WITHIN GROUP (ORDER BY td.Debit DESC, td.AccountCode)
        FROM dbo.TicketMaster tm INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode WHERE tm.ReferenceNumber = @ref1;
        SELECT @nD = COUNT(*), @dAmt = SUM(Amount), @dCtl = MAX(ControlNo), @dRes = MAX(CAST(IsResolved AS INT)), @dAcc = MAX(AccountCode)
        FROM dbo.BankStatementRecon WHERE SourceRef = @ref1 AND SourceModule = 'AR-PAYMENT';
        SELECT @nCL = COUNT(*) FROM dbo.ClientLedger WHERE ReferenceNumber = @ref1;
        SELECT @t1 = CONCAT(COUNT(*), '|', SUM(Balance), '|', SUM(AmountPaid)) FROM dbo.TransactionChargeSales WHERE CustomerKey = @ccust;
        SELECT @a1 = AccountBalance FROM dbo.ClientAccounts WHERE AccountKey = @ccust;
        SELECT @crN = COUNT(*), @crAmt = SUM(InvoicePaymentAmount) FROM dbo.funcview_CustomerCashReceipts(@today, @today, 'P', NULL) WHERE CRNo = @crno AND CustomerKey = @ccust;
        SELECT @crOldN = COUNT(*), @crOld = SUM(InvoicePaymentAmount) FROM dbo.funcview_CustomerCashReceipts_OLD_10172026200000(@today, @today, 'P', NULL) WHERE CRNo = @crno AND CustomerKey = @ccust;
        -- sp_GetClientPaymentDetails sets 3 / 4: the same SELECTs as the proc (a multi-set proc cannot be captured with INSERT ... EXEC)
        SELECT @s3 = COUNT(*) FROM (SELECT InvoiceNo, PONumber FROM dbo.ARPaymentDetails WHERE PaymentHeaderID = @phid AND ISNULL(PONumber, '') <> '#OTHER' GROUP BY InvoiceNo, PONumber) x;
        SELECT @s3old = COUNT(*) FROM (SELECT InvoiceNo, PONumber FROM dbo.ARPaymentDetails WHERE PaymentHeaderID = @phid GROUP BY InvoiceNo, PONumber) x;
        SELECT @s4 = COUNT(*), @s4amt = SUM(D.Amount), @s4t = MAX(coa.Description)
        FROM dbo.ARPaymentDetails D LEFT JOIN dbo.ChartOfAccounts coa ON coa.AccountCode = D.CreditGLCode
        WHERE D.PaymentHeaderID = @phid AND D.PaymentType = 'OTHER COLLECTION';
        SET @defD = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetClientPaymentDetails'));
        SET @defOK = CASE WHEN CHARINDEX('ISNULL(PONumber, '''') <> ''#OTHER''', @defD) > 0 AND CHARINDEX('D.PaymentType = ''OTHER COLLECTION''', @defD) > 0 THEN 1 ELSE 0 END;
        BEGIN TRY
            EXEC dbo.sp_GetClientPaymentDetails @PaymentHeaderID = @phid;   -- its 4 result sets show in SSMS
        END TRY
        BEGIN CATCH
            SET @detErr = LEFT(CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE()), 400);
        END CATCH

        INSERT @r VALUES ('OC2 Other Collections only: DR bank / CR 404, DIT, no ledger, Cash Receipts, details sets',
            CASE WHEN @nTM = 1 AND @mn = 'OR-COLL' AND @nTD = 2 AND @vBank = @oamt AND @v404 = @oamt AND @dr = @cr
                      AND @nD = 1 AND @dAmt = @oamt AND @dCtl = @ctl AND @dRes = 0 AND @dAcc = @bank
                      AND @nCL = 0 AND @t1 = @t0 AND @a1 = @a0
                      AND @crN = 1 AND @crAmt = @oamt AND @s3 = 0 AND @s4 = 1 AND @s4amt = @oamt AND @defOK = 1 AND @detErr IS NULL THEN 'PASS' ELSE 'FAIL' END,
            LEFT(CONCAT('ticket ', @nTM, ' ', @mn, ': ', @lines, '; DIT ', @nD, ' ', @dAcc, ' ', @dAmt, ' ctl ', @dCtl, ' resolved ', @dRes,
                        '; ledger rows ', @nCL, '; invoices ', CASE WHEN @t1 = @t0 THEN 'unchanged' ELSE CONCAT(@t0, ' -> ', @t1) END,
                        '; account ', @a0, ' -> ', @a1, '; Cash Receipts ', @crN, ' row(s) ', @crAmt, ' (old function: ', @crOldN, ' row(s) ', @crOld, ')',
                        '; details set 3 rows ', @s3, ' (old set 3 rule: ', @s3old, '), set 4 rows ', @s4, ' ', @s4amt, ' ', @s4t,
                        '; proc text ', CASE WHEN @defOK = 1 THEN 'ok' ELSE 'NOT the [104] sets' END, CASE WHEN @detErr IS NULL THEN '' ELSE CONCAT('; details proc error ', @detErr) END), 1000));
    END TRY
    BEGIN CATCH
        INSERT @r VALUES ('OC2 Other Collections only: DR bank / CR 404, DIT, no ledger, Cash Receipts, details sets', 'ERROR', LEFT(CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE()), 1000));
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
END

------------------------------------------------------------------
-- OC3 invoice + Other Collections line in one payment
------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM @hdr WHERE CaseID = 'OC3') INSERT @r VALUES ('OC3 invoice + Other Collections line: one ticket, bank = invoice + other, DIT = total', 'SKIP', 'no INVOICE fixture or no second active Other Collections account');
ELSE
BEGIN
    SET @cid = 'OC3'; SET @ccust = @cust;
    BEGIN TRAN;
    BEGIN TRY
        DELETE @ph;
        INSERT INTO dbo.PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
        OUTPUT INSERTED.PaymentHeaderID INTO @ph
        SELECT Cust, @ref1, @ctl, @crno, PayType, Total, @today, 'TEST104', 'TEST104' FROM @hdr WHERE CaseID = @cid;
        SELECT @phid = ID FROM @ph;
        INSERT INTO dbo.ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
        SELECT @phid, @ccust, @ref1, PO, Inv, InvDate, Amt, PType, 'PAYMENT', ISNULL(DebGL, @bank), CrGL, '' FROM @spec WHERE CaseID = @cid ORDER BY Ln;
        EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @phid;

        SELECT @nTM = COUNT(*), @mn = MAX(Mnemonic) FROM dbo.TicketMaster WHERE ReferenceNumber = @ref1;
        SELECT @nTD = COUNT(*), @dr = SUM(td.Debit), @cr = SUM(td.Credit),
               @vBank = SUM(CASE WHEN td.AccountCode = @bank THEN td.Debit - td.Credit ELSE 0 END),
               @vAR   = SUM(CASE WHEN td.AccountCode = @ar THEN td.Credit - td.Debit ELSE 0 END),
               @vAcc2 = SUM(CASE WHEN td.AccountCode = @acc2 THEN td.Credit - td.Debit ELSE 0 END),
               @lines = STRING_AGG(CONCAT(td.AccountCode, ' DR ', td.Debit, ' CR ', td.Credit), ', ') WITHIN GROUP (ORDER BY td.Debit DESC, td.AccountCode)
        FROM dbo.TicketMaster tm INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode WHERE tm.ReferenceNumber = @ref1;
        SELECT @nD = COUNT(*), @dAmt = SUM(Amount), @dCtl = MAX(ControlNo) FROM dbo.BankStatementRecon WHERE SourceRef = @ref1 AND SourceModule = 'AR-PAYMENT';
        SELECT @iPaid = AmountPaid, @iBal = Balance, @iStat = PayStatus FROM dbo.TransactionChargeSales WHERE InvoiceNo = @inv AND ReferenceNo = @po AND CustomerKey = @ccust;
        SELECT @nCL = COUNT(*), @clD = SUM(Debit), @clC = SUM(Credit) FROM dbo.ClientLedger WHERE ReferenceNumber = @ref1 AND AccountKey = @ccust;
        SELECT @crN = COUNT(*), @crAmt = SUM(InvoicePaymentAmount) FROM dbo.funcview_CustomerCashReceipts(@today, @today, 'P', NULL) WHERE CRNo = @crno AND CustomerKey = @ccust;
        SELECT @s3 = COUNT(*) FROM (SELECT InvoiceNo, PONumber FROM dbo.ARPaymentDetails WHERE PaymentHeaderID = @phid AND ISNULL(PONumber, '') <> '#OTHER' GROUP BY InvoiceNo, PONumber) x;
        SELECT @s4 = COUNT(*), @s4amt = SUM(Amount) FROM dbo.ARPaymentDetails WHERE PaymentHeaderID = @phid AND PaymentType = 'OTHER COLLECTION';
        SELECT @dCrd = NULL;
        SELECT TOP 1 @dCrd = CASE WHEN a.PaymentType = 'OTHER COLLECTION' THEN NULL ELSE a.CreditGLCode END   -- details header rule (see D1)
        FROM dbo.ARPaymentDetails a WHERE a.PaymentHeaderID = @phid
        ORDER BY CASE WHEN a.PaymentType = 'INVOICE PAYMENT' THEN 0 WHEN a.PaymentType = 'OTHER COLLECTION' THEN 2 ELSE 1 END, a.InvoiceNo;
        INSERT @r VALUES ('OC3 invoice + Other Collections line: one ticket, bank = invoice + other, DIT = total',
            CASE WHEN @nTM = 1 AND @nTD = 3 AND @dr = @cr AND @vBank = @amt + @oamt3 AND @vAR = @amt AND @vAcc2 = @oamt3
                      AND @nD = 1 AND @dAmt = @amt + @oamt3 AND @dCtl = @ctl
                      AND @iBal = 0 AND @iPaid = @amt AND @iStat = 'FULLYPAID' AND @nCL = 1 AND @clC = @amt AND @clD = 0
                      AND @crAmt = @amt + @oamt3 AND @s3 = 1 AND @s4 = 1 AND @s4amt = @oamt3 AND @dCrd = @ar THEN 'PASS' ELSE 'FAIL' END,
            LEFT(CONCAT('invoice ', @inv, ' ', @amt, ' + ', @acc2, ' ', @oamt3, ': ticket ', @nTM, ' ', @mn, ': ', @lines, '; DIT ', @nD, ' ', @dAmt,
                        '; invoice after ', @iPaid, ' / ', @iBal, ' ', @iStat, '; ledger ', @nCL, ' row(s) DR ', @clD, ' CR ', @clC,
                        '; Cash Receipts ', @crN, ' row(s) ', @crAmt, '; details set 3 rows ', @s3, ', set 4 rows ', @s4, ' ', @s4amt,
                        '; details header CreditGLCode ', ISNULL(@dCrd, '(null)')), 1000));
    END TRY
    BEGIN CATCH
        INSERT @r VALUES ('OC3 invoice + Other Collections line: one ticket, bank = invoice + other, DIT = total', 'ERROR', LEFT(CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE()), 1000));
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
END

------------------------------------------------------------------
-- D1 details header of an Other-only payment: CreditGLCode NULL, DebitGLCode = the bank
--    (set 1 of sp_GetClientPaymentDetails; a multi-set proc cannot be captured, so its OUTER APPLY is repeated here
--     and the proc text is checked to contain it; the proc itself runs in OC2)
------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM @hdr WHERE CaseID = 'OC2') INSERT @r VALUES ('D1 details header of an Other-only payment: CreditGLCode NULL, DebitGLCode = bank', 'SKIP', 'no INVOICE fixture (its customer is used)');
ELSE
BEGIN
    SET @cid = 'OC2'; SET @ccust = @cust; SELECT @dDeb = NULL, @dCrd = NULL, @dCrdOld = NULL;
    BEGIN TRAN;
    BEGIN TRY
        DELETE @ph;
        INSERT INTO dbo.PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
        OUTPUT INSERTED.PaymentHeaderID INTO @ph
        SELECT Cust, @ref1, @ctl, @crno, PayType, Total, @today, 'TEST104', 'TEST104' FROM @hdr WHERE CaseID = @cid;
        SELECT @phid = ID FROM @ph;
        INSERT INTO dbo.ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
        SELECT @phid, @ccust, @ref1, PO, Inv, InvDate, Amt, PType, 'PAYMENT', ISNULL(DebGL, @bank), CrGL, '' FROM @spec WHERE CaseID = @cid ORDER BY Ln;
        EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @phid;
        -- the [104] v2 header rule
        SELECT TOP 1 @dDeb = a.DebitGLCode, @dCrd = CASE WHEN a.PaymentType = 'OTHER COLLECTION' THEN NULL ELSE a.CreditGLCode END
        FROM dbo.ARPaymentDetails a WHERE a.PaymentHeaderID = @phid
        ORDER BY CASE WHEN a.PaymentType = 'INVOICE PAYMENT' THEN 0 WHEN a.PaymentType = 'OTHER COLLECTION' THEN 2 ELSE 1 END, a.InvoiceNo;
        -- the backup's header rule (for the detail only)
        SELECT TOP 1 @dCrdOld = a.CreditGLCode FROM dbo.ARPaymentDetails a WHERE a.PaymentHeaderID = @phid
        ORDER BY CASE WHEN a.PaymentType = 'INVOICE PAYMENT' THEN 0 ELSE 1 END, a.InvoiceNo;
        SET @defD = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetClientPaymentDetails'));
        SET @dDefOK = CASE WHEN CHARINDEX('CASE WHEN a.PaymentType = ''OTHER COLLECTION'' THEN NULL ELSE a.CreditGLCode END', @defD) > 0
                            AND CHARINDEX('WHEN a.PaymentType = ''OTHER COLLECTION'' THEN 2 ELSE 1 END', @defD) > 0 THEN 1 ELSE 0 END;
        INSERT @r VALUES ('D1 details header of an Other-only payment: CreditGLCode NULL, DebitGLCode = bank',
            CASE WHEN @dCrd IS NULL AND @dDeb = @bank AND @dDefOK = 1 THEN 'PASS' ELSE 'FAIL' END,
            CONCAT('header DebitGLCode ', ISNULL(@dDeb, '(null)'), ', CreditGLCode ', ISNULL(@dCrd, '(null)'), ' (backup''s rule would show ', ISNULL(@dCrdOld, '(null)'),
                   '); proc text ', CASE WHEN @dDefOK = 1 THEN 'has the [104] v2 header rule' ELSE 'does NOT have the [104] v2 header rule' END));
    END TRY
    BEGIN CATCH
        INSERT @r VALUES ('D1 details header of an Other-only payment: CreditGLCode NULL, DebitGLCode = bank', 'ERROR', LEFT(CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE()), 1000));
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
END

------------------------------------------------------------------
-- OC4 / OC5 / OC7 balance-forward credit closed by Other Collections (OC7: with cash left over)
------------------------------------------------------------------
IF @scust IS NULL
BEGIN
    INSERT @r VALUES ('OC4 whole BF credit + Other Income: DR AR / CR 404, no DIT, credit closed, account up', 'SKIP', 'no open balance-forward credit here');
    INSERT @r VALUES ('OC5 part of a BF credit + Other Income: credit PARTIAL and still listed', 'SKIP', 'no open balance-forward credit here');
    INSERT @r VALUES ('OC7 whole BF credit + a larger Other line: cash left over = DIT, DR AR = credit, CR 404 = line', 'SKIP', 'no open balance-forward credit here');
END
ELSE
BEGIN
    SET @cid = 'OC4';
    WHILE @cid IS NOT NULL
    BEGIN
        SET @ccust = @scust;
        SET @cname = CASE @cid WHEN 'OC4' THEN 'OC4 whole BF credit + Other Income: DR AR / CR 404, no DIT, credit closed, account up'
                               WHEN 'OC5' THEN 'OC5 part of a BF credit + Other Income: credit PARTIAL and still listed'
                               ELSE 'OC7 whole BF credit + a larger Other line: cash left over = DIT, DR AR = credit, CR 404 = line' END;
        SELECT @n = CASE @cid WHEN 'OC5' THEN 1 ELSE 0 END;   -- 0 = whole credit, 1 = part
        SET @xtra = CASE @cid WHEN 'OC7' THEN 1000 ELSE 0 END;   -- cash beyond the credit
        SET @u = CASE @cid WHEN 'OC5' THEN ROUND(@sbal / 2, 2) ELSE @sbal END;
        BEGIN TRAN;
        BEGIN TRY
            SELECT @a0 = AccountBalance FROM dbo.ClientAccounts WHERE AccountKey = @ccust;
            SELECT @sb0 = SUM(Balance) FROM dbo.TransactionChargeSales WHERE CustomerKey = @ccust;
            DELETE @ph;
            INSERT INTO dbo.PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
            OUTPUT INSERTED.PaymentHeaderID INTO @ph
            SELECT Cust, @ref1, @ctl, @crno, PayType, Total, @today, 'TEST104', 'TEST104' FROM @hdr WHERE CaseID = @cid;
            SELECT @phid = ID FROM @ph;
            INSERT INTO dbo.ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
            SELECT @phid, @ccust, @ref1, PO, Inv, InvDate, Amt, PType, 'PAYMENT', ISNULL(DebGL, @bank), CrGL, '' FROM @spec WHERE CaseID = @cid ORDER BY Ln;
            EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @phid;

            SELECT @nTM = COUNT(*), @mn = MAX(Mnemonic) FROM dbo.TicketMaster WHERE ReferenceNumber = @ref1;
            SELECT @nTD = COUNT(*), @dr = SUM(td.Debit), @cr = SUM(td.Credit),
                   @vBank = SUM(CASE WHEN td.AccountCode = @bank THEN td.Debit - td.Credit ELSE 0 END),
                   @vAR   = SUM(CASE WHEN td.AccountCode = @ar THEN td.Debit - td.Credit ELSE 0 END),
                   @v404  = SUM(CASE WHEN td.AccountCode = '404' THEN td.Credit - td.Debit ELSE 0 END),
                   @lines = STRING_AGG(CONCAT(td.AccountCode, ' DR ', td.Debit, ' CR ', td.Credit), ', ') WITHIN GROUP (ORDER BY td.Debit DESC, td.AccountCode)
            FROM dbo.TicketMaster tm INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode WHERE tm.ReferenceNumber = @ref1;
            SELECT @nD = COUNT(*), @dAmt = SUM(Amount), @dAcc = MAX(AccountCode), @dCtl = MAX(ControlNo) FROM dbo.BankStatementRecon WHERE (SourceRef = @ref1 OR ReferenceNo = @ref1);
            SELECT @iPaid = AmountPaid, @iBal = Balance, @iStat = PayStatus FROM dbo.TransactionChargeSales WHERE InvoiceNo = @sinv AND ReferenceNo = @spo AND CustomerKey = @ccust;
            SELECT @nCL = COUNT(*), @clD = SUM(Debit), @clC = SUM(Credit), @clDesc = MAX(Description) FROM dbo.ClientLedger WHERE ReferenceNumber = @ref1 AND AccountKey = @ccust;
            SELECT @a1 = AccountBalance FROM dbo.ClientAccounts WHERE AccountKey = @ccust;
            SELECT @sb1 = SUM(Balance) FROM dbo.TransactionChargeSales WHERE CustomerKey = @ccust;
            DELETE @sl;
            INSERT @sl EXEC dbo.splist_ARAccounts @parmcustkey = @ccust, @IncludeCredits = 1;
            SELECT @slN = COUNT(*), @slBal = MAX(Balance), @slType = MAX(InvoiceType) FROM @sl WHERE InvoiceNo = @sinv AND OrderNo = @spo;

            INSERT @r VALUES (@cname,
                CASE WHEN @nTM = 1 AND @nTD = CASE WHEN @xtra > 0 THEN 3 ELSE 2 END AND @dr = @cr AND @dr = @u + @xtra AND @vAR = @u AND @v404 = @u + @xtra AND ISNULL(@vBank, 0) = @xtra
                          AND ((@xtra = 0 AND @nD = 0) OR (@xtra > 0 AND @nD = 1 AND @dAmt = @xtra AND @dAcc = @bank AND @dCtl = @ctl))
                          AND @iPaid = -@u AND @nCL = 1 AND @clD = @u AND @clC = 0 AND @a1 - @a0 = @u AND @sb1 - @sb0 = @u
                          AND ((@n = 0 AND @iBal = 0 AND @iStat = 'FULLYPAID' AND @slN = 0)
                            OR (@n = 1 AND @iBal = -(@sbal - @u) AND @iStat = 'PARTIAL' AND @slN = 1 AND @slBal = -(@sbal - @u) AND @slType = 'BF CREDIT')) THEN 'PASS' ELSE 'FAIL' END,
                LEFT(CONCAT(@ccust, ' ', @sname, ' credit ', @sinv, ' ', -@sbal, ', used ', -@u, ' + 404 ', @u + @xtra, ': ticket ', @nTM, ' ', @mn, ': ', @lines,
                            '; recon items ', @nD, CASE WHEN @nD > 0 THEN CONCAT(' (', @dAcc, ' ', @dAmt, ' ctl ', @dCtl, ')') ELSE '' END, '; credit row after paid ', @iPaid, ' balance ', @iBal, ' ', @iStat,
                            '; ledger ', @nCL, ' row(s) DR ', @clD, ' CR ', @clC, ' "', @clDesc, '"',
                            '; account ', @a0, ' -> ', @a1, ' (open rows ', @sb0, ' -> ', @sb1, ')',
                            '; splist @IncludeCredits=1 lists it: ', @slN, ' row(s) ', @slType, ' ', @slBal), 1000));
        END TRY
        BEGIN CATCH
            INSERT @r VALUES (@cname, 'ERROR', LEFT(CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE()), 1000));
        END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @cid = CASE @cid WHEN 'OC4' THEN 'OC5' WHEN 'OC5' THEN 'OC7' ELSE NULL END;
    END
END

------------------------------------------------------------------
-- OC6a / OC6b reversal of OC2 and OC4 with sp_ReversePaymentClient
------------------------------------------------------------------
SET @cid = 'OC2';
WHILE @cid IS NOT NULL
BEGIN
    SET @cname = CASE @cid WHEN 'OC2' THEN 'OC6a reversal of OC2: ticket mirrored, DIT voided, Cash Receipts empty, accounts net 0'
                           ELSE 'OC6b reversal of OC4: ticket mirrored, credit back UNPAID, ledger net 0, account back' END;
    IF NOT EXISTS (SELECT 1 FROM @hdr WHERE CaseID = @cid)
        INSERT @r VALUES (@cname, 'SKIP', 'its fixture is missing here');
    ELSE
    BEGIN
        SELECT @ccust = Cust FROM @hdr WHERE CaseID = @cid;
        BEGIN TRAN;
        BEGIN TRY
            SELECT @a0 = AccountBalance FROM dbo.ClientAccounts WHERE AccountKey = @ccust;
            SELECT @t0 = CONCAT(COUNT(*), '|', SUM(Balance), '|', SUM(AmountPaid)) FROM dbo.TransactionChargeSales WHERE CustomerKey = @ccust;
            DELETE @ph;
            INSERT INTO dbo.PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
            OUTPUT INSERTED.PaymentHeaderID INTO @ph
            SELECT Cust, @ref1, @ctl, @crno, PayType, Total, @today, 'TEST104', 'TEST104' FROM @hdr WHERE CaseID = @cid;
            SELECT @phid = ID FROM @ph;
            INSERT INTO dbo.ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
            SELECT @phid, @ccust, @ref1, PO, Inv, InvDate, Amt, PType, 'PAYMENT', ISNULL(DebGL, @bank), CrGL, '' FROM @spec WHERE CaseID = @cid ORDER BY Ln;
            EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @phid;
            EXEC dbo.sp_ReversePaymentClient @PaymentHeaderID = @phid, @ReversedBy = 'TEST104';

            SELECT @st = Status FROM dbo.PaymentHeader WHERE PaymentHeaderID = @phid;
            SELECT @nTM = COUNT(*), @nTMrev = SUM(CASE WHEN Status = 'REVERSED' THEN 1 ELSE 0 END) FROM dbo.TicketMaster WHERE ReferenceNumber = @ref1;
            SELECT @nz = COUNT(*) FROM (SELECT AccountCode FROM dbo.TicketDetails WHERE ReferenceNumber = @ref1 GROUP BY AccountCode HAVING SUM(Debit - Credit) <> 0) x;
            SELECT @nTD = COUNT(*), @dr = SUM(Debit), @cr = SUM(Credit) FROM dbo.TicketDetails WHERE ReferenceNumber = @ref1;
            SELECT @nD = COUNT(*), @dRes = MIN(CAST(IsResolved AS INT)), @dWhy = MAX(ResolvedReason) FROM dbo.BankStatementRecon WHERE SourceRef = @ref1 AND SourceModule = 'AR-PAYMENT';
            SELECT @nCL = COUNT(*), @clD = ISNULL(SUM(Debit), 0), @clC = ISNULL(SUM(Credit), 0) FROM dbo.ClientLedger WHERE ReferenceNumber = @ref1 AND AccountKey = @ccust;
            SELECT @a1 = AccountBalance FROM dbo.ClientAccounts WHERE AccountKey = @ccust;
            SELECT @t1 = CONCAT(COUNT(*), '|', SUM(Balance), '|', SUM(AmountPaid)) FROM dbo.TransactionChargeSales WHERE CustomerKey = @ccust;
            SELECT @crN = COUNT(*) FROM dbo.funcview_CustomerCashReceipts(@today, @today, 'P', NULL) WHERE CRNo = @crno AND CustomerKey = @ccust;
            SELECT @iPaid = NULL, @iBal = NULL, @iStat = NULL;
            IF @cid = 'OC4' SELECT @iPaid = AmountPaid, @iBal = Balance, @iStat = PayStatus FROM dbo.TransactionChargeSales WHERE InvoiceNo = @sinv AND ReferenceNo = @spo AND CustomerKey = @ccust;

            INSERT @r VALUES (@cname,
                CASE WHEN @st = 'REVERSED' AND @nTM = 2 AND @nTMrev = 1 AND @nz = 0 AND @dr = @cr AND @a1 = @a0 AND @t1 = @t0 AND @crN = 0
                          AND ((@cid = 'OC2' AND @nTD = 4 AND @nD = 1 AND @dRes = 1 AND @dWhy = 'REVERSED' AND @nCL = 0)
                            OR (@cid = 'OC4' AND @nTD = 4 AND @nD = 0 AND @nCL = 2 AND @clD = @clC AND @clD = @sbal AND @iPaid = 0 AND @iBal = -@sbal AND @iStat = 'UNPAID')) THEN 'PASS' ELSE 'FAIL' END,
                LEFT(CONCAT('payment ', @st, '; tickets ', @nTM, ' (', @nTMrev, ' REVERSED), ', @nTD, ' lines DR ', @dr, ' CR ', @cr, ', accounts not netting to 0: ', @nz,
                            '; DIT ', @nD, ' resolved ', @dRes, ' ', @dWhy, '; ledger ', @nCL, ' row(s) DR ', @clD, ' CR ', @clC,
                            '; account ', @a0, ' -> ', @a1, '; invoices ', CASE WHEN @t1 = @t0 THEN 'as before' ELSE CONCAT(@t0, ' -> ', @t1) END,
                            '; Cash Receipts rows after ', @crN,
                            CASE WHEN @cid = 'OC4' THEN CONCAT('; credit row ', @sinv, ' paid ', @iPaid, ' balance ', @iBal, ' ', @iStat) ELSE '' END), 1000));
        END TRY
        BEGIN CATCH
            INSERT @r VALUES (@cname, 'ERROR', LEFT(CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE()), 1000));
        END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
    END
    SET @cid = CASE @cid WHEN 'OC2' THEN 'OC4' ELSE NULL END;
END

------------------------------------------------------------------
-- refusals (new proc) and BUG SHOWN (old proc): one transaction each
------------------------------------------------------------------
IF @cust IS NULL INSERT @r VALUES ('R-92020 / 92021 / 92022 refusals, BUG-OC2', 'SKIP', 'no INVOICE fixture (its customer is used)');
IF @scust IS NULL INSERT @r VALUES ('R-92014 / BUG-OC4', 'SKIP', 'no open balance-forward credit here');
IF @bcust IS NULL INSERT @r VALUES ('R-92023', 'SKIP', 'no customer with an open balance-forward credit and an open invoice here');
IF @cust IS NOT NULL AND @acc2 IS NULL INSERT @r VALUES ('R-92021b mapping row deactivated', 'SKIP', 'no second active Other Collections account');
SET @k = 0;
WHILE @k < @kmax
BEGIN
    SET @k += 1;
    SELECT @cid = CaseID, @cname = Name, @kind = Kind, @exp = ExpectErr, @mapoff = MapOff, @ccust = Cust, @twice = Twice FROM @hdr WHERE Ord = @k;
    IF @kind NOT IN ('REFUSE', 'BUGOLD') CONTINUE;
    SELECT @err = NULL, @msg = NULL, @tc = NULL, @rows = NULL;
    BEGIN TRAN;
    BEGIN TRY
        IF @mapoff IS NOT NULL
            UPDATE dbo.JournalEntryMapping SET IsActive = 0 WHERE Origin = 'OR' AND Mnemonic = 'OR-OTHERCOLL' AND AccountCode = @mapoff;
        DELETE @ph;
        INSERT INTO dbo.PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
        OUTPUT INSERTED.PaymentHeaderID INTO @ph
        SELECT Cust, @ref1, @ctl, @crno, PayType, Total, @today, 'TEST104', 'TEST104' FROM @hdr WHERE CaseID = @cid;
        SELECT @phid = ID FROM @ph;
        INSERT INTO dbo.ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
        SELECT @phid, @ccust, @ref1, PO, Inv, InvDate, Amt, PType, 'PAYMENT', ISNULL(DebGL, @bank), CrGL, '' FROM @spec WHERE CaseID = @cid ORDER BY Ln;
        IF @kind = 'BUGOLD' EXEC dbo.sp_AddPaymentClient_OLD_10172026200000 @PaymentHeaderID = @phid;
        ELSE                EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @phid;
        IF @twice = 1       EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @phid;   -- the same header again
    END TRY
    BEGIN CATCH
        SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
    END CATCH
    SELECT @tc = @@TRANCOUNT;
    SELECT @rows = (SELECT COUNT(*) FROM dbo.PaymentHeader WHERE ReferenceNo = @ref1) + (SELECT COUNT(*) FROM dbo.ARPaymentDetails WHERE ReferenceNo = @ref1)
                 + (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber = @ref1) + (SELECT COUNT(*) FROM dbo.ClientLedger WHERE ReferenceNumber = @ref1)
                 + (SELECT COUNT(*) FROM dbo.BankStatementRecon WHERE SourceRef = @ref1 OR ReferenceNo = @ref1);
    IF @@TRANCOUNT > 0 ROLLBACK;
    SELECT @sig = CONCAT(
        (SELECT STRING_AGG(CONCAT(t.CustomerKey, ':', t.InvoiceNo, ':', t.AmountPaid, ':', t.Balance, ':', t.PayStatus, ':', ISNULL(t.EWTAmount, 0), ':', ISNULL(t.DiscountAmount, 0), ':', ISNULL(t.OffsetAmount, 0), ':', ISNULL(t.AdvancePayment, 0)), ',')
                WITHIN GROUP (ORDER BY t.CustomerKey, t.InvoiceNo)
         FROM dbo.TransactionChargeSales t WHERE EXISTS (SELECT 1 FROM @fx f WHERE f.c = t.CustomerKey AND f.i = t.InvoiceNo AND f.p = t.ReferenceNo)), '|',
        (SELECT STRING_AGG(CONCAT(a.AccountKey, ':', a.AccountBalance), ',') WITHIN GROUP (ORDER BY a.AccountKey) FROM dbo.ClientAccounts a WHERE a.AccountKey IN (SELECT c FROM @fx)), '|',
        (SELECT STRING_AGG(CONCAT(m.AccountCode, ':', CAST(m.IsActive AS INT)), ',') WITHIN GROUP (ORDER BY m.Seq) FROM dbo.JournalEntryMapping m WHERE m.Origin = 'OR' AND m.Mnemonic = 'OR-OTHERCOLL'));
    INSERT @r VALUES (@cname,
        CASE WHEN @kind = 'REFUSE' THEN CASE WHEN @err = @exp AND @tc = 0 AND @rows = 0 AND @sig = @sig0 THEN 'PASS' ELSE 'FAIL' END
             ELSE CASE WHEN @err = @exp AND @tc = 0 AND @rows = 0 AND @sig = @sig0 THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END END,
        LEFT(CONCAT(CASE WHEN @kind = 'BUGOLD' THEN 'old proc: ' ELSE '' END, 'error ', ISNULL(CAST(@err AS VARCHAR(10)), 'none (posted)'), ' (expected ', @exp, '): ', ISNULL(@msg, '-'),
                    ' | @@TRANCOUNT after the CATCH ', @tc, ', rows under the reference ', @rows, ', fixture rows + mapping ', CASE WHEN @sig = @sig0 THEN 'unchanged' ELSE 'CHANGED' END), 1000));
END

------------------------------------------------------------------
-- leftovers
------------------------------------------------------------------
Report:
SELECT @tc = @@TRANCOUNT;
SELECT @rows = (SELECT COUNT(*) FROM dbo.PaymentHeader WHERE ReferenceNo = @ref1 OR ControlNo = @ctl OR CRNo = @crno)
             + (SELECT COUNT(*) FROM dbo.ARPaymentDetails WHERE ReferenceNo = @ref1)
             + (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber = @ref1)
             + (SELECT COUNT(*) FROM dbo.TicketDetails WHERE ReferenceNumber = @ref1)
             + (SELECT COUNT(*) FROM dbo.ClientLedger WHERE ReferenceNumber = @ref1)
             + (SELECT COUNT(*) FROM dbo.BankStatementRecon WHERE SourceRef = @ref1 OR ReferenceNo = @ref1);
SELECT @hdrCnt1 = COUNT(*) FROM dbo.BankReconHeader WHERE BranchCode = '888' AND AccountCode = @bank AND PeriodEnd = EOMONTH(@today);
SELECT @sig = CONCAT(
    (SELECT STRING_AGG(CONCAT(t.CustomerKey, ':', t.InvoiceNo, ':', t.AmountPaid, ':', t.Balance, ':', t.PayStatus, ':', ISNULL(t.EWTAmount, 0), ':', ISNULL(t.DiscountAmount, 0), ':', ISNULL(t.OffsetAmount, 0), ':', ISNULL(t.AdvancePayment, 0)), ',')
            WITHIN GROUP (ORDER BY t.CustomerKey, t.InvoiceNo)
     FROM dbo.TransactionChargeSales t WHERE EXISTS (SELECT 1 FROM @fx f WHERE f.c = t.CustomerKey AND f.i = t.InvoiceNo AND f.p = t.ReferenceNo)), '|',
    (SELECT STRING_AGG(CONCAT(a.AccountKey, ':', a.AccountBalance), ',') WITHIN GROUP (ORDER BY a.AccountKey) FROM dbo.ClientAccounts a WHERE a.AccountKey IN (SELECT c FROM @fx)), '|',
    (SELECT STRING_AGG(CONCAT(m.AccountCode, ':', CAST(m.IsActive AS INT)), ',') WITHIN GROUP (ORDER BY m.Seq) FROM dbo.JournalEntryMapping m WHERE m.Origin = 'OR' AND m.Mnemonic = 'OR-OTHERCOLL'));
INSERT @r VALUES ('leftovers',
    CASE WHEN @rows = 0 AND @tc = 0 AND ISNULL(@sig, '') = ISNULL(@sig0, '') AND ISNULL(@hdrCnt1, 0) = ISNULL(@hdrCnt0, 0) THEN 'PASS' ELSE 'FAIL' END,
    CONCAT(@rows, ' test rows left under 99921 / TEST104; open transactions ', @tc, '; fixture rows + mapping ', CASE WHEN ISNULL(@sig, '') = ISNULL(@sig0, '') THEN 'unchanged' ELSE 'CHANGED' END,
           '; recon headers of this month ', @hdrCnt0, ' -> ', @hdrCnt1));

SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
SELECT DB_NAME() AS DatabaseName,
       SUM(CASE WHEN Result = 'PASS' THEN 1 ELSE 0 END) AS Pass,
       SUM(CASE WHEN Result = 'BUG SHOWN' THEN 1 ELSE 0 END) AS BugShown,
       SUM(CASE WHEN Result = 'PRE-EXISTING' THEN 1 ELSE 0 END) AS PreExisting,
       SUM(CASE WHEN Result = 'SKIP' THEN 1 ELSE 0 END) AS Skip,
       SUM(CASE WHEN Result IN ('FAIL', 'ERROR', 'UNEXPECTED') THEN 1 ELSE 0 END) AS Fail
FROM @r;
