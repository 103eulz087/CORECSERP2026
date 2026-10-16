/* ================================================================
   [89] 2026-10-15c  DeliverySummary counters of a SALES ORDER follow its lines
   ================================================================
   Why (user, 2026-10-15): POForApproval › Paid showed PO 12415 with 3 items /
   1 sold, but Show Items listed 2 lines. Line 1 (13170, 300 kg) was cancelled
   27 s after it was scanned; the invoice (J328840, 50,520.00) bills the other
   two. The stored counters were wrong, not the lines:
       TotalItem 3 (Save counts cancelled lines), TotalItemSold 1 (set by the
       cancel when 1 line was live; the line scanned 12 s later never counted),
       TotalQtyDelivered 468.4 (incl. the cancelled 300), TotalActualQty 0.

   Cause: about 12 live procs write DeliverySummary.TotalItem / TotalItemSold /
   TotalItemReturned / TotalQtyDelivered / TotalActualQty, each with its own
   rule (Save sp_ConfirmBranchOrder: every line incl. cancelled; cancel / return:
   TotalItem incl. cancelled; Confirm sp_ConfirmOrder: TotalQtyDelivered =
   SUM(ActualQty); the V1 scan procs never set TotalItemSold / TotalItemReturned
   (NULL) and leave TotalActualQty 0 until a return; a PENDING draft keeps the
   first scan's totals). PRODUCTION 2026-10-15, 9,794 sales-order deliveries:
   TotalItem wrong 317, TotalItemSold wrong 156, TotalQtyDelivered wrong 160
   (146 have a cancelled line, 14 are PENDING drafts with the first scan's
   totals), TotalItemSold / TotalItemReturned NULL 9,383, TotalActualQty 0
   on 9,519.

   RULE (one place: dbo.fn_SODelivery_LiveTotals), for a sales-order delivery
   (its PO has a PurchaseOrderSummary row and no TransferOrderSummary row; no PO
   number is in both on DEV / STAGING / PRODUCTION, checked 2026-10-15):
       TotalItem          = lines not cancelled
       TotalItemSold      = lines not cancelled and not returned
       TotalItemReturned  = lines not cancelled and returned
                            (TotalItem = TotalItemSold + TotalItemReturned)
       TotalQtyDelivered  = SUM(QtyDelivered) of the lines not cancelled
                            = what was delivered, returned lines included
       TotalActualQty     = SUM(ActualQty) of the lines not cancelled and not returned
                            = what is billed (a credit memo lowers ActualQty)
   Confirm's own TotalQtyDelivered = SUM(ActualQty) is overridden on purpose:
   the billed qty is TotalActualQty. On PRODUCTION no live line has ActualQty
   <> QtyDelivered today, so no Delivered-report figure moves for that reason.
   STS transfers (TransferOrderSummary) are left alone: their receive step
   sets TotalItem / TotalActualQty to the received figures on purpose.
   Deliveries with no PO header (14 on DEV) are left alone too.
   Don't re-patch a writer's own counter formula: the triggers below win.

   HOW: two recalc triggers instead of patching every writer (the same idea as
   trg_ClientLedger_Recalc / trg_SupplierLedger_Recalc), so every writer is
   covered at once: the WinForms procs (V1 and V2), the legacy screens and the
   web v2, now and later.
     trg_DeliveryDetails_SOTotals  AFTER INSERT/UPDATE/DELETE on DeliveryDetails:
         a line added, cancelled, returned, re-weighed or removed recomputes
         its delivery's counters.
     trg_DeliverySummary_SOTotals  AFTER INSERT/UPDATE on DeliverySummary:
         whatever a proc writes into a counter is put back to the rule in the
         same statement.
   Checked before choosing triggers (DEV / STAGING / PRODUCTION, 2026-10-15):
     no trigger on either table yet; recursive triggers OFF, nested ON on all
     three; no MERGE and no OUTPUT-without-INTO on either table (the OUTPUT
     clauses in sp_ReturnSalesOrder / spu_SO_SplitDeliveryLine write INTO temp
     tables of other tables); the caller's @@ROWCOUNT after an UPDATE is the
     statement's own count, not the trigger's (tested on DEV, rolled back), so
     the posting procs' rowcount guards are unaffected; nothing reads the
     counters to decide anything (readers: display views / grids only, incl.
     view_InventoryForSettlement / view_SettledInventory, which show
     TotalActualQty but don't filter on it; sp_ConfirmOrder /
     sp_ReturnSalesOrder read BatchSalesSummary, not these).
     Both triggers SET NOCOUNT ON (ExecuteNonQuery counts stay the caller's).
     A trigger only updates rows whose values differ, so the nested firing
     (details trigger -> summary update -> summary trigger) stops at once; the
     summary trigger also returns at once when fired from the details trigger.
   WEB v2: a table with an enabled trigger refuses OUTPUT without INTO (334).
     EF Core's SaveChanges uses it unless the entity is configured with
     UseSqlOutputClause(false) (or HasTrigger). Applies to DeliverySummary and
     DeliveryDetails from [89] on.

   DATA: every sales-order delivery whose counters differ from its lines is
   recomputed, after the triggers exist (a writer committing between the repair
   and the triggers cannot slip through). Old and new values are kept in
   dbo.DeliverySummary_Counters_Backup_20261015 (one row per changed delivery
   per run).

   RUN: in ONE connection (SSMS / sqlcmd), in a session with no open
   transaction (refused otherwise). One transaction; LOCK_TIMEOUT 5 s, so if a
   long report holds the tables the install stops and rolls back instead of
   queueing the schema lock in front of the screens (just run it again).
   Each batch is skipped (NOEXEC) once the transaction is gone, and the batch
   after each CREATE checks the object exists (a CREATE that does not compile
   leaves the transaction open, so @@TRANCOUNT alone is not enough).
   Post-check: no sales-order delivery differs from its lines, both triggers
   enabled. Re-runnable: existing objects of the same names are renamed to
   <name>_OLD_<MMddyyyyHHmmss of the run> (triggers also disabled) first.
   ROLLBACK of [89] = DROP the two triggers (and the function if wanted); do
   NOT re-enable an _OLD_ trigger: its text calls the current function.
   No exe change. The POForApproval Delivered / Paid grids already count from
   the lines (2026-10-15 C# change); they keep doing so.
   Test: [89]-2026-10-15c_DeliverySummary_LiveTotals_Test.sql (rolled back).
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET LOCK_TIMEOUT 5000;
GO

------------------------------------------------------------------
-- 0. Prerequisites, then open the one transaction
------------------------------------------------------------------
IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[89] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.DeliverySummary', 'U') IS NULL
   OR OBJECT_ID('dbo.DeliveryDetails', 'U') IS NULL
   OR OBJECT_ID('dbo.PurchaseOrderSummary', 'U') IS NULL
   OR OBJECT_ID('dbo.TransferOrderSummary', 'U') IS NULL
BEGIN
    RAISERROR('[89] stopped: DeliverySummary / DeliveryDetails / PurchaseOrderSummary / TransferOrderSummary not found in this database.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[89] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
GO

------------------------------------------------------------------
-- 1. Re-run: back up objects of the same names
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @sfx VARCHAR(30) = '_OLD_' + FORMAT(SYSDATETIME(), 'MMddyyyyHHmmss');
DECLARE @old SYSNAME;
IF OBJECT_ID('dbo.trg_DeliveryDetails_SOTotals', 'TR') IS NOT NULL
BEGIN
    DISABLE TRIGGER dbo.trg_DeliveryDetails_SOTotals ON dbo.DeliveryDetails;
    SET @old = 'trg_DeliveryDetails_SOTotals' + @sfx;
    EXEC sp_rename 'dbo.trg_DeliveryDetails_SOTotals', @old;
END
IF OBJECT_ID('dbo.trg_DeliverySummary_SOTotals', 'TR') IS NOT NULL
BEGIN
    DISABLE TRIGGER dbo.trg_DeliverySummary_SOTotals ON dbo.DeliverySummary;
    SET @old = 'trg_DeliverySummary_SOTotals' + @sfx;
    EXEC sp_rename 'dbo.trg_DeliverySummary_SOTotals', @old;
END
IF OBJECT_ID('dbo.fn_SODelivery_LiveTotals', 'IF') IS NOT NULL
BEGIN
    SET @old = 'fn_SODelivery_LiveTotals' + @sfx;
    EXEC sp_rename 'dbo.fn_SODelivery_LiveTotals', @old;
END
GO

------------------------------------------------------------------
-- 2. The rule, in one place
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE FUNCTION dbo.fn_SODelivery_LiveTotals
(
    @DeliveryNo VARCHAR(20),
    @PONumber   VARCHAR(20)
)
RETURNS TABLE
AS
/*
    Returns: one row, always (an aggregate with no GROUP BY):
        IsSalesOrder       1 = the PO has a PurchaseOrderSummary row and no
                           TransferOrderSummary row (STS transfers and
                           deliveries without a PO header are 0)
        TotalItem          lines not cancelled (= TotalItemSold + TotalItemReturned)
        TotalItemSold      lines not cancelled and not returned
        TotalItemReturned  lines not cancelled and returned
        TotalQtyDelivered  SUM(QtyDelivered), lines not cancelled (delivered)
        TotalActualQty     SUM(ActualQty), lines not cancelled and not returned (billed)
    Callers: trg_DeliveryDetails_SOTotals, trg_DeliverySummary_SOTotals,
             script [89]'s data repair. Exception Center S09 writes the same
             rule out on its own.
    [89] 2026-10-15.
*/
RETURN
SELECT
    so.IsSalesOrder,
    a.TotalItem,
    a.TotalItemSold,
    a.TotalItemReturned,
    a.TotalQtyDelivered,
    a.TotalActualQty
