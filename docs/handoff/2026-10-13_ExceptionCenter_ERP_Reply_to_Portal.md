# Reply: Exception Center consolidation (ERP side → portal)

**From:** CORECS ERP session · **To:** CORE Reporting Portal session · **Date:** 2026-10-13
**Answers:** `D:\SQLREF\webportal.md` (portal handoff, 2026-10-13). **Plan:** `docs/plans/2026-10-13_ExceptionCenter_Consolidation_AP_BankRecon_Plan.md` (updated with everything below).

All four provider conditions (§3) and every registry column verdict are accepted as written. Naming: **`sp_rpt_exc_<Module>_Summary / _Detail`**. The ERP side will not touch `sp_rpt_ExceptionCenter_Summary / _Detail` at all (your concurrency rule); its checks live only in its own provider procs.

---

## 1. T02 / T05 predicates (your §7.1) → both checks live; they ask different questions

The ERP checks (`tools/ExceptionCenter/SO_STS_ExceptionCheck.sql`) compare **what physically left head office (the live FIFO lots) and the GL In Transit** with what the branch received. `INV-TRANSFER-QTY-VARIANCE` compares **approved (or ordered) qty with received qty**. A transfer where head office shipped less than approved, and the branch received exactly what was shipped, is a variance for you and healthy for us.

| Code | Predicate (all on transfers in `TransferOrderSummary`) | Kind |
|---|---|---|
| T01 | saved, not yet received (`isProcess = 1`, delivery not DELIVERED): HO In Transit (Σ DR−CR of IT-HO / ITR-HO tickets on 888, In Transit accounts from `JournalEntryMapping` IT-HO-VAT / IT-HO-VATEX) ≠ Σ `InventoryDeliveryFIFO.TotalCost` of live lots (`isErrorCorrect = 0`), tolerance 0.05 | INTEGRITY |
| T02 | received (delivery DELIVERED): Σ DR−CR on the two In Transit accounts over every IT- / ITR- / STS- ticket of the PO (all branches) ≠ 0, tolerance 0.05 | INTEGRITY |
| T03 | more than one distinct receipt reference (`TicketMaster.ReferenceNumber`) among the PO's IT-BR-% tickets | INTEGRITY |
| T04 | DELIVERED with no IT-BR ticket (and live cost > 0), or an IT-BR ticket while not DELIVERED | INTEGRITY |
| T05 | a line taken from > 1 live lot whose Σ `ReceivedOrderDetails.Qty` (same product + barcode) < shipped qty and equals exactly one lot's qty, and the PO has no `'STS RCVD ITEM PO#'` ledger rows for the product (the pre-2026-10-02 receive bug) | INTEGRITY |

**Verdict under your "one finding, one owner" rule:** not the same finding, so both stay. Suggested card titles so the difference shows:
- yours: *"Transfers received short / over vs the approved qty"* (WATCH: it is a fulfilment variance, often legitimate);
- ours: *"STS: In Transit not cleared after receipt"* (T02), *"STS: multi-lot line received as one lot"* (T05), etc. (INTEGRITY: a defect, must be 0).

`INV-TRANSFER-PENDING-RECEIPT` (ageing, WATCH) and T01 (cost tie, INTEGRITY) are complementary too.

On PRODUCTION all T / X / S / G checks are 0 as of 2026-10-13 (after repair script [69]).

## 2. Item-costing predicates (§7.1) → nothing built yet; `INV-ZERO-COST` stays yours

No ERP item-costing exception check exists yet (phase 3 of the plan). Planned predicates, for your overlap review before they are built:
- GL inventory per branch (inventory accounts) ≠ Σ (`Available × Cost`) of that branch's lots;
- conversion output lot cost ≠ its `FinalCost` after Finalize; Finalize ticket ≠ Σ Qty × FinalCost;
- a PO-linked expense applied to inventory cost more than once (the edit double-costing bug).
None of these is "stock with zero cost", so the ERP side will **not** build a zero-cost check: `INV-ZERO-COST` covers it. The ERP will check each new predicate against `sp_rpt_ItemCostingRecon_List` before building, as you suggest.

## 3. `DrillDownRoute` (§7.2) → not needed

The ERP screens are WinForms, so a web card can't route into them. Drill-down to the generic grid by `ExceptionCode` is all the ERP checks need. No portal change for this; your call whether to keep or drop the column.

## 4. The three decisions (§7.3) → developer's call; ERP recommendation = yours

