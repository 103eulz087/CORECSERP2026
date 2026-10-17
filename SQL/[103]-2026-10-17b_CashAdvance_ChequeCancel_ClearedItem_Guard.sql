/* ================================================================
   [103] 2026-10-17b  Cash advance reversal and cheque cancel: a bank item already ticked as cleared
   ================================================================
   User (2026-10-17): "yes add the same guard to cash advance and cheque" (after [101], the AR payment guard 93030).

   WHY
   The reversals close the document's bank-recon items only while they are OPEN (IsResolved = 0). An item already
   ticked as cleared stays CLEARED for a document that no longer exists, and when the document is keyed again its new
   item is ticked too: the bank side counts the money twice while the GL counts it once (PRODUCTION 2026-10-17,
   AR side: O-CR-011241, refs 38760 -> 45337, PNB PESO August; fixed by [101]). The same gap was left in:
   - sp_ReverseCashAdvanceEntry (Supplier Voucher Reversal, the manual / cash-advance leg): voids its OC / DIT items
     WHERE IsResolved = 0;
   - sp_CancelledChequesCS (Supplier Voucher Reversal invoice leg + View Check Voucher's cheque cancel):
     sp_BankRecon_VoidOC voids the OC items WHERE IsResolved = 0.

   RULES
   - A cash advance whose own bank item (OC or DIT: voucher id + SourceModule CASH-ADVANCE + SourceRef = reference,
     the items the reversal voids) is already ticked as cleared can't be reversed: 93031 (reference, account, amount,
     kind, month). The accountant unticks it first if the tick was a mistake.
   - A supplier voucher whose cheque / bank payment is already ticked as cleared can't be cancelled / reversed: 93032.
     Scope = the items sp_BankRecon_VoidOC would void (OC under the reference): the voucher's own items read with
     UPDLOCK + HOLDLOCK through the index (ReferenceNo = voucher id, SourceRef = reference), and any other OC under the
     reference read plainly, a best-effort probe without a range lock (none with an amount on any tier: the 2
     AP-PAYMENT items whose ReferenceNo is not a voucher id are the known zero-amount rows of refs 20571 / 20580; a
     locked scan of the whole table on every reversal was not worth it). Only when a voucher id is given (the void
     runs only then). The message names the item (cheque / payment or cash advance: on a combined voucher the cash
     advance's own item is found here first, under the same voucher id and reference) and says a cleared item means
     the bank has paid it.
   - sp_ReverseCashAdvanceEntry takes the voucher id once (ORDER BY VoucherID); the void reuses it, so the check and
     the void see the same items (both were unordered TOP 1 lookups; 0 references with two voucher ids on DEV).
   - Both: a zero-amount item never blocks; REVERSED / VOID% items don't count (same predicate as [101] / [90]'s 60402).
     The check sits before the reversal's first write, inside its transaction (the CATCH rolls back and re-throws),
     and before the lock checks 93027 / 93006, so a cleared item gets the cleared message.
   - Same rule already in place: AR payment 93030 ([101]), GL-only telegraphic voucher 60402 ([90]).

   Measured first (2026-10-17, read-only): cleared items of a REVERSED cash advance / supplier voucher: DEV 0 /
   STAGING 0 / PRODUCTION 0 (nothing to repair; Exception Center BankRecon section 7 = 0 on every tier). Live
   documents that would now be refused (cleared items): cash advances DEV 50 refs (35 OC + 15 DIT) / STAGING 50 /
   PRODUCTION 83 (68 OC + 15 DIT); supplier voucher refs with a cleared OC DEV 95 / STAGING 95 / PRODUCTION 95.
   OC SourceRef shared by two modules: 0 on every tier. Error codes 93031 / 93032 unused on every tier.
   Guard: sp_ReverseCashAdvanceEntry 0E2B7B1F… and sp_CancelledChequesCS 40486C39… = their live texts
   (whitespace-insensitive SHA-256, identical on DEV / STAGING / PRODUCTION 2026-10-17; = the [88] / [97] texts).
   Needs: [88] (93027 in the cash-advance proc) and [97] (MIXED in the cheque proc). sp_BankRecon_VoidOC unchanged.
   One transaction with a post-check; backups _OLD_10172026180000.
   Exe: no change; old and new exe show the proc's message ("Reversal failed: ..."). Web v2: the same rule applies to
   any client that reverses a cash advance or cancels a supplier voucher.
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
    RAISERROR('[103] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.sp_ReverseCashAdvanceEntry', 'P') IS NULL OR OBJECT_ID('dbo.sp_CancelledChequesCS', 'P') IS NULL
BEGIN
    RAISERROR('[103] stopped: sp_ReverseCashAdvanceEntry or sp_CancelledChequesCS does not exist in this database; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReverseCashAdvanceEntry')) LIKE '%[[]103]%'
     AND OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS')) LIKE '%[[]103]%'
BEGIN
    RAISERROR('[103] already applied in this database; nothing changed.', 10, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.sp_ReverseCashAdvanceEntry_OLD_10172026180000') IS NOT NULL
     OR OBJECT_ID('dbo.sp_CancelledChequesCS_OLD_10172026180000') IS NOT NULL
BEGIN
    RAISERROR('[103] stopped: a backup proc _OLD_10172026180000 already exists; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReverseCashAdvanceEntry')) NOT LIKE '%93027%'
     OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS')) NOT LIKE '%MIXED%'
BEGIN
    RAISERROR('[103] stopped: needs [88] and [97] first; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReverseCashAdvanceEntry')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '0E2B7B1F3F81798BF492FD4062628BA11E305DB26EBAC122AF09C77255E04B6A'
BEGIN
    RAISERROR('[103] stopped: sp_ReverseCashAdvanceEntry is not the text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '40486C392956F2CC52C592DFD1CDBE6066C46483DCFC777089CD05956E50A7A6'
BEGIN
    RAISERROR('[103] stopped: sp_CancelledChequesCS is not the text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[103] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
GO

------------------------------------------------------------------
-- 1. sp_ReverseCashAdvanceEntry: refuse a cleared own item (93031)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReverseCashAdvanceEntry'));
DECLARE @nl NCHAR(2) = NCHAR(13) + NCHAR(10);
DECLARE @a NVARCHAR(400) = N'IF OBJECT_ID(''tempdb..#CATickets'') IS NOT NULL DROP TABLE #CATickets;';
DECLARE @cnt INT = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @a, N''))) / DATALENGTH(@a), @m NVARCHAR(400);
IF @cnt <> 1
BEGIN
    SET @m = N'[103] sp_ReverseCashAdvanceEntry anchor found ' + CAST(@cnt AS NVARCHAR(5)) + N' times.';
    THROW 59898, @m, 1;
END
SET @def = REPLACE(@def, @a, CAST(N'' AS NVARCHAR(MAX))
  + N'-- [103] 2026-10-17: a bank item of this cash advance already ticked as cleared in Bank Recon is refused (93031). The void' + @nl
  + N'        --       below closes OPEN items only, so a cleared one stayed CLEARED and a re-keyed advance''s item was ticked too' + @nl
  + N'        --       (the bank side counted the money twice; same gap as [101] for AR). Same scope as the void (voucher id +' + @nl
  + N'        --       CASH-ADVANCE + SourceRef, the index seek). UPDLOCK + HOLDLOCK: no tick between this check and the void.' + @nl
  + N'        DECLARE @CAVid103 VARCHAR(10), @clr103Found BIT = 0, @clr103Msg NVARCHAR(2048);' + @nl
  + N'        SELECT TOP (1) @CAVid103 = VoucherID FROM dbo.CashAdvance WHERE ReferenceNo = @parmreferenceno ORDER BY VoucherID;' + @nl
  + N'        SELECT TOP (1) @clr103Found = 1,' + @nl
  + N'               @clr103Msg = N''Cannot reverse: the bank item of cash advance '' + ISNULL(@parmreferenceno, N''?'') + N'' ('' + ISNULL(b.AccountCode, N''?'') + N'', ''' + @nl
  + N'                   + ISNULL(FORMAT(b.Amount, ''N2''), N''?'') + N'', '' + CASE b.ItemType WHEN ''DIT'' THEN N''deposit'' ELSE N''payment'' END' + @nl
  + N'                   + N'') is already ticked as cleared in Bank Recon (month '' + ISNULL(CONVERT(NVARCHAR(7), COALESCE(b.ClearedPeriodEnd, h.PeriodEnd), 120), N''?'')' + @nl
  + N'                   + N''). Ask the accountant to untick it first if the tick was a mistake (or reopen that month if it is locked), then reverse.''' + @nl
  + N'        FROM dbo.BankStatementRecon AS b WITH (UPDLOCK, HOLDLOCK)' + @nl
  + N'        LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID' + @nl
  + N'        WHERE b.ReferenceNo = @CAVid103 AND b.SourceModule = ''CASH-ADVANCE'' AND b.SourceRef = @parmreferenceno' + @nl
  + N'          AND b.ItemType IN (''OC'', ''DIT'') AND b.IsResolved = 1 AND b.Amount <> 0' + @nl
  + N'          AND ISNULL(b.ResolvedReason, '''') <> ''REVERSED'' AND ISNULL(b.ResolvedReason, '''') NOT LIKE ''VOID%''' + @nl
  + N'        ORDER BY b.ReconID;' + @nl
  + N'        IF @clr103Found = 1' + @nl
  + N'            THROW 93031, @clr103Msg, 1;' + @nl
  + @nl
  + N'        ' + @a);
-- the void's own voucher-id lookup (an unordered TOP 1) now reuses the checked id, so check and void see the same items
DECLARE @a2 NVARCHAR(400) = N'SELECT TOP 1 @CAVoucherID = VoucherID FROM dbo.CashAdvance WHERE ReferenceNo = @parmreferenceno;';
SET @cnt = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @a2, N''))) / DATALENGTH(@a2);
IF @cnt <> 1
BEGIN
    SET @m = N'[103] sp_ReverseCashAdvanceEntry anchor 2 found ' + CAST(@cnt AS NVARCHAR(5)) + N' times.';
    THROW 59898, @m, 1;
END
SET @def = REPLACE(@def, @a2, N'SET @CAVoucherID = @CAVid103;   /* [103] the voucher id the cleared-item check used */');
EXEC sp_rename 'dbo.sp_ReverseCashAdvanceEntry', 'sp_ReverseCashAdvanceEntry_OLD_10172026180000';
EXEC (@def);
GO

