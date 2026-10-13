/* ================================================================
   2026-10-12c: Cancelled cheques - list and edit (typo corrections)
   ================================================================
   Follow-up to 2026-10-12 / 2026-10-12b (needs both). User (2026-10-12): after
   recording a cancelled cheque, staff must be able to fix a typo (wrong cheque no.,
   date, CV no., reason, remarks, bank).

   New objects only (nothing existing changes):
     * table dbo.CancelledChequeEditLog: one row per edit, old and new values, who, when;
     * dbo.sp_GetCancelledCheques @DateFrom / @DateTo (optional, on the cheque date):
       the cancelled cheques recorded with sp_RecordCancelledCheque, newest first;
     * dbo.sp_EditCancelledCheque: corrects one of them. Only such records can be
       edited (60621): a CheckVoucher row with PaidTo 'CANCELLED', amount 0, voided,
       and its CheckVoucherCancelled log row (VoucherType 'CANCELLED CHEQUE') - never a
       payment voucher. Same checks as recording: a bank account (60605), cheque no.,
       date, reason, CV no. required (60601-60604, 60624); a cheque no. already used on
       that bank by another voucher (60622) or a CV no. used by another voucher (60623)
       is refused. Updates the two rows and logs the edit. No GL / recon / AP rows exist,
       so nothing else changes.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;

IF OBJECT_ID('dbo.sp_RecordCancelledCheque', 'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID('dbo.sp_RecordCancelledCheque') AND name = '@CVNo')
    THROW 60620, 'Run 2026-10-12_SupplierPayment_RecordCancelledCheque.sql and 2026-10-12b_RecordCancelledCheque_CVNoField.sql first.', 1;
IF OBJECT_ID('dbo.sp_EditCancelledCheque', 'P') IS NOT NULL OR OBJECT_ID('dbo.CancelledChequeEditLog', 'U') IS NOT NULL
    THROW 60620, 'This script has been run here before (sp_EditCancelledCheque / CancelledChequeEditLog exist).', 1;
GO

BEGIN TRANSACTION;

CREATE TABLE dbo.CancelledChequeEditLog
(
    LogID           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CancelledChequeEditLog PRIMARY KEY,
    VoucherID       DECIMAL(7,0)  NOT NULL,
    ReferenceNumber VARCHAR(10)   NOT NULL,
    OldValues       VARCHAR(1000) NOT NULL,
    NewValues       VARCHAR(1000) NOT NULL,
    EditedBy        VARCHAR(50)   NOT NULL,
    EditedAt        DATETIME      NOT NULL CONSTRAINT DF_CancelledChequeEditLog_EditedAt DEFAULT (GETDATE())
);
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

CREATE PROCEDURE dbo.sp_GetCancelledCheques
    @DateFrom DATE = NULL,
    @DateTo   DATE = NULL
AS
/*  The cancelled cheques recorded with sp_RecordCancelledCheque (newest first).
    Caller: SupplierPaymentDevEx "Cancelled Cheque…" list. */
