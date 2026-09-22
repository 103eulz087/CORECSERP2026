/* ================================================================
   PO "Confirm and Finalize Cost" (VIEWPO.cs, FOR CONFIRMATION tab)
   ================================================================
   Flow this supports:
     1. Receiving (AddInventoryDevEx -> SP_POSTINVENTORY) inserts the
        shipment's Inventory rows with Available = 0 and sets
        POSUMMARY.Status = 'FOR CONFIRMATION' (already done in the
        live SP_POSTINVENTORY - NOT touched here).
     2. The user finalizes the cost per distinct Product on the
        POFinalizeCostFrm dialog -> spu_ConfirmPOFinalCost:
          - Inventory.Cost  = Final Cost   (every lot of that Product
            in this shipment; the provisional cost is kept only in
            POFinalCostLog)
          - Inventory.Available = Inventory.Quantity
          - POSUMMARY.Status = 'RECEIVED'
     3. (Later) the AP step (spu_APAccounts) runs from RECEIVED.

   Objects (all new - dedicated to this module, per CLAUDE.md):
     dbo.POFinalCostLog            audit of provisional vs final cost
     dbo.POFinalCostTVP            (Product, FinalCost) lines from the form
     dbo.sp_GetPOFinalCostItems    read: distinct Product, SUM(Quantity), Cost
     dbo.spu_ConfirmPOFinalCost    post: atomic finalize

   ASSUMED COLUMNS (not scripted anywhere in the repo - verify on DEV
   before first run; the script will fail to compile/run if wrong):
     Inventory : ShipmentNo, Product, Description, Quantity, Cost, Available
     POSUMMARY : ShipmentNo, SupplierID, Status
   (Inventory has no SupplierID assumed; the supplier is validated
   through POSUMMARY.)

   Guard for shipments received BEFORE the SP_POSTINVENTORY change:
   their lots already have Available > 0 (possibly partly consumed).
   spu_ConfirmPOFinalCost refuses any shipment that has a lot with
   Available <> 0, so it can never overwrite live stock levels with
   Quantity.

   Deploy to CORECSERP_002_DEV first; mirror to CORECSJFC2026_STAGING
   only after confirming with the user, per project convention.
   ================================================================ */

-- ----------------------------------------------------------------
-- 1. Audit table
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.POFinalCostLog', 'U') IS NULL
    CREATE TABLE dbo.POFinalCostLog
    (
        LogID            BIGINT IDENTITY(1,1) PRIMARY KEY,
        ShipmentNo       VARCHAR(50)    NOT NULL,
        SupplierID       VARCHAR(50)    NOT NULL,
        Product          VARCHAR(50)    NOT NULL,
        Quantity         DECIMAL(18,3)  NOT NULL,
        ProvisionalCost  DECIMAL(18,4)  NOT NULL,
        FinalCost        DECIMAL(18,4)  NOT NULL,
        FinalizedBy      VARCHAR(50)    NOT NULL,
        FinalizedAt      DATETIME       NOT NULL CONSTRAINT DF_POFinalCostLog_At DEFAULT (GETDATE())
    );
GO

-- ----------------------------------------------------------------
-- 2. TVP
-- ----------------------------------------------------------------
IF TYPE_ID(N'dbo.POFinalCostTVP') IS NULL
    CREATE TYPE dbo.POFinalCostTVP AS TABLE
    (
        Product    VARCHAR(50),
        FinalCost  DECIMAL(18,4)
    );
GO

-- ----------------------------------------------------------------
-- 3. sp_GetPOFinalCostItems - one row per distinct Product
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_GetPOFinalCostItems', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetPOFinalCostItems', 'sp_GetPOFinalCostItems_OLD_20260921130000';
GO

