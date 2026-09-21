/* ================================================================
   Chart of Accounts — CRUD procedures for the new AccountingDevEx\
   ChartOfAccountsDevEx.cs maintenance form
   ================================================================
   Context: the only existing way to add/edit a ChartOfAccounts row
   was the legacy Accounting/COA.cs form, which builds its INSERT/
   UPDATE via raw string concatenation of textbox values (SQL
   injection risk, no validation). This script adds three procedures
   for the new DevEx form to call instead, all parameterized:

     - sp_GetChartOfAccountsList : the grid's data source (includes
       the Summary Account's own Description and the Branch's own
       BranchName, joined in, for a readable grid).
     - spu_UpsertChartOfAccount  : insert-or-update by AccountCode.
       AccountCode itself is immutable once a row exists - it's the
       key TicketDetails/JournalEntryMapping/every lookup elsewhere
       references, so only the descriptive/classification columns are
       ever updated; a rename would orphan every existing reference.
     - spu_DeleteChartOfAccount  : guarded delete. Blocks the delete
       if the account has posted GL activity (TicketDetails), is
       another account's Summary (parent) account, or is referenced
       by JournalEntryMapping. NOTE: this database has no real FK
       constraints, so this is not an exhaustive scan of every table
       that might reference an AccountCode (e.g. CashAdvanceAllowed
       Accounts, various *Payable/Debit/Credit GL code columns spread
       across many forms/config tables aren't checked here) - it only
       covers the three highest-risk references. When in doubt, leave
       an unused account in place rather than deleting it.

   ChartOfAccounts columns (confirmed via INFORMATION_SCHEMA):
     AccountCode         varchar(50)  NOT NULL  -- key
     Description         varchar(256) NULL
     AccountType         varchar(1)   NULL      -- 'D' Detail (postable) / 'S' Summary (header)
     LevelNumber         smallint     NULL      -- hierarchy depth, 0 = root
     SummaryAccount      varchar(20)  NULL      -- parent AccountCode
     GLSL                char(1)      NULL      -- 'G' General Ledger / 'S' Sub-Ledger
     BranchCode          char(5)      NULL      -- optional, branch-specific account
     YearEndIndicator    char(2)      NULL      -- 'BS' Balance Sheet / 'IS' Income Statement
     Nature              char(1)      NULL      -- 'D' Debit-normal / 'C' Credit-normal
     DueToFromIndicator  varchar(50)  NULL      -- 'DFR'/'DTO', reserved for the inter-branch
                                                 -- Due-From/Due-To accounts consumed by
                                                 -- sp_PostVoucherManual's backdated-posting
                                                 -- guard - leave NULL for ordinary accounts.

   Deploy to CORECSERP_002_DEV first; mirror to CORECSJFC2026_STAGING
   only after confirming with the user, per project convention.
   ================================================================ */

-- ----------------------------------------------------------------
-- sp_GetChartOfAccountsList
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_GetChartOfAccountsList', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetChartOfAccountsList', 'sp_GetChartOfAccountsList_OLD_09172026100000';
GO

CREATE PROCEDURE dbo.sp_GetChartOfAccountsList
AS
/*
    Returns: one result set, every ChartOfAccounts row plus the
             Summary Account's own Description and the Branch's own
             BranchName (joined in for display - not editable here).
    Callers: AccountingDevEx/ChartOfAccountsDevEx.cs (grid data source).
*/
BEGIN
    SET NOCOUNT ON;

    SELECT
        coa.AccountCode,
        coa.Description,
        coa.AccountType,
        coa.LevelNumber,
        coa.SummaryAccount,
        parent.Description AS SummaryAccountDescription,
        coa.GLSL,
        coa.BranchCode,
        br.BranchName,
        coa.YearEndIndicator,
        coa.Nature,
        coa.DueToFromIndicator
    FROM dbo.ChartOfAccounts AS coa
    LEFT JOIN dbo.ChartOfAccounts AS parent ON parent.AccountCode = coa.SummaryAccount
    LEFT JOIN dbo.Branches AS br ON br.BranchCode = coa.BranchCode
    ORDER BY coa.AccountCode;
END
GO

