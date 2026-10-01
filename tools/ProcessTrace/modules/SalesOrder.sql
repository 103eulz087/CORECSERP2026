/* ================================================================
   Process Trace: Sales Order (AddOrder → approval → AddBranchOrder →
   invoice no. → ConfirmOrderDevEx)
   READ-ONLY. The builder passes @Ids = comma-separated PONumbers.
   Every result set starts with _t = the table id used in SalesOrder.json.
   ================================================================ */
SET NOCOUNT ON;

DECLARE @PO TABLE (PONumber VARCHAR(20) PRIMARY KEY);
INSERT INTO @PO (PONumber)
SELECT DISTINCT LTRIM(RTRIM(value))
FROM STRING_SPLIT(@Ids, ',')
WHERE LTRIM(RTRIM(value)) <> '';

DECLARE @Inv TABLE (PONumber VARCHAR(20), InvoiceNo VARCHAR(50), CustomerKey CHAR(8));
INSERT INTO @Inv (PONumber, InvoiceNo, CustomerKey)
SELECT DISTINCT ds.PONumber, ds.InvoiceNo, ps.Customer
FROM dbo.DeliverySummary AS ds
INNER JOIN @PO AS p ON p.PONumber = ds.PONumber
INNER JOIN dbo.PurchaseOrderSummary AS ps ON ps.PONumber = ds.PONumber;

DECLARE @SalesTk TABLE (TicketNumber VARCHAR(30) PRIMARY KEY);
INSERT INTO @SalesTk
SELECT DISTINCT CAST(tm.TicketNumber AS VARCHAR(30))
FROM dbo.TicketMaster AS tm
INNER JOIN @Inv AS i ON i.PONumber = tm.ReferenceNumber AND i.InvoiceNo = tm.ReferenceKey
WHERE tm.Mnemonic LIKE 'SI-%';

------------------------------------------------------------------ step 1: order placed (AddOrder → sp_AddSalesOrderRequest)
SELECT 'pos' AS _t, ps.PONumber, ps.Customer, ps.BranchCode, ps.Qty, ps.OrderType, ps.PaymentType,
       ps.EffectivityDate, ps.Dateadded, ps.RequestedBy, ps.Notes
FROM dbo.PurchaseOrderSummary AS ps
INNER JOIN @PO AS p ON p.PONumber = ps.PONumber;

SELECT 'pod' AS _t, d.PONumber, d.SeqNo, d.ProductCode, d.ProductName, d.Qty, d.Units, d.SellingPrice, d.Remarks
FROM dbo.PurchaseOrderDetails AS d
INNER JOIN @PO AS p ON p.PONumber = d.PONumber
ORDER BY d.PONumber, d.SeqNo;

------------------------------------------------------------------ step 2: approved (POForApprovalDetails)
SELECT 'posAppr' AS _t, ps.PONumber, ps.Status, ps.ApprovedBy, ps.DateApproved, ps.Remarks, ps.isProcess
FROM dbo.PurchaseOrderSummary AS ps
INNER JOIN @PO AS p ON p.PONumber = ps.PONumber;

------------------------------------------------------------------ step 3: processed (AddBranchOrder → per scan + Save)
SELECT 'dd' AS _t, dd.DeliveryNo, dd.PONumber, dd.ReferenceNumber, dd.SeqNo, dd.ProductNo, dd.BarcodeNo, dd.ProductName,
       dd.QtyDelivered, dd.ActualQty, dd.Variance, dd.Cost, dd.SellingPrice, dd.isVat, dd.Status, dd.isCancelled,
       dd.ProcessedBy, dd.DateTimeAdded
FROM dbo.DeliveryDetails AS dd
INNER JOIN @PO AS p ON p.PONumber = dd.PONumber
ORDER BY dd.PONumber, dd.SeqNo;

SELECT 'fifo' AS _t, f.DeliveryNo, f.PONumber, f.DevDetSeqNo, f.ProductNo, f.SequenceReferenceNumber, f.QtyDelivered,
       f.Cost, f.TotalCost, f.DateProcessed, f.isErrorCorrect
FROM dbo.InventoryDeliveryFIFO AS f
INNER JOIN @PO AS p ON p.PONumber = f.PONumber
ORDER BY f.PONumber, f.DevDetSeqNo, f.SequenceReferenceNumber;

SELECT 'inv' AS _t, i.SequenceNumber, i.Branch, i.ShipmentNo, i.ReferenceCode, i.Product, i.Description,
       i.Quantity, i.Available, i.Cost, i.IsVat, i.IsWarehouse, i.DateReceived
FROM dbo.Inventory AS i
WHERE i.SequenceNumber IN (SELECT f.SequenceReferenceNumber FROM dbo.InventoryDeliveryFIFO AS f
                           INNER JOIN @PO AS p ON p.PONumber = f.PONumber)
ORDER BY i.Product, i.SequenceNumber;

SELECT 'il' AS _t, l.SequenceNumber, l.SequenceRefNum, l.OriginBranch, l.DestinationBranch, l.DateProcessed, l.Product,
       l.BegQty, l.QtyIN, l.QtyOut, l.EndQty, l.Cost, l.Remarks, l.ProcessedBy
