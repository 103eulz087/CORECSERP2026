/* ================================================================
   2026-10-02f: Bank Recon — Outstanding Cheques show Control No / Check No
   ================================================================
   Needs 2026-10-02e (sp_BankRecon_GetPeriod with the DIT control number).

   The OC grid of AccountingDevEx/BankReconFormV2 showed only date, payee,
   amount and resolved. OC rows are cheques ISSUED (AP-PAYMENT, CASH-ADVANCE,
   MANUAL-JV); BankStatementRecon.ReferenceNo = the voucher no. and SourceRef
   = the payment reference, so each links to its CheckVoucher / CashVoucher /
   TelegraphicVoucher, which carry ControlNo (and CheckNo on cheques).
   STAGING 2026-10-02: AP-PAYMENT 141 / 143 linked, 140 with a control number
   (133 distinct -- usually the cheque number); CASH-ADVANCE 80 / 82 linked,
   cheque no. but no control no.; MANUAL-JV has no voucher.

   The OC result set adds ControlNo, CheckNo, ReferenceNo (voucher no.) and
   SourceModule, read from the voucher at load time (a later correction on the
   voucher shows). Same first columns as before; the form reads OC rows only by
   ReconID / Selected, so any exe works (new columns appear automatically).

   Patches only the OC block of the live proc (exact anchor, count-guarded,
   one transaction). Backup: sp_BankRecon_GetPeriod_OLD_10022026190000.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

IF OBJECT_ID('dbo.sp_BankRecon_GetPeriod_OLD_10022026190000', 'P') IS NOT NULL
    THROW 59890, 'Already applied (sp_BankRecon_GetPeriod_OLD_10022026190000 exists).', 1;

DECLARE @def NVARCHAR(MAX) = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_BankRecon_GetPeriod')), NCHAR(13) + NCHAR(10), NCHAR(10));
IF @def IS NULL
    THROW 59891, 'Cannot read sp_BankRecon_GetPeriod''s definition; nothing changed.', 1;
IF CHARINDEX(N'2026-10-02e', @def) = 0
    THROW 59892, 'Run 2026-10-02e_BankRecon_ControlNo.sql first.', 1;

DECLARE @old NVARCHAR(MAX) = REPLACE(N'    -- OC ROWS (unchanged)
    SELECT
        BSR.ReconID,
        BSR.ItemDate,
        BSR.Payee,
        BSR.Amount,
        BSR.IsResolved
    FROM dbo.BankStatementRecon AS BSR
    INNER JOIN dbo.BankReconHeader AS H ON BSR.HeaderID = H.HeaderID
    WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd <= @PeriodEnd
      AND BSR.ItemType = ''OC''
    ORDER BY BSR.ReconID DESC;', NCHAR(13) + NCHAR(10), NCHAR(10));

DECLARE @new NVARCHAR(MAX) = REPLACE(N'    -- OC ROWS -- 2026-10-02f: + ControlNo / CheckNo / voucher no. / source, from the voucher
    SELECT
        BSR.ReconID,
        BSR.ItemDate,
        BSR.Payee,
        BSR.Amount,
        BSR.IsResolved,
        NULLIF(LTRIM(RTRIM(COALESCE(NULLIF(LTRIM(RTRIM(BSR.ControlNo)), ''''), cv.ControlNo, ca.ControlNo, tv.ControlNo))), '''') AS ControlNo,
        NULLIF(LTRIM(RTRIM(cv.CheckNo)), '''') AS CheckNo,
        BSR.ReferenceNo,
        BSR.SourceModule
    FROM dbo.BankStatementRecon AS BSR
    INNER JOIN dbo.BankReconHeader AS H ON BSR.HeaderID = H.HeaderID
    OUTER APPLY (SELECT TOP (1) x.ControlNo, x.CheckNo FROM dbo.CheckVoucher AS x
                 WHERE CAST(x.VoucherID AS VARCHAR(20)) = BSR.ReferenceNo AND CAST(x.ReferenceNumber AS VARCHAR(20)) = BSR.SourceRef
                 ORDER BY x.SequenceNumber DESC) AS cv
    OUTER APPLY (SELECT TOP (1) x.ControlNo FROM dbo.CashVoucher AS x
                 WHERE CAST(x.VoucherID AS VARCHAR(20)) = BSR.ReferenceNo AND CAST(x.ReferenceNumber AS VARCHAR(20)) = BSR.SourceRef
                 ORDER BY x.SequenceNumber DESC) AS ca
    OUTER APPLY (SELECT TOP (1) x.ControlNo FROM dbo.TelegraphicVoucher AS x
                 WHERE CAST(x.VoucherID AS VARCHAR(20)) = BSR.ReferenceNo AND CAST(x.ReferenceNumber AS VARCHAR(20)) = BSR.SourceRef
                 ORDER BY x.SequenceNumber DESC) AS tv
    WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd <= @PeriodEnd
      AND BSR.ItemType = ''OC''
    ORDER BY BSR.ReconID DESC;', NCHAR(13) + NCHAR(10), NCHAR(10));

IF (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @old, N''))) / DATALENGTH(@old) <> 1
    THROW 59893, 'sp_BankRecon_GetPeriod text differs from the 2026-10-02e version; nothing changed.', 1;

SET @def = REPLACE(@def, @old, @new);

BEGIN TRANSACTION;
    EXEC sp_rename 'dbo.sp_BankRecon_GetPeriod', 'sp_BankRecon_GetPeriod_OLD_10022026190000';
    EXEC (@def);
COMMIT TRANSACTION;

SELECT name, CONVERT(VARCHAR(19), modify_date, 120) AS modified FROM sys.objects WHERE name LIKE 'sp_BankRecon_GetPeriod%' ORDER BY name;
