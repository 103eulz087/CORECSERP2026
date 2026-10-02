/* ================================================================
   2026-10-02c: Process Sales Order V2 on the FIFO engine
   ================================================================
   Plan: docs/plans/2026-10-02_AddBranchOrderV2_Sales_Plan.md
   Needs: 2026-09-29b (engine), 2026-10-01 (SO lifecycle, 19), 2026-10-01e (23).

   User decisions (2026-10-02):
     D2 a line can't be cancelled once the invoice number is set (change the invoice first)
     D3 over / short: accept what the scan gives (no qty cap against the order)
     D4 SCAN is the default method on the form
     D5 the old form's scan procs take the order lock too
     JFC keeps every lot at IsWarehouse = 1, so the engine's rule fits both companies.

   New
     sp_SOOrder_Lock          per-order lock 'SOORDER:<PO>' (inside the caller's transaction)
     funcview_SOV2_Products / _ProductLots / _DeliveryLines   form lookups
     spu_PostSOLineV2         scan / pick one line (SCAN / AUTO / BATCH) through spu_InvFIFO_Deduct
     spu_ReverseSOLineV2      cancel one line through spu_InvFIFO_Restore
   Patched (exact one-line anchors, backups _OLD_10022026160000)
     sp_ConfirmBranchOrder    Save: runs in a transaction, takes the lock, refuses once invoiced / confirmed
     sp_ConfirmOrder, sp_CreditMemo, sp_ReturnSalesOrder, sp_CancelDeliveryFIFOJFC,
     sp_AddBranchOrderHRI_JFC, sp_AddBranchOrderHRI, sp_AddHRIOrderByBarcode   take the lock

   Same tables as the old form (DeliveryDetails / DeliverySummary /
   InventoryDeliveryFIFO), so Save, invoice number, Confirm, credit memo,
   return and the Exception Center work unchanged. No exe change for the
   patched procs; the new form needs the new exe.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.spu_InvFIFO_Deduct', 'P') IS NULL OR OBJECT_ID('dbo.spu_SO_PostInvoiceReduction', 'P') IS NULL
    THROW 59860, 'Run 2026-09-29b_InvFIFO_Engine.sql and 2026-10-01_SalesOrder_Lifecycle_Fixes.sql first.', 1;
IF OBJECT_ID('dbo.spu_PostSOLineV2', 'P') IS NOT NULL OR OBJECT_ID('dbo.sp_SOOrder_Lock', 'P') IS NOT NULL
    THROW 59861, 'Already applied (spu_PostSOLineV2 / sp_SOOrder_Lock exist).', 1;
GO

------------------------------------------------------------------
-- A. Per-order lock
------------------------------------------------------------------
CREATE PROCEDURE dbo.sp_SOOrder_Lock
    @PONumber VARCHAR(20)
AS
/*
    Takes the exclusive per-order lock 'SOORDER:<PO>' for the caller's
    transaction (released at its commit / rollback). Every Sales Order writer
    calls it first: V2 scan / cancel, the old scan procs, Save, Confirm,
    credit memo, return, cancel line. THROWs 59849 after 10 s.
*/
BEGIN
    SET NOCOUNT ON;
    IF @@TRANCOUNT = 0
        THROW 59848, 'sp_SOOrder_Lock must run inside a transaction.', 1;
    DECLARE @Res NVARCHAR(255) = N'SOORDER:' + LTRIM(RTRIM(ISNULL(@PONumber, ''))), @rc INT;
    EXEC @rc = sys.sp_getapplock @Resource = @Res, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
    IF @rc < 0
        THROW 59849, 'Another user is changing this sales order right now (scan, cancel, save, confirm, credit memo or return). Please try again.', 1;
END
GO

