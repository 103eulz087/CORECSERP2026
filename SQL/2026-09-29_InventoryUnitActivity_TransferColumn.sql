/* ================================================================
   2026-09-29: spr_InventoryUnitActivity -- Inventory Transfer column,
   one row per item, date-filtered Sold/Sales, real unit cost
   (Reporting/InventoryUnitActivityReport.cs).
   ================================================================
   PROBLEMS (checked on COREX001):
     1. Transfers: InventoryDeliveryFIFO.BranchCode holds the REQUESTING
        (destination) branch for a transfer, while the stock leaves the
        SOURCE lot's branch (Inventory.Branch) -- all 108 transfer rows.
        So the source branch never showed the transfer-out, and the
        destination branch showed it as Unit Sold (e.g. 888 lot
        506-100-111-CFS17676 -> "Sold 1,050" at 004).
     2. Aggregated grouped by Cost, and every movement row carried Cost 0,
        so each item split into a stock row + a negative "sold" row with
        Unit Cost 0 -> Cost of Goods Sold always 0 (888: 109 negative rows).
     3. Unit Sold / Sales ignored the From/To dates (all-time).

   CHANGES (user-confirmed 2026-09-29):
     - NEW InventoryTransfer (qty out): FIFO rows whose PONumber is in
       TransferOrderSummary, attributed to the SOURCE lot's branch
       (Inventory.Branch). Same Sold/Transfer rule as
       sp_rpt_ItemCostingReport_Detail/_Master (2026-09-28c/d).
     - UnitSold and Sales exclude transfers.
     - UnitSold, Sales, InventoryTransfer filtered by FIFO DateProcessed
       within @datefrom..@dateto (inclusive), like Beginning/Purchased.
     - One row per Branch + ItemCode + ProductCode (no GROUP BY Cost).
     - UnitCost = quantity-weighted average Cost over ALL of the branch's
       Inventory lots for that item (not only lots received in the range),
       so sold/transferred units from older lots get a real cost.
     - QtyOnHand / ItemValue subtract InventoryTransfer; Cost (COGS) =
       UnitSold * UnitCost (sales only).
     - Review fixes (same day): QtyDelivered (float) is CAST to DECIMAL(18,3)
       so qty/value/COGS stay decimal; UnitCost is rounded to 2 dp once in
       ItemCost and that same value drives ItemValue/Cost; blank and NULL
       ReferenceCode are normalised to one item key (no split/double join).
   UNCHANGED: A (Beginning = lots received in the range), B (Unit
   Purchased) and the C.1 "Adjustment" block (still always 0 -- pre-
   existing, see worklog), Products/ProductCategory joins, parameters.
   New column InventoryTransfer sits after UnitSold; caller binds by name.

   Only caller: Reporting/InventoryUnitActivityReport.cs.
   Deploy to COREX001 (DEV) first; CORECSJFC2026_STAGING only after the
   user confirms -- together with the new exe.
   ================================================================ */

