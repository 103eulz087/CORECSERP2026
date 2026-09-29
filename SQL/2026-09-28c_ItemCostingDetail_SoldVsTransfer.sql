/* ================================================================
   2026-09-28c: sp_rpt_ItemCostingReport_Detail -- split MovementType
   'Sold' into 'Sold' and 'Transfer' (Reporting/ItemCostingReport.cs).
   ================================================================
   InventoryDeliveryFIFO holds BOTH customer sales and branch transfers.
   They're told apart by the delivery's PONumber:
     - found in TransferOrderSummary.PONumber  -> 'Transfer'
     - otherwise                                -> 'Sold'
   Checked on COREX001 (7,109 distinct delivery PONumbers):
     7,070 in PurchaseOrderSummary only, 25 in TransferOrderSummary only,
     0 in both, 14 in neither. The 14 (branch 004, 2026-09-09) carry
     customer charge-invoice numbers (e.g. C-048076) in DeliverySummary,
     i.e. sales whose PurchaseOrderSummary header is missing -- so they
     stay 'Sold', as the report showed them before.
   Why a bare PONumber match is safe (not just "0 collisions today"):
   PurchaseOrderSummary and TransferOrderSummary draw their numbers from
   ONE shared counter (dbo.ponumber), so a purchase and a transfer can't
   share a PONumber, and no branch predicate is needed.
   ServiceOrderSummary is NOT used: it has its own SVCNumber sequence,
   which overlaps PurchaseOrderSummary.PONumber (164 collisions), and it
   matches none of the 14.

   Only the label changes. QtyOut / AmountOut / SalesAmount, the running
   balances, SortOrder and row granularity (one row per delivery) are
   unchanged -- a delivery never spans two PONumbers (checked: 0), so
   adding PONumber to the GROUP BY adds no rows.

   Only caller: Reporting/ItemCostingReport.cs (shows MovementType as
   "Type"; no code keys off the 'Sold' text).
   Deploy to COREX001 (DEV) first; CORECSJFC2026_STAGING only after the
   user confirms.
   ================================================================ */

IF OBJECT_ID('dbo.sp_rpt_ItemCostingReport_Detail', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_ItemCostingReport_Detail', 'sp_rpt_ItemCostingReport_Detail_OLD_09282026140000';
GO
CREATE PROCEDURE [dbo].[sp_rpt_ItemCostingReport_Detail]
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

        -- Sold / Transfer (CHANGED 2026-09-28c, was all 'Sold') -- one row per (date, delivery ticket) rather than per individual piece,
        -- to keep the ledger at a human-readable transaction granularity. AmountOut uses
        -- TotalCost (cost basis leaving inventory), not TotalAmount (sales revenue) -- see
        -- header comment. TotalAmount is kept as a separate informational SalesAmount
        -- column and does NOT feed the running qty/value balance.
        SELECT
            I.Product + '|' + I.ShipmentNo + '|' + ISNULL(I.ReferenceCode, '') AS LotKey,
            CAST(D.DateProcessed AS DATE),
            MT.MovementType,                                   -- CHANGED 2026-09-28c: was 'Sold'
            CAST(D.DeliveryNo AS VARCHAR(50)),
            CAST(0 AS DECIMAL(18,3)),
            SUM(ISNULL(D.QtyDelivered, 0)),
            CAST(0 AS DECIMAL(18,2)),
            SUM(ISNULL(D.TotalCost, 0)),
            SUM(ISNULL(D.TotalAmount, 0)),
            2
        FROM dbo.InventoryDeliveryFIFO D
        JOIN dbo.Inventory I ON I.SequenceNumber = D.SequenceReferenceNumber
        -- NEW 2026-09-28c: a delivery whose PONumber is a transfer order is a
        -- branch TRANSFER; everything else is a customer sale (see header).
        CROSS APPLY (
            SELECT CASE WHEN EXISTS (SELECT 1 FROM dbo.TransferOrderSummary TOS WHERE TOS.PONumber = D.PONumber)
                        THEN 'Transfer' ELSE 'Sold' END AS MovementType
        ) MT
        WHERE D.isErrorCorrect = 0
          AND (@Branch IS NULL OR I.Branch = @Branch)
          AND (@ShipmentNo IS NULL OR I.ShipmentNo = @ShipmentNo)
          AND (@ReferenceCode IS NULL OR I.ReferenceCode = @ReferenceCode)
        GROUP BY I.Product, I.ShipmentNo, ISNULL(I.ReferenceCode, ''), D.DateProcessed, D.DeliveryNo, MT.MovementType

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
