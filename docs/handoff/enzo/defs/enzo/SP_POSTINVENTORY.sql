
CREATE PROCEDURE [dbo].[SP_POSTINVENTORY]
    @parmshipmentno   varchar(10),
    @parmrefno        varchar(10),
    @parmuser         varchar(20),
    @parmbranch       char(3),
    @parminvoiceno    varchar(50),
    @parminvoicedate  date,
    @parmduedate      date
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON; -- Ensures that if the nested SP fails, the whole transaction safely aborts

    DECLARE @totalVat       decimal(19,3) = 0,
            @totalVatExempt decimal(19,3) = 0;

    BEGIN TRY
        BEGIN TRAN;

        /* 1) Rebuild Inventory for the shipment (single pass) */
        DELETE FROM dbo.Inventory
        WHERE ShipmentNo = @parmshipmentno;

        INSERT INTO dbo.Inventory
        (
            Branch, ShipmentNo, PalletNo, BatchCode, DateReceived, ExpiryDate,
            Product, [Description], Barcode, TipWeight, Quantity, Cost, Available,
            IsStock, IsVat, IsWarehouse, ReferenceCode, LastMovementDate,
            isProcess, isSource, isConversion
        )
        SELECT
            Branch, ShipmentNo, PalletNo, BatchCode, DateReceived, @parmduedate,
            Product, [Description], Barcode, TipWeight, Quantity, Cost, Available,
            IsStock, IsVat, IsWarehouse, ReferenceCode, LastMovementDate,
            isProcess, isSource, isConversion
        FROM dbo.TempInventory WITH (HOLDLOCK)   -- keep consistent within XACT
        WHERE ShipmentNo = @parmshipmentno AND isProcess = 0;

		UPDATE a SET a.isVat=b.isVat
		FROM dbo.Inventory a
		INNER JOIN dbo.Products b
			ON a.Branch=b.BranchCode
			and a.Product=b.ProductCode
		WHERE a.ShipmentNo = @parmshipmentno
		

        /* 2) Update PODETAILS (set-based) */
        ;WITH QtyAgg AS
        (
            SELECT ShipmentNo,
                   Product AS OrderCode,
                   SUM(Quantity) AS SumQty
            FROM dbo.TempInventory
            WHERE ShipmentNo = @parmshipmentno
            GROUP BY ShipmentNo, Product
        )
        UPDATE pd
           SET pd.ActualQuantity = ISNULL(ROUND(q.SumQty,2), 0)
        FROM dbo.PODETAILS pd
        LEFT JOIN QtyAgg q
          ON q.ShipmentNo = pd.ShipmentNo
         AND q.OrderCode  = pd.OrderCode
        WHERE pd.ShipmentNo = @parmshipmentno
          AND pd.OrderType  = 'P';

        UPDATE pd
        SET pd.ActualCost = ISNULL(ROUND(fc.Cost,2), 0)
        FROM dbo.PODETAILS AS pd
        OUTER APPLY
        (
            -- "First" cost by SequenceNumber:
            SELECT TOP (1) Cost
            FROM dbo.TempInventory ti
            WHERE ti.ShipmentNo = pd.ShipmentNo
              AND ti.Product    = pd.OrderCode
            ORDER BY ti.SequenceNumber
        ) AS fc
        WHERE pd.ShipmentNo = @parmshipmentno
          AND pd.OrderType  = 'P';

        UPDATE pd
           SET pd.ActualTotalCost = pd.ActualCost * pd.ActualQuantity
        FROM dbo.PODETAILS pd
        WHERE pd.ShipmentNo = @parmshipmentno
          AND pd.OrderType  = 'P';

        /* 3) Update POSUMMARY (status + totals) in one pass */
        ;WITH Totals AS
        (
            SELECT ShipmentNo, SupplierID,
                   SUM(ActualQuantity)   AS TotalActualQty,
                   SUM(ActualTotalCost)  AS TotalActualCost
            FROM dbo.PODETAILS
            WHERE ShipmentNo = @parmshipmentno
              AND OrderType  = 'P'
            GROUP BY ShipmentNo, SupplierID
        )
        UPDATE ps
           SET ps.Status         = 'FOR CONFIRMATION',  -- previously APPROVED
               ps.ReceivedBy     = @parmuser,
               ps.ReceivedDate   = GETDATE(),
               ps.TotalActualQty = t.TotalActualQty,
               ps.TotalActualCost= t.TotalActualCost
        FROM dbo.POSUMMARY ps
        INNER JOIN Totals t
           ON t.ShipmentNo = ps.ShipmentNo
          AND t.SupplierID = ps.SupplierID
        WHERE ps.ShipmentNo = @parmshipmentno
          AND ps.OrderType  = 'P';

        /* 4) Compute totals from Inventory for AP ACCOUNTS (Using Base Cost) */
        SELECT
            @totalVat       = SUM(CASE WHEN IsVat = 1 THEN Quantity * Cost ELSE 0 END),
            @totalVatExempt = SUM(CASE WHEN IsVat = 0 THEN Quantity * Cost ELSE 0 END)
        FROM dbo.Inventory
        WHERE ShipmentNo = @parmshipmentno;

        /* =========================================================================
           4.5) EXECUTE LANDED COST UPDATE
           ========================================================================= */
        -- Execute the SP. If it fails, XACT_ABORT pushes it immediately to the CATCH block.
        EXEC spu_InventoryCostUpdate @parmshipmentno;

        -- Ensure it actually generated cost details before attempting an update
        IF EXISTS (SELECT 1 FROM dbo.POSCOSTINGDETAILS WHERE Shipmentno = @parmshipmentno)
        BEGIN
            UPDATE a 
            SET a.Cost = b.NewUnitCost
            FROM dbo.Inventory a
            INNER JOIN dbo.POSCOSTINGDETAILS b
                ON a.Product = b.ProductCode
                AND a.ShipmentNo = b.Shipmentno
            WHERE a.ShipmentNo = @parmshipmentno;
        END
        /* ========================================================================= */

        /* 5) Insert into APACCOUNTS (guard against duplicates) */
        INSERT INTO dbo.APACCOUNTS
        (
            ShipmentNo, SupplierID, ReferenceNumber, InvoiceDate, InvoiceNo,
            VatExemptAmount, VatableAmount, ActualCost, Balance,
            AmountPaid, Discount, EWTAmount, OffsetAmount, HPYAmount,
            DueDate, PayStatus, DateAdded, AddedBy, DateUpdated, UpdateBy
        )
        SELECT
            ps.ShipmentNo, ps.SupplierID, ' ',
            @parminvoicedate, @parminvoiceno,
            ISNULL(@totalVatExempt, 0), ISNULL(@totalVat, 0),
            ISNULL(@totalVatExempt, 0) + ISNULL(@totalVat, 0),
            ISNULL(@totalVatExempt, 0) + ISNULL(@totalVat, 0),
            0, 0, 0, 0, 0,
            @parmduedate,
            'UNPAID', GETDATE(), @parmuser, GETDATE(), @parmuser
        FROM dbo.POSUMMARY ps
        WHERE ps.ShipmentNo = @parmshipmentno
          AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.APACCOUNTS a
                  WHERE a.ShipmentNo = ps.ShipmentNo
                    AND a.InvoiceNo  = @parminvoiceno
              );

        /* 6) Inventory ledger — captures the newly updated Landed Cost */
        INSERT INTO dbo.InventoryLedger
        (
            SequenceRefNum, OriginBranch, DestinationBranch, DateProcessed,
            Product, [Description], BegQty, QtyIN, QtyOut, EndQty,
            Cost, Remarks, ProcessedBy
        )
        SELECT
            inv.SequenceNumber, inv.Branch, inv.Branch, GETDATE(),
            inv.Product, inv.[Description], 0, inv.Quantity, 0, inv.Quantity,
            inv.Cost, CONCAT('RECEIVED FROM SUPPLIER-PO#-', @parmshipmentno), @parmuser
        FROM dbo.Inventory inv
        WHERE inv.ShipmentNo = @parmshipmentno
          AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.InventoryLedger il
                  WHERE il.Remarks   = CONCAT('RECEIVED FROM SUPPLIER-PO#-', @parmshipmentno)
                    AND il.SequenceRefNum = inv.SequenceNumber
              );

        /* 7) History log */
        INSERT INTO dbo.HistoryLogs (UserID, DateExecute, ActionLogs, BranchCode)
        VALUES (@parmuser, GETDATE(), CONCAT('Received ShipmentOrder with ShipmentNo=', @parmshipmentno), @parmbranch);

        COMMIT TRAN;

        /* Optional: return a quick summary for UI */
        SELECT
            ShipmentNo     = @parmshipmentno,
            TotalVat       = @totalVat,
            TotalVatExempt = @totalVatExempt,
            GrandTotal     = ISNULL(@totalVat,0) + ISNULL(@totalVatExempt,0);
    END TRY
    BEGIN CATCH
        -- Ensure the transaction is correctly rolled back regardless of nested SP behaviors
        IF XACT_STATE() <> 0 ROLLBACK TRAN;

        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE(),
                @ErrNum int = ERROR_NUMBER(),
                @ErrLine int = ERROR_LINE(),
                @ErrSev int = ERROR_SEVERITY(),
                @ErrSta int = ERROR_STATE();

        RAISERROR('SP_POSTINVENTORY failed. %s (Err %d, Line %d, State %d)',
                  @ErrSev, 1, @ErrMsg, @ErrNum, @ErrLine, @ErrSta);
    END CATCH
END