# ENZO onto the current ERP: implementation handoff (2026-10-16)

**Status: plan complete, every question answered, nothing built.** Work moves back to JFC matters and the hardening
backlog (`2026-10-14_Hardening_Handoff_to_Fable.md`). This file is what a session needs to pick ENZO up again
without re-reading the 10-15 / 10-16 conversation.

- **The plan (read it first):** `docs/plans/2026-10-15_ENZO_Unification_Plan.md`. Sections 4 (settings, one text per
  proc), 5 (phases + module order), 5.1 (end-of-day cost), 7 (all decisions), 9 (the month-end count module).
- **Investigation files:** `docs/handoff/enzo/` (index at the end).

## 1. Why

ENZO wants to use the ERP as it is today. Its database (`CORECSERP_001`) runs older copies of the shared procs (GL
calls commented out, `IsWarehouse = 1` filters, its own fixes) and an exe that picks flows by `CompanyName`. The goal:
**one exe and one text per proc for every client**, with the differences held in a settings table; ENZO gets the
hardened JFC flows (FIFO engine, STS V2, Sales V2, locks, error standard, Exception Center); ENZO's good fixes come into
the common text. ENZO's sales stay in its hybrid POS: sales are uploaded at the end of the day, then deducted from stock.

## 2. Environments and access rules

| What | Where | Rule |
|---|---|---|
| ENZO production | `erp.itcoreapps.com,4281 / CORECSERP_001`, key `AAITCRE\ConnSettingsEnzoReadOnly` | The login is db_owner, but **Claude only reads**: SELECT, `OBJECT_DEFINITION`, catalog views. Never EXEC (not even report procs), no DML, no DDL. The user runs every write. Same for 002 / 003 / TEST / ITCOREPOSENZO on that server (memory `enzo-db-read-only-by-rule`) |
| **ENZO test database** | `CORECSERP_001_BACKUP` on the practice server `itcore-apps.com\SQLEXPRESS,5281`, key `AAITCRE\ConnSettingsEnzoTest` (DPAPI) | ENZO data to 2026-10-14, SQL 2022 Standard, compat 120, login db_owner. Nobody else uses it (user). Every ENZO rehearsal runs here first. **Ask the user before the first write**, then rehearse rolled back as on JFC (memory `enzo-test-server`). Other databases on that server (ENZODEV, ENZOTESTING, STAGING_CORECSERP_001, CORECSJFC2026_STAGING …) are not targets |
| JFC DEV / STAGING / PRODUCTION | as in CLAUDE.md | Unchanged. A common proc text goes DEV → STAGING (user's go) → PRODUCTION (user) as usual |

Helpers: `.claude/skills/staging-rollout/scripts/db.ps1 -Key <key>` (reads the registry, prints server / catalog
first). Never write a login into a file.

## 3. Decisions (2026-10-16, plan section 7)

| Topic | Decision |
|---|---|
| GL | ENZO posts **no GL**: `GL_POSTING = 0` (JFC 1); the GL writer returns without a ticket |
| Third-party storage | One rule for every client: a process may take a lot only when `IsWarehouse = 1` |
| Whole boxes | **A01** (supplier), **D01** (inventory in / re-weigh / repack, no GL entry), **R01** (return / pull-out) are whole units: scan only, FIFO never splits them; **B01** (STS) / **C01** (conversion) are tags. **JFC too.** A D01 unit can be one plastic bag |
| STS approval | `STS_REQUIRE_APPROVED` = 1 on both; 0 = bypass (the user wants the switch) |
| End-of-day cost | Weighted average of the lots the sale used (plan 5.1). Today ENZO stores the last lot's unit cost |
| AR | Migrated into the ERP (phase 3 row 5b): customer payments with GL off, opening load from Xero |
| Conversion | `ConversionPerBarcode` (`HOConversion` stays until every channel has the new exe) |
| Channels | ENZO / ENZOCOMM / ENZOHRI / ENZOKIM / ENZOb2 are update tokens on ONE database: **several exe versions run on the same procs**, so every change must work for the oldest exe still out (optional parameters, opt-in flags, `_OLD_` backups) |
| `Login.cs` ENZOSTAGING token | Points at JFC PRODUCTION by mistake; **the user fixes it** and defines a new ENZO token (its connection from the registry, not from `Login.cs`) |
| A / X branch suffixes | Garbage on purpose; nothing to migrate |
| Rollout | Module by module |
| Month-end count | New module 1b (plan section 9): freeze the branch (head office too) while a count is open; count rights = users with InventoryIN access; re-weigh / repack in the count with D01 labels; uncounted = 0; adjust the existing lot in place with a ledger row (no zeroing, no new rows); merge today's duplicates keeping the **original** row |

## 4. Work order

Each step: script in the house template (rename to `_OLD_` + create, guard hash **per database**, one transaction,
post-check), sp-reviewer, rehearsed rolled back on the ENZO test DB, then JFC DEV / STAGING with the same text, then
ENZO and JFC PRODUCTION by the user. Scripts take the next shared `[NN]` number (work log). If a step touches an object
claimed in the Fable backlog, claim it there first.

### Step 0: baseline (read-only, test DB)
- Re-extract the ENZO definitions from the test DB and compare them with the 10-15 snapshot in `enzo/defs/enzo/`
  (ENZO may have changed since).
- The Exception Center checks that make sense without GL (stock, STS, sales lines, transfer receive); per-module counts;
  5 sample transactions per module traced, to compare after each module moves.
- Timings of ENZO's hot procs (EOD deduction, conversion FIFO, the three monitors) for the before / after.

### Step 1: settings + schema (no behaviour change)
- `SystemFeature` + `fn_Feature('KEY')` on every tier, values in plan 4.1; the exe reads them once at start-up and
  every `CompanyName == "JFC"` test becomes a setting (56 branches in 23 files: `enzo/findings/csharp_company_branches.txt`).
- ENZO schema alignment (plan 4.3): widen `DeliveryDetails.SeqNo` (3,0 → 10,0) and the narrow invoice / reference /
  barcode columns (`enzo/findings/enzo_cols.tsv` vs `prod_cols.tsv`); add the missing tables / columns / types. Never drop
  ENZO-only tables.
- [82] on ENZO (written, still missing there).
- `fn_InvIsStickerBarcode`: add D01 / R01 (changes 1 live JFC lot, 0.05 kg).
- `ConversionPerBarcode.cs:430`: replace `STRING_SPLIT` (fails at compat 120). Keep ENZO at compat 120 for now.

### Step 1b: month-end count (plan section 9), right after step 1
- Tables `InvCount`, `InvCountSnapshot`, `InvCountLine`, `InvCountSession`; procs to open (snapshot + freeze), stage a
  scan / typed weight / re-weigh piece, review, post (adjust in place + `COUNT <no.>` ledger rows; GL only when
  `GL_POSTING = 1`, mapped variance account for JFC), cancel, reverse (only while no lot moved); one screen for head
  office and branches; variance report.
- **Freeze:** every stock writer must refuse while a count is open at its branch, including the old exe on every
  channel. Two ways, decide with a test on ENZO's volume: a guard in each writer (receiving, conversion, STS, branch
  transfer, stock out, sales order, EOD deduction), or one trigger on `Inventory` that refuses changes at a frozen
  branch unless the count post sets a `SESSION_CONTEXT` flag (covers every writer at once, old exe and web v2 included;
  `Inventory` is hot, so measure). Opening a count first runs that branch's pending EOD deduction; the 23:45 job skips
  a frozen branch and catches up after the post.
