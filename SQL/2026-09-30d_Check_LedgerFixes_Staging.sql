/* ================================================================
   2026-09-30d: READ-ONLY check that scripts 17 (SupplierLedger) and
   18 (ClientLedger) are applied. Changes nothing.
   Run in SSMS against CORECSJFC2026_STAGING (or COREX001).
   Expected results are noted above each query.
   ================================================================ */
USE CORECSJFC2026_STAGING;
SET NOCOUNT ON;

-- 1. Objects. Expected: every column = 'YES'.
SELECT
    DB_NAME() AS DatabaseName,
    CASE WHEN OBJECT_ID('dbo.ClientLedger_Backup_20260930', 'U')   IS NOT NULL THEN 'YES' ELSE 'NO' END AS ClientLedgerBackup,
    CASE WHEN OBJECT_ID('dbo.ClientAccounts_Backup_20260930', 'U') IS NOT NULL THEN 'YES' ELSE 'NO' END AS ClientAccountsBackup,
    CASE WHEN OBJECT_ID('dbo.trg_ClientLedger_Recalc', 'TR')       IS NOT NULL THEN 'YES' ELSE 'NO' END AS ClientNewTrigger,
    CASE WHEN OBJECT_ID('dbo.InsertClientLedger', 'TR')            IS NULL     THEN 'YES' ELSE 'NO' END AS ClientOldTriggerRenamed,
    CASE WHEN OBJECT_ID('dbo.SupplierLedger_Backup_20260930', 'U') IS NOT NULL THEN 'YES' ELSE 'NO' END AS SupplierLedgerBackup,
    CASE WHEN OBJECT_ID('dbo.trg_SupplierLedger_Recalc', 'TR')     IS NOT NULL THEN 'YES' ELSE 'NO' END AS SupplierNewTrigger,
    CASE WHEN OBJECT_ID('dbo.InsertSupplierLedger', 'TR')          IS NULL     THEN 'YES' ELSE 'NO' END AS SupplierOldTriggerRenamed;

-- 2. Triggers. Expected: only trg_ClientLedger_Recalc and trg_SupplierLedger_Recalc
--    are enabled (IsDisabled = 0); every *_OLD_* / dated trigger is disabled (1).
SELECT OBJECT_NAME(t.parent_id) AS TableName, t.name AS TriggerName, t.is_disabled AS IsDisabled,
       CONVERT(VARCHAR(19), o.modify_date, 120) AS Modified
FROM sys.triggers AS t
INNER JOIN sys.objects AS o ON o.object_id = t.object_id
WHERE t.parent_id IN (OBJECT_ID('dbo.ClientLedger'), OBJECT_ID('dbo.SupplierLedger'))
ORDER BY TableName, t.is_disabled, t.name;

-- 3. ClientLedger audit. Expected: all zeros.
;WITH L AS
(
    SELECT AccountKey, TRN_SEQ_NO,
           ISNULL(BeginningBalance, 0) AS Beg, ISNULL(Debit, 0) AS Dr,
           ISNULL(Credit, 0) AS Cr, ISNULL(EndingBalance, 0) AS EndBal,
           ROW_NUMBER() OVER (PARTITION BY AccountKey ORDER BY TRN_SEQ_NO) AS rn,
           LAG(ISNULL(EndingBalance, 0)) OVER (PARTITION BY AccountKey ORDER BY TRN_SEQ_NO) AS PrevEnd
    FROM dbo.ClientLedger
)
SELECT
    'ClientLedger' AS Ledger,
    (SELECT COUNT(*) FROM L WHERE ABS(Beg + Dr - Cr - EndBal) > 0.005) AS BadMathRows,
    (SELECT COUNT(*) FROM L WHERE (rn = 1 AND ABS(Beg) > 0.005) OR (rn > 1 AND ABS(Beg - PrevEnd) > 0.005)) AS ChainBreaks,
    (SELECT COUNT(*)
     FROM (SELECT AccountKey, SUM(Dr - Cr) AS Bal FROM L GROUP BY AccountKey) AS f
     INNER JOIN dbo.ClientAccounts AS ca ON ca.AccountKey = f.AccountKey
     WHERE ABS(ISNULL(ca.AccountBalance, 0) - f.Bal) > 0.005) AS AccountsOff,
    (SELECT COUNT(*) FROM dbo.ClientLedger WHERE RTRIM(AccountKey) <> RTRIM(AccountID)) AS KeyIdMismatch;

