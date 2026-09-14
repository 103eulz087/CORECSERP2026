SET NOCOUNT ON;
PRINT '=== ReceivedSTS-from-FIFO: new parallel receiving module carrying source-lot ReferenceCode ===';
GO

/* ================================================================================
   Context (2026-09-07): the existing STS receiving flow (Orders/ReceivedSTS.cs ->
   HOFormsDevEx/ReceivedSTSBatchMode.cs) sources its grid from
   funcview_DeliveryDetailsForReceiving(@PONumber), which reads dbo.DeliveryDetails.
   DeliveryDetails has NO ReferenceCode column at all -- and the destination
   Inventory row is created at DISPATCH time by spu_PostSTSDispatch with
   ReferenceCode stamped to @PONumber, NOT the true source lot's own ReferenceCode
   (which sits one join away via InventoryDeliveryFIFO.SequenceNumber -> the
   origin branch's Inventory.ReferenceCode).

   This script adds a fully parallel receiving path that carries the true source
   ReferenceCode through to the receiving branch's Inventory row, WITHOUT touching
   the existing module: funcview_DeliveryDetailsForReceiving, sp_AddBranchInventoryBatch,
   and ReceivedSTSBatchMode.cs are untouched. The return/reversal step
   (sp_ReverseSTSInventoryTransfer) and finalize/GL-post step
   (sp_ConfirmBranchRecievedOrder / JFC) are REUSED unchanged -- both operate at
   the PONumber/DeliveryNo level, not the grid-source level, and are already
   GL-correct.

   Because spu_PostSTSDispatch already inserts the destination Inventory row at
   dispatch time (confirmed: SQL\2026-08-24_DispatchPerBarcode_NewModule.sql:661-668),
   this module's target population -- STS lines dispatched via DispatchPerBarcode.cs,
   the only path that writes InventoryDeliveryFIFO rows -- already has that
   destination row waiting. spu_PostSTSReceiveFromFIFO below therefore UPDATEs it
   (correcting ReferenceCode + reconciling any ActualQty variance); if it's missing
   that's data drift, not an expected case, so the SP THROWs rather than silently
   fabricating a fresh, untraceable Inventory row. This sidesteps needing to know
   sp_AddBranchInventoryBatch's internals (not sourced anywhere in this repo) --
   this new module never calls it.

   CORRECTION (2026-09-09): the paragraph above is wrong about the legacy
   AddBranchOrderSTS.cs path, and it caused a real production-blocking bug --
   traced and fixed in
   SQL/2026-09-09_spu_PostSTSReceiveFromFIFO_FallbackInsertDestinationRow.sql.
   AddBranchOrderSTS.cs calls sp_AddBranchOrderByBarcode, which DOES insert an
   InventoryDeliveryFIFO row (confirmed against the live SP body on
   CORECSERP_002_DEV) -- so those lines DO appear in
   funcview_InventoryDeliveryFIFOForReceiving, exactly like DispatchPerBarcode.cs
   lines. What it does NOT do is create the destination-branch Inventory row
   (it only zeroes the origin row) -- only spu_PostSTSDispatch does that. Before
   the 2026-09-09 fix, spu_PostSTSReceiveFromFIFO's THROW 58171 on a missing
   destination row silently rolled back the entire receive batch for exactly
   this population of lines. See the 2026-09-09 file's header for the fix.
   ================================================================================ */

------------------------------------------------------------------
-- 1. dbo.tt_STSReceiveFIFOLines -- TVP for checked/received rows.
--    Dedicated to this module per the "own TVPs, don't reuse another
--    module's" convention -- not the same shape as dbo.InventoryItemType.
------------------------------------------------------------------
-- Create-once, never DROP/recreate: DROP TYPE fails (error 3732) the moment
-- ANY procedure -- including one already renamed to a timestamped backup --
-- still references it. Same convention tt_STSDispatchStagedLots/
-- tt_STSDispatchLines already use, for the same reason.
IF TYPE_ID('dbo.tt_STSReceiveFIFOLines') IS NULL
BEGIN
    CREATE TYPE dbo.tt_STSReceiveFIFOLines AS TABLE
    (
        SeqNo        INT           NOT NULL,  -- DeliveryDetails.SeqNo for this line
        DeliveryNo   VARCHAR(20)   NOT NULL,
        ProductCode  VARCHAR(50)   NOT NULL,
        Barcode      VARCHAR(120)  NOT NULL,
        ActualQty    DECIMAL(18,3) NOT NULL CHECK (ActualQty > 0),
        SellingPrice DECIMAL(18,2) NULL
    );
END
GO

