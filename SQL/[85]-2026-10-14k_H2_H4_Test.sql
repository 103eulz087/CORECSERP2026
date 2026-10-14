/* ================================================================
   [85] TEST SCRIPT - H2 (AR reversal scope) + H4 (atomic wrappers, STS receive in one call)
   ================================================================
   Run in SSMS on DEV or STAGING AFTER [85] is applied. Every test runs inside BEGIN TRAN ... ROLLBACK, so nothing is
   left behind; the result set at the end shows PASS / FAIL / BUG SHOWN per test. Do NOT run on PRODUCTION (it posts and
   reverses inside transactions; the read-only login can't run it anyway).

   Fixtures are picked automatically (first result set shows them):
     - an AR payment whose reference is also the PO number of another customer's sales ticket (the H2 case)
     - an ordinary AR payment (no collision)
     - a saved STS transfer waiting to be received (FIFO rows), with its branch and delivery
     - an open single-line expense (POSTED, nothing paid yet) and its supplier
   If one is missing on the database, its tests show SKIP.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT OFF;   -- the tests catch the refusals themselves

DECLARE @r TABLE (Seq INT IDENTITY, Test VARCHAR(50), Result VARCHAR(12), Detail VARCHAR(600));
DECLARE @err INT, @n INT, @m INT, @lc INT, @k VARCHAR(10), @st VARCHAR(30), @dr DECIMAL(18,2), @cr DECIMAL(18,2);

------------------------------------------------------------------
-- 0. fixtures
------------------------------------------------------------------
DECLARE @phCollide INT, @refCollide VARCHAR(20), @custCollide CHAR(8), @salesTicket VARCHAR(20);
SELECT TOP (1) @phCollide = ph.PaymentHeaderID, @refCollide = ph.ReferenceNo, @custCollide = ph.CustomerKey, @salesTicket = tm.TicketNumber
FROM PaymentHeader ph JOIN TicketMaster tm ON tm.ReferenceNumber = ph.ReferenceNo AND tm.Mnemonic LIKE 'SI-%'
WHERE ph.Status <> 'REVERSED'
  AND EXISTS (SELECT 1 FROM TicketMaster o WHERE o.ReferenceNumber = ph.ReferenceNo AND ISNULL(o.Status, '') <> 'REVERSED' AND (o.Mnemonic LIKE 'OR-%' OR (ISNULL(o.Mnemonic, '') = '' AND o.ReferenceKey = ph.ReferenceNo)))
ORDER BY ph.PaymentHeaderID DESC;

DECLARE @phPlain INT, @refPlain VARCHAR(20);
SELECT TOP (1) @phPlain = ph.PaymentHeaderID, @refPlain = ph.ReferenceNo
FROM PaymentHeader ph
WHERE ph.Status <> 'REVERSED' AND ph.PaymentHeaderID <> ISNULL(@phCollide, -1)
  AND EXISTS (SELECT 1 FROM TicketMaster o WHERE o.ReferenceNumber = ph.ReferenceNo AND o.Mnemonic LIKE 'OR-%')
  AND NOT EXISTS (SELECT 1 FROM TicketMaster o WHERE o.ReferenceNumber = ph.ReferenceNo AND ISNULL(o.Mnemonic, '') NOT LIKE 'OR-%' AND ISNULL(o.Status, '') <> 'REVERSED')
  AND EXISTS (SELECT 1 FROM ARPaymentDetails d WHERE d.PaymentHeaderID = ph.PaymentHeaderID AND d.PaymentType = 'INVOICE PAYMENT')
ORDER BY ph.PaymentHeaderID DESC;

DECLARE @po VARCHAR(10), @dev VARCHAR(20), @br VARCHAR(10), @rows INT;
SELECT TOP (1) @po = d.PONumber, @dev = d.DeliveryNo, @br = d.BranchCode, @rows = x.n
FROM DeliverySummary d
CROSS APPLY (SELECT COUNT(*) AS n FROM dbo.funcview_InventoryDeliveryFIFOForReceivingV2(d.PONumber)) x
WHERE d.Status <> 'DELIVERED' AND x.n > 0 AND EXISTS (SELECT 1 FROM TransferOrderSummary t WHERE t.PONumber = d.PONumber)
ORDER BY TRY_CAST(d.PONumber AS INT) DESC;

DECLARE @exp VARCHAR(10), @sup VARCHAR(10), @supName VARCHAR(150), @inv VARCHAR(100), @batch BIGINT, @amt DECIMAL(18,2), @expDate DATE;
SELECT TOP (1) @exp = e.ReferenceNumber, @sup = e.SupplierID, @supName = s.SupplierName, @inv = e.InvoiceNo, @batch = e.BatchReferenceID, @amt = e.Amount, @expDate = e.ExpenseDate
FROM ExpenseSummary e JOIN Supplier s ON s.SupplierID = e.SupplierID
WHERE e.Status = 'POSTED' AND e.PostingMode = 'SINGLE' AND e.Balance = e.Amount AND e.Balance > 0 AND ISNULL(e.AmountPaid, 0) = 0
  AND (SELECT COUNT(*) FROM ExpenseMaster m WHERE m.ReferenceNumber = e.ReferenceNumber) = 1
  AND EXISTS (SELECT 1 FROM ExpenseMaster m WHERE m.ReferenceNumber = e.ReferenceNumber AND m.BranchCode = '888')
ORDER BY e.ReferenceNumber DESC;

DECLARE @caAcct VARCHAR(20) = (SELECT TOP (1) a.AccountCode FROM CashAdvanceAllowedAccounts a JOIN ChartOfAccounts c ON c.AccountCode = a.AccountCode ORDER BY a.AccountCode);
DECLARE @bank VARCHAR(30) = '101020101';
DECLARE @tref VARCHAR(10) = '99904';   -- test reference / voucher id (must be unused)
IF EXISTS (SELECT 1 FROM CheckVoucher WHERE ReferenceNumber = @tref OR VoucherID = CAST(@tref AS DECIMAL(7,0))) OR EXISTS (SELECT 1 FROM TicketMaster WHERE ReferenceNumber = @tref)
    SET @tref = '99905';

SELECT 'fixtures' AS what, @phCollide AS payment_with_collision, @refCollide AS its_reference, @salesTicket AS colliding_sales_ticket, @phPlain AS plain_payment,
       @po AS sts_po, @dev AS delivery, @br AS branch, @rows AS screen_rows, @exp AS expense, @sup AS supplier, @inv AS invoice, @amt AS amount, @caAcct AS cash_advance_account, @tref AS test_ref;

------------------------------------------------------------------
-- H2-1 the OLD text on the colliding payment: refused by the ticket PK (two masters under one reversal ticket no.)
------------------------------------------------------------------
IF @phCollide IS NULL INSERT @r VALUES ('H2-1 old proc, collision', 'SKIP', 'no live payment with a colliding sales ticket here');
ELSE
BEGIN
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_ReversePaymentClient_OLD_10152026003000 @PaymentHeaderID = @phCollide, @ReversedBy = 'TEST85';
        INSERT @r VALUES ('H2-1 old proc, collision', 'UNEXPECTED', 'the old proc posted the reversal');
    END TRY BEGIN CATCH
        INSERT @r VALUES ('H2-1 old proc, collision', CASE WHEN ERROR_NUMBER() = 2627 THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END, CONCAT('refused ', ERROR_NUMBER(), ': ', LEFT(ERROR_MESSAGE(), 110)));
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
END

------------------------------------------------------------------
-- H2-2 the NEW text on the same payment: one reversal ticket, the customer's ledger only, the sales ticket untouched
------------------------------------------------------------------
IF @phCollide IS NULL INSERT @r VALUES ('H2-2 new proc, collision', 'SKIP', '');
ELSE
BEGIN
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_ReversePaymentClient @PaymentHeaderID = @phCollide, @ReversedBy = 'TEST85';
        SELECT @m = COUNT(*) FROM TicketMaster WHERE ReferenceNumber = @refCollide AND Status = 'REVERSED';
        SELECT @n = COUNT(*), @dr = SUM(Debit), @cr = SUM(Credit) FROM TicketDetails WHERE TicketNumber = (SELECT TOP 1 TicketNumber FROM TicketMaster WHERE ReferenceNumber = @refCollide AND Status = 'REVERSED');
        SELECT @lc = COUNT(DISTINCT AccountKey), @k = MAX(AccountKey) FROM ClientLedger WHERE ReferenceNumber = @refCollide AND Remarks = 'REVERSAL ENTRY';
        SELECT @st = Status FROM TicketMaster WHERE TicketNumber = @salesTicket;
        INSERT @r VALUES ('H2-2 new proc, collision', CASE WHEN @m = 1 AND @dr = @cr AND @lc = 1 AND @k = @custCollide AND @st = 'POSTED' THEN 'PASS' ELSE 'FAIL' END,
                          CONCAT('reversal masters ', @m, ', lines ', @n, ' DR ', @dr, ' CR ', @cr, ', ledger customers ', @lc, ' (', @k, '), sales ticket ', @salesTicket, ' still ', @st));
    END TRY BEGIN CATCH INSERT @r VALUES ('H2-2 new proc, collision', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
END

------------------------------------------------------------------
-- H2-3 an ordinary payment: OLD and NEW post the same rows
------------------------------------------------------------------
IF @phPlain IS NULL INSERT @r VALUES ('H2-3 plain payment old = new', 'SKIP', '');
ELSE
BEGIN
    DECLARE @fp TABLE (Run VARCHAR(3), Item VARCHAR(10), Val VARCHAR(MAX));
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_ReversePaymentClient_OLD_10152026003000 @PaymentHeaderID = @phPlain, @ReversedBy = 'TEST85';
        INSERT @fp SELECT 'old', 'TKD', CONCAT(COUNT(*), '|', SUM(Debit), '|', SUM(Credit), '|', STRING_AGG(CONCAT(AccountCode, ':', Debit, ':', Credit), ',') WITHIN GROUP (ORDER BY AccountCode, Debit, Credit)) FROM TicketDetails WHERE ReferenceNumber = @refPlain;
        INSERT @fp SELECT 'old', 'CL', CONCAT(COUNT(*), '|', SUM(Debit), '|', SUM(Credit), '|', STRING_AGG(CONCAT(AccountKey, ':', TransCode, ':', Debit, ':', Credit, ':', InvoiceNo), ',') WITHIN GROUP (ORDER BY AccountKey, TransCode, InvoiceNo, Debit)) FROM ClientLedger WHERE ReferenceNumber = @refPlain;
        INSERT @fp SELECT 'old', 'TCS', STRING_AGG(CONCAT(t.InvoiceNo, ':', t.ReferenceNo, ':', t.AmountPaid, ':', t.Balance, ':', t.PayStatus), ',') WITHIN GROUP (ORDER BY t.InvoiceNo, t.ReferenceNo) FROM TransactionChargeSales t WHERE EXISTS (SELECT 1 FROM ARPaymentDetails d WHERE d.PaymentHeaderID = @phPlain AND d.InvoiceNo = t.InvoiceNo AND d.PONumber = t.ReferenceNo);
    END TRY BEGIN CATCH INSERT @r VALUES ('H2-3 old', 'ERROR', ERROR_MESSAGE()); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_ReversePaymentClient @PaymentHeaderID = @phPlain, @ReversedBy = 'TEST85';
        INSERT @fp SELECT 'new', 'TKD', CONCAT(COUNT(*), '|', SUM(Debit), '|', SUM(Credit), '|', STRING_AGG(CONCAT(AccountCode, ':', Debit, ':', Credit), ',') WITHIN GROUP (ORDER BY AccountCode, Debit, Credit)) FROM TicketDetails WHERE ReferenceNumber = @refPlain;
        INSERT @fp SELECT 'new', 'CL', CONCAT(COUNT(*), '|', SUM(Debit), '|', SUM(Credit), '|', STRING_AGG(CONCAT(AccountKey, ':', TransCode, ':', Debit, ':', Credit, ':', InvoiceNo), ',') WITHIN GROUP (ORDER BY AccountKey, TransCode, InvoiceNo, Debit)) FROM ClientLedger WHERE ReferenceNumber = @refPlain;
        INSERT @fp SELECT 'new', 'TCS', STRING_AGG(CONCAT(t.InvoiceNo, ':', t.ReferenceNo, ':', t.AmountPaid, ':', t.Balance, ':', t.PayStatus), ',') WITHIN GROUP (ORDER BY t.InvoiceNo, t.ReferenceNo) FROM TransactionChargeSales t WHERE EXISTS (SELECT 1 FROM ARPaymentDetails d WHERE d.PaymentHeaderID = @phPlain AND d.InvoiceNo = t.InvoiceNo AND d.PONumber = t.ReferenceNo);
    END TRY BEGIN CATCH INSERT @r VALUES ('H2-3 new', 'ERROR', ERROR_MESSAGE()); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE Run = 'old' EXCEPT SELECT Item, Val FROM @fp WHERE Run = 'new') x;
    INSERT @r VALUES ('H2-3 plain payment old = new', CASE WHEN @n = 0 AND (SELECT COUNT(*) FROM @fp WHERE Run = 'new') = 3 THEN 'PASS' ELSE 'FAIL' END, CONCAT('payment ', @phPlain, ': ', @n, ' of 3 footprint rows differ; ', LEFT((SELECT Val FROM @fp WHERE Run = 'new' AND Item = 'TKD'), 150)));
END

------------------------------------------------------------------
-- H2-4 refusal 60002: a second payment ticket under the reference
------------------------------------------------------------------
IF @phPlain IS NULL INSERT @r VALUES ('H2-4 refusal 60002', 'SKIP', '');
ELSE
BEGIN
    BEGIN TRAN;
    BEGIN TRY
        INSERT INTO TicketMaster (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber, ReferenceNumber, ReferenceKey, Owner, Particulars, EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
        SELECT TOP (1) TicketDate, SupplementaryNumber, BranchCode, Origin, '9999901', ReferenceNumber, ReferenceKey, Owner, Particulars, EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product
        FROM TicketMaster WHERE ReferenceNumber = @refPlain AND Mnemonic LIKE 'OR-%';
        EXEC dbo.sp_ReversePaymentClient @PaymentHeaderID = @phPlain, @ReversedBy = 'TEST85';
        INSERT @r VALUES ('H2-4 refusal 60002', 'FAIL', 'not refused');
    END TRY BEGIN CATCH
        INSERT @r VALUES ('H2-4 refusal 60002', CASE WHEN ERROR_NUMBER() = 60002 THEN 'PASS' ELSE 'FAIL' END, CONCAT(ERROR_NUMBER(), ' ', LEFT(ERROR_MESSAGE(), 120)));
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    INSERT @r VALUES ('H2-4 after the refusal', CASE WHEN (SELECT Status FROM PaymentHeader WHERE PaymentHeaderID = @phPlain) = 'POSTED' AND NOT EXISTS (SELECT 1 FROM TicketMaster WHERE TicketNumber = '9999901') THEN 'PASS' ELSE 'FAIL' END, 'header still POSTED, nothing left');
END

------------------------------------------------------------------
-- H4-STS-1 the wrapper receives the whole transfer: DELIVERED, receipt rows, receipt ticket, HO In Transit cleared
------------------------------------------------------------------
DECLARE @L dbo.tt_STSReceiveFIFOLines, @LE dbo.tt_STSReceiveFIFOLines, @RR dbo.tt_STSReceiveReturnRows, @RE dbo.tt_STSReceiveReturnRows;
IF @po IS NULL INSERT @r VALUES ('H4-STS-1 full receipt', 'SKIP', 'no transfer waiting to be received');
ELSE
BEGIN
    INSERT @L SELECT SeqNo, DeliveryNo, ProductNo, BarcodeNo, ActualQty, SellingPrice FROM dbo.funcview_InventoryDeliveryFIFOForReceivingV2(@po);
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.spu_STS_ReceiveTransfer @PONumber = @po, @BranchCode = @br, @ReceivedBy = 'TEST85', @PreparedBy = 'TEST85', @Lines = @L, @ReturnRows = @RE, @GroupedRows = 1;
        SELECT @st = Status FROM DeliverySummary WHERE PONumber = @po;
        SELECT @n = COUNT(*) FROM ReceivedOrderDetails WHERE PONumber = @po;
        SELECT @m = COUNT(*) FROM TicketMaster WHERE ReferenceKey = @po AND Mnemonic LIKE 'IT-BR%';
        SELECT @dr = ISNULL(SUM(Debit) - SUM(Credit), 0) FROM TicketDetails WHERE ReferenceKey = @po AND BranchCode = '888';
        INSERT @r VALUES ('H4-STS-1 full receipt', CASE WHEN @st = 'DELIVERED' AND @n > 0 AND @m = 1 AND ABS(@dr) < 0.01 THEN 'PASS' ELSE 'FAIL' END,
                          CONCAT('PO ', @po, ': ', @st, ', receipt rows ', @n, ', IT-BR tickets ', @m, ', head-office In Transit net ', @dr));
    END TRY BEGIN CATCH INSERT @r VALUES ('H4-STS-1 full receipt', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;

    ------------------------------------------------------------------
    -- H4-STS-2 a failure in the LAST step (confirm: IT-BR-VATEX mapping off): nothing of the receipt remains
    ------------------------------------------------------------------
    BEGIN TRAN;
    BEGIN TRY
        UPDATE JournalEntryMapping SET IsActive = 0 WHERE Mnemonic = 'IT-BR-VATEX';
        EXEC dbo.spu_STS_ReceiveTransfer @PONumber = @po, @BranchCode = @br, @ReceivedBy = 'TEST85', @PreparedBy = 'TEST85', @Lines = @L, @ReturnRows = @RE, @GroupedRows = 1;
        INSERT @r VALUES ('H4-STS-2 confirm fails', 'FAIL', 'no error raised');
    END TRY BEGIN CATCH
        SET @err = ERROR_NUMBER();
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT @n = (SELECT COUNT(*) FROM ReceivedOrderDetails WHERE PONumber = @po) + (SELECT COUNT(*) FROM Inventory WHERE Branch = @br AND Barcode IN (SELECT BarcodeNo FROM DeliveryDetails WHERE PONumber = @po)) + (SELECT COUNT(*) FROM InventoryLedger WHERE Remarks = 'STS RCVD ITEM PO#' + @po);
        SELECT @st = Status FROM DeliverySummary WHERE PONumber = @po;
        INSERT @r VALUES ('H4-STS-2 confirm fails', CASE WHEN @n = 0 AND @st <> 'DELIVERED' AND (SELECT MIN(CAST(IsActive AS INT)) FROM JournalEntryMapping WHERE Mnemonic = 'IT-BR-VATEX') = 1 THEN 'PASS' ELSE 'FAIL' END,
                          CONCAT('error ', @err, '; receipt rows + branch stock + ledger left = ', @n, ', delivery ', @st, ', mapping back on'));
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;

    ------------------------------------------------------------------
    -- H4-STS-3 refusals: stale row 59624, row not on screen 59626, nothing sent 59623, row sent both ways 59627
    ------------------------------------------------------------------
    DECLARE @firstSeq INT = (SELECT MIN(SeqNo) FROM @L), @lastSeq INT = (SELECT MAX(SeqNo) FROM @L);
    DELETE @RR; INSERT @RR VALUES (@dev, @firstSeq, 999);
    DELETE @LE; INSERT @LE SELECT * FROM @L WHERE SeqNo <> @firstSeq;
    BEGIN TRAN;
    BEGIN TRY EXEC dbo.spu_STS_ReceiveTransfer @PONumber = @po, @BranchCode = @br, @ReceivedBy = 'TEST85', @PreparedBy = 'TEST85', @Lines = @LE, @ReturnRows = @RR, @GroupedRows = 1; INSERT @r VALUES ('H4-STS-3a stale row 59624', 'FAIL', 'not refused');
    END TRY BEGIN CATCH INSERT @r VALUES ('H4-STS-3a stale row 59624', CASE WHEN ERROR_NUMBER() = 59624 THEN 'PASS' ELSE 'FAIL' END, CONCAT(ERROR_NUMBER(), ' ', LEFT(ERROR_MESSAGE(), 120))); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    IF @rows >= 2
    BEGIN
        DELETE @RR; DELETE @LE; INSERT @LE SELECT * FROM @L WHERE SeqNo NOT IN (@firstSeq);   -- the first row is neither ticked nor unticked
        BEGIN TRAN;
        BEGIN TRY EXEC dbo.spu_STS_ReceiveTransfer @PONumber = @po, @BranchCode = @br, @ReceivedBy = 'TEST85', @PreparedBy = 'TEST85', @Lines = @LE, @ReturnRows = @RE, @GroupedRows = 1; INSERT @r VALUES ('H4-STS-3b not on screen 59626', 'FAIL', 'not refused');
        END TRY BEGIN CATCH INSERT @r VALUES ('H4-STS-3b not on screen 59626', CASE WHEN ERROR_NUMBER() = 59626 THEN 'PASS' ELSE 'FAIL' END, CONCAT(ERROR_NUMBER(), ' ', LEFT(ERROR_MESSAGE(), 120))); END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
    END
    ELSE INSERT @r VALUES ('H4-STS-3b not on screen 59626', 'SKIP', 'the transfer has one row only');
    DELETE @LE;
    BEGIN TRAN;
    BEGIN TRY EXEC dbo.spu_STS_ReceiveTransfer @PONumber = @po, @BranchCode = @br, @ReceivedBy = 'TEST85', @PreparedBy = 'TEST85', @Lines = @LE, @ReturnRows = @RE, @GroupedRows = 1; INSERT @r VALUES ('H4-STS-3c nothing sent 59623', 'FAIL', 'not refused');
    END TRY BEGIN CATCH INSERT @r VALUES ('H4-STS-3c nothing sent 59623', CASE WHEN ERROR_NUMBER() = 59623 THEN 'PASS' ELSE 'FAIL' END, CONCAT(ERROR_NUMBER(), ' ', LEFT(ERROR_MESSAGE(), 120))); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    DELETE @RR; INSERT @RR VALUES (@dev, @firstSeq, 1);
    BEGIN TRAN;
    BEGIN TRY EXEC dbo.spu_STS_ReceiveTransfer @PONumber = @po, @BranchCode = @br, @ReceivedBy = 'TEST85', @PreparedBy = 'TEST85', @Lines = @L, @ReturnRows = @RR, @GroupedRows = 1; INSERT @r VALUES ('H4-STS-3d both ways 59627', 'FAIL', 'not refused');
    END TRY BEGIN CATCH INSERT @r VALUES ('H4-STS-3d both ways 59627', CASE WHEN ERROR_NUMBER() = 59627 THEN 'PASS' ELSE 'FAIL' END, CONCAT(ERROR_NUMBER(), ' ', LEFT(ERROR_MESSAGE(), 120))); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;

    ------------------------------------------------------------------
    -- H4-STS-4 first row returned, the rest received: stock back at the origin, the rest at the branch, DELIVERED
    ------------------------------------------------------------------
    IF @rows >= 2
    BEGIN
        DELETE @LE; INSERT @LE SELECT * FROM @L WHERE SeqNo <> @firstSeq;
        DELETE @RR; INSERT @RR SELECT DeliveryNo, SeqNo, LineCount FROM dbo.funcview_InventoryDeliveryFIFOForReceivingV2(@po) WHERE SeqNo = @firstSeq;
        DECLARE @srcBefore DECIMAL(18,3) = (SELECT SUM(i.Available) FROM Inventory i WHERE i.SequenceNumber IN (SELECT SequenceReferenceNumber FROM InventoryDeliveryFIFO f JOIN DeliveryDetails dd ON dd.DeliveryNo = f.DeliveryNo AND dd.SeqNo = f.DevDetSeqNo WHERE f.PONumber = @po AND f.isErrorCorrect = 0 AND dd.SeqNo IN (SELECT SeqNo FROM dbo.funcview_STSReceiveLines(@po) WHERE GroupSeqNo = @firstSeq)));
        DECLARE @retQty DECIMAL(18,3) = (SELECT SUM(QtyDelivered) FROM dbo.funcview_STSReceiveLines(@po) WHERE GroupSeqNo = @firstSeq);
        BEGIN TRAN;
        BEGIN TRY
            EXEC dbo.spu_STS_ReceiveTransfer @PONumber = @po, @BranchCode = @br, @ReceivedBy = 'TEST85', @PreparedBy = 'TEST85', @Lines = @LE, @ReturnRows = @RR, @GroupedRows = 1;
            DECLARE @srcAfter DECIMAL(18,3) = (SELECT SUM(i.Available) FROM Inventory i WHERE i.SequenceNumber IN (SELECT SequenceReferenceNumber FROM InventoryDeliveryFIFO f JOIN DeliveryDetails dd ON dd.DeliveryNo = f.DeliveryNo AND dd.SeqNo = f.DevDetSeqNo WHERE f.PONumber = @po AND dd.SeqNo IN (SELECT SeqNo FROM DeliveryDetails WHERE PONumber = @po AND isReturned = 1)));
            SELECT @st = Status FROM DeliverySummary WHERE PONumber = @po;
            SELECT @n = COUNT(*) FROM DeliveryDetails WHERE PONumber = @po AND isReturned = 1;
            SELECT @dr = ISNULL(SUM(Debit) - SUM(Credit), 0) FROM TicketDetails WHERE ReferenceKey = @po AND BranchCode = '888';
            INSERT @r VALUES ('H4-STS-4 partial (1 row returned)', CASE WHEN @st = 'DELIVERED' AND @n >= 1 AND ABS(@dr) < 0.01 AND @srcAfter >= @srcBefore + @retQty - 0.001 THEN 'PASS' ELSE 'FAIL' END,
                              CONCAT(@st, ', lines returned ', @n, ', origin lots ', @srcBefore, ' -> ', @srcAfter, ' (returned ', @retQty, '), HO In Transit net ', @dr));
        END TRY BEGIN CATCH INSERT @r VALUES ('H4-STS-4 partial (1 row returned)', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
    END
    ELSE INSERT @r VALUES ('H4-STS-4 partial (1 row returned)', 'SKIP', 'the transfer has one row only');
END

------------------------------------------------------------------
-- H4-AP-1 combined CHECK voucher (invoice + 1,000 manual line) posts as one; cheque = bank credits; expense paid
------------------------------------------------------------------
DECLARE @IL dbo.AP_PaymentLineTVP, @ML dbo.ManualVoucherDebitLineTVP, @MLbad dbo.ManualVoucherDebitLineTVP, @EX dbo.AP_PaymentLineExtraTVP;
IF @exp IS NULL OR @caAcct IS NULL INSERT @r VALUES ('H4-AP-1 combined voucher', 'SKIP', 'no open single-line expense (or no allowed cash-advance account)');
ELSE
BEGIN
    INSERT @IL VALUES ('888', @inv, @expDate, @exp, @batch, @amt, @amt, 0, 0, 0, 'TEST85', 0, NULL);
    INSERT @ML VALUES ('888', @caAcct, 1000, 'TEST85 manual line');
    INSERT @MLbad VALUES ('888', 'ZZZZZ', 1000, 'TEST85 bad account');
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_PostSupplierPaymentWithManualLines
            @parmrefno = @tref, @parmvoucherid = @tref, @parmsupplierid = @sup, @parmsuppliername = @supName, @parmcheckcoding = 'T85', @parmcheckno = 'T85', @parmcheckdate = @expDate,
            @parmcontrolno = NULL, @parmcheckremarks = 'TEST85', @parmpreparedby = 'TEST85', @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CHECK',
            @parmPayingBranch = '888', @InvoiceLegAmount = @amt, @InvoiceLines = @IL, @ManualLines = @ML, @InvoiceLineExtras = @EX;
        SELECT @dr = Amount FROM CheckVoucher WHERE ReferenceNumber = @tref;
        SELECT @cr = SUM(Credit) FROM TicketDetails WHERE ReferenceNumber = @tref AND AccountCode = @bank;
        SELECT @n = COUNT(*) FROM CashAdvance WHERE ReferenceNo = @tref;
        INSERT @r VALUES ('H4-AP-1 combined voucher', CASE WHEN @dr = @amt + 1000 AND @cr = @amt + 1000 AND @n = 1 AND (SELECT Balance FROM ExpenseSummary WHERE ReferenceNumber = @exp) = 0 THEN 'PASS' ELSE 'FAIL' END,
                          CONCAT('cheque ', @dr, ', bank credits ', @cr, ', cash advance rows ', @n, ', expense balance ', (SELECT Balance FROM ExpenseSummary WHERE ReferenceNumber = @exp)));

        -- H4-AP-2 reverse it as one: voucher voided, expense open again, cash advance REVERSED
        EXEC dbo.sp_ReverseCombinedSupplierVoucher @parmsupplierid = @sup, @parmreferenceno = @tref, @parmvoucherid = @tref, @parmvouchertype = 'EXPENSE', @parmcheckno = 'T85', @parmglcode = NULL, @parmbranch = NULL, @parmreason = 'TEST85', @parmuser = 'TEST85';
        INSERT @r VALUES ('H4-AP-2 combined reversal', CASE WHEN (SELECT isErrorCorrect FROM CheckVoucher WHERE ReferenceNumber = @tref) = 1 AND (SELECT Balance FROM ExpenseSummary WHERE ReferenceNumber = @exp) = @amt AND (SELECT MAX(Status) FROM CashAdvance WHERE ReferenceNo = @tref) = 'REVERSED' THEN 'PASS' ELSE 'FAIL' END,
                          CONCAT('voucher voided ', (SELECT isErrorCorrect FROM CheckVoucher WHERE ReferenceNumber = @tref), ', expense balance ', (SELECT Balance FROM ExpenseSummary WHERE ReferenceNumber = @exp), ', cash advance ', (SELECT MAX(Status) FROM CashAdvance WHERE ReferenceNo = @tref)));
    END TRY BEGIN CATCH INSERT @r VALUES ('H4-AP-1/2 combined voucher', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;

    ------------------------------------------------------------------
    -- H4-AP-3 the manual line fails (account not allowed, 60103): nothing of the invoice leg is posted either
    ------------------------------------------------------------------
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_PostSupplierPaymentWithManualLines
            @parmrefno = @tref, @parmvoucherid = @tref, @parmsupplierid = @sup, @parmsuppliername = @supName, @parmcheckcoding = 'T85', @parmcheckno = 'T85', @parmcheckdate = @expDate,
            @parmcontrolno = NULL, @parmcheckremarks = 'TEST85', @parmpreparedby = 'TEST85', @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CHECK',
            @parmPayingBranch = '888', @InvoiceLegAmount = @amt, @InvoiceLines = @IL, @ManualLines = @MLbad, @InvoiceLineExtras = @EX;
        INSERT @r VALUES ('H4-AP-3 manual line fails 60103', 'FAIL', 'no error raised');
    END TRY BEGIN CATCH
        SET @err = ERROR_NUMBER();
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT @n = (SELECT COUNT(*) FROM APPaymentDetails WHERE ReferenceNumber = @tref) + (SELECT COUNT(*) FROM CheckVoucher WHERE ReferenceNumber = @tref) + (SELECT COUNT(*) FROM TicketMaster WHERE ReferenceNumber = @tref) + (SELECT COUNT(*) FROM CashAdvance WHERE ReferenceNo = @tref);
        INSERT @r VALUES ('H4-AP-3 manual line fails 60103', CASE WHEN @err = 60103 AND @n = 0 AND (SELECT Balance FROM ExpenseSummary WHERE ReferenceNumber = @exp) = @amt THEN 'PASS' ELSE 'FAIL' END,
                          CONCAT('error ', @err, '; rows left for ', @tref, ': ', @n, ', expense balance ', (SELECT Balance FROM ExpenseSummary WHERE ReferenceNumber = @exp), ' (the invoice leg was rolled back with the manual line)'));
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;

    ------------------------------------------------------------------
    -- H4-AP-4 reversal where the manual leg refuses (cash advance partly liquidated, 60302): the invoice leg is not reversed either
    --         (posting + fault + reversal in one transaction; the wrapper's rollback takes all of it back, so nothing of the test is left)
    ------------------------------------------------------------------
    BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_PostSupplierPaymentWithManualLines
            @parmrefno = @tref, @parmvoucherid = @tref, @parmsupplierid = @sup, @parmsuppliername = @supName, @parmcheckcoding = 'T85', @parmcheckno = 'T85', @parmcheckdate = @expDate,
            @parmcontrolno = NULL, @parmcheckremarks = 'TEST85', @parmpreparedby = 'TEST85', @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CHECK',
            @parmPayingBranch = '888', @InvoiceLegAmount = @amt, @InvoiceLines = @IL, @ManualLines = @ML, @InvoiceLineExtras = @EX;
        UPDATE CashAdvance SET Balance = Amount - 1 WHERE ReferenceNo = @tref;
        EXEC dbo.sp_ReverseCombinedSupplierVoucher @parmsupplierid = @sup, @parmreferenceno = @tref, @parmvoucherid = @tref, @parmvouchertype = 'EXPENSE', @parmcheckno = 'T85', @parmglcode = NULL, @parmbranch = NULL, @parmreason = 'TEST85', @parmuser = 'TEST85';
        INSERT @r VALUES ('H4-AP-4 manual leg refuses 60302', 'FAIL', 'no error raised');
    END TRY BEGIN CATCH
        SET @err = ERROR_NUMBER();
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT @n = (SELECT COUNT(*) FROM PaymentReversalAudit WHERE ReferenceNumber = @tref) + (SELECT COUNT(*) FROM TicketMaster WHERE ReferenceNumber = @tref) + (SELECT COUNT(*) FROM CheckVoucher WHERE ReferenceNumber = @tref);
        INSERT @r VALUES ('H4-AP-4 manual leg refuses 60302', CASE WHEN @err = 60302 AND @n = 0 THEN 'PASS' ELSE 'FAIL' END, CONCAT('error ', @err, '; reversal audit + tickets + voucher rows left for ', @tref, ': ', @n));
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
END

------------------------------------------------------------------
-- leftovers
------------------------------------------------------------------
INSERT @r VALUES ('nothing left behind', CASE WHEN @@TRANCOUNT = 0 AND NOT EXISTS (SELECT 1 FROM TicketMaster WHERE EnteredBy = 'TEST85') AND NOT EXISTS (SELECT 1 FROM PaymentHeader WHERE ReversedBy = 'TEST85')
                                                 AND NOT EXISTS (SELECT 1 FROM CheckVoucher WHERE ReferenceNumber = @tref) AND NOT EXISTS (SELECT 1 FROM ReceivedOrderDetails WHERE PONumber = @po AND @po IS NOT NULL AND EXISTS (SELECT 1 FROM DeliverySummary WHERE PONumber = @po AND Status <> 'DELIVERED'))
                                            THEN 'PASS' ELSE 'FAIL' END, 'no TEST85 rows, no open transaction');
SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
