/* ================================================================
   [101] test: AR payment reversal refuses a deposit already ticked as cleared
   ================================================================
   Run AFTER [101]. Self-fixturing; every case runs in its own transaction and
   is rolled back (a refusal rolls back the whole transaction, so each refusal
   is its own case). Ticks / unticks go through the real sp_BankRecon_ResolveItem.
   Read the last result set: PASS / BUG SHOWN / SKIP / FAIL.

   Fixture: the newest POSTED AR payment (since 2026-09-01) with its own open
   AR-PAYMENT deposit (DIT), exactly one OR- ticket, in an open recon month.
   Optional: set @PickRef to test one payment reference.
     T1  old proc (backup): ticked deposit + reversal -> deposit stays CLEARED  = BUG SHOWN
         (and BankRecon_GLvsRecon_Check.sql section 7 finds it)
     T2  new proc: ticked deposit -> refused 93030, nothing changed
     T3  new proc: open deposit -> reversed, deposit REVERSED (unchanged behaviour)
     T4  new proc: ticked, then unticked by the accountant -> reversed, deposit REVERSED
     T0b the 93030 guard sits before the proc's first write (UPDATE T) and before the 93028 lock check
         (T2's "nothing changed" alone can't show it: the refusal rolls the whole transaction back)
     T5  repair rule ([101] section 1, same predicate) on the T1 state, cleared in its own month:
         FIXED, fn_BankRecon_Figures of the month unchanged
     T6  same, cleared in a LATER month (needs a later open header of the account): FIXED, the own
         month's open DIT drops by the deposit (the GL nets to 0 there after the reversal)
     T7  same, the deposit's month LOCKED: SKIPPED
     T8  new proc: ticked deposit AND its month locked -> 93030 (not 93028)
   Not covered: the script's post-check failure path and its re-run guard (checked by hand on DEV:
   a second run says "already applied").
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @PickRef VARCHAR(20) = NULL;

DECLARE @Res TABLE (Seq INT IDENTITY(1,1), Test VARCHAR(8), Result VARCHAR(10), Detail VARCHAR(600));
DECLARE @PH INT, @Ref VARCHAR(20), @Recon INT, @Amt DECIMAL(18,2), @Period DATE, @Hdr INT, @NextPeriod DATE;
DECLARE @d1 DECIMAL(18,2), @d2 DECIMAL(18,2), @o1 DECIMAL(18,2), @o2 DECIMAL(18,2), @sel VARCHAR(30), @def NVARCHAR(MAX);
DECLARE @st VARCHAR(20), @isRes BIT, @why VARCHAR(500), @e INT, @em NVARCHAR(2048), @n INT;

IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient')) NOT LIKE '%THROW 93030%'
BEGIN
    SELECT 'T0' AS Test, 'FAIL' AS Result, '[101] is not installed' AS Detail;
    RETURN;
END
SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient'));
INSERT @Res VALUES ('T0b', CASE WHEN CHARINDEX('THROW 93030', @def) > 0 AND CHARINDEX('THROW 93030', @def) < CHARINDEX('UPDATE T', @def)
                                 AND CHARINDEX('THROW 93030', @def) < CHARINDEX('THROW 93028', @def) THEN 'PASS' ELSE 'FAIL' END,
    CONCAT('position of THROW 93030 ', CHARINDEX('THROW 93030', @def), ', first write UPDATE T ', CHARINDEX('UPDATE T', @def), ', THROW 93028 ', CHARINDEX('THROW 93028', @def)));
INSERT @Res VALUES ('T0', 'PASS', '[101] installed; backup proc ' + CASE WHEN OBJECT_ID('dbo.sp_ReversePaymentClient_OLD_10172026120000') IS NULL THEN 'MISSING' ELSE 'present' END
    + ', backup table ' + CASE WHEN OBJECT_ID('dbo.BankRecon_ReversedARCleared_Backup_20261017', 'U') IS NULL THEN 'MISSING' ELSE 'present' END);

SELECT TOP (1) @PH = ph.PaymentHeaderID, @Ref = ph.ReferenceNo, @Recon = r.ReconID, @Amt = r.Amount, @Period = h.PeriodEnd, @Hdr = h.HeaderID
FROM dbo.PaymentHeader AS ph
INNER JOIN dbo.BankStatementRecon AS r ON r.SourceModule = 'AR-PAYMENT' AND r.SourceRef = ph.ReferenceNo AND r.ReferenceNo = ph.ReferenceNo
                                       AND r.ItemType = 'DIT' AND r.IsResolved = 0
INNER JOIN dbo.BankReconHeader AS h ON h.HeaderID = r.HeaderID
WHERE ph.Status = 'POSTED' AND ph.PaymentDate >= '2026-09-01'
  AND (@PickRef IS NULL OR ph.ReferenceNo = @PickRef)
  AND (SELECT COUNT(*) FROM dbo.TicketMaster AS tm WHERE tm.ReferenceNumber = ph.ReferenceNo AND tm.Mnemonic LIKE 'OR-%') = 1
  AND NOT EXISTS (SELECT 1 FROM dbo.BankReconHeader AS x WHERE x.BranchCode = h.BranchCode AND x.AccountCode = h.AccountCode
                                                            AND x.Status = 'LOCKED' AND x.PeriodEnd >= h.PeriodEnd)
  AND (SELECT COUNT(*) FROM dbo.BankStatementRecon AS r2 WHERE r2.SourceModule = 'AR-PAYMENT' AND r2.SourceRef = ph.ReferenceNo) = 1
ORDER BY ph.PaymentHeaderID DESC;

IF @PH IS NULL
BEGIN
    INSERT @Res VALUES ('FIX', 'SKIP', 'no POSTED AR payment with an open deposit in an open recon month');
    GOTO Report;
END
SELECT @NextPeriod = MIN(x.PeriodEnd) FROM dbo.BankReconHeader AS x
INNER JOIN dbo.BankReconHeader AS h ON h.HeaderID = @Hdr
WHERE x.BranchCode = h.BranchCode AND x.AccountCode = h.AccountCode AND x.PeriodEnd > h.PeriodEnd AND ISNULL(x.Status, '') <> 'LOCKED';
INSERT @Res VALUES ('FIX', 'PASS', CONCAT('payment ', @PH, ' / ref ', @Ref, ', deposit ReconID ', @Recon, ' ', FORMAT(@Amt, 'N2'), ', month ', @Period));

------------------------------------------------------------------
-- T1 old proc: the bug
------------------------------------------------------------------
IF OBJECT_ID('dbo.sp_ReversePaymentClient_OLD_10172026120000', 'P') IS NULL
    INSERT @Res VALUES ('T1', 'SKIP', 'backup proc missing');
ELSE
BEGIN
    BEGIN TRANSACTION;
    BEGIN TRY
        EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @Recon, @IsResolved = 1, @ResolvedBy = 'TEST [101]', @PeriodEnd = @Period;
        EXEC dbo.sp_ReversePaymentClient_OLD_10172026120000 @PaymentHeaderID = @PH, @ReversedBy = 'TEST [101]';
        SELECT @st = Status FROM dbo.PaymentHeader WHERE PaymentHeaderID = @PH;
        SELECT @isRes = IsResolved, @why = ResolvedReason FROM dbo.BankStatementRecon WHERE ReconID = @Recon;
        -- the Exception Center rule (BankRecon_GLvsRecon_Check.sql section 7, AR part)
        SELECT @n = COUNT(*) FROM dbo.BankStatementRecon AS r
        INNER JOIN dbo.PaymentHeader AS ph ON ph.ReferenceNo = r.SourceRef
        WHERE r.ReconID = @Recon AND r.SourceModule = 'AR-PAYMENT' AND ph.Status = 'REVERSED' AND r.IsResolved = 1
          AND ISNULL(r.ResolvedReason, '') <> 'REVERSED' AND ISNULL(r.ResolvedReason, '') NOT LIKE 'VOIDED%';
        INSERT @Res VALUES ('T1', CASE WHEN @st = 'REVERSED' AND @isRes = 1 AND ISNULL(@why, '') NOT IN ('REVERSED') AND @why NOT LIKE 'VOIDED%' AND @n = 1 THEN 'BUG SHOWN' ELSE 'FAIL' END,
            CONCAT('old proc: payment ', @st, ', deposit IsResolved ', @isRes, ' / ', ISNULL(@why, '(null)'), '; section 7 finds it: ', @n));
    END TRY
    BEGIN CATCH
        INSERT @Res VALUES ('T1', 'FAIL', CONCAT('error ', ERROR_NUMBER(), ': ', ERROR_MESSAGE()));
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END

------------------------------------------------------------------
-- T2 new proc: ticked deposit -> 93030, nothing changed
------------------------------------------------------------------
SELECT @e = NULL, @em = NULL;
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @Recon, @IsResolved = 1, @ResolvedBy = 'TEST [101]', @PeriodEnd = @Period;
    EXEC dbo.sp_ReversePaymentClient @PaymentHeaderID = @PH, @ReversedBy = 'TEST [101]';
END TRY
BEGIN CATCH
    SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
SELECT @st = Status FROM dbo.PaymentHeader WHERE PaymentHeaderID = @PH;
SELECT @isRes = IsResolved FROM dbo.BankStatementRecon WHERE ReconID = @Recon;
INSERT @Res VALUES ('T2', CASE WHEN @e = 93030 AND @em LIKE '%' + @Ref + '%' AND @st = 'POSTED' AND @isRes = 0 THEN 'PASS' ELSE 'FAIL' END,
    CONCAT('error ', ISNULL(CAST(@e AS VARCHAR(10)), 'none'), ': ', ISNULL(@em, '(reversal was not refused)'), ' | after: payment ', @st, ', deposit IsResolved ', @isRes));

------------------------------------------------------------------
-- T3 new proc: open deposit -> reversed, deposit REVERSED
------------------------------------------------------------------
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.sp_ReversePaymentClient @PaymentHeaderID = @PH, @ReversedBy = 'TEST [101]';
    SELECT @st = Status FROM dbo.PaymentHeader WHERE PaymentHeaderID = @PH;
    SELECT @isRes = IsResolved, @why = ResolvedReason FROM dbo.BankStatementRecon WHERE ReconID = @Recon;
    INSERT @Res VALUES ('T3', CASE WHEN @st = 'REVERSED' AND @isRes = 1 AND @why = 'REVERSED' THEN 'PASS' ELSE 'FAIL' END,
        CONCAT('payment ', @st, ', deposit IsResolved ', @isRes, ' / ', ISNULL(@why, '(null)')));
END TRY
BEGIN CATCH
    INSERT @Res VALUES ('T3', 'FAIL', CONCAT('error ', ERROR_NUMBER(), ': ', ERROR_MESSAGE()));
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

------------------------------------------------------------------
-- T4 new proc: ticked, unticked by the accountant, then reversed
------------------------------------------------------------------
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @Recon, @IsResolved = 1, @ResolvedBy = 'TEST [101]', @PeriodEnd = @Period;
    EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @Recon, @IsResolved = 0, @ResolvedBy = 'TEST [101]', @PeriodEnd = @Period;
    EXEC dbo.sp_ReversePaymentClient @PaymentHeaderID = @PH, @ReversedBy = 'TEST [101]';
    SELECT @st = Status FROM dbo.PaymentHeader WHERE PaymentHeaderID = @PH;
    SELECT @isRes = IsResolved, @why = ResolvedReason FROM dbo.BankStatementRecon WHERE ReconID = @Recon;
    INSERT @Res VALUES ('T4', CASE WHEN @st = 'REVERSED' AND @isRes = 1 AND @why = 'REVERSED' THEN 'PASS' ELSE 'FAIL' END,
        CONCAT('payment ', @st, ', deposit IsResolved ', @isRes, ' / ', ISNULL(@why, '(null)')));
END TRY
BEGIN CATCH
    INSERT @Res VALUES ('T4', 'FAIL', CONCAT('error ', ERROR_NUMBER(), ': ', ERROR_MESSAGE()));
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

------------------------------------------------------------------
-- T5 / T6 / T7: the repair rule of [101] section 1 on the old proc's leftover (same predicate, this item only)
------------------------------------------------------------------
DECLARE @case INT = 5, @tick DATE;
WHILE @case <= 7
BEGIN
    SET @tick = CASE WHEN @case = 6 THEN @NextPeriod ELSE @Period END;
    IF OBJECT_ID('dbo.sp_ReversePaymentClient_OLD_10172026120000', 'P') IS NULL OR @tick IS NULL
    BEGIN
        INSERT @Res VALUES (CONCAT('T', @case), 'SKIP', CASE WHEN @tick IS NULL THEN 'no later open recon month for this account' ELSE 'backup proc missing' END);
        SET @case += 1;
        CONTINUE;
    END
    SELECT @d1 = NULL, @d2 = NULL, @o1 = NULL, @o2 = NULL, @sel = NULL;
    BEGIN TRANSACTION;
    BEGIN TRY
        EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @Recon, @IsResolved = 1, @ResolvedBy = 'TEST [101]', @PeriodEnd = @tick;
        EXEC dbo.sp_ReversePaymentClient_OLD_10172026120000 @PaymentHeaderID = @PH, @ReversedBy = 'TEST [101]';
        IF @case = 7 UPDATE dbo.BankReconHeader SET Status = 'LOCKED' WHERE HeaderID = @Hdr;
        SELECT @d1 = Difference, @o1 = OpenDIT FROM dbo.fn_BankRecon_Figures(@Hdr);

        SELECT @sel = CASE WHEN EXISTS (SELECT 1 FROM dbo.BankReconHeader AS h WITH (HOLDLOCK)
                                        WHERE h.BranchCode = hb.BranchCode AND h.AccountCode = hb.AccountCode
                                          AND h.Status = 'LOCKED' AND h.PeriodEnd >= hb.PeriodEnd)
                           THEN 'SKIPPED' ELSE 'FIXED' END
        FROM dbo.BankStatementRecon AS r
        INNER JOIN dbo.BankReconHeader AS hb ON hb.HeaderID = r.HeaderID
        INNER JOIN dbo.PaymentHeader AS ph ON ph.ReferenceNo = r.SourceRef AND ph.ReferenceNo = r.ReferenceNo
        WHERE r.ReconID = @Recon AND r.SourceModule = 'AR-PAYMENT' AND r.ItemType = 'DIT' AND r.IsResolved = 1
          AND ISNULL(r.ResolvedReason, '') <> 'REVERSED' AND ISNULL(r.ResolvedReason, '') NOT LIKE 'VOIDED%'
          AND ph.Status = 'REVERSED'
          AND NOT EXISTS (SELECT 1 FROM dbo.PaymentHeader AS p2 WHERE p2.ReferenceNo = ph.ReferenceNo AND ISNULL(p2.Status, '') <> 'REVERSED');
        IF @sel = 'FIXED'
            UPDATE dbo.BankStatementRecon SET ResolvedReason = 'REVERSED', UpdatedBy = 'TEST [101]', DateTimeUpdated = GETDATE() WHERE ReconID = @Recon;
        SELECT @d2 = Difference, @o2 = OpenDIT FROM dbo.fn_BankRecon_Figures(@Hdr);

        IF @case = 5
            INSERT @Res VALUES ('T5', CASE WHEN @sel = 'FIXED' AND @d1 = @d2 AND @o1 = @o2 THEN 'PASS' ELSE 'FAIL' END,
                CONCAT('own month: ', ISNULL(@sel, '(not selected)'), '; Difference ', @d1, ' -> ', @d2, ', open DIT ', @o1, ' -> ', @o2));
        ELSE IF @case = 6
            INSERT @Res VALUES ('T6', CASE WHEN @sel = 'FIXED' AND @o1 - @o2 = @Amt AND @d1 - @d2 = @Amt THEN 'PASS' ELSE 'FAIL' END,
                CONCAT('cleared in ', @tick, ': ', ISNULL(@sel, '(not selected)'), '; own month open DIT ', @o1, ' -> ', @o2, ' (expected -', @Amt, '), Difference ', @d1, ' -> ', @d2));
        ELSE
            INSERT @Res VALUES ('T7', CASE WHEN @sel = 'SKIPPED' THEN 'PASS' ELSE 'FAIL' END, CONCAT('month locked: ', ISNULL(@sel, '(not selected)')));
    END TRY
    BEGIN CATCH
        INSERT @Res VALUES (CONCAT('T', @case), 'FAIL', CONCAT('error ', ERROR_NUMBER(), ': ', ERROR_MESSAGE()));
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @case += 1;
END

------------------------------------------------------------------
-- T8 new proc: ticked deposit and its month locked -> 93030 first
------------------------------------------------------------------
SELECT @e = NULL, @em = NULL;
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.sp_BankRecon_ResolveItem @ReconID = @Recon, @IsResolved = 1, @ResolvedBy = 'TEST [101]', @PeriodEnd = @Period;
    UPDATE dbo.BankReconHeader SET Status = 'LOCKED' WHERE HeaderID = @Hdr;
    EXEC dbo.sp_ReversePaymentClient @PaymentHeaderID = @PH, @ReversedBy = 'TEST [101]';
END TRY
BEGIN CATCH
    SELECT @e = ERROR_NUMBER(), @em = ERROR_MESSAGE();
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
INSERT @Res VALUES ('T8', CASE WHEN @e = 93030 THEN 'PASS' ELSE 'FAIL' END,
    CONCAT('error ', ISNULL(CAST(@e AS VARCHAR(10)), 'none'), ': ', ISNULL(@em, '(not refused)')));

------------------------------------------------------------------
-- leftovers
------------------------------------------------------------------
SELECT @st = Status FROM dbo.PaymentHeader WHERE PaymentHeaderID = @PH;
SELECT @isRes = IsResolved FROM dbo.BankStatementRecon WHERE ReconID = @Recon;
SELECT @n = (SELECT COUNT(*) FROM dbo.BankStatementRecon WHERE ResolvedBy = 'TEST [101]' OR UpdatedBy = 'TEST [101]')
          + (SELECT COUNT(*) FROM dbo.BankReconHeader WHERE HeaderID = @Hdr AND Status = 'LOCKED');
INSERT @Res VALUES ('LEFT', CASE WHEN @st = 'POSTED' AND @isRes = 0 AND @n = 0 AND @@TRANCOUNT = 0 THEN 'PASS' ELSE 'FAIL' END,
    CONCAT('payment ', @st, ', deposit IsResolved ', @isRes, ', test rows ', @n));

Report:
SELECT Test, Result, Detail FROM @Res ORDER BY Seq;
SELECT SUM(CASE WHEN Result = 'PASS' THEN 1 ELSE 0 END) AS PASS, SUM(CASE WHEN Result = 'BUG SHOWN' THEN 1 ELSE 0 END) AS BUG_SHOWN,
       SUM(CASE WHEN Result = 'SKIP' THEN 1 ELSE 0 END) AS SKIP, SUM(CASE WHEN Result = 'FAIL' THEN 1 ELSE 0 END) AS FAIL
FROM @Res;
