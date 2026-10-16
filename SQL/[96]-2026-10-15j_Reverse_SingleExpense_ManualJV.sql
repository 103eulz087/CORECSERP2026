/* ================================================================
   [96] 2026-10-15j  Reverse a saved Single Expense / Manual JV (multi-branch)
   ================================================================
   User (2026-10-15): on AddExpenseDevExFrm (Post Single Expense) and
   ManualJournalVoucherMultiBranchFrm (Manual JV) an entry that was saved but
   should never have been keyed must be reversible / cancellable from the
   Posted tab.

   User decisions (2026-10-15):
     - an expense linked to a PO shipment: refused once any stock of that
       shipment was deducted (sold, transferred, converted, adjusted): the
       lots already carry the cost. Otherwise the cost is taken back out.
     - anyone who can post on the screen may reverse (no extra role)
     - a reversed entry stays on the Posted tab, marked CANCELLED, with who /
       when / why

   RULES (both)
     - the original stays in the books; the reversal is a mirror ticket
       (Debit / Credit swapped) dated like the original (2026-10-09 rule:
       a reversal falls in its source month); a closed GL month refuses it
       (period-lock trigger 59900)
     - a reason is required; who / when / why kept in the module's own log
       table (ExpenseSingleReversal / ManualJournalVoucherReversal)
     - a reversed entry can't be edited (56110 / 59229); Copy to New Entry
       still works

   SINGLE EXPENSE  dbo.spu_ReverseSingleExpense (56201-56215)
     - only POSTED / UNPAID with nothing paid, withheld or offset, and the
       balance = the payable of its own SNGLE supplier-ledger row (a
       payment voucher must be reversed first: Supplier Voucher Reversal)
     - exactly one posting ticket (Mnemonic SINGLE, TicketNumber =
       ExpenseMaster.TicketReference, ReferenceNumber + InvoiceNo), DR = CR;
       a balance-forward load (ReferenceNumber 1, no ticket) is refused
     - PO-linked with an inventory leg: the shipment's rows are read under
       UPDLOCK; refused 56211 when any row has Available < Quantity (except a
       lot still HELD at Available 0 while its PO is RECEIVED / FOR
       CONFIRMATION: spu_ConfirmPOFinalCost releases it later at the final
       cost), any row sits at another branch than the costing base (an STS
       copy); 56212 when a lot was received after the expense's day (or on
       that day while the shipment has several receipt dates); 56216 when
       the expense was posted before 2026-09-25 09:48 (the inventory-legs
       costing rule; the same time on every tier: older postings added a
       different amount); else every row of the shipment gets
       Cost - ROUND(inventory legs / fn_InvShipmentBase().BaseQty, 2)
       (= exactly what the posting added: Cost is DECIMAL(18,2))
     - sp_EditSingleExpense takes the same applock EXPREV:<supplier>:<ref>
       inside its transaction and re-reads the expense under UPDLOCK
       (56110 reversed / paid meanwhile, 56111 lock busy), so an edit and a
       reversal never interleave; its duplicate-invoice rule (56104) and the
       screen's ignore a CANCELLED expense (the same invoice no. may be
       posted again correctly; the payment procs key by BatchReferenceID)
     - supplier ledger: the SNGLE row tagged ErrorCorrectTag 1 + a REVERSAL
       row (debit = its credit, the reversed row's TransactionDate), like
       sp_ReverseApprovedExpense; TRN_SEQ_NO via func_getLastID like every
       ledger writer (H8)
     - ExpenseSummary / ExpenseMaster: Status CANCELLED, Balance 0
     - no bank recon item: spu_PostExpenseV2 writes none
   MANUAL JV  dbo.spu_ReverseManualJournalVoucher (59221-59228)
     - applock MANUALJV:<ref> (the same lock as sp_EditManualJournalVoucher)
     - the voucher's own tickets (Origin JV, the TicketNumber its rows carry)
       must be whole: every branch row has its ticket, ticket debits =
       voucher total (else Save Changes repairs it first)
     - its bank recon items (SourceModule MANUAL-JV, SourceRef = ref):
       refused when one is already cleared by the bank (unclear it first) or a
       LOCKED month at or after the item's month exists for its branch +
       account (the H7 lock rule, HOLDLOCK); else voided: IsResolved 1,
       ResolvedReason 'VOIDED - MANUAL JV REVERSED', ClearedPeriodEnd = its
       own month (voided items are hidden in every month)
     - one reversal ticket number for all branches (like the posting)
     - ManualJournalVoucher rows are kept (View Details shows the lines);
       trigger trg_ManualJournalVoucher_NoDeleteAfterReversal refuses 59229 a
       delete of a reversed voucher's rows, so the edit proc (Fable's H7
       object, not changed here) can't re-post it
   LISTS
     - sp_GetPostedSingleExpenses: + ReversedBy, ReversedDate, ReverseReason
     - sp_GetPostedManualJournalVouchers: + Status (POSTED / CANCELLED),
       ReversedBy, ReversedDate, ReverseReason
     - sp_GetSingleExpenseDetails: BlockedReason for a CANCELLED expense; its
       lines = the original posting only (View Details / Copy to New Entry)
     - sp_EditSingleExpense: refuses a CANCELLED expense (56110)
     - fn_rpt_exc_AP_Findings (if installed): AP-STATUS-VS-BALANCE skips a
       CANCELLED expense at 0 (by design; one with a balance still shows)
     - sp_rpt_ItemCostingRecon_List / fn_rpt_exc_AP_ShipmentCosting (if
       installed): a CANCELLED expense is no longer a linked expense
     (sp-reviewer 2026-10-15 points 1-7 + nitpicks taken; v1 was on DEV /
     STAGING for an hour, undone and re-applied as this text)

   Guard: the 4 patched procs = their live texts (whitespace-insensitive
   SHA-256, identical on DEV / STAGING / PRODUCTION 2026-10-15). Independent
   of [88] (the JV recon rules are written here, the edit proc is untouched).
   One transaction with a post-check; backups _OLD_10152026200000. Run in ONE
   connection with no open transaction. Old exe: unchanged behaviour (extra
   list columns only).
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET LOCK_TIMEOUT 10000;
GO

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[96] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.spu_ReverseSingleExpense', 'P') IS NOT NULL OR OBJECT_ID('dbo.spu_ReverseManualJournalVoucher', 'P') IS NOT NULL
BEGIN
    RAISERROR('[96] already applied in this database (the reversal procs exist); nothing changed.', 10, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.fn_InvShipmentBase', 'IF') IS NULL OR OBJECT_ID('dbo.fn_InventoryCostAccounts') IS NULL
     OR COL_LENGTH('dbo.BankStatementRecon', 'ClearedPeriodEnd') IS NULL
BEGIN
    RAISERROR('[96] stopped: needs [78] (fn_InvShipmentBase), fn_InventoryCostAccounts and BankStatementRecon.ClearedPeriodEnd (46); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_EditSingleExpense')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
            <> 'A1C04267BF59AC0C2837E1A0F20E757AD263170B9F673132EEA1520AF0733892'
     OR CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetSingleExpenseDetails')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
            <> '8E572BA89346324596013ACD8251571B31A675F3E9E77B6221978E1AFF0A5058'
     OR CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetPostedSingleExpenses')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
            <> '1E65A1E846487EC0D6F22478B08475A38684F131B2CD089D04B1B8CC38FA05F0'
     OR CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetPostedManualJournalVouchers')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
            <> 'B8A98026D0D432AB5F4CDBB3FBA6DD1A40796EE2B1C7D5C0B9A2FD59D964535D'
BEGIN
    RAISERROR('[96] stopped: sp_EditSingleExpense / sp_GetSingleExpenseDetails / sp_GetPostedSingleExpenses / sp_GetPostedManualJournalVouchers is not the text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[96] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
GO

------------------------------------------------------------------
-- 1. Log tables (one per module)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
IF OBJECT_ID('dbo.ExpenseSingleReversal', 'U') IS NULL
    CREATE TABLE dbo.ExpenseSingleReversal
    (
        ReversalID             INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ExpenseSingleReversal PRIMARY KEY,
        ReferenceNumber        VARCHAR(10)   NOT NULL,
        InvoiceNo              VARCHAR(150)  NOT NULL,
        SupplierID             VARCHAR(20)   NOT NULL,
        BatchReferenceID       BIGINT        NULL,
        OriginalTicketNumber   VARCHAR(50)   NOT NULL,
        ReversalTicketNumber   VARCHAR(50)   NOT NULL,
        Amount                 DECIMAL(18,2) NOT NULL,
        ShipmentNo             VARCHAR(10)   NULL,
        InventoryCostBackedOut DECIMAL(18,2) NOT NULL CONSTRAINT DF_ExpenseSingleReversal_InvCost DEFAULT (0),
        CostPerUnitBackedOut   DECIMAL(18,2) NOT NULL CONSTRAINT DF_ExpenseSingleReversal_PerUnit DEFAULT (0),
        Reason                 VARCHAR(300)  NOT NULL,
        ReversedBy             VARCHAR(100)  NOT NULL,
        ReversedDate           DATETIME      NOT NULL CONSTRAINT DF_ExpenseSingleReversal_Date DEFAULT (GETDATE()),
        CONSTRAINT UQ_ExpenseSingleReversal UNIQUE (ReferenceNumber, InvoiceNo, SupplierID)
    );

IF OBJECT_ID('dbo.ManualJournalVoucherReversal', 'U') IS NULL
    CREATE TABLE dbo.ManualJournalVoucherReversal
    (
        ReferenceNo          VARCHAR(10)   NOT NULL CONSTRAINT PK_ManualJournalVoucherReversal PRIMARY KEY,
        OriginalTicketNumber VARCHAR(50)   NOT NULL,
        ReversalTicketNumber VARCHAR(50)   NOT NULL,
        BranchCount          INT           NOT NULL,
        TotalAmount          DECIMAL(18,2) NOT NULL,
        ReconItemsVoided     INT           NOT NULL CONSTRAINT DF_ManualJournalVoucherReversal_Items DEFAULT (0),
        Reason               VARCHAR(300)  NOT NULL,
        ReversedBy           VARCHAR(50)   NOT NULL,
        ReversedDate         DATETIME      NOT NULL CONSTRAINT DF_ManualJournalVoucherReversal_Date DEFAULT (GETDATE())
    );
GO

------------------------------------------------------------------
-- 2. spu_ReverseSingleExpense
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE dbo.spu_ReverseSingleExpense
(
    @ReferenceNumber VARCHAR(10),
    @InvoiceNo       VARCHAR(150),
    @SupplierID      VARCHAR(20),    -- ExpenseSummary.SupplierID (the supplier key)
    @Reason          VARCHAR(300),
    @User            VARCHAR(100)
)
AS
/*  [96] 2026-10-15. Reverses a saved SINGLE-mode expense (AddExpenseDevExFrm › Posted › Reverse): mirror ticket dated like
    the original, supplier-ledger REVERSAL row, PO landed cost taken back out of the shipment's lots, header + lines CANCELLED.
    Refused when anything was paid, the shipment's stock was already deducted, or the GL month is closed (59900).
    Rules: SQL/[96]-2026-10-15j_Reverse_SingleExpense_ManualJV.sql. Error handling per
    docs/standards/2026-10-14_Posting_Proc_Error_Handling.md.
    Result set: Status 1, ReversalTicketNumber, InventoryCostBackedOut, Message. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @msg NVARCHAR(700);

    BEGIN TRY
        BEGIN TRANSACTION;

        IF LTRIM(RTRIM(ISNULL(@Reason, ''))) = ''
            THROW 56201, 'Enter the reason for the reversal.', 1;

        -- the same lock as sp_EditSingleExpense ([96] patch): an edit and a reversal of one expense never run together
        DECLARE @Lock INT, @LockRes NVARCHAR(255) = N'EXPREV:' + RTRIM(ISNULL(@SupplierID, N'')) + N':' + RTRIM(ISNULL(@ReferenceNumber, N''));
        EXEC @Lock = sp_getapplock @Resource = @LockRes, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 15000;
        IF @Lock < 0
            THROW 56202, 'Another user is working on this expense right now. Please try again.', 1;

        ------------------------------------------------------------------
        -- the expense, read under lock
        ------------------------------------------------------------------
        DECLARE @n INT, @Status VARCHAR(50), @Amount DECIMAL(18,2), @Balance DECIMAL(18,2), @AmountPaid DECIMAL(18,2),
                @Withheld DECIMAL(18,2), @BatchID BIGINT, @ShipmentNo VARCHAR(10), @ExpAdded DATETIME;

        SELECT @n = COUNT(*)
        FROM dbo.ExpenseSummary WITH (UPDLOCK, ROWLOCK)
        WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @InvoiceNo AND SupplierID = @SupplierID AND PostingMode = 'SINGLE';
        IF @n <> 1
            THROW 56203, 'Single expense not found for this Reference / Invoice / Supplier.', 1;

        SELECT @Status = Status, @Amount = CAST(ISNULL(Amount, 0) AS DECIMAL(18,2)), @Balance = ISNULL(Balance, 0),
               @AmountPaid = ISNULL(AmountPaid, 0),
               @Withheld = ISNULL(EWTWithheld, 0) + ISNULL(DiscountWithheld, 0) + ISNULL(OffsetWithheld, 0),
               @BatchID = BatchReferenceID, @ShipmentNo = LTRIM(RTRIM(ISNULL(ShipmentNo, ''))), @ExpAdded = DateTimeAdded
        FROM dbo.ExpenseSummary
        WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @InvoiceNo AND SupplierID = @SupplierID AND PostingMode = 'SINGLE';

        IF @Status = 'CANCELLED'
           OR EXISTS (SELECT 1 FROM dbo.ExpenseSingleReversal WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @InvoiceNo AND SupplierID = @SupplierID)
            THROW 56204, 'This expense is already reversed (cancelled).', 1;

        IF ISNULL(@Status, '') NOT IN ('POSTED', 'UNPAID')
        BEGIN
            SET @msg = N'This expense is ' + ISNULL(@Status, N'(no status)') + N': only an unpaid expense can be reversed. Reverse its payment voucher first (Supplier Voucher Reversal).';
            THROW 56205, @msg, 1;
        END

        IF @AmountPaid <> 0 OR @Withheld <> 0
           OR EXISTS (SELECT 1 FROM dbo.ExpenseMaster
                      WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @InvoiceNo AND BatchReferenceID = @BatchID
                        AND (ISNULL(AmountPaid, 0) <> 0 OR ISNULL(EWTAmount, 0) <> 0 OR ISNULL(DiscountAmount, 0) <> 0 OR ISNULL(OffsetAmount, 0) <> 0))
            THROW 56206, 'This expense already has a payment, withholding or offset applied. Reverse the payment voucher first (Supplier Voucher Reversal).', 1;

        ------------------------------------------------------------------
        -- its posting ticket (exactly one, balanced)
        ------------------------------------------------------------------
        DECLARE @Ticket VARCHAR(50), @nTickets INT;
        SELECT @nTickets = COUNT(DISTINCT TicketReference), @Ticket = MIN(TicketReference)
        FROM dbo.ExpenseMaster
        WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @InvoiceNo AND BatchReferenceID = @BatchID;

        IF @nTickets <> 1
           OR (SELECT COUNT(*) FROM dbo.TicketMaster
               WHERE TicketNumber = @Ticket AND ReferenceNumber = @ReferenceNumber AND ReferenceKey = @InvoiceNo
                 AND Mnemonic = 'SINGLE' AND ISNULL(Product, '') <> 'REVERSAL') <> 1
            THROW 56208, 'This expense has no posting ticket of its own (a balance-forward load, or its ticket was changed by hand), so it cannot be reversed here.', 1;

        IF EXISTS (SELECT 1 FROM dbo.TicketMaster
                   WHERE ReferenceNumber = @ReferenceNumber AND ReferenceKey = @InvoiceNo AND Mnemonic = 'SINGLE' AND Product = 'REVERSAL')
            THROW 56204, 'A reversal ticket already exists for this expense.', 1;

        DECLARE @TD DECIMAL(18,2), @TC DECIMAL(18,2), @nLines INT;
        SELECT @TD = ISNULL(SUM(Debit), 0), @TC = ISNULL(SUM(Credit), 0), @nLines = COUNT(*)
        FROM dbo.TicketDetails
        WHERE TicketNumber = @Ticket AND ReferenceNumber = @ReferenceNumber AND ReferenceKey = @InvoiceNo;
        IF @nLines = 0 OR @TD <> @TC
            THROW 56208, 'This expense''s posting ticket has no lines or does not balance, so it cannot be reversed here.', 1;

        ------------------------------------------------------------------
        -- its supplier-ledger row (exactly one, open), and the balance it set
        ------------------------------------------------------------------
        DECLARE @L TABLE (TRN_SEQ_NO DECIMAL(10,0), SupplierKey CHAR(6), SupplierID VARCHAR(50), Description VARCHAR(5000), ReferenceKey VARCHAR(50),
                          InvoiceNo VARCHAR(50), Credit DECIMAL(18,2), TotalAmount DECIMAL(18,2), TransactionDate DATETIME);
        INSERT INTO @L (TRN_SEQ_NO, SupplierKey, SupplierID, Description, ReferenceKey, InvoiceNo, Credit, TotalAmount, TransactionDate)
        SELECT TRN_SEQ_NO, SupplierKey, SupplierID, Description, ReferenceKey, InvoiceNo, ISNULL(Credit, 0), ISNULL(TotalAmount, 0), TransactionDate
        FROM dbo.SupplierLedger WITH (UPDLOCK, ROWLOCK)
        WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @InvoiceNo AND BatchReferenceID = @BatchID
          AND (SupplierKey = @SupplierID OR SupplierID = @SupplierID)
          AND TransCode = 'SNGLE' AND ISNULL(ErrorCorrectTag, 0) = 0;
        IF (SELECT COUNT(*) FROM @L) <> 1
            THROW 56209, 'The supplier ledger does not hold exactly one open posting row for this expense, so it cannot be reversed here.', 1;

        IF @Balance <> (SELECT Credit FROM @L)
        BEGIN
            SELECT @msg = N'The expense balance (' + CONVERT(NVARCHAR(30), @Balance) + N') is not what its posting left (' + CONVERT(NVARCHAR(30), Credit)
                        + N'): something has been applied to it. Nothing was reversed.' FROM @L;
            THROW 56207, @msg, 1;
        END

        ------------------------------------------------------------------
        -- PO landed cost: take it back out, only if the shipment's stock is untouched
        ------------------------------------------------------------------
        DECLARE @InvCost DECIMAL(18,2) = 0, @PerUnit DECIMAL(18,2) = 0, @BaseQty DECIMAL(18,3), @BaseBranch VARCHAR(5),
                @nRows INT, @nDed INT, @nCopies INT, @nLater INT, @POStatus VARCHAR(30), @Held BIT = 0;
        -- since 2026-09-25 09:48 (the same on every tier) the posting adds ONLY its inventory legs / base qty to the lots;
        -- before that it added a different amount (the whole invoice, other divisors), which can't be taken back out exactly
        DECLARE @CostRuleFrom DATETIME = '2026-09-25T09:49:00';

        IF @ShipmentNo NOT IN ('', 'CONVERSION')
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.fn_InventoryCostAccounts())
                THROW 56210, 'Inventory costing root account (JournalEntryMapping EXP-INVCOST-ROOT) is not configured, so the shipment''s landed cost cannot be backed out.', 1;

            SELECT @InvCost = ISNULL(SUM(ISNULL(td.Debit, 0) - ISNULL(td.Credit, 0)), 0)
            FROM dbo.TicketDetails AS td
            WHERE td.TicketNumber = @Ticket AND td.ReferenceNumber = @ReferenceNumber AND td.ReferenceKey = @InvoiceNo
              AND td.AccountCode IN (SELECT a.AccountCode FROM dbo.fn_InventoryCostAccounts() AS a);
        END

        IF @InvCost <> 0
        BEGIN
            IF @ExpAdded IS NULL OR @ExpAdded < @CostRuleFrom
            BEGIN
                SET @msg = N'This expense was posted on ' + ISNULL(CONVERT(NVARCHAR(16), @ExpAdded, 120), N'(unknown)') + N', before the 2026-09-25 costing rule: '
                         + N'the cost it added to shipment ' + @ShipmentNo + N' can''t be recomputed exactly, so it cannot be reversed here. Book a correcting entry instead.';
                THROW 56216, @msg, 1;
            END

            SELECT @BaseQty = b.BaseQty, @BaseBranch = b.BaseBranch FROM dbo.fn_InvShipmentBase() AS b WHERE b.ShipmentNo = @ShipmentNo;

            -- a received PO waiting for its final cost holds its lots at Available = 0 (spu_ConfirmPOFinalCost releases them):
            -- held, not deducted
            SELECT @POStatus = MAX(p.Status) FROM dbo.POSUMMARY AS p WHERE p.ShipmentNo = @ShipmentNo;
            IF @POStatus IN ('RECEIVED', 'FOR CONFIRMATION') SET @Held = 1;

            DECLARE @nDates INT = (SELECT COUNT(DISTINCT x.DateReceived) FROM dbo.Inventory AS x WHERE x.ShipmentNo = @ShipmentNo);

            SELECT @nRows   = COUNT(*),
                   @nDed    = ISNULL(SUM(CASE WHEN ISNULL(i.Available, 0) < ISNULL(i.Quantity, 0)
                                               AND NOT (@Held = 1 AND ISNULL(i.Available, 0) = 0) THEN 1 ELSE 0 END), 0),
                   @nCopies = ISNULL(SUM(CASE WHEN i.Branch <> ISNULL(@BaseBranch, i.Branch) THEN 1 ELSE 0 END), 0),
                   -- a lot received after the expense never got its cost; one received the same day may or may not have
                   @nLater  = ISNULL(SUM(CASE WHEN i.DateReceived > CAST(@ExpAdded AS DATE) THEN 1
                                              WHEN i.DateReceived = CAST(@ExpAdded AS DATE) AND @nDates > 1 THEN 1
                                              ELSE 0 END), 0)
            FROM dbo.Inventory AS i WITH (UPDLOCK, HOLDLOCK)
            WHERE i.ShipmentNo = @ShipmentNo;

            IF @nDed > 0 OR @nCopies > 0
            BEGIN
                SET @msg = N'Stock of shipment ' + @ShipmentNo + N' has already been sold, transferred or deducted ('
                         + CAST(@nDed AS NVARCHAR(10)) + N' of ' + CAST(@nRows AS NVARCHAR(10)) + N' lot(s) used'
                         + CASE WHEN @nCopies > 0 THEN N', ' + CAST(@nCopies AS NVARCHAR(10)) + N' at other branches' ELSE N'' END
                         + N'), so it already carries this expense''s cost. The expense cannot be reversed; book a correcting entry instead.';
                THROW 56211, @msg, 1;
            END

            IF @nLater > 0
            BEGIN
                SET @msg = N'Shipment ' + @ShipmentNo + N' received ' + CAST(@nLater AS NVARCHAR(10)) + N' lot(s) on or after the day this expense was posted; '
                         + N'they may not carry its cost, so it cannot be taken back out evenly. Book a correcting entry instead.';
                THROW 56212, @msg, 1;
            END

            IF ISNULL(@BaseQty, 0) <= 0
                THROW 56213, 'The linked shipment has no received quantity to back the cost out of.', 1;

            -- the posting added ROUND(legs / base qty, 2) to every row (Cost is DECIMAL(18,2)); take exactly that back
            SET @PerUnit = ROUND(@InvCost / @BaseQty, 2);
            UPDATE dbo.Inventory SET Cost = Cost - @PerUnit WHERE ShipmentNo = @ShipmentNo;

            IF EXISTS (SELECT 1 FROM dbo.Inventory WHERE ShipmentNo = @ShipmentNo AND Cost < 0)
                THROW 56214, 'Backing the cost out would make the shipment''s unit cost negative. Check the shipment''s cost history first; nothing was reversed.', 1;
        END

        ------------------------------------------------------------------
        -- GL: mirror ticket, dated like the original (a closed month -> 59900)
        ------------------------------------------------------------------
        DECLARE @NewTicket VARCHAR(20);
        EXEC GetTicketNumber @NewTicket OUTPUT;

        INSERT INTO dbo.TicketMaster
            (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber,
             ReferenceNumber, ReferenceKey, Owner, Particulars,
             EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
        SELECT CAST(TicketDate AS DATE), SupplementaryNumber, BranchCode, Origin, @NewTicket,
               ReferenceNumber, ReferenceKey, Owner, LEFT('(REVERSAL) ' + ISNULL(Particulars, ''), 7000),
               @User, CheckedBy, ApprovedBy, Status, Mnemonic, 'REVERSAL'
        FROM dbo.TicketMaster
        WHERE TicketNumber = @Ticket AND ReferenceNumber = @ReferenceNumber AND ReferenceKey = @InvoiceNo
          AND Mnemonic = 'SINGLE' AND ISNULL(Product, '') <> 'REVERSAL';

        INSERT INTO dbo.TicketDetails
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter, Particulars)
        SELECT CAST(TicketDate AS DATE), SupplementaryNumber, BranchCode, ReferenceKey,
               @NewTicket, ReferenceNumber, AccountCode, Credit, Debit, CostCenter, Particulars
        FROM dbo.TicketDetails
        WHERE TicketNumber = @Ticket AND ReferenceNumber = @ReferenceNumber AND ReferenceKey = @InvoiceNo;

        ------------------------------------------------------------------
        -- supplier ledger: tag the posting row, add the REVERSAL row (trg_SupplierLedger_Recalc re-chains)
        ------------------------------------------------------------------
        UPDATE s SET s.ErrorCorrectTag = 1
        FROM dbo.SupplierLedger AS s
        INNER JOIN @L AS l ON l.TRN_SEQ_NO = s.TRN_SEQ_NO AND l.SupplierKey = s.SupplierKey;

        DECLARE @LedgerSupplier VARCHAR(50) = (SELECT SupplierID FROM @L);
        INSERT INTO dbo.SupplierLedger
            (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate,
             Description, TransCode, TransactionDate, ReferenceNumber,
             ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance,
             TransactedBy, ApprovedBy, TotalAmount, PaymentType,
             ErrorCorrectTag, TicketReference, BatchReferenceID)
        SELECT dbo.func_getLastID(@LedgerSupplier), l.SupplierKey, l.SupplierID, GETDATE(),
               LEFT('(REVERSAL) ' + ISNULL(l.Description, ''), 5000), 'SNGLE', l.TransactionDate, @ReferenceNumber,
               l.ReferenceKey, l.InvoiceNo, 0, l.Credit, 0, 0,
               LEFT(@User, 50), '*', l.TotalAmount, 'REVERSAL',
               1, @NewTicket, @BatchID
        FROM @L AS l;

        ------------------------------------------------------------------
        -- header + lines CANCELLED, nothing owed; log
        ------------------------------------------------------------------
        UPDATE dbo.ExpenseSummary
        SET Status = 'CANCELLED', Balance = 0, UpdatedBy = LEFT(@User, 30), DateTimeUpdated = GETDATE()
        WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @InvoiceNo AND SupplierID = @SupplierID AND PostingMode = 'SINGLE';

        UPDATE dbo.ExpenseMaster
        SET Status = 'CANCELLED', Balance = 0
        WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @InvoiceNo AND BatchReferenceID = @BatchID;

        INSERT INTO dbo.ExpenseSingleReversal
            (ReferenceNumber, InvoiceNo, SupplierID, BatchReferenceID, OriginalTicketNumber, ReversalTicketNumber, Amount,
             ShipmentNo, InventoryCostBackedOut, CostPerUnitBackedOut, Reason, ReversedBy)
        VALUES
            (@ReferenceNumber, @InvoiceNo, @SupplierID, @BatchID, @Ticket, @NewTicket, @Amount,
             NULLIF(@ShipmentNo, ''), @InvCost, @PerUnit, LTRIM(RTRIM(@Reason)), @User);

        ------------------------------------------------------------------
        -- post-check: original + reversal net to zero per branch / account
        ------------------------------------------------------------------
        IF EXISTS (SELECT 1 FROM dbo.TicketDetails
                   WHERE TicketNumber IN (@Ticket, @NewTicket) AND ReferenceNumber = @ReferenceNumber AND ReferenceKey = @InvoiceNo
                   GROUP BY BranchCode, AccountCode
                   HAVING SUM(Debit) <> SUM(Credit))
           OR (SELECT ISNULL(SUM(Debit), 0) FROM dbo.TicketDetails WHERE TicketNumber = @NewTicket AND ReferenceNumber = @ReferenceNumber) <> @TD
            THROW 56215, 'Reversal post-check failed: the reversal ticket does not offset the original. Nothing was reversed.', 1;

        COMMIT TRANSACTION;

        SELECT 1 AS Status, @NewTicket AS ReversalTicketNumber, @InvCost AS InventoryCostBackedOut,
               'Expense ' + @ReferenceNumber + ' / ' + @InvoiceNo + ' reversed (reversal ticket ' + @NewTicket + ')'
               + CASE WHEN @InvCost <> 0 THEN '; ' + CONVERT(VARCHAR(30), @PerUnit) + ' per unit taken back out of shipment ' + @ShipmentNo ELSE '' END
               + '.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

------------------------------------------------------------------
-- 3. spu_ReverseManualJournalVoucher
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE dbo.spu_ReverseManualJournalVoucher
(
    @ReferenceNo VARCHAR(10),
    @Reason      VARCHAR(300),
    @User        VARCHAR(50)
)
AS
/*  [96] 2026-10-15. Reverses a saved Manual JV (ManualJournalVoucherMultiBranchFrm › Posted › Reverse): one mirror ticket for
    all its branches, dated like the original; its own bank recon items voided. Refused when a recon item is already cleared
    by the bank, a reconciliation month at or after the item's month is LOCKED, or the GL month is closed (59900).
    The voucher rows are kept (View Details); trg_ManualJournalVoucher_NoDeleteAfterReversal stops an edit re-posting it.
    Rules: SQL/[96]-2026-10-15j_Reverse_SingleExpense_ManualJV.sql. Error handling per
    docs/standards/2026-10-14_Posting_Proc_Error_Handling.md.
    Result set: Status 1, ReferenceNo, ReversalTicketNumber, ReconItemsVoided, Message. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @msg NVARCHAR(700);

    BEGIN TRY
        BEGIN TRANSACTION;

        IF LTRIM(RTRIM(ISNULL(@Reason, ''))) = ''
            THROW 59221, 'Enter the reason for the reversal.', 1;

        DECLARE @Lock INT, @LockRes NVARCHAR(255) = N'MANUALJV:' + ISNULL(@ReferenceNo, N'');   -- same lock as sp_EditManualJournalVoucher
        EXEC @Lock = sp_getapplock @Resource = @LockRes, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 15000;
        IF @Lock < 0
            THROW 59222, 'Another user is saving this journal voucher right now. Please try again.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.ManualJournalVoucher WITH (UPDLOCK, ROWLOCK) WHERE ReferenceNo = @ReferenceNo)
            THROW 59223, 'Journal voucher not found for this Reference No.', 1;

        IF EXISTS (SELECT 1 FROM dbo.ManualJournalVoucherReversal WHERE ReferenceNo = @ReferenceNo)
           OR EXISTS (SELECT 1 FROM dbo.TicketMaster
                      WHERE ReferenceNumber = @ReferenceNo AND Origin = 'JV' AND Product = 'REVERSAL'
                        AND TicketNumber NOT IN (SELECT TicketNumber FROM dbo.ManualJournalVoucher WHERE ReferenceNo = @ReferenceNo))
            THROW 59224, 'This journal voucher is already reversed.', 1;

        ------------------------------------------------------------------
        -- its own tickets, whole
        ------------------------------------------------------------------
        DECLARE @Orig TABLE (TicketNumber VARCHAR(50), BranchCode VARCHAR(5), TicketDate DATETIME, SupplementaryNumber TINYINT);
        INSERT INTO @Orig (TicketNumber, BranchCode, TicketDate, SupplementaryNumber)
        SELECT tm.TicketNumber, tm.BranchCode, tm.TicketDate, tm.SupplementaryNumber
        FROM dbo.TicketMaster AS tm
        WHERE tm.ReferenceNumber = @ReferenceNo
          AND tm.TicketNumber IN (SELECT v.TicketNumber FROM dbo.ManualJournalVoucher AS v WHERE v.ReferenceNo = @ReferenceNo)
          AND tm.Origin = 'JV' AND ISNULL(tm.Product, '') <> 'REVERSAL';

        DECLARE @VTotal DECIMAL(18,2), @nBranches INT, @OrigTicket VARCHAR(50), @TD DECIMAL(18,2), @TC DECIMAL(18,2);
        SELECT @VTotal = CAST(ISNULL(SUM(ISNULL(TotalAmount, 0)), 0) AS DECIMAL(18,2)), @nBranches = COUNT(DISTINCT BranchCode), @OrigTicket = MIN(TicketNumber)
        FROM dbo.ManualJournalVoucher WHERE ReferenceNo = @ReferenceNo;

        SELECT @TD = ISNULL(SUM(td.Debit), 0), @TC = ISNULL(SUM(td.Credit), 0)
        FROM dbo.TicketDetails AS td
        INNER JOIN @Orig AS o ON o.TicketNumber = td.TicketNumber AND o.BranchCode = td.BranchCode
        WHERE td.ReferenceNumber = @ReferenceNo;

        IF EXISTS (SELECT 1 FROM dbo.ManualJournalVoucher AS v
                   WHERE v.ReferenceNo = @ReferenceNo
                     AND NOT EXISTS (SELECT 1 FROM @Orig AS o WHERE o.TicketNumber = v.TicketNumber AND o.BranchCode = v.BranchCode))
           OR @TD <> @VTotal OR @TD <> @TC OR @TD = 0
            THROW 59225, 'This journal voucher''s GL ticket is missing or does not match the voucher. Open it with Edit and Save Changes to repair it first; nothing was reversed.', 1;

        ------------------------------------------------------------------
        -- its bank recon items: cleared or in a locked month -> refused; else voided
        ------------------------------------------------------------------
        DECLARE @Items TABLE (ReconID INT PRIMARY KEY, AccountCode VARCHAR(20), ItemType VARCHAR(5), Amount DECIMAL(18,2),
                              IsResolved INT, ResolvedReason VARCHAR(500), ItemPeriod DATE, LockedP DATE);
        INSERT INTO @Items (ReconID, AccountCode, ItemType, Amount, IsResolved, ResolvedReason, ItemPeriod, LockedP)
        SELECT b.ReconID, b.AccountCode, b.ItemType, b.Amount, CAST(ISNULL(b.IsResolved, 0) AS INT), ISNULL(b.ResolvedReason, ''),
               ISNULL(h.PeriodEnd, b.PeriodEnd),
               (SELECT MIN(l.PeriodEnd) FROM dbo.BankReconHeader AS l WITH (HOLDLOCK)
                WHERE l.BranchCode = ISNULL(h.BranchCode, b.BranchCode) AND l.AccountCode = b.AccountCode
                  AND l.Status = 'LOCKED' AND l.PeriodEnd >= ISNULL(h.PeriodEnd, b.PeriodEnd))
        FROM dbo.BankStatementRecon AS b WITH (UPDLOCK, ROWLOCK)
        LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
        WHERE b.ReferenceNo = @ReferenceNo AND b.SourceModule = 'MANUAL-JV' AND b.SourceRef = @ReferenceNo
          AND ISNULL(b.ResolvedReason, '') <> 'REVERSED' AND ISNULL(b.ResolvedReason, '') NOT LIKE 'VOIDED%';

        SELECT TOP (1) @msg = N'The ' + i.ItemType + N' item of bank account ' + i.AccountCode + N' (' + CONVERT(NVARCHAR(30), i.Amount)
                            + N') is already cleared / closed in the bank reconciliation (item month ' + CONVERT(NVARCHAR(10), i.ItemPeriod, 120) + N')'
                            + CASE WHEN i.ResolvedReason <> '' THEN N', reason: ' + i.ResolvedReason ELSE N'' END
                            + N'. Mark it uncleared in Bank Recon first, or book a correcting entry. Nothing was reversed.'
        FROM @Items AS i WHERE i.IsResolved = 1 ORDER BY i.ReconID;
        IF @msg IS NOT NULL THROW 59226, @msg, 1;

        SET @msg = NULL;
        SELECT TOP (1) @msg = N'Bank reconciliation of account ' + i.AccountCode + N' is locked for the month ending ' + CONVERT(NVARCHAR(10), i.LockedP, 120)
                            + N'; this voucher''s ' + i.ItemType + N' item (' + CONVERT(NVARCHAR(10), i.ItemPeriod, 120) + N') counts in it. Have the period unlocked first. Nothing was reversed.'
        FROM @Items AS i WHERE i.LockedP IS NOT NULL ORDER BY i.ReconID;
        IF @msg IS NOT NULL THROW 59227, @msg, 1;

        ------------------------------------------------------------------
        -- GL: one mirror ticket number for every branch, dated like the original (a closed month -> 59900)
        ------------------------------------------------------------------
        DECLARE @NewTicket VARCHAR(20);
        EXEC GetTicketNumber @NewTicket OUTPUT;

        INSERT INTO dbo.TicketMaster
            (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber,
             ReferenceNumber, ReferenceKey, Owner, Particulars,
             EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
        SELECT CAST(tm.TicketDate AS DATE), tm.SupplementaryNumber, tm.BranchCode, tm.Origin, @NewTicket,
               tm.ReferenceNumber, tm.ReferenceKey, tm.Owner, LEFT('(REVERSAL) ' + ISNULL(tm.Particulars, ''), 7000),
               @User, tm.CheckedBy, tm.ApprovedBy, tm.Status, tm.Mnemonic, 'REVERSAL'
        FROM dbo.TicketMaster AS tm
        INNER JOIN @Orig AS o ON o.TicketNumber = tm.TicketNumber AND o.BranchCode = tm.BranchCode
                             AND o.TicketDate = tm.TicketDate AND o.SupplementaryNumber = tm.SupplementaryNumber
        WHERE tm.ReferenceNumber = @ReferenceNo;

        INSERT INTO dbo.TicketDetails
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
             TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter, Particulars)
        SELECT CAST(td.TicketDate AS DATE), td.SupplementaryNumber, td.BranchCode, td.ReferenceKey,
               @NewTicket, td.ReferenceNumber, td.AccountCode, td.Credit, td.Debit, td.CostCenter, td.Particulars
        FROM dbo.TicketDetails AS td
        INNER JOIN @Orig AS o ON o.TicketNumber = td.TicketNumber AND o.BranchCode = td.BranchCode
        WHERE td.ReferenceNumber = @ReferenceNo;

        ------------------------------------------------------------------
        -- void the recon items (hidden in every month; cleared in their own month)
        ------------------------------------------------------------------
        UPDATE b
        SET IsResolved      = 1,
            ResolvedDate    = GETDATE(),
            ResolvedBy      = @User,
            ResolvedReason  = 'VOIDED - MANUAL JV REVERSED',
            ClearedPeriodEnd = i.ItemPeriod,
            UpdatedBy       = @User,
            DateTimeUpdated = GETDATE()
        FROM dbo.BankStatementRecon AS b
        INNER JOIN @Items AS i ON i.ReconID = b.ReconID;

        DECLARE @nVoided INT = (SELECT COUNT(*) FROM @Items);

        INSERT INTO dbo.ManualJournalVoucherReversal
            (ReferenceNo, OriginalTicketNumber, ReversalTicketNumber, BranchCount, TotalAmount, ReconItemsVoided, Reason, ReversedBy)
        VALUES
            (@ReferenceNo, @OrigTicket, @NewTicket, @nBranches, @VTotal, @nVoided, LTRIM(RTRIM(@Reason)), @User);

        ------------------------------------------------------------------
        -- post-check: original + reversal net to zero per branch / account
        ------------------------------------------------------------------
        IF EXISTS (SELECT 1 FROM dbo.TicketDetails AS td
                   WHERE td.ReferenceNumber = @ReferenceNo
                     AND (td.TicketNumber = @NewTicket OR EXISTS (SELECT 1 FROM @Orig AS o WHERE o.TicketNumber = td.TicketNumber AND o.BranchCode = td.BranchCode))
                   GROUP BY td.BranchCode, td.AccountCode
                   HAVING SUM(td.Debit) <> SUM(td.Credit))
           OR (SELECT ISNULL(SUM(Debit), 0) FROM dbo.TicketDetails WHERE TicketNumber = @NewTicket AND ReferenceNumber = @ReferenceNo) <> @TD
            THROW 59228, 'Reversal post-check failed: the reversal ticket does not offset the original. Nothing was reversed.', 1;

        COMMIT TRANSACTION;

        SELECT 1 AS Status, @ReferenceNo AS ReferenceNo, @NewTicket AS ReversalTicketNumber, @nVoided AS ReconItemsVoided,
               'Journal voucher ' + @ReferenceNo + ' reversed (reversal ticket ' + @NewTicket + ')'
               + CASE WHEN @nVoided > 0 THEN '; ' + CAST(@nVoided AS VARCHAR(10)) + ' bank recon item(s) voided' ELSE '' END + '.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

------------------------------------------------------------------
-- 4. A reversed voucher's rows can't be deleted (the edit deletes and re-posts)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE TRIGGER dbo.trg_ManualJournalVoucher_NoDeleteAfterReversal
ON dbo.ManualJournalVoucher
AFTER DELETE
AS
/*  [96] 2026-10-15: a reversed journal voucher is final. sp_EditManualJournalVoucher deletes and re-posts the voucher; on a
    reversed one that would put the original back in the GL beside its reversal. Refused for every writer (59229). */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;   -- the THROW dooms the caller's transaction even when the caller runs with XACT_ABORT OFF
    IF EXISTS (SELECT 1 FROM deleted AS d INNER JOIN dbo.ManualJournalVoucherReversal AS r ON r.ReferenceNo = d.ReferenceNo)
    BEGIN
        DECLARE @msg NVARCHAR(400) = N'Journal voucher ' + (SELECT TOP (1) d.ReferenceNo FROM deleted AS d
                                                             INNER JOIN dbo.ManualJournalVoucherReversal AS r ON r.ReferenceNo = d.ReferenceNo)
                                   + N' was reversed (cancelled); it cannot be edited. Use Copy to New Entry to post a corrected voucher.';
        THROW 59229, @msg, 1;
    END
