SET NOCOUNT ON;
PRINT '=== sp_rpt_BalanceSheetWithDate: fix Total Assets/Liabilities/Equity aggregated inside the per-section GROUP BY (AccountingReportsForm.cs Balance Sheet, All Branches) ===';
GO

-- =============================================================================
-- BUG: SET 2 (section subtotals) computed TotalAssets/TotalLiabilities/
-- TotalEquity with CASE-gated SUM(Amount) expressions inside a query that is
-- itself GROUP BY BSSection. Since Combined only ever has ONE BSSection value
-- per group, every one of those three CASE expressions collapses to either
-- "= SectionTotal" (when the row's own section matches the CASE) or "= 0"
-- (every other row) -- they never actually sum ACROSS sections into a true
-- grand total. Concretely, for the "1-Current Assets" row, TotalAssets came
-- back equal to the Current-Assets SectionTotal alone, not
-- Current+Non-Current Assets combined -- so it could never match a manual
-- Assets total computed from SET 1's line items, which is exactly what was
-- reported (Balance Sheet, All Branches, AsOfDate 2026-09-08).
--
-- Reproduced live against CORECSJFC2026_STAGING, all branches, AsOfDate
-- 2026-09-08:
--   Before fix (buggy SP), TotalAssets column read per row:
--     1-Current Assets          -> TotalAssets = 1,489,144,952.27  (just that row's own SectionTotal)
--     2-Non-Current Assets      -> TotalAssets =   146,109,036.78  (just that row's own SectionTotal)
--     3-Current Liabilities     -> TotalAssets = 0.00
--     ... (same pattern for TotalLiabilities/TotalEquity on the other rows)
--   True combined totals (manually summed across SET 1's line items):
--     TotalAssets      = 1,635,253,989.05  (Current + Non-Current Assets)
--     TotalLiabilities =   859,319,473.67  (Current + Non-Current Liabilities)
--     TotalEquity       =   661,795,758.64  (unchanged -- only one Equity section, so this one happened to already read correctly)
--
-- FIX: split into a SectionTotals CTE (still GROUP BY BSSection, unchanged
-- amount/classification logic) and a separate GrandTotals CTE that sums
-- SectionTotals across ALL sections with no GROUP BY, then CROSS JOIN the two
-- so every output row carries its own correct SectionTotal alongside the true,
-- repeated-per-row grand totals. No change to BSSection classification,
-- CurrentEarnings calc, or the @BranchCode=NULL consolidation in LatestPerBranch
-- (all copied verbatim from the live version). SET 1 is unchanged.
--
-- Separately noted but OUT OF SCOPE for this fix: the true detail-level
-- TotalAssets (1,635,253,989.05) does not currently tie to TotalLiabilities+
-- TotalEquity (1,521,115,232.31, a ~114M difference) or to the parent
-- 'ASSETS' summary account's own EndingBalance in GLSummary -- that looks
-- like a separate GL/subledger tie-out question, not a report-query bug, and
-- was flagged to the user rather than "fixed" here.
-- =============================================================================
IF OBJECT_ID('dbo.sp_rpt_BalanceSheetWithDate_OLD_09082026150000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.sp_rpt_BalanceSheetWithDate', 'P') IS NOT NULL
        DROP PROCEDURE dbo.sp_rpt_BalanceSheetWithDate;
END
ELSE IF OBJECT_ID('dbo.sp_rpt_BalanceSheetWithDate', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.sp_rpt_BalanceSheetWithDate', 'sp_rpt_BalanceSheetWithDate_OLD_09082026150000';
END
GO

CREATE PROCEDURE [dbo].[sp_rpt_BalanceSheetWithDate]
    @BranchCode VARCHAR(5) = NULL,
    @AsOfDate   DATE
AS
BEGIN
    SET NOCOUNT ON;

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
             coa.AccountCode
            ,coa.Description                AS AccountDescription
            ,CAST(ABS(lp.EndingBalance) AS DECIMAL(19,2)) AS Amount
            ,CAST(lp.EndingBalance      AS DECIMAL(19,2)) AS RawEndingBalance
        FROM LatestPosting lp
        INNER JOIN ChartOfAccounts coa ON coa.AccountCode = lp.AccountCode
        WHERE coa.AccountType    = 'D'
          AND coa.YearEndIndicator = 'BS'
          AND lp.EndingBalance  <> 0
    ),
    CurrentEarnings AS
    (
        SELECT
             'CURRENT_EARNINGS'        AS AccountCode
            ,'Current Period Earnings' AS AccountDescription
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
        SELECT * FROM CurrentEarnings WHERE Amount <> 0
    ) x
    ORDER BY AccountCode;


    -- ── SET 2: Section subtotals + balance check ──────────────────
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
                WHEN coa.AccountCode LIKE '201%'  THEN '3-Current Liabilities'
                WHEN coa.AccountCode LIKE '202%'  THEN '4-Non-Current Liabilities'
                WHEN coa.AccountCode LIKE '203%'  THEN '4-Non-Current Liabilities'
                WHEN coa.AccountCode LIKE '3%'    THEN '5-Equity'
                ELSE '9-Other'
            END                                AS BSSection
            ,CAST(ABS(lp.EndingBalance) AS DECIMAL(19,2)) AS Amount
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
    -- FIX: per-section subtotal only, still grouped by BSSection.
    SectionTotals AS
    (
        SELECT BSSection, CAST(SUM(Amount) AS DECIMAL(19,2)) AS SectionTotal
        FROM Combined
        GROUP BY BSSection
    ),
    -- FIX: grand totals computed ACROSS every section (no GROUP BY), so
    -- these are genuine combined figures instead of one section's own
    -- SectionTotal masquerading as the total.
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

PRINT 'DEPLOYMENT COMPLETE: sp_rpt_BalanceSheetWithDate TotalAssets/TotalLiabilities/TotalEquity now sum across all sections, not just the current GROUP BY row.';
