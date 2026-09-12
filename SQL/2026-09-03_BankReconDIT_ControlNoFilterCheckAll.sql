-- =============================================
-- Author: Eulz Avancena; 2026-09-03
-- Description: BankReconFormV2's Deposits-in-Transit (DIT) tab gets:
--   1. A ControlNo column, letting a DIT row be tied to the real control
--      number collections are grouped under (TransactionCheque /
--      TransactionOnline.ControlNo) when a batch of collections is
--      deposited to the bank as one slip.
--   2. A picker (sp_BankRecon_GetControlNoCandidates) so the control number
--      is chosen from a real, existing collection batch instead of being
--      freely typed -- confirmed with user 2026-09-03.
--   3. A bulk-resolve path (sp_BankRecon_BulkResolveItems) so, after
--      filtering the grid down to one control number and checking every
--      row, the whole batch can be marked cleared in a single call.
--
-- BLOCKING BUG FOUND AND FIXED IN sp_BankRecon_SaveItem WHILE ADDING
-- @ControlNo (not part of the originally scoped ask, but the ControlNo/
-- filter/check-all feature is pointless without it -- flagged to user):
--   - The INSERT hardcoded ItemType='OC' regardless of the @ItemType
--     parameter, so a DIT/BCM/BDM/BC/NSF item added from the UI was
--     ALWAYS silently saved as an OC row. No DIT row could ever exist.
--   - ReferenceNo was populated from a freshly-generated voucher number
--     (@parmvoucherid, via GetVoucherNumber) instead of the user-typed
--     @ReferenceNo parameter; @ReferenceNo itself was stuffed into
--     SourceRef (a column meant for auto-inserted-item traceability)
--     instead of being discarded.
--   - @BranchCode = '888' was hardcoded into the sp_BankRecon_GetOrCreateHeader
--     call, ignoring the real @BranchCode parameter -- every manually
--     added item always attached to Head Office's period header
--     regardless of which branch was actually selected in the UI.
--   All three are fixed below by simply using the already-correct
--   parameters that were being passed in and ignored.
-- =============================================

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-------------------------------------------------------------------
-- 1. Schema: ControlNo on BankStatementRecon (nullable -- only DIT rows
--    use it; OC/BCM/BDM/BC/NSF/ADB rows leave it NULL).
-------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.BankStatementRecon') AND name = 'ControlNo')
    ALTER TABLE dbo.BankStatementRecon ADD ControlNo VARCHAR(50) NULL;
GO

-------------------------------------------------------------------
-- 2. Candidate lookup for the "Add DIT" dialog's Control No picker.
--    Aggregates real collection batches from TransactionCheque and
--    TransactionOnline, grouped by ControlNo, matched to the bank GL
--    account being reconciled via CreditGLCode. Excludes any ControlNo
--    already saved as a DIT row for this account (mirrors the
--    idempotent-by-key pattern used in sp_Payment_PostBankReconEntry).
--    Branch match is lenient (exact match OR blank BranchCode) -- the
--    live TransactionCheque/TransactionOnline data observed in DEV has
--    BranchCode frequently blank, and a strict match would silently
--    hide real, legitimate candidates rather than surfacing them.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.sp_BankRecon_GetControlNoCandidates', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_BankRecon_GetControlNoCandidates;
GO

CREATE PROCEDURE dbo.sp_BankRecon_GetControlNoCandidates
    @BranchCode  VARCHAR(5),
    @AccountCode VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Collections AS (
        SELECT ControlNo, Amount = CAST(Amount AS DECIMAL(19,2)), ItemDate = CheckDate
        FROM dbo.TransactionCheque
        WHERE ControlNo IS NOT NULL AND LTRIM(RTRIM(ControlNo)) <> ''
          AND CreditGLCode = @AccountCode
          AND (LTRIM(RTRIM(ISNULL(BranchCode,''))) = '' OR BranchCode = @BranchCode)
        UNION ALL
        SELECT ControlNo, Amount = CAST(Amount AS DECIMAL(19,2)), ItemDate = DateDeposit
        FROM dbo.TransactionOnline
        WHERE ControlNo IS NOT NULL AND LTRIM(RTRIM(ControlNo)) <> ''
          AND CreditGLCode = @AccountCode
          AND (LTRIM(RTRIM(ISNULL(BranchCode,''))) = '' OR BranchCode = @BranchCode)
    )
    SELECT
        ControlNo,
        ItemCount   = COUNT(*),
        TotalAmount = SUM(Amount),
        ItemDate    = MAX(ItemDate)
    FROM Collections
    WHERE ControlNo NOT IN (
        SELECT ControlNo FROM dbo.BankStatementRecon
        WHERE ItemType = 'DIT' AND AccountCode = @AccountCode AND ControlNo IS NOT NULL
    )
    GROUP BY ControlNo
    ORDER BY MAX(ItemDate) DESC;
