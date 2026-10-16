/* ================================================================
   [88] 2026-10-15 - Hardening H7 (Fable session): bank reconciliation loopholes closed
   ================================================================
   Needs [85] + [86] + [87] (the guard checks the live text of every object it touches: DEV = STAGING = PRODUCTION 10-15).
   Backups _OLD_10152026120000. One transaction; a failure rolls everything back. No exe change.

   What goes wrong today (every case reproduced on DEV, rolled back; see [88]-2026-10-15b_H7_Test.sql):
     1. sp_Payment_PostBankReconEntry silently did nothing when an item with the same reference, account and side
        already existed (Known Bug #9): a caller posting two amounts under one key lost the second with no error,
        and a reference colliding with another document's number lost the whole item. sp_PostCashAdvance wrote its
        own copy of that rule: a cash advance with two debit lines on the same bank account got one deposit (the
        first line) instead of their sum.
     2. Editing a Manual JV (and the multi-branch expense) deleted the voucher's recon items and re-created them:
        an item the bank had already cleared came back OPEN, with a new ReconID; the cleared state and the
        clearing month were lost.
     3. Nothing stopped a payment, a reversal, a manual item or a delete from changing a LOCKED reconciliation month:
        the AR deposit insert, the helper, the legacy sp_AddPaymentSupplierCompound (auto-debit postings; two inline
        inserts of its own), sp_BankRecon_SaveItem / DeleteItem / UpdateItem and the two reversal procs had no lock
        check (no period is locked on any tier yet, so nothing is wrong today). The rule is "a locked month AT OR
        AFTER the item's month": an open item carries forward into every later month, so a new, changed, deleted or
        voided item in July changes a locked August as well (same rule as sp_BankRecon_ResolveItem's range).
     4. sp_BankRecon_DeleteItem let a system-inserted item (a payment's cheque or deposit) be deleted, which
        leaves the GL movement with nothing to tick (GL-vs-recon check: GL ONLY).
     5. sp_PostSupplierPaymentWithManualLines updated the voucher's cheque item by reference number alone, and
        the cash advance reversal voided items by voucher number alone: another document's item under the same
        number would have been changed. (The reference counters don't collide today; the rule now makes it
        impossible.) A combined voucher whose invoice leg left no cash got no item at all for the manual lines.
     6. sp_BankRecon_AutoMatch (clears cheques from their own GL credit, not from the bank) was only hidden.
     7. A multi-branch expense with a bank line never got a recon item: the JV helper read only ManualJournalVoucher.

   Rules from [88] (recorded in the work log and docs/standards):
     - sp_Payment_PostBankReconEntry: one item per (ReferenceNo, AccountCode, ItemType). The same posting again
       (same SourceModule + SourceRef + Amount) is a no-op; anything else under an existing key is refused 93021.
       A LOCKED month refuses the insert (93022). Negative amounts / other item types refused (93026).
       Optional @ControlNo. New index IX_BankStatementRecon_RefAccountType.
     - sp_JV_PostBankReconForLines @Mode = 'SYNC' (edits): a cleared item must still be there, unchanged in amount,
       month and branch (else 93023); open items are updated in place (same ReconID), removed lines delete their
       open item, new lines insert; a LOCKED month refuses (93022). Source = ManualJournalVoucher ('MANUAL-JV'),
       else ExpenseManualLines ('MANUAL-EXP').
     - sp_BankRecon_DeleteItem: manual items only (SourceModule MANUAL BANK ENTRY, BF-PEACHTREE or blank; anything
       else 60005: reverse the document instead); locked month 93002.
     - sp_BankRecon_SaveItem: locked month 93002. sp_BankRecon_UpdateItem (no screen uses it): locked month 93002,
       a cleared item's amount / type / date / reference can't change (93024), @IsResolved goes through
       sp_BankRecon_ResolveItem.
     - sp_ReverseCashAdvanceEntry voids only its own items (SourceModule + SourceRef); locked month 93027.
       sp_ReversePaymentClient: locked month 93028. sp_AddPaymentClient: a deposit into a locked month 93022.
     - sp_PostSupplierPaymentWithManualLines: the combined total goes on the voucher's own open item; if the
       invoice leg left none, the item is created for the combined total.
     - sp_PostCashAdvance and the legacy sp_AddPaymentSupplierCompound: items through the helper; a cash advance
       posts one deposit per bank account (lines added up).
     - sp_BankRecon_AutoMatch: hard-disabled (93020); the user decides whether to drop it.
   Acceptance: tools/ExceptionCenter/BankRecon_GLvsRecon_Check.sql unchanged (PRODUCTION 10-15: every reference OK)
   plus its new section 6 (items of a locked month changed after the lock) = 0.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF CHARINDEX('[88]', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_Payment_PostBankReconEntry'))) > 0
BEGIN
    RAISERROR('[88] already applied here; nothing to do.', 16, 1);
    SET NOEXEC ON;
END
ELSE
BEGIN
    DECLARE @bad NVARCHAR(1000) = N'';
    DECLARE @Exp TABLE (Obj SYSNAME, Hash VARCHAR(66));
    INSERT INTO @Exp VALUES   -- whitespace-insensitive SHA-256 of the live text, DEV = STAGING = PRODUCTION 2026-10-15
        ('sp_AddPaymentClient', '0xF8BE77B568A6C72EB1D9A4313A3482ED180BADFD9E6B36C9C6413B01B95F9AD0'),
        ('sp_AddPaymentSupplierCompound', '0xB73713F12603873E98B2684F1ED7105172D77884B056B9A6AE490AC9A2E52853'),
        ('sp_BankRecon_AutoMatch', '0xE7C2119001C585F35B2214F96E402E8E0730C1CFDD0A226C1A61CF5139B210C9'),
        ('sp_BankRecon_DeleteItem', '0x2E297E66ACD5633998741E3BD910256C29BB70FD0CE56304F7D8210228E3AD63'),
        ('sp_BankRecon_SaveItem', '0xECFDB7D86C9EF11FB20B44DF588A03D21E9935FB2F4B2E6866F80243EB4A7C71'),
        ('sp_BankRecon_UpdateItem', '0x12A41D1D62EA335CE75C083943D215B24B201BE999C4DA1FE0EDF43F52618EAC'),
        ('sp_EditExpenseManualMultiBranch', '0x28F3082D383789F00B8C16B984839050080DACB8D080C80BA667F223511E25F9'),
        ('sp_EditManualJournalVoucher', '0xA4807E54353CAE96E0DE1802FB18049DD862380401C757585DA317579A6D8DA8'),
        ('sp_JV_PostBankReconForLines', '0xA0372335F7391CA230FB32A9D217D1C2F7BAC4C96413923F93A90C97482078D0'),
        ('sp_Payment_PostBankReconEntry', '0xB79E2C915B27928EF1740926F397BA48B437FDDF57BC389615F3BB9C87F9C3EC'),
        ('sp_PostCashAdvance', '0xCED9A1A019AC0E172BFDFD17F9A021C3A24E700D98CFCEEBA039B2484D8FA23F'),
        ('sp_PostSupplierPaymentWithManualLines', '0x968DB6442FCB511A7C53FA82114296EDBE1D84EF3D6747C3D867C1AC96E47CD8'),
        ('sp_ReverseCashAdvanceEntry', '0x26AA7C8DCC2438959E2463FFE7C3AF0DC63B3770B67A5F45C176656824A9DF19'),
        ('sp_ReversePaymentClient', '0xC73DE374B4427F7E318E927DAC08C1F2D80CBF05DA2B6A1FEBDC35593A5854B7');
    SELECT @bad = @bad + e.Obj + N' '
    FROM @Exp e
    WHERE ISNULL(CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.' + e.Obj)), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 1), '') <> e.Hash;
    IF @bad <> N'' OR EXISTS (SELECT 1 FROM sys.objects WHERE name LIKE '%[_]OLD[_]10152026120000')
    BEGIN
        SET @bad = N'[88] stopped, nothing changed: not the expected text (run [85] + [86] + [87] first on this database): ' + @bad + N'; or a [88] backup already exists.';
        RAISERROR(@bad, 16, 1);
        SET NOEXEC ON;
    END
    IF OBJECT_ID('dbo.sp_BankRecon_GetOrCreateHeader') IS NULL OR OBJECT_ID('dbo.sp_BankRecon_ResolveItem') IS NULL OR OBJECT_ID('dbo.ExpenseManualLines') IS NULL
    BEGIN
        RAISERROR('[88] stopped, nothing changed: sp_BankRecon_GetOrCreateHeader / sp_BankRecon_ResolveItem / ExpenseManualLines missing.', 16, 1);
        SET NOEXEC ON;
    END
END
GO

BEGIN TRANSACTION;
GO

-- The helper now reads the existing item under UPDLOCK + HOLDLOCK by reference + account + side; the table's only
-- index is the ReconID key, so without this index every payment would range-lock the whole table.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.BankStatementRecon') AND name = 'IX_BankStatementRecon_RefAccountType')
    CREATE NONCLUSTERED INDEX IX_BankStatementRecon_RefAccountType
        ON dbo.BankStatementRecon (ReferenceNo, AccountCode, ItemType)
        INCLUDE (SourceModule, SourceRef, Amount, IsResolved, HeaderID);
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[88] the index step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ================================================================
-- 1. sp_Payment_PostBankReconEntry (recreated)
-- ================================================================
EXEC sp_rename 'dbo.sp_Payment_PostBankReconEntry', 'sp_Payment_PostBankReconEntry_OLD_10152026120000';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[88] stopped (rename 1 failed).', 16, 1); SET NOEXEC ON; END
GO
CREATE PROCEDURE [dbo].[sp_Payment_PostBankReconEntry]
(
    @ItemType     VARCHAR(5),      -- 'OC' or 'DIT'
    @BranchCode   VARCHAR(5),
    @AccountCode  VARCHAR(20),
    @PeriodEnd    DATE,            -- any date of the month; stored as its month end
    @ReferenceNo  VARCHAR(20),     -- the document's own number (voucher id for AP / cash advance, reference no. for AR / JV)
    @ItemDate     DATE,
    @Payee        VARCHAR(150),
    @Amount       DECIMAL(18,2),   -- net cash for OC; the deposit for DIT
    @Remarks      VARCHAR(500),
    @SourceModule VARCHAR(20),
    @SourceRef    VARCHAR(50),
    @CreatedBy    VARCHAR(50),
    @ControlNo    VARCHAR(50) = NULL   -- [88] optional
)
AS
/*  [88] 2026-10-15 (hardening H7). One bank recon item per (ReferenceNo, AccountCode, ItemType):
      - the same posting again (same SourceModule, SourceRef and Amount) does nothing: a re-run is safe;
      - an existing item under that key with another amount or from another document is refused (93021): before, the
        second call was silently dropped (Known Bug #9) and the reconciliation was short with no error anywhere;
      - a month whose reconciliation is LOCKED refuses the insert (93022): the locked figures would change;
      - negative amounts and item types other than OC / DIT are refused (93026).
    Callers add up all cash movement per account and side BEFORE calling (sp_PostVoucherManual, sp_JV_PostBankReconForLines,
    sp_PostCashAdvance since [88]). Error handling per docs/standards/2026-10-14_Posting_Proc_Error_Handling.md. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @msg NVARCHAR(700), @P DATE = EOMONTH(@PeriodEnd);

        IF @ItemType NOT IN ('OC', 'DIT')
        BEGIN
            SET @msg = N'Bank recon item type ''' + ISNULL(@ItemType, N'') + N''' is not OC or DIT. Nothing was posted.';
            THROW 93026, @msg, 1;
        END
        IF @Amount < 0
        BEGIN
            SET @msg = N'Bank recon item amount ' + CONVERT(NVARCHAR(30), @Amount) + N' is negative (reference ' + ISNULL(@ReferenceNo, N'') + N', account ' + ISNULL(@AccountCode, N'') + N'). Nothing was posted.';
            THROW 93026, @msg, 1;
        END

        DECLARE @exID INT, @exSrc VARCHAR(20), @exRef VARCHAR(50), @exAmt DECIMAL(18,2);
        SELECT TOP (1) @exID = ReconID, @exSrc = ISNULL(SourceModule, ''), @exRef = ISNULL(SourceRef, ''), @exAmt = Amount
        FROM dbo.BankStatementRecon WITH (UPDLOCK, HOLDLOCK)
        WHERE ReferenceNo = @ReferenceNo AND AccountCode = @AccountCode AND ItemType = @ItemType
        ORDER BY ReconID;

        IF @exID IS NOT NULL
        BEGIN
            IF @exSrc = ISNULL(@SourceModule, '') AND @exRef = ISNULL(@SourceRef, '') AND @exAmt = @Amount
            BEGIN
                COMMIT TRANSACTION;   -- the same posting once more: nothing to do
                RETURN;
            END
            SET @msg = N'Bank recon: reference ' + ISNULL(@ReferenceNo, N'') + N' already has a ' + @ItemType + N' item on account ' + ISNULL(@AccountCode, N'')
                     + N' (' + @exSrc + N' ref ' + @exRef + N', ' + CONVERT(NVARCHAR(30), @exAmt) + N'); this posting would add ' + CONVERT(NVARCHAR(30), @Amount)
                     + N' for ' + ISNULL(@SourceModule, N'') + N' ref ' + ISNULL(@SourceRef, N'') + N'. Cash movement must be added up per account before posting, or the reference number collides with another document. Nothing was posted.';
            THROW 93021, @msg, 1;
        END

        DECLARE @HeaderID INT;
        EXEC dbo.sp_BankRecon_GetOrCreateHeader
            @BranchCode = @BranchCode, @AccountCode = @AccountCode,
            @PeriodEnd  = @P,          @CreatedBy   = @CreatedBy,
            @HeaderID   = @HeaderID OUTPUT;

        -- a LOCKED month at or after the item's month: open items carry forward, so this entry would change that month's figures
        DECLARE @LockedP DATE = (SELECT MIN(PeriodEnd) FROM dbo.BankReconHeader WITH (HOLDLOCK)
                                 WHERE BranchCode = @BranchCode AND AccountCode = @AccountCode AND Status = 'LOCKED' AND PeriodEnd >= @P);
        IF @LockedP IS NOT NULL
        BEGIN
            SET @msg = N'Bank reconciliation of account ' + ISNULL(@AccountCode, N'') + N' (branch ' + ISNULL(@BranchCode, N'') + N') is locked for the month ending ' + CONVERT(NVARCHAR(10), @LockedP, 120)
                     + N'. An entry dated ' + CONVERT(NVARCHAR(10), @ItemDate, 120) + N' would change that reconciliation: use a date in an open month after it, or have the period unlocked. Nothing was posted.';
            THROW 93022, @msg, 1;
        END

        INSERT INTO dbo.BankStatementRecon
            (HeaderID, BranchCode, AccountCode, PeriodEnd,
             ItemType, ReferenceNo, ItemDate, Payee, Amount, Remarks,
             IsResolved, AddedBy, DateTimeAdded,
             SourceModule, SourceRef, ResolvedReason, CreatedBy, CreatedDate, ControlNo)
        VALUES
            (@HeaderID, @BranchCode, @AccountCode, @P,
             @ItemType, @ReferenceNo, @ItemDate, @Payee, @Amount, @Remarks,
             0, @CreatedBy, GETDATE(),
             @SourceModule, @SourceRef, '', @CreatedBy, GETDATE(), NULLIF(LTRIM(RTRIM(@ControlNo)), ''));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[88] stopped (create 1 failed).', 16, 1); SET NOEXEC ON; END
GO

-- ================================================================
-- 2. sp_JV_PostBankReconForLines (recreated): + @Mode = 'SYNC', + multi-branch expense lines
-- ================================================================
EXEC sp_rename 'dbo.sp_JV_PostBankReconForLines', 'sp_JV_PostBankReconForLines_OLD_10152026120000';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[88] stopped (rename 2 failed).', 16, 1); SET NOEXEC ON; END
GO
CREATE PROCEDURE dbo.sp_JV_PostBankReconForLines
(
    @ReferenceNo   VARCHAR(10),
    @VoucherDate   DATE,
    @DefaultBranch VARCHAR(5) = NULL,   -- used only if a detail row's own branch is unavailable
    @CreatedBy     VARCHAR(50),
    @Mode          VARCHAR(4) = 'POST'  -- [88] 'POST' = a new voucher; 'SYNC' = an edit (keeps cleared items, updates open ones in place)
)
AS
/*
    Reads what was just posted for @ReferenceNo and keeps one Bank Recon item per bank account and side:
    DIT = the account's total debit, OC = its total credit (2026-10-08b: per line before, and the helper dropped every
    line after the first). Source: ManualJournalVoucher / Details (SourceModule 'MANUAL-JV'); when the reference has
    none, ExpenseManualLines (the multi-branch expense screen, 'MANUAL-EXP'; [88]: it never got items before).
    [88] @Mode = 'SYNC' (sp_EditManualJournalVoucher / sp_EditExpenseManualMultiBranch): the voucher's existing items are
    reconciled with its new lines instead of deleted and re-created:
      - an item the bank already cleared must still be there with the same amount, month and branch, else 93023
        (unclear it in its month first, or reverse the voucher);
      - an open item in a LOCKED month cannot change or go (93022);
      - open items whose line is still there are updated in place (same ReconID: amount, date, month, branch, remarks);
      - open items whose line is gone are deleted; new lines get new items (sp_Payment_PostBankReconEntry).
    Error handling per docs/standards/2026-10-14_Posting_Proc_Error_Handling.md.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Mode NOT IN ('POST', 'SYNC')
            THROW 93029, 'sp_JV_PostBankReconForLines: @Mode must be POST or SYNC.', 1;

        DECLARE @PeriodEnd DATE = EOMONTH(@VoucherDate), @Src VARCHAR(20) = 'MANUAL-JV', @msg NVARCHAR(700);

        IF OBJECT_ID('tempdb..#JVBankItems') IS NOT NULL DROP TABLE #JVBankItems;
        CREATE TABLE #JVBankItems (RowNum INT NOT NULL, AccountCode VARCHAR(20) NOT NULL, ItemType VARCHAR(5) NOT NULL,
                                   BranchCode VARCHAR(5) NULL, Amount DECIMAL(18,2) NOT NULL, Lines INT NOT NULL, Particulars VARCHAR(500) NULL,
                                   Remarks VARCHAR(1000) NULL, ReconID INT NULL);

        IF EXISTS (SELECT 1 FROM dbo.ManualJournalVoucher WHERE ReferenceNo = @ReferenceNo)
        BEGIN
            ;WITH Lines AS (
                SELECT  ISNULL(mjv.BranchCode, @DefaultBranch) AS BranchCode,
                        mjvd.AccountCode,
                        CAST(ISNULL(mjvd.Debit, 0)  AS DECIMAL(18,2)) AS Debit,
                        CAST(ISNULL(mjvd.Credit, 0) AS DECIMAL(18,2)) AS Credit,
                        mjvd.Particulars
                FROM dbo.ManualJournalVoucher AS mjv
                INNER JOIN dbo.ManualJournalVoucherDetails AS mjvd ON mjvd.VoucherID = mjv.VoucherID
                INNER JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = mjvd.AccountCode
                WHERE mjv.ReferenceNo = @ReferenceNo
                  AND coa.AccountCode LIKE '10102%'),
            Sides AS (
                SELECT l.BranchCode, l.AccountCode, s.ItemType, s.Amount, l.Particulars
                FROM Lines AS l
                CROSS APPLY (VALUES ('DIT', l.Debit), ('OC', l.Credit)) AS s (ItemType, Amount)
                WHERE s.Amount > 0)
            INSERT INTO #JVBankItems (RowNum, AccountCode, ItemType, BranchCode, Amount, Lines, Particulars)
            SELECT  ROW_NUMBER() OVER (ORDER BY AccountCode, ItemType), AccountCode, ItemType,
                    MIN(BranchCode), SUM(Amount), COUNT(*), MIN(Particulars)
            FROM Sides
            GROUP BY AccountCode, ItemType;
        END
        ELSE IF EXISTS (SELECT 1 FROM dbo.ExpenseManualLines WHERE ReferenceNumber = @ReferenceNo)
        BEGIN
            SET @Src = 'MANUAL-EXP';
            ;WITH Lines AS (
                SELECT  ISNULL(l.BranchCode, @DefaultBranch) AS BranchCode,
                        l.AccountCode,
                        CAST(ISNULL(l.Debit, 0)  AS DECIMAL(18,2)) AS Debit,
                        CAST(ISNULL(l.Credit, 0) AS DECIMAL(18,2)) AS Credit,
                        CAST(l.Particulars AS VARCHAR(500)) AS Particulars
                FROM dbo.ExpenseManualLines AS l
                INNER JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = l.AccountCode
                WHERE l.ReferenceNumber = @ReferenceNo
                  AND coa.AccountCode LIKE '10102%'),
            Sides AS (
                SELECT l.BranchCode, l.AccountCode, s.ItemType, s.Amount, l.Particulars
                FROM Lines AS l
                CROSS APPLY (VALUES ('DIT', l.Debit), ('OC', l.Credit)) AS s (ItemType, Amount)
                WHERE s.Amount > 0)
            INSERT INTO #JVBankItems (RowNum, AccountCode, ItemType, BranchCode, Amount, Lines, Particulars)
            SELECT  ROW_NUMBER() OVER (ORDER BY AccountCode, ItemType), AccountCode, ItemType,
                    MIN(BranchCode), SUM(Amount), COUNT(*), MIN(Particulars)
            FROM Sides
            GROUP BY AccountCode, ItemType;
        END

        UPDATE #JVBankItems
        SET Remarks = CASE WHEN ItemType = 'DIT'
                           THEN 'Auto-DIT | ' + CASE WHEN @Src = 'MANUAL-JV' THEN 'MANUAL JV' ELSE 'MANUAL EXPENSE' END + ' | Ref: ' + ISNULL(@ReferenceNo, '')
                                + CASE WHEN Lines = 1 THEN ISNULL(' | ' + Particulars, '') ELSE '' END
                           ELSE 'Auto-OC | ' + CASE WHEN @Src = 'MANUAL-JV' THEN 'MANUAL JV' ELSE 'MANUAL EXPENSE' END + ' | Ref: ' + ISNULL(@ReferenceNo, '') END
                    + CASE WHEN Lines > 1 THEN ' | ' + CAST(Lines AS VARCHAR(10)) + ' bank lines' ELSE '' END;

        IF @Mode = 'SYNC'
        BEGIN
            -- the voucher's items as they are now (its own only: SourceModule + SourceRef)
            SELECT  b.ReconID, b.AccountCode, b.ItemType, b.Amount, b.BranchCode, b.HeaderID,
                    CAST(ISNULL(b.IsResolved, 0) AS INT) AS IsResolved, ISNULL(b.ResolvedReason, '') AS Reason,
                    ISNULL(h.PeriodEnd, b.PeriodEnd) AS HPeriod,
                    COALESCE(b.ClearedPeriodEnd, h.PeriodEnd, b.PeriodEnd) AS ClearedIn,
                    -- a LOCKED month at or after the item's month (open items carry forward into it)
                    (SELECT MIN(l.PeriodEnd) FROM dbo.BankReconHeader AS l WITH (HOLDLOCK)
                     WHERE l.BranchCode = ISNULL(h.BranchCode, b.BranchCode) AND l.AccountCode = b.AccountCode
                       AND l.Status = 'LOCKED' AND l.PeriodEnd >= ISNULL(h.PeriodEnd, b.PeriodEnd)) AS LockedP
            INTO #Old
            FROM dbo.BankStatementRecon AS b WITH (UPDLOCK, HOLDLOCK)
            LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
            WHERE b.ReferenceNo = @ReferenceNo AND b.SourceModule = @Src AND b.SourceRef = @ReferenceNo;   -- ReferenceNo first: the index

            UPDATE n SET ReconID = o.ReconID
            FROM #JVBankItems AS n INNER JOIN #Old AS o ON o.AccountCode = n.AccountCode AND o.ItemType = n.ItemType;

            -- 1. a cleared item stays exactly as the bank cleared it
            SELECT TOP (1) @msg = N'Bank line ' + o.AccountCode + N' (' + o.ItemType + N' ' + CONVERT(NVARCHAR(30), o.Amount) + N') of reference ' + ISNULL(@ReferenceNo, N'')
                               + N' was already cleared by the bank in the ' + CONVERT(NVARCHAR(10), o.ClearedIn, 120) + N' reconciliation (' + o.Reason + N'). An edit cannot change, move or remove it'
                               + N': mark it uncleared in that period first, or reverse the voucher and post a new one. Nothing was saved.'
            FROM #Old AS o
            LEFT JOIN #JVBankItems AS n ON n.AccountCode = o.AccountCode AND n.ItemType = o.ItemType
            WHERE o.IsResolved = 1
              AND (n.AccountCode IS NULL OR n.Amount <> o.Amount OR o.HPeriod <> @PeriodEnd OR ISNULL(n.BranchCode, '') <> ISNULL(o.BranchCode, ''))
            ORDER BY o.ReconID;
            IF @msg IS NOT NULL THROW 93023, @msg, 1;

            -- 2. an open item that counts in a locked month (its own, or a later locked one) cannot change or go
            SELECT TOP (1) @msg = N'Bank reconciliation of account ' + o.AccountCode + N' is locked for the month ending ' + CONVERT(NVARCHAR(10), o.LockedP, 120)
                               + N'; the ' + o.ItemType + N' item of reference ' + ISNULL(@ReferenceNo, N'') + N' (' + CONVERT(NVARCHAR(10), o.HPeriod, 120) + N') counts in it and cannot be changed by this edit. Have the period unlocked, or reverse the voucher. Nothing was saved.'
            FROM #Old AS o
            LEFT JOIN #JVBankItems AS n ON n.AccountCode = o.AccountCode AND n.ItemType = o.ItemType
            WHERE o.IsResolved = 0 AND o.LockedP IS NOT NULL
              AND (n.AccountCode IS NULL OR n.Amount <> o.Amount OR o.HPeriod <> @PeriodEnd OR ISNULL(n.BranchCode, '') <> ISNULL(o.BranchCode, ''))
            ORDER BY o.ReconID;
            IF @msg IS NOT NULL THROW 93022, @msg, 1;

            -- 3. open items whose bank line is gone
            DELETE b
            FROM dbo.BankStatementRecon AS b
            INNER JOIN #Old AS o ON o.ReconID = b.ReconID
            WHERE o.IsResolved = 0
              AND NOT EXISTS (SELECT 1 FROM #JVBankItems AS n WHERE n.AccountCode = o.AccountCode AND n.ItemType = o.ItemType);

            -- 4. open items whose line is still there: updated in place (same ReconID), moved to the right month / branch
            DECLARE @sRow INT = 1, @sMax INT, @sReconID INT, @sAccount VARCHAR(20), @sType VARCHAR(5), @sBranch VARCHAR(5),
                    @sAmount DECIMAL(18,2), @sRemarks VARCHAR(1000), @sHeaderID INT, @sOldHeader INT;
            SELECT @sMax = MAX(RowNum) FROM #JVBankItems;
            WHILE @sRow <= ISNULL(@sMax, 0)
            BEGIN
                SELECT @sReconID = n.ReconID, @sAccount = n.AccountCode, @sType = n.ItemType, @sBranch = n.BranchCode, @sAmount = n.Amount, @sRemarks = n.Remarks,
                       @sOldHeader = o.HeaderID
                FROM #JVBankItems AS n
                LEFT JOIN #Old AS o ON o.ReconID = n.ReconID
                WHERE n.RowNum = @sRow;

                IF @sReconID IS NOT NULL AND EXISTS (SELECT 1 FROM #Old WHERE ReconID = @sReconID AND IsResolved = 0)
                BEGIN
                    SET @sHeaderID = NULL;
                    EXEC dbo.sp_BankRecon_GetOrCreateHeader
                        @BranchCode = @sBranch, @AccountCode = @sAccount, @PeriodEnd = @PeriodEnd, @CreatedBy = @CreatedBy,
                        @HeaderID = @sHeaderID OUTPUT;
                    IF @sHeaderID <> ISNULL(@sOldHeader, -1)
                    BEGIN
                        DECLARE @sLockedP DATE = (SELECT MIN(PeriodEnd) FROM dbo.BankReconHeader WITH (HOLDLOCK)
                                                  WHERE BranchCode = @sBranch AND AccountCode = @sAccount AND Status = 'LOCKED' AND PeriodEnd >= @PeriodEnd);
                        IF @sLockedP IS NOT NULL
                        BEGIN
                            SET @msg = N'Bank reconciliation of account ' + @sAccount + N' is locked for the month ending ' + CONVERT(NVARCHAR(10), @sLockedP, 120)
                                     + N'; the ' + @sType + N' item of reference ' + ISNULL(@ReferenceNo, N'') + N' cannot be moved to ' + CONVERT(NVARCHAR(10), @PeriodEnd, 120) + N' (it would count in the locked month). Nothing was saved.';
                            THROW 93022, @msg, 1;
                        END
                    END
                    UPDATE dbo.BankStatementRecon
                    SET Amount          = @sAmount,
                        ItemDate        = @VoucherDate,
                        PeriodEnd       = @PeriodEnd,
                        HeaderID        = @sHeaderID,
                        BranchCode      = ISNULL(@sBranch, BranchCode),
                        Remarks         = @sRemarks,
                        UpdatedBy       = @CreatedBy,
                        DateTimeUpdated = GETDATE()
                    WHERE ReconID = @sReconID
                      AND (Amount <> @sAmount OR ItemDate <> @VoucherDate OR ISNULL(HeaderID, -1) <> @sHeaderID OR ISNULL(Remarks, '') <> @sRemarks
                           OR ISNULL(BranchCode, '') <> ISNULL(@sBranch, ISNULL(BranchCode, '')));
                END
                SET @sRow += 1;
            END

            -- 5. new lines: only those without an item yet
            DELETE FROM #JVBankItems WHERE ReconID IS NOT NULL;
            DROP TABLE #Old;
        END

        DECLARE @i INT = 1, @maxi INT, @itBranch VARCHAR(5), @itAccount VARCHAR(20), @itType VARCHAR(5),
                @itAmount DECIMAL(18,2), @itRemarks VARCHAR(1000);
        SELECT @maxi = MAX(RowNum) FROM #JVBankItems;
        WHILE @i <= ISNULL(@maxi, 0)
        BEGIN
            SELECT @itAccount = NULL;
            SELECT @itBranch = BranchCode, @itAccount = AccountCode, @itType = ItemType, @itAmount = Amount, @itRemarks = Remarks
            FROM #JVBankItems WHERE RowNum = @i;

            IF @itAccount IS NOT NULL
                EXEC dbo.sp_Payment_PostBankReconEntry
                    @ItemType = @itType, @BranchCode = @itBranch, @AccountCode = @itAccount,
                    @PeriodEnd = @PeriodEnd, @ReferenceNo = @ReferenceNo, @ItemDate = @VoucherDate,
                    @Payee = @CreatedBy, @Amount = @itAmount,
                    @Remarks = @itRemarks,
                    @SourceModule = @Src, @SourceRef = @ReferenceNo, @CreatedBy = @CreatedBy;

            SET @i += 1;
        END;

        DROP TABLE #JVBankItems;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[88] stopped (create 2 failed).', 16, 1); SET NOEXEC ON; END
GO

-- ================================================================
-- 3. sp_BankRecon_DeleteItem (recreated): manual items only, never in a locked month
-- ================================================================
EXEC sp_rename 'dbo.sp_BankRecon_DeleteItem', 'sp_BankRecon_DeleteItem_OLD_10152026120000';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[88] stopped (rename 3 failed).', 16, 1); SET NOEXEC ON; END
GO
CREATE PROCEDURE [dbo].[sp_BankRecon_DeleteItem]
    @ReconID INT,
    @User    VARCHAR(50)
AS
/*  Deletes a reconciling item typed by hand (Add on the Bank Recon screen, or a balance-forward load).
    [88] 2026-10-15 (H7): an item a document posted (a payment's cheque or deposit, a cash advance, a JV / expense bank
    line) is refused (60005): deleting it leaves the GL movement with nothing to tick; reverse the document instead.
    A cleared item (60004, as before) and an item of a LOCKED month (93002) are refused too. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Resolved BIT, @Src VARCHAR(20), @SrcRef VARCHAR(50), @HPeriod DATE, @HBranch VARCHAR(5), @Account VARCHAR(20), @LockedP DATE, @msg NVARCHAR(500);
        SELECT @Resolved = ISNULL(b.IsResolved, 0), @Src = ISNULL(b.SourceModule, ''), @SrcRef = ISNULL(b.SourceRef, ''),
               @HPeriod = ISNULL(h.PeriodEnd, b.PeriodEnd), @HBranch = ISNULL(h.BranchCode, b.BranchCode), @Account = b.AccountCode
        FROM dbo.BankStatementRecon AS b WITH (UPDLOCK)
        LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
        WHERE b.ReconID = @ReconID;

        IF @Account IS NULL OR @Resolved = 1
            THROW 60004, 'Item not found or already resolved - cannot delete.', 1;

        -- only items typed by hand (or loaded as a balance forward) can be deleted; everything else was posted by a document
        IF @Src NOT IN ('', 'MANUAL BANK ENTRY', 'BF-PEACHTREE')
        BEGIN
            SET @msg = N'This item was posted by ' + @Src + N' reference ' + @SrcRef + N'; it cannot be deleted here, because its GL entry would be left with nothing to tick. Reverse that document instead.';
            THROW 60005, @msg, 1;
        END

        -- its own month, or a later locked one: an open item carries forward into every later month
        SET @LockedP = (SELECT MIN(PeriodEnd) FROM dbo.BankReconHeader WITH (HOLDLOCK)
                        WHERE BranchCode = @HBranch AND AccountCode = @Account AND Status = 'LOCKED' AND PeriodEnd >= @HPeriod);
        IF @LockedP IS NOT NULL
        BEGIN
            SET @msg = N'Cannot delete: the ' + CONVERT(NVARCHAR(10), @LockedP, 120) + N' reconciliation of account ' + @Account + N' is locked and this item (' + CONVERT(NVARCHAR(10), @HPeriod, 120) + N') counts in it.';
            THROW 93002, @msg, 1;
        END

        DELETE FROM dbo.BankStatementRecon WHERE ReconID = @ReconID;

        COMMIT TRANSACTION;
        SELECT 'OK' AS Result, 'Item deleted.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[88] stopped (create 3 failed).', 16, 1); SET NOEXEC ON; END
GO

-- ================================================================
-- 4. sp_BankRecon_SaveItem (recreated): never into a locked month
-- ================================================================
EXEC sp_rename 'dbo.sp_BankRecon_SaveItem', 'sp_BankRecon_SaveItem_OLD_10152026120000';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[88] stopped (rename 4 failed).', 16, 1); SET NOEXEC ON; END
GO
CREATE PROCEDURE [dbo].[sp_BankRecon_SaveItem]
    @BranchCode       VARCHAR(5),
    @AccountCode      VARCHAR(20),
    @PeriodEnd        DATE,
    @BankStatementBal DECIMAL(19,2),
    @ItemType         VARCHAR(5),
    @ReferenceNo      VARCHAR(150),
    @ItemDate         DATE,
    @Payee            VARCHAR(200) = NULL,
    @Amount           DECIMAL(19,2),
    @Remarks          VARCHAR(500) = NULL,
    @User             VARCHAR(50),
    @ControlNo        VARCHAR(50)  = NULL
AS
/*  A reconciling item typed by hand (Bank Recon screen > Add). [88] 2026-10-15 (H7): refused when the month's
    reconciliation is LOCKED (93002). Everything else as before (60001 type, 60002 amount, 60003 control no. twice). */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @ItemType NOT IN ('OC','DIT','BCM','BDM','BC','NSF')
            THROW 60001, 'Invalid ItemType. Use: OC, DIT, BCM, BDM, BC, NSF', 1;

        IF @Amount <= 0
            THROW 60002, 'Amount must be greater than zero.', 1;

        -- two "Add DIT" dialogs opened before either is saved (or a double-click on Save) must not both carry the same deposit
        IF @ItemType = 'DIT' AND @ControlNo IS NOT NULL AND EXISTS (
            SELECT 1 FROM dbo.BankStatementRecon
            WHERE ItemType = 'DIT' AND AccountCode = @AccountCode AND ControlNo = @ControlNo
        )
            THROW 60003, 'This Control No has already been added as a Deposit in Transit for this account.', 1;

        DECLARE @ReconHeaderID INT, @P DATE = EOMONTH(@PeriodEnd), @LockedP DATE, @msg NVARCHAR(400);

        -- the month itself, or a later locked one: an open item carries forward into every later month
        SET @LockedP = (SELECT MIN(PeriodEnd) FROM dbo.BankReconHeader WITH (HOLDLOCK)
                        WHERE BranchCode = @BranchCode AND AccountCode = @AccountCode AND Status = 'LOCKED' AND PeriodEnd >= @P);
        IF @LockedP IS NOT NULL
        BEGIN
            SET @msg = N'Cannot add an item dated ' + CONVERT(NVARCHAR(10), @ItemDate, 120) + N': the ' + CONVERT(NVARCHAR(10), @LockedP, 120) + N' reconciliation of account ' + @AccountCode + N' is locked and the item would count in it.';
            THROW 93002, @msg, 1;
        END

        EXEC dbo.sp_BankRecon_GetOrCreateHeader
            @BranchCode = @BranchCode, @AccountCode = @AccountCode,
            @PeriodEnd  = @P,          @CreatedBy   = @User,
            @HeaderID   = @ReconHeaderID OUTPUT;

        INSERT INTO dbo.BankStatementRecon
            (HeaderID, BranchCode, AccountCode, PeriodEnd,
             ItemType, ReferenceNo, ItemDate, Payee, Amount, Remarks,
             IsResolved, AddedBy, DateTimeAdded,
             SourceModule, SourceRef, ResolvedReason, CreatedBy, CreatedDate, ControlNo)
        VALUES
            (@ReconHeaderID, @BranchCode, @AccountCode, @P, @ItemType,
             @ReferenceNo, @ItemDate, @Payee, @Amount,
             @Remarks,
             0, @User, GETDATE(), 'MANUAL BANK ENTRY', NULL, '',
             @User, GETDATE(), @ControlNo);

        DECLARE @NewID INT = SCOPE_IDENTITY();
        COMMIT TRANSACTION;

        SELECT @NewID AS ReconID, 'OK' AS Result, 'Item saved.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[88] stopped (create 4 failed).', 16, 1); SET NOEXEC ON; END
