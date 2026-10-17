/* ================================================================
   [108] 2026-10-17g  CheckVoucher: no duplicate CV no.
   ================================================================
   User (2026-10-17): "in SupplierPaymentDevEx.cs put trappings on CVNo column CheckVoucher table. when placing a payment
   it must check that there is no existing CVNo to avoid duplicate."

   RULES
   - A CV no. (CheckVoucher.CVNo, compared trimmed, the database's case-insensitive collation) belongs to ONE document
     (VoucherID + ReferenceNumber) among the rows that hold their number:
       a live cheque voucher (isErrorCorrect 0), or
       a cancelled-cheque record ([55]: PaidTo 'CANCELLED', Amount 0, isErrorCorrect 1 + its CheckVoucherCancelled row,
       the same proof as trg_CheckVoucher_NoCancelledChequeReuse / sp_EditCancelledCheque): its CV no. stays used up.
     A REVERSED voucher's CV no. may be issued again (existing practice: 6 CV nos. on every tier were re-issued after a
     reversal, e.g. CV2609-188PNB2000413 vouchers 1075 / 1077).
   - New trigger trg_CheckVoucher_NoDuplicateCVNo (AFTER INSERT, UPDATE; XACT_ABORT ON) refuses 60632, naming the
     voucher that holds the number. One rule for every writer (sp_Payment_CreateVoucherHeader via the payment screens,
     sp_PostCashAdvance, sp_AddPaymentSupplierCompound, sp_RecordCancelledCheque / sp_EditCancelledCheque, retired
     screens, web v2). On UPDATE only rows whose CV no. or status changed are checked; a reversal (isErrorCorrect -> 1)
     never trips it.
   - C# SupplierPaymentDevEx checks the same before posting (clear message, nothing drawn); the trigger is the backstop.
   - Concurrency: the lookup reads WITH (READCOMMITTEDLOCK), so two posts of one CV no. at the same time cannot both commit,
     whatever the database's RCSI setting (RCSI is off on every tier today). sp-reviewer 2026-10-17: no blocker.

   Measured first (2026-10-17, read-only): DEV / STAGING / PRODUCTION identical: 378 CheckVoucher rows, 0 blank CV nos.,
   one row per voucher (0 multi-row), 0 live CV nos. shared by two documents, 0 live vouchers on a cancelled record's CV
   no.; only CHECK vouchers write CheckVoucher (cash / telegraphic: CashVoucher / TelegraphicVoucher). 60632 unused.
   New object only (CREATE). No backups needed. Exe: no change needed; the new exe checks before posting.
   Run in ONE connection with no open transaction.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET LOCK_TIMEOUT 10000;
GO

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[108] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.trg_CheckVoucher_NoDuplicateCVNo', 'TR') IS NOT NULL
BEGIN
    RAISERROR('[108] already applied in this database; nothing changed.', 10, 1);
    SET NOEXEC ON;
END
ELSE IF COL_LENGTH('dbo.CheckVoucher', 'CVNo') IS NULL OR OBJECT_ID('dbo.CheckVoucherCancelled', 'U') IS NULL
BEGIN
    RAISERROR('[108] stopped: needs CheckVoucher.CVNo ([33]) and CheckVoucherCancelled ([55]); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
-- the rule must already hold, or the trigger would block an edit of an existing row
ELSE IF EXISTS (SELECT 1
                FROM dbo.CheckVoucher AS a
                INNER JOIN dbo.CheckVoucher AS b
                        ON LTRIM(RTRIM(b.CVNo)) = LTRIM(RTRIM(a.CVNo))
                       AND NOT (b.VoucherID = a.VoucherID AND b.ReferenceNumber = a.ReferenceNumber)
                WHERE NULLIF(LTRIM(RTRIM(a.CVNo)), '') IS NOT NULL
                  AND ISNULL(a.isErrorCorrect, 0) = 0
                  AND (ISNULL(b.isErrorCorrect, 0) = 0
                       OR (b.PaidTo = 'CANCELLED' AND ISNULL(b.Amount, 0) = 0 AND b.isErrorCorrect = 1
                           AND EXISTS (SELECT 1 FROM dbo.CheckVoucherCancelled AS l
                                       WHERE l.VoucherID = b.VoucherID AND l.ReferenceNumber = b.ReferenceNumber AND l.VoucherType = 'CANCELLED CHEQUE'))))
BEGIN
    RAISERROR('[108] stopped: this database already has a live voucher sharing its CV no. with another live voucher or a cancelled-cheque record; fix those first (query in the script header rules); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[108] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
GO

IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE TRIGGER dbo.trg_CheckVoucher_NoDuplicateCVNo
ON dbo.CheckVoucher
AFTER INSERT, UPDATE
AS
/*  [108] 2026-10-17: a CV no. belongs to one document among the rows that hold their number (a live cheque voucher, or a
    cancelled-cheque record); a reversed voucher's CV no. may be issued again. Refuses 60632. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    DECLARE @CVNo VARCHAR(50), @OtherVoucher VARCHAR(20), @OtherRef VARCHAR(30), @OtherPaidTo VARCHAR(200),
            @OtherCancelled BIT, @msg NVARCHAR(800);
    SELECT TOP (1)
        @CVNo = LTRIM(RTRIM(i.CVNo)),
        @OtherVoucher = CAST(k.VoucherID AS VARCHAR(20)),
        @OtherRef = CAST(k.ReferenceNumber AS VARCHAR(30)),
        @OtherPaidTo = k.PaidTo,
        @OtherCancelled = k.IsCancelledRecord
    FROM inserted AS i
    CROSS APPLY (
        SELECT TOP (1) c.VoucherID, c.ReferenceNumber, c.PaidTo,
               CAST(CASE WHEN ISNULL(c.isErrorCorrect, 0) = 1 THEN 1 ELSE 0 END AS BIT) AS IsCancelledRecord
        FROM dbo.CheckVoucher AS c WITH (READCOMMITTEDLOCK)   -- [108] review: waits for a concurrent uncommitted voucher even under RCSI
        WHERE LTRIM(RTRIM(c.CVNo)) = LTRIM(RTRIM(i.CVNo))
          AND NOT (c.VoucherID = i.VoucherID AND c.ReferenceNumber = i.ReferenceNumber)
          AND (ISNULL(c.isErrorCorrect, 0) = 0
               OR (c.PaidTo = 'CANCELLED' AND ISNULL(c.Amount, 0) = 0 AND c.isErrorCorrect = 1
                   AND EXISTS (SELECT 1 FROM dbo.CheckVoucherCancelled AS l
                               WHERE l.VoucherID = c.VoucherID AND l.ReferenceNumber = c.ReferenceNumber AND l.VoucherType = 'CANCELLED CHEQUE')))
        ORDER BY c.VoucherID) AS k
    WHERE NULLIF(LTRIM(RTRIM(i.CVNo)), '') IS NOT NULL
      -- the row itself holds its number: a live voucher, or a cancelled-cheque record
      AND (ISNULL(i.isErrorCorrect, 0) = 0 OR ISNULL(i.PaidTo, '') = 'CANCELLED')
      -- on UPDATE: only rows whose CV no. or status changed
      AND NOT EXISTS (SELECT 1 FROM deleted AS d
                      WHERE d.VoucherID = i.VoucherID AND d.ReferenceNumber = i.ReferenceNumber AND d.SupplierID = i.SupplierID
                        AND d.SequenceNumber = i.SequenceNumber
                        AND ISNULL(LTRIM(RTRIM(d.CVNo)), '') = ISNULL(LTRIM(RTRIM(i.CVNo)), '')
                        AND ISNULL(d.isErrorCorrect, 0) = ISNULL(i.isErrorCorrect, 0)
                        AND ISNULL(d.PaidTo, '') = ISNULL(i.PaidTo, ''));

    IF @CVNo IS NOT NULL
    BEGIN
        SET @msg = N'CV no. ' + @CVNo + N' is already used by '
                 + CASE WHEN @OtherCancelled = 1 THEN N'cancelled-cheque record ' ELSE N'voucher ' END
                 + ISNULL(@OtherVoucher, N'-') + N' (ref ' + ISNULL(@OtherRef, N'-') + N', ' + ISNULL(@OtherPaidTo, N'-') + N'). '
                 + N'Use another CV no.; a CV no. can be issued again only after its voucher is reversed. Nothing was saved.';
        THROW 60632, @msg, 1;
    END
END;
GO

IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF OBJECT_ID('dbo.trg_CheckVoucher_NoDuplicateCVNo', 'TR') IS NULL
   OR EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'trg_CheckVoucher_NoDuplicateCVNo' AND is_disabled = 1)
    SET @msg = N'the trigger is missing or disabled';
IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[108] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59897, @msg, 1;
END
COMMIT TRANSACTION;
PRINT '[108] committed: a CV no. can be held by one live cheque voucher (or cancelled-cheque record) only (60632).';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
