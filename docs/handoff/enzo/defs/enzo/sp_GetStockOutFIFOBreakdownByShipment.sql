
CREATE PROCEDURE [dbo].[sp_GetStockOutFIFOBreakdownByShipment]
    @ProductCode   VARCHAR(50),
    @BranchCode    VARCHAR(50),
    @ShipmentNo    VARCHAR(10),
    @ReferenceCode VARCHAR(50),
    @RequestedQty  DECIMAL(18,3),
    @AlreadyStaged dbo.tt_StockOutStagedLots READONLY
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF @RequestedQty IS NULL OR @RequestedQty <= 0
            THROW 59602, 'Requested quantity must be greater than zero.', 1;

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
          AND i.IsWarehouse=1
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
