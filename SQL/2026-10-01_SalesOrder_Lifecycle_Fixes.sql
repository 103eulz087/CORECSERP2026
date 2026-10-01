/* ================================================================
   2026-10-01: Sales Order lifecycle fixes (cancel / credit memo / return)
   ================================================================
   Found by rolled-back lifecycle tests on COREX001 (docs/CLAUDE_WORKLOG.md,
   Feature 14). User decisions (2026-10-01):
     * Credit memo = shrinkage: the missing qty is gone. Reduce the invoice;
       its cost goes to COS OTHERS (503 VAT-exempt / 504 VAT); no stock back.
     * Excess after a payment (credit memo / return larger than the unpaid
       balance) becomes customer credit: OVERPAY in the AR credit pool, 20115.
     * A return puts back the billed quantity (ActualQty), and credits it.

   Changes:
     A. JournalEntryMapping: new mnemonics SO-SHRINK-*, SO-CM-*, SO-RET-*
        (old CM-CLIENT-* rows untouched, still used by history only).
     B. NEW spu_SO_PostInvoiceReduction: one place that posts the credit-memo /
        return ticket(s), the client-ledger credit, the invoice update and the
        customer credit for any excess. DR = CR checked per ticket.
     C. sp_CancelDeliveryFIFOJFC: restore EVERY lot the line consumed (was one),
        one ledger row per lot, refuse when nothing is found (was: marked the
        line cancelled and wrote an empty ledger row), refuse confirmed lines.
     D. sp_ConfirmBranchOrder: line cost = weighted cost of all its lots
        (was the cost of one arbitrary lot). Nothing else changed.
     E. sp_CreditMemo:
          - before confirm: only the qty changes + shrinkage ticket
            (was a client-ledger credit with no invoice, then confirm billed
            the reduced qty as well = counted twice);
          - after confirm: through B (cost to COS OTHERS, excess to credit);
          - ActualQty must be between 0 and QtyDelivered;
          - confirmed/not confirmed is read from the data, not trusted from
            the form's tab.
     F. sp_ReturnSalesOrder:
          - credits only the lines returned now, at ActualQty x price (was the
            running total of every return on the PO, at QtyDelivered);
          - invoice balance recomputed with payments; excess to credit
            (was Balance = TotalAmount, PayStatus = UNPAID);
          - VAT-exempt returns reverse cost of sales too;
          - stock restored lot by lot (newest consumed first) with ledger rows;
          - lines matched by DeliveryNo + SeqNo, sales lines 1:1, sales header
            updated without the CashierTransNo filter that never matched;
          - values come from DeliveryDetails, not from the form's grid.
     Tickets are dated today (closed months stay closed) on the order's branch.

   Rename-then-create; backups end in _OLD_10012026150000.
   ================================================================ */

-- ----------------------------------------------------------------
-- A. Mapping rows
-- ----------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.JournalEntryMapping WHERE Mnemonic LIKE 'SO-SHRINK-%' OR Mnemonic LIKE 'SO-CM-%' OR Mnemonic LIKE 'SO-RET-%')
BEGIN
    INSERT INTO dbo.JournalEntryMapping
        (Origin, Mnemonic, Description, Seq, DebitCredit, AccountCode, AccountDescription,
         IsConditional, IsAmountFromSource, IsActive, Notes, AmountType, ConditionFlag, BranchCode)
    VALUES
    ('SO','SO-SHRINK-VAT',  'Sales order shrinkage before confirm (VAT)',        1,'D','504',      'COS OTHERS - VAT',                  0,1,1,'Credit memo before confirm: cost of the missing qty', 'COST',  NULL, NULL),
    ('SO','SO-SHRINK-VAT',  'Sales order shrinkage before confirm (VAT)',        2,'C','101040202','INVENTORY - VAT',                   0,1,1,NULL, 'COST',  NULL, NULL),
    ('SO','SO-SHRINK-VATEX','Sales order shrinkage before confirm (VAT exempt)', 1,'D','503',      'COS OTHERS - VAT EXEMPT',           0,1,1,'Credit memo before confirm: cost of the missing qty', 'COST',  NULL, NULL),
    ('SO','SO-SHRINK-VATEX','Sales order shrinkage before confirm (VAT exempt)', 2,'C','101040201','INVENTORY - VAT EXEMPT',            0,1,1,NULL, 'COST',  NULL, NULL),

    ('SO','SO-CM-VAT',      'Sales order credit memo after confirm (VAT)',       1,'D','402',      'Sales - VAT',                       0,1,1,NULL, 'NET',   NULL, NULL),
    ('SO','SO-CM-VAT',      'Sales order credit memo after confirm (VAT)',       2,'D','20112',    'Output Tax Payable (reversal)',     0,1,1,NULL, 'VAT',   NULL, NULL),
    ('SO','SO-CM-VAT',      'Sales order credit memo after confirm (VAT)',       3,'C','101030101','Accounts Receivable - Trade',       0,1,1,NULL, 'ARPART',NULL, NULL),
    ('SO','SO-CM-VAT',      'Sales order credit memo after confirm (VAT)',       4,'C','20115',    'CUSTOMER ADVANCES / OVERPAYMENTS',  0,1,1,'Only when the invoice was already paid past the new total', 'EXCESS', NULL, NULL),
    ('SO','SO-CM-VAT',      'Sales order credit memo after confirm (VAT)',       5,'D','504',      'COS OTHERS - VAT',                  0,1,1,'Shrinkage: cost moved out of normal COS', 'COST', NULL, NULL),
    ('SO','SO-CM-VAT',      'Sales order credit memo after confirm (VAT)',       6,'C','502',      'COS - VAT',                         0,1,1,NULL, 'COST',  NULL, NULL),

    ('SO','SO-CM-VATEX',    'Sales order credit memo after confirm (VAT exempt)',1,'D','401',      'Sales - VAT Exempt',                0,1,1,NULL, 'GROSS', NULL, NULL),
    ('SO','SO-CM-VATEX',    'Sales order credit memo after confirm (VAT exempt)',2,'C','101030101','Accounts Receivable - Trade',       0,1,1,NULL, 'ARPART',NULL, NULL),
    ('SO','SO-CM-VATEX',    'Sales order credit memo after confirm (VAT exempt)',3,'C','20115',    'CUSTOMER ADVANCES / OVERPAYMENTS',  0,1,1,'Only when the invoice was already paid past the new total', 'EXCESS', NULL, NULL),
    ('SO','SO-CM-VATEX',    'Sales order credit memo after confirm (VAT exempt)',4,'D','503',      'COS OTHERS - VAT EXEMPT',           0,1,1,'Shrinkage: cost moved out of normal COS', 'COST', NULL, NULL),
    ('SO','SO-CM-VATEX',    'Sales order credit memo after confirm (VAT exempt)',5,'C','501',      'COS - VAT Exempt',                  0,1,1,NULL, 'COST',  NULL, NULL),

    ('SO','SO-RET-VAT',     'Sales order return after confirm (VAT)',            1,'D','402',      'Sales - VAT',                       0,1,1,NULL, 'NET',   NULL, NULL),
    ('SO','SO-RET-VAT',     'Sales order return after confirm (VAT)',            2,'D','20112',    'Output Tax Payable (reversal)',     0,1,1,NULL, 'VAT',   NULL, NULL),
    ('SO','SO-RET-VAT',     'Sales order return after confirm (VAT)',            3,'C','101030101','Accounts Receivable - Trade',       0,1,1,NULL, 'ARPART',NULL, NULL),
    ('SO','SO-RET-VAT',     'Sales order return after confirm (VAT)',            4,'C','20115',    'CUSTOMER ADVANCES / OVERPAYMENTS',  0,1,1,'Only when the invoice was already paid past the new total', 'EXCESS', NULL, NULL),
    ('SO','SO-RET-VAT',     'Sales order return after confirm (VAT)',            5,'D','101040202','INVENTORY - VAT (restored)',        0,1,1,NULL, 'COST',  NULL, NULL),
    ('SO','SO-RET-VAT',     'Sales order return after confirm (VAT)',            6,'C','502',      'COS - VAT',                         0,1,1,NULL, 'COST',  NULL, NULL),

    ('SO','SO-RET-VATEX',   'Sales order return after confirm (VAT exempt)',     1,'D','401',      'Sales - VAT Exempt',                0,1,1,NULL, 'GROSS', NULL, NULL),
    ('SO','SO-RET-VATEX',   'Sales order return after confirm (VAT exempt)',     2,'C','101030101','Accounts Receivable - Trade',       0,1,1,NULL, 'ARPART',NULL, NULL),
    ('SO','SO-RET-VATEX',   'Sales order return after confirm (VAT exempt)',     3,'C','20115',    'CUSTOMER ADVANCES / OVERPAYMENTS',  0,1,1,'Only when the invoice was already paid past the new total', 'EXCESS', NULL, NULL),
    ('SO','SO-RET-VATEX',   'Sales order return after confirm (VAT exempt)',     4,'D','101040201','INVENTORY - VAT EXEMPT (restored)', 0,1,1,NULL, 'COST',  NULL, NULL),
    ('SO','SO-RET-VATEX',   'Sales order return after confirm (VAT exempt)',     5,'C','501',      'COS - VAT Exempt',                  0,1,1,NULL, 'COST',  NULL, NULL);
