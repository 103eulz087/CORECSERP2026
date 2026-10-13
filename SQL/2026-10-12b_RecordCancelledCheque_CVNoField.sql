/* ================================================================
   2026-10-12b: Record Cancelled Cheque - CV number field
   ================================================================
   Follow-up to 2026-10-12_SupplierPayment_RecordCancelledCheque.sql (needs it).
   User (2026-10-12): the Cancelled Cheque window gets a CV No. field. The screen
   fills it with the next CV no. of the series (same rule as before) and staff may
   overwrite it.
     * sp_RecordCancelledCheque gets an optional @CVNo (last parameter): blank / NULL
       = the next one of the series, as before;
     * a CV no. already on a cheque voucher (CVNo or NotedBy) is refused (60610),
       whether typed or computed.
   Same other parameters, so the exe built before this still works. Backup
   sp_RecordCancelledCheque_OLD_10122026160000. One transaction with a post-check.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
GO
IF OBJECT_ID('dbo.sp_RecordCancelledCheque', 'P') IS NULL
    THROW 60611, 'Run 2026-10-12_SupplierPayment_RecordCancelledCheque.sql first.', 1;
IF OBJECT_ID('dbo.sp_RecordCancelledCheque_OLD_10122026160000', 'P') IS NOT NULL
    THROW 60611, 'This script has been run here before (sp_RecordCancelledCheque_OLD_10122026160000 exists).', 1;
GO
BEGIN TRANSACTION;
EXEC sp_rename 'dbo.sp_RecordCancelledCheque', 'sp_RecordCancelledCheque_OLD_10122026160000';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE PROCEDURE dbo.sp_RecordCancelledCheque
    @BankGLCode VARCHAR(30),
    @CheckNo    VARCHAR(50),
    @CheckDate  DATE,
    @Reason     VARCHAR(100),
    @Remarks    VARCHAR(1000) = '',
    @User       VARCHAR(50),
    @CVNo       VARCHAR(50) = NULL    -- 2026-10-12b: the CV no. typed on screen; NULL / blank = the next one in the series
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
        DECLARE @AutoCVNo VARCHAR(50) = 'CV' + RIGHT(CONVERT(CHAR(4), YEAR(@CheckDate)), 2) + RIGHT('0' + CAST(MONTH(@CheckDate) AS VARCHAR(2)), 2)
                                   + '-' + CASE WHEN @Seq < 1000 THEN RIGHT('00' + CAST(@Seq AS VARCHAR(10)), 3) ELSE CAST(@Seq AS VARCHAR(10)) END
                                   + @Bank + @CheckNo;
        -- 2026-10-12b: the CV no. typed on screen wins; blank = the next one of the series
        SET @CVNo = ISNULL(NULLIF(LTRIM(RTRIM(ISNULL(@CVNo, ''))), ''), @AutoCVNo);
        IF LEN(@CVNo) > 50 THROW 60608, 'The CV number would be longer than 50 characters; check the cheque number.', 1;
        IF EXISTS (SELECT 1 FROM dbo.CheckVoucher WITH (UPDLOCK, HOLDLOCK) WHERE LTRIM(RTRIM(CVNo)) = @CVNo OR LTRIM(RTRIM(NotedBy)) = @CVNo)
        BEGIN
            SET @msg = N'CV number ' + @CVNo + N' is already used; enter another one. Nothing was recorded.';
            THROW 60610, @msg, 1;
        END

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
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
IF OBJECT_ID('dbo.sp_RecordCancelledCheque', 'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID('dbo.sp_RecordCancelledCheque') AND name = '@CVNo')
BEGIN
    RAISERROR('Post-check failed; rolled back.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
COMMIT TRANSACTION;
PRINT 'sp_RecordCancelledCheque: optional @CVNo (backup _OLD_10122026160000).';
GO
SET NOEXEC OFF;
GO
