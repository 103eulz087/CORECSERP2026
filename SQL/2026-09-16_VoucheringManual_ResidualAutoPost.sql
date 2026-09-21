/* ================================================================
   VoucheringManualFrm — restore residual auto-post to Credit GLCode
   for pure-manual (no-invoice) vouchers
   ================================================================
   DEPENDS ON: SQL/2026-09-15_VoucheringManual_AutoAPTradeLegs.sql
   (must already be live — this script only patches sp_PostVoucherManual
   further; it reuses everything else from that version unchanged).

   Bug this fixes: that script made the manual @GLLines grid ALWAYS
   have to self-balance on its own (THROW 58025), on the theory that
   the only thing it was ever reconciling against was the AP-Trade
   line for invoices - which is no longer needed since invoices now
   auto-post their own Amount-To-Apply/Variance legs. But the grid has
   a SECOND, unrelated use: a pure advance to a supplier with NO
   invoice attached (Telegraphic + EXPENSE, zero invoices checked, one
   Debit "Advances to HPY" line, Credit GLCode chosen from the header
   dropdown to supply the other side) - the exact shape
   SupplierPaymentDevEx.cs already supports, and the exact shape the
   ORIGINAL sp_PostVoucherManual (pre-AutoAPTradeLegs) supported via
   its "ResidualCash auto-posts to Credit GLCode" mechanic. Forcing
   self-balance broke that scenario, surfacing as "manual GL entry is
   out of balance" with no way to proceed short of typing a second,
   made-up balancing line - the same friction the AP-Trade tie-check
   removal was supposed to eliminate, just relocated.

   Fix: restore the residual-auto-posts-to-Credit-GLCode mechanic, but
   scoped to ONLY apply when there are no invoices being paid:
     - No invoices: @GLLines does NOT need to self-balance. Whatever it
       nets to (Debit total - Credit total) auto-posts as the
       offsetting leg against @parmcreditglcode (Credit if net debit,
       Debit if net credit) - same shape as the old ResidualCash leg.
     - Invoices being paid: @GLLines still must self-balance on its
       own, unchanged from AutoAPTradeLegs.sql - Amount-To-Apply/
       Variance already auto-post their own AP-Trade legs against
       Credit GLCode, so a second unbalanced residual there would
       double up against the same account.
   Credit GLCode is now required whenever it will actually be used:
   invoices being paid, OR the grid has a nonzero residual - not just
   "when paying invoices" as AutoAPTradeLegs.sql had it.

   Everything else (AP-Trade/Variance auto legs, compound #Legs
   netting, Gross-vs-fresh-Balance assertion, duplicate-post guard,
   combined-per-account Bank Recon calls, final ticket-balance
   assertion) is unchanged from AutoAPTradeLegs.sql.

   Deploy to CORECSERP_002_DEV first; mirror to CORECSJFC2026_STAGING
   only after confirming with the user, per project convention.
   ================================================================ */

