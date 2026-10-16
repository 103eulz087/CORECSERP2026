
CREATE TRIGGER [dbo].[sp_TrgInsertSupplierInfo]
   ON  [dbo].[Supplier]
   AFTER INSERT
AS 
declare @acctid varchar(50),@acctname varchar(100),@maxid int,@acctno varchar(13),@suppkey varchar(20)
BEGIN
	--select @maxid=MAX(CAST(AccountNumber as int)) FROM SupplierAccounts
	--set @acctno = dbo.func_SequencePaddingDynamic2(cast(@maxid as varchar(20)),11)
	select @suppkey=SupplierKey,@acctid=SupplierID,@acctname=SupplierName from inserted

	INSERT INTO SupplierAccounts --select * FROM Supplier select * FROM SupplierAccounts 
	select @suppkey,@acctid,@acctname,'Active',0,GETDATE() from inserted

END