GO

-- ================================================================
-- 5. sp_BankRecon_UpdateItem (recreated; no current screen calls it): lock + cleared rules, resolve through sp_BankRecon_ResolveItem
-- ================================================================
EXEC sp_rename 'dbo.sp_BankRecon_UpdateItem', 'sp_BankRecon_UpdateItem_OLD_10152026120000';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[88] stopped (rename 5 failed).', 16, 1); SET NOEXEC ON; END
GO
CREATE PROCEDURE [dbo].[sp_BankRecon_UpdateItem]
    @ReconID         INT,
    @ItemType        VARCHAR(5)       = NULL,
    @ReferenceNo     VARCHAR(150)     = NULL,
    @ItemDate        DATE             = NULL,
    @Payee           VARCHAR(200)     = NULL,
    @Amount          DECIMAL(19,2)    = NULL,
    @Remarks         VARCHAR(500)     = NULL,
    @IsResolved      BIT              = NULL,
    @User            VARCHAR(50)
AS
/*  Edits an item (older screens; BankReconFormV2 does not call it). [88] 2026-10-15 (H7): refused in a LOCKED month
    (93002); a cleared item's type, reference, date or amount cannot change (93024); @IsResolved is applied through
    sp_BankRecon_ResolveItem, so the cleared-month rules hold here too. Payee / Remarks can always be corrected. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Resolved BIT, @HPeriod DATE, @HBranch VARCHAR(5), @Account VARCHAR(20), @LockedP DATE, @msg NVARCHAR(400),
                @cType VARCHAR(5), @cRef VARCHAR(150), @cDate DATE, @cAmount DECIMAL(19,2);
        SELECT @Resolved = ISNULL(b.IsResolved, 0), @HPeriod = ISNULL(h.PeriodEnd, b.PeriodEnd), @HBranch = ISNULL(h.BranchCode, b.BranchCode), @Account = b.AccountCode,
               @cType = b.ItemType, @cRef = b.ReferenceNo, @cDate = b.ItemDate, @cAmount = b.Amount
        FROM dbo.BankStatementRecon AS b WITH (UPDLOCK)
        LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
        WHERE b.ReconID = @ReconID;

        IF @Account IS NULL
            THROW 60003, 'ReconID not found.', 1;

        SET @LockedP = (SELECT MIN(PeriodEnd) FROM dbo.BankReconHeader WITH (HOLDLOCK)
                        WHERE BranchCode = @HBranch AND AccountCode = @Account AND Status = 'LOCKED' AND PeriodEnd >= @HPeriod);
        IF @LockedP IS NOT NULL
        BEGIN
            SET @msg = N'Cannot edit: the ' + CONVERT(NVARCHAR(10), @LockedP, 120) + N' reconciliation of account ' + @Account + N' is locked and this item (' + CONVERT(NVARCHAR(10), @HPeriod, 120) + N') counts in it.';
            THROW 93002, @msg, 1;
        END

        IF @Resolved = 1 AND (   (@ItemType    IS NOT NULL AND @ItemType    <> @cType)
                              OR (@ReferenceNo IS NOT NULL AND @ReferenceNo <> @cRef)
                              OR (@ItemDate    IS NOT NULL AND @ItemDate    <> @cDate)
                              OR (@Amount      IS NOT NULL AND @Amount      <> @cAmount))
            THROW 93024, 'This item was already cleared by the bank; its type, reference, date and amount cannot change. Mark it uncleared first.', 1;

        UPDATE dbo.BankStatementRecon
        SET ItemType        = ISNULL(@ItemType,    ItemType),
            ReferenceNo     = ISNULL(@ReferenceNo, ReferenceNo),
            ItemDate        = ISNULL(@ItemDate,    ItemDate),
            Payee           = ISNULL(@Payee,       Payee),
            Amount          = ISNULL(@Amount,      Amount),
            Remarks         = ISNULL(@Remarks,     Remarks),
            UpdatedBy       = @User,
            DateTimeUpdated = GETDATE()
        WHERE ReconID = @ReconID;

        IF @IsResolved IS NOT NULL AND @IsResolved <> @Resolved
            EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @ReconID, @IsResolved = @IsResolved, @ResolvedBy = @User;   -- the item's own month

        COMMIT TRANSACTION;
        SELECT 'OK' AS Result, 'Item updated.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[88] stopped (create 5 failed).', 16, 1); SET NOEXEC ON; END
GO

-- ================================================================
-- 6. sp_BankRecon_AutoMatch (recreated): disabled
-- ================================================================
EXEC sp_rename 'dbo.sp_BankRecon_AutoMatch', 'sp_BankRecon_AutoMatch_OLD_10152026120000';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[88] stopped (rename 6 failed).', 16, 1); SET NOEXEC ON; END
GO
CREATE PROCEDURE [dbo].[sp_BankRecon_AutoMatch]
    @BranchCode  VARCHAR(5),
    @AccountCode VARCHAR(20),
    @PeriodEnd   DATE,
    @User        VARCHAR(50)
AS
/*  [88] 2026-10-15 (H7): disabled. It marked outstanding cheques cleared whenever their own GL credit existed, i.e. from
    the book side, not from the bank statement (rolled back on STAGING 10-08: 78 cheques, 47.6M, cleared with no bank
    evidence). The screen's buttons were hidden on 2026-10-08; an older exe that still calls it gets this message.
    The previous text is kept as sp_BankRecon_AutoMatch_OLD_10152026120000. */
