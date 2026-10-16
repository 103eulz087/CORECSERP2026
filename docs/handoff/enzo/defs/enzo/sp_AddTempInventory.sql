



CREATE PROCEDURE [dbo].[sp_AddTempInventory]
	-- Add the parameters for the stored procedure here
	@parmbranchcode VARCHAR(5),
	@parmshipmentno VARCHAR(10),
	@parmpalletno VARCHAR(50),
	@parmprodcode VARCHAR(50),
	@parmprodname VARCHAR(150),
	@parmbarcode VARCHAR(150),
	@parmtipweight FLOAT,
	@parmqty FLOAT,
	@parmcost VARCHAR(20),
	@parmisoverride BIT,
	@parmisusebarcode bit,
	@parmexpirydate date
	 

AS
BEGIN
declare @barcode varchar(100)
IF @parmisusebarcode=1
BEGIN
	set @barcode=@parmbarcode
END
ELSE 
BEGIN
	SELECT TOP(1) @barcode=Barcode FROM dbo.Products with(nolock) WHERE ProductCode=@parmprodcode and BranchCode='888'
END

declare @cost VARCHAR(20)
IF @parmisoverride = 1
BEGIN
	SET @cost=@parmcost
END
ELSE
BEGIN
	--SELECT @cost=ISNULL(CostKg,0) FROM InventoryCost WHERE ProductCode=@productcode and SupplierID=@supplierID
	--select * FROM PODETAILS
	SELECT @cost=ISNULL(Cost,0)
	FROM PODETAILS 
	WHERE OrderCode=@parmprodcode 
	AND ShipmentNo=@parmshipmentno
END

INSERT INTO [dbo].[TempInventory]
           ([Branch]
		   ,[ShipmentNo]
           ,[PalletNo]
           ,[DateReceived]
           ,[Product]
           ,[Description]
		   ,[Cost]
           ,[Barcode]
           ,[TipWeight]
           ,[Quantity]
           ,[Available]
           ,[IsStock]
           ,[IsVat]
           ,[IsWarehouse],[LastMovementDate],[isProcess],[isSource],[isConversion])
     VALUES
           (@parmbranchcode
		   ,@parmshipmentno
           ,@parmpalletno
           ,GETDATE()
           ,@parmprodcode
           ,@parmprodname
		   ,ISNULL(@cost,0)
           ,@parmbarcode
           ,@parmtipweight
           ,@parmqty
           ,@parmqty
           ,1 --isstock
           ,0
           ,1,
		   @parmexpirydate,
		   0,
		   1,
		   0)
         
END

