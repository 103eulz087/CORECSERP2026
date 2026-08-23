/* ================================================================================
   Consolidated catch-up patch for a lagging database, sourced entirely from
   CORECSERP_002_DEV's current state (reconstructed from this repo's SQL/
   history -- same-day revision conflicts were resolved using the embedded
   _OLD_MMDDYYYYHHMMSS backup-rename timestamps to find the true latest
   version of each object).

   Covers every object from your list that has a traceable, sourced
   definition in this repo. It does NOT include objects with no trace in
   source control -- those are called out below and must be supplied
   (e.g. via `sp_helptext '<name>'` or SSMS "Script as CREATE" against
   CORECSERP_002_DEV) before this script's dependents on them will actually
   run successfully.

   ================================================================================
   NOT INCLUDED -- no trace anywhere in this repo's history. CREATE PROCEDURE/
   FUNCTION/VIEW succeeds even when the body references a nonexistent object
   (T-SQL deferred name resolution), so the sections below that depend on
   these will deploy "successfully" but FAIL AT RUNTIME until you supply them:

     - sp_AddBranchOrder             <- hard prerequisite for sp_AddBranchOrderBatch (section 5)
     - sp_CancelDelivery             <- referenced by sp_ReverseSTSInventoryTransfer (not in this script)
     - sp_CancelDeliveryByBarcode
     - sp_AddBranchOrderByBarcode    <- only ever appears as a typo'd string inside
                                        sp_AddHRIOrderByBarcode's own error message;
                                        no such object was ever actually created
     - sp_AddBranchInventoryBatch
     - func_getTotalAmountOfPendingPO
     - funcview_ProcessOrderItemsSales
     - view_BranchOrderDetails       <- only ever mentioned in a comment, never defined
     - view_ReturnedSummary
     - spview_SalesInvoice
     - CreditMemo base table         <- hard prerequisite for section 7 (this script only
                                        ALTERs it; the column list below is inferred from
                                        sp_CreditMemo's own INSERT column list, but real
                                        data types/nullability/constraints are NOT verified)
     - DeliveryDetails.isCancelled / DateTimeAdded / DateTimeUpdated
     - InventoryDeliveryFIFO.SellingPrice / TotalAmount   <- hard prerequisite for
                                        sp_AddHRIOrderByBarcode (section 6): it INSERTs
                                        15 positional values including these two; the
                                        INSERT will fail on a column-count mismatch if
                                        they don't already exist on the target
     - DeliverySummary.TotalItemReturned / TotalItemSold

   Run `sp_helptext '<name>'` (or Object Explorer -> Script Table/Procedure/
   View/Function as -> CREATE) against CORECSERP_002_DEV for each, and paste
   the results back to fold them into a follow-up script in the right place.

   Also assumed already present on the target (foundational ticketing
   infrastructure used across many other already-deployed modules, not part
   of your list, not touched here): dbo.tt_AmountBreakdown,
   dbo.tt_TokenResolution, dbo.tt_ConditionFlags, dbo.sp_PostCompoundTicket,
   dbo.sp_PostCompoundTicketSales, dbo.func_getUsername, dbo.GetReferenceNumber.
   ================================================================================ */

SET NOCOUNT ON;
PRINT '=== Patch target DB to match CORECSERP_002_DEV (2026-08-23 consolidated) ===';
GO

-- ================================================================================
-- SECTION 1: Transfer Order Approval
--   dbo.tt_TransferApprovalLines (TYPE) -> TransferOrderDetails.ApprovedQty (col)
--   -> funcview_TransferOrderDetailsSTS (FUNCTION) -> sp_ApproveTransferOrder (PROC)
-- ================================================================================

PRINT '--- 1a. TransferOrderDetails.ApprovedQty column ---';
GO
-- Already live on CORECSERP_002_DEV (pre-existing before any of these scripts
-- ran -- nothing there added it either); included here because your target
-- database may not have it yet.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TransferOrderDetails') AND name = 'ApprovedQty')
    ALTER TABLE dbo.TransferOrderDetails ADD ApprovedQty decimal(12,3) NULL;
GO

PRINT '--- 1b. funcview_TransferOrderDetailsSTS (per-line/SeqNo grain, latest as of 2026-08-18) ---';
GO
IF OBJECT_ID('dbo.funcview_TransferOrderDetailsSTS_OLD_08232026PATCH', 'IF') IS NOT NULL
    DROP FUNCTION dbo.funcview_TransferOrderDetailsSTS_OLD_08232026PATCH;
GO
IF OBJECT_ID('dbo.funcview_TransferOrderDetailsSTS', 'IF') IS NOT NULL
    EXEC sp_rename 'dbo.funcview_TransferOrderDetailsSTS', 'funcview_TransferOrderDetailsSTS_OLD_08232026PATCH';
GO
-- =============================================
-- Author:      rewritten 2026-08-09, restored 2026-08-18 (untracked drift found live)
-- Description: One row per REQUESTED LINE (TransferOrderDetails.SeqNo), not one row
--              per product -- the same product can legitimately appear on more than
--              one line (box-level prep), each needing its own ApprovedQty.
--              AvailableInv/Status are computed against the PRODUCT's total demand
--              across all of its lines (ProductTotals CTE) -- inventory is a shared
--              pool across those lines.
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
        r.RequestedQty AS Qty,
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

