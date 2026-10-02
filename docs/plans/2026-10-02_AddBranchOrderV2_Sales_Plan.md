# Plan: Process Sales Order V2 (`Orders/AddBranchOrderV2`) on the FIFO engine

Status: **PLAN ONLY (2026-10-02). Nothing built.** Decisions D1–D6 at the end need the user.

## 1. Why

Sales orders are processed in `Orders/AddBranchOrder` (opened from `Orders/ViewBranchOrder`). STS got a V2 form on the FIFO engine (`Orders/AddBranchOrderSTSV2`, scripts 13/14/24). Sales still runs on the old scan procedures, which have the gaps STS V2 closed:

| Area | Today (sales) | V2 target |
|---|---|---|
| Lot eligibility | Product scan (`sp_AddBranchOrderHRI_JFC` → `sp_FiFoMappingHRI_JFC`) takes any lot with `Available > 0`; **no `IsWarehouse = 1`** (09-29 FIFO standard: third-party-storage stock is IsWarehouse = 0) | Engine: `Available > 0 AND IsWarehouse = 1`, re-checked under lock |
| Concurrency | Product scan: no row lock, no applock (check, then deduct) → two users can oversell a lot (Exception Center X03) | Engine: per-product applocks in ProductCode order + UPDLOCK / rowcount-guarded deduction |
| Order-level lock | None: a scan can interleave with cancel / Save / confirm on the same PO | One per-PO lock `SOORDER:<PO>` taken by every Sales Order writer |
| After Save / invoice / confirm | Nothing stops a stale screen from adding lines | Refused with clear errors |
| Lot choice | Product FIFO, or barcode | SCAN (lot barcode) / AUTO (FIFO) / BATCH (ShipmentNo + ReferenceCode, composite key — Known Bug Pattern 7) |
| Stock ledger | Remarks say `STS IN-TRANSIT PO#-` for sales | `SO OUT PO#<po>` per lot |
| VAT flag | Line flag from the lot / product mix | Product's flag at origin (GL is all VAT-exempt anyway — 2026-10-01 rule; the flag only feeds the printed invoice) |

The barcode path (`sp_AddHRIOrderByBarcode`) already has UPDLOCK + applock + IsWarehouse; cancel (`sp_CancelDeliveryFIFOJFC`) and Save (`sp_ConfirmBranchOrder`) were fixed in script 19.

## 2. Shape (same as STS V2)

- **New form** `Orders/AddBranchOrderV2` = copy of `AddBranchOrder` (748 lines) with the STS V2 input panel (method radio SCAN / AUTO / BATCH, product + batch `SearchLookUpEdit`, requested-items panel, staged lines grid). The old form stays untouched and routed.
- **Entry:** `Orders/ViewBranchOrder` › Process this Order › **"FIFO V2 (Test)"**, admins only (`Login.isglobalAdmin`), like STS V2. Later the default once proven.
- **Same tables** (`DeliveryDetails`, `DeliverySummary`, `InventoryDeliveryFIFO`, `InventoryLedger`). So everything downstream is unchanged: Save (`sp_ConfirmBranchOrder`), invoice number (`HOForms/ViewForDeliveryDetails`), Confirm (`sp_ConfirmOrder`), credit memo, return, the Exception Center, the Process Trace.
  - CLAUDE.md asks new modules for their own tables; this is a new *screen* for the same document (like STS V2), so sharing is intended — flagged here on purpose.
- **Per-scan posting** (one line per scan, as today), not a staged submit: Save already exists as the commit step and downstream reads lines as they are written.

## 3. SQL (one script, `SQL/2026-10-xx_SalesOrder_V2_FIFOEngine.sql`; needs 13 + 19 + 23)

New:

| Object | Purpose |
|---|---|
| `spu_PostSOLineV2` (@DeliveryNo, @RefNo, @PONumber, @CustomerBranch, @OriginBranch, @PreparedBy, @Method, @Qty, @ProductCode, @Barcode, @ShipmentNo, @ReferenceCode) | Takes `SOORDER:<PO>`; refuses: PO not APPROVED (60001), already saved = DeliverySummary FOR DELIVERY (60002), invoice assigned / confirmed (60003), second DeliveryNo for the PO (60004), product not on the order or over the ordered qty beyond tolerance (60005 — D3). Calls `spu_InvFIFO_Deduct` (remarks `SO OUT PO#<po>`), writes `DeliveryDetails` (line cost = weighted of the lots) + one `InventoryDeliveryFIFO` row per lot (column list, never positional). Returns SeqNo / product / qty / cost. |
| `spu_ReverseSOLineV2` (@DeliveryNo, @PONumber, @SeqNo, @OriginBranch, @PreparedBy) | Same lock; refuses once confirmed (use Return) or invoiced (D2); `spu_InvFIFO_Restore` puts back exactly the lots the line took (ledger `SO CANCEL ITEM PO#`), flags the FIFO rows, marks the line cancelled. |
| `funcview_SOV2_Products` / `_ProductLots` / `_DeliveryLines` | Lookups for the form: the order's products with eligible stock, a product's eligible lots (composite key `Product||ShipmentNo||ReferenceCode`), the delivery's lines. |

