/* ================================================================
   Bank Recon checks for the web Exception Center (handoff 2026-10-09)
   ================================================================
   Read-only. Four parts, each between ">>>" / "<<<" markers:
     1. FUNCTION    dbo.fn_rpt_BankRecon_GLvsRecon: the GL-vs-recon match, shared by
                    four checks (create it once, in the web tool's next sql/NN file)
     2. DEFINITIONS rows for dbo.ExceptionDefinition (category "Bank Recon")
     3. SUMMARY     INSERT blocks for sp_rpt_ExceptionCenter_Summary (at the
                    "Future checks land here" marker). They use the proc's existing
                    @Start, @End, @StaleAsOf, @AsOf and #Result.
     4. DETAIL      IF blocks for sp_rpt_ExceptionCenter_Detail (same variables).
   New placeholder variable for both procs: @DITStaleDays int = 7.
   Tested 2026-10-09 against CORECSJFC2026_STAGING (copy of production, 2026-10-08)
   inside a rolled-back transaction; the handoff lists the counts it returned.
   ================================================================ */

-- >>> FUNCTION
CREATE FUNCTION dbo.fn_rpt_BankRecon_GLvsRecon ()
RETURNS TABLE
AS
/*
    One row per bank account + reference: the GL movement on the account since the ERP
    go-live (2026-08-01; the 2026-07-31 opening is covered by the BF-PEACHTREE items)
    against the Bank Recon items with the same reference (BankStatementRecon.SourceRef =
    TicketDetails.ReferenceNumber). DIT counts +, OC counts -, reversed / voided items 0.
    Result: OK, GL NETS TO 0, RECON NETS TO 0, JULY ITEM (harmless) or
            GL ONLY, RECON ONLY, AMOUNT DIFFERS, OTHER MONTH (exceptions).
    Same rule as the ERP's tools/ExceptionCenter/BankRecon_GLvsRecon_Check.sql.
*/
RETURN
    WITH GL AS (
        SELECT  td.AccountCode,
                ISNULL(NULLIF(LTRIM(RTRIM(td.ReferenceNumber)), ''), '(blank)')          AS Ref,
                CAST(SUM(ISNULL(td.Debit, 0) - ISNULL(td.Credit, 0)) AS DECIMAL(18,2))  AS GLNet,
                COUNT(*)                                                                AS GLLines,
                MIN(CAST(td.TicketDate AS DATE))                                        AS GLDate1,
                MAX(CAST(td.TicketDate AS DATE))                                        AS GLDate2,
                MIN(td.TicketNumber)                                                    AS Ticket1
        FROM dbo.TicketDetails AS td
        WHERE td.AccountCode LIKE '10102%' AND td.TicketDate >= '2026-08-01'
        GROUP BY td.AccountCode, ISNULL(NULLIF(LTRIM(RTRIM(td.ReferenceNumber)), ''), '(blank)')),
    RC AS (
        SELECT  b.AccountCode,
                ISNULL(NULLIF(LTRIM(RTRIM(b.SourceRef)), ''), '(blank)')                 AS Ref,
                CAST(SUM(CASE WHEN ISNULL(b.ResolvedReason, '') = 'REVERSED' OR ISNULL(b.ResolvedReason, '') LIKE 'VOIDED%' THEN 0
                              WHEN b.ItemType = 'DIT' THEN b.Amount ELSE -b.Amount END) AS DECIMAL(18,2)) AS RecNet,
                COUNT(*)                                                                AS RecItems,
                MAX(b.SourceModule)                                                     AS Src,
                MIN(h.PeriodEnd)                                                        AS Period1,
                MAX(h.PeriodEnd)                                                        AS Period2,
                MIN(CAST(b.ItemDate AS DATE))                                           AS ItemDate1,
                MIN(b.ReconID)                                                          AS ReconID1
        FROM dbo.BankStatementRecon AS b
        LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
        WHERE b.AccountCode LIKE '10102%' AND b.ItemType IN ('DIT', 'OC')
          AND ISNULL(b.SourceModule, '') <> 'BF-PEACHTREE'
        GROUP BY b.AccountCode, ISNULL(NULLIF(LTRIM(RTRIM(b.SourceRef)), ''), '(blank)'))
    SELECT  COALESCE(g.AccountCode, r.AccountCode) AS AccountCode,
            COALESCE(g.Ref, r.Ref)                 AS Ref,
            g.GLNet, g.GLLines, g.GLDate1, g.GLDate2, g.Ticket1,
            r.RecNet, r.RecItems, r.Src, r.Period1, r.Period2, r.ItemDate1, r.ReconID1,
            COALESCE(g.GLDate1, r.ItemDate1)       AS SortDate,
            CASE WHEN g.Ref IS NULL AND r.RecNet = 0                 THEN 'RECON NETS TO 0'
                 WHEN g.Ref IS NULL AND r.Period2 < '2026-08-01'     THEN 'JULY ITEM'
                 WHEN g.Ref IS NULL                                  THEN 'RECON ONLY'
                 WHEN r.Ref IS NULL AND g.GLNet = 0                  THEN 'GL NETS TO 0'
                 WHEN r.Ref IS NULL                                  THEN 'GL ONLY'
                 WHEN g.GLNet <> r.RecNet                            THEN 'AMOUNT DIFFERS'
                 WHEN EOMONTH(g.GLDate1) <> r.Period1 AND g.GLNet <> 0 THEN 'OTHER MONTH'
                 ELSE 'OK' END                     AS Result
    FROM GL AS g
    FULL OUTER JOIN RC AS r ON r.AccountCode = g.AccountCode AND r.Ref = g.Ref;
