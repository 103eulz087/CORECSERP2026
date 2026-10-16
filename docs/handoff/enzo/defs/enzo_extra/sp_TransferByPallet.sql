CREATE PROCEDURE [dbo].[sp_TransferByPallet]
    @parmshipmentno   varchar(5),
    @parmprodcode     varchar(10),
    @parmpalletno     int,
    @parmbatchnumber  varchar(8),
    @parmdispatchno   varchar(10),
    @parmsource       varchar(30),
    @parmdestination  varchar(30),
    @parmuser         varchar(30),
    @parmoption       varchar(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Normalize inputs if needed (SQL 2022+ TRIM is built-in; otherwise use LTRIM/RTRIM)
    -- SET @parmdestination = TRIM(@parmdestination);
    -- SET @parmoption = TRIM(@parmoption);



    DECLARE @now datetime2(0) = SYSUTCDATETIME(); -- or GETDATE() if you prefer local time
    DECLARE @targetWarehouse bit =
        CASE WHEN @parmdestination = 'Commissary' THEN 1 ELSE 0 END; -- Commissary=1, BigBlue=0
    DECLARE @sourceWarehouse bit = IIF(@targetWarehouse = 1, 0, 1);

    BEGIN TRY
        BEGIN TRAN;

        --------------------------------------------------------------------
        -- If a prior staging row exists for same batch/shipment/pallet, delete it
        --------------------------------------------------------------------
    --    DELETE FROM dbo.TempInventoryTransfer
    --    WHERE BatchNumber = @parmbatchnumber
    --      AND PalletNo    = @parmpalletno
		  --AND Product = @parmprodcode
    --      AND ShipmentNo  = @parmshipmentno;

        --------------------------------------------------------------------
        -- ADD: stage the items from Inventory -> TempInventoryTransfer
        --------------------------------------------------------------------
        IF (@parmoption = 'ADD')
        BEGIN
            INSERT INTO dbo.TempInventoryTransfer
            (
                BatchNumber, ShipmentNo, PalletNo, Product,
                [Description], Barcode, Quantity, isTransfer
            )
            SELECT
                @parmbatchnumber,
                @parmshipmentno,
                @parmpalletno,
                I.Product,
                I.[Description],
                I.Barcode,
                I.Available,  -- quantity staged equals current available
                0             -- not yet transferred
            FROM dbo.Inventory AS I WITH (READCOMMITTEDLOCK)
            WHERE I.ShipmentNo = @parmshipmentno
              AND I.PalletNo   = @parmpalletno
              AND I.Product    = @parmprodcode
              AND I.IsWarehouse = @sourceWarehouse
              AND I.Available  > 0;

            -- Return current staged rows for this batch/shipment
            SELECT PalletNo, [Description], Barcode, Quantity
            FROM dbo.TempInventoryTransfer
            WHERE BatchNumber = @parmbatchnumber
              AND ShipmentNo  = @parmshipmentno;
        END
        --------------------------------------------------------------------
        -- SAVE: finalize the transfer (flip IsWarehouse; mark staged rows)
        --------------------------------------------------------------------
        ELSE IF (@parmoption = 'SAVE')
        BEGIN
            -- Update inventory only when the item is where we expect it (sourceWarehouse) and Available > 0
            
		IF EXISTS
            (
                SELECT 1
                FROM dbo.Inventory AS I WITH (READCOMMITTEDLOCK)
                WHERE I.ShipmentNo  = @parmshipmentno
                  AND I.PalletNo    = @parmpalletno
                  AND I.IsWarehouse = @sourceWarehouse
                  AND I.Available   > 0
                  AND NOT EXISTS (
                        SELECT 1
                        FROM dbo.TempInventoryTransfer AS T WITH (READCOMMITTEDLOCK)
                        WHERE T.BatchNumber = @parmbatchnumber
                          AND T.ShipmentNo  = I.ShipmentNo
                          AND T.PalletNo    = I.PalletNo
                          AND T.Product     = I.Product
                  )
            )
            BEGIN
                print 'Cannot SAVE: not all pallet items are staged in TempInventoryTransfer for this batch.'
            END;

            -- All good: update every eligible Inventory row in the pallet
            UPDATE I
                SET I.IsWarehouse      = @targetWarehouse,
                    I.LastMovementDate = @now,
                    I.ReferenceCode    = @parmbatchnumber
            FROM dbo.Inventory AS I WITH (ROWLOCK, UPDLOCK)
            WHERE I.ShipmentNo  = @parmshipmentno
              AND I.PalletNo    = @parmpalletno
              AND I.IsWarehouse = @sourceWarehouse
              AND I.Available   > 0
              AND EXISTS (
                    SELECT 1
                    FROM dbo.TempInventoryTransfer AS T
                    WHERE T.BatchNumber = @parmbatchnumber
                      AND T.ShipmentNo  = I.ShipmentNo
                      AND T.PalletNo    = I.PalletNo
                      AND T.Product     = I.Product
              );

            DECLARE @rows int = @@ROWCOUNT;

            -- Mark staged rows as transferred then clean up temp for this pallet+batch
            UPDATE T
                SET T.isTransfer = 1
            FROM dbo.TempInventoryTransfer AS T WITH (ROWLOCK)
            WHERE T.BatchNumber = @parmbatchnumber
              AND T.ShipmentNo  = @parmshipmentno
              AND T.PalletNo    = @parmpalletno;

            DELETE FROM dbo.TempInventoryTransfer
            WHERE BatchNumber = @parmbatchnumber
              AND ShipmentNo  = @parmshipmentno
              AND PalletNo    = @parmpalletno;

            -- Optional: return a simple status
            SELECT
                BatchNumber = @parmbatchnumber,
                ShipmentNo  = @parmshipmentno,
                PalletNo    = @parmpalletno,
                RowsUpdated = @rows,
                Destination = @parmdestination,
                MovedToWarehouse = @targetWarehouse;

            COMMIT;
            RETURN;
        END;

        -- Fallback (should not reach here due to validation)
        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        THROW; -- rethrow original error
    END CATCH
END

