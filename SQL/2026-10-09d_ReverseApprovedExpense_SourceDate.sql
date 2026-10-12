/* ================================================================
   2026-10-09d: expense approval reversal dated like the expense
   ================================================================
   Same accountants' rule as 2026-10-09c (a reversal falls into the month of
   its source entry, dated like it), extended by the user on 2026-10-09 to
   sp_ReverseApprovedExpense (ViewExpenseDevEx > reverse an approved, unpaid
   expense; no bank leg).

   Changes (anchor patch, same parameters, backup _OLD_10092026170000):
     * each reversal ticket and its lines take the date of the expense ticket /
       line they reverse (was the reversal day);
     * the supplier-ledger reversal row takes the TransactionDate of the row it
       reverses (PostingDate stays = today).
   Audit columns (ExpenseApprovalReversalAudit.ReversedDate, DateTimeUpdated)
   still record when it was done. A source month closed in GLPeriodLock refuses
   the reversal (59900). Works with the current exe. One transaction with a
   post-check.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
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
    DECLARE @old SYSNAME = @Obj + N'_OLD_10092026170000', @full NVARCHAR(300) = N'dbo.' + @Obj;
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
IF OBJECT_ID('dbo.sp_ReverseApprovedExpense_OLD_10092026170000', 'P') IS NOT NULL
BEGIN
    RAISERROR('This script has been run here before (sp_ReverseApprovedExpense_OLD_10092026170000 exists).', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
INSERT INTO #Patch (Obj, OldText, NewText) VALUES
(N'sp_ReverseApprovedExpense',
 N'                CAST(GETDATE() as date), SupplementaryNumber, BranchCode, Origin, @newTicket,',
 N'                CAST(TicketDate as date), SupplementaryNumber, BranchCode, Origin, @newTicket,   -- 2026-10-09d: the expense ticket''s date'),
(N'sp_ReverseApprovedExpense',
 N'                CAST(GETDATE() as date), SupplementaryNumber, BranchCode, ReferenceKey,',
 N'                CAST(TicketDate as date), SupplementaryNumber, BranchCode, ReferenceKey,   -- 2026-10-09d: the expense line''s date'),
(N'sp_ReverseApprovedExpense',
 N'            L.ReferenceKey, L.InvoiceNo, L.Credit, L.TotalAmount, L.BatchReferenceID,',
 N'            L.ReferenceKey, L.InvoiceNo, L.Credit, L.TotalAmount, L.BatchReferenceID, L.TransactionDate,   -- 2026-10-09d'),
(N'sp_ReverseApprovedExpense',
 N'            GETDATE(), @parmrefno, o.ReferenceKey, o.InvoiceNo,',
 N'            o.TransactionDate, @parmrefno, o.ReferenceKey, o.InvoiceNo,   -- 2026-10-09d: the reversed row''s date');
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'sp_ReverseApprovedExpense';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReverseApprovedExpense')) NOT LIKE '%CAST(TicketDate as date), SupplementaryNumber, BranchCode, Origin%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReverseApprovedExpense')) NOT LIKE '%CAST(TicketDate as date), SupplementaryNumber, BranchCode, ReferenceKey%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReverseApprovedExpense')) NOT LIKE '%o.TransactionDate, @parmrefno%'
BEGIN
    RAISERROR('Post-check failed; rolled back.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
COMMIT TRANSACTION;
PRINT 'sp_ReverseApprovedExpense: reversal dated like the expense (backup _OLD_10092026170000).';
GO
SET NOEXEC OFF;
GO
