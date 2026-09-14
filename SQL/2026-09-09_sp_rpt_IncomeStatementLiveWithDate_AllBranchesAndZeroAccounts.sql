-- Extend Income Statement (Real-Time) with the two options requested:
-- 1. ALL BRANCHES consolidation -- this SP was single-branch-only by
--    original design (@BranchCode had no default and THREW on NULL).
--    Reworked to the SAME per-branch-cutoff-then-consolidate pattern
--    already used by sp_rpt_BalanceSheetLiveWithDate (BranchScope/
--    GLMaxDate/BranchCutoff CTEs), so each in-scope branch's posted and
--    live activity is computed and bounded independently against its OWN
--    posting cutoff, then summed together per AccountCode. This is plain
--    consolidation, NOT the side-by-side per-branch pivot that
--    AccountingReportsForm.cs's SupportsAllBranchPivot/PivotSpName
--    mechanism handles elsewhere for the original (non-real-time) Income
--    Statement -- that remains a separate, unbuilt feature.
-- 2. @IncludeZeroActivity -- same toggle/parameter name as
--    sp_rpt_GLDetailTransactionReport and the sibling change just made to
--    sp_rpt_BalanceSheetLiveWithDate. SET 1 now drives FROM ChartOfAccounts
--    (LEFT JOIN #CombinedActivity) instead of FROM #CombinedActivity
--    (INNER JOIN ChartOfAccounts), so an IS account with zero period
--    activity -- or no #CombinedActivity row at all -- can be shown too.
--
-- SET 2 (P&L summary) is unaffected by either change in the same way the
-- Balance Sheet's SET 2 is unaffected by zero-accounts: a zero-activity
-- account contributes 0 to every SUM regardless of whether it's present,
-- and consolidating across branches is exactly the same SUM(...)-per-
-- account math the SP already did for one branch, just fed a
-- multi-branch #CombinedActivity built the same way Balance Sheet
-- (Real-Time) already builds its #LatestPosting.
--
-- @BranchCode output column now shows ISNULL(@BranchCode,'ALL'), matching
-- the Balance Sheet (Real-Time) SET 2 convention, instead of always
-- echoing the (now-nullable) input parameter directly.

IF OBJECT_ID('dbo.sp_rpt_IncomeStatementLiveWithDate', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_IncomeStatementLiveWithDate', 'sp_rpt_IncomeStatementLiveWithDate_OLD_09092026220000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_IncomeStatementLiveWithDate]
    @BranchCode          VARCHAR(5) = NULL,
    @DateFrom            DATE,
    @DateTo              DATE,
    @IncludeLiveActivity BIT        = 1,   -- 0 = tie-out mode: must match sp_rpt_IncomeStatementWithDate exactly (single-branch only)
    @IncludeZeroActivity BIT        = 0    -- 1 = show every IS detail account, including zero/no-activity ones
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#CombinedActivity') IS NOT NULL DROP TABLE #CombinedActivity;

    -- ── Hybrid posted+live period activity per account, built ONCE,
    --    consolidated across every in-scope branch ─────────────────────
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
        -- Live window per branch starts the later of (that branch's
        -- cutoff+1 day) and @DateFrom -- GREATEST is safe at this DB's
        -- compat level 120 (confirmed in the T-SQL authoring skill).
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

    -- ── SET 1: Line items ────────────────────────────────────────────
    -- CHANGE: drive FROM ChartOfAccounts (LEFT JOIN #CombinedActivity)
    -- instead of FROM #CombinedActivity (INNER JOIN ChartOfAccounts), so
    -- every detail IS account can be represented -- gated by
    -- @IncludeZeroActivity.
    SELECT
         coa.AccountCode
        ,coa.Description AS AccountDescription
        ,coa.LevelNumber
        ,coa.Nature
        ,CASE
            WHEN LEFT(coa.AccountCode,1) = '4' THEN '1-Revenue'
            WHEN LEFT(coa.AccountCode,1) = '5' THEN '2-Cost of Goods Sold'
            WHEN LEFT(coa.AccountCode,1) = '6' THEN '3-Operating Expenses'
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
         AS DECIMAL(19,2)) AS NetAmount
        ,CASE
            WHEN LEFT(coa.AccountCode,1) = '5'
             AND coa.Nature = 'C'
            THEN 1 ELSE 0
         END AS IsContraCOGS
        ,@DateFrom  AS PeriodFrom
        ,@DateTo    AS PeriodTo
    FROM ChartOfAccounts coa
    LEFT JOIN #CombinedActivity ca ON ca.AccountCode = coa.AccountCode
    WHERE coa.AccountType      = 'D'
      AND coa.YearEndIndicator = 'IS'
      AND (@IncludeZeroActivity = 1 OR ISNULL(ca.PeriodDebits,0) <> 0 OR ISNULL(ca.PeriodCredits,0) <> 0)
    ORDER BY ISSection, coa.AccountCode;

    -- ── SET 2: P&L Summary (unchanged math -- zero accounts contribute 0,
    --    consolidation is the same per-account SUM fed multi-branch data) ──
    -- FIX (sp-reviewer): every SUM() wrapped in ISNULL(...,0) -- a scope
    -- with zero matching IS accounts (a dormant/new branch, or a narrow
    -- date range) used to return one row of all-NULL totals instead of a
    -- proper all-zero row. Demonstrated live on branch 012.
    SELECT
         CAST(ISNULL(SUM(
            CASE WHEN LEFT(coa.AccountCode,1) = '4'
             THEN ca.PeriodCredits - ca.PeriodDebits
             ELSE 0 END
         ),0) AS DECIMAL(19,2))                                AS TotalRevenue

        ,CAST(ISNULL(SUM(
            CASE
                WHEN LEFT(coa.AccountCode,1) = '5' AND coa.Nature = 'D'
                THEN ca.PeriodDebits - ca.PeriodCredits
                WHEN LEFT(coa.AccountCode,1) = '5' AND coa.Nature = 'C'
                THEN -(ca.PeriodCredits - ca.PeriodDebits)
                ELSE 0
            END
         ),0) AS DECIMAL(19,2))                                AS TotalCOGS

        ,CAST(ISNULL(
            SUM(CASE WHEN LEFT(coa.AccountCode,1)='4'
                 THEN ca.PeriodCredits - ca.PeriodDebits ELSE 0 END)
           -SUM(CASE WHEN LEFT(coa.AccountCode,1)='5' AND coa.Nature='D'
                 THEN ca.PeriodDebits - ca.PeriodCredits ELSE 0 END)
           +SUM(CASE WHEN LEFT(coa.AccountCode,1)='5' AND coa.Nature='C'
                 THEN ca.PeriodCredits - ca.PeriodDebits ELSE 0 END)
         ,0) AS DECIMAL(19,2))                                  AS GrossProfit

        ,CAST(ISNULL(SUM(
            CASE WHEN LEFT(coa.AccountCode,1) = '6'
             THEN ca.PeriodDebits - ca.PeriodCredits
             ELSE 0 END
         ),0) AS DECIMAL(19,2))                                AS TotalExpenses

        ,CAST(ISNULL(
            SUM(CASE WHEN LEFT(coa.AccountCode,1)='4'
                      AND coa.AccountCode NOT IN ('403','404')
                 THEN ca.PeriodCredits - ca.PeriodDebits ELSE 0 END)
           -SUM(CASE WHEN LEFT(coa.AccountCode,1)='5' AND coa.Nature='D'
                 THEN ca.PeriodDebits - ca.PeriodCredits ELSE 0 END)
           +SUM(CASE WHEN LEFT(coa.AccountCode,1)='5' AND coa.Nature='C'
                 THEN ca.PeriodCredits - ca.PeriodDebits ELSE 0 END)
           -SUM(CASE WHEN LEFT(coa.AccountCode,1)='6'
                 THEN ca.PeriodDebits - ca.PeriodCredits ELSE 0 END)
         ,0) AS DECIMAL(19,2))                                  AS OperatingIncome

        ,CAST(ISNULL(SUM(
            CASE WHEN coa.AccountCode IN ('403','404')
             THEN ca.PeriodCredits - ca.PeriodDebits
             ELSE 0 END
         ),0) AS DECIMAL(19,2))                                AS OtherIncome

        ,CAST(ISNULL(
            SUM(CASE WHEN LEFT(coa.AccountCode,1)='4'
                 THEN ca.PeriodCredits - ca.PeriodDebits ELSE 0 END)
           -SUM(CASE WHEN LEFT(coa.AccountCode,1)='5' AND coa.Nature='D'
                 THEN ca.PeriodDebits - ca.PeriodCredits ELSE 0 END)
           +SUM(CASE WHEN LEFT(coa.AccountCode,1)='5' AND coa.Nature='C'
                 THEN ca.PeriodCredits - ca.PeriodDebits ELSE 0 END)
           -SUM(CASE WHEN LEFT(coa.AccountCode,1)='6'
                 THEN ca.PeriodDebits - ca.PeriodCredits ELSE 0 END)
         ,0) AS DECIMAL(19,2))                                  AS NetIncome

        ,@DateFrom                   AS PeriodFrom
        ,@DateTo                     AS PeriodTo
        ,ISNULL(@BranchCode, 'ALL')  AS BranchCode
    FROM #CombinedActivity ca
    INNER JOIN ChartOfAccounts coa ON coa.AccountCode = ca.AccountCode
    WHERE coa.AccountType      = 'D'
      AND coa.YearEndIndicator = 'IS';

    DROP TABLE IF EXISTS #CombinedActivity;
END;
GO
