/* ================================================================
   2026-10-02e: Bank Recon (AccountingDevEx/BankReconFormV2) — Control No.
   ================================================================
   The user groups deposits in transit (DIT) by the control number staff
   type when posting a client payment (PaymentHeader.ControlNo; it carries
   the CR numbers of a deposit batch). The form already groups the DIT grid
   by ControlNo and has "Resolve group" (2026-09-03 work), but:

   1. BankStatementRecon.ControlNo was never filled. sp_AddPaymentClient
      inserts one DIT row per payment (SourceModule 'AR-PAYMENT', SourceRef =
      PaymentHeader.ReferenceNo) without it. STAGING 2026-10-02: 4,980 of 4,980
      AR DIT rows blank, every one matches a PaymentHeader with a ControlNo
      (576 control numbers); the header agrees with TransactionCheque /
      TransactionOnline wherever those exist, and 3,680 are CASH (header only).
      -> one blank group, "Resolve group" disabled.
   2. The form sends @ItemType to sp_BankRecon_BulkResolveItems, but
      SQL/2026-09-04_BankRecon_OCBulkResolve.sql (which adds it) was never
      deployed -> every Bulk Resolve / Resolve group (DIT and OC) failed.
   3. sp_BankRecon_GetControlNoCandidates offered every control number as
      "not yet in the recon" (none had a ControlNo), so adding a DIT from the
      picker would double-count collections already auto-inserted per payment.

   This script (ONE explicit transaction for the data + objects; a failed step stops the rest):
     A. backfills ControlNo on AR-PAYMENT DIT rows from PaymentHeader
        (old values kept in BankStatementRecon_ControlNo_Backup_20261002);
     B. sp_AddPaymentClient writes ControlNo on its DIT row (one-line patch);
     C. sp_BankRecon_GetPeriod: DIT rows add ReferenceNo, CRNo, PaymentType,
        ResolvedReason; ControlNo falls back to the payment's;
     D. sp_BankRecon_BulkResolveItems with @ItemType (the 2026-09-04 version);
     E. sp_BankRecon_GetControlNoCandidates leaves out control numbers whose
        payments already have an AR-PAYMENT DIT row on that account.
   Backups: <name>_OLD_10022026180000.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.BankStatementRecon_ControlNo_Backup_20261002') IS NOT NULL
   OR OBJECT_ID('dbo.sp_BankRecon_GetPeriod_OLD_10022026180000') IS NOT NULL
    THROW 59880, 'Already applied (backup table / _OLD_10022026180000 objects exist).', 1;
IF COL_LENGTH('dbo.BankStatementRecon', 'ControlNo') IS NULL
    THROW 59881, 'BankStatementRecon.ControlNo is missing (run 2026-09-03_BankReconDIT_ControlNoFilterCheckAll.sql first).', 1;

-- One transaction for everything below (XACT_ABORT ON rolls it back on any error; every later
-- step first checks it is still open, so nothing runs after a failed step).
BEGIN TRANSACTION;
GO

------------------------------------------------------------------
-- A. Backfill
------------------------------------------------------------------
IF @@TRANCOUNT = 0 THROW 59889, 'An earlier step of this script failed and its transaction was rolled back; nothing more is run.', 1;
SELECT b.ReconID, b.ControlNo AS OldControlNo, LTRIM(RTRIM(ph.ControlNo)) AS NewControlNo, GETDATE() AS BackedUpAt
INTO dbo.BankStatementRecon_ControlNo_Backup_20261002
FROM dbo.BankStatementRecon AS b
INNER JOIN dbo.PaymentHeader AS ph ON ph.ReferenceNo = b.SourceRef
WHERE b.ItemType = 'DIT' AND b.SourceModule = 'AR-PAYMENT'
  AND NULLIF(LTRIM(RTRIM(b.ControlNo)), '') IS NULL
  AND NULLIF(LTRIM(RTRIM(ph.ControlNo)), '') IS NOT NULL;

UPDATE b SET b.ControlNo = k.NewControlNo
FROM dbo.BankStatementRecon AS b
INNER JOIN dbo.BankStatementRecon_ControlNo_Backup_20261002 AS k ON k.ReconID = b.ReconID;

PRINT 'A. control numbers filled: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
GO

------------------------------------------------------------------
-- B. sp_AddPaymentClient writes ControlNo on its DIT row
------------------------------------------------------------------
IF @@TRANCOUNT = 0 THROW 59889, 'An earlier step of this script failed and its transaction was rolled back; nothing more is run.', 1;
DECLARE @def NVARCHAR(MAX) = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentClient')), NCHAR(13) + NCHAR(10), NCHAR(10));
DECLARE @o1 NVARCHAR(400) = N'            SourceModule, SourceRef, ResolvedReason,' + NCHAR(10) + N'            CreatedBy, CreatedDate' + NCHAR(10) + N'        )';
DECLARE @n1 NVARCHAR(400) = N'            SourceModule, SourceRef, ResolvedReason,' + NCHAR(10) + N'            CreatedBy, CreatedDate, ControlNo   -- 2026-10-02e' + NCHAR(10) + N'        )';
DECLARE @o2 NVARCHAR(400) = N'            ''AR-PAYMENT'',' + NCHAR(10) + N'            @refno,' + NCHAR(10) + N'            '' '',' + NCHAR(10) + N'            @preparedby,' + NCHAR(10) + N'            GETDATE()' + NCHAR(10) + N'        );';
DECLARE @n2 NVARCHAR(600) = N'            ''AR-PAYMENT'',' + NCHAR(10) + N'            @refno,' + NCHAR(10) + N'            '' '',' + NCHAR(10) + N'            @preparedby,' + NCHAR(10) + N'            GETDATE(),' + NCHAR(10)
                          + N'            (SELECT NULLIF(LTRIM(RTRIM(ControlNo)), '''') FROM dbo.PaymentHeader WHERE PaymentHeaderID = @PaymentHeaderID)   -- 2026-10-02e: the payment''s control number' + NCHAR(10) + N'        );';

IF @def IS NULL
    THROW 59883, 'Cannot read sp_AddPaymentClient''s definition (missing, encrypted or no VIEW DEFINITION); nothing changed.', 1;

IF (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @o1, N''))) / DATALENGTH(@o1) <> 1
   OR (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @o2, N''))) / DATALENGTH(@o2) <> 1
    THROW 59882, 'sp_AddPaymentClient text differs from the version this script was written for; nothing changed.', 1;

SET @def = REPLACE(REPLACE(@def, @o1, @n1), @o2, @n2);
EXEC sp_rename 'dbo.sp_AddPaymentClient', 'sp_AddPaymentClient_OLD_10022026180000';
EXEC (@def);
GO

------------------------------------------------------------------
-- C. sp_BankRecon_GetPeriod
------------------------------------------------------------------
IF @@TRANCOUNT = 0 THROW 59889, 'An earlier step of this script failed and its transaction was rolled back; nothing more is run.', 1;
EXEC sp_rename 'dbo.sp_BankRecon_GetPeriod', 'sp_BankRecon_GetPeriod_OLD_10022026180000';
GO

CREATE PROCEDURE dbo.sp_BankRecon_GetPeriod
    @BranchCode  CHAR(3),
    @AccountCode VARCHAR(20),
    @PeriodEnd   DATE
AS
/*
    Result sets for AccountingDevEx/BankReconFormV2: header, DIT rows, OC rows,
    bank-side rows. 2026-10-02e: DIT rows carry the client payment's ControlNo
    (stored on the row, else the payment's), CRNo, PaymentType, ReferenceNo and
    ResolvedReason, so the form can group and resolve by control number.
*/
BEGIN
    SET NOCOUNT ON;

    -- HEADER
    SELECT
        H.HeaderID, H.BranchCode, H.AccountCode,
        CA.Description AS AccountName,
        H.PeriodEnd, H.BankStatementBal, H.GLBookBalance, H.Status, H.Remarks,
        ISNULL(DIT.TotalDIT, 0) AS TotalDIT,
        ISNULL(OC.TotalOC,   0) AS TotalOC,
        H.BankStatementBal + ISNULL(DIT.TotalDIT, 0) - ISNULL(OC.TotalOC, 0) AS AdjustedBankBalance,
        H.GLBookBalance - (H.BankStatementBal + ISNULL(DIT.TotalDIT, 0) - ISNULL(OC.TotalOC, 0)) AS Difference,
        CASE WHEN H.GLBookBalance = (H.BankStatementBal + ISNULL(DIT.TotalDIT, 0) - ISNULL(OC.TotalOC, 0))
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsReconciled
    FROM dbo.BankReconHeader AS H
    LEFT JOIN dbo.ChartOfAccounts AS CA ON CA.AccountCode = H.AccountCode
    OUTER APPLY (SELECT ISNULL(SUM(Amount), 0) AS TotalDIT
                 FROM dbo.BankStatementRecon WHERE HeaderID = H.HeaderID AND ItemType = 'DIT') AS DIT
    OUTER APPLY (SELECT ISNULL(SUM(Amount), 0) AS TotalOC
                 FROM dbo.BankStatementRecon WHERE HeaderID = H.HeaderID AND ItemType = 'OC') AS OC
    WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd <= @PeriodEnd;

    -- DIT ROWS
    SELECT
        BSR.ReconID,
        BSR.ItemDate,
        COALESCE(NULLIF(LTRIM(RTRIM(BSR.ControlNo)), ''), NULLIF(LTRIM(RTRIM(ph.ControlNo)), '')) AS ControlNo,
        NULLIF(LTRIM(RTRIM(ph.CRNo)), '') AS CRNo,
        BSR.ReferenceNo,
        BSR.Payee,
        ph.PaymentType,
        BSR.Amount,
        BSR.IsResolved,
        BSR.ResolvedReason,
        CASE WHEN BSR.SourceModule IS NOT NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsAutoInserted
    FROM dbo.BankStatementRecon AS BSR
    INNER JOIN dbo.BankReconHeader AS H ON BSR.HeaderID = H.HeaderID
    OUTER APPLY (SELECT TOP (1) p.ControlNo, p.CRNo, p.PaymentType
                 FROM dbo.PaymentHeader AS p
                 WHERE BSR.SourceModule = 'AR-PAYMENT' AND p.ReferenceNo = BSR.SourceRef
                 ORDER BY p.PaymentHeaderID DESC) AS ph
    WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd <= @PeriodEnd
      AND BSR.ItemType = 'DIT'
    ORDER BY BSR.ReconID DESC;

    -- OC ROWS (unchanged)
    SELECT
        BSR.ReconID,
        BSR.ItemDate,
        BSR.Payee,
        BSR.Amount,
        BSR.IsResolved
    FROM dbo.BankStatementRecon AS BSR
    INNER JOIN dbo.BankReconHeader AS H ON BSR.HeaderID = H.HeaderID
    WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd <= @PeriodEnd
      AND BSR.ItemType = 'OC'
    ORDER BY BSR.ReconID DESC;

    -- BANK-SIDE ROWS (BCM / BDM / BC / NSF / ADB) (unchanged)
    SELECT BSR.ReconID, BSR.HeaderID, BSR.ItemType, BSR.ItemDate, BSR.Payee, BSR.ReferenceNo,
           BSR.Amount, BSR.IsResolved, BSR.ResolvedDate, BSR.ResolvedReason,
           BSR.SourceModule, BSR.SourceRef, BSR.CreatedBy, BSR.CreatedDate,
           BSR.PostedPaymentRef,
           CASE WHEN BSR.SourceModule IS NOT NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsAutoInserted
    FROM dbo.BankStatementRecon AS BSR
    INNER JOIN dbo.BankReconHeader AS H ON BSR.HeaderID = H.HeaderID
    WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd <= @PeriodEnd
      AND BSR.ItemType IN ('BCM', 'BDM', 'BC', 'NSF', 'ADB')
    ORDER BY BSR.ReconID DESC;
