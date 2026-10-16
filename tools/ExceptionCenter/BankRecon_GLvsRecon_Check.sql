/* ================================================================
   Bank Recon: GL vs recon items check (read-only)
   ================================================================
   Run before each month's bank reconciliation. For every cash-in-bank
   account (101020%), it matches each GL reference posted to the account
   since the 2026-08-01 go-live against the Bank Recon items (DIT +, OC -;
   reversed / voided items count as 0; the Peachtree July balance forward
   is the opening, so it is left out), and lists the state of every recon
   period.
   Result codes (set 2):
     GL ONLY         the bank moved in the GL but there is no item to tick:
                     that period can never reach 0
     RECON ONLY      an item with no GL line (duplicate, wrong account, ...)
     AMOUNT DIFFERS  e.g. a multi-line JV that got only its first line
                     (Known Bug Pattern #9)
     OTHER MONTH     the item is filed under a different period than its GL date
   A clean database shows only OK in set 1 and no rows in set 2.
   First run 2026-10-08 on STAGING (production copy): 3 findings, fixed by
   SQL/2026-10-08_BankRecon_DataFix_DupTransfer_AugCheques_JV32412.sql and
   SQL/2026-10-08b_JV_BankRecon_OneItemPerAccount.sql.
   ================================================================ */
SET NOCOUNT ON;
-- GL movement on each bank account since go-live, per reference
SELECT td.AccountCode, ISNULL(NULLIF(LTRIM(RTRIM(td.ReferenceNumber)),''),'(blank)') AS Ref,
       CAST(SUM(ISNULL(td.Debit,0) - ISNULL(td.Credit,0)) AS DECIMAL(18,2)) AS GLNet, COUNT(*) AS GLLines,
       MIN(CAST(td.TicketDate AS DATE)) AS GLDate1, MAX(CAST(td.TicketDate AS DATE)) AS GLDate2,
       MIN(td.TicketNumber) AS Ticket1
INTO #GL
FROM dbo.TicketDetails AS td
WHERE td.AccountCode LIKE '101020%' AND td.TicketDate >= '2026-08-01'
GROUP BY td.AccountCode, ISNULL(NULLIF(LTRIM(RTRIM(td.ReferenceNumber)),''),'(blank)');

-- recon items (DIT +, OC -), reversed / voided count as 0, Peachtree balance forward excluded (it is the July opening)
SELECT b.AccountCode, ISNULL(NULLIF(LTRIM(RTRIM(b.SourceRef)),''),'(blank)') AS Ref,
       CAST(SUM(CASE WHEN ISNULL(b.ResolvedReason,'') = 'REVERSED' OR ISNULL(b.ResolvedReason,'') LIKE 'VOIDED%' THEN 0
                     WHEN b.ItemType = 'DIT' THEN b.Amount ELSE -b.Amount END) AS DECIMAL(18,2)) AS RecNet,
       COUNT(*) AS RecItems, MAX(b.SourceModule) AS Src,
       MIN(h.PeriodEnd) AS Period1, MAX(h.PeriodEnd) AS Period2, SUM(CASE WHEN b.HeaderID IS NULL OR h.HeaderID IS NULL THEN 1 ELSE 0 END) AS NoHeader
INTO #RC
FROM dbo.BankStatementRecon AS b
LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
WHERE b.AccountCode LIKE '101020%' AND b.ItemType IN ('DIT','OC') AND ISNULL(b.SourceModule,'') <> 'BF-PEACHTREE'
GROUP BY b.AccountCode, ISNULL(NULLIF(LTRIM(RTRIM(b.SourceRef)),''),'(blank)');

SELECT COALESCE(g.AccountCode, r.AccountCode) AS AccountCode, COALESCE(g.Ref, r.Ref) AS Ref,
       g.GLNet, g.GLLines, g.GLDate1, g.GLDate2, g.Ticket1, r.RecNet, r.RecItems, r.Src, r.Period1, r.Period2,
       CASE WHEN g.Ref IS NULL AND r.RecNet = 0 THEN 'RECON NETS TO 0'
            WHEN g.Ref IS NULL AND r.Period2 < '2026-08-01' THEN 'JULY ITEM'
            WHEN g.Ref IS NULL THEN 'RECON ONLY'
            WHEN r.Ref IS NULL AND g.GLNet = 0 THEN 'GL NETS TO 0'
            WHEN r.Ref IS NULL THEN 'GL ONLY'
            WHEN g.GLNet <> r.RecNet THEN 'AMOUNT DIFFERS'
            WHEN EOMONTH(g.GLDate1) <> r.Period1 AND g.GLNet <> 0 THEN 'OTHER MONTH'
            ELSE 'OK' END AS Result
INTO #M
FROM #GL AS g FULL OUTER JOIN #RC AS r ON r.AccountCode = g.AccountCode AND r.Ref = g.Ref;

