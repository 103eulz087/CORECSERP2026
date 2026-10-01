# Partial return (Sales Order + STS): plan

2026-10-01. Plan only; nothing is built or deployed. No database access in the session that wrote this:
SQL object counts come from the Dependency Atlas snapshot (COREX001, 2026-09-30 23:54); everything
else comes from the repo code. The "Verify on DEV first" list below has to be run before building.

Scenario: a Sales Order is DELIVERED (confirmed, invoiced). One line has qty 100. The customer
returns 50. Orders for Approval > Delivered > Return Order lets you tick whole lines only.

---

## 1. What the code does today

### Sales Order

- Entry: `Orders/POForApproval.cs:1212` (Delivered tab, "Return Order") and `:451` (For Delivery tab)
  open `Orders/ReturnSalesOrder.cs`, which sends the ticked lines to `sp_ReturnSalesOrder`
  (TVP `dbo.tt_ReturnSalesOrderLines`).
- The grid is read-only with CheckBoxRowSelect (`ReturnSalesOrder.Designer.cs:207-210`). There is
  nowhere to type a quantity.
- `sp_ReturnSalesOrder` (`SQL/2026-10-01_SalesOrder_Lifecycle_Fixes.sql:555`, VAT legs patched by
  `2026-10-01e`) takes only SeqNo / ProductNo from the TVP and re-reads everything else. Per line it:
  - sets `DeliveryDetails.isReturned = 1` (line 625);
  - restores the line's whole `ActualQty` to its lots, newest consumed first, then sets
    `isErrorCorrect = 1` on every FIFO row of the line (640-669);
  - after confirm: cancels one `BatchSalesDetails` row (paired by product + barcode, 676-685), tags
    `TransactionChargeSalesDetails` rows `ErrorTag = 1` (707-710) and posts SO-RET-VATEX through
    `spu_SO_PostInvoiceReduction` (amount-based; it already handles a partial amount and any excess
    as customer credit).
- So the line is the unit of state in four tables, each with a yes/no flag:
  `DeliveryDetails.isReturned`, `InventoryDeliveryFIFO.isErrorCorrect`,
  `BatchSalesDetails.isCancelled`, `TransactionChargeSalesDetails.ErrorTag`.
- Credit Memo after confirm (`sp_CreditMemo`) already reduces a line by part of its qty, but it is
  shrinkage: the goods do not go back to stock, cost goes to COS OTHERS, once per line
  (`isCreditMemo = 0` filter).
- Fully paid POs are filtered out of the Delivered tab (`POForApproval.cs:126`) and the Paid tab has
  no context menu, so a fully paid order can't be returned or credit-memo'd from the UI.

### STS

- After the branch receives (Delivered), there is no return at all: the Delivered tab of
  `POForApprovalSTS` has no menu.
- Before receipt, a return is whole-line only:
  - Head office: `AddBranchOrderSTS.returnOrder()` (line 354).
  - Unticked rows at receiving: `ReceivedSTSBatchModeFIFO.ReturnUnreceivedItems()`.
  - Both call `sp_ReverseSTSInventoryTransfer`. On JFC it calls `sp_CancelDeliveryFIFOJFC`, which
    restores every lot of the line and ignores `@parmqty`.
- At receiving, a received qty below the shipped qty is booked as a loss on head office (STS-SHORT,
  DR COS OTHERS / CR In Transit). If the other 50 went back on the truck, the stock is not restored.

## 2. Why not a "returned qty" column

Every reader of those flags would have to learn the new column. Live SQL objects that reference each
table (Atlas, `_OLD_` / dated backups excluded):

| Table | SQL objects | C# files |
|---|---|---|
| DeliveryDetails | 54 | 23 |
| InventoryDeliveryFIFO | 39 | 0 |
| BatchSalesDetails (shared with POS) | 43 | 27 |
| TransactionChargeSalesDetails | 5 | 0 |

Also, `InventoryDeliveryFIFO` is inserted positionally (`VALUES` with no column list) by at least the
DispatchPerBarcode posting proc (`SQL/2026-08-24_DispatchPerBarcode_NewModule.sql:686`), so a new
column there breaks that proc. Same lesson as `TicketDetails` (worklog Feature 5).

## 3. Design: split the line, then return the split part

A partial return of r from line L becomes:
1. Split L into L (live, qty − r) and a twin line L' (qty r), moving the matching lots to L'.
2. Run the existing whole-line return on L'.

After step 1 every table still holds "live" and "fully returned" lines only, so the views, reports,
confirm, credit memo, `spu_STS_SyncInTransit` and the Exception Center checks keep working unchanged.
Each return event has its own line, its own `ReturnedOrderDetails` row and its own stock-ledger rows.
`CreditMemoRepDevEx`'s return print (`QtyDelivered × SellingPrice` from `ReturnedOrderDetails`)
shows the right amount without a change.

