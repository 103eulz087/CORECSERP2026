/* ================================================================
   Process Trace: Supplier Payment (AddExpenseDevExFrm → SupplierPaymentDevEx
   → reversal)
   READ-ONLY. The builder passes @Ids = comma-separated VoucherIDs.
   Every result set starts with _t = the table id used in SupplierPayment.json.
   ================================================================ */
SET NOCOUNT ON;

DECLARE @V TABLE (VoucherID VARCHAR(20) PRIMARY KEY);
INSERT INTO @V (VoucherID)
SELECT DISTINCT LTRIM(RTRIM(value))
FROM STRING_SPLIT(@Ids, ',')
WHERE LTRIM(RTRIM(value)) <> '';

-- one row per payment (voucher + payment reference + supplier)
DECLARE @Pay TABLE (VoucherID VARCHAR(20), ReferenceNumber VARCHAR(30), SupplierID VARCHAR(30));
INSERT INTO @Pay
SELECT DISTINCT CAST(d.VoucherID AS VARCHAR(20)), RTRIM(CAST(d.ReferenceNumber AS VARCHAR(30))), d.SupplierID
FROM dbo.APPaymentDetails AS d
INNER JOIN @V AS v ON v.VoucherID = CAST(d.VoucherID AS VARCHAR(20));

-- the expense invoices those payments settled
DECLARE @Exp TABLE (SupplierID VARCHAR(30), BatchReferenceID BIGINT, InvoiceNo VARCHAR(150));
INSERT INTO @Exp
SELECT DISTINCT d.SupplierID, d.BatchReferenceID, d.InvoiceNo
FROM dbo.APPaymentDetails AS d
INNER JOIN @V AS v ON v.VoucherID = CAST(d.VoucherID AS VARCHAR(20));

DECLARE @ExpRef TABLE (ReferenceNumber VARCHAR(30), InvoiceNo VARCHAR(150), SupplierID VARCHAR(30));
INSERT INTO @ExpRef
SELECT DISTINCT RTRIM(es.ReferenceNumber), es.InvoiceNo, es.SupplierID
FROM dbo.ExpenseSummary AS es
INNER JOIN @Exp AS e ON e.SupplierID = es.SupplierID AND e.BatchReferenceID = es.BatchReferenceID AND e.InvoiceNo = es.InvoiceNo;

DECLARE @ExpTk TABLE (TicketNumber VARCHAR(30) PRIMARY KEY);
INSERT INTO @ExpTk
SELECT DISTINCT CAST(tm.TicketNumber AS VARCHAR(30))
FROM dbo.TicketMaster AS tm
INNER JOIN @ExpRef AS r ON r.ReferenceNumber = tm.ReferenceNumber AND r.InvoiceNo = tm.ReferenceKey;

DECLARE @PayTk TABLE (TicketNumber VARCHAR(30) PRIMARY KEY);
INSERT INTO @PayTk
SELECT DISTINCT CAST(tm.TicketNumber AS VARCHAR(30))
FROM dbo.TicketMaster AS tm
INNER JOIN @Pay AS p ON p.ReferenceNumber = tm.ReferenceNumber AND p.VoucherID = tm.ReferenceKey
WHERE ISNULL(tm.Product, '') <> 'REVERSAL';

DECLARE @RevTk TABLE (TicketNumber VARCHAR(30) PRIMARY KEY);
INSERT INTO @RevTk
SELECT DISTINCT CAST(tm.TicketNumber AS VARCHAR(30))
FROM dbo.TicketMaster AS tm
INNER JOIN @Pay AS p ON p.ReferenceNumber = tm.ReferenceNumber AND p.VoucherID = tm.ReferenceKey
WHERE tm.Product = 'REVERSAL';

------------------------------------------------------------------ step 1: the expense (payable) is posted
SELECT 'es' AS _t, es.SupplierID, es.ReferenceNumber, es.InvoiceNo, es.BatchReferenceID, es.Description, es.ExpenseDate,
       es.Amount, es.PostingMode, es.PayableAccountCode, es.ShipmentNo, es.AddedBy
FROM dbo.ExpenseSummary AS es
INNER JOIN @Exp AS e ON e.SupplierID = es.SupplierID AND e.BatchReferenceID = es.BatchReferenceID AND e.InvoiceNo = es.InvoiceNo
ORDER BY es.BatchReferenceID;

