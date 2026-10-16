
CREATE PROCEDURE [dbo].[sp_ConfirmBranchReceivedTransferInventory]
(
    @parmtransno      VARCHAR(20),
    @parmbranchcode   VARCHAR(10),
    @preparedby       VARCHAR(30),
    @category         VARCHAR(100),
    @remarks          VARCHAR(255),
    @suppliername     VARCHAR(100)
)
AS
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @IsInventory BIT;
    DECLARE @username VARCHAR(50);

    SET @username = @preparedby;

    BEGIN TRANSACTION;

    -------------------------------------------------------------------------
    -- Get category behavior
    -------------------------------------------------------------------------
    SELECT
        @IsInventory = IsInventory
    FROM ReceiveCategoryMaster
    WHERE CategoryCode = @category;

    -------------------------------------------------------------------------
    -- Save category, remarks, and supplier
    -------------------------------------------------------------------------
    UPDATE ReceiveTransferInventorySummary
    SET
        ReceiveCategory = @category,
        Remarks         = @remarks,
        SupplierName    = @suppliername
    WHERE TransferNo = @parmtransno;

    -------------------------------------------------------------------------
    -- Insert Inventory Records (only for inventory categories)
    -------------------------------------------------------------------------
    IF (@IsInventory = 1)
    BEGIN
        INSERT INTO Inventory
        (
            Branch,
            ShipmentNo,
            PalletNo,
            BatchCode,
            DateReceived,
            ExpiryDate,
            Product,
            Description,
            Barcode,
            TipWeight,
            Quantity,
            Cost,
            Available,
            IsStock,
            IsVat,
            IsWarehouse,
            ReferenceCode,
            LastMovementDate,
            isProcess,
            isSource,
            isConversion
        )
        SELECT
            @parmbranchcode,
            ' ',
            ' ',
            ' ',
            GETDATE(),
            DATEADD(YEAR, 1, CAST(GETDATE() AS DATE)),
            ProductCode,
            ProductName,
            Barcode,
            0,
            Qty,
            Cost,
            Qty,
            1,
            IsVat,
            1,
            'rcv-' + TransferNo,
            GETDATE(),
            0,
            1,
            0
        FROM ReceivedTransferInventoryDetails r
        WHERE r.TransferNo = @parmtransno
          AND NOT EXISTS
          (
              SELECT 1
              FROM Inventory i
              WHERE i.ReferenceCode = 'rcv-' + @parmtransno
                AND i.Barcode = r.Barcode
          );

        ---------------------------------------------------------------------
        -- Inventory Ledger Insert (currently disabled)
        ---------------------------------------------------------------------
        /*
        INSERT INTO dbo.InventoryLedger
        (
            SequenceReferenceNumber,
            SourceBranchCode,
            DestBranchCode,
            TransactionDate,
            ProductNo,
            Description,
            InQty,
            OutQty,
            BalanceQty,
            RunningQty,
            UnitCost,
            Reference,
            CreatedBy
        )
        SELECT
            NEWID(),
            t.SourceBranchCode,
            @parmbranchcode,
            GETDATE(),
            r.ProductCode,
            r.ProductName,
            r.Qty,
            0,
            0,
            r.Qty,
            r.Cost,
            'BRANCH RECEIVE - TRN# ' + @parmtransno,
            @preparedby
        FROM ReceivedTransferInventoryDetails r
        INNER JOIN TransferInventorySummary t
            ON r.TransferNo = t.TransferNo
        WHERE r.TransferNo = @parmtransno
          AND NOT EXISTS
          (
              SELECT 1
              FROM InventoryLedger l
              WHERE l.Reference = 'BRANCH RECEIVE - TRN# ' + @parmtransno
                AND l.ProductNo = r.ProductCode
          );
        */
    END;

    -------------------------------------------------------------------------
    -- Update transfer details and compute variance
    -------------------------------------------------------------------------
    UPDATE dt
    SET
        dt.Status    = 'DELIVERED',
        dt.ActualQty = rt.Qty,
        dt.Variance  = dt.QtyDelivered - rt.Qty
    FROM dbo.TransferInventoryDetails dt
    INNER JOIN dbo.ReceivedTransferInventoryDetails rt
        ON dt.TransferNo = rt.TransferNo
       AND dt.BarcodeNo = rt.Barcode
       AND dt.ProductNo = rt.ProductCode
    WHERE dt.TransferNo = @parmtransno;

    -------------------------------------------------------------------------
    -- Update transfer summary totals
    -------------------------------------------------------------------------
    UPDATE a
    SET a.TotalActualQty = sub.TotalQty
    FROM dbo.TransferInventorySummary a
    INNER JOIN
    (
        SELECT
            TransferNo,
            SUM(ActualQty) AS TotalQty
        FROM dbo.TransferInventoryDetails
        GROUP BY TransferNo
    ) sub
        ON a.TransferNo = sub.TransferNo
    WHERE a.TransferNo = @parmtransno;

    -------------------------------------------------------------------------
    -- Mark transfer as delivered
    -------------------------------------------------------------------------
    UPDATE TransferInventorySummary
    SET Status = 'DELIVERED'
    WHERE TransferNo = @parmtransno;

    -------------------------------------------------------------------------
    -- Update receiving summary totals
    -------------------------------------------------------------------------
    UPDATE a
    SET
        a.TotalItem = sub.Ctr,
        a.TotalKilo = sub.TotalQty
    FROM dbo.ReceiveTransferInventorySummary a
    INNER JOIN
    (
        SELECT
            TransferNo,
            COUNT(*) AS Ctr,
            SUM(Qty) AS TotalQty
        FROM dbo.ReceivedTransferInventoryDetails
        GROUP BY TransferNo
    ) sub
        ON a.TransferNo = sub.TransferNo
    WHERE a.TransferNo = @parmtransno;

    -------------------------------------------------------------------------
    -- Audit Log
    -------------------------------------------------------------------------
    INSERT INTO dbo.HistoryLogs
    (
        UserID,
        DateExecute,
        ActionLogs,
        BranchCode
    )
    VALUES
    (
        @username,
        GETDATE(),
        'Received/Confirm Transfer=' + @parmtransno +
        ' Category=' + @category,
        @parmbranchcode
    );

    COMMIT TRANSACTION;
END;
