/* ================================================================
   [65] 2026-10-12h - Loan Revaluation (foreign-currency loans; first: PROFOOD GMBH EUR 800,000)
   ================================================================
   Plan: docs/plans/2026-10-12_PROFOOD_Loan_FX_Plan.md. User 2026-10-12: build it with the defaults
   (forex account 60323 as in Peachtree, no branch allocation yet, revaluations only) and apply on STAGING.

   New objects only (nothing existing changes):
     * dbo.LoanAccount          one row per loan: code, lender, currency, branch, liability GL account.
     * dbo.LoanTransaction      the loan's history: OPENING, then one REVALUATION per month end, each with the
                                rate, the foreign and peso change and the running balances, its reference no. and ticket.
     * JournalEntryMapping      LOAN-REVAL: FXLOSS = DR 60323, FXGAIN = CR 60323 (REALIZED GAIN/LOSS ON FOREX, the
                                account Peachtree used: 6041 FRZ-Realized gain/loss-Forex). The liability side is the
                                loan's own LiabilityAccount (20203).
     * sp_Loan_GetAccounts      loans with balance, last rate / date, the GL balance of the liability account
                                (branch) and the mapped forex accounts.
     * sp_Loan_GetTransactions  a loan's history (Posted tab).
     * sp_Loan_GetTicketLines   the GL lines of a transaction (and of its reversal).
     * spu_Loan_PostRevaluation month-end revaluation: new peso balance = foreign balance x new rate; the difference is
                                posted on the loan's branch, dated the month end:
                                  liability up   (rate up, loss):   DR forex loss / CR liability
                                  liability down (rate down, gain): DR liability  / CR forex gain
                                Rules: month-end date, after the loan's last transaction (so one per month, in order),
                                rate > 0, stale-screen guard (@ExpectedPhpBalance), nothing to post if 0, mapping must
                                exist; a closed GL month is refused by the period-lock trigger (59900).
     * spu_Loan_ReverseRevaluation  only the latest revaluation of a loan; mirror ticket dated like the original
                                (reversal rule of 2026-10-09); reason required.
   Data: loan LOAN051618 (PROFOOD GMBH 000125, EUR, branch 888, 20203) with its opening 2026-07-31:
   EUR 800,000.00 @ 70.5095 = 56,407,600.00 (= the 07-31 opening ticket 1 on 20203 and Peachtree's 07-31 balance; no posting).
   The script stops (nothing installed) unless GL 20203 on 888 at 07-31 is exactly that.
   Errors 62001-62020.

   After the reviews (2026-10-13):
     * 62020: a revaluation is refused unless GL <liability> on the branch, up to the revaluation date, equals the loan's
       balance (e.g. a month already entered by hand as a Manual JV would otherwise be counted twice).
     * 62016: the next revaluation must be the month right after the last entry, and not ahead of the current month.
     * 62007 also when the mapped forex account isn't in the chart of accounts or is the loan's own account.
     * Contract for callers (exe and web v2): call the procs outside any transaction of your own. Under XACT_ABORT a
       refusal inside a caller's transaction rolls the caller's whole transaction back. @User comes from the caller
       (shared SQL login, as everywhere in this system): the caller authorises the user (admins / accounting).

   One transaction with a post-check. DEV and STAGING; PRODUCTION by the user.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

IF OBJECT_ID('dbo.LoanAccount', 'U') IS NOT NULL OR OBJECT_ID('dbo.spu_Loan_PostRevaluation', 'P') IS NOT NULL
BEGIN
    RAISERROR('This script has been run here before (dbo.LoanAccount exists); nothing was run.', 16, 1);
    SET NOEXEC ON;
END
GO
IF NOT EXISTS (SELECT 1 FROM dbo.ChartOfAccounts WHERE AccountCode = '60323') OR NOT EXISTS (SELECT 1 FROM dbo.ChartOfAccounts WHERE AccountCode = '20203')
BEGIN
    RAISERROR('Accounts 60323 / 20203 are missing from ChartOfAccounts; nothing was run.', 16, 1);
    SET NOEXEC ON;
END
GO
-- review S1: the opening loaded below must be what the GL says at 07-31 (20203, branch 888)
IF ISNULL((SELECT SUM(ISNULL(Credit, 0) - ISNULL(Debit, 0)) FROM dbo.TicketDetails
           WHERE AccountCode = '20203' AND BranchCode = '888' AND TicketDate < '2026-08-01'), 0) <> 56407600.00
BEGIN
    RAISERROR('GL 20203 on branch 888 at 2026-07-31 is not 56,407,600.00, the opening this script loads; nothing was run. Check the account first.', 16, 1);
    SET NOEXEC ON;
END
GO

BEGIN TRANSACTION;
GO

CREATE TABLE dbo.LoanAccount
(
    LoanID           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_LoanAccount PRIMARY KEY,
    LoanCode         VARCHAR(30)   NOT NULL CONSTRAINT UQ_LoanAccount_Code UNIQUE,
    SupplierID       VARCHAR(50)   NOT NULL,
    Description      VARCHAR(200)  NOT NULL,
    Currency         CHAR(3)       NOT NULL,
    BranchCode       VARCHAR(5)    NOT NULL,
    LiabilityAccount VARCHAR(20)   NOT NULL,
    IsActive         BIT           NOT NULL CONSTRAINT DF_LoanAccount_IsActive DEFAULT (1),
    CreatedBy        VARCHAR(60)   NOT NULL,
    CreatedAt        DATETIME2(0)  NOT NULL CONSTRAINT DF_LoanAccount_CreatedAt DEFAULT (SYSDATETIME())
);

CREATE TABLE dbo.LoanTransaction
(
    TxnID                INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_LoanTransaction PRIMARY KEY,
    LoanID               INT           NOT NULL CONSTRAINT FK_LoanTransaction_Loan REFERENCES dbo.LoanAccount (LoanID),
    TxnDate              DATE          NOT NULL,
    TxnType              VARCHAR(15)   NOT NULL,
    Rate                 DECIMAL(18,6) NOT NULL,          -- the loan's rate after this transaction (pesos per foreign unit)
    PrevRate             DECIMAL(18,6) NULL,
    ForeignChange        DECIMAL(18,2) NOT NULL,          -- + = more owed in foreign currency
    PhpChange            DECIMAL(18,2) NOT NULL,          -- + = liability up (forex loss), - = down (forex gain)
    ForeignBalance       DECIMAL(18,2) NOT NULL,          -- after this transaction
    PhpBalance           DECIMAL(18,2) NOT NULL,          -- after this transaction (= GL liability while nothing else posts there)
    ReferenceNumber      VARCHAR(20)   NULL,
    TicketNumber         VARCHAR(20)   NULL,
    Description          VARCHAR(300)  NULL,
    Status               VARCHAR(10)   NOT NULL CONSTRAINT DF_LoanTransaction_Status DEFAULT ('POSTED'),
    PostedBy             VARCHAR(60)   NOT NULL,
    PostedAt             DATETIME2(0)  NOT NULL CONSTRAINT DF_LoanTransaction_PostedAt DEFAULT (SYSDATETIME()),
    ReversedBy           VARCHAR(60)   NULL,
    ReversedAt           DATETIME2(0)  NULL,
    ReverseReason        VARCHAR(300)  NULL,
    ReversalTicketNumber VARCHAR(20)   NULL,
    CONSTRAINT CK_LoanTransaction_Type CHECK (TxnType IN ('OPENING', 'REVALUATION')),
    CONSTRAINT CK_LoanTransaction_Status CHECK (Status IN ('POSTED', 'REVERSED'))
);
CREATE UNIQUE INDEX UX_LoanTransaction_OneOpening ON dbo.LoanTransaction (LoanID) WHERE TxnType = 'OPENING';
CREATE INDEX IX_LoanTransaction_Loan ON dbo.LoanTransaction (LoanID, TxnDate, TxnID);
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- forex accounts of the revaluation (configurable; never hard-coded in the procs)
INSERT INTO dbo.JournalEntryMapping
    (Origin, Mnemonic, Description, Seq, DebitCredit, AccountCode, AccountDescription, IsConditional, IsAmountFromSource, IsActive, Notes, AmountType, ConditionFlag)
SELECT 'LOAN', 'LOAN-REVAL', v.Description, v.Seq, v.DC, '60323', (SELECT Description FROM dbo.ChartOfAccounts WHERE AccountCode = '60323'),
       1, 0, 1, 'Loan Revaluation (2026-10-12h): forex on foreign-currency loans; the other side is LoanAccount.LiabilityAccount', v.AmountType, v.Flag
FROM (VALUES (1, 'D', 'Loan Revaluation - Forex Loss', 'FXLOSS', 'HasFXLoss'),
             (2, 'C', 'Loan Revaluation - Forex Gain', 'FXGAIN', 'HasFXGain')) AS v (Seq, DC, Description, AmountType, Flag)
WHERE NOT EXISTS (SELECT 1 FROM dbo.JournalEntryMapping AS m WHERE m.Mnemonic = 'LOAN-REVAL' AND m.AmountType = v.AmountType);

-- the PROFOOD GMBH loan and its opening (07-31, = GL 20203 and Peachtree; no posting)
INSERT INTO dbo.LoanAccount (LoanCode, SupplierID, Description, Currency, BranchCode, LiabilityAccount, CreatedBy)
VALUES ('LOAN051618', '000125', 'PROFOOD GMBH - EUR LOAN', 'EUR', '888', '20203', 'SCRIPT 2026-10-12h');
INSERT INTO dbo.LoanTransaction (LoanID, TxnDate, TxnType, Rate, PrevRate, ForeignChange, PhpChange, ForeignBalance, PhpBalance, Description, PostedBy)
SELECT LoanID, '2026-07-31', 'OPENING', 70.5095, NULL, 800000.00, 56407600.00, 800000.00, 56407600.00,
       'OPENING 07.31.26 (E800000 @70.5095) - Peachtree balance and GL 20203 opening ticket 1', 'SCRIPT 2026-10-12h'
FROM dbo.LoanAccount WHERE LoanCode = 'LOAN051618';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
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
           @gain AS GainAccount, (SELECT Description FROM dbo.ChartOfAccounts WHERE AccountCode = @gain) AS GainAccountName
    FROM dbo.LoanAccount AS a
    LEFT JOIN dbo.Supplier AS s ON s.SupplierID = a.SupplierID
    LEFT JOIN dbo.Branches AS b ON b.BranchCode = a.BranchCode
    LEFT JOIN dbo.ChartOfAccounts AS la ON la.AccountCode = a.LiabilityAccount
    OUTER APPLY (SELECT TOP 1 x.TxnDate, x.TxnType, x.Rate, x.ForeignBalance, x.PhpBalance FROM dbo.LoanTransaction AS x
                 WHERE x.LoanID = a.LoanID AND x.Status = 'POSTED' ORDER BY x.TxnDate DESC, x.TxnID DESC) AS t
    OUTER APPLY (SELECT SUM(ISNULL(d.Credit, 0) - ISNULL(d.Debit, 0)) AS Bal FROM dbo.TicketDetails AS d
                 WHERE d.AccountCode = a.LiabilityAccount AND d.BranchCode = a.BranchCode) AS gl
    WHERE a.IsActive = 1
    ORDER BY a.LoanCode;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

CREATE PROCEDURE dbo.sp_Loan_GetTransactions
    @LoanID INT
AS
/*  Read-only. A loan's history, oldest first. Caller: LoanRevaluationFrm (Posted tab). */
BEGIN
    SET NOCOUNT ON;
    SELECT t.TxnID, t.TxnDate, t.TxnType, t.PrevRate, t.Rate, CAST(t.Rate - t.PrevRate AS DECIMAL(18,6)) AS RateChange,
           t.ForeignChange, t.PhpChange,
           CASE WHEN t.TxnType = 'REVALUATION' AND t.PhpChange > 0 THEN 'LOSS' WHEN t.TxnType = 'REVALUATION' AND t.PhpChange < 0 THEN 'GAIN' ELSE '' END AS GainLoss,
           t.ForeignBalance, t.PhpBalance, t.ReferenceNumber, t.TicketNumber, t.Description, t.Status,
           t.PostedBy, t.PostedAt, t.ReversedBy, t.ReversedAt, t.ReverseReason, t.ReversalTicketNumber
    FROM dbo.LoanTransaction AS t
    WHERE t.LoanID = @LoanID
    ORDER BY t.TxnDate, t.TxnID;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

