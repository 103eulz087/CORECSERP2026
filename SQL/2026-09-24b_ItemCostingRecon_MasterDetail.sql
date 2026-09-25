/* ================================================================
   2026-09-24b: Item Costing Recon -- all-shipments master-detail view
   + review follow-ups on 2026-09-24_ExpenseInventoryCosting_InventoryLegsOnly.sql
   ================================================================
   Requested by user: see ALL shipments in one grid, expand a row to see
   its linked expenses (master-detail), instead of one shipment at a time.

   1. dbo.sp_rpt_ItemCostingRecon_List (NEW) -- set-based, two result sets:
        Result set 1 (Master): one row per PO shipment in scope
          (view_POSUMMARYREP is one row per ShipmentNo -- verified 365/365
          on STAGING). Totals: linked expense count, total invoice amount,
          total INVENTORY cost (net 10104-subtree legs of each expense's own
          SINGLE ticket), per-unit cost incorporated, live min/max
          Inventory.Cost, variance, and a ReconStatus text.
        Result set 2 (Detail): one row per linked SINGLE expense, keyed by
          ShipmentNo (the relation key), with a per-shipment running total
          (PARTITION BY ShipmentNo, ROWS UNBOUNDED PRECEDING).
      Tie-out by construction: Master.TotalCostIncorporated and the last
      Detail.RunningTotal of the same shipment are the same
      SUM(InventoryCost / TotalQty) over the same #Exp rows.
      Ticket lines are aggregated ONCE (TicketDetails has no TicketNumber
      index, so the per-row OUTER APPLY used by the single-shipment procs
      would rescan it per expense across hundreds of shipments).
      Filters (all optional, independent): @DateFrom/@DateTo on the PO's
      DateOrder (half-open), @ShipmentNo, @OnlyWithExpenses (default 1).
      The single-shipment sp_rpt_ItemCostingRecon_Header/_Detail are left
      in place (no longer called by the form; not deleted per house rule).

   2. dbo.fn_InventoryCostAccounts -- self-reference guard in the recursive
      member (sp-reviewer): a COA row whose SummaryAccount points to itself
      would otherwise fail with "maximum recursion 100 has been exhausted".
      (Inline TVFs can't carry OPTION (MAXRECURSION); the default 100 still
      bounds any longer cycle.)

   3. dbo.spu_PostExpenseV2 -- CATCH re-raises with THROW; instead of
      RAISERROR(@msg,...), which always surfaced as error 50000 and hid the
      real number (56002, the new 56010, etc.) from forms that show
      ex.Number. Approved by user. Body otherwise unchanged.

   Deploy to CORECSERP_002_DEV first; mirror to CORECSJFC2026_STAGING only
   after confirming with the user (both 2026-09-24 scripts, in order).
   ================================================================ */

-- ----------------------------------------------------------------
-- 1. fn_InventoryCostAccounts -- self-loop guard
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.fn_InventoryCostAccounts', 'IF') IS NOT NULL
    EXEC sp_rename 'dbo.fn_InventoryCostAccounts', 'fn_InventoryCostAccounts_OLD_09242026233000';
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
             sp_rpt_ItemCostingRecon_Detail, sp_rpt_ItemCostingRecon_List.
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
        WHERE c.AccountCode <> t.AccountCode   -- a row that is its own parent never recurses
    )
    SELECT AccountCode FROM Tree;
GO

-- ----------------------------------------------------------------
-- 2. sp_rpt_ItemCostingRecon_List (NEW)
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_ItemCostingRecon_List', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_ItemCostingRecon_List', 'sp_rpt_ItemCostingRecon_List_OLD_09242026234500';
GO

