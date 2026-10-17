/* [108] test: trg_CheckVoucher_NoDuplicateCVNo. Self-fixturing, every case in its own transaction, ROLLED BACK.
   Picks a live voucher's CV no., a CV no. held only by reversed vouchers and a cancelled-cheque record's CV no.
   Test rows: VoucherID 9990801.., CheckNo 'T108-..' (never a real cheque no.). Prints PASS / FAIL / SKIP. */
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF @@TRANCOUNT <> 0 BEGIN RAISERROR('open transaction: stop', 16, 1); RETURN; END
IF OBJECT_ID('dbo.trg_CheckVoucher_NoDuplicateCVNo', 'TR') IS NULL BEGIN RAISERROR('[108] is not installed here', 16, 1); RETURN; END
PRINT 'database: ' + DB_NAME() + ' on ' + @@SERVERNAME;

DECLARE @Live VARCHAR(50), @LiveVid DECIMAL(7,0), @Live2Vid DECIMAL(7,0), @Live2Ref VARCHAR(20), @Live2Seq DECIMAL(10,0), @Live2Sup VARCHAR(50),
        @RevOnly VARCHAR(50), @Canc VARCHAR(50), @Seq DECIMAL(10,0), @Sup VARCHAR(50), @n INT, @err INT, @r NVARCHAR(400);
SELECT TOP (1) @Live = LTRIM(RTRIM(CVNo)), @LiveVid = VoucherID, @Sup = SupplierID FROM dbo.CheckVoucher
 WHERE ISNULL(isErrorCorrect, 0) = 0 AND NULLIF(LTRIM(RTRIM(CVNo)), '') IS NOT NULL ORDER BY VoucherID DESC;
SELECT TOP (1) @Live2Vid = VoucherID, @Live2Ref = ReferenceNumber, @Live2Seq = SequenceNumber, @Live2Sup = SupplierID FROM dbo.CheckVoucher
 WHERE ISNULL(isErrorCorrect, 0) = 0 AND NULLIF(LTRIM(RTRIM(CVNo)), '') IS NOT NULL AND VoucherID <> @LiveVid ORDER BY VoucherID DESC;
SELECT TOP (1) @RevOnly = LTRIM(RTRIM(c.CVNo)) FROM dbo.CheckVoucher AS c
 WHERE c.isErrorCorrect = 1 AND ISNULL(c.PaidTo, '') <> 'CANCELLED' AND NULLIF(LTRIM(RTRIM(c.CVNo)), '') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM dbo.CheckVoucher AS x WHERE LTRIM(RTRIM(x.CVNo)) = LTRIM(RTRIM(c.CVNo)) AND ISNULL(x.isErrorCorrect, 0) = 0)
 ORDER BY c.VoucherID DESC;
SELECT TOP (1) @Canc = LTRIM(RTRIM(c.CVNo)) FROM dbo.CheckVoucher AS c
 WHERE c.PaidTo = 'CANCELLED' AND ISNULL(c.Amount, 0) = 0 AND c.isErrorCorrect = 1 AND NULLIF(LTRIM(RTRIM(c.CVNo)), '') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.CheckVoucherCancelled AS l WHERE l.VoucherID = c.VoucherID AND l.ReferenceNumber = c.ReferenceNumber AND l.VoucherType = 'CANCELLED CHEQUE')
 ORDER BY c.VoucherID DESC;
-- CheckVoucher.SequenceNumber is an identity
PRINT 'fixtures: live ' + ISNULL(@Live, '-') + ' (voucher ' + ISNULL(CAST(@LiveVid AS VARCHAR(10)), '-') + '), 2nd live voucher ' + ISNULL(CAST(@Live2Vid AS VARCHAR(10)), '-')
    + ', reversed-only ' + ISNULL(@RevOnly, '-') + ', cancelled record ' + ISNULL(@Canc, '-');

