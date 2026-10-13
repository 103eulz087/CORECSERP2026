/* ================================================================
   2026-10-12d - Supplier payment: multi-branch split fix + "as paid" invoice view
   ================================================================
   1. sp_AddPaymentSupplierCompound_V2 (Supplier Payment, CASH / CHECK, multi-branch expense invoices):
      the last branch's share was the invoice amount settled minus
        SUM(BranchNetLiability / @eNetLiability * @eGross)
      over the #BranchTotals column. That SUM column is DECIMAL(38,2), so SQL Server cuts the ratio to 6
      decimals (6,220 / 199,999 -> 0.031100) and the other branches are under-counted; the last branch
      (usually 888) took the difference. Example: expense 17710 / CEB-PCF-080626, 199,999.00, paid by
      voucher 688 / ref 28500 as 6,220.00 + 6,340.00 + 187,439.06 = 199,999.06 (cheque, GL, supplier
      ledger and bank recon all 0.06 over). Now the last branch gets what is left after the ROUNDED
      shares already given out, so the legs always add up to the amount settled (same as EWT / discount
      / offset in the same loop). Anchor patch; backup sp_AddPaymentSupplierCompound_V2_OLD_10122026200000.
      No parameter change, no exe change. After sp-reviewer: an invoice whose branch net liability adds
      up to 0 is refused (60523; the old formula failed there with a divide-by-zero, the new one would
      have posted NULL amounts), and so is a negative last-branch share (60524: the branch lines don't
      add up to the invoice, e.g. after a bad edit).

   2. New read-only dbo.sp_GetSupplierVoucherInvoiceView (@SupplierID, @ReferenceNumber), for
      SupplierVoucherReversalFrm > View Details > "Invoices (as paid)": one row per invoice the voucher
      paid, in the shape of the payment screen (splist_Accounts): invoice amount, balance before this
      voucher, amount paid (cash), variance, EWT, discount, returns, overpay, advance applied, amount
      settled, balance after. Result set 2 = the branch legs of each invoice (expand a row).
      * A leg = one voucher's rows for one invoice and branch (every PaymentType, so an invoice settled
        with no cash still shows). How it was settled, by writer:
        - expense legs of the cash / check screen have their own settlement ticket (EXP-ACCRUAL-PAY /
          SINGLE-PAY): settled = payable debit, cash = bank credit, EWT = 20104, returns = 40104,
          FX = 60310 / 40510 (sp_Payment_PostSettlementTicket's accounts; the supplier-payment proc never
          overrides them), discount = what is left of the ticket;
        - telegraphic / manual vouchers (one netted VOUCHER-MANUAL ticket): cash = the row's amount,
          settled = cash - variance (sp_PostVoucherManual's rule);
        - purchases of the cash / check screen (no per-invoice ticket): one row per kind (INVOICE PAYMENT
          = cash, EWT, DISCOUNT, RETURNALLOWANCES, VARIANCE, OVERPAY, OVERPAYEXPENSE, ADVANCEAPPLIED),
          settled = cash + EWT + discount + returns + advance - variance - overpay (the proc's @pGross);
        - an overpay-only head-office ticket (EXP-OVERPAY-HO, invoice with no 888 share): cash = the
          overpay, settled 0.
        Multi-branch expense payments never post FX: their variance is already netted into settled.
      * Balance before = the payable booked at posting (purchase: ActualCost; expense: its supplier-
        ledger posting rows, else today's balance + every payment not reversed) less the payments not
        reversed made before this voucher (by reference number: one global counter, sp_GetReferenceNumber).
        So a multi-branch payment hit by the split bug shows Balance After -0.06 instead of hiding it,
        and Balance Now shows today's figure.
      * Reversed = in PaymentReversalAudit (reference + supplier); a reversed voucher is still shown
        (Status REVERSED).

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
    DECLARE @old SYSNAME = @Obj + N'_OLD_10122026200000', @full NVARCHAR(300) = N'dbo.' + @Obj;
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
IF OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2_OLD_10122026200000', 'P') IS NOT NULL OR OBJECT_ID('dbo.sp_GetSupplierVoucherInvoiceView', 'P') IS NOT NULL
BEGIN
    RAISERROR('This script has been run here before (sp_AddPaymentSupplierCompound_V2_OLD_10122026200000 or sp_GetSupplierVoucherInvoiceView exists).', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── 1. the split ─────────────────────────────────────────────────
DECLARE @LF NCHAR(1) = NCHAR(10);
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_AddPaymentSupplierCompound_V2',
    N'                        @offRunning DECIMAL(18,2)=0, @varRunning DECIMAL(18,2)=0;',
    N'                        @offRunning DECIMAL(18,2)=0, @varRunning DECIMAL(18,2)=0;' + @LF +
    N'                -- 2026-10-12d: the rounded branch shares given out so far (the last branch takes the rest)' + @LF +
    N'                DECLARE @grossRunning DECIMAL(18,2) = 0;' + @LF +
    N'                SET @grossRunning = 0;' + @LF +
    N'                IF ISNULL(@eNetLiability, 0) = 0' + @LF +
    N'                BEGIN' + @LF +
    N'                    DECLARE @ENoLiabMsg VARCHAR(400) = ''Invoice '' + ISNULL(@eInvoiceNo,'''') + '': its branch lines add up to no payable amount, so the payment can''''t be split across branches. Check the expense entry.'';' + @LF +
    N'                    THROW 60523, @ENoLiabMsg, 1;' + @LF +
    N'                END');
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'sp_AddPaymentSupplierCompound_V2',
    N'                    IF @brrow = @brmaxrow' + @LF +
    N'                        SET @brGross = @eGross - ISNULL((SELECT SUM(BranchNetLiability/@eNetLiability * @eGross) FROM #BranchTotals WHERE RowNum < @brmaxrow), 0);',
    N'                    -- 2026-10-12d: the last branch = amount settled - the ROUNDED shares already given out. It used to' + @LF +
    N'                    -- re-add the shares over the #BranchTotals SUM column, whose ratio SQL Server cuts to 6 decimals,' + @LF +
    N'                    -- so the legs could add up to more than the amount settled (voucher 688: +0.06 on 888).' + @LF +
    N'                    IF @brrow = @brmaxrow' + @LF +
    N'                    BEGIN' + @LF +
    N'                        SET @brGross = @eGross - @grossRunning;' + @LF +
    N'                        IF @brGross < 0' + @LF +
    N'                        BEGIN' + @LF +
    N'                            DECLARE @ENegShareMsg VARCHAR(400) = ''Invoice '' + ISNULL(@eInvoiceNo,'''') + '': the branch shares come to more than the amount being settled (branch '' + @brBranch + '' would get '' + CAST(@brGross AS VARCHAR(30)) + ''). Its branch lines don''''t add up to the invoice; check the expense entry.'';' + @LF +
    N'                            THROW 60524, @ENegShareMsg, 1;' + @LF +
    N'                        END' + @LF +
    N'                    END' + @LF +
    N'                    ELSE' + @LF +
    N'                        SET @grossRunning += ISNULL(@brGross, 0);');
EXEC #ApplyPatch N'sp_AddPaymentSupplierCompound_V2';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── 2. the "as paid" view ────────────────────────────────────────
CREATE PROCEDURE dbo.sp_GetSupplierVoucherInvoiceView
    @SupplierID      VARCHAR(50),
    @ReferenceNumber VARCHAR(10)
AS
/*  Read-only. One supplier voucher (reference no.) shown the way the payment screen showed it:
    result set 1 = one row per invoice it paid, result set 2 = the branch legs of each invoice
    (InvKey links them). See SQL/2026-10-12d_SupplierPayment_MultiBranchSplit_InvoiceView.sql.
    Caller: AccountingDevEx/SupplierVoucherReversalFrm (View Details). */
