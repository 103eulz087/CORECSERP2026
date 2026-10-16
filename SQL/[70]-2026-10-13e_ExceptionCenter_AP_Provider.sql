/* ================================================================
   [70] 2026-10-13e - Exception Center: AP provider (sp_rpt_exc_AP_Summary / _Detail)
   ================================================================
   Plan: docs/plans/2026-10-13_ExceptionCenter_Consolidation_AP_BankRecon_Plan.md (phase 1, AP).
   Agreed with the web portal session (D:\SQLREF\webportal.md, 2026-10-13): per-module read-only providers named
   sp_rpt_exc_<Module>_*, called by the portal's sp_rpt_ExceptionCenter_Summary / _Detail dispatcher (portal sql/43).
   Registry rows (ExceptionDefinition, Owner = 'erp') are added by a separate script once sql/43's columns exist.

   New objects only, all read-only (pure SELECT):
     dbo.fn_rpt_exc_AP_Findings()      one row per finding, every AP check (single source of truth)
     dbo.sp_rpt_exc_AP_Summary         ExceptionCode, Findings, ValueAtRisk - one row per code, 0 when healthy
     dbo.sp_rpt_exc_AP_Detail          the findings of one code: TOP (500) + TotalMatchCount + Hint; unknown code -> RAISERROR
   Parameters @DateFrom / @DateTo / @AsOfDate follow the portal contract; these are INTEGRITY checks (a broken
   invariant is broken whenever it started), so they are evaluated as of now and the dates are not used.

   Checks (every rule validated on DEV, STAGING and PRODUCTION 2026-10-13 before it was written down; tolerance 0.005):
     AP-VOUCHER-LEGS          Critical  voucher not reversed: legs + overpay - advance applied = screen total
                                        (TransactionPaymentAP) when it has legs; voucher amount = GL bank credit; recon OC
                                        item = voucher amount (if any). The voucher is not compared with the legs: manual GL
                                        lines add to it legitimately (DEV 32340: a telegraphic voucher of manual lines only).
                                        (PRODUCTION: 684 / 914 / 934 / 967, the multi-branch split bug, keyed before the
                                        [61] fix; 914 / 934 / 967 keyed 10-09 / 10-10.)
     AP-TICKET-UNBALANCED     Critical  AP posting / payment / cash-advance ticket DR <> CR: per ticket number over all
                                        branches; cross-branch expenses (one ticket per branch) per expense reference.
     AP-SUPPLIER-LEDGER-CHAIN Critical  SupplierLedger: Ending = Beginning + Credit - Debit, and Beginning = the previous
                                        row's Ending (per supplier, TRN_SEQ_NO order).
     AP-ACCOUNT-VS-LEDGER     Critical  SupplierAccounts.AccountBalance = the supplier's last ledger Ending.
     AP-INVOICE-VS-LEDGER     Critical  open invoice balance = the supplier-ledger net (Credit - Debit) of the invoice:
                                        expense invoices (ExpenseSummary); purchases with a cost (APACCOUNTS, ActualCost
                                        <> 0; cost-0 rows are placeholders of PO-linked expenses). A NULL balance counts.
     AP-LEDGER-PAYMENT-SIDE   Critical  a payment ledger row (PV-AP / PV-MANUAL / SNGLE-PAY / EXP-ACCRUAL-PAY) of a live
                                        voucher posted as a credit (a payment reduces the payable: debit). (PRODUCTION:
                                        the 4 PV-AP purchase payments, 4,363,758.48, supplier balances overstated 2x.)
     AP-REVERSAL-NOT-RESTORED Critical  a reversed voucher (PaymentReversalAudit) whose ledger rows do not net to 0.
     AP-CREDIT-NEGATIVE       Critical  supplier advance credit (OVERPAY - ADVANCEAPPLIED, live vouchers) below 0.
     AP-STATUS-VS-BALANCE     Warning   FULLYPAID with a balance; negative balance; not FULLYPAID with balance 0 when the
                                        invoice had a payable (a ledger credit): expenses that liquidate an advance (e.g.
                                        AVENIDO CUSTOMS BROKERAGE) never create one and stay POSTED at 0 by design.
                                        (NULL balances are reported by AP-INVOICE-VS-LEDGER.)
     AP-CHEQUE-REUSED         Warning   a live cheque voucher reuses a cheque no. spent on a cancelled-cheque record ([55])
                                        of the same bank (the portal's VOU-DUP-CHECKNO covers two live cheques).

   Run on DEV first; STAGING on the user's go; PRODUCTION by the user. Re-running stops at the start.
   ================================================================ */

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('dbo.fn_rpt_exc_AP_Findings') IS NOT NULL OR OBJECT_ID('dbo.sp_rpt_exc_AP_Summary') IS NOT NULL OR OBJECT_ID('dbo.sp_rpt_exc_AP_Detail') IS NOT NULL
BEGIN
    RAISERROR('[70] has been run here before (fn_rpt_exc_AP_Findings / sp_rpt_exc_AP_* exist). Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

CREATE FUNCTION dbo.fn_rpt_exc_AP_Findings()
RETURNS TABLE
AS
/*  Read-only. Every AP exception finding, one row each. Shared by sp_rpt_exc_AP_Summary / _Detail.
    See SQL/[70]-2026-10-13e_ExceptionCenter_AP_Provider.sql for the rules. */
RETURN
WITH
rev AS (   -- reversed vouchers
    SELECT DISTINCT LTRIM(RTRIM(CAST(r.ReferenceNumber AS VARCHAR(30)))) AS Ref, r.SupplierID FROM dbo.PaymentReversalAudit r),
tp AS (
    SELECT LTRIM(RTRIM(CAST(t.ReferenceNumber AS VARCHAR(30)))) AS Ref, MAX(t.SupplierKey) AS SupplierID, MAX(t.VoucherType) AS VType,
           CAST(SUM(t.Amount) AS DECIMAL(18,2)) AS Screen, MAX(CAST(ISNULL(t.ErrorCorrect, 0) AS INT)) AS IsErr
    FROM dbo.TransactionPaymentAP t GROUP BY LTRIM(RTRIM(CAST(t.ReferenceNumber AS VARCHAR(30))))),
pd AS (
    SELECT LTRIM(RTRIM(p.ReferenceNumber)) AS Ref, MAX(p.VoucherID) AS VoucherID, MAX(p.CreditGLCode) AS BankAcct,
           COUNT(DISTINCT p.BranchCode) AS nBranches,
           CAST(SUM(CASE WHEN p.PaymentType IN ('EXPENSE PAYMENT', 'INVOICE PAYMENT') THEN p.Amount ELSE 0 END)
              + SUM(CASE WHEN p.PaymentType = 'OVERPAY' THEN p.Amount ELSE 0 END)
              - SUM(CASE WHEN p.PaymentType = 'ADVANCEAPPLIED' THEN p.Amount ELSE 0 END) AS DECIMAL(18,2)) AS Cash
    FROM dbo.APPaymentDetails p GROUP BY LTRIM(RTRIM(p.ReferenceNumber))),
vc AS (
    SELECT LTRIM(RTRIM(ReferenceNumber)) AS Ref, 'CHECK' AS VType, CAST(SUM(Amount) AS DECIMAL(18,2)) AS VAmt, MAX(CAST(ISNULL(isErrorCorrect, 0) AS INT)) AS IsErr
    FROM dbo.CheckVoucher GROUP BY LTRIM(RTRIM(ReferenceNumber))
    UNION ALL
    SELECT LTRIM(RTRIM(ReferenceNumber)), 'CASH', CAST(SUM(Amount) AS DECIMAL(18,2)), MAX(CAST(ISNULL(isErrorCorrect, 0) AS INT))
    FROM dbo.CashVoucher GROUP BY LTRIM(RTRIM(ReferenceNumber))
    UNION ALL
    SELECT LTRIM(RTRIM(ReferenceNumber)), 'TELEGRAPHIC', CAST(SUM(Amount) AS DECIMAL(18,2)), MAX(CAST(ISNULL(isErrorCorrect, 0) AS INT))
    FROM dbo.TelegraphicVoucher GROUP BY LTRIM(RTRIM(ReferenceNumber))),
gl AS (    -- bank credit on the voucher's payment tickets (bank accounts 1010201xx / 1010202xx)
    SELECT LTRIM(RTRIM(td.ReferenceNumber)) AS Ref, CAST(SUM(td.Credit - td.Debit) AS DECIMAL(18,2)) AS BankCr
    FROM dbo.TicketDetails td
    INNER JOIN dbo.TicketMaster tm ON tm.TicketNumber = td.TicketNumber AND tm.BranchCode = td.BranchCode
    WHERE (td.AccountCode LIKE '1010201__' OR td.AccountCode LIKE '1010202__')
      AND tm.Mnemonic IN ('SINGLE-PAY', 'EXP-ACCRUAL-PAY', 'VOUCHER-MANUAL', 'PV-AP', 'PV-AP-OVERPAY', 'PV-AP-OVERPAYEXP', 'PV-AP-ADVAPPLIED', 'EXP-OVERPAY-HO')
    GROUP BY LTRIM(RTRIM(td.ReferenceNumber))),
rc AS (
    SELECT r.ReferenceNo AS VoucherID, r.AccountCode, CAST(SUM(r.Amount) AS DECIMAL(18,2)) AS ReconAmt
    FROM dbo.BankStatementRecon r WHERE r.ItemType = 'OC' AND r.SourceModule = 'AP-PAYMENT'
    GROUP BY r.ReferenceNo, r.AccountCode),
v AS (
    SELECT tp.Ref, tp.SupplierID, tp.VType, tp.Screen, pd.VoucherID, pd.Cash, pd.nBranches, vc.VAmt, gl.BankCr, rc.ReconAmt
    FROM tp
    LEFT JOIN pd ON pd.Ref = tp.Ref
    LEFT JOIN vc ON vc.Ref = tp.Ref AND vc.VType = tp.VType
    LEFT JOIN gl ON gl.Ref = tp.Ref
    LEFT JOIN rc ON rc.VoucherID = CAST(pd.VoucherID AS VARCHAR(30)) AND rc.AccountCode = pd.BankAcct
    WHERE tp.IsErr = 0 AND ISNULL(vc.IsErr, 0) = 0
      AND NOT EXISTS (SELECT 1 FROM rev WHERE rev.Ref = tp.Ref AND rev.SupplierID = tp.SupplierID)),
apt AS (   -- AP tickets: per ticket number (all branches); cross-branch expenses per expense reference
    SELECT CAST(td.TicketNumber AS VARCHAR(50)) AS Ref, MAX(m.Mnemonic) AS Mnemonic, CAST(SUM(td.Debit) - SUM(td.Credit) AS DECIMAL(18,2)) AS Gap,
           MAX(LTRIM(RTRIM(td.ReferenceNumber))) AS PostRef
    FROM dbo.TicketDetails td
    INNER JOIN (SELECT DISTINCT TicketNumber, Mnemonic FROM dbo.TicketMaster
                WHERE Mnemonic IN ('SINGLE', 'SINGLE-PAY', 'EXP-ACCRUAL-PAY', 'EXP-MANUAL-MULTI-BR', 'VOUCHER-MANUAL', 'PV-AP', 'PV-AP-OVERPAY',
                                   'PV-AP-OVERPAYEXP', 'PV-AP-ADVAPPLIED', 'EXP-OVERPAY-HO', 'CASH ADVANCE')) m ON m.TicketNumber = td.TicketNumber
    GROUP BY td.TicketNumber
    UNION ALL
    SELECT 'ref ' + LTRIM(RTRIM(td.ReferenceNumber)), 'EXP-MANUAL-CROSS-BR', CAST(SUM(td.Debit) - SUM(td.Credit) AS DECIMAL(18,2)), LTRIM(RTRIM(td.ReferenceNumber))
    FROM dbo.TicketDetails td
    WHERE td.TicketNumber IN (SELECT TicketNumber FROM dbo.TicketMaster WHERE Mnemonic = 'EXP-MANUAL-CROSS-BR')
    GROUP BY LTRIM(RTRIM(td.ReferenceNumber))),
led AS (   -- NULL amounts are findings in their own right (a NULL made the row math NULL and the row escaped: [72])
    SELECT s.SupplierKey, s.TRN_SEQ_NO, ISNULL(s.BeginningBalance, 0) AS BeginningBalance, ISNULL(s.Debit, 0) AS Debit,
           ISNULL(s.Credit, 0) AS Credit, ISNULL(s.EndingBalance, 0) AS EndingBalance,
           CASE WHEN s.BeginningBalance IS NULL OR s.Debit IS NULL OR s.Credit IS NULL OR s.EndingBalance IS NULL THEN 1 ELSE 0 END AS HasNull,
           LAG(ISNULL(s.EndingBalance, 0)) OVER (PARTITION BY s.SupplierKey ORDER BY s.TRN_SEQ_NO) AS PrevEnd,
           ROW_NUMBER() OVER (PARTITION BY s.SupplierKey ORDER BY s.TRN_SEQ_NO) AS rn
    FROM dbo.SupplierLedger s),
lastEnd AS (
    SELECT SupplierKey, EndingBalance FROM (SELECT SupplierKey, EndingBalance, ROW_NUMBER() OVER (PARTITION BY SupplierKey ORDER BY TRN_SEQ_NO DESC) AS rn
                                            FROM dbo.SupplierLedger) x WHERE rn = 1),
inv AS (   -- open invoices vs their supplier-ledger net
    SELECT 'EXPENSE' AS InvType, es.SupplierID, es.InvoiceNo, LTRIM(RTRIM(es.ReferenceNumber)) AS PostRef, es.Status,
           CAST(es.Balance AS DECIMAL(18,2)) AS Balance,
           CAST((SELECT SUM(ISNULL(s.Credit, 0) - ISNULL(s.Debit, 0)) FROM dbo.SupplierLedger s WHERE s.SupplierKey = es.SupplierID AND s.InvoiceNo = es.InvoiceNo
                    AND (s.BatchReferenceID = es.BatchReferenceID OR s.BatchReferenceID IS NULL)) AS DECIMAL(18,2)) AS LedgerNet,
           (SELECT COUNT(*) FROM dbo.SupplierLedger s WHERE s.SupplierKey = es.SupplierID AND s.ReferenceNumber = es.ReferenceNumber) AS nLedgerByRef,
           CAST((SELECT SUM(m.Balance) FROM dbo.ExpenseMaster m WHERE m.SupplierID = es.SupplierID AND m.InvoiceNo = es.InvoiceNo
                    AND m.BatchReferenceID = es.BatchReferenceID) AS DECIMAL(18,2)) AS LineBalance,
           CASE WHEN es.AddedBy = 'system' OR LTRIM(RTRIM(es.ReferenceNumber)) = '1' THEN 1 ELSE 0 END AS IsBF,   -- balance-forward load
           CAST(es.Amount AS DECIMAL(18,2)) AS InvAmount
    FROM dbo.ExpenseSummary es
    UNION ALL
    SELECT 'PURCHASE', a.SupplierID, a.InvoiceNo, LTRIM(RTRIM(a.ReferenceNumber)), a.PayStatus,
           CAST(a.Balance AS DECIMAL(18,2)),
           CAST(ISNULL((SELECT SUM(ISNULL(s.Credit, 0) - ISNULL(s.Debit, 0)) FROM dbo.SupplierLedger s WHERE s.SupplierKey = a.SupplierID AND s.InvoiceNo = a.InvoiceNo), 0)
                - ISNULL((SELECT SUM(es.Balance) FROM dbo.ExpenseSummary es WHERE es.SupplierID = a.SupplierID AND es.InvoiceNo = a.InvoiceNo), 0) AS DECIMAL(18,2)),
           NULL, NULL, CASE WHEN a.AddedBy = 'system' THEN 1 ELSE 0 END, CAST(a.ActualCost AS DECIMAL(18,2))
    FROM dbo.APACCOUNTS a WHERE a.ActualCost <> 0),
credit AS (
    SELECT p.SupplierID,
           CAST(SUM(CASE WHEN p.PaymentType = 'OVERPAY' THEN p.Amount WHEN p.PaymentType = 'ADVANCEAPPLIED' THEN -p.Amount ELSE 0 END) AS DECIMAL(18,2)) AS Credit
    FROM dbo.APPaymentDetails p
    WHERE p.PaymentType IN ('OVERPAY', 'ADVANCEAPPLIED')
      AND NOT EXISTS (SELECT 1 FROM rev WHERE rev.Ref = LTRIM(RTRIM(p.ReferenceNumber)) AND rev.SupplierID = p.SupplierID)
    GROUP BY p.SupplierID)

-- AP-VOUCHER-LEGS
SELECT CAST('AP-VOUCHER-LEGS' AS VARCHAR(50)) AS ExceptionCode,
       CAST(v.Ref AS VARCHAR(50)) AS Ref, CAST(v.VoucherID AS VARCHAR(30)) AS VoucherID, CAST(v.SupplierID AS VARCHAR(50)) AS SupplierID,
       CAST(NULL AS VARCHAR(150)) AS InvoiceNo,
       v.Screen AS Expected, v.Cash AS Actual, CAST(ISNULL(v.Cash, 0) - ISNULL(v.Screen, 0) AS DECIMAL(18,2)) AS Difference,
       CAST((SELECT MAX(d) FROM (VALUES (CASE WHEN v.Cash IS NOT NULL THEN ABS(v.Cash - ISNULL(v.Screen, 0)) ELSE 0 END),
                                        (ABS(ISNULL(v.VAmt, 0) - ISNULL(v.BankCr, 0))), (ABS(ISNULL(v.ReconAmt, v.VAmt) - ISNULL(v.VAmt, 0)))) x(d)) AS DECIMAL(18,2)) AS ValueAtRisk,
       CAST(v.VType + ' voucher: screen ' + ISNULL(FORMAT(v.Screen, 'N2'), '-') + ' | legs (cheque pays) ' + ISNULL(FORMAT(v.Cash, 'N2'), '-')
            + ' | voucher ' + ISNULL(FORMAT(v.VAmt, 'N2'), '-') + ' | GL bank ' + ISNULL(FORMAT(v.BankCr, 'N2'), '-')
            + ' | recon ' + ISNULL(FORMAT(v.ReconAmt, 'N2'), 'none') + ' | branches ' + CAST(ISNULL(v.nBranches, 0) AS VARCHAR(10)) AS VARCHAR(400)) AS Detail,
       CAST(CASE WHEN v.Cash > v.Screen AND v.Cash - v.Screen <= 1.00 AND v.nBranches > 1
                 THEN 'Multi-branch split bug (posted before the [61] fix of 2026-10-12): the last branch leg is a few cents high. Correct the leg, ticket, ledger, cheque and recon item like [63] / [66], after confirming the cheque was written for the screen total.'
                 WHEN v.VAmt IS NULL THEN 'No voucher row (CheckVoucher / CashVoucher / TelegraphicVoucher) for this payment reference.'
                 WHEN v.BankCr IS NULL THEN 'No bank credit found on the payment tickets of this reference.'
                 ELSE 'Compare the payment legs, voucher, GL bank credit and bank-recon item of this reference.' END AS VARCHAR(400)) AS Hint
FROM v
-- legs = screen (when there are legs; the split bug), voucher = GL bank credit, recon item = voucher (when there is one).
-- The voucher is not compared with the legs: manual GL lines (telegraphic / cheque with manual lines) add to it legitimately.
WHERE (v.Cash IS NOT NULL AND ABS(v.Cash - ISNULL(v.Screen, -1)) >= 0.005)
   OR v.VAmt IS NULL
   OR ABS(v.VAmt - ISNULL(v.BankCr, -1)) >= 0.005
   OR (v.ReconAmt IS NOT NULL AND ABS(v.ReconAmt - v.VAmt) >= 0.005)

UNION ALL
-- AP-TICKET-UNBALANCED
SELECT 'AP-TICKET-UNBALANCED', apt.Ref, NULL, NULL, NULL, 0, apt.Gap, apt.Gap, ABS(apt.Gap),
       apt.Mnemonic + ' ticket(s) of reference ' + ISNULL(apt.PostRef, '-') + ': DR - CR = ' + FORMAT(apt.Gap, 'N2'),
       CASE WHEN apt.Mnemonic = 'EXP-MANUAL-CROSS-BR' THEN 'Cross-branch expense: its per-branch tickets together must balance. Check the branch lines of the reference.'
            ELSE 'Check the mnemonic''s JournalEntryMapping rows and the amounts passed to the posting proc (MIRROR / missing amount types post at GROSS).' END
FROM apt WHERE ABS(apt.Gap) >= 0.005

UNION ALL
-- AP-SUPPLIER-LEDGER-CHAIN
SELECT 'AP-SUPPLIER-LEDGER-CHAIN', led.SupplierKey + ' seq ' + CAST(led.TRN_SEQ_NO AS VARCHAR(20)), NULL, led.SupplierKey, NULL,
       CAST(CASE WHEN ABS(led.EndingBalance - (led.BeginningBalance + led.Credit - led.Debit)) >= 0.005 THEN led.BeginningBalance + led.Credit - led.Debit ELSE led.PrevEnd END AS DECIMAL(18,2)),
       CAST(CASE WHEN ABS(led.EndingBalance - (led.BeginningBalance + led.Credit - led.Debit)) >= 0.005 THEN led.EndingBalance ELSE led.BeginningBalance END AS DECIMAL(18,2)),
       CAST(CASE WHEN ABS(led.EndingBalance - (led.BeginningBalance + led.Credit - led.Debit)) >= 0.005 THEN led.EndingBalance - (led.BeginningBalance + led.Credit - led.Debit)
                 ELSE led.BeginningBalance - led.PrevEnd END AS DECIMAL(18,2)),
       NULL,
       CASE WHEN led.HasNull = 1 THEN 'a NULL amount (Beginning / Debit / Credit / Ending)'
            WHEN ABS(led.EndingBalance - (led.BeginningBalance + led.Credit - led.Debit)) >= 0.005 THEN 'Ending <> Beginning + Credit - Debit'
            WHEN led.rn = 1 THEN 'first row does not start at 0' ELSE 'Beginning <> the previous row''s Ending' END,
       CASE WHEN led.HasNull = 1 THEN 'A NULL amount: the posting computed a sum over no rows (e.g. an expense with no payable line, fixed in spu_PostExpenseV2 by [72]). Set it to 0.'
            ELSE 'trg_SupplierLedger_Recalc ([17]) recomputes the whole chain of a supplier on any change: an UPDATE of one row of this supplier heals it. Find what wrote the row with the trigger disabled.' END
FROM led
WHERE led.HasNull = 1
   OR ABS(led.EndingBalance - (led.BeginningBalance + led.Credit - led.Debit)) >= 0.005
   OR (led.rn > 1 AND ABS(led.BeginningBalance - led.PrevEnd) >= 0.005)
   OR (led.rn = 1 AND ABS(led.BeginningBalance) >= 0.005)

UNION ALL
-- AP-ACCOUNT-VS-LEDGER
SELECT 'AP-ACCOUNT-VS-LEDGER', a.SupplierKey, NULL, a.SupplierKey, NULL,
       CAST(ISNULL(le.EndingBalance, 0) AS DECIMAL(18,2)), CAST(a.AccountBalance AS DECIMAL(18,2)),
       CAST(a.AccountBalance - ISNULL(le.EndingBalance, 0) AS DECIMAL(18,2)), CAST(ABS(a.AccountBalance - ISNULL(le.EndingBalance, 0)) AS DECIMAL(18,2)),
       'supplier account balance vs its last ledger Ending' + CASE WHEN le.SupplierKey IS NULL THEN ' (no ledger rows)' ELSE '' END,
       'The account row may have been created after the ledger rows (sp_TrgInsertSupplierInfo at 0), so the trigger had nothing to update. Touch one ledger row of the supplier to recompute.'
FROM dbo.SupplierAccounts a LEFT JOIN lastEnd le ON le.SupplierKey = a.SupplierKey
WHERE ABS(a.AccountBalance - ISNULL(le.EndingBalance, 0)) >= 0.005

UNION ALL
-- AP-INVOICE-VS-LEDGER
SELECT 'AP-INVOICE-VS-LEDGER', inv.InvType + ' ' + ISNULL(inv.PostRef, ''), NULL, inv.SupplierID, inv.InvoiceNo,
       inv.LedgerNet, inv.Balance, CAST(ISNULL(inv.Balance, 0) - ISNULL(inv.LedgerNet, 0) AS DECIMAL(18,2)),
       CAST(CASE WHEN inv.Balance IS NULL THEN ISNULL(inv.LineBalance, inv.InvAmount) ELSE ABS(inv.Balance - ISNULL(inv.LedgerNet, 0)) END AS DECIMAL(18,2)),
       inv.InvType + ' invoice (' + ISNULL(inv.Status, '-') + '): balance ' + ISNULL(FORMAT(inv.Balance, 'N2'), 'NULL') + ' vs supplier ledger ' + ISNULL(FORMAT(inv.LedgerNet, 'N2'), 'none')
           + CASE WHEN inv.LineBalance IS NOT NULL THEN ' | branch lines ' + FORMAT(inv.LineBalance, 'N2') ELSE '' END,
       CASE WHEN inv.Balance IS NULL THEN 'The invoice balance is NULL. If its posting has no payable line (a reclass keyed on the expense screen) nothing is owed: set it to 0 as [72] does. Otherwise the payment screen (Balance > 0) cannot list it.'
            WHEN inv.LedgerNet IS NULL AND inv.nLedgerByRef > 0 THEN 'Its ledger row is under a different invoice no. (invoice no. edited after posting?).'
            WHEN inv.InvType = 'PURCHASE' AND inv.LedgerNet > inv.Balance + 0.005 AND ABS(inv.LedgerNet - 2 * inv.InvAmount) < 0.005
              THEN 'The purchase payment was posted to the supplier ledger as a credit (see AP-LEDGER-PAYMENT-SIDE): the ledger shows the invoice owed twice.'
            WHEN inv.IsBF = 1 AND ABS(ISNULL(inv.LedgerNet, 0)) < 0.005 AND inv.Balance > 0
              THEN 'Balance-forward invoice loaded at its invoice amount while the ledger holds the Peachtree balance (same pattern as the AR fix [43]).'
            WHEN inv.IsBF = 1
              THEN 'Balance-forward invoice: the invoice and its balance-forward row in the supplier ledger were loaded at different amounts. Compare both with the Peachtree list (accountant).'
            WHEN ABS(ISNULL(inv.Balance, 0) - ISNULL(inv.LedgerNet, 0)) <= 1.00
              THEN 'A few cents: usually the multi-branch split bug on its payment (see AP-VOUCHER-LEGS).'
            ELSE 'Compare the invoice''s posting, payments and reversals with its supplier-ledger rows.' END
FROM inv
WHERE inv.Balance IS NULL OR ABS(inv.Balance - ISNULL(inv.LedgerNet, 0)) >= 0.005

UNION ALL
-- AP-LEDGER-PAYMENT-SIDE
SELECT 'AP-LEDGER-PAYMENT-SIDE', s.SupplierKey + ' seq ' + CAST(s.TRN_SEQ_NO AS VARCHAR(20)), NULL, s.SupplierKey, s.InvoiceNo,
       0, CAST(s.Credit AS DECIMAL(18,2)), CAST(s.Credit AS DECIMAL(18,2)), CAST(2 * s.Credit AS DECIMAL(18,2)),
       s.TransCode + ' payment ref ' + ISNULL(LTRIM(RTRIM(s.ReferenceNumber)), '-') + ' posted as a credit of ' + FORMAT(s.Credit, 'N2') + ' (' + CONVERT(VARCHAR(10), s.TransactionDate, 120) + ')',
       'A payment reduces the payable: it must be a debit. The supplier balance is overstated by twice this amount. Check the ledger side of the posting proc for ' + s.TransCode + '.'
FROM dbo.SupplierLedger s
WHERE s.TransCode IN ('PV-AP', 'PV-MANUAL', 'SNGLE-PAY', 'EXP-ACCRUAL-PAY') AND s.Credit > 0.005 AND ISNULL(s.ErrorCorrectTag, 0) = 0
  AND NOT EXISTS (SELECT 1 FROM rev WHERE rev.Ref = LTRIM(RTRIM(s.ReferenceNumber)) AND rev.SupplierID = s.SupplierKey)

UNION ALL
-- AP-REVERSAL-NOT-RESTORED
SELECT 'AP-REVERSAL-NOT-RESTORED', rev.Ref, NULL, rev.SupplierID, NULL, 0, x.Net, x.Net, ABS(x.Net),
       'reversed voucher: its supplier-ledger rows net to ' + FORMAT(x.Net, 'N2') + ' (debit - credit)',
       'The reversal did not mirror every ledger row of the voucher; compare the payment rows with the reversal rows (ErrorCorrectTag).'
FROM rev
CROSS APPLY (SELECT CAST(SUM(s.Debit - s.Credit) AS DECIMAL(18,2)) AS Net FROM dbo.SupplierLedger s
             WHERE s.SupplierKey = rev.SupplierID AND LTRIM(RTRIM(s.ReferenceNumber)) = rev.Ref) x
WHERE ABS(ISNULL(x.Net, 0)) >= 0.005

UNION ALL
-- AP-CREDIT-NEGATIVE
SELECT 'AP-CREDIT-NEGATIVE', credit.SupplierID, NULL, credit.SupplierID, NULL, 0, credit.Credit, credit.Credit, ABS(credit.Credit),
       'supplier advance credit (overpay - advance applied, live vouchers) = ' + FORMAT(credit.Credit, 'N2'),
       'More advance was applied than was overpaid (rule 60514 / 60519). Check the advance-applied vouchers of this supplier and any reversal order.'
FROM credit WHERE credit.Credit < -0.005

UNION ALL
-- AP-STATUS-VS-BALANCE
SELECT 'AP-STATUS-VS-BALANCE', 'EXPENSE ' + LTRIM(RTRIM(es.ReferenceNumber)), NULL, es.SupplierID, es.InvoiceNo,
       NULL, CAST(es.Balance AS DECIMAL(18,2)), NULL, CAST(ABS(es.Balance) AS DECIMAL(18,2)),
       'expense invoice ' + ISNULL(es.Status, '-') + ' with balance ' + FORMAT(es.Balance, 'N2') + ' (amount ' + FORMAT(es.Amount, 'N2') + ')',
       CASE WHEN es.Balance < -0.005 THEN 'Negative balance: paid more than the payable (an overpay must go to the OverPay column).'
            WHEN es.Status = 'FULLYPAID' THEN 'Marked FULLYPAID but a balance is left.'
            WHEN es.InvoiceNo LIKE '%REVERSAL%' THEN 'A hand-made "-REVERSAL" invoice with nothing to pay: reverse the original expense in the system instead.'
            ELSE 'Balance 0 but not FULLYPAID.' END
FROM dbo.ExpenseSummary es
WHERE es.Balance IS NOT NULL AND (ISNULL(es.Status, '') <> 'CANCELLED' OR ABS(es.Balance) >= 0.005)   -- [96] a reversed expense owes 0 by design
  AND ((es.Status = 'FULLYPAID' AND ABS(es.Balance) >= 0.005) OR es.Balance < -0.005
       -- balance 0 but not FULLYPAID: only when there was a payable (a ledger credit); an expense that liquidates an
       -- advance (e.g. a broker's) never creates one and stays POSTED at 0 by design
       OR (es.Status <> 'FULLYPAID' AND ABS(es.Balance) < 0.005
           AND EXISTS (SELECT 1 FROM dbo.SupplierLedger s WHERE s.SupplierKey = es.SupplierID AND s.InvoiceNo = es.InvoiceNo AND s.Credit > 0.005)))
UNION ALL
SELECT 'AP-STATUS-VS-BALANCE', 'PURCHASE ' + CAST(a.SequenceNo AS VARCHAR(20)), NULL, a.SupplierID, a.InvoiceNo,
       NULL, CAST(a.Balance AS DECIMAL(18,2)), NULL, CAST(ABS(a.Balance) AS DECIMAL(18,2)),
       'purchase invoice ' + ISNULL(a.PayStatus, '-') + ' with balance ' + FORMAT(a.Balance, 'N2') + ' (cost ' + FORMAT(a.ActualCost, 'N2') + ')',
       CASE WHEN a.Balance < -0.005 THEN 'Negative balance: paid more than the payable.'
            WHEN a.PayStatus = 'FULLYPAID' THEN 'Marked FULLYPAID but a balance is left.' ELSE 'Balance 0 but not FULLYPAID.' END
FROM dbo.APACCOUNTS a
WHERE a.ActualCost <> 0
  AND ((a.PayStatus = 'FULLYPAID' AND ABS(a.Balance) >= 0.005) OR a.Balance < -0.005
       OR (a.PayStatus <> 'FULLYPAID' AND ABS(a.Balance) < 0.005
           AND EXISTS (SELECT 1 FROM dbo.SupplierLedger s WHERE s.SupplierKey = a.SupplierID AND s.InvoiceNo = a.InvoiceNo AND s.Credit > 0.005)))

UNION ALL
-- AP-CHEQUE-REUSED
SELECT 'AP-CHEQUE-REUSED', c.CreditGLCode + ' / ' + c.CheckNo, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       'cheque no. ' + c.CheckNo + ' on bank ' + c.CreditGLCode + ': ' + CAST(c.nLive AS VARCHAR(10)) + ' live voucher(s) and ' + CAST(c.nCancelled AS VARCHAR(10)) + ' cancelled-cheque record(s)',
       'A cancelled cheque uses up its number ([55]); the live voucher should carry a new cheque no. Check which cheque the bank actually cleared.'
FROM (SELECT cv.CreditGLCode, LTRIM(RTRIM(cv.CheckNo)) AS CheckNo,
             SUM(CASE WHEN ISNULL(cv.isErrorCorrect, 0) = 0 AND ISNULL(cv.PaidTo, '') <> 'CANCELLED' THEN 1 ELSE 0 END) AS nLive,
             SUM(CASE WHEN ISNULL(cv.PaidTo, '') = 'CANCELLED' THEN 1 ELSE 0 END) AS nCancelled
      FROM dbo.CheckVoucher cv WHERE ISNULL(LTRIM(RTRIM(cv.CheckNo)), '') <> ''
      GROUP BY cv.CreditGLCode, LTRIM(RTRIM(cv.CheckNo))) c
WHERE c.nLive >= 1 AND c.nCancelled >= 1;
GO

CREATE PROCEDURE dbo.sp_rpt_exc_AP_Summary
    @DateFrom date = NULL,
    @DateTo   date = NULL,
    @AsOfDate date = NULL
AS
/*  Read-only. Exception Center AP provider, Summary: one row per AP code (Findings 0 when healthy).
    Contract (portal handoff 2026-10-13): ExceptionCode varchar(50), Findings int, ValueAtRisk decimal(18,2) NULL.
    INTEGRITY checks: evaluated as of now; the dates are accepted for the contract and not used. */
BEGIN
    SET NOCOUNT ON;
    DECLARE @Codes TABLE (ExceptionCode VARCHAR(50) PRIMARY KEY, Priced BIT);
    INSERT INTO @Codes VALUES ('AP-VOUCHER-LEGS', 1), ('AP-TICKET-UNBALANCED', 1), ('AP-SUPPLIER-LEDGER-CHAIN', 0), ('AP-ACCOUNT-VS-LEDGER', 1),
                              ('AP-INVOICE-VS-LEDGER', 1), ('AP-LEDGER-PAYMENT-SIDE', 1), ('AP-REVERSAL-NOT-RESTORED', 1), ('AP-CREDIT-NEGATIVE', 1),
                              ('AP-STATUS-VS-BALANCE', 1), ('AP-CHEQUE-REUSED', 0);
    SELECT c.ExceptionCode,
           CAST(ISNULL(f.Findings, 0) AS INT) AS Findings,
           CAST(CASE WHEN c.Priced = 1 THEN f.ValueAtRisk END AS DECIMAL(18,2)) AS ValueAtRisk
    FROM @Codes c
    LEFT JOIN (SELECT ExceptionCode, COUNT(*) AS Findings, SUM(ValueAtRisk) AS ValueAtRisk
               FROM dbo.fn_rpt_exc_AP_Findings() GROUP BY ExceptionCode) f ON f.ExceptionCode = c.ExceptionCode
    ORDER BY c.ExceptionCode;
END
GO

CREATE PROCEDURE dbo.sp_rpt_exc_AP_Detail
    @ExceptionCode varchar(50),
    @DateFrom      date = NULL,
    @DateTo        date = NULL,
    @AsOfDate      date = NULL
AS
/*  Read-only. Exception Center AP provider, Detail: the findings of one AP code, TOP (500) + TotalMatchCount, with a Hint.
    An unknown code raises an error (the portal shows it as a 400). */
BEGIN
    SET NOCOUNT ON;
    IF @ExceptionCode NOT IN ('AP-VOUCHER-LEGS', 'AP-TICKET-UNBALANCED', 'AP-SUPPLIER-LEDGER-CHAIN', 'AP-ACCOUNT-VS-LEDGER', 'AP-INVOICE-VS-LEDGER',
                              'AP-LEDGER-PAYMENT-SIDE', 'AP-REVERSAL-NOT-RESTORED', 'AP-CREDIT-NEGATIVE', 'AP-STATUS-VS-BALANCE', 'AP-CHEQUE-REUSED')
    BEGIN
        RAISERROR('sp_rpt_exc_AP_Detail: unknown exception code %s.', 16, 1, @ExceptionCode);
        RETURN;
    END

    SELECT TOP (500)
           f.Ref, f.VoucherID AS Voucher, f.SupplierID AS Supplier,
           (SELECT TOP 1 a.SupplierName FROM dbo.SupplierAccounts a WHERE a.SupplierKey = f.SupplierID) AS SupplierName,
           f.InvoiceNo AS Invoice, f.Expected, f.Actual, f.Difference, f.ValueAtRisk, f.Detail, f.Hint,
           COUNT(*) OVER () AS TotalMatchCount
    FROM dbo.fn_rpt_exc_AP_Findings() f
    WHERE f.ExceptionCode = @ExceptionCode
    ORDER BY f.ValueAtRisk DESC, f.Ref;
END
GO

SET NOEXEC OFF;
GO
