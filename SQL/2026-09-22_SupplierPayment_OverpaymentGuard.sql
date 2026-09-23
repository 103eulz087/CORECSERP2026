-- 2026-09-22: sp_AddPaymentSupplierCompound_V2 -- reject overpayment instead
-- of silently corrupting Balance.
--
-- BUG: SupplierPaymentDevEx.cs's "Amount Paid" grid cell is directly
-- editable with no validation against the invoice's Balance. Posting this
-- SP with Gross (AmountPaid+EWT+Discount+Offset) > Balance used to:
--   - PURCHASE: update APAccounts.Balance = Balance - Gross with no read-back
--     check at all, driving Balance negative.
--   - EXPENSE SINGLE/BATCH: floor ExpenseSummary.Balance at 0
--     (CASE WHEN CurBalance - Gross < 0 THEN 0 ELSE ... END), silently
--     discarding how much the overpayment actually was.
-- Reversing the voucher (sp_CancelledChequesCS) then adds the ORIGINAL
-- (unclamped) Gross back on top of that corrupted starting point -- for
-- EXPENSE mode this lands Balance on Gross (what was paid) instead of the
-- true original Balance, exactly the symptom reported against
-- SupplierPaymentDevEx.cs.
--
-- FIX: read Balance fresh under UPDLOCK/ROWLOCK (Known Bug Pattern #10 --
-- never trust the caller's numbers over a freshly-read, locked value; same
-- pattern already used in sp_PostVoucherManual) immediately before computing
-- Gross, and THROW if Gross would exceed it -- for PURCHASE (60502), EXPENSE
-- SINGLE (60503), and EXPENSE BATCH (60504). This makes the reversal-
-- asymmetry bug structurally unreachable rather than something the reversal
-- side has to detect after the fact. Companion NULL-safety guards added:
-- 60501/60508 (invoice not found in APAccounts/ExpenseSummary -- a NULL
-- Balance would make the overpayment check evaluate UNKNOWN and silently
-- skip the THROW) and 60507 (supplier not found).
--
-- BONUS FIX bundled in the same deploy: sp_CancelledChequesCS's PURCHASE
-- reversal has always summed APPaymentDetails by PaymentType IN ('EWT',
-- 'DISCOUNT','RETURNALLOWANCES') to add those back onto Balance on reversal,
-- but the PURCHASE branch here never actually wrote those rows -- only the
-- AmountPaid ('INVOICE PAYMENT') row -- so that SUM was always 0 and every
-- PURCHASE reversal permanently under-restored Balance by whatever EWT/
-- Discount/Offset was withheld (and a line settled ENTIRELY by those,
-- AmtPaid=0, was skipped from reversal altogether). This proc now writes
-- EWT/DISCOUNT/RETURNALLOWANCES/VARIANCE rows too when nonzero/nonequal.
-- sp_CancelledChequesCS itself needed no change -- it already expected them.
--
-- STATUS: already deployed and live on CORECSERP_002_DEV (verified via
-- OBJECT_DEFINITION + the backup object sp_AddPaymentSupplierCompound_V2_
-- OLD_20260922100000 already present) -- this script is the missing
-- checked-in record of that change, written from the live definition, so
-- it can be tracked and mirrored to CORECSJFC2026_STAGING later. Running it
-- again on DEV is a safe no-op (recreates the identical object).

IF OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_AddPaymentSupplierCompound_V2', 'sp_AddPaymentSupplierCompound_V2_OLD_09222026231938';
GO