PRINT '--- 1c. dbo.tt_TransferApprovalLines (TYPE, SeqNo-keyed) + sp_ApproveTransferOrder ---';
GO
-- sp_ApproveTransferOrder depends on this type, so it must be dropped first
-- (SQL Server has no ALTER TYPE for table types).
IF OBJECT_ID('dbo.sp_ApproveTransferOrder', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ApproveTransferOrder;
GO
IF TYPE_ID('dbo.tt_TransferApprovalLines') IS NOT NULL
    DROP TYPE dbo.tt_TransferApprovalLines;
GO
CREATE TYPE dbo.tt_TransferApprovalLines AS TABLE
(
    SeqNo        decimal(3,0)   NOT NULL,
    ApprovedQty  decimal(12,3)  NOT NULL
);
GO
-- =============================================
-- Author:      2026-08-09 (second pass, same day -- SeqNo-keyed)
-- Description: Approve or reject a Stock Transfer Order request
--              (Orders/STSForApprovalDetails.cs). On approval, writes the
--              approver's edited ApprovedQty back to TransferOrderDetails,
--              keyed by (PONumber, SeqNo) -- not ProductCode, since the same
--              product can appear on multiple lines (box-level prep).
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

-- ================================================================================
-- SECTION 2: spr_STSSummary (independent -- no type/column prerequisites)
-- ================================================================================

PRINT '--- 2. spr_STSSummary ---';
GO
IF OBJECT_ID('dbo.spr_STSSummary', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spr_STSSummary', 'spr_STSSummary_OLD_08232026PATCH';
GO
-- =============================================
-- Author:      Eulz Avancena (original); rewritten 2026-08-11
-- Description: Feeds StocksOrder.cs. Branches between a genuine STS transfer
--              (TransferOrderSummary/TransferOrderDetails) and a regular
--              Products sales order (PurchaseOrderSummary/PurchaseOrderDetails)
--              depending on which table the PONumber actually belongs to,
--              detected via EXISTS against TransferOrderSummary (not the
--              legacy, always-false PurchaseOrderSummary.BranchCode check).
-- =============================================
CREATE PROC [dbo].[spr_STSSummary]
    @parmpono VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @isSTS BIT = CASE
        WHEN EXISTS (SELECT 1 FROM TransferOrderSummary WHERE PONumber = @parmpono) THEN 1
        ELSE 0
    END;

    CREATE TABLE #temptable (
        SeqNo BIGINT,
        BranchCode CHAR(3),
        PONumber VARCHAR(10),
        ProductCode CHAR(5),
        ProductName VARCHAR(100),
        Qty DECIMAL(10,3),
        Unit VARCHAR(10),
        SellingPrice DECIMAL(10,2),
        Cost DECIMAL(10,2),
        TotalAmount DECIMAL(10,2),
        Description VARCHAR(250),
        BarcodeNo VARCHAR(35),
        Dispatch DECIMAL(10,3),
        Received DECIMAL(10,3)
    );

    IF @isSTS = 1
    BEGIN
        INSERT INTO #temptable
        SELECT
            dd.SeqNo,
            a.InitiatingBranch,
            a.PONumber,
            dd.ProductNo,
            dd.ProductName,
            b.Qty,
            b.Units,
            d.SellingPrice,
            0,
            dd.QtyDelivered * d.SellingPrice,
            c.Description,
            d.Barcode,
            dd.QtyDelivered,
            0
        FROM TransferOrderSummary a
        INNER JOIN DeliveryDetails dd
            ON a.PONumber COLLATE SQL_Latin1_General_CP1_CI_AS = dd.PONumber
            AND dd.isCancelled = 0
            AND dd.isReturned = 0
        INNER JOIN Products d ON dd.ProductNo = d.ProductCode AND d.BranchCode = a.BranchCode COLLATE SQL_Latin1_General_CP1_CI_AS
        INNER JOIN ProductCategory c ON c.ProductCategoryID = d.ProductCategoryCode
        INNER JOIN TransferOrderDetails b
            ON a.PONumber COLLATE SQL_Latin1_General_CP1_CI_AS = b.PONumber
            AND b.ProductCode = dd.ProductNo
        WHERE a.PONumber COLLATE SQL_Latin1_General_CP1_CI_AS = @parmpono;
    END
    ELSE
    BEGIN
        INSERT INTO #temptable
        SELECT
            dd.SeqNo,
            a.BranchCode,
            a.PONumber,
            dd.ProductNo,
            dd.ProductName,
            b.Qty,
            b.Units,
            d.SellingPrice,
            0,
            dd.QtyDelivered * d.SellingPrice,
            c.Description,
            d.Barcode,
            dd.QtyDelivered,
            0
        FROM PurchaseOrderSummary a
        INNER JOIN PurchaseOrderDetails b ON a.PONumber = b.PONumber
        INNER JOIN DeliveryDetails dd ON a.PONumber = dd.PONumber
            AND dd.isReturned = 0
            AND dd.isCancelled = 0
        INNER JOIN Products d ON b.ProductCode COLLATE SQL_Latin1_General_CP1_CI_AS = d.ProductCode COLLATE SQL_Latin1_General_CP1_CI_AS AND d.BranchCode = a.BranchCode COLLATE SQL_Latin1_General_CP1_CI_AS
        INNER JOIN ProductCategory c ON c.ProductCategoryID = d.ProductCategoryCode
        WHERE a.PONumber = @parmpono;
    END

    UPDATE t
    SET t.Received = r.Qty
    FROM #temptable t
    INNER JOIN ReceivedOrderDetails r ON r.PONumber COLLATE SQL_Latin1_General_CP1_CI_AS = t.PONumber COLLATE SQL_Latin1_General_CP1_CI_AS
        AND r.ProductCode COLLATE SQL_Latin1_General_CP1_CI_AS = t.ProductCode COLLATE SQL_Latin1_General_CP1_CI_AS;

    UPDATE t
    SET t.Cost = i.Cost
    FROM #temptable t
    INNER JOIN InventoryDeliveryFIFO i
        ON i.PONumber COLLATE SQL_Latin1_General_CP1_CI_AS = t.PONumber COLLATE SQL_Latin1_General_CP1_CI_AS
        AND t.SeqNo = i.DevDetSeqNo
        AND i.ProductNo COLLATE SQL_Latin1_General_CP1_CI_AS = t.ProductCode COLLATE SQL_Latin1_General_CP1_CI_AS;

    SELECT
        SeqNo,
        ProductCode,
        ProductName,
        BarcodeNo,
        Qty AS QtyReq,
        Dispatch AS QtyDispatch,
        Qty - Dispatch AS Variance,
        Cost,
        FORMAT(Dispatch * Cost, 'N', 'en-us') AS TotalCost,
        '' AS Received
    FROM #temptable
    ORDER BY ProductName ASC;
END
GO

-- ================================================================================
-- SECTION 3: sp_ConfirmBranchOrderSTS (your list said sp_ConfirmBranchOrder --
--   confirmed with you this is the real object)
-- ================================================================================

PRINT '--- 3. sp_ConfirmBranchOrderSTS ---';
GO
IF OBJECT_ID('dbo.sp_ConfirmBranchOrderSTS_OLD_08232026PATCH', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ConfirmBranchOrderSTS_OLD_08232026PATCH;
GO
IF OBJECT_ID('dbo.sp_ConfirmBranchOrderSTS', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_ConfirmBranchOrderSTS', 'sp_ConfirmBranchOrderSTS_OLD_08232026PATCH';
GO
-- =============================================
-- Author:      rewritten 2026-08-17
-- Description: Confirms an HO-side STS branch delivery order -- FIFO cost
--              recalculation, DeliverySummary upsert, GL ticket posting
--              (IT-HO-VAT/IT-HO-VATEX via sp_PostCompoundTicket), guarded
--              against confirming an empty delivery (zero DeliveryDetails
--              lines) which previously crashed on a NULL SUM() inserted into
--              a NOT NULL column.
-- =============================================
CREATE PROCEDURE [dbo].[sp_ConfirmBranchOrderSTS]
(
    @parmdevno           VARCHAR(20),
    @parmrefno           VARCHAR(10),
    @parmeffectivitydate DATE,
    @parmpono            VARCHAR(10),
    @parmbarcode         VARCHAR(50),
    @parmbranchcode      VARCHAR(10),
    @parmorigin          VARCHAR(10), -- not used
    @preparedby          VARCHAR(30)
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @username VARCHAR(50);
        SELECT @username = dbo.func_getUsername(@preparedby);

        IF NOT EXISTS (
            SELECT 1 FROM DeliveryDetails
            WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono
              AND isReturned = 0 AND isCancelled = 0
        )
            THROW 58161, 'Cannot confirm: no line items found for this delivery. Add at least one product before confirming.', 1;

        DECLARE @ProductCosting TABLE (
            ProductCode VARCHAR(10),
            Qty         FLOAT,
            Cost        MONEY,
            TotalCost   MONEY
        );

        INSERT INTO @ProductCosting (ProductCode, Qty, Cost, TotalCost)
        SELECT I.ProductNo,
               SUM(I.QtyDelivered),
               SUM(I.Cost),
               SUM(I.TotalCost)
        FROM InventoryDeliveryFIFO I
        WHERE I.PONumber = @parmpono AND I.DeliveryNo = @parmdevno and I.isErrorCorrect=0
        GROUP BY I.ProductNo;

        UPDATE dd
        SET dd.Cost =  isnull(i.Cost,0)
        FROM DeliveryDetails dd
        INNER JOIN InventoryDeliveryFIFO i
            ON dd.PONumber=i.PONumber
            and dd.SeqNo=i.DevDetSeqNo
            and dd.ProductNo=i.ProductNo
            and i.isErrorCorrect=0
        WHERE dd.PONumber = @parmpono
        AND dd.DeliveryNo = @parmdevno;

        SELECT TOP (1) @parmeffectivitydate = EffectivityDate
        FROM TransferOrderSummary WITH (NOLOCK)
        WHERE PONumber = @parmpono;

        DECLARE @totalitem INT, @totalqtydelivered FLOAT;
        SELECT @totalitem = COUNT(*), @totalqtydelivered = SUM(QtyDelivered)
        FROM DeliveryDetails
        WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono  and isReturned=0 and isCancelled=0;

        SET @totalitem         = ISNULL(@totalitem, 0);
        SET @totalqtydelivered = ISNULL(@totalqtydelivered, 0);

        IF NOT EXISTS (SELECT 1 FROM DeliverySummary WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono)
        BEGIN
            INSERT INTO [dbo].[DeliverySummary]
                ([DeliveryNo],[PONumber],[ReferenceNumber],[InvoiceNo],[BranchCode],
                 [TotalItem],[TotalQtyDelivered],[TotalActualQty],[TotalVarianceVat],
                 [TotalVarianceVatExempt],[EffectivityDate],[Status],[DateAdded],
                 [PreparedBy],[isSettled],[isInvoiceUpdate])
            VALUES
                (@parmdevno, @parmpono, @parmrefno, @parmrefno, @parmbranchcode,
                 @totalitem, @totalqtydelivered, 0, 0,
                 0, @parmeffectivitydate, 'FOR DELIVERY', GETDATE(),
                 @preparedby, 0, 0);
        END
        ELSE
        BEGIN
            UPDATE DeliverySummary
            SET TotalItem = (SELECT ISNULL(COUNT(*),0) FROM DeliveryDetails WHERE PONumber=@parmpono),
                TotalQtyDelivered = (SELECT ISNULL(SUM(QtyDelivered),0) FROM DeliveryDetails WHERE PONumber=@parmpono and isCancelled=0 and isReturned=0),
                TotalItemSold = (SELECT ISNULL(COUNT(*),0) FROM DeliveryDetails WHERE PONumber=@parmpono and isCancelled=0 and isReturned=0),
                TotalItemReturned = (SELECT ISNULL(COUNT(*),0) FROM DeliveryDetails WHERE PONumber=@parmpono and isReturned=0),
                Status = 'FOR DELIVERY'
            WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono;
        END

        DECLARE @overalltotalcostnonvat MONEY, @overalltotalcostwithvat MONEY;

        SELECT @overalltotalcostnonvat  = SUM(CASE WHEN IsVat = '0' THEN ISNULL(TotalCost,0) END),
               @overalltotalcostwithvat = SUM(CASE WHEN IsVat = '1' THEN ISNULL(TotalCost,0) END)
        FROM InventoryDeliveryFIFO
        WHERE BranchCode = @parmbranchcode
          AND PONumber = @parmpono
          AND DeliveryNo = @parmdevno
          AND isErrorCorrect=0;

        SET @overalltotalcostnonvat  = ISNULL(@overalltotalcostnonvat, 0);
        SET @overalltotalcostwithvat = ISNULL(@overalltotalcostwithvat, 0);

        DECLARE @TicketBranchCode VARCHAR(10) = '888';
        DECLARE @MnemonicVAT      VARCHAR(20) = 'IT-HO-VAT';
        DECLARE @MnemonicVATEX    VARCHAR(20) = 'IT-HO-VATEX';

        DECLARE @outrefnum VARCHAR(10), @Particulars VARCHAR(400);
        EXEC GetReferenceNumber @outrefnum OUTPUT;

        SET @Particulars = 'Inventory Transfer Out - PO#' + @parmpono + ' (to Branch ' + @parmbranchcode + ')- VATable';

        IF @overalltotalcostwithvat > 0
        BEGIN
            DECLARE @AmtsVAT dbo.tt_AmountBreakdown, @TokVAT dbo.tt_TokenResolution, @FlgVAT dbo.tt_ConditionFlags;
            INSERT @AmtsVAT VALUES ('GROSS', @overalltotalcostwithvat);

            EXEC [dbo].[sp_PostCompoundTicket]
                @Mnemonic        = @MnemonicVAT,
                @TicketDate      = @parmeffectivitydate,
                @BranchCode      = @TicketBranchCode,
                @ReferenceNumber = @outrefnum,
                @ReferenceKey    = @parmpono,
                @Particulars     = @Particulars,
                @Owner           = 'CS IN TRANSIT',
                @PreparedBy      = @username,
                @Amounts         = @AmtsVAT,
                @Tokens          = @TokVAT,
                @Flags           = @FlgVAT,
                @LedgerType      = NULL,
                @LedgerEntityID  = NULL,
                @LedgerInvoiceNo = NULL,
                @LedgerBatchRef  = @parmpono,
                @LedgerSeqRef    = 1;
        END

        IF @overalltotalcostnonvat > 0
        BEGIN
            DECLARE @AmtsVE dbo.tt_AmountBreakdown, @TokVE dbo.tt_TokenResolution, @FlgVE dbo.tt_ConditionFlags;
            INSERT @AmtsVE VALUES ('GROSS', @overalltotalcostnonvat);
             SET @Particulars = 'Inventory Transfer Out - PO#' + @parmpono + ' (to Branch ' + @parmbranchcode + ')- VAT Exempt';

            EXEC [dbo].[sp_PostCompoundTicket]
                @Mnemonic        = @MnemonicVATEX,
                @TicketDate      = @parmeffectivitydate,
                @BranchCode      = @TicketBranchCode,
                @ReferenceNumber = @outrefnum,
                @ReferenceKey    = @parmpono,
                @Particulars     = @Particulars,
                @Owner           = 'CS IN TRANSIT',
                @PreparedBy      = @username,
                @Amounts         = @AmtsVE,
                @Tokens          = @TokVE,
                @Flags           = @FlgVE,
                @LedgerType      = NULL,
                @LedgerEntityID  = NULL,
                @LedgerInvoiceNo = NULL,
                @LedgerBatchRef  = @parmpono,
                @LedgerSeqRef    = 2;
        END

        UPDATE TransferOrderSummary
        SET isProcess = '1'
        WHERE PONumber = @parmpono;

        INSERT INTO HistoryLogs
        VALUES (@preparedby, GETDATE(), 'Commissary Process Order with PONumber=' + @parmpono, @parmbranchcode);

        COMMIT TRANSACTION;

        SELECT 1 AS Status, 'Order confirmed and posted.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- ================================================================================
-- SECTION 4: dbo.TransferItemType (TYPE, SeqNo-carrying) -> sp_AddBranchOrderBatch
--   *** HARD PREREQUISITE MISSING: sp_AddBranchOrderBatch EXECs dbo.sp_AddBranchOrder,
--   which is NOT sourced in this repo. This section will deploy cleanly but
--   sp_AddBranchOrderBatch will fail at runtime until sp_AddBranchOrder exists
--   on the target. ***
-- ================================================================================

PRINT '--- 4. dbo.TransferItemType + sp_AddBranchOrderBatch (needs sp_AddBranchOrder to actually run) ---';
GO

-- SQL Server won't DROP TYPE while ANY object references it -- including old
-- *_OLD_* backup copies, not just the live SP -- so every sp_AddBranchOrderBatch*
-- object must go first.
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

-- =============================================
-- Author:      2026-08-18 (latest revision, SeqNo end-to-end)
-- Description: Loops @TransferItems, calling dbo.sp_AddBranchOrder once per
--              line inside its own TRY/CATCH so one failing row (e.g.
--              insufficient stock) is skipped and reported, not an abort of
--              the whole batch. Keyed by SeqNo (not ProductCode) so two
--              lines of the same product don't collide.
-- =============================================
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

-- ================================================================================
-- SECTION 5: sp_AddHRIOrderByBarcode
--   *** HARD PREREQUISITE MISSING: this INSERTs 15 positional values into
--   InventoryDeliveryFIFO, which requires SellingPrice/TotalAmount to already
--   exist on that table (not sourced in this repo -- see header). Without
--   them, "Add Item" will fail with a column-count mismatch. ***
-- ================================================================================

PRINT '--- 5. sp_AddHRIOrderByBarcode (needs InventoryDeliveryFIFO.SellingPrice/TotalAmount to already exist) ---';
GO
IF OBJECT_ID('dbo.sp_AddHRIOrderByBarcode', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_AddHRIOrderByBarcode', 'sp_AddHRIOrderByBarcode_OLD_08232026PATCH';
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE PROCEDURE [dbo].[sp_AddHRIOrderByBarcode]
    @parmdevno       VARCHAR(20),
    @parmrefno       VARCHAR(10),
    @parmpono        VARCHAR(10),
    @parmbarcode     VARCHAR(100),
    @parmbranchcode  VARCHAR(10),
    @parmorigin      VARCHAR(10),
    @preparedby      VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE
            @parmeffectivitydate DATE,
            @invqty FLOAT,
            @invprodcode VARCHAR(10),
            @invprodname VARCHAR(150),
            @invcost MONEY,
            @invisvat BIT,
            @invSeqNo BIGINT,
            @custkey CHAR(8),
            @specialpriceamount MONEY,
            @devseqno INT;

        SELECT @parmeffectivitydate = s.EffectivityDate
        FROM dbo.PurchaseOrderSummary AS s WITH (READCOMMITTED)
        WHERE s.PONumber = @parmpono;

        SELECT TOP (1)
            @invqty      = inv.Available,
            @invprodcode = inv.Product,
            @invprodname = inv.Description,
            @invcost     = inv.Cost,
            @invisvat    = inv.IsVat,
            @invSeqNo    = inv.SequenceNumber
        FROM dbo.Inventory AS inv WITH (UPDLOCK, ROWLOCK)
        WHERE inv.Branch = @parmorigin
          AND inv.IsWarehouse = 1
          AND inv.Available > 0
          AND inv.Barcode = @parmbarcode
        ORDER BY inv.SequenceNumber ASC;

        IF NOT EXISTS (SELECT TOP(1) 1 FROM dbo.PurchaseOrderDetails WHERE PONumber=@parmpono and ProductCode=@invprodcode)
        BEGIN
            RAISERROR('This Product is not Available in the the Request %s.', 16, 1, @parmbarcode, @parmorigin);
        END

        IF (@invSeqNo IS NULL)
        BEGIN
            RAISERROR('No available warehouse inventory found for barcode %s in origin %s.', 16, 1, @parmbarcode, @parmorigin);
        END

        DECLARE @seqLockResource NVARCHAR(256);
        SET @seqLockResource = N'DeliveryDetailsSeq_' + CAST(@parmdevno AS NVARCHAR(50)) + N'_' + CAST(@parmpono AS NVARCHAR(50));

        DECLARE @applockResult INT;

        EXEC @applockResult = sys.sp_getapplock
             @Resource     = @seqLockResource,
             @LockMode     = 'Exclusive',
             @LockTimeout  = 10000,
             @DbPrincipal  = 'dbo';

        IF (@applockResult < 0)
        BEGIN
            RAISERROR('Unable to acquire sequence lock for Delivery %s / PO %s.', 16, 1, @parmdevno, @parmpono);
        END

        SELECT @devseqno = ISNULL(MAX(d.SeqNo), 0)
        FROM dbo.DeliveryDetails AS d WITH (UPDLOCK, HOLDLOCK)
        WHERE d.DeliveryNo = @parmdevno
          AND d.PONumber   = @parmpono;

        SET @devseqno = @devseqno + 1;

        SELECT @specialpriceamount = p.SellingPrice
        FROM dbo.Products AS p WITH (READCOMMITTED)
        WHERE p.ProductCode = @invprodcode
          AND p.BranchCode = @parmorigin;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.DeliveryDetails WITH (UPDLOCK, HOLDLOCK)
            WHERE DeliveryNo = @parmdevno
              AND PONumber = @parmpono
              AND BarcodeNo = @parmbarcode
        )
        BEGIN
            INSERT INTO dbo.DeliveryDetails
            (
                SeqNo, DeliveryNo, PONumber, ReferenceNumber,
                ProductNo, BarcodeNo, ProductName,
                QtyDelivered, ActualQty, Variance,
                Cost, SellingPrice, [Status], isVat,
                ProcessedBy, isSettled, isCreditMemo, isReturned
            )
            VALUES
            (
                @devseqno, @parmdevno, @parmpono, @parmrefno,
                @invprodcode, @parmbarcode, @invprodname,
                @invqty, @invqty, 0,
                @invcost, ISNULL(@specialpriceamount, 0), 'PENDING', @invisvat,
                @preparedby, 0, 0, 0
            );

            UPDATE dbo.Inventory
            SET Available = 0
            WHERE SequenceNumber = @invSeqNo;

            IF NOT EXISTS(SELECT 1 FROM InventoryDeliveryFIFO WHERE SequenceReferenceNumber=@invSeqNo and isErrorCorrect=0)
            BEGIN
                INSERT INTO InventoryDeliveryFIFO
                VALUES(@parmdevno,@parmpono,@parmbranchcode,@invprodcode,@invprodname,@invqty,@invcost,(@invqty*@invcost),GETDATE(),@invSeqNo,@devseqno,0,0,ISNULL(@specialpriceamount,0),(@invqty*ISNULL(@specialpriceamount,0)))
            END

        END

        EXEC sys.sp_releaseapplock @Resource = @seqLockResource, @DbPrincipal = 'dbo';

        DECLARE
            @totalitem INT,
            @totalqtydelivered FLOAT;

        SELECT
            @totalitem = COUNT(*),
            @totalqtydelivered = ISNULL(SUM(d.QtyDelivered), 0)
        FROM dbo.DeliveryDetails AS d WITH (READCOMMITTED)
        WHERE d.DeliveryNo = @parmdevno
          AND d.PONumber = @parmpono;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.DeliverySummary WITH (READCOMMITTED)
            WHERE PONumber = @parmpono
              AND DeliveryNo = @parmdevno
        )
        BEGIN
            INSERT INTO dbo.DeliverySummary
            (
                DeliveryNo, PONumber, ReferenceNumber, InvoiceNo,
                BranchCode, TotalItem, TotalQtyDelivered, TotalActualQty,
                TotalVarianceVat, TotalVarianceVatExempt, EffectivityDate,
                [Status], DateAdded, PreparedBy, isSettled, isInvoiceUpdate
            )
            VALUES
            (
                @parmdevno, @parmpono, @parmrefno, @parmrefno,
                @parmbranchcode, @totalitem, @totalqtydelivered, 0,
                0, 0, ISNULL(@parmeffectivitydate, GETDATE()),
                'PENDING', GETDATE(), @preparedby, 0, 0
            );
        END
        ELSE
        BEGIN
            UPDATE dbo.DeliverySummary
            SET TotalItem         = @totalitem,
                TotalQtyDelivered = @totalqtydelivered,
                EffectivityDate   = ISNULL(@parmeffectivitydate, EffectivityDate),
                DateAdded         = DateAdded,
                PreparedBy        = PreparedBy
            WHERE PONumber = @parmpono
              AND DeliveryNo = @parmdevno;
        END

        COMMIT TRAN;

        SELECT
            1     AS [status],
            'OK'  AS [message],
            @devseqno AS NextSeqNoUsed,
            @invprodcode AS ProductCode,
            @invprodname AS ProductName,
            @invqty AS QtyDelivered;

    END TRY
    BEGIN CATCH
        IF (XACT_STATE()) <> 0 ROLLBACK TRAN;

        DECLARE @errMsg NVARCHAR(4000) = ERROR_MESSAGE(),
                @errNo  INT            = ERROR_NUMBER(),
                @errSev INT            = ERROR_SEVERITY(),
                @errSta INT            = ERROR_STATE(),
                @errLin INT            = ERROR_LINE();

        RAISERROR('[sp_AddHRIOrderByBarcode] failed: %s (Err %d, Sev %d, State %d, Line %d)',
                  @errSev, 1, @errMsg, @errNo, @errSev, @errSta, @errLin);

        SELECT 2 AS [status], 'Error' AS [message], @errNo AS ErrorNumber, @errMsg AS ErrorMessage;
    END CATCH
END
GO

-- ================================================================================
-- SECTION 6: Credit Memo
--   dbo.tt_CreditMemoLines (TYPE) -> CreditMemo table columns (ALTER) -> sp_CreditMemo
--   *** HARD PREREQUISITE MISSING: the base CreditMemo table itself isn't
--   sourced in this repo -- only this additive ALTER. If the target doesn't
--   have a CreditMemo table at all yet, section 6b below will fail. ***
-- ================================================================================

PRINT '--- 6a. dbo.tt_CreditMemoLines (TYPE) ---';
GO
IF OBJECT_ID('dbo.sp_CreditMemo', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CreditMemo;
GO
IF TYPE_ID('dbo.tt_CreditMemoLines') IS NOT NULL
    DROP TYPE dbo.tt_CreditMemoLines;
GO
CREATE TYPE dbo.tt_CreditMemoLines AS TABLE
(
    SeqNo     decimal(10,0) NOT NULL,
    ProductNo char(5)       NOT NULL,
    ActualQty decimal(10,3) NOT NULL
);
GO

PRINT '--- 6b. CreditMemo table columns (base table must already exist on target) ---';
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.CreditMemo') AND name = 'SeqNo')
    ALTER TABLE dbo.CreditMemo ADD DeliveryNo varchar(20) NULL, ReferenceNumber varchar(20) NULL, SeqNo decimal(18,0) NULL;
GO

PRINT '--- 6c. sp_CreditMemo ---';
GO
SET QUOTED_IDENTIFIER ON;
GO
-- =============================================
-- Author:      Eulz Avancena (original branch: sp_CreditMemo_09132018); rewritten 2026-08-05
-- Description: Credit Memo for a client order (Orders/POForApproval.cs -> CreditMemoDevEx.cs).
--              Applies the qty/amount adjustment recorded on DeliveryDetails
--              (ActualQty vs QtyDelivered -> Variance) and, when the order was already
--              confirmed (@parmstat='DELIVERED'), books REVERSAL GL tickets against the
--              SI-VAT / SI-VATEX tickets sp_ConfirmOrder already posted, via
--              sp_PostCompoundTicketSales / CM-CLIENT-VAT / CM-CLIENT-VATEX.
-- =============================================
CREATE PROCEDURE [dbo].[sp_CreditMemo]
    @parmpono varchar(10),
    @parmuser varchar(30),
    @parmstat varchar(30),
    @Lines    dbo.tt_CreditMemoLines READONLY
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @custkey                CHAR(8),
        @custname                VARCHAR(100),
        @custbranch              CHAR(3),
        @effectivitydate         DATE,
        @invoiceno               VARCHAR(20),
        @Particulars             VARCHAR(6999),
        @totaldiscount           MONEY,
        @totaldiscountvatable    MONEY,
        @totaldiscountvatexempt  MONEY,
        @totalvatablesales       MONEY,
        @totalvatoutput          MONEY,
        @totalvatcost            MONEY,
        @totalvatexcost          MONEY,
        @ticketnumvat            VARCHAR(10) = ' ',
        @ticketnumvatex          VARCHAR(10) = ' ';

    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM @Lines)
            THROW 59002, 'No lines submitted for this Credit Memo.', 1;

        UPDATE dd
           SET dd.ActualQty    = l.ActualQty,
               dd.Variance     = dd.QtyDelivered - l.ActualQty,
               dd.isCreditMemo = 1
        FROM DeliveryDetails dd
        JOIN @Lines l
          ON dd.SeqNo     = l.SeqNo
         AND dd.ProductNo = l.ProductNo
        WHERE dd.PONumber = @parmpono
          AND dd.isCreditMemo = 0;

        SELECT dd.DeliveryNo, dd.ReferenceNumber, dd.SeqNo, dd.ProductNo, dd.ProductName,
               dd.QtyDelivered, dd.ActualQty, dd.Variance, dd.SellingPrice, dd.Cost, dd.isVat
        INTO #CMBatch
        FROM DeliveryDetails dd
        JOIN @Lines l
          ON dd.SeqNo     = l.SeqNo
         AND dd.ProductNo = l.ProductNo
        WHERE dd.PONumber = @parmpono
          AND ISNULL(dd.Variance, 0) <> 0
          AND NOT EXISTS (
              SELECT 1 FROM CreditMemo cm
              WHERE cm.PONumber         = dd.PONumber
                AND cm.ProductCode      = dd.ProductNo
                AND cm.DeliveryNo       = dd.DeliveryNo
                AND cm.ReferenceNumber  = dd.ReferenceNumber
                AND cm.SeqNo            = dd.SeqNo
          );

        IF NOT EXISTS (SELECT 1 FROM #CMBatch)
            THROW 59001, 'No new Credit Memo variance to process for this PO (already processed, or ActualQty unchanged).', 1;

        UPDATE DeliverySummary
           SET TotalActualQty         = (SELECT SUM(ActualQty) FROM DeliveryDetails WHERE PONumber=@parmpono),
               TotalVarianceVat       = (SELECT SUM(Variance) FROM DeliveryDetails WHERE PONumber=@parmpono AND isVat=1),
               TotalVarianceVatExempt = (SELECT SUM(Variance) FROM DeliveryDetails WHERE PONumber=@parmpono AND isVat=0)
         WHERE PONumber = @parmpono;

        SELECT
            @totaldiscount          = SUM(ISNULL(Variance*SellingPrice,0)),
            @totaldiscountvatable   = SUM(CASE WHEN isVat=1 THEN ISNULL(Variance*SellingPrice,0) ELSE 0 END),
            @totaldiscountvatexempt = SUM(CASE WHEN isVat=0 THEN ISNULL(Variance*SellingPrice,0) ELSE 0 END),
            @totalvatcost           = SUM(CASE WHEN isVat=1 THEN ISNULL(Variance*Cost,0) ELSE 0 END),
            @totalvatexcost         = SUM(CASE WHEN isVat=0 THEN ISNULL(Variance*Cost,0) ELSE 0 END)
        FROM #CMBatch;

        SET @totalvatablesales = ISNULL(@totaldiscountvatable,0) / 1.12;
        SET @totalvatoutput    = @totalvatablesales * 0.12;

        SELECT @custkey = Customer, @effectivitydate = EffectivityDate
        FROM PurchaseOrderSummary WHERE PONumber = @parmpono;

        SELECT @invoiceno = InvoiceNo FROM DeliverySummary WHERE PONumber = @parmpono;

        SELECT @custbranch = BranchCode, @custname = CustomerName
        FROM Customers WHERE CustomerKey = @custkey;

        SET @custbranch = '888';

        SET @Particulars =
            'CREDIT MEMO | Customer: ' + ISNULL(@custname,'')
            + ' | PO: ' + @parmpono
            + ' | Invoice: ' + ISNULL(@invoiceno,'');

        IF @parmstat = 'DELIVERED'
        BEGIN
            IF ISNULL(@totaldiscountvatable,0) <> 0
            BEGIN
                DECLARE @AmtCMVat dbo.tt_AmountBreakdown;
                DECLARE @TokCMVat dbo.tt_TokenResolution;
                DECLARE @FlgCMVat dbo.tt_ConditionFlags;

                INSERT @AmtCMVat VALUES
                    ('GROSS', ROUND(@totaldiscountvatable,2)),
                    ('NET',   ROUND(@totalvatablesales,2)),
                    ('VAT',   ROUND(@totalvatoutput,2)),
                    ('VATEX', 0),
                    ('COST',  ROUND(ISNULL(@totalvatcost,0),2));

                INSERT @FlgCMVat VALUES ('HasVAT', 1), ('HasVATEX', 0);

                EXEC [dbo].[sp_PostCompoundTicketSales]
                    @Mnemonic        = 'CM-CLIENT-VAT',
                    @TicketDate      = @effectivitydate,
                    @BranchCode      = @custbranch,
                    @ReferenceNumber = @parmpono,
                    @ReferenceKey    = @invoiceno,
                    @Particulars     = @Particulars,
                    @Owner           = @custname,
                    @PreparedBy      = @parmuser,
                    @Status          = 'POSTED',
                    @Amounts         = @AmtCMVat,
                    @Tokens          = @TokCMVat,
                    @Flags           = @FlgCMVat,
                    @LedgerType      = NULL;

                SELECT TOP 1 @ticketnumvat = TicketNumber
                FROM TicketMaster
                WHERE ReferenceNumber = @parmpono AND Mnemonic = 'CM-CLIENT-VAT'
                ORDER BY TRY_CAST(TicketNumber AS INT) DESC;

                DECLARE @TRNVat DECIMAL(7,0);
                SELECT @TRNVat = ISNULL(MAX(TRN_SEQ_NO),0)+1 FROM ClientLedger WHERE AccountID = @custkey;

                INSERT INTO ClientLedger
                    (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch,
                     Description, TransCode, TransactionDate, ReferenceNumber, ReferenceKey,
                     InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, ORNumber,
                     TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
                VALUES
                    (@TRNVat, @custkey, @custkey, @effectivitydate, @custbranch,
                     @Particulars, 'CM-CLIENT-VAT', @effectivitydate, @parmpono, @invoiceno,
                     @invoiceno, 0, 0, ROUND(@totaldiscountvatable,2), 0, @invoiceno,
                     @parmuser, '*', 'Credit Memo', ROUND(@totaldiscountvatable,2), 0, @ticketnumvat);
            END;

            IF ISNULL(@totaldiscountvatexempt,0) <> 0
            BEGIN
                DECLARE @AmtCMVatEx dbo.tt_AmountBreakdown;
                DECLARE @TokCMVatEx dbo.tt_TokenResolution;
                DECLARE @FlgCMVatEx dbo.tt_ConditionFlags;

                INSERT @AmtCMVatEx VALUES
                    ('GROSS', ROUND(@totaldiscountvatexempt,2)),
                    ('COST',  ROUND(ISNULL(@totalvatexcost,0),2));

                EXEC [dbo].[sp_PostCompoundTicketSales]
                    @Mnemonic        = 'CM-CLIENT-VATEX',
                    @TicketDate      = @effectivitydate,
                    @BranchCode      = @custbranch,
                    @ReferenceNumber = @parmpono,
                    @ReferenceKey    = @invoiceno,
                    @Particulars     = @Particulars,
                    @Owner           = @custname,
                    @PreparedBy      = @parmuser,
                    @Status          = 'POSTED',
                    @Amounts         = @AmtCMVatEx,
                    @Tokens          = @TokCMVatEx,
                    @Flags           = @FlgCMVatEx,
                    @LedgerType      = NULL;

                SELECT TOP 1 @ticketnumvatex = TicketNumber
                FROM TicketMaster
                WHERE ReferenceNumber = @parmpono AND Mnemonic = 'CM-CLIENT-VATEX'
                ORDER BY TRY_CAST(TicketNumber AS INT) DESC;

                DECLARE @TRNVatEx DECIMAL(7,0);
                SELECT @TRNVatEx = ISNULL(MAX(TRN_SEQ_NO),0)+1 FROM ClientLedger WHERE AccountID = @custkey;

                INSERT INTO ClientLedger
                    (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch,
                     Description, TransCode, TransactionDate, ReferenceNumber, ReferenceKey,
                     InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, ORNumber,
                     TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
                VALUES
                    (@TRNVatEx, @custkey, @custkey, @effectivitydate, @custbranch,
                     @Particulars, 'CM-CLIENT-VATEX', @effectivitydate, @parmpono, @invoiceno,
                     @invoiceno, 0, 0, ROUND(@totaldiscountvatexempt,2), 0, @invoiceno,
                     @parmuser, '*', 'Credit Memo', ROUND(@totaldiscountvatexempt,2), 0, @ticketnumvatex);
            END;
        END
        ELSE
        BEGIN
            IF ISNULL(@totaldiscount,0) <> 0
            BEGIN
                DECLARE @TRNPre DECIMAL(7,0);
                SELECT @TRNPre = ISNULL(MAX(TRN_SEQ_NO),0)+1 FROM ClientLedger WHERE AccountID = @custkey;

                INSERT INTO ClientLedger
                    (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch,
                     Description, TransCode, TransactionDate, ReferenceNumber, ReferenceKey,
                     InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, ORNumber,
                     TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
                VALUES
                    (@TRNPre, @custkey, @custkey, CAST(GETDATE() AS date), @custbranch,
                     'Credit Memo Adjustment (pre-confirm)', 'ADJ', CAST(GETDATE() AS date),
                     @parmpono, @parmpono, 'NON', 0, 0, ROUND(@totaldiscount,2), 0, 'NON',
                     @parmuser, '*', 'Credit Memo', ROUND(@totaldiscount,2), 0, ' ');
            END;
        END;

        UPDATE TransactionChargeSales
           SET DiscountAmount = ISNULL(DiscountAmount,0) + ISNULL(@totaldiscount,0),
               Balance        = Balance - ISNULL(@totaldiscount,0)
         WHERE CustomerKey = @custkey
           AND ReferenceNo = @parmpono
           AND InvoiceNo   = @invoiceno;

        INSERT INTO CreditMemo
            (PONumber, ProductCode, Description, Qty, ActualQty, Variance,
             SellingPrice, TotalAmount, DiscountAmount, TicketRefNo, DateAdded, ExecuteBy,
             DeliveryNo, ReferenceNumber, SeqNo)
        SELECT
            @parmpono, ProductNo, ProductName, QtyDelivered, ActualQty, Variance,
            SellingPrice, (ActualQty*SellingPrice), (Variance*SellingPrice),
            CASE WHEN isVat=1 THEN @ticketnumvat ELSE @ticketnumvatex END,
            CAST(GETDATE() AS date), @parmuser,
            DeliveryNo, ReferenceNumber, SeqNo
        FROM #CMBatch;

        DROP TABLE IF EXISTS #CMBatch;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        DROP TABLE IF EXISTS #CMBatch;

        DECLARE @EMsg  NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ESev  INT            = ERROR_SEVERITY();
        DECLARE @ESt   INT            = ERROR_STATE();
        DECLARE @ELine INT            = ERROR_LINE();
        DECLARE @EProc NVARCHAR(128)  = ISNULL(ERROR_PROCEDURE(), 'sp_CreditMemo');
        RAISERROR('Error in %s (line %d): %s', @ESev, @ESt, @EProc, @ELine, @EMsg);
    END CATCH;
END;
GO

-- ================================================================================
-- SECTION 7: Sales Return
--   dbo.tt_ReturnSalesOrderLines (TYPE) -> ReturnedOrderSummary columns (ALTER)
--   -> sp_ReturnSalesOrder (latest = 2026-08-10, supersedes the 2026-08-05 rewrite)
--   (Included even though only the TYPE was on your original list -- the type
--   is unusable without the proc, confirmed with you.)
-- ================================================================================

PRINT '--- 7a. dbo.tt_ReturnSalesOrderLines (TYPE) ---';
GO
IF OBJECT_ID('dbo.sp_ReturnSalesOrder', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ReturnSalesOrder;
GO
IF TYPE_ID('dbo.tt_ReturnSalesOrderLines') IS NOT NULL
    DROP TYPE dbo.tt_ReturnSalesOrderLines;
GO
CREATE TYPE dbo.tt_ReturnSalesOrderLines AS TABLE
(
    SeqNo         decimal(10,0)  NOT NULL,
    ProductNo     varchar(20)    NOT NULL,
    ProductName   varchar(100)   NOT NULL,
    BarcodeNo     varchar(30)    NULL,
    QtyDelivered  decimal(10,3)  NOT NULL,
    Cost          decimal(12,2)  NOT NULL,
    SellingPrice  decimal(12,2)  NOT NULL,
    ActualQty     decimal(10,3)  NOT NULL,
    Variance      float          NULL,
    isVat         bit            NULL
);
GO

PRINT '--- 7b. ReturnedOrderSummary.TicketRefNoVAT / TicketRefNoVATEX columns ---';
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.ReturnedOrderSummary') AND name = 'TicketRefNoVAT')
    ALTER TABLE dbo.ReturnedOrderSummary ADD TicketRefNoVAT varchar(10) NULL, TicketRefNoVATEX varchar(10) NULL;
GO

PRINT '--- 7c. sp_ReturnSalesOrder (latest, 2026-08-10) ---';
GO
SET QUOTED_IDENTIFIER ON;
GO
-- =============================================
-- Author:      Eulz Avancena (original); rewritten 2026-08-05, then 2026-08-10
-- Description: Sales Return (Orders/ReturnSalesOrder.cs). Supports staged/
--              partial returns. Step 4 (inventory refund) scopes strictly to
--              #NewReturns (this call's lines only) -- fixes a double-refund
--              bug where a second staged return on the same PO re-refunded
--              every previously-returned line too. Books reversal GL tickets
--              via CM-CLIENT-VAT / CM-CLIENT-VATEX when @parmreturnstatus=
--              'DELIVERED'.
-- =============================================
CREATE PROCEDURE [dbo].[sp_ReturnSalesOrder]
    @parmbranchcode   char(3),
    @parmpono         varchar(10),
    @parmdevno        varchar(10),
    @parmuser         varchar(50),
    @parmreturnstatus varchar(30),
    @parmreason       varchar(930),
    @parmmachinename  varchar(50),
    @Lines            dbo.tt_ReturnSalesOrderLines READONLY
AS
BEGIN
    SET XACT_ABORT OFF;
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM @Lines)
            THROW 59101, 'No lines submitted for this Sales Return.', 1;

        ---------------------------------------------------------------------------
        -- 1. GET INVOICE / CUSTOMER INFO
        ---------------------------------------------------------------------------
        DECLARE @invoiceno VARCHAR(20), @effectivitydate DATE, @custkey CHAR(8), @custname VARCHAR(100);

        SELECT @invoiceno = InvoiceNo,
               @effectivitydate = EffectivityDate
        FROM DeliverySummary WITH(NOLOCK)
        WHERE PONumber = @parmpono;

        SELECT @custkey = Customer FROM PurchaseOrderSummary WITH(NOLOCK) WHERE PONumber = @parmpono;
        SELECT @custname = CustomerName FROM Customers WITH(NOLOCK) WHERE CustomerKey = @custkey;

        ---------------------------------------------------------------------------
        -- 1b. INSERT NEW RETURN LINES (TVP-driven, idempotent)
        ---------------------------------------------------------------------------
        SELECT l.SeqNo, @parmpono AS PONumber, l.ProductNo, l.ProductName, l.BarcodeNo,
               l.QtyDelivered, l.Cost, l.SellingPrice, l.ActualQty, l.Variance, l.isVat,
               @parmuser AS ProcessedBy, CAST(GETDATE() AS date) AS DateProcessed
        INTO #NewReturns
        FROM @Lines l
        JOIN DeliveryDetails dd
          ON dd.PONumber = @parmpono
         AND dd.SeqNo = l.SeqNo
         AND dd.ProductNo = l.ProductNo
         AND ISNULL(dd.BarcodeNo,'') = ISNULL(l.BarcodeNo,'')
        WHERE ISNULL(dd.isReturned,0) = 0;

        IF NOT EXISTS (SELECT 1 FROM #NewReturns)
            THROW 59102, 'No new lines to return for this PO (already returned).', 1;

        INSERT INTO ReturnedOrderDetails
            (SeqNo, PONumber, ProductNo, ProductName, BarcodeNo, QtyDelivered,
             Cost, SellingPrice, ActualQty, Variance, isVat, ProcessedBy, DateProcessed)
        SELECT SeqNo, PONumber, ProductNo, ProductName, BarcodeNo, QtyDelivered,
               Cost, SellingPrice, ActualQty, Variance, isVat, ProcessedBy, DateProcessed
        FROM #NewReturns;

        ---------------------------------------------------------------------------
        -- 2. UPSERT RETURNED ORDER SUMMARY
        ---------------------------------------------------------------------------
        DECLARE @Ret_TotalItem INT = 0,
                @Ret_TotalQty DECIMAL(18,2) = 0,
                @Ret_TotalAmt DECIMAL(18,2) = 0;

        SELECT @Ret_TotalItem = COUNT(*),
               @Ret_TotalQty = ISNULL(SUM(QtyDelivered), 0),
               @Ret_TotalAmt = ISNULL(SUM(QtyDelivered * SellingPrice), 0)
        FROM ReturnedOrderDetails WITH(NOLOCK)
        WHERE PONumber = @parmpono;

        IF NOT EXISTS (SELECT 1 FROM ReturnedOrderSummary WITH(UPDLOCK) WHERE PONumber = @parmpono)
        BEGIN
            INSERT INTO ReturnedOrderSummary (PONumber, InvoiceNo, BranchCode, TotalItem, TotalQtyDelivered, TotalAmount, EffectivityDate, DateAdded, PreparedBy, ReturnType)
            VALUES (@parmpono, @invoiceno, @parmbranchcode, @Ret_TotalItem, @Ret_TotalQty, @Ret_TotalAmt, @effectivitydate, GETDATE(), @parmuser, ' ');
        END
        ELSE
        BEGIN
            UPDATE ReturnedOrderSummary
            SET TotalItem = @Ret_TotalItem,
                TotalQtyDelivered = @Ret_TotalQty,
                TotalAmount = @Ret_TotalAmt
            WHERE PONumber = @parmpono;
        END

        ---------------------------------------------------------------------------
        -- 3. UPDATE DELIVERY DETAILS & SUMMARY
        ---------------------------------------------------------------------------
        UPDATE a
        SET a.isReturned = 1
        FROM DeliveryDetails a
        INNER JOIN ReturnedOrderDetails b
            ON a.PONumber = b.PONumber
            AND a.ProductNo = b.ProductNo
            AND a.BarcodeNo = b.BarcodeNo
            AND a.SeqNo = b.SeqNo
        WHERE a.PONumber = @parmpono;

        DECLARE @Del_TotalItem INT = 0,
                @Del_TotalQty DECIMAL(18,2) = 0,
                @Del_TotalActual DECIMAL(18,2) = 0;

        SELECT @Del_TotalItem = ISNULL(COUNT(*), 0),
               @Del_TotalQty = ISNULL(SUM(QtyDelivered), 0),
               @Del_TotalActual = ISNULL(SUM(ActualQty), 0)
        FROM DeliveryDetails WITH(NOLOCK)
        WHERE PONumber = @parmpono AND isReturned = 0;

        UPDATE DeliverySummary
        SET TotalItem = @Del_TotalItem,
            TotalQtyDelivered = @Del_TotalQty,
            TotalActualQty = @Del_TotalActual
        WHERE PONumber = @parmpono;

        ---------------------------------------------------------------------------
        -- 4. UPDATE INVENTORY FIFO & MASTER INVENTORY
        ---------------------------------------------------------------------------
        UPDATE InventoryDeliveryFIFO
        SET isErrorCorrect = 1
        WHERE DevDetSeqNo IN (
            SELECT SeqNo FROM DeliveryDetails WHERE PONumber = @parmpono AND isReturned = 1
        ) AND PONumber = @parmpono;

        UPDATE Inventory
        SET IsStock = 1,
            Available = (SELECT ISNULL(SUM(QtyDelivered), 0)
                         FROM InventoryDeliveryFIFO
                         WHERE PONumber = @parmpono
                         AND Inventory.SequenceNumber = SequenceReferenceNumber)
        WHERE SequenceNumber IN (
            SELECT SequenceReferenceNumber FROM InventoryDeliveryFIFO WHERE PONumber = @parmpono
        );

        ---------------------------------------------------------------------------
        -- 5. UPDATE BATCH SALES DETAILS
        ---------------------------------------------------------------------------
        UPDATE BatchSalesDetails
        SET isCancelled = 1
        WHERE ReferenceNo = @parmpono
          AND BranchCode = @parmbranchcode
          AND Barcode IN (SELECT BarcodeNo FROM ReturnedOrderDetails WHERE PONumber = @parmpono);

        ---------------------------------------------------------------------------
        -- 6. UPDATE BATCH SALES SUMMARY
        ---------------------------------------------------------------------------
        DECLARE @userid VARCHAR(20), @cashiertransno INT, @cashiertransdate CHAR(8);
        SELECT @userid = UserID FROM Users WITH(NOLOCK) WHERE FullName = @parmuser;
        SET @cashiertransdate = dbo.func_ConvertDateTimeToChar('DATE', GETDATE());

        SELECT @cashiertransno = CashierTransNo
        FROM SalesTransactionSummary WITH(NOLOCK)
        WHERE BranchCode = @parmbranchcode
          AND MachineUsed = @parmmachinename
          AND UserID = @userid
          AND TransactionDate = @cashiertransdate;

        DECLARE @B_ItemRet INT = 0, @B_Item INT = 0, @B_ItemSold INT = 0, @B_VatItems INT = 0;
        DECLARE @B_RetAmt DECIMAL(18,2)=0, @B_Tax DECIMAL(18,2)=0, @B_Kilos DECIMAL(18,2)=0;
        DECLARE @B_SubTotal DECIMAL(18,2)=0, @B_Amt DECIMAL(18,2)=0, @B_VatSale DECIMAL(18,2)=0;
        DECLARE @B_VatExempt DECIMAL(18,2)=0, @B_Vatable DECIMAL(18,2)=0;

        SELECT
            @B_ItemRet = SUM(CASE WHEN isCancelled=1 AND isVoid=0 THEN 1 ELSE 0 END),
            @B_Item = SUM(CASE WHEN isCancelled=0 AND isVoid=0 THEN 1 ELSE 0 END),
            @B_ItemSold = SUM(CASE WHEN isCancelled=0 AND isVoid=0 THEN 1 ELSE 0 END),
            @B_VatItems = SUM(CASE WHEN isVat=1 AND isCancelled=0 AND isVoid=0 THEN 1 ELSE 0 END),
            @B_RetAmt = SUM(CASE WHEN isCancelled=1 AND isVoid=0 THEN TotalAmount ELSE 0 END),
            @B_Tax = SUM(CASE WHEN isCancelled=0 AND isVoid=0 THEN TaxTotal ELSE 0 END),
            @B_Kilos = SUM(CASE WHEN isCancelled=0 AND isVoid=0 THEN QtySold ELSE 0 END),
            @B_SubTotal = SUM(CASE WHEN isCancelled=0 AND isVoid=0 THEN SubTotal ELSE 0 END),
            @B_Amt = SUM(CASE WHEN isCancelled=0 AND isVoid=0 THEN TotalAmount ELSE 0 END),
            @B_VatSale = SUM(CASE WHEN isCancelled=0 AND isVoid=0 THEN TaxTotal ELSE 0 END),
            @B_VatExempt = SUM(CASE WHEN isVat=0 AND isCancelled=0 AND isVoid=0 THEN TotalAmount ELSE 0 END),
            @B_Vatable = SUM(CASE WHEN isVat=1 AND isCancelled=0 AND isVoid=0 THEN SubTotal ELSE 0 END)
        FROM BatchSalesDetails WITH(NOLOCK)
        WHERE ReferenceNo = @parmpono AND BranchCode = @parmbranchcode;

        UPDATE BatchSalesSummary
        SET TotalItemReturned = ISNULL(@B_ItemRet,0),
            TotalItem = ISNULL(@B_Item,0),
            TotalItemSold = ISNULL(@B_ItemSold,0),
            TotalVatableItems = ISNULL(@B_VatItems,0),
            TotalReturnedAmount = ISNULL(@B_RetAmt,0),
            TotalTax = ISNULL(@B_Tax,0),
            TotalKilos = ISNULL(@B_Kilos,0),
            SubTotal = ISNULL(@B_SubTotal,0),
            TotalAmount = ISNULL(@B_Amt,0),
            TotalVATSale = ISNULL(@B_VatSale,0),
            TotalVATExemptSale = ISNULL(@B_VatExempt,0),
            TotalVatableSale = ISNULL(@B_Vatable,0)
        WHERE ReferenceNo = @parmpono AND BranchCode = @parmbranchcode AND CashierTransNo = @cashiertransno;

        ---------------------------------------------------------------------------
        -- 7. UPDATE TRANSACTION CHARGE SALES + POST REVERSAL TICKETS (If Delivered)
        ---------------------------------------------------------------------------
        IF @parmreturnstatus = 'DELIVERED'
        BEGIN
            UPDATE TransactionChargeSalesDetails
            SET ErrorTag = 1
            WHERE ReferenceNo = @parmpono AND BranchCode = @parmbranchcode
              AND SKU IN (SELECT BarcodeNo FROM ReturnedOrderDetails WHERE PONumber = @parmpono);

            DECLARE @Charge_Total DECIMAL(18,2) = 0;
            SELECT @Charge_Total = ISNULL(SUM(TotalAmount), 0)
            FROM TransactionChargeSalesDetails WITH(NOLOCK)
            WHERE ReferenceNo = @parmpono AND BranchCode = @parmbranchcode AND ErrorTag = 0;

            UPDATE TransactionChargeSales
            SET TotalAmount = @Charge_Total,
                Balance = @Charge_Total,
                PayStatus = 'UNPAID'
            WHERE ReferenceNo = @parmpono AND BranchCode = @parmbranchcode;

            DECLARE
                @totalgrossvat    MONEY, @totalgrossvatex MONEY,
                @totalnetvat      MONEY, @totalvatoutput   MONEY,
                @totalcostvat     MONEY, @totalcostvatex   MONEY,
                @Particulars      VARCHAR(6999),
                @ticketnumvat     VARCHAR(10) = ' ',
                @ticketnumvatex   VARCHAR(10) = ' ';

            SELECT
                @totalgrossvat   = SUM(CASE WHEN isVat=1 THEN ISNULL(QtyDelivered*SellingPrice,0) ELSE 0 END),
                @totalgrossvatex = SUM(CASE WHEN isVat=0 THEN ISNULL(QtyDelivered*SellingPrice,0) ELSE 0 END),
                @totalcostvat    = SUM(CASE WHEN isVat=1 THEN ISNULL(QtyDelivered*Cost,0) ELSE 0 END),
                @totalcostvatex  = SUM(CASE WHEN isVat=0 THEN ISNULL(QtyDelivered*Cost,0) ELSE 0 END)
            FROM #NewReturns;

            SET @totalnetvat    = ISNULL(@totalgrossvat,0) / 1.12;
            SET @totalvatoutput = @totalnetvat * 0.12;

            SET @Particulars =
                'SALES RETURN | Customer: ' + ISNULL(@custname,'')
                + ' | PO: ' + @parmpono
                + ' | Invoice: ' + ISNULL(@invoiceno,'');

            IF ISNULL(@totalgrossvat,0) <> 0
            BEGIN
                DECLARE @AmtRetVat dbo.tt_AmountBreakdown;
                DECLARE @TokRetVat dbo.tt_TokenResolution;
                DECLARE @FlgRetVat dbo.tt_ConditionFlags;

                INSERT @AmtRetVat VALUES
                    ('GROSS', ROUND(@totalgrossvat,2)),
                    ('NET',   ROUND(@totalnetvat,2)),
                    ('VAT',   ROUND(@totalvatoutput,2)),
                    ('VATEX', 0),
                    ('COST',  ROUND(ISNULL(@totalcostvat,0),2));

                INSERT @FlgRetVat VALUES ('HasVAT', 1), ('HasVATEX', 0);

                EXEC [dbo].[sp_PostCompoundTicketSales]
                    @Mnemonic        = 'CM-CLIENT-VAT',
                    @TicketDate      = @effectivitydate,
                    @BranchCode      = @parmbranchcode,
                    @ReferenceNumber = @parmpono,
                    @ReferenceKey    = @invoiceno,
                    @Particulars     = @Particulars,
                    @Owner           = @custname,
                    @PreparedBy      = @parmuser,
                    @Status          = 'POSTED',
                    @Amounts         = @AmtRetVat,
                    @Tokens          = @TokRetVat,
                    @Flags           = @FlgRetVat,
                    @LedgerType      = NULL;

                SELECT TOP 1 @ticketnumvat = TicketNumber
                FROM TicketMaster
                WHERE ReferenceNumber = @parmpono AND Mnemonic = 'CM-CLIENT-VAT'
                ORDER BY TRY_CAST(TicketNumber AS INT) DESC;

                DECLARE @TRNRetVat DECIMAL(7,0);
                SELECT @TRNRetVat = ISNULL(MAX(TRN_SEQ_NO),0)+1 FROM ClientLedger WHERE AccountID = @custkey;

                INSERT INTO ClientLedger
                    (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch,
                     Description, TransCode, TransactionDate, ReferenceNumber, ReferenceKey,
                     InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, ORNumber,
                     TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
                VALUES
                    (@TRNRetVat, @custkey, @custkey, @effectivitydate, @parmbranchcode,
                     @Particulars, 'CM-CLIENT-VAT', @effectivitydate, @parmpono, @invoiceno,
                     @invoiceno, 0, 0, ROUND(@totalgrossvat,2), 0, @invoiceno,
                     @parmuser, '*', 'Sales Return', ROUND(@totalgrossvat,2), 0, @ticketnumvat);

                UPDATE ReturnedOrderSummary SET TicketRefNoVAT = @ticketnumvat WHERE PONumber = @parmpono;
            END;

            IF ISNULL(@totalgrossvatex,0) <> 0
            BEGIN
                DECLARE @AmtRetVatEx dbo.tt_AmountBreakdown;
                DECLARE @TokRetVatEx dbo.tt_TokenResolution;
                DECLARE @FlgRetVatEx dbo.tt_ConditionFlags;

                INSERT @AmtRetVatEx VALUES
                    ('GROSS', ROUND(@totalgrossvatex,2)),
                    ('COST',  ROUND(ISNULL(@totalcostvatex,0),2));

                EXEC [dbo].[sp_PostCompoundTicketSales]
                    @Mnemonic        = 'CM-CLIENT-VATEX',
                    @TicketDate      = @effectivitydate,
                    @BranchCode      = @parmbranchcode,
                    @ReferenceNumber = @parmpono,
                    @ReferenceKey    = @invoiceno,
                    @Particulars     = @Particulars,
                    @Owner           = @custname,
                    @PreparedBy      = @parmuser,
                    @Status          = 'POSTED',
                    @Amounts         = @AmtRetVatEx,
                    @Tokens          = @TokRetVatEx,
                    @Flags           = @FlgRetVatEx,
                    @LedgerType      = NULL;

                SELECT TOP 1 @ticketnumvatex = TicketNumber
                FROM TicketMaster
                WHERE ReferenceNumber = @parmpono AND Mnemonic = 'CM-CLIENT-VATEX'
                ORDER BY TRY_CAST(TicketNumber AS INT) DESC;

                DECLARE @TRNRetVatEx DECIMAL(7,0);
                SELECT @TRNRetVatEx = ISNULL(MAX(TRN_SEQ_NO),0)+1 FROM ClientLedger WHERE AccountID = @custkey;

                INSERT INTO ClientLedger
                    (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch,
                     Description, TransCode, TransactionDate, ReferenceNumber, ReferenceKey,
                     InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, ORNumber,
                     TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
                VALUES
                    (@TRNRetVatEx, @custkey, @custkey, @effectivitydate, @parmbranchcode,
                     @Particulars, 'CM-CLIENT-VATEX', @effectivitydate, @parmpono, @invoiceno,
                     @invoiceno, 0, 0, ROUND(@totalgrossvatex,2), 0, @invoiceno,
                     @parmuser, '*', 'Sales Return', ROUND(@totalgrossvatex,2), 0, @ticketnumvatex);

                UPDATE ReturnedOrderSummary SET TicketRefNoVATEX = @ticketnumvatex WHERE PONumber = @parmpono;
            END;
        END

        DROP TABLE IF EXISTS #NewReturns;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        DROP TABLE IF EXISTS #NewReturns;

        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE(), @ErrSeverity INT = ERROR_SEVERITY();
        RAISERROR(@ErrMsg, @ErrSeverity, 1);
    END CATCH
END
GO

PRINT 'DEPLOYMENT COMPLETE: sections 1-7 applied. Re-read the header comment block for the list of objects still needing DDL from you before their dependents will run.';