END
GO

------------------------------------------------------------------
-- 5. sp_EditSingleExpense: refuse a reversed expense (anchor patch)
-- 6. sp_GetSingleExpenseDetails: BlockedReason for it (anchor patch)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @def NVARCHAR(MAX), @anchor NVARCHAR(400), @new NVARCHAR(MAX), @cnt INT;

SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_EditSingleExpense'));
SET @anchor = N'    IF @CurAmountPaid > 0';
SET @cnt = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @anchor, N''))) / DATALENGTH(@anchor);
IF @cnt <> 1 THROW 59898, '[96] sp_EditSingleExpense anchor not found exactly once.', 1;
SET @new = REPLACE(@def, @anchor,
      N'    -- [96] 2026-10-15: a reversed (cancelled) expense is final' + NCHAR(13) + NCHAR(10)
    + N'    IF EXISTS (SELECT 1 FROM ExpenseSummary WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @OldInvoiceNo' + NCHAR(13) + NCHAR(10)
    + N'               AND SupplierID = @OldSupplierID AND PostingMode = ''SINGLE'' AND Status = ''CANCELLED'')' + NCHAR(13) + NCHAR(10)
    + N'        THROW 56110, ''This expense was reversed (cancelled); it cannot be edited. Use Copy to New Entry to post a corrected expense.'', 1;' + NCHAR(13) + NCHAR(10)
    + NCHAR(13) + NCHAR(10)
    + @anchor);
