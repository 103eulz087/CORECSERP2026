-- =============================================
-- Author: Eulz Avancena; 2026-09-04
-- Description: BankReconFormV2's Outstanding Checks (OC) grid gets the same
--              Selected-checkbox / Check-All / Bulk Resolve pattern already built for
--              the Deposits-in-Transit (DIT) grid. sp_BankRecon_BulkResolveItems was
--              hardcoded to ItemType='DIT' (a defensive guard against being called with
--              IDs from an unrelated grid) -- generalized to accept @ItemType so the
--              same procedure now serves both grids while keeping that same guard,
--              exactly mirroring how sp_BankRecon_ResolveItem (the single-row version)
--              already has no ItemType restriction at all.
-- =============================================

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.sp_BankRecon_BulkResolveItems', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.sp_BankRecon_BulkResolveItems_bak_20260904', 'P') IS NULL
        EXEC sp_rename 'dbo.sp_BankRecon_BulkResolveItems', 'sp_BankRecon_BulkResolveItems_bak_20260904';
    ELSE
        DROP PROCEDURE dbo.sp_BankRecon_BulkResolveItems;
END
GO

CREATE PROCEDURE dbo.sp_BankRecon_BulkResolveItems
    @ReconIDs   dbo.tt_BankReconIDList READONLY,
    @ResolvedBy VARCHAR(50),
    @ItemType   VARCHAR(5)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM @ReconIDs)
        THROW 93101, 'No items were selected to resolve.', 1;

    IF @ItemType NOT IN ('OC','DIT','BCM','BDM','BC','NSF')
        THROW 93104, 'Invalid ItemType. Use: OC, DIT, BCM, BDM, BC, NSF', 1;

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

PRINT 'DEPLOYMENT COMPLETE: sp_BankRecon_BulkResolveItems now accepts @ItemType (OC/DIT/...).';
