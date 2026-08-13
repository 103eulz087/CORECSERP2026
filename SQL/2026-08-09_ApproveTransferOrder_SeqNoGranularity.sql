SET NOCOUNT ON;
PRINT '=== funcview_TransferOrderDetailsSTS / sp_ApproveTransferOrder: per-line (SeqNo) granularity ===';
GO
EXEC sp_rename 'dbo.funcview_TransferOrderDetailsSTS', 'funcview_TransferOrderDetailsSTS_OLD_08092026101247';
GO
SET QUOTED_IDENTIFIER ON;
GO
-- =============================================
-- Author:      rewritten 2026-08-09 (second pass, same day)
-- Description: One row per REQUESTED LINE (TransferOrderDetails.SeqNo), not one row per product.
--              The prior version (funcview_TransferOrderDetailsSTS_OLD_08092026100409, itself a
--              same-day rewrite) grouped by ProductCode and SUMmed Qty across lines -- that
--              collapsed multiple lines for the same product into a single row. Per the actual
--              design, the same product can legitimately appear on more than one line because
--              items are prepped per box, and each box-line can carry a different quantity and
--              needs its own ApprovedQty -- not one shared value forced across every line for
--              that product. SeqNo is TransferOrderDetails' real PK grain (with PONumber), so
--              this is more correct, not less, than the product-level grouping it replaces.
--
--              AvailableInv/Status are still computed against the PRODUCT's total demand across
--              all of its lines (ProductTotals CTE) -- inventory is a shared pool across those
--              lines, so "NEGATIVE INVENTORY" should reflect the combined ask, not just
--              whichever single line happens to be showing.
--
-- The previous version is preserved as funcview_TransferOrderDetailsSTS_OLD_08092026101247.
-- =============================================
CREATE FUNCTION [dbo].[funcview_TransferOrderDetailsSTS]
(
	@parmbranchcode char(3),
	@parmpono varchar(10)
)
RETURNS TABLE
AS
RETURN
(
	WITH Lines AS (
    SELECT
        a.PONumber,
        a.SeqNo,
        a.ProductCode,
        a.Qty AS RequestedQty,
        a.Units
    FROM dbo.TransferOrderDetails AS a
    WHERE a.PONumber = @parmpono
),
ProductTotals AS (
    SELECT ProductCode, SUM(RequestedQty) AS TotalRequestedQty
    FROM Lines
    GROUP BY ProductCode
),
Inv AS (
    SELECT
        i.Product,
        SUM(i.Available) AS AvailableInv
    FROM dbo.Inventory AS i
    WHERE i.Branch = @parmbranchcode
      AND i.IsWarehouse = 1
      AND i.Available > 0
    GROUP BY i.Product
)
SELECT
	r.PONumber,
	r.SeqNo,
	pc.Description AS Category,
	r.ProductCode,
    CONCAT(r.ProductCode,' - ',p.Description) AS Product,
    p.Description AS ProductName,
	p.Barcode,
    r.RequestedQty AS QtyRequested,
    COALESCE(inv.AvailableInv, 0) AS AvailableInv,
	ISNULL(r.RequestedQty,0) AS ApprovedQty,
    CASE
        WHEN COALESCE(inv.AvailableInv, 0) = 0 THEN 'NO INVENTORY'
        WHEN COALESCE(inv.AvailableInv, 0) < pt.TotalRequestedQty THEN 'NEGATIVE INVENTORY'
        ELSE 'PASSED'
    END AS Status
FROM Lines AS r
JOIN ProductTotals AS pt
  ON pt.ProductCode = r.ProductCode
JOIN dbo.Products AS p
  ON p.ProductCode = r.ProductCode
 AND p.BranchCode  = @parmbranchcode
LEFT JOIN Inv AS inv
  ON inv.Product = r.ProductCode
LEFT JOIN dbo.ProductCategory AS pc
  ON pc.ProductCategoryID = p.ProductCategoryCode
);
GO
PRINT 'funcview_TransferOrderDetailsSTS rewritten (per-line).';
GO

-- sp_ApproveTransferOrder depends on tt_TransferApprovalLines, so it has to go before the type
-- can be dropped and recreated (SQL Server has no ALTER TYPE for table types).
IF OBJECT_ID('dbo.sp_ApproveTransferOrder') IS NOT NULL
    DROP PROCEDURE dbo.sp_ApproveTransferOrder;
GO
IF TYPE_ID('dbo.tt_TransferApprovalLines') IS NOT NULL
    DROP TYPE dbo.tt_TransferApprovalLines;
GO
-- Now keyed by SeqNo (TransferOrderDetails' real PK grain, with PONumber) instead of ProductCode
-- -- ProductCode is no longer sufficient to identify which line an edited ApprovedQty belongs to.
CREATE TYPE dbo.tt_TransferApprovalLines AS TABLE
(
    SeqNo        decimal(3,0)   NOT NULL,
    ApprovedQty  decimal(12,3)  NOT NULL
);
GO
SET QUOTED_IDENTIFIER ON;
GO
-- =============================================
-- Author:      rewritten 2026-08-09 (second pass, same day)
-- Description: Same as the first pass (see SQL/2026-08-09_ApproveTransferOrder_ApprovedQty.sql)
--              except the ApprovedQty update now joins on (PONumber, SeqNo) instead of
--              (PONumber, ProductCode) -- see funcview_TransferOrderDetailsSTS's rewrite above
--              for why: the same product can appear on multiple lines (box-level prep), each
--              needing its own approved quantity.
-- =============================================
CREATE PROCEDURE [dbo].[sp_ApproveTransferOrder]
    @parmpono     varchar(10),
    @parmuser     varchar(50),
    @parmremarks  varchar(200),
    @parmaction   varchar(20),   -- 'APPROVED' or 'REJECTED'
    @Lines        dbo.tt_TransferApprovalLines READONLY
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF @parmaction NOT IN ('APPROVED', 'REJECTED')
            THROW 59501, 'Action must be APPROVED or REJECTED.', 1;

        UPDATE TransferOrderSummary
           SET Status       = @parmaction,
               Remarks      = @parmremarks,
               ApprovedBy   = @parmuser,
               DateApproved = CAST(GETDATE() AS DATE)
         WHERE PONumber = @parmpono;

        IF @@ROWCOUNT = 0
            THROW 59502, 'PO Number not found.', 1;

        IF @parmaction = 'APPROVED'
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM @Lines)
                THROW 59503, 'No line items submitted for approval.', 1;

            UPDATE d
               SET d.ApprovedQty = l.ApprovedQty
            FROM TransferOrderDetails d
            JOIN @Lines l ON d.PONumber = @parmpono AND d.SeqNo = l.SeqNo;
        END

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;

        DECLARE @EMsg  NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ESev  INT            = ERROR_SEVERITY();
        DECLARE @ESt   INT            = ERROR_STATE();
        DECLARE @ELine INT            = ERROR_LINE();
        DECLARE @EProc NVARCHAR(128)  = ISNULL(ERROR_PROCEDURE(), 'sp_ApproveTransferOrder');
        RAISERROR('Error in %s (line %d): %s', @ESev, @ESt, @EProc, @ELine, @EMsg);
    END CATCH
END
GO
PRINT 'DEPLOYMENT COMPLETE: sp_ApproveTransferOrder rewritten (SeqNo-keyed), funcview_TransferOrderDetailsSTS rewritten (per-line).';
