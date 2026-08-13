SET NOCOUNT ON;
PRINT '=== sp_InvQtyAdjustment: simplified signature (Branch/Product/Qty/Type only) ===';
GO
EXEC sp_rename 'dbo.sp_InvQtyAdjustment', 'sp_InvQtyAdjustment_OLD_08032026183949';
GO
SET QUOTED_IDENTIFIER ON;
GO
-- =============================================
-- Author:      Eulz Avancena (original 12/5/2017); rewritten 2026-08-03
-- Description: Branch inventory quantity adjustment (ADD or DEDUCT).
--
--   ADD    -> directly inserts a new Inventory row for the branch/product
--             carrying the adjustment quantity, costed from
--             Products.LandingCost.
--   DEDUCT -> consumes existing Inventory rows for that branch/product in
--             chronological (FIFO) order - oldest DateReceived first - one
--             row at a time, decrementing Available until the requested
--             quantity is fully accounted for. The audit CostKg/
--             AmountAdjusted reflect the true weighted-average cost of the
--             specific batches actually consumed, not a guess.
--
-- 2026-08-03: signature simplified further - the calling form
-- (InventoryQtyAdjustmentDevEx.cs) no longer has Cost/Available Qty/New
-- Qty UI fields, so those figures are now resolved authoritatively inside
-- this procedure instead of being round-tripped through (possibly stale)
-- UI textboxes. Only Branch, Product, Qty Adjustment and Adjustment Type
-- are supplied by the caller now.
-- Previous version preserved as sp_InvQtyAdjustment_OLD_08032026183949.
-- =============================================
CREATE PROCEDURE [dbo].[sp_InvQtyAdjustment]
    @parmbranchcode      varchar(5),
    @parmprodcode        varchar(10),
    @parmdesc            varchar(120),
    @parmqtyadj          float,          -- quantity being added or deducted
    @parmadjustmenttype  varchar(50),    -- 'ADD' or 'DEDUCT'
    @parmuser            varchar(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @parmqtyadj IS NULL OR @parmqtyadj <= 0
    BEGIN
        THROW 93003, 'Qty Adjustment must be greater than zero.', 1;
    END

    IF @parmadjustmenttype NOT IN ('ADD', 'DEDUCT')
    BEGIN
        THROW 93002, 'AdjustmentType must be ADD or DEDUCT.', 1;
    END

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @isvat bit = 0, @prodcatcode varchar(5);
        SELECT @prodcatcode = ProductCategoryCode FROM Products WHERE BranchCode = '888' AND ProductCode = @parmprodcode;
        SELECT @isvat = isVat FROM ProductCategory WHERE ProductCategoryID = @prodcatcode;
        SET @isvat = ISNULL(@isvat, 0);

        DECLARE @currentavailable float;
        SELECT @currentavailable = ISNULL(SUM(Available), 0)
        FROM Inventory
        WHERE Branch = @parmbranchcode AND Product = @parmprodcode AND IsStock = 1;

        DECLARE @cost money = 0, @amountadjusted money = 0, @newqty float;

        IF @parmadjustmenttype = 'ADD'
        BEGIN
            -- Cost source: most recent actual Inventory cost for this
            -- product at this branch; fall back to the most recent cost at
            -- any branch if it's never been stocked here - Products.LandingCost
            -- is not a reliable source (unpopulated/zero in this dataset).
            SELECT TOP 1 @cost = Cost
            FROM Inventory
            WHERE Product = @parmprodcode AND Branch = @parmbranchcode
            ORDER BY DateReceived DESC, SequenceNumber DESC;

            IF @cost IS NULL
            BEGIN
                SELECT TOP 1 @cost = Cost
                FROM Inventory
                WHERE Product = @parmprodcode
                ORDER BY DateReceived DESC, SequenceNumber DESC;
            END

            SET @cost = ISNULL(@cost, 0);
            SET @amountadjusted = @cost * @parmqtyadj;
            SET @newqty = @currentavailable + @parmqtyadj;

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
                @parmprodcode, @parmdesc, '', 0, @parmqtyadj, @cost, @parmqtyadj,
                0, 1, @isvat, 1, 'QTYADJ', CAST(GETDATE() AS date),
                0, 1, 0
            );
        END
        ELSE -- DEDUCT
        BEGIN
            IF @currentavailable < @parmqtyadj
            BEGIN
                ROLLBACK TRAN;
                THROW 93000, 'Insufficient stock to complete FIFO deduction.', 1;
            END

            DECLARE @remaining float = @parmqtyadj;
            DECLARE @seq int, @avail decimal(18,3), @rowcost decimal(18,2), @take float;
            DECLARE @totalcostremoved money = 0;

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

                SET @totalcostremoved = @totalcostremoved + (@take * @rowcost);
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

            SET @amountadjusted = @totalcostremoved;
            SET @cost = CASE WHEN @parmqtyadj > 0 THEN @totalcostremoved / @parmqtyadj ELSE 0 END;
            SET @newqty = @currentavailable - @parmqtyadj;
        END

        -- Audit header row - uses the authoritative, server-computed figures
        INSERT INTO InventoryAdjustment
        (
            BranchCode, ShipmentNo, ProductCode, Description, Quantity, CostKg,
            QtyAdjustment, CostAdjustment, NewQty, NewCost, AmountAdjusted,
            SeqRefNum, DateAdjusted, isVat, AdjustmentType, isCost, isQty
        )
        VALUES
        (
            @parmbranchcode, '', @parmprodcode, @parmdesc, @currentavailable, @cost,
            @parmqtyadj, 0, @newqty, 0, @amountadjusted,
            '', GETDATE(), @isvat, @parmadjustmenttype, 0, 1
        );

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
PRINT 'DEPLOYMENT COMPLETE: sp_InvQtyAdjustment simplified, previous version preserved as sp_InvQtyAdjustment_OLD_08032026183949.';
