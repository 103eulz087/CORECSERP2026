/* ================================================================
   [103] TEST SCRIPT - cash advance reversal / cheque cancel refuse a bank item already ticked as cleared
   ================================================================
   Run in SSMS on DEV or STAGING AFTER [103] is applied. Every test runs inside BEGIN TRAN ... ROLLBACK, so nothing is
   left behind; the last result sets show PASS / BUG SHOWN / SKIP / FAIL per test. Do NOT run on PRODUCTION.
   "BUG SHOWN" = the _OLD_10172026180000 backup reproduces what [103] closes (a reversal that leaves the ticked item
   CLEARED for a document that no longer exists). Ticks go through the real sp_BankRecon_ResolveItem.
   A refusal rolls back the WHOLE test transaction (the procs' CATCH does ROLLBACK; THROW), the in-transaction tick
   included, so "nothing changed" is checked after the CATCH against the footprint read before the transaction; the
   cases on items that are REALLY cleared in the database (CA5, CC4, CC5a) show the item still cleared afterwards.

   Fixtures picked automatically (first result set shows them); missing fixture -> that test shows SKIP:
     - CA : the newest live cash advance (OUTSTANDING, Balance = Amount, one CashAdvance row, no invoice leg, its cheque
            voucher live) with exactly two bank items, one open OC and one open DIT (a fund transfer), nothing else under
            its reference, no LOCKED recon month at or after them, its ticket in an open GL month;
     - CA5: the newest live cash advance (same conditions, any items) with an item REALLY ticked as cleared;
     - CV : the newest live one-kind cheque voucher (CheckVoucher, invoice leg only, no cash advance) whose only bank item
            is its own open AP-PAYMENT OC, no LOCKED recon month at or after it, its tickets in an open GL month;
     - CV4: the newest live cheque voucher with an invoice leg whose AP-PAYMENT OC is REALLY ticked as cleared;
     - EXP: an open SINGLE expense (nothing paid, no EWT / discount / offset) for the combined voucher of CC5b-d,
            paid 500.00 by cheque + a 200.00 manual line to a second bank account (a cash advance with its own DIT).
   Optional: @PickCARef / @PickVoucherRef force one record. Test reference 99920 / voucher id 99930 must be unused
   (checked first). The GL must not be closed through today, nor through the fixtures' ticket dates.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT OFF;   -- the tests catch the refusals themselves

DECLARE @PickCARef VARCHAR(10) = NULL, @PickVoucherRef VARCHAR(20) = NULL;

DECLARE @r TABLE (Seq INT IDENTITY, Test VARCHAR(120), Result VARCHAR(12), Detail VARCHAR(1000));
DECLARE @fp TABLE (Cs VARCHAR(10), Run VARCHAR(10), Item VARCHAR(10), Val VARCHAR(MAX));
DECLARE @user VARCHAR(50) = 'TEST103', @ref5 VARCHAR(10) = '99920', @vid5 VARCHAR(10) = '99930', @today DATE = CAST(GETDATE() AS DATE);
DECLARE @bank VARCHAR(20) = '101020101', @branch VARCHAR(5) = '888';
DECLARE @e INT, @em NVARCHAR(2048), @tc INT, @n INT, @n2 INT, @n3 INT, @s VARCHAR(1000), @s2 VARCHAR(1000), @stage VARCHAR(20),
        @isRes BIT, @why VARCHAR(500), @st VARCHAR(30), @d1 DECIMAL(18,2), @def NVARCHAR(MAX), @run VARCHAR(10), @k INT, @x INT,
        @p1 INT, @p2 INT, @p3 INT, @p4 INT;

------------------------------------------------------------------
-- 0. install check
------------------------------------------------------------------
IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReverseCashAdvanceEntry')) NOT LIKE '%THROW 93031%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS')) NOT LIKE '%THROW 93032%'
BEGIN
    INSERT @r VALUES ('I0 install check', 'FAIL', '[103] is not installed');
    SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
    RETURN;
END
IF OBJECT_ID('dbo.sp_ReverseCashAdvanceEntry_OLD_10172026180000', 'P') IS NULL OR OBJECT_ID('dbo.sp_CancelledChequesCS_OLD_10172026180000', 'P') IS NULL
BEGIN
    INSERT @r VALUES ('I0 install check', 'FAIL', '[103] backups _OLD_10172026180000 missing; the old = new / BUG SHOWN tests need them');
    SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
    RETURN;
END
INSERT @r VALUES ('I0 install check', CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReverseCashAdvanceEntry_OLD_10172026180000')) NOT LIKE '%93031%'
                                            AND OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS_OLD_10172026180000')) NOT LIKE '%93032%' THEN 'PASS' ELSE 'FAIL' END,
                  'both procs carry [103] (THROW 93031 / 93032); backups _OLD_10172026180000 present and without the new checks');

-- I1: the new checks sit before each proc's first write and before the lock checks (a refusal rolls everything back,
--     so a run-time "nothing changed" alone can't show the order)
SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReverseCashAdvanceEntry'));
SELECT @p1 = CHARINDEX('THROW 93031', @def), @p2 = CHARINDEX('INSERT INTO TicketMaster', @def), @p3 = CHARINDEX('UPDATE dbo.CashAdvance', @def), @p4 = CHARINDEX('THROW 93027', @def);
INSERT @r VALUES ('I1a cash advance: 93031 before the first write and before the 93027 lock check',
                  CASE WHEN @p1 > 0 AND @p1 < @p2 AND @p1 < @p3 AND @p1 < @p4 THEN 'PASS' ELSE 'FAIL' END,
                  CONCAT('position THROW 93031 ', @p1, ', INSERT INTO TicketMaster ', @p2, ', UPDATE dbo.CashAdvance ', @p3, ', THROW 93027 ', @p4));
SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS'));
SELECT @p1 = CHARINDEX('THROW 93032', @def), @p2 = CHARINDEX('UPDATE CheckVoucher', @def), @p3 = CHARINDEX('INSERT INTO PaymentReversalAudit', @def), @p4 = CHARINDEX('EXEC [dbo].[sp_BankRecon_VoidOC]', @def);
INSERT @r VALUES ('I1b cheque cancel: 93032 before the first write and before sp_BankRecon_VoidOC (its 93006 lock check)',
                  CASE WHEN @p1 > 0 AND @p1 < @p2 AND @p1 < @p3 AND @p1 < @p4 THEN 'PASS' ELSE 'FAIL' END,
                  CONCAT('position THROW 93032 ', @p1, ', UPDATE CheckVoucher ', @p2, ', INSERT INTO PaymentReversalAudit ', @p3, ', EXEC sp_BankRecon_VoidOC ', @p4));

------------------------------------------------------------------
-- 1. footprint queries (one row per table the reversals write; dates of today, ids and ticket numbers left out)
------------------------------------------------------------------
DECLARE @qCA NVARCHAR(MAX) = N'
SELECT @cs, @run, ''CA'', (SELECT STRING_AGG(CONCAT(Status, ''|'', Balance, ''|'', Amount), '','') WITHIN GROUP (ORDER BY CashAdvanceID) FROM dbo.CashAdvance WHERE ReferenceNo = @ref)
UNION ALL SELECT @cs, @run, ''BSR'', (SELECT STRING_AGG(CONCAT(ReconID, '':'', ItemType, '':'', Amount, '':'', CAST(IsResolved AS INT), '':'', ISNULL(ResolvedReason, ''-''), '':'', ISNULL(ResolvedBy, ''-''), '':'', ISNULL(CONVERT(VARCHAR(10), ClearedPeriodEnd, 120), ''-'')), '','') WITHIN GROUP (ORDER BY ReconID)
                                     FROM dbo.BankStatementRecon WHERE SourceRef = @ref)
UNION ALL SELECT @cs, @run, ''TKREV'', (SELECT CONCAT(COUNT(*), ''|'', STRING_AGG(CONCAT(BranchCode, '':'', Mnemonic, '':'', Status, '':'', Origin, '':'', CONVERT(VARCHAR(10), TicketDate, 120)), '','') WITHIN GROUP (ORDER BY BranchCode, Mnemonic))
                                       FROM dbo.TicketMaster WHERE ReferenceNumber = @ref AND Product = ''REVERSAL'' AND EnteredBy = @user)
UNION ALL SELECT @cs, @run, ''TKDREV'', (SELECT CONCAT(COUNT(*), ''|'', STRING_AGG(CONCAT(d.BranchCode, '':'', d.AccountCode, '':'', d.Debit, '':'', d.Credit, '':'', CONVERT(VARCHAR(10), d.TicketDate, 120)), '','') WITHIN GROUP (ORDER BY d.BranchCode, d.AccountCode, d.Debit, d.Credit))
                                        FROM dbo.TicketDetails AS d INNER JOIN dbo.TicketMaster AS m ON m.TicketNumber = d.TicketNumber AND m.BranchCode = d.BranchCode
                                        WHERE m.ReferenceNumber = @ref AND d.ReferenceNumber = @ref AND m.Product = ''REVERSAL'' AND m.EnteredBy = @user)
UNION ALL SELECT @cs, @run, ''NET'', CAST((SELECT COUNT(*) FROM (SELECT d.AccountCode FROM dbo.TicketDetails AS d
                                     WHERE d.ReferenceNumber = @ref
                                       AND d.TicketNumber IN (SELECT TicketNumber FROM dbo.CashAdvance WHERE ReferenceNo = @ref
                                                              UNION SELECT TicketNumber FROM dbo.TicketMaster WHERE ReferenceNumber = @ref AND Product = ''REVERSAL'' AND EnteredBy = @user)
                                     GROUP BY d.AccountCode HAVING ABS(SUM(ISNULL(d.Debit, 0)) - SUM(ISNULL(d.Credit, 0))) > 0.004) AS x) AS VARCHAR(10))
UNION ALL SELECT @cs, @run, ''AUD'', CAST((SELECT COUNT(*) FROM dbo.ExpenseApprovalReversalAudit WHERE ReferenceNumber = @ref AND ReversedBy = @user) AS VARCHAR(10))
UNION ALL SELECT @cs, @run, ''CV'', (SELECT STRING_AGG(CONCAT(VoucherID, '':'', ISNULL(CAST(isErrorCorrect AS INT), 0)), '','') WITHIN GROUP (ORDER BY VoucherID) FROM dbo.CheckVoucher WHERE ReferenceNumber = @ref);';

DECLARE @qCV NVARCHAR(MAX) = N'
SELECT @cs, @run, ''CV'', (SELECT STRING_AGG(CONCAT(ISNULL(CAST(isErrorCorrect AS INT), 0), ''|'', ISNULL(CancelledBy, ''-''), ''|'', ISNULL(CancelReason, ''-'')), '','')
                         FROM dbo.CheckVoucher WHERE ReferenceNumber = @ref AND CAST(VoucherID AS VARCHAR(10)) = @vid)
UNION ALL SELECT @cs, @run, ''PRA'', (SELECT CONCAT(COUNT(*), ''|'', MAX(VoucherType), ''|'', MAX(CancelledBy)) FROM dbo.PaymentReversalAudit WHERE ReferenceNumber = @ref AND SupplierID = @sup)
UNION ALL SELECT @cs, @run, ''CVC'', (SELECT CONCAT(COUNT(*), ''|'', SUM(Amount)) FROM dbo.CheckVoucherCancelled WHERE ReferenceNumber = @ref AND CAST(VoucherID AS VARCHAR(10)) = @vid)
UNION ALL SELECT @cs, @run, ''ES'', (SELECT STRING_AGG(CONCAT(es.InvoiceNo, '':'', es.Balance, '':'', ISNULL(es.AmountPaid, 0), '':'', es.Status, '':'', ISNULL(es.EWTWithheld, 0), '':'', ISNULL(es.DiscountWithheld, 0), '':'', ISNULL(es.OffsetWithheld, 0)), '','') WITHIN GROUP (ORDER BY es.BatchReferenceID, es.InvoiceNo)
                                    FROM dbo.ExpenseSummary AS es
                                    WHERE es.SupplierID = @sup AND EXISTS (SELECT 1 FROM dbo.APPaymentDetails AS a WHERE a.ReferenceNumber = @ref AND a.VoucherID = @vid AND a.PaymentMethod = ''EXPENSE''
                                                                                                       AND a.BatchReferenceID = es.BatchReferenceID AND a.InvoiceNo = es.InvoiceNo))
UNION ALL SELECT @cs, @run, ''EM'', (SELECT STRING_AGG(CONCAT(em.BranchCode, '':'', em.Amount, '':'', ISNULL(em.AmountPaid, 0), '':'', ISNULL(em.Balance, -1), '':'', em.Status, '':'', ISNULL(em.EWTAmount, 0)), '','') WITHIN GROUP (ORDER BY em.TRN_SEQ_NO)
                                    FROM dbo.ExpenseMaster AS em
                                    WHERE em.SupplierID = @sup AND EXISTS (SELECT 1 FROM dbo.APPaymentDetails AS a WHERE a.ReferenceNumber = @ref AND a.VoucherID = @vid AND a.PaymentMethod = ''EXPENSE''
                                                                                                       AND a.BatchReferenceID = em.BatchReferenceID AND a.InvoiceNo = em.InvoiceNo))
UNION ALL SELECT @cs, @run, ''AP'', (SELECT STRING_AGG(CONCAT(ap.SequenceNo, '':'', ap.Balance, '':'', ap.PayStatus, '':'', ISNULL(ap.AmountPaid, 0)), '','') WITHIN GROUP (ORDER BY ap.SequenceNo)
                                    FROM dbo.APAccounts AS ap
                                    WHERE ap.SupplierID = @sup AND EXISTS (SELECT 1 FROM dbo.APPaymentDetails AS a WHERE a.ReferenceNumber = @ref AND a.VoucherID = @vid AND a.PaymentMethod = ''PURCHASE''
                                                                                                       AND a.SequenceReferenceNumber = CAST(ap.SequenceNo AS VARCHAR(10))))
UNION ALL SELECT @cs, @run, ''TPAP'', (SELECT CONCAT(COUNT(*), ''|'', SUM(CAST(ErrorCorrect AS INT))) FROM dbo.TransactionPaymentAP WHERE SupplierKey = @sup AND ReferenceNumber = CAST(@ref AS INT))
UNION ALL SELECT @cs, @run, ''SL'', (SELECT CONCAT(COUNT(*), ''|'', SUM(ISNULL(Debit, 0)), ''|'', SUM(ISNULL(Credit, 0)), ''|'', SUM(CAST(ISNULL(ErrorCorrectTag, 0) AS INT)), ''|'',
                                           STRING_AGG(CONCAT(PaymentType, '':'', InvoiceNo, '':'', CONVERT(VARCHAR(10), TransactionDate, 120)), '','') WITHIN GROUP (ORDER BY PaymentType, InvoiceNo, TRN_SEQ_NO))
                                    FROM dbo.SupplierLedger WHERE SupplierID = @sup AND ReferenceNumber = @ref)
UNION ALL SELECT @cs, @run, ''TKREV'', (SELECT CONCAT(COUNT(*), ''|'', STRING_AGG(CONCAT(BranchCode, '':'', Mnemonic, '':'', Status, '':'', CONVERT(VARCHAR(10), TicketDate, 120)), '','') WITHIN GROUP (ORDER BY BranchCode, Mnemonic))
                                       FROM dbo.TicketMaster WHERE ReferenceNumber = @ref AND ReferenceKey = @vid AND Product = ''REVERSAL'' AND EnteredBy = @user)
UNION ALL SELECT @cs, @run, ''NET'', CAST((SELECT COUNT(*) FROM (SELECT d.AccountCode FROM dbo.TicketDetails AS d
                                     WHERE d.ReferenceNumber = @ref AND d.ReferenceKey = @vid
                                     GROUP BY d.AccountCode HAVING ABS(SUM(ISNULL(d.Debit, 0)) - SUM(ISNULL(d.Credit, 0))) > 0.004) AS x) AS VARCHAR(10))
UNION ALL SELECT @cs, @run, ''BSR'', (SELECT STRING_AGG(CONCAT(ReconID, '':'', ItemType, '':'', ISNULL(SourceModule, ''-''), '':'', Amount, '':'', CAST(IsResolved AS INT), '':'', ISNULL(ResolvedReason, ''-'')), '','') WITHIN GROUP (ORDER BY ReconID)
                                     FROM dbo.BankStatementRecon WHERE SourceRef = @ref)
UNION ALL SELECT @cs, @run, ''SA'', (SELECT CONCAT(MAX(sa.AccountBalance), ''|'', (SELECT SUM(ISNULL(l.Credit, 0) - ISNULL(l.Debit, 0)) FROM dbo.SupplierLedger AS l WHERE l.SupplierID = @sup))
                                    FROM dbo.SupplierAccounts AS sa WHERE sa.SupplierID = @sup);';
DECLARE @pCA NVARCHAR(200) = N'@cs VARCHAR(10), @run VARCHAR(10), @ref VARCHAR(10), @user VARCHAR(50)',
        @pCV NVARCHAR(300) = N'@cs VARCHAR(10), @run VARCHAR(10), @ref VARCHAR(20), @vid VARCHAR(10), @sup VARCHAR(50), @user VARCHAR(50)';

------------------------------------------------------------------
-- 2. fixtures and pre-checks
------------------------------------------------------------------
IF (SELECT COUNT(*) FROM dbo.BankStatementRecon WHERE SourceRef = @ref5 OR ReferenceNo IN (@ref5, @vid5))
 + (SELECT COUNT(*) FROM dbo.CashAdvance WHERE ReferenceNo = @ref5 OR VoucherID = @vid5)
 + (SELECT COUNT(*) FROM dbo.CheckVoucher WHERE ReferenceNumber = @ref5 OR VoucherID = CAST(@vid5 AS DECIMAL(7,0)))
 + (SELECT COUNT(*) FROM dbo.CashVoucher WHERE ReferenceNumber = @ref5 OR VoucherID = CAST(@vid5 AS DECIMAL(7,0)))
 + (SELECT COUNT(*) FROM dbo.APPaymentDetails WHERE ReferenceNumber = @ref5 OR VoucherID = @vid5)
 + (SELECT COUNT(*) FROM dbo.TransactionPaymentAP WHERE ReferenceNumber = CAST(@ref5 AS INT))
 + (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber = @ref5)
 + (SELECT COUNT(*) FROM dbo.SupplierLedger WHERE ReferenceNumber = @ref5)
 + (SELECT COUNT(*) FROM dbo.PaymentReversalAudit WHERE ReferenceNumber = @ref5) > 0
BEGIN
    INSERT @r VALUES ('fixtures', 'ERROR', 'test reference 99920 / voucher id 99930 is in use here; nothing was run');
    SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
    RETURN;
END
IF EXISTS (SELECT 1 FROM dbo.GLPeriodLock WHERE LockedThroughDate >= @today)
BEGIN
    INSERT @r VALUES ('fixtures', 'ERROR', 'the GL is closed through today; the postings and reversals would be refused (59900)');
    SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
    RETURN;
END
DECLARE @glLock DATE = (SELECT MAX(LockedThroughDate) FROM dbo.GLPeriodLock);
DECLARE @lockedBefore INT = (SELECT COUNT(*) FROM dbo.BankReconHeader WHERE Status = 'LOCKED');

-- CA: live cash advance with one open OC + one open DIT (fund transfer)
DECLARE @caRef VARCHAR(10), @caVid VARCHAR(10), @caSup VARCHAR(50), @caAmt DECIMAL(18,2);
SELECT TOP (1) @caRef = c.ReferenceNo, @caVid = c.VoucherID, @caSup = c.SupplierID, @caAmt = c.Amount
FROM dbo.CashAdvance AS c
WHERE c.Status = 'OUTSTANDING' AND c.Balance = c.Amount AND c.Amount > 0 AND (@PickCARef IS NULL OR c.ReferenceNo = @PickCARef)
  AND (SELECT COUNT(*) FROM dbo.CashAdvance AS x WHERE x.ReferenceNo = c.ReferenceNo) = 1
  AND NOT EXISTS (SELECT 1 FROM dbo.APPaymentDetails AS a WHERE a.ReferenceNumber = c.ReferenceNo)
  AND EXISTS (SELECT 1 FROM dbo.CheckVoucher AS v WHERE v.ReferenceNumber = c.ReferenceNo AND CAST(v.VoucherID AS VARCHAR(10)) = c.VoucherID AND ISNULL(v.isErrorCorrect, 0) = 0)
  AND (SELECT COUNT(*) FROM dbo.BankStatementRecon AS b WHERE b.SourceRef = c.ReferenceNo) = 2
  AND EXISTS (SELECT 1 FROM dbo.BankStatementRecon AS b WHERE b.ReferenceNo = c.VoucherID AND b.SourceModule = 'CASH-ADVANCE' AND b.SourceRef = c.ReferenceNo AND b.ItemType = 'OC' AND b.IsResolved = 0 AND b.Amount <> 0)
  AND EXISTS (SELECT 1 FROM dbo.BankStatementRecon AS b WHERE b.ReferenceNo = c.VoucherID AND b.SourceModule = 'CASH-ADVANCE' AND b.SourceRef = c.ReferenceNo AND b.ItemType = 'DIT' AND b.IsResolved = 0 AND b.Amount <> 0)
  AND NOT EXISTS (SELECT 1 FROM dbo.BankStatementRecon AS b INNER JOIN dbo.BankReconHeader AS hb ON hb.HeaderID = b.HeaderID
                  INNER JOIN dbo.BankReconHeader AS h ON h.BranchCode = hb.BranchCode AND h.AccountCode = hb.AccountCode AND h.Status = 'LOCKED' AND h.PeriodEnd >= hb.PeriodEnd
                  WHERE b.SourceRef = c.ReferenceNo)
  AND EXISTS (SELECT 1 FROM dbo.TicketMaster AS t WHERE t.TicketNumber = c.TicketNumber AND t.ReferenceNumber = c.ReferenceNo AND (@glLock IS NULL OR t.TicketDate > @glLock))
ORDER BY c.CashAdvanceID DESC;
DECLARE @caOC INT, @caOCHdr INT, @caOCPer DATE, @caOCAmt DECIMAL(18,2), @caDIT INT, @caDITHdr INT, @caDITPer DATE;
SELECT @caOC = b.ReconID, @caOCHdr = h.HeaderID, @caOCPer = h.PeriodEnd, @caOCAmt = b.Amount
FROM dbo.BankStatementRecon AS b INNER JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
WHERE b.ReferenceNo = @caVid AND b.SourceModule = 'CASH-ADVANCE' AND b.SourceRef = @caRef AND b.ItemType = 'OC';
SELECT @caDIT = b.ReconID, @caDITHdr = h.HeaderID, @caDITPer = h.PeriodEnd
FROM dbo.BankStatementRecon AS b INNER JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
WHERE b.ReferenceNo = @caVid AND b.SourceModule = 'CASH-ADVANCE' AND b.SourceRef = @caRef AND b.ItemType = 'DIT';

-- CA5: live cash advance with an item really ticked as cleared
DECLARE @ca5Ref VARCHAR(10), @ca5Vid VARCHAR(10), @ca5Sup VARCHAR(50), @ca5Recon INT, @ca5Amt DECIMAL(18,2);
SELECT TOP (1) @ca5Ref = c.ReferenceNo, @ca5Vid = c.VoucherID, @ca5Sup = c.SupplierID, @ca5Recon = b.ReconID, @ca5Amt = b.Amount
FROM dbo.CashAdvance AS c
INNER JOIN dbo.BankStatementRecon AS b ON b.ReferenceNo = c.VoucherID AND b.SourceModule = 'CASH-ADVANCE' AND b.SourceRef = c.ReferenceNo
                                       AND b.IsResolved = 1 AND b.Amount <> 0 AND ISNULL(b.ResolvedReason, '') <> 'REVERSED' AND ISNULL(b.ResolvedReason, '') NOT LIKE 'VOID%'
WHERE c.Status = 'OUTSTANDING' AND c.Balance = c.Amount AND c.Amount > 0
  AND (SELECT COUNT(*) FROM dbo.CashAdvance AS x WHERE x.ReferenceNo = c.ReferenceNo) = 1
  AND NOT EXISTS (SELECT 1 FROM dbo.APPaymentDetails AS a WHERE a.ReferenceNumber = c.ReferenceNo)
  AND EXISTS (SELECT 1 FROM dbo.CheckVoucher AS v WHERE v.ReferenceNumber = c.ReferenceNo AND CAST(v.VoucherID AS VARCHAR(10)) = c.VoucherID AND ISNULL(v.isErrorCorrect, 0) = 0)
ORDER BY c.CashAdvanceID DESC, b.ReconID;

-- CV: live one-kind cheque voucher with its own open AP-PAYMENT OC only
DECLARE @cvRef VARCHAR(20), @cvVid VARCHAR(10), @cvSup VARCHAR(50), @cvType VARCHAR(20), @cvAmt DECIMAL(18,2);
SELECT TOP (1) @cvRef = v.ReferenceNumber, @cvVid = CAST(v.VoucherID AS VARCHAR(10)), @cvSup = v.SupplierID, @cvAmt = v.Amount,
       @cvType = (SELECT MIN(a.PaymentMethod) FROM dbo.APPaymentDetails AS a WHERE a.ReferenceNumber = v.ReferenceNumber AND a.VoucherID = CAST(v.VoucherID AS VARCHAR(10)))
FROM dbo.CheckVoucher AS v
WHERE ISNULL(v.isErrorCorrect, 0) = 0 AND v.Amount > 0 AND (@PickVoucherRef IS NULL OR v.ReferenceNumber = @PickVoucherRef)
  AND (SELECT COUNT(*) FROM dbo.CheckVoucher AS x WHERE x.ReferenceNumber = v.ReferenceNumber) = 1
  AND NOT EXISTS (SELECT 1 FROM dbo.PaymentReversalAudit AS ra WHERE ra.ReferenceNumber = v.ReferenceNumber)
  AND NOT EXISTS (SELECT 1 FROM dbo.CashAdvance AS c WHERE c.ReferenceNo = v.ReferenceNumber)
  AND (SELECT COUNT(DISTINCT a.PaymentMethod) FROM dbo.APPaymentDetails AS a WHERE a.ReferenceNumber = v.ReferenceNumber AND a.VoucherID = CAST(v.VoucherID AS VARCHAR(10)) AND a.SupplierID = v.SupplierID) = 1
  AND NOT EXISTS (SELECT 1 FROM dbo.APPaymentDetails AS a WHERE a.ReferenceNumber = v.ReferenceNumber AND (a.VoucherID <> CAST(v.VoucherID AS VARCHAR(10)) OR a.SupplierID <> v.SupplierID))
  AND (SELECT COUNT(*) FROM dbo.BankStatementRecon AS b WHERE b.SourceRef = v.ReferenceNumber) = 1
  AND EXISTS (SELECT 1 FROM dbo.BankStatementRecon AS b WHERE b.SourceRef = v.ReferenceNumber AND b.ReferenceNo = CAST(v.VoucherID AS VARCHAR(10))
                                                         AND b.SourceModule = 'AP-PAYMENT' AND b.ItemType = 'OC' AND b.IsResolved = 0 AND b.Amount <> 0)
  AND NOT EXISTS (SELECT 1 FROM dbo.BankStatementRecon AS b INNER JOIN dbo.BankReconHeader AS hb ON hb.HeaderID = b.HeaderID
                  INNER JOIN dbo.BankReconHeader AS h ON h.BranchCode = hb.BranchCode AND h.AccountCode = hb.AccountCode AND h.Status = 'LOCKED' AND h.PeriodEnd >= hb.PeriodEnd
                  WHERE b.SourceRef = v.ReferenceNumber)
  AND EXISTS (SELECT 1 FROM dbo.TicketMaster AS t WHERE t.ReferenceNumber = v.ReferenceNumber AND t.ReferenceKey = CAST(v.VoucherID AS VARCHAR(10)))
  AND NOT EXISTS (SELECT 1 FROM dbo.TicketMaster AS t WHERE t.ReferenceNumber = v.ReferenceNumber AND t.ReferenceKey = CAST(v.VoucherID AS VARCHAR(10)) AND @glLock IS NOT NULL AND t.TicketDate <= @glLock)
ORDER BY v.VoucherID DESC;
DECLARE @cvOC INT, @cvHdr INT, @cvPer DATE;
SELECT @cvOC = b.ReconID, @cvHdr = h.HeaderID, @cvPer = h.PeriodEnd
FROM dbo.BankStatementRecon AS b INNER JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
WHERE b.SourceRef = @cvRef AND b.ReferenceNo = @cvVid AND b.ItemType = 'OC';

-- CV4: live cheque voucher whose OC is really ticked as cleared
DECLARE @cv4Ref VARCHAR(20), @cv4Vid VARCHAR(10), @cv4Sup VARCHAR(50), @cv4Type VARCHAR(20), @cv4Recon INT, @cv4Amt DECIMAL(18,2);
SELECT TOP (1) @cv4Ref = v.ReferenceNumber, @cv4Vid = CAST(v.VoucherID AS VARCHAR(10)), @cv4Sup = v.SupplierID, @cv4Recon = b.ReconID, @cv4Amt = b.Amount,
       @cv4Type = (SELECT MIN(a.PaymentMethod) FROM dbo.APPaymentDetails AS a WHERE a.ReferenceNumber = v.ReferenceNumber AND a.VoucherID = CAST(v.VoucherID AS VARCHAR(10)))
FROM dbo.CheckVoucher AS v
INNER JOIN dbo.BankStatementRecon AS b ON b.SourceRef = v.ReferenceNumber AND b.ReferenceNo = CAST(v.VoucherID AS VARCHAR(10)) AND b.ItemType = 'OC' AND b.SourceModule = 'AP-PAYMENT'
                                       AND b.IsResolved = 1 AND b.Amount <> 0 AND ISNULL(b.ResolvedReason, '') <> 'REVERSED' AND ISNULL(b.ResolvedReason, '') NOT LIKE 'VOID%'
WHERE ISNULL(v.isErrorCorrect, 0) = 0
  AND NOT EXISTS (SELECT 1 FROM dbo.PaymentReversalAudit AS ra WHERE ra.ReferenceNumber = v.ReferenceNumber)
  AND EXISTS (SELECT 1 FROM dbo.APPaymentDetails AS a WHERE a.ReferenceNumber = v.ReferenceNumber AND a.VoucherID = CAST(v.VoucherID AS VARCHAR(10)) AND a.SupplierID = v.SupplierID)
ORDER BY v.VoucherID DESC;

-- EXP: open SINGLE expense for the combined voucher (CC5b-d) + a second bank account for its manual line
DECLARE @caBank VARCHAR(20) = (SELECT TOP (1) AccountCode FROM dbo.CashAdvanceAllowedAccounts WHERE AccountCode LIKE '1010201%' AND LEN(AccountCode) = 9 AND AccountCode <> @bank ORDER BY AccountCode);
DECLARE @xSup VARCHAR(50), @xSupName VARCHAR(150), @xRef VARCHAR(10), @xInv VARCHAR(150), @xBatch BIGINT, @xAmt DECIMAL(18,2), @xBal DECIMAL(18,2), @xDate DATE, @xBranch CHAR(3), @xBefore VARCHAR(400);
SELECT TOP (1) @xSup = es.SupplierID, @xSupName = s.SupplierName, @xRef = es.ReferenceNumber, @xInv = es.InvoiceNo, @xBatch = es.BatchReferenceID, @xAmt = es.Amount,
       @xBal = es.Balance, @xDate = es.ExpenseDate,
       @xBranch = (SELECT TOP (1) m.BranchCode FROM dbo.ExpenseMaster AS m WHERE m.SupplierID = es.SupplierID AND m.InvoiceNo = es.InvoiceNo AND m.BatchReferenceID = es.BatchReferenceID ORDER BY m.TRN_SEQ_NO)
FROM dbo.ExpenseSummary AS es INNER JOIN dbo.Supplier AS s ON s.SupplierID = es.SupplierID AND s.SupplierKey = es.SupplierID
WHERE es.Status NOT IN ('PAID', 'VOID', 'CANCELLED', 'FOR APPROVAL', 'FULLYPAID') AND es.PostingMode = 'SINGLE' AND es.PayableAccountCode IS NOT NULL
  AND es.Balance = es.Amount AND es.Balance >= 500 AND ISNULL(es.AmountPaid, 0) = 0
  AND ISNULL(es.EWTAmount, 0) = 0 AND ISNULL(es.DiscountAmount, 0) = 0 AND ISNULL(es.OffsetAmount, 0) = 0
  AND (SELECT COUNT(*) FROM dbo.ExpenseSummary AS z WHERE z.SupplierID = es.SupplierID AND z.BatchReferenceID = es.BatchReferenceID AND z.InvoiceNo = es.InvoiceNo) = 1
  AND EXISTS (SELECT 1 FROM dbo.ExpenseMaster AS m WHERE m.SupplierID = es.SupplierID AND m.InvoiceNo = es.InvoiceNo AND m.BatchReferenceID = es.BatchReferenceID)
  AND NOT EXISTS (SELECT 1 FROM dbo.BankReconHeader AS h WHERE h.Status = 'LOCKED' AND h.AccountCode IN (@bank, @caBank) AND h.PeriodEnd >= EOMONTH(@today))
ORDER BY es.BatchReferenceID DESC;
SELECT @xBefore = CONCAT(Balance, '|', ISNULL(AmountPaid, 0), '|', Status) FROM dbo.ExpenseSummary WHERE SupplierID = @xSup AND BatchReferenceID = @xBatch AND InvoiceNo = @xInv;

SELECT 'fixtures' AS what, @caRef AS ca_ref, @caVid AS ca_voucher, @caAmt AS ca_amount, @caOC AS ca_oc_recon, @caOCPer AS ca_oc_month, @caDIT AS ca_dit_recon, @caDITPer AS ca_dit_month,
       @ca5Ref AS ca5_ref, @ca5Vid AS ca5_voucher, @ca5Recon AS ca5_cleared_recon,
       @cvRef AS cv_ref, @cvVid AS cv_voucher, @cvSup AS cv_supplier, @cvType AS cv_kind, @cvOC AS cv_oc_recon, @cvPer AS cv_oc_month,
       @cv4Ref AS cv4_ref, @cv4Vid AS cv4_voucher, @cv4Recon AS cv4_cleared_recon,
       @xRef AS exp_ref, @xInv AS exp_invoice, @xBal AS exp_balance, @caBank AS manual_line_bank, @glLock AS gl_locked_through, @lockedBefore AS locked_recon_headers;

IF @caRef IS NULL AND @ca5Ref IS NULL AND @cvRef IS NULL AND @cv4Ref IS NULL AND @xRef IS NULL
BEGIN
    INSERT @r VALUES ('fixtures', 'SKIP', 'no live cash advance / cheque voucher / open expense fits; every test skipped');
    GOTO Report;
END
INSERT @r VALUES ('fixtures', 'PASS', CONCAT('CA ', ISNULL(@caRef, '-'), ' / voucher ', ISNULL(@caVid, '-'), ' (OC ', ISNULL(CAST(@caOC AS VARCHAR(10)), '-'), ', DIT ', ISNULL(CAST(@caDIT AS VARCHAR(10)), '-'),
                                             '); CA5 ', ISNULL(@ca5Ref, '-'), ' (cleared ', ISNULL(CAST(@ca5Recon AS VARCHAR(10)), '-'), '); CV ', ISNULL(@cvRef, '-'), ' / ', ISNULL(@cvVid, '-'), ' ', ISNULL(@cvType, '-'),
                                             ' (OC ', ISNULL(CAST(@cvOC AS VARCHAR(10)), '-'), '); CV4 ', ISNULL(@cv4Ref, '-'), ' / ', ISNULL(@cv4Vid, '-'), ' (cleared ', ISNULL(CAST(@cv4Recon AS VARCHAR(10)), '-'),
                                             '); EXP ', ISNULL(@xRef, '-'), ' ', ISNULL(@xInv, '-'), ', manual line bank ', ISNULL(@caBank, '-')));

-- "before" footprints of the fixtures (read outside any transaction)
IF @caRef IS NOT NULL  INSERT @fp EXEC sp_executesql @qCA, @pCA, @cs = 'CA', @run = 'pre', @ref = @caRef, @user = @user;
IF @ca5Ref IS NOT NULL INSERT @fp EXEC sp_executesql @qCA, @pCA, @cs = 'CA5', @run = 'pre', @ref = @ca5Ref, @user = @user;
IF @cvRef IS NOT NULL  INSERT @fp EXEC sp_executesql @qCV, @pCV, @cs = 'CV', @run = 'pre', @ref = @cvRef, @vid = @cvVid, @sup = @cvSup, @user = @user;
IF @cv4Ref IS NOT NULL INSERT @fp EXEC sp_executesql @qCV, @pCV, @cs = 'CV4', @run = 'pre', @ref = @cv4Ref, @vid = @cv4Vid, @sup = @cv4Sup, @user = @user;

------------------------------------------------------------------
-- CA1 old = new: live cash advance with open items reversed by both procs
------------------------------------------------------------------
IF @caRef IS NULL
    INSERT @r VALUES ('CA1 cash advance with open items: old = new footprint', 'SKIP', 'no live cash advance with an open OC + DIT');
ELSE
BEGIN
    SET @run = 'old';
    WHILE @run IS NOT NULL
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            IF @run = 'old'
                EXEC dbo.sp_ReverseCashAdvanceEntry_OLD_10172026180000 @parmreferenceno = @caRef, @parmreason = 'TEST103 CA1 (rolled back)', @parmuser = @user;
            ELSE
                EXEC dbo.sp_ReverseCashAdvanceEntry @parmreferenceno = @caRef, @parmreason = 'TEST103 CA1 (rolled back)', @parmuser = @user;
            INSERT @fp EXEC sp_executesql @qCA, @pCA, @cs = 'CA1', @run = @run, @ref = @caRef, @user = @user;
        END TRY
        BEGIN CATCH
            INSERT @r VALUES (CONCAT('CA1 ', @run, ' proc'), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE()));
        END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
    END
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE Cs = 'CA1' AND Run = 'old' EXCEPT SELECT Item, Val FROM @fp WHERE Cs = 'CA1' AND Run = 'new') AS a;
    SELECT @n2 = COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE Cs = 'CA1' AND Run = 'new' EXCEPT SELECT Item, Val FROM @fp WHERE Cs = 'CA1' AND Run = 'old') AS a;
    SELECT @n3 = COUNT(*) FROM @fp WHERE Cs = 'CA1' AND Run = 'new';
    SELECT @s = (SELECT Val FROM @fp WHERE Cs = 'CA1' AND Run = 'new' AND Item = 'CA'), @s2 = (SELECT Val FROM @fp WHERE Cs = 'CA1' AND Run = 'new' AND Item = 'BSR');
    INSERT @r VALUES ('CA1 cash advance with open items: old = new footprint (tickets, CashAdvance, recon items voided)',
                      CASE WHEN @n = 0 AND @n2 = 0 AND @n3 = 7 AND (SELECT COUNT(*) FROM @fp WHERE Cs = 'CA1' AND Run = 'old') = 7 AND @s LIKE 'REVERSED|0.00|%'
                                AND @s2 NOT LIKE '%:0:%' AND (SELECT Val FROM @fp WHERE Cs = 'CA1' AND Run = 'new' AND Item = 'NET') = '0' THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('ref ', @caRef, ' ', FORMAT(@caAmt, 'N2'), ': ', @n, ' + ', @n2, ' of ', @n3, ' footprint rows differ; CashAdvance ', @s, '; items ', @s2,
                             '; reversal tickets ', (SELECT Val FROM @fp WHERE Cs = 'CA1' AND Run = 'new' AND Item = 'TKREV'), '; accounts not netting to 0: ', (SELECT Val FROM @fp WHERE Cs = 'CA1' AND Run = 'new' AND Item = 'NET')));
END

------------------------------------------------------------------
-- CA2 / CA2b new proc: its OC (CA2) or DIT (CA2b) ticked cleared in the transaction -> 93031, nothing changed
------------------------------------------------------------------
SET @k = 1;
WHILE @k <= 2
BEGIN
    IF @caRef IS NULL
        INSERT @r VALUES (CASE @k WHEN 1 THEN 'CA2 cash advance, OC ticked cleared: refused 93031' ELSE 'CA2b cash advance, DIT ticked cleared: refused 93031' END, 'SKIP', 'no CA fixture');
    ELSE
    BEGIN
        SELECT @e = NULL, @em = NULL, @stage = 'tick';
        DELETE @fp WHERE Cs = 'CA2';
        BEGIN TRAN;
        BEGIN TRY
            IF @k = 1
                EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @caOC, @IsResolved = 1, @ResolvedBy = @user, @PeriodEnd = @caOCPer;
            ELSE
                EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @caDIT, @IsResolved = 1, @ResolvedBy = @user, @PeriodEnd = @caDITPer;
            SET @stage = 'reverse';
            EXEC dbo.sp_ReverseCashAdvanceEntry @parmreferenceno = @caRef, @parmreason = 'TEST103 CA2 (rolled back)', @parmuser = @user;
            SET @stage = 'not refused';
        END TRY
        BEGIN CATCH
            SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
        END CATCH
        SELECT @tc = @@TRANCOUNT;
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @fp EXEC sp_executesql @qCA, @pCA, @cs = 'CA2', @run = 'post', @ref = @caRef, @user = @user;
        SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE Cs = 'CA' AND Run = 'pre' EXCEPT SELECT Item, Val FROM @fp WHERE Cs = 'CA2' AND Run = 'post') AS a;
        INSERT @r VALUES (CASE @k WHEN 1 THEN 'CA2 cash advance, OC ticked cleared: refused 93031, nothing changed' ELSE 'CA2b cash advance, DIT ticked cleared: refused 93031, nothing changed' END,
                          CASE WHEN @stage = 'reverse' AND @e = 93031 AND @tc = 0 AND @n = 0 AND @em LIKE '%' + @caRef + '%' THEN 'PASS' ELSE 'FAIL' END,
                          CONCAT('at ', @stage, ': error ', ISNULL(CAST(@e AS VARCHAR(10)), 'none'), ' ', ISNULL(@em, '(not refused)'), ' | @@TRANCOUNT after the CATCH ', @tc,
                                 ', footprint rows changed vs before ', @n, ' of 7; CashAdvance ', (SELECT Val FROM @fp WHERE Cs = 'CA2' AND Item = 'CA')));
    END
    SET @k += 1;
END

------------------------------------------------------------------
-- CA3 BUG SHOWN: the old proc reverses and leaves the ticked OC CLEARED
------------------------------------------------------------------
IF @caRef IS NULL
    INSERT @r VALUES ('CA3 old proc: ticked OC left CLEARED after the reversal', 'SKIP', 'no CA fixture');
ELSE
BEGIN
    SELECT @st = NULL, @isRes = NULL, @why = NULL, @n = NULL;
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @caOC, @IsResolved = 1, @ResolvedBy = @user, @PeriodEnd = @caOCPer;
        EXEC dbo.sp_ReverseCashAdvanceEntry_OLD_10172026180000 @parmreferenceno = @caRef, @parmreason = 'TEST103 CA3 (rolled back)', @parmuser = @user;
        SELECT @st = Status FROM dbo.CashAdvance WHERE ReferenceNo = @caRef;
        SELECT @isRes = IsResolved, @why = ResolvedReason FROM dbo.BankStatementRecon WHERE ReconID = @caOC;
        SELECT @s = ResolvedReason FROM dbo.BankStatementRecon WHERE ReconID = @caDIT;
        -- the Exception Center rule (BankRecon_GLvsRecon_Check.sql section 7, cash-advance part)
        SELECT @n = COUNT(*) FROM dbo.BankStatementRecon AS b
        WHERE b.ReconID = @caOC AND b.SourceModule = 'CASH-ADVANCE' AND b.IsResolved = 1
          AND ISNULL(b.ResolvedReason, '') <> 'REVERSED' AND ISNULL(b.ResolvedReason, '') NOT LIKE 'VOIDED%'
          AND EXISTS (SELECT 1 FROM dbo.CashAdvance AS ca WHERE ca.ReferenceNo = b.SourceRef AND ca.Status = 'REVERSED');
        INSERT @r VALUES ('CA3 old proc: ticked OC left CLEARED after the cash advance is reversed',
                          CASE WHEN @st = 'REVERSED' AND @isRes = 1 AND @why = 'CLEARED' AND @n = 1 THEN 'BUG SHOWN' ELSE 'FAIL' END,
                          CONCAT('old proc: cash advance ', @st, ', OC ', @caOC, ' (', FORMAT(@caOCAmt, 'N2'), ') IsResolved ', CAST(@isRes AS INT), ' / ', ISNULL(@why, '(null)'),
                                 ' (the open DIT became ', ISNULL(@s, '(null)'), '); Exception Center section 7 finds it: ', @n));
    END TRY
    BEGIN CATCH
        INSERT @r VALUES ('CA3 old proc: ticked OC left CLEARED after the cash advance is reversed', 'FAIL', CONCAT('error ', ERROR_NUMBER(), ': ', ERROR_MESSAGE()));
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
END

------------------------------------------------------------------
-- CA4a-d: what does NOT block (an extra item row of the cash advance, added in the transaction):
--   a) cleared with Amount 0, b) IsResolved 1 with ResolvedReason VOIDED - ..., c) ResolvedReason REVERSED -> reversed;
--   d) control: the same extra row cleared with an amount -> 93031 (the extra row is in the check's scope)
------------------------------------------------------------------
SET @k = 1;
WHILE @k <= 4
BEGIN
    SET @s2 = CASE @k WHEN 1 THEN 'CA4a extra cleared item with Amount 0: does not block, reversed'
                      WHEN 2 THEN 'CA4b extra item VOIDED - ...: does not block, reversed'
                      WHEN 3 THEN 'CA4c extra item REVERSED: does not block, reversed'
                      ELSE        'CA4d control: the same extra item cleared with its amount: refused 93031' END;
    IF @caRef IS NULL
        INSERT @r VALUES (@s2, 'SKIP', 'no CA fixture');
    ELSE
    BEGIN
        SELECT @e = NULL, @em = NULL, @st = NULL, @s = NULL, @stage = 'insert';
        BEGIN TRAN;
        BEGIN TRY
            INSERT INTO dbo.BankStatementRecon
                (BranchCode, AccountCode, PeriodEnd, ItemType, ReferenceNo, ItemDate, Payee, Amount, Remarks, IsResolved, ResolvedDate, ResolvedBy,
                 AddedBy, DateTimeAdded, UpdatedBy, DateTimeUpdated, SourceModule, SourceRef, HeaderID, ResolvedReason, CreatedBy, CreatedDate,
                 PostedPaymentRef, MatchedSupplierID, MatchedBatchReferenceID, MatchedInvoiceNo, PostedReferenceNo, PostedVoucherID, ControlNo, ClearedPeriodEnd)
            SELECT BranchCode, AccountCode, PeriodEnd, ItemType, ReferenceNo, ItemDate, Payee,
                   CASE WHEN @k = 1 THEN 0 ELSE Amount END, 'TEST103 extra row (rolled back)', 1, GETDATE(), @user,
                   @user, GETDATE(), @user, GETDATE(), SourceModule, SourceRef, HeaderID,
                   CASE @k WHEN 2 THEN 'VOIDED - TEST103' WHEN 3 THEN 'REVERSED' ELSE 'CLEARED' END, @user, GETDATE(),
                   PostedPaymentRef, MatchedSupplierID, MatchedBatchReferenceID, MatchedInvoiceNo, PostedReferenceNo, PostedVoucherID, ControlNo, PeriodEnd
            FROM dbo.BankStatementRecon WHERE ReconID = @caOC;
            SET @stage = 'reverse';
            EXEC dbo.sp_ReverseCashAdvanceEntry @parmreferenceno = @caRef, @parmreason = 'TEST103 CA4 (rolled back)', @parmuser = @user;
            SET @stage = 'reversed';
            SELECT @st = Status FROM dbo.CashAdvance WHERE ReferenceNo = @caRef;
            SELECT @s = STRING_AGG(CONCAT(ReconID, ':', CAST(IsResolved AS INT), ':', ISNULL(ResolvedReason, '-')), ',') WITHIN GROUP (ORDER BY ReconID)
            FROM dbo.BankStatementRecon WHERE ReconID IN (@caOC, @caDIT);
        END TRY
        BEGIN CATCH
            SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
        END CATCH
        SELECT @tc = @@TRANCOUNT;
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF @k <= 3
            INSERT @r VALUES (@s2, CASE WHEN @stage = 'reversed' AND @e IS NULL AND @st = 'REVERSED' AND @s LIKE '%:1:VOIDED - CASH ADVANCE REVERSED,%:1:VOIDED - CASH ADVANCE REVERSED' THEN 'PASS' ELSE 'FAIL' END,
                              CONCAT('at ', @stage, ': ', CASE WHEN @e IS NULL THEN 'no error' ELSE CONCAT('error ', @e, ' ', @em) END, '; cash advance ', ISNULL(@st, '-'), ', its own items ', ISNULL(@s, '-')));
        ELSE
            INSERT @r VALUES (@s2, CASE WHEN @stage = 'reverse' AND @e = 93031 AND @tc = 0 THEN 'PASS' ELSE 'FAIL' END,
                              CONCAT('at ', @stage, ': error ', ISNULL(CAST(@e AS VARCHAR(10)), 'none'), ' ', ISNULL(@em, '(not refused)'), ' | @@TRANCOUNT ', @tc));
    END
    SET @k += 1;
END

------------------------------------------------------------------
-- CA5 a cash advance whose item is REALLY ticked cleared in the database -> 93031, item still cleared
------------------------------------------------------------------
IF @ca5Ref IS NULL
    INSERT @r VALUES ('CA5 live cash advance with a really cleared item: refused 93031', 'SKIP', 'no live cash advance with a cleared item here');
ELSE
BEGIN
    SELECT @e = NULL, @em = NULL;
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_ReverseCashAdvanceEntry @parmreferenceno = @ca5Ref, @parmreason = 'TEST103 CA5 (rolled back)', @parmuser = @user;
    END TRY
    BEGIN CATCH
        SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
    END CATCH
    SELECT @tc = @@TRANCOUNT;
    IF @@TRANCOUNT > 0 ROLLBACK;
    INSERT @fp EXEC sp_executesql @qCA, @pCA, @cs = 'CA5', @run = 'post', @ref = @ca5Ref, @user = @user;
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE Cs = 'CA5' AND Run = 'pre' EXCEPT SELECT Item, Val FROM @fp WHERE Cs = 'CA5' AND Run = 'post') AS a;
    SELECT @isRes = IsResolved, @why = ResolvedReason FROM dbo.BankStatementRecon WHERE ReconID = @ca5Recon;
    SELECT @st = Status FROM dbo.CashAdvance WHERE ReferenceNo = @ca5Ref;
    INSERT @r VALUES ('CA5 live cash advance with a really cleared item: refused 93031, item still cleared, nothing changed',
                      CASE WHEN @e = 93031 AND @tc = 0 AND @n = 0 AND @isRes = 1 AND @st = 'OUTSTANDING' THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('ref ', @ca5Ref, ' / voucher ', @ca5Vid, ', item ', @ca5Recon, ' ', FORMAT(@ca5Amt, 'N2'), ': error ', ISNULL(CAST(@e AS VARCHAR(10)), 'none'), ' ', ISNULL(@em, '(not refused)'),
                             ' | after: cash advance ', @st, ', item IsResolved ', CAST(@isRes AS INT), ' / ', ISNULL(@why, '-'), ', footprint rows changed ', @n, ' of 7, @@TRANCOUNT ', @tc));
END

------------------------------------------------------------------
-- CA6 order: DIT ticked cleared AND the OC's month LOCKED -> new 93031 (the cleared message), control old proc -> 93027
------------------------------------------------------------------
IF @caRef IS NULL
    INSERT @r VALUES ('CA6 cleared item + locked month: 93031 before 93027', 'SKIP', 'no CA fixture');
ELSE
BEGIN
    DECLARE @eNew INT, @eOld INT, @emNew NVARCHAR(2048), @emOld NVARCHAR(2048), @tcNew INT, @tcOld INT;
    SET @run = 'new';
    WHILE @run IS NOT NULL
    BEGIN
        SELECT @e = NULL, @em = NULL, @stage = 'tick';
        BEGIN TRAN;
        BEGIN TRY
            EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @caDIT, @IsResolved = 1, @ResolvedBy = @user, @PeriodEnd = @caDITPer;
            SET @stage = 'lock';
            UPDATE dbo.BankReconHeader SET Status = 'LOCKED' WHERE HeaderID = @caOCHdr;
            SET @stage = 'reverse';
            IF @run = 'new'
                EXEC dbo.sp_ReverseCashAdvanceEntry @parmreferenceno = @caRef, @parmreason = 'TEST103 CA6 (rolled back)', @parmuser = @user;
            ELSE
                EXEC dbo.sp_ReverseCashAdvanceEntry_OLD_10172026180000 @parmreferenceno = @caRef, @parmreason = 'TEST103 CA6 (rolled back)', @parmuser = @user;
            SET @stage = 'not refused';
        END TRY
        BEGIN CATCH
            SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
        END CATCH
        SELECT @tc = @@TRANCOUNT;
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF @run = 'new' SELECT @eNew = @e, @emNew = CONCAT(@stage, ': ', @em), @tcNew = @tc;
        ELSE SELECT @eOld = @e, @emOld = CONCAT(@stage, ': ', @em), @tcOld = @tc;
        SET @run = CASE WHEN @run = 'new' THEN 'old' ELSE NULL END;
    END
    INSERT @r VALUES ('CA6 DIT ticked cleared + the OC''s month locked: new 93031 (not 93027); old proc 93027',
                      CASE WHEN @eNew = 93031 AND @eOld = 93027 AND @tcNew = 0 AND @tcOld = 0 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('new: ', ISNULL(CAST(@eNew AS VARCHAR(10)), 'none'), ' at ', @emNew, ' || old: ', ISNULL(CAST(@eOld AS VARCHAR(10)), 'none'), ' at ', @emOld));
END

------------------------------------------------------------------
-- CC1 old = new = wrapper: a live cheque voucher with its open OC, reversed by sp_CancelledChequesCS old / new and by
--     sp_ReverseCombinedSupplierVoucher (SupplierVoucherReversalFrm's entry point)
------------------------------------------------------------------
IF @cvRef IS NULL
    INSERT @r VALUES ('CC1 cheque voucher with an open OC: old = new = wrapper footprint', 'SKIP', 'no live one-kind cheque voucher with an open OC');
ELSE
BEGIN
    SET @run = 'old';
    WHILE @run IS NOT NULL
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            IF @run = 'old'
                EXEC dbo.sp_CancelledChequesCS_OLD_10172026180000 @parmsupplierid = @cvSup, @parmreferenceno = @cvRef, @parmvoucherid = @cvVid, @parmvouchertype = @cvType,
                     @parmreason = 'TEST103 CC1 (rolled back)', @parmuser = @user;
            ELSE IF @run = 'new'
                EXEC dbo.sp_CancelledChequesCS @parmsupplierid = @cvSup, @parmreferenceno = @cvRef, @parmvoucherid = @cvVid, @parmvouchertype = @cvType,
                     @parmreason = 'TEST103 CC1 (rolled back)', @parmuser = @user;
            ELSE
                EXEC dbo.sp_ReverseCombinedSupplierVoucher @parmsupplierid = @cvSup, @parmreferenceno = @cvRef, @parmvoucherid = @cvVid, @parmvouchertype = @cvType,
                     @parmreason = 'TEST103 CC1 (rolled back)', @parmuser = @user;
            INSERT @fp EXEC sp_executesql @qCV, @pCV, @cs = 'CC1', @run = @run, @ref = @cvRef, @vid = @cvVid, @sup = @cvSup, @user = @user;
        END TRY
        BEGIN CATCH
            INSERT @r VALUES (CONCAT('CC1 ', @run, ' proc'), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE()));
        END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @run = CASE @run WHEN 'old' THEN 'new' WHEN 'new' THEN 'wrap' ELSE NULL END;
    END
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE Cs = 'CC1' AND Run = 'old' EXCEPT SELECT Item, Val FROM @fp WHERE Cs = 'CC1' AND Run = 'new') AS a;
    SELECT @n2 = COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE Cs = 'CC1' AND Run = 'new' EXCEPT SELECT Item, Val FROM @fp WHERE Cs = 'CC1' AND Run = 'old') AS a;
    SELECT @x = COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE Cs = 'CC1' AND Run = 'wrap' EXCEPT SELECT Item, Val FROM @fp WHERE Cs = 'CC1' AND Run = 'new') AS a;
    SELECT @x = @x + COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE Cs = 'CC1' AND Run = 'new' EXCEPT SELECT Item, Val FROM @fp WHERE Cs = 'CC1' AND Run = 'wrap') AS a;
    SELECT @n3 = COUNT(*) FROM @fp WHERE Cs = 'CC1' AND Run = 'new';
    SELECT @s = (SELECT Val FROM @fp WHERE Cs = 'CC1' AND Run = 'new' AND Item = 'BSR');
    INSERT @r VALUES ('CC1 cheque voucher with an open OC: old = new = wrapper footprint (voucher, invoices, ledger, tickets, recon)',
                      CASE WHEN @n = 0 AND @n2 = 0 AND @x = 0 AND @n3 = 12 AND (SELECT COUNT(*) FROM @fp WHERE Cs = 'CC1' AND Run = 'old') = 12 AND (SELECT COUNT(*) FROM @fp WHERE Cs = 'CC1' AND Run = 'wrap') = 12
                                AND (SELECT Val FROM @fp WHERE Cs = 'CC1' AND Run = 'new' AND Item = 'CV') LIKE '1|%' AND @s LIKE '%:1:VOIDED'
                                AND (SELECT Val FROM @fp WHERE Cs = 'CC1' AND Run = 'new' AND Item = 'NET') = '0' THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('voucher ', @cvVid, ' / ref ', @cvRef, ' ', @cvType, ' ', FORMAT(@cvAmt, 'N2'), ': old vs new ', @n, ' + ', @n2, ', wrapper vs new ', @x, ' of ', @n3,
                             ' footprint rows differ; OC ', @s, '; invoices ', ISNULL((SELECT Val FROM @fp WHERE Cs = 'CC1' AND Run = 'new' AND Item = 'ES'), '-'), ' ', ISNULL((SELECT Val FROM @fp WHERE Cs = 'CC1' AND Run = 'new' AND Item = 'AP'), ''),
                             '; reversal tickets ', (SELECT Val FROM @fp WHERE Cs = 'CC1' AND Run = 'new' AND Item = 'TKREV'), '; accounts not netting to 0: ', (SELECT Val FROM @fp WHERE Cs = 'CC1' AND Run = 'new' AND Item = 'NET')));
END

------------------------------------------------------------------
-- CC2 new proc: its OC ticked cleared in the transaction -> 93032, nothing changed
------------------------------------------------------------------
IF @cvRef IS NULL
    INSERT @r VALUES ('CC2 cheque voucher, OC ticked cleared: refused 93032', 'SKIP', 'no CV fixture');
ELSE
BEGIN
    SELECT @e = NULL, @em = NULL, @stage = 'tick';
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @cvOC, @IsResolved = 1, @ResolvedBy = @user, @PeriodEnd = @cvPer;
        SET @stage = 'reverse';
        EXEC dbo.sp_CancelledChequesCS @parmsupplierid = @cvSup, @parmreferenceno = @cvRef, @parmvoucherid = @cvVid, @parmvouchertype = @cvType,
             @parmreason = 'TEST103 CC2 (rolled back)', @parmuser = @user;
        SET @stage = 'not refused';
    END TRY
    BEGIN CATCH
        SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
    END CATCH
    SELECT @tc = @@TRANCOUNT;
    IF @@TRANCOUNT > 0 ROLLBACK;
    INSERT @fp EXEC sp_executesql @qCV, @pCV, @cs = 'CC2', @run = 'post', @ref = @cvRef, @vid = @cvVid, @sup = @cvSup, @user = @user;
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE Cs = 'CV' AND Run = 'pre' EXCEPT SELECT Item, Val FROM @fp WHERE Cs = 'CC2' AND Run = 'post') AS a;
    INSERT @r VALUES ('CC2 cheque voucher, OC ticked cleared: refused 93032, nothing changed',
                      CASE WHEN @stage = 'reverse' AND @e = 93032 AND @tc = 0 AND @n = 0 AND @em LIKE '%' + @cvRef + '%' THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('at ', @stage, ': error ', ISNULL(CAST(@e AS VARCHAR(10)), 'none'), ' ', ISNULL(@em, '(not refused)'), ' | @@TRANCOUNT ', @tc,
                             ', footprint rows changed vs before ', @n, ' of 12; voucher ', (SELECT Val FROM @fp WHERE Cs = 'CC2' AND Item = 'CV')));
END

------------------------------------------------------------------
-- CC3 BUG SHOWN: the old proc cancels the cheque and leaves its ticked OC CLEARED
------------------------------------------------------------------
IF @cvRef IS NULL
    INSERT @r VALUES ('CC3 old proc: ticked OC left CLEARED after the cheque cancel', 'SKIP', 'no CV fixture');
ELSE
BEGIN
    SELECT @st = NULL, @isRes = NULL, @why = NULL, @n = NULL;
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @cvOC, @IsResolved = 1, @ResolvedBy = @user, @PeriodEnd = @cvPer;
        EXEC dbo.sp_CancelledChequesCS_OLD_10172026180000 @parmsupplierid = @cvSup, @parmreferenceno = @cvRef, @parmvoucherid = @cvVid, @parmvouchertype = @cvType,
             @parmreason = 'TEST103 CC3 (rolled back)', @parmuser = @user;
        SELECT @st = CAST(ISNULL(CAST(isErrorCorrect AS INT), 0) AS VARCHAR(5)) FROM dbo.CheckVoucher WHERE ReferenceNumber = @cvRef AND CAST(VoucherID AS VARCHAR(10)) = @cvVid;
        SELECT @isRes = IsResolved, @why = ResolvedReason FROM dbo.BankStatementRecon WHERE ReconID = @cvOC;
        -- the Exception Center rule (section 7, supplier-voucher part)
        SELECT @n = COUNT(*) FROM dbo.BankStatementRecon AS b
        WHERE b.ReconID = @cvOC AND b.ItemType = 'OC' AND ISNULL(b.SourceModule, '') <> 'CASH-ADVANCE' AND b.IsResolved = 1
          AND ISNULL(b.ResolvedReason, '') <> 'REVERSED' AND ISNULL(b.ResolvedReason, '') NOT LIKE 'VOIDED%'
          AND EXISTS (SELECT 1 FROM dbo.PaymentReversalAudit AS a WHERE a.ReferenceNumber = b.SourceRef);
        SELECT @s = STRING_AGG(CONCAT(Balance, '|', Status), ',') FROM dbo.ExpenseSummary AS es
        WHERE es.SupplierID = @cvSup AND EXISTS (SELECT 1 FROM dbo.APPaymentDetails AS a WHERE a.ReferenceNumber = @cvRef AND a.VoucherID = @cvVid AND a.BatchReferenceID = es.BatchReferenceID AND a.InvoiceNo = es.InvoiceNo);
        INSERT @r VALUES ('CC3 old proc: ticked OC left CLEARED after the cheque is cancelled',
                          CASE WHEN @st = '1' AND @isRes = 1 AND @why = 'CLEARED' AND @n = 1 THEN 'BUG SHOWN' ELSE 'FAIL' END,
                          CONCAT('old proc: voucher ', @cvVid, ' isErrorCorrect ', @st, ', invoice back to ', ISNULL(@s, '-'), ', OC ', @cvOC, ' (', FORMAT(@cvAmt, 'N2'), ') IsResolved ', CAST(@isRes AS INT), ' / ', ISNULL(@why, '(null)'),
                                 '; Exception Center section 7 finds it: ', @n));
    END TRY
    BEGIN CATCH
        INSERT @r VALUES ('CC3 old proc: ticked OC left CLEARED after the cheque is cancelled', 'FAIL', CONCAT('error ', ERROR_NUMBER(), ': ', ERROR_MESSAGE()));
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
END

------------------------------------------------------------------
-- CC4 a live voucher whose OC is REALLY ticked cleared in the database -> 93032, item still cleared
------------------------------------------------------------------
IF @cv4Ref IS NULL
    INSERT @r VALUES ('CC4 live voucher with a really cleared OC: refused 93032', 'SKIP', 'no live cheque voucher with a cleared OC here');
ELSE
BEGIN
    SELECT @e = NULL, @em = NULL;
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_CancelledChequesCS @parmsupplierid = @cv4Sup, @parmreferenceno = @cv4Ref, @parmvoucherid = @cv4Vid, @parmvouchertype = @cv4Type,
             @parmreason = 'TEST103 CC4 (rolled back)', @parmuser = @user;
    END TRY
    BEGIN CATCH
        SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
    END CATCH
    SELECT @tc = @@TRANCOUNT;
    IF @@TRANCOUNT > 0 ROLLBACK;
    INSERT @fp EXEC sp_executesql @qCV, @pCV, @cs = 'CV4', @run = 'post', @ref = @cv4Ref, @vid = @cv4Vid, @sup = @cv4Sup, @user = @user;
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE Cs = 'CV4' AND Run = 'pre' EXCEPT SELECT Item, Val FROM @fp WHERE Cs = 'CV4' AND Run = 'post') AS a;
    SELECT @isRes = IsResolved, @why = ResolvedReason FROM dbo.BankStatementRecon WHERE ReconID = @cv4Recon;
    INSERT @r VALUES ('CC4 live voucher with a really cleared OC: refused 93032, OC still cleared, nothing changed',
                      CASE WHEN @e = 93032 AND @tc = 0 AND @n = 0 AND @isRes = 1 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('voucher ', @cv4Vid, ' / ref ', @cv4Ref, ' ', @cv4Type, ', OC ', @cv4Recon, ' ', FORMAT(@cv4Amt, 'N2'), ': error ', ISNULL(CAST(@e AS VARCHAR(10)), 'none'), ' ', ISNULL(@em, '(not refused)'),
                             ' | after: OC IsResolved ', CAST(@isRes AS INT), ' / ', ISNULL(@why, '-'), ', footprint rows changed ', @n, ' of 12, @@TRANCOUNT ', @tc));
END

------------------------------------------------------------------
-- CC4b / CC4c: an extra cleared OC with Amount 0 (b) or IsResolved 1 'VOIDED - ...' (c) under the reference does not block
------------------------------------------------------------------
SET @k = 1;
WHILE @k <= 2
BEGIN
    SET @s2 = CASE @k WHEN 1 THEN 'CC4b extra cleared OC with Amount 0 under the reference: does not block, cancelled'
                      ELSE        'CC4c extra OC VOIDED - ... under the reference: does not block, cancelled' END;
    IF @cvRef IS NULL
        INSERT @r VALUES (@s2, 'SKIP', 'no CV fixture');
    ELSE
    BEGIN
        SELECT @e = NULL, @em = NULL, @st = NULL, @s = NULL, @stage = 'insert';
        BEGIN TRAN;
        BEGIN TRY
            INSERT INTO dbo.BankStatementRecon
                (BranchCode, AccountCode, PeriodEnd, ItemType, ReferenceNo, ItemDate, Payee, Amount, Remarks, IsResolved, ResolvedDate, ResolvedBy,
                 AddedBy, DateTimeAdded, UpdatedBy, DateTimeUpdated, SourceModule, SourceRef, HeaderID, ResolvedReason, CreatedBy, CreatedDate,
                 PostedPaymentRef, MatchedSupplierID, MatchedBatchReferenceID, MatchedInvoiceNo, PostedReferenceNo, PostedVoucherID, ControlNo, ClearedPeriodEnd)
            SELECT BranchCode, AccountCode, PeriodEnd, ItemType, ReferenceNo, ItemDate, Payee,
                   CASE WHEN @k = 1 THEN 0 ELSE Amount END, 'TEST103 extra row (rolled back)', 1, GETDATE(), @user,
                   @user, GETDATE(), @user, GETDATE(), SourceModule, SourceRef, HeaderID,
                   CASE @k WHEN 2 THEN 'VOIDED - TEST103' ELSE 'CLEARED' END, @user, GETDATE(),
                   PostedPaymentRef, MatchedSupplierID, MatchedBatchReferenceID, MatchedInvoiceNo, PostedReferenceNo, PostedVoucherID, ControlNo, PeriodEnd
            FROM dbo.BankStatementRecon WHERE ReconID = @cvOC;
            SET @stage = 'reverse';
            EXEC dbo.sp_CancelledChequesCS @parmsupplierid = @cvSup, @parmreferenceno = @cvRef, @parmvoucherid = @cvVid, @parmvouchertype = @cvType,
                 @parmreason = 'TEST103 CC4b (rolled back)', @parmuser = @user;
            SET @stage = 'cancelled';
            SELECT @st = CAST(ISNULL(CAST(isErrorCorrect AS INT), 0) AS VARCHAR(5)) FROM dbo.CheckVoucher WHERE ReferenceNumber = @cvRef AND CAST(VoucherID AS VARCHAR(10)) = @cvVid;
            SELECT @s = CONCAT(CAST(IsResolved AS INT), ':', ISNULL(ResolvedReason, '-')) FROM dbo.BankStatementRecon WHERE ReconID = @cvOC;
        END TRY
        BEGIN CATCH
            SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
        END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES (@s2, CASE WHEN @stage = 'cancelled' AND @e IS NULL AND @st = '1' AND @s = '1:VOIDED' THEN 'PASS' ELSE 'FAIL' END,
                          CONCAT('at ', @stage, ': ', CASE WHEN @e IS NULL THEN 'no error' ELSE CONCAT('error ', @e, ' ', @em) END, '; voucher isErrorCorrect ', ISNULL(@st, '-'), ', its own OC ', ISNULL(@s, '-')));
    END
    SET @k += 1;
END

------------------------------------------------------------------
-- CC5a the screen's entry point (sp_ReverseCombinedSupplierVoucher) on a live cash-advance voucher whose item is REALLY
--      cleared -> 93031, voucher untouched
------------------------------------------------------------------
IF @ca5Ref IS NULL
    INSERT @r VALUES ('CC5a wrapper, cash-advance voucher with a really cleared item: refused 93031', 'SKIP', 'no CA5 fixture');
ELSE
BEGIN
    SELECT @e = NULL, @em = NULL;
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_ReverseCombinedSupplierVoucher @parmsupplierid = @ca5Sup, @parmreferenceno = @ca5Ref, @parmvoucherid = @ca5Vid, @parmvouchertype = 'EXPENSE',
             @parmreason = 'TEST103 CC5a (rolled back)', @parmuser = @user;
    END TRY
    BEGIN CATCH
        SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
    END CATCH
    SELECT @tc = @@TRANCOUNT;
    IF @@TRANCOUNT > 0 ROLLBACK;
    DELETE @fp WHERE Cs = 'CA5' AND Run = 'post';
    INSERT @fp EXEC sp_executesql @qCA, @pCA, @cs = 'CA5', @run = 'post', @ref = @ca5Ref, @user = @user;
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE Cs = 'CA5' AND Run = 'pre' EXCEPT SELECT Item, Val FROM @fp WHERE Cs = 'CA5' AND Run = 'post') AS a;
    SELECT @n2 = COUNT(*) FROM dbo.PaymentReversalAudit WHERE ReferenceNumber = @ca5Ref;
    INSERT @r VALUES ('CC5a wrapper, cash-advance voucher with a really cleared item: refused 93031, voucher untouched',
                      CASE WHEN @e = 93031 AND @tc = 0 AND @n = 0 AND @n2 = 0 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('ref ', @ca5Ref, ' / voucher ', @ca5Vid, ': error ', ISNULL(CAST(@e AS VARCHAR(10)), 'none'), ' ', ISNULL(@em, '(not refused)'),
                             ' | after: footprint rows changed ', @n, ' of 7 (cheque voucher ', (SELECT Val FROM @fp WHERE Cs = 'CA5' AND Run = 'post' AND Item = 'CV'),
                             ', cash advance ', (SELECT Val FROM @fp WHERE Cs = 'CA5' AND Run = 'post' AND Item = 'CA'), '), reversal audit rows ', @n2, ', @@TRANCOUNT ', @tc));
END

------------------------------------------------------------------
-- CC5b-d a combined voucher posted in the transaction (cheque: expense 500.00 + manual line 200.00 to a second bank, which
--   is a cash advance with its own DIT), reversed through the screen's entry point:
--   b) the cash advance's DIT ticked cleared -> the invoice leg passes 93032 and writes, then 93031 rolls the whole voucher back
--   c) control, nothing ticked -> reversed whole (cash advance, cheque, both items, expense balance)
--   d) the cheque's OC ticked cleared -> 93032
------------------------------------------------------------------
DECLARE @ILn dbo.AP_PaymentLineTVP, @IXn dbo.AP_PaymentLineExtraTVP, @MLn dbo.ManualVoucherDebitLineTVP, @tick INT, @tickPer DATE;
IF @xRef IS NOT NULL AND @caBank IS NOT NULL
BEGIN
    INSERT INTO @ILn (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
    VALUES (@xBranch, @xInv, @xDate, @xRef, @xBatch, @xAmt, 500.00, 0, 0, 0, 'TEST103', 0, NULL);
    INSERT INTO @MLn (BranchCode, AccountCode, Amount, Particulars) VALUES (@branch, @caBank, 200.00, 'TEST103 manual line (rolled back)');
END
SET @k = 1;
WHILE @k <= 3
BEGIN
    SET @s2 = CASE @k WHEN 1 THEN 'CC5b combined voucher, its cash advance''s DIT ticked: wrapper refused 93031, whole voucher rolled back'
                      WHEN 2 THEN 'CC5c control, combined voucher nothing ticked: wrapper reverses it whole'
                      ELSE        'CC5d combined voucher, its cheque OC ticked: wrapper refused 93032' END;
    IF @xRef IS NULL OR @caBank IS NULL
        INSERT @r VALUES (@s2, 'SKIP', 'no open SINGLE expense / second bank account on the cash-advance list');
    ELSE
    BEGIN
        SELECT @e = NULL, @em = NULL, @stage = 'post', @s = NULL, @tick = NULL, @tickPer = NULL;
        BEGIN TRAN;
        BEGIN TRY
            EXEC dbo.sp_PostSupplierPaymentWithManualLines @parmrefno = @ref5, @parmvoucherid = @vid5, @parmsupplierid = @xSup, @parmsuppliername = @xSupName,
                 @parmcheckcoding = 'T103CV', @parmcheckno = 'T103C', @parmcheckdate = @today, @parmcontrolno = NULL, @parmcheckremarks = 'TEST103 (rolled back)', @parmpreparedby = @user,
                 @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CHECK', @parmPayingBranch = @branch,
                 @InvoiceLegAmount = 500.00, @InvoiceLines = @ILn, @ManualLines = @MLn, @InvoiceLineExtras = @IXn;
            SELECT @s = STRING_AGG(CONCAT(ItemType, ':', SourceModule, ':', AccountCode, ':', Amount), ',') WITHIN GROUP (ORDER BY ItemType) FROM dbo.BankStatementRecon WHERE SourceRef = @ref5;
            IF @k = 1
                SELECT @tick = b.ReconID, @tickPer = h.PeriodEnd FROM dbo.BankStatementRecon AS b INNER JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
                WHERE b.SourceRef = @ref5 AND b.ReferenceNo = @vid5 AND b.SourceModule = 'CASH-ADVANCE' AND b.ItemType = 'DIT';
            ELSE IF @k = 3
                SELECT @tick = b.ReconID, @tickPer = h.PeriodEnd FROM dbo.BankStatementRecon AS b INNER JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
                WHERE b.SourceRef = @ref5 AND b.ReferenceNo = @vid5 AND b.SourceModule = 'AP-PAYMENT' AND b.ItemType = 'OC';
            IF @k <> 2
            BEGIN
                SET @stage = 'tick';
                IF @tick IS NULL THROW 59999, 'TEST103: the combined voucher has no item of the expected kind to tick', 1;
                EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @tick, @IsResolved = 1, @ResolvedBy = @user, @PeriodEnd = @tickPer;
            END
            SET @stage = 'reverse';
            EXEC dbo.sp_ReverseCombinedSupplierVoucher @parmsupplierid = @xSup, @parmreferenceno = @ref5, @parmvoucherid = @vid5, @parmvouchertype = 'EXPENSE',
                 @parmcheckno = 'T103C', @parmglcode = @bank, @parmbranch = @branch, @parmreason = 'TEST103 CC5 (rolled back)', @parmuser = @user;
            SET @stage = 'reversed';
            IF @k = 2
            BEGIN
                SELECT @st = Status FROM dbo.CashAdvance WHERE ReferenceNo = @ref5;
                SELECT @n = ISNULL(CAST(isErrorCorrect AS INT), 0) FROM dbo.CheckVoucher WHERE ReferenceNumber = @ref5 AND VoucherID = CAST(@vid5 AS DECIMAL(7,0));
                SELECT @n2 = COUNT(*) FROM dbo.BankStatementRecon WHERE SourceRef = @ref5 AND (IsResolved = 0 OR ISNULL(ResolvedReason, '') NOT LIKE 'VOID%');
                SELECT @n3 = COUNT(*) FROM (SELECT d.AccountCode FROM dbo.TicketDetails AS d
                                            WHERE EXISTS (SELECT 1 FROM dbo.TicketMaster AS m WHERE m.TicketNumber = d.TicketNumber AND m.BranchCode = d.BranchCode AND m.ReferenceNumber = @ref5)
                                            GROUP BY d.AccountCode HAVING ABS(SUM(ISNULL(d.Debit, 0)) - SUM(ISNULL(d.Credit, 0))) > 0.004) AS a;
                SELECT @s2 = CONCAT(Balance, '|', ISNULL(AmountPaid, 0), '|', Status) FROM dbo.ExpenseSummary WHERE SupplierID = @xSup AND BatchReferenceID = @xBatch AND InvoiceNo = @xInv;
                INSERT @r VALUES ('CC5c control, combined voucher nothing ticked: wrapper reverses it whole',
                                  CASE WHEN @st = 'REVERSED' AND @n = 1 AND @n2 = 0 AND @n3 = 0 AND @s2 = @xBefore THEN 'PASS' ELSE 'FAIL' END,
                                  CONCAT('posted items ', @s, '; after the reversal: cash advance ', @st, ', cheque isErrorCorrect ', @n, ', items not voided ', @n2,
                                         ', accounts not netting to 0 ', @n3, ', expense ', @s2, ' (before ', @xBefore, ')'));
            END
        END TRY
        BEGIN CATCH
            SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
        END CATCH
        SELECT @tc = @@TRANCOUNT;
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT @n = (SELECT COUNT(*) FROM dbo.BankStatementRecon WHERE SourceRef = @ref5 OR ReferenceNo IN (@ref5, @vid5))
                  + (SELECT COUNT(*) FROM dbo.CashAdvance WHERE ReferenceNo = @ref5)
                  + (SELECT COUNT(*) FROM dbo.CheckVoucher WHERE ReferenceNumber = @ref5)
                  + (SELECT COUNT(*) FROM dbo.APPaymentDetails WHERE ReferenceNumber = @ref5)
                  + (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber = @ref5)
                  + (SELECT COUNT(*) FROM dbo.SupplierLedger WHERE ReferenceNumber = @ref5)
                  + (SELECT COUNT(*) FROM dbo.PaymentReversalAudit WHERE ReferenceNumber = @ref5);
        SELECT @s2 = CONCAT(Balance, '|', ISNULL(AmountPaid, 0), '|', Status) FROM dbo.ExpenseSummary WHERE SupplierID = @xSup AND BatchReferenceID = @xBatch AND InvoiceNo = @xInv;
        IF @k = 2 AND @e IS NOT NULL
            INSERT @r VALUES ('CC5c control, combined voucher nothing ticked: wrapper reverses it whole', 'ERROR', CONCAT('at ', @stage, ': ', @e, ' ', @em));
        ELSE IF @k <> 2
            INSERT @r VALUES (CASE @k WHEN 1 THEN 'CC5b combined voucher, its cash advance''s DIT ticked: wrapper refused 93031, whole voucher rolled back'
                                      ELSE        'CC5d combined voucher, its cheque OC ticked: wrapper refused 93032, whole voucher rolled back' END,
                              CASE WHEN @stage = 'reverse' AND @e = CASE @k WHEN 1 THEN 93031 ELSE 93032 END AND @tc = 0 AND @n = 0 AND @s2 = @xBefore THEN 'PASS' ELSE 'FAIL' END,
                              CONCAT('posted ', ISNULL(@s, '-'), ', ticked ', ISNULL(CAST(@tick AS VARCHAR(10)), '-'), '; at ', @stage, ': error ', ISNULL(CAST(@e AS VARCHAR(10)), 'none'), ' ', ISNULL(@em, '(not refused)'),
                                     ' | @@TRANCOUNT ', @tc, ', rows under ', @ref5, ' left ', @n, ', expense ', @s2, ' (before ', @xBefore, ')'));
    END
    SET @k += 1;
END

------------------------------------------------------------------
-- CC6 cheque OC ticked cleared AND its month LOCKED -> 93032 (the cleared message, not a lock message)
------------------------------------------------------------------
IF @cvRef IS NULL
    INSERT @r VALUES ('CC6 cleared OC + locked month: 93032', 'SKIP', 'no CV fixture');
ELSE
BEGIN
    SELECT @e = NULL, @em = NULL, @stage = 'tick';
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @cvOC, @IsResolved = 1, @ResolvedBy = @user, @PeriodEnd = @cvPer;
        UPDATE dbo.BankReconHeader SET Status = 'LOCKED' WHERE HeaderID = @cvHdr;
        SET @stage = 'reverse';
        EXEC dbo.sp_CancelledChequesCS @parmsupplierid = @cvSup, @parmreferenceno = @cvRef, @parmvoucherid = @cvVid, @parmvouchertype = @cvType,
             @parmreason = 'TEST103 CC6 (rolled back)', @parmuser = @user;
        SET @stage = 'not refused';
    END TRY
    BEGIN CATCH
        SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
    END CATCH
    SELECT @tc = @@TRANCOUNT;
    IF @@TRANCOUNT > 0 ROLLBACK;
    INSERT @r VALUES ('CC6 cheque OC ticked cleared + its month locked: refused 93032',
                      CASE WHEN @stage = 'reverse' AND @e = 93032 AND @tc = 0 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('at ', @stage, ': error ', ISNULL(CAST(@e AS VARCHAR(10)), 'none'), ' ', ISNULL(@em, '(not refused)'), ' | @@TRANCOUNT ', @tc));
END

------------------------------------------------------------------
-- leftovers
------------------------------------------------------------------
Report:
SELECT @n = (SELECT COUNT(*) FROM dbo.BankStatementRecon WHERE ResolvedBy = 'TEST103' OR UpdatedBy = 'TEST103' OR AddedBy = 'TEST103' OR SourceRef = '99920' OR ReferenceNo IN ('99920', '99930'))
          + (SELECT COUNT(*) FROM dbo.CashAdvance WHERE ReferenceNo = '99920' OR VoucherID = '99930')
          + (SELECT COUNT(*) FROM dbo.CheckVoucher WHERE ReferenceNumber = '99920' OR CancelledBy = 'TEST103')
          + (SELECT COUNT(*) FROM dbo.APPaymentDetails WHERE ReferenceNumber = '99920')
          + (SELECT COUNT(*) FROM dbo.TransactionPaymentAP WHERE ReferenceNumber = 99920)
          + (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber = '99920' OR EnteredBy = 'TEST103')
          + (SELECT COUNT(*) FROM dbo.SupplierLedger WHERE ReferenceNumber = '99920' OR TransactedBy = 'TEST103')
          + (SELECT COUNT(*) FROM dbo.PaymentReversalAudit WHERE ReferenceNumber = '99920' OR CancelledBy = 'TEST103')
          + (SELECT COUNT(*) FROM dbo.CheckVoucherCancelled WHERE ExecuteBy = 'TEST103')
          + (SELECT COUNT(*) FROM dbo.ExpenseApprovalReversalAudit WHERE ReversedBy = 'TEST103');
SELECT @n2 = COUNT(*) FROM dbo.BankReconHeader WHERE Status = 'LOCKED';
SELECT @tc = @@TRANCOUNT;
INSERT @r VALUES ('leftovers', CASE WHEN @n = 0 AND @n2 = ISNULL(@lockedBefore, @n2) AND @tc = 0 THEN 'PASS' ELSE 'FAIL' END,
                  CONCAT(@n, ' test rows left behind (TEST103 / ref 99920 / voucher 99930); LOCKED recon headers ', @n2, ' (before ', ISNULL(CAST(@lockedBefore AS VARCHAR(10)), '-'), '); @@TRANCOUNT ', @tc));

SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
SELECT DB_NAME() AS DatabaseName, SUM(CASE WHEN Result = 'PASS' THEN 1 ELSE 0 END) AS Pass, SUM(CASE WHEN Result = 'BUG SHOWN' THEN 1 ELSE 0 END) AS BugShown,
       SUM(CASE WHEN Result = 'PRE-EXISTING' THEN 1 ELSE 0 END) AS PreExisting, SUM(CASE WHEN Result = 'SKIP' THEN 1 ELSE 0 END) AS Skip,
       SUM(CASE WHEN Result IN ('FAIL', 'ERROR', 'UNEXPECTED') THEN 1 ELSE 0 END) AS Fail
FROM @r;
