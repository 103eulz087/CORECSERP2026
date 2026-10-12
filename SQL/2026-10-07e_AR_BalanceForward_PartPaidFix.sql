/* ================================================================
   2026-10-07e: AR balance forward loaded at the invoice amount
   ================================================================
   Data fix, no object changes. Source: ARAGING3$ (the Peachtree AR aging
   upload of 2026-09-11: INVOICEAMOUNT = original invoice, BALANCE = what
   was still unpaid on 2026-07-31).

   Problem: for invoices that were partly paid in Peachtree (BALANCE <>
   INVOICEAMOUNT), the balance forward was loaded as
     TransactionChargeSales.TotalAmount = INVOICEAMOUNT  (should be BALANCE)
     TransactionChargeSales.Balance     = BALANCE        (right, until a payment)
     ClientLedger BF row Debit          = INVOICEAMOUNT  (should be BALANCE)
   sp_AddPaymentClient recomputes Balance = TotalAmount - (AmountPaid + EWT +
   Discount + Offset), so the first payment in this system brought the part
   already paid in Peachtree back.
   Example: I-072260 (00005937), invoice 6,840.50, Peachtree balance 2,640.50.
   The customer paid 2,640.50 here; Balance became 4,200.00 instead of 0.00.
   The customer ledger (statements, ClientAccounts.AccountBalance) carried the
   full invoice amounts: DEV +33,996,341.98 on 760 rows. Negative balances
   (customer credits) were posted as a debit of the full invoice, e.g.
   B_045745: Debit 65,894.50 instead of Credit 2,138.60.

   Fix, per balance-forward row with TotalAmount <> BALANCE (matched on
   InvoiceNo + TransactionDate; invoice numbers are unique):
     TotalAmount = BALANCE
     Balance     = BALANCE - (AmountPaid + EWT + Discount + Offset)
     PayStatus   = unchanged when nothing was paid here; FULLYPAID when the
                   new balance is <= 0; else PARTIAL
     ClientLedger BF row: Debit = BALANCE (> 0) or Credit = -BALANCE (< 0),
                   TotalAmount = BALANCE. trg_ClientLedger_Recalc recomputes
                   each customer's running balance and AccountBalance.
   A row paid MORE than its Peachtree balance keeps a negative Balance (the
   excess is the customer's credit) and is listed at the end.
   The GL is not touched: the opening ticket was built from the balances.

   Backups (the script stops if any of them exists):
     TransactionChargeSales_BFFix_Backup_20261007   (the rows in scope)
     ClientLedger_BFFix_Backup_20261007             (their BF ledger rows)
     ClientAccounts_BFFix_Backup_20261007           (their customers)
   One transaction with post-checks; anything unexpected rolls it all back.
   ================================================================ */

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('dbo.ARAGING3$', 'U') IS NULL
    THROW 93201, 'ARAGING3$ is missing on this database.', 1;
IF OBJECT_ID('dbo.TransactionChargeSales_BFFix_Backup_20261007', 'U') IS NOT NULL
   OR OBJECT_ID('dbo.ClientLedger_BFFix_Backup_20261007', 'U') IS NOT NULL
   OR OBJECT_ID('dbo.ClientAccounts_BFFix_Backup_20261007', 'U') IS NOT NULL
    THROW 93202, 'A backup table of this script already exists: it has been run here before.', 1;

