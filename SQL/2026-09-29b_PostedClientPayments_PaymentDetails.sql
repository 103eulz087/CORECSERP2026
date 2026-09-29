/* ================================================================
   2026-09-29b: sp_GetPostedClientPayments -- add payment-method details
   (AccountingDevEx/ClientPaymentsDevExAcctg.cs, FULLPAID INVOICE tab,
   LoadPostedClientPayments).
   ================================================================
   The posting screen stores each payment's method details, keyed by
   PaymentHeaderID, in:
     CASH   -> TransactionCashCollection
     CHECK  -> TransactionCheque  (CheckNo, CheckName, CheckBankName, CheckDate, CheckAmount)
     ONLINE -> TransactionOnline  (BankRefNumber, BankName, DateDeposit)
   and the receiving account in ARPaymentDetails.DebitGLCode.

   NEW columns (appended after the existing ones -- existing columns,
   filters, order and BlockedReason are unchanged):
     PaymentDetails  one-line summary, e.g.
                       CASH   - CR# 12345
                       CHECK  - #000123 BDO dated 2026-09-10 (Juan Cruz)
                       ONLINE - Ref ABC123 BPI deposited 2026-09-11
     DepositedTo     DebitGLCode + ' - ' + ChartOfAccounts.Description
     CheckNo, CheckName, CheckBank, CheckDate, CheckAmount (CHECK only)
     OnlineRefNo, OnlineBank, DepositDate                  (ONLINE only)
   Each is NULL when it doesn't apply. OUTER APPLY TOP 1 per source so a
   payment can never be duplicated (checked on COREX001: every payment has
   at most one cheque/online/cash row and one distinct DebitGLCode).

   Only caller: AccountingDevEx/ClientPaymentsDevExAcctg.cs (binds by
   column name). Deploy to COREX001 (DEV) first; CORECSJFC2026_STAGING
   only after the user confirms.
   ================================================================ */

IF OBJECT_ID('dbo.sp_GetPostedClientPayments', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetPostedClientPayments', 'sp_GetPostedClientPayments_OLD_09292026140000';
GO

CREATE PROCEDURE [dbo].[sp_GetPostedClientPayments]
(
    @CustomerKey CHAR(8),
    @DateFrom    DATE = NULL,
    @DateTo      DATE = NULL   -- INCLUSIVE upper bound; NULL = no upper bound.
                               -- The +1-day exclusive conversion happens here,
                               -- not in the caller, so a future caller can't
                               -- get the boundary wrong by passing a plain
                               -- inclusive date (sp-reviewer finding).
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ph.PaymentHeaderID,
        ph.CustomerKey,
        ph.ReferenceNo,
        ph.ControlNo,
        ph.CRNo,
        ph.PaymentType,
        FORMAT(ph.TotalAmount,'N2') AS TotalAmount,
        ph.PaymentDate,
        ph.Remarks,
        ph.CreatedBy,
        ph.CreatedDate,
        ph.Status,
        ph.ReversedBy,
        ph.ReversedDate,
        CASE WHEN ph.Status = 'REVERSED' THEN 'Already Reversed' ELSE NULL END AS BlockedReason,

        -- NEW 2026-09-29b: payment-method details
        CASE ph.PaymentType
            WHEN 'CASH' THEN 'CASH' + ISNULL(' - CR# ' + NULLIF(LTRIM(RTRIM(ph.CRNo)), ''), '')
            WHEN 'CHECK' THEN 'CHECK'
                 + ISNULL(' - #' + NULLIF(LTRIM(RTRIM(chq.CheckNo)), ''), '')
                 + ISNULL(' ' + NULLIF(LTRIM(RTRIM(chq.CheckBankName)), ''), '')
                 + ISNULL(' dated ' + CONVERT(VARCHAR(10), chq.CheckDate, 23), '')
                 + ISNULL(' (' + NULLIF(LTRIM(RTRIM(chq.CheckName)), '') + ')', '')
            WHEN 'ONLINE' THEN 'ONLINE'
                 + ISNULL(' - Ref ' + NULLIF(LTRIM(RTRIM(onl.BankRefNumber)), ''), '')
                 + ISNULL(' ' + NULLIF(LTRIM(RTRIM(onl.BankName)), ''), '')
                 + ISNULL(' deposited ' + CONVERT(VARCHAR(10), onl.DateDeposit, 23), '')
            ELSE ph.PaymentType
        END AS PaymentDetails,
        dep.DebitGLCode + ISNULL(' - ' + coa.Description, '') AS DepositedTo,
        chq.CheckNo,
        chq.CheckName,
        chq.CheckBankName                  AS CheckBank,
        chq.CheckDate,
        CAST(chq.CheckAmount AS DECIMAL(18,2)) AS CheckAmount,
        onl.BankRefNumber                  AS OnlineRefNo,
        onl.BankName                       AS OnlineBank,
        onl.DateDeposit                    AS DepositDate
    FROM dbo.PaymentHeader ph
    OUTER APPLY (SELECT TOP 1 c.CheckNo, c.CheckName, c.CheckBankName, c.CheckDate, c.CheckAmount
                 FROM dbo.TransactionCheque c
                 WHERE c.PaymentHeaderID = ph.PaymentHeaderID
                 ORDER BY c.SequenceNo) chq
    OUTER APPLY (SELECT TOP 1 o.BankRefNumber, o.BankName, o.DateDeposit
                 FROM dbo.TransactionOnline o
                 WHERE o.PaymentHeaderID = ph.PaymentHeaderID
                 ORDER BY o.SequenceNumber) onl
    OUTER APPLY (SELECT TOP 1 d.DebitGLCode
                 FROM dbo.ARPaymentDetails d
                 WHERE d.PaymentHeaderID = ph.PaymentHeaderID
                   AND NULLIF(LTRIM(RTRIM(d.DebitGLCode)), '') IS NOT NULL) dep
    LEFT JOIN dbo.ChartOfAccounts coa ON coa.AccountCode = dep.DebitGLCode
    WHERE ph.CustomerKey = @CustomerKey
      AND (@DateFrom IS NULL OR ph.PaymentDate >= @DateFrom)
      AND (@DateTo   IS NULL OR ph.PaymentDate <  DATEADD(DAY, 1, @DateTo))
    ORDER BY ph.PaymentDate DESC, ph.PaymentHeaderID DESC;
END
GO
