/* ================================================================
   2026-09-29: sp_EditSingleExpense -- editing a PO-linked expense
   re-added its landed cost to the shipment every time
   ================================================================
   BUG (reported: edited only the supplier of a PO-linked expense, amount
   unchanged, yet Item Costing Recon showed the shipment's unit cost went up):
     Edit = delete + repost via spu_PostExpenseV2. The delete removed the old
     ticket/ExpenseSummary/ExpenseMaster/SupplierLedger rows but never took
     the old cost increment back out of Inventory.Cost, and the repost
     (@isLinkedToPO = 1) added it again. Guard 56103, which used to block
     editing a PO-linked expense, is commented out, so every save of an
     unpaid PO-linked expense stacked one more full increment.
     Reproduced on COREX001 (rolled back): expense 32473 / SI#00254,
     shipment 11012, supplier change only -> unit cost 68.86 -> 112.61
     (+43.75 = 1,225,000.00 / 28,000).

   FIX:
     - The repost now calls spu_PostExpenseV2 with @isLinkedToPO = 0 (so it
       records the link in ExpenseSummary.ShipmentNo but does NOT cost), and
       this proc applies the cost change itself, once:
         * same shipment before and after -> ONE update by the difference
           (new inventory legs - old inventory legs) / qty; nothing at all
           when the inventory amount is unchanged (the reported case).
         * shipment changed / link added / link removed -> back the old
           amount out of the old shipment, add the new amount to the new one.
       One net update, not "subtract then add": Inventory.Cost is
       DECIMAL(18,2), so two separately-rounded updates could drift a cent.
     - "Old amount" = net Debit - Credit of the old ticket's lines on the
       inventory subtree (fn_InventoryCostAccounts), the same basis
       spu_PostExpenseV2 and the Item Costing Recon use. Qty basis =
       SUM(Inventory.Quantity), same as spu_PostExpenseV2.
     - New guards: 56107 (costing root not configured), 56108 (old shipment
       has no quantity to back out against), 56109 (a back-out would make a
       unit cost negative).
     Guard 56103 stays commented out (editing PO-linked expenses is allowed).

   LIMITS (flagged to user, not changed):
     - Expenses costed BEFORE the 2026-09-24 fix had the whole invoice
       (SUM(Debit)) added, not just the inventory legs. Unlinking or moving
       one of those backs out only the inventory legs; the older
       overstatement stays (same as open decision #4, historical cost).
     - If the shipment's Quantity changed since the expense was posted, the
       per-unit back-out differs slightly from what was originally added.
     - Shipments already inflated by earlier edits are NOT corrected here.

   Deploy to COREX001 (DEV) first; STAGING only after the user confirms.
   ================================================================ */