SELECT 'em' AS _t, em.SupplierID, em.ReferenceNumber, em.InvoiceNo, em.BatchReferenceID, em.TRN_SEQ_NO, em.BranchCode,
       em.ExpenseName, em.Amount, em.Balance, em.AmountPaid, em.Status, em.TicketReference
FROM dbo.ExpenseMaster AS em
INNER JOIN @Exp AS e ON e.SupplierID = em.SupplierID AND e.BatchReferenceID = em.BatchReferenceID AND e.InvoiceNo = em.InvoiceNo
ORDER BY em.BatchReferenceID, em.TRN_SEQ_NO;

SELECT 'expTm' AS _t, tm.TicketDate, tm.BranchCode, tm.TicketNumber, tm.ReferenceNumber, tm.ReferenceKey, tm.Owner,
       tm.Particulars, tm.Status, tm.Mnemonic, tm.EnteredBy
FROM dbo.TicketMaster AS tm
INNER JOIN @ExpTk AS k ON k.TicketNumber = CAST(tm.TicketNumber AS VARCHAR(30))
ORDER BY tm.TicketNumber;

SELECT 'expTd' AS _t, td.TicketNumber, td.BranchCode, td.ReferenceNumber, td.ReferenceKey, td.AccountCode,
       coa.Description AS AccountName, td.Debit, td.Credit
FROM dbo.TicketDetails AS td
INNER JOIN @ExpTk AS k ON k.TicketNumber = CAST(td.TicketNumber AS VARCHAR(30))
LEFT JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = td.AccountCode
ORDER BY td.TicketNumber, td.Debit DESC;

SELECT 'expSl' AS _t, sl.SupplierID, sl.TRN_SEQ_NO, sl.PostingDate, sl.TransCode, sl.ReferenceNumber, sl.ReferenceKey,
       sl.InvoiceNo, sl.BatchReferenceID, sl.BeginningBalance, sl.Debit, sl.Credit, sl.EndingBalance, sl.TicketReference, sl.PaymentType
FROM dbo.SupplierLedger AS sl
INNER JOIN @ExpRef AS r ON r.ReferenceNumber = RTRIM(sl.ReferenceNumber) AND r.SupplierID = sl.SupplierID AND r.InvoiceNo = sl.InvoiceNo
ORDER BY sl.TRN_SEQ_NO;

------------------------------------------------------------------ step 2: the payment is posted (sp_PostSupplierPaymentWithManualLines → V2)
SELECT 'tpap' AS _t, t.SupplierKey, t.SEQ_NO, t.ReferenceNumber, t.Amount, t.VoucherType, t.DatePaid, t.ExecuteBy, t.ErrorCorrect
FROM dbo.TransactionPaymentAP AS t
INNER JOIN (SELECT DISTINCT ReferenceNumber, SupplierID FROM @Pay) AS p
        ON p.ReferenceNumber = RTRIM(CAST(t.ReferenceNumber AS VARCHAR(30))) AND p.SupplierID = t.SupplierKey
ORDER BY t.SEQ_NO;

SELECT 'cv' AS _t, c.VoucherID, c.SupplierID, c.ReferenceNumber, c.PaidTo, c.CheckNo, c.CheckDate, c.ControlNo, c.Amount,
       c.CreditGLCode, c.Particulars, c.PreparedBy, c.isErrorCorrect, c.CancelledBy, c.CancelReason
FROM dbo.CheckVoucher AS c
INNER JOIN @Pay AS p ON p.VoucherID = CAST(c.VoucherID AS VARCHAR(20)) AND p.ReferenceNumber = RTRIM(c.ReferenceNumber);

SELECT 'cashv' AS _t, c.VoucherID, c.SupplierID, c.ReferenceNumber, c.PaidTo, c.ControlNo, c.Amount,
       c.CreditGLCode, c.Particulars, c.PreparedBy, c.isErrorCorrect
FROM dbo.CashVoucher AS c
INNER JOIN @Pay AS p ON p.VoucherID = CAST(c.VoucherID AS VARCHAR(20)) AND p.ReferenceNumber = RTRIM(c.ReferenceNumber);

SELECT 'tv' AS _t, c.VoucherID, c.SupplierID, c.ReferenceNumber, c.PaidTo, c.ControlNo, c.Amount,
       c.CreditGLCode, c.Particulars, c.PreparedBy, c.isErrorCorrect
