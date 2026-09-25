/* ================================================================
   2026-09-24c: Supplier Payment -- OverPay / OverPay (Expense) /
   Advance Applied for EXPENSE SINGLE-mode invoices.
   Extends SQL/2026-09-24_SupplierPayment_OverpaymentCredit.sql
   (PURCHASE only) -- read that header first for the GL design.
   ================================================================
   Confirmed with user: go ahead with Expense SINGLE; BATCH (multi-branch
   split) stays unsupported. The supplier credit pool is SHARED across
   PURCHASE and EXPENSE (sp_GetSupplierAvailableCredit already sums every
   OVERPAY / ADVANCEAPPLIED row for the supplier regardless of
   PaymentMethod) -- an overpaid purchase invoice can be applied to an
   expense invoice and vice versa. No change needed there, nor to the
   per-supplier applock / credit checks in V2 or the credit-consumed
   reversal guard in sp_CancelledChequesCS, which are all method-agnostic.

   SINGLE-mode GL (SINGLE-PAY ticket via sp_Payment_PostSettlementTicket):
     Gross = cash + EWT + Discount + Offset + AdvanceApplied - OverPay - OverPayExpense
     DR <PayableAccountCode>  Gross
     DR 101030208             OverPay         (PV-AP-OVERPAY mapping)
     DR 60339                 OverPayExpense  (PV-AP-OVERPAYEXP mapping)
     CR <bank>                cash
     CR 20104 / discount / offset (unchanged)
     CR 101030208             AdvanceApplied  (PV-AP-ADVAPPLIED mapping)
   Accounts are read from the existing PURCHASE mapping rows, so both modes
   always hit the same accounts.

   Objects:
     1. sp_Payment_PostSettlementTicket -- 6 new OPTIONAL params (amounts
        default 0) + 3 conditional legs. BATCH and every other caller pass
        none of them and post exactly as before.
     2. sp_AddPaymentSupplierCompound_V2 -- SINGLE branch: new Gross formula,
        60515 "only when fully settled" guard, DR = CR pre-check (60518),
        extras rows in APPaymentDetails (PaymentMethod 'EXPENSE').
        ExpenseSummary.AmountPaid now += cash + AdvanceApplied - OverPay -
        OverPayExpense (identical to the old "+ cash" when extras are 0).
        BATCH branch: THROW 60509 if a BATCH line carries extras (moved
        from the top of the proc, which used to reject all non-PURCHASE).
     3. sp_CancelledChequesCS -- EXPENSE reversal restores Balance from
        PaymentType = 'EXPENSE PAYMENT' rows only (verified: every existing
        EXPENSE row on DEV (31) and STAGING (74) is 'EXPENSE PAYMENT', so
        existing reversals are unaffected).

   Pre-existing, NOT changed (flagged): EXPENSE reversal subtracts the
   Gross from ExpenseSummary.AmountPaid although posting only ever added
   the non-withholding part -- AmountPaid can drift low by the EWT/
   Discount/Offset withheld after a reversal. Balance/Status are correct.

   Deploy to CORECSERP_002_DEV first; mirror to CORECSJFC2026_STAGING only
   after confirming with the user (after the 2026-09-24 PURCHASE script).
   ================================================================ */

-- ----------------------------------------------------------------
-- 1. sp_Payment_PostSettlementTicket
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_Payment_PostSettlementTicket', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_Payment_PostSettlementTicket', 'sp_Payment_PostSettlementTicket_OLD_09242026235900';
GO


