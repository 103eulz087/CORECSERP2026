/* ================================================================
   [86] TEST SCRIPT - Manual JV edit: keep the preparer, Last Modified By / Date, unchanged save re-posts nothing
   ================================================================
   Run in SSMS on DEV or STAGING AFTER [86] is applied (not PRODUCTION). Every test runs inside BEGIN TRAN ... ROLLBACK:
   nothing is left behind. The last result set has one row per test: PASS / FAIL / BUG SHOWN / SKIP.

   Each test rebuilds exactly what the screen sends on Posted > Edit > Save Changes: the voucher date, remarks and
   control no. as loaded, and the lines in the order sp_GetManualJournalVoucherDetails returns them, numbered 1..n.
   Fixtures picked automatically (shown first): the newest multi-branch voucher, and the newest one posted before
   line numbers existed (LineNo NULL). Optional: set @Ref below to test one voucher of your choice.
   ================================================================ */
SET NOCOUNT ON;
DECLARE @Ref VARCHAR(10) = NULL;   -- optional: a reference no. to test; NULL = the newest multi-branch voucher

DECLARE @res TABLE (Seq INT IDENTITY, Test VARCHAR(55), Result VARCHAR(12), Detail VARCHAR(700));
DECLARE @err INT, @n INT, @st INT, @msg VARCHAR(300), @dr DECIMAL(18,2), @cr DECIMAL(18,2);

IF @Ref IS NULL
    SELECT TOP (1) @Ref = v.ReferenceNo FROM ManualJournalVoucher v GROUP BY v.ReferenceNo
    HAVING COUNT(DISTINCT v.BranchCode) > 1 AND SUM(CASE WHEN v.isErrorCorrect = 1 THEN 1 ELSE 0 END) = 0
    ORDER BY MAX(v.VoucherID) DESC;
DECLARE @RefOld VARCHAR(10);
SELECT TOP (1) @RefOld = v.ReferenceNo FROM ManualJournalVoucher v JOIN ManualJournalVoucherDetails d ON d.VoucherID = v.VoucherID
GROUP BY v.ReferenceNo HAVING SUM(CASE WHEN d.[LineNo] IS NULL THEN 1 ELSE 0 END) > 0 AND v.ReferenceNo <> ISNULL(@Ref, '')
ORDER BY MAX(v.VoucherID) DESC;

-- what the screen sends for @Ref
DECLARE @Lines dbo.JournalVoucherLineMultiTVP_V2, @LinesOld dbo.JournalVoucherLineMultiTVP_V2, @LinesX dbo.JournalVoucherLineMultiTVP_V2;
DECLARE @vdate DATE, @remarks VARCHAR(500), @ctrl VARCHAR(50), @cross BIT, @prep VARCHAR(50), @padded DATETIME, @tkt VARCHAR(20), @vids VARCHAR(200);
DECLARE @vdateO DATE, @remarksO VARCHAR(500), @ctrlO VARCHAR(50), @crossO BIT;

INSERT @Lines ([LineNo], BranchCode, AccountCode, Debit, Credit, Particulars)
SELECT ROW_NUMBER() OVER (ORDER BY d.[LineNo], v.BranchCode, d.DetailID), v.BranchCode, d.AccountCode, CAST(d.Debit AS DECIMAL(18,2)), CAST(d.Credit AS DECIMAL(18,2)), ISNULL(d.Particulars, '')
FROM ManualJournalVoucher v JOIN ManualJournalVoucherDetails d ON d.VoucherID = v.VoucherID WHERE v.ReferenceNo = @Ref;
SELECT @vdate = MIN(VoucherDate), @remarks = LTRIM(RTRIM(MAX(ISNULL(Remarks, '')))) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref;
SELECT TOP (1) @ctrl = ReferenceKey FROM TicketMaster WHERE ReferenceNumber = @Ref AND Origin = 'JV' ORDER BY CASE WHEN ReferenceKey IS NULL THEN 1 ELSE 0 END, TicketNumber;
SET @cross = CASE WHEN EXISTS (SELECT 1 FROM TicketMaster WHERE ReferenceNumber = @Ref AND Origin = 'JV' AND Mnemonic LIKE '%CROSS-BR') THEN 1 ELSE 0 END;
SELECT TOP (1) @prep = PreparedBy, @padded = DateAdded FROM ManualJournalVoucher WHERE ReferenceNo = @Ref ORDER BY DateAdded, VoucherID;
SELECT @tkt = MAX(TicketNumber), @vids = STRING_AGG(CAST(VoucherID AS VARCHAR(12)), ',') WITHIN GROUP (ORDER BY VoucherID) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref;

