/* ================================================================
   [99] 2026-10-16b  Bank Recon: GL movement of a bank account for the
                     "Account Reconciliation Report" export
   ================================================================
   User (2026-10-16): Bank Recon › Export should produce the accountants'
   Peachtree-style ACCOUNT RECONCILIATION REPORT (D:\SQLREF\2.png):

       Beginning GL Balance
       Add: Cash Receipts
       Less: Cash Disbursements
       Add (Less) Other
       Ending GL Balance
       Ending Bank Balance, + deposits in transit (listed), (less) outstanding
       checks (listed), add (less) other (listed), unreconciled difference,
       Ending GL Balance.

   The bank side comes from the screen (the same items as its summary box). This
   new read-only proc gives the GL side, for ONE bank account and the month that
   ends on @PeriodEnd, all branches (the Bank Recon "GL Book Balance" rule,
   fn_BankRecon_GLBalance, 2026-10-07):

     Beginning GL = every TicketDetails line before the 1st of the month;
     each line of the month goes to ONE journal (Peachtree's CRJ / CDJ / GJ), by its
     ticket master (same TicketNumber + BranchCode; else any branch's master):
       RECEIPTS       customer collections: Mnemonic 'OR-%', and the AR tickets with no
                      mnemonic (Origin '888': the 08-01..05 payments and every AR payment
                      reversal, which sp_ReversePaymentClient writes without a mnemonic);
       DISBURSEMENTS  money OUT on payment vouchers and cash advances (Origin 'PV' / 'CA', Mnemonic
                      'PV-%' / 'CASH ADVANCE'): their credit lines, and the debit lines of their REVERSAL
                      tickets. Money IN on such a ticket (a fund transfer into this bank is posted as a
                      cash advance: the receiving bank gets the debit) and its reversal go to OTHER,
                      as Peachtree carried transfers in the general journal;
       OTHER          everything else (Manual JV, expenses, the opening ticket ...).
     Cash Receipts = their debit - credit; Cash Disbursements = their credit - debit;
     Add (Less) Other = their debit - credit. So Beginning + Receipts - Disbursements
     + Other = Ending GL, to the cent, always (reversals net inside their own journal).

   Result sets:
     1. one row: AccountCode, AccountName, PeriodStart, PeriodEnd, BeginningGL,
        CashReceipts, CashDisbursements, OtherNet, EndingGL;
     2. the month's lines (@ResultSet NULL = both sets, 1 = set 1 only, 2 = set 2 only): Journal, TicketDate, BranchCode, TicketNumber,
        ReferenceNumber, ReferenceKey, Mnemonic, Particulars, Debit, Credit
        (the export's second sheet, so the accountant can see what is in each figure).

   New object only (no rename), read-only; nothing else changes. Callers:
   AccountingDevEx/BankReconFormV2.cs (Export › Account Reconciliation Report).
   The exe of 2026-10-16 needs it for that export (the grid export works without it).
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET LOCK_TIMEOUT 10000;
GO

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[99] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.sp_rpt_BankRecon_GLMovement') IS NOT NULL
BEGIN
    RAISERROR('[99] stopped: sp_rpt_BankRecon_GLMovement already exists ([99] already installed?); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[99] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
GO

IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE dbo.sp_rpt_BankRecon_GLMovement
    @AccountCode VARCHAR(20),
    @PeriodEnd   DATE,
    @ResultSet   TINYINT = NULL   -- NULL = both (the exe); 1 = figures only; 2 = lines only (INSERT..EXEC callers, tests)
AS
/*
    [99] 2026-10-16: GL side of the Account Reconciliation Report (see the script header).
    Read-only. All branches. Callers: AccountingDevEx/BankReconFormV2.cs.
*/
BEGIN
    SET NOCOUNT ON;

    DECLARE @PeriodStart DATE = DATEFROMPARTS(YEAR(@PeriodEnd), MONTH(@PeriodEnd), 1);
    DECLARE @NextDay     DATETIME = DATEADD(DAY, 1, CAST(@PeriodEnd AS DATETIME));

    DECLARE @Beginning DECIMAL(18,2) =
        (SELECT CAST(ISNULL(SUM(ISNULL(td.Debit, 0) - ISNULL(td.Credit, 0)), 0) AS DECIMAL(18,2))
         FROM dbo.TicketDetails AS td
         WHERE td.AccountCode = @AccountCode
           AND td.TicketDate < CAST(@PeriodStart AS DATETIME));

    IF OBJECT_ID('tempdb..#Lines') IS NOT NULL DROP TABLE #Lines;
    SELECT
        CASE
            WHEN m.Mnemonic LIKE 'OR-%' OR (m.Mnemonic IS NULL AND m.Origin = '888')         THEN 'RECEIPTS'
            -- vouchers / cash advances: money OUT (a credit line), or the reversal of one (a debit on a REVERSAL ticket);
            -- money IN on such a ticket (a fund transfer into this bank, posted as a cash advance) and its reversal go to OTHER
            WHEN (m.Origin IN ('PV', 'CA') OR m.Mnemonic LIKE 'PV-%' OR m.Mnemonic = 'CASH ADVANCE')
             AND (   (ISNULL(td.Credit, 0) <> 0 AND ISNULL(m.Product, '') NOT LIKE 'REVERSAL%')
                  OR (ISNULL(td.Debit, 0)  <> 0 AND ISNULL(m.Product, '') LIKE 'REVERSAL%'))                         THEN 'DISBURSEMENTS'
            ELSE 'OTHER'
        END                                                AS Journal,
        td.TicketDate,
        td.BranchCode,
        td.TicketNumber,
        m.ReferenceNumber,
        m.ReferenceKey,
        m.Mnemonic,
        ISNULL(NULLIF(LTRIM(RTRIM(td.Particulars)), ''), m.Particulars) AS Particulars,
        CAST(ISNULL(td.Debit, 0)  AS DECIMAL(18,2))        AS Debit,
        CAST(ISNULL(td.Credit, 0) AS DECIMAL(18,2))        AS Credit
    INTO #Lines
    FROM dbo.TicketDetails AS td
    OUTER APPLY (
        SELECT TOP (1) tm.Mnemonic, tm.Origin, tm.Product, tm.ReferenceNumber, tm.ReferenceKey, tm.Particulars
        FROM dbo.TicketMaster AS tm
        WHERE tm.TicketNumber = td.TicketNumber
        ORDER BY CASE WHEN tm.BranchCode = td.BranchCode THEN 0 ELSE 1 END, tm.BranchCode
    ) AS m
    WHERE td.AccountCode = @AccountCode
      AND td.TicketDate >= CAST(@PeriodStart AS DATETIME)
      AND td.TicketDate <  @NextDay;

    DECLARE @Receipts      DECIMAL(18,2) = (SELECT ISNULL(SUM(Debit - Credit), 0) FROM #Lines WHERE Journal = 'RECEIPTS');
    DECLARE @Disbursements DECIMAL(18,2) = (SELECT ISNULL(SUM(Credit - Debit), 0) FROM #Lines WHERE Journal = 'DISBURSEMENTS');
    DECLARE @Other         DECIMAL(18,2) = (SELECT ISNULL(SUM(Debit - Credit), 0) FROM #Lines WHERE Journal = 'OTHER');

    IF @ResultSet IS NULL OR @ResultSet = 1
    SELECT
        @AccountCode                                        AS AccountCode,
        (SELECT TOP (1) coa.Description FROM dbo.ChartOfAccounts coa WHERE coa.AccountCode = @AccountCode) AS AccountName,
        @PeriodStart                                        AS PeriodStart,
        @PeriodEnd                                          AS PeriodEnd,
        @Beginning                                          AS BeginningGL,
        @Receipts                                           AS CashReceipts,
        @Disbursements                                      AS CashDisbursements,
        @Other                                              AS OtherNet,
        CAST(@Beginning + @Receipts - @Disbursements + @Other AS DECIMAL(18,2)) AS EndingGL;

    IF @ResultSet IS NULL OR @ResultSet = 2
    SELECT Journal, TicketDate, BranchCode, TicketNumber, ReferenceNumber, ReferenceKey, Mnemonic, Particulars, Debit, Credit
    FROM #Lines
    ORDER BY CASE Journal WHEN 'RECEIPTS' THEN 1 WHEN 'DISBURSEMENTS' THEN 2 ELSE 3 END, TicketDate, TicketNumber, BranchCode;

    DROP TABLE #Lines;
END;
GO

IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
IF OBJECT_ID('dbo.sp_rpt_BankRecon_GLMovement', 'P') IS NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[99] post-check failed: sp_rpt_BankRecon_GLMovement was not created; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO

COMMIT TRANSACTION;
PRINT '[99] committed: sp_rpt_BankRecon_GLMovement created.';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