-- <<<

-- >>> DEFINITIONS
INSERT INTO dbo.ExceptionDefinition (ExceptionCode, Category, Title, Severity, HasDrillDown, DrillDownRoute, IsActive, SortOrder) VALUES
('BRC-GL-NO-RECON-ITEM',        'Bank Recon', 'Bank movement in the GL with no reconciling item to tick',          'Critical', 1, '/ExceptionCenter/Detail?code=BRC-GL-NO-RECON-ITEM',        1, 70),
('BRC-AMOUNT-MISMATCH',         'Bank Recon', 'Reconciling item amount differs from its GL entry',                 'Critical', 1, '/ExceptionCenter/Detail?code=BRC-AMOUNT-MISMATCH',         1, 71),
('BRC-RECON-NO-GL',             'Bank Recon', 'Reconciling item with no GL entry (duplicate or wrong account)',     'Warning',  1, '/ExceptionCenter/Detail?code=BRC-RECON-NO-GL',             1, 72),
('BRC-DUP-RECON-ITEM',          'Bank Recon', 'Possible duplicate reconciling item',                               'Warning',  1, '/ExceptionCenter/Detail?code=BRC-DUP-RECON-ITEM',          1, 73),
('BRC-WRONG-PERIOD',            'Bank Recon', 'Reconciling item filed under a different month than its GL entry',  'Warning',  1, '/ExceptionCenter/Detail?code=BRC-WRONG-PERIOD',            1, 74),
('BRC-REVERSED-LATER-MONTH',    'Bank Recon', 'Reversed in a later month but hidden from the original month',      'Warning',  1, '/ExceptionCenter/Detail?code=BRC-REVERSED-LATER-MONTH',    1, 75),
('BRC-CLEARED-NO-REASON',       'Bank Recon', 'Item cleared outside the Bank Recon screen (Auto-Match / old screen)', 'Warning', 1, '/ExceptionCenter/Detail?code=BRC-CLEARED-NO-REASON',     1, 76),
('BRC-CLEARED-MONTH-INCONSISTENT','Bank Recon','Cleared flag and cleared month disagree',                          'Critical', 1, '/ExceptionCenter/Detail?code=BRC-CLEARED-MONTH-INCONSISTENT', 1, 77),
('BRC-LOCKED-OUT-OF-BALANCE',   'Bank Recon', 'Locked reconciliation period that no longer balances',              'Critical', 1, '/ExceptionCenter/Detail?code=BRC-LOCKED-OUT-OF-BALANCE',   1, 78),
('BRC-PERIOD-OUT-OF-BALANCE',   'Bank Recon', 'Reconciliation period with a statement balance but a difference',   'Warning',  1, '/ExceptionCenter/Detail?code=BRC-PERIOD-OUT-OF-BALANCE',   1, 79),
('BRC-NO-STATEMENT-BALANCE',    'Bank Recon', 'Month ended but no bank statement balance entered',                 'Warning',  1, '/ExceptionCenter/Detail?code=BRC-NO-STATEMENT-BALANCE',    1, 80),
('BRC-NO-OPENING-LIST',         'Bank Recon', 'Bank account with an opening balance but no opening reconciliation','Warning',  1, '/ExceptionCenter/Detail?code=BRC-NO-OPENING-LIST',         1, 81),
('BRC-STALE-DIT',               'Bank Recon', 'Deposits in transit not cleared after N days',                      'Warning',  1, '/ExceptionCenter/Detail?code=BRC-STALE-DIT',               1, 82);
-- <<<

-- >>> SUMMARY
/* ---- Bank Recon (BRC-*), handoff 2026-10-09 ---- */
INSERT INTO #Result (ExceptionCode, Findings, ValueAtRisk)
SELECT 'BRC-GL-NO-RECON-ITEM', COUNT(*), SUM(ABS(m.GLNet))
FROM dbo.fn_rpt_BankRecon_GLvsRecon() AS m
WHERE m.Result = 'GL ONLY' AND m.SortDate >= @Start AND m.SortDate < @End;

INSERT INTO #Result (ExceptionCode, Findings, ValueAtRisk)
SELECT 'BRC-AMOUNT-MISMATCH', COUNT(*), SUM(ABS(m.GLNet - m.RecNet))
FROM dbo.fn_rpt_BankRecon_GLvsRecon() AS m
WHERE m.Result = 'AMOUNT DIFFERS' AND m.SortDate >= @Start AND m.SortDate < @End;

INSERT INTO #Result (ExceptionCode, Findings, ValueAtRisk)
SELECT 'BRC-RECON-NO-GL', COUNT(*), SUM(ABS(m.RecNet))
FROM dbo.fn_rpt_BankRecon_GLvsRecon() AS m
WHERE m.Result = 'RECON ONLY' AND m.SortDate >= @Start AND m.SortDate < @End;

