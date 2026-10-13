/* ================================================================
   [72] 2026-10-13g - Expense posting: an entry with no payable line owes 0, not NULL (proc fix + data repair)
   ================================================================
   Found by the Exception Center AP check AP-INVOICE-VS-LEDGER ([70]) on 2026-10-13.

   Cause: spu_PostExpenseV2 sets @PayableAmount = SUM(Credit) of the payable accounts (20101 / 20102 / 20103). When the
   entry has no payable line (a reclassification keyed on the expense screen, e.g. DR Inventory / CR Prepayment -
   Others), that SUM is NULL; the guard that refused it (56001) is commented out on purpose (such entries are allowed),
   so the NULL went into ExpenseSummary.Balance and the SupplierLedger row's Credit / Ending / TotalAmount, while the
   branch lines (ExpenseMaster) got Balance = their debit, i.e. "owed" although nothing is payable.
   PRODUCTION / STAGING: 6 entries (5 x "BOXES FOR SI-... (REVERSED PREPAYMENT)" of supplier 000023, keyed 09-29,
   dated 08-03..08-06; CI-0002483-REVERSAL of 000006, a light-and-water reclass dated 08-20). DEV: none.
   Nothing is owed on any of them (no payable credit on their tickets, no payment).

   Fix (no exe change; sp_EditSingleExpense reposts through spu_PostExpenseV2, so edits are covered):
     1. spu_PostExpenseV2: @PayableAmount = ISNULL(..., 0); when it is 0 the branch lines are written with Balance 0
        (an entry with a payable line is unchanged).
     2. Data, only rows that match exactly: ExpenseSummary Balance NULL whose reference has no payable credit in its
        tickets, no payment (APPaymentDetails) and AmountPaid 0 -> Balance 0; their ExpenseMaster lines -> Balance 0;
        their SNGLE SupplierLedger row: NULL Debit / Credit / TotalAmount -> 0 (trg_SupplierLedger_Recalc re-chains).
   Anchor patches (backup spu_PostExpenseV2_OLD_10132026220000); data backups Expense_NoPayable_Backup_20261013_*.
   One transaction with a post-check. DEV, then STAGING (user's go), then PRODUCTION (user).
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
    DECLARE @old SYSNAME = @Obj + N'_OLD_10132026220000', @full NVARCHAR(300) = N'dbo.' + @Obj;
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
IF OBJECT_ID('dbo.spu_PostExpenseV2_OLD_10132026220000', 'P') IS NOT NULL OR OBJECT_ID('dbo.Expense_NoPayable_Backup_20261013_Summary', 'U') IS NOT NULL
BEGIN
    RAISERROR('[72] has been run here before (spu_PostExpenseV2_OLD_10132026220000 or the backup tables exist).', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── 1. spu_PostExpenseV2 ─────────────────────────────────────────────
DECLARE @LF NCHAR(1) = NCHAR(10);
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'spu_PostExpenseV2',
    N'        WHERE AccountCode IN (''20101'',''20102'',''20103'')--= @PayableAccountCode',
    N'        WHERE AccountCode IN (''20101'',''20102'',''20103'')--= @PayableAccountCode' + @LF +
    N'        -- 2026-10-13g [72]: an entry with no payable line (e.g. a reclass) owes 0, not NULL' + @LF +
    N'        SET @PayableAmount = ISNULL(@PayableAmount, 0);');
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'spu_PostExpenseV2',
    N'            ''UNPAID'',' + @LF + N'            Debit,' + @LF + N'            0,' + @LF + N'            @TicketNumber',
    N'            ''UNPAID'',' + @LF + N'            CASE WHEN @PayableAmount = 0 THEN 0 ELSE Debit END,   -- [72]: nothing payable, nothing owed per branch' + @LF +
    N'            0,' + @LF + N'            @TicketNumber');
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'spu_PostExpenseV2';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── 2. data: entries posted with a NULL payable ────────────────────
SELECT es.ReferenceNumber, es.SupplierID, es.InvoiceNo, es.BatchReferenceID, es.Amount,
       (SELECT COUNT(*) FROM dbo.TicketDetails td WHERE LTRIM(RTRIM(td.ReferenceNumber)) = LTRIM(RTRIM(es.ReferenceNumber))) AS nTicketLines,
       (SELECT COUNT(*) FROM dbo.TicketDetails td WHERE LTRIM(RTRIM(td.ReferenceNumber)) = LTRIM(RTRIM(es.ReferenceNumber))
          AND td.AccountCode IN ('20101', '20102', '20103') AND td.Credit > 0) AS nPayableCredits,
       (SELECT COUNT(*) FROM dbo.APPaymentDetails p WHERE p.SupplierID = es.SupplierID AND p.InvoiceNo = es.InvoiceNo AND p.BatchReferenceID = es.BatchReferenceID) AS nPayments
INTO #R72
FROM dbo.ExpenseSummary es
WHERE es.Balance IS NULL AND ISNULL(es.AmountPaid, 0) = 0;

SELECT * FROM #R72 ORDER BY ReferenceNumber;
IF EXISTS (SELECT 1 FROM #R72 WHERE nTicketLines = 0 OR nPayableCredits > 0 OR nPayments > 0)
BEGIN
    RAISERROR('An entry with a NULL balance has a payable credit, a payment or no ticket: it is not a "nothing payable" entry; nothing was changed.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
SELECT es.* INTO dbo.Expense_NoPayable_Backup_20261013_Summary FROM dbo.ExpenseSummary es INNER JOIN #R72 r ON r.ReferenceNumber = es.ReferenceNumber AND r.SupplierID = es.SupplierID;
SELECT m.* INTO dbo.Expense_NoPayable_Backup_20261013_Lines FROM dbo.ExpenseMaster m
    INNER JOIN #R72 r ON r.SupplierID = m.SupplierID AND r.InvoiceNo = m.InvoiceNo AND r.BatchReferenceID = m.BatchReferenceID;
SELECT s.* INTO dbo.Expense_NoPayable_Backup_20261013_Ledger FROM dbo.SupplierLedger s
    INNER JOIN #R72 r ON r.SupplierID = s.SupplierKey AND LTRIM(RTRIM(s.ReferenceNumber)) = LTRIM(RTRIM(r.ReferenceNumber)) AND s.TransCode = 'SNGLE';

UPDATE es SET es.Balance = 0
FROM dbo.ExpenseSummary es INNER JOIN #R72 r ON r.ReferenceNumber = es.ReferenceNumber AND r.SupplierID = es.SupplierID;
UPDATE m SET m.Balance = 0
FROM dbo.ExpenseMaster m INNER JOIN #R72 r ON r.SupplierID = m.SupplierID AND r.InvoiceNo = m.InvoiceNo AND r.BatchReferenceID = m.BatchReferenceID
WHERE ISNULL(m.AmountPaid, 0) = 0;
UPDATE s SET s.Debit = ISNULL(s.Debit, 0), s.Credit = ISNULL(s.Credit, 0), s.TotalAmount = ISNULL(s.TotalAmount, 0)
FROM dbo.SupplierLedger s
INNER JOIN #R72 r ON r.SupplierID = s.SupplierKey AND LTRIM(RTRIM(s.ReferenceNumber)) = LTRIM(RTRIM(r.ReferenceNumber)) AND s.TransCode = 'SNGLE';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── post-check ───────────────────────────────────────────────────────
DECLARE @bad NVARCHAR(1000) = NULL;
IF OBJECT_DEFINITION(OBJECT_ID('dbo.spu_PostExpenseV2')) NOT LIKE '%SET @PayableAmount = ISNULL(@PayableAmount, 0);%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.spu_PostExpenseV2')) NOT LIKE '%CASE WHEN @PayableAmount = 0 THEN 0 ELSE Debit END%'
    SET @bad = N'spu_PostExpenseV2 not patched';
IF EXISTS (SELECT 1 FROM dbo.ExpenseSummary es INNER JOIN #R72 r ON r.ReferenceNumber = es.ReferenceNumber AND r.SupplierID = es.SupplierID WHERE es.Balance IS NULL OR es.Balance <> 0)
    SET @bad = N'a repaired entry still has a balance';
IF EXISTS (SELECT 1 FROM dbo.SupplierLedger s INNER JOIN #R72 r ON r.SupplierID = s.SupplierKey AND LTRIM(RTRIM(s.ReferenceNumber)) = LTRIM(RTRIM(r.ReferenceNumber))
           WHERE s.Debit IS NULL OR s.Credit IS NULL OR s.EndingBalance IS NULL OR s.BeginningBalance IS NULL)
    SET @bad = N'a repaired ledger row still has a NULL amount';
IF EXISTS (SELECT 1 FROM dbo.SupplierLedger s WHERE s.SupplierKey IN (SELECT SupplierID FROM #R72)
           AND ABS(s.EndingBalance - (s.BeginningBalance + s.Credit - s.Debit)) >= 0.005)
   OR EXISTS (SELECT 1 FROM dbo.SupplierAccounts a WHERE a.SupplierKey IN (SELECT SupplierID FROM #R72)
              AND ABS(a.AccountBalance - ISNULL((SELECT TOP 1 x.EndingBalance FROM dbo.SupplierLedger x WHERE x.SupplierKey = a.SupplierKey ORDER BY x.TRN_SEQ_NO DESC), 0)) >= 0.005)
    SET @bad = N'an affected supplier''s ledger chain or account does not tie';
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
SELECT ReferenceNumber, SupplierID, InvoiceNo, Balance FROM dbo.ExpenseSummary
WHERE ReferenceNumber IN (SELECT ReferenceNumber FROM dbo.Expense_NoPayable_Backup_20261013_Summary) ORDER BY ReferenceNumber;
GO