BEGIN
    SET NOCOUNT ON;
    SET @ReferenceNumber = LTRIM(RTRIM(@ReferenceNumber));

    -- every payment row of this supplier, keyed by invoice (expense rows carry BatchReferenceID, purchase rows the APACCOUNTS SequenceNo)
    CREATE TABLE #Row (
        Ref          VARCHAR(20)   NOT NULL,
        RefNum       BIGINT        NULL,
        InvKey       VARCHAR(250)  NOT NULL,
        InvType      VARCHAR(10)   NOT NULL,
        InvoiceNo    VARCHAR(150)  NULL,
        BatchRef     BIGINT        NULL,
        SeqRef       VARCHAR(50)   NULL,
        BranchCode   VARCHAR(10)   NOT NULL,
        PaymentType  VARCHAR(30)   NOT NULL,
        Amount       DECIMAL(18,2) NOT NULL,
        Variance     DECIMAL(18,2) NOT NULL,
        TicketNumber VARCHAR(30)   NULL,
        PayableAcct  VARCHAR(30)   NULL,
        BankAcct     VARCHAR(30)   NULL
    );
    INSERT INTO #Row (Ref, RefNum, InvKey, InvType, InvoiceNo, BatchRef, SeqRef, BranchCode, PaymentType, Amount, Variance, TicketNumber, PayableAcct, BankAcct)
    SELECT LTRIM(RTRIM(p.ReferenceNumber)), TRY_CAST(LTRIM(RTRIM(p.ReferenceNumber)) AS BIGINT),
           CASE WHEN p.BatchReferenceID IS NOT NULL THEN 'E|' + ISNULL(p.InvoiceNo, '') + '|' + CAST(p.BatchReferenceID AS VARCHAR(30))
                ELSE 'P|' + ISNULL(p.InvoiceNo, '') + '|' + ISNULL(p.SequenceReferenceNumber, '') END,
           CASE WHEN p.BatchReferenceID IS NOT NULL THEN 'EXPENSE' ELSE 'PURCHASE' END,
           p.InvoiceNo, p.BatchReferenceID, CASE WHEN p.BatchReferenceID IS NULL THEN p.SequenceReferenceNumber END,
           ISNULL(p.BranchCode, ''), ISNULL(p.PaymentType, ''), ISNULL(p.Amount, 0), ISNULL(p.Variance, 0),
           NULLIF(LTRIM(RTRIM(p.TicketNumber)), ''), p.DebitGLCode, p.CreditGLCode
    FROM dbo.APPaymentDetails AS p
    WHERE p.SupplierID = @SupplierID
      AND EXISTS (SELECT 1 FROM dbo.APPaymentDetails AS q
                  WHERE q.SupplierID = @SupplierID AND q.ReferenceNumber = @ReferenceNumber
                    AND ISNULL(q.InvoiceNo, '') = ISNULL(p.InvoiceNo, '')
                    AND ((q.BatchReferenceID IS NOT NULL AND q.BatchReferenceID = p.BatchReferenceID)
                         OR (q.BatchReferenceID IS NULL AND p.BatchReferenceID IS NULL
                             AND ISNULL(q.SequenceReferenceNumber, '') = ISNULL(p.SequenceReferenceNumber, ''))));

    -- the invoices this voucher paid
    CREATE TABLE #Inv (InvKey VARCHAR(250) NOT NULL PRIMARY KEY, InvType VARCHAR(10) NOT NULL, InvoiceNo VARCHAR(150) NULL, BatchRef BIGINT NULL, SeqRef VARCHAR(50) NULL);
    INSERT INTO #Inv (InvKey, InvType, InvoiceNo, BatchRef, SeqRef)
    SELECT InvKey, MAX(InvType), MAX(InvoiceNo), MAX(BatchRef), MAX(SeqRef) FROM #Row WHERE Ref = @ReferenceNumber GROUP BY InvKey;

    -- vouchers of this supplier reversed since (their payments no longer count against the balance)
    CREATE TABLE #Rev (Ref VARCHAR(20) NOT NULL PRIMARY KEY);
    INSERT INTO #Rev (Ref)
    SELECT DISTINCT LTRIM(RTRIM(CAST(ReferenceNumber AS VARCHAR(20)))) FROM dbo.PaymentReversalAudit
    WHERE ReferenceNumber IS NOT NULL AND SupplierID = @SupplierID;

    -- one leg per (voucher, invoice, branch): how it was settled
    CREATE TABLE #Br (
        Ref          VARCHAR(20)   NOT NULL,
        RefNum       BIGINT        NULL,
        InvKey       VARCHAR(250)  NOT NULL,
        BranchCode   VARCHAR(10)   NOT NULL,
        TicketNumber VARCHAR(30)   NULL,
        Settled      DECIMAL(18,2) NOT NULL,
        Cash         DECIMAL(18,2) NOT NULL,
        EWT          DECIMAL(18,2) NOT NULL,
        Discount     DECIMAL(18,2) NOT NULL,
        RetAmt       DECIMAL(18,2) NOT NULL,
        Variance     DECIMAL(18,2) NOT NULL,
        OverPay      DECIMAL(18,2) NOT NULL,
        OverPayExp   DECIMAL(18,2) NOT NULL,
        Advance      DECIMAL(18,2) NOT NULL
    );
    ;WITH Leg AS (
        SELECT r.Ref, MAX(r.RefNum) AS RefNum, r.InvKey, r.BranchCode,
               -- the principal row (the invoice payment itself) and its ticket / accounts
               MAX(CASE WHEN r.PaymentType IN ('EXPENSE PAYMENT', 'INVOICE PAYMENT') THEN 1 ELSE 0 END) AS HasMain,
               SUM(CASE WHEN r.PaymentType IN ('EXPENSE PAYMENT', 'INVOICE PAYMENT') THEN r.Amount ELSE 0 END) AS MainAmt,
               SUM(CASE WHEN r.PaymentType IN ('EXPENSE PAYMENT', 'INVOICE PAYMENT') THEN r.Variance ELSE 0 END) AS MainVar,
               MAX(CASE WHEN r.PaymentType IN ('EXPENSE PAYMENT', 'INVOICE PAYMENT') THEN r.TicketNumber END) AS TicketNumber,
               MAX(CASE WHEN r.PaymentType IN ('EXPENSE PAYMENT', 'INVOICE PAYMENT') THEN r.PayableAcct END) AS PayableAcct,
               MAX(CASE WHEN r.PaymentType IN ('EXPENSE PAYMENT', 'INVOICE PAYMENT') THEN r.BankAcct END) AS BankAcct,
               -- the purchase path's one-row-per-kind rows
               SUM(CASE WHEN r.PaymentType = 'EWT' THEN r.Amount ELSE 0 END) AS RowEWT,
               SUM(CASE WHEN r.PaymentType = 'DISCOUNT' THEN r.Amount ELSE 0 END) AS RowDisc,
               SUM(CASE WHEN r.PaymentType = 'RETURNALLOWANCES' THEN r.Amount ELSE 0 END) AS RowRet,
               SUM(CASE WHEN r.PaymentType = 'VARIANCE' THEN r.Amount ELSE 0 END) AS RowVar,
               SUM(CASE WHEN r.PaymentType = 'OVERPAY' THEN r.Amount ELSE 0 END) AS OverPay,
               SUM(CASE WHEN r.PaymentType = 'OVERPAYEXPENSE' THEN r.Amount ELSE 0 END) AS OverPayExp,
               SUM(CASE WHEN r.PaymentType = 'ADVANCEAPPLIED' THEN r.Amount ELSE 0 END) AS Advance
        FROM #Row AS r
        GROUP BY r.Ref, r.InvKey, r.BranchCode)
    INSERT INTO #Br (Ref, RefNum, InvKey, BranchCode, TicketNumber, Settled, Cash, EWT, Discount, RetAmt, Variance, OverPay, OverPayExp, Advance)
    SELECT l.Ref, l.RefNum, l.InvKey, l.BranchCode, l.TicketNumber, v.Settled, v.Cash, v.EWT, v.Discount, v.RetAmt, v.Variance, l.OverPay, l.OverPayExp, l.Advance
    FROM Leg AS l
    OUTER APPLY (SELECT TOP 1 m.Mnemonic FROM dbo.TicketMaster AS m
                 WHERE m.TicketNumber = l.TicketNumber AND m.ReferenceNumber = l.Ref ORDER BY m.BranchCode) AS tm
    OUTER APPLY (SELECT SUM(q.Payable) AS Payable, SUM(q.Bank) AS Bank, SUM(q.EWT) AS EWT,
                        SUM(q.RetAmt) AS RetAmt, SUM(q.FXLoss) AS FXLoss, SUM(q.FXGain) AS FXGain
                 FROM (SELECT CASE WHEN d.AccountCode = l.PayableAcct THEN ISNULL(d.Debit, 0) - ISNULL(d.Credit, 0) ELSE 0 END AS Payable,
                              CASE WHEN d.AccountCode = l.BankAcct    THEN ISNULL(d.Credit, 0) - ISNULL(d.Debit, 0) ELSE 0 END AS Bank,
                              CASE WHEN d.AccountCode = '20104' THEN ISNULL(d.Credit, 0) ELSE 0 END AS EWT,
                              CASE WHEN d.AccountCode = '40104' THEN ISNULL(d.Credit, 0) ELSE 0 END AS RetAmt,
                              CASE WHEN d.AccountCode = '60310' THEN ISNULL(d.Debit, 0) ELSE 0 END AS FXLoss,
                              CASE WHEN d.AccountCode = '40510' THEN ISNULL(d.Credit, 0) ELSE 0 END AS FXGain
                       FROM dbo.TicketDetails AS d
                       WHERE d.TicketNumber = l.TicketNumber AND d.ReferenceNumber = l.Ref AND d.BranchCode = l.BranchCode) AS q) AS t
    CROSS APPLY (SELECT CASE
           WHEN l.HasMain = 1 AND ISNULL(tm.Mnemonic, '') NOT LIKE 'VOUCHER-MANUAL%' AND ISNULL(t.Payable, 0) <> 0 THEN 'TICKET'   -- own settlement ticket
           WHEN l.HasMain = 1 AND tm.Mnemonic LIKE 'VOUCHER-MANUAL%' THEN 'MANUAL'                                              -- telegraphic / manual voucher
           WHEN l.HasMain = 1 OR l.RowEWT + l.RowDisc + l.RowRet + l.Advance <> 0 OR l.RowVar <> 0 THEN 'ROWS'                 -- purchase rows per kind (cash may be 0)
           ELSE 'EXTRA' END AS Mode) AS k                                                                                       -- overpay-only HO ticket
    CROSS APPLY (SELECT
           CAST(CASE k.Mode WHEN 'TICKET' THEN t.Payable
                            WHEN 'MANUAL' THEN l.MainAmt - l.MainVar
                            WHEN 'ROWS'   THEN l.MainAmt + l.RowEWT + l.RowDisc + l.RowRet + l.Advance - l.RowVar - l.OverPay - l.OverPayExp
                            ELSE 0 END AS DECIMAL(18,2)) AS Settled,
           CAST(CASE k.Mode WHEN 'TICKET' THEN ISNULL(t.Bank, 0)
                            WHEN 'EXTRA'  THEN l.OverPay + l.OverPayExp
                            ELSE l.MainAmt END AS DECIMAL(18,2)) AS Cash,
           CAST(CASE k.Mode WHEN 'TICKET' THEN ISNULL(t.EWT, 0) WHEN 'ROWS' THEN l.RowEWT ELSE 0 END AS DECIMAL(18,2)) AS EWT,
           CAST(CASE k.Mode WHEN 'TICKET' THEN t.Payable + ISNULL(t.FXLoss, 0) + l.OverPay + l.OverPayExp - ISNULL(t.Bank, 0) - ISNULL(t.EWT, 0)
                                                - ISNULL(t.RetAmt, 0) - ISNULL(t.FXGain, 0) - l.Advance
                            WHEN 'ROWS' THEN l.RowDisc ELSE 0 END AS DECIMAL(18,2)) AS Discount,
           CAST(CASE k.Mode WHEN 'TICKET' THEN ISNULL(t.RetAmt, 0) WHEN 'ROWS' THEN l.RowRet ELSE 0 END AS DECIMAL(18,2)) AS RetAmt,
           CAST(CASE k.Mode WHEN 'TICKET' THEN ISNULL(t.FXLoss, 0) - ISNULL(t.FXGain, 0)
                            WHEN 'MANUAL' THEN l.MainVar
                            WHEN 'ROWS'   THEN l.RowVar ELSE 0 END AS DECIMAL(18,2)) AS Variance) AS v;

    -- the payable booked at posting: a purchase's ActualCost (all 387 STAGING purchases tie: cost = balance + payments, except one
    -- broken by a reversal); an expense's supplier-ledger posting rows (Balance starts below Amount when withholding is booked at
    -- accrual), payment rows left out; else today's balance + every payment not reversed
    CREATE TABLE #Open (InvKey VARCHAR(250) NOT NULL PRIMARY KEY, Opening DECIMAL(18,2) NULL, InvoiceAmount DECIMAL(18,2) NULL, BalanceNow DECIMAL(18,2) NULL,
                        DocRef VARCHAR(50) NULL, InvoiceDate DATE NULL, Description VARCHAR(5000) NULL);
    INSERT INTO #Open (InvKey, Opening, InvoiceAmount, BalanceNow, DocRef, InvoiceDate, Description)
    SELECT i.InvKey,
           CASE WHEN i.InvType = 'PURCHASE' THEN CAST(ap.ActualCost AS DECIMAL(18,2))
                ELSE COALESCE(NULLIF(led.Net, 0), CAST(ISNULL(es.Balance, es.Amount) AS DECIMAL(18,2)) + ISNULL(paid.Settled, 0)) END,
           CAST(COALESCE(es.Amount, ap.ActualCost) AS DECIMAL(18,2)),
           CAST(COALESCE(es.Balance, ap.Balance) AS DECIMAL(18,2)),
           LTRIM(RTRIM(COALESCE(CAST(es.ReferenceNumber AS VARCHAR(50)), CAST(ap.ReferenceNumber AS VARCHAR(50))))),
           COALESCE(es.ExpenseDate, ap.InvoiceDate),
           COALESCE(CAST(es.Description AS VARCHAR(5000)), CAST(ap.InvoiceNo AS VARCHAR(5000)))
    FROM #Inv AS i
    OUTER APPLY (SELECT TOP 1 e.ReferenceNumber, e.Amount, e.Balance, e.ExpenseDate, e.Description FROM dbo.ExpenseSummary AS e
                 WHERE i.InvType = 'EXPENSE' AND e.SupplierID = @SupplierID AND ISNULL(e.InvoiceNo, '') = ISNULL(i.InvoiceNo, '')
                   AND e.BatchReferenceID = i.BatchRef ORDER BY e.ReferenceNumber) AS es
    OUTER APPLY (SELECT TOP 1 a.ReferenceNumber, a.ActualCost, a.Balance, a.InvoiceDate, a.InvoiceNo FROM dbo.APACCOUNTS AS a
                 WHERE i.InvType = 'PURCHASE' AND a.SupplierID = @SupplierID AND ISNULL(a.InvoiceNo, '') = ISNULL(i.InvoiceNo, '')
                   AND CAST(a.SequenceNo AS VARCHAR(50)) = i.SeqRef ORDER BY a.SequenceNo) AS ap
    OUTER APPLY (SELECT SUM(ISNULL(sl.Credit, 0) - ISNULL(sl.Debit, 0)) AS Net FROM dbo.SupplierLedger AS sl
                 WHERE i.InvType = 'EXPENSE' AND sl.SupplierKey = @SupplierID AND ISNULL(sl.InvoiceNo, '') = ISNULL(i.InvoiceNo, '')
                   AND sl.ReferenceNumber = CAST(es.ReferenceNumber AS VARCHAR(50))
                   AND NOT EXISTS (SELECT 1 FROM dbo.APPaymentDetails AS x
                                   WHERE x.SupplierID = @SupplierID AND LTRIM(RTRIM(x.ReferenceNumber)) = LTRIM(RTRIM(sl.ReferenceNumber)))) AS led
    OUTER APPLY (SELECT SUM(b.Settled) AS Settled FROM #Br AS b WHERE b.InvKey = i.InvKey AND NOT EXISTS (SELECT 1 FROM #Rev AS r WHERE r.Ref = b.Ref)) AS paid;

    -- this voucher's branch legs
    SELECT b.InvKey, b.BranchCode, br.BranchName,
           CAST(sh.Share AS DECIMAL(18,2)) AS BranchShare,
           b.Cash AS AmountPaid, b.Variance, b.EWT AS EWTAmount, b.Discount AS DiscountAmount, b.RetAmt AS ReturnAllowances,
           b.OverPay, b.OverPayExp AS OverPayExpense, b.Advance AS AdvanceApplied, b.Settled AS AmountSettled, b.TicketNumber
    INTO #ThisLeg
    FROM #Br AS b
    INNER JOIN #Inv AS i ON i.InvKey = b.InvKey
    LEFT JOIN dbo.Branches AS br ON br.BranchCode = b.BranchCode
    OUTER APPLY (SELECT SUM(m.Amount) AS Share FROM dbo.ExpenseMaster AS m
                 WHERE i.InvType = 'EXPENSE' AND m.SupplierID = @SupplierID AND ISNULL(m.InvoiceNo, '') = ISNULL(i.InvoiceNo, '')
                   AND m.BatchReferenceID = i.BatchRef AND m.BranchCode = b.BranchCode) AS sh
    WHERE b.Ref = @ReferenceNumber;

    -- 1. one row per invoice, as on the payment screen
    SELECT i.InvKey, i.InvType AS [Type], i.InvoiceNo, o.DocRef AS ReferenceNo, o.InvoiceDate, o.Description,
           (SELECT COUNT(*) FROM #ThisLeg AS t WHERE t.InvKey = i.InvKey) AS Branches,
           o.InvoiceAmount,
           CAST(o.Opening - ISNULL(prior.Settled, 0) AS DECIMAL(18,2)) AS BalanceBefore,
           CAST(SUM(t.AmountPaid) AS DECIMAL(18,2)) AS AmountPaid,
           CAST(SUM(t.Variance) AS DECIMAL(18,2)) AS Variance,
           CAST(SUM(t.EWTAmount) AS DECIMAL(18,2)) AS EWTAmount,
           CAST(SUM(t.DiscountAmount) AS DECIMAL(18,2)) AS DiscountAmount,
           CAST(SUM(t.ReturnAllowances) AS DECIMAL(18,2)) AS ReturnAllowances,
           CAST(SUM(t.OverPay) AS DECIMAL(18,2)) AS OverPay,
           CAST(SUM(t.OverPayExpense) AS DECIMAL(18,2)) AS OverPayExpense,
           CAST(SUM(t.AdvanceApplied) AS DECIMAL(18,2)) AS AdvanceApplied,
           CAST(SUM(t.AmountSettled) AS DECIMAL(18,2)) AS AmountSettled,
           CAST(o.Opening - ISNULL(prior.Settled, 0) - SUM(t.AmountSettled) AS DECIMAL(18,2)) AS BalanceAfter,
           o.BalanceNow,
           CASE WHEN EXISTS (SELECT 1 FROM #Rev AS r WHERE r.Ref = @ReferenceNumber) THEN 'REVERSED' ELSE 'POSTED' END AS Status
    FROM #Inv AS i
    INNER JOIN #Open AS o ON o.InvKey = i.InvKey
    INNER JOIN #ThisLeg AS t ON t.InvKey = i.InvKey
    OUTER APPLY (SELECT SUM(b.Settled) AS Settled FROM #Br AS b
                 WHERE b.InvKey = i.InvKey AND b.Ref <> @ReferenceNumber
                   AND (b.RefNum < TRY_CAST(@ReferenceNumber AS BIGINT) OR (b.RefNum IS NULL AND b.Ref < @ReferenceNumber))
                   AND NOT EXISTS (SELECT 1 FROM #Rev AS r WHERE r.Ref = b.Ref)) AS prior
    GROUP BY i.InvKey, i.InvType, i.InvoiceNo, o.DocRef, o.InvoiceDate, o.Description, o.InvoiceAmount, o.Opening, prior.Settled, o.BalanceNow
    ORDER BY o.InvoiceDate, i.InvoiceNo;

    -- 2. the branch legs of each invoice
    SELECT InvKey, BranchCode, BranchName, BranchShare, AmountPaid, Variance, EWTAmount, DiscountAmount, ReturnAllowances,
           OverPay, OverPayExpense, AdvanceApplied, AmountSettled, TicketNumber
    FROM #ThisLeg
    ORDER BY InvKey, BranchCode;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

IF OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2_OLD_10122026200000', 'P') IS NULL
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2')) NOT LIKE '%SET @brGross = @eGross - @grossRunning;%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2')) LIKE '%SUM(BranchNetLiability/@eNetLiability * @eGross)%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2')) NOT LIKE '%60523%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2')) NOT LIKE '%60524%'
   OR OBJECT_ID('dbo.sp_GetSupplierVoucherInvoiceView', 'P') IS NULL
BEGIN
    RAISERROR('Post-check failed; rolled back.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
COMMIT TRANSACTION;
PRINT 'Multi-branch split fixed (sp_AddPaymentSupplierCompound_V2) and sp_GetSupplierVoucherInvoiceView created.';
GO
SET NOEXEC OFF;
GO