BEGIN
    SET NOCOUNT ON;
    THROW 93020, 'Auto-Match is disabled: it cleared cheques from their own GL entry, not from the bank statement. Tick the items that appear on the statement instead.', 1;
END;
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[88] stopped (create 6 failed).', 16, 1); SET NOEXEC ON; END
GO

-- ================================================================
-- 7. anchor patches of 8 live procs (the live text is normalised to LF before matching; backups keep the original)
-- ================================================================
BEGIN TRY
    DECLARE @Patch TABLE (Obj SYSNAME, Ord INT, Anchor NVARCHAR(MAX), Repl NVARCHAR(MAX));
    INSERT INTO @Patch (Obj, Ord, Anchor, Repl) VALUES
    ('sp_EditManualJournalVoucher', 1,
     N'            DELETE FROM dbo.BankStatementRecon WHERE ReferenceNo = @parmrefno AND SourceModule = ''MANUAL-JV'';',
     N'            -- [88] H7: the voucher''s bank recon items are no longer deleted here; sp_JV_PostBankReconForLines @Mode = ''SYNC'' (below) keeps cleared items and updates open ones in place'),
    ('sp_EditManualJournalVoucher', 2,
     N'            EXEC dbo.sp_JV_PostBankReconForLines{NL}                @ReferenceNo = @parmrefno, @VoucherDate = @parmvoucherdate,{NL}                @DefaultBranch = NULL, @CreatedBy = @parmuser;',
     N'            EXEC dbo.sp_JV_PostBankReconForLines{NL}                @ReferenceNo = @parmrefno, @VoucherDate = @parmvoucherdate,{NL}                @DefaultBranch = NULL, @CreatedBy = @parmuser, @Mode = ''SYNC'';   -- [88]'),
    ('sp_EditExpenseManualMultiBranch', 1,
     N'        DELETE FROM BankStatementRecon WHERE ReferenceNo = @parmrefno AND SourceModule = ''MANUAL-JV'';',
     N'        -- [88] H7: the expense''s bank recon items are no longer deleted here; sp_JV_PostBankReconForLines @Mode = ''SYNC'' (below) keeps cleared items and updates open ones in place'),
    ('sp_EditExpenseManualMultiBranch', 2,
     N'        EXEC dbo.sp_JV_PostBankReconForLines{NL}            @ReferenceNo = @parmrefno, @VoucherDate = @parmexpensedate,{NL}            @DefaultBranch = NULL, @CreatedBy = @parmuser;',
     N'        EXEC dbo.sp_JV_PostBankReconForLines{NL}            @ReferenceNo = @parmrefno, @VoucherDate = @parmexpensedate,{NL}            @DefaultBranch = NULL, @CreatedBy = @parmuser, @Mode = ''SYNC'';   -- [88]'),
    ('sp_PostSupplierPaymentWithManualLines', 1,
     N'            UPDATE BankStatementRecon{NL}            SET Amount = @GrandTotal,{NL}                Remarks = Remarks + '' | Corrected to combined total (invoices + manual lines)''{NL}            WHERE ReferenceNo = @parmvoucherid AND AccountCode = @parmglcode AND ItemType = ''OC'';',
     N'            -- [88] H7: the voucher''s OWN open item only (SourceModule + SourceRef), never another document''s under the same number;{NL}            --          when the invoice leg left no cash (no item), the combined total gets its item here{NL}            UPDATE BankStatementRecon{NL}            SET Amount = @GrandTotal,{NL}                Remarks = Remarks + '' | Corrected to combined total (invoices + manual lines)''{NL}            WHERE ReferenceNo = @parmvoucherid AND AccountCode = @parmglcode AND ItemType = ''OC''{NL}              AND SourceModule = ''AP-PAYMENT'' AND SourceRef = @parmrefno AND IsResolved = 0;{NL}            IF @@ROWCOUNT = 0{NL}            BEGIN{NL}                DECLARE @CombRemarks VARCHAR(500) = ''Auto-OC | Ref: '' + ISNULL(@parmrefno, '''') + '' | combined total (invoices + manual lines)'';{NL}                DECLARE @CombPeriodEnd DATE = EOMONTH(@EffectiveDate);{NL}                EXEC dbo.sp_Payment_PostBankReconEntry{NL}                    @ItemType = ''OC'', @BranchCode = @parmPayingBranch, @AccountCode = @parmglcode, @PeriodEnd = @CombPeriodEnd,{NL}                    @ReferenceNo = @parmvoucherid, @ItemDate = @EffectiveDate, @Payee = @parmsuppliername, @Amount = @GrandTotal,{NL}                    @Remarks = @CombRemarks, @SourceModule = ''AP-PAYMENT'', @SourceRef = @parmrefno, @CreatedBy = @parmpreparedby;{NL}            END'),
    ('sp_ReverseCashAdvanceEntry', 1,
     N'        UPDATE BankStatementRecon{NL}        SET IsResolved     = 1,{NL}            ResolvedDate   = GETDATE(),{NL}            ResolvedBy     = @parmuser,{NL}            ResolvedReason = ''VOIDED - CASH ADVANCE REVERSED'',{NL}            UpdatedBy      = @parmuser,{NL}            DateTimeUpdated = GETDATE(){NL}        WHERE ReferenceNo = @CAVoucherID{NL}          AND ItemType IN (''OC'',''DIT''){NL}          AND IsResolved = 0;',
     N'        -- [88] H7: only this cash advance''s own items (voucher id + SourceModule + SourceRef), never another document''s under the same number;{NL}        --          refused while a LOCKED reconciliation month (the item''s own, or a later one) would change{NL}        IF EXISTS (SELECT 1 FROM dbo.BankStatementRecon b{NL}                   INNER JOIN dbo.BankReconHeader hb ON hb.HeaderID = b.HeaderID{NL}                   INNER JOIN dbo.BankReconHeader h WITH (HOLDLOCK) ON h.BranchCode = hb.BranchCode AND h.AccountCode = hb.AccountCode AND h.Status = ''LOCKED'' AND h.PeriodEnd >= hb.PeriodEnd{NL}                   WHERE b.ReferenceNo = @CAVoucherID AND b.SourceModule = ''CASH-ADVANCE'' AND b.SourceRef = @parmreferenceno AND b.IsResolved = 0){NL}            THROW 93027, ''Cannot reverse: a bank reconciliation month in which this cash advance''''s bank item counts is locked. Have that period unlocked first.'', 1;{NL}{NL}        UPDATE BankStatementRecon{NL}        SET IsResolved     = 1,{NL}            ResolvedDate   = GETDATE(),{NL}            ResolvedBy     = @parmuser,{NL}            ResolvedReason = ''VOIDED - CASH ADVANCE REVERSED'',{NL}            UpdatedBy      = @parmuser,{NL}            DateTimeUpdated = GETDATE(){NL}        WHERE ReferenceNo = @CAVoucherID AND SourceModule = ''CASH-ADVANCE'' AND SourceRef = @parmreferenceno{NL}          AND ItemType IN (''OC'',''DIT''){NL}          AND IsResolved = 0;'),
    ('sp_ReversePaymentClient', 1,
     N'    UPDATE BankStatementRecon{NL}    SET IsResolved     = 1,{NL}        ResolvedDate   = GETDATE(),{NL}        ResolvedReason = ''REVERSED''{NL}    WHERE SourceRef    = @refno{NL}      AND SourceModule = ''AR-PAYMENT''{NL}      AND ItemType     = ''DIT''{NL}      AND IsResolved   = 0;',
     N'    -- [88] H7: refused while a LOCKED reconciliation month in which the payment''s deposit counts (its own, or a later one) would change{NL}    IF EXISTS (SELECT 1 FROM dbo.BankStatementRecon b{NL}               INNER JOIN dbo.BankReconHeader hb ON hb.HeaderID = b.HeaderID{NL}               INNER JOIN dbo.BankReconHeader h WITH (HOLDLOCK) ON h.BranchCode = hb.BranchCode AND h.AccountCode = hb.AccountCode AND h.Status = ''LOCKED'' AND h.PeriodEnd >= hb.PeriodEnd{NL}               WHERE b.ReferenceNo = @refno AND b.SourceModule = ''AR-PAYMENT'' AND b.SourceRef = @refno AND b.ItemType = ''DIT'' AND b.IsResolved = 0){NL}        THROW 93028, ''Cannot reverse: a bank reconciliation month in which this payment''''s deposit counts is locked. Have that period unlocked first.'', 1;{NL}{NL}    UPDATE BankStatementRecon{NL}    SET IsResolved     = 1,{NL}        ResolvedDate   = GETDATE(),{NL}        ResolvedReason = ''REVERSED''{NL}    WHERE SourceRef    = @refno{NL}      AND SourceModule = ''AR-PAYMENT''{NL}      AND ItemType     = ''DIT''{NL}      AND IsResolved   = 0;'),
    ('sp_AddPaymentClient', 1,
     N'            @HeaderID    = @ReconHeaderID OUTPUT;{NL}{NL}        INSERT INTO BankStatementRecon',
     N'            @HeaderID    = @ReconHeaderID OUTPUT;{NL}{NL}        -- [88] H7: a payment whose deposit would count in a LOCKED reconciliation month (its own, or a later locked one) is refused{NL}        DECLARE @LockedP DATE = (SELECT MIN(PeriodEnd) FROM dbo.BankReconHeader WITH (HOLDLOCK){NL}                                 WHERE BranchCode = ''888'' AND AccountCode = @BankGLCode AND Status = ''LOCKED'' AND PeriodEnd >= @PeriodEnd);{NL}        IF @LockedP IS NOT NULL{NL}        BEGIN{NL}            DECLARE @LockedMsg NVARCHAR(400) = N''Bank reconciliation of account '' + ISNULL(@BankGLCode, N'''') + N'' is locked for the month ending '' + CONVERT(NVARCHAR(10), @LockedP, 120) + N''. A payment dated '' + CONVERT(NVARCHAR(10), @date, 120) + N'' would change that reconciliation: use a date in an open month after it, or have the period unlocked. Nothing was posted.'';{NL}            THROW 93022, @LockedMsg, 1;{NL}        END{NL}{NL}        INSERT INTO BankStatementRecon'),
    ('sp_PostCashAdvance', 1,
     N'            IF NOT EXISTS (SELECT 1 FROM BankStatementRecon{NL}                   WHERE ReferenceNo = @parmvoucherid AND AccountCode = @parmcreditaccount AND ItemType = ''OC''){NL}                INSERT INTO [dbo].[BankStatementRecon]{NL}                    (HeaderID, BranchCode, AccountCode, PeriodEnd,{NL}                     ItemType, ReferenceNo, ItemDate, Payee, Amount, Remarks,{NL}                     IsResolved, AddedBy, DateTimeAdded,{NL}                     SourceModule, SourceRef, ResolvedReason, CreatedBy, CreatedDate){NL}                VALUES{NL}                    (@ReconHeaderID, @parmbranchcode, @parmcreditaccount, @PeriodEnd, ''OC'',{NL}                     @parmvoucherid, @parmcheckdate, @parmpayeename, @TotalAmount,{NL}                     ''Auto-OC | CASH ADVANCE | Ref: '' + @parmrefno,{NL}                     0, @parmuser, GETDATE(), ''CASH-ADVANCE'', @parmrefno, '''', @parmuser, GETDATE());',
     N'            -- [88] H7: through the shared helper (the same posting again = no-op; another amount under the same key, or a locked month, is refused){NL}            DECLARE @CaOcRemarks VARCHAR(500) = ''Auto-OC | CASH ADVANCE | Ref: '' + @parmrefno;{NL}            EXEC dbo.sp_Payment_PostBankReconEntry{NL}                @ItemType = ''OC'', @BranchCode = @parmbranchcode, @AccountCode = @parmcreditaccount, @PeriodEnd = @PeriodEnd,{NL}                @ReferenceNo = @parmvoucherid, @ItemDate = @parmcheckdate, @Payee = @parmpayeename, @Amount = @TotalAmount,{NL}                @Remarks = @CaOcRemarks, @SourceModule = ''CASH-ADVANCE'', @SourceRef = @parmrefno, @CreatedBy = @parmuser;'),
    ('sp_PostCashAdvance', 2,
     N'            IF OBJECT_ID(''tempdb..#DitLines'') IS NOT NULL DROP TABLE #DitLines;{NL}            SELECT ROW_NUMBER() OVER (ORDER BY L.BranchCode, L.AccountCode) AS RowNum,{NL}                   L.BranchCode, L.AccountCode, L.Amount, L.Particulars{NL}            INTO #DitLines{NL}            FROM @Lines L{NL}            JOIN ChartOfAccounts coa ON coa.AccountCode = L.AccountCode{NL}            WHERE coa.AccountCode LIKE ''10102%'';{NL}{NL}            SELECT @ditMax = COUNT(*) FROM #DitLines;{NL}{NL}            WHILE @ditRow <= @ditMax{NL}            BEGIN{NL}                SELECT @ditBranch = BranchCode, @ditAccount = AccountCode, @ditAmount = Amount, @ditParticulars = Particulars{NL}                FROM #DitLines WHERE RowNum = @ditRow;{NL}{NL}                DECLARE @DitReconHeaderID INT, @DitPeriodEnd DATE = EOMONTH(@parmcheckdate);{NL}                EXEC sp_BankRecon_GetOrCreateHeader{NL}                    @BranchCode = @ditBranch, @AccountCode = @ditAccount,{NL}                    @PeriodEnd  = @DitPeriodEnd, @CreatedBy = @parmuser,{NL}                    @HeaderID   = @DitReconHeaderID OUTPUT;{NL}{NL}                IF NOT EXISTS (SELECT 1 FROM BankStatementRecon{NL}                       WHERE ReferenceNo = @parmvoucherid AND AccountCode = @ditAccount AND ItemType = ''DIT''){NL}                    INSERT INTO [dbo].[BankStatementRecon]{NL}                        (HeaderID, BranchCode, AccountCode, PeriodEnd,{NL}                         ItemType, ReferenceNo, ItemDate, Payee, Amount, Remarks,{NL}                         IsResolved, AddedBy, DateTimeAdded,{NL}                         SourceModule, SourceRef, ResolvedReason, CreatedBy, CreatedDate){NL}                    VALUES{NL}                        (@DitReconHeaderID, @ditBranch, @ditAccount, @DitPeriodEnd, ''DIT'',{NL}                         @parmvoucherid, @parmcheckdate, @parmpayeename, @ditAmount,{NL}                         ''Auto-DIT | FUND TRANSFER (via debit line) | Ref: '' + @parmrefno{NL}                         + CASE WHEN LEN(ISNULL(@ditParticulars,'''')) > 0 THEN '' | '' + @ditParticulars ELSE '''' END,{NL}                         0, @parmuser, GETDATE(), ''CASH-ADVANCE'', @parmrefno, '''', @parmuser, GETDATE());{NL}{NL}                SET @ditRow += 1;{NL}            END;{NL}            DROP TABLE #DitLines;',
     N'            -- [88] H7: one deposit per bank account (debit lines on the same account are added up: the helper keeps one item per reference, account and side){NL}            IF OBJECT_ID(''tempdb..#DitLines'') IS NOT NULL DROP TABLE #DitLines;{NL}            SELECT ROW_NUMBER() OVER (ORDER BY L.AccountCode) AS RowNum,{NL}                   MIN(L.BranchCode) AS BranchCode, L.AccountCode, SUM(L.Amount) AS Amount, COUNT(*) AS Lines_, MIN(L.Particulars) AS Particulars{NL}            INTO #DitLines{NL}            FROM @Lines L{NL}            JOIN ChartOfAccounts coa ON coa.AccountCode = L.AccountCode{NL}            WHERE coa.AccountCode LIKE ''10102%''{NL}            GROUP BY L.AccountCode;{NL}{NL}            SELECT @ditMax = COUNT(*) FROM #DitLines;{NL}{NL}            DECLARE @ditLines INT, @ditRemarks VARCHAR(500), @DitPeriodEnd DATE = EOMONTH(@parmcheckdate);{NL}            WHILE @ditRow <= @ditMax{NL}            BEGIN{NL}                SELECT @ditBranch = BranchCode, @ditAccount = AccountCode, @ditAmount = Amount, @ditParticulars = Particulars, @ditLines = Lines_{NL}                FROM #DitLines WHERE RowNum = @ditRow;{NL}{NL}                SET @ditRemarks = ''Auto-DIT | FUND TRANSFER (via debit line) | Ref: '' + @parmrefno{NL}                    + CASE WHEN @ditLines = 1 AND LEN(ISNULL(@ditParticulars,'''')) > 0 THEN '' | '' + @ditParticulars ELSE '''' END{NL}                    + CASE WHEN @ditLines > 1 THEN '' | '' + CAST(@ditLines AS VARCHAR(10)) + '' bank lines'' ELSE '''' END;{NL}                EXEC dbo.sp_Payment_PostBankReconEntry{NL}                    @ItemType = ''DIT'', @BranchCode = @ditBranch, @AccountCode = @ditAccount, @PeriodEnd = @DitPeriodEnd,{NL}                    @ReferenceNo = @parmvoucherid, @ItemDate = @parmcheckdate, @Payee = @parmpayeename, @Amount = @ditAmount,{NL}                    @Remarks = @ditRemarks, @SourceModule = ''CASH-ADVANCE'', @SourceRef = @parmrefno, @CreatedBy = @parmuser;{NL}{NL}                SET @ditRow += 1;{NL}            END;{NL}            DROP TABLE #DitLines;'),
    ('sp_AddPaymentSupplierCompound', 1,
     N'                    IF NOT EXISTS(SELECT 1 FROM BankStatementRecon{NL}                       WHERE ReferenceNo=@parmvoucherid AND AccountCode=@parmglcode{NL}                         AND ItemType=''OC''){NL}                    BEGIN{NL}                    EXEC sp_BankRecon_GetOrCreateHeader{NL}                    @BranchCode = ''888'', @AccountCode = @parmglcode,{NL}                    @PeriodEnd  = @PeriodEnd, @CreatedBy = @parmpreparedby,{NL}                    @HeaderID   = @ReconHeaderID OUTPUT;{NL}{NL}                    INSERT INTO [dbo].[BankStatementRecon]{NL}                        (HeaderID, BranchCode, AccountCode, PeriodEnd,{NL}                         ItemType, ReferenceNo, ItemDate, Payee, Amount, Remarks,{NL}                         IsResolved, AddedBy, DateTimeAdded,{NL}                         SourceModule, SourceRef, ResolvedReason, CreatedBy, CreatedDate){NL}                    VALUES(@ReconHeaderID, @ocBranch, @parmglcode, @ocPeriodEnd, ''OC'',{NL}                           @parmvoucherid, @parmcheckdate, @parmsuppliername, @TotalNetCashForRecon,{NL}                           ''Auto-OC | Invoice: ''+@InvoiceNo+'' | Ref: ''+@parmrefno,{NL}                           0, @parmpreparedby, GETDATE(), ''AP-PAYMENT'', @parmrefno, '''',{NL}                           @parmpreparedby, GETDATE());{NL}                    END',
     N'                    -- [88] H7: through the shared helper (one item per reference, account and side; a locked month is refused){NL}                    DECLARE @LegacyOcBranch VARCHAR(5) = ISNULL(@ocBranch, ''888'');{NL}                    DECLARE @LegacyOcRemarks VARCHAR(500) = ''Auto-OC | Invoice: ''+@InvoiceNo+'' | Ref: ''+@parmrefno;{NL}                    EXEC dbo.sp_Payment_PostBankReconEntry{NL}                        @ItemType = ''OC'', @BranchCode = @LegacyOcBranch, @AccountCode = @parmglcode, @PeriodEnd = @ocPeriodEnd,{NL}                        @ReferenceNo = @parmvoucherid, @ItemDate = @parmcheckdate, @Payee = @parmsuppliername, @Amount = @TotalNetCashForRecon,{NL}                        @Remarks = @LegacyOcRemarks, @SourceModule = ''AP-PAYMENT'', @SourceRef = @parmrefno, @CreatedBy = @parmpreparedby;'),
    ('sp_AddPaymentSupplierCompound', 2,
     N'                        IF NOT EXISTS(SELECT 1 FROM BankStatementRecon{NL}                           WHERE ReferenceNo=@parmvoucherid AND AccountCode=@parmglcode{NL}                             AND ItemType=''OC''){NL}                        BEGIN{NL}                        EXEC sp_BankRecon_GetOrCreateHeader{NL}                        @BranchCode = ''888'', @AccountCode = @parmglcode,{NL}                        @PeriodEnd  = @PeriodEnd, @CreatedBy = @parmpreparedby,{NL}                        @HeaderID   = @ReconHeaderID OUTPUT; {NL}{NL}                        INSERT INTO [dbo].[BankStatementRecon]{NL}                            (HeaderID, BranchCode, AccountCode, PeriodEnd,{NL}                             ItemType, ReferenceNo, ItemDate, Payee, Amount, Remarks,{NL}                             IsResolved, AddedBy, DateTimeAdded,{NL}                             SourceModule, SourceRef, ResolvedReason, CreatedBy, CreatedDate){NL}                        VALUES(@ReconHeaderID, ISNULL(@ocBranch,@br), @parmglcode,{NL}                               @ocPeriodEnd, ''OC'', @parmvoucherid, @parmcheckdate,{NL}                               @parmsuppliername, @TotalNetCashForRecon,{NL}                               ''Auto-OC | ''+LEFT(ISNULL(@allDescNames,''''),200){NL}                               +'' | Ref: ''+@parmrefno,{NL}                               0, @parmpreparedby, GETDATE(), ''AP-PAYMENT'', @parmrefno, '''',{NL}                               @parmpreparedby, GETDATE());{NL}                        END',
     N'                        -- [88] H7: through the shared helper (one item per reference, account and side; a locked month is refused){NL}                        DECLARE @LegacyOcBranch2 VARCHAR(5) = ISNULL(@ocBranch, ISNULL(@br, ''888''));{NL}                        DECLARE @LegacyOcRemarks2 VARCHAR(500) = ''Auto-OC | ''+LEFT(ISNULL(@allDescNames,''''),200)+'' | Ref: ''+@parmrefno;{NL}                        EXEC dbo.sp_Payment_PostBankReconEntry{NL}                            @ItemType = ''OC'', @BranchCode = @LegacyOcBranch2, @AccountCode = @parmglcode, @PeriodEnd = @ocPeriodEnd,{NL}                            @ReferenceNo = @parmvoucherid, @ItemDate = @parmcheckdate, @Payee = @parmsuppliername, @Amount = @TotalNetCashForRecon,{NL}                            @Remarks = @LegacyOcRemarks2, @SourceModule = ''AP-PAYMENT'', @SourceRef = @parmrefno, @CreatedBy = @parmpreparedby;');

    DECLARE @obj SYSNAME, @def NVARCHAR(MAX), @msg NVARCHAR(400), @a NVARCHAR(MAX), @r NVARCHAR(MAX), @cnt INT, @bak SYSNAME, @nl NCHAR(1) = NCHAR(10);
    DECLARE objs CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT Obj FROM @Patch;
    OPEN objs;
    FETCH NEXT FROM objs INTO @obj;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @def = OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + @obj));
        IF @def IS NULL BEGIN SET @msg = N'[88] ' + @obj + N' is missing here.'; THROW 59986, @msg, 1; END
        -- normalised to LF: two of the live texts mix CRLF and LF lines (the backup keeps the original bytes)
        SET @def = REPLACE(@def, NCHAR(13) + NCHAR(10), NCHAR(10));

        DECLARE pt CURSOR LOCAL FAST_FORWARD FOR SELECT Anchor, Repl FROM @Patch WHERE Obj = @obj ORDER BY Ord;
        OPEN pt;
        FETCH NEXT FROM pt INTO @a, @r;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @a = REPLACE(@a, N'{NL}', @nl);
            SET @r = REPLACE(@r, N'{NL}', @nl);
            SET @cnt = (LEN(@def) - LEN(REPLACE(@def, @a, N''))) / LEN(@a);
            IF @cnt <> 1 BEGIN SET @msg = N'[88] ' + @obj + N': anchor found ' + CAST(@cnt AS NVARCHAR(10)) + N' times (expected 1): ' + LEFT(REPLACE(@a, @nl, N'|'), 120); THROW 59986, @msg, 1; END
            SET @def = REPLACE(@def, @a, @r);
            FETCH NEXT FROM pt INTO @a, @r;
        END
        CLOSE pt; DEALLOCATE pt;

        IF CHARINDEX(N'[88]', @def) = 0 BEGIN SET @msg = N'[88] ' + @obj + N': marker missing after patching.'; THROW 59986, @msg, 1; END
        SET @bak = @obj + N'_OLD_10152026120000';
        SET @a = N'dbo.' + @obj;
        EXEC sp_rename @a, @bak;
        EXEC (@def);
        PRINT N'[88] ' + @obj + N': patched (backup ' + @bak + N').';
        FETCH NEXT FROM objs INTO @obj;
    END
    CLOSE objs; DEALLOCATE objs;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @em NVARCHAR(2048) = N'[88] stopped, nothing changed (while patching ' + ISNULL(@obj, N'?') + N'): ' + ERROR_MESSAGE();
    RAISERROR(@em, 16, 1);
    SET NOEXEC ON;
END CATCH
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[88] an earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- post-check: every object carries the marker, 14 backups, the index
IF (SELECT COUNT(*) FROM sys.objects o WHERE o.name IN ('sp_Payment_PostBankReconEntry','sp_JV_PostBankReconForLines','sp_BankRecon_DeleteItem','sp_BankRecon_SaveItem','sp_BankRecon_UpdateItem','sp_BankRecon_AutoMatch',
                                                       'sp_EditManualJournalVoucher','sp_EditExpenseManualMultiBranch','sp_PostSupplierPaymentWithManualLines','sp_ReverseCashAdvanceEntry','sp_ReversePaymentClient','sp_AddPaymentClient','sp_PostCashAdvance','sp_AddPaymentSupplierCompound')
        AND CHARINDEX('[88]', OBJECT_DEFINITION(o.object_id)) > 0) <> 14
   OR (SELECT COUNT(*) FROM sys.objects WHERE name LIKE '%[_]OLD[_]10152026120000') <> 14
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.BankStatementRecon') AND name = 'IX_BankStatementRecon_RefAccountType')
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[88] post-check failed; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
GO

SET NOEXEC OFF;
GO
SELECT DB_NAME() AS DatabaseName, name, CONVERT(VARCHAR(16), modify_date, 120) AS Modified FROM sys.objects
WHERE name IN ('sp_Payment_PostBankReconEntry','sp_JV_PostBankReconForLines','sp_BankRecon_DeleteItem','sp_BankRecon_SaveItem','sp_BankRecon_UpdateItem','sp_BankRecon_AutoMatch',
               'sp_EditManualJournalVoucher','sp_EditExpenseManualMultiBranch','sp_PostSupplierPaymentWithManualLines','sp_ReverseCashAdvanceEntry','sp_ReversePaymentClient','sp_AddPaymentClient','sp_PostCashAdvance','sp_AddPaymentSupplierCompound')
   OR name LIKE '%[_]OLD[_]10152026120000'
UNION ALL SELECT DB_NAME(), name, NULL FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.BankStatementRecon') AND name = 'IX_BankStatementRecon_RefAccountType'
ORDER BY name;
