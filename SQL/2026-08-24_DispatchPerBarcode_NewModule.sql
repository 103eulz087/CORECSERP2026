SET NOCOUNT ON;
PRINT '=== Dispatch Per Barcode: new HO dispatch module (barcode/FIFO-Auto/FIFO-Manual), mirrors Conversion Per Barcode (HOFormsDevEx/DispatchPerBarcode.cs) ===';
GO

/* ================================================================================
   All NEW objects. Nothing existing (sp_AddBranchOrder, sp_AddBranchOrderBatch,
   sp_ConfirmBranchOrderSTS, AddBranchOrderSTS.cs, AddBranchOrderSTSBatchMode.cs)
   is touched, altered, or even called by this file. This is a parallel,
   additive way to dispatch an APPROVED Transfer Order request from whichever
   branch is doing the dispatching to the requesting branch, reusing the
   existing shared tables (TransferOrderSummary, DeliveryDetails,
   DeliverySummary, Inventory, InventoryDeliveryFIFO) so receiving/
   reporting/GL keep working unchanged regardless of which screen created
   the dispatch.

   Same 3-source-method pattern as Conversion Per Barcode (scan barcode /
   pick product + FIFO-Auto walk-oldest-lot-first / pick product + FIFO-Manual
   scoped to one ShipmentNo+ReferenceCode batch), all resolving to the same
   row shape (InventorySeqNo, Barcode, ProductCode, Description, Qty, Cost)
   before one atomic Submit does everything: race-safe deduct origin
   Inventory, create destination Inventory, write DeliveryDetails +
   InventoryDeliveryFIFO, upsert DeliverySummary, post the IT-HO-VAT/
   IT-HO-VATEX GL ticket (same mnemonics sp_ConfirmBranchOrderSTS already
   posts) -- scoped to only what THIS submit contributed, so dispatching the
   same PO across multiple sessions never double-posts.

   Reversal is NOT reimplemented here -- the new form's Posted-tab Reverse
   action calls the existing, already-fixed dbo.sp_ReverseSTSInventoryTransfer
   (SQL\2026-08-24_STS_AccountingIntegrityFixes.sql) directly, the same way
   ReceivedSTSBatchMode.cs already does. It operates on DeliveryNo/PONumber/
   ProductNo/Qty/DevSeqNo, so it works regardless of which screen created the
   DeliveryDetails row.

   ONE FLAGGED UNCERTAINTY -- read before trusting this in production:
   dbo.InventoryDeliveryFIFO has no CREATE TABLE in this repo. Its column
   order/meaning is inferred with high confidence by cross-referencing two
   independent, currently-live INSERT statements that both use the identical
   15-value positional pattern (SQL\2026-08-01_AddBranchOrder_DevDetSeqNo_Fix.sql,
   sp_AddHRIOrderByBarcode and sp_SalesQtyToInventoryQtyHRI). Both of those
   reference calls hardcode position 13 (a bit flag) to literal 0 -- in this
   proc that position is instead the ORIGIN lot's real IsVat value, since
   sp_ConfirmBranchOrderSTS demonstrably reads a real IsVat column back out of
   this table for VAT/VAT-exempt GL splitting (a column that's always 0 could
   never produce a nonzero "withvat" bucket). This is the single most
   important thing to verify on a test database before trusting this proc.

   POST-REVIEW HARDENING (sp-reviewer pass, same day): spu_PostSTSDispatch now
   (1) enforces TransferOrderDetails.ApprovedQty per product, not just the
   request-level Status='APPROVED' -- Status alone doesn't prove THIS
   product/quantity was approved; (2) rejects a resubmit of already-dispatched
   barcodes under the same DeliveryNo/PONumber (duplicate-click/retry guard);
   (3) takes an sp_getapplock on @DeliveryNo to serialize concurrent submits
   (fixes a SeqNo-generation race and a DeliverySummary first-insert race);
   (4) re-reads Cost live from the origin Inventory row instead of trusting
   the @Lines TVP, matching the IsVat re-read that was already there --
   Cost/IsVat both drive the GL VAT split, so both need to come from the
   locked row, not client-staged data; (5) only flips
   TransferOrderSummary.isProcess once every approved product for the PO is
   fully dispatched, not on the first partial dispatch (the picker filters on
   isProcess=0, so flipping it early would hide a not-yet-fully-dispatched PO).
   The two TVP types below are also now create-once-only (never DROP+CREATE)
   since a redeploy would otherwise fail with error 3732 while
   spu_PostSTSDispatch/the FIFO breakdown procs still reference them.

   ORIGIN BRANCH IS NOW DYNAMIC (2026-08-25): earlier versions of this file
   hardcoded '888' (HO) as the only possible dispatch origin. Per explicit
   correction, the origin is now whichever branch is actually doing the
   dispatching (Login.assignedBranch in the C# form, threaded through as
   @OriginBranch everywhere) -- HO is just one branch among others that can
   dispatch, not a special case. This means:
     - The IsWarehouse=1 filter was DROPPED from every lookup SP (barcode
       scan, both FIFO dropdowns, both FIFO breakdowns) -- it only matched
       HO-warehouse-tagged stock, which would have shown zero dispatchable
       items for any branch that doesn't tag its stock that way.
     - sp_GetApprovedTransferOrdersForDispatch now takes @OriginBranch and
       only returns POs THIS branch is the approved supplier for
       (TransferOrderSummary.BranchCode) -- previously it showed every
       approved, not-yet-dispatched PO regardless of who was supposed to
       supply it.
     - spu_PostSTSDispatch now THROWs if @OriginBranch doesn't match
       TransferOrderSummary.BranchCode -- the same kind of guard it already
       had for @DestinationBranch vs InitiatingBranch, just for the other
       side of the transfer.
     - DeliveryDetails gained a new OriginBranch column (guarded ALTER TABLE
       below), written per dispatched line, because origin can no longer be
       assumed to always be '888' when Reverse looks a historical dispatch
       back up later.
     - The IT-HO-VAT/IT-HO-VATEX GL tickets now post under @OriginBranch
       instead of a fixed '888' -- a deliberate, confirmed deviation from
       sp_ConfirmBranchOrderSTS, which still deliberately keeps that ticket
       family pinned to HO/888 regardless of which branch confirms receipt.
       The two procs now disagree on this by design; don't "fix" one to
       match the other without re-confirming which behavior is wanted.
   ================================================================================ */