FROM
(
    SELECT
        CAST(COUNT(*) AS INT) AS TotalItem,
        CAST(ISNULL(SUM(CASE WHEN ISNULL(d.isReturned, 0) = 0 THEN 1 ELSE 0 END), 0) AS INT) AS TotalItemSold,
        CAST(ISNULL(SUM(CASE WHEN ISNULL(d.isReturned, 0) = 1 THEN 1 ELSE 0 END), 0) AS INT) AS TotalItemReturned,
        CAST(ISNULL(SUM(d.QtyDelivered), 0) AS DECIMAL(18,3)) AS TotalQtyDelivered,
        CAST(ISNULL(SUM(CASE WHEN ISNULL(d.isReturned, 0) = 0 THEN ISNULL(d.ActualQty, 0) ELSE 0 END), 0) AS DECIMAL(18,3)) AS TotalActualQty
    FROM dbo.DeliveryDetails AS d
    WHERE d.DeliveryNo = @DeliveryNo
      AND d.PONumber   = @PONumber
      AND ISNULL(d.isCancelled, 0) = 0
) AS a
CROSS JOIN
(
    SELECT CASE WHEN EXISTS (SELECT 1 FROM dbo.PurchaseOrderSummary AS p WHERE p.PONumber = @PONumber)
                 AND NOT EXISTS (SELECT 1 FROM dbo.TransferOrderSummary AS t WHERE t.PONumber = @PONumber)
                THEN 1 ELSE 0 END AS IsSalesOrder
) AS so;
GO

