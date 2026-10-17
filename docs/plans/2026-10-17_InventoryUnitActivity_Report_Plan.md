# Inventory Unit Activity report: assessment and plan (2026-10-17)

Screen: `Reporting/InventoryUnitActivityReport.cs` (menu btnInventoryUnitActivityReport; the older
`Reporting/InventoryUnitActivity.cs` is hidden and calls the proc with wrong parameter names).
Proc: `dbo.spr_InventoryUnitActivity` (@parmbrcode, @datefrom, @dateto), same text on DEV / STAGING /
PRODUCTION (hash 34355E73…, last altered 2026-09-29).

## User's ask

Show every movement of an item for the period: conversion out (source consumed) and conversion in
(output), STS in / STS out, Inventory IN; a shipment received this month shows under Unit Purchased,
next month it is part of the Beginning Qty.

## What the report does today (PRODUCTION, read-only, branch 888, September)

| Column | Today's rule | Problem |
|---|---|---|
| Beginning Qty | lots RECEIVED in the period (all kinds) | not a beginning balance; it repeats this period's receipts |
| Unit Purchased | PO lines with TargetDate in the period, joined to every lot of the shipment | each PO line counted once per lot: 888 Sept = 731,662,883.94 kg (PORK CUTTING FAT SKINLESS 174,527,772.50 vs 119,808.50 ordered) |
| Adjustment | always 0 | quantity adjustments never shown |
| Unit Sold | sales deliveries in the period | ok |
| Inventory Transfer | STS out in the period | ok |
| (missing) | — | STS in, conversion in / out, Inventory IN, returns |
| Qty On Hand | Beginning + Purchased − out | double count of receipts, so meaningless |

## How stock really moves (measured on PRODUCTION 2026-10-17)

Every IN creates an `Inventory` lot; every OUT is a row pointing at a lot (`SequenceNumber`).
Lot origin can be told from the lot itself:

| Lot kind | How to recognise it | Lots | Kg in |
|---|---|---|---|
| Purchase (CONFIRMED / RECEIVED) | ShipmentNo is a PO of the lot's own branch (POSUMMARY) | 29,605 | 1,182,918 |
| Purchase still FOR CONFIRMATION | same, PO status FOR CONFIRMATION (Available held at 0) | 40,047 | 1,195,358 |
| HO opening load (09-07) | POSUMMARY status DELIVERED, keyed 09-07, TargetDate Jan–Jul | 207 | 3,049,298 |
| Branch opening load (09-07) | branch lot dated 09-07, ShipmentNo not a PO of that branch | 901 | 5,599,707 |
| STS in | copy of another branch's lot (same ShipmentNo + ReferenceCode) / barcode in ReceivedOrderDetails | 322 | 580,342 |
| Conversion in | ShipmentNo 'CONVERSION' / isConversion | 4 | 4,167 |
| Inventory IN (adjustment screen) | ShipmentNo blank / '00000' | 37 | 1,298 |

OUT rows: sales and STS out = `InventoryDeliveryFIFO` (isErrorCorrect = 0; STS when the PO is in
TransferOrderSummary); conversion out = `ConversionFIFO` (old) + `ConversionBarcodeSourceDetails`
(per-barcode, not reversed); branch transfer = `InventoryBranchTransferFIFO`; quantity adjustment =
`InventoryAdjustment` (DEDUCT: 2 rows, 1,200 kg, 08-03).

**Tie-out per lot (received − every OUT row = Available):** exact on every lot except
- the 40,047 lots of FOR CONFIRMATION shipments (Available held at 0 until confirmed, 1,195,358.30 kg);
- 10 lots with a small gap (2,347.55 kg on 5 HO lots, −530 kg on 5 branch lots: old conversion /
  STS-cancel quirks), to be listed by an Exception Center check.

So the report can be rebuilt from these tables and still tie to stock on hand. `InventoryLedger`
cannot be the source: it starts 2026-09-09 and has no conversion / adjustment rows.

## Proposed report (one row per branch + item code + product)

Beginning Qty | Unit Purchased | STS In | Conversion In | Inventory In | Unit Sold | STS Out |
Conversion Out | Adjustment | Ending Qty | Unit Cost | Item Value | Sales | Cost of Sales

- Computed per lot, then summed: Beginning = lot IN before the period − its OUT rows before the period;
  each column = that kind of movement inside the period; Ending = Beginning + INs − OUTs. Next month's
  Beginning = this month's Ending by construction.
- Dates: lot IN = DateReceived; sale / STS out = DateProcessed; conversion = its conversion date
  (`DateConverted`, the picked date since [67]); adjustment = DateAdjusted.
- Values at the lots' own cost (exact FIFO): Item Value = Σ ending qty × lot cost, Cost of Sales =
  Σ sold qty × lot cost (today: one average cost × qty).
- Check: Ending as of today = SUM(Available) of the branch's lots (except the held shipments).

## Decisions for the user

1. FOR CONFIRMATION shipments: count in Unit Purchased when received (physically in) or only when confirmed?
2. A cancel / return keyed in a later month: today it erases the original sale (the earlier month changes).
   Keep that, or add a "Sales Return" in-column dated on the return day so closed months never change?
3. The 09-07 opening loads: part of Beginning Qty, or their own "Opening" column?
4. Branch Transfer (non-STS module, 5 transfers): inside STS In / Out, or separate?
5. An "All branches" choice for head office?

## User's answers (2026-10-17) and what was built ([102], DEV)

1. FOR CONFIRMATION shipments count in Unit Purchased **when received**.
2. **Sales Return** column: a cancel / return shows on the day it was keyed, the original sale stays in its month.
   Other reversals (STS line cancel, conversion reversal, branch transfer cancel, stock-out reversal) are a negative
   figure in their own column on the reversal day.
3. The 09-07 opening loads are part of **Beginning Qty**.
4. Branch Transfer has its own **In / Out** columns.
5. Head office can pick **ALL BRANCHES**.

Built: `SQL/[102]-2026-10-17_InventoryUnitActivity_PerLotMovements.sql` (rules in its header) +
`Reporting/InventoryUnitActivityReport.cs`. Checks on PRODUCTION's data (read-only): every lot's Qty On Hand =
Available except the held FOR CONFIRMATION lots and lot 63 (STS 14044 cancel of 10-01 never restored 2,407.55 kg);
September Qty On Hand = October Beginning on all 1,485 rows. One correction to the measurements above: the "10 odd
lots" were pre-go-live test rows (branch transfers 240–246 of 08-04 / 08-05, old conversions of 08-23 / 08-24) that
point at sequence numbers reused by the 09-07 load; the report leaves them out, and lot 139's gap was the back-dated
conversion CVB-000001 (08-07), which the report counts.