IF OBJECT_ID('dbo.sp_EditSingleExpense', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_EditSingleExpense', 'sp_EditSingleExpense_OLD_09292026100000';
GO

CREATE PROCEDURE [dbo].[sp_EditSingleExpense]
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
    SET @ShipmentNo = LTRIM(RTRIM(ISNULL(@ShipmentNo, '')));

    DECLARE @CurAmountPaid DECIMAL(18,2), @CurShipmentNo VARCHAR(10),
            @PayableAccountCode VARCHAR(20), @CurTicketNumber VARCHAR(20);

    SELECT
        @CurAmountPaid = ISNULL(AmountPaid,0),
        @CurShipmentNo = LTRIM(RTRIM(ISNULL(ShipmentNo, ''))),
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
        THROW 56102, 'This expense already has a payment applied â€” editing is blocked. Use Reverse instead.', 1;
        RETURN;
    END

    --IF LTRIM(RTRIM(ISNULL(@CurShipmentNo,''))) <> ''
    --BEGIN
    --    THROW 56103, 'This expense is already linked to a Purchase Order and its cost has been incorporated into that shipment â€” it cannot be edited safely here. Reverse and re-post manually instead.', 1;
    --    RETURN;
    --END

    -- Validate the actual quantity basis spu_PostExpenseV2 will divide by, not just
    -- that the shipment has SOME row -- SUM(Available) can be NULL (all-NULL rows,
    -- would silently null out Cost) or <= 0 (divide-by-zero or a nonsense increment).
    DECLARE @NewQty DECIMAL(15,3);
    IF @isLinkedToPO = 1
    BEGIN
        IF @ShipmentNo = ''
        BEGIN
            THROW 56105, 'Cannot link to PO: no shipment was selected.', 1;
            RETURN;
        END

        SELECT @NewQty = SUM(Quantity) FROM Inventory WHERE ShipmentNo = @ShipmentNo;

        IF @NewQty IS NULL OR @NewQty <= 0
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

    -- 2026-09-29: landed-cost bookkeeping for the edit (see header).
    DECLARE @OldInvCost DECIMAL(18,2) = 0, @NewInvCost DECIMAL(18,2) = 0, @OldQty DECIMAL(15,3);

    IF @CurShipmentNo <> '' OR @ShipmentNo <> ''
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.fn_InventoryCostAccounts())
        BEGIN
            THROW 56107, 'Inventory costing root account (JournalEntryMapping EXP-INVCOST-ROOT) is not configured - cannot adjust the linked shipment''s landed cost.', 1;
            RETURN;
        END

        IF @CurShipmentNo <> ''
        BEGIN
            -- What the old posting added: net inventory legs of its own ticket.
            SELECT @OldInvCost = ISNULL(SUM(ISNULL(td.Debit,0) - ISNULL(td.Credit,0)), 0)
            FROM TicketDetails td
            WHERE td.ReferenceNumber = @ReferenceNumber
              AND td.ReferenceKey    = @OldInvoiceNo
              AND td.TicketNumber    = @CurTicketNumber
              AND td.AccountCode IN (SELECT AccountCode FROM dbo.fn_InventoryCostAccounts());

            SELECT @OldQty = SUM(Quantity) FROM Inventory WHERE ShipmentNo = @CurShipmentNo;

            IF @OldInvCost <> 0 AND (@OldQty IS NULL OR @OldQty <= 0)
            BEGIN
                THROW 56108, 'The shipment this expense is currently linked to has no valid quantity, so its cost cannot be backed out. Edit is blocked.', 1;
                RETURN;
            END
        END

        IF @ShipmentNo <> ''
            SELECT @NewInvCost = ISNULL(SUM(ISNULL(ed.Debit,0) - ISNULL(ed.Credit,0)), 0)
            FROM @ExpenseDetails ed
            WHERE ed.AccountCode IN (SELECT AccountCode FROM dbo.fn_InventoryCostAccounts());
    END

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

        -- Re-post fresh under the NEW identity via the SAME procedure Submit
        -- uses, with @isLinkedToPO = 0: it still stores @ShipmentNo on
        -- ExpenseSummary (the link), but skips its own cost increment -- the
        -- cost change is applied once, below, as a net difference.
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
            @isLinkedToPO       = 0,
            @User               = @User,
            @PayableAccountCode = @PayableAccountCode;

        IF @CurShipmentNo <> '' AND @CurShipmentNo = @ShipmentNo
        BEGIN
            -- Same shipment: one net update; nothing when the inventory amount is unchanged.
            IF @NewInvCost <> @OldInvCost
                UPDATE Inventory
                SET Cost = Cost + (@NewInvCost - @OldInvCost) / @NewQty
                WHERE ShipmentNo = @ShipmentNo;
        END
        ELSE
        BEGIN
            IF @CurShipmentNo <> '' AND @OldInvCost <> 0
                UPDATE Inventory
                SET Cost = Cost - @OldInvCost / @OldQty
                WHERE ShipmentNo = @CurShipmentNo;

            IF @ShipmentNo <> '' AND @NewInvCost <> 0
                UPDATE Inventory
                SET Cost = Cost + @NewInvCost / @NewQty
                WHERE ShipmentNo = @ShipmentNo;
        END

        IF EXISTS (SELECT 1 FROM Inventory
                   WHERE ShipmentNo IN (@CurShipmentNo, @ShipmentNo) AND ShipmentNo <> ''
                     AND Cost < 0)
            THROW 56109, 'This edit would make the linked shipment''s unit cost negative. Check the shipment''s cost history before editing.', 1;

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