------------------------------------------------------------------
-- 2. Guarded schema addition: ReceivedOrderDetails.ReferenceCode --
--    audit trail of which source lot each received line came from.
------------------------------------------------------------------
IF COL_LENGTH('dbo.ReceivedOrderDetails', 'ReferenceCode') IS NULL
BEGIN
    ALTER TABLE dbo.ReceivedOrderDetails ADD ReferenceCode VARCHAR(20) NULL;
END
GO

------------------------------------------------------------------
-- 3. funcview_InventoryDeliveryFIFOForReceiving -- read-only source for
--    ReceivedSTSBatchModeFIFO.cs's grid. Same isReturned/isCancelled
--    filter convention as funcview_DeliveryDetailsForReceiving, PLUS an
--    explicit exclusion of lines already posted through
--    spu_PostSTSReceiveFromFIFO (that SP's own duplicate-receive guard
--    prevents double-posting even without this, but without this filter
--    an already-received line would keep reappearing in the grid), plus
--    the source-lot ReferenceCode pulled through InventoryDeliveryFIFO.
------------------------------------------------------------------
IF OBJECT_ID('dbo.funcview_InventoryDeliveryFIFOForReceiving_OLD_09072026120000', 'IF') IS NOT NULL
    DROP FUNCTION dbo.funcview_InventoryDeliveryFIFOForReceiving_OLD_09072026120000;
GO
IF OBJECT_ID('dbo.funcview_InventoryDeliveryFIFOForReceiving', 'IF') IS NOT NULL
    EXEC sp_rename 'dbo.funcview_InventoryDeliveryFIFOForReceiving', 'funcview_InventoryDeliveryFIFOForReceiving_OLD_09072026120000';
GO

CREATE FUNCTION dbo.funcview_InventoryDeliveryFIFOForReceiving
(
    @PONumber VARCHAR(10)
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        dd.SeqNo,
        dd.DeliveryNo,
        dd.PONumber,
        dd.ReferenceNumber,
        dd.ProductNo,
        dd.ProductName,
        dd.BarcodeNo,
        dd.QtyDelivered,
        dd.ActualQty,
        dd.Cost,
        dd.SellingPrice,
        dd.isVat,
        src.ReferenceCode AS SourceReferenceCode,
        src.ShipmentNo    AS SourceShipmentNo,
        src.Branch        AS SourceBranch
    FROM dbo.DeliveryDetails dd
    INNER JOIN dbo.InventoryDeliveryFIFO f
        ON f.DevDetSeqNo = dd.SeqNo
       AND f.PONumber = dd.PONumber
       AND f.isErrorCorrect = 0
    INNER JOIN dbo.Inventory src
        ON src.SequenceNumber = f.SequenceNumber
    WHERE dd.PONumber = @PONumber
      AND dd.isReturned = 0
      AND dd.isCancelled = 0
      AND NOT EXISTS (
          SELECT 1 FROM dbo.ReceivedOrderDetails r
          WHERE r.PONumber = dd.PONumber AND r.Barcode = dd.BarcodeNo
      )
);
GO

