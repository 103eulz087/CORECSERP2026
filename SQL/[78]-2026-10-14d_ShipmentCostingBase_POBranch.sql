/* ================================================================
   [78] 2026-10-14 - Shipment costing base = the PO branch's lots (not STS copies at other branches)
   ================================================================
   Found 2026-10-14 (user: Item Costing Recon shipments 10958 / 10977 / 10980 / 10984 / 10988 / 10994 went MATCHED -> VARIANCE
   on PRODUCTION). Nothing in the expenses changed. Every STS receipt creates a row at the receiving branch with the source
   lot's ShipmentNo / ReferenceCode / cost, while the source lot keeps its received Quantity. Anything that divides by
   SUM(Inventory.Quantity) WHERE ShipmentNo = @x therefore counts moved stock twice:
     - sp_rpt_ItemCostingRecon_List (the report)                 -> false VARIANCE
     - spu_PostExpenseV2 (landed cost of a PO-linked expense)    -> per-kg increment too small (under-costing)
     - sp_EditSingleExpense (back-out / re-apply on edit)        -> same
   (No expense has been posted after a transfer on PRODUCTION yet, so no lot cost is wrong today. Checked and NOT affected:
   spu_ConfirmPOFinalCost / sp_GetPOFinalCostItems, SP_POSTINVENTORY, sp_FinalizeInventoryUpload: they run while the lots are
   still held at Available 0, before any transfer can exist. Not called any more, left as is: sp_rpt_ItemCostingRecon_Header /
   _Detail.)

   User 2026-10-14: option 1 + "make sure this will not happen again".
   1. New dbo.fn_InvShipmentBase(): THE rule, in one place. A shipment's costing base = its Inventory rows at the PO's branch
      (POSUMMARY.BranchCode); when the PO branch holds none (111 legacy shipments uploaded straight to another branch, no
      linked expenses), the branch of its first-received row. Returns BaseBranch, BaseQty, BaseValue, MinCost, MaxCost.
   2. spu_PostExpenseV2: divides by BaseQty. The cost increment is still applied to every row of the shipment (STS copies are
      the same stock and carry the same per-kg cost). New refusal 56011 when a PO-linked expense has an inventory leg but the
      shipment has no base quantity (before: the cost update silently touched nothing and the inventory leg was lost;
      sp_EditSingleExpense already refuses this case, 56106).
   3. sp_EditSingleExpense: @NewQty / @OldQty = BaseQty.
   4. sp_rpt_ItemCostingRecon_List: TotalQty / MinCost / MaxCost from the base rows only.
   5. Exception Center (AP provider, if [70] is installed here): new fn_rpt_exc_AP_ShipmentCosting() with two INTEGRITY codes,
      folded into sp_rpt_exc_AP_Summary / _Detail:
        AP-EXPENSE-COSTING-DRIFT   PO CONFIRMED (final cost set; RECEIVED / FOR CONFIRMATION are still provisional), lots of one
                                   cost, and lot cost <> linked expenses' inventory legs / BaseQty by more than 0.01 (the recon's
                                   own MATCHED test as a standing check; all 39 CONFIRMED shipments on PRODUCTION pass it today)
        AP-COSTING-BASE-AMBIGUOUS  an STS receipt (ledger 'STS RCVD ITEM PO#', from 2026-10-02) of a lot of the shipment INTO its
                                   base branch: that copy can't be told from received stock, so the base would count it. Only
                                   shipments with a linked expense or a PO at RECEIVED / FOR CONFIRMATION / CONFIRMED (legacy
                                   shipments 01024 / 01039 at 006 moved back and forth on 10-06 and are not listed)
   6. Registry rows for the 2 codes (if the portal's sql/43 + [77] are installed here).

   Anchor patches of the live text (each anchor must occur exactly once, else nothing changes); backups _OLD_10142026120000.
   A part already applied (marker "[78]" in the live text) is skipped, so the script can be re-run, e.g. on PRODUCTION after
   [70] + [77]. One transaction; any failure rolls everything back. No exe change.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

BEGIN TRANSACTION;
GO

-- 1. the rule ---------------------------------------------------------------------------------------------------------------
CREATE OR ALTER FUNCTION dbo.fn_InvShipmentBase()
RETURNS TABLE
AS
/*  [78] 2026-10-14. The costing base of a PO shipment: its Inventory rows at the PO's branch (POSUMMARY.BranchCode), or,
    when the PO branch holds none, at the branch of the shipment's first-received row. STS receipts create rows at other
    branches with the same ShipmentNo / ReferenceCode / cost; they are the same stock and are NOT part of the base.
    Use this for every per-kg cost of a shipment (expense costing, edit back-out, recon, checks). Never divide by
    SUM(Quantity) WHERE ShipmentNo alone. Filter by ShipmentNo in the caller. */
