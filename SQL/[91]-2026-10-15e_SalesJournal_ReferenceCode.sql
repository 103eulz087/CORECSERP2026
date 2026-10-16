/* ================================================================
   [91] 2026-10-15e  Sales Journal: the inventory lot's ReferenceCode per line
   ================================================================
   User (2026-10-15): POS › POS Sales Report › Sales Journal
   (POSSalesReportDevEx.populateSalesJournal -> LoadCustomerSalesJournal ->
   dbo.funcview_CustomerSalesJournal) should show the ReferenceCode of the
   item's inventory.

   The function already reads it: its CTE takes one row per lot the line was
   taken from (InventoryDeliveryFIFO -> Inventory by SequenceReferenceNumber)
   and carries Inventory.ReferenceCode as ItemID, but the final SELECT had it
   commented out (--a.ItemID). It is now returned as ReferenceCode, right after
   Product. Nothing else changes: same parameters, same rows, same other
   columns in the same order (checked old vs new on all three tiers before
   the deploy).

   Callers: only POSSalesReportDevEx (SELECT *, columns read by name); no SQL
   object references it. Text identical on DEV / STAGING / PRODUCTION on
   2026-10-15 (whitespace-insensitive SHA-256 7797F2BF...).
   Deploy: rename to funcview_CustomerSalesJournal_OLD_10152026180000, CREATE,
   one transaction, guarded by that hash. Run in ONE connection, no open
   transaction. The exe of 2026-10-15 captions the column "Reference Code";
   an older exe just shows it as "ReferenceCode".
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET LOCK_TIMEOUT 10000;
GO

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[91] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.funcview_CustomerSalesJournal', 'IF') IS NULL
BEGIN
    RAISERROR('[91] stopped: funcview_CustomerSalesJournal does not exist in this database; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.funcview_CustomerSalesJournal_OLD_10152026180000') IS NOT NULL
BEGIN
    RAISERROR('[91] stopped: the backup funcview_CustomerSalesJournal_OLD_10152026180000 already exists ([91] already installed?); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(
            OBJECT_DEFINITION(OBJECT_ID('dbo.funcview_CustomerSalesJournal')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '7797F2BF35F5B93BFAA87ACE2A1F2774767083C2E83EEEE10B7C0AD362632630'
BEGIN
    RAISERROR('[91] stopped: funcview_CustomerSalesJournal is not the 2026-09-25c text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[91] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
EXEC sp_rename 'dbo.funcview_CustomerSalesJournal', 'funcview_CustomerSalesJournal_OLD_10152026180000';
GO

IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE FUNCTION [dbo].[funcview_CustomerSalesJournal]
(
    @datefrom       DATE,
    @dateto         DATE,
    @parmbranchcode VARCHAR(10)     -- NEW 2026-09-25c: NULL / '' / 'ALL' = all branches
)
RETURNS TABLE
AS
-- [91] 2026-10-15: ReferenceCode (the inventory lot's Inventory.ReferenceCode, one row per lot taken) after Product.
RETURN
(

    WITH zzz AS (
        SELECT
            a.BranchCode,
            a.PONumber,
            d.InvoiceNo,
            d.EffectivityDate as InvoiceDate,
            --a.QtyDelivered,
            case when c.isCreditMemo=1 then c.ActualQty when c.isReturned=1 then 0 else a.QtyDelivered end as QtyDelivered,
            b.ReferenceCode AS ItemID,
            a.ProductNo,
            a.Description,
            c.SellingPrice AS UnitPrice,
            --(c.SellingPrice * a.QtyDelivered) AS Amount,
            case when c.isCreditMemo=1 then (c.SellingPrice * c.ActualQty) when c.isReturned=1 then 0 else (c.SellingPrice * a.QtyDelivered) end as Amount,
            a.QtyDelivered AS StockingQty,
            c.Cost,
            (c.Cost * a.QtyDelivered) AS CostOfSalesAmount,
            c.isReturned,
            c.isCreditMemo
        FROM dbo.InventoryDeliveryFIFO a
        INNER JOIN dbo.Inventory b
            ON a.SequenceReferenceNumber = b.SequenceNumber
            --and a.isErrorCorrect=0
        INNER JOIN dbo.DeliveryDetails c
            ON a.PONumber = c.PONumber
            AND a.DeliveryNo = c.DeliveryNo
            AND a.ProductNo = c.ProductNo
            AND a.DevDetSeqNo = c.SeqNo
            AND c.isCancelled=0
        INNER JOIN dbo.DeliverySummary d
            ON d.PONumber = c.PONumber
            AND d.DeliveryNo = c.DeliveryNo
        -- NEW 2026-09-25c: branch filter applied early (before the joins below)
        WHERE (NULLIF(LTRIM(RTRIM(ISNULL(@parmbranchcode, ''))), '') IS NULL
               OR @parmbranchcode = 'ALL'
               OR a.BranchCode = @parmbranchcode)
    )
    SELECT
        c.CustomerKey,
        c.CustomerID,
        c.CustomerName,
        --c.CustomerEmail,
        --c.CustomerContactNo,
        --c.CustomerAddress,
        --c.Term,
        --c.TinNo,
        FORMAT(CAST(a.InvoiceDate AS DATE),'yyyy-MM-dd') AS InvoiceDate,
        a.InvoiceNo,
        CONCAT(a.BranchCode,' - ',br.BranchName) AS Branch,
        a.PONumber,
        --a.ItemID,
        CONCAT(a.ProductNo,' - ',a.Description) AS Product,
        a.ItemID AS ReferenceCode,       -- [91] the inventory lot's ReferenceCode
        --a.ProductNo,
        --a.Description,
        a.QtyDelivered,
        a.UnitPrice,
        FORMAT(a.Amount,'N2') AS Amount,
        --a.StockingQty,
        b.PayStatus,
        c.AccountOfficer,
        FORMAT(c.CustomerCreditLimit,'N2') AS CustomerCreditLimit,
        a.isCreditMemo,
        a.isReturned
        --a.Cost,
        --FORMAT(a.CostOfSalesAmount,'N2') AS CostOfSalesAmount
    FROM zzz a
    LEFT OUTER JOIN dbo.TransactionChargeSales b
        ON a.BranchCode = b.BranchCode
        AND a.PONumber = b.ReferenceNo
    INNER JOIN dbo.Customers c
        ON b.CustomerKey = c.CustomerKey
    INNER JOIN dbo.Branches br
        ON a.BranchCode = br.BranchCode
    WHERE     a.InvoiceDate >= @datefrom
            AND a.InvoiceDate < DATEADD(DAY,1,@dateto)
);
GO

IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF OBJECT_ID('dbo.funcview_CustomerSalesJournal', 'IF') IS NULL
    SET @msg = N'funcview_CustomerSalesJournal was not created';
ELSE IF OBJECT_ID('dbo.funcview_CustomerSalesJournal_OLD_10152026180000') IS NULL
    SET @msg = N'the backup is missing';
ELSE IF COL_LENGTH('dbo.funcview_CustomerSalesJournal', 'ReferenceCode') IS NULL
    SET @msg = N'the new function has no ReferenceCode column';

IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[91] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59894, @msg, 1;
END

COMMIT TRANSACTION;
PRINT '[91] committed: funcview_CustomerSalesJournal returns ReferenceCode; backup funcview_CustomerSalesJournal_OLD_10152026180000.';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
