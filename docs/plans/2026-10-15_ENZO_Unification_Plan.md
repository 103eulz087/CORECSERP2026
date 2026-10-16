# ENZO onto the current version: one exe, one set of procs (plan, 2026-10-15)

Status: **PLAN ONLY, nothing built or changed.** Read-only investigation of ENZO (`erp.itcoreapps.com,4281 /
CORECSERP_001`, key `AAITCRE\ConnSettingsEnzoReadOnly`), JFC PRODUCTION and the C# code, 2026-10-15.
Working files: `docs/handoff/enzo/` (object usage, definitions, diffs, table / type compare, company branches, menu
map, procs per form, count procs and queries). **Implementation handoff:**
`docs/handoff/2026-10-16_ENZO_Unification_Handoff.md`.

**2026-10-16:** your answers are in section 7 and change 4.1 (fewer settings) and phase 3 (the month-end count
moves up and becomes a new module, section 9). Section 9 also has the read-only findings on today's counts
(`docs/handoff/enzo/count`). The ENZO login is db_owner now; by your rule Claude only reads there (no EXEC, no writes).

**2026-10-16, second round:** Q-A, Q-B, Q-C (cost), Q-D, Q-F and Q-G1 / G3 / G4 answered (section 7). The count
freezes the branch while it is open (9.2), re-weigh / repack is part of the count, uncounted = 0. ENZO's goal stated:
adopt the ERP as it is, so its structure is brought up to the current version; its sales stay in the hybrid POS
(sales uploaded at end of day, then deducted from stock).

**2026-10-16, third round:** Q-E (test database), Q-G2, G5, G6, G7 answered. The test database is
`CORECSERP_001_BACKUP` on the practice server (registry key `AAITCRE\ConnSettingsEnzoTest`, DPAPI; ENZO data to
2026-10-14). Section 9.6 has the duplicate-row findings from it and the merge plan; 9.7 compares your temp-table idea
with the in-place design.

## 1. The goal

Today the exe chooses the flow by `GlobalCache.CompanyName` (`CompanyProfile`: `ENZO` / `JFC`), in 56 branches across
23 files, and the two databases carry different texts under the same proc names. The goal:

- **One exe** for every client. What differs between clients is **settings** (a per-database table), not code
  paths and not `_JFC` proc names.
- **One text per proc** on every database. The same script runs on DEV, JFC STAGING, JFC PRODUCTION and ENZO.
- ENZO gets the hardened flows JFC got in September–October: the FIFO engine, STS V2 and FIFO receive, Sales V2,
  locks, the error-handling standard, the transfer-receive guard [82] and the Exception Center.
- ENZO's own good changes come INTO the common version. JFC gains from them too.

## 2. What ENZO really runs (since the server start, 2026-05-25)

ENZO runs more than the modules listed in the brief. By run count:

| Module | Busiest procs (runs) | Notes |
|---|---|---|
| POS end-of-day sales deduction | `sp_SalesQtyToInventoryQtyEODSalesInvDeduct` 197,050; `…PerMachine` 22,329; `sp_Analyze` 7,810; `spman_apply_and_calculate` 2,530 (ENZO-only) | ENZO's biggest load. 98,493 POS batches in the last 30 days |
| Monitors / reports | `sp_GetTopPendingDeliveries`, `splive_GetDailySTSMonitor`, `sp_GetDailyDeliveryMonitor` ~155,500 each; `spr_POSReports` 30,065; `spr_STS` 14,226 | Dashboards that refresh all day |
| Conversion | `sp_ConversionFIFO` 52,298; `sp_SubmitConversionRaw` 22,793; `sp_ConfirmConversion` 22,203; `sp_ConversionProcess` 14,707 | 4,751 conversions in 30 days, through `HOConversion` |
| Receiving (PO) | `sp_AddTempInventory` 35,386; `sp_InsertTempInventoryPrimal` 11,367; `SP_ADDPOSUM` 1,005; `SP_POSTINVENTORY` 565 | Primal-cut and carcass receiving, pallets |
| Branch transfer | `sp_StageBarcodeForTransfer` 27,624; `sp_AddBranchTransferInventory` 5,076; pallet / batch commit | By pallet, by barcode, branch to branch |
| STS | `sp_FiFoMappingSTS` / `sp_SalesQtyToInventoryQtySTS` 12,897; `sp_AddBranchOrderByBarcode` 8,897; `sp_AddBranchOrder` 6,725; receive `sp_AddBranchInventoryBatch` 1,056 | 769 STS deliveries in 30 days, old (V1) screens |
| Sales orders (HRI) | `sp_ConfirmOrder` 2,102; `sp_FiFoMappingHRI` 1,645; `sp_AddBranchOrderHRI` 952 | 449 sales deliveries in 30 days |
| Re-inventory IN | `sp_StageBarcodeForReInventoryIN` 2,969; `…ManualEntry` 814; `sp_CommitReInventoryIN` | ENZO's month-end count (`InventoryINMonthEnd`) |
| Stock out | `spu_PostStockOutBarcode` 20 | Light use |
| Night jobs (SQL Agent) | 23:45 `DeductInventoryAndUploadSales`: `spjob_DeductBranchInventory` → `spjob_DeductLateUploadCleaner` → `spjob_UploadSalesToXero` → 2 re-uploads; 23:55 snapshot; backup every 5 h | **Accounting is in Xero** (database `ITCOREPOSENZO`) |