CREATE PROCEDURE dbo.sp_Loan_GetTicketLines
    @TxnID INT
AS
/*  Read-only. The GL lines of a loan transaction's ticket and, if reversed, of its reversal ticket. */
BEGIN
    SET NOCOUNT ON;
    SELECT CASE WHEN d.TicketNumber = t.TicketNumber THEN 'POSTING' ELSE 'REVERSAL' END AS Entry,
           d.TicketNumber, CAST(d.TicketDate AS DATE) AS TicketDate, d.BranchCode, d.ReferenceNumber,
           d.AccountCode, coa.Description AS AccountName, d.Debit, d.Credit
    FROM dbo.LoanTransaction AS t
    INNER JOIN dbo.LoanAccount AS a ON a.LoanID = t.LoanID
    INNER JOIN dbo.TicketDetails AS d ON d.BranchCode = a.BranchCode AND d.TicketNumber IN (t.TicketNumber, t.ReversalTicketNumber)
                                     AND d.ReferenceNumber = t.ReferenceNumber
    LEFT JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = d.AccountCode
    WHERE t.TxnID = @TxnID
    ORDER BY CASE WHEN d.TicketNumber = t.TicketNumber THEN 0 ELSE 1 END, d.Debit DESC, d.Credit DESC;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

CREATE PROCEDURE dbo.spu_Loan_PostRevaluation
    @LoanID              INT,
    @RevalDate           DATE,
    @Rate                DECIMAL(18,6),
    @ExpectedPhpBalance  DECIMAL(18,2),        -- the peso balance the screen showed (stale-screen guard)
    @User                VARCHAR(60),
    @Description         VARCHAR(300) = NULL   -- blank = 'LOANCODE - FOREX REVALUATION mm.dd.yy (E800000 @1.7147)'
