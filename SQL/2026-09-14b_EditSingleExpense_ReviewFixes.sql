-- 2026-09-14 (follow-up): sp_EditSingleExpense / sp_GetSingleExpenseDetails
-- Fixes from sp-reviewer pass on SQL/2026-09-14_EditSingleExpense_POCostLinkFix.sql
-- (that script is already live on CORECSERP_002_DEV; this is the very next revision,
-- backing THAT version up before replacing it -- not a redo of the whole fix).
--
-- Blocker 1: the @isLinkedToPO=1 guard did nothing when @isLinkedToPO=0 but @ShipmentNo
-- was non-blank -- spu_PostExpenseV2 would still stamp ExpenseSummary.ShipmentNo with it
-- (costing skipped, since that block is gated on @isLinkedToPO=1, but the record now
-- LOOKS linked). On the next load, both the @CurShipmentNo guard here and
-- sp_GetSingleExpenseDetails' BlockedReason would treat it as already-linked/already-
-- costed and permanently refuse further edits, with no cost ever having been applied.
-- Fix: sanitize @ShipmentNo to '' whenever @isLinkedToPO=0, inside the proc -- don't
-- trust the caller to keep the two in sync.
--
-- Blocker 2: the @isLinkedToPO=1 guard only checked EXISTS, not that the quantity basis
-- spu_PostExpenseV2 divides by is sane. SUM(Available) over rows that are all NULL is
-- NULL -> Cost=Cost+NULL silently nulls out the whole shipment's cost; SUM(Available)<=0
-- either throws divide-by-zero or produces a nonsense negative increment. Fix: compute
-- SUM(Available) here and reject IS NULL or <= 0 before ever calling spu_PostExpenseV2.
--
-- Should-fix: SupplierLedger delete lacked the @OldSupplierID filter its sibling deletes
-- have -- ReferenceNumber+InvoiceNo alone isn't guaranteed unique across suppliers (the
-- proc's own duplicate check is scoped to SupplierID+InvoiceNo, not ReferenceNumber+
-- InvoiceNo). Added for defensive symmetry.
--
-- Should-fix: sp_GetSingleExpenseDetails' line-detail SELECT returned Debit/Credit via
-- FORMAT(...,'N2') as varchar -- violates this project's "Quantity/Amount must be real
-- numeric types in SQL" convention (CLAUDE.md). Changed to DECIMAL(18,2); the C# grid
-- already applies its own N2 DisplayFormat, so no UI change needed.
--
-- Not fixed here (flagged, not silently changed):
--   - Nested EXEC dbo.spu_PostExpenseV2 inside this proc's own BEGIN TRAN can surface a
--     transaction-count-mismatch message (SQL Server msg 266) ahead of the real business
--     error on certain failure paths, because spu_PostExpenseV2 manages its own BEGIN/
--     COMMIT/ROLLBACK TRAN rather than being trancount-aware. Fixing this means changing
--     spu_PostExpenseV2's own transaction handling, which affects the New-Post path too --
--     out of scope for this Edit-only fix without separate confirmation.
--   - @ReferenceNumber/@SupplierID parameter widths differ between this proc and
--     sp_GetSingleExpenseDetails (20/20 here vs 10/100 there). Checked the real columns:
--     ExpenseSummary.ReferenceNumber is varchar(10), SupplierID is char(6) -- both procs'
--     parameters are wider than the actual columns, so this is not a truncation risk today,
--     just cosmetic looseness. Left alone.

