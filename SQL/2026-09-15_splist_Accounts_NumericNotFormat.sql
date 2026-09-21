/* ================================================================
   splist_Accounts — return ActualCost/Balance/AmountPaid as real
   DECIMAL, not FORMAT()-ed strings
   ================================================================
   Root cause of "AmountPaid looks unformatted at rest, but shows
   numeric formatting once you click the cell" in
   AccountingDevEx/SupplierPaymentDevEx.cs's gridViewMaster (and the
   same latent bug in every other caller of this SP): the EXPENSE
   branch wrapped ActualCost/Balance/AmountPaid in FORMAT(...,'N2'),
   which returns NVARCHAR, not a number. A GridColumn's
   DisplayFormat.FormatType=Numeric can't numeric-format an
   already-string cell value at rest — it just shows the raw string.
   The column's ColumnEdit (a numeric SpinEdit) DOES parse and
   reformat it correctly, but only while the cell is actively being
   edited — hence "only looks numeric when clicked."

   The PURCHASE branch has the same FORMAT() anti-pattern for
   ActualCost/Balance (AmountPaid there happens to dodge it, since
   it's hardcoded to a literal 0 via CAST(...AS DECIMAL(12,2))).

   Per CLAUDE.md's "Reporting Quantity/Amount columns must be
   numeric" convention: SQL side must return real numeric types,
   never FORMAT()-ed to VARCHAR/NVARCHAR. This script fixes all
   three columns in both branches to CAST(...AS DECIMAL(12,2))
   instead, matching the type the SP's own "no branch selected"
   dummy result set already declares (CAST(NULL AS DECIMAL(12,2))),
   so every branch is now type-consistent.

   Blast radius checked before writing this: 4 callers —
   AccountingDevEx/SupplierPaymentDevEx.cs, VoucheringManualFrm.cs,
   HOFormsDevEx/SupplierPaymentDevEx.cs (same bug, unfixed on the
   C# side too — not touched by this script), and legacy
   HOForms/TransactionPayment.cs (writes Math.Round(x,2).ToString()
   back into the "Balance" grid column today — a well-formed numeric
   string still converts cleanly into a DECIMAL-typed DataColumn, so
   this is expected to keep working unchanged).

   No column list, parameter, or WHERE-clause logic changed — only
   the three FORMAT() wrappers, PLUS one small disclosed addition:
   the PURCHASE branch's ActualCost/Balance now also get an
   ISNULL(x,0) guard, matching the EXPENSE branch's existing
   ISNULL(FORMAT(...),0) pattern and this proc's own header title
   ("ISNULL guards on all 6 columns" — previously true for EXPENSE
   but not PURCHASE). Currently a no-op in practice (APACCOUNTS.
   ActualCost/Balance are NOT NULL columns with zero NULL rows
   today, confirmed against live data before writing this), kept as
   defensive consistency rather than dropped, since it aligns with
   what this proc already states its own intent to be.

   Deploy to CORECSERP_002_DEV first; mirror to CORECSJFC2026_STAGING
   only after confirming with the
   user, per project convention.
   ================================================================ */

