SET NOCOUNT ON;
PRINT '=== StockOut Per Barcode: new module (Barcode scan + FIFO Auto/Manual selection), standard inventory-out design per CLAUDE.md ===';
GO

-- =============================================================================
-- WHY ALL-NEW OBJECTS, NOT THE LEGACY StockOutDetails/StockoutSummary/
-- sp_FiFoMappingStockOut/sp_InsertStockOutSummary:
--   The legacy flow (InventoryOut.cs) inserts one StockOutDetails row per line
--   immediately (isDone=0), then a separate "Confirm" step runs
--   sp_FiFoMappingStockOut (FIFO deduction with NO deterministic ORDER BY --
--   relies on physical row order via UPDATE TOP(1) with no ORDER BY) and
--   sp_InsertStockOutSummary. That immediate-insert/isDone-flag lifecycle
--   doesn't fit this module's stage-in-memory-then-post-atomically design
--   (same shape as ConversionPerBarcode/DispatchPerBarcode), and reusing the
--   legacy tables would risk the two flows' rows colliding under shared
--   IDs/queries. New, dedicated tables -- same choice already made for
--   ConversionBarcodeSummary/Details vs. reusing something older.
--   BadOrderReport.cs, ViewStockOutRequest.cs, and InventoryOut.cs itself
--   keep reading/writing the legacy tables entirely untouched.
--
-- WHY THIS MIRRORS spu_PostConversionBarcode'S SOURCE SIDE, NOT
-- spu_PostSTSDispatch:
--   A stock-out is a pure write-off/consumption -- no destination branch, no
--   Transfer Order approval workflow, no GL/VAT posting (the legacy
--   sp_FiFoMappingStockOut doesn't post GL either, only an InventoryLedger
--   audit row). spu_PostSTSDispatch's complexity (destination Inventory
--   creation, sp_PostCompoundTicket GL entries, TransferOrderSummary
--   approval checks) is all inter-branch-transfer-specific and doesn't
--   apply here. Conversion's SOURCE-side deduction (scan/pick lots, UPDLOCK
--   deduct, IsStock=0 cleanup, no output) is architecturally identical to
--   what a stock-out needs -- this script follows that shape exactly, just
--   without an output/destination side at all.
-- =============================================================================

