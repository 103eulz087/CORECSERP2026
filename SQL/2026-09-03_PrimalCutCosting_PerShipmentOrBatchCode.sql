-- =============================================
-- Author: Eulz Avancena (original); modified 2026-09-03
-- Description: Adds a second costing method to PrimalCutCosting.cs.
--              Today, cost is set per (Product, ShipmentNo) -- one cost
--              applies to every isWarehouse=0 holding lot of that product
--              in that shipment, regardless of which physical batch it came
--              from (Inventory.BatchCode, correctly populated per real
--              batch by sp_CommitPrimalCutConversion, but never consulted
--              by this costing screen). The user wants a second method:
--              cost a specific (ShipmentNo, BatchCode) combination
--              independently, so one batch within a shipment can be priced
--              differently from the rest of that same shipment.
--
--              Design (confirmed with user 2026-09-03): BatchCode=0 is the
--              "Per Shipment" sentinel and acts as a WILDCARD across all
--              batches -- i.e. today's exact behavior, completely
--              unchanged, is what BatchCode=0 means. A nonzero BatchCode
--              scopes strictly to that one batch's isWarehouse=0 lots only.
--              0 (not NULL) is used deliberately: SQL Server unique indexes
--              treat multiple NULLs as non-duplicates, which would silently
--              defeat a (ShipmentNo, ItemCode, BatchCode) uniqueness
--              constraint for the Per Shipment case.
--
--              TempCosting is confirmed EMPTY in this database as of this
--              change -- zero migration risk, the unique index can be
--              dropped and recreated directly with no backfill needed.
-- =============================================

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-------------------------------------------------------------------
-- 1. Schema: BatchCode on TempCosting, replace the (ShipmentNo, ItemCode)
--    unique index with (ShipmentNo, ItemCode, BatchCode).
-------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TempCosting') AND name = 'BatchCode')
    ALTER TABLE dbo.TempCosting ADD BatchCode INT NOT NULL CONSTRAINT DF_TempCosting_BatchCode DEFAULT (0);
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TempCosting') AND name = 'UX_TempCosting_Shipment_Item')
    DROP INDEX UX_TempCosting_Shipment_Item ON dbo.TempCosting;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TempCosting') AND name = 'UX_TempCosting_Shipment_Item_Batch')
    CREATE UNIQUE INDEX UX_TempCosting_Shipment_Item_Batch ON dbo.TempCosting(ShipmentNo, ItemCode, BatchCode);
GO

-------------------------------------------------------------------
-- 2. New lookup SP for the UI's Batch Code dropdown -- only offers batch
--    codes that actually have isWarehouse=0 (un-costed/holding) stock for
--    the selected shipment, so a typo/nonexistent batch can't be entered.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.sp_GetBatchCodesForShipment', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetBatchCodesForShipment;
GO

CREATE PROCEDURE dbo.sp_GetBatchCodesForShipment
    @ShipmentNo VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT BatchCode
    FROM dbo.Inventory WITH (NOLOCK)
    WHERE ShipmentNo = @ShipmentNo
      AND isWarehouse = 0
      AND BatchCode IS NOT NULL
      AND BatchCode <> 0
    ORDER BY BatchCode;
END
GO

