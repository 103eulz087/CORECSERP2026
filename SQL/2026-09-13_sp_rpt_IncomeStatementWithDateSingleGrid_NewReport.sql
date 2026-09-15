-- New, fully isolated report proc: Income Statement, single-grid presentation.
-- Zero existing objects modified -- net-new SP for HOFormsDevEx/AccountingReportsFormV2.cs,
-- same idea as sp_rpt_BalanceSheetPerBranchInventorySingleGrid: fold the line items AND the
-- section/subsection/grand totals (previously a separate SET 2 summary grid) into ONE result
-- set via a RowType discriminator, so the report renders as one grid instead of a detail grid
-- + summary grid pair.
--
-- Source logic is copied verbatim from the currently-live dbo.sp_rpt_IncomeStatementWithDate
-- (single branch only, no all-branches/zero-activity options -- this base SP doesn't have
-- those; matching its actual current signature) and reshaped into ONE result set:
--   'DETAIL'               -- one row per posting (ChartOfAccounts.AccountType='D',
--                              YearEndIndicator='IS') account with period activity.
--   'SUBSECTION_SUBTOTAL'  -- one row per ExpenseSubSection (3A/3B/3C/3D), Operating
--                              Expenses only -- the one level of nesting Balance Sheet
--                              doesn't have.
--   'SECTION_SUBTOTAL'     -- one row per ISSection (TOTAL REVENUE / TOTAL COST OF GOODS
--                              SOLD / TOTAL OPERATING EXPENSES).
--   'GRANDTOTAL'           -- GROSS PROFIT, OPERATING INCOME, OTHER INCOME, NET INCOME --
--                              exactly the same formulas as the live SP's SET 2, verified
--                              algebraically: GrossProfit = TotalRevenue - TotalCOGS;
--                              OperatingIncome = (TotalRevenue - OtherIncome) - TotalCOGS
--                              - TotalExpenses; NetIncome = TotalRevenue - TotalCOGS -
--                              TotalExpenses (= OperatingIncome + OtherIncome).
--
-- IMPORTANT sign nuance (verified algebraically against the live SET 2 math, not guessed --
-- and re-verified by a ledger-integrity review that caught the first version of this file only
-- generalizing the fix to COGS): DETAIL.Amount is nature-based (Nature='C': Credit-Debit;
-- Nature='D': Debit-Credit) -- correct for per-row DISPLAY (every account shows its own natural-
-- balance sign), but the live SP's SET 2 totals are NOT nature-based at all: TotalRevenue is
-- unconditionally SUM(Credit-Debit) for every '4' account regardless of that account's own
-- Nature, TotalExpenses is unconditionally SUM(Debit-Credit) for every '6' account, and
-- TotalCOGS's own Nature-branched formula (D: +Debit-Credit, C: -(Credit-Debit)) algebraically
-- collapses to the SAME SUM(Debit-Credit) either way. So a section subtotal derived from
-- DETAIL.Amount (nature-based) would silently diverge from the original SET 2 figure for ANY
-- contra-nature account in ANY section (a Nature='D' account under '4-Revenue', a Nature='C'
-- account under '6-Operating Expenses' -- not just the already-known contra-COGS case) --
-- exactly the class of bug the original per-section IsContraCOGS-only flip would NOT have
-- caught. Fix: #SectionTotals and #SubsectionTotals below are computed directly from
-- PeriodDebits/PeriodCredits (the same nature-agnostic formula the live SP's SET 2 uses), not
-- from DETAIL.Amount -- guaranteed to tie out regardless of what Nature values exist in the
-- COA. IsContraCOGS is kept as a DETAIL-row-only informational flag (so the grid can still show
-- which rows are contra-COGS), but no rollup in this proc depends on it.
--
-- Row order: within Revenue/COGS, DETAIL rows (by AccountCode) then that section's
-- SECTION_SUBTOTAL. Within Operating Expenses, DETAIL rows grouped by ExpenseSubSection (by
-- AccountCode within each), each subsection's SUBSECTION_SUBTOTAL right after its own group,
-- then the section's own SECTION_SUBTOTAL last. GRANDTOTAL rows last of all, in presentation
-- order (Gross Profit sits between COGS and Operating Expenses; Operating Income/Other
-- Income/Net Income sit after Operating Expenses) -- achieved via the ISSection/SortRank
-- values below, NOT via any change to what's actually displayed (ISSection/ExpenseSubSection/
-- RowType are internal sort/grouping keys, hidden columns in the grid, same as BSSection/
-- RowType are for the Balance Sheet single-grid version).
--
-- Callers: HOFormsDevEx/AccountingReportsFormV2.cs, "Income Statement".
IF OBJECT_ID('dbo.sp_rpt_IncomeStatementWithDateSingleGrid', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_IncomeStatementWithDateSingleGrid', 'sp_rpt_IncomeStatementWithDateSingleGrid_OLD_09132026200000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_IncomeStatementWithDateSingleGrid]
    @BranchCode  VARCHAR(5),
    @DateFrom    DATE,
    @DateTo      DATE
