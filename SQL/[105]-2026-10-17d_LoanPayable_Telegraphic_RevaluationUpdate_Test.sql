/* ================================================================
   [105] TEST SCRIPT - the loan as a payable in Vouchering Telegraphic, moved by every revaluation
   ================================================================
   Run in SSMS on DEV or STAGING AFTER [105] is applied. Every test runs inside BEGIN TRAN ... ROLLBACK, so nothing is
   left behind; the last result sets show PASS / BUG SHOWN / SKIP / FAIL per test. Do NOT run on PRODUCTION.
   "BUG SHOWN" = the _OLD_10172026210000 backup reproduces what [105] closes (a revaluation / reversal that leaves the
   loan's payable behind the GL, a loan paid from the wrong branch, the loan listed in a screen that would settle it
   against the wrong account).
   A refusal rolls back the WHOLE test transaction (the procs' CATCH does ROLLBACK; THROW), so "nothing changed" is
   checked after the CATCH against the loan's state read before the transaction.

   Fixtures picked automatically (first result set shows them); missing fixture -> that test shows SKIP:
     - LOAN: the first active loan (LoanAccount) whose PayableBatchReferenceID is set ([105] loaded its payable);
             its last POSTED entry gives the next revaluation date (the following month end, not after this month),
             the foreign / peso balance and the last rate. @PickLoanID forces one loan.
     - the revaluation rate @Rate (default 70.2158, the 09-30 Peachtree rate), the telegraphic payment @PayAmt
       (default 7,000,000.00, dated the 15th of the revaluation month) and the principal it paid @ForeignPaid
       (default 100,000.00: 70.00 a unit, within 20% of the last rate, as [81] requires);
     - the bank account @bank (default 101020101) and another branch (the first one that is not the loan's).
   Test references 99931-99935 / voucher ids 99941-99944 must be unused (checked first). The GL must not be closed
   through the payment date, and the bank recon month of the payment must not be LOCKED.
   v2 of [105] (2026-10-17 ~21:45): a revaluation moves Balance to the current value and Amount (the gross) by the same
   change, so Balance <= Amount stays true after a payment; Vouchering Telegraphic shows a loan's Actual Cost = its
   Balance; 62033 (payable below 0), 58041 (memo on the loan), 58040 also on a line branch <> the loan's.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT OFF;   -- the tests catch the refusals themselves

DECLARE @PickLoanID INT = NULL, @Rate DECIMAL(18,6) = 70.2158, @PayAmt DECIMAL(18,2) = 7000000.00, @ForeignPaid DECIMAL(18,2) = 100000.00,
        @bank VARCHAR(20) = '101020101';

DECLARE @r TABLE (Seq INT IDENTITY, Test VARCHAR(120), Result VARCHAR(12), Detail VARCHAR(1000));
DECLARE @fp TABLE (Cs VARCHAR(10), Run VARCHAR(10), Item VARCHAR(10), Val VARCHAR(MAX));
DECLARE @user VARCHAR(50) = 'TEST105', @ctl VARCHAR(50) = 'TEST105', @today DATE = CAST(GETDATE() AS DATE);
DECLARE @refA VARCHAR(10) = '99931', @vidA VARCHAR(10) = '99941',   -- telegraphic payment from the loan's branch (L3, L5)
        @refB VARCHAR(10) = '99932', @vidB VARCHAR(10) = '99942',   -- telegraphic payment from another branch (L4a)
        @refC VARCHAR(10) = '99933', @vidC VARCHAR(10) = '99943',   -- sp_AddPaymentSupplierCompound_V2 (L4b)
        @refD VARCHAR(10) = '99934', @vidD VARCHAR(10) = '99944',   -- legacy sp_AddPaymentSupplierCompound (L4c)
        @refE VARCHAR(10) = '99935';                                -- supplier adjustment memo on the loan (L4h)
DECLARE @e INT, @em NVARCHAR(2048), @tc INT, @n INT, @n2 INT, @n3 INT, @s VARCHAR(1000), @s2 VARCHAR(1000), @stage VARCHAR(30), @run VARCHAR(10), @k INT,
        @pay DECIMAL(18,2), @amt DECIMAL(18,2), @paid DECIMAL(18,2), @st VARCHAR(50), @gl DECIMAL(18,2), @led DECIMAL(18,2), @line DECIMAL(18,2),
        @lines VARCHAR(400), @lt VARCHAR(50), @tie VARCHAR(600), @now VARCHAR(800), @nAP INT, @apList VARCHAR(400),
        @txn INT, @tn VARCHAR(20), @tref VARCHAR(20), @d1 DECIMAL(18,2), @d2 DECIMAL(18,2), @d3 DECIMAL(18,2), @x1 VARCHAR(300), @x2 VARCHAR(300), @bigDate DATE;

------------------------------------------------------------------
-- 0. install check
------------------------------------------------------------------
IF COL_LENGTH('dbo.LoanAccount', 'PayableBatchReferenceID') IS NULL
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.spu_Loan_PostRevaluation')), N'') NOT LIKE '%THROW 62032%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.spu_Loan_ReverseRevaluation')), N'') NOT LIKE '%THROW 62032%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_Loan_GetAccounts')), N'') NOT LIKE '%PayableBalance%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostVoucherManual')), N'') NOT LIKE '%THROW 58040%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.splist_Accounts')), N'') NOT LIKE '%[[]105]%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetUnpaidInvoicesForSupplier')), N'') NOT LIKE '%[[]105]%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2')), N'') NOT LIKE '%THROW 60540%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound')), N'') NOT LIKE '%THROW 60540%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.view_ExpenseSummary')), N'') NOT LIKE '%[[]105]%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostSupplierAdjustmentMemo')), N'') NOT LIKE '%THROW 58041%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.spu_Loan_PostRevaluation')), N'') NOT LIKE '%THROW 62033%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.spu_Loan_ReverseRevaluation')), N'') NOT LIKE '%THROW 62033%'
BEGIN
    INSERT @r VALUES ('I0 install check', 'FAIL', '[105] is not installed (column LoanAccount.PayableBatchReferenceID or a [105] marker missing)');
    SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
    RETURN;
END
IF OBJECT_ID('dbo.spu_Loan_PostRevaluation_OLD_10172026210000', 'P') IS NULL OR OBJECT_ID('dbo.spu_Loan_ReverseRevaluation_OLD_10172026210000', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_PostVoucherManual_OLD_10172026210000', 'P') IS NULL OR OBJECT_ID('dbo.splist_Accounts_OLD_10172026210000', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_GetUnpaidInvoicesForSupplier_OLD_10172026210000', 'P') IS NULL OR OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2_OLD_10172026210000', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_OLD_10172026210000', 'P') IS NULL OR OBJECT_ID('dbo.view_ExpenseSummary_OLD_10172026210000', 'V') IS NULL
   OR OBJECT_ID('dbo.sp_Loan_GetAccounts_OLD_10172026210000', 'P') IS NULL OR OBJECT_ID('dbo.sp_PostSupplierAdjustmentMemo_OLD_10172026210000', 'P') IS NULL
BEGIN
    INSERT @r VALUES ('I0 install check', 'FAIL', '[105] backups _OLD_10172026210000 missing; the old = new / BUG SHOWN tests need them');
    SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
    RETURN;
END
INSERT @r VALUES ('I0 install check', CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.spu_Loan_PostRevaluation_OLD_10172026210000')) NOT LIKE '%62030%'
                                            AND OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostVoucherManual_OLD_10172026210000')) NOT LIKE '%58040%'
                                            AND OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2_OLD_10172026210000')) NOT LIKE '%60540%'
                                            AND OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostSupplierAdjustmentMemo_OLD_10172026210000')) NOT LIKE '%58041%' THEN 'PASS' ELSE 'FAIL' END,
                  'column LoanAccount.PayableBatchReferenceID; the 10 objects carry [105] (62032 / 62033 / 58040 / 58041 / 60540 / the LOAN filter); 10 backups _OLD_10172026210000 present and without the new checks');

-- I1: race fix (v2) - spu_Loan_PostRevaluation reads the payable under UPDLOCK and checks 62030 BEFORE it reads the GL up to the date
DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.spu_Loan_PostRevaluation'));
DECLARE @p1 INT = CHARINDEX('FROM dbo.ExpenseSummary WITH (UPDLOCK, ROWLOCK)', @def), @p2 INT = CHARINDEX('THROW 62030', @def),
        @p3 INT = CHARINDEX('DECLARE @glBal', @def), @p4 INT = CHARINDEX('THROW 62020', @def), @p5 INT = CHARINDEX('INSERT INTO dbo.TicketMaster', @def);
INSERT @r VALUES ('I1 revaluation: payable read under UPDLOCK + 62030 before the GL read (62020) and before the first write',
                  CASE WHEN @p1 > 0 AND @p1 < @p2 AND @p2 < @p3 AND @p2 < @p4 AND @p2 < @p5 THEN 'PASS' ELSE 'FAIL' END,
                  CONCAT('position UPDLOCK read ', @p1, ', THROW 62030 ', @p2, ', DECLARE @glBal ', @p3, ', THROW 62020 ', @p4, ', INSERT INTO dbo.TicketMaster ', @p5));

------------------------------------------------------------------
-- 1. state queries
------------------------------------------------------------------
-- the loan's payable, its GL (liability, loan branch, all dates), its supplier-ledger net, its line(s), its loan entries
DECLARE @qTie NVARCHAR(MAX) = N'
SELECT @pay = NULL, @amt = NULL, @paid = NULL, @st = NULL;
SELECT @pay = CAST(es.Balance AS DECIMAL(18,2)), @amt = CAST(es.Amount AS DECIMAL(18,2)), @paid = CAST(ISNULL(es.AmountPaid, 0) AS DECIMAL(18,2)), @st = es.Status
FROM dbo.ExpenseSummary AS es WHERE es.BatchReferenceID = @batch AND es.SupplierID = @sup AND es.InvoiceNo = @code AND es.PostingMode = ''LOAN'';
SELECT @gl = CAST(ISNULL(SUM(ISNULL(d.Credit, 0) - ISNULL(d.Debit, 0)), 0) AS DECIMAL(18,2)) FROM dbo.TicketDetails AS d WHERE d.AccountCode = @liab AND d.BranchCode = @branch;
SELECT @led = CAST(ISNULL(SUM(ISNULL(l.Credit, 0) - ISNULL(l.Debit, 0)), 0) AS DECIMAL(18,2)) FROM dbo.SupplierLedger AS l WHERE l.SupplierKey = @sup AND l.InvoiceNo = @code AND l.BatchReferenceID = @batch;
SELECT @line = CAST(SUM(m.Balance) AS DECIMAL(18,2)),
       @lines = STRING_AGG(CONCAT(m.BranchCode, '':'', m.Amount, ''|'', ISNULL(m.AmountPaid, 0), ''|'', m.Balance, ''|'', m.Status), '','') WITHIN GROUP (ORDER BY m.TRN_SEQ_NO)
FROM dbo.ExpenseMaster AS m WHERE m.SupplierID = @sup AND m.InvoiceNo = @code AND m.BatchReferenceID = @batch;
SELECT @lt = CONCAT(COUNT(*), ''|'', MAX(TxnID), ''|'', SUM(PhpChange)) FROM dbo.LoanTransaction WHERE LoanID = @loan AND Status = ''POSTED'';';
DECLARE @pTie NVARCHAR(MAX) = N'@batch BIGINT, @sup VARCHAR(50), @code VARCHAR(30), @liab VARCHAR(20), @branch VARCHAR(5), @loan INT,
  @pay DECIMAL(18,2) OUTPUT, @amt DECIMAL(18,2) OUTPUT, @paid DECIMAL(18,2) OUTPUT, @st VARCHAR(50) OUTPUT, @gl DECIMAL(18,2) OUTPUT,
  @led DECIMAL(18,2) OUTPUT, @line DECIMAL(18,2) OUTPUT, @lines VARCHAR(400) OUTPUT, @lt VARCHAR(50) OUTPUT';

-- AP Exception Center findings that were not there before the tests (any check, any supplier)
DECLARE @qAP NVARCHAR(MAX) = N'
SELECT @nAP = COUNT(*),
       @apList = LEFT(ISNULL(STRING_AGG(CAST(CONCAT(f.ExceptionCode, '' '', f.Ref, '' '', ISNULL(f.InvoiceNo, ''''), '' '', f.Difference) AS VARCHAR(MAX)), ''; ''), ''none''), 400)
FROM dbo.fn_rpt_exc_AP_Findings() AS f
WHERE NOT EXISTS (SELECT 1 FROM #apBase AS b WHERE b.Code = f.ExceptionCode AND b.Ref = f.Ref AND ISNULL(b.Inv, '''') = ISNULL(f.InvoiceNo, ''''));';
DECLARE @pAP NVARCHAR(200) = N'@nAP INT OUTPUT, @apList VARCHAR(400) OUTPUT';

-- one telegraphic voucher's footprint (Cs, Run as given): every table sp_PostVoucherManual writes, numbers / today left out
DECLARE @qV NVARCHAR(MAX) = N'
SELECT @cs, @run, ''TD'', (SELECT CONCAT(COUNT(*), ''|'', STRING_AGG(CONCAT(d.BranchCode, '':'', d.AccountCode, '':'', d.Debit, '':'', d.Credit, '':'', CONVERT(VARCHAR(10), d.TicketDate, 120)), '','')
                                    WITHIN GROUP (ORDER BY d.BranchCode, d.AccountCode))
                         FROM dbo.TicketDetails AS d WHERE d.ReferenceNumber = @ref AND d.ReferenceKey = @vid)
UNION ALL SELECT @cs, @run, ''TM'', (SELECT STRING_AGG(CONCAT(BranchCode, '':'', Origin, '':'', Mnemonic, '':'', Status, '':'', Owner), '','') WITHIN GROUP (ORDER BY BranchCode)
                                   FROM dbo.TicketMaster WHERE ReferenceNumber = @ref AND ReferenceKey = @vid)
UNION ALL SELECT @cs, @run, ''ES'', (SELECT CONCAT(Amount, ''|'', Balance, ''|'', ISNULL(AmountPaid, 0), ''|'', Status) FROM dbo.ExpenseSummary
                                   WHERE BatchReferenceID = @batch AND SupplierID = @sup AND InvoiceNo = @code)
UNION ALL SELECT @cs, @run, ''EM'', (SELECT STRING_AGG(CONCAT(BranchCode, '':'', Amount, ''|'', ISNULL(AmountPaid, 0), ''|'', Balance, ''|'', Status), '','') WITHIN GROUP (ORDER BY TRN_SEQ_NO)
                                   FROM dbo.ExpenseMaster WHERE BatchReferenceID = @batch AND SupplierID = @sup AND InvoiceNo = @code)
UNION ALL SELECT @cs, @run, ''SL'', (SELECT STRING_AGG(CONCAT(TransCode, '':'', Debit, '':'', Credit, '':'', InvoiceNo, '':'', BatchReferenceID, '':'', PaymentType, '':'', CONVERT(VARCHAR(10), TransactionDate, 120)), '','')
                                    WITHIN GROUP (ORDER BY TRN_SEQ_NO)
                                   FROM dbo.SupplierLedger WHERE SupplierKey = @sup AND ReferenceNumber = @ref)
UNION ALL SELECT @cs, @run, ''APD'', (SELECT STRING_AGG(CONCAT(BranchCode, '':'', PaymentType, '':'', PaymentMethod, '':'', VoucherType, '':'', Amount, '':'', DebitGLCode, '':'', CreditGLCode, '':'', BatchReferenceID, '':'', ISNULL(Variance, 0)), '','')
                                    WITHIN GROUP (ORDER BY InvoiceNo)
                                    FROM dbo.APPaymentDetails WHERE ReferenceNumber = @ref AND VoucherID = @vid)
UNION ALL SELECT @cs, @run, ''TPAP'', (SELECT STRING_AGG(CONCAT(Amount, ''|'', VoucherType, ''|'', CAST(ErrorCorrect AS INT)), '','') FROM dbo.TransactionPaymentAP
                                     WHERE SupplierKey = @sup AND ReferenceNumber = CAST(@ref AS INT))
UNION ALL SELECT @cs, @run, ''TV'', (SELECT STRING_AGG(CONCAT(Amount, ''|'', ControlNo, ''|'', OfficialReceiptNo, ''|'', VoucherType, ''|'', CAST(ISNULL(isErrorCorrect, 0) AS INT)), '','') FROM dbo.TelegraphicVoucher
                                   WHERE ReferenceNumber = @ref AND VoucherID = CAST(@vid AS DECIMAL(7,0)))
UNION ALL SELECT @cs, @run, ''BSR'', (SELECT STRING_AGG(CONCAT(BranchCode, '':'', ItemType, '':'', AccountCode, '':'', Amount, '':'', CONVERT(VARCHAR(10), PeriodEnd, 120), '':'', SourceModule, '':'', ReferenceNo, '':'', CAST(IsResolved AS INT), '':'', ISNULL(ResolvedReason, ''-'')), '','')
                                    WITHIN GROUP (ORDER BY ReconID)
                                    FROM dbo.BankStatementRecon WHERE SourceRef = @ref);';
DECLARE @pV NVARCHAR(300) = N'@cs VARCHAR(10), @run VARCHAR(10), @ref VARCHAR(10), @vid VARCHAR(10), @batch BIGINT, @sup VARCHAR(50), @code VARCHAR(30)';

------------------------------------------------------------------
-- 2. fixtures and pre-checks
------------------------------------------------------------------
IF (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber IN (@refA, @refB, @refC, @refD, @refE))
 + (SELECT COUNT(*) FROM dbo.SupplierAdjustmentMemo WHERE ReferenceNo = @refE)
 + (SELECT COUNT(*) FROM dbo.APPaymentDetails WHERE ReferenceNumber IN (@refA, @refB, @refC, @refD) OR VoucherID IN (@vidA, @vidB, @vidC, @vidD))
 + (SELECT COUNT(*) FROM dbo.TransactionPaymentAP WHERE ReferenceNumber IN (99931, 99932, 99933, 99934))
 + (SELECT COUNT(*) FROM dbo.TelegraphicVoucher WHERE ReferenceNumber IN (@refA, @refB, @refC, @refD) OR VoucherID IN (99941, 99942, 99943, 99944))
 + (SELECT COUNT(*) FROM dbo.CashVoucher WHERE ReferenceNumber IN (@refA, @refB, @refC, @refD) OR VoucherID IN (99941, 99942, 99943, 99944))
 + (SELECT COUNT(*) FROM dbo.CheckVoucher WHERE ReferenceNumber IN (@refA, @refB, @refC, @refD) OR VoucherID IN (99941, 99942, 99943, 99944))
 + (SELECT COUNT(*) FROM dbo.BankStatementRecon WHERE SourceRef IN (@refA, @refB, @refC, @refD) OR ReferenceNo IN (@vidA, @vidB, @vidC, @vidD))
 + (SELECT COUNT(*) FROM dbo.SupplierLedger WHERE ReferenceNumber IN (@refA, @refB, @refC, @refD, @refE))
 + (SELECT COUNT(*) FROM dbo.PaymentReversalAudit WHERE ReferenceNumber IN (@refA, @refB, @refC, @refD)) > 0
BEGIN
    INSERT @r VALUES ('fixtures', 'ERROR', 'test references 99931-99935 / voucher ids 99941-99944 are in use here; nothing was run');
    SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
    RETURN;
END

DECLARE @loan INT, @code VARCHAR(30), @sup VARCHAR(50), @supName VARCHAR(150), @branch VARCHAR(5), @liab VARCHAR(20), @batch BIGINT, @cur CHAR(3);
SELECT TOP (1) @loan = a.LoanID, @code = a.LoanCode, @sup = a.SupplierID, @supName = s.SupplierName, @branch = a.BranchCode, @liab = a.LiabilityAccount,
       @batch = a.PayableBatchReferenceID, @cur = a.Currency
FROM dbo.LoanAccount AS a INNER JOIN dbo.Supplier AS s ON s.SupplierID = a.SupplierID AND s.SupplierKey = a.SupplierID
WHERE a.IsActive = 1 AND a.PayableBatchReferenceID IS NOT NULL AND (@PickLoanID IS NULL OR a.LoanID = @PickLoanID)
  AND EXISTS (SELECT 1 FROM dbo.LoanTransaction AS t WHERE t.LoanID = a.LoanID AND t.Status = 'POSTED')
ORDER BY a.LoanID;

DECLARE @payRef VARCHAR(10), @lastTxn INT, @lastType VARCHAR(15), @lastDate DATE, @lastRate DECIMAL(18,6), @fBal DECIMAL(18,2), @pBal DECIMAL(18,2), @lastChg DECIMAL(18,2);
SELECT @payRef = ReferenceNumber FROM dbo.ExpenseSummary WHERE BatchReferenceID = @batch AND SupplierID = @sup AND InvoiceNo = @code AND PostingMode = 'LOAN';
SELECT TOP (1) @lastTxn = TxnID, @lastType = TxnType, @lastDate = TxnDate, @lastRate = Rate, @fBal = ForeignBalance, @pBal = PhpBalance, @lastChg = PhpChange
FROM dbo.LoanTransaction WHERE LoanID = @loan AND Status = 'POSTED' ORDER BY TxnDate DESC, TxnID DESC;

DECLARE @revalDate DATE = EOMONTH(DATEADD(DAY, 1, @lastDate));
DECLARE @canReval BIT = CASE WHEN @loan IS NOT NULL AND @revalDate <= EOMONTH(@today) THEN 1 ELSE 0 END;
DECLARE @payDate DATE = DATEFROMPARTS(YEAR(@revalDate), MONTH(@revalDate), 15);
IF @payDate > @today SET @payDate = @today;
DECLARE @other VARCHAR(5) = (SELECT TOP (1) BranchCode FROM dbo.Branches WHERE BranchCode <> ISNULL(@branch, '') ORDER BY BranchCode);
DECLARE @glLock DATE = (SELECT MAX(LockedThroughDate) FROM dbo.GLPeriodLock);
DECLARE @canPay BIT = CASE WHEN @loan IS NOT NULL
                                AND EXISTS (SELECT 1 FROM dbo.ChartOfAccounts WHERE AccountCode = @bank AND AccountCode LIKE '10102%')
                                AND NOT EXISTS (SELECT 1 FROM dbo.BankReconHeader WHERE Status = 'LOCKED' AND AccountCode = @bank AND BranchCode IN (@branch, @other)
                                                                                    AND PeriodEnd >= EOMONTH(@payDate))
                                AND @payDate > @lastDate THEN 1 ELSE 0 END;
-- the expected figures
DECLARE @exp1 DECIMAL(18,2) = ROUND(@fBal * @Rate, 2);                      -- L1: unchanged foreign balance at @Rate
DECLARE @chg1 DECIMAL(18,2) = @exp1 - @pBal;
DECLARE @newF3 DECIMAL(18,2) = @fBal - @ForeignPaid;                        -- L3: after the principal payment
DECLARE @exp3 DECIMAL(18,2) = ROUND(@newF3 * @Rate, 2);
DECLARE @chg3 DECIMAL(18,2) = @exp3 - (@pBal - @PayAmt);
DECLARE @canL3c BIT = CASE WHEN @canReval = 1 AND @canPay = 1 AND @newF3 > 0 AND @ForeignPaid > 0
                                AND @PayAmt / @ForeignPaid BETWEEN @lastRate * 0.8 AND @lastRate * 1.2 THEN 1 ELSE 0 END;
-- L4i / L4j: a payment of all but 1,000.00 (L4i: dated the day after the revaluation date, which the revaluation's
-- "GL up to the date" does not see; L4j: on the usual payment date, before reversing the last revaluation)
DECLARE @lateDate DATE = DATEADD(DAY, 1, @revalDate), @BigPay DECIMAL(18,2) = @pBal - 1000.00;
DECLARE @canLate BIT = CASE WHEN @canReval = 1 AND @canPay = 1 AND @lateDate <= @today AND @chg1 < -1000.00
                                 AND NOT EXISTS (SELECT 1 FROM dbo.BankReconHeader WHERE Status = 'LOCKED' AND AccountCode = @bank AND BranchCode = @branch AND PeriodEnd >= EOMONTH(@lateDate))
                            THEN 1 ELSE 0 END;
-- L5b: the revaluation after the one at @revalDate (the loan can be revalued again after the payment is reversed)
DECLARE @nextDate DATE = EOMONTH(DATEADD(DAY, 1, @revalDate));

IF @loan IS NOT NULL AND @glLock IS NOT NULL AND @glLock >= @payDate
BEGIN
    INSERT @r VALUES ('fixtures', 'ERROR', CONCAT('the GL is closed through ', CONVERT(VARCHAR(10), @glLock, 120), ', on or after the test payment / revaluation dates (', CONVERT(VARCHAR(10), @payDate, 120),
                                               ' / ', CONVERT(VARCHAR(10), @revalDate, 120), '); they would be refused (59900)'));
    SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
    RETURN;
END

SELECT 'fixtures' AS what, @loan AS loan_id, @code AS loan_code, @sup AS supplier, @branch AS loan_branch, @liab AS liability, @batch AS payable_batch, @payRef AS payable_ref,
       @lastType AS last_entry, @lastDate AS last_date, @lastRate AS last_rate, @fBal AS foreign_balance, @pBal AS php_balance,
       @revalDate AS next_reval, @Rate AS rate, @exp1 AS expected_unchanged, @payDate AS pay_date, @PayAmt AS pay_amount, @newF3 AS foreign_after_pay, @exp3 AS expected_after_pay,
       @bank AS bank, @other AS other_branch, @glLock AS gl_locked_through, @canReval AS can_reval, @canPay AS can_pay;

IF @loan IS NULL
BEGIN
    INSERT @r VALUES ('fixtures', 'SKIP', 'no active loan with a payable (LoanAccount.PayableBatchReferenceID) here; every test skipped');
    GOTO Report;
END
INSERT @r VALUES ('fixtures', 'PASS', CONCAT('loan ', @code, ' (', @loan, ', ', @sup, ', ', @cur, ', branch ', @branch, ', ', @liab, '), payable ref ', @payRef, ' / batch ', @batch,
                                         '; last ', @lastType, ' ', CONVERT(VARCHAR(10), @lastDate, 120), ' ', @fBal, ' @', @lastRate, ' = ', @pBal,
                                         '; next revaluation ', CONVERT(VARCHAR(10), @revalDate, 120), ' @', @Rate, ' -> ', @exp1, ' (', @chg1, ')',
                                         '; payment ', @PayAmt, ' on ', CONVERT(VARCHAR(10), @payDate, 120), ' from ', @bank, ', then ', @newF3, ' -> ', @exp3, '; other branch ', @other));

-- "before": the loan's state (read outside any transaction) and the AP findings already there
DECLARE @before VARCHAR(800);
EXEC sp_executesql @qTie, @pTie, @batch, @sup, @code, @liab, @branch, @loan, @pay OUTPUT, @amt OUTPUT, @paid OUTPUT, @st OUTPUT, @gl OUTPUT, @led OUTPUT, @line OUTPUT, @lines OUTPUT, @lt OUTPUT;
SET @before = CONCAT('payable ', @amt, '/', @pay, ' paid ', @paid, ' ', @st, '; GL ', @gl, '; ledger ', @led, '; line ', @lines, '; loan entries ', @lt);
IF OBJECT_ID('tempdb..#apBase') IS NOT NULL DROP TABLE #apBase;
CREATE TABLE #apBase (Code VARCHAR(50), Ref VARCHAR(50), Inv VARCHAR(150));
INSERT INTO #apBase (Code, Ref, Inv) SELECT ExceptionCode, Ref, InvoiceNo FROM dbo.fn_rpt_exc_AP_Findings();

-- the payment lines the screens would send (one row: the loan's payable)
DECLARE @vInv dbo.VoucherManualInvoiceTVP_v3, @vGL dbo.VoucherManualGLLineTVP, @apl dbo.AP_PaymentLineTVP;
INSERT INTO @vInv (BranchCode, InvoiceNo, SequenceReferenceNumber, BatchReferenceID, AmountPaid, Variance, ExpectedBalance)
SELECT (SELECT TOP (1) m.BranchCode FROM dbo.ExpenseMaster AS m WHERE m.SupplierID = @sup AND m.InvoiceNo = @code AND m.BatchReferenceID = @batch ORDER BY m.TRN_SEQ_NO),
       @code, CAST(@batch AS VARCHAR(50)), @batch, @PayAmt, 0, @pay;
DECLARE @vInvBr dbo.VoucherManualInvoiceTVP_v3, @vInvBig dbo.VoucherManualInvoiceTVP_v3, @memoOff dbo.SupplierMemoOffsetLineTVP;
INSERT INTO @vInvBr (BranchCode, InvoiceNo, SequenceReferenceNumber, BatchReferenceID, AmountPaid, Variance, ExpectedBalance)    -- line branch <> the loan's (L4a2)
SELECT @other, InvoiceNo, SequenceReferenceNumber, BatchReferenceID, AmountPaid, Variance, ExpectedBalance FROM @vInv;
INSERT INTO @vInvBig (BranchCode, InvoiceNo, SequenceReferenceNumber, BatchReferenceID, AmountPaid, Variance, ExpectedBalance)   -- all but 1,000.00 (L4i / L4j)
SELECT BranchCode, InvoiceNo, SequenceReferenceNumber, BatchReferenceID, @BigPay, 0, ExpectedBalance FROM @vInv;
INSERT INTO @memoOff (AccountCode, Debit, Credit, Particulars) VALUES ('60323', 0, 100000.00, 'TEST105 memo offset (rolled back)');   -- credit memo 100,000.00 (L4h)
INSERT INTO @apl (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
SELECT LEFT(@branch, 3), @code, es.ExpenseDate, CAST(@batch AS VARCHAR(10)), @batch, CAST(es.Amount AS DECIMAL(12,2)), 1000000.00, 0, 0, 0, es.Description, 0, NULL
FROM dbo.ExpenseSummary AS es WHERE es.BatchReferenceID = @batch AND es.SupplierID = @sup AND es.InvoiceNo = @code;

------------------------------------------------------------------
-- L0 the load: one payable at the loan's current position, listed in Vouchering Telegraphic only
------------------------------------------------------------------
INSERT @r VALUES ('L0a payable = GL (liability, loan branch, all dates) = its supplier ledger = its line = the loan''s balance',
                  CASE WHEN @pay = @amt AND @pay = @pBal AND @pay = @gl AND @pay = @led AND @pay = @line AND @paid = 0 AND @st = 'POSTED'
                            AND (SELECT COUNT(*) FROM dbo.ExpenseSummary WHERE BatchReferenceID = @batch AND SupplierID = @sup AND InvoiceNo = @code AND PostingMode = 'LOAN' AND PayableAccountCode = @liab) = 1
                            AND (SELECT COUNT(*) FROM dbo.ExpenseMaster WHERE BatchReferenceID = @batch AND SupplierID = @sup AND InvoiceNo = @code AND BranchCode = @branch) = 1
                            AND (SELECT COUNT(*) FROM dbo.ExpenseSummary WHERE PostingMode = 'LOAN' AND SupplierID = @sup AND InvoiceNo = @code) = 1 THEN 'PASS' ELSE 'FAIL' END,
                  CONCAT(@before, ' | loan ', @pBal, '; ledger rows ', (SELECT COUNT(*) FROM dbo.SupplierLedger WHERE SupplierKey = @sup AND InvoiceNo = @code AND BatchReferenceID = @batch),
                         ' (', (SELECT STRING_AGG(CONCAT(TransCode, ' ', Credit - Debit), ', ') WITHIN GROUP (ORDER BY TRN_SEQ_NO) FROM dbo.SupplierLedger WHERE SupplierKey = @sup AND InvoiceNo = @code AND BatchReferenceID = @batch), ')'));

DECLARE @lst TABLE (Src VARCHAR(20), SequenceNumber BIGINT, Pay VARCHAR(15), ShipmentNo VARCHAR(50), BranchCode VARCHAR(5), ReferenceNo VARCHAR(150), BatchReferenceID BIGINT,
                    InvoiceNo VARCHAR(150), InvoiceDate DATE, Description VARCHAR(5000), ActualCost DECIMAL(18,2), Balance DECIMAL(18,2), AmountPaid DECIMAL(18,2),
                    Variance DECIMAL(18,2), EWTAmount DECIMAL(18,2), DiscountAmount DECIMAL(18,2), DiscountAccountCode VARCHAR(20), ReturnAllowances DECIMAL(18,2), Type VARCHAR(30));
BEGIN TRY
    INSERT INTO @lst (SequenceNumber, Pay, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, Variance, EWTAmount, DiscountAmount, DiscountAccountCode, ReturnAllowances, Type)
    EXEC dbo.splist_Accounts @parmsupplierid = @sup, @parmispurchase = 0, @parmisexpense = 1;
    UPDATE @lst SET Src = 'expense' WHERE Src IS NULL;
    INSERT INTO @lst (SequenceNumber, Pay, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, Variance, EWTAmount, DiscountAmount, DiscountAccountCode, ReturnAllowances, Type)
    EXEC dbo.splist_Accounts @parmsupplierid = @sup, @parmispurchase = 1, @parmisexpense = 1;
    UPDATE @lst SET Src = 'both' WHERE Src IS NULL;
    INSERT INTO @lst (SequenceNumber, Pay, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, Variance, EWTAmount, DiscountAmount, DiscountAccountCode, ReturnAllowances, Type)
    EXEC dbo.splist_Accounts_OLD_10172026210000 @parmsupplierid = @sup, @parmispurchase = 1, @parmisexpense = 1;
    UPDATE @lst SET Src = 'both-old' WHERE Src IS NULL;
    SELECT @n = COUNT(*), @d1 = MAX(ActualCost), @d2 = MAX(Balance), @s = MAX(BranchCode) FROM @lst WHERE Src = 'expense' AND InvoiceNo = @code AND BatchReferenceID = @batch;
    INSERT @r VALUES ('L0b Vouchering Telegraphic (splist_Accounts expense-only) lists the loan: Actual Cost = Balance = the current value',
                      CASE WHEN @n = 1 AND @d1 = @pBal AND @d2 = @pBal AND @s = @branch THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT(@n, ' row(s) for ', @code, ': ActualCost ', ISNULL(CAST(@d1 AS VARCHAR(30)), '-'), ', Balance ', ISNULL(CAST(@d2 AS VARCHAR(30)), '-'), ', branch ', ISNULL(@s, '-'),
                             ' (loan ', @pBal, '); ', (SELECT COUNT(*) FROM @lst WHERE Src = 'expense'), ' expense rows of ', @sup));
    SELECT @n = COUNT(*) FROM @lst WHERE Src = 'both' AND InvoiceNo = @code AND BatchReferenceID = @batch;
    SELECT @n2 = COUNT(*) FROM @lst WHERE Src = 'both-old' AND InvoiceNo = @code AND BatchReferenceID = @batch;
    INSERT @r VALUES ('L0c Supplier Payment cash / check (splist_Accounts both flags) leaves the loan out',
                      CASE WHEN @n = 0 AND (SELECT COUNT(*) FROM @lst WHERE Src = 'both') + 1 = (SELECT COUNT(*) FROM @lst WHERE Src = 'both-old') THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('new list: ', @n, ' loan row(s) of ', (SELECT COUNT(*) FROM @lst WHERE Src = 'both'), '; old list: ', (SELECT COUNT(*) FROM @lst WHERE Src = 'both-old'), ' rows'));
    INSERT @r VALUES ('L0c-old the old splist_Accounts listed the loan in Supplier Payment cash / check (it would settle it against 20103)',
                      CASE WHEN @n2 = 1 THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END, CONCAT('old both-flags list: ', @n2, ' row(s) for ', @code));
END TRY
BEGIN CATCH
    INSERT @r VALUES ('L0b/L0c splist_Accounts lists', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE()));
END CATCH

DECLARE @unp TABLE (Src VARCHAR(10), ReferenceNumber VARCHAR(10), InvoiceNo VARCHAR(150), BatchReferenceID BIGINT, ExpenseDate DATE, Description VARCHAR(300),
                    Amount DECIMAL(18,2), Balance DECIMAL(18,2), PostingMode VARCHAR(20), BranchCode VARCHAR(5));
BEGIN TRY
    INSERT INTO @unp (ReferenceNumber, InvoiceNo, BatchReferenceID, ExpenseDate, Description, Amount, Balance, PostingMode, BranchCode)
    EXEC dbo.sp_GetUnpaidInvoicesForSupplier @SupplierID = @sup;
    UPDATE @unp SET Src = 'new' WHERE Src IS NULL;
    INSERT INTO @unp (ReferenceNumber, InvoiceNo, BatchReferenceID, ExpenseDate, Description, Amount, Balance, PostingMode, BranchCode)
    EXEC dbo.sp_GetUnpaidInvoicesForSupplier_OLD_10172026210000 @SupplierID = @sup;
    UPDATE @unp SET Src = 'old' WHERE Src IS NULL;
    SELECT @n = COUNT(*) FROM @unp WHERE Src = 'new' AND InvoiceNo = @code AND BatchReferenceID = @batch;
    SELECT @n2 = COUNT(*) FROM @unp WHERE Src = 'old' AND InvoiceNo = @code AND BatchReferenceID = @batch;
    INSERT @r VALUES ('L0d Combined Supplier Voucher (sp_GetUnpaidInvoicesForSupplier) leaves the loan out',
                      CASE WHEN @n = 0 AND (SELECT COUNT(*) FROM @unp WHERE Src = 'new') + 1 = (SELECT COUNT(*) FROM @unp WHERE Src = 'old') THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('new: ', @n, ' loan row(s) of ', (SELECT COUNT(*) FROM @unp WHERE Src = 'new'), '; old: ', (SELECT COUNT(*) FROM @unp WHERE Src = 'old'), ' rows'));
    INSERT @r VALUES ('L0d-old the old sp_GetUnpaidInvoicesForSupplier listed the loan', CASE WHEN @n2 = 1 THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END, CONCAT('old: ', @n2, ' row(s) for ', @code));
END TRY
BEGIN CATCH
    INSERT @r VALUES ('L0d sp_GetUnpaidInvoicesForSupplier', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE()));
END CATCH

SELECT @n = COUNT(*) FROM dbo.view_ExpenseSummary WHERE BatchReferenceID = @batch AND InvoiceNo = @code;
SELECT @n2 = COUNT(*) FROM dbo.view_ExpenseSummary_OLD_10172026210000 WHERE BatchReferenceID = @batch AND InvoiceNo = @code;
SELECT @n3 = (SELECT COUNT(*) FROM dbo.view_ExpenseSummary_OLD_10172026210000) - (SELECT COUNT(*) FROM dbo.view_ExpenseSummary);
INSERT @r VALUES ('L0e old expense screens (view_ExpenseSummary) leave the loan out', CASE WHEN @n = 0 AND @n3 = (SELECT COUNT(*) FROM dbo.ExpenseSummary WHERE PostingMode = 'LOAN') THEN 'PASS' ELSE 'FAIL' END,
                  CONCAT('new view: ', @n, ' loan row(s); old view has ', @n3, ' row(s) more (loan payables ', (SELECT COUNT(*) FROM dbo.ExpenseSummary WHERE PostingMode = 'LOAN'), ')'));
INSERT @r VALUES ('L0e-old the old view_ExpenseSummary listed the loan (list / reverse / edit as an expense)', CASE WHEN @n2 = 1 THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END, CONCAT('old view: ', @n2, ' row(s) for ', @code));

DECLARE @ga TABLE (LoanID INT, LoanCode VARCHAR(30), SupplierID VARCHAR(50), SupplierName VARCHAR(200), Description VARCHAR(300), Currency VARCHAR(5), BranchCode VARCHAR(5), BranchName VARCHAR(200),
                   LiabilityAccount VARCHAR(20), LiabilityAccountName VARCHAR(300), DisplayText VARCHAR(400), LastTxnDate DATE, LastTxnType VARCHAR(15), LastRate DECIMAL(18,6),
                   ForeignBalance DECIMAL(18,2), PhpBalance DECIMAL(18,2), GLBalance DECIMAL(18,2), LossAccount VARCHAR(50), LossAccountName VARCHAR(300), GainAccount VARCHAR(50), GainAccountName VARCHAR(300),
                   PayableInvoiceNo VARCHAR(150), PayableAmount DECIMAL(18,2), PayableBalance DECIMAL(18,2), PayableAmountPaid DECIMAL(18,2));
BEGIN TRY
    INSERT INTO @ga EXEC dbo.sp_Loan_GetAccounts;
    SELECT @s = CONCAT(PayableInvoiceNo, ' ', PayableAmount, '/', PayableBalance, ' paid ', PayableAmountPaid, '; loan ', PhpBalance, '; GL ', GLBalance) FROM @ga WHERE LoanID = @loan;
    INSERT @r VALUES ('L0f Loan Revaluation screen (sp_Loan_GetAccounts) shows the payable''s figures',
                      CASE WHEN EXISTS (SELECT 1 FROM @ga WHERE LoanID = @loan AND PayableInvoiceNo = @code AND PayableAmount = @amt AND PayableBalance = @pay AND PayableAmountPaid = @paid AND GLBalance = @gl AND PhpBalance = @pBal)
                           THEN 'PASS' ELSE 'FAIL' END, ISNULL(@s, 'loan not listed'));
END TRY
BEGIN CATCH
    INSERT @r VALUES ('L0f sp_Loan_GetAccounts', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE()));
END CATCH

SELECT @n = COUNT(*) FROM #apBase WHERE Inv = @code OR Ref = 'EXPENSE ' + @payRef;
INSERT @r VALUES ('L0g AP Exception Center: no finding on the loan payable', CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END,
                  CONCAT(@n, ' finding(s) for ', @code, ' / EXPENSE ', @payRef, '; ', (SELECT COUNT(*) FROM #apBase), ' AP finding(s) in all before the tests (the baseline the cases compare with)'));

------------------------------------------------------------------
-- L1 revaluation at the next month end, foreign balance unchanged: the payable moves with it (old proc: it stays behind)
------------------------------------------------------------------
IF @canReval = 0
    INSERT @r VALUES ('L1 revaluation moves the payable', 'SKIP', CONCAT('next revaluation ', CONVERT(VARCHAR(10), @revalDate, 120), ' is after this month'));
ELSE
BEGIN
    SET @k = 1;
    WHILE @k <= 2
    BEGIN
        SET @run = CASE @k WHEN 1 THEN 'new' ELSE 'old' END;
        SELECT @e = NULL, @em = NULL, @stage = 'post';
        BEGIN TRAN;
        BEGIN TRY
            IF @k = 1 EXEC dbo.spu_Loan_PostRevaluation @LoanID = @loan, @RevalDate = @revalDate, @Rate = @Rate, @ExpectedPhpBalance = @pBal, @User = @user, @ControlNo = @ctl;
            ELSE      EXEC dbo.spu_Loan_PostRevaluation_OLD_10172026210000 @LoanID = @loan, @RevalDate = @revalDate, @Rate = @Rate, @ExpectedPhpBalance = @pBal, @User = @user, @ControlNo = @ctl;
            SET @stage = 'read';
            EXEC sp_executesql @qTie, @pTie, @batch, @sup, @code, @liab, @branch, @loan, @pay OUTPUT, @amt OUTPUT, @paid OUTPUT, @st OUTPUT, @gl OUTPUT, @led OUTPUT, @line OUTPUT, @lines OUTPUT, @lt OUTPUT;
            SET @tie = CONCAT('payable ', @amt, '/', @pay, ' ', @st, '; GL ', @gl, '; ledger ', @led, '; line ', @lines);
            SELECT @txn = TxnID, @tn = TicketNumber, @tref = ReferenceNumber, @d1 = PhpChange, @d2 = PhpBalance FROM dbo.LoanTransaction WHERE LoanID = @loan AND TxnDate = @revalDate AND Status = 'POSTED';
            SELECT @s = STRING_AGG(CONCAT(TransCode, ' D', Debit, ' C', Credit, ' ', PaymentType), ', ') FROM dbo.SupplierLedger
            WHERE SupplierKey = @sup AND InvoiceNo = @code AND BatchReferenceID = @batch AND ReferenceNumber = @tref;
            INSERT @fp SELECT 'L1', @run, 'LT', CONCAT(TxnType, '|', Rate, '|', PrevRate, '|', ForeignChange, '|', PhpChange, '|', ForeignBalance, '|', PhpBalance, '|', Description, '|', Status, '|', ControlNo)
                       FROM dbo.LoanTransaction WHERE LoanID = @loan AND TxnDate = @revalDate AND Status = 'POSTED';
            INSERT @fp SELECT 'L1', @run, 'TM', CONCAT(BranchCode, '|', Origin, '|', Mnemonic, '|', CONVERT(VARCHAR(10), TicketDate, 120), '|', ReferenceKey, '|', Owner, '|', Particulars, '|', Status)
                       FROM dbo.TicketMaster WHERE TicketNumber = @tn AND ReferenceNumber = @tref;
            INSERT @fp SELECT 'L1', @run, 'TD', STRING_AGG(CONCAT(BranchCode, ':', AccountCode, ':', Debit, ':', Credit, ':', CONVERT(VARCHAR(10), TicketDate, 120)), ',') WITHIN GROUP (ORDER BY AccountCode)
                       FROM dbo.TicketDetails WHERE TicketNumber = @tn AND ReferenceNumber = @tref;
            IF @k = 1 EXEC sp_executesql @qAP, @pAP, @nAP OUTPUT, @apList OUTPUT;
        END TRY
        BEGIN CATCH
            SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
        END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF @e IS NOT NULL
            INSERT @r VALUES (CONCAT('L1 ', @run, ' revaluation'), 'ERROR', CONCAT('at ', @stage, ': ', @e, ' ', @em));
        ELSE IF @k = 1
            INSERT @r VALUES ('L1a revaluation, balance unchanged: payable Amount = Balance = new value = GL = ledger = line, LOAN-REVAL row',
                              CASE WHEN @pay = @exp1 AND @amt = @exp1 AND @gl = @exp1 AND @led = @exp1 AND @line = @exp1 AND @d1 = @chg1 AND @d2 = @exp1 AND @st = 'POSTED'
                                        AND @s = CONCAT('LOAN-REVAL D', CAST(CASE WHEN @chg1 < 0 THEN -@chg1 ELSE 0 END AS MONEY), ' C', CAST(CASE WHEN @chg1 > 0 THEN @chg1 ELSE 0 END AS MONEY), ' REVALUATION')
                                        AND @nAP = 0 THEN 'PASS' ELSE 'FAIL' END,
                              CONCAT(CONVERT(VARCHAR(10), @revalDate, 120), ' @', @Rate, ': change ', @d1, ', loan ', @d2, ' (expected ', @exp1, ') | ', @tie, ' | ledger row ', ISNULL(@s, 'none'),
                                     ' | new AP findings ', @nAP, ' (', @apList, ')'));
        ELSE
            INSERT @r VALUES ('L1b old proc: the same revaluation leaves the payable at the old value (payable <> GL)',
                              CASE WHEN @pay = @pBal AND @amt = @pBal AND @gl = @exp1 AND @led = @pBal AND @s IS NULL THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END,
                              CONCAT('old proc: change ', @d1, ' | ', @tie, ' | ledger row ', ISNULL(@s, 'none'), ' | payable - GL = ', @pay - @gl));
        SET @k += 1;
    END
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE Cs = 'L1' AND Run = 'old' EXCEPT SELECT Item, Val FROM @fp WHERE Cs = 'L1' AND Run = 'new') AS x;
    SELECT @n2 = COUNT(*) FROM @fp WHERE Cs = 'L1' AND Run = 'new' AND Val IS NOT NULL;
    INSERT @r VALUES ('L1c old = new: the revaluation ticket and loan entry are the same (only the payable changed)',
                      CASE WHEN @n = 0 AND @n2 = 3 AND (SELECT COUNT(*) FROM @fp WHERE Cs = 'L1' AND Run = 'old' AND Val IS NOT NULL) = 3 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT(@n, ' of 3 footprint rows differ (loan entry, ticket master, ticket lines); new ticket lines ', (SELECT Val FROM @fp WHERE Cs = 'L1' AND Run = 'new' AND Item = 'TD')));
END

------------------------------------------------------------------
-- L2 reversal of the L1 revaluation: the payable goes back (old reversal proc: it stays at the revalued value)
------------------------------------------------------------------
IF @canReval = 0
    INSERT @r VALUES ('L2 reversal moves the payable back', 'SKIP', 'no revaluation to post (see L1)');
ELSE
BEGIN
    SET @k = 1;
    WHILE @k <= 2
    BEGIN
        SET @run = CASE @k WHEN 1 THEN 'new' ELSE 'old' END;
        SELECT @e = NULL, @em = NULL, @stage = 'post', @txn = NULL;
        BEGIN TRAN;
        BEGIN TRY
            EXEC dbo.spu_Loan_PostRevaluation @LoanID = @loan, @RevalDate = @revalDate, @Rate = @Rate, @ExpectedPhpBalance = @pBal, @User = @user, @ControlNo = @ctl;
            SELECT @txn = TxnID, @tref = ReferenceNumber FROM dbo.LoanTransaction WHERE LoanID = @loan AND TxnDate = @revalDate AND Status = 'POSTED';
            SET @stage = 'reverse';
            IF @k = 1 EXEC dbo.spu_Loan_ReverseRevaluation @TxnID = @txn, @User = @user, @Reason = 'TEST105 L2 (rolled back)';
            ELSE      EXEC dbo.spu_Loan_ReverseRevaluation_OLD_10172026210000 @TxnID = @txn, @User = @user, @Reason = 'TEST105 L2 (rolled back)';
            SET @stage = 'read';
            EXEC sp_executesql @qTie, @pTie, @batch, @sup, @code, @liab, @branch, @loan, @pay OUTPUT, @amt OUTPUT, @paid OUTPUT, @st OUTPUT, @gl OUTPUT, @led OUTPUT, @line OUTPUT, @lines OUTPUT, @lt OUTPUT;
            SET @tie = CONCAT('payable ', @amt, '/', @pay, ' ', @st, '; GL ', @gl, '; ledger ', @led, '; line ', @lines);
            SELECT @s = STRING_AGG(CONCAT(TransCode, ' D', Debit, ' C', Credit, ' ', PaymentType, ' ', CONVERT(VARCHAR(10), TransactionDate, 120)), ', ') WITHIN GROUP (ORDER BY TRN_SEQ_NO)
            FROM dbo.SupplierLedger WHERE SupplierKey = @sup AND InvoiceNo = @code AND BatchReferenceID = @batch AND ReferenceNumber = @tref;
            SELECT @st = CONCAT(@st, ' / loan entry ', Status) FROM dbo.LoanTransaction WHERE TxnID = @txn;
            IF @k = 1 EXEC sp_executesql @qAP, @pAP, @nAP OUTPUT, @apList OUTPUT;
        END TRY
        BEGIN CATCH
            SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
        END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF @e IS NOT NULL
            INSERT @r VALUES (CONCAT('L2 ', @run, ' reversal'), 'ERROR', CONCAT('at ', @stage, ': ', @e, ' ', @em));
        ELSE IF @k = 1
            INSERT @r VALUES ('L2a reversal of the L1 revaluation: payable back = GL = ledger = line, ledger row the other way dated like it',
                              CASE WHEN @pay = @pBal AND @amt = @pBal AND @gl = @pBal AND @led = @pBal AND @line = @pBal AND @st = 'POSTED / loan entry REVERSED'
                                        AND @s LIKE CONCAT('%REVERSAL ', CONVERT(VARCHAR(10), @revalDate, 120)) AND @nAP = 0 THEN 'PASS' ELSE 'FAIL' END,
                              CONCAT(@tie, ' | ', @st, ' | ledger rows of ref ', @tref, ': ', ISNULL(@s, 'none'), ' | new AP findings ', @nAP, ' (', @apList, ')'));
        ELSE
            INSERT @r VALUES ('L2b old reversal proc: the payable stays at the revalued value (payable <> GL)',
                              CASE WHEN @pay = @exp1 AND @gl = @pBal THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END,
                              CONCAT('old proc: ', @tie, ' | payable - GL = ', @pay - @gl));
        SET @k += 1;
    END
END

-- L2c reversal of the loan's own last revaluation (a real one): the payable goes back to the entry before it
IF @lastType <> 'REVALUATION' OR (@glLock IS NOT NULL AND @glLock >= @lastDate)
    INSERT @r VALUES ('L2c reversal of the loan''s last real revaluation', 'SKIP', CONCAT('last entry is ', @lastType, ' ', CONVERT(VARCHAR(10), @lastDate, 120), ' (GL locked through ', ISNULL(CONVERT(VARCHAR(10), @glLock, 120), '-'), ')'));
ELSE
BEGIN
    SELECT @e = NULL, @em = NULL, @stage = 'reverse';
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.spu_Loan_ReverseRevaluation @TxnID = @lastTxn, @User = @user, @Reason = 'TEST105 L2c (rolled back)';
        SET @stage = 'read';
        EXEC sp_executesql @qTie, @pTie, @batch, @sup, @code, @liab, @branch, @loan, @pay OUTPUT, @amt OUTPUT, @paid OUTPUT, @st OUTPUT, @gl OUTPUT, @led OUTPUT, @line OUTPUT, @lines OUTPUT, @lt OUTPUT;
        SET @tie = CONCAT('payable ', @amt, '/', @pay, ' ', @st, '; GL ', @gl, '; ledger ', @led, '; line ', @lines);
        EXEC sp_executesql @qAP, @pAP, @nAP OUTPUT, @apList OUTPUT;
    END TRY
    BEGIN CATCH
        SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @d1 = @pBal - @lastChg;
    IF @e IS NOT NULL
        INSERT @r VALUES ('L2c reversal of the loan''s last real revaluation', 'ERROR', CONCAT('at ', @stage, ': ', @e, ' ', @em));
    ELSE
        INSERT @r VALUES ('L2c reversal of the loan''s last real revaluation: payable back to the entry before it = GL = ledger',
                          CASE WHEN @pay = @d1 AND @amt = @d1 AND @gl = @d1 AND @led = @d1 AND @line = @d1 AND @nAP = 0 THEN 'PASS' ELSE 'FAIL' END,
                          CONCAT('reversed TxnID ', @lastTxn, ' (', CONVERT(VARCHAR(10), @lastDate, 120), ', change ', @lastChg, '): expected ', @d1, ' | ', @tie, ' | new AP findings ', @nAP, ' (', @apList, ')'));
END

------------------------------------------------------------------
-- L3 telegraphic partial payment of the loan from its own branch (old = new), then a revaluation of the new foreign balance
------------------------------------------------------------------
IF @canPay = 0
    INSERT @r VALUES ('L3 telegraphic payment of the loan', 'SKIP', CONCAT('bank ', @bank, ' not a bank account, its recon month ', CONVERT(VARCHAR(7), @payDate, 120), ' locked, or pay date not after the last loan entry'));
ELSE
BEGIN
    SET @k = 1;
    WHILE @k <= 2
    BEGIN
        SET @run = CASE @k WHEN 1 THEN 'new' ELSE 'old' END;
        SELECT @e = NULL, @em = NULL, @stage = 'pay';
        BEGIN TRAN;
        BEGIN TRY
            IF @k = 1
                EXEC dbo.sp_PostVoucherManual @parmrefno = @refA, @parmvoucherid = @vidA, @parmsupplierid = @sup, @parmsuppliername = @supName, @parmpaymethod = 'EXPENSE',
                     @parmvouchertype = 'TELEGRAPHIC', @parmcheckno = NULL, @parmcreditglcode = @bank, @parmcontrolno = @ctl, @parmvoucherdate = @payDate,
                     @parmremarks = 'TEST105 L3 loan principal (rolled back)', @parmpreparedby = @user, @parmbranch = @branch, @InvoiceLines = @vInv, @GLLines = @vGL;
            ELSE
                EXEC dbo.sp_PostVoucherManual_OLD_10172026210000 @parmrefno = @refA, @parmvoucherid = @vidA, @parmsupplierid = @sup, @parmsuppliername = @supName, @parmpaymethod = 'EXPENSE',
                     @parmvouchertype = 'TELEGRAPHIC', @parmcheckno = NULL, @parmcreditglcode = @bank, @parmcontrolno = @ctl, @parmvoucherdate = @payDate,
                     @parmremarks = 'TEST105 L3 loan principal (rolled back)', @parmpreparedby = @user, @parmbranch = @branch, @InvoiceLines = @vInv, @GLLines = @vGL;
            SET @stage = 'read';
            EXEC sp_executesql @qTie, @pTie, @batch, @sup, @code, @liab, @branch, @loan, @pay OUTPUT, @amt OUTPUT, @paid OUTPUT, @st OUTPUT, @gl OUTPUT, @led OUTPUT, @line OUTPUT, @lines OUTPUT, @lt OUTPUT;
            SET @tie = CONCAT('payable ', @amt, '/', @pay, ' paid ', @paid, ' ', @st, '; GL ', @gl, '; ledger ', @led, '; line ', @lines);
            INSERT @fp EXEC sp_executesql @qV, @pV, @cs = 'L3', @run = @run, @ref = @refA, @vid = @vidA, @batch = @batch, @sup = @sup, @code = @code;
            IF @k = 1
            BEGIN
                SELECT @s = (SELECT Val FROM @fp WHERE Cs = 'L3' AND Run = 'new' AND Item = 'TD'), @s2 = (SELECT Val FROM @fp WHERE Cs = 'L3' AND Run = 'new' AND Item = 'SL');
                EXEC sp_executesql @qAP, @pAP, @nAP OUTPUT, @apList OUTPUT;
                SET @d1 = @pBal - @PayAmt;
                SET @x1 = CONCAT('2|', @branch, ':', @bank, ':0.00:', @PayAmt, ':', CONVERT(VARCHAR(10), @payDate, 120), ',', @branch, ':', @liab, ':', @PayAmt, ':0.00:', CONVERT(VARCHAR(10), @payDate, 120));
                INSERT @r VALUES ('L3a telegraphic partial payment, loan''s branch: DR liability / CR bank, payable + line PARTIAL, ledger debit',
                                  CASE WHEN @s = @x1 AND @pay = @d1 AND @amt = @pBal AND @paid = @PayAmt AND @st = 'PARTIAL' AND @gl = @d1 AND @led = @d1 AND @line = @d1
                                            AND @lines = CONCAT(@branch, ':', @pBal, '|', @PayAmt, '|', @d1, '|PARTIAL')
                                            AND @s2 LIKE CONCAT('PV-MANUAL:', CAST(@PayAmt AS MONEY), ':0.00:', @code, ':', @batch, ':PARTIAL:%') AND @nAP = 0 THEN 'PASS' ELSE 'FAIL' END,
                                  CONCAT('ticket ', ISNULL(@s, 'none'), ' | ', @tie, ' | ledger ', ISNULL(@s2, 'none'), ' | new AP findings ', @nAP, ' (', @apList, ')'));
            END
        END TRY
        BEGIN CATCH
            SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
        END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF @e IS NOT NULL INSERT @r VALUES (CONCAT('L3 ', @run, ' telegraphic payment'), 'ERROR', CONCAT('at ', @stage, ': ', @e, ' ', @em));
        SET @k += 1;
    END
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE Cs = 'L3' AND Run = 'old' EXCEPT SELECT Item, Val FROM @fp WHERE Cs = 'L3' AND Run = 'new') AS x;
    SELECT @n2 = COUNT(*) FROM @fp WHERE Cs = 'L3' AND Run = 'new' AND Val IS NOT NULL;
    INSERT @r VALUES ('L3b old = new: a loan payment from the loan''s own branch posts the same rows as before [105]',
                      CASE WHEN @n = 0 AND @n2 = 9 AND (SELECT COUNT(*) FROM @fp WHERE Cs = 'L3' AND Run = 'old' AND Val IS NOT NULL) = 9 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT(@n, ' of 9 footprint rows differ (ticket lines, ticket, payable, line, ledger, payment detail, TPAP, voucher, recon OC); new recon ', (SELECT Val FROM @fp WHERE Cs = 'L3' AND Run = 'new' AND Item = 'BSR')));

    -- L3c the payment, then the month-end revaluation of the new foreign balance ([81] changed balance)
    IF @canL3c = 0
        INSERT @r VALUES ('L3c payment then revaluation of the new balance', 'SKIP', CONCAT('payment ', @PayAmt, ' / ', @ForeignPaid, ' is not within 20% of the last rate ', @lastRate, ', or no revaluation date'));
    ELSE
    BEGIN
        SELECT @e = NULL, @em = NULL, @stage = 'pay';
        BEGIN TRAN;
        BEGIN TRY
            EXEC dbo.sp_PostVoucherManual @parmrefno = @refA, @parmvoucherid = @vidA, @parmsupplierid = @sup, @parmsuppliername = @supName, @parmpaymethod = 'EXPENSE',
                 @parmvouchertype = 'TELEGRAPHIC', @parmcheckno = NULL, @parmcreditglcode = @bank, @parmcontrolno = @ctl, @parmvoucherdate = @payDate,
                 @parmremarks = 'TEST105 L3c loan principal (rolled back)', @parmpreparedby = @user, @parmbranch = @branch, @InvoiceLines = @vInv, @GLLines = @vGL;
            SET @stage = 'revalue';
            EXEC dbo.spu_Loan_PostRevaluation @LoanID = @loan, @RevalDate = @revalDate, @Rate = @Rate, @ExpectedPhpBalance = @pBal, @User = @user, @ForeignBalance = @newF3, @ControlNo = @ctl;
            SET @stage = 'read';
            EXEC sp_executesql @qTie, @pTie, @batch, @sup, @code, @liab, @branch, @loan, @pay OUTPUT, @amt OUTPUT, @paid OUTPUT, @st OUTPUT, @gl OUTPUT, @led OUTPUT, @line OUTPUT, @lines OUTPUT, @lt OUTPUT;
            SET @tie = CONCAT('payable ', @amt, '/', @pay, ' paid ', @paid, ' ', @st, '; GL ', @gl, '; ledger ', @led, '; line ', @lines);
            SELECT @d1 = PhpChange, @d2 = ForeignBalance FROM dbo.LoanTransaction WHERE LoanID = @loan AND TxnDate = @revalDate AND Status = 'POSTED';
            SELECT @x2 = STRING_AGG(CONCAT(BranchCode, ':', Amount, '|', ISNULL(AmountPaid, 0), '|', Balance), ',') FROM dbo.ExpenseMaster WHERE BatchReferenceID = @batch AND SupplierID = @sup AND InvoiceNo = @code;
            EXEC sp_executesql @qAP, @pAP, @nAP OUTPUT, @apList OUTPUT;
            SET @stage = 'list';
            DELETE FROM @lst WHERE Src = 'l3c';
            INSERT INTO @lst (SequenceNumber, Pay, ShipmentNo, BranchCode, ReferenceNo, BatchReferenceID, InvoiceNo, InvoiceDate, Description, ActualCost, Balance, AmountPaid, Variance, EWTAmount, DiscountAmount, DiscountAccountCode, ReturnAllowances, Type)
            EXEC dbo.splist_Accounts @parmsupplierid = @sup, @parmispurchase = 0, @parmisexpense = 1;
            UPDATE @lst SET Src = 'l3c' WHERE Src IS NULL;
            SELECT @x1 = CONCAT('Vouchering Telegraphic shows ActualCost ', MAX(ActualCost), ' / Balance ', MAX(Balance), ' / paid ', MAX(AmountPaid), ' (', COUNT(*), ' row)'),
                   @n = SUM(CASE WHEN ActualCost = @exp3 AND Balance = @exp3 AND AmountPaid = @PayAmt THEN 1 ELSE 0 END)
            FROM @lst WHERE Src = 'l3c' AND InvoiceNo = @code AND BatchReferenceID = @batch;
        END TRY
        BEGIN CATCH
            SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
        END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @d3 = @pBal + @chg3;   -- v2: Amount (the gross) moves by the change, Balance = the new value
        IF @e IS NOT NULL
            INSERT @r VALUES ('L3c payment then revaluation of the new balance', 'ERROR', CONCAT('at ', @stage, ': ', @e, ' ', @em));
        ELSE
            INSERT @r VALUES ('L3c payment, then revaluation of the new balance: Balance = new value = GL = ledger = line, Amount + change',
                              CASE WHEN @pay = @exp3 AND @amt = @d3 AND @gl = @exp3 AND @led = @exp3 AND @line = @exp3 AND @d1 = @chg3 AND @d2 = @newF3 AND @st = 'PARTIAL' AND @paid = @PayAmt
                                        AND @x2 = CONCAT(@branch, ':', @d3, '|', @PayAmt, '|', @exp3) AND @n = 1 AND @nAP = 0
                                   THEN 'PASS' ELSE 'FAIL' END,
                              CONCAT(@cur, ' ', @newF3, ' @', @Rate, ' = ', @exp3, ' (change ', @d1, ', expected ', @chg3, '; Amount expected ', @d3, ') | ', @tie, ' | line ', @x2, ' | ', @x1,
                                     ' | new AP findings ', @nAP, ' (', @apList, ')'));
    END
END

------------------------------------------------------------------
-- L4 refusals (one per transaction; the proc's CATCH rolls back the whole test transaction)
------------------------------------------------------------------
-- L4a the loan paid from another branch: 58040 (old proc: posts, and the loan's branch GL no longer matches the payable)
IF @canPay = 0 OR @other IS NULL
    INSERT @r VALUES ('L4a loan paid from another branch: 58040', 'SKIP', 'no payment fixture (see L3) or no other branch');
ELSE
BEGIN
    SELECT @e = NULL, @em = NULL, @stage = 'pay';
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_PostVoucherManual @parmrefno = @refB, @parmvoucherid = @vidB, @parmsupplierid = @sup, @parmsuppliername = @supName, @parmpaymethod = 'EXPENSE',
             @parmvouchertype = 'TELEGRAPHIC', @parmcheckno = NULL, @parmcreditglcode = @bank, @parmcontrolno = @ctl, @parmvoucherdate = @payDate,
             @parmremarks = 'TEST105 L4a (rolled back)', @parmpreparedby = @user, @parmbranch = @other, @InvoiceLines = @vInv, @GLLines = @vGL;
        SET @stage = 'not refused';
    END TRY
    BEGIN CATCH
        SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
    END CATCH
    SELECT @tc = @@TRANCOUNT;
    IF @@TRANCOUNT > 0 ROLLBACK;
    EXEC sp_executesql @qTie, @pTie, @batch, @sup, @code, @liab, @branch, @loan, @pay OUTPUT, @amt OUTPUT, @paid OUTPUT, @st OUTPUT, @gl OUTPUT, @led OUTPUT, @line OUTPUT, @lines OUTPUT, @lt OUTPUT;
    SET @now = CONCAT('payable ', @amt, '/', @pay, ' paid ', @paid, ' ', @st, '; GL ', @gl, '; ledger ', @led, '; line ', @lines, '; loan entries ', @lt);
    SELECT @n = (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber = @refB) + (SELECT COUNT(*) FROM dbo.TelegraphicVoucher WHERE ReferenceNumber = @refB)
              + (SELECT COUNT(*) FROM dbo.APPaymentDetails WHERE ReferenceNumber = @refB) + (SELECT COUNT(*) FROM dbo.SupplierLedger WHERE ReferenceNumber = @refB);
    INSERT @r VALUES (CONCAT('L4a loan paid from branch ', @other, ' (not the loan''s ', @branch, '): refused 58040, nothing changed'),
                      CASE WHEN @stage = 'pay' AND @e = 58040 AND @tc = 0 AND @n = 0 AND @now = @before THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('error ', ISNULL(CAST(@e AS VARCHAR(10)), 'none'), ' ', ISNULL(@em, '(not refused)'), ' | @@TRANCOUNT ', @tc, ', rows under ', @refB, ' ', @n, ', loan state unchanged: ', CASE WHEN @now = @before THEN 'yes' ELSE CONCAT('NO: ', @now) END));

    -- the old proc pays it from the other branch; the next revaluation then refuses 62030 (the payable no longer = the loan's GL)
    SELECT @e = NULL, @em = NULL, @stage = 'pay', @x1 = NULL;
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_PostVoucherManual_OLD_10172026210000 @parmrefno = @refB, @parmvoucherid = @vidB, @parmsupplierid = @sup, @parmsuppliername = @supName, @parmpaymethod = 'EXPENSE',
             @parmvouchertype = 'TELEGRAPHIC', @parmcheckno = NULL, @parmcreditglcode = @bank, @parmcontrolno = @ctl, @parmvoucherdate = @payDate,
             @parmremarks = 'TEST105 L4a old (rolled back)', @parmpreparedby = @user, @parmbranch = @other, @InvoiceLines = @vInv, @GLLines = @vGL;
        SET @stage = 'read';
        EXEC sp_executesql @qTie, @pTie, @batch, @sup, @code, @liab, @branch, @loan, @pay OUTPUT, @amt OUTPUT, @paid OUTPUT, @st OUTPUT, @gl OUTPUT, @led OUTPUT, @line OUTPUT, @lines OUTPUT, @lt OUTPUT;
        SET @tie = CONCAT('payable ', @amt, '/', @pay, ' paid ', @paid, ' ', @st, '; GL ', @branch, ' ', @gl, '; ledger ', @led);
        SELECT @d1 = CAST(ISNULL(SUM(ISNULL(Credit, 0) - ISNULL(Debit, 0)), 0) AS DECIMAL(18,2)) FROM dbo.TicketDetails WHERE AccountCode = @liab AND BranchCode = @other AND ReferenceNumber = @refB;
        IF @canReval = 1
        BEGIN
            SET @stage = 'revalue';
            BEGIN TRY
                EXEC dbo.spu_Loan_PostRevaluation @LoanID = @loan, @RevalDate = @revalDate, @Rate = @Rate, @ExpectedPhpBalance = @pBal, @User = @user, @ControlNo = @ctl;
                SET @x1 = 'the next revaluation was NOT refused';
            END TRY
            BEGIN CATCH
                SET @x1 = CONCAT('the next revaluation is refused ', ERROR_NUMBER());
            END CATCH
        END
        SET @stage = 'done';
    END TRY
    BEGIN CATCH
        SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    IF @e IS NOT NULL
        INSERT @r VALUES ('L4a-old old proc: loan paid from another branch', 'ERROR', CONCAT('at ', @stage, ': ', @e, ' ', @em));
    ELSE
        INSERT @r VALUES ('L4a-old old proc pays the loan from another branch: the payable drops, the loan''s branch GL does not',
                          CASE WHEN @pay = @pBal - @PayAmt AND @gl = @pBal THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END,
                          CONCAT('old proc on ', @other, ': ', @tie, ' | ', @liab, ' on ', @other, ' ', @d1, ' | ', ISNULL(@x1, 'no revaluation tried')));
END

-- L4b / L4c the loan through the cash / check payment procs: 60540 (V2 and the legacy proc)
SET @k = 1;
WHILE @k <= 2
BEGIN
    SELECT @e = NULL, @em = NULL, @stage = 'pay';
    BEGIN TRAN;
    BEGIN TRY
        IF @k = 1
            EXEC dbo.sp_AddPaymentSupplierCompound_V2 @parmrefno = @refC, @parmvoucherid = @vidC, @parmsupplierid = @sup, @parmsuppliername = @supName,
                 @parmcheckamount = 1000000.00, @parmcheckcoding = '', @parmcheckno = '', @parmcontrolno = @ctl, @parmcheckdate = @payDate,
                 @parmcheckremarks = 'TEST105 L4b (rolled back)', @parmpreparedby = @user, @parmglcode = @bank, @parmpaymethod = 'EXPENSE',
                 @parmforliquidation = 0, @parmvouchertype = 'CASH', @Lines = @apl, @parmPayingBranch = @branch;
        ELSE
            EXEC dbo.sp_AddPaymentSupplierCompound @parmrefno = @refD, @parmvoucherid = @vidD, @parmsupplierid = @sup, @parmsuppliername = @supName,
                 @parmcheckamount = 1000000.00, @parmcheckcoding = '', @parmcheckno = '', @parmcontrolno = @ctl, @parmcheckdate = @payDate,
                 @parmcheckremarks = 'TEST105 L4c (rolled back)', @parmpreparedby = @user, @parmglcode = @bank, @parmpaymethod = 'EXPENSE',
                 @parmforliquidation = 0, @parmvouchertype = 'CASH', @Lines = @apl, @parmPayingBranch = @branch;
        SET @stage = 'not refused';
    END TRY
    BEGIN CATCH
        SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
    END CATCH
    SELECT @tc = @@TRANCOUNT;
    IF @@TRANCOUNT > 0 ROLLBACK;
    EXEC sp_executesql @qTie, @pTie, @batch, @sup, @code, @liab, @branch, @loan, @pay OUTPUT, @amt OUTPUT, @paid OUTPUT, @st OUTPUT, @gl OUTPUT, @led OUTPUT, @line OUTPUT, @lines OUTPUT, @lt OUTPUT;
    SET @now = CONCAT('payable ', @amt, '/', @pay, ' paid ', @paid, ' ', @st, '; GL ', @gl, '; ledger ', @led, '; line ', @lines, '; loan entries ', @lt);
    SELECT @n = (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber IN (@refC, @refD)) + (SELECT COUNT(*) FROM dbo.CashVoucher WHERE ReferenceNumber IN (@refC, @refD))
              + (SELECT COUNT(*) FROM dbo.TransactionPaymentAP WHERE ReferenceNumber IN (99933, 99934)) + (SELECT COUNT(*) FROM dbo.APPaymentDetails WHERE ReferenceNumber IN (@refC, @refD));
    INSERT @r VALUES (CASE @k WHEN 1 THEN 'L4b sp_AddPaymentSupplierCompound_V2 with the loan as an EXPENSE line: refused 60540, nothing changed'
                              ELSE        'L4c legacy sp_AddPaymentSupplierCompound with the loan: refused 60540, nothing changed' END,
                      CASE WHEN @stage = 'pay' AND @e = 60540 AND @tc = 0 AND @n = 0 AND @now = @before THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('error ', ISNULL(CAST(@e AS VARCHAR(10)), 'none'), ' ', ISNULL(LEFT(@em, 200), '(not refused)'), ' | @@TRANCOUNT ', @tc, ', rows under ', CASE @k WHEN 1 THEN @refC ELSE @refD END, ' ', @n,
                             ', loan state unchanged: ', CASE WHEN @now = @before THEN 'yes' ELSE CONCAT('NO: ', @now) END));
    SET @k += 1;
END

-- L4b-old the old V2 settles the loan through its BATCH path (against the expense AP account, not the loan's)
SELECT @e = NULL, @em = NULL, @stage = 'pay';
BEGIN TRAN;
BEGIN TRY
    EXEC dbo.sp_AddPaymentSupplierCompound_V2_OLD_10172026210000 @parmrefno = @refC, @parmvoucherid = @vidC, @parmsupplierid = @sup, @parmsuppliername = @supName,
         @parmcheckamount = 1000000.00, @parmcheckcoding = '', @parmcheckno = '', @parmcontrolno = @ctl, @parmcheckdate = @payDate,
         @parmcheckremarks = 'TEST105 L4b old (rolled back)', @parmpreparedby = @user, @parmglcode = @bank, @parmpaymethod = 'EXPENSE',
         @parmforliquidation = 0, @parmvouchertype = 'CASH', @Lines = @apl, @parmPayingBranch = @branch;
    SET @stage = 'read';
    EXEC sp_executesql @qTie, @pTie, @batch, @sup, @code, @liab, @branch, @loan, @pay OUTPUT, @amt OUTPUT, @paid OUTPUT, @st OUTPUT, @gl OUTPUT, @led OUTPUT, @line OUTPUT, @lines OUTPUT, @lt OUTPUT;
    SET @tie = CONCAT('payable ', @amt, '/', @pay, ' paid ', @paid, ' ', @st, '; GL ', @liab, ' ', @gl, '; ledger ', @led);
    SELECT @s = STRING_AGG(CONCAT(BranchCode, ':', AccountCode, ':', Debit, ':', Credit), ',') WITHIN GROUP (ORDER BY BranchCode, AccountCode) FROM dbo.TicketDetails WHERE ReferenceNumber = @refC;
END TRY
BEGIN CATCH
    SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e IS NOT NULL
    INSERT @r VALUES ('L4b-old old V2 with the loan', 'SKIP', CONCAT('the old V2 refused it for its own reason at ', @stage, ': ', @e, ' ', LEFT(@em, 250)));
ELSE
    INSERT @r VALUES ('L4b-old old V2 settles the loan in the cash / check path: payable down, the loan account untouched',
                      CASE WHEN @pay < @pBal AND @gl = @pBal THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END,
                      CONCAT('old V2: ', @tie, ' | ticket lines ', ISNULL(@s, 'none')));

-- L4d revaluation when the payable was changed by hand: 62030
-- L4e reversal (of the loan's last revaluation) when the payable was changed by hand: 62030
-- L4f revaluation when the payable has two lines: 62031
-- L4g revaluation when the payable's supplier ledger is off: post-check 62032
-- L4h supplier adjustment memo on the loan: 58041
-- L4i revaluation (a gain) after a payment of all but 1,000.00 dated after the revaluation date: 62033 (payable below 0)
-- L4j reversal of the last revaluation (a loss) after a payment of all but 1,000.00: 62033
-- L4k telegraphic voucher on the loan's branch but with the invoice line on another branch: 58040
SET @k = 1;
WHILE @k <= 8
BEGIN
    IF (@k IN (1, 3, 4) AND @canReval = 0) OR (@k IN (2, 7) AND (@lastType <> 'REVALUATION' OR (@glLock IS NOT NULL AND @glLock >= @lastDate)))
       OR (@k = 6 AND @canLate = 0) OR (@k = 7 AND (@canPay = 0 OR @lastChg <= 1000.00)) OR (@k = 8 AND (@canPay = 0 OR @other IS NULL))
        INSERT @r VALUES (CASE @k WHEN 1 THEN 'L4d revaluation, payable changed by hand: 62030' WHEN 2 THEN 'L4e reversal, payable changed by hand: 62030'
                                  WHEN 3 THEN 'L4f revaluation, payable with two lines: 62031' WHEN 4 THEN 'L4g revaluation, supplier ledger off: 62032'
                                  WHEN 5 THEN 'L4h memo on the loan: 58041' WHEN 6 THEN 'L4i revaluation below 0 after a late payment: 62033'
                                  WHEN 7 THEN 'L4j reversal below 0 after a payment: 62033' ELSE 'L4k invoice line on another branch: 58040' END, 'SKIP',
                          CONCAT('no fixture for it (revaluation date ', CONVERT(VARCHAR(10), @revalDate, 120), ', last entry ', @lastType, ' change ', @lastChg, ', late date ', CONVERT(VARCHAR(10), @lateDate, 120), ')'));
    ELSE
    BEGIN
        SELECT @e = NULL, @em = NULL, @stage = 'setup';
        BEGIN TRAN;
        BEGIN TRY
            IF @k IN (1, 2)
                UPDATE dbo.ExpenseSummary SET Balance = Balance - 1 WHERE BatchReferenceID = @batch AND SupplierID = @sup AND InvoiceNo = @code AND PostingMode = 'LOAN';
            IF @k = 3
                INSERT INTO dbo.ExpenseMaster (TRN_SEQ_NO, BranchCode, SupplierID, ReferenceNumber, BatchReferenceID, InvoiceNo, ExpenseName, ExpenseDate, Amount, Remarks, Status, Balance, AmountPaid, TicketReference, IsEWTPostedAtAccrual)
                SELECT TRN_SEQ_NO + 1, BranchCode, SupplierID, ReferenceNumber, BatchReferenceID, InvoiceNo, ExpenseName, ExpenseDate, 0, 'TEST105 L4f', 'UNPAID', 0, 0, TicketReference, 0
                FROM dbo.ExpenseMaster WHERE BatchReferenceID = @batch AND SupplierID = @sup AND InvoiceNo = @code;
            IF @k = 4
                INSERT INTO dbo.SupplierLedger (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate, Description, TransCode, TransactionDate, ReferenceNumber, ReferenceKey, InvoiceNo,
                                                BeginningBalance, Debit, Credit, EndingBalance, TransactedBy, ApprovedBy, TotalAmount, PaymentType, ErrorCorrectTag, TicketReference, BatchReferenceID)
                VALUES (dbo.func_getLastID(@sup), @sup, @sup, @payDate, 'TEST105 L4g stray row', 'TEST105', @payDate, @refA, 'TEST105', @code,
                        0, 1.00, 0, 0, @user, '*', 1.00, 'TEST105', 0, '', @batch);
            IF @k IN (6, 7)
            BEGIN
                SELECT @d3 = NULL, @bigDate = CASE WHEN @k = 6 THEN @lateDate ELSE @payDate END;
                EXEC dbo.sp_PostVoucherManual @parmrefno = @refA, @parmvoucherid = @vidA, @parmsupplierid = @sup, @parmsuppliername = @supName, @parmpaymethod = 'EXPENSE',
                     @parmvouchertype = 'TELEGRAPHIC', @parmcheckno = NULL, @parmcreditglcode = @bank, @parmcontrolno = @ctl, @parmvoucherdate = @bigDate,
                     @parmremarks = 'TEST105 L4i/L4j large payment (rolled back)', @parmpreparedby = @user, @parmbranch = @branch, @InvoiceLines = @vInvBig, @GLLines = @vGL;
                SELECT @d3 = CAST(Balance AS DECIMAL(18,2)) FROM dbo.ExpenseSummary WHERE BatchReferenceID = @batch AND SupplierID = @sup AND InvoiceNo = @code;
            END
            SET @stage = CASE WHEN @k IN (2, 7) THEN 'reverse' WHEN @k = 5 THEN 'memo' WHEN @k = 8 THEN 'pay' ELSE 'revalue' END;
            IF @k = 2 EXEC dbo.spu_Loan_ReverseRevaluation @TxnID = @lastTxn, @User = @user, @Reason = 'TEST105 L4e (rolled back)';
            ELSE IF @k = 7 EXEC dbo.spu_Loan_ReverseRevaluation @TxnID = @lastTxn, @User = @user, @Reason = 'TEST105 L4j (rolled back)';
            ELSE IF @k = 5
                EXEC dbo.sp_PostSupplierAdjustmentMemo @parmrefno = @refE, @parmsupplierid = @sup, @parmmemodate = @payDate, @parminvoicetype = 'EXPENSE', @parminvoiceno = @code,
                     @parmbatchrefno = @batch, @parmsequenceno = NULL, @parmbranchcode = @branch, @parmremarks = 'TEST105 L4h (rolled back)', @parmuser = @user,
                     @APAccountCode = @liab, @APDebitCredit = 'D', @APAmount = 100000.00, @OffsetLines = @memoOff;
            ELSE IF @k = 8
                EXEC dbo.sp_PostVoucherManual @parmrefno = @refB, @parmvoucherid = @vidB, @parmsupplierid = @sup, @parmsuppliername = @supName, @parmpaymethod = 'EXPENSE',
                     @parmvouchertype = 'TELEGRAPHIC', @parmcheckno = NULL, @parmcreditglcode = @bank, @parmcontrolno = @ctl, @parmvoucherdate = @payDate,
                     @parmremarks = 'TEST105 L4k (rolled back)', @parmpreparedby = @user, @parmbranch = @branch, @InvoiceLines = @vInvBr, @GLLines = @vGL;
            ELSE EXEC dbo.spu_Loan_PostRevaluation @LoanID = @loan, @RevalDate = @revalDate, @Rate = @Rate, @ExpectedPhpBalance = @pBal, @User = @user, @ControlNo = @ctl;
            SET @stage = 'not refused';
        END TRY
        BEGIN CATCH
            SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
        END CATCH
        SELECT @tc = @@TRANCOUNT;
        IF @@TRANCOUNT > 0 ROLLBACK;
        EXEC sp_executesql @qTie, @pTie, @batch, @sup, @code, @liab, @branch, @loan, @pay OUTPUT, @amt OUTPUT, @paid OUTPUT, @st OUTPUT, @gl OUTPUT, @led OUTPUT, @line OUTPUT, @lines OUTPUT, @lt OUTPUT;
        SET @now = CONCAT('payable ', @amt, '/', @pay, ' paid ', @paid, ' ', @st, '; GL ', @gl, '; ledger ', @led, '; line ', @lines, '; loan entries ', @lt);
        SELECT @n = (SELECT COUNT(*) FROM dbo.LoanTransaction WHERE PostedBy = @user OR ReversedBy = @user) + (SELECT COUNT(*) FROM dbo.TicketMaster WHERE EnteredBy = @user)
                  + (SELECT COUNT(*) FROM dbo.SupplierLedger WHERE TransactedBy = @user) + (SELECT COUNT(*) FROM dbo.ExpenseMaster WHERE Remarks LIKE 'TEST105%');
        SELECT @n = @n + (SELECT COUNT(*) FROM dbo.SupplierAdjustmentMemo WHERE ReferenceNo = @refE) + (SELECT COUNT(*) FROM dbo.TelegraphicVoucher WHERE ReferenceNumber IN (@refA, @refB));
        SET @n2 = CASE @k WHEN 3 THEN 62031 WHEN 4 THEN 62032 WHEN 5 THEN 58041 WHEN 6 THEN 62033 WHEN 7 THEN 62033 WHEN 8 THEN 58040 ELSE 62030 END;
        INSERT @r VALUES (CASE @k WHEN 1 THEN 'L4d revaluation when the payable was changed by hand (Balance - 1): refused 62030, nothing changed'
                                  WHEN 2 THEN 'L4e reversal of the last revaluation when the payable was changed by hand: refused 62030, nothing changed'
                                  WHEN 3 THEN 'L4f revaluation when the payable has two lines: refused 62031, nothing changed'
                                  WHEN 4 THEN 'L4g revaluation when the payable''s supplier ledger is off by 1.00: post-check 62032, nothing changed'
                                  WHEN 5 THEN 'L4h supplier adjustment memo (credit memo 100,000 on the loan''s account): refused 58041, nothing changed'
                                  WHEN 6 THEN 'L4i revaluation gain larger than what is left after a later payment: refused 62033, nothing changed'
                                  WHEN 7 THEN 'L4j reversal of the last (loss) revaluation after a payment: payable below 0, refused 62033'
                                  ELSE        'L4k voucher on the loan''s branch, invoice line on another branch: refused 58040, nothing changed' END,
                          CASE WHEN @stage IN ('revalue', 'reverse', 'memo', 'pay') AND @e = @n2 AND @tc = 0 AND @n = 0 AND @now = @before THEN 'PASS' ELSE 'FAIL' END,
                          CONCAT('at ', @stage, ': error ', ISNULL(CAST(@e AS VARCHAR(10)), 'none'), ' ', ISNULL(LEFT(@em, 300), '(not refused)'),
                                 CASE WHEN @k IN (6, 7) THEN CONCAT(' | payable after the payment of ', @BigPay, ' on ', CONVERT(VARCHAR(10), @bigDate, 120), ': ', ISNULL(CAST(@d3 AS VARCHAR(30)), '-'),
                                                                    CASE @k WHEN 6 THEN CONCAT(', revaluation change ', @chg1) ELSE CONCAT(', reversed change ', @lastChg) END) ELSE '' END,
                                 ' | @@TRANCOUNT ', @tc, ', TEST105 rows ', @n, ', loan state unchanged: ', CASE WHEN @now = @before THEN 'yes' ELSE CONCAT('NO: ', @now) END));
    END
    SET @k += 1;
END

-- L4h-old the old memo proc posts the same credit memo: the payable moves, its line does not (and with the expense AP account 20103 the
--         loan's GL does not either); run with the loan's own account and with 20103
SET @k = 1;
SELECT @x2 = '', @n = 0;
WHILE @k <= 2
BEGIN
    SELECT @e = NULL, @em = NULL, @stage = 'memo', @x1 = CASE @k WHEN 1 THEN @liab ELSE '20103' END;
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_PostSupplierAdjustmentMemo_OLD_10172026210000 @parmrefno = @refE, @parmsupplierid = @sup, @parmmemodate = @payDate, @parminvoicetype = 'EXPENSE', @parminvoiceno = @code,
             @parmbatchrefno = @batch, @parmsequenceno = NULL, @parmbranchcode = @branch, @parmremarks = 'TEST105 L4h old (rolled back)', @parmuser = @user,
             @APAccountCode = @x1, @APDebitCredit = 'D', @APAmount = 100000.00, @OffsetLines = @memoOff;
        SET @stage = 'read';
        EXEC sp_executesql @qTie, @pTie, @batch, @sup, @code, @liab, @branch, @loan, @pay OUTPUT, @amt OUTPUT, @paid OUTPUT, @st OUTPUT, @gl OUTPUT, @led OUTPUT, @line OUTPUT, @lines OUTPUT, @lt OUTPUT;
        SET @x2 = CONCAT(@x2, CASE WHEN @k = 2 THEN ' || ' ELSE '' END, 'AP account ', @x1, ': payable ', @amt, '/', @pay, ' ', @st, '; GL ', @gl, '; ledger ', @led, '; line ', @line);
        SET @n = CASE WHEN @pay = @pBal - 100000.00 AND (@line <> @pay OR @gl <> @pay) THEN @n + 1 ELSE @n END;
    END TRY
    BEGIN CATCH
        SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
        SET @x2 = CONCAT(@x2, CASE WHEN @k = 2 THEN ' || ' ELSE '' END, 'AP account ', @x1, ': refused ', @e, ' ', LEFT(@em, 150));
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @k += 1;
END
INSERT @r VALUES ('L4h-old old memo proc: a credit memo on the loan moves the payable but not its line (nor the GL with 20103)',
                  CASE WHEN @n = 2 THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END, @x2);

------------------------------------------------------------------
-- L5 reversal of the L3 voucher through sp_ReverseCombinedSupplierVoucher (as SupplierVoucherReversalFrm calls it)
--    L5a payment, reversal of the payment
--    L5b payment, revaluation of the new foreign balance, reversal of the payment (v2: Balance <= Amount, so it posts),
--        then the next month end's revaluation of the restored foreign balance
--    L5c payment, revaluation, reversal of the revaluation, then reversal of the payment
------------------------------------------------------------------
IF @canPay = 0
    INSERT @r VALUES ('L5 reversal of the loan payment', 'SKIP', 'no payment fixture (see L3)');
ELSE
BEGIN
    SET @k = 1;
    WHILE @k <= 3
    BEGIN
        IF @k IN (2, 3) AND @canL3c = 0
            INSERT @r VALUES (CASE @k WHEN 2 THEN 'L5b payment, revaluation, then reversal of the payment' ELSE 'L5c payment, revaluation, reversal of both' END, 'SKIP', 'no revaluation after the payment (see L3c)');
        ELSE
        BEGIN
            SELECT @e = NULL, @em = NULL, @stage = 'pay', @x1 = NULL, @txn = NULL;
            BEGIN TRAN;
            BEGIN TRY
                EXEC dbo.sp_PostVoucherManual @parmrefno = @refA, @parmvoucherid = @vidA, @parmsupplierid = @sup, @parmsuppliername = @supName, @parmpaymethod = 'EXPENSE',
                     @parmvouchertype = 'TELEGRAPHIC', @parmcheckno = NULL, @parmcreditglcode = @bank, @parmcontrolno = @ctl, @parmvoucherdate = @payDate,
                     @parmremarks = 'TEST105 L5 loan principal (rolled back)', @parmpreparedby = @user, @parmbranch = @branch, @InvoiceLines = @vInv, @GLLines = @vGL;
                IF @k IN (2, 3)
                BEGIN
                    SET @stage = 'revalue';
                    EXEC dbo.spu_Loan_PostRevaluation @LoanID = @loan, @RevalDate = @revalDate, @Rate = @Rate, @ExpectedPhpBalance = @pBal, @User = @user, @ForeignBalance = @newF3, @ControlNo = @ctl;
                    SELECT @txn = TxnID FROM dbo.LoanTransaction WHERE LoanID = @loan AND TxnDate = @revalDate AND Status = 'POSTED';
                END
                IF @k = 3
                BEGIN
                    SET @stage = 'reverse revaluation';
                    EXEC dbo.spu_Loan_ReverseRevaluation @TxnID = @txn, @User = @user, @Reason = 'TEST105 L5c (rolled back)';
                END
                SET @stage = 'reverse';
                EXEC dbo.sp_ReverseCombinedSupplierVoucher @parmsupplierid = @sup, @parmreferenceno = @refA, @parmvoucherid = @vidA, @parmvouchertype = 'EXPENSE',
                     @parmcheckno = @ctl, @parmglcode = NULL, @parmbranch = NULL, @parmreason = 'TEST105 L5 (rolled back)', @parmuser = @user;
                SET @stage = 'read';
                EXEC sp_executesql @qTie, @pTie, @batch, @sup, @code, @liab, @branch, @loan, @pay OUTPUT, @amt OUTPUT, @paid OUTPUT, @st OUTPUT, @gl OUTPUT, @led OUTPUT, @line OUTPUT, @lines OUTPUT, @lt OUTPUT;
                SET @tie = CONCAT('payable ', @amt, '/', @pay, ' paid ', @paid, ' ', @st, '; GL ', @gl, '; ledger ', @led, '; line ', @lines);
                SELECT @s = CONCAT('voucher voided ', (SELECT MAX(CAST(ISNULL(isErrorCorrect, 0) AS INT)) FROM dbo.TelegraphicVoucher WHERE ReferenceNumber = @refA AND VoucherID = CAST(@vidA AS DECIMAL(7,0))),
                                   ', reversal tickets ', (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber = @refA AND ReferenceKey = @vidA AND Product = 'REVERSAL'),
                                   ', ticket accounts not netting to 0 ', (SELECT COUNT(*) FROM (SELECT AccountCode FROM dbo.TicketDetails WHERE ReferenceNumber = @refA AND ReferenceKey = @vidA
                                                                                                GROUP BY AccountCode HAVING ABS(SUM(ISNULL(Debit, 0)) - SUM(ISNULL(Credit, 0))) > 0.004) AS z),
                                   ', recon ', (SELECT STRING_AGG(CONCAT(ItemType, ' ', Amount, ' ', CAST(IsResolved AS INT), ' ', ISNULL(ResolvedReason, '-')), ',') FROM dbo.BankStatementRecon WHERE SourceRef = @refA),
                                   ', ledger rows of the voucher ', (SELECT CONCAT(COUNT(*), ' net ', SUM(ISNULL(Credit, 0) - ISNULL(Debit, 0))) FROM dbo.SupplierLedger WHERE SupplierKey = @sup AND ReferenceNumber = @refA));
                SELECT @d1 = PhpBalance, @d2 = ForeignBalance FROM dbo.LoanTransaction
                WHERE TxnID = (SELECT TOP (1) TxnID FROM dbo.LoanTransaction WHERE LoanID = @loan AND Status = 'POSTED' ORDER BY TxnDate DESC, TxnID DESC);
                SET @s2 = @tie;
                EXEC sp_executesql @qAP, @pAP, @nAP OUTPUT, @apList OUTPUT;
                SELECT @n = 0;
                IF @pay = @gl AND @pay = @led AND @pay = @line AND @paid = 0 AND @amt = @pay SET @n = 1;
                SET @d3 = @pay;
                SET @x2 = @lines;
                -- L5b: the loan entry still says the typed foreign balance; the next month end has to type the restored one
                IF @k = 2 AND @nextDate <= EOMONTH(@today)
                BEGIN
                    SET @stage = 'next revaluation';
                    BEGIN TRY
                        EXEC dbo.spu_Loan_PostRevaluation @LoanID = @loan, @RevalDate = @nextDate, @Rate = @Rate, @ExpectedPhpBalance = @d1, @User = @user, @ForeignBalance = @fBal, @ControlNo = @ctl;
                        EXEC sp_executesql @qTie, @pTie, @batch, @sup, @code, @liab, @branch, @loan, @pay OUTPUT, @amt OUTPUT, @paid OUTPUT, @st OUTPUT, @gl OUTPUT, @led OUTPUT, @line OUTPUT, @lines OUTPUT, @lt OUTPUT;
                        SET @x1 = CONCAT('next revaluation ', CONVERT(VARCHAR(10), @nextDate, 120), ' of ', @fBal, ' @', @Rate, ': payable ', @amt, '/', @pay, ', GL ', @gl, ', ledger ', @led, ', line ', @line,
                                         CASE WHEN @pay = @gl AND @pay = @led AND @pay = @line AND @pay = ROUND(@fBal * @Rate, 2) THEN ' (ties)' ELSE ' (DOES NOT TIE)' END);
                    END TRY
                    BEGIN CATCH
                        SET @x1 = CONCAT('next revaluation ', CONVERT(VARCHAR(10), @nextDate, 120), ' of ', @fBal, ' refused ', ERROR_NUMBER(), ' ', LEFT(ERROR_MESSAGE(), 200));
                    END CATCH
                    SET @stage = 'read';
                END
            END TRY
            BEGIN CATCH
                SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
            END CATCH
            SELECT @tc = @@TRANCOUNT;
            IF @@TRANCOUNT > 0 ROLLBACK;
            -- the payable expected after the reversal of the payment (L5b: the revalued value + the payment back)
            SET @d1 = CASE @k WHEN 2 THEN @exp3 + @PayAmt ELSE @pBal END;
            IF @e IS NOT NULL
                INSERT @r VALUES (CASE @k WHEN 1 THEN 'L5a reversal of the loan payment' WHEN 2 THEN 'L5b payment, revaluation, then reversal of the payment' ELSE 'L5c payment, revaluation, reversal of both' END,
                                  'FAIL', CONCAT('at ', @stage, ': error ', @e, ' ', LEFT(@em, 400), ' | @@TRANCOUNT ', @tc));
            ELSE
                INSERT @r VALUES (CASE @k WHEN 1 THEN 'L5a reversal of the loan payment (combined reversal proc): payable back = GL = ledger = line, POSTED / UNPAID'
                                          WHEN 2 THEN 'L5b payment, revaluation, then reversal of the payment: payable = GL = ledger = line, POSTED / UNPAID'
                                          ELSE        'L5c payment, revaluation, reversal of the revaluation, then of the payment: all back, UNPAID' END,
                                  CASE WHEN @n = 1 AND @d3 = @d1 AND @x2 = CONCAT(@branch, ':', @d1, '|0.00|', @d1, '|UNPAID') AND @s2 LIKE '% POSTED; GL %'
                                            AND @s LIKE 'voucher voided 1, reversal tickets 1, ticket accounts not netting to 0 0, %' AND @s LIKE '%, ledger rows of the voucher 2 net 0.00' AND @nAP = 0
                                            AND (@k <> 2 OR @x1 IS NULL OR @x1 LIKE '%(ties)')
                                       THEN 'PASS' ELSE 'FAIL' END,
                                  CONCAT('expected ', @d1, ' | ', @s2, ' | ', @s, ' | loan entry then ', @d2, ' | new AP findings ', @nAP, ' (', @apList, ')',
                                         CASE WHEN @x1 IS NOT NULL THEN CONCAT(' | ', @x1) ELSE '' END));
        END
        SET @k += 1;
    END
END

------------------------------------------------------------------
-- leftovers
------------------------------------------------------------------
Report:
SELECT @n = (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber IN ('99931', '99932', '99933', '99934', '99935') OR EnteredBy = 'TEST105')
          + (SELECT COUNT(*) FROM dbo.SupplierAdjustmentMemo WHERE ReferenceNo = '99935' OR PreparedBy = 'TEST105')
          + (SELECT COUNT(*) FROM dbo.APPaymentDetails WHERE ReferenceNumber IN ('99931', '99932', '99933', '99934') OR VoucherID IN ('99941', '99942', '99943', '99944'))
          + (SELECT COUNT(*) FROM dbo.TransactionPaymentAP WHERE ReferenceNumber IN (99931, 99932, 99933, 99934))
          + (SELECT COUNT(*) FROM dbo.TelegraphicVoucher WHERE ReferenceNumber IN ('99931', '99932', '99933', '99934') OR VoucherID IN (99941, 99942, 99943, 99944))
          + (SELECT COUNT(*) FROM dbo.CashVoucher WHERE ReferenceNumber IN ('99931', '99932', '99933', '99934') OR VoucherID IN (99941, 99942, 99943, 99944))
          + (SELECT COUNT(*) FROM dbo.BankStatementRecon WHERE SourceRef IN ('99931', '99932', '99933', '99934') OR ReferenceNo IN ('99941', '99942', '99943', '99944') OR AddedBy = 'TEST105')
          + (SELECT COUNT(*) FROM dbo.SupplierLedger WHERE ReferenceNumber IN ('99931', '99932', '99933', '99934') OR TransactedBy = 'TEST105')
          + (SELECT COUNT(*) FROM dbo.PaymentReversalAudit WHERE ReferenceNumber IN ('99931', '99932', '99933', '99934') OR CancelledBy = 'TEST105')
          + (SELECT COUNT(*) FROM dbo.LoanTransaction WHERE PostedBy = 'TEST105' OR ReversedBy = 'TEST105')
          + (SELECT COUNT(*) FROM dbo.ExpenseMaster WHERE Remarks LIKE 'TEST105%')
          + (SELECT COUNT(*) FROM dbo.ExpenseSummary WHERE UpdatedBy = 'TEST105');
SELECT @tc = @@TRANCOUNT;
SET @now = NULL;
IF @loan IS NOT NULL
BEGIN
    EXEC sp_executesql @qTie, @pTie, @batch, @sup, @code, @liab, @branch, @loan, @pay OUTPUT, @amt OUTPUT, @paid OUTPUT, @st OUTPUT, @gl OUTPUT, @led OUTPUT, @line OUTPUT, @lines OUTPUT, @lt OUTPUT;
    SET @now = CONCAT('payable ', @amt, '/', @pay, ' paid ', @paid, ' ', @st, '; GL ', @gl, '; ledger ', @led, '; line ', @lines, '; loan entries ', @lt);
END
INSERT @r VALUES ('leftovers', CASE WHEN @n = 0 AND @tc = 0 AND ISNULL(@now, '') = ISNULL(@before, '') THEN 'PASS' ELSE 'FAIL' END,
                  CONCAT(@n, ' test rows left behind (TEST105 / refs 99931-99935 / voucher ids 99941-99944); @@TRANCOUNT ', @tc,
                         '; loan state as before: ', CASE WHEN ISNULL(@now, '') = ISNULL(@before, '') THEN 'yes' ELSE CONCAT('NO: ', @now) END));
IF OBJECT_ID('tempdb..#apBase') IS NOT NULL DROP TABLE #apBase;

SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
SELECT DB_NAME() AS DatabaseName, SUM(CASE WHEN Result = 'PASS' THEN 1 ELSE 0 END) AS Pass, SUM(CASE WHEN Result = 'BUG SHOWN' THEN 1 ELSE 0 END) AS BugShown,
       SUM(CASE WHEN Result = 'PRE-EXISTING' THEN 1 ELSE 0 END) AS PreExisting, SUM(CASE WHEN Result = 'SKIP' THEN 1 ELSE 0 END) AS Skip,
       SUM(CASE WHEN Result IN ('FAIL', 'ERROR', 'UNEXPECTED') THEN 1 ELSE 0 END) AS Fail
FROM @r;