- **Merge of today's duplicates (plan 9.6):** one-off script, test DB first, ENZO in a frozen window by the user.
  Per pair the original takes the copy's `Available` + `IsWarehouse`, the copy's history is repointed to the original
  (`InventoryDeliveryFIFO.SequenceReferenceNumber`, `InventoryLedger.SequenceRefNum` (text), `InventoryLedgerDeduct.
  InventorySequenceNumber`, `StockOutBarcodeDetails.InventorySeqNo`, plus every other lot column found in the catalog),
  one `COUNT MERGE` ledger row, the copy goes to an archive table. Post-check: one row per barcode at 888 (except
  `stsfifo`), live stock per product unchanged, no history row pointing at a missing lot. Queries:
  `enzo/count/t1.sql`–`t4.sql`.
- JFC's `InventoryIN` screen (`sp_UploadInventoryINAdj`) retires once JFC counts with 1b; JFC needs a GL variance
  account mapping first. Re-weigh lots on JFC carry a `COUNT-<no.>` ReferenceCode that `fn_InvShipmentBase` excludes
  (Known Bug #7).
- Exception Center (ENZO profile): duplicate barcode in one count; `Available > Quantity`; outlier line posted without
  the second confirmation; more than one live row per barcode at a branch.

### Step 2: shared infrastructure on ENZO (installed, not called)
GL writer with the switch + `JournalEntryMapping` + types; FIFO engine with the sticker rule; `sp_SOOrder_Lock`;
`spu_STS_SyncInTransit` (no-op without GL); [89] counter triggers (rehearse ENZO's counter repair first).

### Step 3: modules, in this order (plan section 5 table)
1 branch transfer receive ([82]) · 1b count · 2 stock out (fix ENZO's AND/OR in `spu_PostStockOutBarcode`) · 3 STS
receive (one call) · 4 STS process (V2; ENZO's `stsfifo` stamp, DevDetSeqNo, approval switch) · 5 sales order (V2) ·
5b AR payments (GL off; Xero opening load tied to Xero's aging) · 6 conversion (`ConversionPerBarcode`) · 7 PO +
receiving · 9 POS EOD deduction + night jobs (weighted cost, no `READPAST`, shortage list; Xero database from the
setting; schedule away from 23:30–00:30). Each module gets an old = new test on ENZO data (test-writer agent).

### Step 4: clean-up
Remove the `CompanyName` branches and old menu routes, retire the transition wrappers, one exe build for every
client, Exception Center ENZO profile.

## 5. Findings to carry (all read-only, not fixed)

- **EOD cost:** `sp_SalesQtyToInventoryQtyEODSalesInvDeduct` returns `SET @TotalCost = @iCost` (last lot's unit cost);
  `READPAST` can skip the oldest lot or deduct nothing; a sale bigger than stock stops silently.
- **Count (head office):** only the 9/30 count was posted (1,956 rows, 39,185.45 kg); 7/31 and 8/31 were done by hand
  (ReferenceCode + Available edited). 659 barcodes scanned twice in one count (per-batch check only). Re-created boxes
  come back at received weight (27 A01 boxes, 931 kg on 9/30). No ledger row for the zeroing or the INVIN rows.
- **Duplicates at 888 (test DB, 10-14):** 2,095 INVIN copies on 2,093 barcodes; originals all at 0; 1,045 copies live;
  623 copies changed `IsWarehouse`; 75 copies have no original; 2 barcodes have two copies. History on the copies:
  1,050 STS FIFO, 1,066 ledger, 7 POS, 2 stock-out rows. Plus 631 `stsfifo` rows (boxes transferred back to 888).
  Earlier hand clean-ups left tables like `InventoryINDuplicateDeleted…`, `InventoryZeroOut_04072026`.
- **Branch count:** uncounted products sent as 0; variance from the stock at screen load (sales in between come off
  twice); `IsWarehouse` ignored; slips posted as typed (010 on 6/16 −137,451.38 kg PORKCHOP; 009 on 9/30 +34,397 oyster
  sauce / +19,540 hot sauce, lots fixed by hand, ledger still shows them).
- ENZO is compat 120: `STRING_SPLIT`, `OPENJSON`, `GENERATE_SERIES` fail; `STRING_AGG`, `TRIM`, `GREATEST` work.
- `Login.cs` still holds a live hard-coded login in two places (flagged in CLAUDE.md's rule 5 sense; never copy it).

## 6. Index of `docs/handoff/enzo/`

| Folder | What |
|---|---|
| `findings/` | Read-only inventories of 10-15: `enzo_usage.tsv` (ENZO proc run counts), `enzo_modules.tsv` / `prod_modules.tsv`, `enzo_only_modules.csv`, `jfc_closure_missing_on_enzo.csv` (objects JFC flows call that ENZO lacks), `enzo_cols.tsv` / `prod_cols.tsv` (column compare), `param_compare.csv`, `enzo_jobs.tsv` (SQL Agent), `enzo_compat_probe.txt`, `csharp_company_branches.txt` + `ENZO_JFC_CSharp_Findings.txt` (exe forks), `procs_per_form.txt`, `main_menu_map.txt`, `hardcoded_888.txt`, `sticker_rules.txt`, `iswarehouse.txt` |
| `defs/enzo`, `defs/enzo_extra` | ENZO definitions as of 2026-10-15 (snapshot; re-extract before patching) |
| `defs/prod_jfc` | The JFC PRODUCTION `_JFC` counterparts |
| `defs/diffs`, `defs/diffs_vs_jfcvariant` | ENZO vs JFC text differences per proc |
| `queries/` | The read-only analysis queries (q1–q12) |
| `count/` | ENZO's count procs / functions / views and the duplicate queries `t1.sql`–`t4.sql` |

## 7. Waiting on

Nothing from the user on decisions. To resume: the user says when ENZO work restarts; then step 0 on the test DB
(ask before its first write).