------------------------------------------------------------------
-- 3. Trigger: a line changes -> its delivery's counters
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
IF OBJECT_ID('dbo.fn_SODelivery_LiveTotals', 'IF') IS NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[89] stopped: fn_SODelivery_LiveTotals was not created; everything rolled back.', 16, 1);
    SET NOEXEC ON;
END
GO
CREATE TRIGGER dbo.trg_DeliveryDetails_SOTotals
ON dbo.DeliveryDetails
AFTER INSERT, UPDATE, DELETE
AS
/*
    [89] 2026-10-15. Keeps a sales-order delivery's DeliverySummary counters
    equal to its lines (rule: dbo.fn_SODelivery_LiveTotals). STS transfers
    are skipped (IsSalesOrder = 0). Writes only rows whose values differ.
*/
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted)
        RETURN;

    -- an UPDATE that touched none of the columns the counters depend on
    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
       AND NOT (UPDATE(QtyDelivered) OR UPDATE(ActualQty) OR UPDATE(isCancelled)
                OR UPDATE(isReturned) OR UPDATE(DeliveryNo) OR UPDATE(PONumber))
        RETURN;

    UPDATE s
    SET TotalItem         = t.TotalItem,
        TotalItemSold     = t.TotalItemSold,
        TotalItemReturned = t.TotalItemReturned,
        TotalQtyDelivered = t.TotalQtyDelivered,
        TotalActualQty    = t.TotalActualQty
    FROM (SELECT DeliveryNo, PONumber FROM inserted
          UNION
          SELECT DeliveryNo, PONumber FROM deleted) AS k
    INNER JOIN dbo.DeliverySummary AS s
        ON  s.DeliveryNo = k.DeliveryNo
        AND s.PONumber   = k.PONumber
    CROSS APPLY dbo.fn_SODelivery_LiveTotals(s.DeliveryNo, s.PONumber) AS t
    WHERE t.IsSalesOrder = 1
      AND (   ISNULL(s.TotalItem, -1)         <> t.TotalItem
           OR ISNULL(s.TotalItemSold, -1)     <> t.TotalItemSold
           OR ISNULL(s.TotalItemReturned, -1) <> t.TotalItemReturned
           OR ISNULL(s.TotalQtyDelivered, -1) <> t.TotalQtyDelivered
           OR ISNULL(s.TotalActualQty, -1)    <> t.TotalActualQty);
