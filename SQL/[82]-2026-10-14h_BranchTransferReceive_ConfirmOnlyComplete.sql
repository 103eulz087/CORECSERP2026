/* ================================================================
   [82] 2026-10-14 - Branch transfer receiving: confirm only a complete receipt
   ================================================================
   User 2026-10-14 (ENZO, ReceivedTransferInventoryBatchMode): transfers 1192 (10-12) and 1214 (10-14) were received with
   ONE line each and still closed as DELIVERED. Traced on ENZO (read-only): the screen built the item list from the rows the
   grid showed (a find-panel search / column filter / grouping left one row), sp_AddBranchTransferInventoryBatch saved that
   one line, and sp_ConfirmBranchReceivedTransferInventory then closed the transfer with no completeness check, so it left
   the For Receiving list. (The screen is fixed too: it sends every loaded line and stops on any error.)

   sp_ConfirmBranchReceivedTransferInventory: refuses (59451, nothing changed) unless every TransferInventoryDetails line of
   the transfer has its received row (same ProductCode + Barcode); the message names the first missing line. The stock
   insert also skips a line whose barcode already has stock at the receiving branch (it skipped only reference 'rcv-<no>',
   while 3,133 received lines of 310 ENZO transfers sit under 'stsfifo': confirming one again would have doubled them).
   Re-confirming (as done by hand on 1192 / 1214) still completes missing stock, never doubles it.

   Same proc text on ENZO (CORECSERP_001), DEV, STAGING and PRODUCTION JFC on 2026-10-14; the script stops unless it is
   still that text (compared without whitespace). Backup _OLD_10142026230000. One transaction.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF CHARINDEX('[82]', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ConfirmBranchReceivedTransferInventory'))) > 0
BEGIN
    RAISERROR('[82] already applied here; nothing to do.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF ISNULL(CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ConfirmBranchReceivedTransferInventory')),
            CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 1), '') <> '0xA80CCE4EDA32F2DA615CF95B8AE0BCBC7C21EA019388B36C88181536B8B05125'
     OR OBJECT_ID('dbo.sp_ConfirmBranchReceivedTransferInventory_OLD_10142026230000') IS NOT NULL
BEGIN
    RAISERROR('[82] stopped, nothing changed: sp_ConfirmBranchReceivedTransferInventory is not the 2026-10-14 text here, or the backup _OLD_10142026230000 already exists.', 16, 1);
    SET NOEXEC ON;
END
GO

BEGIN TRANSACTION;
GO

EXEC sp_rename 'dbo.sp_ConfirmBranchReceivedTransferInventory', 'sp_ConfirmBranchReceivedTransferInventory_OLD_10142026230000';
GO


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
/*  [82] 2026-10-14: a transfer is confirmed (DELIVERED, stock added) only when EVERY line of it was received. Before, a
    receipt that saved one line (ENZO 1192 on 10-12, 1214 on 10-14: the screen sent only the rows its filter showed) was
    still closed as DELIVERED and dropped off the For Receiving list. Refused with 59451, nothing changed. */
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @IsInventory BIT;
    DECLARE @username VARCHAR(50);

    SET @username = @preparedby;

    BEGIN TRANSACTION;

    -------------------------------------------------------------------------
    -- [82] every line of the transfer must have been received (same product + barcode)
    -------------------------------------------------------------------------
    DECLARE @lines INT, @missing INT, @firstMissing VARCHAR(200), @msg NVARCHAR(400);
    SELECT @lines = COUNT(*) FROM dbo.TransferInventoryDetails d WHERE d.TransferNo = @parmtransno;
    SELECT @missing = COUNT(*)
    FROM dbo.TransferInventoryDetails d
    WHERE d.TransferNo = @parmtransno
      AND NOT EXISTS (SELECT 1 FROM dbo.ReceivedTransferInventoryDetails r WITH (UPDLOCK, HOLDLOCK)
                      WHERE r.TransferNo = d.TransferNo AND r.Barcode = d.BarcodeNo AND r.ProductCode = d.ProductNo);

    IF ISNULL(@lines, 0) = 0 OR ISNULL(@missing, 0) > 0
    BEGIN
        SELECT TOP 1 @firstMissing = d.ProductName + ' (' + d.BarcodeNo + ')'
        FROM dbo.TransferInventoryDetails d
        WHERE d.TransferNo = @parmtransno
          AND NOT EXISTS (SELECT 1 FROM dbo.ReceivedTransferInventoryDetails r
                          WHERE r.TransferNo = d.TransferNo AND r.Barcode = d.BarcodeNo AND r.ProductCode = d.ProductNo)
        ORDER BY d.SeqNo;
        ROLLBACK TRANSACTION;
        SET @msg = N'Transfer ' + @parmtransno + N': ' + CAST(ISNULL(@lines, 0) - ISNULL(@missing, 0) AS NVARCHAR(10)) + N' of '
                 + CAST(ISNULL(@lines, 0) AS NVARCHAR(10)) + N' line(s) were received'
                 + ISNULL(N' (not received: ' + @firstMissing + CASE WHEN @missing > 1 THEN N' and ' + CAST(@missing - 1 AS NVARCHAR(10)) + N' more' ELSE N'' END + N')', N'')
                 + N'. The transfer was not confirmed; receive all its lines first.';
        THROW 59451, @msg, 1;
    END

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
          )
          -- [82] nor when that line's barcode already has stock at this branch under another reference (ENZO: 3,133 lines
          -- of 310 transfers carry 'stsfifo'), so confirming a transfer again never adds its stock twice
          AND NOT EXISTS
          (
              SELECT 1
              FROM Inventory i
              WHERE i.Branch = @parmbranchcode
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

GO

IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ConfirmBranchReceivedTransferInventory')) NOT LIKE '%[[]82]%'
   OR OBJECT_ID('dbo.sp_ConfirmBranchReceivedTransferInventory_OLD_10142026230000') IS NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[82] post-check failed; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
GO

SET NOEXEC OFF;
GO
SELECT DB_NAME() AS DatabaseName, name, CONVERT(VARCHAR(16), modify_date, 120) AS Modified FROM sys.objects
WHERE name LIKE 'sp_ConfirmBranchReceivedTransferInventory%' ORDER BY name;
GO
