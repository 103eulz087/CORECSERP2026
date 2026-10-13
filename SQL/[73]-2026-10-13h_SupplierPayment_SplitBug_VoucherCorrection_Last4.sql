/* ================================================================
   [73] 2026-10-13 - Supplier payment: correct the last 4 vouchers the multi-branch split bug inflated (data only)
   ================================================================
   Follows [63] (688 / 913) and [66] (787 / 803 / 823 / 837 / 867). These 4 were keyed on PRODUCTION before [61] fixed
   sp_AddPaymentSupplierCompound_V2 and were found by the [70] AP checks (AP-VOUCHER-LEGS / AP-INVOICE-VS-LEDGER).
   User 2026-10-13: "the cheques were for the screen total, fix the 4 vouchers".

     ref 28473 / voucher 684  (BAC PCF, BAC-PCF-080626 branch 003)                      41,941.03  -> 41,941.02   (-0.01)
     ref 39390 / voucher 914  (BUT PCF, BUT-PCF-083126 branch 014)                      24,981.98  -> 24,981.96   (-0.02)
     ref 39611 / voucher 934  (CEB PCF, CEB-PCF-083126 888 -0.03 + CEB-PCF-090526 888 -0.46) 199,983.17 -> 199,982.68 (-0.49)
     ref 40881 / voucher 967  (ROBINSONS LAND, SOA-091426 888, PARTIAL payment)          131,250.71 -> 131,250.00  (-0.71)
   (PRODUCTION figures. On STAGING 684 was reversed and the other 3 don't exist; DEV has 684 only.)

   Differences from [66]:
     - a voucher may carry more than one multi-branch invoice (934): each one is checked and corrected on its own;
     - a partial payment is allowed (967): the invoice must be FULLYPAID with balance 0, or PARTIAL with a balance > 0;
     - the amount the voucher settled on an invoice is taken from the invoice itself
       (its payable credit in the supplier ledger - its balance now), not from the screen total, and the settled
       amounts of all invoices must add up to the screen total;
     - a reversed voucher is skipped (listed as SKIPPED), not an error.

   Per multi-branch invoice the extra is recomputed independently, the way the old proc computed it: last branch =
   settled - SUM(BranchNetLiability / eNetLiability * settled) over a DECIMAL(38,2) column (ratio cut to 6 decimals),
   vs. the correct settled - SUM(ROUND(share, 2)) of the other branches. It is corrected only when
   the last leg = the old formula's value AND (old - correct) = the invoice's legs - settled. The voucher's extra
   (sum over its invoices) must equal legs - screen total.

   Per corrected leg (the last branch of the invoice):
     1. APPaymentDetails   - the leg's Amount
     2. TicketDetails      - the leg's ticket: DR payable and CR bank (stays balanced)
     3. SupplierLedger     - the leg's payment row Debit (trg_SupplierLedger_Recalc re-chains the supplier)
   Per voucher:
     4. CheckVoucher       - the voucher amount (= the cheque)
     5. BankStatementRecon - the voucher's outstanding-cheque item (must be open, uncleared, period not locked)
   ExpenseSummary / ExpenseMaster are not touched (they already carry the screen's amount).
   If any check fails nothing is changed and the reason is shown. A GL month closed over the ticket date is refused
   by the lock trigger (59900). Backups: SplitFix_Backup_20261013b_* (the rows before).

   One transaction with a post-check. Run on DEV / STAGING / PRODUCTION; a reference not found there is skipped.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

IF OBJECT_ID('dbo.SplitFix_Backup_20261013b_APPaymentDetails', 'U') IS NOT NULL
    THROW 59976, 'This script has been run here before (SplitFix_Backup_20261013b_APPaymentDetails exists).', 1;

BEGIN TRANSACTION;

DECLARE @List TABLE (Ref VARCHAR(10) NOT NULL PRIMARY KEY);
INSERT INTO @List (Ref) VALUES ('28473'), ('39390'), ('39611'), ('40881');

-- one row per listed voucher found here
CREATE TABLE #V (
    Ref VARCHAR(10) NOT NULL PRIMARY KEY, VoucherID VARCHAR(20) NULL, SupplierID VARCHAR(50) NULL, BankAcct VARCHAR(30) NULL,
    Legs DECIMAL(18,2) NULL, Screen DECIMAL(18,2) NULL, Cheque DECIMAL(18,2) NULL, Extra DECIMAL(18,2) NULL,
    nMultiInv INT NULL, Skipped BIT NOT NULL DEFAULT 0, Problem VARCHAR(300) NULL);
INSERT INTO #V (Ref, VoucherID, SupplierID, BankAcct, Legs, Screen, Cheque)
SELECT l.Ref, MAX(p.VoucherID), MAX(p.SupplierID), MAX(p.CreditGLCode), SUM(p.Amount),
       (SELECT CAST(MAX(t.Amount) AS DECIMAL(18,2)) FROM dbo.TransactionPaymentAP AS t WHERE t.ReferenceNumber = TRY_CAST(l.Ref AS INT)),
       (SELECT CAST(MAX(c.Amount) AS DECIMAL(18,2)) FROM dbo.CheckVoucher AS c WHERE c.ReferenceNumber = l.Ref)
FROM @List AS l
INNER JOIN dbo.APPaymentDetails AS p ON p.ReferenceNumber = l.Ref AND p.PaymentType = 'EXPENSE PAYMENT'
GROUP BY l.Ref;
UPDATE #V SET Extra = Legs - Screen;
UPDATE v SET Skipped = 1
FROM #V AS v
WHERE EXISTS (SELECT 1 FROM dbo.PaymentReversalAudit AS r WHERE CAST(r.ReferenceNumber AS VARCHAR(10)) = v.Ref AND r.SupplierID = v.SupplierID)
   OR EXISTS (SELECT 1 FROM dbo.CheckVoucher AS c WHERE c.ReferenceNumber = v.Ref AND c.isErrorCorrect = 1);

-- invoices of each voucher, with the amount the voucher settled on each (payable credit - balance now)
CREATE TABLE #I (
    Ref VARCHAR(10) NOT NULL, InvoiceNo VARCHAR(150) NOT NULL, BatchRef BIGINT NULL, nBr INT NOT NULL, InvLegs DECIMAL(18,2) NOT NULL,
    nSummary INT NULL, Status VARCHAR(30) NULL, Balance DECIMAL(18,2) NULL, Payable DECIMAL(18,2) NULL, nCredit INT NULL,
    nOtherPay INT NULL, Settled DECIMAL(18,2) NULL);
INSERT INTO #I (Ref, InvoiceNo, BatchRef, nBr, InvLegs)
SELECT p.ReferenceNumber, p.InvoiceNo, p.BatchReferenceID, COUNT(DISTINCT p.BranchCode), SUM(p.Amount)
FROM #V AS v INNER JOIN dbo.APPaymentDetails AS p ON p.ReferenceNumber = v.Ref AND p.PaymentType = 'EXPENSE PAYMENT'
WHERE v.Skipped = 0
GROUP BY p.ReferenceNumber, p.InvoiceNo, p.BatchReferenceID;
UPDATE i SET
    nSummary = (SELECT COUNT(*) FROM dbo.ExpenseSummary AS e WHERE e.SupplierID = v.SupplierID AND e.InvoiceNo = i.InvoiceNo AND e.BatchReferenceID = i.BatchRef),
    Status = (SELECT MAX(e.Status) FROM dbo.ExpenseSummary AS e WHERE e.SupplierID = v.SupplierID AND e.InvoiceNo = i.InvoiceNo AND e.BatchReferenceID = i.BatchRef),
    Balance = (SELECT CAST(MAX(e.Balance) AS DECIMAL(18,2)) FROM dbo.ExpenseSummary AS e WHERE e.SupplierID = v.SupplierID AND e.InvoiceNo = i.InvoiceNo AND e.BatchReferenceID = i.BatchRef),
    Payable = (SELECT CAST(SUM(s.Credit) AS DECIMAL(18,2)) FROM dbo.SupplierLedger AS s WHERE s.SupplierKey = v.SupplierID AND s.InvoiceNo = i.InvoiceNo AND s.Credit > 0),
    nCredit = (SELECT COUNT(*) FROM dbo.SupplierLedger AS s WHERE s.SupplierKey = v.SupplierID AND s.InvoiceNo = i.InvoiceNo AND s.Credit > 0),
    nOtherPay = (SELECT COUNT(*) FROM dbo.APPaymentDetails AS o WHERE o.SupplierID = v.SupplierID AND o.InvoiceNo = i.InvoiceNo
                   AND o.BatchReferenceID = i.BatchRef AND o.PaymentType = 'EXPENSE PAYMENT' AND o.ReferenceNumber <> i.Ref)
FROM #I AS i INNER JOIN #V AS v ON v.Ref = i.Ref;
UPDATE #I SET Settled = Payable - Balance;
UPDATE v SET nMultiInv = (SELECT COUNT(*) FROM #I AS i WHERE i.Ref = v.Ref AND i.nBr > 1) FROM #V AS v WHERE v.Skipped = 0;

-- the old proc's split, recomputed per multi-branch invoice (eGross = the amount settled on it)
CREATE TABLE #R (
    Ref VARCHAR(10) NOT NULL, InvoiceNo VARCHAR(150) NOT NULL, BranchCode VARCHAR(10) NOT NULL, Net DECIMAL(38,2) NOT NULL,
    eNet DECIMAL(18,2) NOT NULL, eGross DECIMAL(18,2) NOT NULL, RowNum INT NOT NULL, nBr INT NOT NULL);
;WITH br AS (
    SELECT i.Ref, i.InvoiceNo, i.Settled AS eGross, m.BranchCode,
           SUM(m.Amount) - SUM(CASE WHEN m.IsEWTPostedAtAccrual = 1 THEN ISNULL(m.EWTAmount, 0) ELSE 0 END) AS Net
    FROM #I AS i
    INNER JOIN #V AS v ON v.Ref = i.Ref
    INNER JOIN dbo.ExpenseMaster AS m ON m.SupplierID = v.SupplierID AND m.InvoiceNo = i.InvoiceNo AND m.BatchReferenceID = i.BatchRef
    WHERE i.nBr > 1 AND i.Settled IS NOT NULL
    GROUP BY i.Ref, i.InvoiceNo, i.Settled, m.BranchCode)
INSERT INTO #R
SELECT br.Ref, br.InvoiceNo, br.BranchCode, br.Net, CAST(SUM(br.Net) OVER (PARTITION BY br.Ref, br.InvoiceNo) AS DECIMAL(18,2)), br.eGross,
       ROW_NUMBER() OVER (PARTITION BY br.Ref, br.InvoiceNo ORDER BY br.BranchCode), COUNT(*) OVER (PARTITION BY br.Ref, br.InvoiceNo)
FROM br;

-- the legs to correct: the last branch of each multi-branch invoice
CREATE TABLE #L (
    Ref VARCHAR(10) NOT NULL, InvoiceNo VARCHAR(150) NOT NULL, VoucherID VARCHAR(20) NOT NULL, SupplierID VARCHAR(50) NOT NULL,
    BatchRef BIGINT NULL, BranchCode VARCHAR(10) NOT NULL, TicketNumber VARCHAR(30) NOT NULL, PayableAcct VARCHAR(30) NOT NULL,
    BankAcct VARCHAR(30) NOT NULL, OldAmount DECIMAL(18,2) NOT NULL, BuggyLast DECIMAL(18,2) NOT NULL, CorrectLast DECIMAL(18,2) NOT NULL,
    Diff DECIMAL(18,2) NOT NULL, InvExtra DECIMAL(18,2) NOT NULL, nRows INT NOT NULL, PRIMARY KEY (Ref, InvoiceNo));
INSERT INTO #L
SELECT x.Ref, x.InvoiceNo, MAX(p.VoucherID), MAX(p.SupplierID), MAX(p.BatchReferenceID), x.BranchCode, MAX(p.TicketNumber),
       MAX(p.DebitGLCode), MAX(p.CreditGLCode), SUM(p.Amount),
       CAST(x.eGross - (SELECT SUM(r2.Net / r2.eNet * r2.eGross) FROM #R AS r2
                        WHERE r2.Ref = x.Ref AND r2.InvoiceNo = x.InvoiceNo AND r2.RowNum < r2.nBr) AS DECIMAL(18,2)),
       CAST(x.eGross - (SELECT SUM(ROUND(CAST(r2.Net AS DECIMAL(18,2)) / r2.eNet * r2.eGross, 2)) FROM #R AS r2
                        WHERE r2.Ref = x.Ref AND r2.InvoiceNo = x.InvoiceNo AND r2.RowNum < r2.nBr) AS DECIMAL(18,2)),
       0, MAX(i.InvLegs) - MAX(i.Settled), COUNT(*)
FROM #R AS x
INNER JOIN #I AS i ON i.Ref = x.Ref AND i.InvoiceNo = x.InvoiceNo
INNER JOIN dbo.APPaymentDetails AS p ON p.ReferenceNumber = x.Ref AND p.InvoiceNo = x.InvoiceNo AND p.BranchCode = x.BranchCode
                                    AND p.PaymentType = 'EXPENSE PAYMENT'
WHERE x.RowNum = x.nBr
GROUP BY x.Ref, x.InvoiceNo, x.BranchCode, x.eGross;
UPDATE #L SET Diff = BuggyLast - CorrectLast;

-- every expected value per invoice, or the reason it isn't safe
CREATE TABLE #P (Ref VARCHAR(10) NOT NULL, InvoiceNo VARCHAR(150) NOT NULL, Problem VARCHAR(300) NULL);
INSERT INTO #P
SELECT i.Ref, i.InvoiceNo,
    CASE WHEN i.nSummary <> 1 OR i.Balance IS NULL OR i.Status IS NULL THEN 'not exactly one ExpenseSummary row, or its balance / status is blank'
         WHEN i.nOtherPay > 0 THEN 'another voucher also paid the invoice'
         WHEN i.nCredit <> 1 THEN 'not exactly one payable credit in the supplier ledger'
         WHEN NOT ((i.Status = 'FULLYPAID' AND i.Balance = 0) OR (i.Status = 'PARTIAL' AND i.Balance > 0))
              THEN 'invoice status / balance not consistent (' + ISNULL(i.Status, '-') + ' / ' + ISNULL(CAST(i.Balance AS VARCHAR(30)), '-') + ')'
         WHEN i.Settled IS NULL OR i.Settled <= 0 THEN 'nothing settled on the invoice'
         WHEN i.nBr = 1 AND i.InvLegs <> i.Settled THEN 'single-branch invoice: legs <> settled'
         WHEN i.nBr > 1 AND NOT EXISTS (SELECT 1 FROM #L AS l WHERE l.Ref = i.Ref AND l.InvoiceNo = i.InvoiceNo) THEN 'last-branch leg not found'
         WHEN i.nBr > 1 AND (SELECT l.nRows FROM #L AS l WHERE l.Ref = i.Ref AND l.InvoiceNo = i.InvoiceNo) <> 1 THEN 'the last branch has more than one payment row'
         WHEN i.nBr > 1 AND (SELECT l.OldAmount - l.BuggyLast FROM #L AS l WHERE l.Ref = i.Ref AND l.InvoiceNo = i.InvoiceNo) <> 0
              THEN 'the last leg is not the old formula''s amount'
         WHEN i.nBr > 1 AND (SELECT l.Diff - l.InvExtra FROM #L AS l WHERE l.Ref = i.Ref AND l.InvoiceNo = i.InvoiceNo) <> 0
              THEN 'recomputed extra <> the invoice''s legs - settled'
         WHEN i.nBr > 1 AND (SELECT l.Diff FROM #L AS l WHERE l.Ref = i.Ref AND l.InvoiceNo = i.InvoiceNo) NOT BETWEEN 0 AND 1.00
              THEN 'extra not between 0.00 and 1.00'
         WHEN i.nBr > 1 AND (SELECT COUNT(*) FROM dbo.TicketDetails AS d INNER JOIN #L AS l ON l.Ref = i.Ref AND l.InvoiceNo = i.InvoiceNo
                             WHERE d.TicketNumber = l.TicketNumber AND d.ReferenceNumber = l.Ref AND d.BranchCode = l.BranchCode) <> 2
           OR i.nBr > 1 AND (SELECT COUNT(*) FROM dbo.TicketDetails AS d INNER JOIN #L AS l ON l.Ref = i.Ref AND l.InvoiceNo = i.InvoiceNo
                             WHERE d.TicketNumber = l.TicketNumber AND d.ReferenceNumber = l.Ref AND d.BranchCode = l.BranchCode
                               AND ((d.AccountCode = l.PayableAcct AND d.Debit = l.OldAmount AND ISNULL(d.Credit, 0) = 0)
                                    OR (d.AccountCode = l.BankAcct AND d.Credit = l.OldAmount AND ISNULL(d.Debit, 0) = 0))) <> 2
              THEN 'ticket lines not as expected'
         WHEN i.nBr > 1 AND (SELECT COUNT(*) FROM dbo.SupplierLedger AS s INNER JOIN #L AS l ON l.Ref = i.Ref AND l.InvoiceNo = i.InvoiceNo
                             WHERE s.SupplierKey = l.SupplierID AND s.ReferenceNumber = l.Ref AND s.InvoiceNo = l.InvoiceNo
                               AND s.ReferenceKey LIKE '%-' + l.BranchCode AND s.Debit = l.OldAmount AND ISNULL(s.Credit, 0) = 0) <> 1
              THEN 'supplier ledger row not as expected'
         END
FROM #I AS i;

UPDATE v SET Problem =
    CASE WHEN v.Screen IS NULL OR v.Cheque IS NULL THEN 'no TransactionPaymentAP / CheckVoucher row'
         WHEN EXISTS (SELECT 1 FROM #P AS p WHERE p.Ref = v.Ref AND p.Problem IS NOT NULL)
              THEN (SELECT TOP (1) p.InvoiceNo + ': ' + p.Problem FROM #P AS p WHERE p.Ref = v.Ref AND p.Problem IS NOT NULL ORDER BY p.InvoiceNo)
         WHEN v.nMultiInv < 1 THEN 'no multi-branch invoice on the voucher'
         WHEN (SELECT SUM(i.Settled) FROM #I AS i WHERE i.Ref = v.Ref) <> v.Screen THEN 'the invoices'' settled amounts don''t add up to the screen total'
         WHEN v.Extra <= 0 OR v.Extra > 1.00 THEN 'extra not between 0.01 and 1.00 (' + CAST(v.Extra AS VARCHAR(30)) + ')'
         WHEN (SELECT SUM(l.Diff) FROM #L AS l WHERE l.Ref = v.Ref) <> v.Extra THEN 'recomputed extras don''t add up to legs - screen'
         WHEN v.Cheque <> v.Legs THEN 'cheque amount is not the sum of the legs'
         WHEN (SELECT COUNT(DISTINCT l.BankAcct) FROM #L AS l WHERE l.Ref = v.Ref) <> 1
           OR (SELECT MAX(l.BankAcct) FROM #L AS l WHERE l.Ref = v.Ref) <> v.BankAcct THEN 'legs on more than one bank account'
         WHEN (SELECT COUNT(*) FROM dbo.BankStatementRecon AS r
               WHERE r.ReferenceNo = v.VoucherID AND r.ItemType = 'OC' AND r.SourceModule = 'AP-PAYMENT' AND r.AccountCode = v.BankAcct) <> 1
              THEN 'not exactly one bank-recon item for the voucher'
         WHEN EXISTS (SELECT 1 FROM dbo.BankStatementRecon AS r LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = r.HeaderID
                      WHERE r.ReferenceNo = v.VoucherID AND r.ItemType = 'OC' AND r.SourceModule = 'AP-PAYMENT' AND r.AccountCode = v.BankAcct
                        AND (r.Amount <> v.Cheque OR h.Status = 'LOCKED' OR ISNULL(r.IsResolved, 0) <> 0))
              THEN 'bank-recon item differs from the cheque, is already cleared, or its period is locked'
         END
FROM #V AS v
WHERE v.Skipped = 0;

SELECT v.Ref, v.VoucherID, i.InvoiceNo, i.Status, i.Settled, i.InvLegs, l.BranchCode AS LastBranch, l.OldAmount, l.BuggyLast, l.CorrectLast, l.Diff,
       v.Legs, v.Screen, v.Cheque, v.Extra,
       CASE WHEN v.Skipped = 1 THEN 'SKIPPED (voucher was reversed)' ELSE ISNULL(v.Problem, 'OK') END AS [Check]
FROM #V AS v
LEFT JOIN #I AS i ON i.Ref = v.Ref
LEFT JOIN #L AS l ON l.Ref = i.Ref AND l.InvoiceNo = i.InvoiceNo
ORDER BY v.Ref, i.InvoiceNo;
IF EXISTS (SELECT 1 FROM #V WHERE Skipped = 0 AND Problem IS NOT NULL)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 59977, 'A listed voucher is not as expected (see the Check column); nothing was changed.', 1;
END
DELETE FROM #V WHERE Skipped = 1;

-- backups (the rows before)
SELECT p.* INTO dbo.SplitFix_Backup_20261013b_APPaymentDetails
FROM dbo.APPaymentDetails AS p INNER JOIN #L AS l ON p.ReferenceNumber = l.Ref AND p.InvoiceNo = l.InvoiceNo AND p.BranchCode = l.BranchCode
                                                AND p.PaymentType = 'EXPENSE PAYMENT';
SELECT d.* INTO dbo.SplitFix_Backup_20261013b_TicketDetails
FROM dbo.TicketDetails AS d INNER JOIN #L AS l ON d.TicketNumber = l.TicketNumber AND d.ReferenceNumber = l.Ref AND d.BranchCode = l.BranchCode;
SELECT s.* INTO dbo.SplitFix_Backup_20261013b_SupplierLedger
FROM dbo.SupplierLedger AS s INNER JOIN #L AS l ON s.SupplierKey = l.SupplierID AND s.ReferenceNumber = l.Ref AND s.InvoiceNo = l.InvoiceNo
     AND s.ReferenceKey LIKE '%-' + l.BranchCode AND s.Debit = l.OldAmount;
SELECT c.* INTO dbo.SplitFix_Backup_20261013b_CheckVoucher
FROM dbo.CheckVoucher AS c INNER JOIN #V AS v ON c.ReferenceNumber = v.Ref;
SELECT r.* INTO dbo.SplitFix_Backup_20261013b_BankStatementRecon
FROM dbo.BankStatementRecon AS r INNER JOIN #V AS v ON r.ReferenceNo = v.VoucherID AND r.ItemType = 'OC' AND r.SourceModule = 'AP-PAYMENT'
                                                   AND r.AccountCode = v.BankAcct;

-- 1. the legs
UPDATE p SET Amount = p.Amount - l.Diff
FROM dbo.APPaymentDetails AS p INNER JOIN #L AS l ON p.ReferenceNumber = l.Ref AND p.InvoiceNo = l.InvoiceNo AND p.BranchCode = l.BranchCode
                                                AND p.PaymentType = 'EXPENSE PAYMENT'
WHERE l.Diff <> 0;
-- 2. their tickets: DR payable / CR bank
UPDATE d SET Debit = CASE WHEN d.AccountCode = l.PayableAcct THEN d.Debit - l.Diff ELSE d.Debit END,
             Credit = CASE WHEN d.AccountCode = l.BankAcct THEN d.Credit - l.Diff ELSE d.Credit END
FROM dbo.TicketDetails AS d INNER JOIN #L AS l ON d.TicketNumber = l.TicketNumber AND d.ReferenceNumber = l.Ref AND d.BranchCode = l.BranchCode
WHERE d.AccountCode IN (l.PayableAcct, l.BankAcct) AND l.Diff <> 0;
-- 3. their supplier-ledger rows (the trigger re-chains the supplier and its account)
UPDATE s SET Debit = s.Debit - l.Diff
FROM dbo.SupplierLedger AS s INNER JOIN #L AS l ON s.SupplierKey = l.SupplierID AND s.ReferenceNumber = l.Ref AND s.InvoiceNo = l.InvoiceNo
     AND s.ReferenceKey LIKE '%-' + l.BranchCode AND s.Debit = l.OldAmount
WHERE l.Diff <> 0;
-- 4. the voucher / cheque
UPDATE c SET Amount = c.Amount - v.Extra, DateUpdate = CAST(GETDATE() AS DATE)
FROM dbo.CheckVoucher AS c INNER JOIN #V AS v ON c.ReferenceNumber = v.Ref;
-- 5. its outstanding-cheque item
UPDATE r SET Amount = r.Amount - v.Extra, UpdatedBy = 'SplitFix [73] 2026-10-13', DateTimeUpdated = GETDATE()
FROM dbo.BankStatementRecon AS r INNER JOIN #V AS v ON r.ReferenceNo = v.VoucherID AND r.ItemType = 'OC' AND r.SourceModule = 'AP-PAYMENT'
                                                   AND r.AccountCode = v.BankAcct;

-- post-check: legs = screen = cheque = bank credit = recon item; every invoice's legs = settled; touched tickets balanced
IF EXISTS (
    SELECT 1 FROM #V AS v
    WHERE (SELECT SUM(p.Amount) FROM dbo.APPaymentDetails AS p WHERE p.ReferenceNumber = v.Ref AND p.PaymentType = 'EXPENSE PAYMENT') <> v.Screen
       OR (SELECT CAST(c.Amount AS DECIMAL(18,2)) FROM dbo.CheckVoucher AS c WHERE c.ReferenceNumber = v.Ref) <> v.Screen
       OR (SELECT SUM(d.Credit) FROM dbo.TicketDetails AS d INNER JOIN dbo.APPaymentDetails AS p ON p.TicketNumber = d.TicketNumber AND p.BranchCode = d.BranchCode
           WHERE p.ReferenceNumber = v.Ref AND p.PaymentType = 'EXPENSE PAYMENT' AND d.ReferenceNumber = v.Ref AND d.AccountCode = p.CreditGLCode) <> v.Screen
       OR EXISTS (SELECT 1 FROM dbo.BankStatementRecon AS r
                  WHERE r.ReferenceNo = v.VoucherID AND r.ItemType = 'OC' AND r.SourceModule = 'AP-PAYMENT' AND r.AccountCode = v.BankAcct
                    AND r.Amount <> v.Screen)
       OR EXISTS (SELECT 1 FROM #I AS i
                  WHERE i.Ref = v.Ref
                    AND (SELECT SUM(p.Amount) FROM dbo.APPaymentDetails AS p
                         WHERE p.ReferenceNumber = i.Ref AND p.InvoiceNo = i.InvoiceNo AND p.PaymentType = 'EXPENSE PAYMENT') <> i.Settled)
       OR EXISTS (SELECT 1 FROM #L AS l INNER JOIN dbo.TicketDetails AS d ON d.TicketNumber = l.TicketNumber AND d.ReferenceNumber = l.Ref
                                                                         AND d.BranchCode = l.BranchCode
                  WHERE l.Ref = v.Ref GROUP BY l.TicketNumber HAVING SUM(d.Debit - d.Credit) <> 0))
BEGIN
    ROLLBACK TRANSACTION;
    THROW 59978, 'Post-check failed (legs / cheque / bank / recon / invoice / ticket don''t tie); nothing was changed.', 1;
END

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
SELECT v.Ref, v.VoucherID, v.Legs AS OldAmount, v.Screen AS NewAmount, v.Extra AS Removed FROM #V AS v ORDER BY v.Ref;
PRINT 'Split-bug vouchers corrected (backups dbo.SplitFix_Backup_20261013b_*).';
