/* ================================================================
   2026-09-29b: Inventory FIFO deduction engine (standard, phase 1)
   ================================================================
   See docs/standards/2026-09-29_Inventory_FIFO_Deduction_Standard.md.
   One shared engine for every inventory-reducing post. Nothing existing
   calls it yet; first caller is the new STS V2 module
   (2026-09-29c_STS_V2_FIFOEngine.sql). All objects are NEW -- no existing
   object is renamed or altered.

   Rules implemented (decided with the user 2026-09-29):
     * Eligible lot (one definition, fn_InvEligibleLots):
         Branch = @Branch AND Available > 0 AND IsWarehouse = 1.
       IsWarehouse matters for ENZO (HO stock in 3rd-party storage is
       IsWarehouse = 0 until pulled into the commissary). IsStock is NOT a
       filter (legacy procs never cleared it); the engine still maintains
       it (0 when a lot empties, 1 when restored).
     * FIFO = oldest SequenceNumber first.
     * Modes per line:
         LOT   - one specific lot (a scanned barcode); partial qty allowed.
         BATCH - one batch, Product + ShipmentNo + ReferenceCode (never
                 ShipmentNo alone - CLAUDE.md Known Bug Pattern #7).
         AUTO  - any eligible lot of the product at the branch.
       Allocation order inside one call: LOT lines, then BATCH, then AUTO,
       each by LineID, so a specific pick is never starved by an AUTO line.
     * All-or-nothing: a shortfall THROWs (never BREAKs / posts partially).
       Lots are locked (UPDLOCK) BEFORE they are allocated, and the deduct
       is guarded by Available >= Qty + @@ROWCOUNT.
     * Cost is read from Inventory.Cost under the lock, never from the
       client.
     * Every lot touched gets an InventoryLedger row.
     * The engine never changes ShipmentNo / ReferenceCode / Barcode / Cost.
     * The engine does not own a transaction: the caller (a module's
       spu_Post...) opens it, calls the engine once, and commits.

   Error numbers 59800-59819:
     59800 no caller transaction          59805 lot changed concurrently
     59801 qty must be > 0                59806 caller temp table missing
     59802 invalid mode / missing key     59807 no lines
     59804 insufficient stock             59808 restore exceeds lot Quantity
     59809 restore lot not found at branch
     59810 product lock timeout (another post of the same product in progress)

   Review follow-ups (sp-reviewer, 2026-09-30): IsWarehouse is re-checked on
   the locked row; per-product applocks are taken in ProductCode order
   (sp_InvFIFO_LockProducts) before any lot row lock, so concurrent posts
   sharing products serialize instead of deadlocking.

   Objects:
     dbo.tt_InvDeductLine        TVP  (request lines)
     dbo.tt_InvRestoreLot        TVP  (lots + qty to put back)
     dbo.fn_InvEligibleLots      inline TVF
     dbo.fn_InvExpandBOM         inline TVF (InventoryMapping parent -> children)
     dbo.sp_InvFIFO_Allocate     internal: allocation core (temp tables)
     dbo.sp_InvFIFO_LockProducts internal: ordered per-product applocks
     dbo.sp_InvFIFO_Preview      read-only preview (no locks, no writes)
     dbo.spu_InvFIFO_Deduct      the engine
     dbo.spu_InvFIFO_Restore     reversal helper

   Deploy to COREX001 (DEV) first; STAGING only after the user confirms.
   ================================================================ */

-- ----------------------------------------------------------------
-- Types (new; created only if missing)
-- ----------------------------------------------------------------
IF TYPE_ID('dbo.tt_InvDeductLine') IS NULL
    CREATE TYPE dbo.tt_InvDeductLine AS TABLE
    (
        LineID         INT           NOT NULL PRIMARY KEY,
        ProductCode    VARCHAR(10)   NOT NULL,
        Qty            DECIMAL(18,3) NOT NULL,
        Mode           VARCHAR(5)    NOT NULL,   -- LOT / BATCH / AUTO
        InventorySeqNo INT           NULL,       -- LOT
        ShipmentNo     VARCHAR(10)   NULL,       -- BATCH (NULL = '')
        ReferenceCode  VARCHAR(100)  NULL        -- BATCH (NULL = '')
    );
