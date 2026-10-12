/* ================================================================
   2026-10-05: FIFO (Auto / By Shipment) skips only STICKERED lots
   ================================================================
   Replaces the 2026-10-03 rule "FIFO takes only lots with a blank barcode"
   (script 2026-10-03_STS_V2_NoBarcodeFIFO_ReceiveGrouped.sql).

   User rule (2026-10-05): what matters is whether the barcode is a physical
   sticker that will be scanned, not whether a barcode exists.
     Sticker (scan only, FIFO never takes part of it):
       * 'A01...'          received from the supplier (Setup S_LET 'A' / S_NUM '01')
       * 19 characters     received manually in the offline app (all digits)
     Tag only (no sticker; FIFO may take it):
       * 'B01...'          STS receipt / process to primal (func_GenerateBarcodeSTS)
       * 'C01...CVB-...'   conversion output
       * 'D01...'          other tags
       * blank
   Why: a branch receives STS stock with a generated B01 tag barcode; under the
   10-03 rule that stock vanished from every FIFO dropdown at the branch.

   The rule lives in ONE place, dbo.fn_InvIsStickerBarcode, used by:
     sp_InvFIFO_Allocate          (the engine: AUTO / BATCH lines with @SkipBarcodedLots = 1)
     funcview_STSV2_Products      funcview_STSV2_ProductLots
     funcview_SOV2_Products       funcview_SOV2_ProductLots
   spu_InvFIFO_Deduct: only its shortfall message changes. Scanning (LOT mode)
   is unchanged. Partial return (2026-10-04) is unaffected: it tells a scanned
   line by "line barcode = lot barcode".

   funcview_STSV2_ProductLots had been edited on DEV by the user (17:10 today,
   "LEN(Barcode) <> 19"); that version is kept as its _OLD_ backup.

   Needs 2026-10-03_STS_V2_NoBarcodeFIFO_ReceiveGrouped.sql (script 34) and
   its prerequisites: the anchors below are its text (on STAGING since
   2026-10-03 22:56). Without it the patch stops with 59958, nothing changed.
   sp-reviewer 2026-10-05: no blocker; whitespace / case hardening of the rule
   taken (DEV got it through 2026-10-05b, STAGING gets it here).

   Procs are patched by exact anchors (each must occur once) and recreated;
   functions are recreated in full. Backups: _OLD_10052026120000.
   Everything runs in one transaction; the last batch commits only if every
   object exists and uses the new rule.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
BEGIN TRANSACTION;
CREATE TABLE #Patch (Id INT IDENTITY PRIMARY KEY, Obj SYSNAME NOT NULL, OldText NVARCHAR(MAX) NOT NULL, NewText NVARCHAR(MAX) NOT NULL);
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
        THROW 59957, @msg, 1;
    END
    IF EXISTS (SELECT 1 FROM #Patch WHERE Obj = @Obj
               AND (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, OldText, N''))) / DATALENGTH(OldText) <> 1)
    BEGIN
        SET @msg = @Obj + N' text differs from the expected version (an anchor is missing or repeated); nothing changed.';
        THROW 59958, @msg, 1;
    END

    DECLARE @o NVARCHAR(MAX), @n NVARCHAR(MAX);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT OldText, NewText FROM #Patch WHERE Obj = @Obj ORDER BY Id;
    OPEN c; FETCH NEXT FROM c INTO @o, @n;
    WHILE @@FETCH_STATUS = 0 BEGIN SET @def = REPLACE(@def, @o, @n); FETCH NEXT FROM c INTO @o, @n; END
    CLOSE c; DEALLOCATE c;

    DECLARE @old SYSNAME = @Obj + N'_OLD_10052026120000', @full NVARCHAR(300) = N'dbo.' + @Obj;
    EXEC sp_rename @full, @old;
    EXEC (@def);
    IF OBJECT_ID(@full) IS NULL
    BEGIN
        SET @msg = @Obj + N' was not recreated.';
        THROW 59959, @msg, 1;
    END
END
GO

------------------------------------------------------------------
-- 1. The rule
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
IF OBJECT_ID('dbo.fn_InvIsStickerBarcode', 'IF') IS NOT NULL
    EXEC sp_rename 'dbo.fn_InvIsStickerBarcode', 'fn_InvIsStickerBarcode_OLD_10052026120000';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE FUNCTION dbo.fn_InvIsStickerBarcode (@Barcode VARCHAR(120))
RETURNS TABLE
AS
/*
    IsSticker = 1 when the lot carries a physical barcode sticker that is
    scanned (FIFO Auto / By Shipment never takes part of it):
      'A01...'        received from the supplier
      19 characters   received in the offline app
    Everything else (blank, B01 / C01 / D01 tags) is not a sticker.
    The ONE definition of the rule (2026-10-05); change it here only.
    CR / LF / TAB / non-breaking space are stripped first: a scanned or
    imported 19-digit code with a stray trailing character must still count
    as a sticker. 'A01' is compared case-insensitively whatever the collation.
*/
RETURN
    SELECT CAST(CASE WHEN x.b LIKE 'A01%' COLLATE SQL_Latin1_General_CP1_CI_AS OR LEN(x.b) = 19 THEN 1 ELSE 0 END AS BIT) AS IsSticker
    FROM (SELECT LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(@Barcode, ''),
                 CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), CHAR(160), ''))) AS b) AS x;
