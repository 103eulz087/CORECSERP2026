-- Fixes a real receiving failure traced against CORECSERP_002_DEV: a PO
-- dispatched through the LEGACY AddBranchOrderSTS.cs -> sp_AddBranchOrderByBarcode
-- path DOES write an InventoryDeliveryFIFO row (line ~142-148 of that SP), so it
-- correctly appears in ReceivedSTSBatchModeFIFO.cs's grid via
-- funcview_InventoryDeliveryFIFOForReceiving -- but that same SP never creates a
-- destination-branch Inventory row (it only zeroes the ORIGIN row, line ~151-153).
-- Only spu_PostSTSDispatch (the DispatchPerBarcode.cs path) does that. The
-- header comment in SQL/2026-09-07_ReceivedSTSFromFIFO_NewModule.sql assumed the
-- legacy path never wrote InventoryDeliveryFIFO at all -- that assumption was
-- wrong; corrected there too (comment-only, no object changes in that file).
--
-- Previously spu_PostSTSReceiveFromFIFO's @@ROWCOUNT=0 branch (no matching
-- destination Inventory row) THREW 58171, rolling back the WHOLE receive batch
-- -- nothing landed in ReceivedOrderDetails or Inventory for any line in that
-- submit, matching the reported bug exactly. Per user decision: fall back to
-- INSERTing a fresh destination Inventory row instead of throwing, mirroring
-- spu_PostSTSDispatch's own destination-row INSERT
-- (SQL/2026-08-24_DispatchPerBarcode_NewModule.sql:661-668) column-for-column,
-- with one deliberate deviation -- ReferenceCode is set to @SourceReferenceCode
-- (the true source lot, already re-derived server-side a few lines above),
-- NOT @PONumber the way spu_PostSTSDispatch stamps it -- using @PONumber here
-- would silently reintroduce the exact ReferenceCode bug this whole module
-- exists to fix.
--
-- REVISION (same day, before this ever shipped): ledger-integrity-auditor and
-- sp-reviewer both caught real problems in the first cut of this fix. Both
-- fixed here together, per their explicit instruction not to ship one without
-- the other:
--
-- BUG 1 -- the first cut added a second-chance UPDATE ("dst2") keyed by
-- Branch+Product+ShipmentNo+ReferenceCode with NO Barcode predicate, intended
-- as a safety net "in case an equivalent row already exists that the stricter
-- tuple missed." Re-reading that intent against how this data actually looks
-- (SQL\2026-09-07_ItemCostingReport.sql:13-14: one Product+ShipmentNo+
-- ReferenceCode routinely spans thousands of individual barcoded Inventory
-- rows, one per physical unit) shows dst2 could never legitimately help: on a
-- genuinely first receive (the actual bug being fixed here) NO row exists
-- under any key, so dst2 always misses too, exactly like the primary UPDATE --
-- it only ever matches something on a SECOND-OR-LATER barcode of the same lot,
-- which is precisely the corrupting case: unit B2 finds unit B1's just-created
-- row via the barcode-less composite key and overwrites its Barcode/Quantity,
-- silently losing B1's stock from Inventory. Zero benefit for the target
-- scenario, real corruption risk for the common multi-piece-lot case. REMOVED
-- entirely rather than patched -- primary UPDATE (exact 4-column match) -> if
-- that misses, straight to INSERT. No barcode-unscoped second chance remains.
--
-- BUG 2 -- pre-existing, not introduced by this module's first cut, but must
-- ship in the same deploy per the auditor (fixing BUG 1's insert-a-fresh-row
-- behavior without this makes @SourceReferenceCode resolve correctly for the
-- first time, which is exactly what made BUG 1 fire deterministically instead
-- of by rare coincidence). InventoryDeliveryFIFO has two unrelated int
-- columns: SequenceReferenceNumber (nullable, the real FK back to the origin
-- Inventory row -- confirmed via SQL\2026-08-24_STS_AccountingIntegrityFixes.sql:93-95
-- and SQL\2026-08-01_AddBranchOrder_DevDetSeqNo_Fix.sql:294) and SequenceNumber
-- (its own unrelated IDENTITY). Both this SP's inline derivation query AND
-- funcview_InventoryDeliveryFIFOForReceiving (the grid source, same file as
-- the original module) joined "src.SequenceNumber = f.SequenceNumber" -- the
-- WRONG column. Live-data proof on CORECSERP_002_DEV before this fix: of 2781
-- InventoryDeliveryFIFO rows, the wrong join resolves only 33 to any source
-- row at all; the correct join (f.SequenceReferenceNumber) resolves 1116; and
-- of the 33 the wrong join DOES resolve, 27 disagree with the correct answer.
-- This was the DOMINANT failure mode, not a rare coincidence -- most legacy
-- receives were silently no-op'ing into @SkippedLines with "No source FIFO
-- lot found," never even reaching the destination-row logic at all. Fixed in
-- BOTH places: this SP's derivation query, and funcview_InventoryDeliveryFIFOForReceiving
-- below (same file, so the grid and this SP's own re-derivation can't disagree).
--
-- Also noted, not fixed (pre-existing, out of scope, flagged for visibility):
-- @ReceivedBy is accepted but never used anywhere in this body (ReceivedOrderDetails
-- has no column for it). The TVP's Barcode is VARCHAR(120) and DeliveryDetails.BarcodeNo
-- is VARCHAR(120), but Inventory.Barcode is only VARCHAR(35) -- a barcode over
-- 35 chars fails loud (truncation error) on the fallback INSERT, not silently.

