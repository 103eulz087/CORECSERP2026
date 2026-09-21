-- 2026-09-14: sp_EditSingleExpense / sp_GetSingleExpenseDetails -- PO-link cost fix
--
-- BUG (reported): AddExpenseDevExFrm.cs BtnEdit_Click -> SaveEditAsync() lets the user
-- check "Link to PO" and pick a shipment while editing an expense that was NOT
-- originally linked. That selection was silently dropped: sp_EditSingleExpense has no
-- @ShipmentNo/@isLinkedToPO parameters at all, and its repost call to
-- spu_PostExpenseV2 hardcoded @ShipmentNo='' / @isLinkedToPO=0 -- so the cost-into-
-- shipment incorporation block inside spu_PostExpenseV2 never ran on Edit, regardless
-- of what the user picked.
--
-- RISK found while fixing this: spu_PostExpenseV2's cost incorporation is a cumulative
-- increment (Cost = Cost + amount/qty), not a replace. If we simply forwarded whatever
-- the UI sends on every edit, re-editing an ALREADY-linked expense (e.g. just to fix a
-- Remarks typo) would re-run that increment and double-add cost to the shipment. Both
-- SPs already had a guard for exactly this (using the fetched-but-unused @CurShipmentNo
-- / es.ShipmentNo), left commented out. Per user decision (2026-09-14): re-enable both,
-- so editing an already-PO-linked expense is blocked outright (Reverse-and-repost
-- instead), while an expense that was NOT previously linked can still be linked during
-- Edit and gets its cost incorporated exactly once -- the reported scenario.

IF OBJECT_ID('dbo.sp_EditSingleExpense', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_EditSingleExpense', 'sp_EditSingleExpense_OLD_09142026163617';
GO

/* ================================================================
   sp_EditSingleExpense — ALLOW SUPPLIER/INVOICENO CHANGE
   Same fix as sp_EditExpenseManualMultiBranch: split the old
   (lookup/delete) identity from the new (re-post) identity, plus a
   duplicate check on the new combination.

   2026-09-14: accepts @ShipmentNo/@isLinkedToPO so a PO link picked
   during Edit is no longer dropped on the floor. Only honored when
   the record was NOT already linked before this edit (@CurShipmentNo
   blank) -- otherwise blocked, since spu_PostExpenseV2's cost
   incorporation is a cumulative increment and re-running it on an
   already-costed shipment would double-add. See
   SQL/2026-09-14_EditSingleExpense_POCostLinkFix.sql for context.
   ================================================================ */
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

    -- Defensive: don't let a bad UI selection reach spu_PostExpenseV2's costing
    -- math, where SUM(Available) over zero rows -> NULL -> Cost gets corrupted to NULL.
    IF @isLinkedToPO = 1
       AND (LTRIM(RTRIM(ISNULL(@ShipmentNo,''))) = ''
            OR NOT EXISTS (SELECT 1 FROM Inventory WHERE ShipmentNo = @ShipmentNo))
    BEGIN
        THROW 56105, 'Cannot link to PO: the selected shipment has no inventory records.', 1;
        RETURN;
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
        DELETE FROM SupplierLedger WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @OldInvoiceNo;
        DELETE FROM ExpenseMaster
        WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @OldInvoiceNo AND SupplierID = @OldSupplierID;
        DELETE FROM ExpenseSummary
        WHERE ReferenceNumber = @ReferenceNumber AND InvoiceNo = @OldInvoiceNo AND SupplierID = @OldSupplierID;

        -- Re-post fresh under the NEW identity via the SAME procedure
        -- Submit already uses. @CurShipmentNo is guaranteed blank at this point
        -- (blocked above otherwise), so forwarding the caller's @ShipmentNo/
        -- @isLinkedToPO here applies cost incorporation at most once.
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
    EXEC sp_rename 'dbo.sp_GetSingleExpenseDetails', 'sp_GetSingleExpenseDetails_OLD_09142026163617';
GO

-- 2026-09-14: re-enabled the PO-linked BlockedReason to match sp_EditSingleExpense's
-- restored guard above -- otherwise Edit would open fine and only fail at Save.
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

    -- Lines — pulled straight from the actual posted ticket, same
    -- source your existing LoadPreviousEntry() already uses, so this
    -- reflects exactly what's on the books, not a reconstruction select top 1 * FROM TicketDetails
    SELECT
        td.AccountCode, coa.Description AS AccountTitle, FORMAT(td.Debit,'N2') AS Debit, FORMAT(td.Credit,'N2') AS Credit, Particulars  AS Particulars
    FROM TicketDetails td
    JOIN ChartOfAccounts coa ON coa.AccountCode = td.AccountCode
    WHERE td.ReferenceNumber = @ReferenceNumber
      AND td.ReferenceKey = @InvoiceNo
    ORDER BY td.Debit DESC, td.Credit DESC;
END
GO
