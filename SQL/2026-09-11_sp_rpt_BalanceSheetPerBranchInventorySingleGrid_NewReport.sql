-- New, fully isolated report proc: Balance Sheet, single-grid presentation.
-- Zero existing objects modified -- net-new SP for the new "Reports V2" form
-- (HOFormsDevEx/AccountingReportsFormV2.cs), which redesigns the Accounting
-- Reports screen (top parameter bar instead of a left sidebar, freeing width
-- for the report grid) and wants the Balance Sheet's line items AND section/
-- grand totals in ONE grid instead of a separate detail grid + summary grid.
--
-- Source logic is copied verbatim from the currently-live
-- dbo.sp_rpt_BalanceSheetPerBranchInventory (both of its result sets --
-- SET1 line items, SET2 section/grand totals) and combined into a single
-- result set via a RowType discriminator column:
--   'DETAIL'     -- one row per posting (ChartOfAccounts.AccountType='D')
--                    BS account, same shape/signs/per-branch Petty Cash Fund
--                    + Inventory (VAT/VAT-Exempt) breakout as the source SP.
--   'SUBTOTAL'   -- one row per BSSection, Amount = that section's total.
--   'GRANDTOTAL' -- Total Assets / Total Liabilities & Equity / Difference
--                    (should be 0 -- a real out-of-balance condition, not
--                    just a display artifact, since this is the same
--                    GrandTotals computation the 2-grid version already
--                    trusts).
-- Row order: within each BSSection, DETAIL rows (by AccountCode, then
-- BranchCode) followed by that section's SUBTOTAL row; sections in the same
-- '1-'..'5-' prefix order as before; GRANDTOTAL rows ('6-Totals') last.
--
-- Callers: HOFormsDevEx/AccountingReportsFormV2.cs, "Balance Sheet".
IF OBJECT_ID('dbo.sp_rpt_BalanceSheetPerBranchInventorySingleGrid', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_BalanceSheetPerBranchInventorySingleGrid', 'sp_rpt_BalanceSheetPerBranchInventorySingleGrid_OLD_09112026180000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_BalanceSheetPerBranchInventorySingleGrid]
    @BranchCode VARCHAR(5) = NULL,
    @AsOfDate   DATE
