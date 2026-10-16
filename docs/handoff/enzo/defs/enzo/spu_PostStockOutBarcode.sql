
CREATE PROCEDURE [dbo].[spu_PostStockOutBarcode]
    @RefNo      VARCHAR(20),
    @BranchCode VARCHAR(50),
    @Category   VARCHAR(100),
    @Remarks    VARCHAR(259),
    @PreparedBy VARCHAR(50),
    @Lines      dbo.tt_StockOutBarcodeLines READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        ------------------------------------------------------------------
        -- 1. Validate everything BEFORE any write
        ------------------------------------------------------------------
        IF NOT EXISTS (SELECT 1 FROM @Lines)
            THROW 59501, 'No items to stock out.', 1;

        IF EXISTS (SELECT 1 FROM dbo.StockOutBarcodeSummary WHERE RefNo = @RefNo)
            THROW 59502, 'This Stock-Out Reference Number has already been posted.', 1;

        -- Reject a scanned lot (InventorySeqNo) appearing more than once --
        -- otherwise totals/audit rows count it twice while the Inventory
        -- deduction below only ever applies once per lot.
        IF EXISTS (SELECT InventorySeqNo FROM @Lines GROUP BY InventorySeqNo HAVING COUNT(*) > 1)
            THROW 59503, 'The same scanned item (Inventory lot) appears more than once in this batch. Please rescan.', 1;

        ------------------------------------------------------------------
        -- 2. Fail fast if a scanned lot clearly no longer has enough
        --    Available (good error UX). The authoritative, race-safe check
        --    is the UPDLOCK'd deduction in step 4 below.
        ------------------------------------------------------------------
        IF EXISTS (
            SELECT 1
            FROM @Lines AS l
            INNER JOIN dbo.Inventory AS i ON i.SequenceNumber = l.InventorySeqNo
            WHERE i.Branch <> @BranchCode OR i.Available < l.Qty OR i.IsStock = 0 and i.IsWarehouse=1
        )
            THROW 59504, 'One of the scanned items no longer has enough available stock. Please rescan.', 1;

        DECLARE @TotalQty DECIMAL(18,3), @TotalCost DECIMAL(18,2);
        SELECT @TotalQty = SUM(Qty), @TotalCost = SUM(Qty * Cost) FROM @Lines;

        BEGIN TRANSACTION;

        ------------------------------------------------------------------
        -- 3. Header + detail lines
        ------------------------------------------------------------------
        INSERT INTO dbo.StockOutBarcodeSummary
            (RefNo, BranchCode, Category, Remarks, TotalQty, TotalCost, Status, DateAdded, PreparedBy)
        VALUES
            (@RefNo, @BranchCode, @Category, @Remarks, @TotalQty, @TotalCost, 'POSTED', GETDATE(), @PreparedBy);

        INSERT INTO dbo.StockOutBarcodeDetails
            (RefNo, SeqNo, InventorySeqNo, Barcode, ProductCode, Description, Qty, Cost, Amount)
        SELECT
            @RefNo,
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
            InventorySeqNo, Barcode, ProductCode, Description, Qty, Cost, Qty * Cost
        FROM @Lines;

        ------------------------------------------------------------------
        -- 4. Race-safe deduction. UPDLOCK + re-checking Available >= Qty at
        --    the moment of deduction (not just the step-2 fail-fast check)
        --    closes the race window between step 2 and this transaction.
        ------------------------------------------------------------------
        DECLARE @LineCount INT = (SELECT COUNT(*) FROM @Lines);

        UPDATE i
        SET i.Available = i.Available - l.Qty,
            i.LastMovementDate = GETDATE()
        FROM dbo.Inventory AS i WITH (UPDLOCK, ROWLOCK)
        INNER JOIN @Lines AS l ON l.InventorySeqNo = i.SequenceNumber
        WHERE i.Branch = @BranchCode AND i.IsStock = 1 AND i.Available >= l.Qty AND i.IsWarehouse = 1;

        IF @@ROWCOUNT <> @LineCount
            THROW 59504, 'One of the scanned items no longer has enough available stock (it may have changed concurrently). Please rescan.', 1;

        UPDATE dbo.Inventory
        SET IsStock = 0
        WHERE SequenceNumber IN (SELECT InventorySeqNo FROM @Lines)
          AND Available <= 0
          AND IsWarehouse = 1;

        COMMIT TRANSACTION;

        SELECT 1 AS [Status], 'Stock-out posted.' AS [Message];
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        -- Bare THROW (not RAISERROR('%s', ...)) preserves the original error
        -- number (59501-59504 above) so callers can distinguish failure
        -- reasons instead of everything collapsing to error 50000.
        THROW;
    END CATCH
END
