/* ================================================================
   2026-10-13b - Conversion Per Barcode: Conversion Date (like the Sales Order effectivity date)
   ================================================================
   Why (user, 2026-10-13): staff are catching up last month's conversions (parallel run), but the
   conversion was always dated the day it was keyed, and the Finalize GL ticket the day it was finalized.

   Rule (same as Sales Order: EffectivityDate dates the GL ticket, audit stamps stay "now"):
     * ConversionBarcodeSummary.DateConverted = the conversion date picked on the screen (+ the time of day
       it was keyed, so lists stay in keying order within a day). Every report already filters / sorts on it
       (sp_rpt_ConversionReport_Master / _Source / _Output, sp_rpt_ItemCostingReport_Detail, the Posted tab),
       so they follow the picked date with no change.
     * New column DateEntered = when it was really keyed (audit). Backfilled = DateConverted for old rows.
     * The output lots' Inventory.DateReceived = the conversion date (Item Costing dates lots by it).
     * spu_FinalizeConversionBarcode: the CONV-FINALIZE ticket (TicketMaster + TicketDetails TicketDate) is
       dated with the conversion date, not the finalize day. DateFinalized stays "now" (audit).
     * Unchanged "now": source lots' LastMovementDate, DateReversed, DateFinalized.

   spu_PostConversionBarcode gets an optional @DateConversion DATE = NULL (last parameter): NULL = today, so an
   old exe works unchanged. Refused: a future date (59217); a date in a month closed in GLPeriodLock (59218),
   checked at Submit so staff learn it before Finalize (the lock trigger would refuse the ticket anyway, 59900).

   Anchor patches on the live text (nothing changes if the text differs); backups _OLD_10132026180000.
   One transaction with a post-check. Run on DEV, then STAGING (user's go), then PRODUCTION (user).
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
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
    DECLARE @old SYSNAME = @Obj + N'_OLD_10132026180000', @full NVARCHAR(300) = N'dbo.' + @Obj;
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
IF OBJECT_ID('dbo.spu_PostConversionBarcode_OLD_10132026180000', 'P') IS NOT NULL OR COL_LENGTH('dbo.ConversionBarcodeSummary', 'DateEntered') IS NOT NULL
BEGIN
    RAISERROR('This script has been run here before (spu_PostConversionBarcode_OLD_10132026180000 or ConversionBarcodeSummary.DateEntered exists).', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── 1. audit column: when the conversion was really keyed ────────────
ALTER TABLE dbo.ConversionBarcodeSummary ADD DateEntered DATETIME NULL;
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
UPDATE dbo.ConversionBarcodeSummary SET DateEntered = DateConverted WHERE DateEntered IS NULL;
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── 2. the summary view lists it (last column, so SELECT-list callers are unaffected) ──
ALTER VIEW dbo.vw_ConversionBarcodeSummary
AS
SELECT
    ConversionRefNo,
    BranchCode,
    ConversionType,
    TotalSourceQty,
    TotalSourceCost,
    CuttingCharge,
    TotalDriplossQty,
    CostBasisQty,
    MaterialRatePerUnit,
    ChargeRatePerLine,
    Status,
    DateConverted,
    ConvertedBy,
    ReversedBy,
    DateReversed,
    FinalizedBy,
    DateFinalized,
    Remarks,
    DateEntered
FROM dbo.ConversionBarcodeSummary;
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── 3. Submit: the conversion date ───────────────────────────────────
DECLARE @LF NCHAR(1) = NCHAR(10);
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'spu_PostConversionBarcode',
    N'    @OutputLines     dbo.tt_ConversionBarcodeOutputLines READONLY' + @LF + N'AS',
    N'    @OutputLines     dbo.tt_ConversionBarcodeOutputLines READONLY,' + @LF +
    N'    @DateConversion  DATE = NULL   -- 2026-10-13b: the conversion date picked on the screen (NULL = today, old exe)' + @LF +
    N'AS');
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'spu_PostConversionBarcode',
    N'        IF @ConversionType NOT IN (''OneToMany'', ''ManyToOne'')',
    N'        -- 2026-10-13b: conversion date = DateConverted (+ the time keyed) and the output lots'' DateReceived;' + @LF +
    N'        -- the Finalize ticket is dated with it. Not in the future, not in a month closed in the GL.' + @LF +
    N'        IF @DateConversion IS NULL SET @DateConversion = CAST(GETDATE() AS DATE);' + @LF +
    N'        IF @DateConversion > CAST(GETDATE() AS DATE)' + @LF +
    N'            THROW 59217, ''The conversion date cannot be in the future.'', 1;' + @LF +
    N'        DECLARE @GLLockedThrough DATE = (SELECT MAX(LockedThroughDate) FROM dbo.GLPeriodLock);' + @LF +
    N'        IF @GLLockedThrough IS NOT NULL AND @DateConversion <= @GLLockedThrough' + @LF +
    N'        BEGIN' + @LF +
    N'            DECLARE @GLLockMsg NVARCHAR(300) = N''The conversion date is in a month already closed in the GL (closed through '' +' + @LF +
    N'                CONVERT(NVARCHAR(10), @GLLockedThrough, 120) + N''). Pick a date in an open month, or ask an admin to reopen it.'';' + @LF +
    N'            THROW 59218, @GLLockMsg, 1;' + @LF +
    N'        END' + @LF +
    N'        DECLARE @ConvDateTime DATETIME = DATEADD(DAY, DATEDIFF(DAY, 0, @DateConversion), CAST(CAST(GETDATE() AS TIME) AS DATETIME));' + @LF +
    N'' + @LF +
    N'        IF @ConversionType NOT IN (''OneToMany'', ''ManyToOne'')');
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'spu_PostConversionBarcode',
    N'             Status, DateConverted, ConvertedBy)',
    N'             Status, DateConverted, ConvertedBy, DateEntered)');
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'spu_PostConversionBarcode',
    N'             ''FOR POSTING'', GETDATE(), @ConvertedBy);',
    N'             ''FOR POSTING'', @ConvDateTime, @ConvertedBy, GETDATE());');
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'spu_PostConversionBarcode',
    N'                (@BranchCode, ''CONVERSION'', 0, 0, GETDATE(), NULL, @outProduct, @outDesc, @newBarcode,',
    N'                (@BranchCode, ''CONVERSION'', 0, 0, @ConvDateTime, NULL, @outProduct, @outDesc, @newBarcode,');
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'spu_PostConversionBarcode';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── 4. Finalize: the ticket is dated with the conversion date ────────
DECLARE @LF NCHAR(1) = NCHAR(10);
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'spu_FinalizeConversionBarcode',
    N'        DECLARE @TicketNo BIGINT;',
    N'        -- 2026-10-13b: the GL ticket is dated with the conversion date (like a Sales Order''s effectivity date)' + @LF +
    N'        DECLARE @TicketDate DATE = (SELECT CAST(DateConverted AS DATE) FROM dbo.ConversionBarcodeSummary WHERE ConversionRefNo = @ConversionRefNo);' + @LF +
    N'        SET @TicketDate = ISNULL(@TicketDate, CAST(GETDATE() AS DATE));' + @LF +
    N'' + @LF +
    N'        DECLARE @TicketNo BIGINT;');
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'spu_FinalizeConversionBarcode',
    N'            GETDATE(), 0, @BranchCode, @BranchCode,',
    N'            @TicketDate, 0, @BranchCode, @BranchCode,');
INSERT INTO #Patch (Obj, OldText, NewText) VALUES (N'spu_FinalizeConversionBarcode',
    N'            GETDATE(), 0, @BranchCode, @ConversionRefNo,',
    N'            @TicketDate, 0, @BranchCode, @ConversionRefNo,');
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'spu_FinalizeConversionBarcode';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── post-check ───────────────────────────────────────────────────────
IF OBJECT_DEFINITION(OBJECT_ID('dbo.spu_PostConversionBarcode')) NOT LIKE '%@DateConversion  DATE = NULL%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.spu_PostConversionBarcode')) NOT LIKE '%''FOR POSTING'', @ConvDateTime, @ConvertedBy, GETDATE());%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.spu_PostConversionBarcode')) NOT LIKE '%''CONVERSION'', 0, 0, @ConvDateTime, NULL,%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.spu_FinalizeConversionBarcode')) NOT LIKE '%@TicketDate, 0, @BranchCode, @BranchCode,%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.spu_FinalizeConversionBarcode')) NOT LIKE '%@TicketDate, 0, @BranchCode, @ConversionRefNo,%'
   OR OBJECT_ID('dbo.spu_PostConversionBarcode_OLD_10132026180000', 'P') IS NULL
   OR OBJECT_ID('dbo.spu_FinalizeConversionBarcode_OLD_10132026180000', 'P') IS NULL
   OR COL_LENGTH('dbo.vw_ConversionBarcodeSummary', 'DateEntered') IS NULL
   OR EXISTS (SELECT 1 FROM dbo.ConversionBarcodeSummary WHERE DateEntered IS NULL)
BEGIN
    RAISERROR('Post-check failed; nothing was changed.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
SET NOEXEC OFF;
PRINT 'Conversion Date installed (backups *_OLD_10132026180000).';
GO
