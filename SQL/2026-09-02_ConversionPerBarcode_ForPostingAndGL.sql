-- =============================================
-- Author: Eulz Avancena (original); modified 2026-09-02
-- Description: Adds a "FOR POSTING" workflow stage to Conversion Per
--              Barcode, ahead of the existing "POSTED" status. Submit
--              behaves exactly as before (deducts source Inventory, creates
--              output Inventory lots at the system-computed cost) except
--              the header now lands in Status='FOR POSTING' instead of
--              'POSTED' -- output cost is treated as provisional until a
--              human reviews/overrides it ("final cost adjustment... human
--              judgement").
--
--              NEW: a Finalize step (spu_FinalizeConversionBarcode) is what
--              actually:
--                1. Applies any FinalCost overrides to the output
--                   Inventory lots' Cost.
--                2. Posts ONE GL ticket with two legs:
--                     SOURCE leg  (valued at ORIGINAL source cost, NOT
--                                  affected by any output FinalCost
--                                  override): Debit COGS / Credit Inventory,
--                                  split VAT/VATEx by each consumed source
--                                  lot's own Inventory.IsVat.
--                     OUTPUT leg (the reverse, valued at each output line's
--                                  FINAL cost): Debit Inventory / Credit
--                                  COGS, split VAT/VATEx by each output
--                                  lot's own Inventory.IsVat.
--                3. Flips Status to 'POSTED'.
--
--              GL accounts (confirmed with user 2026-09-02):
--                COGS:      501 = COS - VAT EXEMPT,  502 = COS - VAT
--                Inventory: 101040201 = INVENTORY - VAT EXEMPT,
--                           101040202 = INVENTORY - VAT
--              Legs are posted GROSS (not netted against each other) even
--              though the same AccountCode appears on both a Debit and a
--              Credit row across the two legs -- matches this codebase's
--              existing convention (e.g. ClientPayments) of never netting
--              distinct economic events into one row, and matches the
--              user's own framing of "the converted output will just [be]
--              a reverse of the source" (two distinct entries).
--
--              Once POSTED (finalized, with a real GL ticket), a conversion
--              is now PERMANENT -- confirmed with user 2026-09-02 that
--              Reverse should only be available pre-finalize, from 'FOR
--              POSTING'. spu_ReverseConversionBarcode's status guard moves
--              from 'POSTED' to 'FOR POSTING' accordingly; it still only
--              ever touches Inventory (no GL to unwind, since none exists
--              yet at that stage).
-- =============================================

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-------------------------------------------------------------------
-- 1. Schema: FinalCost on output lines, Finalize audit trail on the header
-------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.ConversionBarcodeOutputDetails') AND name = 'FinalCost')
    ALTER TABLE dbo.ConversionBarcodeOutputDetails ADD FinalCost DECIMAL(18,6) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.ConversionBarcodeSummary') AND name = 'FinalizedBy')
    ALTER TABLE dbo.ConversionBarcodeSummary ADD FinalizedBy VARCHAR(50) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.ConversionBarcodeSummary') AND name = 'DateFinalized')
    ALTER TABLE dbo.ConversionBarcodeSummary ADD DateFinalized DATETIME NULL;
GO

-------------------------------------------------------------------
-- 2. New TVP for the Finalize call -- one row per NON-driploss output
--    line's user-entered final cost.
-------------------------------------------------------------------
IF TYPE_ID('dbo.tt_ConversionFinalCostLines') IS NULL
BEGIN
    CREATE TYPE dbo.tt_ConversionFinalCostLines AS TABLE
    (
        SeqNo     INT           NOT NULL,
        FinalCost DECIMAL(18,6) NOT NULL
    );
END
GO

-------------------------------------------------------------------
-- 3. spu_PostConversionBarcode: Status 'POSTED' -> 'FOR POSTING'; seed
--    FinalCost = the system-computed UnitCost so the For Posting tab always
--    has a real starting value to show/override.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.spu_PostConversionBarcode_OLD_09022026090000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.spu_PostConversionBarcode', 'P') IS NOT NULL
        DROP PROCEDURE dbo.spu_PostConversionBarcode;
END
ELSE IF OBJECT_ID('dbo.spu_PostConversionBarcode', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.spu_PostConversionBarcode', 'spu_PostConversionBarcode_OLD_09022026090000';
END
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

        IF (@TotalNonDriploss + @TotalDriploss) <> @TotalSourceQty
            THROW 59208, 'Destination quantity (including driploss) must equal total scanned source quantity.', 1;

        SET @CostBasisQty = @TotalSourceQty - @TotalDriploss;
        IF @CostBasisQty <= 0
            THROW 59209, 'Cost basis quantity (source qty minus driploss) must be greater than zero.', 1;

        SET @AdjustedDivisor = @CostBasisQty - @TotalDriploss;
        IF @AdjustedDivisor <= 0
            THROW 59215, 'Adjusted cost-rate divisor (non-driploss output qty minus driploss qty) must be greater than zero -- driploss quantity is too large relative to the non-driploss output.', 1;

        SET @MaterialRate = @TotalSourceCost / @AdjustedDivisor;
        SET @ChargeRate   = @CuttingCharge / @NonDriplossLines; -- informational only

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
                SET @PercentagePerShare = @outQty / @CostBasisQty;
                SET @unitCost = (@MaterialRate + @CuttingCharge) * @PercentagePerShare;
                SET @totalCost = @outQty * @unitCost;
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

-------------------------------------------------------------------
-- 4. spu_ReverseConversionBarcode: guard moves from Status='POSTED' to
--    Status='FOR POSTING' -- reversal is now a pre-finalize-only action.
--    Everything else (restore source Available, soft-reverse output lots)
--    is unchanged -- there is still no GL to unwind at this stage, since
--    Finalize (which is what posts GL) hasn't happened yet.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.spu_ReverseConversionBarcode_OLD_09022026090000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.spu_ReverseConversionBarcode', 'P') IS NOT NULL
        DROP PROCEDURE dbo.spu_ReverseConversionBarcode;
END
ELSE IF OBJECT_ID('dbo.spu_ReverseConversionBarcode', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.spu_ReverseConversionBarcode', 'spu_ReverseConversionBarcode_OLD_09022026090000';
END
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE dbo.spu_ReverseConversionBarcode
    @ConversionRefNo VARCHAR(20),
    @ReversedBy      VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.ConversionBarcodeSummary WHERE ConversionRefNo = @ConversionRefNo AND Status = 'FOR POSTING')
            THROW 59211, 'This Conversion is not in FOR POSTING status (already finalized/posted, already reversed, or does not exist).', 1;

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

        IF @@ROWCOUNT <> @ExpectedSourceLines
            THROW 59214, 'Cannot reverse -- one or more original source inventory lots no longer exist.', 1;

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

-------------------------------------------------------------------
-- 5. spu_FinalizeConversionBarcode (NEW): applies FinalCost overrides,
--    posts the source-consumption / output-creation GL ticket, flips
--    Status to POSTED.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.spu_FinalizeConversionBarcode_OLD_09022026090000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.spu_FinalizeConversionBarcode', 'P') IS NOT NULL
        DROP PROCEDURE dbo.spu_FinalizeConversionBarcode;
END
ELSE IF OBJECT_ID('dbo.spu_FinalizeConversionBarcode', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.spu_FinalizeConversionBarcode', 'spu_FinalizeConversionBarcode_OLD_09022026090000';
END
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE dbo.spu_FinalizeConversionBarcode
    @ConversionRefNo VARCHAR(20),
    @FinalCosts      dbo.tt_ConversionFinalCostLines READONLY,
    @FinalizedBy     VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        DECLARE @BranchCode VARCHAR(50), @Status VARCHAR(20);

        SELECT @BranchCode = BranchCode, @Status = Status
        FROM dbo.ConversionBarcodeSummary
        WHERE ConversionRefNo = @ConversionRefNo;

        IF @BranchCode IS NULL
            THROW 59301, 'Conversion not found.', 1;

        IF @Status <> 'FOR POSTING'
            THROW 59302, 'This Conversion is not in FOR POSTING status (already finalized, reversed, or does not exist).', 1;

        -- Reject a FinalCost row targeting a driploss line -- driploss stays
        -- at Cost = 0 always, it is not eligible for human override.
        IF EXISTS (
            SELECT 1 FROM @FinalCosts f
            INNER JOIN dbo.ConversionBarcodeOutputDetails o
                ON o.ConversionRefNo = @ConversionRefNo AND o.SeqNo = f.SeqNo
            WHERE o.IsDriploss = 1
        )
            THROW 59303, 'Cannot set a Final Cost override on a driploss line.', 1;

        IF EXISTS (SELECT 1 FROM @FinalCosts WHERE FinalCost < 0)
            THROW 59304, 'Final Cost cannot be negative.', 1;

        BEGIN TRANSACTION;

        -- Apply overrides (only for rows actually present in @FinalCosts --
        -- an unedited line keeps its existing FinalCost, seeded at Submit
        -- time to the system-computed UnitCost).
        UPDATE o
        SET o.FinalCost = f.FinalCost
        FROM dbo.ConversionBarcodeOutputDetails o
        INNER JOIN @FinalCosts f ON f.SeqNo = o.SeqNo
        WHERE o.ConversionRefNo = @ConversionRefNo;

        -- Push the (possibly overridden) final cost onto the actual
        -- Inventory lot -- applies going forward to whatever Available
        -- remains; units already sold before Finalize keep whatever cost
        -- was recorded at the time they were sold, unaffected.
        UPDATE i
        SET i.Cost = o.FinalCost
        FROM dbo.Inventory i
        INNER JOIN dbo.ConversionBarcodeOutputDetails o
            ON o.NewInventorySeqNo = i.SequenceNumber
        WHERE o.ConversionRefNo = @ConversionRefNo
          AND o.IsDriploss = 0;

        ------------------------------------------------------------------
        -- GL: source-consumption leg (Debit COGS / Credit Inventory,
        -- valued at ORIGINAL source cost -- unaffected by output FinalCost)
        -- and output-creation leg (the reverse, valued at FINAL cost).
        -- Both split VAT/VATEx by each lot's own Inventory.IsVat.
        ------------------------------------------------------------------
        DECLARE
            @SourceVat    DECIMAL(18,2) = 0,
            @SourceVatEx  DECIMAL(18,2) = 0,
            @OutputVat    DECIMAL(18,2) = 0,
            @OutputVatEx  DECIMAL(18,2) = 0;

        SELECT
            @SourceVat   = ISNULL(SUM(CASE WHEN i.IsVat = 1 THEN s.Qty * s.Cost ELSE 0 END), 0),
            @SourceVatEx = ISNULL(SUM(CASE WHEN i.IsVat = 0 OR i.IsVat IS NULL THEN s.Qty * s.Cost ELSE 0 END), 0)
        FROM dbo.ConversionBarcodeSourceDetails s
        INNER JOIN dbo.Inventory i ON i.SequenceNumber = s.InventorySeqNo
        WHERE s.ConversionRefNo = @ConversionRefNo;

        SELECT
            @OutputVat   = ISNULL(SUM(CASE WHEN i.IsVat = 1 THEN o.Qty * o.FinalCost ELSE 0 END), 0),
            @OutputVatEx = ISNULL(SUM(CASE WHEN i.IsVat = 0 OR i.IsVat IS NULL THEN o.Qty * o.FinalCost ELSE 0 END), 0)
        FROM dbo.ConversionBarcodeOutputDetails o
        INNER JOIN dbo.Inventory i ON i.SequenceNumber = o.NewInventorySeqNo
        WHERE o.ConversionRefNo = @ConversionRefNo
          AND o.IsDriploss = 0;

        DECLARE @TicketNo BIGINT;
        EXEC GetTicketNumber @TicketNo OUTPUT;

        INSERT INTO TicketMaster
        (
            TicketDate, SupplementaryNumber, BranchCode, Origin,
            TicketNumber, ReferenceNumber, ReferenceKey,
            Owner, Particulars, EnteredBy,
            CheckedBy, ApprovedBy, Status, Mnemonic, Product
        )
        VALUES
        (
            GETDATE(), 0, @BranchCode, @BranchCode,
            @TicketNo, @ConversionRefNo, @ConversionRefNo,
            @FinalizedBy, 'CONVERSION FINALIZE ENTRY', @FinalizedBy,
            '*', '*', 'UPDATED', 'CONV-FINALIZE', NULL
        );

        DECLARE @COGS_VAT VARCHAR(20) = '502', @COGS_VATEX VARCHAR(20) = '501',
                @INV_VAT  VARCHAR(20) = '101040202', @INV_VATEX VARCHAR(20) = '101040201';

        ;WITH Legs AS (
            SELECT 1 AS Seq, @COGS_VAT    AS AccountCode, @SourceVat   AS Debit, CAST(0 AS DECIMAL(18,2)) AS Credit
            UNION ALL SELECT 2, @COGS_VATEX, @SourceVatEx, 0
            UNION ALL SELECT 3, @INV_VAT,    0, @SourceVat
            UNION ALL SELECT 4, @INV_VATEX,  0, @SourceVatEx
            UNION ALL SELECT 5, @INV_VAT,    @OutputVat,   0
            UNION ALL SELECT 6, @INV_VATEX,  @OutputVatEx, 0
            UNION ALL SELECT 7, @COGS_VAT,   0, @OutputVat
            UNION ALL SELECT 8, @COGS_VATEX, 0, @OutputVatEx
        )
        INSERT INTO TicketDetails
        (
            TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
            TicketNumber, ReferenceNumber,
            AccountCode, Debit, Credit, CostCenter
        )
        SELECT
            GETDATE(), 0, @BranchCode, @ConversionRefNo,
            @TicketNo, @ConversionRefNo,
            AccountCode, Debit, Credit, ' '
        FROM Legs
        WHERE Debit <> 0 OR Credit <> 0
        ORDER BY Seq;

        DECLARE @TotalDebit DECIMAL(18,2), @TotalCredit DECIMAL(18,2);
        SELECT @TotalDebit = ISNULL(SUM(Debit), 0), @TotalCredit = ISNULL(SUM(Credit), 0)
        FROM TicketDetails WHERE TicketNumber = @TicketNo AND ReferenceKey = @ConversionRefNo;

        IF @TotalDebit <> @TotalCredit
        BEGIN
            ROLLBACK;
            THROW 59305, 'Finalize GL entry did not balance -- Debit and Credit totals differ.', 1;
        END

        UPDATE dbo.ConversionBarcodeSummary
        SET Status = 'POSTED',
            FinalizedBy = @FinalizedBy,
            DateFinalized = GETDATE()
        WHERE ConversionRefNo = @ConversionRefNo;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-------------------------------------------------------------------
-- 6. funcview_ConversionBarcodeOutputDetails: expose FinalCost so the For
--    Posting tab's grid can show/edit it.
-------------------------------------------------------------------
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
    SELECT SeqNo, ProductCode, Description, Qty, IsDriploss, UnitCost, TotalCost, FinalCost, NewInventorySeqNo, NewBarcode
    FROM dbo.ConversionBarcodeOutputDetails
    WHERE ConversionRefNo = @ConversionRefNo
);
GO

-------------------------------------------------------------------
-- 7. vw_ConversionBarcodeSummary: expose FinalizedBy/DateFinalized (same
--    precedent as ReversedBy/DateReversed) so both the For Posting and
--    Posted tabs can show them.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.vw_ConversionBarcodeSummary', 'V') IS NOT NULL
    DROP VIEW dbo.vw_ConversionBarcodeSummary;
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
    FinalizedBy,
    DateFinalized,
    Remarks
FROM dbo.ConversionBarcodeSummary;
GO

PRINT 'DEPLOYMENT COMPLETE: ConversionBarcodeOutputDetails.FinalCost, ConversionBarcodeSummary.FinalizedBy/DateFinalized, tt_ConversionFinalCostLines, spu_PostConversionBarcode (Status=FOR POSTING), spu_ReverseConversionBarcode (guard=FOR POSTING), spu_FinalizeConversionBarcode (NEW), funcview_ConversionBarcodeOutputDetails (+FinalCost), vw_ConversionBarcodeSummary (+FinalizedBy/DateFinalized).';