GO

IF TYPE_ID('dbo.tt_InvRestoreLot') IS NULL
    CREATE TYPE dbo.tt_InvRestoreLot AS TABLE
    (
        InventorySeqNo INT           NOT NULL,
        Qty            DECIMAL(18,3) NOT NULL
    );
GO

-- ----------------------------------------------------------------
-- fn_InvEligibleLots -- the ONE definition of a deductible lot
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.fn_InvEligibleLots', 'IF') IS NOT NULL
    EXEC sp_rename 'dbo.fn_InvEligibleLots', 'fn_InvEligibleLots_OLD_09292026110000';
GO

CREATE FUNCTION dbo.fn_InvEligibleLots (@BranchCode VARCHAR(5))
RETURNS TABLE
AS
/*
    Lots at @BranchCode that FIFO may take from. Used by the engine (which
    then locks the returned rows by SequenceNumber), the preview, and the
    module dropdowns -- so every screen and every post agree on "available".
*/
RETURN
    SELECT
        i.SequenceNumber,
        i.Branch,
        i.Product,
        i.ShipmentNo,
        i.ReferenceCode,
        i.Barcode,
        i.Description,
        i.Available,
        i.Cost,
        i.IsVat,
        i.DateReceived
    FROM dbo.Inventory AS i
    WHERE i.Branch      = @BranchCode
      AND i.Available   > 0
      AND i.IsWarehouse = 1;
GO

-- ----------------------------------------------------------------
-- fn_InvExpandBOM -- parent product -> component lines
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.fn_InvExpandBOM', 'IF') IS NOT NULL
    EXEC sp_rename 'dbo.fn_InvExpandBOM', 'fn_InvExpandBOM_OLD_09292026110000';
GO

CREATE FUNCTION dbo.fn_InvExpandBOM (@ProductCode VARCHAR(10), @Qty DECIMAL(18,3))
RETURNS TABLE
AS
/*
    A product mapped in InventoryMapping (a combo) expands to its children
    (recipe Quantity x @Qty); anything else returns itself. Same expansion
    as sp_FiFoMappingSTS[_JFC] (InventoryMapping.Status is not filtered,
    matching them). Callers expand BEFORE the engine so the stock check
    covers the children, not the parent.
*/
RETURN
    SELECT
        CAST(RTRIM(m.ChildProductCode) AS VARCHAR(10)) AS ProductCode,
        CAST(m.Quantity * @Qty AS DECIMAL(18,3))       AS Qty,
        CAST(1 AS BIT)                                 AS IsComponent
    FROM dbo.InventoryMapping AS m
    WHERE m.ParentProductCode = @ProductCode
    UNION ALL
    SELECT @ProductCode, @Qty, CAST(0 AS BIT)
    WHERE NOT EXISTS (SELECT 1 FROM dbo.InventoryMapping AS m2 WHERE m2.ParentProductCode = @ProductCode);
GO

-- ----------------------------------------------------------------
-- sp_InvFIFO_Allocate -- allocation core (internal)
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_InvFIFO_Allocate', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_InvFIFO_Allocate', 'sp_InvFIFO_Allocate_OLD_09292026110000';
GO

