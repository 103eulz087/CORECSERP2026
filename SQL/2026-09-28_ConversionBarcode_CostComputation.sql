/* ================================================================
   2026-09-28: spu_PostConversionBarcode -- output cost computation
   (HOFormsDevEx/ConversionPerBarcode.cs)
   ================================================================
   PROBLEM (e.g. CVB-000045: 30 kg @ 243.58 = 7,307.40, cutting charge
   250.00, outputs 26.52 + 3.02 kg, driploss 0.46 kg):
     1. MaterialRate = SourceCost / (CostBasisQty - Driploss) -- driploss
        subtracted TWICE (29.08 instead of 29.54).
     2. UnitCost = (MaterialRate + @CuttingCharge) * share -- the WHOLE
        cutting charge (250.00) was added to the per-kg rate.
     Result: 450.04 / 51.25 per kg.

   FIX -- per the user's worksheet (yellow cells, "computation" block):
     Q            = TotalSourceQty - TotalDriploss   (good output qty)
     MaterialRate = TotalSourceCost / Q
     ChargeRate   = CuttingCharge   / Q
     share        = OutputQty / Q
     UnitCost     = (MaterialRate + ChargeRate) * share
     TotalCost    = ROUND(OutputQty * UnitCost, 2)
     FinalCost    = UnitCost (seed; overridable at Finalize, unchanged)
   CVB-000045 -> 229.68 / 26.16 per kg, totals 6,091.14 / 78.99.
   Many-to-One has one non-driploss output, so share = 1 and
   UnitCost = (SourceCost + CuttingCharge) / Q.

   NOTE (user-confirmed method): because each output is also scaled by
   its own share, SUM(TotalCost) is less than SourceCost + CuttingCharge
   whenever there are 2+ outputs (CVB-000045: 6,170.13 of 7,557.40).
   Finalize values the source leg at source cost and the output leg at
   final cost, so the difference lands in the CONV-FINALIZE COGS legs.

   Only the rate/unit-cost lines changed; validation, stock deduction,
   barcode/Inventory creation and detail inserts are as before. The
   AdjustedDivisor (and its 59215 check) is removed -- no longer used.
   ChargeRatePerLine is still stored as CuttingCharge / non-driploss
   lines (informational only, as before).

   Deploy to COREX001 (DEV) first; CORECSJFC2026_STAGING only after the
   user confirms.
   ================================================================ */

IF OBJECT_ID('dbo.spu_PostConversionBarcode', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_PostConversionBarcode', 'spu_PostConversionBarcode_OLD_09282026100000';
GO
CREATE PROCEDURE [dbo].[spu_PostConversionBarcode]
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

        DECLARE
            @TotalSourceQty   DECIMAL(18,3),
            @TotalSourceCost  DECIMAL(18,2),
            @TotalDriploss    DECIMAL(18,3),
            @TotalNonDriploss DECIMAL(18,3),
            @NonDriplossLines INT,
            @CostBasisQty     DECIMAL(18,3),
            @MaterialRate     DECIMAL(18,6),
            @ChargeRatePerKg  DECIMAL(18,6),   -- NEW 2026-09-28: CuttingCharge / good qty
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

        IF (@TotalNonDriploss + @TotalDriploss) <> @TotalSourceQty
            THROW 59208, 'Destination quantity (including driploss) must equal total scanned source quantity.', 1;

        SET @CostBasisQty = @TotalSourceQty - @TotalDriploss;
        IF @CostBasisQty <= 0
            THROW 59209, 'Cost basis quantity (source qty minus driploss) must be greater than zero.', 1;

        -- CHANGED 2026-09-28: both rates are per kg of GOOD output (Q = source
        -- qty minus driploss). Was SourceCost / (Q - driploss), which took
        -- driploss off twice, and the whole CuttingCharge was added per kg.
        SET @MaterialRate    = @TotalSourceCost / @CostBasisQty;
        SET @ChargeRatePerKg = @CuttingCharge   / @CostBasisQty;
        SET @ChargeRate      = @CuttingCharge / @NonDriplossLines; -- informational only (ChargeRatePerLine)

        IF EXISTS (SELECT InventorySeqNo FROM @SourceLines GROUP BY InventorySeqNo HAVING COUNT(*) > 1)
            THROW 59213, 'The same scanned item (Inventory lot) appears more than once in this batch. Please rescan.', 1;

        IF EXISTS (
            SELECT 1
            FROM @SourceLines AS s
            INNER JOIN dbo.Inventory AS i ON i.SequenceNumber = s.InventorySeqNo
            WHERE i.Branch <> @BranchCode OR i.Available < s.Qty OR i.IsStock = 0
        )
            THROW 59210, 'One of the scanned items no longer has enough available stock. Please rescan.', 1;

        DECLARE @ParentReferenceCode VARCHAR(50) = NULL;

        IF NOT EXISTS (SELECT 1 FROM @SourceLines WHERE NULLIF(LTRIM(RTRIM(ReferenceCode)), '') IS NULL)
           AND (SELECT COUNT(DISTINCT NULLIF(LTRIM(RTRIM(ReferenceCode)), '')) FROM @SourceLines) = 1
        BEGIN
            SELECT TOP 1 @ParentReferenceCode = NULLIF(LTRIM(RTRIM(ReferenceCode)), '')
            FROM @SourceLines;
        END

        BEGIN TRANSACTION;

        -- Status FOR POSTING, not POSTED -- output cost is provisional
        -- until Finalize.
        INSERT INTO dbo.ConversionBarcodeSummary
            (ConversionRefNo, BranchCode, ConversionType, TotalSourceQty, TotalSourceCost,
             CuttingCharge, TotalDriplossQty, CostBasisQty, MaterialRatePerUnit, ChargeRatePerLine,
             Status, DateConverted, ConvertedBy)
        VALUES
            (@ConversionRefNo, @BranchCode, @ConversionType, @TotalSourceQty, @TotalSourceCost,
             @CuttingCharge, @TotalDriploss, @CostBasisQty, @MaterialRate, @ChargeRate,
             'FOR POSTING', GETDATE(), @ConvertedBy);

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
                -- CHANGED 2026-09-28 (user's worksheet): per-kg material + charge
                -- rate, scaled by this output's share of the good qty.
                SET @PercentagePerShare = @outQty / @CostBasisQty;
                SET @unitCost = (@MaterialRate + @ChargeRatePerKg) * @PercentagePerShare;
                SET @totalCost = ROUND(@outQty * @unitCost, 2);
            END

            SET @newBarcode = dbo.func_GenerateBarcodeConversion(@BranchCode, @outProduct, @ConversionRefNo,
                                    FORMAT(GETDATE(), 'HHmmss'), FORMAT(@outQty, '00.000'));

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
                 NewInventorySeqNo, NewBarcode, FinalCost)
            VALUES
                (@ConversionRefNo, @OutSeq, @outProduct, @outDesc, @outQty, @outDriploss, @unitCost, @totalCost,
                 @newSeq, @newBarcode, @unitCost);

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
