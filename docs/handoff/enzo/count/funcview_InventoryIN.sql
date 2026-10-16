
CREATE FUNCTION [dbo].[funcview_InventoryIN] 

(  

@parmid int 

) 

RETURNS TABLE  

AS 

RETURN  

( 

SELECT a.SequenceNumber,b.Product,b.Description,a.Barcode,b.Quantity,b.Cost  

FROM dbo.[InventoryINMonthEnd] a with(nolock) 

INNER JOIN dbo.Inventory b 

ON a.Barcode=b.Barcode 

and a.Branch=b.Branch 

and b.ReferenceCode not like 'INVIN%' 

WHERE a.ID=@parmid  

) 
