/* ================================================================
   2026-10-04: Sales Order partial return (FIFO lines only)
   ================================================================
   Plan: docs/plans/2026-10-01_PartialReturn_SO_STS_Plan.md (section 3),
   narrowed by the user on 2026-10-04:
     * Return part of a line's billed qty (ActualQty) from Orders for Approval:
       Delivered tab and For Delivery tab (POForApproval -> Orders/ReturnSalesOrder).
     * Only lines processed through FIFO (product scan / V2 Auto / By Shipment).
       A barcode-scanned line is one labelled box: it is returned whole or not at
       all (59114). A line is "barcode-scanned" when its BarcodeNo is the own
       Inventory.Barcode of a lot it took stock from (FIFO lines carry a generated
       sticker barcode that no lot has).
     * Cost of the returned part = the cost of the lots actually put back.
     * As before: the GL return posts today; the original order's sales rows are
       adjusted.

   How: a partial return of r from line L
     1. spu_SO_SplitDeliveryLine splits L into L (qty - r, stays live) and a twin
        L' (qty r, next SeqNo of the PO). The newest r of L's FIFO qty moves to L'
        (a lot row on the boundary is split in two). After confirm, L's sales row
        (BatchSalesDetails) and invoice detail rows (TransactionChargeSalesDetails)
        are split the same way: the kept part stays live, the returned part is
        written as already cancelled / ErrorTag = 1. Totals are preserved exactly.
     2. sp_ReturnSalesOrder then returns L' as a whole line, as before.
   So every line stays either fully live or fully returned, and every reader
   (views, reports, confirm, credit memo, Exception Center) keeps working.

   Objects:
     dbo.tt_ReturnSalesOrderQty    NEW type   (SeqNo, ProductNo, ReturnQty)
     dbo.SalesReturnLog            NEW table  one row per returned line per Submit
     dbo.spu_SO_SplitDeliveryLine  NEW proc
     dbo.sp_ReturnSalesOrder       REPLACED   (new optional last parameter
                                   @ReturnQty; omitted = whole-line return as
                                   before, so the old exe keeps working)

   Also fixed in sp_ReturnSalesOrder (needed because a twin keeps its line's
   barcode): the invoice detail rows of a whole-line return are now tagged one
   set per returned sales row (product + barcode + qty), not every row of that
   product + barcode.

   Errors: 59104-59108 (return proc), 59110-59119 (split).

   sp-reviewer 2026-10-04, taken:
     * The returned part's sales amount is the split-off sales row (original -
       kept), not ROUND(r * price): with fractional weights the two differ by a
       cent and a fully returned invoice would keep 0.01.
     * Its invoice COGS row is the cost of the lots moved to the twin (= the GL
       return cost), not "old - ROUND(kept qty * average cost)".
     * A partial with no matching invoice rows is refused (59119); whole-line
       tagging falls back to the old product + barcode match when no row matches
       on qty. A qty for a line that is no longer live is refused (59108).
     * No HOLDLOCK: the per-order applock already serializes every Sales Order
       writer; range locks on these unindexed tables would block POS.
     * Everything after the type runs in one transaction with a post-check.

   Deploy: DEV first. The type batch runs on its own (committed) first: a table
   type created inside a transaction can't be used in it (worklog Feature 8).
   Backup: sp_ReturnSalesOrder_OLD_10042026120000. No grants exist on the proc.
   ================================================================ */

-- ----------------------------------------------------------------
-- 1. Type
-- ----------------------------------------------------------------
IF TYPE_ID('dbo.tt_ReturnSalesOrderQty') IS NULL
    CREATE TYPE dbo.tt_ReturnSalesOrderQty AS TABLE
    (
        SeqNo      DECIMAL(10,0) NOT NULL PRIMARY KEY,
        ProductNo  VARCHAR(20)   NOT NULL,
        ReturnQty  DECIMAL(10,3) NOT NULL
    );
GO

-- everything below is one transaction; the last batch commits only if both procs exist
SET XACT_ABORT ON;
BEGIN TRANSACTION;
GO

-- ----------------------------------------------------------------
-- 2. Return log (one row per returned line per Submit)
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.SalesReturnLog', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.SalesReturnLog
    (
        ReturnLogID   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_SalesReturnLog PRIMARY KEY,
        ReturnBatch   UNIQUEIDENTIFIER  NOT NULL,             -- one per Submit
        PONumber      VARCHAR(20)       NOT NULL,
        DeliveryNo    VARCHAR(20)       NOT NULL,
        SourceSeqNo   DECIMAL(10,0)     NOT NULL,             -- the line the customer returned from
        ReturnSeqNo   DECIMAL(10,0)     NOT NULL,             -- the line actually returned (= SourceSeqNo for a whole line, the twin for a partial)
        ProductNo     VARCHAR(20)       NOT NULL,
        IsPartial     BIT               NOT NULL,
        QtyBefore     DECIMAL(10,3)     NOT NULL,             -- billed qty on the source line before this return
        ReturnQty     DECIMAL(10,3)     NOT NULL,
        SellingPrice  DECIMAL(12,2)     NOT NULL,
        ReturnAmount  DECIMAL(18,2)     NOT NULL,
        ReturnCost    DECIMAL(18,2)     NOT NULL,             -- cost of the lots put back
        AfterConfirm  BIT               NOT NULL,
        TicketNumber  VARCHAR(20)       NULL,                 -- SO-RET ticket (after confirm)
        Reason        VARCHAR(930)      NULL,
        CreatedBy     VARCHAR(50)       NOT NULL,
        CreatedAt     DATETIME          NOT NULL CONSTRAINT DF_SalesReturnLog_CreatedAt DEFAULT (GETDATE())
    );
    CREATE INDEX IX_SalesReturnLog_PO ON dbo.SalesReturnLog (PONumber, DeliveryNo);
END
GO

-- ----------------------------------------------------------------
-- 3. spu_SO_SplitDeliveryLine
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.spu_SO_SplitDeliveryLine', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_SO_SplitDeliveryLine', 'spu_SO_SplitDeliveryLine_OLD_10042026120000';
GO

CREATE PROCEDURE dbo.spu_SO_SplitDeliveryLine
    @PONumber      VARCHAR(20),
    @DeliveryNo    VARCHAR(20),
    @SeqNo         DECIMAL(10,0),
    @SplitQty      DECIMAL(10,3),           -- qty that moves to the twin (the part being returned)
    @ExpectedQty   DECIMAL(10,3),           -- the line's ActualQty as the screen saw it
    @AfterConfirm  BIT,                     -- 1 = the order is invoiced: split its sales / invoice rows too
    @InvoiceNo     VARCHAR(50),
    @SalesBranch   VARCHAR(5),              -- BatchSalesDetails.BranchCode (= PurchaseOrderSummary.BranchCode)
    @User          VARCHAR(50),
    @NewSeqNo      DECIMAL(10,0) OUTPUT,
    @RetGross      DECIMAL(18,2) OUTPUT,    -- sales amount of the split-off part (after confirm: original sales row - kept)
    @RetCost       DECIMAL(18,2) OUTPUT     -- cost of the lots moved to the twin
