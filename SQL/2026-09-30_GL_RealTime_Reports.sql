/* ================================================================
   2026-09-30: GL real-time report procs (retire daily GL posting)
   ================================================================
   Decision (user, 2026-09-30): stop depending on daily GL posting
   (GLPostingDevEx -> sp_GLPosting -> GLPosting, which builds GLSummary).
   Reason, measured on COREX001 / STAGING: GLSummary for Jul-Aug 2026
   differs from TicketDetails on 459 / 513 branch-accounts (353M / 585M of
   debits+credits) -- tickets entered or changed after August was posted
   (back-dated entries, delete-and-repost edits, reversals). Every report
   reading GLSummary inherits that gap, including the "Live" hybrid ones
   (GLSummary up to the posting cutoff + TicketDetails after it: a
   back-dated ticket falls into neither part).
   TicketDetails is small (37-43k lines since 2026-07-24) and clustered on
   (TicketDate, BranchCode, AccountCode): a full all-branch balance straight
   from tickets took 47 ms (DEV) / 94 ms (STAGING).

   NEW procs (the old ones are NOT changed; AccountingReportsFormV2 lists
   both, the new ones as "... (Real-Time)"). Each is its source proc with
   ONLY the GLSummary / PostingDateControl block replaced by a TicketDetails
   aggregation -- same parameters (minus @IncludeLiveActivity, which no
   longer means anything), same result sets, columns, signs and sections:

     sp_rpt_TrialBalanceRealTime                 <- sp_rpt_TrialBalanceWithDate
     sp_rpt_BalanceSheetRealTimeSingleGrid       <- sp_rpt_BalanceSheetLiveWithDateSingleGrid
     sp_rpt_IncomeStatementRealTimeSingleGrid    <- sp_rpt_IncomeStatementLiveWithDateSingleGrid
     sp_rpt_IncomeStatementRealTimeAllBranchesPivot <- sp_rpt_IncomeStatementLiveAllBranchesPivot
     sp_rpt_GLDetailLedgerRealTime               <- sp_rpt_GLDetailLedgerWithDate
     sp_rpt_GLDetailTransactionRealTime          <- sp_rpt_GLDetailTransactionReport
     sp_rpt_BankReconciliationRealTime           <- sp_rpt_BankReconciliationWithDate
     sp_rpt_ConsolidatedGLRealTime               <- sp_rpt_ConsolidatedGLWithDate

   Balances are inception-to-date net Debit - Credit (what GLSummary's
   EndingBalance carried). No year-end closing entries exist yet (system
   started 2026-07); revisit when the first year-end close is designed.
   Month-end locking is separate: SQL/2026-09-30_GL_PeriodLock.sql.

   Deploy to COREX001 (DEV) first; STAGING only after the user confirms.
   ================================================================ */

-- ----------------------------------------------------------------
-- sp_rpt_TrialBalanceRealTime
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_TrialBalanceRealTime', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_TrialBalanceRealTime', 'sp_rpt_TrialBalanceRealTime_OLD_09302026150000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_TrialBalanceRealTime]
    @BranchCode  VARCHAR(5) = NULL,
    @AsOfDate    DATE
AS
/*
    Same two result sets as sp_rpt_TrialBalanceWithDate (line items, then the
    Debit/Credit/Difference summary), computed straight from TicketDetails:
    EndingBalance = SUM(Debit - Credit) of every leg dated <= @AsOfDate.
    Callers: HOFormsDevEx/AccountingReportsFormV2.cs ("Trial Balance (Real-Time)").
*/
BEGIN
    SET NOCOUNT ON;

    SELECT td.AccountCode,
           SUM(ISNULL(td.Debit, 0)) - SUM(ISNULL(td.Credit, 0)) AS EndingBalance
    INTO #Bal
    FROM dbo.TicketDetails AS td
    WHERE (@BranchCode IS NULL OR td.BranchCode = @BranchCode)
      AND td.TicketDate < DATEADD(DAY, 1, @AsOfDate)
    GROUP BY td.AccountCode;

    SELECT
         coa.AccountCode
        ,coa.Description                                    AS AccountDescription
        ,CAST(ISNULL(cb.EndingBalance, 0) AS DECIMAL(19,2)) AS EndingBalance
        ,CAST(CASE WHEN ISNULL(cb.EndingBalance,0) >= 0 THEN ISNULL(cb.EndingBalance,0)
                    ELSE 0 END AS DECIMAL(19,2))              AS [TB Debit]
        ,CAST(CASE WHEN ISNULL(cb.EndingBalance,0) <  0 THEN -ISNULL(cb.EndingBalance,0)
                    ELSE 0 END AS DECIMAL(19,2))              AS [TB Credit]
        ,CASE WHEN (coa.Nature = 'D' AND ISNULL(cb.EndingBalance,0) < 0)
               OR (coa.Nature = 'C' AND ISNULL(cb.EndingBalance,0) > 0)
              THEN 1 ELSE 0 END                                AS [Is Abnormal Balance]
        ,@AsOfDate                                           AS [As Of Date]
        ,ISNULL(@BranchCode, 'ALL')                          AS [Branch Code]
    FROM ChartOfAccounts coa
    LEFT JOIN #Bal cb ON cb.AccountCode = coa.AccountCode
    WHERE coa.AccountType = 'D'
    ORDER BY coa.AccountCode;

    SELECT
         CAST(SUM(CASE WHEN ISNULL(cb.EndingBalance,0) >= 0 THEN ISNULL(cb.EndingBalance,0)
                         ELSE 0 END) AS DECIMAL(19,2)) AS [Total Debit]
        ,CAST(SUM(CASE WHEN ISNULL(cb.EndingBalance,0) <  0 THEN -ISNULL(cb.EndingBalance,0)
                         ELSE 0 END) AS DECIMAL(19,2)) AS [Total Credit]
        ,CAST(
            SUM(CASE WHEN ISNULL(cb.EndingBalance,0) >= 0 THEN ISNULL(cb.EndingBalance,0) ELSE 0 END)
          - SUM(CASE WHEN ISNULL(cb.EndingBalance,0) <  0 THEN -ISNULL(cb.EndingBalance,0) ELSE 0 END)
          AS DECIMAL(19,2)) AS Difference
        ,@AsOfDate AS [As Of Date]
        ,ISNULL(@BranchCode, 'ALL') AS [Branch Code]
    FROM ChartOfAccounts coa
    LEFT JOIN #Bal cb ON cb.AccountCode = coa.AccountCode
    WHERE coa.AccountType = 'D';
END;
GO

-- ----------------------------------------------------------------
-- sp_rpt_BalanceSheetRealTimeSingleGrid
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_BalanceSheetRealTimeSingleGrid', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_BalanceSheetRealTimeSingleGrid', 'sp_rpt_BalanceSheetRealTimeSingleGrid_OLD_09302026150000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_BalanceSheetRealTimeSingleGrid]
    @BranchCode          VARCHAR(5) = NULL,
    @AsOfDate            DATE,
    @IncludeZeroActivity BIT        = 0
