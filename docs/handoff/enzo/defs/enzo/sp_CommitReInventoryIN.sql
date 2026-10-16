
CREATE PROCEDURE [dbo].[sp_CommitReInventoryIN] 

     @parmid      INT 

AS 

BEGIN 

    SET NOCOUNT ON; 

    SET XACT_ABORT ON; 

  

    BEGIN TRY 

        BEGIN TRAN; 

  

DELETE FROM [dbo].[Inventory] WHERE ReferenceCode='INVIN-'+CONVERT(VARCHAR(10),@parmid)    

INSERT INTO [dbo].[Inventory] 

   ([Branch] 

   ,[ShipmentNo] 

   ,[PalletNo] 

   ,[BatchCode] 

   ,[DateReceived] 

   ,[ExpiryDate] 

   ,[Product] 

   ,[Description] 

   ,[Barcode] 

   ,[TipWeight] 

   ,[Quantity] 

   ,[Cost] 

   ,[Available] 

   ,[QtyBigBlue] 

   ,[IsStock] 

   ,[IsVat] 

   ,[IsWarehouse] 

   ,[ReferenceCode] 

   ,[LastMovementDate] 

   ,[isProcess] 

   ,[isSource] 

   ,[isConversion]) 

SELECT a.[Branch] 

   ,b.[ShipmentNo] 

   ,b.[PalletNo] 

   ,b.[BatchCode] 

   ,b.[DateReceived] 

   ,b.[ExpiryDate] 

   ,b.[Product] 

   ,b.[Description] 

   ,a.[Barcode] 

   ,0 

   ,b.[Quantity] 

   ,b.[Cost] 

   ,b.[Quantity] 

   ,0 

   ,b.[IsStock] 

   ,b.[IsVat] 

   ,a.[IsWarehouse] 

   ,'INVIN-'+CONVERT(VARCHAR(10),@parmid) 

   ,GETDATE() 

   ,b.[isProcess] 

   ,b.[isSource] 

   ,b.[isConversion] 

FROM dbo.[InventoryINMonthEnd] a with(nolock) 

INNER JOIN dbo.Inventory b 

ON a.Barcode=b.Barcode 

and a.Branch=b.Branch 

WHERE ID=@parmid 

  

        COMMIT TRAN; 

    END TRY 

    BEGIN CATCH 

      IF XACT_STATE() <> 0 ROLLBACK; 

        THROW; 

    END CATCH 

END 