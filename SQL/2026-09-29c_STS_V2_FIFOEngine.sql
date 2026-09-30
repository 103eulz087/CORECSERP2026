/* ================================================================
   2026-09-29c: STS Stock Transfer V2 -- first module on the FIFO engine
   ================================================================
   Requires 2026-09-29b_InvFIFO_Engine.sql.
   Backs the NEW form Orders/AddBranchOrderSTSV2 (a copy of
   AddBranchOrderSTS, opened from ViewBranchOrderSTS > Process this Order >
   "FIFO V2 (Test)", admins only). The old form and its procs
   (sp_AddBranchOrder[_JFC], sp_AddBranchOrderByBarcode,
   sp_FiFoMappingSTS[_JFC], sp_SalesQtyToInventoryQtySTS[_JFC],
   sp_ReverseSTSInventoryTransfer, sp_CancelDelivery*) are NOT changed.

   Decisions (user, 2026-09-29):
     * Per-scan posting kept: each scan / pick is ONE atomic call and is
       saved as a PENDING line straight away (Save-as-Pending/resume and
       the Confirm step keep working).
     * Writes the SAME STS tables (DeliveryDetails, DeliverySummary,
       InventoryDeliveryFIFO) in the same shape, so sp_ConfirmBranchOrderSTS,
       branch receiving and the STS reports work unchanged. Deliberate
       exception to the "own tables per module" convention.
     * Returns use the new spu_ReverseSTSLineV2 (restores exactly the lots
       the line took).
     * One proc serves JFC and non-JFC: JFC picks a batch (BATCH mode:
       Product + ShipmentNo + ReferenceCode), non-JFC picks any warehouse
       lot (AUTO mode). Scanned barcodes are LOT mode, partial qty allowed.

   What this fixes vs the old STS chain (see the standard doc, section 3):
     A1 silent short delivery (loop BREAK)     -> engine THROWs 59804
     A2 unlocked pre-check race                -> check under UPDLOCK
     A3 check/pop filter mismatch              -> fn_InvEligibleLots only
     A4 BOM checked on the parent              -> children expanded first
     A5 ReferenceCode overwritten 'stsfifo'    -> engine never touches it
     A6 JFC shipment scope by ShipmentNo alone -> BATCH = Product+Ship+Ref
     A7 IsStock never cleared                  -> engine maintains it
     A9 errors collapsed to 50000              -> THROW with 598xx numbers
     A10 zero qty accepted                     -> 59821
     A11 SeqNo from MAX()+1 under NOLOCK       -> applock + UPDLOCK, and
                                                   numbered past BOTH
                                                   DeliveryDetails.SeqNo and
                                                   InventoryDeliveryFIFO.DevDetSeqNo
     + one-lot-only return (sp_CancelDeliveryFIFOJFC) and full-Quantity
       reset on barcode return (sp_CancelDeliveryByBarcode)
                                               -> spu_ReverseSTSLineV2

   Row shapes mirror the old procs:
     * InventoryDeliveryFIFO.BranchCode = DESTINATION branch (Confirm
       filters on it for the GL legs); isVat = the source lot's IsVat
       (old JFC path hard-coded 0; every lot on COREX001 is IsVat = 0
       today, so the Confirm GL split is unchanged); SellingPrice =
       destination Products.SellingPrice (as sp_SalesQtyToInventoryQtySTS_JFC).
     * DeliveryDetails.SellingPrice: SCAN = origin Products.SellingPrice
       (as sp_AddBranchOrderByBarcode); AUTO/BATCH = customer special price
       when destination = origin, else 0 (as sp_AddBranchOrder_JFC).
     * DeliveryDetails.Cost = cost per unit of what was taken; Confirm
       recomputes it from InventoryDeliveryFIFO anyway.
     * InventoryLedger remarks: 'STS IN-TRANSIT PO#-<po>' out,
       'STS CANCEL ITEM PO#<po>' back (same texts as before).

   Error numbers 59820-59839.
   Deploy to COREX001 (DEV) first; STAGING only after the user confirms.
   ================================================================ */

-- ----------------------------------------------------------------
-- funcview_STSV2_Products -- FIFO Auto dropdown (one row per product)
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.funcview_STSV2_Products', 'IF') IS NOT NULL
    EXEC sp_rename 'dbo.funcview_STSV2_Products', 'funcview_STSV2_Products_OLD_09292026110000';
GO

