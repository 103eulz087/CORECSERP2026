CREATE FUNCTION [dbo].[func_checkLapseInvoice]
(
	@parmcustkey char(8)
	
)
RETURNS INT
AS
BEGIN
	
	-- Declare the return variable here
	declare @flag int=0
	DECLARE @num int,@term smallint

	select @term=Term FROM Customers WHERE CustomerKey=@parmcustkey

	-- Add the T-SQL statements to compute the return value here
	select @num=COUNT(*) FROM TransactionChargeSales WHERE CustomerKey=@parmcustkey and DATEDIFF(DAY,TransactionDate,GETDATE()) > @term
	
	if(@num > 0)
	set @flag=1
	else
	set @flag=0
	-- Return the result of the function
	--select @flag as Resultset
	RETURN @flag 
	
	--select dbo.func_checkLapseInvoice('BAC-AGCY-001')
END
