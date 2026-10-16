CREATE   PROCEDURE [dbo].[sp_StageManualEntryForReInventoryIN]
(
    @parmid       INT,
    @parmbranch   VARCHAR(5),
    @parmdatereceived date,
    @parmexpirydate date,
    @parmproductcode varchar(5),
    @parmbarcode  VARCHAR(120),
    @parmqty decimal(12,3),
    @parmcost decimal(12,2),
    @parmiswarehouse bit,
    @parmuser     VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
   
        declare @prodname varchar(250),@isvat bit
        SELECT @prodname=Description,@isvat=isVat FROM Products WHERE BranchCode=@parmbranch and ProductCode=@parmproductcode
        ---------------------------------------------------------------------
        -- Idempotency Check SELECT * FROM TempInventoryIN
        -- If barcode already staged for this document, do nothing.
        ---------------------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM dbo.TempInventoryIN
            WHERE ID = @parmid
              AND Barcode = @parmbarcode
        )
        BEGIN
            COMMIT TRANSACTION;
            RETURN;
        END;

        ---------------------------------------------------------------------
        -- Remove Existing Record (if any)
        ---------------------------------------------------------------------
        DELETE FROM dbo.TempInventoryIN
        WHERE ID = @parmid
          AND Barcode = @parmbarcode;

        ---------------------------------------------------------------------
        -- Insert Staging Record
        ---------------------------------------------------------------------
        ---------------------------------------------------------------------
        -- Create New Re-Inventory Snapshot select top 1 * FROM TempInventoryIN
        ---------------------------------------------------------------------
        INSERT INTO dbo.TempInventoryIN
        (
            ID,
            Branch,
            DateReceived,
            ExpiryDate,
            Product,
            Description,
            Barcode,
            Quantity,
            Cost,
            isWarehouse,
            IsVat,
            DateEncode,
            EncodeBy
        )
        SELECT
            @parmid,
            @parmbranch,
            @parmdatereceived,
            @parmexpirydate,
            @parmproductcode,
            @prodname,
            @parmbarcode,
            @parmqty,
            @parmcost,
            @parmiswarehouse,
            @isvat,
            GETDATE(),
            @parmuser;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        DECLARE @Msg NVARCHAR(2048);

        SET @Msg = ERROR_MESSAGE();

        RAISERROR(@Msg, 16, 1);
    END CATCH
END;
