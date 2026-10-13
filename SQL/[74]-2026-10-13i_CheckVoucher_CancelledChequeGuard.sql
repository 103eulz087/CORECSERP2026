/* ================================================================
   [74] 2026-10-13 - Cheque vouchers: a cheque recorded as cancelled can't be issued again
   ================================================================
   [55] made a spoiled / misprinted / lost cheque use up its number (sp_RecordCancelledCheque refuses a number already
   used on the bank, 60607), but nothing stopped the other direction: a payment could still be posted on a cheque number
   that was recorded as cancelled. Found by the [70] AP check AP-CHEQUE-REUSED on STAGING (cheque 2384570: cancelled
   record 916, then live voucher 917). User 2026-10-13: "go ahead add the cancelled cheque guard".

   New trigger dbo.trg_CheckVoucher_NoCancelledChequeReuse (AFTER INSERT, UPDATE) on dbo.CheckVoucher:
     refuses (60631) a LIVE cheque voucher row whose cheque no. is a cancelled-cheque record's on the same bank.
       - live row      = isErrorCorrect 0, PaidTo not 'CANCELLED', cheque no. not blank;
       - cancelled-cheque record = what sp_RecordCancelledCheque writes (same proof as sp_EditCancelledCheque):
         PaidTo 'CANCELLED', Amount 0, isErrorCorrect 1, with its CheckVoucherCancelled row of type 'CANCELLED CHEQUE';
       - same bank     = the record's bank (CreditGLCode, else OfficialReceiptNo) is in the live row's CreditGLCode,
         OfficialReceiptNo or NotedBy (the writers keep the bank in different columns: sp_Payment_CreateVoucherHeader
         in CreditGLCode + OfficialReceiptNo, sp_PostCashAdvance in OfficialReceiptNo, sp_AddPaymentSupplierCompound
         in NotedBy);
       - on UPDATE only rows whose cheque no. / bank / status changed are checked, so editing the amount or reversing
         an existing voucher is never refused.
   One rule for every writer: SupplierPaymentDevEx / CombinedSupplierVoucherFrm (sp_PostSupplierPaymentWithManualLines ->
   V2 -> sp_Payment_CreateVoucherHeader), CashAdvanceVoucherFrm (sp_PostCashAdvance), BankReconFormV2 auto-debit and
   HOFormsDevEx/SupplierPaymentDevEx (sp_AddPaymentSupplierCompound), the retired screens, and the web v2.
   The posting transaction is rolled back, so the voucher, its tickets, ledger and bank-recon rows are not saved; the
   screens show the message (they display the SQL error text).

   NOT refused (on purpose): a number of a REVERSED voucher (PRODUCTION re-issues 11 such numbers: a voucher reversed
   and re-posted on the same cheque); a duplicate between two live vouchers (none on any database today; not asked).
   Existing rows are not touched (STAGING keeps its test pair 916 / 917).

   New object only (CREATE OR ALTER, so a re-run is safe); no exe change. Post-check: the trigger exists and is enabled.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER TRIGGER dbo.trg_CheckVoucher_NoCancelledChequeReuse
ON dbo.CheckVoucher
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    DECLARE @CheckNo VARCHAR(50), @Bank VARCHAR(50), @CVNo VARCHAR(50), @CancelledVoucher VARCHAR(20), @msg NVARCHAR(600);

    SELECT TOP (1)
        @CheckNo = LTRIM(RTRIM(i.CheckNo)),
        @Bank = k.Bank,
        @CVNo = ISNULL(NULLIF(LTRIM(RTRIM(k.CVNo)), ''), '-'),
        @CancelledVoucher = CAST(k.VoucherID AS VARCHAR(20))
    FROM inserted AS i
    CROSS APPLY (
        SELECT TOP (1) c.VoucherID, c.CVNo,
               COALESCE(NULLIF(LTRIM(RTRIM(c.CreditGLCode)), ''), NULLIF(LTRIM(RTRIM(c.OfficialReceiptNo)), '')) AS Bank
        FROM dbo.CheckVoucher AS c
        WHERE c.PaidTo = 'CANCELLED' AND ISNULL(c.Amount, 0) = 0 AND ISNULL(c.isErrorCorrect, 0) = 1
          AND LTRIM(RTRIM(c.CheckNo)) = LTRIM(RTRIM(i.CheckNo))
          AND COALESCE(NULLIF(LTRIM(RTRIM(c.CreditGLCode)), ''), NULLIF(LTRIM(RTRIM(c.OfficialReceiptNo)), ''))
              IN (LTRIM(RTRIM(i.CreditGLCode)), LTRIM(RTRIM(i.OfficialReceiptNo)), LTRIM(RTRIM(i.NotedBy)))
          AND EXISTS (SELECT 1 FROM dbo.CheckVoucherCancelled AS l
                      WHERE l.VoucherID = c.VoucherID AND l.ReferenceNumber = c.ReferenceNumber AND l.VoucherType = 'CANCELLED CHEQUE')
        ORDER BY c.VoucherID) AS k
    WHERE ISNULL(i.isErrorCorrect, 0) = 0
      AND ISNULL(i.PaidTo, '') <> 'CANCELLED'
      AND ISNULL(LTRIM(RTRIM(i.CheckNo)), '') <> ''
      -- on UPDATE: only rows whose cheque no., bank or status changed
      AND NOT EXISTS (SELECT 1 FROM deleted AS d
                      WHERE d.VoucherID = i.VoucherID AND d.ReferenceNumber = i.ReferenceNumber
                        AND ISNULL(LTRIM(RTRIM(d.CheckNo)), '') = ISNULL(LTRIM(RTRIM(i.CheckNo)), '')
                        AND ISNULL(d.CreditGLCode, '') = ISNULL(i.CreditGLCode, '')
                        AND ISNULL(d.OfficialReceiptNo, '') = ISNULL(i.OfficialReceiptNo, '')
                        AND ISNULL(d.NotedBy, '') = ISNULL(i.NotedBy, '')
                        AND ISNULL(d.isErrorCorrect, 0) = ISNULL(i.isErrorCorrect, 0)
                        AND ISNULL(d.PaidTo, '') = ISNULL(i.PaidTo, ''));

    IF @CheckNo IS NOT NULL
    BEGIN
        SET @msg = N'Cheque ' + @CheckNo + N' on bank ' + ISNULL(@Bank, N'-') + N' was recorded as a cancelled cheque ('
                 + @CVNo + N', voucher ' + ISNULL(@CancelledVoucher, N'-') + N'), so its number is used up. '
                 + N'Use the next cheque number. If it was recorded as cancelled by mistake, correct that record in '
                 + N'"Cancelled Cheque..." first. This voucher was not saved.';
        THROW 60631, @msg, 1;
    END
END;
GO

-- post-check
IF NOT EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'trg_CheckVoucher_NoCancelledChequeReuse'
                                            AND parent_id = OBJECT_ID('dbo.CheckVoucher') AND is_disabled = 0)
    THROW 60632, 'trg_CheckVoucher_NoCancelledChequeReuse is missing or disabled.', 1;
SELECT name AS TriggerName, is_disabled, CONVERT(VARCHAR(19), modify_date, 120) AS Modified
FROM sys.triggers WHERE name = 'trg_CheckVoucher_NoCancelledChequeReuse';
PRINT 'Cancelled-cheque guard installed (trg_CheckVoucher_NoCancelledChequeReuse, error 60631).';
GO