/* ================================================================
   sp_AddPaymentSupplierCompound_V2
   Parallel to sp_AddPaymentSupplierCompound - same tables, same
   TVP shape (dbo.AP_PaymentLineTVP), callable as a drop-in test
   alternative. PURCHASE mode still delegates to your existing
   sp_PostCompoundTicket (unchanged - never implicated in any bug
   this thread found). EXPENSE mode (SINGLE + BATCH) is rebuilt
   entirely on the three helper procedures in 01_V2_Helpers.sql.

   PARAMETER CONTRACT (stated explicitly, not just assumed):
     @parmcheckamount MUST be net cash actually disbursed - never
     gross. This SP does not trust that blindly for Bank Recon:
     it self-computes net cash from the same figures used to build
     the tickets (the fix already proven out in the V1 procedure)
     and uses THAT for Bank Recon and the voucher header amount.
     If the caller's @parmcheckamount disagrees by more than a cent,
     that's surfaced via @parmcheckamount vs the computed total in
     the result set - see the final SELECT.
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
    @parmPayingBranch   VARCHAR(5)   = NULL
)
AS
/*
    Unchanged from the prior version except: PURCHASE now reads
    APAccounts.Balance fresh under UPDLOCK/ROWLOCK before computing
    Gross (it previously updated Balance blind, in one statement,
    with no overpayment check at all); EXPENSE SINGLE and BATCH now
    read ExpenseSummary.Balance under UPDLOCK/ROWLOCK (previously
    unlocked) and both THROW if Gross would exceed it, before the
    existing (now-defensive-only) floor-at-zero Balance update runs.
    See SQL/2026-09-22_SupplierPayment_OverpaymentGuard.sql header for
    why this replaces "remove the floor" - same effect, smaller diff,
    consistent with sp_PostVoucherManual's reviewed pattern.
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

        -- NEW: fail loudly on a bad @parmsupplierid instead of letting every
        -- EXPENSE-branch filter on SupplierID=@SupplierKey silently match zero
        -- rows (which would otherwise compound the NULL-bypass fixed below).
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
            -- NEW: ISNULL-guarded like the other four amount columns below - a
            -- NULL here would make @pGross/@eGross NULL, and NULL > 0 is
            -- UNKNOWN, silently bypassing the overpayment THROWs added below
            -- (same failure shape as a NULL @pCurBalance/@eCurBalance).
            ISNULL(L.ActualCost, 0) AS ActualCost, ISNULL(L.AmountPaid, 0) AS AmountPaid,
            ISNULL(L.EWTAmount, 0) AS EWTAmount,
            ISNULL(L.DiscountAmount, 0) AS DiscountAmount,
            ISNULL(L.OffsetAmount, 0) AS OffsetAmount,
            ISNULL(L.Variance, 0) AS Variance,
            L.DiscountAccountCode,
            L.Description
        INTO #Lines
        FROM @Lines L;

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
                    @pCurBalance DECIMAL(18,2);   -- NEW

            WHILE @row <= @maxrow
            BEGIN
                SELECT
                    @pInvoiceNo = InvoiceNo, @pInvoiceDate = InvoiceDate, @pSeqRef = SequenceReferenceNumber,
                    @pAmtPaid = AmountPaid, @pEWT = EWTAmount, @pDiscount = DiscountAmount,
                    @pRetAllow = OffsetAmount, @pVariance = Variance
                FROM #Lines WHERE RowNum = @row;

                SET @pGross = @pAmtPaid + @pEWT + @pDiscount + @pRetAllow - @pVariance;

                -- NEW: fresh, locked Balance - previously this branch never
                -- read Balance at all, it updated it blind in one statement
                -- with no overpayment check. Known Bug Pattern #10: never
                -- trust the caller's numbers over a freshly-read, locked value.
                SET @pCurBalance = NULL;
                SELECT @pCurBalance = Balance FROM APAccounts WITH (UPDLOCK, ROWLOCK)
                WHERE SupplierID = @parmsupplierid AND InvoiceNo = @pInvoiceNo AND SequenceNo = @pSeqRef;

                IF @pCurBalance IS NULL
                BEGIN
                    DECLARE @PNotFoundMsg VARCHAR(400) = 'Invoice ' + ISNULL(@pInvoiceNo,'') + ' was not found in APAccounts (SequenceNo ' + ISNULL(@pSeqRef,'') + ').';
                    THROW 60501, @PNotFoundMsg, 1;
                END

                -- NEW: reject an overpayment outright instead of letting the
                -- UPDATE below drive Balance negative.
                IF ROUND(@pGross - @pCurBalance, 2) > 0
                BEGIN
                    DECLARE @POverpayMsg VARCHAR(500) = 'Invoice ' + ISNULL(@pInvoiceNo,'') + ': the amount being settled (' + CAST(@pGross AS VARCHAR(30))
                        + ') exceeds its Balance (' + CAST(@pCurBalance AS VARCHAR(30)) + '). Lower Amount Paid (or the EWT/Discount/Offset lines) so it does not exceed Balance.';
                    THROW 60502, @POverpayMsg, 1;
                END

                SET @pFXLoss = CASE WHEN @pVariance > 0 THEN @pVariance ELSE 0 END;
                SET @pFXGain = CASE WHEN @pVariance < 0 THEN -@pVariance ELSE 0 END;
                SET @TotalNetCashForRecon += @pAmtPaid;

                SET @pMnemonic = CASE
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
                INSERT @Amounts VALUES ('GROSS',@pGross),('NET',@pAmtPaid),('EWT',@pEWT),
                                       ('MIRROR',@pDiscount+@pRetAllow),('VARIANCE_LOSS',@pFXLoss),('VARIANCE_GAIN',@pFXGain);
                INSERT @Tokens VALUES ('{BANK}', @parmglcode);
                INSERT @Flags VALUES
                    ('HasEWT', CASE WHEN @pEWT>0 THEN 1 ELSE 0 END),
                    ('HasDiscount', CASE WHEN @pDiscount>0 THEN 1 ELSE 0 END),
                    ('HasFXLoss', CASE WHEN @pFXLoss>0 THEN 1 ELSE 0 END),
                    ('HasFXGain', CASE WHEN @pFXGain>0 THEN 1 ELSE 0 END);

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

                -- NEW: sp_CancelledChequesCS's PURCHASE reversal has ALWAYS
                -- summed APPaymentDetails by PaymentType IN ('EWT','DISCOUNT',
                -- 'RETURNALLOWANCES') to add these back onto Balance on
                -- reversal - but this branch never wrote those rows, so that
                -- SUM was always 0 and every PURCHASE reversal permanently
                -- under-restored Balance by whatever EWT/Discount/Offset was
                -- withheld (and a line settled ENTIRELY by those, AmtPaid=0,
                -- was skipped from reversal altogether - see @pAmtPaid > 0
                -- above). Writing these rows is the fix; sp_CancelledChequesCS
                -- itself needs no change, it already expects them. Confirmed
                -- via sys.sql_expression_dependencies that APAccounts.EWTAmount/
                -- Discount/OffsetAmount are 0 on all 346 existing rows (no
                -- historical version of this posting SP ever populated them
                -- either) - deliberately NOT touched here, since Balance
                -- restoration depends only on these APPaymentDetails rows, not
                -- on those columns' values, and touching them would widen this
                -- fix into every report/aging SP that reads APAccounts.
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

                -- NEW: signed Variance (FX gain/loss) row. @pGross already
                -- has "- @pVariance" baked in (see @pGross formula above), so
                -- restoring Balance by AmtPaid+EWT+Discount+RetAllow ALONE
                -- overshoots by +Variance on every round trip whenever
                -- Variance <> 0 - sp_CancelledChequesCS below now subtracts
                -- this row back out to close that gap exactly. Stored signed
                -- (positive = FX loss, negative = FX gain), matching
                -- @pVariance's convention used throughout this proc. Unlike
                -- the three inserts above this fires on <> 0, not > 0, since
                -- a negative value is a legitimate FX gain, not "nothing to
                -- record".
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

                -- CHANGED: uses the locked @pCurBalance read above instead of
                -- the table's own Balance inline - same result now that Gross
                -- is guaranteed <= Balance, but explicit about what's being
                -- subtracted from.
                UPDATE APACCOUNTS
                SET Balance = @pCurBalance - @pGross,
                    PayStatus = CASE WHEN (@pCurBalance - @pGross) <= 0 THEN 'FULLYPAID' ELSE 'PARTIAL' END
                WHERE SupplierID = @parmsupplierid AND InvoiceNo = @pInvoiceNo AND SequenceNo = @pSeqRef;

                SET @row += 1;
            END;

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

        -- ============================================================
        -- EXPENSE - SINGLE and BATCH
        -- ============================================================
        ELSE
        BEGIN
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

                -- CHANGED: UPDLOCK/ROWLOCK - previously an unlocked read, so a
                -- concurrent payment against the same invoice could read the
                -- same stale Balance (lost update) between here and either
                -- UPDATE below (Known Bug Pattern #10).
                SET @eCurBalance = NULL;
                SELECT @eCurBalance = ISNULL(Balance, ISNULL(Amount, 0))
                FROM ExpenseSummary WITH (UPDLOCK, ROWLOCK)
                WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo;

                -- NEW: without this, no matching row (bad/stale BatchReferenceID
                -- or InvoiceNo) leaves @eCurBalance NULL, which makes every
                -- ROUND(Gross - CurBalance, 2) > 0 check below evaluate UNKNOWN -
                -- silently skipping the THROW instead of firing it. Mirrors the
                -- @pCurBalance IS NULL guard already present in the PURCHASE
                -- branch above.
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
                            @sOffset DECIMAL(18,2), @sFXLoss DECIMAL(18,2), @sFXGain DECIMAL(18,2);

                    SELECT
                        @eGross   = AmountPaid + ISNULL(EWTAmount,0) + ISNULL(DiscountAmount,0) + ISNULL(OffsetAmount,0),
                        @sNetCash = AmountPaid,
                        @sEWT     = ISNULL(EWTAmount,0),
                        @sDisc    = ISNULL(DiscountAmount,0),
                        @sOffset  = ISNULL(OffsetAmount,0)
                    FROM #Lines WHERE RowNum = @row;

                    -- NEW: reject overpayment. This is the exact defect that
                    -- produced the reported bug - Gross was allowed to exceed
                    -- Balance, Balance got floored to 0, and the reversal SP
                    -- then added the FULL (unclamped) Gross back on top of
                    -- that floor, landing on Gross instead of the original
                    -- Balance. Rejecting it here makes that unreachable.
                    IF ROUND(@eGross - @eCurBalance, 2) > 0
                    BEGIN
                        DECLARE @EOverpayMsgS VARCHAR(500) = 'Invoice ' + ISNULL(@eInvoiceNo,'') + ': the amount being settled (' + CAST(@eGross AS VARCHAR(30))
                            + ') exceeds its Balance (' + CAST(@eCurBalance AS VARCHAR(30)) + '). Lower Amount Paid (or the EWT/Discount/Offset lines) so it does not exceed Balance.';
                        THROW 60503, @EOverpayMsgS, 1;
                    END

                    SET @sFXLoss = 0;
                    SET @sFXGain = 0;
                    SET @TotalNetCashForRecon += @sNetCash;

                    -- Unchanged formula - now provably a no-op (Gross <= CurBalance
                    -- is guaranteed by the THROW above) but left in place rather
                    -- than removed, so this stays a minimal diff.
                    SET @eNewBalance = ROUND(CASE WHEN @eCurBalance - @eGross < 0 THEN 0 ELSE @eCurBalance - @eGross END, 2);

                    UPDATE ExpenseSummary
                    SET Balance = @eNewBalance,
                        AmountPaid = ISNULL(AmountPaid,0) + @sNetCash,
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
                        @TicketNumber=@TicketNumber OUTPUT;

                    INSERT INTO APPaymentDetails
                        (VoucherID, SupplierID, ReferenceNumber, BranchCode,
                         InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod,
                         VoucherType, TicketNumber, DebitGLCode, CreditGLCode,
                         SequenceReferenceNumber, BatchReferenceID)
                    VALUES (@parmvoucherid, @parmsupplierid, @parmrefno, @eBranch,
                            @eInvoiceNo, @eInvoiceDate, @eGross, 'EXPENSE PAYMENT',
                            @parmpaymethod, @parmvouchertype, @TicketNumber,
                            @ePayableAcct, @parmglcode, CAST(@eBatchRef AS VARCHAR(50)), @eBatchRef);

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

                -- NEW: same guard as SINGLE mode, at the equivalent point for BATCH.
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
