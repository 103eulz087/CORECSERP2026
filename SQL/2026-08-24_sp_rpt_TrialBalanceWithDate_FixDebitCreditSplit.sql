SET NOCOUNT ON;
PRINT '=== sp_rpt_TrialBalanceWithDate: fix inverted Nature-gated Debit/Credit split (AccountingReportsForm.cs Trial Balance) ===';
GO

-- =============================================================================
-- BUG: GLSummary.EndingBalance uses ONE uniform sign convention for every
-- account regardless of Nature -- GLPosting computes
-- EndingBalance = BeginningBalance + Debits + Credits where Credits is
-- stored NEGATIVE (Credits = -SUM(TicketDetails.Credit)). So EndingBalance
-- is always "net debit position": positive = net debit, negative = net
-- credit, for EVERY account regardless of whether it's Nature='D' or
-- Nature='C'. This SP's own [Is Abnormal Balance] column already encodes
-- exactly that understanding correctly:
--     (Nature='D' AND EndingBalance<0) OR (Nature='C' AND EndingBalance>0)
-- i.e. Nature only decides whether a given sign is NORMAL or ABNORMAL for
-- that account -- it does NOT change which column (Debit vs Credit) the
-- amount belongs in. The sign alone determines the column.
--
-- The previous [TB Debit]/[TB Credit] (and [Total Debit]/[Total Credit] in
-- the summary result set) CASE expressions incorrectly gated the sign split
-- BY Nature:
--     TB Debit  = (Nature='D' AND EB>=0) OR (Nature='C' AND EB<0)
--     TB Credit = (Nature='C' AND EB>=0) OR (Nature='D' AND EB<0)
-- Since a Nature='C' account's NORMAL balance is EB<0 (per the sign
-- convention above), that branch shoved every normal Credit-nature balance
-- (liabilities/equity/revenue -- the bulk of the chart) into the TB DEBIT
-- column instead of TB Credit, and vice versa for abnormal cases. This
-- produced a massive Debit/Credit mismatch on every multi-branch or
-- single-branch run despite TicketDetails itself (the true source of truth)
-- always balancing to zero by double-entry construction.
--
-- Reproduced and confirmed live against CORECSJFC2026_STAGING as of
-- 2026-07-31, all branches:
--   Before fix (buggy SP):   Total Debit = 7,327,133,999.47   Total Credit = 57,069,378.77
--   After fix (sign-only):   Total Debit = 3,692,101,689.12   Total Credit = 3,692,101,689.12  (balances exactly)
--   TicketDetails source total (Debit=Credit by double-entry): 3,688,581,595.84
--
-- FIX: split TB Debit/TB Credit (and Total Debit/Total Credit) purely by
-- EndingBalance sign, independent of Nature. Nature continues to drive ONLY
-- the [Is Abnormal Balance] flag, unchanged.
--
-- No other logic (LatestPerBranch CTE, @BranchCode=NULL consolidation,
-- ChartOfAccounts join/filter) changed.
-- =============================================================================
-- Idempotent re-run guard: only rename-to-backup the FIRST time this script
-- runs against a given database (i.e. only if the timestamped backup name
-- doesn't already exist). A second run in the same environment just
-- replaces the current draft directly -- no value in stacking backups of a
-- version that was never used against real data.
IF OBJECT_ID('dbo.sp_rpt_TrialBalanceWithDate_OLD_08242026180000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.sp_rpt_TrialBalanceWithDate', 'P') IS NOT NULL
        DROP PROCEDURE dbo.sp_rpt_TrialBalanceWithDate;
END
ELSE IF OBJECT_ID('dbo.sp_rpt_TrialBalanceWithDate', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.sp_rpt_TrialBalanceWithDate', 'sp_rpt_TrialBalanceWithDate_OLD_08242026180000';
END
GO

CREATE PROCEDURE [dbo].[sp_rpt_TrialBalanceWithDate]
    @BranchCode  VARCHAR(5) = NULL,
    @AsOfDate    DATE
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH LatestPerBranch AS (
        SELECT
            gs.BranchCode, gs.AccountCode, gs.EndingBalance,
            ROW_NUMBER() OVER (
                PARTITION BY gs.BranchCode, gs.AccountCode
                ORDER BY gs.PostingDate DESC, gs.SupplementaryNumber DESC
            ) AS rn
        FROM GLSummary gs
        WHERE gs.PostingDate <= @AsOfDate
          AND (@BranchCode IS NULL OR gs.BranchCode = @BranchCode)
    ),
    ConsolidatedBalance AS (
        SELECT AccountCode, SUM(EndingBalance) AS EndingBalance
        FROM LatestPerBranch
        WHERE rn = 1
        GROUP BY AccountCode
    )
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
    LEFT JOIN ConsolidatedBalance cb ON cb.AccountCode = coa.AccountCode
    WHERE coa.AccountType = 'D'
    ORDER BY coa.AccountCode;

    -- Summary
    ;WITH LatestPerBranch2 AS (
        SELECT
            gs.BranchCode, gs.AccountCode, gs.EndingBalance,
            ROW_NUMBER() OVER (
                PARTITION BY gs.BranchCode, gs.AccountCode
                ORDER BY gs.PostingDate DESC, gs.SupplementaryNumber DESC
            ) AS rn
        FROM GLSummary gs
        WHERE gs.PostingDate <= @AsOfDate
          AND (@BranchCode IS NULL OR gs.BranchCode = @BranchCode)
    ),
    ConsolidatedBalance2 AS (
        SELECT lp.AccountCode, SUM(lp.EndingBalance) AS EndingBalance
        FROM LatestPerBranch2 lp
        WHERE lp.rn = 1
        GROUP BY lp.AccountCode
    )
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
    LEFT JOIN ConsolidatedBalance2 cb ON cb.AccountCode = coa.AccountCode
    WHERE coa.AccountType = 'D';
END;
GO

PRINT 'DEPLOYMENT COMPLETE: sp_rpt_TrialBalanceWithDate Debit/Credit split now keyed on EndingBalance sign only.';