AS
/*
    REAL-TIME copy (2026-09-30) of sp_rpt_BalanceSheetLiveWithDateSingleGrid: identical
    result set (RowType 'DETAIL'/'SUBTOTAL'/'GRANDTOTAL'/'GRANDTOTAL_DIFF', same BSSection
    mapping, same Current Period Earnings row), but every account's ending balance comes
    straight from TicketDetails (inception to @AsOfDate) -- no GLSummary, no posting cutoff,
    so back-dated tickets are always included. @IncludeLiveActivity is gone (everything is live).
    Callers: HOFormsDevEx/AccountingReportsFormV2.cs ("Balance Sheet (Real-Time)").
*/
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#LatestPosting') IS NOT NULL DROP TABLE #LatestPosting;
    IF OBJECT_ID('tempdb..#DetailRows')    IS NOT NULL DROP TABLE #DetailRows;
    IF OBJECT_ID('tempdb..#SectionTotals') IS NOT NULL DROP TABLE #SectionTotals;

    -- ── REAL-TIME (2026-09-30): ending balance per account straight from TicketDetails,
    --    inception to @AsOfDate -- no GLSummary, no posting cutoff. Everything below this
    --    block is unchanged from sp_rpt_BalanceSheetLiveWithDateSingleGrid. ──
    SELECT td.AccountCode,
           SUM(ISNULL(td.Debit, 0)) - SUM(ISNULL(td.Credit, 0)) AS EndingBalance
    INTO #LatestPosting
    FROM dbo.TicketDetails AS td
    WHERE (@BranchCode IS NULL OR td.BranchCode = @BranchCode)
      AND td.TicketDate < DATEADD(DAY, 1, @AsOfDate)
    GROUP BY td.AccountCode;

    -- ── DETAIL rows -- same BSSection classification/sign convention as the non-real-time
    --    single-grid SP (structural, based on AccountCode prefix -- not Nature-based, so none
    --    of the Income Statement contra-account sign nuance applies here). ──
    ;WITH BSBase AS
    (
        SELECT
             coa.AccountCode
            ,coa.Description AS AccountDescription
            ,CASE
                WHEN coa.AccountCode LIKE '101%' OR coa.AccountCode LIKE '102%' OR coa.AccountCode LIKE '103%'
                    THEN CAST(ISNULL(lp.EndingBalance,0)  AS DECIMAL(19,2))
                ELSE CAST(-ISNULL(lp.EndingBalance,0) AS DECIMAL(19,2))
             END AS Amount
            ,CAST(ISNULL(lp.EndingBalance,0) AS DECIMAL(19,2)) AS RawEndingBalance
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
        LEFT JOIN #LatestPosting lp ON lp.AccountCode = coa.AccountCode
        WHERE coa.AccountType    = 'D'
          AND coa.YearEndIndicator = 'BS'
          AND (@IncludeZeroActivity = 1 OR ISNULL(lp.EndingBalance,0) <> 0)
    ),
    CurrentEarnings AS
    (
        SELECT
             'CURRENT_EARNINGS'        AS AccountCode
            ,'Current Period Earnings' AS AccountDescription
            ,CAST(-SUM(ISNULL(lp.EndingBalance, 0)) AS DECIMAL(19,2)) AS Amount
            ,CAST( SUM(ISNULL(lp.EndingBalance, 0)) AS DECIMAL(19,2)) AS RawEndingBalance
            ,'5-Equity' AS BSSection
        FROM #LatestPosting lp
        INNER JOIN ChartOfAccounts coa ON coa.AccountCode = lp.AccountCode
        WHERE coa.AccountType    = 'D'
          AND coa.YearEndIndicator = 'IS'
    )
    SELECT AccountCode, AccountDescription, Amount, RawEndingBalance, BSSection
    INTO #DetailRows
    FROM (
        SELECT AccountCode, AccountDescription, Amount, RawEndingBalance, BSSection FROM BSBase
        UNION ALL
        SELECT AccountCode, AccountDescription, Amount, RawEndingBalance, BSSection FROM CurrentEarnings WHERE Amount <> 0
    ) combined;

    -- Same fail-loudly guard as the non-real-time single-grid SP -- the live SP's own SET 2
    -- never had one (it just let an unmapped '9-Other' account show up with no total to roll
    -- into), but since this is new code there's no reason not to add it.
    IF EXISTS (SELECT 1 FROM #DetailRows WHERE BSSection = '9-Other')
    BEGIN
        THROW 50000, 'One or more posting BS accounts do not map to a known Balance Sheet section (AccountCode does not match 101/102/103/20202/201/202/203/3%). Fix the account''s classification before running this report.', 1;
    END;

    -- ── Section totals -- same zero-fill guard as the live 2-grid SP's SET 2 (a scope with
    --    zero BS activity in a section, e.g. a dormant/new branch, still gets a real
    --    SectionTotal=0 SUBTOTAL row for each of the 5 canonical sections, not a missing row).
    --    Unlike that source SP, there's no second branch here surfacing a genuine out-of-canon
    --    '9-Other' section with data as its own row -- it's not dropped for simplicity, it's
    --    unreachable: the THROW guard just above already aborts before this point if any
    --    '9-Other' DETAIL row exists at all. ──
    ;WITH AllSections AS
    (
        SELECT BSSection FROM (VALUES
            ('1-Current Assets'), ('2-Non-Current Assets'),
            ('3-Current Liabilities'), ('4-Non-Current Liabilities'),
            ('5-Equity')
        ) AS s(BSSection)
    )
    SELECT s.BSSection, CAST(ISNULL(SUM(d.Amount),0) AS DECIMAL(19,2)) AS SectionTotal
    INTO #SectionTotals
    FROM AllSections s
    LEFT JOIN #DetailRows d ON d.BSSection = s.BSSection
    GROUP BY s.BSSection;

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
    SELECT RowType, BSSection, AccountCode, AccountDescription, Amount, RawEndingBalance
    FROM (
        SELECT
             'DETAIL' AS RowType, BSSection, AccountCode, AccountDescription,
             Amount, RawEndingBalance, 0 AS SortRank
        FROM #DetailRows

        UNION ALL

        SELECT
             'SUBTOTAL', BSSection, NULL, 'TOTAL - ' + SUBSTRING(BSSection, 3, 50),
             SectionTotal, CAST(NULL AS DECIMAL(19,2)), 1
        FROM #SectionTotals

        UNION ALL

        -- Same distinct-SortRank-per-row and separate GRANDTOTAL_DIFF RowType as the
        -- non-real-time single-grid SP -- see that script's comments for why (ORDER BY ties
        -- have no guaranteed order; the C# grid flips the DIFFERENCE row red by RowType, not
        -- by matching its label text).
        SELECT 'GRANDTOTAL', '6-Totals', NULL, 'TOTAL ASSETS', TotalAssets, NULL, 2
        FROM GrandTotals
        UNION ALL
        SELECT 'GRANDTOTAL', '6-Totals', NULL, 'TOTAL LIABILITIES & EQUITY', TotalLiabilities + TotalEquity, NULL, 3
        FROM GrandTotals
        UNION ALL
        SELECT 'GRANDTOTAL_DIFF', '6-Totals', NULL, 'DIFFERENCE (Assets vs Liabilities & Equity)',
               TotalAssets - (TotalLiabilities + TotalEquity), NULL, 4
        FROM GrandTotals
    ) x
    ORDER BY BSSection, SortRank, AccountCode;

    DROP TABLE IF EXISTS #LatestPosting;
    DROP TABLE IF EXISTS #DetailRows;
    DROP TABLE IF EXISTS #SectionTotals;
