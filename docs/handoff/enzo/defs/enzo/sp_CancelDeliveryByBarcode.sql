

CREATE PROCEDURE [dbo].[sp_CancelDeliveryByBarcode]
	@parmbranchcode char(3),
	@parmorigin char(3),
	@parmdevno varchar(20),
	@parmrefno varchar(10),
	@parmpono varchar(10),
	@parmbarcode varchar(50),
	@preparedby varchar(30)
AS
BEGIN
		declare @qty decimal(18,3),@qtyavailable decimal(18,3),@seqrefnum int,@prodno varchar(10),@prodname varchar(250),@cost money,@seqno int
		set nocount on
		
		SELECT TOP(1) 
		@prodno=Product
		,@prodname=Description
		,@qty=Quantity
		,@qtyavailable=Available
		FROM dbo.Inventory WHERE Barcode=@parmbarcode

		UPDATE DeliveryDetails set @seqno=SeqNo,isCancelled=1, DateTimeUpdated=GETDATE()
		WHERE BarcodeNo=@parmbarcode 
		and PONumber=@parmpono
		
		 UPDATE DeliverySummary
            SET TotalItem = (SELECT ISNULL(COUNT(*),0) FROM DeliveryDetails WHERE PONumber=@parmpono),
                TotalQtyDelivered = (SELECT ISNULL(SUM(QtyDelivered),0) FROM DeliveryDetails WHERE PONumber=@parmpono and isCancelled=0 and isReturned=0),
                TotalItemSold = (SELECT ISNULL(COUNT(*),0) FROM DeliveryDetails WHERE PONumber=@parmpono and isCancelled=0 and isReturned=0),
                TotalItemReturned = (SELECT ISNULL(COUNT(*),0) FROM DeliveryDetails WHERE PONumber=@parmpono and isReturned=1),
                Status = case when Status='FOR DELIVERY'
					then 'FOR DELIVERY'
					else 'PENDING'
					end
            WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono;


		UPDATE InventoryDeliveryFIFO Set @seqrefnum=SequenceReferenceNumber, isErrorCorrect=1
			WHERE DeliveryNo=@parmdevno 
				and PONumber=@parmpono
				--and SequenceReferenceNumber=@seqrefnum
				and DevDetSeqNo=@seqno
				and isErrorCorrect=0
		
		Update Inventory SET Available=Quantity WHERE Barcode=@parmbarcode AND SequenceNumber=@seqrefnum		

			INSERT INTO [dbo].[InventoryLedger]
           ([SequenceRefNum]
           ,[OriginBranch]
           ,[DestinationBranch]
           ,[DateProcessed]
           ,[Product]
           ,[Description]
           ,[BegQty]
           ,[QtyIN]
           ,[QtyOut]
           ,[EndQty]
           ,[Cost]
           ,[Remarks]
           ,[ProcessedBy])
		   SELECT 
			@seqrefnum			--[SequenceRefNum]
			,@parmorigin  --        ,[OriginBranch]
			,@parmbranchcode   --        ,[DestinationBranch]
			,GETDATE()  --        ,[DateProcessed]
			,@prodno   --        ,[Product]
			,@prodname   --        ,[Description]
			,@qtyavailable  --        ,[BegQty]
			,@qty   --        ,[QtyIN]
			,0   --        ,[QtyOut]
			,@qty+@qtyavailable   --        ,[EndQty]
			,@cost   --        ,[Cost]
			,'STS CANCEL LINEBYBARCODE'   --        ,[Remarks]
			,@preparedby   --        ,[ProcessedBy]
END