AS
/*
    Returns: ONE result set -- posting-account line items, per-BSSection
    subtotals, and grand totals/balance-check, discriminated by RowType
    ('DETAIL'/'SUBTOTAL'/'GRANDTOTAL'). See header comment above for the
    full row-order/shape contract; identical underlying figures to
    sp_rpt_BalanceSheetPerBranchInventory's two result sets, just reshaped
    for a single-grid presentation.
    Assumes: same as sp_rpt_BalanceSheetPerBranchInventory -- GLSummary
    carries a running EndingBalance per (BranchCode, AccountCode,
    PostingDate); ChartOfAccounts.AccountType='D' marks postable detail
    accounts; YearEndIndicator 'BS'/'IS' separates balance-sheet from
    income-statement accounts.
    Callers: HOFormsDevEx/AccountingReportsFormV2.cs ("Balance Sheet").
*/
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#DetailRows') IS NOT NULL DROP TABLE #DetailRows;
    IF OBJECT_ID('tempdb..#SectionTotals') IS NOT NULL DROP TABLE #SectionTotals;

    DECLARE @PerBranchAccounts TABLE (AccountCode VARCHAR(50) PRIMARY KEY);
    INSERT INTO @PerBranchAccounts (AccountCode) VALUES ('1010101'), ('101040201'), ('101040202');

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
        -- Every detail BS account (LEFT JOIN + ISNULL), including accounts
        -- with zero/no GLSummary activity -- same as the live SP's SET1.
        SELECT
             coa.AccountCode
            ,coa.Description AS AccountDescription
            ,CAST(NULL AS VARCHAR(128)) AS BranchCode
            ,CAST(NULL AS VARCHAR(128)) AS BranchName
            ,CASE
                WHEN coa.AccountCode LIKE '101%' OR coa.AccountCode LIKE '102%' OR coa.AccountCode LIKE '103%'
                    THEN CAST( ISNULL(lp.EndingBalance, 0) AS DECIMAL(19,2))
                ELSE CAST(-ISNULL(lp.EndingBalance, 0) AS DECIMAL(19,2))
             END AS Amount
            ,CAST(ISNULL(lp.EndingBalance, 0) AS DECIMAL(19,2)) AS RawEndingBalance
            ,CASE
                WHEN coa.AccountCode LIKE '101%'  THEN '1-Current Assets'
                WHEN coa.AccountCode LIKE '102%'  THEN '2-Non-Current Assets'
                WHEN coa.AccountCode LIKE '103%'  THEN '2-Non-Current Assets'
                WHEN coa.AccountCode = '20202'    THEN '3-Current Liabilities'
                WHEN coa.AccountCode LIKE '201%'  THEN '3-Current Liabilities'
                WHEN coa.AccountCode LIKE '202%'  THEN '4-Non-Current Liabilities'
                WHEN coa.AccountCode LIKE '203%'  THEN '4-Non-Current Liabilities'
                WHEN coa.AccountCode LIKE '3%'    THEN '5-Equity'
                ELSE '9-Other'
             END AS BSSection
        FROM ChartOfAccounts coa
        LEFT JOIN LatestPosting lp ON lp.AccountCode = coa.AccountCode
        WHERE coa.AccountType    = 'D'
          AND coa.YearEndIndicator = 'BS'
          AND coa.AccountCode NOT IN (SELECT AccountCode FROM @PerBranchAccounts)
    ),
    PerBranchBase AS
    (
        -- Petty Cash Fund + Inventory (VAT/VAT-Exempt) expanded one row per
        -- branch -- all three accounts are 101% (Current Assets).
        SELECT
             coa.AccountCode
            ,coa.Description + ' - ' + ISNULL(b.BranchName, b.BranchCode) AS AccountDescription
            ,b.BranchCode
            ,b.BranchName
            ,CAST(ISNULL(lpb.EndingBalance, 0) AS DECIMAL(19,2)) AS Amount
            ,CAST(ISNULL(lpb.EndingBalance, 0) AS DECIMAL(19,2)) AS RawEndingBalance
            ,'1-Current Assets' AS BSSection
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
            ,CAST(NULL AS VARCHAR(128)) AS BranchCode
            ,CAST(NULL AS VARCHAR(128)) AS BranchName
            ,CAST(-SUM(ISNULL(lp.EndingBalance, 0)) AS DECIMAL(19,2)) AS Amount
            ,CAST( SUM(ISNULL(lp.EndingBalance, 0)) AS DECIMAL(19,2)) AS RawEndingBalance
            ,'5-Equity' AS BSSection
        FROM LatestPosting lp
        INNER JOIN ChartOfAccounts coa ON coa.AccountCode = lp.AccountCode
        WHERE coa.AccountType    = 'D'
          AND coa.YearEndIndicator = 'IS'
    )
    SELECT AccountCode, AccountDescription, BranchCode, BranchName, Amount, RawEndingBalance, BSSection
    INTO #DetailRows
    FROM (
        SELECT AccountCode, AccountDescription, BranchCode, BranchName, Amount, RawEndingBalance, BSSection FROM BSBase
        UNION ALL
        SELECT AccountCode, AccountDescription, BranchCode, BranchName, Amount, RawEndingBalance, BSSection FROM PerBranchBase
        UNION ALL
        SELECT AccountCode, AccountDescription, BranchCode, BranchName, Amount, RawEndingBalance, BSSection FROM CurrentEarnings WHERE Amount <> 0
    ) combined;

    -- A CTE chain can only be followed by the ONE statement that consumes it, so
    -- SectionTotals/GrandTotals -- and the guard below, which needs its own statement --
    -- have to live past that boundary via a real temp table instead of staying a CTE.
    SELECT BSSection, CAST(SUM(Amount) AS DECIMAL(19,2)) AS SectionTotal
    INTO #SectionTotals
    FROM #DetailRows
    GROUP BY BSSection;

    -- sp-reviewer finding: the section-total CASE below (and TotalAssets/TotalLiabilities/
    -- TotalEquity, unchanged from the live 2-result-set SP) only ever sums BSSection LIKE
    -- '1%'/'2-Non-Current Assets'/'3%'/'4%'/'5%'. Any detail account that falls into the
    -- BSSection CASE's '9-Other' fallback (an AccountType='D', YearEndIndicator='BS' account
    -- whose code doesn't match 101/102/103/20202/201/202/203/3%) would silently drop out of
    -- every total AND -- new risk specific to this single-grid reshape -- '9-Other' sorts
    -- lexically AFTER '6-Totals', so it would render below the GRANDTOTAL rows, contradicting
    -- "GRANDTOTAL always last." No current account hits this (verified live), but fail loudly
    -- rather than silently misstate the balance sheet if a future COA addition ever does.
    IF EXISTS (SELECT 1 FROM #SectionTotals WHERE BSSection = '9-Other')
    BEGIN
        THROW 50000, 'One or more posting BS accounts do not map to a known Balance Sheet section (AccountCode does not match 101/102/103/20202/201/202/203/3%). Fix the account''s classification before running this report.', 1;
    END;

    ;WITH GrandTotals AS
    (
        SELECT
             CAST(SUM(CASE WHEN BSSection LIKE '1%' OR BSSection = '2-Non-Current Assets'
                           THEN SectionTotal ELSE 0 END) AS DECIMAL(19,2)) AS TotalAssets
            ,CAST(SUM(CASE WHEN BSSection LIKE '3%' OR BSSection LIKE '4%'
                           THEN SectionTotal ELSE 0 END) AS DECIMAL(19,2)) AS TotalLiabilities
            ,CAST(SUM(CASE WHEN BSSection LIKE '5%'
                           THEN SectionTotal ELSE 0 END) AS DECIMAL(19,2)) AS TotalEquity
        FROM #SectionTotals
    )
    SELECT RowType, BSSection, AccountCode, AccountDescription, BranchCode, BranchName, Amount, RawEndingBalance
    FROM (
        SELECT
             'DETAIL' AS RowType, BSSection, AccountCode, AccountDescription, BranchCode, BranchName,
             Amount, RawEndingBalance, 0 AS SortRank
        FROM #DetailRows

        UNION ALL

        SELECT
             'SUBTOTAL', BSSection, CAST(NULL AS VARCHAR(50)), 'TOTAL - ' + SUBSTRING(BSSection, 3, 50),
             CAST(NULL AS VARCHAR(128)), CAST(NULL AS VARCHAR(128)), SectionTotal, CAST(NULL AS DECIMAL(19,2)), 1
        FROM #SectionTotals

        UNION ALL

        -- Each GRANDTOTAL row gets its OWN SortRank (2/3/4), not a shared value -- three rows
        -- tying on every ORDER BY column has no guaranteed relative order in SQL Server (a
        -- different plan/stats update could silently reshuffle "DIFFERENCE" above "TOTAL
        -- ASSETS"). sp-reviewer finding.
        --
        -- The DIFFERENCE row gets its OWN RowType ('GRANDTOTAL_DIFF', not 'GRANDTOTAL') --
        -- the C# grid needs to flip this one row red when it's non-zero (an out-of-balance
        -- statement), and matching on the AccountDescription text would silently break the
        -- moment either side's wording changes. ui-form-reviewer finding.
        SELECT 'GRANDTOTAL', '6-Totals', NULL, 'TOTAL ASSETS', NULL, NULL, TotalAssets, NULL, 2
        FROM GrandTotals
        UNION ALL
        SELECT 'GRANDTOTAL', '6-Totals', NULL, 'TOTAL LIABILITIES & EQUITY', NULL, NULL, TotalLiabilities + TotalEquity, NULL, 3
        FROM GrandTotals
        UNION ALL
        SELECT 'GRANDTOTAL_DIFF', '6-Totals', NULL, 'DIFFERENCE (Assets vs Liabilities & Equity)', NULL, NULL,
               TotalAssets - (TotalLiabilities + TotalEquity), NULL, 4
        FROM GrandTotals
    ) x
    ORDER BY BSSection, SortRank, AccountCode, ISNULL(BranchCode, '');

    DROP TABLE IF EXISTS #DetailRows;
    DROP TABLE IF EXISTS #SectionTotals;
END;
GO
