/* ================================================================
   VoucheringManualFrm — Variance column + auto FX mapping (60323)
   ================================================================
   Context: VoucheringManualFrm.cs lets the user manually build the
   compound GL entry for a supplier payment (mostly Telegraphic, for
   USD-invoiced suppliers). The invoice's Balance is booked at the
   FX rate on the original invoice date; the actual cash disbursed is
   converted at today's rate, so there is almost always a difference.

   This script:
     1. Adds Variance to APPaymentDetails (persists the per-invoice
        FX variance for drill-down/reporting).
     2. Seeds two JournalEntryMapping rows (HasFXLoss / HasFXGain,
        both -> AccountCode 60323 REALIZED GAIN/LOSS ON FOREX) so the
        posting procedure resolves the account from config instead of
        hardcoding '60323'.
     3. Adds a NEW type dbo.VoucherManualInvoiceTVP_v2 (BranchCode,
        InvoiceNo, SequenceReferenceNumber, BatchReferenceID,
        AmountPaid, Variance) alongside the existing
        dbo.VoucherManualInvoiceTVP, rather than dropping/altering the
        original in place — SQL Server does not support ALTER TYPE to
        add a column, and DROP TYPE while sp_PostVoucherManual still
        references it is a real risk that couldn't be safely verified
        against the live DB from here. The old type is left untouched
        for history; only the new type is used going forward.
     4. Rebuilds sp_PostVoucherManual (rename-old-to-backup, then
        CREATE) to:
          - Always fully settle a checked invoice: Gross = AmountPaid
            (cash) - Variance always equals the invoice's Balance by
            construction, so APAccounts/ExpenseSummary Balance is
            reduced by Gross (clamped at 0), not by the raw cash
            amount. This is the fix for the bug where an edited
            AmountToApply (once editable) would leave a phantom
            residual Balance on the invoice.
          - AP-Trade tie-check now compares the GL entry's AP-Trade
            Debit total against SUM(Gross) (the liability actually
            extinguished), not SUM(AmountPaid) (the FX-adjusted cash).
          - Auto-inserts one extra TicketDetails leg for the net FX
            variance against the mapped 60323 account (Debit if net
            loss, Credit if net gain) - same mechanic as the existing
            auto Credit-GLCode residual-cash leg.
          - ResidualCash (the auto Credit-GLCode cash leg) is widened
            by the total variance, since the actual cash leaving the
            bank differs from the manually-entered GL debit total by
            exactly that amount.
          - Persists Variance onto APPaymentDetails per invoice line.
          - Adds a balance assertion (SUM(Debit)=SUM(Credit) for the
            posted ticket) before COMMIT.
     5. Rebuilds sp_GetVoucherManualDetails to surface Variance in the
        Posted-tab invoice drill-down.

   Deploy to CORECSERP_002_DEV first; mirror to CORECSJFC2026_STAGING
   only after confirming with the user, per project convention.
   ================================================================ */

-- ----------------------------------------------------------------
-- 1. APPaymentDetails.Variance
-- ----------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.APPaymentDetails')
      AND name = 'Variance'
)
    ALTER TABLE dbo.APPaymentDetails ADD Variance DECIMAL(18,2) NOT NULL CONSTRAINT DF_APPaymentDetails_Variance DEFAULT (0);
GO

-- ----------------------------------------------------------------
-- 2. JournalEntryMapping seed — VOUCHER-MANUAL-FXVAR -> 60323
-- ----------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.JournalEntryMapping WHERE Mnemonic = 'VOUCHER-MANUAL-FXVAR' AND ConditionFlag = 'HasFXLoss')
    INSERT INTO dbo.JournalEntryMapping
        (Origin, Mnemonic, Description, Seq, DebitCredit, AccountCode, AccountDescription,
         IsConditional, IsAmountFromSource, IsActive, Notes, AmountType, ConditionFlag, BranchCode)
    VALUES
        ('PV', 'VOUCHER-MANUAL-FXVAR', 'Vouchering Manual - Realized FX Loss', 1, 'D', '60323', 'REALIZED GAIN/LOSS ON FOREX',
         1, 0, 1, 'Auto-mapped FX variance leg for VoucheringManualFrm (Amount to Apply > Balance)', 'FXLOSS', 'HasFXLoss', NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.JournalEntryMapping WHERE Mnemonic = 'VOUCHER-MANUAL-FXVAR' AND ConditionFlag = 'HasFXGain')
    INSERT INTO dbo.JournalEntryMapping
        (Origin, Mnemonic, Description, Seq, DebitCredit, AccountCode, AccountDescription,
         IsConditional, IsAmountFromSource, IsActive, Notes, AmountType, ConditionFlag, BranchCode)
    VALUES
        ('PV', 'VOUCHER-MANUAL-FXVAR', 'Vouchering Manual - Realized FX Gain', 2, 'C', '60323', 'REALIZED GAIN/LOSS ON FOREX',
         1, 0, 1, 'Auto-mapped FX variance leg for VoucheringManualFrm (Amount to Apply < Balance)', 'FXGAIN', 'HasFXGain', NULL);
