namespace SalesInventorySystem.POSV2.Services
{
    // The terminal's own local database (PosV2Config.LocalCatalog, default CORECS_POSV2), created on first run.
    // Must run on SQL Server 2014 (terminals today): no CREATE OR ALTER, DROP IF EXISTS, STRING_AGG or JSON.
    // Re-runnable: every object is created only when missing.
    internal static class PosLocalSchema
    {
        public const string CreateDatabase = @"
IF DB_ID(@db) IS NULL
BEGIN
    DECLARE @sql NVARCHAR(400) = N'CREATE DATABASE ' + QUOTENAME(@db);
    EXEC (@sql);
END";

        public const string Tables = @"
IF OBJECT_ID('dbo.PosMeta', 'U') IS NULL
    CREATE TABLE dbo.PosMeta (Name VARCHAR(50) NOT NULL PRIMARY KEY, Value NVARCHAR(400) NULL);

IF OBJECT_ID('dbo.PosTerminal', 'U') IS NULL
    CREATE TABLE dbo.PosTerminal
    (
        Id           INT          NOT NULL PRIMARY KEY CHECK (Id = 1),   -- one row: this terminal
        TerminalID   INT          NOT NULL,
        BranchCode   VARCHAR(10)  NOT NULL,
        TerminalCode VARCHAR(50)  NOT NULL,
        ORPrefix     VARCHAR(12)  NOT NULL,
        NextORSeq    BIGINT       NOT NULL,
        RegisteredAt DATETIME     NOT NULL DEFAULT (GETDATE())
    );

IF OBJECT_ID('dbo.PosProduct', 'U') IS NULL
    CREATE TABLE dbo.PosProduct
    (
        ProductCode  VARCHAR(50)   NOT NULL PRIMARY KEY,
        Description  VARCHAR(300)  NULL,
        Barcode      VARCHAR(150)  NULL,
        SellingPrice DECIMAL(18,2) NOT NULL,
        Price1       DECIMAL(18,2) NOT NULL,
        Price2       DECIMAL(18,2) NOT NULL,
        Price3       DECIMAL(18,2) NOT NULL,
        Price4       DECIMAL(18,2) NOT NULL,
        IsVat        BIT           NOT NULL,
        CategoryCode INT           NULL
    );
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PosProduct_Barcode')
    CREATE INDEX IX_PosProduct_Barcode ON dbo.PosProduct (Barcode);

IF OBJECT_ID('dbo.PosStock', 'U') IS NULL
    CREATE TABLE dbo.PosStock (ProductCode VARCHAR(50) NOT NULL PRIMARY KEY, Available DECIMAL(18,3) NOT NULL);

IF OBJECT_ID('dbo.PosSale', 'U') IS NULL
    CREATE TABLE dbo.PosSale
    (
        SaleGUID       UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        ORNo           VARCHAR(30)   NOT NULL UNIQUE,
        SaleDateTime   DATETIME      NOT NULL,
        CashierUserID  VARCHAR(50)   NOT NULL,
        CashierName    VARCHAR(100)  NULL,
        CustomerKey    VARCHAR(20)   NULL,
        GrossAmount    DECIMAL(18,2) NOT NULL,
        DiscountAmount DECIMAL(18,2) NOT NULL,
        NetAmount      DECIMAL(18,2) NOT NULL,
        VatableSales   DECIMAL(18,2) NOT NULL,
        VatAmount      DECIMAL(18,2) NOT NULL,
        VatExemptSales DECIMAL(18,2) NOT NULL,
        ZeroRatedSales DECIMAL(18,2) NOT NULL,
        AmountTendered DECIMAL(18,2) NOT NULL,
        ChangeAmount   DECIMAL(18,2) NOT NULL,
        WasOffline     BIT           NOT NULL,
        SavedAt        DATETIME      NOT NULL,
        SyncStatus     VARCHAR(10)   NOT NULL DEFAULT ('PENDING'),   -- PENDING / POSTED / FAILED
        SyncMessage    NVARCHAR(1000) NULL,
        PostedAt       DATETIME      NULL,
        ShortLines     INT           NULL
    );

IF OBJECT_ID('dbo.PosSaleLine', 'U') IS NULL
    CREATE TABLE dbo.PosSaleLine
    (
        SaleGUID     UNIQUEIDENTIFIER NOT NULL,
        [LineNo]     INT           NOT NULL,
        ProductCode  VARCHAR(50)   NOT NULL,
        Barcode      VARCHAR(150)  NULL,
        Description  VARCHAR(300)  NULL,
        Qty          DECIMAL(18,3) NOT NULL,
        PriceLevel   VARCHAR(10)   NOT NULL,
        UnitPrice    DECIMAL(18,2) NOT NULL,
        LineDiscount DECIMAL(18,2) NOT NULL,
        LineTotal    DECIMAL(18,2) NOT NULL,
        IsVat        BIT           NOT NULL,
        VatAmount    DECIMAL(18,2) NOT NULL,
        PRIMARY KEY (SaleGUID, [LineNo])
    );

IF OBJECT_ID('dbo.PosPayment', 'U') IS NULL
    CREATE TABLE dbo.PosPayment
    (
        SaleGUID    UNIQUEIDENTIFIER NOT NULL,
        PayNo       INT           NOT NULL,
        PaymentType VARCHAR(20)   NOT NULL,
        Amount      DECIMAL(18,2) NOT NULL,
        Reference   VARCHAR(100)  NULL,
        PRIMARY KEY (SaleGUID, PayNo)
    );

-- the outbox: one row per event to send, sent in OutboxID order
IF OBJECT_ID('dbo.PosOutbox', 'U') IS NULL
    CREATE TABLE dbo.PosOutbox
    (
        OutboxID      INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        SaleGUID      UNIQUEIDENTIFIER NOT NULL,
        EventType     VARCHAR(10)   NOT NULL,                 -- SALE / VOID / SHIFTOPEN / SHIFTCLOSE (SaleGUID = the shift's GUID)
        Status        VARCHAR(10)   NOT NULL DEFAULT ('PENDING'),   -- PENDING / SENT / FAILED
        Attempts      INT           NOT NULL DEFAULT (0),
        LastAttemptAt DATETIME      NULL,
        LastError     NVARCHAR(1000) NULL,
        CreatedAt     DATETIME      NOT NULL DEFAULT (GETDATE()),
        SentAt        DATETIME      NULL
    );
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PosOutbox_Status')
    CREATE INDEX IX_PosOutbox_Status ON dbo.PosOutbox (Status, OutboxID);

-- ── phase 2: discounts, void, hold, reprint count (columns added to an existing phase-1 database too) ──
IF COL_LENGTH('dbo.PosSaleLine', 'IsVatItem') IS NULL       ALTER TABLE dbo.PosSaleLine ADD IsVatItem BIT NOT NULL DEFAULT (0);
IF COL_LENGTH('dbo.PosSaleLine', 'DiscNo') IS NULL          ALTER TABLE dbo.PosSaleLine ADD DiscNo INT NULL;
IF COL_LENGTH('dbo.PosSaleLine', 'DiscountCode') IS NULL    ALTER TABLE dbo.PosSaleLine ADD DiscountCode VARCHAR(10) NULL;
IF COL_LENGTH('dbo.PosSaleLine', 'DiscountAmount') IS NULL  ALTER TABLE dbo.PosSaleLine ADD DiscountAmount DECIMAL(18,2) NOT NULL DEFAULT (0);
IF COL_LENGTH('dbo.PosSaleLine', 'VatExemptAmount') IS NULL ALTER TABLE dbo.PosSaleLine ADD VatExemptAmount DECIMAL(18,2) NOT NULL DEFAULT (0);
IF COL_LENGTH('dbo.PosSale', 'CancelledLineCount') IS NULL  ALTER TABLE dbo.PosSale ADD CancelledLineCount INT NOT NULL DEFAULT (0);
IF COL_LENGTH('dbo.PosSale', 'CancelledLineAmount') IS NULL ALTER TABLE dbo.PosSale ADD CancelledLineAmount DECIMAL(18,2) NOT NULL DEFAULT (0);
IF COL_LENGTH('dbo.PosSale', 'Status') IS NULL              ALTER TABLE dbo.PosSale ADD Status VARCHAR(10) NOT NULL DEFAULT ('PAID');   -- PAID / VOIDED
IF COL_LENGTH('dbo.PosSale', 'VoidedAt') IS NULL            ALTER TABLE dbo.PosSale ADD VoidedAt DATETIME NULL;
IF COL_LENGTH('dbo.PosSale', 'VoidReason') IS NULL          ALTER TABLE dbo.PosSale ADD VoidReason NVARCHAR(300) NULL;
IF COL_LENGTH('dbo.PosSale', 'VoidedBy') IS NULL            ALTER TABLE dbo.PosSale ADD VoidedBy VARCHAR(60) NULL;
IF COL_LENGTH('dbo.PosSale', 'ReprintCount') IS NULL        ALTER TABLE dbo.PosSale ADD ReprintCount INT NOT NULL DEFAULT (0);

IF OBJECT_ID('dbo.PosSaleDiscount', 'U') IS NULL
    CREATE TABLE dbo.PosSaleDiscount
    (
        SaleGUID        UNIQUEIDENTIFIER NOT NULL,
        DiscNo          INT           NOT NULL,
        DiscountCode    VARCHAR(10)   NOT NULL,
        Name            VARCHAR(100)  NULL,
        [Percent]       DECIMAL(9,4)  NOT NULL,
        Amount          DECIMAL(18,2) NOT NULL,
        VatExemptAmount DECIMAL(18,2) NOT NULL,
        CustomerName    VARCHAR(150)  NULL,
        IDNo            VARCHAR(50)   NULL,
        TIN             VARCHAR(30)   NULL,
        Remarks         VARCHAR(300)  NULL,
        PRIMARY KEY (SaleGUID, DiscNo)
    );

IF OBJECT_ID('dbo.PosDiscountType', 'U') IS NULL
    CREATE TABLE dbo.PosDiscountType
    (
        DiscountCode VARCHAR(10)  NOT NULL PRIMARY KEY,
        Name         VARCHAR(100) NOT NULL,
        Kind         VARCHAR(10)  NOT NULL,
        [Percent]    DECIMAL(9,4) NOT NULL,
        VatExempt    BIT          NOT NULL,
        RequiresID   BIT          NOT NULL,
        SortOrder    INT          NOT NULL
    );

-- held (parked) sales: on this terminal only, no OR number until paid
IF OBJECT_ID('dbo.PosHold', 'U') IS NULL
    CREATE TABLE dbo.PosHold
    (
        HoldID              INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        Name                NVARCHAR(100) NULL,
        CashierUserID       VARCHAR(50)   NULL,
        PriceLevel          VARCHAR(10)   NOT NULL,
        CancelledLineCount  INT           NOT NULL,
        CancelledLineAmount DECIMAL(18,2) NOT NULL,
        CreatedAt           DATETIME      NOT NULL DEFAULT (GETDATE())
    );
IF OBJECT_ID('dbo.PosHoldLine', 'U') IS NULL
    CREATE TABLE dbo.PosHoldLine
    (
        HoldID          INT           NOT NULL,
        [LineNo]        INT           NOT NULL,
        ProductCode     VARCHAR(50)   NOT NULL,
        Barcode         VARCHAR(150)  NULL,
        Description     VARCHAR(300)  NULL,
        Qty             DECIMAL(18,3) NOT NULL,
        PriceLevel      VARCHAR(10)   NOT NULL,
        UnitPrice       DECIMAL(18,2) NOT NULL,
        IsVatItem       BIT           NOT NULL,
        DiscNo          INT           NULL,
        DiscountCode    VARCHAR(10)   NULL,
        DiscountAmount  DECIMAL(18,2) NOT NULL,
        VatExemptAmount DECIMAL(18,2) NOT NULL,
        PRIMARY KEY (HoldID, [LineNo])
    );
IF OBJECT_ID('dbo.PosHoldDiscount', 'U') IS NULL
    CREATE TABLE dbo.PosHoldDiscount
    (
        HoldID       INT           NOT NULL,
        DiscNo       INT           NOT NULL,
        DiscountCode VARCHAR(10)   NOT NULL,
        Name         VARCHAR(100)  NULL,
        [Percent]    DECIMAL(9,4)  NOT NULL,
        CustomerName VARCHAR(150)  NULL,
        IDNo         VARCHAR(50)   NULL,
        TIN          VARCHAR(30)   NULL,
        Remarks      VARCHAR(300)  NULL,
        PRIMARY KEY (HoldID, DiscNo)
    );

-- ── phase 3: shifts, supervisors, cleared sales, drawer openings ──
IF COL_LENGTH('dbo.PosTerminal', 'NextZNo') IS NULL            ALTER TABLE dbo.PosTerminal ADD NextZNo INT NOT NULL DEFAULT (1);
IF COL_LENGTH('dbo.PosSale', 'ShiftGUID') IS NULL              ALTER TABLE dbo.PosSale ADD ShiftGUID UNIQUEIDENTIFIER NULL;
IF COL_LENGTH('dbo.PosSale', 'DiscountApprovedBy') IS NULL     ALTER TABLE dbo.PosSale ADD DiscountApprovedBy VARCHAR(60) NULL;
IF COL_LENGTH('dbo.PosSale', 'VoidApprovedBy') IS NULL         ALTER TABLE dbo.PosSale ADD VoidApprovedBy VARCHAR(60) NULL;
IF COL_LENGTH('dbo.PosDiscountType', 'RequiresApproval') IS NULL ALTER TABLE dbo.PosDiscountType ADD RequiresApproval BIT NOT NULL DEFAULT (0);

IF OBJECT_ID('dbo.PosShift', 'U') IS NULL
    CREATE TABLE dbo.PosShift
    (
        ShiftGUID       UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        ZNo             INT           NOT NULL UNIQUE,
        CashierUserID   VARCHAR(50)   NOT NULL,
        CashierName     VARCHAR(100)  NULL,
        OpenedAt        DATETIME      NOT NULL,
        BeginningCash   DECIMAL(18,2) NOT NULL,
        Status          VARCHAR(10)   NOT NULL DEFAULT ('OPEN'),   -- OPEN / CLOSED
        ClosedAt        DATETIME      NULL,
        CountedCash     DECIMAL(18,2) NULL,
        ClosedBy        VARCHAR(60)   NULL,
        CloseApprovedBy VARCHAR(60)   NULL,
        SyncMessage     NVARCHAR(1000) NULL                         -- the server's answer to the close (GL ticket / why not yet)
    );

IF OBJECT_ID('dbo.PosSupervisor', 'U') IS NULL
    CREATE TABLE dbo.PosSupervisor
    (
        UserID        VARCHAR(50)   NOT NULL PRIMARY KEY,
        FullName      VARCHAR(100)  NULL,
        PinHash       VARBINARY(32) NOT NULL,
        PinSalt       VARBINARY(16) NOT NULL,
        PinIterations INT           NOT NULL
    );

-- a whole sale cleared before payment (F8) and a no-sale drawer opening: counted on the Z-reading
IF OBJECT_ID('dbo.PosShiftEvent', 'U') IS NULL
    CREATE TABLE dbo.PosShiftEvent
    (
        EventID    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        ShiftGUID  UNIQUEIDENTIFIER NOT NULL,
        EventType  VARCHAR(10)   NOT NULL,          -- CLEARED / DRAWER
        Lines      INT           NOT NULL DEFAULT (0),
        Amount     DECIMAL(18,2) NOT NULL DEFAULT (0),
        UserID     VARCHAR(50)   NULL,
        ApprovedBy VARCHAR(60)   NULL,
        Reason     NVARCHAR(300) NULL,
        CreatedAt  DATETIME      NOT NULL DEFAULT (GETDATE())
    );
IF COL_LENGTH('dbo.PosShiftEvent', 'RemovedLines') IS NULL  ALTER TABLE dbo.PosShiftEvent ADD RemovedLines INT NOT NULL DEFAULT (0);
IF COL_LENGTH('dbo.PosShiftEvent', 'RemovedAmount') IS NULL ALTER TABLE dbo.PosShiftEvent ADD RemovedAmount DECIMAL(18,2) NOT NULL DEFAULT (0);

-- ── phase 4: charge customers, card / charge payments, returns ──
IF COL_LENGTH('dbo.PosSale', 'CreditApprovedBy') IS NULL      ALTER TABLE dbo.PosSale ADD CreditApprovedBy VARCHAR(60) NULL;
IF COL_LENGTH('dbo.PosSale', 'CustomerName') IS NULL          ALTER TABLE dbo.PosSale ADD CustomerName VARCHAR(150) NULL;
IF COL_LENGTH('dbo.PosTerminal', 'NextReturnSeq') IS NULL     ALTER TABLE dbo.PosTerminal ADD NextReturnSeq BIGINT NOT NULL DEFAULT (1);
-- phase 5 (BIR): the accumulated grand total (never resets) and each Z-reading's before / after
IF COL_LENGTH('dbo.PosTerminal', 'AccumulatedTotal') IS NULL  ALTER TABLE dbo.PosTerminal ADD AccumulatedTotal DECIMAL(18,2) NOT NULL DEFAULT (0);
IF COL_LENGTH('dbo.PosShift', 'AccumulatedBefore') IS NULL    ALTER TABLE dbo.PosShift ADD AccumulatedBefore DECIMAL(18,2) NULL;
IF COL_LENGTH('dbo.PosShift', 'AccumulatedAfter') IS NULL     ALTER TABLE dbo.PosShift ADD AccumulatedAfter DECIMAL(18,2) NULL;

IF OBJECT_ID('dbo.PosCustomer', 'U') IS NULL
    CREATE TABLE dbo.PosCustomer
    (
        CustomerKey  VARCHAR(20)   NOT NULL PRIMARY KEY,
        CustomerName VARCHAR(150)  NULL,
        BranchCode   VARCHAR(100)  NULL,
        CreditLimit  DECIMAL(18,2) NOT NULL,
        Balance      DECIMAL(18,2) NOT NULL          -- AR balance at the last download
    );

IF OBJECT_ID('dbo.PosReturn', 'U') IS NULL
    CREATE TABLE dbo.PosReturn
    (
        ReturnGUID     UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        ReturnNo       VARCHAR(30)   NOT NULL UNIQUE,
        ShiftGUID      UNIQUEIDENTIFIER NOT NULL,
        OrigSaleGUID   UNIQUEIDENTIFIER NOT NULL,
        OrigORNo       VARCHAR(30)   NOT NULL,
        ReturnDateTime DATETIME      NOT NULL,
        CashierUserID  VARCHAR(50)   NOT NULL,
        CashierName    VARCHAR(100)  NULL,
        ApprovedBy     VARCHAR(60)   NOT NULL,
        Reason         NVARCHAR(300) NOT NULL,
        CustomerKey    VARCHAR(20)   NULL,
        CustomerName   VARCHAR(150)  NULL,
        CashRefund     DECIMAL(18,2) NOT NULL,
        CardRefund     DECIMAL(18,2) NOT NULL,
        ChargeRefund   DECIMAL(18,2) NOT NULL,
        SavedAt        DATETIME      NOT NULL,
        SyncStatus     VARCHAR(10)   NOT NULL DEFAULT ('PENDING'),
        SyncMessage    NVARCHAR(1000) NULL
    );
IF OBJECT_ID('dbo.PosReturnLine', 'U') IS NULL
    CREATE TABLE dbo.PosReturnLine
    (
        ReturnGUID      UNIQUEIDENTIFIER NOT NULL,
        [LineNo]        INT           NOT NULL,
        OrigLineNo      INT           NOT NULL,
        ProductCode     VARCHAR(50)   NOT NULL,
        Description     VARCHAR(300)  NULL,
        Qty             DECIMAL(18,3) NOT NULL,
        GrossAmount     DECIMAL(18,2) NOT NULL,
        DiscountAmount  DECIMAL(18,2) NOT NULL,
        VatExemptAmount DECIMAL(18,2) NOT NULL,
        NetAmount       DECIMAL(18,2) NOT NULL,
        VatAmount       DECIMAL(18,2) NOT NULL,
        PRIMARY KEY (ReturnGUID, [LineNo])
    );
";
    }
}
