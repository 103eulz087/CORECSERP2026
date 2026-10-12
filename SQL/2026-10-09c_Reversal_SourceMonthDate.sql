/* ================================================================
   2026-10-09c: payment reversals dated like their source entry
   ================================================================
   Accountants' rule (2026-10-09): a reversal falls into the month of the
   source entry, the same as the source entry. Until now the AP-cheque and
   cash-advance reversals were dated the day the reversal was done, so a
   cheque issued in August and voided in September stayed in August's GL
   while the bank recon hid it from August (see 2026-10-09b, the data fix
   for the 16 items found).

   Changes (anchor patches, same parameters, backups _OLD_10092026150000):
     * sp_ReverseTicketsAP (cheque / cash / telegraphic voucher reversal,
       called by sp_CancelledChequesCS): each reversal ticket and its lines
       take the date of the ticket / line they reverse, not GETDATE();
     * sp_ReverseCashAdvanceEntry: the same for cash advances and transfers;
     * sp_CancelledChequesCS: the supplier-ledger reversal row takes the
       TransactionDate of the row it reverses (PostingDate stays = today);
     * sp_ReversePaymentClient: its GL ticket was already dated on the payment
       date; the client-ledger reversal row now takes the TransactionDate of
       the row it reverses too (it was GETDATE()).
   Audit columns (CancelledDate, ReversedDate, ResolvedDate, PostingDate,
   PaymentReversalAudit, ...) still record when the reversal was done.

   A source month that is closed in the GL (GLPeriodLock) refuses the
   reversal (the lock triggers, 59900), the same as any posting into it.

   Works with the current exe (no parameter changes). One transaction with a
   post-check. Needs nothing else first.
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
    DECLARE @old SYSNAME = @Obj + N'_OLD_10092026150000', @full NVARCHAR(300) = N'dbo.' + @Obj;
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
IF OBJECT_ID('dbo.sp_ReverseTicketsAP_OLD_10092026150000', 'P') IS NOT NULL
BEGIN
    RAISERROR('This script has been run here before (sp_ReverseTicketsAP_OLD_10092026150000 exists).', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
DECLARE @LF NCHAR(1) = NCHAR(10);
INSERT INTO #Patch (Obj, OldText, NewText) VALUES
-- sp_ReverseTicketsAP: master row from #ReverseTickets (has the source TicketDate), lines from the source lines
(N'sp_ReverseTicketsAP',
 N'            CAST(GETDATE() as date),' + @LF + N'            SupplementaryNumber,' + @LF + N'            BranchCode,' + @LF + N'            Origin,',
 N'            CAST(TicketDate as date),   -- 2026-10-09c: the source ticket''s date (was the reversal day)' + @LF + N'            SupplementaryNumber,' + @LF + N'            BranchCode,' + @LF + N'            Origin,'),
(N'sp_ReverseTicketsAP',
 N'            CAST(GETDATE() as date),' + @LF + N'            SupplementaryNumber,' + @LF + N'            BranchCode,' + @LF + N'            ReferenceKey,',
 N'            CAST(TicketDate as date),   -- 2026-10-09c: the source line''s date (was the reversal day)' + @LF + N'            SupplementaryNumber,' + @LF + N'            BranchCode,' + @LF + N'            ReferenceKey,'),

-- sp_ReverseCashAdvanceEntry: both inserts select from the source rows
(N'sp_ReverseCashAdvanceEntry',
 N'                CAST(GETDATE() AS DATE), SupplementaryNumber, BranchCode, Origin, @newTicket,',
 N'                CAST(TicketDate AS DATE), SupplementaryNumber, BranchCode, Origin, @newTicket,   -- 2026-10-09c: the source ticket''s date'),
(N'sp_ReverseCashAdvanceEntry',
 N'                CAST(GETDATE() AS DATE), SupplementaryNumber, BranchCode, ReferenceKey,',
 N'                CAST(TicketDate AS DATE), SupplementaryNumber, BranchCode, ReferenceKey,   -- 2026-10-09c: the source line''s date'),

-- sp_CancelledChequesCS: supplier-ledger reversal row
(N'sp_CancelledChequesCS',
 N'            GETDATE(), @parmreferenceno, L.ReferenceKey, L.InvoiceNo,',
 N'            L.TransactionDate, @parmreferenceno, L.ReferenceKey, L.InvoiceNo,   -- 2026-10-09c: the reversed row''s date (was the reversal day)'),

-- sp_ReversePaymentClient: client-ledger reversal row
(N'sp_ReversePaymentClient',
 N'        CL.TransCode, GETDATE(),',
 N'        CL.TransCode, CL.TransactionDate,   -- 2026-10-09c: the reversed row''s date (was the reversal day)');
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'sp_ReverseTicketsAP';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'sp_ReverseCashAdvanceEntry';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'sp_CancelledChequesCS';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'sp_ReversePaymentClient';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReverseTicketsAP')) NOT LIKE '%2026-10-09c%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReverseTicketsAP')) LIKE '%GETDATE()%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReverseCashAdvanceEntry')) NOT LIKE '%CAST(TicketDate AS DATE), SupplementaryNumber, BranchCode, ReferenceKey%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS')) NOT LIKE '%L.TransactionDate, @parmreferenceno%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient')) NOT LIKE '%CL.TransCode, CL.TransactionDate%'
BEGIN
    RAISERROR('Post-check failed; rolled back.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
COMMIT TRANSACTION;
PRINT 'Reversals dated like their source entry (backups _OLD_10092026150000).';
GO
SET NOEXEC OFF;
GO
