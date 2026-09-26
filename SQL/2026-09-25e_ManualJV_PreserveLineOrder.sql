/* ================================================================
   2026-09-25e: Manual Journal Voucher (single + multi-branch) --
   keep GL lines in the order the user encoded them.
   Same fix as 2026-09-25d (ExpenseManualMultiBranchFrm).
   ================================================================
   PROBLEM:
     - sp_GetManualJournalVoucherDetails: ORDER BY BranchCode, AccountCode
       -> View/Copy/Edit showed lines sorted by account, not as typed.
     - Multi-branch Post/Edit insert ManualJournalVoucherDetails one
       branch at a time, so even DetailID (IDENTITY) order is grouped by
       branch; and INSERT ... SELECT FROM @Lines has no ORDER BY anyway.
     - Edit (ManualJournalVoucherMultiBranchFrm) re-posted the reordered
       grid, locking the scrambled order in.

   FIX:
     1. ManualJournalVoucherDetails.LineNo INT NULL -- the grid position
        (1..n) across the whole voucher, all branches. Existing rows stay
        NULL and fall back to BranchCode, DetailID (insertion) order.
        Safe to add: every INSERT into this table uses a column list
        (checked sys.sql_modules; sp_JV_PostBankReconForLines only reads).
     2. New TVP types (+LineNo). Old types kept -- the _OLD_ / dated
        backup procs still reference them:
          dbo.JournalVoucherLineTVP_V2       (single-branch)
          dbo.JournalVoucherLineMultiTVP_V2  (multi-branch)
     3. sp_PostManualJournalVoucher, sp_PostManualJournalVoucherMultiBranch,
        sp_EditManualJournalVoucher: take the V2 TVP, store LineNo, insert
        ORDER BY LineNo. No other logic changed.
     4. sp_GetManualJournalVoucherDetails: ORDER BY LineNo, then the
        legacy fallback.

   C# (same change set): HOFormsDevEx/ManualJournalVoucherFrm.cs and
   ManualJournalVoucherMultiBranchFrm.cs BuildLinesTVP() send LineNo and
   the _V2 TypeName. Deploy the exe together with this script.

   Deploy to CORECSERP_002_DEV first; CORECSJFC2026_STAGING only after
   the user confirms.
   ================================================================ */

-- ----------------------------------------------------------------
-- 1. ManualJournalVoucherDetails.LineNo
-- ----------------------------------------------------------------
IF COL_LENGTH('dbo.ManualJournalVoucherDetails', 'LineNo') IS NULL
    ALTER TABLE dbo.ManualJournalVoucherDetails ADD [LineNo] INT NULL;
GO

-- ----------------------------------------------------------------
-- 2. TVP types
-- ----------------------------------------------------------------
IF TYPE_ID('dbo.JournalVoucherLineTVP_V2') IS NULL
    CREATE TYPE dbo.JournalVoucherLineTVP_V2 AS TABLE
    (
        [LineNo]    INT           NOT NULL,
        AccountCode VARCHAR(20)   NOT NULL,
        Debit       DECIMAL(18,2) NOT NULL,
        Credit      DECIMAL(18,2) NOT NULL,
        Particulars VARCHAR(300)  NULL
    );
GO

IF TYPE_ID('dbo.JournalVoucherLineMultiTVP_V2') IS NULL
    CREATE TYPE dbo.JournalVoucherLineMultiTVP_V2 AS TABLE
    (
        [LineNo]    INT           NOT NULL,
        BranchCode  VARCHAR(5)    NOT NULL,
        AccountCode VARCHAR(20)   NOT NULL,
        Debit       DECIMAL(18,2) NOT NULL,
        Credit      DECIMAL(18,2) NOT NULL,
        Particulars VARCHAR(500)  NULL
    );
GO

-- ----------------------------------------------------------------
-- 3a. sp_PostManualJournalVoucher (single branch)
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_PostManualJournalVoucher', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_PostManualJournalVoucher', 'sp_PostManualJournalVoucher_OLD_09252026170000';
GO

