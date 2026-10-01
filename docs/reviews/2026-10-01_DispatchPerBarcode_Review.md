# Dispatch Per Barcode (STS): review before adopting it

2026-10-01. Code review only. There was no database access: "on DEV" facts come from the Dependency Atlas
snapshot of COREX001 (2026-09-30 23:54).

Files: `HOFormsDevEx/DispatchPerBarcode.cs`, `SQL/2026-08-24_DispatchPerBarcode_NewModule.sql`
(`spu_PostSTSDispatch` and its lookup procs). The menu entry `btnDispatchPerBarcode` is
`Visibility.Never` and nothing makes it visible.

## Verdict

Don't adopt it as the replacement for `AddBranchOrderSTS` as it stands.

- It was written 08-24/25, before the 09-29 FIFO deduction standard and the 10-01 STS redesign
  (`spu_STS_SyncInTransit`, all-VAT-exempt GL), and it follows neither.
- Its SQL objects are not on COREX001 (Atlas: all 8 procs/views "not in DB"), so the form fails
  on open there.
- `Orders/AddBranchOrderSTSV2` (built 09-29, on DEV, ViewBranchOrderSTS › Process this Order ›
  "FIFO V2 (Test)", admins only) already does what you want:
  - It opens with the PO's requested items (`funcview_TransferOrderDetailsSTS`).
  - It has the same three methods: SCAN (barcode, partial qty allowed), AUTO (FIFO auto) and
    BATCH (FIFO manual by Product + ShipmentNo + ReferenceCode).
  - It uses the FIFO engine and saves through the 10-01 `sp_ConfirmBranchOrderSTS`.
  - It needs a small alignment pass (section 4), not a rebuild.

## 1. Critical (wrong stock or wrong GL in normal use)

