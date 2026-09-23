-- 2026-09-23: ManualJournalVoucherMultiBranchFrm.cs -- Posted Voucher Tab /
-- View Details bug report.
--
-- ISSUE (a): TotalAmount in the Posted Voucher Tab "looks multiplied by
-- BranchCount" for a multi-branch voucher.
--
-- ROOT CAUSE (confirmed from sp_PostManualJournalVoucherMultiBranch's
-- actual INSERT shape, not guessed): a multi-branch voucher writes ONE
-- ManualJournalVoucher row PER BRANCH, but ALL of those rows -- and ALL of
-- the TicketMaster rows written for those branches -- share the exact SAME
-- (TicketNumber, ReferenceNumber) pair (one TicketNumber is generated once
-- per voucher, shared across every branch's TicketMaster/ManualJournalVoucher
-- row; only BranchCode differs). sp_GetPostedManualJournalVouchers's
-- INNER JOIN TicketMaster b ON a.TicketNumber=b.TicketNumber AND
-- a.ReferenceNo=b.ReferenceNumber therefore matches EVERY branch's
-- ManualJournalVoucher row against EVERY branch's TicketMaster row for that
-- same voucher (BranchCode plays no part in the join condition) -- for an
-- N-branch voucher that's N x N joined rows feeding SUM(a.TotalAmount),
-- i.e. the true total appears N times over -- exactly "multiplied by
-- BranchCount".
--
-- FIX: ControlNo (TicketMaster.ReferenceKey) is identical across every
-- branch row of the same voucher, so pull it as a scalar subquery instead
-- of a join that participates in the aggregation -- and revert GROUP BY to
-- a.ReferenceNo alone (drop b.ReferenceKey from it).
--
-- sp-reviewer findings addressed in this revision (2nd deploy, same day):
--   - SUM(a.TotalAmount)/COUNT(DISTINCT a.BranchCode) now wrap TotalAmount
--     in ISNULL so one branch-row with a NULL TotalAmount can't silently
--     understate the voucher's reported total with no error surfaced.
--   - ControlNo subquery now prefers a non-NULL ReferenceKey via ORDER BY
--     CASE WHEN NULL THEN 1 ELSE 0 END before TicketNumber, so a NULL on
--     the lowest-TicketNumber branch row can't hide a real value that
--     exists on another branch row of the same voucher.
--   - ControlNo is a passive display-only column (confirmed: not read by
--     ManualJournalVoucherMultiBranchFrm.cs/ManualJournalVoucherFrm.cs
--     beyond binding it to the grid) whose correctness ultimately depends
--     on sp_GetReferenceNumber producing a globally-unique ReferenceNo
--     across the whole system -- that generator's body isn't checked into
--     this repo, so its uniqueness guarantee could not be independently
--     verified here. Flagged for the user; not blocking since a wrong
--     ControlNo today is cosmetic only, not a ledger-mutating value.
--
-- ISSUE (details): sp_GetManualJournalVoucherDetails (View Details / Copy /
-- Edit-load source) returns Debit/Credit as FORMAT()-ed VARCHAR instead of
-- real DECIMAL -- violates CLAUDE.md's "Reporting Quantity/Amount columns
-- must be numeric" convention and is why the View Details grid could not
-- carry a Debit/Credit footer total (a formatted-string column can't be
-- summed by the grid). Fixed alongside (a) since both are read by the same
-- form/feature and BtnEditVoucher_Click/BtnCopyToNew_Click also consume
-- this same result set into a typed-decimal DataTable column.
--
-- Deploy to CORECSERP_002_DEV first; mirror to CORECSJFC2026_STAGING only
-- after confirming with the user, per project convention.

-- ----------------------------------------------------------------
-- 1. sp_GetPostedManualJournalVouchers
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_GetPostedManualJournalVouchers', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetPostedManualJournalVouchers', 'sp_GetPostedManualJournalVouchers_OLD_09232026070000';
GO

CREATE PROCEDURE [dbo].[sp_GetPostedManualJournalVouchers]
    @DateFrom         DATE = NULL,
    @DateTo           DATE = NULL,
    @SingleBranchOnly BIT  = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        (
            SELECT TOP 1 tm.ReferenceKey
            FROM dbo.TicketMaster tm
            WHERE tm.ReferenceNumber = a.ReferenceNo
            ORDER BY CASE WHEN tm.ReferenceKey IS NULL THEN 1 ELSE 0 END, tm.TicketNumber
        )                                                     AS ControlNo,
        a.ReferenceNo,
        MIN(a.VoucherDate)                                  AS VoucherDate,
        MAX(a.Remarks)                                       AS Remarks,
        COUNT(DISTINCT a.BranchCode)                         AS BranchCount,
        MAX(a.BranchCode)                                    AS BranchCode,   -- meaningful only when BranchCount = 1
        CAST(SUM(ISNULL(a.TotalAmount, 0)) AS DECIMAL(18,2)) AS TotalAmount,
        MAX(a.PreparedBy)                                    AS PreparedBy
    FROM dbo.ManualJournalVoucher a
    WHERE (@DateFrom IS NULL OR a.VoucherDate >= @DateFrom)
      AND (@DateTo   IS NULL OR a.VoucherDate <= @DateTo)
    GROUP BY a.ReferenceNo
    HAVING (@SingleBranchOnly = 0 OR COUNT(DISTINCT a.BranchCode) = 1)
    ORDER BY MIN(a.VoucherDate) DESC, a.ReferenceNo DESC;
END
GO

-- ----------------------------------------------------------------
-- 2. sp_GetManualJournalVoucherDetails -- real DECIMAL Debit/Credit
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_GetManualJournalVoucherDetails', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetManualJournalVoucherDetails', 'sp_GetManualJournalVoucherDetails_OLD_09232026070000';
GO

CREATE PROCEDURE [dbo].[sp_GetManualJournalVoucherDetails]
    @ReferenceNo VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        mjv.BranchCode,
        br.BranchName,
        mjvd.AccountCode,
        c.Description as AccountTitle,
        CAST(mjvd.Debit AS DECIMAL(18,2)) as Debit,
        CAST(mjvd.Credit AS DECIMAL(18,2)) as Credit,
        mjvd.Particulars
    FROM dbo.ManualJournalVoucher mjv
    JOIN dbo.ManualJournalVoucherDetails mjvd ON mjvd.VoucherID = mjv.VoucherID
    INNER JOIN dbo.ChartOfAccounts c ON mjvd.AccountCode=c.AccountCode
    INNER JOIN Branches br ON mjv.BranchCode=br.BranchCode
    WHERE mjv.ReferenceNo = @ReferenceNo
    ORDER BY mjv.BranchCode, mjvd.AccountCode;
END
GO
