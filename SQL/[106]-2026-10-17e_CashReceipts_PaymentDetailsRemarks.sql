/* ================================================================
   [106] 2026-10-17e  Cash Receipts report: the payment details under Remarks
   ================================================================
   User (2026-10-17): "when doing posting of client payment we input the details either the cash, check or online. that
   details should also display in cash receipts reports. you can concatenate it under Remarks column".

   RULES
   - funcview_CustomerCashReceipts (POS Sales Report > Cash Receipts, also its Excel export) returns a new LAST column
     Remarks (VARCHAR(2000)) = one text per payment, parts joined with ' | ':
       CASH payments: 'CASH'
       each cheque (TransactionCheque, in SequenceNo order, '; ' between): 'CHECK no / bank / cheque date / name / amount'
       each online deposit (TransactionOnline): 'ONLINE bank / ref no. / deposited date'
       each card (TransactionCreditCard, none today): 'CARD bank / ****last 4 / approval'
       then the remarks typed on the payment (PaymentHeader.Remarks), when not blank.
     Blank parts are left out. Every row of a payment (one per invoice line) shows the same text, like TotalAmount.
   - Nothing else changes: same rows, same other columns in the same order (old exes keep their positions; the screen
     reads SELECT * by name).

   Measured first (2026-10-17, PRODUCTION read-only): 4,988 CASH payments (81 with remarks), 961 CHECK (each one cheque
   row with no. / bank / date / name / amount; 818 with remarks), 1,081 ONLINE (each one row: bank + deposit date, the
   reference mostly blank; 242 with remarks), 0 card rows.
   Guard: funcview_CustomerCashReceipts = the [104] text (9AD4568B…). **Needs [104] first** on STAGING / PRODUCTION
   ([104] recreates the same function from the pre-[104] text). Backup _OLD_10172026220000. Anchor patch (2 anchors).
   Exe: no change needed (the new column shows with the rest); the new exe gives it a caption / width.
   Run in ONE connection with no open transaction.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET LOCK_TIMEOUT 10000;
GO

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[106] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.funcview_CustomerCashReceipts') IS NULL
BEGIN
    RAISERROR('[106] stopped: funcview_CustomerCashReceipts does not exist here; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.funcview_CustomerCashReceipts')), N'') LIKE '%[[]106]%'
BEGIN
    RAISERROR('[106] already applied in this database; nothing changed.', 10, 1);
    SET NOEXEC ON;
END
ELSE IF ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.funcview_CustomerCashReceipts')), N'') NOT LIKE '%[[]104]%'
BEGIN
    RAISERROR('[106] stopped: needs [104] first (funcview_CustomerCashReceipts is not the [104] text); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.funcview_CustomerCashReceipts_OLD_10172026220000') IS NOT NULL
BEGIN
    RAISERROR('[106] stopped: the backup _OLD_10172026220000 already exists; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.funcview_CustomerCashReceipts')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '9AD4568B971A6710B7D997E3FF8FF21ACBFD62AB7240E5A5E58441FA3B3175D9'
BEGIN
    RAISERROR('[106] stopped: funcview_CustomerCashReceipts is not the text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[106] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
GO

IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.funcview_CustomerCashReceipts', 'funcview_CustomerCashReceipts_OLD_10172026220000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE FUNCTION [dbo].[funcview_CustomerCashReceipts]
(
    @datefrom       DATE,
    @dateto         DATE,
    @dateFilterType CHAR(1),        -- 'I' = ARPaymentDetails.InvoiceDate, 'P' = PaymentHeader.PaymentDate select * FROM ARPaymentDetails
    @parmbranchcode VARCHAR(10)     -- NEW 2026-09-25c: NULL / '' / 'ALL' = all branches
)
RETURNS TABLE
AS
RETURN
(
        WITH aa AS
        (
            SELECT
                apd.PaymentHeaderID,
                apd.CustomerKey,
                apd.DebitGLCode,
                apd.InvoiceNo,
                apd.InvoiceDate,
                -- CHANGED 2026-09-25c: OFFSET and EWT are deducted (non-cash).
                -- [104] 2026-10-17: Other Collections lines are cash received too (their InvoiceNo holds the line's remarks)
                SUM(CASE WHEN apd.PaymentType IN ('INVOICE PAYMENT', 'OVERPAY','OVERPAYINCOME','SERVICES','OTHER COLLECTION') THEN apd.Amount
                         WHEN apd.PaymentType IN ('OFFSET', 'EWT','DISCOUNT')              THEN -apd.Amount
                         ELSE 0 END) AS InvoicePaymentAmount,
                SUM(CASE WHEN apd.PaymentType = 'EWT' THEN apd.Amount ELSE 0 END) AS EwtAmount,
                SUM(CASE WHEN apd.PaymentType = 'DISCOUNT' THEN apd.Amount ELSE 0 END) AS DiscountAmount
            FROM ARPaymentDetails apd
            WHERE (apd.ErrorTag IS NULL OR apd.ErrorTag <> 1)
              AND (
                    (@dateFilterType = 'I'
                     AND apd.InvoiceDate >= @datefrom
                     AND apd.InvoiceDate < DATEADD(DAY, 1, @dateto))
                 OR (@dateFilterType = 'P'
                     AND EXISTS (
                            SELECT 1
                            FROM PaymentHeader ph
                            WHERE ph.PaymentHeaderID = apd.PaymentHeaderID
                              AND ph.PaymentDate >= @datefrom
                              AND ph.PaymentDate < DATEADD(DAY, 1, @dateto)
                         ))
                  )
            GROUP BY
                apd.PaymentHeaderID,
                apd.CustomerKey,
                apd.DebitGLCode,
                apd.InvoiceNo,
                apd.InvoiceDate
        )
        SELECT a.CustomerKey, b.InvoiceDate, c.CustomerName, a.ControlNo, d.Description AS Bank, a.PaymentDate, a.CRNo,
               a.TotalAmount,
               b.InvoicePaymentAmount,
               b.InvoiceNo,
               b.EwtAmount,
               b.DiscountAmount,
               a.PaymentType, c.AccountOfficer AS SalesPerson,
               c.BranchCode,                              -- NEW 2026-09-25c
               -- [106] 2026-10-17 (user): the payment details typed on Client Payments (cash / cheque / online / card) and
               --       the payment's remarks, in one text column, LAST (old exes keep their column positions)
               CAST(ISNULL(pm.Details, '') AS VARCHAR(2000)) AS Remarks
        FROM PaymentHeader a
        INNER JOIN aa b
            ON a.PaymentHeaderID = b.PaymentHeaderID
        INNER JOIN Customers c
            ON a.CustomerKey = c.CustomerKey
        INNER JOIN ChartOfAccounts d
            ON b.DebitGLCode = d.AccountCode
        -- [106] one text per payment: 'CASH' / each cheque 'CHECK no / bank / date / name / amount' / each online deposit
        --       'ONLINE bank / ref / deposited date' / each card 'CARD bank / ****last4 / approval', then the remarks
        OUTER APPLY (
            SELECT CONCAT_WS(' | ',
                       CASE WHEN a.PaymentType = 'CASH' THEN 'CASH' END,
                       (SELECT STRING_AGG(CONCAT_WS(' / ', 'CHECK ' + ISNULL(NULLIF(LTRIM(RTRIM(q.CheckNo)), ''), '(no.)'),
                                                    NULLIF(LTRIM(RTRIM(q.CheckBankName)), ''), CONVERT(VARCHAR(10), q.CheckDate, 120),
                                                    NULLIF(LTRIM(RTRIM(q.CheckName)), ''), CONVERT(VARCHAR(30), CAST(q.CheckAmount AS MONEY), 1)), '; ')
                               WITHIN GROUP (ORDER BY q.SequenceNo)
                        FROM dbo.TransactionCheque AS q WHERE q.PaymentHeaderID = a.PaymentHeaderID),
                       (SELECT STRING_AGG(CONCAT_WS(' / ', 'ONLINE ' + ISNULL(NULLIF(LTRIM(RTRIM(o.BankName)), ''), ''),
                                                    'ref ' + NULLIF(LTRIM(RTRIM(o.BankRefNumber)), ''),
                                                    'deposited ' + CONVERT(VARCHAR(10), o.DateDeposit, 120)), '; ')
                               WITHIN GROUP (ORDER BY o.SequenceNumber)
                        FROM dbo.TransactionOnline AS o WHERE o.PaymentHeaderID = a.PaymentHeaderID),
                       (SELECT STRING_AGG(CONCAT_WS(' / ', 'CARD ' + ISNULL(NULLIF(LTRIM(RTRIM(k.CardBankName)), ''), ''),
                                                    '****' + NULLIF(RIGHT(LTRIM(RTRIM(k.CardNumber)), 4), ''),
                                                    'approval ' + NULLIF(LTRIM(RTRIM(k.ApprovalCode)), '')), '; ')
                               WITHIN GROUP (ORDER BY k.SequenceNo)
                        FROM dbo.TransactionCreditCard AS k WHERE k.PaymentHeaderID = a.PaymentHeaderID),
                       NULLIF(LTRIM(RTRIM(a.Remarks)), '')) AS Details
        ) AS pm
        WHERE (NULLIF(LTRIM(RTRIM(ISNULL(@parmbranchcode, ''))), '') IS NULL
               OR @parmbranchcode = 'ALL'
               OR c.BranchCode = @parmbranchcode)
);
GO

------------------------------------------------------------------
-- Post-check: marker, backup, same rows as before (this month and last), every other column unchanged
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400), @from DATE = DATEADD(MONTH, -1, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)), @to DATE = EOMONTH(GETDATE());
IF ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.funcview_CustomerCashReceipts')), N'') NOT LIKE '%[[]106]%'
    SET @msg = N'funcview_CustomerCashReceipts is not the [106] text';
ELSE IF OBJECT_ID('dbo.funcview_CustomerCashReceipts_OLD_10172026220000') IS NULL
    SET @msg = N'the backup is missing';
ELSE IF EXISTS (SELECT CustomerKey, InvoiceDate, CustomerName, ControlNo, Bank, PaymentDate, CRNo, TotalAmount, InvoicePaymentAmount, InvoiceNo, EwtAmount, DiscountAmount, PaymentType, SalesPerson, BranchCode
                FROM dbo.funcview_CustomerCashReceipts(@from, @to, 'P', NULL)
                EXCEPT
                SELECT CustomerKey, InvoiceDate, CustomerName, ControlNo, Bank, PaymentDate, CRNo, TotalAmount, InvoicePaymentAmount, InvoiceNo, EwtAmount, DiscountAmount, PaymentType, SalesPerson, BranchCode
                FROM dbo.funcview_CustomerCashReceipts_OLD_10172026220000(@from, @to, 'P', NULL))
     OR (SELECT COUNT(*) FROM dbo.funcview_CustomerCashReceipts(@from, @to, 'P', NULL))
        <> (SELECT COUNT(*) FROM dbo.funcview_CustomerCashReceipts_OLD_10172026220000(@from, @to, 'P', NULL))
    SET @msg = N'the report rows changed';

IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[106] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59897, @msg, 1;
END

COMMIT TRANSACTION;
PRINT '[106] committed: Cash Receipts returns the payment details under Remarks (last column).';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