------------------------------------------------------------------
-- B. Lookups for the form
------------------------------------------------------------------
CREATE FUNCTION dbo.funcview_SOV2_Products (@OriginBranch VARCHAR(5), @PONumber VARCHAR(10))
RETURNS TABLE
AS
/*
    Products on the sales order that can be picked FIFO Auto: those with
    eligible stock at the origin (fn_InvEligibleLots: Available > 0 AND
    IsWarehouse = 1), plus combo parents (checked on their components at post).
    ValueMember = ProductCode, DisplayMember = DisplayText (Code - Name).
*/
RETURN
    SELECT
        o.ProductCode,
        ISNULL(p.Description, o.ProductName)                         AS Description,
        o.ProductCode + ' - ' + ISNULL(p.Description, o.ProductName) AS DisplayText,
        CAST(o.OrderedQty AS DECIMAL(18,3))                          AS OrderedQty,
        CAST(ISNULL(a.Available, 0) AS DECIMAL(18,3))                AS Available,
        c.IsCombo
    FROM (SELECT ProductCode, MAX(ProductName) AS ProductName, SUM(ISNULL(Qty, 0)) AS OrderedQty
          FROM dbo.PurchaseOrderDetails
          WHERE PONumber = @PONumber
          GROUP BY ProductCode) AS o
    LEFT JOIN dbo.Products AS p
           ON p.ProductCode = o.ProductCode AND p.BranchCode = @OriginBranch
    OUTER APPLY (SELECT SUM(e.Available) AS Available
                 FROM dbo.fn_InvEligibleLots(@OriginBranch) AS e
                 WHERE e.Product = o.ProductCode) AS a
    CROSS APPLY (SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM dbo.InventoryMapping AS m
                                                WHERE m.ParentProductCode = o.ProductCode)
                                  THEN 1 ELSE 0 END AS BIT) AS IsCombo) AS c
    WHERE ISNULL(a.Available, 0) > 0 OR c.IsCombo = 1;
GO

CREATE FUNCTION dbo.funcview_SOV2_ProductLots (@OriginBranch VARCHAR(5), @PONumber VARCHAR(10))
RETURNS TABLE
AS
/*
    One row per batch (Product + ShipmentNo + ReferenceCode) of an ordered
    product with eligible stock at the origin. ValueMember = LotKey
    'Product||ShipmentNo||ReferenceCode' (CLAUDE.md Known Bug Pattern #7).
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
    WHERE EXISTS (SELECT 1 FROM dbo.PurchaseOrderDetails AS o
                  WHERE o.PONumber = @PONumber AND o.ProductCode = e.Product)
    GROUP BY e.Product, ISNULL(e.ShipmentNo, ''), ISNULL(e.ReferenceCode, '');
GO

CREATE FUNCTION dbo.funcview_SOV2_DeliveryLines (@DeliveryNo VARCHAR(20), @PONumber VARCHAR(10))
RETURNS TABLE
AS
/*
    One row per active, unsaved (PENDING) line of this delivery -- the unit
    Cancel Line acts on -- with how many lots it drew from.
*/
RETURN
    SELECT
        CAST(d.SeqNo AS INT)                           AS SeqNo,
        d.ProductNo,
        d.ProductName,
        d.BarcodeNo,
        CAST(d.QtyDelivered AS DECIMAL(18,3))          AS QtyDelivered,
        CAST(d.SellingPrice AS DECIMAL(18,2))          AS SellingPrice,
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

------------------------------------------------------------------
-- C. Scan / pick one line
------------------------------------------------------------------
CREATE PROCEDURE dbo.spu_PostSOLineV2
    @DeliveryNo     VARCHAR(20),
    @RefNo          VARCHAR(10),
    @PONumber       VARCHAR(10),
    @CustomerBranch VARCHAR(10),                -- the order's branch (DeliverySummary.BranchCode)
    @OriginBranch   VARCHAR(10),                -- branch the stock leaves (Login.assignedBranch)
    @PreparedBy     VARCHAR(30),
    @Method         VARCHAR(5),                 -- SCAN / AUTO / BATCH
    @Qty            DECIMAL(18,3),
    @ProductCode    VARCHAR(10)  = NULL,        -- AUTO / BATCH (SCAN takes it from the lot)
    @Barcode        VARCHAR(100) = NULL,        -- SCAN: the lot's barcode; AUTO / BATCH: the sticker barcode
    @ShipmentNo     VARCHAR(10)  = NULL,        -- BATCH
    @ReferenceCode  VARCHAR(100) = NULL         -- BATCH
