/* ================================================================
   2026-10-12: record a cancelled (spoiled) cheque - no payment, no GL
   ================================================================
   User request (AccountingDevEx/SupplierPaymentDevEx): staff record a spoiled /
   misprinted / lost cheque by paying a fake supplier "CANCELLED" (000075), which
   needs an invoice or GL line that doesn't exist. The cheque only has to be
   accounted for, so the cheque series has no gap and the screen's next cheque
   number moves past it.

   New dbo.sp_RecordCancelledCheque (new object only; nothing existing changes):
     * uses up a voucher no. (sp_GetVoucherNumber), a reference no.
       (sp_GetReferenceNumber), the cheque no. and a CV no. (user, 2026-10-12: a
       spoiled cheque takes a CV number too). The CV no. follows the screen's rule
       (SupplierPaymentDevEx.GenerateVoucherNumber):
       'CV' + yy + mm + '-' + (cheque vouchers dated that month + 1, 3 digits) + BankCoa.Bank + cheque no.;
     * writes one CheckVoucher row: Amount 0, PaidTo 'CANCELLED', supplier
       'CANCELLED' (when it exists), isErrorCorrect = 1, CancelledBy / Date / Reason,
       the bank in OfficialReceiptNo / CreditGLCode as a normal cheque;
     * logs it in CheckVoucherCancelled (VoucherType 'CANCELLED CHEQUE');
     * creates no GL ticket, no bank recon item, no AP or supplier-ledger row.
   A cheque no. already recorded on that bank account is refused (60607); an older,
   out-of-sequence number is allowed (user, 2026-10-12). The screen's next-cheque
   suggestion skips numbers recorded this way (C#).
   Errors 60601-60609. Callers: SupplierPaymentDevEx "Record Cancelled Cheque".
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;

IF OBJECT_ID('dbo.sp_RecordCancelledCheque', 'P') IS NOT NULL
    THROW 60600, 'dbo.sp_RecordCancelledCheque already exists: this script has been run here before.', 1;
GO

CREATE PROCEDURE dbo.sp_RecordCancelledCheque
    @BankGLCode VARCHAR(30),
    @CheckNo    VARCHAR(50),
    @CheckDate  DATE,
    @Reason     VARCHAR(100),
    @Remarks    VARCHAR(1000) = '',
    @User       VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @BankGLCode = LTRIM(RTRIM(ISNULL(@BankGLCode, '')));
    SET @CheckNo    = LTRIM(RTRIM(ISNULL(@CheckNo, '')));
    SET @Reason     = LTRIM(RTRIM(ISNULL(@Reason, '')));
    SET @Remarks    = LTRIM(RTRIM(ISNULL(@Remarks, '')));

    IF @BankGLCode = '' THROW 60601, 'Select the bank account the cheque belongs to.', 1;
    IF @CheckNo = ''    THROW 60602, 'Enter the cancelled cheque number.', 1;
    IF @CheckDate IS NULL THROW 60603, 'Enter the cheque date.', 1;
    IF @Reason = ''     THROW 60604, 'Enter why the cheque was cancelled.', 1;

    DECLARE @Bank VARCHAR(50) = (SELECT TOP (1) LTRIM(RTRIM(Bank)) FROM dbo.BankCoa WHERE AccountCode = @BankGLCode);
    IF @Bank IS NULL THROW 60605, 'This account is not set up as a bank account (BankCoa); nothing was recorded.', 1;

    DECLARE @SupplierID VARCHAR(50) = ISNULL((SELECT TOP (1) SupplierID FROM dbo.Supplier
                                              WHERE LTRIM(RTRIM(SupplierName)) = 'CANCELLED' ORDER BY SupplierID), '');
    DECLARE @msg NVARCHAR(300);

    BEGIN TRY
        BEGIN TRAN;

        -- one cancelled-cheque writer at a time (the CV month count and the duplicate check below)
        DECLARE @lock INT;
        EXEC @lock = sp_getapplock @Resource = 'CANCELLEDCHEQUE', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
        IF @lock < 0 THROW 60606, 'Another cancelled cheque is being recorded; try again.', 1;

        IF EXISTS (SELECT 1 FROM dbo.CheckVoucher WITH (UPDLOCK, HOLDLOCK)
                   WHERE (OfficialReceiptNo = @BankGLCode OR CreditGLCode = @BankGLCode)
                     AND LTRIM(RTRIM(CheckNo)) = @CheckNo)
        BEGIN
            SET @msg = N'Cheque ' + @CheckNo + N' is already recorded on this bank account; nothing was recorded.';
            THROW 60607, @msg, 1;
        END

        -- the CV no. the screen would give the next cheque of that month
        DECLARE @Seq INT = 1 + (SELECT COUNT(*) FROM dbo.CheckVoucher WITH (HOLDLOCK)
                                WHERE YEAR(CheckDate) = YEAR(@CheckDate) AND MONTH(CheckDate) = MONTH(@CheckDate));
        DECLARE @CVNo VARCHAR(50) = 'CV' + RIGHT(CONVERT(CHAR(4), YEAR(@CheckDate)), 2) + RIGHT('0' + CAST(MONTH(@CheckDate) AS VARCHAR(2)), 2)
                                   + '-' + CASE WHEN @Seq < 1000 THEN RIGHT('00' + CAST(@Seq AS VARCHAR(10)), 3) ELSE CAST(@Seq AS VARCHAR(10)) END
                                   + @Bank + @CheckNo;
        IF LEN(@CVNo) > 50 THROW 60608, 'The CV number would be longer than 50 characters; check the cheque number.', 1;

        DECLARE @n TABLE (v VARCHAR(10));
        INSERT INTO @n EXEC dbo.sp_GetVoucherNumber;
        DECLARE @VoucherID VARCHAR(10) = (SELECT TOP (1) v FROM @n);
        DELETE FROM @n;
        INSERT INTO @n EXEC dbo.sp_GetReferenceNumber;
        DECLARE @Ref VARCHAR(10) = (SELECT TOP (1) v FROM @n);
        IF ISNULL(@VoucherID, '') = '' OR ISNULL(@Ref, '') = ''
            THROW 60609, 'Could not get a voucher / reference number; nothing was recorded.', 1;

        DECLARE @Particulars VARCHAR(2000) = 'CANCELLED CHEQUE (' + @Reason + ')' + CASE WHEN @Remarks = '' THEN '' ELSE ' - ' + @Remarks END;

        INSERT INTO dbo.CheckVoucher
            (VoucherID, SupplierID, ReferenceNumber, PaidTo, CheckNo, CheckDate,
             Particulars, Amount, PreparedBy, VerifiedBy, NotedBy, PaymentApprovedBy,
             PaymentReceivedBy, OfficialReceiptNo, VoucherType, DateReceived,
             DateAdded, DateUpdate, isErrorCorrect, isLiquidation, ControlNo, CreditGLCode, CVNo,
             CancelledBy, CancelledDate, CancelReason)
        VALUES
            (@VoucherID, @SupplierID, @Ref, 'CANCELLED', @CheckNo, @CheckDate,
             @Particulars, 0, @User, '', @CVNo, '',
             '', @BankGLCode, 'CHECK', NULL,
             GETDATE(), GETDATE(), 1, 0, @CheckNo, @BankGLCode, @CVNo,
             @User, GETDATE(), LEFT('CANCELLED CHEQUE: ' + @Reason + CASE WHEN @Remarks = '' THEN '' ELSE ' - ' + @Remarks END, 300));

        INSERT INTO dbo.CheckVoucherCancelled
            (VoucherID, SupplierKey, ReferenceNumber, PaidTo, CheckNo, CheckDate, Particulars, Amount,
             ExecuteBy, VoucherType, DateAdded, DateUpdate)
        VALUES
            (@VoucherID, LEFT(@SupplierID, 6), @Ref, 'CANCELLED', @CheckNo, @CheckDate, @Particulars, 0,
             LEFT(@User, 30), 'CANCELLED CHEQUE', GETDATE(), GETDATE());

        COMMIT TRAN;

        SELECT 1 AS Status, @VoucherID AS VoucherID, @Ref AS ReferenceNumber, @CVNo AS CVNo, @CheckNo AS CheckNo,
               'Cancelled cheque ' + @CheckNo + ' recorded as ' + @CVNo + ' (voucher ' + @VoucherID + '). No GL entry was made.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO
