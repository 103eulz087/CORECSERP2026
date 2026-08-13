SET NOCOUNT ON;
PRINT '=== Service Order: new dedicated tables, TVP, SPs, view (Orders/AddOrder.cs Services tab) ===';
GO

-- =============================================
-- WHY DEDICATED TABLES (not PurchaseOrderSummary/PurchaseOrderDetails):
--   Products' request/delivery tables are wired into a physical-goods
--   pipeline (DeliveryDetails/DeliverySummary, sp_ConfirmOrder, manual
--   pre-printed Sales Invoice entry, POForApproval delivery tabs). Services
--   have no picking/delivery step and must NOT go through that pipeline
--   (explicit requirement: "not processed like Process Sales Order").
--   A parallel, smaller table pair keeps the two concerns from having to
--   special-case each other anywhere downstream.
-- =============================================

IF OBJECT_ID('dbo.ServiceOrderDetails', 'U') IS NOT NULL DROP TABLE dbo.ServiceOrderDetails;
IF OBJECT_ID('dbo.ServiceOrderSummary', 'U') IS NOT NULL DROP TABLE dbo.ServiceOrderSummary;
GO

CREATE TABLE dbo.ServiceOrderSummary
(
    SVCNumber      VARCHAR(50)   NOT NULL PRIMARY KEY,
    CustomerKey    CHAR(8)       NOT NULL,
    BranchCode     VARCHAR(50)   NOT NULL,
    TotalQty       DECIMAL(18,3) NOT NULL DEFAULT 0,
    TotalAmount    DECIMAL(18,2) NOT NULL DEFAULT 0,
    PaymentType    VARCHAR(10)   NULL,
    Status         VARCHAR(50)   NOT NULL DEFAULT 'FOR APPROVAL',
    DateAdded      DATETIME      NOT NULL DEFAULT GETDATE(),
    RequestedBy    VARCHAR(50)   NULL,
    ApprovedBy     VARCHAR(50)   NULL,
    DateApproved   DATETIME      NULL,
    RejectedBy     VARCHAR(50)   NULL,
    DateRejected   DATETIME      NULL,
    RejectReason   VARCHAR(250)  NULL,
    ReferenceNo    VARCHAR(20)   NULL,   -- = SVCNumber, mirrors sp_ConfirmOrder's use of PONumber as AR ReferenceNo
    InvoiceNo      VARCHAR(10)   NULL,   -- system-generated at approval time (GetReferenceNumber) -- no physical booklet for services
    Remarks        VARCHAR(200)  NULL
);
GO

CREATE TABLE dbo.ServiceOrderDetails
(
    SVCNumber      VARCHAR(50)   NOT NULL,
    SeqNo          DECIMAL(3,0)  NOT NULL,
    ServiceCode    VARCHAR(50)   NOT NULL,
    ServiceName    VARCHAR(100)  NOT NULL,
    Qty            DECIMAL(18,3) NOT NULL,
    SellingPrice   DECIMAL(10,2) NOT NULL,
    CONSTRAINT PK_ServiceOrderDetails PRIMARY KEY (SVCNumber, SeqNo),
    CONSTRAINT FK_ServiceOrderDetails_Summary FOREIGN KEY (SVCNumber)
        REFERENCES dbo.ServiceOrderSummary(SVCNumber)
);
GO

IF TYPE_ID('dbo.tt_ServiceOrderLines') IS NOT NULL DROP TYPE dbo.tt_ServiceOrderLines;
GO
CREATE TYPE dbo.tt_ServiceOrderLines AS TABLE
(
    ServiceCode    VARCHAR(50)   NOT NULL,
    ServiceName    VARCHAR(100)  NOT NULL,
    Qty            DECIMAL(18,3) NOT NULL,
    SellingPrice   DECIMAL(10,2) NOT NULL
);
GO