-- the duplicate-invoice rule (56104) ignores a reversed expense: its invoice no. may be posted again correctly
SET @def = @new;
SET @anchor = N'AND NOT (ReferenceNumber = @ReferenceNumber AND InvoiceNo = @OldInvoiceNo AND SupplierID = @OldSupplierID)';
SET @cnt = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @anchor, N''))) / DATALENGTH(@anchor);
IF @cnt <> 1 THROW 59898, '[96] sp_EditSingleExpense duplicate-check anchor not found exactly once.', 1;
SET @new = REPLACE(@def, @anchor, @anchor + N' AND ISNULL(Status, '''') <> ''CANCELLED''   -- [96]');
-- inside the transaction: the reversal's lock + a re-read under lock (a reversal or payment may have committed since the checks)
SET @def = @new;
SET @anchor = N'        DELETE FROM TicketDetails WHERE ReferenceNumber = @ReferenceNumber AND ReferenceKey = @OldInvoiceNo;';
SET @cnt = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @anchor, N''))) / DATALENGTH(@anchor);
IF @cnt <> 1 THROW 59898, '[96] sp_EditSingleExpense delete anchor not found exactly once.', 1;
SET @new = REPLACE(@def, @anchor,
      N'        -- [96] same lock as spu_ReverseSingleExpense; re-read under lock before deleting anything' + NCHAR(13) + NCHAR(10)
    + N'        DECLARE @H96Lock INT, @H96Res NVARCHAR(255) = N''EXPREV:'' + RTRIM(ISNULL(@OldSupplierID, N'''')) + N'':'' + RTRIM(ISNULL(@ReferenceNumber, N''''));' + NCHAR(13) + NCHAR(10)
    + N'        EXEC @H96Lock = sp_getapplock @Resource = @H96Res, @LockMode = ''Exclusive'', @LockOwner = ''Transaction'', @LockTimeout = 15000;' + NCHAR(13) + NCHAR(10)
    + N'        IF @H96Lock < 0' + NCHAR(13) + NCHAR(10)
    + N'            THROW 56111, ''Another user is working on this expense right now. Please try again.'', 1;' + NCHAR(13) + NCHAR(10)
    + N'        IF EXISTS (SELECT 1 FROM ExpenseSummary WITH (UPDLOCK, ROWLOCK)' + NCHAR(13) + NCHAR(10)
    + N'                   WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @OldInvoiceNo AND SupplierID = @OldSupplierID AND PostingMode = ''SINGLE''' + NCHAR(13) + NCHAR(10)
    + N'                     AND (Status = ''CANCELLED'' OR ISNULL(AmountPaid, 0) > 0))' + NCHAR(13) + NCHAR(10)
    + N'            THROW 56110, ''This expense was reversed or paid while it was being edited; nothing was saved.'', 1;' + NCHAR(13) + NCHAR(10)
    + NCHAR(13) + NCHAR(10)
    + @anchor);