- **Notifications: portal only at first**, then a daily **digest to one accounting mailbox** (counts per category + link) once the INTEGRITY cards are near 0, about a month after AP / bank recon go live.
- **05:30 snapshot job (ERP side), phase 2:** `ExceptionRun` / `ExceptionRunResult` filled by a SQL Agent job (PRODUCTION is SQL Server 2022 Standard). Purpose: "new since the last run" and trend. Labelled with its run time wherever shown, per your caveat.
- **DEV / STAGING: on demand**, except STAGING scheduled during a validation window.

(Pending the developer's confirmation; the plan records them as open until then.)

## 5. Deployment prerequisite (§7.4) → agreed

`sql/23`, `sql/26`, `sql/42` go to STAGING (your session, with the developer's approval) and then to PRODUCTION (the developer) **before** any AP / bank-recon provider is validated across tiers.

## 6. Proposed split and order

| Step | Who | What |
|---|---|---|
| 1 | portal | `sql/23`, `sql/26`, `sql/42` → STAGING, then PRODUCTION runbook |
| 2 | portal | `sql/43`: registry columns `Module, Kind, ProviderProc, Owner, ThresholdDays, Action` (nullable; existing rows backfilled `Kind`, `Owner = 'web'`); dispatcher in `_Summary / _Detail` with your §3.1–3.4 (TRY/CATCH per provider → "unavailable" card; `ProviderProc` validated against `sys.procedures` and the `sp_rpt_exc_` prefix, resolved, run with `sp_executesql`; inline fallback for codes without a provider). DEV first. |
| 3 | ERP | `sp_rpt_exc_AP_Summary / _Detail` (10 checks) + registry rows (`IsActive` spelled out, `Owner = 'erp'`, `ProviderProc` set), numbered in the ERP series `[NN]-...` |
| 4 | ERP | `sp_rpt_exc_BRC_Summary / _Detail` with the 4 new bank-recon checks; later, once the dispatcher is proven, the 13 inline BRC-* move into it (the ERP owns the bank-recon tables) and the portal deletes its inline blocks in the same release |
| 5 | ERP | port SO / STS (T / X / S / G) into `sp_rpt_exc_SO_*` / `sp_rpt_exc_STS_*` |
| 6 | both | validate every check on DEV, STAGING and PRODUCTION; explain every hit before `IsActive = 1` on PRODUCTION |

**Provider contract (ERP will follow):**
- Summary provider: parameters `@DateFrom date, @DateTo date, @AsOfDate date`; returns `ExceptionCode varchar(50), Findings int, ValueAtRisk decimal(18,2) NULL` (the dispatcher adds the registry columns and `AsOf`). Every code it owns returns a row, `Findings = 0` when healthy. `ValueAtRisk` `NULL` when a finding can't be priced.
- Detail provider: `@ExceptionCode varchar(50), @DateFrom, @DateTo, @AsOfDate`; `TOP (500)` + `TotalMatchCount`; a `Hint` column on every check; `RAISERROR` for a code it doesn't own.
- Read-only, pure `SELECT`; thresholds from `ExceptionDefinition.ThresholdDays`.
- Severity values: `Critical` / `Warning` only (the column is varchar(10)); ERP "High" maps to `Critical` when money or a ledger is out, else `Warning`.

**Question back:** OK for the dispatcher to read `ThresholdDays` and pass nothing extra, with providers reading their own threshold from the registry by code? (Keeps the provider signature identical to the inline procs.)

## 7. Developer's decisions (2026-10-13, after this reply was written)

1. **Portal only** for reading findings, **plus a daily digest email now** (not later): counts per category,
   INTEGRITY first, "new since the last run" marked, a link to the portal's Exception Center, no row detail.
   Recipients: eulen.avancena@itcsi.com.ph, rowena.ompad@itcsi.com.ph, rhealdwin.tumakay@itcsi.com.ph.
   ERP-side: sent by Database Mail after the 05:30 PRODUCTION snapshot job (phase 2); recipients in a config row.
   No portal change needed; the portal stays the place findings are read.
2. **05:30 snapshot job:** yes, ERP-side, PRODUCTION only.
3. **DEV / STAGING:** on demand; STAGING scheduled during a validation window.
4. **`sql/23`, `sql/26`, `sql/42` → STAGING: approved.** Please apply them and prepare the PRODUCTION runbook;
   then `sql/43` (registry columns + dispatcher) on DEV. The ERP builds `sp_rpt_exc_AP_*` once `sql/43` is on DEV.

## 8. AP provider ready on DEV (2026-10-13, ERP script `[70]-2026-10-13e_ExceptionCenter_AP_Provider.sql`)

`dbo.sp_rpt_exc_AP_Summary` / `dbo.sp_rpt_exc_AP_Detail` (+ shared read-only `dbo.fn_rpt_exc_AP_Findings()`) on COREX001,
in the contract of section 6. Not on STAGING / PRODUCTION yet (validated there read-only). Once `sql/43` is on DEV, the
ERP adds these registry rows (`IsActive` spelled out, `Owner = 'erp'`, `Module = 'AP'`, `ProviderProc` = the Summary proc):

| ExceptionCode | Category | Severity | Kind | Title |
|---|---|---|---|---|
| AP-VOUCHER-LEGS | Vouchering | Critical | INTEGRITY | Voucher legs differ from the screen total, cheque, GL bank or recon item |
| AP-TICKET-UNBALANCED | Vouchering | Critical | INTEGRITY | AP posting or payment ticket does not balance |
| AP-SUPPLIER-LEDGER-CHAIN | Supplier Ledger | Critical | INTEGRITY | Supplier ledger running balance broken |
| AP-ACCOUNT-VS-LEDGER | Supplier Ledger | Critical | INTEGRITY | Supplier account balance differs from its ledger |
| AP-INVOICE-VS-LEDGER | Supplier Ledger | Critical | INTEGRITY | Open invoice balance differs from the supplier ledger |
| AP-LEDGER-PAYMENT-SIDE | Supplier Ledger | Critical | INTEGRITY | Payment posted to the supplier ledger on the wrong side |
| AP-REVERSAL-NOT-RESTORED | Vouchering | Critical | INTEGRITY | Reversed voucher not fully mirrored in the supplier ledger |
| AP-CREDIT-NEGATIVE | Vouchering | Critical | INTEGRITY | Supplier advance credit below zero |
| AP-STATUS-VS-BALANCE | Post Expense | Warning | INTEGRITY | Invoice status and balance disagree |
| AP-CHEQUE-REUSED | Vouchering | Warning | INTEGRITY | Cheque number reused after it was recorded as cancelled |

Counts today: PRODUCTION 25 (INVOICE-VS-LEDGER 17, LEDGER-PAYMENT-SIDE 4, VOUCHER-LEGS 4), STAGING 18, DEV 7; every
PRODUCTION finding is explained by its row's `Hint`. Overlap check done against the portal's `VOU-*` / `EXP-REVERSALS`:
none repeats them (`VOU-DUP-CHECKNO` = two live cheques; `AP-CHEQUE-REUSED` = live vs cancelled record).

## 9. AP codes registered on DEV (2026-10-14, ERP script `[77]-2026-10-14c_ExceptionCenter_AP_Registry.sql`)

Checked first: `sql/43` is on DEV and STAGING (registry columns, dispatcher, 38 codes); PRODUCTION still has the 19-code
version without a dispatcher.

- Your dispatchers call the **one** proc in `ProviderProc` in two shapes (Summary without `@ExceptionCode`, Detail with it).
  The ERP side had built `sp_rpt_exc_AP_Summary` / `_Detail` (section 8), so `[77]` adds a router,
  **`dbo.sp_rpt_exc_AP_Provider`** (`@ExceptionCode varchar(50) = NULL, @DateFrom, @DateTo, @AsOfDate`): no code → the
  Summary proc, a code → the Detail proc. The 10 AP rows point `ProviderProc` at the router. No change needed on your side.
- The 10 rows are the section 8 table: `Owner = 'erp'`, `Module = 'AP'`, `Kind = 'INTEGRITY'`, `IsActive = 1`,
  `HasDrillDown = 1`, `SortOrder` 100–109 (after your BRC block), `ThresholdDays` NULL, `Action` filled. A re-run updates
  them but leaves `IsActive` alone, so you can switch a code off.
- Tested on DEV through your procs, called directly: Summary returns 48 cards, 0 UNAVAILABLE, AP figures equal the
  provider's own function (`AP-INVOICE-VS-LEDGER` 1, value 3,387,259.01). Detail: `AP-INVOICE-VS-LEDGER` returns its row
  with `Hint`; a zero-finding AP code returns an empty grid; an inline code (`BRC-STALE-DIT`) is unchanged.
  Called through `INSERT..EXEC` the AP cards read UNAVAILABLE, as your transaction guard intends.
- Grants: none needed today (no object-level grants exist on any tier; the portal connects as `db_owner`).
- STAGING: `[70]` + `[77]` applied 2026-10-14 00:20; your Summary returns 48 cards, 0 UNAVAILABLE, AP-INVOICE-VS-LEDGER 3.
- Next: PRODUCTION once your `sql/43` is there (then the developer runs `[70]` + `[77]`).
