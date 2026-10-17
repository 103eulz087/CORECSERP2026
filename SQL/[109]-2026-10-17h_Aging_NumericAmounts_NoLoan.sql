/* ================================================================
   [109] 2026-10-17h  Aging report (sp_Aging): numeric amounts, loan payable left out
   ================================================================
   User (2026-10-17): "put aging report in accounting board". The report is Accounting/AgingReports (sp_Aging, types AR /
   AP / AP-EXP); its Main menu button has been hidden, the board is its entry point now.

   CHANGES (nothing else; same columns, same order, same rows apart from the loan):
   - Amount, the age buckets and CustomerCreditLimit come back as DECIMAL(18,2) instead of FORMAT()-ed text, so the grid
     can add them up per customer / supplier and in the footer (CLAUDE.md numeric rule). Empty buckets are NULL (AP used
     to return '' there).
   - AP-EXP leaves out the loan payable (ExpenseSummary.PostingMode 'LOAN', [105]): it is the PROFOOD loan principal
     (20203), not trade AP; same filter [105] puts on the other AP lists. Harmless where [105] isn't installed.
   - Not changed (noted for the accountant): Age counts to today, not to the To date; AR Amount = the invoice amount,
     AP / AP-EXP Amount = the balance; the dates filter on the invoice / expense date.

   Measured first (2026-10-17): sp_Aging hash-identical on DEV / STAGING / PRODUCTION (F40884FA…, 2026-09-10); its only
   caller is Accounting/AgingReports.cs (no SQL object references it). Guard = that hash; backup _OLD_10172026233000.
   Exe: the old exe works on it (unformatted numbers); the new exe formats them and also copes with the old text columns.
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
    RAISERROR('[109] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.sp_Aging', 'P') IS NULL
BEGIN
    RAISERROR('[109] stopped: dbo.sp_Aging is missing; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_Aging')), N'') LIKE '%[[]109]%'
BEGIN
    RAISERROR('[109] already applied in this database; nothing changed.', 10, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.sp_Aging_OLD_10172026233000') IS NOT NULL
BEGIN
    RAISERROR('[109] stopped: the backup sp_Aging_OLD_10172026233000 already exists; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_Aging')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> 'F40884FAA2E0CD711ACBF0E51BA4865EF403007AB1277ACBA60B985A7ADA3630'
BEGIN
    RAISERROR('[109] stopped: sp_Aging is not the text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[109] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
GO

IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.sp_Aging', 'sp_Aging_OLD_10172026233000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE [dbo].[sp_Aging]
	@parmdatefrom date,
	@parmdateto date,
	@parmtype varchar(12)
AS
/*  [109] 2026-10-17: amounts DECIMAL(18,2) (were FORMAT()-ed text, so the grid could not total them); AP-EXP leaves out
    the loan payable (PostingMode 'LOAN', [105]). Backup sp_Aging_OLD_10172026233000. */
