/* ================================================================
   2026-10-10b: Inventory cost fix, lots 1109 / 1110 (data only)
   ================================================================
   Found on STAGING (restore of PRODUCTION 2026-10-08); the lots are production's.

   Lots (branch 003, Re-Inventory IN, ShipmentNo ' '):
     1109  13475 PORK LEG BONELESS SKINLESS  INVIN-130  29.12 kg, 0.05 left   Cost 54,922,604.87
     1110  13050 PORK MASKS                  INVIN-132  80.00 kg, 0.00 left   Cost 54,922,484.50
   Both were sold on 2026-09-11 (POs 6619 / 7153) at 229.87 / 109.50: those are the
   costs in InventoryDeliveryFIFO, InventoryLedger and the sales GL. Later each lot's
   cost grew by exactly 54,922,375.00 = 2,746,118.75 / 0.05, i.e. expense 17959
   (SI-202630161, ticket 7339, inventory leg 2,746,118.75) spread a second time over the
   two lots' remaining stock (0.05 + 0.00 kg). The expense was costed correctly to its
   shipment 10955 (lot 1112: 130.32 = the four linked expenses' inventory legs / 27,250 kg),
   so this second application is wrong. No procedure in the database divides by
   remaining stock; the statement that did it isn't on record (Query Store is off).

   Effect today: nothing has moved from either lot since 09-11, so no GL entry used the
   bad cost. Lot 1109's 0.05 kg is valued at 2,746,130.24; selling, transferring or
   adjusting it would post that as cost. Stock valuation reports are overstated by
   2,746,118.75 until this runs.

   Fix: each lot back to its cost at the 09-11 sale (Cost - 54,922,375.00 = 229.87 / 109.50).
   Refused (nothing changed) if a lot's cost is no longer as found, or if anything has
   moved from either lot since 09-11 (then a GL correction is needed too).
   Backup: Inventory_CostFix_Backup_20261010.
   ================================================================ */

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('dbo.Inventory_CostFix_Backup_20261010', 'U') IS NOT NULL
    THROW 93601, 'Inventory_CostFix_Backup_20261010 already exists: this script has been run here before.', 1;

DECLARE @Lots TABLE (SequenceNumber INT PRIMARY KEY, Product VARCHAR(20), BadCost DECIMAL(18,2), GoodCost DECIMAL(18,2));
INSERT INTO @Lots VALUES
    (1109, '13475', 54922604.87, 229.87),
    (1110, '13050', 54922484.50, 109.50);

BEGIN TRANSACTION;

    IF (SELECT COUNT(*) FROM dbo.Inventory AS i WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN @Lots AS l ON l.SequenceNumber = i.SequenceNumber
        WHERE i.Product = l.Product AND CAST(i.Cost AS DECIMAL(18,2)) = l.BadCost) <> 2
        THROW 93602, 'Lot 1109 / 1110 is no longer as found (cost or product changed); nothing changed.', 1;

    -- the cost each lot had when it was sold (all movements so far used it)
    IF EXISTS (SELECT 1 FROM dbo.InventoryDeliveryFIFO AS d INNER JOIN @Lots AS l ON l.SequenceNumber = d.SequenceReferenceNumber
               WHERE d.Cost <> l.GoodCost)
        THROW 93603, 'A delivery of lot 1109 / 1110 used another cost than 229.87 / 109.50 (moved since 2026-10-08?); nothing changed. The GL needs checking too.', 1;

    IF (SELECT COUNT(*) FROM dbo.InventoryDeliveryFIFO WHERE SequenceReferenceNumber IN (1109, 1110)) <> 3
       OR (SELECT COUNT(*) FROM dbo.InventoryLedger WHERE SequenceRefNum IN (1109, 1110)) <> 4
       OR EXISTS (SELECT 1 FROM dbo.InventoryBranchTransferFIFO WHERE SequenceReferenceNumber IN (1109, 1110))
       OR EXISTS (SELECT 1 FROM dbo.InventoryAdjustmentFIFO WHERE SequenceReferenceNumber IN (1109, 1110))
       OR EXISTS (SELECT 1 FROM dbo.ConversionBarcodeSourceDetails WHERE InventorySeqNo IN (1109, 1110))
       OR EXISTS (SELECT 1 FROM dbo.StockOutBarcodeDetails WHERE InventorySeqNo IN (1109, 1110))
       OR EXISTS (SELECT 1 FROM dbo.ConversionFIFO WHERE SequenceReferenceNumber IN (1109, 1110))
        THROW 93604, 'Lot 1109 / 1110 has moved since 2026-09-11 (possibly at the wrong cost); nothing changed. Check the GL of that movement first.', 1;

    SELECT i.* INTO dbo.Inventory_CostFix_Backup_20261010
    FROM dbo.Inventory AS i INNER JOIN @Lots AS l ON l.SequenceNumber = i.SequenceNumber;

    UPDATE i SET Cost = l.GoodCost
    FROM dbo.Inventory AS i INNER JOIN @Lots AS l ON l.SequenceNumber = i.SequenceNumber;
    IF @@ROWCOUNT <> 2 THROW 93605, 'The fix did not touch exactly 2 lots.', 1;

    -- post-check: no lot anywhere is left at an absurd cost
    IF EXISTS (SELECT 1 FROM dbo.Inventory WHERE Cost > 100000)
        THROW 93606, 'Post-check: a lot still costs more than 100,000 per unit; nothing changed.', 1;

COMMIT TRANSACTION;

SELECT i.SequenceNumber, i.Branch, i.Product, i.ReferenceCode, i.Quantity, i.Available, b.Cost AS WasCost, i.Cost AS NowCost,
       CAST(i.Available * i.Cost AS DECIMAL(18,2)) AS StockValue
FROM dbo.Inventory AS i
INNER JOIN dbo.Inventory_CostFix_Backup_20261010 AS b ON b.SequenceNumber = i.SequenceNumber
ORDER BY i.SequenceNumber;
