/* SUPERSEDED 2026-10-02 by 2026-10-02i_CheckVoucher_CVNo.sql (user: CV # lives on CheckVoucher.CVNo;
   the retired screens that blocked a new column are not used). DEV only -- removed there by 2i.
   Do NOT run on STAGING. */
/* ================================================================
   2026-10-02h: VoucherCVNo — the CV # in its own table
   ================================================================
   Needs 2026-10-02g (Bank Recon OC rows show the CV #).

   The CV number has been kept in the vouchers' NotedBy column as a stopgap
   (sp_Payment_CreateVoucherHeader writes @CheckCoding there). A new column on
   CheckVoucher is NOT safe: Accounting/AddCheckVoucher.cs and
   HOForms/TransactionPayment.cs (both still on the menu) insert into
   CheckVoucher positionally, so one more column makes every save there fail.
   User decision (2026-10-02): a separate table.

   dbo.VoucherCVNo (VoucherType, VoucherID, ReferenceNumber) -> CVNo
     CHECK        CVNo = CheckVoucher.NotedBy
     TELEGRAPHIC  CVNo = TelegraphicVoucher.ControlNo
     CASH         CVNo = CashVoucher.ControlNo
   - backfilled from the three voucher tables;
   - kept current by AFTER INSERT, UPDATE triggers on each voucher table, so
     every screen and procedure that writes a voucher (the V2 payment, cash
     advance, manual voucher, the two older screens, the legacy procs) fills it
     without being changed;
   - sp_BankRecon_GetPeriod's OC CV # reads it first (falls back to the voucher).
   When the payment screen gets its own CV # field, its proc can write this
   table directly and the triggers can stop copying from NotedBy.

   One transaction; backup sp_BankRecon_GetPeriod_OLD_10022026210000.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.VoucherCVNo', 'U') IS NOT NULL
    THROW 59900, 'Already applied (dbo.VoucherCVNo exists).', 1;
IF CHARINDEX(N'2026-10-02g', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_BankRecon_GetPeriod'))) = 0
    THROW 59901, 'Run 2026-10-02g_BankRecon_OC_CVNo.sql first.', 1;
BEGIN TRANSACTION;
GO

IF @@TRANCOUNT = 0 THROW 59909, 'An earlier step failed and its transaction was rolled back; nothing more is run.', 1;
CREATE TABLE dbo.VoucherCVNo (
    VoucherType     VARCHAR(12)   NOT NULL,          -- CHECK / TELEGRAPHIC / CASH
    VoucherID       DECIMAL(7,0)  NOT NULL,
    ReferenceNumber VARCHAR(50)   NOT NULL,          -- the payment reference (trimmed)
    CVNo            VARCHAR(100)  NULL,
    UpdatedAt       DATETIME      NOT NULL CONSTRAINT DF_VoucherCVNo_UpdatedAt DEFAULT (GETDATE()),
    CONSTRAINT PK_VoucherCVNo PRIMARY KEY (VoucherType, VoucherID, ReferenceNumber)
);

INSERT INTO dbo.VoucherCVNo (VoucherType, VoucherID, ReferenceNumber, CVNo)
SELECT 'CHECK', VoucherID, LTRIM(RTRIM(ReferenceNumber)), NULLIF(LTRIM(RTRIM(NotedBy)), '') FROM dbo.CheckVoucher
UNION ALL
SELECT 'TELEGRAPHIC', VoucherID, LTRIM(RTRIM(ReferenceNumber)), NULLIF(LTRIM(RTRIM(ControlNo)), '') FROM dbo.TelegraphicVoucher
UNION ALL
SELECT 'CASH', VoucherID, LTRIM(RTRIM(ReferenceNumber)), NULLIF(LTRIM(RTRIM(ControlNo)), '') FROM dbo.CashVoucher;
PRINT 'VoucherCVNo backfilled: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
GO

CREATE TRIGGER dbo.trg_CheckVoucher_CVNo ON dbo.CheckVoucher AFTER INSERT, UPDATE
AS
/* Keeps dbo.VoucherCVNo current: a cheque voucher's CV # is its NotedBy (2026-10-02h). */
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;
    MERGE dbo.VoucherCVNo AS t
    USING (SELECT DISTINCT 'CHECK' AS VoucherType, VoucherID, LTRIM(RTRIM(ReferenceNumber)) AS ReferenceNumber,
                  NULLIF(LTRIM(RTRIM(NotedBy)), '') AS CVNo
           FROM inserted WHERE VoucherID IS NOT NULL AND ReferenceNumber IS NOT NULL) AS s
       ON t.VoucherType = s.VoucherType AND t.VoucherID = s.VoucherID AND t.ReferenceNumber = s.ReferenceNumber
    WHEN MATCHED AND ISNULL(t.CVNo, '') <> ISNULL(s.CVNo, '') THEN UPDATE SET CVNo = s.CVNo, UpdatedAt = GETDATE()
    WHEN NOT MATCHED THEN INSERT (VoucherType, VoucherID, ReferenceNumber, CVNo) VALUES (s.VoucherType, s.VoucherID, s.ReferenceNumber, s.CVNo);
END
GO