CREATE PROCEDURE [dbo].[sp_PostManualJournalVoucher]
(
    @parmrefno       VARCHAR(10),
    @parmvoucherdate DATE,
    @parmbranchcode  VARCHAR(5),
    @parmremarks     VARCHAR(500),
    @parmuser        VARCHAR(50),
    @Lines           dbo.JournalVoucherLineTVP_V2 READONLY   -- CHANGED 2026-09-25e: V2 (+LineNo)
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF (SELECT COUNT(*) FROM @Lines) < 2
            THROW 59001, 'A journal voucher needs at least two lines (one debit, one credit).', 1;

        IF EXISTS (SELECT 1 FROM @Lines WHERE (Debit > 0 AND Credit > 0) OR (Debit = 0 AND Credit = 0))
            THROW 59002, 'Each line must have an amount in either Debit or Credit, not both or neither.', 1;

        IF EXISTS (SELECT 1 FROM @Lines WHERE LTRIM(RTRIM(ISNULL(AccountCode,''))) = '')
            THROW 59003, 'Every line requires an Account Code.', 1;

        DECLARE @TotalDebit DECIMAL(18,2), @TotalCredit DECIMAL(18,2);
        SELECT @TotalDebit = ISNULL(SUM(Debit), 0), @TotalCredit = ISNULL(SUM(Credit), 0) FROM @Lines;

        IF @TotalDebit <> @TotalCredit
            THROW 59004, 'Entry does not balance - total Debit must equal total Credit.', 1;

        IF @TotalDebit <= 0
            THROW 59005, 'Entry total must be greater than zero.', 1;

        DECLARE @ticketnum VARCHAR(20);
        EXEC GetTicketNumber @ticketnum OUTPUT;

        INSERT INTO [dbo].[TicketMaster]
            (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber,
             ReferenceNumber, ReferenceKey, Owner, Particulars,
             EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
        VALUES
            (@parmvoucherdate, 0, @parmbranchcode, 'JV', @ticketnum,
             @parmrefno, @parmrefno, @parmuser, ISNULL(@parmremarks,''),
             @parmuser, '*', '*', 'POSTED', 'MANUAL JV', NULL);

        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        SELECT
            @parmvoucherdate, 0, @parmbranchcode, @parmrefno,
            @ticketnum, @parmrefno, AccountCode, Debit, Credit, ''
        FROM @Lines
        ORDER BY [LineNo];                                              -- CHANGED 2026-09-25e

        DECLARE @voucherID INT;
        INSERT INTO dbo.ManualJournalVoucher
            (ReferenceNo, VoucherDate, BranchCode, Remarks, PreparedBy, TicketNumber, TotalAmount)
        VALUES
            (@parmrefno, @parmvoucherdate, @parmbranchcode, @parmremarks, @parmuser, @ticketnum, @TotalDebit);
        SET @voucherID = SCOPE_IDENTITY();

        INSERT INTO dbo.ManualJournalVoucherDetails (VoucherID, AccountCode, Debit, Credit, Particulars, [LineNo])
        SELECT @voucherID, AccountCode, Debit, Credit, Particulars, [LineNo]
        FROM @Lines
        ORDER BY [LineNo];                                              -- CHANGED 2026-09-25e

        -- Bank Recon detection: a line touching a bank account
        -- (AccountCode LIKE '10102%') -- Debit = money INTO that account
        -- (DIT), Credit = money OUT (OC).
        EXEC dbo.sp_JV_PostBankReconForLines
            @ReferenceNo = @parmrefno, @VoucherDate = @parmvoucherdate,
            @DefaultBranch = @parmbranchcode, @CreatedBy = @parmuser;

        COMMIT TRAN;

        SELECT 1 AS Status, @parmrefno AS ReferenceNo, @ticketnum AS TicketNumber,
               'Journal voucher posted successfully.' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH;
END
GO

-- ----------------------------------------------------------------
-- 3b. sp_PostManualJournalVoucherMultiBranch
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_PostManualJournalVoucherMultiBranch', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_PostManualJournalVoucherMultiBranch', 'sp_PostManualJournalVoucherMultiBranch_OLD_09252026170000';
GO

CREATE PROCEDURE [dbo].[sp_PostManualJournalVoucherMultiBranch]
(
    @parmrefno         VARCHAR(10),
    @parmcontrolno     VARCHAR(50),
    @parmvoucherdate   DATE,
    @parmremarks       VARCHAR(500),
    @parmuser          VARCHAR(50),
    @Lines             dbo.JournalVoucherLineMultiTVP_V2 READONLY,   -- CHANGED 2026-09-25e: V2 (+LineNo)
    @AllowCrossBranch  BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF (SELECT COUNT(*) FROM @Lines) < 2
            THROW 59101, 'A journal voucher needs at least two lines (one debit, one credit).', 1;

        IF EXISTS (SELECT 1 FROM @Lines WHERE (Debit > 0 AND Credit > 0) OR (Debit = 0 AND Credit = 0))
            THROW 59102, 'Each line must have an amount in either Debit or Credit, not both or neither.', 1;

        IF EXISTS (SELECT 1 FROM @Lines WHERE LTRIM(RTRIM(ISNULL(AccountCode,''))) = '')
            THROW 59103, 'Every line requires an Account Code.', 1;

        IF EXISTS (SELECT 1 FROM @Lines WHERE LTRIM(RTRIM(ISNULL(BranchCode,''))) = '')
            THROW 59104, 'Every line requires a Branch Code.', 1;

        DECLARE @TotalDebit DECIMAL(18,2), @TotalCredit DECIMAL(18,2);
        SELECT @TotalDebit = ISNULL(SUM(Debit), 0), @TotalCredit = ISNULL(SUM(Credit), 0) FROM @Lines;

        IF @TotalDebit <= 0
            THROW 59105, 'Entry total must be greater than zero.', 1;

        -- The grand-total check ALWAYS applies, cross-branch or not.
        IF @TotalDebit <> @TotalCredit
            THROW 59107, 'Entry does not balance overall — total Debit must equal total Credit across all branches.', 1;

        -- The PER-BRANCH check only applies when cross-branch entry is off.
        IF @AllowCrossBranch = 0
        BEGIN
            IF EXISTS (
                SELECT BranchCode FROM @Lines GROUP BY BranchCode HAVING SUM(Debit) <> SUM(Credit)
            )
            BEGIN
                DECLARE @BadBranches VARCHAR(200) = (
                    SELECT STRING_AGG(BranchCode, ', ')
                    FROM (
                        SELECT BranchCode FROM @Lines
                        GROUP BY BranchCode HAVING SUM(Debit) <> SUM(Credit)
                    ) x
                );
                DECLARE @BalanceMsg VARCHAR(400) = 'Entry does not balance per branch. Out-of-balance branch(es): ' + ISNULL(@BadBranches, '')
                    + '. If this is intentional (e.g. one branch funding others'' expenses), check "Allow Cross-Branch Entry."';
                THROW 59106, @BalanceMsg, 1;
            END
        END

        IF OBJECT_ID('tempdb..#Branches') IS NOT NULL DROP TABLE #Branches;
        SELECT ROW_NUMBER() OVER (ORDER BY BranchCode) AS RowNum, BranchCode, SUM(Debit) AS BranchTotal
        INTO #Branches FROM @Lines GROUP BY BranchCode;

        DECLARE @row INT = 1, @maxrow INT, @br VARCHAR(5), @brTotal DECIMAL(18,2), @ticketnum VARCHAR(20);
        SELECT @maxrow = COUNT(*) FROM #Branches;

        -- ONE ticket number for the whole voucher, shared across every
        -- branch it touches.
        EXEC GetTicketNumber @ticketnum OUTPUT;

        WHILE @row <= @maxrow
        BEGIN
            SELECT @br = BranchCode, @brTotal = BranchTotal FROM #Branches WHERE RowNum = @row;

            INSERT INTO [dbo].[TicketMaster]
                (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber,
                 ReferenceNumber, ReferenceKey, Owner, Particulars,
                 EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
            VALUES
                (@parmvoucherdate, 0, @br, 'JV', @ticketnum,
                 @parmrefno, @parmcontrolno, @parmuser, ISNULL(@parmremarks,''),
                 @parmuser, '*', '*', 'POSTED',
                 CASE WHEN @AllowCrossBranch = 1 THEN 'MANUAL JV - CROSS-BR' ELSE 'MANUAL JV - MULTI-BR' END, NULL);

            INSERT INTO [dbo].[TicketDetails]
                (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                 TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
            SELECT @parmvoucherdate, 0, @br, @parmcontrolno, @ticketnum, @parmrefno, AccountCode, Debit, Credit, ''
            FROM @Lines WHERE BranchCode = @br
            ORDER BY [LineNo];                                          -- CHANGED 2026-09-25e

            DECLARE @voucherID INT;
            INSERT INTO dbo.ManualJournalVoucher
                (ReferenceNo, VoucherDate, BranchCode, Remarks, PreparedBy, TicketNumber, TotalAmount)
            VALUES (@parmrefno, @parmvoucherdate, @br, @parmremarks, @parmuser, @ticketnum, @brTotal);
            SET @voucherID = SCOPE_IDENTITY();

            INSERT INTO dbo.ManualJournalVoucherDetails (VoucherID, AccountCode, Debit, Credit, Particulars, [LineNo])
            SELECT @voucherID, AccountCode, Debit, Credit, Particulars, [LineNo]
            FROM @Lines WHERE BranchCode = @br
            ORDER BY [LineNo];                                          -- CHANGED 2026-09-25e

            SET @row += 1;
        END;

        DROP TABLE #Branches;

        EXEC dbo.sp_JV_PostBankReconForLines
            @ReferenceNo = @parmrefno, @VoucherDate = @parmvoucherdate,
            @DefaultBranch = NULL, @CreatedBy = @parmuser;

        COMMIT TRAN;

        SELECT 1 AS Status, @parmrefno AS ReferenceNo, @maxrow AS BranchesPosted,
               'Journal voucher posted successfully across ' + CAST(@maxrow AS VARCHAR) + ' branch(es).' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------
-- 3c. sp_EditManualJournalVoucher
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_EditManualJournalVoucher', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_EditManualJournalVoucher', 'sp_EditManualJournalVoucher_OLD_09252026170000';
GO

CREATE PROCEDURE [dbo].[sp_EditManualJournalVoucher]
(
    @parmrefno         VARCHAR(10),
    @parmcontrolno     VARCHAR(50),
    @parmvoucherdate   DATE,
    @parmremarks       VARCHAR(500),
    @parmuser          VARCHAR(50),
    @Lines             dbo.JournalVoucherLineMultiTVP_V2 READONLY,   -- CHANGED 2026-09-25e: V2 (+LineNo)
    @AllowCrossBranch  BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.ManualJournalVoucher WHERE ReferenceNo = @parmrefno)
    BEGIN
        THROW 59201, 'No existing journal voucher found for this Reference No — use the Post function for a new entry.', 1;
        RETURN;
    END

    IF (SELECT COUNT(*) FROM @Lines) < 2
        THROW 59202, 'A journal voucher needs at least two lines (one debit, one credit).', 1;

    IF EXISTS (SELECT 1 FROM @Lines WHERE (Debit > 0 AND Credit > 0) OR (Debit = 0 AND Credit = 0))
        THROW 59203, 'Each line must have an amount in either Debit or Credit, not both or neither.', 1;

    IF EXISTS (SELECT 1 FROM @Lines WHERE LTRIM(RTRIM(ISNULL(AccountCode,''))) = '')
        THROW 59204, 'Every line requires an Account Code.', 1;

    IF EXISTS (SELECT 1 FROM @Lines WHERE LTRIM(RTRIM(ISNULL(BranchCode,''))) = '')
        THROW 59205, 'Every line requires a Branch Code.', 1;

    DECLARE @TotalDebit DECIMAL(18,2), @TotalCredit DECIMAL(18,2);
    SELECT @TotalDebit = ISNULL(SUM(Debit),0), @TotalCredit = ISNULL(SUM(Credit),0) FROM @Lines;

    IF @TotalDebit <= 0
        THROW 59206, 'Entry total must be greater than zero.', 1;

    IF @TotalDebit <> @TotalCredit
        THROW 59208, 'Entry does not balance overall — total Debit must equal total Credit across all branches.', 1;

    IF @AllowCrossBranch = 0
    BEGIN
        IF EXISTS (SELECT BranchCode FROM @Lines GROUP BY BranchCode HAVING SUM(Debit) <> SUM(Credit))
        BEGIN
            DECLARE @BadBranches VARCHAR(200) = (
                SELECT STRING_AGG(BranchCode, ', ') FROM (
                    SELECT BranchCode FROM @Lines GROUP BY BranchCode HAVING SUM(Debit) <> SUM(Credit)
                ) x
            );
            DECLARE @BalanceMsg VARCHAR(400) = 'Entry does not balance per branch. Out-of-balance branch(es): ' + ISNULL(@BadBranches, '')
                + '. If this is intentional, check "Allow Cross-Branch Entry."';
            THROW 59207, @BalanceMsg, 1;
        END
    END

    BEGIN TRY
        BEGIN TRAN;

        DELETE FROM TicketDetails WHERE ReferenceNumber = @parmrefno;
        DELETE FROM TicketMaster WHERE ReferenceNumber = @parmrefno;
        DELETE FROM BankStatementRecon WHERE ReferenceNo = @parmrefno AND SourceModule = 'MANUAL-JV';

        DELETE FROM dbo.ManualJournalVoucherDetails
        WHERE VoucherID IN (SELECT VoucherID FROM dbo.ManualJournalVoucher WHERE ReferenceNo = @parmrefno);
        DELETE FROM dbo.ManualJournalVoucher WHERE ReferenceNo = @parmrefno;

        IF OBJECT_ID('tempdb..#EditBranches') IS NOT NULL DROP TABLE #EditBranches;
        SELECT ROW_NUMBER() OVER (ORDER BY BranchCode) AS RowNum, BranchCode, SUM(Debit) AS BranchTotal
        INTO #EditBranches FROM @Lines GROUP BY BranchCode;

        DECLARE @row INT = 1, @maxrow INT, @br VARCHAR(5), @brTotal DECIMAL(18,2), @ticketnum VARCHAR(20);
        SELECT @maxrow = COUNT(*) FROM #EditBranches;
        DECLARE @isMultiBranch BIT = CASE WHEN @maxrow > 1 THEN 1 ELSE 0 END;

        -- ONE ticket number for the whole voucher, shared across every
        -- branch — so an edit doesn't fragment a single-ticket entry.
        EXEC GetTicketNumber @ticketnum OUTPUT;

        WHILE @row <= @maxrow
        BEGIN
            SELECT @br = BranchCode, @brTotal = BranchTotal FROM #EditBranches WHERE RowNum = @row;

            INSERT INTO [dbo].[TicketMaster]
                (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber,
                 ReferenceNumber, ReferenceKey, Owner, Particulars,
                 EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
            VALUES
                (@parmvoucherdate, 0, @br, 'JV', @ticketnum,
                 @parmrefno, @parmcontrolno, @parmuser, ISNULL(@parmremarks,''),
                 @parmuser, '*', '*', 'POSTED',
                 CASE WHEN @AllowCrossBranch = 1 THEN 'MANUAL JV - CROSS-BR'
                      WHEN @isMultiBranch = 1 THEN 'MANUAL JV - MULTI-BR'
                      ELSE 'MANUAL JV' END, NULL);

            INSERT INTO [dbo].[TicketDetails]
                (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                 TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
            SELECT @parmvoucherdate, 0, @br, @parmcontrolno, @ticketnum, @parmrefno, AccountCode, Debit, Credit, ''
            FROM @Lines WHERE BranchCode = @br
            ORDER BY [LineNo];                                          -- CHANGED 2026-09-25e

            DECLARE @voucherID INT;
            INSERT INTO dbo.ManualJournalVoucher
                (ReferenceNo, VoucherDate, BranchCode, Remarks, PreparedBy, TicketNumber, TotalAmount)
            VALUES (@parmrefno, @parmvoucherdate, @br, @parmremarks, @parmuser, @ticketnum, @brTotal);
            SET @voucherID = SCOPE_IDENTITY();

            INSERT INTO dbo.ManualJournalVoucherDetails (VoucherID, AccountCode, Debit, Credit, Particulars, [LineNo])
            SELECT @voucherID, AccountCode, Debit, Credit, Particulars, [LineNo]
            FROM @Lines WHERE BranchCode = @br
            ORDER BY [LineNo];                                          -- CHANGED 2026-09-25e

            SET @row += 1;
        END;

        DROP TABLE #EditBranches;

        EXEC dbo.sp_JV_PostBankReconForLines
            @ReferenceNo = @parmrefno, @VoucherDate = @parmvoucherdate,
            @DefaultBranch = NULL, @CreatedBy = @parmuser;

        COMMIT TRAN;

        SELECT 1 AS Status, @parmrefno AS ReferenceNo, @maxrow AS BranchesPosted,
               'Journal voucher updated successfully.' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------
-- 4. sp_GetManualJournalVoucherDetails
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_GetManualJournalVoucherDetails', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetManualJournalVoucherDetails', 'sp_GetManualJournalVoucherDetails_OLD_09252026170000';
GO

CREATE PROCEDURE [dbo].[sp_GetManualJournalVoucherDetails]
    @ReferenceNo VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        mjv.BranchCode,
        br.BranchName,
        mjvd.AccountCode,
        c.Description as AccountTitle,
        CAST(mjvd.Debit AS DECIMAL(18,2)) as Debit,
        CAST(mjvd.Credit AS DECIMAL(18,2)) as Credit,
        mjvd.Particulars
    FROM dbo.ManualJournalVoucher mjv
    JOIN dbo.ManualJournalVoucherDetails mjvd ON mjvd.VoucherID = mjv.VoucherID
    INNER JOIN dbo.ChartOfAccounts c ON mjvd.AccountCode=c.AccountCode
    INNER JOIN Branches br ON mjv.BranchCode=br.BranchCode
    WHERE mjv.ReferenceNo = @ReferenceNo
    -- CHANGED 2026-09-25e: encoded order (was BranchCode, AccountCode).
    -- Pre-fix rows have LineNo NULL -> branch, then insertion (DetailID) order.
    ORDER BY mjvd.[LineNo], mjv.BranchCode, mjvd.DetailID;
END
GO
