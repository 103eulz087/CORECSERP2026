SET NOCOUNT ON;
PRINT '=== Conversion: FIFO Type (Auto vs Manual shipment selection) for the Select Product (FIFO) source method (HOFormsDevEx/ConversionPerBarcode.cs) ===';
GO

-- =============================================
-- WHY NO CHANGES TO spu_PostConversionBarcode / spu_ReverseConversionBarcode /
-- tt_ConversionBarcodeSourceLines / tt_ConversionStagedLots:
--   Both FIFO sub-modes -- Auto (walk all of a product's lots oldest-first)
--   and Manual (walk only the lots belonging to one specific
--   ShipmentNo+ReferenceCode batch the user picked) -- still resolve down
--   to the same shape: one row per physical Inventory lot consumed
--   (InventorySeqNo, Barcode, ProductCode, Description, Qty, Cost). Only
--   the source of that breakdown changes.
-- =============================================

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-24
-- Description: Product+Shipment dropdown for Conversion's "Select Product
--              (FIFO)" source method when FIFO Type = Manual -- one row per
--              ProductCode/ShipmentNo/ReferenceCode combination still in
--              stock, so the user can target a specific batch instead of
--              letting the system walk every lot oldest-first
--              (sp_GetInventoryForConversionDropdown, the Auto-mode
--              dropdown, is unchanged).
--
--              LookupKey (Product||ShipmentNo||ReferenceCode) is a
--              composite ValueMember -- ProductCode alone is NOT unique per
--              row here, since one product can have several batches in
--              stock at once (unlike the Auto dropdown, which is grouped by
--              Product only).
--
--              GROUP BY is Product+ShipmentNo+ReferenceCode, NOT just
--              Product+ShipmentNo: every Conversion-output lot is inserted
--              with the literal ShipmentNo = 'CONVERSION'
--              (spu_PostConversionBarcode, see 2026-08-23_ConversionPerBarcode_NewModule.sql)
--              but a real, per-run ReferenceCode = @ConversionRefNo -- so
--              grouping by ShipmentNo alone would silently pool every past
--              conversion run for a product into one dropdown row, and
--              picking it would let the breakdown SP walk lots across
--              unrelated runs/costs/dates. Including ReferenceCode in the
--              group keeps each conversion run (and each real shipment) as
--              its own row. This does NOT fully disambiguate
--              quantity-adjustment-added lots, which carry ShipmentNo = ''
--              and a constant literal ReferenceCode = 'QTYADJ'
--              (2026-08-03_InventoryQtyAdjustment_Rewrite.sql) -- those
--              still pool together per product under one row. Accepted as a
--              known limitation: ad-hoc adjustments have no real "shipment"
--              concept to scope to in the first place.
-- =============================================
IF OBJECT_ID('dbo.sp_GetInventoryForConversionManualDropdown', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetInventoryForConversionManualDropdown', 'sp_GetInventoryForConversionManualDropdown_OLD_08242026090000';
GO

CREATE PROCEDURE dbo.sp_GetInventoryForConversionManualDropdown
    @BranchCode VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        CONCAT(i.Product, '||', i.ShipmentNo, '||', i.ReferenceCode) AS LookupKey,
        i.ShipmentNo                                                 AS ShipmentNo,
        i.ReferenceCode                                              AS ReferenceCode,
        i.Product                                                    AS ProductCode,
        MAX(i.Description)                                           AS Description,
        SUM(i.Available)                                             AS Available,
        CONCAT(i.Product, ' - ', MAX(i.Description))                 AS DisplayText
    FROM dbo.Inventory AS i WITH (NOLOCK)
    WHERE i.Branch = @BranchCode
      AND i.IsStock = 1
      AND i.Available > 0
    GROUP BY i.Product, i.ShipmentNo, i.ReferenceCode
    ORDER BY MAX(i.Description), i.ShipmentNo, i.ReferenceCode;
END
GO

-- =============================================
-- Author: Eulz Avancena (original); added 2026-08-24
-- Description: FIFO lot breakdown scoped to ONE batch -- same
--              walk-oldest-lot-first logic as sp_GetInventoryFIFOBreakdown
--              (oldest SequenceNumber first, nets out @AlreadyStaged per
--              lot), but restricted to the ProductCode+ShipmentNo+ReferenceCode
--              the user picked in Manual FIFO Type mode (matching
--              sp_GetInventoryForConversionManualDropdown's grouping --
--              ReferenceCode is required too, not just ShipmentNo, so a
--              Conversion-output pick (ShipmentNo='CONVERSION') only walks
--              lots from that one @ConversionRefNo run, not every past run).
--              Deliberately does NOT fall through to other batches of the
--              same product if this one is short -- that's the whole point
--              of picking a specific batch instead of letting Auto mode
--              walk everything.
-- =============================================
IF OBJECT_ID('dbo.sp_GetInventoryFIFOBreakdownByShipment', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetInventoryFIFOBreakdownByShipment', 'sp_GetInventoryFIFOBreakdownByShipment_OLD_08242026090000';
GO

CREATE PROCEDURE dbo.sp_GetInventoryFIFOBreakdownByShipment
    @ProductCode   VARCHAR(50),
    @BranchCode    VARCHAR(50),
    @ShipmentNo    VARCHAR(10),
    @ReferenceCode VARCHAR(50),
    @RequestedQty  DECIMAL(18,3),
    @AlreadyStaged dbo.tt_ConversionStagedLots READONLY
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF @RequestedQty IS NULL OR @RequestedQty <= 0
            THROW 59302, 'Requested quantity must be greater than zero.', 1;

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
          AND i.ShipmentNo = @ShipmentNo
          AND ISNULL(i.ReferenceCode, '') = ISNULL(@ReferenceCode, '')
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

        DECLARE fifoshp_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT SequenceNumber, Barcode, Description, Available, Cost FROM @Lots ORDER BY SequenceNumber ASC;

        OPEN fifoshp_cur;
        FETCH NEXT FROM fifoshp_cur INTO @seq, @barcode, @desc, @avail, @cost;

        WHILE @@FETCH_STATUS = 0 AND @Remaining > 0
        BEGIN
            SET @take = CASE WHEN @avail >= @Remaining THEN @Remaining ELSE @avail END;

            INSERT INTO @Result (SequenceNumber, Barcode, ProductCode, Description, Qty, Cost)
            VALUES (@seq, @barcode, @ProductCode, @desc, @take, @cost);

            SET @Remaining -= @take;

            FETCH NEXT FROM fifoshp_cur INTO @seq, @barcode, @desc, @avail, @cost;
        END

        CLOSE fifoshp_cur;
        DEALLOCATE fifoshp_cur;

        SELECT SequenceNumber, Barcode, ProductCode, Description, Qty, Cost
        FROM @Result
        ORDER BY ResultSeq ASC;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'fifoshp_cur') >= 0
            CLOSE fifoshp_cur;
        IF CURSOR_STATUS('local', 'fifoshp_cur') = -1
            DEALLOCATE fifoshp_cur;
        THROW;
    END CATCH
END
GO

PRINT 'DEPLOYMENT COMPLETE: sp_GetInventoryForConversionManualDropdown, sp_GetInventoryFIFOBreakdownByShipment.';
