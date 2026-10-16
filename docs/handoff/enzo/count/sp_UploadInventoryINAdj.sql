
CREATE PROCEDURE [dbo].[sp_UploadInventoryINAdj]
	@parmid varchar(20)
	,@parmbranchcode char(3)=''
AS
BEGIN
	SET NOCOUNT ON;
	BEGIN TRAN
	DELETE FROM [dbo].[Inventory] WHERE ReferenceCode=@parmid and Branch=@parmbranchcode
	INSERT INTO [dbo].[Inventory]
			   ([Branch]
			   ,ShipmentNo
			   ,PalletNo
			   ,[DateReceived]
			   ,[ExpiryDate]
			   ,[Product]
			   ,[Description]
			   ,[Barcode]
			   ,[Quantity]
			   ,[Available]
			   ,IsStock
			   ,[Cost]
			   ,[isVat]
			   ,IsWarehouse
			   ,ReferenceCode
			   ,isSource
			   ,[LastMovementDate])
	SELECT 
			Branch--[BranchCode]
			,' '
			,0
			,DateReceived	   --        ,[DateReceived]
			,DATEADD(YEAR,1,DateReceived)	   --        ,[ExpiryDate]
			,Product--        ,[ProductCode]
			,Description	   --        ,[Description]
			,Barcode	   --        ,[Barcode]
			,Quantity	   --        ,[Quantity]
			,Quantity	   --        ,[Available]
			,1
			,Cost	   --        ,[Cost]
			,isVat	   --        ,[isVat]
			,IsWarehouse
			,ID
			,1
			,GETDATE()	   --        ,[LastMovementDate] select * FROM InventoryIN
	FROM InventoryIN
	WHERE ID=@parmid
	and Branch=@parmbranchcode
	and isProcess=0

	declare @a int,@b int
	set @a=0
	set @b=0
	SELECT @a=ISNULL(COUNT(*),0) FROM Inventory WHERE ReferenceCode=@parmid and Branch=@parmbranchcode
	SELECT @b=ISNULL(COUNT(*),0) FROM InventoryIN WHERE ID=@parmid and Branch=@parmbranchcode
	IF @a<>@b
	BEGIN	
		raiserror('Record Not Matched... Inventory Rollback',16,1) 
		set nocount off
		select 2 as status, 'Error' as message
		rollback tran
		return
	END
	ELSE
	BEGIN	
		UPDATE InventoryIN SET isProcess=1--isDone=1 
		WHERE ID=@parmid
		and Branch=@parmbranchcode
		and isProcess=0
		commit tran
	END
END
 