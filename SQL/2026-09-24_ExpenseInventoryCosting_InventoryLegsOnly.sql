/* ================================================================
   2026-09-24: PO-linked expense costing -- incorporate ONLY the
   inventory legs, not the whole invoice amount.
   (Reporting/ItemCostingReconReport.cs + spu_PostExpenseV2)
   ================================================================
   PROBLEM (user-reported, reproduced on CORECSJFC2026_STAGING):
     ExpenseSummary 30437 (SI-202610696, PO/ShipmentNo 11008) has
     Amount = 151,359.27, but its ticket 14287 only debits
     101040201 INVENTORY - VAT EXEMPT for 118,199.35 -- the rest is
     DR 20103 Accrued Expenses Payable 33,159.92 (+ credits to 507,
     EWT, advances). Two places used the whole invoice amount as the
     landed-cost increment:
       - spu_PostExpenseV2: @TotalAmount = SUM(Debit) of the entry was
         spread over the shipment into Inventory.Cost.
       - sp_rpt_ItemCostingRecon_Header/_Detail: es.Amount.

   FIX (confirmed with user: fix both; "inventory" = the whole 10104
   INVENTORY subtree, i.e. on-hand AND in-transit accounts):
     1. JournalEntryMapping row EXP-INVCOST-ROOT -> AccountCode 10104,
        so no GL code is hardcoded in any proc body (house rule).
     2. dbo.fn_InventoryCostAccounts() -- inline TVF expanding that
        root through ChartOfAccounts.SummaryAccount (recursive), so a
        future inventory sub-account is picked up automatically.
        Verified identical hierarchy on DEV and STAGING:
        10104 > 1010401 > 101040101/101040102, 1010402 > 101040201/101040202.
     3. spu_PostExpenseV2: cost increment = net (Debit - Credit) on
        inventory accounts from @ExpenseDetails, instead of SUM(Debit).
        Everything else in the proc is unchanged (verbatim from live).
     4. Report SPs: per linked expense, net (Debit - Credit) on inventory
        accounts from its own SINGLE ticket (TicketMaster.ReferenceNumber =
        ExpenseSummary.ReferenceNumber AND ReferenceKey = InvoiceNo AND
        Mnemonic = 'SINGLE' -- verified 1:1 for all 180 linked expenses on
        STAGING). Detail keeps the invoice Amount column for reference and
        adds InventoryCost; CostDerived/RunningTotal now use InventoryCost.
        Header's output columns are unchanged (form reads them by name).

   NOT DONE (flagged to user):
     - FORWARD-ONLY. Inventory.Cost already inflated by past postings is
       NOT corrected; for those shipments the report will now (correctly)
       show a variance vs the live cost.
     - sp_EditSingleExpense (pre-existing): its "linked to PO" edit guard
       56103 is commented out, and it re-posts via spu_PostExpenseV2
       without first backing out the old Inventory.Cost increment -- every
       edit of a PO-linked expense adds its cost again.
     - spu_ConfirmPOFinalCost overwrites Inventory.Cost with the user's
       FinalCost, so after finalization the header "variance vs live cost"
       compares against a manually set number, not the accumulated one.

   Deploy to CORECSERP_002_DEV first; mirror to CORECSJFC2026_STAGING
   only after confirming with the user, per project convention.
   ================================================================ */

-- ----------------------------------------------------------------
-- 1. Config: inventory root account for expense costing
-- ----------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.JournalEntryMapping WHERE Mnemonic = 'EXP-INVCOST-ROOT')
    INSERT INTO dbo.JournalEntryMapping
        (Origin, Mnemonic, Description, Seq, DebitCredit, AccountCode, AccountDescription,
         IsConditional, IsAmountFromSource, IsActive, Notes, AmountType, ConditionFlag)
    VALUES
        ('CFG', 'EXP-INVCOST-ROOT', 'Root account whose COA subtree counts as inventory cost for PO-linked expenses',
         1, 'D', '10104', 'INVENTORY',
         0, 0, 1,
         'Config only - not a posting template. Read by dbo.fn_InventoryCostAccounts() (spu_PostExpenseV2, sp_rpt_ItemCostingRecon_*).',
         'CONFIG', NULL);
GO

-- ----------------------------------------------------------------
-- 2. dbo.fn_InventoryCostAccounts
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.fn_InventoryCostAccounts', 'IF') IS NOT NULL
    EXEC sp_rename 'dbo.fn_InventoryCostAccounts', 'fn_InventoryCostAccounts_OLD_09242026220000';
GO