IF OBJECT_ID('dbo.sp_EditSingleExpense', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_EditSingleExpense', 'sp_EditSingleExpense_OLD_09142026164403';
GO

CREATE   PROCEDURE [dbo].[sp_EditSingleExpense]
(
    @ReferenceNumber VARCHAR(20),
    @OldInvoiceNo    VARCHAR(150),   -- WHICH record to find/delete
    @OldSupplierID   VARCHAR(20),    -- (SupplierKey) WHICH record to find/delete
    @InvoiceNo       VARCHAR(150),   -- NEW invoice no. (same as old if unchanged)
    @SupplierID      VARCHAR(20),    -- NEW supplier key (same as old if unchanged)
    @BranchCode      VARCHAR(10),
    @ExpenseDate     DATE,
    @Remarks         VARCHAR(500),
    @User            VARCHAR(100),
    @ExpenseDetails  ExpenseDetailType READONLY,
    @ShipmentNo      VARCHAR(10) = '',
    @isLinkedToPO    BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Don't trust the caller to keep these two in sync -- a stale/leftover @ShipmentNo
    -- alongside @isLinkedToPO=0 must never reach spu_PostExpenseV2's INSERT.
    IF @isLinkedToPO = 0
        SET @ShipmentNo = '';

    DECLARE @CurAmountPaid DECIMAL(18,2), @CurShipmentNo VARCHAR(10),
            @PayableAccountCode VARCHAR(20), @CurTicketNumber VARCHAR(20);

    SELECT
        @CurAmountPaid = ISNULL(AmountPaid,0),
        @CurShipmentNo = ShipmentNo,
        @PayableAccountCode = PayableAccountCode
    FROM ExpenseSummary
    WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @OldInvoiceNo
      AND SupplierID = @OldSupplierID AND PostingMode = 'SINGLE';

    IF @PayableAccountCode IS NULL
    BEGIN
        THROW 56101, 'SINGLE-mode expense not found for this Reference/Invoice/Supplier.', 1;
        RETURN;
    END

    IF @CurAmountPaid > 0
    BEGIN
        THROW 56102, 'This expense already has a payment applied — editing is blocked. Use Reverse instead.', 1;
        RETURN;
    END

    IF LTRIM(RTRIM(ISNULL(@CurShipmentNo,''))) <> ''
    BEGIN
        THROW 56103, 'This expense is already linked to a Purchase Order and its cost has been incorporated into that shipment — it cannot be edited safely here. Reverse and re-post manually instead.', 1;
        RETURN;
    END

    -- Validate the actual quantity basis spu_PostExpenseV2 will divide by, not just
    -- that the shipment has SOME row -- SUM(Available) can be NULL (all-NULL rows,
    -- would silently null out Cost) or <= 0 (divide-by-zero or a nonsense increment).
    IF @isLinkedToPO = 1
    BEGIN
        IF LTRIM(RTRIM(ISNULL(@ShipmentNo,''))) = ''
        BEGIN
            THROW 56105, 'Cannot link to PO: no shipment was selected.', 1;
            RETURN;
        END

        DECLARE @AvailableQty DECIMAL(15,3);
        SELECT @AvailableQty = SUM(Available) FROM Inventory WHERE ShipmentNo = @ShipmentNo;

        IF @AvailableQty IS NULL OR @AvailableQty <= 0
        BEGIN
            THROW 56106, 'Cannot link to PO: the selected shipment has no valid available quantity to cost against.', 1;
            RETURN;
        END
    END

    -- NEW: duplicate check on the new identity, only when it's actually changing
    IF (@InvoiceNo <> @OldInvoiceNo OR @SupplierID <> @OldSupplierID)
       AND EXISTS (
           SELECT 1 FROM ExpenseSummary
           WHERE SupplierID = @SupplierID AND InvoiceNo = @InvoiceNo
             AND NOT (ReferenceNumber = @ReferenceNumber AND InvoiceNo = @OldInvoiceNo AND SupplierID = @OldSupplierID)
       )
    BEGIN
        THROW 56104, 'Another expense already exists for that Supplier/Invoice No. combination.', 1;
        RETURN;
    END

    SELECT TOP 1 @CurTicketNumber = TicketReference
    FROM ExpenseMaster
    WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @OldInvoiceNo AND SupplierID = @OldSupplierID;

    BEGIN TRY
        BEGIN TRAN;

        DELETE FROM TicketDetails WHERE ReferenceNumber = @ReferenceNumber AND ReferenceKey = @OldInvoiceNo;
        DELETE FROM TicketMaster
        WHERE ReferenceNumber = @ReferenceNumber AND ReferenceKey = @OldInvoiceNo AND TicketNumber = @CurTicketNumber;
        DELETE FROM SupplierLedger
        WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @OldInvoiceNo AND SupplierID = @OldSupplierID;
        DELETE FROM ExpenseMaster
        WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @OldInvoiceNo AND SupplierID = @OldSupplierID;
        DELETE FROM ExpenseSummary
        WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @OldInvoiceNo AND SupplierID = @OldSupplierID;

        -- Re-post fresh under the NEW identity via the SAME procedure
        -- Submit already uses. @CurShipmentNo is guaranteed blank at this point
        -- (blocked above otherwise), and @ShipmentNo/@isLinkedToPO have been
        -- sanitized/validated above, so this applies cost incorporation at most
        -- once, only when the caller actually asked for it with a sane quantity basis.
        EXEC dbo.spu_PostExpenseV2
            @ExpenseDetails     = @ExpenseDetails,
            @TicketNumber       = @CurTicketNumber,
            @BranchCode         = @BranchCode,
            @ReferenceNumber    = @ReferenceNumber,
            @InvoiceNo          = @InvoiceNo,
            @ShipmentNo         = @ShipmentNo,
            @SupplierID         = @SupplierID,
            @ExpenseDate        = @ExpenseDate,
            @Remarks            = @Remarks,
            @isLinkedToPO       = @isLinkedToPO,
            @User               = @User,
            @PayableAccountCode = @PayableAccountCode;

        COMMIT TRAN;

        SELECT 1 AS Status, @ReferenceNumber AS ReferenceNumber, @InvoiceNo AS InvoiceNo,
               'Expense updated successfully.' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

IF OBJECT_ID('dbo.sp_GetSingleExpenseDetails', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetSingleExpenseDetails', 'sp_GetSingleExpenseDetails_OLD_09142026164403';
GO

CREATE   PROCEDURE [dbo].[sp_GetSingleExpenseDetails]
(
    @ReferenceNumber VARCHAR(10),
    @InvoiceNo       VARCHAR(150),
    @SupplierID      VARCHAR(100)
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Header
    SELECT
        es.ReferenceNumber, es.InvoiceNo, es.SupplierID, s.SupplierName,
        MIN(em.BranchCode) AS BranchCode, es.ExpenseDate, es.Description AS Remarks,
        es.Amount, es.Balance, es.AmountPaid, es.Status, es.ShipmentNo,
        MIN(em.TicketReference) AS TicketNumber,
        CASE
            WHEN es.AmountPaid > 0 THEN 'This expense has a payment applied — use Reverse instead of Edit.'
            WHEN LTRIM(RTRIM(ISNULL(es.ShipmentNo,''))) <> '' THEN 'This expense is already linked to a Purchase Order and its cost has been incorporated into that shipment — it cannot be edited safely here. Reverse and re-post manually instead.'
            ELSE NULL
        END AS BlockedReason
    FROM ExpenseSummary es
    JOIN Supplier s ON s.SupplierKey = es.SupplierID
    JOIN ExpenseMaster em
      ON em.ReferenceNumber = es.ReferenceNumber AND em.InvoiceNo = es.InvoiceNo
     AND em.BatchReferenceID = es.BatchReferenceID
    WHERE es.ReferenceNumber = @ReferenceNumber
      AND es.InvoiceNo = @InvoiceNo
      AND es.SupplierID = @SupplierID
    GROUP BY es.ReferenceNumber, es.InvoiceNo, es.SupplierID, s.SupplierName,
             es.ExpenseDate, es.Description, es.Amount, es.Balance, es.AmountPaid, es.Status, es.ShipmentNo;

    -- Lines — pulled straight from the actual posted ticket, same source your existing
    -- LoadPreviousEntry() already uses, so this reflects exactly what's on the books,
    -- not a reconstruction. Debit/Credit returned as real DECIMAL now, not FORMAT()-ed
    -- varchar (CLAUDE.md numeric-column convention) -- the C# grid applies its own N2
    -- DisplayFormat on bind.
    SELECT
        td.AccountCode, coa.Description AS AccountTitle,
        CAST(td.Debit AS DECIMAL(18,2)) AS Debit,
        CAST(td.Credit AS DECIMAL(18,2)) AS Credit,
        Particulars AS Particulars
    FROM TicketDetails td
    JOIN ChartOfAccounts coa ON coa.AccountCode = td.AccountCode
    WHERE td.ReferenceNumber = @ReferenceNumber
      AND td.ReferenceKey = @InvoiceNo
    ORDER BY td.Debit DESC, td.Credit DESC;
END
GO
