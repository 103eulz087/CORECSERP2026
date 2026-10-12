/* ================================================================
   2026-10-07c: "Bank Reconciliation (Real-Time)" report = the Bank Recon screen
   ================================================================
   sp_rpt_BankReconciliationRealTime (AccountingReportsFormV2). Checked against the
   screen (fn_BankRecon_Figures, script 39) on STAGING 2026-10-07, BDO PESO1 Aug:
   report difference 170,542.54 vs screen 816,883.06, because the report
     * took the GL balance of the picked branch only (888: -14,946,459.51; the screen
       and the user's rule use all branches: -15,933,885.11);
     * left bank-side items (BCM / BDM / BC / NSF / ADB) out (OtherBank fixed 0.00);
     * picked open items by ItemDate instead of by recon period;
     * showed the difference as book - bank (the screen: bank - book).
   Now every figure follows the screen's rules:
     GL balances / receipts / disbursements   all branches (fn_BankRecon_GLBalance rule)
     Bank statement balance                   the header(s) of PeriodEnd = @DateTo
     Open items                               uncleared items of every header of the branch
                                              (all branches if NULL) + account with
                                              PeriodEnd <= @DateTo, reversed / voided out
     Adjusted Bank = Bank Statement + open DIT - open OC
     Adjusted Book = Ending GL + open BCM - open BDM / BC / NSF / ADB
     UnreconciledDifference = Adjusted Bank - Adjusted Book   (0 = reconciled)
   Result sets unchanged; set 3 gains OpenBCM, OpenBankDebits, AdjustedBookBalance at
   the end, and OtherBank now carries the net bank-side items (BCM - debits).
   Backup: _OLD_10072026160000.
   ================================================================ */

