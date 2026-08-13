SET NOCOUNT ON;
PRINT '=== funcview_TransferOrderDetailsSTS: expose raw ProductCode + sp_ApproveTransferOrder ===';
GO
EXEC sp_rename 'dbo.funcview_TransferOrderDetailsSTS', 'funcview_TransferOrderDetailsSTS_OLD_08092026100409';
GO
SET QUOTED_IDENTIFIER ON;
GO
-- =============================================
-- Author:      (original undated); rewritten 2026-08-09
-- Description: Same as the legacy version -- one row per product requested on a Stock Transfer
--              PO, with available warehouse inventory and a pass/fail status. Now also exposes
--              the raw ProductCode column (the old version only exposed a concatenated
--              "ProductCode - Description" display string) so the caller can identify which
--              product a row is without parsing that string -- needed by
--              Orders/STSForApprovalDetails.cs to know which TransferOrderDetails rows to
--              update when the approver edits ApprovedQty (see sp_ApproveTransferOrder below).
--              Hidden in that grid; other existing callers (ReceivedSTS.cs, ViewBranchOrderSTS.cs,
--              and the other POForApprovalSTS.cs tabs) use SELECT * and will just gain this one
--              extra column -- additive, not a breaking change, but flagging it since they weren't
--              updated to hide it.
--
-- The previous version is preserved as funcview_TransferOrderDetailsSTS_OLD_08092026100409.
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
	WITH Req AS (
    SELECT
		a.PONumber,
        a.ProductCode,
        SUM(a.Qty) AS RequestedQty,
        MAX(a.Units) AS Units
    FROM dbo.TransferOrderDetails AS a
    WHERE a.PONumber = @parmpono
    GROUP BY a.ProductCode,a.PONumber
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
        WHEN COALESCE(inv.AvailableInv, 0) < r.RequestedQty THEN 'NEGATIVE INVENTORY'
        ELSE 'PASSED'
    END AS Status
FROM Req AS r
JOIN dbo.Products AS p
  ON p.ProductCode = r.ProductCode
 AND p.BranchCode  = @parmbranchcode
LEFT JOIN Inv AS inv
  ON inv.Product = r.ProductCode
LEFT JOIN dbo.ProductCategory AS pc
  ON pc.ProductCategoryID = p.ProductCategoryCode
);
GO
PRINT 'funcview_TransferOrderDetailsSTS rewritten.';
GO

-- Lines the caller (Orders/STSForApprovalDetails.cs, gridView1) wants applied when approving --
-- one row per product, the edited ApprovedQty. Since every PONumber+ProductCode combination in
-- production data today maps to exactly one TransferOrderDetails row (verified against this DB),
-- the update below applies directly by PONumber+ProductCode; it is NOT a proportional split
-- across multiple lines for the same product. If that ever becomes possible, this will need
-- revisiting.
IF TYPE_ID('dbo.tt_TransferApprovalLines') IS NULL
    CREATE TYPE dbo.tt_TransferApprovalLines AS TABLE
    (
        ProductCode  char(5)        NOT NULL,
        ApprovedQty  decimal(12,3)  NOT NULL
    );
GO
IF OBJECT_ID('dbo.sp_ApproveTransferOrder') IS NOT NULL
    DROP PROCEDURE dbo.sp_ApproveTransferOrder;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- =============================================
-- Author:      2026-08-09
-- Description: Approve or reject a Stock Transfer Order request
--              (Orders/STSForApprovalDetails.cs -- replaces the four near-identical button
--              handlers: btnapprove_Click/btnadd_Click for approve, btnreject_Click/
--              simpleButton9_Click for reject, all of which ran the same raw UPDATE
--              TransferOrderSummary statement). On approval, also writes the approver's edited
--              ApprovedQty back to TransferOrderDetails per product -- the column already
--              existed on the table but nothing in the application read or wrote it until now.
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
            JOIN @Lines l ON d.PONumber = @parmpono AND d.ProductCode = l.ProductCode;
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
PRINT 'DEPLOYMENT COMPLETE: sp_ApproveTransferOrder created, funcview_TransferOrderDetailsSTS rewritten (original preserved as funcview_TransferOrderDetailsSTS_OLD_08092026100409).';