Patched (exact-anchor text patch + `_OLD_` backup, as 2026-10-01e/f):

| Proc | Change |
|---|---|
| `sp_ConfirmBranchOrder` (Save) | take `SOORDER:<PO>` first; refuse a second Save once invoiced |
| `sp_ConfirmOrder` (Confirm) | take `SOORDER:<PO>` first |
| `sp_CreditMemo`, `sp_ReturnSalesOrder`, `sp_CancelDeliveryFIFOJFC` | take `SOORDER:<PO>` first (cancel is shared with STS: lock name by order type) |
| `sp_AddBranchOrderHRI_JFC`, `sp_AddHRIOrderByBarcode` (old form) | optional (D5): take the PO lock too, so old and V2 screens can't interleave |

## 4. C#

- `Orders/AddBranchOrderV2.cs` + `.Designer.cs` (copy, then trim to the V2 flow); every lookup column `TextEditStyle = DisableTextEditor` (Known Bug Pattern 2); `.EditValue` for ValueMember reads (Pattern 3); `LoadData()` stays the real init (Pattern 1); DB fetches in `Task.Run`, binding after `await` (Pattern 8).
- `Orders/ViewBranchOrder.cs`: the "FIFO V2 (Test)" entry, admin-gated.
- Errors shown from the SqlException (no "success" after a swallowed error — the bug fixed in `ReturnSalesOrder.cs`, commit bb48873).

## 5. Tests

Rolled-back harness `lc/test_so_v2.ps1` (as `test_so.ps1`), then the Exception Center (all X / S / G checks must stay 0):

1. AUTO scan spanning 2 lots → 2 FIFO rows, weighted line cost, ledger rows per lot, nothing posted.
2. BATCH on a `CONVERSION` lot and on a `''` ShipmentNo lot → takes only that batch, refuses (not spills) if short.
3. SCAN by lot barcode → that lot only.
4. IsWarehouse = 0 lot is never taken (third-party storage).
5. Two sessions scanning the last stock of one lot → one waits, no oversell (X03 stays 0).
6. Cancel before Save → stock back exactly, ledger `SO CANCEL ITEM`.
7. Save → line status FOR DELIVERY; a new scan is refused (60002); Save again is harmless.
8. Invoice number → cancel refused (D2); Confirm → SI-VATEX ticket = invoice = client ledger = GL AR, COGS = FIFO cost (S01–S04).
9. Credit memo and return after a V2 order → same results as the old-form scenarios C / D / E / G.
10. Old form and V2 on the same PO at once → serialized, no deadlock (if D5).

## 6. Order of work

1. User answers D1–D6.
2. SQL on DEV (rehearsed rolled back) → harness → Exception Center → sp-reviewer.
3. Form → build → ui-form-reviewer → user UI test on DEV (admins only).
4. STAGING only after STS V2 is live there (scripts 13 + 14 + 24 + the new exe), with this script and the new exe.

## 7. Decisions for the user

- **D1** Timing: build after STS V2 is live on STAGING (recommended), or now on DEV in parallel?
- **D2** Can a line be cancelled after the invoice number is assigned but before Confirm? (Today: yes. Recommended: no — change the invoice first.)
- **D3** Over-scan: may a line exceed the ordered qty (meat is weighed)? If yes, by how much (e.g. +10 %)?
- **D4** Default method on open: AUTO (FIFO) or SCAN?
- **D5** Put the old form's scan procs on the PO lock too (recommended while both screens exist), or leave the old form exactly as is?
- **D6** Partial return (Feature 17, `docs/plans/2026-10-01_PartialReturn_SO_STS_Plan.md`): settle its D1–D6 first, so V2 lines are split-ready from day one.

## 8. Interim option (if waiting for V2 feels risky)

Patch only the two worst gaps in the current product scan (`sp_AddBranchOrderHRI_JFC` / `sp_FiFoMappingHRI_JFC`): the `IsWarehouse = 1` rule and UPDLOCK + per-product applock. Small, no exe change; V2 replaces it later.
