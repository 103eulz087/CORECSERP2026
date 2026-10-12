/* ================================================================
   2026-10-08z: read-only check after deploying 2026-10-08 / 08b / 08c / 08e
   ================================================================
   Changes nothing. Every line of result set 1 should say OK; result set 2
   shows the BDO PESO 1 figures to compare with the expected values.
   ================================================================ */
SET NOCOUNT ON;

SELECT x.Chk, CASE WHEN x.Ok = 1 THEN 'OK' ELSE '** CHECK **' END AS Result, x.Detail
FROM (
    SELECT 1 AS N, '08  data fix: backup of the 14 rows' AS Chk,
           CASE WHEN OBJECT_ID('dbo.BankStatementRecon_Fix_Backup_20261008', 'U') IS NOT NULL THEN 1 ELSE 0 END AS Ok,
           CAST((SELECT COUNT(*) FROM sys.tables WHERE name = 'BankStatementRecon_Fix_Backup_20261008') AS VARCHAR(10)) AS Detail
    UNION ALL
    SELECT 2, '08  duplicate transfer 13157 voided (2 rows)',
           CASE WHEN (SELECT COUNT(*) FROM dbo.BankStatementRecon WHERE ReconID IN (22, 23) AND ResolvedReason LIKE 'VOIDED - DUPLICATE%') = 2 THEN 1 ELSE 0 END, ''
    UNION ALL
    SELECT 3, '08  11 BDO PESO 2 cheques in the August period',
           CASE WHEN (SELECT COUNT(*) FROM dbo.BankStatementRecon b JOIN dbo.BankReconHeader h ON h.HeaderID = b.HeaderID
                      WHERE b.ReconID IN (39,40,41,42,43,44,45,46,47,48,82) AND h.PeriodEnd = '2026-08-31') = 11 THEN 1 ELSE 0 END, ''
    UNION ALL
    SELECT 4, '08  JV 32412 OC = 383,499.06',
           CASE WHEN (SELECT Amount FROM dbo.BankStatementRecon WHERE ReconID = 5467) = 383499.06 THEN 1 ELSE 0 END,
           CAST((SELECT Amount FROM dbo.BankStatementRecon WHERE ReconID = 5467) AS VARCHAR(30))
    UNION ALL
    SELECT 5, '08b sp_JV_PostBankReconForLines replaced',
           CASE WHEN OBJECT_ID('dbo.sp_JV_PostBankReconForLines_OLD_10082026120000', 'P') IS NOT NULL
                 AND OBJECT_DEFINITION(OBJECT_ID('dbo.sp_JV_PostBankReconForLines')) LIKE '%2026-10-08b%' THEN 1 ELSE 0 END, ''
    UNION ALL
    SELECT 6, '08c column ClearedPeriodEnd',
           CASE WHEN COL_LENGTH('dbo.BankStatementRecon', 'ClearedPeriodEnd') IS NOT NULL THEN 1 ELSE 0 END, ''
    UNION ALL
    SELECT 7, '08c cleared rows all have a month',
           CASE WHEN (SELECT COUNT(*) FROM dbo.BankStatementRecon WHERE ISNULL(IsResolved, 0) = 1 AND ClearedPeriodEnd IS NULL
                      AND ISNULL(ResolvedReason, '') <> 'REVERSED' AND ISNULL(ResolvedReason, '') NOT LIKE 'VOIDED%') = 0 THEN 1 ELSE 0 END, ''
    UNION ALL
    SELECT 8, '08c 8 backups _OLD_10082026180000',
           CASE WHEN (SELECT COUNT(*) FROM sys.objects WHERE name LIKE '%[_]OLD[_]10082026180000') = 8 THEN 1 ELSE 0 END,
           CAST((SELECT COUNT(*) FROM sys.objects WHERE name LIKE '%[_]OLD[_]10082026180000') AS VARCHAR(10))
    UNION ALL
    SELECT 9, '08e no silent move (3 procs, 3 backups)',
           CASE WHEN (SELECT COUNT(*) FROM sys.objects WHERE name LIKE '%[_]OLD[_]10082026220000') = 3
                 AND OBJECT_DEFINITION(OBJECT_ID('dbo.sp_BankRecon_ResolveItem')) LIKE '%93013%' THEN 1 ELSE 0 END, ''
) AS x
ORDER BY x.N;

SELECT CONVERT(VARCHAR(10), h.PeriodEnd, 120) AS PeriodEnd, h.Status, f.BankStatementBal, f.GLBookBalance,
       f.OpenDIT, f.OpenOC, f.Difference,
       CASE h.PeriodEnd WHEN '2026-07-31' THEN 'expect 0.00' WHEN '2026-08-31' THEN 'expect 2,290,814.93 before any tick' ELSE '' END AS Expected
FROM dbo.BankReconHeader AS h
CROSS APPLY dbo.fn_BankRecon_Figures(h.HeaderID) AS f
WHERE h.BranchCode = '888' AND h.AccountCode = '101020101'
ORDER BY h.PeriodEnd;