END;

GO

-- ----------------------------------------------------------------
-- sp_rpt_IncomeStatementRealTimeSingleGrid
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_IncomeStatementRealTimeSingleGrid', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_IncomeStatementRealTimeSingleGrid', 'sp_rpt_IncomeStatementRealTimeSingleGrid_OLD_09302026150000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_IncomeStatementRealTimeSingleGrid]
    @BranchCode          VARCHAR(5) = NULL,
    @DateFrom            DATE,
    @DateTo              DATE,
    @IncludeZeroActivity BIT        = 0
AS
/*
    REAL-TIME copy (2026-09-30) of sp_rpt_IncomeStatementLiveWithDateSingleGrid: identical
    RowType-discriminated result set (sections, expense subsections, Gross Profit / Operating
    Income / Net Income), but period activity comes straight from TicketDetails for
    @DateFrom..@DateTo -- no GLSummary, no posting cutoff. @IncludeLiveActivity is gone.
    Callers: HOFormsDevEx/AccountingReportsFormV2.cs ("Income Statement (Real-Time)").
*/
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#CombinedActivity') IS NOT NULL DROP TABLE #CombinedActivity;
    IF OBJECT_ID('tempdb..#DetailRows') IS NOT NULL DROP TABLE #DetailRows;
    IF OBJECT_ID('tempdb..#SectionTotals') IS NOT NULL DROP TABLE #SectionTotals;
    IF OBJECT_ID('tempdb..#SubsectionTotals') IS NOT NULL DROP TABLE #SubsectionTotals;

    -- ── REAL-TIME (2026-09-30): period activity per account straight from TicketDetails
    --    -- no GLSummary, no posting cutoff. Everything below this block is unchanged from
    --    sp_rpt_IncomeStatementLiveWithDateSingleGrid. ──
    SELECT td.AccountCode,
           SUM(ISNULL(td.Debit, 0))  AS PeriodDebits,
           SUM(ISNULL(td.Credit, 0)) AS PeriodCredits
    INTO #CombinedActivity
    FROM dbo.TicketDetails AS td
    WHERE (@BranchCode IS NULL OR td.BranchCode = @BranchCode)
      AND td.TicketDate >= @DateFrom
      AND td.TicketDate <  DATEADD(DAY, 1, @DateTo)
    GROUP BY td.AccountCode;

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

-- ----------------------------------------------------------------
-- sp_rpt_IncomeStatementRealTimeAllBranchesPivot
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_IncomeStatementRealTimeAllBranchesPivot', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_IncomeStatementRealTimeAllBranchesPivot', 'sp_rpt_IncomeStatementRealTimeAllBranchesPivot_OLD_09302026150000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_IncomeStatementRealTimeAllBranchesPivot]
(
    @DateFrom            DATE,
    @DateTo              DATE
)
AS
/*
    REAL-TIME copy (2026-09-30) of sp_rpt_IncomeStatementLiveAllBranchesPivot: identical
    per-branch pivoted result set, but per-(branch, account) period activity comes straight
    from TicketDetails -- no GLSummary, no posting cutoff. @IncludeLiveActivity is gone.
    Callers: HOFormsDevEx/AccountingReportsFormV2.cs ("Income Statement (Real-Time)" ->
    All Branches/Pivot).
*/
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#CombinedActivity') IS NOT NULL DROP TABLE #CombinedActivity;
    IF OBJECT_ID('tempdb..#BranchActivity')   IS NOT NULL DROP TABLE #BranchActivity;
    IF OBJECT_ID('tempdb..#BranchSummary')    IS NOT NULL DROP TABLE #BranchSummary;
    IF OBJECT_ID('tempdb..#PivotSource')      IS NOT NULL DROP TABLE #PivotSource;

    -- ── REAL-TIME (2026-09-30): period activity per (branch, account) straight from
    --    TicketDetails -- no GLSummary, no posting cutoff. Everything below this block is
    --    unchanged from sp_rpt_IncomeStatementLiveAllBranchesPivot. ──
    SELECT td.BranchCode,
           td.AccountCode,
           SUM(ISNULL(td.Debit, 0))  AS PeriodDebits,
           SUM(ISNULL(td.Credit, 0)) AS PeriodCredits
    INTO #CombinedActivity
    FROM dbo.TicketDetails AS td
    WHERE td.TicketDate >= @DateFrom
      AND td.TicketDate <  DATEADD(DAY, 1, @DateTo)
    GROUP BY td.BranchCode, td.AccountCode;

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
    GROUP BY
    ca.BranchCode,
    b.BranchName,
    b.BranchCode;

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
        WITHIN GROUP (ORDER BY CASE WHEN BranchCode = '888' THEN 0 ELSE 1 END, ISNULL(TRY_CAST(BranchCode AS INT), 999999), BranchCode)  -- CHANGED 2026-09-25f: Head Office (888) first
    FROM OrderedBranches;

    ;WITH OrderedBranches AS (
        SELECT DISTINCT BranchCode, BranchName FROM #BranchActivity
        UNION
        SELECT DISTINCT BranchCode, BranchName FROM #BranchSummary
    )
    SELECT @BranchColsForSelect = STRING_AGG(
        'CAST(ISNULL(' + QUOTENAME(BranchName) + ',0) AS DECIMAL(19,2)) AS ' + QUOTENAME(BranchName), ','
    ) WITHIN GROUP (ORDER BY CASE WHEN BranchCode = '888' THEN 0 ELSE 1 END, ISNULL(TRY_CAST(BranchCode AS INT), 999999), BranchCode)  -- CHANGED 2026-09-25f: Head Office (888) first
    FROM OrderedBranches;

    ;WITH OrderedBranches AS (
        SELECT DISTINCT BranchCode, BranchName FROM #BranchActivity
        UNION
        SELECT DISTINCT BranchCode, BranchName FROM #BranchSummary
    )
    SELECT @GrandTotalExpr = STRING_AGG('ISNULL(' + QUOTENAME(BranchName) + ',0)', '+')
        WITHIN GROUP (ORDER BY CASE WHEN BranchCode = '888' THEN 0 ELSE 1 END, ISNULL(TRY_CAST(BranchCode AS INT), 999999), BranchCode)  -- CHANGED 2026-09-25f: Head Office (888) first
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

-- ----------------------------------------------------------------
-- sp_rpt_GLDetailTransactionRealTime
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_GLDetailTransactionRealTime', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_GLDetailTransactionRealTime', 'sp_rpt_GLDetailTransactionRealTime_OLD_09302026150000';
GO

