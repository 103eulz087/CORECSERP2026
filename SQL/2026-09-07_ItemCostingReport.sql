-- =============================================
-- Author: Eulz Avancena; 2026-09-07 (revised same day after sp-reviewer findings)
-- Description: New Item Costing Report (Reporting/ItemCostingReport.cs) -- a per-lot
--   "stock card" style master-detail report, requested with a Google Sheets example
--   showing: one lot identified by ShipmentNo+ReferenceCode, a Beginning Balance row,
--   then chronological Received/Sold/Adjusted movement rows with a running qty/value
--   balance. Built master-detail (per user's explicit choice) rather than mirroring the
--   flat/grouped spreadsheet layout directly, for the same reason ConversionReportMasterDetail
--   was: it scales far better once there are thousands of lots.
--
--   LOT GROUPING KEY: Per CLAUDE.md's known bug pattern -- "Inventory.ShipmentNo alone is
--   NOT a unique per-batch key... group/filter by Product+ShipmentNo+ReferenceCode instead"
--   -- confirmed live: (Product='13035', ShipmentNo='00222', ReferenceCode='202610379') alone
--   spans 2520 individual Inventory rows (individually barcoded pieces of one receiving
--   batch), all received on the same single date. So a "lot" for this report is the
--   composite (Branch, Product, ShipmentNo, ReferenceCode) group, aggregating across
--   however many underlying Inventory.SequenceNumber rows share it -- exactly matching
--   "group item per reference code or shipment" from the task description.
--   (No @Product parameter is exposed -- master/detail rows are correlated client-side via
--   the full LotKey composite by Database.GridMasterDetail's DataRelation, not a per-row
--   SQL re-query, so this is not a data-mixing risk despite the ShipmentNo-alone-not-unique
--   pattern this file itself is built around.)
--
--   ADJUSTMENT SEMANTICS -- REVISED after sp-reviewer caught a real bug in the first version:
--   dbo.InventoryAdjustment.SeqRefNum is NOT a usable Inventory.SequenceNumber reference --
--   confirmed against dbo.sp_InvQtyAdjustment (SQL\2026-08-03_InventoryQtyAdjustment_*.sql),
--   which hardcodes SeqRefNum to the literal '' (which SQL Server silently coerces to 0 on
--   insert into the INT column) for every 'DEDUCT' (isQty=1) row it writes -- confirmed live,
--   every InventoryAdjustment row sampled has SeqRefNum=0, which can never match a real
--   Inventory.SequenceNumber (an IDENTITY column). The original version of this report joined
--   through that column directly, meaning TotalAdjustedQty/TotalAdjustedAmount silently
--   computed to 0 for every lot -- a real, quiet reporting bug now fixed.
--     - isQty=1 ('DEDUCT'): the ACTUAL per-lot attribution lives in
--       dbo.InventoryAdjustmentFIFO.SequenceReferenceNumber instead (populated correctly
--       inside sp_InvQtyAdjustment's own cursor loop -- verified live against real data:
--       SequenceReferenceNumber values there resolve to real Inventory rows with real
--       ShipmentNo/ReferenceCode). QtyDeducted/Cost there are per-lot magnitudes of a
--       reduction; modeled as a QtyOut movement (QtyDeducted * Cost = amount removed).
--     - isCost=1 ('COST ADJUSTMENT'): DROPPED from this report entirely, not just excluded
--       from the running totals as the first version did. dbo.InventoryAdjustment.ShipmentNo
--       IS populated correctly for these rows (unlike isQty=1 rows), but SeqRefNum is STILL
--       unusable (also observed as 0 live), and there is no per-lot detail table for cost
--       adjustments the way InventoryAdjustmentFIFO exists for quantity deductions -- the
--       finest attribution available is (Branch, ShipmentNo, ProductCode), which cannot
--       distinguish between multiple ReferenceCode lots sharing one shipment. Showing a
--       shipment-wide cost re-rate against one arbitrary ReferenceCode lot within that
--       shipment would misattribute it, which is worse than omitting it. The master row's
--       own UnitCost/RemainingValue are computed straight from Inventory's CURRENT
--       Cost/Available regardless, so the latest cost is still reflected there.
--     - If a future AdjustmentType ever represents an INCREASE rather than a deduction,
--       this SP's hardcoded "QtyOut" modeling of InventoryAdjustmentFIFO rows would need
--       revisiting -- flagged here since no such type exists in the data today.
--
--   MOVEMENT DATE PRECISION: all 4 movement branches below truncate their date column to
--   DATE explicitly (even ones already DATE-typed, for self-documentation) so the
--   chronological ORDER BY MovementDate, SortOrder tiebreaker behaves consistently --
--   mixing DATE and full-precision DATETIME columns in one UNION previously let a same-day
--   event with a real afternoon timestamp sort ahead of/behind another same-day event in a
--   way SortOrder couldn't correct, since MovementDate values were rarely exactly equal.
--
--   KNOWN LIMITATION -- this is NOT a complete reconciliation of every possible way
--   Inventory.Available can change. Verified live on a real lot (Product=13035,
--   ShipmentNo=00222, ReferenceCode=202610379, 2520 pieces) before the InventoryAdjustment
--   fix above: BeginningQty - TotalSoldQty left a 1010-unit gap against the live Available
--   snapshot; 280 units were explained by ConversionBarcodeSourceDetails (modeled below as
--   a "Converted" movement type). That specific test lot had no InventoryAdjustment activity
--   of its own, so the adjustment-attribution fix doesn't change its reconciliation number,
--   but lots that DO have DEDUCT history should reconcile more accurately now than before
--   this fix. Any residual gap on a given lot is still possible (branch transfers, POS
--   stock-outs, or another write-path this report doesn't model) -- the MASTER row's
--   CurrentAvailable/RemainingValue are pulled directly from live Inventory and are always
--   correct regardless; the DETAIL ledger's running balance can legitimately fall short of
--   that live figure -- a transparency gap to flag to users, not a bug to silently paper over.
-- =============================================

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-------------------------------------------------------------------
-- 1. sp_rpt_ItemCostingReport_Master -- one row per (Branch, Product, ShipmentNo,
--    ReferenceCode) lot group.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_ItemCostingReport_Master', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_rpt_ItemCostingReport_Master;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE dbo.sp_rpt_ItemCostingReport_Master
    @Branch        VARCHAR(5)   = NULL,
    @DateFrom      DATE         = NULL,
    @DateTo        DATE         = NULL,
    @ShipmentNo    VARCHAR(10)  = NULL,
    @ReferenceCode VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH LotBase AS (
        SELECT
            Branch, Product, ShipmentNo, ISNULL(ReferenceCode, '') AS ReferenceCode,
            MIN(DateReceived) AS DateReceived,
            SUM(ISNULL(Quantity, 0)) AS BeginningQty,
            SUM(ISNULL(Quantity, 0) * ISNULL(Cost, 0)) AS BeginningCostTotal,
            SUM(ISNULL(Available, 0)) AS CurrentAvailable,
            SUM(ISNULL(Available, 0) * ISNULL(Cost, 0)) AS RemainingValue
        FROM dbo.Inventory
        WHERE (@Branch IS NULL OR Branch = @Branch)
          AND (@DateFrom IS NULL OR DateReceived >= @DateFrom)
          AND (@DateTo IS NULL OR DateReceived < DATEADD(DAY, 1, @DateTo))
          AND (@ShipmentNo IS NULL OR ShipmentNo = @ShipmentNo)
          AND (@ReferenceCode IS NULL OR ReferenceCode = @ReferenceCode)
        GROUP BY Branch, Product, ShipmentNo, ISNULL(ReferenceCode, '')
    ),
    SoldAgg AS (
        -- TotalCostOfSales uses TotalCost (Qty*UnitCost, the cost-basis leaving inventory),
        -- NOT TotalAmount (Qty*SellingPrice, revenue) -- confirmed live that TotalAmount is
        -- NULL for some real delivery rows (e.g. non-revenue/internal-use movements) while
        -- TotalCost is still populated, and a valuation report must deplete by cost, not
        -- revenue, regardless. TotalSalesRevenue is kept separately, informational only.
        SELECT
            I.Branch, I.Product, I.ShipmentNo, ISNULL(I.ReferenceCode, '') AS ReferenceCode,
            SUM(ISNULL(D.QtyDelivered, 0)) AS TotalSoldQty,
            SUM(ISNULL(D.TotalCost, 0))    AS TotalCostOfSales,
            SUM(ISNULL(D.TotalAmount, 0))  AS TotalSalesRevenue
        FROM dbo.InventoryDeliveryFIFO D
        JOIN dbo.Inventory I ON I.SequenceNumber = D.SequenceReferenceNumber
        WHERE D.isErrorCorrect = 0
          AND (@Branch IS NULL OR I.Branch = @Branch)
          AND (@ShipmentNo IS NULL OR I.ShipmentNo = @ShipmentNo)
          AND (@ReferenceCode IS NULL OR I.ReferenceCode = @ReferenceCode)
        GROUP BY I.Branch, I.Product, I.ShipmentNo, ISNULL(I.ReferenceCode, '')
    ),
    AdjAgg AS (
        -- Attributed via InventoryAdjustmentFIFO.SequenceReferenceNumber, NOT
        -- InventoryAdjustment.SeqRefNum -- see header comment (SeqRefNum is unusable).
        SELECT
            I.Branch, I.Product, I.ShipmentNo, ISNULL(I.ReferenceCode, '') AS ReferenceCode,
            SUM(ISNULL(AF.QtyDeducted, 0)) AS TotalAdjustedQty,
            SUM(ISNULL(AF.QtyDeducted, 0) * ISNULL(AF.Cost, 0)) AS TotalAdjustedAmount
        FROM dbo.InventoryAdjustmentFIFO AF
        JOIN dbo.Inventory I ON I.SequenceNumber = AF.SequenceReferenceNumber
        WHERE (@Branch IS NULL OR I.Branch = @Branch)
          AND (@ShipmentNo IS NULL OR I.ShipmentNo = @ShipmentNo)
          AND (@ReferenceCode IS NULL OR I.ReferenceCode = @ReferenceCode)
        GROUP BY I.Branch, I.Product, I.ShipmentNo, ISNULL(I.ReferenceCode, '')
    ),
    ConvertedAgg AS (
        -- Lots used as conversion SOURCE material (barcode-based Conversion system --
        -- see 2026-09-07_ConversionReportMasterDetail.sql for the full module).
        SELECT
            I.Branch, I.Product, I.ShipmentNo, ISNULL(I.ReferenceCode, '') AS ReferenceCode,
            SUM(ISNULL(CSD.Qty, 0))    AS TotalConvertedQty,
            SUM(ISNULL(CSD.Amount, 0)) AS TotalConvertedAmount
        FROM dbo.ConversionBarcodeSourceDetails CSD
        JOIN dbo.Inventory I ON I.SequenceNumber = CSD.InventorySeqNo
        WHERE (@Branch IS NULL OR I.Branch = @Branch)
          AND (@ShipmentNo IS NULL OR I.ShipmentNo = @ShipmentNo)
          AND (@ReferenceCode IS NULL OR I.ReferenceCode = @ReferenceCode)
        GROUP BY I.Branch, I.Product, I.ShipmentNo, ISNULL(I.ReferenceCode, '')
    )
    SELECT
        L.Product + '|' + L.ShipmentNo + '|' + L.ReferenceCode AS LotKey,
        L.Branch,
        B.BranchName,
        L.ShipmentNo,
        L.ReferenceCode,
        L.Product,
        P.Description,
        PC.Description AS Category,
        L.DateReceived,
        L.BeginningQty,
        CASE WHEN L.BeginningQty = 0 THEN 0 ELSE L.BeginningCostTotal / L.BeginningQty END AS UnitCost,
        L.CurrentAvailable,
        ISNULL(S.TotalSoldQty, 0)        AS TotalSoldQty,
        ISNULL(S.TotalCostOfSales, 0)    AS TotalCostOfSales,
        ISNULL(S.TotalSalesRevenue, 0)   AS TotalSalesRevenue,
        ISNULL(A.TotalAdjustedQty, 0)    AS TotalAdjustedQty,
        ISNULL(A.TotalAdjustedAmount, 0) AS TotalAdjustedAmount,
        ISNULL(C.TotalConvertedQty, 0)    AS TotalConvertedQty,
        ISNULL(C.TotalConvertedAmount, 0) AS TotalConvertedAmount,
        L.RemainingValue
    FROM LotBase L
    LEFT JOIN dbo.Branches B ON B.BranchCode = L.Branch
    LEFT JOIN dbo.Products P ON P.ProductCode = L.Product AND P.BranchCode = '888'
    LEFT JOIN dbo.ProductCategory PC ON PC.ProductCategoryID = P.ProductCategoryCode
    LEFT JOIN SoldAgg S ON S.Branch = L.Branch AND S.Product = L.Product AND S.ShipmentNo = L.ShipmentNo AND S.ReferenceCode = L.ReferenceCode
    LEFT JOIN AdjAgg A ON A.Branch = L.Branch AND A.Product = L.Product AND A.ShipmentNo = L.ShipmentNo AND A.ReferenceCode = L.ReferenceCode
    LEFT JOIN ConvertedAgg C ON C.Branch = L.Branch AND C.Product = L.Product AND C.ShipmentNo = L.ShipmentNo AND C.ReferenceCode = L.ReferenceCode
    ORDER BY L.DateReceived DESC, L.ShipmentNo, L.ReferenceCode;
END
GO

-------------------------------------------------------------------
-- 2. sp_rpt_ItemCostingReport_Detail -- chronological movement ledger per lot group,
--    with a running qty/value balance.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_ItemCostingReport_Detail', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_rpt_ItemCostingReport_Detail;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE dbo.sp_rpt_ItemCostingReport_Detail
    @Branch        VARCHAR(5)   = NULL,
    @DateFrom      DATE         = NULL,
    @DateTo        DATE         = NULL,
    @ShipmentNo    VARCHAR(10)  = NULL,
    @ReferenceCode VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Movements AS (
        -- Received (usually one row per lot -- grouped by date defensively in case a lot's
        -- pieces were ever received across more than one date).
        SELECT
            Product + '|' + ShipmentNo + '|' + ISNULL(ReferenceCode, '') AS LotKey,
            CAST(DateReceived AS DATE) AS MovementDate,
            'Received' AS MovementType,
            CAST(NULL AS VARCHAR(50)) AS Reference,
            SUM(ISNULL(Quantity, 0)) AS QtyIn,
            CAST(0 AS DECIMAL(18,3)) AS QtyOut,
            SUM(ISNULL(Quantity, 0) * ISNULL(Cost, 0)) AS AmountIn,
            CAST(0 AS DECIMAL(18,2)) AS AmountOut,
            CAST(0 AS DECIMAL(18,2)) AS SalesAmount,
            1 AS SortOrder
        FROM dbo.Inventory
        WHERE (@Branch IS NULL OR Branch = @Branch)
          AND (@DateFrom IS NULL OR DateReceived >= @DateFrom)
          AND (@DateTo IS NULL OR DateReceived < DATEADD(DAY, 1, @DateTo))
          AND (@ShipmentNo IS NULL OR ShipmentNo = @ShipmentNo)
          AND (@ReferenceCode IS NULL OR ReferenceCode = @ReferenceCode)
        GROUP BY Product, ShipmentNo, ISNULL(ReferenceCode, ''), DateReceived

        UNION ALL

        -- Sold -- one row per (date, delivery ticket) rather than per individual piece,
        -- to keep the ledger at a human-readable transaction granularity. AmountOut uses
        -- TotalCost (cost basis leaving inventory), not TotalAmount (sales revenue) -- see
        -- header comment. TotalAmount is kept as a separate informational SalesAmount
        -- column and does NOT feed the running qty/value balance.
        SELECT
            I.Product + '|' + I.ShipmentNo + '|' + ISNULL(I.ReferenceCode, '') AS LotKey,
            CAST(D.DateProcessed AS DATE),
            'Sold',
            CAST(D.DeliveryNo AS VARCHAR(50)),
            CAST(0 AS DECIMAL(18,3)),
            SUM(ISNULL(D.QtyDelivered, 0)),
            CAST(0 AS DECIMAL(18,2)),
            SUM(ISNULL(D.TotalCost, 0)),
            SUM(ISNULL(D.TotalAmount, 0)),
            2
        FROM dbo.InventoryDeliveryFIFO D
        JOIN dbo.Inventory I ON I.SequenceNumber = D.SequenceReferenceNumber
        WHERE D.isErrorCorrect = 0
          AND (@Branch IS NULL OR I.Branch = @Branch)
          AND (@ShipmentNo IS NULL OR I.ShipmentNo = @ShipmentNo)
          AND (@ReferenceCode IS NULL OR I.ReferenceCode = @ReferenceCode)
        GROUP BY I.Product, I.ShipmentNo, ISNULL(I.ReferenceCode, ''), D.DateProcessed, D.DeliveryNo

        UNION ALL

        -- Quantity-reducing adjustments -- attributed via InventoryAdjustmentFIFO, NOT
        -- InventoryAdjustment.SeqRefNum (see header comment: that column is unusable, always
        -- 0). QtyDeducted/Cost here are genuine per-lot magnitudes of a reduction.
        SELECT
            I.Product + '|' + I.ShipmentNo + '|' + ISNULL(I.ReferenceCode, '') AS LotKey,
            CAST(AF.DateAdded AS DATE),
            'Adjusted',
            CAST('DEDUCT' AS VARCHAR(50)),
            CAST(0 AS DECIMAL(18,3)),
            SUM(ISNULL(AF.QtyDeducted, 0)),
            CAST(0 AS DECIMAL(18,2)),
            SUM(ISNULL(AF.QtyDeducted, 0) * ISNULL(AF.Cost, 0)),
            CAST(0 AS DECIMAL(18,2)),
            3
        FROM dbo.InventoryAdjustmentFIFO AF
        JOIN dbo.Inventory I ON I.SequenceNumber = AF.SequenceReferenceNumber
        WHERE (@Branch IS NULL OR I.Branch = @Branch)
          AND (@ShipmentNo IS NULL OR I.ShipmentNo = @ShipmentNo)
          AND (@ReferenceCode IS NULL OR I.ReferenceCode = @ReferenceCode)
        GROUP BY I.Product, I.ShipmentNo, ISNULL(I.ReferenceCode, ''), AF.DateAdded

        UNION ALL

        -- Consumed as conversion source material (barcode-based Conversion system).
        -- AmountOut uses CSD.Amount (Qty*Cost, the cost-basis leaving inventory) --
        -- ConversionBarcodeSourceDetails has no separate revenue-style column to worry
        -- about mixing in, unlike the Sold branch above.
        SELECT
            I.Product + '|' + I.ShipmentNo + '|' + ISNULL(I.ReferenceCode, '') AS LotKey,
            CAST(CSum.DateConverted AS DATE),
            'Converted',
            CAST(CSD.ConversionRefNo AS VARCHAR(50)),
            CAST(0 AS DECIMAL(18,3)),
            SUM(ISNULL(CSD.Qty, 0)),
            CAST(0 AS DECIMAL(18,2)),
            SUM(ISNULL(CSD.Amount, 0)),
            CAST(0 AS DECIMAL(18,2)),
            4
        FROM dbo.ConversionBarcodeSourceDetails CSD
        JOIN dbo.Inventory I ON I.SequenceNumber = CSD.InventorySeqNo
        JOIN dbo.ConversionBarcodeSummary CSum ON CSum.ConversionRefNo = CSD.ConversionRefNo
        WHERE (@Branch IS NULL OR I.Branch = @Branch)
          AND (@ShipmentNo IS NULL OR I.ShipmentNo = @ShipmentNo)
          AND (@ReferenceCode IS NULL OR I.ReferenceCode = @ReferenceCode)
        GROUP BY I.Product, I.ShipmentNo, ISNULL(I.ReferenceCode, ''), CSum.DateConverted, CSD.ConversionRefNo
    )
    SELECT
        LotKey,
        MovementDate,
        MovementType,
        Reference,
        QtyIn,
        QtyOut,
        AmountIn,
        AmountOut,
        SalesAmount,
        SUM(ISNULL(QtyIn, 0) - ISNULL(QtyOut, 0)) OVER (PARTITION BY LotKey ORDER BY MovementDate, SortOrder ROWS UNBOUNDED PRECEDING) AS RunningQty,
        SUM(ISNULL(AmountIn, 0) - ISNULL(AmountOut, 0)) OVER (PARTITION BY LotKey ORDER BY MovementDate, SortOrder ROWS UNBOUNDED PRECEDING) AS RunningValue
    FROM Movements
    ORDER BY LotKey, MovementDate, SortOrder;
END
GO

PRINT 'DEPLOYMENT COMPLETE: sp_rpt_ItemCostingReport_Master, sp_rpt_ItemCostingReport_Detail.';
