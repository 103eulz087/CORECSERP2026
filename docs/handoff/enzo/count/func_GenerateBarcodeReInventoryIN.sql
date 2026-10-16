CREATE   FUNCTION [dbo].[func_GenerateBarcodeReInventoryIN]
(
  
    @parmbatchid varchar(20)     -- Increased from 5 (PO numbers are rarely just 5 chars)
   , @parmprdcd varchar(20)    -- Increased from 5 
   , @parmqty varchar(15)      -- Increased to accommodate larger weights
   
)
RETURNS varchar(100)           -- Increased return length to ensure the whole string fits
AS
BEGIN

    DECLARE @seqno varchar(5)
          , @barcode varchar(100)
          , @batchidleadingzero varchar(5)
          , @slet varchar(5)
          , @snum varchar(5)
          , @cleanQty varchar(15)

   
    -- Calculate Sequence (WARNING: Prone to race conditions under heavy concurrent load) select top 1 * FROM InventoryIN
    SELECT @seqno = ISNULL(COUNT(*), 0) + 1
    FROM [InventoryINMonthEnd] WITH(NOLOCK) 
    WHERE ID = @parmbatchid 

 
	SELECT @seqno = RIGHT(REPLICATE('0', 4) + CAST(@seqno AS varchar(4)), 4)
	SELECT @batchidleadingzero = RIGHT(REPLICATE('0', 5) + CAST(@parmbatchid AS varchar(5)), 5)

    -- Clean formatting issues out of the quantities
    -- Removes spaces and decimals to create a flat string for the barcode
    SET @cleanQty = REPLACE(RTRIM(LTRIM(@parmqty)), '.', '')

    -- Build the barcode safely D01 01022 10015 02345 1
    SET @barcode = CONCAT(
        LTRIM(RTRIM('D01')), 
        LTRIM(RTRIM(@batchidleadingzero)), 
        LTRIM(RTRIM(@parmprdcd)),  
        @cleanQty,
        @seqno
        
    )

    RETURN @barcode

END