;WITH live AS (   -- live (not reversed / voided) DIT / OC items with an amount
    SELECT b.ReconID, b.AccountCode, b.ItemType, b.SourceModule, b.SourceRef, b.ItemDate, b.Amount, ISNULL(b.SourceRef, '') AS Ref
    FROM dbo.BankStatementRecon AS b
    WHERE b.ItemType IN ('DIT', 'OC') AND b.AccountCode LIKE '10102%' AND b.Amount <> 0
      AND ISNULL(b.ResolvedReason, '') <> 'REVERSED' AND ISNULL(b.ResolvedReason, '') NOT LIKE 'VOIDED%'),
gl AS (SELECT DISTINCT td.AccountCode, td.ReferenceNumber FROM dbo.TicketDetails AS td WHERE td.AccountCode LIKE '10102%'),
w AS (
    SELECT l.*, CASE WHEN g.AccountCode IS NULL THEN 0 ELSE 1 END AS HasGL,
           COUNT(*) OVER (PARTITION BY l.AccountCode, l.ItemType, l.Ref)            AS RefCnt,
           MIN(l.Ref) OVER (PARTITION BY l.AccountCode, l.ItemType, l.Amount, l.ItemDate) AS MinRef,
           MAX(l.Ref) OVER (PARTITION BY l.AccountCode, l.ItemType, l.Amount, l.ItemDate) AS MaxRef
    FROM live AS l
    LEFT JOIN gl AS g ON g.AccountCode = l.AccountCode AND g.ReferenceNumber = l.SourceRef)
INSERT INTO #Result (ExceptionCode, Findings, ValueAtRisk)
SELECT 'BRC-DUP-RECON-ITEM', COUNT(*), SUM(w.Amount)
FROM w
WHERE ((w.Ref <> '' AND w.RefCnt > 1)                                  -- same reference twice on the account
    OR (w.HasGL = 0 AND ISNULL(w.SourceModule, '') NOT IN ('', 'BF-PEACHTREE') AND w.MinRef <> w.MaxRef))   -- no GL, twin of another item
  AND w.ItemDate >= @Start AND w.ItemDate < @End;

INSERT INTO #Result (ExceptionCode, Findings, ValueAtRisk)
SELECT 'BRC-WRONG-PERIOD', COUNT(*), SUM(ABS(m.GLNet))
FROM dbo.fn_rpt_BankRecon_GLvsRecon() AS m
WHERE m.Result = 'OTHER MONTH' AND m.SortDate >= @Start AND m.SortDate < @End;

INSERT INTO #Result (ExceptionCode, Findings, ValueAtRisk)
SELECT 'BRC-REVERSED-LATER-MONTH', COUNT(*), SUM(x.Amount)
FROM (
    SELECT b.ReconID, b.Amount, g.FirstDate, g.LastDate, COALESCE(b.ClearedPeriodEnd, h.PeriodEnd) AS ClearedIn, h.PeriodEnd AS OwnPeriod
    FROM dbo.BankStatementRecon AS b
    LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
    CROSS APPLY (SELECT MIN(CAST(td.TicketDate AS DATE)) AS FirstDate, MAX(CAST(td.TicketDate AS DATE)) AS LastDate
                 FROM dbo.TicketDetails AS td WHERE td.AccountCode = b.AccountCode AND td.ReferenceNumber = b.SourceRef) AS g
    WHERE b.AccountCode LIKE '10102%' AND (b.ResolvedReason = 'REVERSED' OR b.ResolvedReason LIKE 'VOIDED%')) AS x
WHERE x.FirstDate IS NOT NULL AND EOMONTH(x.FirstDate) <> EOMONTH(x.LastDate)
  AND (x.OwnPeriod > EOMONTH(x.FirstDate) OR x.ClearedIn < EOMONTH(x.LastDate))   -- filed after its GL month, or hidden before its reversal month
  AND x.FirstDate >= @Start AND x.FirstDate < @End;

INSERT INTO #Result (ExceptionCode, Findings, ValueAtRisk)
SELECT 'BRC-CLEARED-NO-REASON', COUNT(*), SUM(b.Amount)
FROM dbo.BankStatementRecon AS b
WHERE b.AccountCode LIKE '10102%' AND ISNULL(b.IsResolved, 0) = 1 AND LTRIM(RTRIM(ISNULL(b.ResolvedReason, ''))) = ''
  AND b.ItemDate >= @Start AND b.ItemDate < @End;

INSERT INTO #Result (ExceptionCode, Findings, ValueAtRisk)
SELECT 'BRC-CLEARED-MONTH-INCONSISTENT', COUNT(*), SUM(b.Amount)
FROM dbo.BankStatementRecon AS b
LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
WHERE b.AccountCode LIKE '10102%'
  AND (   (ISNULL(b.IsResolved, 0) = 1 AND b.ClearedPeriodEnd IS NULL
           AND ISNULL(b.ResolvedReason, '') <> 'REVERSED' AND ISNULL(b.ResolvedReason, '') NOT LIKE 'VOIDED%')
       OR (ISNULL(b.IsResolved, 0) = 0 AND b.ClearedPeriodEnd IS NOT NULL)
       OR (b.ClearedPeriodEnd < h.PeriodEnd));