-- T1 new live voucher on a live voucher's CV no. -> 60632
SET @err = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT dbo.CheckVoucher (VoucherID, SupplierID, ReferenceNumber, PaidTo, CheckNo, Amount, isErrorCorrect, CVNo)
    VALUES (9990801, @Sup, '99908', 'T108', 'T108-01', 1, 0, @Live + '  ');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH SET @err = ERROR_NUMBER(); SET @r = ERROR_MESSAGE(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; END CATCH
PRINT CASE WHEN @Live IS NULL THEN 'SKIP' WHEN @err = 60632 THEN 'PASS' ELSE 'FAIL' END + '  T1 live CV no. re-used (trailing blanks) -> 60632 (got ' + CAST(@err AS VARCHAR(10)) + ')';
IF @err = 60632 PRINT '      message: ' + @r;

-- T2 a CV no. held only by reversed vouchers may be issued again -> saved
SET @err = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT dbo.CheckVoucher (VoucherID, SupplierID, ReferenceNumber, PaidTo, CheckNo, Amount, isErrorCorrect, CVNo)
    VALUES (9990802, @Sup, '99908', 'T108', 'T108-02', 1, 0, @RevOnly);
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH SET @err = ERROR_NUMBER(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; END CATCH
PRINT CASE WHEN @RevOnly IS NULL THEN 'SKIP' WHEN @err = 0 THEN 'PASS' ELSE 'FAIL' END + '  T2 reversed voucher''s CV no. re-issued -> saved (got ' + CAST(@err AS VARCHAR(10)) + ')';

-- T3 a cancelled-cheque record's CV no. -> 60632
SET @err = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT dbo.CheckVoucher (VoucherID, SupplierID, ReferenceNumber, PaidTo, CheckNo, Amount, isErrorCorrect, CVNo)
    VALUES (9990803, @Sup, '99908', 'T108', 'T108-03', 1, 0, @Canc);
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH SET @err = ERROR_NUMBER(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; END CATCH
PRINT CASE WHEN @Canc IS NULL THEN 'SKIP' WHEN @err = 60632 THEN 'PASS' ELSE 'FAIL' END + '  T3 cancelled-cheque record''s CV no. -> 60632 (got ' + CAST(@err AS VARCHAR(10)) + ')';

-- T4 a free CV no. -> saved
SET @err = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT dbo.CheckVoucher (VoucherID, SupplierID, ReferenceNumber, PaidTo, CheckNo, Amount, isErrorCorrect, CVNo)
    VALUES (9990804, @Sup, '99908', 'T108', 'T108-04', 1, 0, 'CVT108-FREE-0001');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH SET @err = ERROR_NUMBER(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; END CATCH
PRINT CASE WHEN @err = 0 THEN 'PASS' ELSE 'FAIL' END + '  T4 free CV no. -> saved (got ' + CAST(@err AS VARCHAR(10)) + ')';

-- T5 two new vouchers in one INSERT sharing a new CV no. -> 60632
SET @err = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT dbo.CheckVoucher (VoucherID, SupplierID, ReferenceNumber, PaidTo, CheckNo, Amount, isErrorCorrect, CVNo)
    VALUES (9990805, @Sup, '99908', 'T108', 'T108-05', 1, 0, 'CVT108-PAIR'),
           (9990806, @Sup, '99909', 'T108', 'T108-06', 1, 0, 'CVT108-PAIR');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH SET @err = ERROR_NUMBER(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; END CATCH
PRINT CASE WHEN @err = 60632 THEN 'PASS' ELSE 'FAIL' END + '  T5 two new vouchers, one CV no., one INSERT -> 60632 (got ' + CAST(@err AS VARCHAR(10)) + ')';

-- T6 UPDATE a live voucher's CV no. to another live voucher's -> 60632
SET @err = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE dbo.CheckVoucher SET CVNo = @Live
     WHERE VoucherID = @Live2Vid AND ReferenceNumber = @Live2Ref AND SequenceNumber = @Live2Seq AND SupplierID = @Live2Sup;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH SET @err = ERROR_NUMBER(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; END CATCH
PRINT CASE WHEN @Live2Vid IS NULL THEN 'SKIP' WHEN @err = 60632 THEN 'PASS' ELSE 'FAIL' END + '  T6 CV no. edited onto another live voucher''s -> 60632 (got ' + CAST(@err AS VARCHAR(10)) + ')';

-- T7 reversing a live voucher (isErrorCorrect -> 1) -> saved, then its number is free (a new voucher takes it)
SET @err = 0; SET @n = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE dbo.CheckVoucher SET isErrorCorrect = 1 WHERE VoucherID = @LiveVid;
    INSERT dbo.CheckVoucher (VoucherID, SupplierID, ReferenceNumber, PaidTo, CheckNo, Amount, isErrorCorrect, CVNo)
    VALUES (9990807, @Sup, '99908', 'T108', 'T108-07', 1, 0, @Live);
    SET @n = 1;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH SET @err = ERROR_NUMBER(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; END CATCH
PRINT CASE WHEN @Live IS NULL THEN 'SKIP' WHEN @err = 0 AND @n = 1 THEN 'PASS' ELSE 'FAIL' END + '  T7 reverse a voucher, then re-issue its CV no. -> saved (got ' + CAST(@err AS VARCHAR(10)) + ')';

-- T8 an UPDATE of other columns on every row -> saved (nothing changed CV no. / status)
SET @err = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE dbo.CheckVoucher SET DateUpdate = DateUpdate;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH SET @err = ERROR_NUMBER(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; END CATCH
PRINT CASE WHEN @err = 0 THEN 'PASS' ELSE 'FAIL' END + '  T8 update of other columns on all rows -> saved (got ' + CAST(@err AS VARCHAR(10)) + ')';

-- T9 the screen's pre-check query (SupplierPaymentDevEx.FindCVNoHolder): a holder for live / cancelled, none for reversed-only / free
DECLARE @h1 INT, @h2 INT, @h3 INT, @h4 INT;
SELECT @h1 = COUNT(*) FROM dbo.CheckVoucher AS c WHERE LTRIM(RTRIM(c.CVNo)) = @Live AND (ISNULL(c.isErrorCorrect, 0) = 0 OR (c.PaidTo = 'CANCELLED' AND ISNULL(c.Amount, 0) = 0 AND c.isErrorCorrect = 1 AND EXISTS (SELECT 1 FROM dbo.CheckVoucherCancelled AS l WHERE l.VoucherID = c.VoucherID AND l.ReferenceNumber = c.ReferenceNumber AND l.VoucherType = 'CANCELLED CHEQUE')));
SELECT @h2 = COUNT(*) FROM dbo.CheckVoucher AS c WHERE LTRIM(RTRIM(c.CVNo)) = @Canc AND (ISNULL(c.isErrorCorrect, 0) = 0 OR (c.PaidTo = 'CANCELLED' AND ISNULL(c.Amount, 0) = 0 AND c.isErrorCorrect = 1 AND EXISTS (SELECT 1 FROM dbo.CheckVoucherCancelled AS l WHERE l.VoucherID = c.VoucherID AND l.ReferenceNumber = c.ReferenceNumber AND l.VoucherType = 'CANCELLED CHEQUE')));
SELECT @h3 = COUNT(*) FROM dbo.CheckVoucher AS c WHERE LTRIM(RTRIM(c.CVNo)) = @RevOnly AND (ISNULL(c.isErrorCorrect, 0) = 0 OR (c.PaidTo = 'CANCELLED' AND ISNULL(c.Amount, 0) = 0 AND c.isErrorCorrect = 1 AND EXISTS (SELECT 1 FROM dbo.CheckVoucherCancelled AS l WHERE l.VoucherID = c.VoucherID AND l.ReferenceNumber = c.ReferenceNumber AND l.VoucherType = 'CANCELLED CHEQUE')));
SELECT @h4 = COUNT(*) FROM dbo.CheckVoucher AS c WHERE LTRIM(RTRIM(c.CVNo)) = 'CVT108-FREE-0001';
PRINT CASE WHEN @h1 = 1 AND (@Canc IS NULL OR @h2 = 1) AND (@RevOnly IS NULL OR @h3 = 0) AND @h4 = 0 THEN 'PASS' ELSE 'FAIL' END
    + '  T9 screen pre-check: live ' + CAST(@h1 AS VARCHAR(5)) + ' / cancelled ' + CAST(ISNULL(@h2, 0) AS VARCHAR(5)) + ' / reversed-only ' + CAST(ISNULL(@h3, 0) AS VARCHAR(5)) + ' / free ' + CAST(@h4 AS VARCHAR(5));

-- leftovers
SELECT @n = COUNT(*) FROM dbo.CheckVoucher WHERE VoucherID BETWEEN 9990800 AND 9990899 OR CheckNo LIKE 'T108-%';
PRINT CASE WHEN @n = 0 AND @@TRANCOUNT = 0 THEN 'PASS' ELSE 'FAIL' END + '  leftovers: ' + CAST(@n AS VARCHAR(5)) + ' test rows';
