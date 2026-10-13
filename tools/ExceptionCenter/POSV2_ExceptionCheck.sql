/* ================================================================
   Exception Center: POS V2 health check (phase 5, 2026-10-13)
   ================================================================
   READ-ONLY. Safe to run any time (temp tables only). Run it after every change to a POS V2 procedure, on STAGING
   after deploying POS V2, and on a schedule once terminals sell (daily at first).

   Result set 1 = one row per check: how many exceptions, what it means, what to do. A healthy database shows
                  Found = 0 on CRITICAL / HIGH (MEDIUM rows are work lists: shortages, long shifts, review flags).
   Result set 2 = the exception rows themselves.

   The ties it tests (proven by the phase 3-5 tests):
     * a closed shift's GL ticket balances, is booked once, and its AR leg = the shift's charges less charge refunds;
     * the shift's stored cost = the cost of the lots its sales took / its returns put back;
     * a POS charge invoice (TransactionChargeSales) = the sale's charge less what returns took off it, and its
       client-ledger rows net to the same amount;
     * a voided sale gave its lots back (the same quantity);
     * a closed shift's VAT split adds up to its net (what BIR reads), and the accumulated grand total chains from
       one Z-reading to the next and matches what the terminal printed.
   Accounts come from the mapping (POSV2-SHIFT), never hard-coded.

   Work lists with no "done" marker (P07 voids, P10 customer credit, P11 review flags, P13 OR gaps) look back
   @SinceDays only, so they clear by themselves once handled and older; set it higher for an audit.

   When a new failure mode is found, add a check here (next free P code) and record it in docs/CLAUDE_WORKLOG.md.
   ================================================================ */
SET NOCOUNT ON;

DECLARE @Tol DECIMAL(18,2) = 0.005;
DECLARE @SinceDays INT = 45;
DECLARE @Since DATETIME2(0) = DATEADD(DAY, -@SinceDays, SYSDATETIME());

IF OBJECT_ID('dbo.POSV2_Shift', 'U') IS NULL
BEGIN
    SELECT 'POS V2 is not installed in this database (SQL/POSV2 scripts 01-03).' AS Note;
    RETURN;
END

IF OBJECT_ID('tempdb..#X') IS NOT NULL DROP TABLE #X;
CREATE TABLE #X (
    CheckCode VARCHAR(5)    NOT NULL,
    Branch    VARCHAR(10)   NULL,
    Ref       VARCHAR(80)   NULL,      -- terminal Z# / OR no. / return no. / invoice
    Expected  DECIMAL(18,2) NULL,
    Actual    DECIMAL(18,2) NULL,
    Detail    VARCHAR(400)  NULL
);

DECLARE @ARAcct VARCHAR(50) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping
                               WHERE Origin = 'POSV2' AND Mnemonic = 'POSV2-SHIFT' AND AmountType = 'CHARGE' AND DebitCredit = 'D' AND IsActive = 1 ORDER BY Seq);

------------------------------------------------------------------
-- G. GL of the shifts
------------------------------------------------------------------
-- P01 a shift's GL ticket doesn't balance, or a POSTED shift with something to book has no ticket
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P01', s.BranchCode, t.TerminalCode + ' Z#' + CAST(s.ZNo AS VARCHAR(10)), d.Dr, d.Cr,
       CASE WHEN d.TicketNumber IS NULL THEN 'GLStatus POSTED with ticket ' + ISNULL(s.GLTicketNumber, '(none)') + ' but no ticket lines'
            ELSE 'ticket ' + s.GLTicketNumber + ' DR <> CR' END
FROM dbo.POSV2_Shift s
INNER JOIN dbo.POSV2_Terminal t ON t.TerminalID = s.TerminalID
OUTER APPLY (SELECT MAX(TicketNumber) AS TicketNumber, SUM(Debit) AS Dr, SUM(Credit) AS Cr FROM dbo.TicketDetails WHERE TicketNumber = s.GLTicketNumber) d
WHERE s.Status = 'CLOSED' AND s.GLStatus = 'POSTED' AND s.GLTicketNumber IS NOT NULL
  AND (d.TicketNumber IS NULL OR ABS(d.Dr - d.Cr) > @Tol);
-- ... and POSTED with no ticket at all although the shift had something to book (only 'Nothing to book' may have none)
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P01', s.BranchCode, t.TerminalCode + ' Z#' + CAST(s.ZNo AS VARCHAR(10)), s.NetAmount, NULL,
       'GLStatus POSTED without a ticket: ' + LEFT(ISNULL(CAST(s.GLMessage AS VARCHAR(400)), '(no message)'), 300)