RETURN
WITH po AS (
    SELECT p.ShipmentNo, MAX(p.BranchCode) AS POBranch
    FROM dbo.POSUMMARY AS p
    WHERE ISNULL(p.ShipmentNo, '') <> ''
    GROUP BY p.ShipmentNo),
first_row AS (
    SELECT i.ShipmentNo, i.Branch,
           ROW_NUMBER() OVER (PARTITION BY i.ShipmentNo ORDER BY i.DateReceived, i.SequenceNumber) AS rn
    FROM dbo.Inventory AS i
    WHERE ISNULL(i.ShipmentNo, '') NOT IN ('', 'CONVERSION')),
base AS (
    SELECT f.ShipmentNo,
           CASE WHEN EXISTS (SELECT 1 FROM dbo.Inventory AS x WHERE x.ShipmentNo = f.ShipmentNo AND x.Branch = po.POBranch)
                THEN po.POBranch ELSE f.Branch END AS BaseBranch
    FROM first_row AS f
    LEFT JOIN po ON po.ShipmentNo = f.ShipmentNo
    WHERE f.rn = 1)
SELECT b.ShipmentNo, b.BaseBranch,
       CAST(SUM(ISNULL(i.Quantity, 0)) AS DECIMAL(18,3))                     AS BaseQty,
       CAST(SUM(ISNULL(i.Quantity, 0) * ISNULL(i.Cost, 0)) AS DECIMAL(18,4)) AS BaseValue,
       MIN(i.Cost)                                                           AS MinCost,
       MAX(i.Cost)                                                           AS MaxCost,
       COUNT(*)                                                              AS BaseRows
FROM base AS b
INNER JOIN dbo.Inventory AS i ON i.ShipmentNo = b.ShipmentNo AND i.Branch = b.BaseBranch
GROUP BY b.ShipmentNo, b.BaseBranch;
GO

