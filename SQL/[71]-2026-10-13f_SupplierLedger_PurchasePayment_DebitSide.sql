/* ================================================================
   [71] 2026-10-13f - Supplier ledger: purchase payments are written as a DEBIT (proc fix + data repair)
   ================================================================
   Found by the Exception Center AP check AP-LEDGER-PAYMENT-SIDE ([70]) on 2026-10-13.

   Cause: sp_PostCompoundTicket's supplier-ledger back-write is hard-coded Debit 0 / Credit = GROSS, i.e. it treats
   every ledger row as a new payable. Right for the accrual callers (SP_POSTINVENTORY, sp_FinalizeInventoryUpload),
   wrong for the two purchase-payment callers, which call it with @LedgerType = 'SUPPLIER' on their PV-AP leg:
     sp_AddPaymentSupplierCompound_V2  (SupplierPaymentDevEx, CombinedSupplierVoucherFrm; PURCHASE mode)
     sp_AddPaymentSupplierCompound     (HOFormsDevEx/SupplierPaymentDevEx, BankReconFormV2 auto-debit Post Payment;
                                        its EXPENSE payments write their own SNGLE-PAY debits and were right)
   A payment reduces the payable, so its row must be a debit. PRODUCTION: 4 rows (4,363,758.48: DR-00565-TVP,
   RF-2241 BELLY, SI-457557-FRIES, SI-457594-FRIES), each supplier's balance overstated by twice the payment
   (8,727,516.96). The GL tickets and cheques were right; only the supplier ledger is affected.

   Fix (backward compatible, no exe change):
     1. sp_PostCompoundTicket: new optional @LedgerSide CHAR(1) = 'C' ('C' = today's behaviour; 'D' = a payment).
        Any other value is refused (50026).
     2. sp_AddPaymentSupplierCompound_V2 and sp_AddPaymentSupplierCompound pass @LedgerSide = 'D' on their PV-AP call.
     3. Data: the existing payment rows written this way (TransCode PV-AP%, PaymentType COMPOUND, Debit 0, Credit > 0,
        not tagged, voucher not reversed) become Debit = the amount, Credit 0. trg_SupplierLedger_Recalc ([17])
        recomputes each affected supplier's chain and SupplierAccounts balance. Refused if such a row belongs to a
        reversed voucher (its reversal mirror would then be on the wrong side): 59981.
   Anchor patches on the live text (nothing changes if the text differs); backups _OLD_10132026210000; data backup
   SupplierLedger_PVAPSide_Backup_20261013. One transaction with a post-check. DEV, then STAGING (user's go), then
   PRODUCTION (user).
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
BEGIN TRANSACTION;
CREATE TABLE #Patch (Id INT IDENTITY PRIMARY KEY, Obj SYSNAME NOT NULL, OldText NVARCHAR(MAX) NOT NULL, NewText NVARCHAR(MAX) NOT NULL);
GO

CREATE PROCEDURE #ApplyPatch @Obj SYSNAME
AS
BEGIN
    DECLARE @def NVARCHAR(MAX) = REPLACE(OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + @Obj)), NCHAR(13) + NCHAR(10), NCHAR(10));
    DECLARE @msg NVARCHAR(400);
    IF @def IS NULL
    BEGIN
        SET @msg = N'Cannot read the definition of ' + @Obj + N'; nothing changed.';
        THROW 59960, @msg, 1;
    END
    IF EXISTS (SELECT 1 FROM #Patch WHERE Obj = @Obj
               AND (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, OldText, N''))) / DATALENGTH(OldText) <> 1)
    BEGIN
        SET @msg = @Obj + N' text differs from the expected version (an anchor is missing or repeated); nothing changed.';
        THROW 59961, @msg, 1;
    END
    DECLARE @o NVARCHAR(MAX), @n NVARCHAR(MAX);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT OldText, NewText FROM #Patch WHERE Obj = @Obj ORDER BY Id;
    OPEN c; FETCH NEXT FROM c INTO @o, @n;
    WHILE @@FETCH_STATUS = 0 BEGIN SET @def = REPLACE(@def, @o, @n); FETCH NEXT FROM c INTO @o, @n; END
    CLOSE c; DEALLOCATE c;
    DECLARE @old SYSNAME = @Obj + N'_OLD_10132026210000', @full NVARCHAR(300) = N'dbo.' + @Obj;
    EXEC sp_rename @full, @old;
    EXEC (@def);
    IF OBJECT_ID(@full) IS NULL
    BEGIN
        SET @msg = @Obj + N' was not recreated.';
        THROW 59962, @msg, 1;
    END
END
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
IF OBJECT_ID('dbo.sp_PostCompoundTicket_OLD_10132026210000', 'P') IS NOT NULL OR OBJECT_ID('dbo.SupplierLedger_PVAPSide_Backup_20261013', 'U') IS NOT NULL
BEGIN
    RAISERROR('[71] has been run here before (sp_PostCompoundTicket_OLD_10132026210000 or the backup table exists).', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── 1. sp_PostCompoundTicket: @LedgerSide ────────────────────────────
DECLARE @LF NCHAR(1) = NCHAR(10);
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_PostCompoundTicket',
    N'@LedgerSeqRef       INT            = NULL',
    N'@LedgerSeqRef       INT            = NULL,' + @LF +
    N'    @LedgerSide         CHAR(1)        = ''C''    -- 2026-10-13f [71]: ''C'' = a payable (accrual, default), ''D'' = a payment');
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_PostCompoundTicket',
    N'        SELECT @GrossAmount = Amount FROM @Amounts WHERE AmountType = ''GROSS'';',
    N'        IF ISNULL(@LedgerSide, '''') NOT IN (''C'', ''D'')' + @LF +
    N'            THROW 50026, ''@LedgerSide must be C (payable) or D (payment).'', 1;' + @LF +
    N'' + @LF +
    N'        SELECT @GrossAmount = Amount FROM @Amounts WHERE AmountType = ''GROSS'';');
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_PostCompoundTicket',
    N'                0, 0, @GrossAmount, 0,',
    N'                0, CASE WHEN @LedgerSide = ''D'' THEN @GrossAmount ELSE 0 END,   -- 2026-10-13f [71]: a payment is a debit' + @LF +
    N'                   CASE WHEN @LedgerSide = ''D'' THEN 0 ELSE @GrossAmount END, 0,');
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'sp_PostCompoundTicket';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── 2. the two purchase-payment callers pass 'D' ────────────────────
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_AddPaymentSupplierCompound_V2',
    N'@LedgerSeqRef=@pSeqRef;',
    N'@LedgerSeqRef=@pSeqRef, @LedgerSide=''D'';   -- 2026-10-13f [71]: the payment row is a debit');
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_AddPaymentSupplierCompound',
    N'@LedgerSeqRef=@SeqRef;',
    N'@LedgerSeqRef=@SeqRef, @LedgerSide=''D'';   -- 2026-10-13f [71]: the payment row is a debit');
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'sp_AddPaymentSupplierCompound_V2';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'sp_AddPaymentSupplierCompound';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── 3. data: the payment rows already written as credits ───────────
SELECT s.TRN_SEQ_NO, s.SupplierKey, s.InvoiceNo, s.ReferenceNumber, s.TransCode, s.Debit, s.Credit,
       CASE WHEN EXISTS (SELECT 1 FROM dbo.PaymentReversalAudit r
                         WHERE LTRIM(RTRIM(CAST(r.ReferenceNumber AS VARCHAR(30)))) = LTRIM(RTRIM(s.ReferenceNumber)) AND r.SupplierID = s.SupplierKey)
            THEN 1 ELSE 0 END AS IsReversed
INTO #R71
FROM dbo.SupplierLedger s
WHERE s.TransCode LIKE 'PV-AP%' AND s.PaymentType = 'COMPOUND' AND ISNULL(s.Debit, 0) = 0 AND s.Credit > 0 AND ISNULL(s.ErrorCorrectTag, 0) = 0;

SELECT TRN_SEQ_NO, SupplierKey, InvoiceNo, ReferenceNumber, TransCode, Credit AS WasCredit, IsReversed FROM #R71 ORDER BY SupplierKey, TRN_SEQ_NO;
IF EXISTS (SELECT 1 FROM #R71 WHERE IsReversed = 1)
BEGIN
    RAISERROR('A PV-AP payment row to flip belongs to a reversed voucher (its reversal mirror would end on the wrong side); nothing was changed.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
SELECT s.* INTO dbo.SupplierLedger_PVAPSide_Backup_20261013
FROM dbo.SupplierLedger s INNER JOIN #R71 r ON r.SupplierKey = s.SupplierKey AND r.TRN_SEQ_NO = s.TRN_SEQ_NO;

UPDATE s SET s.Debit = r.Credit, s.Credit = 0
FROM dbo.SupplierLedger s INNER JOIN #R71 r ON r.SupplierKey = s.SupplierKey AND r.TRN_SEQ_NO = s.TRN_SEQ_NO;
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── post-check ───────────────────────────────────────────────────────
DECLARE @bad NVARCHAR(1000) = NULL;
IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostCompoundTicket')) NOT LIKE '%@LedgerSide         CHAR(1)        = ''C''%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostCompoundTicket')) NOT LIKE '%CASE WHEN @LedgerSide = ''D'' THEN @GrossAmount ELSE 0 END%'
    SET @bad = N'sp_PostCompoundTicket not patched';
IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2')) NOT LIKE '%@LedgerSeqRef=@pSeqRef, @LedgerSide=''D'';%'
    SET @bad = N'sp_AddPaymentSupplierCompound_V2 not patched';
IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound')) NOT LIKE '%@LedgerSeqRef=@SeqRef, @LedgerSide=''D'';%'
    SET @bad = N'sp_AddPaymentSupplierCompound not patched';
IF EXISTS (SELECT 1 FROM dbo.SupplierLedger s
           WHERE s.TransCode LIKE 'PV-AP%' AND s.PaymentType = 'COMPOUND' AND ISNULL(s.Debit, 0) = 0 AND s.Credit > 0 AND ISNULL(s.ErrorCorrectTag, 0) = 0)
    SET @bad = N'PV-AP payment rows still on the credit side';
-- the trigger re-chained every affected supplier: row math and account = last Ending
IF EXISTS (SELECT 1 FROM dbo.SupplierLedger s WHERE s.SupplierKey IN (SELECT SupplierKey FROM #R71)
           AND ABS(s.EndingBalance - (s.BeginningBalance + s.Credit - s.Debit)) >= 0.005)
   OR EXISTS (SELECT 1 FROM dbo.SupplierAccounts a
              WHERE a.SupplierKey IN (SELECT SupplierKey FROM #R71)
                AND ABS(a.AccountBalance - ISNULL((SELECT TOP 1 x.EndingBalance FROM dbo.SupplierLedger x WHERE x.SupplierKey = a.SupplierKey ORDER BY x.TRN_SEQ_NO DESC), 0)) >= 0.005)
    SET @bad = N'an affected supplier''s ledger chain or account balance does not tie after the repair';
IF @bad IS NOT NULL
BEGIN
    SET @bad = N'Post-check failed (' + @bad + N'); nothing was changed.';
    RAISERROR(@bad, 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
SET NOEXEC OFF;
GO
SELECT a.SupplierKey, a.SupplierName, a.AccountBalance FROM dbo.SupplierAccounts a
WHERE a.SupplierKey IN (SELECT SupplierKey FROM dbo.SupplierLedger_PVAPSide_Backup_20261013) ORDER BY a.SupplierKey;
GO