-- =============================================
-- Author:      Eulz Avancena (original); added 2026-08-09
-- Description: Submits a new Service Order request (AddOrder.cs Services tab,
--              saveAllServices()). Header + lines only -- lands in FOR APPROVAL,
--              same as it does for Products, but on the dedicated Service tables.
-- =============================================
CREATE PROCEDURE [dbo].[sp_AddServiceOrderRequest]
    @SVCNumber    VARCHAR(50),
    @CustomerKey  CHAR(8),
    @BranchCode   VARCHAR(50),
    @PaymentType  VARCHAR(10),
    @RequestedBy  VARCHAR(50),
    @Lines        dbo.tt_ServiceOrderLines READONLY
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM @Lines)
            THROW 58101, 'No service lines to submit.', 1;

        IF EXISTS (SELECT 1 FROM dbo.ServiceOrderSummary WHERE SVCNumber = @SVCNumber)
            THROW 58102, 'This Service Order number already exists.', 1;

        INSERT INTO dbo.ServiceOrderSummary
            (SVCNumber, CustomerKey, BranchCode, TotalQty, TotalAmount,
             PaymentType, Status, DateAdded, RequestedBy)
        SELECT
            @SVCNumber, @CustomerKey, @BranchCode,
            SUM(Qty), SUM(Qty * SellingPrice),
            @PaymentType, 'FOR APPROVAL', GETDATE(), @RequestedBy
        FROM @Lines;

        INSERT INTO dbo.ServiceOrderDetails
            (SVCNumber, SeqNo, ServiceCode, ServiceName, Qty, SellingPrice)
        SELECT
            @SVCNumber,
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
            ServiceCode, ServiceName, Qty, SellingPrice
        FROM @Lines;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        DECLARE @EMsg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ESev INT = ERROR_SEVERITY();
        DECLARE @ESt  INT = ERROR_STATE();
        RAISERROR('%s', @ESev, @ESt, @EMsg);
    END CATCH
END;
GO

-- =============================================
-- Author:      Eulz Avancena (original); added 2026-08-09
-- Description: Approves a Service Order (new Services approval screen).
--              Skips the entire Delivery/BatchSales pipeline products go
--              through -- posts straight to TransactionChargeSales so it
--              reflects in Aging. InvoiceNo is system-generated
--              (GetReferenceNumber); there is no physical invoice booklet
--              step for services.
-- =============================================
CREATE PROCEDURE [dbo].[sp_ApproveServiceOrder]
    @SVCNumber   VARCHAR(50),
    @ApprovedBy  VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE
        @custkey      CHAR(8),
        @branchcode   VARCHAR(50),
        @paymenttype  VARCHAR(10),
        @term         INT,
        @totalAmount  DECIMAL(18,2),
        @invoiceno    VARCHAR(10);

    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM dbo.ServiceOrderSummary WHERE SVCNumber = @SVCNumber AND Status = 'FOR APPROVAL')
            THROW 58111, 'This Service Order is not pending approval (already approved/rejected).', 1;

        SELECT @custkey = CustomerKey, @branchcode = BranchCode, @paymenttype = PaymentType
        FROM dbo.ServiceOrderSummary
        WHERE SVCNumber = @SVCNumber;

        SELECT @term = ISNULL(Term, 0) FROM dbo.Customers WHERE CustomerKey = @custkey;

        SELECT @totalAmount = ISNULL(SUM(Qty * SellingPrice), 0)
        FROM dbo.ServiceOrderDetails
        WHERE SVCNumber = @SVCNumber;

        EXEC dbo.GetReferenceNumber @invoiceno OUTPUT;

        INSERT INTO dbo.TransactionChargeSales
            (CustomerKey, BranchCode, TransactionDate, ReferenceNo, InvoiceNo,
             TotalAmount, PaymentType, Balance, AmountPaid, PayStatus, DueDate, Remarks)
        VALUES
            (@custkey, @branchcode, CAST(GETDATE() AS DATE), @SVCNumber, @invoiceno,
             @totalAmount, ISNULL(@paymenttype, ''), @totalAmount, 0, 'UNPAID',
             DATEADD(DAY, @term, CAST(GETDATE() AS DATE)), 'SERVICE CHARGE - ' + @SVCNumber);

        UPDATE dbo.ServiceOrderSummary
        SET Status = 'APPROVED',
            ApprovedBy = @ApprovedBy,
            DateApproved = GETDATE(),
            ReferenceNo = @SVCNumber,
            InvoiceNo = @invoiceno,
            TotalAmount = @totalAmount
        WHERE SVCNumber = @SVCNumber;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        DECLARE @EMsg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ESev INT = ERROR_SEVERITY();
        DECLARE @ESt  INT = ERROR_STATE();
        RAISERROR('%s', @ESev, @ESt, @EMsg);
    END CATCH
