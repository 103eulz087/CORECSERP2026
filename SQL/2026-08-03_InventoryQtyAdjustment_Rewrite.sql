SET NOCOUNT ON;
PRINT '=== sp_InvQtyAdjustment: simplified ADD/DEDUCT rewrite ===';
GO
EXEC sp_rename 'dbo.sp_InvQtyAdjustment', 'sp_InvQtyAdjustment_OLD_08032026144611';
GO
SET QUOTED_IDENTIFIER ON;
GO
-- =============================================
-- Author:      Eulz Avancena (original 12/5/2017); rewritten 2026-08-03
-- Description: Branch inventory quantity adjustment (ADD or DEDUCT).
--
--   ADD    -> directly inserts a new Inventory row for the branch/product
--             carrying the adjustment quantity.
--   DEDUCT -> consumes existing Inventory rows for that branch/product in
--             chronological (FIFO) order - oldest DateReceived first - one
--             row at a time, decrementing Available until the requested
--             quantity is fully accounted for.
--
-- This version intentionally drops the Supplier/Shipment "In Transit" and
-- "Link to Supplier" linkage the old version required (PODETAILS/POSUMMARY/
-- APACCOUNTS/SupplierLedger updates, GL ticket posting tied to a supplier
-- transaction) - InventoryQtyAdjustmentDevEx.cs no longer uses that design.
-- The previous version is preserved as sp_InvQtyAdjustment_OLD_08032026144611.
-- =============================================
CREATE PROCEDURE [dbo].[sp_InvQtyAdjustment]
    @parmbranchcode      varchar(5),
    @parmprodcode        varchar(10),
    @parmdesc            varchar(120),
    @parmqty             float,          -- available qty before this adjustment (audit)
    @parmcost            money,
    @parmqtyadj          float,          -- quantity being added or deducted
    @parmnewqty          float,          -- resulting qty (audit)
    @parmadjustmenttype  varchar(50),    -- 'ADD' or 'DEDUCT'
    @parmamountadjusted  money,
    @parmuser            varchar(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @parmqtyadj IS NULL OR @parmqtyadj <= 0
    BEGIN
        THROW 93003, 'Qty Adjustment must be greater than zero.', 1;
    END

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @isvat bit = 0, @prodcatcode varchar(5);
        SELECT @prodcatcode = ProductCategoryCode FROM Products WHERE BranchCode = '888' AND ProductCode = @parmprodcode;
        SELECT @isvat = isVat FROM ProductCategory WHERE ProductCategoryID = @prodcatcode;
        SET @isvat = ISNULL(@isvat, 0);

        -- Audit header row (same table/shape the old version wrote to)
        INSERT INTO InventoryAdjustment
        (
            BranchCode, ShipmentNo, ProductCode, Description, Quantity, CostKg,
            QtyAdjustment, CostAdjustment, NewQty, NewCost, AmountAdjusted,
            SeqRefNum, DateAdjusted, isVat, AdjustmentType, isCost, isQty
        )
        VALUES
        (
            @parmbranchcode, '', @parmprodcode, @parmdesc, @parmqty, @parmcost,
            @parmqtyadj, 0, @parmnewqty, 0, @parmamountadjusted,
            '', GETDATE(), @isvat, @parmadjustmenttype, 0, 1
        );

        IF @parmadjustmenttype = 'ADD'
        BEGIN
            INSERT INTO Inventory
            (
                Branch, ShipmentNo, PalletNo, BatchCode, DateReceived, ExpiryDate,
                Product, Description, Barcode, TipWeight, Quantity, Cost, Available,
                QtyBigBlue, IsStock, IsVat, IsWarehouse, ReferenceCode, LastMovementDate,
                isProcess, isSource, isConversion
            )
            VALUES
            (
                @parmbranchcode, '', 0, 0, CAST(GETDATE() AS date), NULL,
                @parmprodcode, @parmdesc, '', 0, @parmqtyadj, @parmcost, @parmqtyadj,
                0, 1, @isvat, 1, 'QTYADJ', CAST(GETDATE() AS date),
                0, 1, 0
            );
        END
        ELSE IF @parmadjustmenttype = 'DEDUCT'
        BEGIN
            DECLARE @remaining float = @parmqtyadj;
            DECLARE @seq int, @avail decimal(18,3), @rowcost decimal(18,2), @take float;

            DECLARE fifo_cursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT SequenceNumber, Available, Cost
                FROM Inventory
                WHERE Branch = @parmbranchcode
                  AND Product = @parmprodcode
                  AND IsStock = 1
                  AND Available > 0
                ORDER BY DateReceived ASC, SequenceNumber ASC;  -- chronological / FIFO

            OPEN fifo_cursor;
            FETCH NEXT FROM fifo_cursor INTO @seq, @avail, @rowcost;

            WHILE @@FETCH_STATUS = 0 AND @remaining > 0
            BEGIN
                SET @take = CASE WHEN @avail <= @remaining THEN @avail ELSE @remaining END;

                UPDATE Inventory
                SET Available = Available - @take,
                    IsStock = CASE WHEN Available - @take <= 0 THEN 0 ELSE IsStock END,
                    LastMovementDate = CAST(GETDATE() AS date)
                WHERE SequenceNumber = @seq;

                INSERT INTO InventoryAdjustmentFIFO
                (
                    BranchCode, ProductCode, Description, OrigQty, QtyDeducted,
                    Cost, SequenceReferenceNumber, DateAdded, ExecuteBy
                )
                VALUES
                (
                    @parmbranchcode, @parmprodcode, @parmdesc, @avail, @take,
                    @rowcost, @seq, GETDATE(), @parmuser
                );

                SET @remaining = @remaining - @take;

                FETCH NEXT FROM fifo_cursor INTO @seq, @avail, @rowcost;
            END

            CLOSE fifo_cursor;
            DEALLOCATE fifo_cursor;

            IF @remaining > 0
            BEGIN
                ROLLBACK TRAN;
                THROW 93000, 'Insufficient stock to complete FIFO deduction.', 1;
            END
        END
        ELSE
        BEGIN
            ROLLBACK TRAN;
            THROW 93002, 'AdjustmentType must be ADD or DEDUCT.', 1;
        END

        INSERT INTO HistoryLogs VALUES(@parmuser, GETDATE(), 'QTY ADJUSTMENT (' + @parmadjustmenttype + ') Product=' + @parmprodcode + ' Qty=' + CAST(@parmqtyadj AS varchar(20)), @parmbranchcode);

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        IF CURSOR_STATUS('local', 'fifo_cursor') >= 0
        BEGIN
            CLOSE fifo_cursor;
            DEALLOCATE fifo_cursor;
        END
        DECLARE @errMsg nvarchar(4000) = ERROR_MESSAGE();
        THROW 93001, @errMsg, 1;
    END CATCH
END
GO
PRINT 'DEPLOYMENT COMPLETE: sp_InvQtyAdjustment rewritten, original preserved as sp_InvQtyAdjustment_OLD_08032026144611.';
