# Exception Center: one center for every module, run daily (plan, 2026-10-13)

**Ask (user, 2026-10-13):** run the exception checks daily so problems surface before staff or the accountant
find them; add checks for every module (AP, bank recon first; then PO, item costing, inventory, ...); run them in
the web portal's Exception Center (https://corexrpt.itcoresystems.com), consolidated with the checks the web
session already built, without building anything twice.

**Why:** the SO / STS integrity checks (`tools/ExceptionCenter/SO_STS_ExceptionCheck.sql`) found 7 CRITICAL
findings on PRODUCTION on 10-13 that had been sitting there since 10-01 (610,568.46 stuck in In Transit,
~5,508 kg missing from branch stock, 840 kg missing from a lot). Fixed by [69]. A daily run would have shown
them on 10-02.

---

## 1. What exists today (checked 2026-10-13)

| | Web portal Exception Center (other session) | This repo |
|---|---|---|
| Where | DB: `ExceptionDefinition` (registry), `sp_rpt_ExceptionCenter_Summary` (one row per code: `ExceptionCode, Findings, ValueAtRisk`), `sp_rpt_ExceptionCenter_Detail` (`@ExceptionCode` → its rows). Each check = a block inside those two procs. Menu in the portal. | `tools/ExceptionCenter/*.sql` scripts run by hand: SO / STS (17 checks X / S / T / G), POS V2 (P01–P15), bank recon GL vs recon. |
| Parameters | `@DateFrom`, `@DateTo`, `@AsOfDate` (ageing); thresholds hard-coded as "PLACEHOLDER" variables | `@FromDate`, `@StsFromDate`, tolerance |
| Kind of check | mostly **watch-lists** (pending approvals, ageing, reversals, cancelled cheques) + some integrity (negative qty, duplicate cheque no., the 13 BRC-* checks from the 10-09 handoff) | **reconciliation invariants**: subledger = GL = stock; every hit is a defect to fix |
| Checks | DEV: **38** definitions (procs 10-12). **STAGING and PRODUCTION: 19** (procs 09-25, byte-identical): the portal's `sql/23` (Inventory 5), `sql/26` (Sales 1) and `sql/42` (Bank Recon 13) are on DEV only. 28 of the 38 fire on DEV, some in the thousands. | SO / STS 17, POS V2 15, bank recon 1 script |
| Daily run / history | none: no scheduler, background service or email in the portal; 2-minute in-memory cache; no snapshot table (portal handoff) | none |
| Detail columns | rendered dynamically per check (no C# per check); `TOP (500)` + `TotalMatchCount`; a `Hint` column; unknown code → `RAISERROR`. `DrillDownRoute` is stored but unused. | |

PRODUCTION is **SQL Server 2022 Standard** (Agent available) → the daily run can be a server job.

## 2. Target

**One Exception Center: the web portal's** (registry + menu + drill-down already there). Every check lives in the
database, so the same code serves the portal, the daily job, the WinForms app (later, optional) and Claude's
read-only verifications.

1. **Check providers, not one growing proc.** Each module gets its own read-only procs with the portal's contract:
   - `sp_rpt_exc_<Module>_Summary @DateFrom, @DateTo, @AsOfDate` → `ExceptionCode, Findings, ValueAtRisk`
   - `sp_rpt_exc_<Module>_Detail @ExceptionCode, @DateFrom, @DateTo, @AsOfDate` → the drill-down rows
     (standard leading columns `Ref, Expected, Actual, Difference, Detail`, then module-specific ones).
   - `sp_rpt_ExceptionCenter_Summary / _Detail` become dispatchers: their existing blocks stay (or move to
     providers over time) and they also call the providers listed in the registry (agreed with the portal session 2026-10-13, with its four conditions: a failing provider shows one "unavailable" card; `ProviderProc` validated against `sys.procedures` + the `sp_rpt_exc_` prefix and run with `sp_executesql`; `sp_rpt_` prefix = read-only; incremental, with inline fallback).
   - Why: the two procs are already 37k / 67k characters edited by one session; two sessions editing the same
     proc text is how changes get lost. A provider per module = one owner per file.
2. **Registry columns added** (backward compatible, NULL = today's behaviour): `Module`, `Kind`
   (`INTEGRITY` = a defect, must be 0 / `WATCH` = an operational list), `ProviderProc`, `Owner`
   (`web` / `erp`), `ThresholdDays` (replaces the hard-coded PLACEHOLDERs), `Action` (what to do about a hit).
3. **Integrity checks are "as of now"**, not date-ranged: a broken invariant is broken whenever it started. They
   accept `@DateFrom / @DateTo` (contract) and use them only to limit the drill-down where it makes sense.
4. **Daily run + history.** SQL Agent job, 05:30, on PRODUCTION (DEV / STAGING on demand; see section 7):
   - `ExceptionRun (RunID, RunAt, DatabaseName, DurationMs)` and
     `ExceptionRunResult (RunID, ExceptionCode, Findings, ValueAtRisk, NewSinceLastRun)`;
   - "new since the last run" per code, so a known finding doesn't page anyone every morning;
   - notification (Database Mail) only for **new CRITICAL INTEGRITY** findings; the rest is on the portal.
   - Runs under a dedicated login that can read everything and write only the two run tables (not Claude's
     read-only login, which stays write-less).
5. **Claude's read-only login** gets `EXECUTE` on the `sp_rpt_exc_*` providers only (all pure SELECT), so PRODUCTION
   verification (CLAUDE.md rule, 2026-10-13) runs the same code as the portal.
6. **Rules carried over:** every new check is run on DEV, STAGING and PRODUCTION and every hit explained before it
   goes live (no check that cries wolf); a new bug found → a new check (CLAUDE.md, Exception Center section).

## 3. Phase 1 checks: AP and Bank Recon (owner: erp)

Codes follow the portal's style. The portal already has `VOU-DUP-CHECKNO`, `VOU-DUP-SUPPLIER-INVOICE`,
`VOU-STALE-OUTSTANDING-CHECKS`, `VOU-REVERSED-VOUCHERS`, `VOU-CANCELLED-CHECKS` and the 13 `BRC-*` checks: those
are kept as they are; nothing below repeats them.

### AP / supplier payments (`sp_rpt_exc_AP_*`)

| Code | Kind / Severity | Rule (0 = healthy) | Found by / why |
|---|---|---|---|
| AP-VOUCHER-LEGS | INTEGRITY / Critical | per voucher: Σ payment legs (APPaymentDetails) = CheckVoucher amount = GL bank credit = screen total (TransactionPaymentAP) = bank-recon OC item | the multi-branch split bug ([61], vouchers fixed by [63] / [66]) |
| AP-TICKET-UNBALANCED | INTEGRITY / Critical | every AP payment / expense / reversal ticket DR = CR | PV-AP bank leg at GROSS; MIRROR amount type (pre-existing issues list) |
| AP-SUPPLIER-LEDGER-CHAIN | INTEGRITY / Critical | SupplierLedger Ending = Beginning + Credit − Debit, chained per supplier | Feature 11 audit ([17] rebuilt it; the trigger keeps it; this proves it stays) |
| AP-ACCOUNT-VS-LEDGER | INTEGRITY / Critical | SupplierAccounts.AccountBalance = Σ ledger (Credit − Debit) | Feature 11: 11 accounts stuck at 0.00 |
| AP-INVOICE-BALANCE | INTEGRITY / High | ExpenseSummary / APAccounts: Balance = amount − paid − EWT − discount − offset; Status FULLYPAID ⇔ Balance 0 | NULL-balance reversal ([4]); PRIBLET FULLYPAID with 70,000 owed ([62]) |
| AP-REVERSAL-NOT-RESTORED | INTEGRITY / Critical | a reversed voucher (PaymentReversalAudit) restored the settled amount (cash − variance) on its invoices, and its ledger rows net to 0 | telegraphic reversal restored cash only ([62]) |
| AP-SUBLEDGER-VS-GL | INTEGRITY / High | open payables (expense + purchase balances) per payable account = GL 20101 / 20102 / 20103 | Feature 11 "still open" tie-out; needs the accountant's mapping of BF rows first (calibrate) |
| AP-CREDIT-NEGATIVE | INTEGRITY / High | supplier advance credit (OVERPAY − ADVANCEAPPLIED, not reversed) ≥ 0 | Feature 1 rule 60514 / 60519 |
| AP-DUP-CASH-ADVANCE | WATCH / High | two OUTSTANDING cash advances, same supplier and amount | CA 133 duplicate of 173 (still open) |
| AP-CHEQUE-REUSED | INTEGRITY / High | a cheque no. on a live voucher also recorded as cancelled (or two live vouchers) per bank | [55] / [57] rule |

### Bank recon (additions to the portal's 13 BRC-*; `sp_rpt_exc_BRC_*`)

| Code | Kind / Severity | Rule | Found by / why |
|---|---|---|---|
| BRC-STATEMENT-COPIED | WATCH / Warning | a month's statement balance equals the previous month's exactly | 10-13: six accounts' Aug 31 balance = their Jul 31 balance |
| BRC-DUP-PERIOD | INTEGRITY / Warning | two recon headers for one account and month (any branch) | PNB PESO Aug on 888 and 008 (header 1150) |
| BRC-NON-BANK-ACCOUNT | INTEGRITY / Warning | a recon header on an account that is not a bank account / not in the COA | 1010101, 101030103, 10102010 (test) |
| BRC-BF-DIFFERENCE | WATCH / Warning | a balance-forward (BF-PEACHTREE) period with a difference ≠ 0 | BDO PESO 2 1,978,452.67, WB 1,000,050.00 (Peachtree's own) |

Also in phase 1: get the portal's 10-12 version (incl. the 13 BRC-*) onto PRODUCTION; verify every BRC-* hit on
PRODUCTION against the bank-recon screen.

## 4. Later phases (one module at a time, same rules)

| Phase | Module | First checks (from bugs found this year) |
|---|---|---|
| 2 | SO / STS | port the 17 tested X / S / T / G checks into `sp_rpt_exc_SO_*` / `sp_rpt_exc_STS_*` (overlap to merge: portal `INV-TRANSFER-QTY-VARIANCE` ~ T02 / T05) |
| 3 | Inventory / item costing / conversion | GL inventory per branch = Σ Available × cost; lots at cost 0 (portal has INV-ZERO-COST: reuse); FIFO rows on missing lots; IsStock vs Available; output lot cost = Final Cost after Finalize; conversions FOR POSTING > N days; source qty = outputs + driploss |
| 4 | PO / purchasing, expenses | PO-linked expense costed once (Open decision 5); receipt vs PO (portal PUR-OVER-RECEIPT: reuse) |
| 5 | AR, GL general | customer account = client ledger; invoice balance columns (S02 beyond SO); any unbalanced ticket (all mnemonics); detail branch ≠ header branch; accounts not in the COA; inactive mapping rows |
| with go-live | POS V2, loan revaluation | P01–P15 (written); GL 20203 = loan balance |

## 5. Agreed with the web session (portal handoff `D:\SQLREF\webportal.md`, reply `docs/handoff/2026-10-13_ExceptionCenter_ERP_Reply_to_Portal.md`)

- **Provider model accepted**, names `sp_rpt_exc_<Module>_Summary / _Detail` (the portal's rule: every `sp_rpt_*`
  only reads), with its four conditions (section 2.1). The ERP side never edits the portal's monolithic
  `_Summary / _Detail` (two passes on them silently overwrite each other; it nearly cost the Inventory checks
  on 10-12). Rule for anyone who must edit them: re-pull `OBJECT_DEFINITION()` right before writing.
- **All six registry columns accepted**; `Kind` is wanted now (28 of 38 DEV checks fire). `Severity` is
  `Critical` / `Warning` only (varchar(10)): the ERP "High" maps to `Critical` when money or a ledger is out, else
  `Warning`. `IsActive` has no default on COREX001: always spell it out.
- **Contract:** Summary provider returns `ExceptionCode, Findings, ValueAtRisk` (dispatcher adds the registry
  columns); a row per owned code, `Findings = 0` when healthy, `ValueAtRisk NULL` when it can't be priced.
  Detail provider: dynamic columns, `TOP (500)` + `TotalMatchCount`, a `Hint` column, `RAISERROR` on an unknown code.
- **Overlaps ("one finding, one owner"):** `INV-TRANSFER-QTY-VARIANCE` (approved vs received) and T01–T05 (shipped
  lots / GL In Transit vs received) ask different questions → both stay, titled so the difference shows;
  `INV-ZERO-COST` stays the portal's, no ERP zero-cost check; the 13 inline BRC-* move into the ERP's
  `sp_rpt_exc_BRC_*` once the dispatcher is proven (the ERP owns the bank-recon tables).
- **`DrillDownRoute`:** not needed (ERP screens are WinForms); generic drill-down by code is enough.
- **Deployment prerequisite:** the portal's `sql/23`, `sql/26`, `sql/42` reach STAGING and PRODUCTION before any
  provider is validated across tiers. Numbering: the portal's `sql/NN` series and the ERP's `[NN]-...` series stay
  separate; scripts cross-reference each other in their headers.
- **The portal has no scheduler or email**; the 05:30 snapshot job is ERP-side (phase 2) and must be labelled with
  its run time wherever it is shown (a 05:30 snapshot won't match the live page at 10:00).

## 6. Order of work

| Step | Who | What |
|---|---|---|
| 1 | portal (STAGING on the user's approval), user (PRODUCTION) | `sql/23`, `sql/26`, `sql/42` → STAGING → PRODUCTION |
| 2 | portal | `sql/43`: registry columns + dispatcher with the four conditions, behind the inline blocks (DEV first) |
| 3 | ERP | `sp_rpt_exc_AP_*` (10 checks) + registry rows; build on DEV, validate on DEV / STAGING / PRODUCTION, explain every hit |
| 4 | ERP | `sp_rpt_exc_BRC_*` (4 new checks); later the 13 inline BRC-* move in, the portal deletes its blocks in the same release |
| 5 | ERP | phase 2: `ExceptionRun` / `ExceptionRunResult` + 05:30 Agent job on PRODUCTION; EXECUTE on `sp_rpt_exc_*` for Claude's read-only login |
| 6 | ERP | port SO / STS into `sp_rpt_exc_SO_* / _STS_*`; then inventory / item costing, PO, AR, GL (section 4) |

## 7. Decisions (user, 2026-10-13)

1. **Findings are read in the portal only**, plus a **daily digest email**: counts per category (INTEGRITY first,
   new since the last run marked) and a link to https://corexrpt.itcoresystems.com Exception Center; no row
   detail in the mail. Recipients: eulen.avancena@itcsi.com.ph, rowena.ompad@itcsi.com.ph,
   rhealdwin.tumakay@itcsi.com.ph. Built with the snapshot job (phase 2): SQL Server Database Mail on the 7701
   instance, sent after the 05:30 run. Recipients are kept in a config row, not in proc code. The SMTP account /
   Database Mail profile is set up by the user on the server: profile **`COREX_Mail`** (7701, created 2026-10-13; no credentials in any script); the job script only
   names the profile. If the run fails, the digest says so instead of staying silent.
   **Status 2026-10-13: email set-up postponed by the user (pending).** Database Mail is enabled on 7701 and the
   profile exists, but the SMTP login is not set yet (test mail failed: no username); see the work log for the
   steps left. Until then the portal is the only channel.
2. **05:30 snapshot job:** yes, ERP-side, PRODUCTION only.
3. **DEV / STAGING: on demand**, STAGING scheduled only during a validation window: yes.
4. **The portal session applies `sql/23`, `sql/26`, `sql/42` to STAGING:** approved by the user (step 1).
