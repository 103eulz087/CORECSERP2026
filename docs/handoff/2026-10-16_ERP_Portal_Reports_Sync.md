# Handoff: ERP ↔ web portal, keeping the reports in sync (2026-10-16)

**From:** CORECS ERP session (WinForms exe + the shared SQL)
**To:** CORE Reporting Portal session
**Follows:** your `webportal.md` (2026-10-13) and our reply `2026-10-13_ExceptionCenter_ERP_Reply_to_Portal.md`
(sections 1–9).
**Measured:** read-only on PRODUCTION (`PRODJFC_COREX`, 7701) and STAGING (6601), 2026-10-16.

**Purpose (the developer's ask):** the two sessions build reports on ONE database. No report built twice, none
missing, and no report quietly reading a source the other side has retired. This file: the state of the Exception
Center per tier, three problems found in report procs the exe does not call (probably yours), the ERP reports and
business rules you can rely on, and the full inventory of report objects with who calls them (appendix). Please reply
with section 6.

---

## 1. Ownership rule (your proposal, agreed)

- **One report / one finding, one owner.** The side that owns the source tables owns the report or check; the other
  side reuses it (calls the proc) instead of writing a second query. If both need it, it is ONE proc.
- `sp_rpt_*` only ever reads (your invariant; the ERP follows it: `sp_rpt_exc_<Module>_*` providers, `fn_rpt_*`).
- A shared proc (called by both, e.g. `sp_rpt_ItemCostingRecon_List`, `sp_rpt_ItemCostingReport_Master`) is changed
  only by its owner, keeping its result shape or adding columns at the end; the owner tells the other side in its
  handoff before deploying.
- Script numbers stay separate: ERP `SQL/[NN]-…` (next free **[101]**; [100] = user skin per account; [98] = GL Detail Transaction Owner column, [99] = Bank Recon GL movement `sp_rpt_BankRecon_GLMovement`, 2026-10-16), portal `sql/NN` (next free after **43**).
- Before recreating anything the other side created: re-pull `OBJECT_DEFINITION()` on that tier first (your rule from
  section 1; it saved the Inventory checks once).

## 2. Exception Center: state per tier today

**⚠️ 2026-10-16: the developer restored PRODUCTION's backup over DEV (COREX001) and STAGING.** All three tiers are
now identical (1,245 module definitions, same hashes, checked read-only after the restore). Everything that existed
only on DEV / STAGING is gone, including **your `sql/23`, `sql/26`, `sql/42` and `sql/43`** (and the ERP's `[77]`
router on DEV / STAGING):

| Tier | Definitions | `ExceptionDefinition` columns | ERP AP provider |
|---|---|---|---|
| DEV, STAGING, PRODUCTION (all the same) | **19** | **8** | provider functions / Summary / Detail present ([70], [78]), **no router, no AP rows** |

So every tier lacks `sql/23 → 43` now. The ERP side is ready and waiting:

1. You: re-apply `sql/23 → 26 → 42 → 43` on DEV, then STAGING (with the developer's approval), and hand the
   developer the PRODUCTION runbook. Re-pull the definitions first: they are PRODUCTION's 09-25 bodies again.
2. Then ERP `[77]` (router + the AP registry rows) and an `[78]` re-run (adds the two shipment costing checks,
   AP-EXPENSE-COSTING-DRIFT / AP-COSTING-BASE-AMBIGUOUS, to the AP provider) follow on each tier: the ERP session on
   DEV / STAGING, the developer on PRODUCTION.
3. The ERP session verifies read-only afterwards (portal summary = provider functions, 0 UNAVAILABLE).

Checks still living only on the ERP side (`tools/ExceptionCenter/`, run by hand, not in the portal yet):
`SO_STS_ExceptionCheck.sql` (X / S / T / G codes, 25 checks), `BankRecon_GLvsRecon_Check.sql` (sections 1–6; the BRC
checks you took in `sql/42` came from it), `POSV2_ExceptionCheck.sql` (P01–P15; POS V2 not live yet). They move into
providers module by module after step 2 (S, then T, then X / G), one provider per module, so nothing is lost or
doubled. Your `INV-TRANSFER-QTY-VARIANCE` / `INV-TRANSFER-PENDING-RECEIPT` / `INV-ZERO-COST` stay yours (reply
section 1–2).

## 3. ⚠️ Three problems in report procs the exe does not call

The exe calls none of the procs below, so if they are on a portal page, the page is affected. Please check which
ones your pages call (section 6.1).

### 3.1 Six procs read `GLSummary`, which stopped on 2026-08-31

`GLSummary` was filled by the old daily GL posting, retired on 2026-09-30 (the exe's GL reports are real-time from
`TicketDetails` since then). On PRODUCTION its last `PostingDate` is **2026-08-31**: every September and October entry
is missing, and July / August were already stale (back-dated, edited and reversed tickets after posting; e.g. head
office AR-Trade as of 08-31 was 178.69M in GLSummary vs 156.19M in the tickets).

| Proc (not called by the exe) | Reads | Use instead (what the exe calls) |
|---|---|---|
| `sp_rpt_TrialBalance` | `vw_GLSummaryMonthly` | `sp_rpt_TrialBalanceRealTime` |
| `sp_rpt_BalanceSheet` | `sp_rpt_BalanceSheetWithDate` → GLSummary | `sp_rpt_BalanceSheetRealTimeSingleGrid` |
| `sp_rpt_IncomeStatement` | `sp_rpt_IncomeStatementWithDate` → GLSummary | `sp_rpt_IncomeStatementRealTimeSingleGrid` / `…RealTimeAllBranchesPivot` |
| `sp_rpt_GLDetailLedger` | `sp_rpt_GLDetailLedgerWithDate` → GLSummary | `sp_rpt_GLDetailLedgerRealTime` |
| `sp_rpt_ConsolidatedGL` | `sp_rpt_ConsolidatedGLWithDate` → GLSummary | `sp_rpt_ConsolidatedGLRealTime` |
| `sp_rpt_BankReconciliation` | `sp_rpt_BankReconciliationWithDate` → GLSummary | `sp_rpt_BankReconciliationRealTime` (= the Bank Recon screen's figures) |

Also on GLSummary (the exe's old "WithDate" / "Live" variants, kept only as history): see the appendix notes. Your
Exec / DataHealth procs were already moved off it on 10-01 (`…_GLSUMMARY_20260930` backups), good.

### 3.2 `sp_rpt_GeneralLedger` counts cross-branch lines once per branch

It joins `TicketMaster` on `TicketNumber + ReferenceNumber` only. A cross-branch entry (Manual JV, multi-branch
expense) has one master per branch under the same ticket number, so each line is counted once per branch master.
**PRODUCTION, September 2026:** debits 375,991,681.69 through the join vs **349,812,225.68** in `TicketDetails` alone
(+26.2M); per account e.g. 20103 −13,270,491.41 vs −2,928,191.79, 60110 6,415,500.00 vs 493,500.00 (13×), 503
1,833,202.49 vs 538,220.49. The exe's GL report had the same bug and was fixed by ERP script 40
(`sp_rpt_GeneralLedger_WithRunningBal`).

**Rule:** GL amounts come from `TicketDetails` alone. If a master column is needed, join on
`TicketNumber + BranchCode` (+ `ReferenceNumber`), never on the ticket number alone.

### 3.3 The four-part master join in `sp_rpt_Exec_Summary`, `sp_rpt_DataHealthCheck`, `sp_rpt_AR_Aging`

They join `TicketMaster` on `TicketDate + SupplementaryNumber + …`. Measured on DEV on 09-30: such joins drop lines
whose master is on another branch or has a blank `BranchCode` (the 07-31 opening ticket 1 has a blank BranchCode;
some CONV-FINALIZE lines sit under a different branch than their master), 858 lines then. Not measured on PRODUCTION
for your exact predicates: please compare each proc's totals against `TicketDetails` alone for one month (section
6.2). If they tie, nothing to do.

## 4. ERP reports and objects you can reuse (don't rebuild)

New or changed since 10-13, all read-only, same result shape on every tier where installed:

| Report | Object(s) | Where in the exe | Tiers |
|---|---|---|---|
| Invoice register (per series, DUPLICATE / GAP / JUMP) | `sp_rpt_InvoiceRegister`, `fn_rpt_DocNoSplit` | REPORTING › SALES › Registers | DEV, STAGING, PRODUCTION ([92]) |
| Collection receipt register | `sp_rpt_CollectionReceiptRegister` | same | same |
| EWT payable ledger (20104, FIFO paid / unpaid) | `sp_rpt_EWTPayableLedger` | same (admins / accounting) | same |
| GL real-time set | the "Use instead" column of 3.1 + `sp_rpt_GeneralLedger_WithRunningBal`, `sp_rpt_GLDetailTransactionRealTime` (GL Detail Transaction, also on the Accounting Board; **ERP [98], 2026-10-16: adds `[Owner]` as the LAST column** = the line's `TicketMaster.Owner` (first version `[Supplier Name]` replaced the same day, DEV only); DEV now, STAGING / PRODUCTION on the developer's go; existing columns unchanged) | Accounting Reports | all |
| Item costing recon (shipment vs linked expenses) | `sp_rpt_ItemCostingRecon_List` (2 result sets), `sp_rpt_ItemCostingRecon_ExpenseTickets`; cost base = `fn_InvShipmentBase()` | Item Costing Recon | all (PRODUCTION's `_List` carries a hand edit: `TargetDate` as DateOrder) |
| Bank recon | `fn_BankRecon_Figures`, `sp_BankRecon_GetPeriod`, `sp_BankRecon_GetPeriodSummary`, `fn_rpt_BankRecon_GLvsRecon` | Bank Recon screen | all |
| POS V2 (not live yet) | `sp_rpt_POSV2_Shifts / _SalesJournal / _Returns / _NeedsAttention`, `fn_POSV2_ZReadings` | POS V2 Reports | none since the 10-16 restore (was DEV only; [58]–[60] to be re-installed) |
| AP Exception Center provider | `fn_rpt_exc_AP_Findings`, `fn_rpt_exc_AP_ShipmentCosting`, `sp_rpt_exc_AP_Summary / _Detail / _Provider` | (portal) | see section 2 |

## 5. Business rules that change report results (since 10-13)

Any report over these tables must follow them; the Exception Center codes in brackets watch them.

1. **Cancelled documents** ([96]): a reversed single expense is `ExpenseSummary.Status = 'CANCELLED'`, Balance 0, lines
   CANCELLED, with a mirror ticket; a reversed Manual JV keeps its rows, `Status` on the posted list, recon items
   voided. Exclude CANCELLED from "open / owed" figures (your `sp_rpt_APEXP_Aging` already does via `Balance > 0`).
   (G05)
2. **Reversal tickets are dated like their source** (since 10-09): a reversal falls in the source's month. The status
   `REVERSED` sits on the reversal ticket itself, so a `Status = 'POSTED'` filter drops reversals and leaves the
   original counting.
3. **`TicketMaster.ReferenceNumber` is not a document key**: AR payment references and sales PO numbers come from
   different counters and meet. Scope by mnemonic family + `ReferenceKey` (AP: `ReferenceKey` = voucher id; AR:
   Mnemonic `OR-%`). (G04)
4. **`TransactionChargeSales.InvoiceNo` is not unique**: match `InvoiceNo + ReferenceNo + CustomerKey`. (S06)
5. **Negative `TransactionChargeSales` rows = balance-forward customer credits** from the go-live load (205 open on
   PRODUCTION, −2,079,610.34); they are used against invoices ([79]). AR aging should show them as credits, not net
   them silently.
6. **Shipment cost base** = `fn_InvShipmentBase()` (the PO branch's lots), never `SUM(Quantity) WHERE ShipmentNo = …`
   (STS copies count twice).
7. **Sales-order delivery counters** (`DeliverySummary.TotalItem / Sold / Returned / QtyDelivered / ActualQty`) are
   kept by triggers since [89] (= the lines). Raw ADO.NET is unaffected; an ORM must not use `OUTPUT` without `INTO`
   on those two tables (error 334).
8. **Bank recon "open in period P"** = not cleared, OR cleared in a month after P (`BankStatementRecon.ClearedPeriodEnd`);
   reversed / voided items are hidden; `sp_BankRecon_AutoMatch` is disabled (93020).
9. **Suppliers:** `Supplier.isPayableBoth` (new); IMPORT = 000121–000129 + 000132, every other supplier LOCAL ([93]).
10. **Products are the same at every branch** ([94]): a product exists at all 15 branches with the same VAT flag /
    type / price.
11. **A loan payable is not an expense** (ERP [105], 2026-10-17; DEV first): the PROFOOD EUR loan LOAN051618 is one
    `ExpenseSummary` row with `PostingMode = 'LOAN'` (PayableAccountCode **20203**, ~57.5M, one `ExpenseMaster` line,
    supplier-ledger rows), paid in Vouchering Telegraphic and moved by every month's revaluation. **Your reports must
    leave `PostingMode = 'LOAN'` out of expense figures:** `sp_rpt_APEXP_Aging` (it would show 57.5M as AP-expense
    aging) and `sp_rpt_DataHealthCheck` check 13 / `sp_rpt_DataHealthCheckDetail` Seq 13 (the AP subledger vs GL
    20101–20103 gap would show +57.5M CRITICAL; the loan is in 20203). `ISNULL(PostingMode, '') <> 'LOAN'` changes
    nothing else today (every other row is SINGLE or MULTI-MANUAL, none NULL). The AP Exception Center checks keep
    the row on purpose (its balance must equal its supplier ledger).

## 6. What the ERP needs back

1. **Your page → proc list** (every portal report page and the procs it calls), so the appendix's "not in the exe" rows
   can be marked portal / unused. In particular: does any page call a proc from 3.1 or `sp_rpt_GeneralLedger`?
2. **The 3.3 tie-out** (one month, your three procs vs `TicketDetails` alone).
3. **The PRODUCTION runbook timing** for `sql/23 → 43` (section 2), so `[77]` / `[78]` can follow the same day.
4. Anything the portal **writes** to shared tables besides `sp_portaladmin_*` (none known).
5. Agreement on section 1, or changes to it.

Once 6.1 is back, the ERP side will mark the unused old procs in the appendix as candidates to retire (the developer
decides; nothing is dropped without a backup).

---

## Appendix: report objects in the shared database (STAGING, 2026-10-16, taken just before the restore)

Compared again after the restore: the same list, minus two objects that were never on PRODUCTION:
`sp_rpt_exc_AP_Provider` (ERP `[77]`) and `fn_rpt_BankRecon_GLvsRecon` (your `sql/42`). Both come back with section 2.

131 objects named `sp_rpt_*`, `spr_*`, `fn_rpt_*`, `vw_rpt_*`, `sp_portaladmin_*` … (backups `_OLD_` / `_PRE<NN>_`
excluded). "Called by the exe" = the name appears in the exe's C# (scratch / demo folders ignored). 63 are called by
the exe, 68 are not (yours, or unused).

| Object | Type | Modified (STAGING) | Called by the exe (first files) | Note |
|---|---|---|---|---|
| `fn_rpt_BankRecon_GLvsRecon` | IF | 2026-10-13 | — (not in the exe: portal, or unused) |  |
| `fn_rpt_DocNoSplit` | IF | 2026-10-15 | — (not in the exe: portal, or unused) |  |
| `fn_rpt_exc_AP_Findings` | IF | 2026-10-15 | — (not in the exe: portal, or unused) |  |
| `fn_rpt_exc_AP_ShipmentCosting` | IF | 2026-10-15 | — (not in the exe: portal, or unused) |  |
| `sp_portaladmin_Access_SetGrants` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_portaladmin_Access_SetUser` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_Access_GetUser` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_Access_ListModules` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_Access_ListUsers` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_Access_RecentAudit` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_Agent_Scorecard` | P | 2026-09-25 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_AP_Aging` | P | 2026-09-15 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_APEXP_Aging` | P | 2026-09-15 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_AR_Aging` | P | 2026-09-15 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_BalanceSheet` | P | 2026-06-22 | — (not in the exe: portal, or unused) | reads GLSummary (stale since 08-31) |
| `sp_rpt_BalanceSheetLiveWithDate` | P | 2026-09-09 | HOFormsDevEx/AccountingReportsForm.cs,HOFormsDevEx/AccountingReportsFormV2.cs | reads GLSummary (stale since 08-31) |
| `sp_rpt_BalanceSheetLiveWithDateSingleGrid` | P | 2026-09-13 | HOFormsDevEx/AccountingReportsFormV2.cs | reads GLSummary (stale since 08-31) |
| `sp_rpt_BalanceSheetPerBranchInventory` | P | 2026-09-08 | HOFormsDevEx/AccountingReportsForm.cs | reads GLSummary (stale since 08-31) |
| `sp_rpt_BalanceSheetPerBranchInventorySingleGrid` | P | 2026-09-11 | HOFormsDevEx/AccountingReportsFormV2.cs | reads GLSummary (stale since 08-31) |
| `sp_rpt_BalanceSheetRealTimeSingleGrid` | P | 2026-09-30 | HOFormsDevEx/AccountingReportsFormV2.cs |  |
| `sp_rpt_BalanceSheetWithDate` | P | 2026-09-08 | HOFormsDevEx/AccountingReportsForm.cs,Reporting/AccountingReportsForm.cs | reads GLSummary (stale since 08-31) |
| `sp_rpt_BalanceSheetWithDate_07132026` | P | 2026-07-13 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_BankReconciliation` | P | 2026-06-22 | — (not in the exe: portal, or unused) | reads GLSummary (stale since 08-31) |
| `sp_rpt_BankReconciliationRealTime` | P | 2026-10-08 | HOFormsDevEx/AccountingReportsFormV2.cs |  |
| `sp_rpt_BankReconciliationReport` | P | 2026-06-28 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_BankReconciliationWithDate` | P | 2026-07-13 | HOFormsDevEx/AccountingReportsForm.cs,HOFormsDevEx/AccountingReportsFormV2.cs,Reporting/AccountingReportsForm.cs | reads GLSummary (stale since 08-31) |
| `sp_rpt_BankReconciliationWithDate_07132026` | P | 2026-07-13 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_CollectionReceiptRegister` | P | 2026-10-15 | AccountingDevEx/AccountingRegistersFrm.cs |  |
| `sp_rpt_ConsolidatedGL` | P | 2026-06-22 | — (not in the exe: portal, or unused) | reads GLSummary (stale since 08-31) |
| `sp_rpt_ConsolidatedGLRealTime` | P | 2026-09-30 | HOFormsDevEx/AccountingReportsFormV2.cs |  |
| `sp_rpt_ConsolidatedGLWithDate` | P | 2026-09-08 | HOFormsDevEx/AccountingReportsForm.cs,HOFormsDevEx/AccountingReportsFormV2.cs,Reporting/AccountingReportsForm.cs | reads GLSummary (stale since 08-31) |
| `sp_rpt_ConversionReport_Master` | P | 2026-09-07 | Reporting/ConversionReportMasterDetail.cs |  |
| `sp_rpt_ConversionReport_Output` | P | 2026-09-07 | Reporting/ConversionReportMasterDetail.cs |  |
| `sp_rpt_ConversionReport_Source` | P | 2026-09-07 | Reporting/ConversionReportMasterDetail.cs |  |
| `sp_rpt_DailyBranchActivity` | P | 2026-09-15 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_DataHealthCheck` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_DataHealthCheck_GLSUMMARY_20260930` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_DataHealthCheckDetail` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_EWTPayableLedger` | P | 2026-10-15 | AccountingDevEx/AccountingRegistersFrm.cs |  |
| `sp_rpt_exc_AP_Detail` | P | 2026-10-14 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_exc_AP_Provider` | P | 2026-10-14 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_exc_AP_Summary` | P | 2026-10-14 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_ExceptionCenter_Detail` | P | 2026-10-13 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_ExceptionCenter_Summary` | P | 2026-10-13 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_Exec_BranchScorecard` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_Exec_CashPosition` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_Exec_FlowBar` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_Exec_FlowBar_GLSUMMARY_20260930` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_Exec_InventoryByBranch` | P | 2026-09-30 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_Exec_SalesTrend` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_Exec_Summary` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_Exec_Summary_GLSUMMARY_20260930` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_Exec_Watermark` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_GeneralLedger` | P | 2026-06-28 | — (not in the exe: portal, or unused) | joins TicketMaster without BranchCode: cross-branch lines counted per branch |
| `sp_rpt_GeneralLedger_WithRunningBal` | P | 2026-10-07 | HOFormsDevEx/AccountingReportsForm.cs,HOFormsDevEx/AccountingReportsFormV2.cs |  |
| `sp_rpt_GLDetailLedger` | P | 2026-06-22 | — (not in the exe: portal, or unused) | reads GLSummary (stale since 08-31) |
| `sp_rpt_GLDetailLedgerRealTime` | P | 2026-10-12 | HOFormsDevEx/AccountingReportsFormV2.cs |  |
| `sp_rpt_GLDetailLedgerWithDate` | P | 2026-07-13 | HOFormsDevEx/AccountingReportsForm.cs,HOFormsDevEx/AccountingReportsFormV2.cs,Reporting/AccountingReportsForm.cs | reads GLSummary (stale since 08-31) |
| `sp_rpt_GLDetailLedgerWithDate_07132026` | P | 2026-07-13 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_GLDetailTransactionRealTime` | P | 2026-09-30 | HOFormsDevEx/AccountingReportsFormV2.cs |  |
| `sp_rpt_GLDetailTransactionReport` | P | 2026-09-28 | HOFormsDevEx/AccountingReportsForm.cs,HOFormsDevEx/AccountingReportsFormV2.cs | reads GLSummary (stale since 08-31) |
| `sp_rpt_GLDetailTransactionReport_07282026` | P | 2026-07-28 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_GLPeriodStatus` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_IncomeStatement` | P | 2026-06-22 | — (not in the exe: portal, or unused) | reads GLSummary (stale since 08-31) |
| `sp_rpt_IncomeStatementAllBranchesPivot` | P | 2026-07-13 | HOFormsDevEx/AccountingReportsForm.cs,HOFormsDevEx/AccountingReportsFormV2.cs | reads GLSummary (stale since 08-31) |
| `sp_rpt_IncomeStatementAllBranchesPivot_TEST` | P | 2026-09-13 | HOFormsDevEx/AccountingReportsForm.cs,HOFormsDevEx/AccountingReportsFormV2.cs | reads GLSummary (stale since 08-31) |
| `sp_rpt_IncomeStatementAllBranchesPivot_TEST_07142026` | P | 2026-07-14 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_IncomeStatementLiveAllBranchesPivot` | P | 2026-09-26 | HOFormsDevEx/AccountingReportsFormV2.cs | reads GLSummary (stale since 08-31) |
| `sp_rpt_IncomeStatementLiveWithDate` | P | 2026-09-09 | HOFormsDevEx/AccountingReportsForm.cs,HOFormsDevEx/AccountingReportsFormV2.cs | reads GLSummary (stale since 08-31) |
| `sp_rpt_IncomeStatementLiveWithDateSingleGrid` | P | 2026-09-13 | HOFormsDevEx/AccountingReportsFormV2.cs | reads GLSummary (stale since 08-31) |
| `sp_rpt_IncomeStatementRealTimeAllBranchesPivot` | P | 2026-09-30 | HOFormsDevEx/AccountingReportsFormV2.cs |  |
| `sp_rpt_IncomeStatementRealTimeSingleGrid` | P | 2026-09-30 | HOFormsDevEx/AccountingReportsFormV2.cs |  |
| `sp_rpt_IncomeStatementWithDate` | P | 2026-09-08 | HOFormsDevEx/AccountingReportsForm.cs,Reporting/AccountingReportsForm.cs | reads GLSummary (stale since 08-31) |
| `sp_rpt_IncomeStatementWithDateSingleGrid` | P | 2026-09-13 | HOFormsDevEx/AccountingReportsFormV2.cs | reads GLSummary (stale since 08-31) |
| `sp_rpt_Inventory_Overview` | P | 2026-10-06 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_InventoryReport_Detail` | P | 2026-09-09 | Reporting/InventoryReport.cs |  |
| `sp_rpt_InventoryReport_Summary` | P | 2026-09-09 | Reporting/InventoryReport.cs |  |
| `sp_rpt_InvoiceRegister` | P | 2026-10-15 | AccountingDevEx/AccountingRegistersFrm.cs |  |
| `sp_rpt_ItemCostingRecon_Detail` | P | 2026-09-25 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_ItemCostingRecon_ExpenseTickets` | P | 2026-09-26 | Reporting/ItemCostingReconReport.cs |  |
| `sp_rpt_ItemCostingRecon_Header` | P | 2026-09-25 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_ItemCostingRecon_List` | P | 2026-10-15 | Reporting/ItemCostingReconReport.cs |  |
| `sp_rpt_ItemCostingReport_Detail` | P | 2026-10-10 | Reporting/ItemCostingReport.cs |  |
| `sp_rpt_ItemCostingReport_Master` | P | 2026-09-29 | Reporting/ItemCostingReport.cs |  |
| `sp_rpt_LiveTrends` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_LiveTrends_Watermark` | P | 2026-10-01 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_SupplierPriceComparison` | P | 2026-09-30 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_TicketDrilldown` | P | 2026-09-15 | — (not in the exe: portal, or unused) |  |
| `sp_rpt_TrialBalance` | P | 2026-06-22 | — (not in the exe: portal, or unused) | reads GLSummary (stale since 08-31) |
| `sp_rpt_TrialBalanceRealTime` | P | 2026-09-30 | HOFormsDevEx/AccountingReportsFormV2.cs |  |
| `sp_rpt_TrialBalanceWithDate` | P | 2026-08-24 | HOFormsDevEx/AccountingReportsForm.cs,HOFormsDevEx/AccountingReportsFormV2.cs,Reporting/AccountingReportsForm.cs | reads GLSummary (stale since 08-31) |
| `sp_rpt_TrialBalanceWithDate_07132026` | P | 2026-07-13 | — (not in the exe: portal, or unused) |  |
| `spr_Aging` | P | 2018-03-02 | — (not in the exe: portal, or unused) |  |
| `spr_ARSalesSummary` | P | 2019-03-01 | Reporting/BIR/BIR2550M.cs |  |
| `spr_CashSales` | P | 2016-08-09 | POS/PreviewReceipt.cs |  |
| `spr_CashSalesReport` | P | 2016-08-09 | Reporting/CashSalesReport.cs |  |
| `spr_comparativeNetReport` | P | 2023-08-24 | Reporting/BIR/ComparativeReport.cs |  |
| `spr_comparativeNetReport2` | P | 2023-08-24 | Reporting/BIR/ComparativeReport2.cs |  |
| `spr_DeliveryDetailsSummary` | P | 2026-03-04 | — (not in the exe: portal, or unused) |  |
| `spr_DepreciationReports` | P | 2017-07-16 | Reporting/DepreciationReports.cs |  |
| `spr_ESalesDetails` | P | 2020-02-10 | Reporting/BIR/BIR2550M.cs,Reporting/BIR/BIR2550M2.cs,Reporting/BIR/POSSalesReportSummary.cs |  |
| `spr_ESalesDetails2` | P | 2023-09-09 | — (not in the exe: portal, or unused) |  |
| `spr_EWTReconciliation` | P | 2019-05-03 | Reporting/BIR/EWTReports.cs |  |
| `spr_InventoryUnitActivity` | P | 2026-09-29 | HOFormsDevEx/DeductInventoryDevEx.cs,Reporting/InventoryUnitActivity.cs,Reporting/InventoryUnitActivityReport.cs |  |
| `spr_POSCloseTransaction` | P | 2019-05-03 | Main.cs,POS/POSMainRestoDashboard.cs,POS/POSTransactionChecker.cs |  |
| `spr_POSReports` | P | 2025-09-17 | POSDevEx/POSManagementReport.cs,POSDevEx/POSXReadReportDevEx.cs |  |
| `spr_POSReports2` | P | 2025-09-17 | POSDevEx/POSManagementReport.cs |  |
| `spr_POSReports2_09132025` | P | 2025-09-13 | — (not in the exe: portal, or unused) |  |
| `spr_POSSalesReportSummary` | P | 2020-02-10 | Reporting/BIR/POSSalesReportSummary.cs |  |
| `spr_POSSalesReportSummary2` | P | 2023-09-09 | Reporting/BIR/POSSalesReportSummary.cs |  |
| `spr_POSZReading` | P | 2019-05-03 | POS/POSEndOfDay.cs,POS/POSTransactionChecker.cs |  |
| `spr_PurchaseOrder` | P | 2016-08-09 | Reporting/POPreview.cs |  |
| `spr_ReprintCheckVoucher` | P | 2019-07-09 | AccountingDevEx/ViewCheckVoucherDetailsDevEx.cs |  |
| `spr_SalesDetailsComparativeAB` | P | 2023-09-22 | Reporting/BIR/SalesDetailsComparative.cs |  |
| `spr_SalesReportSummary` | P | 2019-05-03 | Reporting/BIR/BIR2550M.cs |  |
| `spr_SalesReportSummary2` | P | 2023-08-24 | Reporting/BIR/BIR2550M2.cs |  |
| `spr_SalesSummary` | P | 2017-08-07 | — (not in the exe: portal, or unused) |  |
| `spr_SalesTicketing` | P | 2019-08-15 | HOForms/DataAnalysisAndTicketing.cs |  |
| `spr_SalesTicketingBak` | P | 2017-03-22 | — (not in the exe: portal, or unused) |  |
| `spr_SalesTicketingNewEulz` | P | 2017-08-31 | — (not in the exe: portal, or unused) |  |
| `spr_STS` | P | 2026-04-13 | Reporting/STSSummaryReport.cs |  |
| `spr_STSSummary` | P | 2026-08-11 | Orders/POForApprovalSTS.cs,Orders/ViewBranchOrderSTS.cs,Reporting/DeliveryReportsFrm.cs |  |
| `spr_STSSummary02182026` | P | 2026-02-18 | — (not in the exe: portal, or unused) |  |
| `spr_Ticketing` | P | 2016-12-14 | — (not in the exe: portal, or unused) |  |
| `spr_VATInput` | P | 2019-09-16 | Reporting/BIR/VATInput.cs |  |
| `spr_XreadRep2` | P | 2018-01-09 | POS/POSXreadReport.cs |  |
| `spr_XreadRep2_01092018` | P | 2018-01-09 | — (not in the exe: portal, or unused) |  |
| `spr_XreadRep2ORIG` | P | 2017-08-11 | — (not in the exe: portal, or unused) |  |
| `spr_XreadRepEulz` | P | 2019-05-03 | — (not in the exe: portal, or unused) |  |
| `spr_XreadRepEulzORIG` | P | 2017-08-08 | — (not in the exe: portal, or unused) |  |
| `vw_rpt_AccountBSClassification` | V | 2026-09-25 | — (not in the exe: portal, or unused) |  |