IF OBJECT_ID('dbo.sp_rpt_BankReconciliationRealTime', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_BankReconciliationRealTime', 'sp_rpt_BankReconciliationRealTime_OLD_10072026160000';
GO

CREATE PROCEDURE dbo.sp_rpt_BankReconciliationRealTime
(
    @BranchCode  VARCHAR(5) = NULL,
    @AccountCode VARCHAR(20),
    @DateFrom    DATE,
    @DateTo      DATE
)
AS
/*
    The Bank Recon screen's reconciliation as a report (2026-10-07c; see the script header).
    Set 1 account header, set 2 open reconciling items, set 3 summary.
    Callers: HOFormsDevEx/AccountingReportsFormV2.cs ("Bank Reconciliation").
*/
BEGIN
    SET NOCOUNT ON;

    -- ── SET 1: account header ──
    SELECT
         CAST(coa.AccountCode AS VARCHAR(20))           AS AccountCode
        ,CAST(coa.Description AS VARCHAR(256))          AS AccountDescription
        ,CAST(coa.Nature AS CHAR(1))                    AS Nature
        ,CAST(ISNULL(@BranchCode, 'ALL') AS VARCHAR(5)) AS BranchCode
        ,CAST(@DateFrom AS DATE)                        AS DateFrom
        ,CAST(@DateTo   AS DATE)                        AS DateTo
    FROM dbo.ChartOfAccounts AS coa
    WHERE coa.AccountCode = @AccountCode;

    -- ── GL side: all branches (one bank account, one statement) ──
    DECLARE @BeginningGLBalance DECIMAL(19,2), @EndingGLBalance DECIMAL(19,2),
            @CashReceipts DECIMAL(19,2), @CashDisbursements DECIMAL(19,2);
    SELECT @EndingGLBalance = GLBalance FROM dbo.fn_BankRecon_GLBalance(@AccountCode, @DateTo);
    SELECT @BeginningGLBalance = GLBalance FROM dbo.fn_BankRecon_GLBalance(@AccountCode, DATEADD(DAY, -1, @DateFrom));
    SELECT @CashReceipts      = CAST(ISNULL(SUM(ISNULL(td.Debit, 0)), 0) AS DECIMAL(19,2)),
           @CashDisbursements = CAST(ISNULL(SUM(ISNULL(td.Credit, 0)), 0) AS DECIMAL(19,2))
    FROM dbo.TicketDetails AS td
    WHERE td.AccountCode = @AccountCode
      AND td.TicketDate >= @DateFrom
      AND td.TicketDate <  DATEADD(DAY, 1, CAST(@DateTo AS DATETIME));
    DECLARE @OtherGL DECIMAL(19,2) = @EndingGLBalance - @BeginningGLBalance - @CashReceipts + @CashDisbursements;   -- ~0.00 plug

    -- ── Bank statement balance: the header(s) of this period end ──
    DECLARE @BankStatementBal DECIMAL(18,2), @HeaderRowCount INT;
    SELECT @HeaderRowCount = COUNT(*), @BankStatementBal = SUM(ISNULL(h.BankStatementBal, 0))
    FROM dbo.BankReconHeader AS h
    WHERE (@BranchCode IS NULL OR h.BranchCode = @BranchCode)
      AND h.AccountCode = @AccountCode
      AND h.PeriodEnd   = @DateTo;
    IF @HeaderRowCount = 0 SET @BankStatementBal = NULL;

    -- ── open items: the screen's rule (carried forward until cleared) ──
    SELECT b.ReconID, b.BranchCode, b.ItemType, b.ReferenceNo, b.ItemDate, b.Payee, b.Amount, b.Remarks,
           b.SourceModule, b.SourceRef, b.IsResolved
    INTO #Open
    FROM dbo.BankStatementRecon AS b
    INNER JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
    WHERE (@BranchCode IS NULL OR h.BranchCode = @BranchCode)
      AND h.AccountCode = @AccountCode
      AND h.PeriodEnd  <= @DateTo
      AND ISNULL(b.IsResolved, 0) = 0
      AND ISNULL(b.ResolvedReason, '') <> 'REVERSED' AND ISNULL(b.ResolvedReason, '') NOT LIKE 'VOIDED%';

    -- ── SET 2: reconciling items ──
    SELECT ReconID, BranchCode, ItemType, ReferenceNo, ItemDate, Payee, Amount, Remarks, SourceModule, SourceRef, IsResolved
    FROM #Open
    ORDER BY BranchCode, ItemType, ItemDate, ReferenceNo;

    DECLARE @TotalDIT DECIMAL(19,2), @TotalOC DECIMAL(19,2), @OpenBCM DECIMAL(19,2), @OpenBankDebits DECIMAL(19,2);
    SELECT @TotalDIT       = CAST(ISNULL(SUM(CASE WHEN ItemType = 'DIT' THEN Amount ELSE 0 END), 0) AS DECIMAL(19,2)),
           @TotalOC        = CAST(ISNULL(SUM(CASE WHEN ItemType = 'OC'  THEN Amount ELSE 0 END), 0) AS DECIMAL(19,2)),
           @OpenBCM        = CAST(ISNULL(SUM(CASE WHEN ItemType = 'BCM' THEN Amount ELSE 0 END), 0) AS DECIMAL(19,2)),
           @OpenBankDebits = CAST(ISNULL(SUM(CASE WHEN ItemType IN ('BDM', 'BC', 'NSF', 'ADB') THEN Amount ELSE 0 END), 0) AS DECIMAL(19,2))
    FROM #Open;

    DECLARE @AdjustedBankBalance DECIMAL(19,2) = ISNULL(@BankStatementBal, 0) + @TotalDIT - @TotalOC;
    DECLARE @AdjustedBookBalance DECIMAL(19,2) = @EndingGLBalance + @OpenBCM - @OpenBankDebits;

    -- ── SET 3: summary ──
    SELECT
         CAST(@BeginningGLBalance AS DECIMAL(19,2))     AS BeginningGLBalance
        ,CAST(@CashReceipts AS DECIMAL(19,2))           AS CashReceipts
        ,CAST(@CashDisbursements AS DECIMAL(19,2))      AS CashDisbursements
        ,CAST(@OtherGL AS DECIMAL(19,2))                AS OtherGL
        ,CAST(@EndingGLBalance AS DECIMAL(19,2))        AS EndingGLBalance
        ,CAST(@BankStatementBal AS DECIMAL(18,2))       AS BankStatementBalance
        ,CAST(@TotalDIT AS DECIMAL(19,2))               AS TotalDepositsInTransit
        ,CAST(@TotalOC  AS DECIMAL(19,2))               AS TotalOutstandingChecks
        ,CAST(@OpenBCM - @OpenBankDebits AS DECIMAL(19,2)) AS OtherBank
        ,CAST(@AdjustedBankBalance AS DECIMAL(19,2))    AS AdjustedBankBalance
        ,CAST(@AdjustedBankBalance - @AdjustedBookBalance AS DECIMAL(19,2)) AS UnreconciledDifference
        ,CASE WHEN @BankStatementBal IS NULL THEN CAST(0 AS BIT)
              WHEN ABS(@AdjustedBankBalance - @AdjustedBookBalance) < 0.01 THEN CAST(1 AS BIT)
              ELSE CAST(0 AS BIT) END                   AS IsReconciled
        ,CAST(ISNULL(@BranchCode, 'ALL') AS VARCHAR(5)) AS BranchCode
        ,@OpenBCM                                       AS OpenBCM
        ,@OpenBankDebits                                AS OpenBankDebits
        ,CAST(@AdjustedBookBalance AS DECIMAL(19,2))    AS AdjustedBookBalance;
END;
GO
