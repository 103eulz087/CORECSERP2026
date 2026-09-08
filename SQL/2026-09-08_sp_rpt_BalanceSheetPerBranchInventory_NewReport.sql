SET NOCOUNT ON;
PRINT '=== sp_rpt_BalanceSheetPerBranchInventory: new report -- Balance Sheet with Petty Cash Fund and Inventory (VAT/VAT-Exempt) broken out one row per branch, everything else consolidated (AccountingReportsForm.cs) ===';
GO

-- =============================================================================
-- NEW REPORT: requested to match the accounting team's existing Google-Sheets
-- Balance Sheet format, whose distinguishing feature is that Petty Cash Fund
-- and Inventory (VAT Exempt / VAT) are shown as one row PER BRANCH instead of
-- one company-wide consolidated row -- every other account stays consolidated,
-- same as the existing sp_rpt_BalanceSheetWithDate.
--
-- Scope decisions confirmed with the user (2026-09-08):
--   - New, separate report entry -- sp_rpt_BalanceSheetWithDate is untouched.
--   - Stays dynamic/ChartOfAccounts-driven (ORDER BY AccountCode, same as the
--     existing report) rather than a hardcoded line-by-line layout -- only
--     AccountCode 1010101 (PETTY CASH FUND), 101040201 (INVENTORY - VAT
--     EXEMPT), and 101040202 (INVENTORY - VAT) get the per-branch treatment.
--   - Every row in the Branches table is enumerated for those three accounts
--     (LEFT JOIN + ISNULL, so a branch with a zero/no balance still gets its
--     own labeled row) -- confirmed these are single ChartOfAccounts codes
--     with per-branch GLSummary rows, not separate per-branch account codes.
--   - The sheet's one "Petty Cash Fund - N. P. ALVIOR" row (a named
--     custodian, not a real BranchCode) is NOT reproduced -- per-branch
--     breakout is strictly by actual Branches.BranchCode.
--
-- SET 1 (line items): every other BS detail account is grouped from
-- LatestPosting (summed across branches) exactly like sp_rpt_BalanceSheetWithDate;
-- the three per-branch accounts instead come from a Branches CROSS JOIN
-- LEFT JOIN'd to per-branch GLSummary balances, one row per BranchCode.
-- AccountCode/Amount signing convention (Assets as-is, Liabilities/Equity
-- flipped -- see the 2026-09-08 sp_rpt_BalanceSheetWithDate sign-netting fix)
-- is reused verbatim; all three per-branch accounts are Assets (101%
-- prefix), so their sign is always "as-is".
--
-- SET 2 (section subtotals + grand totals): identical logic/output shape to
-- the fixed sp_rpt_BalanceSheetWithDate -- section totals are unaffected by
-- whether Assets is shown as one row or fourteen; copied verbatim.
-- =============================================================================
IF OBJECT_ID('dbo.sp_rpt_BalanceSheetPerBranchInventory_OLD_09082026190000', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_rpt_BalanceSheetPerBranchInventory_OLD_09082026190000;
GO
IF OBJECT_ID('dbo.sp_rpt_BalanceSheetPerBranchInventory', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_BalanceSheetPerBranchInventory', 'sp_rpt_BalanceSheetPerBranchInventory_OLD_09082026190000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_BalanceSheetPerBranchInventory]
    @BranchCode VARCHAR(5) = NULL,
    @AsOfDate   DATE
AS
/*
    Returns: SET 1 -- one row per BS detail account (AccountCode,
    AccountDescription, BranchCode, BranchName, Amount, RawEndingBalance);
    AccountCode 1010101/101040201/101040202 expand into one row per
    Branches.BranchCode instead of one consolidated row (BranchCode/
    BranchName populated only for those rows, NULL otherwise).
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
        SELECT
             coa.AccountCode
            ,coa.Description                AS AccountDescription
            ,CAST(NULL AS VARCHAR(128))      AS BranchCode
            ,CAST(NULL AS VARCHAR(128))      AS BranchName
            ,CASE
                WHEN coa.AccountCode LIKE '101%' OR coa.AccountCode LIKE '102%' OR coa.AccountCode LIKE '103%'
                    THEN CAST(lp.EndingBalance  AS DECIMAL(19,2))
                ELSE CAST(-lp.EndingBalance AS DECIMAL(19,2))
             END                             AS Amount
            ,CAST(lp.EndingBalance      AS DECIMAL(19,2)) AS RawEndingBalance
        FROM LatestPosting lp
        INNER JOIN ChartOfAccounts coa ON coa.AccountCode = lp.AccountCode
        WHERE coa.AccountType    = 'D'
          AND coa.YearEndIndicator = 'BS'
          AND lp.EndingBalance  <> 0
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
        -- FIX (sp-reviewer): match BSBase's YearEndIndicator='BS' guard for
        -- defensive consistency -- these 3 codes are asset/BS accounts today,
        -- but without this, a future COA mistag to 'IS' would silently drop
        -- the account from BSBase/SET 2 while PerBranchBase/SET 1 kept
        -- showing it, producing an unreconcilable report.
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
    --    sp_rpt_BalanceSheetWithDate -- per-branch breakout in SET 1 doesn't
    --    change any section's total) ──
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

PRINT 'DEPLOYMENT COMPLETE: sp_rpt_BalanceSheetPerBranchInventory created.';
