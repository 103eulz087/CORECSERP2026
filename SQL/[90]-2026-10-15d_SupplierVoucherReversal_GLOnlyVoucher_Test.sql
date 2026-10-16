/* ================================================================
   [90] test: Supplier Voucher Reversal of a GL-only voucher
   ================================================================
   Run AFTER [90]. Self-fixturing; every case runs in its own transaction and
   is rolled back (a refusal rolls back the whole transaction, so each refusal
   is its own case). Read the last result sets: PASS / SKIP / FAIL.

   Fixtures picked here:
     @GV / @GRef / @GSup   a GL-only voucher not reversed yet: TelegraphicVoucher
                           or CashVoucher row, VOUCHER-MANUAL ticket, no
                           APPaymentDetails, no CashAdvance
     @IV / @IRef / @ISup   a voucher with an invoice leg, not reversed (G6)
   Optional: set @PickRef to test one reference (e.g. '38711' on STAGING).
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @PickRef VARCHAR(10) = NULL;

DECLARE @Res TABLE (Seq INT IDENTITY(1,1), Test VARCHAR(8), Result VARCHAR(6), Detail VARCHAR(500));
DECLARE @Out TABLE (Status INT, Message VARCHAR(400));
DECLARE @GV VARCHAR(10), @GRef VARCHAR(10), @GSup VARCHAR(50), @GAmt DECIMAL(18,2);
DECLARE @IV VARCHAR(10), @IRef VARCHAR(10), @ISup VARCHAR(50), @IType VARCHAR(20);
DECLARE @n INT, @m INT, @k INT, @e INT, @em VARCHAR(400), @msg VARCHAR(400), @d1 DATE, @d2 DATE;

IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReverseCombinedSupplierVoucher')) NOT LIKE '%@HasGLOnlyLeg%'
BEGIN
    SELECT 'G0' AS Test, 'FAIL' AS Result, '[90] is not installed' AS Detail;
    RETURN;
END
INSERT @Res VALUES ('G0', 'PASS', '[90] installed; backup ' + CASE WHEN OBJECT_ID('dbo.sp_ReverseCombinedSupplierVoucher_OLD_10152026170000') IS NULL THEN 'MISSING' ELSE 'present' END);

;WITH V AS (
    SELECT CAST(VoucherID AS VARCHAR(10)) AS VoucherID, SupplierID, ReferenceNumber, Amount FROM dbo.TelegraphicVoucher WHERE ISNULL(isErrorCorrect, 0) = 0
    UNION ALL
    SELECT CAST(VoucherID AS VARCHAR(10)), SupplierID, ReferenceNumber, Amount FROM dbo.CashVoucher WHERE ISNULL(isErrorCorrect, 0) = 0)
SELECT TOP (1) @GV = v.VoucherID, @GRef = v.ReferenceNumber, @GSup = v.SupplierID, @GAmt = v.Amount
FROM V AS v
WHERE (@PickRef IS NULL OR v.ReferenceNumber = @PickRef)
  AND NOT EXISTS (SELECT 1 FROM dbo.APPaymentDetails a WHERE a.ReferenceNumber = v.ReferenceNumber AND a.SupplierID = v.SupplierID)
  AND NOT EXISTS (SELECT 1 FROM dbo.CashAdvance c WHERE c.ReferenceNo = v.ReferenceNumber AND c.SupplierID = v.SupplierID)
  AND EXISTS (SELECT 1 FROM dbo.TicketMaster t WHERE t.ReferenceNumber = v.ReferenceNumber AND t.ReferenceKey = v.VoucherID AND t.Mnemonic = 'VOUCHER-MANUAL')
  AND NOT EXISTS (SELECT 1 FROM dbo.TicketMaster t WHERE t.ReferenceNumber = v.ReferenceNumber AND t.ReferenceKey = v.VoucherID AND t.Product = 'REVERSAL')
  AND NOT EXISTS (SELECT 1 FROM dbo.PaymentReversalAudit r WHERE r.ReferenceNumber = v.ReferenceNumber AND r.SupplierID = v.SupplierID)
ORDER BY v.ReferenceNumber DESC;

SELECT TOP (1) @IV = CAST(a.VoucherID AS VARCHAR(10)), @IRef = a.ReferenceNumber, @ISup = a.SupplierID, @IType = a.PaymentMethod
FROM dbo.APPaymentDetails AS a
WHERE NOT EXISTS (SELECT 1 FROM dbo.PaymentReversalAudit r WHERE r.VoucherID = a.VoucherID AND r.SupplierID = a.SupplierID)
  AND a.PaymentMethod IN ('PURCHASE', 'EXPENSE')
ORDER BY a.ReferenceNumber DESC;

IF @GV IS NULL
BEGIN
    INSERT @Res VALUES ('FIX', 'SKIP', 'no GL-only voucher that is not reversed yet in this database');
    GOTO Report;
END

------------------------------------------------------------------
-- G1 success: ticket mirrored (dated like the source), OC voided, header + audit + voucher marked
------------------------------------------------------------------
DECLARE @src INT = (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber = @GRef AND ReferenceKey = @GV);
BEGIN TRANSACTION;
BEGIN TRY
    -- INSERT ... EXEC is safe here only because this is the success path (no ROLLBACK inside the proc)
    INSERT @Out EXEC dbo.sp_ReverseCombinedSupplierVoucher
        @parmsupplierid = @GSup, @parmreferenceno = @GRef, @parmvoucherid = @GV, @parmvouchertype = 'EXPENSE',
        @parmcheckno = NULL, @parmreason = 'TEST [90] G1 (rolled back)', @parmuser = 'TEST [90]';
    SELECT TOP (1) @msg = Message FROM @Out;

    SELECT @n = COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber = @GRef AND ReferenceKey = @GV AND Product = 'REVERSAL';
    SELECT @m = COUNT(*) FROM (SELECT AccountCode FROM dbo.TicketDetails WHERE ReferenceNumber = @GRef AND ReferenceKey = @GV
                               GROUP BY AccountCode HAVING ABS(SUM(ISNULL(Debit, 0)) - SUM(ISNULL(Credit, 0))) > 0.004) x;
    SELECT @d1 = MIN(CAST(TicketDate AS DATE)) FROM dbo.TicketMaster WHERE ReferenceNumber = @GRef AND ReferenceKey = @GV AND ISNULL(Product, '') <> 'REVERSAL';
    SELECT @d2 = MIN(CAST(TicketDate AS DATE)) FROM dbo.TicketMaster WHERE ReferenceNumber = @GRef AND ReferenceKey = @GV AND Product = 'REVERSAL';
    INSERT @Res VALUES ('G1a', CASE WHEN @msg LIKE '%GLOnly=1%' AND @msg LIKE '%InvoiceLeg=0%' AND @msg LIKE '%ManualLeg=0%' THEN 'PASS' ELSE 'FAIL' END,
        'ref ' + @GRef + ' / voucher ' + @GV + ' (' + FORMAT(@GAmt, 'N2') + '): ' + ISNULL(@msg, '(no message)'));
    INSERT @Res VALUES ('G1b', CASE WHEN @n = @src AND @src >= 1 AND @m = 0 AND @d1 = @d2 THEN 'PASS' ELSE 'FAIL' END,
        CONCAT('source tickets ', @src, ', reversal tickets ', @n, ', accounts not netting to 0: ', @m, ', source date ', @d1, ' / reversal date ', @d2));

    SELECT @n = COUNT(*), @m = ISNULL(SUM(CASE WHEN IsResolved = 1 AND ResolvedReason = 'VOIDED' THEN 1 ELSE 0 END), 0)
    FROM dbo.BankStatementRecon WHERE SourceRef = @GRef AND ItemType = 'OC';
    INSERT @Res VALUES ('G1c', CASE WHEN @n > 0 AND @n = @m THEN 'PASS' ELSE 'FAIL' END, CONCAT('OC items ', @n, ', voided ', @m));

    SELECT @n = COUNT(*) FROM dbo.PaymentReversalAudit WHERE VoucherID = @GV AND SupplierID = @GSup AND ReferenceNumber = @GRef;
    SELECT @m = COUNT(*) FROM dbo.TransactionPaymentAP WHERE SupplierKey = @GSup AND ReferenceNumber = @GRef AND ISNULL(ErrorCorrect, 0) = 0;
    SELECT @k = (SELECT COUNT(*) FROM dbo.TelegraphicVoucher WHERE VoucherID = @GV AND SupplierID = @GSup AND ReferenceNumber = @GRef AND isErrorCorrect = 1)
              + (SELECT COUNT(*) FROM dbo.CashVoucher WHERE VoucherID = @GV AND SupplierID = @GSup AND ReferenceNumber = @GRef AND isErrorCorrect = 1);
    INSERT @Res VALUES ('G1d', CASE WHEN @n = 1 AND @m = 0 AND @k = 1 THEN 'PASS' ELSE 'FAIL' END,
        CONCAT('audit rows ', @n, ', payment headers not error-corrected ', @m, ', voucher marked ', @k));

    -- G2 a second reversal of the same voucher is refused (this ends the transaction)
    BEGIN TRY
        EXEC dbo.sp_ReverseCombinedSupplierVoucher
            @parmsupplierid = @GSup, @parmreferenceno = @GRef, @parmvoucherid = @GV, @parmvouchertype = 'EXPENSE',
            @parmreason = 'TEST [90] G2', @parmuser = 'TEST [90]';
        INSERT @Res VALUES ('G2', 'FAIL', 'second reversal was accepted');
    END TRY
    BEGIN CATCH
        SET @e = ERROR_NUMBER(); SET @em = ERROR_MESSAGE();
        INSERT @Res VALUES ('G2', CASE WHEN @e = 50050 THEN 'PASS' ELSE 'FAIL' END, CONCAT('second reversal refused ', @e, ': ', @em));
    END CATCH
END TRY
BEGIN CATCH
    SET @e = ERROR_NUMBER(); SET @em = ERROR_MESSAGE();
    INSERT @Res VALUES ('G1', 'FAIL', CONCAT('reversal raised ', @e, ': ', @em));
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

------------------------------------------------------------------
-- G3 an OC item already cleared in the bank recon: refused 60402, nothing changed
------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.BankStatementRecon WHERE SourceRef = @GRef AND ItemType = 'OC' AND IsResolved = 0)
    INSERT @Res VALUES ('G3', 'SKIP', 'the fixture has no open OC item');
ELSE
BEGIN
    BEGIN TRANSACTION;
    BEGIN TRY
        UPDATE TOP (1) dbo.BankStatementRecon SET IsResolved = 1, ResolvedReason = 'TEST [90] CLEARED'
        WHERE SourceRef = @GRef AND ItemType = 'OC' AND IsResolved = 0;
        EXEC dbo.sp_ReverseCombinedSupplierVoucher
            @parmsupplierid = @GSup, @parmreferenceno = @GRef, @parmvoucherid = @GV, @parmvouchertype = 'EXPENSE',
            @parmreason = 'TEST [90] G3', @parmuser = 'TEST [90]';
        INSERT @Res VALUES ('G3', 'FAIL', 'a cleared OC item did not stop the reversal');
    END TRY
    BEGIN CATCH
        SET @e = ERROR_NUMBER(); SET @em = ERROR_MESSAGE();
        INSERT @Res VALUES ('G3', CASE WHEN @e = 60402 THEN 'PASS' ELSE 'FAIL' END, CONCAT('refused ', @e, ': ', @em));
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END

------------------------------------------------------------------
-- G4 an open DIT item under the reference: refused 60403
------------------------------------------------------------------
BEGIN TRANSACTION;
BEGIN TRY
    INSERT INTO dbo.BankStatementRecon (BranchCode, AccountCode, PeriodEnd, ItemType, ReferenceNo, ItemDate, Payee, Amount, Remarks, IsResolved, SourceModule, SourceRef)
    SELECT TOP (1) BranchCode, AccountCode, PeriodEnd, 'DIT', ReferenceNo, ItemDate, Payee, 1.00, 'TEST [90] G4', 0, SourceModule, SourceRef
    FROM dbo.BankStatementRecon WHERE SourceRef = @GRef AND ItemType = 'OC';
    IF @@ROWCOUNT = 0
        INSERT @Res VALUES ('G4', 'SKIP', 'the fixture has no OC item to copy');
    ELSE
    BEGIN
        EXEC dbo.sp_ReverseCombinedSupplierVoucher
            @parmsupplierid = @GSup, @parmreferenceno = @GRef, @parmvoucherid = @GV, @parmvouchertype = 'EXPENSE',
            @parmreason = 'TEST [90] G4', @parmuser = 'TEST [90]';
        INSERT @Res VALUES ('G4', 'FAIL', 'an open DIT item did not stop the reversal');
    END
END TRY
BEGIN CATCH
    SET @e = ERROR_NUMBER(); SET @em = ERROR_MESSAGE();
    INSERT @Res VALUES ('G4', CASE WHEN @e = 60403 THEN 'PASS' ELSE 'FAIL' END, CONCAT('refused ', @e, ': ', @em));
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

------------------------------------------------------------------
-- G5 a reference with nothing under it is still refused 60401
------------------------------------------------------------------
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.sp_ReverseCombinedSupplierVoucher
        @parmsupplierid = @GSup, @parmreferenceno = 'ZZ90NONE', @parmvoucherid = '9999999', @parmvouchertype = 'EXPENSE',
        @parmreason = 'TEST [90] G5', @parmuser = 'TEST [90]';
    INSERT @Res VALUES ('G5', 'FAIL', 'an empty reference was accepted');
END TRY
BEGIN CATCH
    SET @e = ERROR_NUMBER(); SET @em = ERROR_MESSAGE();
    INSERT @Res VALUES ('G5', CASE WHEN @e = 60401 THEN 'PASS' ELSE 'FAIL' END, CONCAT('refused ', @e, ': ', @em));
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

------------------------------------------------------------------
-- G7 another document's recon item under the same reference: refused 60407 (nothing of it is voided)
------------------------------------------------------------------
BEGIN TRANSACTION;
BEGIN TRY
    INSERT INTO dbo.BankStatementRecon (BranchCode, AccountCode, PeriodEnd, ItemType, ReferenceNo, ItemDate, Payee, Amount, Remarks, IsResolved, SourceModule, SourceRef)
    SELECT TOP (1) BranchCode, AccountCode, PeriodEnd, 'OC', 'T90FOREIGN', ItemDate, Payee, 1.00, 'TEST [90] G7', 0, 'MANUAL BANK ENTRY', SourceRef
    FROM dbo.BankStatementRecon WHERE SourceRef = @GRef AND ItemType = 'OC';
    IF @@ROWCOUNT = 0
        INSERT @Res VALUES ('G7', 'SKIP', 'the fixture has no OC item to copy');
    ELSE
    BEGIN
        EXEC dbo.sp_ReverseCombinedSupplierVoucher
            @parmsupplierid = @GSup, @parmreferenceno = @GRef, @parmvoucherid = @GV, @parmvouchertype = 'EXPENSE',
            @parmreason = 'TEST [90] G7', @parmuser = 'TEST [90]';
        INSERT @Res VALUES ('G7', 'FAIL', 'a foreign recon item under the reference did not stop the reversal');
    END
END TRY
BEGIN CATCH
    SET @e = ERROR_NUMBER(); SET @em = ERROR_MESSAGE();
    INSERT @Res VALUES ('G7', CASE WHEN @e = 60407 THEN 'PASS' ELSE 'FAIL' END, CONCAT('refused ', @e, ': ', @em));
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

------------------------------------------------------------------
-- G8 the bank recon is LOCKED in the item's month or a later one: refused 60406 (H7's rule)
------------------------------------------------------------------
DECLARE @hdr INT;
SELECT TOP (1) @hdr = h.HeaderID
FROM dbo.BankStatementRecon AS r
INNER JOIN dbo.BankReconHeader AS h ON h.AccountCode = r.AccountCode AND h.BranchCode = r.BranchCode AND h.PeriodEnd >= r.PeriodEnd
WHERE r.SourceRef = @GRef AND r.ReferenceNo = @GV AND r.ItemType = 'OC' AND ISNULL(r.IsResolved, 0) = 0
ORDER BY h.PeriodEnd DESC;
IF @hdr IS NULL
    INSERT @Res VALUES ('G8', 'SKIP', 'no recon header at or after the item''s month for its account');
ELSE
BEGIN
    BEGIN TRANSACTION;
    BEGIN TRY
        UPDATE dbo.BankReconHeader SET Status = 'LOCKED' WHERE HeaderID = @hdr;
        EXEC dbo.sp_ReverseCombinedSupplierVoucher
            @parmsupplierid = @GSup, @parmreferenceno = @GRef, @parmvoucherid = @GV, @parmvouchertype = 'EXPENSE',
            @parmreason = 'TEST [90] G8', @parmuser = 'TEST [90]';
        INSERT @Res VALUES ('G8', 'FAIL', 'a locked recon month did not stop the reversal');
    END TRY
    BEGIN CATCH
        SET @e = ERROR_NUMBER(); SET @em = ERROR_MESSAGE();
        INSERT @Res VALUES ('G8', CASE WHEN @e = 60406 THEN 'PASS' ELSE 'FAIL' END, CONCAT('header ', @hdr, ' locked: refused ', @e, ': ', @em));
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END

------------------------------------------------------------------
-- G9 another document's ticket under the same reference + voucher id: refused 60408 (it is not mirrored)
------------------------------------------------------------------
BEGIN TRANSACTION;
BEGIN TRY
    INSERT INTO dbo.TicketMaster (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber, ReferenceNumber, ReferenceKey, Owner,
                                  Particulars, EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
    SELECT TOP (1) TicketDate, SupplementaryNumber, BranchCode, 'OR', 'T90TEST', ReferenceNumber, ReferenceKey, Owner,
           'TEST [90] G9', 'TEST [90]', CheckedBy, ApprovedBy, Status, 'OR-TEST', NULL
    FROM dbo.TicketMaster WHERE ReferenceNumber = @GRef AND ReferenceKey = @GV;
    EXEC dbo.sp_ReverseCombinedSupplierVoucher
        @parmsupplierid = @GSup, @parmreferenceno = @GRef, @parmvoucherid = @GV, @parmvouchertype = 'EXPENSE',
        @parmreason = 'TEST [90] G9', @parmuser = 'TEST [90]';
    INSERT @Res VALUES ('G9', 'FAIL', 'a foreign ticket under the reference + voucher id did not stop the reversal');
END TRY
BEGIN CATCH
    SET @e = ERROR_NUMBER(); SET @em = ERROR_MESSAGE();
    INSERT @Res VALUES ('G9', CASE WHEN @e = 60408 THEN 'PASS' ELSE 'FAIL' END, CONCAT('refused ', @e, ': ', @em));
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

------------------------------------------------------------------
-- G6 the invoice path is untouched: old and new proc give the same footprint on an invoice voucher
--    (plain EXEC, not INSERT ... EXEC: a refusal rolls back, which INSERT ... EXEC turns into 3915 over the real error)
------------------------------------------------------------------
IF @IV IS NULL OR OBJECT_ID('dbo.sp_ReverseCombinedSupplierVoucher_OLD_10152026170000') IS NULL
    INSERT @Res VALUES ('G6', 'SKIP', 'no unreversed invoice voucher, or no backup proc to compare with');
ELSE
BEGIN
    DECLARE @FootOld VARCHAR(400), @FootNew VARCHAR(400), @who VARCHAR(20);
    DECLARE @pass INT = 1;
    WHILE @pass <= 2
    BEGIN
        DELETE @Out;
        BEGIN TRANSACTION;
        BEGIN TRY
            IF @pass = 1
                EXEC dbo.sp_ReverseCombinedSupplierVoucher_OLD_10152026170000
                    @parmsupplierid = @ISup, @parmreferenceno = @IRef, @parmvoucherid = @IV, @parmvouchertype = @IType,
                    @parmreason = 'TEST [90] G6', @parmuser = 'TEST [90]';
            ELSE
                EXEC dbo.sp_ReverseCombinedSupplierVoucher
                    @parmsupplierid = @ISup, @parmreferenceno = @IRef, @parmvoucherid = @IV, @parmvouchertype = @IType,
                    @parmreason = 'TEST [90] G6', @parmuser = 'TEST [90]';
            SET @msg = CONCAT(
                'tickets ', (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber = @IRef),
                ' lines ', (SELECT COUNT(*) FROM dbo.TicketDetails WHERE ReferenceNumber = @IRef),
                ' net ', (SELECT SUM(ISNULL(Debit, 0) - ISNULL(Credit, 0)) FROM dbo.TicketDetails WHERE ReferenceNumber = @IRef),
                ' ledger ', (SELECT COUNT(*) FROM dbo.SupplierLedger WHERE ReferenceNumber = @IRef AND SupplierID = @ISup),
                ' audit ', (SELECT COUNT(*) FROM dbo.PaymentReversalAudit WHERE ReferenceNumber = @IRef AND SupplierID = @ISup),
                ' recon open ', (SELECT COUNT(*) FROM dbo.BankStatementRecon WHERE SourceRef = @IRef AND IsResolved = 0),
                ' apd ', (SELECT COUNT(*) FROM dbo.APPaymentDetails WHERE ReferenceNumber = @IRef));
        END TRY
        BEGIN CATCH
            SET @msg = CONCAT('raised ', ERROR_NUMBER(), ': ', ERROR_MESSAGE());
        END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF @pass = 1 SET @FootOld = @msg ELSE SET @FootNew = @msg;
        SET @pass += 1;
    END
    INSERT @Res VALUES ('G6', CASE WHEN @FootOld = @FootNew AND @FootOld NOT LIKE 'raised%' THEN 'PASS' ELSE 'FAIL' END,
        'invoice voucher ' + @IRef + ' / ' + @IV + ': old [' + @FootOld + '] new [' + @FootNew + ']');
END

Report:
DECLARE @tc INT;
SELECT @tc = @@TRANCOUNT;   -- read on its own: inside an INSERT / SELECT INTO it reads at least 1
SELECT n = (SELECT COUNT(*) FROM dbo.TicketMaster WHERE ReferenceNumber = @GRef AND Product = 'REVERSAL') INTO #Left;
INSERT @Res VALUES ('END', CASE WHEN @tc = 0 AND (SELECT n FROM #Left) = 0 THEN 'PASS' ELSE 'FAIL' END,
    CONCAT('rolled back; reversal tickets left on the fixture: ', (SELECT n FROM #Left), '; fixtures GL-only ', ISNULL(@GRef, '-'), ' / ', ISNULL(@GV, '-'),
           ', invoice ', ISNULL(@IRef, '-'), ' / ', ISNULL(@IV, '-')));
DROP TABLE #Left;

SELECT Test, Result, Detail FROM @Res ORDER BY Seq;
SELECT SUM(CASE WHEN Result = 'PASS' THEN 1 ELSE 0 END) AS Passed,
       SUM(CASE WHEN Result = 'FAIL' THEN 1 ELSE 0 END) AS Failed,
       SUM(CASE WHEN Result = 'SKIP' THEN 1 ELSE 0 END) AS Skipped
FROM @Res;