IF @RefOld IS NOT NULL
BEGIN
    INSERT @LinesOld ([LineNo], BranchCode, AccountCode, Debit, Credit, Particulars)
    SELECT ROW_NUMBER() OVER (ORDER BY d.[LineNo], v.BranchCode, d.DetailID), v.BranchCode, d.AccountCode, CAST(d.Debit AS DECIMAL(18,2)), CAST(d.Credit AS DECIMAL(18,2)), ISNULL(d.Particulars, '')
    FROM ManualJournalVoucher v JOIN ManualJournalVoucherDetails d ON d.VoucherID = v.VoucherID WHERE v.ReferenceNo = @RefOld;
    SELECT @vdateO = MIN(VoucherDate), @remarksO = LTRIM(RTRIM(MAX(ISNULL(Remarks, '')))) FROM ManualJournalVoucher WHERE ReferenceNo = @RefOld;
    SELECT TOP (1) @ctrlO = ReferenceKey FROM TicketMaster WHERE ReferenceNumber = @RefOld AND Origin = 'JV' ORDER BY CASE WHEN ReferenceKey IS NULL THEN 1 ELSE 0 END, TicketNumber;
    SET @crossO = CASE WHEN EXISTS (SELECT 1 FROM TicketMaster WHERE ReferenceNumber = @RefOld AND Origin = 'JV' AND Mnemonic LIKE '%CROSS-BR') THEN 1 ELSE 0 END;
END

SELECT 'fixtures' AS what, @Ref AS voucher, (SELECT COUNT(*) FROM @Lines) AS lines_, @prep AS prepared_by, @padded AS date_prepared, @tkt AS ticket, @vids AS voucher_ids, @cross AS cross_branch,
       @RefOld AS voucher_without_line_numbers;

IF @Ref IS NULL
BEGIN
    SELECT 'SKIP' AS Result, 'no multi-branch manual JV on this database' AS Detail;
    RETURN;
END

------------------------------------------------------------------
-- T1 OLD proc, untouched save: re-posts anyway, editor becomes the preparer (the reported bug)
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    DECLARE @sink TABLE (Status INT, ReferenceNo VARCHAR(10), BranchesPosted INT, Message VARCHAR(300));
    INSERT @sink EXEC dbo.sp_EditManualJournalVoucher_OLD_10142026233000 @parmrefno = @Ref, @parmcontrolno = @ctrl, @parmvoucherdate = @vdate, @parmremarks = @remarks,
         @parmuser = 'TEST86 EDITOR', @Lines = @Lines, @AllowCrossBranch = @cross;
    INSERT @res VALUES ('T1 old proc, untouched save', CASE WHEN (SELECT MAX(PreparedBy) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref) = 'TEST86 EDITOR' THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END,
                       CONCAT('preparer now ', (SELECT MAX(PreparedBy) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref), ' (was ', @prep, '), ticket ', (SELECT MAX(TicketNumber) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref), ' (was ', @tkt, ')'));
