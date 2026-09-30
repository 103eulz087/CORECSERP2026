/* ================================================================
   Process Trace: AR Payment (ClientPaymentsDevExAcctg)
   READ-ONLY. The builder passes @Ids = comma-separated PaymentHeaderIDs.
   Every result set starts with _t = the table id used in ARPayment.json.
   Rows are scoped by the keys the procs actually use, so the trace shows
   exactly what sp_ConfirmOrder / sp_AddPaymentClient / sp_ReversePaymentClient
   touched for these payments.
   ================================================================ */
SET NOCOUNT ON;

DECLARE @H TABLE (PaymentHeaderID INT PRIMARY KEY);
INSERT INTO @H (PaymentHeaderID)
SELECT DISTINCT TRY_CAST(LTRIM(RTRIM(value)) AS INT)
FROM STRING_SPLIT(@Ids, ',')
WHERE TRY_CAST(LTRIM(RTRIM(value)) AS INT) IS NOT NULL;

DECLARE @Ref TABLE (ReferenceNo VARCHAR(30) NOT NULL, CustomerKey CHAR(8) NOT NULL);
INSERT INTO @Ref (ReferenceNo, CustomerKey)
SELECT ph.ReferenceNo, ph.CustomerKey
FROM dbo.PaymentHeader AS ph
INNER JOIN @H AS h ON h.PaymentHeaderID = ph.PaymentHeaderID;

DECLARE @Inv TABLE (CustomerKey CHAR(8), PONumber VARCHAR(30), InvoiceNo VARCHAR(50));
INSERT INTO @Inv (CustomerKey, PONumber, InvoiceNo)
SELECT DISTINCT d.CustomerKey, d.PONumber, d.InvoiceNo
FROM dbo.ARPaymentDetails AS d
INNER JOIN @H AS h ON h.PaymentHeaderID = d.PaymentHeaderID;

-- posting tickets = the OR-* tickets of these references; reversal tickets = 'REVERSAL:' copies
DECLARE @PayTk TABLE (TicketNumber VARCHAR(30) PRIMARY KEY);
INSERT INTO @PayTk
SELECT DISTINCT CAST(tm.TicketNumber AS VARCHAR(30))
FROM dbo.TicketMaster AS tm
INNER JOIN @Ref AS r ON r.ReferenceNo = tm.ReferenceNumber
WHERE tm.Mnemonic LIKE 'OR-%';

DECLARE @RevTk TABLE (TicketNumber VARCHAR(30) PRIMARY KEY);
INSERT INTO @RevTk
SELECT DISTINCT CAST(tm.TicketNumber AS VARCHAR(30))
FROM dbo.TicketMaster AS tm
INNER JOIN @Ref AS r ON r.ReferenceNo = tm.ReferenceNumber
WHERE tm.Status = 'REVERSED' AND tm.Particulars LIKE 'REVERSAL: OR-%';

DECLARE @SalesTk TABLE (TicketNumber VARCHAR(30) PRIMARY KEY);
INSERT INTO @SalesTk
SELECT DISTINCT CAST(tm.TicketNumber AS VARCHAR(30))
FROM dbo.TicketMaster AS tm
INNER JOIN @Inv AS i ON i.PONumber = tm.ReferenceNumber AND i.InvoiceNo = tm.ReferenceKey
WHERE tm.Mnemonic LIKE 'SI-%';

------------------------------------------------------------------ step 1: sales invoice
SELECT 'tcs' AS _t, t.CustomerKey, t.BranchCode, t.TransactionDate, t.ReferenceNo, t.InvoiceNo,
       t.TotalAmount, t.PaymentType, t.DueDate, t.Remarks
FROM dbo.TransactionChargeSales AS t
INNER JOIN @Inv AS i ON i.CustomerKey = t.CustomerKey AND i.PONumber = t.ReferenceNo AND i.InvoiceNo = t.InvoiceNo
ORDER BY t.InvoiceNo;

SELECT 'tcsd' AS _t, d.SeqNo, d.BranchCode, d.ReferenceNo, d.InvoiceNo, d.TransactionDate, d.Product,
       d.Quantity, d.Cost, d.SellingPrice, d.TotalAmount, d.SKU, d.TransCode, d.Type
FROM dbo.TransactionChargeSalesDetails AS d
INNER JOIN (SELECT DISTINCT PONumber, InvoiceNo FROM @Inv) AS i ON i.PONumber = d.ReferenceNo AND i.InvoiceNo = d.InvoiceNo
ORDER BY d.InvoiceNo, d.SeqNo;

SELECT 'salesTm' AS _t, tm.TicketDate, tm.BranchCode, tm.TicketNumber, tm.ReferenceNumber, tm.ReferenceKey,
       tm.Owner, tm.Particulars, tm.Status, tm.Mnemonic, tm.EnteredBy
