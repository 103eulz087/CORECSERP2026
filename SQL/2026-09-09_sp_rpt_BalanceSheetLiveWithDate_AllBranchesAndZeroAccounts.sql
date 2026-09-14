-- Extend Balance Sheet (Real-Time): add @IncludeZeroActivity to show every
-- BS detail GL account, including ones with a zero hybrid ending balance or
-- no GLSummary/TicketDetails activity at all as of @AsOfDate. ALL BRANCHES
-- consolidation already worked (@BranchCode=NULL) -- no change needed there.
--
-- Mirrors SQL/2026-09-08_sp_rpt_BalanceSheetPerBranchInventory_IncludeZeroBalanceAccounts.sql's
-- approach exactly: SET 1's BSBase now drives FROM ChartOfAccounts (LEFT
-- JOIN #LatestPosting, ISNULL'd to 0) instead of FROM #LatestPosting (INNER
-- JOIN ChartOfAccounts), gated by the new parameter instead of being an
-- unconditional change, since this report needs a toggle (existing
-- chkIncludeZeroActivity checkbox on AccountingReportsForm.cs) rather than
-- always-on. Parameter name matches sp_rpt_GLDetailTransactionReport's
-- @IncludeZeroActivity for consistency across the codebase.
--
-- SET 2 unchanged, same reasoning as the sibling migration: section/grand
-- totals sum to the same value whether a zero-balance account's row is
-- present or not.
--
-- CurrentEarnings (SET 1) is a computed row, not a real GL account, and
-- stays hidden when zero regardless of the new parameter -- same as before.

IF OBJECT_ID('dbo.sp_rpt_BalanceSheetLiveWithDate', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_BalanceSheetLiveWithDate', 'sp_rpt_BalanceSheetLiveWithDate_OLD_09092026220000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_BalanceSheetLiveWithDate]
    @BranchCode          VARCHAR(5) = NULL,
    @AsOfDate            DATE,
    @IncludeLiveActivity BIT        = 1,   -- 0 = tie-out mode: must match sp_rpt_BalanceSheetWithDate exactly
    @IncludeZeroActivity BIT        = 0    -- 1 = show every BS detail account, including zero/no-activity ones
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#LatestPosting') IS NOT NULL DROP TABLE #LatestPosting;

    -- ── Hybrid posted+live ending balance per account, built ONCE ──────
    -- FIX (sp-reviewer): derive branch scope from every table that could
    -- carry a BranchCode, not just Branches -- a branch present in
    -- GLSummary/TicketDetails but missing/renamed in Branches must still
    -- get a cutoff, or its live activity is silently dropped while its
    -- posted balance (which doesn't depend on Branches) still shows up.
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

    -- ── SET 1: Line items ────────────────────────────────────────────
    -- CHANGE: drive FROM ChartOfAccounts (LEFT JOIN #LatestPosting,
    -- ISNULL to 0) instead of FROM #LatestPosting (INNER JOIN COA), so
    -- every detail BS account can be represented -- gated by
    -- @IncludeZeroActivity instead of unconditional, since this report
    -- exposes a checkbox rather than always showing zero accounts.
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
        FROM #LatestPosting lp
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

    -- ── SET 2: Section subtotals + balance check (unchanged -- summing in
    --    zero-balance accounts doesn't change any section's total) ───────
    ;WITH BSBase AS
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
            END AS BSSection
            ,CASE
                WHEN coa.AccountCode LIKE '101%' OR coa.AccountCode LIKE '102%' OR coa.AccountCode LIKE '103%'
                    THEN CAST(lp.EndingBalance  AS DECIMAL(19,2))
                ELSE CAST(-lp.EndingBalance AS DECIMAL(19,2))
             END AS Amount
        FROM #LatestPosting lp
        INNER JOIN ChartOfAccounts coa ON coa.AccountCode = lp.AccountCode
        WHERE coa.AccountType = 'D' AND coa.YearEndIndicator = 'BS'
    ),
    CurrentEarnings AS
    (
        SELECT
             '5-Equity' AS BSSection
            ,CAST(-SUM(ISNULL(lp.EndingBalance,0)) AS DECIMAL(19,2)) AS Amount
        FROM #LatestPosting lp
        INNER JOIN ChartOfAccounts coa ON coa.AccountCode = lp.AccountCode
        WHERE coa.AccountType = 'D' AND coa.YearEndIndicator = 'IS'
    ),
    Combined AS
    (
        SELECT BSSection, Amount FROM BSBase
        UNION ALL
        SELECT BSSection, Amount FROM CurrentEarnings WHERE Amount <> 0
    ),
    -- FIX (sp-reviewer): a scope with zero BS activity in every section
    -- (e.g. a dormant/new branch) used to make SectionTotals -- and
    -- therefore the whole SET 2 output -- return ZERO rows entirely,
    -- since GROUP BY over an empty Combined has nothing to group. Drive
    -- from a fixed 5-section list instead so SET 2 always has one row per
    -- canonical section, with SectionTotal=0 where nothing exists.
    AllSections AS
    (
        SELECT BSSection FROM (VALUES
            ('1-Current Assets'), ('2-Non-Current Assets'),
            ('3-Current Liabilities'), ('4-Non-Current Liabilities'),
            ('5-Equity')
        ) AS s(BSSection)
    ),
    SectionTotals AS
    (
        -- The 5 canonical sections, always present (zero-filled if empty).
        SELECT s.BSSection, CAST(ISNULL(SUM(c.Amount),0) AS DECIMAL(19,2)) AS SectionTotal
        FROM AllSections s
        LEFT JOIN Combined c ON c.BSSection = s.BSSection
        GROUP BY s.BSSection

        UNION ALL

        -- Anything outside the 5 canonical sections (e.g. a genuine
        -- '9-Other' account) still shows, but only when it actually has
        -- data -- unlike the canonical 5, it's not force-zero-filled.
        SELECT c.BSSection, CAST(SUM(c.Amount) AS DECIMAL(19,2)) AS SectionTotal
        FROM Combined c
        WHERE c.BSSection NOT IN (SELECT BSSection FROM AllSections)
        GROUP BY c.BSSection
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

    DROP TABLE IF EXISTS #LatestPosting;
END;
GO
