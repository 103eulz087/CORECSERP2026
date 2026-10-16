CREATE TRIGGER [dbo].[sp_TrgInsertClientInfo]
   ON  dbo.Customers
   AFTER INSERT
AS 
BEGIN

	declare @acctkey char(8),@acctid varchar(50),@acctname varchar(150)
	select @acctkey=CustomerKey,@acctid=CustomerID,@acctname=CustomerName from inserted
	INSERT INTO ClientAccounts
	select @acctkey,@acctid,@acctname,'Active',0,0,GETDATE() from inserted

END