EXEC sp_rename 'dbo.sp_EditSingleExpense', 'sp_EditSingleExpense_OLD_10152026200000';
EXEC (@new);

SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetSingleExpenseDetails'));
SET @anchor = N'WHEN es.AmountPaid > 0 THEN';
SET @cnt = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @anchor, N''))) / DATALENGTH(@anchor);
IF @cnt <> 1 THROW 59898, '[96] sp_GetSingleExpenseDetails anchor not found exactly once.', 1;
SET @new = REPLACE(@def, @anchor,
      N'WHEN es.Status = ''CANCELLED'' THEN ''This expense was reversed (cancelled); it cannot be edited.''   -- [96]' + NCHAR(13) + NCHAR(10)
    + N'            ' + @anchor);
-- the lines: the original posting only (a reversed expense also has its mirror ticket under the same reference / invoice,
-- and Copy to New Entry copies these lines)
SET @def = @new;
SET @anchor = N'AND td.ReferenceKey = @InvoiceNo';
SET @cnt = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @anchor, N''))) / DATALENGTH(@anchor);
IF @cnt <> 1 THROW 59898, '[96] sp_GetSingleExpenseDetails lines anchor not found exactly once.', 1;
SET @new = REPLACE(@def, @anchor, @anchor + NCHAR(13) + NCHAR(10)
    + N'      AND td.TicketNumber NOT IN (SELECT r.ReversalTicketNumber FROM dbo.ExpenseSingleReversal r'
    + N' WHERE r.ReferenceNumber = @ReferenceNumber AND r.InvoiceNo = @InvoiceNo)   -- [96] original lines only');
