/* ================================================================
   2026-10-02i: CheckVoucher.CVNo + Bank Recon hides reversed items
   ================================================================
   Replaces 2026-10-02h (VoucherCVNo table + triggers, DEV only): user decision
   2026-10-02 -- the CV # lives on CheckVoucher itself. The two screens that
   insert into CheckVoucher positionally (Accounting/AddCheckVoucher.cs,
   HOForms/TransactionPayment.cs -> sp_AddPaymentSupplier) are retired (user
   confirmed); they will fail on the extra column if ever opened again.
   Every writer still in use inserts with a column list.

   1. Removes 2026-10-02h's triggers and dbo.VoucherCVNo where present.
   2. CheckVoucher.CVNo VARCHAR(50) NULL, backfilled from NotedBy (where the CV
      number was kept as a stopgap; both DBs: every NotedBy is a CV-style code).
   3. The writers fill CVNo with the CV number they already receive:
        sp_Payment_CreateVoucherHeader (supplier payments, V2)  @CheckCoding
        sp_PostCashAdvance                                     @parmcheckcoding
        sp_AddPaymentSupplierCompound (Bank Recon auto-debit)  @parmcheckcoding
      NotedBy keeps being written as before for now (printouts may read it).
   4. sp_BankRecon_GetPeriod (recreated in full):
        - OC CV #: cheque = CVNo (else NotedBy); telegraphic / cash = ControlNo;
        - reversed items are not listed (user 2026-10-02): ResolvedReason
          'REVERSED' (reversed client payment) or 'VOIDED%' (cancelled voucher /
          reversed cash advance). They are already resolved, so the
          reconciliation totals don't change.
   One transaction. Backups: <proc>_OLD_10022026220000.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH('dbo.CheckVoucher', 'CVNo') IS NOT NULL OR OBJECT_ID('dbo.sp_BankRecon_GetPeriod_OLD_10022026220000', 'P') IS NOT NULL
    THROW 59910, 'Already applied (CheckVoucher.CVNo / _OLD_10022026220000 exist).', 1;
IF CHARINDEX(N'2026-10-02g', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_BankRecon_GetPeriod'))) = 0
    THROW 59911, 'Run 2026-10-02e, f and g first.', 1;
BEGIN TRANSACTION;
GO

------------------------------------------------------------------
-- 1. remove 2026-10-02h (DEV only)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 THROW 59919, 'An earlier step failed and its transaction was rolled back; nothing more is run.', 1;
IF OBJECT_ID('dbo.trg_CheckVoucher_CVNo', 'TR') IS NOT NULL DROP TRIGGER dbo.trg_CheckVoucher_CVNo;
IF OBJECT_ID('dbo.trg_TelegraphicVoucher_CVNo', 'TR') IS NOT NULL DROP TRIGGER dbo.trg_TelegraphicVoucher_CVNo;
IF OBJECT_ID('dbo.trg_CashVoucher_CVNo', 'TR') IS NOT NULL DROP TRIGGER dbo.trg_CashVoucher_CVNo;
IF OBJECT_ID('dbo.VoucherCVNo', 'U') IS NOT NULL DROP TABLE dbo.VoucherCVNo;
GO

------------------------------------------------------------------
-- 2. the column + backfill
------------------------------------------------------------------
IF @@TRANCOUNT = 0 THROW 59919, 'An earlier step failed and its transaction was rolled back; nothing more is run.', 1;
ALTER TABLE dbo.CheckVoucher ADD CVNo VARCHAR(50) NULL;
GO
IF @@TRANCOUNT = 0 THROW 59919, 'An earlier step failed and its transaction was rolled back; nothing more is run.', 1;
UPDATE dbo.CheckVoucher SET CVNo = NULLIF(LTRIM(RTRIM(NotedBy)), '') WHERE CVNo IS NULL;
PRINT 'CheckVoucher.CVNo filled: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
GO

------------------------------------------------------------------
-- 3. writers fill CVNo (exact anchors, count-guarded)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 THROW 59919, 'An earlier step failed and its transaction was rolled back; nothing more is run.', 1;
IF OBJECT_ID('tempdb..#P') IS NOT NULL DROP TABLE #P;
CREATE TABLE #P (Id INT IDENTITY PRIMARY KEY, ProcName SYSNAME, OldText NVARCHAR(MAX), NewText NVARCHAR(MAX));
INSERT #P (ProcName, OldText, NewText) VALUES
('sp_Payment_CreateVoucherHeader',
 N'             DateAdded, DateUpdate, isErrorCorrect, isLiquidation, ControlNo, CreditGLCode)',
 N'             DateAdded, DateUpdate, isErrorCorrect, isLiquidation, ControlNo, CreditGLCode, CVNo)   -- 2026-10-02i'),
('sp_Payment_CreateVoucherHeader',
 N'             @Particulars, @Amount, @PreparedBy, '''', @CheckCoding, '''', '''', @GLCode, ''CHECK'', NULL,
             GETDATE(), GETDATE(), 0, @ForLiquidation,@CheckOrControlNo,@GLCode);',
 N'             @Particulars, @Amount, @PreparedBy, '''', @CheckCoding, '''', '''', @GLCode, ''CHECK'', NULL,
             GETDATE(), GETDATE(), 0, @ForLiquidation,@CheckOrControlNo,@GLCode, NULLIF(LTRIM(RTRIM(@CheckCoding)), ''''));'),
('sp_PostCashAdvance',
 N'                     PaymentReceivedBy, OfficialReceiptNo, VoucherType, DateReceived,
                     DateAdded, DateUpdate, isErrorCorrect, isLiquidation)',
 N'                     PaymentReceivedBy, OfficialReceiptNo, VoucherType, DateReceived,
                     DateAdded, DateUpdate, isErrorCorrect, isLiquidation, CVNo)   -- 2026-10-02i'),
('sp_PostCashAdvance',
 N'                     @parmuser, '''', @parmcheckcoding, '''', '''', @parmcreditaccount, ''CHECK'', NULL, GETDATE(), GETDATE(), 0, 1);',
 N'                     @parmuser, '''', @parmcheckcoding, '''', '''', @parmcreditaccount, ''CHECK'', NULL, GETDATE(), GETDATE(), 0, 1, NULLIF(LTRIM(RTRIM(@parmcheckcoding)), ''''));'),
('sp_AddPaymentSupplierCompound',
 N'                 PaymentReceivedBy, OfficialReceiptNo, VoucherType, DateReceived,
                 DateAdded, DateUpdate, isErrorCorrect, isLiquidation)',
 N'                 PaymentReceivedBy, OfficialReceiptNo, VoucherType, DateReceived,
                 DateAdded, DateUpdate, isErrorCorrect, isLiquidation, CVNo)   -- 2026-10-02i'),
('sp_AddPaymentSupplierCompound',
 N'                   @parmpaymethod, '''', GETDATE(), GETDATE(), 0, @parmforliquidation);',
 N'                   @parmpaymethod, '''', GETDATE(), GETDATE(), 0, @parmforliquidation, NULLIF(LTRIM(RTRIM(@parmcheckcoding)), ''''));');

IF OBJECT_ID('tempdb..#Def') IS NOT NULL DROP TABLE #Def;
SELECT DISTINCT p.ProcName, REPLACE(OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + p.ProcName)), NCHAR(13) + NCHAR(10), NCHAR(10)) AS Def
INTO #Def FROM #P AS p;
UPDATE #P SET OldText = REPLACE(OldText, NCHAR(13) + NCHAR(10), NCHAR(10)), NewText = REPLACE(NewText, NCHAR(13) + NCHAR(10), NCHAR(10));

IF EXISTS (SELECT 1 FROM #Def WHERE Def IS NULL)
    THROW 59912, 'A writer procedure is missing or unreadable; nothing changed.', 1;
IF EXISTS (SELECT 1 FROM #P AS p INNER JOIN #Def AS d ON d.ProcName = p.ProcName
           WHERE (DATALENGTH(d.Def) - DATALENGTH(REPLACE(d.Def, p.OldText, N''))) / DATALENGTH(p.OldText) <> 1)
BEGIN
    SELECT p.ProcName, p.OldText FROM #P AS p INNER JOIN #Def AS d ON d.ProcName = p.ProcName
    WHERE (DATALENGTH(d.Def) - DATALENGTH(REPLACE(d.Def, p.OldText, N''))) / DATALENGTH(p.OldText) <> 1;
    THROW 59913, 'A writer procedure''s text differs from the version this script was written for; nothing changed.', 1;
END

DECLARE @name SYSNAME, @def NVARCHAR(MAX), @old NVARCHAR(MAX), @new NVARCHAR(MAX), @bak NVARCHAR(300), @newName SYSNAME;
DECLARE pc CURSOR LOCAL FAST_FORWARD FOR SELECT ProcName, Def FROM #Def ORDER BY ProcName;
OPEN pc; FETCH NEXT FROM pc INTO @name, @def;
WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE rc CURSOR LOCAL FAST_FORWARD FOR SELECT OldText, NewText FROM #P WHERE ProcName = @name ORDER BY Id;
    OPEN rc; FETCH NEXT FROM rc INTO @old, @new;
    WHILE @@FETCH_STATUS = 0 BEGIN SET @def = REPLACE(@def, @old, @new); FETCH NEXT FROM rc INTO @old, @new; END
    CLOSE rc; DEALLOCATE rc;
    SET @bak = N'dbo.' + @name; SET @newName = @name + N'_OLD_10022026220000';
    EXEC sp_rename @bak, @newName;
    EXEC (@def);
    FETCH NEXT FROM pc INTO @name, @def;
END
CLOSE pc; DEALLOCATE pc;
GO

------------------------------------------------------------------
-- 4. sp_BankRecon_GetPeriod, recreated in full
------------------------------------------------------------------
IF @@TRANCOUNT = 0 THROW 59919, 'An earlier step failed and its transaction was rolled back; nothing more is run.', 1;
EXEC sp_rename 'dbo.sp_BankRecon_GetPeriod', 'sp_BankRecon_GetPeriod_OLD_10022026220000';
GO

CREATE PROCEDURE dbo.sp_BankRecon_GetPeriod
    @BranchCode  CHAR(3),
    @AccountCode VARCHAR(20),
    @PeriodEnd   DATE
AS
/*
    Result sets for AccountingDevEx/BankReconFormV2: header, DIT rows, OC rows,
    bank-side rows.
    - DIT rows carry the client payment's ControlNo / CRNo / PaymentType (2026-10-02e).
    - OC rows carry the issuing voucher's ControlNo / CheckNo / CV # (2026-10-02f/g/i):
      CV # = CheckVoucher.CVNo (else NotedBy) for cheques, ControlNo for telegraphic / cash.
    - Reversed items are not listed (2026-10-02i): ResolvedReason 'REVERSED' or 'VOIDED%'.
*/
BEGIN
    SET NOCOUNT ON;

    -- HEADER
    SELECT
        H.HeaderID, H.BranchCode, H.AccountCode,
        CA.Description AS AccountName,
        H.PeriodEnd, H.BankStatementBal, H.GLBookBalance, H.Status, H.Remarks,
        ISNULL(DIT.TotalDIT, 0) AS TotalDIT,
        ISNULL(OC.TotalOC,   0) AS TotalOC,
        H.BankStatementBal + ISNULL(DIT.TotalDIT, 0) - ISNULL(OC.TotalOC, 0) AS AdjustedBankBalance,
        H.GLBookBalance - (H.BankStatementBal + ISNULL(DIT.TotalDIT, 0) - ISNULL(OC.TotalOC, 0)) AS Difference,
        CASE WHEN H.GLBookBalance = (H.BankStatementBal + ISNULL(DIT.TotalDIT, 0) - ISNULL(OC.TotalOC, 0))
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsReconciled
    FROM dbo.BankReconHeader AS H
    LEFT JOIN dbo.ChartOfAccounts AS CA ON CA.AccountCode = H.AccountCode
    OUTER APPLY (SELECT ISNULL(SUM(Amount), 0) AS TotalDIT
                 FROM dbo.BankStatementRecon WHERE HeaderID = H.HeaderID AND ItemType = 'DIT') AS DIT
    OUTER APPLY (SELECT ISNULL(SUM(Amount), 0) AS TotalOC
                 FROM dbo.BankStatementRecon WHERE HeaderID = H.HeaderID AND ItemType = 'OC') AS OC
    WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd <= @PeriodEnd;

    -- DIT ROWS
    SELECT
        BSR.ReconID,
        BSR.ItemDate,
        COALESCE(NULLIF(LTRIM(RTRIM(BSR.ControlNo)), ''), NULLIF(LTRIM(RTRIM(ph.ControlNo)), '')) AS ControlNo,
        NULLIF(LTRIM(RTRIM(ph.CRNo)), '') AS CRNo,
        BSR.ReferenceNo,
        BSR.Payee,
        ph.PaymentType,
        BSR.Amount,
        BSR.IsResolved,
        BSR.ResolvedReason,
        CASE WHEN BSR.SourceModule IS NOT NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsAutoInserted
    FROM dbo.BankStatementRecon AS BSR
    INNER JOIN dbo.BankReconHeader AS H ON BSR.HeaderID = H.HeaderID
    OUTER APPLY (SELECT TOP (1) p.ControlNo, p.CRNo, p.PaymentType
                 FROM dbo.PaymentHeader AS p
                 WHERE BSR.SourceModule = 'AR-PAYMENT' AND p.ReferenceNo = BSR.SourceRef
                 ORDER BY p.PaymentHeaderID DESC) AS ph
    WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd <= @PeriodEnd
      AND BSR.ItemType = 'DIT'
      AND ISNULL(BSR.ResolvedReason, '') <> 'REVERSED' AND ISNULL(BSR.ResolvedReason, '') NOT LIKE 'VOIDED%'
    ORDER BY BSR.ReconID DESC;

    -- OC ROWS
    SELECT
        BSR.ReconID,
        BSR.ItemDate,
        BSR.Payee,
        BSR.Amount,
        BSR.IsResolved,
        NULLIF(LTRIM(RTRIM(COALESCE(NULLIF(LTRIM(RTRIM(BSR.ControlNo)), ''), cv.ControlNo, ca.ControlNo, tv.ControlNo))), '') AS ControlNo,
        NULLIF(LTRIM(RTRIM(cv.CheckNo)), '') AS CheckNo,
        NULLIF(LTRIM(RTRIM(CASE WHEN cv.HasRow = 1 THEN COALESCE(NULLIF(LTRIM(RTRIM(cv.CVNo)), ''), cv.NotedBy)
                                WHEN tv.HasRow = 1 THEN tv.ControlNo
                                WHEN ca.HasRow = 1 THEN ca.ControlNo END)), '') AS CVNo,
        BSR.ReferenceNo,
        BSR.SourceModule
    FROM dbo.BankStatementRecon AS BSR
    INNER JOIN dbo.BankReconHeader AS H ON BSR.HeaderID = H.HeaderID
    OUTER APPLY (SELECT TOP (1) x.ControlNo, x.CheckNo, x.CVNo, x.NotedBy, 1 AS HasRow FROM dbo.CheckVoucher AS x
                 WHERE CAST(x.VoucherID AS VARCHAR(20)) = BSR.ReferenceNo AND CAST(x.ReferenceNumber AS VARCHAR(20)) = BSR.SourceRef
                 ORDER BY x.SequenceNumber DESC) AS cv
    OUTER APPLY (SELECT TOP (1) x.ControlNo, 1 AS HasRow FROM dbo.CashVoucher AS x
                 WHERE CAST(x.VoucherID AS VARCHAR(20)) = BSR.ReferenceNo AND CAST(x.ReferenceNumber AS VARCHAR(20)) = BSR.SourceRef
                 ORDER BY x.SequenceNumber DESC) AS ca
    OUTER APPLY (SELECT TOP (1) x.ControlNo, 1 AS HasRow FROM dbo.TelegraphicVoucher AS x
                 WHERE CAST(x.VoucherID AS VARCHAR(20)) = BSR.ReferenceNo AND CAST(x.ReferenceNumber AS VARCHAR(20)) = BSR.SourceRef
                 ORDER BY x.SequenceNumber DESC) AS tv
    WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd <= @PeriodEnd
      AND BSR.ItemType = 'OC'
      AND ISNULL(BSR.ResolvedReason, '') <> 'REVERSED' AND ISNULL(BSR.ResolvedReason, '') NOT LIKE 'VOIDED%'
    ORDER BY BSR.ReconID DESC;

    -- BANK-SIDE ROWS (BCM / BDM / BC / NSF / ADB) (unchanged)
    SELECT BSR.ReconID, BSR.HeaderID, BSR.ItemType, BSR.ItemDate, BSR.Payee, BSR.ReferenceNo,
           BSR.Amount, BSR.IsResolved, BSR.ResolvedDate, BSR.ResolvedReason,
           BSR.SourceModule, BSR.SourceRef, BSR.CreatedBy, BSR.CreatedDate,
           BSR.PostedPaymentRef,
           CASE WHEN BSR.SourceModule IS NOT NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsAutoInserted
    FROM dbo.BankStatementRecon AS BSR
    INNER JOIN dbo.BankReconHeader AS H ON BSR.HeaderID = H.HeaderID
    WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd <= @PeriodEnd
      AND BSR.ItemType IN ('BCM', 'BDM', 'BC', 'NSF', 'ADB')
    ORDER BY BSR.ReconID DESC;
END
GO

IF @@TRANCOUNT = 0 THROW 59919, 'An earlier step failed and its transaction was rolled back; nothing more is run.', 1;
COMMIT TRANSACTION;
GO

SELECT 'CheckVoucher with CVNo' AS x, COUNT(*) AS vouchers, SUM(CASE WHEN CVNo IS NOT NULL THEN 1 ELSE 0 END) AS withCVNo FROM dbo.CheckVoucher;
SELECT name, CONVERT(VARCHAR(19), modify_date, 120) AS modified FROM sys.objects
WHERE name IN ('sp_Payment_CreateVoucherHeader', 'sp_PostCashAdvance', 'sp_AddPaymentSupplierCompound', 'sp_BankRecon_GetPeriod') ORDER BY name;