CREATE FUNCTION dbo.funcview_STSV2_Products (@OriginBranch VARCHAR(5), @PONumber VARCHAR(10))
RETURNS TABLE
AS
/*
    Products requested on the transfer that can be picked FIFO Auto:
    those with eligible stock at the origin, plus combo (InventoryMapping)
    parents, whose availability is checked on their components at post.
    ValueMember = ProductCode, DisplayMember = DisplayText (Code - Name).
*/
RETURN
    SELECT
        t.ProductCode,
        ISNULL(p.Description, t.ProductName)                               AS Description,
        t.ProductCode + ' - ' + ISNULL(p.Description, t.ProductName)       AS DisplayText,
        CAST(ISNULL(a.Available, 0) AS DECIMAL(18,3))                      AS Available,
        c.IsCombo
    FROM (SELECT ProductCode, MAX(ProductName) AS ProductName
          FROM dbo.TransferOrderDetails
          WHERE PONumber = @PONumber
          GROUP BY ProductCode) AS t
    LEFT JOIN dbo.Products AS p
           ON p.ProductCode = t.ProductCode AND p.BranchCode = @OriginBranch
    OUTER APPLY (SELECT SUM(e.Available) AS Available
                 FROM dbo.fn_InvEligibleLots(@OriginBranch) AS e
                 WHERE e.Product = t.ProductCode) AS a
    CROSS APPLY (SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM dbo.InventoryMapping AS m
                                                WHERE m.ParentProductCode = t.ProductCode)
                                  THEN 1 ELSE 0 END AS BIT) AS IsCombo) AS c
    WHERE ISNULL(a.Available, 0) > 0 OR c.IsCombo = 1;
GO

-- ----------------------------------------------------------------
-- funcview_STSV2_ProductLots -- FIFO Manual dropdown (one row per batch)
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.funcview_STSV2_ProductLots', 'IF') IS NOT NULL
    EXEC sp_rename 'dbo.funcview_STSV2_ProductLots', 'funcview_STSV2_ProductLots_OLD_09292026110000';
GO

CREATE FUNCTION dbo.funcview_STSV2_ProductLots (@OriginBranch VARCHAR(5), @PONumber VARCHAR(10))
RETURNS TABLE
AS
/*
    One row per batch (Product + ShipmentNo + ReferenceCode) of a requested
    product with eligible stock at the origin. ValueMember = LotKey
    'Product||ShipmentNo||ReferenceCode' (CLAUDE.md Known Bug Pattern #7).
    Replaces funcview_populateProductsInPOJFC for V2; that one has an
    AND/OR precedence bug (blank-shipment lots from ANY branch, even with
    no stock, appear) and is left untouched for the old form.
*/
RETURN
    SELECT
        e.Product + '||' + ISNULL(e.ShipmentNo, '') + '||' + ISNULL(e.ReferenceCode, '') AS LotKey,
        e.Product                                        AS ProductCode,
        MAX(e.Description)                               AS Description,
        e.Product + ' - ' + MAX(e.Description)           AS DisplayText,
        ISNULL(e.ShipmentNo, '')                         AS ShipmentNo,
        ISNULL(e.ReferenceCode, '')                      AS ReferenceCode,
        CAST(SUM(e.Available) AS DECIMAL(18,3))          AS Available,
        MIN(e.DateReceived)                              AS OldestReceived
    FROM dbo.fn_InvEligibleLots(@OriginBranch) AS e
    WHERE EXISTS (SELECT 1 FROM dbo.TransferOrderDetails AS t
                  WHERE t.PONumber = @PONumber AND t.ProductCode = e.Product)
    GROUP BY e.Product, ISNULL(e.ShipmentNo, ''), ISNULL(e.ReferenceCode, '');
GO

-- ----------------------------------------------------------------
-- funcview_STSV2_DeliveryLines -- the V2 form's "for delivery" grid
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.funcview_STSV2_DeliveryLines', 'IF') IS NOT NULL
    EXEC sp_rename 'dbo.funcview_STSV2_DeliveryLines', 'funcview_STSV2_DeliveryLines_OLD_09292026110000';
GO