END
GO

-------------------------------------------------------------------
-- 3. Bulk resolve for the DIT grid's Check-All + Bulk Resolve action.
-------------------------------------------------------------------
-- Re-running this script the same day must not fail if the type already exists and is
-- already referenced by sp_BankRecon_BulkResolveItems below (table types can't be dropped
-- while referenced) -- the type's shape isn't changing across re-runs, so just skip if present.
IF TYPE_ID('dbo.tt_BankReconIDList') IS NULL
    EXEC('CREATE TYPE dbo.tt_BankReconIDList AS TABLE (ReconID INT NOT NULL PRIMARY KEY)');
GO

IF OBJECT_ID('dbo.sp_BankRecon_BulkResolveItems', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_BankRecon_BulkResolveItems;
GO

CREATE PROCEDURE dbo.sp_BankRecon_BulkResolveItems
    @ReconIDs   dbo.tt_BankReconIDList READONLY,
    @ResolvedBy VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM @ReconIDs)
        THROW 93101, 'No items were selected to resolve.', 1;

    BEGIN TRY
        BEGIN TRAN;

        -- Same locked-period and reversed-item guards as the single-row
        -- sp_BankRecon_ResolveItem, applied set-based.
        IF EXISTS (
            SELECT 1
            FROM dbo.BankStatementRecon BSR
            JOIN dbo.BankReconHeader H ON BSR.HeaderID = H.HeaderID
            JOIN @ReconIDs R ON R.ReconID = BSR.ReconID
            WHERE H.Status = 'LOCKED'
        )
            THROW 93102, 'Cannot resolve items in a locked period.', 1;

        IF EXISTS (
            SELECT 1 FROM dbo.BankStatementRecon BSR
            JOIN @ReconIDs R ON R.ReconID = BSR.ReconID
            WHERE BSR.ResolvedReason = 'REVERSED'
        )
            THROW 93103, 'One or more selected items were already resolved by a payment reversal.', 1;

        UPDATE BSR
        SET IsResolved     = 1,
            ResolvedDate   = GETDATE(),
            ResolvedBy     = @ResolvedBy,
            ResolvedReason = 'CLEARED'
        FROM dbo.BankStatementRecon BSR
        JOIN @ReconIDs R ON R.ReconID = BSR.ReconID
        WHERE BSR.ItemType = 'DIT' AND BSR.IsResolved = 0;

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

-------------------------------------------------------------------
-- 4. sp_BankRecon_SaveItem: add @ControlNo, and fix the three hardcoding
--    bugs described at the top of this file (ItemType, ReferenceNo/
--    SourceRef swap, and BranchCode).
-------------------------------------------------------------------
IF OBJECT_ID('dbo.sp_BankRecon_SaveItem', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.sp_BankRecon_SaveItem_bak_20260903', 'P') IS NULL
        EXEC sp_rename 'dbo.sp_BankRecon_SaveItem', 'sp_BankRecon_SaveItem_bak_20260903';
    ELSE
        DROP PROCEDURE dbo.sp_BankRecon_SaveItem;
END
GO

CREATE PROCEDURE [dbo].[sp_BankRecon_SaveItem]
    @BranchCode       VARCHAR(5),
    @AccountCode      VARCHAR(20),
    @PeriodEnd        DATE,
    @BankStatementBal DECIMAL(19,2),
    @ItemType         VARCHAR(5),
    @ReferenceNo      VARCHAR(150),
    @ItemDate         DATE,
    @Payee            VARCHAR(200) = NULL,
    @Amount           DECIMAL(19,2),
    @Remarks          VARCHAR(500) = NULL,
    @User             VARCHAR(50),
    @ControlNo        VARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @ItemType NOT IN ('OC','DIT','BCM','BDM','BC','NSF')
        THROW 60001, 'Invalid ItemType. Use: OC, DIT, BCM, BDM, BC, NSF', 1;

    IF @Amount <= 0
        THROW 60002, 'Amount must be greater than zero.', 1;

    -- TOCTOU guard: sp_BankRecon_GetControlNoCandidates only excludes a ControlNo already
    -- saved as a DIT row at the moment the picker was populated -- two "Add DIT" dialogs
    -- opened before either is saved (or a double-click on Save) could otherwise both carry
    -- the same ControlNo and both insert, double-counting that deposit.
    IF @ItemType = 'DIT' AND @ControlNo IS NOT NULL AND EXISTS (
        SELECT 1 FROM dbo.BankStatementRecon
        WHERE ItemType = 'DIT' AND AccountCode = @AccountCode AND ControlNo = @ControlNo
    )
        THROW 60003, 'This Control No has already been added as a Deposit in Transit for this account.', 1;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @ReconHeaderID INT;

        EXEC sp_BankRecon_GetOrCreateHeader
            @BranchCode = @BranchCode, @AccountCode = @AccountCode,
            @PeriodEnd  = @PeriodEnd,  @CreatedBy   = @User,
            @HeaderID   = @ReconHeaderID OUTPUT;

        INSERT INTO [dbo].[BankStatementRecon]
            (HeaderID, BranchCode, AccountCode, PeriodEnd,
             ItemType, ReferenceNo, ItemDate, Payee, Amount, Remarks,
             IsResolved, AddedBy, DateTimeAdded,
             SourceModule, SourceRef, ResolvedReason, CreatedBy, CreatedDate, ControlNo)
        VALUES
            (@ReconHeaderID, @BranchCode, @AccountCode, @PeriodEnd, @ItemType,
             @ReferenceNo, @ItemDate, @Payee, @Amount,
             @Remarks,
             0, @User, GETDATE(), 'MANUAL BANK ENTRY', NULL, '',
             @User, GETDATE(), @ControlNo);

        DECLARE @NewID INT = SCOPE_IDENTITY();
        COMMIT TRAN;

        SELECT @NewID AS ReconID, 'OK' AS Result, 'Item saved.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH;
END;
GO

-------------------------------------------------------------------
-- 5. sp_BankRecon_GetPeriod: DIT result set now also returns ControlNo.
--    Everything else reproduced unchanged from the currently-deployed
--    version.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.sp_BankRecon_GetPeriod', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.sp_BankRecon_GetPeriod_bak_20260903', 'P') IS NULL
        EXEC sp_rename 'dbo.sp_BankRecon_GetPeriod', 'sp_BankRecon_GetPeriod_bak_20260903';
    ELSE
        DROP PROCEDURE dbo.sp_BankRecon_GetPeriod;
