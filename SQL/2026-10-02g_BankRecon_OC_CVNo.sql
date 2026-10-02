/* ================================================================
   2026-10-02g: Bank Recon — Outstanding Checks show the CV #
   ================================================================
   Needs 2026-10-02f (OC rows with ControlNo / CheckNo from the voucher).

   The CV number is stored, for now, in the voucher's NotedBy column:
   sp_Payment_CreateVoucherHeader writes @CheckCoding into
   CheckVoucher.NotedBy / TelegraphicVoucher.NotedBy (e.g. CV2608-112BDO2384522),
   and @CheckOrControlNo into ControlNo. User rule (2026-10-02):
     CHECK       -> CV # = CheckVoucher.NotedBy
     TELEGRAPHIC -> CV # = TelegraphicVoucher.ControlNo
     CASH        -> CV # = CashVoucher.ControlNo (NotedBy holds the same value)
   Adds a CVNo column to the OC result set of sp_BankRecon_GetPeriod (any exe
   shows it; the form reads OC rows only by ReconID / Selected).

   Patches only the OC block (exact anchor, count-guarded, one transaction).
   Backup: sp_BankRecon_GetPeriod_OLD_10022026200000.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

IF OBJECT_ID('dbo.sp_BankRecon_GetPeriod_OLD_10022026200000', 'P') IS NOT NULL
    THROW 59895, 'Already applied (sp_BankRecon_GetPeriod_OLD_10022026200000 exists).', 1;

DECLARE @def NVARCHAR(MAX) = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_BankRecon_GetPeriod')), NCHAR(13) + NCHAR(10), NCHAR(10));
IF @def IS NULL
    THROW 59896, 'Cannot read sp_BankRecon_GetPeriod''s definition; nothing changed.', 1;
IF CHARINDEX(N'2026-10-02f', @def) = 0
    THROW 59897, 'Run 2026-10-02f_BankRecon_OC_ControlNo.sql first.', 1;

DECLARE @p TABLE (Id INT IDENTITY, OldText NVARCHAR(MAX), NewText NVARCHAR(MAX));
INSERT @p (OldText, NewText) VALUES
-- the CV # column, right after CheckNo
(N'        NULLIF(LTRIM(RTRIM(cv.CheckNo)), '''') AS CheckNo,',
 N'        NULLIF(LTRIM(RTRIM(cv.CheckNo)), '''') AS CheckNo,
        -- 2026-10-02g: CV # -- cheque: NotedBy (where the CV no. is kept for now); telegraphic / cash: ControlNo
        NULLIF(LTRIM(RTRIM(CASE WHEN cv.HasRow = 1 THEN cv.NotedBy
                                WHEN tv.HasRow = 1 THEN tv.ControlNo
                                WHEN ca.HasRow = 1 THEN ca.ControlNo END)), '''') AS CVNo,'),
-- the voucher lookups also return NotedBy and a found-flag
(N'    OUTER APPLY (SELECT TOP (1) x.ControlNo, x.CheckNo FROM dbo.CheckVoucher AS x',
 N'    OUTER APPLY (SELECT TOP (1) x.ControlNo, x.CheckNo, x.NotedBy, 1 AS HasRow FROM dbo.CheckVoucher AS x'),
(N'    OUTER APPLY (SELECT TOP (1) x.ControlNo FROM dbo.CashVoucher AS x',
 N'    OUTER APPLY (SELECT TOP (1) x.ControlNo, 1 AS HasRow FROM dbo.CashVoucher AS x'),
(N'    OUTER APPLY (SELECT TOP (1) x.ControlNo FROM dbo.TelegraphicVoucher AS x',
 N'    OUTER APPLY (SELECT TOP (1) x.ControlNo, 1 AS HasRow FROM dbo.TelegraphicVoucher AS x');

IF EXISTS (SELECT 1 FROM @p WHERE (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, OldText, N''))) / DATALENGTH(OldText) <> 1)
    THROW 59898, 'sp_BankRecon_GetPeriod text differs from the 2026-10-02f version; nothing changed.', 1;

DECLARE @o NVARCHAR(MAX), @n NVARCHAR(MAX);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT OldText, NewText FROM @p ORDER BY Id;
OPEN c; FETCH NEXT FROM c INTO @o, @n;
WHILE @@FETCH_STATUS = 0 BEGIN SET @def = REPLACE(@def, @o, @n); FETCH NEXT FROM c INTO @o, @n; END
CLOSE c; DEALLOCATE c;

BEGIN TRANSACTION;
    EXEC sp_rename 'dbo.sp_BankRecon_GetPeriod', 'sp_BankRecon_GetPeriod_OLD_10022026200000';
    EXEC (@def);
COMMIT TRANSACTION;

SELECT name, CONVERT(VARCHAR(19), modify_date, 120) AS modified FROM sys.objects WHERE name LIKE 'sp_BankRecon_GetPeriod%' ORDER BY name;
