SET NOCOUNT ON;
PRINT '=== sp_AddBranchOrderBatch: skip negative-inventory rows instead of aborting the whole batch ===';
GO

-- =============================================
-- BUG (Orders/AddBranchOrderSTSBatchMode.cs, executeTransfer()):
-- User checks "process all" including items already flagged NEGATIVE
-- INVENTORY in the grid. The warning dialog only asks "continue?" -- it
-- never actually excludes those rows from the DataTable sent to
-- sp_AddBranchOrderBatch.
--
-- Worse, sp_AddBranchOrderBatch itself has no per-row error isolation: it
-- loops calling EXEC dbo.sp_AddBranchOrder once per line, each with its own
-- internal BEGIN TRAN/COMMIT/ROLLBACK, but the loop has no TRY/CATCH of its
-- own. Confirmed live (rollback-wrapped, nothing committed) against
-- CORECSERP_002_DEV with a 2-row batch (good item, then a deliberately
-- oversized bad item): sp_AddBranchOrder correctly rejects the bad row via
-- RAISERROR, but that error is uncaught here -- it aborts the whole
-- procedure call. In real production (no ambient .NET transaction wraps
-- this call), any row processed BEFORE the bad one is already durably
-- committed by its own internal COMMIT TRAN, while the caller only sees a
-- hard failure -- so what actually gets deducted depends on row order and
-- is disconnected from what the C# side reports to the user.
--
-- FIX (paired with a client-side pre-filter in executeTransfer() that stops
-- sending already-flagged negative rows in the first place):
--   1. Wrap each row's EXEC dbo.sp_AddBranchOrder in its own TRY/CATCH.
--      A failure on one row (e.g. a race condition -- inventory changed
--      between grid-load and Save-click) no longer aborts the remaining
--      rows; it's recorded and the loop continues.
--   2. Return a result set of skipped items (ProductCode, ProductName,
--      Reason) so the C# side can tell the user exactly what was skipped
--      and why, instead of a generic try/catch popup.
--   3. Add @PreparedBy as an explicit, DEFAULTED parameter. Prerequisite,
--      not scope creep: the C# side already sends @PreparedBy (matching
--      the ENZODEV copy of this SP), but this dev copy didn't declare it --
--      confirmed live that every call from this screen currently fails
--      outright with "too many arguments specified" before ever reaching
--      the negative-inventory logic. Defaulted to 'system' (the prior
--      hardcoded value) so this stays backward compatible; only one caller
--      exists in the whole solution (grep-confirmed).
-- sp_AddBranchOrder's own insufficient-stock check remains the single
-- source of truth for "is this deductible" -- not duplicated here.
-- =============================================

IF OBJECT_ID('dbo.sp_AddBranchOrderBatch_OLD_08182026131447', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.sp_AddBranchOrderBatch', 'P') IS NOT NULL
        DROP PROCEDURE dbo.sp_AddBranchOrderBatch;
END
ELSE IF OBJECT_ID('dbo.sp_AddBranchOrderBatch', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.sp_AddBranchOrderBatch', 'sp_AddBranchOrderBatch_OLD_08182026131447';
END
GO

CREATE PROCEDURE [dbo].[sp_AddBranchOrderBatch]
    @TransferItems dbo.TransferItemType READONLY,
    @PONumber      VARCHAR(10),
    @DeliveryNo    VARCHAR(10),
    @ReferenceNo   VARCHAR(10),
    @BranchCode    VARCHAR(10),
    @PreparedBy    VARCHAR(50) = 'system'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OriginCode VARCHAR(10);

    SELECT @OriginCode = BranchCode FROM TransferOrderSummary WHERE PONumber = @PONumber;

    DECLARE @Item TABLE (
        RowID               INT IDENTITY(1,1),
        ProductCategoryCode VARCHAR(10),
        ProductCode         VARCHAR(10),
        ProductName         VARCHAR(100),
        Qty                 DECIMAL(9,3)
    );

    INSERT INTO @Item (ProductCategoryCode, ProductCode, ProductName, Qty)
    SELECT ProductCategoryCode, ProductCode, ProductName, Qty
    FROM @TransferItems;

    DECLARE @SkippedItems TABLE (
        ProductCode VARCHAR(10),
        ProductName VARCHAR(100),
        Reason      VARCHAR(400)
    );

    DECLARE @i INT = 1, @max INT = (SELECT COUNT(*) FROM @Item);
    WHILE @i <= @max
    BEGIN
        DECLARE @prodcatcode VARCHAR(10), @prodcode VARCHAR(10), @prodname VARCHAR(100), @qty DECIMAL(9,3);
        SELECT @prodcatcode = ProductCategoryCode, @prodcode = ProductCode, @prodname = ProductName, @qty = Qty
        FROM @Item WHERE RowID = @i;

        BEGIN TRY
            EXEC dbo.sp_AddBranchOrder
                @DeliveryNo, @ReferenceNo, @PONumber,
                @prodcatcode, @prodcode, @qty, '',
                @BranchCode, @OriginCode, @PreparedBy, '', 0;
        END TRY
        BEGIN CATCH
            INSERT INTO @SkippedItems (ProductCode, ProductName, Reason)
            VALUES (@prodcode, @prodname, ERROR_MESSAGE());
        END CATCH

        SET @i += 1;
    END

    SELECT ProductCode, ProductName, Reason FROM @SkippedItems;
END
GO

PRINT 'DEPLOYMENT COMPLETE: sp_AddBranchOrderBatch now isolates each line item, skips (not aborts on) insufficient-stock rows, and reports what was skipped.';