END
GO

CREATE PROCEDURE [dbo].[sp_BankRecon_GetPeriod]
    @BranchCode  CHAR(3),
    @AccountCode VARCHAR(20),
    @PeriodEnd   DATE
AS
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
    FROM BankReconHeader H
    LEFT JOIN ChartOfAccounts CA ON CA.AccountCode = H.AccountCode
    OUTER APPLY (
        SELECT ISNULL(SUM(Amount), 0) AS TotalDIT
        FROM BankStatementRecon WHERE HeaderID = H.HeaderID AND ItemType = 'DIT'
    ) DIT
    OUTER APPLY (
        SELECT ISNULL(SUM(Amount), 0) AS TotalOC
        FROM BankStatementRecon WHERE HeaderID = H.HeaderID AND ItemType = 'OC'
    ) OC
    WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd <= @PeriodEnd;

    -- DIT ROWS -- ControlNo added
    SELECT
        BSR.ReconID,
        BSR.ItemDate,
        BSR.Payee,
        BSR.Amount,
        BSR.IsResolved,
        BSR.ControlNo,
        CASE WHEN BSR.SourceModule IS NOT NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsAutoInserted
    FROM BankStatementRecon BSR
    JOIN BankReconHeader H ON BSR.HeaderID = H.HeaderID
    WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd <= @PeriodEnd
      AND BSR.ItemType = 'DIT'
    ORDER BY BSR.ReconID DESC

    -- OC ROWS -- unchanged
    SELECT
        BSR.ReconID,
        BSR.ItemDate,
        BSR.Payee,
        BSR.Amount,
        BSR.IsResolved
    FROM BankStatementRecon BSR
    JOIN BankReconHeader H ON BSR.HeaderID = H.HeaderID
    WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd <= @PeriodEnd
      AND BSR.ItemType = 'OC'
    ORDER BY BSR.ReconID DESC

    -- BANK-SIDE ROWS (BCM / BDM / BC / NSF / ADB) -- unchanged
    SELECT BSR.ReconID, BSR.HeaderID, BSR.ItemType, BSR.ItemDate, BSR.Payee, BSR.ReferenceNo,
           BSR.Amount, BSR.IsResolved, BSR.ResolvedDate, BSR.ResolvedReason,
           BSR.SourceModule, BSR.SourceRef, BSR.CreatedBy, BSR.CreatedDate,
           BSR.PostedPaymentRef,
           CASE WHEN BSR.SourceModule IS NOT NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsAutoInserted
    FROM BankStatementRecon BSR
    JOIN BankReconHeader H ON BSR.HeaderID = H.HeaderID
    WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd <= @PeriodEnd
      AND BSR.ItemType IN ('BCM','BDM','BC','NSF','ADB')
    ORDER BY BSR.ReconID DESC

END
GO

PRINT 'DEPLOYMENT COMPLETE: BankStatementRecon.ControlNo, sp_BankRecon_GetControlNoCandidates, tt_BankReconIDList, sp_BankRecon_BulkResolveItems, sp_BankRecon_SaveItem (fixed + ControlNo), sp_BankRecon_GetPeriod (+ControlNo).';