FROM dbo.TelegraphicVoucher AS c
INNER JOIN @Pay AS p ON p.VoucherID = CAST(c.VoucherID AS VARCHAR(20)) AND p.ReferenceNumber = RTRIM(c.ReferenceNumber);

SELECT 'apd' AS _t, d.VoucherID, d.SupplierID, d.ReferenceNumber, d.BranchCode, d.InvoiceNo, d.BatchReferenceID,
       d.PaymentType, d.PaymentMethod, d.VoucherType, d.Amount, d.DebitGLCode, d.CreditGLCode, d.TicketNumber
FROM dbo.APPaymentDetails AS d
INNER JOIN @V AS v ON v.VoucherID = CAST(d.VoucherID AS VARCHAR(20))
ORDER BY d.VoucherID, d.InvoiceNo, CASE d.PaymentType WHEN 'EXPENSE PAYMENT' THEN 0 WHEN 'INVOICE PAYMENT' THEN 0 ELSE 1 END;

SELECT 'jem' AS _t, m.Mnemonic, m.Seq, m.DebitCredit, m.AccountCode, m.AccountDescription, m.AmountType
FROM dbo.JournalEntryMapping AS m
-- expense-mode payments read only the account of the row whose AmountType matches (see V2)
WHERE m.IsActive = 1
  AND EXISTS (SELECT 1 FROM dbo.APPaymentDetails AS d
              INNER JOIN @V AS v ON v.VoucherID = CAST(d.VoucherID AS VARCHAR(20))
              WHERE d.PaymentType = m.AmountType
                AND m.Mnemonic = CASE d.PaymentType WHEN 'OVERPAY' THEN 'PV-AP-OVERPAY'
                                                    WHEN 'OVERPAYEXPENSE' THEN 'PV-AP-OVERPAYEXP'
                                                    WHEN 'ADVANCEAPPLIED' THEN 'PV-AP-ADVAPPLIED' END)
ORDER BY m.Mnemonic, m.Seq;

SELECT 'payTm' AS _t, tm.TicketDate, tm.BranchCode, tm.TicketNumber, tm.ReferenceNumber, tm.ReferenceKey, tm.Owner,
       tm.Particulars, tm.Status, tm.Mnemonic, tm.EnteredBy
FROM dbo.TicketMaster AS tm
INNER JOIN @PayTk AS k ON k.TicketNumber = CAST(tm.TicketNumber AS VARCHAR(30))
ORDER BY tm.TicketNumber;

SELECT 'payTd' AS _t, td.TicketNumber, td.BranchCode, td.ReferenceNumber, td.ReferenceKey, td.AccountCode,
       coa.Description AS AccountName, td.Debit, td.Credit
FROM dbo.TicketDetails AS td
INNER JOIN @PayTk AS k ON k.TicketNumber = CAST(td.TicketNumber AS VARCHAR(30))
LEFT JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = td.AccountCode
ORDER BY td.TicketNumber, td.Debit DESC;

SELECT 'paySl' AS _t, sl.SupplierID, sl.TRN_SEQ_NO, sl.PostingDate, sl.TransCode, sl.ReferenceNumber, sl.ReferenceKey,
       sl.InvoiceNo, sl.BatchReferenceID, sl.BeginningBalance, sl.Debit, sl.Credit, sl.EndingBalance, sl.TicketReference,
       sl.PaymentType, sl.ErrorCorrectTag
FROM dbo.SupplierLedger AS sl
INNER JOIN (SELECT DISTINCT ReferenceNumber, SupplierID FROM @Pay) AS p
        ON p.ReferenceNumber = RTRIM(sl.ReferenceNumber) AND p.SupplierID = sl.SupplierID
WHERE ISNULL(sl.PaymentType, '') <> 'REVERSAL'
ORDER BY sl.TRN_SEQ_NO;

SELECT 'esAfter' AS _t, es.SupplierID, es.InvoiceNo, es.BatchReferenceID, es.Amount, es.AmountPaid, es.EWTWithheld,
       es.DiscountWithheld, es.OffsetWithheld, es.Balance, es.Status, es.UpdatedBy
FROM dbo.ExpenseSummary AS es
INNER JOIN @Exp AS e ON e.SupplierID = es.SupplierID AND e.BatchReferenceID = es.BatchReferenceID AND e.InvoiceNo = es.InvoiceNo
ORDER BY es.BatchReferenceID;

