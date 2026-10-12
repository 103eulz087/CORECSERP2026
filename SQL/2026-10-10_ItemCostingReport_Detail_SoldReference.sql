/* ================================================================
   2026-10-10: Item Costing Report movement ledger - Reference column
   ================================================================
   User request (Reporting/ItemCostingReport.cs, "Movement Ledger" detail):
     * Sold     -> Reference = the invoice number, then the customer as
                   "CustomerBranch-CustomerName", e.g. "J38560 | 888-BAYARCAL, JIMMY";
     * Transfer -> Reference = the transfer's PO number (as before).
   Invoice: DeliverySummary.InvoiceNo of the delivery (DeliveryNo + PONumber;
   every sold delivery on STAGING has one, 7,945 checked). Customer: the sales
   order's PurchaseOrderSummary.Customer -> Customers (BranchCode, CustomerName);
   14 sold deliveries have no customer there and show the invoice only. A sale
   with a blank invoice falls back to the PO number.
   A PO delivered twice on one day with two invoices now shows as two rows
   (one per invoice) instead of one.
   BranchName stays in the result (hidden on the screen, C# side), so nothing
   else changes. Only caller: Reporting/ItemCostingReport.cs.
   Anchor patch of the live text (it differs from SQL/2026-09-07_ItemCostingReport.sql,
   changed 2026-09-28c); backup _OLD_10102026120000. One transaction with a post-check.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
BEGIN TRANSACTION;
CREATE TABLE #Patch (Id INT IDENTITY PRIMARY KEY, Obj SYSNAME NOT NULL, OldText NVARCHAR(MAX) NOT NULL, NewText NVARCHAR(MAX) NOT NULL);
GO

CREATE PROCEDURE #ApplyPatch @Obj SYSNAME
AS
BEGIN
    DECLARE @def NVARCHAR(MAX) = REPLACE(OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + @Obj)), NCHAR(13) + NCHAR(10), NCHAR(10));
    DECLARE @msg NVARCHAR(400);
    IF @def IS NULL
    BEGIN
        SET @msg = N'Cannot read the definition of ' + @Obj + N'; nothing changed.';
        THROW 59960, @msg, 1;
    END
    IF EXISTS (SELECT 1 FROM #Patch WHERE Obj = @Obj
               AND (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, OldText, N''))) / DATALENGTH(OldText) <> 1)
    BEGIN
        SET @msg = @Obj + N' text differs from the expected version (an anchor is missing or repeated); nothing changed.';
        THROW 59961, @msg, 1;
    END
    DECLARE @o NVARCHAR(MAX), @n NVARCHAR(MAX);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT OldText, NewText FROM #Patch WHERE Obj = @Obj ORDER BY Id;
    OPEN c; FETCH NEXT FROM c INTO @o, @n;
    WHILE @@FETCH_STATUS = 0 BEGIN SET @def = REPLACE(@def, @o, @n); FETCH NEXT FROM c INTO @o, @n; END
    CLOSE c; DEALLOCATE c;
    DECLARE @old SYSNAME = @Obj + N'_OLD_10102026120000', @full NVARCHAR(300) = N'dbo.' + @Obj;
    EXEC sp_rename @full, @old;
    EXEC (@def);
    IF OBJECT_ID(@full) IS NULL
    BEGIN
        SET @msg = @Obj + N' was not recreated.';
        THROW 59962, @msg, 1;
    END
END
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
IF OBJECT_ID('dbo.sp_rpt_ItemCostingReport_Detail_OLD_10102026120000', 'P') IS NOT NULL
BEGIN
    RAISERROR('This script has been run here before (sp_rpt_ItemCostingReport_Detail_OLD_10102026120000 exists).', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
INSERT INTO #Patch (Obj, OldText, NewText) VALUES
(N'sp_rpt_ItemCostingReport_Detail',
 N'            CAST(D.PONumber AS VARCHAR(50)) AS Reference,',
 N'            -- 2026-10-10 (user): Sold = invoice no. | customer "branch-name"; Transfer (or no invoice) = PO no.
            CAST(CASE WHEN MT.MovementType = ''Sold'' AND ISNULL(LTRIM(RTRIM(DS.InvoiceNo)), '''') <> ''''
                      THEN LTRIM(RTRIM(DS.InvoiceNo))
                           + ISNULL('' | '' + LTRIM(RTRIM(CU.BranchCode)) + ''-'' + LTRIM(RTRIM(CU.CustomerName)), '''')
                      ELSE CAST(D.PONumber AS VARCHAR(50)) END AS VARCHAR(250)) AS Reference,'),
(N'sp_rpt_ItemCostingReport_Detail',
 N'        JOIN dbo.Branches b ON b.BranchCode=D.BranchCode',
 N'        JOIN dbo.Branches b ON b.BranchCode=D.BranchCode
        -- 2026-10-10: the delivery''s invoice and the sales order''s customer (one row each per delivery / PO)
        OUTER APPLY (SELECT TOP (1) X.InvoiceNo FROM dbo.DeliverySummary X
                     WHERE X.DeliveryNo = D.DeliveryNo AND X.PONumber = D.PONumber) DS
        OUTER APPLY (SELECT TOP (1) C.BranchCode, C.CustomerName
                     FROM dbo.PurchaseOrderSummary P INNER JOIN dbo.Customers C ON C.CustomerKey = P.Customer
                     WHERE P.PONumber = D.PONumber) CU'),
(N'sp_rpt_ItemCostingReport_Detail',
 N'        GROUP BY I.Product, I.ShipmentNo, ISNULL(I.ReferenceCode, ''''), D.DateProcessed, D.PONumber, MT.MovementType,b.BranchName',
 N'        GROUP BY I.Product, I.ShipmentNo, ISNULL(I.ReferenceCode, ''''), D.DateProcessed, D.PONumber, MT.MovementType,b.BranchName,
                 DS.InvoiceNo, CU.BranchCode, CU.CustomerName   -- 2026-10-10');
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'sp_rpt_ItemCostingReport_Detail';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_rpt_ItemCostingReport_Detail')) NOT LIKE '%DS.InvoiceNo, CU.BranchCode, CU.CustomerName%'
BEGIN
    RAISERROR('Post-check failed; rolled back.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
COMMIT TRANSACTION;
PRINT 'sp_rpt_ItemCostingReport_Detail: Sold reference = invoice | customer (backup _OLD_10102026120000).';
GO
SET NOEXEC OFF;
GO