INSERT INTO #Result (ExceptionCode, Findings, ValueAtRisk)
SELECT 'BRC-LOCKED-OUT-OF-BALANCE', COUNT(*), SUM(ABS(f.Difference))
FROM dbo.BankReconHeader AS h
CROSS APPLY dbo.fn_BankRecon_Figures(h.HeaderID) AS f
WHERE h.Status = 'LOCKED' AND f.Difference <> 0;

INSERT INTO #Result (ExceptionCode, Findings, ValueAtRisk)
SELECT 'BRC-PERIOD-OUT-OF-BALANCE', COUNT(*), SUM(ABS(f.Difference))
FROM dbo.BankReconHeader AS h
CROSS APPLY dbo.fn_BankRecon_Figures(h.HeaderID) AS f
WHERE h.Status <> 'LOCKED' AND f.BankStatementBal <> 0 AND f.Difference <> 0
  AND h.PeriodEnd >= @Start AND h.PeriodEnd < @End;

INSERT INTO #Result (ExceptionCode, Findings, ValueAtRisk)
SELECT 'BRC-NO-STATEMENT-BALANCE', COUNT(*), SUM(ABS(f.GLBookBalance))
FROM dbo.BankReconHeader AS h
CROSS APPLY dbo.fn_BankRecon_Figures(h.HeaderID) AS f
WHERE f.BankStatementBal = 0 AND h.PeriodEnd < CAST(@AsOf AS DATE) AND h.AccountCode LIKE '10102%'
  AND h.PeriodEnd >= @Start AND h.PeriodEnd < @End
  AND (f.GLBookBalance <> 0 OR f.OpenDIT <> 0 OR f.OpenOC <> 0);

INSERT INTO #Result (ExceptionCode, Findings, ValueAtRisk)
SELECT 'BRC-NO-OPENING-LIST', COUNT(*), SUM(ABS(o.Opening))
FROM (
    SELECT td.AccountCode, CAST(SUM(ISNULL(td.Debit, 0) - ISNULL(td.Credit, 0)) AS DECIMAL(18,2)) AS Opening
    FROM dbo.TicketDetails AS td
    WHERE td.AccountCode LIKE '10102%' AND td.TicketDate < '2026-08-01'
    GROUP BY td.AccountCode) AS o
WHERE o.Opening <> 0
  AND NOT EXISTS (SELECT 1 FROM dbo.BankReconHeader AS h
                  WHERE h.AccountCode = o.AccountCode AND h.PeriodEnd = '2026-07-31' AND h.BankStatementBal <> 0);

INSERT INTO #Result (ExceptionCode, Findings, ValueAtRisk)
SELECT 'BRC-STALE-DIT', COUNT(*), SUM(b.Amount)
FROM dbo.BankStatementRecon AS b
WHERE b.ItemType = 'DIT' AND b.AccountCode LIKE '10102%' AND ISNULL(b.IsResolved, 0) = 0
  AND ISNULL(b.ResolvedReason, '') <> 'REVERSED' AND ISNULL(b.ResolvedReason, '') NOT LIKE 'VOIDED%'
  AND DATEDIFF(DAY, b.ItemDate, @StaleAsOf) > @DITStaleDays
  AND b.ItemDate >= @Start AND b.ItemDate < @End;
-- <<<

-- >>> DETAIL
/* ==== BRC-GL-NO-RECON-ITEM / BRC-AMOUNT-MISMATCH / BRC-RECON-NO-GL / BRC-WRONG-PERIOD (shared shape) ==== */
IF @ExceptionCode IN ('BRC-GL-NO-RECON-ITEM', 'BRC-AMOUNT-MISMATCH', 'BRC-RECON-NO-GL', 'BRC-WRONG-PERIOD')
BEGIN
    SELECT TOP (500)
        AccountCode    = CAST(m.AccountCode AS varchar(20)),
        AccountName    = CAST(ISNULL(coa.Description, '') AS varchar(256)),
        Reference      = CAST(m.Ref AS varchar(50)),
        Source         = CAST(ISNULL(m.Src, '') AS varchar(20)),
        GLDate         = CAST(m.GLDate1 AS date),
        GLTicket       = CAST(ISNULL(m.Ticket1, '') AS varchar(20)),
        GLLines        = CAST(ISNULL(m.GLLines, 0) AS int),
        GLAmount       = CAST(m.GLNet AS decimal(18,2)),
        ReconItems     = CAST(ISNULL(m.RecItems, 0) AS int),
        ReconAmount    = CAST(m.RecNet AS decimal(18,2)),
        ReconPeriod    = CAST(m.Period1 AS date),
        Gap            = CAST(ISNULL(m.GLNet, 0) - ISNULL(m.RecNet, 0) AS decimal(18,2)),
        Hint           = CAST(CASE m.Result
                              WHEN 'GL ONLY'        THEN 'The bank moved in the GL but nothing can be ticked: check the posting created its recon item (sp_Payment_PostBankReconEntry / sp_JV_PostBankReconForLines).'
                              WHEN 'AMOUNT DIFFERS' THEN CASE WHEN m.GLLines > 1 AND m.RecItems = 1 THEN 'Several GL lines but one item: lines after the first were probably dropped (Known Bug Pattern #9).'
                                                              ELSE 'Item amount differs from the GL: gross vs net cash, or the item was edited.' END
                              WHEN 'RECON ONLY'     THEN 'Item with no GL entry on this account: duplicate posting, wrong bank account, or a voucher without a ticket.'
                              WHEN 'OTHER MONTH'    THEN 'Item filed under ' + CONVERT(varchar(10), m.Period1, 120) + ' but its GL entry is dated ' + CONVERT(varchar(10), m.GLDate1, 120) + ': it is missing from the GL month''s list.'
                              END AS varchar(400))
    FROM dbo.fn_rpt_BankRecon_GLvsRecon() AS m
    LEFT JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = m.AccountCode
    WHERE m.Result = CASE @ExceptionCode WHEN 'BRC-GL-NO-RECON-ITEM' THEN 'GL ONLY' WHEN 'BRC-AMOUNT-MISMATCH' THEN 'AMOUNT DIFFERS'
                                         WHEN 'BRC-RECON-NO-GL' THEN 'RECON ONLY' ELSE 'OTHER MONTH' END
      AND m.SortDate >= @Start AND m.SortDate < @End
    ORDER BY ABS(ISNULL(m.GLNet, 0) - ISNULL(m.RecNet, 0)) DESC, m.AccountCode, m.Ref;
    RETURN;
