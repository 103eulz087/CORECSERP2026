/* ================================================================
   [93] 2026-10-15g  Supplier: local / import + "payable both ways"
   ================================================================
   User (2026-10-15): Supplier.isLocal tells a LOCAL supplier from an IMPORT one.
     - Supplier Payment (cash / check, AccountingDevEx/SupplierPaymentDevEx) lists
       LOCAL suppliers only
     - Vouchering Telegraphic (AccountingDevEx/VoucheringManualFrm) lists IMPORT
       suppliers only
     - 000121 JANIVA RESOURCES is import but is paid both ways (it has 2 cheque
       vouchers on PRODUCTION), so it must show on both screens
   isLocal is a bit and can't say "both"; Supplier.PaymentMode (MANUAL /
   AUTODEBIT) is about auto-debit (Bureau of Customs), not about the screen.
   So: NEW COLUMN Supplier.isPayableBoth BIT NOT NULL DEFAULT 0.
   RULE (the two screens' supplier lists, C# of 2026-10-15):
     Cash / Check:  ISNULL(isLocal, 1) = 1 OR isPayableBoth = 1
     Telegraphic:   isLocal = 0           OR isPayableBoth = 1

   DATA (user, 2026-10-15): isLocal was not reliable: PRODUCTION had 36 suppliers
   marked IMPORT, most of them local (BUREAU OF CUSTOMS 81 cash vouchers,
   ZAMBOANGA G. CORP 3 cheques, hotels, individuals ...), probably created
   without ticking the box. User's answer: IMPORT = 000121-000129 + 000132
   (PROFOOD HOLLAND, paid by telegraphic 3 times); every other supplier LOCAL;
   000121 isPayableBoth = 1. Telegraphic history on PRODUCTION: 000125 (6),
   000132 (3), 000129 (1): all IMPORT after this. Old / new values kept in
   dbo.Supplier_LocalImport_Backup_20261015.

   sp_addSupplier (the Supplier screen's ADD; its UPDATE path is unused by the
   screen today): the INSERT had no column list (INSERT INTO Supplier VALUES
   (12 values)), so a new column breaks it: now an explicit column list. New
   optional @parmisboth BIT = NULL (NULL = keep / 0 for a new supplier), so the
   current exe keeps working. It was the only writer into Supplier (PRODUCTION,
   every module checked; no C# inserts). WEB v2: an INSERT into Supplier must
   name its columns.
   Guard: sp_addSupplier = its 2026 text (whitespace-insensitive SHA-256
   9B96144E..., identical on DEV / STAGING / PRODUCTION); the 10 import keys must
   exist. One transaction, re-runnable (skips the column if present; the
   backup proc name is taken per run). Run in ONE connection, no open
   transaction.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET LOCK_TIMEOUT 10000;
GO

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[93] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.Supplier', 'U') IS NULL OR COL_LENGTH('dbo.Supplier', 'isLocal') IS NULL
BEGIN
    RAISERROR('[93] stopped: dbo.Supplier / isLocal not found in this database.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF COL_LENGTH('dbo.Supplier', 'isPayableBoth') IS NULL
     AND CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(
            OBJECT_DEFINITION(OBJECT_ID('dbo.sp_addSupplier')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
         <> '9B96144E6DA6B41443785514E652DCE64374B257D4DC7251B4A814CF1CE40E36'
BEGIN
    RAISERROR('[93] stopped: sp_addSupplier is not the text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF (SELECT COUNT(*) FROM dbo.Supplier
         WHERE SupplierKey IN ('000121','000122','000123','000124','000125','000126','000127','000128','000129','000132')) <> 10
BEGIN
    RAISERROR('[93] stopped: the 10 import suppliers (000121-000129, 000132) are not all in this database; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[93] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
IF COL_LENGTH('dbo.Supplier', 'isPayableBoth') IS NULL
    ALTER TABLE dbo.Supplier ADD isPayableBoth BIT NOT NULL CONSTRAINT DF_Supplier_isPayableBoth DEFAULT (0);
GO

------------------------------------------------------------------
-- 1. Data: imports = 000121-000129 + 000132, everyone else local; 000121 both
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
IF OBJECT_ID('dbo.Supplier_LocalImport_Backup_20261015', 'U') IS NULL
    CREATE TABLE dbo.Supplier_LocalImport_Backup_20261015
    (
        SupplierKey       VARCHAR(50)  NOT NULL,
        SupplierID        VARCHAR(20)  NULL,
        SupplierName      VARCHAR(100) NULL,
        Old_isLocal       BIT          NULL,
        Old_isPayableBoth BIT          NULL,
        New_isLocal       BIT          NULL,
        New_isPayableBoth BIT          NULL,
        BackedUpAt        DATETIME2(0) NOT NULL CONSTRAINT DF_SuppLI93_At DEFAULT (SYSDATETIME()),
        BackedUpBy        SYSNAME      NOT NULL CONSTRAINT DF_SuppLI93_By DEFAULT (SUSER_SNAME())
    );
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
;WITH target AS (
    SELECT s.SupplierKey, s.SupplierID, s.SupplierName, s.isLocal, s.isPayableBoth,
           CAST(CASE WHEN s.SupplierKey IN ('000121','000122','000123','000124','000125','000126','000127','000128','000129','000132')
                     THEN 0 ELSE 1 END AS BIT) AS NewLocal,
           CAST(CASE WHEN s.SupplierKey = '000121' THEN 1 ELSE s.isPayableBoth END AS BIT) AS NewBoth
    FROM dbo.Supplier AS s
)
INSERT INTO dbo.Supplier_LocalImport_Backup_20261015
    (SupplierKey, SupplierID, SupplierName, Old_isLocal, Old_isPayableBoth, New_isLocal, New_isPayableBoth)
SELECT SupplierKey, SupplierID, SupplierName, isLocal, isPayableBoth, NewLocal, NewBoth
FROM target
WHERE ISNULL(CAST(isLocal AS INT), -1) <> NewLocal OR isPayableBoth <> NewBoth;
PRINT '[93] suppliers backed up for change: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

UPDATE s
SET isLocal       = CASE WHEN s.SupplierKey IN ('000121','000122','000123','000124','000125','000126','000127','000128','000129','000132')
                         THEN 0 ELSE 1 END,
    isPayableBoth = CASE WHEN s.SupplierKey = '000121' THEN 1 ELSE s.isPayableBoth END
FROM dbo.Supplier AS s
WHERE ISNULL(CAST(s.isLocal AS INT), -1) <> CASE WHEN s.SupplierKey IN ('000121','000122','000123','000124','000125','000126','000127','000128','000129','000132') THEN 0 ELSE 1 END
   OR (s.SupplierKey = '000121' AND s.isPayableBoth <> 1);
PRINT '[93] suppliers changed: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
GO

------------------------------------------------------------------
-- 2. sp_addSupplier: explicit column list + optional @parmisboth
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @old SYSNAME = 'sp_addSupplier_OLD_' + FORMAT(SYSDATETIME(), 'MMddyyyyHHmmss');
EXEC sp_rename 'dbo.sp_addSupplier', @old;
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE [dbo].[sp_addSupplier]
	@parmsuppkey varchar(15),
	@parmid varchar(10),
	@parmsuppliername varchar(50),
	@parmaddress varchar(100),
	@parmcontact varchar(20),
	@parmofficer varchar(30),
	@parmtinno varchar(30),
	@parmtradename varchar(50),
	@parmlineofbusiness varchar(50),
	@parmisvat bit,
	@parmislocal bit,
	@exectype varchar(20),
	@parmisboth bit = NULL      -- [93] 2026-10-15: paid by Cash / Check AND Telegraphic; NULL = keep (0 for a new supplier)
AS
/*
    The Supplier screen (HOFormsDevEx/AddSupplierDevEx): ADD inserts a supplier; UPDATE (not used by the screen today)
    updates one. [93] 2026-10-15: explicit column list on the INSERT (it was INSERT INTO Supplier VALUES (...), which a
    new column breaks) and the optional @parmisboth (Supplier.isPayableBoth); an older exe that omits it keeps working.
*/
BEGIN
	SET NOCOUNT ON;

	if(@exectype='ADD')
	begin
		INSERT INTO dbo.Supplier
			(SupplierKey, SupplierID, SupplierName, Address, ContactNo, Officer, TinNo, TradeName, LineOfBusiness,
			 isVat, isLocal, PaymentMode, isPayableBoth)
		VALUES
			(@parmsuppkey, @parmid, @parmsuppliername, @parmaddress, @parmcontact, @parmofficer, @parmtinno, @parmtradename, @parmlineofbusiness,
			 @parmisvat, @parmislocal, 'MANUAL', ISNULL(@parmisboth, 0))
	end
	else if(@exectype='UPDATE')
	begin
		UPDATE dbo.Supplier set SupplierName=@parmsuppliername,Address=@parmaddress,ContactNo=@parmcontact,Officer=@parmofficer,TinNo=@parmtinno,
		TradeName=@parmtradename,LineOfBusiness=@parmlineofbusiness,isVat=@parmisvat,isLocal=@parmislocal,
		isPayableBoth=ISNULL(@parmisboth, isPayableBoth)
		WHERE SupplierKey=@parmsuppkey
	end
END
GO

------------------------------------------------------------------
-- 3. Post-check, then commit
------------------------------------------------------------------
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF OBJECT_ID('dbo.sp_addSupplier', 'P') IS NULL
    SET @msg = N'sp_addSupplier was not created';
ELSE IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_addSupplier')) NOT LIKE '%@parmisboth%'
    SET @msg = N'sp_addSupplier is not the [93] text';
ELSE IF COL_LENGTH('dbo.Supplier', 'isPayableBoth') IS NULL
    SET @msg = N'Supplier.isPayableBoth is missing';
ELSE IF EXISTS (SELECT 1 FROM dbo.Supplier
                WHERE isLocal IS NULL
                   OR isLocal <> CASE WHEN SupplierKey IN ('000121','000122','000123','000124','000125','000126','000127','000128','000129','000132') THEN 0 ELSE 1 END)
    SET @msg = N'a supplier''s isLocal is not as decided';
ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Supplier WHERE SupplierKey = '000121' AND isPayableBoth = 1)
    SET @msg = N'000121 is not marked payable both ways';

IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[93] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59897, @msg, 1;
END

COMMIT TRANSACTION;
PRINT '[93] committed: Supplier.isPayableBoth, local / import flags, sp_addSupplier.';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