-------------------------------------------------------------------
-- 3. spu_UpdatePrimalCutCosting: add @BatchCode (default 0 = Per Shipment,
--    preserves the exact old behavior/signature-compatible call shape for
--    that mode). All TempCosting/Inventory scoping now BatchCode-aware.
-------------------------------------------------------------------
-- SP Backup Renaming: preserve the pre-BatchCode version under a timestamped name
-- before dropping/recreating, per CLAUDE.md convention. Re-running this script the
-- same day (expected during testing/iteration) must not fail on a duplicate backup
-- name, so only the FIRST run captures a backup; later re-runs just drop-and-recreate.
IF OBJECT_ID('dbo.spu_UpdatePrimalCutCosting', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.spu_UpdatePrimalCutCosting_bak_20260903', 'P') IS NULL
        EXEC sp_rename 'dbo.spu_UpdatePrimalCutCosting', 'spu_UpdatePrimalCutCosting_bak_20260903';
    ELSE
        DROP PROCEDURE dbo.spu_UpdatePrimalCutCosting;
END
GO

CREATE PROCEDURE [dbo].[spu_UpdatePrimalCutCosting]
    @ShipmentNo  VARCHAR(10),
    @Branch      VARCHAR(5),
    @PreparedBy  VARCHAR(50),
    @Lines       dbo.tt_PrimalCutCostingLines READONLY,
    @BatchCode   INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @Item TABLE (
            RowID       INT IDENTITY(1,1),
            ProductCode VARCHAR(10),
            Description VARCHAR(100),
            Cost        DECIMAL(18,2)
        );
        INSERT INTO @Item (ProductCode, Description, Cost)
        SELECT ProductCode, Description, Cost FROM @Lines;

        IF NOT EXISTS (SELECT 1 FROM @Item)
            THROW 58201, 'No costing lines were supplied.', 1;

        IF @BatchCode IS NULL OR @BatchCode < 0
            THROW 58202, 'BatchCode must be 0 (Per Shipment) or a positive batch code.', 1;

        DECLARE @Results TABLE (
            ProductCode  VARCHAR(10),
            Description  VARCHAR(100),
            NewCost      DECIMAL(18,2),
            Transferred  BIT,
            AffectedRows INT,
            Reason       VARCHAR(200)
        );

        DECLARE @row INT = 1, @maxrow INT = (SELECT COUNT(*) FROM @Item);
        DECLARE @transferredCount INT = 0, @heldCount INT = 0;

        WHILE @row <= @maxrow
        BEGIN
            DECLARE @productcode VARCHAR(10), @description VARCHAR(100), @cost DECIMAL(18,2),
                    @prevcost DECIMAL(18,2), @affectedrows INT, @transferred BIT, @reason VARCHAR(200),
                    @remainingCount INT, @totalCount INT;

            SELECT @productcode = ProductCode, @description = Description, @cost = Cost
            FROM @Item WHERE RowID = @row;

            -- Previous cost for THIS costing method's own row -- Per Shipment
            -- (BatchCode=0) and a specific batch are separate TempCosting
            -- rows by design, so this correctly never confuses the two.
            SELECT @prevcost = CostPerKg FROM dbo.TempCosting
            WHERE ShipmentNo = @ShipmentNo AND ItemCode = @productcode AND BatchCode = @BatchCode;

            SET @affectedrows = 0;

            -- Scope totals for this product under the requested BatchCode (wildcard match on
            -- 0, exact match otherwise). @remainingCount = holding lots still isWarehouse=0
            -- (eligible to cost/transfer); @totalCount = every matching lot regardless of
            -- isWarehouse. Distinguishing these three states fixes a real reviewer-caught bug:
            -- the old single EXISTS(isWarehouse=1) wildcard check reported an ENTIRE product as
            -- "already transferred" the moment any ONE of its batches had been transferred via
            -- a separate Combination-mode call, silently skipping the cost/transfer of that
            -- product's still-held OTHER batches under a later Per Shipment (wildcard) call.
            SELECT @remainingCount = SUM(CASE WHEN isWarehouse = 0 THEN 1 ELSE 0 END),
                   @totalCount = COUNT(*)
            FROM dbo.Inventory
            WHERE Product = @productcode AND ShipmentNo = @ShipmentNo AND Branch = @Branch
              AND (@BatchCode = 0 OR BatchCode = @BatchCode);

            SET @remainingCount = ISNULL(@remainingCount, 0);
            SET @totalCount = ISNULL(@totalCount, 0);

            IF @totalCount > 0 AND @remainingCount = 0
            BEGIN
                -- Every matching lot is already isWarehouse=1 -- genuinely already
                -- transferred. Still record the submitted cost for reference (matches
                -- the pre-existing TempCosting write, just no Inventory side effect).
                IF EXISTS (SELECT 1 FROM dbo.TempCosting WHERE ShipmentNo = @ShipmentNo AND ItemCode = @productcode AND BatchCode = @BatchCode)
                    UPDATE dbo.TempCosting SET CostPerKg = @cost
                    WHERE ShipmentNo = @ShipmentNo AND ItemCode = @productcode AND BatchCode = @BatchCode;
                ELSE
                    INSERT INTO dbo.TempCosting (ShipmentNo, ItemCode, Parts, CostPerKg, BatchCode)
                    VALUES (@ShipmentNo, @productcode, @description, @cost, @BatchCode);

                SET @transferred = 1;
                SET @reason = 'Already transferred to Commissary -- no changes applied';
                SET @transferredCount += 1;
            END
            ELSE IF @cost < 0
            BEGIN
                SET @transferred = 0;
                SET @reason = 'Rejected -- cost cannot be negative';
                SET @heldCount += 1;
            END
            ELSE
            BEGIN
                IF EXISTS (SELECT 1 FROM dbo.TempCosting WHERE ShipmentNo = @ShipmentNo AND ItemCode = @productcode AND BatchCode = @BatchCode)
                    UPDATE dbo.TempCosting SET CostPerKg = @cost
                    WHERE ShipmentNo = @ShipmentNo AND ItemCode = @productcode AND BatchCode = @BatchCode;
                ELSE
                    INSERT INTO dbo.TempCosting (ShipmentNo, ItemCode, Parts, CostPerKg, BatchCode)
                    VALUES (@ShipmentNo, @productcode, @description, @cost, @BatchCode);

                IF @totalCount = 0
                BEGIN
                    -- No Inventory lots exist yet for this product under this BatchCode
                    -- (e.g. costed ahead of physical intake, or a typo'd/unused batch) --
                    -- cost is recorded above for when intake picks it up, but there is
                    -- nothing to transfer right now. Previously this branch was
                    -- unreachable and fell through to "Transferred to Commissary" purely
                    -- because @cost > 0, misreporting success with @affectedrows=0.
                    SET @transferred = 0;
                    SET @reason = 'Cost recorded -- no matching holding stock yet for this product' + CASE WHEN @BatchCode <> 0 THEN '/batch' ELSE '' END + ' in this shipment';
                    SET @heldCount += 1;
                END
                ELSE IF @cost > 0
                BEGIN
                    -- Cost update: Per Shipment (BatchCode=0) touches every
                    -- batch's holding lots for this product; a specific
                    -- BatchCode touches only that batch's lots.
                    UPDATE dbo.Inventory
                    SET Cost = @cost
                    WHERE Product = @productcode AND ShipmentNo = @ShipmentNo AND Branch = @Branch AND isWarehouse = 0
                      AND (@BatchCode = 0 OR BatchCode = @BatchCode);

                    SET @affectedrows = @@ROWCOUNT;

                    UPDATE dbo.Inventory
                    SET isWarehouse = 1
                    WHERE Product = @productcode AND ShipmentNo = @ShipmentNo AND Branch = @Branch AND isWarehouse = 0
                      AND (@BatchCode = 0 OR BatchCode = @BatchCode);

                    SET @transferred = 1;
                    SET @reason = 'Transferred to Commissary';
                    SET @transferredCount += 1;
                END
                ELSE
                BEGIN
                    SET @transferred = 0;
                    SET @reason = 'Held in BigBlue -- cost not yet set (0)';
                    SET @heldCount += 1;
                END
            END

            INSERT INTO dbo.PrimalCutCostingAuditLog
                (ShipmentNo, ItemCode, Description, PreviousCost, NewCost, TransferredToCommissary, AffectedInventoryRows, Reason, PerformedBy, BranchCode)
            VALUES
                (@ShipmentNo, @productcode, @description, @prevcost, @cost, @transferred, @affectedrows, @reason, @PreparedBy, @Branch);

            INSERT INTO @Results (ProductCode, Description, NewCost, Transferred, AffectedRows, Reason)
            VALUES (@productcode, @description, @cost, @transferred, @affectedrows, @reason);

            SET @row += 1;
        END;

        INSERT INTO dbo.HistoryLogs (UserID, DateExecute, ActionLogs, BranchCode)
        VALUES (
            @PreparedBy, GETDATE(),
            'Primal Cut Costing updated for ShipmentNo=' + @ShipmentNo +
                CASE WHEN @BatchCode <> 0 THEN ' BatchCode=' + CAST(@BatchCode AS VARCHAR) ELSE ' (Per Shipment)' END + ': ' +
                CAST(@transferredCount AS VARCHAR) + ' item(s) transferred to Commissary, ' +
                CAST(@heldCount AS VARCHAR) + ' item(s) held in BigBlue (zero cost)',
            @Branch
        );

        COMMIT TRAN;

        SELECT ProductCode, Description, NewCost, Transferred, AffectedRows, Reason FROM @Results;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

PRINT 'DEPLOYMENT COMPLETE: TempCosting.BatchCode, UX_TempCosting_Shipment_Item_Batch, sp_GetBatchCodesForShipment, spu_UpdatePrimalCutCosting (+@BatchCode, wildcard-on-0).';