-- =============================================================================
-- Tables
-- =============================================================================
IF OBJECT_ID('dbo.StockOutBarcodeDetails', 'U') IS NULL
BEGIN
    IF OBJECT_ID('dbo.StockOutBarcodeSummary', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.StockOutBarcodeSummary
        (
            RefNo        VARCHAR(20)   NOT NULL PRIMARY KEY,
            BranchCode   VARCHAR(50)   NOT NULL,
            Category     VARCHAR(100)  NOT NULL,
            Remarks      VARCHAR(259)  NULL,
            TotalQty     DECIMAL(18,3) NOT NULL,
            TotalCost    DECIMAL(18,2) NOT NULL,
            Status       VARCHAR(20)   NOT NULL,
            DateAdded    DATETIME      NOT NULL,
            PreparedBy   VARCHAR(50)   NOT NULL,
            ReversedBy   VARCHAR(50)   NULL,
            DateReversed DATETIME      NULL
        );
    END

    CREATE TABLE dbo.StockOutBarcodeDetails
    (
        RefNo          VARCHAR(20)   NOT NULL,
        SeqNo          INT           NOT NULL,
        InventorySeqNo INT           NOT NULL,
        Barcode        VARCHAR(100)  NULL,
        ProductCode    VARCHAR(50)   NOT NULL,
        Description    VARCHAR(150)  NULL,
        Qty            DECIMAL(18,3) NOT NULL,
        Cost           DECIMAL(18,4) NOT NULL,
        Amount         DECIMAL(18,2) NOT NULL,
        CONSTRAINT PK_StockOutBarcodeDetails PRIMARY KEY (RefNo, SeqNo),
        CONSTRAINT FK_StockOutBarcodeDetails_Summary FOREIGN KEY (RefNo)
            REFERENCES dbo.StockOutBarcodeSummary (RefNo)
    );
END
GO

-- =============================================================================
-- Table-valued parameter types
--
-- Create-only guard (never DROP+CREATE): every renamed-away "_OLD_..." backup
-- of a proc that takes one of these TVPs as a parameter keeps a live
-- dependency on the type FOREVER (renaming a proc doesn't remove its
-- parameter-type dependency, and backups are deliberately never dropped) --
-- so a DROP TYPE here would work on a first deploy but permanently fail on
-- any later re-run once even one backup exists, regardless of where in this
-- script the DROP is placed relative to the proc renames. Since neither
-- TVP's shape is expected to change via this kind of routine redeploy, skip
-- the type entirely if it already exists rather than trying to recreate it.
-- =============================================================================
IF TYPE_ID('dbo.tt_StockOutStagedLots') IS NULL
BEGIN
    CREATE TYPE dbo.tt_StockOutStagedLots AS TABLE
    (
        InventorySeqNo INT           NOT NULL,
        Qty            DECIMAL(18,3) NOT NULL CHECK (Qty > 0)
    );
END
GO

IF TYPE_ID('dbo.tt_StockOutBarcodeLines') IS NULL
BEGIN
    CREATE TYPE dbo.tt_StockOutBarcodeLines AS TABLE
    (
        InventorySeqNo INT           NOT NULL,
        Barcode        VARCHAR(100)  NULL,
        ProductCode    VARCHAR(50)   NOT NULL,
        Description    VARCHAR(150)  NULL,
        Qty            DECIMAL(18,3) NOT NULL CHECK (Qty > 0),
        Cost           DECIMAL(18,4) NOT NULL
    );
END
GO

-- =============================================================================
-- Author: Eulz Avancena (original); added 2026-08-25
-- Description: Reference number generator for StockOut Per Barcode, same
--              self-contained MAX+1 shape as sp_GetConversionBarcodeNumber.
-- =============================================================================
IF OBJECT_ID('dbo.sp_GetStockOutBarcodeNumber_OLD_08252026090000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.sp_GetStockOutBarcodeNumber', 'P') IS NOT NULL
        DROP PROCEDURE dbo.sp_GetStockOutBarcodeNumber;
END
ELSE IF OBJECT_ID('dbo.sp_GetStockOutBarcodeNumber', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.sp_GetStockOutBarcodeNumber', 'sp_GetStockOutBarcodeNumber_OLD_08252026090000';
END
GO

CREATE PROCEDURE dbo.sp_GetStockOutBarcodeNumber
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @next INT;

    SELECT @next = ISNULL(MAX(CAST(SUBSTRING(RefNo, 5, 20) AS INT)), 0) + 1
    FROM dbo.StockOutBarcodeSummary WITH (NOLOCK);

    SELECT 'SOB-' + RIGHT('000000' + CAST(@next AS VARCHAR(10)), 6) AS RefNo;
END
GO

-- =============================================================================
-- Author: Eulz Avancena (original); added 2026-08-25
-- Description: Auto-FIFO product dropdown for StockOut's "Select Product
--              (FIFO)" source method -- same shape as
--              sp_GetInventoryForConversionDropdown/ForDispatchDropdown.
-- =============================================================================
IF OBJECT_ID('dbo.sp_GetInventoryForStockOutDropdown_OLD_08252026090000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.sp_GetInventoryForStockOutDropdown', 'P') IS NOT NULL
        DROP PROCEDURE dbo.sp_GetInventoryForStockOutDropdown;
END
ELSE IF OBJECT_ID('dbo.sp_GetInventoryForStockOutDropdown', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.sp_GetInventoryForStockOutDropdown', 'sp_GetInventoryForStockOutDropdown_OLD_08252026090000';
END
GO

CREATE PROCEDURE dbo.sp_GetInventoryForStockOutDropdown
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

-- =============================================================================
-- Author: Eulz Avancena (original); added 2026-08-25
-- Description: Manual-FIFO product+batch dropdown for StockOut's "Select
--              Product (FIFO)" source method when FIFO Type = Manual --
--              grouped by Product+ShipmentNo+ReferenceCode (not ShipmentNo
--              alone) for the same reason already documented and fixed for
--              Conversion's equivalent SP: every Conversion-output lot
--              carries the literal ShipmentNo='CONVERSION' and quantity-
--              adjustment lots carry ShipmentNo='' -- grouping by ShipmentNo
--              alone would pool unrelated batches together. LookupKey
--              (Product||ShipmentNo||ReferenceCode) is the composite
--              ValueMember; ProductCode alone is not unique per row here.
-- =============================================================================
IF OBJECT_ID('dbo.sp_GetInventoryForStockOutManualDropdown_OLD_08252026090000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.sp_GetInventoryForStockOutManualDropdown', 'P') IS NOT NULL
        DROP PROCEDURE dbo.sp_GetInventoryForStockOutManualDropdown;
END
ELSE IF OBJECT_ID('dbo.sp_GetInventoryForStockOutManualDropdown', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.sp_GetInventoryForStockOutManualDropdown', 'sp_GetInventoryForStockOutManualDropdown_OLD_08252026090000';
END
GO

CREATE PROCEDURE dbo.sp_GetInventoryForStockOutManualDropdown
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

-- =============================================================================
-- Author: Eulz Avancena (original); added 2026-08-25
-- Description: Barcode-scan lookup for StockOut's "Scan Barcode" source
--              method -- same shape as sp_GetInventoryByBarcode.
-- =============================================================================
IF OBJECT_ID('dbo.sp_GetInventoryByBarcodeForStockOut_OLD_08252026090000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.sp_GetInventoryByBarcodeForStockOut', 'P') IS NOT NULL
        DROP PROCEDURE dbo.sp_GetInventoryByBarcodeForStockOut;
END
ELSE IF OBJECT_ID('dbo.sp_GetInventoryByBarcodeForStockOut', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.sp_GetInventoryByBarcodeForStockOut', 'sp_GetInventoryByBarcodeForStockOut_OLD_08252026090000';
END
GO

CREATE PROCEDURE dbo.sp_GetInventoryByBarcodeForStockOut
    @Barcode    VARCHAR(100),
    @BranchCode VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (1)
        i.SequenceNumber,
        i.Barcode,
        i.Product AS ProductCode,
        i.Description,
        i.Available,
        i.Cost
    FROM dbo.Inventory AS i WITH (NOLOCK)
    WHERE i.Barcode = @Barcode
      AND i.Branch = @BranchCode
      AND i.IsStock = 1
      AND i.Available > 0
    ORDER BY i.SequenceNumber ASC;
END
GO

-- =============================================================================
-- Author: Eulz Avancena (original); added 2026-08-25
-- Description: Auto-FIFO lot breakdown -- walks a product's lots oldest
--              (SequenceNumber ASC) first, netting out @AlreadyStaged per
--              lot, until @RequestedQty is satisfied. Same shape as
--              sp_GetInventoryFIFOBreakdown.
-- =============================================================================
IF OBJECT_ID('dbo.sp_GetStockOutFIFOBreakdown_OLD_08252026090000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.sp_GetStockOutFIFOBreakdown', 'P') IS NOT NULL
        DROP PROCEDURE dbo.sp_GetStockOutFIFOBreakdown;
END
ELSE IF OBJECT_ID('dbo.sp_GetStockOutFIFOBreakdown', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.sp_GetStockOutFIFOBreakdown', 'sp_GetStockOutFIFOBreakdown_OLD_08252026090000';
END
GO

CREATE PROCEDURE dbo.sp_GetStockOutFIFOBreakdown
    @ProductCode   VARCHAR(50),
    @BranchCode    VARCHAR(50),
    @RequestedQty  DECIMAL(18,3),
    @AlreadyStaged dbo.tt_StockOutStagedLots READONLY
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF @RequestedQty IS NULL OR @RequestedQty <= 0
            THROW 59601, 'Requested quantity must be greater than zero.', 1;

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

        DECLARE fifo_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT SequenceNumber, Barcode, Description, Available, Cost FROM @Lots ORDER BY SequenceNumber ASC;

        OPEN fifo_cur;
        FETCH NEXT FROM fifo_cur INTO @seq, @barcode, @desc, @avail, @cost;

        WHILE @@FETCH_STATUS = 0 AND @Remaining > 0
        BEGIN
            SET @take = CASE WHEN @avail >= @Remaining THEN @Remaining ELSE @avail END;

            INSERT INTO @Result (SequenceNumber, Barcode, ProductCode, Description, Qty, Cost)
            VALUES (@seq, @barcode, @ProductCode, @desc, @take, @cost);

            SET @Remaining -= @take;

            FETCH NEXT FROM fifo_cur INTO @seq, @barcode, @desc, @avail, @cost;
        END

        CLOSE fifo_cur;
        DEALLOCATE fifo_cur;

        SELECT SequenceNumber, Barcode, ProductCode, Description, Qty, Cost
        FROM @Result
        ORDER BY ResultSeq ASC;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'fifo_cur') >= 0
            CLOSE fifo_cur;
        IF CURSOR_STATUS('local', 'fifo_cur') = -1
            DEALLOCATE fifo_cur;
        THROW;
    END CATCH
END
GO

-- =============================================================================
-- Author: Eulz Avancena (original); added 2026-08-25
-- Description: FIFO lot breakdown scoped to ONE batch (Product+ShipmentNo+
--              ReferenceCode) for StockOut's Manual FIFO Type -- does NOT
--              fall through to other batches of the same product if this
--              one is short. Same shape as
--              sp_GetDispatchFIFOBreakdownByShipment/
--              sp_GetInventoryFIFOBreakdownByShipment.
-- =============================================================================
IF OBJECT_ID('dbo.sp_GetStockOutFIFOBreakdownByShipment_OLD_08252026090000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.sp_GetStockOutFIFOBreakdownByShipment', 'P') IS NOT NULL
        DROP PROCEDURE dbo.sp_GetStockOutFIFOBreakdownByShipment;
END
ELSE IF OBJECT_ID('dbo.sp_GetStockOutFIFOBreakdownByShipment', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.sp_GetStockOutFIFOBreakdownByShipment', 'sp_GetStockOutFIFOBreakdownByShipment_OLD_08252026090000';
END
GO

CREATE PROCEDURE dbo.sp_GetStockOutFIFOBreakdownByShipment
    @ProductCode   VARCHAR(50),
    @BranchCode    VARCHAR(50),
    @ShipmentNo    VARCHAR(10),
    @ReferenceCode VARCHAR(50),
    @RequestedQty  DECIMAL(18,3),
    @AlreadyStaged dbo.tt_StockOutStagedLots READONLY
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF @RequestedQty IS NULL OR @RequestedQty <= 0
            THROW 59602, 'Requested quantity must be greater than zero.', 1;

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

        DECLARE fifoshp_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT SequenceNumber, Barcode, Description, Available, Cost FROM @Lots ORDER BY SequenceNumber ASC;

        OPEN fifoshp_cur;
        FETCH NEXT FROM fifoshp_cur INTO @seq, @barcode, @desc, @avail, @cost;

        WHILE @@FETCH_STATUS = 0 AND @Remaining > 0
        BEGIN
            SET @take = CASE WHEN @avail >= @Remaining THEN @Remaining ELSE @avail END;

            INSERT INTO @Result (SequenceNumber, Barcode, ProductCode, Description, Qty, Cost)
            VALUES (@seq, @barcode, @ProductCode, @desc, @take, @cost);

            SET @Remaining -= @take;

            FETCH NEXT FROM fifoshp_cur INTO @seq, @barcode, @desc, @avail, @cost;
        END

        CLOSE fifoshp_cur;
        DEALLOCATE fifoshp_cur;

        SELECT SequenceNumber, Barcode, ProductCode, Description, Qty, Cost
        FROM @Result
        ORDER BY ResultSeq ASC;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'fifoshp_cur') >= 0
            CLOSE fifoshp_cur;
        IF CURSOR_STATUS('local', 'fifoshp_cur') = -1
            DEALLOCATE fifoshp_cur;
        THROW;
    END CATCH
END
GO

-- =============================================================================
-- Author: Eulz Avancena (original); added 2026-08-25
-- Description: Posts a StockOut Per Barcode batch -- validates, race-safe
--              UPDLOCK deduction of Inventory.Available (mirrors
--              spu_PostConversionBarcode's source-deduction step exactly),
--              IsStock=0 cleanup for exhausted lots, then writes the header
--              + detail rows. Deliberately does NOT create any destination
--              Inventory row and does NOT post a GL ticket -- a stock-out is
--              a pure write-off (matches the legacy sp_FiFoMappingStockOut's
--              scope, not spu_PostSTSDispatch's).
-- =============================================================================
IF OBJECT_ID('dbo.spu_PostStockOutBarcode_OLD_08252026090000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.spu_PostStockOutBarcode', 'P') IS NOT NULL
        DROP PROCEDURE dbo.spu_PostStockOutBarcode;
END
ELSE IF OBJECT_ID('dbo.spu_PostStockOutBarcode', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.spu_PostStockOutBarcode', 'spu_PostStockOutBarcode_OLD_08252026090000';
END
GO

CREATE PROCEDURE dbo.spu_PostStockOutBarcode
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
            WHERE i.Branch <> @BranchCode OR i.Available < l.Qty OR i.IsStock = 0
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
        WHERE i.Branch = @BranchCode AND i.IsStock = 1 AND i.Available >= l.Qty;

        IF @@ROWCOUNT <> @LineCount
            THROW 59504, 'One of the scanned items no longer has enough available stock (it may have changed concurrently). Please rescan.', 1;

        UPDATE dbo.Inventory
        SET IsStock = 0
        WHERE SequenceNumber IN (SELECT InventorySeqNo FROM @Lines)
          AND Available <= 0;

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
GO

-- =============================================================================
-- Author: Eulz Avancena (original); added 2026-08-25
-- Description: Reverses a POSTED StockOut Per Barcode batch -- restores
--              Available/IsStock on every original lot. No "already moved"
--              check is needed here (unlike spu_ReverseConversionBarcode's
--              OUTPUT-side check) because a stock-out creates no new
--              Inventory lot that could have been subsequently moved --
--              only the original source lots exist, restored in place.
--
--              The Status='POSTED'-to-'REVERSED' transition IS the
--              concurrency guard (done FIRST, inside the transaction, via
--              UPDATE ... WHERE Status='POSTED' + @@ROWCOUNT), not a plain
--              SELECT check before BEGIN TRANSACTION -- two concurrent
--              reverse calls for the same @RefNo (double-click, a UI retry,
--              two operators) would otherwise both pass an unlocked
--              "IF NOT EXISTS ... Status='POSTED'" check while both rows are
--              still POSTED, and both then credit Inventory.Available,
--              double-crediting it. The Post side already has an equivalent
--              guard for free via the RefNo PRIMARY KEY rejecting a second
--              INSERT; Reverse needs this explicit UPDATE-as-guard because
--              it has no analogous natural uniqueness check.
-- =============================================================================
IF OBJECT_ID('dbo.spu_ReverseStockOutBarcode_OLD_08252026090000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.spu_ReverseStockOutBarcode', 'P') IS NOT NULL
        DROP PROCEDURE dbo.spu_ReverseStockOutBarcode;
END
ELSE IF OBJECT_ID('dbo.spu_ReverseStockOutBarcode', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.spu_ReverseStockOutBarcode', 'spu_ReverseStockOutBarcode_OLD_08252026090000';
END
GO

CREATE PROCEDURE dbo.spu_ReverseStockOutBarcode
    @RefNo      VARCHAR(20),
    @ReversedBy VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.StockOutBarcodeSummary WHERE RefNo = @RefNo)
            THROW 59505, 'This Stock-Out was not found.', 1;

        DECLARE @ExpectedLines INT = (SELECT COUNT(*) FROM dbo.StockOutBarcodeDetails WHERE RefNo = @RefNo);

        BEGIN TRANSACTION;

        -- Atomic guard: only ever transitions ONE caller's row from POSTED to
        -- REVERSED. A concurrent second call sees @@ROWCOUNT=0 and fails
        -- cleanly instead of both callers proceeding to double-credit stock.
        UPDATE dbo.StockOutBarcodeSummary WITH (ROWLOCK)
        SET Status = 'REVERSED',
            ReversedBy = @ReversedBy,
            DateReversed = GETDATE()
        WHERE RefNo = @RefNo AND Status = 'POSTED';

        IF @@ROWCOUNT = 0
            THROW 59507, 'This Stock-Out is not in POSTED status (already reversed, or reversed concurrently by another session).', 1;

        UPDATE i
        SET i.Available = i.Available + d.Qty,
            i.IsStock = 1
        FROM dbo.Inventory AS i
        INNER JOIN dbo.StockOutBarcodeDetails AS d ON d.InventorySeqNo = i.SequenceNumber
        WHERE d.RefNo = @RefNo;

        -- If a lot no longer exists (e.g. hard-deleted elsewhere in the
        -- app), the join above silently matches nothing for it and the
        -- reversal would otherwise "succeed" while permanently losing that
        -- quantity. Catch the mismatch instead of failing silently.
        IF @@ROWCOUNT <> @ExpectedLines
            THROW 59506, 'Cannot reverse -- one or more original inventory lots no longer exist.', 1;

        COMMIT TRANSACTION;

        SELECT 1 AS [Status], 'Stock-out reversed.' AS [Message];
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- =============================================================================
-- Author: Eulz Avancena (original); added 2026-08-25
-- Description: Posted-tab summary view for StockOutPerBarcode.cs.
-- =============================================================================
IF OBJECT_ID('dbo.vw_StockOutBarcodeSummary_OLD_08252026090000', 'V') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.vw_StockOutBarcodeSummary', 'V') IS NOT NULL
        DROP VIEW dbo.vw_StockOutBarcodeSummary;
END
ELSE IF OBJECT_ID('dbo.vw_StockOutBarcodeSummary', 'V') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.vw_StockOutBarcodeSummary', 'vw_StockOutBarcodeSummary_OLD_08252026090000';
END
GO

CREATE VIEW dbo.vw_StockOutBarcodeSummary
AS
SELECT
    RefNo,
    BranchCode,
    Category,
    Remarks,
    TotalQty,
    TotalCost,
    Status,
    DateAdded,
    PreparedBy,
    ReversedBy,
    DateReversed
FROM dbo.StockOutBarcodeSummary;
GO

PRINT 'DEPLOYMENT COMPLETE: StockOutBarcodeSummary/Details, tt_StockOutStagedLots/BarcodeLines, sp_GetStockOutBarcodeNumber, sp_GetInventoryForStockOutDropdown/ManualDropdown, sp_GetInventoryByBarcodeForStockOut, sp_GetStockOutFIFOBreakdown/ByShipment, spu_PostStockOutBarcode, spu_ReverseStockOutBarcode, vw_StockOutBarcodeSummary.';
