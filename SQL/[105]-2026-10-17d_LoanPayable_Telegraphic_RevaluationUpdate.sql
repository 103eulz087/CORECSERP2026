/* ================================================================
   [105] 2026-10-17d  Loan Revaluation: the loan as a payable in Vouchering Telegraphic, moved by every revaluation
   ================================================================
   User (2026-10-17): "balance forward the July so that it becomes an invoice principal balance, so it will reflect in
   VoucherManualForm (Telegraphic) and the ActualCost column is the revaluation value the 56,407,600. Then when doing
   revaluation ... the actualcost amount in principal should also be update. It will update every month." (+ a grid for
   the automatic entry on the screen: C#, no SQL).
   User decisions (2026-10-17): supplier = PROFOOD GMBH 000125 (the loan's own supplier); Actual Cost always = the
   current value (= Balance), not "original + revaluations".

   RULES
   - The loan's payable = ONE ExpenseSummary row (PostingMode 'LOAN', InvoiceNo = the loan code LOAN051618, supplier =
     the loan's, PayableAccountCode = the loan's liability account 20203) + ONE ExpenseMaster line (the loan's branch)
     + supplier-ledger rows; LoanAccount.PayableBatchReferenceID points at it. Vouchering Telegraphic (Expense) lists it
     (ActualCost = Amount, Balance) and sp_PostVoucherManual pays it: DR 20203 (PayableAccountCode) / CR bank, partial
     payments allowed (Variance only on a full settlement, 58033 as for any invoice), supplier-ledger debit.
   - No GL of its own: the July opening (ticket 1) and the revaluations already carry 20203.
   - The load (this script) creates it at the loan's CURRENT position: Amount = Balance = the last POSTED peso balance
     (07-31 opening 56,407,600 + 08-31 revaluation 1,136,800 = 57,544,400 on every tier today), which must equal GL 20203
     on the loan's branch, all dates (else the load stops, 59951). Ledger: one credit per POSTED loan entry (opening
     LOAN-BF 07-31; each revaluation LOAN-REVAL on its date / ticket / reference: credit for a loss, debit for a gain).
   - spu_Loan_PostRevaluation: FIRST (before the GL is read) the payable row is read under UPDLOCK (a telegraphic payment
     of the loan locks the same row, so none can commit in between) and must = GL (liability, branch, all dates; 62030);
     then Balance = Balance + the change = the new value, Amount = Amount + the change (the gross: a payment reversal
     keeps Balance <= Amount, sp_CancelledChequesCS 60506), never below 0 (62033), Status POSTED / PARTIAL, line the same
     (62031: exactly one line), ledger row LOAN-REVAL; post-check 62032 (payable = GL = its ledger rows).
     **What the user sees as Actual Cost** (decision: always the current value) is the Balance: splist_Accounts' expense
     list shows a loan's ActualCost = its Balance (with no payment yet, Amount = Balance anyway).
   - spu_Loan_ReverseRevaluation: the same check (62030), the payable back by the change (62033 below 0), ledger row the
     other way dated like the revaluation (PaymentType REVERSAL); post-check 62032.
   - sp_PostSupplierAdjustmentMemo: a memo on the loan payable is refused (58041; it would move the payable without the GL).
   - A loan fully paid (Balance 0, GL 0) stays on the Loan Revaluation screen: its revaluation is refused (62020 / 62021)
     until a "closed" state exists (none yet; ask when the first loan is paid off).
   - sp_PostVoucherManual: a loan payable is paid from the loan's own branch only (58040); the voucher posts its GL on the
     paying branch and the loan is kept on its branch's GL. Nothing else changes in it.
   - sp_Loan_GetAccounts: + PayableInvoiceNo / PayableAmount / PayableBalance / PayableAmountPaid (last columns).
   - The loan payable stays out of every other payment path (sweep of the 47 readers of ExpenseSummary / ExpenseMaster,
     2026-10-17): splist_Accounts' purchase + expense list (Supplier Payment cash / check) and
     sp_GetUnpaidInvoicesForSupplier (Combined Supplier Voucher) leave PostingMode 'LOAN' out; sp_AddPaymentSupplierCompound_V2
     and the legacy sp_AddPaymentSupplierCompound refuse it (60540: they would settle it through the BATCH path and debit
     20103); view_ExpenseSummary (old expense screens that list / reverse / edit) leaves it out. Not changed here (the web
     portal's, told in the sync handoff): sp_rpt_APEXP_Aging, sp_rpt_DataHealthCheck / _Detail check 13. Unchanged on
     purpose: splist_Accounts' expense-only list (Vouchering Telegraphic) and the AP Exception Center checks (they watch
     the payable: balance = its supplier-ledger rows).

   Measured first (2026-10-17, read-only): spu_Loan_PostRevaluation 78155AA6…, spu_Loan_ReverseRevaluation 6312630…,
   sp_Loan_GetAccounts AE07E8B8…, sp_PostVoucherManual 47F24B92… identical on DEV / STAGING / PRODUCTION; loan
   LOAN051618 (LoanID 1, 000125, EUR, branch 888, 20203): OPENING 07-31 800,000 @70.5095 = 56,407,600 and REVALUATION
   08-31 @71.9305 +1,136,800 = 57,544,400 POSTED on every tier; GL 20203 = 57,544,400 on 888 and in all; no ExpenseSummary
   row with PostingMode 'LOAN' or invoice LOAN051618, no ledger row of it; codes 58040-58049 / 62030-62039 unused.
   Guard: the four live hashes. Full recreate of each (rename to _OLD_10172026210000 + CREATE with the full new text,
   generated from the live text by exact-count replacements). New column LoanAccount.PayableBatchReferenceID.
   Exe: the old exe works on it (the loan shows in Vouchering Telegraphic at once; the Loan Revaluation screen posts as
   before and the payable moves with it). The new exe shows the entry as a grid and the payable's figures; it reads the
   new columns of sp_Loan_GetAccounts, so it needs [105]. Web v2: pay the loan through sp_PostVoucherManual only, from the
   loan's branch; never change the payable by hand (the revaluation refuses, 62030).
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
    RAISERROR('[105] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.LoanAccount', 'U') IS NULL OR OBJECT_ID('dbo.spu_Loan_PostRevaluation', 'P') IS NULL OR OBJECT_ID('dbo.spu_Loan_ReverseRevaluation', 'P') IS NULL
     OR OBJECT_ID('dbo.sp_Loan_GetAccounts', 'P') IS NULL OR OBJECT_ID('dbo.sp_PostVoucherManual', 'P') IS NULL
BEGIN
    RAISERROR('[105] stopped: needs [65] / [81] (Loan Revaluation) and sp_PostVoucherManual; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.spu_Loan_PostRevaluation')), N'') LIKE '%[[]105]%'
BEGIN
    RAISERROR('[105] already applied in this database; nothing changed.', 10, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.spu_Loan_PostRevaluation_OLD_10172026210000') IS NOT NULL OR OBJECT_ID('dbo.spu_Loan_ReverseRevaluation_OLD_10172026210000') IS NOT NULL
     OR OBJECT_ID('dbo.sp_Loan_GetAccounts_OLD_10172026210000') IS NOT NULL OR OBJECT_ID('dbo.sp_PostVoucherManual_OLD_10172026210000') IS NOT NULL
     OR OBJECT_ID('dbo.splist_Accounts_OLD_10172026210000') IS NOT NULL OR OBJECT_ID('dbo.sp_GetUnpaidInvoicesForSupplier_OLD_10172026210000') IS NOT NULL
     OR OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2_OLD_10172026210000') IS NOT NULL OR OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_OLD_10172026210000') IS NOT NULL
     OR OBJECT_ID('dbo.view_ExpenseSummary_OLD_10172026210000') IS NOT NULL OR OBJECT_ID('dbo.sp_PostSupplierAdjustmentMemo_OLD_10172026210000') IS NOT NULL
BEGIN
    RAISERROR('[105] stopped: a backup _OLD_10172026210000 already exists; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.spu_Loan_PostRevaluation')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '78155AA67101BF24A71D9D5F53C29C0D96C88CA1BBF1F61EC105AC6B14D3C55B'
     OR CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.spu_Loan_ReverseRevaluation')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '6312630098FDB2FF01ABC0BCCF2C6CDD2BFE5B171469AC05E0F06C13DF36EFAF'
     OR CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_Loan_GetAccounts')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> 'AE07E8B86E4F3A8C49E53EED32E5A5DC1DA17AE903CA7399469C1AC0ED86CA70'
     OR CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostVoucherManual')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '47F24B92A1D2D8F216B268ED2030749EA6B3A674D0EBACC355EE1FAF6E6B13E6'
     OR CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.splist_Accounts')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '96CAE8C61C823D8696501C3AE8677213A1D3D319BCBE2E00F0C901B05AE98C1F'
     OR CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetUnpaidInvoicesForSupplier')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '2669D2065F06451052596D4CC8329D0926266C35490BA52938DECABD747706E2'
     OR CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> 'AB8C6A24456254D70AE2CCDCC5F41F895FE566EFCF092641B1B1B52EB56C7F93'
     OR CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '3C026EDC488E3C8C7B337DB87B129F268130454D166FC394152FF728EAA6B7D6'
     OR CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.view_ExpenseSummary')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '0D99AE43434F7138990AC1C8CDFD5D5641B2B170C088EA14B6096B868B089760'
     OR CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostSupplierAdjustmentMemo')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> 'B393070E9211D99669718B269467044D550E58CA530AED6639FB1C701C2449A2'
BEGIN
    RAISERROR('[105] stopped: a loan proc or sp_PostVoucherManual is not the text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF EXISTS (SELECT 1 FROM dbo.ExpenseSummary WHERE PostingMode = 'LOAN')
BEGIN
    RAISERROR('[105] stopped: a loan payable (PostingMode LOAN) already exists here; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[105] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
GO

------------------------------------------------------------------
-- 1. LoanAccount.PayableBatchReferenceID
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
IF COL_LENGTH('dbo.LoanAccount', 'PayableBatchReferenceID') IS NULL
    ALTER TABLE dbo.LoanAccount ADD PayableBatchReferenceID BIGINT NULL;   -- [105] the loan's payable (ExpenseSummary.BatchReferenceID)
GO



------------------------------------------------------------------
-- 3. spu_Loan_PostRevaluation (the payable moves with the revaluation)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.spu_Loan_PostRevaluation', 'spu_Loan_PostRevaluation_OLD_10172026210000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
-- 2. spu_Loan_PostRevaluation ----------------------------------------------------------------------------------------------

CREATE PROCEDURE dbo.spu_Loan_PostRevaluation
    @LoanID              INT,
    @RevalDate           DATE,
    @Rate                DECIMAL(18,6),
    @ExpectedPhpBalance  DECIMAL(18,2),        -- the peso balance the screen showed (stale-screen guard)
    @User                VARCHAR(60),
    @Description         VARCHAR(300) = NULL,  -- blank = 'LOANCODE - FOREX REVALUATION mm.dd.yy (E800000 @1.7147)'
    @ForeignBalance      DECIMAL(18,2) = NULL, -- [81] the foreign balance to revalue (screen box, pre-filled); NULL = the loan's own
    @ControlNo           VARCHAR(30) = NULL    -- [81] their reference coding: saved on the loan entry and shown on the GL ticket
AS
/*  [81] 2026-10-14 (user): the foreign balance is an editable box on the screen (it was shown as text) and a Control No. is
    kept. A typed balance different from the loan's (e.g. 700,000 after a principal payment) becomes the loan's new foreign
    balance. The principal payment itself is booked elsewhere (voucher to the liability account), so GL already holds it:
    the forex entry is new peso balance - GL balance up to the date (= - the loan's peso balance when nothing else moved).
    The GL is checked against the loan: unchanged balance -> GL must equal the loan (62020, as before); changed balance -> the
    GL movement since the last entry must be in the same direction and at a rate within 20% of the last rate (62022), so a
    wrong figure or a hand-booked revaluation is refused instead of posted as forex. */
/*  Month-end revaluation of a foreign-currency loan: new peso balance = foreign balance x @Rate, rounded to centavos;
    the difference to the current peso balance is posted on the loan's branch, dated @RevalDate:
      liability up (loss):   DR forex loss (LOAN-REVAL FXLOSS) / CR the loan's LiabilityAccount
      liability down (gain): DR the loan's LiabilityAccount    / CR forex gain (LOAN-REVAL FXGAIN)
    Errors 62001-62009, 62016, 62018-62020 (refusals); a closed GL month is refused by the period-lock trigger (59900).
    [105] 2026-10-17: the loan is also a payable (ExpenseSummary PostingMode 'LOAN', LoanAccount.PayableBatchReferenceID)
    paid through Vouchering Telegraphic. Its balance must equal GL (liability account, loan branch, all dates; 62030); the
    revaluation moves it by the forex change: Actual Cost (Amount) = Balance = the new value (user: always the current
    value), plus a supplier-ledger row (credit for a loss, debit for a gain). Post-check 62032.
    Returns one row: TxnID, TicketNumber, ReferenceNumber, PhpChange, NewPhpBalance, Message. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @msg NVARCHAR(400);

    IF @RevalDate IS NULL OR @RevalDate <> EOMONTH(@RevalDate)
        THROW 62002, 'The revaluation date must be a month end (the last day of a month).', 1;
    IF @Rate IS NULL OR @Rate <= 0
        THROW 62003, 'Enter the month-end rate (greater than 0).', 1;
    IF ISNULL(LTRIM(@User), '') = ''
        THROW 62009, 'The user is required.', 1;
    IF @ForeignBalance IS NOT NULL AND @ForeignBalance <= 0   -- [81]
        THROW 62021, 'The loan balance to revalue must be greater than 0.', 1;
    SET @ControlNo = NULLIF(LTRIM(RTRIM(@ControlNo)), '');

    BEGIN TRY
        BEGIN TRAN;
        DECLARE @lock INT, @res NVARCHAR(100) = N'LOAN:' + CAST(@LoanID AS NVARCHAR(20));
        EXEC @lock = sp_getapplock @Resource = @res, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
        IF @lock < 0 THROW 62008, 'This loan is being updated by someone else right now. Please try again.', 1;

        DECLARE @code VARCHAR(30), @cur CHAR(3), @branch VARCHAR(5), @liab VARCHAR(20), @supplier VARCHAR(50), @active BIT;
        SELECT @code = LoanCode, @cur = Currency, @branch = BranchCode, @liab = LiabilityAccount, @supplier = SupplierID, @active = IsActive
        FROM dbo.LoanAccount WHERE LoanID = @LoanID;
        IF @code IS NULL OR @active = 0 THROW 62001, 'The loan is not found or not active.', 1;

        DECLARE @lastDate DATE, @lastRate DECIMAL(18,6), @fBal DECIMAL(18,2), @pBal DECIMAL(18,2);
        SELECT TOP 1 @lastDate = TxnDate, @lastRate = Rate, @fBal = ForeignBalance, @pBal = PhpBalance
        FROM dbo.LoanTransaction WHERE LoanID = @LoanID AND Status = 'POSTED' ORDER BY TxnDate DESC, TxnID DESC;
        IF @lastDate IS NULL THROW 62001, 'The loan has no opening balance.', 1;
        IF @RevalDate <= @lastDate
        BEGIN
            SET @msg = N'The revaluation date must be after the loan''s last entry (' + CONVERT(NVARCHAR(10), @lastDate, 120)
                     + N'). Months are revalued in order, one per month.';
            THROW 62004, @msg, 1;
        END
        -- review S2: the very next month (no gaps), and not in the future
        IF @RevalDate <> EOMONTH(DATEADD(DAY, 1, @lastDate)) OR @RevalDate > EOMONTH(CAST(GETDATE() AS DATE))
        BEGIN
            SET @msg = N'The next revaluation of this loan is ' + CONVERT(NVARCHAR(10), EOMONTH(DATEADD(DAY, 1, @lastDate)), 120)
                     + N' (months are revalued one after another, never ahead of the current month).';
            THROW 62016, @msg, 1;
        END
        IF @ExpectedPhpBalance IS NULL OR @ExpectedPhpBalance <> @pBal
        BEGIN
            SET @msg = N'The loan''s balance is now ' + CONVERT(NVARCHAR(30), @pBal) + N' but the screen showed '
                     + ISNULL(CONVERT(NVARCHAR(30), @ExpectedPhpBalance), N'nothing') + N'. Refresh and try again.';
            THROW 62005, @msg, 1;
        END
        -- [105] the loan's payable must agree with the GL before it moves with it (a payment booked outside Vouchering
        --       Telegraphic, or a hand edit, would otherwise be carried into the new balance). Read FIRST, under UPDLOCK:
        --       a telegraphic payment of the loan locks the same row, so none can commit between this and the GL read below.
        DECLARE @payBatch BIGINT = (SELECT PayableBatchReferenceID FROM dbo.LoanAccount WHERE LoanID = @LoanID);
        DECLARE @invBal DECIMAL(18,2), @glAll DECIMAL(18,2);
        IF @payBatch IS NOT NULL
        BEGIN
            SELECT @invBal = CAST(Balance AS DECIMAL(18,2)) FROM dbo.ExpenseSummary WITH (UPDLOCK, ROWLOCK)
            WHERE BatchReferenceID = @payBatch AND SupplierID = @supplier AND InvoiceNo = @code AND PostingMode = 'LOAN';
            SET @glAll = ISNULL((SELECT SUM(ISNULL(d.Credit, 0) - ISNULL(d.Debit, 0)) FROM dbo.TicketDetails AS d
                                 WHERE d.AccountCode = @liab AND d.BranchCode = @branch), 0);
            IF @invBal IS NULL OR @invBal <> @glAll
            BEGIN
                SET @msg = N'The loan''s payable ' + @code + N' (Vouchering Telegraphic) shows ' + ISNULL(CONVERT(NVARCHAR(30), @invBal), N'nothing')
                         + N' but GL ' + @liab + N' on branch ' + @branch + N' is ' + CONVERT(NVARCHAR(30), @glAll)
                         + N'. A payment was booked outside Vouchering Telegraphic, or the payable was changed by hand; sort it out first.';
                THROW 62030, @msg, 1;
            END
        END

        -- review S1: the loan must agree with the GL. If anything else was booked to the liability account on the branch
        -- up to this date (e.g. a revaluation already entered by hand as a Manual JV), posting would count it twice.
        DECLARE @glBal DECIMAL(18,2) = ISNULL((SELECT SUM(ISNULL(d.Credit, 0) - ISNULL(d.Debit, 0)) FROM dbo.TicketDetails AS d
                                               WHERE d.AccountCode = @liab AND d.BranchCode = @branch
                                                 AND d.TicketDate < DATEADD(DAY, 1, CAST(@RevalDate AS DATETIME))), 0);
        -- [81] the balance to revalue: the typed one, else the loan's
        DECLARE @newF DECIMAL(18,2) = ISNULL(@ForeignBalance, @fBal);
        IF @newF = @fBal AND @glBal <> @pBal
        BEGIN
            SET @msg = N'GL ' + @liab + N' on branch ' + @branch + N' up to ' + CONVERT(NVARCHAR(10), @RevalDate, 120) + N' is '
                     + CONVERT(NVARCHAR(30), @glBal) + N' but the loan says ' + CONVERT(NVARCHAR(30), @pBal)
                     + N' (difference ' + CONVERT(NVARCHAR(30), @glBal - @pBal) + N'). Something else was posted to that account '
                     + N'(e.g. this revaluation entered by hand, or a principal payment: then type the loan''s new balance); '
                     + N'sort it out first so it isn''t counted twice.';
            THROW 62020, @msg, 1;
        END
        IF @newF <> @fBal
        BEGIN
            -- the GL movement since the last entry must match the principal change: same direction, rate within 20%
            DECLARE @dF DECIMAL(18,2) = @newF - @fBal, @dP DECIMAL(18,2) = @glBal - @pBal;
            IF @dP = 0 OR SIGN(@dF) <> SIGN(@dP) OR @dP / @dF < @lastRate * 0.8 OR @dP / @dF > @lastRate * 1.2
            BEGIN
                SET @msg = N'The loan balance changes by ' + CONVERT(NVARCHAR(30), @dF) + N' ' + @cur + N' but GL ' + @liab + N' on branch '
                         + @branch + N' moved by ' + CONVERT(NVARCHAR(30), @dP) + N' since the last entry (loan '
                         + CONVERT(NVARCHAR(30), @pBal) + N', GL ' + CONVERT(NVARCHAR(30), @glBal) + N'). Book the principal '
                         + N'payment to ' + @liab + N' first, or check the balance typed.';
                THROW 62022, @msg, 1;
            END
        END

        DECLARE @newBal DECIMAL(18,2) = ROUND(@newF * @Rate, 2);
        DECLARE @change DECIMAL(18,2) = @newBal - @glBal;   -- [81] = @newBal - @pBal when the balance didn't change (GL = loan)
        IF @change = 0 THROW 62006, 'Nothing to post: the peso balance doesn''t change at this rate.', 1;

        DECLARE @lossAcct VARCHAR(50) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'LOAN-REVAL' AND AmountType = 'FXLOSS' AND IsActive = 1 ORDER BY Seq),
                @gainAcct VARCHAR(50) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'LOAN-REVAL' AND AmountType = 'FXGAIN' AND IsActive = 1 ORDER BY Seq);
        IF (@change > 0 AND @lossAcct IS NULL) OR (@change < 0 AND @gainAcct IS NULL)
            THROW 62007, 'JournalEntryMapping LOAN-REVAL (FXLOSS / FXGAIN) is missing or inactive.', 1;
        -- review S7: the mapped forex account must exist and can't be the loan account itself
        IF NOT EXISTS (SELECT 1 FROM dbo.ChartOfAccounts WHERE AccountCode = CASE WHEN @change > 0 THEN @lossAcct ELSE @gainAcct END)
           OR CASE WHEN @change > 0 THEN @lossAcct ELSE @gainAcct END = @liab
            THROW 62007, 'The LOAN-REVAL forex account is not in the chart of accounts, or is the loan''s own account.', 1;

        -- Peachtree-style description: 'LOAN051618 - FOREX REVALUATION 09.30.26 (E800000 @1.7147)'
        IF NULLIF(LTRIM(RTRIM(@Description)), '') IS NULL
            SET @Description = @code + ' - FOREX REVALUATION ' + FORMAT(@RevalDate, 'MM.dd.yy', 'en-US') + ' (' + LEFT(@cur, 1)
                             + FORMAT(@newF, '0.##', 'en-US') + ' @' + FORMAT(ABS(@Rate - @lastRate), '0.####', 'en-US') + ')';

        -- ticket no. first, then the reference no. (review S5: same order as the Manual JV, which takes a ticket no. only)
        DECLARE @tn VARCHAR(10);
        EXEC dbo.GetTicketNumber @tn OUTPUT;
        -- the next reference no., same counter and rule as sp_GetReferenceNumber (read inline: an INSERT-EXEC of it
        -- here would break any caller that itself runs this proc through INSERT-EXEC)
        DECLARE @refInt INT;
        UPDATE dbo.ReferenceNumber WITH (TABLOCKX, HOLDLOCK)
        SET @refInt = ReferenceNumber,
            ReferenceNumber = CASE WHEN ReferenceNumber > 99999 THEN 1 ELSE ReferenceNumber + 1 END;
        IF @refInt IS NULL THROW 62018, 'The reference-number counter (dbo.ReferenceNumber) is empty.', 1;
        IF @refInt > 99999 SET @refInt = 0;
        DECLARE @refno VARCHAR(20) = CONVERT(VARCHAR(10), @refInt);

        INSERT INTO dbo.TicketMaster
            (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber, ReferenceNumber, ReferenceKey, Owner, Particulars,
             EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
        VALUES
            (@RevalDate, 0, @branch, 'JV', @tn, @refno, @code, @supplier,
             @Description + ISNULL(' | CONTROL NO. ' + @ControlNo, ''),   -- [81]
             @User, '*', '*', 'POSTED', 'LOAN-REVAL', NULL);

        INSERT INTO dbo.TicketDetails
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey, TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        SELECT @RevalDate, 0, @branch, @code, @tn, @refno, l.AccountCode, l.Debit, l.Credit, ''
        FROM (VALUES (1, CASE WHEN @change > 0 THEN @lossAcct ELSE @liab END, ABS(@change), CAST(0 AS DECIMAL(18,2))),
                     (2, CASE WHEN @change > 0 THEN @liab ELSE @gainAcct END, CAST(0 AS DECIMAL(18,2)), ABS(@change))) AS l (Seq, AccountCode, Debit, Credit)
        ORDER BY l.Seq;

        INSERT INTO dbo.LoanTransaction
            (LoanID, TxnDate, TxnType, Rate, PrevRate, ForeignChange, PhpChange, ForeignBalance, PhpBalance, ReferenceNumber, TicketNumber, Description, PostedBy, ControlNo)
        VALUES
            (@LoanID, @RevalDate, 'REVALUATION', @Rate, @lastRate, @newF - @fBal, @change, @newF, @newBal, @refno, @tn, @Description, LEFT(@User, 60), @ControlNo);
        DECLARE @txn INT = SCOPE_IDENTITY();

        -- [105] the payable moves with the loan by the change: Balance = the new value; Amount (gross) by the same change, so a
        --       payment reversal still finds Balance <= Amount (sp_CancelledChequesCS 60506); Vouchering Telegraphic shows a
        --       loan's Actual Cost as its Balance (splist_Accounts), i.e. the current value. Supplier-ledger row for the change.
        IF @payBatch IS NOT NULL
        BEGIN
            DECLARE @invNew DECIMAL(18,2) = @invBal + @change;
            IF @invNew < 0 THROW 62033, 'The revaluation would take the loan''s payable below 0 (more was paid than the new value); check the balance typed. Nothing was posted.', 1;
            UPDATE dbo.ExpenseSummary
            SET Amount = ISNULL(Amount, 0) + @change, Balance = @invNew,
                Status = CASE WHEN ISNULL(AmountPaid, 0) > 0 THEN 'PARTIAL' ELSE 'POSTED' END,
                UpdatedBy = LEFT(@User, 30), DateTimeUpdated = GETDATE()
            WHERE BatchReferenceID = @payBatch AND SupplierID = @supplier AND InvoiceNo = @code AND PostingMode = 'LOAN';
            IF @@ROWCOUNT <> 1 THROW 62031, 'The loan''s payable is not found; nothing was posted.', 1;
            UPDATE dbo.ExpenseMaster
            SET Amount = ISNULL(Amount, 0) + @change, Balance = @invNew,
                Status = CASE WHEN ISNULL(AmountPaid, 0) > 0 THEN 'PARTIAL' ELSE 'UNPAID' END
            WHERE BatchReferenceID = @payBatch AND SupplierID = @supplier AND InvoiceNo = @code;
            IF @@ROWCOUNT <> 1 THROW 62031, 'The loan''s payable must have exactly one line (ExpenseMaster); nothing was posted.', 1;
            DECLARE @ledSeq DECIMAL(7) = dbo.func_getLastID(@supplier);
            INSERT INTO dbo.SupplierLedger
                (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate, Description, TransCode, TransactionDate, ReferenceNumber,
                 ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, TransactedBy, ApprovedBy, TotalAmount,
                 PaymentType, ErrorCorrectTag, TicketReference, BatchReferenceID)
            SELECT @ledSeq, s.SupplierKey, @supplier, @RevalDate, LEFT(@Description, 490), 'LOAN-REVAL', @RevalDate, @refno,
                   CAST(@payBatch AS VARCHAR(40)) + '-' + @branch, @code, 0,
                   CASE WHEN @change < 0 THEN -@change ELSE 0 END, CASE WHEN @change > 0 THEN @change ELSE 0 END, 0,
                   LEFT(@User, 50), '*', ABS(@change), 'REVALUATION', 0, @tn, @payBatch
            FROM dbo.Supplier AS s WHERE s.SupplierID = @supplier;
            IF @@ROWCOUNT <> 1 THROW 62031, 'The loan''s supplier is not found; nothing was posted.', 1;
        END

        IF (SELECT SUM(Debit) - SUM(Credit) FROM dbo.TicketDetails WHERE TicketNumber = @tn AND ReferenceNumber = @refno AND BranchCode = @branch) <> 0
            THROW 62019, 'Post-check: the revaluation ticket does not balance; nothing was posted.', 1;
        -- [105] post-check: payable = GL (all dates, loan branch) = its supplier-ledger rows
        IF @payBatch IS NOT NULL
           AND (   ISNULL((SELECT CAST(Balance AS DECIMAL(18,2)) FROM dbo.ExpenseSummary WHERE BatchReferenceID = @payBatch AND SupplierID = @supplier AND InvoiceNo = @code), -1)
                   <> ISNULL((SELECT SUM(ISNULL(d.Credit, 0) - ISNULL(d.Debit, 0)) FROM dbo.TicketDetails AS d WHERE d.AccountCode = @liab AND d.BranchCode = @branch), 0)
                OR ISNULL((SELECT CAST(Balance AS DECIMAL(18,2)) FROM dbo.ExpenseSummary WHERE BatchReferenceID = @payBatch AND SupplierID = @supplier AND InvoiceNo = @code), -1)
                   <> ISNULL((SELECT SUM(ISNULL(l.Credit, 0) - ISNULL(l.Debit, 0)) FROM dbo.SupplierLedger AS l WHERE l.SupplierKey = @supplier AND l.InvoiceNo = @code AND l.BatchReferenceID = @payBatch), 0))
            THROW 62032, 'Post-check: the loan''s payable does not equal the GL and its supplier ledger; nothing was posted.', 1;

        COMMIT TRAN;

        SELECT @txn AS TxnID, @tn AS TicketNumber, @refno AS ReferenceNumber, @change AS PhpChange, @newBal AS NewPhpBalance,
               CASE WHEN @change > 0 THEN N'Forex loss ' ELSE N'Forex gain ' END + FORMAT(ABS(@change), 'N2', 'en-US') + N' posted (ticket ' + @tn
               + N', ref ' + @refno + N'). New balance ' + FORMAT(@newBal, 'N2', 'en-US') + N'.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

------------------------------------------------------------------
-- 4. spu_Loan_ReverseRevaluation (the payable goes back with it)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.spu_Loan_ReverseRevaluation', 'spu_Loan_ReverseRevaluation_OLD_10172026210000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE dbo.spu_Loan_ReverseRevaluation
    @TxnID   INT,
    @User    VARCHAR(60),
    @Reason  VARCHAR(300)
AS
/*  Reverses a loan's LATEST revaluation (a later one depends on it): a mirror ticket of its GL lines, dated like the
    original (the reversal rule of 2026-10-09; a closed month is refused by the lock trigger, 59900), and the transaction
    is marked REVERSED, so the loan's balance and rate go back to the entry before it. Errors 62011-62015. */