BEGIN TRANSACTION;

    -- 1. scope
    SELECT  a.CustomerKey, a.InvoiceNo, a.TransactionDate,
            CAST(b.BALANCE AS DECIMAL(18,2))       AS BFBalance,
            CAST(ISNULL(a.AmountPaid, 0) + ISNULL(a.EWTAmount, 0) + ISNULL(a.DiscountAmount, 0) + ISNULL(a.OffsetAmount, 0) AS DECIMAL(18,2)) AS Settled
    INTO    #Fix
    FROM    dbo.TransactionChargeSales AS a WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN dbo.ARAGING3$ AS b
            ON  b.INVOICENO       = a.InvoiceNo
            AND b.TRANSACTIONDATE = a.TransactionDate
    WHERE   a.TotalAmount <> CAST(b.BALANCE AS DECIMAL(18,2));

    DECLARE @n INT = @@ROWCOUNT, @msg NVARCHAR(400);

    IF EXISTS (SELECT 1 FROM #Fix GROUP BY InvoiceNo HAVING COUNT(*) > 1)
        THROW 93203, 'An invoice number appears more than once in scope.', 1;

    -- every row must have exactly one BF ledger row under the same customer
    IF EXISTS (SELECT 1 FROM #Fix AS f
               WHERE (SELECT COUNT(*) FROM dbo.ClientLedger AS l
                      WHERE l.TransCode = 'BF' AND l.InvoiceNo = f.InvoiceNo AND l.AccountKey = f.CustomerKey) <> 1)
    BEGIN
        SELECT @msg = N'Rows without exactly one BF ledger row: '
                    + CAST(COUNT(*) AS NVARCHAR(10)) + N', e.g. ' + MIN(f.InvoiceNo)
        FROM #Fix AS f
        WHERE (SELECT COUNT(*) FROM dbo.ClientLedger AS l
               WHERE l.TransCode = 'BF' AND l.InvoiceNo = f.InvoiceNo AND l.AccountKey = f.CustomerKey) <> 1;
        THROW 93204, @msg, 1;
    END;

    -- 2. backups
    SELECT a.* INTO dbo.TransactionChargeSales_BFFix_Backup_20261007
    FROM dbo.TransactionChargeSales AS a
    INNER JOIN #Fix AS f ON f.InvoiceNo = a.InvoiceNo AND f.TransactionDate = a.TransactionDate;

    SELECT l.* INTO dbo.ClientLedger_BFFix_Backup_20261007
    FROM dbo.ClientLedger AS l
    INNER JOIN #Fix AS f ON f.InvoiceNo = l.InvoiceNo AND f.CustomerKey = l.AccountKey
    WHERE l.TransCode = 'BF';

    SELECT c.* INTO dbo.ClientAccounts_BFFix_Backup_20261007
    FROM dbo.ClientAccounts AS c
    WHERE c.AccountKey IN (SELECT CustomerKey FROM #Fix);

    -- 3. invoices
    UPDATE a
    SET     TotalAmount = f.BFBalance,
            Balance     = f.BFBalance - f.Settled,
            PayStatus   = CASE WHEN f.Settled = 0                 THEN a.PayStatus
                               WHEN f.BFBalance - f.Settled <= 0  THEN 'FULLYPAID'
                               ELSE 'PARTIAL' END
    FROM    dbo.TransactionChargeSales AS a
    INNER JOIN #Fix AS f ON f.InvoiceNo = a.InvoiceNo AND f.TransactionDate = a.TransactionDate;

    IF @@ROWCOUNT <> @n THROW 93205, 'Invoice update count differs from the scope.', 1;

    -- 4. customer ledger (the trigger recomputes running balances + AccountBalance)
    UPDATE  l
    SET     Debit       = CASE WHEN f.BFBalance > 0 THEN f.BFBalance ELSE 0 END,
            Credit      = CASE WHEN f.BFBalance < 0 THEN -f.BFBalance ELSE 0 END,
            TotalAmount = f.BFBalance
    FROM    dbo.ClientLedger AS l
    INNER JOIN #Fix AS f ON f.InvoiceNo = l.InvoiceNo AND f.CustomerKey = l.AccountKey
    WHERE   l.TransCode = 'BF';

    IF @@ROWCOUNT <> @n THROW 93206, 'Ledger update count differs from the scope.', 1;

    -- 5. post-checks
    IF EXISTS (SELECT 1 FROM dbo.TransactionChargeSales AS a
               INNER JOIN dbo.ARAGING3$ AS b ON b.INVOICENO = a.InvoiceNo AND b.TRANSACTIONDATE = a.TransactionDate
               WHERE a.TotalAmount <> CAST(b.BALANCE AS DECIMAL(18,2)))
        THROW 93207, 'Some balance-forward invoices still differ from ARAGING3$.', 1;

    IF EXISTS (SELECT 1 FROM dbo.ClientLedger AS l
               INNER JOIN dbo.ARAGING3$ AS b ON b.INVOICENO = l.InvoiceNo
               WHERE l.TransCode = 'BF' AND CAST(l.Debit - l.Credit AS DECIMAL(18,2)) <> CAST(b.BALANCE AS DECIMAL(18,2)))
        THROW 93208, 'Some BF ledger rows still differ from ARAGING3$.', 1;

COMMIT TRANSACTION;

-- Result
SELECT  CASE WHEN f.Settled = 0                THEN '1 nothing paid here'
             WHEN f.BFBalance - f.Settled > 0  THEN '2 partly paid, still open'
             WHEN f.BFBalance - f.Settled = 0  THEN '3 now fully paid'
             ELSE                                   '4 paid more than the Peachtree balance' END AS Category,
        COUNT(*)                         AS Invoices,
        SUM(f.BFBalance)                 AS PeachtreeBalance,
        SUM(f.Settled)                   AS PaidHere,
        SUM(bk.Balance)                  AS BalanceBefore,
        SUM(f.BFBalance - f.Settled)     AS BalanceNow
FROM    #Fix AS f
INNER JOIN dbo.TransactionChargeSales_BFFix_Backup_20261007 AS bk ON bk.InvoiceNo = f.InvoiceNo AND bk.TransactionDate = f.TransactionDate
GROUP BY CASE WHEN f.Settled = 0                THEN '1 nothing paid here'
              WHEN f.BFBalance - f.Settled > 0  THEN '2 partly paid, still open'
              WHEN f.BFBalance - f.Settled = 0  THEN '3 now fully paid'
              ELSE                                   '4 paid more than the Peachtree balance' END
ORDER BY 1;

SELECT  f.CustomerKey, f.InvoiceNo, f.BFBalance AS PeachtreeBalance, f.Settled AS PaidHere, f.BFBalance - f.Settled AS CustomerCredit
FROM    #Fix AS f
WHERE   f.BFBalance - f.Settled < 0
  AND   f.Settled > 0          -- paid here beyond the Peachtree balance (not the Peachtree credits)
ORDER BY f.CustomerKey, f.InvoiceNo;

DROP TABLE #Fix;
