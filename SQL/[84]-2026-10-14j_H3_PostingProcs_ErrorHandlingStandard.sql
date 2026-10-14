/* ================================================================
   [84] 2026-10-14 - Hardening H3: one error-handling pattern for the posting procs (standard docs/standards/2026-10-14_Posting_Proc_Error_Handling.md)
   ================================================================
   Handoff docs/handoff/2026-10-14_Hardening_Handoff_to_Fable.md, item H3 (user's go 2026-10-14). Needs [83] (the two supplier
   payment procs carry its marker). Anchor patches of the live text; every anchor must occur exactly once, else nothing changes.
   What was wrong, proved on DEV before this script:
     - sp_AddPaymentSupplierCompound_V2 / sp_AddPaymentSupplierCompound: named transaction; inside an outer transaction (the
       wrapper sp_PostSupplierPaymentWithManualLines, a screen's SqlTransaction) every refusal surfaced as 6401 "Cannot roll back
       PaySupplierV2" and left the outer transaction doomed.                      -> unnamed BEGIN / COMMIT / ROLLBACK TRANSACTION
     - sp_AddPaymentClient (15 guards) / sp_ReversePaymentClient (2): no TRY/CATCH, each guard did ROLLBACK; THROW, which rolls
       back the caller's transaction too.                                        -> TRY / CATCH, guards THROW only, CATCH rolls back
     - SP_CONFIRMPO: NOT converted: its 2019 text no longer compiles (213, a positional INSERT vs a table that gained a column),
       so the screen (VIEWPO > CONFIRMPO) fails before writing anything; SERVICESCOST is empty on every tier. Retire it.
     - SP_POSTINVENTORY and sp_FinalizeInventoryUpload: the shipment's Inventory rows were DELETED and rebuilt from the temp table
       BEFORE the transaction opened and before the "already finalized" check; a repeated call on a finalized shipment wiped the
       live lots (Available back to 0, STS copies at other branches deleted) and then refused, with that damage committed. The
       temp rows are never flagged processed (3,157 rows at isProcess = 0 on DEV), so every finalized shipment was exposed.
                                                                                     -> BEGIN TRANSACTION is the first statement of the TRY;
                                                                                        the two RAISERROR + RETURN become THROW 50061 / 50062;
                                                                                        SP_POSTINVENTORY's CATCH re-throws the real error
                                                                                        (it re-raised everything as 50000)
     - sp_PostCompoundTicket / sp_PostCompoundTicketSales ([83]): the CATCH ran DROP TABLE IF EXISTS #Legs inside the doomed
       transaction, and that DDL raised 3930 "The current transaction cannot be committed" over the real error: a payment
       posted into a closed month showed 3930 instead of 59900.                     -> the CATCH only re-throws (the temp table drops itself)
     - SP_UPLOADINVENTORY: not converted, no caller left (UPLOADINVENTORY.cs calls sp_FinalizeInventoryUpload).
   Behaviour on the success path is unchanged for every proc (old vs new compared row by row on DEV). Backups _OLD_10142026235900.
   One transaction; a failure rolls everything back. No exe change.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF CHARINDEX('[84]', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentClient'))) > 0
BEGIN
    RAISERROR('[84] already applied here; nothing to do.', 16, 1);
    SET NOEXEC ON;
END
ELSE
BEGIN
    DECLARE @bad NVARCHAR(400) = N'';
    DECLARE @Exp TABLE (Obj SYSNAME, Hash VARCHAR(66));
    INSERT INTO @Exp VALUES
        ('sp_AddPaymentSupplierCompound_V2', '0x82486BAE101C16F6B9D62ABF838382B49BD8E1B4F7A9BFC6068D41370380598B'),
        ('sp_AddPaymentSupplierCompound',    '0x1CC0AEB5BB1E865469BD9DD34D835658F2A73C91039CFD67C9DE365DA649E488'),
        ('sp_AddPaymentClient',              '0xA5F38220E79510277FC249D0AEDE0F5F1D0D2C22B90BB0DC2C6737A1C5D29A73'),
        ('sp_ReversePaymentClient',          '0xC51DBD085A7BBB6F857A3A862816746CF1F4C0BEC1ED251F8950D3B9BD09A61D'),
        ('SP_POSTINVENTORY',                 '0x88F9FA7C47E92C077B2F6737716F7509E045019A0D73D5D0666374B29A650F9D'),
        ('sp_FinalizeInventoryUpload',       '0x1DD26360FE6D39FA84AD39F02E08D50481B3168EE02A4B03C3799555DED66569'),
        ('sp_PostCompoundTicket',            '0xDECB4F5F6AD045602BEE7B2FBA8F55F6116CCF50CD328B73A6DD08999BCC57E8'),
        ('sp_PostCompoundTicketSales',       '0x60D7F4724BD6E63E1D0C9B16A3A1A1B4232833BE05A641952DFA20D7A030AD3A');
    SELECT @bad = @bad + e.Obj + N' '
    FROM @Exp e
    WHERE ISNULL(CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.' + e.Obj)), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 1), '') <> e.Hash;
    IF @bad <> N'' OR EXISTS (SELECT 1 FROM sys.objects WHERE name LIKE '%[_]OLD[_]10142026235900')
    BEGIN
        SET @bad = N'[84] stopped, nothing changed: not the expected 2026-10-14 text (run [83] first on this database): ' + @bad + N'; or a [84] backup already exists.';
        RAISERROR(@bad, 16, 1);
        SET NOEXEC ON;
    END
END
GO

BEGIN TRANSACTION;
GO

BEGIN TRY
    DECLARE @Patch TABLE (Obj SYSNAME, Ord INT, Anchor NVARCHAR(600), Repl NVARCHAR(MAX));
    -- {NL} = the object's own line ending, {TAB} = a tab
    INSERT INTO @Patch (Obj, Ord, Anchor, Repl) VALUES
    -- 1. V2: unnamed transaction
    (N'sp_AddPaymentSupplierCompound_V2', 1, N'BEGIN TRANSACTION PaySupplierV2;', N'BEGIN TRANSACTION;   -- [84] unnamed: a named ROLLBACK fails with 6401 when this proc runs inside an outer transaction'),
    (N'sp_AddPaymentSupplierCompound_V2', 2, N'COMMIT TRANSACTION PaySupplierV2;', N'COMMIT TRANSACTION;'),
    (N'sp_AddPaymentSupplierCompound_V2', 3, N'IF XACT_STATE() <> 0 ROLLBACK TRANSACTION PaySupplierV2;', N'IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;'),
    -- 2. old Compound: unnamed transaction
    (N'sp_AddPaymentSupplierCompound', 1, N'BEGIN TRANSACTION PaySupplier;', N'BEGIN TRANSACTION;   -- [84] unnamed: a named ROLLBACK fails with 6401 when this proc runs inside an outer transaction'),
    (N'sp_AddPaymentSupplierCompound', 2, N'COMMIT TRANSACTION PaySupplier;', N'COMMIT TRANSACTION;'),
    (N'sp_AddPaymentSupplierCompound', 3, N'IF XACT_STATE() <> 0 ROLLBACK TRANSACTION PaySupplier;', N'IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;'),
    -- 3. sp_AddPaymentClient: TRY / CATCH around the body (the guard ROLLBACKs are removed below)
    (N'sp_AddPaymentClient', 1, N'    BEGIN TRAN;', N'    BEGIN TRAN;{NL}    BEGIN TRY   -- [84] guards THROW only; the CATCH rolls back'),
    (N'sp_AddPaymentClient', 2, N'    COMMIT;{NL}END', N'    COMMIT;{NL}    END TRY{NL}    BEGIN CATCH{NL}        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;   -- [84]{NL}        THROW;{NL}    END CATCH{NL}END'),
    -- 4. sp_ReversePaymentClient: same
    (N'sp_ReversePaymentClient', 1, N'    BEGIN TRAN;', N'    BEGIN TRAN;{NL}    BEGIN TRY   -- [84] guards THROW only; the CATCH rolls back'),
    (N'sp_ReversePaymentClient', 2, N'    COMMIT;{NL}END', N'    COMMIT;{NL}    END TRY{NL}    BEGIN CATCH{NL}        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;   -- [84]{NL}        THROW;{NL}    END CATCH{NL}END'),
    -- 5. SP_CONFIRMPO: NOT converted. Its 2019 text no longer compiles (213: a positional INSERT vs a table that gained a column), so the screen fails before writing anything; SERVICESCOST is empty on every tier. Candidate to retire.
    -- 6. SP_POSTINVENTORY: transaction first, THROW instead of RAISERROR + RETURN, real error re-thrown
    (N'SP_POSTINVENTORY', 1, N'        BEGIN TRANSACTION;', N'        -- [84] the transaction is opened at the top of the TRY block (it used to open here, after the Inventory rebuild)'),
    (N'SP_POSTINVENTORY', 2, N'--BEGIN TRAN;', N'BEGIN TRANSACTION;   -- [84] first statement of the TRY: the Inventory rebuild below is part of it'),
    (N'SP_POSTINVENTORY', 3, N'RAISERROR(''Shipment %s / Supplier %s has already been finalized.'', 16, 1, @ShipmentNo, @SupplierID);{NL}            RETURN;',
                              N'DECLARE @m61 NVARCHAR(400) = N''Shipment '' + ISNULL(@ShipmentNo, N'''') + N'' / Supplier '' + ISNULL(@SupplierID, N'''') + N'' has already been finalized. Nothing was changed.'';{NL}            THROW 50061, @m61, 1;   -- [84]'),
    (N'SP_POSTINVENTORY', 4, N'RAISERROR(''No POSUMMARY Purchase row found for ShipmentNo %s / SupplierID %s.'', 16, 1, @ShipmentNo, @SupplierID);{NL}            RETURN;',
                              N'DECLARE @m62 NVARCHAR(400) = N''No POSUMMARY purchase row found for shipment '' + ISNULL(@ShipmentNo, N'''') + N'' / supplier '' + ISNULL(@SupplierID, N'''') + N''. Nothing was changed.'';{NL}            THROW 50062, @m62, 1;   -- [84]'),
    (N'SP_POSTINVENTORY', 5, N'RAISERROR(''SP_POSTINVENTORY failed. %s (Err %d, Line %d, State %d)'',{NL}                  @ErrSev, 1, @ErrMsg, @ErrNum, @ErrLine, @ErrSta);', N'THROW;   -- [84] the original error (it was re-raised as 50000)'),
    -- 7. sp_FinalizeInventoryUpload: transaction first, THROW instead of RAISERROR + RETURN (its CATCH already re-throws)
    (N'sp_FinalizeInventoryUpload', 1, N'        BEGIN TRANSACTION;', N'        -- [84] the transaction is opened at the top of the TRY block (it used to open here, after the Inventory rebuild)'),
    (N'sp_FinalizeInventoryUpload', 2, N'{TAB}DELETE FROM Inventory WHERE ShipmentNo=@ShipmentNo', N'        BEGIN TRANSACTION;   -- [84] first statement of the TRY (only comments precede this line): the Inventory rebuild below is part of it{NL}{TAB}DELETE FROM Inventory WHERE ShipmentNo=@ShipmentNo'),
    (N'sp_FinalizeInventoryUpload', 3, N'RAISERROR(''Shipment %s / Supplier %s has already been finalized.'', 16, 1, @ShipmentNo, @SupplierID);{NL}            RETURN;',
                                        N'DECLARE @m61 NVARCHAR(400) = N''Shipment '' + ISNULL(@ShipmentNo, N'''') + N'' / Supplier '' + ISNULL(@SupplierID, N'''') + N'' has already been finalized. Nothing was changed.'';{NL}            THROW 50061, @m61, 1;   -- [84]'),
    (N'sp_FinalizeInventoryUpload', 4, N'RAISERROR(''No POSUMMARY Purchase row found for ShipmentNo %s / SupplierID %s.'', 16, 1, @ShipmentNo, @SupplierID);{NL}            RETURN;',
                                        N'DECLARE @m62 NVARCHAR(400) = N''No POSUMMARY purchase row found for shipment '' + ISNULL(@ShipmentNo, N'''') + N'' / supplier '' + ISNULL(@SupplierID, N'''') + N''. Nothing was changed.'';{NL}            THROW 50062, @m62, 1;   -- [84]'),
    -- 8. the two ticket writers ([83]): no DDL in the CATCH. DROP TABLE inside the doomed transaction raised 3930 over the real error
    --    (a closed month, 59900, reached the screen as "The current transaction cannot be committed"); a proc-scoped temp table drops itself.
    (N'sp_PostCompoundTicket', 1, N'        DROP TABLE IF EXISTS #Legs;{NL}        THROW;   -- [83] the real error, not 50050 ''ERROR SP''',
                                  N'        THROW;   -- [83] the real error, not 50050 ''ERROR SP''; [84] no DROP here: DDL in a doomed transaction raised 3930 over it (#Legs drops itself)'),
    (N'sp_PostCompoundTicketSales', 1, N'        DROP TABLE IF EXISTS #Legs;{NL}        -- Re-throw the ORIGINAL error, not a generic one.{NL}        THROW;',
                                       N'        -- Re-throw the ORIGINAL error, not a generic one. [84] no DROP here: DDL in a doomed transaction raised 3930 over it (#Legs drops itself){NL}        THROW;');

    DECLARE @obj SYSNAME, @def NVARCHAR(MAX), @msg NVARCHAR(400), @a NVARCHAR(600), @r NVARCHAR(MAX), @cnt INT, @bak SYSNAME, @nl NVARCHAR(2), @before INT;
    DECLARE objs CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT Obj FROM @Patch;
    OPEN objs;
    FETCH NEXT FROM objs INTO @obj;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @def = OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + @obj));
        IF @def IS NULL BEGIN SET @msg = N'[84] ' + @obj + N' is missing here.'; THROW 59985, @msg, 1; END
        SET @nl = CASE WHEN CHARINDEX(CHAR(13) + CHAR(10), @def) > 0 THEN CHAR(13) + CHAR(10) ELSE CHAR(10) END;

        DECLARE pt CURSOR LOCAL FAST_FORWARD FOR SELECT Anchor, Repl FROM @Patch WHERE Obj = @obj ORDER BY Ord;
        OPEN pt;
        FETCH NEXT FROM pt INTO @a, @r;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @a = REPLACE(REPLACE(@a, N'{NL}', @nl), N'{TAB}', CHAR(9));
            SET @r = REPLACE(REPLACE(@r, N'{NL}', @nl), N'{TAB}', CHAR(9));
            SET @cnt = (LEN(@def) - LEN(REPLACE(@def, @a, N''))) / LEN(@a);
            IF @cnt <> 1 BEGIN SET @msg = N'[84] ' + @obj + N': anchor found ' + CAST(@cnt AS NVARCHAR(10)) + N' times (expected 1): ' + LEFT(REPLACE(@a, @nl, N'¶'), 120); THROW 59985, @msg, 1; END
            SET @def = REPLACE(@def, @a, @r);
            FETCH NEXT FROM pt INTO @a, @r;
        END
        CLOSE pt; DEALLOCATE pt;

        -- the AR procs: every guard's "ROLLBACK;" line goes (the CATCH rolls back); 15 in sp_AddPaymentClient, 2 in sp_ReversePaymentClient
        IF @obj IN (N'sp_AddPaymentClient', N'sp_ReversePaymentClient')
        BEGIN
            SET @before = (LEN(@def) - LEN(REPLACE(@def, N'ROLLBACK;', N''))) / 9;
            SET @def = REPLACE(@def, @nl + N'            ROLLBACK;', N'');
            SET @def = REPLACE(@def, @nl + N'        ROLLBACK;', N'');
            IF CHARINDEX(N'ROLLBACK;', @def) > 0 OR @before <> CASE WHEN @obj = N'sp_AddPaymentClient' THEN 15 ELSE 2 END
            BEGIN SET @msg = N'[84] ' + @obj + N': guard ROLLBACKs not as expected (' + CAST(@before AS NVARCHAR(10)) + N' found).'; THROW 59985, @msg, 1; END
        END

        IF CHARINDEX(N'[84]', @def) = 0 BEGIN SET @msg = N'[84] ' + @obj + N': marker missing after patching.'; THROW 59985, @msg, 1; END
        SET @bak = @obj + N'_OLD_10142026235900';
        SET @a = N'dbo.' + @obj;
        EXEC sp_rename @a, @bak;
        EXEC (@def);
        PRINT N'[84] ' + @obj + N': patched (backup ' + @bak + N').';
        FETCH NEXT FROM objs INTO @obj;
    END
    CLOSE objs; DEALLOCATE objs;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @em NVARCHAR(2048) = N'[84] stopped, nothing changed (while patching ' + ISNULL(@obj, N'?') + N'): ' + ERROR_MESSAGE();
    RAISERROR(@em, 16, 1);
    SET NOEXEC ON;
END CATCH
GO

-- post-check: 8 patched procs carry [84], 8 backups, no named transaction, no guard ROLLBACK, no DROP in the writers' CATCH
IF (SELECT COUNT(*) FROM sys.objects o WHERE o.name IN ('sp_AddPaymentSupplierCompound_V2','sp_AddPaymentSupplierCompound','sp_AddPaymentClient','sp_ReversePaymentClient','SP_POSTINVENTORY','sp_FinalizeInventoryUpload','sp_PostCompoundTicket','sp_PostCompoundTicketSales')
      AND OBJECT_DEFINITION(o.object_id) LIKE '%[[]84]%') <> 8
   OR (SELECT COUNT(*) FROM sys.objects WHERE name LIKE '%[_]OLD[_]10142026235900') <> 8
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_PostCompoundTicket')) LIKE '%DROP TABLE IF EXISTS #Legs%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound_V2')) LIKE '%TRANSACTION PaySupplier%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentSupplierCompound')) LIKE '%TRANSACTION PaySupplier%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AddPaymentClient')) LIKE '%ROLLBACK;%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient')) LIKE '%ROLLBACK;%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.SP_POSTINVENTORY')) LIKE '%RAISERROR(''SP_POSTINVENTORY failed%'
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[84] post-check failed; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
GO

SET NOEXEC OFF;
GO
SELECT DB_NAME() AS DatabaseName, name, CONVERT(VARCHAR(16), modify_date, 120) AS Modified FROM sys.objects
WHERE name IN ('sp_AddPaymentSupplierCompound_V2','sp_AddPaymentSupplierCompound','sp_AddPaymentClient','sp_ReversePaymentClient','SP_POSTINVENTORY','sp_FinalizeInventoryUpload')
   OR name LIKE '%[_]OLD[_]10142026235900' ORDER BY name;
GO
