-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- ============================================= exec sp_ReInventoryAnalyzer '5494','001' exec sp_ReInventoryAnalyzer '5495','008' 
CREATE PROCEDURE [dbo].[sp_ReInventoryAnalyzer]
	@parmbatchid int,
	@parmbranchcode varchar(5)
AS
BEGIN

	create table #temptable(
		tempbranchcode varchar(5),
		tempprodcode varchar(5),
		tempprodname varchar(60),
		tempqtysold float,
		tempavailable float,
		tempvariance float,
		tempstatus varchar(20),
		tempisvat bit
	)

    truncate table #temptable
	declare @brcode varchar(6),@pcode varchar(5),@desc varchar(200),@qty float,@invprodcode varchar(5),@invavailable float,@remarks varchar(50),@variance float
	Declare AnalyzeCursor Cursor for
		Select Branch,Product,Description,SUM(Quantity) as Quantity FROM TempInventoryIN --select * FROM TempInventoryIN WHERE Branch='008'
		WHERE ID=@parmbatchid
		GROUP BY Branch,Product,Description
			OPEN AnalyzeCursor
				fetch next from AnalyzeCursor into @brcode,@pcode,@desc,@qty
					WHILE @@FETCH_STATUS=0
					begin

						SELECT @invprodcode=Product,@invavailable=SUM(Available) 
						FROM Inventory 
						WHERE Branch=@parmbranchcode and IsStock=1 and Available > 0 and Product=@pcode and Branch=@brcode-- and IsWarehouse=1
						GROUP BY Product
						
						if @@ROWCOUNT=0
						begin
							set @remarks = 'NO INVENTORY' 
							insert into #temptable values(@parmbranchcode,@pcode,@desc,@qty,0,0,@remarks,0)
						end

						if(@pcode=@invprodcode)
						begin
							set @variance = @invavailable-@qty
							if(@variance < 0)
							set @remarks = 'FAILED'
							else
							set @remarks = 'PASSED'
							insert into #temptable values(@parmbranchcode,@pcode,@desc,@qty,@invavailable,@variance,@remarks,0)
						end

						fetch next from AnalyzeCursor into @brcode,@pcode,@desc,@qty
					end
			CLOSE AnalyzeCursor
	DEALLOCATE AnalyzeCursor

	insert into #temptable
	SELECT Branch,Product,Description,0,SUM(Available),SUM(Available),'EXISTING STOCK ITEMS',IsVat
    FROM Inventory 
	WHERE Product not in (Select Product FROM TempInventoryIN WHERE ID=@parmbatchid)
	and Branch=@parmbranchcode and IsStock=1 and Available > 0
	GROUP BY Branch,Product,Description,IsVat

	SELECT 
	tempbranchcode as BranchCode,
	tempprodcode as ProductCode,
	tempprodname as ProductName,
	tempqtysold as Qty,
	tempavailable as AvailableOnHand,
	tempvariance as Variance,
	tempstatus as Status,
	tempisvat as isVat
	--INTO TempEulz008
	FROM #temptable

	
END
