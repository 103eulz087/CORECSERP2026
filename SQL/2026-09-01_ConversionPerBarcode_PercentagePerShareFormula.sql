-- =============================================
-- Author: Eulz Avancena (original); modified 2026-09-01
-- Description: Replaces the old FLAT cost/charge allocation (every
--              non-driploss output line got the identical unit cost
--              @MaterialRate + @ChargeRate, regardless of its own qty) with
--              a percentage-per-share allocation: each non-driploss output
--              line's share of the cost pool is proportional to its own qty
--              relative to the total non-driploss output qty.
--
--              Confirmed against user-supplied worked example (2026-09-01):
--                Source: 4 lots of ProductCode 10015, qty 21/22/23/24,
--                        cost 110/110/120/120 -> TotalSourceQty=90,
--                        TotalSourceCost=10370.
--                Output: ADOBO qty=60, SINIGANG qty=25, SAWDUST qty=5 (driploss).
--                Expected: PercentagePerShare 0.71 / 0.29 / 0 (driploss),
--                          UnitCost(material only) 91.5 / 38.125 / 0,
--                          CuttingShare 141.18 / 58.82 / 0 (CuttingCharge=200),
--                          FinalCost 232.68 / 96.95 / 0.
--
--              Formula (per output line i, non-driploss only):
--                CostBasisQty        = TotalSourceQty - TotalDriploss
--                                       (== SUM(Qty) of non-driploss output
--                                       lines, guaranteed by the existing qty-
--                                       balance check -- doubles as the
--                                       percentage-share divisor, no new
--                                       variable needed for that half)
--                AdjustedDivisor     = CostBasisQty - TotalDriploss
--                                       (confirmed intentional double
--                                       subtraction of driploss qty -- this is
--                                       NOT the same as CostBasisQty; verified
--                                       against the worked example, the ONLY
--                                       divisor that reproduces 91.5/38.125
--                                       exactly)
--                MaterialRate        = TotalSourceCost / AdjustedDivisor
--                PercentagePerShare_i = Qty_i / CostBasisQty
--                UnitCost_i          = (MaterialRate + CuttingCharge) * PercentagePerShare_i
--                TotalCost_i         = Qty_i * UnitCost_i
--              Driploss lines: PercentagePerShare/UnitCost/TotalCost all 0,
--              unchanged from the existing driploss-still-creates-Inventory
--              behavior (2026-09-01_ConversionPerBarcode_DriplossCreatesSellableInventory.sql).
--
--              ChargeRatePerLine (header/audit column) keeps storing
--              CuttingCharge/NonDriplossLines as an "if split evenly"
--              informational figure only -- it is NO LONGER used in the
--              actual per-line cost calculation (that's now entirely
--              percentage-share driven), but the column is left populated
--              rather than dropped/nulled to avoid a schema change and keep
--              existing Posted-tab/report queries working.
-- =============================================

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.spu_PostConversionBarcode', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_PostConversionBarcode', 'spu_PostConversionBarcode_OLD_09012026210000';
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE dbo.spu_PostConversionBarcode
    @ConversionRefNo VARCHAR(20),
    @BranchCode      VARCHAR(50),
    @ConversionType  VARCHAR(20),
    @CuttingCharge   DECIMAL(18,2),
    @ConvertedBy     VARCHAR(50),
    @SourceLines     dbo.tt_ConversionBarcodeSourceLines READONLY,
    @OutputLines     dbo.tt_ConversionBarcodeOutputLines READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        ------------------------------------------------------------------
        -- 1. Validate everything BEFORE any write
        ------------------------------------------------------------------
        IF @ConversionType NOT IN ('OneToMany', 'ManyToOne')
            THROW 59201, 'Invalid conversion type.', 1;

        IF NOT EXISTS (SELECT 1 FROM @SourceLines)
            THROW 59202, 'No source items scanned.', 1;

        IF NOT EXISTS (SELECT 1 FROM @OutputLines)
            THROW 59203, 'No destination items entered.', 1;

        IF EXISTS (SELECT 1 FROM dbo.ConversionBarcodeSummary WHERE ConversionRefNo = @ConversionRefNo)
            THROW 59204, 'This Conversion Reference Number has already been posted.', 1;

        IF @ConversionType = 'OneToMany' AND
           (SELECT COUNT(DISTINCT ProductCode) FROM @SourceLines) <> 1
            THROW 59205, 'One To Many conversion requires all scanned source items to be the same product.', 1;

        IF @ConversionType = 'ManyToOne' AND
           (SELECT COUNT(*) FROM @OutputLines WHERE IsDriploss = 0) <> 1
            THROW 59206, 'Many To One conversion requires exactly one non-driploss destination product.', 1;

        ------------------------------------------------------------------
        -- 2. Self-accumulate totals -- never trust a caller-supplied total
        ------------------------------------------------------------------
        DECLARE
            @TotalSourceQty   DECIMAL(18,3),
            @TotalSourceCost  DECIMAL(18,2),
            @TotalDriploss    DECIMAL(18,3),
            @TotalNonDriploss DECIMAL(18,3),
            @NonDriplossLines INT,
            @CostBasisQty     DECIMAL(18,3),
            @AdjustedDivisor  DECIMAL(18,3),
            @MaterialRate     DECIMAL(18,6),
            @ChargeRate       DECIMAL(18,6),
            @PercentagePerShare DECIMAL(18,6);

        SELECT
            @TotalSourceQty  = SUM(Qty),
            @TotalSourceCost = SUM(Qty * Cost)
        FROM @SourceLines;

        SELECT @TotalDriploss = ISNULL(SUM(Qty), 0)
        FROM @OutputLines WHERE IsDriploss = 1;

        SELECT
            @TotalNonDriploss = ISNULL(SUM(Qty), 0),
            @NonDriplossLines = COUNT(*)
        FROM @OutputLines WHERE IsDriploss = 0;

        IF @NonDriplossLines = 0
            THROW 59207, 'At least one non-driploss destination product is required.', 1;

        ------------------------------------------------------------------
        -- 3. Qty balance check
        ------------------------------------------------------------------
        IF (@TotalNonDriploss + @TotalDriploss) <> @TotalSourceQty
            THROW 59208, 'Destination quantity (including driploss) must equal total scanned source quantity.', 1;

        SET @CostBasisQty = @TotalSourceQty - @TotalDriploss;
        IF @CostBasisQty <= 0
            THROW 59209, 'Cost basis quantity (source qty minus driploss) must be greater than zero.', 1;

        SET @AdjustedDivisor = @CostBasisQty - @TotalDriploss;
        IF @AdjustedDivisor <= 0
            THROW 59215, 'Adjusted cost-rate divisor (non-driploss output qty minus driploss qty) must be greater than zero -- driploss quantity is too large relative to the non-driploss output.', 1;

        SET @MaterialRate = @TotalSourceCost / @AdjustedDivisor;
        SET @ChargeRate   = @CuttingCharge / @NonDriplossLines; -- informational only, see header comment; not used below

        ------------------------------------------------------------------
        -- 4. Reject a scanned lot (InventorySeqNo) appearing more than once
        ------------------------------------------------------------------
        IF EXISTS (SELECT InventorySeqNo FROM @SourceLines GROUP BY InventorySeqNo HAVING COUNT(*) > 1)
            THROW 59213, 'The same scanned item (Inventory lot) appears more than once in this batch. Please rescan.', 1;

        ------------------------------------------------------------------
        -- 5. Fail fast if a scanned lot clearly no longer has enough
        --    Available
        ------------------------------------------------------------------
        IF EXISTS (
            SELECT 1
            FROM @SourceLines AS s
            INNER JOIN dbo.Inventory AS i ON i.SequenceNumber = s.InventorySeqNo
            WHERE i.Branch <> @BranchCode OR i.Available < s.Qty OR i.IsStock = 0
        )
            THROW 59210, 'One of the scanned items no longer has enough available stock. Please rescan.', 1;

        ------------------------------------------------------------------
        -- 5b. Determine the parent ReferenceCode to stamp on new output
        --     lots, IF -- and only if -- EVERY source line in the batch
        --     carries the same non-blank ReferenceCode (see
        --     2026-09-01_ConversionPerBarcode_ParentReferenceCodeForManualShipment.sql
        --     for the full rationale/history of this check).
        ------------------------------------------------------------------
        DECLARE @ParentReferenceCode VARCHAR(50) = NULL;

        IF NOT EXISTS (SELECT 1 FROM @SourceLines WHERE NULLIF(LTRIM(RTRIM(ReferenceCode)), '') IS NULL)
           AND (SELECT COUNT(DISTINCT NULLIF(LTRIM(RTRIM(ReferenceCode)), '')) FROM @SourceLines) = 1
        BEGIN
            SELECT TOP 1 @ParentReferenceCode = NULLIF(LTRIM(RTRIM(ReferenceCode)), '')
            FROM @SourceLines;
        END

        BEGIN TRANSACTION;

        ------------------------------------------------------------------
        -- 6. Header
        ------------------------------------------------------------------
        INSERT INTO dbo.ConversionBarcodeSummary
            (ConversionRefNo, BranchCode, ConversionType, TotalSourceQty, TotalSourceCost,
             CuttingCharge, TotalDriplossQty, CostBasisQty, MaterialRatePerUnit, ChargeRatePerLine,
             Status, DateConverted, ConvertedBy)
        VALUES
            (@ConversionRefNo, @BranchCode, @ConversionType, @TotalSourceQty, @TotalSourceCost,
             @CuttingCharge, @TotalDriploss, @CostBasisQty, @MaterialRate, @ChargeRate,
             'POSTED', GETDATE(), @ConvertedBy);

        ------------------------------------------------------------------
        -- 7. Source lines + deduct Inventory
        ------------------------------------------------------------------
        INSERT INTO dbo.ConversionBarcodeSourceDetails
            (ConversionRefNo, SeqNo, InventorySeqNo, Barcode, ProductCode, Description, Qty, Cost, Amount)
        SELECT
            @ConversionRefNo,
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
            InventorySeqNo, Barcode, ProductCode, Description, Qty, Cost, Qty * Cost
        FROM @SourceLines;

        DECLARE @SourceLineCount INT = (SELECT COUNT(*) FROM @SourceLines);

        UPDATE i
        SET i.Available = i.Available - s.Qty,
            i.LastMovementDate = GETDATE()
        FROM dbo.Inventory AS i WITH (UPDLOCK, ROWLOCK)
        INNER JOIN @SourceLines AS s ON s.InventorySeqNo = i.SequenceNumber
        WHERE i.Branch = @BranchCode AND i.IsStock = 1 AND i.Available >= s.Qty;

        IF @@ROWCOUNT <> @SourceLineCount
            THROW 59210, 'One of the scanned items no longer has enough available stock (it may have changed concurrently). Please rescan.', 1;

        UPDATE dbo.Inventory
        SET IsStock = 0
        WHERE SequenceNumber IN (SELECT InventorySeqNo FROM @SourceLines)
          AND Available <= 0;

        ------------------------------------------------------------------
        -- 8. Output lines: EVERY line (driploss or not) becomes a real,
        --    sellable Inventory lot. Non-driploss lines are costed via the
        --    percentage-per-share formula (see header comment); driploss
        --    lines carry Cost = 0.
        ------------------------------------------------------------------
        DECLARE @OutSeq INT = 1;
        DECLARE @outProduct VARCHAR(50), @outDesc VARCHAR(150), @outQty DECIMAL(18,3), @outDriploss BIT;
        DECLARE @unitCost DECIMAL(18,6), @totalCost DECIMAL(18,2), @newBarcode VARCHAR(100), @newSeq INT;
        DECLARE @outProdCatCode VARCHAR(5), @outIsVat BIT;

        DECLARE outcur CURSOR LOCAL FAST_FORWARD FOR
            SELECT ProductCode, Description, Qty, IsDriploss FROM @OutputLines;

        OPEN outcur;
        FETCH NEXT FROM outcur INTO @outProduct, @outDesc, @outQty, @outDriploss;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF @outDriploss = 1
            BEGIN
                SET @PercentagePerShare = 0;
                SET @unitCost = 0;
                SET @totalCost = 0;
            END
            ELSE
            BEGIN
                SET @PercentagePerShare = @outQty / @CostBasisQty;
                SET @unitCost = (@MaterialRate + @CuttingCharge) * @PercentagePerShare;
                SET @totalCost = @outQty * @unitCost;
            END

            SET @newBarcode = dbo.func_GenerateBarcodeConversion(@BranchCode, @outProduct, @ConversionRefNo,
                                    FORMAT(GETDATE(), 'HHmmss'), FORMAT(@outQty, '00.000'));

            -- Reset before each lookup -- SELECT @var = col ... WHERE ... does NOT null
            -- out @var on a zero-row match, so without this a product/category miss on
            -- one line (most likely a driploss byproduct not registered in dbo.Products)
            -- would silently inherit the PREVIOUS line's VAT classification instead of
            -- correctly falling through to ISNULL(...,0). Found by sp-reviewer.
            SET @outProdCatCode = NULL;
            SET @outIsVat = NULL;
            SELECT @outProdCatCode = ProductCategoryCode FROM dbo.Products WHERE BranchCode = '888' AND ProductCode = @outProduct;
            SELECT @outIsVat = isVat FROM dbo.ProductCategory WHERE ProductCategoryID = @outProdCatCode;
            SET @outIsVat = ISNULL(@outIsVat, 0);

            INSERT INTO dbo.Inventory
                (Branch, ShipmentNo, PalletNo, BatchCode, DateReceived, ExpiryDate, Product, Description, Barcode,
                 TipWeight, Quantity, Cost, Available, QtyBigBlue, IsStock, IsVat, IsWarehouse, ReferenceCode,
                 LastMovementDate, isProcess, isSource, isConversion)
            VALUES
                (@BranchCode, 'CONVERSION', 0, 0, GETDATE(), NULL, @outProduct, @outDesc, @newBarcode,
                 @outQty, @outQty, @unitCost, @outQty, 0, 1, @outIsVat, 1,
                 COALESCE(@ParentReferenceCode, @ConversionRefNo),
                 GETDATE(), 0, 0, 1);

            SET @newSeq = SCOPE_IDENTITY();

            INSERT INTO dbo.ConversionBarcodeOutputDetails
                (ConversionRefNo, SeqNo, ProductCode, Description, Qty, IsDriploss, UnitCost, TotalCost,
                 NewInventorySeqNo, NewBarcode)
            VALUES
                (@ConversionRefNo, @OutSeq, @outProduct, @outDesc, @outQty, @outDriploss, @unitCost, @totalCost,
                 @newSeq, @newBarcode);

            SET @OutSeq += 1;
            FETCH NEXT FROM outcur INTO @outProduct, @outDesc, @outQty, @outDriploss;
        END

        CLOSE outcur;
        DEALLOCATE outcur;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'outcur') >= 0
            CLOSE outcur;
        IF CURSOR_STATUS('local', 'outcur') = -1
            DEALLOCATE outcur;
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

PRINT 'DEPLOYMENT COMPLETE: spu_PostConversionBarcode now uses percentage-per-share cost/charge allocation across non-driploss output lines.';
