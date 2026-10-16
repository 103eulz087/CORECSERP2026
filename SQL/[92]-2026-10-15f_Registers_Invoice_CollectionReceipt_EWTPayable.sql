/* ================================================================
   [92] 2026-10-15f  Registers: Invoice No. / Collection Receipt / EWT Payable
   ================================================================
   User (2026-10-15): new reports, "a list in sequential order":
     1. Invoice No. register
     2. Collection Receipt (CR No.) register
     3. EWT report: the paid and unpaid EWT payable ledger (AP side, 20104
        WTAX PAYABLE - EXPANDED: the tax withheld from suppliers, owed to BIR)
   User decisions (2026-10-15):
     - registers sorted per series, flagging DUPLICATE numbers and GAPs
     - EWT: remittances pay the oldest withheld amounts first (FIFO)
     - shown in a new 3-tab screen on the Accounting Board (AccountingDevEx/
       AccountingRegistersFrm), read-only
   Read-only objects only (one inline TVF + three report procs); no table,
   no posting proc touched. No PRODUCTION data changes.

   FACTS behind the design (PRODUCTION, read-only, 2026-10-15):
   - Invoice and CR numbers are TYPED by staff (ViewForDeliveryDetails txtsino
     -> DeliverySummary.InvoiceNo; ClientPaymentsDevExAcctg txtcrno ->
     PaymentHeader.CRNo). One series per branch: invoices C-, J, D_, B_, T_,
     I-, O-, P_, Z_, U_, X-, R-, A- ...; receipts T_CR_, A-CR-, I-CR-, "AR ..."
     ... Typing varies ("P_ 010645", "Z_10794", "X-0099901", a customer name
     typed as an invoice no.).
     SERIES = the text before the number's trailing digits (trimmed, upper
     case); NUMBER = those trailing digits (dbo.fn_rpt_DocNoSplit). A value
     with no trailing digits has no number ("NO NUMBER"). Leading zeros don't
     matter ("C-04803" = 4803).
   - An invoice's branch = DeliverySummary.BranchCode (the selling branch; the
     series follow it). A receipt's branch = its customer's BranchCode (same as
     the Cash Receipts Book, funcview_CustomerCashReceipts).
   - Sales-order deliveries only: PO in PurchaseOrderSummary, not in
     TransferOrderSummary (STS transfers have no invoice).
   - Invoice amounts: TransactionChargeSales matched by InvoiceNo + ReferenceNo
     (= PO) + CustomerKey (Known Bug #11: InvoiceNo alone is not unique).
   - 20104 credits: the 07-31 opening ticket (Mnemonic '*', 956,909.86 = July's
     EWT) and expense postings (SINGLE, EXP-MANUAL-CROSS-BR / -MULTI-BR).
     20104 debits: one Manual JV on 08-31 "WITHHOLDING TAX-EXPANDED PAYABLE -
     JULY 2026 -- REMITTED AUG" (957,024.76). No reversal ever debited 20104.

   RULES
   Registers (sp_rpt_InvoiceRegister / sp_rpt_CollectionReceiptRegister):
     - a series = branch + prefix (each branch keeps its own booklets; several
       branches type plain numbers with no prefix); sorted by branch, series,
       number; filtered by date and branch for display, but DUPLICATE / GAP are
       judged against ALL documents of the branch's series (all dates), so a
       number used outside the range is not a gap
     - DUPLICATE: the same series + number on more than one document (a
       reversed receipt does not count: its number may be typed again)
     - GAP: the numbers between this one and the previous one used in the
       series; more than 50 at once is reported as JUMP (most likely a typing
       slip, e.g. X-0099901 after X-009647)
     - RETURNED invoices / REVERSED receipts are listed and marked
   EWT payable (sp_rpt_EWTPayableLedger):
     - the account comes from JournalEntryMapping (PV-AP-EWT, AmountType EWT,
       credit side) = 20104; @AccountCode overrides it
     - every GL line on the account (TicketDetails, the amounts' source like the
       real-time Trial Balance), in date order, with the running balance
     - Kind: OPENING (Mnemonic '*'), WITHHELD (credit), REMITTANCE (debit),
       REVERSAL (a debit whose reference + branch also holds a credit on the
       account: cancels that document's own withheld amount, oldest first, and
       is not a remittance)
     - FIFO: remittances up to @DateTo, company-wide, pay the withheld amounts
       oldest first. Each withheld line: Paid / Unpaid and Status PAID /
       PARTIAL / UNPAID / REVERSED, as of @DateTo
     - remittances and the running balance are company-wide (tax is remitted
       for the company); the branch filter only hides other branches' lines
     - first row: BEGINNING (the balance before @DateFrom)

   Deploy: one transaction; re-runnable (an existing object of the same name is
   renamed to <name>_OLD_<MMddyyyyHHmmss of the run> first). Run in ONE
   connection, no open transaction. Needs the exe with AccountingRegistersFrm
   to be seen; an older exe never calls these objects.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET LOCK_TIMEOUT 10000;
GO

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[92] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.DeliverySummary', 'U') IS NULL OR OBJECT_ID('dbo.PaymentHeader', 'U') IS NULL
     OR OBJECT_ID('dbo.TicketDetails', 'U') IS NULL OR OBJECT_ID('dbo.JournalEntryMapping', 'U') IS NULL
BEGIN
    RAISERROR('[92] stopped: DeliverySummary / PaymentHeader / TicketDetails / JournalEntryMapping not found in this database.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[92] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
DECLARE @sfx VARCHAR(30) = '_OLD_' + FORMAT(SYSDATETIME(), 'MMddyyyyHHmmss'), @old SYSNAME;
IF OBJECT_ID('dbo.sp_rpt_EWTPayableLedger', 'P') IS NOT NULL
BEGIN SET @old = 'sp_rpt_EWTPayableLedger' + @sfx; EXEC sp_rename 'dbo.sp_rpt_EWTPayableLedger', @old; END
IF OBJECT_ID('dbo.sp_rpt_CollectionReceiptRegister', 'P') IS NOT NULL
BEGIN SET @old = 'sp_rpt_CollectionReceiptRegister' + @sfx; EXEC sp_rename 'dbo.sp_rpt_CollectionReceiptRegister', @old; END
IF OBJECT_ID('dbo.sp_rpt_InvoiceRegister', 'P') IS NOT NULL
BEGIN SET @old = 'sp_rpt_InvoiceRegister' + @sfx; EXEC sp_rename 'dbo.sp_rpt_InvoiceRegister', @old; END
IF OBJECT_ID('dbo.fn_rpt_DocNoSplit', 'IF') IS NOT NULL
BEGIN SET @old = 'fn_rpt_DocNoSplit' + @sfx; EXEC sp_rename 'dbo.fn_rpt_DocNoSplit', @old; END
GO

------------------------------------------------------------------
-- 1. Series + number of a typed document number
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE FUNCTION dbo.fn_rpt_DocNoSplit
(
    @DocNo VARCHAR(100)
)
RETURNS TABLE
AS
/*
    Returns: one row.
        CleanNo  the number as typed, trimmed
        Series   the text before its trailing digits, trimmed, upper case
                 ('C-04803' -> 'C-', 'P_ 010645' -> 'P_', 'J329606' -> 'J', '24683' -> '')
        SeqNo    the trailing digits as a number (NULL when there are none, or more than 18)
    Callers: sp_rpt_InvoiceRegister, sp_rpt_CollectionReceiptRegister. [92] 2026-10-15.
*/
RETURN
SELECT
    c.s AS CleanNo,
    CASE WHEN c.nd BETWEEN 1 AND 18 THEN UPPER(RTRIM(LEFT(c.s, LEN(c.s) - c.nd))) ELSE UPPER(c.s) END AS Series,
    CASE WHEN c.nd BETWEEN 1 AND 18 THEN CAST(RIGHT(c.s, c.nd) AS BIGINT) END AS SeqNo
