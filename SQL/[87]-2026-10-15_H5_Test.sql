/* ================================================================
   [87] TEST SCRIPT - H5 (settlements checked against the balance read now)
   ================================================================
   Run in SSMS on DEV or STAGING AFTER [87] is applied. Every test runs inside BEGIN TRAN ... ROLLBACK, so nothing is
   left behind; the result set at the end shows PASS / FAIL / BUG SHOWN per test. Do NOT run on PRODUCTION.

   Fixtures are picked automatically (first result set shows them):
     - an open AR invoice (UNPAID, nothing paid, a single row under its invoice no.) whose customer has a ClientAccounts row
     - an open multi-branch expense (MULTI-MANUAL, POSTED, Balance = Amount, no EWT) and its supplier
   If one is missing on the database, its tests show SKIP. The test payment references 99906 / 99907 must be unused.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT OFF;   -- the tests catch the refusals themselves

DECLARE @r TABLE (Seq INT IDENTITY, Test VARCHAR(60), Result VARCHAR(12), Detail VARCHAR(700));
DECLARE @err INT, @n INT, @msg NVARCHAR(500), @d1 DECIMAL(18,2), @d2 DECIMAL(18,2), @s VARCHAR(30);
DECLARE @bank VARCHAR(30) = '101020101', @ar VARCHAR(30) = '101030101', @today DATE = CAST(GETDATE() AS DATE);

------------------------------------------------------------------
-- 0. fixtures
------------------------------------------------------------------
DECLARE @cust CHAR(8), @inv VARCHAR(100), @po VARCHAR(20), @amt DECIMAL(18,2), @invDate DATE;
SELECT TOP (1) @cust = T.CustomerKey, @inv = T.InvoiceNo, @po = T.ReferenceNo, @amt = T.TotalAmount, @invDate = T.TransactionDate
FROM TransactionChargeSales T
WHERE T.PayStatus = 'UNPAID' AND T.TotalAmount > 0 AND T.Balance = T.TotalAmount
  AND ISNULL(T.AmountPaid, 0) = 0 AND ISNULL(T.EWTAmount, 0) = 0 AND ISNULL(T.DiscountAmount, 0) = 0 AND ISNULL(T.OffsetAmount, 0) = 0
  AND (SELECT COUNT(*) FROM TransactionChargeSales x WHERE x.InvoiceNo = T.InvoiceNo) = 1
  AND EXISTS (SELECT 1 FROM ClientAccounts c WHERE c.AccountKey = T.CustomerKey)
ORDER BY T.TransactionDate DESC, T.InvoiceNo;

DECLARE @exp VARCHAR(10), @sup VARCHAR(10), @supName VARCHAR(150), @einv VARCHAR(150), @batch BIGINT, @eamt DECIMAL(18,2), @edate DATE, @ebranch CHAR(3);
SELECT TOP (1) @exp = e.ReferenceNumber, @sup = e.SupplierID, @supName = s.SupplierName, @einv = e.InvoiceNo, @batch = e.BatchReferenceID,
       @eamt = e.Amount, @edate = e.ExpenseDate,
       @ebranch = (SELECT TOP 1 m.BranchCode FROM ExpenseMaster m WHERE m.SupplierID = e.SupplierID AND m.InvoiceNo = e.InvoiceNo AND m.BatchReferenceID = e.BatchReferenceID ORDER BY m.TRN_SEQ_NO)
FROM ExpenseSummary e JOIN Supplier s ON s.SupplierID = e.SupplierID
WHERE e.PostingMode = 'MULTI-MANUAL' AND e.Status = 'POSTED' AND e.Balance = e.Amount AND e.Balance > 0
  AND NOT EXISTS (SELECT 1 FROM ExpenseMaster m WHERE m.ReferenceNumber = e.ReferenceNumber AND ISNULL(m.EWTAmount, 0) <> 0)
  AND (SELECT COUNT(*) FROM ExpenseMaster m WHERE m.ReferenceNumber = e.ReferenceNumber) > 1
ORDER BY e.ReferenceNumber DESC;

DECLARE @ref1 VARCHAR(20) = '99906', @ref2 VARCHAR(20) = '99907';
IF EXISTS (SELECT 1 FROM PaymentHeader WHERE ReferenceNo IN (@ref1, @ref2)) OR EXISTS (SELECT 1 FROM TicketMaster WHERE ReferenceNumber IN (@ref1, @ref2))
   OR EXISTS (SELECT 1 FROM CashVoucher WHERE ReferenceNumber IN (@ref1, @ref2) OR VoucherID IN (99906, 99907))
   OR EXISTS (SELECT 1 FROM CheckVoucher WHERE ReferenceNumber IN (@ref1, @ref2) OR VoucherID IN (99906, 99907))
   OR EXISTS (SELECT 1 FROM TransactionPaymentAP WHERE ReferenceNumber IN (99906, 99907))
BEGIN
    INSERT @r VALUES ('fixtures', 'ERROR', 'test references 99906 / 99907 are in use here; change @ref1 / @ref2');
    SELECT * FROM @r; RETURN;
END
IF EXISTS (SELECT 1 FROM GLPeriodLock WHERE LockedThroughDate >= @today)
BEGIN
    INSERT @r VALUES ('fixtures', 'ERROR', 'the GL is closed through today; the postings would be refused (59900)');
    SELECT * FROM @r; RETURN;
END

SELECT 'fixtures' AS what, @cust AS customer, @inv AS invoice, @po AS po, @amt AS amount, @exp AS expense, @sup AS supplier, @einv AS exp_invoice, @batch AS batch, @eamt AS exp_amount, @ebranch AS first_branch;

------------------------------------------------------------------
-- helpers as inline blocks: an AR payment = header + lines the screen would write
------------------------------------------------------------------
DECLARE @ph TABLE (ID INT);
DECLARE @ph1 INT, @ph2 INT;

------------------------------------------------------------------
-- H5-AR-1 ordinary full payment: OLD and NEW write the same rows; invoice balances = account
------------------------------------------------------------------
IF @cust IS NULL INSERT @r VALUES ('H5-AR-1 full payment old = new', 'SKIP', 'no open single-row AR invoice here');
ELSE
BEGIN
    DECLARE @fp TABLE (Run VARCHAR(3), Item VARCHAR(10), Val VARCHAR(MAX));
    DECLARE @run VARCHAR(3) = 'old';
    WHILE @run IS NOT NULL
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            DELETE @ph;
            INSERT INTO PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
            OUTPUT INSERTED.PaymentHeaderID INTO @ph VALUES (@cust, @ref1, 'TEST87', 'TEST87', 'CASH', @amt, @today, 'TEST87', 'TEST87');
            SELECT @ph1 = ID FROM @ph;
            INSERT INTO ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
            VALUES (@ph1, @cust, @ref1, @po, @inv, @invDate, @amt, 'INVOICE PAYMENT', 'PAYMENT', @bank, @ar, '');
            IF @run = 'old' EXEC dbo.sp_AddPaymentClient_OLD_10152026010000 @PaymentHeaderID = @ph1;
            ELSE            EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @ph1;
            INSERT @fp SELECT @run, 'TCS', CONCAT(AmountPaid, '|', Balance, '|', PayStatus, '|', ISNULL(EWTAmount, 0), '|', ISNULL(DiscountAmount, 0), '|', ISNULL(OffsetAmount, 0)) FROM TransactionChargeSales WHERE InvoiceNo = @inv AND ReferenceNo = @po AND CustomerKey = @cust;
            INSERT @fp SELECT @run, 'TKD', CONCAT(COUNT(*), '|', SUM(td.Debit), '|', SUM(td.Credit), '|', STRING_AGG(CONCAT(td.AccountCode, ':', td.Debit, ':', td.Credit), ',') WITHIN GROUP (ORDER BY td.AccountCode, td.Debit, td.Credit))
                       FROM TicketMaster tm JOIN TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode WHERE tm.ReferenceNumber = @ref1;
            INSERT @fp SELECT @run, 'CL', CONCAT(COUNT(*), '|', STRING_AGG(CONCAT(AccountKey, ':', TransCode, ':', Debit, ':', Credit, ':', InvoiceNo), ',') WITHIN GROUP (ORDER BY AccountKey, TransCode, InvoiceNo, Debit)) FROM ClientLedger WHERE ReferenceNumber = @ref1;
            INSERT @fp SELECT @run, 'DIT', CONCAT(COUNT(*), '|', STRING_AGG(CONCAT(ItemType, ':', AccountCode, ':', Amount, ':', ControlNo), ',') WITHIN GROUP (ORDER BY ItemType)) FROM BankStatementRecon WHERE SourceRef = @ref1;
            INSERT @fp SELECT @run, 'ACCT', CONCAT(c.AccountBalance, '|', (SELECT SUM(Balance) FROM TransactionChargeSales t WHERE t.CustomerKey = c.AccountKey)) FROM ClientAccounts c WHERE c.AccountKey = @cust;
        END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('H5-AR-1 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
    END
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp WHERE Run = 'old' EXCEPT SELECT Item, Val FROM @fp WHERE Run = 'new') x;
    SELECT @s = Val FROM @fp WHERE Run = 'new' AND Item = 'ACCT';
    INSERT @r VALUES ('H5-AR-1 full payment old = new', CASE WHEN @n = 0 AND (SELECT COUNT(*) FROM @fp WHERE Run = 'new') = 5
                                                                  AND (SELECT COUNT(*) FROM @fp WHERE Run = 'new' AND Item = 'ACCT' AND LEFT(Val, CHARINDEX('|', Val) - 1) = SUBSTRING(Val, CHARINDEX('|', Val) + 1, 50)) = 1 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT(@n, ' of 5 footprint rows differ; invoice after: ', (SELECT Val FROM @fp WHERE Run = 'new' AND Item = 'TCS'), '; account|sum of balances: ', @s));
END

------------------------------------------------------------------
-- H5-AR-2 partial payment: OLD and NEW the same (PARTIAL)
------------------------------------------------------------------
IF @cust IS NULL INSERT @r VALUES ('H5-AR-2 partial payment old = new', 'SKIP', '');
ELSE
BEGIN
    DECLARE @fp2 TABLE (Run VARCHAR(3), Item VARCHAR(10), Val VARCHAR(MAX));
    DECLARE @part DECIMAL(18,2) = ROUND(@amt / 3, 2);
    SET @run = 'old';
    WHILE @run IS NOT NULL
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            DELETE @ph;
            INSERT INTO PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
            OUTPUT INSERTED.PaymentHeaderID INTO @ph VALUES (@cust, @ref1, 'TEST87', 'TEST87', 'CASH', @part, @today, 'TEST87', 'TEST87');
            SELECT @ph1 = ID FROM @ph;
            INSERT INTO ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
            VALUES (@ph1, @cust, @ref1, @po, @inv, @invDate, @part, 'INVOICE PAYMENT', 'PAYMENT', @bank, @ar, '');
            IF @run = 'old' EXEC dbo.sp_AddPaymentClient_OLD_10152026010000 @PaymentHeaderID = @ph1;
            ELSE            EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @ph1;
            INSERT @fp2 SELECT @run, 'TCS', CONCAT(AmountPaid, '|', Balance, '|', PayStatus) FROM TransactionChargeSales WHERE InvoiceNo = @inv AND ReferenceNo = @po AND CustomerKey = @cust;
            INSERT @fp2 SELECT @run, 'TKD', CONCAT(COUNT(*), '|', SUM(td.Debit), '|', SUM(td.Credit)) FROM TicketMaster tm JOIN TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode WHERE tm.ReferenceNumber = @ref1;
            INSERT @fp2 SELECT @run, 'CL', CONCAT(COUNT(*), '|', SUM(Debit), '|', SUM(Credit)) FROM ClientLedger WHERE ReferenceNumber = @ref1;
        END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('H5-AR-2 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
    END
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp2 WHERE Run = 'old' EXCEPT SELECT Item, Val FROM @fp2 WHERE Run = 'new') x;
    INSERT @r VALUES ('H5-AR-2 partial payment old = new', CASE WHEN @n = 0 AND (SELECT COUNT(*) FROM @fp2 WHERE Run = 'new') = 3 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT(@part, ' of ', @amt, ': ', @n, ' of 3 footprint rows differ; invoice after: ', (SELECT Val FROM @fp2 WHERE Run = 'new' AND Item = 'TCS')));
END

------------------------------------------------------------------
-- H5-AR-3 stale screen: two payments of the full balance (the second keyed from a grid loaded before the first)
--         OLD: the second posts, invoice negative and FULLYPAID (BUG SHOWN). NEW: refused 92017, nothing posted.
------------------------------------------------------------------
IF @cust IS NULL INSERT @r VALUES ('H5-AR-3a old proc, stale second payment', 'SKIP', '');
ELSE
BEGIN
    SET @run = 'old';
    WHILE @run IS NOT NULL
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            DELETE @ph;
            INSERT INTO PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
            OUTPUT INSERTED.PaymentHeaderID INTO @ph VALUES (@cust, @ref1, 'TEST87', 'TEST87', 'CASH', @amt, @today, 'TEST87', 'TEST87');
            SELECT @ph1 = ID FROM @ph;
            INSERT INTO ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
            VALUES (@ph1, @cust, @ref1, @po, @inv, @invDate, @amt, 'INVOICE PAYMENT', 'PAYMENT', @bank, @ar, '');
            EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @ph1;   -- the first payment settles the invoice (new proc, both runs)
            DELETE @ph;
            INSERT INTO PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
            OUTPUT INSERTED.PaymentHeaderID INTO @ph VALUES (@cust, @ref2, 'TEST87', 'TEST87', 'CASH', @amt, @today, 'TEST87', 'TEST87');
            SELECT @ph2 = ID FROM @ph;
            INSERT INTO ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
            VALUES (@ph2, @cust, @ref2, @po, @inv, @invDate, @amt, 'INVOICE PAYMENT', 'PAYMENT', @bank, @ar, '');
            BEGIN TRY
                IF @run = 'old' EXEC dbo.sp_AddPaymentClient_OLD_10152026010000 @PaymentHeaderID = @ph2;
                ELSE            EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @ph2;
                SELECT @d1 = Balance, @s = PayStatus FROM TransactionChargeSales WHERE InvoiceNo = @inv AND ReferenceNo = @po AND CustomerKey = @cust;
                SELECT @n = COUNT(*) FROM TicketMaster WHERE ReferenceNumber = @ref2;
                IF @run = 'old' INSERT @r VALUES ('H5-AR-3a old proc, stale second payment', CASE WHEN @d1 < 0 AND @n > 0 THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END, CONCAT('the old proc posted it: invoice balance ', @d1, ' ', @s, ', payment ticket rows ', @n));
                ELSE            INSERT @r VALUES ('H5-AR-3b new proc, stale second payment 92017', 'FAIL', CONCAT('not refused: invoice balance ', @d1, ' ', @s));
            END TRY BEGIN CATCH
                SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
                IF @run = 'old' INSERT @r VALUES ('H5-AR-3a old proc, stale second payment', 'UNEXPECTED', CONCAT('refused ', @err, ' ', LEFT(@msg, 150)));
                ELSE
                BEGIN
                    -- nothing of the second payment posted, the first one intact (the proc's CATCH rolled back only its own work? no: the whole
                    -- transaction is doomed by THROW inside the proc's transaction; so check with XACT_STATE)
                    INSERT @r VALUES ('H5-AR-3b new proc, stale second payment 92017', CASE WHEN @err = 92017 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 200), ' | trancount after ', @@TRANCOUNT));
                END
            END CATCH
        END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('H5-AR-3 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
    END
END

------------------------------------------------------------------
-- H5-AR-4 a balance set by hand (off its own columns): OLD silently resets it with the payment (BUG SHOWN); NEW refuses 92016
------------------------------------------------------------------
IF @cust IS NULL INSERT @r VALUES ('H5-AR-4a old proc, hand-set balance', 'SKIP', '');
ELSE
BEGIN
    SET @run = 'old';
    WHILE @run IS NOT NULL
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            UPDATE TransactionChargeSales SET Balance = Balance - 100 WHERE InvoiceNo = @inv AND ReferenceNo = @po AND CustomerKey = @cust;   -- someone "corrected" the balance by hand
            DELETE @ph;
            INSERT INTO PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
            OUTPUT INSERTED.PaymentHeaderID INTO @ph VALUES (@cust, @ref1, 'TEST87', 'TEST87', 'CASH', 50, @today, 'TEST87', 'TEST87');
            SELECT @ph1 = ID FROM @ph;
            INSERT INTO ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
            VALUES (@ph1, @cust, @ref1, @po, @inv, @invDate, 50, 'INVOICE PAYMENT', 'PAYMENT', @bank, @ar, '');
            BEGIN TRY
                IF @run = 'old' EXEC dbo.sp_AddPaymentClient_OLD_10152026010000 @PaymentHeaderID = @ph1;
                ELSE            EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @ph1;
                SELECT @d1 = Balance FROM TransactionChargeSales WHERE InvoiceNo = @inv AND ReferenceNo = @po AND CustomerKey = @cust;
                IF @run = 'old' INSERT @r VALUES ('H5-AR-4a old proc, hand-set balance', CASE WHEN @d1 = @amt - 50 THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END, CONCAT('balance was ', @amt - 100, ' by hand; after paying 50 the old proc made it ', @d1, ' (the hand correction is gone)'));
                ELSE            INSERT @r VALUES ('H5-AR-4b new proc, hand-set balance 92016', 'FAIL', CONCAT('not refused: balance ', @d1));
            END TRY BEGIN CATCH
                SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
                IF @run = 'old' INSERT @r VALUES ('H5-AR-4a old proc, hand-set balance', 'UNEXPECTED', CONCAT('refused ', @err, ' ', LEFT(@msg, 150)));
                ELSE            INSERT @r VALUES ('H5-AR-4b new proc, hand-set balance 92016', CASE WHEN @err = 92016 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 200)));
            END CATCH
        END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('H5-AR-4 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
    END
END

------------------------------------------------------------------
-- H5-AR-5 a line for an invoice the customer doesn't have: OLD records the payment and settles nothing (BUG SHOWN); NEW refuses 92015
------------------------------------------------------------------
IF @cust IS NULL INSERT @r VALUES ('H5-AR-5a old proc, invoice not the customer''s', 'SKIP', '');
ELSE
BEGIN
    SET @run = 'old';
    WHILE @run IS NOT NULL
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            DELETE @ph;
            INSERT INTO PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
            OUTPUT INSERTED.PaymentHeaderID INTO @ph VALUES (@cust, @ref1, 'TEST87', 'TEST87', 'CASH', 100, @today, 'TEST87', 'TEST87');
            SELECT @ph1 = ID FROM @ph;
            INSERT INTO ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
            VALUES (@ph1, @cust, @ref1, @po, 'NOPE-87', @invDate, 100, 'INVOICE PAYMENT', 'PAYMENT', @bank, @ar, '');
            BEGIN TRY
                IF @run = 'old' EXEC dbo.sp_AddPaymentClient_OLD_10152026010000 @PaymentHeaderID = @ph1;
                ELSE            EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @ph1;
                SELECT @n = COUNT(*) FROM TicketMaster WHERE ReferenceNumber = @ref1;
                SELECT @d1 = SUM(Credit) FROM ClientLedger WHERE ReferenceNumber = @ref1;
                SELECT @d2 = SUM(AmountPaid) FROM TransactionChargeSales WHERE CustomerKey = @cust;
                IF @run = 'old' INSERT @r VALUES ('H5-AR-5a old proc, invoice not the customer''s', CASE WHEN @n > 0 THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END, CONCAT('posted: ticket masters ', @n, ', ledger credit ', @d1, ', but no invoice of the customer changed (paid total ', @d2, ')'));
                ELSE            INSERT @r VALUES ('H5-AR-5b new proc, invoice not the customer''s 92015', 'FAIL', 'not refused');
            END TRY BEGIN CATCH
                SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
                IF @run = 'old' INSERT @r VALUES ('H5-AR-5a old proc, invoice not the customer''s', 'UNEXPECTED', CONCAT('refused ', @err, ' ', LEFT(@msg, 150)));
                ELSE            INSERT @r VALUES ('H5-AR-5b new proc, invoice not the customer''s 92015', CASE WHEN @err = 92015 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 200)));
            END CATCH
        END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('H5-AR-5 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
    END
END

------------------------------------------------------------------
-- H5-AP-1 multi-branch expense paid in full (cash voucher): OLD and NEW write the same rows
------------------------------------------------------------------
IF @exp IS NULL INSERT @r VALUES ('H5-AP-1 multi-branch payment old = new', 'SKIP', 'no open multi-branch expense without EWT here');
ELSE
BEGIN
    DECLARE @fp3 TABLE (Run VARCHAR(3), Item VARCHAR(10), Val VARCHAR(MAX));
    SET @run = 'old';
    WHILE @run IS NOT NULL
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            DECLARE @L dbo.AP_PaymentLineTVP, @LE dbo.AP_PaymentLineExtraTVP;
            DELETE @L;
            INSERT INTO @L (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
            VALUES (@ebranch, @einv, @edate, @exp, @batch, @eamt, @eamt, 0, 0, 0, 'TEST87', 0, NULL);
            IF @run = 'old'
                EXEC dbo.sp_AddPaymentSupplierCompound_V2_OLD_10152026010000 @parmrefno = @ref1, @parmvoucherid = @ref1, @parmsupplierid = @sup, @parmsuppliername = @supName,
                     @parmcheckamount = @eamt, @parmcheckcoding = '', @parmcheckno = '', @parmcontrolno = 'TEST87', @parmcheckdate = @today, @parmcheckremarks = 'TEST87',
                     @parmpreparedby = 'TEST87', @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @Lines = @L, @parmPayingBranch = '888', @LineExtras = @LE;
            ELSE
                EXEC dbo.sp_AddPaymentSupplierCompound_V2 @parmrefno = @ref1, @parmvoucherid = @ref1, @parmsupplierid = @sup, @parmsuppliername = @supName,
                     @parmcheckamount = @eamt, @parmcheckcoding = '', @parmcheckno = '', @parmcontrolno = 'TEST87', @parmcheckdate = @today, @parmcheckremarks = 'TEST87',
                     @parmpreparedby = 'TEST87', @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @Lines = @L, @parmPayingBranch = '888', @LineExtras = @LE;
            INSERT @fp3 SELECT @run, 'APD', CONCAT(COUNT(*), '|', SUM(Amount), '|', STRING_AGG(CONCAT(BranchCode, ':', InvoiceNo, ':', Amount, ':', PaymentType), ',') WITHIN GROUP (ORDER BY BranchCode, PaymentType, Amount)) FROM APPaymentDetails WHERE ReferenceNumber = @ref1;
            INSERT @fp3 SELECT @run, 'TKD', CONCAT(COUNT(*), '|', SUM(td.Debit), '|', SUM(td.Credit), '|', STRING_AGG(CONCAT(td.BranchCode, ':', td.AccountCode, ':', td.Debit, ':', td.Credit), ',') WITHIN GROUP (ORDER BY td.BranchCode, td.AccountCode, td.Debit, td.Credit))
                        FROM TicketMaster tm JOIN TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode WHERE tm.ReferenceNumber = @ref1;
            INSERT @fp3 SELECT @run, 'ES', CONCAT(Balance, '|', AmountPaid, '|', Status) FROM ExpenseSummary WHERE ReferenceNumber = @exp;
            INSERT @fp3 SELECT @run, 'EM', STRING_AGG(CONCAT(BranchCode, ':', Balance, ':', AmountPaid, ':', Status), ',') WITHIN GROUP (ORDER BY BranchCode) FROM ExpenseMaster WHERE ReferenceNumber = @exp;
            INSERT @fp3 SELECT @run, 'SL', CONCAT(COUNT(*), '|', SUM(Debit), '|', SUM(Credit)) FROM SupplierLedger WHERE ReferenceNumber = @ref1;
            INSERT @fp3 SELECT @run, 'OC', CONCAT(COUNT(*), '|', SUM(Amount)) FROM BankStatementRecon WHERE ItemType = 'OC' AND (SourceRef = @ref1 OR ReferenceNo = @ref1);
        END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('H5-AP-1 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
    END
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp3 WHERE Run = 'old' EXCEPT SELECT Item, Val FROM @fp3 WHERE Run = 'new') x;
    INSERT @r VALUES ('H5-AP-1 multi-branch payment old = new', CASE WHEN @n = 0 AND (SELECT COUNT(*) FROM @fp3 WHERE Run = 'new') = 6 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('expense ', @exp, ' ', @eamt, ': ', @n, ' of 6 footprint rows differ; legs ', (SELECT Val FROM @fp3 WHERE Run = 'new' AND Item = 'APD'), '; summary ', (SELECT Val FROM @fp3 WHERE Run = 'new' AND Item = 'ES')));
END

------------------------------------------------------------------
-- H5-AP-2 the screen's invoice amount differs from the stored one (expense edited after the list loaded):
--         OLD computes the branch split from the screen's figure (BUG SHOWN); NEW refuses 60525
------------------------------------------------------------------
IF @exp IS NULL INSERT @r VALUES ('H5-AP-2a old proc, stale invoice amount', 'SKIP', '');
ELSE
BEGIN
    SET @run = 'old';
    WHILE @run IS NOT NULL
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            DECLARE @L2 dbo.AP_PaymentLineTVP, @LE2 dbo.AP_PaymentLineExtraTVP;
            DELETE @L2;
            INSERT INTO @L2 (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
            VALUES (@ebranch, @einv, @edate, @exp, @batch, @eamt * 2, @eamt, 0, 0, 0, 'TEST87', 0, NULL);   -- ActualCost = twice the stored amount
            BEGIN TRY
                IF @run = 'old'
                    EXEC dbo.sp_AddPaymentSupplierCompound_V2_OLD_10152026010000 @parmrefno = @ref1, @parmvoucherid = @ref1, @parmsupplierid = @sup, @parmsuppliername = @supName,
                         @parmcheckamount = @eamt, @parmcheckcoding = '', @parmcheckno = '', @parmcontrolno = 'TEST87', @parmcheckdate = @today, @parmcheckremarks = 'TEST87',
                         @parmpreparedby = 'TEST87', @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @Lines = @L2, @parmPayingBranch = '888', @LineExtras = @LE2;
                ELSE
                    EXEC dbo.sp_AddPaymentSupplierCompound_V2 @parmrefno = @ref1, @parmvoucherid = @ref1, @parmsupplierid = @sup, @parmsuppliername = @supName,
                         @parmcheckamount = @eamt, @parmcheckcoding = '', @parmcheckno = '', @parmcontrolno = 'TEST87', @parmcheckdate = @today, @parmcheckremarks = 'TEST87',
                         @parmpreparedby = 'TEST87', @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @Lines = @L2, @parmPayingBranch = '888', @LineExtras = @LE2;
                SELECT @d1 = SUM(Amount), @n = COUNT(*) FROM APPaymentDetails WHERE ReferenceNumber = @ref1;
                SELECT @d2 = SUM(td.Debit) FROM TicketMaster tm JOIN TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode WHERE tm.ReferenceNumber = @ref1;
                IF @run = 'old' INSERT @r VALUES ('H5-AP-2a old proc, stale invoice amount', 'BUG SHOWN', CONCAT('posted with the screen''s amount ', @eamt * 2, ' as the invoice total: ', @n, ' legs = ', @d1, ', ticket DR ', @d2, ' (settled ', @eamt, ')'));
                ELSE            INSERT @r VALUES ('H5-AP-2b new proc, stale invoice amount 60525', 'FAIL', CONCAT('not refused: legs ', @d1));
            END TRY BEGIN CATCH
                SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
                IF @run = 'old' INSERT @r VALUES ('H5-AP-2a old proc, stale invoice amount', CASE WHEN @err <> 60525 THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END, CONCAT('the old proc never saw the stale amount; it failed later on ', @err, ' ', LEFT(@msg, 150)));
                ELSE            INSERT @r VALUES ('H5-AP-2b new proc, stale invoice amount 60525', CASE WHEN @err = 60525 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 200)));
            END CATCH
        END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('H5-AP-2 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
    END
END

------------------------------------------------------------------
-- H5-AP-3 the stored amount wins: the TVP's AmountPaid still bounded by the balance (60504 unchanged), over-settlement refused
------------------------------------------------------------------
IF @exp IS NULL INSERT @r VALUES ('H5-AP-3 over-settlement still 60504', 'SKIP', '');
ELSE
BEGIN
    BEGIN TRAN;
    BEGIN TRY
        DECLARE @L3 dbo.AP_PaymentLineTVP, @LE3 dbo.AP_PaymentLineExtraTVP;
        INSERT INTO @L3 (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
        VALUES (@ebranch, @einv, @edate, @exp, @batch, @eamt, @eamt + 1, 0, 0, 0, 'TEST87', 0, NULL);
        BEGIN TRY
            EXEC dbo.sp_AddPaymentSupplierCompound_V2 @parmrefno = @ref1, @parmvoucherid = @ref1, @parmsupplierid = @sup, @parmsuppliername = @supName,
                 @parmcheckamount = @eamt, @parmcheckcoding = '', @parmcheckno = '', @parmcontrolno = 'TEST87', @parmcheckdate = @today, @parmcheckremarks = 'TEST87',
                 @parmpreparedby = 'TEST87', @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @Lines = @L3, @parmPayingBranch = '888', @LineExtras = @LE3;
            INSERT @r VALUES ('H5-AP-3 over-settlement still 60504', 'FAIL', 'not refused');
        END TRY BEGIN CATCH
            INSERT @r VALUES ('H5-AP-3 over-settlement still 60504', CASE WHEN ERROR_NUMBER() = 60504 THEN 'PASS' ELSE 'FAIL' END, CONCAT(ERROR_NUMBER(), ' ', LEFT(ERROR_MESSAGE(), 200)));
        END CATCH
    END TRY BEGIN CATCH INSERT @r VALUES ('H5-AP-3', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
END

------------------------------------------------------------------
-- H5-AR-6 gross with EWT + DISCOUNT lines (gross = balance): OLD and NEW the same
------------------------------------------------------------------
IF @cust IS NULL INSERT @r VALUES ('H5-AR-6 EWT + discount lines old = new', 'SKIP', '');
ELSE
BEGIN
    DECLARE @fp6 TABLE (Run VARCHAR(3), Item VARCHAR(10), Val VARCHAR(MAX));
    DECLARE @ewt DECIMAL(18,2) = ROUND(@amt * 0.01, 2), @disc DECIMAL(18,2) = 10.00;
    SET @run = 'old';
    WHILE @run IS NOT NULL
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            DELETE @ph;
            INSERT INTO PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
            OUTPUT INSERTED.PaymentHeaderID INTO @ph VALUES (@cust, @ref1, 'TEST87', 'TEST87', 'CASH', @amt - @ewt - @disc, @today, 'TEST87', 'TEST87');
            SELECT @ph1 = ID FROM @ph;
            INSERT INTO ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
            VALUES (@ph1, @cust, @ref1, @po, @inv, @invDate, @amt, 'INVOICE PAYMENT', 'PAYMENT', @bank, @ar, ''),
                   (@ph1, @cust, @ref1, @po, @inv, @invDate, @ewt, 'EWT', 'PAYMENT', @bank, @ar, ''),
                   (@ph1, @cust, @ref1, @po, @inv, @invDate, @disc, 'DISCOUNT', 'PAYMENT', @bank, @ar, '');
            IF @run = 'old' EXEC dbo.sp_AddPaymentClient_OLD_10152026010000 @PaymentHeaderID = @ph1;
            ELSE            EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @ph1;
            INSERT @fp6 SELECT @run, 'TCS', CONCAT(AmountPaid, '|', Balance, '|', PayStatus, '|', ISNULL(EWTAmount, 0), '|', ISNULL(DiscountAmount, 0)) FROM TransactionChargeSales WHERE InvoiceNo = @inv AND ReferenceNo = @po AND CustomerKey = @cust;
            INSERT @fp6 SELECT @run, 'TKD', CONCAT(COUNT(*), '|', SUM(td.Debit), '|', SUM(td.Credit), '|', STRING_AGG(CONCAT(td.AccountCode, ':', td.Debit, ':', td.Credit), ',') WITHIN GROUP (ORDER BY td.AccountCode, td.Debit, td.Credit))
                        FROM TicketMaster tm JOIN TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode WHERE tm.ReferenceNumber = @ref1;
            INSERT @fp6 SELECT @run, 'CL', CONCAT(COUNT(*), '|', SUM(Debit), '|', SUM(Credit)) FROM ClientLedger WHERE ReferenceNumber = @ref1;
        END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('H5-AR-6 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
    END
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp6 WHERE Run = 'old' EXCEPT SELECT Item, Val FROM @fp6 WHERE Run = 'new') x;
    INSERT @r VALUES ('H5-AR-6 EWT + discount lines old = new', CASE WHEN @n = 0 AND (SELECT COUNT(*) FROM @fp6 WHERE Run = 'new') = 3 AND (SELECT Val FROM @fp6 WHERE Run = 'new' AND Item = 'TCS') LIKE '%|0.00|FULLYPAID|%' THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('gross ', @amt, ' EWT ', @ewt, ' discount ', @disc, ': ', @n, ' of 3 differ; invoice after: ', (SELECT Val FROM @fp6 WHERE Run = 'new' AND Item = 'TCS'), '; ticket ', (SELECT Val FROM @fp6 WHERE Run = 'new' AND Item = 'TKD')));
END

------------------------------------------------------------------
-- H5-AR-7 an OVERPAY line (cash above the invoice): OLD and NEW the same
------------------------------------------------------------------
IF @cust IS NULL INSERT @r VALUES ('H5-AR-7 overpay line old = new', 'SKIP', '');
ELSE
BEGIN
    DECLARE @fp7 TABLE (Run VARCHAR(3), Item VARCHAR(10), Val VARCHAR(MAX));
    SET @run = 'old';
    WHILE @run IS NOT NULL
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            DELETE @ph;
            INSERT INTO PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
            OUTPUT INSERTED.PaymentHeaderID INTO @ph VALUES (@cust, @ref1, 'TEST87', 'TEST87', 'CASH', @amt + 100, @today, 'TEST87', 'TEST87');
            SELECT @ph1 = ID FROM @ph;
            INSERT INTO ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
            VALUES (@ph1, @cust, @ref1, @po, @inv, @invDate, @amt, 'INVOICE PAYMENT', 'PAYMENT', @bank, @ar, ''),
                   (@ph1, @cust, @ref1, @po, @inv, @invDate, 100, 'OVERPAY', 'PAYMENT', @bank, @ar, '');
            IF @run = 'old' EXEC dbo.sp_AddPaymentClient_OLD_10152026010000 @PaymentHeaderID = @ph1;
            ELSE            EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @ph1;
            INSERT @fp7 SELECT @run, 'TCS', CONCAT(AmountPaid, '|', Balance, '|', PayStatus, '|', ISNULL(AdvancePayment, 0)) FROM TransactionChargeSales WHERE InvoiceNo = @inv AND ReferenceNo = @po AND CustomerKey = @cust;
            INSERT @fp7 SELECT @run, 'TKD', CONCAT(COUNT(*), '|', SUM(td.Debit), '|', SUM(td.Credit), '|', STRING_AGG(CONCAT(td.AccountCode, ':', td.Debit, ':', td.Credit), ',') WITHIN GROUP (ORDER BY td.AccountCode, td.Debit, td.Credit))
                        FROM TicketMaster tm JOIN TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode WHERE tm.ReferenceNumber = @ref1;
            INSERT @fp7 SELECT @run, 'CL', CONCAT(COUNT(*), '|', SUM(Debit), '|', SUM(Credit)) FROM ClientLedger WHERE ReferenceNumber = @ref1;
        END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('H5-AR-7 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
    END
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp7 WHERE Run = 'old' EXCEPT SELECT Item, Val FROM @fp7 WHERE Run = 'new') x;
    INSERT @r VALUES ('H5-AR-7 overpay line old = new', CASE WHEN @n = 0 AND (SELECT COUNT(*) FROM @fp7 WHERE Run = 'new') = 3 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT(@n, ' of 3 differ; invoice after: ', (SELECT Val FROM @fp7 WHERE Run = 'new' AND Item = 'TCS'), '; ticket ', (SELECT Val FROM @fp7 WHERE Run = 'new' AND Item = 'TKD')));
END

------------------------------------------------------------------
-- H5-AR-8 two INVOICE PAYMENT lines for one invoice that add up to more than its balance: NEW refuses 92017
------------------------------------------------------------------
IF @cust IS NULL INSERT @r VALUES ('H5-AR-8 two lines over the balance 92017', 'SKIP', '');
ELSE
BEGIN
    BEGIN TRAN;
    BEGIN TRY
        DELETE @ph;
        INSERT INTO PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
        OUTPUT INSERTED.PaymentHeaderID INTO @ph VALUES (@cust, @ref1, 'TEST87', 'TEST87', 'CASH', @amt + 1, @today, 'TEST87', 'TEST87');
        SELECT @ph1 = ID FROM @ph;
        INSERT INTO ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
        VALUES (@ph1, @cust, @ref1, @po, @inv, @invDate, @amt - 1, 'INVOICE PAYMENT', 'PAYMENT', @bank, @ar, ''),
               (@ph1, @cust, @ref1, @po, @inv, @invDate, 2, 'INVOICE PAYMENT', 'PAYMENT', @bank, @ar, '');
        BEGIN TRY
            EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @ph1;
            INSERT @r VALUES ('H5-AR-8 two lines over the balance 92017', 'FAIL', 'not refused');
        END TRY BEGIN CATCH
            INSERT @r VALUES ('H5-AR-8 two lines over the balance 92017', CASE WHEN ERROR_NUMBER() = 92017 THEN 'PASS' ELSE 'FAIL' END, CONCAT(ERROR_NUMBER(), ' ', LEFT(ERROR_MESSAGE(), 200)));
        END CATCH
    END TRY BEGIN CATCH INSERT @r VALUES ('H5-AR-8', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
END

------------------------------------------------------------------
-- H5-AR-9 a balance-forward credit ticked with an invoice ([79] shape): OLD and NEW the same; the credit rules still apply
------------------------------------------------------------------
DECLARE @bcust CHAR(8), @binv VARCHAR(100), @bpo VARCHAR(20), @bamt DECIMAL(18,2), @bdate DATE, @cinv VARCHAR(100), @cpo VARCHAR(20), @cbal DECIMAL(18,2), @cdate DATE;
SELECT TOP (1) @bcust = i.CustomerKey, @binv = i.InvoiceNo, @bpo = i.ReferenceNo, @bamt = i.TotalAmount, @bdate = i.TransactionDate,
       @cinv = c.InvoiceNo, @cpo = c.ReferenceNo, @cbal = -c.Balance, @cdate = c.TransactionDate
FROM TransactionChargeSales c
JOIN TransactionChargeSales i ON i.CustomerKey = c.CustomerKey AND i.TotalAmount > 0 AND i.Balance = i.TotalAmount AND i.PayStatus = 'UNPAID' AND ISNULL(i.AmountPaid, 0) = 0
WHERE c.TotalAmount < 0 AND c.Balance < 0 AND c.PayStatus IN ('UNPAID', 'PARTIAL') AND -c.Balance <= i.TotalAmount
  AND (SELECT COUNT(*) FROM TransactionChargeSales x WHERE x.InvoiceNo = i.InvoiceNo) = 1 AND (SELECT COUNT(*) FROM TransactionChargeSales x WHERE x.InvoiceNo = c.InvoiceNo) = 1
ORDER BY i.TransactionDate DESC;
IF @bcust IS NULL INSERT @r VALUES ('H5-AR-9 BF credit + invoice old = new', 'SKIP', 'no customer with an open balance-forward credit and an open invoice here');
ELSE
BEGIN
    DECLARE @fp9 TABLE (Run VARCHAR(3), Item VARCHAR(10), Val VARCHAR(MAX));
    SET @run = 'old';
    WHILE @run IS NOT NULL
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            DELETE @ph;
            INSERT INTO PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
            OUTPUT INSERTED.PaymentHeaderID INTO @ph VALUES (@bcust, @ref1, 'TEST87', 'TEST87', 'CASH', @bamt - @cbal, @today, 'TEST87', 'TEST87');
            SELECT @ph1 = ID FROM @ph;
            INSERT INTO ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
            VALUES (@ph1, @bcust, @ref1, @bpo, @binv, @bdate, @bamt, 'INVOICE PAYMENT', 'PAYMENT', @bank, @ar, ''),
                   (@ph1, @bcust, @ref1, @cpo, @cinv, @cdate, -@cbal, 'INVOICE PAYMENT', 'PAYMENT', @bank, @ar, '');
            IF @run = 'old' EXEC dbo.sp_AddPaymentClient_OLD_10152026010000 @PaymentHeaderID = @ph1;
            ELSE            EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @ph1;
            INSERT @fp9 SELECT @run, 'TCS', STRING_AGG(CONCAT(InvoiceNo, ':', AmountPaid, ':', Balance, ':', PayStatus), ',') WITHIN GROUP (ORDER BY InvoiceNo) FROM TransactionChargeSales WHERE CustomerKey = @bcust AND InvoiceNo IN (@binv, @cinv);
            INSERT @fp9 SELECT @run, 'TKD', CONCAT(COUNT(*), '|', SUM(td.Debit), '|', SUM(td.Credit)) FROM TicketMaster tm JOIN TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode WHERE tm.ReferenceNumber = @ref1;
            INSERT @fp9 SELECT @run, 'CL', CONCAT(COUNT(*), '|', SUM(Debit), '|', SUM(Credit)) FROM ClientLedger WHERE ReferenceNumber = @ref1;
        END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('H5-AR-9 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
    END
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp9 WHERE Run = 'old' EXCEPT SELECT Item, Val FROM @fp9 WHERE Run = 'new') x;
    INSERT @r VALUES ('H5-AR-9 BF credit + invoice old = new', CASE WHEN @n = 0 AND (SELECT COUNT(*) FROM @fp9 WHERE Run = 'new') = 3 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('customer ', @bcust, ' invoice ', @binv, ' ', @bamt, ' + credit ', @cinv, ' ', -@cbal, ': ', @n, ' of 3 differ; rows after: ', (SELECT Val FROM @fp9 WHERE Run = 'new' AND Item = 'TCS'), '; ticket ', (SELECT Val FROM @fp9 WHERE Run = 'new' AND Item = 'TKD')));
END

------------------------------------------------------------------
-- H5-AP-4 a partly paid multi-branch expense (stored Amount <> Balance): the rest is paid with ActualCost = Amount, as the
--         screen sends it, and 60525 does not fire; OLD and NEW the same
------------------------------------------------------------------
IF @exp IS NULL INSERT @r VALUES ('H5-AP-4 partly paid expense, rest old = new', 'SKIP', '');
ELSE
BEGIN
    DECLARE @fp4 TABLE (Run VARCHAR(3), Item VARCHAR(10), Val VARCHAR(MAX));
    DECLARE @half DECIMAL(18,2) = ROUND(@eamt / 2, 2), @rest DECIMAL(18,2) = @eamt - ROUND(@eamt / 2, 2);
    SET @run = 'old';
    WHILE @run IS NOT NULL
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            DECLARE @L4 dbo.AP_PaymentLineTVP, @LE4 dbo.AP_PaymentLineExtraTVP;
            DELETE @L4;
            INSERT INTO @L4 (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
            VALUES (@ebranch, @einv, @edate, @exp, @batch, @eamt, @half, 0, 0, 0, 'TEST87', 0, NULL);
            EXEC dbo.sp_AddPaymentSupplierCompound_V2 @parmrefno = @ref1, @parmvoucherid = @ref1, @parmsupplierid = @sup, @parmsuppliername = @supName,
                 @parmcheckamount = @half, @parmcheckcoding = '', @parmcheckno = '', @parmcontrolno = 'TEST87', @parmcheckdate = @today, @parmcheckremarks = 'TEST87',
                 @parmpreparedby = 'TEST87', @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @Lines = @L4, @parmPayingBranch = '888', @LineExtras = @LE4;
            DELETE @L4;
            INSERT INTO @L4 (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
            VALUES (@ebranch, @einv, @edate, @exp, @batch, @eamt, @eamt - @half, 0, 0, 0, 'TEST87', 0, NULL);   -- ActualCost = the stored Amount, Balance is now Amount - half
            IF @run = 'old'
                EXEC dbo.sp_AddPaymentSupplierCompound_V2_OLD_10152026010000 @parmrefno = @ref2, @parmvoucherid = @ref2, @parmsupplierid = @sup, @parmsuppliername = @supName,
                     @parmcheckamount = @rest, @parmcheckcoding = '', @parmcheckno = '', @parmcontrolno = 'TEST87B', @parmcheckdate = @today, @parmcheckremarks = 'TEST87',
                     @parmpreparedby = 'TEST87', @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @Lines = @L4, @parmPayingBranch = '888', @LineExtras = @LE4;
            ELSE
                EXEC dbo.sp_AddPaymentSupplierCompound_V2 @parmrefno = @ref2, @parmvoucherid = @ref2, @parmsupplierid = @sup, @parmsuppliername = @supName,
                     @parmcheckamount = @rest, @parmcheckcoding = '', @parmcheckno = '', @parmcontrolno = 'TEST87B', @parmcheckdate = @today, @parmcheckremarks = 'TEST87',
                     @parmpreparedby = 'TEST87', @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @Lines = @L4, @parmPayingBranch = '888', @LineExtras = @LE4;
            INSERT @fp4 SELECT @run, 'APD', CONCAT(COUNT(*), '|', SUM(Amount), '|', STRING_AGG(CONCAT(BranchCode, ':', Amount), ',') WITHIN GROUP (ORDER BY BranchCode, Amount)) FROM APPaymentDetails WHERE ReferenceNumber = @ref2;
            INSERT @fp4 SELECT @run, 'TKD', CONCAT(COUNT(*), '|', SUM(td.Debit), '|', SUM(td.Credit)) FROM TicketMaster tm JOIN TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode WHERE tm.ReferenceNumber = @ref2;
            INSERT @fp4 SELECT @run, 'ES', CONCAT(Balance, '|', AmountPaid, '|', Status) FROM ExpenseSummary WHERE ReferenceNumber = @exp;
            INSERT @fp4 SELECT @run, 'EM', STRING_AGG(CONCAT(BranchCode, ':', Balance, ':', AmountPaid, ':', Status), ',') WITHIN GROUP (ORDER BY BranchCode) FROM ExpenseMaster WHERE ReferenceNumber = @exp;
        END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('H5-AP-4 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
    END
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp4 WHERE Run = 'old' EXCEPT SELECT Item, Val FROM @fp4 WHERE Run = 'new') x;
    INSERT @r VALUES ('H5-AP-4 partly paid expense, rest old = new', CASE WHEN @n = 0 AND (SELECT COUNT(*) FROM @fp4 WHERE Run = 'new') = 4 AND (SELECT Val FROM @fp4 WHERE Run = 'new' AND Item = 'ES') LIKE '0.00|%FULLYPAID' THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT('half ', @half, ' then the rest: ', @n, ' of 4 differ; summary after ', (SELECT Val FROM @fp4 WHERE Run = 'new' AND Item = 'ES'), '; legs ', (SELECT Val FROM @fp4 WHERE Run = 'new' AND Item = 'APD')));
END

------------------------------------------------------------------
-- leftovers + results
------------------------------------------------------------------
SELECT @n = (SELECT COUNT(*) FROM PaymentHeader WHERE ReferenceNo IN (@ref1, @ref2)) + (SELECT COUNT(*) FROM TicketMaster WHERE ReferenceNumber IN (@ref1, @ref2))
          + (SELECT COUNT(*) FROM APPaymentDetails WHERE ReferenceNumber IN (@ref1, @ref2)) + (SELECT COUNT(*) FROM CashVoucher WHERE ReferenceNumber IN (@ref1, @ref2))
          + (SELECT COUNT(*) FROM ClientLedger WHERE ReferenceNumber IN (@ref1, @ref2)) + (SELECT COUNT(*) FROM SupplierLedger WHERE ReferenceNumber IN (@ref1, @ref2));
INSERT @r VALUES ('leftovers', CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@n, ' test rows left behind'));

SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
SELECT DB_NAME() AS DatabaseName, SUM(CASE WHEN Result = 'PASS' THEN 1 ELSE 0 END) AS Pass, SUM(CASE WHEN Result = 'BUG SHOWN' THEN 1 ELSE 0 END) AS BugShown,
       SUM(CASE WHEN Result = 'SKIP' THEN 1 ELSE 0 END) AS Skip, SUM(CASE WHEN Result IN ('FAIL', 'ERROR', 'UNEXPECTED') THEN 1 ELSE 0 END) AS Fail FROM @r;