CREATE FUNCTION dbo.fn_InventoryCostAccounts()
RETURNS TABLE
AS
/*
    Every ChartOfAccounts code in the subtree of the active
    EXP-INVCOST-ROOT mapping (root included), walked via SummaryAccount.
    Empty when the mapping is missing/inactive -- spu_PostExpenseV2
    THROWs on that rather than silently incorporating 0.
    Callers: spu_PostExpenseV2, sp_rpt_ItemCostingRecon_Header,
             sp_rpt_ItemCostingRecon_Detail.
*/
RETURN
    WITH Tree AS (
        SELECT c.AccountCode
        FROM dbo.ChartOfAccounts c
        JOIN dbo.JournalEntryMapping m
          ON m.AccountCode = c.AccountCode
         AND m.Mnemonic    = 'EXP-INVCOST-ROOT'
         AND m.IsActive    = 1
        UNION ALL
        SELECT c.AccountCode
        FROM dbo.ChartOfAccounts c
        JOIN Tree t ON c.SummaryAccount = t.AccountCode
    )
    SELECT AccountCode FROM Tree;
GO

-- ----------------------------------------------------------------
-- 3. sp_rpt_ItemCostingRecon_Header
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_ItemCostingRecon_Header', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_ItemCostingRecon_Header', 'sp_rpt_ItemCostingRecon_Header_OLD_09242026220000';
GO

