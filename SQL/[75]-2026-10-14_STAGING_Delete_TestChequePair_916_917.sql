/* ================================================================
   [75] 2026-10-14 - STAGING ONLY: delete the test cheque pair 916 / 917 (data only)
   ================================================================
   User 2026-10-14: "delete the 916 / 917 test pair on staging".
   Test data keyed on STAGING 2026-10-13 by ADMINISTRATOR (found by the [70] check AP-CHEQUE-REUSED; [74] now refuses it):
     voucher 916 / ref 38651 - cancelled-cheque record of cheque 2384570 (BDO 101020101), supplier 000075 CANCELLED, 0.00
     voucher 917 / ref 38657 - payment 29,660.71 on the same cheque 2384570 to ALPA (000142) for test invoice SI#00224
                               (expense 38654, 6 branches, MULTI-MANUAL)
   (Cheque 2384570 is a real PRODUCTION cheque, voucher 921; nothing here runs on PRODUCTION.)

   Deleted (every row was found by a scan of all reference columns, 2026-10-14):
     916: CheckVoucher, CheckVoucherCancelled, CancelledChequeEditLog (if any)
     917: CheckVoucher, TransactionPaymentAP, APPaymentDetails (6), TicketMaster (6) + TicketDetails (12) of tickets 20656-20661,
          SupplierLedger (6; trg_SupplierLedger_Recalc re-chains supplier 000142), BankStatementRecon OC (open, uncleared)
   Put back as before the payment (the state sp_PostExpenseManualMultiBranch leaves an unpaid invoice in):
     ExpenseSummary 38654: Status POSTED, Balance 29,660.71, AmountPaid 0
     ExpenseMaster lines of 38654: Status UNPAID, Balance = Amount, AmountPaid 0
   The test invoice 38654 itself stays (not asked); it is open again for 29,660.71.

   Refuses unless the database is CORECSJFC2026_STAGING and every row is as listed (59979). One transaction with a
   post-check (59980). Backups: TestPair916917_Backup_20261014_* (the rows before).
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

IF DB_NAME() <> 'CORECSJFC2026_STAGING'
    THROW 59979, 'This cleanup is for STAGING (CORECSJFC2026_STAGING) only; nothing was changed.', 1;
IF OBJECT_ID('dbo.TestPair916917_Backup_20261014_CheckVoucher', 'U') IS NOT NULL
    THROW 59979, 'This script has been run here before (TestPair916917_Backup_20261014_CheckVoucher exists).', 1;

BEGIN TRANSACTION;

DECLARE @Ref916 VARCHAR(10) = '38651', @Ref917 VARCHAR(10) = '38657', @InvRef VARCHAR(10) = '38654',
        @Supplier VARCHAR(10) = '000142', @Invoice VARCHAR(150) = 'SI#00224', @Batch BIGINT = 2338, @Paid DECIMAL(18,2) = 29660.71;

-- every value as found on 2026-10-14, or nothing changes
DECLARE @Problem VARCHAR(300) =
    CASE WHEN (SELECT COUNT(*) FROM dbo.CheckVoucher WHERE VoucherID = '916' AND ReferenceNumber = @Ref916 AND PaidTo = 'CANCELLED'
                AND LTRIM(RTRIM(CheckNo)) = '2384570' AND ISNULL(Amount, 0) = 0 AND isErrorCorrect = 1) <> 1 THEN 'voucher 916 not as expected'
         WHEN (SELECT COUNT(*) FROM dbo.CheckVoucher WHERE VoucherID = '917' AND ReferenceNumber = @Ref917 AND SupplierID = @Supplier
                AND LTRIM(RTRIM(CheckNo)) = '2384570' AND Amount = @Paid AND isErrorCorrect = 0) <> 1 THEN 'voucher 917 not as expected'
         WHEN (SELECT COUNT(*) FROM dbo.CheckVoucher WHERE ReferenceNumber IN (@Ref916, @Ref917)) <> 2 THEN 'more CheckVoucher rows than expected'
         WHEN (SELECT COUNT(*) FROM dbo.APPaymentDetails WHERE ReferenceNumber = @Ref917) <> 6
           OR (SELECT SUM(Amount) FROM dbo.APPaymentDetails WHERE ReferenceNumber = @Ref917) <> @Paid
           OR EXISTS (SELECT 1 FROM dbo.APPaymentDetails WHERE ReferenceNumber = @Ref917
                      AND (SupplierID <> @Supplier OR InvoiceNo <> @Invoice OR BatchReferenceID <> @Batch OR PaymentType <> 'EXPENSE PAYMENT'))
              THEN 'payment lines of 917 not as expected'
         WHEN (SELECT COUNT(*) FROM dbo.TransactionPaymentAP WHERE ReferenceNumber = TRY_CAST(@Ref917 AS INT)) <> 1 THEN 'TransactionPaymentAP of 917 not as expected'
         WHEN (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber = @Ref917) <> 6
           OR (SELECT COUNT(*) FROM dbo.TicketDetails WHERE ReferenceNumber = @Ref917) <> 12
           OR (SELECT SUM(Debit) FROM dbo.TicketDetails WHERE ReferenceNumber = @Ref917) <> @Paid
           OR (SELECT SUM(Credit) FROM dbo.TicketDetails WHERE ReferenceNumber = @Ref917) <> @Paid
           OR EXISTS (SELECT 1 FROM dbo.TicketMaster WHERE ReferenceNumber = @Ref917 AND Mnemonic <> 'EXP-ACCRUAL-PAY')
              THEN 'tickets of 917 not as expected'
         WHEN (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber = @Ref916) + (SELECT COUNT(*) FROM dbo.TicketDetails WHERE ReferenceNumber = @Ref916) <> 0
              THEN '916 has tickets'
         WHEN (SELECT COUNT(*) FROM dbo.SupplierLedger WHERE ReferenceNumber = @Ref917 AND SupplierKey = @Supplier AND InvoiceNo = @Invoice) <> 6
           OR (SELECT COUNT(*) FROM dbo.SupplierLedger WHERE ReferenceNumber IN (@Ref916, @Ref917)) <> 6
           OR (SELECT SUM(Debit) - SUM(Credit) FROM dbo.SupplierLedger WHERE ReferenceNumber = @Ref917) <> @Paid
              THEN 'supplier-ledger rows of 917 not as expected'
         WHEN (SELECT COUNT(*) FROM dbo.BankStatementRecon WHERE ReferenceNo = '917' AND ItemType = 'OC' AND SourceModule = 'AP-PAYMENT'
                AND Amount = @Paid AND ISNULL(IsResolved, 0) = 0) <> 1
           OR (SELECT COUNT(*) FROM dbo.BankStatementRecon WHERE SourceRef IN (@Ref916, @Ref917) OR ReferenceNo IN ('916', '917')) <> 1
              THEN 'bank-recon item of 917 not as expected (or already cleared)'
         WHEN EXISTS (SELECT 1 FROM dbo.PaymentReversalAudit WHERE CAST(ReferenceNumber AS VARCHAR(10)) IN (@Ref916, @Ref917)) THEN '917 was reversed'
         WHEN (SELECT COUNT(*) FROM dbo.ExpenseSummary WHERE ReferenceNumber = @InvRef AND SupplierID = @Supplier AND InvoiceNo = @Invoice
                AND BatchReferenceID = @Batch AND Status = 'FULLYPAID' AND Balance = 0 AND AmountPaid = @Paid
                AND ISNULL(EWTWithheld, 0) = 0 AND ISNULL(DiscountWithheld, 0) = 0 AND ISNULL(OffsetWithheld, 0) = 0) <> 1
              THEN 'invoice 38654 not as expected'
         WHEN (SELECT COUNT(*) FROM dbo.APPaymentDetails WHERE SupplierID = @Supplier AND InvoiceNo = @Invoice AND ReferenceNumber <> @Ref917) <> 0
              THEN 'another voucher also paid the invoice'
         WHEN (SELECT COUNT(*) FROM dbo.ExpenseMaster WHERE SupplierID = @Supplier AND InvoiceNo = @Invoice AND BatchReferenceID = @Batch) <> 6
           OR EXISTS (SELECT 1 FROM dbo.ExpenseMaster WHERE SupplierID = @Supplier AND InvoiceNo = @Invoice AND BatchReferenceID = @Batch
                      AND (Status <> 'FULLYPAID' OR Balance <> 0 OR AmountPaid <> Amount))
              THEN 'invoice lines of 38654 not as expected'
         END;
IF @Problem IS NOT NULL
BEGIN
    ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(400) = N'Not as expected: ' + @Problem + N'; nothing was changed.';
    THROW 59979, @msg, 1;
END

-- backups (the rows before)
SELECT * INTO dbo.TestPair916917_Backup_20261014_CheckVoucher FROM dbo.CheckVoucher WHERE ReferenceNumber IN (@Ref916, @Ref917);
SELECT * INTO dbo.TestPair916917_Backup_20261014_CheckVoucherCancelled FROM dbo.CheckVoucherCancelled WHERE ReferenceNumber = @Ref916;
SELECT * INTO dbo.TestPair916917_Backup_20261014_TransactionPaymentAP FROM dbo.TransactionPaymentAP WHERE ReferenceNumber = TRY_CAST(@Ref917 AS INT);
SELECT * INTO dbo.TestPair916917_Backup_20261014_APPaymentDetails FROM dbo.APPaymentDetails WHERE ReferenceNumber = @Ref917;
SELECT * INTO dbo.TestPair916917_Backup_20261014_TicketMaster FROM dbo.TicketMaster WHERE ReferenceNumber = @Ref917;
SELECT * INTO dbo.TestPair916917_Backup_20261014_TicketDetails FROM dbo.TicketDetails WHERE ReferenceNumber = @Ref917;
SELECT * INTO dbo.TestPair916917_Backup_20261014_SupplierLedger FROM dbo.SupplierLedger WHERE ReferenceNumber = @Ref917;
SELECT * INTO dbo.TestPair916917_Backup_20261014_BankStatementRecon FROM dbo.BankStatementRecon WHERE ReferenceNo = '917' AND ItemType = 'OC' AND SourceModule = 'AP-PAYMENT';
SELECT * INTO dbo.TestPair916917_Backup_20261014_ExpenseSummary FROM dbo.ExpenseSummary WHERE ReferenceNumber = @InvRef;
SELECT * INTO dbo.TestPair916917_Backup_20261014_ExpenseMaster FROM dbo.ExpenseMaster WHERE SupplierID = @Supplier AND InvoiceNo = @Invoice AND BatchReferenceID = @Batch;

-- 916: the cancelled-cheque record
IF OBJECT_ID('dbo.CancelledChequeEditLog', 'U') IS NOT NULL
    DELETE FROM dbo.CancelledChequeEditLog WHERE CAST(VoucherID AS VARCHAR(10)) = '916' AND ReferenceNumber = @Ref916;
DELETE FROM dbo.CheckVoucherCancelled WHERE ReferenceNumber = @Ref916 AND VoucherType = 'CANCELLED CHEQUE';
DELETE FROM dbo.CheckVoucher WHERE VoucherID = '916' AND ReferenceNumber = @Ref916;

-- 917: the payment
DELETE FROM dbo.BankStatementRecon WHERE ReferenceNo = '917' AND ItemType = 'OC' AND SourceModule = 'AP-PAYMENT';
DELETE FROM dbo.SupplierLedger WHERE ReferenceNumber = @Ref917 AND SupplierKey = @Supplier;
DELETE FROM dbo.TicketDetails WHERE ReferenceNumber = @Ref917;
DELETE FROM dbo.TicketMaster WHERE ReferenceNumber = @Ref917;
DELETE FROM dbo.APPaymentDetails WHERE ReferenceNumber = @Ref917;
DELETE FROM dbo.TransactionPaymentAP WHERE ReferenceNumber = TRY_CAST(@Ref917 AS INT);
DELETE FROM dbo.CheckVoucher WHERE VoucherID = '917' AND ReferenceNumber = @Ref917;

-- the invoice back to unpaid
UPDATE dbo.ExpenseSummary
SET Status = 'POSTED', Balance = Balance + @Paid, AmountPaid = AmountPaid - @Paid,
    UpdatedBy = 'CLEANUP [75]', DateTimeUpdated = GETDATE()
WHERE ReferenceNumber = @InvRef AND SupplierID = @Supplier AND InvoiceNo = @Invoice AND BatchReferenceID = @Batch;
UPDATE dbo.ExpenseMaster
SET Status = 'UNPAID', Balance = Amount, AmountPaid = 0
WHERE SupplierID = @Supplier AND InvoiceNo = @Invoice AND BatchReferenceID = @Batch;

-- post-check: nothing of 916 / 917 left; invoice open for the full net; supplier account = its ledger = the open invoice
IF (SELECT COUNT(*) FROM dbo.CheckVoucher WHERE ReferenceNumber IN (@Ref916, @Ref917)) <> 0
   OR (SELECT COUNT(*) FROM dbo.CheckVoucherCancelled WHERE ReferenceNumber = @Ref916) <> 0
   OR (SELECT COUNT(*) FROM dbo.APPaymentDetails WHERE ReferenceNumber = @Ref917) <> 0
   OR (SELECT COUNT(*) FROM dbo.TransactionPaymentAP WHERE ReferenceNumber = TRY_CAST(@Ref917 AS INT)) <> 0
   OR (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber = @Ref917) <> 0
   OR (SELECT COUNT(*) FROM dbo.TicketDetails WHERE ReferenceNumber = @Ref917) <> 0
   OR (SELECT COUNT(*) FROM dbo.SupplierLedger WHERE ReferenceNumber = @Ref917) <> 0
   OR (SELECT COUNT(*) FROM dbo.BankStatementRecon WHERE SourceRef IN (@Ref916, @Ref917) OR ReferenceNo IN ('916', '917')) <> 0
   OR (SELECT COUNT(*) FROM dbo.ExpenseSummary WHERE ReferenceNumber = @InvRef AND Status = 'POSTED' AND Balance = @Paid AND AmountPaid = 0) <> 1
   OR EXISTS (SELECT 1 FROM dbo.ExpenseMaster WHERE SupplierID = @Supplier AND InvoiceNo = @Invoice AND BatchReferenceID = @Batch
              AND (Status <> 'UNPAID' OR Balance <> Amount OR AmountPaid <> 0))
   OR (SELECT SUM(Credit) - SUM(Debit) FROM dbo.SupplierLedger WHERE SupplierKey = @Supplier AND InvoiceNo = @Invoice) <> @Paid
   OR (SELECT AccountBalance FROM dbo.SupplierAccounts WHERE SupplierKey = @Supplier)
      <> (SELECT SUM(Credit) - SUM(Debit) FROM dbo.SupplierLedger WHERE SupplierKey = @Supplier)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 59980, 'Post-check failed; nothing was changed.', 1;
END

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
SELECT e.ReferenceNumber, e.InvoiceNo, e.Status, e.Balance, e.AmountPaid,
       (SELECT AccountBalance FROM dbo.SupplierAccounts WHERE SupplierKey = @Supplier) AS Supplier000142Balance
FROM dbo.ExpenseSummary e WHERE e.ReferenceNumber = @InvRef;
PRINT 'Test pair 916 / 917 deleted (backups dbo.TestPair916917_Backup_20261014_*).';
