-- 2026-09-22: sp_GetReversibleSupplierVouchers -- Amount must be numeric,
-- not FORMAT()-ed VARCHAR, so SupplierVoucherReversalFrm.cs's list grid can
-- right-align it, sort it by value, and carry a footer total. Same
-- anti-pattern/fix already applied this session to sp_GetPostedSingleExpenses
-- and sp_GetSupplierVoucherDetails -- see CLAUDE.md's "Reporting
-- Quantity/Amount columns must be numeric" convention.
--
-- Amount is MONEY on all three source tables (CheckVoucher/CashVoucher/
-- TelegraphicVoucher) -- CAST to DECIMAL(18,2) matches the convention used
-- everywhere else in this codebase for money columns.
--
-- Only caller confirmed (grepped the whole repo): SupplierVoucherReversalFrm.cs
-- (BtnReverse_Click / viewDetailsToolStripMenuItem_Click already do
-- Convert.ToDecimal(...) on this value -- works unchanged against a native
-- decimal, no C# call site breaks).

IF OBJECT_ID('dbo.sp_GetReversibleSupplierVouchers', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetReversibleSupplierVouchers', 'sp_GetReversibleSupplierVouchers_OLD_09222026190000';
GO

CREATE PROCEDURE [dbo].[sp_GetReversibleSupplierVouchers]
    @SupplierID VARCHAR(50) = NULL,
    @DateFrom   DATE = NULL,
    @DateTo     DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

     ;WITH AllVouchers AS (
        SELECT VoucherID, SupplierID, ReferenceNumber, PaidTo, NotedBy AS PhysicalRef,
               CheckDate AS VoucherDate, Amount, VoucherType AS PhysicalVoucherType,isErrorCorrect
        FROM CheckVoucher --WHERE isErrorCorrect = 0
        UNION ALL
        SELECT VoucherID, SupplierID, ReferenceNumber, PaidTo, ControlNo AS PhysicalRef,
               DateReceived AS VoucherDate, Amount, VoucherType AS PhysicalVoucherType,isErrorCorrect
        FROM CashVoucher --WHERE isErrorCorrect = 0
        UNION ALL
        SELECT VoucherID, SupplierID, ReferenceNumber, PaidTo, ControlNo AS PhysicalRef,
               DateReceived AS VoucherDate, Amount, VoucherType AS PhysicalVoucherType,isErrorCorrect
        FROM TelegraphicVoucher --WHERE isErrorCorrect = 0
    )
    SELECT
        v.VoucherID,
        v.SupplierID,
        v.ReferenceNumber,
        v.PaidTo,
        v.PhysicalRef,
        v.VoucherDate,
        CAST(v.Amount AS DECIMAL(18,2)) AS Amount,
        v.PhysicalVoucherType,
        (SELECT TOP 1 apd.PaymentMethod FROM APPaymentDetails apd
         WHERE apd.ReferenceNumber = v.ReferenceNumber AND apd.SupplierID = v.SupplierID) AS PaymentMethod,
        CASE WHEN EXISTS (
            SELECT 1 FROM APPaymentDetails apd
            WHERE apd.ReferenceNumber = v.ReferenceNumber AND apd.SupplierID = v.SupplierID
        ) THEN 1 ELSE 0 END AS HasInvoiceLeg,
        CASE WHEN EXISTS (
            SELECT 1 FROM dbo.CashAdvance ca
            WHERE ca.ReferenceNo = v.ReferenceNumber AND ca.SupplierID = v.SupplierID AND ca.Status <> 'REVERSED'
        ) THEN 1 ELSE 0 END AS HasManualLeg,
        v.isErrorCorrect
    FROM AllVouchers v
    WHERE (@SupplierID IS NULL OR v.SupplierID = @SupplierID)
      AND (@DateFrom   IS NULL OR v.VoucherDate >= @DateFrom)
      AND (@DateTo     IS NULL OR v.VoucherDate <= @DateTo)
    ORDER BY v.VoucherDate DESC, v.ReferenceNumber DESC;
END
GO
