/* [110] test: cancelled CR records. Self-fixturing (a GAP number, a live payment's CR, a CR held only by reversed
   payments), every case in its own transaction, ROLLED BACK. Prints PASS / FAIL / SKIP; nothing is left behind. */
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF @@TRANCOUNT <> 0 BEGIN RAISERROR('open transaction: stop', 16, 1); RETURN; END
IF OBJECT_ID('dbo.spu_RecordCancelledCR', 'P') IS NULL BEGIN RAISERROR('[110] is not installed here', 16, 1); RETURN; END
PRINT 'database: ' + DB_NAME() + ' on ' + @@SERVERNAME;

DECLARE @br VARCHAR(10), @next VARCHAR(20), @gap VARCHAR(20), @gapAlt VARCHAR(20), @d DATE, @dig INT, @sq BIGINT,
        @liveBr VARCHAR(10), @live VARCHAR(20), @revBr VARCHAR(10), @rev VARCHAR(20), @otherBr VARCHAR(10),
        @err INT, @n INT, @n2 INT, @m NVARCHAR(600), @id INT, @before INT;
DECLARE @r TABLE (id INT, msg VARCHAR(400));

;WITH n AS (SELECT c.BranchCode, s.Series, s.SeqNo, ph.CRNo, CAST(ph.PaymentDate AS DATE) d
            FROM dbo.PaymentHeader ph JOIN dbo.Customers c ON c.CustomerKey = ph.CustomerKey
            CROSS APPLY dbo.fn_rpt_DocNoSplit(ph.CRNo) s WHERE s.SeqNo IS NOT NULL)
SELECT TOP (1) @br = a.BranchCode, @next = a.CRNo, @d = a.d, @sq = a.SeqNo - 1
FROM n a
WHERE EXISTS (SELECT 1 FROM n b WHERE b.BranchCode = a.BranchCode AND b.Series = a.Series AND b.SeqNo = a.SeqNo - 2)
  AND NOT EXISTS (SELECT 1 FROM n b WHERE b.BranchCode = a.BranchCode AND b.Series = a.Series AND b.SeqNo = a.SeqNo - 1)
  AND NOT EXISTS (SELECT 1 FROM dbo.CancelledCollectionReceipt x WHERE x.BranchCode = a.BranchCode)
ORDER BY a.d DESC;
SET @dig = PATINDEX('%[^0-9]%', REVERSE(@next)) - 1;
SET @gap = LEFT(@next, LEN(@next) - @dig) + RIGHT(REPLICATE('0', @dig) + CAST(@sq AS VARCHAR(20)), @dig);
SET @gapAlt = LEFT(@next, LEN(@next) - @dig) + CAST(@sq AS VARCHAR(20));        -- same number without the leading zeros
SELECT TOP (1) @liveBr = c.BranchCode, @live = ph.CRNo
FROM dbo.PaymentHeader ph JOIN dbo.Customers c ON c.CustomerKey = ph.CustomerKey
WHERE ISNULL(ph.Status, '') <> 'REVERSED' AND NULLIF(LTRIM(RTRIM(ph.CRNo)), '') IS NOT NULL ORDER BY ph.PaymentHeaderID DESC;
SELECT TOP (1) @revBr = c.BranchCode, @rev = ph.CRNo
FROM dbo.PaymentHeader ph JOIN dbo.Customers c ON c.CustomerKey = ph.CustomerKey
WHERE ph.Status = 'REVERSED' AND NULLIF(LTRIM(RTRIM(ph.CRNo)), '') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.PaymentHeader p2 JOIN dbo.Customers c2 ON c2.CustomerKey = p2.CustomerKey
                  WHERE c2.BranchCode = c.BranchCode AND LTRIM(RTRIM(p2.CRNo)) = LTRIM(RTRIM(ph.CRNo)) AND ISNULL(p2.Status, '') <> 'REVERSED')
ORDER BY ph.PaymentHeaderID DESC;
SELECT TOP (1) @otherBr = BranchCode FROM dbo.Branches WHERE BranchCode <> @br ORDER BY BranchCode;
SELECT @before = COUNT(*) FROM dbo.CancelledCollectionReceipt;
PRINT CONCAT('fixtures: gap ', @br, ' ', @gap, ' (before ', @next, ', ', @d, '); live ', @liveBr, ' ', @live, '; reversed-only ', @revBr, ' ', @rev);