FROM dbo.TicketMaster AS tm
INNER JOIN @SalesTk AS k ON k.TicketNumber = CAST(tm.TicketNumber AS VARCHAR(30))
ORDER BY tm.TicketNumber;

SELECT 'salesTd' AS _t, td.TicketNumber, td.BranchCode, td.ReferenceNumber, td.ReferenceKey, td.AccountCode,
       coa.Description AS AccountName, td.Debit, td.Credit
FROM dbo.TicketDetails AS td
INNER JOIN @SalesTk AS k ON k.TicketNumber = CAST(td.TicketNumber AS VARCHAR(30))
LEFT JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = td.AccountCode
ORDER BY td.TicketNumber, td.Debit DESC;

SELECT 'salesCl' AS _t, cl.AccountKey, cl.TRN_SEQ_NO, cl.PostingDate, cl.TransCode, cl.ReferenceNumber, cl.InvoiceNo,
       cl.BeginningBalance, cl.Debit, cl.Credit, cl.EndingBalance, cl.TicketReference
FROM dbo.ClientLedger AS cl
INNER JOIN @Inv AS i ON i.CustomerKey = cl.AccountKey AND i.InvoiceNo = cl.InvoiceNo
WHERE cl.TransCode LIKE 'SI-%'
ORDER BY cl.TRN_SEQ_NO;

------------------------------------------------------------------ step 2: payment captured by the form
SELECT 'ph' AS _t, ph.PaymentHeaderID, ph.CustomerKey, ph.ReferenceNo, ph.ControlNo, ph.CRNo, ph.PaymentType,
       ph.TotalAmount, ph.PaymentDate, ph.Remarks, ph.CreatedBy, ph.Status, ph.ReversedBy, ph.ReversedDate
FROM dbo.PaymentHeader AS ph
INNER JOIN @H AS h ON h.PaymentHeaderID = ph.PaymentHeaderID
ORDER BY ph.PaymentHeaderID;

SELECT 'cheque' AS _t, tc.PaymentHeaderID, tc.BranchCode, tc.ControlNo, tc.CRNo, tc.CustomerID, tc.CustomerName,
       tc.CheckNo, tc.CheckName, tc.CheckBankName, tc.CheckAmount, tc.CheckDate, tc.Amount, tc.Remarks, tc.CreditGLCode
FROM dbo.TransactionCheque AS tc
INNER JOIN @H AS h ON h.PaymentHeaderID = tc.PaymentHeaderID;

SELECT 'online' AS _t, o.PaymentHeaderID, o.BranchCode, o.ControlNo, o.CRNo, o.CustomerID, o.CustomerName,
       o.BankRefNumber, o.BankName, o.DateDeposit, o.Amount, o.Remarks, o.CreditGLCode
FROM dbo.TransactionOnline AS o
INNER JOIN @H AS h ON h.PaymentHeaderID = o.PaymentHeaderID;

SELECT 'cash' AS _t, c.PaymentHeaderID, c.CustomerKey, c.AmountPaid, c.Remarks, c.DatePaid, c.TransactedBy, c.isErrorCorrect
FROM dbo.TransactionCashCollection AS c
INNER JOIN @H AS h ON h.PaymentHeaderID = c.PaymentHeaderID;

SELECT 'arpd' AS _t, d.PaymentHeaderID, d.CustomerKey, d.ReferenceNo, d.PONumber, d.InvoiceNo, d.InvoiceDate,
       d.PaymentType, d.Amount, d.DebitGLCode, d.CreditGLCode, d.ErrorTag
FROM dbo.ARPaymentDetails AS d
INNER JOIN @H AS h ON h.PaymentHeaderID = d.PaymentHeaderID
ORDER BY d.PaymentHeaderID, d.InvoiceNo,
         CASE d.PaymentType WHEN 'INVOICE PAYMENT' THEN 0 WHEN 'EWT' THEN 1 WHEN 'DISCOUNT' THEN 2 ELSE 3 END;

------------------------------------------------------------------ step 3: sp_AddPaymentClient posts it
SELECT 'jem' AS _t, m.Origin, m.Mnemonic, m.Seq, m.DebitCredit, m.AccountCode, m.AccountDescription,
       m.AmountType, m.IsConditional, m.ConditionFlag
FROM dbo.JournalEntryMapping AS m
WHERE m.Origin = 'OR' AND m.IsActive = 1
  AND m.Mnemonic IN (SELECT tm.Mnemonic FROM dbo.TicketMaster AS tm
                     INNER JOIN @PayTk AS k ON k.TicketNumber = CAST(tm.TicketNumber AS VARCHAR(30)))
ORDER BY m.Mnemonic, m.Seq;