END TRY BEGIN CATCH INSERT @res VALUES ('T1 old proc, untouched save', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T2 NEW proc, untouched save: Status 0, nothing re-posted (same VoucherIDs, ticket, preparer; no Last Modified)
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    DELETE @sink;
    INSERT @sink EXEC dbo.sp_EditManualJournalVoucher @parmrefno = @Ref, @parmcontrolno = @ctrl, @parmvoucherdate = @vdate, @parmremarks = @remarks,
         @parmuser = 'TEST86 EDITOR', @Lines = @Lines, @AllowCrossBranch = @cross;
    SELECT @st = Status, @msg = Message FROM @sink;
    INSERT @res VALUES ('T2 new proc, untouched save', CASE WHEN @st = 0
                            AND (SELECT STRING_AGG(CAST(VoucherID AS VARCHAR(12)), ',') WITHIN GROUP (ORDER BY VoucherID) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref) = @vids
                            AND (SELECT MAX(TicketNumber) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref) = @tkt
                            AND (SELECT MAX(PreparedBy) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref) = @prep
                            AND NOT EXISTS (SELECT 1 FROM ManualJournalVoucher WHERE ReferenceNo = @Ref AND LastModifiedBy IS NOT NULL) THEN 'PASS' ELSE 'FAIL' END,
                       CONCAT('Status ', @st, ': ', @msg));
END TRY BEGIN CATCH INSERT @res VALUES ('T2 new proc, untouched save', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T3 the cross-branch tick alone is not a change
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    DELETE @sink;
    INSERT @sink EXEC dbo.sp_EditManualJournalVoucher @parmrefno = @Ref, @parmcontrolno = @ctrl, @parmvoucherdate = @vdate, @parmremarks = @remarks,
         @parmuser = 'TEST86 EDITOR', @Lines = @Lines, @AllowCrossBranch = 0;   -- the screen opens with the box unticked
    SELECT @st = Status FROM @sink;
    INSERT @res VALUES ('T3 untouched, box unticked', CASE WHEN @st = 0 THEN 'PASS' ELSE 'FAIL' END, CONCAT('Status ', @st, ' (voucher posted cross-branch: ', @cross, ')'));
END TRY BEGIN CATCH INSERT @res VALUES ('T3 untouched, box unticked', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T4 a real change (particulars of line 1): re-posted, preparer + date kept, Last Modified By / Date set, tickets balance
------------------------------------------------------------------
DELETE @LinesX; INSERT @LinesX SELECT * FROM @Lines;
UPDATE @LinesX SET Particulars = LEFT(Particulars + ' (edited by test)', 500) WHERE [LineNo] = 1;
BEGIN TRAN;
BEGIN TRY
    DELETE @sink;
    INSERT @sink EXEC dbo.sp_EditManualJournalVoucher @parmrefno = @Ref, @parmcontrolno = @ctrl, @parmvoucherdate = @vdate, @parmremarks = @remarks,
         @parmuser = 'TEST86 EDITOR', @Lines = @LinesX, @AllowCrossBranch = @cross;
    SELECT @st = Status FROM @sink;
    SELECT @dr = SUM(Debit), @cr = SUM(Credit) FROM TicketDetails WHERE ReferenceNumber = @Ref AND TicketNumber IN (SELECT TicketNumber FROM TicketMaster WHERE ReferenceNumber = @Ref AND Origin = 'JV');
    INSERT @res VALUES ('T4 real change', CASE WHEN @st = 1
                            AND NOT EXISTS (SELECT 1 FROM ManualJournalVoucher WHERE ReferenceNo = @Ref AND (PreparedBy <> @prep OR DateAdded <> @padded OR ISNULL(LastModifiedBy, '') <> 'TEST86 EDITOR' OR LastModifiedDate IS NULL OR LastModifiedDate < DATEADD(MINUTE, -5, GETDATE())))
                            AND @dr = @cr AND @dr > 0 THEN 'PASS' ELSE 'FAIL' END,
                       CONCAT('Status ', @st, '; preparer ', (SELECT MAX(PreparedBy) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref), ' / ', CONVERT(VARCHAR(19), (SELECT MIN(DateAdded) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref), 120),
                              '; last modified ', (SELECT MAX(LastModifiedBy) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref), ' / ', CONVERT(VARCHAR(19), (SELECT MAX(LastModifiedDate) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref), 120),
                              '; ticket DR ', @dr, ' CR ', @cr));

    -- T5 the Posted tab shows it: one row, original preparer, Last Modified By / Date
    DECLARE @list TABLE (ControlNo VARCHAR(150), ReferenceNo VARCHAR(10), VoucherDate DATE, Remarks VARCHAR(500), BranchCount INT, BranchCode VARCHAR(5), TotalAmount DECIMAL(18,2),
                         PreparedBy VARCHAR(50), DatePrepared DATETIME, LastModifiedBy VARCHAR(50), LastModifiedDate DATETIME);
    INSERT @list EXEC dbo.sp_GetPostedManualJournalVouchers @DateFrom = @vdate, @DateTo = @vdate;
    INSERT @res VALUES ('T5 Posted tab row', CASE WHEN (SELECT COUNT(*) FROM @list WHERE ReferenceNo = @Ref) = 1
                            AND EXISTS (SELECT 1 FROM @list WHERE ReferenceNo = @Ref AND PreparedBy = @prep AND DatePrepared = @padded AND LastModifiedBy = 'TEST86 EDITOR' AND LastModifiedDate IS NOT NULL) THEN 'PASS' ELSE 'FAIL' END,
                       (SELECT TOP 1 CONCAT('rows ', (SELECT COUNT(*) FROM @list WHERE ReferenceNo = @Ref), ': Prepared By ', PreparedBy, ' ', CONVERT(VARCHAR(16), DatePrepared, 120), ' | Last Modified By ', LastModifiedBy, ' ', CONVERT(VARCHAR(16), LastModifiedDate, 120), ' | control no ', ControlNo)
                        FROM @list WHERE ReferenceNo = @Ref));

    -- T6 saving the edited voucher again untouched: Status 0, Last Modified unchanged
    DECLARE @lm DATETIME = (SELECT MAX(LastModifiedDate) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref);
    DELETE @sink;
    INSERT @sink EXEC dbo.sp_EditManualJournalVoucher @parmrefno = @Ref, @parmcontrolno = @ctrl, @parmvoucherdate = @vdate, @parmremarks = @remarks,
         @parmuser = 'TEST86 SOMEONE ELSE', @Lines = @LinesX, @AllowCrossBranch = @cross;
    SELECT @st = Status FROM @sink;
    INSERT @res VALUES ('T6 re-save of an edited voucher, untouched', CASE WHEN @st = 0 AND (SELECT MAX(LastModifiedDate) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref) = @lm
                            AND (SELECT MAX(LastModifiedBy) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref) = 'TEST86 EDITOR' THEN 'PASS' ELSE 'FAIL' END,
                       CONCAT('Status ', @st, '; last modified by still ', (SELECT MAX(LastModifiedBy) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref)));
END TRY BEGIN CATCH INSERT @res VALUES ('T4-T6 real change', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T7 each kind of change is detected: remarks, date, control no., amount, line order, upper/lower case
------------------------------------------------------------------
DECLARE @kind INT = 1, @kname VARCHAR(30), @d2 DATE, @r2 VARCHAR(500), @c2 VARCHAR(50);
WHILE @kind <= 6
BEGIN
    DELETE @LinesX; INSERT @LinesX SELECT * FROM @Lines;
    SELECT @d2 = @vdate, @r2 = @remarks, @c2 = @ctrl;
    IF @kind = 1 BEGIN SET @kname = 'remarks';      SET @r2 = LEFT(@remarks + ' x', 500); END
    IF @kind = 2 BEGIN SET @kname = 'voucher date'; SET @d2 = DATEADD(DAY, -1, @vdate); END
    IF @kind = 3 BEGIN SET @kname = 'control no.';  SET @c2 = LEFT(ISNULL(@ctrl, '') + 'X', 50); END
    IF @kind = 4 BEGIN SET @kname = 'amount';       UPDATE @LinesX SET Debit = Debit + 1 WHERE [LineNo] = (SELECT MIN([LineNo]) FROM @LinesX WHERE Debit > 0); UPDATE @LinesX SET Credit = Credit + 1 WHERE [LineNo] = (SELECT MIN([LineNo]) FROM @LinesX WHERE Credit > 0); END
    IF @kind = 5 BEGIN SET @kname = 'line order';   UPDATE @LinesX SET [LineNo] = (SELECT COUNT(*) FROM @Lines) + 1 - [LineNo]; END
    IF @kind = 6 BEGIN SET @kname = 'upper/lower case'; UPDATE @LinesX SET Particulars = CASE WHEN Particulars = UPPER(Particulars) THEN LOWER(Particulars) + 'a' ELSE UPPER(Particulars) END WHERE [LineNo] = 1; END
    BEGIN TRAN;
    BEGIN TRY
        DELETE @sink;
        INSERT @sink EXEC dbo.sp_EditManualJournalVoucher @parmrefno = @Ref, @parmcontrolno = @c2, @parmvoucherdate = @d2, @parmremarks = @r2,
             @parmuser = 'TEST86 EDITOR', @Lines = @LinesX, @AllowCrossBranch = 1;
        SELECT @st = Status FROM @sink;
        INSERT @res VALUES (CONCAT('T7 change of ', @kname), CASE WHEN @st = 1 THEN 'PASS' ELSE 'FAIL' END, CONCAT('Status ', @st));
    END TRY BEGIN CATCH
        -- a change that is refused (e.g. a closed GL month) still proves it was seen as a change
        INSERT @res VALUES (CONCAT('T7 change of ', @kname), CASE WHEN ERROR_NUMBER() IN (59900) THEN 'PASS' ELSE 'ERROR' END, CONCAT(ERROR_NUMBER(), ' ', LEFT(ERROR_MESSAGE(), 150)));
    END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @kind += 1;
END

------------------------------------------------------------------
-- T8 a voucher posted before line numbers existed (LineNo NULL): untouched save is still recognised
------------------------------------------------------------------
IF @RefOld IS NULL INSERT @res VALUES ('T8 untouched, old voucher (LineNo NULL)', 'SKIP', 'no such voucher here');
ELSE
BEGIN
    BEGIN TRAN;
    BEGIN TRY
        DELETE @sink;
        INSERT @sink EXEC dbo.sp_EditManualJournalVoucher @parmrefno = @RefOld, @parmcontrolno = @ctrlO, @parmvoucherdate = @vdateO, @parmremarks = @remarksO,
             @parmuser = 'TEST86 EDITOR', @Lines = @LinesOld, @AllowCrossBranch = @crossO;
        SELECT @st = Status FROM @sink;
        INSERT @res VALUES ('T8 untouched, old voucher (LineNo NULL)', CASE WHEN @st = 0 THEN 'PASS' ELSE 'FAIL' END, CONCAT('voucher ', @RefOld, ': Status ', @st));
    END TRY BEGIN CATCH INSERT @res VALUES ('T8 untouched, old voucher (LineNo NULL)', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
END

------------------------------------------------------------------
-- T9 another document's ticket under the same number survives an edit (OLD proc deleted it)
------------------------------------------------------------------
DELETE @LinesX; INSERT @LinesX SELECT * FROM @Lines;
UPDATE @LinesX SET Particulars = LEFT(Particulars + ' (edited by test)', 500) WHERE [LineNo] = 1;
BEGIN TRAN;
BEGIN TRY
    INSERT INTO TicketMaster (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber, ReferenceNumber, ReferenceKey, Owner, Particulars, EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
    VALUES (@vdate, 0, '888', '888', '9999986', @Ref, 'TEST86', 'TEST86', 'another document under the same number', 'TEST86', '*', '*', 'POSTED', 'SI-VATEX', NULL);
    INSERT INTO TicketDetails (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey, TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
    VALUES (@vdate, 0, '888', 'TEST86', '9999986', @Ref, '101030101', 1, 0, ''), (@vdate, 0, '888', 'TEST86', '9999986', @Ref, '401', 0, 1, '');
    DELETE @sink;
    INSERT @sink EXEC dbo.sp_EditManualJournalVoucher_OLD_10142026233000 @parmrefno = @Ref, @parmcontrolno = @ctrl, @parmvoucherdate = @vdate, @parmremarks = @remarks,
         @parmuser = 'TEST86 EDITOR', @Lines = @LinesX, @AllowCrossBranch = 1;
    INSERT @res VALUES ('T9a old proc, other ticket under the number', CASE WHEN NOT EXISTS (SELECT 1 FROM TicketMaster WHERE TicketNumber = '9999986') THEN 'BUG SHOWN' ELSE 'UNEXPECTED' END,
                       CONCAT('other ticket rows left: ', (SELECT COUNT(*) FROM TicketMaster WHERE TicketNumber = '9999986') + (SELECT COUNT(*) FROM TicketDetails WHERE TicketNumber = '9999986')));
END TRY BEGIN CATCH INSERT @res VALUES ('T9a old proc, other ticket under the number', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
BEGIN TRAN;
BEGIN TRY
    INSERT INTO TicketMaster (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber, ReferenceNumber, ReferenceKey, Owner, Particulars, EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
    VALUES (@vdate, 0, '888', '888', '9999986', @Ref, 'TEST86', 'TEST86', 'another document under the same number', 'TEST86', '*', '*', 'POSTED', 'SI-VATEX', NULL);
    INSERT INTO TicketDetails (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey, TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
    VALUES (@vdate, 0, '888', 'TEST86', '9999986', @Ref, '101030101', 1, 0, ''), (@vdate, 0, '888', 'TEST86', '9999986', @Ref, '401', 0, 1, '');
    DELETE @sink;
    INSERT @sink EXEC dbo.sp_EditManualJournalVoucher @parmrefno = @Ref, @parmcontrolno = @ctrl, @parmvoucherdate = @vdate, @parmremarks = @remarks,
         @parmuser = 'TEST86 EDITOR', @Lines = @LinesX, @AllowCrossBranch = 1;
    SELECT @st = Status FROM @sink;
    INSERT @res VALUES ('T9b new proc, other ticket under the number', CASE WHEN @st = 1 AND (SELECT COUNT(*) FROM TicketMaster WHERE TicketNumber = '9999986') = 1 AND (SELECT COUNT(*) FROM TicketDetails WHERE TicketNumber = '9999986') = 2 THEN 'PASS' ELSE 'FAIL' END,
                       CONCAT('Status ', @st, '; other ticket rows left: ', (SELECT COUNT(*) FROM TicketMaster WHERE TicketNumber = '9999986') + (SELECT COUNT(*) FROM TicketDetails WHERE TicketNumber = '9999986'), ' of 3'));
END TRY BEGIN CATCH INSERT @res VALUES ('T9b new proc, other ticket under the number', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T10 a refused edit (out of balance, 59208) leaves the voucher as it was
------------------------------------------------------------------
DELETE @LinesX; INSERT @LinesX SELECT * FROM @Lines;
UPDATE @LinesX SET Debit = Debit + 1 WHERE [LineNo] = (SELECT MIN([LineNo]) FROM @LinesX WHERE Debit > 0);
BEGIN TRAN;
BEGIN TRY
    -- called directly: a refused proc cannot roll back inside INSERT ... EXEC (3915)
    EXEC dbo.sp_EditManualJournalVoucher @parmrefno = @Ref, @parmcontrolno = @ctrl, @parmvoucherdate = @vdate, @parmremarks = @remarks,
         @parmuser = 'TEST86 EDITOR', @Lines = @LinesX, @AllowCrossBranch = 1;
    INSERT @res VALUES ('T10 refused edit 59208', 'FAIL', 'not refused');
END TRY BEGIN CATCH
    SET @err = ERROR_NUMBER();
    IF @@TRANCOUNT > 0 ROLLBACK;
    INSERT @res VALUES ('T10 refused edit 59208', CASE WHEN @err = 59208 AND (SELECT STRING_AGG(CAST(VoucherID AS VARCHAR(12)), ',') WITHIN GROUP (ORDER BY VoucherID) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref) = @vids THEN 'PASS' ELSE 'FAIL' END,
                       CONCAT(@err, ' ', LEFT(ERROR_MESSAGE(), 120)));
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
-- T11 a voucher whose GL ticket is damaged (a debit line missing): an untouched save re-posts it (Save still repairs),
--     and the preparer is kept
------------------------------------------------------------------
BEGIN TRAN;
BEGIN TRY
    DELETE TOP (1) FROM TicketDetails WHERE ReferenceNumber = @Ref AND Debit > 0
      AND TicketNumber IN (SELECT TicketNumber FROM ManualJournalVoucher WHERE ReferenceNo = @Ref);
    DELETE @sink;
    INSERT @sink EXEC dbo.sp_EditManualJournalVoucher @parmrefno = @Ref, @parmcontrolno = @ctrl, @parmvoucherdate = @vdate, @parmremarks = @remarks,
         @parmuser = 'TEST86 EDITOR', @Lines = @Lines, @AllowCrossBranch = @cross;
    SELECT @st = Status FROM @sink;
    SELECT @dr = SUM(Debit), @cr = SUM(Credit) FROM TicketDetails WHERE ReferenceNumber = @Ref AND TicketNumber IN (SELECT TicketNumber FROM ManualJournalVoucher WHERE ReferenceNo = @Ref);
    INSERT @res VALUES ('T11 damaged GL ticket, untouched save', CASE WHEN @st = 1 AND @dr = @cr AND @dr = (SELECT SUM(TotalAmount) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref)
                            AND (SELECT MAX(PreparedBy) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref) = @prep THEN 'PASS' ELSE 'FAIL' END,
                       CONCAT('Status ', @st, '; ticket DR ', @dr, ' CR ', @cr, ' = voucher total ', (SELECT SUM(TotalAmount) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref), '; preparer ', (SELECT MAX(PreparedBy) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref)));
END TRY BEGIN CATCH INSERT @res VALUES ('T11 damaged GL ticket, untouched save', 'ERROR', CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE())); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;

------------------------------------------------------------------
INSERT @res VALUES ('nothing left behind', CASE WHEN @@TRANCOUNT = 0 AND NOT EXISTS (SELECT 1 FROM ManualJournalVoucher WHERE PreparedBy LIKE 'TEST86%' OR LastModifiedBy LIKE 'TEST86%')
                                                 AND NOT EXISTS (SELECT 1 FROM TicketMaster WHERE TicketNumber = '9999986' OR EnteredBy LIKE 'TEST86%')
                                                 AND (SELECT STRING_AGG(CAST(VoucherID AS VARCHAR(12)), ',') WITHIN GROUP (ORDER BY VoucherID) FROM ManualJournalVoucher WHERE ReferenceNo = @Ref) = @vids THEN 'PASS' ELSE 'FAIL' END,
                    'no TEST86 rows, voucher as before, no open transaction');
SELECT Seq, Test, Result, Detail FROM @res ORDER BY Seq;