/* ================================================================
   sp_rpt_GLDetailTransactionReport — ADD TicketNumber TO OUTPUT
   Root cause of the drill-down menu never finding a column: the SP
   already JOINs TicketMaster/TicketDetails and uses td.TicketNumber
   for sort ordering, but never actually exposes it in the final
   SELECT. Adding it here, carried as NULL through the synthetic
   Opening/Period/Ending rows (only real DETAIL rows have one, which
   is correct — those are the only rows a "same ticket" drill-down
   makes sense for anyway).

   Aliased as [TicketNumber] (no space, unlike the other bracketed
   display columns) so it matches the C# check verbatim with no
   further code changes needed there.
   ================================================================ */
CREATE PROCEDURE [dbo].[sp_rpt_GLDetailTransactionRealTime]
(
    @BranchCode          VARCHAR(5)  = NULL,
    @AccountCode         VARCHAR(20) = NULL,
    @DateFrom            DATE,
    @DateTo              DATE,
    @IncludeZeroActivity BIT         = 0
)
AS
/*
    REAL-TIME copy (2026-09-30) of sp_rpt_GLDetailTransactionReport: identical flat result
    set (Opening / detail legs / Period / Ending rows per account, TicketNumber on detail
    rows). Two changes, so Opening + period = Ending always ties to the Trial Balance:
      1. Opening = every TicketDetails leg before @DateFrom (was GLSummary's last EndingBalance).
      2. Detail legs LEFT JOIN TicketMaster (was INNER): the 2026-07-31 opening-balance ticket
         has a blank TicketMaster.BranchCode and some CONV-FINALIZE tickets post legs under a
         different branch than their master, so an inner 4-part join silently dropped them.
         Such legs show a NULL Reference and fall back to their own Particulars.
    Callers: HOFormsDevEx/AccountingReportsFormV2.cs ("GL Detail Transaction (Real-Time)").
*/
BEGIN
    SET NOCOUNT ON;

    -- ── Target account list ──────────────────────────────────────────
    IF OBJECT_ID('tempdb..#Accounts') IS NOT NULL DROP TABLE #Accounts;
    SELECT
        ROW_NUMBER() OVER (ORDER BY coa.AccountCode) AS AcctSeq,
        coa.AccountCode,
        coa.Description AS AccountDescription
    INTO #Accounts
    FROM ChartOfAccounts coa
    WHERE (@AccountCode IS NOT NULL AND coa.AccountCode = @AccountCode)
       OR (@AccountCode IS NULL AND coa.AccountType = 'D');

    -- ── REAL-TIME (2026-09-30): opening balance per account = every TicketDetails leg
    --    before @DateFrom (summed across branches if @BranchCode IS NULL) -- no GLSummary.
    --    Everything below this block is unchanged from sp_rpt_GLDetailTransactionReport. ──
    IF OBJECT_ID('tempdb..#Opening') IS NOT NULL DROP TABLE #Opening;
    SELECT
        a.AcctSeq,
        a.AccountCode,
        CAST(ISNULL(SUM(ISNULL(td.Debit, 0) - ISNULL(td.Credit, 0)), 0) AS DECIMAL(19,2)) AS OpeningBalance
    INTO #Opening
    FROM #Accounts a
    LEFT JOIN dbo.TicketDetails td
           ON td.AccountCode = a.AccountCode
          AND td.TicketDate  < @DateFrom
          AND (@BranchCode IS NULL OR td.BranchCode = @BranchCode)
    GROUP BY a.AcctSeq, a.AccountCode;

    -- ── Detail rows: one per TicketDetails leg in the period ────────── 
    IF OBJECT_ID('tempdb..#Detail') IS NOT NULL DROP TABLE #Detail;
    SELECT
        a.AcctSeq,
        a.AccountCode,
        a.AccountDescription,
        td.TicketDate                              AS TxnDate,
        tm.ReferenceKey                             AS Reference,
        isnull(td.Particulars,tm.Particulars)      AS TransDescription,
        NULLIF(td.Debit, 0)                        AS DebitAmt,
        NULLIF(td.Credit, 0)                       AS CreditAmt,
        CAST(NULL AS DECIMAL(19,2))                AS Balance,
        td.TicketNumber                            AS TicketNumber,   -- NEW
        ROW_NUMBER() OVER (
            PARTITION BY a.AcctSeq
            ORDER BY td.TicketDate, tm.ReferenceKey, td.TicketNumber
        )                                           AS DetailSeq
    INTO #Detail
    FROM #Accounts a
    INNER JOIN TicketDetails td ON td.AccountCode = a.AccountCode
    LEFT JOIN TicketMaster tm   -- REAL-TIME: keep legs whose master is keyed differently (see header)
        ON  tm.TicketDate          = td.TicketDate
        AND tm.SupplementaryNumber = td.SupplementaryNumber
        AND tm.BranchCode          = td.BranchCode
        AND tm.TicketNumber        = td.TicketNumber
    WHERE td.TicketDate >= @DateFrom
      AND td.TicketDate <  DATEADD(DAY, 1, @DateTo)   -- REAL-TIME: half-open (TicketDate is DATETIME)
      AND (@BranchCode IS NULL OR td.BranchCode = @BranchCode);

    -- ── Period totals per account ──────────────────────────────────────
    IF OBJECT_ID('tempdb..#PeriodTotals') IS NOT NULL DROP TABLE #PeriodTotals;
    SELECT
        AcctSeq,
        CAST(ISNULL(SUM(DebitAmt), 0)  AS DECIMAL(19,2)) AS TotalDebit,
        CAST(ISNULL(SUM(CreditAmt), 0) AS DECIMAL(19,2)) AS TotalCredit
    INTO #PeriodTotals
    FROM #Detail
    GROUP BY AcctSeq;

    -- ── Assemble the flat, ordered result set ──────────────────────────
    ;WITH Combined AS
    (
        -- OPENING BALANCE row — no ticket, NULL
        SELECT
            a.AcctSeq, 0 AS StageOrder, 0 AS DetailSeq,
            a.AccountCode, a.AccountDescription,
            @DateFrom                       AS TxnDate,
            CAST(NULL AS VARCHAR(150))      AS Reference,
            'Beginning Balance'             AS TransDescription,
            CAST(NULL AS DECIMAL(19,2))     AS DebitAmt,
            CAST(NULL AS DECIMAL(19,2))     AS CreditAmt,
            o.OpeningBalance                AS Balance,
            CAST(NULL AS VARCHAR(20))       AS TicketNumber   -- NEW
        FROM #Accounts a
        JOIN #Opening o ON o.AcctSeq = a.AcctSeq
        WHERE @IncludeZeroActivity = 1
           OR o.OpeningBalance <> 0
           OR EXISTS (SELECT 1 FROM #Detail d WHERE d.AcctSeq = a.AcctSeq)

        UNION ALL

        -- DETAIL rows — the real ticket number
        SELECT
            d.AcctSeq, 1 AS StageOrder, d.DetailSeq,
            d.AccountCode, d.AccountDescription,
            d.TxnDate, d.Reference, d.TransDescription,
            d.DebitAmt, d.CreditAmt, d.Balance,
            d.TicketNumber   -- NEW
        FROM #Detail d

        UNION ALL

        -- CURRENT PERIOD CHANGE row — no single ticket, NULL
        SELECT
            a.AcctSeq, 2 AS StageOrder, 0 AS DetailSeq,
            a.AccountCode, a.AccountDescription,
            CAST(NULL AS DATE)              AS TxnDate,
            CAST(NULL AS VARCHAR(150))      AS Reference,
            'Current Period Change'         AS TransDescription,
            pt.TotalDebit                   AS DebitAmt,
            pt.TotalCredit                  AS CreditAmt,
            CAST(pt.TotalDebit - pt.TotalCredit AS DECIMAL(19,2)) AS Balance,
            CAST(NULL AS VARCHAR(20))       AS TicketNumber   -- NEW
        FROM #Accounts a
        JOIN #PeriodTotals pt ON pt.AcctSeq = a.AcctSeq
        WHERE @IncludeZeroActivity = 1
           OR EXISTS (SELECT 1 FROM #Detail d WHERE d.AcctSeq = a.AcctSeq)

        UNION ALL

        -- ENDING BALANCE row — no single ticket, NULL
        SELECT
            a.AcctSeq, 3 AS StageOrder, 0 AS DetailSeq,
            CAST(NULL AS VARCHAR(20))       AS AccountCode,
            CAST(NULL AS VARCHAR(150))      AS AccountDescription,
            @DateTo                         AS TxnDate,
            CAST(NULL AS VARCHAR(150))      AS Reference,
            'Ending Balance'                AS TransDescription,
            CAST(NULL AS DECIMAL(19,2))     AS DebitAmt,
            CAST(NULL AS DECIMAL(19,2))     AS CreditAmt,
            CAST(o.OpeningBalance + ISNULL(pt.TotalDebit,0) - ISNULL(pt.TotalCredit,0) AS DECIMAL(19,2)) AS Balance,
            CAST(NULL AS VARCHAR(20))       AS TicketNumber   -- NEW
        FROM #Accounts a
        JOIN #Opening o ON o.AcctSeq = a.AcctSeq
        LEFT JOIN #PeriodTotals pt ON pt.AcctSeq = a.AcctSeq
        WHERE @IncludeZeroActivity = 1
           OR o.OpeningBalance <> 0
           OR EXISTS (SELECT 1 FROM #Detail d WHERE d.AcctSeq = a.AcctSeq)
    )
    SELECT
        AccountCode          AS [Account ID],
        AccountDescription   AS [Account Description],
        TxnDate              AS [Date],
        Reference            AS [Reference],
        TransDescription     AS [Trans Description],
        DebitAmt             AS [Debit Amt],
        CreditAmt            AS [Credit Amt],
        Balance              AS [Balance],
        TicketNumber         AS [TicketNumber]   -- NEW — no space, matches C# check verbatim
    FROM Combined
    ORDER BY AcctSeq, StageOrder, DetailSeq;

    DROP TABLE #Accounts;
    DROP TABLE #Opening;
    DROP TABLE #Detail;
    DROP TABLE #PeriodTotals;
END;

GO

-- ----------------------------------------------------------------
-- sp_rpt_BankReconciliationRealTime
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_BankReconciliationRealTime', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_BankReconciliationRealTime', 'sp_rpt_BankReconciliationRealTime_OLD_09302026150000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_BankReconciliationRealTime]
(
    @BranchCode  VARCHAR(5) = NULL,
    @AccountCode VARCHAR(20),
    @DateFrom    DATE,
    @DateTo      DATE
)
AS
/*
    REAL-TIME copy (2026-09-30) of sp_rpt_BankReconciliationWithDate: identical three
    result sets (account header, unresolved reconciling items, summary), with the GL side
    computed as the account's LEDGER (every TicketDetails leg, Nature-signed) instead of a
    GLSummary anchor + "posted-only" ticket movement. Two deliberate differences from the
    source proc, both found while testing on COREX001 (2026-09-30):
      1. No TicketMaster join. The 2026-07-31 opening-balance ticket (TicketNumber 1) has a
         blank TicketMaster.BranchCode, and some CONV-FINALIZE tickets post legs under a
         different branch than their master, so a 4-part master join silently drops them
         (on 101020111/888 the opening alone is 10,398,492.39).
      2. No POSTED/UPDATED status filter. Status 'REVERSED' is carried by the REVERSAL
         tickets themselves ("REVERSAL: OR-COLL ENTRY"), while the original stays POSTED --
         filtering them out counted every reversed collection but not its reversal.
    Cash receipts / disbursements use the same rule, so OtherGL stays an honest ~0.00 plug.
    Callers: HOFormsDevEx/AccountingReportsFormV2.cs ("Bank Reconciliation (Real-Time)").
*/
BEGIN
    SET NOCOUNT ON;

    -- ── SET 1: account header ──────────────────────────────────────────
    SELECT
         CAST(coa.AccountCode AS VARCHAR(20))        AS AccountCode
        ,CAST(coa.Description AS VARCHAR(256))       AS AccountDescription
        ,CAST(coa.Nature AS CHAR(1))                 AS Nature
        ,CAST(ISNULL(@BranchCode, 'ALL') AS VARCHAR(5)) AS BranchCode
        ,CAST(@DateFrom AS DATE)                     AS DateFrom
        ,CAST(@DateTo   AS DATE)                     AS DateTo
    FROM ChartOfAccounts coa
    WHERE coa.AccountCode = @AccountCode;

    DECLARE @Nature  CHAR(1);
    SELECT @Nature = Nature FROM ChartOfAccounts WHERE AccountCode = @AccountCode;
    DECLARE @SignMul INT = CASE WHEN @Nature = 'D' THEN 1 ELSE -1 END;

    DECLARE @BeginTarget DATE = DATEADD(DAY, -1, @DateFrom);
    DECLARE @EndTarget   DATE = @DateTo;

    -- ── REAL-TIME (2026-09-30): GL balances = the account's ledger balance, straight from
    --    TicketDetails (every leg, Nature-signed) -- no GLSummary anchor, no TicketMaster
    --    join, no status filter, i.e. exactly what the Trial Balance / GL Detail Ledger show.
    --    See the header for why the source proc's POSTED/UPDATED rule was dropped. ──
    DECLARE @BeginningGLBalance DECIMAL(19,2), @EndingGLBalance DECIMAL(19,2);
    SELECT
        @BeginningGLBalance = ISNULL(SUM(CASE WHEN td.TicketDate < DATEADD(DAY, 1, @BeginTarget)
                                              THEN @SignMul * (ISNULL(td.Debit, 0) - ISNULL(td.Credit, 0)) END), 0),
        @EndingGLBalance    = ISNULL(SUM(@SignMul * (ISNULL(td.Debit, 0) - ISNULL(td.Credit, 0))), 0)
    FROM TicketDetails td
    WHERE td.AccountCode = @AccountCode
      AND (@BranchCode IS NULL OR td.BranchCode = @BranchCode)
      AND td.TicketDate  < DATEADD(DAY, 1, @EndTarget);

    -- ── Cash receipts / disbursements: raw posted-only ledger movement for
    --    the period (Hard Rules #1 and #4) — UNCHANGED from the rejected
    --    version, already independent of GLSummary. ───────────────────────
    DECLARE @CashReceipts      DECIMAL(19,2) = 0.00;
    DECLARE @CashDisbursements DECIMAL(19,2) = 0.00;
    SELECT
        @CashReceipts      = ISNULL(SUM(td.Debit), 0),
        @CashDisbursements = ISNULL(SUM(td.Credit), 0)
    FROM TicketDetails td
    WHERE 1 = 1   -- REAL-TIME: every ledger line of the account (see header)
      AND td.AccountCode = @AccountCode
      AND (@BranchCode IS NULL OR td.BranchCode = @BranchCode)
      AND td.TicketDate >= @DateFrom
      AND td.TicketDate <  DATEADD(DAY, 1, @DateTo);

    -- GL-side "Other" — a COMPUTED PLUG, algebraically ~0.00 now that both GL
    -- balances are hybrid-computed from the same raw ledger CashReceipts/
    -- CashDisbursements already read (see header "OTHERGL IS NOW AN HONEST
    -- ZERO"). Kept as a formula, not hardcoded, so a genuine future
    -- inconsistency still surfaces visibly.
    DECLARE @OtherGL DECIMAL(19,2) =
        @EndingGLBalance - @BeginningGLBalance - @CashReceipts + @CashDisbursements;

    -- ── Bank-stated balance: SUM across matching BankReconHeader rows,
    --    bound to period end (unchanged logic from the pre-existing proc) ─
    DECLARE @BankStatementBal DECIMAL(18,2) = NULL;
    DECLARE @HeaderRowCount INT;
    SELECT @HeaderRowCount = COUNT(*), @BankStatementBal = SUM(brh.BankStatementBal)
    FROM BankReconHeader brh
    WHERE (@BranchCode IS NULL OR brh.BranchCode = @BranchCode)
      AND brh.AccountCode = @AccountCode
      AND brh.PeriodEnd   = @DateTo;
    IF @HeaderRowCount = 0 SET @BankStatementBal = NULL;

    -- ── SET 2: reconciling items (unresolved, up to period end @DateTo) ──
    SELECT
         bsr.ReconID
        ,bsr.BranchCode
        ,bsr.ItemType
        ,bsr.ReferenceNo
        ,bsr.ItemDate
        ,bsr.Payee
        ,bsr.Amount
        ,bsr.Remarks
        ,bsr.SourceModule
        ,bsr.SourceRef
        ,bsr.IsResolved
    FROM BankStatementRecon bsr
    WHERE (@BranchCode IS NULL OR bsr.BranchCode = @BranchCode)
      AND bsr.AccountCode = @AccountCode
      AND bsr.ItemDate   <= @DateTo
      AND bsr.IsResolved  = 0
    ORDER BY bsr.BranchCode, bsr.ItemType, bsr.ItemDate, bsr.ReferenceNo;

    -- ── SET 3: summary (period roll-forward shape, UNCHANGED from the
    --    rejected version except Beginning/EndingGLBalance now come from the
    --    hybrid calculation above instead of a direct GLSummary read) ──────
    DECLARE @TotalDIT DECIMAL(19,2), @TotalOC DECIMAL(19,2);
    SELECT
        @TotalDIT = ISNULL(SUM(CASE WHEN ItemType = 'DIT' THEN Amount ELSE 0 END), 0),
        @TotalOC  = ISNULL(SUM(CASE WHEN ItemType = 'OC'  THEN Amount ELSE 0 END), 0)
    FROM BankStatementRecon
    WHERE (@BranchCode IS NULL OR BranchCode = @BranchCode)
      AND AccountCode = @AccountCode
      AND ItemDate   <= @DateTo
      AND IsResolved  = 0;

    -- Bank-side "Other" — always 0.00 (unrelated to this fix; unchanged; see
    -- header — BankStatementRecon.ItemType has exactly two live values,
    -- DIT/OC, re-confirmed unchanged this pass).
    DECLARE @OtherBank DECIMAL(19,2) = 0.00;

    DECLARE @AdjustedBankBalance DECIMAL(19,2) =
        ISNULL(@BankStatementBal, 0) + @TotalDIT - @TotalOC + @OtherBank;

    SELECT
         CAST(@BeginningGLBalance AS DECIMAL(19,2))    AS BeginningGLBalance
        ,CAST(@CashReceipts AS DECIMAL(19,2))          AS CashReceipts
        ,CAST(@CashDisbursements AS DECIMAL(19,2))     AS CashDisbursements
        ,CAST(@OtherGL AS DECIMAL(19,2))               AS OtherGL
        ,CAST(@EndingGLBalance AS DECIMAL(19,2))       AS EndingGLBalance
        ,CAST(@BankStatementBal AS DECIMAL(18,2))      AS BankStatementBalance
        ,CAST(@TotalDIT AS DECIMAL(19,2))              AS TotalDepositsInTransit
        ,CAST(@TotalOC  AS DECIMAL(19,2))              AS TotalOutstandingChecks
        ,CAST(@OtherBank AS DECIMAL(19,2))             AS OtherBank
        ,CASE WHEN @BankStatementBal IS NULL THEN NULL
              ELSE CAST(@AdjustedBankBalance AS DECIMAL(19,2)) END AS AdjustedBankBalance
        ,CASE WHEN @BankStatementBal IS NULL THEN NULL
              ELSE CAST(@EndingGLBalance - @AdjustedBankBalance AS DECIMAL(19,2)) END AS UnreconciledDifference
        ,CASE WHEN @BankStatementBal IS NULL THEN CAST(0 AS BIT)
              WHEN ABS(@EndingGLBalance - @AdjustedBankBalance) < 0.01 THEN CAST(1 AS BIT)
              ELSE CAST(0 AS BIT) END AS IsReconciled
        ,CAST(ISNULL(@BranchCode, 'ALL') AS VARCHAR(5)) AS BranchCode;
END;

GO

-- ----------------------------------------------------------------
-- sp_rpt_GLDetailLedgerRealTime
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_GLDetailLedgerRealTime', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_GLDetailLedgerRealTime', 'sp_rpt_GLDetailLedgerRealTime_OLD_09302026150000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_GLDetailLedgerRealTime]
    @BranchCode  VARCHAR(5) = NULL,
    @AccountCode VARCHAR(20),
    @DateFrom    DATE,
    @DateTo      DATE
AS
/*
    Same four result sets as sp_rpt_GLDetailLedgerWithDate (header, opening row,
    one row per day with a running balance, period summary), computed straight
    from TicketDetails instead of GLSummary:
      opening = SUM(Debit - Credit) of every leg before @DateFrom;
      one row per TicketDate with activity (Credits carried NEGATIVE internally,
      as GLSummary stored them, and shown positive -- same as the source proc).
    Callers: HOFormsDevEx/AccountingReportsFormV2.cs ("GL Detail Ledger (Real-Time)").
*/
BEGIN
    SET NOCOUNT ON;

    -- SET 1: Account header metadata
    SELECT
         coa.AccountCode
        ,coa.Description        AS AccountDescription
        ,coa.AccountType
        ,coa.Nature
        ,coa.YearEndIndicator
        ,@DateFrom              AS PeriodFrom
        ,@DateTo                AS PeriodTo
        ,ISNULL(@BranchCode, 'ALL') AS BranchCode
    FROM ChartOfAccounts coa
    WHERE coa.AccountCode = @AccountCode;

    DECLARE @OpeningBalance DECIMAL(19,2) =
        (SELECT ISNULL(SUM(ISNULL(td.Debit, 0) - ISNULL(td.Credit, 0)), 0)
         FROM dbo.TicketDetails td
         WHERE (@BranchCode IS NULL OR td.BranchCode = @BranchCode)
           AND td.AccountCode = @AccountCode
           AND td.TicketDate  < @DateFrom);

    -- SET 2: Opening balance row
    SELECT
         CAST(@DateFrom AS DATE)        AS PostingDate
        ,0                              AS SupplementaryNumber
        ,ISNULL(@BranchCode, 'ALL')     AS BranchCode
        ,@AccountCode                   AS AccountCode
        ,'OPENING BALANCE'              AS Particulars
        ,@OpeningBalance                AS BeginningBalance
        ,CAST(0 AS DECIMAL(19,2))       AS Debits
        ,CAST(0 AS DECIMAL(19,2))       AS Credits
        ,@OpeningBalance                AS EndingBalance
        ,CAST(NULL AS VARCHAR(MAX))     AS TicketNumbers
        ,'OPENING'                      AS RowType;

    -- SET 3: one row per day with activity, running balance
    ;WITH DailyActivity AS
    (
        SELECT
             CAST(td.TicketDate AS DATE)     AS PostingDate
            ,SUM(ISNULL(td.Debit, 0))        AS Debits
            ,-SUM(ISNULL(td.Credit, 0))      AS Credits      -- negative, as GLSummary stored it
        FROM dbo.TicketDetails td
        WHERE (@BranchCode IS NULL OR td.BranchCode = @BranchCode)
          AND td.AccountCode = @AccountCode
          AND td.TicketDate >= @DateFrom
          AND td.TicketDate <  DATEADD(DAY, 1, @DateTo)
        GROUP BY CAST(td.TicketDate AS DATE)
    ),
    RunningBalance AS
    (
        SELECT
             da.PostingDate, da.Debits, da.Credits
            ,@OpeningBalance + SUM(da.Debits + da.Credits) OVER (
                ORDER BY da.PostingDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
             ) AS EndingBalance
            ,@OpeningBalance + ISNULL(SUM(da.Debits + da.Credits) OVER (
                ORDER BY da.PostingDate ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
             ), 0) AS BeginningBalance
        FROM DailyActivity da
    )
    SELECT
         rb.PostingDate
        ,0                              AS SupplementaryNumber
        ,ISNULL(@BranchCode, 'ALL')     AS BranchCode
        ,@AccountCode                   AS AccountCode
        ,tm_agg.Particulars
        ,CAST(rb.BeginningBalance AS DECIMAL(19,2)) AS BeginningBalance
        ,CAST(rb.Debits           AS DECIMAL(19,2)) AS Debits
        ,CAST(ABS(rb.Credits)     AS DECIMAL(19,2)) AS Credits
        ,CAST(rb.EndingBalance    AS DECIMAL(19,2)) AS EndingBalance
        ,tm_agg.TicketNumbers
        ,'DETAIL'                   AS RowType
    FROM RunningBalance rb
    OUTER APPLY
    (
        SELECT
             LEFT(MIN(x.Particulars), 200)                              AS Particulars
            ,STRING_AGG(CAST(x.TicketNumber AS VARCHAR(MAX)), ', ')     AS TicketNumbers
        FROM
        (
            SELECT DISTINCT
                 CONVERT(VARCHAR(50), td.TicketNumber) AS TicketNumber
                ,COALESCE(tm.Particulars, td.Particulars) AS Particulars
            FROM TicketDetails td
            -- LEFT: the opening-balance ticket / some CONV-FINALIZE legs have a master
            -- keyed under a different branch -- keep their day labels.
            LEFT JOIN TicketMaster tm
                ON  tm.TicketDate          = td.TicketDate
                AND tm.SupplementaryNumber = td.SupplementaryNumber
                AND tm.BranchCode          = td.BranchCode
                AND tm.TicketNumber        = td.TicketNumber
            WHERE (@BranchCode IS NULL OR td.BranchCode = @BranchCode)
              AND td.AccountCode         = @AccountCode
              AND td.TicketDate          = rb.PostingDate
        ) x
    ) tm_agg
    ORDER BY rb.PostingDate;

    -- SET 4: Period summary
    SELECT
         CAST(ISNULL(SUM(ISNULL(td.Debit, 0)),  0) AS DECIMAL(19,2)) AS TotalDebits
        ,CAST(ISNULL(SUM(ISNULL(td.Credit, 0)), 0) AS DECIMAL(19,2)) AS TotalCredits
        ,@OpeningBalance                                              AS OpeningBalance
        ,CAST(@OpeningBalance
              + ISNULL(SUM(ISNULL(td.Debit, 0)),  0)
              - ISNULL(SUM(ISNULL(td.Credit, 0)), 0)
              AS DECIMAL(19,2))              AS ClosingBalance
        ,@DateFrom AS PeriodFrom
        ,@DateTo   AS PeriodTo
    FROM dbo.TicketDetails td
    WHERE (@BranchCode IS NULL OR td.BranchCode = @BranchCode)
      AND td.AccountCode = @AccountCode
      AND td.TicketDate >= @DateFrom
      AND td.TicketDate <  DATEADD(DAY, 1, @DateTo);
END;
GO

-- ----------------------------------------------------------------
-- sp_rpt_ConsolidatedGLRealTime
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_ConsolidatedGLRealTime', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_ConsolidatedGLRealTime', 'sp_rpt_ConsolidatedGLRealTime_OLD_09302026150000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_ConsolidatedGLRealTime]
    @AsOfDate   DATE     = NULL,
    @PeriodFrom DATE     = NULL,
    @PeriodTo   DATE     = NULL,
    @ReportType VARCHAR(5) = 'TB'   -- 'TB' = as-of snapshot, 'IS' = period range
AS
/*
    Same result sets as sp_rpt_ConsolidatedGLWithDate (TB mode: line items,
    balance check, intercompany check; IS mode: activity, summary), all
    branches, computed straight from TicketDetails instead of GLSummary.
    Callers: HOFormsDevEx/AccountingReportsFormV2.cs ("Consolidated GL (Real-Time)").
*/
BEGIN
    SET NOCOUNT ON;

    IF @ReportType = 'TB'
    BEGIN
        -- per (branch, account) balance, inception to @AsOfDate
        SELECT td.BranchCode, td.AccountCode,
               SUM(ISNULL(td.Debit, 0)) - SUM(ISNULL(td.Credit, 0)) AS EndingBalance
        INTO #BranchBal
        FROM dbo.TicketDetails td
        WHERE td.TicketDate < DATEADD(DAY, 1, @AsOfDate)
        GROUP BY td.BranchCode, td.AccountCode;

        -- SET 1: Line items
        ;WITH AccountBalances AS
        (
            SELECT
                 coa.AccountCode
                ,coa.Description        AS AccountDescription
                ,coa.LevelNumber
                ,coa.Nature
                ,coa.YearEndIndicator
                ,CASE WHEN coa.DueToFromIndicator IS NOT NULL THEN 1 ELSE 0 END AS IsIntercompany
                ,SUM(b.EndingBalance)   AS ConsolidatedBalance
            FROM #BranchBal b
            INNER JOIN ChartOfAccounts coa ON coa.AccountCode = b.AccountCode
            WHERE coa.AccountType = 'D'
            GROUP BY
                 coa.AccountCode, coa.Description, coa.LevelNumber,
                 coa.Nature, coa.YearEndIndicator, coa.DueToFromIndicator
            HAVING SUM(b.EndingBalance) <> 0
        )
        SELECT
             ab.AccountCode
            ,ab.AccountDescription
            ,ab.LevelNumber
            ,ab.Nature
            ,ab.YearEndIndicator
            ,ab.IsIntercompany
            ,CAST(ab.ConsolidatedBalance AS DECIMAL(19,2))   AS ConsolidatedBalance
            ,CAST(CASE WHEN ab.ConsolidatedBalance > 0
                       THEN ab.ConsolidatedBalance ELSE 0 END AS DECIMAL(19,2)) AS TBDebit
            ,CAST(CASE WHEN ab.ConsolidatedBalance < 0
                       THEN ABS(ab.ConsolidatedBalance) ELSE 0 END AS DECIMAL(19,2)) AS TBCredit
            ,@AsOfDate AS AsOfDate
        FROM AccountBalances ab
        ORDER BY ab.AccountCode;

        -- SET 2: Balance check totals
        ;WITH AccountBalances AS
        (
            SELECT b.AccountCode, SUM(b.EndingBalance) AS ConsolidatedBalance
            FROM #BranchBal b
            INNER JOIN ChartOfAccounts coa ON coa.AccountCode = b.AccountCode
            WHERE coa.AccountType = 'D'
            GROUP BY b.AccountCode
        )
        SELECT
             CAST(SUM(CASE WHEN ConsolidatedBalance > 0
                           THEN ConsolidatedBalance ELSE 0 END) AS DECIMAL(19,2)) AS TotalDebit
            ,CAST(SUM(CASE WHEN ConsolidatedBalance < 0
                           THEN ABS(ConsolidatedBalance) ELSE 0 END) AS DECIMAL(19,2)) AS TotalCredit
            ,CAST(SUM(CASE WHEN ConsolidatedBalance > 0 THEN  ConsolidatedBalance ELSE 0 END)
                - SUM(CASE WHEN ConsolidatedBalance < 0 THEN  ABS(ConsolidatedBalance) ELSE 0 END)
                  AS DECIMAL(19,2)) AS Difference
            ,@AsOfDate AS AsOfDate
        FROM AccountBalances;

        -- SET 3: Intercompany check, per branch
        SELECT
             coa.DueToFromIndicator   AS ICType
            ,coa.AccountCode
            ,coa.Description          AS AccountDescription
            ,b.BranchCode
            ,CAST(SUM(b.EndingBalance) AS DECIMAL(19,2)) AS Balance
        FROM #BranchBal b
        INNER JOIN ChartOfAccounts coa ON coa.AccountCode = b.AccountCode
        WHERE coa.DueToFromIndicator IS NOT NULL
        GROUP BY coa.DueToFromIndicator, coa.AccountCode, coa.Description, b.BranchCode
        ORDER BY coa.DueToFromIndicator, coa.AccountCode, b.BranchCode;
    END
    ELSE  -- IS MODE: period range, all branches
    BEGIN
        SELECT td.AccountCode,
               SUM(ISNULL(td.Debit, 0))  AS Debits,
               SUM(ISNULL(td.Credit, 0)) AS Credits
        INTO #Period
        FROM dbo.TicketDetails td
        WHERE td.TicketDate >= @PeriodFrom
          AND td.TicketDate <  DATEADD(DAY, 1, @PeriodTo)
        GROUP BY td.AccountCode;

        -- SET 1: IS activity
        SELECT
             coa.AccountCode
            ,coa.Description            AS AccountDescription
            ,coa.LevelNumber
            ,coa.Nature
            ,coa.YearEndIndicator
            ,CASE WHEN coa.DueToFromIndicator IS NOT NULL THEN 1 ELSE 0 END AS IsIntercompany
            ,CAST(SUM(p.Debits)   AS DECIMAL(19,2)) AS ConsolidatedDebits
            ,CAST(SUM(p.Credits)  AS DECIMAL(19,2)) AS ConsolidatedCredits
            ,CAST(CASE coa.Nature
                WHEN 'C' THEN SUM(p.Credits) - SUM(p.Debits)
                WHEN 'D' THEN SUM(p.Debits)  - SUM(p.Credits)
             END AS DECIMAL(19,2))      AS NetAmount
            ,@PeriodFrom AS PeriodFrom
            ,@PeriodTo   AS PeriodTo
        FROM #Period p
        INNER JOIN ChartOfAccounts coa ON coa.AccountCode = p.AccountCode
        WHERE coa.AccountType      = 'D'
          AND coa.YearEndIndicator = 'IS'
        GROUP BY
             coa.AccountCode, coa.Description, coa.LevelNumber,
             coa.Nature, coa.YearEndIndicator, coa.DueToFromIndicator
        HAVING SUM(p.Debits) <> 0 OR SUM(p.Credits) <> 0
        ORDER BY coa.AccountCode;

        -- SET 2: IS summary totals
        SELECT
             CAST(SUM(CASE WHEN LEFT(coa.AccountCode,1)='4'
                           THEN p.Credits - p.Debits ELSE 0 END) AS DECIMAL(19,2)) AS TotalRevenue
            ,CAST(SUM(CASE WHEN LEFT(coa.AccountCode,1)='5'
                           THEN p.Debits - p.Credits ELSE 0 END) AS DECIMAL(19,2)) AS TotalCOGS
            ,CAST(SUM(CASE WHEN LEFT(coa.AccountCode,1)='6'
                           THEN p.Debits - p.Credits ELSE 0 END) AS DECIMAL(19,2)) AS TotalExpenses
            ,CAST(SUM(CASE WHEN LEFT(coa.AccountCode,1)='4'
                           THEN p.Credits - p.Debits
                           WHEN LEFT(coa.AccountCode,1) IN ('5','6')
                           THEN -(p.Debits - p.Credits)
                           ELSE 0 END) AS DECIMAL(19,2)) AS NetIncome
            ,@PeriodFrom AS PeriodFrom
            ,@PeriodTo   AS PeriodTo
        FROM #Period p
        INNER JOIN ChartOfAccounts coa ON coa.AccountCode = p.AccountCode
        WHERE coa.AccountType      = 'D'
          AND coa.YearEndIndicator = 'IS';
    END;
END;
GO