BEGIN
SET NOCOUNT ON
	IF @parmtype = 'AR'
	BEGIN

		SELECT
			d.BranchName,
			t.CustomerKey AS CustomerID,
			c.CustomerName,
			CAST(t.TransactionDate AS DATE) AS TransactionDate,
			t.InvoiceNo,
			CAST(t.TotalAmount AS DECIMAL(18,2)) AS Amount,
			DATEDIFF(DAY, t.TransactionDate, GETDATE()) AS Age,

			CASE
				WHEN DATEDIFF(DAY, t.TransactionDate, GETDATE()) <= 30
					THEN CAST(t.Balance AS DECIMAL(18,2))
			END AS [0 to 30],

			CASE
				WHEN DATEDIFF(DAY, t.TransactionDate, GETDATE()) BETWEEN 31 AND 60
					THEN CAST(t.Balance AS DECIMAL(18,2))
			END AS [31 to 60],

			CASE
				WHEN DATEDIFF(DAY, t.TransactionDate, GETDATE()) BETWEEN 61 AND 90
					THEN CAST(t.Balance AS DECIMAL(18,2))
			END AS [61 to 90],

			CASE
				WHEN DATEDIFF(DAY, t.TransactionDate, GETDATE()) > 90
					THEN CAST(t.Balance AS DECIMAL(18,2))
			END AS [Over 90],

			CAST(c.CustomerCreditLimit AS DECIMAL(18,2)) AS CustomerCreditLimit,
			c.Term,
			c.AccountOfficer,
			t.PayStatus AS PaymentStatus

		FROM TransactionChargeSales t
		INNER JOIN Customers c
			ON t.CustomerKey = c.CustomerKey
		INNER JOIN Branches d
			ON c.BranchCode=d.BranchCode

		WHERE t.TransactionDate >= @parmdatefrom
		  AND t.TransactionDate < DATEADD(DAY,1,@parmdateto)
		 AND t.PayStatus NOT IN ('FULLYPAID', 'CANCELLED')
		  AND t.Balance > 0

		ORDER BY t.CustomerKey, t.TransactionDate;

	END
	IF @parmtype = 'AP'
	BEGIN

		SELECT
			a.SupplierID AS SupplierID,
			s.SupplierName,
			a.InvoiceDate AS TransactionDate,
			a.InvoiceNo,
			CAST(a.Balance AS DECIMAL(18,2)) AS Amount,
			DATEDIFF(DAY, a.InvoiceDate, GETDATE()) AS Age,

			CASE
				WHEN DATEDIFF(DAY,a.InvoiceDate,GETDATE()) <= 30
					THEN CAST(a.Balance AS DECIMAL(18,2))
			END AS [0 to 30],

			CASE
				WHEN DATEDIFF(DAY,a.InvoiceDate,GETDATE()) BETWEEN 31 AND 60
					THEN CAST(a.Balance AS DECIMAL(18,2))
			END AS [31 to 60],

			CASE
				WHEN DATEDIFF(DAY,a.InvoiceDate,GETDATE()) BETWEEN 61 AND 90
					THEN CAST(a.Balance AS DECIMAL(18,2))
			END AS [61 to 90],

			CASE
				WHEN DATEDIFF(DAY,a.InvoiceDate,GETDATE()) BETWEEN 91 AND 120
					THEN CAST(a.Balance AS DECIMAL(18,2))
			END AS [91 to 120],

			CASE
				WHEN DATEDIFF(DAY,a.InvoiceDate,GETDATE()) > 120
					THEN CAST(a.Balance AS DECIMAL(18,2))
			END AS [Over 120],
			a.PayStatus AS PaymentStatus

		FROM APAccounts a
		INNER JOIN Supplier s
			ON a.SupplierID = s.SupplierID

		WHERE a.InvoiceDate >= @parmdatefrom
		  AND a.InvoiceDate < DATEADD(DAY,1,@parmdateto)
		  AND a.PayStatus NOT IN ('FULLYPAID', 'CANCELLED')
		  AND a.Balance > 0

		ORDER BY a.SupplierID, a.InvoiceDate;

	END
	IF @parmtype = 'AP-EXP'
	BEGIN

		SELECT
			a.SupplierID AS CustomerID,
			s.SupplierName,
			a.ExpenseDate AS TransactionDate,
			a.InvoiceNo,
			CAST(a.Balance AS DECIMAL(18,2)) AS Amount,
			DATEDIFF(DAY, a.ExpenseDate, GETDATE()) AS Age,

			CASE
				WHEN DATEDIFF(DAY,a.ExpenseDate,GETDATE()) <= 30
					THEN CAST(a.Balance AS DECIMAL(18,2))
			END AS [0 to 30],

			CASE
				WHEN DATEDIFF(DAY,a.ExpenseDate,GETDATE()) BETWEEN 31 AND 60
					THEN CAST(a.Balance AS DECIMAL(18,2))
			END AS [31 to 60],

			CASE
				WHEN DATEDIFF(DAY,a.ExpenseDate,GETDATE()) BETWEEN 61 AND 90
					THEN CAST(a.Balance AS DECIMAL(18,2))
			END AS [61 to 90],

			CASE
				WHEN DATEDIFF(DAY,a.ExpenseDate,GETDATE()) BETWEEN 91 AND 120
					THEN CAST(a.Balance AS DECIMAL(18,2))
			END AS [91 to 120],

			CASE
				WHEN DATEDIFF(DAY,a.ExpenseDate,GETDATE()) > 120
					THEN CAST(a.Balance AS DECIMAL(18,2))
			END AS [Over 120],
			a.Status AS PaymentStatus

		FROM ExpenseSummary a
		INNER JOIN Supplier s
			ON a.SupplierID = s.SupplierID

		WHERE a.Status NOT IN ('FULLYPAID', 'CANCELLED')
		  AND a.Balance > 0
		  AND ISNULL(a.PostingMode, '') <> 'LOAN'   -- [109] the loan payable ([105]) is not trade AP
		  AND a.ExpenseDate >= @parmdatefrom
		  AND a.ExpenseDate < DATEADD(DAY,1,@parmdateto)

		ORDER BY a.SupplierID, a.ExpenseDate;

	END
END
GO

IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_Aging')), N'') NOT LIKE '%[[]109]%'
    SET @msg = N'sp_Aging is not the [109] text';
ELSE IF OBJECT_ID('dbo.sp_Aging_OLD_10172026233000', 'P') IS NULL
    SET @msg = N'the backup is missing';
IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[109] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59897, @msg, 1;
END
COMMIT TRANSACTION;
PRINT '[109] committed: sp_Aging returns numbers; AP-EXP leaves out the loan payable.';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
