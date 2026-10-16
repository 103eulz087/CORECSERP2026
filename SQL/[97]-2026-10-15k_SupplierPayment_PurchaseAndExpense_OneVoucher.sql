/* ================================================================
   [97] 2026-10-15k  Supplier Payment (cash / check): purchases and expenses
                     in one list and one voucher
   ================================================================
   User (2026-10-14 / 15): AccountingDevEx/SupplierPaymentDevEx drops the
   Purchase / Expense radio buttons, lists both kinds of a supplier's open
   invoices together, and one voucher (one cheque) may pay both. Telegraphic
   (VoucheringManualFrm) is NOT changed ("we will see first the cash and
   check"). Plan: docs/plans/2026-10-14_SupplierPayment_CombinedPurchaseExpense_Plan.md.

   WHY IN SQL: one sp_AddPaymentSupplierCompound_V2 call writes the voucher's
   TransactionPaymentAP row, its bank-recon OC and its voucher header. Two calls
   for one cheque would write two of each (since [88] the second OC is refused
   93021; before, silently dropped: Known Bug #9). So:

   RULES
   - a voucher with ONE kind keeps today's exact path (same parameters, same rows)
   - a MIXED voucher (sp_PostSupplierPaymentWithManualLines with the new optional
     @PurchaseLines / @PurchaseLineExtras + the expense lines in @InvoiceLines):
       * cash / check only (60232); @PurchaseLines only together with expense
         lines (60231 / 60233)
       * voucher-wide rules checked once across both kinds: OverPay on one invoice
         per voucher (60513); Advance Applied <= the supplier's credit pool, read
         under the same APCREDIT applock as V2 (60514 / 60517)
       * V2 runs twice (PURCHASE, then EXPENSE) with the new @SkipVoucherWrap = 1:
         invoice tickets, payment rows (APPaymentDetails.PaymentMethod per kind),
         supplier ledger and invoice balances as today, but no voucher-level rows;
         each returns its net cash (@NetCashOut)
       * then ONE TransactionPaymentAP row (amount = the screen's invoice total),
         ONE OC (purchase + expense net cash, paying branch else 888), ONE voucher
         header; manual debit lines and the combined-total step work as before
   - reversal (sp_CancelledChequesCS): a voucher whose payment rows carry both
     PaymentMethods is MIXED whatever the caller sends: the purchase block and the
     expense block both run (each already filters its own PaymentMethod), then
     the per-voucher steps once. The whole voucher is reversed (one cheque).
   - list (splist_Accounts): both flags = 1 returns purchases + expenses (same
     columns, Type PURCHASE / EXPENSE), by invoice date. One flag = as before
     (VoucheringManualFrm and the old screen send one flag).
   - "Invoices (as paid)" (sp_GetSupplierVoucherInvoiceView) already classifies
     each row on its own: no change.

   DEPENDENCY: needs [88] (H7) on the database: the guard takes the [88] text of
   sp_PostSupplierPaymentWithManualLines. On STAGING / PRODUCTION run [88] first.
   Guard = the four live texts (whitespace-insensitive SHA-256; V2, splist_Accounts
   and sp_CancelledChequesCS identical on DEV / STAGING / PRODUCTION 2026-10-15).
   One transaction with a post-check; backups _OLD_10152026220000. The old exe
   keeps working (single-kind vouchers only); the new exe sends mixed vouchers.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET LOCK_TIMEOUT 10000;
GO

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[97] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2')) LIKE '%@SkipVoucherWrap%'
BEGIN
    RAISERROR('[97] already applied in this database; nothing changed.', 10, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostSupplierPaymentWithManualLines')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> 'FC4FA0335AC89DF19B20DCEB67078A1B36A0407686CE0FB429F8D3530184D4AE'
BEGIN
    RAISERROR('[97] stopped: sp_PostSupplierPaymentWithManualLines is not the [88] text (run [88] first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
            <> '359BC7616EE405820AFAED876BA2559B4E98523C47A9863ED6641CC7649A239F'
     OR CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.splist_Accounts')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
            <> '11C2EF1666AA20B5A4A1F236254CD0AF565A05234CBC44645AD07BC9BE4593AC'
     OR CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
            <> '4FD43ECBEA97F5AC77C26063E960BEF09EFC56AECAE51EBFEB440F08F89CB3C9'
BEGIN
    RAISERROR('[97] stopped: sp_AddPaymentSupplierCompound_V2 / splist_Accounts / sp_CancelledChequesCS is not the text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[97] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
GO

------------------------------------------------------------------
-- 1. sp_AddPaymentSupplierCompound_V2: optional @SkipVoucherWrap / @NetCashOut (anchor patches)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2'));
DECLARE @p TABLE (n INT IDENTITY, Anchor NVARCHAR(400), Repl NVARCHAR(MAX));
DECLARE @nl NCHAR(2) = NCHAR(13) + NCHAR(10);
INSERT INTO @p (Anchor, Repl) VALUES
 (N'@LineExtras         [dbo].[AP_PaymentLineExtraTVP] READONLY   -- NEW 2026-09-24, optional (empty when omitted)',
  N'@LineExtras         [dbo].[AP_PaymentLineExtraTVP] READONLY,  -- NEW 2026-09-24, optional (empty when omitted)' + @nl
  + N'    @SkipVoucherWrap    BIT          = 0,      -- [97] 1 = invoice lines only: no TransactionPaymentAP / OC / voucher header (a mixed voucher writes them once)' + @nl
  + N'    @NetCashOut         DECIMAL(18,2) = NULL OUTPUT   -- [97] the net cash these lines disbursed'),
 (N'        SELECT @SeqNo = ISNULL(MAX(SEQ_NO),0) + 1 FROM TransactionPaymentAP WHERE SupplierKey = @SupplierKey;',
  N'        IF ISNULL(@SkipVoucherWrap, 0) = 0   -- [97]' + @nl + N'        BEGIN' + @nl
  + N'        SELECT @SeqNo = ISNULL(MAX(SEQ_NO),0) + 1 FROM TransactionPaymentAP WHERE SupplierKey = @SupplierKey;'),
 (N'@parmcheckdate, @parmpreparedby, GETDATE(), @parmpreparedby, 0);',
  N'@parmcheckdate, @parmpreparedby, GETDATE(), @parmpreparedby, 0);' + @nl + N'        END   -- [97]'),
 (N'IF @TotalNetCashForRecon <> 0',
  N'IF @TotalNetCashForRecon <> 0 AND ISNULL(@SkipVoucherWrap, 0) = 0   -- [97]'),
 (N'SET @Remarks2 = ''Auto-OC | Ref: '' + ISNULL(@parmrefno, '''');',
  N'SET @Remarks2 = ''Auto-OC | Ref: '' + ISNULL(@parmrefno, '''');' + @nl
  + N'            IF ISNULL(@SkipVoucherWrap, 0) = 0   -- [97] a mixed voucher posts its one OC in sp_PostSupplierPaymentWithManualLines'),
 (N'EXEC sp_Payment_CreateVoucherHeader',
  N'IF ISNULL(@SkipVoucherWrap, 0) = 0   -- [97]' + @nl + N'            EXEC sp_Payment_CreateVoucherHeader'),
 (N'DROP TABLE #Lines;',
  N'SET @NetCashOut = @TotalNetCashForRecon;   -- [97]' + @nl + N'        DROP TABLE #Lines;');
DECLARE @i INT = 1, @a NVARCHAR(400), @r NVARCHAR(MAX), @cnt INT, @m NVARCHAR(400);
WHILE @i <= (SELECT MAX(n) FROM @p)
BEGIN
    SELECT @a = Anchor, @r = Repl FROM @p WHERE n = @i;
    SET @cnt = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @a, N''))) / DATALENGTH(@a);
    IF @cnt <> 1
    BEGIN
        SET @m = N'[97] V2 anchor ' + CAST(@i AS NVARCHAR(5)) + N' found ' + CAST(@cnt AS NVARCHAR(5)) + N' times.';
        THROW 59898, @m, 1;
    END
    SET @def = REPLACE(@def, @a, @r);
    SET @i += 1;
END
EXEC sp_rename 'dbo.sp_AddPaymentSupplierCompound_V2', 'sp_AddPaymentSupplierCompound_V2_OLD_10152026220000';
EXEC (@def);
GO

------------------------------------------------------------------
-- 2. splist_Accounts: both flags = purchases + expenses together
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.splist_Accounts'));
DECLARE @a NVARCHAR(400) = N'    -- PURCHASE' + NCHAR(10), @a2 NVARCHAR(400) = N'    -- PURCHASE' + NCHAR(13) + NCHAR(10), @cnt INT;
DECLARE @nl NCHAR(2) = NCHAR(13) + NCHAR(10);
DECLARE @both NVARCHAR(MAX) =
  CAST(N'' AS NVARCHAR(MAX)) + N'    -- [97] 2026-10-15: both flags = purchases and expenses of the supplier in one list (SupplierPaymentDevEx, cash / check).' + @nl
+ N'    --      Same columns as the one-kind lists below (keep the three in step); Type tells the kind.' + @nl
+ N'    IF (@parmispurchase = 1 AND @parmisexpense = 1)' + @nl
+ N'    BEGIN' + @nl
+ N'        SELECT x.SequenceNumber, x.Pay, x.ShipmentNo, x.BranchCode, x.ReferenceNo, x.BatchReferenceID, x.InvoiceNo, x.InvoiceDate,' + @nl
+ N'               x.Description, x.ActualCost, x.Balance, x.AmountPaid, x.Variance, x.EWTAmount, x.DiscountAmount, x.DiscountAccountCode,' + @nl
+ N'               x.ReturnAllowances, x.Type' + @nl
+ N'        FROM (' + @nl
+ N'            SELECT CAST(a.SequenceNo AS BIGINT) AS SequenceNumber, CAST(''NONE'' AS VARCHAR(15)) AS Pay, a.ShipmentNo, b.BranchCode,' + @nl
+ N'                   CAST(a.InvoiceNo AS VARCHAR(150)) AS ReferenceNo, CAST(0 AS BIGINT) AS BatchReferenceID, CAST(a.InvoiceNo AS VARCHAR(150)) AS InvoiceNo,' + @nl
+ N'                   a.InvoiceDate, CAST(ISNULL(CAST(a.InvoiceNo AS VARCHAR(50)), '' '') AS VARCHAR(5000)) AS Description,' + @nl
+ N'                   CAST(ISNULL(a.ActualCost, 0) AS DECIMAL(12,2)) AS ActualCost, CAST(ISNULL(a.Balance, 0) AS DECIMAL(12,2)) AS Balance,' + @nl
+ N'                   CAST(0 AS DECIMAL(12,2)) AS AmountPaid, CAST(0 AS DECIMAL(12,2)) AS Variance, CAST(0 AS DECIMAL(12,2)) AS EWTAmount,' + @nl
+ N'                   CAST(0 AS DECIMAL(12,2)) AS DiscountAmount, CAST(NULL AS VARCHAR(20)) AS DiscountAccountCode,' + @nl
+ N'                   CAST(0 AS DECIMAL(12,2)) AS ReturnAllowances, CAST(''PURCHASE'' AS VARCHAR(30)) AS Type' + @nl
+ N'            FROM dbo.APACCOUNTS a' + @nl
+ N'            INNER JOIN POSUMMARY b ON a.ShipmentNo = b.ShipmentNo' + @nl
+ N'            WHERE a.PayStatus IN (''UNPAID'',''PARTIAL'') AND a.Balance > 0 AND a.SupplierID = @parmsupplierid' + @nl
+ N'            UNION ALL' + @nl
+ N'            SELECT CAST(es.BatchReferenceID AS BIGINT), CAST(''NONE'' AS VARCHAR(15)), CAST('''' AS VARCHAR(10)),' + @nl
+ N'                   (SELECT TOP 1 em2.BranchCode FROM ExpenseMaster em2' + @nl
+ N'                    WHERE em2.SupplierID = es.SupplierID AND em2.InvoiceNo = es.InvoiceNo AND em2.BatchReferenceID = es.BatchReferenceID' + @nl
+ N'                    ORDER BY em2.TRN_SEQ_NO),' + @nl
+ N'                   CAST(es.ReferenceNumber AS VARCHAR(150)), es.BatchReferenceID, CAST(es.InvoiceNo AS VARCHAR(150)), es.ExpenseDate,' + @nl
+ N'                   CAST(es.Description AS VARCHAR(5000)),' + @nl
+ N'                   CAST(ISNULL(es.Amount, 0) AS DECIMAL(12,2)), CAST(ISNULL(es.Balance, ISNULL(es.Amount, 0)) AS DECIMAL(12,2)),' + @nl
+ N'                   CAST(ISNULL(es.AmountPaid, 0) AS DECIMAL(12,2)), CAST(0 AS DECIMAL(12,2)),' + @nl
+ N'                   CAST(CASE WHEN ISNULL(es.EWTAmount,0) - ISNULL(es.EWTWithheld,0) < 0 THEN 0 ELSE ISNULL(es.EWTAmount,0) - ISNULL(es.EWTWithheld,0) END AS DECIMAL(12,2)),' + @nl
+ N'                   CAST(CASE WHEN ISNULL(es.DiscountAmount,0) - ISNULL(es.DiscountWithheld,0) < 0 THEN 0 ELSE ISNULL(es.DiscountAmount,0) - ISNULL(es.DiscountWithheld,0) END AS DECIMAL(12,2)),' + @nl
+ N'                   CAST(NULL AS VARCHAR(20)),' + @nl
+ N'                   CAST(CASE WHEN ISNULL(es.OffsetAmount,0) - ISNULL(es.OffsetWithheld,0) < 0 THEN 0 ELSE ISNULL(es.OffsetAmount,0) - ISNULL(es.OffsetWithheld,0) END AS DECIMAL(12,2)),' + @nl
+ N'                   CAST(''EXPENSE'' AS VARCHAR(30))' + @nl
+ N'            FROM dbo.ExpenseSummary es' + @nl
+ N'            WHERE es.SupplierID = @parmsupplierid' + @nl
+ N'              AND es.Status NOT IN (''PAID'',''VOID'',''CANCELLED'',''FOR APPROVAL'',''FULLYPAID'')' + @nl
+ N'              AND ISNULL(es.Balance, ISNULL(es.Amount, 0)) > 0' + @nl
+ N'        ) AS x' + @nl
+ N'        ORDER BY x.InvoiceDate, x.Type, x.InvoiceNo;' + @nl
+ N'        RETURN;' + @nl
+ N'    END;' + @nl + @nl;
SET @cnt = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @a2, N''))) / DATALENGTH(@a2);
IF @cnt = 1
    SET @def = REPLACE(@def, @a2, @both + @a2);
ELSE
BEGIN
    SET @cnt = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @a, N''))) / DATALENGTH(@a);
    IF @cnt <> 1 THROW 59898, '[97] splist_Accounts anchor (-- PURCHASE) not found exactly once.', 1;
    SET @def = REPLACE(@def, @a, @both + @a);
END
EXEC sp_rename 'dbo.splist_Accounts', 'splist_Accounts_OLD_10152026220000';
EXEC (@def);
GO

------------------------------------------------------------------
-- 3. sp_PostSupplierPaymentWithManualLines: the mixed voucher (anchor patches on the [88] text)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostSupplierPaymentWithManualLines'));
DECLARE @nl NCHAR(2) = NCHAR(13) + NCHAR(10);
DECLARE @p TABLE (n INT IDENTITY, Anchor NVARCHAR(400), Repl NVARCHAR(MAX));
INSERT INTO @p (Anchor, Repl) VALUES
 (N'@InvoiceLineExtras dbo.AP_PaymentLineExtraTVP READONLY   -- 2026-09-24, optional',
  N'@InvoiceLineExtras dbo.AP_PaymentLineExtraTVP READONLY,  -- 2026-09-24, optional' + @nl
  + N'    @PurchaseLines      dbo.AP_PaymentLineTVP READONLY,       -- [97] optional: the purchase invoices of a voucher that also pays expenses' + @nl
  + N'    @PurchaseLineExtras dbo.AP_PaymentLineExtraTVP READONLY   -- [97] optional: their OverPay / Advance extras'),
 (N'        -- 1. the invoice leg (expense / purchase settlement, voucher header, GL, ledger, bank recon)',
  CAST(N'' AS NVARCHAR(MAX)) + N'        -- [97] 2026-10-15: a cash / check voucher paying purchase AND expense invoices (SupplierPaymentDevEx). The purchases' + @nl
+ N'        -- come in @PurchaseLines, the expenses in @InvoiceLines. V2 posts each kind''s invoice lines (@SkipVoucherWrap = 1);' + @nl
+ N'        -- the voucher-level rows (TransactionPaymentAP, the OC, the voucher header) are written ONCE here.' + @nl
+ N'        DECLARE @PurchaseLineCount INT = (SELECT COUNT(*) FROM @PurchaseLines);' + @nl
+ N'        DECLARE @IsMixed BIT = 0;' + @nl
+ N'        IF @PurchaseLineCount > 0' + @nl
+ N'        BEGIN' + @nl
+ N'            IF @InvoiceLineCount = 0' + @nl
+ N'                THROW 60231, ''A voucher of purchase invoices only sends them in @InvoiceLines (@parmpaymethod PURCHASE); @PurchaseLines is for a voucher that also pays expenses.'', 1;' + @nl
+ N'            IF ISNULL(@parmvouchertype, '''') NOT IN (''CHECK'', ''CASH'')' + @nl
+ N'                THROW 60232, ''Purchases and expenses can be paid on one voucher only with a cash or check voucher.'', 1;' + @nl
+ N'            IF ISNULL(@parmpaymethod, '''') NOT IN (''EXPENSE'', ''MIXED'')' + @nl
+ N'                THROW 60233, ''With @PurchaseLines, @InvoiceLines must hold the expense invoices (@parmpaymethod EXPENSE or MIXED).'', 1;' + @nl
+ N'            SET @IsMixed = 1;' + @nl
+ N'        END' + @nl
+ @nl
+ N'        IF @IsMixed = 1' + @nl
+ N'        BEGIN' + @nl
+ N'            -- the date V2 would default for itself (a cash voucher may come without one)' + @nl
+ N'            IF @parmcheckdate IS NULL SET @parmcheckdate = CAST(GETDATE() AS DATE);' + @nl
+ N'            SET @EffectiveDate = @parmcheckdate;' + @nl
+ @nl
+ N'            -- voucher-wide rules across both kinds (each V2 call checks its own lines only)' + @nl
+ N'            IF (SELECT COUNT(*) FROM (SELECT InvoiceNo FROM @PurchaseLineExtras WHERE ISNULL(OverPay, 0) > 0 OR ISNULL(OverPayExpense, 0) > 0' + @nl
+ N'                                      UNION ALL' + @nl
+ N'                                      SELECT InvoiceNo FROM @InvoiceLineExtras WHERE ISNULL(OverPay, 0) > 0 OR ISNULL(OverPayExpense, 0) > 0) AS o) > 1' + @nl
+ N'                THROW 60513, ''OverPay / OverPay (Expense) must be assigned to only one invoice per voucher.'', 1;' + @nl
+ @nl
+ N'            DECLARE @MixAdvance DECIMAL(18,2) = ISNULL((SELECT SUM(ISNULL(AdvanceApplied, 0)) FROM @PurchaseLineExtras), 0)' + @nl
+ N'                                              + ISNULL((SELECT SUM(ISNULL(AdvanceApplied, 0)) FROM @InvoiceLineExtras), 0);' + @nl
+ N'            IF @MixAdvance > 0' + @nl
+ N'            BEGIN' + @nl
+ N'                DECLARE @MixLock INT, @MixLockRes NVARCHAR(255) = N''APCREDIT:'' + @parmsupplierid;   -- the lock V2 and the reversal take' + @nl
+ N'                EXEC @MixLock = sp_getapplock @Resource = @MixLockRes, @LockMode = ''Exclusive'', @LockOwner = ''Transaction'', @LockTimeout = 10000;' + @nl
+ N'                IF @MixLock < 0' + @nl
+ N'                    THROW 60517, ''Could not acquire a lock for this supplier''''s advance credit (another payment or reversal for the same supplier is in progress). Please try again.'', 1;' + @nl
+ N'                DECLARE @MixPool DECIMAL(18,2);' + @nl
+ N'                SELECT @MixPool = ISNULL(SUM(CASE WHEN d.PaymentType = ''OVERPAY'' THEN d.Amount ELSE 0 END), 0)' + @nl
+ N'                                - ISNULL(SUM(CASE WHEN d.PaymentType = ''ADVANCEAPPLIED'' THEN d.Amount ELSE 0 END), 0)' + @nl
+ N'                FROM APPaymentDetails d' + @nl
+ N'                WHERE d.SupplierID = @parmsupplierid AND d.PaymentType IN (''OVERPAY'', ''ADVANCEAPPLIED'') AND d.VoucherID <> @parmvoucherid' + @nl
+ N'                  AND NOT EXISTS (SELECT 1 FROM PaymentReversalAudit r WHERE r.VoucherID = d.VoucherID AND r.SupplierID = d.SupplierID);' + @nl
+ N'                IF @MixAdvance > ISNULL(@MixPool, 0)' + @nl
+ N'                BEGIN' + @nl
+ N'                    DECLARE @MixCreditMsg NVARCHAR(400) = N''Advance Applied ('' + CAST(@MixAdvance AS NVARCHAR(30))' + @nl
+ N'                        + N'') exceeds this supplier''''s available advance credit ('' + CAST(ISNULL(@MixPool, 0) AS NVARCHAR(30)) + N'').'';' + @nl
+ N'                    THROW 60514, @MixCreditMsg, 1;' + @nl
+ N'                END' + @nl
+ N'            END' + @nl
+ @nl
+ N'            DECLARE @MixPurchaseLeg DECIMAL(18,2) = (SELECT ISNULL(SUM(AmountPaid), 0) FROM @PurchaseLines),' + @nl
+ N'                    @MixExpenseLeg  DECIMAL(18,2) = (SELECT ISNULL(SUM(AmountPaid), 0) FROM @InvoiceLines),' + @nl
+ N'                    @MixPurchaseNet DECIMAL(18,2), @MixExpenseNet DECIMAL(18,2);' + @nl
+ @nl
+ N'            EXEC sp_AddPaymentSupplierCompound_V2' + @nl
+ N'                @parmrefno = @parmrefno, @parmvoucherid = @parmvoucherid, @parmsupplierid = @parmsupplierid, @parmsuppliername = @parmsuppliername,' + @nl
+ N'                @parmcheckamount = @MixPurchaseLeg, @parmcheckcoding = @parmcheckcoding, @parmcheckno = @parmcheckno, @parmcontrolno = @parmcontrolno,' + @nl
+ N'                @parmcheckdate = @parmcheckdate, @parmcheckremarks = @parmcheckremarks, @parmpreparedby = @parmpreparedby, @parmglcode = @parmglcode,' + @nl
+ N'                @parmpaymethod = ''PURCHASE'', @parmforliquidation = @parmforliquidation, @parmvouchertype = @parmvouchertype,' + @nl
+ N'                @Lines = @PurchaseLines, @parmPayingBranch = @parmPayingBranch, @LineExtras = @PurchaseLineExtras,' + @nl
+ N'                @SkipVoucherWrap = 1, @NetCashOut = @MixPurchaseNet OUTPUT;' + @nl
+ @nl
+ N'            EXEC sp_AddPaymentSupplierCompound_V2' + @nl
+ N'                @parmrefno = @parmrefno, @parmvoucherid = @parmvoucherid, @parmsupplierid = @parmsupplierid, @parmsuppliername = @parmsuppliername,' + @nl
+ N'                @parmcheckamount = @MixExpenseLeg, @parmcheckcoding = @parmcheckcoding, @parmcheckno = @parmcheckno, @parmcontrolno = @parmcontrolno,' + @nl
+ N'                @parmcheckdate = @parmcheckdate, @parmcheckremarks = @parmcheckremarks, @parmpreparedby = @parmpreparedby, @parmglcode = @parmglcode,' + @nl
+ N'                @parmpaymethod = ''EXPENSE'', @parmforliquidation = @parmforliquidation, @parmvouchertype = @parmvouchertype,' + @nl
+ N'                @Lines = @InvoiceLines, @parmPayingBranch = @parmPayingBranch, @LineExtras = @InvoiceLineExtras,' + @nl
+ N'                @SkipVoucherWrap = 1, @NetCashOut = @MixExpenseNet OUTPUT;' + @nl
+ @nl
+ N'            -- the voucher-level rows, once (same shapes as V2 writes them for a one-kind voucher)' + @nl
+ N'            DECLARE @MixSupplierKey VARCHAR(30), @MixSeqNo INT, @MixNet DECIMAL(18,2) = ISNULL(@MixPurchaseNet, 0) + ISNULL(@MixExpenseNet, 0);' + @nl
+ N'            SELECT @MixSupplierKey = SupplierKey FROM Supplier WHERE SupplierID = @parmsupplierid;' + @nl
+ N'            SELECT @MixSeqNo = ISNULL(MAX(SEQ_NO), 0) + 1 FROM TransactionPaymentAP WHERE SupplierKey = @MixSupplierKey;' + @nl
+ N'            INSERT INTO dbo.TransactionPaymentAP' + @nl
+ N'                (SEQ_NO, SupplierKey, ReferenceNumber, Amount, VoucherType, DatePaid, ExecuteBy, DateUpdate, UpdateBy, ErrorCorrect)' + @nl
+ N'            VALUES (@MixSeqNo, @MixSupplierKey, @parmrefno, ISNULL(@InvoiceLegAmount, 0), @parmvouchertype,' + @nl
+ N'                    @parmcheckdate, @parmpreparedby, GETDATE(), @parmpreparedby, 0);' + @nl
+ @nl
+ N'            IF @MixNet <> 0' + @nl
+ N'            BEGIN' + @nl
+ N'                DECLARE @MixOCBranch VARCHAR(5) = ISNULL(NULLIF(LTRIM(RTRIM(ISNULL(@parmPayingBranch, ''''))), ''''), ''888''),' + @nl
+ N'                        @MixOCPeriod DATE = EOMONTH(@parmcheckdate),' + @nl
+ N'                        @MixOCRemarks VARCHAR(500) = ''Auto-OC | Ref: '' + ISNULL(@parmrefno, '''') + '' | purchases + expenses'';' + @nl
+ N'                EXEC dbo.sp_Payment_PostBankReconEntry' + @nl
+ N'                    @ItemType = ''OC'', @BranchCode = @MixOCBranch, @AccountCode = @parmglcode, @PeriodEnd = @MixOCPeriod,' + @nl
+ N'                    @ReferenceNo = @parmvoucherid, @ItemDate = @parmcheckdate, @Payee = @parmsuppliername, @Amount = @MixNet,' + @nl
+ N'                    @Remarks = @MixOCRemarks, @SourceModule = ''AP-PAYMENT'', @SourceRef = @parmrefno, @CreatedBy = @parmpreparedby;' + @nl
+ N'            END' + @nl
+ @nl
+ N'            DECLARE @MixCheckOrControl VARCHAR(50) = CASE WHEN @parmvouchertype = ''CHECK'' THEN @parmcheckno ELSE @parmcontrolno END;' + @nl
+ N'            EXEC sp_Payment_CreateVoucherHeader' + @nl
+ N'                @VoucherType = @parmvouchertype, @VoucherID = @parmvoucherid, @SupplierID = @parmsupplierid, @ReferenceNumber = @parmrefno,' + @nl
+ N'                @PaidTo = @parmsuppliername, @CheckOrControlNo = @MixCheckOrControl, @CheckCoding = @parmcheckcoding, @VoucherDate = @parmcheckdate,' + @nl
+ N'                @Particulars = @parmcheckremarks, @Amount = @MixNet, @PreparedBy = @parmpreparedby, @ForLiquidation = @parmforliquidation,' + @nl
+ N'                @GLCode = @parmglcode;' + @nl
+ @nl
+ N'            -- the combined total with manual lines (step 3) = what the invoice lines really paid + the manual lines,' + @nl
+ N'            -- never the caller''s figure (Known Bug #5)' + @nl
+ N'            SET @GrandTotal = @MixNet + @ManualTotal;' + @nl
+ N'        END' + @nl
+ @nl
+ N'        -- [97] a one-kind voucher says which kind (a stray MIXED / other value would write payment rows the reversal never finds)' + @nl
+ N'        IF @IsMixed = 0 AND @InvoiceLineCount > 0 AND ISNULL(@parmpaymethod, '''') NOT IN (''PURCHASE'', ''EXPENSE'')' + @nl
+ N'            THROW 60234, ''@parmpaymethod must be PURCHASE or EXPENSE for a voucher of one kind (MIXED needs @PurchaseLines and expense @InvoiceLines).'', 1;' + @nl
+ @nl
+ N'        IF @IsMixed = 0   -- [97] one kind: today''s path' + @nl
+ N'        BEGIN' + @nl
+ N'        -- 1. the invoice leg (expense / purchase settlement, voucher header, GL, ledger, bank recon)'),
 (N'        COMMIT TRANSACTION;',
  CAST(N'' AS NVARCHAR(MAX)) + N'        -- [97] post-check of a mixed voucher: one header, one TransactionPaymentAP row, one open OC, all = the total' + @nl
+ N'        IF @IsMixed = 1' + @nl
+ N'        BEGIN' + @nl
+ N'            DECLARE @PcHeader DECIMAL(18,2) = CASE WHEN @parmvouchertype = ''CHECK''' + @nl
+ N'                         THEN (SELECT SUM(Amount) FROM CheckVoucher WHERE ReferenceNumber = @parmrefno AND VoucherID = @parmvoucherid)' + @nl
+ N'                         ELSE (SELECT SUM(Amount) FROM CashVoucher WHERE ReferenceNumber = @parmrefno AND VoucherID = @parmvoucherid) END,' + @nl
+ N'                    @PcHeaders INT = CASE WHEN @parmvouchertype = ''CHECK''' + @nl
+ N'                         THEN (SELECT COUNT(*) FROM CheckVoucher WHERE ReferenceNumber = @parmrefno AND VoucherID = @parmvoucherid)' + @nl
+ N'                         ELSE (SELECT COUNT(*) FROM CashVoucher WHERE ReferenceNumber = @parmrefno AND VoucherID = @parmvoucherid) END,' + @nl
+ N'                    @PcOC DECIMAL(18,2) = (SELECT ISNULL(SUM(Amount), 0) FROM BankStatementRecon' + @nl
+ N'                                           WHERE ReferenceNo = @parmvoucherid AND SourceModule = ''AP-PAYMENT'' AND SourceRef = @parmrefno AND ItemType = ''OC'' AND IsResolved = 0),' + @nl
+ N'                    @PcTPAP INT = (SELECT COUNT(*) FROM TransactionPaymentAP WHERE ReferenceNumber = @parmrefno),' + @nl
+ N'                    @PcExpect DECIMAL(18,2) = CASE WHEN @ManualLineCount > 0 THEN @GrandTotal ELSE @MixNet END;' + @nl
+ N'            IF @PcHeaders <> 1 OR @PcTPAP <> 1 OR ISNULL(@PcHeader, -1) <> @PcExpect OR @PcOC <> @PcExpect' + @nl
+ N'            BEGIN' + @nl
+ N'                DECLARE @PcMsg NVARCHAR(400) = N''Mixed voucher post-check failed (headers '' + CAST(@PcHeaders AS NVARCHAR(10)) + N'', payment rows '' + CAST(@PcTPAP AS NVARCHAR(10))' + @nl
+ N'                    + N'', header '' + ISNULL(CONVERT(NVARCHAR(30), @PcHeader), N''none'') + N'', OC '' + CONVERT(NVARCHAR(30), @PcOC) + N'', expected '' + CONVERT(NVARCHAR(30), @PcExpect) + N''); nothing was posted.'';' + @nl
+ N'                THROW 60235, @PcMsg, 1;' + @nl
+ N'            END' + @nl
+ N'        END' + @nl
+ @nl
+ N'        COMMIT TRANSACTION;'),
 (N'        -- 2. the manual debit lines',
  N'        END   -- [97] IF @IsMixed = 0' + @nl + @nl + N'        -- 2. the manual debit lines');
DECLARE @i INT = 1, @a NVARCHAR(400), @r NVARCHAR(MAX), @cnt INT, @m NVARCHAR(400);
WHILE @i <= (SELECT MAX(n) FROM @p)
BEGIN
    SELECT @a = Anchor, @r = Repl FROM @p WHERE n = @i;
    SET @cnt = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @a, N''))) / DATALENGTH(@a);
    IF @cnt <> 1
    BEGIN
        SET @m = N'[97] sp_PostSupplierPaymentWithManualLines anchor ' + CAST(@i AS NVARCHAR(5)) + N' found ' + CAST(@cnt AS NVARCHAR(5)) + N' times.';
        THROW 59898, @m, 1;
    END
    SET @def = REPLACE(@def, @a, @r);
    SET @i += 1;
END
EXEC sp_rename 'dbo.sp_PostSupplierPaymentWithManualLines', 'sp_PostSupplierPaymentWithManualLines_OLD_10152026220000';
EXEC (@def);
GO

------------------------------------------------------------------
-- 4. sp_CancelledChequesCS: a voucher with both kinds is reversed as MIXED (both blocks)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS'));
DECLARE @nl NCHAR(2) = NCHAR(13) + NCHAR(10), @a NVARCHAR(600), @cnt INT;

-- 4a. detect MIXED from the voucher's own payment rows (any caller, old exe included)
SET @a = N'        -- 2026-10-12e: two reversals of the same voucher at the same time wait for each other';
SET @cnt = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @a, N''))) / DATALENGTH(@a);
IF @cnt <> 1 THROW 59898, '[97] sp_CancelledChequesCS anchor 4a not found exactly once.', 1;
SET @def = REPLACE(@def, @a,
      N'        -- [97] 2026-10-15: a voucher that paid purchases AND expenses (one cheque) is reversed whole: both blocks below' + @nl
    + N'        IF EXISTS (SELECT 1 FROM APPaymentDetails WHERE VoucherID = @parmvoucherid AND SupplierID = @parmsupplierid AND ReferenceNumber = @parmreferenceno AND PaymentMethod = ''PURCHASE'')' + @nl
    + N'           AND EXISTS (SELECT 1 FROM APPaymentDetails WHERE VoucherID = @parmvoucherid AND SupplierID = @parmsupplierid AND ReferenceNumber = @parmreferenceno AND PaymentMethod = ''EXPENSE'')' + @nl
    + N'            SET @parmvouchertype = ''MIXED'';' + @nl + @nl
    + @a);

-- 4b. the purchase block runs for PURCHASE and MIXED
SET @a = N'        IF @parmvouchertype = ''PURCHASE''';
SET @cnt = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @a, N''))) / DATALENGTH(@a);
IF @cnt <> 1 THROW 59898, '[97] sp_CancelledChequesCS anchor 4b not found exactly once.', 1;
SET @def = REPLACE(@def, @a, N'        IF @parmvouchertype IN (''PURCHASE'', ''MIXED'')   -- [97]');

-- 4c. the expense block (was the ELSE): every type but PURCHASE, so EXPENSE, MIXED and anything else as before
DECLARE @aLF NVARCHAR(600) = N'        ELSE' + NCHAR(10) + N'        BEGIN' + NCHAR(10) + N'            IF OBJECT_ID(''tempdb..#ExpRev'') IS NOT NULL DROP TABLE #ExpRev;';
DECLARE @aCR NVARCHAR(600) = N'        ELSE' + @nl + N'        BEGIN' + @nl + N'            IF OBJECT_ID(''tempdb..#ExpRev'') IS NOT NULL DROP TABLE #ExpRev;';
DECLARE @newHead NVARCHAR(600) = N'        IF ISNULL(@parmvouchertype, '''') <> ''PURCHASE''   -- [97] was ELSE: EXPENSE, or the second half of MIXED' + @nl
                                + N'        BEGIN' + @nl + N'            IF OBJECT_ID(''tempdb..#ExpRev'') IS NOT NULL DROP TABLE #ExpRev;';
IF (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @aCR, N''))) / DATALENGTH(@aCR) = 1
    SET @def = REPLACE(@def, @aCR, @newHead);
ELSE IF (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @aLF, N''))) / DATALENGTH(@aLF) = 1
    SET @def = REPLACE(@def, @aLF, @newHead);
ELSE
    THROW 59898, '[97] sp_CancelledChequesCS anchor 4c (ELSE before #ExpRev) not found exactly once.', 1;

EXEC sp_rename 'dbo.sp_CancelledChequesCS', 'sp_CancelledChequesCS_OLD_10152026220000';
EXEC (@def);
GO

------------------------------------------------------------------
-- 5. Post-check, then commit
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2')) NOT LIKE '%@SkipVoucherWrap%'
    SET @msg = N'V2 is not the [97] text';
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.splist_Accounts')) NOT LIKE '%[[]97]%'
    SET @msg = N'splist_Accounts is not the [97] text';
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostSupplierPaymentWithManualLines')) NOT LIKE '%@PurchaseLines%'
    SET @msg = N'sp_PostSupplierPaymentWithManualLines is not the [97] text';
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CancelledChequesCS')) NOT LIKE '%''MIXED''%'
    SET @msg = N'sp_CancelledChequesCS is not the [97] text';
ELSE IF OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2_OLD_10152026220000', 'P') IS NULL OR OBJECT_ID('dbo.splist_Accounts_OLD_10152026220000', 'P') IS NULL
     OR OBJECT_ID('dbo.sp_PostSupplierPaymentWithManualLines_OLD_10152026220000', 'P') IS NULL OR OBJECT_ID('dbo.sp_CancelledChequesCS_OLD_10152026220000', 'P') IS NULL
    SET @msg = N'a backup is missing';

IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[97] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59897, @msg, 1;
END

COMMIT TRANSACTION;
PRINT '[97] committed: mixed purchase + expense vouchers (V2, splist_Accounts, sp_PostSupplierPaymentWithManualLines, sp_CancelledChequesCS).';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