-- Inventory carries two filtered indexes (IX_Inventory_ActiveStock_ByBranch,
-- IX_Inventory_FIFO_Engine), so any object that UPDATEs/INSERTs it must be
-- CREATEd with QUOTED_IDENTIFIER ON baked into its metadata (a stored proc's
-- ANSI settings are captured at CREATE time from the connection, not read
-- fresh from the caller's session at execution time) -- confirmed via
-- sys.sql_modules.uses_quoted_identifier: the pre-existing OLD version has it
-- ON, sqlcmd's own session default is OFF. Must stay set before the
-- CREATE PROCEDURE batch below.
SET QUOTED_IDENTIFIER ON;
GO

-- NOTE: spu_PostSTSReceiveFromFIFO_OLD_09092026170000 (the correctly-
-- QUOTED_IDENTIFIER-ON original from 2026-09-07) and
-- spu_PostSTSReceiveFromFIFO_OLD_09092026180000 (the previous, dst2-carrying
-- cut of THIS fix -- kept as a record even though it had the bugs above)
-- already exist and are intentionally left alone; only the current live
-- object is renamed aside.
IF OBJECT_ID('dbo.spu_PostSTSReceiveFromFIFO', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_PostSTSReceiveFromFIFO', 'spu_PostSTSReceiveFromFIFO_OLD_09092026190000';
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

    Per line: tries an exact-identity UPDATE on the destination Inventory row
    (Branch+ShipmentNo+Product+Barcode -- the tuple spu_PostSTSDispatch stamps
    a destination row with at dispatch time). If that misses -- either because
    dispatch happened via the legacy AddBranchOrderSTS.cs path (which never
    creates a destination row at all) or any other reason no row exists under
    that exact identity -- INSERTs a fresh destination row instead, mirroring
    spu_PostSTSDispatch's own column population. No barcode-unscoped second
    chance is attempted in between (removed 2026-09-09; see file header --
    it could only ever match a DIFFERENT barcode's row within the same lot,
    which is corruption, not a legitimate match).

    Returns: one result set -- @SkippedLines (SeqNo, Barcode, Reason) for
             any line skipped as an already-processed duplicate, or for which
             no source FIFO lot could be attributed at all.
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
            --    (INFORMATION_SCHEMA.COLUMNS on CORECSERP_002_DEV, 2026-09-07).
            --    FIX (2026-09-09, BUG 2): join on f.SequenceReferenceNumber,
            --    NOT f.SequenceNumber -- InventoryDeliveryFIFO.SequenceNumber
            --    is that table's OWN unrelated identity column;
            --    SequenceReferenceNumber is the real FK back to the origin
            --    Inventory row (confirmed against
            --    SQL\2026-08-24_STS_AccountingIntegrityFixes.sql:93-95 and
            --    SQL\2026-08-01_AddBranchOrder_DevDetSeqNo_Fix.sql:294). The
            --    old join resolved a source row for only 33 of 2781 live
            --    InventoryDeliveryFIFO rows, and 27 of those 33 were wrong. ──
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
                ON src.SequenceNumber = f.SequenceReferenceNumber
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
                -- ── FIX (2026-09-09, BUG 1): no barcode-unscoped second
                --    chance here anymore -- see file header for why it was
                --    removed rather than patched. Straight to fallback
                --    INSERT: no destination row exists under the exact
                --    identity above, either because this line was dispatched
                --    via the legacy AddBranchOrderSTS.cs path (no destination
                --    row was ever created for it) or any other reason. Insert
                --    a fresh one, mirroring spu_PostSTSDispatch's own
                --    destination-row INSERT column-for-column
                --    (SQL/2026-08-24_DispatchPerBarcode_NewModule.sql:661-668)
                --    -- EXCEPT ReferenceCode, which is @SourceReferenceCode
                --    here (the true source lot), not @PONumber -- using
                --    @PONumber would silently reintroduce the bug this
                --    module exists to fix. ──
                INSERT INTO dbo.Inventory
                    (Branch, ShipmentNo, PalletNo, BatchCode, DateReceived, ExpiryDate, Product, Description, Barcode,
                     TipWeight, Quantity, Cost, Available, QtyBigBlue, IsStock, IsVat, IsWarehouse, ReferenceCode,
                     LastMovementDate, isProcess, isSource, isConversion)
                VALUES
                    (@BranchCode, @DeliveryNo, 0, 0, GETDATE(), NULL, @ProductCode, @ProductName, @Barcode,
                     @ActualQty, @ActualQty, ISNULL(@LineCost, 0), @ActualQty, 0, 1, ISNULL(@LineIsVat, 0), 0, @SourceReferenceCode,
                     GETDATE(), 0, 0, 0);
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

------------------------------------------------------------------
-- BUG 2, second half: funcview_InventoryDeliveryFIFOForReceiving (the grid
-- source ReceivedSTSBatchModeFIFO.cs binds from, defined in
-- SQL/2026-09-07_ReceivedSTSFromFIFO_NewModule.sql) has the exact same wrong
-- join. Fixed here too so the grid and this SP's own re-derivation can never
-- disagree with each other.
------------------------------------------------------------------
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID('dbo.funcview_InventoryDeliveryFIFOForReceiving_OLD_09092026190000', 'IF') IS NOT NULL
    DROP FUNCTION dbo.funcview_InventoryDeliveryFIFOForReceiving_OLD_09092026190000;
GO
IF OBJECT_ID('dbo.funcview_InventoryDeliveryFIFOForReceiving', 'IF') IS NOT NULL
    EXEC sp_rename 'dbo.funcview_InventoryDeliveryFIFOForReceiving', 'funcview_InventoryDeliveryFIFOForReceiving_OLD_09092026190000';
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
        ON src.SequenceNumber = f.SequenceReferenceNumber  -- FIX (2026-09-09, BUG 2): was f.SequenceNumber
    WHERE dd.PONumber = @PONumber
      AND dd.isReturned = 0
      AND dd.isCancelled = 0
      AND NOT EXISTS (
          SELECT 1 FROM dbo.ReceivedOrderDetails r
          WHERE r.PONumber = dd.PONumber AND r.Barcode = dd.BarcodeNo
      )
);
GO

PRINT 'DEPLOYMENT COMPLETE: spu_PostSTSReceiveFromFIFO (dst2 removed, source-lot join fixed), funcview_InventoryDeliveryFIFOForReceiving (source-lot join fixed).';