END
GO

------------------------------------------------------------------
-- 4. Trigger: a proc writes a counter -> put back to the rule
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
IF OBJECT_ID('dbo.trg_DeliveryDetails_SOTotals', 'TR') IS NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[89] stopped: trg_DeliveryDetails_SOTotals was not created; everything rolled back.', 16, 1);
    SET NOEXEC ON;
END
GO
CREATE TRIGGER dbo.trg_DeliverySummary_SOTotals
ON dbo.DeliverySummary
AFTER INSERT, UPDATE
AS
/*
    [89] 2026-10-15. Whatever a proc writes into TotalItem / TotalItemSold /
    TotalItemReturned / TotalQtyDelivered / TotalActualQty of a sales-order
    delivery is put back to its lines (rule: dbo.fn_SODelivery_LiveTotals).
    Save, cancel, confirm and return keep their own formulas; this corrects
    them in the same statement. STS transfers are skipped. Writes only rows
    whose values differ. Returns at once when fired by
    trg_DeliveryDetails_SOTotals (that trigger has just set the rule).
*/
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM inserted)
        RETURN;

    IF TRIGGER_NESTLEVEL(OBJECT_ID('dbo.trg_DeliveryDetails_SOTotals'), 'AFTER', 'DML') > 0
        RETURN;

    -- an UPDATE of other columns only (Status, InvoiceNo, ...)
    IF EXISTS (SELECT 1 FROM deleted)
       AND NOT (UPDATE(TotalItem) OR UPDATE(TotalItemSold) OR UPDATE(TotalItemReturned)
                OR UPDATE(TotalQtyDelivered) OR UPDATE(TotalActualQty)
                OR UPDATE(DeliveryNo) OR UPDATE(PONumber))
        RETURN;

    UPDATE s
    SET TotalItem         = t.TotalItem,
        TotalItemSold     = t.TotalItemSold,
        TotalItemReturned = t.TotalItemReturned,
        TotalQtyDelivered = t.TotalQtyDelivered,
        TotalActualQty    = t.TotalActualQty
    FROM (SELECT DISTINCT DeliveryNo, PONumber FROM inserted WHERE PONumber IS NOT NULL) AS k
    INNER JOIN dbo.DeliverySummary AS s
        ON  s.DeliveryNo = k.DeliveryNo
        AND s.PONumber   = k.PONumber
    CROSS APPLY dbo.fn_SODelivery_LiveTotals(s.DeliveryNo, s.PONumber) AS t
    WHERE t.IsSalesOrder = 1
      AND (   ISNULL(s.TotalItem, -1)         <> t.TotalItem
           OR ISNULL(s.TotalItemSold, -1)     <> t.TotalItemSold
           OR ISNULL(s.TotalItemReturned, -1) <> t.TotalItemReturned
           OR ISNULL(s.TotalQtyDelivered, -1) <> t.TotalQtyDelivered
           OR ISNULL(s.TotalActualQty, -1)    <> t.TotalActualQty);
END
GO

------------------------------------------------------------------
-- 5. Data repair (after the triggers: nothing can slip in between)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
IF OBJECT_ID('dbo.trg_DeliverySummary_SOTotals', 'TR') IS NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[89] stopped: trg_DeliverySummary_SOTotals was not created; everything rolled back.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID('dbo.DeliverySummary_Counters_Backup_20261015', 'U') IS NULL
    CREATE TABLE dbo.DeliverySummary_Counters_Backup_20261015
    (
        DeliveryNo            VARCHAR(20)   NOT NULL,
        PONumber              VARCHAR(20)   NULL,
        Status                VARCHAR(50)   NULL,
        Old_TotalItem         INT           NULL,
        Old_TotalItemSold     INT           NULL,
        Old_TotalItemReturned INT           NULL,
        Old_TotalQtyDelivered DECIMAL(18,3) NULL,
        Old_TotalActualQty    DECIMAL(18,3) NULL,
        New_TotalItem         INT           NULL,
        New_TotalItemSold     INT           NULL,
        New_TotalItemReturned INT           NULL,
        New_TotalQtyDelivered DECIMAL(18,3) NULL,
        New_TotalActualQty    DECIMAL(18,3) NULL,
        BackedUpAt            DATETIME2(0)  NOT NULL CONSTRAINT DF_DSCounters89_BackedUpAt DEFAULT (SYSDATETIME()),
        BackedUpBy            SYSNAME       NOT NULL CONSTRAINT DF_DSCounters89_BackedUpBy DEFAULT (SUSER_SNAME())
    );
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
INSERT INTO dbo.DeliverySummary_Counters_Backup_20261015
    (DeliveryNo, PONumber, Status,
     Old_TotalItem, Old_TotalItemSold, Old_TotalItemReturned, Old_TotalQtyDelivered, Old_TotalActualQty,
     New_TotalItem, New_TotalItemSold, New_TotalItemReturned, New_TotalQtyDelivered, New_TotalActualQty)
