/* ================================================================
   DEV ONLY: removes every POS V2 object so 01 + 02 can be re-run (used while POS V2
   phases are built on DEV; STAGING / production get 01 + 02 once).
   Refuses if any POS V2 sale exists, so it can't wipe real data.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() NOT IN ('COREX001') OR SERVERPROPERTY('InstanceName') IS NOT NULL   -- DEV = COREX001 on the default instance only
    THROW 61099, 'DEV only (COREX001).', 1;
IF OBJECT_ID('dbo.POSV2_Sale', 'U') IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.POSV2_Sale)
    THROW 61099, 'POS V2 sales exist; nothing was removed.', 1;
IF EXISTS (SELECT 1 FROM dbo.TicketMaster WHERE Mnemonic = 'POSV2-SHIFT')
    THROW 61099, 'POS V2 shift GL tickets exist (clean them with the test cleanup first); nothing was removed.', 1;
BEGIN TRAN;
-- phase 5: script 03's patched shared procs go back to their backups (DEV re-runs 03 after 01 + 02)
DECLARE @r SYSNAME;
DECLARE rc CURSOR LOCAL FAST_FORWARD FOR
    SELECT REPLACE(name, '_OLD_10132026120000', '') FROM sys.procedures WHERE name LIKE '%[_]OLD[_]10132026120000';
OPEN rc; FETCH NEXT FROM rc INTO @r;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF OBJECT_ID('dbo.' + @r, 'P') IS NOT NULL EXEC ('DROP PROCEDURE dbo.' + @r);
    DECLARE @from NVARCHAR(300) = N'dbo.' + @r + N'_OLD_10132026120000';
    EXEC sp_rename @from, @r;
    FETCH NEXT FROM rc INTO @r;
END
CLOSE rc; DEALLOCATE rc;
DECLARE @p SYSNAME;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.procedures WHERE name IN ('spu_POSV2_PostSale','spu_POSV2_VoidSale','spu_POSV2_RegisterTerminal','sp_POSV2_GetProducts','sp_POSV2_GetStock','sp_POSV2_GetDiscountTypes',
                                               'spu_POSV2_OpenShift','spu_POSV2_CloseShift','spu_POSV2_PostShiftGL','spu_POSV2_PostPendingShiftGL',
                                               'sp_POSV2_GetSupervisors','sp_POSV2_ListSupervisors','spu_POSV2_SetSupervisor','spu_POSV2_ForceCloseShift',
                                               'spu_POSV2_PostReturn','sp_POSV2_GetSaleForReturn','sp_POSV2_GetCustomers',
                                               'sp_rpt_POSV2_Shifts','sp_rpt_POSV2_SalesJournal','sp_rpt_POSV2_Returns','sp_rpt_POSV2_NeedsAttention');
OPEN c; FETCH NEXT FROM c INTO @p;
WHILE @@FETCH_STATUS = 0 BEGIN EXEC ('DROP PROCEDURE dbo.' + @p); FETCH NEXT FROM c INTO @p; END
CLOSE c; DEALLOCATE c;
IF OBJECT_ID('dbo.fn_POSV2_ZReadings', 'IF') IS NOT NULL DROP FUNCTION dbo.fn_POSV2_ZReadings;
IF OBJECT_ID('dbo.POSV2_ReturnLot', 'U') IS NOT NULL DROP TABLE dbo.POSV2_ReturnLot;
IF OBJECT_ID('dbo.POSV2_ReturnLine', 'U') IS NOT NULL DROP TABLE dbo.POSV2_ReturnLine;
IF OBJECT_ID('dbo.POSV2_Return', 'U') IS NOT NULL DROP TABLE dbo.POSV2_Return;
IF OBJECT_ID('dbo.POSV2_Shortage', 'U') IS NOT NULL DROP TABLE dbo.POSV2_Shortage;
IF OBJECT_ID('dbo.POSV2_SaleLot', 'U') IS NOT NULL DROP TABLE dbo.POSV2_SaleLot;
IF OBJECT_ID('dbo.POSV2_SaleDiscount', 'U') IS NOT NULL DROP TABLE dbo.POSV2_SaleDiscount;
IF OBJECT_ID('dbo.POSV2_Payment', 'U') IS NOT NULL DROP TABLE dbo.POSV2_Payment;
IF OBJECT_ID('dbo.POSV2_SaleLine', 'U') IS NOT NULL DROP TABLE dbo.POSV2_SaleLine;
IF OBJECT_ID('dbo.POSV2_Sale', 'U') IS NOT NULL DROP TABLE dbo.POSV2_Sale;
IF OBJECT_ID('dbo.POSV2_Shift', 'U') IS NOT NULL DROP TABLE dbo.POSV2_Shift;
IF OBJECT_ID('dbo.POSV2_Supervisor', 'U') IS NOT NULL DROP TABLE dbo.POSV2_Supervisor;
IF OBJECT_ID('dbo.POSV2_SupervisorLog', 'U') IS NOT NULL DROP TABLE dbo.POSV2_SupervisorLog;
IF OBJECT_ID('dbo.POSV2_DiscountType', 'U') IS NOT NULL DROP TABLE dbo.POSV2_DiscountType;
-- phase 3 mapping rows (configuration): only when no ticket uses them
IF NOT EXISTS (SELECT 1 FROM dbo.TicketMaster WHERE Mnemonic = 'POSV2-SHIFT')
    DELETE FROM dbo.JournalEntryMapping WHERE Origin = 'POSV2' AND Mnemonic = 'POSV2-SHIFT';
-- phase 4 account (DEV re-creates it): only when no ticket line uses it
IF NOT EXISTS (SELECT 1 FROM dbo.TicketDetails WHERE AccountCode = '60340')
    DELETE FROM dbo.ChartOfAccounts WHERE AccountCode = '60340';
IF OBJECT_ID('dbo.POSV2_Terminal', 'U') IS NOT NULL DROP TABLE dbo.POSV2_Terminal;
IF TYPE_ID('dbo.tt_POSV2_SaleLine') IS NOT NULL DROP TYPE dbo.tt_POSV2_SaleLine;
IF TYPE_ID('dbo.tt_POSV2_Payment') IS NOT NULL DROP TYPE dbo.tt_POSV2_Payment;
IF TYPE_ID('dbo.tt_POSV2_SaleDiscount') IS NOT NULL DROP TYPE dbo.tt_POSV2_SaleDiscount;
IF TYPE_ID('dbo.tt_POSV2_ReturnLine') IS NOT NULL DROP TYPE dbo.tt_POSV2_ReturnLine;
IF OBJECT_ID('dbo.seq_POSV2_ARRef', 'SO') IS NOT NULL DROP SEQUENCE dbo.seq_POSV2_ARRef;
COMMIT;
PRINT 'POS V2 objects removed (DEV).';