GO

-- ----------------------------------------------------------------
-- 3. New TVP shape — VoucherManualInvoiceTVP_v2 (old type untouched)
-- ----------------------------------------------------------------
IF TYPE_ID(N'dbo.VoucherManualInvoiceTVP_v2') IS NULL
    CREATE TYPE dbo.VoucherManualInvoiceTVP_v2 AS TABLE
    (
        BranchCode               VARCHAR(5),
        InvoiceNo                VARCHAR(150),
        SequenceReferenceNumber  VARCHAR(50),
        BatchReferenceID         BIGINT,
        AmountPaid                DECIMAL(18,2),
        Variance                  DECIMAL(18,2)   -- NEW: AmountPaid - Variance = the invoice's Balance
    );
GO

-- ----------------------------------------------------------------
-- 4. sp_PostVoucherManual — rebuilt on VoucherManualInvoiceTVP_v2
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_PostVoucherManual', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_PostVoucherManual', 'sp_PostVoucherManual_OLD_20260915120000';
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
    @parmcreditglcode  VARCHAR(20),
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
    Posts a manual (no-mapping) compound voucher. Invoice lines fully
    settle their Balance (Gross = AmountPaid - Variance); the FX
    variance auto-posts to whatever JournalEntryMapping maps
    Mnemonic='VOUCHER-MANUAL-FXVAR' to (currently 60323).
    Callers: VoucheringManualFrm.cs BtnPost_Click.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ── Validation ──────────────────────────────────────────────
    -- NOTE: @InvoiceLines CAN be empty - this module also supports
    -- pure GL-to-GL fund transfers (Cash to Cash, no invoice being
    -- paid). The AP-Trade tie-check below still applies and works
    -- correctly with zero invoices: SUM(Gross)=0 naturally matches
    -- SUM(AP-Trade Debit)=0, since a fund transfer wouldn't touch an
    -- AP-Trade account (20101/20102/20103) either.
    IF EXISTS (SELECT 1 FROM @InvoiceLines WHERE ISNULL(AmountPaid,0) <= 0)
    BEGIN
        THROW 58002, 'Every checked invoice must have an Amount Paid greater than zero.', 1;
        RETURN;
    END

    -- NEW: Variance only makes sense for Telegraphic (USD-invoiced
    -- suppliers converted at today's rate) - a Check/Cash voucher is
    -- always same-currency, so a nonzero Variance there would post a
    -- spurious FX gain/loss and misstate what the physical instrument
    -- actually settled.
    IF @parmvouchertype IN ('CHECK','CASH') AND EXISTS (SELECT 1 FROM @InvoiceLines WHERE ISNULL(Variance,0) <> 0)
    BEGIN
        THROW 58022, 'A Variance (FX difference) is only supported for Telegraphic Transfer vouchers - Amount Paid must equal Balance exactly for Check/Cash.', 1;
        RETURN;
    END

    IF (SELECT COUNT(*) FROM @GLLines) = 0
    BEGIN
        THROW 58003, 'The GL entry needs at least one line.', 1;
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

    DECLARE @GLTotalDebit DECIMAL(18,2), @GLTotalCredit DECIMAL(18,2);
    SELECT @GLTotalDebit = ISNULL(SUM(Debit),0), @GLTotalCredit = ISNULL(SUM(Credit),0) FROM @GLLines;

    -- NEW: total FX variance across all checked invoices. Positive =
    -- more cash paid than the invoices' recorded Balance (FX loss).
    -- Negative = less cash paid (FX gain).
    DECLARE @TotalVariance DECIMAL(18,2) = ISNULL((SELECT SUM(Variance) FROM @InvoiceLines), 0);
    DECLARE @FXLoss DECIMAL(18,2) = CASE WHEN @TotalVariance > 0 THEN @TotalVariance ELSE 0 END;
    DECLARE @FXGain DECIMAL(18,2) = CASE WHEN @TotalVariance < 0 THEN -@TotalVariance ELSE 0 END;

    -- The grid no longer needs to balance on its own - whatever's
    -- left over (Debit total minus Credit total) is the residual cash
    -- that gets auto-posted as a Credit to @parmcreditglcode. Widened
    -- by @TotalVariance: the actual cash leaving the bank differs
    -- from the manually-entered GL debit total (which ties to Gross,
    -- not cash) by exactly the FX variance.
    DECLARE @ResidualCash DECIMAL(18,2) = @GLTotalDebit - @GLTotalCredit + @TotalVariance;

    IF @ResidualCash < 0
    BEGIN
        THROW 58012, 'GL entry''s Credit total exceeds Debit total - check your entries.', 1;
        RETURN;
    END

    IF @ResidualCash = 0
    BEGIN
        THROW 58013, 'No residual cash - Debit and Credit in the GL entry already balance, so nothing would post to Credit GLCode.', 1;
        RETURN;
    END

    IF LTRIM(RTRIM(ISNULL(@parmcreditglcode,''))) = ''
    BEGIN
        THROW 58014, 'Credit GLCode is required.', 1;
        RETURN;
    END

    -- ── THE tie-check: invoices vs. GL entry ──
    -- Compares the GL entry's AP-Trade Debit total against SUM(Gross)
    -- - the amount that actually extinguishes each invoice's Balance
    -- - not SUM(AmountPaid), which includes the FX-adjusted cash.
    DECLARE @TotalGross DECIMAL(18,2), @APTradeDebitTotal DECIMAL(18,2);
    SELECT @TotalGross = ISNULL(SUM(AmountPaid - ISNULL(Variance,0)),0) FROM @InvoiceLines;
    SELECT @APTradeDebitTotal = ISNULL(SUM(Debit),0) FROM @GLLines WHERE AccountCode IN ('20101','20102','20103');

    IF @TotalGross <> @APTradeDebitTotal
    BEGIN
        DECLARE @TieMsg VARCHAR(500) = 'The GL entry''s AP-Trade debit total (' + CAST(@APTradeDebitTotal AS VARCHAR(30))
            + ') does not match the sum of invoice Balances being paid off (' + CAST(@TotalGross AS VARCHAR(30))
            + '). Debit whichever AP-Trade/Accrued Payable account (20101/20102/20103) applies for exactly the total of the invoices'' recorded Balance (Amount to Apply minus Variance), not the FX-adjusted cash.';
        THROW 58008, @TieMsg, 1;
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

    DECLARE @supplierkey VARCHAR(30);
    SELECT @supplierkey = SupplierKey FROM Supplier WHERE SupplierID = @parmsupplierid;

    IF @supplierkey IS NULL
    BEGIN
        THROW 58011, 'Supplier not found.', 1;
        RETURN;
    END

    -- NEW: duplicate-post guard - a retry or a double-click must not
    -- silently double-pay the supplier (AP balances clamp at 0 and
    -- would swallow a second post without erroring otherwise).
    IF EXISTS (SELECT 1 FROM TicketMaster WHERE ReferenceNumber = @parmrefno AND Mnemonic = 'VOUCHER-MANUAL')
    BEGIN
        THROW 58020, 'A voucher has already been posted under this reference number.', 1;
        RETURN;
    END

    -- NEW: resolve the FX variance account(s) up front, before any
    -- write, so a missing mapping fails fast instead of mid-post.
    DECLARE @FXLossAccountCode VARCHAR(20), @FXGainAccountCode VARCHAR(20);

    IF @FXLoss > 0
    BEGIN
        SELECT @FXLossAccountCode = AccountCode FROM dbo.JournalEntryMapping
        WHERE Mnemonic = 'VOUCHER-MANUAL-FXVAR' AND ConditionFlag = 'HasFXLoss' AND IsActive = 1;

        IF @FXLossAccountCode IS NULL
        BEGIN
            THROW 58017, 'No active JournalEntryMapping found for VOUCHER-MANUAL-FXVAR / HasFXLoss (Realized Loss on Forex). Verify seed data.', 1;
            RETURN;
        END
    END

    IF @FXGain > 0
    BEGIN
        SELECT @FXGainAccountCode = AccountCode FROM dbo.JournalEntryMapping
        WHERE Mnemonic = 'VOUCHER-MANUAL-FXVAR' AND ConditionFlag = 'HasFXGain' AND IsActive = 1;

        IF @FXGainAccountCode IS NULL
        BEGIN
            THROW 58018, 'No active JournalEntryMapping found for VOUCHER-MANUAL-FXVAR / HasFXGain (Realized Gain on Forex). Verify seed data.', 1;
            RETURN;
        END
    END

    BEGIN TRY
        BEGIN TRAN;

        -- ── Voucher header - Amount = net cash = the GL entry's own
        --    total (this SP has no gross/net ambiguity to begin with,
        --    since the user built the whole entry themselves) ──
        IF @parmvouchertype = 'TELEGRAPHIC'
            INSERT INTO [dbo].[TelegraphicVoucher]
                (VoucherID, SupplierID, ReferenceNumber, PaidTo, Particulars, Amount,
                 PreparedBy, VerifiedBy, NotedBy, PaymentApprovedBy, PaymentReceivedBy,
                 OfficialReceiptNo, VoucherType, DateReceived, DateAdded, DateUpdate,
                 isErrorCorrect, isLiquidation)
            VALUES
                (@parmvoucherid, @parmsupplierid, @parmrefno, @parmsuppliername,
                 @parmremarks, @ResidualCash, @parmpreparedby, '', @parmcontrolno, '', '',
                 @parmcreditglcode, 'TELEGRAPHIC', @parmvoucherdate, GETDATE(), GETDATE(), 0, 0);
        ELSE
            INSERT INTO [dbo].[CashVoucher]
                (VoucherID, SupplierID, ReferenceNumber, PaidTo, Particulars, Amount,
                 PreparedBy, VerifiedBy, NotedBy, PaymentApprovedBy, PaymentReceivedBy,
                 OfficialReceiptNo, VoucherType, DateReceived, DateAdded, DateUpdate,
                 isErrorCorrect, isLiquidation)
            VALUES
                (@parmvoucherid, @parmsupplierid, @parmrefno, @parmsuppliername,
                 @parmremarks, @ResidualCash, @parmpreparedby, '', @parmcontrolno, '', '',
                 @parmcreditglcode, 'CASH', @parmvoucherdate, GETDATE(), GETDATE(), 0, 0);

        DECLARE @SeqNo INT;
        SELECT @SeqNo = ISNULL(MAX(SEQ_NO),0) + 1 FROM TransactionPaymentAP WHERE SupplierKey = @supplierkey;
        INSERT INTO [dbo].[TransactionPaymentAP]
            (SEQ_NO, SupplierKey, ReferenceNumber, Amount, VoucherType,
             DatePaid, ExecuteBy, DateUpdate, UpdateBy, ErrorCorrect)
        VALUES (@SeqNo, @supplierkey, @parmrefno, @ResidualCash, @parmvouchertype,
                GETDATE(), @parmpreparedby, GETDATE(), @parmpreparedby, 0);

        -- ── One ticket, the whole compound entry exactly as the user built it ──
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

        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        SELECT @parmvoucherdate, 0, @parmbranch, @parmvoucherid, @ticketnum, @parmrefno,
               AccountCode, Debit, Credit, ''
        FROM @GLLines;

        -- The auto-posted Credit leg for the residual cash amount,
        -- against the header's Credit GLCode selection.
        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        VALUES
            (@parmvoucherdate, 0, @parmbranch, @parmvoucherid, @ticketnum, @parmrefno,
             @parmcreditglcode, 0, @ResidualCash, '');

        -- NEW: the auto-posted FX variance leg(s), against the
        -- JournalEntryMapping-resolved account (60323 today).
        IF @FXLoss > 0
            INSERT INTO [dbo].[TicketDetails]
                (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                 TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
            VALUES
                (@parmvoucherdate, 0, @parmbranch, @parmvoucherid, @ticketnum, @parmrefno,
                 @FXLossAccountCode, @FXLoss, 0, '');

        IF @FXGain > 0
            INSERT INTO [dbo].[TicketDetails]
                (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                 TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
            VALUES
                (@parmvoucherdate, 0, @parmbranch, @parmvoucherid, @ticketnum, @parmrefno,
                 @FXGainAccountCode, 0, @FXGain, '');

        -- ── Per-invoice settlement - mirrors the existing PURCHASE/
        --    EXPENSE settlement patterns already established. Gross
        --    (AmountPaid - Variance) always extinguishes the invoice's
        --    Balance in full; Variance itself is booked above as the
        --    FX leg(s), never touches APAccounts/ExpenseSummary ──
        DECLARE @row INT = 1, @maxrow INT, @invBranch VARCHAR(5), @invInvoiceNo VARCHAR(150),
                @invSeqRef VARCHAR(50), @invBatchRef BIGINT, @invAmtPaid DECIMAL(18,2),
                @invVariance DECIMAL(18,2), @invGross DECIMAL(18,2),
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

                -- NEW: Gross must equal the invoice's CURRENT Balance.
                -- If it doesn't, the invoice grid was loaded against a
                -- Balance that has since changed (e.g. another payment
                -- posted against it in the meantime) - the "checking an
                -- invoice always fully settles it" guarantee no longer
                -- holds, so fail loudly instead of silently leaving a
                -- phantom residual Balance or writing off an
                -- uncompensated surplus.
                IF ROUND(@invCurBalance - @invGross, 2) <> 0
                BEGIN
                    DECLARE @StaleMsgP VARCHAR(500) = 'Invoice ' + @invInvoiceNo + ': its Balance (' + CAST(@invCurBalance AS VARCHAR(30))
                        + ') no longer matches what this voucher expects to pay off (' + CAST(@invGross AS VARCHAR(30))
                        + '). It may have been paid or adjusted since this voucher was loaded - refresh Load Invoices and try again.';
                    THROW 58024, @StaleMsgP, 1;
                END

                -- Overpayment guard now checks the CASH figure against
                -- Balance (unchanged intent) - Check/Cash still can't
                -- carry an FX variance, only Telegraphic (also now
                -- enforced up front, before any write - see 58022).
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
                        @parmpaymethod, @parmvouchertype, @ticketnum, '', '',
                        @invSeqRef, NULL, @invVariance);
            END
            ELSE  -- EXPENSE
            BEGIN
                SET @invCurBalance = NULL;
                SELECT @invCurBalance = ISNULL(Balance, ISNULL(Amount,0)) FROM ExpenseSummary WITH (UPDLOCK, ROWLOCK)
                WHERE SupplierID = @supplierkey AND InvoiceNo = @invInvoiceNo AND BatchReferenceID = @invBatchRef;

                IF @invCurBalance IS NULL
                BEGIN
                    THROW 58023, 'Invoice ' + @invInvoiceNo + ' was not found in ExpenseSummary (BatchReferenceID ' + CAST(ISNULL(@invBatchRef,0) AS VARCHAR(30)) + ').', 1;
                END

                -- NEW: same Gross-vs-current-Balance guard as PURCHASE - see 58024 above.
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
                        @parmpaymethod, @parmvouchertype, @ticketnum, '', '',
                        CAST(@invBatchRef AS VARCHAR(50)), @invBatchRef, @invVariance);
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

        -- ── Bank Recon: the auto-posted Credit GLCode leg ──
        DECLARE @PeriodEnd DATE = EOMONTH(@parmvoucherdate);
        DECLARE @Remarks VARCHAR(500);

        SET @Remarks =
            'Auto-OC | VOUCHER-MANUAL | Ref: '
            + ISNULL(@parmrefno, '');
        IF EXISTS (SELECT 1 FROM ChartOfAccounts WHERE AccountCode = @parmcreditglcode AND AccountCode LIKE '10102%')
            EXEC dbo.sp_Payment_PostBankReconEntry
                @ItemType='OC', @BranchCode=@parmbranch, @AccountCode=@parmcreditglcode,
                @PeriodEnd=@PeriodEnd, @ReferenceNo=@parmvoucherid, @ItemDate=@parmvoucherdate,
                @Payee=@parmsuppliername, @Amount=@ResidualCash,
                @Remarks=@Remarks,
                @SourceModule='AP-PAYMENT', @SourceRef=@parmrefno, @CreatedBy=@parmpreparedby;

        -- ── Bank Recon - auto-detect bank-account lines in the GL
        --    entry ITSELF (separate from the Credit GLCode leg above) ──
        IF EXISTS (SELECT 1 FROM @GLLines gl JOIN ChartOfAccounts coa ON coa.AccountCode = gl.AccountCode WHERE coa.AccountCode LIKE '10102%')
        BEGIN
            DECLARE @bi INT = 1, @bmax INT, @bAcct VARCHAR(20), @bDebit DECIMAL(18,2), @bCredit DECIMAL(18,2), @bPart VARCHAR(500);
            IF OBJECT_ID('tempdb..#BankLines') IS NOT NULL DROP TABLE #BankLines;
            SELECT ROW_NUMBER() OVER (ORDER BY gl.AccountCode) AS RowNum, gl.AccountCode, gl.Debit, gl.Credit, gl.Particulars
            INTO #BankLines
            FROM @GLLines gl JOIN ChartOfAccounts coa ON coa.AccountCode = gl.AccountCode
            WHERE coa.AccountCode LIKE '10102%';

            SELECT @bmax = COUNT(*) FROM #BankLines;
            WHILE @bi <= @bmax
            BEGIN
                SELECT @bAcct = AccountCode, @bDebit = Debit, @bCredit = Credit, @bPart = Particulars FROM #BankLines WHERE RowNum = @bi;

                IF @bCredit > 0
                BEGIN
                     SET @Remarks =
                        'Auto-OC | VOUCHER-MANUAL | Ref: '
                        + ISNULL(@parmrefno, '')
                        + ISNULL(' | ' + @bPart, '');
                    EXEC dbo.sp_Payment_PostBankReconEntry
                        @ItemType='OC', @BranchCode=@parmbranch, @AccountCode=@bAcct,
                        @PeriodEnd=@PeriodEnd, @ReferenceNo=@parmvoucherid, @ItemDate=@parmvoucherdate,
                        @Payee=@parmsuppliername, @Amount=@bCredit,
                        @Remarks=@Remarks,
                        @SourceModule='AP-PAYMENT', @SourceRef=@parmrefno, @CreatedBy=@parmpreparedby;
                END

                IF @bDebit > 0
                BEGIN
                     SET @Remarks =
                        'Auto-DIT | VOUCHER-MANUAL | Ref: '
                        + ISNULL(@parmrefno, '')
                        + ISNULL(' | ' + @bPart, '');
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
        END

        -- NEW: prove the whole compound entry balances before commit
        -- (cheap, and catches a leg-building bug at post time instead
        -- of at month-end).
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

        SELECT 1 AS Status, @parmrefno AS ReferenceNo, @ResidualCash AS TotalAmount,
               'Voucher posted successfully.' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------
-- 5. sp_GetVoucherManualDetails — surface Variance in the drill-down
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_GetVoucherManualDetails', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetVoucherManualDetails', 'sp_GetVoucherManualDetails_OLD_20260915120000';
GO

CREATE PROCEDURE [dbo].[sp_GetVoucherManualDetails]
(
    @ReferenceNumber VARCHAR(10)
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Header
    SELECT TOP 1
        tm.TicketNumber, tm.ReferenceNumber, tm.BranchCode, tm.TicketDate AS VoucherDate,
        tm.Particulars AS Remarks, tm.Owner AS PaidTo, apd.SupplierID
    FROM TicketMaster tm
    OUTER APPLY (SELECT TOP 1 SupplierID FROM APPaymentDetails WHERE ReferenceNumber = tm.ReferenceNumber) apd
    WHERE tm.ReferenceNumber = @ReferenceNumber AND tm.Mnemonic = 'VOUCHER-MANUAL';

    -- Invoices paid - same shape the entry-side grid uses, so Copy
    -- can reuse the same loading logic where practical. Variance
    -- added so the drill-down shows the FX difference per invoice.
    SELECT
        apd.InvoiceNo, apd.BranchCode, apd.Amount AS AmountToApply, apd.Variance,
        apd.InvoiceDate, apd.PaymentMethod, apd.SequenceReferenceNumber, apd.BatchReferenceID
    FROM APPaymentDetails apd
    WHERE apd.ReferenceNumber = @ReferenceNumber
    ORDER BY apd.InvoiceNo;

    -- Compound GL entry - the FULL entry as posted, including the
    -- auto-generated Credit GLCode leg and the auto-generated FX
    -- variance leg (there's no way to tell either apart from a
    -- user-entered line after the fact, which is fine - Copy just
    -- recreates the same picture the user built)
    SELECT
        td.AccountCode, coa.Description AS AccountTitle, td.Debit, td.Credit, ''  AS Particulars
    FROM TicketDetails td
    LEFT JOIN ChartOfAccounts coa ON coa.AccountCode = td.AccountCode
    WHERE td.ReferenceNumber = @ReferenceNumber
    ORDER BY td.Debit DESC, td.Credit DESC;
END
GO
