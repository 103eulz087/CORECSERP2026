-- New, fully isolated report: Balance Sheet (Real-Time).
-- Zero existing objects modified -- net-new SP, net-new C# picker entry.
--
-- Same shape/logic as sp_rpt_BalanceSheetWithDate (SET1: AccountCode,
-- AccountDescription, Amount, RawEndingBalance; SET2: BSSection,
-- SectionTotal, TotalAssets, TotalLiabilities, TotalEquity, AsOfDate,
-- BranchCode), but folds in ticket activity not yet run through the
-- GLPosting batch job, so a new ticket shows up immediately instead of
-- waiting for the next posting run.
--
-- Approach: per branch, find a "posting cutoff" = the last date GLPosting
-- actually ran (COALESCE(PostingDateControl.LatestPostingDate,
-- MAX(GLSummary.PostingDate)) -- PostingDateControl first because GLPosting
-- deletes any GLSummary row that nets to all-zero, so MAX(PostingDate) alone
-- can understate how far a branch is really posted). Everything up to and
-- including that cutoff comes from GLSummary unchanged. Everything after it
-- is computed live from TicketDetails (SUM(Debit)-SUM(Credit) per account)
-- and added on top -- this is provably consistent with GLPosting's own
-- EndingBalance = BeginningBalance + Debits + Credits formula (GLSummary
-- stores Credits negated; TicketDetails.Debit/.Credit are raw positive).
--
-- Known limitations:
-- 1. Does not replicate GLPosting's due-to/due-from (DFR/DTO) netting for
--    tickets posted in the live window. Accepted per business confirmation
--    that DueToFromIndicator accounts are being removed from ChartOfAccounts.
--    Already-netted ("BOSNET") tickets are immune to this by construction --
--    GLPosting creates and consumes them atomically inside its own
--    transaction, so they can never appear as unposted/live data.
-- 2. A ticket BACKDATED onto an already-posted date is invisible here until
--    GLPosting is re-run for that date: it's excluded from GLSummary (not
--    yet reflected) AND excluded from the live tail (TicketDate <= the
--    branch's cutoff, so it falls before the live window's start). This is
--    a real, expected scenario -- see GLPosting's own backdated-post guard
--    (2026-09-09_GLPosting_EnableBackdatedPostingGuard.sql) -- not just a
--    hypothetical. "Real-Time" means "current through the live tail," not
--    "immune to backdated entries against already-posted history."
--
-- Note: built off the PLAIN sp_rpt_BalanceSheetWithDate, not
-- sp_rpt_BalanceSheetPerBranchInventory (which is what the picker's current
-- "Balance Sheet" entry actually points to) -- so this does not include the
-- per-branch Petty Cash/Inventory breakout rows. Confirmed with the user.
--
-- Callers: AccountingReportsForm.cs, "Balance Sheet (Real-Time)".

IF OBJECT_ID('dbo.sp_rpt_BalanceSheetLiveWithDate', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_BalanceSheetLiveWithDate', 'sp_rpt_BalanceSheetLiveWithDate_OLD_09092026160000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_BalanceSheetLiveWithDate]
    @BranchCode          VARCHAR(5) = NULL,
    @AsOfDate            DATE,
    @IncludeLiveActivity BIT        = 1   -- 0 = tie-out mode: must match sp_rpt_BalanceSheetWithDate exactly
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

    -- ── SET 1: Line items (verbatim logic from sp_rpt_BalanceSheetWithDate,
    --    sourced from #LatestPosting instead of a raw GLSummary scan) ────
    ;WITH BSBase AS
    (
        SELECT
             coa.AccountCode
            ,coa.Description AS AccountDescription
            ,CASE
                WHEN coa.AccountCode LIKE '101%' OR coa.AccountCode LIKE '102%' OR coa.AccountCode LIKE '103%'
                    THEN CAST(lp.EndingBalance  AS DECIMAL(19,2))
                ELSE CAST(-lp.EndingBalance AS DECIMAL(19,2))
             END AS Amount
            ,CAST(lp.EndingBalance AS DECIMAL(19,2)) AS RawEndingBalance
        FROM #LatestPosting lp
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

    -- ── SET 2: Section subtotals + balance check (verbatim logic) ──────
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

    DROP TABLE IF EXISTS #LatestPosting;
END;
GO