-- =============================================
-- TVPs
-- =============================================
-- NOT dropped-and-recreated on redeploy: spu_PostSTSDispatch (and the FIFO breakdown
-- procs below) take these as parameter types, so DROP TYPE fails with error 3732 the
-- moment ANY procedure -- including one already renamed to a timestamped backup by an
-- earlier run of this very script -- still references it. Table types can't be ALTERed
-- either, so "create once, never touch again" is the safe re-runnable form here; a real
-- shape change would need the dependent procs dropped first in a dedicated migration.
IF TYPE_ID('dbo.tt_STSDispatchStagedLots') IS NULL
BEGIN
    CREATE TYPE dbo.tt_STSDispatchStagedLots AS TABLE
    (
        InventorySeqNo INT           NOT NULL,
        Qty            DECIMAL(18,3) NOT NULL CHECK (Qty > 0)
    );
END
GO

IF TYPE_ID('dbo.tt_STSDispatchLines') IS NULL
BEGIN
    CREATE TYPE dbo.tt_STSDispatchLines AS TABLE
    (
        InventorySeqNo INT           NOT NULL,
        Barcode        VARCHAR(100)  NOT NULL,
        ProductCode    VARCHAR(50)   NOT NULL,
        Description    VARCHAR(150)  NULL,
        Qty            DECIMAL(18,3) NOT NULL,
        Cost           DECIMAL(18,4) NOT NULL
    );
END
GO

-- =============================================
-- Dispatch is now origin-branch-dynamic (see 2026-08-25 addendum below) --
-- OriginBranch persists, per dispatched line, which branch actually supplied
-- the stock, since that's no longer always '888' and can't be safely
-- re-derived after the fact from Inventory.Branch (InventoryDeliveryFIFO's
-- column names aren't confirmed enough to query by name -- see header).
-- Needed for correct Reverse (restore stock to the branch it actually came
-- from, not whichever branch happens to click Reverse).
-- =============================================
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.DeliveryDetails')
                 AND name = 'OriginBranch')
    ALTER TABLE dbo.DeliveryDetails ADD OriginBranch VARCHAR(10) NULL;
