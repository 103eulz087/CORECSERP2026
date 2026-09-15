-- Fix: sp_rpt_IncomeStatementAllBranchesPivot_TEST ("Income Statement", All Branches / Pivot)
-- was returning TWO result sets (SET1 = pivoted line items, SET2 = pivoted P&L summary), but
-- AccountingReportsFormV2.cs's ResultShape.SingleSet binding only shows ds.Tables[0] and
-- explicitly discards ds.Tables[1] -- so the pivot view was silently missing every "header
-- account" row (TOTAL REVENUE, TOTAL COST OF GOODS SOLD, GROSS PROFIT, etc.), while unchecking
-- "All Branches" (single-branch mode, sp_rpt_IncomeStatementWithDateSingleGrid) correctly showed
-- them, since that SP already returns ONE merged result set.
--
-- This merges the pivot SP's own two result sets into ONE, the same way the single-branch SP
-- was reshaped: a RowType discriminator ('DETAIL'/'SECTION_SUBTOTAL'/'GRANDTOTAL'), pivoted by
-- BranchName ONCE so header/total rows render in the same grid as the line items. No
-- ExpenseSubSection tier here -- this pivot SP never had that granularity to begin with; can be
-- added later if wanted, out of scope for "the header rows are missing."
--
-- Two correctness fixes applied while rewriting (both already found and fixed in the sibling
-- single-branch SPs -- see SQL/2026-09-13_sp_rpt_IncomeStatementWithDateSingleGrid_NewReport.sql
-- for the full rationale):
--   1. Section/summary totals are computed directly from PeriodDebits/PeriodCredits, nature-
--      agnostic, NOT derived from the per-row NetAmount column -- the original #BranchSummary's
--      TotalCOGS/TotalExpenses were already effectively nature-agnostic (verified algebraically:
--      TotalCOGS's Nature-branched formula collapses to the same Debit-Credit either way), so no
--      figures actually change here, but the derivation is now consistent/explicit with the
--      single-branch SPs instead of coincidentally correct.
--   2. TotalRevenue here previously EXCLUDED AccountCode IN ('403','404') from the start, making
--      this SP's "Gross Profit" (TotalRevenue[excl. 403/404] - TotalCOGS) different from
--      sp_rpt_IncomeStatementWithDateSingleGrid's Gross Profit (TotalRevenue[incl. 403/404] -
--      TotalCOGS) for the same period -- standardized on the single-branch SP's definition
--      (TotalRevenue includes 403/404; Other Income is reported and subtracted separately only
--      for Operating Income) so "Gross Profit" means the same thing whether or not "All
--      Branches" is checked. Operating Income/Net Income were already numerically equivalent
--      either way (verified: this SP's original Operating Income/Net Income formulas reduce to
--      the same values as the single-branch SP's, just packaged through a differently-scoped
--      TotalRevenue) -- only Gross Profit actually changes.
--
-- Callers: HOFormsDevEx/AccountingReportsFormV2.cs, "Income Statement" -> "All Branches (Pivot)".
IF OBJECT_ID('dbo.sp_rpt_IncomeStatementAllBranchesPivot_TEST', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_IncomeStatementAllBranchesPivot_TEST', 'sp_rpt_IncomeStatementAllBranchesPivot_TEST_OLD_09132026210000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_IncomeStatementAllBranchesPivot_TEST]
(
    @DateFrom DATE,
    @DateTo   DATE
)
AS
/*
    Returns: ONE result set -- per-branch pivoted (branches as columns, plus a Grand Total
    column) posting IS account line items, section subtotals (TOTAL REVENUE/TOTAL COST OF GOODS
    SOLD/TOTAL OPERATING EXPENSES), and P&L grand totals (GROSS PROFIT/OPERATING INCOME/OTHER
    INCOME/NET INCOME), discriminated by a hidden RowType/ISSection pair (same convention as
    sp_rpt_IncomeStatementWithDateSingleGrid -- see that script's header for the full sign-
    nuance rationale, which applies identically here).
    Assumes: same as sp_rpt_IncomeStatementWithDateSingleGrid, across every branch instead of
    one.
    Callers: HOFormsDevEx/AccountingReportsFormV2.cs ("Income Statement" -> All Branches/Pivot).
*/
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#BranchActivity') IS NOT NULL DROP TABLE #BranchActivity;
    IF OBJECT_ID('tempdb..#BranchSummary')  IS NOT NULL DROP TABLE #BranchSummary;
    IF OBJECT_ID('tempdb..#PivotSource')    IS NOT NULL DROP TABLE #PivotSource;

    -- ── Per-branch, per-account activity (same math as sp_rpt_IncomeStatementWithDate) ──
    ;WITH ISActivity AS
    (
        SELECT
             gs.BranchCode
            ,gs.AccountCode
            ,SUM(gs.Debits)       AS PeriodDebits
            ,SUM(gs.Credits)      AS PeriodCreditsRaw
            ,SUM(ABS(gs.Credits)) AS PeriodCredits
        FROM GLSummary gs
        WHERE gs.PostingDate BETWEEN @DateFrom AND @DateTo
        GROUP BY gs.BranchCode, gs.AccountCode
    )
    SELECT
         ia.BranchCode
        -- Falls back to BranchCode when BranchName is blank/NULL -- STRING_AGG silently drops
        -- a NULL input, which would make that branch's whole column (and its GL activity)
        -- vanish from the pivot with no error. Normalized once here so every downstream use
        -- (the #BranchSummary/#PivotSource BranchName below, the pivot column list, and the
        -- PIVOT clause's own FOR BranchName IN (...)) stays consistent automatically.
        ,ISNULL(NULLIF(LTRIM(RTRIM(b.BranchName)), ''), b.BranchCode) AS BranchName
        ,coa.AccountCode
        ,coa.Description AS AccountDescription
        ,coa.LevelNumber
        ,coa.Nature
        ,CASE
            WHEN LEFT(coa.AccountCode,1) = '4' THEN '1-Revenue'
            WHEN LEFT(coa.AccountCode,1) = '5' THEN '2-Cost of Goods Sold'
            WHEN LEFT(coa.AccountCode,1) = '6' THEN '4-Operating Expenses'
            ELSE                                     '9-Other'
         END AS ISSection
        ,CAST(
            CASE coa.Nature
                WHEN 'C' THEN ia.PeriodCredits - ia.PeriodDebits
                WHEN 'D' THEN ia.PeriodDebits  - ia.PeriodCredits
            END
         AS DECIMAL(19,2)) AS NetAmount
    INTO #BranchActivity
    FROM ISActivity ia
    INNER JOIN ChartOfAccounts coa ON coa.AccountCode = ia.AccountCode
    INNER JOIN dbo.Branches b ON b.BranchCode = ia.BranchCode
    WHERE coa.AccountType      = 'D'
      AND coa.YearEndIndicator = 'IS'
      AND (ia.PeriodDebits <> 0 OR ia.PeriodCreditsRaw <> 0);

    IF EXISTS (SELECT 1 FROM #BranchActivity WHERE ISSection = '9-Other')
    BEGIN
        THROW 50000, 'One or more posting IS accounts do not map to a known Income Statement section (AccountCode does not start with 4/5/6). Fix the account''s classification before running this report.', 1;
    END;

    IF EXISTS (SELECT 1 FROM ChartOfAccounts WHERE AccountType = 'D' AND YearEndIndicator = 'IS' AND Nature NOT IN ('C','D'))
    BEGIN
        THROW 50000, 'One or more posting IS accounts have an unrecognized Nature (expected ''C'' or ''D''). Fix the account''s Nature before running this report.', 1;
    END;

    -- ── Per-branch P&L summary metrics -- nature-agnostic (unconditional on Nature), same
    --    formulas as sp_rpt_IncomeStatementWithDateSingleGrid, NOT derived from NetAmount ──
    ;WITH ISActivity2 AS
    (
        SELECT
             gs.BranchCode
            ,gs.AccountCode
            ,SUM(gs.Debits)       AS PeriodDebits
            ,SUM(ABS(gs.Credits)) AS PeriodCredits
        FROM GLSummary gs
        WHERE gs.PostingDate BETWEEN @DateFrom AND @DateTo
        GROUP BY gs.BranchCode, gs.AccountCode
    )
    SELECT
         ia.BranchCode
        ,ISNULL(NULLIF(LTRIM(RTRIM(b.BranchName)), ''), b.BranchCode) AS BranchName
        ,CAST(SUM(CASE WHEN LEFT(coa.AccountCode,1) = '4'
                       THEN ia.PeriodCredits - ia.PeriodDebits ELSE 0 END) AS DECIMAL(19,2)) AS TotalRevenue
        ,CAST(SUM(CASE WHEN LEFT(coa.AccountCode,1) = '5'
                       THEN ia.PeriodDebits - ia.PeriodCredits ELSE 0 END) AS DECIMAL(19,2)) AS TotalCOGS
        ,CAST(SUM(CASE WHEN LEFT(coa.AccountCode,1) = '6'
                       THEN ia.PeriodDebits - ia.PeriodCredits ELSE 0 END) AS DECIMAL(19,2)) AS TotalExpenses
        ,CAST(SUM(CASE WHEN coa.AccountCode IN ('403','404')
                       THEN ia.PeriodCredits - ia.PeriodDebits ELSE 0 END) AS DECIMAL(19,2)) AS OtherIncome
    INTO #BranchSummary
    FROM ISActivity2 ia
    INNER JOIN ChartOfAccounts coa ON coa.AccountCode = ia.AccountCode
    INNER JOIN dbo.Branches b ON b.BranchCode = ia.BranchCode
    WHERE coa.AccountType = 'D' AND coa.YearEndIndicator = 'IS'
    GROUP BY ia.BranchCode, b.BranchName;

    -- ── Merge DETAIL + SECTION_SUBTOTAL + GRANDTOTAL rows into ONE long/unpivoted staging
    --    table, then pivot ONCE so header/total rows render in the SAME grid as the line items
    --    instead of a separate summary grid. ──
    SELECT RowType, ISSection, SortRank, AccountCode, AccountDescription, BranchName, Value
    INTO #PivotSource
    FROM (
        SELECT
             'DETAIL' AS RowType, ISSection, 0 AS SortRank, AccountCode, AccountDescription,
             BranchName, NetAmount AS Value
        FROM #BranchActivity

        UNION ALL

        SELECT 'SECTION_SUBTOTAL', '1-Revenue',             1, NULL, 'TOTAL REVENUE',             BranchName, TotalRevenue  FROM #BranchSummary
        UNION ALL
        SELECT 'SECTION_SUBTOTAL', '2-Cost of Goods Sold',  1, NULL, 'TOTAL COST OF GOODS SOLD',  BranchName, TotalCOGS     FROM #BranchSummary
        UNION ALL
        SELECT 'SECTION_SUBTOTAL', '4-Operating Expenses',  1, NULL, 'TOTAL OPERATING EXPENSES',  BranchName, TotalExpenses FROM #BranchSummary

        UNION ALL

        -- Same ISSection/SortRank scheme as the single-branch SP: '3-Gross Profit' sorts
        -- between COGS and Operating Expenses; '5-Grand Totals' holds the last three.
        SELECT 'GRANDTOTAL', '3-Gross Profit',  0, NULL, 'GROSS PROFIT',     BranchName, CAST(TotalRevenue - TotalCOGS AS DECIMAL(19,2)) FROM #BranchSummary
        UNION ALL
        SELECT 'GRANDTOTAL', '5-Grand Totals',  0, NULL, 'OPERATING INCOME', BranchName, CAST((TotalRevenue - OtherIncome) - TotalCOGS - TotalExpenses AS DECIMAL(19,2)) FROM #BranchSummary
        UNION ALL
        SELECT 'GRANDTOTAL', '5-Grand Totals',  1, NULL, 'OTHER INCOME',     BranchName, OtherIncome FROM #BranchSummary
        UNION ALL
        SELECT 'GRANDTOTAL', '5-Grand Totals',  2, NULL, 'NET INCOME',       BranchName, CAST(TotalRevenue - TotalCOGS - TotalExpenses AS DECIMAL(19,2)) FROM #BranchSummary
    ) merged;

    IF NOT EXISTS (SELECT 1 FROM #PivotSource)
    BEGIN
        SELECT
             CAST(NULL AS VARCHAR(20))  AS RowType
            ,CAST(NULL AS VARCHAR(30))  AS ISSection
            ,CAST(NULL AS VARCHAR(20))  AS AccountCode
            ,CAST(NULL AS VARCHAR(200)) AS AccountDescription
            ,CAST(NULL AS DECIMAL(19,2)) AS [Grand Total]
        WHERE 1 = 0;
        DROP TABLE #BranchActivity;
        DROP TABLE #BranchSummary;
        DROP TABLE #PivotSource;
        RETURN;
    END

    -- Fail loudly if two distinct branches ever normalize to the same pivot column label
    -- (identical BranchName, or identical BranchCode-fallback collision) -- STRING_AGG would
    -- otherwise emit that label twice into the PIVOT's FOR-list and SQL Server throws "column
    -- name ... specified more than once", or worse, an actually-silent value merge.
    IF EXISTS (
        SELECT BranchName FROM (
            SELECT DISTINCT BranchCode, BranchName FROM #BranchActivity
            UNION
            SELECT DISTINCT BranchCode, BranchName FROM #BranchSummary
        ) x
        GROUP BY BranchName
        HAVING COUNT(DISTINCT BranchCode) > 1
    )
    BEGIN
        THROW 50000, 'Two or more branches share the same effective column label (Branches.BranchName is blank/duplicated) -- fix the duplicate before running this pivot report.', 1;
    END;

    -- ── Branch column list, numerically ordered by code -- derived from the UNION of both
    --    source tables (not just #BranchActivity) so a branch with summary-only activity (no
    --    individual DETAIL row surviving the nonzero-activity filter) still gets a column. ──
    -- @BranchColsForPivot: plain bracketed names, required as-is by PIVOT's FOR clause.
    -- @BranchColsForSelect: same columns wrapped in ISNULL(...,0) for the outer SELECT, so an
    -- account/row with no activity in a given branch shows 0 instead of a blank cell (PIVOT's
    -- SUM over an empty group is NULL, not 0) -- same treatment [Grand Total] already got.
    DECLARE @BranchColsForPivot  NVARCHAR(MAX);
    DECLARE @BranchColsForSelect NVARCHAR(MAX);
    DECLARE @GrandTotalExpr      NVARCHAR(MAX);

    ;WITH OrderedBranches AS (
        SELECT DISTINCT BranchCode, BranchName FROM #BranchActivity
        UNION
        SELECT DISTINCT BranchCode, BranchName FROM #BranchSummary
    )
    SELECT @BranchColsForPivot = STRING_AGG(QUOTENAME(BranchName), ',')
        WITHIN GROUP (ORDER BY ISNULL(TRY_CAST(BranchCode AS INT), 999999), BranchCode)
    FROM OrderedBranches;

    ;WITH OrderedBranches AS (
        SELECT DISTINCT BranchCode, BranchName FROM #BranchActivity
        UNION
        SELECT DISTINCT BranchCode, BranchName FROM #BranchSummary
    )
    SELECT @BranchColsForSelect = STRING_AGG(
        'CAST(ISNULL(' + QUOTENAME(BranchName) + ',0) AS DECIMAL(19,2)) AS ' + QUOTENAME(BranchName), ','
    ) WITHIN GROUP (ORDER BY ISNULL(TRY_CAST(BranchCode AS INT), 999999), BranchCode)
    FROM OrderedBranches;

    ;WITH OrderedBranches AS (
        SELECT DISTINCT BranchCode, BranchName FROM #BranchActivity
        UNION
        SELECT DISTINCT BranchCode, BranchName FROM #BranchSummary
    )
    SELECT @GrandTotalExpr = STRING_AGG('ISNULL(' + QUOTENAME(BranchName) + ',0)', '+')
        WITHIN GROUP (ORDER BY ISNULL(TRY_CAST(BranchCode AS INT), 999999), BranchCode)
    FROM OrderedBranches;

    -- ── ONE pivoted result set -- RowType/ISSection carried through the PIVOT's implicit
    --    grouping for ORDER BY, but deliberately left out of the final SELECT list (hidden
    --    columns in the C# grid instead -- same treatment as the single-branch SPs). ──
    DECLARE @sql NVARCHAR(MAX) = N'
        SELECT
             RowType, ISSection, AccountCode, AccountDescription
            ,' + @BranchColsForSelect + N'
            ,CAST((' + @GrandTotalExpr + N') AS DECIMAL(19,2)) AS [Grand Total]
        FROM (
            SELECT RowType, ISSection, SortRank, AccountCode, AccountDescription, BranchName, Value
            FROM #PivotSource
        ) src
        PIVOT (
            SUM(Value) FOR BranchName IN (' + @BranchColsForPivot + N')
        ) pvt
        ORDER BY pvt.ISSection, pvt.SortRank, pvt.AccountCode;';

    EXEC sp_executesql @sql;

    DROP TABLE #BranchActivity;
    DROP TABLE #BranchSummary;
    DROP TABLE #PivotSource;
END;
GO