END

/* ==== BRC-DUP-RECON-ITEM ==== */
IF @ExceptionCode = 'BRC-DUP-RECON-ITEM'
BEGIN
    ;WITH live AS (
        SELECT b.ReconID, b.AccountCode, b.ItemType, b.SourceModule, b.SourceRef, b.ReferenceNo, b.ItemDate, b.Amount, b.Payee,
               ISNULL(b.SourceRef, '') AS Ref
        FROM dbo.BankStatementRecon AS b
        WHERE b.ItemType IN ('DIT', 'OC') AND b.AccountCode LIKE '10102%' AND b.Amount <> 0
          AND ISNULL(b.ResolvedReason, '') <> 'REVERSED' AND ISNULL(b.ResolvedReason, '') NOT LIKE 'VOIDED%'),
    gl AS (SELECT DISTINCT td.AccountCode, td.ReferenceNumber FROM dbo.TicketDetails AS td WHERE td.AccountCode LIKE '10102%'),
    w AS (
        SELECT l.*, CASE WHEN g.AccountCode IS NULL THEN 0 ELSE 1 END AS HasGL,
               COUNT(*) OVER (PARTITION BY l.AccountCode, l.ItemType, l.Ref)            AS RefCnt,
               MIN(l.Ref) OVER (PARTITION BY l.AccountCode, l.ItemType, l.Amount, l.ItemDate) AS MinRef,
               MAX(l.Ref) OVER (PARTITION BY l.AccountCode, l.ItemType, l.Amount, l.ItemDate) AS MaxRef
        FROM live AS l
        LEFT JOIN gl AS g ON g.AccountCode = l.AccountCode AND g.ReferenceNumber = l.SourceRef)
    SELECT TOP (500)
        ReconID      = CAST(w.ReconID AS int),
        AccountCode  = CAST(w.AccountCode AS varchar(20)),
        AccountName  = CAST(ISNULL(coa.Description, '') AS varchar(256)),
        ItemType     = CAST(w.ItemType AS varchar(5)),
        Source       = CAST(ISNULL(w.SourceModule, '') AS varchar(20)),
        Reference    = CAST(w.Ref AS varchar(50)),
        VoucherOrRef = CAST(ISNULL(w.ReferenceNo, '') AS varchar(150)),
        ItemDate     = CAST(w.ItemDate AS date),
        Amount       = CAST(w.Amount AS decimal(18,2)),
        Payee        = CAST(ISNULL(w.Payee, '') AS varchar(200)),
        HasGLEntry   = CAST(w.HasGL AS bit),
        Hint         = CAST(CASE WHEN w.Ref <> '' AND w.RefCnt > 1 THEN 'Same reference listed more than once on this account.'
                                 ELSE 'Same amount, date and type as another item, and no GL entry of its own: likely a duplicate (e.g. the same transfer entered twice as two cash advances).' END AS varchar(400))
    FROM w
    LEFT JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = w.AccountCode
    WHERE ((w.Ref <> '' AND w.RefCnt > 1)
        OR (w.HasGL = 0 AND ISNULL(w.SourceModule, '') NOT IN ('', 'BF-PEACHTREE') AND w.MinRef <> w.MaxRef))
      AND w.ItemDate >= @Start AND w.ItemDate < @End
    ORDER BY w.AccountCode, w.Amount DESC, w.ItemDate;
    RETURN;
END