AS
/*  Month-end revaluation of a foreign-currency loan: new peso balance = foreign balance x @Rate, rounded to centavos;
    the difference to the current peso balance is posted on the loan's branch, dated @RevalDate:
      liability up (loss):   DR forex loss (LOAN-REVAL FXLOSS) / CR the loan's LiabilityAccount
      liability down (gain): DR the loan's LiabilityAccount    / CR forex gain (LOAN-REVAL FXGAIN)
    Errors 62001-62009, 62016, 62018-62020 (refusals); a closed GL month is refused by the period-lock trigger (59900).
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
        -- review S1: the loan must agree with the GL. If anything else was booked to the liability account on the branch
        -- up to this date (e.g. a revaluation already entered by hand as a Manual JV), posting would count it twice.
        DECLARE @glBal DECIMAL(18,2) = ISNULL((SELECT SUM(ISNULL(d.Credit, 0) - ISNULL(d.Debit, 0)) FROM dbo.TicketDetails AS d
                                               WHERE d.AccountCode = @liab AND d.BranchCode = @branch
                                                 AND d.TicketDate < DATEADD(DAY, 1, CAST(@RevalDate AS DATETIME))), 0);
        IF @glBal <> @pBal
        BEGIN
            SET @msg = N'GL ' + @liab + N' on branch ' + @branch + N' up to ' + CONVERT(NVARCHAR(10), @RevalDate, 120) + N' is '
                     + CONVERT(NVARCHAR(30), @glBal) + N' but the loan says ' + CONVERT(NVARCHAR(30), @pBal)
                     + N' (difference ' + CONVERT(NVARCHAR(30), @glBal - @pBal) + N'). Something else was posted to that account '
                     + N'(e.g. this revaluation entered by hand); sort it out first so it isn''t counted twice.';
            THROW 62020, @msg, 1;
        END

        DECLARE @newBal DECIMAL(18,2) = ROUND(@fBal * @Rate, 2);
        DECLARE @change DECIMAL(18,2) = @newBal - @pBal;
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
                             + FORMAT(@fBal, '0.##', 'en-US') + ' @' + FORMAT(ABS(@Rate - @lastRate), '0.####', 'en-US') + ')';

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
            (@RevalDate, 0, @branch, 'JV', @tn, @refno, @code, @supplier, @Description,
             @User, '*', '*', 'POSTED', 'LOAN-REVAL', NULL);

        INSERT INTO dbo.TicketDetails
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey, TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        SELECT @RevalDate, 0, @branch, @code, @tn, @refno, l.AccountCode, l.Debit, l.Credit, ''
        FROM (VALUES (1, CASE WHEN @change > 0 THEN @lossAcct ELSE @liab END, ABS(@change), CAST(0 AS DECIMAL(18,2))),
                     (2, CASE WHEN @change > 0 THEN @liab ELSE @gainAcct END, CAST(0 AS DECIMAL(18,2)), ABS(@change))) AS l (Seq, AccountCode, Debit, Credit)
        ORDER BY l.Seq;

        INSERT INTO dbo.LoanTransaction
            (LoanID, TxnDate, TxnType, Rate, PrevRate, ForeignChange, PhpChange, ForeignBalance, PhpBalance, ReferenceNumber, TicketNumber, Description, PostedBy)
        VALUES
            (@LoanID, @RevalDate, 'REVALUATION', @Rate, @lastRate, 0, @change, @fBal, @newBal, @refno, @tn, @Description, LEFT(@User, 60));
        DECLARE @txn INT = SCOPE_IDENTITY();

        IF (SELECT SUM(Debit) - SUM(Credit) FROM dbo.TicketDetails WHERE TicketNumber = @tn AND ReferenceNumber = @refno AND BranchCode = @branch) <> 0
            THROW 62019, 'Post-check: the revaluation ticket does not balance; nothing was posted.', 1;

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
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

CREATE PROCEDURE dbo.spu_Loan_ReverseRevaluation
    @TxnID   INT,
    @User    VARCHAR(60),
    @Reason  VARCHAR(300)
AS
/*  Reverses a loan's LATEST revaluation (a later one depends on it): a mirror ticket of its GL lines, dated like the
    original (the reversal rule of 2026-10-09; a closed month is refused by the lock trigger, 59900), and the transaction
    is marked REVERSED, so the loan's balance and rate go back to the entry before it. Errors 62011-62015. */
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

        IF (SELECT SUM(Debit) - SUM(Credit) FROM dbo.TicketDetails WHERE ReferenceNumber = @refno AND BranchCode = @branch AND TicketNumber IN (@tn, @rtn)) <> 0
            THROW 62019, 'Post-check: the revaluation and its reversal do not net to zero; nothing was reversed.', 1;

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
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