IF OBJECT_ID('dbo.spr_InventoryUnitActivity', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spr_InventoryUnitActivity', 'spr_InventoryUnitActivity_OLD_09292026090000';
GO

CREATE PROCEDURE [dbo].[spr_InventoryUnitActivity] --exec spr_InventoryUnitActivity '888','09/01/2026','09/30/2026'
    @parmbrcode CHAR(3),
    @datefrom   DATE,
    @dateto     DATE
AS
BEGIN
    SET NOCOUNT ON;

    WITH UnifiedReport AS (

        -- A. BEGINNING INVENTORY (lots received in the range) -- unchanged
        SELECT
            Branch AS BranchCode,
            ReferenceCode AS ItemCode,
            Product AS ProductCode,
            Quantity AS BeginningQty,
            0 AS UnitPurchased,
            0 AS Adjustment,
            0 AS UnitSold,
            0 AS InventoryTransfer,
            0 AS Sales
        FROM dbo.Inventory WITH (NOLOCK)
        WHERE Branch = @parmbrcode
          AND DateReceived BETWEEN @datefrom AND @dateto

        UNION ALL

        -- B. UNIT PURCHASED -- unchanged
        SELECT
            a.BranchCode,
            c.ReferenceCode,
            b.OrderCode,
            0,
            b.Quantity,
            0,
            0,
            0,
            0
        FROM POSUMMARY a WITH (NOLOCK)
        INNER JOIN PODETAILS b WITH (NOLOCK)
            ON a.ShipmentNo = b.ShipmentNo
        INNER JOIN Inventory c WITH (NOLOCK)
            ON b.ShipmentNo = c.ShipmentNo
           AND b.OrderCode = c.Product
        WHERE a.BranchCode = @parmbrcode
          AND a.TargetDate BETWEEN @datefrom AND @dateto

        UNION ALL

        -- C.1 ADJUSTMENT -- unchanged (pre-existing: always 0)
        SELECT
            a.BranchCode,
            c.ReferenceCode,
            b.OrderCode,
            0,
            0,
            0,
            0,
            0,
            0
        FROM POSUMMARY a WITH (NOLOCK)
        INNER JOIN PODETAILS b WITH (NOLOCK)
            ON a.ShipmentNo = b.ShipmentNo
        INNER JOIN Inventory c WITH (NOLOCK)
            ON b.ShipmentNo = c.ShipmentNo
        WHERE a.BranchCode = @parmbrcode
          AND a.TargetDate BETWEEN @datefrom AND @dateto

        UNION ALL

        -- C.2 UNIT SOLD + SALES -- CHANGED 2026-09-29: customer sales only
        -- (transfers excluded) and filtered to the date range.
        SELECT
            a.BranchCode,
            b.ReferenceCode,
            a.ProductNo,
            0,
            0,
            0,
            CAST(a.QtyDelivered AS DECIMAL(18,3)),   -- float -> decimal (keeps ItemValue/COGS decimal)
            0,
            a.TotalAmount
        FROM InventoryDeliveryFIFO a WITH (NOLOCK)
        INNER JOIN Inventory b WITH (NOLOCK)
            ON a.SequenceReferenceNumber = b.SequenceNumber
        WHERE a.BranchCode = @parmbrcode
          AND a.isErrorCorrect = 0
          AND a.DateProcessed >= @datefrom
          AND a.DateProcessed < DATEADD(DAY, 1, @dateto)
          AND NOT EXISTS (SELECT 1 FROM dbo.TransferOrderSummary TOS WHERE TOS.PONumber = a.PONumber)

        UNION ALL

        -- C.3 INVENTORY TRANSFER (out) -- NEW 2026-09-29: attributed to the
        -- SOURCE lot's branch (b.Branch). a.BranchCode on a transfer row is
        -- the requesting/destination branch, so it can't be used here.
        SELECT
            b.Branch,
            b.ReferenceCode,
            a.ProductNo,
            0,
            0,
            0,
            0,
            CAST(a.QtyDelivered AS DECIMAL(18,3)),   -- float -> decimal (keeps ItemValue/COGS decimal)
            0
        FROM InventoryDeliveryFIFO a WITH (NOLOCK)
        INNER JOIN Inventory b WITH (NOLOCK)
            ON a.SequenceReferenceNumber = b.SequenceNumber
        WHERE b.Branch = @parmbrcode
          AND a.isErrorCorrect = 0
          AND a.DateProcessed >= @datefrom
          AND a.DateProcessed < DATEADD(DAY, 1, @dateto)
          AND EXISTS (SELECT 1 FROM dbo.TransferOrderSummary TOS WHERE TOS.PONumber = a.PONumber)
    ),
    -- CHANGED 2026-09-29: one row per item (was also grouped by Cost, which
    -- split every item into a stock row and a zero-cost movement row).
    -- Blank and NULL ReferenceCode are treated as the same item (normalised to ''
    -- here and in ItemCost) so a product can't split into two rows, or join to two
    -- cost rows and double its figures, if its lots mix '' and NULL.
    Aggregated AS (
        SELECT
            BranchCode,
            ISNULL(ItemCode, '') AS ItemCode,
            ProductCode,
            SUM(BeginningQty)      AS BeginningQty,
            SUM(UnitPurchased)     AS UnitPurchased,
            SUM(Adjustment)        AS Adjustment,
            SUM(UnitSold)          AS UnitSold,
            SUM(InventoryTransfer) AS InventoryTransfer,
            SUM(Sales)             AS TotalAmount
        FROM UnifiedReport
        GROUP BY BranchCode, ISNULL(ItemCode, ''), ProductCode
    ),
    -- NEW 2026-09-29: unit cost from ALL of the branch's lots for the item
    -- (quantity-weighted), not only lots received in the date range. Rounded to
    -- 2 decimals HERE, so the UnitCost shown is exactly the one ItemValue and
    -- Cost are multiplied by.
    ItemCost AS (
        SELECT
            Branch AS BranchCode,
            ISNULL(ReferenceCode, '') AS ItemCode,
            Product AS ProductCode,
            CAST(CASE WHEN SUM(ISNULL(Quantity, 0)) = 0 THEN MAX(ISNULL(Cost, 0))
                      ELSE SUM(ISNULL(Quantity, 0) * ISNULL(Cost, 0)) / SUM(ISNULL(Quantity, 0))
                 END AS DECIMAL(18,2)) AS UnitCost
        FROM dbo.Inventory WITH (NOLOCK)
        WHERE Branch = @parmbrcode
        GROUP BY Branch, ISNULL(ReferenceCode, ''), Product
    )
    SELECT
        L.BranchCode,
        NULLIF(L.ItemCode, '') AS ItemCode,   -- blank shown as NULL, as before
        L.ProductCode,
        P.Description,
        C.Description AS Category,
        L.BeginningQty,
        L.UnitPurchased,
        L.Adjustment,
        L.UnitSold,
        L.InventoryTransfer,                                                                 -- NEW
        (L.BeginningQty + L.UnitPurchased) - (L.Adjustment + L.UnitSold + L.InventoryTransfer) AS QtyOnHand,
        ISNULL(IC.UnitCost, 0) AS UnitCost,
        ((L.BeginningQty + L.UnitPurchased) - (L.Adjustment + L.UnitSold + L.InventoryTransfer)) * ISNULL(IC.UnitCost, 0) AS ItemValue,
        L.TotalAmount AS Sales,
        L.UnitSold * ISNULL(IC.UnitCost, 0) AS Cost
    FROM Aggregated L
    LEFT JOIN ItemCost IC
        ON IC.BranchCode = L.BranchCode
       AND IC.ItemCode = L.ItemCode        -- both already normalised to ''
       AND IC.ProductCode = L.ProductCode
    INNER JOIN Products P WITH (NOLOCK)
        ON L.BranchCode = P.BranchCode
       AND L.ProductCode = P.ProductCode
    INNER JOIN ProductCategory C WITH (NOLOCK)
        ON P.ProductCategoryCode = C.ProductCategoryID;
END
GO