/* ==== BRC-REVERSED-LATER-MONTH ==== */
IF @ExceptionCode = 'BRC-REVERSED-LATER-MONTH'
BEGIN
    SELECT TOP (500)
        ReconID          = CAST(b.ReconID AS int),
        AccountCode      = CAST(b.AccountCode AS varchar(20)),
        AccountName      = CAST(ISNULL(coa.Description, '') AS varchar(256)),
        ItemType         = CAST(b.ItemType AS varchar(5)),
        Source           = CAST(ISNULL(b.SourceModule, '') AS varchar(20)),
        Reference        = CAST(ISNULL(b.SourceRef, '') AS varchar(50)),
        VoucherOrRef     = CAST(ISNULL(b.ReferenceNo, '') AS varchar(150)),
        CVorControlNo    = CAST(ISNULL(COALESCE(NULLIF(LTRIM(RTRIM(cv.CVNo)), ''), NULLIF(LTRIM(RTRIM(cv.NotedBy)), ''), NULLIF(LTRIM(RTRIM(tv.ControlNo)), ''),
                                         NULLIF(LTRIM(RTRIM(ca.ControlNo)), ''), NULLIF(LTRIM(RTRIM(ph.ControlNo)), '')), '') AS varchar(100)),
        CheckNo          = CAST(ISNULL(cv.CheckNo, '') AS varchar(100)),
        Payee            = CAST(ISNULL(b.Payee, '') AS varchar(200)),
        Amount           = CAST(b.Amount AS decimal(18,2)),
        OriginalGLDate   = CAST(g.FirstDate AS date),
        ReversalGLDate   = CAST(g.LastDate AS date),
        Reason           = CAST(ISNULL(b.ResolvedReason, '') AS varchar(500)),
        ItemPeriod       = CAST(h.PeriodEnd AS date),
        DifferenceChange = CAST(CASE WHEN b.ItemType = 'DIT' THEN b.Amount ELSE -b.Amount END AS decimal(18,2)),
        Hint             = CAST('At ' + CONVERT(varchar(10), EOMONTH(g.FirstDate), 120) + ' the GL had the original entry but not yet the reversal, so this was a real outstanding item that month'
                                + CASE WHEN h.PeriodEnd > EOMONTH(g.FirstDate) THEN ' (and the item itself is filed under ' + CONVERT(varchar(10), h.PeriodEnd, 120) + ')' ELSE '' END
                                + '. Verify it is NOT on that month''s bank statement.' AS varchar(400))
    FROM dbo.BankStatementRecon AS b
    LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
    LEFT JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = b.AccountCode
    CROSS APPLY (SELECT MIN(CAST(td.TicketDate AS DATE)) AS FirstDate, MAX(CAST(td.TicketDate AS DATE)) AS LastDate
                 FROM dbo.TicketDetails AS td WHERE td.AccountCode = b.AccountCode AND td.ReferenceNumber = b.SourceRef) AS g
    OUTER APPLY (SELECT TOP (1) x.CheckNo, x.CVNo, x.NotedBy FROM dbo.CheckVoucher AS x
                 WHERE CAST(x.VoucherID AS varchar(20)) = b.ReferenceNo AND CAST(x.ReferenceNumber AS varchar(20)) = b.SourceRef ORDER BY x.SequenceNumber DESC) AS cv
    OUTER APPLY (SELECT TOP (1) x.ControlNo FROM dbo.CashVoucher AS x
                 WHERE CAST(x.VoucherID AS varchar(20)) = b.ReferenceNo AND CAST(x.ReferenceNumber AS varchar(20)) = b.SourceRef ORDER BY x.SequenceNumber DESC) AS ca
    OUTER APPLY (SELECT TOP (1) x.ControlNo FROM dbo.TelegraphicVoucher AS x
                 WHERE CAST(x.VoucherID AS varchar(20)) = b.ReferenceNo AND CAST(x.ReferenceNumber AS varchar(20)) = b.SourceRef ORDER BY x.SequenceNumber DESC) AS tv
    OUTER APPLY (SELECT TOP (1) p.ControlNo FROM dbo.PaymentHeader AS p
                 WHERE b.SourceModule = 'AR-PAYMENT' AND p.ReferenceNo = b.SourceRef ORDER BY p.PaymentHeaderID DESC) AS ph
    WHERE b.AccountCode LIKE '10102%' AND (b.ResolvedReason = 'REVERSED' OR b.ResolvedReason LIKE 'VOIDED%')
      AND g.FirstDate IS NOT NULL AND EOMONTH(g.FirstDate) <> EOMONTH(g.LastDate)
      AND (h.PeriodEnd > EOMONTH(g.FirstDate) OR COALESCE(b.ClearedPeriodEnd, h.PeriodEnd) < EOMONTH(g.LastDate))
      AND g.FirstDate >= @Start AND g.FirstDate < @End
    ORDER BY b.AccountCode, g.FirstDate, b.ReconID;
    RETURN;
END

