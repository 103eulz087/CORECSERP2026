/* ================================================================
   [83] 2026-10-14 - Hardening H1: the compound ticket writers refuse an unbalanced or incomplete ticket; PV-AP mapping fix
   ================================================================
   Handoff docs/handoff/2026-10-14_Hardening_Handoff_to_Fable.md, item H1 (user's go 2026-10-14, FX account 60323).
   Found on the live sp_PostCompoundTicket (and its twin sp_PostCompoundTicketSales, used by sales / credit memo / returns):
     - no DR = CR check before the insert;
     - a leg whose AmountType the caller didn't supply posted at GROSS (first leg) or at the PREVIOUS leg's amount (later
       legs: a SELECT @var that finds no row keeps the old value); the same for a flag or a {TOKEN} missing from the TVPs;
     - every error re-thrown as 50050 'ERROR SP' (the Sales twin already re-threw the real one);
     - the ticket number was taken before any check, so a refused call burned a number.
   Mapping data (JournalEntryMapping): PV-AP credited the bank at GROSS while carrying FX legs (unbalanced on any variance);
   PV-AP-DISC / PV-AP-EWT-DISC booked the discount leg as MIRROR (= gross); FX loss went to 60302 BAD DEBTS and FX gain to
   405 GAIN ON SALE OF FIXED ASSET. The telegraphic voucher and the loan revaluation use 60323 REALIZED GAIN/LOSS ON FOREX.
   PRODUCTION has 4 PV-AP tickets (08-12 / 08-13), all plain and balanced: their lines are unchanged by this script.

   1. sp_PostCompoundTicket and sp_PostCompoundTicketSales recreated from the live text: legs staged, then
        50021 amount type not supplied   50022 DR <> CR   50023 no active leg   50040 token unresolved   50041 account not in COA
      MIRROR still = GROSS. THROW; re-throws the real error. Number taken after the checks. Output rows identical for every
      balanced call (regression per caller mnemonic in the tests). Signatures unchanged (@LedgerSide of [71] stays).
   2. Mapping fix, PV-AP family: PV-AP leg 2 {BANK} GROSS -> NET (the cash paid; NET = GROSS + FX loss - FX gain in the
      callers); PV-AP-DISC leg 3 and PV-AP-EWT-DISC leg 4: MIRROR -> DISCRETALLOW; every VARIANCE_LOSS leg 60302 -> 60323 and
      every VARIANCE_GAIN leg 405 -> 60323. Rows backed up to JournalEntryMapping_PVAP_Backup_20261014; applied only if found
      as expected.
   3. sp_AddPaymentSupplierCompound_V2 and sp_AddPaymentSupplierCompound (anchor patches): the plain PURCHASE path now also
      supplies ('DISCRETALLOW', discount + return allowance) and treats a return allowance like a discount when picking the
      mnemonic / HasDiscount (the overpay path already did), so the fixed mapping is fed. Before: a return allowance without
      a discount posted an unbalanced PV-AP ticket.
   4. Exception Center: G03 "any ticket DR <> CR" (all modules, per ticket number; cross-branch expenses per reference) in
      tools/ExceptionCenter/SO_STS_ExceptionCheck.sql; baseline 0 on DEV, STAGING, PRODUCTION on 2026-10-14.
   Guard: the four procs must still be the 2026-10-14 texts (compared without whitespace). Backups _OLD_10142026234500.
   One transaction; a failure rolls everything back. No exe change.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF CHARINDEX('[83]', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostCompoundTicket'))) > 0
BEGIN
    RAISERROR('[83] already applied here; nothing to do.', 16, 1);
    SET NOEXEC ON;
END
ELSE
BEGIN
    DECLARE @h1 VARCHAR(66) = CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostCompoundTicket')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 1),
            @h2 VARCHAR(66) = CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostCompoundTicketSales')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 1),
            @h3 VARCHAR(66) = CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 1),
            @h4 VARCHAR(66) = CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 1);
    IF ISNULL(@h1, '') <> '0x68BE80EBE12309CC5ADB2F2476D87F14AFC719098A3DEEDD8FA8B2A9D90A6A9E'
       OR ISNULL(@h2, '') <> '0x3ED7195422E681ABBD78F7138B7141D558170FD9DB3FC6149B3FE66244BA8D3E'
       OR ISNULL(@h3, '') <> '0xB7AF7A1D1A461F3A14851009B1A53C5C3839155C82E1825A4E4F6EACCC1C717C'
       OR ISNULL(@h4, '') <> '0x366A9C45CCE224D64D0E4A48A9A99509B80D4BBFEDBC5868ABAFA101E38A858C'
       OR EXISTS (SELECT 1 FROM sys.objects WHERE name LIKE '%[_]OLD[_]10142026234500')
       OR OBJECT_ID('dbo.JournalEntryMapping_PVAP_Backup_20261014') IS NOT NULL
    BEGIN
        RAISERROR('[83] stopped, nothing changed: one of sp_PostCompoundTicket / sp_PostCompoundTicketSales / sp_AddPaymentSupplierCompound_V2 / sp_AddPaymentSupplierCompound is not the 2026-10-14 text here, or a [83] backup already exists.', 16, 1);
        SET NOEXEC ON;
    END
END
GO

BEGIN TRANSACTION;
GO

EXEC sp_rename 'dbo.sp_PostCompoundTicket', 'sp_PostCompoundTicket_OLD_10142026234500';
EXEC sp_rename 'dbo.sp_PostCompoundTicketSales', 'sp_PostCompoundTicketSales_OLD_10142026234500';
GO

-- 1a. sp_PostCompoundTicket -----------------------------------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[sp_PostCompoundTicket]
(
    -- Ticket identity
    @Mnemonic           VARCHAR(50),         -- key into JournalEntryMapping
    @TicketDate         DATE,
    @BranchCode         VARCHAR(5),
    @ReferenceNumber    VARCHAR(150),
    @ReferenceKey       VARCHAR(150),
    @Particulars        VARCHAR(7000),
    @Owner              VARCHAR(150),
    @PreparedBy         VARCHAR(128),
    @CheckedBy          VARCHAR(128)   = '*',
    @ApprovedBy         VARCHAR(128)   = '*',
    @Status             VARCHAR(50)    = 'POSTED',
    @Product            VARCHAR(530)   = NULL,

    -- Amount resolution (caller pre-computes all amounts)
    @Amounts            dbo.tt_AmountBreakdown  READONLY,
    -- e.g. { GROSS=362000, NET=250000, VAT=12000, EWT=1000, COST=195000 }

    -- Token resolution (caller resolves runtime GL codes)
    @Tokens             dbo.tt_TokenResolution  READONLY,
    -- e.g. { {BANK} = '101020101' }, { {DUE_FROM_BRANCH} = '1030101' }

    -- Condition flags
    @Flags              dbo.tt_ConditionFlags   READONLY,
    -- e.g. { HasVAT=1, HasEWT=0, HasDiscount=0 }

    -- Ledger back-write
    @LedgerType         VARCHAR(10)    = NULL,  -- 'SUPPLIER' or 'AR' or NULL
    @LedgerEntityID     VARCHAR(40)    = NULL,  -- SupplierID or CustomerID
    @LedgerInvoiceNo    VARCHAR(150)   = NULL,
    @LedgerBatchRef     BIGINT         = NULL,
    @LedgerSeqRef       INT            = NULL,
    @LedgerSide         CHAR(1)        = 'C'    -- 2026-10-13f [71]: 'C' = a payable (accrual, default), 'D' = a payment
)
AS
/*  [83] 2026-10-14 (hardening H1). The legs are staged and checked BEFORE anything is written:
      50021  a leg's AmountType is not in @Amounts (it used to fall back to GROSS, or to the previous leg's amount)
      50022  the legs don't balance (DR <> CR); the message carries the mnemonic and both sums
      50023  no leg is active for the mnemonic (every conditional leg off)
      50040  a {TOKEN} account is not in @Tokens (the check used to miss it after the first resolved leg)
      50041  a resolved account is not in the chart of accounts
    MIRROR still means "same as GROSS" (documented, callers rely on it). The real error is re-thrown (it used to become
    50050 'ERROR SP'). The ticket number is taken only after the checks pass, so a refused call burns no number. Posted
    rows are identical to before for every balanced call (regression-tested per caller mnemonic on DEV). */
