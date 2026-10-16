/* ================================================================
   [87] 2026-10-15 - Hardening H5 (Fable session): settlements checked against the balance read NOW, never the screen's
   ================================================================
   Handoff docs/handoff/2026-10-14_Hardening_Handoff_to_Fable.md, item H5. Needs [84] (sp_AddPaymentClient) and [83] + [84]
   (sp_AddPaymentSupplierCompound_V2): the guard checks the live text. Backups _OLD_10152026010000.

   Audit (2026-10-15, read-only on DEV / STAGING / PRODUCTION):
     - sp_AddPaymentSupplierCompound_V2 (purchase, expense single, expense multi-branch): already reads each invoice's
       balance WITH (UPDLOCK) and refuses a settlement above it (60502 / 60503 / 60504); the new balance is computed from
       the locked value. One client figure remained: the multi-branch split used the TVP's ActualCost as the invoice
       amount (@eNetLiability = ActualCost - EWT already posted). Now the stored ExpenseSummary.Amount is used, and a
       TVP amount that differs from it is refused (60525: the screen is stale, the expense was edited).
     - sp_AddPaymentClient (AR): ordinary invoices were never read under lock and never compared with the settlement:
       a payment larger than the balance now (another payment posted after the grid loaded) went through and left the
       invoice at a negative balance marked FULLYPAID; a line for an invoice that does not exist for the customer was
       silently skipped (the payment recorded, nothing settled); step 7 recomputes Balance = TotalAmount - components,
       which silently resets a balance set by hand. Now, per invoice of the payment (lines added up first), read
       WITH (UPDLOCK, ROWLOCK) through the new index IX_TransactionChargeSales_Customer_Invoice (CustomerKey, InvoiceNo,
       ReferenceNo; the table's only index was the clustered BranchCode / ReferenceNo / InvoiceNo, so the read was a scan):
         92015 the invoice is not the customer's (invoice no. + PO + customer)
         92016 its balance no longer follows its own columns (set by hand; fix the row, the proc won't reset it)
         92017 the settlement (INVOICE PAYMENT lines, net of balance-forward credits) is more than the balance now
       Balance-forward credit rows keep the [79] rules (92010-92012). The success path writes exactly what it wrote
       (old vs new compared row by row on DEV). Measured first: 0 invoices off their formula, 0 customers whose invoice
       balances differ from their account, on all three tiers.
     - sp_CreditMemo / sp_ReturnSalesOrder / spu_SO_PostInvoiceReduction: already lock and refuse (59404, 59107);
       sp_PostCashAdvance: the amount is the advance itself, nothing to settle. No change.
   Exception Center S07: per customer, SUM(TransactionChargeSales.Balance) = ClientAccounts.AccountBalance (0 on all tiers);
   S08: every invoice row's Balance follows its own columns, all dates (the 92016 condition; 0 on all tiers). Historical:
   6 INVOICE PAYMENT lines on DEV and on PRODUCTION have no invoice row under their invoice no. + PO + customer (old
   payments, before the 09-23 / [80] matching fixes); they are not touched, and they don't affect a new payment.
   One transaction; a failure rolls everything back. No exe change.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF CHARINDEX('[87]', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentClient'))) > 0
BEGIN
    RAISERROR('[87] already applied here; nothing to do.', 16, 1);
    SET NOEXEC ON;
END
ELSE
BEGIN
    DECLARE @bad NVARCHAR(400) = N'';
    DECLARE @Exp TABLE (Obj SYSNAME, Hash VARCHAR(66));
    INSERT INTO @Exp VALUES
        ('sp_AddPaymentClient',              '0x22F40F2675610948711C7E0E68A778FF73E2AD6B29889CC534EE820EF6E2F757'),   -- [79] + [84] text (DEV = STAGING = PRODUCTION 10-14)
        ('sp_AddPaymentSupplierCompound_V2', '0xB23FBA25B09DAB1DFB44C49C6C289C3DB5F5E7A0AE137AFD14D166B167362777');   -- [83] + [84] text
    SELECT @bad = @bad + e.Obj + N' '
    FROM @Exp e
    WHERE ISNULL(CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.' + e.Obj)), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 1), '') <> e.Hash;
    IF @bad <> N'' OR EXISTS (SELECT 1 FROM sys.objects WHERE name LIKE '%[_]OLD[_]10152026010000')
    BEGIN
        SET @bad = N'[87] stopped, nothing changed: not the expected text (run [83] + [84] first on this database): ' + @bad + N'; or a [87] backup already exists.';
        RAISERROR(@bad, 16, 1);
        SET NOEXEC ON;
    END
END
GO

BEGIN TRANSACTION;
GO

-- The invoice read above seeks by customer + invoice no. + PO; the table's only index is the clustered key
-- (BranchCode, ReferenceNo, InvoiceNo), so without this index every payment scanned the table under UPDLOCK.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TransactionChargeSales') AND name = 'IX_TransactionChargeSales_Customer_Invoice')
    CREATE NONCLUSTERED INDEX IX_TransactionChargeSales_Customer_Invoice
        ON dbo.TransactionChargeSales (CustomerKey, InvoiceNo, ReferenceNo)
        INCLUDE (TotalAmount, Balance, AmountPaid, EWTAmount, DiscountAmount, OffsetAmount, PayStatus);
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[87] the index step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

BEGIN TRY
    DECLARE @Patch TABLE (Obj SYSNAME, Ord INT, Anchor NVARCHAR(600), Repl NVARCHAR(MAX));
    INSERT INTO @Patch (Obj, Ord, Anchor, Repl) VALUES
    -- AR: per-invoice lock + refusals, placed before the offset-credit guard (after the customer applock and the [79] credit rules)
    (N'sp_AddPaymentClient', 1,
     N'    -- Offset cannot exceed the customer''s actual available credit.',
     N'    -- [87] H5: every invoice of this payment is read NOW, under lock, and compared with the settlement sent (Known Bug #10).{NL}'
   + N'    --      The screen''s Balance is never trusted: another payment may have settled the invoice since the grid loaded.{NL}'
   + N'    --      The lines are added up per invoice first, then each invoice row is read once (UPDLOCK, held to COMMIT; the{NL}'
   + N'    --      customer applock above serializes payments, so no range lock is needed for a row that is not there).{NL}'
   + N'    IF OBJECT_ID(''tempdb..#H5'') IS NOT NULL DROP TABLE #H5;{NL}'
   + N'    SELECT D.InvoiceNo, D.PONumber, D.Settled,{NL}'
   + N'           CASE WHEN T.InvoiceNo IS NULL THEN 0 ELSE 1 END AS Found,{NL}'
   + N'           ISNULL(T.TotalAmount, 0) AS TotalAmount, ISNULL(T.Balance, 0) AS Balance,{NL}'
   + N'           ISNULL(T.AmountPaid, 0) + ISNULL(T.EWTAmount, 0) + ISNULL(T.DiscountAmount, 0) + ISNULL(T.OffsetAmount, 0) AS Components{NL}'
   + N'    INTO #H5{NL}'
   + N'    FROM (SELECT InvoiceNo, PONumber, SUM(CASE WHEN PaymentType = ''INVOICE PAYMENT'' THEN Amount ELSE 0 END) AS Settled{NL}'
   + N'          FROM ARPaymentDetails{NL}'
   + N'          WHERE PaymentHeaderID = @PaymentHeaderID AND PaymentType IN (''INVOICE PAYMENT'', ''EWT'', ''DISCOUNT'', ''OFFSET''){NL}'
   + N'          GROUP BY InvoiceNo, PONumber) D{NL}'
   + N'    LEFT JOIN TransactionChargeSales T WITH (UPDLOCK, ROWLOCK){NL}'
   + N'           ON T.InvoiceNo = D.InvoiceNo AND T.ReferenceNo = D.PONumber AND T.CustomerKey = @custkey;{NL}'
   + N'{NL}'
   + N'    DECLARE @h5Msg NVARCHAR(400);{NL}'
   + N'    SELECT TOP 1 @h5Msg = N''Invoice '' + InvoiceNo + N'' is not an invoice of this customer (invoice no. + PO). Reload the customer and try again. Nothing was posted.''{NL}'
   + N'    FROM #H5 WHERE Found = 0 ORDER BY InvoiceNo;{NL}'
   + N'    IF @h5Msg IS NOT NULL THROW 92015, @h5Msg, 1;{NL}'
   + N'    SELECT TOP 1 @h5Msg = N''Invoice '' + InvoiceNo + N'': its balance does not follow its paid / EWT / discount / offset amounts (it was set by hand). Correct the invoice row first; the payment would have reset the balance. Nothing was posted.''{NL}'
   + N'    FROM #H5 WHERE ABS(Balance - (TotalAmount - Components)) > 0.005 ORDER BY InvoiceNo;{NL}'
   + N'    IF @h5Msg IS NOT NULL THROW 92016, @h5Msg, 1;{NL}'
   + N'    SELECT TOP 1 @h5Msg = N''Invoice '' + InvoiceNo + N'': '' + CONVERT(NVARCHAR(30), CAST(Settled AS MONEY), 1) + N'' is being settled but only ''{NL}'
   + N'                        + CONVERT(NVARCHAR(30), CAST(Balance AS MONEY), 1) + N'' is owed now (another payment may have been posted since the list was loaded). Reload the customer and try again. Nothing was posted.''{NL}'
   + N'    FROM #H5 WHERE TotalAmount >= 0 AND ROUND(Settled - Balance, 2) > 0 ORDER BY InvoiceNo;{NL}'
   + N'    IF @h5Msg IS NOT NULL THROW 92017, @h5Msg, 1;{NL}'
   + N'{NL}'
   + N'    -- Offset cannot exceed the customer''s actual available credit.'),
    -- AP multi-branch: the invoice amount from the stored expense, not the screen
    (N'sp_AddPaymentSupplierCompound_V2', 1,
     N'                SET @eNetLiability = @eTotalAmt - @eEWTAlreadyPosted;',
     N'                -- [87] H5: the invoice amount is the stored one; a screen whose amount differs is stale (the expense was edited){NL}'
   + N'                DECLARE @eStoredAmt DECIMAL(18,2);{NL}'
   + N'                SELECT @eStoredAmt = ISNULL(Amount, 0) FROM ExpenseSummary{NL}'
   + N'                WHERE SupplierID = @SupplierKey AND BatchReferenceID = @eBatchRef AND InvoiceNo = @eInvoiceNo;{NL}'
   + N'                IF ABS(ISNULL(@eTotalAmt, 0) - @eStoredAmt) > 0.005{NL}'
   + N'                BEGIN{NL}'
   + N'                    DECLARE @EStaleAmtMsg VARCHAR(400) = ''Invoice '' + ISNULL(@eInvoiceNo, '''') + '': the screen shows '' + CAST(ISNULL(@eTotalAmt, 0) AS VARCHAR(30)){NL}'
   + N'                        + '' but the expense is now '' + CAST(@eStoredAmt AS VARCHAR(30)) + '' (it was edited since the list was loaded). Reload the supplier and try again.'';{NL}'
   + N'                    THROW 60525, @EStaleAmtMsg, 1;{NL}'
   + N'                END{NL}'
   + N'                SET @eNetLiability = @eStoredAmt - @eEWTAlreadyPosted;');

    DECLARE @obj SYSNAME, @def NVARCHAR(MAX), @msg NVARCHAR(400), @a NVARCHAR(600), @r NVARCHAR(MAX), @cnt INT, @bak SYSNAME, @nl NVARCHAR(2);
    DECLARE objs CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT Obj FROM @Patch;
    OPEN objs;
    FETCH NEXT FROM objs INTO @obj;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @def = OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + @obj));
        IF @def IS NULL BEGIN SET @msg = N'[87] ' + @obj + N' is missing here.'; THROW 59985, @msg, 1; END
        -- IF / ELSE, not a CASE: a CASE pads a lone LF to char(2) (see docs/standards/2026-10-14_Posting_Proc_Error_Handling.md)
        IF CHARINDEX(CHAR(13) + CHAR(10), @def) > 0 SET @nl = CHAR(13) + CHAR(10); ELSE SET @nl = CHAR(10);

        DECLARE pt CURSOR LOCAL FAST_FORWARD FOR SELECT Anchor, Repl FROM @Patch WHERE Obj = @obj ORDER BY Ord;
        OPEN pt;
        FETCH NEXT FROM pt INTO @a, @r;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @a = REPLACE(@a, N'{NL}', @nl);
            SET @r = REPLACE(@r, N'{NL}', @nl);
            SET @cnt = (LEN(@def) - LEN(REPLACE(@def, @a, N''))) / LEN(@a);
            IF @cnt = 0 AND @nl = CHAR(13) + CHAR(10)
            BEGIN
                SET @a = REPLACE(@a, CHAR(13) + CHAR(10), CHAR(10));
                SET @r = REPLACE(@r, CHAR(13) + CHAR(10), CHAR(10));
                SET @cnt = (LEN(@def) - LEN(REPLACE(@def, @a, N''))) / LEN(@a);
            END
            IF @cnt <> 1 BEGIN SET @msg = N'[87] ' + @obj + N': anchor found ' + CAST(@cnt AS NVARCHAR(10)) + N' times (expected 1): ' + LEFT(REPLACE(@a, @nl, N'|'), 120); THROW 59985, @msg, 1; END
            SET @def = REPLACE(@def, @a, @r);
            FETCH NEXT FROM pt INTO @a, @r;
        END
        CLOSE pt; DEALLOCATE pt;

        IF CHARINDEX(N'[87]', @def) = 0 BEGIN SET @msg = N'[87] ' + @obj + N': marker missing after patching.'; THROW 59985, @msg, 1; END
        SET @bak = @obj + N'_OLD_10152026010000';
        SET @a = N'dbo.' + @obj;
        EXEC sp_rename @a, @bak;
        EXEC (@def);
        PRINT N'[87] ' + @obj + N': patched (backup ' + @bak + N').';
        FETCH NEXT FROM objs INTO @obj;
    END
    CLOSE objs; DEALLOCATE objs;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @em NVARCHAR(2048) = N'[87] stopped, nothing changed (while patching ' + ISNULL(@obj, N'?') + N'): ' + ERROR_MESSAGE();
    RAISERROR(@em, 16, 1);
    SET NOEXEC ON;
END CATCH
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[87] an earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- post-check
IF OBJECT_ID('dbo.sp_AddPaymentClient') IS NULL OR OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2') IS NULL
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentClient')), '') NOT LIKE '%THROW 92017%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2')), '') NOT LIKE '%THROW 60525%'
   OR (SELECT COUNT(*) FROM sys.objects WHERE name LIKE '%[_]OLD[_]10152026010000') <> 2
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TransactionChargeSales') AND name = 'IX_TransactionChargeSales_Customer_Invoice')
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[87] post-check failed; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
GO

SET NOEXEC OFF;
GO
SELECT DB_NAME() AS DatabaseName, name, CONVERT(VARCHAR(16), modify_date, 120) AS Modified FROM sys.objects
WHERE name IN ('sp_AddPaymentClient', 'sp_AddPaymentSupplierCompound_V2') OR name LIKE '%[_]OLD[_]10152026010000'
UNION ALL SELECT DB_NAME(), name, NULL FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TransactionChargeSales') AND name = 'IX_TransactionChargeSales_Customer_Invoice'
ORDER BY name;
GO
