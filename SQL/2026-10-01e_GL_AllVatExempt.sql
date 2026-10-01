/* ================================================================
   2026-10-01e: the GL is all VAT-exempt (client rule)
   ================================================================
   Client rule (2026-10-01): every item posts as VAT-exempt in the GL.
   The VAT split appears only on the printed invoice (the line isVat,
   SubTotal / TaxTotal, BatchSalesSummary VAT columns stay as they are);
   the month-end VAT is computed by hand outside the books.

   Needs 2026-10-01_SalesOrder_Lifecycle_Fixes.sql (19) and
   2026-10-01b_STS_Lifecycle_Fixes.sql (20). Run before 21.

   Patches, each by exact one-line replacements of the live text
   (every replacement must match exactly once, or nothing changes):
     sp_ConfirmOrder                    one SI-VATEX ticket for the whole invoice
                                        (GROSS = all lines, COST = all lines);
                                        no SI-VAT ticket any more
     sp_CreditMemo                      SO-CM-VATEX / SO-SHRINK-VATEX for every line
     sp_ReturnSalesOrder                SO-RET-VATEX for every line
     spu_STS_SyncInTransit              In Transit target all VAT-exempt; any VAT
                                        transit already posted is reversed (ITR-HO-VAT)
     sp_ConfirmBranchRecievedOrderJFC   IT-BR-VATEX and STS-SHORT/OVER-VATEX only
   The previous versions are kept as <name>_OLD_10012026210000.
   No parameters change, so no exe change.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('dbo.spu_STS_SyncInTransit', 'P') IS NULL OR OBJECT_ID('dbo.spu_SO_PostInvoiceReduction', 'P') IS NULL
    THROW 59720, 'Run 2026-10-01_SalesOrder_Lifecycle_Fixes.sql and 2026-10-01b_STS_Lifecycle_Fixes.sql first.', 1;

IF OBJECT_ID('tempdb..#P') IS NOT NULL DROP TABLE #P;
CREATE TABLE #P (Id INT IDENTITY PRIMARY KEY, ProcName SYSNAME, OldText NVARCHAR(MAX), NewText NVARCHAR(MAX));

-- sp_ConfirmOrder: fold the VAT lines into the VAT-exempt ticket right before posting
INSERT #P (ProcName, OldText, NewText) VALUES
('sp_ConfirmOrder',
 N'-- SI-VAT ticket (only if there are vatable items)',
 N'-- 2026-10-01: the GL is all VAT-exempt (client rule). The VAT split stays on the lines and
        -- BatchSalesSummary for the printed invoice; the whole invoice and its cost post on SI-VATEX.
        SET @totalVATExempt = ISNULL(@totalAmount, 0);
        SET @totalVATEXCost = ISNULL(@totalVATEXCost, 0) + ISNULL(@totalVATCost, 0);
        SET @totalVATSub = 0;
        SET @totalVAT = 0;
        SET @totalVATCost = 0;

        -- SI-VAT ticket (not posted any more: the amounts above are 0)');

-- sp_CreditMemo
INSERT #P (ProcName, OldText, NewText) VALUES
('sp_CreditMemo', N'-- VAT split per line, the way sp_ConfirmOrder rounds the invoice',
                  N'-- 2026-10-01: the GL is all VAT-exempt (client rule): every line goes to the VATEX legs'),
('sp_CreditMemo', N'@nVat   = ISNULL(SUM(CASE WHEN isVat = 1 THEN ROUND((Variance * SellingPrice) / 1.12, 2) END), 0),',
                  N'@nVat   = 0,'),
('sp_CreditMemo', N'@tVat   = ISNULL(SUM(CASE WHEN isVat = 1 THEN ROUND((Variance * SellingPrice) / 1.12 * 0.12, 2) END), 0),',
                  N'@tVat   = 0,'),
('sp_CreditMemo', N'@gVatEx = ISNULL(SUM(CASE WHEN ISNULL(isVat, 0) = 0 THEN ROUND(Variance * SellingPrice, 2) END), 0),',
                  N'@gVatEx = ISNULL(SUM(ROUND(Variance * SellingPrice, 2)), 0),'),
('sp_CreditMemo', N'@cVat   = ISNULL(SUM(CASE WHEN isVat = 1 THEN ROUND(Variance * ISNULL(Cost, 0), 2) END), 0),',
                  N'@cVat   = 0,'),
('sp_CreditMemo', N'@cVatEx = ISNULL(SUM(CASE WHEN ISNULL(isVat, 0) = 0 THEN ROUND(Variance * ISNULL(Cost, 0), 2) END), 0)',
                  N'@cVatEx = ISNULL(SUM(ROUND(Variance * ISNULL(Cost, 0), 2)), 0)'),
('sp_CreditMemo', N'CASE WHEN isVat = 1 THEN @tkVat ELSE @tkVatEx END, @Today',
                  N'@tkVatEx, @Today');

-- sp_ReturnSalesOrder
INSERT #P (ProcName, OldText, NewText) VALUES
('sp_ReturnSalesOrder', N'-- VAT split per line, the way sp_ConfirmOrder rounded the invoice',
                        N'-- 2026-10-01: the GL is all VAT-exempt (client rule): every line goes to the VATEX legs'),
('sp_ReturnSalesOrder', N'@nVat   = ISNULL(SUM(CASE WHEN isVat = 1 THEN ROUND((ActualQty * SellingPrice) / 1.12, 2) END), 0),',
                        N'@nVat   = 0,'),
('sp_ReturnSalesOrder', N'@tVat   = ISNULL(SUM(CASE WHEN isVat = 1 THEN ROUND((ActualQty * SellingPrice) / 1.12 * 0.12, 2) END), 0),',
                        N'@tVat   = 0,'),
('sp_ReturnSalesOrder', N'@gVatEx = ISNULL(SUM(CASE WHEN isVat = 0 THEN ROUND(ActualQty * SellingPrice, 2) END), 0),',
                        N'@gVatEx = ISNULL(SUM(ROUND(ActualQty * SellingPrice, 2)), 0),'),
('sp_ReturnSalesOrder', N'@cVat   = ISNULL(SUM(CASE WHEN isVat = 1 THEN ROUND(ActualQty * Cost, 2) END), 0),',
                        N'@cVat   = 0,'),
('sp_ReturnSalesOrder', N'@cVatEx = ISNULL(SUM(CASE WHEN isVat = 0 THEN ROUND(ActualQty * Cost, 2) END), 0)',
                        N'@cVatEx = ISNULL(SUM(ROUND(ActualQty * Cost, 2)), 0)');

-- spu_STS_SyncInTransit: target all VAT-exempt (posted VAT transit, if any, gets reversed)
INSERT #P (ProcName, OldText, NewText) VALUES
('spu_STS_SyncInTransit', N'SELECT @TargetVat   = ISNULL(SUM(CASE WHEN x.isVat = 1 THEN f.TotalCost END), 0),',
                          N'SELECT @TargetVat   = 0,   -- 2026-10-01: the GL is all VAT-exempt (client rule)'),
('spu_STS_SyncInTransit', N'@TargetVatEx = ISNULL(SUM(CASE WHEN x.isVat = 0 THEN f.TotalCost END), 0)',
                          N'@TargetVatEx = ISNULL(SUM(f.TotalCost), 0)');

-- sp_ConfirmBranchRecievedOrderJFC: receipt and short / over all VAT-exempt
INSERT #P (ProcName, OldText, NewText) VALUES
('sp_ConfirmBranchRecievedOrderJFC', N'SELECT @rcvVat   = ISNULL(SUM(CASE WHEN IsVat = 1 THEN ROUND(Qty * Cost, 2) END), 0),',
                                     N'SELECT @rcvVat   = 0,   -- 2026-10-01: the GL is all VAT-exempt (client rule)'),
('sp_ConfirmBranchRecievedOrderJFC', N'@rcvVatEx = ISNULL(SUM(CASE WHEN ISNULL(IsVat, 0) = 0 THEN ROUND(Qty * Cost, 2) END), 0)',
                                     N'@rcvVatEx = ISNULL(SUM(ROUND(Qty * Cost, 2)), 0)'),
('sp_ConfirmBranchRecievedOrderJFC', N'SELECT @shipVat   = ISNULL(SUM(CASE WHEN ISNULL(dd.isVat, 0) = 1 THEN f.TotalCost END), 0),',
                                     N'SELECT @shipVat   = 0,'),
('sp_ConfirmBranchRecievedOrderJFC', N'@shipVatEx = ISNULL(SUM(CASE WHEN ISNULL(dd.isVat, 0) = 0 THEN f.TotalCost END), 0)',
                                     N'@shipVatEx = ISNULL(SUM(f.TotalCost), 0)');

------------------------------------------------------------------
-- Check every replacement first, then patch each procedure
------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Def') IS NOT NULL DROP TABLE #Def;
SELECT DISTINCT p.ProcName,
       REPLACE(OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + p.ProcName)), NCHAR(13) + NCHAR(10), NCHAR(10)) AS Def
INTO #Def
FROM #P p;

IF EXISTS (SELECT 1 FROM #Def WHERE Def IS NULL)
    THROW 59721, 'A procedure to patch is missing.', 1;

IF EXISTS (SELECT 1 FROM #Def WHERE CHARINDEX(N'2026-10-01: the GL is all VAT-exempt', Def) > 0)
    THROW 59722, 'Already applied (the procedures carry the 2026-10-01 VAT-exempt note).', 1;

IF EXISTS (SELECT 1 FROM #P p INNER JOIN #Def d ON d.ProcName = p.ProcName
           WHERE (DATALENGTH(d.Def) - DATALENGTH(REPLACE(d.Def, p.OldText, N''))) / DATALENGTH(p.OldText) <> 1)
BEGIN
    SELECT p.ProcName, p.OldText,
           (DATALENGTH(d.Def) - DATALENGTH(REPLACE(d.Def, p.OldText, N''))) / DATALENGTH(p.OldText) AS Matches
    FROM #P p INNER JOIN #Def d ON d.ProcName = p.ProcName
    WHERE (DATALENGTH(d.Def) - DATALENGTH(REPLACE(d.Def, p.OldText, N''))) / DATALENGTH(p.OldText) <> 1;
    THROW 59723, 'A procedure''s text differs from the version this script was written for; nothing changed.', 1;
END

IF EXISTS (SELECT 1 FROM #Def WHERE OBJECT_ID(N'dbo.' + ProcName + N'_OLD_10012026210000') IS NOT NULL)
    THROW 59724, 'A backup named <proc>_OLD_10012026210000 already exists.', 1;

BEGIN TRANSACTION;

    DECLARE @name SYSNAME, @def NVARCHAR(MAX), @old NVARCHAR(MAX), @new NVARCHAR(MAX), @bak NVARCHAR(300);
    DECLARE pc CURSOR LOCAL FAST_FORWARD FOR SELECT ProcName, Def FROM #Def ORDER BY ProcName;
    OPEN pc; FETCH NEXT FROM pc INTO @name, @def;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE rc CURSOR LOCAL FAST_FORWARD FOR SELECT OldText, NewText FROM #P WHERE ProcName = @name ORDER BY Id;
        OPEN rc; FETCH NEXT FROM rc INTO @old, @new;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @def = REPLACE(@def, @old, @new);
            FETCH NEXT FROM rc INTO @old, @new;
        END
        CLOSE rc; DEALLOCATE rc;

        SET @bak = N'dbo.' + @name;
        DECLARE @newName SYSNAME = @name + N'_OLD_10012026210000';
        EXEC sp_rename @bak, @newName;
        EXEC (@def);
        PRINT 'patched ' + @name;

        FETCH NEXT FROM pc INTO @name, @def;
    END
    CLOSE pc; DEALLOCATE pc;

COMMIT TRANSACTION;

SELECT name, CONVERT(VARCHAR(19), modify_date, 120) AS modified
FROM sys.objects
WHERE name IN (SELECT ProcName FROM #Def) OR name IN (SELECT ProcName + '_OLD_10012026210000' FROM #Def)
ORDER BY name;