SELECT 'tcsAfter' AS _t, t.CustomerKey, t.ReferenceNo, t.InvoiceNo, t.TotalAmount, t.AmountPaid, t.EWTAmount,
       t.DiscountAmount, t.OffsetAmount, t.AdvancePayment, t.Balance, t.PayStatus
FROM dbo.TransactionChargeSales AS t
INNER JOIN @Inv AS i ON i.CustomerKey = t.CustomerKey AND i.PONumber = t.ReferenceNo AND i.InvoiceNo = t.InvoiceNo
ORDER BY t.InvoiceNo;

SELECT 'payTm' AS _t, tm.TicketDate, tm.BranchCode, tm.Origin, tm.TicketNumber, tm.ReferenceNumber, tm.ReferenceKey,
       tm.Owner, tm.Particulars, tm.Status, tm.Mnemonic, tm.EnteredBy
FROM dbo.TicketMaster AS tm
INNER JOIN @PayTk AS k ON k.TicketNumber = CAST(tm.TicketNumber AS VARCHAR(30))
ORDER BY tm.TicketNumber;

SELECT 'payTd' AS _t, td.TicketNumber, td.BranchCode, td.ReferenceNumber, td.ReferenceKey, td.AccountCode,
       coa.Description AS AccountName, td.Debit, td.Credit
FROM dbo.TicketDetails AS td
INNER JOIN @PayTk AS k ON k.TicketNumber = CAST(td.TicketNumber AS VARCHAR(30))
LEFT JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = td.AccountCode
ORDER BY td.TicketNumber, td.Debit DESC;

SELECT 'payCl' AS _t, cl.AccountKey, cl.TRN_SEQ_NO, cl.PostingDate, cl.TransCode, cl.ReferenceNumber, cl.ORNumber, cl.InvoiceNo,
       cl.BeginningBalance, cl.Debit, cl.Credit, cl.EndingBalance, cl.TicketReference
FROM dbo.ClientLedger AS cl
INNER JOIN @Ref AS r ON r.ReferenceNo = cl.ReferenceNumber AND r.CustomerKey = cl.AccountKey
WHERE cl.TransCode LIKE 'OR-%' AND ISNULL(cl.Remarks, '') <> 'REVERSAL ENTRY'
ORDER BY cl.TRN_SEQ_NO;

SELECT 'bsr' AS _t, b.ReconID, b.HeaderID, b.BranchCode, b.AccountCode, b.PeriodEnd, b.ItemType, b.ItemDate,
       b.Payee, b.ReferenceNo, b.Amount, b.SourceModule, b.SourceRef, b.IsResolved, b.ResolvedReason
FROM dbo.BankStatementRecon AS b
INNER JOIN @Ref AS r ON r.ReferenceNo = b.SourceRef
WHERE b.SourceModule = 'AR-PAYMENT'
ORDER BY b.ReconID;

SELECT 'ca' AS _t, ca.AccountKey, ca.AccountID, ca.AccountName, ca.AccountStatus, ca.AccountBalance, ca.CashWalletBalance
FROM dbo.ClientAccounts AS ca
WHERE ca.AccountKey IN (SELECT CustomerKey FROM @Ref);

------------------------------------------------------------------ step 4: sp_ReversePaymentClient
SELECT 'revTm' AS _t, tm.TicketDate, tm.BranchCode, tm.TicketNumber, tm.ReferenceNumber, tm.ReferenceKey,
       tm.Particulars, tm.Status, tm.EnteredBy, tm.Product
FROM dbo.TicketMaster AS tm
INNER JOIN @RevTk AS k ON k.TicketNumber = CAST(tm.TicketNumber AS VARCHAR(30))
ORDER BY tm.TicketNumber;

SELECT 'revTd' AS _t, td.TicketNumber, td.ReferenceNumber, td.AccountCode, coa.Description AS AccountName, td.Debit, td.Credit
FROM dbo.TicketDetails AS td
INNER JOIN @RevTk AS k ON k.TicketNumber = CAST(td.TicketNumber AS VARCHAR(30))
LEFT JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = td.AccountCode
ORDER BY td.TicketNumber, td.Debit DESC;

SELECT 'revCl' AS _t, cl.AccountKey, cl.TRN_SEQ_NO, cl.PostingDate, cl.TransCode, cl.ReferenceNumber, cl.InvoiceNo,
       cl.Debit, cl.Credit, cl.EndingBalance, cl.TicketReference, cl.Remarks
FROM dbo.ClientLedger AS cl
INNER JOIN @Ref AS r ON r.ReferenceNo = cl.ReferenceNumber AND r.CustomerKey = cl.AccountKey
WHERE cl.Remarks = 'REVERSAL ENTRY'
ORDER BY cl.TRN_SEQ_NO;