CREATE PROCEDURE dbo.sp_InvFIFO_Allocate
AS
/*
    Internal -- called only by sp_InvFIFO_Preview and spu_InvFIFO_Deduct,
    which create and fill these temp tables first:
        #InvReq  (LineID PK, ProductCode, Qty, Mode, InventorySeqNo,
                  ShipmentNo, ReferenceCode, Allocated)
        #InvLots (SequenceNumber PK, Product, ShipmentNo, ReferenceCode,
                  Barcode, Description, Available, Remaining, Cost, IsVat)
        #InvPick (PickID IDENTITY, LineID, SequenceNumber, Qty)
    Validates the request lines, then fills #InvPick oldest-first and sets
    #InvReq.Allocated. Does NOT decide what a shortfall means -- the preview
    reports it, the engine throws.
    Loops over request LINES (a handful); lots are allocated set-based with
    a running total (works at compatibility level 120).
*/
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#InvReq') IS NULL OR OBJECT_ID('tempdb..#InvLots') IS NULL OR OBJECT_ID('tempdb..#InvPick') IS NULL
        THROW 59806, 'sp_InvFIFO_Allocate: caller must create #InvReq, #InvLots and #InvPick.', 1;

    IF NOT EXISTS (SELECT 1 FROM #InvReq)
        THROW 59807, 'No inventory lines to process.', 1;

    IF EXISTS (SELECT 1 FROM #InvReq WHERE Qty IS NULL OR Qty <= 0)
        THROW 59801, 'Quantity must be greater than zero on every line.', 1;

    IF EXISTS (SELECT 1 FROM #InvReq
               WHERE Mode NOT IN ('LOT', 'BATCH', 'AUTO')
                  OR NULLIF(LTRIM(RTRIM(ProductCode)), '') IS NULL
                  OR (Mode = 'LOT' AND InventorySeqNo IS NULL))
        THROW 59802, 'Invalid inventory line: Mode must be LOT, BATCH or AUTO, a product is required, and LOT needs an InventorySeqNo.', 1;

    DECLARE @LineID INT, @Mode VARCHAR(5), @Product VARCHAR(10), @Need DECIMAL(18,3),
            @Seq INT, @Ship VARCHAR(10), @Ref VARCHAR(100);

    DECLARE line_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT LineID, Mode, ProductCode, Qty, InventorySeqNo, ISNULL(ShipmentNo, ''), ISNULL(ReferenceCode, '')
        FROM #InvReq
        ORDER BY CASE Mode WHEN 'LOT' THEN 1 WHEN 'BATCH' THEN 2 ELSE 3 END, LineID;

    OPEN line_cur;
    FETCH NEXT FROM line_cur INTO @LineID, @Mode, @Product, @Need, @Seq, @Ship, @Ref;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        ;WITH Cand AS
        (
            SELECT l.SequenceNumber,
                   l.Remaining,
                   SUM(l.Remaining) OVER (ORDER BY l.SequenceNumber ROWS UNBOUNDED PRECEDING) AS Cum
            FROM #InvLots AS l
            WHERE l.Remaining > 0
              AND l.Product = @Product
              AND (   (@Mode = 'LOT'   AND l.SequenceNumber = @Seq)
                   OR (@Mode = 'BATCH' AND ISNULL(l.ShipmentNo, '') = @Ship AND ISNULL(l.ReferenceCode, '') = @Ref)
                   OR  @Mode = 'AUTO')
        )
        INSERT INTO #InvPick (LineID, SequenceNumber, Qty)
        SELECT @LineID,
               c.SequenceNumber,
               CASE WHEN c.Cum <= @Need THEN c.Remaining ELSE @Need - (c.Cum - c.Remaining) END
        FROM Cand AS c
        WHERE c.Cum - c.Remaining < @Need       -- lots before this one don't already cover the need
        ORDER BY c.SequenceNumber;

        UPDATE l
        SET l.Remaining = l.Remaining - p.Qty
        FROM #InvLots AS l
        INNER JOIN #InvPick AS p ON p.SequenceNumber = l.SequenceNumber
        WHERE p.LineID = @LineID;

        UPDATE #InvReq
        SET Allocated = ISNULL((SELECT SUM(p.Qty) FROM #InvPick AS p WHERE p.LineID = @LineID), 0)
        WHERE LineID = @LineID;

        FETCH NEXT FROM line_cur INTO @LineID, @Mode, @Product, @Need, @Seq, @Ship, @Ref;
    END

    CLOSE line_cur;
    DEALLOCATE line_cur;
END
GO

-- ----------------------------------------------------------------
-- sp_InvFIFO_Preview -- read-only preview for staging screens
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_InvFIFO_Preview', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_InvFIFO_Preview', 'sp_InvFIFO_Preview_OLD_09292026110000';
GO

CREATE PROCEDURE dbo.sp_InvFIFO_Preview
    @BranchCode    VARCHAR(5),
    @Lines         dbo.tt_InvDeductLine READONLY,
    @AlreadyStaged dbo.tt_InvRestoreLot READONLY   -- qty already staged on screen, per lot
AS
/*
    Same allocation as spu_InvFIFO_Deduct, without locks or writes.
    Result set 1: one row per allocated lot
        LineID, InventorySeqNo, Barcode, ProductCode, Description,
        ShipmentNo, ReferenceCode, Qty, Cost
    Result set 2: one row per requested line
        LineID, ProductCode, RequestedQty, AllocatedQty, ShortQty
    A shortfall is REPORTED (ShortQty > 0), not thrown and not silently
    truncated. A lot partly used by already-staged lines is still offered
    with what's left of it.
    Callers: none yet (replaces sp_Get{StockOut,Inventory}FIFOBreakdown[ByShipment]
    when Stock Out / Conversion move onto the engine).
*/
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #InvReq (LineID INT NOT NULL PRIMARY KEY, ProductCode VARCHAR(10) NOT NULL, Qty DECIMAL(18,3) NULL,
                          Mode VARCHAR(5) NOT NULL, InventorySeqNo INT NULL, ShipmentNo VARCHAR(10) NULL,
                          ReferenceCode VARCHAR(100) NULL, Allocated DECIMAL(18,3) NOT NULL DEFAULT 0);
    CREATE TABLE #InvLots (SequenceNumber INT NOT NULL PRIMARY KEY, Product VARCHAR(10) NOT NULL, ShipmentNo VARCHAR(10) NULL,
                           ReferenceCode VARCHAR(100) NULL, Barcode VARCHAR(35) NULL, Description VARCHAR(300) NULL,
                           Available DECIMAL(18,3) NOT NULL, Remaining DECIMAL(18,3) NOT NULL,
                           Cost DECIMAL(18,2) NOT NULL, IsVat BIT NOT NULL);
    CREATE TABLE #InvPick (PickID INT IDENTITY(1,1) PRIMARY KEY, LineID INT NOT NULL, SequenceNumber INT NOT NULL, Qty DECIMAL(18,3) NOT NULL);

    INSERT INTO #InvReq (LineID, ProductCode, Qty, Mode, InventorySeqNo, ShipmentNo, ReferenceCode)
    SELECT LineID, ProductCode, Qty, UPPER(Mode), InventorySeqNo, ShipmentNo, ReferenceCode
    FROM @Lines;

    INSERT INTO #InvLots (SequenceNumber, Product, ShipmentNo, ReferenceCode, Barcode, Description, Available, Remaining, Cost, IsVat)
    SELECT e.SequenceNumber, e.Product, e.ShipmentNo, e.ReferenceCode, e.Barcode, e.Description,
           e.Available - ISNULL(s.Qty, 0),
           e.Available - ISNULL(s.Qty, 0),
           ISNULL(e.Cost, 0), ISNULL(e.IsVat, 0)
    FROM dbo.fn_InvEligibleLots(@BranchCode) AS e
    LEFT JOIN (SELECT InventorySeqNo, SUM(Qty) AS Qty FROM @AlreadyStaged GROUP BY InventorySeqNo) AS s
           ON s.InventorySeqNo = e.SequenceNumber
    WHERE e.Product IN (SELECT ProductCode FROM #InvReq)
      AND e.Available - ISNULL(s.Qty, 0) > 0;

    EXEC dbo.sp_InvFIFO_Allocate;

    SELECT p.LineID,
           p.SequenceNumber AS InventorySeqNo,
           l.Barcode,
           l.Product        AS ProductCode,
           l.Description,
           ISNULL(l.ShipmentNo, '')    AS ShipmentNo,
           ISNULL(l.ReferenceCode, '') AS ReferenceCode,
           p.Qty,
           l.Cost
    FROM #InvPick AS p
    INNER JOIN #InvLots AS l ON l.SequenceNumber = p.SequenceNumber
    ORDER BY p.LineID, p.PickID;

    SELECT r.LineID,
           r.ProductCode,
           r.Qty                AS RequestedQty,
           r.Allocated          AS AllocatedQty,
           r.Qty - r.Allocated  AS ShortQty
    FROM #InvReq AS r
    ORDER BY r.LineID;
END
GO

-- ----------------------------------------------------------------
-- sp_InvFIFO_LockProducts -- ordered per-product serialization (internal)
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_InvFIFO_LockProducts', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_InvFIFO_LockProducts', 'sp_InvFIFO_LockProducts_OLD_09302026090000';
GO

CREATE PROCEDURE dbo.sp_InvFIFO_LockProducts
    @BranchCode VARCHAR(5)
AS
/*
    Internal -- called by spu_InvFIFO_Deduct and spu_InvFIFO_Restore inside
    the caller's transaction. Takes an exclusive, transaction-owned applock
    'INVFIFO|<branch>|<product>' for every product in the caller's
    #InvLockKeys (ProductCode PK), in ProductCode order, BEFORE any lot row
    is locked. Every engine call therefore locks products in one global
    order, so two concurrent posts sharing products serialize instead of
    deadlocking. (Legacy procs don't take these locks; they only contend
    on the Inventory rows, as before.)
*/
BEGIN
    SET NOCOUNT ON;

    IF @@TRANCOUNT = 0
        THROW 59800, 'sp_InvFIFO_LockProducts must run inside the caller''s transaction.', 1;

    IF OBJECT_ID('tempdb..#InvLockKeys') IS NULL
        THROW 59806, 'sp_InvFIFO_LockProducts: caller must create #InvLockKeys.', 1;

    DECLARE @Product VARCHAR(10), @Res NVARCHAR(255), @rc INT, @msg NVARCHAR(2048);

    DECLARE lock_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT ProductCode FROM #InvLockKeys ORDER BY ProductCode;

    OPEN lock_cur;
    FETCH NEXT FROM lock_cur INTO @Product;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Res = N'INVFIFO|' + @BranchCode + N'|' + @Product;
        EXEC @rc = sys.sp_getapplock @Resource = @Res, @LockMode = 'Exclusive',
                                     @LockOwner = 'Transaction', @LockTimeout = 15000;
        IF @rc < 0
        BEGIN
            SET @msg = N'Product ' + @Product + N' at branch ' + @BranchCode
                     + N' is being posted by another user right now. Nothing was posted - please try again.';
            THROW 59810, @msg, 1;
        END

        FETCH NEXT FROM lock_cur INTO @Product;
    END

    CLOSE lock_cur;
    DEALLOCATE lock_cur;
END
GO

-- ----------------------------------------------------------------
-- spu_InvFIFO_Deduct -- THE engine
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.spu_InvFIFO_Deduct', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_InvFIFO_Deduct', 'spu_InvFIFO_Deduct_OLD_09292026110000';
GO

CREATE PROCEDURE dbo.spu_InvFIFO_Deduct
    @BranchCode        VARCHAR(5),                 -- branch the stock leaves
    @Lines             dbo.tt_InvDeductLine READONLY,
    @DestinationBranch VARCHAR(5)   = NULL,        -- InventoryLedger.DestinationBranch (default = @BranchCode)
    @LedgerRemarks     VARCHAR(500),               -- InventoryLedger.Remarks, e.g. 'STS IN-TRANSIT PO#-12345'
    @User              VARCHAR(60)
AS
/*
    Runs INSIDE the caller's transaction (THROWs 59800 otherwise) and fills
    the caller's #InvAlloc, one row per (line, lot) taken:

        CREATE TABLE #InvAlloc (
            LineID         INT           NOT NULL,
            InventorySeqNo INT           NOT NULL,
            ProductCode    VARCHAR(10)   NOT NULL,
            Description    VARCHAR(300)  NULL,
            Barcode        VARCHAR(35)   NULL,
            ShipmentNo     VARCHAR(10)   NULL,
            ReferenceCode  VARCHAR(100)  NULL,
            Qty            DECIMAL(18,3) NOT NULL,
            Cost           DECIMAL(18,2) NOT NULL,   -- Inventory.Cost, read under lock
            IsVat          BIT           NOT NULL,
            BegQty         DECIMAL(18,3) NOT NULL,
            EndQty         DECIMAL(18,3) NOT NULL);

    The caller stores what it needs from #InvAlloc in its OWN detail/FIFO
    table (CLAUDE.md: each module keeps its own tables). Rows already in
    #InvAlloc are left alone, so a caller may call the engine twice.
    No TRY/CATCH here on purpose: errors propagate to the caller, whose
    CATCH rolls back its transaction.
*/
BEGIN
    SET NOCOUNT ON;

    IF @@TRANCOUNT = 0
        THROW 59800, 'spu_InvFIFO_Deduct must run inside the caller''s transaction.', 1;

    IF OBJECT_ID('tempdb..#InvAlloc') IS NULL
        THROW 59806, 'spu_InvFIFO_Deduct: caller must create #InvAlloc (see the proc header).', 1;

    CREATE TABLE #InvReq (LineID INT NOT NULL PRIMARY KEY, ProductCode VARCHAR(10) NOT NULL, Qty DECIMAL(18,3) NULL,
                          Mode VARCHAR(5) NOT NULL, InventorySeqNo INT NULL, ShipmentNo VARCHAR(10) NULL,
                          ReferenceCode VARCHAR(100) NULL, Allocated DECIMAL(18,3) NOT NULL DEFAULT 0);
    CREATE TABLE #InvLots (SequenceNumber INT NOT NULL PRIMARY KEY, Product VARCHAR(10) NOT NULL, ShipmentNo VARCHAR(10) NULL,
                           ReferenceCode VARCHAR(100) NULL, Barcode VARCHAR(35) NULL, Description VARCHAR(300) NULL,
                           Available DECIMAL(18,3) NOT NULL, Remaining DECIMAL(18,3) NOT NULL,
                           Cost DECIMAL(18,2) NOT NULL, IsVat BIT NOT NULL);
    CREATE TABLE #InvPick (PickID INT IDENTITY(1,1) PRIMARY KEY, LineID INT NOT NULL, SequenceNumber INT NOT NULL, Qty DECIMAL(18,3) NOT NULL);

    INSERT INTO #InvReq (LineID, ProductCode, Qty, Mode, InventorySeqNo, ShipmentNo, ReferenceCode)
    SELECT LineID, ProductCode, Qty, UPPER(Mode), InventorySeqNo, ShipmentNo, ReferenceCode
    FROM @Lines;

    ------------------------------------------------------------------
    -- 1a. Serialize per (branch, product), taking the product locks in
    --     ProductCode order. Two engine posts that need overlapping
    --     products (e.g. two combos sharing a component) then always lock
    --     in the same order and can't deadlock each other; an ORDER BY on
    --     the row-lock SELECT below would not guarantee lock order.
    --     Released at commit/rollback (@LockOwner = 'Transaction').
    ------------------------------------------------------------------
    CREATE TABLE #InvLockKeys (ProductCode VARCHAR(10) NOT NULL PRIMARY KEY);
    INSERT INTO #InvLockKeys (ProductCode) SELECT DISTINCT ProductCode FROM #InvReq;
    EXEC dbo.sp_InvFIFO_LockProducts @BranchCode = @BranchCode;

    ------------------------------------------------------------------
    -- 1b. Lock the candidate lots, then allocate from the locked values
    --     (the check and the deduction see the same numbers). The
    --     eligibility columns that can change are re-checked on the
    --     locked row, not just in the pre-lock fn_InvEligibleLots read.
    ------------------------------------------------------------------
    INSERT INTO #InvLots (SequenceNumber, Product, ShipmentNo, ReferenceCode, Barcode, Description, Available, Remaining, Cost, IsVat)
    SELECT i.SequenceNumber, i.Product, i.ShipmentNo, i.ReferenceCode, i.Barcode, i.Description,
           i.Available, i.Available, ISNULL(i.Cost, 0), ISNULL(i.IsVat, 0)
    FROM dbo.fn_InvEligibleLots(@BranchCode) AS e
    INNER JOIN dbo.Inventory AS i WITH (UPDLOCK, ROWLOCK)
            ON i.SequenceNumber = e.SequenceNumber
    WHERE e.Product IN (SELECT ProductCode FROM #InvReq)
      AND i.Available   > 0                     -- locked values, not the pre-lock read
      AND i.IsWarehouse = 1;

    ------------------------------------------------------------------
    -- 2. Allocate (validates the lines too)
    ------------------------------------------------------------------
    EXEC dbo.sp_InvFIFO_Allocate;

    ------------------------------------------------------------------
    -- 3. All or nothing
    ------------------------------------------------------------------
    DECLARE @msg NVARCHAR(2048);
    SELECT TOP (1)
        @msg = N'Insufficient stock for product ' + r.ProductCode
             + CASE r.Mode
                   WHEN 'LOT'   THEN N' (scanned lot #' + CONVERT(NVARCHAR(20), r.InventorySeqNo) + N')'
                   WHEN 'BATCH' THEN N' (shipment ' + ISNULL(NULLIF(r.ShipmentNo, ''), N'(blank)')
                                     + ISNULL(N' / ref ' + NULLIF(r.ReferenceCode, ''), N'') + N')'
                   ELSE N''
               END
             + N' at branch ' + @BranchCode
             + N': requested ' + CONVERT(NVARCHAR(30), r.Qty)
             + N', available ' + CONVERT(NVARCHAR(30), r.Allocated) + N'.'
    FROM #InvReq AS r
    WHERE r.Allocated < r.Qty
    ORDER BY r.LineID;

    IF @msg IS NOT NULL
        THROW 59804, @msg, 1;

    ------------------------------------------------------------------
    -- 4. Deduct (guarded) + IsStock maintenance
    ------------------------------------------------------------------
    DECLARE @LotCount INT = (SELECT COUNT(DISTINCT SequenceNumber) FROM #InvPick);

    UPDATE i
    SET i.Available        = i.Available - p.Qty,
        i.IsStock          = CASE WHEN i.Available - p.Qty <= 0 THEN 0 ELSE i.IsStock END,
        i.LastMovementDate = GETDATE()
    FROM dbo.Inventory AS i
    INNER JOIN (SELECT SequenceNumber, SUM(Qty) AS Qty FROM #InvPick GROUP BY SequenceNumber) AS p
            ON p.SequenceNumber = i.SequenceNumber
    WHERE i.Available >= p.Qty;

    IF @@ROWCOUNT <> @LotCount
        THROW 59805, 'A lot changed while posting (another user took the stock). Nothing was posted - please try again.', 1;

    ------------------------------------------------------------------
    -- 5. Result rows (BegQty/EndQty chained when two lines hit one lot)
    --    + InventoryLedger
    ------------------------------------------------------------------
    SELECT p.PickID, p.LineID, p.SequenceNumber, l.Product, l.Description, l.Barcode, l.ShipmentNo, l.ReferenceCode,
           p.Qty, l.Cost, l.IsVat,
           CAST(l.Available
                - SUM(p.Qty) OVER (PARTITION BY p.SequenceNumber ORDER BY p.PickID ROWS UNBOUNDED PRECEDING)
                + p.Qty AS DECIMAL(18,3)) AS BegQty
    INTO #InvOut
    FROM #InvPick AS p
    INNER JOIN #InvLots AS l ON l.SequenceNumber = p.SequenceNumber;

    INSERT INTO #InvAlloc (LineID, InventorySeqNo, ProductCode, Description, Barcode, ShipmentNo, ReferenceCode, Qty, Cost, IsVat, BegQty, EndQty)
    SELECT LineID, SequenceNumber, Product, Description, Barcode, ShipmentNo, ReferenceCode, Qty, Cost, IsVat, BegQty, BegQty - Qty
    FROM #InvOut
    ORDER BY PickID;

    INSERT INTO dbo.InventoryLedger
        (SequenceRefNum, OriginBranch, DestinationBranch, DateProcessed, Product, Description,
         BegQty, QtyIN, QtyOut, EndQty, Cost, Remarks, ProcessedBy)
    SELECT o.SequenceNumber, @BranchCode, ISNULL(@DestinationBranch, @BranchCode), GETDATE(), o.Product, o.Description,
           o.BegQty, 0, o.Qty, o.BegQty - o.Qty, o.Cost, @LedgerRemarks, @User
    FROM #InvOut AS o
    ORDER BY o.PickID;
END
GO

-- ----------------------------------------------------------------
-- spu_InvFIFO_Restore -- put exactly these lots/qty back
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.spu_InvFIFO_Restore', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_InvFIFO_Restore', 'spu_InvFIFO_Restore_OLD_09292026110000';
GO

CREATE PROCEDURE dbo.spu_InvFIFO_Restore
    @BranchCode        VARCHAR(5),                 -- branch the lots belong to
    @Lots              dbo.tt_InvRestoreLot READONLY,
    @DestinationBranch VARCHAR(5)   = NULL,        -- InventoryLedger.DestinationBranch (default = @BranchCode)
    @LedgerRemarks     VARCHAR(500),
    @User              VARCHAR(60)
AS
/*
    Reversal helper: restores exactly the lots and quantities a posting
    saved (never re-runs FIFO). Available += Qty, IsStock = 1, one
    InventoryLedger QtyIN row per lot. Runs inside the caller's
    transaction. Refuses (59808) to push a lot above its original
    Quantity -- on COREX001 no lot has Available > Quantity, so that only
    happens on a double restore.
*/
BEGIN
    SET NOCOUNT ON;

    IF @@TRANCOUNT = 0
        THROW 59800, 'spu_InvFIFO_Restore must run inside the caller''s transaction.', 1;

    IF NOT EXISTS (SELECT 1 FROM @Lots)
        THROW 59807, 'No lots to restore.', 1;

    IF EXISTS (SELECT 1 FROM @Lots WHERE Qty IS NULL OR Qty <= 0)
        THROW 59801, 'Restore quantity must be greater than zero.', 1;

    SELECT InventorySeqNo, SUM(Qty) AS Qty
    INTO #R
    FROM @Lots
    GROUP BY InventorySeqNo;

    -- Same ordered per-product locks as spu_InvFIFO_Deduct, taken before
    -- the lot rows, so a restore and a deduct can't deadlock each other.
    CREATE TABLE #InvLockKeys (ProductCode VARCHAR(10) NOT NULL PRIMARY KEY);
    INSERT INTO #InvLockKeys (ProductCode)
    SELECT DISTINCT i.Product
    FROM dbo.Inventory AS i
    INNER JOIN #R AS r ON r.InventorySeqNo = i.SequenceNumber
    WHERE i.Branch = @BranchCode;
    IF EXISTS (SELECT 1 FROM #InvLockKeys)
        EXEC dbo.sp_InvFIFO_LockProducts @BranchCode = @BranchCode;

    SELECT i.SequenceNumber, i.Product, i.Description,
           CAST(ISNULL(i.Available, 0) AS DECIMAL(18,3)) AS BegQty,
           CAST(ISNULL(i.Quantity, 0)  AS DECIMAL(18,3)) AS LotQty,
           CAST(ISNULL(i.Cost, 0)      AS DECIMAL(18,2)) AS Cost,
           r.Qty
    INTO #RL
    FROM dbo.Inventory AS i WITH (UPDLOCK, ROWLOCK)
    INNER JOIN #R AS r ON r.InventorySeqNo = i.SequenceNumber
    WHERE i.Branch = @BranchCode;

    IF (SELECT COUNT(*) FROM #RL) <> (SELECT COUNT(*) FROM #R)
        THROW 59809, 'A lot to restore was not found at this branch. Nothing was restored.', 1;

    DECLARE @msg NVARCHAR(2048);
    SELECT TOP (1)
        @msg = N'Restoring lot #' + CONVERT(NVARCHAR(20), SequenceNumber) + N' would raise it to '
             + CONVERT(NVARCHAR(30), BegQty + Qty) + N', above its original quantity '
             + CONVERT(NVARCHAR(30), LotQty) + N'. It may already have been returned. Nothing was restored.'
    FROM #RL
    WHERE BegQty + Qty > LotQty
    ORDER BY SequenceNumber;

    IF @msg IS NOT NULL
        THROW 59808, @msg, 1;

    UPDATE i
    SET i.Available        = ISNULL(i.Available, 0) + r.Qty,
        i.IsStock          = 1,
        i.LastMovementDate = GETDATE()
    FROM dbo.Inventory AS i
    INNER JOIN #RL AS r ON r.SequenceNumber = i.SequenceNumber;

    INSERT INTO dbo.InventoryLedger
        (SequenceRefNum, OriginBranch, DestinationBranch, DateProcessed, Product, Description,
         BegQty, QtyIN, QtyOut, EndQty, Cost, Remarks, ProcessedBy)
    SELECT r.SequenceNumber, @BranchCode, ISNULL(@DestinationBranch, @BranchCode), GETDATE(), r.Product, r.Description,
           r.BegQty, r.Qty, 0, r.BegQty + r.Qty, r.Cost, @LedgerRemarks, @User
    FROM #RL AS r
    ORDER BY r.SequenceNumber;
END
GO