/* ==== BRC-CLEARED-NO-REASON / BRC-CLEARED-MONTH-INCONSISTENT (item list) ==== */
IF @ExceptionCode IN ('BRC-CLEARED-NO-REASON', 'BRC-CLEARED-MONTH-INCONSISTENT')
BEGIN
    SELECT TOP (500)
        ReconID          = CAST(b.ReconID AS int),
        AccountCode      = CAST(b.AccountCode AS varchar(20)),
        AccountName      = CAST(ISNULL(coa.Description, '') AS varchar(256)),
        ItemType         = CAST(b.ItemType AS varchar(5)),
        Reference        = CAST(ISNULL(b.SourceRef, '') AS varchar(50)),
        ItemDate         = CAST(b.ItemDate AS date),
        Amount           = CAST(b.Amount AS decimal(18,2)),
        ItemPeriod       = CAST(h.PeriodEnd AS date),
        IsCleared        = CAST(ISNULL(b.IsResolved, 0) AS bit),
        ClearedInMonth   = CAST(b.ClearedPeriodEnd AS date),
        ClearedOn        = CAST(b.ResolvedDate AS date),
        ClearedBy        = CAST(ISNULL(b.ResolvedBy, ISNULL(b.UpdatedBy, '')) AS varchar(50)),
        Reason           = CAST(ISNULL(b.ResolvedReason, '') AS varchar(500)),
        Hint             = CAST(CASE
                              WHEN @ExceptionCode = 'BRC-CLEARED-NO-REASON' THEN 'Cleared without the Bank Recon screen''s reason: most likely Auto-Match, which clears a cheque from its own GL entry, not from the bank statement. Check the bank statement.'
                              WHEN ISNULL(b.IsResolved, 0) = 0 THEN 'Not cleared, but a cleared month is recorded.'
                              WHEN b.ClearedPeriodEnd IS NULL THEN 'Cleared, but no cleared month recorded (written by an old screen or procedure).'
                              ELSE 'Cleared in a month before the item''s own period.' END AS varchar(400))
    FROM dbo.BankStatementRecon AS b
    LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
    LEFT JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = b.AccountCode
    WHERE b.AccountCode LIKE '10102%'
      AND (   (@ExceptionCode = 'BRC-CLEARED-NO-REASON'
               AND ISNULL(b.IsResolved, 0) = 1 AND LTRIM(RTRIM(ISNULL(b.ResolvedReason, ''))) = ''
               AND b.ItemDate >= @Start AND b.ItemDate < @End)
           OR (@ExceptionCode = 'BRC-CLEARED-MONTH-INCONSISTENT'
               AND (   (ISNULL(b.IsResolved, 0) = 1 AND b.ClearedPeriodEnd IS NULL
                        AND ISNULL(b.ResolvedReason, '') <> 'REVERSED' AND ISNULL(b.ResolvedReason, '') NOT LIKE 'VOIDED%')
                    OR (ISNULL(b.IsResolved, 0) = 0 AND b.ClearedPeriodEnd IS NOT NULL)
                    OR (b.ClearedPeriodEnd < h.PeriodEnd))))
    ORDER BY b.AccountCode, b.ItemDate, b.ReconID;
    RETURN;
END

/* ==== BRC-LOCKED-OUT-OF-BALANCE / BRC-PERIOD-OUT-OF-BALANCE / BRC-NO-STATEMENT-BALANCE (period list) ==== */
IF @ExceptionCode IN ('BRC-LOCKED-OUT-OF-BALANCE', 'BRC-PERIOD-OUT-OF-BALANCE', 'BRC-NO-STATEMENT-BALANCE')
BEGIN
    SELECT TOP (500)
        AccountCode         = CAST(h.AccountCode AS varchar(20)),
        AccountName         = CAST(ISNULL(coa.Description, '') AS varchar(256)),
        BranchCode          = CAST(h.BranchCode AS varchar(5)),
        PeriodEnd           = CAST(h.PeriodEnd AS date),
        Status              = CAST(h.Status AS varchar(10)),
        BankStatementBal    = CAST(f.BankStatementBal AS decimal(18,2)),
        OpenDIT             = CAST(f.OpenDIT AS decimal(18,2)),
        OpenOC              = CAST(f.OpenOC AS decimal(18,2)),
        AdjustedBankBalance = CAST(f.AdjustedBankBalance AS decimal(18,2)),
        GLBookBalance       = CAST(f.GLBookBalance AS decimal(18,2)),
        OpenBCM             = CAST(f.OpenBCM AS decimal(18,2)),
        OpenBankDebits      = CAST(f.OpenBankDebits AS decimal(18,2)),
        AdjustedBookBalance = CAST(f.AdjustedBookBalance AS decimal(18,2)),
        Difference          = CAST(f.Difference AS decimal(18,2)),
        Hint                = CAST(CASE
                                 WHEN @ExceptionCode = 'BRC-LOCKED-OUT-OF-BALANCE' THEN 'Locked but no longer at 0: something changed the figures of a closed month (an item cleared / deleted / edited outside the lock rules, or the GL snapshot).'
                                 WHEN @ExceptionCode = 'BRC-NO-STATEMENT-BALANCE' THEN 'The month has ended but its bank statement balance is still 0, so its Difference means nothing yet.'
                                 WHEN CAST(ABS(f.Difference) * 100 AS bigint) % 9 = 0 THEN 'Not reconciled. The difference is divisible by 9: look for two swapped digits.'
                                 ELSE 'Not reconciled: unticked statement lines, wrong ticks, bank charges / interest not entered, or a posting error. A difference equal to one item = that item; twice an item = wrong side.' END AS varchar(400))
    FROM dbo.BankReconHeader AS h
    CROSS APPLY dbo.fn_BankRecon_Figures(h.HeaderID) AS f
    LEFT JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = h.AccountCode
    WHERE (@ExceptionCode = 'BRC-LOCKED-OUT-OF-BALANCE' AND h.Status = 'LOCKED' AND f.Difference <> 0)
       OR (@ExceptionCode = 'BRC-PERIOD-OUT-OF-BALANCE' AND h.Status <> 'LOCKED' AND f.BankStatementBal <> 0 AND f.Difference <> 0
           AND h.PeriodEnd >= @Start AND h.PeriodEnd < @End)
       OR (@ExceptionCode = 'BRC-NO-STATEMENT-BALANCE' AND f.BankStatementBal = 0 AND h.PeriodEnd < CAST(@AsOf AS DATE) AND h.AccountCode LIKE '10102%'
           AND h.PeriodEnd >= @Start AND h.PeriodEnd < @End AND (f.GLBookBalance <> 0 OR f.OpenDIT <> 0 OR f.OpenOC <> 0))
    ORDER BY ABS(f.Difference) DESC, h.AccountCode, h.PeriodEnd;
    RETURN;