CREATE PROCEDURE dbo.sp_rpt_ItemCostingRecon_Header
(
    @ShipmentNo VARCHAR(10)
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Scalar, not an inner-joined CTE (sp-reviewer catch 2026-09-22): a
    -- shipment can have linked SINGLE expenses posted before Inventory
    -- ever gets rows for it (not yet received / fully written off to
    -- zero qty). Joining ExpenseSummary to a qty-derived CTE would drop
    -- those expenses out of the count/total entirely instead of
    -- surfacing them as an un-reconciled 0-qty case.
    DECLARE @TotalQty DECIMAL(18,3) =
        (SELECT SUM(Quantity) FROM dbo.Inventory WHERE ShipmentNo = @ShipmentNo);

    ;WITH ShipmentCost AS (
        SELECT MIN(Cost) AS MinCost, MAX(Cost) AS MaxCost
        FROM dbo.Inventory
        WHERE ShipmentNo = @ShipmentNo
    ),
    -- CHANGED 2026-09-24: inventory legs of each expense's own ticket,
    -- not the whole invoice amount (es.Amount).
    ExpenseInventory AS (
        SELECT inv.InventoryCost
        FROM dbo.ExpenseSummary es
        OUTER APPLY (
            SELECT ISNULL(SUM(td.Debit - td.Credit), 0) AS InventoryCost
            FROM dbo.TicketMaster tm
            JOIN dbo.TicketDetails td
              ON td.TicketNumber    = tm.TicketNumber
             AND td.ReferenceNumber = tm.ReferenceNumber
            WHERE tm.ReferenceNumber = es.ReferenceNumber
              AND tm.ReferenceKey    = es.InvoiceNo
              AND tm.Mnemonic        = 'SINGLE'
              AND td.AccountCode IN (SELECT AccountCode FROM dbo.fn_InventoryCostAccounts())
        ) inv
        WHERE es.ShipmentNo = @ShipmentNo
          AND es.PostingMode = 'SINGLE'
    ),
    Incorporated AS (
        SELECT
            SUM(CAST(ei.InventoryCost AS DECIMAL(18,4)) / NULLIF(@TotalQty, 0)) AS TotalCostIncorporated,
            COUNT(*) AS ExpenseCount
        FROM ExpenseInventory ei
    )
    SELECT
        p.ShipmentNo,
        p.SupplierID,
        p.SupplierName,
        p.BranchCode,
        p.Status,
        p.OrderType,
        p.DateOrder,
        CAST(ISNULL(@TotalQty, 0) AS DECIMAL(18,3))              AS TotalQty,
        CAST(ISNULL(sc.MinCost, 0) AS DECIMAL(18,4))             AS CurrentMinCost,
        CAST(ISNULL(sc.MaxCost, 0) AS DECIMAL(18,4))             AS CurrentMaxCost,
        CAST(ISNULL(i.TotalCostIncorporated, 0) AS DECIMAL(18,4)) AS TotalCostIncorporated,
        ISNULL(i.ExpenseCount, 0)                                AS LinkedExpenseCount,
        CAST(ISNULL(sc.MaxCost, 0) - ISNULL(i.TotalCostIncorporated, 0) AS DECIMAL(18,4)) AS Variance,
        -- Tolerance instead of exact equality (sp-reviewer catch): the
        -- live Cost column accumulates via a sequence of separate
        -- UPDATE ... SET Cost = Cost + (...) statements, one per posted
        -- expense, so immaterial rounding drift against this report's
        -- own end-to-end DECIMAL(18,4) sum is expected, not an error.
        -- Computed once here so SQL and UI can't disagree on the verdict.
        CAST(CASE WHEN ABS(ISNULL(sc.MaxCost, 0) - ISNULL(i.TotalCostIncorporated, 0)) <= 0.01
                  THEN 1 ELSE 0 END AS BIT) AS IsMatched
    FROM dbo.view_POSUMMARYREP p
    CROSS JOIN ShipmentCost sc
    CROSS JOIN Incorporated i
    WHERE p.ShipmentNo = @ShipmentNo;
END
GO

-- ----------------------------------------------------------------
-- 4. sp_rpt_ItemCostingRecon_Detail
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_ItemCostingRecon_Detail', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_ItemCostingRecon_Detail', 'sp_rpt_ItemCostingRecon_Detail_OLD_09242026220000';
GO

CREATE PROCEDURE dbo.sp_rpt_ItemCostingRecon_Detail
(
    @ShipmentNo VARCHAR(10)
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TotalQty DECIMAL(18,3) =
        (SELECT SUM(Quantity) FROM dbo.Inventory WHERE ShipmentNo = @ShipmentNo);

    SELECT
        es.ReferenceNumber,
        es.InvoiceNo,
        es.SupplierID,
        ISNULL(s.SupplierName, es.SupplierID) AS SupplierName,
        es.ExpenseDate,
        es.Description AS Remarks,
        CAST(es.Amount AS DECIMAL(18,2)) AS Amount,                 -- invoice amount, reference only
        CAST(inv.InventoryCost AS DECIMAL(18,2)) AS InventoryCost,  -- NEW 2026-09-24: what is actually costed
        CAST(inv.InventoryCost / NULLIF(@TotalQty, 0) AS DECIMAL(18,4)) AS CostDerived,
        CAST(
            SUM(inv.InventoryCost / NULLIF(@TotalQty, 0)) OVER (
                ORDER BY es.ExpenseDate, es.ReferenceNumber
                ROWS UNBOUNDED PRECEDING)
        AS DECIMAL(18,4)) AS RunningTotal
    FROM dbo.ExpenseSummary es
    LEFT JOIN dbo.Supplier s ON s.SupplierKey = es.SupplierID
    OUTER APPLY (
        SELECT ISNULL(SUM(td.Debit - td.Credit), 0) AS InventoryCost
        FROM dbo.TicketMaster tm
        JOIN dbo.TicketDetails td
          ON td.TicketNumber    = tm.TicketNumber
         AND td.ReferenceNumber = tm.ReferenceNumber
        WHERE tm.ReferenceNumber = es.ReferenceNumber
          AND tm.ReferenceKey    = es.InvoiceNo
          AND tm.Mnemonic        = 'SINGLE'
          AND td.AccountCode IN (SELECT AccountCode FROM dbo.fn_InventoryCostAccounts())
    ) inv
    WHERE es.ShipmentNo = @ShipmentNo
      AND es.PostingMode = 'SINGLE'
    ORDER BY es.ExpenseDate, es.ReferenceNumber;
END
GO

-- ----------------------------------------------------------------
-- 5. spu_PostExpenseV2 -- cost increment from inventory legs only
--    (body verbatim from live except the marked costing block)
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.spu_PostExpenseV2', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_PostExpenseV2', 'spu_PostExpenseV2_OLD_09242026220000';
GO

-- =============================================================================
-- spu_PostExpenseV2  (fixed)
--
-- CHANGES vs. previous version:
--
--   1. ExpenseMaster now only gets DEBIT lines (the actual expense
--      categories). Previously it inserted one row per GL leg, including
--      credit legs (AP-Trade, EWT Payable) - a 3-leg compound entry
--      (Dr Expense 15000 / Cr AP 12750 / Cr EWT 2250) was creating THREE
--      ExpenseMaster rows totaling 30000 instead of the real 15000
--      invoice amount, which would badly break any downstream logic that
--      sums ExpenseMaster.Amount as the payable basis.
--
--   2. ExpenseSummary.Balance = SUM(Credit) on the designated payable
--      account (@PayableAccountCode, default '20103' - same "Accrued
--      Expenses Payable" code used everywhere else in the expense
--      module), NOT the gross debit total. If your compound entry
--      already split off EWT/other liabilities to different accounts,
--      the amount actually owed to the supplier is only what landed on
--      the payable account - same principle as the BATCH/mapped flow.
--
--   3. Tags PostingMode='SINGLE' and records PayableAccountCode, so
--      sp_AddPaymentSupplierCompound knows to settle this invoice with
--      the simplified single-line logic instead of the branch-weighted
--      EWT-recompute logic built for the BATCH flow.
--
--   4. Validates that at least one credit line hits @PayableAccountCode -
--      without that, there's nothing for ExpenseSummary.Balance to track
--      and payment would have no account to debit back down.
-- =============================================================================
CREATE   PROCEDURE [dbo].[spu_PostExpenseV2]
(
    @ExpenseDetails      ExpenseDetailType READONLY,
    @TicketNumber        VARCHAR(10),
    @BranchCode          VARCHAR(10),
    @ReferenceNumber     VARCHAR(20),
    @InvoiceNo           VARCHAR(150),
    @ShipmentNo          VARCHAR(10),
    @SupplierID          VARCHAR(20),
    @ExpenseDate         DATE,
    @Remarks             VARCHAR(500),
    @isLinkedToPO        BIT,
    @User                VARCHAR(100),
    @PayableAccountCode  VARCHAR(20) = '20103'   -- NEW: which credited account is "owed to supplier"
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRAN

        DECLARE @TotalAmount   DECIMAL(18,2)
        DECLARE @PayableAmount DECIMAL(18,2)
        DECLARE @BatchID       INT
        DECLARE @Particulars   VARCHAR(400)

        EXEC GetBatchReferenceID @BatchID OUTPUT

        SELECT @TotalAmount = SUM(Debit) FROM @ExpenseDetails

        SELECT @PayableAmount = SUM(Credit)
        FROM @ExpenseDetails
        WHERE AccountCode IN ('20101','20102','20103')--= @PayableAccountCode

        --IF ISNULL(@PayableAmount, 0) <= 0
        --    THROW 56001, 'No credit line found on the designated payable account - nothing for payment to settle against.', 1;
       
       DECLARE @TotalDebit  DECIMAL(18,2)
        DECLARE @TotalCredit DECIMAL(18,2)

        SELECT
            @TotalDebit = ISNULL(SUM(Debit),0),
            @TotalCredit = ISNULL(SUM(Credit),0)
        FROM @ExpenseDetails

        IF @TotalDebit <> @TotalCredit
        BEGIN
            THROW 56002,
            'Journal Entry is out of balance. Total Debit must equal Total Credit.',
            1;
        END

        DECLARE @invsumQty decimal(15,3),@invsumTotalCost decimal(15,2)
        IF @isLinkedToPO=1
        BEGIN
            -- CHANGED 2026-09-24: incorporate ONLY the net inventory legs
            -- (COA subtree of JournalEntryMapping EXP-INVCOST-ROOT, i.e.
            -- 10104 INVENTORY) instead of @TotalAmount = SUM(Debit) of the
            -- whole entry, which also swept in non-inventory debits (e.g.
            -- DR 20103 Accrued Expenses Payable on ExpenseSummary 30437).
            IF NOT EXISTS (SELECT 1 FROM dbo.fn_InventoryCostAccounts())
                THROW 56010, 'Inventory costing root account (JournalEntryMapping EXP-INVCOST-ROOT) is not configured - cannot compute the PO landed-cost increment.', 1;

            DECLARE @InventoryCost DECIMAL(18,2) =
                (SELECT ISNULL(SUM(ed.Debit - ed.Credit), 0)
                 FROM @ExpenseDetails ed
                 WHERE ed.AccountCode IN (SELECT AccountCode FROM dbo.fn_InventoryCostAccounts()));

            --COSTING BY VALUE
            SELECT @invsumQty=SUM(Quantity),@invsumTotalCost=SUM(Cost*Quantity) FROM Inventory WHERE ShipmentNo=@ShipmentNo
            --Update Inventory Set Cost=Cost + (((Available*Cost)/@invsumTotalCost) * @TotalAmount) / Available WHERE ShipmentNo=@ShipmentNo

            --COSTING BY QUANTITY
            -- Skipped when the entry has no inventory leg at all (nothing to cost).
            IF @InventoryCost <> 0
                Update Inventory Set Cost=Cost + (@InventoryCost) / @invsumQty WHERE ShipmentNo=@ShipmentNo

        END


        -- ✅ Expense Summary
        INSERT INTO ExpenseSummary
        (
            ReferenceNumber, InvoiceNo, SupplierID, Description, BatchReferenceID,
            Status, Amount, ExpenseDate, AddedBy, DateTimeAdded,
            Balance, AmountPaid, ShipmentNo,
            PostingMode, PayableAccountCode
        )
        VALUES
        (
            @ReferenceNumber, @InvoiceNo, @SupplierID, @Remarks, @BatchID,
            'POSTED', @TotalAmount, @ExpenseDate, @User, GETDATE(),
            @PayableAmount, 0, @ShipmentNo,
            'SINGLE', @PayableAccountCode
        )

        -- ✅ Expense Master - DEBIT lines only (the actual expense categories).
        -- Credit legs (AP-Trade, EWT Payable, etc.) stay in TicketDetails
        -- only - they're GL postings, not "expenses owed" in their own right.
        INSERT INTO ExpenseMaster
        (
            TRN_SEQ_NO, BranchCode, SupplierID, ReferenceNumber, BatchReferenceID,
            InvoiceNo, ExpenseName, ExpenseDate,
            Amount, Remarks, Status, Balance, AmountPaid,TicketReference
        )
        SELECT
            ROW_NUMBER() OVER(ORDER BY (SELECT 1)),
            BranchCode,
            @SupplierID,
            @ReferenceNumber,
            @BatchID,
            @InvoiceNo,
            Particulars,
            @ExpenseDate,
            Debit,
            'D-' + @Remarks,
            'UNPAID',
            Debit,
            0,
            @TicketNumber
        FROM @ExpenseDetails
        WHERE Debit > 0

        -- ✅ Ticket Master / SupplierLedger (unchanged from your version)
        DECLARE @suppname VARCHAR(100), @supplierkey VARCHAR(10)
        DECLARE @ticketnum VARCHAR(20), @transid INT
        SELECT @suppname = SupplierName, @supplierkey = SupplierKey FROM Supplier WHERE SupplierID = @SupplierID

        EXEC GetTicketNumber @ticketnum OUTPUT;
        SET @transid = dbo.func_getLastID(@SupplierID);

        -- NOTE: SupplierLedger records the NET payable amount (@PayableAmount),
        -- consistent with how the BATCH flow records net-of-EWT, not gross.
        INSERT INTO [dbo].[SupplierLedger]
            (TRN_SEQ_NO, SupplierKey, SupplierID, PostingDate,
             Description, TransCode, TransactionDate, ReferenceNumber,
             ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance,
             TransactedBy, ApprovedBy, TotalAmount, PaymentType,
             ErrorCorrectTag, TicketReference, BatchReferenceID)
        VALUES
        (
            @transid, @supplierkey, @SupplierID,
            @ExpenseDate,
            LEFT(ISNULL(@Remarks,''), 490),
            'SNGLE',
            @ExpenseDate,
            @ReferenceNumber,
            CAST(@BatchID AS VARCHAR(40)) + '-'+@BranchCode,--update by eulz from invoice to batchid
            @InvoiceNo,
            0, 0, @PayableAmount, @PayableAmount,
            @User, '*',
            @PayableAmount, 'UNPAID', 0, @ticketnum, @BatchID
        );

        INSERT INTO [dbo].[TicketMaster]
           ([TicketDate],[SupplementaryNumber],[BranchCode],[Origin],[TicketNumber],
            [ReferenceNumber],[ReferenceKey],[Owner],[Particulars],
            [EnteredBy],[CheckedBy],[ApprovedBy],[Status],[Mnemonic],[Product])
        VALUES
        (
         @ExpenseDate, 0, @BranchCode, '', @TicketNumber,
         @ReferenceNumber, @InvoiceNo, @suppname, @Remarks,
         @User, '*', '*', 'POSTED', 'SINGLE', 'NONE'
        )

        INSERT INTO [dbo].[TicketDetails]
           ([TicketDate],[SupplementaryNumber],[BranchCode],[ReferenceKey],
            [TicketNumber],[ReferenceNumber],[AccountCode],[Debit],[Credit],[CostCenter],[Particulars])
        SELECT
           @ExpenseDate, 0, @BranchCode, @InvoiceNo, @TicketNumber, @ReferenceNumber,
           AccountCode, Debit, Credit, 0, Particulars
        FROM @ExpenseDetails

        COMMIT TRAN
    END TRY

    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN

        DECLARE @ErrorMessage NVARCHAR(4000)
        DECLARE @ErrorSeverity INT
        DECLARE @ErrorState INT

        SELECT
            @ErrorMessage = ERROR_MESSAGE(),
            @ErrorSeverity = ERROR_SEVERITY(),
            @ErrorState = ERROR_STATE()

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState)
    END CATCH
END
GO
