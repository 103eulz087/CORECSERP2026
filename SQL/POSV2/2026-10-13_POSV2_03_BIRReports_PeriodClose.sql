/* ================================================================
   POS V2 phase 5 (2026-10-13) - 03: BIR reports include POS V2; no GL month close over open POS shifts
   ================================================================
   Needs 01 + 02 (fn_POSV2_ZReadings, POSV2_Shift). Anchor patches of existing shared procs, same parameters and
   same result columns; backups _OLD_10132026120000. Nothing changes for the old POS: its rows are read as before,
   and POS V2 adds its own rows (none until a terminal sells).

     * spr_ESalesDetails (E-Sales report, BIR2550M / POSSalesReportSummary screens): one more row per POS V2
       Z-reading (closed shift) of the branch and period: VAT-exempt, VATable (with VAT), net of VAT, VAT, OR range,
       number of ORs. Shift = sales less the returns it paid back, split by the original line's VAT.
     * spr_POSSalesReportSummary / spr_POSSalesReportSummary2 (POS Sales Summary; 2550M through
       spr_SalesReportSummary2): POS V2 machines summed per branch / machine next to the old ones. The machine is
       the terminal's BIRMachine (its POSInfoDetails row: TIN, MIN), else its terminal code; a terminal not yet linked
       to POSInfoDetails is still listed (TIN / MIN blank) so no sale is left out of the BIR totals.
     * spr_SalesReportSummary (the older BIR2550M screen, still on the menu; one row per branch): POS V2 added to
       each branch's VAT-exempt / VATable / net of VAT / VAT.
     * spu_GLPeriod_Close: a month can't be closed while a POS V2 shift of it (or earlier) is still open or its GL
       ticket isn't booked (59908): closing first would leave that shift's sales out of a closed month for good.
       Nor while a terminal used in the month hasn't connected since it ended (59909): it may hold offline sales.
       Limit: a terminal that was offline for the WHOLE month (never seen in it) isn't known to have sold; its
       shift then reaches a closed month and its GL fails (59900, listed in POS V2 Needs attention).

   How POS V2 is counted (same as the old POS's Z-readings): one row per closed shift, on its BusinessDate (the day
   it opened; a shift that crossed midnight counts whole on that day, while the POS V2 sales journal lists each OR by
   its own date). Sales less the returns paid back in the shift, split by the original line's VAT; voided sales are
   out, but their ORs are in the OR range and the number of transactions (an OR series counts every OR issued).
   POS V2 has no zero-rated lines. A day with more returns than sales shows negative figures (the month sums right).

   One transaction with a post-check. Run on DEV first, then STAGING / production with 01 + 02.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
IF OBJECT_ID('dbo.fn_POSV2_ZReadings', 'IF') IS NULL OR OBJECT_ID('dbo.POSV2_Shift', 'U') IS NULL
    THROW 61000, 'Run SQL/POSV2/2026-10-12_POSV2_01_Types.sql and _02_Server.sql first.', 1;
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
    DECLARE @old SYSNAME = @Obj + N'_OLD_10132026120000', @full NVARCHAR(300) = N'dbo.' + @Obj;
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
IF OBJECT_ID('dbo.spr_ESalesDetails_OLD_10132026120000', 'P') IS NOT NULL
BEGIN
    RAISERROR('This script has been run here before (spr_ESalesDetails_OLD_10132026120000 exists).', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

DECLARE @LF NCHAR(1) = NCHAR(10);

-- E-Sales: one row per POS V2 Z-reading of the branch (inserted before the existing final SELECT)
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'spr_ESalesDetails', N'set nocount off',
    N'-- POS V2 (2026-10-13): its Z-readings (closed shifts, sales less returns), one row each' + @LF +
    N'insert into #tempsalesdetails (BranchCode, BranchName, MachineName, SalesDate, TotalVatExemptSales, TotalVatSales, TotalSalesNetOfVat, TotalVat, BeginningOR, EndingOR, NumberOfTransactions)' + @LF +
    N'select z.BranchCode, LEFT(b.BranchName, 40), LEFT(z.MachineUsed, 30), z.DateExecute,' + @LF +
    N'       z.VatExemptSale + z.ZeroRatedSale, z.VatableSale + z.VatInput, z.VatableSale, z.VatInput,' + @LF +
    N'       LEFT(ISNULL(z.BeginningSINo, '' ''), 20), LEFT(ISNULL(z.EndingSINo, '' ''), 20), ISNULL(z.SaleCount, 0)' + @LF +
    N'from dbo.fn_POSV2_ZReadings(@parmdatefrom, @parmdateto) as z' + @LF +
    N'inner join Branches as b on b.BranchCode = z.BranchCode' + @LF +
    N'where z.BranchCode = @parmbranchcode' + @LF + @LF +
    N'set nocount off');
EXEC #ApplyPatch N'spr_ESalesDetails';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

DECLARE @LF NCHAR(1) = NCHAR(10);
DECLARE @block NVARCHAR(MAX) =
    N'-- POS V2 (2026-10-13): its machines, summed per branch / machine (LEFT JOIN POSInfoDetails: a terminal not yet' + @LF +
    N'-- linked to its BIR registration is listed with TIN / MIN blank rather than left out of the totals)' + @LF +
    N'insert into #salesrep (BranchCode, BranchName, POSName, TinNo, MINNo, LastOR, TotalVatExemptSales, TotalVatSales, TotalSalesNetOfVat, TotalVat)' + @LF +
    N'select z.BranchCode, LEFT(b.BranchName, 40), LEFT(z.MachineUsed, 30), LEFT(c.TINNo, 30), LEFT(c.MINNo, 30), LEFT(MAX(z.EndingSINo), 30),' + @LF +
    N'       SUM(z.VatExemptSale + z.ZeroRatedSale), SUM(z.VatableSale + z.VatInput), SUM(z.VatableSale), SUM(z.VatInput)' + @LF +
    N'from dbo.fn_POSV2_ZReadings(@parmdatefrom, @parmdateto) as z' + @LF +
    N'inner join Branches as b on b.BranchCode = z.BranchCode' + @LF +
    N'outer apply (select top 1 i.TINNo, i.MINNo from POSInfoDetails as i where i.BranchCode = z.BranchCode and i.MachineUsed = z.MachineUsed' + @LF +
    N'             order by i.DatePermitEnd desc, i.DateIssued desc) as c' + @LF +
    N'group by z.BranchCode, b.BranchName, z.MachineUsed, c.TINNo, c.MINNo' + @LF + @LF +
    N'set nocount off';
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'spr_POSSalesReportSummary', N'set nocount off', @block);
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'spr_POSSalesReportSummary2', N'set nocount off', @block);
EXEC #ApplyPatch N'spr_POSSalesReportSummary';
EXEC #ApplyPatch N'spr_POSSalesReportSummary2';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- 2550M (the older BIR2550M screen, still on the menu): every branch's row gets its POS V2 Z-readings added
DECLARE @LF NCHAR(1) = NCHAR(10);
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'spr_SalesReportSummary', N'set nocount off',
    N'-- POS V2 (2026-10-13): its Z-readings (closed shifts, sales less returns) added to each branch' + @LF +
    N'update r set TotalVatExemptSales = r.TotalVatExemptSales + z.Exempt, TotalVatSales = r.TotalVatSales + z.VatGross,' + @LF +
    N'             TotalSalesNetOfVat = r.TotalSalesNetOfVat + z.Vatable, TotalVat = r.TotalVat + z.Vat' + @LF +
    N'from #salesrep as r' + @LF +
    N'inner join (select BranchCode, sum(VatExemptSale + ZeroRatedSale) as Exempt, sum(VatableSale + VatInput) as VatGross,' + @LF +
    N'                   sum(VatableSale) as Vatable, sum(VatInput) as Vat' + @LF +
    N'            from dbo.fn_POSV2_ZReadings(@parmdatefrom, @parmdateto) group by BranchCode) as z' + @LF +
    N'  on z.BranchCode = r.BranchCode collate database_default' + @LF + @LF +
    N'set nocount off');
EXEC #ApplyPatch N'spr_SalesReportSummary';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

DECLARE @LF NCHAR(1) = NCHAR(10);
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'spu_GLPeriod_Close',
    N'        UPDATE dbo.GLPeriodLock' + @LF + N'        SET LockedThroughDate = @PeriodEnd',
    N'        -- POS V2 (2026-10-13): its sales reach the GL when a shift closes (one ticket per shift). A month with a shift' + @LF +
    N'        -- still open, or closed but not yet booked (GLStatus PENDING / FAILED), would lose those sales for good.' + @LF +
    N'        -- The read is locked (UPDLOCK, HOLDLOCK) so a shift can''t open into the month while it closes.' + @LF +
    N'        IF EXISTS (SELECT 1 FROM dbo.POSV2_Shift WITH (UPDLOCK, HOLDLOCK) WHERE BusinessDate <= @PeriodEnd AND (Status = ''OPEN'' OR GLStatus <> ''POSTED''))' + @LF +
    N'        BEGIN' + @LF +
    N'            SET @msg = N''POS V2 shifts of this month (or earlier) are still open or their GL is not booked: close them'' +' + @LF +
    N'                       N'' (Z-reading) and let their GL post first (POS V2 reports, Needs attention). A shift whose terminal'' +' + @LF +
    N'                       N'' is lost or reinstalled can be closed by an admin with dbo.spu_POSV2_ForceCloseShift.'';' + @LF +
    N'            THROW 59908, @msg, 1;' + @LF +
    N'        END' + @LF +
    N'        -- A terminal used in this month that hasn''t reached the server since it ended may still hold sales of the month' + @LF +
    N'        -- (offline). Connect it first; a terminal no longer used is deactivated (POSV2_Terminal.IsActive = 0).' + @LF +
    N'        DECLARE @posv2Dark NVARCHAR(400) = STUFF((SELECT TOP 10 N'', '' + t.BranchCode + N''/'' + t.TerminalCode' + @LF +
    N'            FROM dbo.POSV2_Terminal AS t' + @LF +
    N'            WHERE t.IsActive = 1 AND t.LastSeenAt >= DATEADD(DAY, 1, EOMONTH(@PeriodEnd, -1)) AND t.LastSeenAt < DATEADD(DAY, 1, @PeriodEnd)' + @LF +
    N'            ORDER BY t.BranchCode, t.TerminalCode FOR XML PATH(''''), TYPE).value(''.'', ''NVARCHAR(400)''), 1, 2, N'''');' + @LF +
    N'        IF @posv2Dark IS NOT NULL' + @LF +
    N'        BEGIN' + @LF +
    N'            SET @msg = N''POS V2 terminals used this month have not connected to the server since it ended, so they may still'' +' + @LF +
    N'                       N'' hold sales of the month: '' + @posv2Dark + N''. Connect them first (or deactivate one no longer used).'';' + @LF +
    N'            THROW 59909, @msg, 1;' + @LF +
    N'        END' + @LF + @LF +
    N'        UPDATE dbo.GLPeriodLock' + @LF + N'        SET LockedThroughDate = @PeriodEnd');
EXEC #ApplyPatch N'spu_GLPeriod_Close';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

IF OBJECT_ID('dbo.spr_ESalesDetails', 'P') IS NULL OR OBJECT_ID('dbo.spr_POSSalesReportSummary', 'P') IS NULL
   OR OBJECT_ID('dbo.spr_POSSalesReportSummary2', 'P') IS NULL OR OBJECT_ID('dbo.spu_GLPeriod_Close', 'P') IS NULL
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.spr_ESalesDetails')) NOT LIKE '%fn_POSV2_ZReadings%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.spr_POSSalesReportSummary')) NOT LIKE '%fn_POSV2_ZReadings%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.spr_POSSalesReportSummary2')) NOT LIKE '%fn_POSV2_ZReadings%'
   OR OBJECT_ID('dbo.spr_SalesReportSummary', 'P') IS NULL
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.spr_SalesReportSummary')) NOT LIKE '%fn_POSV2_ZReadings%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.spu_GLPeriod_Close')) NOT LIKE '%59908%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.spu_GLPeriod_Close')) NOT LIKE '%59909%'
BEGIN
    RAISERROR('Post-check failed; rolled back.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
COMMIT TRANSACTION;
PRINT 'POS V2 BIR reports + GL period close guard installed.';
GO
SET NOEXEC OFF;
GO