EXEC sp_rename 'dbo.sp_GetSingleExpenseDetails', 'sp_GetSingleExpenseDetails_OLD_10152026200000';
EXEC (@new);
GO

------------------------------------------------------------------
-- 7. sp_GetPostedSingleExpenses: + reversal columns
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.sp_GetPostedSingleExpenses', 'sp_GetPostedSingleExpenses_OLD_10152026200000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
/* ================================================================
   POST SINGLE EXPENSE — Posted Expenses tab support
   Read-only listing/detail SPs, safe to build independent of
   spu_PostExpenseV2's internals since they only SELECT.

   2026-09-14: Amount/Balance/AmountPaid returned as DECIMAL, not
   FORMAT()-ed VARCHAR.
   2026-09-22: added ShipmentNo (PO link) + @POLinkedOnly filter --
   AddExpenseDevExFrm.cs LoadPostedExpenses() / BtnViewPODetails_Click.
   [96] 2026-10-15: + ReversedBy, ReversedDate, ReverseReason (a reversed
   expense keeps Status CANCELLED; spu_ReverseSingleExpense).
   ================================================================ */
CREATE PROCEDURE [dbo].[sp_GetPostedSingleExpenses]
(
    @DateFrom     DATE = NULL,
    @DateTo       DATE = NULL,
    @BranchCode   VARCHAR(5) = NULL,   -- NULL = all branches
    @POLinkedOnly BIT = 0              -- 1 = only expenses linked to a PO
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        es.ReferenceNumber,
        es.InvoiceNo,
        es.SupplierID,
        s.SupplierName,
        MIN(em.BranchCode) AS BranchCode,   -- SINGLE mode is one branch per posting
        br.BranchName,
        es.ExpenseDate,
        es.Description AS Remarks,
        CAST(es.Amount AS DECIMAL(18,2)) AS Amount,
        CAST(es.Balance AS DECIMAL(18,2)) AS Balance,
        CAST(es.AmountPaid AS DECIMAL(18,2)) AS AmountPaid,
        es.Status,
        MIN(em.TicketReference) AS TicketNumber,
        es.ShipmentNo,
        rv.ReversedBy,                       -- [96]
        rv.ReversedDate,                     -- [96]
        rv.Reason AS ReverseReason           -- [96]
    FROM ExpenseSummary es
    JOIN Supplier s ON s.SupplierKey = es.SupplierID
    JOIN ExpenseMaster em
      ON em.ReferenceNumber = es.ReferenceNumber
     AND em.InvoiceNo = es.InvoiceNo
     AND em.BatchReferenceID = es.BatchReferenceID
    JOIN Branches br ON em.BranchCode=br.BranchCode
    LEFT JOIN dbo.ExpenseSingleReversal rv   -- [96]
      ON rv.ReferenceNumber = es.ReferenceNumber AND rv.InvoiceNo = es.InvoiceNo AND rv.SupplierID = es.SupplierID
    WHERE es.PostingMode = 'SINGLE'
      AND (@DateFrom IS NULL OR es.ExpenseDate >= @DateFrom)
      AND (@DateTo IS NULL OR es.ExpenseDate <= @DateTo)
      AND (@BranchCode IS NULL OR em.BranchCode = @BranchCode)
      AND (@POLinkedOnly = 0 OR LTRIM(RTRIM(ISNULL(es.ShipmentNo,''))) <> '')
    GROUP BY es.ReferenceNumber, es.InvoiceNo, es.SupplierID, s.SupplierName,
             es.ExpenseDate, es.Description, es.Amount, es.Balance, es.AmountPaid, es.Status, br.BranchName, es.ShipmentNo,
             rv.ReversedBy, rv.ReversedDate, rv.Reason
    ORDER BY es.ExpenseDate DESC, es.ReferenceNumber DESC;
END
GO

------------------------------------------------------------------
-- 8. sp_GetPostedManualJournalVouchers: + Status / reversal columns
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.sp_GetPostedManualJournalVouchers', 'sp_GetPostedManualJournalVouchers_OLD_10152026200000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE [dbo].[sp_GetPostedManualJournalVouchers]
    @DateFrom         DATE = NULL,
    @DateTo           DATE = NULL,
    @SingleBranchOnly BIT  = 0
AS
/*  Posted tab of both Manual JV screens. One row per reference.
    [86] 2026-10-14: + DatePrepared, LastModifiedBy, LastModifiedDate (edits keep the original PreparedBy);
    ControlNo from the voucher's own tickets (the TicketNumber its rows carry), not any ticket under the same number.
    [96] 2026-10-15: + Status (POSTED / CANCELLED), ReversedBy, ReversedDate, ReverseReason (spu_ReverseManualJournalVoucher). */
BEGIN
    SET NOCOUNT ON;

    SELECT
        (
            SELECT TOP 1 tm.ReferenceKey
            FROM dbo.TicketMaster tm
            WHERE tm.ReferenceNumber = a.ReferenceNo
              AND tm.TicketNumber IN (SELECT x.TicketNumber FROM dbo.ManualJournalVoucher x WHERE x.ReferenceNo = a.ReferenceNo)
            ORDER BY CASE WHEN tm.ReferenceKey IS NULL THEN 1 ELSE 0 END, tm.TicketNumber
        )                                                     AS ControlNo,
        a.ReferenceNo,
        MIN(a.VoucherDate)                                   AS VoucherDate,
        MAX(a.Remarks)                                       AS Remarks,
        COUNT(DISTINCT a.BranchCode)                         AS BranchCount,
        MAX(a.BranchCode)                                    AS BranchCode,   -- meaningful only when BranchCount = 1
        CAST(SUM(ISNULL(a.TotalAmount, 0)) AS DECIMAL(18,2)) AS TotalAmount,
        MAX(a.PreparedBy)                                    AS PreparedBy,
        MIN(a.DateAdded)                                     AS DatePrepared,       -- [86]
        MAX(a.LastModifiedBy)                                AS LastModifiedBy,     -- [86]
        MAX(a.LastModifiedDate)                              AS LastModifiedDate,   -- [86]
        CASE WHEN MAX(rv.ReferenceNo) IS NULL THEN 'POSTED' ELSE 'CANCELLED' END AS Status,   -- [96]
        MAX(rv.ReversedBy)                                   AS ReversedBy,         -- [96]
        MAX(rv.ReversedDate)                                 AS ReversedDate,       -- [96]
        MAX(rv.Reason)                                       AS ReverseReason       -- [96]
    FROM dbo.ManualJournalVoucher a
    LEFT JOIN dbo.ManualJournalVoucherReversal rv ON rv.ReferenceNo = a.ReferenceNo   -- [96] one row per reference (PK)
    WHERE (@DateFrom IS NULL OR a.VoucherDate >= @DateFrom)
      AND (@DateTo   IS NULL OR a.VoucherDate <= @DateTo)
    GROUP BY a.ReferenceNo
    HAVING (@SingleBranchOnly = 0 OR COUNT(DISTINCT a.BranchCode) = 1)
    ORDER BY MIN(a.VoucherDate) DESC, a.ReferenceNo DESC;
END
GO

------------------------------------------------------------------
-- 9. Readers that must not count a reversed expense (each patched only if installed; anchor must occur once)
--    fn_rpt_exc_AP_Findings AP-STATUS-VS-BALANCE: CANCELLED at 0 is by design (a CANCELLED one with a balance still shows)
--    sp_rpt_ItemCostingRecon_List / fn_rpt_exc_AP_ShipmentCosting: a reversed expense is not a linked expense any more
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @p TABLE (n INT IDENTITY, Obj SYSNAME, Anchor NVARCHAR(400), Addition NVARCHAR(400));
INSERT INTO @p (Obj, Anchor, Addition) VALUES
 ('fn_rpt_exc_AP_Findings', N'WHERE es.Balance IS NOT NULL',
  N' AND (ISNULL(es.Status, '''') <> ''CANCELLED'' OR ABS(es.Balance) >= 0.005)   -- [96] a reversed expense owes 0 by design'),
 ('sp_rpt_ItemCostingRecon_List', N'    WHERE es.PostingMode = ''SINGLE''',
  N' AND ISNULL(es.Status, '''') <> ''CANCELLED''   -- [96] a reversed expense is not linked any more'),
 ('fn_rpt_exc_AP_ShipmentCosting', N'    WHERE es.PostingMode = ''SINGLE'' AND ISNULL(es.ShipmentNo, '''') NOT IN ('''', ''CONVERSION'')',
  N' AND ISNULL(es.Status, '''') <> ''CANCELLED''   -- [96]');
DECLARE @i INT = 1, @obj SYSNAME, @def NVARCHAR(MAX), @anchor NVARCHAR(400), @add NVARCHAR(400), @cnt INT, @new NVARCHAR(MAX), @bak SYSNAME, @m NVARCHAR(300);
WHILE @i <= 3
BEGIN
    SELECT @obj = Obj, @anchor = Anchor, @add = Addition FROM @p WHERE n = @i;
    SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.' + @obj));
    IF @def IS NULL
        PRINT '[96] ' + @obj + ' not installed here; skipped (its [96] rule is in its source file).';
    ELSE IF @def LIKE '%[[]96]%'
        PRINT '[96] ' + @obj + ' already carries [96].';
    ELSE
    BEGIN
        SET @cnt = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @anchor, N''))) / DATALENGTH(@anchor);
        IF @cnt <> 1
        BEGIN
            SET @m = N'[96] ' + @obj + N' anchor not found exactly once (' + CAST(@cnt AS NVARCHAR(10)) + N').';
            THROW 59898, @m, 1;
        END
        SET @new = REPLACE(@def, @anchor, @anchor + @add);
        SET @bak = @obj + '_OLD_10152026200000';
        SET @m = N'dbo.' + @obj;
        EXEC sp_rename @m, @bak;
        EXEC (@new);
    END
    SET @i += 1;
