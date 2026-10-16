/* ================================================================
   [98] 2026-10-16  GL Detail Transaction: Owner per GL line
   ================================================================
   User (2026-10-16): Accounting Reports › GL Detail Transaction (also on the
   Accounting Board) shows the ticket's Owner after Account Description,
   "whatever is in TicketMaster, it should be the same": [Owner] = the
   TicketMaster.Owner of the line's own master (the same 4-part join the report
   already uses for Reference / Particulars: TicketDate + SupplementaryNumber +
   BranchCode + TicketNumber, so one master per line and no extra rows). Shown
   as stored: the supplier on vouchers / expenses, the customer on sales and
   collections, the preparer on Manual JVs and cash advances, "CS IN TRANSIT" on
   STS. A line whose master is keyed differently (the 07-31 opening ticket, some
   CONV-FINALIZE lines) shows blank, like its Reference. Blank on the Beginning /
   Current Period Change / Ending rows.
   (First version of [98], same day, DEV only: a [Supplier Name] looked up from the
   document behind the ticket; replaced by this at the user's request.)

   Result: the same rows, same columns in the same order, plus [Owner] as the
   LAST column. The exe of 2026-10-16 shows it right after Account Description;
   an older exe shows it at the end. Callers: HOFormsDevEx/AccountingReportsFormV2.cs only.

   Text identical on DEV / STAGING / PRODUCTION on 2026-10-16 (whitespace-insensitive
   SHA-256 6A06CAE2...). Deploy: rename to
   sp_rpt_GLDetailTransactionRealTime_OLD_10162026120000, CREATE, one transaction,
   guarded by that hash. Run in ONE connection, no open transaction. Read-only proc:
   no data changes, no exe needed.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET LOCK_TIMEOUT 10000;
GO

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[98] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.sp_rpt_GLDetailTransactionRealTime', 'P') IS NULL
BEGIN
    RAISERROR('[98] stopped: sp_rpt_GLDetailTransactionRealTime does not exist in this database; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.sp_rpt_GLDetailTransactionRealTime_OLD_10162026120000') IS NOT NULL
BEGIN
    RAISERROR('[98] stopped: the backup sp_rpt_GLDetailTransactionRealTime_OLD_10162026120000 already exists ([98] already installed?); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(
            OBJECT_DEFINITION(OBJECT_ID('dbo.sp_rpt_GLDetailTransactionRealTime')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '6A06CAE25F2D8D495399C42F0D272ECA48F981E1FE54BBB267ED4EE01545465C'
BEGIN
    RAISERROR('[98] stopped: sp_rpt_GLDetailTransactionRealTime is not the text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[98] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
EXEC sp_rename 'dbo.sp_rpt_GLDetailTransactionRealTime', 'sp_rpt_GLDetailTransactionRealTime_OLD_10162026120000';
GO

IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
/* ================================================================
   sp_rpt_GLDetailTransactionReport — ADD TicketNumber TO OUTPUT
   Root cause of the drill-down menu never finding a column: the SP
   already JOINs TicketMaster/TicketDetails and uses td.TicketNumber
   for sort ordering, but never actually exposes it in the final
   SELECT. Adding it here, carried as NULL through the synthetic
   Opening/Period/Ending rows (only real DETAIL rows have one, which
   is correct — those are the only rows a "same ticket" drill-down
   makes sense for anyway).

   Aliased as [TicketNumber] (no space, unlike the other bracketed
   display columns) so it matches the C# check verbatim with no
   further code changes needed there.
   ================================================================ */
