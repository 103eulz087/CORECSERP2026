/* ================================================================
   2026-09-28d: sp_rpt_ItemCostingReport_Master -- separate TRANSFER
   totals from SOLD totals (Reporting/ItemCostingReport.cs).
   ================================================================
   Companion to 2026-09-28c (sp_rpt_ItemCostingReport_Detail), which
   labels each InventoryDeliveryFIFO movement 'Transfer' (PONumber found
   in TransferOrderSummary) or 'Sold' (everything else). Without this
   change the Master row kept counting transfers in TotalSoldQty /
   TotalCostOfSales, so Master and its Detail ledger stopped agreeing.

   CHANGED (same Transfer/Sold rule as the Detail proc):
     TotalSoldQty, TotalCostOfSales, TotalSalesRevenue -- Sold only
     NEW TotalTransferQty, TotalTransferCost          -- Transfer only
   Transfers carry no TotalAmount (checked on COREX001: 0.00 on all 108
   transfer FIFO rows), so TotalSalesRevenue is unchanged in practice.
   BeginningQty / CurrentAvailable / RemainingValue / adjusted /
   converted columns are unchanged. The two new columns are inserted
   right after TotalSalesRevenue; the caller binds by column name.

   Only caller: Reporting/ItemCostingReport.cs.
   Deploy to COREX001 (DEV) first; CORECSJFC2026_STAGING only after the
   user confirms -- together with 2026-09-28c.
   ================================================================ */

IF OBJECT_ID('dbo.sp_rpt_ItemCostingReport_Master', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_ItemCostingReport_Master', 'sp_rpt_ItemCostingReport_Master_OLD_09282026150000';
GO
CREATE PROCEDURE [dbo].[sp_rpt_ItemCostingReport_Master]
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
        -- CHANGED 2026-09-28d: split Sold vs Transfer, same rule as the Detail proc
        -- (PONumber in TransferOrderSummary = Transfer, everything else = Sold).
        SELECT
            I.Branch, I.Product, I.ShipmentNo, ISNULL(I.ReferenceCode, '') AS ReferenceCode,
            SUM(CASE WHEN MT.IsTransfer = 0 THEN ISNULL(D.QtyDelivered, 0) ELSE 0 END) AS TotalSoldQty,
            SUM(CASE WHEN MT.IsTransfer = 0 THEN ISNULL(D.TotalCost, 0)    ELSE 0 END) AS TotalCostOfSales,
            SUM(CASE WHEN MT.IsTransfer = 0 THEN ISNULL(D.TotalAmount, 0)  ELSE 0 END) AS TotalSalesRevenue,
            SUM(CASE WHEN MT.IsTransfer = 1 THEN ISNULL(D.QtyDelivered, 0) ELSE 0 END) AS TotalTransferQty,
            SUM(CASE WHEN MT.IsTransfer = 1 THEN ISNULL(D.TotalCost, 0)    ELSE 0 END) AS TotalTransferCost
        FROM dbo.InventoryDeliveryFIFO D
        JOIN dbo.Inventory I ON I.SequenceNumber = D.SequenceReferenceNumber
        CROSS APPLY (
            SELECT CASE WHEN EXISTS (SELECT 1 FROM dbo.TransferOrderSummary TOS WHERE TOS.PONumber = D.PONumber)
                        THEN 1 ELSE 0 END AS IsTransfer
        ) MT
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
        ISNULL(S.TotalTransferQty, 0)    AS TotalTransferQty,     -- NEW 2026-09-28d
        ISNULL(S.TotalTransferCost, 0)   AS TotalTransferCost,    -- NEW 2026-09-28d
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
