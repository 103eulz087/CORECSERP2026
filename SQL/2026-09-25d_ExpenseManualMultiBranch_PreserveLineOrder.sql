/* ================================================================
   2026-09-25d: AccountingDevEx/ExpenseManualMultiBranchFrm.cs --
   keep GL lines in the order the user encoded them.
   ================================================================
   PROBLEM:
     Edit (and View Details / Copy) showed the GL lines regrouped by
     branch, not in the order they were typed:
       - sp_GetExpenseManualMultiBranchDetails: ORDER BY BranchCode, LineID
       - Post/Edit: INSERT ... SELECT FROM @Lines with no ORDER BY, so
         even LineID (IDENTITY) order is not guaranteed to match the grid.
     Saving an edit re-posted the regrouped order, locking it in.

   FIX:
     1. ExpenseManualLines.LineNo INT NULL -- the grid position (1..n).
        Existing rows stay NULL and fall back to LineID order.
     2. New TVP type dbo.ExpenseManualLineTVP_V2 = old columns + LineNo.
        The old type is left in place: the _OLD_ backup procs still
        reference it (a type in use can't be altered/dropped anyway).
     3. sp_PostExpenseManualMultiBranch / sp_EditExpenseManualMultiBranch:
        take the V2 TVP, store LineNo, and insert every line-derived
        table (ExpenseMaster, ExpenseManualLines, TicketDetails)
        ORDER BY LineNo. No other logic changed.
     4. sp_GetExpenseManualMultiBranchDetails: ORDER BY LineNo, LineID.

   C# (same change set): ExpenseManualMultiBranchFrm.BuildLinesTVP()
   sends LineNo and TypeName = dbo.ExpenseManualLineTVP_V2. The C# build
   and this script must be deployed together -- an older exe calling
   the new procs fails with an operand-type-clash on @Lines.

   Only callers (grepped): AccountingDevEx/ExpenseManualMultiBranchFrm.cs.
   Deploy to CORECSERP_002_DEV first; CORECSJFC2026_STAGING only after
   the user confirms.
   ================================================================ */

-- ----------------------------------------------------------------
-- 1. ExpenseManualLines.LineNo
-- ----------------------------------------------------------------
IF COL_LENGTH('dbo.ExpenseManualLines', 'LineNo') IS NULL
    ALTER TABLE dbo.ExpenseManualLines ADD [LineNo] INT NULL;
GO

-- ----------------------------------------------------------------
-- 2. dbo.ExpenseManualLineTVP_V2
-- ----------------------------------------------------------------
IF TYPE_ID('dbo.ExpenseManualLineTVP_V2') IS NULL
    CREATE TYPE dbo.ExpenseManualLineTVP_V2 AS TABLE
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
-- 3a. sp_PostExpenseManualMultiBranch
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_PostExpenseManualMultiBranch', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_PostExpenseManualMultiBranch', 'sp_PostExpenseManualMultiBranch_OLD_09252026160000';
GO

