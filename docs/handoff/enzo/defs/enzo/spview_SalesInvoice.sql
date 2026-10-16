CREATE    PROCEDURE [dbo].[spview_SalesInvoice]
	-- Add the parameters for the stored procedure here
	@parmpono varchar(10)
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT OFF;
	SELECT 
		SUM(a.QtyDelivered)AS Quantity
		,'Kg' as Unit
		--,a.ProductName+'(Less Discount)'
		,case when isnull(b.DiscountAmount,0) = 0 then a.ProductName when isnull(b.DiscountAmount,0) <> 0 then a.ProductName+' (Less Discount @'+CAST(b.Percentage as varchar(10))+'%)' else a.ProductName end as ProductName
		--,FORMAT(a.Cost, 'N', 'en-US')  AS Cost
		,FORMAT(a.SellingPrice, 'N', 'en-US')  AS Price
		--,FORMAT(b.DiscountAmount, 'N', 'en-US')  AS Discount
		,FORMAT(SUM(isnull(a.QtyDelivered,0) * isnull(a.SellingPrice,0))-isnull(b.DiscountAmount,0), 'N', 'en-US') AS Amount
		,a.isVat
	FROM view_DeliveryReciept a
	LEFT OUTER JOIN SalesOrderDiscounts b
	ON a.PONumber=b.PONumber
	and a.ProductNo=b.ProductCode
	--and a.SeqNo=b.SeqNo
	WHERE a.PONumber = @parmpono  
	GROUP BY a.ProductName,a.SellingPrice,a.isVat,b.DiscountAmount,b.Percentage

END