BEGIN
    SET NOCOUNT ON;

    IF @@TRANCOUNT = 0
        THROW 50010, 'sp_PostCompoundTicket must be called inside a transaction.', 1;

    DECLARE
        @TicketNum      VARCHAR(20),
        @row            INT = 1,
        @maxrow         INT,
        @Seq            TINYINT,
        @DC             CHAR(1),
        @RawAcct        VARCHAR(50),
        @ResolvedAcct   VARCHAR(50),
        @AmtType        VARCHAR(30),
        @IsCond         BIT,
        @CondFlag       VARCHAR(50),
        @FlagVal        BIT,
        @LegAmount      DECIMAL(18,2),
        @GrossAmount    DECIMAL(18,2),
        @Dr             DECIMAL(18,2),
        @Cr             DECIMAL(18,2),
        @msg            NVARCHAR(400),
        @TicketDateDT   DATETIME = CAST(@TicketDate AS DATETIME);

    DECLARE @Staged TABLE (Seq TINYINT, AccountCode VARCHAR(50), Debit DECIMAL(18,2), Credit DECIMAL(18,2));

    BEGIN TRY

        -- ── Resolve GROSS (used for ledger entry) ─────────────
        IF ISNULL(@LedgerSide, '') NOT IN ('C', 'D')
            THROW 50026, '@LedgerSide must be C (payable) or D (payment).', 1;

        SELECT @GrossAmount = Amount FROM @Amounts WHERE AmountType = 'GROSS';
        IF @GrossAmount IS NULL
            THROW 50020, 'GROSS amount must be supplied in @Amounts TVP.', 1;

        -- ── Get legs from JournalEntryMapping ──────────────────
        SELECT
            ROW_NUMBER() OVER (ORDER BY Seq) AS RowNum,
            Seq, DebitCredit, AccountCode, AmountType, IsConditional, ConditionFlag
        INTO #Legs
        FROM [dbo].[JournalEntryMapping]
        WHERE Mnemonic = @Mnemonic
          AND IsActive = 1
          AND (BranchCode IS NULL OR BranchCode = @BranchCode)
        ORDER BY Seq;

        SELECT @maxrow = COUNT(*) FROM #Legs;

        IF @maxrow = 0
        BEGIN
            SET @msg = N'No active JournalEntryMapping rows for Mnemonic ''' + @Mnemonic + N''' (BranchCode ' + ISNULL(@BranchCode, N'') + N').';
            THROW 50030, @msg, 1;
        END

        -- ── Stage the legs (nothing written yet) ───────────────
        WHILE @row <= @maxrow
        BEGIN
            SELECT
                @Seq      = Seq,
                @DC       = DebitCredit,
                @RawAcct  = AccountCode,
                @AmtType  = AmountType,
                @IsCond   = IsConditional,
                @CondFlag = ConditionFlag
            FROM #Legs WHERE RowNum = @row;

            -- ── Skip conditional legs where flag is off ────────
            IF @IsCond = 1
            BEGIN
                SET @FlagVal = NULL;   -- [83] a flag missing from @Flags is off, not the previous leg's value
                SELECT @FlagVal = FlagValue FROM @Flags WHERE FlagName = @CondFlag;
                IF ISNULL(@FlagVal, 0) = 0
                BEGIN
                    SET @row += 1;
                    CONTINUE;
                END;
            END;

            -- ── Resolve {TOKEN} accounts ──────────────────────
            SET @ResolvedAcct = NULL;   -- [83] a missing token must not inherit the previous leg's account
            IF LEFT(@RawAcct, 1) = '{'
                SELECT @ResolvedAcct = GLAccount
                FROM   @Tokens
                WHERE  Token = @RawAcct;
            ELSE
                SET @ResolvedAcct = @RawAcct;

            IF @ResolvedAcct IS NULL
            BEGIN
                SET @msg = N'GL account could not be resolved for token ''' + @RawAcct + N''' (Mnemonic ' + @Mnemonic + N', Seq ' + CAST(@Seq AS NVARCHAR(10)) + N'). Check @Tokens.';
                THROW 50040, @msg, 1;
            END

            -- [83] the account must exist in the chart
            IF NOT EXISTS (SELECT 1 FROM [dbo].[ChartOfAccounts] WHERE AccountCode = @ResolvedAcct)
            BEGIN
                SET @msg = N'Account ''' + @ResolvedAcct + N''' (Mnemonic ' + @Mnemonic + N', Seq ' + CAST(@Seq AS NVARCHAR(10)) + N') is not in the chart of accounts.';
                THROW 50041, @msg, 1;
            END

            -- ── Resolve amount by AmountType ───────────────────
            SET @LegAmount = NULL;
            SELECT @LegAmount = Amount FROM @Amounts WHERE AmountType = @AmtType;

            -- MIRROR = same as GROSS (used for symmetrical legs)
            IF @AmtType = 'MIRROR'
                SET @LegAmount = @GrossAmount;

            IF @LegAmount IS NULL   -- [83] no silent fallback
            BEGIN
                SET @msg = N'Amount type ''' + @AmtType + N''' (Mnemonic ' + @Mnemonic + N', Seq ' + CAST(@Seq AS NVARCHAR(10)) + N') was not supplied in @Amounts.';
                THROW 50021, @msg, 1;
            END

            INSERT INTO @Staged (Seq, AccountCode, Debit, Credit)
            VALUES (@Seq, @ResolvedAcct,
                    CASE WHEN @DC = 'D' THEN ROUND(@LegAmount, 2) ELSE 0 END,
                    CASE WHEN @DC = 'C' THEN ROUND(@LegAmount, 2) ELSE 0 END);

            SET @row += 1;
        END;

        -- ── [83] DR must equal CR before anything is written ───
        IF NOT EXISTS (SELECT 1 FROM @Staged)
        BEGIN
            SET @msg = N'Mnemonic ' + @Mnemonic + N': no leg is active for the flags supplied; nothing to post.';
            THROW 50023, @msg, 1;
        END

        SELECT @Dr = ISNULL(SUM(Debit), 0), @Cr = ISNULL(SUM(Credit), 0) FROM @Staged;
        IF @Dr <> @Cr
        BEGIN
            SET @msg = N'Mnemonic ' + @Mnemonic + N' on branch ' + ISNULL(@BranchCode, N'') + N' would not balance: Debit '
                     + FORMAT(@Dr, 'N2', 'en-US') + N', Credit ' + FORMAT(@Cr, 'N2', 'en-US') + N'. Nothing was posted; check the mapping rows and the amounts supplied.';
            THROW 50022, @msg, 1;
        END

        -- ── Generate ticket number ─────────────────────────────
        EXEC GetTicketNumber @TicketNum OUTPUT;

        -- ── Insert TicketMaster (1 per compound event) ────────
        INSERT INTO [dbo].[TicketMaster]
            (TicketDate, SupplementaryNumber, BranchCode, Origin,
             TicketNumber, ReferenceNumber, ReferenceKey, Owner,
             Particulars, EnteredBy, CheckedBy, ApprovedBy,
             Status, Mnemonic, Product)
        SELECT TOP 1
            @TicketDateDT, 0, @BranchCode,
            Origin,           -- from JEM, first leg
            @TicketNum, @ReferenceNumber, @ReferenceKey, @Owner,
            @Particulars, @PreparedBy, @CheckedBy, @ApprovedBy,
            @Status, @Mnemonic, @Product
        FROM [dbo].[JournalEntryMapping]
        WHERE Mnemonic = @Mnemonic AND Seq = 1
        ORDER BY CASE WHEN BranchCode = @BranchCode THEN 0 ELSE 1 END;   -- [83] exactly one master row

        -- ── Insert TicketDetails (the staged legs, in Seq order) ──
        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        SELECT
            @TicketDateDT, 0, @BranchCode, @ReferenceKey,
            @TicketNum, @ReferenceNumber,
            AccountCode, Debit, Credit,
            @BranchCode
        FROM @Staged
        ORDER BY Seq;

        -- ── Ledger back-write (once per ticket, not per leg) ──
        IF @LedgerType = 'SUPPLIER' AND @LedgerEntityID IS NOT NULL
        BEGIN
            DECLARE
                @SupplierKey VARCHAR(30),
                @TransID     INT;

            SELECT @SupplierKey = SupplierKey
            FROM   Supplier WHERE SupplierID = @LedgerEntityID;

            SET @TransID = dbo.func_getLastID(@LedgerEntityID);

            INSERT INTO [dbo].[SupplierLedger]
                (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate,
                 Description, TransCode, TransactionDate, ReferenceNumber,
                 ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit,
                 EndingBalance, TransactedBy, ApprovedBy, TotalAmount,
                 PaymentType, ErrorCorrectTag, TicketReference, BatchReferenceID)
            VALUES
            (
                @TransID, @SupplierKey, @LedgerEntityID, @TicketDate,
                @Particulars, @Mnemonic, @TicketDate, @ReferenceNumber,
                @LedgerSeqRef, @LedgerInvoiceNo,
                0, CASE WHEN @LedgerSide = 'D' THEN @GrossAmount ELSE 0 END,   -- 2026-10-13f [71]: a payment is a debit
                   CASE WHEN @LedgerSide = 'D' THEN 0 ELSE @GrossAmount END, 0,
                @PreparedBy, @ApprovedBy, @GrossAmount,
                'COMPOUND',   -- replaces old per-PaymentType value
                0, @TicketNum, @LedgerBatchRef
            );
        END;

        -- AR Ledger (extend same pattern when you build ARLedger table)
        -- IF @LedgerType = 'AR' AND @LedgerEntityID IS NOT NULL ...

        DROP TABLE #Legs;

    END TRY
    BEGIN CATCH
        DROP TABLE IF EXISTS #Legs;
        THROW;   -- [83] the real error, not 50050 'ERROR SP'
    END CATCH;
END;

GO

-- 1b. sp_PostCompoundTicketSales ---------------------------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[sp_PostCompoundTicketSales]
(
    @Mnemonic           VARCHAR(50),
    @TicketDate         DATE,
    @BranchCode         VARCHAR(5),
    @ReferenceNumber    VARCHAR(150),
    @ReferenceKey       VARCHAR(150),
    @Particulars        VARCHAR(7000),
    @Owner              VARCHAR(150),
    @PreparedBy         VARCHAR(128),
    @CheckedBy          VARCHAR(128)   = '*',
    @ApprovedBy         VARCHAR(128)   = '*',
    @Status             VARCHAR(50)    = 'POSTED',
    @Product            VARCHAR(530)   = NULL,
    @Amounts            dbo.tt_AmountBreakdown  READONLY,
    @Tokens             dbo.tt_TokenResolution  READONLY,
    @Flags              dbo.tt_ConditionFlags   READONLY,
    @LedgerType         VARCHAR(10)    = NULL,   -- 'SUPPLIER' | 'CLIENT' | NULL
    @LedgerEntityID     VARCHAR(40)    = NULL,
    @LedgerInvoiceNo    VARCHAR(150)   = NULL,
    @LedgerBatchRef     BIGINT         = NULL,
    @LedgerSeqRef       INT            = NULL
)
AS
/*  [83] 2026-10-14 (hardening H1), same rules as sp_PostCompoundTicket: legs staged and checked before anything is
    written (50021 amount type not supplied, 50022 DR <> CR, 50023 no active leg, 50040 token unresolved, 50041 account
    not in the chart); MIRROR = GROSS; zero-amount legs are still skipped (this proc's own rule); the ticket number is
    taken after the checks. Posted rows identical to before for every balanced call. */
BEGIN
    SET NOCOUNT ON;

    IF @@TRANCOUNT = 0
        THROW 50010, 'sp_PostCompoundTicket must be called inside a transaction.', 1;

    DECLARE
        @TicketNum      VARCHAR(20),
        @row            INT = 1,
        @maxrow         INT,
        @Seq            TINYINT,
        @DC             CHAR(1),
        @RawAcct        VARCHAR(50),
        @ResolvedAcct   VARCHAR(50),
        @AmtType        VARCHAR(30),
        @IsCond         BIT,
        @CondFlag       VARCHAR(50),
        @FlagVal        BIT,
        @LegAmount      DECIMAL(18,2),
        @GrossAmount    DECIMAL(18,2),
        @Dr             DECIMAL(18,2),
        @Cr             DECIMAL(18,2),
        @msg            NVARCHAR(400),
        @TicketDateDT   DATETIME = CAST(@TicketDate AS DATETIME);

    DECLARE @Staged TABLE (Seq TINYINT, AccountCode VARCHAR(50), Debit DECIMAL(18,2), Credit DECIMAL(18,2));

    BEGIN TRY

        SELECT @GrossAmount = Amount FROM @Amounts WHERE AmountType = 'GROSS';
        IF @GrossAmount IS NULL
            THROW 50020, 'GROSS amount must be supplied in @Amounts TVP.', 1;

        SELECT
            ROW_NUMBER() OVER (ORDER BY Seq) AS RowNum,
            Seq, DebitCredit, AccountCode, AmountType, IsConditional, ConditionFlag
        INTO #Legs
        FROM [dbo].[JournalEntryMapping]
        WHERE Mnemonic   = @Mnemonic
          AND IsActive   = 1
          AND (BranchCode IS NULL OR BranchCode = @BranchCode)
        ORDER BY Seq;

        SELECT @maxrow = COUNT(*) FROM #Legs;

        IF @maxrow = 0
        BEGIN
            SET @msg = N'No active JournalEntryMapping rows for Mnemonic=''' + @Mnemonic + N''' BranchCode=''' + ISNULL(@BranchCode, N'') + N'''';
            THROW 50030, @msg, 1;
        END;

        -- Leg loop: stage only (nothing written yet)
        WHILE @row <= @maxrow
        BEGIN
            SELECT
                @Seq      = Seq,      @DC       = DebitCredit,
                @RawAcct  = AccountCode,        @AmtType  = AmountType,
                @IsCond   = IsConditional,       @CondFlag = ConditionFlag
            FROM #Legs WHERE RowNum = @row;

            IF @IsCond = 1
            BEGIN
                SET @FlagVal = NULL;   -- [83] a flag missing from @Flags is off, not the previous leg's value
                SELECT @FlagVal = FlagValue FROM @Flags WHERE FlagName = @CondFlag;
                IF ISNULL(@FlagVal, 0) = 0
                BEGIN SET @row += 1; CONTINUE; END;
            END;

            SET @ResolvedAcct = NULL;   -- [83] a missing token must not inherit the previous leg's account
            IF LEFT(@RawAcct, 1) = '{'
                SELECT @ResolvedAcct = GLAccount FROM @Tokens WHERE Token = @RawAcct;
            ELSE
                SET @ResolvedAcct = @RawAcct;

            IF @ResolvedAcct IS NULL
            BEGIN
                SET @msg = N'GL account could not be resolved for token ''' + @RawAcct
                    + N''' (Mnemonic=' + @Mnemonic + N' Seq=' + CAST(@Seq AS NVARCHAR(10)) + N')';
                THROW 50040, @msg, 1;
            END;

            IF NOT EXISTS (SELECT 1 FROM [dbo].[ChartOfAccounts] WHERE AccountCode = @ResolvedAcct)   -- [83]
            BEGIN
                SET @msg = N'Account ''' + @ResolvedAcct + N''' (Mnemonic ' + @Mnemonic + N', Seq ' + CAST(@Seq AS NVARCHAR(10)) + N') is not in the chart of accounts.';
                THROW 50041, @msg, 1;
            END

            SET @LegAmount = NULL;
            SELECT @LegAmount = Amount FROM @Amounts WHERE AmountType = @AmtType;
            IF @AmtType = 'MIRROR'
                SET @LegAmount = @GrossAmount;
            IF @LegAmount IS NULL   -- [83] no silent fallback
            BEGIN
                SET @msg = N'Amount type ''' + @AmtType + N''' (Mnemonic ' + @Mnemonic + N', Seq ' + CAST(@Seq AS NVARCHAR(10)) + N') was not supplied in @Amounts.';
                THROW 50021, @msg, 1;
            END

            -- Skip zero-amount legs (no-op rather than posting a 0.00 leg)
            IF ISNULL(@LegAmount, 0) = 0
            BEGIN SET @row += 1; CONTINUE; END;

            INSERT INTO @Staged (Seq, AccountCode, Debit, Credit)
            VALUES (@Seq, @ResolvedAcct,
                    CASE WHEN @DC = 'D' THEN ROUND(@LegAmount, 2) ELSE 0 END,
                    CASE WHEN @DC = 'C' THEN ROUND(@LegAmount, 2) ELSE 0 END);

            SET @row += 1;
        END;

        -- [83] DR must equal CR before anything is written
        IF NOT EXISTS (SELECT 1 FROM @Staged)
        BEGIN
            SET @msg = N'Mnemonic ' + @Mnemonic + N': no leg is active for the flags and amounts supplied; nothing to post.';
            THROW 50023, @msg, 1;
        END

        SELECT @Dr = ISNULL(SUM(Debit), 0), @Cr = ISNULL(SUM(Credit), 0) FROM @Staged;
        IF @Dr <> @Cr
        BEGIN
            SET @msg = N'Mnemonic ' + @Mnemonic + N' on branch ' + ISNULL(@BranchCode, N'') + N' would not balance: Debit '
                     + FORMAT(@Dr, 'N2', 'en-US') + N', Credit ' + FORMAT(@Cr, 'N2', 'en-US') + N'. Nothing was posted; check the mapping rows and the amounts supplied.';
            THROW 50022, @msg, 1;
        END

        EXEC GetTicketNumber @TicketNum OUTPUT;

        INSERT INTO [dbo].[TicketMaster]
            (TicketDate, SupplementaryNumber, BranchCode, Origin,
             TicketNumber, ReferenceNumber, ReferenceKey, Owner,
             Particulars, EnteredBy, CheckedBy, ApprovedBy,
             Status, Mnemonic, Product)
        SELECT TOP 1
            @TicketDateDT, 0, @BranchCode,
            Origin,
            @TicketNum, @ReferenceNumber, @ReferenceKey, @Owner,
            @Particulars, @PreparedBy, @CheckedBy, @ApprovedBy,
            @Status, @Mnemonic, @Product
        FROM [dbo].[JournalEntryMapping]
        WHERE Mnemonic = @Mnemonic
          AND IsActive = 1
          AND (BranchCode IS NULL OR BranchCode = @BranchCode)
          AND Seq = 1
        ORDER BY CASE WHEN BranchCode = @BranchCode THEN 0 ELSE 1 END;   -- [83] exactly one master row

        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        SELECT
            @TicketDateDT, 0, @BranchCode, @ReferenceKey,
            @TicketNum, @ReferenceNumber, AccountCode, Debit, Credit,
            @BranchCode
        FROM @Staged
        ORDER BY Seq;

        -- ── SUPPLIER ledger (unchanged) ────────────────────────────
        IF @LedgerType = 'SUPPLIER' AND @LedgerEntityID IS NOT NULL
        BEGIN
            DECLARE @SupplierKey VARCHAR(30), @TransIDSup INT;
            SELECT @SupplierKey = SupplierKey FROM Supplier WHERE SupplierID = @LedgerEntityID;
            SET @TransIDSup = dbo.func_getLastID(@LedgerEntityID);

            INSERT INTO [dbo].[SupplierLedger]
                (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate,
                 Description, TransCode, TransactionDate, ReferenceNumber,
                 ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit,
                 EndingBalance, TransactedBy, ApprovedBy, TotalAmount,
                 PaymentType, ErrorCorrectTag, TicketReference, BatchReferenceID)
            VALUES
            (@TransIDSup, @SupplierKey, @LedgerEntityID, @TicketDate,
             @Particulars, @Mnemonic, @TicketDate, @ReferenceNumber,
             @LedgerSeqRef, @LedgerInvoiceNo,
             0, @GrossAmount, 0, 0,
             @PreparedBy, @ApprovedBy, @GrossAmount,
             'COMPOUND', 0, @TicketNum, @LedgerBatchRef);
        END;

        -- ── CLIENT ledger ──────────────────────────────────────────
        -- Writes ClientLedger when @LedgerType='CLIENT'.
        -- sp_ConfirmOrder no longer inserts into ClientLedger directly;
        -- all ClientLedger writes for sales tickets go through here.
        IF @LedgerType = 'CLIENT' AND @LedgerEntityID IS NOT NULL
        BEGIN
            DECLARE @ClientTRNSeq DECIMAL(7,0);
            SELECT @ClientTRNSeq =
                ISNULL(MAX(TRN_SEQ_NO), 0) + 1
            FROM ClientLedger
            WHERE AccountID = @LedgerEntityID;

            INSERT INTO [dbo].[ClientLedger]
                (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch,
                 Description, TransCode, TransactionDate, ReferenceNumber, ReferenceKey,
                 InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, ORNumber,
                 TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag,
                 TicketReference)
            VALUES
            (
                @ClientTRNSeq,
                @LedgerEntityID,            -- AccountKey = CustomerKey
                @LedgerEntityID,            -- AccountID
                @TicketDate,
                @BranchCode,
                @Particulars,
                @Mnemonic,                  -- TransCode = mnemonic (SI-VAT / SI-VATEX)
                @TicketDate,
                @ReferenceNumber,           -- PO number
                @ReferenceKey,              -- Invoice number
                @LedgerInvoiceNo,
                0,
                @GrossAmount,               -- Debit = AR amount
                0,
                0,
                @LedgerInvoiceNo,           -- OR number = invoice number
                @PreparedBy,
                @ApprovedBy,
                LEFT(@Particulars, 50),
                @GrossAmount,
                0,
                @TicketNum
            );
        END;

        DROP TABLE IF EXISTS #Legs;

    END TRY
    BEGIN CATCH
        DROP TABLE IF EXISTS #Legs;
        -- Re-throw the ORIGINAL error, not a generic one.
        THROW;
    END CATCH;
END;

GO

-- 2. mapping fix, PV-AP family ----------------------------------------------------------------------------------------------------
BEGIN TRY
    SELECT m.*, CAST(GETDATE() AS DATETIME) AS BackupAt
    INTO dbo.JournalEntryMapping_PVAP_Backup_20261014
    FROM dbo.JournalEntryMapping AS m
    WHERE m.Mnemonic LIKE 'PV-AP%';

    DECLARE @exp INT, @n INT;
    -- as found 2026-10-14 on DEV / STAGING / PRODUCTION: 1 bank leg at GROSS, 2 MIRROR discount legs, 7 loss legs on 60302, 7 gain legs on 405
    SELECT @exp = SUM(CASE WHEN Mnemonic = 'PV-AP' AND Seq = 2 AND AccountCode = '{BANK}' AND AmountType = 'GROSS' THEN 1 ELSE 0 END)
                + SUM(CASE WHEN Mnemonic IN ('PV-AP-DISC', 'PV-AP-EWT-DISC') AND AccountCode = '508' AND AmountType = 'MIRROR' THEN 1 ELSE 0 END)
                + SUM(CASE WHEN AmountType = 'VARIANCE_LOSS' AND AccountCode = '60302' THEN 1 ELSE 0 END)
                + SUM(CASE WHEN AmountType = 'VARIANCE_GAIN' AND AccountCode = '405' THEN 1 ELSE 0 END)
    FROM dbo.JournalEntryMapping WHERE Mnemonic LIKE 'PV-AP%' AND IsActive = 1;
    IF ISNULL(@exp, 0) <> 1 + 2 + 7 + 7
    BEGIN
        DECLARE @m1 NVARCHAR(300) = N'[83] the PV-AP mapping rows are not as found on 2026-10-14 (' + CAST(ISNULL(@exp, 0) AS NVARCHAR(10)) + N' of 17 expected rows match); compare before applying.';
        THROW 59987, @m1, 1;
    END
    IF NOT EXISTS (SELECT 1 FROM dbo.ChartOfAccounts WHERE AccountCode = '60323')
        THROW 59987, '[83] account 60323 (REALIZED GAIN/LOSS ON FOREX) is not in the chart of accounts here.', 1;

    UPDATE dbo.JournalEntryMapping SET AmountType = 'NET' WHERE Mnemonic = 'PV-AP' AND Seq = 2 AND AccountCode = '{BANK}' AND AmountType = 'GROSS';
    SET @n = @@ROWCOUNT;
    UPDATE dbo.JournalEntryMapping SET AmountType = 'DISCRETALLOW' WHERE Mnemonic IN ('PV-AP-DISC', 'PV-AP-EWT-DISC') AND AccountCode = '508' AND AmountType = 'MIRROR';
    SET @n += @@ROWCOUNT;
    UPDATE dbo.JournalEntryMapping SET AccountCode = '60323' WHERE Mnemonic LIKE 'PV-AP%' AND AmountType = 'VARIANCE_LOSS' AND AccountCode = '60302';
    SET @n += @@ROWCOUNT;
    UPDATE dbo.JournalEntryMapping SET AccountCode = '60323' WHERE Mnemonic LIKE 'PV-AP%' AND AmountType = 'VARIANCE_GAIN' AND AccountCode = '405';
    SET @n += @@ROWCOUNT;
    IF @n <> 17 THROW 59987, '[83] the mapping update did not touch exactly 17 rows.', 1;
    PRINT '[83] mapping: 17 PV-AP rows updated (bank leg NET, discount legs DISCRETALLOW, FX legs 60323).';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @em2 NVARCHAR(2048) = N'[83] stopped, nothing changed: ' + ERROR_MESSAGE();
    RAISERROR(@em2, 16, 1);
    SET NOEXEC ON;
END CATCH
GO

-- 3. the two payment procs feed the fixed mapping (anchor patches; every anchor must occur exactly once) --------------------------
BEGIN TRY
    DECLARE @Patch TABLE (Obj SYSNAME, Ord INT, Anchor NVARCHAR(400), Repl NVARCHAR(MAX));
    INSERT INTO @Patch (Obj, Ord, Anchor, Repl) VALUES
    (N'sp_AddPaymentSupplierCompound_V2', 1,
     N'WHEN @pEWT>0 AND @pDiscount>0 THEN ''PV-AP-EWT-DISC''',
     N'WHEN @pEWT>0 AND @pDiscount+@pRetAllow>0 THEN ''PV-AP-EWT-DISC''   -- [83] a return allowance is booked like a discount'),
    (N'sp_AddPaymentSupplierCompound_V2', 2,
     N'WHEN @pDiscount>0 THEN ''PV-AP-DISC''',
     N'WHEN @pDiscount+@pRetAllow>0 THEN ''PV-AP-DISC''   -- [83]'),
    (N'sp_AddPaymentSupplierCompound_V2', 3,
     N'(''MIRROR'',@pDiscount+@pRetAllow),(''VARIANCE_LOSS'',@pFXLoss),(''VARIANCE_GAIN'',@pFXGain);',
     N'(''MIRROR'',@pDiscount+@pRetAllow),(''DISCRETALLOW'',@pDiscount+@pRetAllow),(''VARIANCE_LOSS'',@pFXLoss),(''VARIANCE_GAIN'',@pFXGain);   -- [83] DISCRETALLOW feeds the fixed discount legs'),
    (N'sp_AddPaymentSupplierCompound_V2', 4,
     N'(''HasDiscount'', CASE WHEN @pDiscount>0 THEN 1 ELSE 0 END),',
     N'(''HasDiscount'', CASE WHEN @pDiscount+@pRetAllow>0 THEN 1 ELSE 0 END),   -- [83]'),
    (N'sp_AddPaymentSupplierCompound', 1,
     N'WHEN @EWT>0 AND @Discount>0 THEN ''PV-AP-EWT-DISC''',
     N'WHEN @EWT>0 AND @Discount+@RetAllow>0 THEN ''PV-AP-EWT-DISC''   -- [83] a return allowance is booked like a discount'),
    (N'sp_AddPaymentSupplierCompound', 2,
     N'WHEN @Discount>0 THEN ''PV-AP-DISC''',
     N'WHEN @Discount+@RetAllow>0 THEN ''PV-AP-DISC''   -- [83]'),
    (N'sp_AddPaymentSupplierCompound', 3,
     N'(''EWT'',@EWT),(''MIRROR'',@Discount+@RetAllow),',
     N'(''EWT'',@EWT),(''MIRROR'',@Discount+@RetAllow),(''DISCRETALLOW'',@Discount+@RetAllow),   -- [83]'),
    (N'sp_AddPaymentSupplierCompound', 4,
     N'(''HasDiscount'',CASE WHEN @Discount>0 THEN 1 ELSE 0 END),',
     N'(''HasDiscount'',CASE WHEN @Discount+@RetAllow>0 THEN 1 ELSE 0 END),   -- [83]');

    DECLARE @obj SYSNAME, @def NVARCHAR(MAX), @msg NVARCHAR(400), @a NVARCHAR(400), @r NVARCHAR(MAX), @cnt INT, @bak SYSNAME;
    DECLARE objs CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT Obj FROM @Patch;
    OPEN objs;
    FETCH NEXT FROM objs INTO @obj;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @def = OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + @obj));
        IF @def IS NULL BEGIN SET @msg = N'[83] ' + @obj + N' is missing here.'; THROW 59985, @msg, 1; END
        DECLARE pt CURSOR LOCAL FAST_FORWARD FOR SELECT Anchor, Repl FROM @Patch WHERE Obj = @obj ORDER BY Ord;
        OPEN pt;
        FETCH NEXT FROM pt INTO @a, @r;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @cnt = (LEN(@def) - LEN(REPLACE(@def, @a, N''))) / LEN(@a);
            IF @cnt <> 1 BEGIN SET @msg = N'[83] ' + @obj + N': anchor found ' + CAST(@cnt AS NVARCHAR(10)) + N' times (expected 1): ' + LEFT(@a, 120); THROW 59985, @msg, 1; END
            SET @def = REPLACE(@def, @a, @r);
            FETCH NEXT FROM pt INTO @a, @r;
        END
        CLOSE pt; DEALLOCATE pt;
        SET @bak = @obj + N'_OLD_10142026234500';
        SET @a = N'dbo.' + @obj;
        EXEC sp_rename @a, @bak;
        EXEC (@def);
        PRINT N'[83] ' + @obj + N': patched (backup ' + @bak + N').';
        FETCH NEXT FROM objs INTO @obj;
    END
    CLOSE objs; DEALLOCATE objs;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @em3 NVARCHAR(2048) = N'[83] stopped, nothing changed: ' + ERROR_MESSAGE();
    RAISERROR(@em3, 16, 1);
    SET NOEXEC ON;
