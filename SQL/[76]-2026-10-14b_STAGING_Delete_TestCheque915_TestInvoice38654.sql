/* ================================================================
   [76] 2026-10-14 - STAGING ONLY: delete test cancelled cheque 915 and test invoice 38654 (data only)
   ================================================================
   User 2026-10-14: "delete 915 and the test invoice 38654 too" (after [75] deleted the test pair 916 / 917).
   Test data keyed on STAGING 2026-10-13 by ADMINISTRATOR:
     voucher 915 / ref 38650 - cancelled-cheque record of cheque 2384568 (BDO 101020101), supplier 000075 CANCELLED, 0.00
     expense 38654           - ALPA (000142) SI#00224, batch 2338, MULTI-MANUAL, 30,200.00 (net 29,660.71 + EWT 539.29),
                               unpaid again since [75]; a copy of the real invoice 9680
   Deleted (every row found by a scan of all reference / batch / invoice / ticket columns, 2026-10-14):
     915:   CheckVoucher, CheckVoucherCancelled, CancelledChequeEditLog (if any)
     38654: ExpenseSummary (1), ExpenseMaster (6), ExpenseManualLines (8), TicketMaster (7) + TicketDetails (8) of ticket 20655,
            SupplierLedger (1; trg_SupplierLedger_Recalc re-chains supplier 000142)
   (The scan's ClientLedger / TransactionChargeSales hits are unrelated AR balance-forward rows that use 915 / 2338 as
   their own reference numbers; not touched.)

   Refuses unless the database is CORECSJFC2026_STAGING, the invoice is unpaid (no payment line, no recon item) and every
   row is as listed (59981). One transaction with a post-check (59982). Backups: TestCleanup_Backup_20261014_*.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

IF DB_NAME() <> 'CORECSJFC2026_STAGING'
    THROW 59981, 'This cleanup is for STAGING (CORECSJFC2026_STAGING) only; nothing was changed.', 1;
IF OBJECT_ID('dbo.TestCleanup_Backup_20261014_ExpenseSummary', 'U') IS NOT NULL
    THROW 59981, 'This script has been run here before (TestCleanup_Backup_20261014_ExpenseSummary exists).', 1;

BEGIN TRANSACTION;

DECLARE @Ref915 VARCHAR(10) = '38650', @InvRef VARCHAR(10) = '38654', @Supplier VARCHAR(10) = '000142',
        @Invoice VARCHAR(150) = 'SI#00224', @Batch BIGINT = 2338, @Ticket VARCHAR(20) = '20655', @Net DECIMAL(18,2) = 29660.71;

DECLARE @Problem VARCHAR(300) =
    CASE WHEN (SELECT COUNT(*) FROM dbo.CheckVoucher WHERE VoucherID = '915' AND ReferenceNumber = @Ref915 AND PaidTo = 'CANCELLED'
                AND LTRIM(RTRIM(CheckNo)) = '2384568' AND ISNULL(Amount, 0) = 0 AND isErrorCorrect = 1) <> 1
           OR (SELECT COUNT(*) FROM dbo.CheckVoucher WHERE ReferenceNumber = @Ref915) <> 1 THEN 'voucher 915 not as expected'
         WHEN (SELECT COUNT(*) FROM dbo.CheckVoucherCancelled WHERE ReferenceNumber = @Ref915 AND VoucherType = 'CANCELLED CHEQUE') <> 1
              THEN 'cancelled-cheque log of 915 not as expected'
         WHEN (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber = @Ref915) + (SELECT COUNT(*) FROM dbo.TicketDetails WHERE ReferenceNumber = @Ref915)
            + (SELECT COUNT(*) FROM dbo.SupplierLedger WHERE ReferenceNumber = @Ref915) <> 0 THEN '915 has GL / ledger rows'
         WHEN (SELECT COUNT(*) FROM dbo.ExpenseSummary WHERE ReferenceNumber = @InvRef AND SupplierID = @Supplier AND InvoiceNo = @Invoice
                AND BatchReferenceID = @Batch AND PostingMode = 'MULTI-MANUAL' AND Status = 'POSTED' AND Balance = @Net AND AmountPaid = 0) <> 1
           OR (SELECT COUNT(*) FROM dbo.ExpenseSummary WHERE ReferenceNumber = @InvRef OR (SupplierID = @Supplier AND InvoiceNo = @Invoice)) <> 1
              THEN 'invoice 38654 not as expected (must be unpaid)'
         WHEN EXISTS (SELECT 1 FROM dbo.APPaymentDetails WHERE SupplierID = @Supplier AND InvoiceNo = @Invoice)
           OR EXISTS (SELECT 1 FROM dbo.BankStatementRecon WHERE SourceRef = @InvRef)
              THEN 'the invoice has a payment line or a bank-recon item'
         WHEN (SELECT COUNT(*) FROM dbo.ExpenseMaster WHERE SupplierID = @Supplier AND InvoiceNo = @Invoice AND BatchReferenceID = @Batch
                AND ReferenceNumber = @InvRef AND Status = 'UNPAID' AND Balance = Amount AND AmountPaid = 0) <> 6
           OR (SELECT COUNT(*) FROM dbo.ExpenseMaster WHERE SupplierID = @Supplier AND InvoiceNo = @Invoice) <> 6
              THEN 'invoice lines of 38654 not as expected'
         WHEN (SELECT COUNT(*) FROM dbo.ExpenseManualLines WHERE ReferenceNumber = @InvRef AND BatchReferenceID = @Batch AND InvoiceNo = @Invoice) <> 8
              THEN 'entry lines of 38654 not as expected'
         WHEN (SELECT COUNT(*) FROM dbo.TicketMaster WHERE TicketNumber = @Ticket AND ReferenceNumber = @InvRef AND Mnemonic = 'EXP-MANUAL-CROSS-BR') <> 7
           OR (SELECT COUNT(*) FROM dbo.TicketMaster WHERE TicketNumber = @Ticket) <> 7
           OR (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber = @InvRef) <> 7
              THEN 'ticket 20655 masters not as expected'
         WHEN (SELECT COUNT(*) FROM dbo.TicketDetails WHERE TicketNumber = @Ticket AND ReferenceNumber = @InvRef) <> 8
           OR (SELECT COUNT(*) FROM dbo.TicketDetails WHERE TicketNumber = @Ticket) <> 8
           OR (SELECT COUNT(*) FROM dbo.TicketDetails WHERE ReferenceNumber = @InvRef) <> 8
           OR (SELECT SUM(Debit) - SUM(Credit) FROM dbo.TicketDetails WHERE TicketNumber = @Ticket) <> 0
           OR (SELECT SUM(Debit) FROM dbo.TicketDetails WHERE TicketNumber = @Ticket) <> 30200.00
              THEN 'ticket 20655 lines not as expected'
         WHEN (SELECT COUNT(*) FROM dbo.SupplierLedger WHERE SupplierKey = @Supplier AND InvoiceNo = @Invoice AND ReferenceNumber = @InvRef
                AND Credit = @Net AND ISNULL(Debit, 0) = 0) <> 1
           OR (SELECT COUNT(*) FROM dbo.SupplierLedger WHERE SupplierKey = @Supplier AND InvoiceNo = @Invoice) <> 1
              THEN 'supplier-ledger row of 38654 not as expected'
         END;
IF @Problem IS NOT NULL
BEGIN
    ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(400) = N'Not as expected: ' + @Problem + N'; nothing was changed.';
    THROW 59981, @msg, 1;
END

-- backups (the rows before)
SELECT * INTO dbo.TestCleanup_Backup_20261014_CheckVoucher FROM dbo.CheckVoucher WHERE ReferenceNumber = @Ref915;
SELECT * INTO dbo.TestCleanup_Backup_20261014_CheckVoucherCancelled FROM dbo.CheckVoucherCancelled WHERE ReferenceNumber = @Ref915;
SELECT * INTO dbo.TestCleanup_Backup_20261014_ExpenseSummary FROM dbo.ExpenseSummary WHERE ReferenceNumber = @InvRef;
SELECT * INTO dbo.TestCleanup_Backup_20261014_ExpenseMaster FROM dbo.ExpenseMaster WHERE SupplierID = @Supplier AND InvoiceNo = @Invoice AND BatchReferenceID = @Batch;
SELECT * INTO dbo.TestCleanup_Backup_20261014_ExpenseManualLines FROM dbo.ExpenseManualLines WHERE ReferenceNumber = @InvRef;
SELECT * INTO dbo.TestCleanup_Backup_20261014_TicketMaster FROM dbo.TicketMaster WHERE TicketNumber = @Ticket;
SELECT * INTO dbo.TestCleanup_Backup_20261014_TicketDetails FROM dbo.TicketDetails WHERE TicketNumber = @Ticket;
SELECT * INTO dbo.TestCleanup_Backup_20261014_SupplierLedger FROM dbo.SupplierLedger WHERE SupplierKey = @Supplier AND InvoiceNo = @Invoice;

-- 915: the cancelled-cheque record
IF OBJECT_ID('dbo.CancelledChequeEditLog', 'U') IS NOT NULL
    DELETE FROM dbo.CancelledChequeEditLog WHERE CAST(VoucherID AS VARCHAR(10)) = '915' AND ReferenceNumber = @Ref915;
DELETE FROM dbo.CheckVoucherCancelled WHERE ReferenceNumber = @Ref915 AND VoucherType = 'CANCELLED CHEQUE';
DELETE FROM dbo.CheckVoucher WHERE VoucherID = '915' AND ReferenceNumber = @Ref915;

-- 38654: the test invoice
DELETE FROM dbo.SupplierLedger WHERE SupplierKey = @Supplier AND InvoiceNo = @Invoice AND ReferenceNumber = @InvRef;
DELETE FROM dbo.TicketDetails WHERE TicketNumber = @Ticket AND ReferenceNumber = @InvRef;
DELETE FROM dbo.TicketMaster WHERE TicketNumber = @Ticket AND ReferenceNumber = @InvRef;
DELETE FROM dbo.ExpenseManualLines WHERE ReferenceNumber = @InvRef AND BatchReferenceID = @Batch;
DELETE FROM dbo.ExpenseMaster WHERE SupplierID = @Supplier AND InvoiceNo = @Invoice AND BatchReferenceID = @Batch;
DELETE FROM dbo.ExpenseSummary WHERE ReferenceNumber = @InvRef AND SupplierID = @Supplier AND InvoiceNo = @Invoice;

-- post-check: nothing left; supplier 000142 account = its ledger
IF (SELECT COUNT(*) FROM dbo.CheckVoucher WHERE ReferenceNumber = @Ref915) <> 0
   OR (SELECT COUNT(*) FROM dbo.CheckVoucherCancelled WHERE ReferenceNumber = @Ref915) <> 0
   OR (SELECT COUNT(*) FROM dbo.ExpenseSummary WHERE ReferenceNumber = @InvRef) <> 0
   OR (SELECT COUNT(*) FROM dbo.ExpenseMaster WHERE SupplierID = @Supplier AND InvoiceNo = @Invoice) <> 0
   OR (SELECT COUNT(*) FROM dbo.ExpenseManualLines WHERE ReferenceNumber = @InvRef) <> 0
   OR (SELECT COUNT(*) FROM dbo.TicketMaster WHERE TicketNumber = @Ticket) <> 0
   OR (SELECT COUNT(*) FROM dbo.TicketDetails WHERE TicketNumber = @Ticket) <> 0
   OR (SELECT COUNT(*) FROM dbo.SupplierLedger WHERE SupplierKey = @Supplier AND InvoiceNo = @Invoice) <> 0
   OR (SELECT AccountBalance FROM dbo.SupplierAccounts WHERE SupplierKey = @Supplier)
      <> (SELECT ISNULL(SUM(Credit) - SUM(Debit), 0) FROM dbo.SupplierLedger WHERE SupplierKey = @Supplier)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 59982, 'Post-check failed; nothing was changed.', 1;
END

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
SELECT a.SupplierKey, a.AccountBalance FROM dbo.SupplierAccounts AS a WHERE a.SupplierKey = '000142';
PRINT 'Test cancelled cheque 915 and test invoice 38654 deleted (backups dbo.TestCleanup_Backup_20261014_*).';
