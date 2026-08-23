SET NOCOUNT ON;
PRINT '=== Conversion: add FIFO-by-product source method alongside barcode scan (HOFormsDevEx/ConversionPerBarcode.cs) ===';
GO

-- =============================================
-- WHY NO CHANGES TO EXISTING TABLES/TVPs/spu_PostConversionBarcode/
-- spu_ReverseConversionBarcode:
--   Both source-selection methods (scan a barcode vs. pick a product and let
--   FIFO choose the lots) produce the exact same shape: one row per physical
--   Inventory lot consumed (InventorySeqNo, Barcode, ProductCode,
--   Description, Qty, Cost). The posting/reversal SPs only ever see that
--   shape via dbo.tt_ConversionBarcodeSourceLines -- they don't care how the
--   form arrived at it. Only two new READ-ONLY lookup SPs are needed.
-- =============================================

-- =============================================
-- Lightweight TVP for "what's already staged in the grid this session, not
-- yet posted" (Qty per InventorySeqNo, regardless of whether it was staged
-- by scanning a barcode or by a FIFO product pick) -- passed into
-- sp_GetInventoryFIFOBreakdown so a second FIFO pick (or a scan) can't walk
-- into a lot's quantity that's already earmarked by an earlier pick in the
-- same unposted batch.
-- =============================================
IF TYPE_ID('dbo.tt_ConversionStagedLots') IS NOT NULL DROP TYPE dbo.tt_ConversionStagedLots;
GO
CREATE TYPE dbo.tt_ConversionStagedLots AS TABLE
(
    InventorySeqNo INT           NOT NULL,
    Qty            DECIMAL(18,3) NOT NULL CHECK (Qty > 0)
);
GO

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-23
-- Description: Product dropdown source for Conversion's "Select Product
--              (FIFO)" source method -- one row per ProductCode/Description
--              with total Available summed across all of that branch's
--              in-stock lots.
-- =============================================
IF OBJECT_ID('dbo.sp_GetInventoryForConversionDropdown', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetInventoryForConversionDropdown', 'sp_GetInventoryForConversionDropdown_OLD_08232026130000';
GO

CREATE PROCEDURE dbo.sp_GetInventoryForConversionDropdown
    @BranchCode VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Grouped by Product only (not Description) -- sp_GetInventoryFIFOBreakdown
    -- pools ALL lots for a ProductCode regardless of Description, so grouping
    -- this dropdown by Description too would fragment a product with
    -- inconsistent lot descriptions into multiple rows, each understating
    -- what a FIFO pick against it can actually retrieve.
    SELECT
        i.Product AS ProductCode,
        MAX(i.Description) AS Description,
        SUM(i.Available) AS Available,
        CONCAT(i.Product, ' - ', MAX(i.Description)) AS DisplayText
    FROM dbo.Inventory AS i WITH (NOLOCK)
    WHERE i.Branch = @BranchCode
      AND i.IsStock = 1
      AND i.Available > 0
    GROUP BY i.Product
    ORDER BY MAX(i.Description);
END
GO

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-23
-- Description: FIFO lot breakdown for Conversion's "Select Product (FIFO)"
--              source method -- given a product and a requested quantity,
--              walks that branch's in-stock lots for the product by
--              SequenceNumber ASC (oldest first), greedily consuming each
--              lot's Available (minus whatever @AlreadyStaged already
--              earmarks against it this session) until the requested
--              quantity is satisfied. Read-only -- does not touch
--              Inventory.Available; the actual deduction (with its own
--              UPDLOCK + rowcount race guard) happens at Submit time in
--              spu_PostConversionBarcode, same as the barcode-scan path.
--              If the branch's remaining stock for this product is less
--              than requested, returns whatever is available (caller must
--              check SUM(Qty) against @RequestedQty and reject/prompt if
--              short).
-- =============================================
IF OBJECT_ID('dbo.sp_GetInventoryFIFOBreakdown', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetInventoryFIFOBreakdown', 'sp_GetInventoryFIFOBreakdown_OLD_08232026130000';
GO

CREATE PROCEDURE dbo.sp_GetInventoryFIFOBreakdown
    @ProductCode   VARCHAR(50),
    @BranchCode    VARCHAR(50),
    @RequestedQty  DECIMAL(18,3),
    @AlreadyStaged dbo.tt_ConversionStagedLots READONLY
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF @RequestedQty IS NULL OR @RequestedQty <= 0
            THROW 59301, 'Requested quantity must be greater than zero.', 1;

        DECLARE @Lots TABLE (
            SequenceNumber INT,
            Barcode        VARCHAR(100),
            Description    VARCHAR(150),
            Available      DECIMAL(18,3),
            Cost           DECIMAL(18,4)
        );

        INSERT INTO @Lots (SequenceNumber, Barcode, Description, Available, Cost)
        SELECT
            i.SequenceNumber,
            i.Barcode,
            i.Description,
            i.Available - ISNULL(s.StagedQty, 0),
            i.Cost
        FROM dbo.Inventory AS i WITH (NOLOCK)
        LEFT JOIN (
            SELECT InventorySeqNo, SUM(Qty) AS StagedQty
            FROM @AlreadyStaged
            GROUP BY InventorySeqNo
        ) AS s ON s.InventorySeqNo = i.SequenceNumber
        WHERE i.Branch = @BranchCode
          AND i.Product = @ProductCode
          AND i.IsStock = 1
          AND (i.Available - ISNULL(s.StagedQty, 0)) > 0
        ORDER BY i.SequenceNumber ASC;

        DECLARE @Result TABLE (
            ResultSeq      INT IDENTITY(1,1),
            SequenceNumber INT,
            Barcode        VARCHAR(100),
            ProductCode    VARCHAR(50),
            Description    VARCHAR(150),
            Qty            DECIMAL(18,3),
            Cost           DECIMAL(18,4)
        );

        DECLARE @Remaining DECIMAL(18,3) = @RequestedQty;
        DECLARE @seq INT, @barcode VARCHAR(100), @desc VARCHAR(150), @avail DECIMAL(18,3), @cost DECIMAL(18,4), @take DECIMAL(18,3);

        DECLARE fifo_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT SequenceNumber, Barcode, Description, Available, Cost FROM @Lots ORDER BY SequenceNumber ASC;

        OPEN fifo_cur;
        FETCH NEXT FROM fifo_cur INTO @seq, @barcode, @desc, @avail, @cost;

        WHILE @@FETCH_STATUS = 0 AND @Remaining > 0
        BEGIN
            SET @take = CASE WHEN @avail >= @Remaining THEN @Remaining ELSE @avail END;

            INSERT INTO @Result (SequenceNumber, Barcode, ProductCode, Description, Qty, Cost)
            VALUES (@seq, @barcode, @ProductCode, @desc, @take, @cost);

            SET @Remaining -= @take;

            FETCH NEXT FROM fifo_cur INTO @seq, @barcode, @desc, @avail, @cost;
        END

        CLOSE fifo_cur;
        DEALLOCATE fifo_cur;

        SELECT SequenceNumber, Barcode, ProductCode, Description, Qty, Cost
        FROM @Result
        ORDER BY ResultSeq ASC;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'fifo_cur') >= 0
            CLOSE fifo_cur;
        IF CURSOR_STATUS('local', 'fifo_cur') = -1
            DEALLOCATE fifo_cur;
        THROW;
    END CATCH
END
GO

PRINT 'DEPLOYMENT COMPLETE: tt_ConversionStagedLots, sp_GetInventoryForConversionDropdown, sp_GetInventoryFIFOBreakdown.';
