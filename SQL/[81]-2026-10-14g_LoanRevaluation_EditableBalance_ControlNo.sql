/* ================================================================
   [81] 2026-10-14 - Loan Revaluation: editable foreign balance + Control No.
   ================================================================
   User 2026-10-14: "dont make static amount the 800,000.00, it should be displayed in the editable textfield, and also add
   ControlNo textfield for their reference coding". Decisions (user): a typed balance different from the loan's is revalued
   and becomes the loan's new foreign balance; the Control No. is kept on the loan entry AND shown on the GL ticket.
   1. LoanTransaction: new column ControlNo VARCHAR(30) NULL.
   2. spu_Loan_PostRevaluation: optional @ForeignBalance (NULL = the loan's own, so an old exe posts as before) and
      @ControlNo. Forex entry = typed balance x rate - GL balance of the liability account up to the date (equals the old
      formula while nothing else moved: GL = loan). Guards: unchanged balance -> GL must equal the loan (62020, as before);
      changed balance -> GL must have moved the same way at a rate within 20% of the last rate, i.e. the principal payment
      is booked (62022); typed balance <= 0 (62021). Ticket Particulars = description + ' | CONTROL NO. <no>'.
      LoanTransaction gets ForeignChange = typed - previous, ForeignBalance = typed, ControlNo.
   3. sp_Loan_GetTransactions: returns ControlNo (last column).
   Guard: both procs must still be the [65] versions (compared without whitespace). Backups _OLD_10142026220000.
   One transaction; a failure rolls everything back. The new exe sends the two parameters; the old exe still works.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF CHARINDEX('[81]', OBJECT_DEFINITION(OBJECT_ID('dbo.spu_Loan_PostRevaluation'))) > 0
BEGIN
    RAISERROR('[81] already applied here; nothing to do.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF ISNULL(CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.spu_Loan_PostRevaluation')),
            CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 1), '') <> '0x35CBFC889958F791F362B72DBF3ED4C5B34457FE59C2C4E721A3A8909B949694'
     OR ISNULL(CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_Loan_GetTransactions')),
            CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 1), '') <> '0x3B33A484094E1D6A374ABF55CE5B1FD3E0354FF1AEDA413B725C3982C90CB51D'
     OR OBJECT_ID('dbo.spu_Loan_PostRevaluation_OLD_10142026220000') IS NOT NULL
     OR OBJECT_ID('dbo.sp_Loan_GetTransactions_OLD_10142026220000') IS NOT NULL
BEGIN
    RAISERROR('[81] stopped, nothing changed: spu_Loan_PostRevaluation / sp_Loan_GetTransactions is not the [65] version here, or a backup _OLD_10142026220000 already exists.', 16, 1);
    SET NOEXEC ON;
END
GO

BEGIN TRANSACTION;
GO

IF COL_LENGTH('dbo.LoanTransaction', 'ControlNo') IS NULL
    ALTER TABLE dbo.LoanTransaction ADD ControlNo VARCHAR(30) NULL;
GO

EXEC sp_rename 'dbo.spu_Loan_PostRevaluation', 'spu_Loan_PostRevaluation_OLD_10142026220000';
EXEC sp_rename 'dbo.sp_Loan_GetTransactions', 'sp_Loan_GetTransactions_OLD_10142026220000';
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

-- 3. sp_Loan_GetTransactions ---------------------------------------------------------------------------------------------------

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
           t.PostedBy, t.PostedAt, t.ReversedBy, t.ReversedAt, t.ReverseReason, t.ReversalTicketNumber,
           t.ControlNo   -- [81] their reference coding
    FROM dbo.LoanTransaction AS t
    WHERE t.LoanID = @LoanID
    ORDER BY t.TxnDate, t.TxnID;
END

GO

IF COL_LENGTH('dbo.LoanTransaction', 'ControlNo') IS NULL
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.spu_Loan_PostRevaluation')) NOT LIKE '%[[]81]%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_Loan_GetTransactions')) NOT LIKE '%[[]81]%'
   OR OBJECT_ID('dbo.spu_Loan_PostRevaluation_OLD_10142026220000') IS NULL
   OR OBJECT_ID('dbo.sp_Loan_GetTransactions_OLD_10142026220000') IS NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[81] post-check failed; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
GO

SET NOEXEC OFF;
GO
SELECT name, CONVERT(VARCHAR(16), modify_date, 120) AS Modified FROM sys.objects
WHERE name IN ('spu_Loan_PostRevaluation', 'sp_Loan_GetTransactions') OR name LIKE '%[_]OLD[_]10142026220000' ORDER BY name;
SELECT CASE WHEN COL_LENGTH('dbo.LoanTransaction', 'ControlNo') IS NULL THEN 'missing' ELSE 'present' END AS LoanTransaction_ControlNo;
GO
