-- New, fully isolated report: Income Statement (Real-Time).
-- Zero existing objects modified -- net-new SP, net-new C# picker entry.
-- Same posted-snapshot + live-ticket-tail hybrid as
-- sp_rpt_BalanceSheetLiveWithDate -- see that script's header comment for
-- the full rationale (posting-cutoff derivation, sign conventions, and both
-- known limitations: DFR/DTO netting and backdated tickets onto an
-- already-posted date being invisible until GLPosting re-runs for that
-- date). Single branch only, matching sp_rpt_IncomeStatementWithDate
-- exactly (no all-branches pivot -- out of scope, a separate not-yet-built
-- pivot SP handles that elsewhere).
--
-- Callers: AccountingReportsForm.cs, "Income Statement (Real-Time)".

IF OBJECT_ID('dbo.sp_rpt_IncomeStatementLiveWithDate', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_IncomeStatementLiveWithDate', 'sp_rpt_IncomeStatementLiveWithDate_OLD_09092026160000';
GO

CREATE PROCEDURE [dbo].[sp_rpt_IncomeStatementLiveWithDate]
    @BranchCode          VARCHAR(5),
    @DateFrom            DATE,
    @DateTo              DATE,
    @IncludeLiveActivity BIT = 1   -- 0 = tie-out mode: must match sp_rpt_IncomeStatementWithDate exactly
AS
BEGIN
    SET NOCOUNT ON;

    IF @BranchCode IS NULL
        THROW 50000, 'sp_rpt_IncomeStatementLiveWithDate: @BranchCode is required (single-branch report, same as sp_rpt_IncomeStatementWithDate).', 1;

    IF OBJECT_ID('tempdb..#CombinedActivity') IS NOT NULL DROP TABLE #CombinedActivity;

    DECLARE @Cutoff DATE;
    SELECT @Cutoff = COALESCE(
        (SELECT LatestPostingDate FROM PostingDateControl WHERE BranchCode = @BranchCode),
        (SELECT MAX(PostingDate) FROM GLSummary WHERE BranchCode = @BranchCode)
    );

    -- Live window starts the later of (cutoff+1 day) and @DateFrom -- a
    -- report whose range starts well after the branch's posting cutoff
    -- should not pull in live activity from before @DateFrom.
    DECLARE @LiveLowerBound DATE = (
        SELECT MAX(v) FROM (VALUES
            (DATEADD(day, 1, ISNULL(@Cutoff, '19000101'))),
            (@DateFrom)
        ) AS x(v)
    );

    -- ── Hybrid posted+live period activity per account, built ONCE ─────
    ;WITH PostedActivity AS
    (
        SELECT
             gs.AccountCode
            ,SUM(gs.Debits)       AS PeriodDebits
            ,SUM(ABS(gs.Credits)) AS PeriodCredits
        FROM GLSummary gs
        WHERE gs.BranchCode  = @BranchCode
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
        WHERE @IncludeLiveActivity = 1
          AND td.BranchCode = @BranchCode
          AND td.TicketDate >= @LiveLowerBound
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

    -- ── SET 1: Line items (verbatim logic from sp_rpt_IncomeStatementWithDate) ──
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
        ,CAST(ca.PeriodDebits  AS DECIMAL(19,2)) AS PeriodDebits
        ,CAST(ca.PeriodCredits AS DECIMAL(19,2)) AS PeriodCredits
        ,CAST(
            CASE coa.Nature
                WHEN 'C' THEN ca.PeriodCredits - ca.PeriodDebits
                WHEN 'D' THEN ca.PeriodDebits  - ca.PeriodCredits
            END
         AS DECIMAL(19,2)) AS NetAmount
        ,CASE
            WHEN LEFT(coa.AccountCode,1) = '5'
             AND coa.Nature = 'C'
            THEN 1 ELSE 0
         END AS IsContraCOGS
        ,@DateFrom  AS PeriodFrom
        ,@DateTo    AS PeriodTo
    FROM #CombinedActivity ca
    INNER JOIN ChartOfAccounts coa ON coa.AccountCode = ca.AccountCode
    WHERE coa.AccountType      = 'D'
      AND coa.YearEndIndicator = 'IS'
      AND (ca.PeriodDebits <> 0 OR ca.PeriodCredits <> 0)
    ORDER BY ISSection, coa.AccountCode;

    -- ── SET 2: P&L Summary (verbatim logic) ─────────────────────────────
    SELECT
         CAST(SUM(
            CASE WHEN LEFT(coa.AccountCode,1) = '4'
             THEN ca.PeriodCredits - ca.PeriodDebits
             ELSE 0 END
         ) AS DECIMAL(19,2))                                AS TotalRevenue

        ,CAST(SUM(
            CASE
                WHEN LEFT(coa.AccountCode,1) = '5' AND coa.Nature = 'D'
                THEN ca.PeriodDebits - ca.PeriodCredits
                WHEN LEFT(coa.AccountCode,1) = '5' AND coa.Nature = 'C'
                THEN -(ca.PeriodCredits - ca.PeriodDebits)
                ELSE 0
            END
         ) AS DECIMAL(19,2))                                AS TotalCOGS

        ,CAST(
            SUM(CASE WHEN LEFT(coa.AccountCode,1)='4'
                 THEN ca.PeriodCredits - ca.PeriodDebits ELSE 0 END)
           -SUM(CASE WHEN LEFT(coa.AccountCode,1)='5' AND coa.Nature='D'
                 THEN ca.PeriodDebits - ca.PeriodCredits ELSE 0 END)
           +SUM(CASE WHEN LEFT(coa.AccountCode,1)='5' AND coa.Nature='C'
                 THEN ca.PeriodCredits - ca.PeriodDebits ELSE 0 END)
         AS DECIMAL(19,2))                                  AS GrossProfit

        ,CAST(SUM(
            CASE WHEN LEFT(coa.AccountCode,1) = '6'
             THEN ca.PeriodDebits - ca.PeriodCredits
             ELSE 0 END
         ) AS DECIMAL(19,2))                                AS TotalExpenses

        ,CAST(
            SUM(CASE WHEN LEFT(coa.AccountCode,1)='4'
                      AND coa.AccountCode NOT IN ('403','404')
                 THEN ca.PeriodCredits - ca.PeriodDebits ELSE 0 END)
           -SUM(CASE WHEN LEFT(coa.AccountCode,1)='5' AND coa.Nature='D'
                 THEN ca.PeriodDebits - ca.PeriodCredits ELSE 0 END)
           +SUM(CASE WHEN LEFT(coa.AccountCode,1)='5' AND coa.Nature='C'
                 THEN ca.PeriodCredits - ca.PeriodDebits ELSE 0 END)
           -SUM(CASE WHEN LEFT(coa.AccountCode,1)='6'
                 THEN ca.PeriodDebits - ca.PeriodCredits ELSE 0 END)
         AS DECIMAL(19,2))                                  AS OperatingIncome

        ,CAST(SUM(
            CASE WHEN coa.AccountCode IN ('403','404')
             THEN ca.PeriodCredits - ca.PeriodDebits
             ELSE 0 END
         ) AS DECIMAL(19,2))                                AS OtherIncome

        ,CAST(
            SUM(CASE WHEN LEFT(coa.AccountCode,1)='4'
                 THEN ca.PeriodCredits - ca.PeriodDebits ELSE 0 END)
           -SUM(CASE WHEN LEFT(coa.AccountCode,1)='5' AND coa.Nature='D'
                 THEN ca.PeriodDebits - ca.PeriodCredits ELSE 0 END)
           +SUM(CASE WHEN LEFT(coa.AccountCode,1)='5' AND coa.Nature='C'
                 THEN ca.PeriodCredits - ca.PeriodDebits ELSE 0 END)
           -SUM(CASE WHEN LEFT(coa.AccountCode,1)='6'
                 THEN ca.PeriodDebits - ca.PeriodCredits ELSE 0 END)
         AS DECIMAL(19,2))                                  AS NetIncome

        ,@DateFrom   AS PeriodFrom
        ,@DateTo     AS PeriodTo
        ,@BranchCode AS BranchCode
    FROM #CombinedActivity ca
    INNER JOIN ChartOfAccounts coa ON coa.AccountCode = ca.AccountCode
    WHERE coa.AccountType      = 'D'
      AND coa.YearEndIndicator = 'IS';

    DROP TABLE IF EXISTS #CombinedActivity;
END;
GO
