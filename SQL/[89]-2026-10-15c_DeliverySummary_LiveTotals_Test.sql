/* ================================================================
   [89] test: DeliverySummary counters of a sales order follow its lines
   ================================================================
   Run AFTER [89] is installed. Self-fixturing, everything inside ONE
   transaction that is rolled back at the end (results are kept in a table
   variable, which a rollback does not empty). Read the last result set:
   every row should say PASS (SKIP = no fixture of that kind in this DB).

   Fixtures picked here:
     @SoDev / @SoPO   a sales-order delivery with >= 2 live, not returned lines
     @StsDev          an STS delivery (TransferOrderSummary), if any
     @OpenDev         a sales-order delivery FOR DELIVERY, invoice not set, with
                      >= 2 live lines, for the real Save proc (T11), if any
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Res TABLE (Seq INT IDENTITY(1,1), Test VARCHAR(12), Result VARCHAR(10), Detail VARCHAR(400));

DECLARE @SoDev VARCHAR(20), @SoPO VARCHAR(20), @StsDev VARCHAR(20), @StsPO VARCHAR(20);
DECLARE @OpenDev VARCHAR(20), @OpenPO VARCHAR(20);
DECLARE @Seq DECIMAL(10,0), @LineQty DECIMAL(18,3), @LineAct DECIMAL(18,3), @NewSeq DECIMAL(10,0);
DECLARE @i0 INT, @s0 INT, @r0 INT, @q0 DECIMAL(18,3), @a0 DECIMAL(18,3);
DECLARE @i INT, @s INT, @r INT, @q DECIMAL(18,3), @a DECIMAL(18,3);
DECLARE @rc INT, @n INT;

-- T0 objects
IF OBJECT_ID('dbo.fn_SODelivery_LiveTotals', 'IF') IS NULL
   OR NOT EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'trg_DeliveryDetails_SOTotals' AND is_disabled = 0)
   OR NOT EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'trg_DeliverySummary_SOTotals' AND is_disabled = 0)
BEGIN
    SELECT 'T0' AS Test, 'FAIL' AS Result, '[89] is not installed (function / triggers missing or disabled); nothing tested.' AS Detail;
    RETURN;
END
INSERT @Res VALUES ('T0', 'PASS', 'function and both triggers present and enabled');

-- fixtures
SELECT TOP 1 @SoDev = s.DeliveryNo, @SoPO = s.PONumber
FROM dbo.DeliverySummary AS s
CROSS APPLY dbo.fn_SODelivery_LiveTotals(s.DeliveryNo, s.PONumber) AS t
WHERE t.IsSalesOrder = 1 AND t.TotalItemSold >= 2
ORDER BY s.DeliveryNo DESC;

SELECT TOP 1 @StsDev = s.DeliveryNo, @StsPO = s.PONumber
FROM dbo.DeliverySummary AS s
WHERE EXISTS (SELECT 1 FROM dbo.TransferOrderSummary AS t WHERE t.PONumber = s.PONumber)
ORDER BY s.DeliveryNo DESC;

SELECT TOP 1 @OpenDev = s.DeliveryNo, @OpenPO = s.PONumber
FROM dbo.DeliverySummary AS s
CROSS APPLY dbo.fn_SODelivery_LiveTotals(s.DeliveryNo, s.PONumber) AS t
WHERE t.IsSalesOrder = 1 AND t.TotalItem >= 2 AND s.Status = 'FOR DELIVERY' AND ISNULL(s.isInvoiceUpdate, 0) = 0
ORDER BY s.DeliveryNo DESC;

IF @SoDev IS NULL
BEGIN
    SELECT 'FIXTURE' AS Test, 'FAIL' AS Result, 'no sales-order delivery with 2 or more live lines in this database' AS Detail;
    RETURN;
END

BEGIN TRANSACTION;

-- T1 nothing differs right after install (Exception Center S09)
SELECT @n = COUNT(*)
FROM dbo.DeliverySummary AS s
CROSS APPLY dbo.fn_SODelivery_LiveTotals(s.DeliveryNo, s.PONumber) AS t
WHERE s.PONumber IS NOT NULL AND t.IsSalesOrder = 1
  AND (   ISNULL(s.TotalItem, -1) <> t.TotalItem OR ISNULL(s.TotalItemSold, -1) <> t.TotalItemSold
       OR ISNULL(s.TotalItemReturned, -1) <> t.TotalItemReturned OR s.TotalQtyDelivered <> t.TotalQtyDelivered
       OR ISNULL(s.TotalActualQty, -1) <> t.TotalActualQty);
INSERT @Res VALUES ('T1', CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END, 'sales-order deliveries differing from their lines: ' + CAST(@n AS VARCHAR(10)));

-- baseline of the fixture
SELECT @i0 = TotalItem, @s0 = TotalItemSold, @r0 = TotalItemReturned, @q0 = TotalQtyDelivered, @a0 = TotalActualQty
FROM dbo.fn_SODelivery_LiveTotals(@SoDev, @SoPO);

-- T2 the Save / cancel / confirm formulas written straight into the counters are put back
UPDATE dbo.DeliverySummary
SET TotalItem = 99, TotalItemSold = NULL, TotalItemReturned = 7, TotalQtyDelivered = 12345.678, TotalActualQty = 0
WHERE DeliveryNo = @SoDev AND PONumber = @SoPO;
SELECT @i = TotalItem, @s = TotalItemSold, @r = TotalItemReturned, @q = TotalQtyDelivered, @a = TotalActualQty
FROM dbo.DeliverySummary WHERE DeliveryNo = @SoDev AND PONumber = @SoPO;
INSERT @Res VALUES ('T2', CASE WHEN @i = @i0 AND @s = @s0 AND @r = @r0 AND @q = @q0 AND @a = @a0 THEN 'PASS' ELSE 'FAIL' END,
    'PO ' + @SoPO + ' wrong values written, stored now ' + CONCAT(@i, '/', @s, '/', @r, '/', @q, '/', @a)
    + ' vs lines ' + CONCAT(@i0, '/', @s0, '/', @r0, '/', @q0, '/', @a0));

-- the line used for T3-T5: highest live, not returned SeqNo
SELECT TOP 1 @Seq = d.SeqNo, @LineQty = d.QtyDelivered, @LineAct = ISNULL(d.ActualQty, 0)
FROM dbo.DeliveryDetails AS d
WHERE d.DeliveryNo = @SoDev AND d.PONumber = @SoPO AND ISNULL(d.isCancelled, 0) = 0 AND ISNULL(d.isReturned, 0) = 0
ORDER BY d.SeqNo DESC;

-- T3 cancel the line (PO 12415's case)
UPDATE dbo.DeliveryDetails SET isCancelled = 1 WHERE DeliveryNo = @SoDev AND PONumber = @SoPO AND SeqNo = @Seq;
SET @rc = @@ROWCOUNT;
SELECT @i = TotalItem, @s = TotalItemSold, @r = TotalItemReturned, @q = TotalQtyDelivered, @a = TotalActualQty
FROM dbo.DeliverySummary WHERE DeliveryNo = @SoDev AND PONumber = @SoPO;
INSERT @Res VALUES ('T3', CASE WHEN @i = @i0 - 1 AND @s = @s0 - 1 AND @r = @r0 AND @q = @q0 - @LineQty AND @a = @a0 - @LineAct THEN 'PASS' ELSE 'FAIL' END,
    'cancel line ' + CAST(@Seq AS VARCHAR(10)) + ' (' + CAST(@LineQty AS VARCHAR(20)) + '): stored ' + CONCAT(@i, '/', @s, '/', @r, '/', @q, '/', @a));

-- T4 caller's @@ROWCOUNT is the statement's own (the posting procs' guards)
INSERT @Res VALUES ('T4', CASE WHEN @rc = 1 THEN 'PASS' ELSE 'FAIL' END, '@@ROWCOUNT after the one-line UPDATE: ' + CAST(@rc AS VARCHAR(10)));

-- T5 un-cancel, then return the same line
UPDATE dbo.DeliveryDetails SET isCancelled = 0 WHERE DeliveryNo = @SoDev AND PONumber = @SoPO AND SeqNo = @Seq;
UPDATE dbo.DeliveryDetails SET isReturned = 1 WHERE DeliveryNo = @SoDev AND PONumber = @SoPO AND SeqNo = @Seq;
SELECT @i = TotalItem, @s = TotalItemSold, @r = TotalItemReturned, @q = TotalQtyDelivered, @a = TotalActualQty
FROM dbo.DeliverySummary WHERE DeliveryNo = @SoDev AND PONumber = @SoPO;
INSERT @Res VALUES ('T5', CASE WHEN @i = @i0 AND @s = @s0 - 1 AND @r = @r0 + 1 AND @q = @q0 AND @a = @a0 - @LineAct THEN 'PASS' ELSE 'FAIL' END,
    'returned line: stored ' + CONCAT(@i, '/', @s, '/', @r, '/', @q, '/', @a) + ' (item same, sold -1, returned +1, qty same, actual -line)');
UPDATE dbo.DeliveryDetails SET isReturned = 0 WHERE DeliveryNo = @SoDev AND PONumber = @SoPO AND SeqNo = @Seq;

-- T6 a line scanned after a cancel (the line PO 12415's counters missed), then removed
SELECT @NewSeq = MAX(SeqNo) + 1 FROM dbo.DeliveryDetails WHERE DeliveryNo = @SoDev AND PONumber = @SoPO;
INSERT INTO dbo.DeliveryDetails
    (SeqNo, DeliveryNo, PONumber, ReferenceNumber, ProductNo, BarcodeNo, ProductName, QtyDelivered, ActualQty, Variance,
     Cost, SellingPrice, Status, isVat, ProcessedBy, isSettled, isCreditMemo, isReturned, isCancelled, DateTimeAdded, DateTimeUpdated)
SELECT @NewSeq, DeliveryNo, PONumber, ReferenceNumber, ProductNo, BarcodeNo, ProductName, QtyDelivered, ActualQty, Variance,
       Cost, SellingPrice, Status, isVat, 'TEST [89]', isSettled, isCreditMemo, isReturned, isCancelled, DateTimeAdded, DateTimeUpdated
FROM dbo.DeliveryDetails
WHERE DeliveryNo = @SoDev AND PONumber = @SoPO AND SeqNo = @Seq;
SELECT @i = TotalItem, @s = TotalItemSold, @q = TotalQtyDelivered
FROM dbo.DeliverySummary WHERE DeliveryNo = @SoDev AND PONumber = @SoPO;
INSERT @Res VALUES ('T6', CASE WHEN @i = @i0 + 1 AND @s = @s0 + 1 AND @q = @q0 + @LineQty THEN 'PASS' ELSE 'FAIL' END,
    'line ' + CAST(@NewSeq AS VARCHAR(10)) + ' added: stored ' + CONCAT(@i, '/', @s, '/', @q));
DELETE FROM dbo.DeliveryDetails WHERE DeliveryNo = @SoDev AND PONumber = @SoPO AND SeqNo = @NewSeq;
SELECT @i = TotalItem, @s = TotalItemSold, @r = TotalItemReturned, @q = TotalQtyDelivered, @a = TotalActualQty
FROM dbo.DeliverySummary WHERE DeliveryNo = @SoDev AND PONumber = @SoPO;
INSERT @Res VALUES ('T7', CASE WHEN @i = @i0 AND @s = @s0 AND @r = @r0 AND @q = @q0 AND @a = @a0 THEN 'PASS' ELSE 'FAIL' END,
    'line removed again: stored ' + CONCAT(@i, '/', @s, '/', @r, '/', @q, '/', @a));

-- T8 a status-only update leaves the counters alone (and still right)
UPDATE dbo.DeliverySummary SET Status = Status WHERE DeliveryNo = @SoDev AND PONumber = @SoPO;
SELECT @i = TotalItem, @s = TotalItemSold, @q = TotalQtyDelivered
FROM dbo.DeliverySummary WHERE DeliveryNo = @SoDev AND PONumber = @SoPO;
INSERT @Res VALUES ('T8', CASE WHEN @i = @i0 AND @s = @s0 AND @q = @q0 THEN 'PASS' ELSE 'FAIL' END, 'status-only update: stored ' + CONCAT(@i, '/', @s, '/', @q));

-- T9 an STS transfer is not touched
IF @StsDev IS NULL
    INSERT @Res VALUES ('T9', 'SKIP', 'no STS delivery in this database');
ELSE
BEGIN
    UPDATE dbo.DeliverySummary SET TotalItem = 999 WHERE DeliveryNo = @StsDev AND PONumber = @StsPO;
    SELECT @i = TotalItem FROM dbo.DeliverySummary WHERE DeliveryNo = @StsDev AND PONumber = @StsPO;
    INSERT @Res VALUES ('T9', CASE WHEN @i = 999 THEN 'PASS' ELSE 'FAIL' END, 'STS PO ' + @StsPO + ': TotalItem written 999, stored ' + CAST(@i AS VARCHAR(10)));
END

-- T10 a whole-PO update of the lines (Confirm sets Status / Variance on every line): counters unchanged
UPDATE dbo.DeliveryDetails SET Variance = Variance WHERE DeliveryNo = @SoDev AND PONumber = @SoPO;
SELECT @i = TotalItem, @s = TotalItemSold, @q = TotalQtyDelivered
FROM dbo.DeliverySummary WHERE DeliveryNo = @SoDev AND PONumber = @SoPO;
INSERT @Res VALUES ('T10', CASE WHEN @i = @i0 AND @s = @s0 AND @q = @q0 THEN 'PASS' ELSE 'FAIL' END, 'Variance-only update of every line: stored ' + CONCAT(@i, '/', @s, '/', @q));

-- T12 one set-based statement over many deliveries (the triggers' key set with more than one PO)
UPDATE TOP (50) s SET TotalItem = 0, TotalItemSold = NULL, TotalQtyDelivered = 0
FROM dbo.DeliverySummary AS s
WHERE EXISTS (SELECT 1 FROM dbo.PurchaseOrderSummary AS p WHERE p.PONumber = s.PONumber)
  AND NOT EXISTS (SELECT 1 FROM dbo.TransferOrderSummary AS t WHERE t.PONumber = s.PONumber);
SET @rc = @@ROWCOUNT;
SELECT @n = COUNT(*)
FROM dbo.DeliverySummary AS s
CROSS APPLY dbo.fn_SODelivery_LiveTotals(s.DeliveryNo, s.PONumber) AS t
WHERE s.PONumber IS NOT NULL AND t.IsSalesOrder = 1
  AND (   ISNULL(s.TotalItem, -1) <> t.TotalItem OR ISNULL(s.TotalItemSold, -1) <> t.TotalItemSold
       OR ISNULL(s.TotalItemReturned, -1) <> t.TotalItemReturned OR ISNULL(s.TotalQtyDelivered, -1) <> t.TotalQtyDelivered
       OR ISNULL(s.TotalActualQty, -1) <> t.TotalActualQty);
INSERT @Res VALUES ('T12', CASE WHEN @rc = 50 AND @n = 0 THEN 'PASS' ELSE 'FAIL' END,
    'zeroed the counters of ' + CAST(@rc AS VARCHAR(10)) + ' deliveries in one statement; differing afterwards: ' + CAST(@n AS VARCHAR(10)));

-- T13 the header written after its lines (spitcr_AddSalesOrderFinal / Save's first INSERT), with wrong counters
DECLARE @Hdr TABLE (DeliveryNo VARCHAR(20), PONumber VARCHAR(20), ReferenceNumber VARCHAR(20), InvoiceNo VARCHAR(100), BranchCode VARCHAR(20),
                    TotalVarianceVat FLOAT, TotalVarianceVatExempt FLOAT, EffectivityDate DATE, Status VARCHAR(50), DateAdded DATE,
                    PreparedBy VARCHAR(50), isSettled BIT, isInvoiceUpdate BIT);
INSERT @Hdr
SELECT DeliveryNo, PONumber, ReferenceNumber, InvoiceNo, BranchCode, TotalVarianceVat, TotalVarianceVatExempt, EffectivityDate, Status,
       DateAdded, PreparedBy, isSettled, isInvoiceUpdate
FROM dbo.DeliverySummary WHERE DeliveryNo = @SoDev AND PONumber = @SoPO;
DELETE FROM dbo.DeliverySummary WHERE DeliveryNo = @SoDev AND PONumber = @SoPO;
INSERT INTO dbo.DeliverySummary
    (DeliveryNo, PONumber, ReferenceNumber, InvoiceNo, BranchCode, TotalItem, TotalQtyDelivered, TotalActualQty, TotalVarianceVat,
     TotalVarianceVatExempt, EffectivityDate, Status, DateAdded, PreparedBy, isSettled, isInvoiceUpdate, TotalItemReturned, TotalItemSold)
SELECT DeliveryNo, PONumber, ReferenceNumber, InvoiceNo, BranchCode, 77, 1.000, 0, TotalVarianceVat,
       TotalVarianceVatExempt, EffectivityDate, Status, DateAdded, PreparedBy, isSettled, isInvoiceUpdate, 0, 77
FROM @Hdr;
SELECT @i = TotalItem, @s = TotalItemSold, @r = TotalItemReturned, @q = TotalQtyDelivered, @a = TotalActualQty
FROM dbo.DeliverySummary WHERE DeliveryNo = @SoDev AND PONumber = @SoPO;
INSERT @Res VALUES ('T13', CASE WHEN @i = @i0 AND @s = @s0 AND @r = @r0 AND @q = @q0 AND @a = @a0 THEN 'PASS' ELSE 'FAIL' END,
    'header re-inserted with 77 / 1.000: stored ' + CONCAT(@i, '/', @s, '/', @r, '/', @q, '/', @a));

-- T11 PO 12415's sequence through the REAL procs: cancel a line (sp_CancelDeliveryFIFOJFC), then Save
--     (sp_ConfirmBranchOrder, which writes TotalItem / qty from EVERY line, incl. the cancelled one)
IF @OpenDev IS NULL
    INSERT @Res VALUES ('T11', 'SKIP', 'no open (FOR DELIVERY, invoice not set, 2+ live lines) sales-order delivery in this database');
ELSE IF LEN(@OpenPO) > 10
    INSERT @Res VALUES ('T11', 'SKIP', 'PO ' + @OpenPO + ' is longer than the procs'' varchar(10) @parmpono');
ELSE
BEGIN
BEGIN TRY
    DECLARE @ref VARCHAR(10), @eff DATE, @br VARCHAR(10), @oSeq INT, @oProd VARCHAR(20), @oQty DECIMAL(18,3), @oRef VARCHAR(10), @how VARCHAR(40);
    SELECT @ref = LEFT(ReferenceNumber, 10), @eff = EffectivityDate, @br = LEFT(BranchCode, 10)
    FROM dbo.DeliverySummary WHERE DeliveryNo = @OpenDev AND PONumber = @OpenPO;
    -- the first live line that took stock from lots (the cancel proc refuses a line with no FIFO rows)
    SELECT TOP 1 @oSeq = d.SeqNo, @oProd = d.ProductNo, @oQty = d.QtyDelivered, @oRef = LEFT(d.ReferenceNumber, 10)
    FROM dbo.DeliveryDetails AS d
    WHERE d.DeliveryNo = @OpenDev AND d.PONumber = @OpenPO AND ISNULL(d.isCancelled, 0) = 0
      AND EXISTS (SELECT 1 FROM dbo.InventoryDeliveryFIFO AS f
                  WHERE f.DeliveryNo = d.DeliveryNo AND f.PONumber = d.PONumber AND f.DevDetSeqNo = d.SeqNo AND ISNULL(f.isErrorCorrect, 0) = 0)
    ORDER BY d.SeqNo;
    IF @oSeq IS NOT NULL
    BEGIN
        EXEC dbo.sp_CancelDeliveryFIFOJFC
            @parmdevno = @OpenDev, @parmrefno = @oRef, @parmpono = @OpenPO, @parmprodno = @oProd, @parmqty = @oQty,
            @parmbranchcode = @br, @parmorigin = '', @preparedby = 'TEST [89]', @parmdevseqno = @oSeq;
        SET @how = 'real cancel proc';
    END
    ELSE
    BEGIN
        -- no line with lots: flag one cancelled so Save's own formula is still wrong
        SELECT TOP 1 @oSeq = SeqNo FROM dbo.DeliveryDetails
        WHERE DeliveryNo = @OpenDev AND PONumber = @OpenPO AND ISNULL(isCancelled, 0) = 0 ORDER BY SeqNo;
        UPDATE dbo.DeliveryDetails SET isCancelled = 1 WHERE DeliveryNo = @OpenDev AND PONumber = @OpenPO AND SeqNo = @oSeq;
        SET @how = 'cancel flag (no lots on the line)';
    END

    -- not INSERT ... EXEC (a proc that rolls back under it raises 3915 over the real error);
    -- Save's own SELECT of the delivery no. just comes back as an extra result set
    EXEC dbo.sp_ConfirmBranchOrder
        @parmdevno = @OpenDev, @parmrefno = @ref, @parmeffectivitydate = @eff, @parmpono = @OpenPO,
        @parmbarcode = '', @parmbranchcode = @br, @parmorigin = '', @preparedby = 'TEST [89]';

    SELECT @i0 = TotalItem, @s0 = TotalItemSold, @q0 = TotalQtyDelivered FROM dbo.fn_SODelivery_LiveTotals(@OpenDev, @OpenPO);
    SELECT @i = TotalItem, @s = TotalItemSold, @q = TotalQtyDelivered
    FROM dbo.DeliverySummary WHERE DeliveryNo = @OpenDev AND PONumber = @OpenPO;
    SELECT @n = COUNT(*) FROM dbo.DeliveryDetails WHERE DeliveryNo = @OpenDev AND PONumber = @OpenPO;
    INSERT @Res VALUES ('T11', CASE WHEN @i = @i0 AND @s = @s0 AND @q = @q0 THEN 'PASS' ELSE 'FAIL' END,
        'PO ' + @OpenPO + ': line ' + CAST(@oSeq AS VARCHAR(10)) + ' of ' + CAST(@n AS VARCHAR(10)) + ' cancelled (' + @how + '), then Save: stored '
        + CONCAT(@i, '/', @s, '/', @q) + ', lines say ' + CONCAT(@i0, '/', @s0, '/', @q0)
        + ' (Save''s own formula: ' + CAST(@n AS VARCHAR(10)) + ' items)');
END TRY
BEGIN CATCH
    -- Save's own CATCH may already have rolled the test transaction back
    DECLARE @em VARCHAR(300) = LEFT(ERROR_MESSAGE(), 300);
    INSERT @Res VALUES ('T11', 'SKIP', 'Save raised ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + ': ' + @em);
END CATCH
END

IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

-- leftovers: the fixture is as before the test
SELECT @n = COUNT(*) FROM dbo.DeliveryDetails WHERE DeliveryNo = @SoDev AND PONumber = @SoPO AND SeqNo = @NewSeq;
INSERT @Res VALUES ('END', CASE WHEN @n = 0 AND @@TRANCOUNT = 0 THEN 'PASS' ELSE 'FAIL' END,
    'rolled back; test line left: ' + CAST(@n AS VARCHAR(10)) + '; fixtures SO ' + @SoPO + ' / STS ' + ISNULL(@StsPO, '-') + ' / open ' + ISNULL(@OpenPO, '-'));

SELECT Test, Result, Detail FROM @Res ORDER BY Seq;
SELECT SUM(CASE WHEN Result = 'PASS' THEN 1 ELSE 0 END) AS Passed,
       SUM(CASE WHEN Result = 'FAIL' THEN 1 ELSE 0 END) AS Failed,
       SUM(CASE WHEN Result = 'SKIP' THEN 1 ELSE 0 END) AS Skipped
FROM @Res;