/*  [105] 2026-10-17: the loan's payable (Vouchering Telegraphic) goes back too: Actual Cost = Balance less the change,
    and a supplier-ledger row the other way, dated like the revaluation. It must agree with the GL first (62030);
    post-check 62032. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF ISNULL(LTRIM(@Reason), '') = '' THROW 62012, 'A reason is required to reverse a revaluation.', 1;
    IF ISNULL(LTRIM(@User), '') = '' THROW 62009, 'The user is required.', 1;

    DECLARE @loan INT = (SELECT LoanID FROM dbo.LoanTransaction WHERE TxnID = @TxnID);
    IF @loan IS NULL THROW 62011, 'The loan entry is not found.', 1;

    BEGIN TRY
        BEGIN TRAN;
        DECLARE @lock INT, @res NVARCHAR(100) = N'LOAN:' + CAST(@loan AS NVARCHAR(20));
        EXEC @lock = sp_getapplock @Resource = @res, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
        IF @lock < 0 THROW 62008, 'This loan is being updated by someone else right now. Please try again.', 1;

        DECLARE @type VARCHAR(15), @status VARCHAR(10), @date DATE, @tn VARCHAR(20), @refno VARCHAR(20), @desc VARCHAR(300), @branch VARCHAR(5), @code VARCHAR(30), @supplier VARCHAR(50);
        SELECT @type = t.TxnType, @status = t.Status, @date = t.TxnDate, @tn = t.TicketNumber, @refno = t.ReferenceNumber, @desc = t.Description,
               @branch = a.BranchCode, @code = a.LoanCode, @supplier = a.SupplierID
        FROM dbo.LoanTransaction AS t WITH (UPDLOCK) INNER JOIN dbo.LoanAccount AS a ON a.LoanID = t.LoanID
        WHERE t.TxnID = @TxnID;
        IF @type <> 'REVALUATION' THROW 62013, 'Only a revaluation can be reversed (not the opening).', 1;
        IF @status <> 'POSTED' THROW 62014, 'This revaluation is already reversed.', 1;
        IF EXISTS (SELECT 1 FROM dbo.LoanTransaction WHERE LoanID = @loan AND Status = 'POSTED' AND TxnID <> @TxnID
                   AND (TxnDate > @date OR (TxnDate = @date AND TxnID > @TxnID)))
            THROW 62015, 'A later revaluation of this loan depends on this one: reverse the later one first.', 1;

        -- [105] the loan's payable must agree with the GL before it is moved back
        DECLARE @payBatch BIGINT, @liab VARCHAR(20), @chg DECIMAL(18,2), @invBal DECIMAL(18,2), @glAll DECIMAL(18,2), @msg NVARCHAR(400);
        SELECT @payBatch = PayableBatchReferenceID, @liab = LiabilityAccount FROM dbo.LoanAccount WHERE LoanID = @loan;
        SELECT @chg = PhpChange FROM dbo.LoanTransaction WHERE TxnID = @TxnID;
        IF @payBatch IS NOT NULL
        BEGIN
            SELECT @invBal = CAST(Balance AS DECIMAL(18,2)) FROM dbo.ExpenseSummary WITH (UPDLOCK, ROWLOCK)
            WHERE BatchReferenceID = @payBatch AND SupplierID = @supplier AND InvoiceNo = @code AND PostingMode = 'LOAN';
            SET @glAll = ISNULL((SELECT SUM(ISNULL(d.Credit, 0) - ISNULL(d.Debit, 0)) FROM dbo.TicketDetails AS d
                                 WHERE d.AccountCode = @liab AND d.BranchCode = @branch), 0);
            IF @invBal IS NULL OR @invBal <> @glAll
            BEGIN
                SET @msg = N'The loan''s payable ' + @code + N' (Vouchering Telegraphic) shows ' + ISNULL(CONVERT(NVARCHAR(30), @invBal), N'nothing')
                         + N' but GL ' + @liab + N' on branch ' + @branch + N' is ' + CONVERT(NVARCHAR(30), @glAll)
                         + N'. A payment was booked outside Vouchering Telegraphic, or the payable was changed by hand; sort it out first.';
                THROW 62030, @msg, 1;
            END
        END

        DECLARE @rtn VARCHAR(10);
        EXEC dbo.GetTicketNumber @rtn OUTPUT;
        INSERT INTO dbo.TicketMaster
            (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber, ReferenceNumber, ReferenceKey, Owner, Particulars,
             EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
        VALUES
            (@date, 0, @branch, 'JV', @rtn, @refno, @code, @supplier, LEFT('(REVERSAL) ' + ISNULL(@desc, '') + ' | ' + @Reason, 7000),
             @User, '*', '*', 'POSTED', 'LOAN-REVAL', NULL);
        INSERT INTO dbo.TicketDetails
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey, TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        SELECT @date, 0, @branch, @code, @rtn, @refno, d.AccountCode, d.Credit, d.Debit, ''
        FROM dbo.TicketDetails AS d
        WHERE d.TicketNumber = @tn AND d.ReferenceNumber = @refno AND d.BranchCode = @branch;
        IF @@ROWCOUNT = 0 THROW 62011, 'The revaluation''s ticket lines are not found; nothing was reversed.', 1;

        UPDATE dbo.LoanTransaction
        SET Status = 'REVERSED', ReversedBy = LEFT(@User, 60), ReversedAt = SYSDATETIME(), ReverseReason = LEFT(@Reason, 300), ReversalTicketNumber = @rtn
        WHERE TxnID = @TxnID;

        -- [105] the payable goes back by the revaluation's change; supplier-ledger row the other way, dated like it
        IF @payBatch IS NOT NULL
        BEGIN
            DECLARE @invNew DECIMAL(18,2) = @invBal - @chg;
            IF @invNew < 0 THROW 62033, 'Reversing this revaluation would take the loan''s payable below 0 (it was paid down since); nothing was reversed.', 1;
            UPDATE dbo.ExpenseSummary
            SET Amount = ISNULL(Amount, 0) - @chg, Balance = @invNew,
                Status = CASE WHEN ISNULL(AmountPaid, 0) > 0 THEN 'PARTIAL' ELSE 'POSTED' END,
                UpdatedBy = LEFT(@User, 30), DateTimeUpdated = GETDATE()
            WHERE BatchReferenceID = @payBatch AND SupplierID = @supplier AND InvoiceNo = @code AND PostingMode = 'LOAN';
            IF @@ROWCOUNT <> 1 THROW 62031, 'The loan''s payable is not found; nothing was reversed.', 1;
            UPDATE dbo.ExpenseMaster
            SET Amount = ISNULL(Amount, 0) - @chg, Balance = @invNew,
                Status = CASE WHEN ISNULL(AmountPaid, 0) > 0 THEN 'PARTIAL' ELSE 'UNPAID' END
            WHERE BatchReferenceID = @payBatch AND SupplierID = @supplier AND InvoiceNo = @code;
            IF @@ROWCOUNT <> 1 THROW 62031, 'The loan''s payable must have exactly one line (ExpenseMaster); nothing was reversed.', 1;
            DECLARE @ledSeq DECIMAL(7) = dbo.func_getLastID(@supplier);
            INSERT INTO dbo.SupplierLedger
                (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate, Description, TransCode, TransactionDate, ReferenceNumber,
                 ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, TransactedBy, ApprovedBy, TotalAmount,
                 PaymentType, ErrorCorrectTag, TicketReference, BatchReferenceID)
            SELECT @ledSeq, s.SupplierKey, @supplier, @date, LEFT('(REVERSAL) ' + ISNULL(@desc, '') + ' | ' + @Reason, 490), 'LOAN-REVAL', @date, @refno,
                   CAST(@payBatch AS VARCHAR(40)) + '-' + @branch, @code, 0,
                   CASE WHEN @chg > 0 THEN @chg ELSE 0 END, CASE WHEN @chg < 0 THEN -@chg ELSE 0 END, 0,
                   LEFT(@User, 50), '*', ABS(@chg), 'REVERSAL', 0, @rtn, @payBatch
            FROM dbo.Supplier AS s WHERE s.SupplierID = @supplier;
            IF @@ROWCOUNT <> 1 THROW 62031, 'The loan''s supplier is not found; nothing was reversed.', 1;
        END

        IF (SELECT SUM(Debit) - SUM(Credit) FROM dbo.TicketDetails WHERE ReferenceNumber = @refno AND BranchCode = @branch AND TicketNumber IN (@tn, @rtn)) <> 0
            THROW 62019, 'Post-check: the revaluation and its reversal do not net to zero; nothing was reversed.', 1;
        -- [105] post-check: payable = GL (all dates, loan branch) = its supplier-ledger rows
        IF @payBatch IS NOT NULL
           AND (   ISNULL((SELECT CAST(Balance AS DECIMAL(18,2)) FROM dbo.ExpenseSummary WHERE BatchReferenceID = @payBatch AND SupplierID = @supplier AND InvoiceNo = @code), -1)
                   <> ISNULL((SELECT SUM(ISNULL(d.Credit, 0) - ISNULL(d.Debit, 0)) FROM dbo.TicketDetails AS d WHERE d.AccountCode = @liab AND d.BranchCode = @branch), 0)
                OR ISNULL((SELECT CAST(Balance AS DECIMAL(18,2)) FROM dbo.ExpenseSummary WHERE BatchReferenceID = @payBatch AND SupplierID = @supplier AND InvoiceNo = @code), -1)
                   <> ISNULL((SELECT SUM(ISNULL(l.Credit, 0) - ISNULL(l.Debit, 0)) FROM dbo.SupplierLedger AS l WHERE l.SupplierKey = @supplier AND l.InvoiceNo = @code AND l.BatchReferenceID = @payBatch), 0))
            THROW 62032, 'Post-check: the loan''s payable does not equal the GL and its supplier ledger; nothing was reversed.', 1;

        COMMIT TRAN;
        SELECT @TxnID AS TxnID, @rtn AS ReversalTicketNumber,
               N'Revaluation reversed (ticket ' + @rtn + N', dated ' + CONVERT(NVARCHAR(10), @date, 120) + N').' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

------------------------------------------------------------------
-- 5. sp_Loan_GetAccounts (+ the payable's figures)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.sp_Loan_GetAccounts', 'sp_Loan_GetAccounts_OLD_10172026210000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE dbo.sp_Loan_GetAccounts
AS
/*  Read-only. Every active loan with its current position (last POSTED transaction), the GL balance of its liability
    account on its branch (credit - debit, all dates) and the mapped forex accounts. Caller: LoanRevaluationFrm. */
BEGIN
    SET NOCOUNT ON;
    DECLARE @loss VARCHAR(50) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'LOAN-REVAL' AND AmountType = 'FXLOSS' AND IsActive = 1 ORDER BY Seq),
            @gain VARCHAR(50) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'LOAN-REVAL' AND AmountType = 'FXGAIN' AND IsActive = 1 ORDER BY Seq);
    SELECT a.LoanID, a.LoanCode, a.SupplierID, s.SupplierName, a.Description, a.Currency, a.BranchCode, b.BranchName,
           a.LiabilityAccount, la.Description AS LiabilityAccountName,
           a.LoanCode + ' - ' + ISNULL(s.SupplierName, a.SupplierID) + ' (' + a.Currency + ')' AS DisplayText,
           t.TxnDate AS LastTxnDate, t.TxnType AS LastTxnType, t.Rate AS LastRate,
           t.ForeignBalance, t.PhpBalance,
           CAST(ISNULL(gl.Bal, 0) AS DECIMAL(18,2)) AS GLBalance,
           @loss AS LossAccount, (SELECT Description FROM dbo.ChartOfAccounts WHERE AccountCode = @loss) AS LossAccountName,
           @gain AS GainAccount, (SELECT Description FROM dbo.ChartOfAccounts WHERE AccountCode = @gain) AS GainAccountName,
           -- [105] the loan's payable in Vouchering Telegraphic (NULL = none)
           pay.InvoiceNo AS PayableInvoiceNo, CAST(pay.Amount AS DECIMAL(18,2)) AS PayableAmount,
           CAST(pay.Balance AS DECIMAL(18,2)) AS PayableBalance, CAST(ISNULL(pay.AmountPaid, 0) AS DECIMAL(18,2)) AS PayableAmountPaid
    FROM dbo.LoanAccount AS a
    LEFT JOIN dbo.Supplier AS s ON s.SupplierID = a.SupplierID
    LEFT JOIN dbo.Branches AS b ON b.BranchCode = a.BranchCode
    LEFT JOIN dbo.ChartOfAccounts AS la ON la.AccountCode = a.LiabilityAccount
    OUTER APPLY (SELECT TOP 1 x.TxnDate, x.TxnType, x.Rate, x.ForeignBalance, x.PhpBalance FROM dbo.LoanTransaction AS x
                 WHERE x.LoanID = a.LoanID AND x.Status = 'POSTED' ORDER BY x.TxnDate DESC, x.TxnID DESC) AS t
    OUTER APPLY (SELECT SUM(ISNULL(d.Credit, 0) - ISNULL(d.Debit, 0)) AS Bal FROM dbo.TicketDetails AS d
                 WHERE d.AccountCode = a.LiabilityAccount AND d.BranchCode = a.BranchCode) AS gl
    OUTER APPLY (SELECT TOP 1 es.InvoiceNo, es.Amount, es.Balance, es.AmountPaid FROM dbo.ExpenseSummary AS es
                 WHERE es.BatchReferenceID = a.PayableBatchReferenceID AND es.SupplierID = a.SupplierID AND es.PostingMode = 'LOAN') AS pay   -- [105]
    WHERE a.IsActive = 1
    ORDER BY a.LoanCode;
END
GO

