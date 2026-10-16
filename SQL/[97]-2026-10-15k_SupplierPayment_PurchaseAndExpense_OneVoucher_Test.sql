/* ================================================================
   [97] TEST SCRIPT - Supplier Payment (cash / check): purchases and expenses on one voucher
   ================================================================
   Run in SSMS on DEV or STAGING AFTER [97] is applied. Every test runs inside BEGIN TRAN ... ROLLBACK, so nothing is
   left behind; the last result sets show PASS / BUG SHOWN / SKIP / FAIL per test. Do NOT run on PRODUCTION.
   "BUG SHOWN" = the _OLD_10152026220000 backup of sp_CancelledChequesCS reproduces what [97] closes.
   T08 / T08c use voucher ids 99985 / 99986, NOT their reference 99976, as real vouchers do (2026-10-16): with
   reference = voucher id the invoice reversal also mirrors the manual line's CASH ADVANCE ticket (keyed by the
   reference), so the first version of this test showed a double reversal that real numbering never produces.

   Fixtures picked automatically (first result set shows them):
     - a supplier (SupplierID = SupplierKey) with BOTH an open purchase invoice and an open expense invoice;
     - its newest open purchase (APAccounts UNPAID, nothing paid, Balance = ActualCost >= 1,000, one row per SequenceNo,
       its shipment in POSUMMARY);
     - its newest open expense (ExpenseSummary not paid / void / cancelled, Balance = Amount, no EWT / discount /
       offset, one row per invoice + batch; SINGLE with a payable account preferred);
     - bank account 101020101 and a non-bank cash-advance account for the manual line.
   Optional: @PickSupplier / @PickPurchaseSeq / @PickExpenseRef force one record. Missing fixture -> SKIP.
   Each payment pays 1,000.00 of the purchase and 500.00 of the expense (less when the balance is lower).
   Test reference numbers 99971 - 99979 and voucher ids 99985 / 99986 must be unused (checked first).
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT OFF;   -- the tests catch the refusals themselves

DECLARE @PickSupplier VARCHAR(10) = NULL, @PickPurchaseSeq DECIMAL(18,0) = NULL, @PickExpenseRef VARCHAR(10) = NULL;

DECLARE @r TABLE (Seq INT IDENTITY, Test VARCHAR(120), Result VARCHAR(12), Detail VARCHAR(900));
DECLARE @err INT, @n INT, @n2 INT, @n3 INT, @tc INT, @msg NVARCHAR(600), @d1 DECIMAL(18,2), @d2 DECIMAL(18,2), @d3 DECIMAL(18,2), @d4 DECIMAL(18,2),
        @s VARCHAR(400), @s2 VARCHAR(400), @dt1 DATE, @dt2 DATE, @dt3 DATE, @dt4 DATE;
DECLARE @bank VARCHAR(20) = '101020101', @today DATE = CAST(GETDATE() AS DATE), @user VARCHAR(30) = 'TEST97', @branch VARCHAR(5) = '888';
DECLARE @caAcct VARCHAR(20) = (SELECT TOP 1 AccountCode FROM CashAdvanceAllowedAccounts WHERE AccountCode NOT LIKE '10102%' AND LEN(AccountCode) >= 5 ORDER BY AccountCode);

------------------------------------------------------------------
-- 0. install check
------------------------------------------------------------------
IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2')) NOT LIKE '%@SkipVoucherWrap%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.splist_Accounts')) NOT LIKE '%[[]97]%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostSupplierPaymentWithManualLines')) NOT LIKE '%@PurchaseLines%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS')) NOT LIKE '%''MIXED''%'
BEGIN INSERT @r VALUES ('I0 install check', 'FAIL', '[97] is not installed'); SELECT * FROM @r; RETURN; END
IF OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2_OLD_10152026220000', 'P') IS NULL OR OBJECT_ID('dbo.splist_Accounts_OLD_10152026220000', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_PostSupplierPaymentWithManualLines_OLD_10152026220000', 'P') IS NULL OR OBJECT_ID('dbo.sp_CancelledChequesCS_OLD_10152026220000', 'P') IS NULL
BEGIN INSERT @r VALUES ('I0 install check', 'FAIL', '[97] backups _OLD_10152026220000 missing; the old = new / BUG SHOWN tests need them'); SELECT * FROM @r; RETURN; END
INSERT @r VALUES ('I0 install check', 'PASS', '4 objects carry [97], 4 backups _OLD_10152026220000 present');

------------------------------------------------------------------
-- 1. fixtures and pre-checks
------------------------------------------------------------------
IF (SELECT COUNT(*) FROM TransactionPaymentAP WHERE ReferenceNumber BETWEEN 99971 AND 99979)
 + (SELECT COUNT(*) FROM APPaymentDetails WHERE ReferenceNumber BETWEEN '99971' AND '99979' OR VoucherID BETWEEN '99971' AND '99989')
 + (SELECT COUNT(*) FROM TicketMaster WHERE ReferenceNumber IN ('99971','99972','99973','99974','99975','99976','99977','99978','99979'))
 + (SELECT COUNT(*) FROM SupplierLedger WHERE ReferenceNumber IN ('99971','99972','99973','99974','99975','99976','99977','99978','99979'))
 + (SELECT COUNT(*) FROM CheckVoucher WHERE ReferenceNumber IN ('99971','99972','99973','99974','99975','99976','99977','99978','99979') OR VoucherID BETWEEN 99971 AND 99989)
 + (SELECT COUNT(*) FROM CashVoucher WHERE ReferenceNumber IN ('99971','99972','99973','99974','99975','99976','99977','99978','99979') OR VoucherID BETWEEN 99971 AND 99989)
 + (SELECT COUNT(*) FROM BankStatementRecon WHERE ReferenceNo IN ('99971','99972','99973','99974','99975','99976','99977','99978','99979','99985','99986') OR SourceRef IN ('99971','99972','99973','99974','99975','99976','99977','99978','99979'))
 + (SELECT COUNT(*) FROM CashAdvance WHERE ReferenceNo IN ('99971','99972','99973','99974','99975','99976','99977','99978','99979') OR VoucherID IN ('99971','99972','99973','99974','99975','99976','99977','99978','99979','99985','99986'))
 + (SELECT COUNT(*) FROM PaymentReversalAudit WHERE ReferenceNumber IN ('99971','99972','99973','99974','99975','99976','99977','99978','99979')) > 0
BEGIN INSERT @r VALUES ('fixtures', 'ERROR', 'test references 99971 - 99979 are in use here'); SELECT * FROM @r; RETURN; END
IF EXISTS (SELECT 1 FROM GLPeriodLock WHERE LockedThroughDate >= @today)
BEGIN INSERT @r VALUES ('fixtures', 'ERROR', 'the GL is closed through today; the postings would be refused (59900)'); SELECT * FROM @r; RETURN; END
IF EXISTS (SELECT 1 FROM BankReconHeader WHERE Status = 'LOCKED' AND AccountCode = @bank AND PeriodEnd >= EOMONTH(@today))
BEGIN INSERT @r VALUES ('fixtures', 'ERROR', 'the current month of 101020101 is locked in the bank recon; the OC items would be refused (93022)'); SELECT * FROM @r; RETURN; END
IF @caAcct IS NULL OR NOT EXISTS (SELECT 1 FROM CashAdvanceAllowedAccounts WHERE AccountCode = @bank)
BEGIN INSERT @r VALUES ('fixtures', 'ERROR', '101020101 or a non-bank account is not on the cash-advance allowed list (manual-line tests)'); SELECT * FROM @r; RETURN; END

DECLARE @sup VARCHAR(10), @supName VARCHAR(150);
SELECT TOP (1) @sup = s.SupplierID, @supName = s.SupplierName
FROM Supplier s
WHERE s.SupplierID = s.SupplierKey AND (@PickSupplier IS NULL OR s.SupplierID = @PickSupplier)
  AND EXISTS (SELECT 1 FROM APAccounts a JOIN POSUMMARY b ON b.ShipmentNo = a.ShipmentNo
              WHERE a.SupplierID = s.SupplierID AND a.PayStatus = 'UNPAID' AND a.Balance >= 1000 AND a.Balance = a.ActualCost AND ISNULL(a.AmountPaid, 0) = 0
                AND (SELECT COUNT(*) FROM APAccounts x WHERE x.SupplierID = a.SupplierID AND x.SequenceNo = a.SequenceNo) = 1
                AND (SELECT COUNT(*) FROM POSUMMARY y WHERE y.ShipmentNo = a.ShipmentNo) = 1)
  AND EXISTS (SELECT 1 FROM ExpenseSummary es
              WHERE es.SupplierID = s.SupplierID AND es.Status NOT IN ('PAID','VOID','CANCELLED','FOR APPROVAL','FULLYPAID')
                AND es.Balance = es.Amount AND es.Balance > 0 AND ISNULL(es.AmountPaid, 0) = 0
                AND ISNULL(es.EWTAmount, 0) = 0 AND ISNULL(es.DiscountAmount, 0) = 0 AND ISNULL(es.OffsetAmount, 0) = 0
                AND (ISNULL(es.PostingMode, 'BATCH') <> 'SINGLE' OR es.PayableAccountCode IS NOT NULL)
                AND (SELECT COUNT(*) FROM ExpenseSummary z WHERE z.SupplierID = es.SupplierID AND z.BatchReferenceID = es.BatchReferenceID AND z.InvoiceNo = es.InvoiceNo) = 1)
ORDER BY s.SupplierID;

DECLARE @pseq DECIMAL(18,0), @pseqs VARCHAR(10), @pinv VARCHAR(80), @pdate DATE, @pcost DECIMAL(12,2), @pbal DECIMAL(12,2), @pstat VARCHAR(20), @pbranch CHAR(3);
SELECT TOP (1) @pseq = a.SequenceNo, @pseqs = CAST(a.SequenceNo AS VARCHAR(10)), @pinv = a.InvoiceNo, @pdate = a.InvoiceDate, @pcost = a.ActualCost,
       @pbal = a.Balance, @pstat = a.PayStatus, @pbranch = b.BranchCode
FROM APAccounts a JOIN POSUMMARY b ON b.ShipmentNo = a.ShipmentNo
WHERE a.SupplierID = @sup AND (@PickPurchaseSeq IS NULL OR a.SequenceNo = @PickPurchaseSeq)
  AND a.PayStatus = 'UNPAID' AND a.Balance >= 1000 AND a.Balance = a.ActualCost AND ISNULL(a.AmountPaid, 0) = 0
  AND (SELECT COUNT(*) FROM APAccounts x WHERE x.SupplierID = a.SupplierID AND x.SequenceNo = a.SequenceNo) = 1
  AND (SELECT COUNT(*) FROM POSUMMARY y WHERE y.ShipmentNo = a.ShipmentNo) = 1
ORDER BY a.SequenceNo DESC;

DECLARE @eref VARCHAR(10), @einv VARCHAR(150), @ebatch BIGINT, @eamt DECIMAL(18,2), @ebal DECIMAL(18,2), @edate DATE, @ebranch CHAR(3), @estat VARCHAR(50), @emode VARCHAR(50);
SELECT TOP (1) @eref = es.ReferenceNumber, @einv = es.InvoiceNo, @ebatch = es.BatchReferenceID, @eamt = es.Amount, @ebal = es.Balance, @edate = es.ExpenseDate,
       @estat = es.Status, @emode = ISNULL(es.PostingMode, 'BATCH'),
       @ebranch = (SELECT TOP 1 m.BranchCode FROM ExpenseMaster m WHERE m.SupplierID = es.SupplierID AND m.InvoiceNo = es.InvoiceNo AND m.BatchReferenceID = es.BatchReferenceID ORDER BY m.TRN_SEQ_NO)
FROM ExpenseSummary es
WHERE es.SupplierID = @sup AND (@PickExpenseRef IS NULL OR es.ReferenceNumber = @PickExpenseRef)
  AND es.Status NOT IN ('PAID','VOID','CANCELLED','FOR APPROVAL','FULLYPAID')
  AND es.Balance = es.Amount AND es.Balance > 0 AND ISNULL(es.AmountPaid, 0) = 0
  AND ISNULL(es.EWTAmount, 0) = 0 AND ISNULL(es.DiscountAmount, 0) = 0 AND ISNULL(es.OffsetAmount, 0) = 0
  AND (ISNULL(es.PostingMode, 'BATCH') <> 'SINGLE' OR es.PayableAccountCode IS NOT NULL)
  AND (SELECT COUNT(*) FROM ExpenseSummary z WHERE z.SupplierID = es.SupplierID AND z.BatchReferenceID = es.BatchReferenceID AND z.InvoiceNo = es.InvoiceNo) = 1
  AND EXISTS (SELECT 1 FROM ExpenseMaster m WHERE m.SupplierID = es.SupplierID AND m.InvoiceNo = es.InvoiceNo AND m.BatchReferenceID = es.BatchReferenceID)
ORDER BY CASE WHEN es.PostingMode = 'SINGLE' THEN 0 ELSE 1 END, es.BatchReferenceID DESC;

DECLARE @pPay DECIMAL(18,2) = CASE WHEN @pbal >= 1000 THEN 1000.00 ELSE @pbal END,
        @ePay DECIMAL(18,2) = CASE WHEN @ebal >= 500 THEN 500.00 ELSE @ebal END;
DECLARE @tot DECIMAL(18,2) = @pPay + @ePay;
DECLARE @acct0 DECIMAL(18,2) = (SELECT AccountBalance FROM SupplierAccounts WHERE SupplierID = @sup);

SELECT 'fixtures' AS what, @sup AS supplier, @supName AS supplier_name, @pseq AS purchase_seq, @pinv AS purchase_invoice, @pbal AS purchase_balance, @pPay AS purchase_paid,
       @eref AS expense_ref, @einv AS expense_invoice, @ebatch AS expense_batch, @emode AS expense_mode, @ebal AS expense_balance, @ePay AS expense_paid,
       @bank AS bank, @caAcct AS manual_line_acct, @acct0 AS supplier_account;

IF @sup IS NULL OR @pseq IS NULL OR @eref IS NULL
BEGIN
    INSERT @r VALUES ('fixtures', 'SKIP', 'no supplier here with both an open purchase (Balance >= 1,000, nothing paid) and an open expense (nothing paid, no EWT); every test skipped');
    GOTO Report;
END

DECLARE @PLn dbo.AP_PaymentLineTVP, @ILn dbo.AP_PaymentLineTVP, @PXn dbo.AP_PaymentLineExtraTVP, @IXn dbo.AP_PaymentLineExtraTVP, @MLn dbo.ManualVoucherDebitLineTVP;
DECLARE @fp TABLE (Cs INT, Run VARCHAR(3), Item VARCHAR(10), Val VARCHAR(MAX));
DECLARE @c INT, @run VARCHAR(3), @ref VARCHAR(10), @name VARCHAR(80), @mixNets INT, @mixNetDetail VARCHAR(400);

------------------------------------------------------------------
-- T01-T04 one-kind vouchers: OLD and NEW write the same rows
--   T01 purchase through V2, T02 expense through V2, T03 expense + manual line through the wrapper,
--   T04 purchase through the wrapper. Footprint = 12 items (payment row, legs, tickets, ledger, both invoices,
--   expense lines, bank item, voucher header, cash advance, supplier account vs ledger).
------------------------------------------------------------------
SET @c = 1;
WHILE @c <= 4
BEGIN
    SET @ref = CASE @c WHEN 1 THEN '99971' WHEN 2 THEN '99972' WHEN 3 THEN '99973' ELSE '99974' END;
    SET @name = CASE @c WHEN 1 THEN 'T01 one-kind purchase via V2 old = new'
                        WHEN 2 THEN 'T02 one-kind expense via V2 old = new'
                        WHEN 3 THEN 'T03 one-kind expense + manual line via wrapper old = new'
                        ELSE        'T04 one-kind purchase via wrapper old = new' END;
    SET @run = 'old';
    WHILE @run IS NOT NULL
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            DELETE @ILn; DELETE @MLn;
            IF @c IN (1, 4)
                INSERT INTO @ILn (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
                VALUES (@pbranch, @pinv, @pdate, @pseqs, 0, @pcost, @pPay, 0, 0, 0, 'TEST97', 0, NULL);
            ELSE
                INSERT INTO @ILn (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
                VALUES (@ebranch, @einv, @edate, @eref, @ebatch, @eamt, @ePay, 0, 0, 0, 'TEST97', 0, NULL);
            IF @c = 3 INSERT INTO @MLn (BranchCode, AccountCode, Amount, Particulars) VALUES (@branch, @caAcct, 200.00, 'TEST97 manual');

            IF @c = 1 AND @run = 'old'
                EXEC dbo.sp_AddPaymentSupplierCompound_V2_OLD_10152026220000 @parmrefno = @ref, @parmvoucherid = @ref, @parmsupplierid = @sup, @parmsuppliername = @supName,
                     @parmcheckamount = @pPay, @parmcheckcoding = '', @parmcheckno = '', @parmcontrolno = 'TEST97', @parmcheckdate = @today, @parmcheckremarks = 'TEST97',
                     @parmpreparedby = @user, @parmglcode = @bank, @parmpaymethod = 'PURCHASE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @Lines = @ILn, @parmPayingBranch = @branch, @LineExtras = @IXn;
            ELSE IF @c = 1
                EXEC dbo.sp_AddPaymentSupplierCompound_V2 @parmrefno = @ref, @parmvoucherid = @ref, @parmsupplierid = @sup, @parmsuppliername = @supName,
                     @parmcheckamount = @pPay, @parmcheckcoding = '', @parmcheckno = '', @parmcontrolno = 'TEST97', @parmcheckdate = @today, @parmcheckremarks = 'TEST97',
                     @parmpreparedby = @user, @parmglcode = @bank, @parmpaymethod = 'PURCHASE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @Lines = @ILn, @parmPayingBranch = @branch, @LineExtras = @IXn;
            ELSE IF @c = 2 AND @run = 'old'
                EXEC dbo.sp_AddPaymentSupplierCompound_V2_OLD_10152026220000 @parmrefno = @ref, @parmvoucherid = @ref, @parmsupplierid = @sup, @parmsuppliername = @supName,
                     @parmcheckamount = @ePay, @parmcheckcoding = '', @parmcheckno = '', @parmcontrolno = 'TEST97', @parmcheckdate = @today, @parmcheckremarks = 'TEST97',
                     @parmpreparedby = @user, @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @Lines = @ILn, @parmPayingBranch = @branch, @LineExtras = @IXn;
            ELSE IF @c = 2
                EXEC dbo.sp_AddPaymentSupplierCompound_V2 @parmrefno = @ref, @parmvoucherid = @ref, @parmsupplierid = @sup, @parmsuppliername = @supName,
                     @parmcheckamount = @ePay, @parmcheckcoding = '', @parmcheckno = '', @parmcontrolno = 'TEST97', @parmcheckdate = @today, @parmcheckremarks = 'TEST97',
                     @parmpreparedby = @user, @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @Lines = @ILn, @parmPayingBranch = @branch, @LineExtras = @IXn;
            ELSE IF @c = 3 AND @run = 'old'
                EXEC dbo.sp_PostSupplierPaymentWithManualLines_OLD_10152026220000 @parmrefno = @ref, @parmvoucherid = @ref, @parmsupplierid = @sup, @parmsuppliername = @supName,
                     @parmcheckcoding = '', @parmcheckno = NULL, @parmcheckdate = @today, @parmcontrolno = 'TEST97', @parmcheckremarks = 'TEST97', @parmpreparedby = @user,
                     @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @parmPayingBranch = @branch,
                     @InvoiceLegAmount = @ePay, @InvoiceLines = @ILn, @ManualLines = @MLn, @InvoiceLineExtras = @IXn;
            ELSE IF @c = 3
                EXEC dbo.sp_PostSupplierPaymentWithManualLines @parmrefno = @ref, @parmvoucherid = @ref, @parmsupplierid = @sup, @parmsuppliername = @supName,
                     @parmcheckcoding = '', @parmcheckno = NULL, @parmcheckdate = @today, @parmcontrolno = 'TEST97', @parmcheckremarks = 'TEST97', @parmpreparedby = @user,
                     @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @parmPayingBranch = @branch,
                     @InvoiceLegAmount = @ePay, @InvoiceLines = @ILn, @ManualLines = @MLn, @InvoiceLineExtras = @IXn;
            ELSE IF @run = 'old'
                EXEC dbo.sp_PostSupplierPaymentWithManualLines_OLD_10152026220000 @parmrefno = @ref, @parmvoucherid = @ref, @parmsupplierid = @sup, @parmsuppliername = @supName,
                     @parmcheckcoding = 'T97CV74', @parmcheckno = 'T97C74', @parmcheckdate = @today, @parmcontrolno = NULL, @parmcheckremarks = 'TEST97', @parmpreparedby = @user,
                     @parmglcode = @bank, @parmpaymethod = 'PURCHASE', @parmforliquidation = 0, @parmvouchertype = 'CHECK', @parmPayingBranch = @branch,
                     @InvoiceLegAmount = @pPay, @InvoiceLines = @ILn, @ManualLines = @MLn, @InvoiceLineExtras = @IXn;
            ELSE
                EXEC dbo.sp_PostSupplierPaymentWithManualLines @parmrefno = @ref, @parmvoucherid = @ref, @parmsupplierid = @sup, @parmsuppliername = @supName,
                     @parmcheckcoding = 'T97CV74', @parmcheckno = 'T97C74', @parmcheckdate = @today, @parmcontrolno = NULL, @parmcheckremarks = 'TEST97', @parmpreparedby = @user,
                     @parmglcode = @bank, @parmpaymethod = 'PURCHASE', @parmforliquidation = 0, @parmvouchertype = 'CHECK', @parmPayingBranch = @branch,
                     @InvoiceLegAmount = @pPay, @InvoiceLines = @ILn, @ManualLines = @MLn, @InvoiceLineExtras = @IXn;

            INSERT @fp SELECT @c, @run, 'TPAP', CONCAT(COUNT(*), '|', SUM(Amount), '|', MAX(VoucherType), '|', CONVERT(VARCHAR(10), MAX(DatePaid), 120), '|', SUM(CAST(ErrorCorrect AS INT)))
                       FROM TransactionPaymentAP WHERE ReferenceNumber = CAST(@ref AS INT);
            INSERT @fp SELECT @c, @run, 'APD', CONCAT(COUNT(*), '|', SUM(Amount), '|', STRING_AGG(CONCAT(BranchCode, ':', InvoiceNo, ':', Amount, ':', PaymentType, ':', PaymentMethod, ':', VoucherType, ':', DebitGLCode, ':', CreditGLCode, ':', SequenceReferenceNumber), ',')
                                                     WITHIN GROUP (ORDER BY PaymentMethod, PaymentType, InvoiceNo, Amount))
                       FROM APPaymentDetails WHERE ReferenceNumber = @ref AND VoucherID = @ref;
            INSERT @fp SELECT @c, @run, 'TKD', CONCAT(COUNT(*), '|', SUM(td.Debit), '|', SUM(td.Credit), '|', STRING_AGG(CONCAT(tm.Mnemonic, ':', td.BranchCode, ':', td.AccountCode, ':', td.Debit, ':', td.Credit, ':', CONVERT(VARCHAR(10), td.TicketDate, 120)), ',')
                                                     WITHIN GROUP (ORDER BY tm.Mnemonic, td.BranchCode, td.AccountCode, td.Debit, td.Credit))
                       FROM TicketMaster tm JOIN TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode WHERE tm.ReferenceNumber = @ref;
            INSERT @fp SELECT @c, @run, 'SL', CONCAT(COUNT(*), '|', STRING_AGG(CONCAT(TransCode, ':', InvoiceNo, ':', Debit, ':', Credit, ':', PaymentType, ':', ErrorCorrectTag), ',') WITHIN GROUP (ORDER BY TransCode, InvoiceNo, Debit, Credit))
                       FROM SupplierLedger WHERE SupplierID = @sup AND ReferenceNumber = @ref;
            INSERT @fp SELECT @c, @run, 'AP', CONCAT(Balance, '|', PayStatus, '|', ISNULL(AmountPaid, 0)) FROM APAccounts WHERE SupplierID = @sup AND SequenceNo = @pseq;
            INSERT @fp SELECT @c, @run, 'ES', CONCAT(Balance, '|', ISNULL(AmountPaid, 0), '|', Status, '|', ISNULL(EWTWithheld, 0)) FROM ExpenseSummary WHERE SupplierID = @sup AND BatchReferenceID = @ebatch AND InvoiceNo = @einv;
            INSERT @fp SELECT @c, @run, 'EM', STRING_AGG(CONCAT(BranchCode, ':', Balance, ':', AmountPaid, ':', Status), ',') WITHIN GROUP (ORDER BY BranchCode, TRN_SEQ_NO)
                       FROM ExpenseMaster WHERE SupplierID = @sup AND BatchReferenceID = @ebatch AND InvoiceNo = @einv;
            INSERT @fp SELECT @c, @run, 'OC', CONCAT(COUNT(*), '|', STRING_AGG(CONCAT(ItemType, ':', BranchCode, ':', AccountCode, ':', Amount, ':', CONVERT(VARCHAR(10), PeriodEnd, 120), ':', CONVERT(VARCHAR(10), ItemDate, 120), ':', SourceModule, ':', IsResolved), ',')
                                                    WITHIN GROUP (ORDER BY ItemType, AccountCode, Amount))
                       FROM BankStatementRecon WHERE ReferenceNo = @ref OR SourceRef = @ref;
            INSERT @fp SELECT @c, @run, 'HDR', CONCAT((SELECT CONCAT(COUNT(*), ':', SUM(Amount), ':', MAX(CheckNo), ':', CONVERT(VARCHAR(10), MAX(CheckDate), 120), ':', MAX(CreditGLCode), ':', MAX(CVNo)) FROM CheckVoucher WHERE ReferenceNumber = @ref),
                                                  '|', (SELECT CONCAT(COUNT(*), ':', SUM(Amount), ':', MAX(ControlNo), ':', CONVERT(VARCHAR(10), MAX(DateReceived), 120), ':', MAX(CreditGLCode)) FROM CashVoucher WHERE ReferenceNumber = @ref));
            INSERT @fp SELECT @c, @run, 'CA', CONCAT(COUNT(*), '|', SUM(Amount), '|', STRING_AGG(CONCAT(BranchCode, ':', DebitAccountCode, ':', CreditAccountCode, ':', Amount, ':', Status), ',') WITHIN GROUP (ORDER BY BranchCode, DebitAccountCode))
                       FROM CashAdvance WHERE ReferenceNo = @ref;
            INSERT @fp SELECT @c, @run, 'ACCT', CONCAT(CAST(sa.AccountBalance AS DECIMAL(18,2)), '|', (SELECT CAST(SUM(ISNULL(l.Credit, 0) - ISNULL(l.Debit, 0)) AS DECIMAL(18,2)) FROM SupplierLedger l WHERE l.SupplierID = @sup))
                       FROM SupplierAccounts sa WHERE sa.SupplierID = @sup;
            INSERT @fp SELECT @c, @run, 'BANKCR', CONCAT(CAST(SUM(ISNULL(td.Credit, 0) - ISNULL(td.Debit, 0)) AS DECIMAL(18,2)), '')
                       FROM TicketDetails td WHERE td.AccountCode = @bank AND EXISTS (SELECT 1 FROM TicketMaster tm WHERE tm.TicketNumber = td.TicketNumber AND tm.BranchCode = td.BranchCode AND tm.ReferenceNumber = @ref);
        END TRY BEGIN CATCH INSERT @r VALUES (CONCAT(LEFT(@name, 3), ' ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
    END
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE Cs = @c AND Run = 'old' EXCEPT SELECT Item, Val FROM @fp WHERE Cs = @c AND Run = 'new') x;
    SELECT @n2 = COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE Cs = @c AND Run = 'new' EXCEPT SELECT Item, Val FROM @fp WHERE Cs = @c AND Run = 'old') x;
    SELECT @n3 = COUNT(*) FROM @fp WHERE Cs = @c AND Run = 'new';
    INSERT @r VALUES (@name, CASE WHEN @n = 0 AND @n2 = 0 AND @n3 = 12 AND (SELECT COUNT(*) FROM @fp WHERE Cs = @c AND Run = 'old') = 12
                                       AND (SELECT Val FROM @fp WHERE Cs = @c AND Run = 'new' AND Item = 'APD') NOT LIKE '0|%' THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('ref ', @ref, ': ', @n + @n2, ' of ', @n3, ' footprint rows differ; legs ', LEFT((SELECT Val FROM @fp WHERE Cs = @c AND Run = 'new' AND Item = 'APD'), 220),
                             '; header ', (SELECT Val FROM @fp WHERE Cs = @c AND Run = 'new' AND Item = 'HDR'), '; bank credit ', (SELECT Val FROM @fp WHERE Cs = @c AND Run = 'new' AND Item = 'BANKCR'),
                             '; OC ', LEFT((SELECT Val FROM @fp WHERE Cs = @c AND Run = 'new' AND Item = 'OC'), 120)));
    SET @c += 1;
END

------------------------------------------------------------------
-- T05 MIXED cheque voucher (purchase + expense): ONE header / ONE TransactionPaymentAP / ONE open OC = the total,
--     both invoices settled, legs carry their own PaymentMethod, tickets balanced, bank credit = total, account = ledger.
-- T06 then reversed through the screen's entry point (sp_ReverseCombinedSupplierVoucher) sending 'PURCHASE':
--     both invoices restored (detected MIXED), audit MIXED, OC voided, every account nets to 0, account back.
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    DELETE @PLn; DELETE @ILn; DELETE @MLn;
    INSERT INTO @PLn (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
    VALUES (@pbranch, @pinv, @pdate, @pseqs, 0, @pcost, @pPay, 0, 0, 0, 'TEST97', 0, NULL);
    INSERT INTO @ILn (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
    VALUES (@ebranch, @einv, @edate, @eref, @ebatch, @eamt, @ePay, 0, 0, 0, 'TEST97', 0, NULL);
    EXEC dbo.sp_PostSupplierPaymentWithManualLines @parmrefno = '99975', @parmvoucherid = '99975', @parmsupplierid = @sup, @parmsuppliername = @supName,
         @parmcheckcoding = 'T97CV75', @parmcheckno = 'T97C75', @parmcheckdate = @today, @parmcontrolno = NULL, @parmcheckremarks = 'TEST97', @parmpreparedby = @user,
         @parmglcode = @bank, @parmpaymethod = 'MIXED', @parmforliquidation = 0, @parmvouchertype = 'CHECK', @parmPayingBranch = @branch,
         @InvoiceLegAmount = @tot, @InvoiceLines = @ILn, @ManualLines = @MLn, @InvoiceLineExtras = @IXn, @PurchaseLines = @PLn, @PurchaseLineExtras = @PXn;

    SELECT @n = COUNT(*), @d1 = SUM(Amount) FROM CheckVoucher WHERE ReferenceNumber = '99975' AND VoucherID = 99975;
    SELECT @n2 = COUNT(*), @d2 = SUM(Amount) FROM TransactionPaymentAP WHERE ReferenceNumber = 99975;
    SELECT @n3 = COUNT(*), @d3 = SUM(Amount) FROM BankStatementRecon WHERE ReferenceNo = '99975' AND SourceRef = '99975' AND ItemType = 'OC' AND IsResolved = 0;
    SELECT @s = STRING_AGG(CONCAT(BranchCode, ':', ItemType, ':', Amount, ':', SourceModule), ',') FROM BankStatementRecon WHERE ReferenceNo = '99975' OR SourceRef = '99975';
    INSERT @r VALUES ('T05a mixed cheque: one header / payment row / OC = total', CASE WHEN @n = 1 AND @d1 = @tot AND @n2 = 1 AND @d2 = @tot AND @n3 = 1 AND @d3 = @tot THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('purchase ', @pPay, ' + expense ', @ePay, ' = ', @tot, ': headers ', @n, ' (', @d1, '), payment rows ', @n2, ' (', @d2, '), open OC ', @n3, ' (', @d3, ') [', @s, ']'));

    SELECT @d1 = SUM(CASE WHEN PaymentMethod = 'PURCHASE' AND PaymentType = 'INVOICE PAYMENT' THEN Amount ELSE 0 END),
           @d2 = SUM(CASE WHEN PaymentMethod = 'EXPENSE' AND PaymentType = 'EXPENSE PAYMENT' THEN Amount ELSE 0 END),
           @n = SUM(CASE WHEN PaymentMethod NOT IN ('PURCHASE', 'EXPENSE') THEN 1 ELSE 0 END)
    FROM APPaymentDetails WHERE ReferenceNumber = '99975' AND VoucherID = '99975' AND SupplierID = @sup;
    SELECT @d3 = Balance, @s = PayStatus FROM APAccounts WHERE SupplierID = @sup AND SequenceNo = @pseq;
    SELECT @d4 = Balance, @s2 = Status FROM ExpenseSummary WHERE SupplierID = @sup AND BatchReferenceID = @ebatch AND InvoiceNo = @einv;
    INSERT @r VALUES ('T05b mixed cheque: both invoices settled, legs by kind', CASE WHEN @d1 = @pPay AND @d2 = @ePay AND @n = 0 AND @d3 = @pbal - @pPay AND @d4 = @ebal - @ePay THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('legs PURCHASE ', @d1, ' / EXPENSE ', @d2, ' (other methods ', @n, '); purchase ', @pbal, ' -> ', @d3, ' ', @s, '; expense ', @ebal, ' -> ', @d4, ' ', @s2));

    SELECT @n = COUNT(*) FROM (SELECT td.TicketNumber, td.BranchCode FROM TicketDetails td
                               WHERE EXISTS (SELECT 1 FROM TicketMaster tm WHERE tm.TicketNumber = td.TicketNumber AND tm.BranchCode = td.BranchCode AND tm.ReferenceNumber = '99975')
                               GROUP BY td.TicketNumber, td.BranchCode HAVING ABS(SUM(ISNULL(td.Debit, 0)) - SUM(ISNULL(td.Credit, 0))) > 0.004) x;
    SELECT @n2 = COUNT(*), @s = STRING_AGG(Mnemonic, ',') WITHIN GROUP (ORDER BY Mnemonic) FROM TicketMaster WHERE ReferenceNumber = '99975';
    SELECT @d1 = SUM(ISNULL(td.Credit, 0) - ISNULL(td.Debit, 0)) FROM TicketDetails td
    WHERE td.AccountCode = @bank AND EXISTS (SELECT 1 FROM TicketMaster tm WHERE tm.TicketNumber = td.TicketNumber AND tm.BranchCode = td.BranchCode AND tm.ReferenceNumber = '99975');
    SELECT @d2 = AccountBalance FROM SupplierAccounts WHERE SupplierID = @sup;
    SELECT @d3 = SUM(ISNULL(Credit, 0) - ISNULL(Debit, 0)) FROM SupplierLedger WHERE SupplierID = @sup;
    SELECT @d4 = SUM(ISNULL(Debit, 0) - ISNULL(Credit, 0)) FROM SupplierLedger WHERE SupplierID = @sup AND ReferenceNumber = '99975';
    INSERT @r VALUES ('T05c mixed cheque: tickets balanced, bank credit = total, account = ledger', CASE WHEN @n = 0 AND @n2 >= 2 AND @d1 = @tot AND @d2 = @d3 AND @d2 = @acct0 - @tot AND @d4 = @tot THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT(@n2, ' tickets (', @s, '), unbalanced ', @n, '; bank credit ', @d1, '; ledger debits ', @d4, '; account ', @acct0, ' -> ', @d2, ' = ledger ', @d3));

    -- T06 reversal (screen entry point, the old exe sends one kind)
    EXEC dbo.sp_ReverseCombinedSupplierVoucher @parmsupplierid = @sup, @parmreferenceno = '99975', @parmvoucherid = '99975', @parmvouchertype = 'PURCHASE',
         @parmcheckno = 'T97C75', @parmglcode = @bank, @parmbranch = @branch, @parmreason = 'TEST97 T06 (rolled back)', @parmuser = @user;
    SELECT @d3 = Balance, @s = PayStatus FROM APAccounts WHERE SupplierID = @sup AND SequenceNo = @pseq;
    SELECT @d4 = Balance, @d1 = ISNULL(AmountPaid, 0), @s2 = Status FROM ExpenseSummary WHERE SupplierID = @sup AND BatchReferenceID = @ebatch AND InvoiceNo = @einv;
    INSERT @r VALUES ('T06a reversal sent PURCHASE restores BOTH invoices', CASE WHEN @d3 = @pbal AND @s = @pstat AND @d4 = @ebal AND @d1 = 0 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('purchase back to ', @d3, ' ', @s, ' (was ', @pbal, ' ', @pstat, '); expense back to ', @d4, ' paid ', @d1, ' ', @s2, ' (was ', @ebal, ' ', @estat, ')'));
    SELECT @s = MAX(VoucherType), @n = COUNT(*) FROM PaymentReversalAudit WHERE ReferenceNumber = '99975' AND VoucherID = '99975' AND SupplierID = @sup;
    SELECT @n2 = COUNT(*) FROM BankStatementRecon WHERE (ReferenceNo = '99975' OR SourceRef = '99975') AND IsResolved = 0;
    SELECT @n3 = COUNT(*) FROM (SELECT td.AccountCode FROM TicketDetails td
                                WHERE EXISTS (SELECT 1 FROM TicketMaster tm WHERE tm.TicketNumber = td.TicketNumber AND tm.BranchCode = td.BranchCode AND tm.ReferenceNumber = '99975')
                                GROUP BY td.AccountCode HAVING ABS(SUM(ISNULL(td.Debit, 0)) - SUM(ISNULL(td.Credit, 0))) > 0.004) x;
    SELECT @d1 = AccountBalance FROM SupplierAccounts WHERE SupplierID = @sup;
    SELECT @d2 = SUM(ISNULL(Credit, 0) - ISNULL(Debit, 0)) FROM SupplierLedger WHERE SupplierID = @sup AND ReferenceNumber = '99975';
    SELECT @n = @n * 10 + (SELECT COUNT(*) FROM TransactionPaymentAP WHERE ReferenceNumber = 99975 AND ISNULL(ErrorCorrect, 0) = 0)
                       + (SELECT COUNT(*) FROM CheckVoucher WHERE ReferenceNumber = '99975' AND ISNULL(isErrorCorrect, 0) = 0);
    INSERT @r VALUES ('T06b reversal: audit MIXED, OC voided, GL / ledger / account back', CASE WHEN @s = 'MIXED' AND @n = 10 AND @n2 = 0 AND @n3 = 0 AND @d1 = @acct0 AND @d2 = 0 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('audit type ', @s, '; open OC ', @n2, '; accounts not netting to 0 ', @n3, '; ledger net ', @d2, '; account ', @d1, ' (was ', @acct0, '); audit*10 + live payment rows + live headers = ', @n));
END TRY BEGIN CATCH INSERT @r VALUES ('T05/T06', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T07 the OLD sp_CancelledChequesCS on a mixed voucher sent 'PURCHASE': restores the purchase only, the expense stays
--     paid while its ledger row is reversed (BUG SHOWN). [97] detects MIXED from the payment rows (T06).
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    DELETE @PLn; DELETE @ILn; DELETE @MLn;
    INSERT INTO @PLn (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
    VALUES (@pbranch, @pinv, @pdate, @pseqs, 0, @pcost, @pPay, 0, 0, 0, 'TEST97', 0, NULL);
    INSERT INTO @ILn (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
    VALUES (@ebranch, @einv, @edate, @eref, @ebatch, @eamt, @ePay, 0, 0, 0, 'TEST97', 0, NULL);
    EXEC dbo.sp_PostSupplierPaymentWithManualLines @parmrefno = '99975', @parmvoucherid = '99975', @parmsupplierid = @sup, @parmsuppliername = @supName,
         @parmcheckcoding = 'T97CV75', @parmcheckno = 'T97C75', @parmcheckdate = @today, @parmcontrolno = NULL, @parmcheckremarks = 'TEST97', @parmpreparedby = @user,
         @parmglcode = @bank, @parmpaymethod = 'MIXED', @parmforliquidation = 0, @parmvouchertype = 'CHECK', @parmPayingBranch = @branch,
         @InvoiceLegAmount = @tot, @InvoiceLines = @ILn, @ManualLines = @MLn, @InvoiceLineExtras = @IXn, @PurchaseLines = @PLn, @PurchaseLineExtras = @PXn;
    EXEC dbo.sp_CancelledChequesCS_OLD_10152026220000 @parmsupplierid = @sup, @parmreferenceno = '99975', @parmvoucherid = '99975', @parmvouchertype = 'PURCHASE',
         @parmreason = 'TEST97 T07 (rolled back)', @parmuser = @user, @parmglcode = @bank, @parmbranch = @branch;
    SELECT @d3 = Balance, @s = PayStatus FROM APAccounts WHERE SupplierID = @sup AND SequenceNo = @pseq;
    SELECT @d4 = Balance, @s2 = Status FROM ExpenseSummary WHERE SupplierID = @sup AND BatchReferenceID = @ebatch AND InvoiceNo = @einv;
    SELECT @d2 = SUM(ISNULL(Credit, 0) - ISNULL(Debit, 0)) FROM SupplierLedger WHERE SupplierID = @sup AND ReferenceNumber = '99975';
    INSERT @r VALUES ('T07 old reversal proc on a mixed voucher', CASE WHEN @d3 = @pbal AND @d4 = @ebal - @ePay THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END,
                      CONCAT('purchase back to ', @d3, ' ', @s, ', but the expense stays at ', @d4, ' ', @s2, ' (paid ', @ePay, ' of ', @ebal, ') while the voucher''s ledger rows net ', @d2, ' (reversed): invoice <> ledger by ', @ePay));
END TRY BEGIN CATCH INSERT @r VALUES ('T07', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T08 MIXED cheque + manual debit line 200: header = OC = bank credit = total + 200 (net, not the caller's figure);
--     then reversed through the screen's entry point (sent 'EXPENSE'): invoices, cash advance, GL and recon all back.
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    DELETE @PLn; DELETE @ILn; DELETE @MLn;
    INSERT INTO @PLn (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
    VALUES (@pbranch, @pinv, @pdate, @pseqs, 0, @pcost, @pPay, 0, 0, 0, 'TEST97', 0, NULL);
    INSERT INTO @ILn (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
    VALUES (@ebranch, @einv, @edate, @eref, @ebatch, @eamt, @ePay, 0, 0, 0, 'TEST97', 0, NULL);
    INSERT INTO @MLn (BranchCode, AccountCode, Amount, Particulars) VALUES (@branch, @caAcct, 200.00, 'TEST97 manual');
    -- @InvoiceLegAmount deliberately off by 1.00: the header / OC must follow what the lines paid (Known Bug #5)
    SET @d1 = @tot + 1.00;
    EXEC dbo.sp_PostSupplierPaymentWithManualLines @parmrefno = '99976', @parmvoucherid = '99985', @parmsupplierid = @sup, @parmsuppliername = @supName,
         @parmcheckcoding = 'T97CV76', @parmcheckno = 'T97C76', @parmcheckdate = @today, @parmcontrolno = NULL, @parmcheckremarks = 'TEST97', @parmpreparedby = @user,
         @parmglcode = @bank, @parmpaymethod = 'MIXED', @parmforliquidation = 0, @parmvouchertype = 'CHECK', @parmPayingBranch = @branch,
         @InvoiceLegAmount = @d1, @InvoiceLines = @ILn, @ManualLines = @MLn, @InvoiceLineExtras = @IXn, @PurchaseLines = @PLn, @PurchaseLineExtras = @PXn;
    SELECT @n = COUNT(*), @d1 = SUM(Amount) FROM CheckVoucher WHERE ReferenceNumber = '99976' AND VoucherID = 99985;
    SELECT @n2 = COUNT(*), @d2 = SUM(Amount) FROM BankStatementRecon WHERE ReferenceNo = '99985' AND SourceRef = '99976' AND ItemType = 'OC' AND IsResolved = 0;
    SELECT @d3 = SUM(ISNULL(td.Credit, 0) - ISNULL(td.Debit, 0)) FROM TicketDetails td
    WHERE td.AccountCode = @bank AND EXISTS (SELECT 1 FROM TicketMaster tm WHERE tm.TicketNumber = td.TicketNumber AND tm.BranchCode = td.BranchCode AND tm.ReferenceNumber = '99976');
    SELECT @n3 = COUNT(*), @d4 = SUM(Amount) FROM CashAdvance WHERE ReferenceNo = '99976';
    SELECT @s = STRING_AGG(CONCAT(ItemType, ':', Amount, ':', SourceModule), ',') FROM BankStatementRecon WHERE ReferenceNo = '99976' OR SourceRef = '99976';
    INSERT @r VALUES ('T08a mixed cheque + manual line: header = OC = bank credit = total + 200', CASE WHEN @n = 1 AND @d1 = @tot + 200 AND @n2 = 1 AND @d2 = @tot + 200 AND @d3 = @tot + 200 AND @n3 = 1 AND @d4 = 200 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('expected ', @tot + 200, ' (invoice leg sent as ', @tot + 1, '): header ', @n, ' / ', @d1, ', open OC ', @n2, ' / ', @d2, ' [', @s, '], bank credit ', @d3, ', cash advance ', @n3, ' / ', @d4,
                             ', payment row (the screen total as sent, as on a one-kind voucher) ', (SELECT SUM(Amount) FROM TransactionPaymentAP WHERE ReferenceNumber = 99976)));

    EXEC dbo.sp_ReverseCombinedSupplierVoucher @parmsupplierid = @sup, @parmreferenceno = '99976', @parmvoucherid = '99985', @parmvouchertype = 'EXPENSE',
         @parmcheckno = 'T97C76', @parmglcode = @bank, @parmbranch = @branch, @parmreason = 'TEST97 T08 (rolled back)', @parmuser = @user;
    SELECT @d3 = Balance FROM APAccounts WHERE SupplierID = @sup AND SequenceNo = @pseq;
    SELECT @d4 = Balance FROM ExpenseSummary WHERE SupplierID = @sup AND BatchReferenceID = @ebatch AND InvoiceNo = @einv;
    SELECT @n = COUNT(*) FROM CashAdvance WHERE ReferenceNo = '99976' AND Status <> 'REVERSED';
    SELECT @n2 = COUNT(*) FROM BankStatementRecon WHERE (ReferenceNo = '99976' OR SourceRef = '99976') AND IsResolved = 0;
    SELECT @n3 = COUNT(*) FROM (SELECT td.AccountCode FROM TicketDetails td
                                WHERE EXISTS (SELECT 1 FROM TicketMaster tm WHERE tm.TicketNumber = td.TicketNumber AND tm.BranchCode = td.BranchCode AND tm.ReferenceNumber = '99976')
                                GROUP BY td.AccountCode HAVING ABS(SUM(ISNULL(td.Debit, 0)) - SUM(ISNULL(td.Credit, 0))) > 0.004) x;
    SELECT @s2 = STRING_AGG(CONCAT(a.AccountCode, ' ', a.net), ', ') FROM (SELECT td.AccountCode, CAST(SUM(ISNULL(td.Debit, 0)) - SUM(ISNULL(td.Credit, 0)) AS DECIMAL(18,2)) AS net FROM TicketDetails td
                                WHERE EXISTS (SELECT 1 FROM TicketMaster tm WHERE tm.TicketNumber = td.TicketNumber AND tm.BranchCode = td.BranchCode AND tm.ReferenceNumber = '99976')
                                GROUP BY td.AccountCode HAVING ABS(SUM(ISNULL(td.Debit, 0)) - SUM(ISNULL(td.Credit, 0))) > 0.004) a;
    SET @mixNets = @n3; SET @mixNetDetail = @s2;
    SELECT @d1 = AccountBalance FROM SupplierAccounts WHERE SupplierID = @sup;
    SELECT @s = MAX(VoucherType) FROM PaymentReversalAudit WHERE ReferenceNumber = '99976' AND SupplierID = @sup;
    INSERT @r VALUES ('T08b reversal of the mixed + manual voucher (sent EXPENSE): invoices, cash advance, recon, account back', CASE WHEN @d3 = @pbal AND @d4 = @ebal AND @n = 0 AND @n2 = 0 AND @d1 = @acct0 AND @s = 'MIXED' THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('purchase ', @d3, ' (', @pbal, '), expense ', @d4, ' (', @ebal, '), cash advances not reversed ', @n, ', open recon items ', @n2, ', account ', @d1, ' (', @acct0, '), audit ', @s));
END TRY BEGIN CATCH INSERT @r VALUES ('T08', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T08c GL after reversing a voucher WITH a manual line: every account of the reference must net to 0.
--      Control: the same on a ONE-KIND voucher (expense + manual line), which [97] does not change. If both show the
--      same leftover, it is NOT [97]. Voucher id <> reference here (real numbering): sp_ReverseTicketsAP mirrors
--      reference + voucher id only, the CASH ADVANCE ticket (reference + reference) is mirrored once, by sp_ReverseCashAdvanceEntry.
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    DELETE @PLn; DELETE @ILn; DELETE @MLn;
    INSERT INTO @ILn (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
    VALUES (@ebranch, @einv, @edate, @eref, @ebatch, @eamt, @ePay, 0, 0, 0, 'TEST97', 0, NULL);
    INSERT INTO @MLn (BranchCode, AccountCode, Amount, Particulars) VALUES (@branch, @caAcct, 200.00, 'TEST97 manual');
    EXEC dbo.sp_PostSupplierPaymentWithManualLines @parmrefno = '99976', @parmvoucherid = '99986', @parmsupplierid = @sup, @parmsuppliername = @supName,
         @parmcheckcoding = 'T97CV76', @parmcheckno = 'T97C76', @parmcheckdate = @today, @parmcontrolno = NULL, @parmcheckremarks = 'TEST97', @parmpreparedby = @user,
         @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CHECK', @parmPayingBranch = @branch,
         @InvoiceLegAmount = @ePay, @InvoiceLines = @ILn, @ManualLines = @MLn, @InvoiceLineExtras = @IXn;
    EXEC dbo.sp_ReverseCombinedSupplierVoucher @parmsupplierid = @sup, @parmreferenceno = '99976', @parmvoucherid = '99986', @parmvouchertype = 'EXPENSE',
         @parmcheckno = 'T97C76', @parmglcode = @bank, @parmbranch = @branch, @parmreason = 'TEST97 T08c (rolled back)', @parmuser = @user;
    SELECT @n = COUNT(*), @s = STRING_AGG(CONCAT(a.AccountCode, ' ', a.net), ', ') FROM (SELECT td.AccountCode, CAST(SUM(ISNULL(td.Debit, 0)) - SUM(ISNULL(td.Credit, 0)) AS DECIMAL(18,2)) AS net FROM TicketDetails td
                                WHERE EXISTS (SELECT 1 FROM TicketMaster tm WHERE tm.TicketNumber = td.TicketNumber AND tm.BranchCode = td.BranchCode AND tm.ReferenceNumber = '99976')
                                GROUP BY td.AccountCode HAVING ABS(SUM(ISNULL(td.Debit, 0)) - SUM(ISNULL(td.Credit, 0))) > 0.004) a;
    SELECT @n2 = COUNT(*) FROM TicketMaster WHERE ReferenceNumber = '99976' AND Mnemonic = 'CASH ADVANCE' AND Product = 'REVERSAL';
    INSERT @r VALUES ('T08c GL nets to 0 after reversing a voucher with a manual line (each ticket reversed once)', CASE WHEN ISNULL(@mixNets, -1) = 0 AND @n = 0 THEN 'PASS' WHEN ISNULL(@mixNets, -1) = @n AND @n > 0 THEN 'PRE-EXISTING' ELSE 'FAIL' END,
                      CONCAT('mixed voucher: ', ISNULL(@mixNets, -1), ' accounts not at 0 (', ISNULL(@mixNetDetail, '-'), '); one-kind control voucher: ', @n, ' (', ISNULL(@s, '-'), '), cash-advance reversal tickets ', @n2,
                             ' for 1 cash-advance ticket'));
END TRY BEGIN CATCH INSERT @r VALUES ('T08c', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T09 MIXED cash voucher with no date: dated today everywhere (header, payment row, OC, tickets)
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    DELETE @PLn; DELETE @ILn; DELETE @MLn;
    INSERT INTO @PLn (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
    VALUES (@pbranch, @pinv, @pdate, @pseqs, 0, @pcost, @pPay, 0, 0, 0, 'TEST97', 0, NULL);
    INSERT INTO @ILn (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
    VALUES (@ebranch, @einv, @edate, @eref, @ebatch, @eamt, @ePay, 0, 0, 0, 'TEST97', 0, NULL);
    EXEC dbo.sp_PostSupplierPaymentWithManualLines @parmrefno = '99977', @parmvoucherid = '99977', @parmsupplierid = @sup, @parmsuppliername = @supName,
         @parmcheckcoding = '', @parmcheckno = NULL, @parmcheckdate = NULL, @parmcontrolno = 'T97CTL77', @parmcheckremarks = 'TEST97', @parmpreparedby = @user,
         @parmglcode = @bank, @parmpaymethod = 'MIXED', @parmforliquidation = 0, @parmvouchertype = 'CASH', @parmPayingBranch = @branch,
         @InvoiceLegAmount = @tot, @InvoiceLines = @ILn, @ManualLines = @MLn, @InvoiceLineExtras = @IXn, @PurchaseLines = @PLn, @PurchaseLineExtras = @PXn;
    SELECT @n = COUNT(*), @d1 = SUM(Amount), @dt1 = MAX(DateReceived) FROM CashVoucher WHERE ReferenceNumber = '99977' AND VoucherID = 99977;
    SELECT @dt2 = MAX(CAST(DatePaid AS DATE)) FROM TransactionPaymentAP WHERE ReferenceNumber = 99977;
    SELECT @dt3 = MAX(ItemDate), @d2 = SUM(Amount) FROM BankStatementRecon WHERE ReferenceNo = '99977' AND SourceRef = '99977' AND ItemType = 'OC';
    SELECT @dt4 = MIN(CAST(TicketDate AS DATE)), @n2 = COUNT(DISTINCT CAST(TicketDate AS DATE)) FROM TicketMaster WHERE ReferenceNumber = '99977';
    INSERT @r VALUES ('T09 mixed cash voucher with no date: dated today', CASE WHEN @n = 1 AND @d1 = @tot AND @d2 = @tot AND @dt1 = @today AND @dt2 = @today AND @dt3 = @today AND @dt4 = @today AND @n2 = 1 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('cash header ', @n, ' / ', @d1, ' dated ', @dt1, '; payment row ', @dt2, '; OC ', @d2, ' ', @dt3, '; tickets ', @dt4, ' (', @n2, ' distinct dates); today ', @today));
END TRY BEGIN CATCH INSERT @r VALUES ('T09', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T10 splist_Accounts: both flags = the purchase list + the expense list (old proc, one flag each); one flag unchanged
------------------------------------------------------------------
BEGIN TRY
    DECLARE @SL TABLE (Run VARCHAR(6) NULL, SequenceNumber BIGINT, Pay VARCHAR(15), ShipmentNo VARCHAR(10), BranchCode VARCHAR(5), ReferenceNo VARCHAR(150), BatchReferenceID BIGINT,
                       InvoiceNo VARCHAR(150), InvoiceDate DATE, Description VARCHAR(5000), ActualCost DECIMAL(12,2), Balance DECIMAL(12,2), AmountPaid DECIMAL(12,2), Variance DECIMAL(12,2),
                       EWTAmount DECIMAL(12,2), DiscountAmount DECIMAL(12,2), DiscountAccountCode VARCHAR(20), ReturnAllowances DECIMAL(12,2), Type VARCHAR(30));
    INSERT @SL (SequenceNumber, Pay, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, Variance, EWTAmount, DiscountAmount, DiscountAccountCode, ReturnAllowances, Type)
    EXEC dbo.splist_Accounts_OLD_10152026220000 @parmsupplierid = @sup, @parmispurchase = 1, @parmisexpense = 0;
    UPDATE @SL SET Run = 'oldP' WHERE Run IS NULL;
    INSERT @SL (SequenceNumber, Pay, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, Variance, EWTAmount, DiscountAmount, DiscountAccountCode, ReturnAllowances, Type)
    EXEC dbo.splist_Accounts_OLD_10152026220000 @parmsupplierid = @sup, @parmispurchase = 0, @parmisexpense = 1;
    UPDATE @SL SET Run = 'oldE' WHERE Run IS NULL;
    INSERT @SL (SequenceNumber, Pay, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, Variance, EWTAmount, DiscountAmount, DiscountAccountCode, ReturnAllowances, Type)
    EXEC dbo.splist_Accounts @parmsupplierid = @sup, @parmispurchase = 1, @parmisexpense = 1;
    UPDATE @SL SET Run = 'newPE' WHERE Run IS NULL;
    INSERT @SL (SequenceNumber, Pay, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, Variance, EWTAmount, DiscountAmount, DiscountAccountCode, ReturnAllowances, Type)
    EXEC dbo.splist_Accounts @parmsupplierid = @sup, @parmispurchase = 1, @parmisexpense = 0;
    UPDATE @SL SET Run = 'newP' WHERE Run IS NULL;
    INSERT @SL (SequenceNumber, Pay, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, Variance, EWTAmount, DiscountAmount, DiscountAccountCode, ReturnAllowances, Type)
    EXEC dbo.splist_Accounts @parmsupplierid = @sup, @parmispurchase = 0, @parmisexpense = 1;
    UPDATE @SL SET Run = 'newE' WHERE Run IS NULL;

    -- both flags: every row of the two old lists and nothing else (both directions, duplicates counted)
    SELECT @n = COUNT(*) FROM (SELECT SequenceNumber, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, EWTAmount, DiscountAmount, ReturnAllowances, Type FROM @SL WHERE Run IN ('oldP', 'oldE')
                               EXCEPT SELECT SequenceNumber, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, EWTAmount, DiscountAmount, ReturnAllowances, Type FROM @SL WHERE Run = 'newPE') x;
    SELECT @n2 = COUNT(*) FROM (SELECT SequenceNumber, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, EWTAmount, DiscountAmount, ReturnAllowances, Type FROM @SL WHERE Run = 'newPE'
                                EXCEPT SELECT SequenceNumber, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, EWTAmount, DiscountAmount, ReturnAllowances, Type FROM @SL WHERE Run IN ('oldP', 'oldE')) x;
    SELECT @d1 = (SELECT COUNT(*) FROM @SL WHERE Run = 'oldP'), @d2 = (SELECT COUNT(*) FROM @SL WHERE Run = 'oldE'), @d3 = (SELECT COUNT(*) FROM @SL WHERE Run = 'newPE');
    INSERT @r VALUES ('T10a list both flags = purchases + expenses', CASE WHEN @n = 0 AND @n2 = 0 AND @d3 = @d1 + @d2 AND @d1 > 0 AND @d2 > 0 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('supplier ', @sup, ': old purchase list ', CAST(@d1 AS INT), ' + old expense list ', CAST(@d2 AS INT), ' = new both-flag list ', CAST(@d3 AS INT), '; rows missing ', @n, ', extra ', @n2,
                             '; types ', (SELECT STRING_AGG(CONCAT(Type, ' ', c), ', ') FROM (SELECT Type, COUNT(*) AS c FROM @SL WHERE Run = 'newPE' GROUP BY Type) t)));

    -- one flag: unchanged (purchase / expense lists of the new proc = the old proc's, in both directions)
    SELECT @n = COUNT(*) FROM (SELECT SequenceNumber, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, EWTAmount, DiscountAmount, ReturnAllowances, Type, 'P' AS k FROM @SL WHERE Run = 'oldP'
                               UNION ALL SELECT SequenceNumber, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, EWTAmount, DiscountAmount, ReturnAllowances, Type, 'E' FROM @SL WHERE Run = 'oldE'
                               EXCEPT
                               (SELECT SequenceNumber, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, EWTAmount, DiscountAmount, ReturnAllowances, Type, 'P' FROM @SL WHERE Run = 'newP'
                                UNION ALL SELECT SequenceNumber, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, EWTAmount, DiscountAmount, ReturnAllowances, Type, 'E' FROM @SL WHERE Run = 'newE')) x;
    SELECT @n2 = COUNT(*) FROM (SELECT SequenceNumber, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, EWTAmount, DiscountAmount, ReturnAllowances, Type, 'P' AS k FROM @SL WHERE Run = 'newP'
                                UNION ALL SELECT SequenceNumber, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, EWTAmount, DiscountAmount, ReturnAllowances, Type, 'E' FROM @SL WHERE Run = 'newE'
                                EXCEPT
                                (SELECT SequenceNumber, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, EWTAmount, DiscountAmount, ReturnAllowances, Type, 'P' FROM @SL WHERE Run = 'oldP'
                                 UNION ALL SELECT SequenceNumber, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, EWTAmount, DiscountAmount, ReturnAllowances, Type, 'E' FROM @SL WHERE Run = 'oldE')) x;
    INSERT @r VALUES ('T10b list one flag unchanged (Telegraphic / old screen)', CASE WHEN @n = 0 AND @n2 = 0 AND (SELECT COUNT(*) FROM @SL WHERE Run = 'newP') = @d1 AND (SELECT COUNT(*) FROM @SL WHERE Run = 'newE') = @d2 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('purchase only ', (SELECT COUNT(*) FROM @SL WHERE Run = 'newP'), ' rows, expense only ', (SELECT COUNT(*) FROM @SL WHERE Run = 'newE'), ' rows; differ from the old proc: ', @n + @n2));
END TRY BEGIN CATCH INSERT @r VALUES ('T10', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH

------------------------------------------------------------------
-- R1-R8 refusals of the wrapper, one transaction each; PASS = that error number AND nothing of the voucher left
--   R1 60232 telegraphic voucher with both kinds          R2 60231 purchase lines + manual line, no expense lines
--   R3 60201 purchase lines only (nothing in @InvoiceLines: "nothing to post" comes first; 60231 needs a manual line)
--   R4 60233 both kinds sent as @parmpaymethod PURCHASE   R5 60513 OverPay on one purchase AND one expense
--   R6 60514 Advance Applied split across the kinds, each half within the pool, together above it (pool seeded)
--   R7 60234 one kind sent as MIXED                       R8 60235 post-check: a second payment row under the reference
------------------------------------------------------------------
DECLARE @k INT = 1, @want INT, @vt VARCHAR(12), @pm VARCHAR(20), @pool DECIMAL(18,2), @adv DECIMAL(18,2), @seq DECIMAL(7,0);
WHILE @k <= 8
BEGIN
    SET @want = CASE @k WHEN 1 THEN 60232 WHEN 2 THEN 60231 WHEN 3 THEN 60201 WHEN 4 THEN 60233 WHEN 5 THEN 60513 WHEN 6 THEN 60514 WHEN 7 THEN 60234 ELSE 60235 END;
    SET @name = CASE @k WHEN 1 THEN 'R1 mixed on a telegraphic voucher 60232'
                        WHEN 2 THEN 'R2 purchase lines + manual line, no expense lines 60231'
                        WHEN 3 THEN 'R3 purchase lines only: nothing to post 60201'
                        WHEN 4 THEN 'R4 both kinds sent as PURCHASE 60233'
                        WHEN 5 THEN 'R5 OverPay on a purchase AND an expense 60513'
                        WHEN 6 THEN 'R6 Advance Applied across both kinds above the pool 60514'
                        WHEN 7 THEN 'R7 one kind sent as MIXED 60234'
                        ELSE        'R8 post-check: two payment rows under the reference 60235' END;
    SET @vt = CASE WHEN @k = 1 THEN 'TELEGRAPHIC' ELSE 'CHECK' END;
    SET @pm = CASE WHEN @k = 4 THEN 'PURCHASE' ELSE 'MIXED' END;
    SET @err = NULL; SET @msg = NULL; SET @s = NULL;
    BEGIN TRAN;
    BEGIN TRY
        DELETE @PLn; DELETE @ILn; DELETE @PXn; DELETE @IXn; DELETE @MLn;
        IF @k <> 7
            INSERT INTO @PLn (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
            VALUES (@pbranch, @pinv, @pdate, @pseqs, 0, @pcost, @pPay, 0, 0, 0, 'TEST97', 0, NULL);
        IF @k NOT IN (2, 3)
            INSERT INTO @ILn (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
            VALUES (@ebranch, @einv, @edate, @eref, @ebatch, @eamt, @ePay, 0, 0, 0, 'TEST97', 0, NULL);
        IF @k = 2 INSERT INTO @MLn (BranchCode, AccountCode, Amount, Particulars) VALUES (@branch, @caAcct, 200.00, 'TEST97 manual');
        IF @k = 5
        BEGIN
            INSERT INTO @PXn (InvoiceNo, SequenceReferenceNumber, OverPay, OverPayExpense, AdvanceApplied) VALUES (@pinv, @pseqs, 10.00, 0, 0);
            INSERT INTO @IXn (InvoiceNo, SequenceReferenceNumber, OverPay, OverPayExpense, AdvanceApplied) VALUES (@einv, @eref, 10.00, 0, 0);
        END
        IF @k = 6
        BEGIN
            -- seed 100.00 of advance credit (an OVERPAY row of a test voucher), then draw (pool / 2 + 1) on each kind
            INSERT INTO APPaymentDetails (VoucherID, SupplierID, ReferenceNumber, BranchCode, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, VoucherType, TicketNumber, DebitGLCode, CreditGLCode, SequenceReferenceNumber, BatchReferenceID)
            VALUES ('99979', @sup, '99979', @branch, 'TEST97-SEED', @today, 100.00, 'OVERPAY', 'PURCHASE', 'CHECK', '', @bank, @bank, '0', NULL);
            SELECT @pool = ISNULL(SUM(CASE WHEN d.PaymentType = 'OVERPAY' THEN d.Amount ELSE 0 END), 0) - ISNULL(SUM(CASE WHEN d.PaymentType = 'ADVANCEAPPLIED' THEN d.Amount ELSE 0 END), 0)
            FROM APPaymentDetails d
            WHERE d.SupplierID = @sup AND d.PaymentType IN ('OVERPAY', 'ADVANCEAPPLIED') AND d.VoucherID <> '99978'
              AND NOT EXISTS (SELECT 1 FROM PaymentReversalAudit x WHERE x.VoucherID = d.VoucherID AND x.SupplierID = d.SupplierID);
            SET @adv = ROUND(@pool / 2, 2) + 1.00;
            INSERT INTO @PXn (InvoiceNo, SequenceReferenceNumber, OverPay, OverPayExpense, AdvanceApplied) VALUES (@pinv, @pseqs, 0, 0, @adv);
            INSERT INTO @IXn (InvoiceNo, SequenceReferenceNumber, OverPay, OverPayExpense, AdvanceApplied) VALUES (@einv, @eref, 0, 0, @adv);
            SET @s = CONCAT('pool ', @pool, ' (incl. 100.00 seeded); applied ', @adv, ' + ', @adv, ' = ', @adv * 2, ' | ');
        END
        IF @k = 8
        BEGIN
            SELECT @seq = ISNULL(MAX(SEQ_NO), 0) + 1 FROM TransactionPaymentAP WHERE SupplierKey = @sup;
            INSERT INTO TransactionPaymentAP (SEQ_NO, SupplierKey, ReferenceNumber, Amount, VoucherType, DatePaid, ExecuteBy, DateUpdate, UpdateBy, ErrorCorrect)
            VALUES (@seq, @sup, 99978, 1.00, 'CHECK', @today, @user, GETDATE(), @user, 0);
        END
        SET @d1 = CASE WHEN @k IN (2, 3) THEN @pPay WHEN @k = 7 THEN @ePay ELSE @tot END;
        EXEC dbo.sp_PostSupplierPaymentWithManualLines @parmrefno = '99978', @parmvoucherid = '99978', @parmsupplierid = @sup, @parmsuppliername = @supName,
             @parmcheckcoding = 'T97CV78', @parmcheckno = 'T97C78', @parmcheckdate = @today, @parmcontrolno = 'T97CTL78', @parmcheckremarks = 'TEST97', @parmpreparedby = @user,
             @parmglcode = @bank, @parmpaymethod = @pm, @parmforliquidation = 0, @parmvouchertype = @vt, @parmPayingBranch = @branch,
             @InvoiceLegAmount = @d1, @InvoiceLines = @ILn, @ManualLines = @MLn, @InvoiceLineExtras = @IXn, @PurchaseLines = @PLn, @PurchaseLineExtras = @PXn;
        INSERT @r VALUES (@name, 'FAIL', CONCAT(@s, 'not refused: header ', (SELECT SUM(Amount) FROM CheckVoucher WHERE ReferenceNumber = '99978'), ', payment rows ', (SELECT COUNT(*) FROM TransactionPaymentAP WHERE ReferenceNumber = 99978)));
    END TRY
    BEGIN CATCH
        SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
        SELECT @tc = @@TRANCOUNT;   -- read on its own (inside an INSERT it reads at least 1)
        SELECT @n = (SELECT COUNT(*) FROM APPaymentDetails WHERE ReferenceNumber IN ('99978', '99979')) + (SELECT COUNT(*) FROM TransactionPaymentAP WHERE ReferenceNumber IN (99978, 99979))
                  + (SELECT COUNT(*) FROM TicketMaster WHERE ReferenceNumber IN ('99978', '99979')) + (SELECT COUNT(*) FROM CheckVoucher WHERE ReferenceNumber IN ('99978', '99979'))
                  + (SELECT COUNT(*) FROM BankStatementRecon WHERE ReferenceNo IN ('99978', '99979') OR SourceRef IN ('99978', '99979'))
                  + (SELECT COUNT(*) FROM SupplierLedger WHERE ReferenceNumber IN ('99978', '99979'))
                  + (SELECT COUNT(*) FROM APAccounts WHERE SupplierID = @sup AND SequenceNo = @pseq AND Balance <> @pbal)
                  + (SELECT COUNT(*) FROM ExpenseSummary WHERE SupplierID = @sup AND BatchReferenceID = @ebatch AND InvoiceNo = @einv AND Balance <> @ebal);
        INSERT @r VALUES (@name, CASE WHEN @err = @want AND @n = 0 THEN 'PASS' ELSE 'FAIL' END,
                          CONCAT(@s, 'refused ', @err, ' ', LEFT(@msg, 200), ' | open transactions after ', @tc, ', rows of the voucher / invoices changed ', @n));
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @k += 1;
END

------------------------------------------------------------------
-- leftovers + results
------------------------------------------------------------------
Report:
SELECT @n = (SELECT COUNT(*) FROM TransactionPaymentAP WHERE ReferenceNumber BETWEEN 99971 AND 99979)
          + (SELECT COUNT(*) FROM APPaymentDetails WHERE ReferenceNumber BETWEEN '99971' AND '99979' OR VoucherID BETWEEN '99971' AND '99989')
          + (SELECT COUNT(*) FROM TicketMaster WHERE ReferenceNumber IN ('99971','99972','99973','99974','99975','99976','99977','99978','99979'))
          + (SELECT COUNT(*) FROM SupplierLedger WHERE ReferenceNumber IN ('99971','99972','99973','99974','99975','99976','99977','99978','99979'))
          + (SELECT COUNT(*) FROM CheckVoucher WHERE ReferenceNumber IN ('99971','99972','99973','99974','99975','99976','99977','99978','99979') OR VoucherID BETWEEN 99971 AND 99989)
          + (SELECT COUNT(*) FROM CashVoucher WHERE ReferenceNumber IN ('99971','99972','99973','99974','99975','99976','99977','99978','99979') OR VoucherID BETWEEN 99971 AND 99989)
          + (SELECT COUNT(*) FROM BankStatementRecon WHERE ReferenceNo IN ('99971','99972','99973','99974','99975','99976','99977','99978','99979','99985','99986') OR SourceRef IN ('99971','99972','99973','99974','99975','99976','99977','99978','99979'))
          + (SELECT COUNT(*) FROM CashAdvance WHERE ReferenceNo IN ('99971','99972','99973','99974','99975','99976','99977','99978','99979') OR VoucherID IN ('99985','99986'))
          + (SELECT COUNT(*) FROM PaymentReversalAudit WHERE ReferenceNumber IN ('99971','99972','99973','99974','99975','99976','99977','99978','99979'));
SELECT @n2 = (SELECT COUNT(*) FROM APAccounts WHERE SupplierID = @sup AND SequenceNo = @pseq AND (Balance <> @pbal OR PayStatus <> @pstat))
           + (SELECT COUNT(*) FROM ExpenseSummary WHERE SupplierID = @sup AND BatchReferenceID = @ebatch AND InvoiceNo = @einv AND (Balance <> @ebal OR Status <> @estat))
           + (SELECT COUNT(*) FROM SupplierAccounts WHERE SupplierID = @sup AND CAST(AccountBalance AS DECIMAL(18,2)) <> @acct0);
SELECT @tc = @@TRANCOUNT;
INSERT @r VALUES ('leftovers', CASE WHEN @n = 0 AND ISNULL(@n2, 0) = 0 AND @tc = 0 THEN 'PASS' ELSE 'FAIL' END,
                  CONCAT(@n, ' test rows left behind (refs 99971 - 99979); fixture invoices / account changed: ', ISNULL(@n2, 0), '; open transactions ', @tc));

SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
SELECT DB_NAME() AS DatabaseName, SUM(CASE WHEN Result = 'PASS' THEN 1 ELSE 0 END) AS Pass, SUM(CASE WHEN Result = 'BUG SHOWN' THEN 1 ELSE 0 END) AS BugShown, SUM(CASE WHEN Result = 'PRE-EXISTING' THEN 1 ELSE 0 END) AS PreExisting,
       SUM(CASE WHEN Result = 'SKIP' THEN 1 ELSE 0 END) AS Skip, SUM(CASE WHEN Result IN ('FAIL', 'ERROR', 'UNEXPECTED') THEN 1 ELSE 0 END) AS Fail FROM @r;
