/* ================================================================
   [85] 2026-10-14 - Hardening H2 + H4 (Fable session): AR reversal mirrors only the payment's own rows; the three
        multi-step postings become one transaction each
   ================================================================
   Handoff docs/handoff/2026-10-14_Hardening_Handoff_to_Fable.md, items H2 and H4 (user's go 2026-10-14). Needs [84]
   (sp_ReversePaymentClient must carry its marker). On PRODUCTION run after [83] and [84].

   H2  sp_ReversePaymentClient (anchor patches of the [84] text, backup _OLD_10152026003000)
       Steps 6-9 mirrored EVERY TicketMaster / TicketDetails / ClientLedger row WHERE ReferenceNumber = the payment's
       reference. Sales tickets keep the PO number in that same column (another counter), and the client ledger keeps
       the PO number on the SI row, so when the numbers meet, reversing a payment also reversed ANOTHER customer's sales
       ticket (a second master under the same reversal ticket number) and put a reversal of that customer's SI row on
       the OTHER customer's ledger. Measured 2026-10-14 (read-only): PRODUCTION 28 live payments share their reference
       with another customer's SI-VAT / SI-VATEX ticket (STAGING 26, DEV 22, where payment 4262 / ref 13382 meets sales
       ticket 14662 of PO 13382); no reversal has hit one yet (0 reversal tickets with two masters, 0 reversal ledger
       rows on another customer, all three tiers).
       Now: the payment's own ticket = Mnemonic 'OR-%' (2026-08-06 on) or no mnemonic with ReferenceKey = the reference
       (the 33 tickets of 08-01..08-05 on every tier), Status <> REVERSED; the lines are taken by that ticket number; the
       ledger rows by AccountKey = the customer AND TransCode 'OR-%'. Refusals: 60002 more than one payment ticket under
       the reference; 60004 the customer's ledger rows of the payment point at a ticket that is not the one mirrored
       (a missed own ticket would otherwise reopen the invoices with no GL reversal); 60003 post-check (the reversal
       ticket must mirror the payment ticket's lines and balance). Measured 2026-10-14 on all three tiers: 0 payment
       tickets with a NULL status, every live payment's ledger rows carry its own ticket and an OR- trans code, and the
       ledger filter drops no row (rows = invoices paid for every live payment: DEV 2,763 / STAGING 5,637 / PROD 6,736).
       What the old text really did on a collision: the two mirrored masters get the same TicketDate / branch 888 /
       reversal ticket number, so the TicketMaster primary key refuses the whole reversal (2627); those payments cannot
       be reversed at all until [85].
       Reviewed, no change needed: sp_ReverseTicketsAP (ReferenceNumber + ReferenceKey = voucher id: only the voucher's
       own SINGLE-PAY / EXP-ACCRUAL-PAY / VOUCHER-MANUAL / PV-AP tickets sit under that pair on all three tiers),
       sp_ReverseCashAdvanceEntry (by CashAdvance.TicketNumber), sp_ReverseApprovedExpense (+ ReferenceKey = invoice),
       sp_CancelApprovedServiceOrder (+ Mnemonic), spu_Loan_ReverseRevaluation (ticket number + branch),
       sp_CancelledChequesCS (supplier ledger by SupplierID + reference).

   H4  one transaction per business action (the inner procs nest safely since [84]):
       - sp_PostSupplierPaymentWithManualLines (recreated, backup _OLD_10152026003000): the invoice leg
         (sp_AddPaymentSupplierCompound_V2) used to commit on its own, then the manual lines (sp_PostCashAdvance) ran
         separately; a failure there left a half-posted voucher (cheque <> GL) and said "already posted, do not re-run"
         (60299). Now one transaction: a failure anywhere leaves nothing. 60299 is gone; the real error surfaces.
       - sp_ReverseCombinedSupplierVoucher (recreated, backup _OLD_10152026003000): had no transaction at all, so a
         refusal of the manual leg (60301 / 60302) left the invoice leg reversed and the voucher voided. Now one.
       - STS receive: HOFormsDevEx/ReceivedSTSBatchModeFIFO.cs made THREE calls, each committed on its own
         (spu_PostSTSReceiveFromFIFO, sp_ReverseSTSInventoryTransfer per unticked line, sp_ConfirmBranchRecievedOrderJFC);
         a failure in the confirm left branch stock received with the transfer still FOR DELIVERY and In Transit not
         cleared (Exception Center T04). New dbo.spu_STS_ReceiveTransfer does the three steps in one transaction
         (lock -> receive -> return the unticked rows -> confirm -> post-check), refuses a stale screen (59624 a row's
         lines changed, 59626 a line not on the screen), and returns the skipped lines like the receive proc did. The
         receive proc writes its skipped lines into the caller's #STSRcvSkipped when that table exists (anchor patch)
         instead of a result set. New type dbo.tt_STSReceiveReturnRows (DeliveryNo, SeqNo, LineCount) for the unticked
         rows. The new exe calls the wrapper; an old exe keeps working (the three procs are unchanged in behaviour).
         The legacy screen ReceivedSTSBatchMode (sp_AddBranchInventoryBatch) is not converted: its grid function
         funcview_DeliveryDetailsForReceiving does not exist on DEV, STAGING or PRODUCTION, so it fails on open.

   Exception Center: G04 (an AR reversal ticket with more than one master, or a reversal ledger row on another
   customer / not OR-coded) and T06 (branch received rows on a transfer not DELIVERED for over an hour).
   One transaction (after the committed type); a failure rolls everything back.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF CHARINDEX('[85]', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient'))) > 0
BEGIN
    RAISERROR('[85] already applied here; nothing to do.', 16, 1);
    SET NOEXEC ON;
END
ELSE
BEGIN
    DECLARE @bad NVARCHAR(400) = N'';
    DECLARE @Exp TABLE (Obj SYSNAME, Hash VARCHAR(66));
    INSERT INTO @Exp VALUES
        ('sp_ReversePaymentClient',               '0xBDC495126037C7ECE13D5DC44E0BE832CB47321BB006BEF4396EB788B0B2B12E'),   -- [84] text
        ('sp_PostSupplierPaymentWithManualLines', '0xCBC1C3B9DED0714B268EF1D08FC8F91076F9F3B7CB81A459EA7CFECF37F6396C'),   -- 2026-09-25
        ('sp_ReverseCombinedSupplierVoucher',     '0x67F2A0ECE9807A1C40AE99D6753D0C8B99C5D554C0798B98C0ED1BCD86834151'),   -- 2026-07-30
        ('spu_PostSTSReceiveFromFIFO',            '0x7D5942834CFFCEA23FBBAA5B9EE710F5EDEE9C6932DAE13355B3030C0536B39D');   -- 2026-10-03 (script 34)
    SELECT @bad = @bad + e.Obj + N' '
    FROM @Exp e
    WHERE ISNULL(CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.' + e.Obj)), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 1), '') <> e.Hash;
    IF @bad <> N'' OR EXISTS (SELECT 1 FROM sys.objects WHERE name LIKE '%[_]OLD[_]10152026003000')
       OR OBJECT_ID('dbo.spu_STS_ReceiveTransfer') IS NOT NULL
       OR OBJECT_ID('dbo.sp_ConfirmBranchRecievedOrderJFC') IS NULL OR OBJECT_ID('dbo.sp_ReverseSTSInventoryTransfer') IS NULL
       OR OBJECT_ID('dbo.sp_PostCashAdvance') IS NULL OR OBJECT_ID('dbo.sp_ReverseCashAdvanceEntry') IS NULL
    BEGIN
        SET @bad = N'[85] stopped, nothing changed: not the expected text (run [83] + [84] first on this database): ' + @bad + N'; or a [85] backup / spu_STS_ReceiveTransfer already exists; or an inner proc is missing.';
        RAISERROR(@bad, 16, 1);
        SET NOEXEC ON;
    END
END
GO

-- the type is created committed, outside the transaction (a type created inside a transaction cannot be used in it)
IF TYPE_ID('dbo.tt_STSReceiveReturnRows') IS NULL
    CREATE TYPE dbo.tt_STSReceiveReturnRows AS TABLE
    (
        DeliveryNo VARCHAR(20) NOT NULL,
        SeqNo      INT         NOT NULL,   -- the screen row's SeqNo (= GroupSeqNo when the rows are grouped)
        LineCount  INT         NULL        -- lines the row showed; NULL = not checked
    );
GO

BEGIN TRANSACTION;
GO

------------------------------------------------------------------
-- 1. anchor patches: sp_ReversePaymentClient (H2), spu_PostSTSReceiveFromFIFO (H4, skipped lines to the caller)
------------------------------------------------------------------
BEGIN TRY
    DECLARE @Patch TABLE (Obj SYSNAME, Ord INT, Anchor NVARCHAR(600), Repl NVARCHAR(MAX));
    -- {NL} = the object's own line ending
    INSERT INTO @Patch (Obj, Ord, Anchor, Repl) VALUES
    -- H2 step 6: the payment's own ticket(s) only, and a ticket number only when there is one
    (N'sp_ReversePaymentClient', 1,
     N'    IF EXISTS (SELECT 1 FROM TicketMaster WHERE ReferenceNumber = @refno)   -- [79] credits-only payments have no ticket{NL}        EXEC GetTicketNumber @ReversalTicketNo OUTPUT;',
     N'    -- [85] H2: only the payment''s OWN ticket is mirrored. Sales tickets keep the PO number in ReferenceNumber (another{NL}'
   + N'    --      counter), so the same number also belongs to other customers'' documents. A payment ticket = Mnemonic ''OR-%''{NL}'
   + N'    --      (2026-08-06 on) or no mnemonic with ReferenceKey = the reference (2026-08-01..05); never a REVERSED one.{NL}'
   + N'    DECLARE @OwnTickets TABLE (TicketNumber VARCHAR(20) PRIMARY KEY);{NL}'
   + N'    INSERT INTO @OwnTickets (TicketNumber){NL}'
   + N'    SELECT DISTINCT TM.TicketNumber{NL}'
   + N'    FROM TicketMaster TM{NL}'
   + N'    WHERE TM.ReferenceNumber = @refno AND ISNULL(TM.Status, '''') <> ''REVERSED''{NL}'
   + N'      AND (TM.Mnemonic LIKE ''OR-%'' OR (ISNULL(TM.Mnemonic, '''') = '''' AND TM.ReferenceKey = @refno));{NL}'
   + N'    IF (SELECT COUNT(*) FROM @OwnTickets) > 1{NL}'
   + N'        THROW 60002, ''More than one payment ticket is posted under this reference; the reversal cannot tell which one to mirror. Nothing was changed.'', 1;{NL}'
   + N'    IF EXISTS (SELECT 1 FROM @OwnTickets)   -- [79] credits-only payments have no ticket{NL}'
   + N'        EXEC GetTicketNumber @ReversalTicketNo OUTPUT;'),
    -- H2 step 7: master(s) of that ticket only
    (N'sp_ReversePaymentClient', 2,
     N'    FROM TicketMaster TM{NL}    WHERE TM.ReferenceNumber = @refno;',
     N'    FROM TicketMaster TM{NL}    INNER JOIN @OwnTickets O ON O.TicketNumber = TM.TicketNumber   -- [85]{NL}    WHERE TM.ReferenceNumber = @refno;'),
    -- H2 step 8: lines of that ticket only
    (N'sp_ReversePaymentClient', 3,
     N'    FROM TicketDetails TD{NL}    WHERE TD.ReferenceNumber = @refno;',
     N'    FROM TicketDetails TD{NL}    INNER JOIN @OwnTickets O ON O.TicketNumber = TD.TicketNumber   -- [85]{NL}    WHERE TD.ReferenceNumber = @refno;'),
    -- H2 step 9: this customer''s payment rows only
    (N'sp_ReversePaymentClient', 4,
     N'    FROM ClientLedger CL{NL}    WHERE CL.ReferenceNumber = @refno;',
     N'    FROM ClientLedger CL{NL}    WHERE CL.ReferenceNumber = @refno{NL}'
   + N'      AND CL.AccountKey = @custkey AND CL.TransCode LIKE ''OR-%''   -- [85] H2: the customer''s own payment rows (a sales row of another customer can carry the same number){NL}'
   + N'      AND ISNULL(CL.Remarks, '''') <> ''REVERSAL ENTRY'';'),
    -- H2 post-check before step 10
    (N'sp_ReversePaymentClient', 5,
     N'    -------------------------------------------------------{NL}    -- 10. MARK HEADER AS REVERSED',
     N'    -- [85] post-check 1: the customer''s ledger rows of this payment all point at the ticket(s) just mirrored (a missed own{NL}'
   + N'    --      ticket would reopen the invoices and reverse the ledger with no GL reversal; measured 2026-10-14: 0 such rows on any tier){NL}'
   + N'    IF EXISTS (SELECT 1 FROM ClientLedger CL{NL}'
   + N'               WHERE CL.ReferenceNumber = @refno AND CL.AccountKey = @custkey AND CL.TransCode LIKE ''OR-%'' AND ISNULL(CL.Remarks, '''') <> ''REVERSAL ENTRY''{NL}'
   + N'                 AND CL.TicketReference IS NOT NULL{NL}'
   + N'                 AND NOT EXISTS (SELECT 1 FROM @OwnTickets O WHERE O.TicketNumber = CAST(CL.TicketReference AS VARCHAR(20))))'
   + N'{NL}        THROW 60004, ''The customer''''s ledger rows of this payment point at a ticket that is not the payment''''s own ticket; the reversal cannot tell what to mirror. Nothing was changed.'', 1;{NL}'
   + N'    -- [85] post-check 2: the reversal ticket mirrors exactly the payment ticket''s lines, and balances{NL}'
   + N'    IF @ReversalTicketNo IS NOT NULL{NL}'
   + N'       AND (   (SELECT COUNT(*) FROM TicketDetails WHERE TicketNumber = CAST(@ReversalTicketNo AS VARCHAR(20))){NL}'
   + N'            <> (SELECT COUNT(*) FROM TicketDetails TD INNER JOIN @OwnTickets O ON O.TicketNumber = TD.TicketNumber WHERE TD.ReferenceNumber = @refno){NL}'
   + N'            OR (SELECT ABS(SUM(Debit) - SUM(Credit)) FROM TicketDetails WHERE TicketNumber = CAST(@ReversalTicketNo AS VARCHAR(20))) > 0.005 ){NL}'
   + N'        THROW 60003, ''Post-check: the reversal ticket does not mirror the payment ticket; nothing was changed.'', 1;{NL}'
   + N'{NL}'
   + N'    -------------------------------------------------------{NL}    -- 10. MARK HEADER AS REVERSED'),
    -- H4 STS: the receive proc hands its skipped lines to a caller that owns #STSRcvSkipped (spu_STS_ReceiveTransfer)
    (N'spu_PostSTSReceiveFromFIFO', 1,
     N'{NL}            SELECT SeqNo, Barcode, Reason FROM @SkippedLines;{NL}            RETURN;',
     N'{NL}            IF OBJECT_ID(''tempdb..#STSRcvSkipped'') IS NOT NULL   -- [85] the caller collects the skipped lines{NL}'
   + N'                INSERT INTO #STSRcvSkipped (SeqNo, Barcode, Reason) SELECT SeqNo, Barcode, Reason FROM @SkippedLines;{NL}'
   + N'            ELSE{NL}'
   + N'                SELECT SeqNo, Barcode, Reason FROM @SkippedLines;{NL}            RETURN;'),
    (N'spu_PostSTSReceiveFromFIFO', 2,
     N'{NL}        SELECT SeqNo, Barcode, Reason FROM @SkippedLines;{NL}    END TRY',
     N'{NL}        IF OBJECT_ID(''tempdb..#STSRcvSkipped'') IS NOT NULL   -- [85] the caller (spu_STS_ReceiveTransfer) collects the skipped lines{NL}'
   + N'            INSERT INTO #STSRcvSkipped (SeqNo, Barcode, Reason) SELECT SeqNo, Barcode, Reason FROM @SkippedLines;{NL}'
   + N'        ELSE{NL}'
   + N'            SELECT SeqNo, Barcode, Reason FROM @SkippedLines;{NL}    END TRY');

    DECLARE @obj SYSNAME, @def NVARCHAR(MAX), @msg NVARCHAR(400), @a NVARCHAR(600), @r NVARCHAR(MAX), @cnt INT, @bak SYSNAME, @nl NVARCHAR(2);
    DECLARE objs CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT Obj FROM @Patch;
    OPEN objs;
    FETCH NEXT FROM objs INTO @obj;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @def = OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + @obj));
        IF @def IS NULL BEGIN SET @msg = N'[85] ' + @obj + N' is missing here.'; THROW 59985, @msg, 1; END
        -- not a CASE: its result would be char(2), and a lone LF comes out padded to LF + space (spu_PostSTSReceiveFromFIFO is LF-only)
        IF CHARINDEX(CHAR(13) + CHAR(10), @def) > 0 SET @nl = CHAR(13) + CHAR(10); ELSE SET @nl = CHAR(10);

        DECLARE pt CURSOR LOCAL FAST_FORWARD FOR SELECT Anchor, Repl FROM @Patch WHERE Obj = @obj ORDER BY Ord;
        OPEN pt;
        FETCH NEXT FROM pt INTO @a, @r;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @a = REPLACE(@a, N'{NL}', @nl);
            SET @r = REPLACE(@r, N'{NL}', @nl);
            SET @cnt = (LEN(@def) - LEN(REPLACE(@def, @a, N''))) / LEN(@a);
            IF @cnt = 0 AND @nl = CHAR(13) + CHAR(10)   -- an object with mixed line endings (LF only around this anchor)
            BEGIN
                SET @a = REPLACE(@a, CHAR(13) + CHAR(10), CHAR(10));
                SET @r = REPLACE(@r, CHAR(13) + CHAR(10), CHAR(10));
                SET @cnt = (LEN(@def) - LEN(REPLACE(@def, @a, N''))) / LEN(@a);
            END
            IF @cnt <> 1 BEGIN SET @msg = N'[85] ' + @obj + N': anchor found ' + CAST(@cnt AS NVARCHAR(10)) + N' times (expected 1): ' + LEFT(REPLACE(@a, @nl, N'¶'), 120); THROW 59985, @msg, 1; END
            SET @def = REPLACE(@def, @a, @r);
            FETCH NEXT FROM pt INTO @a, @r;
        END
        CLOSE pt; DEALLOCATE pt;

        IF CHARINDEX(N'[85]', @def) = 0 BEGIN SET @msg = N'[85] ' + @obj + N': marker missing after patching.'; THROW 59985, @msg, 1; END
        SET @bak = @obj + N'_OLD_10152026003000';
        SET @a = N'dbo.' + @obj;
        EXEC sp_rename @a, @bak;
        EXEC (@def);
        PRINT N'[85] ' + @obj + N': patched (backup ' + @bak + N').';
        FETCH NEXT FROM objs INTO @obj;
    END
    CLOSE objs; DEALLOCATE objs;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @em NVARCHAR(2048) = N'[85] stopped, nothing changed (while patching ' + ISNULL(@obj, N'?') + N'): ' + ERROR_MESSAGE();
    RAISERROR(@em, 16, 1);
    SET NOEXEC ON;
END CATCH
GO

-- every later batch runs only while the one transaction is still open (a failed CREATE under XACT_ABORT rolls it back;
-- without this, the following batches would commit on their own and leave the database half-applied)
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[85] an earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
------------------------------------------------------------------
-- 2. sp_PostSupplierPaymentWithManualLines: one transaction (H4)
------------------------------------------------------------------
EXEC sp_rename 'dbo.sp_PostSupplierPaymentWithManualLines', 'sp_PostSupplierPaymentWithManualLines_OLD_10152026003000';
GO
CREATE PROCEDURE [dbo].[sp_PostSupplierPaymentWithManualLines]
(
    @parmrefno         VARCHAR(10),
    @parmvoucherid     VARCHAR(10),
    @parmsupplierid    VARCHAR(50),
    @parmsuppliername  VARCHAR(150),
    @parmcheckcoding   VARCHAR(50),
    @parmcheckno       VARCHAR(50)  = NULL,
    @parmcheckdate     DATE,
    @parmcontrolno     VARCHAR(50)  = NULL,
    @parmcheckremarks  VARCHAR(2000),
    @parmpreparedby    VARCHAR(30),
    @parmglcode        VARCHAR(30),
    @parmpaymethod     VARCHAR(20)  = 'EXPENSE',
    @parmforliquidation BIT         = 0,
    @parmvouchertype   VARCHAR(10),
    @parmPayingBranch  VARCHAR(5),
    @InvoiceLegAmount  DECIMAL(18,2),
    @InvoiceLines      dbo.AP_PaymentLineTVP READONLY,
    @ManualLines       dbo.ManualVoucherDebitLineTVP READONLY,
    @InvoiceLineExtras dbo.AP_PaymentLineExtraTVP READONLY   -- 2026-09-24, optional
)
AS
/*  [85] 2026-10-14 (hardening H4): the whole voucher is ONE transaction. Before, sp_AddPaymentSupplierCompound_V2
    committed the invoice leg on its own and sp_PostCashAdvance ran after it; a failure in the manual lines left a
    half-posted voucher (cheque <> GL) with the message 60299 "already posted ... do not re-run". Now a failure in
    any step leaves nothing, and the real error reaches the screen. Same parameters, same result set, same rows on
    the success path (compared old vs new on DEV). Error handling per docs/standards/2026-10-14_Posting_Proc_Error_Handling.md. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @InvoiceLineCount INT = (SELECT COUNT(*) FROM @InvoiceLines);
    DECLARE @ManualLineCount  INT = (SELECT COUNT(*) FROM @ManualLines);
    DECLARE @ManualTotal      DECIMAL(18,2) = (SELECT ISNULL(SUM(Amount),0) FROM @ManualLines);
    DECLARE @GrandTotal       DECIMAL(18,2) = ISNULL(@InvoiceLegAmount,0) + @ManualTotal;

    DECLARE @PhysicalRef VARCHAR(50) = CASE WHEN @parmvouchertype = 'CHECK' THEN @parmcheckno ELSE @parmcontrolno END;
    DECLARE @EffectiveDate DATE = @parmcheckdate;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @InvoiceLineCount = 0 AND @ManualLineCount = 0
            THROW 60201, 'Nothing to post - check at least one invoice or add at least one manual debit line.', 1;

        IF @ManualLineCount > 0 AND EXISTS (SELECT 1 FROM @ManualLines WHERE Amount <= 0)
            THROW 60202, 'Every manual debit line''s Amount must be greater than zero.', 1;

        IF @parmvouchertype = 'CHECK' AND (LTRIM(RTRIM(ISNULL(@parmcheckno,''))) = '' OR @parmcheckdate IS NULL)
            THROW 60203, 'Check No. and Check Date are required for a Check voucher.', 1;

        IF @parmvouchertype IN ('CASH','TELEGRAPHIC') AND (LTRIM(RTRIM(ISNULL(@parmcontrolno,''))) = '' )
            THROW 60204, 'Control No. and Date are required for Cash/Telegraphic vouchers.', 1;

        -- 1. the invoice leg (expense / purchase settlement, voucher header, GL, ledger, bank recon)
        IF @InvoiceLineCount > 0
        BEGIN
            EXEC sp_AddPaymentSupplierCompound_V2
                @parmrefno          = @parmrefno,
                @parmvoucherid      = @parmvoucherid,
                @parmsupplierid     = @parmsupplierid,
                @parmsuppliername   = @parmsuppliername,
                @parmcheckamount    = @InvoiceLegAmount,
                @parmcheckcoding    = @parmcheckcoding,
                @parmcheckno        = @parmcheckno,
                @parmcontrolno      = @parmcontrolno,
                @parmcheckdate      = @parmcheckdate,
                @parmcheckremarks   = @parmcheckremarks,
                @parmpreparedby     = @parmpreparedby,
                @parmglcode         = @parmglcode,
                @parmpaymethod      = @parmpaymethod,
                @parmforliquidation = @parmforliquidation,
                @parmvouchertype    = @parmvouchertype,
                @Lines              = @InvoiceLines,
                @parmPayingBranch   = @parmPayingBranch,
                @LineExtras         = @InvoiceLineExtras;
        END

        -- 2. the manual debit lines (cash advance rows + their tickets); [85] no TRY/CATCH of its own any more:
        --    a failure here rolls the invoice leg back with it
        IF @ManualLineCount > 0
        BEGIN
            DECLARE @CashAdvanceLines dbo.CashAdvanceLineTVP;
            INSERT INTO @CashAdvanceLines (BranchCode, AccountCode, PayeeName, Amount, Particulars)
            SELECT BranchCode, AccountCode, NULL, Amount, Particulars FROM @ManualLines;

            DECLARE @SkipVoucherInsertFlag BIT = CASE WHEN @InvoiceLineCount > 0 THEN 1 ELSE 0 END;

            EXEC sp_PostCashAdvance
                @parmrefno         = @parmrefno,
                @parmvoucherid     = @parmvoucherid,
                @parmsupplierid    = @parmsupplierid,
                @parmpayeename     = @parmsuppliername,
                @parmbranchcode    = @parmPayingBranch,
                @parmcheckcoding   = @parmcheckcoding,
                @parmcreditaccount = @parmglcode,
                @parmvouchertype   = @parmvouchertype,
                @parmcheckno       = @PhysicalRef,
                @parmcheckdate     = @EffectiveDate,
                @parmremarks       = @parmcheckremarks,
                @parmuser          = @parmpreparedby,
                @Lines             = @CashAdvanceLines,
                @SkipVoucherInsert = @SkipVoucherInsertFlag;
        END

        -- 3. a combined voucher carries the combined total on its header and its bank-recon item
        IF @InvoiceLineCount > 0 AND @ManualLineCount > 0
        BEGIN
            IF @parmvouchertype = 'CHECK'
                UPDATE CheckVoucher SET Amount = @GrandTotal
                WHERE ReferenceNumber = @parmrefno AND VoucherID = @parmvoucherid;
            ELSE IF @parmvouchertype = 'TELEGRAPHIC'
                UPDATE TelegraphicVoucher SET Amount = @GrandTotal
                WHERE ReferenceNumber = @parmrefno AND VoucherID = @parmvoucherid;
            ELSE
                UPDATE CashVoucher SET Amount = @GrandTotal
                WHERE ReferenceNumber = @parmrefno AND VoucherID = @parmvoucherid;

            UPDATE BankStatementRecon
            SET Amount = @GrandTotal,
                Remarks = Remarks + ' | Corrected to combined total (invoices + manual lines)'
            WHERE ReferenceNo = @parmvoucherid AND AccountCode = @parmglcode AND ItemType = 'OC';
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT 1 AS Status, @parmrefno AS ReferenceNo, @GrandTotal AS GrandTotal,
           'Combined voucher posted successfully.' AS Message;
END
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('[85] an earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
------------------------------------------------------------------
-- 3. sp_ReverseCombinedSupplierVoucher: one transaction (H4)
------------------------------------------------------------------
EXEC sp_rename 'dbo.sp_ReverseCombinedSupplierVoucher', 'sp_ReverseCombinedSupplierVoucher_OLD_10152026003000';
GO
-- ----------------------------------------------------------------
-- sp_ReverseCombinedSupplierVoucher - the single entry point of SupplierVoucherReversalFrm.
-- Inspects what is posted under this ReferenceNo and reverses whichever legs exist, together.
-- [85] 2026-10-14 (hardening H4): ONE transaction. It had none: a refusal of the manual leg (60301 / 60302) after
-- sp_CancelledChequesCS had committed left the invoice leg reversed and the voucher voided while the cash advance
-- stayed outstanding. Same parameters, same result set, same rows on the success path (compared old vs new on DEV).
-- ----------------------------------------------------------------
CREATE PROCEDURE [dbo].[sp_ReverseCombinedSupplierVoucher]
(
    @parmsupplierid  VARCHAR(50),
    @parmreferenceno VARCHAR(10),
    @parmvoucherid   VARCHAR(10),
    @parmvouchertype VARCHAR(20),   -- 'PURCHASE' or 'EXPENSE' - passed through to sp_CancelledChequesCS
    @parmcheckno     VARCHAR(50)  = NULL,
    @parmglcode      VARCHAR(30)  = NULL,
    @parmbranch      VARCHAR(5)   = NULL,
    @parmreason      VARCHAR(300),
    @parmuser        VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @HasInvoiceLeg BIT, @HasManualLeg BIT;

    BEGIN TRY
        BEGIN TRANSACTION;

        SET @HasInvoiceLeg = CASE WHEN EXISTS (
            SELECT 1 FROM APPaymentDetails WHERE ReferenceNumber = @parmreferenceno AND SupplierID = @parmsupplierid
        ) THEN 1 ELSE 0 END;

        SET @HasManualLeg = CASE WHEN EXISTS (
            SELECT 1 FROM dbo.CashAdvance WHERE ReferenceNo = @parmreferenceno AND SupplierID = @parmsupplierid AND Status <> 'REVERSED'
        ) THEN 1 ELSE 0 END;

        IF @HasInvoiceLeg = 0 AND @HasManualLeg = 0
            THROW 60401, 'Nothing found to reverse for this Reference No.', 1;

        -- Invoice leg: the existing proc, unchanged; it voids CheckVoucher / CashVoucher itself (right here, since
        -- both legs are reversed together the whole voucher ends up voided).
        IF @HasInvoiceLeg = 1
            EXEC sp_CancelledChequesCS
                @parmsupplierid  = @parmsupplierid,
                @parmreferenceno = @parmreferenceno,
                @parmvoucherid   = @parmvoucherid,
                @parmvouchertype = @parmvouchertype,
                @parmreason      = @parmreason,
                @parmuser        = @parmuser,
                @parmglcode      = @parmglcode,
                @parmbranch      = @parmbranch;

        -- Manual leg
        IF @HasManualLeg = 1
            EXEC sp_ReverseCashAdvanceEntry
                @parmreferenceno = @parmreferenceno,
                @parmreason      = @parmreason,
                @parmuser        = @parmuser;

        -- the voucher record itself (a manual-only voucher never went through sp_CancelledChequesCS)
        UPDATE CheckVoucher SET isErrorCorrect = 1, CancelledBy = @parmuser, CancelledDate = GETDATE(), CancelReason = @parmreason
        WHERE VoucherID = @parmvoucherid AND SupplierID = @parmsupplierid AND ReferenceNumber = @parmreferenceno;

        UPDATE CashVoucher SET isErrorCorrect = 1, DateUpdate = GETDATE()
        WHERE VoucherID = @parmvoucherid AND SupplierID = @parmsupplierid AND ReferenceNumber = @parmreferenceno;

        UPDATE TelegraphicVoucher SET isErrorCorrect = 1, DateUpdate = GETDATE()
        WHERE VoucherID = @parmvoucherid AND SupplierID = @parmsupplierid AND ReferenceNumber = @parmreferenceno;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT 1 AS Status,
           CONCAT('Voucher reversed. InvoiceLeg=', @HasInvoiceLeg, ' ManualLeg=', @HasManualLeg) AS Message;
END
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('[85] an earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
------------------------------------------------------------------
-- 4. spu_STS_ReceiveTransfer: the receive screen's three steps in one transaction (H4)
------------------------------------------------------------------
CREATE PROCEDURE dbo.spu_STS_ReceiveTransfer
(
    @PONumber    VARCHAR(10),
    @BranchCode  VARCHAR(10),
    @ReceivedBy  VARCHAR(40),                            -- user id (ReceivedOrderDetails, stock ledger)
    @PreparedBy  VARCHAR(30),                            -- full name (return + receipt tickets)
    @Lines       dbo.tt_STSReceiveFIFOLines  READONLY,   -- the ticked rows (received)
    @ReturnRows  dbo.tt_STSReceiveReturnRows READONLY,   -- the unticked rows (returned to the origin)
    @GroupedRows BIT        = 1,                         -- 1 = a row stands for the lines of its group (funcview_InventoryDeliveryFIFOForReceivingV2)
    @Origin      VARCHAR(10) = '888',                    -- the origin branch of the transfer (head office)
    @UseJFC      BIT        = 1                          -- 1 = sp_ConfirmBranchRecievedOrderJFC, 0 = sp_ConfirmBranchRecievedOrder
)
AS
/*  [85] 2026-10-14 (hardening H4). HOFormsDevEx/ReceivedSTSBatchModeFIFO.cs used to make three calls, each committed on
    its own: spu_PostSTSReceiveFromFIFO (branch stock + receipt rows), sp_ReverseSTSInventoryTransfer per unticked line
    (stock back to the origin), sp_ConfirmBranchRecievedOrderJFC (IT-BR / STS-SHORT / STS-OVER tickets, DELIVERED). A
    failure in a later step left the earlier ones committed (branch stock received, transfer still FOR DELIVERY, In
    Transit not cleared: Exception Center T04). This proc runs the same three procs in ONE transaction, under the
    transfer's lock, and refuses a stale screen:
      59620 lock not acquired           59621 no delivery for the PO        59622 already DELIVERED
      59623 nothing sent                59624 an unticked row's lines changed since the screen was opened
      59625 post-check: not DELIVERED   59626 a line of the transfer is neither ticked nor unticked (not on the screen)
      59627 a row sent both as received and as returned
    Result set = the lines the receive proc skipped (SeqNo, Barcode, Reason), as before. Error handling per
    docs/standards/2026-10-14_Posting_Proc_Error_Handling.md. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- the receive proc writes its skipped lines here instead of returning a result set (it checks for this table)
    CREATE TABLE #STSRcvSkipped (SeqNo INT, Barcode VARCHAR(120), Reason VARCHAR(200));

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Lock INT, @LockRes NVARCHAR(255) = N'STSTRANSIT:' + @PONumber;
        EXEC @Lock = sp_getapplock @Resource = @LockRes, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 30000;
        IF @Lock < 0
            THROW 59620, 'Another save, return or receive for this transfer is in progress. Please try again.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.DeliverySummary WHERE PONumber = @PONumber)
            THROW 59621, 'This transfer has no delivery to receive.', 1;
        IF EXISTS (SELECT 1 FROM dbo.DeliverySummary WHERE PONumber = @PONumber AND Status = 'DELIVERED')
            THROW 59622, 'This transfer has already been received by the branch.', 1;
        IF NOT EXISTS (SELECT 1 FROM @Lines) AND NOT EXISTS (SELECT 1 FROM @ReturnRows)
            THROW 59623, 'Nothing to receive or return: no rows were sent.', 1;
        IF EXISTS (SELECT 1 FROM @Lines l INNER JOIN @ReturnRows r ON r.DeliveryNo = l.DeliveryNo AND r.SeqNo = l.SeqNo)
            THROW 59627, 'A row was sent both as received and as returned; nothing was changed.', 1;

        ------------------------------------------------------------------
        -- 0. the screen must still match the transfer (read under the lock, before anything is written)
        ------------------------------------------------------------------
        SELECT SeqNo, DeliveryNo, ReferenceNumber, ProductNo, QtyDelivered, GroupSeqNo, GroupLineCount
        INTO #Open
        FROM dbo.funcview_STSReceiveLines(@PONumber);

        DECLARE @Msg NVARCHAR(400);

        -- an unticked row must still be the lines it showed
        SELECT TOP (1) @Msg = N'Item ' + ISNULL(o.ProductNo, N'?') + N' (row ' + CAST(r.SeqNo AS NVARCHAR(10)) + N') changed since this screen was opened '
                            + N'(a line of it was already received or returned). Close the screen and open the transfer again. Nothing was changed.'
        FROM @ReturnRows r
        LEFT JOIN (SELECT DeliveryNo, CASE WHEN @GroupedRows = 1 THEN GroupSeqNo ELSE SeqNo END AS RowSeq, MIN(ProductNo) AS ProductNo, COUNT(*) AS n
                   FROM #Open GROUP BY DeliveryNo, CASE WHEN @GroupedRows = 1 THEN GroupSeqNo ELSE SeqNo END) o
               ON o.DeliveryNo = r.DeliveryNo AND o.RowSeq = r.SeqNo
        WHERE o.n IS NULL OR (r.LineCount IS NOT NULL AND o.n <> r.LineCount)
        ORDER BY r.DeliveryNo, r.SeqNo;
        IF @Msg IS NOT NULL THROW 59624, @Msg, 1;

        -- every open line of the transfer must be on the screen, ticked or unticked
        SELECT TOP (1) @Msg = N'Line ' + CAST(o.SeqNo AS NVARCHAR(10)) + N' (' + o.ProductNo + N') of this transfer is not on the screen: '
                            + N'the transfer changed since it was opened. Close the screen and open the transfer again. Nothing was changed.'
        FROM #Open o
        WHERE NOT EXISTS (SELECT 1 FROM @Lines l WHERE l.DeliveryNo = o.DeliveryNo AND l.SeqNo = CASE WHEN @GroupedRows = 1 THEN o.GroupSeqNo ELSE o.SeqNo END)
          AND NOT EXISTS (SELECT 1 FROM @ReturnRows r WHERE r.DeliveryNo = o.DeliveryNo AND r.SeqNo = CASE WHEN @GroupedRows = 1 THEN o.GroupSeqNo ELSE o.SeqNo END)
        ORDER BY o.DeliveryNo, o.SeqNo;
        IF @Msg IS NOT NULL THROW 59626, @Msg, 1;

        ------------------------------------------------------------------
        -- 1. receive the ticked rows (branch stock, receipt rows, stock ledger)
        ------------------------------------------------------------------
        IF EXISTS (SELECT 1 FROM @Lines)
            EXEC dbo.spu_PostSTSReceiveFromFIFO
                @PONumber = @PONumber, @BranchCode = @BranchCode, @ReceivedBy = @ReceivedBy,
                @Lines = @Lines, @GroupedRows = @GroupedRows;

        ------------------------------------------------------------------
        -- 2. return the unticked rows' lines to the origin (same proc and order as the screen did)
        ------------------------------------------------------------------
        DECLARE @RL TABLE (RowId INT IDENTITY(1,1) PRIMARY KEY, DeliveryNo VARCHAR(20), SeqNo INT, ReferenceNumber VARCHAR(10), ProductNo VARCHAR(20), QtyDelivered DECIMAL(18,3));
        INSERT INTO @RL (DeliveryNo, SeqNo, ReferenceNumber, ProductNo, QtyDelivered)
        SELECT o.DeliveryNo, o.SeqNo, o.ReferenceNumber, o.ProductNo, o.QtyDelivered
        FROM #Open o
        WHERE EXISTS (SELECT 1 FROM @ReturnRows r WHERE r.DeliveryNo = o.DeliveryNo AND r.SeqNo = CASE WHEN @GroupedRows = 1 THEN o.GroupSeqNo ELSE o.SeqNo END)
        ORDER BY o.DeliveryNo, o.SeqNo;

        DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @RL),
                @dn VARCHAR(20), @rn VARCHAR(10), @pn VARCHAR(20), @q DECIMAL(18,3), @sq INT;
        WHILE @i <= @n
        BEGIN
            SELECT @dn = DeliveryNo, @sq = SeqNo, @rn = ReferenceNumber, @pn = ProductNo, @q = QtyDelivered FROM @RL WHERE RowId = @i;
            EXEC dbo.sp_ReverseSTSInventoryTransfer
                @parmdevno = @dn, @parmrefno = @rn, @parmpono = @PONumber, @parmprodno = @pn, @parmqty = @q,
                @parmbranchcode = @BranchCode, @parmorigin = @Origin, @preparedby = @PreparedBy, @parmdevseqno = @sq;
            SET @i += 1;
        END

        ------------------------------------------------------------------
        -- 3. confirm: receipt tickets (IT-BR / STS-SHORT / STS-OVER), DELIVERED
        ------------------------------------------------------------------
        IF @UseJFC = 1
            EXEC dbo.sp_ConfirmBranchRecievedOrderJFC @parmdevno = '', @parmpono = @PONumber, @parmbarcode = '', @parmbranchcode = @BranchCode, @preparedby = @PreparedBy;
        ELSE
            EXEC dbo.sp_ConfirmBranchRecievedOrder    @parmdevno = '', @parmpono = @PONumber, @parmbarcode = '', @parmbranchcode = @BranchCode, @preparedby = @PreparedBy;

        IF NOT EXISTS (SELECT 1 FROM dbo.DeliverySummary WHERE PONumber = @PONumber AND Status = 'DELIVERED')
            THROW 59625, 'Post-check: the transfer is not marked DELIVERED after the receipt; nothing was changed.', 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT SeqNo, Barcode, Reason FROM #STSRcvSkipped;
END
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('[85] an earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
------------------------------------------------------------------
-- post-check: 4 objects carry [85], 4 backups, the new proc + type exist, no 60299 left, the receive proc feeds the caller
------------------------------------------------------------------
IF (SELECT COUNT(*) FROM sys.objects o WHERE o.name IN ('sp_ReversePaymentClient','sp_PostSupplierPaymentWithManualLines','sp_ReverseCombinedSupplierVoucher','spu_PostSTSReceiveFromFIFO','spu_STS_ReceiveTransfer')
      AND OBJECT_DEFINITION(o.object_id) LIKE '%[[]85]%') <> 5
   OR (SELECT COUNT(*) FROM sys.objects WHERE name LIKE '%[_]OLD[_]10152026003000') <> 4
   OR TYPE_ID('dbo.tt_STSReceiveReturnRows') IS NULL
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostSupplierPaymentWithManualLines')) LIKE '%THROW 60299%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient')) NOT LIKE '%@OwnTickets%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.spu_PostSTSReceiveFromFIFO')) NOT LIKE '%#STSRcvSkipped%'
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[85] post-check failed; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
GO

SET NOEXEC OFF;
GO
SELECT DB_NAME() AS DatabaseName, name, CONVERT(VARCHAR(16), modify_date, 120) AS Modified FROM sys.objects
WHERE name IN ('sp_ReversePaymentClient','sp_PostSupplierPaymentWithManualLines','sp_ReverseCombinedSupplierVoucher','spu_PostSTSReceiveFromFIFO','spu_STS_ReceiveTransfer')
   OR name LIKE '%[_]OLD[_]10152026003000' ORDER BY name;
GO