Of ENZO's 415 procs, about 131 modules are in use. 310 never appeared in the cache: old copies, GL procs, unused screens.

## 3. How far apart the two are

**C# (exe):** the same forms for most modules, with three real forks:

| Module | ENZO path | JFC path | Fork |
|---|---|---|---|
| Process STS | `AddBranchOrderSTS` (`sp_AddBranchOrder`, `sp_AddBranchOrderByBarcode`) | `AddBranchOrderSTSV2` (FIFO engine) | `ViewBranchOrderSTS.cs:42/353` |
| Receive STS | `ReceivedSTSBatchMode` (`sp_AddBranchInventoryBatch` + `sp_ConfirmBranchRecievedOrder`) | `ReceivedSTSBatchModeFIFO` → `spu_STS_ReceiveTransfer` (one call) | `ReceivedSTS.cs:166` |
| Process sales order | `AddBranchOrder` (`sp_AddBranchOrderHRI`, `sp_CancelDelivery`) | `AddBranchOrderV2` (FIFO engine) | `ViewBranchOrder.cs:173/255` |

The rest are small branches inside one form: PO details proc / TVP, conversion `_JFC` proc / TVP / cutting fee,
invoice view and print, the unit default, the categories 10 / 11 / 12 filter, and pallet-required receiving.

**SQL:** of the 131 objects ENZO uses, 75 are identical to JFC PRODUCTION, 50 have different text and 6 are
ENZO-only. ENZO's texts are JFC's older shared procs:
- **with the GL calls commented out** (ENZO has no `JournalEntryMapping` and no GL writer);
- **with `IsWarehouse = 1` filters** (third-party storage);
- **plus ENZO's own work:** the DevDetSeqNo pass-through, `InventoryINMonthEnd` re-inventory, UPDLOCK + savepoint in
  the HRI deduction, and a NULL-safe MinQty in `sp_ConversionProcess` (JFC's version divides without a guard).

JFC replaced several of these with `_JFC` variants or V2 procs that ENZO doesn't have (43 objects the JFC flows
call are missing on ENZO).

**Schema:** inventory, products and the core STS tables match. ENZO lacks 6 tables the flows need (ApprovalSettings,
the ConversionBarcode tables, GLPeriodLock, JournalEntryMapping, SalesReturnLog) and a few JFC columns. Several of
ENZO's columns are narrower. The one that bites: **`DeliveryDetails.SeqNo` is DECIMAL(3,0) on ENZO, (10,0) on JFC.**
Invoice no. and reference columns are also narrower. 7 table types are missing.

**Database setting:** ENZO runs compatibility level **120**, JFC 160. Probed on ENZO:
- **fail at 120:** `STRING_SPLIT`, `OPENJSON`, `GENERATE_SERIES`;
- **work at 120:** `STRING_AGG`, `TRIM`, `GREATEST` and the other functions the ERP procs use.

Only one inline C# query is affected: `ConversionPerBarcode.cs:430` uses `STRING_SPLIT`.