BEGIN
    SET NOCOUNT ON;
    SELECT  cv.VoucherID, cv.ReferenceNumber,
            CAST(cv.CheckDate AS DATE)               AS CheckDate,
            cv.OfficialReceiptNo                     AS BankGLCode,
            ISNULL(coa.Description, '')              AS BankName,
            cv.CheckNo, cv.CVNo,
            -- the reason as picked; the remarks after " - " (see sp_RecordCancelledCheque's CancelReason)
            LTRIM(RTRIM(CASE WHEN CHARINDEX(' - ', r.Body) > 0 THEN LEFT(r.Body, CHARINDEX(' - ', r.Body) - 1) ELSE r.Body END)) AS Reason,
            LTRIM(RTRIM(CASE WHEN CHARINDEX(' - ', r.Body) > 0 THEN SUBSTRING(r.Body, CHARINDEX(' - ', r.Body) + 3, 1000) ELSE '' END)) AS Remarks,
            cv.PreparedBy                            AS RecordedBy,
            cv.CancelledDate                         AS RecordedAt,
            (SELECT COUNT(*) FROM dbo.CancelledChequeEditLog AS e
              WHERE e.VoucherID = cv.VoucherID AND e.ReferenceNumber = cv.ReferenceNumber) AS Edits
    FROM dbo.CheckVoucher AS cv
    INNER JOIN dbo.CheckVoucherCancelled AS l
            ON l.VoucherID = cv.VoucherID AND l.ReferenceNumber = cv.ReferenceNumber AND l.VoucherType = 'CANCELLED CHEQUE'
    LEFT JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = cv.OfficialReceiptNo
    CROSS APPLY (SELECT CASE WHEN ISNULL(cv.CancelReason, '') LIKE 'CANCELLED CHEQUE: %'
                             THEN SUBSTRING(cv.CancelReason, 19, 300) ELSE ISNULL(cv.CancelReason, '') END AS Body) AS r
    WHERE cv.PaidTo = 'CANCELLED' AND ISNULL(cv.Amount, 0) = 0 AND ISNULL(cv.isErrorCorrect, 0) = 1
      AND (@DateFrom IS NULL OR cv.CheckDate >= @DateFrom)
      AND (@DateTo   IS NULL OR cv.CheckDate <= @DateTo)
    ORDER BY cv.CheckDate DESC, cv.VoucherID DESC;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

CREATE PROCEDURE dbo.sp_EditCancelledCheque
    @VoucherID       VARCHAR(10),
    @ReferenceNumber VARCHAR(10),
    @BankGLCode      VARCHAR(30),
    @CheckNo         VARCHAR(50),
    @CheckDate       DATE,
    @CVNo            VARCHAR(50),
    @Reason          VARCHAR(100),
    @Remarks         VARCHAR(1000) = '',
    @User            VARCHAR(50)
AS
/*  Corrects a cancelled cheque recorded with sp_RecordCancelledCheque (typos).
    Caller: SupplierPaymentDevEx "Cancelled Cheque…" > Edit. Errors 60601-60605, 60621-60624. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @BankGLCode = LTRIM(RTRIM(ISNULL(@BankGLCode, '')));
    SET @CheckNo    = LTRIM(RTRIM(ISNULL(@CheckNo, '')));
    SET @CVNo       = LTRIM(RTRIM(ISNULL(@CVNo, '')));
    SET @Reason     = LTRIM(RTRIM(ISNULL(@Reason, '')));
    SET @Remarks    = LTRIM(RTRIM(ISNULL(@Remarks, '')));

    IF @BankGLCode = '' THROW 60601, 'Select the bank account the cheque belongs to.', 1;
    IF @CheckNo = ''    THROW 60602, 'Enter the cancelled cheque number.', 1;
    IF @CheckDate IS NULL THROW 60603, 'Enter the cheque date.', 1;
    IF @Reason = ''     THROW 60604, 'Enter why the cheque was cancelled.', 1;
    IF @CVNo = ''       THROW 60624, 'Enter the CV number.', 1;

    DECLARE @Bank VARCHAR(50) = (SELECT TOP (1) LTRIM(RTRIM(Bank)) FROM dbo.BankCoa WHERE AccountCode = @BankGLCode);
    IF @Bank IS NULL THROW 60605, 'This account is not set up as a bank account (BankCoa); nothing was changed.', 1;

    DECLARE @msg NVARCHAR(300);

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @lock INT;
        EXEC @lock = sp_getapplock @Resource = 'CANCELLEDCHEQUE', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
        IF @lock < 0 THROW 60606, 'Another cancelled cheque is being saved; try again.', 1;

        -- the record, and proof it is a cancelled-cheque record (not a payment voucher)
        DECLARE @OldBank VARCHAR(100), @OldCheckNo VARCHAR(100), @OldDate DATE, @OldCV VARCHAR(50), @OldReason VARCHAR(300);
        SELECT @OldBank = cv.OfficialReceiptNo, @OldCheckNo = cv.CheckNo, @OldDate = cv.CheckDate, @OldCV = cv.CVNo, @OldReason = cv.CancelReason
        FROM dbo.CheckVoucher AS cv WITH (UPDLOCK, HOLDLOCK)
        WHERE CAST(cv.VoucherID AS VARCHAR(10)) = @VoucherID AND cv.ReferenceNumber = @ReferenceNumber
          AND cv.PaidTo = 'CANCELLED' AND ISNULL(cv.Amount, 0) = 0 AND ISNULL(cv.isErrorCorrect, 0) = 1
          AND EXISTS (SELECT 1 FROM dbo.CheckVoucherCancelled AS l
                      WHERE l.VoucherID = cv.VoucherID AND l.ReferenceNumber = cv.ReferenceNumber AND l.VoucherType = 'CANCELLED CHEQUE');
        IF @@ROWCOUNT <> 1
            THROW 60621, 'This is not a cancelled cheque recorded with "Cancelled Cheque..." (or it no longer exists); nothing was changed.', 1;

        IF EXISTS (SELECT 1 FROM dbo.CheckVoucher WITH (UPDLOCK, HOLDLOCK)
                   WHERE (OfficialReceiptNo = @BankGLCode OR CreditGLCode = @BankGLCode)
                     AND LTRIM(RTRIM(CheckNo)) = @CheckNo
                     AND NOT (CAST(VoucherID AS VARCHAR(10)) = @VoucherID AND ReferenceNumber = @ReferenceNumber))
        BEGIN
            SET @msg = N'Cheque ' + @CheckNo + N' is already used by another voucher on this bank account; nothing was changed.';
            THROW 60622, @msg, 1;
        END

        IF EXISTS (SELECT 1 FROM dbo.CheckVoucher WITH (UPDLOCK, HOLDLOCK)
                   WHERE (LTRIM(RTRIM(CVNo)) = @CVNo OR LTRIM(RTRIM(NotedBy)) = @CVNo)
                     AND NOT (CAST(VoucherID AS VARCHAR(10)) = @VoucherID AND ReferenceNumber = @ReferenceNumber))
        BEGIN
            SET @msg = N'CV number ' + @CVNo + N' is already used by another voucher; nothing was changed.';
            THROW 60623, @msg, 1;
        END

        DECLARE @NewReason VARCHAR(300) = LEFT('CANCELLED CHEQUE: ' + @Reason + CASE WHEN @Remarks = '' THEN '' ELSE ' - ' + @Remarks END, 300);
        DECLARE @Particulars VARCHAR(2000) = 'CANCELLED CHEQUE (' + @Reason + ')' + CASE WHEN @Remarks = '' THEN '' ELSE ' - ' + @Remarks END;

        DECLARE @OldValues VARCHAR(1000) = 'Bank ' + ISNULL(@OldBank, '') + ' | Cheque ' + ISNULL(@OldCheckNo, '') + ' | Date ' + ISNULL(CONVERT(VARCHAR(10), @OldDate, 120), '')
                                         + ' | CV ' + ISNULL(@OldCV, '') + ' | ' + ISNULL(@OldReason, '');
        DECLARE @NewValues VARCHAR(1000) = 'Bank ' + @BankGLCode + ' | Cheque ' + @CheckNo + ' | Date ' + CONVERT(VARCHAR(10), @CheckDate, 120)
                                         + ' | CV ' + @CVNo + ' | ' + @NewReason;
        IF @OldValues = @NewValues
        BEGIN
            COMMIT TRAN;
            SELECT 0 AS Status, 'Nothing was changed.' AS Message;
            RETURN;
        END

        UPDATE dbo.CheckVoucher
        SET OfficialReceiptNo = @BankGLCode, CreditGLCode = @BankGLCode,
            CheckNo = @CheckNo, ControlNo = @CheckNo, CheckDate = @CheckDate,
            CVNo = @CVNo, NotedBy = @CVNo,
            Particulars = @Particulars, CancelReason = @NewReason,
            DateUpdate = GETDATE()
        WHERE CAST(VoucherID AS VARCHAR(10)) = @VoucherID AND ReferenceNumber = @ReferenceNumber
          AND PaidTo = 'CANCELLED' AND ISNULL(Amount, 0) = 0;
        IF @@ROWCOUNT <> 1 THROW 60621, 'The cancelled cheque record could not be updated; nothing was changed.', 1;

        UPDATE dbo.CheckVoucherCancelled
        SET CheckNo = @CheckNo, CheckDate = @CheckDate, Particulars = @Particulars, DateUpdate = GETDATE()
        WHERE CAST(VoucherID AS VARCHAR(10)) = @VoucherID AND ReferenceNumber = @ReferenceNumber AND VoucherType = 'CANCELLED CHEQUE';

        INSERT INTO dbo.CancelledChequeEditLog (VoucherID, ReferenceNumber, OldValues, NewValues, EditedBy)
        VALUES (CAST(@VoucherID AS DECIMAL(7,0)), @ReferenceNumber, LEFT(@OldValues, 1000), LEFT(@NewValues, 1000), LEFT(ISNULL(@User, ''), 50));

        COMMIT TRAN;

        SELECT 1 AS Status, 'Cancelled cheque updated: cheque ' + @CheckNo + ', ' + @CVNo + '.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
IF OBJECT_ID('dbo.sp_EditCancelledCheque', 'P') IS NULL OR OBJECT_ID('dbo.sp_GetCancelledCheques', 'P') IS NULL OR OBJECT_ID('dbo.CancelledChequeEditLog', 'U') IS NULL
BEGIN
    RAISERROR('Post-check failed; rolled back.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
COMMIT TRANSACTION;
PRINT 'Cancelled cheques: list + edit (sp_GetCancelledCheques, sp_EditCancelledCheque, CancelledChequeEditLog).';
GO
SET NOEXEC OFF;
GO
