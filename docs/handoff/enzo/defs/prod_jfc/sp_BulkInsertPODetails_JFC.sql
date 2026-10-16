
CREATE   PROCEDURE [dbo].[sp_BulkInsertPODetails_JFC]
    @Items dbo.PODetailsType_JFC READONLY
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO PODETAILS (
        ShipmentNo, SupplierID, OrderType, OrderCode, Quantity, Cost,
        TotalCost, Unit, ReferenceCode, ActualQuantity, ActualCost, ActualTotalCost, isVat
    )
    SELECT * FROM @Items;
END
 