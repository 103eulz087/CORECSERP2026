/* ================================================================
   2026-10-12e - Supplier voucher reversal: put back the amount settled, not the cash (telegraphic FX variance)
   ================================================================
   Bug: sp_CancelledChequesCS (Supplier Voucher Reversal, via sp_ReverseCombinedSupplierVoucher) restores an
   invoice's balance from the voucher's APPaymentDetails rows. The cash / check screen
   (sp_AddPaymentSupplierCompound_V2) writes a PURCHASE variance as its own 'VARIANCE' row, which the reversal
   reads. The telegraphic / manual screen (sp_PostVoucherManual) keeps it in the 'INVOICE PAYMENT' (or
   'EXPENSE PAYMENT') row's Variance column, with Amount = the cash, and settles cash - Variance. The reversal
   never read that column, so it put back only the cash.
   Example (STAGING): PRIBLET SI-202511470, 3,279,561.30. Voucher 38580 settled it with 3,209,561.30 cash and
   a 70,000.00 FX gain (Variance -70,000). Its reversal put back 3,209,561.30, voucher 38581 paid that, and the
   invoice showed FULLYPAID while the supplier ledger and the GL still owed 70,000.00.

   1. sp_CancelledChequesCS (anchor patch; backup sp_CancelledChequesCS_OLD_10122026230000; no parameter or
      exe change):
      * PURCHASE balance: the variance = 'VARIANCE' rows + the Variance column of 'INVOICE PAYMENT' rows (NULL
        on the cash / check screen's rows, so their reversals are unchanged). Balance += cash - variance + ...,
        the same rule the posting used.
      * PURCHASE AmountPaid / EWTAmount / Discount / OffsetAmount: the reversal subtracted all four, but the
        cash / check screen never adds to them (it moves Balance and PayStatus only) and the telegraphic
        screen adds only its cash to AmountPaid. So a cash / check purchase reversal drove AmountPaid (and
        EWTAmount, ...) negative (DEV test: AmountPaid -396,128.57). Now only the telegraphic screen's cash
        comes off AmountPaid (rows with a ticket; the cash / check screen's purchase rows have none), floored
        at 0, and EWTAmount / Discount / OffsetAmount are left alone. No APACCOUNTS row is negative today on
        DEV or STAGING, and neither has purchase rows from other writers (checked 2026-10-12).
      * PURCHASE PayStatus after a reversal: FULLYPAID if nothing is left; PARTIAL if another payment of the
        invoice still stands; else UNPAID (it was UNPAID whenever anything was left).
      * EXPENSE: the balance (and ExpenseMaster lines) get back the amount settled = Amount - Variance; the
        AmountPaid gets back the cash (Amount), as posted. Rows of the cash / check screen have no Variance,
        so their reversals are unchanged. No expense was hurt by the old rule on DEV or STAGING (no reversed
        expense row has a Variance); part 2 lists any it finds.
      * "Already reversed": also when PaymentReversalAudit has this voucher or its TelegraphicVoucher /
        CashVoucher row is already voided (only CheckVoucher was checked, so a telegraphic or cash voucher
        could be reversed twice). An applock per supplier + voucher ('APREV:...') makes two reversals of the
        same voucher at the same time wait for each other, so the second one sees the first.
   2. Data repair of purchases the old rule left short, from the defect itself: an invoice gets back what the
      old reversal didn't put back (minus the Variance column of its reversed vouchers' INVOICE PAYMENT rows),
      and only when the result agrees with ActualCost - what the vouchers still standing settled (else it is
      listed and skipped: something else touched that invoice). Rows locked while read; the UPDATE re-checks
      the balance read. Backup table APACCOUNTS_RevVariance_Backup_20261012.
      STAGING: PRIBLET (supplier 000125, SequenceNo 15) 0.00 FULLYPAID -> 70,000.00 PARTIAL. DEV: none.
      No GL or ledger change: both already owe the 70,000.00. Read-only lists: anything skipped, and any
      expense the old rule left short (none on DEV / STAGING).

   One transaction with a post-check. Run on DEV, then STAGING, then PRODUCTION (user).
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
BEGIN TRANSACTION;
CREATE TABLE #Patch (Id INT IDENTITY PRIMARY KEY, Obj SYSNAME NOT NULL, OldText NVARCHAR(MAX) NOT NULL, NewText NVARCHAR(MAX) NOT NULL);
GO

CREATE PROCEDURE #ApplyPatch @Obj SYSNAME
AS
BEGIN
    DECLARE @def NVARCHAR(MAX) = REPLACE(OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + @Obj)), NCHAR(13) + NCHAR(10), NCHAR(10));
    DECLARE @msg NVARCHAR(400);
    IF @def IS NULL
    BEGIN
        SET @msg = N'Cannot read the definition of ' + @Obj + N'; nothing changed.';
        THROW 59960, @msg, 1;
    END
    IF EXISTS (SELECT 1 FROM #Patch WHERE Obj = @Obj
               AND (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, OldText, N''))) / DATALENGTH(OldText) <> 1)
    BEGIN
        SET @msg = @Obj + N' text differs from the expected version (an anchor is missing or repeated); nothing changed.';
        THROW 59961, @msg, 1;
    END
    DECLARE @o NVARCHAR(MAX), @n NVARCHAR(MAX);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT OldText, NewText FROM #Patch WHERE Obj = @Obj ORDER BY Id;
    OPEN c; FETCH NEXT FROM c INTO @o, @n;
    WHILE @@FETCH_STATUS = 0 BEGIN SET @def = REPLACE(@def, @o, @n); FETCH NEXT FROM c INTO @o, @n; END
    CLOSE c; DEALLOCATE c;
    DECLARE @old SYSNAME = @Obj + N'_OLD_10122026230000', @full NVARCHAR(300) = N'dbo.' + @Obj;
    EXEC sp_rename @full, @old;
    EXEC (@def);
    IF OBJECT_ID(@full) IS NULL
    BEGIN
        SET @msg = @Obj + N' was not recreated.';
        THROW 59962, @msg, 1;
    END
END
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
IF OBJECT_ID('dbo.sp_CancelledChequesCS_OLD_10122026230000', 'P') IS NOT NULL OR OBJECT_ID('dbo.APACCOUNTS_RevVariance_Backup_20261012', 'U') IS NOT NULL
BEGIN
    RAISERROR('This script has been run here before (sp_CancelledChequesCS_OLD_10122026230000 or APACCOUNTS_RevVariance_Backup_20261012 exists).', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── 2 (first, against the old rule's results). Data repair ───────
-- The vouchers reversed so far, by voucher + supplier + reference
SELECT DISTINCT LTRIM(RTRIM(CAST(VoucherID AS VARCHAR(20)))) AS VoucherID, SupplierID, LTRIM(RTRIM(CAST(ReferenceNumber AS VARCHAR(20)))) AS Ref
INTO #Rev
FROM dbo.PaymentReversalAudit WHERE ReferenceNumber IS NOT NULL AND VoucherID IS NOT NULL;

CREATE TABLE #Cand (SupplierID VARCHAR(50) NOT NULL, SequenceNo DECIMAL(38,0) NOT NULL, OldBalance DECIMAL(18,2) NOT NULL, ActualCost DECIMAL(18,2) NOT NULL,
                    Missing DECIMAL(18,2) NOT NULL, Standing DECIMAL(18,2) NOT NULL, HasStanding BIT NOT NULL, PRIMARY KEY (SupplierID, SequenceNo));
;WITH p AS (
    SELECT d.SupplierID, TRY_CAST(d.SequenceReferenceNumber AS DECIMAL(38,0)) AS Seq, d.PaymentType, d.Amount, d.Variance,
           CASE WHEN EXISTS (SELECT 1 FROM #Rev AS r WHERE r.VoucherID = LTRIM(RTRIM(d.VoucherID)) AND r.SupplierID = d.SupplierID
                                                       AND r.Ref = LTRIM(RTRIM(d.ReferenceNumber))) THEN 1 ELSE 0 END AS IsRev
    FROM dbo.APPaymentDetails AS d
    WHERE d.PaymentMethod = 'PURCHASE' AND d.BatchReferenceID IS NULL),
agg AS (
    SELECT SupplierID, Seq,
           -- what the old reversal didn't put back: the Variance column of reversed INVOICE PAYMENT rows
           SUM(CASE WHEN IsRev = 1 AND PaymentType = 'INVOICE PAYMENT' THEN -ISNULL(Variance, 0) ELSE 0 END) AS Missing,
           MAX(CASE WHEN IsRev = 1 AND PaymentType = 'INVOICE PAYMENT' AND ISNULL(Variance, 0) <> 0 THEN 1 ELSE 0 END) AS HasRevVariance,
           -- what the vouchers still standing settled (the posting procs' signs)
           SUM(CASE WHEN IsRev = 1 THEN 0
                    WHEN PaymentType = 'INVOICE PAYMENT' THEN Amount - ISNULL(Variance, 0)
                    WHEN PaymentType IN ('EWT', 'DISCOUNT', 'RETURNALLOWANCES', 'ADVANCEAPPLIED') THEN Amount
                    WHEN PaymentType IN ('VARIANCE', 'OVERPAY', 'OVERPAYEXPENSE') THEN -Amount ELSE 0 END) AS Standing,
           MAX(CASE WHEN IsRev = 0 THEN 1 ELSE 0 END) AS HasStanding
    FROM p WHERE Seq IS NOT NULL GROUP BY SupplierID, Seq)
INSERT INTO #Cand (SupplierID, SequenceNo, OldBalance, ActualCost, Missing, Standing, HasStanding)
SELECT a.SupplierID, a.SequenceNo, a.Balance, a.ActualCost, g.Missing, g.Standing, g.HasStanding
FROM agg AS g
INNER JOIN dbo.APACCOUNTS AS a WITH (UPDLOCK, HOLDLOCK) ON a.SupplierID = g.SupplierID AND a.SequenceNo = g.Seq
WHERE g.HasRevVariance = 1 AND g.Missing <> 0;

-- fixed only when the defect explains the whole difference (else listed and skipped)
SELECT c.*, CAST(c.OldBalance + c.Missing AS DECIMAL(18,2)) AS NewBalance,
       CASE WHEN ABS(c.OldBalance - (c.ActualCost - c.Standing)) <= 0.01 THEN 'OK: balance already right (nothing to repair)'
            WHEN ABS((c.OldBalance + c.Missing) - (c.ActualCost - c.Standing)) > 0.01 THEN 'SKIPPED: the balance has other changes; check by hand'
            WHEN c.OldBalance + c.Missing < 0 OR c.OldBalance + c.Missing > c.ActualCost THEN 'SKIPPED: the corrected balance would be outside 0..ActualCost'
            ELSE 'FIX' END AS Decision
INTO #Fix
FROM #Cand AS c;

SELECT a.* INTO dbo.APACCOUNTS_RevVariance_Backup_20261012
FROM dbo.APACCOUNTS AS a INNER JOIN #Fix AS f ON f.SupplierID = a.SupplierID AND f.SequenceNo = a.SequenceNo AND f.Decision = 'FIX';

UPDATE a
SET Balance = f.NewBalance,
    PayStatus = CASE WHEN f.NewBalance <= 0 THEN 'FULLYPAID' WHEN f.HasStanding = 1 THEN 'PARTIAL' ELSE 'UNPAID' END
FROM dbo.APACCOUNTS AS a
INNER JOIN #Fix AS f ON f.SupplierID = a.SupplierID AND f.SequenceNo = a.SequenceNo AND f.Decision = 'FIX'
WHERE a.Balance = f.OldBalance;
IF @@ROWCOUNT <> (SELECT COUNT(*) FROM #Fix WHERE Decision = 'FIX')
    THROW 59963, 'A purchase balance changed while the repair ran; nothing changed. Run the script again.', 1;

DECLARE @n INT = (SELECT COUNT(*) FROM #Fix WHERE Decision = 'FIX'), @s INT = (SELECT COUNT(*) FROM #Fix WHERE Decision LIKE 'SKIPPED%'), @msg NVARCHAR(400);
SET @msg = N'Purchase invoices repaired: ' + CAST(@n AS NVARCHAR(10)) + N'; skipped: ' + CAST(@s AS NVARCHAR(10))
         + N' (backup dbo.APACCOUNTS_RevVariance_Backup_20261012).';
PRINT @msg;
-- read-only lists for the person running it
SELECT f.SupplierID, f.SequenceNo, a.InvoiceNo, f.ActualCost, f.OldBalance, f.NewBalance, f.Missing, f.Standing, f.Decision
FROM #Fix AS f INNER JOIN dbo.APACCOUNTS AS a ON a.SupplierID = f.SupplierID AND a.SequenceNo = f.SequenceNo;
SELECT 'EXPENSE left short by an earlier reversal (not repaired here; check by hand)' AS Note, p.SupplierID, p.InvoiceNo, p.BatchReferenceID,
       LTRIM(RTRIM(p.ReferenceNumber)) AS ReversedRef, p.BranchCode, p.Amount AS Cash, p.Variance
FROM dbo.APPaymentDetails AS p
INNER JOIN #Rev AS r ON r.VoucherID = LTRIM(RTRIM(p.VoucherID)) AND r.SupplierID = p.SupplierID AND r.Ref = LTRIM(RTRIM(p.ReferenceNumber))
WHERE p.PaymentType = 'EXPENSE PAYMENT' AND ISNULL(p.Variance, 0) <> 0;
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── 1. the reversal ──────────────────────────────────────────────
DECLARE @LF NCHAR(1) = NCHAR(10);

-- already reversed: one at a time per voucher, and telegraphic / cash vouchers too
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_CancelledChequesCS',
    N'        IF EXISTS (' + @LF +
    N'            SELECT 1 FROM CheckVoucher' + @LF +
    N'            WHERE VoucherID = @parmvoucherid' + @LF +
    N'              AND SupplierID = @parmsupplierid' + @LF +
    N'              AND ReferenceNumber = @parmreferenceno' + @LF +
    N'              AND isErrorCorrect = 1' + @LF +
    N'        )' + @LF +
    N'            THROW 50050, ''Voucher already reversed.'', 1;',
    N'        -- 2026-10-12e: two reversals of the same voucher at the same time wait for each other (the second then sees the first)' + @LF +
    N'        DECLARE @RevLock INT, @RevLockName NVARCHAR(255) = N''APREV:'' + ISNULL(@parmsupplierid, '''') + N'':'' + ISNULL(@parmvoucherid, '''');' + @LF +
    N'        EXEC @RevLock = sp_getapplock @Resource = @RevLockName, @LockMode = ''Exclusive'', @LockOwner = ''Transaction'', @LockTimeout = 10000;' + @LF +
    N'        IF @RevLock < 0' + @LF +
    N'            THROW 60521, ''This voucher is being reversed by someone else right now. Please try again.'', 1;' + @LF + @LF +
    N'        IF EXISTS (' + @LF +
    N'            SELECT 1 FROM CheckVoucher' + @LF +
    N'            WHERE VoucherID = @parmvoucherid' + @LF +
    N'              AND SupplierID = @parmsupplierid' + @LF +
    N'              AND ReferenceNumber = @parmreferenceno' + @LF +
    N'              AND isErrorCorrect = 1' + @LF +
    N'        )' + @LF +
    N'            THROW 50050, ''Voucher already reversed.'', 1;' + @LF +
    N'        -- 2026-10-12e: telegraphic / cash vouchers too (only CheckVoucher was checked, so they could be reversed twice)' + @LF +
    N'        IF EXISTS (SELECT 1 FROM PaymentReversalAudit WHERE VoucherID = @parmvoucherid AND SupplierID = @parmsupplierid AND ReferenceNumber = @parmreferenceno)' + @LF +
    N'           OR EXISTS (SELECT 1 FROM TelegraphicVoucher WHERE VoucherID = @parmvoucherid AND SupplierID = @parmsupplierid AND ReferenceNumber = @parmreferenceno AND isErrorCorrect = 1)' + @LF +
    N'           OR EXISTS (SELECT 1 FROM CashVoucher WHERE VoucherID = @parmvoucherid AND SupplierID = @parmsupplierid AND ReferenceNumber = @parmreferenceno AND isErrorCorrect = 1)' + @LF +
    N'            THROW 50050, ''Voucher already reversed.'', 1;');

-- PURCHASE: only the telegraphic screen's cash came onto AmountPaid; nothing came onto EWTAmount / Discount / OffsetAmount
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_CancelledChequesCS',
    N'                SUM(CASE WHEN PaymentType = ''INVOICE PAYMENT''  THEN Amount ELSE 0 END) AS Paid,',
    N'                SUM(CASE WHEN PaymentType = ''INVOICE PAYMENT''  THEN Amount ELSE 0 END) AS Paid,' + @LF +
    N'                -- 2026-10-12e: the cash the telegraphic screen (sp_PostVoucherManual) added to AmountPaid; its rows carry' + @LF +
    N'                -- a ticket, the cash / check screen''s purchase rows don''t (that screen never touches AmountPaid)' + @LF +
    N'                SUM(CASE WHEN PaymentType = ''INVOICE PAYMENT'' AND NULLIF(LTRIM(RTRIM(ISNULL(TicketNumber, ''''))), '''') IS NOT NULL' + @LF +
    N'                         THEN Amount ELSE 0 END) AS PaidOnAccount,');
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_CancelledChequesCS',
    N'                A.AmountPaid   = A.AmountPaid   - D.Paid,' + @LF +
    N'                A.EWTAmount    = A.EWTAmount    - D.EWT,' + @LF +
    N'                A.Discount     = A.Discount     - D.Discount,' + @LF +
    N'                A.OffsetAmount = A.OffsetAmount - D.Offset,',
    N'                -- 2026-10-12e: only what a posting added (EWTAmount / Discount / OffsetAmount are never added to)' + @LF +
    N'                A.AmountPaid   = CASE WHEN ISNULL(A.AmountPaid, 0) - D.PaidOnAccount < 0 THEN 0' + @LF +
    N'                                      ELSE ISNULL(A.AmountPaid, 0) - D.PaidOnAccount END,');

-- PURCHASE: the telegraphic screen's variance sits in the INVOICE PAYMENT row's Variance column
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_CancelledChequesCS',
    N'                SUM(CASE WHEN PaymentType = ''VARIANCE''         THEN Amount ELSE 0 END) AS Variance,',
    N'                -- 2026-10-12e: + the Variance column of INVOICE PAYMENT rows (sp_PostVoucherManual keeps it there;' + @LF +
    N'                -- NULL on the cash / check screen''s rows, which write a separate VARIANCE row instead)' + @LF +
    N'                SUM(CASE WHEN PaymentType = ''VARIANCE''         THEN Amount' + @LF +
    N'                         WHEN PaymentType = ''INVOICE PAYMENT''  THEN ISNULL(Variance, 0) ELSE 0 END) AS Variance,');

-- PURCHASE PayStatus: PARTIAL only while another payment of the invoice stands
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_CancelledChequesCS',
    N'                A.PayStatus    = CASE' + @LF +
    N'                    WHEN A.Balance + (D.Paid + D.EWT + D.Discount + D.Offset - D.Variance' + @LF +
    N'                                      + D.AdvanceApplied - D.OverPay - D.OverPayExpense) > 0' + @LF +
    N'                    THEN ''UNPAID'' ELSE ''FULLYPAID'' END',
    N'                -- 2026-10-12e: PARTIAL while another payment of the invoice still stands (was UNPAID)' + @LF +
    N'                A.PayStatus    = CASE' + @LF +
    N'                    WHEN A.Balance + (D.Paid + D.EWT + D.Discount + D.Offset - D.Variance' + @LF +
    N'                                      + D.AdvanceApplied - D.OverPay - D.OverPayExpense) <= 0 THEN ''FULLYPAID''' + @LF +
    N'                    WHEN EXISTS (SELECT 1 FROM APPaymentDetails X' + @LF +
    N'                                 WHERE X.SupplierID = @parmsupplierid AND X.PaymentMethod = ''PURCHASE''' + @LF +
    N'                                   AND X.SequenceReferenceNumber = D.SequenceReferenceNumber AND X.VoucherID <> @parmvoucherid' + @LF +
    N'                                   AND NOT EXISTS (SELECT 1 FROM PaymentReversalAudit R WHERE R.VoucherID = X.VoucherID AND R.SupplierID = X.SupplierID))' + @LF +
    N'                    THEN ''PARTIAL'' ELSE ''UNPAID'' END');

-- EXPENSE: balance back by what was settled (Amount - Variance); AmountPaid back by the cash (Amount)
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_CancelledChequesCS',
    N'                SUM(Amount) AS TotalGross',
    N'                -- 2026-10-12e: settled = Amount - Variance (sp_PostVoucherManual''s rows; the cash / check screen''s' + @LF +
    N'                -- have no Variance) for the balance; the cash for AmountPaid' + @LF +
    N'                SUM(Amount - ISNULL(Variance, 0)) AS TotalGross,' + @LF +
    N'                SUM(Amount) AS TotalPaid');
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_CancelledChequesCS',
    N'                SELECT BatchReferenceID, InvoiceNo, SUM(TotalGross) AS TotalGross',
    N'                SELECT BatchReferenceID, InvoiceNo, SUM(TotalGross) AS TotalGross, SUM(TotalPaid) AS TotalPaid');
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_CancelledChequesCS',
    N'                ES.AmountPaid = CASE WHEN ES.AmountPaid - R.TotalGross < 0' + @LF +
    N'                                     THEN 0 ELSE ES.AmountPaid - R.TotalGross END,',
    N'                ES.AmountPaid = CASE WHEN ES.AmountPaid - R.TotalPaid < 0' + @LF +
    N'                                     THEN 0 ELSE ES.AmountPaid - R.TotalPaid END,');
EXEC #ApplyPatch N'sp_CancelledChequesCS';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

IF OBJECT_ID('dbo.sp_CancelledChequesCS', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_CancelledChequesCS_OLD_10122026230000', 'P') IS NULL
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS')) NOT LIKE '%WHEN PaymentType = ''INVOICE PAYMENT''  THEN ISNULL(Variance, 0)%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS')) NOT LIKE '%SUM(Amount - ISNULL(Variance, 0)) AS TotalGross%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS')) NOT LIKE '%SUM(TotalPaid) AS TotalPaid%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS')) NOT LIKE '%ES.AmountPaid - R.TotalPaid%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS')) NOT LIKE '%AS PaidOnAccount,%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS')) LIKE '%A.EWTAmount    = A.EWTAmount    - D.EWT,%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS')) NOT LIKE '%THEN ''PARTIAL'' ELSE ''UNPAID'' END%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS')) NOT LIKE '%FROM PaymentReversalAudit WHERE VoucherID = @parmvoucherid%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS')) NOT LIKE '%APREV:%'
   OR OBJECT_ID('dbo.APACCOUNTS_RevVariance_Backup_20261012', 'U') IS NULL
BEGIN
    RAISERROR('Post-check failed; rolled back.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
COMMIT TRANSACTION;
PRINT 'sp_CancelledChequesCS fixed (variance on reversal, AmountPaid, status, double reversal) and purchase balances repaired.';
GO
SET NOEXEC OFF;
GO
