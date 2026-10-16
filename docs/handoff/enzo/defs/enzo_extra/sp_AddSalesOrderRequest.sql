-- =============================================
CREATE PROCEDURE [dbo].[sp_AddSalesOrderRequest]
    @parmpono            varchar(50),
    @parmcustomerkey     varchar(50),
    @parmbranchcode      varchar(50),
    @parmeffectivitydate date,
    @parmrequestedby     varchar(50),
    @parmnotes           varchar(200),
    @parmordertype       varchar(50),
    @parmpaymenttype     varchar(10),
    @Lines               dbo.tt_PurchaseOrderLines READONLY
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM @Lines)
            THROW 59301, 'No product lines submitted for this order.', 1;

        IF EXISTS (SELECT 1 FROM PurchaseOrderSummary WHERE PONumber = @parmpono)
            THROW 59302, 'This PO number has already been saved.', 1;

        INSERT INTO PurchaseOrderDetails
            (SeqNo, PONumber, ProductCode, ProductName, Qty, Units, isValid, Remarks, SellingPrice)
        SELECT
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
            @parmpono,
            ProductCode,
            ProductName,
            Qty,
            Units,
            0,
            REPLACE(REPLACE(ISNULL(Remarks,''), CHAR(10), ''), CHAR(13), ''),
            SellingPrice
        FROM @Lines;

        DECLARE @totalqty decimal(18,3);
        SELECT @totalqty = SUM(Qty) FROM @Lines;

        DECLARE @stat varchar(50) = 'FOR APPROVAL';
        IF EXISTS (SELECT 1 FROM CompanyProfile WHERE CompanyName = 'JFC')
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.ApprovalSettings WHERE Module = 'AddSalesOrder' AND isAuto = 1)
                SET @stat = 'APPROVED';
        END
        
        INSERT INTO PurchaseOrderSummary
            (PONumber, Customer, BranchCode, Qty, Status, Dateadded, EffectivityDate,
             RequestedBy, ApprovedBy, DateApproved, Notes, Remarks, isProcess, OrderType, PaymentType)
        VALUES
            (@parmpono, @parmcustomerkey, @parmbranchcode, @totalqty, @stat, GETDATE(), @parmeffectivitydate,
             @parmrequestedby, '', '19000101', @parmnotes, ' ', 0, @parmordertype, @parmpaymenttype);

        COMMIT TRAN;

        SELECT @stat AS Status;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;

        DECLARE @EMsg  NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ESev  INT            = ERROR_SEVERITY();
        DECLARE @ESt   INT            = ERROR_STATE();
        DECLARE @ELine INT            = ERROR_LINE();
        DECLARE @EProc NVARCHAR(128)  = ISNULL(ERROR_PROCEDURE(), 'sp_AddSalesOrderRequest');
        RAISERROR('Error in %s (line %d): %s', @ESev, @ESt, @EProc, @ELine, @EMsg);
    END CATCH
END