CREATE PROCEDURE [dbo].[sp_rpt_GLDetailTransactionRealTime]
(
    @BranchCode          VARCHAR(5)  = NULL,
    @AccountCode         VARCHAR(20) = NULL,
    @DateFrom            DATE,
    @DateTo              DATE,
    @IncludeZeroActivity BIT         = 0
)
AS
/*
    REAL-TIME copy (2026-09-30) of sp_rpt_GLDetailTransactionReport: identical flat result
    set (Opening / detail legs / Period / Ending rows per account, TicketNumber on detail
    rows). Two changes, so Opening + period = Ending always ties to the Trial Balance:
      1. Opening = every TicketDetails leg before @DateFrom (was GLSummary's last EndingBalance).
      2. Detail legs LEFT JOIN TicketMaster (was INNER): the 2026-07-31 opening-balance ticket
         has a blank TicketMaster.BranchCode and some CONV-FINALIZE tickets post legs under a
         different branch than their master, so an inner 4-part join silently dropped them.
         Such legs show a NULL Reference and fall back to their own Particulars.
    [98] 2026-10-16: [Owner] as the last column = TicketMaster.Owner of the line's own master.
    Callers: HOFormsDevEx/AccountingReportsFormV2.cs ("GL Detail Transaction (Real-Time)").
*/
BEGIN
    SET NOCOUNT ON;

    -- ── Target account list ──────────────────────────────────────────
    IF OBJECT_ID('tempdb..#Accounts') IS NOT NULL DROP TABLE #Accounts;
    SELECT
        ROW_NUMBER() OVER (ORDER BY coa.AccountCode) AS AcctSeq,
        coa.AccountCode,
        coa.Description AS AccountDescription
    INTO #Accounts
    FROM ChartOfAccounts coa
    WHERE (@AccountCode IS NOT NULL AND coa.AccountCode = @AccountCode)
       OR (@AccountCode IS NULL AND coa.AccountType = 'D');

    -- ── REAL-TIME (2026-09-30): opening balance per account = every TicketDetails leg
    --    before @DateFrom (summed across branches if @BranchCode IS NULL) -- no GLSummary.
    --    Everything below this block is unchanged from sp_rpt_GLDetailTransactionReport. ──
    IF OBJECT_ID('tempdb..#Opening') IS NOT NULL DROP TABLE #Opening;
    SELECT
        a.AcctSeq,
        a.AccountCode,
        CAST(ISNULL(SUM(ISNULL(td.Debit, 0) - ISNULL(td.Credit, 0)), 0) AS DECIMAL(19,2)) AS OpeningBalance
    INTO #Opening
    FROM #Accounts a
    LEFT JOIN dbo.TicketDetails td
           ON td.AccountCode = a.AccountCode
          AND td.TicketDate  < @DateFrom
          AND (@BranchCode IS NULL OR td.BranchCode = @BranchCode)
    GROUP BY a.AcctSeq, a.AccountCode;

    -- ── Detail rows: one per TicketDetails leg in the period ──────────
    IF OBJECT_ID('tempdb..#Detail') IS NOT NULL DROP TABLE #Detail;
    SELECT
        a.AcctSeq,
        a.AccountCode,
        a.AccountDescription,
        td.TicketDate                              AS TxnDate,
        tm.ReferenceKey                             AS Reference,
        isnull(td.Particulars,tm.Particulars)      AS TransDescription,
        NULLIF(td.Debit, 0)                        AS DebitAmt,
        NULLIF(td.Credit, 0)                       AS CreditAmt,
        CAST(NULL AS DECIMAL(19,2))                AS Balance,
        td.TicketNumber                            AS TicketNumber,   -- NEW
        tm.Owner                                   AS Owner,          -- [98]
        ROW_NUMBER() OVER (
            PARTITION BY a.AcctSeq
            ORDER BY td.TicketDate, tm.ReferenceKey, td.TicketNumber
        )                                           AS DetailSeq
    INTO #Detail
    FROM #Accounts a
    INNER JOIN TicketDetails td ON td.AccountCode = a.AccountCode
    LEFT JOIN TicketMaster tm   -- REAL-TIME: keep legs whose master is keyed differently (see header)
        ON  tm.TicketDate          = td.TicketDate
        AND tm.SupplementaryNumber = td.SupplementaryNumber
        AND tm.BranchCode          = td.BranchCode
        AND tm.TicketNumber        = td.TicketNumber
    WHERE td.TicketDate >= @DateFrom
      AND td.TicketDate <  DATEADD(DAY, 1, @DateTo)   -- REAL-TIME: half-open (TicketDate is DATETIME)
      AND (@BranchCode IS NULL OR td.BranchCode = @BranchCode);

    -- ── Period totals per account ──────────────────────────────────────
    IF OBJECT_ID('tempdb..#PeriodTotals') IS NOT NULL DROP TABLE #PeriodTotals;
    SELECT
        AcctSeq,
        CAST(ISNULL(SUM(DebitAmt), 0)  AS DECIMAL(19,2)) AS TotalDebit,
        CAST(ISNULL(SUM(CreditAmt), 0) AS DECIMAL(19,2)) AS TotalCredit
    INTO #PeriodTotals
    FROM #Detail
    GROUP BY AcctSeq;

    -- ── Assemble the flat, ordered result set ──────────────────────────
    ;WITH Combined AS
    (
        -- OPENING BALANCE row — no ticket, NULL
        SELECT
            a.AcctSeq, 0 AS StageOrder, 0 AS DetailSeq,
            a.AccountCode, a.AccountDescription,
            @DateFrom                       AS TxnDate,
            CAST(NULL AS VARCHAR(150))      AS Reference,
            'Beginning Balance'             AS TransDescription,
            CAST(NULL AS DECIMAL(19,2))     AS DebitAmt,
            CAST(NULL AS DECIMAL(19,2))     AS CreditAmt,
            o.OpeningBalance                AS Balance,
            CAST(NULL AS VARCHAR(20))       AS TicketNumber,  -- NEW
            CAST(NULL AS VARCHAR(150))      AS Owner          -- [98]
        FROM #Accounts a
        JOIN #Opening o ON o.AcctSeq = a.AcctSeq
        WHERE @IncludeZeroActivity = 1
           OR o.OpeningBalance <> 0
           OR EXISTS (SELECT 1 FROM #Detail d WHERE d.AcctSeq = a.AcctSeq)

        UNION ALL

        -- DETAIL rows — the real ticket number
        SELECT
            d.AcctSeq, 1 AS StageOrder, d.DetailSeq,
            d.AccountCode, d.AccountDescription,
            d.TxnDate, d.Reference, d.TransDescription,
            d.DebitAmt, d.CreditAmt, d.Balance,
            d.TicketNumber,  -- NEW
            d.Owner          -- [98]
        FROM #Detail d

        UNION ALL

        -- CURRENT PERIOD CHANGE row — no single ticket, NULL
        SELECT
            a.AcctSeq, 2 AS StageOrder, 0 AS DetailSeq,
            a.AccountCode, a.AccountDescription,
            CAST(NULL AS DATE)              AS TxnDate,
            CAST(NULL AS VARCHAR(150))      AS Reference,
            'Current Period Change'         AS TransDescription,
            pt.TotalDebit                   AS DebitAmt,
            pt.TotalCredit                  AS CreditAmt,
            CAST(pt.TotalDebit - pt.TotalCredit AS DECIMAL(19,2)) AS Balance,
            CAST(NULL AS VARCHAR(20))       AS TicketNumber,  -- NEW
            CAST(NULL AS VARCHAR(150))      AS Owner          -- [98]
        FROM #Accounts a
        JOIN #PeriodTotals pt ON pt.AcctSeq = a.AcctSeq
        WHERE @IncludeZeroActivity = 1
           OR EXISTS (SELECT 1 FROM #Detail d WHERE d.AcctSeq = a.AcctSeq)

        UNION ALL

        -- ENDING BALANCE row — no single ticket, NULL
        SELECT
            a.AcctSeq, 3 AS StageOrder, 0 AS DetailSeq,
            CAST(NULL AS VARCHAR(20))       AS AccountCode,
            CAST(NULL AS VARCHAR(150))      AS AccountDescription,
            @DateTo                         AS TxnDate,
            CAST(NULL AS VARCHAR(150))      AS Reference,
            'Ending Balance'                AS TransDescription,
            CAST(NULL AS DECIMAL(19,2))     AS DebitAmt,
            CAST(NULL AS DECIMAL(19,2))     AS CreditAmt,
            CAST(o.OpeningBalance + ISNULL(pt.TotalDebit,0) - ISNULL(pt.TotalCredit,0) AS DECIMAL(19,2)) AS Balance,
            CAST(NULL AS VARCHAR(20))       AS TicketNumber,  -- NEW
            CAST(NULL AS VARCHAR(150))      AS Owner          -- [98]
        FROM #Accounts a
        JOIN #Opening o ON o.AcctSeq = a.AcctSeq
        LEFT JOIN #PeriodTotals pt ON pt.AcctSeq = a.AcctSeq
        WHERE @IncludeZeroActivity = 1
           OR o.OpeningBalance <> 0
           OR EXISTS (SELECT 1 FROM #Detail d WHERE d.AcctSeq = a.AcctSeq)
    )
    SELECT
        AccountCode          AS [Account ID],
        AccountDescription   AS [Account Description],
        TxnDate              AS [Date],
        Reference            AS [Reference],
        TransDescription     AS [Trans Description],
        DebitAmt             AS [Debit Amt],
        CreditAmt            AS [Credit Amt],
        Balance              AS [Balance],
        TicketNumber         AS [TicketNumber],   -- NEW — no space, matches C# check verbatim
        Owner                AS [Owner]           -- [98] last, so the existing columns keep their positions
    FROM Combined
    ORDER BY AcctSeq, StageOrder, DetailSeq;

    DROP TABLE #Accounts;
    DROP TABLE #Opening;
    DROP TABLE #Detail;
    DROP TABLE #PeriodTotals;
END;
GO

IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF OBJECT_ID('dbo.sp_rpt_GLDetailTransactionRealTime', 'P') IS NULL
    SET @msg = N'[98] post-check failed: sp_rpt_GLDetailTransactionRealTime is missing.';
ELSE IF OBJECT_ID('dbo.sp_rpt_GLDetailTransactionRealTime_OLD_10162026120000', 'P') IS NULL
    SET @msg = N'[98] post-check failed: the backup sp_rpt_GLDetailTransactionRealTime_OLD_10162026120000 is missing.';
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_rpt_GLDetailTransactionRealTime')) NOT LIKE N'%tm.Owner%AS Owner%'
    SET @msg = N'[98] post-check failed: the new proc text is not the [98] text.';

IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR(@msg, 16, 1);
    SET NOEXEC ON;
END
GO

COMMIT TRANSACTION;
PRINT '[98] committed: sp_rpt_GLDetailTransactionRealTime returns [Owner] last; backup sp_rpt_GLDetailTransactionRealTime_OLD_10162026120000.';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
