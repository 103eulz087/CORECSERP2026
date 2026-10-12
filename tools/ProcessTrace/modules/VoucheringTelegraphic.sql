/* ================================================================
   Process Trace: Vouchering - Telegraphic (VoucheringManualFrm → sp_PostVoucherManual)
   READ-ONLY. The builder passes @Ids = comma-separated VoucherIDs.
   Every result set starts with _t = the table id used in VoucheringTelegraphic.json.
   ================================================================ */
SET NOCOUNT ON;

DECLARE @V TABLE (VoucherID VARCHAR(20) PRIMARY KEY);
INSERT INTO @V (VoucherID)
SELECT DISTINCT LTRIM(RTRIM(value))
FROM STRING_SPLIT(@Ids, ',')
WHERE LTRIM(RTRIM(value)) <> '';

-- one row per voucher: the telegraphic voucher itself (a voucher with only manual GL lines has no payment lines)
DECLARE @Pay TABLE (VoucherID VARCHAR(20), ReferenceNumber VARCHAR(30), SupplierID VARCHAR(30));
INSERT INTO @Pay
SELECT DISTINCT CAST(t.VoucherID AS VARCHAR(20)), RTRIM(CAST(t.ReferenceNumber AS VARCHAR(30))), t.SupplierID
FROM dbo.TelegraphicVoucher AS t
INNER JOIN @V AS v ON v.VoucherID = CAST(t.VoucherID AS VARCHAR(20));

-- the purchase invoices (APAccounts rows) those vouchers settled
DECLARE @Inv TABLE (SupplierID VARCHAR(30), InvoiceNo VARCHAR(150), SequenceNo VARCHAR(50));
INSERT INTO @Inv
SELECT DISTINCT d.SupplierID, d.InvoiceNo, d.SequenceReferenceNumber
FROM dbo.APPaymentDetails AS d
INNER JOIN @Pay AS p ON p.VoucherID = CAST(d.VoucherID AS VARCHAR(20)) AND p.ReferenceNumber = RTRIM(d.ReferenceNumber);

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

------------------------------------------------------------------ step 1: the purchase payable
SELECT 'ap' AS _t, a.SupplierID, a.SequenceNo, a.ShipmentNo, a.ReferenceNumber, a.InvoiceNo, a.InvoiceDate, a.DueDate,
       a.VatExemptAmount, a.VatableAmount, a.ActualCost, a.AddedBy
FROM dbo.APAccounts AS a
INNER JOIN @Inv AS i ON i.SupplierID = a.SupplierID AND i.InvoiceNo = a.InvoiceNo AND i.SequenceNo = CAST(a.SequenceNo AS VARCHAR(50))
ORDER BY a.SequenceNo;

SELECT 'apSl' AS _t, sl.SupplierID, sl.TRN_SEQ_NO, sl.PostingDate, sl.TransCode, sl.ReferenceNumber, sl.ReferenceKey,
       sl.InvoiceNo, sl.BeginningBalance, sl.Debit, sl.Credit, sl.EndingBalance, sl.PaymentType
FROM dbo.SupplierLedger AS sl
INNER JOIN (SELECT DISTINCT SupplierID, InvoiceNo FROM @Inv) AS i ON i.SupplierID = sl.SupplierID AND i.InvoiceNo = sl.InvoiceNo
WHERE ISNULL(sl.TransCode, '') NOT IN ('PV-MANUAL') AND ISNULL(sl.PaymentType, '') <> 'REVERSAL'
  AND sl.Credit > 0
ORDER BY sl.TRN_SEQ_NO;

------------------------------------------------------------------ step 2: the voucher and its payment lines
SELECT 'tv' AS _t, t.VoucherID, t.SupplierID, t.ReferenceNumber, t.PaidTo, t.ControlNo, t.NotedBy, t.Amount,
       t.OfficialReceiptNo, t.CreditGLCode, t.DateReceived, t.Particulars, t.PreparedBy, t.isErrorCorrect
FROM dbo.TelegraphicVoucher AS t
INNER JOIN @Pay AS p ON p.VoucherID = CAST(t.VoucherID AS VARCHAR(20)) AND p.ReferenceNumber = RTRIM(t.ReferenceNumber)
ORDER BY t.VoucherID;

SELECT 'tpap' AS _t, x.SupplierKey, x.SEQ_NO, x.ReferenceNumber, x.Amount, x.VoucherType, x.DatePaid, x.ExecuteBy, x.ErrorCorrect
FROM dbo.TransactionPaymentAP AS x
INNER JOIN (SELECT DISTINCT ReferenceNumber, SupplierID FROM @Pay) AS p
        ON p.ReferenceNumber = RTRIM(CAST(x.ReferenceNumber AS VARCHAR(30))) AND p.SupplierID = x.SupplierKey
ORDER BY x.SEQ_NO;