END;
GO

-- =============================================
-- Author:      Eulz Avancena (original); added 2026-08-09
-- Description: Rejects a pending Service Order request.
-- =============================================
CREATE PROCEDURE [dbo].[sp_RejectServiceOrder]
    @SVCNumber   VARCHAR(50),
    @RejectedBy  VARCHAR(50),
    @Reason      VARCHAR(250)
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.ServiceOrderSummary WHERE SVCNumber = @SVCNumber AND Status = 'FOR APPROVAL')
        THROW 58121, 'This Service Order is not pending approval (already approved/rejected).', 1;

    UPDATE dbo.ServiceOrderSummary
    SET Status = 'REJECTED',
        RejectedBy = @RejectedBy,
        DateRejected = GETDATE(),
        RejectReason = @Reason
    WHERE SVCNumber = @SVCNumber;
END;
GO

-- =============================================
-- List view for the Services approval screen (mirrors view_POSummary's shape).
-- =============================================
IF OBJECT_ID('dbo.view_ServiceOrderSummary', 'V') IS NOT NULL DROP VIEW dbo.view_ServiceOrderSummary;
GO
CREATE VIEW [dbo].[view_ServiceOrderSummary]
AS
SELECT
    a.BranchCode,
    a.SVCNumber,
    b.CustomerName AS Customer,
    a.TotalQty,
    a.TotalAmount,
    a.PaymentType,
    a.Status,
    a.DateAdded,
    UPPER(a.RequestedBy) AS RequestedBy,
    UPPER(ISNULL(a.ApprovedBy, '')) AS ApprovedBy,
    a.DateApproved,
    UPPER(ISNULL(a.RejectedBy, '')) AS RejectedBy,
    a.DateRejected,
    UPPER(ISNULL(a.RejectReason, '')) AS RejectReason,
    a.ReferenceNo,
    a.InvoiceNo,
    UPPER(ISNULL(a.Remarks, '')) AS Remarks
FROM dbo.ServiceOrderSummary a
INNER JOIN dbo.Customers b ON a.CustomerKey = b.CustomerKey;
GO

-- =============================================
-- Line-detail function for a given Service Order (approval popup / re-display).
-- =============================================
IF OBJECT_ID('dbo.funcview_ServiceOrderDetails', 'IF') IS NOT NULL DROP FUNCTION dbo.funcview_ServiceOrderDetails;
GO
CREATE FUNCTION [dbo].[funcview_ServiceOrderDetails]
(
    @parmsvcnumber VARCHAR(50)
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        d.SeqNo,
        d.SVCNumber,
        d.ServiceCode,
        d.ServiceName,
        d.Qty,
        d.SellingPrice,
        (d.Qty * d.SellingPrice) AS Amount
    FROM dbo.ServiceOrderDetails d
    WHERE d.SVCNumber = @parmsvcnumber
);
GO

PRINT 'DEPLOYMENT COMPLETE: ServiceOrderSummary/ServiceOrderDetails, tt_ServiceOrderLines, sp_AddServiceOrderRequest, sp_ApproveServiceOrder, sp_RejectServiceOrder, view_ServiceOrderSummary, funcview_ServiceOrderDetails.';