-- 2-4. anchor patches of the three procs ------------------------------------------------------------------------------------
BEGIN TRY
    DECLARE @Patch TABLE (Obj SYSNAME, Ord INT, Anchor NVARCHAR(400), Repl NVARCHAR(MAX));
    INSERT INTO @Patch (Obj, Ord, Anchor, Repl) VALUES
    (N'spu_PostExpenseV2', 1,
     N'SELECT @invsumQty=SUM(Quantity),@invsumTotalCost=SUM(Cost*Quantity) FROM Inventory WHERE ShipmentNo=@ShipmentNo',
     N'SELECT @invsumQty = b.BaseQty, @invsumTotalCost = b.BaseValue FROM dbo.fn_InvShipmentBase() AS b WHERE b.ShipmentNo = @ShipmentNo;  -- [78] base = the PO branch''s lots, not STS copies'),
    (N'spu_PostExpenseV2', 2,
     N'IF @InventoryCost <> 0',
     N'IF @InventoryCost <> 0 AND ISNULL(@invsumQty, 0) <= 0  -- [78]' + NCHAR(13) + NCHAR(10)
       + N'                THROW 56011, ''The linked shipment has no received quantity at its PO branch to cost against, so this expense''''s inventory cost would be lost. Link the expense after the goods are received.'', 1;' + NCHAR(13) + NCHAR(10)
       + N'            IF @InventoryCost <> 0'),
    (N'sp_EditSingleExpense', 1,
     N'SELECT @NewQty = SUM(Quantity) FROM Inventory WHERE ShipmentNo = @ShipmentNo;',
     N'SELECT @NewQty = b.BaseQty FROM dbo.fn_InvShipmentBase() AS b WHERE b.ShipmentNo = @ShipmentNo;  -- [78] base = the PO branch''s lots'),
    (N'sp_EditSingleExpense', 2,
     N'SELECT @OldQty = SUM(Quantity) FROM Inventory WHERE ShipmentNo = @CurShipmentNo;',
     N'SELECT @OldQty = b.BaseQty FROM dbo.fn_InvShipmentBase() AS b WHERE b.ShipmentNo = @CurShipmentNo;  -- [78] base = the PO branch''s lots'),
    (N'sp_rpt_ItemCostingRecon_List', 1,
     N'JOIN #Ship s ON s.ShipmentNo = i.ShipmentNo',
     N'JOIN #Ship s ON s.ShipmentNo = i.ShipmentNo' + NCHAR(13) + NCHAR(10)
       + N'    JOIN dbo.fn_InvShipmentBase() AS b ON b.ShipmentNo = i.ShipmentNo AND b.BaseBranch = i.Branch  -- [78] base rows only: STS copies at other branches would count moved stock twice');

    DECLARE @obj SYSNAME, @def NVARCHAR(MAX), @msg NVARCHAR(400), @a NVARCHAR(400), @r NVARCHAR(MAX), @n INT, @bak SYSNAME;
    DECLARE objs CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT Obj FROM @Patch;
    OPEN objs;
    FETCH NEXT FROM objs INTO @obj;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @def = OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + @obj));
        IF @def IS NULL
        BEGIN
            SET @msg = N'[78] ' + @obj + N' is missing here.';
            THROW 59985, @msg, 1;
        END
        IF CHARINDEX(N'[78]', @def) > 0
            PRINT N'[78] ' + @obj + N': already patched, skipped.';
        ELSE
        BEGIN
            DECLARE pt CURSOR LOCAL FAST_FORWARD FOR SELECT Anchor, Repl FROM @Patch WHERE Obj = @obj ORDER BY Ord;
            OPEN pt;
            FETCH NEXT FROM pt INTO @a, @r;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @n = (LEN(@def) - LEN(REPLACE(@def, @a, N''))) / LEN(@a);
                IF @n <> 1
                BEGIN
                    SET @msg = N'[78] ' + @obj + N': anchor found ' + CAST(@n AS NVARCHAR(10)) + N' times (expected 1): ' + LEFT(@a, 120);
                    THROW 59985, @msg, 1;
                END
                SET @def = REPLACE(@def, @a, @r);
                FETCH NEXT FROM pt INTO @a, @r;
            END
            CLOSE pt;
            DEALLOCATE pt;

            SET @bak = @obj + N'_OLD_10142026120000';
            IF OBJECT_ID(N'dbo.' + @bak) IS NOT NULL
            BEGIN
                SET @msg = N'[78] backup ' + @bak + N' already exists; nothing changed.';
                THROW 59985, @msg, 1;
            END
            SET @a = N'dbo.' + @obj;
            EXEC sp_rename @a, @bak;
            EXEC (@def);
            PRINT N'[78] ' + @obj + N': patched (backup ' + @bak + N').';
        END
        FETCH NEXT FROM objs INTO @obj;
    END
    CLOSE objs;
    DEALLOCATE objs;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @em NVARCHAR(2048) = N'[78] stopped, nothing changed: ' + ERROR_MESSAGE();
    RAISERROR(@em, 16, 1);
    SET NOEXEC ON;
END CATCH
GO

-- 5. Exception Center checks ------------------------------------------------------------------------------------------------
CREATE OR ALTER FUNCTION dbo.fn_rpt_exc_AP_ShipmentCosting()
RETURNS TABLE
AS
/*  [78] 2026-10-14. Read-only. Same columns as fn_rpt_exc_AP_Findings(); folded into sp_rpt_exc_AP_Summary / _Detail.
    AP-EXPENSE-COSTING-DRIFT, AP-COSTING-BASE-AMBIGUOUS: see SQL/[78]-2026-10-14d_ShipmentCostingBase_POBranch.sql. */
RETURN
WITH ex AS (
    SELECT es.ShipmentNo, COUNT(*) AS nExp, SUM(ISNULL(t.InvCost, 0)) AS Legs
    FROM dbo.ExpenseSummary AS es
    CROSS APPLY (SELECT SUM(ISNULL(td.Debit, 0) - ISNULL(td.Credit, 0)) AS InvCost
                 FROM dbo.TicketMaster AS tm
                 INNER JOIN dbo.TicketDetails AS td ON td.TicketNumber = tm.TicketNumber AND td.ReferenceNumber = tm.ReferenceNumber
                 WHERE tm.ReferenceNumber = es.ReferenceNumber AND tm.ReferenceKey = es.InvoiceNo AND tm.Mnemonic = 'SINGLE'
                   AND td.AccountCode IN (SELECT a.AccountCode FROM dbo.fn_InventoryCostAccounts() AS a)) AS t
    WHERE es.PostingMode = 'SINGLE' AND ISNULL(es.ShipmentNo, '') NOT IN ('', 'CONVERSION')
    GROUP BY es.ShipmentNo),
po AS (
    SELECT p.ShipmentNo, MAX(p.Status) AS Status, MAX(p.SupplierID) AS SupplierID
    FROM dbo.POSUMMARY AS p GROUP BY p.ShipmentNo),
drift AS (
    SELECT ex.ShipmentNo, po.SupplierID, b.BaseBranch, b.BaseQty, b.MaxCost, ex.Legs, ex.nExp,
           CAST(ex.Legs / NULLIF(b.BaseQty, 0) AS DECIMAL(18,4)) AS ExpPerKg
    FROM ex
    INNER JOIN dbo.fn_InvShipmentBase() AS b ON b.ShipmentNo = ex.ShipmentNo
    LEFT JOIN po ON po.ShipmentNo = ex.ShipmentNo
    WHERE po.Status = 'CONFIRMED'   -- final cost set (POFinalCostLog); RECEIVED / FOR CONFIRMATION still carry a provisional cost
      AND b.BaseQty > 0
      AND ABS(ISNULL(b.MinCost, 0) - ISNULL(b.MaxCost, 0)) <= 0.01),
amb AS (
    SELECT b.ShipmentNo, b.BaseBranch, r.PONumber, r.ReferenceCode, SUM(il.QtyIN) AS QtyIn
    FROM dbo.fn_InvShipmentBase() AS b
    INNER JOIN (SELECT DISTINCT i.ShipmentNo, i.Branch, i.ReferenceCode, i.Product FROM dbo.Inventory AS i
                WHERE ISNULL(i.ReferenceCode, '') <> '') AS lot
            ON lot.ShipmentNo = b.ShipmentNo AND lot.Branch = b.BaseBranch
    INNER JOIN dbo.ReceivedOrderDetails AS r ON r.ReferenceCode = lot.ReferenceCode AND r.ProductCode = lot.Product
    INNER JOIN dbo.InventoryLedger AS il
            ON il.Remarks = 'STS RCVD ITEM PO#' + CAST(r.PONumber AS VARCHAR(20))
           AND il.Product = r.ProductCode AND il.DestinationBranch = b.BaseBranch AND il.QtyIN > 0
    -- only shipments whose costing can still matter: a linked expense, or a PO in the current flow (legacy DELIVERED /
    -- PO-less shipments moving between branches are normal and can't be "fixed")
    WHERE EXISTS (SELECT 1 FROM ex WHERE ex.ShipmentNo = b.ShipmentNo)
       OR EXISTS (SELECT 1 FROM po WHERE po.ShipmentNo = b.ShipmentNo AND po.Status IN ('RECEIVED', 'FOR CONFIRMATION', 'CONFIRMED'))
    GROUP BY b.ShipmentNo, b.BaseBranch, r.PONumber, r.ReferenceCode)
SELECT CAST('AP-EXPENSE-COSTING-DRIFT' AS VARCHAR(50)) AS ExceptionCode,
       CAST('SHIPMENT ' + d.ShipmentNo AS VARCHAR(50)) AS Ref, CAST(NULL AS VARCHAR(30)) AS VoucherID,
       CAST(d.SupplierID AS VARCHAR(50)) AS SupplierID, CAST(NULL AS VARCHAR(150)) AS InvoiceNo,
       CAST(d.ExpPerKg AS DECIMAL(18,4)) AS Expected, CAST(d.MaxCost AS DECIMAL(18,4)) AS Actual,
       CAST(d.MaxCost - d.ExpPerKg AS DECIMAL(18,4)) AS Difference,
       CAST(ABS(d.MaxCost - d.ExpPerKg) * d.BaseQty AS DECIMAL(18,2)) AS ValueAtRisk,
       CAST('lot cost ' + FORMAT(d.MaxCost, 'N4') + ' vs linked expenses ' + FORMAT(d.Legs, 'N2') + ' / ' + FORMAT(d.BaseQty, 'N3')
            + ' kg at branch ' + d.BaseBranch + ' = ' + FORMAT(d.ExpPerKg, 'N4') + ' (' + CAST(d.nExp AS VARCHAR(10)) + ' expense(s))' AS VARCHAR(400)) AS Detail,
       CAST('The lot cost no longer equals what the linked expenses put in. Check the expenses posted / edited / reversed for this shipment, a hand edit of Inventory.Cost, or a final-cost confirmation that replaced the cost.' AS VARCHAR(400)) AS Hint
FROM drift AS d
WHERE ABS(d.MaxCost - d.ExpPerKg) > 0.01
UNION ALL
SELECT CAST('AP-COSTING-BASE-AMBIGUOUS' AS VARCHAR(50)),
       CAST('SHIPMENT ' + a.ShipmentNo + ' / STS ' + CAST(a.PONumber AS VARCHAR(20)) AS VARCHAR(50)), CAST(NULL AS VARCHAR(30)),
       CAST(NULL AS VARCHAR(50)), CAST(NULL AS VARCHAR(150)),
       CAST(NULL AS DECIMAL(18,4)), CAST(a.QtyIn AS DECIMAL(18,4)), CAST(NULL AS DECIMAL(18,4)), CAST(NULL AS DECIMAL(18,2)),
       CAST('STS PO#' + CAST(a.PONumber AS VARCHAR(20)) + ' received ' + FORMAT(a.QtyIn, 'N3') + ' of lot ' + a.ReferenceCode
            + ' into branch ' + a.BaseBranch + ', the shipment''s own (PO) branch' AS VARCHAR(400)),
       CAST('Stock of this shipment came back into its PO branch, so the costing base ([78], fn_InvShipmentBase) counts it twice. Tell the ERP session before linking or editing an expense on this shipment.' AS VARCHAR(400))
FROM amb AS a;
GO

BEGIN TRY
    IF OBJECT_ID('dbo.sp_rpt_exc_AP_Summary', 'P') IS NULL OR OBJECT_ID('dbo.sp_rpt_exc_AP_Detail', 'P') IS NULL
        PRINT N'[78] AP provider ([70]) not installed here: the two checks are in fn_rpt_exc_AP_ShipmentCosting(); re-run [78] after [70] + [77] to add them to the portal.';
    ELSE
    BEGIN
        DECLARE @P2 TABLE (Obj SYSNAME, Ord INT, Anchor NVARCHAR(400), Repl NVARCHAR(MAX));
        INSERT INTO @P2 VALUES
        (N'sp_rpt_exc_AP_Summary', 1, N'(''AP-STATUS-VS-BALANCE'', 1), (''AP-CHEQUE-REUSED'', 0);',
         N'(''AP-STATUS-VS-BALANCE'', 1), (''AP-CHEQUE-REUSED'', 0),' + NCHAR(13) + NCHAR(10)
           + N'                              (''AP-EXPENSE-COSTING-DRIFT'', 1), (''AP-COSTING-BASE-AMBIGUOUS'', 0);  -- [78]'),
        (N'sp_rpt_exc_AP_Summary', 2, N'FROM dbo.fn_rpt_exc_AP_Findings() GROUP BY ExceptionCode',
         N'FROM (SELECT ExceptionCode, ValueAtRisk FROM dbo.fn_rpt_exc_AP_Findings() UNION ALL SELECT ExceptionCode, ValueAtRisk FROM dbo.fn_rpt_exc_AP_ShipmentCosting()) AS u GROUP BY ExceptionCode'),
        (N'sp_rpt_exc_AP_Detail', 1, N'''AP-STATUS-VS-BALANCE'', ''AP-CHEQUE-REUSED'')',
         N'''AP-STATUS-VS-BALANCE'', ''AP-CHEQUE-REUSED'', ''AP-EXPENSE-COSTING-DRIFT'', ''AP-COSTING-BASE-AMBIGUOUS'')  -- [78]'),
        (N'sp_rpt_exc_AP_Detail', 2, N'FROM dbo.fn_rpt_exc_AP_Findings() f',
         N'FROM (SELECT * FROM dbo.fn_rpt_exc_AP_Findings() UNION ALL SELECT * FROM dbo.fn_rpt_exc_AP_ShipmentCosting()) AS f');

        DECLARE @obj2 SYSNAME, @def2 NVARCHAR(MAX), @msg2 NVARCHAR(400), @a2 NVARCHAR(400), @r2 NVARCHAR(MAX), @n2 INT, @bak2 SYSNAME;
        DECLARE objs2 CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT Obj FROM @P2;
        OPEN objs2;
        FETCH NEXT FROM objs2 INTO @obj2;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @def2 = OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + @obj2));
            IF CHARINDEX(N'[78]', @def2) > 0
                PRINT N'[78] ' + @obj2 + N': already patched, skipped.';
            ELSE
            BEGIN
                DECLARE pt2 CURSOR LOCAL FAST_FORWARD FOR SELECT Anchor, Repl FROM @P2 WHERE Obj = @obj2 ORDER BY Ord;
                OPEN pt2;
                FETCH NEXT FROM pt2 INTO @a2, @r2;
                WHILE @@FETCH_STATUS = 0
                BEGIN
                    SET @n2 = (LEN(@def2) - LEN(REPLACE(@def2, @a2, N''))) / LEN(@a2);
                    IF @n2 <> 1
                    BEGIN
                        SET @msg2 = N'[78] ' + @obj2 + N': anchor found ' + CAST(@n2 AS NVARCHAR(10)) + N' times (expected 1): ' + LEFT(@a2, 120);
                        THROW 59985, @msg2, 1;
                    END
                    SET @def2 = REPLACE(@def2, @a2, @r2);
                    FETCH NEXT FROM pt2 INTO @a2, @r2;
                END
                CLOSE pt2;
                DEALLOCATE pt2;
                SET @bak2 = @obj2 + N'_OLD_10142026120000';
                IF OBJECT_ID(N'dbo.' + @bak2) IS NOT NULL
                BEGIN
                    SET @msg2 = N'[78] backup ' + @bak2 + N' already exists; nothing changed.';
                    THROW 59985, @msg2, 1;
                END
                SET @a2 = N'dbo.' + @obj2;
                EXEC sp_rename @a2, @bak2;
                EXEC (@def2);
                PRINT N'[78] ' + @obj2 + N': patched (backup ' + @bak2 + N').';
            END
            FETCH NEXT FROM objs2 INTO @obj2;
        END
        CLOSE objs2;
        DEALLOCATE objs2;
    END

    -- 6. registry rows (portal sql/43 + [77])
    IF COL_LENGTH('dbo.ExceptionDefinition', 'ProviderProc') IS NOT NULL AND OBJECT_ID('dbo.sp_rpt_exc_AP_Provider', 'P') IS NOT NULL
        EXEC sp_executesql N'
        INSERT INTO dbo.ExceptionDefinition
            (ExceptionCode, Category, Title, Severity, HasDrillDown, DrillDownRoute, IsActive, SortOrder,
             Module, [Kind], ProviderProc, [Owner], ThresholdDays, [Action])
        SELECT d.ExceptionCode, d.Category, d.Title, d.Severity, 1, NULL, 1, d.SortOrder,
               ''AP'', ''INTEGRITY'', ''sp_rpt_exc_AP_Provider'', ''erp'', NULL, d.[Action]
        FROM (VALUES
            (''AP-EXPENSE-COSTING-DRIFT'', ''Post Expense'', ''Shipment lot cost differs from its linked expenses'', ''Critical'', 110,
             ''Lot cost must equal the linked expenses'''' inventory legs / the PO branch quantity ([78]). Check expenses posted, edited or reversed for the shipment, hand edits of Inventory.Cost, and the final-cost confirmation.''),
            (''AP-COSTING-BASE-AMBIGUOUS'', ''Post Expense'', ''Shipment stock transferred back into its PO branch'', ''Warning'', 111,
             ''An STS receipt brought this shipment''''s lot back into its PO branch, so the costing base counts it twice. Ask the ERP session before linking or editing an expense on it.'')
        ) AS d (ExceptionCode, Category, Title, Severity, SortOrder, [Action])
        WHERE NOT EXISTS (SELECT 1 FROM dbo.ExceptionDefinition AS e WHERE e.ExceptionCode = d.ExceptionCode);';
    ELSE
        PRINT N'[78] portal registry (sql/43) or [77] not installed here: registry rows not added; re-run [78] after them.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @em2 NVARCHAR(2048) = N'[78] stopped, nothing changed: ' + ERROR_MESSAGE();
    RAISERROR(@em2, 16, 1);
    SET NOEXEC ON;
END CATCH
GO

-- post-check: the three procs carry the rule; the function answers
IF OBJECT_DEFINITION(OBJECT_ID('dbo.spu_PostExpenseV2')) NOT LIKE '%fn_InvShipmentBase%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_EditSingleExpense')) NOT LIKE '%fn_InvShipmentBase%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_rpt_ItemCostingRecon_List')) NOT LIKE '%fn_InvShipmentBase%'
   OR NOT EXISTS (SELECT 1 FROM dbo.fn_InvShipmentBase())
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[78] post-check failed; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
GO

SET NOEXEC OFF;
GO
SELECT name, CONVERT(VARCHAR(16), modify_date, 120) AS Modified FROM sys.objects
WHERE name IN ('fn_InvShipmentBase', 'fn_rpt_exc_AP_ShipmentCosting', 'spu_PostExpenseV2', 'sp_EditSingleExpense', 'sp_rpt_ItemCostingRecon_List',
               'sp_rpt_exc_AP_Summary', 'sp_rpt_exc_AP_Detail') ORDER BY name;
GO