SELECT 'apd' AS _t, d.VoucherID, d.SupplierID, d.ReferenceNumber, d.BranchCode, d.InvoiceNo, d.SequenceReferenceNumber,
       d.PaymentType, d.PaymentMethod, d.VoucherType, d.Amount, d.Variance, d.Amount - ISNULL(d.Variance, 0) AS Settled,
       d.DebitGLCode, d.CreditGLCode, d.TicketNumber
FROM dbo.APPaymentDetails AS d
INNER JOIN @Pay AS p ON p.VoucherID = CAST(d.VoucherID AS VARCHAR(20)) AND p.ReferenceNumber = RTRIM(d.ReferenceNumber)
ORDER BY d.VoucherID, d.InvoiceNo;

SELECT 'jem' AS _t, m.Mnemonic, m.Seq, m.DebitCredit, m.AccountCode, m.AccountDescription, m.AmountType, m.ConditionFlag
FROM dbo.JournalEntryMapping AS m
WHERE m.IsActive = 1
  AND ((m.Mnemonic = 'VOUCHER-MANUAL-APTRADE' AND m.ConditionFlag = 'PURCHASE'
        AND EXISTS (SELECT 1 FROM dbo.APPaymentDetails AS d INNER JOIN @Pay AS p ON p.VoucherID = CAST(d.VoucherID AS VARCHAR(20))
                    WHERE d.PaymentMethod = 'PURCHASE'))
    OR (m.Mnemonic = 'VOUCHER-MANUAL-FXVAR' AND m.ConditionFlag = 'HasFXLoss'
        AND EXISTS (SELECT 1 FROM dbo.APPaymentDetails AS d INNER JOIN @Pay AS p ON p.VoucherID = CAST(d.VoucherID AS VARCHAR(20)) WHERE d.Variance > 0))
    OR (m.Mnemonic = 'VOUCHER-MANUAL-FXVAR' AND m.ConditionFlag = 'HasFXGain'
        AND EXISTS (SELECT 1 FROM dbo.APPaymentDetails AS d INNER JOIN @Pay AS p ON p.VoucherID = CAST(d.VoucherID AS VARCHAR(20)) WHERE d.Variance < 0)))
ORDER BY m.Mnemonic, m.Seq;

------------------------------------------------------------------ step 3: GL, ledger, balances, bank recon
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
       sl.InvoiceNo, sl.BeginningBalance, sl.Debit, sl.Credit, sl.EndingBalance, sl.TicketReference, sl.PaymentType, sl.ErrorCorrectTag
FROM dbo.SupplierLedger AS sl
INNER JOIN (SELECT DISTINCT ReferenceNumber, SupplierID FROM @Pay) AS p
        ON p.ReferenceNumber = RTRIM(sl.ReferenceNumber) AND p.SupplierID = sl.SupplierID
WHERE sl.TransCode = 'PV-MANUAL' AND ISNULL(sl.PaymentType, '') <> 'REVERSAL' AND sl.Debit > 0
ORDER BY sl.TRN_SEQ_NO;

SELECT 'apAfter' AS _t, a.SupplierID, a.SequenceNo, a.InvoiceNo, a.ActualCost, a.AmountPaid, a.Discount, a.EWTAmount,
       a.OffsetAmount, a.Balance, a.PayStatus, a.DateUpdated, a.UpdateBy
FROM dbo.APAccounts AS a
INNER JOIN @Inv AS i ON i.SupplierID = a.SupplierID AND i.InvoiceNo = a.InvoiceNo AND i.SequenceNo = CAST(a.SequenceNo AS VARCHAR(50))
ORDER BY a.SequenceNo;

SELECT 'bsr' AS _t, b.ReconID, b.HeaderID, b.BranchCode, b.AccountCode, b.PeriodEnd, b.ItemType, b.ItemDate,
       b.Payee, b.ReferenceNo, b.Amount, b.SourceModule, b.SourceRef, b.IsResolved, b.ResolvedReason
FROM dbo.BankStatementRecon AS b
INNER JOIN @Pay AS p ON p.ReferenceNumber = b.SourceRef AND p.VoucherID = b.ReferenceNo
WHERE b.SourceModule = 'AP-PAYMENT'
ORDER BY b.ReconID;

SELECT 'sa' AS _t, sa.SupplierKey, sa.SupplierID, sa.SupplierName, sa.AccountStatus, sa.AccountBalance, sa.LastMovementDate
FROM dbo.SupplierAccounts AS sa
WHERE sa.SupplierID IN (SELECT SupplierID FROM @Pay);

------------------------------------------------------------------ step 4: the voucher is reversed
SELECT 'pra' AS _t, r.AuditID, r.VoucherID, r.SupplierID, r.VoucherType, r.ReferenceNumber, r.CancelReason, r.CancelledBy, r.CancelledDate
FROM dbo.PaymentReversalAudit AS r
INNER JOIN @Pay AS p ON p.VoucherID = CAST(r.VoucherID AS VARCHAR(20)) AND p.SupplierID = r.SupplierID;

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
WHERE sl.TransCode = 'PV-MANUAL' AND (sl.Credit > 0 OR sl.PaymentType = 'REVERSAL')
ORDER BY sl.TRN_SEQ_NO;