IF OBJECT_ID('dbo.sp_PostVoucherManual', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_PostVoucherManual', 'sp_PostVoucherManual_OLD_20260916100000';
GO

CREATE PROCEDURE [dbo].[sp_PostVoucherManual]
(
    @parmrefno         VARCHAR(10),
    @parmvoucherid     VARCHAR(10),
    @parmsupplierid    VARCHAR(50),
    @parmsuppliername  VARCHAR(150),
    @parmpaymethod     VARCHAR(20),    -- 'PURCHASE' or 'EXPENSE'
    @parmvouchertype   VARCHAR(50),    -- 'CHECK', 'CASH', or 'TELEGRAPHIC'
    @parmcheckno       VARCHAR(50) = NULL,
    @parmcreditglcode  VARCHAR(20) = NULL,
    @parmcontrolno     VARCHAR(50) = NULL,
    @parmvoucherdate   DATE,
    @parmremarks       VARCHAR(2000),
    @parmpreparedby    VARCHAR(50),
    @parmbranch        VARCHAR(5),
    @InvoiceLines      dbo.VoucherManualInvoiceTVP_v2 READONLY,
    @GLLines           dbo.VoucherManualGLLineTVP READONLY
)
AS
/*
    Posts a manual voucher. Checked invoices auto-post two leg pairs
    each (Amount-To-Apply against AP-Trade/Credit-GLCode, Variance
    against AP-Trade/60323) - see SQL/2026-09-15_VoucheringManual_
    AutoAPTradeLegs.sql header comment for the exact shape and the
    account-resolution rules. The manual @GLLines grid is independent
    of invoices:
      - No invoices: free-form, does NOT need to self-balance - its
        residual (Debit total - Credit total) auto-posts against
        @parmcreditglcode (e.g. a lone "Advances to Supplier" Debit
        line with no invoice attached).
      - Invoices being paid: must self-balance on its own (Amount-To-
        Apply/Variance already auto-post their own AP-Trade legs
        against Credit GLCode).
    Callers: VoucheringManualFrm.cs BtnPost_Click.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ── Validation ──────────────────────────────────────────────
    -- NEW: the AP-Trade mapping resolution below partitions on exact
    -- string equality ('PURCHASE'/'EXPENSE'), while the per-invoice
    -- loop further down partitions on "= 'PURCHASE', else EXPENSE"
    -- (fail-open). Reject anything else up front so those two can
    -- never diverge - e.g. a future/alternate caller passing a typo'd
    -- or differently-cased value wouldn't silently resolve neither
    -- mapping variable and then have the loop fail-open into EXPENSE
    -- with a NULL @invPayableAcct.
    IF (SELECT COUNT(*) FROM @InvoiceLines) > 0 AND @parmpaymethod NOT IN ('PURCHASE', 'EXPENSE')
    BEGIN
        THROW 58029, 'Invalid @parmpaymethod - must be ''PURCHASE'' or ''EXPENSE'' when paying invoices.', 1;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM @InvoiceLines WHERE ISNULL(AmountPaid,0) <= 0)
    BEGIN
        THROW 58002, 'Every checked invoice must have an Amount Paid greater than zero.', 1;
        RETURN;
    END

    -- Variance only makes sense for Telegraphic (USD-invoiced
    -- suppliers converted at today's rate) - a Check/Cash voucher is
    -- always same-currency, so a nonzero Variance there would post a
    -- spurious FX gain/loss and misstate what the physical instrument
    -- actually settled.
    IF @parmvouchertype IN ('CHECK','CASH') AND EXISTS (SELECT 1 FROM @InvoiceLines WHERE ISNULL(Variance,0) <> 0)
    BEGIN
        THROW 58022, 'A Variance (FX difference) is only supported for Telegraphic Transfer vouchers - Amount Paid must equal Balance exactly for Check/Cash.', 1;
        RETURN;
    END

    -- NEW: nothing to post if both sides are empty. Invoices alone are
    -- fine now (their own auto legs fully balance the ticket); manual
    -- GL lines alone are fine too (pure GL-to-GL transfer, e.g. a cash
    -- advance with no invoice attached).
    IF (SELECT COUNT(*) FROM @InvoiceLines) = 0 AND (SELECT COUNT(*) FROM @GLLines) = 0
    BEGIN
        THROW 58003, 'Nothing to post - check at least one invoice or add at least one manual GL line.', 1;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM @GLLines WHERE (Debit > 0 AND Credit > 0) OR (Debit = 0 AND Credit = 0))
    BEGIN
        THROW 58004, 'Each GL line must have an amount in either Debit or Credit, not both or neither.', 1;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM @GLLines WHERE LTRIM(RTRIM(ISNULL(AccountCode,''))) = '')
    BEGIN
        THROW 58005, 'Every GL line requires an Account Code.', 1;
        RETURN;
    END

    -- CHANGED 2026-09-16: a pure manual voucher (no invoices - e.g. an
    -- advance to a supplier with no invoice attached, same shape
    -- SupplierPaymentDevEx.cs already supports) only needs ONE side
    -- typed - Debit "Advances to Supplier", nothing else - relying on
    -- the header's Credit GLCode to auto-absorb the other side, same
    -- as the original ResidualCash mechanic. Only require the grid to
    -- self-balance when invoices ARE being paid - Amount-To-Apply/
    -- Variance already auto-post their own AP-Trade legs against
    -- Credit GLCode there, so a second unbalanced residual would
    -- double up against the same account.
    DECLARE @GLTotalDebit DECIMAL(18,2), @GLTotalCredit DECIMAL(18,2), @GLResidual DECIMAL(18,2);
    SELECT @GLTotalDebit = ISNULL(SUM(Debit),0), @GLTotalCredit = ISNULL(SUM(Credit),0) FROM @GLLines;
    SET @GLResidual = ROUND(@GLTotalDebit - @GLTotalCredit, 2);

    IF (SELECT COUNT(*) FROM @InvoiceLines) > 0 AND (SELECT COUNT(*) FROM @GLLines) > 0 AND @GLResidual <> 0
    BEGIN
        DECLARE @GLBalMsg VARCHAR(500) = 'The manual GL entry is out of balance: Debit ' + CAST(@GLTotalDebit AS VARCHAR(30))
            + ' vs Credit ' + CAST(@GLTotalCredit AS VARCHAR(30))
            + '. When paying invoices it must balance on its own - Amount to Apply/Variance already auto-post their own AP-Trade legs.';
        THROW 58025, @GLBalMsg, 1;
        RETURN;
    END

    IF @parmvouchertype = 'CHECK' AND LTRIM(RTRIM(ISNULL(@parmcheckno,''))) = ''
    BEGIN
        THROW 58009, 'Check No. is required for a Check voucher.', 1;
        RETURN;
    END

    IF @parmvouchertype IN ('CASH','TELEGRAPHIC') AND LTRIM(RTRIM(ISNULL(@parmcontrolno,''))) = ''
    BEGIN
        THROW 58010, 'Control No. is required for Cash/Telegraphic vouchers.', 1;
        RETURN;
    END

    -- CHANGED 2026-09-16: also required whenever the manual grid
    -- doesn't self-balance (@GLResidual <> 0) - that residual now
    -- auto-posts against Credit GLCode, same as invoices' Amount-To-
    -- Apply leg.
    IF ((SELECT COUNT(*) FROM @InvoiceLines) > 0 OR @GLResidual <> 0) AND LTRIM(RTRIM(ISNULL(@parmcreditglcode,''))) = ''
    BEGIN
        THROW 58014, 'Credit GLCode is required when paying invoices or when the manual GL entry does not balance on its own.', 1;
        RETURN;
    END

    DECLARE @supplierkey VARCHAR(30);
    SELECT @supplierkey = SupplierKey FROM Supplier WHERE SupplierID = @parmsupplierid;

    IF @supplierkey IS NULL
    BEGIN
        THROW 58011, 'Supplier not found.', 1;
        RETURN;
    END

    -- Duplicate-post guard - a retry or a double-click must not
    -- silently double-pay the supplier.
    IF EXISTS (SELECT 1 FROM TicketMaster WHERE ReferenceNumber = @parmrefno AND Mnemonic = 'VOUCHER-MANUAL')
    BEGIN
        THROW 58020, 'A voucher has already been posted under this reference number.', 1;
        RETURN;
    END

    -- NEW: resolve the FX variance account(s) up front, before any
    -- write, so a missing mapping fails fast instead of mid-post. Now
    -- resolved by whether ANY checked invoice has a loss/gain - a
    -- single voucher can contain both (invoice A overpaid, invoice B
    -- underpaid), unlike the prior net-only design.
    DECLARE @FXLossAccountCode VARCHAR(20), @FXGainAccountCode VARCHAR(20);

    IF EXISTS (SELECT 1 FROM @InvoiceLines WHERE ISNULL(Variance,0) > 0)
    BEGIN
        SELECT @FXLossAccountCode = AccountCode FROM dbo.JournalEntryMapping
        WHERE Mnemonic = 'VOUCHER-MANUAL-FXVAR' AND ConditionFlag = 'HasFXLoss' AND IsActive = 1;

        IF @FXLossAccountCode IS NULL
        BEGIN
            THROW 58017, 'No active JournalEntryMapping found for VOUCHER-MANUAL-FXVAR / HasFXLoss (Realized Loss on Forex). Verify seed data.', 1;
            RETURN;
        END
    END

    IF EXISTS (SELECT 1 FROM @InvoiceLines WHERE ISNULL(Variance,0) < 0)
    BEGIN
        SELECT @FXGainAccountCode = AccountCode FROM dbo.JournalEntryMapping
        WHERE Mnemonic = 'VOUCHER-MANUAL-FXVAR' AND ConditionFlag = 'HasFXGain' AND IsActive = 1;

        IF @FXGainAccountCode IS NULL
        BEGIN
            THROW 58018, 'No active JournalEntryMapping found for VOUCHER-MANUAL-FXVAR / HasFXGain (Realized Gain on Forex). Verify seed data.', 1;
            RETURN;
        END
    END

    -- NEW: resolve the default AP-Trade account per payment method from
    -- JournalEntryMapping instead of hardcoding it in the proc body -
    -- config-driven the same way the FX accounts already are. For
    -- EXPENSE, ExpenseSummary.PayableAccountCode (a real per-invoice
    -- field the rest of the system already populates) still wins when
    -- set; this mapping is only the fallback for a NULL/blank value.
    DECLARE @APTradeAccountPurchase VARCHAR(20), @APTradeAccountExpenseFallback VARCHAR(20);

    IF (SELECT COUNT(*) FROM @InvoiceLines) > 0 AND @parmpaymethod = 'PURCHASE'
    BEGIN
        SELECT @APTradeAccountPurchase = AccountCode FROM dbo.JournalEntryMapping
        WHERE Mnemonic = 'VOUCHER-MANUAL-APTRADE' AND ConditionFlag = 'PURCHASE' AND IsActive = 1;

        IF @APTradeAccountPurchase IS NULL
        BEGIN
            THROW 58027, 'No active JournalEntryMapping found for VOUCHER-MANUAL-APTRADE / PURCHASE. Verify seed data.', 1;
            RETURN;
        END
    END
    ELSE IF (SELECT COUNT(*) FROM @InvoiceLines) > 0 AND @parmpaymethod = 'EXPENSE'
    BEGIN
        SELECT @APTradeAccountExpenseFallback = AccountCode FROM dbo.JournalEntryMapping
        WHERE Mnemonic = 'VOUCHER-MANUAL-APTRADE' AND ConditionFlag = 'EXPENSE' AND IsActive = 1;

        IF @APTradeAccountExpenseFallback IS NULL
        BEGIN
            THROW 58028, 'No active JournalEntryMapping found for VOUCHER-MANUAL-APTRADE / EXPENSE. Verify seed data.', 1;
            RETURN;
        END
    END

    -- NEW: total voucher Amount = the invoice-driven cash, plus
    -- whatever the manual grid separately nets on the SAME
    -- @parmcreditglcode account (e.g. an advance also drawn from the
    -- same bank account) - reproduces the combined physical-instrument
    -- total (e.g. 900 invoice + 2000 advance = 2900), while the manual
    -- grid's OWN balance (Debit=Credit) is validated independently
    -- above and never folded into this figure beyond that net.
    DECLARE @TotalInvoiceCash DECIMAL(18,2) = ISNULL((SELECT SUM(AmountPaid) FROM @InvoiceLines), 0);
    DECLARE @ManualCreditGLCodeNet DECIMAL(18,2) = ISNULL((
        SELECT SUM(Credit) - SUM(Debit) FROM @GLLines
        WHERE LTRIM(RTRIM(ISNULL(AccountCode,''))) = LTRIM(RTRIM(ISNULL(@parmcreditglcode,'')))
    ), 0);

    -- FIX (2026-09-16): a pure manual-GL voucher (no invoices) auto-
    -- posts its residual (@GLResidual, Debit-heavy OR Credit-heavy -
    -- the C# grid supports and previews both directions) against
    -- @parmcreditglcode. The header Amount must be the TRUE net
    -- movement through @parmcreditglcode - that's
    -- @ManualCreditGLCodeNet (whatever the user typed directly against
    -- that account in the grid) PLUS @GLResidual (what the auto-leg
    -- adds to it), not @GLTotalDebit and not @GLResidual alone.
    -- @GLResidual alone breaks when the user types a fully
    -- self-balanced pair directly ON @parmcreditglcode itself (e.g.
    -- Debit Advances 5000 / Credit Cash-in-Bank 5000, no invoices) -
    -- @GLResidual=0 there (grid already balances, no auto-leg needed),
    -- but the real voucher amount is still 5000, not 0. @GLTotalDebit
    -- breaks whenever the grid has more than one line pair (e.g. Debit
    -- 2000 + a self-balanced Credit 500 elsewhere, residual 1500 -
    -- @GLTotalDebit wrongly records 2000) and wrongly throws 58026
    -- "zero Amount" for a genuine Credit-heavy-only grid (@GLTotalDebit
    -- = 0 despite a real nonzero residual).
    DECLARE @TotalVoucherAmount DECIMAL(18,2) =
        CASE WHEN (SELECT COUNT(*) FROM @InvoiceLines) > 0
             THEN @TotalInvoiceCash + @ManualCreditGLCodeNet
             ELSE ABS(@ManualCreditGLCodeNet + @GLResidual)
        END;

    IF @TotalVoucherAmount <= 0
    BEGIN
        THROW 58026, 'This voucher would post a zero or negative Amount - check your entries (a manual debit against the Credit GLCode account may be offsetting the invoice cash).', 1;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRAN;

        -- ── Voucher header ──
        IF @parmvouchertype = 'TELEGRAPHIC'
            INSERT INTO [dbo].[TelegraphicVoucher]
                (VoucherID, SupplierID, ReferenceNumber, PaidTo, Particulars, Amount,
                 PreparedBy, VerifiedBy, NotedBy, PaymentApprovedBy, PaymentReceivedBy,
                 OfficialReceiptNo, VoucherType, DateReceived, DateAdded, DateUpdate,
                 isErrorCorrect, isLiquidation)
            VALUES
                (@parmvoucherid, @parmsupplierid, @parmrefno, @parmsuppliername,
                 @parmremarks, @TotalVoucherAmount, @parmpreparedby, '', @parmcontrolno, '', '',
                 @parmcreditglcode, 'TELEGRAPHIC', @parmvoucherdate, GETDATE(), GETDATE(), 0, 0);
        ELSE
            INSERT INTO [dbo].[CashVoucher]
                (VoucherID, SupplierID, ReferenceNumber, PaidTo, Particulars, Amount,
                 PreparedBy, VerifiedBy, NotedBy, PaymentApprovedBy, PaymentReceivedBy,
                 OfficialReceiptNo, VoucherType, DateReceived, DateAdded, DateUpdate,
                 isErrorCorrect, isLiquidation)
            VALUES
                (@parmvoucherid, @parmsupplierid, @parmrefno, @parmsuppliername,
                 @parmremarks, @TotalVoucherAmount, @parmpreparedby, '', @parmcontrolno, '', '',
                 @parmcreditglcode, 'CASH', @parmvoucherdate, GETDATE(), GETDATE(), 0, 0);

        -- FIX: TransactionPaymentAP specifically tracks AP-invoice cash,
        -- not the voucher's combined total - an unrelated manual GL
        -- entry (e.g. a cash advance sharing the same Credit GLCode)
        -- must not inflate what looks like AP payment activity for
        -- this supplier in any report keyed off this table.
        DECLARE @SeqNo INT;
        SELECT @SeqNo = ISNULL(MAX(SEQ_NO),0) + 1 FROM TransactionPaymentAP WHERE SupplierKey = @supplierkey;
        INSERT INTO [dbo].[TransactionPaymentAP]
            (SEQ_NO, SupplierKey, ReferenceNumber, Amount, VoucherType,
             DatePaid, ExecuteBy, DateUpdate, UpdateBy, ErrorCorrect)
        VALUES (@SeqNo, @supplierkey, @parmrefno, @TotalInvoiceCash, @parmvouchertype,
                GETDATE(), @parmpreparedby, GETDATE(), @parmpreparedby, 0);

        -- ── One ticket, the whole compound entry ──
        DECLARE @ticketnum VARCHAR(20);
        EXEC GetTicketNumber @ticketnum OUTPUT;

        DECLARE @PhysicalRef VARCHAR(50) = CASE WHEN @parmvouchertype = 'CHECK' THEN @parmcheckno ELSE @parmcontrolno END;

        INSERT INTO [dbo].[TicketMaster]
            (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber,
             ReferenceNumber, ReferenceKey, Owner, Particulars,
             EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
        VALUES
            (@parmvoucherdate, 0, @parmbranch, 'PV', @ticketnum,
             @parmrefno, @parmvoucherid, @parmsuppliername, ISNULL(@parmremarks,''),
             @parmpreparedby, '*', '*', 'POSTED', 'VOUCHER-MANUAL', NULL);

        -- NEW: compound-entry staging. Every leg (the user's own
        -- free-form GL lines AND every auto-generated Amount-To-Apply/
        -- Variance leg below, plus the pure-manual-voucher residual
        -- leg below) is staged here first, then netted per AccountCode
        -- into exactly one TicketDetails row per account at the end -
        -- so a voucher paying an invoice with a Variance plus an
        -- unrelated manual advance posts a clean compound entry (e.g.
        -- one AP-Trade line, one Cash-in-Bank line) instead of a
        -- separate row per source. Per-invoice detail is NOT lost - it
        -- still lives in full in APPaymentDetails.Variance and
        -- SupplierLedger; only the GL/TicketDetails view is compounded.
        IF OBJECT_ID('tempdb..#Legs') IS NOT NULL DROP TABLE #Legs;
        CREATE TABLE #Legs (AccountCode VARCHAR(20), Debit DECIMAL(18,2), Credit DECIMAL(18,2));

        -- The user's own free-form GL lines (e.g. a cash advance) -
        -- already validated to self-balance when invoices are being
        -- paid; may be one-sided otherwise (residual handled below).
        -- ISNULL-guarded so a NULL Debit/Credit can't make SUM(...)
        -- resolve to NULL for that account's group below, which would
        -- silently exclude the row (NULL <> 0 is UNKNOWN) instead of
        -- loudly failing the way a NULL landing straight in
        -- TicketDetails used to.
        INSERT INTO #Legs (AccountCode, Debit, Credit)
        SELECT AccountCode, ISNULL(Debit,0), ISNULL(Credit,0)
        FROM @GLLines;

        -- NEW 2026-09-16: pure-manual-voucher residual auto-post
        -- (restores the original ResidualCash mechanic) - only applies
        -- when there are no invoices, since invoices already auto-post
        -- their own Amount-To-Apply leg against @parmcreditglcode and
        -- a second residual there would double up. Debit-heavy grid
        -- (e.g. a lone "Advances to Supplier" Debit line) auto-posts a
        -- Credit here; Credit-heavy grid auto-posts a Debit.
        IF (SELECT COUNT(*) FROM @InvoiceLines) = 0 AND @GLResidual <> 0
        BEGIN
            IF @GLResidual > 0
                INSERT INTO #Legs (AccountCode, Debit, Credit) VALUES (@parmcreditglcode, 0, @GLResidual);
            ELSE
                INSERT INTO #Legs (AccountCode, Debit, Credit) VALUES (@parmcreditglcode, -@GLResidual, 0);
        END

        -- ── Per-invoice settlement + auto AP-Trade/Variance legs ──
        DECLARE @row INT = 1, @maxrow INT, @invBranch VARCHAR(5), @invInvoiceNo VARCHAR(150),
                @invSeqRef VARCHAR(50), @invBatchRef BIGINT, @invAmtPaid DECIMAL(18,2),
                @invVariance DECIMAL(18,2), @invGross DECIMAL(18,2), @invPayableAcct VARCHAR(20),
                @invCurBalance DECIMAL(18,2), @invNewBalance DECIMAL(18,2), @transid INT;
        SELECT @maxrow = COUNT(*) FROM @InvoiceLines;

        IF OBJECT_ID('tempdb..#InvLines') IS NOT NULL DROP TABLE #InvLines;
        SELECT ROW_NUMBER() OVER (ORDER BY InvoiceNo) AS RowNum, * INTO #InvLines FROM @InvoiceLines;

        WHILE @row <= @maxrow
        BEGIN
            SELECT
                @invBranch = BranchCode, @invInvoiceNo = InvoiceNo,
                @invSeqRef = SequenceReferenceNumber, @invBatchRef = BatchReferenceID,
                @invAmtPaid = ISNULL(AmountPaid,0), @invVariance = ISNULL(Variance,0)
            FROM #InvLines WHERE RowNum = @row;

            SET @invGross = @invAmtPaid - @invVariance;

            IF @parmpaymethod = 'PURCHASE'
            BEGIN
                -- PURCHASE invoices carry no per-row payable-account
                -- column (APAccounts) - use the config-driven default
                -- resolved above (JournalEntryMapping VOUCHER-MANUAL-
                -- APTRADE / PURCHASE, normally 20101 ACCOUNTS PAYABLE - TRADE).
                SET @invPayableAcct = @APTradeAccountPurchase;

                -- UPDLOCK/ROWLOCK: hold the row for the rest of this
                -- transaction so a concurrent voucher against the same
                -- invoice can't read the same starting Balance (lost
                -- update) between this SELECT and the UPDATE below.
                SET @invCurBalance = NULL;
                SELECT @invCurBalance = Balance FROM APAccounts WITH (UPDLOCK, ROWLOCK)
                WHERE SupplierID = @parmsupplierid AND InvoiceNo = @invInvoiceNo AND SequenceNo = @invSeqRef;

                IF @invCurBalance IS NULL
                BEGIN
                    THROW 58023, 'Invoice ' + @invInvoiceNo + ' was not found in APAccounts (SequenceNo ' + ISNULL(@invSeqRef,'') + ').', 1;
                END

                -- Gross must equal the invoice's CURRENT Balance - if
                -- it doesn't, the grid was loaded against a Balance
                -- that has since changed (e.g. another payment posted
                -- against it in the meantime). Fail rather than
                -- silently leave a phantom residual or write off an
                -- uncompensated surplus.
                IF ROUND(@invCurBalance - @invGross, 2) <> 0
                BEGIN
                    DECLARE @StaleMsgP VARCHAR(500) = 'Invoice ' + @invInvoiceNo + ': its Balance (' + CAST(@invCurBalance AS VARCHAR(30))
                        + ') no longer matches what this voucher expects to pay off (' + CAST(@invGross AS VARCHAR(30))
                        + '). It may have been paid or adjusted since this voucher was loaded - refresh Load Invoices and try again.';
                    THROW 58024, @StaleMsgP, 1;
                END

                -- Overpayment guard - Check/Cash still can't carry an
                -- FX variance (enforced up front, 58022), so this only
                -- fires for a genuine input error.
                IF @invAmtPaid > @invCurBalance AND @parmvouchertype IN ('CHECK','CASH')
                BEGIN
                    DECLARE @OverpayMsgP VARCHAR(500) = 'Invoice ' + @invInvoiceNo + ': Amount Paid ('
                        + CAST(@invAmtPaid AS VARCHAR(30)) + ') exceeds its Balance ('
                        + CAST(@invCurBalance AS VARCHAR(30)) + '). Not allowed for Check/Cash vouchers.';
                    THROW 58015, @OverpayMsgP, 1;
                END

                SET @invNewBalance = ROUND(CASE WHEN @invCurBalance - @invGross < 0 THEN 0 ELSE @invCurBalance - @invGross END, 2);

                UPDATE APAccounts
                SET Balance = @invNewBalance,
                    AmountPaid = ISNULL(AmountPaid,0) + @invAmtPaid,
                    PayStatus = CASE WHEN @invNewBalance <= 0 THEN 'FULLYPAID' ELSE 'PARTIAL' END
                WHERE SupplierID = @parmsupplierid AND InvoiceNo = @invInvoiceNo AND SequenceNo = @invSeqRef;

                INSERT INTO APPaymentDetails
                    (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                     InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                     VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                     SequenceReferenceNumber, BatchReferenceID, Variance)
                VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @invBranch,
                        @invInvoiceNo, @parmvoucherdate, @invAmtPaid, 'INVOICE PAYMENT',
                        @parmpaymethod, @parmvouchertype, @ticketnum, @invPayableAcct, @parmcreditglcode,
                        @invSeqRef, NULL, @invVariance);
            END
            ELSE  -- EXPENSE
            BEGIN
                SET @invCurBalance = NULL;
                SET @invPayableAcct = NULL;
                SELECT @invCurBalance = ISNULL(Balance, ISNULL(Amount,0)), @invPayableAcct = PayableAccountCode
                FROM ExpenseSummary WITH (UPDLOCK, ROWLOCK)
                WHERE SupplierID = @supplierkey AND InvoiceNo = @invInvoiceNo AND BatchReferenceID = @invBatchRef;

                IF @invCurBalance IS NULL
                BEGIN
                    THROW 58023, 'Invoice ' + @invInvoiceNo + ' was not found in ExpenseSummary (BatchReferenceID ' + CAST(ISNULL(@invBatchRef,0) AS VARCHAR(30)) + ').', 1;
                END

                -- ExpenseSummary.PayableAccountCode wins when set (real
                -- per-invoice data); otherwise fall back to the config-
                -- driven default resolved above (JournalEntryMapping
                -- VOUCHER-MANUAL-APTRADE / EXPENSE, normally 20103).
                SET @invPayableAcct = ISNULL(NULLIF(LTRIM(RTRIM(@invPayableAcct)),''), @APTradeAccountExpenseFallback);

                -- Same Gross-vs-current-Balance guard as PURCHASE - see 58024 above.
                IF ROUND(@invCurBalance - @invGross, 2) <> 0
                BEGIN
                    DECLARE @StaleMsgE VARCHAR(500) = 'Invoice ' + @invInvoiceNo + ': its Balance (' + CAST(@invCurBalance AS VARCHAR(30))
                        + ') no longer matches what this voucher expects to pay off (' + CAST(@invGross AS VARCHAR(30))
                        + '). It may have been paid or adjusted since this voucher was loaded - refresh Load Invoices and try again.';
                    THROW 58024, @StaleMsgE, 1;
                END

                IF @invAmtPaid > @invCurBalance AND @parmvouchertype IN ('CHECK','CASH')
                BEGIN
                    DECLARE @OverpayMsgE VARCHAR(500) = 'Invoice ' + @invInvoiceNo + ': Amount Paid ('
                        + CAST(@invAmtPaid AS VARCHAR(30)) + ') exceeds its Balance ('
                        + CAST(@invCurBalance AS VARCHAR(30)) + '). Not allowed for Check/Cash vouchers.';
                    THROW 58016, @OverpayMsgE, 1;
                END

                SET @invNewBalance = ROUND(CASE WHEN @invCurBalance - @invGross < 0 THEN 0 ELSE @invCurBalance - @invGross END, 2);

                UPDATE ExpenseSummary
                SET Balance = @invNewBalance,
                    AmountPaid = ISNULL(AmountPaid,0) + @invAmtPaid,
                    Status = CASE WHEN @invNewBalance <= 0 THEN 'FULLYPAID' ELSE 'PARTIAL' END,
                    UpdatedBy = @parmpreparedby, DateTimeUpdated = GETDATE()
                WHERE SupplierID = @supplierkey AND InvoiceNo = @invInvoiceNo AND BatchReferenceID = @invBatchRef;

                IF @invNewBalance <= 0
                    UPDATE ExpenseMaster SET Balance = 0, AmountPaid = Amount, Status = 'FULLYPAID'
                    WHERE SupplierID = @supplierkey AND InvoiceNo = @invInvoiceNo AND BatchReferenceID = @invBatchRef;
                ELSE
                    UPDATE ExpenseMaster SET Status = 'PARTIAL'
                    WHERE SupplierID = @supplierkey AND InvoiceNo = @invInvoiceNo AND BatchReferenceID = @invBatchRef
                      AND Status NOT IN ('FULLYPAID','VOID','CANCELLED');

                INSERT INTO APPaymentDetails
                    (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                     InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                     VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                     SequenceReferenceNumber, BatchReferenceID, Variance)
                VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @invBranch,
                        @invInvoiceNo, @parmvoucherdate, @invAmtPaid, 'EXPENSE PAYMENT',
                        @parmpaymethod, @parmvouchertype, @ticketnum, @invPayableAcct, @parmcreditglcode,
                        CAST(@invBatchRef AS VARCHAR(50)), @invBatchRef, @invVariance);
            END

            -- NEW: Amount-To-Apply auto leg pair, staged into #Legs
            -- (not TicketDetails directly - netted per account at the
            -- end into a compound entry) - Debit AP-Trade, Credit the
            -- header's Credit GLCode (e.g. Cash in Bank).
            IF @invAmtPaid > 0
            BEGIN
                INSERT INTO #Legs (AccountCode, Debit, Credit) VALUES (@invPayableAcct, @invAmtPaid, 0);
                INSERT INTO #Legs (AccountCode, Debit, Credit) VALUES (@parmcreditglcode, 0, @invAmtPaid);
            END

            -- NEW: Variance auto leg pair, staged the same way. Loss
            -- (paid MORE than Balance): Debit 60323, Credit AP-Trade
            -- back down. Gain (paid LESS than Balance): Debit AP-Trade
            -- up to Balance, Credit 60323.
            IF @invVariance > 0
            BEGIN
                INSERT INTO #Legs (AccountCode, Debit, Credit) VALUES (@FXLossAccountCode, @invVariance, 0);
                INSERT INTO #Legs (AccountCode, Debit, Credit) VALUES (@invPayableAcct, 0, @invVariance);
            END
            ELSE IF @invVariance < 0
            BEGIN
                INSERT INTO #Legs (AccountCode, Debit, Credit) VALUES (@invPayableAcct, -@invVariance, 0);
                INSERT INTO #Legs (AccountCode, Debit, Credit) VALUES (@FXGainAccountCode, 0, -@invVariance);
            END

            SET @transid = dbo.func_getLastID(@supplierkey);
            INSERT INTO [dbo].[SupplierLedger]
                (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate,
                 Description, TransCode, TransactionDate, ReferenceNumber,
                 ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance,
                 TransactedBy, ApprovedBy, TotalAmount, PaymentType,
                 ErrorCorrectTag, TicketReference, BatchReferenceID)
            VALUES (@transid, @supplierkey, @supplierkey, @parmvoucherdate,
                    LEFT(ISNULL(@parmremarks,''), 490), 'PV-MANUAL', @parmvoucherdate,
                    @parmrefno, @PhysicalRef, @invInvoiceNo, 0, @invGross, 0, @invGross,
                    @parmpreparedby, '*', @invGross,
                    CASE WHEN @invNewBalance<=0 THEN 'FULLYPAID' ELSE 'PARTIAL' END,
                    0, @ticketnum, @invBatchRef);

            SET @row += 1;
        END;

        DROP TABLE #InvLines;

        -- ── Compound the staged legs into TicketDetails ──
        -- NEW: net every staged leg (manual GL lines + pure-manual-
        -- voucher residual + all per-invoice Amount-To-Apply/Variance
        -- legs) per AccountCode into exactly one Debit-or-Credit row -
        -- a true compound entry instead of a separate row per source.
        -- A same-account wash (nets to exactly 0, e.g. offsetting
        -- entries on the same account) posts no row at all rather than
        -- a spurious $0.00 line.
        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        SELECT
            @parmvoucherdate, 0, @parmbranch, @parmvoucherid, @ticketnum, @parmrefno,
            AccountCode,
            CASE WHEN NetAmount > 0 THEN NetAmount ELSE 0 END,
            CASE WHEN NetAmount < 0 THEN -NetAmount ELSE 0 END,
            ''
        FROM (
            SELECT AccountCode, ROUND(SUM(Debit) - SUM(Credit), 2) AS NetAmount
            FROM #Legs
            GROUP BY AccountCode
        ) net
        WHERE NetAmount <> 0;

        DROP TABLE #Legs;

        -- ── Bank Recon ──
        -- FIX: sp_Payment_PostBankReconEntry is idempotent per
        -- (ReferenceNo, AccountCode, ItemType) - it silently no-ops
        -- (RETURN, no error) if that exact combination was already
        -- posted. The invoice-driven cash and the manual grid's own
        -- bank lines can land on the SAME account (e.g. the user's own
        -- worked example: invoice cash + an advance, both against
        -- "Cash in Bank"), which previously meant TWO separate calls
        -- with the same @ReferenceNo/@AccountCode/@ItemType='OC' -
        -- the second one would be silently dropped, permanently
        -- understating that account's reconciliation with no error.
        -- Combine everything per account BEFORE calling the proc, so
        -- each (account, type) combination is called exactly once with
        -- the correct combined amount. (This also incidentally fixes
        -- the same latent collision risk that already existed if a
        -- user typed two separate manual lines against the same bank
        -- account.)
        DECLARE @PeriodEnd DATE = EOMONTH(@parmvoucherdate);
        DECLARE @Remarks VARCHAR(500);

        IF OBJECT_ID('tempdb..#BankLines') IS NOT NULL DROP TABLE #BankLines;
        SELECT
            ROW_NUMBER() OVER (ORDER BY AccountCode) AS RowNum,
            AccountCode, TotalDebit, TotalCredit
        INTO #BankLines
        FROM (
            SELECT AccountCode, SUM(Debit) AS TotalDebit, SUM(Credit) AS TotalCredit
            FROM (
                SELECT @parmcreditglcode AS AccountCode, CAST(0 AS DECIMAL(18,2)) AS Debit, @TotalInvoiceCash AS Credit
                FROM (SELECT 1 AS dummy) d
                WHERE @TotalInvoiceCash > 0
                  AND @parmcreditglcode IS NOT NULL
                  AND EXISTS (SELECT 1 FROM ChartOfAccounts WHERE AccountCode = @parmcreditglcode AND AccountCode LIKE '10102%')

                UNION ALL

                SELECT gl.AccountCode, gl.Debit, gl.Credit
                FROM @GLLines gl
                JOIN ChartOfAccounts coa ON coa.AccountCode = gl.AccountCode
                WHERE coa.AccountCode LIKE '10102%'

                UNION ALL

                -- NEW 2026-09-16: pure-manual-voucher residual leg
                -- (see #Legs staging above) - only when there are no
                -- invoices, mirroring that same guard.
                SELECT @parmcreditglcode AS AccountCode,
                       CASE WHEN @GLResidual < 0 THEN -@GLResidual ELSE 0 END AS Debit,
                       CASE WHEN @GLResidual > 0 THEN @GLResidual ELSE 0 END AS Credit
                FROM (SELECT 1 AS dummy) d
                WHERE (SELECT COUNT(*) FROM @InvoiceLines) = 0
                  AND @GLResidual <> 0
                  AND @parmcreditglcode IS NOT NULL
                  AND EXISTS (SELECT 1 FROM ChartOfAccounts WHERE AccountCode = @parmcreditglcode AND AccountCode LIKE '10102%')
            ) src
            GROUP BY AccountCode
        ) grouped;

        DECLARE @bi INT = 1, @bmax INT, @bAcct VARCHAR(20), @bDebit DECIMAL(18,2), @bCredit DECIMAL(18,2);
        SELECT @bmax = COUNT(*) FROM #BankLines;

        WHILE @bi <= @bmax
        BEGIN
            SELECT @bAcct = AccountCode, @bDebit = TotalDebit, @bCredit = TotalCredit FROM #BankLines WHERE RowNum = @bi;

            IF @bCredit > 0
            BEGIN
                 SET @Remarks = 'Auto-OC | VOUCHER-MANUAL | Ref: ' + ISNULL(@parmrefno, '');
                EXEC dbo.sp_Payment_PostBankReconEntry
                    @ItemType='OC', @BranchCode=@parmbranch, @AccountCode=@bAcct,
                    @PeriodEnd=@PeriodEnd, @ReferenceNo=@parmvoucherid, @ItemDate=@parmvoucherdate,
                    @Payee=@parmsuppliername, @Amount=@bCredit,
                    @Remarks=@Remarks,
                    @SourceModule='AP-PAYMENT', @SourceRef=@parmrefno, @CreatedBy=@parmpreparedby;
            END

            IF @bDebit > 0
            BEGIN
                 SET @Remarks = 'Auto-DIT | VOUCHER-MANUAL | Ref: ' + ISNULL(@parmrefno, '');
                EXEC dbo.sp_Payment_PostBankReconEntry
                    @ItemType='DIT', @BranchCode=@parmbranch, @AccountCode=@bAcct,
                    @PeriodEnd=@PeriodEnd, @ReferenceNo=@parmvoucherid, @ItemDate=@parmvoucherdate,
                    @Payee=@parmsuppliername, @Amount=@bDebit,
                    @Remarks=@Remarks,
                    @SourceModule='AP-PAYMENT', @SourceRef=@parmrefno, @CreatedBy=@parmpreparedby;
            END

            SET @bi += 1;
        END;
        DROP TABLE #BankLines;

        -- Prove the whole compound entry balances before commit -
        -- more valuable than ever now, given how many more auto legs
        -- are being assembled per invoice.
        DECLARE @CheckDebit DECIMAL(18,2), @CheckCredit DECIMAL(18,2);
        SELECT @CheckDebit = ISNULL(SUM(Debit),0), @CheckCredit = ISNULL(SUM(Credit),0)
        FROM TicketDetails WHERE TicketNumber = @ticketnum;

        IF ABS(@CheckDebit - @CheckCredit) > 0.01
        BEGIN
            DECLARE @BalMsg VARCHAR(300) = 'Journal entry is out of balance: Debit ' + CAST(@CheckDebit AS VARCHAR(30))
                + ' vs Credit ' + CAST(@CheckCredit AS VARCHAR(30)) + '.';
            THROW 58019, @BalMsg, 1;
        END

        COMMIT TRAN;

        SELECT 1 AS Status, @parmrefno AS ReferenceNo, @TotalVoucherAmount AS TotalAmount,
               'Voucher posted successfully.' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO
