/* ================================================================
   2026-09-25: Supplier Payment -- OverPay / OverPay (Expense) /
   Advance Applied for MULTI-BRANCH expense invoices (the V2 "BATCH"
   branch: PostingMode MULTI-MANUAL / BATCH / NULL -- anything not SINGLE).
   Extends 2026-09-24_SupplierPayment_OverpaymentCredit.sql (PURCHASE) and
   2026-09-24c_SupplierPayment_OverpaymentCredit_ExpenseSingle.sql (SINGLE).
   ================================================================
   Multi-branch expenses are tagged PostingMode = 'MULTI-MANUAL' (from
   ExpenseManualMultiBranchFrm), not 'BATCH' -- 16 on STAGING (14 open),
   3 on DEV. Both "has a head-office share" and "no head-office share"
   invoices exist in real data.

   DESIGN (confirmed with user: book on the HEAD OFFICE (888) ticket, not
   prorated across branches):
     * Invoice has an 888 share: the whole OverPay / OverPayExpense /
       AdvanceApplied rides on the 888 branch's settlement ticket:
         DR 20103 (888 share) + DR 101030208 OverPay (or 60339 OverPayExp)
         = CR bank + CR EWT/Disc/Offset (888 share) + CR 101030208 Advance.
       Other branch tickets are unchanged. Advance larger than 888's share
       of this payment -> THROW 60522 (its cash would go negative).
     * No 888 share:
         OverPay / OverPayExpense -> a separate 888 ticket 'EXP-OVERPAY-HO',
           DR 101030208 (or 60339) / CR bank, balanced on its own.
         AdvanceApplied -> THROW 60522 (no 888 payable to settle). Checked
           up front, before the credit-pool check, so users get 60522
           rather than a misleading 60514.
   Same rules as the other modes otherwise: overpay only when fully settled
   (60515), one overpaying invoice per voucher (60513), credit re-derived
   under the per-supplier applock (60514), DR = CR pre-check on the ticket
   that carries the extras (60518). The up-front BATCH rejection (60509)
   from 2026-09-24c is removed.

   Objects: sp_AddPaymentSupplierCompound_V2 only (body = live DEV
   definition + the BATCH-branch changes marked 2026-09-25).
   No change needed:
     sp_Payment_PostSettlementTicket (already takes the optional legs),
     sp_CancelledChequesCS (EXPENSE reversal restores Balance / branch
       lines from 'EXPENSE PAYMENT' rows only; reverses every ticket of the
       voucher incl. EXP-OVERPAY-HO via sp_ReverseTicketsAP; the credit-
       consumed guard is method-agnostic),
     sp_GetSupplierAvailableCredit (pool counts all modes).

   Deploy to CORECSERP_002_DEV first; mirror to CORECSJFC2026_STAGING only
   after confirming with the user (after the 24 and 24c scripts).
   ================================================================ */

IF OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_AddPaymentSupplierCompound_V2', 'sp_AddPaymentSupplierCompound_V2_OLD_09252026110000';
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
        -- 2026-09-25 (sp-reviewer): head-office branch code declared ONCE and reused by
        -- the up-front and in-loop multi-branch checks so they can't drift apart.
        DECLARE @HOBranch VARCHAR(5) = '888';
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

        -- CHANGED 2026-09-25: the up-front BATCH rejection (60509, added
        -- 2026-09-24c) is gone - multi-branch expense invoices (PostingMode
        -- MULTI-MANUAL / BATCH / NULL, i.e. anything not SINGLE) now support
        -- the extras too, booked on the head-office (888) branch ticket. See
        -- the BATCH branch below; its HO-specific rejections (60522) happen
        -- before anything is written for that invoice, and the whole voucher
        -- is one transaction either way.
        -- The "advance on an invoice with no head-office share" case is also
        -- checked HERE, before the credit-pool check below, so the user gets
        -- the specific 60522 instead of a misleading 60514 (same ordering
        -- lesson as sp-reviewer 24c). The BATCH branch re-checks per invoice.
        IF @parmpaymethod <> 'PURCHASE'
           AND EXISTS (
               SELECT 1
               FROM #Lines l
               JOIN ExpenseSummary es
                 ON es.SupplierID       = @SupplierKey
                AND es.BatchReferenceID = l.BatchReferenceID
                AND es.InvoiceNo        = l.InvoiceNo
               WHERE ISNULL(es.PostingMode, 'BATCH') <> 'SINGLE'
                 AND l.AdvanceApplied > 0
                 AND NOT EXISTS (SELECT 1 FROM ExpenseMaster em
                                 WHERE em.SupplierID = @SupplierKey AND em.BatchReferenceID = l.BatchReferenceID
                                   AND em.InvoiceNo = l.InvoiceNo AND em.BranchCode = @HOBranch)
           )
            THROW 60522, 'Advance Applied on a multi-branch expense is booked on the head-office (888) ticket, but at least one selected invoice has no head-office share. Pay that invoice in cash, or apply the advance to another invoice.', 1;

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
        -- AdvanceApplied (same rules as PURCHASE).
        -- 2026-09-25: BATCH / MULTI-MANUAL accept them too, booked on the
        -- head-office (888) ticket - see the BATCH section below.
        -- ============================================================
        ELSE
        BEGIN
            -- GL accounts for the extras come from the same mapping rows the
            -- PURCHASE mnemonics use, so both modes always hit the same
            -- accounts (101030208 / 60339 today) - never hardcoded here.
            DECLARE @xOverPayAcct VARCHAR(50), @xOverPayExpAcct VARCHAR(50), @xAdvanceAcct VARCHAR(50);
            -- 2026-09-25 (sp-reviewer): the multi-branch settlement payable (was the literal
            -- '20103' in three places below) declared once.
            DECLARE @eBatchPayableAcct VARCHAR(20) = '20103';
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
                -- (every non-SINGLE expense invoice: MULTI-MANUAL / BATCH / NULL)
                --
                -- NEW 2026-09-25: OverPay / OverPayExpense / AdvanceApplied.
                -- Confirmed with user: the whole amount is booked on the HEAD
                -- OFFICE (888) branch's settlement ticket, not prorated.
                --   * Invoice has an 888 share: the extras ride on the 888
                --     ticket (its cash = its share - withholdings - advance
                --     + overpay). Advance larger than 888's share -> 60522.
                --   * No 888 share: OverPay / OverPayExpense get a separate
                --     888 ticket (DR advances-or-expense / CR bank, balanced
                --     on its own); AdvanceApplied is rejected (60522) - there
                --     is no 888 payable for it to settle.
                -- Invoices with none of the three post exactly as before.
                DECLARE @bOverPay DECIMAL(18,2), @bOverPayExp DECIMAL(18,2), @bAdvApplied DECIMAL(18,2),
                        @bHOBranch VARCHAR(5) = @HOBranch,   -- declared once at the top of the proc
                        @bHasHO BIT;

                SELECT @bOverPay = OverPay, @bOverPayExp = OverPayExpense, @bAdvApplied = AdvanceApplied
                FROM #Lines WHERE RowNum = @row;

                IF (@bOverPay > 0 AND @xOverPayAcct IS NULL)
                   OR (@bOverPayExp > 0 AND @xOverPayExpAcct IS NULL)
                   OR (@bAdvApplied > 0 AND @xAdvanceAcct IS NULL)
                    THROW 60518, 'JournalEntryMapping for supplier overpayment/advance (PV-AP-OVERPAY / PV-AP-OVERPAYEXP / PV-AP-ADVAPPLIED) is missing or inactive.', 1;

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

                -- CHANGED 2026-09-25: + AdvanceApplied - OverPay - OverPayExpense,
                -- same as PURCHASE / SINGLE (all 0 on a plain line -> unchanged).
                SELECT @eGross = AmountPaid + @eEWTRemain + DiscountAmount + OffsetAmount - Variance
                               + AdvanceApplied - OverPay - OverPayExpense
                FROM #Lines WHERE RowNum = @row;

                IF ROUND(@eGross - @eCurBalance, 2) > 0
                BEGIN
                    DECLARE @EOverpayMsgB VARCHAR(500) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': the amount being settled (' + CAST(@eGross AS VARCHAR(30))
                        + ') exceeds its Balance (' + CAST(@eCurBalance AS VARCHAR(30)) + '). Lower Amount Paid, or put the excess in the OverPay / OverPay (Expense) column.';
                    THROW 60504, @EOverpayMsgB, 1;
                END

                -- NEW 2026-09-25: same rule as PURCHASE / SINGLE (60515).
                IF (@bOverPay > 0 OR @bOverPayExp > 0) AND ROUND(@eCurBalance - @eGross, 2) <> 0
                BEGIN
                    DECLARE @EOverNotFullMsgB VARCHAR(500) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': OverPay is only allowed when the invoice is fully settled (Balance ' + CAST(@eCurBalance AS VARCHAR(30))
                        + ', settled ' + CAST(@eGross AS VARCHAR(30)) + ').';
                    THROW 60515, @EOverNotFullMsgB, 1;
                END

                -- NEW 2026-09-25: HO share present? Checked before any write
                -- for this invoice so a rejection leaves nothing half-posted.
                SET @bHasHO = CASE WHEN EXISTS (
                    SELECT 1 FROM ExpenseMaster
                    WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo
                      AND BranchCode = @bHOBranch) THEN 1 ELSE 0 END;

                IF @bAdvApplied > 0 AND @bHasHO = 0
                BEGIN
                    DECLARE @ENoHOAdvMsg VARCHAR(500) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ' has no head-office (' + @bHOBranch
                        + ') share - Advance Applied on a multi-branch expense is booked on the head-office ticket, so it can''t be applied to this invoice. Pay it in cash, or apply the advance to another invoice.';
                    THROW 60522, @ENoHOAdvMsg, 1;
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

                    -- NEW 2026-09-25: extras only on the head-office branch ticket.
                    DECLARE @brOverPay DECIMAL(18,2), @brOverPayExp DECIMAL(18,2), @brAdv DECIMAL(18,2), @brRawNet DECIMAL(18,2);
                    SET @brOverPay    = CASE WHEN @brBranch = @bHOBranch THEN @bOverPay    ELSE 0 END;
                    SET @brOverPayExp = CASE WHEN @brBranch = @bHOBranch THEN @bOverPayExp ELSE 0 END;
                    SET @brAdv        = CASE WHEN @brBranch = @bHOBranch THEN @bAdvApplied ELSE 0 END;

                    SET @brRawNet = @brGross - @brEWT - @brDisc - @brOffset - @brAdv + @brOverPay + @brOverPayExp + @brFXLoss - @brFXGain;

                    IF @brAdv > 0 AND ROUND(@brRawNet, 2) < 0
                    BEGIN
                        DECLARE @EHOAdvTooBigMsg VARCHAR(500) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': Advance Applied (' + CAST(@brAdv AS VARCHAR(30))
                            + ') is more than the head-office share being paid (' + CAST(@brGross - @brEWT - @brDisc - @brOffset AS VARCHAR(30))
                            + '). Lower Advance Applied to at most that amount.';
                        THROW 60522, @EHOAdvTooBigMsg, 1;
                    END

                    -- Unchanged floor-at-0 for ordinary branches (no extras -> identical to before).
                    SET @brNetCash = ROUND(CASE WHEN @brRawNet < 0 THEN 0 ELSE @brRawNet END, 2);
                    SET @TotalNetCashForRecon += @brNetCash;

                    -- The settlement helper never checks DR = CR; do it here for
                    -- the ticket that carries extras, so a rounding cent or the
                    -- floor above can never post an unbalanced ticket silently.
                    IF @brOverPay > 0 OR @brOverPayExp > 0 OR @brAdv > 0
                    BEGIN
                        DECLARE @brDr DECIMAL(18,2), @brCr DECIMAL(18,2);
                        SET @brDr = ROUND(@brGross, 2) + @brOverPay + @brOverPayExp + @brFXLoss;
                        SET @brCr = @brNetCash + @brEWT + @brDisc + @brOffset + @brAdv + @brFXGain;
                        IF @brDr <> @brCr
                        BEGIN
                            DECLARE @BImbalMsg VARCHAR(400) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': head-office settlement ticket would not balance (Debit '
                                + CAST(@brDr AS VARCHAR(30)) + ', Credit ' + CAST(@brCr AS VARCHAR(30)) + ').';
                            THROW 60518, @BImbalMsg, 1;
                        END
                    END

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
                        @PayableAccountCode=@eBatchPayableAcct, @GrossPayable=@brGross,
                        @BankAccountCode=@parmglcode, @NetCash=@brNetCash,
                        @EWTAmount=@brEWT, @DiscountAmount=@brDisc, @DiscountAccountCode=@eDiscAcct,
                        @OffsetAmount=@brOffset, @FXLoss=@brFXLoss, @FXGain=@brFXGain,
                        -- NEW 2026-09-25 (0 on every non-HO branch)
                        @OverPay=@brOverPay, @OverPayAccountCode=@xOverPayAcct,
                        @OverPayExpense=@brOverPayExp, @OverPayExpenseAccountCode=@xOverPayExpAcct,
                        @AdvanceApplied=@brAdv, @AdvanceAccountCode=@xAdvanceAcct,
                        @TicketNumber=@TicketNumber OUTPUT;

                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @brBranch,
                            @eInvoiceNo, @eInvoiceDate, @brGross, 'EXPENSE PAYMENT',
                            @parmpaymethod, @parmvouchertype, @TicketNumber,
                            @eBatchPayableAcct, @parmglcode, CAST(@eBatchRef AS VARCHAR(50)), @eBatchRef);

                    -- NEW 2026-09-25: credit-pool rows for the HO ticket's extras
                    -- (same shape/GL-code convention as the SINGLE branch).
                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    SELECT @parmvoucherid, @parmsupplierid, @parmrefno, @brBranch,
                           @eInvoiceNo, @eInvoiceDate, x.Amount, x.PaymentType,
                           @parmpaymethod, @parmvouchertype, @TicketNumber,
                           x.DebitGL, x.CreditGL, CAST(@eBatchRef AS VARCHAR(50)), @eBatchRef
                    FROM (VALUES ('OVERPAY',        @brOverPay,    @xOverPayAcct,    @parmglcode),
                                 ('OVERPAYEXPENSE', @brOverPayExp, @xOverPayExpAcct, @parmglcode),
                                 ('ADVANCEAPPLIED', @brAdv,        @eBatchPayableAcct, @xAdvanceAcct)) x (PaymentType, Amount, DebitGL, CreditGL)
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
                            @brMnemonic, @parmcheckdate, @parmrefno,
                            CAST(@eBatchRef AS VARCHAR(40))+'-'+@brBranch,
                            @eInvoiceNo, 0, @brGross, 0, @brGross, @parmpreparedby, '*', @brGross, 'PARTIAL',
                            0, @TicketNumber, @eBatchRef);

                    SET @brrow += 1;
                END;

                -- NEW 2026-09-25: invoice with NO head-office share - OverPay /
                -- OverPayExpense go on their own 888 ticket, which balances by
                -- itself (DR advances-or-expense / CR bank = the excess cash).
                -- Reuses the settlement helper with the advances (or expense)
                -- account as its debit leg; no 20103 leg is involved.
                -- (AdvanceApplied was already rejected above for this case.)
                IF @bHasHO = 0 AND (@bOverPay > 0 OR @bOverPayExp > 0)
                BEGIN
                    DECLARE @hoAmt DECIMAL(18,2), @hoAcct VARCHAR(50), @hoType VARCHAR(20);
                    SELECT @hoAmt  = CASE WHEN @bOverPay > 0 THEN @bOverPay ELSE @bOverPayExp END,
                           @hoAcct = CASE WHEN @bOverPay > 0 THEN @xOverPayAcct ELSE @xOverPayExpAcct END,
                           @hoType = CASE WHEN @bOverPay > 0 THEN 'OVERPAY' ELSE 'OVERPAYEXPENSE' END;

                    SET @TotalNetCashForRecon += @hoAmt;

                    SET @eParticulars = 'EXPENSE OVERPAYMENT (HO) | Supplier: '+@parmsupplierid+' | Ref: '+@parmrefno
                        +' | Invoice: '+ISNULL(@eInvoiceNo,'')
                        +CASE WHEN LEN(ISNULL(@parmcheckremarks,''))>0 THEN ' | '+LEFT(@parmcheckremarks,200) ELSE '' END;

                    EXEC sp_Payment_PostSettlementTicket
                        @TicketDate=@parmcheckdate, @BranchCode=@bHOBranch,
                        @ReferenceKey=@parmvoucherid, @ReferenceNumber=@parmrefno,
                        @Owner=@parmsuppliername, @Particulars=@eParticulars,
                        @PreparedBy=@parmpreparedby, @Mnemonic='EXP-OVERPAY-HO',
                        @PayableAccountCode=@hoAcct, @GrossPayable=@hoAmt,
                        @BankAccountCode=@parmglcode, @NetCash=@hoAmt,
                        @TicketNumber=@TicketNumber OUTPUT;

                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @bHOBranch,
                            @eInvoiceNo, @eInvoiceDate, @hoAmt, @hoType,
                            @parmpaymethod, @parmvouchertype, @TicketNumber,
                            @hoAcct, @parmglcode, CAST(@eBatchRef AS VARCHAR(50)), @eBatchRef);
                END

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