-- 4. SupplierLedger audit (script 17). Expected: all zeros.
;WITH L AS
(
    SELECT SupplierKey, TRN_SEQ_NO,
           ISNULL(BeginningBalance, 0) AS Beg, ISNULL(Debit, 0) AS Dr,
           ISNULL(Credit, 0) AS Cr, ISNULL(EndingBalance, 0) AS EndBal,
           ROW_NUMBER() OVER (PARTITION BY SupplierKey ORDER BY TRN_SEQ_NO) AS rn,
           LAG(ISNULL(EndingBalance, 0)) OVER (PARTITION BY SupplierKey ORDER BY TRN_SEQ_NO) AS PrevEnd
    FROM dbo.SupplierLedger
)
SELECT
    'SupplierLedger' AS Ledger,
    (SELECT COUNT(*) FROM L WHERE ABS(Beg + Cr - Dr - EndBal) > 0.005) AS BadMathRows,
    (SELECT COUNT(*) FROM L WHERE (rn = 1 AND ABS(Beg) > 0.005) OR (rn > 1 AND ABS(Beg - PrevEnd) > 0.005)) AS ChainBreaks,
    (SELECT COUNT(*)
     FROM (SELECT SupplierKey, SUM(Cr - Dr) AS Bal FROM L GROUP BY SupplierKey) AS f
     INNER JOIN dbo.SupplierAccounts AS sa ON sa.SupplierKey = f.SupplierKey
     WHERE ABS(ISNULL(sa.AccountBalance, 0) - f.Bal) > 0.005) AS AccountsOff;

-- 5. JELO'S PLACE. Expected on STAGING: AccountBalance = OpenInvoices
--    (00007479 = 455,284.60; 00009065 = 207,768.40).
SELECT ca.AccountKey, ca.AccountName,
       CAST(ca.AccountBalance AS DECIMAL(19,2)) AS AccountBalance,
       CAST((SELECT SUM(ISNULL(cl.Debit, 0) - ISNULL(cl.Credit, 0))
             FROM dbo.ClientLedger AS cl WHERE cl.AccountKey = ca.AccountKey) AS DECIMAL(19,2)) AS LedgerTotal,
       CAST((SELECT SUM(t.Balance)
             FROM dbo.TransactionChargeSales AS t WHERE t.CustomerKey = ca.AccountKey) AS DECIMAL(19,2)) AS OpenInvoices
FROM dbo.ClientAccounts AS ca
WHERE ca.AccountKey IN ('00007479', '00009065');

-- 6. JELO'S PLACE ledger rows. Expected: T_036293 BF now on 00009065 (seq 4),
--    AccountID = AccountKey on every row, the last EndingBalance = the balance in query 5.
SELECT AccountKey, AccountID, TRN_SEQ_NO, TransCode, InvoiceNo,
       CAST(BeginningBalance AS DECIMAL(19,2)) AS Beg,
       CAST(Debit AS DECIMAL(19,2))            AS Dr,
       CAST(Credit AS DECIMAL(19,2))           AS Cr,
       CAST(EndingBalance AS DECIMAL(19,2))    AS EndBal
FROM dbo.ClientLedger
WHERE AccountKey IN ('00007479', '00009065')
ORDER BY AccountKey, TRN_SEQ_NO;

-- 7. Backup row counts vs live. Expected on STAGING: ClientLedger 16,315 = live;
--    SupplierLedger backup 1,416. (Live counts grow once new postings come in.)
SELECT 'ClientLedger' AS TableName,
       (SELECT COUNT(*) FROM dbo.ClientLedger_Backup_20260930) AS BackupRows,
       (SELECT COUNT(*) FROM dbo.ClientLedger) AS LiveRows
UNION ALL
SELECT 'ClientAccounts',
       (SELECT COUNT(*) FROM dbo.ClientAccounts_Backup_20260930),
       (SELECT COUNT(*) FROM dbo.ClientAccounts)
UNION ALL
SELECT 'SupplierLedger',
       (SELECT COUNT(*) FROM dbo.SupplierLedger_Backup_20260930),
       (SELECT COUNT(*) FROM dbo.SupplierLedger)
UNION ALL
SELECT 'SupplierAccounts',
       (SELECT COUNT(*) FROM dbo.SupplierAccounts_Backup_20260930),
       (SELECT COUNT(*) FROM dbo.SupplierAccounts);