AS
/*
    Returns: ONE result set -- posting IS account line items, per-ExpenseSubSection and
    per-ISSection subtotals, and P&L grand totals, discriminated by RowType ('DETAIL'/
    'SUBSECTION_SUBTOTAL'/'SECTION_SUBTOTAL'/'GRANDTOTAL'). See header comment above for the
    full row-order/shape contract and the contra-COGS sign nuance; identical underlying figures
    to sp_rpt_IncomeStatementWithDate's two result sets, just reshaped for a single-grid
    presentation.
    Assumes: same as sp_rpt_IncomeStatementWithDate -- GLSummary carries period Debits/Credits
    per (BranchCode, AccountCode, PostingDate); ChartOfAccounts.AccountType='D' marks postable
    detail accounts; YearEndIndicator='IS' separates income-statement from balance-sheet
    accounts; AccountCode's leading digit (4/5/6) determines Revenue/COGS/Operating Expenses.
    Callers: HOFormsDevEx/AccountingReportsFormV2.cs ("Income Statement").
*/
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#DetailRows') IS NOT NULL DROP TABLE #DetailRows;
    IF OBJECT_ID('tempdb..#SectionTotals') IS NOT NULL DROP TABLE #SectionTotals;
    IF OBJECT_ID('tempdb..#SubsectionTotals') IS NOT NULL DROP TABLE #SubsectionTotals;

    ;WITH ISActivity AS
    (
        SELECT
             gs.AccountCode
            ,SUM(gs.Debits)       AS PeriodDebits
            ,SUM(ABS(gs.Credits)) AS PeriodCredits
        FROM GLSummary gs
        WHERE gs.BranchCode  = @BranchCode
          AND gs.PostingDate BETWEEN @DateFrom AND @DateTo
        GROUP BY gs.AccountCode
    )
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
        ,CAST(ia.PeriodDebits  AS DECIMAL(19,2)) AS PeriodDebits
        ,CAST(ia.PeriodCredits AS DECIMAL(19,2)) AS PeriodCredits
        ,CAST(
            CASE coa.Nature
                WHEN 'C' THEN ia.PeriodCredits - ia.PeriodDebits
                WHEN 'D' THEN ia.PeriodDebits  - ia.PeriodCredits
            END
         AS DECIMAL(19,2)) AS Amount
        ,CASE WHEN LEFT(coa.AccountCode,1) = '5' AND coa.Nature = 'C' THEN 1 ELSE 0 END AS IsContraCOGS
    INTO #DetailRows
    FROM ISActivity ia
    INNER JOIN ChartOfAccounts coa ON coa.AccountCode = ia.AccountCode
    WHERE coa.AccountType      = 'D'
      AND coa.YearEndIndicator = 'IS'
      AND (ia.PeriodDebits <> 0 OR ia.PeriodCredits <> 0);

    -- Same fail-loudly guard as the Balance Sheet single-grid SP: an unclassified account
    -- would silently drop out of every total AND sort in the wrong place ('9-Other' sorts
    -- after '4-Operating Expenses' but the DETAIL rows would have no matching subtotal).
    IF EXISTS (SELECT 1 FROM #DetailRows WHERE ISSection = '9-Other')
    BEGIN
        THROW 50000, 'One or more posting IS accounts do not map to a known Income Statement section (AccountCode does not start with 4/5/6). Fix the account''s classification before running this report.', 1;
    END;

    -- Same "fail loudly" philosophy for an unclassified Nature: the CASE above has no ELSE, so
    -- Nature NOT IN ('C','D') would silently render Amount = NULL on the DETAIL row (display-
    -- only -- section totals below no longer derive from Amount, so this can't skew a total,
    -- but a blank Amount is still a real display defect worth catching at the source).
    IF EXISTS (SELECT 1 FROM ChartOfAccounts WHERE AccountType = 'D' AND YearEndIndicator = 'IS' AND Nature NOT IN ('C','D'))
    BEGIN
        THROW 50000, 'One or more posting IS accounts have an unrecognized Nature (expected ''C'' or ''D''). Fix the account''s Nature before running this report.', 1;
    END;

    -- Section totals -- computed directly from PeriodDebits/PeriodCredits, NOT from the
    -- nature-based DETAIL.Amount column, so this ties out to the live SP's SET 2 regardless of
    -- what Nature value any given account carries (see header comment). Revenue = Credit-Debit
    -- per '4' account; Cost of Goods Sold and Operating Expenses = Debit-Credit per '5'/'6'
    -- account -- all three unconditional on Nature, exactly like the original SET 2 formulas.
    SELECT
         ISSection
        ,CAST(SUM(CASE WHEN ISSection = '1-Revenue' THEN PeriodCredits - PeriodDebits
                        ELSE PeriodDebits - PeriodCredits END) AS DECIMAL(19,2)) AS SectionTotal
    INTO #SectionTotals
    FROM #DetailRows
    GROUP BY ISSection;

    -- Same nature-agnostic Debit-Credit formula per subsection, so subsections sum exactly to
    -- their section's own SECTION_SUBTOTAL above.
    SELECT
         ExpenseSubSection
        ,CAST(SUM(PeriodDebits - PeriodCredits) AS DECIMAL(19,2)) AS SubsectionTotal
    INTO #SubsectionTotals
    FROM #DetailRows
    WHERE ExpenseSubSection IS NOT NULL
    GROUP BY ExpenseSubSection;

    ;WITH Totals AS
    (
        SELECT
             ISNULL((SELECT SectionTotal FROM #SectionTotals WHERE ISSection = '1-Revenue'), 0)            AS TotalRevenue
            ,ISNULL((SELECT SectionTotal FROM #SectionTotals WHERE ISSection = '2-Cost of Goods Sold'), 0) AS TotalCOGS
            ,ISNULL((SELECT SectionTotal FROM #SectionTotals WHERE ISSection = '4-Operating Expenses'), 0) AS TotalExpenses
            -- Nature-agnostic here too, matching the live SP's own unconditional Credit-Debit
            -- OtherIncome formula -- not derived from DETAIL.Amount.
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

        -- SUBSTRING starts at position 4 -- ExpenseSubSection's own sort-prefix is 3 chars
        -- ('3A-','3B-','3C-','3D-'), unlike ISSection's 2-char prefix ('1-','2-','4-').
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

        -- ExpenseSubSection = 'ZZZZ' sentinel (sorts after '3A'.."3D'-prefixed real subsection
        -- codes) so this section-level total renders after every subsection's own subtotal,
        -- not interleaved via NULL-ordering ambiguity.
        SELECT 'SECTION_SUBTOTAL', '4-Operating Expenses', 'ZZZZ', NULL, 'TOTAL OPERATING EXPENSES', NULL, NULL, SectionTotal, NULL, 2
        FROM #SectionTotals WHERE ISSection = '4-Operating Expenses'

        UNION ALL

        -- Each GRANDTOTAL-tier row gets its own ISSection/SortRank (not a shared value) for
        -- the same reason as the Balance Sheet single-grid SP: ties on every ORDER BY column
        -- have no guaranteed relative order in SQL Server. '3-Gross Profit' deliberately sorts
        -- between COGS ('2-...') and Operating Expenses ('4-...'), matching standard P&L
        -- presentation order; '5-Grand Totals' holds Operating Income/Other Income/Net Income.
        SELECT 'GRANDTOTAL', '3-Gross Profit', NULL, NULL, 'GROSS PROFIT', NULL, NULL, GrossProfit, NULL, 0 FROM GrandTotals
        UNION ALL
        SELECT 'GRANDTOTAL', '5-Grand Totals', NULL, NULL, 'OPERATING INCOME', NULL, NULL, OperatingIncome, NULL, 0 FROM GrandTotals
        UNION ALL
        SELECT 'GRANDTOTAL', '5-Grand Totals', NULL, NULL, 'OTHER INCOME', NULL, NULL, OtherIncome, NULL, 1 FROM GrandTotals
        UNION ALL
        SELECT 'GRANDTOTAL', '5-Grand Totals', NULL, NULL, 'NET INCOME', NULL, NULL, NetIncome, NULL, 2 FROM GrandTotals
    ) x
    ORDER BY ISSection, ISNULL(ExpenseSubSection, ''), SortRank, AccountCode;

    DROP TABLE IF EXISTS #DetailRows;
    DROP TABLE IF EXISTS #SectionTotals;
    DROP TABLE IF EXISTS #SubsectionTotals;
END;
GO
