/* ================================================================
   [102] 2026-10-17  Inventory Unit Activity report: every movement, per lot
   ================================================================
   User (2026-10-17): Inventory Unit Activity must show conversion out (the source consumed) and conversion
   in (the output), STS in / STS out, Inventory IN; a shipment received this month shows under Unit
   Purchased, next month it is part of the Beginning Qty.
   Assessment: docs/plans/2026-10-17_InventoryUnitActivity_Report_Plan.md. The old proc counted receipts
   twice (Beginning = lots RECEIVED in the period) and multiplied Unit Purchased by the shipment's lot
   count (888 Sept 731,662,883.94 kg; PORK CUTTING FAT SKINLESS 174,527,772.50 vs 119,808.50 ordered).
   User decisions (2026-10-17):
     1. a shipment still FOR CONFIRMATION counts in Unit Purchased when it is received;
     2. a cancel / return keyed later shows in a new Sales Return column on the day it was keyed, so a
        closed month never changes;
     3. the 09-07 opening loads are part of Beginning Qty;
     4. Branch Transfer (the non-STS module) has its own In / Out columns;
     5. head office may run it for ALL branches (@parmbrcode NULL, '' or 'ALL').

   RULES (one row per branch + item code (lot ReferenceCode) + product)
   - Every IN is an Inventory lot; every OUT is a row pointing at a lot. Figures are computed per lot and
     added up, so Qty On Hand of one period = Beginning Qty of the next (except across 2026-09-07, when the
     opening loads join Beginning Qty), and Qty On Hand as of today =
     the lots' Available (except a FOR CONFIRMATION shipment, held at Available 0 until confirmed).
   - Lot kinds: a lot received from a branch transfer (barcode in ReceivedTransferInventoryDetails, to this branch) -> Branch
     Transfer In; an STS receipt (barcode in ReceivedOrderDetails of an STS requested by this branch, or a
     copy of an earlier lot of another branch: same ShipmentNo + ReferenceCode, conversion outputs included)
     -> STS In; a conversion output (isConversion / ShipmentNo CONVERSION) -> Conversion In; a PO of the
     lot's own branch -> Unit Purchased (DELIVERED POs keyed by 09-07 = the HO opening load); blank /
     '00000' ShipmentNo (Inventory IN / ADD adjustment) -> Inventory In; anything else received on or
     before 2026-09-07 = the branch opening load; anything else later -> Inventory In.
   - Opening loads (received on or before 2026-09-07) are in Beginning Qty of every period that ends on
     or after their receipt date.
   - Dates: lot = DateReceived; sale / STS out = InventoryDeliveryFIFO.DateProcessed; conversion =
     DateConverted (the date picked on screen since [67]); branch transfer = DateAdded; stock out =
     DateAdded; quantity DEDUCT = InventoryAdjustmentFIFO.DateAdded.
   - A cancelled or returned SALES row stays in Unit Sold on its own date and comes back in Sales Return on
     the day it was cancelled / returned (SalesReturnLog.CreatedAt, else ReturnedOrderDetails.DateProcessed,
     else the cancel's stock-ledger row (since 09-09), else the line's DateTimeUpdated (= the ledger cancel day
     on 464 / 466 lines on PRODUCTION)). Every other reversal is a negative figure in the same column on the
     reversal day: STS line cancelled -> STS Out; conversion reversed -> Conversion Out and Conversion In;
     branch transfer cancelled -> Branch Transfer Out; stock out reversed -> Adjustment.
   - Adjustment is signed: stock-out write-offs (StockOutBarcode) and quantity DEDUCT adjustments are
     negative, their reversals positive.
   - An OUT row dated before its lot was received counts on the lot's own date (conversion CVB-000001 was
     back-dated to 08-07 from opening lot 139), except old ConversionFIFO and InventoryBranchTransferFIFO rows:
     on PRODUCTION those are the pre-go-live tests of 08-04 / 08-05 (transfers 240-246) and 08-23 / 08-24 (old
     conversions) on sequence numbers reused by the 09-07 load (the lots' Available never moved): left out.
   - Not covered yet: POS V2 (POSV2_SaleLot / ReturnLot; not on STAGING / PRODUCTION): add before it goes live.
   - Values at each lot's own cost AS IT IS NOW (Inventory.Cost; an expense costed later changes the value of
     an earlier month, its quantities never): Item Value = Qty On Hand x lot cost; Cost (of
     sales) = (Unit Sold - Sales Return) x lot cost; Sales = sold amount - returned amount; Unit Cost =
     Item Value / Qty On Hand (no stock left: the lots' weighted cost).

   Measured first (read-only, PRODUCTION 2026-10-17): lot tie-out exact except the FOR CONFIRMATION lots
   (1,195,358.30 kg held) and a few lots touched by the pre-go-live test rows; out rows dated before their
   lot: 0 sales / STS rows, 8 branch-transfer rows, 25 old conversion rows; cancelled rows: sales 935
   (631 cancelled, 304 returned; 173 keyed in another month), STS 10 (1 in another month).
   Guard: spr_InventoryUnitActivity = its 2026-09-29 text (whitespace-insensitive SHA-256 34355E73...,
   identical on DEV / STAGING / PRODUCTION 2026-10-17). Needs nothing else. Read-only proc (no writes).
   One transaction with a post-check; backup spr_InventoryUnitActivity_OLD_10172026150000.
   Exe: parameter names unchanged (@parmbrcode is now optional); the old exe keeps working and shows the
   new columns without formatting; the new exe formats them, captions them and offers "ALL BRANCHES".
   The old column names that kept their meaning are kept (BeginningQty, UnitPurchased, Adjustment,
   UnitSold, QtyOnHand, UnitCost, ItemValue, Sales, Cost); InventoryTransfer is now STSOut.
   Web v2: same proc, same rules; NULL branch = all branches.
   Run in ONE connection with no open transaction.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET LOCK_TIMEOUT 10000;
GO

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[102] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.spr_InventoryUnitActivity')) LIKE '%[[]102]%'
BEGIN
    RAISERROR('[102] already applied in this database; nothing changed.', 10, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.spr_InventoryUnitActivity_OLD_10172026150000') IS NOT NULL
BEGIN
    RAISERROR('[102] stopped: the backup spr_InventoryUnitActivity_OLD_10172026150000 already exists; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.SalesReturnLog', 'U') IS NULL OR OBJECT_ID('dbo.ReturnedOrderDetails', 'U') IS NULL
     OR OBJECT_ID('dbo.ConversionBarcodeSummary', 'U') IS NULL OR OBJECT_ID('dbo.ConversionBarcodeSourceDetails', 'U') IS NULL
     OR OBJECT_ID('dbo.ConversionBarcodeOutputDetails', 'U') IS NULL OR OBJECT_ID('dbo.StockOutBarcodeSummary', 'U') IS NULL
     OR OBJECT_ID('dbo.StockOutBarcodeDetails', 'U') IS NULL OR OBJECT_ID('dbo.InventoryAdjustmentFIFO', 'U') IS NULL
     OR OBJECT_ID('dbo.InventoryBranchTransferFIFO', 'U') IS NULL OR OBJECT_ID('dbo.ReceivedTransferInventoryDetails', 'U') IS NULL
     OR OBJECT_ID('dbo.InventoryLedger', 'U') IS NULL OR OBJECT_ID('dbo.ConversionFIFO', 'U') IS NULL
     OR COL_LENGTH('dbo.InventoryDeliveryFIFO', 'DevDetSeqNo') IS NULL OR COL_LENGTH('dbo.DeliveryDetails', 'DateTimeUpdated') IS NULL
     OR COL_LENGTH('dbo.ConversionBarcodeSummary', 'DateReversed') IS NULL OR COL_LENGTH('dbo.StockOutBarcodeSummary', 'DateReversed') IS NULL
     OR COL_LENGTH('dbo.InventoryBranchTransferFIFO', 'DateUpdated') IS NULL OR COL_LENGTH('dbo.TransferOrderSummary', 'InitiatingBranch') IS NULL
BEGIN
    RAISERROR('[102] stopped: a table or column the new report reads is missing in this database; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.spr_InventoryUnitActivity', 'P') IS NULL
     OR CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.spr_InventoryUnitActivity')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '34355E73A5145F41B00F1336ED820D3FF131512AC1E840FF8C89F9CD74E699E9'
BEGIN
    RAISERROR('[102] stopped: spr_InventoryUnitActivity is missing or is not the 2026-09-29 text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[102] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
GO

------------------------------------------------------------------
-- 1. Backup of the old proc
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.spr_InventoryUnitActivity', 'spr_InventoryUnitActivity_OLD_10172026150000';
GO

------------------------------------------------------------------
-- 2. New proc (full text)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE dbo.spr_InventoryUnitActivity
    @parmbrcode CHAR(3) = NULL,     -- NULL / '' / 'ALL' = all branches
    @datefrom   DATE,
    @dateto     DATE
AS
/*  [102] 2026-10-17. Inventory Unit Activity, per lot (rules in SQL/[102]-2026-10-17_InventoryUnitActivity_PerLotMovements.sql).
    One row per branch + item code + product: Beginning Qty, the INs (Unit Purchased, STS In, Branch Transfer In,
    Conversion In, Inventory In, Sales Return), the OUTs (Unit Sold, STS Out, Branch Transfer Out, Conversion Out),
    Adjustment (+/-), Qty On Hand, values at the lots' own cost. Read-only. 59741 = bad date range.
    Previous text: spr_InventoryUnitActivity_OLD_10172026150000. */