AS
/*
    Splits a live FIFO delivery line into the kept line (qty - @SplitQty) and a
    twin (qty @SplitQty, next SeqNo of the PO). Moves no stock and writes no
    stock ledger: the caller returns the twin. Runs inside the caller's
    transaction (the caller holds the per-order lock, sp_SOOrder_Lock, which
    serializes every Sales Order writer, so plain UPDLOCK is enough here).
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @@TRANCOUNT = 0
        THROW 59110, 'spu_SO_SplitDeliveryLine must run inside the caller''s transaction.', 1;

    DECLARE @msg NVARCHAR(500), @n INT;
    DECLARE @Prod CHAR(5), @Barcode VARCHAR(120), @QtyDel DECIMAL(10,3), @ActQty DECIMAL(10,3), @DdPrice DECIMAL(10,2);

    SELECT @n = COUNT(*), @Prod = MAX(dd.ProductNo), @Barcode = MAX(dd.BarcodeNo),
           @QtyDel = MAX(dd.QtyDelivered), @ActQty = MAX(ISNULL(dd.ActualQty, dd.QtyDelivered)),
           @DdPrice = MAX(ISNULL(dd.SellingPrice, 0))
    FROM dbo.DeliveryDetails AS dd WITH (UPDLOCK)
    WHERE dd.PONumber = @PONumber AND dd.DeliveryNo = @DeliveryNo AND dd.SeqNo = @SeqNo
      AND ISNULL(dd.isReturned, 0) = 0 AND ISNULL(dd.isCancelled, 0) = 0;

    IF @n <> 1
    BEGIN
        SET @msg = N'Line ' + CAST(@SeqNo AS NVARCHAR(10)) + N' of PO ' + @PONumber + N' is not a live delivery line (already returned or cancelled). Refresh the list.';
        THROW 59111, @msg, 1;
    END;

    IF @ActQty <> @ExpectedQty
    BEGIN
        SET @msg = N'Line ' + CAST(@SeqNo AS NVARCHAR(10)) + N' (' + RTRIM(@Prod) + N') changed since the screen was opened: its quantity is now '
                 + CAST(@ActQty AS NVARCHAR(30)) + N', the screen showed ' + CAST(@ExpectedQty AS NVARCHAR(30)) + N'. Close the screen and open the return again.';
        THROW 59112, @msg, 1;
    END;

    IF @SplitQty <= 0 OR @SplitQty >= @ActQty
    BEGIN
        SET @msg = N'Line ' + CAST(@SeqNo AS NVARCHAR(10)) + N': a partial return must be more than 0 and less than ' + CAST(@ActQty AS NVARCHAR(30)) + N'.';
        THROW 59113, @msg, 1;
    END;

    -- a barcode-scanned line is one labelled box: whole return only
    IF EXISTS (SELECT 1
               FROM dbo.InventoryDeliveryFIFO AS f
               INNER JOIN dbo.Inventory AS i ON i.SequenceNumber = f.SequenceReferenceNumber
               WHERE f.PONumber = @PONumber AND f.DeliveryNo = @DeliveryNo AND f.DevDetSeqNo = @SeqNo AND f.isErrorCorrect = 0
                 AND NULLIF(LTRIM(RTRIM(i.Barcode)), '') = LTRIM(RTRIM(@Barcode)))
    BEGIN
        SET @msg = N'Line ' + CAST(@SeqNo AS NVARCHAR(10)) + N' (' + RTRIM(@Prod) + N') was processed by barcode scan (one labelled box): it can only be returned whole.';
        THROW 59114, @msg, 1;
    END;

    -- the line's live lot rows, locked
    CREATE TABLE #F (FifoSeq INT NOT NULL PRIMARY KEY, Qty DECIMAL(18,3) NOT NULL);
    INSERT INTO #F (FifoSeq, Qty)
    SELECT f.SequenceNumber, CAST(f.QtyDelivered AS DECIMAL(18,3))
    FROM dbo.InventoryDeliveryFIFO AS f WITH (UPDLOCK)
    WHERE f.PONumber = @PONumber AND f.DeliveryNo = @DeliveryNo AND f.DevDetSeqNo = @SeqNo AND f.isErrorCorrect = 0;

    IF ABS(ISNULL((SELECT SUM(Qty) FROM #F), 0) - @QtyDel) > 0.0005
    BEGIN
        SET @msg = N'Line ' + CAST(@SeqNo AS NVARCHAR(10)) + N' (' + RTRIM(@Prod) + N'): its lot rows do not add up to its delivered quantity, so it can''t be split. Return it whole.';
        THROW 59115, @msg, 1;
    END;

    -- next SeqNo of the PO (past both the delivery lines and the lot rows, like the V2 scan procs)
    SELECT @NewSeqNo = ISNULL(MAX(x.s), 0) + 1
    FROM (SELECT MAX(d.SeqNo) AS s
          FROM dbo.DeliveryDetails AS d WITH (UPDLOCK)
          WHERE d.PONumber = @PONumber
          UNION ALL
          SELECT MAX(CAST(f.DevDetSeqNo AS DECIMAL(10,0)))
          FROM dbo.InventoryDeliveryFIFO AS f WITH (UPDLOCK)
          WHERE f.PONumber = @PONumber) AS x;

    IF @NewSeqNo > 99   -- ReturnedOrderDetails.SeqNo is DECIMAL(2,0)
        THROW 59116, 'This order already has 99 line numbers; a partial return would need line 100. Return the whole line instead.', 1;

    -- twin line (the part being returned); Variance stays on the kept line
    INSERT INTO dbo.DeliveryDetails
        (SeqNo, DeliveryNo, PONumber, ReferenceNumber, ProductNo, BarcodeNo, ProductName,
         QtyDelivered, ActualQty, Variance, Cost, SellingPrice, Status, isVat, ProcessedBy,
         isSettled, isCreditMemo, isReturned, isCancelled, DateTimeAdded, DateTimeUpdated)
    SELECT @NewSeqNo, dd.DeliveryNo, dd.PONumber, dd.ReferenceNumber, dd.ProductNo, dd.BarcodeNo, dd.ProductName,
           @SplitQty, @SplitQty, 0, dd.Cost, dd.SellingPrice, dd.Status, dd.isVat, dd.ProcessedBy,
           dd.isSettled, 0, 0, 0, GETDATE(), GETDATE()
    FROM dbo.DeliveryDetails AS dd
    WHERE dd.PONumber = @PONumber AND dd.DeliveryNo = @DeliveryNo AND dd.SeqNo = @SeqNo;

    UPDATE dbo.DeliveryDetails
    SET QtyDelivered    = QtyDelivered - @SplitQty,
        ActualQty       = ISNULL(ActualQty, QtyDelivered) - @SplitQty,
        DateTimeUpdated = GETDATE()
    WHERE PONumber = @PONumber AND DeliveryNo = @DeliveryNo AND SeqNo = @SeqNo;

    -- lot rows: the newest @SplitQty moves to the twin (the return puts back newest first too)
    ;WITH R AS (
        SELECT FifoSeq, Qty, SUM(Qty) OVER (ORDER BY FifoSeq DESC ROWS UNBOUNDED PRECEDING) AS Run
        FROM #F)
    SELECT FifoSeq, Qty,
           CASE WHEN Run <= @SplitQty THEN Qty
                WHEN Run - Qty < @SplitQty THEN @SplitQty - (Run - Qty)
                ELSE 0 END AS MoveQty
    INTO #M
    FROM R;

    UPDATE f SET f.DevDetSeqNo = CAST(@NewSeqNo AS INT)
    FROM dbo.InventoryDeliveryFIFO AS f
    INNER JOIN #M AS m ON m.FifoSeq = f.SequenceNumber
    WHERE m.MoveQty > 0 AND m.MoveQty = m.Qty;

    -- the boundary row (at most one): its moved part becomes a new row of the same lot
    INSERT INTO dbo.InventoryDeliveryFIFO
        (DeliveryNo, PONumber, BranchCode, ProductNo, Description, QtyDelivered, Cost, TotalCost,
         DateProcessed, DevDetSeqNo, SequenceReferenceNumber, isVat, isErrorCorrect, SellingPrice, TotalAmount)
    SELECT f.DeliveryNo, f.PONumber, f.BranchCode, f.ProductNo, f.Description, m.MoveQty, f.Cost, ROUND(m.MoveQty * f.Cost, 2),
           f.DateProcessed, CAST(@NewSeqNo AS INT), f.SequenceReferenceNumber, f.isVat, 0, f.SellingPrice,
           CASE WHEN f.TotalAmount IS NULL THEN NULL ELSE ROUND(m.MoveQty * ISNULL(f.SellingPrice, 0), 2) END
    FROM dbo.InventoryDeliveryFIFO AS f
    INNER JOIN #M AS m ON m.FifoSeq = f.SequenceNumber
    WHERE m.MoveQty > 0 AND m.MoveQty < m.Qty;

    -- cost of what moves to the twin = what the return will put back (same formula as the return's lot cost)
    SELECT @RetCost = ROUND(SUM(m.MoveQty * CAST(f.Cost AS DECIMAL(19,4))), 2)
    FROM #M AS m
    INNER JOIN dbo.InventoryDeliveryFIFO AS f ON f.SequenceNumber = m.FifoSeq
    WHERE m.MoveQty > 0;
    SET @RetCost  = ISNULL(@RetCost, 0);
    SET @RetGross = ROUND(@SplitQty * @DdPrice, 2);   -- before confirm (nothing billed); replaced below after confirm

    UPDATE f
    SET f.QtyDelivered = CAST(CAST(f.QtyDelivered AS DECIMAL(18,3)) - m.MoveQty AS FLOAT),
        f.TotalCost    = ISNULL(f.TotalCost, 0) - ROUND(m.MoveQty * f.Cost, 2),
        f.TotalAmount  = CASE WHEN f.TotalAmount IS NULL THEN NULL ELSE f.TotalAmount - ROUND(m.MoveQty * ISNULL(f.SellingPrice, 0), 2) END
    FROM dbo.InventoryDeliveryFIFO AS f
    INNER JOIN #M AS m ON m.FifoSeq = f.SequenceNumber
    WHERE m.MoveQty > 0 AND m.MoveQty < m.Qty;

    IF ABS(ISNULL((SELECT SUM(CAST(f.QtyDelivered AS DECIMAL(18,3))) FROM dbo.InventoryDeliveryFIFO AS f
                   WHERE f.PONumber = @PONumber AND f.DeliveryNo = @DeliveryNo AND f.DevDetSeqNo = @NewSeqNo AND f.isErrorCorrect = 0), 0) - @SplitQty) > 0.0005
       OR ABS(ISNULL((SELECT SUM(CAST(f.QtyDelivered AS DECIMAL(18,3))) FROM dbo.InventoryDeliveryFIFO AS f
                      WHERE f.PONumber = @PONumber AND f.DeliveryNo = @DeliveryNo AND f.DevDetSeqNo = @SeqNo AND f.isErrorCorrect = 0), 0) - (@QtyDel - @SplitQty)) > 0.0005
        THROW 59117, 'Splitting the line''s lot rows did not add up. Nothing was returned.', 1;

    -- line cost of both parts = their own lots' weighted cost (same formula as Save)
    UPDATE dd SET dd.Cost = c.Cost
    FROM dbo.DeliveryDetails AS dd
    CROSS APPLY (SELECT ROUND(SUM(f.TotalCost) / NULLIF(SUM(CAST(f.QtyDelivered AS DECIMAL(18,3))), 0), 2) AS Cost
                 FROM dbo.InventoryDeliveryFIFO AS f
                 WHERE f.PONumber = dd.PONumber AND f.DeliveryNo = dd.DeliveryNo AND f.DevDetSeqNo = dd.SeqNo AND f.isErrorCorrect = 0) AS c
    WHERE dd.PONumber = @PONumber AND dd.DeliveryNo = @DeliveryNo AND dd.SeqNo IN (@SeqNo, @NewSeqNo) AND c.Cost IS NOT NULL;

    IF @AfterConfirm = 0
        RETURN;

    -- ---- after confirm: split the sales row (BatchSalesDetails) ----
    -- It has no row key, so it is updated through a TOP (1) CTE and the old values are captured with OUTPUT.
    -- After a credit memo QtySold still holds the qty billed at confirm (> ActualQty), hence the ordering.
    SELECT TOP (0) * INTO #B FROM dbo.BatchSalesDetails;

    ;WITH B AS (
        SELECT TOP (1) b.*
        FROM dbo.BatchSalesDetails AS b WITH (UPDLOCK)
        WHERE b.ReferenceNo = @PONumber AND b.BranchCode = @SalesBranch AND b.ProductCode = @Prod
          AND ISNULL(b.Barcode, '') = ISNULL(@Barcode, '')
          AND ISNULL(b.isCancelled, 0) = 0 AND ISNULL(b.isVoid, 0) = 0 AND b.QtySold > @SplitQty
        ORDER BY CASE WHEN b.QtySold = @ActQty THEN 0 WHEN b.QtySold = @QtyDel THEN 1 ELSE 2 END, b.QtySold DESC)
    UPDATE B
    SET QtySold     = QtySold - @SplitQty,
        TotalAmount = ROUND((QtySold - @SplitQty) * SellingPrice, 2),
        SubTotal    = CASE WHEN isVat = 1 THEN ROUND((QtySold - @SplitQty) * SellingPrice / 1.12, 2)
                           ELSE ROUND((QtySold - @SplitQty) * SellingPrice, 2) END,
        TaxTotal    = CASE WHEN isVat = 1 THEN ROUND((QtySold - @SplitQty) * SellingPrice / 1.12 * 0.12, 2) ELSE 0 END
    OUTPUT deleted.* INTO #B;

    IF (SELECT COUNT(*) FROM #B) <> 1
    BEGIN
        SET @msg = N'Line ' + CAST(@SeqNo AS NVARCHAR(10)) + N' (' + RTRIM(@Prod) + N'): its sales record was not found, so it can''t be split. Return it whole.';
        THROW 59118, @msg, 1;
    END;

    DECLARE @OrigQty DECIMAL(9,3), @kq DECIMAL(9,3), @Price DECIMAL(10,2), @bVat BIT,
            @kTotal DECIMAL(10,2), @kSub DECIMAL(10,2), @kTax DECIMAL(10,2);
    SELECT @OrigQty = QtySold, @Price = SellingPrice, @bVat = ISNULL(isVat, 0) FROM #B;
    SET @kq     = @OrigQty - @SplitQty;
    SET @kTotal = ROUND(@kq * @Price, 2);
    SET @kSub   = CASE WHEN @bVat = 1 THEN ROUND(@kq * @Price / 1.12, 2) ELSE ROUND(@kq * @Price, 2) END;
    SET @kTax   = CASE WHEN @bVat = 1 THEN ROUND(@kq * @Price / 1.12 * 0.12, 2) ELSE 0 END;
    SET @RetGross = (SELECT TotalAmount FROM #B) - @kTotal;   -- kept + returned = what was billed, to the cent

    -- the returned part, already cancelled (what a whole-line return leaves behind); discount / charge / income stay on the kept row
    INSERT INTO dbo.BatchSalesDetails
        (SequenceNumber, BranchCode, ReferenceNo, CashierTransNo, ProductCode, CategoryCode, Barcode, Description,
         Cost, OriginalSellingPrice, SellingPrice, QtySold, PrevQty, UnitMeasure, DiscountRate, DiscountTotal,
         ChargeRate, ChargeTotal, TaxRate, TaxTotal, SubTotal, Income, isHold, isConfirmed, isCancelled, isVoid,
         isErrorCorrect, isVat, HoldBy, CancelledBy, VoidBy, ProcessedBy, TotalAmount, Status, DateOrder,
         isUpload, isPosted, isCosting, MachineUsed)
    SELECT b.SequenceNumber, b.BranchCode, b.ReferenceNo, b.CashierTransNo, b.ProductCode, b.CategoryCode, b.Barcode, b.Description,
           b.Cost, b.OriginalSellingPrice, b.SellingPrice, @SplitQty, b.PrevQty, b.UnitMeasure, b.DiscountRate, 0,
           b.ChargeRate, 0, b.TaxRate, b.TaxTotal - @kTax, b.SubTotal - @kSub, 0, b.isHold, b.isConfirmed, 1, b.isVoid,
           b.isErrorCorrect, b.isVat, b.HoldBy, LEFT(@User, 20), b.VoidBy, b.ProcessedBy, b.TotalAmount - @kTotal, b.Status, b.DateOrder,
           b.isUpload, b.isPosted, b.isCosting, b.MachineUsed
    FROM #B AS b;

    -- ---- after confirm: split the invoice detail rows (one per TransCode) ----
    CREATE TABLE #T (SeqNo DECIMAL(7,0), BranchCode CHAR(3), TransactionDate DATE, Product CHAR(5), Cost DECIMAL(12,2),
                     SellingPrice DECIMAL(12,2), SKU VARCHAR(120), TransCode VARCHAR(30), [Type] VARCHAR(100),
                     OldAmount DECIMAL(12,2), NewAmount DECIMAL(12,2));

    ;WITH T AS (
        SELECT d.*, ROW_NUMBER() OVER (PARTITION BY d.TransCode ORDER BY d.SeqNo) AS rn
        FROM dbo.TransactionChargeSalesDetails AS d WITH (UPDLOCK)
        WHERE d.ReferenceNo = @PONumber AND d.InvoiceNo = @InvoiceNo AND d.Product = @Prod
          AND ISNULL(d.SKU, '') = ISNULL(@Barcode, '') AND ISNULL(d.ErrorTag, 0) = 0 AND d.Quantity = @OrigQty
          AND d.TransCode IN ('SI-VATEX', 'SI-VAT', 'SI-VAT-OUT', 'COGS-VATEX', 'COGS-VAT'))
    UPDATE T
    SET Quantity    = @kq,
        TotalAmount = CASE TransCode WHEN 'SI-VATEX'   THEN @kTotal
                                     WHEN 'SI-VAT'     THEN @kSub
                                     WHEN 'SI-VAT-OUT' THEN @kTax
                                     ELSE TotalAmount - @RetCost END   -- COGS: the returned part = the lots put back
    OUTPUT deleted.SeqNo, deleted.BranchCode, deleted.TransactionDate, deleted.Product, deleted.Cost, deleted.SellingPrice,
           deleted.SKU, deleted.TransCode, deleted.[Type], deleted.TotalAmount, inserted.TotalAmount
    INTO #T (SeqNo, BranchCode, TransactionDate, Product, Cost, SellingPrice, SKU, TransCode, [Type], OldAmount, NewAmount)
    WHERE rn = 1;

    IF NOT EXISTS (SELECT 1 FROM #T WHERE TransCode IN ('SI-VATEX', 'SI-VAT'))
    BEGIN
        SET @msg = N'Line ' + CAST(@SeqNo AS NVARCHAR(10)) + N' (' + RTRIM(@Prod) + N'): its invoice detail rows were not found, so it can''t be split. Return it whole.';
        THROW 59119, @msg, 1;
    END;

    DECLARE @MaxSeq DECIMAL(7,0) = (SELECT ISNULL(MAX(d.SeqNo), 0) FROM dbo.TransactionChargeSalesDetails AS d WITH (UPDLOCK)
                                    WHERE d.ReferenceNo = @PONumber AND d.InvoiceNo = @InvoiceNo);

    INSERT INTO dbo.TransactionChargeSalesDetails
        (SeqNo, BranchCode, ReferenceNo, InvoiceNo, TransactionDate, Product, Quantity, Cost, SellingPrice, TotalAmount,
         SKU, TransCode, [Type], ErrorTag)
    SELECT @MaxSeq + ROW_NUMBER() OVER (ORDER BY t.SeqNo), t.BranchCode, @PONumber, @InvoiceNo, t.TransactionDate, t.Product,
           @SplitQty, t.Cost, t.SellingPrice, t.OldAmount - t.NewAmount, t.SKU, t.TransCode, t.[Type], 1
    FROM #T AS t;
END
GO

-- ----------------------------------------------------------------
-- 4. sp_ReturnSalesOrder (same parameters + optional @ReturnQty)
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_ReturnSalesOrder', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_ReturnSalesOrder', 'sp_ReturnSalesOrder_OLD_10042026120000';
GO

CREATE PROCEDURE dbo.sp_ReturnSalesOrder
    @parmbranchcode   char(3),
    @parmpono         varchar(10),
    @parmdevno        varchar(10),
    @parmuser         varchar(50),
    @parmreturnstatus varchar(30),
    @parmreason       varchar(930),
    @parmmachinename  varchar(50),
    @Lines            dbo.tt_ReturnSalesOrderLines READONLY,
    @ReturnQty        dbo.tt_ReturnSalesOrderQty READONLY     -- 2026-10-04: optional; omitted = whole lines
AS
/*
    Returns delivery lines. Only SeqNo / ProductNo (and, from @Lines, the
    ActualQty the screen saw) are taken from the caller; every other quantity
    and price is re-read from DeliveryDetails.
      Partial (2026-10-04): a @ReturnQty row below the line's ActualQty splits the
        line first (spu_SO_SplitDeliveryLine) and returns the split-off twin.
        FIFO lines only; barcode-scanned lines are refused (59114).
      Stock: ActualQty (the billed qty) goes back to the lots the line used,
        newest consumed lot first, one InventoryLedger row per lot.
      Before confirm: no GL (nothing was billed); confirm skips returned lines.
      After confirm: sales lines cancelled 1:1, sales header recomputed, AR
        invoice lines tagged, then spu_SO_PostInvoiceReduction 'RET' for
        THIS return only (sales / AR, cost back to inventory, excess to
        customer credit). Return cost: whole line = ROUND(ActualQty * line Cost, 2)
        as before; partial = the cost of the lots put back.
      SalesReturnLog: one row per returned line.
    Caller: Orders/ReturnSalesOrder.cs.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC dbo.sp_SOOrder_Lock @PONumber = @parmpono;   -- 2026-10-02c: the per-order lock every Sales Order writer shares

        IF NOT EXISTS (SELECT 1 FROM @Lines)
            THROW 59101, 'No lines submitted for this Sales Return.', 1;

        DECLARE @invoiceno VARCHAR(50), @effectivitydate DATE, @custkey CHAR(8), @custname VARCHAR(150), @branch VARCHAR(5);
        SELECT @invoiceno = InvoiceNo, @effectivitydate = EffectivityDate FROM dbo.DeliverySummary WHERE PONumber = @parmpono AND DeliveryNo = @parmdevno;
        SELECT @custkey = Customer, @branch = BranchCode FROM dbo.PurchaseOrderSummary WHERE PONumber = @parmpono;
        SELECT @custname = CustomerName FROM dbo.Customers WHERE CustomerKey = @custkey;

        DECLARE @confirmed BIT = CASE WHEN EXISTS (SELECT 1 FROM dbo.TransactionChargeSales
                                                   WHERE CustomerKey = @custkey AND ReferenceNo = @parmpono AND InvoiceNo = @invoiceno)
                                      THEN 1 ELSE 0 END;
        IF (@confirmed = 1 AND ISNULL(@parmreturnstatus, '') <> 'DELIVERED') OR (@confirmed = 0 AND ISNULL(@parmreturnstatus, '') = 'DELIVERED')
            THROW 59103, 'The screen status does not match the order: refresh the list and open the return from the right tab.', 1;

        -- ---- 2026-10-04: quantities from the screen (new exe only) ----
        CREATE TABLE #Req (SeqNo DECIMAL(10,0) NOT NULL PRIMARY KEY, ProductNo VARCHAR(20) NOT NULL, ReturnQty DECIMAL(10,3) NOT NULL,
                           ExpectedQty DECIMAL(10,3) NOT NULL, LineQty DECIMAL(10,3) NULL, IsPartial BIT NOT NULL DEFAULT 0,
                           ReturnSeqNo DECIMAL(10,0) NULL, RetGross DECIMAL(18,2) NULL, RetCost DECIMAL(18,2) NULL);

        IF EXISTS (SELECT 1 FROM @ReturnQty q WHERE NOT EXISTS (SELECT 1 FROM @Lines l WHERE l.SeqNo = q.SeqNo AND l.ProductNo = q.ProductNo))
            THROW 59104, 'A return quantity was sent for a line that is not ticked. Nothing was returned.', 1;

        INSERT INTO #Req (SeqNo, ProductNo, ReturnQty, ExpectedQty, LineQty)
        SELECT q.SeqNo, q.ProductNo, q.ReturnQty, l.ActualQty, ISNULL(dd.ActualQty, dd.QtyDelivered)
        FROM @ReturnQty AS q
        INNER JOIN @Lines AS l ON l.SeqNo = q.SeqNo AND l.ProductNo = q.ProductNo
        LEFT JOIN dbo.DeliveryDetails AS dd WITH (UPDLOCK)
               ON dd.PONumber = @parmpono AND dd.DeliveryNo = @parmdevno AND dd.SeqNo = q.SeqNo AND dd.ProductNo = q.ProductNo
              AND ISNULL(dd.isReturned, 0) = 0 AND ISNULL(dd.isCancelled, 0) = 0;

        IF EXISTS (SELECT 1 FROM #Req WHERE LineQty IS NULL)
            THROW 59108, 'A ticked line is no longer open (already returned or cancelled). Close the screen and open the return again.', 1;

        IF EXISTS (SELECT 1 FROM #Req WHERE ReturnQty <= 0)
            THROW 59105, 'Return quantity must be more than 0. Untick a line you are not returning.', 1;

        IF EXISTS (SELECT 1 FROM #Req WHERE LineQty IS NOT NULL AND LineQty <> ExpectedQty)
            THROW 59107, 'A line changed since the screen was opened (credit memo or another return). Close the screen and open the return again.', 1;

        IF EXISTS (SELECT 1 FROM #Req WHERE LineQty IS NOT NULL AND ReturnQty > LineQty)
            THROW 59106, 'Return quantity can''t be more than the line''s billed quantity (Actual Qty).', 1;

        UPDATE #Req SET IsPartial = 1 WHERE LineQty IS NOT NULL AND ReturnQty < LineQty;

        DECLARE @sSeq DECIMAL(10,0), @sQty DECIMAL(10,3), @sExp DECIMAL(10,3), @sNew DECIMAL(10,0), @sGross DECIMAL(18,2), @sCost DECIMAL(18,2);
        SELECT @sSeq = MIN(SeqNo) FROM #Req WHERE IsPartial = 1;
        WHILE @sSeq IS NOT NULL
        BEGIN
            SELECT @sQty = ReturnQty, @sExp = ExpectedQty FROM #Req WHERE SeqNo = @sSeq;
            SELECT @sNew = NULL, @sGross = NULL, @sCost = NULL;
            EXEC dbo.spu_SO_SplitDeliveryLine
                @PONumber = @parmpono, @DeliveryNo = @parmdevno, @SeqNo = @sSeq, @SplitQty = @sQty, @ExpectedQty = @sExp,
                @AfterConfirm = @confirmed, @InvoiceNo = @invoiceno, @SalesBranch = @branch, @User = @parmuser,
                @NewSeqNo = @sNew OUTPUT, @RetGross = @sGross OUTPUT, @RetCost = @sCost OUTPUT;
            UPDATE #Req SET ReturnSeqNo = @sNew, RetGross = @sGross, RetCost = @sCost WHERE SeqNo = @sSeq;
            SELECT @sSeq = MIN(SeqNo) FROM #Req WHERE IsPartial = 1 AND SeqNo > @sSeq;
        END;

        -- the lines returned whole: ticked lines that were not split + every split-off twin
        SELECT dd.DeliveryNo, dd.SeqNo, dd.PONumber, dd.ProductNo, dd.ProductName, dd.BarcodeNo,
               dd.QtyDelivered, ISNULL(dd.Cost, 0) AS Cost, ISNULL(dd.SellingPrice, 0) AS SellingPrice,
               ISNULL(dd.ActualQty, dd.QtyDelivered) AS ActualQty, dd.Variance, ISNULL(dd.isVat, 0) AS isVat,
               CAST(CASE WHEN p.SeqNo IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IsPartial,
               ISNULL(p.SeqNo, dd.SeqNo) AS SourceSeqNo,
               ISNULL(p.LineQty, ISNULL(dd.ActualQty, dd.QtyDelivered)) AS QtyBefore
        INTO #NewReturns
        FROM dbo.DeliveryDetails dd WITH (UPDLOCK)
        LEFT JOIN #Req AS p ON p.IsPartial = 1 AND p.ReturnSeqNo = dd.SeqNo
        WHERE dd.PONumber = @parmpono AND dd.DeliveryNo = @parmdevno
          AND ISNULL(dd.isReturned, 0) = 0 AND ISNULL(dd.isCancelled, 0) = 0
          AND (p.SeqNo IS NOT NULL
               OR (EXISTS (SELECT 1 FROM @Lines l WHERE l.SeqNo = dd.SeqNo AND l.ProductNo = dd.ProductNo)
                   AND NOT EXISTS (SELECT 1 FROM #Req s WHERE s.IsPartial = 1 AND s.SeqNo = dd.SeqNo)));

        IF NOT EXISTS (SELECT 1 FROM #NewReturns)
            THROW 59102, 'No new lines to return for this PO (already returned or cancelled).', 1;

        INSERT INTO dbo.ReturnedOrderDetails
            (SeqNo, PONumber, ProductNo, ProductName, BarcodeNo, QtyDelivered,
             Cost, SellingPrice, ActualQty, Variance, isVat, ProcessedBy, DateProcessed)
        SELECT SeqNo, PONumber, ProductNo, ProductName, BarcodeNo, QtyDelivered,
               Cost, SellingPrice, ActualQty, Variance, isVat, @parmuser, CAST(GETDATE() AS DATE)
        FROM #NewReturns;

        DECLARE @RetItems INT, @RetQty DECIMAL(18,3), @RetAmt DECIMAL(18,2);
        SELECT @RetItems = COUNT(*), @RetQty = ISNULL(SUM(ActualQty), 0), @RetAmt = ISNULL(SUM(ROUND(ActualQty * SellingPrice, 2)), 0)
        FROM dbo.ReturnedOrderDetails WHERE PONumber = @parmpono;
        IF NOT EXISTS (SELECT 1 FROM dbo.ReturnedOrderSummary WITH (UPDLOCK) WHERE PONumber = @parmpono)
            INSERT INTO dbo.ReturnedOrderSummary (PONumber, InvoiceNo, BranchCode, TotalItem, TotalQtyDelivered, TotalAmount, EffectivityDate, DateAdded, PreparedBy, ReturnType, Reason)
            VALUES (@parmpono, @invoiceno, @parmbranchcode, @RetItems, @RetQty, @RetAmt, @effectivitydate, GETDATE(), @parmuser, ' ', @parmreason);
        ELSE
            UPDATE dbo.ReturnedOrderSummary SET TotalItem = @RetItems, TotalQtyDelivered = @RetQty, TotalAmount = @RetAmt WHERE PONumber = @parmpono;

        UPDATE dd SET dd.isReturned = 1, dd.DateTimeUpdated = GETDATE()
        FROM dbo.DeliveryDetails dd
        INNER JOIN #NewReturns r ON r.DeliveryNo = dd.DeliveryNo AND r.PONumber = dd.PONumber AND r.SeqNo = dd.SeqNo;

        DECLARE @Live INT = (SELECT COUNT(*) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isReturned = 0 AND isCancelled = 0);
        UPDATE dbo.DeliverySummary
        SET TotalItem = (SELECT ISNULL(COUNT(*),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono),
            TotalQtyDelivered = (SELECT ISNULL(SUM(QtyDelivered),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isCancelled = 0),
            TotalActualQty = (SELECT ISNULL(SUM(ActualQty),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isCancelled = 0 AND isReturned = 0),
            TotalItemSold = (SELECT ISNULL(COUNT(*),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isCancelled = 0 AND isReturned = 0),
            TotalItemReturned = (SELECT ISNULL(COUNT(*),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isReturned = 1),
            Status = CASE WHEN @Live = 0 THEN 'RETURNED' ELSE Status END
        WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono;

        -- stock: put ActualQty back, newest consumed lot first
        ;WITH F AS (
            SELECT f.SequenceNumber AS FifoSeq, f.SequenceReferenceNumber AS Lot, ISNULL(f.QtyDelivered, 0) AS Qty, ISNULL(f.Cost, 0) AS Cost,
                   f.Description, r.ActualQty, r.ProductNo, r.SeqNo,
                   SUM(ISNULL(f.QtyDelivered, 0)) OVER (PARTITION BY r.SeqNo ORDER BY f.SequenceNumber DESC ROWS UNBOUNDED PRECEDING) AS RunQty
            FROM dbo.InventoryDeliveryFIFO f WITH (UPDLOCK, ROWLOCK)
            INNER JOIN #NewReturns r ON r.DeliveryNo = f.DeliveryNo AND r.PONumber = f.PONumber AND r.SeqNo = f.DevDetSeqNo
            WHERE f.isErrorCorrect = 0)
        SELECT FifoSeq, Lot, Cost, Description, ProductNo, SeqNo,
               CASE WHEN RunQty <= ActualQty THEN Qty
                    WHEN RunQty - Qty < ActualQty THEN ActualQty - (RunQty - Qty)
                    ELSE 0 END AS RestoreQty
        INTO #Restore
        FROM F;

        INSERT INTO dbo.InventoryLedger
            (SequenceRefNum, OriginBranch, DestinationBranch, DateProcessed, Product,
             Description, BegQty, QtyIn, QtyOut, EndQty, Cost, Remarks, ProcessedBy)
        SELECT x.Lot, @parmbranchcode, ISNULL(i.Branch, '888'), GETDATE(), x.ProductNo,
               x.Description, ISNULL(i.Available, 0), x.RestoreQty, 0, ISNULL(i.Available, 0) + x.RestoreQty, x.Cost,
               'SO RETURN PO#' + @parmpono, @parmuser
        FROM (SELECT Lot, ProductNo, MAX(Cost) AS Cost, MAX(Description) AS Description, SUM(RestoreQty) AS RestoreQty
              FROM #Restore GROUP BY Lot, ProductNo HAVING SUM(RestoreQty) > 0) x
        LEFT JOIN dbo.Inventory i WITH (UPDLOCK, ROWLOCK) ON i.SequenceNumber = x.Lot;

        UPDATE i SET i.Available = ISNULL(i.Available, 0) + x.RestoreQty, i.IsStock = 1
        FROM dbo.Inventory i
        INNER JOIN (SELECT Lot, SUM(RestoreQty) AS RestoreQty FROM #Restore GROUP BY Lot HAVING SUM(RestoreQty) > 0) x ON x.Lot = i.SequenceNumber;

        UPDATE f SET f.isErrorCorrect = 1
        FROM dbo.InventoryDeliveryFIFO f INNER JOIN #Restore x ON x.FifoSeq = f.SequenceNumber;

        -- amount and cost per returned line: whole line as before; partial = what the split moved
        -- (sales: the split-off sales row; cost: the lots put back)
        SELECT n.SeqNo,
               CAST(CASE WHEN n.IsPartial = 1 THEN ISNULL(p.RetGross, 0) ELSE ROUND(n.ActualQty * n.SellingPrice, 2) END AS DECIMAL(18,2)) AS RetGross,
               CAST(CASE WHEN n.IsPartial = 1 THEN ISNULL(p.RetCost, 0)  ELSE ROUND(n.ActualQty * n.Cost, 2) END AS DECIMAL(18,2)) AS RetCost
        INTO #RetCost
        FROM #NewReturns AS n
        LEFT JOIN #Req AS p ON p.IsPartial = 1 AND p.ReturnSeqNo = n.SeqNo;

        DECLARE @tkVat VARCHAR(20), @tkVatEx VARCHAR(20), @excess DECIMAL(18,2);

        IF @confirmed = 1
        BEGIN
            -- sales lines of WHOLE-line returns: pair each returned delivery line with one live sales line of the same product + barcode
            -- (BatchSalesDetails has no usable row key: SequenceNumber is not filled by sp_ConfirmOrder,
            --  so the rows are numbered and updated through the CTE itself). Split twins already have their cancelled row.
            CREATE TABLE #CanBSD (ProductCode CHAR(5), Barcode VARCHAR(50), QtySold DECIMAL(9,3));
            ;WITH BS AS (SELECT b.isCancelled, b.ProductCode, ISNULL(b.Barcode, '') AS Barcode, b.QtySold,
                               ROW_NUMBER() OVER (PARTITION BY b.ProductCode, ISNULL(b.Barcode, '') ORDER BY b.QtySold DESC, b.TotalAmount DESC) AS rn
                        FROM dbo.BatchSalesDetails b
                        WHERE b.ReferenceNo = @parmpono AND b.BranchCode = @branch AND ISNULL(b.isCancelled, 0) = 0),
                  RS AS (SELECT r.ProductNo, ISNULL(r.BarcodeNo, '') AS Barcode,
                               ROW_NUMBER() OVER (PARTITION BY r.ProductNo, ISNULL(r.BarcodeNo, '') ORDER BY r.SeqNo) AS rn
                        FROM #NewReturns r
                        WHERE r.IsPartial = 0)
            UPDATE BS SET isCancelled = 1
            OUTPUT inserted.ProductCode, inserted.Barcode, inserted.QtySold INTO #CanBSD (ProductCode, Barcode, QtySold)
            FROM BS
            INNER JOIN RS ON RS.ProductNo = BS.ProductCode AND RS.Barcode = BS.Barcode AND RS.rn = BS.rn;

            UPDATE s SET
                TotalItemReturned   = x.ItemRet,  TotalItem = x.Item,  TotalItemSold = x.Item,
                TotalVatableItems   = x.VatItems, TotalReturnedAmount = x.RetAmt,
                TotalTax = x.Tax, TotalKilos = x.Kilos, SubTotal = x.SubTotal, TotalAmount = x.Amt,
                TotalVATSale = x.Tax, TotalVATExemptSale = x.VatExempt, TotalVatableSale = x.Vatable
            FROM dbo.BatchSalesSummary s
            CROSS APPLY (SELECT
                SUM(CASE WHEN isCancelled = 1 AND isVoid = 0 THEN 1 ELSE 0 END) AS ItemRet,
                SUM(CASE WHEN isCancelled = 0 AND isVoid = 0 THEN 1 ELSE 0 END) AS Item,
                SUM(CASE WHEN isVat = 1 AND isCancelled = 0 AND isVoid = 0 THEN 1 ELSE 0 END) AS VatItems,
                ISNULL(SUM(CASE WHEN isCancelled = 1 AND isVoid = 0 THEN TotalAmount END), 0) AS RetAmt,
                ISNULL(SUM(CASE WHEN isCancelled = 0 AND isVoid = 0 THEN TaxTotal END), 0) AS Tax,
                ISNULL(SUM(CASE WHEN isCancelled = 0 AND isVoid = 0 THEN QtySold END), 0) AS Kilos,
                ISNULL(SUM(CASE WHEN isCancelled = 0 AND isVoid = 0 THEN SubTotal END), 0) AS SubTotal,
                ISNULL(SUM(CASE WHEN isCancelled = 0 AND isVoid = 0 THEN TotalAmount END), 0) AS Amt,
                ISNULL(SUM(CASE WHEN isVat = 0 AND isCancelled = 0 AND isVoid = 0 THEN TotalAmount END), 0) AS VatExempt,
                ISNULL(SUM(CASE WHEN isVat = 1 AND isCancelled = 0 AND isVoid = 0 THEN SubTotal END), 0) AS Vatable
                FROM dbo.BatchSalesDetails b WHERE b.ReferenceNo = s.ReferenceNo AND b.BranchCode = s.BranchCode) x
            WHERE s.ReferenceNo = @parmpono AND s.BranchCode = @branch;

            -- invoice detail rows of whole-line returns: one set (per TransCode) per cancelled sales row,
            -- matched on product + barcode + qty (2026-10-04: was product + barcode only, which tagged a split twin's kept rows too).
            -- A cancelled sales row with no invoice row of its qty (older / hand-edited data) keeps the old product + barcode match.
            UPDATE d SET d.ErrorTag = 1
            FROM dbo.TransactionChargeSalesDetails d
            WHERE d.ReferenceNo = @parmpono AND d.InvoiceNo = @invoiceno AND ISNULL(d.ErrorTag, 0) = 0
              AND EXISTS (SELECT 1 FROM #CanBSD c
                          WHERE c.ProductCode = d.Product AND c.Barcode = ISNULL(d.SKU, '')
                            AND NOT EXISTS (SELECT 1 FROM dbo.TransactionChargeSalesDetails q
                                            WHERE q.ReferenceNo = @parmpono AND q.InvoiceNo = @invoiceno AND ISNULL(q.ErrorTag, 0) = 0
                                              AND q.Product = c.ProductCode AND ISNULL(q.SKU, '') = c.Barcode AND q.Quantity = c.QtySold));

            ;WITH C AS (SELECT ProductCode, Barcode, QtySold, COUNT(*) AS n FROM #CanBSD GROUP BY ProductCode, Barcode, QtySold),
                  T AS (SELECT d.ErrorTag, d.Product, ISNULL(d.SKU, '') AS SKU, d.Quantity,
                               ROW_NUMBER() OVER (PARTITION BY d.Product, ISNULL(d.SKU, ''), d.Quantity, d.TransCode ORDER BY d.SeqNo) AS rn
                        FROM dbo.TransactionChargeSalesDetails d
                        WHERE d.ReferenceNo = @parmpono AND d.InvoiceNo = @invoiceno AND ISNULL(d.ErrorTag, 0) = 0)
            UPDATE T SET ErrorTag = 1
            FROM T
            INNER JOIN C ON C.ProductCode = T.Product AND C.Barcode = T.SKU AND C.QtySold = T.Quantity AND T.rn <= C.n;

            -- 2026-10-01: the GL is all VAT-exempt (client rule): every line goes to the VATEX legs
            DECLARE @nVat DECIMAL(18,2), @tVat DECIMAL(18,2), @gVatEx DECIMAL(18,2), @cVat DECIMAL(18,2), @cVatEx DECIMAL(18,2);
            SELECT @nVat   = 0,
                   @tVat   = 0,
                   @gVatEx = ISNULL(SUM(c.RetGross), 0),
                   @cVat   = 0,
                   @cVatEx = ISNULL(SUM(c.RetCost), 0)
            FROM #RetCost AS c;

            DECLARE @Particulars VARCHAR(6999) = 'SALES RETURN | Customer: ' + ISNULL(@custname, '') + ' | PO: ' + @parmpono + ' | Invoice: ' + ISNULL(@invoiceno, '');
            EXEC dbo.spu_SO_PostInvoiceReduction
                @Kind = 'RET', @PONumber = @parmpono, @InvoiceNo = @invoiceno, @CustomerKey = @custkey,
                @BranchCode = @branch, @User = @parmuser,
                @NetVat = @nVat, @TaxVat = @tVat, @CostVat = @cVat, @GrossVatEx = @gVatEx, @CostVatEx = @cVatEx,
                @Particulars = @Particulars,
                @TicketVat = @tkVat OUTPUT, @TicketVatEx = @tkVatEx OUTPUT, @Excess = @excess OUTPUT;

            UPDATE dbo.ReturnedOrderSummary
            SET TicketRefNoVAT   = CASE WHEN @tkVat   <> ' ' THEN @tkVat   ELSE TicketRefNoVAT END,
                TicketRefNoVATEX = CASE WHEN @tkVatEx <> ' ' THEN @tkVatEx ELSE TicketRefNoVATEX END
            WHERE PONumber = @parmpono;
        END

        -- one log row per returned line (the audit trail of which line was split from which)
        DECLARE @Batch UNIQUEIDENTIFIER = NEWID();
        INSERT INTO dbo.SalesReturnLog
            (ReturnBatch, PONumber, DeliveryNo, SourceSeqNo, ReturnSeqNo, ProductNo, IsPartial, QtyBefore, ReturnQty,
             SellingPrice, ReturnAmount, ReturnCost, AfterConfirm, TicketNumber, Reason, CreatedBy)
        SELECT @Batch, n.PONumber, n.DeliveryNo, n.SourceSeqNo, n.SeqNo, n.ProductNo, n.IsPartial, n.QtyBefore, n.ActualQty,
               n.SellingPrice, c.RetGross, c.RetCost, @confirmed,
               CASE WHEN @confirmed = 1 THEN NULLIF(LTRIM(RTRIM(ISNULL(@tkVatEx, ''))), '') END, @parmreason, @parmuser
        FROM #NewReturns AS n
        INNER JOIN #RetCost AS c ON c.SeqNo = n.SeqNo;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------
-- 5. Commit only if everything is in place (a failed CREATE leaves the transaction open in SSMS)
-- ----------------------------------------------------------------
IF @@TRANCOUNT = 0
    RAISERROR('An earlier step failed and its transaction was rolled back; nothing was changed.', 16, 1);
ELSE IF OBJECT_ID('dbo.sp_ReturnSalesOrder', 'P') IS NULL OR OBJECT_ID('dbo.spu_SO_SplitDeliveryLine', 'P') IS NULL
     OR OBJECT_ID('dbo.SalesReturnLog', 'U') IS NULL
     OR NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID('dbo.sp_ReturnSalesOrder') AND name = '@ReturnQty')
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('NOT APPLIED: a procedure or the log table is missing after the script ran; everything was rolled back.', 16, 1);
END
ELSE
BEGIN
    COMMIT TRANSACTION;
    PRINT 'Applied.';
END
GO