CREATE TRIGGER dbo.trg_TelegraphicVoucher_CVNo ON dbo.TelegraphicVoucher AFTER INSERT, UPDATE
AS
/* Keeps dbo.VoucherCVNo current: a telegraphic voucher's CV # is its ControlNo (2026-10-02h). */
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;
    MERGE dbo.VoucherCVNo AS t
    USING (SELECT DISTINCT 'TELEGRAPHIC' AS VoucherType, VoucherID, LTRIM(RTRIM(ReferenceNumber)) AS ReferenceNumber,
                  NULLIF(LTRIM(RTRIM(ControlNo)), '') AS CVNo
           FROM inserted WHERE VoucherID IS NOT NULL AND ReferenceNumber IS NOT NULL) AS s
       ON t.VoucherType = s.VoucherType AND t.VoucherID = s.VoucherID AND t.ReferenceNumber = s.ReferenceNumber
    WHEN MATCHED AND ISNULL(t.CVNo, '') <> ISNULL(s.CVNo, '') THEN UPDATE SET CVNo = s.CVNo, UpdatedAt = GETDATE()
    WHEN NOT MATCHED THEN INSERT (VoucherType, VoucherID, ReferenceNumber, CVNo) VALUES (s.VoucherType, s.VoucherID, s.ReferenceNumber, s.CVNo);
END
GO

CREATE TRIGGER dbo.trg_CashVoucher_CVNo ON dbo.CashVoucher AFTER INSERT, UPDATE
AS
/* Keeps dbo.VoucherCVNo current: a cash voucher's CV # is its ControlNo (2026-10-02h). */
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;
    MERGE dbo.VoucherCVNo AS t
    USING (SELECT DISTINCT 'CASH' AS VoucherType, VoucherID, LTRIM(RTRIM(ReferenceNumber)) AS ReferenceNumber,
                  NULLIF(LTRIM(RTRIM(ControlNo)), '') AS CVNo
           FROM inserted WHERE VoucherID IS NOT NULL AND ReferenceNumber IS NOT NULL) AS s
       ON t.VoucherType = s.VoucherType AND t.VoucherID = s.VoucherID AND t.ReferenceNumber = s.ReferenceNumber
    WHEN MATCHED AND ISNULL(t.CVNo, '') <> ISNULL(s.CVNo, '') THEN UPDATE SET CVNo = s.CVNo, UpdatedAt = GETDATE()
    WHEN NOT MATCHED THEN INSERT (VoucherType, VoucherID, ReferenceNumber, CVNo) VALUES (s.VoucherType, s.VoucherID, s.ReferenceNumber, s.CVNo);
END
GO

------------------------------------------------------------------
-- sp_BankRecon_GetPeriod: OC CV # reads VoucherCVNo first
------------------------------------------------------------------
IF @@TRANCOUNT = 0 THROW 59909, 'An earlier step failed and its transaction was rolled back; nothing more is run.', 1;
DECLARE @def NVARCHAR(MAX) = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_BankRecon_GetPeriod')), NCHAR(13) + NCHAR(10), NCHAR(10));
IF @def IS NULL THROW 59902, 'Cannot read sp_BankRecon_GetPeriod''s definition.', 1;

DECLARE @p TABLE (Id INT IDENTITY, OldText NVARCHAR(MAX), NewText NVARCHAR(MAX));
INSERT @p (OldText, NewText) VALUES
(N'        NULLIF(LTRIM(RTRIM(CASE WHEN cv.HasRow = 1 THEN cv.NotedBy',
 N'        NULLIF(LTRIM(RTRIM(COALESCE(k.CVNo,   -- 2026-10-02h: dbo.VoucherCVNo first
                           CASE WHEN cv.HasRow = 1 THEN cv.NotedBy'),
(N'                                WHEN ca.HasRow = 1 THEN ca.ControlNo END)), '''') AS CVNo,',
 N'                                WHEN ca.HasRow = 1 THEN ca.ControlNo END))), '''') AS CVNo,'),
(N'                 ORDER BY x.SequenceNumber DESC) AS tv',
 N'                 ORDER BY x.SequenceNumber DESC) AS tv
    OUTER APPLY (SELECT TOP (1) v.CVNo FROM dbo.VoucherCVNo AS v
                 WHERE CAST(v.VoucherID AS VARCHAR(20)) = BSR.ReferenceNo AND v.ReferenceNumber = LTRIM(RTRIM(BSR.SourceRef))
                   AND v.VoucherType = CASE WHEN cv.HasRow = 1 THEN ''CHECK'' WHEN tv.HasRow = 1 THEN ''TELEGRAPHIC''
                                            WHEN ca.HasRow = 1 THEN ''CASH'' END) AS k');

IF EXISTS (SELECT 1 FROM @p WHERE (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, OldText, N''))) / DATALENGTH(OldText) <> 1)
    THROW 59903, 'sp_BankRecon_GetPeriod text differs from the 2026-10-02g version; nothing changed.', 1;

DECLARE @o NVARCHAR(MAX), @n NVARCHAR(MAX);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT OldText, NewText FROM @p ORDER BY Id;
OPEN c; FETCH NEXT FROM c INTO @o, @n;
WHILE @@FETCH_STATUS = 0 BEGIN SET @def = REPLACE(@def, @o, @n); FETCH NEXT FROM c INTO @o, @n; END
CLOSE c; DEALLOCATE c;

EXEC sp_rename 'dbo.sp_BankRecon_GetPeriod', 'sp_BankRecon_GetPeriod_OLD_10022026210000';
EXEC (@def);
GO

IF @@TRANCOUNT = 0 THROW 59909, 'An earlier step failed and its transaction was rolled back; nothing more is run.', 1;
COMMIT TRANSACTION;
GO

SELECT VoucherType, COUNT(*) AS vouchers, SUM(CASE WHEN CVNo IS NOT NULL THEN 1 ELSE 0 END) AS withCVNo FROM dbo.VoucherCVNo GROUP BY VoucherType;