CREATE PROCEDURE dbo.sp_GetPOFinalCostItems
(
    @parmshipmentno  VARCHAR(50),
    @parmsupplierid  VARCHAR(50)
)
AS
/*
    Items awaiting cost finalization for one PO shipment. Quantity is
    summed across the shipment's lots; Cost is the quantity-weighted
    average provisional cost (equals the lot cost when every lot of a
    Product carries the same one). Returns nothing unless the PO is
    FOR CONFIRMATION. Numeric columns are returned as real DECIMALs.
    Callers: POFinalizeCostFrm.cs LoadData().
*/
BEGIN
    SET NOCOUNT ON;

    SELECT
        i.Product,
        MAX(i.Description)                                        AS Description,
        CAST(SUM(i.Quantity) AS DECIMAL(18,3))                    AS Quantity,
        CAST(CASE WHEN SUM(i.Quantity) = 0 THEN MAX(i.Cost)
                  ELSE SUM(i.Quantity * i.Cost) / SUM(i.Quantity)
             END AS DECIMAL(18,4))                                AS Cost
    FROM dbo.Inventory i
    WHERE i.ShipmentNo = @parmshipmentno
      AND EXISTS (SELECT 1 FROM dbo.POSUMMARY p
                  WHERE p.ShipmentNo = @parmshipmentno
                    AND p.SupplierID = @parmsupplierid
                    AND p.Status = 'FOR CONFIRMATION')
    GROUP BY i.Product
    ORDER BY i.Product;
END
GO

-- ----------------------------------------------------------------
-- 4. spu_ConfirmPOFinalCost - atomic finalize
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.spu_ConfirmPOFinalCost', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_ConfirmPOFinalCost', 'spu_ConfirmPOFinalCost_OLD_20260921130000';
GO

