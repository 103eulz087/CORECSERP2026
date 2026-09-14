SET NOCOUNT ON;
PRINT '=== sp_rpt_BalanceSheetWithDate: fix Amount = ABS(EndingBalance) double-counting contra/abnormal-balance BS accounts, and reclassify AccountCode 20202 to Current Liabilities per business confirmation (AccountingReportsForm.cs Balance Sheet, All Branches) ===';
GO

-- =============================================================================
-- BUG: BOTH SET 1 (line items) and SET 2 (section subtotals) computed
-- Amount = ABS(EndingBalance) for every BS-type detail account, then summed
-- Amount per section. ABS() throws away sign information that the section
-- total actually needs: a few Asset-classified accounts have a natural
-- CREDIT (negative) EndingBalance under this system's "net debit position"
-- convention (see the 2026-08-24 Trial Balance sign-convention fix) --
-- Accumulated Depreciation accounts (contra-assets, always credit-normal)
-- and, in this snapshot, one overdrawn bank account (101020101, temporarily
-- credit-balance). ABS() turned each of these into a POSITIVE amount and
-- ADDED it to the Assets section instead of correctly NETTING (subtracting)
-- it, silently inflating both Current and Non-Current Assets.
--
-- Reported by the user against CORECSJFC2026_STAGING, AsOfDate 2026-09-08,
-- All Branches -- their manual reconciliation (from the summary-level
-- 'S' accounts, e.g. AccountCode='102' NON-CURRENT ASSETS) gave:
--   Current Assets      1,482,104,765.71
--   Non-Current Assets     39,010,466.60
--   Current Liabilities   793,968,232.36   (unaffected by this bug -- see note below)
--   Non-Current Liab.      65,351,241.31   (unaffected by this bug -- see note below)
--   Equity                661,795,758.64
-- against this SP's OLD result of Current Assets 1,489,144,952.27 and
-- Non-Current Assets 146,109,036.78. Verified detail-level cause:
--   - Current Assets gap (7,040,186.56) = exactly 2x AccountCode 101020101
--     (CASH IN BANK - BDO PESO1), RawEndingBalance -3,520,093.28 (overdrawn).
--   - Non-Current Assets gap (107,098,570.18) = exactly 2x the total of the
--     six 1020210-1020215 "A/D - ..." (Accumulated Depreciation) accounts,
--     RawEndingBalance -53,549,285.09 combined.
-- (2x because ABS() both drops the negative sign AND adds where it should
-- subtract -- a net swing of 2x the account's true magnitude.)
--
-- NOTE on Liabilities: the user's Current/Non-Current Liabilities SPLIT
-- differed from this SP's by exactly AccountCode 20202 (ADVANCES FROM
-- ACCOUNT MANAGERS, 1,298,107.63) -- Liabilities/Equity accounts here are
-- uniformly credit-normal with no contra accounts in this data set, so
-- ABS() was never wrong for the Liabilities/Equity TOTAL (confirmed: this
-- SP's Total Liabilities, 859,319,473.67, already matched the user's
-- independently before this deployment). ChartOfAccounts.SummaryAccount for
-- 20202 is '202' (NON-CURRENT LIABILITIES), i.e. this SP's AccountCode-
-- prefix classification agreed with the chart-of-accounts hierarchy field
-- -- but the user confirmed the business treats this account as a CURRENT
-- liability, overriding that hierarchy field for THIS report. Since SET 2's
-- classification is a literal AccountCode-prefix CASE (it does not read
-- SummaryAccount at all), the only way to honor that decision here is an
-- explicit AccountCode exception, checked before the general '202%' match
-- -- see BSSection CASE below. ChartOfAccounts.SummaryAccount itself was
-- NOT changed (this report doesn't consult it, and retagging the account's
-- actual COA hierarchy is a separate, larger decision than this report fix
-- -- flagged back to the user rather than done here).
--
-- FIX: classify each BS detail account into its section (Asset vs
-- Liability/Equity -- reusing the same AccountCode-prefix rule already used
-- for BSSection in SET 2, now also applied in SET 1) BEFORE computing
-- Amount, then sign Amount to that section's own normal polarity instead of
-- taking an unconditional ABS():
--   Assets (101/102/103 prefix):        Amount =  RawEndingBalance
--   Liabilities/Equity (201/202/203/3): Amount = -RawEndingBalance
-- This lets a contra or abnormal-balance account net correctly within its
-- own section by straight addition, instead of being force-flipped positive
-- and double-added. Verified: no BS-type detail account currently falls
-- outside these seven prefixes (checked directly against ChartOfAccounts),
-- so there is no live "9-Other" bucket being silently dropped by this
-- change. CurrentEarnings' calc (Amount = -SUM(EndingBalance) for IS
-- accounts) already followed this same sign convention and is unchanged.
--
-- Also fixes the backup-rename pattern from the prior same-day deployment
-- (2026-09-08_sp_rpt_BalanceSheetWithDate_FixSectionTotals.sql), which could
-- skip taking a backup on certain re-runs -- this script always drops any
-- stale same-named backup first, then unconditionally renames the current
-- live object, matching this repo's standard convention.
-- =============================================================================
IF OBJECT_ID('dbo.sp_rpt_BalanceSheetWithDate_OLD_09082026180000', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_rpt_BalanceSheetWithDate_OLD_09082026180000;
GO
IF OBJECT_ID('dbo.sp_rpt_BalanceSheetWithDate', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_BalanceSheetWithDate', 'sp_rpt_BalanceSheetWithDate_OLD_09082026180000';
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
            -- FIX: sign the amount to the account's OWN SECTION polarity
            -- (Assets = as-is, Liabilities/Equity = flipped) instead of
            -- ABS(), so contra/abnormal-balance accounts net correctly.
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
                -- Business-confirmed exception: ADVANCES FROM ACCOUNT
                -- MANAGERS is treated as a Current liability for this
                -- report despite rolling up under ChartOfAccounts
                -- SummaryAccount '202' (NON-CURRENT LIABILITIES) -- must be
                -- checked before the general '202%' match below.
                WHEN coa.AccountCode = '20202'   THEN '3-Current Liabilities'
                WHEN coa.AccountCode LIKE '201%'  THEN '3-Current Liabilities'
                WHEN coa.AccountCode LIKE '202%'  THEN '4-Non-Current Liabilities'
                WHEN coa.AccountCode LIKE '203%'  THEN '4-Non-Current Liabilities'
                WHEN coa.AccountCode LIKE '3%'    THEN '5-Equity'
                ELSE '9-Other'
            END                                AS BSSection
            -- FIX: same section-polarity signing as SET 1's BSBase, applied
            -- before SUM() instead of ABS(EndingBalance).
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

PRINT 'DEPLOYMENT COMPLETE: sp_rpt_BalanceSheetWithDate Amount now signed per section polarity instead of ABS(), and AccountCode 20202 reclassified to Current Liabilities.';
