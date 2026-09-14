-- New, fully isolated report proc: Balance Sheet (Real-Time), single-grid presentation.
-- Zero existing objects modified -- net-new SP, sibling to
-- sp_rpt_BalanceSheetPerBranchInventorySingleGrid (see
-- SQL/2026-09-11_sp_rpt_BalanceSheetPerBranchInventorySingleGrid_NewReport.sql for the
-- original single-grid design this mirrors) and to
-- sp_rpt_IncomeStatementLiveWithDateSingleGrid (same "make the real-time variant match the
-- already-merged non-real-time one" pattern, done 2026-09-13 for Income Statement).
--
-- Source logic is the current live dbo.sp_rpt_BalanceSheetLiveWithDate (both of its result
-- sets, SET1 line items + SET2 section/grand totals -- see
-- SQL/2026-09-09_sp_rpt_BalanceSheetLiveWithDate_AllBranchesAndZeroAccounts.sql, its current
-- definition), combined into a single result set via a RowType discriminator, same scheme as
-- the non-real-time single-grid SP:
--   'DETAIL'      -- one row per posting BS account (+ the computed CURRENT_EARNINGS row),
--                     verbatim hybrid posted+live logic (BranchScope/GLMaxDate/BranchCutoff/
--                     LatestPerBranch/PostedPerBranch/LiveActivity/BranchAccountCombined),
--                     all-branches consolidation (@BranchCode=NULL), and @IncludeZeroActivity
--                     toggle -- all carried over unchanged.
--   'SUBTOTAL'    -- one row per BSSection, including the live SP's own zero-fill guard (the
--                     5 canonical sections always render, even at 0, so a dormant/new branch
--                     doesn't make the whole SET 2 vanish -- a real bug this SP already fixed
--                     once, preserved here rather than dropped for "simplicity").
--   'GRANDTOTAL'  / 'GRANDTOTAL_DIFF' -- Total Assets / Total Liabilities & Equity / Difference,
--                     same as the non-real-time single-grid SP (a THROW guard for an unmapped
--                     BSSection is ALSO added here, since the live SP's SET 2 never had one --
--                     new code, not altering the existing 2-grid SP, so free to add it).
--
-- Deliberately NOT carried over: the non-real-time single-grid SP's per-branch Petty Cash
-- Fund/Inventory (VAT/VAT-Exempt) breakout -- the live 2-grid SP never had that either (its own
-- Description already says so), and adding it wasn't asked for here; this is a "merge into one
-- grid" change, not a "add new breakout" change.
--
-- Callers: HOFormsDevEx/AccountingReportsFormV2.cs, "Balance Sheet (Real-Time)".
IF OBJECT_ID('dbo.sp_rpt_BalanceSheetLiveWithDateSingleGrid', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_BalanceSheetLiveWithDateSingleGrid', 'sp_rpt_BalanceSheetLiveWithDateSingleGrid_OLD_09132026220000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_BalanceSheetLiveWithDateSingleGrid]
    @BranchCode          VARCHAR(5) = NULL,
    @AsOfDate            DATE,
    @IncludeLiveActivity BIT        = 1,
    @IncludeZeroActivity BIT        = 0
AS
/*
    Returns: ONE result set -- posting BS account line items, per-BSSection subtotals, and
    grand totals/balance-check, discriminated by RowType ('DETAIL'/'SUBTOTAL'/'GRANDTOTAL'/
    'GRANDTOTAL_DIFF'). Identical underlying figures to sp_rpt_BalanceSheetLiveWithDate's two
    result sets (hybrid posted+live activity, all-branches consolidation, zero-activity
    toggle), just reshaped for a single-grid presentation -- see that SP and
    sp_rpt_BalanceSheetPerBranchInventorySingleGrid for the two halves of this design.
    Assumes: same as sp_rpt_BalanceSheetLiveWithDate.
    Callers: HOFormsDevEx/AccountingReportsFormV2.cs ("Balance Sheet (Real-Time)").
*/
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#LatestPosting') IS NOT NULL DROP TABLE #LatestPosting;
    IF OBJECT_ID('tempdb..#DetailRows')    IS NOT NULL DROP TABLE #DetailRows;
    IF OBJECT_ID('tempdb..#SectionTotals') IS NOT NULL DROP TABLE #SectionTotals;

    -- ── Hybrid posted+live ending balance per account, built ONCE -- verbatim from
    --    sp_rpt_BalanceSheetLiveWithDate. ──
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
    LatestPerBranch AS
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
    PostedPerBranch AS
    (
        SELECT BranchCode, AccountCode, EndingBalance
        FROM LatestPerBranch
        WHERE rn = 1
    ),
    LiveActivity AS
    (
        SELECT
             td.BranchCode
            ,td.AccountCode
            ,SUM(ISNULL(td.Debit,0)) - SUM(ISNULL(td.Credit,0)) AS LiveDelta
        FROM TicketDetails td
        INNER JOIN BranchCutoff bc ON bc.BranchCode = td.BranchCode
        WHERE @IncludeLiveActivity = 1
          AND td.TicketDate >= DATEADD(day, 1, ISNULL(bc.Cutoff, '19000101'))
          AND td.TicketDate <  DATEADD(day, 1, @AsOfDate)
        GROUP BY td.BranchCode, td.AccountCode
    ),
    BranchAccountCombined AS
    (
        SELECT
             COALESCE(pb.BranchCode, la.BranchCode)               AS BranchCode
            ,COALESCE(pb.AccountCode, la.AccountCode)              AS AccountCode
            ,ISNULL(pb.EndingBalance,0) + ISNULL(la.LiveDelta,0)   AS EndingBalance
        FROM PostedPerBranch pb
        FULL OUTER JOIN LiveActivity la
            ON la.BranchCode = pb.BranchCode AND la.AccountCode = pb.AccountCode
    )
    SELECT AccountCode, SUM(EndingBalance) AS EndingBalance
    INTO #LatestPosting
    FROM BranchAccountCombined
    GROUP BY AccountCode;

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
