/* ================================================================
   2026-10-03: STS V2 / Sales V2 FIFO takes only lots with no barcode;
               STS FIFO receive is summed per product, written per line + batch
   ================================================================
   Needs 13 (engine), 14 + 24 (STS V2), 26 (per-lot receive), 27 (Sales V2).
   Grouping is opt-in, so an exe from before this change keeps working exactly as
   today (one row per line): it still reads funcview_InventoryDeliveryFIFOForReceiving
   (unchanged) and calls spu_PostSTSReceiveFromFIFO without @GroupedRows. The new exe
   (Orders/ReceivedSTS.cs + HOFormsDevEx/ReceivedSTSBatchModeFIFO.cs) reads the new
   ...ForReceivingV2, passes @GroupedRows = 1, and returns an unticked summed row
   line by line.

   User rules (2026-10-03):
   - FIFO (Auto / By Shipment) offers and takes only lots whose Inventory.Barcode is
     blank, so it never takes part of a lot someone will scan later. Scanning is
     unchanged (it needs a barcoded lot). Same for Sales V2 (same engine).
   - FIFO placements keep their generated sticker barcode (func_GenerateBarcodeSTS).
   - Receiving: FIFO lines of one product show as ONE row (added up); a scanned line
     stays its own row (scanned lines sharing one lot barcode show as one row).
     The received qty fills the row's lines in line order, then each line's batches
     (ShipmentNo + ReferenceCode + cost) in dispatch order; a short comes off the last
     line / batch, an over receipt goes on the last one.
   - One ReceivedOrderDetails / branch Inventory / InventoryLedger row per line and
     batch (it was one per lot: PO 13764 line 2 = 5 rows of 20 kg from one batch).

   Objects
     sp_InvFIFO_Allocate, spu_InvFIFO_Deduct, sp_InvFIFO_Preview   + @SkipBarcodedLots BIT = 0 (patched)
     spu_PostSTSLineV2, spu_PostSOLineV2                           pass @SkipBarcodedLots = 1 (patched)
     funcview_STSV2_Products / _ProductLots, funcview_SOV2_Products / _ProductLots   recreated, no-barcode lots
     funcview_STSReceiveLines                                      NEW: receivable lines + their group
     funcview_InventoryDeliveryFIFOForReceivingV2                  NEW: one row per group (new exe)
     spu_PostSTSReceiveFromFIFO                                    recreated: + @GroupedRows BIT = 0;
                                                                   group (or line) -> lines -> batches
     sp_ConfirmBranchRecievedOrderJFC                              patched: ActualQty = the line's receipt rows added up;
                                                                   TotalItem = lines received
   One transaction; backups <name>_OLD_10032026140000.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- A failed check or step sets NOEXEC ON, so no later batch runs (SSMS keeps going after an
-- error in one batch; a CREATE batch must not run outside the transaction). Last batch: NOEXEC OFF.
DECLARE @pre NVARCHAR(200) =
    CASE WHEN OBJECT_ID('dbo.funcview_STSReceiveLines') IS NOT NULL
              THEN N'Already applied (dbo.funcview_STSReceiveLines exists).'
         WHEN OBJECT_ID('dbo.spu_PostSOLineV2') IS NULL OR OBJECT_ID('dbo.spu_PostSTSLineV2') IS NULL OR OBJECT_ID('dbo.spu_InvFIFO_Deduct') IS NULL
              THEN N'Run scripts 13, 14, 24 and 27 first.'
         WHEN ISNULL(CHARINDEX(N'per source LOT', OBJECT_DEFINITION(OBJECT_ID('dbo.spu_PostSTSReceiveFromFIFO'))), 0) = 0
              THEN N'Run 2026-10-02b_STS_ReceiveFIFO_PerLot.sql first.'
         WHEN EXISTS (SELECT 1 FROM sys.objects WHERE name LIKE '%[_]OLD[_]10032026140000')
              THEN N'Backups _OLD_10032026140000 already exist; nothing changed.' END;
IF @pre IS NOT NULL
BEGIN
    RAISERROR(@pre, 16, 1);
    SET NOEXEC ON;
    RETURN;
END

CREATE TABLE #Patch (Id INT IDENTITY PRIMARY KEY, Obj SYSNAME NOT NULL, OldText NVARCHAR(MAX) NOT NULL, NewText NVARCHAR(MAX) NOT NULL);
BEGIN TRANSACTION;
GO

------------------------------------------------------------------
-- Helper: patch one procedure by exact anchors (each must occur once), back it up, recreate it
------------------------------------------------------------------
CREATE PROCEDURE #ApplyPatch @Obj SYSNAME
AS
BEGIN
    DECLARE @def NVARCHAR(MAX) = REPLACE(OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + @Obj)), NCHAR(13) + NCHAR(10), NCHAR(10));
    DECLARE @msg NVARCHAR(400);
    IF @def IS NULL
    BEGIN
        SET @msg = N'Cannot read the definition of ' + @Obj + N'; nothing changed.';
        THROW 59954, @msg, 1;
    END
    IF EXISTS (SELECT 1 FROM #Patch WHERE Obj = @Obj
               AND (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, OldText, N''))) / DATALENGTH(OldText) <> 1)
    BEGIN
        SET @msg = @Obj + N' text differs from the expected version (an anchor is missing or repeated); nothing changed.';
        THROW 59955, @msg, 1;
    END

    DECLARE @o NVARCHAR(MAX), @n NVARCHAR(MAX);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT OldText, NewText FROM #Patch WHERE Obj = @Obj ORDER BY Id;
    OPEN c; FETCH NEXT FROM c INTO @o, @n;
    WHILE @@FETCH_STATUS = 0 BEGIN SET @def = REPLACE(@def, @o, @n); FETCH NEXT FROM c INTO @o, @n; END
    CLOSE c; DEALLOCATE c;

    DECLARE @old SYSNAME = @Obj + N'_OLD_10032026140000', @full NVARCHAR(300) = N'dbo.' + @Obj;
    EXEC sp_rename @full, @old;
    EXEC (@def);
    IF OBJECT_ID(@full) IS NULL
    BEGIN
        SET @msg = @Obj + N' was not recreated.';
        THROW 59956, @msg, 1;
    END
END
GO

------------------------------------------------------------------
-- 1. Engine: optional "skip barcoded lots" for AUTO / BATCH lines
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
INSERT #Patch (Obj, OldText, NewText) VALUES
(N'sp_InvFIFO_Allocate',
 N'CREATE PROCEDURE dbo.sp_InvFIFO_Allocate
AS',
 N'CREATE PROCEDURE dbo.sp_InvFIFO_Allocate
    @SkipBarcodedLots BIT = 0   -- 2026-10-03: AUTO / BATCH lines skip lots that have a barcode (LOT = a scanned lot, always allowed)
AS'),
(N'sp_InvFIFO_Allocate',
 N'                   OR  @Mode = ''AUTO'')
        )',
 N'                   OR  @Mode = ''AUTO'')
              AND (@Mode = ''LOT'' OR ISNULL(@SkipBarcodedLots, 0) = 0 OR NULLIF(LTRIM(RTRIM(l.Barcode)), '''') IS NULL)
        )');
EXEC #ApplyPatch N'sp_InvFIFO_Allocate';
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
INSERT #Patch (Obj, OldText, NewText) VALUES
(N'spu_InvFIFO_Deduct',
 N'    @User              VARCHAR(60)
AS',
 N'    @User              VARCHAR(60),
    @SkipBarcodedLots  BIT          = 0          -- 2026-10-03: AUTO / BATCH lines take only lots with no barcode
AS'),
(N'spu_InvFIFO_Deduct',
 N'    EXEC dbo.sp_InvFIFO_Allocate;',
 N'    EXEC dbo.sp_InvFIFO_Allocate @SkipBarcodedLots = @SkipBarcodedLots;'),
(N'spu_InvFIFO_Deduct',
 N'             + N'' at branch '' + @BranchCode',
 N'             + CASE WHEN @SkipBarcodedLots = 1 AND r.Mode <> ''LOT'' THEN N'' (FIFO takes only stock without a barcode; scan barcoded stock)'' ELSE N'''' END
             + N'' at branch '' + @BranchCode');
EXEC #ApplyPatch N'spu_InvFIFO_Deduct';
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
INSERT #Patch (Obj, OldText, NewText) VALUES
(N'sp_InvFIFO_Preview',
 N'    @AlreadyStaged dbo.tt_InvRestoreLot READONLY   -- qty already staged on screen, per lot
AS',
 N'    @AlreadyStaged dbo.tt_InvRestoreLot READONLY,  -- qty already staged on screen, per lot
    @SkipBarcodedLots BIT = 0                      -- 2026-10-03: same as spu_InvFIFO_Deduct
AS'),
(N'sp_InvFIFO_Preview',
 N'    EXEC dbo.sp_InvFIFO_Allocate;',
 N'    EXEC dbo.sp_InvFIFO_Allocate @SkipBarcodedLots = @SkipBarcodedLots;');
EXEC #ApplyPatch N'sp_InvFIFO_Preview';
GO

------------------------------------------------------------------
-- 2. STS V2 / Sales V2 posts: FIFO never takes a barcoded lot
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
INSERT #Patch (Obj, OldText, NewText) VALUES
(N'spu_PostSTSLineV2',
 N'            @LedgerRemarks     = @LedgerRemarks,
            @User              = @PreparedBy;',
 N'            @LedgerRemarks     = @LedgerRemarks,
            @User              = @PreparedBy,
            @SkipBarcodedLots  = 1;   -- 2026-10-03: AUTO / BATCH take only lots with no barcode (barcoded lots are scanned)'),
(N'spu_PostSOLineV2',
 N'            @LedgerRemarks     = @LedgerRemarks,
            @User              = @PreparedBy;',
 N'            @LedgerRemarks     = @LedgerRemarks,
            @User              = @PreparedBy,
            @SkipBarcodedLots  = 1;   -- 2026-10-03: AUTO / BATCH take only lots with no barcode (barcoded lots are scanned)');
EXEC #ApplyPatch N'spu_PostSTSLineV2';
EXEC #ApplyPatch N'spu_PostSOLineV2';
GO

------------------------------------------------------------------
-- 3. FIFO dropdowns: only lots with no barcode
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC sp_rename 'dbo.funcview_STSV2_Products', 'funcview_STSV2_Products_OLD_10032026140000';
EXEC sp_rename 'dbo.funcview_STSV2_ProductLots', 'funcview_STSV2_ProductLots_OLD_10032026140000';
EXEC sp_rename 'dbo.funcview_SOV2_Products', 'funcview_SOV2_Products_OLD_10032026140000';
EXEC sp_rename 'dbo.funcview_SOV2_ProductLots', 'funcview_SOV2_ProductLots_OLD_10032026140000';
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE FUNCTION dbo.funcview_STSV2_Products (@OriginBranch VARCHAR(5), @PONumber VARCHAR(10))
RETURNS TABLE
AS
/*
    Products requested on the transfer that can be picked FIFO Auto:
    those with eligible stock at the origin, plus combo (InventoryMapping)
    parents, whose availability is checked on their components at post.
    2026-10-03: only lots with no barcode count (FIFO never takes a barcoded
    lot; those are scanned).
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
                 WHERE e.Product = t.ProductCode
                   AND NULLIF(LTRIM(RTRIM(e.Barcode)), '') IS NULL) AS a
    CROSS APPLY (SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM dbo.InventoryMapping AS m
                                                WHERE m.ParentProductCode = t.ProductCode)
                                  THEN 1 ELSE 0 END AS BIT) AS IsCombo) AS c
    WHERE ISNULL(a.Available, 0) > 0 OR c.IsCombo = 1;
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE FUNCTION dbo.funcview_STSV2_ProductLots (@OriginBranch VARCHAR(5), @PONumber VARCHAR(10))
RETURNS TABLE
AS
/*
    One row per batch (Product + ShipmentNo + ReferenceCode) of a requested
    product with eligible stock at the origin. ValueMember = LotKey
    'Product||ShipmentNo||ReferenceCode' (CLAUDE.md Known Bug Pattern #7).
    2026-10-03: only lots with no barcode (FIFO never takes a barcoded lot).
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
    WHERE NULLIF(LTRIM(RTRIM(e.Barcode)), '') IS NULL
      AND EXISTS (SELECT 1 FROM dbo.TransferOrderDetails AS t
                  WHERE t.PONumber = @PONumber AND t.ProductCode = e.Product)
    GROUP BY e.Product, ISNULL(e.ShipmentNo, ''), ISNULL(e.ReferenceCode, '');
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE FUNCTION dbo.funcview_SOV2_Products (@OriginBranch VARCHAR(5), @PONumber VARCHAR(10))
RETURNS TABLE
AS
/*
    Products on the sales order that can be picked FIFO Auto: those with
    eligible stock at the origin (fn_InvEligibleLots: Available > 0 AND
    IsWarehouse = 1), plus combo parents (checked on their components at post).
    2026-10-03: only lots with no barcode count (FIFO never takes a barcoded lot).
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
                 WHERE e.Product = o.ProductCode
                   AND NULLIF(LTRIM(RTRIM(e.Barcode)), '') IS NULL) AS a
    CROSS APPLY (SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM dbo.InventoryMapping AS m
                                                WHERE m.ParentProductCode = o.ProductCode)
                                  THEN 1 ELSE 0 END AS BIT) AS IsCombo) AS c
    WHERE ISNULL(a.Available, 0) > 0 OR c.IsCombo = 1;
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE FUNCTION dbo.funcview_SOV2_ProductLots (@OriginBranch VARCHAR(5), @PONumber VARCHAR(10))
RETURNS TABLE
AS
/*
    One row per batch (Product + ShipmentNo + ReferenceCode) of an ordered
    product with eligible stock at the origin. ValueMember = LotKey
    'Product||ShipmentNo||ReferenceCode' (CLAUDE.md Known Bug Pattern #7).
    2026-10-03: only lots with no barcode (FIFO never takes a barcoded lot).
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
    WHERE NULLIF(LTRIM(RTRIM(e.Barcode)), '') IS NULL
      AND EXISTS (SELECT 1 FROM dbo.PurchaseOrderDetails AS o
                  WHERE o.PONumber = @PONumber AND o.ProductCode = e.Product)
    GROUP BY e.Product, ISNULL(e.ShipmentNo, ''), ISNULL(e.ReferenceCode, '');
GO

------------------------------------------------------------------
-- 4. Receivable lines and their groups (shared by the screen and the post)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE FUNCTION dbo.funcview_STSReceiveLines (@PONumber VARCHAR(10))
RETURNS TABLE
AS
/*
    One row per STS line still to receive (live FIFO lots, no receipt row for
    its barcode yet), with the row of the receive screen it belongs to:
      LineKind 'SCAN' = taken by scanning a lot (a lot of the line carries the
                        line's barcode); grouped by barcode (normally 1 line)
      LineKind 'FIFO' = taken by FIFO Auto / By Shipment (generated sticker
                        barcode); grouped by product
      GroupSeqNo      = the smallest SeqNo in the group = the screen row's SeqNo
    Callers: funcview_InventoryDeliveryFIFOForReceivingV2, spu_PostSTSReceiveFromFIFO,
             HOFormsDevEx/ReceivedSTSBatchModeFIFO.cs (returning a summed row).
    2026-10-03.
*/
RETURN
    SELECT
        x.SeqNo, x.DeliveryNo, x.PONumber, x.ReferenceNumber, x.ProductNo, x.ProductName, x.BarcodeNo,
        x.QtyDelivered, x.Cost, x.SellingPrice, x.isVat, x.LineKind,
        MIN(x.SeqNo) OVER (PARTITION BY x.DeliveryNo, x.LineKind, x.GroupKey) AS GroupSeqNo,
        COUNT(*)     OVER (PARTITION BY x.DeliveryNo, x.LineKind, x.GroupKey) AS GroupLineCount
    FROM (
        SELECT
            CAST(dd.SeqNo AS INT) AS SeqNo,
            dd.DeliveryNo, dd.PONumber, dd.ReferenceNumber, dd.ProductNo, dd.ProductName, dd.BarcodeNo,
            q.QtyDelivered, dd.Cost, dd.SellingPrice, dd.isVat,
            k.LineKind,
            CASE k.LineKind WHEN 'SCAN' THEN ISNULL(dd.BarcodeNo, '') ELSE dd.ProductNo END AS GroupKey
        FROM dbo.DeliveryDetails AS dd
        -- only FIFO rows whose source lot exists (the receive needs its ShipmentNo / ReferenceCode)
        CROSS APPLY (SELECT CAST(SUM(f.QtyDelivered) AS DECIMAL(18,3)) AS QtyDelivered
                     FROM dbo.InventoryDeliveryFIFO AS f
                     INNER JOIN dbo.Inventory AS src ON src.SequenceNumber = f.SequenceReferenceNumber
                     WHERE f.DeliveryNo = dd.DeliveryNo AND f.PONumber = dd.PONumber
                       AND f.DevDetSeqNo = dd.SeqNo AND f.isErrorCorrect = 0) AS q
        CROSS APPLY (SELECT CASE WHEN EXISTS (
                                     SELECT 1
                                     FROM dbo.InventoryDeliveryFIFO AS f
                                     INNER JOIN dbo.Inventory AS i ON i.SequenceNumber = f.SequenceReferenceNumber
                                     WHERE f.DeliveryNo = dd.DeliveryNo AND f.PONumber = dd.PONumber
                                       AND f.DevDetSeqNo = dd.SeqNo AND f.isErrorCorrect = 0
                                       AND NULLIF(LTRIM(RTRIM(i.Barcode)), '') IS NOT NULL
                                       AND i.Barcode = dd.BarcodeNo)
                                 THEN 'SCAN' ELSE 'FIFO' END AS LineKind) AS k
        WHERE dd.PONumber = @PONumber
          AND dd.isReturned = 0
          AND dd.isCancelled = 0
          AND q.QtyDelivered > 0
          AND NOT EXISTS (SELECT 1 FROM dbo.ReceivedOrderDetails AS r
                          WHERE r.PONumber = dd.PONumber AND r.Barcode = dd.BarcodeNo)
    ) AS x;
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE FUNCTION dbo.funcview_InventoryDeliveryFIFOForReceivingV2
(
    @PONumber VARCHAR(10)
)
RETURNS TABLE
AS
/*
    Rows for the STS FIFO receive screen (HOFormsDevEx/ReceivedSTSBatchModeFIFO),
    2026-10-03: ONE ROW PER GROUP of funcview_STSReceiveLines -- each scanned
    line on its own, and the FIFO lines of a product added up into one row.
    SeqNo = the group's first line (spu_PostSTSReceiveFromFIFO @GroupedRows = 1
    spreads the row's qty over the group's lines); BarcodeNo = that line's barcode;
    LineKind SCAN / FIFO, LineCount = lines in the row.
    Cost = the group's weighted line cost. Source* = the group's largest lot.
    Same columns as funcview_InventoryDeliveryFIFOForReceiving (one row per line,
    kept unchanged for exes from before 2026-10-03) plus LineKind / LineCount.
    Callers: Orders/ReceivedSTS.cs -> ReceivedSTSBatchModeFIFO (new exe).
*/
RETURN
(
    SELECT
        g.SeqNo,
        g.DeliveryNo,
        g.PONumber,
        g.ReferenceNumber,
        g.ProductNo,
        g.ProductName,
        g.BarcodeNo,
        g.LineKind,
        g.LineCount,
        g.QtyDelivered,
        g.QtyDelivered AS ActualQty,
        g.Cost,
        g.SellingPrice,
        g.isVat,
        src.ReferenceCode AS SourceReferenceCode,
        src.ShipmentNo    AS SourceShipmentNo,
        src.Branch        AS SourceBranch
    FROM (
        SELECT
            l.GroupSeqNo                                                          AS SeqNo,
            l.DeliveryNo,
            MAX(l.PONumber)                                                       AS PONumber,
            MAX(CASE WHEN l.SeqNo = l.GroupSeqNo THEN l.ReferenceNumber END)      AS ReferenceNumber,
            MAX(l.ProductNo)                                                      AS ProductNo,
            MAX(CASE WHEN l.SeqNo = l.GroupSeqNo THEN l.ProductName END)          AS ProductName,
            MAX(CASE WHEN l.SeqNo = l.GroupSeqNo THEN l.BarcodeNo END)            AS BarcodeNo,
            MAX(l.LineKind)                                                       AS LineKind,
            COUNT(*)                                                              AS LineCount,
            CAST(SUM(l.QtyDelivered) AS DECIMAL(18,3))                            AS QtyDelivered,
            CAST(ROUND(SUM(l.QtyDelivered * l.Cost) / NULLIF(SUM(l.QtyDelivered), 0), 2) AS DECIMAL(18,2)) AS Cost,
            MAX(CASE WHEN l.SeqNo = l.GroupSeqNo THEN l.SellingPrice END)         AS SellingPrice,
            CAST(MAX(CAST(ISNULL(l.isVat, 0) AS INT)) AS BIT)                     AS isVat
        FROM dbo.funcview_STSReceiveLines(@PONumber) AS l
        GROUP BY l.DeliveryNo, l.GroupSeqNo
    ) AS g
    OUTER APPLY (SELECT TOP (1) i.ReferenceCode, i.ShipmentNo, i.Branch
                 FROM dbo.funcview_STSReceiveLines(@PONumber) AS m
                 INNER JOIN dbo.InventoryDeliveryFIFO AS f
                         ON f.DeliveryNo = m.DeliveryNo AND f.PONumber = m.PONumber
                        AND f.DevDetSeqNo = m.SeqNo AND f.isErrorCorrect = 0
                 INNER JOIN dbo.Inventory AS i ON i.SequenceNumber = f.SequenceReferenceNumber
                 WHERE m.DeliveryNo = g.DeliveryNo AND m.GroupSeqNo = g.SeqNo
                 ORDER BY f.QtyDelivered DESC, f.SequenceReferenceNumber) AS src
);
GO

