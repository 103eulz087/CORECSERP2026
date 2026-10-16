-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
CREATE TRIGGER [dbo].[trg_AutoAddProducts]
   ON  [dbo].[Branches]
   AFTER INSERT
AS 
	declare @branchcode varchar(5)
	select @branchcode=BranchCode from inserted
BEGIN
	
	
	

	INSERT INTO Products
	select  @branchcode,ProductCode,Description,Description,LandingCost,SellingPrice,ProductCategoryCode,
	Price1,Price2,Price3,Price4,isRegular,isPrice1,isPrice2,isPrice3,isPrice4,isDiscount,haveBarcode,Barcode,ReOrderLevel,isVat,ProdType
	 FROM dbo.Products WHERE BranchCode='888'

	
END