AS
/*
    One sales-order line from one scan / pick, in one transaction:
    order lock -> guards -> spu_InvFIFO_Deduct (eligible lots only, race-safe,
    stock-ledger row per lot 'SO OUT PO#<po>') -> InventoryDeliveryFIFO row per
    lot + DeliveryDetails line (weighted cost of its lots) + DeliverySummary.
    Over / short against the ordered qty is accepted (user rule D3).
    Returns one row: SeqNo, ProductCode, ProductName, QtyDelivered, TotalCost.
    Caller: Orders/AddBranchOrderV2.cs.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        SET @Method = UPPER(LTRIM(RTRIM(ISNULL(@Method, ''))));
        SET @ProductCode = NULLIF(LTRIM(RTRIM(@ProductCode)), '');
        SET @Barcode = NULLIF(LTRIM(RTRIM(@Barcode)), '');

        IF @Method NOT IN ('SCAN', 'AUTO', 'BATCH')
            THROW 59840, 'Invalid input method (expected SCAN, AUTO or BATCH).', 1;
        IF @Qty IS NULL OR @Qty <= 0
            THROW 59840, 'Quantity must be greater than zero.', 1;
        IF NULLIF(LTRIM(RTRIM(@DeliveryNo)), '') IS NULL OR NULLIF(LTRIM(RTRIM(@PONumber)), '') IS NULL
           OR NULLIF(LTRIM(RTRIM(@RefNo)), '') IS NULL
           OR NULLIF(LTRIM(RTRIM(@CustomerBranch)), '') IS NULL OR NULLIF(LTRIM(RTRIM(@OriginBranch)), '') IS NULL
            THROW 59840, 'Delivery No., Reference No., PO No., customer branch and origin branch are all required.', 1;
        IF LEN(@DeliveryNo) > 7 OR LEN(@PONumber) > 7
            THROW 59840, 'Delivery No. and PO No. must be at most 7 characters (InventoryDeliveryFIFO).', 1;

        DECLARE @msg NVARCHAR(2048);
        DECLARE @LotSeq INT, @LotDesc VARCHAR(300), @LotIsVat BIT;

        IF @Method = 'SCAN'
        BEGIN
            IF @Barcode IS NULL
                THROW 59845, 'Scan a barcode first.', 1;
            SELECT TOP (1) @LotSeq = e.SequenceNumber, @ProductCode = e.Product, @LotDesc = e.Description, @LotIsVat = e.IsVat
            FROM dbo.fn_InvEligibleLots(@OriginBranch) AS e
            WHERE e.Barcode = @Barcode
            ORDER BY e.SequenceNumber;
            IF @LotSeq IS NULL
            BEGIN
                SET @msg = N'No available warehouse stock for barcode ' + @Barcode + N' at branch ' + @OriginBranch + N'.';
                THROW 59845, @msg, 1;
            END
        END
        ELSE IF @ProductCode IS NULL
            THROW 59845, 'Select a product first.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.PurchaseOrderDetails WHERE PONumber = @PONumber AND ProductCode = @ProductCode)
        BEGIN
            SET @msg = N'Product ' + @ProductCode + N' is not on sales order PO#' + @PONumber + N'.';
            THROW 59846, @msg, 1;
        END

        IF @Method <> 'AUTO' AND EXISTS (SELECT 1 FROM dbo.InventoryMapping WHERE ParentProductCode = @ProductCode)
        BEGIN
            SET @msg = N'Product ' + @ProductCode + N' is a combo (mapped) item - pick it with FIFO Auto, not by barcode or shipment.';
            THROW 59846, @msg, 1;
        END

        DECLARE @ProductName VARCHAR(100), @ProdIsVat BIT, @ProdSellingPrice DECIMAL(18,2);
        SELECT @ProductName = Description, @ProdIsVat = isVat, @ProdSellingPrice = SellingPrice
        FROM dbo.Products
        WHERE ProductCode = @ProductCode AND BranchCode = @OriginBranch;

        IF @Method <> 'SCAN' AND @ProdIsVat IS NULL
        BEGIN
            SET @msg = N'Product ' + @ProductCode + N' is not set up at branch ' + @OriginBranch + N' (Products.isVat).';
            THROW 59846, @msg, 1;
        END

        -- the order line's price, as the old form (sp_AddBranchOrderHRI_JFC); the product price only as a fallback
        DECLARE @SellingPrice DECIMAL(18,2) =
            (SELECT TOP (1) o.SellingPrice FROM dbo.PurchaseOrderDetails AS o
             WHERE o.PONumber = @PONumber AND o.ProductCode = @ProductCode ORDER BY o.SeqNo);
        SET @SellingPrice = COALESCE(NULLIF(@SellingPrice, 0), @ProdSellingPrice, 0);

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
            (SELECT TOP (1) EffectivityDate FROM dbo.PurchaseOrderSummary WHERE PONumber = @PONumber);
        SET @EffectivityDate = ISNULL(@EffectivityDate, CAST(GETDATE() AS DATE));

        DECLARE @LedgerRemarks VARCHAR(500) = 'SO OUT PO#' + @PONumber;

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

        EXEC dbo.sp_SOOrder_Lock @PONumber = @PONumber;

        IF NOT EXISTS (SELECT 1 FROM dbo.PurchaseOrderSummary WHERE PONumber = @PONumber AND Status = 'APPROVED')
            THROW 59841, 'This sales order is not APPROVED (or was already confirmed); nothing can be added to it.', 1;

        IF EXISTS (SELECT 1 FROM dbo.DeliverySummary
                   WHERE PONumber = @PONumber AND (ISNULL(isInvoiceUpdate, 0) = 1 OR Status IN ('DELIVERED', 'RETURNED')))
            THROW 59843, 'This sales order already has its invoice number (or is confirmed); nothing can be added to it.', 1;

        IF EXISTS (SELECT 1 FROM dbo.PurchaseOrderSummary WHERE PONumber = @PONumber AND ISNULL(isProcess, 0) = 1)
            THROW 59842, 'This sales order has already been saved; lines can no longer be added. Cancel lines instead, or start a new order.', 1;

        DECLARE @OtherDelivery VARCHAR(20) =
            (SELECT TOP (1) x.DeliveryNo
             FROM (SELECT DeliveryNo FROM dbo.DeliverySummary WHERE PONumber = @PONumber
                   UNION ALL
                   SELECT DeliveryNo FROM dbo.DeliveryDetails
                   WHERE PONumber = @PONumber AND ISNULL(isCancelled, 0) = 0 AND ISNULL(isReturned, 0) = 0) AS x
             WHERE x.DeliveryNo <> @DeliveryNo
             ORDER BY x.DeliveryNo);
        IF @OtherDelivery IS NOT NULL
        BEGIN
            SET @msg = N'Sales order ' + @PONumber + N' already has delivery ' + @OtherDelivery + N'. Close this screen and open the order again.';
            THROW 59844, @msg, 1;
        END

        -- past both numbering schemes of the old form, so V2 and old lines can share a delivery
        DECLARE @SeqNo INT;
        SELECT @SeqNo = ISNULL(MAX(x.s), 0) + 1
        FROM (SELECT MAX(CAST(d.SeqNo AS INT)) AS s
              FROM dbo.DeliveryDetails AS d WITH (UPDLOCK, HOLDLOCK)
              WHERE d.DeliveryNo = @DeliveryNo AND d.PONumber = @PONumber
              UNION ALL
              SELECT MAX(f.DevDetSeqNo)
              FROM dbo.InventoryDeliveryFIFO AS f WITH (UPDLOCK, HOLDLOCK)
              WHERE f.DeliveryNo = @DeliveryNo AND f.PONumber = @PONumber) AS x;

        EXEC dbo.spu_InvFIFO_Deduct
            @BranchCode        = @OriginBranch,
            @Lines             = @Lines,
            @DestinationBranch = @CustomerBranch,
            @LedgerRemarks     = @LedgerRemarks,
            @User              = @PreparedBy;

        DECLARE @TotalCost DECIMAL(18,2) = (SELECT SUM(Qty * Cost) FROM #InvAlloc);

        INSERT INTO dbo.InventoryDeliveryFIFO
            (DeliveryNo, PONumber, BranchCode, ProductNo, Description,
             QtyDelivered, Cost, TotalCost, DateProcessed, DevDetSeqNo,
             SequenceReferenceNumber, isVat, isErrorCorrect, SellingPrice, TotalAmount)
        SELECT @DeliveryNo, @PONumber, @CustomerBranch, a.ProductCode, LEFT(a.Description, 50),
               a.Qty, a.Cost, a.Qty * a.Cost, GETDATE(), @SeqNo,
               a.InventorySeqNo, CAST(COALESCE(pv.isVat, a.IsVat, 0) AS BIT), 0, @SellingPrice, a.Qty * @SellingPrice
        FROM #InvAlloc AS a
        OUTER APPLY (SELECT TOP (1) p.isVat FROM dbo.Products AS p
                     WHERE p.BranchCode = @OriginBranch AND p.ProductCode = a.ProductCode) AS pv;

        INSERT INTO dbo.DeliveryDetails
            (SeqNo, DeliveryNo, PONumber, ReferenceNumber, ProductNo, BarcodeNo,
             ProductName, QtyDelivered, ActualQty, Variance, Cost, SellingPrice,
             Status, isVat, ProcessedBy, isSettled, isCreditMemo, isReturned, isCancelled,
             DateTimeAdded, DateTimeUpdated)
        VALUES
            (@SeqNo, @DeliveryNo, @PONumber, @RefNo, @ProductCode, @Barcode,
             LEFT(COALESCE(@ProductName, @LotDesc, @ProductCode), 100), @Qty, @Qty, 0,
             ROUND(ISNULL(@TotalCost, 0) / @Qty, 2), @SellingPrice,
             'PENDING', COALESCE(@ProdIsVat, @LotIsVat, 0),
             @PreparedBy, 0, 0, 0, 0,
             GETDATE(), '');

        IF NOT EXISTS (SELECT 1 FROM dbo.DeliverySummary WITH (UPDLOCK, HOLDLOCK)
                       WHERE DeliveryNo = @DeliveryNo AND PONumber = @PONumber)
            INSERT INTO dbo.DeliverySummary
                (DeliveryNo, PONumber, ReferenceNumber, InvoiceNo, BranchCode,
                 TotalItem, TotalQtyDelivered, TotalActualQty, TotalVarianceVat, TotalVarianceVatExempt,
                 EffectivityDate, Status, DateAdded, PreparedBy, isSettled, isInvoiceUpdate)
            SELECT @DeliveryNo, @PONumber, @RefNo, @RefNo, @CustomerBranch,
                   COUNT(*), ISNULL(SUM(d.QtyDelivered), 0), 0, 0, 0,
                   @EffectivityDate, 'PENDING', GETDATE(), @PreparedBy, 0, 0
            FROM dbo.DeliveryDetails AS d
            WHERE d.DeliveryNo = @DeliveryNo AND d.PONumber = @PONumber
              AND ISNULL(d.isCancelled, 0) = 0 AND ISNULL(d.isReturned, 0) = 0;
        ELSE
            UPDATE s
            SET s.TotalItem = t.TotalItem, s.TotalQtyDelivered = t.TotalQty
            FROM dbo.DeliverySummary AS s
            CROSS APPLY (SELECT COUNT(*) AS TotalItem, ISNULL(SUM(d.QtyDelivered), 0) AS TotalQty
                         FROM dbo.DeliveryDetails AS d
                         WHERE d.DeliveryNo = s.DeliveryNo AND d.PONumber = s.PONumber
                           AND ISNULL(d.isCancelled, 0) = 0 AND ISNULL(d.isReturned, 0) = 0) AS t
            WHERE s.DeliveryNo = @DeliveryNo AND s.PONumber = @PONumber;

        COMMIT TRANSACTION;

        SELECT @SeqNo AS SeqNo, @ProductCode AS ProductCode,
               LEFT(COALESCE(@ProductName, @LotDesc, @ProductCode), 100) AS ProductName,
               @Qty AS QtyDelivered, ISNULL(@TotalCost, 0) AS TotalCost;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

------------------------------------------------------------------
-- D. Cancel one line
------------------------------------------------------------------
CREATE PROCEDURE dbo.spu_ReverseSOLineV2
    @DeliveryNo   VARCHAR(20),
    @PONumber     VARCHAR(10),
    @SeqNo        INT,
    @OriginBranch VARCHAR(10),
    @PreparedBy   VARCHAR(30)
AS
/*
    Restores EXACTLY the lots and quantities the line took (every live
    InventoryDeliveryFIFO row of the line, stock-ledger 'SO CANCEL ITEM PO#'),
    marks them corrected and cancels the line. Refused once the invoice number
    is set or the order is confirmed (user rule D2: change the invoice first;
    after confirm use credit memo / return). Nothing is posted to the GL before
    Confirm, so there is nothing to reverse there.
    Caller: Orders/AddBranchOrderV2.cs (Cancel Line). Works on old-form lines too.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.DeliveryDetails
                       WHERE DeliveryNo = @DeliveryNo AND PONumber = @PONumber AND SeqNo = @SeqNo
                         AND ISNULL(isCancelled, 0) = 0 AND ISNULL(isReturned, 0) = 0)
            THROW 59850, 'This delivery line was not found, or it is already cancelled or returned.', 1;

        DECLARE @CustomerBranch VARCHAR(10) =
            (SELECT TOP (1) BranchCode FROM dbo.DeliverySummary WHERE DeliveryNo = @DeliveryNo AND PONumber = @PONumber);
        IF NULLIF(LTRIM(RTRIM(@CustomerBranch)), '') IS NULL
            THROW 59851, 'This delivery has no header (DeliverySummary) or no branch, so the line can''t be cancelled safely.', 1;

        BEGIN TRANSACTION;

        EXEC dbo.sp_SOOrder_Lock @PONumber = @PONumber;

        IF EXISTS (SELECT 1 FROM dbo.DeliverySummary
                   WHERE PONumber = @PONumber AND (ISNULL(isInvoiceUpdate, 0) = 1 OR Status IN ('DELIVERED', 'RETURNED')))
           OR EXISTS (SELECT 1 FROM dbo.PurchaseOrderSummary WHERE PONumber = @PONumber AND Status = 'DELIVERED')
            THROW 59852, 'This sales order already has its invoice number (or is confirmed). Change the invoice first, or use Credit Memo / Return after confirm.', 1;

        SELECT f.SequenceNumber AS FifoID, f.SequenceReferenceNumber AS InventorySeqNo,
               CAST(f.QtyDelivered AS DECIMAL(18,3)) AS Qty
        INTO #Rows
        FROM dbo.InventoryDeliveryFIFO AS f WITH (UPDLOCK, HOLDLOCK)
        WHERE f.DeliveryNo = @DeliveryNo AND f.PONumber = @PONumber
          AND f.DevDetSeqNo = @SeqNo AND ISNULL(f.isErrorCorrect, 0) = 0;

        IF NOT EXISTS (SELECT 1 FROM #Rows)
            THROW 59853, 'This line has no un-returned FIFO rows, so there is no stock to restore.', 1;

        DECLARE @Restore dbo.tt_InvRestoreLot;
        INSERT INTO @Restore (InventorySeqNo, Qty)
        SELECT InventorySeqNo, Qty FROM #Rows WHERE Qty > 0;

        DECLARE @LedgerRemarks VARCHAR(500) = 'SO CANCEL ITEM PO#' + @PONumber;
        IF EXISTS (SELECT 1 FROM @Restore)
            EXEC dbo.spu_InvFIFO_Restore
                @BranchCode = @OriginBranch, @Lots = @Restore, @DestinationBranch = @CustomerBranch,
                @LedgerRemarks = @LedgerRemarks, @User = @PreparedBy;

        DECLARE @RowCount INT = (SELECT COUNT(*) FROM #Rows);
        UPDATE f SET f.isErrorCorrect = 1
        FROM dbo.InventoryDeliveryFIFO AS f
        INNER JOIN #Rows AS r ON r.FifoID = f.SequenceNumber
        WHERE ISNULL(f.isErrorCorrect, 0) = 0;
        IF @@ROWCOUNT <> @RowCount
            THROW 59854, 'This line was changed by another user while cancelling it. Nothing was cancelled.', 1;

        UPDATE dbo.DeliveryDetails
        SET isCancelled = 1, DateTimeUpdated = GETDATE()
        WHERE DeliveryNo = @DeliveryNo AND PONumber = @PONumber AND SeqNo = @SeqNo
          AND ISNULL(isCancelled, 0) = 0 AND ISNULL(isReturned, 0) = 0;

        UPDATE s
        SET s.TotalItem = t.TotalItem, s.TotalQtyDelivered = t.TotalQty
        FROM dbo.DeliverySummary AS s
        CROSS APPLY (SELECT SUM(CASE WHEN ISNULL(d.isCancelled, 0) = 0 AND ISNULL(d.isReturned, 0) = 0 THEN 1 ELSE 0 END) AS TotalItem,
                            ISNULL(SUM(CASE WHEN ISNULL(d.isCancelled, 0) = 0 AND ISNULL(d.isReturned, 0) = 0 THEN d.QtyDelivered END), 0) AS TotalQty
                     FROM dbo.DeliveryDetails AS d
                     WHERE d.DeliveryNo = s.DeliveryNo AND d.PONumber = s.PONumber) AS t
        WHERE s.DeliveryNo = @DeliveryNo AND s.PONumber = @PONumber;

        COMMIT TRANSACTION;

        SELECT 1 AS Status, 'Line cancelled and stock restored.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

------------------------------------------------------------------
-- E. Every other Sales Order writer takes the same lock
------------------------------------------------------------------
IF OBJECT_ID('tempdb..#P') IS NOT NULL DROP TABLE #P;
CREATE TABLE #P (Id INT IDENTITY PRIMARY KEY, ProcName SYSNAME, OldText NVARCHAR(MAX), NewText NVARCHAR(MAX));
DECLARE @L NVARCHAR(200) = N'EXEC dbo.sp_SOOrder_Lock @PONumber = @parmpono;   -- 2026-10-02c: the per-order lock every Sales Order writer shares';

INSERT #P (ProcName, OldText, NewText) VALUES
('sp_ConfirmOrder',          N'        BEGIN TRAN;',        N'        BEGIN TRAN;' + NCHAR(10) + N'        ' + @L),
('sp_CreditMemo',            N'        BEGIN TRAN;',        N'        BEGIN TRAN;' + NCHAR(10) + N'        ' + @L),
('sp_ReturnSalesOrder',      N'        BEGIN TRANSACTION;', N'        BEGIN TRANSACTION;' + NCHAR(10) + N'        ' + @L),
('sp_AddBranchOrderHRI_JFC', NCHAR(9) + NCHAR(9) + N'BEGIN TRAN;', NCHAR(9) + NCHAR(9) + N'BEGIN TRAN;' + NCHAR(10) + NCHAR(9) + NCHAR(9) + @L),
('sp_AddBranchOrderHRI',     NCHAR(9) + NCHAR(9) + N'BEGIN TRAN;', NCHAR(9) + NCHAR(9) + N'BEGIN TRAN;' + NCHAR(10) + NCHAR(9) + NCHAR(9) + @L),
('sp_AddHRIOrderByBarcode',  N'        BEGIN TRAN;',        N'        BEGIN TRAN;' + NCHAR(10) + N'        ' + @L),
('sp_CancelDeliveryFIFOJFC', N'IF @TranCounter > 0 SAVE TRANSACTION CancelDeliverySave; ELSE BEGIN TRANSACTION;',
                             N'IF @TranCounter > 0 SAVE TRANSACTION CancelDeliverySave; ELSE BEGIN TRANSACTION;' + NCHAR(10) + N'    ' + @L),
-- Save had no transaction: now one, with the lock and the "already invoiced / confirmed" refusal (D2)
('sp_ConfirmBranchOrder',    N'BEGIN' + NCHAR(10) + N'SET XACT_ABORT ON',
                             N'BEGIN' + NCHAR(10) + N'SET XACT_ABORT ON' + NCHAR(10)
                             + N'	BEGIN TRANSACTION;   -- 2026-10-02c: Save runs as one unit (XACT_ABORT rolls it back on any error)' + NCHAR(10)
                             + N'	' + @L + NCHAR(10)
                             + N'	IF EXISTS (SELECT 1 FROM dbo.DeliverySummary WHERE PONumber = @parmpono AND (ISNULL(isInvoiceUpdate, 0) = 1 OR Status IN (''DELIVERED'', ''RETURNED'')))' + NCHAR(10)
                             + N'		THROW 59847, ''This sales order already has its invoice number (or is confirmed); it can''''t be saved again.'', 1;'),
('sp_ConfirmBranchOrder',    N'insert into HistoryLogs values (@preparedby,GETDATE(),''Commissary Process Order with PONumber=''+@parmpono,@parmbranchcode)',
                             N'insert into HistoryLogs values (@preparedby,GETDATE(),''Commissary Process Order with PONumber=''+@parmpono,@parmbranchcode)' + NCHAR(10)
                             + N'	COMMIT TRANSACTION;   -- 2026-10-02c');

IF OBJECT_ID('tempdb..#Def') IS NOT NULL DROP TABLE #Def;
SELECT DISTINCT p.ProcName, REPLACE(OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + p.ProcName)), NCHAR(13) + NCHAR(10), NCHAR(10)) AS Def
INTO #Def FROM #P AS p;

IF EXISTS (SELECT 1 FROM #Def WHERE Def IS NULL)
    THROW 59862, 'A procedure to patch is missing.', 1;
IF EXISTS (SELECT 1 FROM #Def WHERE CHARINDEX(N'2026-10-02c', Def) > 0)
    THROW 59863, 'Already applied (a procedure carries the 2026-10-02c note).', 1;
IF EXISTS (SELECT 1 FROM #P AS p INNER JOIN #Def AS d ON d.ProcName = p.ProcName
           WHERE (DATALENGTH(d.Def) - DATALENGTH(REPLACE(d.Def, p.OldText, N''))) / DATALENGTH(p.OldText) <> 1)
BEGIN
    SELECT p.ProcName, p.OldText, (DATALENGTH(d.Def) - DATALENGTH(REPLACE(d.Def, p.OldText, N''))) / DATALENGTH(p.OldText) AS Matches
    FROM #P AS p INNER JOIN #Def AS d ON d.ProcName = p.ProcName
    WHERE (DATALENGTH(d.Def) - DATALENGTH(REPLACE(d.Def, p.OldText, N''))) / DATALENGTH(p.OldText) <> 1;
    THROW 59864, 'A procedure''s text differs from the version this script was written for; nothing changed.', 1;
END
IF EXISTS (SELECT 1 FROM #Def WHERE OBJECT_ID(N'dbo.' + ProcName + N'_OLD_10022026160000') IS NOT NULL)
    THROW 59865, 'A backup named <proc>_OLD_10022026160000 already exists.', 1;

BEGIN TRANSACTION;
    DECLARE @name SYSNAME, @def NVARCHAR(MAX), @old NVARCHAR(MAX), @new NVARCHAR(MAX), @bak NVARCHAR(300), @newName SYSNAME;
    DECLARE pc CURSOR LOCAL FAST_FORWARD FOR SELECT ProcName, Def FROM #Def ORDER BY ProcName;
    OPEN pc; FETCH NEXT FROM pc INTO @name, @def;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE rc CURSOR LOCAL FAST_FORWARD FOR SELECT OldText, NewText FROM #P WHERE ProcName = @name ORDER BY Id;
        OPEN rc; FETCH NEXT FROM rc INTO @old, @new;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @def = REPLACE(@def, @old, @new);
            FETCH NEXT FROM rc INTO @old, @new;
        END
        CLOSE rc; DEALLOCATE rc;

        SET @bak = N'dbo.' + @name;
        SET @newName = @name + N'_OLD_10022026160000';
        EXEC sp_rename @bak, @newName;
        EXEC (@def);
        FETCH NEXT FROM pc INTO @name, @def;
    END
    CLOSE pc; DEALLOCATE pc;
COMMIT TRANSACTION;
GO

SELECT name, type_desc, CONVERT(VARCHAR(19), modify_date, 120) AS modified,
       CASE WHEN CHARINDEX('2026-10-02c', OBJECT_DEFINITION(object_id)) > 0 OR name LIKE '%SOV2%' OR name IN ('sp_SOOrder_Lock') THEN 'new / patched' ELSE '' END AS note
FROM sys.objects
WHERE name IN ('sp_SOOrder_Lock', 'funcview_SOV2_Products', 'funcview_SOV2_ProductLots', 'funcview_SOV2_DeliveryLines',
               'spu_PostSOLineV2', 'spu_ReverseSOLineV2', 'sp_ConfirmBranchOrder', 'sp_ConfirmOrder', 'sp_CreditMemo',
               'sp_ReturnSalesOrder', 'sp_CancelDeliveryFIFOJFC', 'sp_AddBranchOrderHRI_JFC', 'sp_AddBranchOrderHRI', 'sp_AddHRIOrderByBarcode')
ORDER BY name;