------------------------------------------------------------------
-- 4. spu_PostSTSReceiveFromFIFO -- atomic receive-posting SP for this
--    module. Per checked line: re-derives the source ReferenceCode
--    SERVER-SIDE (never trusts a client-supplied value -- the grid only
--    displays it, the TVP doesn't carry it), then UPDATEs the
--    destination Inventory row dispatch already created if one exists
--    (matched on the exact tuple spu_PostSTSDispatch stamped it with:
--    Branch+ShipmentNo+Product+Barcode), reconciling ReferenceCode and
--    any ActualQty-vs-QtyDelivered variance (net-accumulated into
--    Available, never overwritten -- see CLAUDE.md's gross/net bug
--    pattern). THROWs if no such row exists -- per the confirmed design
--    every line reaching this SP came through InventoryDeliveryFIFO, and
--    spu_PostSTSDispatch always creates the matching destination row, so
--    a missing row means data drift worth investigating, not a case to
--    silently paper over with a fabricated, untraceable Inventory row.
--    Duplicate-receive guarded per line via ReceivedOrderDetails
--    (PONumber+Barcode -- ReceivedOrderDetails has no DeliveryNo column)
--    -- skip-and-report, not a hard abort, so one already-processed line
--    in a resubmitted batch doesn't block the rest.
--    Concurrent submits for the same PO are serialized via sp_getapplock.
------------------------------------------------------------------
IF OBJECT_ID('dbo.spu_PostSTSReceiveFromFIFO_OLD_09072026120000', 'P') IS NOT NULL
    DROP PROCEDURE dbo.spu_PostSTSReceiveFromFIFO_OLD_09072026120000;
GO
IF OBJECT_ID('dbo.spu_PostSTSReceiveFromFIFO', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_PostSTSReceiveFromFIFO', 'spu_PostSTSReceiveFromFIFO_OLD_09072026120000';
GO

CREATE PROCEDURE dbo.spu_PostSTSReceiveFromFIFO
    @PONumber   VARCHAR(10),
    @BranchCode VARCHAR(10),
    @ReceivedBy VARCHAR(50),
    @Lines      dbo.tt_STSReceiveFIFOLines READONLY
AS
/*
    Receives checked STS lines whose dispatch-side lot is traceable via
    InventoryDeliveryFIFO, carrying the true source Inventory.ReferenceCode
    through to the receiving branch's Inventory row.
    Returns: one result set -- @SkippedLines (SeqNo, Barcode, Reason) for
             any line skipped as an already-processed duplicate.
    Assumes: @Lines rows correspond to still-unresolved DeliveryDetails
             lines for @PONumber (funcview_InventoryDeliveryFIFOForReceiving's
             filter already guarantees this at read time).
    Callers: HOFormsDevEx/ReceivedSTSBatchModeFIFO.cs
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @SkippedLines TABLE (SeqNo INT, Barcode VARCHAR(120), Reason VARCHAR(200));

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM @Lines)
        BEGIN
            SELECT SeqNo, Barcode, Reason FROM @SkippedLines;
            RETURN;
        END

        BEGIN TRANSACTION;

        -- ── Serialize concurrent submits for the same PO (double-click
        --    Submit, a retried timeout) so the duplicate-receive guard below
        --    can't be raced by two sessions both passing it before either
        --    commits. Locked on @PONumber (broader than a single DeliveryNo,
        --    since one receive batch can span multiple deliveries under the
        --    same PO) -- same fix spu_PostSTSDispatch already applies via
        --    sp_getapplock on @DeliveryNo. ──
        DECLARE @LockResult INT;
        EXEC @LockResult = sp_getapplock
            @Resource = @PONumber, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 30000;
        IF @LockResult < 0
            THROW 58170, 'Could not acquire a lock on this delivery -- another receive is already in progress. Please try again.', 1;

        DECLARE @SeqNo INT, @DeliveryNo VARCHAR(20), @ProductCode VARCHAR(50),
                @Barcode VARCHAR(120), @ActualQty DECIMAL(18,3), @SellingPrice DECIMAL(18,4);

        DECLARE line_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT SeqNo, DeliveryNo, ProductCode, Barcode, ActualQty, SellingPrice FROM @Lines;

        OPEN line_cur;
        FETCH NEXT FROM line_cur INTO @SeqNo, @DeliveryNo, @ProductCode, @Barcode, @ActualQty, @SellingPrice;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- ── Duplicate-receive guard (PONumber+Barcode --
            --    ReceivedOrderDetails has no DeliveryNo column) ──
            IF EXISTS (SELECT 1 FROM dbo.ReceivedOrderDetails
                       WHERE PONumber = @PONumber AND Barcode = @Barcode)
            BEGIN
                INSERT INTO @SkippedLines (SeqNo, Barcode, Reason)
                VALUES (@SeqNo, @Barcode, 'Already received (duplicate PONumber+Barcode).');

                FETCH NEXT FROM line_cur INTO @SeqNo, @DeliveryNo, @ProductCode, @Barcode, @ActualQty, @SellingPrice;
                CONTINUE;
            END

            -- ── Re-derive the source lot's ReferenceCode server-side --
            --    never trust a client-supplied value for something this
            --    identity-sensitive. Also pull Cost/IsVat/ProductName off
            --    DeliveryDetails -- ReceivedOrderDetails.Cost and .IsVat
            --    are NOT NULL columns confirmed against the live schema
            --    (INFORMATION_SCHEMA.COLUMNS on CORECSERP_002_DEV, 2026-09-07). ──
            DECLARE @SourceReferenceCode VARCHAR(20), @ProductName VARCHAR(50),
                    @LineCost DECIMAL(10,2), @LineIsVat BIT;

            SELECT TOP 1
                @SourceReferenceCode = src.ReferenceCode,
                @ProductName         = dd.ProductName,
                @LineCost            = dd.Cost,
                @LineIsVat           = dd.isVat
            FROM dbo.DeliveryDetails dd
            INNER JOIN dbo.InventoryDeliveryFIFO f
                ON f.DevDetSeqNo = dd.SeqNo AND f.PONumber = dd.PONumber AND f.isErrorCorrect = 0
            INNER JOIN dbo.Inventory src
                ON src.SequenceNumber = f.SequenceNumber
            WHERE dd.SeqNo = @SeqNo AND dd.PONumber = @PONumber AND dd.DeliveryNo = @DeliveryNo;

            IF @SourceReferenceCode IS NULL
            BEGIN
                INSERT INTO @SkippedLines (SeqNo, Barcode, Reason)
                VALUES (@SeqNo, @Barcode, 'No source FIFO lot found for this line -- cannot attribute ReferenceCode.');

                FETCH NEXT FROM line_cur INTO @SeqNo, @DeliveryNo, @ProductCode, @Barcode, @ActualQty, @SellingPrice;
                CONTINUE;
            END

            -- ── UPDATE the destination Inventory row dispatch already
            --    created (matched on the exact tuple spu_PostSTSDispatch
            --    stamped it with), reconciling ReferenceCode + variance.
            --    UPDLOCK guards against a concurrent double-submit. ──
            UPDATE dst
            SET dst.ReferenceCode = @SourceReferenceCode,
                dst.Available     = ISNULL(dst.Available, 0) + (@ActualQty - ISNULL(dst.Quantity, 0)),
                dst.Quantity      = @ActualQty,
                dst.LastMovementDate = GETDATE()
            FROM dbo.Inventory dst WITH (UPDLOCK, ROWLOCK)
            WHERE dst.Branch = @BranchCode
              AND dst.ShipmentNo = @DeliveryNo
              AND dst.Product = @ProductCode
              AND dst.Barcode = @Barcode;

            IF @@ROWCOUNT = 0
            BEGIN
                -- ── Per the confirmed design, every line reaching this SP
                --    came through InventoryDeliveryFIFO, and
                --    spu_PostSTSDispatch ALWAYS creates the matching
                --    destination Inventory row in the same transaction that
                --    deducted the origin. A missing row here means data
                --    drift, not an expected case -- surface it loudly
                --    instead of silently fabricating an untraceable
                --    Inventory row with no matching deduction anywhere. ──
                THROW 58171, 'Expected destination Inventory row not found (Branch/ShipmentNo/Product/Barcode) -- dispatch should have created it. Investigate before receiving this line.', 1;
            END

            -- ── Receiving audit trail. ReceivedOrderDetails has no
            --    DeliveryNo/DateReceived/ReceivedBy columns (confirmed
            --    against the live schema) -- PONumber+Barcode identifies
            --    the line, and SeqNo is a plain decimal(3,0), NOT an
            --    identity, so it's generated here the same way
            --    DeliveryDetails.SeqNo is generated in spu_PostSTSDispatch:
            --    per-PONumber MAX+1. Safe under the sp_getapplock on
            --    @PONumber taken above -- no race between this SELECT and
            --    the INSERT within this transaction. ──
            DECLARE @NextReceivedSeqNo DECIMAL(3,0);
            SELECT @NextReceivedSeqNo = ISNULL(MAX(SeqNo), 0) + 1
            FROM dbo.ReceivedOrderDetails
            WHERE PONumber = @PONumber;

            INSERT INTO dbo.ReceivedOrderDetails
                (SeqNo, PONumber, ProductCode, ProductName, Barcode, Qty, Cost, SellingPrice, IsVat, ReferenceCode)
            VALUES
                (@NextReceivedSeqNo, @PONumber, @ProductCode, @ProductName, @Barcode, @ActualQty,
                 ISNULL(@LineCost, 0), ISNULL(@SellingPrice, 0), ISNULL(@LineIsVat, 0), @SourceReferenceCode);

            -- ── Reflect the true received qty back on DeliveryDetails
            --    (this column already exists for exactly this purpose --
            --    Status is left untouched, sp_ConfirmBranchRecievedOrder
            --    owns that transition). ──
            UPDATE dbo.DeliveryDetails
            SET ActualQty = @ActualQty
            WHERE SeqNo = @SeqNo AND PONumber = @PONumber AND DeliveryNo = @DeliveryNo;

            FETCH NEXT FROM line_cur INTO @SeqNo, @DeliveryNo, @ProductCode, @Barcode, @ActualQty, @SellingPrice;
        END

        CLOSE line_cur;
        DEALLOCATE line_cur;

        COMMIT TRANSACTION;

        SELECT SeqNo, Barcode, Reason FROM @SkippedLines;
    END TRY
    BEGIN CATCH
        -- CURSOR_STATUS = -1 means "closed" -- calling CLOSE again on an
        -- already-closed cursor raises its own error and masks the real one.
        -- Same two-step pattern spu_PostSTSDispatch's CATCH block uses.
        IF CURSOR_STATUS('local', 'line_cur') >= 0
            CLOSE line_cur;
        IF CURSOR_STATUS('local', 'line_cur') = -1
            DEALLOCATE line_cur;
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

PRINT 'DEPLOYMENT COMPLETE: tt_STSReceiveFIFOLines, ReceivedOrderDetails.ReferenceCode, funcview_InventoryDeliveryFIFOForReceiving, spu_PostSTSReceiveFromFIFO.';