------------------------------------------------------------------
-- 6. sp_PostVoucherManual (a loan payable is paid from the loan's branch, 58040)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.sp_PostVoucherManual', 'sp_PostVoucherManual_OLD_10172026210000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE [dbo].[sp_PostVoucherManual]
(
    @parmrefno         VARCHAR(10),
    @parmvoucherid     VARCHAR(10),
    @parmsupplierid    VARCHAR(50),
    @parmsuppliername  VARCHAR(150),
    @parmpaymethod     VARCHAR(20),    -- 'PURCHASE' or 'EXPENSE'
    @parmvouchertype   VARCHAR(50),    -- 'CHECK', 'CASH', or 'TELEGRAPHIC'
    @parmcheckno       VARCHAR(50) = NULL,
    @parmcreditglcode  VARCHAR(20) = NULL,
    @parmcontrolno     VARCHAR(50) = NULL,
    @parmvoucherdate   DATE,
    @parmremarks       VARCHAR(2000),
    @parmpreparedby    VARCHAR(50),
    @parmbranch        VARCHAR(5),
    @InvoiceLines      dbo.VoucherManualInvoiceTVP_v3 READONLY,
    @GLLines           dbo.VoucherManualGLLineTVP READONLY
)
AS
/*
    Posts a manual voucher. Checked invoices auto-post two leg pairs
    each (Amount-To-Apply against AP-Trade/Credit-GLCode, Variance
    against AP-Trade/60323) - see SQL/2026-09-15_VoucheringManual_
    AutoAPTradeLegs.sql header comment for the exact shape and the
    account-resolution rules. The manual @GLLines grid is independent
    of invoices:
      - No invoices: free-form, does NOT need to self-balance - its
        residual (Debit total - Credit total) auto-posts against
        @parmcreditglcode (e.g. a lone "Advances to Supplier" Debit
        line with no invoice attached).
      - Invoices being paid: must self-balance on its own (Amount-To-
        Apply/Variance already auto-post their own AP-Trade legs
        against Credit GLCode).
    Partial payment (2026-09-21): an invoice row with Variance = 0 and
    AmountPaid < Balance is a deliberate partial - Balance drops by
    AmountPaid, status PARTIAL, no FX leg. Each row's fresh Balance
    must equal the client's ExpectedBalance (58024) and the settled
    Gross (AmountPaid - Variance) may not exceed it (58030).
    Callers: VoucheringManualFrm.cs BtnPost_Click.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ── Validation ──────────────────────────────────────────────
    -- NEW: the AP-Trade mapping resolution below partitions on exact
    -- string equality ('PURCHASE'/'EXPENSE'), while the per-invoice
    -- loop further down partitions on "= 'PURCHASE', else EXPENSE"
    -- (fail-open). Reject anything else up front so those two can
    -- never diverge - e.g. a future/alternate caller passing a typo'd
    -- or differently-cased value wouldn't silently resolve neither
    -- mapping variable and then have the loop fail-open into EXPENSE
    -- with a NULL @invPayableAcct.
    IF (SELECT COUNT(*) FROM @InvoiceLines) > 0 AND @parmpaymethod NOT IN ('PURCHASE', 'EXPENSE')
    BEGIN
        THROW 58029, 'Invalid @parmpaymethod - must be ''PURCHASE'' or ''EXPENSE'' when paying invoices.', 1;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM @InvoiceLines WHERE ISNULL(AmountPaid,0) <= 0)
    BEGIN
        THROW 58002, 'Every checked invoice must have an Amount Paid greater than zero.', 1;
        RETURN;
    END

    -- NEW 2026-09-21: ExpectedBalance is what makes a partial payment
    -- safe (stale-grid check per invoice, see the per-invoice loop) -
    -- a caller that doesn't supply it can't be trusted to have seen
    -- the current Balance.
    IF EXISTS (SELECT 1 FROM @InvoiceLines WHERE ExpectedBalance IS NULL)
    BEGIN
        THROW 58032, 'Every checked invoice must supply the Balance it was loaded with (ExpectedBalance).', 1;
        RETURN;
    END

    -- Pure TVP arithmetic, so it belongs here (before any write / before
    -- GetTicketNumber is consumed) rather than inside the transaction:
    -- what actually comes off the invoice's Balance is AmountPaid minus
    -- Variance, and that must be positive.
    IF EXISTS (SELECT 1 FROM @InvoiceLines WHERE ISNULL(AmountPaid,0) - ISNULL(Variance,0) <= 0)
    BEGIN
        THROW 58031, 'Every checked invoice must have Amount Paid minus Variance greater than zero.', 1;
        RETURN;
    END

    -- The same invoice twice in one call would let a crafted second row
    -- (ExpectedBalance = the already-reduced Balance) settle it twice.
    -- The key mirrors how each payment method actually locates the
    -- invoice below: PURCHASE = InvoiceNo + SequenceNo, EXPENSE =
    -- InvoiceNo + BatchReferenceID (SequenceReferenceNumber is ignored).
    IF EXISTS (
        SELECT 1 FROM @InvoiceLines
        GROUP BY InvoiceNo,
                 CASE WHEN @parmpaymethod = 'PURCHASE' THEN ISNULL(SequenceReferenceNumber,'')
                      ELSE CAST(ISNULL(BatchReferenceID,0) AS VARCHAR(30)) END
        HAVING COUNT(*) > 1
    )
    BEGIN
        THROW 58034, 'The same invoice appears more than once in this voucher.', 1;
        RETURN;
    END

    -- Variance only makes sense for Telegraphic (USD-invoiced
    -- suppliers converted at today's rate) - a Check/Cash voucher is
    -- always same-currency, so a nonzero Variance there would post a
    -- spurious FX gain/loss and misstate what the physical instrument
    -- actually settled.
    IF @parmvouchertype IN ('CHECK','CASH') AND EXISTS (SELECT 1 FROM @InvoiceLines WHERE ISNULL(Variance,0) <> 0)
    BEGIN
        THROW 58022, 'A Variance (FX difference) is only supported for Telegraphic Transfer vouchers - for Check/Cash, Variance must be 0 (Amount Paid may be below Balance as a partial payment, never above).', 1;
        RETURN;
    END

    -- NEW: nothing to post if both sides are empty. Invoices alone are
    -- fine now (their own auto legs fully balance the ticket); manual
    -- GL lines alone are fine too (pure GL-to-GL transfer, e.g. a cash
    -- advance with no invoice attached).
    IF (SELECT COUNT(*) FROM @InvoiceLines) = 0 AND (SELECT COUNT(*) FROM @GLLines) = 0
    BEGIN
        THROW 58003, 'Nothing to post - check at least one invoice or add at least one manual GL line.', 1;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM @GLLines WHERE (Debit > 0 AND Credit > 0) OR (Debit = 0 AND Credit = 0))
    BEGIN
        THROW 58004, 'Each GL line must have an amount in either Debit or Credit, not both or neither.', 1;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM @GLLines WHERE LTRIM(RTRIM(ISNULL(AccountCode,''))) = '')
    BEGIN
        THROW 58005, 'Every GL line requires an Account Code.', 1;
        RETURN;
    END

    -- CHANGED 2026-09-16: a pure manual voucher (no invoices - e.g. an
    -- advance to a supplier with no invoice attached, same shape
    -- SupplierPaymentDevEx.cs already supports) only needs ONE side
    -- typed - Debit "Advances to Supplier", nothing else - relying on
    -- the header's Credit GLCode to auto-absorb the other side, same
    -- as the original ResidualCash mechanic. Only require the grid to
    -- self-balance when invoices ARE being paid - Amount-To-Apply/
    -- Variance already auto-post their own AP-Trade legs against
    -- Credit GLCode there, so a second unbalanced residual would
    -- double up against the same account.
    DECLARE @GLTotalDebit DECIMAL(18,2), @GLTotalCredit DECIMAL(18,2), @GLResidual DECIMAL(18,2);
    SELECT @GLTotalDebit = ISNULL(SUM(Debit),0), @GLTotalCredit = ISNULL(SUM(Credit),0) FROM @GLLines;
    SET @GLResidual = ROUND(@GLTotalDebit - @GLTotalCredit, 2);

    IF (SELECT COUNT(*) FROM @InvoiceLines) > 0 AND (SELECT COUNT(*) FROM @GLLines) > 0 AND @GLResidual <> 0
    BEGIN
        DECLARE @GLBalMsg VARCHAR(500) = 'The manual GL entry is out of balance: Debit ' + CAST(@GLTotalDebit AS VARCHAR(30))
            + ' vs Credit ' + CAST(@GLTotalCredit AS VARCHAR(30))
            + '. When paying invoices it must balance on its own - Amount to Apply/Variance already auto-post their own AP-Trade legs.';
        THROW 58025, @GLBalMsg, 1;
        RETURN;
    END

    IF @parmvouchertype = 'CHECK' AND LTRIM(RTRIM(ISNULL(@parmcheckno,''))) = ''
    BEGIN
        THROW 58009, 'Check No. is required for a Check voucher.', 1;
        RETURN;
    END

    IF @parmvouchertype IN ('CASH','TELEGRAPHIC') AND LTRIM(RTRIM(ISNULL(@parmcontrolno,''))) = ''
    BEGIN
        THROW 58010, 'Control No. is required for Cash/Telegraphic vouchers.', 1;
        RETURN;
    END

    -- CHANGED 2026-09-16: also required whenever the manual grid
    -- doesn't self-balance (@GLResidual <> 0) - that residual now
    -- auto-posts against Credit GLCode, same as invoices' Amount-To-
    -- Apply leg.
    IF ((SELECT COUNT(*) FROM @InvoiceLines) > 0 OR @GLResidual <> 0) AND LTRIM(RTRIM(ISNULL(@parmcreditglcode,''))) = ''
    BEGIN
        THROW 58014, 'Credit GLCode is required when paying invoices or when the manual GL entry does not balance on its own.', 1;
        RETURN;
    END

    DECLARE @supplierkey VARCHAR(30);
    SELECT @supplierkey = SupplierKey FROM Supplier WHERE SupplierID = @parmsupplierid;

    IF @supplierkey IS NULL
    BEGIN
        THROW 58011, 'Supplier not found.', 1;
        RETURN;
    END

    -- Duplicate-post guard - a retry or a double-click must not
    -- silently double-pay the supplier.
    IF EXISTS (SELECT 1 FROM TicketMaster WHERE ReferenceNumber = @parmrefno AND Mnemonic = 'VOUCHER-MANUAL')
    BEGIN
        THROW 58020, 'A voucher has already been posted under this reference number.', 1;
        RETURN;
    END

    -- NEW: resolve the FX variance account(s) up front, before any
    -- write, so a missing mapping fails fast instead of mid-post. Now
    -- resolved by whether ANY checked invoice has a loss/gain - a
    -- single voucher can contain both (invoice A overpaid, invoice B
    -- underpaid), unlike the prior net-only design.
    DECLARE @FXLossAccountCode VARCHAR(20), @FXGainAccountCode VARCHAR(20);

    IF EXISTS (SELECT 1 FROM @InvoiceLines WHERE ISNULL(Variance,0) > 0)
    BEGIN
        SELECT @FXLossAccountCode = AccountCode FROM dbo.JournalEntryMapping
        WHERE Mnemonic = 'VOUCHER-MANUAL-FXVAR' AND ConditionFlag = 'HasFXLoss' AND IsActive = 1;

        IF @FXLossAccountCode IS NULL
        BEGIN
            THROW 58017, 'No active JournalEntryMapping found for VOUCHER-MANUAL-FXVAR / HasFXLoss (Realized Loss on Forex). Verify seed data.', 1;
            RETURN;
        END
    END

    IF EXISTS (SELECT 1 FROM @InvoiceLines WHERE ISNULL(Variance,0) < 0)
    BEGIN
        SELECT @FXGainAccountCode = AccountCode FROM dbo.JournalEntryMapping
        WHERE Mnemonic = 'VOUCHER-MANUAL-FXVAR' AND ConditionFlag = 'HasFXGain' AND IsActive = 1;

        IF @FXGainAccountCode IS NULL
        BEGIN
            THROW 58018, 'No active JournalEntryMapping found for VOUCHER-MANUAL-FXVAR / HasFXGain (Realized Gain on Forex). Verify seed data.', 1;
            RETURN;
        END
    END

    -- NEW: resolve the default AP-Trade account per payment method from
    -- JournalEntryMapping instead of hardcoding it in the proc body -
    -- config-driven the same way the FX accounts already are. For
    -- EXPENSE, ExpenseSummary.PayableAccountCode (a real per-invoice
    -- field the rest of the system already populates) still wins when
    -- set; this mapping is only the fallback for a NULL/blank value.
    DECLARE @APTradeAccountPurchase VARCHAR(20), @APTradeAccountExpenseFallback VARCHAR(20);

    IF (SELECT COUNT(*) FROM @InvoiceLines) > 0 AND @parmpaymethod = 'PURCHASE'
    BEGIN
        SELECT @APTradeAccountPurchase = AccountCode FROM dbo.JournalEntryMapping
        WHERE Mnemonic = 'VOUCHER-MANUAL-APTRADE' AND ConditionFlag = 'PURCHASE' AND IsActive = 1;

        IF @APTradeAccountPurchase IS NULL
        BEGIN
            THROW 58027, 'No active JournalEntryMapping found for VOUCHER-MANUAL-APTRADE / PURCHASE. Verify seed data.', 1;
            RETURN;
        END
    END
    ELSE IF (SELECT COUNT(*) FROM @InvoiceLines) > 0 AND @parmpaymethod = 'EXPENSE'
    BEGIN
        SELECT @APTradeAccountExpenseFallback = AccountCode FROM dbo.JournalEntryMapping
        WHERE Mnemonic = 'VOUCHER-MANUAL-APTRADE' AND ConditionFlag = 'EXPENSE' AND IsActive = 1;

        IF @APTradeAccountExpenseFallback IS NULL
        BEGIN
            THROW 58028, 'No active JournalEntryMapping found for VOUCHER-MANUAL-APTRADE / EXPENSE. Verify seed data.', 1;
            RETURN;
        END
    END

    -- NEW: total voucher Amount = the invoice-driven cash, plus
    -- whatever the manual grid separately nets on the SAME
    -- @parmcreditglcode account (e.g. an advance also drawn from the
    -- same bank account) - reproduces the combined physical-instrument
    -- total (e.g. 900 invoice + 2000 advance = 2900), while the manual
    -- grid's OWN balance (Debit=Credit) is validated independently
    -- above and never folded into this figure beyond that net.
    DECLARE @TotalInvoiceCash DECIMAL(18,2) = ISNULL((SELECT SUM(AmountPaid) FROM @InvoiceLines), 0);
    DECLARE @ManualCreditGLCodeNet DECIMAL(18,2) = ISNULL((
        SELECT SUM(Credit) - SUM(Debit) FROM @GLLines
        WHERE LTRIM(RTRIM(ISNULL(AccountCode,''))) = LTRIM(RTRIM(ISNULL(@parmcreditglcode,'')))
    ), 0);

    -- FIX (2026-09-16): a pure manual-GL voucher (no invoices) auto-
    -- posts its residual (@GLResidual, Debit-heavy OR Credit-heavy -
    -- the C# grid supports and previews both directions) against
    -- @parmcreditglcode. The header Amount must be the TRUE net
    -- movement through @parmcreditglcode - that's
    -- @ManualCreditGLCodeNet (whatever the user typed directly against
    -- that account in the grid) PLUS @GLResidual (what the auto-leg
    -- adds to it), not @GLTotalDebit and not @GLResidual alone.
    -- @GLResidual alone breaks when the user types a fully
    -- self-balanced pair directly ON @parmcreditglcode itself (e.g.
    -- Debit Advances 5000 / Credit Cash-in-Bank 5000, no invoices) -
    -- @GLResidual=0 there (grid already balances, no auto-leg needed),
    -- but the real voucher amount is still 5000, not 0. @GLTotalDebit
    -- breaks whenever the grid has more than one line pair (e.g. Debit
    -- 2000 + a self-balanced Credit 500 elsewhere, residual 1500 -
    -- @GLTotalDebit wrongly records 2000) and wrongly throws 58026
    -- "zero Amount" for a genuine Credit-heavy-only grid (@GLTotalDebit
    -- = 0 despite a real nonzero residual).
    DECLARE @TotalVoucherAmount DECIMAL(18,2) =
        CASE WHEN (SELECT COUNT(*) FROM @InvoiceLines) > 0
             THEN @TotalInvoiceCash + @ManualCreditGLCodeNet
             ELSE ABS(@ManualCreditGLCodeNet + @GLResidual)
        END;

    IF @TotalVoucherAmount <= 0
    BEGIN
        THROW 58026, 'This voucher would post a zero or negative Amount - check your entries (a manual debit against the Credit GLCode account may be offsetting the invoice cash).', 1;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRAN;

        -- ── Voucher header ──
        IF @parmvouchertype = 'TELEGRAPHIC'
            INSERT INTO [dbo].[TelegraphicVoucher]
                (VoucherID, SupplierID, ReferenceNumber, PaidTo, Particulars, Amount,
                 PreparedBy, VerifiedBy, NotedBy, PaymentApprovedBy, PaymentReceivedBy,
                 OfficialReceiptNo, VoucherType, DateReceived, DateAdded, DateUpdate,
                 isErrorCorrect, isLiquidation, ControlNo)
            VALUES
                (@parmvoucherid, @parmsupplierid, @parmrefno, @parmsuppliername,
                 @parmremarks, @TotalVoucherAmount, @parmpreparedby, '', @parmcontrolno, '', '',
                 @parmcreditglcode, 'TELEGRAPHIC', @parmvoucherdate, GETDATE(), GETDATE(), 0, 0, @parmcontrolno);
        ELSE
            INSERT INTO [dbo].[CashVoucher]
                (VoucherID, SupplierID, ReferenceNumber, PaidTo, Particulars, Amount,
                 PreparedBy, VerifiedBy, NotedBy, PaymentApprovedBy, PaymentReceivedBy,
                 OfficialReceiptNo, VoucherType, DateReceived, DateAdded, DateUpdate,
                 isErrorCorrect, isLiquidation)
            VALUES
                (@parmvoucherid, @parmsupplierid, @parmrefno, @parmsuppliername,
                 @parmremarks, @TotalVoucherAmount, @parmpreparedby, '', @parmcontrolno, '', '',
                 @parmcreditglcode, 'CASH', @parmvoucherdate, GETDATE(), GETDATE(), 0, 0);

        -- FIX: TransactionPaymentAP specifically tracks AP-invoice cash,
        -- not the voucher's combined total - an unrelated manual GL
        -- entry (e.g. a cash advance sharing the same Credit GLCode)
        -- must not inflate what looks like AP payment activity for
        -- this supplier in any report keyed off this table.
        DECLARE @SeqNo INT;
        SELECT @SeqNo = ISNULL(MAX(SEQ_NO),0) + 1 FROM TransactionPaymentAP WHERE SupplierKey = @supplierkey;
        INSERT INTO [dbo].[TransactionPaymentAP]
            (SEQ_NO, SupplierKey, ReferenceNumber, Amount, VoucherType,
             DatePaid, ExecuteBy, DateUpdate, UpdateBy, ErrorCorrect)
        VALUES (@SeqNo, @supplierkey, @parmrefno, @TotalInvoiceCash, @parmvouchertype,
                GETDATE(), @parmpreparedby, GETDATE(), @parmpreparedby, 0);

        -- ── One ticket, the whole compound entry ──
        DECLARE @ticketnum VARCHAR(20);
        EXEC GetTicketNumber @ticketnum OUTPUT;

        DECLARE @PhysicalRef VARCHAR(50) = CASE WHEN @parmvouchertype = 'CHECK' THEN @parmcheckno ELSE @parmcontrolno END;

        INSERT INTO [dbo].[TicketMaster]
            (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber,
             ReferenceNumber, ReferenceKey, Owner, Particulars,
             EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
        VALUES
            (@parmvoucherdate, 0, @parmbranch, 'PV', @ticketnum,
             @parmrefno, @parmvoucherid, @parmsuppliername, ISNULL(@parmremarks,''),
             @parmpreparedby, '*', '*', 'POSTED', 'VOUCHER-MANUAL', NULL);

        -- NEW: compound-entry staging. Every leg (the user's own
        -- free-form GL lines AND every auto-generated Amount-To-Apply/
        -- Variance leg below, plus the pure-manual-voucher residual
        -- leg below) is staged here first, then netted per AccountCode
        -- into exactly one TicketDetails row per account at the end -
        -- so a voucher paying an invoice with a Variance plus an
        -- unrelated manual advance posts a clean compound entry (e.g.
        -- one AP-Trade line, one Cash-in-Bank line) instead of a
        -- separate row per source. Per-invoice detail is NOT lost - it
        -- still lives in full in APPaymentDetails.Variance and
        -- SupplierLedger; only the GL/TicketDetails view is compounded.
        IF OBJECT_ID('tempdb..#Legs') IS NOT NULL DROP TABLE #Legs;
        CREATE TABLE #Legs (AccountCode VARCHAR(20), Debit DECIMAL(18,2), Credit DECIMAL(18,2));

        -- The user's own free-form GL lines (e.g. a cash advance) -
        -- already validated to self-balance when invoices are being
        -- paid; may be one-sided otherwise (residual handled below).
        -- ISNULL-guarded so a NULL Debit/Credit can't make SUM(...)
        -- resolve to NULL for that account's group below, which would
        -- silently exclude the row (NULL <> 0 is UNKNOWN) instead of
        -- loudly failing the way a NULL landing straight in
        -- TicketDetails used to.
        INSERT INTO #Legs (AccountCode, Debit, Credit)
        SELECT AccountCode, ISNULL(Debit,0), ISNULL(Credit,0)
        FROM @GLLines;

        -- NEW 2026-09-16: pure-manual-voucher residual auto-post
        -- (restores the original ResidualCash mechanic) - only applies
        -- when there are no invoices, since invoices already auto-post
        -- their own Amount-To-Apply leg against @parmcreditglcode and
        -- a second residual there would double up. Debit-heavy grid
        -- (e.g. a lone "Advances to Supplier" Debit line) auto-posts a
        -- Credit here; Credit-heavy grid auto-posts a Debit.
        IF (SELECT COUNT(*) FROM @InvoiceLines) = 0 AND @GLResidual <> 0
        BEGIN
            IF @GLResidual > 0
                INSERT INTO #Legs (AccountCode, Debit, Credit) VALUES (@parmcreditglcode, 0, @GLResidual);
            ELSE
                INSERT INTO #Legs (AccountCode, Debit, Credit) VALUES (@parmcreditglcode, -@GLResidual, 0);
        END

        -- ── Per-invoice settlement + auto AP-Trade/Variance legs ──
        DECLARE @row INT = 1, @maxrow INT, @invBranch VARCHAR(5), @invInvoiceNo VARCHAR(150),
                @invSeqRef VARCHAR(50), @invBatchRef BIGINT, @invAmtPaid DECIMAL(18,2),
                @invVariance DECIMAL(18,2), @invGross DECIMAL(18,2), @invPayableAcct VARCHAR(20),
                @invCurBalance DECIMAL(18,2), @invExpectedBalance DECIMAL(18,2),
                @invNewBalance DECIMAL(18,2), @transid INT;
        SELECT @maxrow = COUNT(*) FROM @InvoiceLines;

        IF OBJECT_ID('tempdb..#InvLines') IS NOT NULL DROP TABLE #InvLines;
        SELECT ROW_NUMBER() OVER (ORDER BY InvoiceNo) AS RowNum,
               BranchCode, InvoiceNo, SequenceReferenceNumber, BatchReferenceID,
               AmountPaid, Variance, ExpectedBalance
        INTO #InvLines FROM @InvoiceLines;

        WHILE @row <= @maxrow
        BEGIN
            SELECT
                @invBranch = BranchCode, @invInvoiceNo = InvoiceNo,
                @invSeqRef = SequenceReferenceNumber, @invBatchRef = BatchReferenceID,
                @invAmtPaid = ISNULL(AmountPaid,0), @invVariance = ISNULL(Variance,0),
                @invExpectedBalance = ExpectedBalance
            FROM #InvLines WHERE RowNum = @row;

            SET @invGross = @invAmtPaid - @invVariance;

            IF @parmpaymethod = 'PURCHASE'
            BEGIN
                -- PURCHASE invoices carry no per-row payable-account
                -- column (APAccounts) - use the config-driven default
                -- resolved above (JournalEntryMapping VOUCHER-MANUAL-
                -- APTRADE / PURCHASE, normally 20101 ACCOUNTS PAYABLE - TRADE).
                SET @invPayableAcct = @APTradeAccountPurchase;

                -- UPDLOCK/ROWLOCK: hold the row for the rest of this
                -- transaction so a concurrent voucher against the same
                -- invoice can't read the same starting Balance (lost
                -- update) between this SELECT and the UPDATE below.
                SET @invCurBalance = NULL;
                SELECT @invCurBalance = Balance FROM APAccounts WITH (UPDLOCK, ROWLOCK)
                WHERE SupplierID = @parmsupplierid AND InvoiceNo = @invInvoiceNo AND SequenceNo = @invSeqRef;

                IF @invCurBalance IS NULL
                BEGIN
                    -- THROW's message must be a literal or a variable, not an expression.
                    DECLARE @NotFoundMsgP VARCHAR(500) = 'Invoice ' + ISNULL(@invInvoiceNo,'') + ' was not found in APAccounts (SequenceNo ' + ISNULL(@invSeqRef,'') + ').';
                    THROW 58023, @NotFoundMsgP, 1;
                END

                -- CHANGED 2026-09-21 (partial payment): the CURRENT
                -- Balance must equal the Balance the client grid was
                -- loaded with (ExpectedBalance) - if it doesn't, the
                -- grid is stale (e.g. another payment posted against
                -- it in the meantime). Fail rather than settle against
                -- a Balance the user never saw. This replaces the old
                -- "Gross must equal Balance" test, which forbade a
                -- deliberate partial payment (Known Bug Pattern #10
                -- intent is unchanged: never trust the caller's number
                -- over the freshly-read, UPDLOCK'd Balance).
                IF ROUND(@invCurBalance - @invExpectedBalance, 2) <> 0
                BEGIN
                    DECLARE @StaleMsgP VARCHAR(500) = 'Invoice ' + ISNULL(@invInvoiceNo,'') + ': its Balance is now ' + CAST(@invCurBalance AS VARCHAR(30))
                        + ' but this voucher was loaded against ' + CAST(@invExpectedBalance AS VARCHAR(30))
                        + '. It may have been paid or adjusted since this voucher was loaded - refresh Load Invoices and try again.';
                    THROW 58024, @StaleMsgP, 1;
                END

                -- With staleness ruled out, the settlement (Gross) can
                -- be anything up to the Balance: = Balance is a full
                -- payment (with or without an FX Variance), < Balance
                -- is a partial payment. Above Balance is never valid.
                IF ROUND(@invGross - @invCurBalance, 2) > 0
                BEGIN
                    DECLARE @GrossMsgP VARCHAR(500) = 'Invoice ' + ISNULL(@invInvoiceNo,'') + ': the amount being settled (' + CAST(@invGross AS VARCHAR(30))
                        + ') exceeds its Balance (' + CAST(@invCurBalance AS VARCHAR(30))
                        + '). For a partial payment Amount to Apply must be less than Balance; for an FX difference leave Variance as computed.';
                    THROW 58030, @GrossMsgP, 1;
                END

                -- An FX row (Variance <> 0) is a full settlement by
                -- definition - the FX leg only makes sense if the invoice
                -- is closed out. Partial + FX on the same row is refused
                -- server-side too, not just by the grid.
                IF @invVariance <> 0 AND ROUND(@invGross - @invCurBalance, 2) <> 0
                BEGIN
                    DECLARE @FxPartialMsgP VARCHAR(500) = 'Invoice ' + ISNULL(@invInvoiceNo,'') + ': a Variance (FX difference) requires the invoice to be settled in full - it cannot be combined with a partial payment.';
                    THROW 58033, @FxPartialMsgP, 1;
                END

                -- Overpayment guard - Check/Cash still can't carry an
                -- FX variance (enforced up front, 58022), so this only
                -- fires for a genuine input error.
                IF @invAmtPaid > @invCurBalance AND @parmvouchertype IN ('CHECK','CASH')
                BEGIN
                    DECLARE @OverpayMsgP VARCHAR(500) = 'Invoice ' + ISNULL(@invInvoiceNo,'') + ': Amount Paid ('
                        + CAST(@invAmtPaid AS VARCHAR(30)) + ') exceeds its Balance ('
                        + CAST(@invCurBalance AS VARCHAR(30)) + '). Not allowed for Check/Cash vouchers.';
                    THROW 58015, @OverpayMsgP, 1;
                END

                SET @invNewBalance = ROUND(CASE WHEN @invCurBalance - @invGross < 0 THEN 0 ELSE @invCurBalance - @invGross END, 2);

                UPDATE APAccounts
                SET Balance = @invNewBalance,
                    AmountPaid = ISNULL(AmountPaid,0) + @invAmtPaid,
                    PayStatus = CASE WHEN @invNewBalance <= 0 THEN 'FULLYPAID' ELSE 'PARTIAL' END
                WHERE SupplierID = @parmsupplierid AND InvoiceNo = @invInvoiceNo AND SequenceNo = @invSeqRef;

                INSERT INTO APPaymentDetails
                    (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                     InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                     VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                     SequenceReferenceNumber, BatchReferenceID, Variance)
                VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @invBranch,
                        @invInvoiceNo, @parmvoucherdate, @invAmtPaid, 'INVOICE PAYMENT',
                        @parmpaymethod, @parmvouchertype, @ticketnum, @invPayableAcct, @parmcreditglcode,
                        @invSeqRef, NULL, @invVariance);
            END
            ELSE  -- EXPENSE
            BEGIN
                SET @invCurBalance = NULL;
                SET @invPayableAcct = NULL;
                SELECT @invCurBalance = ISNULL(Balance, ISNULL(Amount,0)), @invPayableAcct = PayableAccountCode
                FROM ExpenseSummary WITH (UPDLOCK, ROWLOCK)
                WHERE SupplierID = @supplierkey AND InvoiceNo = @invInvoiceNo AND BatchReferenceID = @invBatchRef;

                IF @invCurBalance IS NULL
                BEGIN
                    DECLARE @NotFoundMsgE VARCHAR(500) = 'Invoice ' + ISNULL(@invInvoiceNo,'') + ' was not found in ExpenseSummary (BatchReferenceID ' + CAST(ISNULL(@invBatchRef,0) AS VARCHAR(30)) + ').';
                    THROW 58023, @NotFoundMsgE, 1;
                END

                -- ExpenseSummary.PayableAccountCode wins when set (real
                -- per-invoice data); otherwise fall back to the config-
                -- driven default resolved above (JournalEntryMapping
                -- VOUCHER-MANUAL-APTRADE / EXPENSE, normally 20103).
                SET @invPayableAcct = ISNULL(NULLIF(LTRIM(RTRIM(@invPayableAcct)),''), @APTradeAccountExpenseFallback);
                -- [105] 2026-10-17: a loan's payable (PostingMode 'LOAN') is paid from the loan's own branch: the loan is kept on
                --       that branch's GL (Loan Revaluation checks payable = GL there), and this voucher posts on @parmbranch
                IF EXISTS (SELECT 1 FROM dbo.ExpenseSummary es INNER JOIN dbo.LoanAccount la ON la.PayableBatchReferenceID = es.BatchReferenceID AND la.SupplierID = es.SupplierID
                           WHERE es.SupplierID = @supplierkey AND es.InvoiceNo = @invInvoiceNo AND es.BatchReferenceID = @invBatchRef
                             AND es.PostingMode = 'LOAN' AND (la.BranchCode <> @parmbranch OR la.BranchCode <> ISNULL(@invBranch, la.BranchCode)))
                BEGIN
                    DECLARE @LoanBranchMsg VARCHAR(500) = 'Invoice ' + ISNULL(@invInvoiceNo,'') + ' is a loan kept on branch '
                        + (SELECT TOP 1 la.BranchCode FROM dbo.LoanAccount la WHERE la.PayableBatchReferenceID = @invBatchRef AND la.SupplierID = @supplierkey)
                        + ': pay it from that branch (the voucher''s paying branch).';
                    THROW 58040, @LoanBranchMsg, 1;
                END

                -- Same stale-grid + Gross-vs-Balance guards as PURCHASE - see 58024/58030 above.
                IF ROUND(@invCurBalance - @invExpectedBalance, 2) <> 0
                BEGIN
                    DECLARE @StaleMsgE VARCHAR(500) = 'Invoice ' + ISNULL(@invInvoiceNo,'') + ': its Balance is now ' + CAST(@invCurBalance AS VARCHAR(30))
                        + ' but this voucher was loaded against ' + CAST(@invExpectedBalance AS VARCHAR(30))
                        + '. It may have been paid or adjusted since this voucher was loaded - refresh Load Invoices and try again.';
                    THROW 58024, @StaleMsgE, 1;
                END

                IF ROUND(@invGross - @invCurBalance, 2) > 0
                BEGIN
                    DECLARE @GrossMsgE VARCHAR(500) = 'Invoice ' + ISNULL(@invInvoiceNo,'') + ': the amount being settled (' + CAST(@invGross AS VARCHAR(30))
                        + ') exceeds its Balance (' + CAST(@invCurBalance AS VARCHAR(30))
                        + '). For a partial payment Amount to Apply must be less than Balance; for an FX difference leave Variance as computed.';
                    THROW 58030, @GrossMsgE, 1;
                END

                IF @invVariance <> 0 AND ROUND(@invGross - @invCurBalance, 2) <> 0
                BEGIN
                    DECLARE @FxPartialMsgE VARCHAR(500) = 'Invoice ' + ISNULL(@invInvoiceNo,'') + ': a Variance (FX difference) requires the invoice to be settled in full - it cannot be combined with a partial payment.';
                    THROW 58033, @FxPartialMsgE, 1;
                END

                IF @invAmtPaid > @invCurBalance AND @parmvouchertype IN ('CHECK','CASH')
                BEGIN
                    DECLARE @OverpayMsgE VARCHAR(500) = 'Invoice ' + ISNULL(@invInvoiceNo,'') + ': Amount Paid ('
                        + CAST(@invAmtPaid AS VARCHAR(30)) + ') exceeds its Balance ('
                        + CAST(@invCurBalance AS VARCHAR(30)) + '). Not allowed for Check/Cash vouchers.';
                    THROW 58016, @OverpayMsgE, 1;
                END

                SET @invNewBalance = ROUND(CASE WHEN @invCurBalance - @invGross < 0 THEN 0 ELSE @invCurBalance - @invGross END, 2);

                UPDATE ExpenseSummary
                SET Balance = @invNewBalance,
                    AmountPaid = ISNULL(AmountPaid,0) + @invAmtPaid,
                    Status = CASE WHEN @invNewBalance <= 0 THEN 'FULLYPAID' ELSE 'PARTIAL' END,
                    UpdatedBy = @parmpreparedby, DateTimeUpdated = GETDATE()
                WHERE SupplierID = @supplierkey AND InvoiceNo = @invInvoiceNo AND BatchReferenceID = @invBatchRef;

                IF @invNewBalance <= 0
                    UPDATE ExpenseMaster SET Balance = 0, AmountPaid = Amount, Status = 'FULLYPAID'
                    WHERE SupplierID = @supplierkey AND InvoiceNo = @invInvoiceNo AND BatchReferenceID = @invBatchRef;
                ELSE
                BEGIN
                    -- NEW 2026-09-21 (partial payment): ExpenseMaster is
                    -- line-level (SUM(Balance) per invoice is what other
                    -- screens read), so a partial has to come off the
                    -- line Balances too - oldest line (TRN_SEQ_NO) first,
                    -- spilling into the next only once a line is used up.
                    -- Staged in a temp table because a windowed running
                    -- total can't be UPDATEd through directly.
                    IF OBJECT_ID('tempdb..#ExpAlloc') IS NOT NULL DROP TABLE #ExpAlloc;

                    SELECT TRN_SEQ_NO,
                           CASE WHEN @invGross <= PriorBal THEN 0
                                WHEN @invGross - PriorBal >= LineBal THEN LineBal
                                ELSE @invGross - PriorBal
                           END AS Alloc
                    INTO #ExpAlloc
                    FROM (
                        SELECT TRN_SEQ_NO,
                               ISNULL(Balance, ISNULL(Amount,0)) AS LineBal,
                               SUM(ISNULL(Balance, ISNULL(Amount,0))) OVER (ORDER BY TRN_SEQ_NO ROWS UNBOUNDED PRECEDING)
                                 - ISNULL(Balance, ISNULL(Amount,0)) AS PriorBal
                        FROM ExpenseMaster WITH (UPDLOCK, ROWLOCK)
                        WHERE SupplierID = @supplierkey AND InvoiceNo = @invInvoiceNo AND BatchReferenceID = @invBatchRef
                          AND ISNULL(Status,'') NOT IN ('FULLYPAID','VOID','CANCELLED')
                          AND ISNULL(Balance, ISNULL(Amount,0)) > 0   -- open lines only; a zero/negative line can't absorb payment
                    ) lines;

                    -- The eligible lines must be able to absorb the whole
                    -- settlement - ExpenseSummary.Balance (checked above)
                    -- and ExpenseMaster line Balances are separate stores,
                    -- so prove they agree instead of silently dropping a
                    -- shortfall. Rolls back with everything else.
                    IF ROUND(ISNULL((SELECT SUM(Alloc) FROM #ExpAlloc), 0) - @invGross, 2) <> 0
                    BEGIN
                        DECLARE @AllocMsg VARCHAR(500) = 'Invoice ' + ISNULL(@invInvoiceNo,'') + ': its ExpenseMaster line balances cannot absorb the amount being settled ('
                            + CAST(@invGross AS VARCHAR(30)) + ') - ExpenseSummary and ExpenseMaster disagree. Nothing was posted; check this invoice''s expense lines.';
                        THROW 58035, @AllocMsg, 1;
                    END

                    UPDATE em
                    SET Balance    = ISNULL(em.Balance, ISNULL(em.Amount,0)) - a.Alloc,
                        AmountPaid = ISNULL(em.AmountPaid,0) + a.Alloc,
                        Status     = CASE WHEN ISNULL(em.Balance, ISNULL(em.Amount,0)) - a.Alloc <= 0 THEN 'FULLYPAID' ELSE 'PARTIAL' END
                    FROM ExpenseMaster em
                    JOIN #ExpAlloc a ON a.TRN_SEQ_NO = em.TRN_SEQ_NO
                    WHERE em.SupplierID = @supplierkey AND em.InvoiceNo = @invInvoiceNo AND em.BatchReferenceID = @invBatchRef
                      AND a.Alloc > 0;   -- lines the payment never reached keep their status

                    DROP TABLE #ExpAlloc;
                END

                INSERT INTO APPaymentDetails
                    (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                     InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                     VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                     SequenceReferenceNumber, BatchReferenceID, Variance)
                VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @invBranch,
                        @invInvoiceNo, @parmvoucherdate, @invAmtPaid, 'EXPENSE PAYMENT',
                        @parmpaymethod, @parmvouchertype, @ticketnum, @invPayableAcct, @parmcreditglcode,
                        CAST(@invBatchRef AS VARCHAR(50)), @invBatchRef, @invVariance);
            END

            -- NEW: Amount-To-Apply auto leg pair, staged into #Legs
            -- (not TicketDetails directly - netted per account at the
            -- end into a compound entry) - Debit AP-Trade, Credit the
            -- header's Credit GLCode (e.g. Cash in Bank).
            IF @invAmtPaid > 0
            BEGIN
                INSERT INTO #Legs (AccountCode, Debit, Credit) VALUES (@invPayableAcct, @invAmtPaid, 0);
                INSERT INTO #Legs (AccountCode, Debit, Credit) VALUES (@parmcreditglcode, 0, @invAmtPaid);
            END

            -- NEW: Variance auto leg pair, staged the same way. Loss
            -- (paid MORE than Balance): Debit 60323, Credit AP-Trade
            -- back down. Gain (paid LESS than Balance): Debit AP-Trade
            -- up to Balance, Credit 60323.
            IF @invVariance > 0
            BEGIN
                INSERT INTO #Legs (AccountCode, Debit, Credit) VALUES (@FXLossAccountCode, @invVariance, 0);
                INSERT INTO #Legs (AccountCode, Debit, Credit) VALUES (@invPayableAcct, 0, @invVariance);
            END
            ELSE IF @invVariance < 0
            BEGIN
                INSERT INTO #Legs (AccountCode, Debit, Credit) VALUES (@invPayableAcct, -@invVariance, 0);
                INSERT INTO #Legs (AccountCode, Debit, Credit) VALUES (@FXGainAccountCode, 0, -@invVariance);
            END

            SET @transid = dbo.func_getLastID(@supplierkey);
            INSERT INTO [dbo].[SupplierLedger]
                (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate,
                 Description, TransCode, TransactionDate, ReferenceNumber,
                 ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance,
                 TransactedBy, ApprovedBy, TotalAmount, PaymentType,
                 ErrorCorrectTag, TicketReference, BatchReferenceID)
            VALUES (@transid, @supplierkey, @supplierkey, @parmvoucherdate,
                    LEFT(ISNULL(@parmremarks,''), 490), 'PV-MANUAL', @parmvoucherdate,
                    @parmrefno, @PhysicalRef, @invInvoiceNo, 0, @invGross, 0, @invGross,
                    @parmpreparedby, '*', @invGross,
                    CASE WHEN @invNewBalance<=0 THEN 'FULLYPAID' ELSE 'PARTIAL' END,
                    0, @ticketnum, @invBatchRef);

            SET @row += 1;
        END;

        DROP TABLE #InvLines;

        -- ── Compound the staged legs into TicketDetails ──
        -- NEW: net every staged leg (manual GL lines + pure-manual-
        -- voucher residual + all per-invoice Amount-To-Apply/Variance
        -- legs) per AccountCode into exactly one Debit-or-Credit row -
        -- a true compound entry instead of a separate row per source.
        -- A same-account wash (nets to exactly 0, e.g. offsetting
        -- entries on the same account) posts no row at all rather than
        -- a spurious $0.00 line.
        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        SELECT
            @parmvoucherdate, 0, @parmbranch, @parmvoucherid, @ticketnum, @parmrefno,
            AccountCode,
            CASE WHEN NetAmount > 0 THEN NetAmount ELSE 0 END,
            CASE WHEN NetAmount < 0 THEN -NetAmount ELSE 0 END,
            ''
        FROM (
            SELECT AccountCode, ROUND(SUM(Debit) - SUM(Credit), 2) AS NetAmount
            FROM #Legs
            GROUP BY AccountCode
        ) net
        WHERE NetAmount <> 0;

        DROP TABLE #Legs;

        -- ── Bank Recon ──
        -- FIX: sp_Payment_PostBankReconEntry is idempotent per
        -- (ReferenceNo, AccountCode, ItemType) - it silently no-ops
        -- (RETURN, no error) if that exact combination was already
        -- posted. The invoice-driven cash and the manual grid's own
        -- bank lines can land on the SAME account (e.g. the user's own
        -- worked example: invoice cash + an advance, both against
        -- "Cash in Bank"), which previously meant TWO separate calls
        -- with the same @ReferenceNo/@AccountCode/@ItemType='OC' -
        -- the second one would be silently dropped, permanently
        -- understating that account's reconciliation with no error.
        -- Combine everything per account BEFORE calling the proc, so
        -- each (account, type) combination is called exactly once with
        -- the correct combined amount. (This also incidentally fixes
        -- the same latent collision risk that already existed if a
        -- user typed two separate manual lines against the same bank
        -- account.)
        DECLARE @PeriodEnd DATE = EOMONTH(@parmvoucherdate);
        DECLARE @Remarks VARCHAR(500);

        IF OBJECT_ID('tempdb..#BankLines') IS NOT NULL DROP TABLE #BankLines;
        SELECT
            ROW_NUMBER() OVER (ORDER BY AccountCode) AS RowNum,
            AccountCode, TotalDebit, TotalCredit
        INTO #BankLines
        FROM (
            SELECT AccountCode, SUM(Debit) AS TotalDebit, SUM(Credit) AS TotalCredit
            FROM (
                SELECT @parmcreditglcode AS AccountCode, CAST(0 AS DECIMAL(18,2)) AS Debit, @TotalInvoiceCash AS Credit
                FROM (SELECT 1 AS dummy) d
                WHERE @TotalInvoiceCash > 0
                  AND @parmcreditglcode IS NOT NULL
                  AND EXISTS (SELECT 1 FROM ChartOfAccounts WHERE AccountCode = @parmcreditglcode AND AccountCode LIKE '10102%')

                UNION ALL

                SELECT gl.AccountCode, gl.Debit, gl.Credit
                FROM @GLLines gl
                JOIN ChartOfAccounts coa ON coa.AccountCode = gl.AccountCode
                WHERE coa.AccountCode LIKE '10102%'

                UNION ALL

                -- NEW 2026-09-16: pure-manual-voucher residual leg
                -- (see #Legs staging above) - only when there are no
                -- invoices, mirroring that same guard.
                SELECT @parmcreditglcode AS AccountCode,
                       CASE WHEN @GLResidual < 0 THEN -@GLResidual ELSE 0 END AS Debit,
                       CASE WHEN @GLResidual > 0 THEN @GLResidual ELSE 0 END AS Credit
                FROM (SELECT 1 AS dummy) d
                WHERE (SELECT COUNT(*) FROM @InvoiceLines) = 0
                  AND @GLResidual <> 0
                  AND @parmcreditglcode IS NOT NULL
                  AND EXISTS (SELECT 1 FROM ChartOfAccounts WHERE AccountCode = @parmcreditglcode AND AccountCode LIKE '10102%')
            ) src
            GROUP BY AccountCode
        ) grouped;

        DECLARE @bi INT = 1, @bmax INT, @bAcct VARCHAR(20), @bDebit DECIMAL(18,2), @bCredit DECIMAL(18,2);
        SELECT @bmax = COUNT(*) FROM #BankLines;

        WHILE @bi <= @bmax
        BEGIN
            SELECT @bAcct = AccountCode, @bDebit = TotalDebit, @bCredit = TotalCredit FROM #BankLines WHERE RowNum = @bi;

            IF @bCredit > 0
            BEGIN
                 SET @Remarks = 'Auto-OC | VOUCHER-MANUAL | Ref: ' + ISNULL(@parmrefno, '');
                EXEC dbo.sp_Payment_PostBankReconEntry
                    @ItemType='OC', @BranchCode=@parmbranch, @AccountCode=@bAcct,
                    @PeriodEnd=@PeriodEnd, @ReferenceNo=@parmvoucherid, @ItemDate=@parmvoucherdate,
                    @Payee=@parmsuppliername, @Amount=@bCredit,
                    @Remarks=@Remarks,
                    @SourceModule='AP-PAYMENT', @SourceRef=@parmrefno, @CreatedBy=@parmpreparedby;
            END

            IF @bDebit > 0
            BEGIN
                 SET @Remarks = 'Auto-DIT | VOUCHER-MANUAL | Ref: ' + ISNULL(@parmrefno, '');
                EXEC dbo.sp_Payment_PostBankReconEntry
                    @ItemType='DIT', @BranchCode=@parmbranch, @AccountCode=@bAcct,
                    @PeriodEnd=@PeriodEnd, @ReferenceNo=@parmvoucherid, @ItemDate=@parmvoucherdate,
                    @Payee=@parmsuppliername, @Amount=@bDebit,
                    @Remarks=@Remarks,
                    @SourceModule='AP-PAYMENT', @SourceRef=@parmrefno, @CreatedBy=@parmpreparedby;
            END

            SET @bi += 1;
        END;
        DROP TABLE #BankLines;

        -- Prove the whole compound entry balances before commit -
        -- more valuable than ever now, given how many more auto legs
        -- are being assembled per invoice.
        DECLARE @CheckDebit DECIMAL(18,2), @CheckCredit DECIMAL(18,2);
        SELECT @CheckDebit = ISNULL(SUM(Debit),0), @CheckCredit = ISNULL(SUM(Credit),0)
        FROM TicketDetails WHERE TicketNumber = @ticketnum;

        IF ABS(@CheckDebit - @CheckCredit) > 0.01
        BEGIN
            DECLARE @BalMsg VARCHAR(300) = 'Journal entry is out of balance: Debit ' + CAST(@CheckDebit AS VARCHAR(30))
                + ' vs Credit ' + CAST(@CheckCredit AS VARCHAR(30)) + '.';
            THROW 58019, @BalMsg, 1;
        END

        COMMIT TRAN;

        SELECT 1 AS Status, @parmrefno AS ReferenceNo, @TotalVoucherAmount AS TotalAmount,
               'Voucher posted successfully.' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

------------------------------------------------------------------
-- 7. The loan payable stays out of every other payment path and the old expense screens
--    (sweep of the 47 readers of ExpenseSummary / ExpenseMaster, 2026-10-17: these list or settle it wrongly;
--     the web portal's sp_rpt_APEXP_Aging / sp_rpt_DataHealthCheck(Detail) are the portal's, told in the sync handoff)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.splist_Accounts', 'splist_Accounts_OLD_10172026210000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE [dbo].[splist_Accounts]
    @parmsupplierid VARCHAR(30),
    @parmispurchase BIT,
    @parmisexpense  BIT
AS
BEGIN
    SET NOCOUNT ON;

    IF (@parmispurchase = 0 AND @parmisexpense = 0)
    BEGIN
        SELECT
            CAST(NULL AS BIGINT)        AS SequenceNumber,
            CAST('NONE' AS VARCHAR(15)) AS Pay,
            CAST(NULL AS VARCHAR(10))   AS ShipmentNo,
            CAST(NULL AS VARCHAR(5))    AS BranchCode,
            CAST(NULL AS VARCHAR(150))  AS ReferenceNo,
            CAST(NULL AS BIGINT)        AS BatchReferenceID,
            CAST(NULL AS VARCHAR(150))  AS InvoiceNo,
            CAST(NULL AS DATE)          AS InvoiceDate,
            CAST(NULL AS VARCHAR(5000)) AS Description,
            CAST(NULL AS DECIMAL(12,2)) AS ActualCost,
            CAST(NULL AS DECIMAL(12,2)) AS Balance,
            CAST(0 AS DECIMAL(12,2))    AS AmountPaid,
            CAST(0 AS DECIMAL(12,2))    AS Variance,
            CAST(0 AS DECIMAL(12,2))    AS EWTAmount,
            CAST(0 AS DECIMAL(12,2))    AS DiscountAmount,
            CAST(0 AS DECIMAL(12,2))    AS ReturnAllowances,
            CAST(NULL AS VARCHAR(30))   AS Type
        WHERE 1=0;
        RETURN;
    END;

    -- [97] 2026-10-15: both flags = purchases and expenses of the supplier in one list (SupplierPaymentDevEx, cash / check).
    --      Same columns as the one-kind lists below (keep the three in step); Type tells the kind.
    IF (@parmispurchase = 1 AND @parmisexpense = 1)
    BEGIN
        SELECT x.SequenceNumber, x.Pay, x.ShipmentNo, x.BranchCode, x.ReferenceNo, x.BatchReferenceID, x.InvoiceNo, x.InvoiceDate,
               x.Description, x.ActualCost, x.Balance, x.AmountPaid, x.Variance, x.EWTAmount, x.DiscountAmount, x.DiscountAccountCode,
               x.ReturnAllowances, x.Type
        FROM (
            SELECT CAST(a.SequenceNo AS BIGINT) AS SequenceNumber, CAST('NONE' AS VARCHAR(15)) AS Pay, a.ShipmentNo, b.BranchCode,
                   CAST(a.InvoiceNo AS VARCHAR(150)) AS ReferenceNo, CAST(0 AS BIGINT) AS BatchReferenceID, CAST(a.InvoiceNo AS VARCHAR(150)) AS InvoiceNo,
                   a.InvoiceDate, CAST(ISNULL(CAST(a.InvoiceNo AS VARCHAR(50)), ' ') AS VARCHAR(5000)) AS Description,
                   CAST(ISNULL(a.ActualCost, 0) AS DECIMAL(12,2)) AS ActualCost, CAST(ISNULL(a.Balance, 0) AS DECIMAL(12,2)) AS Balance,
                   CAST(0 AS DECIMAL(12,2)) AS AmountPaid, CAST(0 AS DECIMAL(12,2)) AS Variance, CAST(0 AS DECIMAL(12,2)) AS EWTAmount,
                   CAST(0 AS DECIMAL(12,2)) AS DiscountAmount, CAST(NULL AS VARCHAR(20)) AS DiscountAccountCode,
                   CAST(0 AS DECIMAL(12,2)) AS ReturnAllowances, CAST('PURCHASE' AS VARCHAR(30)) AS Type
            FROM dbo.APACCOUNTS a
            INNER JOIN POSUMMARY b ON a.ShipmentNo = b.ShipmentNo
            WHERE a.PayStatus IN ('UNPAID','PARTIAL') AND a.Balance > 0 AND a.SupplierID = @parmsupplierid
            UNION ALL
            SELECT CAST(es.BatchReferenceID AS BIGINT), CAST('NONE' AS VARCHAR(15)), CAST('' AS VARCHAR(10)),
                   (SELECT TOP 1 em2.BranchCode FROM ExpenseMaster em2
                    WHERE em2.SupplierID = es.SupplierID AND em2.InvoiceNo = es.InvoiceNo AND em2.BatchReferenceID = es.BatchReferenceID
                    ORDER BY em2.TRN_SEQ_NO),
                   CAST(es.ReferenceNumber AS VARCHAR(150)), es.BatchReferenceID, CAST(es.InvoiceNo AS VARCHAR(150)), es.ExpenseDate,
                   CAST(es.Description AS VARCHAR(5000)),
                   CAST(ISNULL(es.Amount, 0) AS DECIMAL(12,2)), CAST(ISNULL(es.Balance, ISNULL(es.Amount, 0)) AS DECIMAL(12,2)),
                   CAST(ISNULL(es.AmountPaid, 0) AS DECIMAL(12,2)), CAST(0 AS DECIMAL(12,2)),
                   CAST(CASE WHEN ISNULL(es.EWTAmount,0) - ISNULL(es.EWTWithheld,0) < 0 THEN 0 ELSE ISNULL(es.EWTAmount,0) - ISNULL(es.EWTWithheld,0) END AS DECIMAL(12,2)),
                   CAST(CASE WHEN ISNULL(es.DiscountAmount,0) - ISNULL(es.DiscountWithheld,0) < 0 THEN 0 ELSE ISNULL(es.DiscountAmount,0) - ISNULL(es.DiscountWithheld,0) END AS DECIMAL(12,2)),
                   CAST(NULL AS VARCHAR(20)),
                   CAST(CASE WHEN ISNULL(es.OffsetAmount,0) - ISNULL(es.OffsetWithheld,0) < 0 THEN 0 ELSE ISNULL(es.OffsetAmount,0) - ISNULL(es.OffsetWithheld,0) END AS DECIMAL(12,2)),
                   CAST('EXPENSE' AS VARCHAR(30))
            FROM dbo.ExpenseSummary es
            WHERE es.SupplierID = @parmsupplierid
              AND es.Status NOT IN ('PAID','VOID','CANCELLED','FOR APPROVAL','FULLYPAID')
              AND ISNULL(es.Balance, ISNULL(es.Amount, 0)) > 0
              AND ISNULL(es.PostingMode, '') <> 'LOAN'   -- [105] a loan is paid in Vouchering Telegraphic only (Expense list below)
        ) AS x
        ORDER BY x.InvoiceDate, x.Type, x.InvoiceNo;
        RETURN;
    END;

    -- PURCHASE
    IF (@parmispurchase = 1)
    BEGIN
        SELECT
            CAST(a.SequenceNo        AS BIGINT)        AS SequenceNumber,
            CAST('NONE'              AS VARCHAR(15))   AS Pay,
            a.ShipmentNo,
            b.BranchCode,
            CAST(a.InvoiceNo         AS VARCHAR(150))  AS ReferenceNo,
            CAST(0                   AS BIGINT)         AS BatchReferenceID,
            CAST(a.InvoiceNo         AS VARCHAR(150))  AS InvoiceNo,
            a.InvoiceDate,
            ISNULL(CAST(a.InvoiceNo  AS VARCHAR(50)),' ') AS Description,
            -- FIX: real DECIMAL, not FORMAT()-ed NVARCHAR - see header comment.
            CAST(ISNULL(a.ActualCost,0) AS DECIMAL(12,2)) AS ActualCost,
            CAST(ISNULL(a.Balance,0)    AS DECIMAL(12,2)) AS Balance,
            CAST(0  AS DECIMAL(12,2)) AS AmountPaid,
            CAST(0  AS DECIMAL(12,2)) AS Variance,
            CAST(0  AS DECIMAL(12,2)) AS EWTAmount,
            CAST(0  AS DECIMAL(12,2)) AS DiscountAmount,
            CAST(NULL AS VARCHAR(20)) AS DiscountAccountCode,
            CAST(0  AS DECIMAL(12,2)) AS ReturnAllowances,
            CAST('PURCHASE' AS VARCHAR(30)) AS Type
        FROM  dbo.APACCOUNTS a
        INNER JOIN POSUMMARY b ON a.ShipmentNo = b.ShipmentNo
        WHERE a.PayStatus   IN ('UNPAID','PARTIAL')
          AND a.Balance       > 0
          AND a.SupplierID    = @parmsupplierid
        ORDER BY a.InvoiceDate, a.InvoiceNo;
        RETURN;
    END;

    -- EXPENSE - one row per ExpenseSummary invoice
    IF (@parmisexpense = 1)
    BEGIN
        SELECT
            CAST(es.BatchReferenceID AS BIGINT)         AS SequenceNumber,
            CAST('NONE'              AS VARCHAR(15))    AS Pay,
            CAST(''                  AS VARCHAR(10))    AS ShipmentNo,
            (SELECT TOP 1 em2.BranchCode
             FROM   ExpenseMaster em2
             WHERE  em2.SupplierID       = es.SupplierID
               AND  em2.InvoiceNo        = es.InvoiceNo
               AND  em2.BatchReferenceID = es.BatchReferenceID
             ORDER BY em2.TRN_SEQ_NO)    AS BranchCode,
            CAST(es.ReferenceNumber      AS VARCHAR(150)) AS ReferenceNo,
            es.BatchReferenceID,
            CAST(es.InvoiceNo            AS VARCHAR(150)) AS InvoiceNo,
            es.ExpenseDate               AS InvoiceDate,
            es.Description,
            -- FIX: real DECIMAL, not FORMAT()-ed NVARCHAR - see header comment.
            -- Original gross amount
            -- [105] a loan's Actual Cost is its current value (= Balance, revalued every month end; user 2026-10-17)
            CAST(CASE WHEN es.PostingMode = 'LOAN' THEN ISNULL(es.Balance, ISNULL(es.Amount,0)) ELSE ISNULL(es.Amount,0) END AS DECIMAL(12,2)) AS ActualCost,
            -- Remaining balance to pay
            CAST(ISNULL(es.Balance, ISNULL(es.Amount,0)) AS DECIMAL(12,2)) AS Balance,
            CAST(ISNULL(es.AmountPaid,0) AS DECIMAL(12,2)) AS AmountPaid,
            CAST(0 AS DECIMAL(12,2))                                         AS Variance,

            -- REMAINING deductions - all ISNULL-guarded
            -- EWTAmount remaining = Total EWT - already withheld
            -- ISNULL on both sides: if either is NULL, treat as 0
            -- Result is clamped to 0 (never negative)
            CASE WHEN ISNULL(es.EWTAmount,0) - ISNULL(es.EWTWithheld,0) < 0
                 THEN 0
                 ELSE ISNULL(es.EWTAmount,0) - ISNULL(es.EWTWithheld,0)
            END                                                              AS EWTAmount,

            -- Discount remaining
            CASE WHEN ISNULL(es.DiscountAmount,0) - ISNULL(es.DiscountWithheld,0) < 0
                 THEN 0
                 ELSE ISNULL(es.DiscountAmount,0) - ISNULL(es.DiscountWithheld,0)
            END                                                              AS DiscountAmount,

            CAST(NULL AS VARCHAR(20)) AS DiscountAccountCode,
            -- Offset/Return remaining
            CASE WHEN ISNULL(es.OffsetAmount,0) - ISNULL(es.OffsetWithheld,0) < 0
                 THEN 0
                 ELSE ISNULL(es.OffsetAmount,0) - ISNULL(es.OffsetWithheld,0)
            END                                                              AS ReturnAllowances,

            CAST('EXPENSE' AS VARCHAR(30))                                   AS Type
        FROM dbo.ExpenseSummary es
        WHERE es.SupplierID  = @parmsupplierid
          AND es.Status      NOT IN ('PAID','VOID','CANCELLED','FOR APPROVAL','FULLYPAID')
          AND ISNULL(es.Balance, ISNULL(es.Amount, 0)) > 0
        ORDER BY es.ExpenseDate, es.BatchReferenceID;
        RETURN;
    END;
END;
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.sp_GetUnpaidInvoicesForSupplier', 'sp_GetUnpaidInvoicesForSupplier_OLD_10172026210000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
/* ================================================================
   COMBINED SUPPLIER VOUCHER — FIXES
   1. sp_GetUnpaidInvoicesForSupplier now also returns BranchCode
      (same TOP-1-from-ExpenseMaster pattern splist_Accounts uses),
      since the TVP needs it per line.
   2. sp_PostSupplierPaymentWithManualLines gains @parmcontrolno /
      @parmdate (for CASH/TELEGRAPHIC) and passes them through to
      sp_AddPaymentSupplierCompound, and accepts 'TELEGRAPHIC' as a
      voucher type alongside CASH/CHECK.
   ================================================================ */

CREATE   PROCEDURE [dbo].[sp_GetUnpaidInvoicesForSupplier]
    @SupplierID VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        es.ReferenceNumber,
        es.InvoiceNo,
        es.BatchReferenceID,
        es.ExpenseDate,
        es.Description,
        es.Amount,
        es.Balance,
        es.PostingMode,
        (SELECT TOP 1 em2.BranchCode
         FROM   ExpenseMaster em2
         WHERE  em2.SupplierID       = es.SupplierID
           AND  em2.InvoiceNo        = es.InvoiceNo
           AND  em2.BatchReferenceID = es.BatchReferenceID
         ORDER BY em2.TRN_SEQ_NO)    AS BranchCode
    FROM ExpenseSummary es
    WHERE es.SupplierID = @SupplierID
      AND es.Balance > 0
      AND ISNULL(es.PostingMode, '') <> 'LOAN'   -- [105] 2026-10-17: a loan is paid in Vouchering Telegraphic only
      AND es.Status NOT IN ('CANCELLED')
    ORDER BY es.ExpenseDate;
END
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.sp_AddPaymentSupplierCompound_V2', 'sp_AddPaymentSupplierCompound_V2_OLD_10172026210000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
/* ================================================================
   sp_AddPaymentSupplierCompound_V2
   Parallel to sp_AddPaymentSupplierCompound - same tables, same
   TVP shape (dbo.AP_PaymentLineTVP), callable as a drop-in test
   alternative. PURCHASE mode still delegates to your existing
   sp_PostCompoundTicket. EXPENSE mode (SINGLE + BATCH) is rebuilt
   entirely on the three helper procedures in 01_V2_Helpers.sql.

   PARAMETER CONTRACT (stated explicitly, not just assumed):
     @parmcheckamount MUST be net cash actually disbursed - never
     gross. This SP does not trust that blindly for Bank Recon:
     it self-computes net cash from the same figures used to build
     the tickets and uses THAT for Bank Recon and the voucher header.
   ================================================================ */
CREATE PROCEDURE [dbo].[sp_AddPaymentSupplierCompound_V2]
(
    @parmrefno          VARCHAR(10),
    @parmvoucherid      VARCHAR(10),
    @parmsupplierid     VARCHAR(50),
    @parmsuppliername   VARCHAR(150),
    @parmcheckamount    DECIMAL(18,2),
    @parmcheckcoding    VARCHAR(50),
    @parmcheckno        VARCHAR(50),
    @parmcontrolno      VARCHAR(50),
    @parmcheckdate      DATE,
    @parmcheckremarks   VARCHAR(2000),
    @parmpreparedby     VARCHAR(30),
    @parmglcode         VARCHAR(30),
    @parmpaymethod      VARCHAR(20),
    @parmforliquidation BIT          = 0,
    @parmvouchertype    VARCHAR(10),
    @Lines              [dbo].[AP_PaymentLineTVP] READONLY,
    @parmPayingBranch   VARCHAR(5)   = NULL,
    @LineExtras         [dbo].[AP_PaymentLineExtraTVP] READONLY,  -- NEW 2026-09-24, optional (empty when omitted)
    @SkipVoucherWrap    BIT          = 0,      -- [97] 1 = invoice lines only: no TransactionPaymentAP / OC / voucher header (a mixed voucher writes them once)
    @NetCashOut         DECIMAL(18,2) = NULL OUTPUT   -- [97] the net cash these lines disbursed
)
AS
/*
    2026-09-24: PURCHASE mode accepts per-line OverPay / OverPayExpense /
    AdvanceApplied via @LineExtras (see SQL/2026-09-24_SupplierPayment_
    OverpaymentCredit.sql header for the GL design). Per line:
        Gross (settles APAccounts.Balance)
          = AmountPaid + EWT + Discount + RetAllow + AdvanceApplied
            - Variance - OverPay - OverPayExpense
    OverPay/OverPayExpense are cash paid BEYOND the invoice; they are only
    allowed when Gross settles the fresh Balance exactly. AdvanceApplied is
    prior OverPay credit consumed instead of cash; total per voucher must not
    exceed the supplier's credit pool, re-derived under a per-supplier
    applock. Lines with none of the three post exactly as before (same
    mnemonics, same @Amounts/@Flags). EXPENSE mode rejects any nonzero extra.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;   -- [84] unnamed: a named ROLLBACK fails with 6401 when this proc runs inside an outer transaction
    BEGIN TRY

        DECLARE @SupplierKey VARCHAR(30), @SeqNo INT, @TicketNumber VARCHAR(20);
        -- 2026-09-25 (sp-reviewer): head-office branch code declared ONCE and reused by
        -- the up-front and in-loop multi-branch checks so they can't drift apart.
        DECLARE @HOBranch VARCHAR(5) = '888';
        DECLARE @PeriodEnd DATE = EOMONTH(ISNULL(@parmcheckdate,GETDATE()));
        DECLARE @ocPeriodEnd DATE;
        DECLARE @TotalNetCashForRecon DECIMAL(18,2) = 0;
        DECLARE @ocBranch VARCHAR(5) = NULLIF(LTRIM(RTRIM(ISNULL(@parmPayingBranch,''))), '');

        IF @parmcheckdate IS NULL SET @parmcheckdate = CAST(GETDATE() AS DATE);
        SET @ocPeriodEnd = EOMONTH(@parmcheckdate);

        SELECT @SupplierKey = SupplierKey FROM Supplier WHERE SupplierID = @parmsupplierid;

        IF @SupplierKey IS NULL
        BEGIN
            DECLARE @NoSupplierMsg VARCHAR(300) = 'Supplier ' + ISNULL(@parmsupplierid,'') + ' was not found.';
            THROW 60507, @NoSupplierMsg, 1;
        END

        IF ISNULL(@SkipVoucherWrap, 0) = 0   -- [97]
        BEGIN
        SELECT @SeqNo = ISNULL(MAX(SEQ_NO),0) + 1 FROM TransactionPaymentAP WHERE SupplierKey = @SupplierKey;
        INSERT INTO [dbo].[TransactionPaymentAP]
            (SEQ_NO, SupplierKey, ReferenceNumber, Amount, VoucherType,
             DatePaid, ExecuteBy, DateUpdate, UpdateBy, ErrorCorrect)
        VALUES (@SeqNo, @SupplierKey, @parmrefno, @parmcheckamount, @parmvouchertype,
                @parmcheckdate, @parmpreparedby, GETDATE(), @parmpreparedby, 0);
        END   -- [97]

        -- -- #Lines ------------------------------------------------
        SELECT
            ROW_NUMBER() OVER (ORDER BY L.BatchReferenceID, L.InvoiceNo) AS RowNum,
            L.InvoiceNo, L.InvoiceDate, L.SequenceReferenceNumber, L.BatchReferenceID,
            ISNULL(L.ActualCost, 0) AS ActualCost, ISNULL(L.AmountPaid, 0) AS AmountPaid,
            ISNULL(L.EWTAmount, 0) AS EWTAmount,
            ISNULL(L.DiscountAmount, 0) AS DiscountAmount,
            ISNULL(L.OffsetAmount, 0) AS OffsetAmount,
            ISNULL(L.Variance, 0) AS Variance,
            L.DiscountAccountCode,
            L.Description,
            -- NEW 2026-09-24
            ISNULL(X.OverPay, 0)        AS OverPay,
            ISNULL(X.OverPayExpense, 0) AS OverPayExpense,
            ISNULL(X.AdvanceApplied, 0) AS AdvanceApplied
        INTO #Lines
        FROM @Lines L
        LEFT JOIN @LineExtras X
               ON X.InvoiceNo = L.InvoiceNo
              AND X.SequenceReferenceNumber = L.SequenceReferenceNumber;

        -- -- NEW 2026-09-24: @LineExtras guards ----------------------
        -- An extras row that matches no invoice line would otherwise be
        -- silently dropped by the LEFT JOIN above.
        IF EXISTS (
            SELECT 1 FROM @LineExtras X
            WHERE NOT EXISTS (SELECT 1 FROM @Lines L
                              WHERE L.InvoiceNo = X.InvoiceNo
                                AND L.SequenceReferenceNumber = X.SequenceReferenceNumber)
        )
            THROW 60510, 'An OverPay/Advance line does not match any invoice being paid in this voucher.', 1;

        IF EXISTS (SELECT 1 FROM #Lines WHERE OverPay < 0 OR OverPayExpense < 0 OR AdvanceApplied < 0)
            THROW 60511, 'OverPay, OverPay (Expense), and Advance Applied cannot be negative.', 1;

        -- CHANGED 2026-09-25: the up-front BATCH rejection (60509, added
        -- 2026-09-24c) is gone - multi-branch expense invoices (PostingMode
        -- MULTI-MANUAL / BATCH / NULL, i.e. anything not SINGLE) now support
        -- the extras too, booked on the head-office (888) branch ticket. See
        -- the BATCH branch below; its HO-specific rejections (60522) happen
        -- before anything is written for that invoice, and the whole voucher
        -- is one transaction either way.
        -- The "advance on an invoice with no head-office share" case is also
        -- checked HERE, before the credit-pool check below, so the user gets
        -- the specific 60522 instead of a misleading 60514 (same ordering
        -- lesson as sp-reviewer 24c). The BATCH branch re-checks per invoice.
        IF @parmpaymethod <> 'PURCHASE'
           AND EXISTS (
               SELECT 1
               FROM #Lines l
               JOIN ExpenseSummary es
                 ON es.SupplierID       = @SupplierKey
                AND es.BatchReferenceID = l.BatchReferenceID
                AND es.InvoiceNo        = l.InvoiceNo
               WHERE ISNULL(es.PostingMode, 'BATCH') <> 'SINGLE'
                 AND l.AdvanceApplied > 0
                 AND NOT EXISTS (SELECT 1 FROM ExpenseMaster em
                                 WHERE em.SupplierID = @SupplierKey AND em.BatchReferenceID = l.BatchReferenceID
                                   AND em.InvoiceNo = l.InvoiceNo AND em.BranchCode = @HOBranch)
           )
            THROW 60522, 'Advance Applied on a multi-branch expense is booked on the head-office (888) ticket, but at least one selected invoice has no head-office share. Pay that invoice in cash, or apply the advance to another invoice.', 1;

        -- One variant per line: each selects a different mnemonic.
        IF EXISTS (
            SELECT 1 FROM #Lines
            WHERE (CASE WHEN OverPay        > 0 THEN 1 ELSE 0 END
                 + CASE WHEN OverPayExpense > 0 THEN 1 ELSE 0 END
                 + CASE WHEN AdvanceApplied > 0 THEN 1 ELSE 0 END) > 1
        )
        BEGIN
            DECLARE @MixMsg VARCHAR(400) = 'Invoice ' + (SELECT TOP 1 InvoiceNo FROM #Lines
                WHERE (CASE WHEN OverPay > 0 THEN 1 ELSE 0 END + CASE WHEN OverPayExpense > 0 THEN 1 ELSE 0 END
                     + CASE WHEN AdvanceApplied > 0 THEN 1 ELSE 0 END) > 1)
                + ': OverPay, OverPay (Expense), and Advance Applied cannot be combined on the same invoice - choose only one.';
            THROW 60512, @MixMsg, 1;
        END

        -- Same rule as AR: the excess attaches to exactly one invoice.
        IF (SELECT COUNT(*) FROM #Lines WHERE OverPay > 0 OR OverPayExpense > 0) > 1
            THROW 60513, 'OverPay / OverPay (Expense) must be assigned to only one invoice per voucher.', 1;

        -- Credit pool: serialize per supplier, then re-derive fresh (Known Bug
        -- Pattern #10 -- never trust the UI's Available Credit label).
        -- Only taken when this voucher draws credit; posting OverPay only
        -- ever increases the pool, so it can't make a concurrent draw unsafe.
        -- sp_CancelledChequesCS takes the same lock before reversing a
        -- voucher that created credit.
        DECLARE @TotalAdvanceApplied DECIMAL(18,2) = (SELECT ISNULL(SUM(AdvanceApplied), 0) FROM #Lines);
        IF @TotalAdvanceApplied > 0
        BEGIN
            DECLARE @LockResult INT, @LockResource NVARCHAR(255) = N'APCREDIT:' + @parmsupplierid;
            EXEC @LockResult = sp_getapplock
                @Resource    = @LockResource,
                @LockMode    = 'Exclusive',
                @LockOwner   = 'Transaction',
                @LockTimeout = 10000;

            IF @LockResult < 0
                THROW 60517, 'Could not acquire a lock for this supplier''s advance credit (another payment or reversal for the same supplier is in progress). Please try again.', 1;

            DECLARE @PriorAvailableCredit DECIMAL(18,2);
            SELECT @PriorAvailableCredit =
                ISNULL(SUM(CASE WHEN d.PaymentType = 'OVERPAY'        THEN d.Amount ELSE 0 END), 0)
              - ISNULL(SUM(CASE WHEN d.PaymentType = 'ADVANCEAPPLIED' THEN d.Amount ELSE 0 END), 0)
            FROM APPaymentDetails d
            WHERE d.SupplierID = @parmsupplierid
              AND d.PaymentType IN ('OVERPAY', 'ADVANCEAPPLIED')
              AND d.VoucherID <> @parmvoucherid
              AND NOT EXISTS (SELECT 1 FROM PaymentReversalAudit r
                              WHERE r.VoucherID = d.VoucherID AND r.SupplierID = d.SupplierID);

            IF @TotalAdvanceApplied > ISNULL(@PriorAvailableCredit, 0)
            BEGIN
                DECLARE @CreditMsg VARCHAR(400) = 'Advance Applied (' + CAST(@TotalAdvanceApplied AS VARCHAR(30))
                    + ') exceeds this supplier''s available advance credit (' + CAST(ISNULL(@PriorAvailableCredit, 0) AS VARCHAR(30)) + ').';
                THROW 60514, @CreditMsg, 1;
            END
        END

        DECLARE @maxrow INT, @row INT = 1;
        SELECT @maxrow = COUNT(*) FROM #Lines;

        IF @ocBranch IS NULL
            SELECT TOP 1 @ocBranch = BranchCode
            FROM ExpenseMaster
            WHERE SupplierID = @SupplierKey
              AND BatchReferenceID = (SELECT TOP 1 BatchReferenceID FROM #Lines ORDER BY RowNum)
            ORDER BY TRN_SEQ_NO;

        -- ============================================================
        -- PURCHASE
        -- ============================================================
        IF @parmpaymethod = 'PURCHASE'
        BEGIN
            DECLARE @pInvoiceNo VARCHAR(150), @pInvoiceDate DATE, @pSeqRef VARCHAR(50),
                    @pAmtPaid DECIMAL(18,2), @pEWT DECIMAL(18,2), @pDiscount DECIMAL(18,2),
                    @pRetAllow DECIMAL(18,2), @pVariance DECIMAL(18,2), @pGross DECIMAL(18,2),
                    @pFXLoss DECIMAL(18,2), @pFXGain DECIMAL(18,2), @pMnemonic VARCHAR(50),
                    @pParticulars VARCHAR(7000), @pBranchCode VARCHAR(5) = '888',
                    @pCurBalance DECIMAL(18,2),
                    -- NEW 2026-09-24
                    @pOverPay DECIMAL(18,2), @pOverPayExp DECIMAL(18,2), @pAdvApplied DECIMAL(18,2),
                    @pIsExtraMnemonic BIT, @pDr DECIMAL(18,2), @pCr DECIMAL(18,2);

            WHILE @row <= @maxrow
            BEGIN
                SELECT
                    @pInvoiceNo = InvoiceNo, @pInvoiceDate = InvoiceDate, @pSeqRef = SequenceReferenceNumber,
                    @pAmtPaid = AmountPaid, @pEWT = EWTAmount, @pDiscount = DiscountAmount,
                    @pRetAllow = OffsetAmount, @pVariance = Variance,
                    @pOverPay = OverPay, @pOverPayExp = OverPayExpense, @pAdvApplied = AdvanceApplied
                FROM #Lines WHERE RowNum = @row;

                -- CHANGED 2026-09-24: + AdvanceApplied - OverPay - OverPayExpense
                -- (all three are 0 for a plain line, so unchanged for them).
                SET @pGross = @pAmtPaid + @pEWT + @pDiscount + @pRetAllow + @pAdvApplied
                            - @pVariance - @pOverPay - @pOverPayExp;

                SET @pCurBalance = NULL;
                SELECT @pCurBalance = Balance FROM APAccounts WITH (UPDLOCK, ROWLOCK)
                WHERE SupplierID = @parmsupplierid AND InvoiceNo = @pInvoiceNo AND SequenceNo = @pSeqRef;

                IF @pCurBalance IS NULL
                BEGIN
                    DECLARE @PNotFoundMsg VARCHAR(400) = 'Invoice ' + ISNULL(@pInvoiceNo,'') + ' was not found in APAccounts (SequenceNo ' + ISNULL(@pSeqRef,'') + ').';
                    THROW 60501, @PNotFoundMsg, 1;
                END

                IF ROUND(@pGross - @pCurBalance, 2) > 0
                BEGIN
                    DECLARE @POverpayMsg VARCHAR(500) = 'Invoice ' + ISNULL(@pInvoiceNo,'') + ': the amount being settled (' + CAST(@pGross AS VARCHAR(30))
                        + ') exceeds its Balance (' + CAST(@pCurBalance AS VARCHAR(30)) + '). Lower Amount Paid, or put the excess in the OverPay / OverPay (Expense) column.';
                    THROW 60502, @POverpayMsg, 1;
                END

                -- NEW 2026-09-24: an overpayment is only an overpayment if the
                -- invoice is fully settled -- otherwise the "excess" is really
                -- an unpaid balance and must stay on the invoice.
                IF (@pOverPay > 0 OR @pOverPayExp > 0) AND ROUND(@pCurBalance - @pGross, 2) <> 0
                BEGIN
                    DECLARE @POverNotFullMsg VARCHAR(500) = 'Invoice ' + ISNULL(@pInvoiceNo,'') + ': OverPay is only allowed when the invoice is fully settled (Balance ' + CAST(@pCurBalance AS VARCHAR(30))
                        + ', settled ' + CAST(@pGross AS VARCHAR(30)) + ').';
                    THROW 60515, @POverNotFullMsg, 1;
                END

                SET @pFXLoss = CASE WHEN @pVariance > 0 THEN @pVariance ELSE 0 END;
                SET @pFXGain = CASE WHEN @pVariance < 0 THEN -@pVariance ELSE 0 END;
                SET @TotalNetCashForRecon += @pAmtPaid;

                SET @pIsExtraMnemonic = CASE WHEN @pOverPay > 0 OR @pOverPayExp > 0 OR @pAdvApplied > 0 THEN 1 ELSE 0 END;

                SET @pMnemonic = CASE
                    WHEN @pOverPay    > 0 THEN 'PV-AP-OVERPAY'
                    WHEN @pOverPayExp > 0 THEN 'PV-AP-OVERPAYEXP'
                    WHEN @pAdvApplied > 0 THEN 'PV-AP-ADVAPPLIED'
                    WHEN @pEWT>0 AND @pDiscount+@pRetAllow>0 THEN 'PV-AP-EWT-DISC'   -- [83] a return allowance is booked like a discount
                    WHEN @pEWT>0 THEN 'PV-AP-EWT'
                    WHEN @pDiscount+@pRetAllow>0 THEN 'PV-AP-DISC'   -- [83]
                    ELSE 'PV-AP' END;

                SET @pParticulars = 'PURCHASE PAYMENT | Supplier: '+@parmsupplierid
                    +' | Invoice: '+@pInvoiceNo+' | Ref: '+@parmrefno
                    +CASE WHEN LEN(ISNULL(@parmcheckremarks,''))>0 THEN ' | '+LEFT(@parmcheckremarks,200) ELSE '' END;

                DECLARE @Amounts dbo.tt_AmountBreakdown;
                DECLARE @Tokens  dbo.tt_TokenResolution;
                DECLARE @Flags   dbo.tt_ConditionFlags;
                DELETE FROM @Amounts; DELETE FROM @Tokens; DELETE FROM @Flags;
                INSERT @Tokens VALUES ('{BANK}', @parmglcode);

                IF @pIsExtraMnemonic = 0
                BEGIN
                    -- Unchanged from the prior version.
                    INSERT @Amounts VALUES ('GROSS',@pGross),('NET',@pAmtPaid),('EWT',@pEWT),
                                           ('MIRROR',@pDiscount+@pRetAllow),('DISCRETALLOW',@pDiscount+@pRetAllow),('VARIANCE_LOSS',@pFXLoss),('VARIANCE_GAIN',@pFXGain);   -- [83] DISCRETALLOW feeds the fixed discount legs
                    INSERT @Flags VALUES
                        ('HasEWT', CASE WHEN @pEWT>0 THEN 1 ELSE 0 END),
                        ('HasDiscount', CASE WHEN @pDiscount+@pRetAllow>0 THEN 1 ELSE 0 END),   -- [83]
                        ('HasFXLoss', CASE WHEN @pFXLoss>0 THEN 1 ELSE 0 END),
                        ('HasFXGain', CASE WHEN @pFXGain>0 THEN 1 ELSE 0 END);
                END
                ELSE
                BEGIN
                    -- NEW 2026-09-24: every AmountType the new mnemonics use is
                    -- supplied explicitly -- sp_PostCompoundTicket silently
                    -- substitutes GROSS for any AmountType it can't find.
                    INSERT @Amounts VALUES
                        ('GROSS', @pGross), ('NET', @pAmtPaid), ('EWT', @pEWT),
                        ('DISCRETALLOW', @pDiscount + @pRetAllow),
                        ('VARIANCE_LOSS', @pFXLoss), ('VARIANCE_GAIN', @pFXGain),
                        ('OVERPAY', @pOverPay), ('OVERPAYEXPENSE', @pOverPayExp),
                        ('ADVANCEAPPLIED', @pAdvApplied);
                    INSERT @Flags VALUES
                        ('HasNetCash',        CASE WHEN @pAmtPaid > 0 THEN 1 ELSE 0 END),
                        ('HasEWT',            CASE WHEN @pEWT > 0 THEN 1 ELSE 0 END),
                        ('HasDiscount',       CASE WHEN @pDiscount + @pRetAllow > 0 THEN 1 ELSE 0 END),
                        ('HasFXLoss',         CASE WHEN @pFXLoss > 0 THEN 1 ELSE 0 END),
                        ('HasFXGain',         CASE WHEN @pFXGain > 0 THEN 1 ELSE 0 END),
                        ('HasOverpay',        CASE WHEN @pOverPay > 0 THEN 1 ELSE 0 END),
                        ('HasOverpayExpense', CASE WHEN @pOverPayExp > 0 THEN 1 ELSE 0 END),
                        ('HasAdvanceApplied', CASE WHEN @pAdvApplied > 0 THEN 1 ELSE 0 END);

                    -- Pre-validate the ticket before posting: every active leg's
                    -- AmountType must be supplied, and DR must equal CR.
                    IF EXISTS (
                        SELECT 1 FROM JournalEntryMapping M
                        WHERE M.Mnemonic = @pMnemonic AND M.IsActive = 1
                          AND NOT EXISTS (SELECT 1 FROM @Amounts A WHERE A.AmountType = M.AmountType)
                    )
                        THROW 60518, 'JournalEntryMapping for the overpayment/advance mnemonic uses an AmountType this procedure does not supply.', 1;

                    SELECT
                        @pDr = ISNULL(SUM(CASE WHEN M.DebitCredit = 'D' THEN A.Amount ELSE 0 END), 0),
                        @pCr = ISNULL(SUM(CASE WHEN M.DebitCredit = 'C' THEN A.Amount ELSE 0 END), 0)
                    FROM JournalEntryMapping M
                    JOIN @Amounts A ON A.AmountType = M.AmountType
                    WHERE M.Mnemonic = @pMnemonic
                      AND M.IsActive = 1
                      AND (M.BranchCode IS NULL OR M.BranchCode = @pBranchCode)
                      AND (M.IsConditional = 0
                           OR EXISTS (SELECT 1 FROM @Flags F WHERE F.FlagName = M.ConditionFlag AND F.FlagValue = 1));

                    IF @pDr <> @pCr
                    BEGIN
                        DECLARE @PImbalMsg VARCHAR(400) = 'Invoice ' + ISNULL(@pInvoiceNo,'') + ': ' + @pMnemonic + ' ticket would not balance (Debit '
                            + CAST(@pDr AS VARCHAR(30)) + ', Credit ' + CAST(@pCr AS VARCHAR(30)) + ').';
                        THROW 60518, @PImbalMsg, 1;
                    END
                END

                EXEC [dbo].[sp_PostCompoundTicket]
                    @Mnemonic=@pMnemonic, @TicketDate=@parmcheckdate,
                    @BranchCode=@pBranchCode, @ReferenceNumber=@parmrefno,
                    @ReferenceKey=@parmvoucherid, @Particulars=@pParticulars,
                    @Owner=@parmsupplierid, @PreparedBy=@parmpreparedby,
                    @Status='POSTED', @Amounts=@Amounts, @Tokens=@Tokens,
                    @Flags=@Flags, @LedgerType='SUPPLIER',
                    @LedgerEntityID=@parmsupplierid,
                    @LedgerInvoiceNo=@pInvoiceNo, @LedgerBatchRef=NULL,
                    @LedgerSeqRef=@pSeqRef, @LedgerSide='D';   -- 2026-10-13f [71]: the payment row is a debit

                IF @pAmtPaid > 0
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @pBranchCode,
                            @pInvoiceNo, @pInvoiceDate, @pAmtPaid, 'INVOICE PAYMENT',
                            @parmpaymethod, @parmvouchertype, '', @parmglcode, @parmglcode,
                            @pSeqRef, NULL);

                IF @pEWT > 0
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @pBranchCode,
                            @pInvoiceNo, @pInvoiceDate, @pEWT, 'EWT',
                            @parmpaymethod, @parmvouchertype, '', @parmglcode, @parmglcode,
                            @pSeqRef, NULL);

                IF @pDiscount > 0
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @pBranchCode,
                            @pInvoiceNo, @pInvoiceDate, @pDiscount, 'DISCOUNT',
                            @parmpaymethod, @parmvouchertype, '', @parmglcode, @parmglcode,
                            @pSeqRef, NULL);

                IF @pRetAllow > 0
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @pBranchCode,
                            @pInvoiceNo, @pInvoiceDate, @pRetAllow, 'RETURNALLOWANCES',
                            @parmpaymethod, @parmvouchertype, '', @parmglcode, @parmglcode,
                            @pSeqRef, NULL);

                IF @pVariance <> 0
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @pBranchCode,
                            @pInvoiceNo, @pInvoiceDate, @pVariance, 'VARIANCE',
                            @parmpaymethod, @parmvouchertype, '', @parmglcode, @parmglcode,
                            @pSeqRef, NULL);

                -- NEW 2026-09-24: OVERPAY / OVERPAYEXPENSE / ADVANCEAPPLIED rows --
                -- the credit pool (sp_GetSupplierAvailableCredit) and the
                -- PURCHASE reversal in sp_CancelledChequesCS both read these.
                IF @pOverPay > 0
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @pBranchCode,
                            @pInvoiceNo, @pInvoiceDate, @pOverPay, 'OVERPAY',
                            @parmpaymethod, @parmvouchertype, '', @parmglcode, @parmglcode,
                            @pSeqRef, NULL);

                IF @pOverPayExp > 0
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @pBranchCode,
                            @pInvoiceNo, @pInvoiceDate, @pOverPayExp, 'OVERPAYEXPENSE',
                            @parmpaymethod, @parmvouchertype, '', @parmglcode, @parmglcode,
                            @pSeqRef, NULL);

                IF @pAdvApplied > 0
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @pBranchCode,
                            @pInvoiceNo, @pInvoiceDate, @pAdvApplied, 'ADVANCEAPPLIED',
                            @parmpaymethod, @parmvouchertype, '', @parmglcode, @parmglcode,
                            @pSeqRef, NULL);

                UPDATE APACCOUNTS
                SET Balance = @pCurBalance - @pGross,
                    PayStatus = CASE WHEN (@pCurBalance - @pGross) <= 0 THEN 'FULLYPAID' ELSE 'PARTIAL' END
                WHERE SupplierID = @parmsupplierid AND InvoiceNo = @pInvoiceNo AND SequenceNo = @pSeqRef;

                SET @row += 1;
            END;

            -- CHANGED 2026-09-24: skip the OC when no cash actually left the
            -- bank (every line settled entirely by Advance Applied / EWT /
            -- Discount) instead of posting a 0.00 outstanding cheque.
            IF @TotalNetCashForRecon <> 0 AND ISNULL(@SkipVoucherWrap, 0) = 0   -- [97]
            BEGIN
                DECLARE @Remarks VARCHAR(500);
                SET @Remarks = 'Auto-OC | Ref: ' + ISNULL(@parmrefno, '');

                EXEC sp_Payment_PostBankReconEntry
                     @ItemType      = 'OC',
                     @BranchCode    = @ocBranch,
                     @AccountCode   = @parmglcode,
                     @PeriodEnd     = @ocPeriodEnd,
                     @ReferenceNo   = @parmvoucherid,
                     @ItemDate      = @parmcheckdate,
                     @Payee         = @parmsuppliername,
                     @Amount        = @TotalNetCashForRecon,
                     @Remarks       = @Remarks,
                     @SourceModule  = 'AP-PAYMENT',
                     @SourceRef     = @parmrefno,
                     @CreatedBy     = @parmpreparedby;
            END

        END

        -- ============================================================
        -- EXPENSE - SINGLE and BATCH
        -- 2026-09-24c: SINGLE accepts OverPay / OverPayExpense /
        -- AdvanceApplied (same rules as PURCHASE).
        -- 2026-09-25: BATCH / MULTI-MANUAL accept them too, booked on the
        -- head-office (888) ticket - see the BATCH section below.
        -- ============================================================
        ELSE
        BEGIN
            -- GL accounts for the extras come from the same mapping rows the
            -- PURCHASE mnemonics use, so both modes always hit the same
            -- accounts (101030208 / 60339 today) - never hardcoded here.
            DECLARE @xOverPayAcct VARCHAR(50), @xOverPayExpAcct VARCHAR(50), @xAdvanceAcct VARCHAR(50);
            -- 2026-09-25 (sp-reviewer): the multi-branch settlement payable (was the literal
            -- '20103' in three places below) declared once.
            DECLARE @eBatchPayableAcct VARCHAR(20) = '20103';
            SELECT @xOverPayAcct    = AccountCode FROM JournalEntryMapping WHERE Mnemonic = 'PV-AP-OVERPAY'    AND AmountType = 'OVERPAY'        AND IsActive = 1;
            SELECT @xOverPayExpAcct = AccountCode FROM JournalEntryMapping WHERE Mnemonic = 'PV-AP-OVERPAYEXP' AND AmountType = 'OVERPAYEXPENSE' AND IsActive = 1;
            SELECT @xAdvanceAcct    = AccountCode FROM JournalEntryMapping WHERE Mnemonic = 'PV-AP-ADVAPPLIED' AND AmountType = 'ADVANCEAPPLIED' AND IsActive = 1;

            SET @row = 1;
            WHILE @row <= @maxrow
            BEGIN
                DECLARE @eInvoiceNo VARCHAR(150), @eInvoiceDate DATE, @eBatchRef BIGINT,
                        @eDesc VARCHAR(300), @eDiscRemain DECIMAL(18,2), @eOffsetRemain DECIMAL(18,2),
                        @eVariance DECIMAL(18,2), @eDiscAcct VARCHAR(20), @eTotalAmt DECIMAL(18,2),
                        @ePostingMode VARCHAR(10), @ePayableAcct VARCHAR(20), @eCurBalance DECIMAL(18,2),
                        @eNewBalance DECIMAL(18,2), @eGross DECIMAL(18,2), @eBranch VARCHAR(5),
                        @eParticulars VARCHAR(7000), @eTransID INT;

                SELECT
                    @eInvoiceNo = InvoiceNo, @eInvoiceDate = InvoiceDate, @eBatchRef = BatchReferenceID,
                    @eTotalAmt = ActualCost, @eDesc = Description,
                    @eDiscRemain = DiscountAmount, @eOffsetRemain = OffsetAmount,
                    @eVariance = Variance, @eDiscAcct = DiscountAccountCode
                FROM #Lines WHERE RowNum = @row;

                SELECT @ePostingMode = ISNULL(PostingMode, 'BATCH'), @ePayableAcct = PayableAccountCode
                FROM ExpenseSummary
                WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo;

                SET @eCurBalance = NULL;
                SELECT @eCurBalance = ISNULL(Balance, ISNULL(Amount, 0))
                FROM ExpenseSummary WITH (UPDLOCK, ROWLOCK)
                WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo;

                IF @eCurBalance IS NULL
                BEGIN
                    DECLARE @ENotFoundMsg VARCHAR(400) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ' was not found in ExpenseSummary (BatchReferenceID ' + CAST(ISNULL(@eBatchRef,0) AS VARCHAR(30)) + ').';
                    THROW 60508, @ENotFoundMsg, 1;
                END

                -- [105] 2026-10-17: a loan payable settles in Vouchering Telegraphic (sp_PostVoucherManual, DR the loan account);
                --       here it would fall into the BATCH path and debit the expense AP account
                IF @ePostingMode = 'LOAN'
                    THROW 60540, 'This invoice is a loan (Loan Revaluation): pay it in Vouchering Telegraphic, which debits the loan account. Nothing was posted.', 1;

                IF @ePostingMode = 'SINGLE'
                BEGIN
                    IF @ePayableAcct IS NULL
                        THROW 56002, 'SINGLE-mode invoice has no PayableAccountCode recorded.', 1;

                    DECLARE @sNetCash DECIMAL(18,2), @sEWT DECIMAL(18,2), @sDisc DECIMAL(18,2),
                            @sOffset DECIMAL(18,2), @sFXLoss DECIMAL(18,2), @sFXGain DECIMAL(18,2),
                            -- NEW 2026-09-24c
                            @sOverPay DECIMAL(18,2), @sOverPayExp DECIMAL(18,2), @sAdvApplied DECIMAL(18,2);

                    -- CHANGED 2026-09-24c: Gross (what settles the invoice) =
                    -- cash + EWT + Discount + Offset + AdvanceApplied
                    -- - OverPay - OverPayExpense, same as PURCHASE's @pGross.
                    -- All three extras are 0 on a plain line -> unchanged.
                    SELECT
                        @eGross   = AmountPaid + ISNULL(EWTAmount,0) + ISNULL(DiscountAmount,0) + ISNULL(OffsetAmount,0)
                                  + AdvanceApplied - OverPay - OverPayExpense,
                        @sNetCash = AmountPaid,
                        @sEWT     = ISNULL(EWTAmount,0),
                        @sDisc    = ISNULL(DiscountAmount,0),
                        @sOffset  = ISNULL(OffsetAmount,0),
                        @sOverPay    = OverPay,
                        @sOverPayExp = OverPayExpense,
                        @sAdvApplied = AdvanceApplied
                    FROM #Lines WHERE RowNum = @row;

                    IF ROUND(@eGross - @eCurBalance, 2) > 0
                    BEGIN
                        DECLARE @EOverpayMsgS VARCHAR(500) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': the amount being settled (' + CAST(@eGross AS VARCHAR(30))
                            + ') exceeds its Balance (' + CAST(@eCurBalance AS VARCHAR(30)) + '). Lower Amount Paid, or put the excess in the OverPay / OverPay (Expense) column.';
                        THROW 60503, @EOverpayMsgS, 1;
                    END

                    -- NEW 2026-09-24c: same rule as PURCHASE (THROW 60515) -
                    -- an overpayment only exists once the invoice is fully settled.
                    IF (@sOverPay > 0 OR @sOverPayExp > 0) AND ROUND(@eCurBalance - @eGross, 2) <> 0
                    BEGIN
                        DECLARE @EOverNotFullMsg VARCHAR(500) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': OverPay is only allowed when the invoice is fully settled (Balance ' + CAST(@eCurBalance AS VARCHAR(30))
                            + ', settled ' + CAST(@eGross AS VARCHAR(30)) + ').';
                        THROW 60515, @EOverNotFullMsg, 1;
                    END

                    IF (@sOverPay > 0 AND @xOverPayAcct IS NULL)
                       OR (@sOverPayExp > 0 AND @xOverPayExpAcct IS NULL)
                       OR (@sAdvApplied > 0 AND @xAdvanceAcct IS NULL)
                        THROW 60518, 'JournalEntryMapping for supplier overpayment/advance (PV-AP-OVERPAY / PV-AP-OVERPAYEXP / PV-AP-ADVAPPLIED) is missing or inactive.', 1;

                    SET @sFXLoss = 0;
                    SET @sFXGain = 0;
                    SET @TotalNetCashForRecon += @sNetCash;

                    -- NEW 2026-09-24c: pre-validate the settlement ticket balances
                    -- (sp_Payment_PostSettlementTicket itself never checks DR = CR).
                    -- DR payable Gross + DR advances OverPay + DR expense OverPayExp
                    --   = CR bank cash + EWT + Discount + Offset + CR advances AdvApplied
                    IF @sOverPay > 0 OR @sOverPayExp > 0 OR @sAdvApplied > 0
                    BEGIN
                        DECLARE @sDr DECIMAL(18,2) = @eGross + @sOverPay + @sOverPayExp + @sFXLoss,
                                @sCr DECIMAL(18,2) = @sNetCash + @sEWT + @sDisc + @sOffset + @sAdvApplied + @sFXGain;
                        IF @sDr <> @sCr
                        BEGIN
                            DECLARE @SImbalMsg VARCHAR(400) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': SINGLE-PAY ticket would not balance (Debit '
                                + CAST(@sDr AS VARCHAR(30)) + ', Credit ' + CAST(@sCr AS VARCHAR(30)) + ').';
                            THROW 60518, @SImbalMsg, 1;
                        END
                    END

                    SET @eNewBalance = ROUND(CASE WHEN @eCurBalance - @eGross < 0 THEN 0 ELSE @eCurBalance - @eGross END, 2);

                    -- CHANGED 2026-09-24c: AmountPaid gets the part of Gross that
                    -- isn't a withholding (cash applied + advance applied, net of
                    -- any excess), so AmountPaid + EWT/Discount/Offset withheld
                    -- still equals what was settled. Identical to the old
                    -- "+ @sNetCash" when all three extras are 0.
                    UPDATE ExpenseSummary
                    SET Balance = @eNewBalance,
                        AmountPaid = ISNULL(AmountPaid,0) + (@sNetCash + @sAdvApplied - @sOverPay - @sOverPayExp),
                        EWTWithheld = ISNULL(EWTWithheld,0) + @sEWT,
                        DiscountWithheld = ISNULL(DiscountWithheld,0) + @sDisc,
                        OffsetWithheld = ISNULL(OffsetWithheld,0) + @sOffset,
                        Status = CASE WHEN @eNewBalance <= 0 THEN 'FULLYPAID' ELSE 'PARTIAL' END,
                        UpdatedBy = @parmpreparedby, DateTimeUpdated = GETDATE()
                    WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo;

                    IF @eNewBalance <= 0
                        UPDATE ExpenseMaster SET Balance = 0, AmountPaid = Amount, Status = 'FULLYPAID'
                        WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo;

                    SELECT TOP 1 @eBranch = BranchCode FROM ExpenseMaster
                    WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo;

                    SET @eParticulars = 'EXPENSE PAYMENT (SINGLE) | Supplier: '+@parmsupplierid
                        +' | Ref: '+@parmrefno+' | '+LEFT(ISNULL(@eDesc,''),500)
                        +CASE WHEN LEN(ISNULL(@parmcheckremarks,''))>0 THEN ' | '+LEFT(@parmcheckremarks,200) ELSE '' END;

                    EXEC sp_Payment_PostSettlementTicket
                        @TicketDate=@parmcheckdate, @BranchCode=@eBranch,
                        @ReferenceKey=@parmvoucherid, @ReferenceNumber=@parmrefno,
                        @Owner=@parmsuppliername, @Particulars=@eParticulars,
                        @PreparedBy=@parmpreparedby, @Mnemonic='SINGLE-PAY',
                        @PayableAccountCode=@ePayableAcct, @GrossPayable=@eGross,
                        @BankAccountCode=@parmglcode, @NetCash=@sNetCash,
                        @EWTAmount=@sEWT, @DiscountAmount=@sDisc, @DiscountAccountCode=@eDiscAcct,
                        @OffsetAmount=@sOffset, @FXLoss=@sFXLoss, @FXGain=@sFXGain,
                        -- NEW 2026-09-24c (all default 0 in the helper; BATCH never passes them)
                        @OverPay=@sOverPay, @OverPayAccountCode=@xOverPayAcct,
                        @OverPayExpense=@sOverPayExp, @OverPayExpenseAccountCode=@xOverPayExpAcct,
                        @AdvanceApplied=@sAdvApplied, @AdvanceAccountCode=@xAdvanceAcct,
                        @TicketNumber=@TicketNumber OUTPUT;

                    -- 'EXPENSE PAYMENT' stays = Gross (what settled the invoice);
                    -- sp_CancelledChequesCS restores Balance from these rows only.
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @eBranch,
                            @eInvoiceNo, @eInvoiceDate, @eGross, 'EXPENSE PAYMENT',
                            @parmpaymethod, @parmvouchertype, @TicketNumber,
                            @ePayableAcct, @parmglcode, CAST(@eBatchRef AS VARCHAR(50)), @eBatchRef);

                    -- NEW 2026-09-24c: extras rows feed the shared supplier credit
                    -- pool (sp_GetSupplierAvailableCredit / V2 / reversal guard),
                    -- which counts PURCHASE and EXPENSE rows alike.
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    -- Debit/Credit GL codes mirror the ticket legs (sp-reviewer 24c):
                    --   OVERPAY        DR advances   / CR bank
                    --   OVERPAYEXPENSE DR expense    / CR bank
                    --   ADVANCEAPPLIED DR payable    / CR advances
                    SELECT @parmvoucherid, @parmsupplierid, @parmrefno, @eBranch,
                           @eInvoiceNo, @eInvoiceDate, x.Amount, x.PaymentType,
                           @parmpaymethod, @parmvouchertype, @TicketNumber,
                           x.DebitGL, x.CreditGL, CAST(@eBatchRef AS VARCHAR(50)), @eBatchRef
                    FROM (VALUES ('OVERPAY',        @sOverPay,    @xOverPayAcct,    @parmglcode),
                                 ('OVERPAYEXPENSE', @sOverPayExp, @xOverPayExpAcct, @parmglcode),
                                 ('ADVANCEAPPLIED', @sAdvApplied, @ePayableAcct,    @xAdvanceAcct)) x (PaymentType, Amount, DebitGL, CreditGL)
                    WHERE x.Amount > 0;

                    SET @eTransID = dbo.func_getLastID(@SupplierKey);
                    INSERT INTO [dbo].[SupplierLedger]
                        (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate,
                         Description, TransCode, TransactionDate, ReferenceNumber,
                         ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit,
                         EndingBalance, TransactedBy, ApprovedBy, TotalAmount,
                         PaymentType, ErrorCorrectTag, TicketReference, BatchReferenceID)
                    VALUES (@eTransID, @SupplierKey, @parmsupplierid, @parmcheckdate,
                            LEFT(ISNULL(@parmcheckremarks,'EXPENSE PAYMENT'),490),
                            'SNGLE-PAY', @parmcheckdate, @parmrefno,
                            CAST(@eBatchRef AS VARCHAR(40))+'-'+@eBranch,
                            @eInvoiceNo, 0, @eGross, 0, @eGross, @parmpreparedby, '*', @eGross,
                            CASE WHEN @eNewBalance<=0 THEN 'FULLYPAID' ELSE 'PARTIAL' END,
                            0, @TicketNumber, @eBatchRef);

                    SET @row += 1;
                    CONTINUE;
                END;

                -- -- BATCH mode --------------------------------------
                -- (every non-SINGLE expense invoice: MULTI-MANUAL / BATCH / NULL)
                --
                -- NEW 2026-09-25: OverPay / OverPayExpense / AdvanceApplied.
                -- Confirmed with user: the whole amount is booked on the HEAD
                -- OFFICE (888) branch's settlement ticket, not prorated.
                --   * Invoice has an 888 share: the extras ride on the 888
                --     ticket (its cash = its share - withholdings - advance
                --     + overpay). Advance larger than 888's share -> 60522.
                --   * No 888 share: OverPay / OverPayExpense get a separate
                --     888 ticket (DR advances-or-expense / CR bank, balanced
                --     on its own); AdvanceApplied is rejected (60522) - there
                --     is no 888 payable for it to settle.
                -- Invoices with none of the three post exactly as before.
                DECLARE @bOverPay DECIMAL(18,2), @bOverPayExp DECIMAL(18,2), @bAdvApplied DECIMAL(18,2),
                        @bHOBranch VARCHAR(5) = @HOBranch,   -- declared once at the top of the proc
                        @bHasHO BIT;

                SELECT @bOverPay = OverPay, @bOverPayExp = OverPayExpense, @bAdvApplied = AdvanceApplied
                FROM #Lines WHERE RowNum = @row;

                IF (@bOverPay > 0 AND @xOverPayAcct IS NULL)
                   OR (@bOverPayExp > 0 AND @xOverPayExpAcct IS NULL)
                   OR (@bAdvApplied > 0 AND @xAdvanceAcct IS NULL)
                    THROW 60518, 'JournalEntryMapping for supplier overpayment/advance (PV-AP-OVERPAY / PV-AP-OVERPAYEXP / PV-AP-ADVAPPLIED) is missing or inactive.', 1;

                DECLARE @eEWTAlreadyPosted DECIMAL(18,2), @eEWTToWithhold DECIMAL(18,2),
                        @eEWTFromTVP DECIMAL(18,2), @eEWTRemain DECIMAL(18,2), @eNetLiability DECIMAL(18,2);

                SELECT
                    @eEWTAlreadyPosted = ISNULL(SUM(CASE WHEN IsEWTPostedAtAccrual = 1 THEN EWTAmount ELSE 0 END), 0),
                    @eEWTToWithhold    = ISNULL(SUM(CASE WHEN IsEWTPostedAtAccrual = 0 THEN EWTAmount ELSE 0 END), 0)
                FROM ExpenseMaster
                WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo;

                SELECT @eEWTFromTVP = ISNULL(EWTAmount, 0) FROM #Lines WHERE RowNum = @row;

                SET @eEWTRemain = CASE WHEN @eEWTFromTVP > 0 THEN @eEWTFromTVP ELSE @eEWTToWithhold END;

                -- [87] H5: the invoice amount is the stored one; a screen whose amount differs is stale (the expense was edited)
                DECLARE @eStoredAmt DECIMAL(18,2);
                SELECT @eStoredAmt = ISNULL(Amount, 0) FROM ExpenseSummary
                WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo;
                IF ABS(ISNULL(@eTotalAmt, 0) - @eStoredAmt) > 0.005
                BEGIN
                    DECLARE @EStaleAmtMsg VARCHAR(400) = 'Invoice ' + ISNULL(@eInvoiceNo, '') + ': the screen shows ' + CAST(ISNULL(@eTotalAmt, 0) AS VARCHAR(30))
                        + ' but the expense is now ' + CAST(@eStoredAmt AS VARCHAR(30)) + ' (it was edited since the list was loaded). Reload the supplier and try again.';
                    THROW 60525, @EStaleAmtMsg, 1;
                END
                SET @eNetLiability = @eStoredAmt - @eEWTAlreadyPosted;

                -- CHANGED 2026-09-25: + AdvanceApplied - OverPay - OverPayExpense,
                -- same as PURCHASE / SINGLE (all 0 on a plain line -> unchanged).
                SELECT @eGross = AmountPaid + @eEWTRemain + DiscountAmount + OffsetAmount - Variance
                               + AdvanceApplied - OverPay - OverPayExpense
                FROM #Lines WHERE RowNum = @row;

                IF ROUND(@eGross - @eCurBalance, 2) > 0
                BEGIN
                    DECLARE @EOverpayMsgB VARCHAR(500) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': the amount being settled (' + CAST(@eGross AS VARCHAR(30))
                        + ') exceeds its Balance (' + CAST(@eCurBalance AS VARCHAR(30)) + '). Lower Amount Paid, or put the excess in the OverPay / OverPay (Expense) column.';
                    THROW 60504, @EOverpayMsgB, 1;
                END

                -- NEW 2026-09-25: same rule as PURCHASE / SINGLE (60515).
                IF (@bOverPay > 0 OR @bOverPayExp > 0) AND ROUND(@eCurBalance - @eGross, 2) <> 0
                BEGIN
                    DECLARE @EOverNotFullMsgB VARCHAR(500) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': OverPay is only allowed when the invoice is fully settled (Balance ' + CAST(@eCurBalance AS VARCHAR(30))
                        + ', settled ' + CAST(@eGross AS VARCHAR(30)) + ').';
                    THROW 60515, @EOverNotFullMsgB, 1;
                END

                -- NEW 2026-09-25: HO share present? Checked before any write
                -- for this invoice so a rejection leaves nothing half-posted.
                SET @bHasHO = CASE WHEN EXISTS (
                    SELECT 1 FROM ExpenseMaster
                    WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo
                      AND BranchCode = @bHOBranch) THEN 1 ELSE 0 END;

                IF @bAdvApplied > 0 AND @bHasHO = 0
                BEGIN
                    DECLARE @ENoHOAdvMsg VARCHAR(500) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ' has no head-office (' + @bHOBranch
                        + ') share - Advance Applied on a multi-branch expense is booked on the head-office ticket, so it can''t be applied to this invoice. Pay it in cash, or apply the advance to another invoice.';
                    THROW 60522, @ENoHOAdvMsg, 1;
                END

                SET @eNewBalance = ROUND(CASE WHEN @eCurBalance - @eGross < 0 THEN 0 ELSE @eCurBalance - @eGross END, 2);

                UPDATE ExpenseSummary SET
                    Balance = @eNewBalance,
                    AmountPaid = ISNULL(AmountPaid,0) + (@eGross - @eEWTRemain - @eDiscRemain - @eOffsetRemain),
                    EWTWithheld = ISNULL(EWTWithheld,0) + @eEWTRemain,
                    DiscountWithheld = ISNULL(DiscountWithheld,0) + @eDiscRemain,
                    OffsetWithheld = ISNULL(OffsetWithheld,0) + @eOffsetRemain,
                    Status = CASE WHEN @eNewBalance<=0 THEN 'FULLYPAID' ELSE 'PARTIAL' END,
                    UpdatedBy = @parmpreparedby, DateTimeUpdated = GETDATE()
                WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo;

                IF OBJECT_ID('tempdb..#BranchTotals') IS NOT NULL DROP TABLE #BranchTotals;

                SELECT
                    ROW_NUMBER() OVER (ORDER BY BranchCode) AS RowNum, BranchCode,
                    SUM(Amount) AS BranchTotalAmt,
                    SUM(Amount) - SUM(CASE WHEN IsEWTPostedAtAccrual = 1 THEN ISNULL(EWTAmount,0) ELSE 0 END) AS BranchNetLiability,
                    ROUND(((SUM(Amount) - SUM(CASE WHEN IsEWTPostedAtAccrual = 1 THEN ISNULL(EWTAmount,0) ELSE 0 END)) / NULLIF(@eNetLiability, 0)) * @eEWTRemain, 2) AS BranchEWT,
                    ROUND(((SUM(Amount) - SUM(CASE WHEN IsEWTPostedAtAccrual = 1 THEN ISNULL(EWTAmount,0) ELSE 0 END)) / NULLIF(@eNetLiability, 0)) * @eDiscRemain, 2) AS BranchDisc,
                    ROUND(((SUM(Amount) - SUM(CASE WHEN IsEWTPostedAtAccrual = 1 THEN ISNULL(EWTAmount,0) ELSE 0 END)) / NULLIF(@eNetLiability, 0)) * @eOffsetRemain, 2) AS BranchOffset
                INTO #BranchTotals
                FROM ExpenseMaster
                WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo
                GROUP BY BranchCode;

                DECLARE @brrow INT = 1, @brmaxrow INT;
                SELECT @brmaxrow = COUNT(*) FROM #BranchTotals;

                DECLARE @ewtRunning DECIMAL(18,2)=0, @discRunning DECIMAL(18,2)=0,
                        @offRunning DECIMAL(18,2)=0, @varRunning DECIMAL(18,2)=0;
                -- 2026-10-12d: the rounded branch shares given out so far (the last branch takes the rest)
                DECLARE @grossRunning DECIMAL(18,2) = 0;
                SET @grossRunning = 0;
                IF ISNULL(@eNetLiability, 0) = 0
                BEGIN
                    DECLARE @ENoLiabMsg VARCHAR(400) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': its branch lines add up to no payable amount, so the payment can''t be split across branches. Check the expense entry.';
                    THROW 60523, @ENoLiabMsg, 1;
                END

                WHILE @brrow <= @brmaxrow
                BEGIN
                    DECLARE @brBranch VARCHAR(5), @brNetLiability DECIMAL(18,2), @brEWT DECIMAL(18,2),
                            @brDisc DECIMAL(18,2), @brOffset DECIMAL(18,2), @brVariance DECIMAL(18,2),
                            @brFXLoss DECIMAL(18,2), @brFXGain DECIMAL(18,2), @brGross DECIMAL(18,2),
                            @brNetCash DECIMAL(18,2), @brMnemonic VARCHAR(50), @allDescNames VARCHAR(2000);

                    SELECT @brBranch=BranchCode, @brNetLiability=BranchNetLiability,
                           @brEWT=BranchEWT, @brDisc=BranchDisc, @brOffset=BranchOffset
                    FROM #BranchTotals WHERE RowNum = @brrow;

                    IF @brrow = @brmaxrow
                    BEGIN
                        SET @brEWT = @eEWTRemain - @ewtRunning;
                        SET @brDisc = @eDiscRemain - @discRunning;
                        SET @brOffset = @eOffsetRemain - @offRunning;
                    END
                    ELSE
                    BEGIN
                        SET @ewtRunning += @brEWT; SET @discRunning += @brDisc;
                        SET @offRunning += @brOffset;
                    END

                    SET @brFXLoss = 0;
                    SET @brFXGain = 0;

                    SET @brGross = ROUND((@brNetLiability / NULLIF(@eNetLiability, 0)) * @eGross, 2);
                    -- 2026-10-12d: the last branch = amount settled - the ROUNDED shares already given out. It used to
                    -- re-add the shares over the #BranchTotals SUM column, whose ratio SQL Server cuts to 6 decimals,
                    -- so the legs could add up to more than the amount settled (voucher 688: +0.06 on 888).
                    IF @brrow = @brmaxrow
                    BEGIN
                        SET @brGross = @eGross - @grossRunning;
                        IF @brGross < 0
                        BEGIN
                            DECLARE @ENegShareMsg VARCHAR(400) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': the branch shares come to more than the amount being settled (branch ' + @brBranch + ' would get ' + CAST(@brGross AS VARCHAR(30)) + '). Its branch lines don''t add up to the invoice; check the expense entry.';
                            THROW 60524, @ENegShareMsg, 1;
                        END
                    END
                    ELSE
                        SET @grossRunning += ISNULL(@brGross, 0);

                    -- NEW 2026-09-25: extras only on the head-office branch ticket.
                    DECLARE @brOverPay DECIMAL(18,2), @brOverPayExp DECIMAL(18,2), @brAdv DECIMAL(18,2), @brRawNet DECIMAL(18,2);
                    SET @brOverPay    = CASE WHEN @brBranch = @bHOBranch THEN @bOverPay    ELSE 0 END;
                    SET @brOverPayExp = CASE WHEN @brBranch = @bHOBranch THEN @bOverPayExp ELSE 0 END;
                    SET @brAdv        = CASE WHEN @brBranch = @bHOBranch THEN @bAdvApplied ELSE 0 END;

                    SET @brRawNet = @brGross - @brEWT - @brDisc - @brOffset - @brAdv + @brOverPay + @brOverPayExp + @brFXLoss - @brFXGain;

                    IF @brAdv > 0 AND ROUND(@brRawNet, 2) < 0
                    BEGIN
                        DECLARE @EHOAdvTooBigMsg VARCHAR(500) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': Advance Applied (' + CAST(@brAdv AS VARCHAR(30))
                            + ') is more than the head-office share being paid (' + CAST(@brGross - @brEWT - @brDisc - @brOffset AS VARCHAR(30))
                            + '). Lower Advance Applied to at most that amount.';
                        THROW 60522, @EHOAdvTooBigMsg, 1;
                    END

                    -- Unchanged floor-at-0 for ordinary branches (no extras -> identical to before).
                    SET @brNetCash = ROUND(CASE WHEN @brRawNet < 0 THEN 0 ELSE @brRawNet END, 2);
                    SET @TotalNetCashForRecon += @brNetCash;

                    -- The settlement helper never checks DR = CR; do it here for
                    -- the ticket that carries extras, so a rounding cent or the
                    -- floor above can never post an unbalanced ticket silently.
                    IF @brOverPay > 0 OR @brOverPayExp > 0 OR @brAdv > 0
                    BEGIN
                        DECLARE @brDr DECIMAL(18,2), @brCr DECIMAL(18,2);
                        SET @brDr = ROUND(@brGross, 2) + @brOverPay + @brOverPayExp + @brFXLoss;
                        SET @brCr = @brNetCash + @brEWT + @brDisc + @brOffset + @brAdv + @brFXGain;
                        IF @brDr <> @brCr
                        BEGIN
                            DECLARE @BImbalMsg VARCHAR(400) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': head-office settlement ticket would not balance (Debit '
                                + CAST(@brDr AS VARCHAR(30)) + ', Credit ' + CAST(@brCr AS VARCHAR(30)) + ').';
                            THROW 60518, @BImbalMsg, 1;
                        END
                    END

                    SET @brMnemonic = CASE WHEN @brEWT > 0 THEN 'EXP-ACCRUAL-PAY-EWT' ELSE 'EXP-ACCRUAL-PAY' END;

                    IF @eNewBalance <= 0
                        UPDATE ExpenseMaster SET Balance=0, AmountPaid=Amount, Status='FULLYPAID'
                        WHERE SupplierID=@SupplierKey AND BatchReferenceID=@eBatchRef AND InvoiceNo=@eInvoiceNo AND BranchCode=@brBranch;
                    ELSE
                        UPDATE ExpenseMaster SET Status='PARTIAL'
                        WHERE SupplierID=@SupplierKey AND BatchReferenceID=@eBatchRef AND InvoiceNo=@eInvoiceNo
                          AND BranchCode=@brBranch AND Status NOT IN ('FULLYPAID','VOID','CANCELLED');

                    SELECT @allDescNames = STUFF((
                        SELECT ' | ' + ExpenseName FROM (
                            SELECT DISTINCT ExpenseName FROM ExpenseMaster
                            WHERE SupplierID=@SupplierKey AND BatchReferenceID=@eBatchRef AND InvoiceNo=@eInvoiceNo AND BranchCode=@brBranch
                        ) d ORDER BY ExpenseName FOR XML PATH(''), TYPE
                    ).value('.','VARCHAR(MAX)'), 1, 3, '');

                    SET @eParticulars = 'EXPENSE PAYMENT | Supplier: '+@parmsupplierid+' | Ref: '+@parmrefno+' | '+LEFT(ISNULL(@allDescNames,''),500)
                        +CASE WHEN LEN(ISNULL(@parmcheckremarks,''))>0 THEN ' | '+LEFT(@parmcheckremarks,200) ELSE '' END;

                    EXEC sp_Payment_PostSettlementTicket
                        @TicketDate=@parmcheckdate, @BranchCode=@brBranch,
                        @ReferenceKey=@parmvoucherid, @ReferenceNumber=@parmrefno,
                        @Owner=@parmsuppliername, @Particulars=@eParticulars,
                        @PreparedBy=@parmpreparedby, @Mnemonic=@brMnemonic,
                        @PayableAccountCode=@eBatchPayableAcct, @GrossPayable=@brGross,
                        @BankAccountCode=@parmglcode, @NetCash=@brNetCash,
                        @EWTAmount=@brEWT, @DiscountAmount=@brDisc, @DiscountAccountCode=@eDiscAcct,
                        @OffsetAmount=@brOffset, @FXLoss=@brFXLoss, @FXGain=@brFXGain,
                        -- NEW 2026-09-25 (0 on every non-HO branch)
                        @OverPay=@brOverPay, @OverPayAccountCode=@xOverPayAcct,
                        @OverPayExpense=@brOverPayExp, @OverPayExpenseAccountCode=@xOverPayExpAcct,
                        @AdvanceApplied=@brAdv, @AdvanceAccountCode=@xAdvanceAcct,
                        @TicketNumber=@TicketNumber OUTPUT;

                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @brBranch,
                            @eInvoiceNo, @eInvoiceDate, @brGross, 'EXPENSE PAYMENT',
                            @parmpaymethod, @parmvouchertype, @TicketNumber,
                            @eBatchPayableAcct, @parmglcode, CAST(@eBatchRef AS VARCHAR(50)), @eBatchRef);

                    -- NEW 2026-09-25: credit-pool rows for the HO ticket's extras
                    -- (same shape/GL-code convention as the SINGLE branch).
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    SELECT @parmvoucherid, @parmsupplierid, @parmrefno, @brBranch,
                           @eInvoiceNo, @eInvoiceDate, x.Amount, x.PaymentType,
                           @parmpaymethod, @parmvouchertype, @TicketNumber,
                           x.DebitGL, x.CreditGL, CAST(@eBatchRef AS VARCHAR(50)), @eBatchRef
                    FROM (VALUES ('OVERPAY',        @brOverPay,    @xOverPayAcct,    @parmglcode),
                                 ('OVERPAYEXPENSE', @brOverPayExp, @xOverPayExpAcct, @parmglcode),
                                 ('ADVANCEAPPLIED', @brAdv,        @eBatchPayableAcct, @xAdvanceAcct)) x (PaymentType, Amount, DebitGL, CreditGL)
                    WHERE x.Amount > 0;

                    SET @eTransID = dbo.func_getLastID(@SupplierKey);
                    INSERT INTO [dbo].[SupplierLedger]
                        (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate,
                         Description, TransCode, TransactionDate, ReferenceNumber,
                         ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit,
                         EndingBalance, TransactedBy, ApprovedBy, TotalAmount,
                         PaymentType, ErrorCorrectTag, TicketReference, BatchReferenceID)
                    VALUES (@eTransID, @SupplierKey, @parmsupplierid, @parmcheckdate,
                            LEFT(ISNULL(@parmcheckremarks,'EXPENSE PAYMENT'),490),
                            @brMnemonic, @parmcheckdate, @parmrefno,
                            CAST(@eBatchRef AS VARCHAR(40))+'-'+@brBranch,
                            @eInvoiceNo, 0, @brGross, 0, @brGross, @parmpreparedby, '*', @brGross, 'PARTIAL',
                            0, @TicketNumber, @eBatchRef);

                    SET @brrow += 1;
                END;

                -- NEW 2026-09-25: invoice with NO head-office share - OverPay /
                -- OverPayExpense go on their own 888 ticket, which balances by
                -- itself (DR advances-or-expense / CR bank = the excess cash).
                -- Reuses the settlement helper with the advances (or expense)
                -- account as its debit leg; no 20103 leg is involved.
                -- (AdvanceApplied was already rejected above for this case.)
                IF @bHasHO = 0 AND (@bOverPay > 0 OR @bOverPayExp > 0)
                BEGIN
                    DECLARE @hoAmt DECIMAL(18,2), @hoAcct VARCHAR(50), @hoType VARCHAR(20);
                    SELECT @hoAmt  = CASE WHEN @bOverPay > 0 THEN @bOverPay ELSE @bOverPayExp END,
                           @hoAcct = CASE WHEN @bOverPay > 0 THEN @xOverPayAcct ELSE @xOverPayExpAcct END,
                           @hoType = CASE WHEN @bOverPay > 0 THEN 'OVERPAY' ELSE 'OVERPAYEXPENSE' END;

                    SET @TotalNetCashForRecon += @hoAmt;

                    SET @eParticulars = 'EXPENSE OVERPAYMENT (HO) | Supplier: '+@parmsupplierid+' | Ref: '+@parmrefno
                        +' | Invoice: '+ISNULL(@eInvoiceNo,'')
                        +CASE WHEN LEN(ISNULL(@parmcheckremarks,''))>0 THEN ' | '+LEFT(@parmcheckremarks,200) ELSE '' END;

                    EXEC sp_Payment_PostSettlementTicket
                        @TicketDate=@parmcheckdate, @BranchCode=@bHOBranch,
                        @ReferenceKey=@parmvoucherid, @ReferenceNumber=@parmrefno,
                        @Owner=@parmsuppliername, @Particulars=@eParticulars,
                        @PreparedBy=@parmpreparedby, @Mnemonic='EXP-OVERPAY-HO',
                        @PayableAccountCode=@hoAcct, @GrossPayable=@hoAmt,
                        @BankAccountCode=@parmglcode, @NetCash=@hoAmt,
                        @TicketNumber=@TicketNumber OUTPUT;

                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @bHOBranch,
                            @eInvoiceNo, @eInvoiceDate, @hoAmt, @hoType,
                            @parmpaymethod, @parmvouchertype, @TicketNumber,
                            @hoAcct, @parmglcode, CAST(@eBatchRef AS VARCHAR(50)), @eBatchRef);
                END

                DROP TABLE #BranchTotals;
                SET @row += 1;
            END;

            declare @reconbranch varchar(5)
            set @reconbranch=ISNULL(@ocBranch,'888');
            DECLARE @Remarks2 VARCHAR(500);
            SET @Remarks2 = 'Auto-OC | Ref: ' + ISNULL(@parmrefno, '');
            IF ISNULL(@SkipVoucherWrap, 0) = 0   -- [97] a mixed voucher posts its one OC in sp_PostSupplierPaymentWithManualLines
            EXEC sp_Payment_PostBankReconEntry
                @ItemType='OC', @BranchCode=@reconbranch, @AccountCode=@parmglcode,
                @PeriodEnd=@ocPeriodEnd, @ReferenceNo=@parmvoucherid, @ItemDate=@parmcheckdate,
                @Payee=@parmsuppliername, @Amount=@TotalNetCashForRecon,
                @Remarks=@Remarks2, @SourceModule='AP-PAYMENT',
                @SourceRef=@parmrefno, @CreatedBy=@parmpreparedby;
        END

        DECLARE @CheckOrControlNo VARCHAR(50);

        SET @CheckOrControlNo =
            CASE
                WHEN @parmvouchertype = 'CHECK'
                    THEN @parmcheckno
                ELSE @parmcontrolno
            END;

            IF ISNULL(@SkipVoucherWrap, 0) = 0   -- [97]
            EXEC sp_Payment_CreateVoucherHeader
                @VoucherType       = @parmvouchertype,
                @VoucherID         = @parmvoucherid,
                @SupplierID        = @parmsupplierid,
                @ReferenceNumber   = @parmrefno,
                @PaidTo            = @parmsuppliername,
                @CheckOrControlNo  = @CheckOrControlNo,
                @CheckCoding       = @parmcheckcoding,
                @VoucherDate       = @parmcheckdate,
                @Particulars       = @parmcheckremarks,
                @Amount            = @TotalNetCashForRecon,
                @PreparedBy        = @parmpreparedby,
                @ForLiquidation    = @parmforliquidation,
                @GLCode            = @parmglcode;
        SET @NetCashOut = @TotalNetCashForRecon;   -- [97]
        DROP TABLE #Lines;
        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.sp_AddPaymentSupplierCompound', 'sp_AddPaymentSupplierCompound_OLD_10172026210000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE   PROCEDURE [dbo].[sp_AddPaymentSupplierCompound]
(
    @parmrefno          VARCHAR(10),
    @parmvoucherid      VARCHAR(10),
    @parmsupplierid     VARCHAR(50),
    @parmsuppliername   VARCHAR(150),
    @parmcheckamount    DECIMAL(18,2),
    @parmcheckcoding    VARCHAR(50),
    @parmcheckno        VARCHAR(50),
    @parmcontrolno      VARCHAR(50),
    --@parmdate           DATE,
    @parmcheckdate      DATE,
    @parmcheckremarks   VARCHAR(2000),
    @parmpreparedby     VARCHAR(30),
    @parmglcode         VARCHAR(30),
    @parmpaymethod      VARCHAR(20),
    @parmforliquidation BIT          = 0,
    @parmvouchertype    VARCHAR(10),
    @Lines              [dbo].[AP_PaymentLineTVP] READONLY,
    @parmPayingBranch   VARCHAR(5)   = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;   -- [84] unnamed: a named ROLLBACK fails with 6401 when this proc runs inside an outer transaction
    BEGIN TRY
    DECLARE @TotalNetCashForRecon DECIMAL(18,2) = 0;
        DECLARE
            @SeqNo           INT,
            @SupplierKey     VARCHAR(30),
            @TransID         INT,
            @brrow           INT = 1,
            @brmaxrow        INT,
            @br              VARCHAR(5),
            @brMnemonic      VARCHAR(50),
            @totalGross      DECIMAL(18,2),
            @totalNetCash    DECIMAL(18,2),
            @totalEWT        DECIMAL(18,2),
            @totalDiscount   DECIMAL(18,2),
            @totalOffset     DECIMAL(18,2),
            @ticketnum       VARCHAR(20),
            @Particulars     VARCHAR(7000),
            @allDescNames    VARCHAR(2000),
            @invrow          INT,
            @invmaxrow       INT,
            @invBatchRef     BIGINT,
            @invInvoiceNo    VARCHAR(150),
            @invInvDate      DATE,
            @invDesc         VARCHAR(300),
            @invGross        DECIMAL(18,2),
            @invTotalAmt     DECIMAL(18,2),
            @invCurBalance   DECIMAL(18,2),
            @invNewBalance   DECIMAL(18,2),
            @invEWTNow       DECIMAL(18,2),
            @invDiscNow      DECIMAL(18,2),
            @invOffsetNow    DECIMAL(18,2),
            @invNetCash      DECIMAL(18,2),
            @invEWTRemain    DECIMAL(18,2),
            @invEWTAlreadyPosted DECIMAL(18,2),  -- NEW
            @invEWTToWithhold    DECIMAL(18,2),  -- NEW
            @invPostingMode      VARCHAR(10),    -- NEW: 'BATCH' or 'SINGLE'
            @invPayableAcct      VARCHAR(20),    -- NEW: for SINGLE mode settlement
            @invDiscRemain   DECIMAL(18,2),
            @invDiscAccountCode VARCHAR(20),   -- NEW: per-invoice override for the discount leg's AccountCode
            @invOffsetRemain DECIMAL(18,2),
            @invVariance     DECIMAL(18,2),
            @legrow          INT,
            @legmaxrow       INT,
            @legTRNSeqNo     DECIMAL(4,0),
            @legAmount       DECIMAL(18,2),
            @legNetLiability DECIMAL(18,2),
            @legPropAmt      DECIMAL(18,2),
            @legRunningSum   DECIMAL(18,2),
            @row             INT = 1,
            @maxrow          INT,
            @BranchCode      VARCHAR(5),
            @InvoiceNo       VARCHAR(150),
            @InvoiceDate     DATE,
            @SeqRef          VARCHAR(50),
            @BatchRef        BIGINT,
            @ActualCost      DECIMAL(18,2),
            @AmtPaid         DECIMAL(18,2),
            @EWT             DECIMAL(18,2),
            @Variance        DECIMAL(18,2),
            @FXLoss          DECIMAL(18,2),
            @FXGain          DECIMAL(18,2),
            @Discount        DECIMAL(18,2),
            @RetAllow        DECIMAL(18,2),
            @Gross           DECIMAL(18,2),
            @Mnemonic        VARCHAR(50),
            @brFirstBatch    BIGINT,
            @brFirstInv      VARCHAR(150),
            @ocBranch        VARCHAR(5),
            @ocPeriodEnd     DATE;

        DECLARE @PeriodEnd     DATE = EOMONTH(@parmcheckdate);
        IF @PeriodEnd IS NULL OR @PeriodEnd=''
        BEGIN
            SET @PeriodEnd = EOMONTH(GETDATE());
        END

        DECLARE @ReconHeaderID INT;

        IF @parmcheckdate IS NULL SET @parmcheckdate = CAST(GETDATE() AS DATE);
        SET @ocPeriodEnd = EOMONTH(@parmcheckdate);

        SELECT @SupplierKey = SupplierKey
        FROM Supplier WHERE SupplierID = @parmsupplierid;

        SELECT @SeqNo = ISNULL(MAX(SEQ_NO),0) + 1
        FROM TransactionPaymentAP WHERE SupplierKey = @SupplierKey;

        INSERT INTO [dbo].[TransactionPaymentAP]
            (SEQ_NO, SupplierKey, ReferenceNumber, Amount, VoucherType,
             DatePaid, ExecuteBy, DateUpdate, UpdateBy, ErrorCorrect)
        VALUES(@SeqNo, @SupplierKey, @parmrefno, @parmcheckamount, @parmvouchertype,
               GETDATE(), @parmpreparedby, GETDATE(), @parmpreparedby, 0);

        IF @parmvouchertype = 'CHECK'
            INSERT INTO [dbo].[CheckVoucher]
                (VoucherID, SupplierID, ReferenceNumber, PaidTo, CheckNo, CheckDate,
                 Particulars, Amount, PreparedBy, VerifiedBy, NotedBy, PaymentApprovedBy,
                 PaymentReceivedBy, OfficialReceiptNo, VoucherType, DateReceived,
                 DateAdded, DateUpdate, isErrorCorrect, isLiquidation, CVNo)   -- 2026-10-02i
            VALUES(@parmvoucherid, @parmsupplierid, @parmrefno, @parmsuppliername,
                   @parmcheckno, @parmcheckdate, @parmcheckremarks, @parmcheckamount,
                   @parmpreparedby, '', @parmglcode, '', '', @parmcheckcoding,
                   @parmpaymethod, '', GETDATE(), GETDATE(), 0, @parmforliquidation, NULLIF(LTRIM(RTRIM(@parmcheckcoding)), ''));
        ELSE IF @parmvouchertype = 'CASH'
            INSERT INTO [dbo].[CashVoucher]
                (VoucherID, SupplierID, ReferenceNumber, PaidTo, Particulars, Amount,
                 PreparedBy, VerifiedBy, NotedBy, PaymentApprovedBy, PaymentReceivedBy,
                 OfficialReceiptNo, VoucherType, DateReceived, DateAdded, DateUpdate,
                 isErrorCorrect, isLiquidation)
            VALUES(@parmvoucherid, @parmsupplierid, @parmrefno, @parmsuppliername,
                   @parmcheckremarks, @parmcheckamount, @parmpreparedby, '', '', '', '', @parmcontrolno,
                   @parmpaymethod, @parmcheckdate, GETDATE(), GETDATE(), 0, @parmforliquidation);
        ELSE IF @parmvouchertype = 'TELEGRAPHIC'  
            INSERT INTO [dbo].[TelegraphicVoucher]
                (VoucherID, SupplierID, ReferenceNumber, PaidTo, Particulars, Amount,
                 PreparedBy, VerifiedBy, NotedBy, PaymentApprovedBy, PaymentReceivedBy,
                 OfficialReceiptNo, VoucherType, DateReceived, DateAdded, DateUpdate,
                 isErrorCorrect, isLiquidation)
            VALUES(@parmvoucherid, @parmsupplierid, @parmrefno, @parmsuppliername,
                   @parmcheckremarks, @parmcheckamount, @parmpreparedby, '', '', '', '', @parmcontrolno,
                   @parmpaymethod, @parmcheckdate, GETDATE(), GETDATE(), 0, @parmforliquidation);

        -- ── #Lines: invoice-level only (BranchCode from TVP ignored) ──
        SELECT
            ROW_NUMBER() OVER(ORDER BY L.BatchReferenceID, L.InvoiceNo) AS RowNum,
            L.InvoiceNo,
            L.InvoiceDate,
            L.SequenceReferenceNumber,
            L.BatchReferenceID,
            L.ActualCost,
            L.AmountPaid,
            ISNULL(L.EWTAmount,      0) AS EWTAmount,
            ISNULL(L.DiscountAmount, 0) AS DiscountAmount,
            ISNULL(L.OffsetAmount,   0) AS OffsetAmount,
            ISNULL(L.Variance,       0) AS Variance,
            L.DiscountAccountCode,        -- NEW
            L.Description
        INTO #Lines
        FROM @Lines L;

        SELECT @maxrow = COUNT(*) FROM #Lines;

        -- OC paying branch: explicit param → fallback to first line header
        SET @ocBranch = ISNULL(
            NULLIF(LTRIM(RTRIM(ISNULL(@parmPayingBranch,''))), ''),
            @parmPayingBranch
        );
        IF @ocBranch IS NULL
            SELECT TOP 1 @ocBranch = BranchCode
            FROM ExpenseMaster
            WHERE SupplierID = @SupplierKey
              AND BatchReferenceID = (SELECT TOP 1 BatchReferenceID FROM #Lines ORDER BY RowNum)
            ORDER BY TRN_SEQ_NO;

        -- ============================================================
        -- PURCHASE FLOW (unchanged)
        -- ============================================================
        IF @parmpaymethod = 'PURCHASE'
        BEGIN
            WHILE @row <= @maxrow
            BEGIN
                SELECT
                    @InvoiceNo  = InvoiceNo,
                    @InvoiceDate= InvoiceDate,
                    @SeqRef     = SequenceReferenceNumber,
                    @BatchRef   = BatchReferenceID,
                    @ActualCost = ActualCost,
                    @AmtPaid    = AmountPaid,
                    @EWT        = EWTAmount,
                    @Discount   = DiscountAmount,
                    @RetAllow   = OffsetAmount,
                    @Variance   = Variance
                FROM #Lines WHERE RowNum = @row;

                SET @BranchCode = '888'

               -- FIX: Gross must stay the ORIGINAL booked liability amount
                -- (what actually extinguishes APACCOUNTS.Balance) - it no
                -- longer equals AmtPaid+EWT+Discount+Offset alone once a
                -- forex variance exists, since AmtPaid now reflects TODAY's
                -- actual cash outlay, which can differ from what was booked.
                SET @Gross = @AmtPaid + @EWT + @Discount + @RetAllow - @Variance;
 
                -- Variance > 0 = paid MORE pesos than booked = FX LOSS
                -- Variance < 0 = paid LESS pesos than booked = FX GAIN
                SET @FXLoss = CASE WHEN @Variance > 0 THEN @Variance ELSE 0 END;
                SET @FXGain = CASE WHEN @Variance < 0 THEN -@Variance ELSE 0 END;
SET @TotalNetCashForRecon += @AmtPaid;
                SET @Mnemonic = CASE
                    WHEN @EWT>0 AND @Discount+@RetAllow>0 THEN 'PV-AP-EWT-DISC'   -- [83] a return allowance is booked like a discount
                    WHEN @EWT>0 THEN 'PV-AP-EWT'
                    WHEN @Discount+@RetAllow>0 THEN 'PV-AP-DISC'   -- [83]
                    ELSE 'PV-AP' END;

                SET @Particulars = 'PURCHASE PAYMENT | Supplier: '+@parmsupplierid
                    +' | Invoice: '+@InvoiceNo+' | Ref: '+@parmrefno
                    +CASE WHEN LEN(ISNULL(@parmcheckremarks,''))>0
                          THEN ' | '+LEFT(@parmcheckremarks,200) ELSE '' END;

                DECLARE @Amounts dbo.tt_AmountBreakdown;
                DECLARE @Tokens  dbo.tt_TokenResolution;
                DECLARE @Flags   dbo.tt_ConditionFlags;
                DELETE FROM @Amounts; DELETE FROM @Tokens; DELETE FROM @Flags;
                INSERT @Amounts VALUES('GROSS',@Gross),('NET',@AmtPaid),
                                      ('EWT',@EWT),('MIRROR',@Discount+@RetAllow),('DISCRETALLOW',@Discount+@RetAllow),   -- [83]
                                      ('VARIANCE_LOSS',@FXLoss),('VARIANCE_GAIN',@FXGain);
                INSERT @Tokens  VALUES('{BANK}',@parmglcode);
                INSERT @Flags
                VALUES('HasEWT',     CASE WHEN @EWT>0      THEN 1 ELSE 0 END),
                      ('HasDiscount',CASE WHEN @Discount+@RetAllow>0 THEN 1 ELSE 0 END),   -- [83]
                      ('HasFXLoss',  CASE WHEN @FXLoss>0    THEN 1 ELSE 0 END),
                      ('HasFXGain',  CASE WHEN @FXGain>0    THEN 1 ELSE 0 END);


                EXEC [dbo].[sp_PostCompoundTicket]
                    @Mnemonic=@Mnemonic, @TicketDate=@parmcheckdate,
                    @BranchCode=@BranchCode, @ReferenceNumber=@parmrefno,
                    @ReferenceKey=@parmcheckno, @Particulars=@Particulars,
                    @Owner=@parmsupplierid, @PreparedBy=@parmpreparedby,
                    @Status='POSTED', @Amounts=@Amounts, @Tokens=@Tokens,
                    @Flags=@Flags, @LedgerType='SUPPLIER',
                    @LedgerEntityID=@parmsupplierid,
                    @LedgerInvoiceNo=@InvoiceNo, @LedgerBatchRef=@BatchRef,
                    @LedgerSeqRef=@SeqRef, @LedgerSide='D';   -- 2026-10-13f [71]: the payment row is a debit

                IF @AmtPaid>0
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES(@parmvoucherid, @parmsupplierid, @parmrefno, @BranchCode,
                           @InvoiceNo, @InvoiceDate, @AmtPaid, 'INVOICE PAYMENT',
                           @parmpaymethod, @parmvouchertype, '', @parmglcode, @parmglcode,
                           @SeqRef, @BatchRef);

                UPDATE APACCOUNTS
                SET Balance   = Balance - @Gross,
                    PayStatus = CASE WHEN (Balance-@Gross)<=0 THEN 'FULLYPAID' ELSE 'PARTIAL' END
                WHERE SupplierID = @parmsupplierid
                  AND InvoiceNo  = @InvoiceNo
                  AND SequenceNo = @SeqRef;

    --///////////////////////////////AP            

              

                SET @row += 1;
            END;
                    -- [88] H7: through the shared helper (one item per reference, account and side; a locked month is refused)
                    DECLARE @LegacyOcBranch VARCHAR(5) = ISNULL(@ocBranch, '888');
                    DECLARE @LegacyOcRemarks VARCHAR(500) = 'Auto-OC | Invoice: '+@InvoiceNo+' | Ref: '+@parmrefno;
                    EXEC dbo.sp_Payment_PostBankReconEntry
                        @ItemType = 'OC', @BranchCode = @LegacyOcBranch, @AccountCode = @parmglcode, @PeriodEnd = @ocPeriodEnd,
                        @ReferenceNo = @parmvoucherid, @ItemDate = @parmcheckdate, @Payee = @parmsuppliername, @Amount = @TotalNetCashForRecon,
                        @Remarks = @LegacyOcRemarks, @SourceModule = 'AP-PAYMENT', @SourceRef = @parmrefno, @CreatedBy = @parmpreparedby;
        END

        -- ============================================================
        -- EXPENSE FLOW — RESTRUCTURED
        -- ============================================================
        ELSE
        BEGIN
            WHILE @row <= @maxrow
            BEGIN
                SELECT
                    @invInvoiceNo   = InvoiceNo,
                    @invInvDate     = InvoiceDate,
                    @invBatchRef    = BatchReferenceID,
                    @invTotalAmt    = ActualCost,
                    @invDesc        = Description,
                    @invDiscRemain  = DiscountAmount,
                    @invOffsetRemain= OffsetAmount,
                    @invVariance    = Variance,
                    @invDiscAccountCode = DiscountAccountCode   -- NEW
                FROM #Lines WHERE RowNum = @row;

                -- ── NEW: figure out which settlement path this invoice needs ──
                SELECT
                    @invPostingMode = ISNULL(PostingMode, 'BATCH'),
                    @invPayableAcct = PayableAccountCode
                FROM ExpenseSummary
                WHERE SupplierID       = @SupplierKey
                  AND BatchReferenceID = @invBatchRef
                  AND InvoiceNo        = @invInvoiceNo;

                -- [105] 2026-10-17: a loan payable settles in Vouchering Telegraphic only (here it would take the BATCH path)
                IF @invPostingMode = 'LOAN'
                    THROW 60540, 'This invoice is a loan (Loan Revaluation): pay it in Vouchering Telegraphic, which debits the loan account. Nothing was posted.', 1;

                IF @invPostingMode = 'SINGLE'
                BEGIN
                    -- ════════════════════════════════════════════════════
                    -- SINGLE MODE SETTLEMENT — manual/no-mapping entries.
                    -- Everything (EWT, discounts, whatever else) was already
                    -- fully resolved in the original compound journal entry
                    -- at posting time, so there's no branch loop, no EWT
                    -- recompute, no proportional splitting - just pay down
                    -- whatever's left on the designated payable account.
                    -- ════════════════════════════════════════════════════
                    SELECT @invCurBalance = ISNULL(Balance, ISNULL(Amount, 0))
                    FROM ExpenseSummary
                    WHERE SupplierID       = @SupplierKey
                      AND BatchReferenceID = @invBatchRef
                      AND InvoiceNo        = @invInvoiceNo;

                     -- ════════════════════════════════════════════════
                    -- FIX: was "@invGross = AmountPaid" only — silently
                    -- ignored EWTAmount/DiscountAmount/OffsetAmount/
                    -- Variance entirely. SINGLE mode still needs the
                    -- SAME gross formula BATCH mode uses (it just skips
                    -- the branch-weighted splitting, since SINGLE
                    -- settles as one lump sum) — otherwise a partial
                    -- payment with EWT withheld never reduces Balance
                    -- by the EWT portion, never creates an EWT Payable
                    -- leg, and Balance never reaches zero even though
                    -- the invoice is fully settled (cash + EWT).
                    -- ════════════════════════════════════════════════
                    DECLARE @invEWT_S DECIMAL(18,2), @invDisc_S DECIMAL(18,2),
                            @invOffset_S DECIMAL(18,2), @invNetCash_S DECIMAL(18,2),
                            @invFXLoss_S DECIMAL(18,2), @invFXGain_S DECIMAL(18,2),
                            @invDiscAcct_S VARCHAR(20);
 
                    SELECT
                        @invGross      = AmountPaid + ISNULL(EWTAmount,0) + ISNULL(DiscountAmount,0) + ISNULL(OffsetAmount,0) - ISNULL(Variance,0),
                        @invNetCash_S  = AmountPaid,
                        @invEWT_S      = ISNULL(EWTAmount,0),
                        @invDisc_S     = ISNULL(DiscountAmount,0),
                        @invOffset_S   = ISNULL(OffsetAmount,0),
                        @invDiscAcct_S = DiscountAccountCode
                    FROM #Lines WHERE RowNum = @row;
 
                    SET @invFXLoss_S = CASE WHEN ISNULL(@invVariance,0) > 0 THEN @invVariance ELSE 0 END;
                    SET @invFXGain_S = CASE WHEN ISNULL(@invVariance,0) < 0 THEN -@invVariance ELSE 0 END;
SET @TotalNetCashForRecon += @invNetCash_S;
                    IF @invPayableAcct IS NULL
                        THROW 56002, 'SINGLE-mode invoice has no PayableAccountCode recorded - cannot determine which account to settle.', 1;

                    SET @invNewBalance = ROUND(
                        CASE WHEN @invCurBalance - @invGross < 0
                             THEN 0 ELSE @invCurBalance - @invGross END, 2);

                    -- FIX: AmountPaid now accumulates the NET cash portion
                    -- only (matching BATCH mode's own pattern), not the
                    -- full gross — and EWT/Discount/Offset Withheld are
                    -- now tracked here too, previously never updated at
                    -- all in SINGLE mode.
                    UPDATE ExpenseSummary
                    SET Balance          = @invNewBalance,
                        AmountPaid       = ISNULL(AmountPaid,0)       + @invNetCash_S,
                        EWTWithheld      = ISNULL(EWTWithheld,0)      + @invEWT_S,
                        DiscountWithheld = ISNULL(DiscountWithheld,0) + @invDisc_S,
                        OffsetWithheld   = ISNULL(OffsetWithheld,0)   + @invOffset_S,
                        Status           = CASE WHEN @invNewBalance <= 0 THEN 'FULLYPAID' ELSE 'PARTIAL' END,
                        UpdatedBy        = @parmpreparedby,
                        DateTimeUpdated  = GETDATE()
                    WHERE SupplierID       = @SupplierKey
                      AND BatchReferenceID = @invBatchRef
                      AND InvoiceNo        = @invInvoiceNo;

                    IF @invNewBalance <= 0
                        UPDATE ExpenseMaster SET Balance = 0, AmountPaid = Amount, Status = 'FULLYPAID'
                        WHERE SupplierID       = @SupplierKey
                          AND BatchReferenceID = @invBatchRef
                          AND InvoiceNo        = @invInvoiceNo;

                    SET @Particulars = 'EXPENSE PAYMENT (SINGLE) | Supplier: '+@parmsupplierid
                        +' | Ref: '+@parmrefno+' | '+LEFT(ISNULL(@invDesc,''),500)
                        +CASE WHEN LEN(ISNULL(@parmcheckremarks,''))>0
                              THEN ' | '+LEFT(@parmcheckremarks,200) ELSE '' END;

                    SELECT TOP 1 @br = BranchCode FROM ExpenseMaster
                    WHERE SupplierID = @SupplierKey AND BatchReferenceID = @invBatchRef AND InvoiceNo = @invInvoiceNo;

                    EXEC GetTicketNumber @ticketnum OUTPUT;
                    SET @TransID = dbo.func_getLastID(@SupplierKey);

                    INSERT INTO [dbo].[TicketMaster]
                        (TicketDate, SupplementaryNumber, BranchCode, Origin,
                         TicketNumber, ReferenceNumber, ReferenceKey, Owner,
                         Particulars, EnteredBy, CheckedBy, ApprovedBy,
                         Status, Mnemonic, Product)
                    VALUES(@parmcheckdate, 0, @br, 'PV', @ticketnum, @parmrefno,
                           @parmvoucherid, @parmsuppliername, LEFT(@Particulars,6999),
                           @parmpreparedby, '*', '*', 'POSTED', 'SINGLE-PAY', NULL);

                    -- DR the payable account (extinguishing what's being paid now)
                    INSERT INTO [dbo].[TicketDetails]
                        (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                         TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
                    VALUES(@parmcheckdate, 0, @br, @parmvoucherid,
                           @ticketnum, @parmrefno, @invPayableAcct, ROUND(@invGross,2), 0, '');

                    -- CR Bank — NET CASH ONLY (was gross before the fix)
                    IF @invNetCash_S > 0
                        INSERT INTO [dbo].[TicketDetails]
                            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
                        VALUES(@parmcheckdate, 0, @br, @parmvoucherid,
                               @ticketnum, @parmrefno, @parmglcode, 0, ROUND(@invNetCash_S,2), '');
 
                    -- CR EWT Payable — NEW, was completely missing before
                    IF @invEWT_S > 0
                        INSERT INTO [dbo].[TicketDetails]
                            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
                        VALUES(@parmcheckdate, 0, @br, @parmvoucherid,
                               @ticketnum, @parmrefno, '20104', 0, ROUND(@invEWT_S,2), '');
 
                    -- CR Discount — NEW, was completely missing before.
                    -- Same override-or-default pattern as BATCH mode.
                    IF @invDisc_S > 0
                        INSERT INTO [dbo].[TicketDetails]
                            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
                        VALUES(@parmcheckdate, 0, @br, @parmvoucherid,
                               @ticketnum, @parmrefno, ISNULL(@invDiscAcct_S, '508'), 0, ROUND(@invDisc_S,2), '');
 
                    -- CR Offset — NEW, was completely missing before
                    IF @invOffset_S > 0
                        INSERT INTO [dbo].[TicketDetails]
                            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
                        VALUES(@parmcheckdate, 0, @br, @parmvoucherid,
                               @ticketnum, @parmrefno, '40104', 0, ROUND(@invOffset_S,2), '');
 
                    -- FX variance legs — NEW, were completely missing before
                    IF @invFXLoss_S > 0
                        INSERT INTO [dbo].[TicketDetails]
                            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
                        VALUES(@parmcheckdate, 0, @br, @parmvoucherid,
                               @ticketnum, @parmrefno, '60310', ROUND(@invFXLoss_S,2), 0, '');
 
                    IF @invFXGain_S > 0
                        INSERT INTO [dbo].[TicketDetails]
                            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
                        VALUES(@parmcheckdate, 0, @br, @parmvoucherid,
                               @ticketnum, @parmrefno, '40510', 0, ROUND(@invFXGain_S,2), '');

                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES(@parmvoucherid, @parmsupplierid, @parmrefno, @br,
                           @invInvoiceNo, @invInvDate, @invGross, 'EXPENSE PAYMENT',
                           @parmpaymethod, @parmvouchertype, @ticketnum,
                           @invPayableAcct, @parmglcode,
                           CAST(@invBatchRef AS VARCHAR(50)), @invBatchRef);

                    INSERT INTO [dbo].[SupplierLedger]
                        (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate,
                         Description, TransCode, TransactionDate, ReferenceNumber,
                         ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit,
                         EndingBalance, TransactedBy, ApprovedBy, TotalAmount,
                         PaymentType, ErrorCorrectTag, TicketReference, BatchReferenceID)
                    VALUES(@TransID, @SupplierKey, @parmsupplierid, @parmcheckdate,
                           LEFT(ISNULL(@parmcheckremarks,'EXPENSE PAYMENT'),490),
                           'SNGLE-PAY', @parmcheckdate, @parmrefno,
                           CAST(@invBatchRef AS VARCHAR(40))+'-'+@br,
                           @invInvoiceNo, 0, @invGross, 0, @invGross,
                           @parmpreparedby, '*', @invGross,
                           CASE WHEN @invNewBalance<=0 THEN 'FULLYPAID' ELSE 'PARTIAL' END,
                           0, @ticketnum, @invBatchRef);
 

                    SET @row += 1;
                    CONTINUE;
                END;

                -- ════════════════════════════════════════════════════
                -- BATCH MODE (existing logic, unchanged below) - mapped
                -- entries with per-branch, per-line EWT handling.
                -- ════════════════════════════════════════════════════

                -- ── NEW: derive the EWT split from ExpenseMaster itself
                --    (source of truth) rather than trusting the TVP's
                --    EWTAmount - this is what prevents double-withholding
                --    for lines already posted at accrual. ──
                SELECT
                    @invEWTAlreadyPosted = ISNULL(SUM(CASE WHEN IsEWTPostedAtAccrual = 1 THEN EWTAmount ELSE 0 END), 0),
                    @invEWTToWithhold    = ISNULL(SUM(CASE WHEN IsEWTPostedAtAccrual = 0 THEN EWTAmount ELSE 0 END), 0)
                FROM ExpenseMaster
                WHERE SupplierID       = @SupplierKey
                  AND BatchReferenceID = @invBatchRef
                  AND InvoiceNo        = @invInvoiceNo;
                   

                --SET @invEWTRemain = @invEWTToWithhold;
                DECLARE @invEWTFromTVP DECIMAL(18,2);
                SELECT @invEWTFromTVP = ISNULL(EWTAmount, 0) FROM #Lines WHERE RowNum = @row;
                
                SET @invEWTRemain = CASE WHEN @invEWTFromTVP > 0 THEN @invEWTFromTVP ELSE @invEWTToWithhold END;
                -- NEW: this is the correct weighting basis for splitting the
                -- payment across branches - NET of whatever EWT was already
                -- posted at accrual, not gross Amount. A branch that had EWT
                -- withheld at posting owes less than its gross share; using
                -- gross Amount as the split basis mis-allocates the payment
                -- (e.g. Branch A gross 1000 with 10 EWT-at-accrual actually
                -- owes 990, not 1000 - splitting a 2990 payment by gross
                -- 1000/3000 gives 996.67, not the correct 990.00).
                DECLARE @invNetLiability DECIMAL(18,2) = @invTotalAmt - @invEWTAlreadyPosted;

                -- invGross = total being paid for this invoice. Already-posted
                -- EWT is excluded - it was already extinguished from AP-Trade
                -- and moved to EWT Payable back at posting time.
                --SELECT @invGross = AmountPaid + @invEWTRemain + DiscountAmount + OffsetAmount
                SELECT @invGross = AmountPaid + @invEWTRemain + DiscountAmount + OffsetAmount - @invVariance
                FROM #Lines WHERE RowNum = @row;

                -- ── STEP A: Update ExpenseSummary balance ────────────
                SELECT @invCurBalance = ISNULL(Balance, ISNULL(Amount, 0))
                FROM ExpenseSummary
                WHERE SupplierID       = @SupplierKey
                  AND BatchReferenceID = @invBatchRef
                  AND InvoiceNo        = @invInvoiceNo;

                SET @invNewBalance = ROUND(
                    CASE WHEN @invCurBalance - @invGross < 0
                         THEN 0 ELSE @invCurBalance - @invGross END, 2);

                UPDATE ExpenseSummary SET
                    Balance          = @invNewBalance,
                    AmountPaid       = ISNULL(AmountPaid,0)       + (@invGross - @invEWTRemain - @invDiscRemain - @invOffsetRemain),
                    EWTWithheld      = ISNULL(EWTWithheld,0)      + @invEWTRemain,
                    DiscountWithheld = ISNULL(DiscountWithheld,0) + @invDiscRemain,
                    OffsetWithheld   = ISNULL(OffsetWithheld,0)   + @invOffsetRemain,
                    Status           = CASE WHEN @invNewBalance<=0 THEN 'FULLYPAID' ELSE 'PARTIAL' END,
                    UpdatedBy        = @parmpreparedby,
                    DateTimeUpdated  = GETDATE()
                WHERE SupplierID       = @SupplierKey
                  AND BatchReferenceID = @invBatchRef
                  AND InvoiceNo        = @invInvoiceNo;

                -- ── STEP B: Get branch breakdown from ExpenseMaster ──
                IF OBJECT_ID('tempdb..#BranchTotals') IS NOT NULL
                    DROP TABLE #BranchTotals;

                SELECT
                    ROW_NUMBER() OVER (ORDER BY BranchCode) AS RowNum,
                    BranchCode,
                    SUM(Amount)                 AS BranchTotalAmt,
                    COUNT(*)                    AS LineCount,
                    SUM(CASE WHEN IsEWTPostedAtAccrual = 1 THEN ISNULL(EWTAmount,0) ELSE 0 END) AS BranchEWTAlreadyPosted,
                    -- NEW: what this branch ACTUALLY still owes, net of
                    -- whatever EWT was already withheld at accrual for it -
                    -- this is the correct basis for every proportional split
                    -- below, not the raw gross Amount.
                    SUM(Amount) - SUM(CASE WHEN IsEWTPostedAtAccrual = 1 THEN ISNULL(EWTAmount,0) ELSE 0 END) AS BranchNetLiability,
                    -- Proportional share of the REMAINING EWT/Discount/Offset,
                    -- now weighted by net liability (see @invNetLiability above)
                    ROUND(
                        ((SUM(Amount) - SUM(CASE WHEN IsEWTPostedAtAccrual = 1 THEN ISNULL(EWTAmount,0) ELSE 0 END))
                         / NULLIF(@invNetLiability, 0)) * @invEWTRemain, 2
                    )                           AS BranchEWT,
                    ROUND(
                        ((SUM(Amount) - SUM(CASE WHEN IsEWTPostedAtAccrual = 1 THEN ISNULL(EWTAmount,0) ELSE 0 END))
                         / NULLIF(@invNetLiability, 0)) * @invDiscRemain, 2
                    )                           AS BranchDisc,
                    ROUND(
                        ((SUM(Amount) - SUM(CASE WHEN IsEWTPostedAtAccrual = 1 THEN ISNULL(EWTAmount,0) ELSE 0 END))
                         / NULLIF(@invNetLiability, 0)) * @invOffsetRemain, 2
                    )                           AS BranchOffset,
                    ROUND(
                        ((SUM(Amount) - SUM(CASE WHEN IsEWTPostedAtAccrual = 1 THEN ISNULL(EWTAmount,0) ELSE 0 END))
                         / NULLIF(@invNetLiability, 0)) * @invVariance, 2
                    )                           AS BranchVariance   
                INTO #BranchTotals
                FROM ExpenseMaster
                WHERE SupplierID       = @SupplierKey
                  AND BatchReferenceID = @invBatchRef
                  AND InvoiceNo        = @invInvoiceNo
                GROUP BY BranchCode;

                SELECT @brmaxrow = COUNT(*) FROM #BranchTotals;
                SET @brrow = 1;

                DECLARE @ewtRunning  DECIMAL(18,2) = 0,
                        @discRunning DECIMAL(18,2) = 0,
                        @offRunning  DECIMAL(18,2) = 0,
                        @varRunning  DECIMAL(18,2) = 0;

                -- ── STEP C: One ticket per branch for this invoice ───
                WHILE @brrow <= @brmaxrow
                BEGIN
                    DECLARE @brTotalAmt DECIMAL(18,2),
                            @brLineCount INT,
                            @brEWT       DECIMAL(18,2),
                            @brDisc      DECIMAL(18,2),
                            @brOffset    DECIMAL(18,2),
                            @brVariance  DECIMAL(18,2),
                            @brFXLoss    DECIMAL(18,2),
                            @brFXGain    DECIMAL(18,2),
                            @brNetCash   DECIMAL(18,2),
                            @brGross     DECIMAL(18,2),
                            @brNetLiability DECIMAL(18,2);

                    SELECT
                        @br          = BranchCode,
                        @brTotalAmt  = BranchTotalAmt,
                        @brLineCount = LineCount,
                        @brEWT       = BranchEWT,
                        @brDisc      = BranchDisc,
                        @brOffset    = BranchOffset,
                        @brNetLiability = BranchNetLiability
                    FROM #BranchTotals WHERE RowNum = @brrow;

                    IF @brrow = @brmaxrow
                    BEGIN
                        SET @brEWT    = @invEWTRemain  - @ewtRunning;
                        SET @brDisc   = @invDiscRemain - @discRunning;
                        SET @brOffset = @invOffsetRemain - @offRunning;
                        SET @brVariance = @invVariance - @varRunning;
                    END
                    ELSE
                    BEGIN
                        SET @ewtRunning  += @brEWT;
                        SET @discRunning += @brDisc;
                        SET @offRunning  += @brOffset;
                        SET @varRunning  += @brVariance;
                    END

                    SET @brFXLoss = CASE WHEN @brVariance > 0 THEN @brVariance ELSE 0 END;
                    SET @brFXGain = CASE WHEN @brVariance < 0 THEN -@brVariance ELSE 0 END;

                    SET @brGross = ROUND(
                        (@brNetLiability / NULLIF(@invNetLiability, 0)) * @invGross, 2);
                    IF @brrow = @brmaxrow
                        SET @brGross = @invGross
                            - ISNULL((SELECT SUM(BranchNetLiability/@invNetLiability * @invGross)
                                      FROM #BranchTotals WHERE RowNum < @brmaxrow), 0);

                    SET @brNetCash = ROUND(
                        CASE WHEN @brGross - @brEWT - @brDisc - @brOffset + @brFXLoss - @brFXGain < 0
                             THEN 0
                             ELSE @brGross - @brEWT - @brDisc - @brOffset + @brFXLoss - @brFXGain
                        END, 2);
 SET @TotalNetCashForRecon += @brNetCash;
                    SET @brMnemonic = CASE WHEN @brEWT > 0
                        THEN 'EXP-ACCRUAL-PAY-EWT'
                        ELSE 'EXP-ACCRUAL-PAY' END;

                    IF @invNewBalance <= 0
                        UPDATE ExpenseMaster SET Balance=0, AmountPaid=Amount, Status='FULLYPAID'
                        WHERE SupplierID       = @SupplierKey
                          AND BatchReferenceID = @invBatchRef
                          AND InvoiceNo        = @invInvoiceNo
                          AND BranchCode       = @br;
                    ELSE
                        UPDATE ExpenseMaster SET Status='PARTIAL'
                        WHERE SupplierID       = @SupplierKey
                          AND BatchReferenceID = @invBatchRef
                          AND InvoiceNo        = @invInvoiceNo
                          AND BranchCode       = @br
                          AND Status NOT IN ('FULLYPAID','VOID','CANCELLED');

                    SET @allDescNames = NULL;
                    SELECT @allDescNames = STUFF((
                        SELECT ' | ' + ExpenseName
                        FROM (SELECT DISTINCT ExpenseName FROM ExpenseMaster
                              WHERE SupplierID=@SupplierKey
                                AND BatchReferenceID=@invBatchRef
                                AND InvoiceNo=@invInvoiceNo
                                AND BranchCode=@br) d
                        ORDER BY ExpenseName
                        FOR XML PATH(''), TYPE
                    ).value('.','VARCHAR(MAX)'), 1, 3, '');

                    SET @Particulars = 'EXPENSE PAYMENT | Supplier: '+@parmsupplierid
                        +' | Ref: '+@parmrefno+' | '+LEFT(ISNULL(@allDescNames,''),500)
                        +CASE WHEN LEN(ISNULL(@parmcheckremarks,''))>0
                              THEN ' | '+LEFT(@parmcheckremarks,200) ELSE '' END;

                    EXEC GetTicketNumber @ticketnum OUTPUT;
                    SET @TransID = dbo.func_getLastID(@SupplierKey);

                    INSERT INTO [dbo].[TicketMaster]
                        (TicketDate, SupplementaryNumber, BranchCode, Origin,
                         TicketNumber, ReferenceNumber, ReferenceKey, Owner,
                         Particulars, EnteredBy, CheckedBy, ApprovedBy,
                         Status, Mnemonic, Product)
                    VALUES(@parmcheckdate, 0, @br, 'PV', @ticketnum, @parmrefno,
                           @parmcheckno, @parmsuppliername, LEFT(@Particulars,6999),
                           @parmpreparedby, '*', '*', 'POSTED', @brMnemonic, NULL);

                    IF OBJECT_ID('tempdb..#LegLines') IS NOT NULL DROP TABLE #LegLines;

                    -- NEW: same net-liability fix as the branch level, applied
                    -- per line - if a branch ever has multiple ExpenseMaster
                    -- lines and only some had EWT posted at accrual, splitting
                    -- @brGross by gross LineAmount would misallocate here too.
                    SELECT
                        ROW_NUMBER() OVER(ORDER BY TRN_SEQ_NO) AS RowNum,
                        COUNT(*) OVER() AS TotalLines,
                        TRN_SEQ_NO,
                        Amount AS LineAmount,
                        Amount - CASE WHEN IsEWTPostedAtAccrual = 1 THEN ISNULL(EWTAmount,0) ELSE 0 END AS LineNetLiability
                    INTO #LegLines
                    FROM ExpenseMaster
                    WHERE SupplierID       = @SupplierKey
                      AND BatchReferenceID = @invBatchRef
                      AND InvoiceNo        = @invInvoiceNo
                      AND BranchCode       = @br
                    ORDER BY TRN_SEQ_NO;

                    SET @legrow = 1; SET @legRunningSum = 0;
                    SELECT @legmaxrow = COUNT(*) FROM #LegLines;

                    WHILE @legrow <= @legmaxrow
                    BEGIN
                        SELECT @legTRNSeqNo = TRN_SEQ_NO, @legAmount = LineAmount, @legNetLiability = LineNetLiability
                        FROM #LegLines WHERE RowNum = @legrow;

                        IF @legrow < @legmaxrow
                        BEGIN
                            SET @legPropAmt = ROUND(
                                (@legNetLiability / NULLIF(@brNetLiability, 0)) * @brGross, 2);
                            SET @legRunningSum += @legPropAmt;
                        END
                        ELSE
                            SET @legPropAmt = ROUND(@brGross - @legRunningSum, 2);

                        IF @legPropAmt > 0
                            INSERT INTO [dbo].[TicketDetails]
                                (TicketDate, SupplementaryNumber, BranchCode,
                                 ReferenceKey, TicketNumber, ReferenceNumber,
                                 AccountCode, Debit, Credit, CostCenter)
                            VALUES(@parmcheckdate, 0, @br, @parmvoucherid,
                                   @ticketnum, @parmrefno, '20103', @legPropAmt, 0, '');

                        SET @legrow += 1;
                    END;
                    DROP TABLE #LegLines;

                    -- ── CR legs: bank + EWT (still-to-withhold only) + discount + offset ──
                    IF @brNetCash > 0
                        INSERT INTO [dbo].[TicketDetails]
                            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
                        VALUES(@parmcheckdate, 0, @br, @parmvoucherid,
                               @ticketnum, @parmrefno, @parmglcode, 0, ROUND(@brNetCash,2), '');

                    IF @brEWT > 0
                        INSERT INTO [dbo].[TicketDetails]
                            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
                        VALUES(@parmcheckdate, 0, @br, @parmvoucherid,
                               @ticketnum, @parmrefno, '20104', 0, ROUND(@brEWT,2), '');

                    IF @brDisc > 0
                        INSERT INTO [dbo].[TicketDetails]
                            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
                        VALUES(@parmcheckdate, 0, @br, @parmvoucherid,
                               @ticketnum, @parmrefno, ISNULL(@invDiscAccountCode, '508'), 0, ROUND(@brDisc,2), '');

                    IF @brOffset > 0
                        INSERT INTO [dbo].[TicketDetails]
                            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
                        VALUES(@parmcheckdate, 0, @br, @parmvoucherid,
                               @ticketnum, @parmrefno, '40104', 0, ROUND(@brOffset,2), '');
                     IF @brFXLoss > 0
                        INSERT INTO [dbo].[TicketDetails]
                            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
                        VALUES(@parmcheckdate, 0, @br, @parmvoucherid,
                               @ticketnum, @parmrefno, '60310', ROUND(@brFXLoss,2), 0, '');
 
                    IF @brFXGain > 0
                        INSERT INTO [dbo].[TicketDetails]
                            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
                        VALUES(@parmcheckdate, 0, @br, @parmvoucherid,
                               @ticketnum, @parmrefno, '40510', 0, ROUND(@brFXGain,2), '');
 
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES(@parmvoucherid, @parmsupplierid, @parmrefno, @br,
                           @invInvoiceNo, @invInvDate, @brGross, 'EXPENSE PAYMENT',
                           @parmpaymethod, @parmvouchertype, @ticketnum,
                           '20103', @parmglcode,
                           CAST(@invBatchRef AS VARCHAR(50)), @invBatchRef);

                   
                    INSERT INTO [dbo].[SupplierLedger]
                        (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate,
                         Description, TransCode, TransactionDate, ReferenceNumber,
                         ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit,
                         EndingBalance, TransactedBy, ApprovedBy, TotalAmount,
                         PaymentType, ErrorCorrectTag, TicketReference, BatchReferenceID)
                    VALUES(@TransID, @SupplierKey, @parmsupplierid, @parmcheckdate,
                           LEFT(ISNULL(@parmcheckremarks,'EXPENSE PAYMENT'),490),
                           @brMnemonic, @parmcheckdate, @parmrefno,
                           CAST(@invBatchRef AS VARCHAR(40))+'-'+@br,
                           @invInvoiceNo, 0, @brGross, 0, @brGross,
                           @parmpreparedby, '*', @brGross, 'PARTIAL',
                           0, @ticketnum, @invBatchRef);

                    


                    SET @brrow += 1;
                END;
                
                    
                DROP TABLE #BranchTotals;
                SET @row += 1;
            END;
                        -- [88] H7: through the shared helper (one item per reference, account and side; a locked month is refused)
                        DECLARE @LegacyOcBranch2 VARCHAR(5) = ISNULL(@ocBranch, ISNULL(@br, '888'));
                        DECLARE @LegacyOcRemarks2 VARCHAR(500) = 'Auto-OC | '+LEFT(ISNULL(@allDescNames,''),200)+' | Ref: '+@parmrefno;
                        EXEC dbo.sp_Payment_PostBankReconEntry
                            @ItemType = 'OC', @BranchCode = @LegacyOcBranch2, @AccountCode = @parmglcode, @PeriodEnd = @ocPeriodEnd,
                            @ReferenceNo = @parmvoucherid, @ItemDate = @parmcheckdate, @Payee = @parmsuppliername, @Amount = @TotalNetCashForRecon,
                            @Remarks = @LegacyOcRemarks2, @SourceModule = 'AP-PAYMENT', @SourceRef = @parmrefno, @CreatedBy = @parmpreparedby;
        END;

        DROP TABLE #Lines;
       
     --IF ABS(@parmcheckamount - @TotalNetCashForRecon) > 0.01
     --    THROW 56010, 'Caller-supplied @parmcheckamount does not match the computed net cash — check how the caller is building this figure.', 1;

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.sp_PostSupplierAdjustmentMemo', 'sp_PostSupplierAdjustmentMemo_OLD_10172026210000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
-- =============================================================================
-- sp_PostSupplierAdjustmentMemo
--
-- One AP-side line (@APAccountCode / @APDebitCredit / @APAmount) + one or
-- more manually-entered offset lines (@OffsetLines TVP) that must balance
-- against it. Posts immediately - no approval workflow.
--
-- @InvoiceType drives which balance gets adjusted:
--   'PURCHASE'   -> APACCOUNTS.Balance (matched by SupplierID+InvoiceNo+SequenceNo)
--   'EXPENSE'    -> ExpenseSummary.Balance (matched by SupplierID+InvoiceNo+BatchReferenceID)
--   'ON-ACCOUNT' -> no invoice-level balance touched; only SupplierLedger/
--                   SupplierAccounts move (via the ledger trigger), since
--                   there's no specific invoice this adjustment settles.
--
-- APDebitCredit='C' -> AP balance INCREASES (DEBIT MEMO)
-- APDebitCredit='D' -> AP balance DECREASES (CREDIT MEMO)
--
-- Negative resulting balances are allowed (not blocked) - a credit memo
-- larger than the remaining invoice balance is a legitimate real-world
-- situation (overpayment-equivalent credit), same as how OVERPAY is
-- handled on the AR side. It's just reported as-is, not silently clamped.
-- =============================================================================

CREATE   PROCEDURE [dbo].[sp_PostSupplierAdjustmentMemo]
(
    @parmrefno        VARCHAR(10),      -- pre-generated by C# (IDGenerator/sp_GetReferenceNumber), matching your other posting SPs' convention
    @parmsupplierid   VARCHAR(100),
    @parmmemodate     DATE,
    @parminvoicetype  VARCHAR(15),      -- 'PURCHASE' / 'EXPENSE' / 'ON-ACCOUNT'
    @parminvoiceno    VARCHAR(150) = NULL,
    @parmbatchrefno   BIGINT       = NULL,
    @parmsequenceno   DECIMAL(18,0) = NULL,
    @parmbranchcode   VARCHAR(5),
    @parmremarks      VARCHAR(500),
    @parmuser         VARCHAR(50),
    @APAccountCode    VARCHAR(20),
    @APDebitCredit    CHAR(1),          -- 'D' or 'C'
    @APAmount         DECIMAL(18,2),
    @OffsetLines      dbo.SupplierMemoOffsetLineTVP READONLY
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        -- ── Validation ────────────────────────────────────────────
        IF @parminvoicetype NOT IN ('PURCHASE','EXPENSE','ON-ACCOUNT')
            THROW 58001, 'InvoiceType must be PURCHASE, EXPENSE, or ON-ACCOUNT.', 1;

        IF @APDebitCredit NOT IN ('D','C')
            THROW 58002, 'APDebitCredit must be D or C.', 1;

        IF @APAmount <= 0
            THROW 58003, 'APAmount must be greater than zero.', 1;

        IF @parminvoicetype = 'PURCHASE' AND (@parminvoiceno IS NULL OR @parmsequenceno IS NULL)
            THROW 58004, 'PURCHASE-type memos require both InvoiceNo and SequenceNo.', 1;

        IF @parminvoicetype = 'EXPENSE' AND (@parminvoiceno IS NULL OR @parmbatchrefno IS NULL)
            THROW 58005, 'EXPENSE-type memos require both InvoiceNo and BatchReferenceID.', 1;

        IF NOT EXISTS (SELECT 1 FROM @OffsetLines)
            THROW 58006, 'At least one offset line is required.', 1;

        -- Whole compound entry must balance: AP leg + offset lines
        DECLARE @totalDebit DECIMAL(18,2), @totalCredit DECIMAL(18,2);
        SELECT
            @totalDebit  = ISNULL(SUM(Debit), 0)  + CASE WHEN @APDebitCredit = 'D' THEN @APAmount ELSE 0 END,
            @totalCredit = ISNULL(SUM(Credit), 0) + CASE WHEN @APDebitCredit = 'C' THEN @APAmount ELSE 0 END
        FROM @OffsetLines;

        IF @totalDebit <> @totalCredit
            THROW 58007, 'Entry does not balance - total Debit must equal total Credit.', 1;

        DECLARE @supplierkey VARCHAR(15), @suppliername VARCHAR(150);
        SELECT @supplierkey = SupplierKey, @suppliername = SupplierName
        FROM Supplier WHERE SupplierID = @parmsupplierid;

        IF @supplierkey IS NULL
            THROW 58008, 'Supplier not found.', 1;

        DECLARE @ticketnum VARCHAR(20), @transid INT, @memoType VARCHAR(15);
        SET @memoType = CASE WHEN @APDebitCredit = 'C' THEN 'DEBIT MEMO' ELSE 'CREDIT MEMO' END;

        EXEC GetTicketNumber @ticketnum OUTPUT;
        SET @transid = dbo.func_getLastID(@supplierkey);

        -- ── TicketMaster / TicketDetails ──────────────────────────
        INSERT INTO [dbo].[TicketMaster]
            (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber,
             ReferenceNumber, ReferenceKey, Owner, Particulars,
             EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
        VALUES
            (@parmmemodate, 0, @parmbranchcode, 'ADJ', @ticketnum,
             @parmrefno, ISNULL(@parminvoiceno, @parmrefno), @suppliername,
             @memoType + ' | ' + ISNULL(@parmremarks,''),
             @parmuser, '*', '*', 'POSTED', @memoType, NULL);

        -- AP leg
        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        VALUES
            (@parmmemodate, 0, @parmbranchcode, ISNULL(@parminvoiceno, @parmrefno),
             @ticketnum, @parmrefno, @APAccountCode,
             CASE WHEN @APDebitCredit = 'D' THEN @APAmount ELSE 0 END,
             CASE WHEN @APDebitCredit = 'C' THEN @APAmount ELSE 0 END, '');

        -- Offset legs
        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        SELECT
            @parmmemodate, 0, @parmbranchcode, ISNULL(@parminvoiceno, @parmrefno),
            @ticketnum, @parmrefno, AccountCode, Debit, Credit, ''
        FROM @OffsetLines;

        -- ── SupplierLedger (drives SupplierAccounts.AccountBalance via trigger) ──
        INSERT INTO [dbo].[SupplierLedger]
            (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate,
             Description, TransCode, TransactionDate, ReferenceNumber,
             ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance,
             TransactedBy, ApprovedBy, TotalAmount, PaymentType,
             ErrorCorrectTag, TicketReference, BatchReferenceID)
        VALUES
            (@transid, @supplierkey, @parmsupplierid, @parmmemodate,
             @memoType + ' - ' + ISNULL(@parmremarks,''), @memoType, @parmmemodate,
             @parmrefno, ISNULL(@parminvoiceno, @parmrefno), @parminvoiceno,
             0,
             CASE WHEN @APDebitCredit = 'D' THEN @APAmount ELSE 0 END,
             CASE WHEN @APDebitCredit = 'C' THEN @APAmount ELSE 0 END,
             0,
             @parmuser, '*', @APAmount, @memoType,
             0, @ticketnum, @parmbatchrefno);

        -- ── Adjust the invoice-level balance, per InvoiceType ─────
        DECLARE @balanceDelta DECIMAL(18,2) = CASE WHEN @APDebitCredit = 'C' THEN @APAmount ELSE -@APAmount END;

        IF @parminvoicetype = 'PURCHASE'
        BEGIN
            UPDATE APACCOUNTS
            SET Balance   = Balance + @balanceDelta,
                PayStatus = CASE WHEN (Balance + @balanceDelta) <= 0 THEN 'PAID' ELSE 'PARTIAL' END
            WHERE SupplierID = @parmsupplierid
              AND InvoiceNo  = @parminvoiceno
              AND SequenceNo = @parmsequenceno;

            IF @@ROWCOUNT = 0
                THROW 58009, 'No matching APACCOUNTS row found for the given InvoiceNo/SequenceNo.', 1;
        END
        ELSE IF @parminvoicetype = 'EXPENSE'
        BEGIN
            -- [105] 2026-10-17: a loan's payable moves only with the loan (Loan Revaluation) and its payments (Vouchering Telegraphic)
            IF EXISTS (SELECT 1 FROM ExpenseSummary WHERE SupplierID = @parmsupplierid AND InvoiceNo = @parminvoiceno
                       AND BatchReferenceID = @parmbatchrefno AND PostingMode = 'LOAN')
                THROW 58041, 'This invoice is a loan (Loan Revaluation): adjust it with a revaluation or pay it in Vouchering Telegraphic, not with a memo. Nothing was posted.', 1;
            UPDATE ExpenseSummary
            SET Balance         = ISNULL(Balance, ISNULL(Amount,0)) + @balanceDelta,
                Status          = CASE WHEN (ISNULL(Balance, ISNULL(Amount,0)) + @balanceDelta) <= 0 THEN 'PAID' ELSE 'PARTIAL' END,
                UpdatedBy       = @parmuser,
                DateTimeUpdated = GETDATE()
            WHERE SupplierID       = @parmsupplierid
              AND InvoiceNo        = @parminvoiceno
              AND BatchReferenceID = @parmbatchrefno;

            IF @@ROWCOUNT = 0
                THROW 58010, 'No matching ExpenseSummary row found for the given InvoiceNo/BatchReferenceID.', 1;
        END
        -- ON-ACCOUNT: nothing further to update - SupplierLedger insert above
        -- already drives SupplierAccounts.AccountBalance via the trigger.

        -- ── Header + detail audit records ─────────────────────────
        DECLARE @memoID INT;

        INSERT INTO dbo.SupplierAdjustmentMemo
            (ReferenceNo, MemoType, SupplierID, SupplierKey, MemoDate,
             InvoiceType, InvoiceNo, BatchReferenceID, SequenceNo, BranchCode,
             APAccountCode, APDebitCredit, APAmount, Reason, PreparedBy, TicketNumber)
        VALUES
            (@parmrefno, @memoType, @parmsupplierid, @supplierkey, @parmmemodate,
             @parminvoicetype, @parminvoiceno, @parmbatchrefno, @parmsequenceno, @parmbranchcode,
             @APAccountCode, @APDebitCredit, @APAmount, @parmremarks, @parmuser, @ticketnum);

        SET @memoID = SCOPE_IDENTITY();

        INSERT INTO dbo.SupplierAdjustmentMemoDetails (MemoID, AccountCode, Debit, Credit, Particulars)
        SELECT @memoID, AccountCode, Debit, Credit, Particulars
        FROM @OffsetLines;

        COMMIT TRAN;

        SELECT 1 AS Status, @parmrefno AS ReferenceNo, @ticketnum AS TicketNumber, @memoType AS MemoType,
               'Adjustment memo posted successfully.' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH;
END;
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.view_ExpenseSummary', 'view_ExpenseSummary_OLD_10172026210000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
 CREATE VIEW [dbo].[view_ExpenseSummary]
 AS
 SELECT 
	b.SupplierID
	,b.SupplierName
	--,a.ExpenseDate
	--,CAST(a.ExpenseDate AS DATE) AS ExpenseDate
	,FORMAT(CAST(a.ExpenseDate AS DATE),'yyyy-MM-dd') AS ExpenseDate
	,a.InvoiceNo
	,a.ReferenceNumber
	,UPPER(a.Description) AS Description
	,FORMAT(a.Amount,'N2') AS Amount
	,a.Status
	,UPPER(a.AddedBy) AS AddedBy
	,FORMAT(CAST(a.DateTimeAdded AS DATE),'yyyy-MM-dd') AS DateTimeAdded
	,a.BatchReferenceID
 FROM ExpenseSummary a
 INNER JOIN Supplier b
	ON a.SupplierID=b.SupplierID
 WHERE ISNULL(a.PostingMode, '') <> 'LOAN'   -- [105] 2026-10-17: a loan payable is not an expense (old expense screens list, reverse and edit from here)
GO


------------------------------------------------------------------
-- 7b. The loan as a payable, at its current position (balance forward of July + the revaluations posted since).
--     Last before the post-check: the two counters it takes stay locked until COMMIT.
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @loan INT, @code VARCHAR(30), @sup VARCHAR(50), @supKey CHAR(6), @branch VARCHAR(5), @liab VARCHAR(20), @desc VARCHAR(300), @cur CHAR(3);
DECLARE @openDate DATE, @openTicket VARCHAR(20), @pBal DECIMAL(18,2), @fBal DECIMAL(18,2), @sumChg DECIMAL(18,2), @gl DECIMAL(18,2);
DECLARE @batchTxt VARCHAR(10), @batch BIGINT, @refInt INT, @ref VARCHAR(10), @text VARCHAR(300), @m NVARCHAR(400), @n INT = 0;

DECLARE cl CURSOR LOCAL FAST_FORWARD FOR
    SELECT a.LoanID FROM dbo.LoanAccount AS a
    WHERE a.IsActive = 1 AND a.PayableBatchReferenceID IS NULL
      AND EXISTS (SELECT 1 FROM dbo.LoanTransaction t WHERE t.LoanID = a.LoanID AND t.Status = 'POSTED')
    ORDER BY a.LoanID;
OPEN cl;
FETCH NEXT FROM cl INTO @loan;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @code = a.LoanCode, @sup = a.SupplierID, @supKey = s.SupplierKey, @branch = a.BranchCode, @liab = a.LiabilityAccount,
           @desc = a.Description, @cur = a.Currency
    FROM dbo.LoanAccount AS a LEFT JOIN dbo.Supplier AS s ON s.SupplierID = a.SupplierID
    WHERE a.LoanID = @loan;
    SELECT TOP 1 @openDate = TxnDate, @openTicket = ISNULL(NULLIF(LTRIM(RTRIM(TicketNumber)), ''), '1')
    FROM dbo.LoanTransaction WHERE LoanID = @loan AND Status = 'POSTED' AND TxnType = 'OPENING' ORDER BY TxnDate, TxnID;
    SELECT TOP 1 @pBal = PhpBalance, @fBal = ForeignBalance
    FROM dbo.LoanTransaction WHERE LoanID = @loan AND Status = 'POSTED' ORDER BY TxnDate DESC, TxnID DESC;
    SET @sumChg = (SELECT SUM(PhpChange) FROM dbo.LoanTransaction WHERE LoanID = @loan AND Status = 'POSTED');
    SET @gl = ISNULL((SELECT SUM(ISNULL(d.Credit, 0) - ISNULL(d.Debit, 0)) FROM dbo.TicketDetails AS d
                      WHERE d.AccountCode = @liab AND d.BranchCode = @branch), 0);
    IF @supKey IS NULL OR @openDate IS NULL OR @sumChg <> @pBal OR @gl <> @pBal
    BEGIN
        SET @m = N'[105] loan ' + ISNULL(@code, N'?') + N': supplier ' + ISNULL(@sup, N'?') + N' / opening / entries ' + ISNULL(CONVERT(NVARCHAR(30), @sumChg), N'?')
               + N' / GL ' + CONVERT(NVARCHAR(30), @gl) + N' do not agree with its balance ' + ISNULL(CONVERT(NVARCHAR(30), @pBal), N'?') + N'; nothing changed.';
        THROW 59951, @m, 1;
    END
    IF EXISTS (SELECT 1 FROM dbo.ExpenseSummary WHERE SupplierID = @sup AND InvoiceNo = @code)
       OR EXISTS (SELECT 1 FROM dbo.SupplierLedger WHERE SupplierKey = @supKey AND InvoiceNo = @code)
    BEGIN
        SET @m = N'[105] loan ' + @code + N': an expense or ledger row with that invoice no. already exists; nothing changed.';
        THROW 59952, @m, 1;
    END

    EXEC dbo.GetBatchReferenceID @batchTxt OUTPUT;
    SET @batch = CAST(@batchTxt AS BIGINT);
    IF ISNULL(@batch, 0) <= 0 THROW 59954, '[105] the batch-reference counter returned 0 (wrapping); nothing changed.', 1;
    UPDATE dbo.ReferenceNumber WITH (TABLOCKX, HOLDLOCK)
    SET @refInt = ReferenceNumber, ReferenceNumber = CASE WHEN ReferenceNumber > 99999 THEN 1 ELSE ReferenceNumber + 1 END;
    IF @refInt IS NULL OR @refInt > 99999 THROW 59953, '[105] the reference-number counter is empty or wrapping; nothing changed.', 1;
    SET @ref = CONVERT(VARCHAR(10), @refInt);
    SET @text = LEFT(ISNULL(@desc, @code) + ' - PRINCIPAL ' + @cur + ' ' + FORMAT(@fBal, 'N2', 'en-US') + ' (revalued every month end, Loan Revaluation)', 300);

    INSERT INTO dbo.ExpenseSummary
        (ReferenceNumber, InvoiceNo, SupplierID, Description, BatchReferenceID, Status, Amount, ExpenseDate, AddedBy, DateTimeAdded,
         Balance, AmountPaid, ShipmentNo, PostingMode, PayableAccountCode)
    VALUES (@ref, @code, @sup, @text, @batch, 'POSTED', @pBal, @openDate, 'SCRIPT [105]', GETDATE(),
            @pBal, 0, NULL, 'LOAN', @liab);
    INSERT INTO dbo.ExpenseMaster
        (TRN_SEQ_NO, BranchCode, SupplierID, ReferenceNumber, BatchReferenceID, InvoiceNo, ExpenseName, ExpenseDate,
         Amount, Remarks, Status, Balance, AmountPaid, TicketReference, IsEWTPostedAtAccrual)
    VALUES (1, @branch, @sup, CAST(@ref AS DECIMAL(18,0)), @batch, @code, @text, @openDate,
            @pBal, 'D-' + @text, 'UNPAID', @pBal, 0, @openTicket, 0);

    -- supplier ledger: one row per POSTED loan entry, in date order (the recalc trigger re-chains the balances)
    DECLARE @tDate DATE, @tType VARCHAR(15), @tChg DECIMAL(18,2), @tTicket VARCHAR(20), @tRef VARCHAR(20), @tDesc VARCHAR(300);
    DECLARE ct CURSOR LOCAL FAST_FORWARD FOR
        SELECT TxnDate, TxnType, PhpChange, TicketNumber, ReferenceNumber, Description
        FROM dbo.LoanTransaction WHERE LoanID = @loan AND Status = 'POSTED' ORDER BY TxnDate, TxnID;
    OPEN ct;
    FETCH NEXT FROM ct INTO @tDate, @tType, @tChg, @tTicket, @tRef, @tDesc;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO dbo.SupplierLedger
            (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate, Description, TransCode, TransactionDate, ReferenceNumber,
             ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, TransactedBy, ApprovedBy, TotalAmount,
             PaymentType, ErrorCorrectTag, TicketReference, BatchReferenceID)
        VALUES (dbo.func_getLastID(@sup), @supKey, @sup, @tDate,
                LEFT(CASE WHEN @tType = 'OPENING' THEN 'BALANCE FORWARD ' + @text ELSE ISNULL(@tDesc, @code + ' - FOREX REVALUATION') END, 490),
                CASE WHEN @tType = 'OPENING' THEN 'LOAN-BF' ELSE 'LOAN-REVAL' END, @tDate,
                CASE WHEN @tType = 'OPENING' THEN @ref ELSE ISNULL(@tRef, @ref) END,
                CAST(@batch AS VARCHAR(40)) + '-' + @branch, @code, 0,
                CASE WHEN @tChg < 0 THEN -@tChg ELSE 0 END, CASE WHEN @tChg > 0 THEN @tChg ELSE 0 END, 0,
                'SCRIPT [105]', '*', ABS(@tChg), CASE WHEN @tType = 'OPENING' THEN 'UNPAID' ELSE 'REVALUATION' END, 0,
                CASE WHEN @tType = 'OPENING' THEN @openTicket ELSE @tTicket END, @batch);
        FETCH NEXT FROM ct INTO @tDate, @tType, @tChg, @tTicket, @tRef, @tDesc;
    END
    CLOSE ct; DEALLOCATE ct;

    UPDATE dbo.LoanAccount SET PayableBatchReferenceID = @batch WHERE LoanID = @loan;
    SET @n += 1;
    PRINT '[105] loan ' + @code + ': payable ' + @ref + ' / batch ' + @batchTxt + ' = ' + FORMAT(@pBal, 'N2', 'en-US') + ' (' + @sup + ', ' + @liab + ', branch ' + @branch + ')';
    FETCH NEXT FROM cl INTO @loan;
END
CLOSE cl; DEALLOCATE cl;
PRINT '[105] loan payables created: ' + CAST(@n AS VARCHAR(10));
GO

------------------------------------------------------------------
-- 8. Post-check, then commit
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.spu_Loan_PostRevaluation')), N'') NOT LIKE '%THROW 62032%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.spu_Loan_ReverseRevaluation')), N'') NOT LIKE '%THROW 62032%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_Loan_GetAccounts')), N'') NOT LIKE '%PayableBalance%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostVoucherManual')), N'') NOT LIKE '%THROW 58040%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.splist_Accounts')), N'') NOT LIKE '%[[]105]%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetUnpaidInvoicesForSupplier')), N'') NOT LIKE '%[[]105]%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2')), N'') NOT LIKE '%THROW 60540%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound')), N'') NOT LIKE '%THROW 60540%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.view_ExpenseSummary')), N'') NOT LIKE '%[[]105]%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostSupplierAdjustmentMemo')), N'') NOT LIKE '%THROW 58041%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.spu_Loan_PostRevaluation')), N'') NOT LIKE '%THROW 62033%'
    SET @msg = N'a proc is not the [105] text';
ELSE IF OBJECT_ID('dbo.spu_Loan_PostRevaluation_OLD_10172026210000', 'P') IS NULL OR OBJECT_ID('dbo.spu_Loan_ReverseRevaluation_OLD_10172026210000', 'P') IS NULL
     OR OBJECT_ID('dbo.sp_Loan_GetAccounts_OLD_10172026210000', 'P') IS NULL OR OBJECT_ID('dbo.sp_PostVoucherManual_OLD_10172026210000', 'P') IS NULL
     OR OBJECT_ID('dbo.splist_Accounts_OLD_10172026210000', 'P') IS NULL OR OBJECT_ID('dbo.sp_GetUnpaidInvoicesForSupplier_OLD_10172026210000', 'P') IS NULL
     OR OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2_OLD_10172026210000', 'P') IS NULL OR OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_OLD_10172026210000', 'P') IS NULL
     OR OBJECT_ID('dbo.view_ExpenseSummary_OLD_10172026210000', 'V') IS NULL OR OBJECT_ID('dbo.sp_PostSupplierAdjustmentMemo_OLD_10172026210000', 'P') IS NULL
    SET @msg = N'a backup is missing';
ELSE IF EXISTS (SELECT 1 FROM dbo.LoanAccount a
                WHERE a.IsActive = 1 AND EXISTS (SELECT 1 FROM dbo.LoanTransaction t WHERE t.LoanID = a.LoanID AND t.Status = 'POSTED')
                  AND (a.PayableBatchReferenceID IS NULL
                       OR NOT EXISTS (SELECT 1 FROM dbo.ExpenseSummary es
                                      WHERE es.BatchReferenceID = a.PayableBatchReferenceID AND es.SupplierID = a.SupplierID AND es.PostingMode = 'LOAN'
                                        AND CAST(es.Balance AS DECIMAL(18,2)) = CAST(es.Amount AS DECIMAL(18,2))
                                        AND CAST(es.Balance AS DECIMAL(18,2)) = ISNULL((SELECT SUM(ISNULL(d.Credit, 0) - ISNULL(d.Debit, 0)) FROM dbo.TicketDetails d WHERE d.AccountCode = a.LiabilityAccount AND d.BranchCode = a.BranchCode), 0)
                                        AND CAST(es.Balance AS DECIMAL(18,2)) = ISNULL((SELECT SUM(ISNULL(l.Credit, 0) - ISNULL(l.Debit, 0)) FROM dbo.SupplierLedger l WHERE l.SupplierKey = a.SupplierID AND l.InvoiceNo = es.InvoiceNo AND l.BatchReferenceID = es.BatchReferenceID), 0)
                                        AND CAST(es.Balance AS DECIMAL(18,2)) = ISNULL((SELECT SUM(m.Balance) FROM dbo.ExpenseMaster m WHERE m.SupplierID = es.SupplierID AND m.InvoiceNo = es.InvoiceNo AND m.BatchReferenceID = es.BatchReferenceID), 0))))
    SET @msg = N'a loan payable is missing or does not equal its GL / ledger / line';

IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[105] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59897, @msg, 1;
END

COMMIT TRANSACTION;
PRINT '[105] committed: loan payables created and kept in step by the revaluation; Vouchering Telegraphic pays them from the loan''s branch.';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