------------------------------------------------------------------
-- 5. Receive: group -> lines -> batches
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC sp_rename 'dbo.spu_PostSTSReceiveFromFIFO', 'spu_PostSTSReceiveFromFIFO_OLD_10032026140000';
GO
CREATE PROCEDURE dbo.spu_PostSTSReceiveFromFIFO
    @PONumber   VARCHAR(10),
    @BranchCode VARCHAR(10),
    @ReceivedBy VARCHAR(50),
    @Lines      dbo.tt_STSReceiveFIFOLines READONLY,
    @GroupedRows BIT = 0          -- 1 = rows come from ...ForReceivingV2 (new exe)
AS
/*
    Receives the checked rows of the STS FIFO receive screen into the branch
    (2026-10-03).
      - @GroupedRows = 0 (an exe from before 2026-10-03, rows of
        funcview_InventoryDeliveryFIFOForReceiving): each row is one line, with
        its own qty -- exactly as before.
      - @GroupedRows = 1 (rows of funcview_InventoryDeliveryFIFOForReceivingV2):
        a row is a group of funcview_STSReceiveLines; its SeqNo is the group's
        first line, and the row's qty is spread over the group's lines in line
        order (a short comes off the last line, an over receipt goes on it).
        If lines of one group arrive separately, each keeps its own qty.
      - each line's qty fills its batches (ShipmentNo + ReferenceCode + cost)
        in dispatch order; a short comes off the last batch.
    Writes one ReceivedOrderDetails row, one branch Inventory row and one
    InventoryLedger row ('STS RCVD ITEM PO#') per line and batch, and sets the
    line's DeliveryDetails.ActualQty / Variance.

    Returns: one result set -- (SeqNo, Barcode, Reason) for rows skipped
             (already received, or no live lot).
    Callers: HOFormsDevEx/ReceivedSTSBatchModeFIFO.cs (first of its 3 calls;
             sp_ConfirmBranchRecievedOrderJFC then posts IT-BR / STS-SHORT).
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @SkippedLines TABLE (SeqNo INT, Barcode VARCHAR(120), Reason VARCHAR(200));

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM @Lines)
        BEGIN
            SELECT SeqNo, Barcode, Reason FROM @SkippedLines;
            RETURN;
        END

        BEGIN TRANSACTION;

        -- the per-PO lock every STS writer shares (2026-10-01f)
        DECLARE @LockResult INT, @RcvLockRes NVARCHAR(255) = N'STSTRANSIT:' + @PONumber;
        EXEC @LockResult = sp_getapplock
            @Resource = @RcvLockRes, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 30000;
        IF @LockResult < 0
            THROW 58170, 'Could not acquire a lock on this delivery -- another receive is already in progress. Please try again.', 1;

        ------------------------------------------------------------------
        -- 1. What is still receivable (read under the lock)
        ------------------------------------------------------------------
        SELECT SeqNo, DeliveryNo, ProductNo, ProductName, BarcodeNo, QtyDelivered, SellingPrice,
               CAST(ISNULL(isVat, 0) AS BIT) AS LineIsVat, GroupSeqNo
        INTO #RL
        FROM dbo.funcview_STSReceiveLines(@PONumber);

        -- the screen rows, added up per SeqNo (a stale screen can repeat one)
        SELECT SeqNo, DeliveryNo, MAX(Barcode) AS Barcode,
               CAST(SUM(ISNULL(ActualQty, 0)) AS DECIMAL(18,3)) AS RcvQty, MAX(SellingPrice) AS SellingPrice
        INTO #T
        FROM @Lines
        GROUP BY SeqNo, DeliveryNo;

        INSERT INTO @SkippedLines (SeqNo, Barcode, Reason)
        SELECT t.SeqNo, t.Barcode, 'Already received (or no live lot left) -- refresh the screen.'
        FROM #T AS t
        WHERE NOT EXISTS (SELECT 1 FROM #RL AS rl WHERE rl.SeqNo = t.SeqNo AND rl.DeliveryNo = t.DeliveryNo);

        ------------------------------------------------------------------
        -- 2. Request -> lines. Grouped screen: a group's first line sent alone
        --    = the whole group; otherwise each sent line stands for itself.
        ------------------------------------------------------------------
        SELECT t.SeqNo AS ReqSeqNo, t.DeliveryNo, t.RcvQty, t.SellingPrice, rl.GroupSeqNo,
               CASE WHEN ISNULL(@GroupedRows, 0) = 1
                         AND t.SeqNo = rl.GroupSeqNo
                         AND NOT EXISTS (SELECT 1 FROM #T AS t2
                                         INNER JOIN #RL AS r2 ON r2.SeqNo = t2.SeqNo AND r2.DeliveryNo = t2.DeliveryNo
                                         WHERE t2.DeliveryNo = t.DeliveryNo AND r2.GroupSeqNo = rl.GroupSeqNo
                                           AND t2.SeqNo <> t.SeqNo)
                    THEN 1 ELSE 0 END AS WholeGroup
        INTO #Req
        FROM #T AS t
        INNER JOIN #RL AS rl ON rl.SeqNo = t.SeqNo AND rl.DeliveryNo = t.DeliveryNo;

        SELECT q.ReqSeqNo, rl.SeqNo, rl.DeliveryNo, rl.ProductNo, rl.ProductName, rl.BarcodeNo, rl.LineIsVat,
               rl.QtyDelivered, q.RcvQty AS ReqQty, ISNULL(q.SellingPrice, rl.SellingPrice) AS SellingPrice
        INTO #ReqLine
        FROM #Req AS q
        INNER JOIN #RL AS rl
                ON rl.DeliveryNo = q.DeliveryNo
               AND (   (q.WholeGroup = 1 AND rl.GroupSeqNo = q.GroupSeqNo)
                    OR (q.WholeGroup = 0 AND rl.SeqNo = q.ReqSeqNo));

        -- the request's qty over its lines, in line order (short off / over on the last line)
        SELECT r.*,
               CAST(CASE WHEN r.RevNo = 1 THEN CASE WHEN r.ReqQty - r.CumBefore > 0 THEN r.ReqQty - r.CumBefore ELSE 0 END
                         WHEN r.ReqQty - r.CumBefore >= r.QtyDelivered THEN r.QtyDelivered
                         WHEN r.ReqQty - r.CumBefore > 0 THEN r.ReqQty - r.CumBefore
                         ELSE 0 END AS DECIMAL(18,3)) AS LineRcv
        INTO #LineRcv
        FROM (SELECT l.*,
                     ISNULL(SUM(l.QtyDelivered) OVER (PARTITION BY l.DeliveryNo, l.ReqSeqNo ORDER BY l.SeqNo
                                                      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS CumBefore,
                     ROW_NUMBER() OVER (PARTITION BY l.DeliveryNo, l.ReqSeqNo ORDER BY l.SeqNo DESC) AS RevNo
              FROM #ReqLine AS l) AS r;

        ------------------------------------------------------------------
        -- 3. Line -> batches (ShipmentNo + ReferenceCode + cost), dispatch order
        ------------------------------------------------------------------
        SELECT b.*,
               CAST(CASE WHEN b.RevNo = 1 THEN CASE WHEN b.LineRcv - b.CumBefore > 0 THEN b.LineRcv - b.CumBefore ELSE 0 END
                         WHEN b.LineRcv - b.CumBefore >= b.BatchQty THEN b.BatchQty
                         WHEN b.LineRcv - b.CumBefore > 0 THEN b.LineRcv - b.CumBefore
                         ELSE 0 END AS DECIMAL(18,3)) AS RcvQty
        INTO #Batch
        FROM (SELECT x.*,
                     ISNULL(SUM(x.BatchQty) OVER (PARTITION BY x.DeliveryNo, x.SeqNo ORDER BY x.FirstFifo
                                                  ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS CumBefore,
                     ROW_NUMBER() OVER (PARTITION BY x.DeliveryNo, x.SeqNo ORDER BY x.FirstFifo DESC) AS RevNo
              FROM (SELECT lr.DeliveryNo, lr.SeqNo, lr.LineRcv,
                           ISNULL(src.ShipmentNo, '')    AS ShipmentNo,
                           ISNULL(src.ReferenceCode, '') AS ReferenceCode,
                           CAST(f.Cost AS DECIMAL(18,4)) AS BatchCost,
                           CAST(SUM(f.QtyDelivered) AS DECIMAL(18,3)) AS BatchQty,
                           MIN(f.SequenceNumber)          AS FirstFifo,
                           MIN(f.SequenceReferenceNumber) AS FirstLot
                    FROM #LineRcv AS lr
                    INNER JOIN dbo.InventoryDeliveryFIFO AS f
                            ON f.DeliveryNo = lr.DeliveryNo AND f.PONumber = @PONumber
                           AND f.DevDetSeqNo = lr.SeqNo AND f.isErrorCorrect = 0
                    INNER JOIN dbo.Inventory AS src ON src.SequenceNumber = f.SequenceReferenceNumber
                    GROUP BY lr.DeliveryNo, lr.SeqNo, lr.LineRcv, ISNULL(src.ShipmentNo, ''), ISNULL(src.ReferenceCode, ''),
                             CAST(f.Cost AS DECIMAL(18,4))) AS x) AS b;

        -- every line's qty must land on its batches exactly (a line with no source lot
        -- left would otherwise be marked received with no stock / ledger behind it)
        DECLARE @BadSeq INT, @BadMsg NVARCHAR(400);
        SELECT TOP (1) @BadSeq = lr.SeqNo
        FROM #LineRcv AS lr
        OUTER APPLY (SELECT SUM(b.RcvQty) AS Qty FROM #Batch AS b
                     WHERE b.DeliveryNo = lr.DeliveryNo AND b.SeqNo = lr.SeqNo) AS s
        WHERE ISNULL(s.Qty, -1) <> lr.LineRcv
        ORDER BY lr.SeqNo;
        IF @BadSeq IS NOT NULL
        BEGIN
            SET @BadMsg = N'Line ' + CAST(@BadSeq AS NVARCHAR(12)) + N' of PO ' + @PONumber
                        + N' has no source lot to receive against (its head-office lot is missing). Nothing was received.';
            THROW 58171, @BadMsg, 1;
        END

        ------------------------------------------------------------------
        -- 4. Branch stock
        ------------------------------------------------------------------
        -- a branch row pre-created by the (unused) Dispatch Per Barcode module: old single-row update
        SELECT lr.DeliveryNo, lr.SeqNo
        INTO #Pre
        FROM #LineRcv AS lr
        WHERE EXISTS (SELECT 1 FROM dbo.Inventory AS dst
                      WHERE dst.Branch = @BranchCode AND dst.ShipmentNo = lr.DeliveryNo
                        AND dst.Product = lr.ProductNo AND dst.Barcode = lr.BarcodeNo);

        UPDATE dst
        SET dst.ReferenceCode    = (SELECT TOP (1) b.ReferenceCode FROM #Batch AS b
                                    WHERE b.DeliveryNo = lr.DeliveryNo AND b.SeqNo = lr.SeqNo
                                    ORDER BY b.BatchQty DESC, b.FirstFifo),
            dst.Available        = ISNULL(dst.Available, 0) + (lr.LineRcv - ISNULL(dst.Quantity, 0)),
            dst.Quantity         = lr.LineRcv,
            dst.LastMovementDate = GETDATE()
        FROM dbo.Inventory AS dst WITH (UPDLOCK, ROWLOCK)
        INNER JOIN #LineRcv AS lr
                ON dst.Branch = @BranchCode AND dst.ShipmentNo = lr.DeliveryNo
               AND dst.Product = lr.ProductNo AND dst.Barcode = lr.BarcodeNo
        INNER JOIN #Pre AS p ON p.DeliveryNo = lr.DeliveryNo AND p.SeqNo = lr.SeqNo;

        INSERT INTO dbo.Inventory
            (Branch, ShipmentNo, PalletNo, BatchCode, DateReceived, ExpiryDate, Product, Description, Barcode,
             TipWeight, Quantity, Cost, Available, QtyBigBlue, IsStock, IsVat, IsWarehouse, ReferenceCode,
             LastMovementDate, isProcess, isSource, isConversion)
        SELECT @BranchCode, b.ShipmentNo, 0, 0, GETDATE(), NULL, lr.ProductNo, lr.ProductName, lr.BarcodeNo,
               b.RcvQty, b.RcvQty, ROUND(b.BatchCost, 2), b.RcvQty, 0, 1, lr.LineIsVat, 1, b.ReferenceCode,
               GETDATE(), 0, 0, 0
        FROM #Batch AS b
        INNER JOIN #LineRcv AS lr ON lr.DeliveryNo = b.DeliveryNo AND lr.SeqNo = b.SeqNo
        WHERE b.RcvQty > 0
          AND NOT EXISTS (SELECT 1 FROM #Pre AS p WHERE p.DeliveryNo = b.DeliveryNo AND p.SeqNo = b.SeqNo)
        ORDER BY lr.SeqNo, b.FirstFifo;

        ------------------------------------------------------------------
        -- 5. Receipt rows + stock ledger, one per line and batch
        --    (ReceivedOrderDetails.SeqNo = per-PO MAX + 1, safe under the lock)
        ------------------------------------------------------------------
        INSERT INTO dbo.ReceivedOrderDetails
            (SeqNo, PONumber, ProductCode, ProductName, Barcode, Qty, Cost, SellingPrice, IsVat, ReferenceCode)
        SELECT ISNULL((SELECT MAX(SeqNo) FROM dbo.ReceivedOrderDetails WHERE PONumber = @PONumber), 0)
                   + ROW_NUMBER() OVER (ORDER BY lr.SeqNo, b.FirstFifo),
               @PONumber, lr.ProductNo, LEFT(lr.ProductName, 50), lr.BarcodeNo, b.RcvQty,
               ROUND(b.BatchCost, 2), ISNULL(lr.SellingPrice, 0), lr.LineIsVat, LEFT(b.ReferenceCode, 20)
        FROM #Batch AS b
        INNER JOIN #LineRcv AS lr ON lr.DeliveryNo = b.DeliveryNo AND lr.SeqNo = b.SeqNo
        WHERE b.RcvQty > 0;

        INSERT INTO dbo.InventoryLedger
            (SequenceRefNum, OriginBranch, DestinationBranch, DateProcessed, Product, Description,
             BegQty, QtyIN, QtyOut, EndQty, Cost, Remarks, ProcessedBy)
        SELECT b.FirstLot, @BranchCode, @BranchCode, GETDATE(), lr.ProductNo, lr.ProductName,
               0, b.RcvQty, 0, b.RcvQty, b.BatchCost, 'STS RCVD ITEM PO#' + @PONumber, @ReceivedBy
        FROM #Batch AS b
        INNER JOIN #LineRcv AS lr ON lr.DeliveryNo = b.DeliveryNo AND lr.SeqNo = b.SeqNo
        WHERE b.RcvQty > 0
        ORDER BY lr.SeqNo, b.FirstFifo;

        UPDATE dd
        SET dd.ActualQty = lr.LineRcv,
            dd.Variance  = dd.QtyDelivered - lr.LineRcv
        FROM dbo.DeliveryDetails AS dd
        INNER JOIN #LineRcv AS lr ON lr.SeqNo = dd.SeqNo AND lr.DeliveryNo = dd.DeliveryNo
        WHERE dd.PONumber = @PONumber;

        COMMIT TRANSACTION;

        SELECT SeqNo, Barcode, Reason FROM @SkippedLines;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

------------------------------------------------------------------
-- 6. Confirm: a line's receipt rows added up (one row per batch now)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
INSERT #Patch (Obj, OldText, NewText) VALUES
(N'sp_ConfirmBranchRecievedOrderJFC',
 N'        UPDATE dt
        SET dt.Status = ''DELIVERED'',
            dt.ActualQty = rt.Qty,
            dt.Variance = (dt.QtyDelivered - rt.Qty)
        FROM DeliveryDetails dt
        INNER JOIN ReceivedOrderDetails rt
            ON dt.PONumber = rt.PONumber AND dt.BarcodeNo = rt.Barcode AND dt.ProductNo = rt.ProductCode
        WHERE dt.PONumber = @parmpono AND dt.isCancelled = 0 AND dt.isReturned = 0;',
 N'        -- 2026-10-03: a line can have several receipt rows (one per batch), and scanned lines can
        -- share one lot barcode: the rows of a barcode are added up and fill its lines in SeqNo
        -- order (a short comes off the last line). Lines with no receipt row are left as they are.
        ;WITH L AS (
            SELECT dt.SeqNo, dt.DeliveryNo, dt.QtyDelivered, r.Qty AS RcvTotal,
                   ISNULL(SUM(dt.QtyDelivered) OVER (PARTITION BY dt.DeliveryNo, dt.BarcodeNo, dt.ProductNo ORDER BY dt.SeqNo
                                                     ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS CumBefore,
                   ROW_NUMBER() OVER (PARTITION BY dt.DeliveryNo, dt.BarcodeNo, dt.ProductNo ORDER BY dt.SeqNo DESC) AS RevNo
            FROM DeliveryDetails dt
            CROSS APPLY (SELECT SUM(rt.Qty) AS Qty FROM ReceivedOrderDetails rt
                         WHERE rt.PONumber = dt.PONumber AND rt.Barcode = dt.BarcodeNo AND rt.ProductCode = dt.ProductNo) r
            WHERE dt.PONumber = @parmpono AND dt.isCancelled = 0 AND dt.isReturned = 0 AND r.Qty IS NOT NULL)
        UPDATE dt
        SET dt.Status = ''DELIVERED'',
            dt.ActualQty = a.Qty,
            dt.Variance = (dt.QtyDelivered - a.Qty)
        FROM DeliveryDetails dt
        INNER JOIN (SELECT SeqNo, DeliveryNo,
                           CAST(CASE WHEN RevNo = 1 THEN CASE WHEN RcvTotal - CumBefore > 0 THEN RcvTotal - CumBefore ELSE 0 END
                                     WHEN RcvTotal - CumBefore >= QtyDelivered THEN QtyDelivered
                                     WHEN RcvTotal - CumBefore > 0 THEN RcvTotal - CumBefore
                                     ELSE 0 END AS DECIMAL(18,3)) AS Qty
                    FROM L) a ON a.SeqNo = dt.SeqNo AND a.DeliveryNo = dt.DeliveryNo
        WHERE dt.PONumber = @parmpono AND dt.isCancelled = 0 AND dt.isReturned = 0;'),
(N'sp_ConfirmBranchRecievedOrderJFC',
 N'        SET TotalItem = (SELECT ISNULL(COUNT(PONumber), 0) FROM ReceivedOrderDetails WITH (NOLOCK) WHERE PONumber = @parmpono),',
 N'        SET TotalItem = (SELECT COUNT(*) FROM DeliveryDetails dl                       -- 2026-10-03: lines received, not receipt rows
                         WHERE dl.PONumber = @parmpono AND dl.isCancelled = 0 AND dl.isReturned = 0
                           AND EXISTS (SELECT 1 FROM ReceivedOrderDetails rx
                                       WHERE rx.PONumber = dl.PONumber AND rx.Barcode = dl.BarcodeNo AND rx.ProductCode = dl.ProductNo)),');
EXEC #ApplyPatch N'sp_ConfirmBranchRecievedOrderJFC';
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
COMMIT TRANSACTION;
GO

SET NOEXEC OFF;
IF OBJECT_ID('dbo.funcview_STSReceiveLines') IS NULL
    PRINT 'NOT APPLIED -- see the first error above; nothing was changed.';
ELSE
    PRINT 'Applied.';
SELECT name, CONVERT(VARCHAR(19), modify_date, 120) AS modified
FROM sys.objects
WHERE name IN ('sp_InvFIFO_Allocate', 'spu_InvFIFO_Deduct', 'sp_InvFIFO_Preview', 'spu_PostSTSLineV2', 'spu_PostSOLineV2',
               'funcview_STSV2_Products', 'funcview_STSV2_ProductLots', 'funcview_SOV2_Products', 'funcview_SOV2_ProductLots',
               'funcview_STSReceiveLines', 'funcview_InventoryDeliveryFIFOForReceivingV2', 'spu_PostSTSReceiveFromFIFO',
               'sp_ConfirmBranchRecievedOrderJFC')
ORDER BY name;
