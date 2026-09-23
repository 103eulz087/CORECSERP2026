-- 2026-09-23: sp_GetPostedManualJournalVouchers -- TotalAmount must be
-- numeric, not FORMAT()-ed VARCHAR, so the Posted Voucher tab's grid can
-- right-align/sort/sum it. Same fix pattern already applied this session to
-- several sibling "posted" list procs -- see CLAUDE.md's "Reporting
-- Quantity/Amount columns must be numeric" convention.
--
-- Two confirmed callers (grepped the whole repo): ManualJournalVoucherMultiBranchFrm.cs
-- and its single-branch sibling ManualJournalVoucherFrm.cs -- both just bind
-- the DataTable straight to a grid with BestFitColumns(), no string-specific
-- handling of TotalAmount, so neither call site breaks from this type change.

IF OBJECT_ID('dbo.sp_GetPostedManualJournalVouchers', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetPostedManualJournalVouchers', 'sp_GetPostedManualJournalVouchers_OLD_09232026010000';
GO

CREATE PROCEDURE [dbo].[sp_GetPostedManualJournalVouchers]
    @DateFrom         DATE = NULL,
    @DateTo           DATE = NULL,
    @SingleBranchOnly BIT  = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ReferenceNo,
        MIN(VoucherDate)                          AS VoucherDate,
        MAX(Remarks)                              AS Remarks,
        COUNT(DISTINCT BranchCode)                AS BranchCount,
        MAX(BranchCode)                           AS BranchCode,   -- meaningful only when BranchCount = 1
        CAST(SUM(TotalAmount) AS DECIMAL(18,2))   AS TotalAmount,
        MAX(PreparedBy)                           AS PreparedBy
    FROM dbo.ManualJournalVoucher
    WHERE (@DateFrom IS NULL OR VoucherDate >= @DateFrom)
      AND (@DateTo   IS NULL OR VoucherDate <= @DateTo)
    GROUP BY ReferenceNo
    HAVING (@SingleBranchOnly = 0 OR COUNT(DISTINCT BranchCode) = 1)
    ORDER BY MIN(VoucherDate) DESC, ReferenceNo DESC;
END
GO
