

CREATE    PROCEDURE [dbo].[sp_ConfirmBranchOrder]
	@parmdevno varchar(20),
	@parmrefno varchar(10),
	@parmeffectivitydate date,
	@parmpono varchar(10),
	@parmbarcode varchar(20),
	@parmbranchcode varchar(10),
	@parmorigin varchar(10), --not used
	@preparedby varchar(30)
AS
	declare @devno varchar(20),@prodno varchar(20),@ponum varchar(20),@branchcode varchar(20),@qty float,@cost money,@totalcost money,@referencecode varchar(20)
	declare @refcodeseqnum int,@invqty float
	declare @_prodno varchar(20),@_pono varchar(20),@_totqty float,@_cost money,@_totcost money,@isvatable varchar(4)
	declare @machinename varchar(30)
	declare @devno2 varchar(20)
	,@prodno2 varchar(20)
	,@ponum2 varchar(20)
	,@branchcode2 varchar(20)
	,@qty2 float
	,@cost2 money
	,@totalcost2 money
	,@referencecode2 varchar(20)
	,@isvatable2 varchar(4);
	declare @totalqtybygroup float

	set @machinename=dbo.func_getMachineName()
 

BEGIN
SET XACT_ABORT ON
	SET NOCOUNT ON
	 
	
	  DECLARE @ProductCosting TABLE (
			ProductCode VARCHAR(10),
			Qty FLOAT,
			Cost MONEY,
			TotalCost MONEY
		);

		INSERT INTO @ProductCosting (ProductCode, Qty, Cost, TotalCost)
		SELECT 
			I.ProductNo,
			SUM(I.QtyDelivered) AS Qty,
			SUM(I.Cost) AS Cost,
			SUM(I.TotalCost) AS TotalCost
		FROM InventoryDeliveryFIFO I
		WHERE I.PONumber = @parmpono AND I.DeliveryNo = @parmdevno and I.isErrorCorrect=0
		GROUP BY I.ProductNo;

		--UPDATE dd
		--SET dd.Cost = ISNULL(pc.TotalCost / NULLIF(pc.Qty, 0), 0)
		--FROM DeliveryDetails dd
		--JOIN @ProductCosting pc ON dd.ProductNo = pc.ProductCode
		--WHERE dd.PONumber = @parmpono AND dd.DeliveryNo = @parmdevno;

		UPDATE dd
		SET dd.Cost =  isnull(i.Cost,0)
		FROM DeliveryDetails dd
		INNER JOIN InventoryDeliveryFIFO i
			ON dd.PONumber=i.PONumber
			and dd.SeqNo=i.DevDetSeqNo
			and dd.ProductNo=i.ProductNo
			and i.isErrorCorrect=0
		WHERE dd.PONumber = @parmpono 
		AND dd.DeliveryNo = @parmdevno;

		UPDATE DeliveryDetails set Status='FOR DELIVERY' 
		WHERE DeliveryNo=@parmdevno and PONumber=@parmpono

	
	declare @totalitem int,@totalqtydelivered float
	select @totalitem=count(*),@totalqtydelivered=SUM(QtyDelivered) FROM DeliveryDetails WHERE DeliveryNo=@parmdevno and PONumber=@parmpono
	--INSERT INTO DeliverySummary
	--SELECT @parmdevno,@parmpono,@parmrefno,@parmbranchcode,@totalitem,@totalqtydelivered,0,0,0,@parmeffectivitydate,'FOR DELIVERY',GETDATE(),@preparedby,0,@parmrefno,0
	
	SELECT top 1 DeliveryNo FROM DeliverySummary WHERE PONumber=@parmpono and DeliveryNo=@parmdevno
	if @@rowcount = 0
	begin
		--select * FROM DeliverySummary 
		INSERT INTO DeliverySummary --select top 1 * from deliverysummary
		SELECT 
		@parmdevno	--	[DeliveryNo]
		,@parmpono	--	           ,[PONumber]
		,@parmrefno	--	           ,[ReferenceNumber]
		,@parmrefno	--	           ,[InvoiceNo]
		,@parmbranchcode	--	           ,[BranchCode]
		,@totalitem	--	           ,[TotalItem]
		,@totalqtydelivered	--	           ,[TotalQtyDelivered]
		,0	--	           ,[TotalActualQty]
		,0	--	           ,[TotalVarianceVat]
		,0	--	           ,[TotalVarianceVatExempt]
		,@parmeffectivitydate	--	           ,[EffectivityDate]
		,'FOR DELIVERY'	--	           ,[Status]
		,GETDATE()	--	           ,[DateAdded]
		,@preparedby	--	           ,[PreparedBy]
		,0	--	           ,[isSettled]
		,0	--	           ,[isInvoiceUpdate]
		,0
		,@totalitem

	end
	else
	begin
		Update DeliverySummary set 
			TotalItem=@totalitem
			,TotalQtyDelivered=@totalqtydelivered
			,Status='FOR DELIVERY' 
		WHERE DeliveryNo=@parmdevno and PONumber=@parmpono
	end

	--declare @ticketbrcode varchar(5),@counter int

	--declare @creditglcode varchar(20),@debitglcode varchar(20),@creditglcodenonvat varchar(20),@debitglcodenonvat varchar(20)
	
	--SELECT @creditglcode=CreditGLAccount
	--		,@debitglcode=DebitGLAccount
	--		,@ticketbrcode=BranchCode 
	--FROM TransactionDefinition 
	--WHERE	TransCode='InvTrns' 
	--	and BranchCode=@parmbranchcode
	--	--and DebitGLAccount='1040302'
	
	--SELECT @creditglcodenonvat=CreditGLAccount,@debitglcodenonvat=DebitGLAccount,@ticketbrcode=BranchCode 
	--FROM TransactionDefinition 
	--WHERE TransCode='InvTrnsVE' 
	--and BranchCode=@parmbranchcode 
	--and DebitGLAccount='1040301'
	--select * FROM TransactionDefinition WHERE TransCode='InvTrns' and BranchCode=
	--select * FROM TransactionDefinition WHERE TransCode='InvTrnsVE' and BranchCode=001

	--declare @overalltotalcost money,@overalltotalcostwithvat money,@overalltotalcostnonvat money

	--SELECT @overalltotalcost=SUM(ISNULL(TotalCost,0)) FROM InventoryDeliveryFIFO
	--WHERE BranchCode=@parmbranchcode and PONumber=@parmpono and DeliveryNo=@parmdevno
	  
	--SELECT @overalltotalcostnonvat=SUM(ISNULL(TotalCost,0)) FROM InventoryDeliveryFIFO WHERE IsVat='0' AND 
	--BranchCode=@parmbranchcode and PONumber=@parmpono and DeliveryNo=@parmdevno

	--SELECT @overalltotalcostwithvat=SUM(ISNULL(TotalCost,0)) FROM InventoryDeliveryFIFO WHERE IsVat='1' AND
	--BranchCode=@parmbranchcode and PONumber=@parmpono and DeliveryNo=@parmdevno
	
	--declare @outrefnum varchar(10)
	--exec GetReferenceNumber @outrefnum output 
	--if exists (SELECT * FROM #TempOrder WHERE IsVat='1')
	--begin
	--	declare @ticketnum varchar(10)
	--	exec GetTicketNumber @ticketnum output --select * FROM aaplock
	--	INSERT INTO TicketMaster VALUES (CAST(GETDATE() as date),0,'888','888',@ticketnum,@outrefnum,@parmrefno,'COMISSARY IN TRANSIT','('+@parmbranchcode+')'+'-'+ @parmpono+' Inventory Transfer Vatable',@username,'*','*','UPDATED','InvTrns','')
	--	INSERT INTO TicketDetails VALUES(CAST(GETDATE() as date),0,'888',@parmrefno,@ticketnum,@outrefnum,@debitglcode,ROUND(@overalltotalcostwithvat,2),0,'')
	--	INSERT INTO TicketDetails VALUES(CAST(GETDATE() as date),0,'888',@parmrefno,@ticketnum,@outrefnum,@creditglcode,0,ROUND(@overalltotalcostwithvat,2),'')
	--end
	--if exists (SELECT * FROM #TempOrder WHERE IsVat='0')
	--begin 
	--	declare @ticketnum2 varchar(10)
	--	exec GetTicketNumber @ticketnum2 output
	--	INSERT INTO TicketMaster VALUES (CAST(GETDATE() as date),0,'888','888',@ticketnum2,@outrefnum,@parmrefno,'COMISSARY IN TRANSIT','('+@parmbranchcode+')'+'-'+ @parmpono+' Inventory Transfer VatExempt',@username,'*','*','UPDATED','InvTrnsVE','')
	--	INSERT INTO TicketDetails VALUES(CAST(GETDATE() as date),0,'888',@parmrefno,@ticketnum2,@outrefnum,@debitglcodenonvat,ROUND(@overalltotalcostnonvat,2),0,'')
	--	INSERT INTO TicketDetails VALUES(CAST(GETDATE() as date),0,'888',@parmrefno,@ticketnum2,@outrefnum,@creditglcodenonvat,0,ROUND(@overalltotalcostnonvat,2),'')
	--end

	----MUST BE TRANSFER TO sp_ConfirmOrder
	--------------------------------------------------------------------------------------------------------------------------------------------
	--------------------------------------------------------------------------------------------------------------------------------------------
	--declare @custid varchar(60)
	--declare @orderdate date,@invoicenumber varchar(10)
	--declare @cashiertransno int,@userid varchar(20),@transactiondate varchar(8),@custkey char(8)
	

	--select @orderdate=EffectivityDate
	--	,@invoicenumber=InvoiceNo 
	--FROM DeliverySummary 
	--WHERE PONumber=@parmpono
	
	--set @transactiondate=dbo.func_ConvertDateTimeToChar('DATE',GETDATE())
	
	--select @userid=UserID FROM Users WHERE FullName=@preparedby
	
	--select @cashiertransno=CashierTransNo 
	--FROM SalesTransactionSummary 
	--WHERE	BranchCode=@parmbranchcode 
	--	and MachineUsed=@machinename 
	--	and UserID=@userid 
	--	and TransactionDate=@transactiondate
		
	--select @custkey=Customer FROM PurchaseOrderSummary WHERE PONumber=@parmpono
	--select @custid=AccountID FROM ClientAccounts WHERE AccountKey=@custkey
	
	--insert into BatchSalesDetails (BranchCode,
	--ReferenceNo, --good as ponumber in h.o
	--CashierTransNo,
	----SequenceNumber, --auto increment
	--ProductCode,
	--Barcode,
	--Description,
	--Cost,
	--OriginalSellingPrice,
	--SellingPrice,
	--QtySold,
	--PrevQty,
	--UnitMeasure,
	--DiscountRate,
	--DiscountTotal,
	--ChargeRate,
	--ChargeTotal,
	--TaxRate,
	--TaxTotal,
	--SubTotal,
	--Income,
	--isHold,
	--isConfirmed,
	--isCancelled,
	--isVoid,
	--isErrorCorrect,
	--isVat,
	--HoldBy,
	--CancelledBy,
	--VoidBy,
	--ProcessedBy,
	--TotalAmount,
	--Status,
	--DateOrder,
	--isUpload,
	--isPosted,
	--isCosting,MachineUsed)
		
	--select --'10000', --TransactionCode
	--'888',
	--PONumber,--@delivsummaryrefno,--@lastor, --ReferenceNo
	--@cashiertransno,
	--ProductNo, --ProductCode
	--BarcodeNo, --Barcode
	--ProductName, --Description
	--Cost, --Cost
	--SellingPrice, --OriginalSellingPrice
	--SellingPrice, --SellingPrice
	--QtyDelivered, --QtySold
	--0, --PrevQty
	--'Kg', --UnitOfMeasure
	--0, --DiscountRate
	--0, --DiscountTotal
	--0, --ChargeRate
	--0, --ChargeTotal
	--0, --TaxRate
	--0, --TaxTotal
	--(QtyDelivered*SellingPrice), --SubTotal
	--0, --Income
	--0, --isHold
	--1, --isConfirmed
	--0, --isCancelled
	--0, --isVoid
	--0, --isErrorCorrect
	--isVat, --isVat
	--'', --HoldBy
	--'', --CancelledBy
	--'', --VoidBy
	--@preparedby, --ProcessedBy
	--(QtyDelivered*SellingPrice), --TotalAmount
	--'SOLD', --Status
	--@orderdate, --DateOrder
	--0, --isUpload
	--0, --isPosted
	--0, --isCosting
	--'' --MachineUsed
	--FROM DeliveryDetails 
	--WHERE DeliveryNo=@parmdevno 
	--and PONumber=@parmpono

	--UPDATE BatchSalesDetails SET SubTotal=(SubTotal/1.12),TaxRate=0.12,TaxTotal=(SubTotal/1.12*0.12),isVat=1 
	--WHERE (SUBSTRING(ProductCode,1,2)) in (Select ProductCategoryID from ProductCategory WHERE isVat=1) and ReferenceNo=@parmpono and BranchCode=@parmbranchcode and MachineUsed=@machinename

	--declare @paymenttype varchar(10)
	--select @paymenttype=PaymentType from PurchaseOrderSummary WHERE PONumber=@parmpono

	--INSERT INTO [dbo].[BatchSalesSummary]
 --          ([BranchCode]--
	--	   ,[ReferenceNo]
	--	   ,[CashierTransNo]
 --          ,[CustomerNo]
 --          ,[Invoice]
 --          ,[TotalItem]
 --          ,[TotalItemSold]
 --          ,[TotalItemCancelled]
 --          ,[TotalItemVoid]
 --          ,[TotalItemReturned]
 --          ,[TotalItemDiscount]
 --          ,[TotalVatableItems]
 --          ,[TotalSoldAmount]
 --          ,[TotalCancelledAmount]
 --          ,[TotalVoidAmount]
 --          ,[TotalReturnedAmount]
 --          ,[TotalDiscountAmount]
 --          ,[TotalCharge]
 --          ,[TotalUnitPrice]
 --          ,[TotalSellingPrice]
 --          ,[TotalTax]
 --          ,[TotalKilos]
 --          ,[SubTotal]
 --          ,[TotalAmount]
 --          ,[TotalIncome]
 --          ,[TotalVATSale]
 --          ,[TotalVATExemptSale]
 --          ,[TotalVatableSale]
 --          ,[PaymentType]
 --          ,[AdvancePayment]
 --          ,[AmountTendered]
 --          ,[AmountChange]
 --          ,[isFloat]
 --          ,[isHold]
 --          ,[isVoid]
 --          ,[isErrorCorrect]
 --          ,[OnHoldName]
 --          ,[VoidBy]
 --          ,[Transdate]
 --          ,[PreparedBy]
 --          ,[MachineUsed]
 --          ,[Posted]
 --          ,[Status]
 --          ,[isUpload]
 --          ,[isPosted]
 --          ,[DiscountType]
 --          ,[SeniorControlNo]
 --          ,[SeniorName]
 --          ,[SeniorDiscount]
 --          ,[PwdIDNo]
 --          ,[PwdName]
 --          ,[PwdDiscountAmount]
 --          ,[ZeroRatedSale])	
	--Select
	--	@parmbranchcode,
	--	@parmpono,		--[ReferenceNo]
	--	@cashiertransno,
	--	@custid,	 --          ,[CustomerNo]
	--	@invoicenumber,	 --          ,[Invoice]
	--	0,	 --          ,[TotalItem]
	--	0,	 --          ,[TotalItemSold]
	--	0,	 --          ,[TotalItemCancelled]
	--	0,	 --          ,[TotalItemVoid]
	--	0,	 --          ,[TotalItemReturned]
	--	0,	 --          ,[TotalItemDiscount]
	--	0,	 --          ,[TotalVatableItems]
	--	0,	 --          ,[TotalSoldAmount]
	--	0,	 --          ,[TotalCancelledAmount]
	--	0,	 --          ,[TotalVoidAmount]
	--	0,	 --          ,[TotalReturnedAmount]
	--	0,	 --          ,[TotalDiscountAmount]
	--	0,	 --          ,[TotalCharge]
	--	0,	 --          ,[TotalUnitPrice]
	--	0,	 --          ,[TotalSellingPrice]
	--	0,	 --          ,[TotalTax]
	--	0,	 --          ,[TotalKilos]
	--	0,	 --          ,[SubTotal]
	--	0,	 --          ,[TotalAmount]
	--	0,	 --          ,[TotalIncome]
	--	0,	 --          ,[TotalVATSale]
	--	0,	 --          ,[TotalVATExemptSale]
	--	0,	 --          ,[TotalVatableSale]
	--	@paymenttype,	 --          ,[PaymentType]
	--	0,	 --          ,[AdvancePayment]
	--	0,	 --          ,[AmountTendered]
	--	0,	 --          ,[AmountChange]
	--	0,	 --          ,[isFloat]
	--	0,	 --          ,[isHold]
	--	0,	 --          ,[isVoid]
	--	0,	 --          ,[isErrorCorrect]
	--	' ',	 --          ,[OnHoldName]
	--	' ',	 --          ,[VoidBy]
	--	@parmeffectivitydate,	 --          ,[Transdate]
	--	@preparedby,	 --          ,[PreparedBy]
	--	@machinename,	 --          ,[MachineUsed]
	--	'',	 --          ,[Posted]
	--	'SOLD',	 --          ,[Status]
	--	1,	 --          ,[isUpload]
	--	0,	 --          ,[isPosted]
	--	' ',	 --          ,[DiscountType]
	--	' ',	 --          ,[SeniorControlNo]
	--	' ',	 --          ,[SeniorName]
	--	0,	 --          ,[SeniorDiscount]
	--	' ',	 --          ,[PwdIDNo]
	--	' ',	 --          ,[PwdName]
	--	0,	 --          ,[PwdDiscountAmount]
	--	0	 --          ,[ZeroRatedSale]

	--UPDATE BatchSalesSummary set 
	--TotalItem = (select ISNULL(COUNT(SequenceNumber),0) FROM BatchSalesDetails WHERE ReferenceNo=@parmpono AND BranchCode=@parmbranchcode),
	--TotalItemSold = (select ISNULL(COUNT(SequenceNumber),0) FROM BatchSalesDetails WHERE ReferenceNo=@parmpono AND BranchCode=@parmbranchcode),	
	--TotalVatableItems = (select ISNULL(COUNT(SequenceNumber),0) FROM BatchSalesDetails WHERE ReferenceNo=@parmpono AND BranchCode=@parmbranchcode and isVat=1),
	--TotalTax = (select ISNULL(SUM(TaxTotal),0) FROM BatchSalesDetails WHERE ReferenceNo=@parmpono AND BranchCode=@parmbranchcode),
	--TotalKilos = (select ISNULL(SUM(QtySold),0) FROM BatchSalesDetails WHERE ReferenceNo=@parmpono AND BranchCode=@parmbranchcode),
	--SubTotal = (select ISNULL(SUM(SubTotal),0) FROM BatchSalesDetails WHERE ReferenceNo=@parmpono AND BranchCode=@parmbranchcode),
	--TotalAmount = (select ISNULL(SUM(TotalAmount),0) FROM BatchSalesDetails WHERE ReferenceNo=@parmpono AND BranchCode=@parmbranchcode),
	--TotalVATSale = (select ISNULL(SUM(TaxTotal),0) FROM BatchSalesDetails WHERE ReferenceNo=@parmpono AND BranchCode=@parmbranchcode),
	--TotalVATExemptSale = (select ISNULL(SUM(TotalAmount),0) FROM BatchSalesDetails WHERE ReferenceNo=@parmpono AND BranchCode=@parmbranchcode and isVat=0),
	--TotalVatableSale = (select ISNULL(SUM(SubTotal),0) FROM BatchSalesDetails WHERE ReferenceNo=@parmpono AND BranchCode=@parmbranchcode and isVat=1)
	-- WHERE ReferenceNo=@parmpono AND BranchCode=@parmbranchcode and MachineUsed=@machinename and CashierTransNo=@cashiertransno

	--declare @transno int,@parmtransno varchar(10)
	
	--select  @transno=isnull(MAX(CAST(TransactionNo as int))+1,1) 
	--from POSTransaction 
	--WHERE BranchCode=@parmbranchcode 
	--and MachineUsed=@machinename
	
	--select @parmtransno=dbo.func_SequencePadding6(@transno)
	--INSERT INTO POSTransaction 
	--	VALUES (  @parmbranchcode	--BranchCode
	--			 ,@parmtransno	--TransactionNo
	--			 ,@machinename	--MachineUsed
	--			 ,UPPER(@paymenttype)+' SALES'	--Type
	--			 ,GETDATE()	--DateAdded
	--			 ,@preparedby	--ExecuteBy
	--			 ,''	--ReprintCtr
	--			 ,''	--ReturnedCtr

	--			)
	--/*******************************************************************************************************************/
	--declare @totalamount decimal(12,2)
	
	--select @totalamount=ISNULL(SUM(TotalAmount),0) 
	--FROM BatchSalesDetails 
	--WHERE ReferenceNo=@parmpono 
	--AND BranchCode=@parmbranchcode
	
	--select * FROM INFORMATION_SCHEMA.Columns WHERE TABLE_NAME='CashiersBlotter'
	

	--INSERT INTO CashiersBlotter 
	--	VALUES (  
	--			  @parmbranchcode	--Branch
	--			 ,GETDATE()	--TransactionDate
	--			 ,@cashiertransno	--CashierTransNo
	--			 ,@parmtransno	--ReferenceNo
	--			 ,'CshSls'	--Transcode
	--			 ,@totalamount	--CashIn
	--			 ,''	--CashOut
	--			 ,@userid	--EnteredBy
	--			 ,0	--isUpload
	--				--SequenceNumber
	--			 ,@machinename	--MachineUsed
	--			)

	--------------------------------------------------------------------------------------------------------------------------------------------
	--------------------------------------------------------------------------------------------------------------------------------------------

	UPDATE PurchaseOrderSummary 
		SET isProcess='1' 
	WHERE PONumber=@parmpono
	
	insert into HistoryLogs values (@preparedby,GETDATE(),'Commissary Process Order with PONumber='+@parmpono,@parmbranchcode)
END

