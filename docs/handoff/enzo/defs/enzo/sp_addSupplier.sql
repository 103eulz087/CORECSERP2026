

CREATE PROCEDURE [dbo].[sp_addSupplier]
	@parmsuppkey varchar(15),
	@parmid varchar(10),
	@parmsuppliername varchar(50),
	@parmaddress varchar(100),
	@parmcontact varchar(20),
	@parmofficer varchar(30),
	@parmtinno varchar(30),
	@parmtradename varchar(50),
	@parmlineofbusiness varchar(50),
	@parmisvat bit,
	@parmislocal bit,
	@exectype varchar(20) 
AS

declare @idinc int
set @idinc=1

declare @id varchar(10)
set @id = '000'

declare @supplierid varchar(10)
set @supplierid=@id+@idinc

BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	if(@exectype='ADD')
	begin
		--select * FROM Supplier truncate table Supplier
		INSERT INTO Supplier VALUES(@parmsuppkey,@parmid,@parmsuppliername,@parmaddress,@parmcontact,@parmofficer,@parmtinno,@parmtradename,@parmlineofbusiness,@parmisvat,@parmislocal)
	end
	else if(@exectype='UPDATE') 
	begin
		UPDATE Supplier set SupplierName=@parmsuppliername,Address=@parmaddress,ContactNo=@parmcontact,Officer=@parmofficer,TinNo=@parmtinno,TradeName=@parmtradename,LineOfBusiness=@parmlineofbusiness,
		isVat=@parmisvat,isLocal=@parmislocal WHERE SupplierKey=@parmsuppkey
	end

END