SELECT s.DeliveryNo, s.PONumber, s.Status,
       s.TotalItem, s.TotalItemSold, s.TotalItemReturned, s.TotalQtyDelivered, s.TotalActualQty,
       t.TotalItem, t.TotalItemSold, t.TotalItemReturned, t.TotalQtyDelivered, t.TotalActualQty
FROM dbo.DeliverySummary AS s
CROSS APPLY dbo.fn_SODelivery_LiveTotals(s.DeliveryNo, s.PONumber) AS t
WHERE s.PONumber IS NOT NULL
  AND t.IsSalesOrder = 1
  AND (   ISNULL(s.TotalItem, -1)         <> t.TotalItem
       OR ISNULL(s.TotalItemSold, -1)     <> t.TotalItemSold
       OR ISNULL(s.TotalItemReturned, -1) <> t.TotalItemReturned
       OR ISNULL(s.TotalQtyDelivered, -1) <> t.TotalQtyDelivered
       OR ISNULL(s.TotalActualQty, -1)    <> t.TotalActualQty);
PRINT '[89] deliveries backed up for repair: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

-- (trg_DeliverySummary_SOTotals fires on this UPDATE, finds nothing differing and writes nothing)
UPDATE s
SET TotalItem         = t.TotalItem,
    TotalItemSold     = t.TotalItemSold,
    TotalItemReturned = t.TotalItemReturned,
    TotalQtyDelivered = t.TotalQtyDelivered,
    TotalActualQty    = t.TotalActualQty
FROM dbo.DeliverySummary AS s
CROSS APPLY dbo.fn_SODelivery_LiveTotals(s.DeliveryNo, s.PONumber) AS t
WHERE s.PONumber IS NOT NULL
  AND t.IsSalesOrder = 1
  AND (   ISNULL(s.TotalItem, -1)         <> t.TotalItem
       OR ISNULL(s.TotalItemSold, -1)     <> t.TotalItemSold
       OR ISNULL(s.TotalItemReturned, -1) <> t.TotalItemReturned
       OR ISNULL(s.TotalQtyDelivered, -1) <> t.TotalQtyDelivered
       OR ISNULL(s.TotalActualQty, -1)    <> t.TotalActualQty);
PRINT '[89] deliveries repaired: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
GO

------------------------------------------------------------------
-- 6. Post-check, then commit
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);

IF OBJECT_ID('dbo.trg_DeliverySummary_SOTotals', 'TR') IS NULL
   OR OBJECT_ID('dbo.trg_DeliveryDetails_SOTotals', 'TR') IS NULL
    SET @msg = N'a [89] trigger is missing';
ELSE IF EXISTS (SELECT 1 FROM sys.triggers
                WHERE name IN ('trg_DeliveryDetails_SOTotals', 'trg_DeliverySummary_SOTotals') AND is_disabled = 1)
    SET @msg = N'a [89] trigger is disabled';
ELSE IF EXISTS (SELECT 1
                FROM dbo.DeliverySummary AS s
                CROSS APPLY dbo.fn_SODelivery_LiveTotals(s.DeliveryNo, s.PONumber) AS t
                WHERE s.PONumber IS NOT NULL
                  AND t.IsSalesOrder = 1
                  AND (   ISNULL(s.TotalItem, -1)         <> t.TotalItem
                       OR ISNULL(s.TotalItemSold, -1)     <> t.TotalItemSold
                       OR ISNULL(s.TotalItemReturned, -1) <> t.TotalItemReturned
                       OR ISNULL(s.TotalQtyDelivered, -1) <> t.TotalQtyDelivered
                       OR ISNULL(s.TotalActualQty, -1)    <> t.TotalActualQty))
    SET @msg = N'a sales-order delivery still differs from its lines';

IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[89] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59890, @msg, 1;
END

COMMIT TRANSACTION;
PRINT '[89] committed: fn_SODelivery_LiveTotals, trg_DeliveryDetails_SOTotals, trg_DeliverySummary_SOTotals; counters repaired.';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
