
CREATE PROCEDURE [dbo].[sp_StageBarcodeForReInventoryIN]-- 

    @parmid      INT, 

    @parmbranch   VARCHAR(5), 

    @parmbarcode  VARCHAR(120), 

    @parmuser     VARCHAR(50) 

AS 

BEGIN 

  

    SET NOCOUNT ON; 

    SET XACT_ABORT ON; 

  

DECLARE 

@Branch varchar(5) 

,@ShipmentNo varchar(10) 

,@PalletNo int 

,@BatchCode int 

,@DateReceived date 

,@ExpiryDate date 

,@Product varchar(10) 

,@Description varchar(300) 

,@Barcode varchar(35) 

,@TipWeight float 

,@Quantity decimal(18,3) 

,@Cost decimal(18,2) 

,@Available decimal(18,3) 

,@QtyBigBlue decimal(18,3) 

,@IsStock bit 

,@IsVat bit 

,@IsWarehouse bit 

,@ReferenceCode varchar(100) 

,@LastMovementDate date 

,@isProcess bit 

,@isSource bit 

,@isConversion bit 

  

  

  

    BEGIN TRY 

        BEGIN TRAN; 

  

        ---- Optional: initialize header if not exists 

        --IF NOT EXISTS (SELECT 1 FROM dbo.TransferBatch WHERE BatchNo = @BatchNo) 

        --BEGIN 

        --    INSERT INTO dbo.TransferBatch (BatchNo, Source, Destination, BranchCode, CreatedBy) 

        --    VALUES (@BatchNo, @Source, @Destination, @Branch, @UserName); 

        --END 

  

        -- Validate item is currently in Source & available at this branch 

        DECLARE @Seq BIGINT; 

  

        SELECT TOP (1)  

@Branch=Branch 

,@ShipmentNo=ShipmentNo 

,@PalletNo=PalletNo 

,@BatchCode=BatchCode 

,@DateReceived=DateReceived 

,@ExpiryDate=ExpiryDate 

,@Product=Product 

,@Description=Description 

,@Barcode=Barcode 

--,@TipWeight=TipWeight 

,@Quantity=Quantity 

,@Cost=Cost 

,@Available=Available 

--,@QtyBigBlue=QtyBigBlue 

,@IsStock=IsStock 

,@IsVat=IsVat 

,@IsWarehouse=IsWarehouse 

,@ReferenceCode=ReferenceCode 

,@LastMovementDate=LastMovementDate 

,@isProcess=isProcess 

,@isSource=isSource 

,@isConversion=isConversion 

,@Seq=SequenceNumber 

        FROM dbo.Inventory AS i WITH (READCOMMITTEDLOCK)  

        WHERE i.Barcode = @parmbarcode 

          AND i.Branch = @parmbranch 

          --AND i.Available > 0 

          --AND ((@Source = 'Commissary' AND i.isWarehouse = 1) 

          --  OR (@Source = 'BigBlue'    AND i.isWarehouse = 0)); 

  

        IF @Seq IS NULL 

        BEGIN 

            RAISERROR('Barcode not found in %s with available > 0 for this branch.', 16, 1, @shipmentno); 

        END 

  

        -- Idempotency: avoid duplicate staging for the same Batch/SequenceNumber --SELECT * FROM InventoryIN 

        IF EXISTS (SELECT 1 FROM dbo.[InventoryINMonthEnd] WHERE ID = @parmid AND Barcode = @parmbarcode) 

        BEGIN 

            -- Nothing to do; already staged 

            COMMIT TRAN; 

            RETURN; 

        END 

DELETE FROM [dbo].[InventoryINMonthEnd] WHERE ID = @parmid AND Barcode = @parmbarcode 

INSERT INTO [dbo].[InventoryINMonthEnd] 

   ([ID] 

   ,[Branch] 

   ,[Barcode] 

   ,[IsWarehouse] 

   ,[AddedBy]  

   ,DateAdded  

   ,UpdatedBy  

   ,DateUpdated  

) 

SELECT @parmid 

,@Branch --[Branch] 

,@Barcode --,[Barcode] 

,@IsWarehouse --,[IsWarehouse] 

,@parmuser --,[EncodeBy] 

,GETDATE() 

,@parmuser 

,GETDATE() 

  

  

        COMMIT TRAN; 

    END TRY 

    BEGIN CATCH 

        IF XACT_STATE() <> 0 ROLLBACK TRAN; 

  

        DECLARE @Msg NVARCHAR(2048) = ERROR_MESSAGE(); 

        RAISERROR(@Msg, 16, 1); 

    END CATCH 

END 