-- ----------------------------------------------------------------
-- spu_UpsertChartOfAccount
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.spu_UpsertChartOfAccount', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_UpsertChartOfAccount', 'spu_UpsertChartOfAccount_OLD_09172026100000';
GO

CREATE PROCEDURE dbo.spu_UpsertChartOfAccount
(
    @AccountCode        VARCHAR(50),
    @Description        VARCHAR(256) = NULL,
    @AccountType        VARCHAR(1)   = NULL,
    @LevelNumber        SMALLINT     = NULL,
    @SummaryAccount     VARCHAR(20)  = NULL,
    @GLSL               CHAR(1)      = NULL,
    @BranchCode         CHAR(5)      = NULL,
    @YearEndIndicator   CHAR(2)      = NULL,
    @Nature             CHAR(1)      = NULL,
    @DueToFromIndicator VARCHAR(50)  = NULL,
    @IsNew              BIT OUTPUT
)
AS
/*
    Inserts a new account, or updates every column except AccountCode
    for an existing one (AccountCode is the immutable key - see header
    comment). @IsNew tells the caller which branch was taken so the
    form can show "Added" vs "Updated".
    Callers: AccountingDevEx/ChartOfAccountsDevEx.cs (Save).
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF LTRIM(RTRIM(ISNULL(@AccountCode, ''))) = ''
    BEGIN
        THROW 59001, 'Account Code is required.', 1;
        RETURN;
    END

    -- FIX: normalize blank-string to NULL for every nullable
    -- reference-like column up front, before any validation reads
    -- them. Without this, a blank SummaryAccount/BranchCode/
    -- DueToFromIndicator gets stored as '' (or, for the CHAR(5)
    -- BranchCode, '     ' after fixed-length padding) rather than
    -- NULL - any current or future query that identifies root
    -- accounts via "WHERE SummaryAccount IS NULL" (the natural way to
    -- query a nullable column) would silently miss rows saved through
    -- this form.
    IF LTRIM(RTRIM(ISNULL(@SummaryAccount, ''))) = '' SET @SummaryAccount = NULL;
    IF LTRIM(RTRIM(ISNULL(@BranchCode, '')))     = '' SET @BranchCode     = NULL;
    IF LTRIM(RTRIM(ISNULL(@DueToFromIndicator,''))) = '' SET @DueToFromIndicator = NULL;

    IF @AccountType IS NOT NULL AND @AccountType NOT IN ('D', 'S')
    BEGIN
        THROW 59002, 'Account Type must be ''D'' (Detail) or ''S'' (Summary).', 1;
        RETURN;
    END

    IF @GLSL IS NOT NULL AND @GLSL NOT IN ('G', 'S')
    BEGIN
        THROW 59003, 'GLSL must be ''G'' (General Ledger) or ''S'' (Sub-Ledger).', 1;
        RETURN;
    END

    IF @Nature IS NOT NULL AND @Nature NOT IN ('D', 'C')
    BEGIN
        THROW 59004, 'Nature must be ''D'' (Debit-normal) or ''C'' (Credit-normal).', 1;
        RETURN;
    END

    IF @YearEndIndicator IS NOT NULL AND @YearEndIndicator NOT IN ('BS', 'IS')
    BEGIN
        THROW 59005, 'Year-End Indicator must be ''BS'' (Balance Sheet) or ''IS'' (Income Statement).', 1;
        RETURN;
    END

    IF @DueToFromIndicator IS NOT NULL AND @DueToFromIndicator NOT IN ('DFR', 'DTO')
    BEGIN
        THROW 59009, 'Due To/From Indicator must be ''DFR'', ''DTO'', or blank.', 1;
        RETURN;
    END

    IF @SummaryAccount IS NOT NULL
    BEGIN
        IF @SummaryAccount = @AccountCode
        BEGIN
            THROW 59006, 'An account cannot be its own Summary (parent) account.', 1;
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.ChartOfAccounts WHERE AccountCode = @SummaryAccount)
        BEGIN
            THROW 59007, 'Summary Account does not exist in Chart of Accounts.', 1;
            RETURN;
        END
    END

    IF @BranchCode IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Branches WHERE BranchCode = @BranchCode)
    BEGIN
        THROW 59008, 'Branch Code does not exist.', 1;
        RETURN;
    END

    -- FIX: wrap the check-then-act in a transaction with UPDLOCK,
    -- HOLDLOCK held on the existence check through the write, so two
    -- concurrent Saves for the same new AccountCode can't both see
    -- "doesn't exist yet" and both INSERT (AccountCode is the key
    -- every join in the app relies on - a duplicate silently fans out
    -- everywhere joins on it). BEGIN TRY/CATCH added because this now
    -- holds a real transaction that needs an explicit ROLLBACK on
    -- failure, unlike the validation-only THROWs above.
    BEGIN TRY
        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM dbo.ChartOfAccounts WITH (UPDLOCK, HOLDLOCK) WHERE AccountCode = @AccountCode)
        BEGIN
            SET @IsNew = 0;

            UPDATE dbo.ChartOfAccounts
            SET Description        = @Description,
                AccountType        = @AccountType,
                LevelNumber        = @LevelNumber,
                SummaryAccount     = @SummaryAccount,
                GLSL               = @GLSL,
                BranchCode         = @BranchCode,
                YearEndIndicator   = @YearEndIndicator,
                Nature             = @Nature,
                DueToFromIndicator = @DueToFromIndicator
            WHERE AccountCode = @AccountCode;
        END
        ELSE
        BEGIN
            SET @IsNew = 1;

            INSERT INTO dbo.ChartOfAccounts
                (AccountCode, Description, AccountType, LevelNumber, SummaryAccount,
                 GLSL, BranchCode, YearEndIndicator, Nature, DueToFromIndicator)
            VALUES
                (@AccountCode, @Description, @AccountType, @LevelNumber, @SummaryAccount,
                 @GLSL, @BranchCode, @YearEndIndicator, @Nature, @DueToFromIndicator);
        END

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------
-- spu_DeleteChartOfAccount
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.spu_DeleteChartOfAccount', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_DeleteChartOfAccount', 'spu_DeleteChartOfAccount_OLD_09172026100000';
GO

CREATE PROCEDURE dbo.spu_DeleteChartOfAccount
(
    @AccountCode VARCHAR(50)
)
AS
/*
    Guarded delete - see header comment for exactly which references
    are (and are not) checked. Not transactional (single DELETE); the
    guards above it are what make it safe, not a rollback.
    Callers: AccountingDevEx/ChartOfAccountsDevEx.cs (Delete).
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.ChartOfAccounts WHERE AccountCode = @AccountCode)
    BEGIN
        THROW 59010, 'Account not found.', 1;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM dbo.TicketDetails WHERE AccountCode = @AccountCode)
    BEGIN
        THROW 59011, 'This account has posted GL activity and cannot be deleted - deleting it would orphan historical postings. Leave it in place instead.', 1;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM dbo.ChartOfAccounts WHERE SummaryAccount = @AccountCode)
    BEGIN
        THROW 59012, 'One or more other accounts use this account as their Summary (parent) account - reassign or remove those first.', 1;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM dbo.JournalEntryMapping WHERE AccountCode = @AccountCode)
    BEGIN
        THROW 59013, 'This account is referenced by one or more JournalEntryMapping entries and cannot be deleted - update or remove those mappings first.', 1;
        RETURN;
    END

    -- FIX: a named, real gap the header comment's general disclaimer
    -- doesn't close on its own - ExpenseSummary.PayableAccountCode
    -- stores an AccountCode (see SQL/2026-09-14_EditSingleExpense_
    -- POCostLinkFix.sql and the VOUCHER-MANUAL-APTRADE EXPENSE
    -- fallback in sp_PostVoucherManual) and deleting an account still
    -- referenced there would leave future EXPENSE postings unable to
    -- resolve their payable account.
    IF EXISTS (SELECT 1 FROM dbo.ExpenseSummary WHERE PayableAccountCode = @AccountCode)
    BEGIN
        THROW 59014, 'This account is used as an Expense Payable Account and cannot be deleted - update or remove those references first.', 1;
        RETURN;
    END

    DELETE FROM dbo.ChartOfAccounts WHERE AccountCode = @AccountCode;
END
GO