FROM
(
    SELECT x.s,
           CASE WHEN x.s = '' THEN 0
                WHEN PATINDEX('%[^0-9]%', REVERSE(x.s)) = 0 THEN LEN(x.s)
                ELSE PATINDEX('%[^0-9]%', REVERSE(x.s)) - 1 END AS nd
    FROM (SELECT LTRIM(RTRIM(ISNULL(@DocNo, ''))) AS s) AS x
) AS c;
GO

------------------------------------------------------------------
-- 2. Invoice No. register
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
IF OBJECT_ID('dbo.fn_rpt_DocNoSplit', 'IF') IS NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[92] stopped: fn_rpt_DocNoSplit was not created; everything rolled back.', 16, 1);
    SET NOEXEC ON;
END
GO
CREATE PROCEDURE dbo.sp_rpt_InvoiceRegister
    @DateFrom   DATE,
    @DateTo     DATE,
    @BranchCode VARCHAR(10) = NULL     -- NULL / '' / 'ALL' = all branches
AS
/*
    Returns: one row per invoiced sales-order delivery (DeliverySummary with an
    InvoiceNo; STS transfers excluded), invoice date in the range, sorted by
    Series and Number:
        Branch (code - name), Series, InvoiceNo, SeqNo, InvoiceDate, PONumber,
        Customer (key - name), Amount / AmountPaid / Balance / PayStatus (the AR
        invoice row, matched by InvoiceNo + PO + customer), DeliveryStatus, Note
    Note: DUPLICATE (the number is on more than one delivery), GAP / JUMP (the
    numbers skipped before this one in the series), NO NUMBER, RETURNED; judged
    against every invoice of the branch's series (branch + prefix), all dates.
    Callers: AccountingDevEx/AccountingRegistersFrm (Invoice Register tab). [92] 2026-10-15.
*/
BEGIN
    SET NOCOUNT ON;

    DECLARE @All BIT = CASE WHEN NULLIF(LTRIM(RTRIM(ISNULL(@BranchCode, ''))), '') IS NULL OR @BranchCode = 'ALL' THEN 1 ELSE 0 END;

    ;WITH inv AS (
        SELECT d.DeliveryNo, d.PONumber, d.BranchCode, d.InvoiceNo, CAST(d.EffectivityDate AS DATE) AS InvoiceDate,
               d.Status AS DeliveryStatus, p.Customer AS CustomerKey, sp.Series, sp.SeqNo, sp.CleanNo
        FROM dbo.DeliverySummary AS d
        INNER JOIN dbo.PurchaseOrderSummary AS p
            ON p.PONumber = d.PONumber
        CROSS APPLY dbo.fn_rpt_DocNoSplit(d.InvoiceNo) AS sp
        WHERE LTRIM(RTRIM(ISNULL(d.InvoiceNo, ''))) <> ''
          AND NOT EXISTS (SELECT 1 FROM dbo.TransferOrderSummary AS t WHERE t.PONumber = d.PONumber)
    ),
    nums AS (
        SELECT DISTINCT BranchCode, Series, SeqNo FROM inv WHERE SeqNo IS NOT NULL
    ),
    prev AS (
        SELECT BranchCode, Series, SeqNo, LAG(SeqNo) OVER (PARTITION BY BranchCode, Series ORDER BY SeqNo) AS PrevNo
        FROM nums
    ),
    marked AS (
        SELECT i.*,
               COUNT(*) OVER (PARTITION BY i.BranchCode, i.Series, ISNULL(i.SeqNo, -1), CASE WHEN i.SeqNo IS NULL THEN i.CleanNo ELSE '' END) AS SameNo,
               pv.PrevNo
        FROM inv AS i
        LEFT JOIN prev AS pv
            ON pv.BranchCode = i.BranchCode AND pv.Series = i.Series AND pv.SeqNo = i.SeqNo
    )
    SELECT
        CONCAT(m.BranchCode, ' - ', br.BranchName)                   AS Branch,
        CASE WHEN m.Series = '' THEN '(no prefix)' ELSE m.Series END AS Series,
        m.InvoiceNo,
        m.SeqNo,
        m.InvoiceDate,
        m.PONumber,
        CONCAT(m.CustomerKey, ' - ', c.CustomerName)                 AS Customer,
        CAST(ISNULL(ar.Amount, 0) AS DECIMAL(18,2))                  AS Amount,
        CAST(ISNULL(ar.AmountPaid, 0) AS DECIMAL(18,2))              AS AmountPaid,
        CAST(ISNULL(ar.Balance, 0) AS DECIMAL(18,2))                 AS Balance,
        ar.PayStatus,
        m.DeliveryStatus,
        NULLIF(CONCAT_WS('; ',
            CASE WHEN m.SeqNo IS NULL THEN 'NO NUMBER (no trailing digits)' END,
            CASE WHEN m.SameNo > 1 THEN CONCAT('DUPLICATE (', m.SameNo, ' deliveries)') END,
            CASE WHEN m.PrevNo IS NOT NULL AND m.SeqNo - m.PrevNo BETWEEN 2 AND 51
                 THEN CONCAT('GAP: ', m.SeqNo - m.PrevNo - 1, ' skipped (', m.PrevNo + 1, CASE WHEN m.SeqNo - m.PrevNo > 2 THEN CONCAT('-', m.SeqNo - 1) ELSE '' END, ')') END,
            CASE WHEN m.PrevNo IS NOT NULL AND m.SeqNo - m.PrevNo > 51
                 THEN CONCAT('JUMP: ', m.SeqNo - m.PrevNo - 1, ' skipped after ', m.PrevNo, ' (check the number typed)') END,
            CASE WHEN m.DeliveryStatus = 'RETURNED' THEN 'RETURNED' END), '') AS Note
    FROM marked AS m
    LEFT JOIN dbo.Branches AS br
        ON br.BranchCode = m.BranchCode
    LEFT JOIN dbo.Customers AS c
        ON c.CustomerKey = m.CustomerKey
    OUTER APPLY (
        SELECT SUM(t.TotalAmount) AS Amount, SUM(t.AmountPaid) AS AmountPaid, SUM(t.Balance) AS Balance, MAX(t.PayStatus) AS PayStatus
        FROM dbo.TransactionChargeSales AS t
        WHERE t.InvoiceNo = m.InvoiceNo AND t.ReferenceNo = m.PONumber AND t.CustomerKey = m.CustomerKey
    ) AS ar
    WHERE m.InvoiceDate >= @DateFrom
      AND m.InvoiceDate <  DATEADD(DAY, 1, @DateTo)
      AND (@All = 1 OR m.BranchCode = @BranchCode)
    ORDER BY m.BranchCode, m.Series, CASE WHEN m.SeqNo IS NULL THEN 1 ELSE 0 END, m.SeqNo, m.InvoiceNo, m.PONumber
    OPTION (RECOMPILE);
