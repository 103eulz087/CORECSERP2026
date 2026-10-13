/* ================================================================
   2026-10-13 - Supplier payment: correct the remaining vouchers the multi-branch split bug inflated (data only)
   ================================================================
   Follows 2026-10-12f (vouchers 688 / 913). Script 2026-10-12d fixed sp_AddPaymentSupplierCompound_V2; vouchers
   posted before it still carry extra cents on the LAST branch (highest BranchCode) of their multi-branch invoice.
   Same rule as 2026-10-12f: the physical cheque / transfer was for the screen's total, so the system records are
   corrected to it (user, 2026-10-13: "fix those vouchers that has discrepancies").

     ref 32949 / voucher 787  (GLOBE, SOA-083126,            MBTC 101020108) 94,071.14  -> 94,070.62   (-0.52)
     ref 34730 / voucher 803  (ALPA, 9680,                   BDO2 101020102) 29,660.72  -> 29,660.71   (-0.01)
     ref 35103 / voucher 823  (CEB PCF, CEB-PCF-081826,      BDO1 101020101) 199,724.83 -> 199,724.35  (-0.48)
     ref 36257 / voucher 837  (DAV PCF, DAV-PCF-082126,      BDO1 101020101) 74,239.94  -> 74,239.88   (-0.06)
     ref 36453 / voucher 867  (CEB PCF, CEB-PCF-082726 + CAR-PCF-081826, BDO1) 199,870.87 -> 199,870.69 (-0.18)
   (STAGING figures. Voucher 684 / ref 28473 (+0.01) was reversed, so there is nothing to correct.)

   Why these invoices can't use 2026-10-12f's check: their payable was booked net (Balance below the line amounts),
   so a leg never equals its ExpenseMaster share. Instead the extra is recomputed independently, the way the old proc
   computed it: last branch = settled - SUM(BranchNetLiability / eNetLiability * settled) over a DECIMAL(38,2) column
   (ratio cut to 6 decimals), vs. the correct settled - SUM(ROUND(share, 2)) of the other branches. The voucher is
   corrected only when that recomputed extra = legs - screen total AND the last leg = the old formula's value.
   (Rehearsed on STAGING 2026-10-13; the same recompute gives +0.06 on 688 / 913, as 2026-10-12f found.)

   Per voucher, by -E on the last leg of its one multi-branch invoice:
     1. APPaymentDetails   - the leg's Amount
     2. TicketDetails      - the leg's ticket: DR payable and CR bank (stays balanced)
     3. SupplierLedger     - the leg's payment row Debit (trg_SupplierLedger_Recalc re-chains the supplier)
     4. CheckVoucher       - the voucher amount (= the cheque)
     5. BankStatementRecon - the voucher's outstanding-cheque item (must be open, uncleared, period not locked)
   If any check fails nothing is changed and the reason is shown. A GL month closed over the ticket date is refused
   by the lock trigger (59900). Backups: SplitFix_Backup_20261013_* (the rows before).

   One transaction with a post-check. Run on DEV / STAGING / PRODUCTION; a reference not found there is skipped.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

IF OBJECT_ID('dbo.SplitFix_Backup_20261013_APPaymentDetails', 'U') IS NOT NULL
    THROW 59973, 'This script has been run here before (SplitFix_Backup_20261013_APPaymentDetails exists).', 1;

BEGIN TRANSACTION;

DECLARE @List TABLE (Ref VARCHAR(10) NOT NULL PRIMARY KEY);
INSERT INTO @List (Ref) VALUES ('32949'), ('34730'), ('35103'), ('36257'), ('36453');

-- one row per listed voucher found here
CREATE TABLE #V (
    Ref VARCHAR(10) NOT NULL PRIMARY KEY, VoucherID VARCHAR(20) NULL, SupplierID VARCHAR(50) NULL,
    Legs DECIMAL(18,2) NULL, Screen DECIMAL(18,2) NULL, Cheque DECIMAL(18,2) NULL, Extra DECIMAL(18,2) NULL,
    nMultiInv INT NULL, Problem VARCHAR(300) NULL);
INSERT INTO #V (Ref, VoucherID, SupplierID, Legs, Screen, Cheque)
SELECT l.Ref, MAX(p.VoucherID), MAX(p.SupplierID), SUM(p.Amount),
       (SELECT CAST(MAX(t.Amount) AS DECIMAL(18,2)) FROM dbo.TransactionPaymentAP AS t WHERE t.ReferenceNumber = TRY_CAST(l.Ref AS INT)),
       (SELECT CAST(MAX(c.Amount) AS DECIMAL(18,2)) FROM dbo.CheckVoucher AS c WHERE c.ReferenceNumber = l.Ref)
FROM @List AS l
INNER JOIN dbo.APPaymentDetails AS p ON p.ReferenceNumber = l.Ref AND p.PaymentType = 'EXPENSE PAYMENT'
GROUP BY l.Ref;
UPDATE #V SET Extra = Legs - Screen;

-- invoices of each voucher; the multi-branch one carries the extra
CREATE TABLE #I (
    Ref VARCHAR(10) NOT NULL, InvoiceNo VARCHAR(150) NOT NULL, BatchRef BIGINT NULL, nBr INT NOT NULL, InvLegs DECIMAL(18,2) NOT NULL);
INSERT INTO #I
SELECT p.ReferenceNumber, p.InvoiceNo, p.BatchReferenceID, COUNT(DISTINCT p.BranchCode), SUM(p.Amount)
FROM #V AS v INNER JOIN dbo.APPaymentDetails AS p ON p.ReferenceNumber = v.Ref AND p.PaymentType = 'EXPENSE PAYMENT'
GROUP BY p.ReferenceNumber, p.InvoiceNo, p.BatchReferenceID;
UPDATE v SET nMultiInv = (SELECT COUNT(*) FROM #I AS i WHERE i.Ref = v.Ref AND i.nBr > 1) FROM #V AS v;

-- the old proc's split, recomputed for that invoice (settled = screen total - the other invoices' legs)
CREATE TABLE #R (
    Ref VARCHAR(10) NOT NULL, BranchCode VARCHAR(10) NOT NULL, Net DECIMAL(38,2) NOT NULL, eNet DECIMAL(18,2) NOT NULL,
    eGross DECIMAL(18,2) NOT NULL, RowNum INT NOT NULL, nBr INT NOT NULL);
;WITH mb AS (
    SELECT i.Ref, i.InvoiceNo, i.BatchRef, v.SupplierID,
           CAST(v.Screen - ISNULL((SELECT SUM(o.InvLegs) FROM #I AS o WHERE o.Ref = i.Ref AND o.InvoiceNo <> i.InvoiceNo), 0) AS DECIMAL(18,2)) AS eGross
    FROM #I AS i INNER JOIN #V AS v ON v.Ref = i.Ref
    WHERE i.nBr > 1 AND v.nMultiInv = 1),
br AS (
    SELECT mb.Ref, mb.eGross, m.BranchCode,
           SUM(m.Amount) - SUM(CASE WHEN m.IsEWTPostedAtAccrual = 1 THEN ISNULL(m.EWTAmount, 0) ELSE 0 END) AS Net
    FROM mb INNER JOIN dbo.ExpenseMaster AS m ON m.SupplierID = mb.SupplierID AND m.InvoiceNo = mb.InvoiceNo AND m.BatchReferenceID = mb.BatchRef
    GROUP BY mb.Ref, mb.eGross, m.BranchCode)
INSERT INTO #R
SELECT br.Ref, br.BranchCode, br.Net, CAST(SUM(br.Net) OVER (PARTITION BY br.Ref) AS DECIMAL(18,2)), br.eGross,
       ROW_NUMBER() OVER (PARTITION BY br.Ref ORDER BY br.BranchCode), COUNT(*) OVER (PARTITION BY br.Ref)
FROM br;

-- the leg to correct: the last branch of the multi-branch invoice
CREATE TABLE #L (
    Ref VARCHAR(10) NOT NULL PRIMARY KEY, VoucherID VARCHAR(20) NOT NULL, SupplierID VARCHAR(50) NOT NULL, InvoiceNo VARCHAR(150) NOT NULL,
    BatchRef BIGINT NULL, BranchCode VARCHAR(10) NOT NULL, TicketNumber VARCHAR(30) NOT NULL, PayableAcct VARCHAR(30) NOT NULL,
    BankAcct VARCHAR(30) NOT NULL, OldAmount DECIMAL(18,2) NOT NULL, BuggyLast DECIMAL(18,2) NOT NULL, CorrectLast DECIMAL(18,2) NOT NULL,
    Diff DECIMAL(18,2) NOT NULL, nRows INT NOT NULL);
INSERT INTO #L
SELECT x.Ref, MAX(p.VoucherID), MAX(p.SupplierID), MAX(p.InvoiceNo), MAX(p.BatchReferenceID), x.BranchCode, MAX(p.TicketNumber),
       MAX(p.DebitGLCode), MAX(p.CreditGLCode), SUM(p.Amount),
       CAST(x.eGross - (SELECT SUM(r2.Net / r2.eNet * r2.eGross) FROM #R AS r2 WHERE r2.Ref = x.Ref AND r2.RowNum < r2.nBr) AS DECIMAL(18,2)),
       CAST(x.eGross - (SELECT SUM(ROUND(CAST(r2.Net AS DECIMAL(18,2)) / r2.eNet * r2.eGross, 2)) FROM #R AS r2 WHERE r2.Ref = x.Ref AND r2.RowNum < r2.nBr) AS DECIMAL(18,2)),
       0, COUNT(*)
FROM #R AS x
INNER JOIN #I AS i ON i.Ref = x.Ref AND i.nBr > 1
INNER JOIN dbo.APPaymentDetails AS p ON p.ReferenceNumber = x.Ref AND p.InvoiceNo = i.InvoiceNo AND p.BranchCode = x.BranchCode AND p.PaymentType = 'EXPENSE PAYMENT'
WHERE x.RowNum = x.nBr
GROUP BY x.Ref, x.BranchCode, x.eGross;
UPDATE #L SET Diff = BuggyLast - CorrectLast;

-- every expected value, or the reason it isn't safe
UPDATE v SET Problem =
    CASE WHEN v.Screen IS NULL OR v.Cheque IS NULL THEN 'no TransactionPaymentAP / CheckVoucher row'
         WHEN EXISTS (SELECT 1 FROM dbo.PaymentReversalAudit AS r WHERE r.ReferenceNumber = v.Ref AND r.SupplierID = v.SupplierID)
              OR EXISTS (SELECT 1 FROM dbo.CheckVoucher AS c WHERE c.ReferenceNumber = v.Ref AND c.isErrorCorrect = 1) THEN 'voucher was reversed'
         WHEN v.nMultiInv <> 1 THEN 'not exactly one multi-branch invoice on the voucher'
         WHEN NOT EXISTS (SELECT 1 FROM #L AS l WHERE l.Ref = v.Ref) THEN 'last-branch leg not found'
         WHEN (SELECT l.nRows FROM #L AS l WHERE l.Ref = v.Ref) <> 1 THEN 'the last branch has more than one payment row'
         WHEN EXISTS (SELECT 1 FROM #L AS l INNER JOIN dbo.APPaymentDetails AS o
                        ON o.SupplierID = l.SupplierID AND o.InvoiceNo = l.InvoiceNo AND o.BatchReferenceID = l.BatchRef
                       AND o.PaymentType = 'EXPENSE PAYMENT' AND o.ReferenceNumber <> l.Ref
                      WHERE l.Ref = v.Ref) THEN 'another voucher also paid the invoice'
         WHEN NOT EXISTS (SELECT 1 FROM dbo.ExpenseSummary AS e INNER JOIN #L AS l ON l.Ref = v.Ref AND e.SupplierID = l.SupplierID
                                                                                   AND e.InvoiceNo = l.InvoiceNo AND e.BatchReferenceID = l.BatchRef
                          WHERE e.Status = 'FULLYPAID' AND e.Balance = 0) THEN 'invoice is not fully paid'
         WHEN v.Extra <= 0 OR v.Extra > 1.00 THEN 'extra not between 0.01 and 1.00 (' + CAST(v.Extra AS VARCHAR(30)) + ')'
         WHEN (SELECT l.Diff FROM #L AS l WHERE l.Ref = v.Ref) <> v.Extra
              THEN 'recomputed extra (' + CAST((SELECT l.Diff FROM #L AS l WHERE l.Ref = v.Ref) AS VARCHAR(30)) + ') <> legs - screen'
         WHEN (SELECT l.OldAmount - l.BuggyLast FROM #L AS l WHERE l.Ref = v.Ref) <> 0 THEN 'the last leg is not the old formula''s amount'
         WHEN v.Cheque <> v.Legs THEN 'cheque amount is not the sum of the legs'
         WHEN (SELECT COUNT(*) FROM dbo.TicketDetails AS d INNER JOIN #L AS l ON l.Ref = v.Ref
               WHERE d.TicketNumber = l.TicketNumber AND d.ReferenceNumber = v.Ref AND d.BranchCode = l.BranchCode) <> 2
           OR (SELECT COUNT(*) FROM dbo.TicketDetails AS d INNER JOIN #L AS l ON l.Ref = v.Ref
               WHERE d.TicketNumber = l.TicketNumber AND d.ReferenceNumber = v.Ref AND d.BranchCode = l.BranchCode
                 AND ((d.AccountCode = l.PayableAcct AND d.Debit = l.OldAmount AND ISNULL(d.Credit, 0) = 0)
                      OR (d.AccountCode = l.BankAcct AND d.Credit = l.OldAmount AND ISNULL(d.Debit, 0) = 0))) <> 2 THEN 'ticket lines not as expected'
         WHEN (SELECT COUNT(*) FROM dbo.SupplierLedger AS s INNER JOIN #L AS l ON l.Ref = v.Ref
               WHERE s.SupplierKey = l.SupplierID AND s.ReferenceNumber = v.Ref AND s.InvoiceNo = l.InvoiceNo
                 AND s.ReferenceKey LIKE '%-' + l.BranchCode AND s.Debit = l.OldAmount AND ISNULL(s.Credit, 0) = 0) <> 1 THEN 'supplier ledger row not as expected'
         WHEN (SELECT COUNT(*) FROM dbo.BankStatementRecon AS r INNER JOIN #L AS l ON l.Ref = v.Ref
               WHERE r.ReferenceNo = l.VoucherID AND r.ItemType = 'OC' AND r.SourceModule = 'AP-PAYMENT' AND r.AccountCode = l.BankAcct) <> 1
              THEN 'not exactly one bank-recon item for the voucher'
         WHEN EXISTS (SELECT 1 FROM dbo.BankStatementRecon AS r INNER JOIN #L AS l ON l.Ref = v.Ref
                      LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = r.HeaderID
                      WHERE r.ReferenceNo = l.VoucherID AND r.ItemType = 'OC' AND r.SourceModule = 'AP-PAYMENT' AND r.AccountCode = l.BankAcct
                        AND (r.Amount <> v.Cheque OR h.Status = 'LOCKED' OR ISNULL(r.IsResolved, 0) <> 0))
              THEN 'bank-recon item differs from the cheque, is already cleared, or its period is locked'
         END
FROM #V AS v;

SELECT v.Ref, v.VoucherID, v.Legs, v.Screen, v.Cheque, v.Extra, l.BranchCode AS LastBranch, l.OldAmount, l.BuggyLast, l.CorrectLast, l.Diff,
       ISNULL(v.Problem, 'OK') AS [Check]
FROM #V AS v LEFT JOIN #L AS l ON l.Ref = v.Ref ORDER BY v.Ref;
IF EXISTS (SELECT 1 FROM #V WHERE Problem IS NOT NULL)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 59974, 'A listed voucher is not as expected (see the Check column); nothing was changed.', 1;
END

-- backups (the rows before)
SELECT p.* INTO dbo.SplitFix_Backup_20261013_APPaymentDetails
FROM dbo.APPaymentDetails AS p INNER JOIN #L AS l ON p.ReferenceNumber = l.Ref AND p.InvoiceNo = l.InvoiceNo AND p.BranchCode = l.BranchCode AND p.PaymentType = 'EXPENSE PAYMENT';
SELECT d.* INTO dbo.SplitFix_Backup_20261013_TicketDetails
FROM dbo.TicketDetails AS d INNER JOIN #L AS l ON d.TicketNumber = l.TicketNumber AND d.ReferenceNumber = l.Ref AND d.BranchCode = l.BranchCode;
SELECT s.* INTO dbo.SplitFix_Backup_20261013_SupplierLedger
FROM dbo.SupplierLedger AS s INNER JOIN #L AS l ON s.SupplierKey = l.SupplierID AND s.ReferenceNumber = l.Ref AND s.InvoiceNo = l.InvoiceNo
     AND s.ReferenceKey LIKE '%-' + l.BranchCode AND s.Debit = l.OldAmount;
SELECT c.* INTO dbo.SplitFix_Backup_20261013_CheckVoucher
FROM dbo.CheckVoucher AS c INNER JOIN #V AS v ON c.ReferenceNumber = v.Ref;
SELECT r.* INTO dbo.SplitFix_Backup_20261013_BankStatementRecon
FROM dbo.BankStatementRecon AS r INNER JOIN #L AS l ON r.ReferenceNo = l.VoucherID AND r.ItemType = 'OC' AND r.SourceModule = 'AP-PAYMENT' AND r.AccountCode = l.BankAcct;

-- 1. the leg
UPDATE p SET Amount = p.Amount - l.Diff
FROM dbo.APPaymentDetails AS p INNER JOIN #L AS l ON p.ReferenceNumber = l.Ref AND p.InvoiceNo = l.InvoiceNo AND p.BranchCode = l.BranchCode AND p.PaymentType = 'EXPENSE PAYMENT';
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
UPDATE r SET Amount = r.Amount - l.Diff, UpdatedBy = 'SplitFix 2026-10-13', DateTimeUpdated = GETDATE()
FROM dbo.BankStatementRecon AS r INNER JOIN #L AS l ON r.ReferenceNo = l.VoucherID AND r.ItemType = 'OC' AND r.SourceModule = 'AP-PAYMENT' AND r.AccountCode = l.BankAcct;

-- post-check: legs = screen = cheque = bank credit (= recon item), every touched ticket balanced
IF EXISTS (
    SELECT 1 FROM #V AS v
    WHERE (SELECT SUM(p.Amount) FROM dbo.APPaymentDetails AS p WHERE p.ReferenceNumber = v.Ref AND p.PaymentType = 'EXPENSE PAYMENT') <> v.Screen
       OR (SELECT CAST(c.Amount AS DECIMAL(18,2)) FROM dbo.CheckVoucher AS c WHERE c.ReferenceNumber = v.Ref) <> v.Screen
       OR (SELECT SUM(d.Credit) FROM dbo.TicketDetails AS d INNER JOIN dbo.APPaymentDetails AS p ON p.TicketNumber = d.TicketNumber AND p.BranchCode = d.BranchCode
           WHERE p.ReferenceNumber = v.Ref AND p.PaymentType = 'EXPENSE PAYMENT' AND d.ReferenceNumber = v.Ref AND d.AccountCode = p.CreditGLCode) <> v.Screen
       OR EXISTS (SELECT 1 FROM dbo.BankStatementRecon AS r INNER JOIN #L AS l ON l.Ref = v.Ref
                  WHERE r.ReferenceNo = l.VoucherID AND r.ItemType = 'OC' AND r.SourceModule = 'AP-PAYMENT' AND r.AccountCode = l.BankAcct AND r.Amount <> v.Screen)
       OR EXISTS (SELECT 1 FROM #L AS l INNER JOIN dbo.TicketDetails AS d ON d.TicketNumber = l.TicketNumber AND d.ReferenceNumber = l.Ref AND d.BranchCode = l.BranchCode
                  WHERE l.Ref = v.Ref GROUP BY l.TicketNumber HAVING SUM(d.Debit - d.Credit) <> 0))
BEGIN
    ROLLBACK TRANSACTION;
    THROW 59975, 'Post-check failed (legs / cheque / bank / recon / ticket don''t tie); nothing was changed.', 1;
END

COMMIT TRANSACTION;
SELECT v.Ref, v.VoucherID, v.Legs AS OldAmount, v.Screen AS NewAmount, v.Extra AS Removed FROM #V AS v ORDER BY v.Ref;
PRINT 'Split-bug vouchers corrected (backups dbo.SplitFix_Backup_20261013_*).';