-- T1 record the GAP number -> saved; register: CANCELLED row, the next receipt's GAP note gone
SET @err = 0; SET @n = 0; SET @n2 = -1;
BEGIN TRY
    BEGIN TRANSACTION;
    DELETE @r; INSERT @r EXEC dbo.spu_RecordCancelledCR @br, @gap, @d, 'spoiled', 'test', 'T110';
    DECLARE @reg TABLE (Branch VARCHAR(200), Series VARCHAR(50), CRNo VARCHAR(20), SeqNo BIGINT, PaymentDate DATE, ControlNo VARCHAR(30), ReferenceNo VARCHAR(20), Customer VARCHAR(300), PaymentType VARCHAR(30), AmountReceived DECIMAL(18,2), AppliedToInvoices DECIMAL(18,2), EWT DECIMAL(18,2), Discount DECIMAL(18,2), Invoices VARCHAR(MAX), Status VARCHAR(20), Note VARCHAR(500));
    INSERT @reg EXEC dbo.sp_rpt_CollectionReceiptRegister @d, @d, @br;
    SELECT @n = COUNT(*) FROM @reg WHERE CRNo = @gap AND Status = 'CANCELLED' AND Note LIKE 'CANCELLED: SPOILED%' AND AmountReceived = 0;
    SELECT @n2 = COUNT(*) FROM @reg WHERE CRNo = @next AND Note LIKE '%GAP%';
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH SET @err = ERROR_NUMBER(); SET @m = ERROR_MESSAGE(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; END CATCH
PRINT CASE WHEN @br IS NULL THEN 'SKIP' WHEN @err = 0 AND @n = 1 AND @n2 = 0 THEN 'PASS' ELSE 'FAIL' END
    + CONCAT('  T1 gap number recorded: register CANCELLED row ', @n, ', GAP note on the next receipt ', @n2, ' (err ', @err, ')');

-- T2 the same number again, typed without the leading zeros -> 59755
SET @err = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    DELETE @r; INSERT @r EXEC dbo.spu_RecordCancelledCR @br, @gap, @d, 'SPOILED', NULL, 'T110';
    EXEC dbo.spu_RecordCancelledCR @br, @gapAlt, @d, 'LOST', NULL, 'T110';   -- refused: plain EXEC (a rollback under INSERT-EXEC is 3915)
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH SET @err = ERROR_NUMBER(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; END CATCH
PRINT CASE WHEN @br IS NULL THEN 'SKIP' WHEN @err = 59755 THEN 'PASS' ELSE 'FAIL' END + CONCAT('  T2 same CR again (', @gapAlt, ') -> 59755 (got ', @err, ')');

-- T3 a live payment's CR -> 59756
SET @err = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC dbo.spu_RecordCancelledCR @liveBr, @live, @d, 'SPOILED', NULL, 'T110';
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH SET @err = ERROR_NUMBER(); SET @m = ERROR_MESSAGE(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; END CATCH
PRINT CASE WHEN @live IS NULL THEN 'SKIP' WHEN @err = 59756 THEN 'PASS' ELSE 'FAIL' END + CONCAT('  T3 live payment''s CR ', @live, ' -> 59756 (got ', @err, ')');
IF @err = 59756 PRINT '      message: ' + @m;

-- T4 a CR held only by reversed payments -> saved
SET @err = 0; SET @n = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    DELETE @r; INSERT @r EXEC dbo.spu_RecordCancelledCR @revBr, @rev, '2026-10-01', 'VOIDED', NULL, 'T110';
    SELECT @n = COUNT(*) FROM @r;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH SET @err = ERROR_NUMBER(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; END CATCH
PRINT CASE WHEN @rev IS NULL THEN 'SKIP' WHEN @err = 0 AND @n = 1 THEN 'PASS' ELSE 'FAIL' END + CONCAT('  T4 reversed-only CR ', @rev, ' -> saved (err ', @err, ')');

-- T5 refusals: unknown branch 59751, blank CR 59752, no reason 59753, future date 59754
DECLARE @k INT = 1, @want INT, @label VARCHAR(40);
WHILE @k <= 4
BEGIN
    SET @err = 0;
    BEGIN TRY
        BEGIN TRANSACTION;
        DELETE @r;
        IF @k = 1 BEGIN SET @want = 59751; SET @label = 'unknown branch'; EXEC dbo.spu_RecordCancelledCR 'ZZZ', @gap, @d, 'SPOILED', NULL, 'T110'; END
        IF @k = 2 BEGIN SET @want = 59752; SET @label = 'blank CR no.';   EXEC dbo.spu_RecordCancelledCR @br, '  ', @d, 'SPOILED', NULL, 'T110'; END
        IF @k = 3 BEGIN SET @want = 59753; SET @label = 'no reason';      EXEC dbo.spu_RecordCancelledCR @br, @gap, @d, ' ', NULL, 'T110'; END
        IF @k = 4 BEGIN SET @want = 59754; SET @label = 'future date';    DECLARE @fut DATE = DATEADD(DAY, 1, CAST(GETDATE() AS DATE)); EXEC dbo.spu_RecordCancelledCR @br, @gap, @fut, 'SPOILED', NULL, 'T110'; END
        ROLLBACK TRANSACTION;
    END TRY
    BEGIN CATCH SET @err = ERROR_NUMBER(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; END CATCH
    PRINT CASE WHEN @err = @want THEN 'PASS' ELSE 'FAIL' END + CONCAT('  T5.', @k, ' ', @label, ' -> ', @want, ' (got ', @err, ')');
    SET @k += 1;
END

-- T6 edit: reason changed -> 1 log row with old / new; the same save again -> "No changes", no new log row
SET @err = 0; SET @n = -1; SET @n2 = -1; SET @m = NULL;
BEGIN TRY
    BEGIN TRANSACTION;
    DELETE @r; INSERT @r EXEC dbo.spu_RecordCancelledCR @br, @gap, @d, 'SPOILED', 'first', 'T110';
    SELECT @id = id FROM @r;
    DELETE @r; INSERT @r EXEC dbo.spu_EditCancelledCR @id, @br, @gap, @d, 'misprinted', 'second', 'T110-EDIT';
    SELECT @n = COUNT(*) FROM dbo.CancelledCollectionReceiptEditLog WHERE CancelledCRID = @id AND OldReason = 'SPOILED' AND NewReason = 'MISPRINTED' AND OldRemarks = 'first' AND NewRemarks = 'second';
    DELETE @r; INSERT @r EXEC dbo.spu_EditCancelledCR @id, @br, @gap, @d, 'MISPRINTED', 'second', 'T110-EDIT';
    SELECT @m = msg FROM @r;
    SELECT @n2 = COUNT(*) FROM dbo.CancelledCollectionReceiptEditLog WHERE CancelledCRID = @id;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH SET @err = ERROR_NUMBER(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; END CATCH
PRINT CASE WHEN @br IS NULL THEN 'SKIP' WHEN @err = 0 AND @n = 1 AND @n2 = 1 AND @m LIKE 'No changes%' THEN 'PASS' ELSE 'FAIL' END
    + CONCAT('  T6 edit logs old / new (', @n, '), unchanged save writes nothing (log rows ', @n2, ', "', @m, '") (err ', @err, ')');

-- T7 edit onto a live payment's CR -> 59756; onto another cancelled CR -> 59755; missing record -> 59757
SET @k = 1;
WHILE @k <= 3
BEGIN
    SET @err = 0;
    BEGIN TRY
        BEGIN TRANSACTION;
        DELETE @r; INSERT @r EXEC dbo.spu_RecordCancelledCR @br, @gap, @d, 'SPOILED', NULL, 'T110';
        SELECT @id = id FROM @r;
        IF @k = 1 BEGIN SET @want = 59756; SET @label = 'onto a live payment''s CR'; EXEC dbo.spu_EditCancelledCR @id, @liveBr, @live, @d, 'SPOILED', NULL, 'T110'; END
        IF @k = 2 BEGIN SET @want = 59755; SET @label = 'onto another cancelled CR';
                        DELETE @r; INSERT @r EXEC dbo.spu_RecordCancelledCR @revBr, @rev, '2026-10-01', 'VOIDED', NULL, 'T110';
                        EXEC dbo.spu_EditCancelledCR @id, @revBr, @rev, @d, 'SPOILED', NULL, 'T110'; END
        IF @k = 3 BEGIN SET @want = 59757; SET @label = 'record not found'; EXEC dbo.spu_EditCancelledCR -1, @br, @gap, @d, 'SPOILED', NULL, 'T110'; END
        ROLLBACK TRANSACTION;
    END TRY
    BEGIN CATCH SET @err = ERROR_NUMBER(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; END CATCH
    PRINT CASE WHEN (@k = 1 AND @live IS NULL) OR (@k = 2 AND @rev IS NULL) THEN 'SKIP' WHEN @err = @want THEN 'PASS' ELSE 'FAIL' END
        + CONCAT('  T7.', @k, ' edit ', @label, ' -> ', @want, ' (got ', @err, ')');
    SET @k += 1;
END

-- T8 sp_FindCancelledCR: finds the number typed without zeros at its branch, nothing at another branch
SET @err = 0; SET @n = -1; SET @n2 = -1;
BEGIN TRY
    BEGIN TRANSACTION;
    DELETE @r; INSERT @r EXEC dbo.spu_RecordCancelledCR @br, @gap, @d, 'SPOILED', NULL, 'T110';
    DECLARE @f TABLE (CancelledCRID INT, BranchCode VARCHAR(10), CRNo VARCHAR(20), CRDate DATE, Reason VARCHAR(100), RecordedBy VARCHAR(50));
    INSERT @f EXEC dbo.sp_FindCancelledCR @br, @gapAlt;      SELECT @n = COUNT(*) FROM @f;
    DELETE @f; INSERT @f EXEC dbo.sp_FindCancelledCR @otherBr, @gap; SELECT @n2 = COUNT(*) FROM @f;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH SET @err = ERROR_NUMBER(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; END CATCH
PRINT CASE WHEN @br IS NULL THEN 'SKIP' WHEN @err = 0 AND @n = 1 AND @n2 = 0 THEN 'PASS' ELSE 'FAIL' END
    + CONCAT('  T8 find: same branch ', @n, ', other branch ', @n2, ' (err ', @err, ')');

-- leftovers
SELECT @n = COUNT(*) FROM dbo.CancelledCollectionReceipt;
SELECT @n2 = COUNT(*) FROM dbo.CancelledCollectionReceiptEditLog WHERE EditedBy LIKE 'T110%';
PRINT CASE WHEN @n = @before AND @n2 = 0 AND @@TRANCOUNT = 0 THEN 'PASS' ELSE 'FAIL' END + CONCAT('  leftovers: records ', @n, ' (were ', @before, '), test log rows ', @n2);