SELECT 'bsr' AS _t, b.ReconID, b.HeaderID, b.BranchCode, b.AccountCode, b.PeriodEnd, b.ItemType, b.ItemDate,
       b.Payee, b.ReferenceNo, b.Amount, b.SourceModule, b.SourceRef, b.IsResolved, b.ResolvedReason
FROM dbo.BankStatementRecon AS b
INNER JOIN (SELECT DISTINCT ReferenceNumber FROM @Pay) AS p ON p.ReferenceNumber = b.SourceRef
WHERE b.SourceModule = 'AP-PAYMENT'
ORDER BY b.ReconID;

SELECT 'credit' AS _t, d.SupplierID, d.VoucherID, d.ReferenceNumber, d.InvoiceNo, d.PaymentType, d.Amount,
       CASE WHEN EXISTS (SELECT 1 FROM dbo.PaymentReversalAudit AS r WHERE r.VoucherID = d.VoucherID AND r.SupplierID = d.SupplierID)
            THEN 1 ELSE 0 END AS VoucherReversed
FROM dbo.APPaymentDetails AS d
WHERE d.PaymentType IN ('OVERPAY', 'ADVANCEAPPLIED')
  AND d.SupplierID IN (SELECT SupplierID FROM @Pay)
ORDER BY d.VoucherID;

SELECT 'sa' AS _t, sa.SupplierKey, sa.SupplierID, sa.SupplierName, sa.AccountStatus, sa.AccountBalance, sa.LastMovementDate
FROM dbo.SupplierAccounts AS sa
WHERE sa.SupplierID IN (SELECT SupplierID FROM @Pay);

------------------------------------------------------------------ step 3: the payment is reversed (sp_CancelledChequesCS)
SELECT 'pra' AS _t, r.AuditID, r.VoucherID, r.SupplierID, r.VoucherType, r.ReferenceNumber, r.CancelReason, r.CancelledBy, r.CancelledDate
FROM dbo.PaymentReversalAudit AS r
INNER JOIN @Pay AS p ON p.VoucherID = CAST(r.VoucherID AS VARCHAR(20)) AND p.SupplierID = r.SupplierID;

SELECT 'cvc' AS _t, c.VoucherID, c.SupplierKey, c.ReferenceNumber, c.PaidTo, c.CheckNo, c.CheckDate, c.Amount, c.VoucherType, c.ExecuteBy, c.DateAdded
FROM dbo.CheckVoucherCancelled AS c
INNER JOIN @Pay AS p ON p.VoucherID = CAST(c.VoucherID AS VARCHAR(20)) AND p.ReferenceNumber = RTRIM(c.ReferenceNumber);

SELECT 'revTm' AS _t, tm.TicketDate, tm.BranchCode, tm.TicketNumber, tm.ReferenceNumber, tm.ReferenceKey,
       tm.Particulars, tm.Status, tm.Mnemonic, tm.Product, tm.EnteredBy
FROM dbo.TicketMaster AS tm
INNER JOIN @RevTk AS k ON k.TicketNumber = CAST(tm.TicketNumber AS VARCHAR(30))
ORDER BY tm.TicketNumber;

SELECT 'revTd' AS _t, td.TicketNumber, td.ReferenceNumber, td.ReferenceKey, td.AccountCode, coa.Description AS AccountName, td.Debit, td.Credit
FROM dbo.TicketDetails AS td
INNER JOIN @RevTk AS k ON k.TicketNumber = CAST(td.TicketNumber AS VARCHAR(30))
LEFT JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = td.AccountCode
ORDER BY td.TicketNumber, td.Debit DESC;

SELECT 'revSl' AS _t, sl.SupplierID, sl.TRN_SEQ_NO, sl.PostingDate, sl.TransCode, sl.ReferenceNumber, sl.InvoiceNo,
       sl.Debit, sl.Credit, sl.EndingBalance, sl.TicketReference, sl.PaymentType, sl.ErrorCorrectTag
FROM dbo.SupplierLedger AS sl
INNER JOIN (SELECT DISTINCT ReferenceNumber, SupplierID FROM @Pay) AS p
        ON p.ReferenceNumber = RTRIM(sl.ReferenceNumber) AND p.SupplierID = sl.SupplierID
WHERE sl.PaymentType = 'REVERSAL'
ORDER BY sl.TRN_SEQ_NO;