CREATE FUNCTION dbo.funcview_STSV2_DeliveryLines (@DeliveryNo VARCHAR(20), @PONumber VARCHAR(10))
RETURNS TABLE
AS
/*
    One row per active DeliveryDetails line of this delivery (the unit a
    Return acts on), with how many lots it drew from. Scoped by DeliveryNo
    AND PONumber (funcview_ProcessOrderItemsSales joins on PONumber only).
*/
RETURN
    SELECT
        CAST(d.SeqNo AS INT)                           AS SeqNo,
        d.ProductNo,
        d.ProductName,
        d.BarcodeNo,
        CAST(d.QtyDelivered AS DECIMAL(18,3))          AS QtyDelivered,
        ISNULL(f.Lots, 0)                              AS Lots,
        CAST(ISNULL(f.TotalCost, 0) AS DECIMAL(18,2))  AS TotalCost,
        d.ProcessedBy,
        d.DateTimeAdded
    FROM dbo.DeliveryDetails AS d
    OUTER APPLY (SELECT COUNT(*) AS Lots, SUM(x.TotalCost) AS TotalCost
                 FROM dbo.InventoryDeliveryFIFO AS x
                 WHERE x.DeliveryNo = d.DeliveryNo AND x.PONumber = d.PONumber
                   AND x.DevDetSeqNo = d.SeqNo AND x.isErrorCorrect = 0) AS f
    WHERE d.DeliveryNo = @DeliveryNo
      AND d.PONumber   = @PONumber
      AND d.Status     = 'PENDING'
      AND ISNULL(d.isCancelled, 0) = 0
      AND ISNULL(d.isReturned, 0)  = 0;
GO

-- ----------------------------------------------------------------
-- spu_PostSTSLineV2 -- one scan / one pick = one atomic post
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.spu_PostSTSLineV2', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_PostSTSLineV2', 'spu_PostSTSLineV2_OLD_09292026110000';
GO

CREATE PROCEDURE dbo.spu_PostSTSLineV2
    @DeliveryNo        VARCHAR(20),
    @RefNo             VARCHAR(10),
    @PONumber          VARCHAR(10),
    @DestinationBranch VARCHAR(10),                -- initiating (receiving) branch
    @OriginBranch      VARCHAR(10),                -- branch the stock leaves (Login.assignedBranch)
    @PreparedBy        VARCHAR(30),
    @Method            VARCHAR(5),                 -- SCAN / AUTO / BATCH
    @Qty               DECIMAL(18,3),
    @ProductCode       VARCHAR(10)  = NULL,        -- AUTO / BATCH (SCAN takes it from the lot)
    @Barcode           VARCHAR(100) = NULL,        -- SCAN: the lot's barcode; AUTO/BATCH: the STS sticker barcode
    @ShipmentNo        VARCHAR(10)  = NULL,        -- BATCH
    @ReferenceCode     VARCHAR(100) = NULL         -- BATCH