FROM dbo.InventoryLedger AS l
INNER JOIN @PO AS p ON l.Remarks IN ('STS IN-TRANSIT PO#-' + p.PONumber, 'STS CANCEL ITEM PO#' + p.PONumber)
ORDER BY l.SequenceNumber;

SELECT 'hist' AS _t, h.UserID, h.DateExecute, h.ActionLogs, h.BranchCode
FROM dbo.HistoryLogs AS h
INNER JOIN @PO AS p ON h.ActionLogs = 'Commissary Process Order with PONumber=' + p.PONumber;

------------------------------------------------------------------ step 4: invoice number set (ViewForDeliveryDetails)
SELECT 'ds' AS _t, ds.DeliveryNo, ds.PONumber, ds.ReferenceNumber, ds.InvoiceNo, ds.isInvoiceUpdate, ds.BranchCode,
       ds.TotalItem, ds.TotalItemSold, ds.TotalQtyDelivered, ds.EffectivityDate, ds.Status, ds.PreparedBy, ds.DateAdded
FROM dbo.DeliverySummary AS ds
INNER JOIN @PO AS p ON p.PONumber = ds.PONumber;

------------------------------------------------------------------ step 5: confirmed (ConfirmOrderDevEx → sp_ConfirmOrder)
SELECT 'bsd' AS _t, b.BranchCode, b.ReferenceNo, b.CashierTransNo, b.ProductCode, b.Description, b.QtySold, b.Cost,
       b.SellingPrice, b.isVat, b.TaxTotal, b.SubTotal, b.DiscountTotal, b.TotalAmount, b.Status, b.DateOrder
FROM dbo.BatchSalesDetails AS b
INNER JOIN @PO AS p ON p.PONumber = b.ReferenceNo
INNER JOIN dbo.PurchaseOrderSummary AS ps ON ps.PONumber = p.PONumber AND ps.BranchCode = b.BranchCode
ORDER BY b.ReferenceNo, b.ProductCode;

SELECT 'bss' AS _t, s.BranchCode, s.ReferenceNo, s.CustomerNo, s.Invoice, s.TotalItem, s.TotalKilos, s.TotalVatableSale,
       s.TotalVATSale, s.TotalVATExemptSale, s.TotalAmount, s.PaymentType, s.Transdate, s.Status
FROM dbo.BatchSalesSummary AS s
INNER JOIN @PO AS p ON p.PONumber = s.ReferenceNo
INNER JOIN dbo.PurchaseOrderSummary AS ps ON ps.PONumber = p.PONumber AND ps.BranchCode = s.BranchCode;

SELECT 'tcs' AS _t, t.CustomerKey, t.BranchCode, t.TransactionDate, t.ReferenceNo, t.InvoiceNo, t.TotalAmount,
       t.PaymentType, t.Balance, t.AmountPaid, t.PayStatus, t.DueDate
FROM dbo.TransactionChargeSales AS t
INNER JOIN @Inv AS i ON i.PONumber = t.ReferenceNo AND i.InvoiceNo = t.InvoiceNo AND i.CustomerKey = t.CustomerKey;

SELECT 'tcsd' AS _t, d.SeqNo, d.BranchCode, d.ReferenceNo, d.InvoiceNo, d.Product, d.Quantity, d.Cost, d.SellingPrice,
       d.TotalAmount, d.TransCode, d.Type
FROM dbo.TransactionChargeSalesDetails AS d
INNER JOIN @Inv AS i ON i.PONumber = d.ReferenceNo AND i.InvoiceNo = d.InvoiceNo
ORDER BY d.ReferenceNo, d.SeqNo;

SELECT 'salesTm' AS _t, tm.TicketDate, tm.BranchCode, tm.TicketNumber, tm.ReferenceNumber, tm.ReferenceKey,
       tm.Owner, tm.Particulars, tm.Status, tm.Mnemonic, tm.EnteredBy
FROM dbo.TicketMaster AS tm
INNER JOIN @SalesTk AS k ON k.TicketNumber = CAST(tm.TicketNumber AS VARCHAR(30))
ORDER BY tm.TicketNumber;

SELECT 'salesTd' AS _t, td.TicketNumber, td.BranchCode, td.ReferenceNumber, td.ReferenceKey, td.AccountCode,
       coa.Description AS AccountName, td.Debit, td.Credit
FROM dbo.TicketDetails AS td
INNER JOIN @SalesTk AS k ON k.TicketNumber = CAST(td.TicketNumber AS VARCHAR(30))
LEFT JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = td.AccountCode
ORDER BY td.TicketNumber, td.Debit DESC;

SELECT 'salesCl' AS _t, cl.AccountKey, cl.TRN_SEQ_NO, cl.PostingDate, cl.TransCode, cl.ReferenceNumber, cl.InvoiceNo,
       cl.BeginningBalance, cl.Debit, cl.Credit, cl.EndingBalance, cl.TicketReference
FROM dbo.ClientLedger AS cl
INNER JOIN @Inv AS i ON i.CustomerKey = cl.AccountKey AND i.InvoiceNo = cl.InvoiceNo
WHERE cl.TransCode LIKE 'SI-%'
ORDER BY cl.TRN_SEQ_NO;
