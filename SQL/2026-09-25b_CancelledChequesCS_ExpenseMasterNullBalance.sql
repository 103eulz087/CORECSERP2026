/* ================================================================
   2026-09-25b: sp_CancelledChequesCS -- EXPENSE reversal wrote NULL into
   ExpenseMaster.Balance.
   ================================================================
   Found while testing 2026-09-25_...ExpenseMultiBranch.sql, reproduced
   with a PLAIN multi-branch payment (no overpay/advance): after reversal
   every ExpenseMaster line of the invoice had Balance = NULL (invoice-level
   ExpenseSummary.Balance was correct). Fix approved by user.

   CAUSE: the per-line reversal used EM2.EWTAmount / DiscountAmount /
   OffsetAmount (NULL on MULTI-MANUAL lines) and EM.AmountPaid without
   ISNULL, so the Balance sum was NULL.

   FIX (EXPENSE per-line UPDATE only; everything else is the live DEV body):
     - ISNULL on the three LineRev shares and on EM.AmountPaid / Amount.
     - New values computed ONCE in a CROSS APPLY (same arithmetic, same
       clamps at 0) instead of being repeated in four expressions.
     - Status: UNPAID (nothing paid) / PARTIAL / FULLYPAID, matching the
       posting side. The old "> 0 -> PARTIAL else POSTED" only produced
       POSTED because of the NULL; with a real Balance it would have marked
       every fully reversed line PARTIAL.

   NOT changed (flagged to user): the reversal subtracts each line's OWN
   EWTAmount / DiscountAmount / OffsetAmount from itself, i.e. zeroes them.
   Those are accrual-time values (V2 reads ExpenseMaster.EWTAmount to know
   how much EWT to withhold), so a reversed-and-repaid multi-branch invoice
   may withhold no EWT the second time.

   Deploy to CORECSERP_002_DEV first; mirror to CORECSJFC2026_STAGING only
   after confirming with the user.
   ================================================================ */

IF OBJECT_ID('dbo.sp_CancelledChequesCS', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_CancelledChequesCS', 'sp_CancelledChequesCS_OLD_09252026100000';
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

            -- CHANGED 2026-09-25 (NULL-balance fix): each line's new values are
            -- computed ONCE in the CROSS APPLY below instead of being repeated in
            -- four expressions, with every term ISNULL-guarded. Before, a NULL
            -- EWTAmount / DiscountAmount / OffsetAmount on the line (normal for
            -- MULTI-MANUAL lines) or a NULL AmountPaid made the whole sum NULL,
            -- so ExpenseMaster.Balance was written as NULL on every reversal.
            -- The arithmetic is otherwise unchanged (same clamps at 0, same
            -- subtraction of the line's own EWT/Discount/Offset).
            -- Status now follows the posting side's vocabulary: nothing paid ->
            -- UNPAID, part paid -> PARTIAL, nothing left -> FULLYPAID. The old
            -- "> 0 -> PARTIAL else POSTED" only ever produced POSTED because the
            -- NULL made the test false; with a real Balance it would have
            -- marked every fully reversed line PARTIAL.
            UPDATE EM SET
                EM.AmountPaid     = v.NewAmountPaid,
                EM.EWTAmount      = v.NewEWT,
                EM.DiscountAmount = v.NewDisc,
                EM.OffsetAmount   = v.NewOffset,
                EM.Balance        = v.NewBalance,
                EM.Status = CASE
                    WHEN v.NewBalance >= ISNULL(EM.Amount, 0) THEN 'UNPAID'
                    WHEN v.NewBalance > 0                     THEN 'PARTIAL'
                    ELSE 'FULLYPAID'
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
                    ISNULL(EM2.EWTAmount, 0)      AS LineEWTShare,
                    ISNULL(EM2.DiscountAmount, 0) AS LineDiscShare,
                    ISNULL(EM2.OffsetAmount, 0)   AS LineOffsetShare
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
            CROSS APPLY (
                SELECT p.NewAmountPaid, w.NewEWT, d.NewDisc, o.NewOffset,
                       ISNULL(EM.Amount, 0) - (p.NewAmountPaid + w.NewEWT + d.NewDisc + o.NewOffset) AS NewBalance
                FROM (SELECT CASE WHEN ISNULL(EM.AmountPaid, 0) - ISNULL(LineRev.LineGrossShare, 0) < 0 THEN 0
                                  ELSE ISNULL(EM.AmountPaid, 0) - ISNULL(LineRev.LineGrossShare, 0) END AS NewAmountPaid) p
                CROSS JOIN (SELECT CASE WHEN ISNULL(EM.EWTAmount, 0) - LineRev.LineEWTShare < 0 THEN 0
                                        ELSE ISNULL(EM.EWTAmount, 0) - LineRev.LineEWTShare END AS NewEWT) w
                CROSS JOIN (SELECT CASE WHEN ISNULL(EM.DiscountAmount, 0) - LineRev.LineDiscShare < 0 THEN 0
                                        ELSE ISNULL(EM.DiscountAmount, 0) - LineRev.LineDiscShare END AS NewDisc) d
                CROSS JOIN (SELECT CASE WHEN ISNULL(EM.OffsetAmount, 0) - LineRev.LineOffsetShare < 0 THEN 0
                                        ELSE ISNULL(EM.OffsetAmount, 0) - LineRev.LineOffsetShare END AS NewOffset) o
            ) v
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
