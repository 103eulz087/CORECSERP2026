
CREATE PROCEDURE [dbo].[sp_UploadInventoryIN]
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
			,DateReceived	   --        ,[DateReceived]
			,ExpiryDate	   --        ,[ExpiryDate]
			,Product--        ,[ProductCode]
			,Description	   --        ,[Description]
			,Barcode	   --        ,[Barcode]
			,Quantity	   --        ,[Quantity]
			,Quantity	   --        ,[Available]
			,1
			,Cost	   --        ,[Cost]
			,isVat	   --        ,[isVat]
			,1
			,ID
			,1
			,GETDATE()	   --        ,[LastMovementDate]
	FROM TempInventoryIN
	WHERE ID=@parmid
	and Branch=@parmbranchcode
	and isDone=0

	declare @a int,@b int
	set @a=0
	set @b=0
	SELECT @a=ISNULL(COUNT(*),0) FROM Inventory WHERE ReferenceCode=@parmid and Branch=@parmbranchcode
	SELECT @b=ISNULL(COUNT(*),0) FROM TempInventoryIN WHERE ID=@parmid and Branch=@parmbranchcode
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
		UPDATE TempInventoryIN SET isDone=1 
		WHERE ID=@parmid
		and Branch=@parmbranchcode
		and isDone=0
		commit tran
	END
END
 