------------------------------------------------------------------
-- 2. sp_CancelledChequesCS: refuse a cleared cheque / payment (93032)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS'));
DECLARE @nl NCHAR(2) = NCHAR(13) + NCHAR(10);
DECLARE @a NVARCHAR(400) = N'-- NEW 2026-09-24: a voucher that created supplier advance credit';
DECLARE @cnt INT = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @a, N''))) / DATALENGTH(@a), @m NVARCHAR(400);
IF @cnt <> 1
BEGIN
    SET @m = N'[103] sp_CancelledChequesCS anchor found ' + CAST(@cnt AS NVARCHAR(5)) + N' times.';
    THROW 59898, @m, 1;
END
SET @def = REPLACE(@def, @a, CAST(N'' AS NVARCHAR(MAX))
  + N'-- [103] 2026-10-17: a cheque / bank payment of this voucher already ticked as cleared in Bank Recon is refused (93032).' + @nl
  + N'        --       sp_BankRecon_VoidOC (end of this proc) closes OPEN items only, so a cleared one stayed CLEARED and a re-issued' + @nl
  + N'        --       payment''s item was ticked too (the bank side counted the money twice; same gap as [101] for AR). Same scope as' + @nl
  + N'        --       the void (OC under the reference): the voucher''s own items with UPDLOCK + HOLDLOCK through the index' + @nl
  + N'        --       (ReferenceNo = voucher id), any other OC under the reference read plainly: a best-effort probe without a' + @nl
  + N'        --       range lock (the index leads with ReferenceNo; such items: 0 with an amount on every tier, 10-17).' + @nl
  + N'        DECLARE @clr103Found BIT = 0, @clr103Msg NVARCHAR(2048);' + @nl
  + N'        IF LEN(LTRIM(RTRIM(ISNULL(@parmvoucherid, '''')))) > 0' + @nl
  + N'        BEGIN' + @nl
  + N'            SELECT TOP (1) @clr103Found = 1,' + @nl
  + N'                   @clr103Msg = N''Cannot reverse: the bank item of voucher reference '' + ISNULL(@parmreferenceno, N''?'') + N'' ('' + ISNULL(b.AccountCode, N''?'') + N'', ''' + @nl
  + N'                       + ISNULL(FORMAT(b.Amount, ''N2''), N''?'') + N'', '' + CASE WHEN b.SourceModule = ''CASH-ADVANCE'' THEN N''cash advance'' ELSE N''cheque / payment'' END' + @nl
  + N'                       + N'') is already ticked as cleared in Bank Recon (month '' + ISNULL(CONVERT(NVARCHAR(7), COALESCE(b.ClearedPeriodEnd, h.PeriodEnd), 120), N''?'')' + @nl
  + N'                       + N''). A cleared item means the bank has paid it. If the tick was a mistake, ask the accountant to untick it first (or reopen that month if it is locked), then reverse.''' + @nl
  + N'            FROM dbo.BankStatementRecon AS b WITH (UPDLOCK, HOLDLOCK)' + @nl
  + N'            LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID' + @nl
  + N'            WHERE b.ReferenceNo = @parmvoucherid AND b.SourceRef = @parmreferenceno AND b.ItemType = ''OC''' + @nl
  + N'              AND b.IsResolved = 1 AND b.Amount <> 0' + @nl
  + N'              AND ISNULL(b.ResolvedReason, '''') <> ''REVERSED'' AND ISNULL(b.ResolvedReason, '''') NOT LIKE ''VOID%''' + @nl
  + N'            ORDER BY b.ReconID;' + @nl
  + N'            IF @clr103Found = 0' + @nl
  + N'                SELECT TOP (1) @clr103Found = 1,' + @nl
  + N'                       @clr103Msg = N''Cannot reverse: a bank item under voucher reference '' + ISNULL(@parmreferenceno, N''?'') + N'' ('' + ISNULL(b.AccountCode, N''?'') + N'', ''' + @nl
  + N'                           + ISNULL(FORMAT(b.Amount, ''N2''), N''?'') + N'', '' + ISNULL(b.SourceModule, N''?'') + N'') is already ticked as cleared in Bank Recon (month ''' + @nl
  + N'                           + ISNULL(CONVERT(NVARCHAR(7), COALESCE(b.ClearedPeriodEnd, h.PeriodEnd), 120), N''?'')' + @nl
  + N'                           + N''). If the tick was a mistake, ask the accountant to untick it first (or reopen that month if it is locked), then reverse.''' + @nl
  + N'                FROM dbo.BankStatementRecon AS b' + @nl
  + N'                LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID' + @nl
  + N'                WHERE b.SourceRef = @parmreferenceno AND b.ItemType = ''OC''' + @nl
  + N'                  AND b.IsResolved = 1 AND b.Amount <> 0' + @nl
  + N'                  AND ISNULL(b.ResolvedReason, '''') <> ''REVERSED'' AND ISNULL(b.ResolvedReason, '''') NOT LIKE ''VOID%''' + @nl
  + N'                ORDER BY b.ReconID;' + @nl
  + N'        END' + @nl
  + N'        IF @clr103Found = 1' + @nl
  + N'            THROW 93032, @clr103Msg, 1;' + @nl
  + @nl
  + N'        ' + @a);