-- ================================================================
-- HELPER 2: sp_Payment_PostSettlementTicket
-- Posts ONE TicketMaster + its full set of TicketDetails legs
-- (payable extinguishment, net cash, EWT, discount, offset, FX)
-- for one branch's settlement. Replaces what used to be six
-- near-identical IF blocks, hand-copied once for SINGLE mode and
-- once per branch for BATCH mode — now there is exactly one
-- implementation, called from both.
-- ================================================================
CREATE   PROCEDURE [dbo].[sp_Payment_PostSettlementTicket]
(
    @TicketDate          DATE,
    @BranchCode          VARCHAR(5),
    @ReferenceKey        VARCHAR(20),     -- VoucherID
    @ReferenceNumber     VARCHAR(10),
    @Owner               VARCHAR(150),
    @Particulars         VARCHAR(4000),
    @PreparedBy          VARCHAR(50),
    @Mnemonic            VARCHAR(50),
    @Origin              VARCHAR(10) = 'PV',

    @PayableAccountCode  VARCHAR(20),
    @GrossPayable        DECIMAL(18,2),   -- DR payable — full liability extinguished this ticket

    @BankAccountCode     VARCHAR(20),
    @NetCash             DECIMAL(18,2) = 0,   -- CR bank — NET only, never includes EWT/Discount/Offset

    @EWTAmount           DECIMAL(18,2) = 0,
    @EWTAccountCode      VARCHAR(20)   = '20104',
    @DiscountAmount      DECIMAL(18,2) = 0,
    @DiscountAccountCode VARCHAR(20)   = NULL,   -- caller must resolve override-or-'508' before calling
    @OffsetAmount        DECIMAL(18,2) = 0,
    @OffsetAccountCode   VARCHAR(20)   = '40104',
    @FXLoss              DECIMAL(18,2) = 0,
    @FXLossAccountCode   VARCHAR(20)   = '60310',
    @FXGain              DECIMAL(18,2) = 0,
    @FXGainAccountCode   VARCHAR(20)   = '40510',

    -- NEW 2026-09-24c: supplier overpayment / advance legs (SINGLE-mode
    -- expense payments only). All default 0, so every existing caller -
    -- including BATCH - posts exactly as before. Caller resolves the
    -- accounts from JournalEntryMapping (PV-AP-OVERPAY / -OVERPAYEXP /
    -- -ADVAPPLIED) and passes them in.
    @OverPay                   DECIMAL(18,2) = 0,   -- DR supplier advances - excess cash carried forward
    @OverPayAccountCode        VARCHAR(50)   = NULL,
    @OverPayExpense            DECIMAL(18,2) = 0,   -- DR expense - excess cash written off
    @OverPayExpenseAccountCode VARCHAR(50)   = NULL,
    @AdvanceApplied            DECIMAL(18,2) = 0,   -- CR supplier advances - prior credit consumed
    @AdvanceAccountCode        VARCHAR(50)   = NULL,

    @TicketNumber        VARCHAR(20) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    IF (ISNULL(@OverPay, 0) > 0        AND NULLIF(LTRIM(RTRIM(ISNULL(@OverPayAccountCode, ''))), '') IS NULL)
       OR (ISNULL(@OverPayExpense, 0) > 0 AND NULLIF(LTRIM(RTRIM(ISNULL(@OverPayExpenseAccountCode, ''))), '') IS NULL)
       OR (ISNULL(@AdvanceApplied, 0) > 0 AND NULLIF(LTRIM(RTRIM(ISNULL(@AdvanceAccountCode, ''))), '') IS NULL)
        THROW 60521, 'sp_Payment_PostSettlementTicket: an OverPay / Advance amount was passed without its GL account.', 1;

    EXEC GetTicketNumber @TicketNumber OUTPUT;

    INSERT INTO [dbo].[TicketMaster]
        (TicketDate, SupplementaryNumber, BranchCode, Origin,
         TicketNumber, ReferenceNumber, ReferenceKey, Owner,
         Particulars, EnteredBy, CheckedBy, ApprovedBy,
         Status, Mnemonic, Product)
    VALUES
        (@TicketDate, 0, @BranchCode, @Origin, @TicketNumber,
         @ReferenceNumber, @ReferenceKey, @Owner, LEFT(@Particulars, 6999),
         @PreparedBy, '*', '*', 'POSTED', @Mnemonic, NULL);

    -- DR the payable account — always posted, this is the liability being settled
    INSERT INTO [dbo].[TicketDetails]
        (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
         TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
    VALUES
        (@TicketDate, 0, @BranchCode, @ReferenceKey, @TicketNumber, @ReferenceNumber,
         @PayableAccountCode, ROUND(@GrossPayable, 2), 0, '');

    IF @NetCash > 0
        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        VALUES
            (@TicketDate, 0, @BranchCode, @ReferenceKey, @TicketNumber, @ReferenceNumber,
             @BankAccountCode, 0, ROUND(@NetCash, 2), '');

    IF @EWTAmount > 0
        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        VALUES
            (@TicketDate, 0, @BranchCode, @ReferenceKey, @TicketNumber, @ReferenceNumber,
             @EWTAccountCode, 0, ROUND(@EWTAmount, 2), '');

    IF @DiscountAmount > 0
        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        VALUES
            (@TicketDate, 0, @BranchCode, @ReferenceKey, @TicketNumber, @ReferenceNumber,
             ISNULL(@DiscountAccountCode, '508'), 0, ROUND(@DiscountAmount, 2), '');

    IF @OffsetAmount > 0
        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        VALUES
            (@TicketDate, 0, @BranchCode, @ReferenceKey, @TicketNumber, @ReferenceNumber,
             @OffsetAccountCode, 0, ROUND(@OffsetAmount, 2), '');

    IF @FXLoss > 0
        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        VALUES
            (@TicketDate, 0, @BranchCode, @ReferenceKey, @TicketNumber, @ReferenceNumber,
             @FXLossAccountCode, ROUND(@FXLoss, 2), 0, '');

    IF @FXGain > 0
        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        VALUES
            (@TicketDate, 0, @BranchCode, @ReferenceKey, @TicketNumber, @ReferenceNumber,
             @FXGainAccountCode, 0, ROUND(@FXGain, 2), '');

    -- NEW 2026-09-24c
    IF @OverPay > 0
        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        VALUES
            (@TicketDate, 0, @BranchCode, @ReferenceKey, @TicketNumber, @ReferenceNumber,
             @OverPayAccountCode, ROUND(@OverPay, 2), 0, '');

    IF @OverPayExpense > 0
        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        VALUES
            (@TicketDate, 0, @BranchCode, @ReferenceKey, @TicketNumber, @ReferenceNumber,
             @OverPayExpenseAccountCode, ROUND(@OverPayExpense, 2), 0, '');

    IF @AdvanceApplied > 0
        INSERT INTO [dbo].[TicketDetails]
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        VALUES
            (@TicketDate, 0, @BranchCode, @ReferenceKey, @TicketNumber, @ReferenceNumber,
             @AdvanceAccountCode, 0, ROUND(@AdvanceApplied, 2), '');
END

GO

-- ----------------------------------------------------------------
-- 2. sp_AddPaymentSupplierCompound_V2
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_AddPaymentSupplierCompound_V2', 'sp_AddPaymentSupplierCompound_V2_OLD_09252026001500';
GO


/* ================================================================
   sp_AddPaymentSupplierCompound_V2
   Parallel to sp_AddPaymentSupplierCompound - same tables, same
   TVP shape (dbo.AP_PaymentLineTVP), callable as a drop-in test
   alternative. PURCHASE mode still delegates to your existing
   sp_PostCompoundTicket. EXPENSE mode (SINGLE + BATCH) is rebuilt
   entirely on the three helper procedures in 01_V2_Helpers.sql.

   PARAMETER CONTRACT (stated explicitly, not just assumed):
     @parmcheckamount MUST be net cash actually disbursed - never
     gross. This SP does not trust that blindly for Bank Recon:
     it self-computes net cash from the same figures used to build
     the tickets and uses THAT for Bank Recon and the voucher header.
   ================================================================ */
CREATE PROCEDURE [dbo].[sp_AddPaymentSupplierCompound_V2]
(
    @parmrefno          VARCHAR(10),
    @parmvoucherid      VARCHAR(10),
    @parmsupplierid     VARCHAR(50),
    @parmsuppliername   VARCHAR(150),
    @parmcheckamount    DECIMAL(18,2),
    @parmcheckcoding    VARCHAR(50),
    @parmcheckno        VARCHAR(50),
    @parmcontrolno      VARCHAR(50),
    @parmcheckdate      DATE,
    @parmcheckremarks   VARCHAR(2000),
    @parmpreparedby     VARCHAR(30),
    @parmglcode         VARCHAR(30),
    @parmpaymethod      VARCHAR(20),
    @parmforliquidation BIT          = 0,
    @parmvouchertype    VARCHAR(10),
    @Lines              [dbo].[AP_PaymentLineTVP] READONLY,
    @parmPayingBranch   VARCHAR(5)   = NULL,
    @LineExtras         [dbo].[AP_PaymentLineExtraTVP] READONLY   -- NEW 2026-09-24, optional (empty when omitted)
)
AS
/*
    2026-09-24: PURCHASE mode accepts per-line OverPay / OverPayExpense /
    AdvanceApplied via @LineExtras (see SQL/2026-09-24_SupplierPayment_
    OverpaymentCredit.sql header for the GL design). Per line:
        Gross (settles APAccounts.Balance)
          = AmountPaid + EWT + Discount + RetAllow + AdvanceApplied
            - Variance - OverPay - OverPayExpense
    OverPay/OverPayExpense are cash paid BEYOND the invoice; they are only
    allowed when Gross settles the fresh Balance exactly. AdvanceApplied is
    prior OverPay credit consumed instead of cash; total per voucher must not
    exceed the supplier's credit pool, re-derived under a per-supplier
    applock. Lines with none of the three post exactly as before (same
    mnemonics, same @Amounts/@Flags). EXPENSE mode rejects any nonzero extra.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION PaySupplierV2;
    BEGIN TRY

        DECLARE @SupplierKey VARCHAR(30), @SeqNo INT, @TicketNumber VARCHAR(20);
        DECLARE @PeriodEnd DATE = EOMONTH(ISNULL(@parmcheckdate,GETDATE()));
        DECLARE @ocPeriodEnd DATE;
        DECLARE @TotalNetCashForRecon DECIMAL(18,2) = 0;
        DECLARE @ocBranch VARCHAR(5) = NULLIF(LTRIM(RTRIM(ISNULL(@parmPayingBranch,''))), '');

        IF @parmcheckdate IS NULL SET @parmcheckdate = CAST(GETDATE() AS DATE);
        SET @ocPeriodEnd = EOMONTH(@parmcheckdate);

        SELECT @SupplierKey = SupplierKey FROM Supplier WHERE SupplierID = @parmsupplierid;

        IF @SupplierKey IS NULL
        BEGIN
            DECLARE @NoSupplierMsg VARCHAR(300) = 'Supplier ' + ISNULL(@parmsupplierid,'') + ' was not found.';
            THROW 60507, @NoSupplierMsg, 1;
        END

        SELECT @SeqNo = ISNULL(MAX(SEQ_NO),0) + 1 FROM TransactionPaymentAP WHERE SupplierKey = @SupplierKey;
        INSERT INTO [dbo].[TransactionPaymentAP]
            (SEQ_NO, SupplierKey, ReferenceNumber, Amount, VoucherType,
             DatePaid, ExecuteBy, DateUpdate, UpdateBy, ErrorCorrect)
        VALUES (@SeqNo, @SupplierKey, @parmrefno, @parmcheckamount, @parmvouchertype,
                @parmcheckdate, @parmpreparedby, GETDATE(), @parmpreparedby, 0);

        -- -- #Lines ------------------------------------------------
        SELECT
            ROW_NUMBER() OVER (ORDER BY L.BatchReferenceID, L.InvoiceNo) AS RowNum,
            L.InvoiceNo, L.InvoiceDate, L.SequenceReferenceNumber, L.BatchReferenceID,
            ISNULL(L.ActualCost, 0) AS ActualCost, ISNULL(L.AmountPaid, 0) AS AmountPaid,
            ISNULL(L.EWTAmount, 0) AS EWTAmount,
            ISNULL(L.DiscountAmount, 0) AS DiscountAmount,
            ISNULL(L.OffsetAmount, 0) AS OffsetAmount,
            ISNULL(L.Variance, 0) AS Variance,
            L.DiscountAccountCode,
            L.Description,
            -- NEW 2026-09-24
            ISNULL(X.OverPay, 0)        AS OverPay,
            ISNULL(X.OverPayExpense, 0) AS OverPayExpense,
            ISNULL(X.AdvanceApplied, 0) AS AdvanceApplied
        INTO #Lines
        FROM @Lines L
        LEFT JOIN @LineExtras X
               ON X.InvoiceNo = L.InvoiceNo
              AND X.SequenceReferenceNumber = L.SequenceReferenceNumber;

        -- -- NEW 2026-09-24: @LineExtras guards ----------------------
        -- An extras row that matches no invoice line would otherwise be
        -- silently dropped by the LEFT JOIN above.
        IF EXISTS (
            SELECT 1 FROM @LineExtras X
            WHERE NOT EXISTS (SELECT 1 FROM @Lines L
                              WHERE L.InvoiceNo = X.InvoiceNo
                                AND L.SequenceReferenceNumber = X.SequenceReferenceNumber)
        )
            THROW 60510, 'An OverPay/Advance line does not match any invoice being paid in this voucher.', 1;

        IF EXISTS (SELECT 1 FROM #Lines WHERE OverPay < 0 OR OverPayExpense < 0 OR AdvanceApplied < 0)
            THROW 60511, 'OverPay, OverPay (Expense), and Advance Applied cannot be negative.', 1;

        -- CHANGED 2026-09-24c: EXPENSE SINGLE-mode lines now support the
        -- extras too; only BATCH-mode (multi-branch) expense lines are
        -- rejected. Checked up front (sp-reviewer 24c) so a mixed SINGLE+
        -- BATCH voucher gets 60509, not a misleading 60514 from the credit
        -- check below summing a BATCH line's AdvanceApplied. The BATCH
        -- branch keeps its own per-line check as defense in depth.
        IF @parmpaymethod <> 'PURCHASE'
           AND EXISTS (
               SELECT 1
               FROM #Lines l
               JOIN ExpenseSummary es
                 ON es.SupplierID       = @SupplierKey
                AND es.BatchReferenceID = l.BatchReferenceID
                AND es.InvoiceNo        = l.InvoiceNo
               WHERE ISNULL(es.PostingMode, 'BATCH') <> 'SINGLE'
                 AND (l.OverPay > 0 OR l.OverPayExpense > 0 OR l.AdvanceApplied > 0)
           )
        BEGIN
            DECLARE @EBatchExtrasUpfrontMsg VARCHAR(400) = 'Invoice ' + (
                SELECT TOP 1 l.InvoiceNo
                FROM #Lines l
                JOIN ExpenseSummary es
                  ON es.SupplierID = @SupplierKey AND es.BatchReferenceID = l.BatchReferenceID AND es.InvoiceNo = l.InvoiceNo
                WHERE ISNULL(es.PostingMode, 'BATCH') <> 'SINGLE'
                  AND (l.OverPay > 0 OR l.OverPayExpense > 0 OR l.AdvanceApplied > 0)
                ORDER BY l.RowNum)
                + ' is a BATCH (multi-branch) expense - OverPay / Advance Applied is supported only for PURCHASE and SINGLE expense invoices.';
            THROW 60509, @EBatchExtrasUpfrontMsg, 1;
        END

        -- One variant per line: each selects a different mnemonic.
        IF EXISTS (
            SELECT 1 FROM #Lines
            WHERE (CASE WHEN OverPay        > 0 THEN 1 ELSE 0 END
                 + CASE WHEN OverPayExpense > 0 THEN 1 ELSE 0 END
                 + CASE WHEN AdvanceApplied > 0 THEN 1 ELSE 0 END) > 1
        )
        BEGIN
            DECLARE @MixMsg VARCHAR(400) = 'Invoice ' + (SELECT TOP 1 InvoiceNo FROM #Lines
                WHERE (CASE WHEN OverPay > 0 THEN 1 ELSE 0 END + CASE WHEN OverPayExpense > 0 THEN 1 ELSE 0 END
                     + CASE WHEN AdvanceApplied > 0 THEN 1 ELSE 0 END) > 1)
                + ': OverPay, OverPay (Expense), and Advance Applied cannot be combined on the same invoice - choose only one.';
            THROW 60512, @MixMsg, 1;
        END

        -- Same rule as AR: the excess attaches to exactly one invoice.
        IF (SELECT COUNT(*) FROM #Lines WHERE OverPay > 0 OR OverPayExpense > 0) > 1
            THROW 60513, 'OverPay / OverPay (Expense) must be assigned to only one invoice per voucher.', 1;

        -- Credit pool: serialize per supplier, then re-derive fresh (Known Bug
        -- Pattern #10 -- never trust the UI's Available Credit label).
        -- Only taken when this voucher draws credit; posting OverPay only
        -- ever increases the pool, so it can't make a concurrent draw unsafe.
        -- sp_CancelledChequesCS takes the same lock before reversing a
        -- voucher that created credit.
        DECLARE @TotalAdvanceApplied DECIMAL(18,2) = (SELECT ISNULL(SUM(AdvanceApplied), 0) FROM #Lines);
        IF @TotalAdvanceApplied > 0
        BEGIN
            DECLARE @LockResult INT, @LockResource NVARCHAR(255) = N'APCREDIT:' + @parmsupplierid;
            EXEC @LockResult = sp_getapplock
                @Resource    = @LockResource,
                @LockMode    = 'Exclusive',
                @LockOwner   = 'Transaction',
                @LockTimeout = 10000;

            IF @LockResult < 0
                THROW 60517, 'Could not acquire a lock for this supplier''s advance credit (another payment or reversal for the same supplier is in progress). Please try again.', 1;

            DECLARE @PriorAvailableCredit DECIMAL(18,2);
            SELECT @PriorAvailableCredit =
                ISNULL(SUM(CASE WHEN d.PaymentType = 'OVERPAY'        THEN d.Amount ELSE 0 END), 0)
              - ISNULL(SUM(CASE WHEN d.PaymentType = 'ADVANCEAPPLIED' THEN d.Amount ELSE 0 END), 0)
            FROM APPaymentDetails d
            WHERE d.SupplierID = @parmsupplierid
              AND d.PaymentType IN ('OVERPAY', 'ADVANCEAPPLIED')
              AND d.VoucherID <> @parmvoucherid
              AND NOT EXISTS (SELECT 1 FROM PaymentReversalAudit r
                              WHERE r.VoucherID = d.VoucherID AND r.SupplierID = d.SupplierID);

            IF @TotalAdvanceApplied > ISNULL(@PriorAvailableCredit, 0)
            BEGIN
                DECLARE @CreditMsg VARCHAR(400) = 'Advance Applied (' + CAST(@TotalAdvanceApplied AS VARCHAR(30))
                    + ') exceeds this supplier''s available advance credit (' + CAST(ISNULL(@PriorAvailableCredit, 0) AS VARCHAR(30)) + ').';
                THROW 60514, @CreditMsg, 1;
            END
        END

        DECLARE @maxrow INT, @row INT = 1;
        SELECT @maxrow = COUNT(*) FROM #Lines;

        IF @ocBranch IS NULL
            SELECT TOP 1 @ocBranch = BranchCode
            FROM ExpenseMaster
            WHERE SupplierID = @SupplierKey
              AND BatchReferenceID = (SELECT TOP 1 BatchReferenceID FROM #Lines ORDER BY RowNum)
            ORDER BY TRN_SEQ_NO;

        -- ============================================================
        -- PURCHASE
        -- ============================================================
        IF @parmpaymethod = 'PURCHASE'
        BEGIN
            DECLARE @pInvoiceNo VARCHAR(150), @pInvoiceDate DATE, @pSeqRef VARCHAR(50),
                    @pAmtPaid DECIMAL(18,2), @pEWT DECIMAL(18,2), @pDiscount DECIMAL(18,2),
                    @pRetAllow DECIMAL(18,2), @pVariance DECIMAL(18,2), @pGross DECIMAL(18,2),
                    @pFXLoss DECIMAL(18,2), @pFXGain DECIMAL(18,2), @pMnemonic VARCHAR(50),
                    @pParticulars VARCHAR(7000), @pBranchCode VARCHAR(5) = '888',
                    @pCurBalance DECIMAL(18,2),
                    -- NEW 2026-09-24
                    @pOverPay DECIMAL(18,2), @pOverPayExp DECIMAL(18,2), @pAdvApplied DECIMAL(18,2),
                    @pIsExtraMnemonic BIT, @pDr DECIMAL(18,2), @pCr DECIMAL(18,2);

            WHILE @row <= @maxrow
            BEGIN
                SELECT
                    @pInvoiceNo = InvoiceNo, @pInvoiceDate = InvoiceDate, @pSeqRef = SequenceReferenceNumber,
                    @pAmtPaid = AmountPaid, @pEWT = EWTAmount, @pDiscount = DiscountAmount,
                    @pRetAllow = OffsetAmount, @pVariance = Variance,
                    @pOverPay = OverPay, @pOverPayExp = OverPayExpense, @pAdvApplied = AdvanceApplied
                FROM #Lines WHERE RowNum = @row;

                -- CHANGED 2026-09-24: + AdvanceApplied - OverPay - OverPayExpense
                -- (all three are 0 for a plain line, so unchanged for them).
                SET @pGross = @pAmtPaid + @pEWT + @pDiscount + @pRetAllow + @pAdvApplied
                            - @pVariance - @pOverPay - @pOverPayExp;

                SET @pCurBalance = NULL;
                SELECT @pCurBalance = Balance FROM APAccounts WITH (UPDLOCK, ROWLOCK)
                WHERE SupplierID = @parmsupplierid AND InvoiceNo = @pInvoiceNo AND SequenceNo = @pSeqRef;

                IF @pCurBalance IS NULL
                BEGIN
                    DECLARE @PNotFoundMsg VARCHAR(400) = 'Invoice ' + ISNULL(@pInvoiceNo,'') + ' was not found in APAccounts (SequenceNo ' + ISNULL(@pSeqRef,'') + ').';
                    THROW 60501, @PNotFoundMsg, 1;
                END

                IF ROUND(@pGross - @pCurBalance, 2) > 0
                BEGIN
                    DECLARE @POverpayMsg VARCHAR(500) = 'Invoice ' + ISNULL(@pInvoiceNo,'') + ': the amount being settled (' + CAST(@pGross AS VARCHAR(30))
                        + ') exceeds its Balance (' + CAST(@pCurBalance AS VARCHAR(30)) + '). Lower Amount Paid, or put the excess in the OverPay / OverPay (Expense) column.';
                    THROW 60502, @POverpayMsg, 1;
                END

                -- NEW 2026-09-24: an overpayment is only an overpayment if the
                -- invoice is fully settled -- otherwise the "excess" is really
                -- an unpaid balance and must stay on the invoice.
                IF (@pOverPay > 0 OR @pOverPayExp > 0) AND ROUND(@pCurBalance - @pGross, 2) <> 0
                BEGIN
                    DECLARE @POverNotFullMsg VARCHAR(500) = 'Invoice ' + ISNULL(@pInvoiceNo,'') + ': OverPay is only allowed when the invoice is fully settled (Balance ' + CAST(@pCurBalance AS VARCHAR(30))
                        + ', settled ' + CAST(@pGross AS VARCHAR(30)) + ').';
                    THROW 60515, @POverNotFullMsg, 1;
                END

                SET @pFXLoss = CASE WHEN @pVariance > 0 THEN @pVariance ELSE 0 END;
                SET @pFXGain = CASE WHEN @pVariance < 0 THEN -@pVariance ELSE 0 END;
                SET @TotalNetCashForRecon += @pAmtPaid;

                SET @pIsExtraMnemonic = CASE WHEN @pOverPay > 0 OR @pOverPayExp > 0 OR @pAdvApplied > 0 THEN 1 ELSE 0 END;

                SET @pMnemonic = CASE
                    WHEN @pOverPay    > 0 THEN 'PV-AP-OVERPAY'
                    WHEN @pOverPayExp > 0 THEN 'PV-AP-OVERPAYEXP'
                    WHEN @pAdvApplied > 0 THEN 'PV-AP-ADVAPPLIED'
                    WHEN @pEWT>0 AND @pDiscount>0 THEN 'PV-AP-EWT-DISC'
                    WHEN @pEWT>0 THEN 'PV-AP-EWT'
                    WHEN @pDiscount>0 THEN 'PV-AP-DISC'
                    ELSE 'PV-AP' END;

                SET @pParticulars = 'PURCHASE PAYMENT | Supplier: '+@parmsupplierid
                    +' | Invoice: '+@pInvoiceNo+' | Ref: '+@parmrefno
                    +CASE WHEN LEN(ISNULL(@parmcheckremarks,''))>0 THEN ' | '+LEFT(@parmcheckremarks,200) ELSE '' END;

                DECLARE @Amounts dbo.tt_AmountBreakdown;
                DECLARE @Tokens  dbo.tt_TokenResolution;
                DECLARE @Flags   dbo.tt_ConditionFlags;
                DELETE FROM @Amounts; DELETE FROM @Tokens; DELETE FROM @Flags;
                INSERT @Tokens VALUES ('{BANK}', @parmglcode);

                IF @pIsExtraMnemonic = 0
                BEGIN
                    -- Unchanged from the prior version.
                    INSERT @Amounts VALUES ('GROSS',@pGross),('NET',@pAmtPaid),('EWT',@pEWT),
                                           ('MIRROR',@pDiscount+@pRetAllow),('VARIANCE_LOSS',@pFXLoss),('VARIANCE_GAIN',@pFXGain);
                    INSERT @Flags VALUES
                        ('HasEWT', CASE WHEN @pEWT>0 THEN 1 ELSE 0 END),
                        ('HasDiscount', CASE WHEN @pDiscount>0 THEN 1 ELSE 0 END),
                        ('HasFXLoss', CASE WHEN @pFXLoss>0 THEN 1 ELSE 0 END),
                        ('HasFXGain', CASE WHEN @pFXGain>0 THEN 1 ELSE 0 END);
                END
                ELSE
                BEGIN
                    -- NEW 2026-09-24: every AmountType the new mnemonics use is
                    -- supplied explicitly -- sp_PostCompoundTicket silently
                    -- substitutes GROSS for any AmountType it can't find.
                    INSERT @Amounts VALUES
                        ('GROSS', @pGross), ('NET', @pAmtPaid), ('EWT', @pEWT),
                        ('DISCRETALLOW', @pDiscount + @pRetAllow),
                        ('VARIANCE_LOSS', @pFXLoss), ('VARIANCE_GAIN', @pFXGain),
                        ('OVERPAY', @pOverPay), ('OVERPAYEXPENSE', @pOverPayExp),
                        ('ADVANCEAPPLIED', @pAdvApplied);
                    INSERT @Flags VALUES
                        ('HasNetCash',        CASE WHEN @pAmtPaid > 0 THEN 1 ELSE 0 END),
                        ('HasEWT',            CASE WHEN @pEWT > 0 THEN 1 ELSE 0 END),
                        ('HasDiscount',       CASE WHEN @pDiscount + @pRetAllow > 0 THEN 1 ELSE 0 END),
                        ('HasFXLoss',         CASE WHEN @pFXLoss > 0 THEN 1 ELSE 0 END),
                        ('HasFXGain',         CASE WHEN @pFXGain > 0 THEN 1 ELSE 0 END),
                        ('HasOverpay',        CASE WHEN @pOverPay > 0 THEN 1 ELSE 0 END),
                        ('HasOverpayExpense', CASE WHEN @pOverPayExp > 0 THEN 1 ELSE 0 END),
                        ('HasAdvanceApplied', CASE WHEN @pAdvApplied > 0 THEN 1 ELSE 0 END);

                    -- Pre-validate the ticket before posting: every active leg's
                    -- AmountType must be supplied, and DR must equal CR.
                    IF EXISTS (
                        SELECT 1 FROM JournalEntryMapping M
                        WHERE M.Mnemonic = @pMnemonic AND M.IsActive = 1
                          AND NOT EXISTS (SELECT 1 FROM @Amounts A WHERE A.AmountType = M.AmountType)
                    )
                        THROW 60518, 'JournalEntryMapping for the overpayment/advance mnemonic uses an AmountType this procedure does not supply.', 1;

                    SELECT
                        @pDr = ISNULL(SUM(CASE WHEN M.DebitCredit = 'D' THEN A.Amount ELSE 0 END), 0),
                        @pCr = ISNULL(SUM(CASE WHEN M.DebitCredit = 'C' THEN A.Amount ELSE 0 END), 0)
                    FROM JournalEntryMapping M
                    JOIN @Amounts A ON A.AmountType = M.AmountType
                    WHERE M.Mnemonic = @pMnemonic
                      AND M.IsActive = 1
                      AND (M.BranchCode IS NULL OR M.BranchCode = @pBranchCode)
                      AND (M.IsConditional = 0
                           OR EXISTS (SELECT 1 FROM @Flags F WHERE F.FlagName = M.ConditionFlag AND F.FlagValue = 1));

                    IF @pDr <> @pCr
                    BEGIN
                        DECLARE @PImbalMsg VARCHAR(400) = 'Invoice ' + ISNULL(@pInvoiceNo,'') + ': ' + @pMnemonic + ' ticket would not balance (Debit '
                            + CAST(@pDr AS VARCHAR(30)) + ', Credit ' + CAST(@pCr AS VARCHAR(30)) + ').';
                        THROW 60518, @PImbalMsg, 1;
                    END
                END

                EXEC [dbo].[sp_PostCompoundTicket]
                    @Mnemonic=@pMnemonic, @TicketDate=@parmcheckdate,
                    @BranchCode=@pBranchCode, @ReferenceNumber=@parmrefno,
                    @ReferenceKey=@parmvoucherid, @Particulars=@pParticulars,
                    @Owner=@parmsupplierid, @PreparedBy=@parmpreparedby,
                    @Status='POSTED', @Amounts=@Amounts, @Tokens=@Tokens,
                    @Flags=@Flags, @LedgerType='SUPPLIER',
                    @LedgerEntityID=@parmsupplierid,
                    @LedgerInvoiceNo=@pInvoiceNo, @LedgerBatchRef=NULL,
                    @LedgerSeqRef=@pSeqRef;

                IF @pAmtPaid > 0
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @pBranchCode,
                            @pInvoiceNo, @pInvoiceDate, @pAmtPaid, 'INVOICE PAYMENT',
                            @parmpaymethod, @parmvouchertype, '', @parmglcode, @parmglcode,
                            @pSeqRef, NULL);

                IF @pEWT > 0
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @pBranchCode,
                            @pInvoiceNo, @pInvoiceDate, @pEWT, 'EWT',
                            @parmpaymethod, @parmvouchertype, '', @parmglcode, @parmglcode,
                            @pSeqRef, NULL);

                IF @pDiscount > 0
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @pBranchCode,
                            @pInvoiceNo, @pInvoiceDate, @pDiscount, 'DISCOUNT',
                            @parmpaymethod, @parmvouchertype, '', @parmglcode, @parmglcode,
                            @pSeqRef, NULL);

                IF @pRetAllow > 0
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @pBranchCode,
                            @pInvoiceNo, @pInvoiceDate, @pRetAllow, 'RETURNALLOWANCES',
                            @parmpaymethod, @parmvouchertype, '', @parmglcode, @parmglcode,
                            @pSeqRef, NULL);

                IF @pVariance <> 0
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @pBranchCode,
                            @pInvoiceNo, @pInvoiceDate, @pVariance, 'VARIANCE',
                            @parmpaymethod, @parmvouchertype, '', @parmglcode, @parmglcode,
                            @pSeqRef, NULL);

                -- NEW 2026-09-24: OVERPAY / OVERPAYEXPENSE / ADVANCEAPPLIED rows --
                -- the credit pool (sp_GetSupplierAvailableCredit) and the
                -- PURCHASE reversal in sp_CancelledChequesCS both read these.
                IF @pOverPay > 0
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @pBranchCode,
                            @pInvoiceNo, @pInvoiceDate, @pOverPay, 'OVERPAY',
                            @parmpaymethod, @parmvouchertype, '', @parmglcode, @parmglcode,
                            @pSeqRef, NULL);

                IF @pOverPayExp > 0
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @pBranchCode,
                            @pInvoiceNo, @pInvoiceDate, @pOverPayExp, 'OVERPAYEXPENSE',
                            @parmpaymethod, @parmvouchertype, '', @parmglcode, @parmglcode,
                            @pSeqRef, NULL);

                IF @pAdvApplied > 0
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @pBranchCode,
                            @pInvoiceNo, @pInvoiceDate, @pAdvApplied, 'ADVANCEAPPLIED',
                            @parmpaymethod, @parmvouchertype, '', @parmglcode, @parmglcode,
                            @pSeqRef, NULL);

                UPDATE APACCOUNTS
                SET Balance = @pCurBalance - @pGross,
                    PayStatus = CASE WHEN (@pCurBalance - @pGross) <= 0 THEN 'FULLYPAID' ELSE 'PARTIAL' END
                WHERE SupplierID = @parmsupplierid AND InvoiceNo = @pInvoiceNo AND SequenceNo = @pSeqRef;

                SET @row += 1;
            END;

            -- CHANGED 2026-09-24: skip the OC when no cash actually left the
            -- bank (every line settled entirely by Advance Applied / EWT /
            -- Discount) instead of posting a 0.00 outstanding cheque.
            IF @TotalNetCashForRecon <> 0
            BEGIN
                DECLARE @Remarks VARCHAR(500);
                SET @Remarks = 'Auto-OC | Ref: ' + ISNULL(@parmrefno, '');

                EXEC sp_Payment_PostBankReconEntry
                     @ItemType      = 'OC',
                     @BranchCode    = @ocBranch,
                     @AccountCode   = @parmglcode,
                     @PeriodEnd     = @ocPeriodEnd,
                     @ReferenceNo   = @parmvoucherid,
                     @ItemDate      = @parmcheckdate,
                     @Payee         = @parmsuppliername,
                     @Amount        = @TotalNetCashForRecon,
                     @Remarks       = @Remarks,
                     @SourceModule  = 'AP-PAYMENT',
                     @SourceRef     = @parmrefno,
                     @CreatedBy     = @parmpreparedby;
            END

        END

        -- ============================================================
        -- EXPENSE - SINGLE and BATCH
        -- 2026-09-24c: SINGLE accepts OverPay / OverPayExpense /
        -- AdvanceApplied (same rules as PURCHASE); BATCH rejects them.
        -- ============================================================
        ELSE
        BEGIN
            -- GL accounts for the extras come from the same mapping rows the
            -- PURCHASE mnemonics use, so both modes always hit the same
            -- accounts (101030208 / 60339 today) - never hardcoded here.
            DECLARE @xOverPayAcct VARCHAR(50), @xOverPayExpAcct VARCHAR(50), @xAdvanceAcct VARCHAR(50);
            SELECT @xOverPayAcct    = AccountCode FROM JournalEntryMapping WHERE Mnemonic = 'PV-AP-OVERPAY'    AND AmountType = 'OVERPAY'        AND IsActive = 1;
            SELECT @xOverPayExpAcct = AccountCode FROM JournalEntryMapping WHERE Mnemonic = 'PV-AP-OVERPAYEXP' AND AmountType = 'OVERPAYEXPENSE' AND IsActive = 1;
            SELECT @xAdvanceAcct    = AccountCode FROM JournalEntryMapping WHERE Mnemonic = 'PV-AP-ADVAPPLIED' AND AmountType = 'ADVANCEAPPLIED' AND IsActive = 1;

            SET @row = 1;
            WHILE @row <= @maxrow
            BEGIN
                DECLARE @eInvoiceNo VARCHAR(150), @eInvoiceDate DATE, @eBatchRef BIGINT,
                        @eDesc VARCHAR(300), @eDiscRemain DECIMAL(18,2), @eOffsetRemain DECIMAL(18,2),
                        @eVariance DECIMAL(18,2), @eDiscAcct VARCHAR(20), @eTotalAmt DECIMAL(18,2),
                        @ePostingMode VARCHAR(10), @ePayableAcct VARCHAR(20), @eCurBalance DECIMAL(18,2),
                        @eNewBalance DECIMAL(18,2), @eGross DECIMAL(18,2), @eBranch VARCHAR(5),
                        @eParticulars VARCHAR(7000), @eTransID INT;

                SELECT
                    @eInvoiceNo = InvoiceNo, @eInvoiceDate = InvoiceDate, @eBatchRef = BatchReferenceID,
                    @eTotalAmt = ActualCost, @eDesc = Description,
                    @eDiscRemain = DiscountAmount, @eOffsetRemain = OffsetAmount,
                    @eVariance = Variance, @eDiscAcct = DiscountAccountCode
                FROM #Lines WHERE RowNum = @row;

                SELECT @ePostingMode = ISNULL(PostingMode, 'BATCH'), @ePayableAcct = PayableAccountCode
                FROM ExpenseSummary
                WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo;

                SET @eCurBalance = NULL;
                SELECT @eCurBalance = ISNULL(Balance, ISNULL(Amount, 0))
                FROM ExpenseSummary WITH (UPDLOCK, ROWLOCK)
                WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo;

                IF @eCurBalance IS NULL
                BEGIN
                    DECLARE @ENotFoundMsg VARCHAR(400) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ' was not found in ExpenseSummary (BatchReferenceID ' + CAST(ISNULL(@eBatchRef,0) AS VARCHAR(30)) + ').';
                    THROW 60508, @ENotFoundMsg, 1;
                END

                IF @ePostingMode = 'SINGLE'
                BEGIN
                    IF @ePayableAcct IS NULL
                        THROW 56002, 'SINGLE-mode invoice has no PayableAccountCode recorded.', 1;

                    DECLARE @sNetCash DECIMAL(18,2), @sEWT DECIMAL(18,2), @sDisc DECIMAL(18,2),
                            @sOffset DECIMAL(18,2), @sFXLoss DECIMAL(18,2), @sFXGain DECIMAL(18,2),
                            -- NEW 2026-09-24c
                            @sOverPay DECIMAL(18,2), @sOverPayExp DECIMAL(18,2), @sAdvApplied DECIMAL(18,2);

                    -- CHANGED 2026-09-24c: Gross (what settles the invoice) =
                    -- cash + EWT + Discount + Offset + AdvanceApplied
                    -- - OverPay - OverPayExpense, same as PURCHASE's @pGross.
                    -- All three extras are 0 on a plain line -> unchanged.
                    SELECT
                        @eGross   = AmountPaid + ISNULL(EWTAmount,0) + ISNULL(DiscountAmount,0) + ISNULL(OffsetAmount,0)
                                  + AdvanceApplied - OverPay - OverPayExpense,
                        @sNetCash = AmountPaid,
                        @sEWT     = ISNULL(EWTAmount,0),
                        @sDisc    = ISNULL(DiscountAmount,0),
                        @sOffset  = ISNULL(OffsetAmount,0),
                        @sOverPay    = OverPay,
                        @sOverPayExp = OverPayExpense,
                        @sAdvApplied = AdvanceApplied
                    FROM #Lines WHERE RowNum = @row;

                    IF ROUND(@eGross - @eCurBalance, 2) > 0
                    BEGIN
                        DECLARE @EOverpayMsgS VARCHAR(500) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': the amount being settled (' + CAST(@eGross AS VARCHAR(30))
                            + ') exceeds its Balance (' + CAST(@eCurBalance AS VARCHAR(30)) + '). Lower Amount Paid, or put the excess in the OverPay / OverPay (Expense) column.';
                        THROW 60503, @EOverpayMsgS, 1;
                    END

                    -- NEW 2026-09-24c: same rule as PURCHASE (THROW 60515) -
                    -- an overpayment only exists once the invoice is fully settled.
                    IF (@sOverPay > 0 OR @sOverPayExp > 0) AND ROUND(@eCurBalance - @eGross, 2) <> 0
                    BEGIN
                        DECLARE @EOverNotFullMsg VARCHAR(500) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': OverPay is only allowed when the invoice is fully settled (Balance ' + CAST(@eCurBalance AS VARCHAR(30))
                            + ', settled ' + CAST(@eGross AS VARCHAR(30)) + ').';
                        THROW 60515, @EOverNotFullMsg, 1;
                    END

                    IF (@sOverPay > 0 AND @xOverPayAcct IS NULL)
                       OR (@sOverPayExp > 0 AND @xOverPayExpAcct IS NULL)
                       OR (@sAdvApplied > 0 AND @xAdvanceAcct IS NULL)
                        THROW 60518, 'JournalEntryMapping for supplier overpayment/advance (PV-AP-OVERPAY / PV-AP-OVERPAYEXP / PV-AP-ADVAPPLIED) is missing or inactive.', 1;

                    SET @sFXLoss = 0;
                    SET @sFXGain = 0;
                    SET @TotalNetCashForRecon += @sNetCash;

                    -- NEW 2026-09-24c: pre-validate the settlement ticket balances
                    -- (sp_Payment_PostSettlementTicket itself never checks DR = CR).
                    -- DR payable Gross + DR advances OverPay + DR expense OverPayExp
                    --   = CR bank cash + EWT + Discount + Offset + CR advances AdvApplied
                    IF @sOverPay > 0 OR @sOverPayExp > 0 OR @sAdvApplied > 0
                    BEGIN
                        DECLARE @sDr DECIMAL(18,2) = @eGross + @sOverPay + @sOverPayExp + @sFXLoss,
                                @sCr DECIMAL(18,2) = @sNetCash + @sEWT + @sDisc + @sOffset + @sAdvApplied + @sFXGain;
                        IF @sDr <> @sCr
                        BEGIN
                            DECLARE @SImbalMsg VARCHAR(400) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': SINGLE-PAY ticket would not balance (Debit '
                                + CAST(@sDr AS VARCHAR(30)) + ', Credit ' + CAST(@sCr AS VARCHAR(30)) + ').';
                            THROW 60518, @SImbalMsg, 1;
                        END
                    END

                    SET @eNewBalance = ROUND(CASE WHEN @eCurBalance - @eGross < 0 THEN 0 ELSE @eCurBalance - @eGross END, 2);

                    -- CHANGED 2026-09-24c: AmountPaid gets the part of Gross that
                    -- isn't a withholding (cash applied + advance applied, net of
                    -- any excess), so AmountPaid + EWT/Discount/Offset withheld
                    -- still equals what was settled. Identical to the old
                    -- "+ @sNetCash" when all three extras are 0.
                    UPDATE ExpenseSummary
                    SET Balance = @eNewBalance,
                        AmountPaid = ISNULL(AmountPaid,0) + (@sNetCash + @sAdvApplied - @sOverPay - @sOverPayExp),
                        EWTWithheld = ISNULL(EWTWithheld,0) + @sEWT,
                        DiscountWithheld = ISNULL(DiscountWithheld,0) + @sDisc,
                        OffsetWithheld = ISNULL(OffsetWithheld,0) + @sOffset,
                        Status = CASE WHEN @eNewBalance <= 0 THEN 'FULLYPAID' ELSE 'PARTIAL' END,
                        UpdatedBy = @parmpreparedby, DateTimeUpdated = GETDATE()
                    WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo;

                    IF @eNewBalance <= 0
                        UPDATE ExpenseMaster SET Balance = 0, AmountPaid = Amount, Status = 'FULLYPAID'
                        WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo;

                    SELECT TOP 1 @eBranch = BranchCode FROM ExpenseMaster
                    WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo;

                    SET @eParticulars = 'EXPENSE PAYMENT (SINGLE) | Supplier: '+@parmsupplierid
                        +' | Ref: '+@parmrefno+' | '+LEFT(ISNULL(@eDesc,''),500)
                        +CASE WHEN LEN(ISNULL(@parmcheckremarks,''))>0 THEN ' | '+LEFT(@parmcheckremarks,200) ELSE '' END;

                    EXEC sp_Payment_PostSettlementTicket
                        @TicketDate=@parmcheckdate, @BranchCode=@eBranch,
                        @ReferenceKey=@parmvoucherid, @ReferenceNumber=@parmrefno,
                        @Owner=@parmsuppliername, @Particulars=@eParticulars,
                        @PreparedBy=@parmpreparedby, @Mnemonic='SINGLE-PAY',
                        @PayableAccountCode=@ePayableAcct, @GrossPayable=@eGross,
                        @BankAccountCode=@parmglcode, @NetCash=@sNetCash,
                        @EWTAmount=@sEWT, @DiscountAmount=@sDisc, @DiscountAccountCode=@eDiscAcct,
                        @OffsetAmount=@sOffset, @FXLoss=@sFXLoss, @FXGain=@sFXGain,
                        -- NEW 2026-09-24c (all default 0 in the helper; BATCH never passes them)
                        @OverPay=@sOverPay, @OverPayAccountCode=@xOverPayAcct,
                        @OverPayExpense=@sOverPayExp, @OverPayExpenseAccountCode=@xOverPayExpAcct,
                        @AdvanceApplied=@sAdvApplied, @AdvanceAccountCode=@xAdvanceAcct,
                        @TicketNumber=@TicketNumber OUTPUT;

                    -- 'EXPENSE PAYMENT' stays = Gross (what settled the invoice);
                    -- sp_CancelledChequesCS restores Balance from these rows only.
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @eBranch,
                            @eInvoiceNo, @eInvoiceDate, @eGross, 'EXPENSE PAYMENT',
                            @parmpaymethod, @parmvouchertype, @TicketNumber,
                            @ePayableAcct, @parmglcode, CAST(@eBatchRef AS VARCHAR(50)), @eBatchRef);

                    -- NEW 2026-09-24c: extras rows feed the shared supplier credit
                    -- pool (sp_GetSupplierAvailableCredit / V2 / reversal guard),
                    -- which counts PURCHASE and EXPENSE rows alike.
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    -- Debit/Credit GL codes mirror the ticket legs (sp-reviewer 24c):
                    --   OVERPAY        DR advances   / CR bank
                    --   OVERPAYEXPENSE DR expense    / CR bank
                    --   ADVANCEAPPLIED DR payable    / CR advances
                    SELECT @parmvoucherid, @parmsupplierid, @parmrefno, @eBranch,
                           @eInvoiceNo, @eInvoiceDate, x.Amount, x.PaymentType,
                           @parmpaymethod, @parmvouchertype, @TicketNumber,
                           x.DebitGL, x.CreditGL, CAST(@eBatchRef AS VARCHAR(50)), @eBatchRef
                    FROM (VALUES ('OVERPAY',        @sOverPay,    @xOverPayAcct,    @parmglcode),
                                 ('OVERPAYEXPENSE', @sOverPayExp, @xOverPayExpAcct, @parmglcode),
                                 ('ADVANCEAPPLIED', @sAdvApplied, @ePayableAcct,    @xAdvanceAcct)) x (PaymentType, Amount, DebitGL, CreditGL)
                    WHERE x.Amount > 0;

                    SET @eTransID = dbo.func_getLastID(@SupplierKey);
                    INSERT INTO [dbo].[SupplierLedger]
                        (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate,
                         Description, TransCode, TransactionDate, ReferenceNumber,
                         ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit,
                         EndingBalance, TransactedBy, ApprovedBy, TotalAmount,
                         PaymentType, ErrorCorrectTag, TicketReference, BatchReferenceID)
                    VALUES (@eTransID, @SupplierKey, @parmsupplierid, @parmcheckdate,
                            LEFT(ISNULL(@parmcheckremarks,'EXPENSE PAYMENT'),490),
                            'SNGLE-PAY', @parmcheckdate, @parmrefno,
                            CAST(@eBatchRef AS VARCHAR(40))+'-'+@eBranch,
                            @eInvoiceNo, 0, @eGross, 0, @eGross, @parmpreparedby, '*', @eGross,
                            CASE WHEN @eNewBalance<=0 THEN 'FULLYPAID' ELSE 'PARTIAL' END,
                            0, @TicketNumber, @eBatchRef);

                    SET @row += 1;
                    CONTINUE;
                END;

                -- -- BATCH mode --------------------------------------
                -- 2026-09-24c: extras are not supported on BATCH (multi-branch
                -- split) invoices - moved here from the top of the proc.
                IF EXISTS (SELECT 1 FROM #Lines WHERE RowNum = @row
                             AND (OverPay > 0 OR OverPayExpense > 0 OR AdvanceApplied > 0))
                BEGIN
                    DECLARE @EBatchExtrasMsg VARCHAR(400) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ' is a BATCH (multi-branch) expense - OverPay / Advance Applied is supported only for PURCHASE and SINGLE expense invoices.';
                    THROW 60509, @EBatchExtrasMsg, 1;
                END

                DECLARE @eEWTAlreadyPosted DECIMAL(18,2), @eEWTToWithhold DECIMAL(18,2),
                        @eEWTFromTVP DECIMAL(18,2), @eEWTRemain DECIMAL(18,2), @eNetLiability DECIMAL(18,2);

                SELECT
                    @eEWTAlreadyPosted = ISNULL(SUM(CASE WHEN IsEWTPostedAtAccrual = 1 THEN EWTAmount ELSE 0 END), 0),
                    @eEWTToWithhold    = ISNULL(SUM(CASE WHEN IsEWTPostedAtAccrual = 0 THEN EWTAmount ELSE 0 END), 0)
                FROM ExpenseMaster
                WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo;

                SELECT @eEWTFromTVP = ISNULL(EWTAmount, 0) FROM #Lines WHERE RowNum = @row;

                SET @eEWTRemain = CASE WHEN @eEWTFromTVP > 0 THEN @eEWTFromTVP ELSE @eEWTToWithhold END;

                SET @eNetLiability = @eTotalAmt - @eEWTAlreadyPosted;

                SELECT @eGross = AmountPaid + @eEWTRemain + DiscountAmount + OffsetAmount - Variance
                FROM #Lines WHERE RowNum = @row;

                IF ROUND(@eGross - @eCurBalance, 2) > 0
                BEGIN
                    DECLARE @EOverpayMsgB VARCHAR(500) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': the amount being settled (' + CAST(@eGross AS VARCHAR(30))
                        + ') exceeds its Balance (' + CAST(@eCurBalance AS VARCHAR(30)) + '). Lower Amount Paid (or the EWT/Discount/Offset lines) so it does not exceed Balance.';
                    THROW 60504, @EOverpayMsgB, 1;
                END

                SET @eNewBalance = ROUND(CASE WHEN @eCurBalance - @eGross < 0 THEN 0 ELSE @eCurBalance - @eGross END, 2);

                UPDATE ExpenseSummary SET
                    Balance = @eNewBalance,
                    AmountPaid = ISNULL(AmountPaid,0) + (@eGross - @eEWTRemain - @eDiscRemain - @eOffsetRemain),
                    EWTWithheld = ISNULL(EWTWithheld,0) + @eEWTRemain,
                    DiscountWithheld = ISNULL(DiscountWithheld,0) + @eDiscRemain,
                    OffsetWithheld = ISNULL(OffsetWithheld,0) + @eOffsetRemain,
                    Status = CASE WHEN @eNewBalance<=0 THEN 'FULLYPAID' ELSE 'PARTIAL' END,
                    UpdatedBy = @parmpreparedby, DateTimeUpdated = GETDATE()
                WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo;

                IF OBJECT_ID('tempdb..#BranchTotals') IS NOT NULL DROP TABLE #BranchTotals;

                SELECT
                    ROW_NUMBER() OVER (ORDER BY BranchCode) AS RowNum, BranchCode,
                    SUM(Amount) AS BranchTotalAmt,
                    SUM(Amount) - SUM(CASE WHEN IsEWTPostedAtAccrual = 1 THEN ISNULL(EWTAmount,0) ELSE 0 END) AS BranchNetLiability,
                    ROUND(((SUM(Amount) - SUM(CASE WHEN IsEWTPostedAtAccrual = 1 THEN ISNULL(EWTAmount,0) ELSE 0 END)) / NULLIF(@eNetLiability, 0)) * @eEWTRemain, 2) AS BranchEWT,
                    ROUND(((SUM(Amount) - SUM(CASE WHEN IsEWTPostedAtAccrual = 1 THEN ISNULL(EWTAmount,0) ELSE 0 END)) / NULLIF(@eNetLiability, 0)) * @eDiscRemain, 2) AS BranchDisc,
                    ROUND(((SUM(Amount) - SUM(CASE WHEN IsEWTPostedAtAccrual = 1 THEN ISNULL(EWTAmount,0) ELSE 0 END)) / NULLIF(@eNetLiability, 0)) * @eOffsetRemain, 2) AS BranchOffset
                INTO #BranchTotals
                FROM ExpenseMaster
                WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo
                GROUP BY BranchCode;

                DECLARE @brrow INT = 1, @brmaxrow INT;
                SELECT @brmaxrow = COUNT(*) FROM #BranchTotals;

                DECLARE @ewtRunning DECIMAL(18,2)=0, @discRunning DECIMAL(18,2)=0,
                        @offRunning DECIMAL(18,2)=0, @varRunning DECIMAL(18,2)=0;

                WHILE @brrow <= @brmaxrow
                BEGIN
                    DECLARE @brBranch VARCHAR(5), @brNetLiability DECIMAL(18,2), @brEWT DECIMAL(18,2),
                            @brDisc DECIMAL(18,2), @brOffset DECIMAL(18,2), @brVariance DECIMAL(18,2),
                            @brFXLoss DECIMAL(18,2), @brFXGain DECIMAL(18,2), @brGross DECIMAL(18,2),
                            @brNetCash DECIMAL(18,2), @brMnemonic VARCHAR(50), @allDescNames VARCHAR(2000);

                    SELECT @brBranch=BranchCode, @brNetLiability=BranchNetLiability,
                           @brEWT=BranchEWT, @brDisc=BranchDisc, @brOffset=BranchOffset
                    FROM #BranchTotals WHERE RowNum = @brrow;

                    IF @brrow = @brmaxrow
                    BEGIN
                        SET @brEWT = @eEWTRemain - @ewtRunning;
                        SET @brDisc = @eDiscRemain - @discRunning;
                        SET @brOffset = @eOffsetRemain - @offRunning;
                    END
                    ELSE
                    BEGIN
                        SET @ewtRunning += @brEWT; SET @discRunning += @brDisc;
                        SET @offRunning += @brOffset;
                    END

                    SET @brFXLoss = 0;
                    SET @brFXGain = 0;

                    SET @brGross = ROUND((@brNetLiability / NULLIF(@eNetLiability, 0)) * @eGross, 2);
                    IF @brrow = @brmaxrow
                        SET @brGross = @eGross - ISNULL((SELECT SUM(BranchNetLiability/@eNetLiability * @eGross) FROM #BranchTotals WHERE RowNum < @brmaxrow), 0);

                    SET @brNetCash = ROUND(CASE WHEN @brGross - @brEWT - @brDisc - @brOffset + @brFXLoss - @brFXGain < 0 THEN 0
                        ELSE @brGross - @brEWT - @brDisc - @brOffset + @brFXLoss - @brFXGain END, 2);
                    SET @TotalNetCashForRecon += @brNetCash;

                    SET @brMnemonic = CASE WHEN @brEWT > 0 THEN 'EXP-ACCRUAL-PAY-EWT' ELSE 'EXP-ACCRUAL-PAY' END;

                    IF @eNewBalance <= 0
                        UPDATE ExpenseMaster SET Balance=0, AmountPaid=Amount, Status='FULLYPAID'
                        WHERE SupplierID=@SupplierKey AND BatchReferenceID=@eBatchRef AND InvoiceNo=@eInvoiceNo AND BranchCode=@brBranch;
                    ELSE
                        UPDATE ExpenseMaster SET Status='PARTIAL'
                        WHERE SupplierID=@SupplierKey AND BatchReferenceID=@eBatchRef AND InvoiceNo=@eInvoiceNo
                          AND BranchCode=@brBranch AND Status NOT IN ('FULLYPAID','VOID','CANCELLED');

                    SELECT @allDescNames = STUFF((
                        SELECT ' | ' + ExpenseName FROM (
                            SELECT DISTINCT ExpenseName FROM ExpenseMaster
                            WHERE SupplierID=@SupplierKey AND BatchReferenceID=@eBatchRef AND InvoiceNo=@eInvoiceNo AND BranchCode=@brBranch
                        ) d ORDER BY ExpenseName FOR XML PATH(''), TYPE
                    ).value('.','VARCHAR(MAX)'), 1, 3, '');

                    SET @eParticulars = 'EXPENSE PAYMENT | Supplier: '+@parmsupplierid+' | Ref: '+@parmrefno+' | '+LEFT(ISNULL(@allDescNames,''),500)
                        +CASE WHEN LEN(ISNULL(@parmcheckremarks,''))>0 THEN ' | '+LEFT(@parmcheckremarks,200) ELSE '' END;

                    EXEC sp_Payment_PostSettlementTicket
                        @TicketDate=@parmcheckdate, @BranchCode=@brBranch,
                        @ReferenceKey=@parmvoucherid, @ReferenceNumber=@parmrefno,
                        @Owner=@parmsuppliername, @Particulars=@eParticulars,
                        @PreparedBy=@parmpreparedby, @Mnemonic=@brMnemonic,
                        @PayableAccountCode='20103', @GrossPayable=@brGross,
                        @BankAccountCode=@parmglcode, @NetCash=@brNetCash,
                        @EWTAmount=@brEWT, @DiscountAmount=@brDisc, @DiscountAccountCode=@eDiscAcct,
                        @OffsetAmount=@brOffset, @FXLoss=@brFXLoss, @FXGain=@brFXGain,
                        @TicketNumber=@TicketNumber OUTPUT;

                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @brBranch,
                            @eInvoiceNo, @eInvoiceDate, @brGross, 'EXPENSE PAYMENT',
                            @parmpaymethod, @parmvouchertype, @TicketNumber,
                            '20103', @parmglcode, CAST(@eBatchRef AS VARCHAR(50)), @eBatchRef);

                    SET @eTransID = dbo.func_getLastID(@SupplierKey);
                    INSERT INTO [dbo].[SupplierLedger]
                        (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate,
                         Description, TransCode, TransactionDate, ReferenceNumber,
                         ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit,
                         EndingBalance, TransactedBy, ApprovedBy, TotalAmount,
                         PaymentType, ErrorCorrectTag, TicketReference, BatchReferenceID)
                    VALUES (@eTransID, @SupplierKey, @parmsupplierid, @parmcheckdate,
                            LEFT(ISNULL(@parmcheckremarks,'EXPENSE PAYMENT'),490),
                            @brMnemonic, @parmcheckdate, @parmrefno,
                            CAST(@eBatchRef AS VARCHAR(40))+'-'+@brBranch,
                            @eInvoiceNo, 0, @brGross, 0, @brGross, @parmpreparedby, '*', @brGross, 'PARTIAL',
                            0, @TicketNumber, @eBatchRef);

                    SET @brrow += 1;
                END;

                DROP TABLE #BranchTotals;
                SET @row += 1;
            END;

            declare @reconbranch varchar(5)
            set @reconbranch=ISNULL(@ocBranch,'888');
            DECLARE @Remarks2 VARCHAR(500);
            SET @Remarks2 = 'Auto-OC | Ref: ' + ISNULL(@parmrefno, '');
            EXEC sp_Payment_PostBankReconEntry
                @ItemType='OC', @BranchCode=@reconbranch, @AccountCode=@parmglcode,
                @PeriodEnd=@ocPeriodEnd, @ReferenceNo=@parmvoucherid, @ItemDate=@parmcheckdate,
                @Payee=@parmsuppliername, @Amount=@TotalNetCashForRecon,
                @Remarks=@Remarks2, @SourceModule='AP-PAYMENT',
                @SourceRef=@parmrefno, @CreatedBy=@parmpreparedby;
        END

        DECLARE @CheckOrControlNo VARCHAR(50);

        SET @CheckOrControlNo =
            CASE
                WHEN @parmvouchertype = 'CHECK'
                    THEN @parmcheckno
                ELSE @parmcontrolno
            END;

            EXEC sp_Payment_CreateVoucherHeader
                @VoucherType       = @parmvouchertype,
                @VoucherID         = @parmvoucherid,
                @SupplierID        = @parmsupplierid,
                @ReferenceNumber   = @parmrefno,
                @PaidTo            = @parmsuppliername,
                @CheckOrControlNo  = @CheckOrControlNo,
                @CheckCoding       = @parmcheckcoding,
                @VoucherDate       = @parmcheckdate,
                @Particulars       = @parmcheckremarks,
                @Amount            = @TotalNetCashForRecon,
                @PreparedBy        = @parmpreparedby,
                @ForLiquidation    = @parmforliquidation,
                @GLCode            = @parmglcode;
        DROP TABLE #Lines;
        COMMIT TRANSACTION PaySupplierV2;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION PaySupplierV2;
        THROW;
    END CATCH
END

GO

-- ----------------------------------------------------------------
-- 3. sp_CancelledChequesCS
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_CancelledChequesCS', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_CancelledChequesCS', 'sp_CancelledChequesCS_OLD_09242026235900';
GO


CREATE PROCEDURE [dbo].[sp_CancelledChequesCS]
(
    @parmsupplierid   VARCHAR(30),
    @parmreferenceno  VARCHAR(20),
    @parmvoucherid    VARCHAR(10),
    @parmvouchertype  VARCHAR(20),  -- 'PURCHASE' or 'EXPENSE'
    @parmreason       VARCHAR(300),
    @parmuser         VARCHAR(50),
    @parmglcode       VARCHAR(30)  = NULL,
    @parmbranch       VARCHAR(5)   = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        IF @parmglcode IS NULL
            SELECT TOP(1) @parmglcode = PaymentApprovedBy
            FROM CheckVoucher
            WHERE VoucherID = @parmvoucherid
              AND SupplierID = @parmsupplierid
              AND ReferenceNumber = @parmreferenceno;

        IF EXISTS (
            SELECT 1 FROM CheckVoucher
            WHERE VoucherID = @parmvoucherid
              AND SupplierID = @parmsupplierid
              AND ReferenceNumber = @parmreferenceno
              AND isErrorCorrect = 1
        )
            THROW 50050, 'Voucher already reversed.', 1;

        -- NEW 2026-09-24: a voucher that created supplier advance credit
        -- (OVERPAY) can only be reversed while that credit is still unused --
        -- otherwise 101030208 would go negative with the later voucher's
        -- AdvanceApplied still standing. Same per-supplier applock as
        -- sp_AddPaymentSupplierCompound_V2's AdvanceApplied check, so the two
        -- can't interleave. Pool computed excluding this voucher (as if
        -- already reversed) and excluding every already-reversed voucher.
        IF EXISTS (SELECT 1 FROM APPaymentDetails
                   WHERE VoucherID = @parmvoucherid AND SupplierID = @parmsupplierid
                     AND PaymentType = 'OVERPAY')
        BEGIN
            DECLARE @LockResult INT, @LockResource NVARCHAR(255) = N'APCREDIT:' + @parmsupplierid;
            EXEC @LockResult = sp_getapplock
                @Resource    = @LockResource,
                @LockMode    = 'Exclusive',
                @LockOwner   = 'Transaction',
                @LockTimeout = 10000;

            IF @LockResult < 0
                THROW 60520, 'Could not acquire a lock for this supplier''s advance credit (another payment or reversal for the same supplier is in progress). Please try again.', 1;

            DECLARE @CreditAfterReversal DECIMAL(18,2);
            SELECT @CreditAfterReversal =
                ISNULL(SUM(CASE WHEN d.PaymentType = 'OVERPAY'        THEN d.Amount ELSE 0 END), 0)
              - ISNULL(SUM(CASE WHEN d.PaymentType = 'ADVANCEAPPLIED' THEN d.Amount ELSE 0 END), 0)
            FROM APPaymentDetails d
            WHERE d.SupplierID = @parmsupplierid
              AND d.PaymentType IN ('OVERPAY', 'ADVANCEAPPLIED')
              AND d.VoucherID <> @parmvoucherid
              AND NOT EXISTS (SELECT 1 FROM PaymentReversalAudit r
                              WHERE r.VoucherID = d.VoucherID AND r.SupplierID = d.SupplierID);

            IF ISNULL(@CreditAfterReversal, 0) < 0
            BEGIN
                DECLARE @UsedMsg VARCHAR(500) = 'This voucher''s overpayment credit has already been applied to a later payment (reversing it would leave supplier advance credit at '
                    + CAST(@CreditAfterReversal AS VARCHAR(30)) + '). Reverse the later voucher(s) that used Advance Applied first.';
                THROW 60519, @UsedMsg, 1;
            END
        END

        UPDATE CheckVoucher
        SET isErrorCorrect = 1,
            CancelledBy    = @parmuser,
            CancelledDate  = GETDATE(),
            CancelReason   = @parmreason
        WHERE VoucherID = @parmvoucherid
          AND SupplierID = @parmsupplierid
          AND ReferenceNumber = @parmreferenceno;

        INSERT INTO PaymentReversalAudit
            (VoucherID, SupplierID, VoucherType, ReferenceNumber, CancelReason, CancelledBy)
        VALUES
            (@parmvoucherid, @parmsupplierid, @parmvouchertype, @parmreferenceno, @parmreason, @parmuser);

        INSERT INTO CheckVoucherCancelled
            (VoucherID, SupplierKey, ReferenceNumber, PaidTo, CheckNo, CheckDate,
             Particulars, Amount, ExecuteBy, VoucherType, DateUpdate, DateAdded)
        SELECT
            VoucherID, SupplierID, @parmreferenceno, PaidTo, CheckNo, CheckDate,
            Particulars, Amount, @parmuser, VoucherType, GETDATE(), GETDATE()
        FROM CheckVoucher
        WHERE VoucherID = @parmvoucherid
          AND SupplierID = @parmsupplierid
          AND ReferenceNumber = @parmreferenceno;

        -- ------------------------------------------------------------
        -- PURCHASE FLOW
        -- ------------------------------------------------------------
        IF @parmvouchertype = 'PURCHASE'
        BEGIN
            IF OBJECT_ID('tempdb..#APRev') IS NOT NULL DROP TABLE #APRev;

            SELECT
                SequenceReferenceNumber,
                SUM(CASE WHEN PaymentType = 'INVOICE PAYMENT'  THEN Amount ELSE 0 END) AS Paid,
                SUM(CASE WHEN PaymentType = 'EWT'              THEN Amount ELSE 0 END) AS EWT,
                SUM(CASE WHEN PaymentType = 'DISCOUNT'         THEN Amount ELSE 0 END) AS Discount,
                SUM(CASE WHEN PaymentType = 'RETURNALLOWANCES' THEN Amount ELSE 0 END) AS Offset,
                -- Signed FX Variance - SUBTRACTED when restoring Balance,
                -- since posting subtracted it from Gross.
                SUM(CASE WHEN PaymentType = 'VARIANCE'         THEN Amount ELSE 0 END) AS Variance,
                -- NEW 2026-09-24: posting Gross = ... + AdvanceApplied
                -- - OverPay - OverPayExpense, so restore with the same signs.
                SUM(CASE WHEN PaymentType = 'OVERPAY'          THEN Amount ELSE 0 END) AS OverPay,
                SUM(CASE WHEN PaymentType = 'OVERPAYEXPENSE'   THEN Amount ELSE 0 END) AS OverPayExpense,
                SUM(CASE WHEN PaymentType = 'ADVANCEAPPLIED'   THEN Amount ELSE 0 END) AS AdvanceApplied
            INTO #APRev
            FROM APPaymentDetails
            WHERE VoucherID = @parmvoucherid
              AND SupplierID = @parmsupplierid
              AND PaymentMethod = 'PURCHASE'
            GROUP BY SequenceReferenceNumber;

            UPDATE A SET
                A.AmountPaid   = A.AmountPaid   - D.Paid,
                A.EWTAmount    = A.EWTAmount    - D.EWT,
                A.Discount     = A.Discount     - D.Discount,
                A.OffsetAmount = A.OffsetAmount - D.Offset,
                A.Balance      = A.Balance + (D.Paid + D.EWT + D.Discount + D.Offset - D.Variance
                                              + D.AdvanceApplied - D.OverPay - D.OverPayExpense),
                A.PayStatus    = CASE
                    WHEN A.Balance + (D.Paid + D.EWT + D.Discount + D.Offset - D.Variance
                                      + D.AdvanceApplied - D.OverPay - D.OverPayExpense) > 0
                    THEN 'UNPAID' ELSE 'FULLYPAID' END
            FROM APAccounts A
            JOIN #APRev D ON A.SequenceNo = D.SequenceReferenceNumber
               AND A.SupplierID = @parmsupplierid;

            IF EXISTS (
                SELECT 1 FROM APAccounts A JOIN #APRev D ON A.SequenceNo = D.SequenceReferenceNumber
                WHERE A.SupplierID = @parmsupplierid AND A.Balance > ISNULL(A.ActualCost,0) + 0.01
            )
            BEGIN
                THROW 60505, 'This reversal would leave an invoice''s Balance above its original ActualCost - aborting rather than corrupt the ledger. The invoice may have been overpaid before the overpayment guard existed; investigate before retrying.', 1;
            END

            DROP TABLE #APRev;
        END

        -- ------------------------------------------------------------
        -- EXPENSE FLOW (unchanged)
        -- ------------------------------------------------------------
        ELSE
        BEGIN
            IF OBJECT_ID('tempdb..#ExpRev') IS NOT NULL DROP TABLE #ExpRev;

            SELECT
                BatchReferenceID,
                BranchCode,
                InvoiceNo,
                SUM(Amount) AS TotalGross
            INTO #ExpRev
            FROM APPaymentDetails
            WHERE VoucherID        = @parmvoucherid
              AND SupplierID       = @parmsupplierid
              AND ReferenceNumber  = @parmreferenceno
              AND PaymentMethod    = 'EXPENSE'
              -- NEW 2026-09-24c: SINGLE-mode expense payments can now also write
              -- OVERPAY / OVERPAYEXPENSE / ADVANCEAPPLIED rows (supplier credit
              -- pool bookkeeping). Only 'EXPENSE PAYMENT' = the Gross that
              -- actually settled the invoice, so only it restores Balance.
              -- Every EXPENSE row written before this change was 'EXPENSE
              -- PAYMENT', so existing reversals behave exactly as before.
              AND PaymentType      = 'EXPENSE PAYMENT'
            GROUP BY BatchReferenceID, BranchCode, InvoiceNo;

            ;WITH InvoiceRev AS (
                SELECT BatchReferenceID, InvoiceNo, SUM(TotalGross) AS TotalGross
                FROM #ExpRev
                GROUP BY BatchReferenceID, InvoiceNo
            )
            UPDATE ES SET
                ES.Balance    = ES.Balance + R.TotalGross,
                ES.AmountPaid = CASE WHEN ES.AmountPaid - R.TotalGross < 0
                                     THEN 0 ELSE ES.AmountPaid - R.TotalGross END,
                ES.EWTWithheld = CASE
                    WHEN (ES.Balance + R.TotalGross) >= ISNULL(ES.Amount, 0)
                    THEN 0
                    ELSE CASE
                        WHEN ES.EWTWithheld
                             - ROUND(ISNULL(ES.EWTAmount,0)
                               * (R.TotalGross / NULLIF(ES.Amount,0)), 2) < 0
                        THEN 0
                        ELSE ES.EWTWithheld
                             - ROUND(ISNULL(ES.EWTAmount,0)
                               * (R.TotalGross / NULLIF(ES.Amount,0)), 2)
                    END
                END,
                ES.DiscountWithheld = CASE
                    WHEN (ES.Balance + R.TotalGross) >= ISNULL(ES.Amount, 0)
                    THEN 0
                    ELSE CASE
                        WHEN ES.DiscountWithheld
                             - ROUND(ISNULL(ES.DiscountAmount,0)
                               * (R.TotalGross / NULLIF(ES.Amount,0)), 2) < 0
                        THEN 0
                        ELSE ES.DiscountWithheld
                             - ROUND(ISNULL(ES.DiscountAmount,0)
                               * (R.TotalGross / NULLIF(ES.Amount,0)), 2)
                    END
                END,
                ES.OffsetWithheld = CASE
                    WHEN (ES.Balance + R.TotalGross) >= ISNULL(ES.Amount, 0)
                    THEN 0
                    ELSE CASE
                        WHEN ES.OffsetWithheld
                             - ROUND(ISNULL(ES.OffsetAmount,0)
                               * (R.TotalGross / NULLIF(ES.Amount,0)), 2) < 0
                        THEN 0
                        ELSE ES.OffsetWithheld
                             - ROUND(ISNULL(ES.OffsetAmount,0)
                               * (R.TotalGross / NULLIF(ES.Amount,0)), 2)
                    END
                END,
                ES.Status          = CASE WHEN (ES.Balance + R.TotalGross) > 0
                                          THEN 'POSTED' ELSE 'PAID' END,
                ES.UpdatedBy       = @parmuser,
                ES.DateTimeUpdated = GETDATE()
            FROM ExpenseSummary ES
            JOIN InvoiceRev R
              ON ES.BatchReferenceID = R.BatchReferenceID
             AND ES.InvoiceNo        = R.InvoiceNo
             AND ES.SupplierID       = @parmsupplierid;

            IF EXISTS (
                SELECT 1
                FROM ExpenseSummary ES
                JOIN (SELECT BatchReferenceID, InvoiceNo FROM #ExpRev GROUP BY BatchReferenceID, InvoiceNo) R2
                  ON ES.BatchReferenceID = R2.BatchReferenceID AND ES.InvoiceNo = R2.InvoiceNo
                WHERE ES.SupplierID = @parmsupplierid
                  AND ES.Balance > ISNULL(ES.Amount,0) + 0.01
            )
            BEGIN
                THROW 60506, 'This reversal would leave an invoice''s Balance above its original Amount - aborting rather than corrupt the ledger. The invoice may have been overpaid before the overpayment guard existed; investigate before retrying.', 1;
            END

            UPDATE EM SET
                EM.AmountPaid = CASE
                    WHEN EM.AmountPaid - LineRev.LineGrossShare < 0
                    THEN 0
                    ELSE EM.AmountPaid - LineRev.LineGrossShare
                END,
                EM.EWTAmount = CASE
                    WHEN ISNULL(EM.EWTAmount,0) - LineRev.LineEWTShare < 0
                    THEN 0
                    ELSE ISNULL(EM.EWTAmount,0) - LineRev.LineEWTShare
                END,
                EM.DiscountAmount = CASE
                    WHEN ISNULL(EM.DiscountAmount,0) - LineRev.LineDiscShare < 0
                    THEN 0
                    ELSE ISNULL(EM.DiscountAmount,0) - LineRev.LineDiscShare
                END,
                EM.OffsetAmount = CASE
                    WHEN ISNULL(EM.OffsetAmount,0) - LineRev.LineOffsetShare < 0
                    THEN 0
                    ELSE ISNULL(EM.OffsetAmount,0) - LineRev.LineOffsetShare
                END,
                EM.Balance = EM.Amount
                    - (CASE WHEN EM.AmountPaid - LineRev.LineGrossShare < 0
                            THEN 0 ELSE EM.AmountPaid - LineRev.LineGrossShare END
                       + CASE WHEN ISNULL(EM.EWTAmount,0) - LineRev.LineEWTShare < 0
                              THEN 0 ELSE ISNULL(EM.EWTAmount,0) - LineRev.LineEWTShare END
                       + CASE WHEN ISNULL(EM.DiscountAmount,0) - LineRev.LineDiscShare < 0
                              THEN 0 ELSE ISNULL(EM.DiscountAmount,0) - LineRev.LineDiscShare END
                       + CASE WHEN ISNULL(EM.OffsetAmount,0) - LineRev.LineOffsetShare < 0
                              THEN 0 ELSE ISNULL(EM.OffsetAmount,0) - LineRev.LineOffsetShare END),
                EM.Status = CASE
                    WHEN EM.Amount - (
                        CASE WHEN EM.AmountPaid - LineRev.LineGrossShare < 0
                             THEN 0 ELSE EM.AmountPaid - LineRev.LineGrossShare END
                        + CASE WHEN ISNULL(EM.EWTAmount,0) - LineRev.LineEWTShare < 0
                               THEN 0 ELSE ISNULL(EM.EWTAmount,0) - LineRev.LineEWTShare END
                        + CASE WHEN ISNULL(EM.DiscountAmount,0) - LineRev.LineDiscShare < 0
                               THEN 0 ELSE ISNULL(EM.DiscountAmount,0) - LineRev.LineDiscShare END
                        + CASE WHEN ISNULL(EM.OffsetAmount,0) - LineRev.LineOffsetShare < 0
                               THEN 0 ELSE ISNULL(EM.OffsetAmount,0) - LineRev.LineOffsetShare END
                    ) > 0
                    THEN 'PARTIAL'
                    ELSE 'POSTED'
                END,
                EM.isErrorCorrect = 0
            FROM ExpenseMaster EM
            JOIN (
                SELECT
                    EM2.TRN_SEQ_NO,
                    EM2.BatchReferenceID,
                    EM2.BranchCode,
                    EM2.InvoiceNo,
                    R.TotalGross,
                    BranchTotal.SumAmt,
                    ROUND(EM2.Amount / NULLIF(BranchTotal.SumAmt,0) * R.TotalGross, 2)
                        AS LineGrossShare,
                    ROUND(
                        ISNULL(EM2.EWTAmount,0)
                        / NULLIF(BranchEWT.SumEWT,0)
                        * BranchEWT.SumEWT, 2
                    ) AS LineEWTShare_placeholder,
                    EM2.EWTAmount      AS LineEWTShare,
                    EM2.DiscountAmount AS LineDiscShare,
                    EM2.OffsetAmount   AS LineOffsetShare
                FROM ExpenseMaster EM2
                JOIN #ExpRev R
                  ON EM2.BatchReferenceID = R.BatchReferenceID
                 AND EM2.BranchCode       = R.BranchCode
                 AND EM2.InvoiceNo        = R.InvoiceNo
                CROSS APPLY (
                    SELECT SUM(Amount) AS SumAmt
                    FROM ExpenseMaster EM3
                    WHERE EM3.BatchReferenceID = EM2.BatchReferenceID
                      AND EM3.BranchCode       = EM2.BranchCode
                      AND EM3.InvoiceNo        = EM2.InvoiceNo
                ) BranchTotal
                CROSS APPLY (
                    SELECT SUM(ISNULL(EWTAmount,0)) AS SumEWT
                    FROM ExpenseMaster EM4
                    WHERE EM4.BatchReferenceID = EM2.BatchReferenceID
                      AND EM4.BranchCode       = EM2.BranchCode
                      AND EM4.InvoiceNo        = EM2.InvoiceNo
                ) BranchEWT
                WHERE EM2.SupplierID = @parmsupplierid
            ) LineRev
              ON EM.TRN_SEQ_NO       = LineRev.TRN_SEQ_NO
             AND EM.BatchReferenceID = LineRev.BatchReferenceID
             AND EM.BranchCode       = LineRev.BranchCode
             AND EM.InvoiceNo        = LineRev.InvoiceNo
            WHERE EM.SupplierID = @parmsupplierid;

            DROP TABLE #ExpRev;
        END;

        UPDATE TransactionPaymentAP
        SET ErrorCorrect = 1
        WHERE SupplierKey = @parmsupplierid
          AND ReferenceNumber = @parmreferenceno;

        UPDATE SupplierLedger
        SET ErrorCorrectTag = 1
        WHERE SupplierID = @parmsupplierid
          AND ReferenceNumber = @parmreferenceno
          AND ErrorCorrectTag = 0;

        DECLARE @baseTrnSeq INT = dbo.func_getLastID(@parmsupplierid);

        INSERT INTO SupplierLedger
            (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate, Description, TransCode,
             TransactionDate, ReferenceNumber, ReferenceKey, InvoiceNo,
             BeginningBalance, Debit, Credit, EndingBalance,
             TransactedBy, ApprovedBy, TotalAmount, PaymentType,
             ErrorCorrectTag, TicketReference, BatchReferenceID)
        SELECT
            @baseTrnSeq + ROW_NUMBER() OVER (ORDER BY L.TRN_SEQ_NO) - 1,
            L.SupplierKey, L.SupplierID,
            GETDATE(), '(Reversal) ' + L.Description, L.TransCode,
            GETDATE(), @parmreferenceno, L.ReferenceKey, L.InvoiceNo,
            0, 0, L.Debit, 0,
            @parmuser, '*', L.TotalAmount, 'REVERSAL', 1,
            L.TicketReference, L.BatchReferenceID
        FROM SupplierLedger L
        WHERE L.SupplierID = @parmsupplierid
          AND L.ReferenceNumber = @parmreferenceno
          AND L.ErrorCorrectTag = 1
          AND L.PaymentType <> 'REVERSAL';

        EXEC dbo.sp_ReverseTicketsAP @parmreferenceno, @parmvoucherid, @parmuser;

        IF @parmvoucherid IS NOT NULL
           AND LEN(LTRIM(RTRIM(ISNULL(@parmvoucherid, '')))) > 0
        BEGIN
            EXEC [dbo].[sp_BankRecon_VoidOC]
                @ReferenceNo = @parmreferenceno,
                @VoidedBy    = @parmuser;
        END

        COMMIT TRAN;

        SELECT
            'OK' AS Result,
            CONCAT(
                'Cheque cancelled and reversed. ',
                'CheckNo=', ISNULL(@parmvoucherid,''), ' ',
                'GLCode=',  ISNULL(@parmglcode,''),  ' ',
                'Branch=',  ISNULL(@parmbranch,''),  ' ',
                'User=',    ISNULL(@parmuser,''),    ' ',
                'Reason=',  ISNULL(@parmreason,'')
            ) AS Message;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH;
END;

GO