END
GO

-- ----------------------------------------------------------------
-- B. Shared posting step for credit memo / return after confirm
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.spu_SO_PostInvoiceReduction', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_SO_PostInvoiceReduction', 'spu_SO_PostInvoiceReduction_OLD_10012026150000';
GO
CREATE PROCEDURE dbo.spu_SO_PostInvoiceReduction
    @Kind         VARCHAR(5),        -- 'CM' (credit memo) | 'RET' (return)
    @PONumber     VARCHAR(20),
    @InvoiceNo    VARCHAR(50),
    @CustomerKey  CHAR(8),
    @BranchCode   VARCHAR(5),
    @User         VARCHAR(50),
    @NetVat       DECIMAL(18,2),     -- VAT lines: SUM of per-line ROUND(gross / 1.12, 2), as sp_ConfirmOrder does
    @TaxVat       DECIMAL(18,2),     -- VAT lines: SUM of per-line ROUND(gross / 1.12 * 0.12, 2); gross = Net + Tax
    @CostVat      DECIMAL(18,2),
    @GrossVatEx   DECIMAL(18,2),
    @CostVatEx    DECIMAL(18,2),
    @Particulars  VARCHAR(6999),
    @TicketVat    VARCHAR(20)   OUTPUT,
    @TicketVatEx  VARCHAR(20)   OUTPUT,
    @Excess       DECIMAL(18,2) OUTPUT
