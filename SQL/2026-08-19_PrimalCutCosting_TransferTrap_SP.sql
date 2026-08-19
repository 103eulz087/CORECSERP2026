SET NOCOUNT ON;
PRINT '=== PrimalCutCosting: zero-cost transfer trap, per-line upsert fix, spu_UpdatePrimalCutCosting, structured audit log ===';
GO

-- =============================================
-- CONTEXT: Orders/PrimalCutCosting.cs -- after primal-cut conversion, child
-- items sit in Inventory with isWarehouse=0 ("BigBlue" holding). The
-- inventory manager sets a per-item Cost here before the items are supposed
-- to move to isWarehouse=1 ("Commissary"). The OLD C# btnsave_Click had two
-- problems:
--   1. No transfer step existed at all -- isWarehouse was never flipped
--      anywhere in this file, so nothing actually moved to Commissary.
--   2. The upsert check ran ONCE for the whole grid ("does ANY TempCosting
--      row exist for this shipment?") and branched the ENTIRE grid into
--      either all-UPDATE or all-INSERT. A shipment with some items already
--      costed from a prior save, plus new items added since, would silently
--      skip the new ones (all-UPDATE branch matches nothing for them) or
--      PK-violate on the existing ones (all-INSERT branch). Needs a real
--      per-line upsert.
--
-- FIX: spu_UpdatePrimalCutCosting does a per-line MERGE-style upsert into
-- TempCosting, updates Inventory.Cost for the converted (isWarehouse=0)
-- items, and adds the missing trap: isWarehouse only flips to 1 (transfer
-- to Commissary) for lines where the newly-set Cost is > 0. Zero-cost lines
-- stay at isWarehouse=0, untransferred.
--
-- Mother/source product safety: ProductCode here is always drawn from
-- view_PrimalCutPartsForCosting's fixed list of ~50 specific primal-cut
-- part codes (confirmed via that view's own definition) -- the mother/
-- source whole-product's own code structurally never appears in that list,
-- so the existing (Product=ItemCode AND ShipmentNo AND Branch AND
-- isWarehouse=0) scoping already can't touch it. Preserved exactly; do not
-- loosen this scoping without re-verifying that invariant still holds.
--
-- AUDIT TRAIL: HistoryLogs (dbo.HistoryLogs) is this codebase's existing
-- generic audit log, but it's a single free-text ActionLogs varchar(500)
-- column -- fine for "something happened" visibility across modules, no
-- good for per-item detail (no before/after cost, no transfer outcome).
-- Still writes one summary line there for consistency with how every other
-- module already logs (e.g. sp_ConfirmBranchOrderSTS's "Commissary Process
-- Order..." line). PrimalCutCostingAuditLog is new and purpose-built:
-- per-line PreviousCost/NewCost/TransferredToCommissary/Reason, so an actual
-- audit question ("why didn't item X transfer on shipment Y") is answerable
-- without parsing free text.
--
-- REVIEW FIXES (same-day, before this SP was ever used against real data --
-- edited in place rather than stacking a backup, per this project's own
-- "second same-day draft fix" convention):
--   1. A line already at isWarehouse=1 (transferred by an earlier call) is
--      now detected up front and skipped entirely -- TempCosting is no
--      longer overwritten for it (was going out of sync with Inventory,
--      since the Inventory.Cost UPDATE below was already correctly a no-op
--      for isWarehouse=1 rows but TempCosting was not), and the reported
--      Reason now correctly says "already transferred" instead of the
--      previous, factually wrong "held -- cost not yet set (0)" whenever
--      someone resubmitted a 0 for an already-transferred item.
--   2. Negative Cost is now rejected per-line (skipped, not written to
--      Inventory.Cost) instead of silently corrupting costing data -- the
--      old version only gated the *transfer* on Cost>0, not the cost write
--      itself, so a negative value would still land in Inventory.Cost.
--   3. Added a unique index on TempCosting(ShipmentNo, ItemCode) -- that
--      table had no PK/unique constraint at all, so the per-line
--      IF EXISTS...UPDATE ELSE INSERT upsert (the fix for the original
--      whole-grid-branch bug) was correct for sequential calls but not
--      race-safe under concurrent saves for the same shipment. Confirmed
--      no existing duplicate (ShipmentNo, ItemCode) rows before adding.
-- =============================================

-- Table types can't be ALTERed, and SQL Server won't DROP TYPE while any object
-- (including this same script's own SP from a prior run) references it -- so the
-- SP has to go first, same lesson as SQL/2026-08-18_TransferItemType_AddSeqNo.sql.
IF OBJECT_ID('dbo.spu_UpdatePrimalCutCosting', 'P') IS NOT NULL
    DROP PROCEDURE dbo.spu_UpdatePrimalCutCosting;
GO

IF TYPE_ID('dbo.tt_PrimalCutCostingLines') IS NOT NULL
    DROP TYPE dbo.tt_PrimalCutCostingLines;
GO

CREATE TYPE dbo.tt_PrimalCutCostingLines AS TABLE (
    ProductCode VARCHAR(10)   NOT NULL,
    Description VARCHAR(100)  NULL,
    Cost        DECIMAL(18,2) NOT NULL
);
GO

IF OBJECT_ID('dbo.PrimalCutCostingAuditLog', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PrimalCutCostingAuditLog (
        AuditID                 INT IDENTITY(1,1) PRIMARY KEY,
        ShipmentNo              VARCHAR(10)   NOT NULL,
        ItemCode                VARCHAR(10)   NOT NULL,
        Description             VARCHAR(100)  NULL,
        PreviousCost            DECIMAL(18,2) NULL,
        NewCost                 DECIMAL(18,2) NOT NULL,
        TransferredToCommissary BIT           NOT NULL,
        AffectedInventoryRows   INT           NOT NULL,
        Reason                  VARCHAR(200)  NULL,
        PerformedBy             VARCHAR(50)   NOT NULL,
        BranchCode              VARCHAR(5)    NULL,
        DateExecuted            DATETIME      NOT NULL CONSTRAINT DF_PrimalCutCostingAuditLog_DateExecuted DEFAULT (GETDATE())
    );
    CREATE INDEX IX_PrimalCutCostingAuditLog_Shipment ON dbo.PrimalCutCostingAuditLog(ShipmentNo, ItemCode);
END
GO

-- TempCosting had no PK/unique constraint at all -- makes the per-line upsert
-- below correct for sequential calls but not race-safe under concurrent saves
-- for the same shipment. No existing duplicate (ShipmentNo, ItemCode) rows as
-- of this fix (confirmed, table was empty), so safe to add.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TempCosting') AND name = 'UX_TempCosting_Shipment_Item')
    CREATE UNIQUE INDEX UX_TempCosting_Shipment_Item ON dbo.TempCosting(ShipmentNo, ItemCode);
GO

-- dbo.Inventory has filtered indexes (IX_Inventory_ActiveStock_ByBranch,
-- IX_Inventory_FIFO_Engine, both WHERE Available>0) -- SQL Server requires
-- QUOTED_IDENTIFIER ON for any INSERT/UPDATE/DELETE against a table with a
-- filtered index, and that setting is baked into a procedure at CREATE time,
-- not read from the caller's session. Matches sp_FiFoMappingSTS/
-- sp_AddBranchOrder, the other SPs that write to Inventory (both ON).
SET QUOTED_IDENTIFIER ON;
GO

CREATE PROCEDURE [dbo].[spu_UpdatePrimalCutCosting]
    @ShipmentNo  VARCHAR(10),
    @Branch      VARCHAR(5),
    @PreparedBy  VARCHAR(50),
    @Lines       dbo.tt_PrimalCutCostingLines READONLY
AS
BEGIN
    SET NOCOUNT ON;

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
                    @prevcost DECIMAL(18,2), @affectedrows INT, @transferred BIT, @reason VARCHAR(200);

            SELECT @productcode = ProductCode, @description = Description, @cost = Cost
            FROM @Item WHERE RowID = @row;

            -- Previous cost, for the audit trail -- the last value entered via this screen.
            SELECT @prevcost = CostPerKg FROM dbo.TempCosting WHERE ShipmentNo = @ShipmentNo AND ItemCode = @productcode;

            SET @affectedrows = 0;

            IF EXISTS (
                SELECT 1 FROM dbo.Inventory
                WHERE Product = @productcode AND ShipmentNo = @ShipmentNo AND Branch = @Branch AND isWarehouse = 1
            )
            BEGIN
                -- Already transferred by an earlier call. Leave TempCosting/Inventory alone --
                -- overwriting TempCosting here (the old behavior) went out of sync with
                -- Inventory, since the Cost UPDATE below was already correctly a no-op for
                -- isWarehouse=1 rows. Report the true status instead of re-deriving it from
                -- @cost, which would wrongly say "held -- cost not yet set" if @cost=0 here.
                SET @transferred = 1;
                SET @reason = 'Already transferred to Commissary -- no changes applied';
                SET @transferredCount += 1;
            END
            ELSE IF @cost < 0
            BEGIN
                -- Reject, don't write. The old version only gated the *transfer* on Cost>0,
                -- not the cost write itself, so a negative value would still land in
                -- Inventory.Cost, corrupting costing data with no rejection.
                SET @transferred = 0;
                SET @reason = 'Rejected -- cost cannot be negative';
                SET @heldCount += 1;
            END
            ELSE
            BEGIN
                -- Per-line upsert -- see header comment on why this replaced the old
                -- whole-grid-branch check.
                IF EXISTS (SELECT 1 FROM dbo.TempCosting WHERE ShipmentNo = @ShipmentNo AND ItemCode = @productcode)
                    UPDATE dbo.TempCosting SET CostPerKg = @cost
                    WHERE ShipmentNo = @ShipmentNo AND ItemCode = @productcode;
                ELSE
                    INSERT INTO dbo.TempCosting (ShipmentNo, ItemCode, Parts, CostPerKg)
                    VALUES (@ShipmentNo, @productcode, @description, @cost);

                -- Cost update, scoped to converted (isWarehouse=0) items only -- see header
                -- comment on why this can never touch the mother/source product.
                UPDATE dbo.Inventory
                SET Cost = @cost
                WHERE Product = @productcode AND ShipmentNo = @ShipmentNo AND Branch = @Branch AND isWarehouse = 0;

                SET @affectedrows = @@ROWCOUNT;

                -- THE TRAP: only transfer to Commissary (isWarehouse 0 -> 1) once a real cost is set.
                IF @cost > 0
                BEGIN
                    UPDATE dbo.Inventory
                    SET isWarehouse = 1
                    WHERE Product = @productcode AND ShipmentNo = @ShipmentNo AND Branch = @Branch AND isWarehouse = 0;

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
            'Primal Cut Costing updated for ShipmentNo=' + @ShipmentNo + ': ' +
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

PRINT 'DEPLOYMENT COMPLETE: tt_PrimalCutCostingLines, PrimalCutCostingAuditLog, spu_UpdatePrimalCutCosting created.';