END

/* ==== BRC-NO-OPENING-LIST ==== */
IF @ExceptionCode = 'BRC-NO-OPENING-LIST'
BEGIN
    SELECT TOP (500)
        AccountCode     = CAST(o.AccountCode AS varchar(20)),
        AccountName     = CAST(ISNULL(coa.Description, '') AS varchar(256)),
        OpeningGL       = CAST(o.Opening AS decimal(18,2)),
        JulyHeader      = CAST(CASE WHEN EXISTS (SELECT 1 FROM dbo.BankReconHeader AS h WHERE h.AccountCode = o.AccountCode AND h.PeriodEnd = '2026-07-31') THEN 1 ELSE 0 END AS bit),
        OpeningItems    = CAST((SELECT COUNT(*) FROM dbo.BankStatementRecon AS b WHERE b.AccountCode = o.AccountCode AND b.SourceModule = 'BF-PEACHTREE') AS int),
        Hint            = CAST('No July 31 bank statement balance / Peachtree outstanding items for this account: July deposits and cheques that cleared in August have nothing to tick, so August can''t reach 0. Load the July reconciliation as a balance forward.' AS varchar(400))
    FROM (
        SELECT td.AccountCode, CAST(SUM(ISNULL(td.Debit, 0) - ISNULL(td.Credit, 0)) AS DECIMAL(18,2)) AS Opening
        FROM dbo.TicketDetails AS td
        WHERE td.AccountCode LIKE '10102%' AND td.TicketDate < '2026-08-01'
        GROUP BY td.AccountCode) AS o
    LEFT JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = o.AccountCode
    WHERE o.Opening <> 0
      AND NOT EXISTS (SELECT 1 FROM dbo.BankReconHeader AS h
                      WHERE h.AccountCode = o.AccountCode AND h.PeriodEnd = '2026-07-31' AND h.BankStatementBal <> 0)
    ORDER BY ABS(o.Opening) DESC;
    RETURN;
END

/* ==== BRC-STALE-DIT ==== */
IF @ExceptionCode = 'BRC-STALE-DIT'
BEGIN
    SELECT TOP (500)
        ReconID        = CAST(b.ReconID AS int),
        AccountCode    = CAST(b.AccountCode AS varchar(20)),
        AccountName    = CAST(ISNULL(coa.Description, '') AS varchar(256)),
        ControlNo      = CAST(ISNULL(COALESCE(NULLIF(LTRIM(RTRIM(b.ControlNo)), ''), NULLIF(LTRIM(RTRIM(ph.ControlNo)), '')), '') AS varchar(50)),
        Reference      = CAST(ISNULL(b.SourceRef, '') AS varchar(50)),
        Source         = CAST(ISNULL(b.SourceModule, '') AS varchar(20)),
        Payee          = CAST(ISNULL(b.Payee, '') AS varchar(200)),
        ItemDate       = CAST(b.ItemDate AS date),
        Amount         = CAST(b.Amount AS decimal(18,2)),
        DaysInTransit  = CAST(DATEDIFF(DAY, b.ItemDate, @StaleAsOf) AS int),
        Hint           = CAST('A deposit normally reaches the bank within days. Still open: not ticked yet, deposited under another account, or never deposited.' AS varchar(400))
    FROM dbo.BankStatementRecon AS b
    LEFT JOIN dbo.ChartOfAccounts AS coa ON coa.AccountCode = b.AccountCode
    OUTER APPLY (SELECT TOP (1) p.ControlNo FROM dbo.PaymentHeader AS p
                 WHERE b.SourceModule = 'AR-PAYMENT' AND p.ReferenceNo = b.SourceRef ORDER BY p.PaymentHeaderID DESC) AS ph
    WHERE b.ItemType = 'DIT' AND b.AccountCode LIKE '10102%' AND ISNULL(b.IsResolved, 0) = 0
      AND ISNULL(b.ResolvedReason, '') <> 'REVERSED' AND ISNULL(b.ResolvedReason, '') NOT LIKE 'VOIDED%'
      AND DATEDIFF(DAY, b.ItemDate, @StaleAsOf) > @DITStaleDays
      AND b.ItemDate >= @Start AND b.ItemDate < @End
    ORDER BY DaysInTransit DESC, b.Amount DESC;
    RETURN;
END
-- <<<
