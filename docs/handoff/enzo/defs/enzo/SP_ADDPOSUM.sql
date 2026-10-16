CREATE PROCEDURE [dbo].[SP_ADDPOSUM]
	@parmshipmentno varchar(10),
	@parmbranch char(3),
	@parmtargetdate date,
	@parmremarks varchar(5000),
	@parmorderedby varchar(30),
	@parmaction varchar(10),
	@parmsuppid varchar(20),
	@parmordertype varchar(10)
AS
BEGIN
	SET NOCOUNT ON;
	
	-- 1. THE CULPRIT FIXED: Using JOINs instead of nested = Subqueries. select TOP(1) * FROM PODETAILS select TOP(1) * FROM InventoryCost
    -- This is much faster and completely eliminates the "more than 1 value" crash.
	--UPDATE pd 
	--SET 
	--	pd.TotalCost = pd.Quantity * pd.Cost,
	--	pd.isVat = ISNULL(p.isVat, 0) -- Safely handles if the category is missing
	--FROM PODETAILS pd
	--INNER JOIN Products p ON pd.OrderCode = p.ProductCode AND p.BranchCode = @parmbranch
	--WHERE pd.ShipmentNo = @parmshipmentno
	--and pd.SupplierID=@parmsuppid;

	;WITH CTE_UpdateData AS (
        SELECT 
            pd.TotalCost, 
            pd.Quantity, 
            pd.Cost, 
            pd.isVat, 
            ISNULL(p.isVat, 0) AS NewIsVat
        FROM PODETAILS pd
        LEFT JOIN Products p ON pd.OrderCode = p.ProductCode AND p.BranchCode = @parmbranch
        WHERE pd.ShipmentNo = @parmshipmentno
    )
    UPDATE CTE_UpdateData
    SET 
        TotalCost = Quantity * Cost,
        isVat = NewIsVat;

	
    -- 2. INSERT OR UPDATE LOGIC
	IF @parmaction <> 'EDITPO'
	BEGIN
		INSERT INTO [dbo].[POSUMMARY]
           ([ShipmentNo],[BranchCode],[SupplierID],[TargetDate]
           ,[TotalItems],[TotalQty],[TotalCost],[TotalActualQty]
           ,[TotalActualCost],[Status],[OrderType],[DateOrder]
           ,[OrderedBy],[ApprovedDate],[ApprovedBy],[ReceivedDate]
           ,[ReceivedBy],[Remarks])
		SELECT 
            @parmshipmentno,
            @parmbranch,
            SupplierID,
            @parmtargetdate,
            COUNT(*),
            SUM(Quantity),
            SUM(TotalCost),
            0,
            0,
            'FOR APPROVAL',
            OrderType,
            GETDATE(),
            @parmorderedby,
            ' ',
            ' ',
            ' ',
            ' ',
            @parmremarks
		FROM PODETAILS WITH(NOLOCK)
		WHERE ShipmentNo = @parmshipmentno 
		  AND SupplierID NOT IN (SELECT SupplierID FROM POSUMMARY WHERE ShipmentNo = @parmshipmentno) 
		GROUP BY SupplierID, OrderType;
	END
	ELSE
	BEGIN
        -- OPTIMIZATION: Calculate the aggregates once into variables
        DECLARE @TotalItems INT = 0;
        DECLARE @TotalQty FLOAT = 0; 

        SELECT 
            @TotalItems = COUNT(*), 
            @TotalQty = ISNULL(SUM(Quantity), 0) 
        FROM PODETAILS WITH(NOLOCK) 
        WHERE ShipmentNo = @parmshipmentno;

        -- Apply the pre-calculated variables cleanly
		UPDATE POSUMMARY 
        SET
			SupplierID = @parmsuppid,
			TotalItems = @TotalItems,
			TotalQty = @TotalQty,
			Remarks = @parmremarks
		WHERE ShipmentNo = @parmshipmentno;

		UPDATE PODETAILS 
		SET SupplierID = @parmsuppid
		WHERE ShipmentNo = @parmshipmentno;
	END

END