BEGIN
    SET NOCOUNT ON;
    -- BODY-START (the lines down to BODY-END also run as a plain script for read-only checks)
    DECLARE @br VARCHAR(3) = NULLIF(LTRIM(RTRIM(ISNULL(@parmbrcode, ''))), '');
    IF @br = 'ALL' SET @br = NULL;
    IF @datefrom IS NULL OR @dateto IS NULL OR @datefrom > @dateto
        THROW 59741, N'Inventory Unit Activity: pick a From date on or before the To date.', 1;

    DECLARE @dtx         DATE = DATEADD(DAY, 1, @dateto);   -- half-open end of the period
    DECLARE @OpeningDate DATE = '2026-09-07';               -- go-live opening loads (HO and branches)
    DECLARE @Ancient     DATE = '1900-01-01';

    -- 1. The lots of the branch (or of every branch) and what brought them in -----------------------------
    CREATE TABLE #StsBarcode (Barcode VARCHAR(100) NOT NULL, Branch VARCHAR(10) NOT NULL, PRIMARY KEY (Barcode, Branch));
    INSERT INTO #StsBarcode (Barcode, Branch)
    SELECT DISTINCT LTRIM(RTRIM(r.Barcode)), LTRIM(RTRIM(t.InitiatingBranch))
    FROM dbo.ReceivedOrderDetails AS r
    INNER JOIN dbo.TransferOrderSummary AS t ON t.PONumber = r.PONumber
    WHERE ISNULL(LTRIM(RTRIM(r.Barcode)), '') <> '' AND t.InitiatingBranch IS NOT NULL;

    CREATE TABLE #BtBarcode (Barcode VARCHAR(100) NOT NULL, Branch VARCHAR(10) NOT NULL, PRIMARY KEY (Barcode, Branch));
    INSERT INTO #BtBarcode (Barcode, Branch)
    SELECT DISTINCT LTRIM(RTRIM(r.Barcode)), LTRIM(RTRIM(f.DestBranchCode))
    FROM dbo.ReceivedTransferInventoryDetails AS r
    INNER JOIN dbo.InventoryBranchTransferFIFO AS f ON f.TransferNo = r.TransferNo
    WHERE ISNULL(LTRIM(RTRIM(r.Barcode)), '') <> '' AND f.DestBranchCode IS NOT NULL;

    CREATE TABLE #Lot
    (
        Seq          INT           NOT NULL PRIMARY KEY,
        Branch       VARCHAR(10)   NOT NULL,
        ItemCode     VARCHAR(100)  NOT NULL,
        Product      VARCHAR(30)   NOT NULL,
        ShipmentNo   VARCHAR(100)  NOT NULL,
        Qty          DECIMAL(18,3) NOT NULL,
        Cost         DECIMAL(19,4) NOT NULL,
        DateReceived DATE          NOT NULL,
        EffDate      DATE          NULL,      -- the date its IN counts on (an opening load: before any period it is in)
        Kind         VARCHAR(6)    NOT NULL   -- OPEN / PUR / STSIN / BTIN / CONVIN / INVIN (UNK / UNKC while classifying)
    );

    INSERT INTO #Lot (Seq, Branch, ItemCode, Product, ShipmentNo, Qty, Cost, DateReceived, Kind)
    SELECT i.SequenceNumber, ISNULL(i.Branch, ''), ISNULL(i.ReferenceCode, ''), ISNULL(i.Product, ''), ISNULL(i.ShipmentNo, ''),
           ISNULL(i.Quantity, 0), ISNULL(i.Cost, 0), ISNULL(i.DateReceived, @Ancient),
           CASE
               WHEN bt.Barcode IS NOT NULL                                               THEN 'BTIN'
               WHEN st.Barcode IS NOT NULL                                               THEN 'STSIN'
               WHEN i.isConversion = 1                                                   THEN 'CONVIN'
               WHEN i.ShipmentNo = 'CONVERSION'                                          THEN 'UNKC'   -- output, or an STS copy of one
               WHEN po.Status = 'DELIVERED' AND ISNULL(i.DateReceived, @Ancient) <= @OpeningDate THEN 'OPEN'
               WHEN po.Status IS NOT NULL                                                THEN 'PUR'
               WHEN ISNULL(LTRIM(RTRIM(i.ShipmentNo)), '') IN ('', '00000')              THEN 'INVIN'
               WHEN ISNULL(i.DateReceived, @Ancient) <= @OpeningDate                     THEN 'OPEN'
               ELSE 'UNK'
           END
    FROM dbo.Inventory AS i
    LEFT JOIN #BtBarcode  AS bt ON bt.Barcode = LTRIM(RTRIM(i.Barcode)) AND bt.Branch = i.Branch
    LEFT JOIN #StsBarcode AS st ON st.Barcode = LTRIM(RTRIM(i.Barcode)) AND st.Branch = i.Branch
    OUTER APPLY (SELECT TOP (1) p.Status
                 FROM dbo.POSUMMARY AS p
                 WHERE p.ShipmentNo = i.ShipmentNo AND p.BranchCode = i.Branch
                 ORDER BY p.Status) AS po
    WHERE (@br IS NULL OR i.Branch = @br);

    -- an STS receipt written without the line barcode is a copy of an earlier lot of another branch
    -- (also when that lot was a conversion output: the receipt copies ShipmentNo CONVERSION, isConversion 0)
    UPDATE l
    SET l.Kind = CASE WHEN EXISTS (SELECT 1
                                   FROM dbo.Inventory AS s
                                   WHERE s.ShipmentNo = l.ShipmentNo
                                     AND ISNULL(s.ReferenceCode, '') = l.ItemCode
                                     AND s.Branch <> l.Branch
                                     AND s.SequenceNumber < l.Seq)
                      THEN 'STSIN' WHEN l.Kind = 'UNKC' THEN 'CONVIN' ELSE 'INVIN' END
    FROM #Lot AS l
    WHERE l.Kind IN ('UNK', 'UNKC');

    UPDATE #Lot SET EffDate = CASE WHEN Kind = 'OPEN' AND DateReceived <= @dateto THEN @Ancient ELSE DateReceived END;

    -- 2. Movements: one row per IN / OUT, signed by its column (OUT columns hold positive quantities) ------
    CREATE TABLE #Mv
    (
        Seq INT           NOT NULL,
        Col VARCHAR(8)    NOT NULL,
        Dt  DATE          NOT NULL,
        Qty DECIMAL(18,3) NOT NULL,
        Amt DECIMAL(19,2) NOT NULL
    );

    -- the lot itself (an opening load is "already there" in any period that ends on or after its date)
    INSERT INTO #Mv (Seq, Col, Dt, Qty, Amt)
    SELECT l.Seq, l.Kind, l.EffDate, l.Qty, 0
    FROM #Lot AS l;

    -- sales and STS out, every row on its own date (cancelled / returned ones included)
    INSERT INTO #Mv (Seq, Col, Dt, Qty, Amt)
    SELECT a.SequenceReferenceNumber,
           CASE WHEN t.PONumber IS NULL THEN 'SOLD' ELSE 'STSOUT' END,
           CASE WHEN a.DateProcessed < l.DateReceived THEN l.EffDate ELSE a.DateProcessed END,
           CAST(ISNULL(a.QtyDelivered, 0) AS DECIMAL(18,3)),
           CASE WHEN t.PONumber IS NULL THEN ISNULL(a.TotalAmount, 0) ELSE 0 END
    FROM dbo.InventoryDeliveryFIFO AS a
    INNER JOIN #Lot AS l ON l.Seq = a.SequenceReferenceNumber
    OUTER APPLY (SELECT TOP (1) s.PONumber FROM dbo.TransferOrderSummary AS s WHERE s.PONumber = a.PONumber) AS t
    WHERE a.DateProcessed IS NOT NULL;

    -- ... and back on the day they were cancelled / returned: Sales Return, or a negative STS Out
    INSERT INTO #Mv (Seq, Col, Dt, Qty, Amt)
    SELECT a.SequenceReferenceNumber,
           CASE WHEN t.PONumber IS NULL THEN 'SRET' ELSE 'STSOUT' END,
           CASE WHEN r.Dt IS NULL OR r.Dt < a.DateProcessed OR r.Dt < l.DateReceived
                THEN CASE WHEN a.DateProcessed < l.DateReceived THEN l.EffDate ELSE a.DateProcessed END
                ELSE r.Dt END,
           CASE WHEN t.PONumber IS NULL THEN 1 ELSE -1 END * CAST(ISNULL(a.QtyDelivered, 0) AS DECIMAL(18,3)),
           CASE WHEN t.PONumber IS NULL THEN ISNULL(a.TotalAmount, 0) ELSE 0 END
    FROM dbo.InventoryDeliveryFIFO AS a
    INNER JOIN #Lot AS l ON l.Seq = a.SequenceReferenceNumber
    OUTER APPLY (SELECT TOP (1) s.PONumber FROM dbo.TransferOrderSummary AS s WHERE s.PONumber = a.PONumber) AS t
    OUTER APPLY (SELECT COALESCE(
                     (SELECT MAX(CAST(g.CreatedAt AS DATE)) FROM dbo.SalesReturnLog AS g
                      WHERE g.PONumber = a.PONumber AND g.ReturnSeqNo = a.DevDetSeqNo),
                     (SELECT MAX(o.DateProcessed) FROM dbo.ReturnedOrderDetails AS o
                      WHERE o.PONumber = a.PONumber AND o.SeqNo = a.DevDetSeqNo),
                     (SELECT MIN(CAST(il.DateProcessed AS DATE)) FROM dbo.InventoryLedger AS il   -- the cancel's own stock-ledger row (since 09-09)
                      WHERE il.SequenceRefNum = a.SequenceReferenceNumber AND il.QtyIN > 0
                        AND il.Remarks LIKE '%CANCEL ITEM PO#' + a.PONumber
                        AND il.DateProcessed >= a.DateProcessed),
                     (SELECT MAX(CAST(d.DateTimeUpdated AS DATE)) FROM dbo.DeliveryDetails AS d
                      WHERE d.DeliveryNo = a.DeliveryNo AND d.SeqNo = a.DevDetSeqNo)) AS Dt) AS r
    WHERE a.isErrorCorrect = 1
      AND a.DateProcessed IS NOT NULL;

    -- conversion out, old module (a reversed conversion is left out on both sides). A row dated before its lot
    -- was received is a pre-go-live test row pointing at a reused sequence number (PRODUCTION: the 08-23 / 08-24
    -- rows; the lots' Available never moved): left out.
    INSERT INTO #Mv (Seq, Col, Dt, Qty, Amt)
    SELECT f.SequenceReferenceNumber, 'CONVOUT', f.DateProcessed, CAST(ISNULL(f.Qty, 0) AS DECIMAL(18,3)), 0
    FROM dbo.ConversionFIFO AS f
    INNER JOIN #Lot AS l ON l.Seq = f.SequenceReferenceNumber AND l.Branch = f.BranchCode
    WHERE f.DateProcessed >= l.DateReceived
      AND NOT EXISTS (SELECT 1 FROM dbo.ConversionSummary AS s
                      WHERE s.ConID = f.ConID AND s.BranchCode = f.BranchCode AND s.isErrorCorrect = 1);

    -- conversion per barcode: source out on the conversion date, back (negative) on the reversal date
    INSERT INTO #Mv (Seq, Col, Dt, Qty, Amt)
    SELECT d.InventorySeqNo, 'CONVOUT',
           CASE WHEN CAST(s.DateConverted AS DATE) < l.DateReceived THEN l.EffDate ELSE CAST(s.DateConverted AS DATE) END,
           ISNULL(d.Qty, 0), 0
    FROM dbo.ConversionBarcodeSourceDetails AS d
    INNER JOIN dbo.ConversionBarcodeSummary AS s ON s.ConversionRefNo = d.ConversionRefNo
    INNER JOIN #Lot AS l ON l.Seq = d.InventorySeqNo
    WHERE s.DateConverted IS NOT NULL
    UNION ALL
    SELECT d.InventorySeqNo, 'CONVOUT', CAST(s.DateReversed AS DATE), -ISNULL(d.Qty, 0), 0
    FROM dbo.ConversionBarcodeSourceDetails AS d
    INNER JOIN dbo.ConversionBarcodeSummary AS s ON s.ConversionRefNo = d.ConversionRefNo
    INNER JOIN #Lot AS l ON l.Seq = d.InventorySeqNo
    WHERE s.Status LIKE 'REVERS%' AND s.DateReversed IS NOT NULL AND s.DateConverted IS NOT NULL
    UNION ALL
    -- its output lots leave again on the reversal date (the reversal sets their Available to 0)
    SELECT o.NewInventorySeqNo, 'CONVIN', CAST(s.DateReversed AS DATE), -l.Qty, 0
    FROM dbo.ConversionBarcodeOutputDetails AS o
    INNER JOIN dbo.ConversionBarcodeSummary AS s ON s.ConversionRefNo = o.ConversionRefNo
    INNER JOIN #Lot AS l ON l.Seq = o.NewInventorySeqNo
    WHERE s.Status LIKE 'REVERS%' AND s.DateReversed IS NOT NULL;

    -- branch transfer out (non-STS module); a cancelled row comes back negative on its update date. Rows dated
    -- before their lot are the pre-go-live tests of 08-04 / 08-05 (transfers 240-246): left out, as above.
    INSERT INTO #Mv (Seq, Col, Dt, Qty, Amt)
    SELECT b.SequenceReferenceNumber, 'BTOUT', CAST(b.DateAdded AS DATE), CAST(ISNULL(b.QtyDelivered, 0) AS DECIMAL(18,3)), 0
    FROM dbo.InventoryBranchTransferFIFO AS b
    INNER JOIN #Lot AS l ON l.Seq = b.SequenceReferenceNumber
    WHERE CAST(b.DateAdded AS DATE) >= l.DateReceived
    UNION ALL
    SELECT b.SequenceReferenceNumber, 'BTOUT',
           CAST(CASE WHEN b.DateUpdated IS NULL OR b.DateUpdated < b.DateAdded THEN b.DateAdded ELSE b.DateUpdated END AS DATE),
           -CAST(ISNULL(b.QtyDelivered, 0) AS DECIMAL(18,3)), 0
    FROM dbo.InventoryBranchTransferFIFO AS b
    INNER JOIN #Lot AS l ON l.Seq = b.SequenceReferenceNumber
    WHERE b.isErrorCorrect = 1
      AND CAST(b.DateAdded AS DATE) >= l.DateReceived;

    -- adjustment: stock out per barcode (negative; its reversal positive) and quantity DEDUCT (negative)
    INSERT INTO #Mv (Seq, Col, Dt, Qty, Amt)
    SELECT d.InventorySeqNo, 'ADJ',
           CASE WHEN CAST(s.DateAdded AS DATE) < l.DateReceived THEN l.EffDate ELSE CAST(s.DateAdded AS DATE) END,
           -ISNULL(d.Qty, 0), 0
    FROM dbo.StockOutBarcodeDetails AS d
    INNER JOIN dbo.StockOutBarcodeSummary AS s ON s.RefNo = d.RefNo
    INNER JOIN #Lot AS l ON l.Seq = d.InventorySeqNo
    WHERE s.DateAdded IS NOT NULL
    UNION ALL
    SELECT d.InventorySeqNo, 'ADJ', CAST(s.DateReversed AS DATE), ISNULL(d.Qty, 0), 0
    FROM dbo.StockOutBarcodeDetails AS d
    INNER JOIN dbo.StockOutBarcodeSummary AS s ON s.RefNo = d.RefNo
    INNER JOIN #Lot AS l ON l.Seq = d.InventorySeqNo
    WHERE s.Status LIKE 'REVERS%' AND s.DateReversed IS NOT NULL AND s.DateAdded IS NOT NULL
    UNION ALL
    SELECT CAST(f.SequenceReferenceNumber AS INT), 'ADJ',
           CASE WHEN f.DateAdded < l.DateReceived THEN l.EffDate ELSE f.DateAdded END,
           -CAST(ISNULL(f.QtyDeducted, 0) AS DECIMAL(18,3)), 0
    FROM dbo.InventoryAdjustmentFIFO AS f
    INNER JOIN #Lot AS l ON l.Seq = f.SequenceReferenceNumber
    WHERE f.DateAdded IS NOT NULL;

    -- 3. Per lot: Beginning (everything before the period) and each column inside it -----------------------
    CREATE TABLE #Per
    (
        Seq     INT           NOT NULL PRIMARY KEY,
        Beg     DECIMAL(18,3) NOT NULL, Pur    DECIMAL(18,3) NOT NULL, StsIn  DECIMAL(18,3) NOT NULL,
        BtIn    DECIMAL(18,3) NOT NULL, ConvIn DECIMAL(18,3) NOT NULL, InvIn  DECIMAL(18,3) NOT NULL,
        SRet    DECIMAL(18,3) NOT NULL, Sold   DECIMAL(18,3) NOT NULL, StsOut DECIMAL(18,3) NOT NULL,
        BtOut   DECIMAL(18,3) NOT NULL, ConvOut DECIMAL(18,3) NOT NULL, Adj   DECIMAL(18,3) NOT NULL,
        SoldAmt DECIMAL(19,2) NOT NULL, SRetAmt DECIMAL(19,2) NOT NULL
    );
    INSERT INTO #Per (Seq, Beg, Pur, StsIn, BtIn, ConvIn, InvIn, SRet, Sold, StsOut, BtOut, ConvOut, Adj, SoldAmt, SRetAmt)
    SELECT m.Seq,
           SUM(CASE WHEN m.Dt < @datefrom
                    THEN CASE WHEN m.Col IN ('SOLD', 'STSOUT', 'BTOUT', 'CONVOUT') THEN -m.Qty ELSE m.Qty END
                    ELSE 0 END),
           SUM(CASE WHEN m.Dt >= @datefrom AND m.Col = 'PUR'     THEN m.Qty ELSE 0 END),
           SUM(CASE WHEN m.Dt >= @datefrom AND m.Col = 'STSIN'   THEN m.Qty ELSE 0 END),
           SUM(CASE WHEN m.Dt >= @datefrom AND m.Col = 'BTIN'    THEN m.Qty ELSE 0 END),
           SUM(CASE WHEN m.Dt >= @datefrom AND m.Col = 'CONVIN'  THEN m.Qty ELSE 0 END),
           SUM(CASE WHEN m.Dt >= @datefrom AND m.Col IN ('INVIN', 'OPEN') THEN m.Qty ELSE 0 END),
           SUM(CASE WHEN m.Dt >= @datefrom AND m.Col = 'SRET'    THEN m.Qty ELSE 0 END),
           SUM(CASE WHEN m.Dt >= @datefrom AND m.Col = 'SOLD'    THEN m.Qty ELSE 0 END),
           SUM(CASE WHEN m.Dt >= @datefrom AND m.Col = 'STSOUT'  THEN m.Qty ELSE 0 END),
           SUM(CASE WHEN m.Dt >= @datefrom AND m.Col = 'BTOUT'   THEN m.Qty ELSE 0 END),
           SUM(CASE WHEN m.Dt >= @datefrom AND m.Col = 'CONVOUT' THEN m.Qty ELSE 0 END),
           SUM(CASE WHEN m.Dt >= @datefrom AND m.Col = 'ADJ'     THEN m.Qty ELSE 0 END),
           SUM(CASE WHEN m.Dt >= @datefrom AND m.Col = 'SOLD'    THEN m.Amt ELSE 0 END),
           SUM(CASE WHEN m.Dt >= @datefrom AND m.Col = 'SRET'    THEN m.Amt ELSE 0 END)
    FROM #Mv AS m
    WHERE m.Dt < @dtx
    GROUP BY m.Seq;

    -- 4. Per branch + item code + product -----------------------------------------------------------------
    ;WITH g AS (
        SELECT l.Branch, l.ItemCode, l.Product,
               SUM(p.Beg) AS Beg, SUM(p.Pur) AS Pur, SUM(p.StsIn) AS StsIn, SUM(p.BtIn) AS BtIn,
               SUM(p.ConvIn) AS ConvIn, SUM(p.InvIn) AS InvIn, SUM(p.SRet) AS SRet,
               SUM(p.Sold) AS Sold, SUM(p.StsOut) AS StsOut, SUM(p.BtOut) AS BtOut, SUM(p.ConvOut) AS ConvOut,
               SUM(p.Adj) AS Adj,
               SUM(p.Beg + p.Pur + p.StsIn + p.BtIn + p.ConvIn + p.InvIn + p.SRet
                   - p.Sold - p.StsOut - p.BtOut - p.ConvOut + p.Adj) AS OnHand,
               SUM(ROUND((p.Beg + p.Pur + p.StsIn + p.BtIn + p.ConvIn + p.InvIn + p.SRet
                          - p.Sold - p.StsOut - p.BtOut - p.ConvOut + p.Adj) * l.Cost, 2)) AS ItemValue,
               SUM(ROUND((p.Sold - p.SRet) * l.Cost, 2)) AS CostOfSales,
               SUM(p.SoldAmt - p.SRetAmt) AS Sales,
               SUM(l.Qty * l.Cost) AS LotValue,
               SUM(l.Qty) AS LotQty
        FROM #Per AS p
        INNER JOIN #Lot AS l ON l.Seq = p.Seq
        GROUP BY l.Branch, l.ItemCode, l.Product
    )
    SELECT g.Branch AS BranchCode,
           b.BranchName,
           NULLIF(g.ItemCode, '') AS ItemCode,
           g.Product AS ProductCode,
           COALESCE(P.Description, P888.Description) AS Description,
           C.Description AS Category,
           CAST(g.Beg     AS DECIMAL(18,3)) AS BeginningQty,
           CAST(g.Pur     AS DECIMAL(18,3)) AS UnitPurchased,
           CAST(g.StsIn   AS DECIMAL(18,3)) AS STSIn,
           CAST(g.BtIn    AS DECIMAL(18,3)) AS BranchTransferIn,
           CAST(g.ConvIn  AS DECIMAL(18,3)) AS ConversionIn,
           CAST(g.InvIn   AS DECIMAL(18,3)) AS InventoryIn,
           CAST(g.SRet    AS DECIMAL(18,3)) AS SalesReturn,
           CAST(g.Sold    AS DECIMAL(18,3)) AS UnitSold,
           CAST(g.StsOut  AS DECIMAL(18,3)) AS STSOut,
           CAST(g.BtOut   AS DECIMAL(18,3)) AS BranchTransferOut,
           CAST(g.ConvOut AS DECIMAL(18,3)) AS ConversionOut,
           CAST(g.Adj     AS DECIMAL(18,3)) AS Adjustment,
           CAST(g.OnHand  AS DECIMAL(18,3)) AS QtyOnHand,
           CAST(CASE WHEN g.OnHand <> 0 THEN g.ItemValue / g.OnHand
                     WHEN g.LotQty <> 0 THEN g.LotValue / g.LotQty
                     ELSE 0 END AS DECIMAL(18,2)) AS UnitCost,
           CAST(g.ItemValue   AS DECIMAL(19,2)) AS ItemValue,
           CAST(g.Sales       AS DECIMAL(19,2)) AS Sales,
           CAST(g.CostOfSales AS DECIMAL(19,2)) AS Cost
    FROM g
    LEFT JOIN dbo.Branches AS b ON b.BranchCode = g.Branch
    LEFT JOIN dbo.Products AS P ON P.BranchCode = g.Branch AND P.ProductCode = g.Product
    LEFT JOIN dbo.Products AS P888 ON P888.BranchCode = '888' AND P888.ProductCode = g.Product
    LEFT JOIN dbo.ProductCategory AS C ON C.ProductCategoryID = COALESCE(P.ProductCategoryCode, P888.ProductCategoryCode)
    WHERE g.Beg <> 0 OR g.Pur <> 0 OR g.StsIn <> 0 OR g.BtIn <> 0 OR g.ConvIn <> 0 OR g.InvIn <> 0 OR g.SRet <> 0
       OR g.Sold <> 0 OR g.StsOut <> 0 OR g.BtOut <> 0 OR g.ConvOut <> 0 OR g.Adj <> 0 OR g.OnHand <> 0
    ORDER BY g.Branch, COALESCE(P.Description, P888.Description), g.ItemCode;
    -- BODY-END
END
GO

------------------------------------------------------------------
-- 3. Post-check, then commit
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF OBJECT_ID('dbo.spr_InventoryUnitActivity', 'P') IS NULL
    SET @msg = N'spr_InventoryUnitActivity was not created';
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.spr_InventoryUnitActivity')) NOT LIKE '%[[]102]%'
    SET @msg = N'spr_InventoryUnitActivity is not the [102] text';
ELSE IF OBJECT_ID('dbo.spr_InventoryUnitActivity_OLD_10172026150000', 'P') IS NULL
    SET @msg = N'the backup spr_InventoryUnitActivity_OLD_10172026150000 is missing';

IF @msg IS NULL
BEGIN
    -- smoke run: last month, every branch (the result is thrown away)
    DECLARE @sf DATE = DATEADD(MONTH, -1, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));
    DECLARE @st DATE = EOMONTH(@sf);
    CREATE TABLE #Smoke102 (BranchCode VARCHAR(10), BranchName VARCHAR(200), ItemCode VARCHAR(100), ProductCode VARCHAR(30),
        Description VARCHAR(500), Category VARCHAR(500), BeginningQty DECIMAL(18,3), UnitPurchased DECIMAL(18,3), STSIn DECIMAL(18,3),
        BranchTransferIn DECIMAL(18,3), ConversionIn DECIMAL(18,3), InventoryIn DECIMAL(18,3), SalesReturn DECIMAL(18,3),
        UnitSold DECIMAL(18,3), STSOut DECIMAL(18,3), BranchTransferOut DECIMAL(18,3), ConversionOut DECIMAL(18,3),
        Adjustment DECIMAL(18,3), QtyOnHand DECIMAL(18,3), UnitCost DECIMAL(18,2), ItemValue DECIMAL(19,2), Sales DECIMAL(19,2), Cost DECIMAL(19,2));
    INSERT INTO #Smoke102 EXEC dbo.spr_InventoryUnitActivity NULL, @sf, @st;
    DECLARE @smokeRows INT = (SELECT COUNT(*) FROM #Smoke102);
    PRINT '[102] smoke run ' + CONVERT(VARCHAR(10), @sf, 120) + '..' + CONVERT(VARCHAR(10), @st, 120) + ': ' + CAST(@smokeRows AS VARCHAR(10)) + ' rows.';
    DROP TABLE #Smoke102;
END

IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[102] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59897, @msg, 1;
END

COMMIT TRANSACTION;
PRINT '[102] committed: spr_InventoryUnitActivity rebuilt per lot (backup spr_InventoryUnitActivity_OLD_10172026150000).';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
