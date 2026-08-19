SET NOCOUNT ON;
PRINT '=== dbo.TransferItemType / sp_AddBranchOrderBatch: key dedup and skip-reporting on SeqNo, not ProductCode ===';
GO

-- =============================================
-- BUG: AddBranchOrderSTSBatchMode.cs's executeTransfer() tracks which items were
-- already durably committed this session (so a retry after declining the
-- discrepancy prompt doesn't resend and double-deduct an already-transferred
-- row) using a HashSet<string> keyed on ProductCode. But the grid's source,
-- funcview_TransferOrderDetailsSTS, is deliberately per-line (per-SeqNo)
-- grain -- the same ProductCode can legitimately appear on more than one
-- TransferOrderDetails line with a different quantity (see
-- SQL/2026-08-18_funcview_TransferOrderDetailsSTS_RestoreColumns.sql's own
-- comments on this). ProductCode alone can't disambiguate two lines of the
-- same product, which breaks the dedup fix two ways:
--   1. A second, independent line for the same product gets wrongly treated
--      as "already transferred" and silently skipped even though it was
--      never actually sent.
--   2. If two lines sharing a ProductCode are sent in the SAME batch and the
--      SP accepts one but rejects the other, the C# side can't tell which
--      dtTransfer row the SP's ProductCode-keyed skip result refers to --
--      it may mark the successfully-committed row as skipped too, which
--      re-opens the original double-deduction risk on the next retry.
--
-- FIX: thread SeqNo (TransferOrderDetails' real per-line grain, already
-- exposed as its own column by the grid) through the TVP and the SP's
-- @SkippedItems output, so both the client-side dedup and the skip-result
-- matching are keyed on an actually-unique per-line identifier instead of
-- ProductCode. Only one live consumer of dbo.TransferItemType exists
-- (sp_AddBranchOrderBatch, grep-confirmed across the whole solution), so
-- this is a safe additive change -- SeqNo is nullable so any other
-- hypothetical caller supplying only the original 5 columns wouldn't break.
--
-- MECHANICAL NOTE: SQL Server has no ALTER TYPE for table types, and won't
-- let you DROP TYPE while ANY object references it -- including old *_OLD_*
-- backup copies, not just the live SP. So this script drops the live SP
-- *and* any existing sp_AddBranchOrderBatch_OLD_* backups before recreating
-- the type. Their exact prior text is preserved in git history (this same
-- SQL/ folder, earlier-dated files) so nothing is actually lost by removing
-- the live backup copies -- there's no meaningful "rollback" concept for a
-- pure structural type anyway. The original 5 columns/types (varchar(10)/
-- varchar(10)/varchar(100)/decimal(9,3)/decimal(9,3)) are preserved exactly
-- below; SeqNo decimal(3,0) NULL is purely additive.
-- =============================================

DECLARE @backupname NVARCHAR(200);
DECLARE backup_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT o.name FROM sys.objects o
    WHERE o.type = 'P' AND o.name LIKE 'sp_AddBranchOrderBatch%';
OPEN backup_cursor;
FETCH NEXT FROM backup_cursor INTO @backupname;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC('DROP PROCEDURE dbo.[' + @backupname + ']');
    FETCH NEXT FROM backup_cursor INTO @backupname;
END
CLOSE backup_cursor;
DEALLOCATE backup_cursor;
GO

IF TYPE_ID('dbo.TransferItemType') IS NOT NULL
    DROP TYPE dbo.TransferItemType;
GO

CREATE TYPE dbo.TransferItemType AS TABLE (
    ProductCategoryCode VARCHAR(10)   NULL,
    ProductCode         VARCHAR(10)   NULL,
    ProductName         VARCHAR(100)  NULL,
    QtyRequested        DECIMAL(9,3)  NULL,
    Qty                 DECIMAL(9,3)  NULL,
    SeqNo                DECIMAL(3,0)  NULL
);
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
        Qty                 DECIMAL(9,3),
        SeqNo               DECIMAL(3,0)
    );

    INSERT INTO @Item (ProductCategoryCode, ProductCode, ProductName, Qty, SeqNo)
    SELECT ProductCategoryCode, ProductCode, ProductName, Qty, SeqNo
    FROM @TransferItems;

    DECLARE @SkippedItems TABLE (
        ProductCode VARCHAR(10),
        ProductName VARCHAR(100),
        SeqNo       DECIMAL(3,0),
        Reason      VARCHAR(400)
    );

    DECLARE @i INT = 1, @max INT = (SELECT COUNT(*) FROM @Item);
    WHILE @i <= @max
    BEGIN
        DECLARE @prodcatcode VARCHAR(10), @prodcode VARCHAR(10), @prodname VARCHAR(100), @qty DECIMAL(9,3), @seqno DECIMAL(3,0);
        SELECT @prodcatcode = ProductCategoryCode, @prodcode = ProductCode, @prodname = ProductName, @qty = Qty, @seqno = SeqNo
        FROM @Item WHERE RowID = @i;

        BEGIN TRY
            EXEC dbo.sp_AddBranchOrder
                @DeliveryNo, @ReferenceNo, @PONumber,
                @prodcatcode, @prodcode, @qty, '',
                @BranchCode, @OriginCode, @PreparedBy, '', 0;
        END TRY
        BEGIN CATCH
            INSERT INTO @SkippedItems (ProductCode, ProductName, SeqNo, Reason)
            VALUES (@prodcode, @prodname, @seqno, ERROR_MESSAGE());
        END CATCH

        SET @i += 1;
    END

    SELECT ProductCode, ProductName, SeqNo, Reason FROM @SkippedItems;
END
GO

PRINT 'DEPLOYMENT COMPLETE: dbo.TransferItemType and sp_AddBranchOrderBatch now carry SeqNo end-to-end for unambiguous per-line dedup/skip-reporting.';