EXEC sp_rename 'dbo.sp_CancelledChequesCS', 'sp_CancelledChequesCS_OLD_10172026180000';
EXEC (@def);
GO

------------------------------------------------------------------
-- 3. Post-check, then commit
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
DECLARE @ca NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReverseCashAdvanceEntry')),
        @cc NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS'));
IF @ca IS NULL OR @ca NOT LIKE '%[[]103]%' OR @ca NOT LIKE '%THROW 93031%'
    SET @msg = N'sp_ReverseCashAdvanceEntry is not the [103] text';
ELSE IF @cc IS NULL OR @cc NOT LIKE '%[[]103]%' OR @cc NOT LIKE '%THROW 93032%'
    SET @msg = N'sp_CancelledChequesCS is not the [103] text';
ELSE IF OBJECT_ID('dbo.sp_ReverseCashAdvanceEntry_OLD_10172026180000', 'P') IS NULL
     OR OBJECT_ID('dbo.sp_CancelledChequesCS_OLD_10172026180000', 'P') IS NULL
    SET @msg = N'a backup is missing';
-- the new checks must come before the first write of each proc
ELSE IF CHARINDEX(N'THROW 93031', @ca) > CHARINDEX(N'INSERT INTO TicketMaster', @ca)
     OR CHARINDEX(N'THROW 93031', @ca) > CHARINDEX(N'THROW 93027', @ca)
     OR CHARINDEX(N'THROW 93031', @ca) < CHARINDEX(N'BEGIN TRAN', @ca)
    SET @msg = N'93031 is not inside the transaction, before the cash advance''s first write / lock check';
ELSE IF @ca NOT LIKE N'%SET @CAVoucherID = @CAVid103;%'
    SET @msg = N'the cash advance''s void does not reuse the checked voucher id';
ELSE IF CHARINDEX(N'THROW 93032', @cc) < CHARINDEX(N'BEGIN TRAN', @cc)
     OR CHARINDEX(N'THROW 93032', @cc) > CHARINDEX(N'UPDATE ', @cc)
     OR CHARINDEX(N'THROW 93032', @cc) > CHARINDEX(N'INSERT INTO', @cc)
    SET @msg = N'93032 is not before the cheque cancel''s first write';

IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[103] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59897, @msg, 1;
END

COMMIT TRANSACTION;
PRINT '[103] committed: cash advance reversal refuses a cleared item (93031), cheque cancel refuses a cleared payment (93032).';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
