/* ================================================================
   [88] TEST SCRIPT - H7 (bank reconciliation loopholes)
   ================================================================
   Run in SSMS on DEV or STAGING AFTER [88] is applied. Every test runs inside BEGIN TRAN ... ROLLBACK, so nothing is
   left behind; the result set at the end shows PASS / FAIL / BUG SHOWN per test. Do NOT run on PRODUCTION.
   "BUG SHOWN" = the _OLD_10152026120000 backup of a proc reproduces the fault [88] closes.

   Fixtures are picked automatically (first result set): bank accounts 101020101 / 101020107 (both on the
   cash-advance allowed list), expense account 60339, payable 20103, a supplier, an open AR invoice (as in [87]) and an
   open multi-branch expense (as in [87]). The test references 99911 - 99918 must be unused.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT OFF;   -- the tests catch the refusals themselves

DECLARE @r TABLE (Seq INT IDENTITY, Test VARCHAR(70), Result VARCHAR(12), Detail VARCHAR(900));
DECLARE @err INT, @n INT, @n2 INT, @msg NVARCHAR(600), @d1 DECIMAL(18,2), @d2 DECIMAL(18,2), @s VARCHAR(400), @s2 VARCHAR(400), @id1 INT, @id2 INT, @id3 INT, @hdr INT, @run VARCHAR(3);
DECLARE @bank VARCHAR(20) = '101020101', @bankB VARCHAR(20) = '101020107', @other VARCHAR(20) = '60339', @ap VARCHAR(20) = '20103', @ar VARCHAR(20) = '101030101';
DECLARE @today DATE = CAST(GETDATE() AS DATE), @P DATE = EOMONTH(GETDATE()), @user VARCHAR(50) = 'TEST88', @branch VARCHAR(5) = '888';
DECLARE @far DATE = '2031-01-31', @farDay DATE = '2031-01-15';
DECLARE @other2 VARCHAR(20) = (SELECT TOP 1 AccountCode FROM ChartOfAccounts WHERE AccountCode LIKE '603%' AND AccountCode <> @other ORDER BY AccountCode);
DECLARE @caAcct VARCHAR(20) = (SELECT TOP 1 AccountCode FROM CashAdvanceAllowedAccounts WHERE AccountCode NOT LIKE '10102%' AND LEN(AccountCode) >= 5 ORDER BY AccountCode);
DECLARE @sup VARCHAR(20), @supName VARCHAR(150);
SELECT TOP 1 @sup = SupplierID, @supName = SupplierName FROM Supplier WHERE SupplierID = SupplierKey ORDER BY SupplierID;

------------------------------------------------------------------
-- 0. pre-checks and fixtures
------------------------------------------------------------------
IF CHARINDEX('[88]', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_Payment_PostBankReconEntry'))) = 0
BEGIN INSERT @r VALUES ('fixtures', 'ERROR', '[88] is not applied here'); SELECT * FROM @r; RETURN; END
IF OBJECT_ID('dbo.sp_PostCashAdvance_OLD_10152026120000') IS NULL OR OBJECT_ID('dbo.sp_EditManualJournalVoucher_OLD_10152026120000') IS NULL OR OBJECT_ID('dbo.sp_ReverseCashAdvanceEntry_OLD_10152026120000') IS NULL
BEGIN INSERT @r VALUES ('fixtures', 'ERROR', 'the [88] backups are missing; the BUG SHOWN tests need them'); SELECT * FROM @r; RETURN; END
IF (SELECT COUNT(*) FROM CashAdvanceAllowedAccounts WHERE AccountCode IN (@bank, @bankB)) <> 2 OR @caAcct IS NULL
BEGIN INSERT @r VALUES ('fixtures', 'ERROR', 'bank accounts 101020101 / 101020107 or a non-bank account are not on the cash-advance allowed list'); SELECT * FROM @r; RETURN; END
IF (SELECT COUNT(*) FROM ChartOfAccounts WHERE AccountCode IN (@bank, @bankB, @other, @ap, @ar)) <> 5 OR @other2 IS NULL
BEGIN INSERT @r VALUES ('fixtures', 'ERROR', 'accounts 101020101 / 101020107 / 60339 / 20103 / 101030101 must exist'); SELECT * FROM @r; RETURN; END
IF (SELECT COUNT(*) FROM PaymentHeader WHERE ReferenceNo IN ('99911','99912','99913','99914','99915','99916','99917','99918'))
 + (SELECT COUNT(*) FROM TicketMaster WHERE ReferenceNumber IN ('99911','99912','99913','99914','99915','99916','99917','99918'))
 + (SELECT COUNT(*) FROM CashVoucher WHERE ReferenceNumber IN ('99911','99912','99913','99914','99915','99916','99917','99918') OR VoucherID IN (99911,99912,99913,99914,99915,99916,99917,99918))
 + (SELECT COUNT(*) FROM CheckVoucher WHERE ReferenceNumber IN ('99911','99912','99913','99914','99915','99916','99917','99918') OR VoucherID IN (99911,99912,99913,99914,99915,99916,99917,99918))
 + (SELECT COUNT(*) FROM ManualJournalVoucher WHERE ReferenceNo IN ('99911','99912','99913','99914','99915','99916','99917','99918'))
 + (SELECT COUNT(*) FROM CashAdvance WHERE ReferenceNo IN ('99911','99912','99913','99914','99915','99916','99917','99918') OR VoucherID IN ('99911','99912','99913','99914','99915','99916','99917','99918'))
 + (SELECT COUNT(*) FROM ExpenseSummary WHERE ReferenceNumber IN ('99911','99912','99913','99914','99915','99916','99917','99918') OR InvoiceNo = 'TEST88-INV')
 + (SELECT COUNT(*) FROM BankStatementRecon WHERE ReferenceNo IN ('99911','99912','99913','99914','99915','99916','99917','99918') OR SourceRef IN ('99911','99912','99913','99914','99915','99916','99917','99918')) > 0
BEGIN INSERT @r VALUES ('fixtures', 'ERROR', 'test references 99911 - 99918 (or invoice TEST88-INV) are in use here'); SELECT * FROM @r; RETURN; END
IF EXISTS (SELECT 1 FROM GLPeriodLock WHERE LockedThroughDate >= @today)
BEGIN INSERT @r VALUES ('fixtures', 'ERROR', 'the GL is closed through today; the postings would be refused (59900)'); SELECT * FROM @r; RETURN; END
IF EXISTS (SELECT 1 FROM BankReconHeader WHERE Status = 'LOCKED' AND AccountCode IN (@bank, @bankB) AND PeriodEnd >= @P)
BEGIN INSERT @r VALUES ('fixtures', 'ERROR', 'the current month of 101020101 / 101020107 is already locked here; the open-month tests would be refused'); SELECT * FROM @r; RETURN; END

-- AR fixture (as in [87])
DECLARE @cust CHAR(8), @inv VARCHAR(100), @po VARCHAR(20), @amt DECIMAL(18,2), @invDate DATE;
SELECT TOP (1) @cust = T.CustomerKey, @inv = T.InvoiceNo, @po = T.ReferenceNo, @amt = T.TotalAmount, @invDate = T.TransactionDate
FROM TransactionChargeSales T
WHERE T.PayStatus = 'UNPAID' AND T.TotalAmount > 0 AND T.Balance = T.TotalAmount
  AND ISNULL(T.AmountPaid, 0) = 0 AND ISNULL(T.EWTAmount, 0) = 0 AND ISNULL(T.DiscountAmount, 0) = 0 AND ISNULL(T.OffsetAmount, 0) = 0
  AND (SELECT COUNT(*) FROM TransactionChargeSales x WHERE x.InvoiceNo = T.InvoiceNo) = 1
  AND EXISTS (SELECT 1 FROM ClientAccounts c WHERE c.AccountKey = T.CustomerKey)
ORDER BY T.TransactionDate DESC, T.InvoiceNo;

-- expense fixture (as in [87]) for the combined voucher
DECLARE @exp VARCHAR(10), @esup VARCHAR(10), @esupName VARCHAR(150), @einv VARCHAR(150), @batch BIGINT, @eamt DECIMAL(18,2), @edate DATE, @ebranch CHAR(3);
SELECT TOP (1) @exp = e.ReferenceNumber, @esup = e.SupplierID, @esupName = s.SupplierName, @einv = e.InvoiceNo, @batch = e.BatchReferenceID,
       @eamt = e.Amount, @edate = e.ExpenseDate,
       @ebranch = (SELECT TOP 1 m.BranchCode FROM ExpenseMaster m WHERE m.SupplierID = e.SupplierID AND m.InvoiceNo = e.InvoiceNo AND m.BatchReferenceID = e.BatchReferenceID ORDER BY m.TRN_SEQ_NO)
FROM ExpenseSummary e JOIN Supplier s ON s.SupplierID = e.SupplierID
WHERE e.PostingMode = 'MULTI-MANUAL' AND e.Status = 'POSTED' AND e.Balance = e.Amount AND e.Balance > 0
  AND NOT EXISTS (SELECT 1 FROM ExpenseMaster m WHERE m.ReferenceNumber = e.ReferenceNumber AND ISNULL(m.EWTAmount, 0) <> 0)
  AND (SELECT COUNT(*) FROM ExpenseMaster m WHERE m.ReferenceNumber = e.ReferenceNumber) > 1
ORDER BY e.ReferenceNumber DESC;

SELECT 'fixtures' AS what, @bank AS bank, @bankB AS bankB, @other AS expense_acct, @other2 AS expense_acct2, @caAcct AS ca_acct, @sup AS supplier,
       @cust AS customer, @inv AS invoice, @po AS po, @amt AS amount, @exp AS expense, @esup AS exp_supplier, @einv AS exp_invoice, @eamt AS exp_amount, @ebranch AS first_branch;

DECLARE @JL dbo.JournalVoucherLineTVP_V2, @JLM dbo.JournalVoucherLineMultiTVP_V2, @CL dbo.CashAdvanceLineTVP, @EL dbo.ExpenseManualLineTVP_V2;
DECLARE @ph TABLE (ID INT);
DECLARE @ph1 INT;

------------------------------------------------------------------
-- T01 the helper: the same posting twice = one item
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    EXEC dbo.sp_Payment_PostBankReconEntry @ItemType = 'OC', @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @today, @ReferenceNo = '99911', @ItemDate = @today,
         @Payee = 'TEST88', @Amount = 100.00, @Remarks = 'TEST88', @SourceModule = 'AP-PAYMENT', @SourceRef = '99911', @CreatedBy = @user;
    EXEC dbo.sp_Payment_PostBankReconEntry @ItemType = 'OC', @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @today, @ReferenceNo = '99911', @ItemDate = @today,
         @Payee = 'TEST88', @Amount = 100.00, @Remarks = 'TEST88', @SourceModule = 'AP-PAYMENT', @SourceRef = '99911', @CreatedBy = @user;
    SELECT @n = COUNT(*), @d1 = SUM(Amount), @s = MAX(CONVERT(VARCHAR(10), PeriodEnd, 120)) FROM BankStatementRecon WHERE ReferenceNo = '99911' AND AccountCode = @bank AND ItemType = 'OC';
    INSERT @r VALUES ('T01 helper: same posting twice = one item', CASE WHEN @n = 1 AND @d1 = 100.00 AND @s = CONVERT(VARCHAR(10), @P, 120) THEN 'PASS' ELSE 'FAIL' END, CONCAT(@n, ' item(s), ', @d1, ', period ', @s, ' | trancount ', @@TRANCOUNT));
END TRY BEGIN CATCH INSERT @r VALUES ('T01', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T02 the helper: another amount under the same key is refused 93021 (OLD: silently dropped = BUG SHOWN)
------------------------------------------------------------------
SET @run = 'old';
WHILE @run IS NOT NULL
BEGIN
    BEGIN TRAN;
    BEGIN TRY
        SET @err = NULL; SET @msg = NULL;
        IF @run = 'old'
        BEGIN
            EXEC dbo.sp_Payment_PostBankReconEntry_OLD_10152026120000 @ItemType = 'OC', @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @P, @ReferenceNo = '99911', @ItemDate = @today,
                 @Payee = 'TEST88', @Amount = 100.00, @Remarks = 'TEST88', @SourceModule = 'AP-PAYMENT', @SourceRef = '99911', @CreatedBy = @user;
            EXEC dbo.sp_Payment_PostBankReconEntry_OLD_10152026120000 @ItemType = 'OC', @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @P, @ReferenceNo = '99911', @ItemDate = @today,
                 @Payee = 'TEST88', @Amount = 250.00, @Remarks = 'TEST88', @SourceModule = 'MANUAL-JV', @SourceRef = '99912', @CreatedBy = @user;
            SELECT @n = COUNT(*), @d1 = SUM(Amount) FROM BankStatementRecon WHERE ReferenceNo = '99911' AND AccountCode = @bank AND ItemType = 'OC';
            INSERT @r VALUES ('T02a old helper, second amount under the same key', CASE WHEN @n = 1 AND @d1 = 100.00 THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END, CONCAT('the second posting (250.00, MANUAL-JV 99912) vanished without an error: ', @n, ' item, ', @d1));
        END
        ELSE
        BEGIN
            EXEC dbo.sp_Payment_PostBankReconEntry @ItemType = 'OC', @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @P, @ReferenceNo = '99911', @ItemDate = @today,
                 @Payee = 'TEST88', @Amount = 100.00, @Remarks = 'TEST88', @SourceModule = 'AP-PAYMENT', @SourceRef = '99911', @CreatedBy = @user;
            BEGIN TRY
                EXEC dbo.sp_Payment_PostBankReconEntry @ItemType = 'OC', @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @P, @ReferenceNo = '99911', @ItemDate = @today,
                     @Payee = 'TEST88', @Amount = 250.00, @Remarks = 'TEST88', @SourceModule = 'MANUAL-JV', @SourceRef = '99912', @CreatedBy = @user;
                INSERT @r VALUES ('T02b new helper, second amount under the same key 93021', 'FAIL', 'not refused');
            END TRY BEGIN CATCH
                SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
                INSERT @r VALUES ('T02b new helper, second amount under the same key 93021', CASE WHEN @err = 93021 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 260)));
            END CATCH
        END
    END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('T02 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
END

------------------------------------------------------------------
-- T03 the helper: an item into a LOCKED month is refused 93022
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    SET @hdr = NULL;
    EXEC dbo.sp_BankRecon_GetOrCreateHeader @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @far, @CreatedBy = @user, @HeaderID = @hdr OUTPUT;
    EXEC dbo.sp_BankRecon_LockPeriod @HeaderID = @hdr, @LockedBy = @user, @StrictMode = 0;
    BEGIN TRY
        EXEC dbo.sp_Payment_PostBankReconEntry @ItemType = 'DIT', @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @far, @ReferenceNo = '99911', @ItemDate = @farDay,
             @Payee = 'TEST88', @Amount = 10.00, @Remarks = 'TEST88', @SourceModule = 'AR-PAYMENT', @SourceRef = '99911', @CreatedBy = @user;
        INSERT @r VALUES ('T03 helper into a locked month 93022', 'FAIL', 'not refused');
    END TRY BEGIN CATCH
        SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
        INSERT @r VALUES ('T03 helper into a locked month 93022', CASE WHEN @err = 93022 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 260)));
    END CATCH
END TRY BEGIN CATCH INSERT @r VALUES ('T03', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T04 a Manual JV with two bank lines on one account: one DIT and one OC item
-- T05 edit the bank debit (open item): NEW updates it in place (same ReconID); OLD deletes and re-creates (BUG SHOWN)
------------------------------------------------------------------
SET @run = 'old';
WHILE @run IS NOT NULL
BEGIN
    BEGIN TRAN;
    BEGIN TRY
        DELETE @JL; INSERT @JL ([LineNo], AccountCode, Debit, Credit, Particulars) VALUES (1, @bank, 100, 0, 'TEST88 in'), (2, @bank, 0, 40, 'TEST88 out'), (3, @other, 0, 60, 'TEST88 exp');
        EXEC dbo.sp_PostManualJournalVoucher @parmrefno = '99912', @parmvoucherdate = @today, @parmbranchcode = @branch, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @JL;
        SELECT @n = COUNT(*), @s = STRING_AGG(CONCAT(ItemType, ':', Amount, ':', SourceModule, ':', CONVERT(VARCHAR(10), PeriodEnd, 120)), ',') WITHIN GROUP (ORDER BY ItemType)
        FROM BankStatementRecon WHERE SourceRef = '99912' AND AccountCode = @bank;
        SELECT @id1 = ReconID FROM BankStatementRecon WHERE SourceRef = '99912' AND AccountCode = @bank AND ItemType = 'DIT';
        SELECT @id2 = ReconID FROM BankStatementRecon WHERE SourceRef = '99912' AND AccountCode = @bank AND ItemType = 'OC';
        IF @run = 'new'
            INSERT @r VALUES ('T04 JV post: one DIT + one OC item', CASE WHEN @n = 2 AND @s = CONCAT('DIT:100.00:MANUAL-JV:', CONVERT(VARCHAR(10), @P, 120), ',OC:40.00:MANUAL-JV:', CONVERT(VARCHAR(10), @P, 120)) THEN 'PASS' ELSE 'FAIL' END, @s);

        DELETE @JLM; INSERT @JLM ([LineNo], BranchCode, AccountCode, Debit, Credit, Particulars) VALUES (1, @branch, @bank, 120, 0, 'TEST88 in'), (2, @branch, @bank, 0, 40, 'TEST88 out'), (3, @branch, @other, 0, 80, 'TEST88 exp');
        IF @run = 'old' EXEC dbo.sp_EditManualJournalVoucher_OLD_10152026120000 @parmrefno = '99912', @parmcontrolno = '99912', @parmvoucherdate = @today, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @JLM, @AllowCrossBranch = 0;
        ELSE             EXEC dbo.sp_EditManualJournalVoucher @parmrefno = '99912', @parmcontrolno = '99912', @parmvoucherdate = @today, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @JLM, @AllowCrossBranch = 0;
        SELECT @n = COUNT(*), @s2 = STRING_AGG(CONCAT(ItemType, ':', Amount, ':', CASE WHEN ReconID = @id1 OR ReconID = @id2 THEN 'same id' ELSE 'NEW id' END), ',') WITHIN GROUP (ORDER BY ItemType)
        FROM BankStatementRecon WHERE SourceRef = '99912' AND AccountCode = @bank;
        IF @run = 'old' INSERT @r VALUES ('T05a old edit, open item', CASE WHEN @s2 LIKE '%NEW id%' THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END, CONCAT('the edit deleted and re-created the items: ', @s2));
        ELSE            INSERT @r VALUES ('T05b new edit, open item updated in place', CASE WHEN @n = 2 AND @s2 = 'DIT:120.00:same id,OC:40.00:same id' THEN 'PASS' ELSE 'FAIL' END, @s2);
    END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('T04/T05 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
END

------------------------------------------------------------------
-- T06 the bank item is CLEARED, the edit changes the remarks only: NEW keeps it cleared (same ReconID); OLD reopens it (BUG SHOWN)
------------------------------------------------------------------
SET @run = 'old';
WHILE @run IS NOT NULL
BEGIN
    BEGIN TRAN;
    BEGIN TRY
        DELETE @JL; INSERT @JL ([LineNo], AccountCode, Debit, Credit, Particulars) VALUES (1, @bank, 100, 0, 'TEST88 in'), (2, @other, 0, 100, 'TEST88 exp');
        EXEC dbo.sp_PostManualJournalVoucher @parmrefno = '99917', @parmvoucherdate = @today, @parmbranchcode = @branch, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @JL;
        SELECT @id1 = ReconID FROM BankStatementRecon WHERE SourceRef = '99917' AND AccountCode = @bank AND ItemType = 'DIT';
        EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @id1, @IsResolved = 1, @ResolvedBy = @user, @PeriodEnd = @P;
        DELETE @JLM; INSERT @JLM ([LineNo], BranchCode, AccountCode, Debit, Credit, Particulars) VALUES (1, @branch, @bank, 100, 0, 'TEST88 in'), (2, @branch, @other, 0, 100, 'TEST88 exp');
        IF @run = 'old' EXEC dbo.sp_EditManualJournalVoucher_OLD_10152026120000 @parmrefno = '99917', @parmcontrolno = '99917', @parmvoucherdate = @today, @parmremarks = 'TEST88 edited', @parmuser = @user, @Lines = @JLM, @AllowCrossBranch = 0;
        ELSE             EXEC dbo.sp_EditManualJournalVoucher @parmrefno = '99917', @parmcontrolno = '99917', @parmvoucherdate = @today, @parmremarks = 'TEST88 edited', @parmuser = @user, @Lines = @JLM, @AllowCrossBranch = 0;
        SELECT @n = COUNT(*), @s = STRING_AGG(CONCAT(ItemType, ':', Amount, ':', CASE WHEN IsResolved = 1 THEN 'cleared ' + ISNULL(CONVERT(VARCHAR(10), ClearedPeriodEnd, 120), '') ELSE 'OPEN' END, ':', CASE WHEN ReconID = @id1 THEN 'same id' ELSE 'NEW id' END), ',')
        FROM BankStatementRecon WHERE SourceRef = '99917' AND AccountCode = @bank;
        IF @run = 'old' INSERT @r VALUES ('T06a old edit, cleared item', CASE WHEN @s LIKE '%OPEN:NEW id%' THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END, CONCAT('a remarks-only edit reopened the cleared item: ', @s));
        ELSE            INSERT @r VALUES ('T06b new edit keeps the cleared item', CASE WHEN @n = 1 AND @s = CONCAT('DIT:100.00:cleared ', CONVERT(VARCHAR(10), @P, 120), ':same id') THEN 'PASS' ELSE 'FAIL' END, @s);
    END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('T06 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
END

------------------------------------------------------------------
-- T07 the bank item is CLEARED and the edit changes its amount: refused 93023, nothing saved
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    DELETE @JL; INSERT @JL ([LineNo], AccountCode, Debit, Credit, Particulars) VALUES (1, @bank, 100, 0, 'TEST88 in'), (2, @other, 0, 100, 'TEST88 exp');
    EXEC dbo.sp_PostManualJournalVoucher @parmrefno = '99917', @parmvoucherdate = @today, @parmbranchcode = @branch, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @JL;
    SELECT @id1 = ReconID FROM BankStatementRecon WHERE SourceRef = '99917' AND AccountCode = @bank AND ItemType = 'DIT';
    EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @id1, @IsResolved = 1, @ResolvedBy = @user, @PeriodEnd = @P;
    DELETE @JLM; INSERT @JLM ([LineNo], BranchCode, AccountCode, Debit, Credit, Particulars) VALUES (1, @branch, @bank, 150, 0, 'TEST88 in'), (2, @branch, @other, 0, 150, 'TEST88 exp');
    BEGIN TRY
        EXEC dbo.sp_EditManualJournalVoucher @parmrefno = '99917', @parmcontrolno = '99917', @parmvoucherdate = @today, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @JLM, @AllowCrossBranch = 0;
        INSERT @r VALUES ('T07 edit changes a cleared bank line 93023', 'FAIL', 'not refused');
    END TRY BEGIN CATCH
        SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
        INSERT @r VALUES ('T07 edit changes a cleared bank line 93023', CASE WHEN @err = 93023 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 260), ' | trancount after ', @@TRANCOUNT));
    END CATCH
END TRY BEGIN CATCH INSERT @r VALUES ('T07', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T08 the edit removes the bank line (open item): the item is deleted; a new bank line gets a new item
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    DELETE @JL; INSERT @JL ([LineNo], AccountCode, Debit, Credit, Particulars) VALUES (1, @bank, 100, 0, 'TEST88 in'), (2, @other, 0, 100, 'TEST88 exp');
    EXEC dbo.sp_PostManualJournalVoucher @parmrefno = '99917', @parmvoucherdate = @today, @parmbranchcode = @branch, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @JL;
    DELETE @JLM; INSERT @JLM ([LineNo], BranchCode, AccountCode, Debit, Credit, Particulars) VALUES (1, @branch, @other2, 100, 0, 'TEST88 other'), (2, @branch, @other, 0, 70, 'TEST88 exp'), (3, @branch, @bankB, 0, 30, 'TEST88 out B');
    EXEC dbo.sp_EditManualJournalVoucher @parmrefno = '99917', @parmcontrolno = '99917', @parmvoucherdate = @today, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @JLM, @AllowCrossBranch = 0;
    SELECT @n = COUNT(*), @s = STRING_AGG(CONCAT(AccountCode, ':', ItemType, ':', Amount), ',') WITHIN GROUP (ORDER BY AccountCode) FROM BankStatementRecon WHERE SourceRef = '99917';
    INSERT @r VALUES ('T08 edit removes one bank line, adds another', CASE WHEN @n = 1 AND @s = CONCAT(@bankB, ':OC:30.00') THEN 'PASS' ELSE 'FAIL' END, @s);
END TRY BEGIN CATCH INSERT @r VALUES ('T08', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T09 a cash advance with two debit lines on the same bank account: NEW = one deposit of their sum; OLD = the first line only (BUG SHOWN)
------------------------------------------------------------------
SET @run = 'old';
WHILE @run IS NOT NULL
BEGIN
    BEGIN TRAN;
    BEGIN TRY
        DELETE @CL; INSERT @CL (BranchCode, AccountCode, PayeeName, Amount, Particulars) VALUES (@branch, @bankB, NULL, 60, 'TEST88 a'), (@branch, @bankB, NULL, 40, 'TEST88 b');
        IF @run = 'old' EXEC dbo.sp_PostCashAdvance_OLD_10152026120000 @parmrefno = '99911', @parmvoucherid = '99911', @parmsupplierid = @sup, @parmpayeename = 'TEST88', @parmbranchcode = @branch, @parmcheckcoding = '', @parmcreditaccount = @bank, @parmvouchertype = 'CASH', @parmcheckno = NULL, @parmcheckdate = @today, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @CL, @SkipVoucherInsert = 0;
        ELSE             EXEC dbo.sp_PostCashAdvance @parmrefno = '99911', @parmvoucherid = '99911', @parmsupplierid = @sup, @parmpayeename = 'TEST88', @parmbranchcode = @branch, @parmcheckcoding = '', @parmcreditaccount = @bank, @parmvouchertype = 'CASH', @parmcheckno = NULL, @parmcheckdate = @today, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @CL, @SkipVoucherInsert = 0;
        SELECT @s = STRING_AGG(CONCAT(AccountCode, ':', ItemType, ':', Amount, ':', SourceModule), ',') WITHIN GROUP (ORDER BY ItemType) FROM BankStatementRecon WHERE SourceRef = '99911';
        SELECT @d1 = SUM(td.Debit) FROM TicketMaster tm JOIN TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode WHERE tm.ReferenceNumber = '99911' AND td.AccountCode = @bankB;
        IF @run = 'old' INSERT @r VALUES ('T09a old cash advance, two lines on one bank account', CASE WHEN @s = CONCAT(@bankB, ':DIT:60.00:CASH-ADVANCE,', @bank, ':OC:100.00:CASH-ADVANCE') THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END, CONCAT('GL debit on ', @bankB, ' = ', @d1, ' but the deposit item is only the first line: ', @s));
        ELSE            INSERT @r VALUES ('T09b new cash advance: one deposit = the sum', CASE WHEN @s = CONCAT(@bankB, ':DIT:100.00:CASH-ADVANCE,', @bank, ':OC:100.00:CASH-ADVANCE') AND @d1 = 100.00 THEN 'PASS' ELSE 'FAIL' END, CONCAT('GL debit ', @d1, '; items ', @s));
    END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('T09 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
END

------------------------------------------------------------------
-- T10 a reference collision: JV 99913 has a deposit on bankB; a cash advance with VOUCHER id 99913 also deposits on bankB.
--     OLD: the cash advance posts and its deposit vanishes (BUG SHOWN). NEW: refused 93021, nothing posted.
------------------------------------------------------------------
SET @run = 'old';
WHILE @run IS NOT NULL
BEGIN
    BEGIN TRAN;
    BEGIN TRY
        DELETE @JL; INSERT @JL ([LineNo], AccountCode, Debit, Credit, Particulars) VALUES (1, @bankB, 100, 0, 'TEST88 in B'), (2, @other, 0, 100, 'TEST88 exp');
        EXEC dbo.sp_PostManualJournalVoucher @parmrefno = '99913', @parmvoucherdate = @today, @parmbranchcode = @branch, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @JL;
        DELETE @CL; INSERT @CL (BranchCode, AccountCode, PayeeName, Amount, Particulars) VALUES (@branch, @bankB, NULL, 50, 'TEST88 transfer');
        IF @run = 'old'
        BEGIN
            EXEC dbo.sp_PostCashAdvance_OLD_10152026120000 @parmrefno = '99918', @parmvoucherid = '99913', @parmsupplierid = @sup, @parmpayeename = 'TEST88', @parmbranchcode = @branch, @parmcheckcoding = '', @parmcreditaccount = @bank, @parmvouchertype = 'CASH', @parmcheckno = NULL, @parmcheckdate = @today, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @CL, @SkipVoucherInsert = 0;
            SELECT @n = COUNT(*) FROM CashAdvance WHERE ReferenceNo = '99918';
            SELECT @n2 = COUNT(*) FROM BankStatementRecon WHERE SourceModule = 'CASH-ADVANCE' AND SourceRef = '99918' AND ItemType = 'DIT';
            INSERT @r VALUES ('T10a old: cash advance under a colliding number', CASE WHEN @n > 0 AND @n2 = 0 THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END, CONCAT('cash advance posted (', @n, ' row) but its 50.00 deposit on ', @bankB, ' was dropped (', @n2, ' item): the JV''s item already used the key'));
        END
        ELSE
        BEGIN
            BEGIN TRY
                EXEC dbo.sp_PostCashAdvance @parmrefno = '99918', @parmvoucherid = '99913', @parmsupplierid = @sup, @parmpayeename = 'TEST88', @parmbranchcode = @branch, @parmcheckcoding = '', @parmcreditaccount = @bank, @parmvouchertype = 'CASH', @parmcheckno = NULL, @parmcheckdate = @today, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @CL, @SkipVoucherInsert = 0;
                INSERT @r VALUES ('T10b new: colliding number refused 93021', 'FAIL', 'not refused');
            END TRY BEGIN CATCH
                SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
                INSERT @r VALUES ('T10b new: colliding number refused 93021', CASE WHEN @err = 93021 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 260)));
            END CATCH
        END
    END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('T10 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
END

------------------------------------------------------------------
-- T11 reversing a cash advance voids only its own items: a JV with the same NUMBER and an OC on the same account is left alone
--     (OLD voided the JV's item too = BUG SHOWN)
------------------------------------------------------------------
SET @run = 'old';
WHILE @run IS NOT NULL
BEGIN
    BEGIN TRAN;
    BEGIN TRY
        DELETE @CL; INSERT @CL (BranchCode, AccountCode, PayeeName, Amount, Particulars) VALUES (@branch, @bankB, NULL, 50, 'TEST88 transfer');
        EXEC dbo.sp_PostCashAdvance @parmrefno = '99918', @parmvoucherid = '99913', @parmsupplierid = @sup, @parmpayeename = 'TEST88', @parmbranchcode = @branch, @parmcheckcoding = '', @parmcreditaccount = @bank, @parmvouchertype = 'CASH', @parmcheckno = NULL, @parmcheckdate = @today, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @CL, @SkipVoucherInsert = 0;
        DELETE @JL; INSERT @JL ([LineNo], AccountCode, Debit, Credit, Particulars) VALUES (1, @other, 30, 0, 'TEST88 exp'), (2, @bankB, 0, 30, 'TEST88 out B');
        EXEC dbo.sp_PostManualJournalVoucher @parmrefno = '99913', @parmvoucherdate = @today, @parmbranchcode = @branch, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @JL;
        IF @run = 'old' EXEC dbo.sp_ReverseCashAdvanceEntry_OLD_10152026120000 @parmreferenceno = '99918', @parmreason = 'TEST88', @parmuser = @user;
        ELSE             EXEC dbo.sp_ReverseCashAdvanceEntry @parmreferenceno = '99918', @parmreason = 'TEST88', @parmuser = @user;
        SELECT @s = STRING_AGG(CONCAT(SourceModule, ':', AccountCode, ':', ItemType, ':', CASE WHEN IsResolved = 1 THEN ISNULL(ResolvedReason, 'resolved') ELSE 'OPEN' END), ',') WITHIN GROUP (ORDER BY SourceModule, ItemType)
        FROM BankStatementRecon WHERE ReferenceNo = '99913';
        IF @run = 'old' INSERT @r VALUES ('T11a old reversal voids by number', CASE WHEN @s LIKE '%MANUAL-JV:' + @bankB + ':OC:VOIDED%' THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END, CONCAT('the JV''s own cheque item was voided with the cash advance: ', @s));
        ELSE            INSERT @r VALUES ('T11b new reversal voids its own items only', CASE WHEN @s = CONCAT('CASH-ADVANCE:', @bankB, ':DIT:VOIDED - CASH ADVANCE REVERSED,CASH-ADVANCE:', @bank, ':OC:VOIDED - CASH ADVANCE REVERSED,MANUAL-JV:', @bankB, ':OC:OPEN') THEN 'PASS' ELSE 'FAIL' END, @s);
    END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('T11 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
END

------------------------------------------------------------------
-- T12 reversing a cash advance whose deposit sits in a LOCKED month is refused 93027
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    DELETE @CL; INSERT @CL (BranchCode, AccountCode, PayeeName, Amount, Particulars) VALUES (@branch, @bankB, NULL, 50, 'TEST88 transfer');
    EXEC dbo.sp_PostCashAdvance @parmrefno = '99911', @parmvoucherid = '99911', @parmsupplierid = @sup, @parmpayeename = 'TEST88', @parmbranchcode = @branch, @parmcheckcoding = '', @parmcreditaccount = @bank, @parmvouchertype = 'CASH', @parmcheckno = NULL, @parmcheckdate = @today, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @CL, @SkipVoucherInsert = 0;
    SELECT @hdr = HeaderID FROM BankStatementRecon WHERE SourceModule = 'CASH-ADVANCE' AND SourceRef = '99911' AND ItemType = 'DIT';
    EXEC dbo.sp_BankRecon_LockPeriod @HeaderID = @hdr, @LockedBy = @user, @StrictMode = 0;
    BEGIN TRY
        EXEC dbo.sp_ReverseCashAdvanceEntry @parmreferenceno = '99911', @parmreason = 'TEST88', @parmuser = @user;
        INSERT @r VALUES ('T12 cash advance reversal in a locked month 93027', 'FAIL', 'not refused');
    END TRY BEGIN CATCH
        SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
        INSERT @r VALUES ('T12 cash advance reversal in a locked month 93027', CASE WHEN @err = 93027 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 200)));
    END CATCH
END TRY BEGIN CATCH INSERT @r VALUES ('T12', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T13 Delete: a system item is refused 60005; a manual item of a locked month 93002; a manual open item is deleted
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    DELETE @CL; INSERT @CL (BranchCode, AccountCode, PayeeName, Amount, Particulars) VALUES (@branch, @caAcct, NULL, 25, 'TEST88');
    EXEC dbo.sp_PostCashAdvance @parmrefno = '99911', @parmvoucherid = '99911', @parmsupplierid = @sup, @parmpayeename = 'TEST88', @parmbranchcode = @branch, @parmcheckcoding = '', @parmcreditaccount = @bank, @parmvouchertype = 'CASH', @parmcheckno = NULL, @parmcheckdate = @today, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @CL, @SkipVoucherInsert = 0;
    SELECT @id1 = ReconID FROM BankStatementRecon WHERE SourceModule = 'CASH-ADVANCE' AND SourceRef = '99911' AND ItemType = 'OC';
    BEGIN TRY
        EXEC dbo.sp_BankRecon_DeleteItem @ReconID = @id1, @User = @user;
        INSERT @r VALUES ('T13a delete a system item 60005', 'FAIL', 'not refused');
    END TRY BEGIN CATCH
        SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
        INSERT @r VALUES ('T13a delete a system item 60005', CASE WHEN @err = 60005 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 200)));
    END CATCH
END TRY BEGIN CATCH INSERT @r VALUES ('T13a', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

BEGIN TRAN;
BEGIN TRY
    DECLARE @sv TABLE (ReconID INT, Result VARCHAR(10), Message VARCHAR(200));
    DELETE @sv; INSERT @sv EXEC dbo.sp_BankRecon_SaveItem @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @far, @BankStatementBal = 0, @ItemType = 'OC', @ReferenceNo = 'TEST88-M', @ItemDate = @farDay, @Payee = 'TEST88', @Amount = 12.50, @Remarks = 'TEST88', @User = @user, @ControlNo = NULL;
    SELECT @id1 = ReconID FROM @sv;
    SELECT @hdr = HeaderID FROM BankStatementRecon WHERE ReconID = @id1;
    EXEC dbo.sp_BankRecon_LockPeriod @HeaderID = @hdr, @LockedBy = @user, @StrictMode = 0;
    BEGIN TRY
        EXEC dbo.sp_BankRecon_DeleteItem @ReconID = @id1, @User = @user;
        INSERT @r VALUES ('T13b delete a manual item of a locked month 93002', 'FAIL', 'not refused');
    END TRY BEGIN CATCH
        SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
        INSERT @r VALUES ('T13b delete a manual item of a locked month 93002', CASE WHEN @err = 93002 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 200)));
    END CATCH
END TRY BEGIN CATCH INSERT @r VALUES ('T13b', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

BEGIN TRAN;
BEGIN TRY
    DELETE @sv; INSERT @sv EXEC dbo.sp_BankRecon_SaveItem @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @today, @BankStatementBal = 0, @ItemType = 'DIT', @ReferenceNo = 'TEST88-M', @ItemDate = @today, @Payee = 'TEST88', @Amount = 12.50, @Remarks = 'TEST88', @User = @user, @ControlNo = NULL;
    SELECT @id1 = ReconID FROM @sv;
    EXEC dbo.sp_BankRecon_DeleteItem @ReconID = @id1, @User = @user;
    SELECT @n = COUNT(*) FROM BankStatementRecon WHERE ReconID = @id1;
    INSERT @r VALUES ('T13c delete a manual open item', CASE WHEN @n = 0 AND @id1 IS NOT NULL THEN 'PASS' ELSE 'FAIL' END, CONCAT('item ', @id1, ' rows left ', @n));
END TRY BEGIN CATCH INSERT @r VALUES ('T13c', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T14 Add a manual item into a locked month: refused 93002.  T15 Auto-Match: disabled 93020
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    SET @hdr = NULL;
    EXEC dbo.sp_BankRecon_GetOrCreateHeader @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @far, @CreatedBy = @user, @HeaderID = @hdr OUTPUT;
    EXEC dbo.sp_BankRecon_LockPeriod @HeaderID = @hdr, @LockedBy = @user, @StrictMode = 0;
    BEGIN TRY
        EXEC dbo.sp_BankRecon_SaveItem @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @far, @BankStatementBal = 0, @ItemType = 'OC', @ReferenceNo = 'TEST88-M', @ItemDate = @farDay, @Payee = 'TEST88', @Amount = 12.50, @Remarks = 'TEST88', @User = @user, @ControlNo = NULL;   -- not INSERT ... EXEC: a refusal rolls back (3915)
        INSERT @r VALUES ('T14 add a manual item into a locked month 93002', 'FAIL', 'not refused');
    END TRY BEGIN CATCH
        SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
        INSERT @r VALUES ('T14 add a manual item into a locked month 93002', CASE WHEN @err = 93002 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 200)));
    END CATCH
END TRY BEGIN CATCH INSERT @r VALUES ('T14', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

BEGIN TRAN;
BEGIN TRY
    BEGIN TRY
        EXEC dbo.sp_BankRecon_AutoMatch @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @P, @User = @user;
        INSERT @r VALUES ('T15 Auto-Match disabled 93020', 'FAIL', 'it ran');
    END TRY BEGIN CATCH
        SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
        INSERT @r VALUES ('T15 Auto-Match disabled 93020', CASE WHEN @err = 93020 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 200)));
    END CATCH
END TRY BEGIN CATCH INSERT @r VALUES ('T15', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T16 AR payment: a deposit into a locked month is refused 93022; reversing a payment whose deposit is in a locked month 93028;
--     an ordinary payment still posts its deposit as before
------------------------------------------------------------------
IF @cust IS NULL INSERT @r VALUES ('T16 AR payment lock rules', 'SKIP', 'no open single-row AR invoice here');
ELSE
BEGIN
    BEGIN TRAN;
    BEGIN TRY
        SET @hdr = NULL;
        EXEC dbo.sp_BankRecon_GetOrCreateHeader @BranchCode = '888', @AccountCode = @bank, @PeriodEnd = @P, @CreatedBy = @user, @HeaderID = @hdr OUTPUT;
        EXEC dbo.sp_BankRecon_LockPeriod @HeaderID = @hdr, @LockedBy = @user, @StrictMode = 0;
        DELETE @ph;
        INSERT INTO PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
        OUTPUT INSERTED.PaymentHeaderID INTO @ph VALUES (@cust, '99914', 'TEST88', 'TEST88', 'CASH', @amt, @today, 'TEST88', @user);
        SELECT @ph1 = ID FROM @ph;
        INSERT INTO ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
        VALUES (@ph1, @cust, '99914', @po, @inv, @invDate, @amt, 'INVOICE PAYMENT', 'PAYMENT', @bank, @ar, '');
        BEGIN TRY
            EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @ph1;
            INSERT @r VALUES ('T16a AR payment into a locked month 93022', 'FAIL', 'not refused');
        END TRY BEGIN CATCH
            SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
            INSERT @r VALUES ('T16a AR payment into a locked month 93022', CASE WHEN @err = 93022 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 220), ' | trancount after ', @@TRANCOUNT));
        END CATCH
    END TRY BEGIN CATCH INSERT @r VALUES ('T16a', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;

    BEGIN TRAN;
    BEGIN TRY
        DELETE @ph;
        INSERT INTO PaymentHeader (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType, TotalAmount, PaymentDate, Remarks, CreatedBy)
        OUTPUT INSERTED.PaymentHeaderID INTO @ph VALUES (@cust, '99914', 'TEST88', 'TEST88', 'CASH', @amt, @today, 'TEST88', @user);
        SELECT @ph1 = ID FROM @ph;
        INSERT INTO ARPaymentDetails (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo, InvoiceDate, Amount, PaymentType, PaymentMethod, DebitGLCode, CreditGLCode, TicketNumber)
        VALUES (@ph1, @cust, '99914', @po, @inv, @invDate, @amt, 'INVOICE PAYMENT', 'PAYMENT', @bank, @ar, '');
        EXEC dbo.sp_AddPaymentClient @PaymentHeaderID = @ph1;
        SELECT @n = COUNT(*), @d1 = SUM(Amount), @s = MAX(CONCAT(ItemType, ':', SourceModule, ':', ControlNo, ':', CONVERT(VARCHAR(10), PeriodEnd, 120))), @hdr = MAX(HeaderID) FROM BankStatementRecon WHERE SourceRef = '99914';
        INSERT @r VALUES ('T16b AR payment posts its deposit as before', CASE WHEN @n = 1 AND @d1 = @amt AND @s = CONCAT('DIT:AR-PAYMENT:TEST88:', CONVERT(VARCHAR(10), @P, 120)) THEN 'PASS' ELSE 'FAIL' END, CONCAT(@n, ' item ', @d1, ' ', @s));
        EXEC dbo.sp_BankRecon_LockPeriod @HeaderID = @hdr, @LockedBy = @user, @StrictMode = 0;
        BEGIN TRY
            EXEC dbo.sp_ReversePaymentClient @PaymentHeaderID = @ph1, @ReversedBy = @user;
            INSERT @r VALUES ('T16c AR reversal with the deposit in a locked month 93028', 'FAIL', 'not refused');
        END TRY BEGIN CATCH
            SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
            INSERT @r VALUES ('T16c AR reversal with the deposit in a locked month 93028', CASE WHEN @err = 93028 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 200)));
        END CATCH
    END TRY BEGIN CATCH INSERT @r VALUES ('T16b/c', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
END

------------------------------------------------------------------
-- T17 combined voucher (invoice lines + manual lines): ONE cheque item = the combined total
------------------------------------------------------------------
IF @exp IS NULL INSERT @r VALUES ('T17 combined voucher: one item = combined total', 'SKIP', 'no open multi-branch expense without EWT here');
ELSE
BEGIN
    BEGIN TRAN;
    BEGIN TRY
        DECLARE @IL dbo.AP_PaymentLineTVP, @IE dbo.AP_PaymentLineExtraTVP, @ML dbo.ManualVoucherDebitLineTVP;
        DELETE @IL; DELETE @ML;
        INSERT INTO @IL (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
        VALUES (@ebranch, @einv, @edate, @exp, @batch, @eamt, @eamt, 0, 0, 0, 'TEST88', 0, NULL);
        INSERT INTO @ML (BranchCode, AccountCode, Amount, Particulars) VALUES (@branch, @caAcct, 500.00, 'TEST88 manual');
        EXEC dbo.sp_PostSupplierPaymentWithManualLines @parmrefno = '99916', @parmvoucherid = '99916', @parmsupplierid = @esup, @parmsuppliername = @esupName,
             @parmcheckcoding = '', @parmcheckno = NULL, @parmcheckdate = @today, @parmcontrolno = 'TEST88', @parmcheckremarks = 'TEST88', @parmpreparedby = @user,
             @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @parmPayingBranch = '888',
             @InvoiceLegAmount = @eamt, @InvoiceLines = @IL, @ManualLines = @ML, @InvoiceLineExtras = @IE;
        SELECT @n = COUNT(*), @d1 = SUM(Amount), @s = STRING_AGG(CONCAT(SourceModule, ':', SourceRef, ':', ItemType), ',') FROM BankStatementRecon WHERE ReferenceNo = '99916' AND AccountCode = @bank;
        SELECT @d2 = Amount FROM CashVoucher WHERE VoucherID = 99916;
        INSERT @r VALUES ('T17 combined voucher: one item = combined total', CASE WHEN @n = 1 AND @d1 = @eamt + 500.00 AND @d2 = @eamt + 500.00 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@n, ' item ', @d1, ' (', @s, '); voucher ', @d2, '; expected ', @eamt + 500.00));
    END TRY BEGIN CATCH INSERT @r VALUES ('T17', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
END

------------------------------------------------------------------
-- T18 a multi-branch expense with a bank credit line gets a cheque item (OLD helper: none = BUG SHOWN); its edit updates the item in place
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    DELETE @EL; INSERT @EL ([LineNo], BranchCode, AccountCode, Debit, Credit, Particulars) VALUES (1, @branch, @other, 100, 0, 'TEST88 exp'), (2, @branch, @bank, 0, 60, 'TEST88 paid'), (3, @branch, @ap, 0, 40, 'TEST88 payable');
    EXEC dbo.sp_PostExpenseManualMultiBranch @parmrefno = '99915', @parminvoiceno = 'TEST88-INV', @parmsupplierid = @sup, @parmexpensedate = @today, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @EL, @AllowCrossBranch = 0;
    SELECT @n = COUNT(*), @s = STRING_AGG(CONCAT(SourceModule, ':', AccountCode, ':', ItemType, ':', Amount), ',') FROM BankStatementRecon WHERE SourceRef = '99915';
    SELECT @id1 = ReconID FROM BankStatementRecon WHERE SourceRef = '99915' AND ItemType = 'OC';
    INSERT @r VALUES ('T18a multi-branch expense with a bank line gets its item', CASE WHEN @n = 1 AND @s = CONCAT('MANUAL-EXP:', @bank, ':OC:60.00') THEN 'PASS' ELSE 'FAIL' END, @s);
    -- the old helper on the same posting: nothing (it read ManualJournalVoucher only)
    DELETE FROM BankStatementRecon WHERE SourceRef = '99915';   -- test only: back to the pre-[88] state
    EXEC dbo.sp_JV_PostBankReconForLines_OLD_10152026120000 @ReferenceNo = '99915', @VoucherDate = @today, @DefaultBranch = NULL, @CreatedBy = @user;
    SELECT @n2 = COUNT(*) FROM BankStatementRecon WHERE SourceRef = '99915';
    INSERT @r VALUES ('T18b old helper on the expense', CASE WHEN @n2 = 0 THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END, CONCAT('the bank credit of 60.00 got no item to tick (', @n2, ' items)'));
    -- back to the [88] state, then edit: bank 60 -> 70
    EXEC dbo.sp_JV_PostBankReconForLines @ReferenceNo = '99915', @VoucherDate = @today, @DefaultBranch = NULL, @CreatedBy = @user;
    SELECT @id1 = ReconID FROM BankStatementRecon WHERE SourceRef = '99915' AND ItemType = 'OC';
    DELETE @EL; INSERT @EL ([LineNo], BranchCode, AccountCode, Debit, Credit, Particulars) VALUES (1, @branch, @other, 100, 0, 'TEST88 exp'), (2, @branch, @bank, 0, 70, 'TEST88 paid'), (3, @branch, @ap, 0, 30, 'TEST88 payable');
    EXEC dbo.sp_EditExpenseManualMultiBranch @parmrefno = '99915', @parmoldinvoiceno = 'TEST88-INV', @parmoldsupplierid = @sup, @parminvoiceno = 'TEST88-INV', @parmsupplierid = @sup, @parmexpensedate = @today, @parmremarks = 'TEST88 edited', @parmuser = @user, @Lines = @EL, @AllowCrossBranch = 0;
    SELECT @n = COUNT(*), @s = STRING_AGG(CONCAT(SourceModule, ':', AccountCode, ':', ItemType, ':', Amount, ':', CASE WHEN ReconID = @id1 THEN 'same id' ELSE 'NEW id' END), ',') FROM BankStatementRecon WHERE SourceRef = '99915';
    INSERT @r VALUES ('T18c expense edit updates the item in place', CASE WHEN @n = 1 AND @s = CONCAT('MANUAL-EXP:', @bank, ':OC:70.00:same id') THEN 'PASS' ELSE 'FAIL' END, @s);
END TRY BEGIN CATCH INSERT @r VALUES ('T18', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T19 UpdateItem: a cleared item's amount cannot change 93024; its payee can
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    DELETE @sv; INSERT @sv EXEC dbo.sp_BankRecon_SaveItem @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @today, @BankStatementBal = 0, @ItemType = 'DIT', @ReferenceNo = 'TEST88-M', @ItemDate = @today, @Payee = 'TEST88', @Amount = 12.50, @Remarks = 'TEST88', @User = @user, @ControlNo = NULL;
    SELECT @id1 = ReconID FROM @sv;
    EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @id1, @IsResolved = 1, @ResolvedBy = @user, @PeriodEnd = @P;
    DECLARE @uv TABLE (Result VARCHAR(10), Message VARCHAR(200));
    INSERT @uv EXEC dbo.sp_BankRecon_UpdateItem @ReconID = @id1, @Payee = 'TEST88 payee', @User = @user;
    SELECT @s = Payee FROM BankStatementRecon WHERE ReconID = @id1;
    BEGIN TRY
        EXEC dbo.sp_BankRecon_UpdateItem @ReconID = @id1, @Amount = 99.00, @User = @user;   -- not INSERT ... EXEC: a refusal rolls back (3915)
        INSERT @r VALUES ('T19 update a cleared item: payee ok, amount refused 93024', 'FAIL', 'the amount change was not refused');
    END TRY BEGIN CATCH
        SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
        INSERT @r VALUES ('T19 update a cleared item: payee ok, amount refused 93024', CASE WHEN @err = 93024 AND @s = 'TEST88 payee' THEN 'PASS' ELSE 'FAIL' END, CONCAT('payee now ''', @s, '''; ', @err, ' ', LEFT(@msg, 160)));
    END CATCH
END TRY BEGIN CATCH INSERT @r VALUES ('T19', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T20 a LOCKED month AFTER the item's month: open items carry forward into it, so a new / changed / deleted / voided item
--     in the earlier month is refused too (helper 93022, Add 93002, Delete 93002, JV edit 93022, cash-advance reversal 93027)
------------------------------------------------------------------
DECLARE @m1 DATE = '2030-12-15', @m1End DATE = '2030-12-31', @m2End DATE = '2031-01-31';
BEGIN TRAN;
BEGIN TRY
    SET @hdr = NULL;
    EXEC dbo.sp_BankRecon_GetOrCreateHeader @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @m2End, @CreatedBy = @user, @HeaderID = @hdr OUTPUT;
    EXEC dbo.sp_BankRecon_LockPeriod @HeaderID = @hdr, @LockedBy = @user, @StrictMode = 0;
    BEGIN TRY
        EXEC dbo.sp_Payment_PostBankReconEntry @ItemType = 'DIT', @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @m1End, @ReferenceNo = '99911', @ItemDate = @m1,
             @Payee = 'TEST88', @Amount = 10.00, @Remarks = 'TEST88', @SourceModule = 'AR-PAYMENT', @SourceRef = '99911', @CreatedBy = @user;
        INSERT @r VALUES ('T20a helper: item in a month before a locked month 93022', 'FAIL', 'not refused');
    END TRY BEGIN CATCH
        SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
        INSERT @r VALUES ('T20a helper: item in a month before a locked month 93022', CASE WHEN @err = 93022 AND @msg LIKE '%2031-01-31%' THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 240)));
    END CATCH
END TRY BEGIN CATCH INSERT @r VALUES ('T20a', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

BEGIN TRAN;
BEGIN TRY
    SET @hdr = NULL;
    EXEC dbo.sp_BankRecon_GetOrCreateHeader @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @m2End, @CreatedBy = @user, @HeaderID = @hdr OUTPUT;
    EXEC dbo.sp_BankRecon_LockPeriod @HeaderID = @hdr, @LockedBy = @user, @StrictMode = 0;
    BEGIN TRY
        EXEC dbo.sp_BankRecon_SaveItem @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @m1End, @BankStatementBal = 0, @ItemType = 'OC', @ReferenceNo = 'TEST88-M', @ItemDate = @m1, @Payee = 'TEST88', @Amount = 12.50, @Remarks = 'TEST88', @User = @user, @ControlNo = NULL;
        INSERT @r VALUES ('T20b add a manual item before a locked month 93002', 'FAIL', 'not refused');
    END TRY BEGIN CATCH
        SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
        INSERT @r VALUES ('T20b add a manual item before a locked month 93002', CASE WHEN @err = 93002 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 200)));
    END CATCH
END TRY BEGIN CATCH INSERT @r VALUES ('T20b', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

BEGIN TRAN;
BEGIN TRY
    DELETE @sv; INSERT @sv EXEC dbo.sp_BankRecon_SaveItem @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @m1End, @BankStatementBal = 0, @ItemType = 'OC', @ReferenceNo = 'TEST88-M', @ItemDate = @m1, @Payee = 'TEST88', @Amount = 12.50, @Remarks = 'TEST88', @User = @user, @ControlNo = NULL;
    SELECT @id1 = ReconID FROM @sv;
    SET @hdr = NULL;
    EXEC dbo.sp_BankRecon_GetOrCreateHeader @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @m2End, @CreatedBy = @user, @HeaderID = @hdr OUTPUT;
    EXEC dbo.sp_BankRecon_LockPeriod @HeaderID = @hdr, @LockedBy = @user, @StrictMode = 0;
    BEGIN TRY
        EXEC dbo.sp_BankRecon_DeleteItem @ReconID = @id1, @User = @user;
        INSERT @r VALUES ('T20c delete a manual item before a locked month 93002', 'FAIL', 'not refused');
    END TRY BEGIN CATCH
        SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
        INSERT @r VALUES ('T20c delete a manual item before a locked month 93002', CASE WHEN @err = 93002 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 200)));
    END CATCH
END TRY BEGIN CATCH INSERT @r VALUES ('T20c', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

BEGIN TRAN;
BEGIN TRY
    DELETE @JL; INSERT @JL ([LineNo], AccountCode, Debit, Credit, Particulars) VALUES (1, @bank, 100, 0, 'TEST88 in'), (2, @other, 0, 100, 'TEST88 exp');
    EXEC dbo.sp_PostManualJournalVoucher @parmrefno = '99917', @parmvoucherdate = @m1, @parmbranchcode = @branch, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @JL;
    SET @hdr = NULL;
    EXEC dbo.sp_BankRecon_GetOrCreateHeader @BranchCode = @branch, @AccountCode = @bank, @PeriodEnd = @m2End, @CreatedBy = @user, @HeaderID = @hdr OUTPUT;
    EXEC dbo.sp_BankRecon_LockPeriod @HeaderID = @hdr, @LockedBy = @user, @StrictMode = 0;
    DELETE @JLM; INSERT @JLM ([LineNo], BranchCode, AccountCode, Debit, Credit, Particulars) VALUES (1, @branch, @bank, 150, 0, 'TEST88 in'), (2, @branch, @other, 0, 150, 'TEST88 exp');
    BEGIN TRY
        EXEC dbo.sp_EditManualJournalVoucher @parmrefno = '99917', @parmcontrolno = '99917', @parmvoucherdate = @m1, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @JLM, @AllowCrossBranch = 0;
        INSERT @r VALUES ('T20d JV edit with its open item before a locked month 93022', 'FAIL', 'not refused');
    END TRY BEGIN CATCH
        SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
        INSERT @r VALUES ('T20d JV edit with its open item before a locked month 93022', CASE WHEN @err = 93022 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 240)));
    END CATCH
END TRY BEGIN CATCH INSERT @r VALUES ('T20d', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

BEGIN TRAN;
BEGIN TRY
    DELETE @CL; INSERT @CL (BranchCode, AccountCode, PayeeName, Amount, Particulars) VALUES (@branch, @bankB, NULL, 50, 'TEST88 transfer');
    EXEC dbo.sp_PostCashAdvance @parmrefno = '99911', @parmvoucherid = '99911', @parmsupplierid = @sup, @parmpayeename = 'TEST88', @parmbranchcode = @branch, @parmcheckcoding = '', @parmcreditaccount = @bank, @parmvouchertype = 'CASH', @parmcheckno = NULL, @parmcheckdate = @m1, @parmremarks = 'TEST88', @parmuser = @user, @Lines = @CL, @SkipVoucherInsert = 0;
    SET @hdr = NULL;
    EXEC dbo.sp_BankRecon_GetOrCreateHeader @BranchCode = @branch, @AccountCode = @bankB, @PeriodEnd = @m2End, @CreatedBy = @user, @HeaderID = @hdr OUTPUT;
    EXEC dbo.sp_BankRecon_LockPeriod @HeaderID = @hdr, @LockedBy = @user, @StrictMode = 0;
    BEGIN TRY
        EXEC dbo.sp_ReverseCashAdvanceEntry @parmreferenceno = '99911', @parmreason = 'TEST88', @parmuser = @user;
        INSERT @r VALUES ('T20e cash advance reversal, deposit before a locked month 93027', 'FAIL', 'not refused');
    END TRY BEGIN CATCH
        SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
        INSERT @r VALUES ('T20e cash advance reversal, deposit before a locked month 93027', CASE WHEN @err = 93027 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@err, ' ', LEFT(@msg, 200)));
    END CATCH
END TRY BEGIN CATCH INSERT @r VALUES ('T20e', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T21 combined voucher whose invoice leg leaves no cash (settled by EWT): the cheque item is created for the manual lines
------------------------------------------------------------------
IF @exp IS NULL INSERT @r VALUES ('T21 combined voucher, invoice leg without cash', 'SKIP', 'no open multi-branch expense without EWT here');
ELSE
BEGIN
    BEGIN TRAN;
    BEGIN TRY
        DELETE @IL; DELETE @ML;
        INSERT INTO @IL (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
        VALUES (@ebranch, @einv, @edate, @exp, @batch, @eamt, 0, @eamt, 0, 0, 'TEST88', 0, NULL);
        INSERT INTO @ML (BranchCode, AccountCode, Amount, Particulars) VALUES (@branch, @caAcct, 500.00, 'TEST88 manual');
        BEGIN TRY
            EXEC dbo.sp_PostSupplierPaymentWithManualLines @parmrefno = '99916', @parmvoucherid = '99916', @parmsupplierid = @esup, @parmsuppliername = @esupName,
                 @parmcheckcoding = '', @parmcheckno = NULL, @parmcheckdate = @today, @parmcontrolno = 'TEST88', @parmcheckremarks = 'TEST88', @parmpreparedby = @user,
                 @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @parmPayingBranch = '888',
                 @InvoiceLegAmount = 0, @InvoiceLines = @IL, @ManualLines = @ML, @InvoiceLineExtras = @IE;
            SELECT @n = COUNT(*), @d1 = SUM(Amount), @s = STRING_AGG(CONCAT(SourceModule, ':', SourceRef, ':', ItemType, ':', Remarks), ',') FROM BankStatementRecon WHERE ReferenceNo = '99916' AND AccountCode = @bank;
            INSERT @r VALUES ('T21 combined voucher, invoice leg without cash', CASE WHEN @n = 1 AND @d1 = 500.00 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@n, ' item ', @d1, ' (', LEFT(@s, 160), ')'));
        END TRY BEGIN CATCH
            SELECT @err = ERROR_NUMBER(), @msg = ERROR_MESSAGE();
            INSERT @r VALUES ('T21 combined voucher, invoice leg without cash', 'SKIP', CONCAT('the fixture does not allow an EWT-only settlement here: ', @err, ' ', LEFT(@msg, 200)));
        END CATCH
    END TRY BEGIN CATCH INSERT @r VALUES ('T21', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
END

------------------------------------------------------------------
-- T22 the legacy sp_AddPaymentSupplierCompound (auto-debit postings) posts its cheque item through the helper: OLD and NEW rows identical
------------------------------------------------------------------
IF @exp IS NULL INSERT @r VALUES ('T22 legacy compound payment old = new', 'SKIP', 'no open multi-branch expense without EWT here');
ELSE
BEGIN
    DECLARE @fp22 TABLE (Run VARCHAR(3), Item VARCHAR(10), Val VARCHAR(MAX));
    SET @run = 'old';
    WHILE @run IS NOT NULL
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            DELETE @IL;
            INSERT INTO @IL (BranchCode, InvoiceNo, InvoiceDate, SequenceReferenceNumber, BatchReferenceID, ActualCost, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, Description, Variance, DiscountAccountCode)
            VALUES (@ebranch, @einv, @edate, @exp, @batch, @eamt, @eamt, 0, 0, 0, 'TEST88', 0, NULL);
            IF @run = 'old'
                EXEC dbo.sp_AddPaymentSupplierCompound_OLD_10152026120000 @parmrefno = '99916', @parmvoucherid = '99916', @parmsupplierid = @esup, @parmsuppliername = @esupName,
                     @parmcheckamount = @eamt, @parmcheckcoding = '', @parmcheckno = '', @parmcontrolno = 'TEST88', @parmcheckdate = @today, @parmcheckremarks = 'TEST88',
                     @parmpreparedby = @user, @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @Lines = @IL, @parmPayingBranch = '888';
            ELSE
                EXEC dbo.sp_AddPaymentSupplierCompound @parmrefno = '99916', @parmvoucherid = '99916', @parmsupplierid = @esup, @parmsuppliername = @esupName,
                     @parmcheckamount = @eamt, @parmcheckcoding = '', @parmcheckno = '', @parmcontrolno = 'TEST88', @parmcheckdate = @today, @parmcheckremarks = 'TEST88',
                     @parmpreparedby = @user, @parmglcode = @bank, @parmpaymethod = 'EXPENSE', @parmforliquidation = 0, @parmvouchertype = 'CASH', @Lines = @IL, @parmPayingBranch = '888';
            INSERT @fp22 SELECT @run, 'APD', CONCAT(COUNT(*), '|', SUM(Amount), '|', STRING_AGG(CONCAT(BranchCode, ':', InvoiceNo, ':', Amount, ':', PaymentType), ',') WITHIN GROUP (ORDER BY BranchCode, PaymentType, Amount)) FROM APPaymentDetails WHERE ReferenceNumber = '99916';
            INSERT @fp22 SELECT @run, 'TKD', CONCAT(COUNT(*), '|', SUM(td.Debit), '|', SUM(td.Credit)) FROM TicketMaster tm JOIN TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode WHERE tm.ReferenceNumber = '99916';
            INSERT @fp22 SELECT @run, 'ES', CONCAT(Balance, '|', AmountPaid, '|', Status) FROM ExpenseSummary WHERE ReferenceNumber = @exp;
            INSERT @fp22 SELECT @run, 'OC', CONCAT(COUNT(*), '|', SUM(Amount), '|', STRING_AGG(CONCAT(BranchCode, ':', AccountCode, ':', ItemType, ':', SourceModule, ':', SourceRef, ':', CONVERT(VARCHAR(10), PeriodEnd, 120), ':', Remarks), ',')) FROM BankStatementRecon WHERE ReferenceNo = '99916';
        END TRY BEGIN CATCH INSERT @r VALUES (CONCAT('T22 ', @run), 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @run = CASE WHEN @run = 'old' THEN 'new' ELSE NULL END;
    END
    SELECT @n = COUNT(*) FROM (SELECT Item, Val FROM @fp22 WHERE Run = 'old' EXCEPT SELECT Item, Val FROM @fp22 WHERE Run = 'new') x;
    INSERT @r VALUES ('T22 legacy compound payment old = new', CASE WHEN @n = 0 AND (SELECT COUNT(*) FROM @fp22 WHERE Run = 'new') = 4 THEN 'PASS' ELSE 'FAIL' END,
                      CONCAT(@n, ' of 4 footprint rows differ; item ', (SELECT Val FROM @fp22 WHERE Run = 'new' AND Item = 'OC')));
END

------------------------------------------------------------------
-- leftovers + results
------------------------------------------------------------------
SELECT @n = (SELECT COUNT(*) FROM PaymentHeader WHERE ReferenceNo IN ('99911','99912','99913','99914','99915','99916','99917','99918'))
          + (SELECT COUNT(*) FROM TicketMaster WHERE ReferenceNumber IN ('99911','99912','99913','99914','99915','99916','99917','99918'))
          + (SELECT COUNT(*) FROM CashVoucher WHERE ReferenceNumber IN ('99911','99912','99913','99914','99915','99916','99917','99918') OR VoucherID IN (99911,99912,99913,99914,99915,99916,99917,99918))
          + (SELECT COUNT(*) FROM ManualJournalVoucher WHERE ReferenceNo IN ('99911','99912','99913','99914','99915','99916','99917','99918'))
          + (SELECT COUNT(*) FROM CashAdvance WHERE ReferenceNo IN ('99911','99912','99913','99914','99915','99916','99917','99918'))
          + (SELECT COUNT(*) FROM ExpenseSummary WHERE ReferenceNumber IN ('99911','99912','99913','99914','99915','99916','99917','99918') OR InvoiceNo = 'TEST88-INV')
          + (SELECT COUNT(*) FROM BankStatementRecon WHERE ReferenceNo IN ('99911','99912','99913','99914','99915','99916','99917','99918') OR SourceRef IN ('99911','99912','99913','99914','99915','99916','99917','99918') OR Payee LIKE 'TEST88%')
          + (SELECT COUNT(*) FROM BankReconHeader WHERE PeriodEnd = @far AND AccountCode IN (@bank, @bankB))
          + (SELECT COUNT(*) FROM BankReconHeader WHERE Status = 'LOCKED' AND LockedBy = @user);
INSERT @r VALUES ('leftovers', CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END, CONCAT(@n, ' test rows left behind'));

SELECT Seq, Test, Result, Detail FROM @r ORDER BY Seq;
SELECT DB_NAME() AS DatabaseName, SUM(CASE WHEN Result = 'PASS' THEN 1 ELSE 0 END) AS Pass, SUM(CASE WHEN Result = 'BUG SHOWN' THEN 1 ELSE 0 END) AS BugShown,
       SUM(CASE WHEN Result = 'SKIP' THEN 1 ELSE 0 END) AS Skip, SUM(CASE WHEN Result IN ('FAIL', 'ERROR', 'UNEXPECTED') THEN 1 ELSE 0 END) AS Fail FROM @r;