FROM dbo.POSV2_Shift s INNER JOIN dbo.POSV2_Terminal t ON t.TerminalID = s.TerminalID
WHERE s.Status = 'CLOSED' AND s.GLStatus = 'POSTED' AND s.GLTicketNumber IS NULL
  AND ISNULL(CAST(s.GLMessage AS NVARCHAR(1000)), N'') NOT LIKE N'Nothing to book%'
  AND (ISNULL(s.GrossAmount, 0) <> 0 OR ISNULL(s.ReturnGross, 0) <> 0 OR ISNULL(s.OverShort, 0) <> 0);

-- P02 more than one POSV2-SHIFT ticket for one shift (booked twice)
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P02', m.BranchCode, m.ReferenceNumber, 1, COUNT(*), 'tickets ' + MIN(m.TicketNumber) + ' .. ' + MAX(m.TicketNumber)
FROM dbo.TicketMaster m
WHERE m.Mnemonic = 'POSV2-SHIFT'
GROUP BY m.BranchCode, m.ReferenceNumber, m.ReferenceKey
HAVING COUNT(*) > 1;

-- P03 the AR leg of a shift's ticket <> the shift's charges less charge refunds (the netted 101030101 line)
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P03', s.BranchCode, t.TerminalCode + ' Z#' + CAST(s.ZNo AS VARCHAR(10)),
       ISNULL(s.ChargeSales, 0) - ISNULL(s.ChargeRefunds, 0), ISNULL(g.Net, 0), 'AR account ' + ISNULL(@ARAcct, '?') + ' on ticket ' + s.GLTicketNumber
FROM dbo.POSV2_Shift s
INNER JOIN dbo.POSV2_Terminal t ON t.TerminalID = s.TerminalID
OUTER APPLY (SELECT SUM(Debit - Credit) AS Net FROM dbo.TicketDetails WHERE TicketNumber = s.GLTicketNumber AND AccountCode = @ARAcct) g
WHERE @ARAcct IS NOT NULL AND s.Status = 'CLOSED' AND s.GLStatus = 'POSTED' AND s.GLTicketNumber IS NOT NULL
  AND ABS((ISNULL(s.ChargeSales, 0) - ISNULL(s.ChargeRefunds, 0)) - ISNULL(g.Net, 0)) > @Tol;
-- without the mapping row the check can't run: one finding instead of one per shift
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P03', NULL, 'POSV2-SHIFT mapping', NULL, NULL, 'No active CHARGE debit row in JournalEntryMapping (POSV2 / POSV2-SHIFT): charge shifts can''t post AR'
WHERE @ARAcct IS NULL AND EXISTS (SELECT 1 FROM dbo.POSV2_Shift WHERE ISNULL(ChargeSales, 0) <> 0 OR ISNULL(ChargeRefunds, 0) <> 0);

-- P04 a closed shift whose GL isn't booked (PENDING / FAILED): its sales are not in the GL yet
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P04', s.BranchCode, t.TerminalCode + ' Z#' + CAST(s.ZNo AS VARCHAR(10)), s.NetAmount, NULL,
       s.GLStatus + ': ' + LEFT(ISNULL(CAST(s.GLMessage AS VARCHAR(400)), ''), 360)
FROM dbo.POSV2_Shift s INNER JOIN dbo.POSV2_Terminal t ON t.TerminalID = s.TerminalID
WHERE s.Status = 'CLOSED' AND s.GLStatus <> 'POSTED';

------------------------------------------------------------------
-- C. Cost and stock
------------------------------------------------------------------
-- P05 the shift's stored cost <> the cost of the lots its (not voided) sales took
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P05', s.BranchCode, t.TerminalCode + ' Z#' + CAST(s.ZNo AS VARCHAR(10)), ISNULL(c.Cost, 0), s.CostTotal, 'shift CostTotal vs its sale lines'' CostTotal'
FROM dbo.POSV2_Shift s
INNER JOIN dbo.POSV2_Terminal t ON t.TerminalID = s.TerminalID
OUTER APPLY (SELECT SUM(l.CostTotal) AS Cost FROM dbo.POSV2_SaleLine l INNER JOIN dbo.POSV2_Sale x ON x.SaleGUID = l.SaleGUID
             WHERE x.ShiftGUID = s.ShiftGUID AND x.Status <> 'VOIDED') c
