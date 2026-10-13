/* ================================================================
   2026-10-12f - Supplier payment: correct the vouchers the multi-branch split bug inflated (data only)
   ================================================================
   Script 2026-10-12d fixed sp_AddPaymentSupplierCompound_V2 so that new multi-branch payments split exactly.
   Vouchers posted before it still carry the extra cents on their last branch leg. The user confirmed (2026-10-12)
   that the physical cheques were written for the correct amount (the screen's total), so the system records are
   wrong and are corrected here:

     ref 28500 / voucher 688  (CEB-PCF-080626, cheque 2384476, 2026-08-10): 199,999.06 -> 199,999.00
     ref 38626 / voucher 913  (SOA#52566,      cheque 2384565, 2026-10-12): 199,999.06 -> 199,999.00

   Per voucher, the extra E = sum of its branch legs - the screen's total (TransactionPaymentAP.Amount); it sits on
   one leg (the last branch, 888). Corrected, each by -E:
     1. APPaymentDetails  - that leg's Amount
     2. TicketDetails     - that leg's ticket: DR payable and CR bank (stays balanced)
     3. SupplierLedger    - that leg's payment row Debit (trg_SupplierLedger_Recalc re-chains the supplier)
     4. CheckVoucher      - the voucher amount (= the cheque)
     5. BankStatementRecon- the voucher's outstanding-cheque item (if its period is not locked)
   Every expected value is checked first (single fully paid expense invoice, not reversed, exactly one leg off by
   exactly E, 0 < E <= 1.00, cheque = legs, one ticket line each side, one ledger row, the recon item = the cheque).
   If any check fails nothing is changed and the reason is shown. A GL month closed over the ticket date is refused
   by the lock trigger (59900). Backups: SplitFix_Backup_20261012_* (the rows before).

   Other vouchers the bug hit (STAGING: 684 / 28473 +0.01, 803 / 34730 +0.01, 823 / 35103 +0.48,
   837 / 36257 +0.06, 787 / 32949 +0.52, 867 / 36453 +0.18) are NOT in the list: add a reference only once the
   accountant confirms its cheque was written for the screen's total (see docs/CLAUDE_WORKLOG.md).

   One transaction with a post-check. Run on DEV / STAGING / PRODUCTION; a reference not found there is skipped.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

IF OBJECT_ID('dbo.SplitFix_Backup_20261012_APPaymentDetails', 'U') IS NOT NULL
    THROW 59970, 'This script has been run here before (SplitFix_Backup_20261012_APPaymentDetails exists).', 1;

BEGIN TRANSACTION;

-- the references to correct (only vouchers whose cheque was confirmed written for the screen's total)
DECLARE @List TABLE (Ref VARCHAR(10) NOT NULL PRIMARY KEY);
INSERT INTO @List (Ref) VALUES ('28500'), ('38626');

-- one row per listed voucher found here
CREATE TABLE #V (
    Ref VARCHAR(10) NOT NULL PRIMARY KEY, VoucherID VARCHAR(20) NULL, SupplierID VARCHAR(50) NULL,
    Legs DECIMAL(18,2) NULL, Screen DECIMAL(18,2) NULL, Cheque DECIMAL(18,2) NULL, Extra DECIMAL(18,2) NULL,
    nInvoices INT NULL, nOffLegs INT NULL, Problem VARCHAR(300) NULL);
INSERT INTO #V (Ref, VoucherID, SupplierID, Legs, Screen, Cheque, nInvoices)
SELECT l.Ref, MAX(p.VoucherID), MAX(p.SupplierID), SUM(p.Amount),
       (SELECT CAST(MAX(t.Amount) AS DECIMAL(18,2)) FROM dbo.TransactionPaymentAP AS t WHERE t.ReferenceNumber = TRY_CAST(l.Ref AS INT)),
       (SELECT CAST(MAX(c.Amount) AS DECIMAL(18,2)) FROM dbo.CheckVoucher AS c WHERE c.ReferenceNumber = l.Ref),
       COUNT(DISTINCT p.InvoiceNo)
FROM @List AS l
INNER JOIN dbo.APPaymentDetails AS p ON p.ReferenceNumber = l.Ref AND p.PaymentType = 'EXPENSE PAYMENT'
GROUP BY l.Ref;
UPDATE #V SET Extra = Legs - Screen;

-- the leg that carries the extra: its amount - its branch share of the (fully paid) invoice
CREATE TABLE #L (
    Ref VARCHAR(10) NOT NULL, VoucherID VARCHAR(20) NOT NULL, SupplierID VARCHAR(50) NOT NULL, InvoiceNo VARCHAR(150) NULL,
    BatchRef BIGINT NULL, BranchCode VARCHAR(10) NOT NULL, TicketNumber VARCHAR(30) NOT NULL, PayableAcct VARCHAR(30) NOT NULL,
    BankAcct VARCHAR(30) NOT NULL, OldAmount DECIMAL(18,2) NOT NULL, Share DECIMAL(18,2) NOT NULL, Diff DECIMAL(18,2) NOT NULL);
INSERT INTO #L
SELECT v.Ref, p.VoucherID, p.SupplierID, p.InvoiceNo, p.BatchReferenceID, p.BranchCode, p.TicketNumber, p.DebitGLCode, p.CreditGLCode,
       p.Amount, sh.Share, p.Amount - sh.Share
FROM #V AS v
INNER JOIN dbo.APPaymentDetails AS p ON p.ReferenceNumber = v.Ref AND p.PaymentType = 'EXPENSE PAYMENT'
CROSS APPLY (SELECT CAST(SUM(m.Amount) AS DECIMAL(18,2)) AS Share FROM dbo.ExpenseMaster AS m
             WHERE m.SupplierID = p.SupplierID AND m.InvoiceNo = p.InvoiceNo AND m.BatchReferenceID = p.BatchReferenceID AND m.BranchCode = p.BranchCode) AS sh
WHERE p.Amount <> sh.Share;
UPDATE v SET nOffLegs = (SELECT COUNT(*) FROM #L AS l WHERE l.Ref = v.Ref) FROM #V AS v;

-- every expected value, or the reason it isn't safe
UPDATE v SET Problem =
    CASE WHEN v.Screen IS NULL OR v.Cheque IS NULL THEN 'no TransactionPaymentAP / CheckVoucher row'
         WHEN v.nInvoices <> 1 THEN 'more than one invoice on the voucher'
         WHEN EXISTS (SELECT 1 FROM dbo.PaymentReversalAudit AS r WHERE r.ReferenceNumber = v.Ref AND r.SupplierID = v.SupplierID)
              OR EXISTS (SELECT 1 FROM dbo.CheckVoucher AS c WHERE c.ReferenceNumber = v.Ref AND c.isErrorCorrect = 1) THEN 'voucher was reversed'
         WHEN NOT EXISTS (SELECT 1 FROM dbo.ExpenseSummary AS e INNER JOIN #L AS l ON l.Ref = v.Ref AND e.SupplierID = l.SupplierID
                                                                                   AND e.InvoiceNo = l.InvoiceNo AND e.BatchReferenceID = l.BatchRef
                          WHERE e.Status = 'FULLYPAID' AND e.Balance = 0) THEN 'invoice is not fully paid (the branch shares can''t be checked)'
         WHEN v.Extra <= 0 OR v.Extra > 1.00 THEN 'extra not between 0.01 and 1.00 (' + CAST(v.Extra AS VARCHAR(30)) + ')'
         WHEN v.nOffLegs <> 1 OR (SELECT MAX(l.Diff) FROM #L AS l WHERE l.Ref = v.Ref) <> v.Extra THEN 'the extra is not on exactly one leg'
         WHEN v.Cheque <> v.Legs THEN 'cheque amount is not the sum of the legs'
         WHEN (SELECT COUNT(*) FROM dbo.TicketDetails AS d INNER JOIN #L AS l ON l.Ref = v.Ref
               WHERE d.TicketNumber = l.TicketNumber AND d.ReferenceNumber = v.Ref AND d.BranchCode = l.BranchCode
                 AND ((d.AccountCode = l.PayableAcct AND d.Debit = l.OldAmount AND ISNULL(d.Credit, 0) = 0)
                      OR (d.AccountCode = l.BankAcct AND d.Credit = l.OldAmount AND ISNULL(d.Debit, 0) = 0))) <> 2 THEN 'ticket lines not as expected'
         WHEN (SELECT COUNT(*) FROM dbo.SupplierLedger AS s INNER JOIN #L AS l ON l.Ref = v.Ref
               WHERE s.SupplierKey = l.SupplierID AND s.ReferenceNumber = v.Ref AND s.InvoiceNo = l.InvoiceNo
                 AND s.ReferenceKey LIKE '%-' + l.BranchCode AND s.Debit = l.OldAmount AND ISNULL(s.Credit, 0) = 0) <> 1 THEN 'supplier ledger row not as expected'
         WHEN EXISTS (SELECT 1 FROM dbo.BankStatementRecon AS r INNER JOIN #L AS l ON l.Ref = v.Ref
                      LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = r.HeaderID
                      WHERE r.ReferenceNo = l.VoucherID AND r.ItemType = 'OC' AND r.SourceModule = 'AP-PAYMENT' AND r.AccountCode = l.BankAcct
                        AND (r.Amount <> v.Cheque OR h.Status = 'LOCKED')) THEN 'bank-recon item differs from the cheque, or its period is locked'
         END
FROM #V AS v;

SELECT v.Ref, v.VoucherID, v.Legs, v.Screen, v.Cheque, v.Extra, ISNULL(v.Problem, 'OK') AS [Check] FROM #V AS v;
IF EXISTS (SELECT 1 FROM #V WHERE Problem IS NOT NULL)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 59971, 'A listed voucher is not as expected (see the Check column); nothing was changed.', 1;
END

-- backups (the rows before)
SELECT p.* INTO dbo.SplitFix_Backup_20261012_APPaymentDetails
FROM dbo.APPaymentDetails AS p INNER JOIN #L AS l ON p.ReferenceNumber = l.Ref AND p.BranchCode = l.BranchCode AND p.PaymentType = 'EXPENSE PAYMENT';
SELECT d.* INTO dbo.SplitFix_Backup_20261012_TicketDetails
FROM dbo.TicketDetails AS d INNER JOIN #L AS l ON d.TicketNumber = l.TicketNumber AND d.ReferenceNumber = l.Ref AND d.BranchCode = l.BranchCode;
SELECT s.* INTO dbo.SplitFix_Backup_20261012_SupplierLedger
FROM dbo.SupplierLedger AS s INNER JOIN #L AS l ON s.SupplierKey = l.SupplierID AND s.ReferenceNumber = l.Ref AND s.InvoiceNo = l.InvoiceNo
     AND s.ReferenceKey LIKE '%-' + l.BranchCode AND s.Debit = l.OldAmount;
SELECT c.* INTO dbo.SplitFix_Backup_20261012_CheckVoucher
FROM dbo.CheckVoucher AS c INNER JOIN #V AS v ON c.ReferenceNumber = v.Ref;
SELECT r.* INTO dbo.SplitFix_Backup_20261012_BankStatementRecon
FROM dbo.BankStatementRecon AS r INNER JOIN #L AS l ON r.ReferenceNo = l.VoucherID AND r.ItemType = 'OC' AND r.SourceModule = 'AP-PAYMENT' AND r.AccountCode = l.BankAcct;

-- 1. the leg
UPDATE p SET Amount = p.Amount - l.Diff
FROM dbo.APPaymentDetails AS p INNER JOIN #L AS l ON p.ReferenceNumber = l.Ref AND p.BranchCode = l.BranchCode AND p.PaymentType = 'EXPENSE PAYMENT';
-- 2. its ticket: DR payable / CR bank
UPDATE d SET Debit = CASE WHEN d.AccountCode = l.PayableAcct THEN d.Debit - l.Diff ELSE d.Debit END,
             Credit = CASE WHEN d.AccountCode = l.BankAcct THEN d.Credit - l.Diff ELSE d.Credit END
FROM dbo.TicketDetails AS d INNER JOIN #L AS l ON d.TicketNumber = l.TicketNumber AND d.ReferenceNumber = l.Ref AND d.BranchCode = l.BranchCode
WHERE d.AccountCode IN (l.PayableAcct, l.BankAcct);
-- 3. its supplier-ledger row (the trigger re-chains the supplier and its account)
UPDATE s SET Debit = s.Debit - l.Diff
FROM dbo.SupplierLedger AS s INNER JOIN #L AS l ON s.SupplierKey = l.SupplierID AND s.ReferenceNumber = l.Ref AND s.InvoiceNo = l.InvoiceNo
     AND s.ReferenceKey LIKE '%-' + l.BranchCode AND s.Debit = l.OldAmount;
-- 4. the voucher / cheque
UPDATE c SET Amount = c.Amount - v.Extra, DateUpdate = CAST(GETDATE() AS DATE)
FROM dbo.CheckVoucher AS c INNER JOIN #V AS v ON c.ReferenceNumber = v.Ref;
-- 5. its outstanding-cheque item
UPDATE r SET Amount = r.Amount - l.Diff, UpdatedBy = 'SplitFix 2026-10-12f', DateTimeUpdated = GETDATE()
FROM dbo.BankStatementRecon AS r INNER JOIN #L AS l ON r.ReferenceNo = l.VoucherID AND r.ItemType = 'OC' AND r.SourceModule = 'AP-PAYMENT' AND r.AccountCode = l.BankAcct;

-- post-check: legs = screen = cheque = bank credit (= recon item), every touched ticket balanced, the invoice nets to 0 in the ledger
IF EXISTS (
    SELECT 1 FROM #V AS v
    WHERE (SELECT SUM(p.Amount) FROM dbo.APPaymentDetails AS p WHERE p.ReferenceNumber = v.Ref AND p.PaymentType = 'EXPENSE PAYMENT') <> v.Screen
       OR (SELECT CAST(c.Amount AS DECIMAL(18,2)) FROM dbo.CheckVoucher AS c WHERE c.ReferenceNumber = v.Ref) <> v.Screen
       OR (SELECT SUM(d.Credit) FROM dbo.TicketDetails AS d INNER JOIN dbo.APPaymentDetails AS p ON p.TicketNumber = d.TicketNumber AND p.BranchCode = d.BranchCode
           WHERE p.ReferenceNumber = v.Ref AND p.PaymentType = 'EXPENSE PAYMENT' AND d.ReferenceNumber = v.Ref AND d.AccountCode = p.CreditGLCode) <> v.Screen
       OR EXISTS (SELECT 1 FROM dbo.BankStatementRecon AS r INNER JOIN #L AS l ON l.Ref = v.Ref
                  WHERE r.ReferenceNo = l.VoucherID AND r.ItemType = 'OC' AND r.SourceModule = 'AP-PAYMENT' AND r.AccountCode = l.BankAcct AND r.Amount <> v.Screen)
       OR EXISTS (SELECT 1 FROM #L AS l INNER JOIN dbo.TicketDetails AS d ON d.TicketNumber = l.TicketNumber AND d.ReferenceNumber = l.Ref AND d.BranchCode = l.BranchCode
                  WHERE l.Ref = v.Ref GROUP BY l.TicketNumber HAVING SUM(d.Debit - d.Credit) <> 0)
       OR (SELECT SUM(s.Credit - s.Debit) FROM dbo.SupplierLedger AS s INNER JOIN #L AS l ON l.Ref = v.Ref
           WHERE s.SupplierKey = l.SupplierID AND s.InvoiceNo = l.InvoiceNo AND ISNULL(s.ErrorCorrectTag, 0) = 0
             AND s.ReferenceNumber IN (v.Ref, (SELECT TOP 1 e.ReferenceNumber FROM dbo.ExpenseSummary AS e
                                               WHERE e.SupplierID = l.SupplierID AND e.InvoiceNo = l.InvoiceNo AND e.BatchReferenceID = l.BatchRef))) <> 0)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 59972, 'Post-check failed (legs / cheque / bank / recon / ticket / ledger don''t tie); nothing was changed.', 1;
END

COMMIT TRANSACTION;
SELECT v.Ref, v.VoucherID, v.Legs AS OldAmount, v.Screen AS NewAmount, v.Extra AS Removed FROM #V AS v;
PRINT 'Split-bug vouchers corrected (backups dbo.SplitFix_Backup_20261012_*).';