END
GO

------------------------------------------------------------------
-- 3. Collection Receipt register
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
IF OBJECT_ID('dbo.sp_rpt_InvoiceRegister', 'P') IS NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[92] stopped: sp_rpt_InvoiceRegister was not created; everything rolled back.', 16, 1);
    SET NOEXEC ON;
END
GO
CREATE PROCEDURE dbo.sp_rpt_CollectionReceiptRegister
    @DateFrom   DATE,
    @DateTo     DATE,
    @BranchCode VARCHAR(10) = NULL     -- NULL / '' / 'ALL' = all branches (the customer's branch)
AS
/*
    Returns: one row per AR payment (PaymentHeader), payment date in the range,
    sorted by CR No. series and number:
        Branch (the customer's, code - name), Series, CRNo, SeqNo, PaymentDate,
        ControlNo, ReferenceNo, Customer (key - name), PaymentType,
        AmountReceived (PaymentHeader.TotalAmount), AppliedToInvoices, EWT,
        Discount (from ARPaymentDetails, ErrorTag <> 1), Invoices (the invoice
        nos. paid), Status, Note
    Note: DUPLICATE (the CR No. is on more than one payment that is not
    reversed), GAP / JUMP, NO CR NO. / NO NUMBER, REVERSED; judged against every
    receipt of the branch's series (customer branch + prefix), all dates (a reversed receipt's number
    counts as used, and may be typed again on its replacement).
    Callers: AccountingDevEx/AccountingRegistersFrm (Collection Receipt Register tab). [92] 2026-10-15.
*/
BEGIN
    SET NOCOUNT ON;

    DECLARE @All BIT = CASE WHEN NULLIF(LTRIM(RTRIM(ISNULL(@BranchCode, ''))), '') IS NULL OR @BranchCode = 'ALL' THEN 1 ELSE 0 END;

    ;WITH cr AS (
        SELECT ph.PaymentHeaderID, ph.CRNo, ph.ControlNo, ph.ReferenceNo, ph.CustomerKey, c.CustomerName, c.BranchCode,
               ph.PaymentType, ph.TotalAmount, CAST(ph.PaymentDate AS DATE) AS PaymentDate, ph.Status,
               CASE WHEN ISNULL(ph.Status, '') = 'REVERSED' THEN 1 ELSE 0 END AS IsReversed,
               sp.Series, sp.SeqNo, sp.CleanNo
        FROM dbo.PaymentHeader AS ph
        LEFT JOIN dbo.Customers AS c
            ON c.CustomerKey = ph.CustomerKey
        CROSS APPLY dbo.fn_rpt_DocNoSplit(ph.CRNo) AS sp
    ),
    nums AS (
        SELECT DISTINCT BranchCode, Series, SeqNo FROM cr WHERE SeqNo IS NOT NULL
    ),
    prev AS (
        SELECT BranchCode, Series, SeqNo, LAG(SeqNo) OVER (PARTITION BY BranchCode, Series ORDER BY SeqNo) AS PrevNo
        FROM nums
    ),
    marked AS (
        SELECT r.*,
               SUM(CASE WHEN r.IsReversed = 0 THEN 1 ELSE 0 END)
                   OVER (PARTITION BY r.BranchCode, r.Series, ISNULL(r.SeqNo, -1), CASE WHEN r.SeqNo IS NULL THEN r.CleanNo ELSE '' END) AS LiveSameNo,
               pv.PrevNo
        FROM cr AS r
        LEFT JOIN prev AS pv
            ON pv.BranchCode = r.BranchCode AND pv.Series = r.Series AND pv.SeqNo = r.SeqNo
    )
    SELECT
        CONCAT(m.BranchCode, ' - ', br.BranchName)                     AS Branch,
        CASE WHEN m.Series = '' THEN '(no prefix)' ELSE m.Series END   AS Series,
        m.CRNo,
        m.SeqNo,
        m.PaymentDate,
        m.ControlNo,
        m.ReferenceNo,
        CONCAT(m.CustomerKey, ' - ', m.CustomerName)                   AS Customer,
        m.PaymentType,
        CAST(ISNULL(m.TotalAmount, 0) AS DECIMAL(18,2))                AS AmountReceived,
        CAST(ISNULL(det.Applied, 0) AS DECIMAL(18,2))                  AS AppliedToInvoices,
        CAST(ISNULL(det.Ewt, 0) AS DECIMAL(18,2))                      AS EWT,
        CAST(ISNULL(det.Discount, 0) AS DECIMAL(18,2))                 AS Discount,
        inv.Invoices,
        m.Status,
        NULLIF(CONCAT_WS('; ',
            CASE WHEN m.CleanNo = '' THEN 'NO CR NO.'
                 WHEN m.SeqNo IS NULL THEN 'NO NUMBER (no trailing digits)' END,
            CASE WHEN m.IsReversed = 0 AND m.CleanNo <> '' AND m.LiveSameNo > 1 THEN CONCAT('DUPLICATE (', m.LiveSameNo, ' payments)') END,
            CASE WHEN m.PrevNo IS NOT NULL AND m.SeqNo - m.PrevNo BETWEEN 2 AND 51
                 THEN CONCAT('GAP: ', m.SeqNo - m.PrevNo - 1, ' skipped (', m.PrevNo + 1, CASE WHEN m.SeqNo - m.PrevNo > 2 THEN CONCAT('-', m.SeqNo - 1) ELSE '' END, ')') END,
            CASE WHEN m.PrevNo IS NOT NULL AND m.SeqNo - m.PrevNo > 51
                 THEN CONCAT('JUMP: ', m.SeqNo - m.PrevNo - 1, ' skipped after ', m.PrevNo, ' (check the number typed)') END,
            CASE WHEN m.IsReversed = 1 THEN 'REVERSED' END), '')        AS Note
    FROM marked AS m
    LEFT JOIN dbo.Branches AS br
        ON br.BranchCode = m.BranchCode
    OUTER APPLY (
        SELECT SUM(CASE WHEN d.PaymentType = 'INVOICE PAYMENT' THEN d.Amount ELSE 0 END) AS Applied,
               SUM(CASE WHEN d.PaymentType = 'EWT' THEN d.Amount ELSE 0 END)             AS Ewt,
               SUM(CASE WHEN d.PaymentType = 'DISCOUNT' THEN d.Amount ELSE 0 END)        AS Discount
        FROM dbo.ARPaymentDetails AS d
        WHERE d.PaymentHeaderID = m.PaymentHeaderID
          AND (d.ErrorTag IS NULL OR d.ErrorTag <> 1)
    ) AS det
    OUTER APPLY (
        SELECT STRING_AGG(x.InvoiceNo, ', ') WITHIN GROUP (ORDER BY x.InvoiceNo) AS Invoices
        FROM (SELECT DISTINCT d.InvoiceNo
              FROM dbo.ARPaymentDetails AS d
              WHERE d.PaymentHeaderID = m.PaymentHeaderID
                AND d.PaymentType = 'INVOICE PAYMENT'
                AND LTRIM(RTRIM(ISNULL(d.InvoiceNo, ''))) <> '') AS x
    ) AS inv
    WHERE m.PaymentDate >= @DateFrom
      AND m.PaymentDate <  DATEADD(DAY, 1, @DateTo)
      AND (@All = 1 OR m.BranchCode = @BranchCode)
    ORDER BY m.BranchCode, CASE WHEN m.CleanNo = '' THEN 1 ELSE 0 END, m.Series, CASE WHEN m.SeqNo IS NULL THEN 1 ELSE 0 END, m.SeqNo, m.PaymentHeaderID
    OPTION (RECOMPILE);
END
GO

------------------------------------------------------------------
-- 4. EWT payable ledger (20104), paid / unpaid by FIFO
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
IF OBJECT_ID('dbo.sp_rpt_CollectionReceiptRegister', 'P') IS NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[92] stopped: sp_rpt_CollectionReceiptRegister was not created; everything rolled back.', 16, 1);
    SET NOEXEC ON;
END
GO
CREATE PROCEDURE dbo.sp_rpt_EWTPayableLedger
    @DateFrom    DATE,
    @DateTo      DATE,
    @BranchCode  VARCHAR(10) = NULL,   -- NULL / '' / 'ALL' = all branches (display filter only)
    @AccountCode VARCHAR(20) = NULL    -- NULL = the EWT payable account of JournalEntryMapping (PV-AP-EWT / EWT / C)
AS
/*
    Returns: the EWT payable ledger in date order:
        Kind (BEGINNING / OPENING / WITHHELD / REMITTANCE / REVERSAL), TicketDate,
        TicketNumber, Branch (code - name), ReferenceNumber, Payee (the ticket's
        Owner), Particulars, Withheld (credit), Remitted (debit), Paid, Unpaid,
        Status (PAID / PARTIAL / UNPAID / REVERSED, as of @DateTo), RunningBalance
        (all branches)
    Paid / Unpaid by FIFO: the remittances up to @DateTo (company-wide) pay the
    withheld amounts oldest first. A debit whose reference + branch also holds a
    credit on the account is a REVERSAL of that document, not a remittance: it
    cancels the document's own withheld amount (oldest first). The branch filter
    hides other branches' lines; remittances and the running balance stay
    company-wide.
    Callers: AccountingDevEx/AccountingRegistersFrm (EWT Payable tab). [92] 2026-10-15.
*/
BEGIN
    SET NOCOUNT ON;

    DECLARE @All BIT = CASE WHEN NULLIF(LTRIM(RTRIM(ISNULL(@BranchCode, ''))), '') IS NULL OR @BranchCode = 'ALL' THEN 1 ELSE 0 END;
    DECLARE @Acct VARCHAR(20) = NULLIF(LTRIM(RTRIM(ISNULL(@AccountCode, ''))), '');

    IF @Acct IS NULL
        SELECT TOP (1) @Acct = m.AccountCode
        FROM dbo.JournalEntryMapping AS m
        WHERE m.Mnemonic = 'PV-AP-EWT' AND m.AmountType = 'EWT' AND m.DebitCredit = 'C' AND m.IsActive = 1
        ORDER BY m.Seq;

    IF @Acct IS NULL
        THROW 59895, 'No EWT payable account: JournalEntryMapping has no active PV-AP-EWT / EWT credit row. Pass @AccountCode.', 1;

    -- every line on the account up to @DateTo; the ticket master only for descriptions (the amounts come from the
    -- lines, like the real-time Trial Balance: a master join on TicketNumber + BranchCode drops lines)
    IF OBJECT_ID('tempdb..#L') IS NOT NULL DROP TABLE #L;
    SELECT
        ROW_NUMBER() OVER (ORDER BY CAST(td.TicketDate AS DATE), TRY_CAST(td.TicketNumber AS BIGINT), td.TicketNumber, td.BranchCode,
                                    td.Debit, td.Credit DESC, td.ReferenceNumber) AS Seq,
        CAST(td.TicketDate AS DATE)       AS TicketDate,
        td.TicketNumber,
        td.BranchCode,
        ISNULL(td.ReferenceNumber, '')    AS ReferenceNumber,
        CAST(ISNULL(td.Debit, 0) AS DECIMAL(18,2))  AS Debit,
        CAST(ISNULL(td.Credit, 0) AS DECIMAL(18,2)) AS Credit,
        tm.Mnemonic,
        tm.Owner,
        COALESCE(NULLIF(LTRIM(RTRIM(td.Particulars)), ''), tm.Particulars) AS Particulars,
        CAST(NULL AS VARCHAR(12))   AS Kind,
        CAST(0 AS DECIMAL(18,2))    AS ReversedAmt,
        CAST(NULL AS DECIMAL(18,2)) AS NetWithheld,
        CAST(NULL AS DECIMAL(18,2)) AS Paid
    INTO #L
    FROM dbo.TicketDetails AS td
    OUTER APPLY (SELECT TOP (1) m.Mnemonic, m.Owner, m.Particulars
                 FROM dbo.TicketMaster AS m
                 WHERE m.TicketNumber = td.TicketNumber
                 ORDER BY CASE WHEN m.BranchCode = td.BranchCode THEN 0 ELSE 1 END) AS tm
    WHERE td.AccountCode = @Acct
      AND CAST(td.TicketDate AS DATE) <= @DateTo
      AND (ISNULL(td.Debit, 0) <> 0 OR ISNULL(td.Credit, 0) <> 0);

    -- kinds
    UPDATE l SET Kind =
        CASE WHEN l.Credit > 0 AND l.Mnemonic = '*' THEN 'OPENING'
             WHEN l.Credit > 0 THEN 'WITHHELD'
             WHEN l.ReferenceNumber <> ''
                  AND EXISTS (SELECT 1 FROM #L AS c WHERE c.Credit > 0 AND c.ReferenceNumber = l.ReferenceNumber AND c.BranchCode = l.BranchCode)
                  THEN 'REVERSAL'
             ELSE 'REMITTANCE' END
    FROM #L AS l;

    -- a reversal cancels its own document's withheld amounts, oldest first
    ;WITH rev AS (
        SELECT ReferenceNumber, BranchCode, SUM(Debit) AS RevAmt FROM #L WHERE Kind = 'REVERSAL' GROUP BY ReferenceNumber, BranchCode
    ),
    cr AS (
        SELECT l.Seq, l.Credit, r.RevAmt,
               SUM(l.Credit) OVER (PARTITION BY l.ReferenceNumber, l.BranchCode ORDER BY l.Seq ROWS UNBOUNDED PRECEDING) - l.Credit AS CumBefore
        FROM #L AS l
        INNER JOIN rev AS r ON r.ReferenceNumber = l.ReferenceNumber AND r.BranchCode = l.BranchCode
        WHERE l.Kind IN ('OPENING', 'WITHHELD')
    )
    UPDATE l SET ReversedAmt = CASE WHEN c.RevAmt - c.CumBefore <= 0 THEN 0
                                    WHEN c.RevAmt - c.CumBefore >= c.Credit THEN c.Credit
                                    ELSE c.RevAmt - c.CumBefore END
    FROM #L AS l INNER JOIN cr AS c ON c.Seq = l.Seq;

    UPDATE #L SET NetWithheld = Credit - ReversedAmt WHERE Kind IN ('OPENING', 'WITHHELD');

    -- FIFO: the remittances up to @DateTo pay the oldest net withheld amounts first
    DECLARE @Remitted DECIMAL(18,2) = ISNULL((SELECT SUM(Debit) FROM #L WHERE Kind = 'REMITTANCE'), 0);
    ;WITH w AS (
        SELECT Seq, NetWithheld,
               SUM(NetWithheld) OVER (ORDER BY Seq ROWS UNBOUNDED PRECEDING) - NetWithheld AS CumBefore
        FROM #L WHERE Kind IN ('OPENING', 'WITHHELD')
    )
    UPDATE l SET Paid = CASE WHEN @Remitted - w.CumBefore <= 0 THEN 0
                             WHEN @Remitted - w.CumBefore >= w.NetWithheld THEN w.NetWithheld
                             ELSE @Remitted - w.CumBefore END
    FROM #L AS l INNER JOIN w ON w.Seq = l.Seq;

    DECLARE @Beginning DECIMAL(18,2) = ISNULL((SELECT SUM(Credit - Debit) FROM #L WHERE TicketDate < @DateFrom), 0);

    SELECT Kind, TicketDate, TicketNumber, Branch, ReferenceNumber, Payee, Particulars,
           Withheld, Remitted, Paid, Unpaid, Status, RunningBalance
    FROM
    (
        SELECT 0 AS SortKey, 'BEGINNING' AS Kind, @DateFrom AS TicketDate, CAST(NULL AS VARCHAR(20)) AS TicketNumber,
               CAST(NULL AS VARCHAR(20)) AS BranchCode, CAST(NULL AS VARCHAR(200)) AS Branch, CAST(NULL AS VARCHAR(50)) AS ReferenceNumber, CAST(NULL AS VARCHAR(200)) AS Payee,
               CONCAT('Balance of ', @Acct, ' before ', CONVERT(VARCHAR(10), @DateFrom, 120), ' (all branches)') AS Particulars,
               CAST(NULL AS DECIMAL(18,2)) AS Withheld, CAST(NULL AS DECIMAL(18,2)) AS Remitted,
               CAST(NULL AS DECIMAL(18,2)) AS Paid, CAST(NULL AS DECIMAL(18,2)) AS Unpaid,
               CAST(NULL AS VARCHAR(10)) AS Status, @Beginning AS RunningBalance, 0 AS Seq
        UNION ALL
        SELECT 1, l.Kind, l.TicketDate, l.TicketNumber, l.BranchCode, CONCAT(l.BranchCode, ' - ', br.BranchName), l.ReferenceNumber, l.Owner, l.Particulars,
               CASE WHEN l.Credit > 0 THEN l.Credit END,
               CASE WHEN l.Debit > 0 THEN l.Debit END,
               l.Paid,
               CASE WHEN l.NetWithheld IS NOT NULL THEN l.NetWithheld - l.Paid END,
               CASE WHEN l.Kind NOT IN ('OPENING', 'WITHHELD') THEN NULL
                    WHEN l.NetWithheld = 0 THEN 'REVERSED'
                    WHEN l.Paid >= l.NetWithheld THEN 'PAID'
                    WHEN l.Paid > 0 THEN 'PARTIAL'
                    ELSE 'UNPAID' END,
               SUM(l.Credit - l.Debit) OVER (ORDER BY l.Seq ROWS UNBOUNDED PRECEDING),
               l.Seq
        FROM #L AS l   -- every line up to @DateTo: the running balance is taken here, before the filter below
        LEFT JOIN dbo.Branches AS br
            ON br.BranchCode = l.BranchCode
    ) AS x
    WHERE x.SortKey = 0
       OR (x.TicketDate >= @DateFrom
           AND (@All = 1 OR x.BranchCode = @BranchCode))
    ORDER BY x.SortKey, x.Seq;

    DROP TABLE #L;
END
GO

------------------------------------------------------------------
-- 5. Post-check, then commit
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF OBJECT_ID('dbo.fn_rpt_DocNoSplit', 'IF') IS NULL OR OBJECT_ID('dbo.sp_rpt_InvoiceRegister', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_rpt_CollectionReceiptRegister', 'P') IS NULL OR OBJECT_ID('dbo.sp_rpt_EWTPayableLedger', 'P') IS NULL
    SET @msg = N'an object was not created';
ELSE IF NOT EXISTS (SELECT 1 FROM dbo.fn_rpt_DocNoSplit('P_ 010645') WHERE Series = 'P_' AND SeqNo = 10645)
     OR NOT EXISTS (SELECT 1 FROM dbo.fn_rpt_DocNoSplit('J329606')   WHERE Series = 'J'  AND SeqNo = 329606)
     OR NOT EXISTS (SELECT 1 FROM dbo.fn_rpt_DocNoSplit('DELA ROSA') WHERE Series = 'DELA ROSA' AND SeqNo IS NULL)
     OR NOT EXISTS (SELECT 1 FROM dbo.fn_rpt_DocNoSplit('24683')     WHERE Series = '' AND SeqNo = 24683)
    SET @msg = N'fn_rpt_DocNoSplit does not split the sample numbers as designed';

IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[92] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59896, @msg, 1;
END

COMMIT TRANSACTION;
PRINT '[92] committed: fn_rpt_DocNoSplit, sp_rpt_InvoiceRegister, sp_rpt_CollectionReceiptRegister, sp_rpt_EWTPayableLedger.';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
