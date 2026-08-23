SET NOCOUNT ON;
PRINT '=== Conversion Per Barcode: new dedicated tables, TVPs, SPs, views (HOFormsDevEx/ConversionPerBarcode.cs) ===';
GO

-- =============================================
-- WHY DEDICATED TABLES (not TempConversionSummary/TempConversionDetails/
-- ConversionSummary/ConversionDetails):
--   Those tables are already written to, with their own column layouts, by
--   HOConversion, HRIConversion, HOConversionPOS and ConversionDevEx. Fitting
--   this barcode-scan module into the same tables risks breaking those four
--   forms. A parallel, dedicated table pair keeps this module's costing
--   model (per-line material + charge rate) isolated from the legacy
--   per-percentage costing model those forms use.
-- =============================================

IF OBJECT_ID('dbo.ConversionBarcodeOutputDetails', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ConversionBarcodeOutputDetails
    (
        ConversionRefNo   VARCHAR(20)   NOT NULL,
        SeqNo             INT           NOT NULL,
        ProductCode       VARCHAR(50)   NOT NULL,
        Description       VARCHAR(150)  NULL,
        Qty               DECIMAL(18,3) NOT NULL,
        IsDriploss        BIT           NOT NULL DEFAULT 0,
        UnitCost          DECIMAL(18,6) NOT NULL DEFAULT 0,
        TotalCost         DECIMAL(18,2) NOT NULL DEFAULT 0,
        NewInventorySeqNo INT           NULL,
        NewBarcode        VARCHAR(100)  NULL,
        CONSTRAINT PK_ConversionBarcodeOutputDetails PRIMARY KEY (ConversionRefNo, SeqNo)
    );
END
GO

IF OBJECT_ID('dbo.ConversionBarcodeSourceDetails', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ConversionBarcodeSourceDetails
    (
        ConversionRefNo VARCHAR(20)   NOT NULL,
        SeqNo           INT           NOT NULL,
        InventorySeqNo  INT           NOT NULL,
        Barcode         VARCHAR(100)  NOT NULL,
        ProductCode     VARCHAR(50)   NOT NULL,
        Description     VARCHAR(150)  NULL,
        Qty             DECIMAL(18,3) NOT NULL,
        Cost            DECIMAL(18,4) NOT NULL,
        Amount          DECIMAL(18,2) NOT NULL,
        CONSTRAINT PK_ConversionBarcodeSourceDetails PRIMARY KEY (ConversionRefNo, SeqNo)
    );
END
GO

IF OBJECT_ID('dbo.ConversionBarcodeSummary', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ConversionBarcodeSummary
    (
        ConversionRefNo     VARCHAR(20)   NOT NULL PRIMARY KEY,
        BranchCode          VARCHAR(50)   NOT NULL,
        ConversionType      VARCHAR(20)   NOT NULL,   -- 'OneToMany' or 'ManyToOne'
        TotalSourceQty      DECIMAL(18,3) NOT NULL,
        TotalSourceCost     DECIMAL(18,2) NOT NULL,
        CuttingCharge       DECIMAL(18,2) NOT NULL DEFAULT 0,
        TotalDriplossQty    DECIMAL(18,3) NOT NULL DEFAULT 0,
        CostBasisQty        DECIMAL(18,3) NOT NULL,   -- TotalSourceQty - TotalDriplossQty
        MaterialRatePerUnit DECIMAL(18,6) NOT NULL,   -- TotalSourceCost / CostBasisQty
        ChargeRatePerLine   DECIMAL(18,6) NOT NULL,   -- CuttingCharge / (# non-driploss output lines)
        Status              VARCHAR(20)   NOT NULL DEFAULT 'POSTED',  -- POSTED / REVERSED
        DateConverted       DATETIME      NOT NULL DEFAULT GETDATE(),
        ConvertedBy         VARCHAR(50)   NOT NULL,
        ReversedBy          VARCHAR(50)   NULL,
        DateReversed        DATETIME      NULL,
        Remarks             VARCHAR(200)  NULL
    );
END
GO

IF OBJECT_ID('dbo.FK_ConversionBarcodeSourceDetails_Summary', 'F') IS NULL
    ALTER TABLE dbo.ConversionBarcodeSourceDetails WITH CHECK
        ADD CONSTRAINT FK_ConversionBarcodeSourceDetails_Summary
        FOREIGN KEY (ConversionRefNo) REFERENCES dbo.ConversionBarcodeSummary(ConversionRefNo);
GO

IF OBJECT_ID('dbo.FK_ConversionBarcodeOutputDetails_Summary', 'F') IS NULL
    ALTER TABLE dbo.ConversionBarcodeOutputDetails WITH CHECK
        ADD CONSTRAINT FK_ConversionBarcodeOutputDetails_Summary
        FOREIGN KEY (ConversionRefNo) REFERENCES dbo.ConversionBarcodeSummary(ConversionRefNo);
GO

IF TYPE_ID('dbo.tt_ConversionBarcodeSourceLines') IS NOT NULL DROP TYPE dbo.tt_ConversionBarcodeSourceLines;
GO
CREATE TYPE dbo.tt_ConversionBarcodeSourceLines AS TABLE
(
    InventorySeqNo INT           NOT NULL,
    Barcode        VARCHAR(100)  NOT NULL,
    ProductCode    VARCHAR(50)   NOT NULL,
    Description    VARCHAR(150)  NULL,
    Qty            DECIMAL(18,3) NOT NULL,
    Cost           DECIMAL(18,4) NOT NULL
);
GO

IF TYPE_ID('dbo.tt_ConversionBarcodeOutputLines') IS NOT NULL DROP TYPE dbo.tt_ConversionBarcodeOutputLines;
GO
CREATE TYPE dbo.tt_ConversionBarcodeOutputLines AS TABLE
(
    ProductCode VARCHAR(50)   NOT NULL,
    Description VARCHAR(150)  NULL,
    Qty         DECIMAL(18,3) NOT NULL,
    IsDriploss  BIT           NOT NULL
);
GO

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-23
-- Description: Next Conversion Per Barcode reference number.
--              Called via IDGenerator.getIDNumberSP("sp_GetConversionBarcodeNumber","ConversionRefNo").
-- =============================================
IF OBJECT_ID('dbo.sp_GetConversionBarcodeNumber', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetConversionBarcodeNumber', 'sp_GetConversionBarcodeNumber_OLD_08232026120000';
GO

CREATE PROCEDURE dbo.sp_GetConversionBarcodeNumber
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @next INT;

    SELECT @next = ISNULL(MAX(CAST(SUBSTRING(ConversionRefNo, 5, 20) AS INT)), 0) + 1
    FROM dbo.ConversionBarcodeSummary WITH (NOLOCK);

    SELECT 'CVB-' + RIGHT('000000' + CAST(@next AS VARCHAR(10)), 6) AS ConversionRefNo;
END
GO

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-23
-- Description: Barcode-scan lookup for Conversion Per Barcode. Read-only --
--              staging happens client-side in the form's grid, nothing is
--              written here. Returns one row if the barcode is a valid,
--              available, in-stock Inventory lot for this branch.
-- =============================================
IF OBJECT_ID('dbo.sp_GetInventoryByBarcode', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetInventoryByBarcode', 'sp_GetInventoryByBarcode_OLD_08232026120000';
GO

CREATE PROCEDURE dbo.sp_GetInventoryByBarcode
    @Barcode    VARCHAR(100),
    @BranchCode VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1
        i.SequenceNumber,
        i.Product AS ProductCode,
        i.Description,
        i.Available,
        i.Cost,
        i.Barcode
    FROM dbo.Inventory AS i WITH (NOLOCK)
    WHERE i.Barcode = @Barcode
      AND i.Branch = @BranchCode
      AND i.IsStock = 1
      AND i.Available > 0;
END
GO

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-23
-- Description: Posts a Conversion Per Barcode batch (ConversionPerBarcode.cs
--              Submit). One source product scanned across possibly many lots
--              for OneToMany; possibly many source products for ManyToOne
--              feeding exactly one non-driploss destination product.
--              Costing (confirmed with user 2026-08-23):
--                CostBasisQty      = TotalSourceQty - TotalDriplossQty
--                MaterialRate      = TotalSourceCost / CostBasisQty
--                ChargeRate        = CuttingCharge / COUNT(non-driploss output lines)
--                UnitCost per line = MaterialRate + ChargeRate  (flat, applied
--                                     per unit uniformly to every non-driploss
--                                     output line regardless of its own qty --
--                                     an explicit policy rate, not a
--                                     value-conserving allocation)
--              Qty balance is enforced: SUM(non-driploss output qty) +
--              TotalDriplossQty must equal SUM(source qty).
-- =============================================
IF OBJECT_ID('dbo.spu_PostConversionBarcode', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_PostConversionBarcode', 'spu_PostConversionBarcode_OLD_08232026120000';
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
            @MaterialRate     DECIMAL(18,6),
            @ChargeRate       DECIMAL(18,6);

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
        --    All quantities are DECIMAL(18,3) exact arithmetic, so any real
        --    imbalance is a multiple of 0.001 -- compare to zero, not a
        --    tolerance band (a tolerance of >0.001 would let a genuine
        --    1-unit-at-the-finest-grain mismatch through).
        ------------------------------------------------------------------
        IF (@TotalNonDriploss + @TotalDriploss) <> @TotalSourceQty
            THROW 59208, 'Destination quantity (including driploss) must equal total scanned source quantity.', 1;

        SET @CostBasisQty = @TotalSourceQty - @TotalDriploss;
        IF @CostBasisQty <= 0
            THROW 59209, 'Cost basis quantity (source qty minus driploss) must be greater than zero.', 1;

        SET @MaterialRate = @TotalSourceCost / @CostBasisQty;
        SET @ChargeRate   = @CuttingCharge / @NonDriplossLines;

        ------------------------------------------------------------------
        -- 4. Reject a scanned lot (InventorySeqNo) appearing more than once
        --    -- otherwise totals/costing/audit rows count it twice while the
        --    Inventory deduction below only ever applies once per lot.
        ------------------------------------------------------------------
        IF EXISTS (SELECT InventorySeqNo FROM @SourceLines GROUP BY InventorySeqNo HAVING COUNT(*) > 1)
            THROW 59213, 'The same scanned item (Inventory lot) appears more than once in this batch. Please rescan.', 1;

        ------------------------------------------------------------------
        -- 5. Fail fast if a scanned lot clearly no longer has enough
        --    Available (good error UX before touching the header). The
        --    authoritative, race-safe check is the UPDLOCK'd deduction in
        --    step 7 below -- this one can still be beaten by a concurrent
        --    conversion between here and BEGIN TRANSACTION.
        ------------------------------------------------------------------
        IF EXISTS (
            SELECT 1
            FROM @SourceLines AS s
            INNER JOIN dbo.Inventory AS i ON i.SequenceNumber = s.InventorySeqNo
            WHERE i.Branch <> @BranchCode OR i.Available < s.Qty OR i.IsStock = 0
        )
            THROW 59210, 'One of the scanned items no longer has enough available stock. Please rescan.', 1;

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
        --    UPDLOCK + a re-check of Available >= Qty at the moment of
        --    deduction (not just the earlier fail-fast check) closes the
        --    race window between the step-5 check and this transaction.
        --    The rowcount THROW catches both "went negative concurrently"
        --    and "InventorySeqNo no longer exists".
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
        -- 8. Output lines: compute cost, create new Inventory lots for
        --    non-driploss products, record driploss for audit only
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
                SET @unitCost = 0;
                SET @totalCost = 0;
                SET @newBarcode = NULL;
                SET @newSeq = NULL;
            END
            ELSE
            BEGIN
                SET @unitCost = @MaterialRate + @ChargeRate;
                SET @totalCost = @outQty * @unitCost;
                SET @newBarcode = dbo.func_GenerateBarcodeConversion(@BranchCode, @outProduct, @ConversionRefNo,
                                        FORMAT(GETDATE(), 'HHmmss'), FORMAT(@outQty, '00.000'));

                -- VAT classification follows the destination product's own
                -- category (varies per line, especially OneToMany where each
                -- output product can differ) -- same lookup sp_InvQtyAdjustment
                -- uses, not a hardcoded value.
                SELECT @outProdCatCode = ProductCategoryCode FROM dbo.Products WHERE BranchCode = '888' AND ProductCode = @outProduct;
                SELECT @outIsVat = isVat FROM dbo.ProductCategory WHERE ProductCategoryID = @outProdCatCode;
                SET @outIsVat = ISNULL(@outIsVat, 0);

                INSERT INTO dbo.Inventory
                    (Branch, ShipmentNo, PalletNo, BatchCode, DateReceived, ExpiryDate, Product, Description, Barcode,
                     TipWeight, Quantity, Cost, Available, QtyBigBlue, IsStock, IsVat, IsWarehouse, ReferenceCode,
                     LastMovementDate, isProcess, isSource, isConversion)
                VALUES
                    (@BranchCode, 'CONVERSION', 0, 0, GETDATE(), NULL, @outProduct, @outDesc, @newBarcode,
                     @outQty, @outQty, @unitCost, @outQty, 0, 1, @outIsVat, 1, @ConversionRefNo,
                     GETDATE(), 0, 0, 1);

                SET @newSeq = SCOPE_IDENTITY();
            END

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
        -- Bare THROW (not RAISERROR('%s', ...)) preserves the original error
        -- number (59201-59213 above) so callers can distinguish failure
        -- reasons instead of everything collapsing to error 50000.
        THROW;
    END CATCH
END
GO

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-23
-- Description: Reverses (voids) a posted Conversion Per Barcode batch.
--              Refuses if any destination lot has already been touched
--              (Available <> Quantity), per the "fall back to reversal, but
--              only if untouched" edit rule -- known bug pattern #4.
--              Restores source Inventory.Available and soft-reverses (does
--              NOT delete) the destination lots it created, so the audit
--              trail (ConversionBarcodeOutputDetails.NewInventorySeqNo)
--              stays resolvable.
-- =============================================
IF OBJECT_ID('dbo.spu_ReverseConversionBarcode', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_ReverseConversionBarcode', 'spu_ReverseConversionBarcode_OLD_08232026120000';
GO

CREATE PROCEDURE dbo.spu_ReverseConversionBarcode
    @ConversionRefNo VARCHAR(20),
    @ReversedBy      VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.ConversionBarcodeSummary WHERE ConversionRefNo = @ConversionRefNo AND Status = 'POSTED')
            THROW 59211, 'This Conversion is not in POSTED status (already reversed, or does not exist).', 1;

        IF EXISTS (
            SELECT 1
            FROM dbo.ConversionBarcodeOutputDetails AS o
            INNER JOIN dbo.Inventory AS i ON i.SequenceNumber = o.NewInventorySeqNo
            WHERE o.ConversionRefNo = @ConversionRefNo
              AND i.Available <> i.Quantity
        )
            THROW 59212, 'Cannot reverse -- some converted stock has already been moved, sold, or transferred out.', 1;

        DECLARE @ExpectedSourceLines INT = (
            SELECT COUNT(*) FROM dbo.ConversionBarcodeSourceDetails WHERE ConversionRefNo = @ConversionRefNo);

        BEGIN TRANSACTION;

        UPDATE i
        SET i.Available = i.Available + s.Qty,
            i.IsStock = 1
        FROM dbo.Inventory AS i
        INNER JOIN dbo.ConversionBarcodeSourceDetails AS s
            ON s.InventorySeqNo = i.SequenceNumber
        WHERE s.ConversionRefNo = @ConversionRefNo;

        -- If a source lot no longer exists (e.g. hard-deleted elsewhere in
        -- the app), the join above silently matches nothing for it and the
        -- reversal would otherwise "succeed" while permanently losing that
        -- quantity. Catch the mismatch instead of failing silently.
        IF @@ROWCOUNT <> @ExpectedSourceLines
            THROW 59214, 'Cannot reverse -- one or more original source inventory lots no longer exist.', 1;

        -- Soft-reverse (not DELETE) the destination lots this Conversion
        -- created, matching the rest of the codebase's avoidance of hard
        -- Inventory deletes -- keeps ConversionBarcodeOutputDetails.
        -- NewInventorySeqNo resolvable for audit drill-down after a reversal.
        UPDATE i
        SET i.Available = 0,
            i.IsStock = 0,
            i.LastMovementDate = GETDATE()
        FROM dbo.Inventory AS i
        INNER JOIN dbo.ConversionBarcodeOutputDetails AS o
            ON o.NewInventorySeqNo = i.SequenceNumber
        WHERE o.ConversionRefNo = @ConversionRefNo;

        UPDATE dbo.ConversionBarcodeSummary
        SET Status = 'REVERSED',
            ReversedBy = @ReversedBy,
            DateReversed = GETDATE()
        WHERE ConversionRefNo = @ConversionRefNo;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- =============================================
-- Posted-tab list view
-- =============================================
IF OBJECT_ID('dbo.vw_ConversionBarcodeSummary', 'V') IS NOT NULL
    EXEC sp_rename 'dbo.vw_ConversionBarcodeSummary', 'vw_ConversionBarcodeSummary_OLD_08232026120000';
GO

CREATE VIEW dbo.vw_ConversionBarcodeSummary
AS
SELECT
    ConversionRefNo,
    BranchCode,
    ConversionType,
    TotalSourceQty,
    TotalSourceCost,
    CuttingCharge,
    TotalDriplossQty,
    CostBasisQty,
    MaterialRatePerUnit,
    ChargeRatePerLine,
    Status,
    DateConverted,
    ConvertedBy,
    ReversedBy,
    DateReversed,
    Remarks
FROM dbo.ConversionBarcodeSummary;
GO

-- =============================================
-- Detail drill-down functions (View Details popup)
-- =============================================
IF OBJECT_ID('dbo.funcview_ConversionBarcodeSourceDetails', 'IF') IS NOT NULL
    DROP FUNCTION dbo.funcview_ConversionBarcodeSourceDetails;
GO

CREATE FUNCTION dbo.funcview_ConversionBarcodeSourceDetails
(
    @ConversionRefNo VARCHAR(20)
)
RETURNS TABLE
AS
RETURN
(
    SELECT SeqNo, InventorySeqNo, Barcode, ProductCode, Description, Qty, Cost, Amount
    FROM dbo.ConversionBarcodeSourceDetails
    WHERE ConversionRefNo = @ConversionRefNo
);
GO

IF OBJECT_ID('dbo.funcview_ConversionBarcodeOutputDetails', 'IF') IS NOT NULL
    DROP FUNCTION dbo.funcview_ConversionBarcodeOutputDetails;
GO

CREATE FUNCTION dbo.funcview_ConversionBarcodeOutputDetails
(
    @ConversionRefNo VARCHAR(20)
)
RETURNS TABLE
AS
RETURN
(
    SELECT SeqNo, ProductCode, Description, Qty, IsDriploss, UnitCost, TotalCost, NewInventorySeqNo, NewBarcode
    FROM dbo.ConversionBarcodeOutputDetails
    WHERE ConversionRefNo = @ConversionRefNo
);
GO

PRINT 'DEPLOYMENT COMPLETE: ConversionBarcodeSummary/SourceDetails/OutputDetails, tt_ConversionBarcodeSourceLines/OutputLines, sp_GetConversionBarcodeNumber, sp_GetInventoryByBarcode, spu_PostConversionBarcode, spu_ReverseConversionBarcode, vw_ConversionBarcodeSummary, funcview_ConversionBarcodeSourceDetails, funcview_ConversionBarcodeOutputDetails.';
