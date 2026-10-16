



CREATE   VIEW [dbo].[view_DeliveryReciept] 
AS
SELECT  
dbo.DeliveryDetails.DeliveryNo, 
dbo.DeliveryDetails.PONumber,  
c.Description as Category,
dbo.DeliveryDetails.ProductNo, 
dbo.DeliveryDetails.BarcodeNo,    
dbo.DeliveryDetails.ProductName,
'KG' as Units,
dbo.DeliveryDetails.QtyDelivered,
dbo.DeliveryDetails.Cost, 
FORMAT((QtyDelivered*Cost),'N2') AS TotalCost,
dbo.DeliveryDetails.SellingPrice, --b.SellingPrice as SellingPrice, 
dbo.DeliveryDetails.isVat,
dbo.DeliveryDetails.Status
FROM dbo.DeliveryDetails
INNER JOIN DeliverySummary d
	ON DeliveryDetails.PONumber=d.PONumber
	--AND DeliveryDetails.DeliveryNo=d.DeliveryNo 
INNER JOIN Products b
	ON dbo.DeliveryDetails.ProductNo=b.ProductCode
	AND b.BranchCode=d.BranchCode
INNER JOIN ProductCategory c
	ON b.ProductCategoryCode=c.ProductCategoryID
	AND b.BranchCode=d.BranchCode

WHERE dbo.DeliveryDetails.isReturned=0 
AND dbo.DeliveryDetails.isCancelled=0
