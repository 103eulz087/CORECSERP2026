-- =============================================
-- Author:		Eulz Avancena
-- Create date: 12/5/2017
-- Description:	Inventory Cost Adjustment
-- 12/05/2017 - set JOURNAL Type to GENERAL then rounding off into two decimal places in ticketdetails value.
-- 02/27/2018 - Adjust Entry into Supplier Ledger set Reversal Entry to Debit and New Adjustment to Credit.
-- 03/02/2018 - Update also the AmountPaid in ShipmentOrder table, before only the BALANCE Column will update during adjustment
-- =============================================
CREATE PROCEDURE [dbo].[sp_InvCostAdjustment]
	@parmbranchcode varchar(5),
	@parmshipmentno varchar(5),
	@parmprodcode varchar(10),
	@parmoldqty float,
	@parmoldcostkg float,
	@parmnewcostvalue decimal(18,6),
	@parmuser varchar(50),
	@parmsupplierid varchar(50)

AS

declare @suppkey varchar(15)
declare @invoiceno varchar(15)
BEGIN
	SET NOCOUNT ON
	declare @suppliername varchar(150),@proddesc varchar(100),@DeliveryDate date
	
	declare @actualqty float,@actualcost money,@isvat bit,@oldcostvalue money
	declare @debitacctcodevat varchar(20),@creditacctcodevat varchar(20),@transcodevatex varchar(30),@transcodevatinput varchar(30)
	declare @debitacctcodevatinput varchar(20),@creditacctcodevatinput varchar(20)
	declare @vatexadj money,@vatinputadj money
	declare @newvatexadj money,@newvatinputadj money
	declare @ticketnum int
	declare @transdescvatreversal varchar(150),@transdescvatinputreversal varchar(150)
	declare @debitacctcode varchar(20),@creditacctcode varchar(20),@debitacctcode1 varchar(20),@creditacctcode1 varchar(20)
	declare @transid decimal(7)

	 
	select @DeliveryDate=TargetDate FROM POSUMMARY WHERE ShipmentNo=@parmshipmentno
	select @proddesc=Description FROM Products WHERE ProductCode=@parmprodcode and BranchCode='888'
	
	select @suppkey=SupplierKey
	,@suppliername=SupplierName 
	FROM Supplier 
	WHERE SupplierID=@parmsupplierid 
	
	select @invoiceno=InvoiceNo FROM APACCOUNTS WHERE ShipmentNo=@parmshipmentno

	select @oldcostvalue=Cost
	,@actualqty=ActualQuantity
	,@actualcost=ActualCost
	,@isvat=isVat 
	FROM PODETAILS 
	WHERE ShipmentNo=@parmshipmentno 
	and OrderCode=@parmprodcode
	

	INSERT INTO InventoryAdjustment VALUES(@parmbranchcode,@parmshipmentno,@parmprodcode,@proddesc,@parmoldqty,@parmoldcostkg,0,@parmnewcostvalue,@parmoldqty,@parmnewcostvalue,@parmnewcostvalue*@parmoldqty,'',GETDATE(),@isvat,'COST ADJUSTMENT',1,0)
			
	
	declare @refno varchar(10)
	exec GetReferenceNumber @refno output
	if(@isvat=1)
	begin
		--VATABLE ENTRY
		SELECT @debitacctcode=DebitGLAccount,@creditacctcode=CreditGLAccount FROM TransactionDefinition WHERE TransCode='Inv' --AND BranchCode=@parmbranch
		SELECT @debitacctcode1=DebitGLAccount,@creditacctcode1=CreditGLAccount FROM TransactionDefinition WHERE TransCode='InvV' --AND BranchCode=@parmbranch
		---------------------
		select @transdescvatreversal=Description,@debitacctcodevat=DebitGLAccount,@creditacctcodevat=CreditGLAccount FROM TransactionDefinition WHERE TransCode = 'CstAdjTran'
		select @transdescvatinputreversal=Description,@debitacctcodevatinput=DebitGLAccount,@creditacctcodevatinput=CreditGLAccount FROM TransactionDefinition WHERE TransCode = 'CstAdjV'

		set @vatexadj = @actualcost / 1.12 --book to ticket reversal entry
		set @vatinputadj = @vatexadj * 0.12 --book to ticket reversal enry
		set @newvatexadj = (@actualqty * @parmnewcostvalue) / 1.12
		set @newvatinputadj = @newvatexadj * 0.12

		--if @parmnewcostvalue > @oldcostvalue
		--begin
		--	--credit to supplierledger
		--	--select * FROM supplierledger
		--			set @transid=dbo.func_getLastID(@parmsupplierid);
		--			INSERT INTO SupplierLedger 
		--			VALUES
		--			(
		--			@transid --trn_seq_no
		--			,@suppkey--SupplierKey
		--			,@parmsupplierid--SupplierID
		--			,GETDATE()--PostingDate
		--			,'Inv VatEx Credit Cost Adjustment Reversal '+@parmshipmentno--Description
		--			,'ADJ'--TransCode
		--			,GETDATE()--TransactionDate
		--			,@refno--ReferenceNumber
		--			,@parmshipmentno--ReferenceKey
		--			,@invoiceno -- InvoiceNo
		--			,0--BeginningBalance
		--			,@vatexadj--Debit
		--			,0--Credit
		--			,0--EndingBalance
		--			,@parmuser--TransactedBy
		--			,'*'--ApprovedBy
		--			,@vatexadj--TotalAmount
		--			,'PARTIAL'--PaymentType
		--			,0--ErrorCorrectTag
		--			,' ' --TicketNumber	
		--			) 

		--			set @transid=dbo.func_getLastID(@parmsupplierid);
		--			INSERT INTO SupplierLedger 
		--			VALUES
		--			(
		--			@transid --trn_seq_no
		--			,@suppkey--SupplierKey
		--			,@parmsupplierid--SupplierID
		--			,GETDATE()--PostingDate
		--			,'Inv VatInput Credit Cost Adjustment Reversal '+@parmshipmentno--Description
		--			,'ADJ'--TransCode
		--			,GETDATE()--TransactionDate
		--			,@refno--ReferenceNumber
		--			,@parmshipmentno--ReferenceKey
		--			,@invoiceno -- InvoiceNo
		--			,0--BeginningBalance
		--			,@vatinputadj--Debit
		--			,0--Credit
		--			,0--EndingBalance
		--			,@parmuser--TransactedBy
		--			,'*'--ApprovedBy
		--			,@vatinputadj--TotalAmount
		--			,'PARTIAL'--PaymentType
		--			,0--ErrorCorrectTag
		--			,' ' --TicketNumber	
		--			) 

		--	INSERT INTO SupplierLedger VALUES(@parmsupplierid,GETDATE(),'Inv VatEx Credit Cost Adjustment Reversal','ADJ',GETDATE(),'',0,@vatexadj,0,0,@parmuser,'*',@vatexadj,'UNPAID',0)
		--	INSERT INTO SupplierLedger VALUES(@parmsupplierid,GETDATE(),'Inv VatInput Credit Cost Adjustment Reversal','ADJ',GETDATE(),'',0,@vatinputadj,0,0,@parmuser,'*',@vatexadj,'UNPAID',0)
		--	INSERT INTO SupplierLedger VALUES(@parmsupplierid,GETDATE(),'Inv VatEx Credit Cost New Adjustment','ADJ',GETDATE(),'',0,0,@newvatexadj,0,@parmuser,'*',@newvatexadj,'UNPAID',0)
		--	INSERT INTO SupplierLedger VALUES(@parmsupplierid,GETDATE(),'Inv VatInput Credit Cost New Adjustment','ADJ',GETDATE(),'',0,0,@newvatinputadj,0,@parmuser,'*',@newvatinputadj,'UNPAID',0)
		--end
		--else
		--begin
		--	INSERT INTO SupplierLedger VALUES(@parmsupplierid,GETDATE(),'Inv VatEx Debit Cost Adjustment Reversal','ADJ',GETDATE(),'',0,@vatexadj,0,0,@parmuser,'*',@vatexadj,'UNPAID',0)
		--	INSERT INTO SupplierLedger VALUES(@parmsupplierid,GETDATE(),'Inv VatInput Debit Cost Adjustment Reversal','ADJ',GETDATE(),'',0,@vatinputadj,0,0,@parmuser,'*',@vatexadj,'UNPAID',0)
		--	INSERT INTO SupplierLedger VALUES(@parmsupplierid,GETDATE(),'Inv VatEx Debit Cost New Adjustment','ADJ',GETDATE(),'',0,0,@newvatexadj,0,@parmuser,'*',@newvatexadj,'UNPAID',0)
		--	INSERT INTO SupplierLedger VALUES(@parmsupplierid,GETDATE(),'Inv VatInput Debit Cost New Adjustment','ADJ',GETDATE(),'',0,0,@newvatinputadj,0,@parmuser,'*',@newvatinputadj,'UNPAID',0)
		--end
		--Update ShipmentOrder SET AmountPaid=case when AmountPaid <> 0 then AmountPaid-@actualcost else 0 end,Balance=case when Balance <> 0 then Balance-@actualcost else 0 end WHERE ShipmentNo=@parmshipmentno
		--Update ShipmentOrder SET AmountPaid=case when AmountPaid <> 0 then AmountPaid+(@actualqty * @parmnewcostvalue) else 0 end,Balance=case when Balance <> 0 then  Balance+(@actualqty * @parmnewcostvalue) else 0 end  WHERE ShipmentNo=@parmshipmentno
	 

		UPDATE APACCOUNTS
			SET AmountPaid=case when AmountPaid <> 0 then AmountPaid-@actualcost else 0 end
			,Balance=case when Balance <> 0 then Balance-@actualcost else 0 end 
		WHERE ShipmentNo=@parmshipmentno
		and SupplierID=@parmsupplierid

		
		UPDATE APACCOUNTS
			SET AmountPaid=case when AmountPaid <> 0 then AmountPaid+(@actualqty * @parmnewcostvalue) else 0 end
			,Balance=case when Balance <> 0 then  Balance+(@actualqty * @parmnewcostvalue) else 0 end  
		WHERE ShipmentNo=@parmshipmentno
		and SupplierID=@parmsupplierid

			--VAT EX ENTRY REVERSAL
		
		exec GetTicketNumber @ticketnum output
		INSERT INTO TicketMaster values(@DeliveryDate,'0',@parmbranchcode,@parmbranchcode,@ticketnum,@refno,@parmshipmentno,@suppliername,@transdescvatreversal+' with Shipment #:'+@parmshipmentno,@parmuser,'*','*','UPDATED','CstAdjTran','')
		insert INTO TicketDetails values(@DeliveryDate,'0',@parmbranchcode,@parmshipmentno,@ticketnum,@refno,@debitacctcodevat,ROUND(@vatexadj,2),0,'') --DEBIT
		insert INTO TicketDetails values(@DeliveryDate,'0',@parmbranchcode,@parmshipmentno,@ticketnum,@refno,@creditacctcodevat,0,ROUND(@vatexadj,2),'') --CREDIT
		--VAT INPUT ENTRY REVERSAL
		exec GetTicketNumber @ticketnum output
		INSERT INTO TicketMaster values(@DeliveryDate,'0',@parmbranchcode,@parmbranchcode,@ticketnum,@refno,@parmshipmentno,@suppliername,@transdescvatinputreversal+' with Shipment #:'+@parmshipmentno,@parmuser,'*','*','UPDATED','CstAdjV','')
		insert INTO TicketDetails values(@DeliveryDate,'0',@parmbranchcode,@parmshipmentno,@ticketnum,@refno,@debitacctcodevatinput,ROUND(@vatinputadj,2),0,'') --DEBIT
		insert INTO TicketDetails values(@DeliveryDate,'0',@parmbranchcode,@parmshipmentno,@ticketnum,@refno,@creditacctcodevatinput,0,ROUND(@vatinputadj,2),'') --CREDIT
	
		--VAT EX ENTRY NEW ADJUSTMENT
		exec GetTicketNumber @ticketnum output
		INSERT INTO TicketMaster values(@DeliveryDate,'0',@parmbranchcode,@parmbranchcode,@ticketnum,@refno,@parmshipmentno,@suppliername,@transdescvatreversal+' with Shipment #:'+@parmshipmentno,@parmuser,'*','*','UPDATED','CstAdjTran','')
		insert INTO TicketDetails values(@DeliveryDate,'0',@parmbranchcode,@parmshipmentno,@ticketnum,@refno,@debitacctcode,ROUND(@newvatexadj,2),0,'') --DEBIT
		insert INTO TicketDetails values(@DeliveryDate,'0',@parmbranchcode,@parmshipmentno,@ticketnum,@refno,@creditacctcode,0,ROUND(@newvatexadj,2),'') --CREDIT
		--VAT EX ENTRY NEW ADJUSTMENT OF VAT INPUT
		exec GetTicketNumber @ticketnum output
		INSERT INTO TicketMaster values(@DeliveryDate,'0',@parmbranchcode,@parmbranchcode,@ticketnum,@refno,@parmshipmentno,@suppliername,@transdescvatinputreversal+' with Shipment #:'+@parmshipmentno,@parmuser,'*','*','UPDATED','CstAdjV','')
		insert INTO TicketDetails values(@DeliveryDate,'0',@parmbranchcode,@parmshipmentno,@ticketnum,@refno,@debitacctcode1,ROUND(@newvatinputadj,2),0,'') --DEBIT
		insert INTO TicketDetails values(@DeliveryDate,'0',@parmbranchcode,@parmshipmentno,@ticketnum,@refno,@creditacctcode1,0,ROUND(@newvatinputadj,2),'') --CREDIT
	
	end
	else 
	begin
		
		SELECT @debitacctcode=DebitGLAccount,@creditacctcode=CreditGLAccount FROM TransactionDefinition WHERE TransCode='InvVE'
		---------------------
		set @vatexadj = @actualcost
		set @newvatexadj = @actualqty * @parmnewcostvalue

		--VAT EXEMPT EXNTRY
		--if @parmnewcostvalue > @oldcostvalue
		--begin
		--	--credit to supplierledger
		--	--select * FROM supplierledger
		--	INSERT INTO SupplierLedger VALUES(@parmsupplierid,GETDATE(),'Inv VatExempt Credit Cost Adjustment Reversal','ADJ',GETDATE(),'',0,@vatexadj,0,0,@parmuser,'*',@vatexadj,'UNPAID',0)
		--	INSERT INTO SupplierLedger VALUES(@parmsupplierid,GETDATE(),'Inv VatExempt Credit Cost New Adjustment','ADJ',GETDATE(),'',0,0,@newvatexadj,0,@parmuser,'*',@vatexadj,'UNPAID',0)
		--end
		--else
		--begin
		--	INSERT INTO SupplierLedger VALUES(@parmsupplierid,GETDATE(),'Inv VatExempt Credit Cost Adjustment Reversal','ADJ',GETDATE(),'',0,@vatexadj,0,0,@parmuser,'*',@vatexadj,'UNPAID',0)
		--	INSERT INTO SupplierLedger VALUES(@parmsupplierid,GETDATE(),'Inv VatExempt Debit Cost New Adjustment','ADJ',GETDATE(),'',0,0,@newvatexadj,0,@parmuser,'*',@newvatinputadj,'UNPAID',0)
		--end
		--Update ShipmentOrder SET AmountPaid=AmountPaid-@vatexadj,Balance=Balance-@vatexadj WHERE ShipmentNo=@parmshipmentno
		--Update ShipmentOrder SET AmountPaid=AmountPaid+@newvatexadj,Balance=Balance+@newvatexadj WHERE ShipmentNo=@parmshipmentno

		UPDATE APACCOUNTS 
			SET AmountPaid=case when AmountPaid <> 0 then AmountPaid-@vatexadj end
			,Balance=case when AmountPaid <> 0 then Balance-@vatexadj end
		WHERE ShipmentNo=@parmshipmentno

		UPDATE APACCOUNTS 
			SET AmountPaid=case when AmountPaid <> 0 then AmountPaid+@newvatexadj end
			,Balance= case when AmountPaid <> 0 then Balance+@newvatexadj end
		WHERE ShipmentNo=@parmshipmentno
		--INV EXEMPT ADJUSTMENT
		exec GetTicketNumber @ticketnum output
		INSERT INTO TicketMaster values(@DeliveryDate,'0',@parmbranchcode,@parmbranchcode,@ticketnum,@refno,@parmshipmentno,@suppliername,@transdescvatreversal+' with Shipment #:'+@parmshipmentno,@parmuser,'*','*','UPDATED','CstAdjTran','')
		insert INTO TicketDetails values(@DeliveryDate,'0',@parmbranchcode,@parmshipmentno,@ticketnum,@refno,@creditacctcode,ROUND(@vatexadj,2),0,'') --DEBIT
		insert INTO TicketDetails values(@DeliveryDate,'0',@parmbranchcode,@parmshipmentno,@ticketnum,@refno,@debitacctcode,0,ROUND(@vatexadj,2),'') --CREDIT
		--VAT EX ENTRY NEW ADJUSTMENT OF VAT INPUT
		exec GetTicketNumber @ticketnum output
		INSERT INTO TicketMaster values(@DeliveryDate,'0',@parmbranchcode,@parmbranchcode,@ticketnum,@refno,@parmshipmentno,@suppliername,@transdescvatinputreversal+' with Shipment #:'+@parmshipmentno,@parmuser,'*','*','UPDATED','CstAdjV','')
		insert INTO TicketDetails values(@DeliveryDate,'0',@parmbranchcode,@parmshipmentno,@ticketnum,@refno,@debitacctcode,ROUND(@newvatexadj,2),0,'') --DEBIT
		insert INTO TicketDetails values(@DeliveryDate,'0',@parmbranchcode,@parmshipmentno,@ticketnum,@refno,@creditacctcode,0,ROUND(@newvatexadj,2),'') --CREDIT
	
	end
	if(@isvat=1)
	begin
		UPDATE Inventory SET Cost=@parmnewcostvalue/1.12 WHERE ShipmentNo=@parmshipmentno and Product=@parmprodcode
	end
	else
	begin
		UPDATE Inventory SET Cost=@parmnewcostvalue WHERE ShipmentNo=@parmshipmentno and Product=@parmprodcode
	end
	
		UPDATE PODETAILS 
			SET ActualCost=@parmnewcostvalue
			,ActualTotalCost=@parmnewcostvalue*ActualQuantity
		WHERE ShipmentNo=@parmshipmentno 
		and OrderCode=@parmprodcode

		--UPDATE OrderDetails SET CostKg=@parmnewcostvalue,ActualCost=@parmnewcostvalue*ActualQty WHERE ShipmentNo=@parmshipmentno and ProductCode=@parmprodcode
		--declare @totalcost money
		--select @totalcost=SUM(ActualCost) FROM OrderDetails WHERE ShipmentNo=@parmshipmentno
		--UPDATE ShipmentOrder SET TotalCost=@totalcost,ActualCost=@totalcost WHERE ShipmentNo=@parmshipmentno  
		UPDATE POSUMMARY SET  
		TotalActualCost=(SELECT SUM(ActualTotalCost) FROM PODETAILS WHERE ShipmentNo=@parmshipmentno)
		--(SELECT SUM(Quantity*Cost) FROM Inventory WHERE ShipmentNo=@parmshipmentno and Product=@parmprodcode)
		WHERE ShipmentNo=@parmshipmentno

		UPDATE APACCOUNTS 
		SET ActualCost=(SELECT SUM(ActualTotalCost) FROM PODETAILS WHERE ShipmentNo=@parmshipmentno)
		--(SELECT SUM(Quantity*Cost) FROM Inventory WHERE ShipmentNo=@parmshipmentno and Product=@parmprodcode)
		,Balance=(SELECT SUM(ActualTotalCost) FROM PODETAILS WHERE ShipmentNo=@parmshipmentno)
		--(SELECT SUM(Quantity*Cost) FROM Inventory WHERE ShipmentNo=@parmshipmentno and Product=@parmprodcode)
		WHERE ShipmentNo=@parmshipmentno 
	
END