CREATE PROCEDURE dbo.spu_ConfirmPOFinalCost
(
    @parmshipmentno  VARCHAR(50),
    @parmsupplierid  VARCHAR(50),
    @parmuser        VARCHAR(50),
    @Lines           dbo.POFinalCostTVP READONLY
)
AS
/*
    Finalizes the cost of a received PO shipment and releases its
    inventory. See the script header for the flow. Everything happens
    in one transaction: Inventory.Cost/Available, POSUMMARY.Status and
    the audit log either all change or none do.

    Errors (58100+ range, this module only):
      58101 shipment/supplier missing or CONVERSION/blank shipment
      58102 no lines
      58103 a FinalCost <= 0
      58104 duplicate Product in lines
      58105 PO not found
      58106 PO is not FOR CONFIRMATION
      58107 lines don't match the shipment's distinct Products
      58108 a lot of this shipment is already Available (legacy / consumed)
      58109 Inventory rowcount mismatch on release
      58110 POSUMMARY status flip failed
    Callers: POFinalizeCostFrm.cs BtnConfirm_Click.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ── Validation (no reads of live state yet) ─────────────────
    IF LTRIM(RTRIM(ISNULL(@parmshipmentno,''))) IN ('', 'CONVERSION')
       OR LTRIM(RTRIM(ISNULL(@parmsupplierid,''))) = ''
    BEGIN
        THROW 58101, 'A Shipment No. and Supplier are required.', 1;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM @Lines)
    BEGIN
        THROW 58102, 'Nothing to finalize - no cost lines were supplied.', 1;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM @Lines WHERE ISNULL(FinalCost,0) <= 0 OR LTRIM(RTRIM(ISNULL(Product,''))) = '')
    BEGIN
        THROW 58103, 'Every item needs a Final Cost greater than zero.', 1;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM @Lines GROUP BY Product HAVING COUNT(*) > 1)
    BEGIN
        THROW 58104, 'The same item appears more than once in the cost lines.', 1;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRAN;

        -- Lock the PO header for the rest of the transaction so two
        -- users can't finalize the same shipment at once.
        DECLARE @status VARCHAR(30);
        SELECT @status = Status
        FROM dbo.POSUMMARY WITH (UPDLOCK, ROWLOCK)
        WHERE ShipmentNo = @parmshipmentno AND SupplierID = @parmsupplierid;

        IF @status IS NULL
        BEGIN
            THROW 58105, 'Purchase order not found for this Shipment No. and Supplier.', 1;
        END

        IF @status <> 'FOR CONFIRMATION'
        BEGIN
            DECLARE @StatusMsg VARCHAR(300) = 'This purchase order is ' + ISNULL(@status,'') + ', not FOR CONFIRMATION - its cost can no longer be finalized here.';
            THROW 58106, @StatusMsg, 1;
        END

        -- The lines must cover exactly the shipment's distinct
        -- Products - a missing one would be released at its old
        -- provisional cost, an unknown one is a stale/wrong form.
        IF EXISTS (
            SELECT 1
            FROM (SELECT DISTINCT Product FROM dbo.Inventory WHERE ShipmentNo = @parmshipmentno) inv
            LEFT JOIN @Lines l ON l.Product = inv.Product
            WHERE l.Product IS NULL
        )
        OR EXISTS (
            SELECT 1 FROM @Lines l
            WHERE NOT EXISTS (SELECT 1 FROM dbo.Inventory i WHERE i.ShipmentNo = @parmshipmentno AND i.Product = l.Product)
        )
        BEGIN
            THROW 58107, 'The items on screen no longer match this shipment''s inventory. Close the form, reopen it and try again.', 1;
        END

        -- Legacy / already-released shipment guard: only lots still
        -- held at Available = 0 may be released. Anything else may be
        -- partly consumed and must not be reset to Quantity.
        IF EXISTS (SELECT 1 FROM dbo.Inventory WITH (UPDLOCK, ROWLOCK)
                   WHERE ShipmentNo = @parmshipmentno AND ISNULL(Available,0) <> 0)
        BEGIN
            THROW 58108, 'This shipment already has inventory available (received before cost confirmation was introduced, or partly consumed). Finalizing it here would overwrite live stock levels.', 1;
        END

        -- Audit first, while Inventory.Cost still holds the
        -- provisional figure.
        INSERT INTO dbo.POFinalCostLog
            (ShipmentNo, SupplierID, Product, Quantity, ProvisionalCost, FinalCost, FinalizedBy)
        SELECT @parmshipmentno, @parmsupplierid, i.Product,
               SUM(i.Quantity),
               CASE WHEN SUM(i.Quantity) = 0 THEN MAX(i.Cost) ELSE SUM(i.Quantity * i.Cost) / SUM(i.Quantity) END,
               l.FinalCost,
               @parmuser
        FROM dbo.Inventory i
        JOIN @Lines l ON l.Product = i.Product
        WHERE i.ShipmentNo = @parmshipmentno
        GROUP BY i.Product, l.FinalCost;

        -- Release: final cost + Available = Quantity, in one statement.
        DECLARE @expectedRows INT = (SELECT COUNT(*) FROM dbo.Inventory WHERE ShipmentNo = @parmshipmentno);

        UPDATE i
        SET i.Cost = l.FinalCost,
            i.Available = i.Quantity
        FROM dbo.Inventory i
        JOIN @Lines l ON l.Product = i.Product
        WHERE i.ShipmentNo = @parmshipmentno;

        IF @@ROWCOUNT <> @expectedRows
        BEGIN
            THROW 58109, 'The inventory release did not touch every lot of this shipment - nothing was saved.', 1;
        END

        UPDATE dbo.POSUMMARY
        SET Status = 'RECEIVED'
        WHERE ShipmentNo = @parmshipmentno AND SupplierID = @parmsupplierid AND Status = 'FOR CONFIRMATION';

        IF @@ROWCOUNT <> 1
        BEGIN
            THROW 58110, 'The purchase order status could not be updated - nothing was saved.', 1;
        END

        COMMIT TRAN;

        SELECT 1 AS Status, @parmshipmentno AS ShipmentNo,
               'Cost finalized and inventory released.' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO
