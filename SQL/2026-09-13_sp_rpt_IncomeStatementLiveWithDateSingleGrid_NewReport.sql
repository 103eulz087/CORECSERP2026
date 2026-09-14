-- New, fully isolated report proc: Income Statement (Real-Time), single-grid presentation.
-- Zero existing objects modified -- net-new SP, sibling to
-- SQL/2026-09-13_sp_rpt_IncomeStatementWithDateSingleGrid_NewReport.sql (see that script's
-- header for the full RowType/row-order/sign-nuance contract, identical here). This version
-- additionally carries over sp_rpt_IncomeStatementLiveWithDate's current shape verbatim:
--   - Posted-GLSummary + live-TicketDetails hybrid activity, per-branch cutoff
--     (BranchScope/GLMaxDate/BranchCutoff CTEs), @IncludeLiveActivity toggle.
--   - @BranchCode nullable -- NULL consolidates every in-scope branch (plain SUM
--     consolidation, NOT the separate side-by-side pivot feature).
--   - @IncludeZeroActivity -- 1 lists every IS detail account regardless of period activity
--     (drives #DetailRows FROM ChartOfAccounts LEFT JOIN #CombinedActivity, same as the
--     2-grid version's SET 1 change).
--   - Every total wrapped in ISNULL(...,0) -- a scope with zero matching IS accounts (a
--     dormant/new branch, or @IncludeZeroActivity=0 with a genuinely empty period) must
--     still return real 0-value SECTION_SUBTOTAL/GRANDTOTAL rows, not silently omit them.
--
-- Callers: HOFormsDevEx/AccountingReportsFormV2.cs, "Income Statement (Real-Time)".
IF OBJECT_ID('dbo.sp_rpt_IncomeStatementLiveWithDateSingleGrid', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_IncomeStatementLiveWithDateSingleGrid', 'sp_rpt_IncomeStatementLiveWithDateSingleGrid_OLD_09132026200000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_IncomeStatementLiveWithDateSingleGrid]
    @BranchCode          VARCHAR(5) = NULL,
    @DateFrom            DATE,
    @DateTo              DATE,
    @IncludeLiveActivity BIT        = 1,
    @IncludeZeroActivity BIT        = 0
AS
/*
    Returns: ONE result set -- same RowType-discriminated shape as
    sp_rpt_IncomeStatementWithDateSingleGrid (see that script's header comment for the full
    contract), fed by the posted+live hybrid, multi-branch-consolidating activity CTE this SP's
    2-grid sibling (sp_rpt_IncomeStatementLiveWithDate) already uses.
    Assumes: same as sp_rpt_IncomeStatementLiveWithDate -- PostingDateControl/GLSummary MAX
    determine each branch's posting cutoff; TicketDetails past that cutoff is "live" activity
    not yet posted; ChartOfAccounts.AccountType='D'/YearEndIndicator='IS' as usual.
    Callers: HOFormsDevEx/AccountingReportsFormV2.cs ("Income Statement (Real-Time)").
*/
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#CombinedActivity') IS NOT NULL DROP TABLE #CombinedActivity;
    IF OBJECT_ID('tempdb..#DetailRows') IS NOT NULL DROP TABLE #DetailRows;
    IF OBJECT_ID('tempdb..#SectionTotals') IS NOT NULL DROP TABLE #SectionTotals;
    IF OBJECT_ID('tempdb..#SubsectionTotals') IS NOT NULL DROP TABLE #SubsectionTotals;

    -- ── Hybrid posted+live period activity per account, built ONCE, consolidated across
    --    every in-scope branch -- verbatim from sp_rpt_IncomeStatementLiveWithDate ──────────
    ;WITH BranchScope AS
    (
        SELECT DISTINCT BranchCode FROM (
            SELECT BranchCode FROM Branches
            UNION
            SELECT BranchCode FROM GLSummary
            UNION
            SELECT BranchCode FROM TicketDetails
        ) allBranches
        WHERE (@BranchCode IS NULL OR BranchCode = @BranchCode)
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
             gs.AccountCode
            ,SUM(gs.Debits)       AS PeriodDebits
            ,SUM(ABS(gs.Credits)) AS PeriodCredits
        FROM GLSummary gs
        WHERE (@BranchCode IS NULL OR gs.BranchCode = @BranchCode)
          AND gs.PostingDate BETWEEN @DateFrom AND @DateTo
        GROUP BY gs.AccountCode
    ),
    LiveActivity AS
    (
        SELECT
             td.AccountCode
            ,SUM(ISNULL(td.Debit,0))  AS PeriodDebits
            ,SUM(ISNULL(td.Credit,0)) AS PeriodCredits
        FROM TicketDetails td
        INNER JOIN BranchCutoff bc ON bc.BranchCode = td.BranchCode
        WHERE @IncludeLiveActivity = 1
          AND td.TicketDate >= GREATEST(DATEADD(day, 1, ISNULL(bc.Cutoff, '19000101')), @DateFrom)
          AND td.TicketDate <  DATEADD(day, 1, @DateTo)
        GROUP BY td.AccountCode
    )
    SELECT
         COALESCE(pa.AccountCode, la.AccountCode)                   AS AccountCode
        ,ISNULL(pa.PeriodDebits,0)     + ISNULL(la.PeriodDebits,0)  AS PeriodDebits
        ,ISNULL(pa.PeriodCredits,0)    + ISNULL(la.PeriodCredits,0) AS PeriodCredits
    INTO #CombinedActivity
    FROM PostedActivity pa
    FULL OUTER JOIN LiveActivity la ON la.AccountCode = pa.AccountCode;

    -- ── DETAIL rows -- FROM ChartOfAccounts (LEFT JOIN #CombinedActivity), gated by
    --    @IncludeZeroActivity, same as the 2-grid version's SET 1 ─────────────────────────
    SELECT
         coa.AccountCode
        ,coa.Description AS AccountDescription
        ,CASE
            WHEN LEFT(coa.AccountCode,1) = '4' THEN '1-Revenue'
            WHEN LEFT(coa.AccountCode,1) = '5' THEN '2-Cost of Goods Sold'
            WHEN LEFT(coa.AccountCode,1) = '6' THEN '4-Operating Expenses'
            ELSE                                     '9-Other'
         END AS ISSection
        ,CASE
            WHEN coa.AccountCode LIKE '601%' THEN '3A-Employee Benefits'
            WHEN coa.AccountCode LIKE '602%' THEN '3B-Depreciation'
            WHEN coa.AccountCode LIKE '603%' THEN '3C-Selling & Admin'
            WHEN LEFT(coa.AccountCode,1) = '6' THEN '3D-Other Expenses'
            ELSE NULL
         END AS ExpenseSubSection
        ,CAST(ISNULL(ca.PeriodDebits,0)  AS DECIMAL(19,2)) AS PeriodDebits
        ,CAST(ISNULL(ca.PeriodCredits,0) AS DECIMAL(19,2)) AS PeriodCredits
        ,CAST(
            CASE coa.Nature
                WHEN 'C' THEN ISNULL(ca.PeriodCredits,0) - ISNULL(ca.PeriodDebits,0)
                WHEN 'D' THEN ISNULL(ca.PeriodDebits,0)  - ISNULL(ca.PeriodCredits,0)
            END
         AS DECIMAL(19,2)) AS Amount
        ,CASE WHEN LEFT(coa.AccountCode,1) = '5' AND coa.Nature = 'C' THEN 1 ELSE 0 END AS IsContraCOGS
    INTO #DetailRows
    FROM ChartOfAccounts coa
    LEFT JOIN #CombinedActivity ca ON ca.AccountCode = coa.AccountCode
    WHERE coa.AccountType      = 'D'
      AND coa.YearEndIndicator = 'IS'
      AND (@IncludeZeroActivity = 1 OR ISNULL(ca.PeriodDebits,0) <> 0 OR ISNULL(ca.PeriodCredits,0) <> 0);

    IF EXISTS (SELECT 1 FROM #DetailRows WHERE ISSection = '9-Other')
    BEGIN
        THROW 50000, 'One or more posting IS accounts do not map to a known Income Statement section (AccountCode does not start with 4/5/6). Fix the account''s classification before running this report.', 1;
    END;

    IF EXISTS (SELECT 1 FROM ChartOfAccounts WHERE AccountType = 'D' AND YearEndIndicator = 'IS' AND Nature NOT IN ('C','D'))
    BEGIN
        THROW 50000, 'One or more posting IS accounts have an unrecognized Nature (expected ''C'' or ''D''). Fix the account''s Nature before running this report.', 1;
    END;

    -- Section/subsection totals computed directly from PeriodDebits/PeriodCredits, NOT from
    -- the nature-based DETAIL.Amount column -- see the non-live sibling SP's header comment for
    -- the full rationale (ties out to the live 2-grid SP's SET 2 regardless of what Nature
    -- value any given account carries, instead of assuming Revenue/Operating Expenses never
    -- contain a contra-nature account the way only COGS previously accounted for).
    SELECT
         ISSection
        ,CAST(SUM(CASE WHEN ISSection = '1-Revenue' THEN PeriodCredits - PeriodDebits
                        ELSE PeriodDebits - PeriodCredits END) AS DECIMAL(19,2)) AS SectionTotal
    INTO #SectionTotals
    FROM #DetailRows
    GROUP BY ISSection;

    SELECT
         ExpenseSubSection
        ,CAST(SUM(PeriodDebits - PeriodCredits) AS DECIMAL(19,2)) AS SubsectionTotal
    INTO #SubsectionTotals
    FROM #DetailRows
    WHERE ExpenseSubSection IS NOT NULL
    GROUP BY ExpenseSubSection;

    -- Every scalar subquery wrapped in ISNULL(...,0) -- matches the 2-grid version's own
    -- ISNULL-guard fix for a scope with zero matching IS accounts.
    ;WITH Totals AS
    (
        SELECT
             ISNULL((SELECT SectionTotal FROM #SectionTotals WHERE ISSection = '1-Revenue'), 0)            AS TotalRevenue
            ,ISNULL((SELECT SectionTotal FROM #SectionTotals WHERE ISSection = '2-Cost of Goods Sold'), 0) AS TotalCOGS
            ,ISNULL((SELECT SectionTotal FROM #SectionTotals WHERE ISSection = '4-Operating Expenses'), 0) AS TotalExpenses
            ,ISNULL((SELECT SUM(PeriodCredits - PeriodDebits) FROM #DetailRows WHERE AccountCode IN ('403','404')), 0) AS OtherIncome
    ),
    GrandTotals AS
    (
        SELECT
             TotalRevenue, TotalCOGS, TotalExpenses, OtherIncome
            ,CAST(TotalRevenue - TotalCOGS AS DECIMAL(19,2))                                    AS GrossProfit
            ,CAST((TotalRevenue - OtherIncome) - TotalCOGS - TotalExpenses AS DECIMAL(19,2))     AS OperatingIncome
            ,CAST(TotalRevenue - TotalCOGS - TotalExpenses AS DECIMAL(19,2))                     AS NetIncome
        FROM Totals
    )
    SELECT
         RowType, ISSection, ExpenseSubSection, AccountCode, AccountDescription,
         PeriodDebits, PeriodCredits, Amount, IsContraCOGS
    FROM (
        SELECT
             'DETAIL' AS RowType, ISSection, ExpenseSubSection, AccountCode, AccountDescription,
             PeriodDebits, PeriodCredits, Amount, IsContraCOGS, 0 AS SortRank
        FROM #DetailRows

        UNION ALL

        SELECT
             'SUBSECTION_SUBTOTAL', '4-Operating Expenses', st.ExpenseSubSection, NULL,
             'TOTAL - ' + SUBSTRING(st.ExpenseSubSection, 4, 50),
             NULL, NULL, st.SubsectionTotal, NULL, 1
        FROM #SubsectionTotals st

        UNION ALL

        SELECT 'SECTION_SUBTOTAL', '1-Revenue', NULL, NULL, 'TOTAL REVENUE', NULL, NULL, SectionTotal, NULL, 1
        FROM #SectionTotals WHERE ISSection = '1-Revenue'

        UNION ALL

        SELECT 'SECTION_SUBTOTAL', '2-Cost of Goods Sold', NULL, NULL, 'TOTAL COST OF GOODS SOLD', NULL, NULL, SectionTotal, NULL, 1
        FROM #SectionTotals WHERE ISSection = '2-Cost of Goods Sold'

        UNION ALL

        SELECT 'SECTION_SUBTOTAL', '4-Operating Expenses', 'ZZZZ', NULL, 'TOTAL OPERATING EXPENSES', NULL, NULL, SectionTotal, NULL, 2
        FROM #SectionTotals WHERE ISSection = '4-Operating Expenses'

        UNION ALL

        SELECT 'GRANDTOTAL', '3-Gross Profit', NULL, NULL, 'GROSS PROFIT', NULL, NULL, GrossProfit, NULL, 0 FROM GrandTotals
        UNION ALL
        SELECT 'GRANDTOTAL', '5-Grand Totals', NULL, NULL, 'OPERATING INCOME', NULL, NULL, OperatingIncome, NULL, 0 FROM GrandTotals
        UNION ALL
        SELECT 'GRANDTOTAL', '5-Grand Totals', NULL, NULL, 'OTHER INCOME', NULL, NULL, OtherIncome, NULL, 1 FROM GrandTotals
        UNION ALL
        SELECT 'GRANDTOTAL', '5-Grand Totals', NULL, NULL, 'NET INCOME', NULL, NULL, NetIncome, NULL, 2 FROM GrandTotals
    ) x
    ORDER BY ISSection, ISNULL(ExpenseSubSection, ''), SortRank, AccountCode;

    DROP TABLE IF EXISTS #CombinedActivity;
    DROP TABLE IF EXISTS #DetailRows;
    DROP TABLE IF EXISTS #SectionTotals;
    DROP TABLE IF EXISTS #SubsectionTotals;
END;
GO
