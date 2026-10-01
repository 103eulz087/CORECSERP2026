/* ================================================================
   2026-10-01c: STS In Transit correction (one-off data fix)
   ================================================================
   Needs 2026-10-01b_STS_Lifecycle_Fixes.sql (spu_STS_SyncInTransit).

   For every saved STS (TransferOrderSummary.isProcess = 1) whose head-office
   In Transit (IT-HO-* minus ITR-HO-* on 888) differs from the cost of its
   live FIFO lots (all VAT-exempt: client rule, needs 2026-10-01e), this runs
   spu_STS_SyncInTransit, which posts the difference dated today:
     * a duplicate transfer-out from a second Save is reversed (ITR-HO-*);
     * any In Transit booked on the VAT account is moved to VAT-exempt.
   Nothing else is touched (no stock, no lines, no receipt tickets).

   On STAGING (checked 2026-10-01 17:xx) this is POs 11699, 11700, 11701,
   14100: 11700 / 11701 carry the second Save of 2026-10-01 13:09 / 13:18
   (tickets 18554 / 18547, 3,989,577.64 together).

   Prints the POs it corrected and the check afterwards (must be empty).
   Re-runnable: a PO that already agrees posts nothing.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('dbo.spu_STS_SyncInTransit', 'P') IS NULL
    THROW 59620, 'Run 2026-10-01b_STS_Lifecycle_Fixes.sql first (spu_STS_SyncInTransit is missing).', 1;

DECLARE @TransitVat VARCHAR(50) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'IT-HO-VAT' AND DebitCredit = 'D' AND IsActive = 1 ORDER BY Seq);
DECLARE @TransitVatEx VARCHAR(50) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'IT-HO-VATEX' AND DebitCredit = 'D' AND IsActive = 1 ORDER BY Seq);

-- POs with cancelled / returned lines whose lots were never restored: the stock is wrong,
-- so they are NOT corrected here (spu_STS_SyncInTransit would refuse them); listed for a decision
SELECT 'skipped: stock never restored' AS step, f.PONumber, f.DeliveryNo, COUNT(*) AS staleLots,
       CAST(SUM(f.QtyDelivered) AS DECIMAL(18,3)) AS staleQty, CAST(SUM(f.TotalCost) AS DECIMAL(18,2)) AS staleCost
FROM dbo.InventoryDeliveryFIFO f
INNER JOIN dbo.DeliveryDetails dd ON dd.DeliveryNo = f.DeliveryNo AND dd.PONumber = f.PONumber AND dd.SeqNo = f.DevDetSeqNo
WHERE f.isErrorCorrect = 0 AND (dd.isCancelled = 1 OR dd.isReturned = 1)
  AND EXISTS (SELECT 1 FROM dbo.TransferOrderSummary s WHERE s.PONumber = f.PONumber)
GROUP BY f.PONumber, f.DeliveryNo;

DECLARE @Todo TABLE (PONumber VARCHAR(10) PRIMARY KEY, DeliveryNo VARCHAR(20), DestBranch VARCHAR(10),
                     TargetVat DECIMAL(18,2), PostedVat DECIMAL(18,2), TargetVatEx DECIMAL(18,2), PostedVatEx DECIMAL(18,2));

;WITH T AS (   -- live shipped cost per PO (all deliveries); the GL is all VAT-exempt (client rule, 2026-10-01e)
    SELECT f.PONumber, MAX(f.DeliveryNo) AS DeliveryNo,
           CAST(0 AS MONEY) AS tVat,
           SUM(f.TotalCost) AS tVatEx
    FROM dbo.InventoryDeliveryFIFO f
    INNER JOIN dbo.DeliveryDetails dd ON dd.DeliveryNo = f.DeliveryNo AND dd.PONumber = f.PONumber AND dd.SeqNo = f.DevDetSeqNo
    WHERE f.isErrorCorrect = 0 AND dd.isCancelled = 0 AND dd.isReturned = 0
      AND EXISTS (SELECT 1 FROM dbo.TransferOrderSummary s WHERE s.PONumber = f.PONumber AND ISNULL(s.isProcess, 0) = 1)
      AND NOT EXISTS (SELECT 1 FROM dbo.InventoryDeliveryFIFO f2
                      INNER JOIN dbo.DeliveryDetails d2 ON d2.DeliveryNo = f2.DeliveryNo AND d2.PONumber = f2.PONumber AND d2.SeqNo = f2.DevDetSeqNo
                      WHERE f2.PONumber = f.PONumber AND f2.isErrorCorrect = 0 AND (d2.isCancelled = 1 OR d2.isReturned = 1))
    GROUP BY f.PONumber),
P AS (
    SELECT tm.ReferenceKey AS PONumber,
           SUM(CASE WHEN td.AccountCode = @TransitVat   THEN td.Debit - td.Credit ELSE 0 END) AS pVat,
           SUM(CASE WHEN td.AccountCode = @TransitVatEx THEN td.Debit - td.Credit ELSE 0 END) AS pVatEx
    FROM dbo.TicketMaster tm
    INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
    WHERE tm.BranchCode = '888' AND tm.Mnemonic IN ('IT-HO-VAT', 'IT-HO-VATEX', 'ITR-HO-VAT', 'ITR-HO-VATEX')
    GROUP BY tm.ReferenceKey)
INSERT INTO @Todo (PONumber, DeliveryNo, DestBranch, TargetVat, PostedVat, TargetVatEx, PostedVatEx)
SELECT T.PONumber, T.DeliveryNo, ds.BranchCode, T.tVat, ISNULL(P.pVat, 0), T.tVatEx, ISNULL(P.pVatEx, 0)
FROM T
LEFT JOIN P ON P.PONumber = T.PONumber
OUTER APPLY (SELECT TOP 1 ISNULL(BranchCode, '') AS BranchCode FROM dbo.DeliverySummary d WHERE d.PONumber = T.PONumber ORDER BY d.DeliveryNo) ds
WHERE ABS(T.tVat - ISNULL(P.pVat, 0)) >= 0.01 OR ABS(T.tVatEx - ISNULL(P.pVatEx, 0)) >= 0.01;

SELECT 'to correct' AS step, PONumber, DeliveryNo, DestBranch,
       TargetVat, PostedVat, TargetVat - PostedVat AS VatChange,
       TargetVatEx, PostedVatEx, TargetVatEx - PostedVatEx AS VatExChange
FROM @Todo ORDER BY PONumber;

BEGIN TRANSACTION;
    DECLARE @po VARCHAR(10), @dev VARCHAR(20), @br VARCHAR(10), @Today DATE = CAST(GETDATE() AS DATE);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT PONumber, DeliveryNo, DestBranch FROM @Todo ORDER BY PONumber;
    OPEN c; FETCH NEXT FROM c INTO @po, @dev, @br;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC dbo.spu_STS_SyncInTransit @PONumber = @po, @DeliveryNo = @dev, @DestBranch = @br,
             @User = 'SYSTEM CORRECTION 2026-10-01', @TicketDate = @Today;
        FETCH NEXT FROM c INTO @po, @dev, @br;
    END
    CLOSE c; DEALLOCATE c;
COMMIT TRANSACTION;

-- tickets just posted
SELECT 'posted' AS step, tm.ReferenceKey AS PONumber, tm.TicketNumber, tm.Mnemonic, CONVERT(VARCHAR(10), tm.TicketDate, 120) AS TicketDate,
       CAST(SUM(td.Debit) AS DECIMAL(18,2)) AS Amount
FROM dbo.TicketMaster tm
INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
WHERE tm.EnteredBy = 'SYSTEM CORRECTION 2026-10-01' AND tm.ReferenceKey IN (SELECT PONumber FROM @Todo)
GROUP BY tm.ReferenceKey, tm.TicketNumber, tm.Mnemonic, tm.TicketDate
ORDER BY tm.ReferenceKey, tm.TicketNumber;