CREATE PROCEDURE dbo.sp_rpt_ItemCostingRecon_List
(
    @DateFrom         DATE        = NULL,   -- PO DateOrder, inclusive
    @DateTo           DATE        = NULL,   -- PO DateOrder, inclusive (half-open internally)
    @ShipmentNo       VARCHAR(10) = NULL,   -- NULL/'' = all shipments
    @OnlyWithExpenses BIT         = 1       -- 1 = hide shipments with no linked SINGLE expense
)
AS
/*
    Result set 1: Master -- one row per PO shipment
        ShipmentNo, SupplierID, SupplierName, BranchCode, Status, DateOrder,
        TotalQty, CurrentMinCost, CurrentMaxCost, LinkedExpenseCount,
        TotalInvoiceAmount, TotalInventoryCost, TotalCostIncorporated,
        Variance, IsMatched, ReconStatus
    Result set 2: Detail -- one row per linked SINGLE expense
        ShipmentNo (relation key), ReferenceNumber, InvoiceNo, SupplierName,
        ExpenseDate, Remarks, Amount, InventoryCost, CostDerived, RunningTotal
    Caller: Reporting/ItemCostingReconReport.cs (reads both result sets in
    this order into one DataSet -- changing order/columns is a breaking change).
    Rounding note: RunningTotal (and Master.TotalCostIncorporated) sum the
    UNROUNDED InventoryCost / TotalQty and round once at the end, so they tie
    to each other exactly; CostDerived is that same per-row value rounded to
    4dp for display, so adding up the CostDerived column by hand can differ
    from RunningTotal by a fraction of a cent. Expected, not a bug.
*/
BEGIN
    SET NOCOUNT ON;

    SET @ShipmentNo = NULLIF(LTRIM(RTRIM(@ShipmentNo)), '');

    CREATE TABLE #InvAccts (AccountCode VARCHAR(50) NOT NULL PRIMARY KEY);
    INSERT INTO #InvAccts (AccountCode)
    SELECT DISTINCT AccountCode FROM dbo.fn_InventoryCostAccounts();

    -- Shipments in scope
    SELECT p.ShipmentNo, p.SupplierID, p.SupplierName, p.BranchCode, p.Status, p.DateOrder
    INTO #Ship
    FROM dbo.view_POSUMMARYREP p
    WHERE (@ShipmentNo IS NULL OR p.ShipmentNo = @ShipmentNo)
      AND (@DateFrom   IS NULL OR p.DateOrder >= @DateFrom)
      AND (@DateTo     IS NULL OR p.DateOrder <  DATEADD(DAY, 1, @DateTo));

    -- Live inventory per shipment
    SELECT i.ShipmentNo,
           SUM(ISNULL(i.Quantity, 0)) AS TotalQty,
           MIN(i.Cost)                AS MinCost,
           MAX(i.Cost)                AS MaxCost
    INTO #Qty
    FROM dbo.Inventory i
    JOIN #Ship s ON s.ShipmentNo = i.ShipmentNo
    GROUP BY i.ShipmentNo;

    -- Linked SINGLE expenses in scope (cost filled in below)
    SELECT es.ShipmentNo, es.ReferenceNumber, es.InvoiceNo, es.SupplierID,
           es.ExpenseDate, es.Description,
           CAST(ISNULL(es.Amount, 0) AS DECIMAL(18,2)) AS Amount,
           CAST(0 AS DECIMAL(18,2))                    AS InventoryCost
    INTO #Exp
    FROM dbo.ExpenseSummary es
    JOIN #Ship s ON s.ShipmentNo = es.ShipmentNo
    WHERE es.PostingMode = 'SINGLE';

    -- Net inventory leg of each expense's own ticket. Same ticket link as
    -- the single-shipment procs (TicketMaster.ReferenceNumber =
    -- es.ReferenceNumber AND ReferenceKey = es.InvoiceNo AND Mnemonic =
    -- 'SINGLE'). Driven from #Exp (sp-reviewer 24b) so only the tickets of
    -- the expenses actually in scope are aggregated, not every SINGLE
    -- ticket in the system. Verified equivalent to the per-row OUTER APPLY
    -- on every PO-linked SINGLE expense on DEV.
    UPDATE e
    SET e.InventoryCost = CAST(inv.InventoryCost AS DECIMAL(18,2))
    FROM #Exp e
    JOIN (
        SELECT tm.ReferenceNumber, tm.ReferenceKey,
               SUM(ISNULL(td.Debit, 0) - ISNULL(td.Credit, 0)) AS InventoryCost
        FROM (SELECT DISTINCT ReferenceNumber, InvoiceNo FROM #Exp) k
        JOIN dbo.TicketMaster tm
          ON tm.ReferenceNumber = k.ReferenceNumber
         AND tm.ReferenceKey    = k.InvoiceNo
         AND tm.Mnemonic        = 'SINGLE'
        JOIN dbo.TicketDetails td
          ON td.TicketNumber    = tm.TicketNumber
         AND td.ReferenceNumber = tm.ReferenceNumber
        JOIN #InvAccts a ON a.AccountCode = td.AccountCode
        GROUP BY tm.ReferenceNumber, tm.ReferenceKey
    ) inv
      ON inv.ReferenceNumber = e.ReferenceNumber
     AND inv.ReferenceKey    = e.InvoiceNo;

    ;WITH ExpAgg AS (
        SELECT e.ShipmentNo,
               COUNT(*)             AS ExpenseCount,
               SUM(e.Amount)        AS TotalInvoiceAmount,
               SUM(e.InventoryCost) AS TotalInventoryCost,
               SUM(e.InventoryCost / NULLIF(q.TotalQty, 0)) AS CostIncorporated
        FROM #Exp e
        LEFT JOIN #Qty q ON q.ShipmentNo = e.ShipmentNo
        GROUP BY e.ShipmentNo
    )
    -- Result set 1: Master
    SELECT
        s.ShipmentNo,
        s.SupplierID,
        s.SupplierName,
        s.BranchCode,
        s.Status,
        s.DateOrder,
        CAST(ISNULL(q.TotalQty, 0) AS DECIMAL(18,3))            AS TotalQty,
        CAST(ISNULL(q.MinCost, 0) AS DECIMAL(18,4))             AS CurrentMinCost,
        CAST(ISNULL(q.MaxCost, 0) AS DECIMAL(18,4))             AS CurrentMaxCost,
        ISNULL(x.ExpenseCount, 0)                               AS LinkedExpenseCount,
        CAST(ISNULL(x.TotalInvoiceAmount, 0) AS DECIMAL(18,2))  AS TotalInvoiceAmount,
        CAST(ISNULL(x.TotalInventoryCost, 0) AS DECIMAL(18,2))  AS TotalInventoryCost,
        CAST(ISNULL(x.CostIncorporated, 0) AS DECIMAL(18,4))    AS TotalCostIncorporated,
        CAST(ISNULL(q.MaxCost, 0) - ISNULL(x.CostIncorporated, 0) AS DECIMAL(18,4)) AS Variance,
        m.IsMatched,
        CASE
            WHEN ISNULL(x.ExpenseCount, 0) = 0                            THEN 'NO EXPENSES'
            WHEN ISNULL(q.TotalQty, 0) = 0                                THEN 'NO INVENTORY'
            WHEN ABS(ISNULL(q.MinCost, 0) - ISNULL(q.MaxCost, 0)) > 0.01  THEN 'LOTS DIVERGE'
            WHEN m.IsMatched = 1                                          THEN 'MATCHED'
            ELSE 'VARIANCE'
        END                                                     AS ReconStatus
    FROM #Ship s
    LEFT JOIN #Qty q  ON q.ShipmentNo = s.ShipmentNo
    LEFT JOIN ExpAgg x ON x.ShipmentNo = s.ShipmentNo
    -- Match test computed ONCE so IsMatched and ReconStatus can't drift apart.
    -- Same 0.01 tolerance as sp_rpt_ItemCostingRecon_Header (Cost is
    -- accumulated by separate UPDATEs, so tiny rounding drift is expected);
    -- LOTS DIVERGE above uses the same tolerance for the same reason.
    CROSS APPLY (
        SELECT CAST(CASE WHEN ABS(ISNULL(q.MaxCost, 0) - ISNULL(x.CostIncorporated, 0)) <= 0.01
                         THEN 1 ELSE 0 END AS BIT) AS IsMatched
    ) m
    WHERE @OnlyWithExpenses = 0 OR ISNULL(x.ExpenseCount, 0) > 0
    ORDER BY s.DateOrder DESC, s.ShipmentNo DESC;

    -- Result set 2: Detail (only shipments with expenses can have rows, so
    -- @OnlyWithExpenses never leaves an orphan detail row)
    SELECT
        e.ShipmentNo,
        e.ReferenceNumber,
        e.InvoiceNo,
        ISNULL(sp.SupplierName, e.SupplierID)                   AS SupplierName,
        e.ExpenseDate,
        e.Description                                           AS Remarks,
        e.Amount,                                               -- full invoice, reference only
        e.InventoryCost,                                        -- what is actually costed
        CAST(e.InventoryCost / NULLIF(q.TotalQty, 0) AS DECIMAL(18,4)) AS CostDerived,
        CAST(SUM(e.InventoryCost / NULLIF(q.TotalQty, 0)) OVER (
                 PARTITION BY e.ShipmentNo
                 ORDER BY e.ExpenseDate, e.ReferenceNumber
                 ROWS UNBOUNDED PRECEDING) AS DECIMAL(18,4))    AS RunningTotal
    FROM #Exp e
    LEFT JOIN #Qty q ON q.ShipmentNo = e.ShipmentNo
    LEFT JOIN dbo.Supplier sp ON sp.SupplierKey = e.SupplierID
    ORDER BY e.ShipmentNo, e.ExpenseDate, e.ReferenceNumber;
END
GO

-- ----------------------------------------------------------------
-- 3. spu_PostExpenseV2 -- THROW; in CATCH (body otherwise unchanged)
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.spu_PostExpenseV2', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_PostExpenseV2', 'spu_PostExpenseV2_OLD_09242026233000';
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

        -- CHANGED 2026-09-24b: THROW keeps the original error number (56002/56010/...);
        -- RAISERROR(@ErrorMessage, ...) always surfaced as 50000.
        ;THROW;
    END CATCH
END
GO
