
CREATE    PROCEDURE [dbo].[sp_AddBranchOrderBatch]
    @TransferItems dbo.TransferItemType READONLY,
    @PONumber      VARCHAR(10),
    @DeliveryNo    VARCHAR(10),
    @ReferenceNo   VARCHAR(10),
    @BranchCode    VARCHAR(10),
    @PreparedBy    VARCHAR(50) = 'system'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SkippedItems TABLE (
        ProductCode VARCHAR(10),
        ProductName VARCHAR(100),
        SeqNo       DECIMAL(3,0),
        Reason      VARCHAR(400)
    );

    -- ── NEW: refuse the whole batch (reported per-row, not a hard THROW --
    --    matches this proc's own per-row skip/report design) if the request
    --    was never approved. ──
    DECLARE @transferStatus VARCHAR(30);
    SELECT @transferStatus = Status FROM TransferOrderSummary WHERE PONumber = @PONumber;
    IF @transferStatus IS NULL OR @transferStatus <> 'APPROVED'
    BEGIN
        INSERT INTO @SkippedItems (ProductCode, ProductName, SeqNo, Reason)
        SELECT ProductCode, ProductName, SeqNo, 'Transfer Order request is not APPROVED.'
        FROM @TransferItems;

        SELECT ProductCode, ProductName, SeqNo, Reason FROM @SkippedItems;
        RETURN;
    END

    DECLARE @OriginCode VARCHAR(10);

    SELECT @OriginCode = BranchCode FROM TransferOrderSummary WHERE PONumber = @PONumber;

    DECLARE @Item TABLE (
        RowID               INT IDENTITY(1,1),
        ProductCategoryCode VARCHAR(10),
        ProductCode         VARCHAR(10),
        ProductName         VARCHAR(100),
        Qty                 DECIMAL(9,3),
        SeqNo               DECIMAL(3,0)
    );

    INSERT INTO @Item (ProductCategoryCode, ProductCode, ProductName, Qty, SeqNo)
    SELECT ProductCategoryCode, ProductCode, ProductName, Qty, SeqNo
    FROM @TransferItems;

    DECLARE @i INT = 1, @max INT = (SELECT COUNT(*) FROM @Item);
    WHILE @i <= @max
    BEGIN
        DECLARE @prodcatcode VARCHAR(10), @prodcode VARCHAR(10), @prodname VARCHAR(100), @qty DECIMAL(9,3), @seqno DECIMAL(3,0);
        SELECT @prodcatcode = ProductCategoryCode, @prodcode = ProductCode, @prodname = ProductName, @qty = Qty, @seqno = SeqNo
        FROM @Item WHERE RowID = @i;

        BEGIN TRY
            EXEC dbo.sp_AddBranchOrder
                @DeliveryNo, @ReferenceNo, @PONumber,
                @prodcatcode, @prodcode, @qty, '',
                @BranchCode, @OriginCode, @PreparedBy, '', 0;
        END TRY
        BEGIN CATCH
            INSERT INTO @SkippedItems (ProductCode, ProductName, SeqNo, Reason)
            VALUES (@prodcode, @prodname, @seqno, ERROR_MESSAGE());
        END CATCH

        SET @i += 1;
    END

    SELECT ProductCode, ProductName, SeqNo, Reason FROM @SkippedItems;
END