AS
/*
    Returns one row: SeqNo, ProductCode, ProductName, QtyDelivered, TotalCost.
    Caller: Orders/AddBranchOrderSTSV2.cs.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        ------------------------------------------------------------------
        -- 1. Validate before any write
        ------------------------------------------------------------------
        SET @Method = UPPER(LTRIM(RTRIM(ISNULL(@Method, ''))));
        SET @ProductCode = NULLIF(LTRIM(RTRIM(@ProductCode)), '');
        SET @Barcode = NULLIF(LTRIM(RTRIM(@Barcode)), '');

        IF @Method NOT IN ('SCAN', 'AUTO', 'BATCH')
            THROW 59820, 'Invalid STS input method (expected SCAN, AUTO or BATCH).', 1;

        IF @Qty IS NULL OR @Qty <= 0
            THROW 59821, 'Quantity must be greater than zero.', 1;

        IF NULLIF(LTRIM(RTRIM(@DeliveryNo)), '') IS NULL OR NULLIF(LTRIM(RTRIM(@PONumber)), '') IS NULL
           OR NULLIF(LTRIM(RTRIM(@RefNo)), '') IS NULL
           OR NULLIF(LTRIM(RTRIM(@DestinationBranch)), '') IS NULL OR NULLIF(LTRIM(RTRIM(@OriginBranch)), '') IS NULL
            THROW 59822, 'Delivery No., Reference No., PO No., origin and destination branch are all required.', 1;

        -- InventoryDeliveryFIFO.DeliveryNo / PONumber are VARCHAR(7)
        IF LEN(@DeliveryNo) > 7 OR LEN(@PONumber) > 7
            THROW 59822, 'Delivery No. and PO No. must be at most 7 characters (InventoryDeliveryFIFO).', 1;

        DECLARE @msg NVARCHAR(2048);
        DECLARE @LotSeq INT, @LotDesc VARCHAR(300), @LotIsVat BIT;

        IF @Method = 'SCAN'
        BEGIN
            IF @Barcode IS NULL
                THROW 59823, 'Scan a barcode first.', 1;

            SELECT TOP (1)
                @LotSeq = e.SequenceNumber, @ProductCode = e.Product,
                @LotDesc = e.Description, @LotIsVat = e.IsVat
            FROM dbo.fn_InvEligibleLots(@OriginBranch) AS e
            WHERE e.Barcode = @Barcode
            ORDER BY e.SequenceNumber;

            IF @LotSeq IS NULL
            BEGIN
                SET @msg = N'No available warehouse stock for barcode ' + @Barcode + N' at branch ' + @OriginBranch + N'.';
                THROW 59824, @msg, 1;
            END
        END
        ELSE IF @ProductCode IS NULL
            THROW 59825, 'Select a product first.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.TransferOrderDetails WHERE PONumber = @PONumber AND ProductCode = @ProductCode)
        BEGIN
            SET @msg = N'Product ' + @ProductCode + N' is not in transfer request PO#' + @PONumber + N'.';
            THROW 59826, @msg, 1;
        END

        DECLARE @IsCombo BIT = CASE WHEN EXISTS (SELECT 1 FROM dbo.InventoryMapping WHERE ParentProductCode = @ProductCode)
                                    THEN 1 ELSE 0 END;
        IF @IsCombo = 1 AND @Method <> 'AUTO'
        BEGIN
            SET @msg = N'Product ' + @ProductCode + N' is a combo (mapped) item - pick it with FIFO Auto, not by barcode or shipment.';
            THROW 59827, @msg, 1;
        END

        DECLARE @ProductName VARCHAR(100), @ProdIsVat BIT, @ProdSellingPrice DECIMAL(18,2);
        SELECT @ProductName = Description, @ProdIsVat = isVat, @ProdSellingPrice = SellingPrice
        FROM dbo.Products
        WHERE ProductCode = @ProductCode AND BranchCode = @OriginBranch;

        -- Same guard as sp_AddBranchOrder_JFC (it also catches a product
        -- that isn't set up at the origin branch at all).
        IF @Method <> 'SCAN' AND @ProdIsVat IS NULL
        BEGIN
            SET @msg = N'Product ' + @ProductCode + N' has no VAT / non-VAT setting at branch ' + @OriginBranch + N' (Products.isVat).';
            THROW 59828, @msg, 1;
        END

        -- DeliveryDetails.SellingPrice, mirroring the old procs per method
        DECLARE @SellingPrice DECIMAL(18,2) = 0;
        IF @Method = 'SCAN'
            SET @SellingPrice = ISNULL(@ProdSellingPrice, 0);
        ELSE IF @DestinationBranch = @OriginBranch
        BEGIN
            SELECT @SellingPrice = c.SpecialPriceAmount
            FROM dbo.CustomerProductSetting AS c
            WHERE c.ProductCode = @ProductCode
              AND c.CustomerKey = (SELECT TOP (1) Customer FROM dbo.PurchaseOrderSummary WHERE PONumber = @PONumber);

            IF ISNULL(@SellingPrice, 0) = 0
                SET @SellingPrice = ISNULL(@ProdSellingPrice, 0);
        END

        ------------------------------------------------------------------
        -- 2. Engine request lines
        ------------------------------------------------------------------
        DECLARE @Lines dbo.tt_InvDeductLine;

        IF @Method = 'SCAN'
            INSERT INTO @Lines (LineID, ProductCode, Qty, Mode, InventorySeqNo)
            VALUES (1, @ProductCode, @Qty, 'LOT', @LotSeq);
        ELSE IF @Method = 'BATCH'
            INSERT INTO @Lines (LineID, ProductCode, Qty, Mode, ShipmentNo, ReferenceCode)
            VALUES (1, @ProductCode, @Qty, 'BATCH', ISNULL(@ShipmentNo, ''), ISNULL(@ReferenceCode, ''));
        ELSE
            INSERT INTO @Lines (LineID, ProductCode, Qty, Mode)
            SELECT ROW_NUMBER() OVER (ORDER BY b.ProductCode), b.ProductCode, b.Qty, 'AUTO'
            FROM dbo.fn_InvExpandBOM(@ProductCode, @Qty) AS b
            WHERE b.Qty > 0;

        DECLARE @EffectivityDate DATE =
            (SELECT TOP (1) EffectivityDate FROM dbo.TransferOrderSummary WHERE PONumber = @PONumber);
        SET @EffectivityDate = ISNULL(@EffectivityDate, CAST(GETDATE() AS DATE));

        DECLARE @LedgerRemarks VARCHAR(500) = 'STS IN-TRANSIT PO#-' + @PONumber;

        CREATE TABLE #InvAlloc (
            LineID         INT           NOT NULL,
            InventorySeqNo INT           NOT NULL,
            ProductCode    VARCHAR(10)   NOT NULL,
            Description    VARCHAR(300)  NULL,
            Barcode        VARCHAR(35)   NULL,
            ShipmentNo     VARCHAR(10)   NULL,
            ReferenceCode  VARCHAR(100)  NULL,
            Qty            DECIMAL(18,3) NOT NULL,
            Cost           DECIMAL(18,2) NOT NULL,
            IsVat          BIT           NOT NULL,
            BegQty         DECIMAL(18,3) NOT NULL,
            EndQty         DECIMAL(18,3) NOT NULL);

        BEGIN TRANSACTION;

        ------------------------------------------------------------------
        -- 3. Serialize line numbering per delivery (lock released at
        --    commit/rollback)
        ------------------------------------------------------------------
        DECLARE @LockRes NVARCHAR(255) = N'STSV2_' + @DeliveryNo + N'_' + @PONumber, @rc INT;
        EXEC @rc = sys.sp_getapplock @Resource = @LockRes, @LockMode = 'Exclusive',
                                     @LockOwner = 'Transaction', @LockTimeout = 10000;
        IF @rc < 0
            THROW 59829, 'Another user is adding to this delivery right now. Please try again.', 1;

        -- Past BOTH numbering schemes of the old form (FIFO lines use
        -- MAX(DevDetSeqNo)+1 from 0, barcode lines MAX(SeqNo)+1), so V2 and
        -- old-form lines can share one delivery without colliding.
        DECLARE @SeqNo INT;
        SELECT @SeqNo = ISNULL(MAX(x.s), 0) + 1
        FROM (SELECT MAX(CAST(d.SeqNo AS INT)) AS s
              FROM dbo.DeliveryDetails AS d WITH (UPDLOCK, HOLDLOCK)
              WHERE d.DeliveryNo = @DeliveryNo AND d.PONumber = @PONumber
              UNION ALL
              SELECT MAX(f.DevDetSeqNo)
              FROM dbo.InventoryDeliveryFIFO AS f WITH (UPDLOCK, HOLDLOCK)
              WHERE f.DeliveryNo = @DeliveryNo AND f.PONumber = @PONumber) AS x;

        ------------------------------------------------------------------
        -- 4. Deduct (locks, checks, deducts, ledger, IsStock -- or throws)
        ------------------------------------------------------------------
        EXEC dbo.spu_InvFIFO_Deduct
            @BranchCode        = @OriginBranch,
            @Lines             = @Lines,
            @DestinationBranch = @DestinationBranch,
            @LedgerRemarks     = @LedgerRemarks,
            @User              = @PreparedBy;

        DECLARE @TotalCost DECIMAL(18,2) = (SELECT SUM(Qty * Cost) FROM #InvAlloc);

        ------------------------------------------------------------------
        -- 5. STS rows, same shape as before
        ------------------------------------------------------------------
        INSERT INTO dbo.InventoryDeliveryFIFO
            (DeliveryNo, PONumber, BranchCode, ProductNo, Description,
             QtyDelivered, Cost, TotalCost, DateProcessed, DevDetSeqNo,
             SequenceReferenceNumber, isVat, isErrorCorrect, SellingPrice, TotalAmount)
        SELECT @DeliveryNo, @PONumber, @DestinationBranch, a.ProductCode, LEFT(a.Description, 50),
               a.Qty, a.Cost, a.Qty * a.Cost, GETDATE(), @SeqNo,
               a.InventorySeqNo, a.IsVat, 0, ISNULL(sp.SellingPrice, 0), a.Qty * ISNULL(sp.SellingPrice, 0)
        FROM #InvAlloc AS a
        OUTER APPLY (SELECT TOP (1) p.SellingPrice
                     FROM dbo.Products AS p
                     WHERE p.BranchCode = @DestinationBranch AND p.ProductCode = a.ProductCode) AS sp;

        INSERT INTO dbo.DeliveryDetails
            (SeqNo, DeliveryNo, PONumber, ReferenceNumber, ProductNo, BarcodeNo,
             ProductName, QtyDelivered, ActualQty, Variance, Cost, SellingPrice,
             Status, isVat, ProcessedBy, isSettled, isCreditMemo, isReturned, isCancelled,
             DateTimeAdded, DateTimeUpdated)
        VALUES
            (@SeqNo, @DeliveryNo, @PONumber, @RefNo, @ProductCode, @Barcode,
             LEFT(COALESCE(@ProductName, @LotDesc, @ProductCode), 100), @Qty, @Qty, 0,
             ROUND(ISNULL(@TotalCost, 0) / @Qty, 2), @SellingPrice,
             'PENDING', COALESCE(CASE WHEN @Method = 'SCAN' THEN @LotIsVat END, @ProdIsVat, 0),
             @PreparedBy, 0, 0, 0, 0,
             GETDATE(), '');

        IF NOT EXISTS (SELECT 1 FROM dbo.DeliverySummary WITH (UPDLOCK, HOLDLOCK)
                       WHERE DeliveryNo = @DeliveryNo AND PONumber = @PONumber)
        BEGIN
            INSERT INTO dbo.DeliverySummary
                (DeliveryNo, PONumber, ReferenceNumber, InvoiceNo, BranchCode,
                 TotalItem, TotalQtyDelivered, TotalActualQty, TotalVarianceVat, TotalVarianceVatExempt,
                 EffectivityDate, Status, DateAdded, PreparedBy, isSettled, isInvoiceUpdate)
            SELECT @DeliveryNo, @PONumber, @RefNo, @RefNo, @DestinationBranch,
                   COUNT(*), ISNULL(SUM(d.QtyDelivered), 0), 0, 0, 0,
                   @EffectivityDate, 'PENDING', GETDATE(), @PreparedBy, 0, 0
            FROM dbo.DeliveryDetails AS d
            WHERE d.DeliveryNo = @DeliveryNo AND d.PONumber = @PONumber
              AND ISNULL(d.isCancelled, 0) = 0 AND ISNULL(d.isReturned, 0) = 0;
        END
        ELSE
        BEGIN
            UPDATE s
            SET s.TotalItem         = t.TotalItem,
                s.TotalQtyDelivered = t.TotalQty
            FROM dbo.DeliverySummary AS s
            CROSS APPLY (SELECT COUNT(*) AS TotalItem, ISNULL(SUM(d.QtyDelivered), 0) AS TotalQty
                         FROM dbo.DeliveryDetails AS d
                         WHERE d.DeliveryNo = s.DeliveryNo AND d.PONumber = s.PONumber
                           AND ISNULL(d.isCancelled, 0) = 0 AND ISNULL(d.isReturned, 0) = 0) AS t
            WHERE s.DeliveryNo = @DeliveryNo AND s.PONumber = @PONumber;
        END

        COMMIT TRANSACTION;

        SELECT @SeqNo AS SeqNo,
               @ProductCode AS ProductCode,
               LEFT(COALESCE(@ProductName, @LotDesc, @ProductCode), 100) AS ProductName,
               @Qty AS QtyDelivered,
               ISNULL(@TotalCost, 0) AS TotalCost;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------
-- spu_ReverseSTSLineV2 -- return one delivery line
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.spu_ReverseSTSLineV2', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_ReverseSTSLineV2', 'spu_ReverseSTSLineV2_OLD_09292026110000';
GO

CREATE PROCEDURE dbo.spu_ReverseSTSLineV2
    @DeliveryNo   VARCHAR(20),
    @PONumber     VARCHAR(10),
    @SeqNo        INT,
    @OriginBranch VARCHAR(10),
    @PreparedBy   VARCHAR(30)
AS
/*
    Restores EXACTLY the lots and quantities the line took (every
    InventoryDeliveryFIFO row with DevDetSeqNo = @SeqNo that isn't
    corrected yet), marks them corrected, cancels the line, and -- when the
    transfer was already processed (TransferOrderSummary.isProcess = 1) --
    posts the same ITR-HO-VAT / ITR-HO-VATEX reversal tickets as
    sp_ReverseSTSInventoryTransfer. Works for lines posted by the old form
    too (all their FIFO rows are restored, not just one).
    Caller: Orders/AddBranchOrderSTSV2.cs (Cancel Line).
*/
BEGIN
    SET NOCOUNT ON;
    -- Same as sp_ReverseSTSInventoryTransfer: sp_PostCompoundTicket runs
    -- inside this transaction; rollback is handled in CATCH.
    SET XACT_ABORT OFF;

    BEGIN TRY
        DECLARE @msg NVARCHAR(2048);

        IF NOT EXISTS (SELECT 1 FROM dbo.DeliveryDetails
                       WHERE DeliveryNo = @DeliveryNo AND PONumber = @PONumber AND SeqNo = @SeqNo
                         AND ISNULL(isCancelled, 0) = 0 AND ISNULL(isReturned, 0) = 0)
            THROW 59830, 'This delivery line was not found, or it is already cancelled or returned.', 1;

        DECLARE @DestinationBranch VARCHAR(10) =
            (SELECT TOP (1) BranchCode FROM dbo.DeliverySummary WHERE DeliveryNo = @DeliveryNo AND PONumber = @PONumber);

        IF NULLIF(LTRIM(RTRIM(@DestinationBranch)), '') IS NULL
            THROW 59833, 'This delivery has no header (DeliverySummary) or no destination branch, so the line can''t be returned safely.', 1;

        BEGIN TRANSACTION;

        DECLARE @LockRes NVARCHAR(255) = N'STSV2_' + @DeliveryNo + N'_' + @PONumber, @rc INT;
        EXEC @rc = sys.sp_getapplock @Resource = @LockRes, @LockMode = 'Exclusive',
                                     @LockOwner = 'Transaction', @LockTimeout = 10000;
        IF @rc < 0
            THROW 59829, 'Another user is changing this delivery right now. Please try again.', 1;

        SELECT f.SequenceNumber          AS FifoID,
               f.SequenceReferenceNumber AS InventorySeqNo,
               CAST(f.QtyDelivered AS DECIMAL(18,3)) AS Qty,
               ISNULL(f.TotalCost, 0)    AS TotalCost,
               ISNULL(f.isVat, 0)        AS isVat
        INTO #Rows
        FROM dbo.InventoryDeliveryFIFO AS f WITH (UPDLOCK, HOLDLOCK)
        WHERE f.DeliveryNo = @DeliveryNo AND f.PONumber = @PONumber
          AND f.DevDetSeqNo = @SeqNo
          AND ISNULL(f.isErrorCorrect, 0) = 0
          AND f.BranchCode = @DestinationBranch;

        IF NOT EXISTS (SELECT 1 FROM #Rows)
            THROW 59831, 'This line has no un-returned FIFO rows, so there is no stock to restore.', 1;

        DECLARE @Restore dbo.tt_InvRestoreLot;
        INSERT INTO @Restore (InventorySeqNo, Qty)
        SELECT InventorySeqNo, Qty FROM #Rows WHERE Qty > 0;

        DECLARE @LedgerRemarks VARCHAR(500) = 'STS CANCEL ITEM PO#' + @PONumber;

        IF EXISTS (SELECT 1 FROM @Restore)
            EXEC dbo.spu_InvFIFO_Restore
                @BranchCode        = @OriginBranch,
                @Lots              = @Restore,
                @DestinationBranch = @DestinationBranch,
                @LedgerRemarks     = @LedgerRemarks,
                @User              = @PreparedBy;

        DECLARE @RowCount INT = (SELECT COUNT(*) FROM #Rows), @Marked INT;

        UPDATE f
        SET f.isErrorCorrect = 1
        FROM dbo.InventoryDeliveryFIFO AS f
        INNER JOIN #Rows AS r ON r.FifoID = f.SequenceNumber
        WHERE ISNULL(f.isErrorCorrect, 0) = 0;

        SET @Marked = @@ROWCOUNT;
        IF @Marked <> @RowCount
            THROW 59832, 'This line was changed by another user while returning it. Nothing was returned.', 1;

        UPDATE dbo.DeliveryDetails
        SET isCancelled = 1, DateTimeUpdated = GETDATE()
        WHERE DeliveryNo = @DeliveryNo AND PONumber = @PONumber AND SeqNo = @SeqNo
          AND ISNULL(isCancelled, 0) = 0 AND ISNULL(isReturned, 0) = 0;

        ------------------------------------------------------------------
        -- GL reversal -- same as sp_ReverseSTSInventoryTransfer
        ------------------------------------------------------------------
        DECLARE @wasProcessed BIT = (SELECT TOP (1) isProcess FROM dbo.TransferOrderSummary WHERE PONumber = @PONumber);

        IF ISNULL(@wasProcessed, 0) = 1
        BEGIN
            DECLARE @totalcostvat MONEY, @totalcostvatex MONEY, @effectivitydate DATE;
            SELECT @totalcostvat   = ISNULL(SUM(CASE WHEN isVat = 1 THEN TotalCost ELSE 0 END), 0),
                   @totalcostvatex = ISNULL(SUM(CASE WHEN isVat = 0 THEN TotalCost ELSE 0 END), 0)
            FROM #Rows;

            SELECT TOP (1) @effectivitydate = EffectivityDate FROM dbo.TransferOrderSummary WHERE PONumber = @PONumber;
            SET @effectivitydate = ISNULL(@effectivitydate, CAST(GETDATE() AS DATE));

            DECLARE @outrefnum VARCHAR(10), @Particulars VARCHAR(400);
            EXEC dbo.GetReferenceNumber @outrefnum OUTPUT;

            IF @totalcostvat > 0
            BEGIN
                DECLARE @AmtsVAT dbo.tt_AmountBreakdown, @TokVAT dbo.tt_TokenResolution, @FlgVAT dbo.tt_ConditionFlags;
                INSERT @AmtsVAT VALUES ('GROSS', @totalcostvat);
                SET @Particulars = 'Inventory Transfer RETURN - PO#' + @PONumber + ' (from Branch ' + ISNULL(@DestinationBranch, '') + ') - VATable';
                EXEC dbo.sp_PostCompoundTicket
                    @Mnemonic = 'ITR-HO-VAT', @TicketDate = @effectivitydate, @BranchCode = '888',
                    @ReferenceNumber = @outrefnum, @ReferenceKey = @PONumber, @Particulars = @Particulars,
                    @Owner = 'CS IN TRANSIT', @PreparedBy = @PreparedBy,
                    @Amounts = @AmtsVAT, @Tokens = @TokVAT, @Flags = @FlgVAT,
                    @LedgerType = NULL, @LedgerEntityID = NULL, @LedgerInvoiceNo = NULL,
                    @LedgerBatchRef = @PONumber, @LedgerSeqRef = 1;
            END

            IF @totalcostvatex > 0
            BEGIN
                DECLARE @AmtsVE dbo.tt_AmountBreakdown, @TokVE dbo.tt_TokenResolution, @FlgVE dbo.tt_ConditionFlags;
                INSERT @AmtsVE VALUES ('GROSS', @totalcostvatex);
                SET @Particulars = 'Inventory Transfer RETURN - PO#' + @PONumber + ' (from Branch ' + ISNULL(@DestinationBranch, '') + ') - VAT Exempt';
                EXEC dbo.sp_PostCompoundTicket
                    @Mnemonic = 'ITR-HO-VATEX', @TicketDate = @effectivitydate, @BranchCode = '888',
                    @ReferenceNumber = @outrefnum, @ReferenceKey = @PONumber, @Particulars = @Particulars,
                    @Owner = 'CS IN TRANSIT', @PreparedBy = @PreparedBy,
                    @Amounts = @AmtsVE, @Tokens = @TokVE, @Flags = @FlgVE,
                    @LedgerType = NULL, @LedgerEntityID = NULL, @LedgerInvoiceNo = NULL,
                    @LedgerBatchRef = @PONumber, @LedgerSeqRef = 2;
            END
        END

        ------------------------------------------------------------------
        -- Header totals + status (scoped to this delivery)
        ------------------------------------------------------------------
        UPDATE s
        SET s.TotalItem         = t.TotalItem,
            s.TotalQtyDelivered = t.TotalQty,
            s.TotalItemSold     = t.TotalItem,
            s.TotalItemReturned = t.Returned,
            s.Status            = CASE WHEN s.Status = 'FOR DELIVERY' THEN 'FOR DELIVERY' ELSE 'PENDING' END
        FROM dbo.DeliverySummary AS s
        CROSS APPLY (SELECT SUM(CASE WHEN ISNULL(d.isCancelled, 0) = 0 AND ISNULL(d.isReturned, 0) = 0 THEN 1 ELSE 0 END) AS TotalItem,
                            ISNULL(SUM(CASE WHEN ISNULL(d.isCancelled, 0) = 0 AND ISNULL(d.isReturned, 0) = 0 THEN d.QtyDelivered END), 0) AS TotalQty,
                            SUM(CASE WHEN ISNULL(d.isReturned, 0) = 1 THEN 1 ELSE 0 END) AS Returned
                     FROM dbo.DeliveryDetails AS d
                     WHERE d.DeliveryNo = s.DeliveryNo AND d.PONumber = s.PONumber) AS t
        WHERE s.DeliveryNo = @DeliveryNo AND s.PONumber = @PONumber
          AND s.Status <> 'RETURNED';

        COMMIT TRANSACTION;

        SELECT 1 AS Status, 'Line returned and stock restored.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