END CATCH
GO

-- post-check ------------------------------------------------------------------------------------------------------------------------
IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostCompoundTicket')) NOT LIKE '%[[]83]%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostCompoundTicketSales')) NOT LIKE '%[[]83]%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2')) NOT LIKE '%[[]83]%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound')) NOT LIKE '%[[]83]%'
   OR (SELECT COUNT(*) FROM sys.objects WHERE name LIKE '%[_]OLD[_]10142026234500') <> 4
   OR EXISTS (SELECT 1 FROM dbo.JournalEntryMapping WHERE Mnemonic LIKE 'PV-AP%' AND IsActive = 1 AND (AccountCode IN ('60302', '405') OR AmountType = 'MIRROR'))
   OR NOT EXISTS (SELECT 1 FROM dbo.JournalEntryMapping WHERE Mnemonic = 'PV-AP' AND Seq = 2 AND AmountType = 'NET')
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[83] post-check failed; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
GO

SET NOEXEC OFF;
GO
SELECT DB_NAME() AS DatabaseName, name, CONVERT(VARCHAR(16), modify_date, 120) AS Modified FROM sys.objects
WHERE name IN ('sp_PostCompoundTicket', 'sp_PostCompoundTicketSales', 'sp_AddPaymentSupplierCompound_V2', 'sp_AddPaymentSupplierCompound', 'JournalEntryMapping_PVAP_Backup_20261014')
   OR name LIKE '%[_]OLD[_]10142026234500' ORDER BY name;
SELECT Mnemonic, Seq, DebitCredit, AccountCode, AmountType, ConditionFlag FROM dbo.JournalEntryMapping WHERE Mnemonic LIKE 'PV-AP%' AND IsActive = 1 ORDER BY Mnemonic, Seq;
GO
