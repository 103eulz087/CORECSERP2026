-- New, fully isolated report proc: Income Statement (Real-Time), All Branches / Pivot.
-- Zero existing objects modified -- net-new SP, giving "Income Statement (Real-Time)" the same
-- pivot option "Income Statement" already has (see
-- SQL/2026-09-13_sp_rpt_IncomeStatementAllBranchesPivot_MergeSingleGrid.sql for the base
-- pivot's full design rationale, identical RowType/ISSection/sign-nuance scheme here).
--
-- Activity source is the same posted+live hybrid, per-branch-cutoff pattern as
-- sp_rpt_IncomeStatementLiveWithDateSingleGrid, just kept split per branch (GROUP BY
-- BranchCode, AccountCode) instead of consolidated into one sum, since every branch needs its
-- own pivoted column here.
--
-- No @IncludeZeroActivity parameter -- matches the base pivot SP, which never had that toggle
-- either (AccountingReportsFormV2.cs's RunPivotReport only ever passes @DateFrom/@DateTo to a
-- pivot SP). @IncludeLiveActivity keeps its usual default (1) for the same reason.
--
-- Callers: HOFormsDevEx/AccountingReportsFormV2.cs, "Income Statement (Real-Time)" -> "All
-- Branches (Pivot)".
IF OBJECT_ID('dbo.sp_rpt_IncomeStatementLiveAllBranchesPivot', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_IncomeStatementLiveAllBranchesPivot', 'sp_rpt_IncomeStatementLiveAllBranchesPivot_OLD_09132026210000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_IncomeStatementLiveAllBranchesPivot]
(
    @DateFrom            DATE,
    @DateTo              DATE,
    @IncludeLiveActivity BIT = 1
)
AS
/*
    Returns: ONE result set -- same RowType-discriminated, per-branch-pivoted shape as
    sp_rpt_IncomeStatementAllBranchesPivot_TEST, fed by the posted+live hybrid activity
    sp_rpt_IncomeStatementLiveWithDateSingleGrid already uses, kept per-branch instead of
    consolidated.
    Assumes: same as sp_rpt_IncomeStatementLiveWithDate/sp_rpt_IncomeStatementLiveWithDateSingleGrid.
    Callers: HOFormsDevEx/AccountingReportsFormV2.cs ("Income Statement (Real-Time)" -> All
    Branches/Pivot).
*/
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#CombinedActivity') IS NOT NULL DROP TABLE #CombinedActivity;
    IF OBJECT_ID('tempdb..#BranchActivity')   IS NOT NULL DROP TABLE #BranchActivity;
    IF OBJECT_ID('tempdb..#BranchSummary')    IS NOT NULL DROP TABLE #BranchSummary;
    IF OBJECT_ID('tempdb..#PivotSource')      IS NOT NULL DROP TABLE #PivotSource;

    -- ── Hybrid posted+live period activity per (branch, account) -- same CTEs as
    --    sp_rpt_IncomeStatementLiveWithDateSingleGrid, but GROUP BY BranchCode too instead of
    --    consolidating across every branch into one sum. ──
    ;WITH BranchScope AS
    (
        SELECT DISTINCT BranchCode FROM (
            SELECT BranchCode FROM Branches
            UNION
            SELECT BranchCode FROM GLSummary
            UNION
            SELECT BranchCode FROM TicketDetails
        ) allBranches
    ),
    GLMaxDate AS
    (
        SELECT BranchCode, MAX(PostingDate) AS MaxPostingDate
        FROM GLSummary
        GROUP BY BranchCode
    ),
    BranchCutoff AS
    (
        SELECT
             bs.BranchCode
            ,COALESCE(pdc.LatestPostingDate, gmd.MaxPostingDate) AS Cutoff
        FROM BranchScope bs
        LEFT JOIN PostingDateControl pdc ON pdc.BranchCode = bs.BranchCode
        LEFT JOIN GLMaxDate          gmd ON gmd.BranchCode = bs.BranchCode
    ),
    PostedActivity AS
    (
        SELECT
             gs.BranchCode
            ,gs.AccountCode
            ,SUM(gs.Debits)       AS PeriodDebits
            ,SUM(ABS(gs.Credits)) AS PeriodCredits
        FROM GLSummary gs
        WHERE gs.PostingDate BETWEEN @DateFrom AND @DateTo
        GROUP BY gs.BranchCode, gs.AccountCode
    ),
    LiveActivity AS
    (
        SELECT
             td.BranchCode
            ,td.AccountCode
            ,SUM(ISNULL(td.Debit,0))  AS PeriodDebits
            ,SUM(ISNULL(td.Credit,0)) AS PeriodCredits
        FROM TicketDetails td
        INNER JOIN BranchCutoff bc ON bc.BranchCode = td.BranchCode
        WHERE @IncludeLiveActivity = 1
          AND td.TicketDate >= GREATEST(DATEADD(day, 1, ISNULL(bc.Cutoff, '19000101')), @DateFrom)
          AND td.TicketDate <  DATEADD(day, 1, @DateTo)
        GROUP BY td.BranchCode, td.AccountCode
    )
    SELECT
         COALESCE(pa.BranchCode, la.BranchCode)                    AS BranchCode
        ,COALESCE(pa.AccountCode, la.AccountCode)                   AS AccountCode
        ,ISNULL(pa.PeriodDebits,0)     + ISNULL(la.PeriodDebits,0)  AS PeriodDebits
        ,ISNULL(pa.PeriodCredits,0)    + ISNULL(la.PeriodCredits,0) AS PeriodCredits
    INTO #CombinedActivity
    FROM PostedActivity pa
    FULL OUTER JOIN LiveActivity la
        ON la.AccountCode = pa.AccountCode AND la.BranchCode = pa.BranchCode;

    -- ── DETAIL rows -- same classification/NetAmount formula as the base pivot SP ──
    SELECT
         ca.BranchCode
        -- Falls back to BranchCode when BranchName is blank/NULL -- see the base pivot SP's
        -- comment for why (STRING_AGG silently drops a NULL pivot key, making that branch's
        -- whole column vanish with no error).
        ,ISNULL(NULLIF(LTRIM(RTRIM(b.BranchName)), ''), b.BranchCode) AS BranchName
        ,coa.AccountCode
        ,coa.Description AS AccountDescription
        ,CASE
            WHEN LEFT(coa.AccountCode,1) = '4' THEN '1-Revenue'
            WHEN LEFT(coa.AccountCode,1) = '5' THEN '2-Cost of Goods Sold'
            WHEN LEFT(coa.AccountCode,1) = '6' THEN '4-Operating Expenses'
            ELSE                                     '9-Other'
         END AS ISSection
        ,CAST(
            CASE coa.Nature
                WHEN 'C' THEN ca.PeriodCredits - ca.PeriodDebits
                WHEN 'D' THEN ca.PeriodDebits  - ca.PeriodCredits
            END
         AS DECIMAL(19,2)) AS NetAmount
    INTO #BranchActivity
    FROM #CombinedActivity ca
    INNER JOIN ChartOfAccounts coa ON coa.AccountCode = ca.AccountCode
    INNER JOIN dbo.Branches b ON b.BranchCode = ca.BranchCode
    WHERE coa.AccountType      = 'D'
      AND coa.YearEndIndicator = 'IS'
      AND (ca.PeriodDebits <> 0 OR ca.PeriodCredits <> 0);

    IF EXISTS (SELECT 1 FROM #BranchActivity WHERE ISSection = '9-Other')
    BEGIN
        THROW 50000, 'One or more posting IS accounts do not map to a known Income Statement section (AccountCode does not start with 4/5/6). Fix the account''s classification before running this report.', 1;
    END;

    IF EXISTS (SELECT 1 FROM ChartOfAccounts WHERE AccountType = 'D' AND YearEndIndicator = 'IS' AND Nature NOT IN ('C','D'))
    BEGIN
        THROW 50000, 'One or more posting IS accounts have an unrecognized Nature (expected ''C'' or ''D''). Fix the account''s Nature before running this report.', 1;
    END;

    -- ── Per-branch P&L summary metrics -- nature-agnostic, same formulas as the base pivot SP ──
    SELECT
         ca.BranchCode
        ,ISNULL(NULLIF(LTRIM(RTRIM(b.BranchName)), ''), b.BranchCode) AS BranchName
        ,CAST(SUM(CASE WHEN LEFT(coa.AccountCode,1) = '4'
                       THEN ca.PeriodCredits - ca.PeriodDebits ELSE 0 END) AS DECIMAL(19,2)) AS TotalRevenue
        ,CAST(SUM(CASE WHEN LEFT(coa.AccountCode,1) = '5'
                       THEN ca.PeriodDebits - ca.PeriodCredits ELSE 0 END) AS DECIMAL(19,2)) AS TotalCOGS
        ,CAST(SUM(CASE WHEN LEFT(coa.AccountCode,1) = '6'
                       THEN ca.PeriodDebits - ca.PeriodCredits ELSE 0 END) AS DECIMAL(19,2)) AS TotalExpenses
        ,CAST(SUM(CASE WHEN coa.AccountCode IN ('403','404')
                       THEN ca.PeriodCredits - ca.PeriodDebits ELSE 0 END) AS DECIMAL(19,2)) AS OtherIncome
    INTO #BranchSummary
    FROM #CombinedActivity ca
    INNER JOIN ChartOfAccounts coa ON coa.AccountCode = ca.AccountCode
    INNER JOIN dbo.Branches b ON b.BranchCode = ca.BranchCode
    WHERE coa.AccountType = 'D' AND coa.YearEndIndicator = 'IS'
    GROUP BY ca.BranchCode, b.BranchName;

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
        DROP TABLE #CombinedActivity;
        DROP TABLE #BranchActivity;
        DROP TABLE #BranchSummary;
        DROP TABLE #PivotSource;
        RETURN;
    END

    -- Fail loudly if two distinct branches ever normalize to the same pivot column label --
    -- see the base pivot SP's comment for the full rationale.
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

    -- @BranchColsForPivot: plain bracketed names, required as-is by PIVOT's FOR clause.
    -- @BranchColsForSelect: same columns wrapped in ISNULL(...,0) for the outer SELECT -- see
    -- the base pivot SP's comment for why (a blank cell for a branch with no activity on that
    -- row should read as 0, not blank).
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

    DROP TABLE #CombinedActivity;
    DROP TABLE #BranchActivity;
    DROP TABLE #BranchSummary;
    DROP TABLE #PivotSource;
END;
GO
