CREATE   PROCEDURE [dbo].[sp_CommitReInventoryINManualEntry]
(
    @parmid INT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        

        ---------------------------------------------------------------------
        -- Create New Re-Inventory Snapshot SELECT TOP 1 * FROM Inventory SELECT TOP 1 * FROM TempInventoryIN
        ---------------------------------------------------------------------
        INSERT INTO dbo.Inventory
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
            Quantity,
            Cost,
            Available,
            IsStock,
            IsVat, 
            IsWarehouse,
            ReferenceCode,
            isProcess,
            isSource,
            isConversion
        )
        SELECT
            Branch,--Branch,
            ' ',--ShipmentNo,
            0,--PalletNo,
            '',--BatchCode,
            DateReceived,--DateReceived,
            ExpiryDate,--ExpiryDate,
            Product,--Product,
            Description,--Description,
            Barcode,--Barcode,
            Quantity,--Quantity,
            Cost,--Cost,
            Quantity,--Available,
            1,--IsStock,
            isVat,--IsVat, 
            isWarehouse,--IsWarehouse,
            'INVIN-'+ CAST(@parmid as varchar(5)),--ReferenceCode,
            1,--isProcess,
            1,--isSource,
            0--isConversion
        FROM dbo.TempInventoryIN  WITH (NOLOCK)
        WHERE ID = @parmid;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END;
