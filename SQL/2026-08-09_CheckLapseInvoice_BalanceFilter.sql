SET NOCOUNT ON;
PRINT '=== func_checkLapseInvoice: only count invoices that still have a balance ===';
GO
EXEC sp_rename 'dbo.func_checkLapseInvoice', 'func_checkLapseInvoice_OLD_08092026114617';
GO
SET QUOTED_IDENTIFIER ON;
GO
-- =============================================
-- Author:      Eulz Avancena (original); rewritten 2026-08-09
-- Description: Flags (1/0) whether a customer has any invoice past its credit term
--              (Orders/AddOrder.cs, add2()/addServices()).
--
-- CHANGELOG FROM func_checkLapseInvoice (legacy, now func_checkLapseInvoice_OLD_08092026114617):
--   [1] Added "AND Balance > 0". The old version counted ANY TransactionChargeSales row past
--       term, including fully-paid ones (Balance=0) -- meaning a customer with an old but
--       already-settled invoice would incorrectly trip this trap forever. Matches the scenario
--       given for this rewrite explicitly: "if there are invoice WITH BALANCE and it is already
--       lapse".
-- =============================================
CREATE FUNCTION [dbo].[func_checkLapseInvoice]
(
	@parmcustkey char(8)
)
RETURNS INT
AS
BEGIN
	declare @flag int=0
	DECLARE @num int,@term smallint

	select @term=Term FROM Customers WHERE CustomerKey=@parmcustkey

	select @num=COUNT(*) FROM TransactionChargeSales
	WHERE CustomerKey=@parmcustkey
	  AND Balance > 0
	  AND DATEDIFF(DAY,TransactionDate,GETDATE()) > @term

	if(@num > 0)
	set @flag=1
	else
	set @flag=0

	RETURN @flag
END
GO
PRINT 'DEPLOYMENT COMPLETE: func_checkLapseInvoice rewritten, original preserved as func_checkLapseInvoice_OLD_08092026114617.';