END
GO

------------------------------------------------------------------
-- D. sp_BankRecon_BulkResolveItems with @ItemType (2026-09-04 version, never deployed)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 THROW 59889, 'An earlier step of this script failed and its transaction was rolled back; nothing more is run.', 1;
EXEC sp_rename 'dbo.sp_BankRecon_BulkResolveItems', 'sp_BankRecon_BulkResolveItems_OLD_10022026180000';
GO

CREATE PROCEDURE dbo.sp_BankRecon_BulkResolveItems
    @ReconIDs   dbo.tt_BankReconIDList READONLY,
    @ResolvedBy VARCHAR(50),
    @ItemType   VARCHAR(5) = 'DIT'   -- 2026-10-02e: optional, so an exe older than the 09-12 form (which sent no @ItemType) still resolves DITs as before
AS
/*
    Marks the given items cleared by the bank. Serves the DIT grid (Bulk Resolve,
    Resolve group by Control No) and the OC grid (Bulk Resolve) of BankReconFormV2,
    which pass @ItemType; only rows of that type are touched.
    (SQL/2026-09-04_BankRecon_OCBulkResolve.sql, deployed by 2026-10-02e.)
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM @ReconIDs)
        THROW 93101, 'No items were selected to resolve.', 1;

    IF @ItemType NOT IN ('OC', 'DIT', 'BCM', 'BDM', 'BC', 'NSF')
        THROW 93104, 'Invalid ItemType. Use: OC, DIT, BCM, BDM, BC, NSF', 1;

    BEGIN TRY
        BEGIN TRAN;

        IF EXISTS (SELECT 1
                   FROM dbo.BankStatementRecon AS BSR
                   INNER JOIN dbo.BankReconHeader AS H ON BSR.HeaderID = H.HeaderID
                   INNER JOIN @ReconIDs AS R ON R.ReconID = BSR.ReconID
                   WHERE H.Status = 'LOCKED')
            THROW 93102, 'Cannot resolve items in a locked period.', 1;

        IF EXISTS (SELECT 1 FROM dbo.BankStatementRecon AS BSR
                   INNER JOIN @ReconIDs AS R ON R.ReconID = BSR.ReconID
                   WHERE BSR.ResolvedReason = 'REVERSED')
            THROW 93103, 'One or more selected items were already resolved by a payment reversal.', 1;

        UPDATE BSR
        SET IsResolved     = 1,
            ResolvedDate   = GETDATE(),
            ResolvedBy     = @ResolvedBy,
            ResolvedReason = 'CLEARED'
        FROM dbo.BankStatementRecon AS BSR
        INNER JOIN @ReconIDs AS R ON R.ReconID = BSR.ReconID
        WHERE BSR.ItemType = @ItemType AND BSR.IsResolved = 0;

        DECLARE @Resolved INT = @@ROWCOUNT;

        COMMIT TRAN;

        SELECT @Resolved AS ResolvedCount;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

------------------------------------------------------------------
-- E. sp_BankRecon_GetControlNoCandidates: no double counting
------------------------------------------------------------------
IF @@TRANCOUNT = 0 THROW 59889, 'An earlier step of this script failed and its transaction was rolled back; nothing more is run.', 1;
EXEC sp_rename 'dbo.sp_BankRecon_GetControlNoCandidates', 'sp_BankRecon_GetControlNoCandidates_OLD_10022026180000';
GO

CREATE PROCEDURE dbo.sp_BankRecon_GetControlNoCandidates
    @BranchCode  VARCHAR(5),
    @AccountCode VARCHAR(20)
AS
/*
    Control numbers offered by BankReconItemForm when a DIT is added by hand.
    2026-10-02e: a control number is left out when it already has a DIT row on
    the account, either stored on the row or through its client payments
    (sp_AddPaymentClient auto-inserts one DIT per payment) -- adding it again
    would count those collections twice.
*/
BEGIN
    SET NOCOUNT ON;

    ;WITH Collections AS (
        SELECT ControlNo = LTRIM(RTRIM(ControlNo)), Amount = CAST(Amount AS DECIMAL(19,2)), ItemDate = CheckDate
        FROM dbo.TransactionCheque
        WHERE ControlNo IS NOT NULL AND LTRIM(RTRIM(ControlNo)) <> ''
          AND CreditGLCode = @AccountCode
          AND (LTRIM(RTRIM(ISNULL(BranchCode, ''))) = '' OR BranchCode = @BranchCode)
        UNION ALL
        SELECT ControlNo = LTRIM(RTRIM(ControlNo)), Amount = CAST(Amount AS DECIMAL(19,2)), ItemDate = DateDeposit
        FROM dbo.TransactionOnline
        WHERE ControlNo IS NOT NULL AND LTRIM(RTRIM(ControlNo)) <> ''
          AND CreditGLCode = @AccountCode
          AND (LTRIM(RTRIM(ISNULL(BranchCode, ''))) = '' OR BranchCode = @BranchCode)
    )
    SELECT
        c.ControlNo,
        ItemCount   = COUNT(*),
        TotalAmount = SUM(c.Amount),
        ItemDate    = MAX(c.ItemDate)
    FROM Collections AS c
    WHERE NOT EXISTS (SELECT 1 FROM dbo.BankStatementRecon AS b
                      WHERE b.ItemType = 'DIT' AND b.AccountCode = @AccountCode
                        AND LTRIM(RTRIM(b.ControlNo)) = c.ControlNo)
      AND NOT EXISTS (SELECT 1 FROM dbo.BankStatementRecon AS b
                      INNER JOIN dbo.PaymentHeader AS ph ON ph.ReferenceNo = b.SourceRef
                      WHERE b.ItemType = 'DIT' AND b.SourceModule = 'AR-PAYMENT' AND b.AccountCode = @AccountCode
                        AND LTRIM(RTRIM(ph.ControlNo)) = c.ControlNo)
    GROUP BY c.ControlNo
    ORDER BY MAX(c.ItemDate) DESC;
END
GO

IF @@TRANCOUNT = 0 THROW 59889, 'An earlier step of this script failed and its transaction was rolled back; nothing more is run.', 1;
COMMIT TRANSACTION;
GO

SELECT 'filled' AS step, COUNT(*) AS n FROM dbo.BankStatementRecon_ControlNo_Backup_20261002;
SELECT 'AR DIT rows still without ControlNo' AS step, COUNT(*) AS n
FROM dbo.BankStatementRecon WHERE ItemType = 'DIT' AND SourceModule = 'AR-PAYMENT' AND NULLIF(LTRIM(RTRIM(ControlNo)), '') IS NULL;
SELECT name, CONVERT(VARCHAR(19), modify_date, 120) AS modified FROM sys.objects
WHERE name IN ('sp_AddPaymentClient', 'sp_BankRecon_GetPeriod', 'sp_BankRecon_BulkResolveItems', 'sp_BankRecon_GetControlNoCandidates')
   OR name LIKE '%[_]OLD[_]10022026180000'
ORDER BY name;