IF OBJECT_ID('dbo.splist_Accounts', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.splist_Accounts', 'splist_Accounts_OLD_20260915220000';
GO

-- Pin these explicitly rather than depend on the deploying session's
-- ambient defaults - the live proc has both baked in (uses_ansi_nulls=1,
-- uses_quoted_identifier=1 per sys.sql_modules).
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE PROCEDURE [dbo].[splist_Accounts]
    @parmsupplierid VARCHAR(30),
    @parmispurchase BIT,
    @parmisexpense  BIT
AS
BEGIN
    SET NOCOUNT ON;

    IF (@parmispurchase = 0 AND @parmisexpense = 0)
    BEGIN
        SELECT
            CAST(NULL AS BIGINT)        AS SequenceNumber,
            CAST('NONE' AS VARCHAR(15)) AS Pay,
            CAST(NULL AS VARCHAR(10))   AS ShipmentNo,
            CAST(NULL AS VARCHAR(5))    AS BranchCode,
            CAST(NULL AS VARCHAR(150))  AS ReferenceNo,
            CAST(NULL AS BIGINT)        AS BatchReferenceID,
            CAST(NULL AS VARCHAR(150))  AS InvoiceNo,
            CAST(NULL AS DATE)          AS InvoiceDate,
            CAST(NULL AS VARCHAR(5000)) AS Description,
            CAST(NULL AS DECIMAL(12,2)) AS ActualCost,
            CAST(NULL AS DECIMAL(12,2)) AS Balance,
            CAST(0 AS DECIMAL(12,2))    AS AmountPaid,
            CAST(0 AS DECIMAL(12,2))    AS Variance,
            CAST(0 AS DECIMAL(12,2))    AS EWTAmount,
            CAST(0 AS DECIMAL(12,2))    AS DiscountAmount,
            CAST(0 AS DECIMAL(12,2))    AS ReturnAllowances,
            CAST(NULL AS VARCHAR(30))   AS Type
        WHERE 1=0;
        RETURN;
    END;

    -- PURCHASE
    IF (@parmispurchase = 1)
    BEGIN
        SELECT
            CAST(a.SequenceNo        AS BIGINT)        AS SequenceNumber,
            CAST('NONE'              AS VARCHAR(15))   AS Pay,
            a.ShipmentNo,
            b.BranchCode,
            CAST(a.InvoiceNo         AS VARCHAR(150))  AS ReferenceNo,
            CAST(0                   AS BIGINT)         AS BatchReferenceID,
            CAST(a.InvoiceNo         AS VARCHAR(150))  AS InvoiceNo,
            a.InvoiceDate,
            ISNULL(CAST(a.InvoiceNo  AS VARCHAR(50)),' ') AS Description,
            -- FIX: real DECIMAL, not FORMAT()-ed NVARCHAR - see header comment.
            CAST(ISNULL(a.ActualCost,0) AS DECIMAL(12,2)) AS ActualCost,
            CAST(ISNULL(a.Balance,0)    AS DECIMAL(12,2)) AS Balance,
            CAST(0  AS DECIMAL(12,2)) AS AmountPaid,
            CAST(0  AS DECIMAL(12,2)) AS Variance,
            CAST(0  AS DECIMAL(12,2)) AS EWTAmount,
            CAST(0  AS DECIMAL(12,2)) AS DiscountAmount,
            CAST(NULL AS VARCHAR(20)) AS DiscountAccountCode,
            CAST(0  AS DECIMAL(12,2)) AS ReturnAllowances,
            CAST('PURCHASE' AS VARCHAR(30)) AS Type
        FROM  dbo.APACCOUNTS a
        INNER JOIN POSUMMARY b ON a.ShipmentNo = b.ShipmentNo
        WHERE a.PayStatus   IN ('UNPAID','PARTIAL')
          AND a.Balance       > 0
          AND a.SupplierID    = @parmsupplierid
        ORDER BY a.InvoiceDate, a.InvoiceNo;
        RETURN;
    END;

    -- EXPENSE - one row per ExpenseSummary invoice
    IF (@parmisexpense = 1)
    BEGIN
        SELECT
            CAST(es.BatchReferenceID AS BIGINT)         AS SequenceNumber,
            CAST('NONE'              AS VARCHAR(15))    AS Pay,
            CAST(''                  AS VARCHAR(10))    AS ShipmentNo,
            (SELECT TOP 1 em2.BranchCode
             FROM   ExpenseMaster em2
             WHERE  em2.SupplierID       = es.SupplierID
               AND  em2.InvoiceNo        = es.InvoiceNo
               AND  em2.BatchReferenceID = es.BatchReferenceID
             ORDER BY em2.TRN_SEQ_NO)    AS BranchCode,
            CAST(es.ReferenceNumber      AS VARCHAR(150)) AS ReferenceNo,
            es.BatchReferenceID,
            CAST(es.InvoiceNo            AS VARCHAR(150)) AS InvoiceNo,
            es.ExpenseDate               AS InvoiceDate,
            es.Description,
            -- FIX: real DECIMAL, not FORMAT()-ed NVARCHAR - see header comment.
            -- Original gross amount
            CAST(ISNULL(es.Amount,0) AS DECIMAL(12,2)) AS ActualCost,
            -- Remaining balance to pay
            CAST(ISNULL(es.Balance, ISNULL(es.Amount,0)) AS DECIMAL(12,2)) AS Balance,
            CAST(ISNULL(es.AmountPaid,0) AS DECIMAL(12,2)) AS AmountPaid,
            CAST(0 AS DECIMAL(12,2))                                         AS Variance,

            -- REMAINING deductions - all ISNULL-guarded
            -- EWTAmount remaining = Total EWT - already withheld
            -- ISNULL on both sides: if either is NULL, treat as 0
            -- Result is clamped to 0 (never negative)
            CASE WHEN ISNULL(es.EWTAmount,0) - ISNULL(es.EWTWithheld,0) < 0
                 THEN 0
                 ELSE ISNULL(es.EWTAmount,0) - ISNULL(es.EWTWithheld,0)
            END                                                              AS EWTAmount,

            -- Discount remaining
            CASE WHEN ISNULL(es.DiscountAmount,0) - ISNULL(es.DiscountWithheld,0) < 0
                 THEN 0
                 ELSE ISNULL(es.DiscountAmount,0) - ISNULL(es.DiscountWithheld,0)
            END                                                              AS DiscountAmount,

            CAST(NULL AS VARCHAR(20)) AS DiscountAccountCode,
            -- Offset/Return remaining
            CASE WHEN ISNULL(es.OffsetAmount,0) - ISNULL(es.OffsetWithheld,0) < 0
                 THEN 0
                 ELSE ISNULL(es.OffsetAmount,0) - ISNULL(es.OffsetWithheld,0)
            END                                                              AS ReturnAllowances,

            CAST('EXPENSE' AS VARCHAR(30))                                   AS Type
        FROM dbo.ExpenseSummary es
        WHERE es.SupplierID  = @parmsupplierid
          AND es.Status      NOT IN ('PAID','VOID','CANCELLED','FOR APPROVAL','FULLYPAID')
          AND ISNULL(es.Balance, ISNULL(es.Amount, 0)) > 0
        ORDER BY es.ExpenseDate, es.BatchReferenceID;
        RETURN;
    END;
END;
GO