END
GO

------------------------------------------------------------------
-- 10. Post-check, then commit
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF OBJECT_ID('dbo.spu_ReverseSingleExpense', 'P') IS NULL OR OBJECT_ID('dbo.spu_ReverseManualJournalVoucher', 'P') IS NULL
    SET @msg = N'a reversal proc was not created';
ELSE IF OBJECT_ID('dbo.trg_ManualJournalVoucher_NoDeleteAfterReversal', 'TR') IS NULL
    SET @msg = N'the voucher trigger was not created';
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_EditSingleExpense')) NOT LIKE '%56110%'
     OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_EditSingleExpense')) NOT LIKE '%56111%'
     OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_EditSingleExpense')) NOT LIKE '%<> ''CANCELLED''   -- [[]96]%'
     OR (OBJECT_ID('dbo.sp_rpt_ItemCostingRecon_List') IS NOT NULL AND OBJECT_DEFINITION(OBJECT_ID('dbo.sp_rpt_ItemCostingRecon_List')) NOT LIKE '%[[]96]%')
     OR (OBJECT_ID('dbo.fn_rpt_exc_AP_ShipmentCosting') IS NOT NULL AND OBJECT_DEFINITION(OBJECT_ID('dbo.fn_rpt_exc_AP_ShipmentCosting')) NOT LIKE '%[[]96]%')
     OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetSingleExpenseDetails')) NOT LIKE '%[[]96]%'
     OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetPostedSingleExpenses')) NOT LIKE '%ExpenseSingleReversal%'
     OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetPostedManualJournalVouchers')) NOT LIKE '%ManualJournalVoucherReversal%'
    SET @msg = N'a patched proc is not the [96] text';
ELSE IF OBJECT_ID('dbo.sp_EditSingleExpense_OLD_10152026200000', 'P') IS NULL OR OBJECT_ID('dbo.sp_GetSingleExpenseDetails_OLD_10152026200000', 'P') IS NULL
     OR OBJECT_ID('dbo.sp_GetPostedSingleExpenses_OLD_10152026200000', 'P') IS NULL OR OBJECT_ID('dbo.sp_GetPostedManualJournalVouchers_OLD_10152026200000', 'P') IS NULL
    SET @msg = N'a backup is missing';
ELSE IF OBJECT_ID('dbo.fn_rpt_exc_AP_Findings') IS NOT NULL AND OBJECT_DEFINITION(OBJECT_ID('dbo.fn_rpt_exc_AP_Findings')) NOT LIKE '%[[]96]%'
    SET @msg = N'fn_rpt_exc_AP_Findings was not patched';

IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[96] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59897, @msg, 1;
END

COMMIT TRANSACTION;
PRINT '[96] committed: spu_ReverseSingleExpense, spu_ReverseManualJournalVoucher, the 2 log tables, the voucher trigger, 4 procs patched.';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