WHERE s.Status = 'CLOSED' AND ABS(ISNULL(c.Cost, 0) - ISNULL(s.CostTotal, 0)) > @Tol;

-- P06 the shift's stored return cost <> the cost of the lots its returns put back
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P06', s.BranchCode, t.TerminalCode + ' Z#' + CAST(s.ZNo AS VARCHAR(10)), ISNULL(c.Cost, 0), s.ReturnCost, 'shift ReturnCost vs its returns'' lots'
FROM dbo.POSV2_Shift s
INNER JOIN dbo.POSV2_Terminal t ON t.TerminalID = s.TerminalID
OUTER APPLY (SELECT SUM(rl.CostAmount) AS Cost FROM dbo.POSV2_ReturnLot rl INNER JOIN dbo.POSV2_Return r ON r.ReturnGUID = rl.ReturnGUID
             WHERE r.ShiftGUID = s.ShiftGUID) c
WHERE s.Status = 'CLOSED' AND ABS(ISNULL(c.Cost, 0) - ISNULL(s.ReturnCost, 0)) > @Tol;

-- P07 a voided sale (last @SinceDays) whose 'POS VOID' stock-ledger rows don't put back what its lots took
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P07', s.BranchCode, s.ORNo, lot.Qty, ISNULL(led.Qty, 0),
       'voided ' + CONVERT(VARCHAR(16), s.VoidedAt, 120) + '; ledger rows ''POS VOID OR#' + s.ORNo + ''' (QtyIN) vs the lots taken'
FROM dbo.POSV2_Sale s
CROSS APPLY (SELECT SUM(Qty) AS Qty FROM dbo.POSV2_SaleLot WHERE SaleGUID = s.SaleGUID) lot
OUTER APPLY (SELECT SUM(l.QtyIN) AS Qty FROM dbo.InventoryLedger l
             WHERE l.OriginBranch = s.BranchCode AND l.Remarks = 'POS VOID OR#' + s.ORNo
               AND l.DateProcessed >= DATEADD(DAY, -1, CAST(s.VoidPostedAt AS DATETIME))) led
WHERE s.Status = 'VOIDED' AND s.VoidPostedAt >= @Since AND lot.Qty > 0
  AND ABS(lot.Qty - ISNULL(led.Qty, 0)) > 0.0005;

------------------------------------------------------------------
-- A. AR (charge sales)
------------------------------------------------------------------
-- P08 a POS charge invoice <> the sale's charge less what returns took off it (0 when voided)
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P08', s.BranchCode, s.ORNo + ' / ' + s.ARReferenceNo,
       CASE WHEN s.Status = 'VOIDED' THEN 0 ELSE p.Charge - ISNULL(r.Applied, 0) END, tcs.TotalAmount,
       'customer ' + s.CustomerKey + '; ' + CAST(ISNULL(tcs.N, 0) AS VARCHAR(10)) + ' invoice row(s), ' + ISNULL(tcs.PayStatus, '(missing)')
FROM dbo.POSV2_Sale s
CROSS APPLY (SELECT SUM(Amount) AS Charge FROM dbo.POSV2_Payment WHERE SaleGUID = s.SaleGUID AND PaymentType = 'CHARGE') p
OUTER APPLY (SELECT SUM(ChargeRefund - ChargeExcess) AS Applied FROM dbo.POSV2_Return WHERE OrigSaleGUID = s.SaleGUID) r
OUTER APPLY (SELECT COUNT(*) AS N, SUM(t.TotalAmount) AS TotalAmount, MAX(t.PayStatus) AS PayStatus FROM dbo.TransactionChargeSales t
             WHERE t.CustomerKey = s.CustomerKey AND t.InvoiceNo = s.ORNo AND t.ReferenceNo = s.ARReferenceNo) tcs
WHERE p.Charge > 0
  AND (ISNULL(tcs.N, 0) <> 1 OR ABS(tcs.TotalAmount - CASE WHEN s.Status = 'VOIDED' THEN 0 ELSE p.Charge - ISNULL(r.Applied, 0) END) > @Tol);

-- P09 the client-ledger rows of a POS charge invoice (charge, void, return, payments) don't net to its open balance
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P09', s.BranchCode, s.ORNo + ' / ' + s.ARReferenceNo, tcs.Balance, cl.Net, 'customer ' + s.CustomerKey + ' (ClientLedger rows with InvoiceNo = the OR no.)'
FROM dbo.POSV2_Sale s
INNER JOIN dbo.TransactionChargeSales tcs ON tcs.CustomerKey = s.CustomerKey AND tcs.InvoiceNo = s.ORNo AND tcs.ReferenceNo = s.ARReferenceNo
OUTER APPLY (SELECT SUM(ISNULL(Debit, 0) - ISNULL(Credit, 0)) AS Net FROM dbo.ClientLedger
             WHERE AccountKey = s.CustomerKey AND InvoiceNo = s.ORNo) cl
WHERE s.ARReferenceNo IS NOT NULL AND ABS(ISNULL(tcs.Balance, 0) - ISNULL(cl.Net, 0)) > @Tol;

-- P10 a charge refund above the invoice's open balance went to customer credit (20115): not in the AR credit pool yet
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P10', r.BranchCode, r.ReturnNo, 0, r.ChargeExcess, 'customer ' + ISNULL(s.CustomerKey, '?') + ', OR ' + s.ORNo + ': give it back or apply it by hand'
FROM dbo.POSV2_Return r INNER JOIN dbo.POSV2_Sale s ON s.SaleGUID = r.OrigSaleGUID
WHERE r.ChargeExcess > 0 AND r.PostedAt >= @Since;

------------------------------------------------------------------
-- W. Work lists
------------------------------------------------------------------
-- P11 sales / returns posted with NeedsReview (a rule changed since an offline event, over the limit, over-return, ...)
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P11', BranchCode, ORNo, NULL, NetAmount, LEFT(ReviewNote, 400) FROM dbo.POSV2_Sale WHERE NeedsReview = 1 AND PostedAt >= @Since
UNION ALL
SELECT 'P11', BranchCode, ReturnNo, NULL, NetAmount, LEFT(ReviewNote, 400) FROM dbo.POSV2_Return WHERE NeedsReview = 1 AND PostedAt >= @Since;

-- P12 open shortages (sold with no stock on record: stock adjustment / receiving to do)
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P12', sh.BranchCode, s.ORNo + ' line ' + CAST(sh.[LineNo] AS VARCHAR(10)), sh.QtySold, sh.QtyDeducted,
       sh.ProductCode + ' short ' + CONVERT(VARCHAR(30), sh.QtyShort) + ' since ' + CONVERT(VARCHAR(16), sh.CreatedAt, 120)
FROM dbo.POSV2_Shortage sh INNER JOIN dbo.POSV2_Sale s ON s.SaleGUID = sh.SaleGUID
WHERE sh.Status = 'OPEN';

-- P13 shifts open more than a day, and gaps in a terminal's OR series on the server (an OR still on a terminal / lost)
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P13', s.BranchCode, t.TerminalCode + ' Z#' + CAST(s.ZNo AS VARCHAR(10)), NULL, s.BeginningCash,
       'open since ' + CONVERT(VARCHAR(16), s.OpenedAt, 120) + '; terminal last seen ' + ISNULL(CONVERT(VARCHAR(16), t.LastSeenAt, 120), '?')
FROM dbo.POSV2_Shift s INNER JOIN dbo.POSV2_Terminal t ON t.TerminalID = s.TerminalID
WHERE s.Status = 'OPEN' AND s.OpenedAt < DATEADD(DAY, -1, SYSDATETIME());
;WITH Seq AS (
    SELECT s.TerminalID, s.BranchCode, TRY_CAST(SUBSTRING(s.ORNo, LEN(t.ORPrefix) + 2, 30) AS BIGINT) AS N
    FROM dbo.POSV2_Sale s INNER JOIN dbo.POSV2_Terminal t ON t.TerminalID = s.TerminalID
    WHERE s.SaleDateTime >= @Since      -- a gap older than that was looked at already (or is a known lost / refused OR)
), Gaps AS (
    SELECT TerminalID, BranchCode, N, LEAD(N) OVER (PARTITION BY TerminalID ORDER BY N) AS NextN FROM Seq
)
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P13', g.BranchCode, t.TerminalCode + ' OR gap', g.N + 1, g.NextN - 1,
       'ORs ' + CAST(g.N + 1 AS VARCHAR(20)) + ' to ' + CAST(g.NextN - 1 AS VARCHAR(20)) + ' are not on the server (still on the terminal, refused, or lost)'
FROM Gaps g INNER JOIN dbo.POSV2_Terminal t ON t.TerminalID = g.TerminalID
WHERE g.NextN > g.N + 1;

------------------------------------------------------------------
-- B. BIR figures
------------------------------------------------------------------
-- P14 a closed shift's VAT split isn't its net (sales, or returns): the Z-reading / E-Sales / 2550M would be off
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P14', s.BranchCode, t.TerminalCode + ' Z#' + CAST(s.ZNo AS VARCHAR(10)),
       CASE WHEN v.SalesOff = 1 THEN s.NetAmount ELSE s.ReturnNet END,
       CASE WHEN v.SalesOff = 1 THEN s.VatableSales + s.VatAmount + s.VatExemptSales + s.ZeroRatedSales
            ELSE ISNULL(s.ReturnVatable, 0) + ISNULL(s.ReturnVat, 0) + ISNULL(s.ReturnExempt, 0) END,
       CASE WHEN v.SalesOff = 1 THEN 'sales: VATable + VAT + exempt + zero-rated vs net' ELSE 'returns: VATable + VAT + exempt vs refunded net' END
FROM dbo.POSV2_Shift s INNER JOIN dbo.POSV2_Terminal t ON t.TerminalID = s.TerminalID
CROSS APPLY (SELECT CASE WHEN ABS(s.VatableSales + s.VatAmount + s.VatExemptSales + s.ZeroRatedSales - s.NetAmount) > @Tol THEN 1 ELSE 0 END AS SalesOff) v
WHERE s.Status = 'CLOSED'
  AND (v.SalesOff = 1 OR ABS(ISNULL(s.ReturnVatable, 0) + ISNULL(s.ReturnVat, 0) + ISNULL(s.ReturnExempt, 0) - ISNULL(s.ReturnNet, 0)) > @Tol);

-- P15 the accumulated grand total doesn't chain (before <> the previous Z's after, or after - before <> the shift's net),
--     or the terminal printed a different one on its Z-reading
;WITH Z AS (
    SELECT s.*, LAG(s.AccumulatedAfter) OVER (PARTITION BY s.TerminalID ORDER BY s.ZNo) AS PrevAfter,
           ROW_NUMBER() OVER (PARTITION BY s.TerminalID ORDER BY s.ZNo) AS Rn
    FROM dbo.POSV2_Shift s WHERE s.Status = 'CLOSED' AND s.AccumulatedAfter IS NOT NULL
)
INSERT #X (CheckCode, Branch, Ref, Expected, Actual, Detail)
SELECT 'P15', z.BranchCode, t.TerminalCode + ' Z#' + CAST(z.ZNo AS VARCHAR(10)),
       CASE WHEN z.TerminalAccumulatedAfter IS NOT NULL AND z.TerminalAccumulatedAfter <> z.AccumulatedAfter THEN z.AccumulatedAfter
            WHEN z.Rn > 1 AND z.AccumulatedBefore <> z.PrevAfter THEN z.PrevAfter
            ELSE z.AccumulatedBefore + z.NetAmount END,
       CASE WHEN z.TerminalAccumulatedAfter IS NOT NULL AND z.TerminalAccumulatedAfter <> z.AccumulatedAfter THEN z.TerminalAccumulatedAfter
            WHEN z.Rn > 1 AND z.AccumulatedBefore <> z.PrevAfter THEN z.AccumulatedBefore
            ELSE z.AccumulatedAfter END,
       CASE WHEN z.TerminalAccumulatedAfter IS NOT NULL AND z.TerminalAccumulatedAfter <> z.AccumulatedAfter THEN 'printed on the terminal''s Z-reading (Actual) vs the server''s (Expected)'
            WHEN z.Rn > 1 AND z.AccumulatedBefore <> z.PrevAfter THEN 'before (Actual) vs the previous Z-reading''s after (Expected)'
            ELSE 'after (Actual) vs before + net (Expected)' END
FROM Z z INNER JOIN dbo.POSV2_Terminal t ON t.TerminalID = z.TerminalID
WHERE (z.TerminalAccumulatedAfter IS NOT NULL AND z.TerminalAccumulatedAfter <> z.AccumulatedAfter)
   OR (z.Rn > 1 AND z.AccumulatedBefore <> z.PrevAfter)
   OR z.AccumulatedAfter - z.AccumulatedBefore <> z.NetAmount;

------------------------------------------------------------------
DECLARE @Info TABLE (CheckCode VARCHAR(5), Area VARCHAR(10), Severity VARCHAR(10), Meaning VARCHAR(300), Action VARCHAR(300));
INSERT @Info VALUES
('P01', 'GL',    'CRITICAL', 'A closed shift''s GL ticket doesn''t balance, or is missing although the shift says POSTED.', 'Check the POSV2-SHIFT mapping rows; re-post the shift (spu_POSV2_PostPendingShiftGL after resetting its GLStatus).'),
('P02', 'GL',    'CRITICAL', 'A shift was booked to the GL more than once.', 'Delete the duplicate ticket (same ReferenceKey = ShiftGUID).'),
('P03', 'GL',    'CRITICAL', 'A shift ticket''s AR line differs from the shift''s charges less charge refunds.', 'Compare the shift''s charge sales / returns with its ticket; AR in the GL is off by the difference.'),
('P04', 'GL',    'HIGH',     'A closed shift''s GL isn''t booked (PENDING / FAILED): its sales are not in the GL.', 'Fix the cause in GLMessage (closed month, mapping), then spu_POSV2_PostPendingShiftGL. A GL month can''t close until then (59908).'),
('P05', 'Stock', 'CRITICAL', 'A shift''s stored cost differs from the cost of the lots its sales took.', 'A sale was changed after the close; re-derive the shift (support).'),
('P06', 'Stock', 'CRITICAL', 'A shift''s stored return cost differs from the lots its returns put back.', 'A return was changed after the close; re-derive the shift (support).'),
('P07', 'Stock', 'CRITICAL', 'A voided sale (last @SinceDays days) whose POS VOID ledger rows don''t put back the quantity its lots took.', 'Restore the missing lots (spu_InvFIFO_Restore) for that OR.'),
('P08', 'AR',    'CRITICAL', 'A POS charge invoice differs from the sale''s charge less what returns took off it, is missing, or is there more than once.', 'Correct TransactionChargeSales for that invoice; check for a payment posted against the wrong invoice.'),
('P09', 'AR',    'HIGH',     'The client-ledger rows of a POS invoice don''t net to its open balance.', 'Look for a ledger row missing or doubled for that OR (charge, void, return, payment). Assumes every row of the invoice carries the OR no. in InvoiceNo: confirm on the first real Client Payments of a POS invoice.'),
('P10', 'AR',    'MEDIUM',   'A charge refund (last @SinceDays days) above the invoice''s open balance is customer credit (20115), not in the AR credit pool.', 'Refund the customer or apply it by hand (no settled marker yet; the row drops off after @SinceDays).'),
('P11', 'Review','MEDIUM',   'A sale / return (last @SinceDays days) posted with NeedsReview (rule changed since an offline event, over the credit limit, over-return, ...).', 'Read ReviewNote; correct by hand if needed.'),
('P12', 'Review','MEDIUM',   'An open shortage: sold with no stock on record at the branch.', 'Receive / adjust the stock, then resolve the shortage.'),
('P13', 'Review','MEDIUM',   'A shift open for more than a day, or a gap in a terminal''s OR series on the server.', 'Close the shift (or force-close it: spu_POSV2_ForceCloseShift); find the missing ORs on the terminal (needs attention).'),
('P14', 'BIR',   'CRITICAL', 'A closed shift''s VAT split (VATable + VAT + exempt + zero-rated) isn''t its net, for its sales or its returns.', 'The BIR reports read this split: find the sale / return line that broke it (each is checked exactly on posting since phase 5).'),
('P15', 'BIR',   'HIGH',     'The accumulated grand total doesn''t chain between Z-readings, or the terminal printed a different one.', 'BIR reads the server''s figure; compare the terminal''s Z-reading slips with POS V2 Reports (Z-readings) and correct the terminal.');

SELECT i.CheckCode, i.Area, i.Severity, COUNT(x.CheckCode) AS Found, i.Meaning, i.Action
FROM @Info i
LEFT JOIN #X x ON x.CheckCode = i.CheckCode
GROUP BY i.CheckCode, i.Area, i.Severity, i.Meaning, i.Action
ORDER BY CASE i.Severity WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END, i.CheckCode;

SELECT x.CheckCode, i.Severity, x.Branch, x.Ref, x.Expected, x.Actual,
       CAST(ISNULL(x.Actual, 0) - ISNULL(x.Expected, 0) AS DECIMAL(18,2)) AS Difference, x.Detail
FROM #X x
INNER JOIN @Info i ON i.CheckCode = x.CheckCode
ORDER BY CASE i.Severity WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END, x.CheckCode, x.Branch, x.Ref;