### 3.1 New `spu_DeliveryLine_Split` (shared by SO and STS)

- Parameters: `@PONumber, @DeliveryNo, @SeqNo, @SplitQty, @ExpectedQty, @User, @NewSeqNo OUTPUT`.
  Must run inside the caller's transaction: THROW when `@@TRANCOUNT = 0`, the same rule as
  `spu_SO_PostInvoiceReduction`.
- Lock the line `WITH (UPDLOCK, HOLDLOCK)`. It must not be returned or cancelled, and its current
  `ActualQty` must equal `@ExpectedQty`. Otherwise refuse: "the line changed since the screen was
  opened; refresh". This guards against a double click or two users at once, because a qty-based
  operation is not idempotent.
- `0 < @SplitQty < ActualQty`. A full qty is not split; the caller returns the whole line.
- `@NewSeqNo = MAX(SeqNo) + 1` over the PO, under the same range lock the scan procs take.
  - Take the PO max, not the delivery max: `sp_CreditMemo` matches lines by PONumber + SeqNo.
  - SeqNo is computed, not an identity column (`2026-08-01_AddBranchOrder_DevDetSeqNo_Fix.sql:245`).
- Insert L' by copying L with an explicit column list (taken from INFORMATION_SCHEMA on DEV):
  `QtyDelivered = ActualQty = @SplitQty`, `Variance = 0`, `isCreditMemo = 0`.
  It keeps the same `BarcodeNo`, Status, price and isVat.
- Update L: `QtyDelivered -= @SplitQty`, `ActualQty -= @SplitQty`. `Variance` stays on L, so a
  credit memo's shrinkage stays with the line it was booked on.
- FIFO split: walk L's live FIFO rows newest `SequenceNumber` first, like the return's restore order.
  - A row that falls wholly inside `@SplitQty` gets `DevDetSeqNo = @NewSeqNo`.
  - The boundary row gives up part of its qty: insert a new row for that part (explicit 15-column
    list, same lot, same `DateProcessed`, `TotalCost = ROUND(q × Cost, 2)`) and take the same
    amounts off the original row. `TotalCost` and `TotalAmount` per lot are preserved exactly.
  - THROW unless the qty moved equals `@SplitQty`. Lines from before 2026-08-01 can have
    `DevDetSeqNo = 0` and no FIFO link; refuse a partial return on those.
- Recompute `Cost` on L and L' as `SUM(TotalCost) / SUM(QtyDelivered)` of their own live rows (same
  formula as Save).
- The split moves no stock and writes no stock-ledger rows. The return of L' does both.

### 3.2 Sales documents after confirm (SO only): new `spu_SO_SplitSalesLine`