GO

------------------------------------------------------------------
-- 2. Engine
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
INSERT #Patch (Obj, OldText, NewText) VALUES
(N'sp_InvFIFO_Allocate',
 N'              AND (@Mode = ''LOT'' OR ISNULL(@SkipBarcodedLots, 0) = 0 OR NULLIF(LTRIM(RTRIM(l.Barcode)), '''') IS NULL)',
 N'              AND (@Mode = ''LOT'' OR ISNULL(@SkipBarcodedLots, 0) = 0
                   OR NOT EXISTS (SELECT 1 FROM dbo.fn_InvIsStickerBarcode(l.Barcode) AS sb WHERE sb.IsSticker = 1))   -- 2026-10-05: skip stickered lots only'),
(N'spu_InvFIFO_Deduct',
 N'N'' (FIFO takes only stock without a barcode; scan barcoded stock)''',
 N'N'' (FIFO does not take stickered stock, A01 / 19-digit barcodes; scan those)''');
EXEC #ApplyPatch N'sp_InvFIFO_Allocate';
EXEC #ApplyPatch N'spu_InvFIFO_Deduct';
GO

------------------------------------------------------------------
-- 3. FIFO dropdowns (STS V2 + Sales V2)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC sp_rename 'dbo.funcview_STSV2_Products', 'funcview_STSV2_Products_OLD_10052026120000';
EXEC sp_rename 'dbo.funcview_STSV2_ProductLots', 'funcview_STSV2_ProductLots_OLD_10052026120000';
EXEC sp_rename 'dbo.funcview_SOV2_Products', 'funcview_SOV2_Products_OLD_10052026120000';
EXEC sp_rename 'dbo.funcview_SOV2_ProductLots', 'funcview_SOV2_ProductLots_OLD_10052026120000';
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
    2026-10-05: stickered lots (fn_InvIsStickerBarcode) don't count; they are
    scanned. Tag barcodes (B01 / C01 / D01) and blank count.
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
                 CROSS APPLY dbo.fn_InvIsStickerBarcode(e.Barcode) AS sb
                 WHERE e.Product = t.ProductCode
                   AND sb.IsSticker = 0) AS a
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
    2026-10-05: stickered lots (fn_InvIsStickerBarcode) are left out; tag
    barcodes (B01 / C01 / D01) and blank are listed.
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
    CROSS APPLY dbo.fn_InvIsStickerBarcode(e.Barcode) AS sb
    WHERE sb.IsSticker = 0
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
    2026-10-05: stickered lots (fn_InvIsStickerBarcode) don't count; tag
    barcodes (B01 / C01 / D01) and blank count.
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
                 CROSS APPLY dbo.fn_InvIsStickerBarcode(e.Barcode) AS sb
                 WHERE e.Product = o.ProductCode
                   AND sb.IsSticker = 0) AS a
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
    2026-10-05: stickered lots (fn_InvIsStickerBarcode) are left out; tag
    barcodes (B01 / C01 / D01) and blank are listed.
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
    CROSS APPLY dbo.fn_InvIsStickerBarcode(e.Barcode) AS sb
    WHERE sb.IsSticker = 0
      AND EXISTS (SELECT 1 FROM dbo.PurchaseOrderDetails AS o
                  WHERE o.PONumber = @PONumber AND o.ProductCode = e.Product)
    GROUP BY e.Product, ISNULL(e.ShipmentNo, ''), ISNULL(e.ReferenceCode, '');
GO

------------------------------------------------------------------
-- 4. Commit only if every object exists and uses the new rule
------------------------------------------------------------------
IF @@TRANCOUNT = 0
    RAISERROR('An earlier step failed and its transaction was rolled back; nothing was changed.', 16, 1);
ELSE IF EXISTS (SELECT 1
                FROM (VALUES ('fn_InvIsStickerBarcode'), ('sp_InvFIFO_Allocate'), ('funcview_STSV2_Products'),
                             ('funcview_STSV2_ProductLots'), ('funcview_SOV2_Products'), ('funcview_SOV2_ProductLots')) AS v(n)
                WHERE OBJECT_ID('dbo.' + v.n) IS NULL
                   OR (v.n <> 'fn_InvIsStickerBarcode' AND OBJECT_DEFINITION(OBJECT_ID('dbo.' + v.n)) NOT LIKE '%fn_InvIsStickerBarcode%'))
     OR OBJECT_DEFINITION(OBJECT_ID('dbo.spu_InvFIFO_Deduct')) NOT LIKE '%FIFO does not take stickered stock%'
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('NOT APPLIED: an object is missing or still on the old rule after the script ran; everything was rolled back.', 16, 1);
END
ELSE
BEGIN
    COMMIT TRANSACTION;
    PRINT 'Applied.';
END
GO
SET NOEXEC OFF;
GO
