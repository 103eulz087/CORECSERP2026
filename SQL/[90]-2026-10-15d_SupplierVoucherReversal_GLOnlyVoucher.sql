/* ================================================================
   [90] 2026-10-15d  Supplier Voucher Reversal: GL-only (manual-line) vouchers
   ================================================================
   Why (user, 2026-10-15, STAGING): SupplierVoucherReversalFrm could not
   reverse telegraphic voucher 923 / reference 38711 (000125 PROFOOD GMBH,
   650,000.00: DR 101030207 ADVANCES TO PROFOOD / CR 101020207 MBTC EURO1).
   The screen showed "Reversal failed: Nothing found to reverse for this
   Reference No." (60401).

   Cause: sp_ReverseCombinedSupplierVoucher only knew two kinds of content:
     invoice leg  = APPaymentDetails rows   -> sp_CancelledChequesCS
     manual leg   = CashAdvance rows        -> sp_ReverseCashAdvanceEntry
   A voucher keyed on the Vouchering (Telegraphic) screen with manual GL lines
   only (sp_PostVoucherManual, no invoice ticked) writes neither: it writes the
   voucher row (TelegraphicVoucher / CashVoucher), a TransactionPaymentAP header
   of 0.00, ONE GL ticket (Mnemonic VOUCHER-MANUAL, ReferenceNumber = reference,
   ReferenceKey = voucher id) and a bank-recon OC item per bank account
   credited (ReferenceNo = voucher id, SourceRef = reference). No supplier-
   ledger row (that proc writes the ledger only for invoices). The list proc
   still offers it, so every such voucher failed with 60401.
   Found 2026-10-15: DEV 1 (739 / 32340), STAGING 5 (919, 920, 922, 923, 924,
   today's PROFOOD loan / advance entries), PRODUCTION 0. Nothing else has this
   shape (the CHECK rows with no ticket are cancelled-cheque records, already
   voided). No VOUCHER-MANUAL voucher ever produced a DIT item on any tier.

   RULE (new third case, "GL-only voucher"): no invoice leg, no cash-advance
   leg, a TelegraphicVoucher or CashVoucher row of this supplier / reference /
   voucher id, and a VOUCHER-MANUAL ticket under reference + voucher id.
   Reversing it, in the wrapper's one transaction:
     - same per-voucher applock as sp_CancelledChequesCS (APREV:<supplier>:<id>, 60521)
     - refused 50050 when already reversed (audit row, voucher isErrorCorrect,
       or a REVERSAL ticket already under reference + voucher id)
     - refused 60402 when an OC item of the voucher is already CLEARED in the
       bank recon (the money left the bank; unclear it there first, or book a
       correcting entry)
     - refused 60403 when an open DIT item of the voucher exists (never seen;
       sp_BankRecon_VoidOC voids OC only, and this script does not write recon
       rows itself: bank recon is hardening H7's area)
     - refused 60404 when supplier-ledger rows exist under the reference
       (sp_PostVoucherManual writes none without invoices: something else
       posted here, reverse it on purpose, not by this path)
     - only the voucher's OWN documents (sp_ReverseTicketsAP and
       sp_BankRecon_VoidOC select by reference alone, Known Bug #12 family):
       60408 when a ticket under reference + voucher id is not its
       VOUCHER-MANUAL / PV ticket, 60407 when a recon item under the
       reference is not its own (ReferenceNo = voucher id, AP-PAYMENT).
       0 such rows on DEV / STAGING / PRODUCTION (2026-10-15): defensive.
     - 60406 when the bank recon is LOCKED for the item's account / branch in
       its month or any later month (H7's rule from [88]: open items carry
       forward; read WITH (HOLDLOCK)). sp_BankRecon_VoidOC itself still checks
       only the item's own header (93006); changing it is H7's to do.
     - "cleared" = IsResolved 1, not VOIDED... / REVERSED, Amount <> 0
       (system-closed zero-amount items don't count).
     - PaymentReversalAudit row; TransactionPaymentAP ErrorCorrect = 1
     - sp_ReverseTicketsAP mirrors the ticket(s) under reference + voucher id,
       dated like the source (rule of 2026-10-09: a reversal falls into the
       source month; a closed GL month refuses, 59900)
     - sp_BankRecon_VoidOC voids the open OC item(s) (locked period: 93006)
     - post-check 60405: under reference + voucher id every account nets to 0,
       reversal tickets = source tickets, no own OC item left open
   Not covered (none on any tier): a CHECK-type manual voucher (sp_PostVoucherManual
   writes TelegraphicVoucher / CashVoucher only), and a voucher whose manual
   lines both debit and credit the same bank account (OC + DIT: refused 60403).
     - the voucher row is marked isErrorCorrect (the wrapper's existing tail)
   The invoice and cash-advance paths are unchanged (same text).
   Loan note: a GL-only voucher that paid the PROFOOD loan (DR 20203) puts
   20203 back when reversed; if a loan revaluation already used that payment
   (Control No. / changed balance, [81]), the next revaluation refuses until
   GL and loan agree again (62020).

   Deploy: rename to sp_ReverseCombinedSupplierVoucher_OLD_10152026170000,
   CREATE the new text, one transaction, guarded: the live text must be the
   [85] text (whitespace-insensitive SHA-256 8DA8222F..., identical on DEV /
   STAGING / PRODUCTION on 2026-10-15). Run in ONE connection, no open
   transaction. Same parameters and result set; no exe change.
   Test: [90]-2026-10-15d_SupplierVoucherReversal_GLOnlyVoucher_Test.sql.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET LOCK_TIMEOUT 10000;
GO

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[90] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.sp_ReverseCombinedSupplierVoucher', 'P') IS NULL
BEGIN
    RAISERROR('[90] stopped: sp_ReverseCombinedSupplierVoucher does not exist in this database; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.sp_ReverseCombinedSupplierVoucher_OLD_10152026170000', 'P') IS NOT NULL
BEGIN
    RAISERROR('[90] stopped: the backup sp_ReverseCombinedSupplierVoucher_OLD_10152026170000 already exists ([90] already installed?); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(
            OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReverseCombinedSupplierVoucher')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '8DA8222F325160384167DA8AC138F1A800D704B7B68A7BFC21366E752255E72C'
BEGIN
    RAISERROR('[90] stopped: sp_ReverseCombinedSupplierVoucher is not the [85] text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[90] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
EXEC sp_rename 'dbo.sp_ReverseCombinedSupplierVoucher', 'sp_ReverseCombinedSupplierVoucher_OLD_10152026170000';
GO

IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
-- ----------------------------------------------------------------
-- sp_ReverseCombinedSupplierVoucher - the single entry point of SupplierVoucherReversalFrm.
-- Inspects what is posted under this ReferenceNo and reverses whichever legs exist, together.
-- [85] 2026-10-14 (hardening H4): ONE transaction. It had none: a refusal of the manual leg (60301 / 60302) after
-- sp_CancelledChequesCS had committed left the invoice leg reversed and the voucher voided while the cash advance
-- stayed outstanding. Same parameters, same result set, same rows on the success path (compared old vs new on DEV).
-- [90] 2026-10-15: third case, a GL-only voucher (Vouchering Telegraphic / Cash with manual GL lines only,
-- sp_PostVoucherManual): its VOUCHER-MANUAL ticket is mirrored and its open OC item voided. It used to fail 60401.
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

    DECLARE @HasInvoiceLeg BIT, @HasManualLeg BIT, @HasGLOnlyLeg BIT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        SET @HasInvoiceLeg = CASE WHEN EXISTS (
            SELECT 1 FROM APPaymentDetails WHERE ReferenceNumber = @parmreferenceno AND SupplierID = @parmsupplierid
        ) THEN 1 ELSE 0 END;

        SET @HasManualLeg = CASE WHEN EXISTS (
            SELECT 1 FROM dbo.CashAdvance WHERE ReferenceNo = @parmreferenceno AND SupplierID = @parmsupplierid AND Status <> 'REVERSED'
        ) THEN 1 ELSE 0 END;

        -- [90] GL-only voucher: no invoice, no cash advance; a telegraphic / cash voucher row and its VOUCHER-MANUAL ticket
        IF @HasInvoiceLeg = 0 AND @HasManualLeg = 0
           AND (   EXISTS (SELECT 1 FROM dbo.TelegraphicVoucher WHERE VoucherID = @parmvoucherid AND SupplierID = @parmsupplierid AND ReferenceNumber = @parmreferenceno)
                OR EXISTS (SELECT 1 FROM dbo.CashVoucher        WHERE VoucherID = @parmvoucherid AND SupplierID = @parmsupplierid AND ReferenceNumber = @parmreferenceno))
           AND EXISTS (SELECT 1 FROM dbo.TicketMaster
                       WHERE ReferenceNumber = @parmreferenceno AND ReferenceKey = @parmvoucherid
                         AND Mnemonic = 'VOUCHER-MANUAL' AND ISNULL(Product, '') <> 'REVERSAL')
            SET @HasGLOnlyLeg = 1;

        IF @HasInvoiceLeg = 0 AND @HasManualLeg = 0 AND @HasGLOnlyLeg = 0
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

        -- [90] GL-only leg
        IF @HasGLOnlyLeg = 1
        BEGIN
            DECLARE @RevLock INT, @RevLockName NVARCHAR(255) = N'APREV:' + ISNULL(@parmsupplierid, '') + N':' + ISNULL(@parmvoucherid, '');
            EXEC @RevLock = sp_getapplock @Resource = @RevLockName, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
            IF @RevLock < 0
                THROW 60521, 'This voucher is being reversed by someone else right now. Please try again.', 1;

            IF EXISTS (SELECT 1 FROM dbo.PaymentReversalAudit WHERE VoucherID = @parmvoucherid AND SupplierID = @parmsupplierid AND ReferenceNumber = @parmreferenceno)
               OR EXISTS (SELECT 1 FROM dbo.TelegraphicVoucher WHERE VoucherID = @parmvoucherid AND SupplierID = @parmsupplierid AND ReferenceNumber = @parmreferenceno AND isErrorCorrect = 1)
               OR EXISTS (SELECT 1 FROM dbo.CashVoucher        WHERE VoucherID = @parmvoucherid AND SupplierID = @parmsupplierid AND ReferenceNumber = @parmreferenceno AND isErrorCorrect = 1)
               OR EXISTS (SELECT 1 FROM dbo.TicketMaster WHERE ReferenceNumber = @parmreferenceno AND ReferenceKey = @parmvoucherid AND Product = 'REVERSAL')
                THROW 50050, 'Voucher already reversed.', 1;

            -- only this voucher's own documents: every ticket under reference + voucher id is its VOUCHER-MANUAL ticket,
            -- every recon item under the reference is its own (ReferenceNo = voucher id, AP-PAYMENT). sp_ReverseTicketsAP
            -- and sp_BankRecon_VoidOC select by reference alone (Known Bug #12 family), so a foreign row is refused here.
            IF EXISTS (SELECT 1 FROM dbo.TicketMaster
                       WHERE ReferenceNumber = @parmreferenceno AND ReferenceKey = @parmvoucherid
                         AND NOT (ISNULL(Mnemonic, '') = 'VOUCHER-MANUAL' AND ISNULL(Origin, '') = 'PV'))
                THROW 60408, 'Another document''s GL ticket shares this reference and voucher id; it cannot be reversed from this screen. Ask the accountant.', 1;

            IF EXISTS (SELECT 1 FROM dbo.BankStatementRecon
                       WHERE SourceRef = @parmreferenceno AND ItemType IN ('OC', 'DIT')
                         AND NOT (ReferenceNo = @parmvoucherid AND ISNULL(SourceModule, '') = 'AP-PAYMENT'))
                THROW 60407, 'Another document''s bank-recon item shares this reference; it cannot be reversed from this screen. Ask the accountant.', 1;

            DECLARE @ClearedMsg NVARCHAR(400);
            SELECT TOP (1) @ClearedMsg = N'This voucher''s bank payment (' + r.AccountCode + N', ' + FORMAT(r.Amount, 'N2')
                   + N') is already cleared in the bank reconciliation. Unclear it there first, or book a correcting entry.'
            FROM dbo.BankStatementRecon AS r
            WHERE r.SourceRef = @parmreferenceno AND r.ReferenceNo = @parmvoucherid AND r.SourceModule = 'AP-PAYMENT'
              AND r.ItemType = 'OC' AND r.IsResolved = 1 AND r.Amount <> 0
              AND ISNULL(r.ResolvedReason, '') NOT LIKE 'VOID%' AND ISNULL(r.ResolvedReason, '') <> 'REVERSED'
            ORDER BY r.ReconID;
            IF @ClearedMsg IS NOT NULL
                THROW 60402, @ClearedMsg, 1;

            IF EXISTS (SELECT 1 FROM dbo.BankStatementRecon
                       WHERE SourceRef = @parmreferenceno AND ReferenceNo = @parmvoucherid AND SourceModule = 'AP-PAYMENT'
                         AND ItemType = 'DIT' AND ISNULL(IsResolved, 0) = 0)
                THROW 60403, 'This voucher has a deposit-in-transit item in the bank reconciliation; this screen reverses outstanding cheques only. Ask the accountant to handle it.', 1;

            -- H7's lock rule ([88]): open items carry forward, so a LOCKED month at or after the item's month refuses
            DECLARE @LockMsg NVARCHAR(400);
            SELECT TOP (1) @LockMsg = N'The bank reconciliation of ' + h.AccountCode + N' is locked for ' + CONVERT(NVARCHAR(10), h.PeriodEnd, 120)
                   + N' (at or after this payment''s month); ask the accountant to reopen it first.'
            FROM dbo.BankStatementRecon AS r
            INNER JOIN dbo.BankReconHeader AS h WITH (HOLDLOCK)
                ON  h.AccountCode = r.AccountCode
                AND h.BranchCode  = r.BranchCode
                AND h.PeriodEnd  >= r.PeriodEnd
                AND h.Status      = 'LOCKED'
            WHERE r.SourceRef = @parmreferenceno AND r.ReferenceNo = @parmvoucherid AND r.SourceModule = 'AP-PAYMENT'
              AND r.ItemType = 'OC' AND ISNULL(r.IsResolved, 0) = 0
            ORDER BY h.PeriodEnd;
            IF @LockMsg IS NOT NULL
                THROW 60406, @LockMsg, 1;

            IF EXISTS (SELECT 1 FROM dbo.SupplierLedger WHERE ReferenceNumber = @parmreferenceno AND SupplierID = @parmsupplierid)
                THROW 60404, 'This voucher has supplier-ledger rows, which a GL-only voucher never writes; it cannot be reversed here.', 1;

            DECLARE @SrcTickets INT = (SELECT COUNT(*) FROM dbo.TicketMaster
                                       WHERE ReferenceNumber = @parmreferenceno AND ReferenceKey = @parmvoucherid);

            INSERT INTO dbo.PaymentReversalAudit
                (VoucherID, SupplierID, VoucherType, ReferenceNumber, CancelReason, CancelledBy)
            VALUES
                (@parmvoucherid, @parmsupplierid, @parmvouchertype, @parmreferenceno, @parmreason, @parmuser);

            UPDATE dbo.TransactionPaymentAP
            SET ErrorCorrect = 1
            WHERE SupplierKey = @parmsupplierid
              AND ReferenceNumber = @parmreferenceno;

            EXEC dbo.sp_ReverseTicketsAP @parmreferenceno, @parmvoucherid, @parmuser;

            EXEC dbo.sp_BankRecon_VoidOC
                @ReferenceNo = @parmreferenceno,
                @VoidedBy    = @parmuser;

            IF EXISTS (SELECT 1 FROM dbo.TicketDetails
                       WHERE ReferenceNumber = @parmreferenceno AND ReferenceKey = @parmvoucherid
                       GROUP BY AccountCode
                       HAVING ABS(SUM(ISNULL(Debit, 0)) - SUM(ISNULL(Credit, 0))) > 0.004)
               OR (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber = @parmreferenceno AND ReferenceKey = @parmvoucherid AND Product = 'REVERSAL') <> @SrcTickets
               OR EXISTS (SELECT 1 FROM dbo.BankStatementRecon
                          WHERE SourceRef = @parmreferenceno AND ReferenceNo = @parmvoucherid AND SourceModule = 'AP-PAYMENT'
                            AND ItemType = 'OC' AND ISNULL(IsResolved, 0) = 0)
                THROW 60405, 'GL-only reversal post-check failed: the voucher''s ticket / bank item and their reversal do not match; nothing was changed.', 1;
        END

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
           CONCAT('Voucher reversed. InvoiceLeg=', @HasInvoiceLeg, ' ManualLeg=', @HasManualLeg, ' GLOnly=', @HasGLOnlyLeg) AS Message;
END
GO

IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF OBJECT_ID('dbo.sp_ReverseCombinedSupplierVoucher', 'P') IS NULL
    SET @msg = N'sp_ReverseCombinedSupplierVoucher was not created';
ELSE IF OBJECT_ID('dbo.sp_ReverseCombinedSupplierVoucher_OLD_10152026170000', 'P') IS NULL
    SET @msg = N'the backup is missing';
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReverseCombinedSupplierVoucher')) NOT LIKE '%@HasGLOnlyLeg%'
    SET @msg = N'the new text is not the [90] text';

IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[90] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59891, @msg, 1;
END

COMMIT TRANSACTION;
PRINT '[90] committed: sp_ReverseCombinedSupplierVoucher reverses GL-only vouchers; backup sp_ReverseCombinedSupplierVoucher_OLD_10152026170000.';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