CREATE PROCEDURE [dbo].[sp_PostExpenseManualMultiBranch]
(
    @parmrefno        VARCHAR(20),
    @parminvoiceno    VARCHAR(150),
    @parmsupplierid   VARCHAR(20),
    @parmexpensedate  DATE,
    @parmremarks      VARCHAR(500),
    @parmuser         VARCHAR(50),
    @Lines            dbo.ExpenseManualLineTVP_V2 READONLY,   -- CHANGED 2026-09-25d: V2 (+LineNo)
    @AllowCrossBranch BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @supplierkey VARCHAR(15), @suppliername VARCHAR(150);
    SELECT @supplierkey = SupplierKey, @suppliername = SupplierName
    FROM Supplier WHERE SupplierID = @parmsupplierid;

    IF @supplierkey IS NULL
    BEGIN
        THROW 57001, 'Supplier not found for the given SupplierID.', 1;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM ExpenseSummary WHERE SupplierID = @supplierkey AND InvoiceNo = @parminvoiceno)
    BEGIN
        THROW 57002, 'Invoice No. already exists for this supplier.', 1;
        RETURN;
    END

    IF (SELECT COUNT(*) FROM @Lines) < 2
    BEGIN
        THROW 57003, 'An entry needs at least two lines (one debit, one credit).', 1;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM @Lines WHERE (Debit > 0 AND Credit > 0) OR (Debit = 0 AND Credit = 0))
    BEGIN
        THROW 57004, 'Each line must have an amount in either Debit or Credit, not both or neither.', 1;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM @Lines WHERE LTRIM(RTRIM(ISNULL(AccountCode,''))) = '')
    BEGIN
        THROW 57005, 'Every line requires an Account Code.', 1;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM @Lines WHERE LTRIM(RTRIM(ISNULL(BranchCode,''))) = '')
    BEGIN
        THROW 57006, 'Every line requires a Branch Code.', 1;
        RETURN;
    END

    DECLARE @TotalDebit DECIMAL(18,2), @TotalCredit DECIMAL(18,2);
    SELECT @TotalDebit = ISNULL(SUM(Debit),0), @TotalCredit = ISNULL(SUM(Credit),0) FROM @Lines;

    IF @TotalDebit <= 0
    BEGIN
        THROW 57007, 'Entry total must be greater than zero.', 1;
        RETURN;
    END

    IF @TotalDebit <> @TotalCredit
    BEGIN
        THROW 57008, 'Entry does not balance overall — total Debit must equal total Credit.', 1;
        RETURN;
    END

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
                + '. If this is intentional (e.g. one branch funding others'' expenses), check "Allow Cross-Branch Entry."';
            THROW 57009, @BalanceMsg, 1;
            RETURN;
        END
    END

    -- Payable amount/account — same heuristic spu_PostExpenseV2 already
    -- uses (sum of Credit on the AP-Trade-type whitelist), generalized
    -- across all branches. This is the value the payment module will
    -- eventually need to settle against once that side is built.
    DECLARE @PayableAmount DECIMAL(18,2);
    SELECT @PayableAmount = ISNULL(SUM(Credit), 0)
    FROM @Lines WHERE AccountCode IN ('20101','20102','20103');

    DECLARE @PayableAccountCode VARCHAR(20) = (
        SELECT TOP 1 AccountCode FROM @Lines
        WHERE AccountCode IN ('20101','20102','20103') AND Credit > 0
        ORDER BY AccountCode
    );

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @BatchID BIGINT;
        EXEC GetBatchReferenceID @BatchID OUTPUT;

        INSERT INTO ExpenseSummary
        (
            ReferenceNumber, InvoiceNo, SupplierID, Description, BatchReferenceID,
            Status, Amount, ExpenseDate, AddedBy, DateTimeAdded,
            Balance, AmountPaid, ShipmentNo,
            PostingMode, PayableAccountCode
        )
        VALUES
        (
            @parmrefno, @parminvoiceno, @supplierkey, @parmremarks, @BatchID,
            'POSTED', @TotalDebit, @parmexpensedate, @parmuser, GETDATE(),
            @PayableAmount, 0, '',
            'MULTI-MANUAL', @PayableAccountCode
        );

        -- ExpenseMaster — DEBIT lines only, same convention as spu_PostExpenseV2
        INSERT INTO ExpenseMaster
        (
            TRN_SEQ_NO, BranchCode, SupplierID, ReferenceNumber, BatchReferenceID,
            InvoiceNo, ExpenseName, ExpenseDate,
            Amount, Remarks, Status, Balance, AmountPaid
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY [LineNo]),                     -- CHANGED 2026-09-25d: encoded order
            BranchCode, @supplierkey, @parmrefno, @BatchID,
            @parminvoiceno, Particulars, @parmexpensedate,
            Debit, 'D-' + ISNULL(@parmremarks,''), 'UNPAID', Debit, 0
        FROM @Lines
        WHERE Debit > 0
        ORDER BY [LineNo];

        -- Full Dr/Cr audit — what View/Copy/Edit actually read
        INSERT INTO dbo.ExpenseManualLines
            (ReferenceNumber, InvoiceNo, SupplierID, BatchReferenceID, BranchCode, AccountCode, Debit, Credit, Particulars, [LineNo])
        SELECT @parmrefno, @parminvoiceno, @supplierkey, @BatchID, BranchCode, AccountCode, Debit, Credit, Particulars, [LineNo]
        FROM @Lines
        ORDER BY [LineNo];                                              -- CHANGED 2026-09-25d

        -- One TicketMaster/TicketDetails pair PER BRANCH — same
        -- convention as Manual JV Multi-Branch
        IF OBJECT_ID('tempdb..#Branches') IS NOT NULL DROP TABLE #Branches;
        SELECT ROW_NUMBER() OVER (ORDER BY BranchCode) AS RowNum, BranchCode,
               SUM(Debit) AS BranchDebit,
               ISNULL(SUM(CASE WHEN AccountCode IN ('20101','20102','20103') THEN Credit ELSE 0 END), 0) AS BranchPayable
        INTO #Branches
        FROM @Lines GROUP BY BranchCode;

        DECLARE @row INT = 1, @maxrow INT, @br VARCHAR(5), @brDebit DECIMAL(18,2),
                @brPayable DECIMAL(18,2), @ticketnum VARCHAR(20), @transid INT;
        SELECT @maxrow = COUNT(*) FROM #Branches;
         EXEC GetTicketNumber @ticketnum OUTPUT;
        WHILE @row <= @maxrow
        BEGIN
            SELECT @br = BranchCode, @brDebit = BranchDebit, @brPayable = BranchPayable
            FROM #Branches WHERE RowNum = @row;



            INSERT INTO [dbo].[TicketMaster]
                (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber,
                 ReferenceNumber, ReferenceKey, Owner, Particulars,
                 EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
            VALUES
                (@parmexpensedate, 0, @br, 'EXP', @ticketnum,
                 @parmrefno, @parminvoiceno, @suppliername, ISNULL(@parmremarks,''),
                 @parmuser, '*', '*', 'POSTED',
                 CASE WHEN @AllowCrossBranch = 1 THEN 'EXP-MANUAL-CROSS-BR' ELSE 'EXP-MANUAL-MULTI-BR' END, NULL);

            INSERT INTO [dbo].[TicketDetails]
                (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                 TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
            SELECT @parmexpensedate, 0, @br, @parminvoiceno, @ticketnum, @parmrefno, AccountCode, Debit, Credit, ''
            FROM @Lines WHERE BranchCode = @br
            ORDER BY [LineNo];                                          -- CHANGED 2026-09-25d

            -- Update ExpenseMaster with the ticket reference for this branch's lines
            UPDATE ExpenseMaster SET TicketReference = @ticketnum
            WHERE ReferenceNumber = @parmrefno AND InvoiceNo = @parminvoiceno
              AND SupplierID = @supplierkey AND BranchCode = @br;

            IF @brPayable > 0
            BEGIN
                SET @transid = dbo.func_getLastID(@supplierkey);
                INSERT INTO [dbo].[SupplierLedger]
                    (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate,
                     Description, TransCode, TransactionDate, ReferenceNumber,
                     ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance,
                     TransactedBy, ApprovedBy, TotalAmount, PaymentType,
                     ErrorCorrectTag, TicketReference, BatchReferenceID)
                VALUES
                    (@transid, @supplierkey, @supplierkey, @parmexpensedate,
                     LEFT(ISNULL(@parmremarks,''), 490), 'EXP-MANUAL', @parmexpensedate,
                     @parmrefno, CAST(@BatchID AS VARCHAR(40)) + '-' + @br, @parminvoiceno,
                     0, 0, @brPayable, @brPayable,
                     @parmuser, '*', @brPayable, 'UNPAID', 0, @ticketnum, @BatchID);
            END

            SET @row += 1;
        END;

        DROP TABLE #Branches;

        EXEC dbo.sp_JV_PostBankReconForLines
            @ReferenceNo = @parmrefno, @VoucherDate = @parmexpensedate,
            @DefaultBranch = NULL, @CreatedBy = @parmuser;

        COMMIT TRAN;

        SELECT 'Expense posted successfully across ' + CAST(@maxrow AS VARCHAR) + ' branch(es).' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------
-- 3b. sp_EditExpenseManualMultiBranch
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_EditExpenseManualMultiBranch', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_EditExpenseManualMultiBranch', 'sp_EditExpenseManualMultiBranch_OLD_09252026160000';
GO

CREATE PROCEDURE [dbo].[sp_EditExpenseManualMultiBranch]
(
    @parmrefno         VARCHAR(20),      -- unchanged identity, as before
    @parmoldinvoiceno  VARCHAR(150),     -- WHICH record to find/delete
    @parmoldsupplierid VARCHAR(20),      -- (SupplierKey) WHICH record to find/delete
    @parminvoiceno     VARCHAR(150),     -- NEW invoice no. (same as old if unchanged)
    @parmsupplierid    VARCHAR(20),      -- NEW supplier key (same as old if unchanged)
    @parmexpensedate   DATE,
    @parmremarks       VARCHAR(500),
    @parmuser          VARCHAR(50),
    @Lines             dbo.ExpenseManualLineTVP_V2 READONLY,   -- CHANGED 2026-09-25d: V2 (+LineNo)
    @AllowCrossBranch  BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CurAmountPaid DECIMAL(18,2), @BatchID BIGINT;
    SELECT @CurAmountPaid = ISNULL(es.AmountPaid,0), @BatchID = es.BatchReferenceID
    FROM ExpenseSummary es
    WHERE es.ReferenceNumber = @parmrefno AND es.InvoiceNo = @parmoldinvoiceno
      AND es.SupplierID = @parmoldsupplierid AND es.PostingMode = 'MULTI-MANUAL';

    IF @BatchID IS NULL
    BEGIN
        THROW 57101, 'MULTI-MANUAL expense not found for this Reference/Invoice/Supplier.', 1;
        RETURN;
    END

    IF @CurAmountPaid > 0
    BEGIN
        THROW 57102, 'This expense already has a payment applied — editing is blocked.', 1;
        RETURN;
    END

    DECLARE @NewSupplierName VARCHAR(150);
    SELECT @NewSupplierName = SupplierName FROM Supplier WHERE SupplierKey = @parmsupplierid;
    IF @NewSupplierName IS NULL
    BEGIN
        THROW 57110, 'The new Supplier was not found.', 1;
        RETURN;
    END

    -- Duplicate check — only matters if the identity is actually
    -- changing. Excludes the record being edited (matched on OLD
    -- values) so editing back to the same values doesn't false-positive.
    IF (@parminvoiceno <> @parmoldinvoiceno OR @parmsupplierid <> @parmoldsupplierid)
       AND EXISTS (
           SELECT 1 FROM ExpenseSummary
           WHERE SupplierID = @parmsupplierid AND InvoiceNo = @parminvoiceno
             AND NOT (ReferenceNumber = @parmrefno AND InvoiceNo = @parmoldinvoiceno AND SupplierID = @parmoldsupplierid)
       )
    BEGIN
        THROW 57111, 'Another expense already exists for that Supplier/Invoice No. combination.', 1;
        RETURN;
    END

    IF (SELECT COUNT(*) FROM @Lines) < 2
        THROW 57103, 'An entry needs at least two lines (one debit, one credit).', 1;

    IF EXISTS (SELECT 1 FROM @Lines WHERE (Debit > 0 AND Credit > 0) OR (Debit = 0 AND Credit = 0))
        THROW 57104, 'Each line must have an amount in either Debit or Credit, not both or neither.', 1;

    IF EXISTS (SELECT 1 FROM @Lines WHERE LTRIM(RTRIM(ISNULL(AccountCode,''))) = '')
        THROW 57105, 'Every line requires an Account Code.', 1;

    IF EXISTS (SELECT 1 FROM @Lines WHERE LTRIM(RTRIM(ISNULL(BranchCode,''))) = '')
        THROW 57106, 'Every line requires a Branch Code.', 1;

    DECLARE @TotalDebit DECIMAL(18,2), @TotalCredit DECIMAL(18,2);
    SELECT @TotalDebit = ISNULL(SUM(Debit),0), @TotalCredit = ISNULL(SUM(Credit),0) FROM @Lines;

    IF @TotalDebit <= 0
        THROW 57107, 'Entry total must be greater than zero.', 1;

    IF @TotalDebit <> @TotalCredit
        THROW 57108, 'Entry does not balance overall — total Debit must equal total Credit.', 1;

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
                + '. Check "Allow Cross-Branch Entry" if intentional.';
            THROW 57109, @BalanceMsg, 1;
        END
    END

    DECLARE @PayableAmount DECIMAL(18,2);
    SELECT @PayableAmount = ISNULL(SUM(Credit), 0) FROM @Lines WHERE AccountCode IN ('20101','20102','20103');
    DECLARE @PayableAccountCode VARCHAR(20) = (
        SELECT TOP 1 AccountCode FROM @Lines
        WHERE AccountCode IN ('20101','20102','20103') AND Credit > 0
        ORDER BY AccountCode
    );

    BEGIN TRY
        BEGIN TRAN;

        -- ── Delete everything for the OLD identity ──
        DELETE FROM TicketDetails WHERE ReferenceNumber = @parmrefno AND ReferenceKey = @parmoldinvoiceno;
        DELETE FROM TicketMaster WHERE ReferenceNumber = @parmrefno AND ReferenceKey = @parmoldinvoiceno AND Origin = 'EXP';
        DELETE FROM SupplierLedger WHERE ReferenceNumber = @parmrefno AND InvoiceNo = @parmoldinvoiceno;
        DELETE FROM BankStatementRecon WHERE ReferenceNo = @parmrefno AND SourceModule = 'MANUAL-JV';
        DELETE FROM dbo.ExpenseManualLines
        WHERE ReferenceNumber = @parmrefno AND InvoiceNo = @parmoldinvoiceno AND SupplierID = @parmoldsupplierid;
        DELETE FROM ExpenseMaster
        WHERE ReferenceNumber = @parmrefno AND InvoiceNo = @parmoldinvoiceno AND SupplierID = @parmoldsupplierid;
        DELETE FROM ExpenseSummary
        WHERE ReferenceNumber = @parmrefno AND InvoiceNo = @parmoldinvoiceno AND SupplierID = @parmoldsupplierid;

        -- ── Re-insert fresh under the NEW identity ──
        INSERT INTO ExpenseSummary
        (
            ReferenceNumber, InvoiceNo, SupplierID, Description, BatchReferenceID,
            Status, Amount, ExpenseDate, AddedBy, DateTimeAdded,
            Balance, AmountPaid, ShipmentNo,
            PostingMode, PayableAccountCode
        )
        VALUES
        (
            @parmrefno, @parminvoiceno, @parmsupplierid, @parmremarks, @BatchID,
            'POSTED', @TotalDebit, @parmexpensedate, @parmuser, GETDATE(),
            @PayableAmount, 0, '',
            'MULTI-MANUAL', @PayableAccountCode
        );

        INSERT INTO ExpenseMaster
        (
            TRN_SEQ_NO, BranchCode, SupplierID, ReferenceNumber, BatchReferenceID,
            InvoiceNo, ExpenseName, ExpenseDate,
            Amount, Remarks, Status, Balance, AmountPaid
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY [LineNo]),                     -- CHANGED 2026-09-25d: encoded order
            BranchCode, @parmsupplierid, @parmrefno, @BatchID,
            @parminvoiceno, Particulars, @parmexpensedate,
            Debit, 'D-' + ISNULL(@parmremarks,''), 'UNPAID', Debit, 0
        FROM @Lines
        WHERE Debit > 0
        ORDER BY [LineNo];

        INSERT INTO dbo.ExpenseManualLines
            (ReferenceNumber, InvoiceNo, SupplierID, BatchReferenceID, BranchCode, AccountCode, Debit, Credit, Particulars, [LineNo])
        SELECT @parmrefno, @parminvoiceno, @parmsupplierid, @BatchID, BranchCode, AccountCode, Debit, Credit, Particulars, [LineNo]
        FROM @Lines
        ORDER BY [LineNo];                                              -- CHANGED 2026-09-25d

        IF OBJECT_ID('tempdb..#EditBranches') IS NOT NULL DROP TABLE #EditBranches;
        SELECT ROW_NUMBER() OVER (ORDER BY BranchCode) AS RowNum, BranchCode,
               ISNULL(SUM(CASE WHEN AccountCode IN ('20101','20102','20103') THEN Credit ELSE 0 END), 0) AS BranchPayable
        INTO #EditBranches
        FROM @Lines GROUP BY BranchCode;

        DECLARE @row INT = 1, @maxrow INT, @br VARCHAR(5), @brPayable DECIMAL(18,2),
                @ticketnum VARCHAR(20), @transid INT;
        SELECT @maxrow = COUNT(*) FROM #EditBranches;

        WHILE @row <= @maxrow
        BEGIN
            SELECT @br = BranchCode, @brPayable = BranchPayable FROM #EditBranches WHERE RowNum = @row;

            EXEC GetTicketNumber @ticketnum OUTPUT;

            INSERT INTO [dbo].[TicketMaster]
                (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber,
                 ReferenceNumber, ReferenceKey, Owner, Particulars,
                 EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
            VALUES
                (@parmexpensedate, 0, @br, 'EXP', @ticketnum,
                 @parmrefno, @parminvoiceno, @NewSupplierName, ISNULL(@parmremarks,''),
                 @parmuser, '*', '*', 'POSTED',
                 CASE WHEN @AllowCrossBranch = 1 THEN 'EXP-MANUAL-CROSS-BR' ELSE 'EXP-MANUAL-MULTI-BR' END, NULL);

            INSERT INTO [dbo].[TicketDetails]
                (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                 TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
            SELECT @parmexpensedate, 0, @br, @parminvoiceno, @ticketnum, @parmrefno, AccountCode, Debit, Credit, ''
            FROM @Lines WHERE BranchCode = @br
            ORDER BY [LineNo];                                          -- CHANGED 2026-09-25d

            UPDATE ExpenseMaster SET TicketReference = @ticketnum
            WHERE ReferenceNumber = @parmrefno AND InvoiceNo = @parminvoiceno
              AND SupplierID = @parmsupplierid AND BranchCode = @br;

            IF @brPayable > 0
            BEGIN
                SET @transid = dbo.func_getLastID(@parmsupplierid);
                INSERT INTO [dbo].[SupplierLedger]
                    (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate,
                     Description, TransCode, TransactionDate, ReferenceNumber,
                     ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance,
                     TransactedBy, ApprovedBy, TotalAmount, PaymentType,
                     ErrorCorrectTag, TicketReference, BatchReferenceID)
                VALUES
                    (@transid, @parmsupplierid, @parmsupplierid, @parmexpensedate,
                     LEFT(ISNULL(@parmremarks,''), 490), 'EXP-MANUAL', @parmexpensedate,
                     @parmrefno, CAST(@BatchID AS VARCHAR(40)) + '-' + @br, @parminvoiceno,
                     0, 0, @brPayable, @brPayable,
                     @parmuser, '*', @brPayable, 'UNPAID', 0, @ticketnum, @BatchID);
            END

            SET @row += 1;
        END;

        DROP TABLE #EditBranches;

        EXEC dbo.sp_JV_PostBankReconForLines
            @ReferenceNo = @parmrefno, @VoucherDate = @parmexpensedate,
            @DefaultBranch = NULL, @CreatedBy = @parmuser;

        COMMIT TRAN;

        SELECT 1 AS Status, @parmrefno AS ReferenceNo, @maxrow AS BranchesPosted,
               'Expense updated successfully.' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------
-- 4. sp_GetExpenseManualMultiBranchDetails — header + lines
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_GetExpenseManualMultiBranchDetails', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetExpenseManualMultiBranchDetails', 'sp_GetExpenseManualMultiBranchDetails_OLD_09252026160000';
GO

CREATE PROCEDURE [dbo].[sp_GetExpenseManualMultiBranchDetails]
(
    @ReferenceNumber VARCHAR(20),
    @InvoiceNo       VARCHAR(150),
    @SupplierID      VARCHAR(20)   -- SupplierKey
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        es.ReferenceNumber, es.InvoiceNo, es.SupplierID, s.SupplierName,
        es.ExpenseDate, es.Description AS Remarks, FORMAT(es.Amount,'N2') AS Amount, es.Balance,
        es.AmountPaid, es.Status,
        CASE WHEN es.AmountPaid > 0
             THEN 'This expense has a payment applied — editing is blocked.'
             ELSE NULL
        END AS BlockedReason
    FROM ExpenseSummary es
    JOIN Supplier s ON s.SupplierKey = es.SupplierID
    WHERE es.ReferenceNumber = @ReferenceNumber
      AND es.InvoiceNo = @InvoiceNo
      AND es.SupplierID = @SupplierID
      AND es.PostingMode = 'MULTI-MANUAL';

    SELECT
        l.BranchCode,br.BranchName, l.AccountCode, coa.Description AS AccountTitle,
        l.Debit, l.Credit, l.Particulars
    FROM dbo.ExpenseManualLines l
    LEFT JOIN ChartOfAccounts coa ON coa.AccountCode = l.AccountCode
    INNER JOIN Branches br ON l.BranchCode=br.BranchCode
    WHERE l.ReferenceNumber = @ReferenceNumber
      AND l.InvoiceNo = @InvoiceNo
      AND l.SupplierID = @SupplierID
    -- CHANGED 2026-09-25d: encoded order (was BranchCode, LineID).
    -- Pre-fix rows have LineNo NULL -> fall back to insertion (LineID) order.
    ORDER BY l.[LineNo], l.LineID;
END
GO
