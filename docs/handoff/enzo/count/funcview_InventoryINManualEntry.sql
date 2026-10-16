 
CREATE   FUNCTION [dbo].[funcview_InventoryINManualEntry]
(
    @parmid INT
)
RETURNS TABLE
AS --SELECT * FROM TempInventoryIN
RETURN
(
    SELECT * FROM dbo.TempInventoryIN a WITH (NOLOCK)
    WHERE a.ID = @parmid
     
);