-- 1. per account summary
SELECT m.AccountCode, c.Description,
       SUM(CASE WHEN Result IN ('OK','OTHER MONTH','GL NETS TO 0','RECON NETS TO 0','JULY ITEM') THEN 1 ELSE 0 END) AS refs_ok,
       SUM(CASE WHEN Result='OTHER MONTH' THEN 1 ELSE 0 END) AS other_month,
       SUM(CASE WHEN Result='GL ONLY' THEN 1 ELSE 0 END) AS gl_only, SUM(CASE WHEN Result='GL ONLY' THEN GLNet ELSE 0 END) AS gl_only_net,
       SUM(CASE WHEN Result='RECON ONLY' THEN 1 ELSE 0 END) AS recon_only, SUM(CASE WHEN Result='RECON ONLY' THEN RecNet ELSE 0 END) AS recon_only_net,
       SUM(CASE WHEN Result='AMOUNT DIFFERS' THEN 1 ELSE 0 END) AS amt_diff, SUM(CASE WHEN Result='AMOUNT DIFFERS' THEN GLNet - RecNet ELSE 0 END) AS amt_diff_net,
       SUM(ISNULL(GLNet,0)) AS gl_movement, SUM(ISNULL(RecNet,0)) AS recon_movement
FROM #M AS m LEFT JOIN dbo.ChartOfAccounts AS c ON c.AccountCode = m.AccountCode
GROUP BY m.AccountCode, c.Description ORDER BY m.AccountCode;

-- 2. every exception
SELECT * FROM #M WHERE Result NOT IN ('OK','GL NETS TO 0','RECON NETS TO 0','JULY ITEM') ORDER BY AccountCode, Result, ABS(ISNULL(GLNet,0) - ISNULL(RecNet,0)) DESC;

-- 3. recon periods
SELECT h.AccountCode, c.Description, h.BranchCode, CONVERT(VARCHAR(10),h.PeriodEnd,120) AS PeriodEnd, h.Status, f.BankStatementBal, f.GLBookBalance,
       f.OpenDIT, f.OpenOC, f.OpenBCM, f.OpenBankDebits, f.AdjustedBankBalance, f.AdjustedBookBalance, f.Difference,
       (SELECT COUNT(*) FROM dbo.BankStatementRecon b WHERE b.HeaderID = h.HeaderID AND b.IsResolved = 1 AND ISNULL(b.ResolvedReason,'') NOT IN ('REVERSED') AND ISNULL(b.ResolvedReason,'') NOT LIKE 'VOIDED%') AS ItemsCleared,
       (SELECT COUNT(*) FROM dbo.BankStatementRecon b WHERE b.HeaderID = h.HeaderID) AS ItemsInPeriod
FROM dbo.BankReconHeader AS h CROSS APPLY dbo.fn_BankRecon_Figures(h.HeaderID) AS f LEFT JOIN dbo.ChartOfAccounts c ON c.AccountCode = h.AccountCode
ORDER BY h.AccountCode, h.BranchCode, h.PeriodEnd;

-- 4. bank-side items and items without a header
SELECT b.AccountCode, b.ItemType, b.IsResolved, COUNT(*) n, SUM(b.Amount) amt FROM dbo.BankStatementRecon b WHERE b.ItemType NOT IN ('DIT','OC') GROUP BY b.AccountCode, b.ItemType, b.IsResolved;
SELECT COUNT(*) items_without_header FROM dbo.BankStatementRecon b WHERE b.HeaderID IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.BankReconHeader h WHERE h.HeaderID = b.HeaderID);
-- 5. GL lines dated after today
SELECT td.AccountCode, CONVERT(VARCHAR(10),td.TicketDate,120) d, td.TicketNumber, td.ReferenceNumber, td.Debit, td.Credit FROM dbo.TicketDetails td WHERE td.AccountCode LIKE '101020%' AND td.TicketDate > GETDATE();

-- 6. [88] 2026-10-15 (hardening H7): a LOCKED month whose items were added, changed, cleared or uncleared after the lock.
--    Since [88] every recon writer refuses a locked month (93002 / 93022 / 93027 / 93028), so any row here was written
--    outside the procs (a hand edit) or by an exe older than [88]'s procs. A clean database shows no rows.
SELECT h.AccountCode, h.BranchCode, CONVERT(VARCHAR(10), h.PeriodEnd, 120) AS PeriodEnd, CONVERT(VARCHAR(16), h.LockedDate, 120) AS LockedDate, h.LockedBy,
       b.ReconID, b.ItemType, b.ReferenceNo, b.SourceModule, b.SourceRef, b.Amount, b.IsResolved, b.ResolvedReason,
       CONVERT(VARCHAR(16), b.DateTimeAdded, 120) AS Added, CONVERT(VARCHAR(16), b.DateTimeUpdated, 120) AS Updated, CONVERT(VARCHAR(16), b.ResolvedDate, 120) AS Resolved,
       CASE WHEN b.DateTimeAdded > h.LockedDate THEN 'ADDED AFTER LOCK'
            WHEN b.DateTimeUpdated > h.LockedDate THEN 'CHANGED AFTER LOCK'
            ELSE 'CLEARED / UNCLEARED AFTER LOCK' END AS Finding
FROM dbo.BankReconHeader AS h
INNER JOIN dbo.BankStatementRecon AS b ON b.HeaderID = h.HeaderID
WHERE h.Status = 'LOCKED' AND h.LockedDate IS NOT NULL
  AND (b.DateTimeAdded > h.LockedDate OR b.DateTimeUpdated > h.LockedDate
       OR (b.ResolvedDate > h.LockedDate AND ISNULL(b.ClearedPeriodEnd, h.PeriodEnd) <= h.PeriodEnd))
ORDER BY h.AccountCode, h.PeriodEnd, b.ReconID;
