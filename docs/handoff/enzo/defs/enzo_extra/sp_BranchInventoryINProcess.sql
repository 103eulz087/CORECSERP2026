CREATE PROCEDURE [dbo].[sp_BranchInventoryINProcess]
(
    @Items dbo.InventoryINType READONLY,
    @EncodeBy varchar(50) = 'system',
    @Result bit OUTPUT,
    @ResultMessage nvarchar(4000) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -------------------------------------------------------------------
        -- 0) Validate
        -------------------------------------------------------------------
        IF NOT EXISTS (SELECT 1 FROM @Items)
        BEGIN
            SET @Result = 0;
            SET @ResultMessage = N'No items to process.';
            RETURN;
        END;

        IF NOT EXISTS (SELECT 1 FROM @Items WHERE ISNULL(Variance,0) <> 0)
        BEGIN
            SET @Result = 0;
            SET @ResultMessage = N'No variance to process. Inventory already matches the count.';
            RETURN;
        END;

        BEGIN TRAN;

        -------------------------------------------------------------------
        -- 1) Save physical count snapshot (audit) 
        -------------------------------------------------------------------
        INSERT INTO dbo.BranchInventoryIN
        (
            BatchID, BranchCode, Category, ProductCode, Description,
            Ending, NewQty, Variance, DateAdded
        )
        SELECT
            BatchID, BranchCode, Category, ProductCode, Description,
            Ending, NewQty, Variance, GETDATE()
        FROM @Items;

        -------------------------------------------------------------------
        -- 2) Consolidate variance per (BatchID, Branch, Product) into #src
        -------------------------------------------------------------------
        IF OBJECT_ID('tempdb..#src') IS NOT NULL DROP TABLE #src;

        SELECT
            i.BatchID,
            i.BranchCode,
            i.ProductCode,
            MAX(i.Description) AS Description,
            SUM(ISNULL(i.Variance,0)) AS VarQty
        INTO #src
        FROM @Items i
        WHERE ISNULL(i.Variance,0) <> 0
        GROUP BY i.BatchID, i.BranchCode, i.ProductCode;

        -------------------------------------------------------------------
        -- 3) Idempotency: prevent repost of same batch
        --    Using InventoryLedger.SequenceRefNum = BatchID and Remarks like 'INVCOUNT%'
        -------------------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM dbo.InventoryLedger l
            WHERE l.SequenceRefNum IN (SELECT DISTINCT BatchID FROM #src)
              AND l.Remarks LIKE 'INVCOUNT%'
        )
        BEGIN
            ;THROW 50001, 'Batch already processed (duplicate posting).', 1;
        END;

        -------------------------------------------------------------------
        -- 4) Snapshot beginning qty BEFORE adjustments (per Branch+Product)
        -------------------------------------------------------------------
        IF OBJECT_ID('tempdb..#beg') IS NOT NULL DROP TABLE #beg;

        SELECT
            s.BranchCode,
            s.ProductCode,
            BegQty = CAST(ISNULL(SUM(inv.Available), 0) AS float)
        INTO #beg
        FROM #src s
        LEFT JOIN dbo.Inventory inv
          ON inv.Branch  = s.BranchCode
         AND inv.Product = s.ProductCode
        GROUP BY s.BranchCode, s.ProductCode;

        -------------------------------------------------------------------
        -- 5) Negative variance guard: BegQty + VarQty must not go below 0
        -------------------------------------------------------------------
        --IF EXISTS
        --(
        --    SELECT 1
        --    FROM #src s
        --    JOIN #beg b
        --      ON b.BranchCode = s.BranchCode
        --     AND b.ProductCode = s.ProductCode
        --    WHERE (b.BegQty + CAST(s.VarQty AS float)) < 0
        --)
        --BEGIN
        --    ;THROW 50002, 'Insufficient Available stock to apply negative variance for one or more items.', 1;
        --END;

        -------------------------------------------------------------------
        -- 6) Insert into TempInventory (staging/audit)
        --    Quantity = ABS(VarQty), Cost = last known cost, Available mirrors +VarQty only
        -------------------------------------------------------------------
        INSERT INTO dbo.TempInventory
        (
            Branch, ShipmentNo, PalletNo, BatchCode, DateReceived,
            Product, Description, Barcode, TipWeight,
            Quantity, Cost, Available,
            IsStock, IsVat, IsWarehouse,
            ReferenceCode, LastMovementDate,
            isProcess, isSource, isConversion
        )
        SELECT
            s.BranchCode,
            'INVCOUNT' AS ShipmentNo,
            NULL AS PalletNo,
            s.BatchID AS BatchCode,
            CAST(GETDATE() AS date) AS DateReceived,
            s.ProductCode,
            LEFT(s.Description, 75) AS Description,   -- TempInventory.Description is varchar(75)
            NULL AS Barcode,
            NULL AS TipWeight,
            ABS(s.VarQty) AS Quantity,
            COALESCE(lastCost.Cost, 0) AS Cost,
            CASE WHEN s.VarQty > 0 THEN s.VarQty ELSE CAST(0 AS decimal(18,3)) END AS Available,
            1 AS IsStock,
            0 AS IsVat,
            1 AS IsWarehouse,
            CONCAT('INVCOUNT-', s.BatchID) AS ReferenceCode,
            CAST(GETDATE() AS date) AS LastMovementDate,
            0 AS isProcess,
            0 AS isSource,
            0 AS isConversion
        FROM #src s
        OUTER APPLY
        (
            SELECT TOP (1) inv.Cost
            FROM dbo.Inventory inv
            WHERE inv.Branch  = s.BranchCode
              AND inv.Product = s.ProductCode
              AND inv.Cost IS NOT NULL
            ORDER BY inv.DateReceived DESC, inv.SequenceNumber DESC
        ) lastCost;

        -------------------------------------------------------------------
        -- 7) POSITIVE variance -> insert NEW FIFO layer into dbo.Inventory
        -------------------------------------------------------------------
        INSERT INTO dbo.Inventory
        (
            Branch, ShipmentNo, PalletNo, BatchCode, DateReceived, ExpiryDate,
            Product, Description, Barcode, TipWeight,
            Quantity, Cost, Available, QtyBigBlue,
            IsStock, IsVat, IsWarehouse,
            ReferenceCode, LastMovementDate,
            isProcess, isSource, isConversion
        )
        SELECT
            s.BranchCode,
            'INVCOUNT' AS ShipmentNo,
            NULL AS PalletNo,
            s.BatchID AS BatchCode,
            CAST(GETDATE() AS date) AS DateReceived,
            DATEADD(YEAR, 1, CAST(GETDATE() AS date)) AS ExpiryDate,
            s.ProductCode,
            LEFT(s.Description, 300) AS Description,
            NULL AS Barcode,
            NULL AS TipWeight,
            s.VarQty AS Quantity,
            COALESCE(lastCost.Cost, 0) AS Cost,
            s.VarQty AS Available,
            NULL AS QtyBigBlue,
            1 AS IsStock,
            0 AS IsVat,
            1 AS IsWarehouse,
            CONCAT('INVCOUNT+', s.BatchID) AS ReferenceCode,
            CAST(GETDATE() AS date) AS LastMovementDate,
            0 AS isProcess,
            0 AS isSource,
            0 AS isConversion
        FROM #src s
        OUTER APPLY
        (
            SELECT TOP (1) inv.Cost
            FROM dbo.Inventory inv
            WHERE inv.Branch  = s.BranchCode
              AND inv.Product = s.ProductCode
              AND inv.Cost IS NOT NULL
            ORDER BY inv.DateReceived DESC, inv.SequenceNumber DESC
        ) lastCost
        WHERE s.VarQty > 0;

        -------------------------------------------------------------------
        -- 8) NEGATIVE variance -> FIFO consume Available from oldest layers
        --    Save allocations into #alloc so we can compute weighted cost
        -------------------------------------------------------------------
        IF OBJECT_ID('tempdb..#alloc') IS NOT NULL DROP TABLE #alloc;

        ;WITH neg AS
        (
            SELECT
                s.BranchCode,
                s.ProductCode,
                NeedQty = ABS(s.VarQty)
            FROM #src s
            WHERE s.VarQty < 0
        ),
        layers AS
        (
            SELECT
                inv.SequenceNumber,
                inv.Branch,
                inv.Product,
                inv.Available,
                inv.Cost,
                inv.DateReceived,
                n.NeedQty,
                CumAvail =
                    SUM(inv.Available) OVER
                    (
                        PARTITION BY inv.Branch, inv.Product
                        ORDER BY inv.DateReceived, inv.SequenceNumber
                        ROWS UNBOUNDED PRECEDING
                    )
            FROM dbo.Inventory inv
            JOIN neg n
              ON n.BranchCode  = inv.Branch
             AND n.ProductCode = inv.Product
            WHERE inv.Available > 0
        ),
        alloc AS
        (
            SELECT
                SequenceNumber,
                Branch,
                Product,
                Cost,
                DeductQty =
                    CASE
                        WHEN (CumAvail - Available) >= NeedQty THEN 0
                        WHEN CumAvail <= NeedQty THEN Available
                        ELSE NeedQty - (CumAvail - Available)
                    END
            FROM layers
        )
        SELECT
            SequenceNumber,
            Branch,
            Product,
            DeductQty,
            Cost
        INTO #alloc
        FROM alloc
        WHERE DeductQty > 0;

        -- Apply the FIFO deductions
        UPDATE inv
            SET inv.Available        = inv.Available - a.DeductQty,
                inv.LastMovementDate = CAST(GETDATE() AS date)
        FROM dbo.Inventory inv
        JOIN #alloc a
          ON a.SequenceNumber = inv.SequenceNumber;

        -------------------------------------------------------------------
        -- 9) Insert InventoryLedger rows (one per consolidated Branch+Product)
        --    Cost:
        --      + variance => last known cost
        --      - variance => weighted avg cost of consumed layers
        -------------------------------------------------------------------
        INSERT INTO dbo.InventoryLedger
        (
            SequenceRefNum,
            OriginBranch,
            DestinationBranch,
            DateProcessed,
            Product,
            Description,
            BegQty,
            QtyIN,
            QtyOut,
            EndQty,
            Cost,
            Remarks,
            ProcessedBy
        )
        SELECT
            s.BatchID AS SequenceRefNum,
            LEFT(s.BranchCode, 3) AS OriginBranch,
            NULL AS DestinationBranch,
            GETDATE() AS DateProcessed,
            LEFT(s.ProductCode, 5) AS Product,   -- ledger is char(5)
            s.Description,
            b.BegQty AS BegQty,
            CASE WHEN s.VarQty > 0 THEN CAST(s.VarQty AS float) ELSE 0 END AS QtyIN,
            CASE WHEN s.VarQty < 0 THEN CAST(ABS(s.VarQty) AS float) ELSE 0 END AS QtyOut,
            (b.BegQty + CAST(s.VarQty AS float)) AS EndQty,
            CASE
                WHEN s.VarQty > 0 THEN COALESCE(lastCost.Cost, 0)
                WHEN s.VarQty < 0 THEN COALESCE(outCost.AvgCost, 0)
                ELSE 0
            END AS Cost,
            CONCAT('INVCOUNT adjustment Batch ', s.BatchID) AS Remarks,
            @EncodeBy AS ProcessedBy
        FROM #src s
        JOIN #beg b
          ON b.BranchCode = s.BranchCode
         AND b.ProductCode = s.ProductCode
        OUTER APPLY
        (
            SELECT TOP (1) inv.Cost
            FROM dbo.Inventory inv
            WHERE inv.Branch  = s.BranchCode
              AND inv.Product = s.ProductCode
              AND inv.Cost IS NOT NULL
            ORDER BY inv.DateReceived DESC, inv.SequenceNumber DESC
        ) lastCost
        OUTER APPLY
        (
            SELECT
                AvgCost =
                    CASE WHEN SUM(a.DeductQty) = 0 THEN NULL
                         ELSE CAST(SUM(a.DeductQty * CAST(a.Cost AS float)) / SUM(a.DeductQty) AS money)
                    END
            FROM #alloc a
            WHERE a.Branch  = s.BranchCode
              AND a.Product = s.ProductCode
        ) outCost;

        -------------------------------------------------------------------
        -- 10) Mark TempInventory rows as processed (optional)
        -------------------------------------------------------------------
        UPDATE t
            SET t.isProcess = 1,
                t.LastMovementDate = CAST(GETDATE() AS date)
        FROM dbo.TempInventory t
        WHERE t.BatchCode IN (SELECT DISTINCT BatchID FROM #src)
          AND t.ReferenceCode = CONCAT('INVCOUNT-', t.BatchCode);

        COMMIT;

        SET @Result = 1;
        SET @ResultMessage = N'Successfully posted FIFO-safe inventory adjustments based on variance.';

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        SET @Result = 0;
        SET @ResultMessage =
            N'Failed: ' + ERROR_MESSAGE() +
            N' (Line ' + CONVERT(nvarchar(10), ERROR_LINE()) + N')';
    END CATCH
END
