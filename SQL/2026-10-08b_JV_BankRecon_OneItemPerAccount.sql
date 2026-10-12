/* ================================================================
   2026-10-08b: Manual JV bank recon items: one item per JV, bank account and side
   ================================================================
   sp_JV_PostBankReconForLines creates the Bank Recon rows (DIT for a debit
   to a bank account, OC for a credit) after a Manual JV is posted or edited.
   Callers (unchanged): sp_PostManualJournalVoucher,
   sp_PostManualJournalVoucherMultiBranch, sp_EditManualJournalVoucher,
   sp_PostExpenseManualMultiBranch, sp_EditExpenseManualMultiBranch.

   Bug (Known Bug Pattern #9): it called sp_Payment_PostBankReconEntry once
   per bank LINE. That helper is idempotent by ReferenceNo + AccountCode +
   ItemType, so every line after the first on the same account and side was
   silently dropped. Example: JV 32412 (MBTC PESO 2) has 6 bank credit lines,
   383,499.06; only the first (3,746.25) got an OC.

   Fix (user rule 2026-10-08: one item per JV): the bank lines are added up
   per bank account and side first; each account gets one DIT (total debit)
   and / or one OC (total credit) with the full amount, through the same
   helper. A one-line JV produces exactly what it did before (same branch,
   date, amount, remarks). The branch of a multi-line item is the lowest
   branch code of its lines, the line that won under the old row order.
   Remarks gain " | n bank lines" when n > 1.
   Same parameters; no exe change. Backup: _OLD_10082026120000.
   ================================================================ */

SET XACT_ABORT ON;
BEGIN TRANSACTION;
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
IF OBJECT_ID('dbo.sp_JV_PostBankReconForLines_OLD_10082026120000', 'P') IS NOT NULL
BEGIN
    RAISERROR('sp_JV_PostBankReconForLines_OLD_10082026120000 already exists: this script has been run here before.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC sp_rename 'dbo.sp_JV_PostBankReconForLines', 'sp_JV_PostBankReconForLines_OLD_10082026120000';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE PROCEDURE dbo.sp_JV_PostBankReconForLines
(
    @ReferenceNo   VARCHAR(10),
    @VoucherDate   DATE,
    @DefaultBranch VARCHAR(5) = NULL,   -- used only if a detail row's own branch is somehow unavailable
    @CreatedBy     VARCHAR(50)
)
AS
/*
    Reads what was just posted to ManualJournalVoucher / ManualJournalVoucherDetails
    for @ReferenceNo and creates one Bank Recon item per bank account and side:
    DIT = the account's total debit, OC = its total credit (2026-10-08b; it used to
    post per line, and the idempotent helper dropped every line after the first).
*/
BEGIN
    SET NOCOUNT ON;

    DECLARE @PeriodEnd DATE = EOMONTH(@VoucherDate);

    IF OBJECT_ID('tempdb..#JVBankItems') IS NOT NULL DROP TABLE #JVBankItems;

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
    SELECT  ROW_NUMBER() OVER (ORDER BY AccountCode, ItemType) AS RowNum,
            AccountCode, ItemType,
            MIN(BranchCode)  AS BranchCode,
            SUM(Amount)      AS Amount,
            COUNT(*)         AS Lines,
            MIN(Particulars) AS Particulars
    INTO #JVBankItems
    FROM Sides
    GROUP BY AccountCode, ItemType;

    DECLARE @i INT = 1, @maxi INT, @itBranch VARCHAR(5), @itAccount VARCHAR(20), @itType VARCHAR(5),
            @itAmount DECIMAL(18,2), @itLines INT, @itParticulars VARCHAR(500), @Remarks VARCHAR(1000);

    SELECT @maxi = COUNT(*) FROM #JVBankItems;

    WHILE @i <= @maxi
    BEGIN
        SELECT @itBranch = BranchCode, @itAccount = AccountCode, @itType = ItemType,
               @itAmount = Amount, @itLines = Lines, @itParticulars = Particulars
        FROM #JVBankItems WHERE RowNum = @i;

        SET @Remarks = CASE WHEN @itType = 'DIT'
                            THEN 'Auto-DIT | MANUAL JV | Ref: ' + ISNULL(@ReferenceNo, '')
                                 + CASE WHEN @itLines = 1 THEN ISNULL(' | ' + @itParticulars, '') ELSE '' END
                            ELSE 'Auto-OC | MANUAL JV | Ref: ' + ISNULL(@ReferenceNo, '') END
                     + CASE WHEN @itLines > 1 THEN ' | ' + CAST(@itLines AS VARCHAR(10)) + ' bank lines' ELSE '' END;

        EXEC dbo.sp_Payment_PostBankReconEntry
            @ItemType = @itType, @BranchCode = @itBranch, @AccountCode = @itAccount,
            @PeriodEnd = @PeriodEnd, @ReferenceNo = @ReferenceNo, @ItemDate = @VoucherDate,
            @Payee = @CreatedBy, @Amount = @itAmount,
            @Remarks = @Remarks,
            @SourceModule = 'MANUAL-JV', @SourceRef = @ReferenceNo, @CreatedBy = @CreatedBy;

        SET @i += 1;
    END;

    DROP TABLE #JVBankItems;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
IF OBJECT_ID('dbo.sp_JV_PostBankReconForLines', 'P') IS NULL OR OBJECT_ID('dbo.sp_JV_PostBankReconForLines_OLD_10082026120000', 'P') IS NULL
BEGIN
    RAISERROR('Post-check failed: the new procedure or its backup is missing; rolled back.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
COMMIT TRANSACTION;
PRINT 'sp_JV_PostBankReconForLines replaced (backup _OLD_10082026120000).';
GO
SET NOEXEC OFF;
GO