IF OBJECT_ID('dbo.LoanAccount', 'U') IS NULL OR OBJECT_ID('dbo.LoanTransaction', 'U') IS NULL
   OR OBJECT_ID('dbo.sp_Loan_GetAccounts', 'P') IS NULL OR OBJECT_ID('dbo.sp_Loan_GetTransactions', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_Loan_GetTicketLines', 'P') IS NULL OR OBJECT_ID('dbo.spu_Loan_PostRevaluation', 'P') IS NULL
   OR OBJECT_ID('dbo.spu_Loan_ReverseRevaluation', 'P') IS NULL
   OR (SELECT COUNT(*) FROM dbo.JournalEntryMapping WHERE Mnemonic = 'LOAN-REVAL' AND IsActive = 1) <> 2
   OR NOT EXISTS (SELECT 1 FROM dbo.LoanTransaction t INNER JOIN dbo.LoanAccount a ON a.LoanID = t.LoanID
                  WHERE a.LoanCode = 'LOAN051618' AND t.TxnType = 'OPENING' AND t.PhpBalance = 56407600.00 AND t.ForeignBalance = 800000.00)
BEGIN
    RAISERROR('Post-check failed; rolled back.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
COMMIT TRANSACTION;
PRINT 'Loan Revaluation installed (LOAN051618: EUR 800,000.00 @ 70.5095 = 56,407,600.00 as of 2026-07-31).';
GO
SET NOEXEC OFF;
GO