- `BatchSalesDetails`: find the live row for L (product + barcode + SellingPrice + QtySold =
  L's ActualQty before the split, `isCancelled = 0`).
  - Reduce it: QtySold, TotalAmount, SubTotal, TaxTotal (per-line VAT rounding as `sp_ConfirmOrder`).
  - Insert the returned part as its own row with `isCancelled = 1`.
  - Live + cancelled rows add up to the original row, which is what a whole-line return leaves too.
  - No match: THROW. Several identical rows: any one of them; sums are preserved either way.
- `TransactionChargeSalesDetails`: same split per TransCode (SI-VATEX / COGS-VATEX, or SI-VAT /
  SI-VAT-OUT / COGS-VAT).
  - The part rows get `ErrorTag = 1` and `SeqNo = MAX + 1` for the invoice.
  - SI-DISC stays on the kept row.
  - COGS part = the return's cost (3.3), so Exception Center S04 (COGS rows vs SI ticket cost)
    still ties.
- The whole-line pairing code in `sp_ReturnSalesOrder` then skips split lines (already handled).

### 3.3 GL and AR (no mapping change)

- SO-RET-VATEX through `spu_SO_PostInvoiceReduction 'RET'`. Gross = r × price.
- Cost = the cost of the lots actually put back (sum of L' FIFO `TotalCost`), not
  `ROUND(qty × line Cost, 2)`. This keeps GL inventory equal to the stock value restored, and what
  stays in COS is exactly the cost of the lots still sold.
  - Recommended for whole-line returns too. That changes those amounts only by rounding, except on
    credit-memo'd lines (decision D3).
- Invoice: `TotalAmount −= gross`, Balance / PayStatus recomputed. An amount above the unpaid balance
  goes to customer credit (OVERPAY, 20115), all already in `spu_SO_PostInvoiceReduction`.
- Tickets are dated today, so a closed month stays closed.

### 3.4 `sp_ReturnSalesOrder` changes (same proc, one code path)

- New optional last parameter `@ReturnQty dbo.tt_ReturnSalesOrderQty READONLY`
  (SeqNo, ProductNo, ReturnQty).
  - An omitted TVP arrives empty (tested in Feature 1), so the old exe keeps doing whole-line returns
    and SQL can deploy before the exe.
- Use `@Lines.ActualQty`, which the current form already sends, as `@ExpectedQty` for the staleness
  check.
- Per line: ReturnQty missing or equal to ActualQty means a whole-line return. Less than ActualQty
  means split (3.1), plus 3.2 when confirmed, then return L'.
- Fix while here, because twin lines share the barcode and would trigger these every time:
  - The `ErrorTag` update (line 707-710) matches product + barcode only, so it tags every line of
    that product + barcode, the live twin included. Match product + SKU + Quantity, one set per line.
  - `ReturnedOrderSummary` keeps the first return's reason and the latest return's ticket numbers
    only. Write one row per return event to a new `DeliveryLineReturn` table (below).
- New table `dbo.DeliveryLineReturn`, one row per returned line per event:
  - Keys: ReturnNo (one per Submit), Module ('SO' / 'STS'), PONumber, DeliveryNo.
  - The split link: SourceSeqNo and ReturnSeqNo (equal for a whole-line return).
  - Amounts: QtyBefore, ReturnQty, ReturnAmount, ReturnCost.
  - Reason, TicketNumber, CreatedBy, CreatedAt.
  - It is the audit trail of which line was split from which. A dedicated table means no new column
    on the shared tables.

### 3.5 UI: `Orders/ReturnSalesOrder.cs` (+ Designer)

- Load its own grid. Today the caller does it:
  `SELECT v.*, CAST(0 AS DECIMAL(18,3)) AS ReturnQty FROM view_BranchOrderDetails v ...`.
- `ReturnQty` is the only editable column, and only on ticked, not-yet-returned rows
  (`ShowingEditor`, the CreditMemoDevEx pattern).
  - Ticking a row fills in ActualQty; unticking clears it.
  - Valid range: 0 < ReturnQty ≤ ActualQty.
- Return Amount = ReturnQty × SellingPrice, with a footer total. Qty columns N3, amount columns N2
  (CLAUDE.md numeric rule).
- Before posting, a confirm dialog shows the qty and amount per line and in total. Submit stays
  disabled while the call runs.
- Fix: `sp()` (line 123-153) catches the SqlException, shows it, and returns normally, so
  `executeTransfer()` then shows "Successfully Returned!" (line 114) and closes. It has to rethrow or
  return false. Use `using` for the connection.
- `POForApproval`: open the return form with `ShowDialog(this)` and reload the Delivered grid after it
  closes. Optional: the same Return / Credit Memo menu on the Paid tab (decision D4).

### 3.6 STS (phase 2, same split primitive)

- `sp_ReverseSTSInventoryTransfer`: new optional `@parmPartialQty DECIMAL(18,3) = NULL`.
  - When it is less than the line qty: split (3.1), then cancel L' as today.
  - `spu_STS_SyncInTransit` already sets In Transit to the cost of the live lots, so it drops by
    exactly the restored cost.
  - JFC only; refuse it on the non-JFC path.
  - Don't reinterpret `@parmqty`. Callers already send other values there (the receive grid sends
    the typed ActualQty).
- `AddBranchOrderSTS` Return asks for the qty (default: full).
- `ReceivedSTSBatchModeFIFO` gets a "Returned to HO" qty column, with received + returned ≤ shipped.
  - Rows with a returned qty go through the partial reverse before the receive call.
  - Whatever is still missing stays a short receipt (STS-SHORT).
  - The receive side is safe for a twin with the same barcode: every receive reader filters
    `isCancelled = 0 AND isReturned = 0` (`funcview_InventoryDeliveryFIFOForReceiving`,
    `sp_AddBranchInventoryBatch`, `sp_ConfirmBranchRecievedOrderJFC`).
- After receipt: no return on the STS PO. Reopening it would mean unwinding branch Inventory rows the
  receipt created, which may already be sold. Goods coming back use a reverse transfer
  (branch → head office).

## 4. Decisions needed (user / accountant)

- **D1. Does a return always go back to stock?** Partial return = restock; damaged goods = Credit
  Memo (shrinkage, COS OTHERS). Keep these as two separate actions.
- **D2. Which lots get the stock back?** Newest consumed first, as whole-line returns do today; the
  units still sold are then the oldest, which is FIFO-consistent. Recommended.
- **D3. Return cost basis:** the cost of the lots put back (recommended, for whole-line returns too),
  or the line's weighted cost (today).
- **D4. Paid tab:** allow Return / Credit Memo on fully paid orders? The SQL already turns the excess
  into customer credit.
- **D5. Which month the return lands in:**
  - Returns (whole-line today, partial after this) rewrite the original sale's `BatchSalesDetails`
    rows, so the sale's own month changes on a re-run of any sales report reading them.
  - The GL books the return in the return month. BIR-sensitive.
  - Keep as is for consistency, or record returns as dated rows in the return month: a separate,
    larger change.
- **D6. STS scope:** phase 2 as above (before receipt only)?

## 5. Verify on DEV first (read-only)

1. Column lists and types (INFORMATION_SCHEMA) of `DeliveryDetails`, `InventoryDeliveryFIFO`,
   `BatchSalesDetails`, `TransactionChargeSalesDetails`, especially the `Cost` precision.
2. The definitions of these readers: `view_BranchOrderDetails`, `view_DeliveryReciept`,
   `spview_SalesInvoiceJFC`, `funcview_CustomerSalesJournal`, `funcview_CustomerSalesInvoiceDetails`,
   `funcview_ForDeliveryDetails`.
   - Confirm they filter `isReturned` / `isErrorCorrect` the way whole-line returns assume.
   - A reader that doesn't already miscounts whole-line returns today, and would miscount partial
     returns more often.
3. Delivered SO lines whose FIFO rows have `DevDetSeqNo = 0` or don't add up to `QtyDelivered` (they
   can't be split).
4. `BatchSalesDetails` rows for SO POs where two live rows share product + barcode + price + qty
   (how often pairing would pick "any one").

## 6. Tests (rolled back, like `lc/test_so.ps1`)

Every scenario must tie: stock ledger qty = qty restored; invoice = client ledger = GL AR;
GL inventory = stock movement; tickets balance; Exception Center all 0.

- P1. Confirmed, unpaid, 100 → return 50: the line splits 50 / 50, the newest lots are restored,
  SO-RET for 50 × price.
- P2. The same line again: 30, then 20. The line ends fully returned and the invoice drops to 0
  (PayStatus RETURNED).
- P3. A line over two lots at different costs: the GL cost equals the restored lot's cost.
- P4. Fully paid, then return 50: the excess becomes OVERPAY credit on 20115.
- P5. Paid partly by EWT: the 59404 refusal is clean.
- P6. A line with a credit memo (100 delivered / 90 billed), return 50: L = 50 / 40 / variance 10.
- P7. Before confirm (For Delivery tab), return 50, then confirm: only the remaining 50 is billed.
- P8. Two sessions each return 50 of 100: the second one is refused (staleness).
- P9. Two lines with the same product + barcode, part of one returned: only its BSD / TCSD rows
  change.
- P10. ReturnQty = full: same result as today's whole-line return (regression).
- P11. Old exe signature (no `@ReturnQty`): whole-line return as before.
- P12. The sale's month closed: the return posts today; no closed-month ticket is touched.
- STS (phase 2):
  - Saved STS, return 30 of 100: In Transit drops by the restored cost.
  - Receive 70: In Transit is 0, no STS-SHORT.
  - Receive 60 + return 30: STS-SHORT = cost of 10.

Testing gotcha (worklog Feature 8): create the new TVP type committed, outside the test transaction.

## 7. Deploy and tooling

- One script `SQL/<date>_PartialReturn.sql`:
  - New type and table first.
  - Rename-then-create with `_OLD_<timestamp>` for `sp_ReturnSalesOrder` (and
    `sp_ReverseSTSInventoryTransfer` in phase 2).
  - Then the new procs.
- DEV first, then the exe. STAGING only after the user confirms.
- Exception Center: add **X05**, a split line whose live FIFO qty ≠ its `QtyDelivered` (scoped to
  lines in `DeliveryLineReturn`). Run it on DEV after deploying.
- Rebuild and republish the Dependency Atlas, and add a partial-return step and sample to the Sales
  Order Process Trace (same artifact URLs).

## 8. Order of work

1. Now, independent of the rest: fix the false "Successfully Returned!" in `ReturnSalesOrder.cs`.
2. Run the section 5 checks on DEV and settle D1–D5.
3. Phase 1: SO partial return (3.1–3.5), tests P1–P12, Exception Center X05, sp-reviewer +
   ui-form-reviewer + ledger-integrity-auditor.
4. Phase 2: STS before receipt (3.6).
5. Optional: Paid-tab return (D4), a return slip per return event.
