






CREATE PROCEDURE [dbo].[sp_ExcelInvMonthEndCount2] 
    @param1 VARCHAR(10),
    @param2 VARCHAR(10)
AS
BEGIN

DECLARE @monthend DATE = GETDATE()

	SELECT
		Branch AS BranchCode,
		ShipmentNo,
		DateReceived,
		ExpiryDate,
		[Product],
		[Description],
		Barcode,
		Available,
		Cost,
		FORMAT(Cost * Available, 'N2') AS TotalCost,
		ReferenceCode
	FROM dbo.Inventory
	WHERE
		Branch = '888' 
		AND 
		(
			-- Condition Block 1 (From your first query)
			(
				Available > 0 AND
				ReferenceCode LIKE 'INVIN-%' AND
				CAST(REPLACE(ReferenceCode, 'INVIN-', '') AS INT) >= @param1
			)
			OR
			-- Condition Block 2 (From your second query)
			(
				DateReceived = EOMONTH(@monthend) AND
				BatchCode IS NULL AND
				ReferenceCode IS NULL
			)
		)
	ORDER BY
		ReferenceCode DESC;

END