**C1. The receiving branch gets the stock at dispatch, and a reverse never takes it back.**
- `spu_PostSTSDispatch` inserts the destination branch's `Inventory` row with `Available = qty,
  IsStock = 1` at dispatch (lines 661-668), so the branch can sell goods that are still in transit.
- The reverse paths restore only the origin lots and leave that destination row as it is:
  - Posted tab › Reverse.
  - Lines left unticked at receiving (`ReceivedSTSBatchModeFIFO.ReturnUnreceivedItems`).
  - Both go through `sp_ReverseSTSInventoryTransfer` → `sp_CancelDeliveryFIFOJFC`.
- Result: the same goods are in stock at both branches. No Exception Center check catches this.

**C2. Reversing a line of a partly dispatched PO leaves its cost in In Transit.**
- Each submit posts IT-HO for its own lines, but `isProcess` turns 1 only when every approved
  product is fully dispatched (step 8).
- `sp_ReverseSTSInventoryTransfer` (10-01) reverses In Transit only when `isProcess = 1`. So on a
  partly dispatched PO the stock comes back and the GL does not.
- Exception Center T01 also checks only `isProcess = 1` POs, so it stays silent.

**C3. An origin other than 888 gets In Transit posted twice.**
- Dispatch posts IT-HO on the origin branch (the 08-25 decision).
- `spu_STS_SyncInTransit`, which runs on every later return and on the old Save, counts "posted"
  on '888' only. On a PO dispatched from branch X, the first sync posts the whole live cost again
  on 888.
- The receipt's short/over (STS-SHORT/OVER) is also booked on 888, not on the origin.
- This only matters if branches other than 888 really dispatch.

## 2. High

- **H1. Wrong PO on submit.** Answering "No" to the "Switching the PO Number…" prompt
  (`slkPONumber_EditValueChanged`) does not undo the switch.
  - The combo shows the new PO while the header still shows the old PO's delivery number and
    destination, and the staged lines stay.
  - Submit then posts those lines under the new PO with the old DeliveryNo. It is refused only
    if the destination or products differ.
- **H2. Not serialized with the rest of STS.**
  - The applock key is `@DeliveryNo`. Save, receive, return and the sync all use
    `'STSTRANSIT:' + PO`, so a dispatch can interleave with a receipt or return on the same PO.
  - The DeliveryNo is chosen in the form: two users opening a new PO at once get two DeliveryNos
    for one PO.
  - The approved-qty check (59406) runs before the lock.
- **H3. No stock-ledger rows.** No `InventoryLedger` row out at the origin or in at the destination.
  - A reverse writes 'STS CANCEL ITEM' IN rows with no matching OUT row.
  - The stock card won't show these transfers.
- **H4. The Posted tab lists every delivery, sales orders included.**
  - `vw_STSDispatchSummary` is all of `DeliverySummary`, with no branch or date filter.
  - Its Reverse would cancel a sales-order line that is FOR DELIVERY through the STS reverse proc.
- **H5. Barcode is used as a line key in places where it isn't unique.**
  - Duplicate guard 59405 refuses a second partial pick from the same lot in a later session.
    It also refuses any two lots with a blank barcode.
  - Receiving matches lines by PO + barcode, and updates the destination row by
    Branch + Delivery + Product + Barcode.
  - With blank or repeated barcodes, received lines disappear from the receive grid, or one
    receipt updates several destination rows.
- **H6. Lot eligibility differs from the 09-29 standard (your answers).** The standard is
  `Available > 0 AND IsWarehouse = 1`, with IsStock not a filter. Dispatch filters on
  `IsStock = 1` and ignores IsWarehouse (dropped on 08-25 so other branches could dispatch).
- **H7. FIFO column order (latent).** `InventoryDeliveryFIFO` is inserted positionally, and the
  lot's VAT flag goes in position 13.
  - The 10-01 STS fix put the VAT flag in position 12 and was tested with VAT items, so
    position 13 is most likely `isErrorCorrect`.
  - A lot with `IsVat = 1` would then be born "already reversed": it would be missing from
    receiving and In Transit, and a reverse would fail.
  - Today every lot has `IsVat = 0` (09-29 note), so nothing has happened yet.
  - Fix: an explicit column list. One check on DEV:
    `SELECT name, column_id FROM sys.columns WHERE object_id = OBJECT_ID('dbo.InventoryDeliveryFIFO') ORDER BY column_id`.

## 3. Your concern: the PO's items are not shown

Correct.
- `AddBranchOrderSTS`, and V2, open from ViewBranchOrderSTS with the requested items in a grid,
  and the product lookup is limited to the PO's products.
- Dispatch opens from the menu with a PO dropdown and shows nothing about the request:
  - The FIFO product list is all stock at the branch.
  - Products outside the PO, or above `ApprovedQty`, are refused only at Submit, with one generic
    message (59406) that doesn't name the product.
  - Barcode scans take the lot's whole `Available` (no partial qty), so the last box usually
    overshoots the approved kg and the whole submit is refused.

## 4. If you go with V2 (recommended): alignment pass

**Decision 2026-10-01: V2.** Items 1–2 below are in `SQL/2026-10-01f_STS_V2_Alignment.sql`, with these changes:
- After sp-reviewer, the post proc refuses a saved transfer (59835) instead of syncing.
- It also refuses a second delivery for one transfer (59836).
- Both V2 procs also refuse once the branch has started receiving.
- Save and the FIFO receive proc take the same PO lock.

Item 3 is `SQL/2026-10-01f_STS_V2_Alignment_Test.sql`, which hasn't been run on a database yet.

1. `spu_ReverseSTSLineV2`:
   - After restoring the lots, call `spu_STS_SyncInTransit` instead of posting its own ITR-HO
     split by FIFO isVat (it predates the 10-01 rules).
   - Use the `'STSTRANSIT:' + PO` lock (today `'STSV2_' + DeliveryNo + PO`).
   - Refuse once the delivery is DELIVERED.
2. `spu_PostSTSLineV2`: the same `'STSTRANSIT:' + PO` lock, and write the FIFO isVat from the
   product flag (as the 10-01 fix did for the old proc).
3. Re-run the 9 STS scenarios plus the Exception Center on DEV.
4. Then retire Dispatch Per Barcode (leave its menu hidden), or rebuild its "stage, then one
   submit" UX on top of the V2 procs if you prefer that flow.

## 5. If you keep Dispatch instead: minimum changes

C1–C3 and H1–H7, plus:
- A requested-items panel (requested / approved / dispatched / remaining, with live progress).
- A FIFO list limited to the PO's products.
- Per-product messages.
- Deploy the SQL to COREX001 first.

Bigger than option 4.

## Decisions needed

- V2 (recommended) or Dispatch as the replacement.
- Do branches other than 888 actually dispatch STS? This decides C3.
- Over-dispatch tolerance when whole boxes overshoot the approved qty.
- Lot eligibility for 888 (IsWarehouse rule from 09-29) vs other branches.
