SET NOCOUNT ON;
PRINT '=== BatchSalesDetails.Barcode: widen varchar(20) -> varchar(50) ===';
GO

-- =============================================
-- BUG: sp_ConfirmOrder ('5130','4293','system',0,'LAPTOP') failed with
-- "String or binary data would be truncated." at its Step 4 INSERT INTO
-- BatchSalesDetails.
--
-- ROOT CAUSE: BatchSalesDetails.Barcode is varchar(20), but the actual
-- barcode values it copies from DeliveryDetails.BarcodeNo (varchar(120))
-- are 22-24 characters (e.g. 'A011092713055000120000' = 22 chars).
-- MAX(LEN(BarcodeNo)) across ALL of DeliveryDetails is 24 -- this wasn't a
-- one-off bad row for this PO, the column has been too narrow generally.
-- TransactionChargeSalesDetails.SKU (also fed from the same barcode value,
-- Step 6) is already varchar(30) and wasn't hit here only because this PO's
-- INSERT never got that far -- it failed earlier, at Step 4.
--
-- FIX: widen to varchar(50), matching the width already used for other
-- string columns in this table (ProcessedBy, MachineUsed) and leaving
-- headroom above the current observed max (24).
-- =============================================

ALTER TABLE dbo.BatchSalesDetails ALTER COLUMN Barcode VARCHAR(50) NULL;
GO

PRINT 'DEPLOYMENT COMPLETE: BatchSalesDetails.Barcode is now varchar(50).';