GO

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-24; updated 2026-08-25
-- Description: Header PO picker for Dispatch Per Barcode -- APPROVED, not
--              yet fully dispatched Transfer Order requests that THIS
--              dispatching branch is actually responsible for supplying
--              (TransferOrderSummary.BranchCode), same filter
--              ViewBranchOrderSTS.cs's own "for dispatch" tab already uses
--              (Status='APPROVED' AND isProcess=0) plus the branch scope.
-- =============================================
IF OBJECT_ID('dbo.sp_GetApprovedTransferOrdersForDispatch', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetApprovedTransferOrdersForDispatch', 'sp_GetApprovedTransferOrdersForDispatch_OLD_08252026090000';
GO

CREATE PROCEDURE dbo.sp_GetApprovedTransferOrdersForDispatch
    @OriginBranch VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        t.PONumber,
        t.InitiatingBranch AS DestinationBranch,
        t.EffectivityDate,
        t.TotalQty,
        CONCAT(t.PONumber, ' - Branch ', t.InitiatingBranch) AS DisplayText
    FROM dbo.TransferOrderSummary AS t WITH (NOLOCK)
    WHERE t.Status = 'APPROVED'
      AND ISNULL(t.isProcess, 0) = 0
      AND t.BranchCode = @OriginBranch
    ORDER BY t.PONumber DESC;
END
GO

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-24; updated 2026-08-25
-- Description: Barcode-scan lookup for Dispatch Per Barcode -- mirrors
--              sp_GetInventoryByBarcode (Conversion module) exactly, scoped
--              to whichever branch is doing the dispatching (@BranchCode =
--              Login.assignedBranch). No IsWarehouse filter -- dispatch can
--              originate from any branch's regular stock, not just an
--              HO-warehouse-flagged subset (a non-HO branch's dispatchable
--              stock generally isn't IsWarehouse=1 at all).
-- =============================================
IF OBJECT_ID('dbo.sp_GetInventoryByBarcodeForDispatch', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetInventoryByBarcodeForDispatch', 'sp_GetInventoryByBarcodeForDispatch_OLD_08252026090000';
GO

CREATE PROCEDURE dbo.sp_GetInventoryByBarcodeForDispatch
    @Barcode    VARCHAR(100),
    @BranchCode VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1
        i.SequenceNumber,
        i.Product AS ProductCode,
        i.Description,
        i.Available,
        i.Cost,
        i.Barcode
    FROM dbo.Inventory AS i WITH (NOLOCK)
    WHERE i.Barcode = @Barcode
      AND i.Branch = @BranchCode
      AND i.IsStock = 1
      AND i.Available > 0;
END
GO

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-24; updated 2026-08-25
-- Description: Product dropdown (FIFO Auto) for Dispatch Per Barcode --
--              mirrors sp_GetInventoryForConversionDropdown, scoped to
--              whichever branch is dispatching. No IsWarehouse filter --
--              see sp_GetInventoryByBarcodeForDispatch's header note.
-- =============================================
IF OBJECT_ID('dbo.sp_GetInventoryForDispatchDropdown', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetInventoryForDispatchDropdown', 'sp_GetInventoryForDispatchDropdown_OLD_08252026090000';
GO

CREATE PROCEDURE dbo.sp_GetInventoryForDispatchDropdown
    @BranchCode VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        i.Product AS ProductCode,
        MAX(i.Description) AS Description,
        SUM(i.Available) AS Available,
        CONCAT(i.Product, ' - ', MAX(i.Description)) AS DisplayText
    FROM dbo.Inventory AS i WITH (NOLOCK)
    WHERE i.Branch = @BranchCode
      AND i.IsStock = 1
      AND i.Available > 0
    GROUP BY i.Product
    ORDER BY MAX(i.Description);
END
GO

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-24; updated 2026-08-25
-- Description: Product+Shipment dropdown (FIFO Manual) for Dispatch Per
--              Barcode -- mirrors sp_GetInventoryForConversionManualDropdown,
--              scoped to whichever branch is dispatching. No IsWarehouse
--              filter -- see sp_GetInventoryByBarcodeForDispatch's header note.
-- =============================================
IF OBJECT_ID('dbo.sp_GetInventoryForDispatchManualDropdown', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetInventoryForDispatchManualDropdown', 'sp_GetInventoryForDispatchManualDropdown_OLD_08252026090000';
GO

CREATE PROCEDURE dbo.sp_GetInventoryForDispatchManualDropdown
    @BranchCode VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        CONCAT(i.Product, '||', i.ShipmentNo, '||', i.ReferenceCode) AS LookupKey,
        i.ShipmentNo                                                 AS ShipmentNo,
        i.ReferenceCode                                              AS ReferenceCode,
        i.Product                                                    AS ProductCode,
        MAX(i.Description)                                           AS Description,
        SUM(i.Available)                                             AS Available,
        CONCAT(i.Product, ' - ', MAX(i.Description))                 AS DisplayText
    FROM dbo.Inventory AS i WITH (NOLOCK)
    WHERE i.Branch = @BranchCode
      AND i.IsStock = 1
      AND i.Available > 0
    GROUP BY i.Product, i.ShipmentNo, i.ReferenceCode
    ORDER BY MAX(i.Description), i.ShipmentNo, i.ReferenceCode;
END
GO

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-24; updated 2026-08-25
-- Description: FIFO breakdown (Auto) for Dispatch Per Barcode -- mirrors
--              sp_GetInventoryFIFOBreakdown exactly, scoped to whichever
--              branch is dispatching (no IsWarehouse filter -- see
--              sp_GetInventoryByBarcodeForDispatch's header note), nets out
--              @AlreadyStaged the same way.
-- =============================================
IF OBJECT_ID('dbo.sp_GetDispatchFIFOBreakdown', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetDispatchFIFOBreakdown', 'sp_GetDispatchFIFOBreakdown_OLD_08252026090000';
GO

CREATE PROCEDURE dbo.sp_GetDispatchFIFOBreakdown
    @ProductCode   VARCHAR(50),
    @BranchCode    VARCHAR(50),
    @RequestedQty  DECIMAL(18,3),
    @AlreadyStaged dbo.tt_STSDispatchStagedLots READONLY
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF @RequestedQty IS NULL OR @RequestedQty <= 0
            THROW 59411, 'Requested quantity must be greater than zero.', 1;

        DECLARE @Lots TABLE (
            SequenceNumber INT,
            Barcode        VARCHAR(100),
            Description    VARCHAR(150),
            Available      DECIMAL(18,3),
            Cost           DECIMAL(18,4)
        );

        INSERT INTO @Lots (SequenceNumber, Barcode, Description, Available, Cost)
        SELECT
            i.SequenceNumber,
            i.Barcode,
            i.Description,
            i.Available - ISNULL(s.StagedQty, 0),
            i.Cost
        FROM dbo.Inventory AS i WITH (NOLOCK)
        LEFT JOIN (
            SELECT InventorySeqNo, SUM(Qty) AS StagedQty
            FROM @AlreadyStaged
            GROUP BY InventorySeqNo
        ) AS s ON s.InventorySeqNo = i.SequenceNumber
        WHERE i.Branch = @BranchCode
          AND i.Product = @ProductCode
          AND i.IsStock = 1
          AND (i.Available - ISNULL(s.StagedQty, 0)) > 0
        ORDER BY i.SequenceNumber ASC;

        DECLARE @Result TABLE (
            ResultSeq      INT IDENTITY(1,1),
            SequenceNumber INT,
            Barcode        VARCHAR(100),
            ProductCode    VARCHAR(50),
            Description    VARCHAR(150),
            Qty            DECIMAL(18,3),
            Cost           DECIMAL(18,4)
        );

        DECLARE @Remaining DECIMAL(18,3) = @RequestedQty;
        DECLARE @seq INT, @barcode VARCHAR(100), @desc VARCHAR(150), @avail DECIMAL(18,3), @cost DECIMAL(18,4), @take DECIMAL(18,3);

        DECLARE dispfifo_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT SequenceNumber, Barcode, Description, Available, Cost FROM @Lots ORDER BY SequenceNumber ASC;

        OPEN dispfifo_cur;
        FETCH NEXT FROM dispfifo_cur INTO @seq, @barcode, @desc, @avail, @cost;

        WHILE @@FETCH_STATUS = 0 AND @Remaining > 0
        BEGIN
            SET @take = CASE WHEN @avail >= @Remaining THEN @Remaining ELSE @avail END;

            INSERT INTO @Result (SequenceNumber, Barcode, ProductCode, Description, Qty, Cost)
            VALUES (@seq, @barcode, @ProductCode, @desc, @take, @cost);

            SET @Remaining -= @take;

            FETCH NEXT FROM dispfifo_cur INTO @seq, @barcode, @desc, @avail, @cost;
        END

        CLOSE dispfifo_cur;
        DEALLOCATE dispfifo_cur;

        SELECT SequenceNumber, Barcode, ProductCode, Description, Qty, Cost
        FROM @Result
        ORDER BY ResultSeq ASC;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'dispfifo_cur') >= 0
            CLOSE dispfifo_cur;
        IF CURSOR_STATUS('local', 'dispfifo_cur') = -1
            DEALLOCATE dispfifo_cur;
        THROW;
    END CATCH
END
GO

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-24; updated 2026-08-25
-- Description: FIFO breakdown (Manual) for Dispatch Per Barcode -- mirrors
--              sp_GetInventoryFIFOBreakdownByShipment exactly, scoped to
--              whichever branch is dispatching (no IsWarehouse filter --
--              see sp_GetInventoryByBarcodeForDispatch's header note).
-- =============================================
IF OBJECT_ID('dbo.sp_GetDispatchFIFOBreakdownByShipment', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetDispatchFIFOBreakdownByShipment', 'sp_GetDispatchFIFOBreakdownByShipment_OLD_08252026090000';
GO

CREATE PROCEDURE dbo.sp_GetDispatchFIFOBreakdownByShipment
    @ProductCode   VARCHAR(50),
    @BranchCode    VARCHAR(50),
    @ShipmentNo    VARCHAR(10),
    @ReferenceCode VARCHAR(50),
    @RequestedQty  DECIMAL(18,3),
    @AlreadyStaged dbo.tt_STSDispatchStagedLots READONLY
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF @RequestedQty IS NULL OR @RequestedQty <= 0
            THROW 59412, 'Requested quantity must be greater than zero.', 1;

        DECLARE @Lots TABLE (
            SequenceNumber INT,
            Barcode        VARCHAR(100),
            Description    VARCHAR(150),
            Available      DECIMAL(18,3),
            Cost           DECIMAL(18,4)
        );

        INSERT INTO @Lots (SequenceNumber, Barcode, Description, Available, Cost)
        SELECT
            i.SequenceNumber,
            i.Barcode,
            i.Description,
            i.Available - ISNULL(s.StagedQty, 0),
            i.Cost
        FROM dbo.Inventory AS i WITH (NOLOCK)
        LEFT JOIN (
            SELECT InventorySeqNo, SUM(Qty) AS StagedQty
            FROM @AlreadyStaged
            GROUP BY InventorySeqNo
        ) AS s ON s.InventorySeqNo = i.SequenceNumber
        WHERE i.Branch = @BranchCode
          AND i.Product = @ProductCode
          AND i.ShipmentNo = @ShipmentNo
          AND ISNULL(i.ReferenceCode, '') = ISNULL(@ReferenceCode, '')
          AND i.IsStock = 1
          AND (i.Available - ISNULL(s.StagedQty, 0)) > 0
        ORDER BY i.SequenceNumber ASC;

        DECLARE @Result TABLE (
            ResultSeq      INT IDENTITY(1,1),
            SequenceNumber INT,
            Barcode        VARCHAR(100),
            ProductCode    VARCHAR(50),
            Description    VARCHAR(150),
            Qty            DECIMAL(18,3),
            Cost           DECIMAL(18,4)
        );

        DECLARE @Remaining DECIMAL(18,3) = @RequestedQty;
        DECLARE @seq INT, @barcode VARCHAR(100), @desc VARCHAR(150), @avail DECIMAL(18,3), @cost DECIMAL(18,4), @take DECIMAL(18,3);

        DECLARE dispfifoshp_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT SequenceNumber, Barcode, Description, Available, Cost FROM @Lots ORDER BY SequenceNumber ASC;

        OPEN dispfifoshp_cur;
        FETCH NEXT FROM dispfifoshp_cur INTO @seq, @barcode, @desc, @avail, @cost;

        WHILE @@FETCH_STATUS = 0 AND @Remaining > 0
        BEGIN
            SET @take = CASE WHEN @avail >= @Remaining THEN @Remaining ELSE @avail END;

            INSERT INTO @Result (SequenceNumber, Barcode, ProductCode, Description, Qty, Cost)
            VALUES (@seq, @barcode, @ProductCode, @desc, @take, @cost);

            SET @Remaining -= @take;

            FETCH NEXT FROM dispfifoshp_cur INTO @seq, @barcode, @desc, @avail, @cost;
        END

        CLOSE dispfifoshp_cur;
        DEALLOCATE dispfifoshp_cur;

        SELECT SequenceNumber, Barcode, ProductCode, Description, Qty, Cost
        FROM @Result
        ORDER BY ResultSeq ASC;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'dispfifoshp_cur') >= 0
            CLOSE dispfifoshp_cur;
        IF CURSOR_STATUS('local', 'dispfifoshp_cur') = -1
            DEALLOCATE dispfifoshp_cur;
        THROW;
    END CATCH
END
GO

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-24; updated 2026-08-25
-- Description: Atomic Dispatch Per Barcode submit. Validates the Transfer
--              Order is APPROVED and that @OriginBranch (the dispatching
--              user's own branch, Login.assignedBranch -- no longer
--              hardcoded to HO/888) is the branch the request expects to
--              supply it (TransferOrderSummary.BranchCode), race-safe
--              deducts origin Inventory, creates destination-branch
--              Inventory (same Barcode/Cost as origin -- a transfer moves
--              the same physical goods, unlike Conversion which creates
--              genuinely new stock), writes DeliveryDetails (including the
--              OriginBranch actually used, for correct Reverse later) +
--              InventoryDeliveryFIFO, upserts DeliverySummary
--              ('FOR DELIVERY'), posts IT-HO-VAT/IT-HO-VATEX (same
--              mnemonics/pattern sp_ConfirmBranchOrderSTS already uses, but
--              under @OriginBranch rather than a fixed '888' -- a deliberate
--              deviation from that sibling proc's convention, confirmed)
--              scoped to only this call's lines -- safe to call again for
--              the same PONumber (partial dispatch across sessions) without
--              double-posting GL for earlier lines.
--
--              Reuses the existing dbo.sp_GetDeliveryNumber numbering SP
--              (already used by AddBranchOrderSTS.cs) and, when a
--              DeliverySummary already exists for this PONumber (a prior
--              partial dispatch), the SAME DeliveryNo must be passed in by
--              the caller -- this proc does not generate one itself.
-- =============================================
IF OBJECT_ID('dbo.spu_PostSTSDispatch', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_PostSTSDispatch', 'spu_PostSTSDispatch_OLD_08252026090000';
GO

CREATE PROCEDURE dbo.spu_PostSTSDispatch
    @DeliveryNo        VARCHAR(20),
    @ReferenceNo       VARCHAR(10),
    @PONumber          VARCHAR(10),
    @OriginBranch      VARCHAR(10),
    @DestinationBranch VARCHAR(10),
    @DispatchedBy      VARCHAR(50),
    @Lines             dbo.tt_STSDispatchLines READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        ------------------------------------------------------------------
        -- 1. Validate everything BEFORE any write
        ------------------------------------------------------------------
        IF NOT EXISTS (SELECT 1 FROM @Lines)
            THROW 59401, 'No items to dispatch.', 1;

        DECLARE @transferStatus VARCHAR(30), @effectivitydate DATE, @approvedDestBranch VARCHAR(10), @approvedOriginBranch VARCHAR(10);
        SELECT @transferStatus = Status, @effectivitydate = EffectivityDate,
               @approvedDestBranch = InitiatingBranch, @approvedOriginBranch = BranchCode
        FROM dbo.TransferOrderSummary WHERE PONumber = @PONumber;

        IF @transferStatus IS NULL
            THROW 59402, 'Transfer Order request not found.', 1;
        IF @transferStatus <> 'APPROVED'
            THROW 59403, 'Cannot dispatch: this Transfer Order request has not been approved.', 1;
        IF @approvedDestBranch <> @DestinationBranch
            THROW 59409, 'Destination branch does not match the branch this Transfer Order request was approved for.', 1;
        IF @approvedOriginBranch <> @OriginBranch
            THROW 59410, 'Your branch is not the one this Transfer Order request expects to supply it.', 1;

        SET @effectivitydate = ISNULL(@effectivitydate, CAST(GETDATE() AS DATE));

        -- Duplicate-submission guard: a UI double-click or a client retry after a
        -- timeout would otherwise resubmit the identical @Lines and, for any lot not
        -- yet fully depleted, sail past the availability check below and double-post.
        -- Reject up front if any of these barcodes are already dispatched-and-not-
        -- reversed under this exact DeliveryNo/PONumber.
        IF EXISTS (
            SELECT 1 FROM dbo.DeliveryDetails AS dd
            INNER JOIN @Lines AS l ON l.Barcode = dd.BarcodeNo
            WHERE dd.DeliveryNo = @DeliveryNo AND dd.PONumber = @PONumber
              AND dd.isReturned = 0 AND dd.isCancelled = 0
        )
            THROW 59405, 'One or more of these items has already been dispatched under this Delivery No/PO. Please refresh and try again.', 1;

        -- Enforce the actual approval, not just the request's overall Status:
        -- TransferOrderSummary.Status = 'APPROVED' only proves the REQUEST was
        -- approved, not that THIS product/quantity was. sp_ApproveTransferOrder
        -- writes the real per-product ceiling into TransferOrderDetails.ApprovedQty;
        -- already-dispatched-and-not-returned quantity plus this call must not
        -- exceed it.
        IF EXISTS (
            SELECT l.ProductCode
            FROM (SELECT ProductCode, SUM(Qty) AS ThisCallQty FROM @Lines GROUP BY ProductCode) AS l
            LEFT JOIN (
                SELECT ProductNo, SUM(QtyDelivered) AS AlreadyDispatched
                FROM dbo.DeliveryDetails
                WHERE PONumber = @PONumber AND isReturned = 0 AND isCancelled = 0
                GROUP BY ProductNo
            ) AS already ON already.ProductNo = l.ProductCode
            LEFT JOIN dbo.TransferOrderDetails AS approved
                ON approved.PONumber = @PONumber AND approved.ProductCode = l.ProductCode
            WHERE ISNULL(already.AlreadyDispatched, 0) + l.ThisCallQty > ISNULL(approved.ApprovedQty, 0)
        )
            THROW 59406, 'One or more items exceed the quantity approved for this Transfer Order request.', 1;

        ------------------------------------------------------------------
        -- 2. Fail fast if a scanned/selected lot clearly no longer has
        --    enough Available (good error UX). The authoritative, race-safe
        --    check is the UPDLOCK'd deduction in step 4.
        ------------------------------------------------------------------
        IF EXISTS (
            SELECT 1 FROM @Lines AS l
            INNER JOIN dbo.Inventory AS i ON i.SequenceNumber = l.InventorySeqNo
            WHERE i.Branch <> @OriginBranch OR i.Available < l.Qty OR i.IsStock = 0
        )
            THROW 59404, 'One of the scanned/selected items no longer has enough available stock. Please rescan/reselect.', 1;

        BEGIN TRANSACTION;

        -- Serialize concurrent submits against the same DeliveryNo -- also protects
        -- the SeqNo generation and the DeliverySummary first-insert race below from
        -- two sessions dispatching against the same PO at once. Released
        -- automatically at COMMIT/ROLLBACK since @LockOwner = 'Transaction'.
        DECLARE @lockResult INT;
        EXEC @lockResult = sp_getapplock @Resource = @DeliveryNo, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 15000;
        IF @lockResult < 0
            THROW 59407, 'Could not acquire a lock for this delivery (another session may be dispatching against it right now). Please try again.', 1;

        ------------------------------------------------------------------
        -- 3. Next DeliveryDetails.SeqNo for this delivery (0 if brand new)
        ------------------------------------------------------------------
        DECLARE @NextSeqNo INT;
        SELECT @NextSeqNo = ISNULL(MAX(SeqNo), 0) FROM dbo.DeliveryDetails WHERE DeliveryNo = @DeliveryNo AND PONumber = @PONumber;

        ------------------------------------------------------------------
        -- 4. Race-safe deduction at origin (whichever branch is dispatching)
        ------------------------------------------------------------------
        DECLARE @LineCount INT = (SELECT COUNT(*) FROM @Lines);

        UPDATE i
        SET i.Available = i.Available - l.Qty,
            i.LastMovementDate = GETDATE()
        FROM dbo.Inventory AS i WITH (UPDLOCK, ROWLOCK)
        INNER JOIN @Lines AS l ON l.InventorySeqNo = i.SequenceNumber
        WHERE i.Branch = @OriginBranch AND i.IsStock = 1 AND i.Available >= l.Qty;

        IF @@ROWCOUNT <> @LineCount
            THROW 59404, 'One of the scanned/selected items no longer has enough available stock (it may have changed concurrently). Please rescan/reselect.', 1;

        UPDATE dbo.Inventory
        SET IsStock = 0
        WHERE SequenceNumber IN (SELECT InventorySeqNo FROM @Lines)
          AND Branch = @OriginBranch
          AND Available <= 0;

        ------------------------------------------------------------------
        -- 5. Per line: destination Inventory row, DeliveryDetails,
        --    InventoryDeliveryFIFO audit row. Barcode carried over from
        --    origin -- this moves the same physical goods, it doesn't
        --    create new ones. Cost and IsVat are re-read live from the
        --    ORIGIN Inventory row (NOT trusted from @Lines/TVP) since they
        --    directly drive the GL VAT/VAT-exempt split below -- @Lines.Cost
        --    was only ever used for the client-side staging total, never
        --    for what actually gets posted.
        ------------------------------------------------------------------
        DECLARE @invseq INT, @prodcode VARCHAR(50), @desc VARCHAR(150), @qty DECIMAL(18,3), @cost DECIMAL(18,4),
                @barcode VARCHAR(100), @isvat BIT, @sellingprice DECIMAL(18,2), @newseq INT;
        DECLARE @totalcostvat DECIMAL(18,2) = 0, @totalcostnonvat DECIMAL(18,2) = 0;

        DECLARE dispatch_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT l.InventorySeqNo, l.ProductCode, l.Description, l.Qty, i.Cost, l.Barcode, ISNULL(i.IsVat, 0) AS IsVat
            FROM @Lines AS l
            INNER JOIN dbo.Inventory AS i ON i.SequenceNumber = l.InventorySeqNo;

        OPEN dispatch_cur;
        FETCH NEXT FROM dispatch_cur INTO @invseq, @prodcode, @desc, @qty, @cost, @barcode, @isvat;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @NextSeqNo += 1;
            SET @sellingprice = NULL;

            SELECT @sellingprice = SellingPrice FROM dbo.Products WHERE ProductCode = @prodcode AND BranchCode = @OriginBranch;

            INSERT INTO dbo.Inventory
                (Branch, ShipmentNo, PalletNo, BatchCode, DateReceived, ExpiryDate, Product, Description, Barcode,
                 TipWeight, Quantity, Cost, Available, QtyBigBlue, IsStock, IsVat, IsWarehouse, ReferenceCode,
                 LastMovementDate, isProcess, isSource, isConversion)
            VALUES
                (@DestinationBranch, @DeliveryNo, 0, 0, GETDATE(), NULL, @prodcode, @desc, @barcode,
                 @qty, @qty, @cost, @qty, 0, 1, @isvat, 0, @PONumber,
                 GETDATE(), 0, 0, 0);

            SET @newseq = SCOPE_IDENTITY();

            INSERT INTO dbo.DeliveryDetails
                (SeqNo, DeliveryNo, PONumber, ReferenceNumber, ProductNo, BarcodeNo, ProductName,
                 QtyDelivered, ActualQty, Variance, Cost, SellingPrice, [Status], isVat,
                 ProcessedBy, isSettled, isCreditMemo, isReturned, isCancelled, OriginBranch)
            VALUES
                (@NextSeqNo, @DeliveryNo, @PONumber, @ReferenceNo, @prodcode, @barcode, @desc,
                 @qty, @qty, 0, @cost, ISNULL(@sellingprice, 0), 'PENDING', @isvat,
                 @DispatchedBy, 0, 0, 0, 0, @OriginBranch);

            -- Positional (no CREATE TABLE available for this table in-repo --
            -- see the header note). Order/meaning cross-referenced against
            -- two independent live INSERTs using this same 15-value shape.
            -- Position 13 (@isvat) is the one deliberate departure from
            -- those references, which both hardcode it to 0 -- see header.
            INSERT INTO InventoryDeliveryFIFO
            VALUES (@DeliveryNo, @PONumber, @DestinationBranch, @prodcode, @desc, @qty, @cost, ROUND(@qty * @cost, 2),
                    GETDATE(), @invseq, @NextSeqNo, 0, @isvat, ISNULL(@sellingprice, 0), ROUND(@qty * ISNULL(@sellingprice, 0), 2));

            IF @isvat = 1
                SET @totalcostvat += ROUND(@qty * @cost, 2);
            ELSE
                SET @totalcostnonvat += ROUND(@qty * @cost, 2);

            FETCH NEXT FROM dispatch_cur INTO @invseq, @prodcode, @desc, @qty, @cost, @barcode, @isvat;
        END

        CLOSE dispatch_cur;
        DEALLOCATE dispatch_cur;

        ------------------------------------------------------------------
        -- 6. DeliverySummary header (insert first time, update thereafter --
        --    same upsert shape sp_ConfirmBranchOrderSTS already uses).
        --    Safe from a two-session first-insert race because of the
        --    sp_getapplock taken in step 2.
        ------------------------------------------------------------------
        DECLARE @totalitem INT, @totalqtydelivered DECIMAL(18,3);
        SELECT @totalitem = COUNT(*), @totalqtydelivered = SUM(QtyDelivered)
        FROM dbo.DeliveryDetails
        WHERE DeliveryNo = @DeliveryNo AND PONumber = @PONumber AND isReturned = 0 AND isCancelled = 0;

        IF NOT EXISTS (SELECT 1 FROM dbo.DeliverySummary WHERE DeliveryNo = @DeliveryNo AND PONumber = @PONumber)
        BEGIN
            INSERT INTO dbo.DeliverySummary
                (DeliveryNo, PONumber, ReferenceNumber, InvoiceNo, BranchCode,
                 TotalItem, TotalQtyDelivered, TotalActualQty, TotalVarianceVat,
                 TotalVarianceVatExempt, EffectivityDate, [Status], DateAdded,
                 PreparedBy, isSettled, isInvoiceUpdate)
            VALUES
                (@DeliveryNo, @PONumber, @ReferenceNo, @ReferenceNo, @DestinationBranch,
                 @totalitem, @totalqtydelivered, 0, 0,
                 0, @effectivitydate, 'FOR DELIVERY', GETDATE(),
                 @DispatchedBy, 0, 0);
        END
        ELSE
        BEGIN
            UPDATE dbo.DeliverySummary
            SET TotalItem = @totalitem,
                TotalQtyDelivered = @totalqtydelivered,
                Status = 'FOR DELIVERY'
            WHERE DeliveryNo = @DeliveryNo AND PONumber = @PONumber;
        END

        ------------------------------------------------------------------
        -- 7. GL ticket -- scoped to THIS call's lines only (@totalcostvat/
        --    @totalcostnonvat), so repeated submits for the same PO never
        --    double-post an earlier submit's amount.
        ------------------------------------------------------------------
        DECLARE @outrefnum VARCHAR(10), @Particulars VARCHAR(400);

        IF @totalcostvat > 0
        BEGIN
            DECLARE @AmtsVAT dbo.tt_AmountBreakdown, @TokVAT dbo.tt_TokenResolution, @FlgVAT dbo.tt_ConditionFlags;
            INSERT @AmtsVAT VALUES ('GROSS', @totalcostvat);
            SET @Particulars = 'Inventory Transfer Out - PO#' + @PONumber + ' (Branch ' + @OriginBranch + ' to Branch ' + @DestinationBranch + ')- VATable';
            EXEC GetReferenceNumber @outrefnum OUTPUT;

            EXEC dbo.sp_PostCompoundTicket
                @Mnemonic = 'IT-HO-VAT', @TicketDate = @effectivitydate, @BranchCode = @OriginBranch,
                @ReferenceNumber = @outrefnum, @ReferenceKey = @PONumber, @Particulars = @Particulars,
                @Owner = 'CS IN TRANSIT', @PreparedBy = @DispatchedBy,
                @Amounts = @AmtsVAT, @Tokens = @TokVAT, @Flags = @FlgVAT,
                @LedgerType = NULL, @LedgerEntityID = NULL, @LedgerInvoiceNo = NULL,
                @LedgerBatchRef = @PONumber, @LedgerSeqRef = 1;
        END

        IF @totalcostnonvat > 0
        BEGIN
            DECLARE @AmtsVE dbo.tt_AmountBreakdown, @TokVE dbo.tt_TokenResolution, @FlgVE dbo.tt_ConditionFlags;
            INSERT @AmtsVE VALUES ('GROSS', @totalcostnonvat);
            SET @Particulars = 'Inventory Transfer Out - PO#' + @PONumber + ' (Branch ' + @OriginBranch + ' to Branch ' + @DestinationBranch + ')- VAT Exempt';
            EXEC GetReferenceNumber @outrefnum OUTPUT;

            EXEC dbo.sp_PostCompoundTicket
                @Mnemonic = 'IT-HO-VATEX', @TicketDate = @effectivitydate, @BranchCode = @OriginBranch,
                @ReferenceNumber = @outrefnum, @ReferenceKey = @PONumber, @Particulars = @Particulars,
                @Owner = 'CS IN TRANSIT', @PreparedBy = @DispatchedBy,
                @Amounts = @AmtsVE, @Tokens = @TokVE, @Flags = @FlgVE,
                @LedgerType = NULL, @LedgerEntityID = NULL, @LedgerInvoiceNo = NULL,
                @LedgerBatchRef = @PONumber, @LedgerSeqRef = 2;
        END

        ------------------------------------------------------------------
        -- 8. Mark the request dispatched ONLY once every approved product
        --    has been fully dispatched -- NOT on every partial dispatch.
        --    sp_GetApprovedTransferOrdersForDispatch filters on isProcess=0,
        --    so flipping it on the first partial submit would hide the PO
        --    from the picker before the remaining approved quantity has
        --    actually gone out, contradicting this module's own multi-
        --    session partial-dispatch design (see header).
        ------------------------------------------------------------------
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.TransferOrderDetails AS td
            LEFT JOIN (
                SELECT ProductNo, SUM(QtyDelivered) AS Dispatched
                FROM dbo.DeliveryDetails
                WHERE PONumber = @PONumber AND isReturned = 0 AND isCancelled = 0
                GROUP BY ProductNo
            ) AS d ON d.ProductNo = td.ProductCode
            WHERE td.PONumber = @PONumber
              AND ISNULL(td.ApprovedQty, 0) > 0
              AND ISNULL(d.Dispatched, 0) < td.ApprovedQty
        )
        BEGIN
            UPDATE dbo.TransferOrderSummary SET isProcess = '1' WHERE PONumber = @PONumber;
        END

        INSERT INTO HistoryLogs
        VALUES (@DispatchedBy, GETDATE(), 'Dispatch Per Barcode PONumber=' + @PONumber, @DestinationBranch);

        COMMIT TRANSACTION;

        SELECT 1 AS [Status], 'Dispatch posted.' AS [Message];
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'dispatch_cur') >= 0
            CLOSE dispatch_cur;
        IF CURSOR_STATUS('local', 'dispatch_cur') = -1
            DEALLOCATE dispatch_cur;
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- =============================================
-- Posted-tab list for Dispatch Per Barcode -- reads the same DeliverySummary
-- every other STS screen already writes to.
-- =============================================
IF OBJECT_ID('dbo.vw_STSDispatchSummary', 'V') IS NOT NULL
    EXEC sp_rename 'dbo.vw_STSDispatchSummary', 'vw_STSDispatchSummary_OLD_08242026150000';
GO

CREATE VIEW dbo.vw_STSDispatchSummary
AS
SELECT
    DeliveryNo,
    PONumber,
    ReferenceNumber,
    BranchCode AS DestinationBranch,
    TotalItem,
    TotalQtyDelivered,
    [Status],
    EffectivityDate,
    DateAdded,
    PreparedBy
FROM dbo.DeliverySummary;
GO

PRINT 'DEPLOYMENT COMPLETE: tt_STSDispatchStagedLots, tt_STSDispatchLines, sp_GetApprovedTransferOrdersForDispatch, sp_GetInventoryByBarcodeForDispatch, sp_GetInventoryForDispatchDropdown, sp_GetInventoryForDispatchManualDropdown, sp_GetDispatchFIFOBreakdown, sp_GetDispatchFIFOBreakdownByShipment, spu_PostSTSDispatch, vw_STSDispatchSummary.';
