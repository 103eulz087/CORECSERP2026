
CREATE PROCEDURE [dbo].[sp_ConfirmOrder]
    @parmdevno VARCHAR(20),
    @parmpono VARCHAR(10),
    @preparedby VARCHAR(30),
	@parmzerorated bit,
    @parmmachinename VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Essential Variables Only
    DECLARE @custkey CHAR(8), @custname VARCHAR(100);
    DECLARE @effectivitydate DATE, @invoicenumber VARCHAR(10), @userid VARCHAR(20);
    DECLARE @paymenttype VARCHAR(30), @notes VARCHAR(500), @term INT;
    DECLARE @parmbranchcode CHAR(3);
    DECLARE @refno VARCHAR(10);

    BEGIN TRY
        BEGIN TRAN;

            -- 2. Bulk Status Updates
            UPDATE PurchaseOrderSummary SET @parmbranchcode=BranchCode,Status = 'DELIVERED' WHERE PONumber = @parmpono;
            UPDATE DeliverySummary SET Status = 'DELIVERED' WHERE PONumber = @parmpono;--DeliveryNo = @parmdevno;
            
            UPDATE dd
            SET dd.Status = 'DELIVERED',
                dd.Variance = dd.QtyDelivered - dd.ActualQty
            FROM DeliveryDetails dd
            WHERE dd.DeliveryNo = @parmdevno AND dd.PONumber = @parmpono;

            -- 3. Header Info Retrieval
            SELECT TOP 1 
                @effectivitydate = EffectivityDate, 
                @invoicenumber = InvoiceNo 
            FROM DeliverySummary WHERE PONumber = @parmpono;

            SELECT @userid = UserID FROM Users WHERE FullName = @preparedby;
            
            SELECT @custkey = Customer, @paymenttype = PaymentType, @notes = Notes 
            FROM PurchaseOrderSummary WHERE PONumber = @parmpono;

            -- 4. Set-Based Insert into BatchSalesDetails
            INSERT INTO BatchSalesDetails (
                BranchCode, ReferenceNo, CashierTransNo, ProductCode, CategoryCode, Barcode, 
                Description, Cost, OriginalSellingPrice, SellingPrice, QtySold, PrevQty, 
                UnitMeasure, DiscountRate, DiscountTotal, ChargeRate, ChargeTotal, TaxRate, 
                TaxTotal, SubTotal, Income, isHold, isConfirmed, isCancelled, isVoid, 
                isErrorCorrect, isVat, HoldBy, CancelledBy, VoidBy, ProcessedBy, 
                TotalAmount, Status, DateOrder, isUpload, isPosted, isCosting, MachineUsed
            )
            SELECT 
                @parmbranchcode, @parmpono, 99999, dd.ProductNo, p.ProductCategoryCode, dd.BarcodeNo,
                dd.ProductName, dd.Cost, dd.SellingPrice, dd.SellingPrice, dd.ActualQty, 0,
                'Kg', 0, 
                CASE WHEN dd.Variance > 0 AND dd.isCreditMemo = 1 THEN (dd.Variance * dd.SellingPrice) ELSE 0 END,
                0,
                CASE WHEN dd.Variance < 0 AND dd.isCreditMemo = 1 THEN ABS(dd.Variance * dd.SellingPrice) ELSE 0 END,
                CASE WHEN dd.isVat = 1 THEN 0.12 ELSE 0 END,
                CASE WHEN dd.isVat = 1 THEN ((dd.ActualQty * dd.SellingPrice) / 1.12) * 0.12 ELSE 0 END,
                CASE WHEN dd.isVat = 1 THEN (dd.ActualQty * dd.SellingPrice) / 1.12 ELSE (dd.ActualQty * dd.SellingPrice) END,
                0, 0, 1, 0, 0, 0, dd.isVat, '', '', '', @preparedby,
                (dd.ActualQty * dd.SellingPrice), 'SOLD', @effectivitydate, 0, 0, 0, ''
            FROM DeliveryDetails dd
            LEFT JOIN Products p ON dd.ProductNo = p.ProductCode AND p.BranchCode = @parmbranchcode
            WHERE dd.DeliveryNo = @parmdevno AND dd.PONumber = @parmpono AND dd.isReturned = 0;

            -- 5. BatchSalesSummary--select top(1) * FROM BatchSalesSummary
            INSERT INTO [dbo].[BatchSalesSummary] (
                [BranchCode], [ReferenceNo], [CashierTransNo], [CustomerNo], [Invoice], 
                [PaymentType], [Transdate], [PreparedBy], [MachineUsed], [Status], [isUpload], [isPosted] 
            )
            VALUES (
                @parmbranchcode, @parmpono, 99999, @custkey, @invoicenumber, 
                @paymenttype, @effectivitydate, @preparedby, @parmmachinename, 'SOLD', 1, 0 
            );

            UPDATE s
            SET s.TotalItem = d.Cnt,
                s.TotalItemSold = d.Cnt,
                s.TotalTax = d.Tax,
                s.TotalKilos = d.Qty,
                s.TotalAmount = d.Total,
                s.SubTotal = d.Sub,
                s.TotalVATSale = d.Tax,
                s.TotalVATExemptSale = d.Exempt,
                s.TotalVatableSale = d.VatSub,
				s.ZeroRatedSale = d.ZeroRated
            FROM BatchSalesSummary s
            CROSS APPLY (
                SELECT 
                    ISNULL(COUNT(*),0) as Cnt,
                    ISNULL(SUM(TaxTotal),0) as Tax,
                    ISNULL(SUM(QtySold),0) as Qty,
                    ISNULL(SUM(TotalAmount),0) as Total,
                    ISNULL(SUM(SubTotal),0) as Sub,
                    SUM(CASE WHEN isVat = 0 THEN TotalAmount ELSE 0 END) as Exempt,
                    SUM(CASE WHEN isVat = 1 THEN SubTotal ELSE 0 END) as VatSub,
					SUM(CASE WHEN isVat = 1 AND @parmzerorated = 1 THEN SubTotal/1.12 ELSE 0 END) as ZeroRated--SUM(case when @parmzerorated = 1 then TotalAmount/1.12 else 0 end) as ZeroRated
                FROM BatchSalesDetails 
                WHERE ReferenceNo = @parmpono AND BranchCode = @parmbranchcode
            ) d
            WHERE s.ReferenceNo = @parmpono AND s.BranchCode = @parmbranchcode;

            -- 6. TransactionChargeSalesDetails
            INSERT INTO TransactionChargeSalesDetails (
                SeqNo, BranchCode, ReferenceNo, InvoiceNo, TransactionDate, Product, 
                Quantity, Cost, SellingPrice, TotalAmount, SKU, TransCode, Type, ErrorTag
            )
            SELECT 
                ROW_NUMBER() OVER(ORDER BY ProductCode), @parmbranchcode, @parmpono, @invoicenumber, @effectivitydate,
                ProductCode, QtySold, Cost, SellingPrice, val.Amt, Barcode, val.TCode, val.TType, 0
            FROM BatchSalesDetails
            CROSS APPLY (
                SELECT SubTotal, 'DlvChg', 'SALES VAT' WHERE TaxTotal > 0
                UNION ALL
                SELECT TaxTotal, 'DlvChgV', 'VAT INPUT' WHERE TaxTotal > 0
                UNION ALL
                SELECT (QtySold * Cost), 'DCOGS', 'COST VAT' WHERE TaxTotal > 0
                UNION ALL
                SELECT TotalAmount, 'DlvChgVE', 'SALES VAT EXEMPT' WHERE TaxTotal <= 0
                UNION ALL
                SELECT (QtySold * Cost), 'DCOGSVE', 'COST VAT EXEMPT' WHERE TaxTotal <= 0
                UNION ALL
                SELECT DiscountTotal, 'SlsDisc', 'DISCOUNT' WHERE DiscountTotal > 0
            ) val(Amt, TCode, TType)
            WHERE ReferenceNo = @parmpono AND BranchCode = @parmbranchcode;

            -- 7. Final Accounting Entries
            EXEC GetReferenceNumber @refno OUTPUT;

            SELECT @term = ISNULL(Term, 0) FROM Customers WHERE CustomerKey = @custkey;

            INSERT INTO [dbo].[TransactionChargeSales] (
                CustomerKey, BranchCode, TransactionDate, ReferenceNo, InvoiceNo, 
                TotalAmount, PaymentType, Balance, PayStatus, DueDate, Remarks
            )
            SELECT 
                @custkey, @parmbranchcode, @effectivitydate, @parmpono, @invoicenumber,
                (TotalAmount - ISNULL(TotalDiscountAmount, 0)), @paymenttype, (TotalAmount - ISNULL(TotalDiscountAmount, 0)),
                'UNPAID', DATEADD(day, @term, @effectivitydate), @notes
            FROM BatchSalesSummary
            WHERE ReferenceNo = @parmpono AND BranchCode = @parmbranchcode;

            -- 8. Ledger Entry
            INSERT INTO ClientLedger (
                TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch, 
                Description, TransCode, TransactionDate, ReferenceNumber, ReferenceKey, 
                InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, ORNumber, 
                TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag
            )
            SELECT 
                ISNULL((SELECT MAX(TRN_SEQ_NO) FROM ClientLedger WHERE AccountID = @custkey), 0) + 1,
                @custkey, @custkey, @effectivitydate, @parmbranchcode,
                'CHARGE TO ACCOUNT (PO)', 'CHRG', GETDATE(), @refno, @parmpono,
                @invoicenumber, 0, TotalAmount, 0, 0, @invoicenumber,
                @preparedby, '*', 'remarks', TotalAmount, 0
            FROM BatchSalesSummary
            WHERE ReferenceNo = @parmpono AND BranchCode = @parmbranchcode;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        -- If an error occurs and a transaction is active, roll it back completely.
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRAN;
        END

        -- Capture the error details
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();

        -- Rethrow the exact error to the application/caller
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END