AS
/*
    Must run inside the caller's transaction. Posts SO-<Kind>-VAT / -VATEX
    through sp_PostCompoundTicketSales, then the client-ledger credit, the
    invoice update and, when the invoice was already paid past its new total,
    the excess as customer credit (PaymentHeader + ARPaymentDetails OVERPAY,
    the pool sp_GetCustomerAvailableCredit reads; GL 20115 via the EXCESS leg).
    Callers: sp_CreditMemo, sp_ReturnSalesOrder.
*/
BEGIN
    SET NOCOUNT ON;
    IF @@TRANCOUNT = 0
        THROW 59401, 'spu_SO_PostInvoiceReduction must run inside a transaction.', 1;
    IF @Kind NOT IN ('CM', 'RET')
        THROW 59402, 'Kind must be CM or RET.', 1;

    SET @NetVat = ISNULL(@NetVat, 0); SET @TaxVat = ISNULL(@TaxVat, 0); SET @CostVat = ISNULL(@CostVat, 0);
    DECLARE @GrossVat DECIMAL(18,2) = @NetVat + @TaxVat;
    SET @GrossVatEx = ISNULL(@GrossVatEx, 0); SET @CostVatEx = ISNULL(@CostVatEx, 0);
    SET @TicketVat = ' '; SET @TicketVatEx = ' '; SET @Excess = 0;

    DECLARE @Total DECIMAL(18,2) = @GrossVat + @GrossVatEx;
    IF @Total <= 0 RETURN;

    -- lock the invoice and re-read its balance (never trust the caller's view of it)
    DECLARE @Bal DECIMAL(18,2), @Paid DECIMAL(18,2), @Found BIT = 0;
    SELECT @Bal = ISNULL(Balance, 0), @Paid = ISNULL(AmountPaid, 0), @Found = 1
    FROM dbo.TransactionChargeSales WITH (UPDLOCK, HOLDLOCK)
    WHERE CustomerKey = @CustomerKey AND ReferenceNo = @PONumber AND InvoiceNo = @InvoiceNo;
    IF @Found = 0
        THROW 59403, 'The AR invoice for this PO was not found (TransactionChargeSales).', 1;

    SET @Excess = @Total - CASE WHEN @Bal >= @Total THEN @Total WHEN @Bal > 0 THEN @Bal ELSE 0 END;
    IF @Excess > @Paid
        THROW 59404, 'This amount is more than the unpaid balance plus the cash paid on the invoice (part of it was settled by EWT / discount / offset). Reverse that part of the payment first.', 1;

    DECLARE @ExVat DECIMAL(18,2) = CASE WHEN @Excess > @GrossVat THEN @GrossVat ELSE @Excess END;
    DECLARE @ExVatEx DECIMAL(18,2) = @Excess - @ExVat;
    DECLARE @Today DATE = CAST(GETDATE() AS DATE);
    DECLARE @MnVat VARCHAR(50) = 'SO-' + @Kind + '-VAT', @MnVatEx VARCHAR(50) = 'SO-' + @Kind + '-VATEX';
    DECLARE @CustName VARCHAR(150) = (SELECT CustomerName FROM dbo.Customers WHERE CustomerKey = @CustomerKey);

    DECLARE @Amt dbo.tt_AmountBreakdown, @Tok dbo.tt_TokenResolution, @Flg dbo.tt_ConditionFlags;

    IF @GrossVat <> 0 OR @CostVat <> 0
    BEGIN
        INSERT @Amt VALUES ('GROSS', @GrossVat), ('NET', @NetVat), ('VAT', @TaxVat),
                           ('ARPART', @GrossVat - @ExVat), ('EXCESS', @ExVat), ('COST', @CostVat);
        EXEC dbo.sp_PostCompoundTicketSales
            @Mnemonic = @MnVat, @TicketDate = @Today, @BranchCode = @BranchCode,
            @ReferenceNumber = @PONumber, @ReferenceKey = @InvoiceNo,
            @Particulars = @Particulars, @Owner = @CustName, @PreparedBy = @User,
            @Status = 'POSTED', @Amounts = @Amt, @Tokens = @Tok, @Flags = @Flg, @LedgerType = NULL;
        SELECT TOP 1 @TicketVat = CAST(TicketNumber AS VARCHAR(20)) FROM dbo.TicketMaster
        WHERE ReferenceNumber = @PONumber AND ReferenceKey = @InvoiceNo AND Mnemonic = @MnVat
        ORDER BY TRY_CAST(TicketNumber AS BIGINT) DESC;
        DELETE FROM @Amt;
    END

    IF @GrossVatEx <> 0 OR @CostVatEx <> 0
    BEGIN
        INSERT @Amt VALUES ('GROSS', @GrossVatEx), ('NET', @GrossVatEx), ('VAT', 0),
                           ('ARPART', @GrossVatEx - @ExVatEx), ('EXCESS', @ExVatEx), ('COST', @CostVatEx);
        EXEC dbo.sp_PostCompoundTicketSales
            @Mnemonic = @MnVatEx, @TicketDate = @Today, @BranchCode = @BranchCode,
            @ReferenceNumber = @PONumber, @ReferenceKey = @InvoiceNo,
            @Particulars = @Particulars, @Owner = @CustName, @PreparedBy = @User,
            @Status = 'POSTED', @Amounts = @Amt, @Tokens = @Tok, @Flags = @Flg, @LedgerType = NULL;
        SELECT TOP 1 @TicketVatEx = CAST(TicketNumber AS VARCHAR(20)) FROM dbo.TicketMaster
        WHERE ReferenceNumber = @PONumber AND ReferenceKey = @InvoiceNo AND Mnemonic = @MnVatEx
        ORDER BY TRY_CAST(TicketNumber AS BIGINT) DESC;
    END

    -- every ticket posted here must balance
    IF EXISTS (SELECT 1 FROM dbo.TicketDetails
               WHERE CAST(TicketNumber AS VARCHAR(20)) IN (@TicketVat, @TicketVatEx)
               GROUP BY TicketNumber
               HAVING ABS(SUM(ISNULL(Debit, 0)) - SUM(ISNULL(Credit, 0))) > 0.005)
        THROW 59405, 'Credit memo / return ticket does not balance (DR <> CR). Check the SO-CM / SO-RET mapping rows.', 1;

    -- client ledger: credit only the part that reduces AR (the excess goes to 20115, not AR)
    DECLARE @Seq DECIMAL(7,0);
    IF @GrossVat - @ExVat > 0
    BEGIN
        SELECT @Seq = ISNULL(MAX(TRN_SEQ_NO), 0) + 1 FROM dbo.ClientLedger WHERE AccountKey = @CustomerKey;
        INSERT INTO dbo.ClientLedger
            (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch, Description, TransCode,
             TransactionDate, ReferenceNumber, ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit,
             EndingBalance, ORNumber, TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
        VALUES
            (@Seq, @CustomerKey, @CustomerKey, @Today, @BranchCode, LEFT(@Particulars, 150), @MnVat,
             @Today, @PONumber, @InvoiceNo, @InvoiceNo, 0, 0, @GrossVat - @ExVat,
             0, @InvoiceNo, @User, '*', CASE @Kind WHEN 'CM' THEN 'Credit Memo' ELSE 'Sales Return' END,
             @GrossVat - @ExVat, 0, @TicketVat);
    END
    IF @GrossVatEx - @ExVatEx > 0
    BEGIN
        SELECT @Seq = ISNULL(MAX(TRN_SEQ_NO), 0) + 1 FROM dbo.ClientLedger WHERE AccountKey = @CustomerKey;
        INSERT INTO dbo.ClientLedger
            (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch, Description, TransCode,
             TransactionDate, ReferenceNumber, ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit,
             EndingBalance, ORNumber, TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
        VALUES
            (@Seq, @CustomerKey, @CustomerKey, @Today, @BranchCode, LEFT(@Particulars, 150), @MnVatEx,
             @Today, @PONumber, @InvoiceNo, @InvoiceNo, 0, 0, @GrossVatEx - @ExVatEx,
             0, @InvoiceNo, @User, '*', CASE @Kind WHEN 'CM' THEN 'Credit Memo' ELSE 'Sales Return' END,
             @GrossVatEx - @ExVatEx, 0, @TicketVatEx);
    END

    -- invoice: CM raises DiscountAmount, RET lowers TotalAmount; the excess moves from
    -- AmountPaid to AdvancePayment so Balance stays TotalAmount - (Paid + EWT + Discount + Offset)
    UPDATE dbo.TransactionChargeSales
    SET DiscountAmount = ISNULL(DiscountAmount, 0) + CASE WHEN @Kind = 'CM'  THEN @Total ELSE 0 END,
        TotalAmount    = TotalAmount              - CASE WHEN @Kind = 'RET' THEN @Total ELSE 0 END,
        AmountPaid     = ISNULL(AmountPaid, 0) - @Excess,
        AdvancePayment = ISNULL(AdvancePayment, 0) + @Excess
    WHERE CustomerKey = @CustomerKey AND ReferenceNo = @PONumber AND InvoiceNo = @InvoiceNo;

    UPDATE dbo.TransactionChargeSales
    SET Balance = TotalAmount - (ISNULL(AmountPaid, 0) + ISNULL(EWTAmount, 0) + ISNULL(DiscountAmount, 0) + ISNULL(OffsetAmount, 0))
    WHERE CustomerKey = @CustomerKey AND ReferenceNo = @PONumber AND InvoiceNo = @InvoiceNo;

    UPDATE dbo.TransactionChargeSales
    SET PayStatus = CASE WHEN TotalAmount <= 0 THEN 'RETURNED'
                         WHEN Balance <= 0 THEN 'FULLYPAID'
                         WHEN ISNULL(AmountPaid, 0) > 0 OR ISNULL(EWTAmount, 0) > 0 OR ISNULL(DiscountAmount, 0) > 0 THEN 'PARTIAL'
                         ELSE 'UNPAID' END
    WHERE CustomerKey = @CustomerKey AND ReferenceNo = @PONumber AND InvoiceNo = @InvoiceNo;

    -- the excess becomes usable customer credit (OVERPAY in the AR credit pool):
    -- one header, one OVERPAY row per ticket that carried part of it
    IF @Excess > 0
    BEGIN
        DECLARE @CreditRef VARCHAR(10);
        EXEC dbo.GetReferenceNumber @CreditRef OUTPUT;   -- same counter as a normal client payment
        DECLARE @Ph TABLE (PaymentHeaderID INT);
        INSERT INTO dbo.PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy, Status)
        OUTPUT INSERTED.PaymentHeaderID INTO @Ph
        VALUES (@CustomerKey, @CreditRef, '', '', CASE @Kind WHEN 'CM' THEN 'CM-CREDIT' ELSE 'RETURN-CREDIT' END,
                @Excess, @Today,
                CASE @Kind WHEN 'CM' THEN 'Credit memo' ELSE 'Sales return' END + ' larger than the unpaid balance of invoice ' + @InvoiceNo + ' (PO ' + @PONumber + ')',
                @User, 'POSTED');
        INSERT INTO dbo.ARPaymentDetails
            (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount,
             PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
        SELECT ph.PaymentHeaderID, @CustomerKey, @CreditRef, @PONumber, @InvoiceNo, @Today, x.Amount,
               'OVERPAY', CASE @Kind WHEN 'CM' THEN 'CREDITMEMO' ELSE 'RETURN' END, NULL,
               (SELECT TOP 1 m.AccountCode FROM dbo.JournalEntryMapping m
                WHERE m.Mnemonic = x.Mnemonic AND m.AmountType = 'EXCESS' AND m.IsActive = 1),
               x.Ticket
        FROM @Ph AS ph
        CROSS JOIN (VALUES (@ExVat, @MnVat, @TicketVat), (@ExVatEx, @MnVatEx, @TicketVatEx)) AS x (Amount, Mnemonic, Ticket)
        WHERE x.Amount > 0;
    END
END
GO

-- ----------------------------------------------------------------
-- C. Cancel a scanned line: restore every lot
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_CancelDeliveryFIFOJFC', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_CancelDeliveryFIFOJFC', 'sp_CancelDeliveryFIFOJFC_OLD_10012026150000';
GO
CREATE PROCEDURE dbo.sp_CancelDeliveryFIFOJFC
    @parmdevno varchar(20),
    @parmrefno varchar(10),
    @parmpono varchar(10),
    @parmprodno varchar(20),
    @parmqty decimal(18,3),
    @parmbranchcode varchar(10),
    @parmorigin varchar(10),
    @preparedby varchar(30),
    @parmdevseqno int
AS
/*
    Cancels one delivery line before confirm and puts back EVERY lot its scan
    consumed (InventoryDeliveryFIFO rows of DeliveryNo + PONumber + line),
    one InventoryLedger row per lot. Refuses when no active lot rows are found
    (the old version marked the line cancelled and restored nothing) and when
    the line is already DELIVERED (use Return instead).
    Callers: Orders/AddBranchOrder.cs (sales order), sp_ReverseSTSInventoryTransfer (STS).
    Same parameters as before.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @TranCounter INT = @@TRANCOUNT;
    IF @TranCounter > 0 SAVE TRANSACTION CancelDeliverySave; ELSE BEGIN TRANSACTION;
    BEGIN TRY
        IF EXISTS (SELECT 1 FROM dbo.DeliveryDetails
                   WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono AND SeqNo = @parmdevseqno AND Status = 'DELIVERED')
            THROW 59421, 'This line is already confirmed (DELIVERED). Use Return instead of Cancel.', 1;

        DECLARE @Lots TABLE (FifoSeq BIGINT PRIMARY KEY, Lot BIGINT, Qty DECIMAL(18,3), Cost DECIMAL(18,4), Descr VARCHAR(400));
        INSERT INTO @Lots (FifoSeq, Lot, Qty, Cost, Descr)
        SELECT f.SequenceNumber, f.SequenceReferenceNumber, ISNULL(f.QtyDelivered, 0), ISNULL(f.Cost, 0), f.Description
        FROM dbo.InventoryDeliveryFIFO AS f WITH (UPDLOCK, ROWLOCK)
        WHERE f.DeliveryNo = @parmdevno
          AND f.PONumber = @parmpono
          AND f.BranchCode = @parmbranchcode
          AND f.ProductNo = @parmprodno
          AND f.DevDetSeqNo = @parmdevseqno
          AND f.isErrorCorrect = 0;

        IF NOT EXISTS (SELECT 1 FROM @Lots)
        BEGIN
            DECLARE @NoLotMsg NVARCHAR(400) = N'Nothing to restore for PO ' + @parmpono + N' line ' + CAST(@parmdevseqno AS NVARCHAR(10))
                + N' (delivery ' + @parmdevno + N', branch ' + @parmbranchcode + N', product ' + @parmprodno
                + N'): no active FIFO rows. The line was not cancelled. Check the branch passed in.';
            THROW 59422, @NoLotMsg, 1;
        END

        IF EXISTS (SELECT 1 FROM @Lots l WHERE NOT EXISTS (SELECT 1 FROM dbo.Inventory i WHERE i.SequenceNumber = l.Lot))
            THROW 59423, 'A lot this line was taken from no longer exists in Inventory. Nothing was cancelled.', 1;

        -- ledger first (needs the balance before the update), one row per lot
        INSERT INTO dbo.InventoryLedger
            (SequenceRefNum, OriginBranch, DestinationBranch, DateProcessed, Product,
             Description, BegQty, QtyIn, QtyOut, EndQty, Cost, Remarks, ProcessedBy)
        SELECT l.Lot, @parmorigin, @parmbranchcode, GETDATE(), @parmprodno,
               l.Descr, ISNULL(i.Available, 0), l.Qty, 0, ISNULL(i.Available, 0) + l.Qty, l.Cost,
               'STS CANCEL ITEM PO#' + @parmpono, @preparedby
        FROM (SELECT Lot, SUM(Qty) AS Qty, MAX(Cost) AS Cost, MAX(Descr) AS Descr FROM @Lots GROUP BY Lot) AS l
        LEFT JOIN dbo.Inventory AS i WITH (UPDLOCK, ROWLOCK) ON i.SequenceNumber = l.Lot;

        UPDATE i
        SET i.Available = ISNULL(i.Available, 0) + l.Qty,
            i.IsStock = 1
        FROM dbo.Inventory AS i
        INNER JOIN (SELECT Lot, SUM(Qty) AS Qty FROM @Lots GROUP BY Lot) AS l ON l.Lot = i.SequenceNumber;

        UPDATE f SET f.isErrorCorrect = 1
        FROM dbo.InventoryDeliveryFIFO AS f
        INNER JOIN @Lots AS l ON l.FifoSeq = f.SequenceNumber;

        UPDATE dbo.DeliveryDetails
        SET isCancelled = 1, DateTimeUpdated = GETDATE()
        WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono AND SeqNo = @parmdevseqno;

        UPDATE dbo.DeliverySummary
        SET TotalItem = (SELECT ISNULL(COUNT(*),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono),
            TotalQtyDelivered = (SELECT ISNULL(SUM(QtyDelivered),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isCancelled = 0 AND isReturned = 0),
            TotalItemSold = (SELECT ISNULL(COUNT(*),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isCancelled = 0 AND isReturned = 0),
            TotalItemReturned = (SELECT ISNULL(COUNT(*),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isReturned = 1),
            Status = CASE WHEN Status = 'FOR DELIVERY' THEN 'FOR DELIVERY' ELSE 'PENDING' END
        WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono;

        IF @TranCounter = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @TranCounter = 0 BEGIN IF XACT_STATE() <> 0 ROLLBACK TRANSACTION; END
        ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION CancelDeliverySave;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------
-- D. sp_ConfirmBranchOrder: weighted line cost (only change)
-- ----------------------------------------------------------------
DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ConfirmBranchOrder'));
DECLARE @old NVARCHAR(MAX) = N'SET dd.Cost =  isnull(i.Cost,0)
		FROM DeliveryDetails dd
		INNER JOIN InventoryDeliveryFIFO i
			ON dd.PONumber=i.PONumber
			and dd.SeqNo=i.DevDetSeqNo
			and dd.ProductNo=i.ProductNo
			and i.isErrorCorrect=0';
DECLARE @new NVARCHAR(MAX) = N'SET dd.Cost = ISNULL(i.Cost, 0)   -- 2026-10-01: weighted cost of every lot the line used
		FROM DeliveryDetails dd
		INNER JOIN (SELECT DeliveryNo, PONumber, DevDetSeqNo, ProductNo,
		                   SUM(TotalCost) / NULLIF(SUM(QtyDelivered), 0) AS Cost
		            FROM InventoryDeliveryFIFO
		            WHERE isErrorCorrect = 0
		            GROUP BY DeliveryNo, PONumber, DevDetSeqNo, ProductNo) i
			ON dd.DeliveryNo=i.DeliveryNo
			and dd.PONumber=i.PONumber
			and dd.SeqNo=i.DevDetSeqNo
			and dd.ProductNo=i.ProductNo';
SET @def = REPLACE(@def, CHAR(13) + CHAR(10), CHAR(10));
SET @old = REPLACE(@old, CHAR(13) + CHAR(10), CHAR(10));
IF CHARINDEX(@old, @def) = 0
    THROW 59430, 'sp_ConfirmBranchOrder text differs from the version this script was written for; not changed.', 1;
SET @def = REPLACE(@def, @old, @new);
EXEC sp_rename 'dbo.sp_ConfirmBranchOrder', 'sp_ConfirmBranchOrder_OLD_10012026150000';
EXEC (@def);
GO

-- ----------------------------------------------------------------
-- E. Credit memo
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_CreditMemo', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_CreditMemo', 'sp_CreditMemo_OLD_10012026150000';
GO
CREATE PROCEDURE dbo.sp_CreditMemo
    @parmpono varchar(10),
    @parmuser varchar(30),
    @parmstat varchar(30),
    @Lines    dbo.tt_CreditMemoLines READONLY
AS
/*
    Credit memo = shrinkage: the customer accepted less than was delivered
    (ActualQty < QtyDelivered); the missing qty is gone.
      Before confirm: set ActualQty / Variance (confirm then bills ActualQty) and
        post SO-SHRINK-* (DR COS OTHERS / CR Inventory, cost of the missing qty).
        No client-ledger entry: there is no invoice yet.
      After confirm: spu_SO_PostInvoiceReduction 'CM' (sales / VAT / AR, cost
        moved to COS OTHERS, excess to customer credit).
    Whether the PO is confirmed is read from TransactionChargeSales; @parmstat
    must agree. Caller: HOFormsDevEx/CreditMemoDevEx.cs. Same parameters as before.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM @Lines)
            THROW 59002, 'No lines submitted for this Credit Memo.', 1;

        DECLARE @custkey CHAR(8), @custname VARCHAR(150), @branch VARCHAR(5), @invoiceno VARCHAR(50);
        SELECT @custkey = Customer, @branch = BranchCode FROM dbo.PurchaseOrderSummary WHERE PONumber = @parmpono;
        SELECT @invoiceno = InvoiceNo FROM dbo.DeliverySummary WHERE PONumber = @parmpono;
        SELECT @custname = CustomerName FROM dbo.Customers WHERE CustomerKey = @custkey;

        DECLARE @confirmed BIT = CASE WHEN EXISTS (SELECT 1 FROM dbo.TransactionChargeSales
                                                   WHERE CustomerKey = @custkey AND ReferenceNo = @parmpono AND InvoiceNo = @invoiceno)
                                      THEN 1 ELSE 0 END;
        IF (@confirmed = 1 AND ISNULL(@parmstat, '') <> 'DELIVERED') OR (@confirmed = 0 AND ISNULL(@parmstat, '') = 'DELIVERED')
            THROW 59003, 'The screen status does not match the order: refresh the list and open the credit memo from the right tab.', 1;

        IF EXISTS (SELECT 1 FROM @Lines l
                   JOIN dbo.DeliveryDetails dd ON dd.PONumber = @parmpono AND dd.SeqNo = l.SeqNo AND dd.ProductNo = l.ProductNo
                   WHERE l.ActualQty < 0 OR l.ActualQty > dd.QtyDelivered)
            THROW 59004, 'Actual quantity must be between 0 and the delivered quantity.', 1;

        UPDATE dd
           SET dd.ActualQty    = l.ActualQty,
               dd.Variance     = dd.QtyDelivered - l.ActualQty,
               dd.isCreditMemo = 1
        FROM dbo.DeliveryDetails dd
        JOIN @Lines l ON dd.SeqNo = l.SeqNo AND dd.ProductNo = l.ProductNo
        WHERE dd.PONumber = @parmpono
          AND dd.isCreditMemo = 0 AND dd.isReturned = 0 AND dd.isCancelled = 0;

        SELECT dd.DeliveryNo, dd.ReferenceNumber, dd.SeqNo, dd.ProductNo, dd.ProductName,
               dd.QtyDelivered, dd.ActualQty, dd.Variance, dd.SellingPrice, dd.Cost, dd.isVat
        INTO #CMBatch
        FROM dbo.DeliveryDetails dd
        JOIN @Lines l ON dd.SeqNo = l.SeqNo AND dd.ProductNo = l.ProductNo
        WHERE dd.PONumber = @parmpono
          AND ISNULL(dd.Variance, 0) > 0
          AND dd.isReturned = 0 AND dd.isCancelled = 0
          AND NOT EXISTS (SELECT 1 FROM dbo.CreditMemo cm
                          WHERE cm.PONumber = dd.PONumber AND cm.ProductCode = dd.ProductNo AND cm.DeliveryNo = dd.DeliveryNo
                            AND cm.ReferenceNumber = dd.ReferenceNumber AND cm.SeqNo = dd.SeqNo);

        IF NOT EXISTS (SELECT 1 FROM #CMBatch)
            THROW 59001, 'No new Credit Memo variance to process for this PO (already processed, or ActualQty unchanged).', 1;

        UPDATE dbo.DeliverySummary
           SET TotalActualQty         = (SELECT SUM(ActualQty) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isReturned = 0 AND isCancelled = 0),
               TotalVarianceVat       = (SELECT SUM(Variance) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isVat = 1 AND isReturned = 0 AND isCancelled = 0),
               TotalVarianceVatExempt = (SELECT SUM(Variance) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isVat = 0 AND isReturned = 0 AND isCancelled = 0)
         WHERE PONumber = @parmpono;

        -- VAT split per line, the way sp_ConfirmOrder rounds the invoice
        DECLARE @nVat DECIMAL(18,2), @tVat DECIMAL(18,2), @gVatEx DECIMAL(18,2), @cVat DECIMAL(18,2), @cVatEx DECIMAL(18,2);
        SELECT @nVat   = ISNULL(SUM(CASE WHEN isVat = 1 THEN ROUND((Variance * SellingPrice) / 1.12, 2) END), 0),
               @tVat   = ISNULL(SUM(CASE WHEN isVat = 1 THEN ROUND((Variance * SellingPrice) / 1.12 * 0.12, 2) END), 0),
               @gVatEx = ISNULL(SUM(CASE WHEN ISNULL(isVat, 0) = 0 THEN ROUND(Variance * SellingPrice, 2) END), 0),
               @cVat   = ISNULL(SUM(CASE WHEN isVat = 1 THEN ROUND(Variance * ISNULL(Cost, 0), 2) END), 0),
               @cVatEx = ISNULL(SUM(CASE WHEN ISNULL(isVat, 0) = 0 THEN ROUND(Variance * ISNULL(Cost, 0), 2) END), 0)
        FROM #CMBatch;

        DECLARE @Particulars VARCHAR(6999) = 'CREDIT MEMO | Customer: ' + ISNULL(@custname, '') + ' | PO: ' + @parmpono + ' | Invoice: ' + ISNULL(@invoiceno, '');
        DECLARE @tkVat VARCHAR(20) = ' ', @tkVatEx VARCHAR(20) = ' ', @excess DECIMAL(18,2) = 0;
        DECLARE @Today DATE = CAST(GETDATE() AS DATE);

        IF @confirmed = 1
        BEGIN
            EXEC dbo.spu_SO_PostInvoiceReduction
                @Kind = 'CM', @PONumber = @parmpono, @InvoiceNo = @invoiceno, @CustomerKey = @custkey,
                @BranchCode = @branch, @User = @parmuser,
                @NetVat = @nVat, @TaxVat = @tVat, @CostVat = @cVat, @GrossVatEx = @gVatEx, @CostVatEx = @cVatEx,
                @Particulars = @Particulars,
                @TicketVat = @tkVat OUTPUT, @TicketVatEx = @tkVatEx OUTPUT, @Excess = @excess OUTPUT;

            UPDATE dbo.BatchSalesSummary
            SET TotalDiscountAmount = ISNULL(TotalDiscountAmount, 0) + @nVat + @tVat + @gVatEx
            WHERE ReferenceNo = @parmpono AND BranchCode = @branch;
        END
        ELSE
        BEGIN
            -- shrinkage before confirm: inventory already left at the scan; confirm will cost only ActualQty
            DECLARE @Amt dbo.tt_AmountBreakdown, @Tok dbo.tt_TokenResolution, @Flg dbo.tt_ConditionFlags;
            IF @cVat > 0
            BEGIN
                INSERT @Amt VALUES ('GROSS', @cVat), ('COST', @cVat);
                EXEC dbo.sp_PostCompoundTicketSales @Mnemonic = 'SO-SHRINK-VAT', @TicketDate = @Today, @BranchCode = @branch,
                    @ReferenceNumber = @parmpono, @ReferenceKey = @invoiceno, @Particulars = @Particulars, @Owner = @custname,
                    @PreparedBy = @parmuser, @Status = 'POSTED', @Amounts = @Amt, @Tokens = @Tok, @Flags = @Flg, @LedgerType = NULL;
                SELECT TOP 1 @tkVat = CAST(TicketNumber AS VARCHAR(20)) FROM dbo.TicketMaster
                WHERE ReferenceNumber = @parmpono AND Mnemonic = 'SO-SHRINK-VAT' ORDER BY TRY_CAST(TicketNumber AS BIGINT) DESC;
                DELETE FROM @Amt;
            END
            IF @cVatEx > 0
            BEGIN
                INSERT @Amt VALUES ('GROSS', @cVatEx), ('COST', @cVatEx);
                EXEC dbo.sp_PostCompoundTicketSales @Mnemonic = 'SO-SHRINK-VATEX', @TicketDate = @Today, @BranchCode = @branch,
                    @ReferenceNumber = @parmpono, @ReferenceKey = @invoiceno, @Particulars = @Particulars, @Owner = @custname,
                    @PreparedBy = @parmuser, @Status = 'POSTED', @Amounts = @Amt, @Tokens = @Tok, @Flags = @Flg, @LedgerType = NULL;
                SELECT TOP 1 @tkVatEx = CAST(TicketNumber AS VARCHAR(20)) FROM dbo.TicketMaster
                WHERE ReferenceNumber = @parmpono AND Mnemonic = 'SO-SHRINK-VATEX' ORDER BY TRY_CAST(TicketNumber AS BIGINT) DESC;
            END
            IF EXISTS (SELECT 1 FROM dbo.TicketDetails WHERE CAST(TicketNumber AS VARCHAR(20)) IN (@tkVat, @tkVatEx)
                       GROUP BY TicketNumber HAVING ABS(SUM(ISNULL(Debit,0)) - SUM(ISNULL(Credit,0))) > 0.005)
                THROW 59005, 'Shrinkage ticket does not balance. Check the SO-SHRINK mapping rows.', 1;
        END

        INSERT INTO dbo.CreditMemo
            (PONumber, ProductCode, Description, Qty, ActualQty, Variance,
             SellingPrice, TotalAmount, DiscountAmount, TicketRefNo, DateAdded, ExecuteBy,
             DeliveryNo, ReferenceNumber, SeqNo)
        SELECT @parmpono, ProductNo, ProductName, QtyDelivered, ActualQty, Variance,
               SellingPrice, ROUND(ActualQty * SellingPrice, 2), ROUND(Variance * SellingPrice, 2),
               CASE WHEN isVat = 1 THEN @tkVat ELSE @tkVatEx END, @Today, @parmuser,
               DeliveryNo, ReferenceNumber, SeqNo
        FROM #CMBatch;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------
-- F. Return
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_ReturnSalesOrder', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_ReturnSalesOrder', 'sp_ReturnSalesOrder_OLD_10012026150000';
GO
CREATE PROCEDURE dbo.sp_ReturnSalesOrder
    @parmbranchcode   char(3),
    @parmpono         varchar(10),
    @parmdevno        varchar(10),
    @parmuser         varchar(50),
    @parmreturnstatus varchar(30),
    @parmreason       varchar(930),
    @parmmachinename  varchar(50),
    @Lines            dbo.tt_ReturnSalesOrderLines READONLY
AS
/*
    Returns delivery lines. Only SeqNo / ProductNo are taken from @Lines; every
    quantity and price is re-read from DeliveryDetails.
      Stock: ActualQty (the billed qty) goes back to the lots the line used,
        newest consumed lot first, one InventoryLedger row per lot.
      Before confirm: no GL (nothing was billed); confirm skips returned lines.
      After confirm: sales lines cancelled 1:1, sales header recomputed, AR
        invoice lines tagged, then spu_SO_PostInvoiceReduction 'RET' for
        THIS return only (sales / VAT / AR, cost back to inventory, excess to
        customer credit).
    Caller: Orders/ReturnSalesOrder.cs. Same parameters as before.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM @Lines)
            THROW 59101, 'No lines submitted for this Sales Return.', 1;

        DECLARE @invoiceno VARCHAR(50), @effectivitydate DATE, @custkey CHAR(8), @custname VARCHAR(150), @branch VARCHAR(5);
        SELECT @invoiceno = InvoiceNo, @effectivitydate = EffectivityDate FROM dbo.DeliverySummary WHERE PONumber = @parmpono AND DeliveryNo = @parmdevno;
        SELECT @custkey = Customer, @branch = BranchCode FROM dbo.PurchaseOrderSummary WHERE PONumber = @parmpono;
        SELECT @custname = CustomerName FROM dbo.Customers WHERE CustomerKey = @custkey;

        DECLARE @confirmed BIT = CASE WHEN EXISTS (SELECT 1 FROM dbo.TransactionChargeSales
                                                   WHERE CustomerKey = @custkey AND ReferenceNo = @parmpono AND InvoiceNo = @invoiceno)
                                      THEN 1 ELSE 0 END;
        IF (@confirmed = 1 AND ISNULL(@parmreturnstatus, '') <> 'DELIVERED') OR (@confirmed = 0 AND ISNULL(@parmreturnstatus, '') = 'DELIVERED')
            THROW 59103, 'The screen status does not match the order: refresh the list and open the return from the right tab.', 1;

        SELECT dd.DeliveryNo, dd.SeqNo, dd.PONumber, dd.ProductNo, dd.ProductName, dd.BarcodeNo,
               dd.QtyDelivered, ISNULL(dd.Cost, 0) AS Cost, ISNULL(dd.SellingPrice, 0) AS SellingPrice,
               ISNULL(dd.ActualQty, dd.QtyDelivered) AS ActualQty, dd.Variance, ISNULL(dd.isVat, 0) AS isVat
        INTO #NewReturns
        FROM dbo.DeliveryDetails dd WITH (UPDLOCK)
        WHERE dd.PONumber = @parmpono AND dd.DeliveryNo = @parmdevno
          AND ISNULL(dd.isReturned, 0) = 0 AND ISNULL(dd.isCancelled, 0) = 0
          AND EXISTS (SELECT 1 FROM @Lines l WHERE l.SeqNo = dd.SeqNo AND l.ProductNo = dd.ProductNo);

        IF NOT EXISTS (SELECT 1 FROM #NewReturns)
            THROW 59102, 'No new lines to return for this PO (already returned or cancelled).', 1;

        INSERT INTO dbo.ReturnedOrderDetails
            (SeqNo, PONumber, ProductNo, ProductName, BarcodeNo, QtyDelivered,
             Cost, SellingPrice, ActualQty, Variance, isVat, ProcessedBy, DateProcessed)
        SELECT SeqNo, PONumber, ProductNo, ProductName, BarcodeNo, QtyDelivered,
               Cost, SellingPrice, ActualQty, Variance, isVat, @parmuser, CAST(GETDATE() AS DATE)
        FROM #NewReturns;

        DECLARE @RetItems INT, @RetQty DECIMAL(18,3), @RetAmt DECIMAL(18,2);
        SELECT @RetItems = COUNT(*), @RetQty = ISNULL(SUM(ActualQty), 0), @RetAmt = ISNULL(SUM(ROUND(ActualQty * SellingPrice, 2)), 0)
        FROM dbo.ReturnedOrderDetails WHERE PONumber = @parmpono;
        IF NOT EXISTS (SELECT 1 FROM dbo.ReturnedOrderSummary WITH (UPDLOCK) WHERE PONumber = @parmpono)
            INSERT INTO dbo.ReturnedOrderSummary (PONumber, InvoiceNo, BranchCode, TotalItem, TotalQtyDelivered, TotalAmount, EffectivityDate, DateAdded, PreparedBy, ReturnType, Reason)
            VALUES (@parmpono, @invoiceno, @parmbranchcode, @RetItems, @RetQty, @RetAmt, @effectivitydate, GETDATE(), @parmuser, ' ', @parmreason);
        ELSE
            UPDATE dbo.ReturnedOrderSummary SET TotalItem = @RetItems, TotalQtyDelivered = @RetQty, TotalAmount = @RetAmt WHERE PONumber = @parmpono;

        UPDATE dd SET dd.isReturned = 1, dd.DateTimeUpdated = GETDATE()
        FROM dbo.DeliveryDetails dd
        INNER JOIN #NewReturns r ON r.DeliveryNo = dd.DeliveryNo AND r.PONumber = dd.PONumber AND r.SeqNo = dd.SeqNo;

        DECLARE @Live INT = (SELECT COUNT(*) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isReturned = 0 AND isCancelled = 0);
        UPDATE dbo.DeliverySummary
        SET TotalItem = (SELECT ISNULL(COUNT(*),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono),
            TotalQtyDelivered = (SELECT ISNULL(SUM(QtyDelivered),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isCancelled = 0),
            TotalActualQty = (SELECT ISNULL(SUM(ActualQty),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isCancelled = 0 AND isReturned = 0),
            TotalItemSold = (SELECT ISNULL(COUNT(*),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isCancelled = 0 AND isReturned = 0),
            TotalItemReturned = (SELECT ISNULL(COUNT(*),0) FROM dbo.DeliveryDetails WHERE PONumber = @parmpono AND isReturned = 1),
            Status = CASE WHEN @Live = 0 THEN 'RETURNED' ELSE Status END
        WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono;

        -- stock: put ActualQty back, newest consumed lot first
        ;WITH F AS (
            SELECT f.SequenceNumber AS FifoSeq, f.SequenceReferenceNumber AS Lot, ISNULL(f.QtyDelivered, 0) AS Qty, ISNULL(f.Cost, 0) AS Cost,
                   f.Description, r.ActualQty, r.ProductNo,
                   SUM(ISNULL(f.QtyDelivered, 0)) OVER (PARTITION BY r.SeqNo ORDER BY f.SequenceNumber DESC ROWS UNBOUNDED PRECEDING) AS RunQty
            FROM dbo.InventoryDeliveryFIFO f WITH (UPDLOCK, ROWLOCK)
            INNER JOIN #NewReturns r ON r.DeliveryNo = f.DeliveryNo AND r.PONumber = f.PONumber AND r.SeqNo = f.DevDetSeqNo
            WHERE f.isErrorCorrect = 0)
        SELECT FifoSeq, Lot, Cost, Description, ProductNo,
               CASE WHEN RunQty <= ActualQty THEN Qty
                    WHEN RunQty - Qty < ActualQty THEN ActualQty - (RunQty - Qty)
                    ELSE 0 END AS RestoreQty
        INTO #Restore
        FROM F;

        INSERT INTO dbo.InventoryLedger
            (SequenceRefNum, OriginBranch, DestinationBranch, DateProcessed, Product,
             Description, BegQty, QtyIn, QtyOut, EndQty, Cost, Remarks, ProcessedBy)
        SELECT x.Lot, @parmbranchcode, ISNULL(i.Branch, '888'), GETDATE(), x.ProductNo,
               x.Description, ISNULL(i.Available, 0), x.RestoreQty, 0, ISNULL(i.Available, 0) + x.RestoreQty, x.Cost,
               'SO RETURN PO#' + @parmpono, @parmuser
        FROM (SELECT Lot, ProductNo, MAX(Cost) AS Cost, MAX(Description) AS Description, SUM(RestoreQty) AS RestoreQty
              FROM #Restore GROUP BY Lot, ProductNo HAVING SUM(RestoreQty) > 0) x
        LEFT JOIN dbo.Inventory i WITH (UPDLOCK, ROWLOCK) ON i.SequenceNumber = x.Lot;

        UPDATE i SET i.Available = ISNULL(i.Available, 0) + x.RestoreQty, i.IsStock = 1
        FROM dbo.Inventory i
        INNER JOIN (SELECT Lot, SUM(RestoreQty) AS RestoreQty FROM #Restore GROUP BY Lot HAVING SUM(RestoreQty) > 0) x ON x.Lot = i.SequenceNumber;

        UPDATE f SET f.isErrorCorrect = 1
        FROM dbo.InventoryDeliveryFIFO f INNER JOIN #Restore x ON x.FifoSeq = f.SequenceNumber;

        IF @confirmed = 1
        BEGIN
            -- sales lines: pair each returned delivery line with one live sales line of the same product + barcode
            -- (BatchSalesDetails has no usable row key: SequenceNumber is not filled by sp_ConfirmOrder,
            --  so the rows are numbered and updated through the CTE itself)
            ;WITH BS AS (SELECT b.isCancelled, b.ProductCode, ISNULL(b.Barcode, '') AS Barcode,
                               ROW_NUMBER() OVER (PARTITION BY b.ProductCode, ISNULL(b.Barcode, '') ORDER BY b.QtySold DESC, b.TotalAmount DESC) AS rn
                        FROM dbo.BatchSalesDetails b
                        WHERE b.ReferenceNo = @parmpono AND b.BranchCode = @branch AND ISNULL(b.isCancelled, 0) = 0),
                  RS AS (SELECT r.ProductNo, ISNULL(r.BarcodeNo, '') AS Barcode,
                               ROW_NUMBER() OVER (PARTITION BY r.ProductNo, ISNULL(r.BarcodeNo, '') ORDER BY r.SeqNo) AS rn
                        FROM #NewReturns r)
            UPDATE BS SET isCancelled = 1
            FROM BS
            INNER JOIN RS ON RS.ProductNo = BS.ProductCode AND RS.Barcode = BS.Barcode AND RS.rn = BS.rn;

            UPDATE s SET
                TotalItemReturned   = x.ItemRet,  TotalItem = x.Item,  TotalItemSold = x.Item,
                TotalVatableItems   = x.VatItems, TotalReturnedAmount = x.RetAmt,
                TotalTax = x.Tax, TotalKilos = x.Kilos, SubTotal = x.SubTotal, TotalAmount = x.Amt,
                TotalVATSale = x.Tax, TotalVATExemptSale = x.VatExempt, TotalVatableSale = x.Vatable
            FROM dbo.BatchSalesSummary s
            CROSS APPLY (SELECT
                SUM(CASE WHEN isCancelled = 1 AND isVoid = 0 THEN 1 ELSE 0 END) AS ItemRet,
                SUM(CASE WHEN isCancelled = 0 AND isVoid = 0 THEN 1 ELSE 0 END) AS Item,
                SUM(CASE WHEN isVat = 1 AND isCancelled = 0 AND isVoid = 0 THEN 1 ELSE 0 END) AS VatItems,
                ISNULL(SUM(CASE WHEN isCancelled = 1 AND isVoid = 0 THEN TotalAmount END), 0) AS RetAmt,
                ISNULL(SUM(CASE WHEN isCancelled = 0 AND isVoid = 0 THEN TaxTotal END), 0) AS Tax,
                ISNULL(SUM(CASE WHEN isCancelled = 0 AND isVoid = 0 THEN QtySold END), 0) AS Kilos,
                ISNULL(SUM(CASE WHEN isCancelled = 0 AND isVoid = 0 THEN SubTotal END), 0) AS SubTotal,
                ISNULL(SUM(CASE WHEN isCancelled = 0 AND isVoid = 0 THEN TotalAmount END), 0) AS Amt,
                ISNULL(SUM(CASE WHEN isVat = 0 AND isCancelled = 0 AND isVoid = 0 THEN TotalAmount END), 0) AS VatExempt,
                ISNULL(SUM(CASE WHEN isVat = 1 AND isCancelled = 0 AND isVoid = 0 THEN SubTotal END), 0) AS Vatable
                FROM dbo.BatchSalesDetails b WHERE b.ReferenceNo = s.ReferenceNo AND b.BranchCode = s.BranchCode) x
            WHERE s.ReferenceNo = @parmpono AND s.BranchCode = @branch;

            UPDATE d SET d.ErrorTag = 1
            FROM dbo.TransactionChargeSalesDetails d
            WHERE d.ReferenceNo = @parmpono AND d.InvoiceNo = @invoiceno AND ISNULL(d.ErrorTag, 0) = 0
              AND EXISTS (SELECT 1 FROM #NewReturns r WHERE r.ProductNo = d.Product AND ISNULL(r.BarcodeNo, '') = ISNULL(d.SKU, ''));

            -- VAT split per line, the way sp_ConfirmOrder rounded the invoice
            DECLARE @nVat DECIMAL(18,2), @tVat DECIMAL(18,2), @gVatEx DECIMAL(18,2), @cVat DECIMAL(18,2), @cVatEx DECIMAL(18,2);
            SELECT @nVat   = ISNULL(SUM(CASE WHEN isVat = 1 THEN ROUND((ActualQty * SellingPrice) / 1.12, 2) END), 0),
                   @tVat   = ISNULL(SUM(CASE WHEN isVat = 1 THEN ROUND((ActualQty * SellingPrice) / 1.12 * 0.12, 2) END), 0),
                   @gVatEx = ISNULL(SUM(CASE WHEN isVat = 0 THEN ROUND(ActualQty * SellingPrice, 2) END), 0),
                   @cVat   = ISNULL(SUM(CASE WHEN isVat = 1 THEN ROUND(ActualQty * Cost, 2) END), 0),
                   @cVatEx = ISNULL(SUM(CASE WHEN isVat = 0 THEN ROUND(ActualQty * Cost, 2) END), 0)
            FROM #NewReturns;

            DECLARE @Particulars VARCHAR(6999) = 'SALES RETURN | Customer: ' + ISNULL(@custname, '') + ' | PO: ' + @parmpono + ' | Invoice: ' + ISNULL(@invoiceno, '');
            DECLARE @tkVat VARCHAR(20), @tkVatEx VARCHAR(20), @excess DECIMAL(18,2);
            EXEC dbo.spu_SO_PostInvoiceReduction
                @Kind = 'RET', @PONumber = @parmpono, @InvoiceNo = @invoiceno, @CustomerKey = @custkey,
                @BranchCode = @branch, @User = @parmuser,
                @NetVat = @nVat, @TaxVat = @tVat, @CostVat = @cVat, @GrossVatEx = @gVatEx, @CostVatEx = @cVatEx,
                @Particulars = @Particulars,
                @TicketVat = @tkVat OUTPUT, @TicketVatEx = @tkVatEx OUTPUT, @Excess = @excess OUTPUT;

            UPDATE dbo.ReturnedOrderSummary
            SET TicketRefNoVAT   = CASE WHEN @tkVat   <> ' ' THEN @tkVat   ELSE TicketRefNoVAT END,
                TicketRefNoVATEX = CASE WHEN @tkVatEx <> ' ' THEN @tkVatEx ELSE TicketRefNoVATEX END
            WHERE PONumber = @parmpono;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
