SET NOCOUNT ON;
PRINT '=== sp_rpt_BalanceSheetPerBranchInventory: SET 1 now enumerates every ChartOfAccounts detail BS account (LEFT JOIN, no EndingBalance<>0 filter) so zero-balance accounts appear in the report, not just accounts with a posting history ===';
GO

-- =============================================================================
-- CHANGE (requested 2026-09-08): the report should show the whole chart of
-- accounts for the BS section, including accounts that currently carry a
-- zero balance -- previously BSBase INNER JOIN'd from LatestPosting (which is
-- built from GLSummary) and filtered EndingBalance <> 0, so an account with
-- no postings at all, or one that nets to exactly zero as of @AsOfDate,
-- silently dropped out of the report.
--
-- Fix: BSBase now drives FROM ChartOfAccounts (LEFT JOIN LatestPosting,
-- ISNULL'd to 0) so every AccountType='D', YearEndIndicator='BS' account gets
-- a row regardless of whether it has GLSummary activity. The <> 0 filter is
-- removed.
--
-- Everything else is unchanged:
--   - PerBranchBase already showed every branch via LEFT JOIN + ISNULL, so
--     zero-balance branches for the 3 per-branch accounts were already
--     visible -- no change needed there.
--   - CurrentEarnings is a computed row, not a real GL account, and stays
--     hidden when zero (SELECT ... WHERE Amount <> 0 at the UNION), same as
--     before.
--   - SET 2 (section/grand totals) is unaffected -- summing in a batch of
--     zero-balance accounts doesn't change any total.
-- =============================================================================
IF OBJECT_ID('dbo.sp_rpt_BalanceSheetPerBranchInventory_OLD_09082026200000', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_rpt_BalanceSheetPerBranchInventory_OLD_09082026200000;
GO
IF OBJECT_ID('dbo.sp_rpt_BalanceSheetPerBranchInventory', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_BalanceSheetPerBranchInventory', 'sp_rpt_BalanceSheetPerBranchInventory_OLD_09082026200000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_BalanceSheetPerBranchInventory]
    @BranchCode VARCHAR(5) = NULL,
    @AsOfDate   DATE
AS
/*
    Returns: SET 1 -- one row per BS detail account (AccountCode,
    AccountDescription, BranchCode, BranchName, Amount, RawEndingBalance),
    INCLUDING accounts with a zero EndingBalance or no GLSummary activity at
    all as of @AsOfDate; AccountCode 1010101/101040201/101040202 expand into
    one row per Branches.BranchCode instead of one consolidated row
    (BranchCode/BranchName populated only for those rows, NULL otherwise).
    SET 2 -- section subtotals + grand totals, identical shape to
    sp_rpt_BalanceSheetWithDate.
    Assumes: GLSummary carries a running EndingBalance per (BranchCode,
    AccountCode, PostingDate); ChartOfAccounts.AccountType='D' marks postable
    detail accounts; YearEndIndicator 'BS'/'IS' separates balance-sheet from
    income-statement accounts.
    Callers: AccountingReportsForm.cs ("Balance Sheet (Per-Branch Inventory)").
*/
BEGIN
    SET NOCOUNT ON;

    DECLARE @PerBranchAccounts TABLE (AccountCode VARCHAR(50) PRIMARY KEY);
    INSERT INTO @PerBranchAccounts (AccountCode) VALUES ('1010101'), ('101040201'), ('101040202');

    -- ── SET 1: Line items ─────────────────────────────────────────
    ;WITH LatestPerBranch AS
    (
        SELECT
             gs.BranchCode
            ,gs.AccountCode
            ,gs.EndingBalance
            ,ROW_NUMBER() OVER (
                PARTITION BY gs.BranchCode, gs.AccountCode
                ORDER BY gs.PostingDate DESC, gs.SupplementaryNumber DESC
             ) AS rn
        FROM GLSummary gs
        WHERE (@BranchCode IS NULL OR gs.BranchCode = @BranchCode)
          AND gs.PostingDate <= @AsOfDate
    ),
    LatestPerBranchFinal AS
    (
        SELECT BranchCode, AccountCode, EndingBalance
        FROM LatestPerBranch
        WHERE rn = 1
    ),
    LatestPosting AS
    (
        SELECT AccountCode, SUM(EndingBalance) AS EndingBalance
        FROM LatestPerBranchFinal
        GROUP BY AccountCode
    ),
    BSBase AS
    (
        -- CHANGE: drive FROM ChartOfAccounts (LEFT JOIN LatestPosting,
        -- ISNULL to 0) instead of FROM LatestPosting (INNER JOIN COA) so
        -- every detail BS account is represented, including accounts with
        -- zero/no GLSummary activity. The prior "EndingBalance <> 0" filter
        -- is removed.
        SELECT
             coa.AccountCode
            ,coa.Description                AS AccountDescription
            ,CAST(NULL AS VARCHAR(128))      AS BranchCode
            ,CAST(NULL AS VARCHAR(128))      AS BranchName
            ,CASE
                WHEN coa.AccountCode LIKE '101%' OR coa.AccountCode LIKE '102%' OR coa.AccountCode LIKE '103%'
                    THEN CAST( ISNULL(lp.EndingBalance, 0) AS DECIMAL(19,2))
                ELSE CAST(-ISNULL(lp.EndingBalance, 0) AS DECIMAL(19,2))
             END                             AS Amount
            ,CAST(ISNULL(lp.EndingBalance, 0) AS DECIMAL(19,2)) AS RawEndingBalance
        FROM ChartOfAccounts coa
        LEFT JOIN LatestPosting lp ON lp.AccountCode = coa.AccountCode
        WHERE coa.AccountType    = 'D'
          AND coa.YearEndIndicator = 'BS'
          AND coa.AccountCode NOT IN (SELECT AccountCode FROM @PerBranchAccounts)
    ),
    PerBranchBase AS
    (
        SELECT
             coa.AccountCode
            ,coa.Description + ' - ' + ISNULL(b.BranchName, b.BranchCode) AS AccountDescription
            ,b.BranchCode
            ,b.BranchName
            -- all three per-branch accounts are 101% (Current Assets) -- sign as-is
            ,CAST(ISNULL(lpb.EndingBalance, 0) AS DECIMAL(19,2)) AS Amount
            ,CAST(ISNULL(lpb.EndingBalance, 0) AS DECIMAL(19,2)) AS RawEndingBalance
        FROM ChartOfAccounts coa
        INNER JOIN @PerBranchAccounts pba ON pba.AccountCode = coa.AccountCode
        CROSS JOIN Branches b
        LEFT JOIN LatestPerBranchFinal lpb
            ON lpb.AccountCode = coa.AccountCode AND lpb.BranchCode = b.BranchCode
        WHERE coa.AccountType = 'D'
          AND coa.YearEndIndicator = 'BS'
          AND (@BranchCode IS NULL OR b.BranchCode = @BranchCode)
    ),
    CurrentEarnings AS
    (
        SELECT
             'CURRENT_EARNINGS'        AS AccountCode
            ,'Current Period Earnings' AS AccountDescription
            ,CAST(NULL AS VARCHAR(128))  AS BranchCode
            ,CAST(NULL AS VARCHAR(128)) AS BranchName
            ,CAST(-SUM(ISNULL(lp.EndingBalance, 0)) AS DECIMAL(19,2)) AS Amount
            ,CAST( SUM(ISNULL(lp.EndingBalance, 0)) AS DECIMAL(19,2)) AS RawEndingBalance
        FROM LatestPosting lp
        INNER JOIN ChartOfAccounts coa ON coa.AccountCode = lp.AccountCode
        WHERE coa.AccountType    = 'D'
          AND coa.YearEndIndicator = 'IS'
    )
    SELECT * FROM (
        SELECT * FROM BSBase
        UNION ALL
        SELECT * FROM PerBranchBase
        UNION ALL
        SELECT * FROM CurrentEarnings WHERE Amount <> 0
    ) x
    ORDER BY AccountCode, ISNULL(BranchCode, '');


    -- ── SET 2: Section subtotals + balance check (identical to
    --    sp_rpt_BalanceSheetWithDate -- per-branch breakout and zero-balance
    --    accounts in SET 1 don't change any section's total) ──
    ;WITH LatestPerBranch AS
    (
        SELECT
             gs.BranchCode
            ,gs.AccountCode
            ,gs.EndingBalance
            ,ROW_NUMBER() OVER (
                PARTITION BY gs.BranchCode, gs.AccountCode
                ORDER BY gs.PostingDate DESC, gs.SupplementaryNumber DESC
             ) AS rn
        FROM GLSummary gs
        WHERE (@BranchCode IS NULL OR gs.BranchCode = @BranchCode)
          AND gs.PostingDate <= @AsOfDate
    ),
    LatestPosting AS
    (
        SELECT AccountCode, SUM(EndingBalance) AS EndingBalance
        FROM LatestPerBranch
        WHERE rn = 1
        GROUP BY AccountCode
    ),
    BSBase AS
    (
        SELECT
            CASE
                WHEN coa.AccountCode LIKE '101%'  THEN '1-Current Assets'
                WHEN coa.AccountCode LIKE '102%'  THEN '2-Non-Current Assets'
                WHEN coa.AccountCode LIKE '103%'  THEN '2-Non-Current Assets'
                WHEN coa.AccountCode = '20202'    THEN '3-Current Liabilities'
                WHEN coa.AccountCode LIKE '201%'  THEN '3-Current Liabilities'
                WHEN coa.AccountCode LIKE '202%'  THEN '4-Non-Current Liabilities'
                WHEN coa.AccountCode LIKE '203%'  THEN '4-Non-Current Liabilities'
                WHEN coa.AccountCode LIKE '3%'    THEN '5-Equity'
                ELSE '9-Other'
            END                                AS BSSection
            ,CASE
                WHEN coa.AccountCode LIKE '101%' OR coa.AccountCode LIKE '102%' OR coa.AccountCode LIKE '103%'
                    THEN CAST(lp.EndingBalance  AS DECIMAL(19,2))
                ELSE CAST(-lp.EndingBalance AS DECIMAL(19,2))
             END                                AS Amount
        FROM LatestPosting lp
        INNER JOIN ChartOfAccounts coa ON coa.AccountCode = lp.AccountCode
        WHERE coa.AccountType = 'D' AND coa.YearEndIndicator = 'BS'
    ),
    CurrentEarnings AS
    (
        SELECT
             '5-Equity' AS BSSection
            ,CAST(-SUM(ISNULL(lp.EndingBalance,0)) AS DECIMAL(19,2)) AS Amount
        FROM LatestPosting lp
        INNER JOIN ChartOfAccounts coa ON coa.AccountCode = lp.AccountCode
        WHERE coa.AccountType = 'D' AND coa.YearEndIndicator = 'IS'
    ),
    Combined AS
    (
        SELECT BSSection, Amount FROM BSBase
        UNION ALL
        SELECT BSSection, Amount FROM CurrentEarnings WHERE Amount <> 0
    ),
    SectionTotals AS
    (
        SELECT BSSection, CAST(SUM(Amount) AS DECIMAL(19,2)) AS SectionTotal
        FROM Combined
        GROUP BY BSSection
    ),
    GrandTotals AS
    (
        SELECT
             CAST(SUM(CASE WHEN BSSection LIKE '1%' OR BSSection = '2-Non-Current Assets'
                           THEN SectionTotal ELSE 0 END) AS DECIMAL(19,2)) AS TotalAssets
            ,CAST(SUM(CASE WHEN BSSection LIKE '3%' OR BSSection LIKE '4%'
                           THEN SectionTotal ELSE 0 END) AS DECIMAL(19,2)) AS TotalLiabilities
            ,CAST(SUM(CASE WHEN BSSection LIKE '5%'
                           THEN SectionTotal ELSE 0 END) AS DECIMAL(19,2)) AS TotalEquity
        FROM SectionTotals
    )
    SELECT
         st.BSSection
        ,st.SectionTotal
        ,gt.TotalAssets
        ,gt.TotalLiabilities
        ,gt.TotalEquity
        ,@AsOfDate                    AS AsOfDate
        ,ISNULL(@BranchCode, 'ALL')   AS BranchCode
    FROM SectionTotals st
    CROSS JOIN GrandTotals gt
    ORDER BY st.BSSection;
END;
GO

PRINT 'DEPLOYMENT COMPLETE: sp_rpt_BalanceSheetPerBranchInventory now includes zero-balance BS accounts in SET 1.';
