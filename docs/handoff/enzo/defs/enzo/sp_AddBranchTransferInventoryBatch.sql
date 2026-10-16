
CREATE PROCEDURE [dbo].[sp_AddBranchTransferInventoryBatch]
(
    @TransferNo        VARCHAR(10),
    @BranchCodeRcvr    VARCHAR(10),
    @ReceivedBy        VARCHAR(40),
    @Items             dbo.TransferInventoryItemType READONLY
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRANSACTION;

    -------------------------------------------------------------------------
    -- Step 1: Separate New and Existing Items
    -------------------------------------------------------------------------

    DECLARE @NewItems TABLE
    (
        ProductCode VARCHAR(10),
        Barcode     VARCHAR(40),
        Qty         FLOAT
    );

    DECLARE @ExistingItems TABLE
    (
        ProductCode VARCHAR(10),
        Qty         FLOAT
    );

    -------------------------------------------------------------------------
    -- Populate New Items
    -- Ignores items already received for this transfer
    -------------------------------------------------------------------------

    INSERT INTO @NewItems
    (
        ProductCode,
        Barcode,
        Qty
    )
    SELECT
        I.ProductCode,
        I.Barcode,
        I.Qty
    FROM @Items I
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM ReceivedTransferInventoryDetails R WITH (UPDLOCK, HOLDLOCK)
        WHERE R.TransferNo = @TransferNo
          AND R.Barcode = I.Barcode
    );

    -------------------------------------------------------------------------
    -- Populate Existing Items (Disabled)
    -------------------------------------------------------------------------
    /*
    INSERT INTO @ExistingItems (ProductCode, Qty)
    SELECT
        I.ProductCode,
        I.Qty
    FROM @Items I
    WHERE EXISTS
    (
        SELECT 1
        FROM ReceivedTransferInventoryDetails R
        WHERE R.TransferNo = @TransferNo
          AND R.ProductCode = I.ProductCode
    );
    */

    -------------------------------------------------------------------------
    -- Step 2: Insert New Items
    -------------------------------------------------------------------------

    INSERT INTO ReceivedTransferInventoryDetails
    (
        SeqNo,
        TransferNo,
        ProductCode,
        ProductName,
        Barcode,
        Qty,
        Cost,
        SellingPrice,
        IsVat
    )
    SELECT
        ISNULL
        (
            (
                SELECT MAX(SeqNo)
                FROM ReceivedTransferInventoryDetails
                WHERE TransferNo = @TransferNo
            ),
            0
        )
        + ROW_NUMBER() OVER (ORDER BY a.ProductCode),

        @TransferNo,
        a.ProductCode,
        b.ProductName,
        a.Barcode,
        a.Qty,
        b.Cost,
        0,
        0
    FROM @NewItems a
    INNER JOIN dbo.TransferInventoryDetails b WITH (NOLOCK)
        ON a.ProductCode = b.ProductNo
       AND a.Barcode = b.BarcodeNo
       AND b.TransferNo = @TransferNo;

    -------------------------------------------------------------------------
    -- Step 3: Update Existing Items (Disabled)
    -------------------------------------------------------------------------
    /*
    UPDATE R
    SET R.Qty = R.Qty + E.Qty
    FROM dbo.ReceivedTransferInventoryDetails R
    INNER JOIN @ExistingItems E
        ON R.ProductCode = E.ProductCode
    WHERE R.TransferNo = @TransferNo;
    */

    -------------------------------------------------------------------------
    -- Step 4: Update Cost from InventoryDeliveryFIFO (Disabled)
    -------------------------------------------------------------------------
    /*
    UPDATE R
    SET R.Cost = C.AvgCost
    FROM dbo.ReceivedTransferInventoryDetails R
    INNER JOIN
    (
        SELECT
            ProductNo,
            SUM(TotalCost) / NULLIF(SUM(QtyDelivered), 0) AS AvgCost
        FROM dbo.InventoryBranchTransferFIFO
        WHERE TransferNo = @TransferNo
          AND DestBranchCode = @BranchCodeDest
        GROUP BY ProductNo
    ) C
        ON R.ProductCode = C.ProductNo
    WHERE R.TransferNo = @TransferNo;
    */

    -------------------------------------------------------------------------
    -- Step 5: Insert Inventory Ledger Entries
    -------------------------------------------------------------------------

    INSERT INTO dbo.InventoryLedger
    SELECT
        SequenceReferenceNumber,
        SourceBranchCode,
        DestBranchCode,
        GETDATE(),
        ProductNo,
        Description,
        0,                          -- InQty
        QtyDelivered,               -- OutQty
        0,                          -- BalanceQty
        QtyDelivered,               -- RunningQty
        0,                          -- UnitCost
        'BRANCH TRNSFR RCVD ITEM TRN#' + TransferNo,
        @ReceivedBy
    FROM dbo.InventoryBranchTransferFIFO WITH (NOLOCK)
    WHERE TransferNo = @TransferNo
      AND DestBranchCode = @BranchCodeRcvr
      AND ProductNo IN
      (
          SELECT ProductCode
          FROM @Items
      );

    -------------------------------------------------------------------------
    -- Step 6: Update or Insert Receive Transfer Summary
    -------------------------------------------------------------------------

    DECLARE
        @TotalItem INT,
        @TotalKilo FLOAT;

    SELECT
        @TotalItem = COUNT(*),
        @TotalKilo = SUM(Qty)
    FROM dbo.ReceivedTransferInventoryDetails
    WHERE TransferNo = @TransferNo;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.ReceiveTransferInventorySummary
        WHERE TransferNo = @TransferNo
    )
    BEGIN
        UPDATE dbo.ReceiveTransferInventorySummary
        SET
            TotalItem = @TotalItem,
            TotalKilo = @TotalKilo
        WHERE TransferNo = @TransferNo;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.ReceiveTransferInventorySummary
        (
            TransferNo,
            BranchCode,
            TotalKilo,
            TotalItem,
            DateReceived,
            ReceivedBy
        )
        VALUES
        (
            @TransferNo,
            @BranchCodeRcvr,
            @TotalKilo,
            @TotalItem,
            GETDATE(),
            @ReceivedBy
        );
    END;

    COMMIT TRANSACTION;
END;