**Why "copy JFC's procs over ENZO" would break ENZO:**
1. They post GL tickets. ENZO has no mapping table, so they would refuse every posting ([83]'s checks).
2. They drop the `IsWarehouse` filter, so third-party stock could be sold or transferred.
3. They undo ENZO's own fixes.
4. They call objects ENZO lacks.
5. ENZO's narrower columns would truncate.

## 4. The approach: settings, not company names

### 4.1 One settings table per database

New table `dbo.SystemFeature (FeatureKey VARCHAR(50) PK, Value VARCHAR(100), Description, ChangedBy, ChangedDate)`,
read by the procs with one inline function `dbo.fn_Feature('KEY')` and by the exe once at start-up (cached like
`GlobalCache`). First keys (JFC value / ENZO value):

| Key | JFC | ENZO | Used by |
|---|---|---|---|
| `GL_POSTING` | 1 | 0 | GL writer `sp_PostCompoundTicket(Sales)`; when 0 it returns without a ticket. One switch for every posting proc. `spu_STS_SyncInTransit` and the GL-only steps skip too. **Confirmed 2026-10-16: ENZO has no GL** |
| `STS_REQUIRE_APPROVED` | 1 | 1 | Process STS refuses an unapproved request; `0` = bypass (process without approval), switchable at any time. **Both clients 2026-10-16, with the bypass option you asked for** |

**Not settings any more (answers 2026-10-16), one rule for every client:**
- **Third-party storage:** only `IsWarehouse = 1` stock may be taken by any process (STS, sales order, stock out,
  conversion, transfer); `IsWarehouse = 0` stays at 888 until it is moved into the commissary. That is already the FIFO
  engine's rule, and every JFC lot is 1, so it needs no switch.
- **Labelled boxes** (`fn_InvIsStickerBarcode`): **A01** (received from supplier), **D01** (manual inventory in) and
  **R01** (return / branch transfer) are whole boxes: scan only, never split by FIFO. **B01** (STS process) and **C01**
  (conversion) are tags: FIFO may take part of them. Today JFC's function knows A01 + 19 digits only; adding D01 / R01
  changes 1 live JFC lot (D01, 0.05 kg) and no R01 (PRODUCTION 2026-10-16), so one rule fits both. **JFC too: yes
  (Q-A, 2026-10-16).** A "whole box" can also be one plastic bag: a re-weighed or repacked unit gets its own D01 label
  and is scanned whole.
  POS sales by the kilo are not bound by it: ENZO already has 313 A01, 56 D01 and 83 R01 live lots partly sold.
  - **D01** = stock put in by hand (inventory in, re-weigh, repack): an inventory injection with **no GL entry**, on
    JFC too. On JFC that means GL inventory moves away from the stock for every D01; the count module (9.2) is where
    such a difference gets booked.
  - **R01** = a return / pull-out: works like an STS and a stock out together (e.g. expired stock pulled from a branch).
- **Branch codes with an A / X suffix** (003X, 010A …): deliberately broken codes that keep old rows out of every
  process. The common procs keep joining on `Branches`, so they stay out; nothing to migrate.
| `SO_FIFO_TYPE_DEFAULT` | MANUAL | AUTO | V2 screens' default FIFO type (today a `CompanyName` test) |
| `PO_PRODUCT_LIST` | ALL_COST0 | SUPPLIER_COST | `AddPurchaseOrder` product list |
| `RECEIVE_PALLET_REQUIRED` | 0 | 1 | `AddInventoryDevEx` |
| `CONVERSION_CUTTING_FEE` | 1 | 0 | Conversion |
| `INVOICE_TEMPLATE` | JFC | STANDARD | Sales invoice print |
| `XERO_DATABASE` | — | ITCOREPOSENZO | Xero upload jobs (today the name is written inside the procs) |
| `HEAD_OFFICE_BRANCH` | 888 | 888 | Today 119 literals in C#; read the setting in new code, replace the literals module by module |

**One ENZO database, several exe channels (answer 2026-10-16).** ENZO, ENZOCOMM, ENZOHRI, ENZOKIM and ENZOb2 are
update tokens on the one database `CORECSERP_001`: an update meant for the commissary goes to ENZOCOMM only, and the
branches keep their exe. So on ENZO, **several exe versions run against the same procs at the same time**, and every
SQL change must work for the oldest exe still in use on any channel (optional parameters, opt-in flags, `_OLD_`
backups: the same rule as JFC's web v2). A module moves to its new screen per channel; a setting is database-wide.
Next clients on the same server: `CORECSERP_002` (an ENZO restore of about 2026-05-30) and `CORECSERP_003` (VROSS),
after ENZO.

The exe stops testing `CompanyName == "JFC"` and reads the setting instead. `CompanyName` remains for display.
Unknown company → each setting has a safe default; the `DEFAULT_COMPANY` fall-through to the old ENZO path goes away.

### 4.2 One text per proc

For each module, one proc text that runs on both databases, built on JFC's current (hardened) version. It takes the
settings above and carries ENZO's good changes over. Rules:

- **No new `_JFC` names.** Where JFC and ENZO call different names today, the common proc keeps the name the exe calls,
  and the other name becomes a thin wrapper (or a synonym) during the transition, so the old exe keeps working on both
  databases.
- Every change follows the existing house rules: rename to `_OLD_` + create, guard hashes **per database** (ENZO's
  current texts are different, so its scripts have their own guard values), one transaction, post-check.
- **Each module gets an "old = new" test on ENZO data:** the same inputs through ENZO's `_OLD_` proc and the common
  proc, in a rolled-back transaction, with the footprint compared. Any difference must be an intended one, listed in
  the script header (a lock, a refusal, a fix). The `test-writer` agent builds these.

### 4.3 Schema alignment first (no behaviour change)

Additive and widening only, safe for the old exe:
- **Widen** ENZO's narrow columns to JFC's sizes: `DeliveryDetails.SeqNo` (3,0 → 10,0), invoice / reference / barcode
  widths, `InventoryDeliveryFIFO` amounts, `ClientLedger.TransCode`. Check indexes and computed columns that depend on
  them first.
- **Add** the missing tables, columns and table types the common procs need (empty or defaulted).
- **Do not drop** ENZO-only tables (BranchInventoryIN 41,696 rows, SalesManagement, InventoryINMonthEnd …): they become
  part of the common schema. JFC gets them empty if a common proc needs them.

## 5. Phases

Each phase can be released and rolled back on its own. ENZO stays on its current exe until phase 3, and every
SQL change keeps that exe working.

**Phase 0: ground (no ENZO change)**
1. Your answers to the questions in section 7.
2. **An ENZO test database: available (Q-E, 2026-10-16).** `CORECSERP_001_BACKUP` on the practice server
   (`itcore-apps.com\SQLEXPRESS,5281`, SQL Server 2022 Standard, compat 120 like ENZO, latest stock received
   2026-10-14), read through the registry key `AAITCRE\ConnSettingsEnzoTest` (DPAPI, nothing in files). You said
   nobody else uses it. All ENZO rehearsals run there first. Claude asks before the first write there.
3. **A baseline on ENZO** (read-only): the Exception Center checks that make sense without GL (stock, STS, sales
   lines, transfer receive), counts per module, 5 sample transactions per module traced (Process Trace) to compare
   after.
4. **Fix the company identification in the exe:**
   - `Login.cs:123-139` points the ENZOSTAGING update channel at JFC PRODUCTION. **A mix-up (Q-F, 2026-10-16): you
     correct it and define a new token for ENZO.** The new token's connection must come from the registry, not from
     a value written in `Login.cs` (CLAUDE.md rule 5; that file still holds a live login in two places).
   - `CompanyName` is read before the token / registry rewrite.
   - The skin is chosen from the JFC database name.

**Phase 1: settings + schema (no behaviour change)**
1. `SystemFeature` + `fn_Feature` on all tiers, with the values in 4.1. The exe reads them; every `CompanyName` branch
   is replaced by its setting, with the same outcome as today on both clients. Build, then the old = new UI pass on
   both.
2. ENZO schema alignment (4.3), plus **[82]** (the branch-transfer receive guard, already written and still missing
   on ENZO).
3. Compatibility: rewrite the one `STRING_SPLIT` in `ConversionPerBarcode.cs:430`. Keep ENZO at level 120 for now:
   raising it changes the optimizer for ENZO's heavy POS procs, so do that on its own later, measured on the test
   database.

**Phase 2: shared infrastructure on ENZO (installed, not yet called)**
1. GL writer `sp_PostCompoundTicket(Sales)` with the `GL_POSTING` switch (ENZO 0), `JournalEntryMapping` and the
   types. Needed because the common procs call it.
2. The FIFO engine (`spu_InvFIFO_*`, `sp_InvFIFO_*`, `fn_InvEligibleLots`, `fn_InvIsStickerBarcode` with ENZO's
   sticker rule), `sp_SOOrder_Lock`, `spu_STS_SyncInTransit` (no-op without GL), `spu_SO_*`.
3. The [89] DeliverySummary counter triggers and their repair, rehearsed on ENZO's counters first.

**Phase 3: module by module** (ENZO switches each module with a new exe build, or with a setting while both screens
exist). Each module: common proc(s) → old = new on the ENZO test DB → JFC DEV / STAGING (same text) → ENZO → JFC
PRODUCTION by you. Order, lowest risk and highest value first:

| # | Module | ENZO moves from → to | Watch |
|---|---|---|---|
| 1 | Branch transfer receive | [82] already | Complete-receipt guard |
| 1b | **Month-end count (new module, section 9)** | ENZO's scan → zero → re-create flow and the branch per-product count → one count document that adjusts the existing lots | Your "badly needed" item. Needs only phase 1 (settings, schema), not the GL writer or the FIFO engine, so it can start right after phase 1, ahead of the busy modules |
| 2 | Stock out | ENZO procs (IsWarehouse) → common, fix the AND/OR bug in ENZO's `spu_PostStockOutBarcode` guard | 20 uses, an easy first |
| 3 | STS receive | `ReceivedSTSBatchMode` + 2 calls → FIFO receive, one call (`spu_STS_ReceiveTransfer`) | ENZO's receive inserts branch stock itself today |
| 4 | STS process | `AddBranchOrderSTS` → V2 (FIFO engine, locks, no GL) | ENZO's barcode stamp `ReferenceCode = 'stsfifo'`, DevDetSeqNo, approval rule, pallet / batch modes |
| 5 | Sales order | `AddBranchOrder` → V2; confirm / return / credit memo common | ENZO writes ClientLedger itself, JFC through the GL writer: keep the AR subledger with GL off |
| 5b | **AR payments (Q-D: migrated into the ERP)** | Xero → `ClientPaymentsDevExAcctg` (`sp_AddPaymentClient` / `sp_ReversePaymentClient`) with GL off: invoice, client ledger and payment rows, no ticket / bank-recon item | An opening load from Xero (open invoices per customer, credits as negative rows, the [79] rule), tied to Xero's AR aging before go-live |
| 6 | Conversion | `HOConversion` → **`ConversionPerBarcode`** (decided 2026-10-16), NULL-safe MinQty into the common text; fix its `STRING_SPLIT` (phase 1) | Cutting fee setting; ENZO's 4,751 conversions a month run through `HOConversion` today, so it stays until every channel has the new exe |
| 7 | PO + receiving | `SP_ADDPOSUM`, `SP_POSTINVENTORY`, `sp_AddTempInventory` common, GL off | Primal / carcass / pallet receiving is ENZO's daily volume |
| 8 | Re-inventory IN | Replaced by 1b (section 9). JFC's `InventoryIN` screen (`sp_UploadInventoryINAdj`) is retired once JFC counts with 1b | JFC needs a GL variance account for count adjustments before it uses 1b |
| 9 | POS end-of-day deduction + night jobs | Last, biggest volume. Common deduction procs, the cost rule in 5.1, Xero database from the setting | Run times on ENZO's volume (1.96M sales lines) |

### 5.1 End-of-day sales cost: recommendation (Q-C, 2026-10-16)

**Today on ENZO** (`sp_SalesQtyToInventoryQtyEODSalesInvDeduct`, read-only): the FIFO walk writes each lot's own cost
on its FIFO row (right), but the cost it returns for the POS line is **the last lot's unit cost**
(`SET @TotalCost = @iCost`; the accumulation is commented out). Example: 10 kg sold, 4 kg from a lot at 200 and 6 kg
from a lot at 260: the line cost is 260 / kg (2,600), while the stock actually given up is 2,360 (236 / kg).

**Recommended: weighted average of the lots this sale used.**
- Line unit cost = Σ(qty taken × that lot's cost) / qty deducted, rounded once at the end; the FIFO rows keep each
  lot's exact cost, so the line total always equals what left the stock.
- Not a moving average over the whole product (that would need a new costing model and changes every report).
- Also in the same rewrite: drop `READPAST` (a lot locked by another session is skipped, so a later lot can go first,
  or nothing is deducted when all are locked); a sale bigger than the stock goes to a shortage list instead of
  stopping silently (POS V2's rule).
- No GL on ENZO, so this changes gross-profit reports only; on JFC it is the same number the GL would need.

**Conversion screen: `ConversionPerBarcode` (your decision, 2026-10-16)**: the standard scan + FIFO pattern, its own
tables, conversion date, with ENZO's NULL-safe MinQty carried over; `HOConversion` stays until every channel has the
new exe.

**Phase 4: clean-up**
- Remove the `CompanyName` branches and the old screens' menu routes, then retire the transition wrappers / `_JFC`
  names once no exe calls them.
- One exe build for every client; per-client update channels stay.
- Exception Center gets an ENZO profile (no GL checks).

## 6. Testing and safety

- Every script: house template (guard per database, one transaction, `_OLD_` backups, post-check), `sp-reviewer`,
  rehearsed rolled back on the ENZO test DB, then on JFC DEV / STAGING. You run ENZO production and JFC PRODUCTION.
- Every module: old = new on ENZO data (test-writer), Exception Center before / after, 5 traced transactions compared.
- **ENZO is a live operation** (receiving, conversion and POS every day, with night jobs at 23:45). Schedule ENZO
  changes outside 23:30–00:30 and away from receiving peaks, with the `_OLD_` backups as the rollback.
- Performance: ENZO's hot procs (EOD deduction, conversion FIFO, the three monitors at about 155,000 runs each) get
  a timing before / after on the test database.
- Also verified: `deploy-verifier` (with ENZO as a tier), and release notes per client (`release-notes-writer`).

## 7. Decisions (your answers, 2026-10-16)

| # | Question | Answer | Effect on the plan |
|---|---|---|---|
| 1 | GL on ENZO? | No GL; ENZO's sales module is outdated | `GL_POSTING = 0`; the sales order module moves to the current one (phase 3, row 5) |
| 2 | Test database, 002 / 003 | 002 = a restore (ENZO, data to about 2026-05-30); 003 = VROSS, another client, next after ENZO | A fresh restore of 001 is still needed (Q-E) |
| 3 | Third-party storage | At 888; a process may take a lot only when `IsWarehouse = 1` | One rule, no setting (4.1) |
| 4 | Barcodes | A01 supplier receiving, B01 STS process, C01 conversion, D01 manual inventory in, R01 return / branch transfer; **whole boxes: A01, D01, R01** | `fn_InvIsStickerBarcode` gets D01 / R01 (4.1) |
| 5 | A / X branch suffixes | Garbage on purpose, so the rows are never processed | Nothing to migrate |
| 6 | ENZO rules | STS must be approved before processing; **the month-end count needs a new workflow** | `STS_REQUIRE_APPROVED`; new module 1b, section 9 |
| 7 | Rollout | Module by module | As in section 5 |
| 8 | ENZO companies | One database; ENZO / ENZOCOMM / ENZOHRI / ENZOKIM / ENZOb2 are update channels | Several exe versions on one database (4.1) |

**Second round (2026-10-16):**

| # | Question | Answer | Effect on the plan |
|---|---|---|---|
| Q-A | JFC: D01 / R01 whole boxes? | Yes. D01 = inventory injection (no GL); R01 = STS + stock out together (returns, expired pull-outs) | One sticker rule (4.1) |
| Q-B | JFC: STS approved first? | Yes, with an option to bypass approval | `STS_REQUIRE_APPROVED` = 1 on both, 0 = bypass (4.1) |
| Q-C | End-of-day cost | ENZO "somehow averages"; recommend one | Weighted average of the lots used (5.1) |
| Q-D | AR on ENZO | Migrated into the ERP | New phase 3 row 5b, opening load from Xero |
| Q-F | ENZOSTAGING token | A mix-up; you correct it and define a new ENZO token | Phase 0 item 4 |
| Q-G1 | Count cut-off | Freeze stock movements at the branch (branches count with `BranchInventoryIN`) | 9.2 step 1 |
| Q-G3 | Re-weigh | Yes: re-weighed stock gets a D01 label, per box or per plastic | 9.2 step 2 |
| Q-G4 | Not counted | Goes to 0 | 9.2 step 3 |
| Q-E | Test database | `CORECSERP_001_BACKUP` on the practice server | Phase 0 item 2 |
| Q-G2 | 7/31 and 8/31 HO counts | Dropped: those months were done by hand, updating `ReferenceCode` and `Available` on the rows; too much hassle, so the process must change | Their hand method = the new module's method (9.7) |
| Q-G5 | Roles | Users given access to InventoryIN re-weigh and encode | Count rights = InventoryIN access (9.2) |
| Q-G6 | Today's duplicates | Merge back to one row per barcode | 9.6 |
| Q-G7 | Head office | Freeze all processes too (HO recounts actual items) | 9.2 step 1 |

| Q-C | Conversion screen | `ConversionPerBarcode` | Phase 3 row 6 |
| Q-G8 | Merge: which row stays | The original | 9.6 |

**Nothing open in the plan (2026-10-16).** Implementation is handed off in
`docs/handoff/2026-10-16_ENZO_Unification_Handoff.md`.

## 8. Rough size

- **Phase 0–1:** a few days, mostly settings plumbing and the schema script.
- **Phase 2:** about a week with tests.
- **Phase 3:** about 1–2 weeks per module for STS and sales order (the biggest), less for the small ones.
- **Module 1b, the count (section 9):** about 1–1.5 weeks (4 tables, about 6 procs, one screen shared by head office
  and branches, tests on ENZO data), after phase 1.
- **Phase 4:** a few days.

The test database is available, so phase 0 can start: the baseline on `CORECSERP_001_BACKUP`, then the phase 1
settings and schema script rehearsed there. The count design has every answer it needs.

## 9. Month-end count: a new workflow (module 1b)

### 9.1 How ENZO counts today (read-only, 2026-10-16)

Two separate screens, two different methods:

| | Head office 888 (`ReInventoryIn`) | Branches (`Branches/BranchInventoryIN`) |
|---|---|---|
| Counted by | barcode scan per box (`sp_StageBarcodeForReInventoryIN` → `InventoryINMonthEnd`), plus a manual tab for unlabelled stock that prints a new D01 label (`TempInventoryIN`) | quantity typed per product |
| Before the count | all stock set to 0 by hand | — |
| Posted by | `sp_CommitReInventoryIN`: a **new** `Inventory` row per scanned box, copying the old row (same barcode, ReferenceCode `INVIN-<batch>`) | `sp_BranchInventoryINProcess`: variance per product; + a new lot `INVCOUNT+<batch>`, − FIFO from the oldest lots |
| Stock ledger | **none** (no ledger row mentions INVIN; the zeroing has no row either) | one `INVCOUNT adjustment Batch n` row per product |

What the data shows:
- **HO counts:** 7/31: 2,660 scans in 49 batches; the August count (done on 9/1): 2,892 in 47; 9/30: 2,801 in 37.
  **Only the 9/30 count was posted** (34 of 37 batches: 1,956 new lots, 39,185.45 kg). The 7/31 and 9/1 scans never
  became stock rows (Q-G2).
- **The same box scanned twice:** 659 barcodes were scanned in two batches of the same count. Each batch checks only
  its own scans, so both would post. After 9/30, 2 boxes have two INVIN rows.
- **A re-created box comes back at its received weight, not at what was left.** The commit copies the old row's
  `Quantity`. On 9/30, 27 A01 boxes had 931 kg taken from them before the count and came back full (to confirm on the
  floor).
- **A barcode is no longer one row per box:** every count adds another row with the same barcode at the same branch
  (kept on purpose so scanning finds a reference), so every screen that finds a box by barcode has to pick the right
  row.
- **Branch count:** every product the branch does not type is sent as counted 0, so it is zeroed. The variance is
  taken from the stock when the screen was opened, so POS sales posted between opening and saving come off twice. The
  count ignores `IsWarehouse`. Keying slips post as typed:
  - branch 010 on 6/16 took 137,451.38 kg of PORKCHOP BI SLAB off (stock 137,488.80 → 37.42);
  - branch 009 on 9/30 added 34,397 KUM CHUN OYSTER SAUCE 150G and 19,540 MB HOT SAUCE 150ML (most likely a barcode
    typed into the quantity box). Both lots were later corrected by hand (stock now 21 / 20), but the ledger still
    shows +34,397 / +19,540.

### 9.2 The new design: count, compare, adjust (no zeroing, no new rows)

One **count document** per branch per month, with the same screens at head office and at the branches.

1. **Open the count** (supervisor): branch; location (commissary `IsWarehouse = 1`, third-party storage `0`, or
   both); count date (month end). The system takes a **snapshot**: every live lot with its `Available` = the book.
   **The branch is frozen while the count is open (Q-G1):**
   - Opening first deducts the branch's POS sales already uploaded up to the count date (the same end-of-day
     deduction), so the book includes them. A POS sale not yet uploaded is listed as a warning (the terminal is
     offline).
   - While open, every stock movement at that branch is refused with "count <no.> open": STS out / receive, branch
     transfer, stock out, conversion, sales order, receiving. The 23:45 end-of-day deduction skips the branch; its
     newer sales stay uploaded and are deducted right after the count is posted (or cancelled).
   - Because nothing moves, counted − snapshot = counted − book; the post still re-checks that no lot moved (refuses
     otherwise).
   - **Head office 888 is frozen too (Q-G7):** receiving, conversion, STS and transfers wait until its count is
     posted.
   - **Who (Q-G5):** users with InventoryIN access open, count, re-weigh and post. A line beyond the outlier limit
     still needs a second user (admin) to confirm.
2. **Count** (several people at once, each in their own session or zone under the same count):
   - **Whole box (A01 / D01 / R01):** scan; the box counts at its book weight.
   - **Re-weigh / repack (Q-G3):** a box whose weight is wrong, or that is split into plastics, is re-weighed in the
     count: the counter scans the box, types each piece's weight and prints a D01 label per piece. At posting the
     original lot goes to 0 and each piece becomes a new lot with the original's product, cost and FIFO date; the
     ledger rows link source → new label. The difference (sum of pieces − book weight) is the count variance.
     JFC caveat: the new lots must not count in the shipment's costing base (`fn_InvShipmentBase`, Known Bug #7), so
     they carry a `COUNT-<no.>` ReferenceCode that the base excludes.
   - **Tag or unlabelled stock (B01 / C01 / no barcode):** scan or pick the product, then type the weight.
   - **Stock with no label at all:** the manual tab, as today; it prints a D01 label, and the line becomes a new lot
     at posting.
   - **A barcode already counted in this count is refused**, whichever session scanned it.
   - **An unknown barcode, or a lot already at 0,** is "found": listed for review, not refused.
3. **Review** (supervisor), per lot and per product:
   - counted = book: nothing changes;
   - counted ≠ book: the difference is adjusted;
   - **in the book but not counted:** goes to 0 (Q-G4); the review lists them first, with quantity and cost, so a
     forgotten shelf is seen before posting;
   - found: back in at its own cost.
   The page shows quantity and cost per line and in total. A line beyond a limit (e.g. 10 × the book, or more than a
   set number of kg) needs a second confirmation. That would have stopped the 34,397 oyster sauce.
4. **Post** (one proc, one transaction, branch lock): **the existing lot is adjusted, not re-created.**
   - Its `Available` changes by (counted − snapshot), so a sale posted after the snapshot (POS end of day at 23:45) is
     neither lost nor taken twice.
   - Each line writes one stock-ledger row `COUNT <no.>` with the before / after quantity.
   - The barcode keeps one row, its cost and its FIFO place, and the ledger explains every change.
   - On JFC (`GL_POSTING = 1`) the same post books the variance to a mapped account; on ENZO it books none.
5. **After posting:** the count is read-only, with a variance report per product and category (quantity and cost)
   for management. A posted count can be reversed only while none of its lots has moved since.

### 9.3 What it replaces

- The hand "set everything to 0" step, `sp_CommitReInventoryIN` (re-creating rows) and `sp_BranchInventoryINProcess`
  (per-product variance). They stay in the database as `_OLD_` backups, and the old screens stay until every channel
  has the new exe.
- `InventoryINMonthEnd` / `TempInventoryIN` keep their history. The new tables are `InvCount` (header),
  `InvCountSnapshot`, `InvCountLine` and `InvCountSession`, with their own procs (house rule: a new module gets its
  own tables).

### 9.4 Checks (Exception Center, ENZO profile)

- the same barcode counted twice in one count;
- a live lot with `Available > Quantity` (a box that came back fuller than it was received);
- a count line far from its book (the limit above) posted without the second confirmation;
- more than one live row for one barcode at one branch (today's INVIN copies).

### 9.5 Questions for the count (Q-G)

All answered 2026-10-16 (section 7): 1 freeze; 2 dropped (done by hand); 3 re-weigh with D01; 4 uncounted = 0;
5 InventoryIN access; 6 merge; 7 head office frozen too. New: Q-G8 in 9.6.

### 9.6 Merging today's duplicates (Q-G6), measured on the test database

Head office 888, 2026-10-14 data:
- **2,095 count copies** (`ReferenceCode INVIN-…`) on 2,093 barcodes. 2,020 copies have their original row next to
  them; 75 have none (no other row at 888) and stay as they are. 2 barcodes have two copies.
- **The originals are all dead** (`Available` 0), and **1,045 copies are live**. So there is never more than one live
  row per barcode: stock totals by `Available` are right. What is doubled is the row count and `SUM(Quantity)`, and
  every screen that looks a box up by barcode can pick the wrong row.
- Copy and original have the same cost and the same received quantity. **623 copies have a different `IsWarehouse`
  from their original:** the count moved them between the commissary and third-party storage. The merge keeps the
  copy's (counted) value.
- **History on the copies, which a merge must keep:** 1,050 STS FIFO rows (`InventoryDeliveryFIFO`), 1,066 stock-ledger
  rows (`SequenceRefNum`), 7 POS deductions (`InventoryLedgerDeduct`), 2 stock-outs. Deleting the copies would leave
  these pointing at nothing.
- Also at 888, not caused by the count: 631 `stsfifo` rows, boxes sent to a branch and transferred back (a second row
  per box, the [82] note). Left alone for now; the new receive flow (phase 3) stops making them.

**Merge, one-off script (test database first, then ENZO by you, in a frozen window):**
1. Backup tables of every row touched.
2. Per pair: the original takes the copy's `Available` and `IsWarehouse`; every history row of the copy is repointed
   to the original's `SequenceNumber` (the tables above, plus every other table with a lot column, listed from the
   catalog first); one ledger row `COUNT MERGE <date>` records 0 → the live quantity.
3. The copy moves to an archive table and leaves `Inventory`.
4. Post-check: one row per barcode at 888 (apart from `stsfifo`), live stock per product unchanged to the gram, no
   history row pointing at a missing lot.

Q-G8, decided 2026-10-16: **keep the original** (older `SequenceNumber`, its receiving trail, its FIFO place).

### 9.7 Your temp-table idea vs. updating in place

Your idea: copy all available stock to a separate table, scan against that table, then insert into `Inventory`, so
`Inventory` stays clean. The first half is the design: that separate table is the **snapshot** (`InvCountSnapshot`),
and scanning looks the barcode up there. The difference is the last step:

| | Insert counted rows into `Inventory` | Update the existing row (the new module) |
|---|---|---|
| Rows per barcode | A new row per count, unless the old one is deleted | Always one |
| History (STS, POS, ledger rows pointing at the lot) | Deleting the old row breaks it (1,050 + 1,066 rows on today's copies) | Untouched |
| FIFO order / cost | New row = new sequence number, the box goes to the back of the queue | Keeps its place and cost |
| Audit | Nothing says what changed | One ledger row per change: before, counted, difference |

**Updating in place is what your team already did by hand for 7/31 and 8/31** (`ReferenceCode` and `Available`
edited on the rows). The new module does the same thing automatically: per count line, one update plus one ledger
row, inside one transaction, with the freeze, the review page and the outlier check in front of it.
