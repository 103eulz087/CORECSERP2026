# Claude Work Log (session handoff)

Imported into every Claude Code session via `CLAUDE.md`, so a fresh terminal on any
machine picks up where the last one stopped. **Keep it short and current:** update
the Status / Open items when something changes; move finished items to "Done" in one
line. Durable rules belong in `CLAUDE.md` itself, not here.

Last updated: **2026-10-01** (Feature 17 plan added)

---

## Deployment status

**DEV = `COREX001`** (new DEV, live replica of STAGING; what the registry points to).
STAGING = `CORECSJFC2026_STAGING`. The old DEV, `CORECSERP_002_DEV`, is no longer a target. See CLAUDE.md.
Per CLAUDE.md, STAGING changes need the user's confirmation first.

Status checked 2026-09-25 by probing each script's actual feature in each database:

| # | Script (`SQL/`) | COREX001 (DEV) | STAGING |
|---|---|---|---|
| 1 | `2026-09-24_SupplierPayment_OverpaymentCredit.sql` | ✅ | ✅ (applied outside this log) |
| 2 | `2026-09-24c_SupplierPayment_OverpaymentCredit_ExpenseSingle.sql` | ✅ | ✅ |
| 3 | `2026-09-25_SupplierPayment_OverpaymentCredit_ExpenseMultiBranch.sql` | ✅ | ✅ |
| 4 | `2026-09-25b_CancelledChequesCS_ExpenseMasterNullBalance.sql` | ✅ | ✅ |
| 5 | `2026-09-24_ExpenseInventoryCosting_InventoryLegsOnly.sql` | ✅ | ✅ |
| 6 | `2026-09-24b_ItemCostingRecon_MasterDetail.sql` | ✅ | ✅ |
| 7 | `2026-09-25c_CashReceipts_SalesJournal_BranchFilter.sql` | ✅ (incl. EWT) | ✅ |
| 8 | `2026-09-25d_ExpenseManualMultiBranch_PreserveLineOrder.sql` | ✅ | ✅ found applied 2026-09-26 00:54 (same as DEV) — STAGING users need the new exe |
| 9 | `2026-09-25e_ManualJV_PreserveLineOrder.sql` | ✅ | ✅ found applied 2026-09-26 00:53 (same as DEV) — STAGING users need the new exe |
| 10 | `2026-09-25f_IncomeStatementPivot_HeadOfficeFirst.sql` | ✅ | ✅ found applied 2026-09-26 00:54 (same as DEV) |
| 11 | `2026-09-26_ItemCostingRecon_ExpenseTickets.sql` | ✅ (by user, 14:24) | ✅ (by user, 14:56) |
| 12 | `2026-09-29_EditSingleExpense_NoDoubleCosting.sql` | ✅ already applied 2026-09-29 14:50 (outside this log); matches the script, backup = original; smoke-tested 2026-09-30 | ✅ found applied 2026-09-29 22:30 (same as DEV) |
| 13 | `2026-09-29b_InvFIFO_Engine.sql` | ✅ 2026-09-30 13:33 (smoke-tested, rolled back) | ⏳ |
| 14 | `2026-09-29c_STS_V2_FIFOEngine.sql` (needs 13) | ✅ 2026-09-30 13:33 | ⏳ ship with the new exe |
| 15 | `2026-09-30_GL_RealTime_Reports.sql` | ✅ 2026-09-30 23:08 (smoke-tested) | ✅ found applied 2026-09-30 23:34 (same as DEV) |
| 16 | `2026-09-30_GL_PeriodLock.sql` | ✅ 2026-09-30 23:08; nothing closed yet; two-session race test passed | ✅ found applied 2026-09-30 23:34 (same as DEV); no month closed yet |
| 17 | `2026-09-30b_SupplierLedger_Rebuild.sql` | ✅ 2026-09-30 23:24 (829 rows / 33 accounts fixed; audit now 0/0/0) | ✅ 2026-09-30 23:26, user-approved (801 rows / 38 accounts fixed; rehearsed rolled back first; audit now 0/0/0) |
| 18 | `2026-09-30c_ClientLedger_RecalcTrigger.sql` | ✅ 2026-09-30 (3 rows / 2 accounts fixed; audit now 0/0/0) | ✅ 2026-09-30, user-approved (6 rows / 2 accounts fixed; rehearsed rolled back first; audit now 0/0/0) |
| 19 | `2026-10-01_SalesOrder_Lifecycle_Fixes.sql` | ✅ 2026-10-01 13:22 (one transaction; 10 lifecycle scenarios re-tested on the live procs) | ✅ 2026-10-01 21:52, run by the user; verified same as DEV |
| 20 | `2026-10-01b_STS_Lifecycle_Fixes.sql` (needs 19) | ✅ 2026-10-01 (one transaction; 9 STS scenarios re-tested on the live procs) | ✅ 2026-10-01 21:52, run by the user; verified same as DEV |
| 21 | `2026-10-01c_STS_InTransit_Correction.sql` (data fix; needs 20) | ✅ 2026-10-01: corrected 11699, 11700, 11702; skipped 11701 (stock never restored, DEV copy only); residuals now empty | — not needed: checked 2026-10-01 after 19/20/23, nothing to correct. The duplicate tickets 18547 / 18554 had been deleted by hand (master + details); each PO's IT-HO-VATEX equals its live FIFO cost |
| 23 | `2026-10-01e_GL_AllVatExempt.sql` (needs 19 + 20; run before 21) | ✅ 2026-10-01 21:22 (sales A/C/D/E/G + STS S1/S2/S3/S5/S8 re-tested rolled back: no VAT legs, all tie); script 21 (updated) re-run: VAT reclass on 11699/11700/11702 reversed (tickets 15881–15886) | ✅ 2026-10-01 21:53, run by the user; verified same as DEV (all 5 procs carry the patch note) |
| 22 | `2026-10-01d_SalesCost_SeptemberFinalCost.sql` (data fix for STAGING) | — | ✅ 2026-10-01, user-approved (rehearsed rolled back first): 20 FIFO rows, 16 SI-VATEX tickets, COGS −3,375.36; backups `CostFix_20261001_*` |
| 24 | `2026-10-01f_STS_V2_Alignment.sql` (needs 13 + 14 + 20 + 23; patches 4 procs) | ✅ 2026-10-02 09:5x (rehearsed rolled back first). Test script fixed (PRINT with a subquery doesn't compile, 1046; NULL barcode on AUTO lines) and run on request 13435 as anthony: 18/18 PASS, nothing left behind. Old-form STS scenarios S1/S2/S3/S5/S8/S9 re-run on the live procs: all tie. Exception Center: only the known 11701 |
| 25 | `2026-10-02_STS_ReceiveFIFO_OneRowPerLine.sql` | ✅ 2026-10-02 11:12 (bug reproduced, then fixed; S1/S8/S10/S11 rolled back, all tie) | ⏳ needs the user's go; no exe change |
| 33 | `2026-10-02i_CheckVoucher_CVNo.sql` (needs 31; `CheckVoucher.CVNo` backfilled from NotedBy; `sp_Payment_CreateVoucherHeader` / `sp_PostCashAdvance` / `sp_AddPaymentSupplierCompound` write it; `sp_BankRecon_GetPeriod` recreated: OC CV # from CVNo, reversed items (REVERSED / VOIDED%) not listed; removes 32) | ✅ 2026-10-02 (65 vouchers) | ✅ 2026-10-02, user-approved (rehearsed rolled back first: 176 vouchers; new voucher gets CVNo; 84 reversed rows hidden). Works with the current exe; new exe 2026-10-03 |
| 32 | `2026-10-02h_VoucherCVNo.sql` — **superseded by 33, never on STAGING; removed from DEV by 33** | (removed) | — do not run |
| 31 | `2026-10-02g_BankRecon_OC_CVNo.sql` (needs 30; OC rows add CV #: cheque = CheckVoucher.NotedBy, telegraphic / cash = ControlNo) | ✅ 2026-10-02 | ✅ 2026-10-02, user-approved (rehearsed rolled back first). No exe needed |
| 30 | `2026-10-02f_BankRecon_OC_ControlNo.sql` (needs 29; OC grid: ControlNo / CheckNo / voucher no. / source from the issuing voucher; patches the OC block only) | ✅ 2026-10-02 | ✅ 2026-10-02, user-approved (rehearsed rolled back first: AP 140 / 143 with control no.; 174 with cheque no.). No exe needed |
| 29 | `2026-10-02e_BankRecon_ControlNo.sql` (Bank Recon control no.; `@ItemType` optional = 'DIT' so any exe works) | ✅ 2026-10-02 (2,663 rows filled) | ✅ 2026-10-02, user-approved (4,980 rows filled; rehearsed rolled back incl. old- and new-exe Bulk Resolve calls). No exe needed; new exe only adds captions |
| 28 | `2026-10-02d_SalesViews_OneRowPerLine.sql` (fixes the user's 10-02 edits of `funcview_ForDeliveryDetails` / `funcview_ProcessOrderItemsSales`: keeps their one-row-per-line fix; puts `BarcodeNo` back — old sales and STS forms print / cancel / return by it; shows returned lines again; OUTER APPLY for the lot ReferenceCode) | ✅ 2026-10-02 15:20 | ✅ 2026-10-02 15:20, user-approved (rehearsed rolled back: 342 → 351 rows = +9 returned lines, all of the user's rows identical, no duplicates) |
| 27 | `2026-10-02c_SalesOrder_V2_FIFOEngine.sql` (needs 13 + 19 + 23) | ✅ 2026-10-02 (rehearsed rolled back; old-form A–H + V2 harness pass) | ⏳ after STS V2 is on STAGING, with the new exe |
| 26 | `2026-10-02b_STS_ReceiveFIFO_PerLot.sql` (needs 25) | ✅ 2026-10-02 13:06 (S1/S5/S6/S8/S10/S11 rolled back, all tie) | ⏳ with 25 | ⏳ after 13 + 14, with the new exe |

- 2026-09-26: the live `sp_rpt_ItemCostingRecon_List` on both DBs was changed by the user (14:13 DEV / 14:18 STAGING): `BranchCode` → `BranchName` via `INNER JOIN dbo.Branches`. The repo copy in script 6 (`2026-09-24b`) still has `BranchCode`.
- Web reporting handoff for the recon: `docs/handoff/2026-09-26_ItemCostingRecon_WebReporting_Handoff.md`.

- Earlier testing and deploys this session went to `CORECSERP_002_DEV`, the old DEV.
- COREX001 already had all 10 scripts when checked, and STAGING had 1–7; it's unclear who or what applied them.
- Each script renames the live object to `<name>_OLD_<timestamp>` before recreating it. Every file's suffix is unique.
- Re-running a script on a database that already has that backup name fails at the rename, so check first.

C# changes (uncommitted as of this entry) — build succeeded:
- `AccountingDevEx/SupplierPaymentDevEx.cs` + `.Designer.cs`
- `Reporting/ItemCostingReconReport.cs` + `.Designer.cs`

---

## Feature 1 — Supplier Payment: OverPay / Advance credit (AP)

**Problem:** the client's Peachtree habit is to overpay an invoice (Balance 1,000, pay 1,200),
leave it at -200, and net it off the next invoice. We post GL per invoice, so a negative
balance is wrong. Modeled on the AR version (`ClientPaymentsDevExAcctg.cs`, account 20115).

**Design:**
- Grid columns in `AccountingDevEx/SupplierPaymentDevEx.cs`, added client-side in `populate()`,
  **not** in `splist_Accounts`, because that proc also feeds `VoucheringManualFrm` and `HOFormsDevEx/SupplierPaymentDevEx`:
  - **OverPay (Credit)**: DR `101030208` Advances to Suppliers. Carried forward as credit.
  - **OverPay (Expense)**: DR `60339` Misc Expense. Written off, not carried forward.
  - **Advance Applied**: CR `101030208`. Consumes earlier credit instead of cash.
- **Adv. Credit** label = `sp_GetSupplierAvailableCredit` = SUM(OVERPAY) − SUM(ADVANCEAPPLIED) from
  `APPaymentDetails`, excluding vouchers found in `PaymentReversalAudit`. **Shared across PURCHASE and EXPENSE.**
- Extras reach the SP through the optional TVP `dbo.AP_PaymentLineExtraTVP`
  (`@InvoiceLineExtras` → `@LineExtras`). An omitted TVP arrives as empty (tested), so `CombinedSupplierVoucherFrm` is unaffected.
- **Rules (SP plus client mirror):**
  - 60511: amounts can't be negative.
  - 60512: only one of the three per invoice.
  - 60513: OverPay on only one invoice per voucher.
  - 60514: Advance can't exceed credit; re-derived under `sp_getapplock 'APCREDIT:'+SupplierID`.
  - 60515: OverPay only when the invoice is fully settled.
  - 60518: the ticket must balance, DR = CR.
  - 60519 (reversal): a voucher whose credit has already been used can't be reversed first.
- **By mode:**
  - **PURCHASE:** new mnemonics `PV-AP-OVERPAY / -OVERPAYEXP / -ADVAPPLIED`, each with explicit amount types, never `MIRROR`.
  - **EXPENSE SINGLE:** extra legs via `sp_Payment_PostSettlementTicket`, which gained 6 optional params that default to 0.
  - **Multi-branch expense:** real data is tagged `PostingMode='MULTI-MANUAL'`, **not** 'BATCH'. User chose: book the extras on the
    **head-office 888 ticket** only.
    - No 888 share + OverPay: a separate `EXP-OVERPAY-HO` ticket, DR advances / CR bank.
    - No 888 share + Advance: rejected (60522).
    - Advance larger than 888's share: rejected (60522).
- Overpayments are **not** written to `SupplierLedger` in any mode. It records only the payable amount settled. This is deliberate.
- User guide for staff was written in chat (2026-09-24). It explains the three columns, the day-1 / day-2 example, the rules and the reversal order.

**Status:** done on DEV and fully tested (rolled-back transactions) for all modes, reversals and negative cases. The reviewer agents passed it.
**Next:** UI test by the user, then STAGING.

## Feature 2 — Item Costing: inventory legs only + master-detail report

- **Bug:** PO-linked expense costing used the **whole invoice amount**. Example: ExpenseSummary 30437 on STAGING has 151,359.27 total but only a
  118,199.35 inventory leg on ticket 14287.
  - **Fixed in `spu_PostExpenseV2`, forward-only:** the cost increment is now the net Debit − Credit on the `10104` inventory subtree, via config row
    `JournalEntryMapping` mnemonic `EXP-INVCOST-ROOT` and `dbo.fn_InventoryCostAccounts()`.
  - Historical `Inventory.Cost` is **not** corrected.
- `spu_PostExpenseV2` CATCH now uses `THROW;`. RAISERROR had been turning every error into 50000.
- `Reporting/ItemCostingReconReport` rewritten as a master-detail view: all shipments, expand a row to see its linked expenses.
  - New SP `sp_rpt_ItemCostingRecon_List` returns 2 result sets. It's set-based and ticket aggregation is scoped to the expenses in scope.
  - The old `_Header/_Detail` procs are kept but no longer called.
- ReconStatus values: MATCHED / VARIANCE / LOTS DIVERGE / NO INVENTORY / NO EXPENSES.

- 2026-09-26: right-click or double-click a Linked Expense row → "View Related Tickets" popup (posting ticket, payment-voucher tickets, reversals, each with GL lines).
  New read-only SP `sp_rpt_ItemCostingRecon_ExpenseTickets` (script 11). Payments link via `APPaymentDetails.BatchReferenceID` → voucher (`ReferenceNumber`+`VoucherID`) → `TicketMaster`.

**Status:** done on DEV. **Next:** UI check, including whether Export includes the expense rows, then STAGING.

## Feature 3 — Reversal NULL balance (`sp_CancelledChequesCS`)

EXPENSE reversal wrote `ExpenseMaster.Balance = NULL` whenever a line's EWT/Discount/Offset was NULL.
The fix adds ISNULL guards, computes values once in a CROSS APPLY, and sets Status to UNPAID / PARTIAL / FULLYPAID.
Tested full / partial / two-step on multi-branch and SINGLE invoices. **Status:** done on DEV.

## Feature 4 — POS Sales Report: Cash Receipts / Sales Journal (script 7)

- Branch filter on both tabs: a global admin picks a branch or all branches; everyone else is locked to `Login.assignedBranch`.
- Cash Receipts `InvoicePaymentAmount` = INVOICE PAYMENT + OVERPAY − OFFSET − EWT. INVOICE PAYMENT is stored gross.
- C#: `POS/POSSalesReportDevEx.cs` + `.Designer.cs`. Built.
- **Open:** should DISCOUNT be deducted too? Asked the user.
- On DEV with the EWT change. **Next:** UI check, then STAGING.

## Feature 5 — Expense Manual Multi-Branch: keep GL line order (script 8)

- **Bug:** the Details SP sorted by `BranchCode, LineID`, so Edit/View/Copy showed lines regrouped by branch, and saving an edit locked that order in.
- **Fix:**
  - New column `ExpenseManualLines.LineNo` and TVP `ExpenseManualLineTVP_V2`. The old type is kept for the `_OLD_` backup procs.
  - Post/Edit insert `ORDER BY LineNo`. Details sorts by `LineNo, LineID`.
  - Rows posted before the fix have LineNo NULL and fall back to LineID order.
- C#: `ExpenseManualMultiBranchFrm.BuildLinesTVP()` sends LineNo. **The exe and the SQL must deploy together**: an old exe calling the new procs fails on the TVP type.
- Tested on DEV (post, then edit in a different order, rolled back, 0 leftover rows).
- **Same fix for Manual JV (script 9):** `HOFormsDevEx/ManualJournalVoucherFrm.cs` and `ManualJournalVoucherMultiBranchFrm.cs`.
  - New column `ManualJournalVoucherDetails.LineNo`, new types `JournalVoucherLineTVP_V2` and `JournalVoucherLineMultiTVP_V2`.
  - The details SP previously sorted by BranchCode, AccountCode.
  - Tested single post, multi post and edit on DEV (rolled back).
- **Single Expense (`AccountingDevEx/AddExpenseDevExFrm`) skipped (user's call).**
  - Its lines come from `TicketDetails`, which has no order column.
  - Adding a column there would break 43 SPs and 3 old forms that insert without a column list.
  - `spu_PostExpenseV2` is shared with 3 other forms, so its TVP can't change.
  - If revisited: a side table plus an optional V2 TVP on `spu_PostExpenseV2`.

## Feature 6 — AccountingReportsFormV2 (`HOFormsDevEx/`)

- The date fields had no calendar button; the Combo button was missing in `.Designer.cs`. Fixed.
- **Income Statement pivot (script 10):** HEAD OFFICE CEBU ('888') is now the first branch column.
  - Verified the output matches the old proc (67 rows, 0 differing cells).
- **Pivot view:**
  - AccountCode and AccountDescription are pinned left in the grid.
  - Excel export for pivot results uses a data-aware XLSX (`ExportPivotToXlsx`), so the header row and those two columns are frozen. Verified the pane in an exported file.
  - PDF and every non-pivot export still use the old print-layout path.
  - The pivot export has no title rows (user's choice): DevExpress won't freeze the header row with rows above it.

## Feature 7 — Posted tabs: draggable splitter (C# only)

- **Forms:** ManualJournalVoucherMultiBranchFrm, ManualJournalVoucherFrm, AddExpenseDevExFrm (AccountingDevEx), ExpenseManualMultiBranchFrm, VoucheringManualFrm.
- **Change:** each form's Posted tab now puts the posted grid on top and buttons + details below, in a `SplitContainerControl` named `splitPosted`.
  - VoucheringManualFrm builds it in code, in `BuildPostedTab()`.
- **Why a helper:** `DevXGridViewSettings.KeepSplitterRatio()` holds the split ratio on resize and remembers a user's drag.
  - Plain `FixedPanel.None` lost the ratio when the control was first laid out tiny: the details panel got squeezed to 0.
- Verified in a harness at 900 px and 560 px window heights, and a simulated drag + resize.
- The ratio is not persisted between sessions.

---

## Feature 8 — Inventory FIFO deduction standard + STS V2 (2026-09-29)

- Analysis + standard: `docs/standards/2026-09-29_Inventory_FIFO_Deduction_Standard.md`.
- User answers: BranchInventoryIN proc lives in another DB (user will create it); **eligible lot = `Available > 0 AND IsWarehouse = 1`** (ENZO keeps 3rd-party-storage HO stock at IsWarehouse=0); non-JFC STS still used elsewhere; partial qty on scan allowed; IsStock not a filter.
- Built (scripts 13/14, not deployed): engine (`spu_InvFIFO_Deduct` / `_Restore` / `sp_InvFIFO_Preview`, LOT/BATCH/AUTO modes) + STS V2 (`spu_PostSTSLineV2`, `spu_ReverseSTSLineV2`).
  - Form `Orders/AddBranchOrderSTSV2` = copy of `AddBranchOrderSTS`; opened from ViewBranchOrderSTS > Process this Order > **FIFO V2 (Test)**, admins only. Old form/procs untouched.
  - Per-scan posting kept; same STS tables (so the unchanged `sp_ConfirmBranchOrderSTS` works — verified on DEV).
- **Testing gotcha:** a table TYPE created inside a transaction can't be used in that transaction (SQL Server deadlocks itself). The 2 types were created committed on COREX001 for testing.
- Found, not fixed: `sp_CancelDeliveryFIFOJFC` restores only ONE lot per line; `sp_CancelDeliveryByBarcode` resets a lot to full `Quantity`. Deliveries 13652/PO 11700 and 13642/PO 11701 (24–25 Sep): 20 cancelled FIFO rows never marked corrected, 19 with no restore ledger row (up to 35,733.47 qty) — needs checking. `funcview_populateProductsInPOJFC` AND/OR precedence bug.
- Reviews (2026-09-30): sp-reviewer + ui-form-reviewer, no blockers. Fixed and retested:
  - SQL: IsWarehouse re-checked under lock; per-product applocks in ProductCode order (`sp_InvFIFO_LockProducts`, 59810) against deadlocks; reverse guard 59833.
  - Form: stale sticker barcode cleared on product/type change; failed full-lot scan keeps the barcode; Save-as-Draft `Close()` instead of `Dispose()`; Load falls back to LoadData.
- Open (user to decide): prune dead handlers copied into the V2 form; pre-existing `displayweight()` FormatException/NullReference; `sp_PostCompoundTicket` re-throws every error as `50050 'ERROR SP'` (real message lost); no idempotency key on a retried scan (by design: one scan = one event).
- Next: user UI test on DEV (after deploying 13+14), then Stock Out / Conversion onto the engine.

## Feature 10 — Retire daily GL posting: real-time reports + month-end lock (2026-09-30)

- **Why:** `GLSummary`, built by `GLPostingDevEx` → `sp_GLPosting` → `GLPosting`, was stale for the months it covers.
  - Jul–Aug vs `TicketDetails`: DEV 459 branch/accounts, 353M; STAGING 513 branch/accounts, 585M. Cause: back-dated / edited / reversed tickets entered after posting.
  - The "Live" hybrid reports inherit the gap (they read `GLSummary` up to the cutoff): 888 AR-Trade as of 08-31 shows 178.69M, the tickets say 156.19M.
  - `TicketDetails` is small (about 40k lines): a full live aggregation takes 47–94 ms.
- **User decisions:**
  - Nothing external uses `GLSummary`.
  - Lock is company-wide; an admin can reopen the last closed month, with a reason, logged.
  - The lock covers GL tickets only.
  - `GLPosting`'s BOSNET netting and auto-reject of unapproved tickets are not needed.
  - Add live versions next to the old reports.
- **Built:**
  - Script 15: 8 `sp_rpt_*RealTime*` procs = their sources with only the `GLSummary` block replaced.
  - Script 16: `GLPeriodLock` + log, close/reopen procs, triggers on `TicketDetails` / `TicketMaster` (59900).
  - C#: 7 "(Real-Time)" entries in `AccountingReportsFormV2` (the Income Statement one also has a real-time pivot).
  - New admin form `AccountingDevEx/GLPeriodClosingFrm`, added in code to Accounting Settings.
  - `btnGLPosting` hidden. Old forms and procs kept.
- **Tested on DEV (rolled back):** 16 report tie-outs and 17 lock scenarios, including the real `sp_EditSingleExpense` being refused after its month is closed.
- **Reviews:**
  - ui-form-reviewer: no bugs.
  - sp-reviewer, fixed + retested:
    - GL Detail Transaction `BETWEEN` on DATETIME: 27 DEV / 3 STAGING lines carry a time of day. The old report misses 19.08M on 2026-09-29.
    - GL Detail Ledger day labels now use a LEFT join.
    - Lock triggers read the lock row `WITH (HOLDLOCK)`, closing the close-vs-posting race.
    - `SupplementaryNumber` added to the guarded columns.
  - Its `STRING_AGG`-at-compat-120 blocker was false: **STAGING now reports compat 160**.
  - Not fixed (existing procs): an unguarded or named rollback can mask 59900 with a "no BEGIN TRANSACTION" error — `sp_AddPaymentSupplierCompound*` (named), `sp_AddPaymentClient`, `SP_CONFIRMPO`, `sp_ReversePaymentClient`, `SP_UPLOADINVENTORY`. Nothing gets posted, but the message is confusing.
  - The two-session close-vs-posting race couldn't be tested before deploying.
- **Found, not fixed:**
  - The existing "Bank Reconciliation" entry fails: the form sends `@AsOfDate`, the proc wants `@DateFrom`/`@DateTo`.
  - Opening-balance ticket 1 has a blank `TicketMaster.BranchCode`; some CONV-FINALIZE lines sit under a different branch than their master. 858 lines are dropped by any 4-part master join.
  - The old bank recon's POSTED/UPDATED filter drops reversal tickets (Status 'REVERSED' is on the reversal itself).
  - Delete-and-repost edit procs are refused for closed months (intended).
  - Year-end closing entries: not designed yet.

## Feature 11 — SupplierLedger / SupplierAccounts audit (2026-09-30, read-only, nothing changed)

- **Rule** (trigger `InsertSupplierLedger`, INSERT only): Ending = Beginning + Credit − Debit, chained per `SupplierKey` in `TRN_SEQ_NO` order. `SupplierAccounts.AccountBalance` = the last row's Ending.
- **STAGING:** 1,416 rows / 87 suppliers.
  - 403 rows with bad math; 69 chain breaks; 82 suppliers affected.
  - 36 accounts wrong vs SUM(Credit − Debit): total 829.47M vs correct 856.13M.
- **DEV:** 824 bad rows, 77 of 80 suppliers, 33 accounts wrong.
- **Causes found:**
  1. Historical cross-supplier overwrite: rows with the same `TRN_SEQ_NO` carry the SAME Ending across suppliers. DEV: every seq, 969 rows. STAGING: 414 rows, mostly seq 1–8, e.g. 9,775.00 on 78 suppliers.
     - The current trigger (2026-07-13) was tested on DEV (rolled back) and is correct: other suppliers untouched.
     - So this came from an older version or an outside script, then propagated down each chain.
  2. The trigger ignores DELETE/UPDATE. Edit procs delete ledger rows (`sp_EditSingleExpense`, `sp_EditApprovedExpense`, `sp_EditExpenseManualMultiBranch`): later rows and the account are never recomputed. Gaps: BUREAU OF CUSTOMS seqs 1, 24, 27, 34, 47.
  3. 11 accounts stuck at 0.00 (e.g. SURE GOOD FOODS 18.78M, CANADA PACKERS 12.55M): their `SupplierAccounts` row was created (7 / 10 Sep, by `sp_TrgInsertSupplierInfo` at 0) after the ledger rows, so the ledger trigger had nothing to update.
- **Also found:**
  - `sp_ReverseApprovedExpense` sets `ErrorCorrectTag = 1 WHERE TRN_SEQ_NO IN (...)` without `SupplierKey`, which tags other suppliers' rows.
  - `func_getLastID` takes the max seq per SupplierID under `NOLOCK` (race; no duplicates today).
- **Fixed (script 17, applied on DEV 2026-09-30):**
  - Backups `SupplierLedger_Backup_20260930` / `SupplierAccounts_Backup_20260930`.
  - Rebuild from Debit/Credit in `TRN_SEQ_NO` order (amounts untouched).
  - New trigger `trg_SupplierLedger_Recalc` (INSERT/UPDATE/DELETE, recomputes affected suppliers' full chains + accounts). The old `InsertSupplierLedger` is renamed `_OLD_09302026180000` and DISABLED.
  - `sp_ReverseApprovedExpense` tags by supplier + seq.
- **Tested first in a rolled-back tx:** audit 824/37/33 → 0/0/0; insert, delete-middle, credit change, 2-supplier insert and hand-edit heal all tie; the real reversal tags only its supplier.
- **STAGING:** applied 2026-09-30 23:26 after a rolled-back rehearsal there (403/75/36 → 0/0/0). Backups `SupplierLedger_Backup_20260930` (1,416 rows) / `SupplierAccounts_Backup_20260930` (145 rows) exist on both DBs.
- **Still open:** optional tie-out of ledger balances to open payables (`ExpenseSummary` + `APAccounts`).

## Feature 12 — ClientLedger / ClientAccounts fix (script 18, 2026-09-30, on DEV + STAGING)

- **Audit (before):** the client ledger was sound (0 bad math, 0 cross-account overwrites, AR ties at 231,213,012.65 on STAGING). The only problems were 2 chain breaks, both JELO'S PLACE (00007479 branch 011 / 00009065 branch 006):
  - BF T_036537 (136,338.20) had been moved to 00009065 by editing `AccountKey`. `AccountID` still said 00007479 and nothing was recomputed, because the old trigger was INSERT-only.
  - BF T_036293 (307,929.20) was still on 00007479, though `TransactionChargeSales` and its payment are on 00009065.
- **Script 18:**
  - Backups `ClientLedger_Backup_20260930` / `ClientAccounts_Backup_20260930`.
  - Moves the T_036293 BF row to 00009065 (seq 4) and fixes `AccountID` on both moved rows.
  - Full chain recompute; only rows that differ are written.
  - `InsertClientLedger` → `InsertClientLedger_OLD_09302026190000` (DISABLED); new `trg_ClientLedger_Recalc` (INSERT/UPDATE/DELETE). It recomputes every touched account, both sides of a move included, and sets `AccountBalance` only (not `CashWalletBalance`).
- **Result:** each JELO'S PLACE account equals its open TCS invoices: STAGING 455,284.60 / 207,768.40; DEV 648,762.20 / 207,768.40 (R-005362 is unpaid on DEV). Trigger tests passed on both DBs: insert, middle delete, amount change, move between accounts, hand-edit heals, emptied account → 0, other accounts untouched.
- **Cosmetic:** on 00009065 the T_036293 OR-EWT (seq 2) now comes before its BF row (seq 4), so the running balance dips negative mid-statement. The final balance is right. Renumbering would shift other rows; left as is.
- Like the old trigger, the new one doesn't create a missing `ClientAccounts` row (0 are missing today).

## Feature 9 — AR: negative balance-forward invoices as credits (DISCUSSION, on hold 2026-09-30)

**On hold:** the user is checking the classification and the EWT entry with the accountant. Nothing built or changed.

- **Ask:** show the negative balance-forward rows of `TransactionChargeSales` in `AccountingDevEx/ClientPaymentsDevExAcctg.cs`, and use them against open invoices, as in Peachtree (tick −300 row + 300 row → both 0). `splist_ARAccounts` lists `Balance > 0` only.
- **Data (COREX001):**
  - 208 negative rows, 147 customers, −2,089,800.34. 106 of those customers also have open invoices.
  - 205 were loaded with `AmountPaid = 0` and a directly-set negative `Balance`: customer-level credits parked on one invoice, e.g. C-000900 is a 295,319.20 invoice carrying −1,146,104.62.
- **Not all negatives are overpayments.** Some are EWT awaiting the 2307 certificate and must NOT be offsettable credit.
  - Data can't classify them reliably: 128 rows are EWT-sized (≤6% of their invoice, 124,570.17), but only 5 exactly match an EWT rate of their own invoice.
  - Needs a per-row list: OVERPAY / EWT-PENDING / OTHER. I offered an Excel export with an "EWT-sized" hint.
- **GL:** the opening ticket (mnemonic `*`, 2026-07-31, AR-Trade 101030101 = 165,433,465.56) has no 20115 leg, so the credits are probably inside AR (net, as in Peachtree). Accountant to confirm.
- **Options:**
  - **A (Peachtree style):** list negatives as CREDIT rows, tick them into a per-voucher credit pool, new payment type (e.g. `BFCREDIT`), post + reversal changes; no GL if the credits are inside AR.
  - **B (recommended):** one-time load of each negative as a typed opening credit, recorded as payment detail rows under one "Peachtree BF" header, and close the rows to 0.
    - `OVERPAY` rows then feed `sp_GetCustomerAvailableCredit` and the inline copy of that formula in `sp_AddPaymentClient` unchanged; `EWT-PENDING` rows are excluded automatically.
    - Reclass ticket DR 101030101 / CR 20115 for the OVERPAY part only. Staff use the existing Offset column.
    - First check that no report reads payment detail rows as cash collected.
- **⚠️ Urgent, separate, not fixed: 504 positive balance-forward rows (60.75M) were partly paid in Peachtree.** `Balance` was loaded directly while `AmountPaid = 0`.
  - `sp_AddPaymentClient` recomputes `Balance = TotalAmount − (AmountPaid + EWT + Discount + Offset)`, so the first payment leaves a wrong balance. Example: D_122462, total 3,450, balance 1,150 → paying 1,150 leaves 2,300.
  - None touched yet. Same trap for any negative row sent through today's post (C-000900 would become +295,319.20).
  - Fix choice: one-time `AmountPaid = TotalAmount − Balance` on inconsistent balance-forward rows, with a backup table first (recommended), OR incremental balance math in post + `sp_ReversePaymentClient`.
- **Questions for the user / accountant:**
  1. Is the opening AR net of these credits?
  2. The Peachtree entry that created the EWT negatives, and the entry when the 2307 arrives (DR Creditable Withholding Tax / CR ?).
  3. The classification list.
  4. Option A or B.
  5. The 504-row fix choice (can be done before the rest).
  6. Is 20115 (COA says "ADVANCES FROM ACCOUNT MANAGERS") the right customer-credit account?
- Unverified: 3 other negative rows (−10,190, FULLYPAID) whose columns are consistent, i.e. some screen let a payment exceed the invoice. Query blocked by a transient permission-check error.

## Feature 13 — Tooling: Dependency Atlas + Process Trace (2026-09-30 / 10-01)

- **Dependency Atlas** rebuilt with tables + table types and a builder script (see CLAUDE.md). Artifact https://claude.ai/artifact/ExWdEYaxmbU9VMZbLpumWa.
- **Process Trace**, the replacement for the user's Excel trace sheets (see CLAUDE.md). Artifact https://claude.ai/artifact/Bmoqk3GnfkQefi74rbnRkU.
  - AR Payment. Samples: 5155 (cheque + EWT, 3 invoices) and 5591 → reversed → 6163 (cash + overpay).
  - Sales Order (added 10-01, listed first). Samples: PO 9496 (VAT + VAT-exempt, 2 SI tickets) and PO 7375 (3 lines cancelled and re-scanned).
    - The user's name `AddSalesOrder.cs` doesn't exist; the form is `Orders/AddOrder.cs`.
    - Findings (on the page, not fixed):
      - `sp_CancelDeliveryFIFOJFC` restores one lot only.
      - Approval, reject and invoice-number updates are string-built SQL.
      - `sp_ConfirmOrder` overwrites `DateApproved`. With auto-approval, `ApprovedBy` is blank on every order.
      - Inventory ledger remarks say "STS" for sales orders.
      - Invoice uniqueness is checked only against DeliverySummary.
  - Supplier Payment (added 10-01, expense mode). Samples:
    - 686: single-branch cheque.
    - 688: multi-branch, 3 branch shares.
    - 735 → 736 → 737: overpay credit applied, reversed, applied again.
    - 628: cash voucher reversed.
    - Findings (on the page, not fixed):
      - `spu_PostExpenseV2` writes `SupplierLedger.TicketReference` from a second `GetTicketNumber` call. All 379 SNGLE ledger rows point to a ticket that doesn't exist.
      - `sp_PostSupplierPaymentWithManualLines` isn't atomic (V2 commits before the manual lines run).
      - The reversal's "already reversed" guard checks `CheckVoucher` only, and the `sp_ReverseCombinedSupplierVoucher` wrapper has no transaction.
      - Reversal tickets keep Status POSTED and the original Mnemonic.
      - SupplierKey vs SupplierID naming is mixed (equal for all 138 suppliers today).
    - PURCHASE mode not traced yet (only 3 vouchers on DEV).
  - Static bundle for colleagues: `CORECS_Tools_Static.zip` in the repo root (not committed). Rebuild it after republishing.
  - **Next module: user to pick** (Expense / STS / Conversion / …).
- `tools/ProcessTrace/` and `docs/process-trace/` were not committed yet as of this entry.
- Git: on 10-01 `main`'s uncommitted `ClientPaymentsDevExAcctg.Designer.cs` / `.resx` + build output were stashed (`stash@{0}`, "main WIP …") before switching back to `laptopdell`. They're still in the stash; nothing is applied.

## Feature 14 — Sales Order lifecycle fixes (script 19, 2026-10-01, on DEV)

- **Scope:** place → approve → process (scan) → cancel line → save → invoice no. → confirm → credit memo → return.
  - Forms: `Orders/AddOrder`, `Orders/POForApproval(Details)`, `Orders/AddBranchOrder`, `HOForms/ViewForDeliveryDetails`, `HOFormsDevEx/ConfirmOrderDevEx`, `HOFormsDevEx/CreditMemoDevEx`, `Orders/ReturnSalesOrder`.
  - No C# change: every procedure keeps its parameters.
- **User rules (10-01):**
  - Credit memo = shrinkage. The missing qty's cost goes to COS OTHERS (503 VAT-exempt / 504 VAT); no stock back.
  - A credit memo or return larger than the unpaid balance → the excess becomes customer credit (OVERPAY in the AR pool, GL 20115).
  - A return restores and credits ActualQty (the billed qty).
- **Bugs fixed (proven with rolled-back lifecycle tests on DEV):**
  - Cancel restored only the last lot of a scan that spanned lots.
  - Credit memo before confirm credited the client ledger and confirm billed the reduced qty too (counted twice).
  - Return ignored payments (reset the invoice to UNPAID).
  - A second return subtracted the running total of all returns again (invoice went negative).
  - Return after a credit memo credited the delivered qty, not the billed qty.
  - VAT-exempt returns never reversed COGS (CM-CLIENT-VATEX cost rows inactive). STAGING history: 135 lines, 2,125,661.70.
  - BatchSalesSummary was never updated by returns (CashierTransNo filter). STAGING: 59 POs.
  - Credit memo on a VAT item put cost back into GL inventory without stock.
  - Line cost after Save came from one arbitrary lot, not the weighted cost.
- **Script 19:**
  - New mnemonics SO-SHRINK / SO-CM / SO-RET (VAT and VATEX).
  - New shared proc `spu_SO_PostInvoiceReduction`.
  - Rewrote `sp_CancelDeliveryFIFOJFC`, `sp_CreditMemo` and `sp_ReturnSalesOrder`; patched `sp_ConfirmBranchOrder`.
  - Tickets are dated today, VAT is rounded per line like `sp_ConfirmOrder`, and every ticket is checked DR = CR.
- **Testing:**
  - The sp-reviewer's 3 should-fix items are in: DeliveryNo in the weighted cost, one credit row per ticket, per-line VAT.
  - Its XACT_ABORT "leak" claim was not taken: SET options revert when a procedure returns.
  - Harness: scratchpad `lc/test_so.ps1`. 10 scenarios (A, A2, B, B2, B3, C to H), rolled back, all tie: invoice = client ledger = GL AR, GL inventory = stock movement, tickets balance, credit pool correct.
  - Deployed to COREX001 in one transaction (scratchpad `deploy_tx.ps1`), then re-tested against the live procs.
- **Next:** user UI test on DEV → STAGING. Then STS (same cancel bug; STAGING POs 11700 / 11701 have 35,733.47 stuck).
- **Open (user to decide):**
  - Repair the STAGING history (VAT-exempt return COGS 2.1M; 59 sales headers; 11 returned invoices whose balance ≠ ledger).
  - There is no reversal for a posted credit memo / return.
  - Hide the dead legacy return menu (`viewBranchOrderDetails` → `ReturnCustomerOrder` → `sp_ReturnDeliveredOrder`: wrong parameter count, never used).
  - Conversion lots carry cost 0, so sales of converted items post 0 COGS.
  - 184 sales-order invoices with plain payments don't match the client ledger (STAGING); not yet investigated (AR side).

## Feature 15 — STS lifecycle fixes (scripts 20 + 21, 2026-10-01, tested on DEV, not deployed)

- **Flow:**
  - Request: `Orders/AddOrderSTS` → `sp_AddTransferOrderRequest`.
  - Approve: `Orders/STSForApprovalDetails` → `sp_ApproveTransferOrder`.
  - Process: `Orders/ViewBranchOrderSTS` → `Orders/AddBranchOrderSTS`.
    - Scan: `sp_AddBranchOrder_JFC` → `sp_SalesQtyToInventoryQtySTS_JFC`; barcode: `sp_AddBranchOrderByBarcode`.
    - Save: `sp_ConfirmBranchOrderSTS` posts IT-HO-*.
    - Return: `sp_ReverseSTSInventoryTransfer`.
  - Receive: `Orders/ReceivedSTS` → `HOFormsDevEx/ReceivedSTSBatchModeFIFO` (the one STAGING uses: `spu_PostSTSReceiveFromFIFO`, which writes branch Inventory rows) or `ReceivedSTSBatchMode` (`sp_AddBranchInventoryBatch`). Then `sp_ConfirmBranchRecievedOrderJFC` posts IT-BR-*.
- **Bugs proven by rolled-back tests (scratchpad `sts/test_sts.ps1`, 9 scenarios):**
  - Saving twice posted the whole transfer-out again.
  - The VAT split used `InventoryDeliveryFIFO.isVat`, which the JFC deduction always wrote as 0; receipt splits by the line flag. STAGING: 309,906.00 of VAT cost was booked as VAT-exempt.
  - A short receipt left the missing cost in In Transit.
  - The line cost after Save was one arbitrary lot's cost.
  - A barcode return reset a lot to its full original quantity.
  - The normal receive skipped a second line of the same product and wrote ledger rows for cancelled lots.
- **User rule (10-01):** a short receipt is a loss at head office: DR COS OTHERS 503/504 / CR In Transit on 888.
- **Script 20 (`2026-10-01b_STS_Lifecycle_Fixes.sql`):**
  - New `spu_STS_SyncInTransit`: head office's In Transit for a PO equals the cost of its live FIFO lots, split by line VAT; it posts only the difference. Save and returns call it.
  - FIFO rows get the product VAT flag.
  - Save: weighted line cost; refused after the PO is received.
  - Return (JFC): always lot-based.
  - Receipt: posts STS-SHORT-* / STS-OVER-*.
  - Normal receive matches per barcode.
  - New mnemonics STS-SHORT-* / STS-OVER-*. Needs script 19 first.
- **Script 21 (`2026-10-01c_STS_InTransit_Correction.sql`):** runs the sync for every saved STS whose In Transit differs.
  - STAGING: POs 11699 (VAT reclass), 11700 (duplicate + VAT), 11701 (duplicate 1,900,713.41), 14100 (VAT reclass, not yet received).
  - Tested on DEV (rolled back): residuals empty afterwards; a second run posts nothing.
- **STAGING incident 10-01:**
  - POs 11700 / 11701 were hand-un-cancelled and re-saved at 13:09 / 13:18, which created the duplicate IT-HO tickets 18547 / 18554. They were received at 13:22 / 13:25.
  - Their stock is now consistent; only the GL needs script 21.
  - Someone else edited data then (and overwrote scratchpad `q.ps1` at 13:07).
- **Review and deploy:**
  - sp-reviewer blocker taken in a different form: the sync now refuses a PO whose cancelled or returned lines still have active lots (stock never restored), and the correction skips and lists such POs instead of posting (its suggested filter alone would have put GL out of step with stock).
  - Also taken: target and posted both use the whole PO; receive / return / Save share the `STSTRANSIT:<PO>` applock; THROW instead of RAISERROR in the receipt procs; deterministic TOP 1.
  - Deployed 20 + 21 to DEV 2026-10-01.
- **Next:** user UI test on DEV → STAGING (20, then 21).
- **Open:** DEV's PO 11701 (10 lots / 18,644.94 on cancelled lines never restored) needs a decision on DEV only; STAGING's copy was fixed by hand.
- **Open:**
  - Barcode scans write no stock-ledger row.
  - The receive screens make 3 separate calls (not atomic; C# change).
  - DEV's copy of PO 11701 still has cancelled lines with active lots (STAGING was fixed by hand).

## ⚠️ 2026-10-01 rule: the GL is all VAT-exempt (rework needed in scripts 19/20/21)

- User: every item posts as VAT-exempt in the GL (sales, credit memo, return, shrinkage, STS). VAT shows only on printed invoices; the month-end VAT is computed by hand. Keep the line `isVat` and VAT amounts for printing.
- Done (script 23, DEV): `sp_ConfirmOrder` (one SI-VATEX ticket per invoice), `sp_CreditMemo`, `sp_ReturnSalesOrder`, `spu_STS_SyncInTransit`, `sp_ConfirmBranchRecievedOrderJFC` all post VATEX only. Script 21 updated to the same target. Line VAT data (BSD SubTotal/TaxTotal, BSS VAT columns, TCSD SI-VAT/COGS-VAT rows) kept for printing / the month-end VAT.
- Not done (user didn't ask yet): reclass STAGING history — 348 SI-VAT tickets (Aug 1 – Sep 4; 20112 = 225,569.66) and 4 IT-BR-VAT receipts.

## Feature 16 — Exception Center (2026-10-01)

- `tools/ExceptionCenter/SO_STS_ExceptionCheck.sql` (read-only, 15 checks; see CLAUDE.md and its README).
- First run, open findings (nothing fixed yet, user to decide):
  - **STAGING X01, SO 13902:** line 2 (14016, 1,500 kg) cancelled 10-01 18:06 on the OLD cancel proc (before the 21:52 deploy). Only lot 30784 (660) was restored; **840 kg still out of lot 30778**. Repair = restore lot 30778 + ledger row + flag the FIFO row.
  - **STAGING T02, STS 11911 / 11913 / 14100:** In Transit left 224,976.73 / 109,907.78 / 275,683.95 after receipt. In each, product **13025** shipped 2,034.31 / 1,002.60 / 2,506.80 kg but was received as 4.75 / 11.10 / 19.80. **Corrected 2026-10-02: not a unit error.** Each 13025 line came from 124 / 58 / 146 lots, and the FIFO receive screen listed one row per lot; only the first lot (4.75 / 11.10 / 19.80) was received, the rest skipped as "duplicate PONumber+Barcode" (Feature 19). Old receipt proc, so no STS-SHORT: the rest is still in In Transit.
  - **DEV X01, STS 11701:** known (cancelled lines never restored, DEV copy only).
- Checked and not a problem: returns 13809 / 13821 / 14061 and cancel 14044 on 10-01 ran on the old procs, which restored stock without stock-ledger rows (hence `@FromDate` = 2026-10-02 for X02).

## Feature 17 — Partial return, Sales Order + STS (PLAN ONLY, 2026-10-01, nothing built)

- Plan: `docs/plans/2026-10-01_PartialReturn_SO_STS_Plan.md`. Ask: return 50 of a 100-qty line from Orders for Approval › Delivered › Return Order.
- Today a return is whole-line only: the line is the unit of state in 4 tables (`DeliveryDetails.isReturned`, `InventoryDeliveryFIFO.isErrorCorrect`, `BatchSalesDetails.isCancelled`, `TransactionChargeSalesDetails.ErrorTag`).
  - Adding a qty column would touch 54 / 39 / 43 SQL objects.
  - `InventoryDeliveryFIFO` is inserted positionally by the DispatchPerBarcode posting proc.
- Proposed: split the line (and its FIFO, sales and AR detail rows) into kept + returned parts, then run the existing whole-line return on the returned part.
  - New optional TVP `@ReturnQty` on `sp_ReturnSalesOrder`, so the old exe still works.
  - The return is costed at the cost of the lots put back.
  - STS: phase 2, before receipt only.
- **Fixed (C# only, commit bb48873, not yet built or UI-tested on Windows):** `ReturnSalesOrder.cs` showed "Successfully Returned!" even when the proc failed (`sp()` swallowed the SqlException).
  - It now shows success only after a commit; on an error the form stays open.
  - Submit is disabled while the proc runs.
  - `HOFormsDevEx/CreditMemoDevEx.cs` has the same pattern ("Payment Successfully Posted" after a swallowed error); not fixed.
- Found, not fixed:
  - Fully paid POs can't be returned or credit-memo'd (the Paid tab has no menu).
  - The return tags `TransactionChargeSalesDetails` by product + barcode only, so it tags every line with that product + barcode.
  - `ReturnedOrderSummary` keeps the first return's reason and the latest return's tickets only.
  - At STS receiving, a partial qty is booked as a loss (STS-SHORT), never as stock back at head office.
- Waiting on the user: decisions D1–D6 in the plan, and the DEV checks in its section 5.

## Feature 18 — Dispatch Per Barcode (STS) review (2026-10-01, review only, nothing changed)

- Review: `docs/reviews/2026-10-01_DispatchPerBarcode_Review.md`. The user plans to replace `AddBranchOrderSTS` with `HOFormsDevEx/DispatchPerBarcode` (08-24, never used; its menu is hidden).
- **Not on COREX001:** all 8 of its SQL objects are missing in the Atlas snapshot (09-30), so the form fails on open.
- It predates the 09-29 FIFO standard and the 10-01 STS redesign.
- Critical:
  - Destination stock is created at dispatch, and a reverse or an unticked receipt line never removes it.
  - A reverse on a partly dispatched PO (`isProcess = 0`) leaves In Transit posted.
  - A non-888 origin posts In Transit on the origin, but the sync counts 888 only.
- High:
  - Answering "No" on a PO switch posts under the wrong PO.
  - Applock is on DeliveryNo, not `STSTRANSIT:<PO>`.
  - No stock-ledger rows.
  - The Posted tab lists every delivery, sales orders included.
  - Barcode is used as a line key.
  - Eligibility ignores the IsWarehouse rule.
  - Latent: the positional FIFO insert likely writes the lot VAT flag into `isErrorCorrect`.
- The user's concern is confirmed: no requested-items panel (`AddBranchOrderSTS` and V2 show the PO's items).
- **User decision (10-01): V2 (`Orders/AddBranchOrderSTSV2`) replaces `AddBranchOrderSTS`.** Dispatch Per Barcode stays hidden and unused.
- **Alignment pass = script 24 `SQL/2026-10-01f_STS_V2_Alignment.sql`.**
  - It patches the live text of 4 procs by exact anchors; nothing changes if the text differs.
  - It keeps backups `_OLD_10012026230000`, and the rename + create runs in a TRY/CATCH with a post-check.
  - Every STS writer now takes `STSTRANSIT:<PO>` first.
  - `spu_PostSTSLineV2`:
    - Takes the lock.
    - Refuses once the branch has received or started receiving (59834; receive step 1 writes `ReceivedOrderDetails` before step 3 sets DELIVERED).
    - Refuses once the transfer is saved (59835; the form closes after Save, so only a stale screen can still add lines). It no longer calls the sync, so no posting runs nested under its `XACT_ABORT ON`.
    - Refuses a second DeliveryNo for the PO (59836).
    - FIFO and line isVat come from the product flag.
  - `spu_ReverseSTSLineV2`:
    - The same lock and 59834 guard.
    - `spu_STS_SyncInTransit`, dated today, replaces its own ITR-HO-VAT/VATEX tickets.
  - `sp_ConfirmBranchOrderSTS` (Save, shared with the old form): takes the lock first. It used to take it last, inside the sync, which could deadlock with the V2 procs.
  - `spu_PostSTSReceiveFromFIFO`: locks `STSTRANSIT:<PO>` instead of the bare PO number.
  - No parameter changes; only a comment changed in `AddBranchOrderSTSV2.cs`.
- **Verified so far:**
  - Simulated on the repo copies: all 12 anchors and the block banners match once.
  - The patched procs and both scripts parse (sqlfluff T-SQL; negative control flagged deliberate errors).
  - sp-reviewer: no blocker. Its should-fixes are all in: receive lock and guard, no sync in post, deploy post-check, and a test that proves its claims.
- **Not yet run on any database.**
  - Next on DEV: script 24, then `SQL/2026-10-01f_STS_V2_Alignment_Test.sql`, then the Exception Center, then rebuild the Atlas.
    - The test needs `@PONumber` (a fresh request) and `@User` set; leaving `@PONumber` NULL lists candidates.
    - It has 7 rolled-back parts with PASS/FAIL lines, plus an optional two-session lock check described in its header.
  - STAGING: after 13 + 14, with the new exe.
- **Known limits (not fixed):**
  - `sp_PostCompoundTicket` source isn't in the repo.
  - The non-JFC receive proc isn't on the lock protocol.
  - Old-form scan procs take no PO lock, so they can deadlock with V2 on the same PO (the victim rolls back cleanly); hide the old form once V2 is live.
  - DEV PO 11701 (X01): V2 post and cancel there fail with 59605, by design.
- Still open (Dispatch-only, moot unless revived): non-888 origins; over-dispatch tolerance; eligibility per branch.

## Feature 19 — STS FIFO receive skipped all but one lot of a line (2026-10-02, script 25)

- **Report:** DEV PO 13721 (V2), 100 kg of 13035 → receiving said "duplicate PONumber + Barcode".
- **Cause:** `funcview_InventoryDeliveryFIFOForReceiving` (rows of `HOFormsDevEx/ReceivedSTSBatchModeFIFO`) returned one row per FIFO lot. A line taken from several lots showed several rows with the same barcode; `spu_PostSTSReceiveFromFIFO` received the first and skipped the rest. The new receipt proc then booked the rest as STS-SHORT (DEV 13721: 31.45 kg, 2,278.92); the old one left it in In Transit.
- **Fix (script 25, DEV):** function = one row per line (qty = its live lots; source = largest lot; matches DeliveryNo). Proc adds up rows per line (stale screens), resets per-line variables (DECLARE in the loop kept the previous line's lot), picks the largest lot deterministically. No exe change.
  - Multi-lot lines are received at the line's 2-dp weighted cost, so a few cents can go to STS-SHORT (e.g. 7,246.05 shipped vs 7,246.00); GL stays consistent with branch stock.
- **Exception Center T05** added (multi-lot line received as exactly one lot's qty). Finds STAGING 11911 (2,029.56 kg not booked) / 11913 (991.50) / 14100 (2,487.00) and DEV 13721 (31.45).
- **Open (user):** deploy script 25 to STAGING; repair the 4 receipts (complete branch stock + ReceivedOrderDetails + IT-BR for the rest; on DEV 13721 also reverse the STS-SHORT 2,278.92). Confirm with branches 012 / 005 that the full qty arrived first.
- **Per lot (script 26, DEV, user rule 2026-10-02 on PO 13727):** the receipt must mirror the dispatch stock ledger. `spu_PostSTSReceiveFromFIFO` now writes, per source lot, one `ReceivedOrderDetails` row (lot ReferenceCode + cost), one branch `Inventory` row (lot ShipmentNo / ReferenceCode / cost, line barcode) and one `InventoryLedger` row `STS RCVD ITEM PO#<po>`.
  - The line's received qty fills its lots in dispatch order; a short comes off the last lot(s) (user's choice); an over receipt goes on the last lot. Received cost is exact per lot (no average-cost cents).
  - Two branch rows can now share a line barcode. Checked: branch stock is consumed by product + lot SequenceNumber (`sp_doFifo`, branch transfer), POS finds products via `Products.Barcode`; STAGING branches have 0 shared barcodes today, head office already has 12.
  - Exception Center T05 now ignores receipts that wrote `STS RCVD ITEM` ledger rows (fixed proc), so a real short equal to one lot isn't flagged.
  - DEV PO 13727 was received before script 26 (one 30 kg row under lot 12); not repaired.
## Feature 20 — Process Sales Order V2 (2026-10-02, built on DEV)

- Plan: `docs/plans/2026-10-02_AddBranchOrderV2_Sales_Plan.md`. Why: the product scan (`sp_AddBranchOrderHRI_JFC` → `sp_FiFoMappingHRI_JFC`) ignores `IsWarehouse = 1` and takes no lock (oversell race); no order-level lock; nothing stopped lines after Save.
- **User answers:** start on DEV now; no cancel once the invoice number is set; accept over / short as scanned; default method SCAN; old-form scan procs take the lock too; partial return as in STS. JFC vs ENZO IsWarehouse: JFC keeps all lots at 1 (checked: every lot with stock is 1 on both DBs).
- **SQL (script 27, `2026-10-02c_SalesOrder_V2_FIFOEngine.sql`, on DEV 2026-10-02):** `sp_SOOrder_Lock` ('SOORDER:<PO>'), `funcview_SOV2_*`, `spu_PostSOLineV2` (59840–59846, ledger `SO OUT PO#`), `spu_ReverseSOLineV2` (59850–59854, ledger `SO CANCEL ITEM PO#`). Patched (backups `_OLD_10022026160000`): Save `sp_ConfirmBranchOrder` now one transaction + lock + refused after invoice (59847); Confirm, credit memo, return, cancel line and the 3 old scan procs take the lock.
- **Tests (rolled back):** old-form scenarios A–H all tie with the patch (39 steps); V2 harness `lc/test_so_v2.ps1` 13 scenarios pass (AUTO multi-lot, BATCH exact / short refused, SCAN lot, IsWarehouse=0 skipped, not on order, cancel, Save guards, invoice guards, confirm, CM + return, pay + return all).
- **C#:** `Orders/AddBranchOrderV2` (copy of STS V2, sales procs, parameterized checker / sticker queries) + admin "FIFO V2 (Test)" in `ViewBranchOrder`. Compiles; the bin copy failed only because the app was running in the debugger.
- Exception Center X02 and the Process Trace SalesOrder module now know the `SO OUT` / `SO CANCEL ITEM` / `SO RETURN` remarks.
- **Known, pre-existing:** Confirm's COGS = line cost (2-dp weighted) × qty, so it can differ from the lots' exact cost by cents (0.62 on 205 kg in the test). Same in the old form.
- **Next:** reviews (running), user UI test on DEV, then STAGING after STS V2 (needs 13 + 14 + 24 + new exe).

## Feature 21 — Bank Recon: deposits grouped by Control No (2026-10-02, script 29)

- Ask: `AccountingDevEx/BankReconFormV2` should show / group deposits in transit by the control number entered at client payment (`PaymentHeader.ControlNo`, which carries the deposit batch's CR numbers).
- **Found:** (1) `BankStatementRecon.ControlNo` never filled — `sp_AddPaymentClient` inserts one DIT per payment without it (STAGING 4,980 / DEV 2,663 rows blank; all match a PaymentHeader with a ControlNo, 576 control numbers; CASH payments have no cheque/online lines, so the header is the only source). The grid grouping / "Resolve group" (09-03 work) therefore showed one blank group. (2) `SQL/2026-09-04_BankRecon_OCBulkResolve.sql` never deployed, but the form (09-12) passes `@ItemType` → every Bulk Resolve / Resolve group failed. (3) The manual "add DIT by control number" picker would double-count auto-inserted collections.
- **Script 29 `2026-10-02e_BankRecon_ControlNo.sql`:** backfill (backup `BankStatementRecon_ControlNo_Backup_20261002`); `sp_AddPaymentClient` writes ControlNo; `sp_BankRecon_GetPeriod` DIT rows add CRNo / ReferenceNo / PaymentType / ResolvedReason (ControlNo falls back to the payment's); `sp_BankRecon_BulkResolveItems` with `@ItemType`; candidates exclude control numbers already covered. Backups `_OLD_10022026180000`. C#: captions / widths for the new DIT columns.
- Applied to DEV and STAGING 2026-10-02 after rolled-back rehearsals (DEV 2,663 filled, busiest account 2,102 rows → 239 groups; STAGING 4,980 filled, PNB 3,968 rows → 373 groups; a new payment.s DIT carries its ControlNo; bulk resolve works from old and new exe).
- Cash-advance / manual-JV DITs have no control number (stay in the blank group).
- **Reviews:** sp-reviewer — no blocker; fixed: explicit transaction + per-step `@@TRANCOUNT` guards (the script claimed one transaction but relied on the deploy helper), NULL-definition guard before renaming `sp_AddPaymentClient`. Re-rehearsed both DBs. ui-form-reviewer — no blocker.
- **Script 30 (`2026-10-02f`, DEV + STAGING):** OC grid shows ControlNo / CheckNo / voucher no. / source from the issuing voucher (STAGING AP 140 / 143 with control no.; 174 cheques with cheque no.; manual JV has no voucher).
- **Combined grid (C#, needs the new exe):** one grid on the tab replaces the side-by-side DIT / OC grids (built in code; `tablePanel1` / `panelControl6` hidden): Kind column, grouped Kind → Control No with count + Amount total (user: no cross-kind grand total), one button bar reusing the existing methods, Bulk Resolve shows counts by kind and control numbers (warning icon when > 1). ui-form-reviewer: no blocker (its GroupFormat finding was wrong — the string was DevExpress's default; the line was removed).
- **CV # (scripts 31–32):** the CV number is kept in the vouchers' `NotedBy` as a stopgap (`sp_Payment_CreateVoucherHeader` writes `@CheckCoding` there). A new column on `CheckVoucher` is NOT safe: `Accounting/AddCheckVoucher.cs` and `HOForms/TransactionPayment.cs` (still on the menu) insert positionally. User first chose a separate table (script 32), then confirmed both screens are retired, so: `CheckVoucher.CVNo` (script 33), filled by the three in-use writers from the CV number they already receive; NotedBy still written for now (printouts may read it). Telegraphic / cash CV # = ControlNo. The retired screens (AddCheckVoucher, TransactionPayment → `sp_AddPaymentSupplier`) will fail if opened — consider hiding their menu entries. Bank Recon no longer lists reversed items (ResolvedReason REVERSED / VOIDED%).
- **Open (user):** "Select All" ticks rows across every control-number group (could bulk-resolve unrelated batches); `@ItemType` allow-list has no ADB (bank-side grid has no bulk resolve today); `sp_AddPaymentClient` has no double-post guard (a second run would add a second DIT to the group); open DITs carry `ResolvedDate = 1900-01-01` (written as ' '); GetPeriod lists every period ≤ the selected one, so a group can span months while the header totals are one period.

## Open decisions (ask the user)

1. **1-cent rounding in multi-branch payments.** In `sp_AddPaymentSupplierCompound_V2`'s BATCH branch, the last branch's gross = eGross − SUM(**unrounded**
   shares), so branch grosses can sum to eGross + 0.01. Fix: remainder from the running sum of rounded shares.
2. **Reversal zeroes each line's accrual EWT/Discount/Offset** in `sp_CancelledChequesCS` (it subtracts the line's own value from itself). A reversed-and-repaid
   multi-branch invoice may withhold no EWT.
3. **Show overpayments and advances on supplier statements (`SupplierLedger`)?** Would need to be done for all modes together.
4. **Correct historical `Inventory.Cost`** that past whole-invoice costing overstated? It touches stock that may already be sold.
5. **`sp_EditSingleExpense` double-costs PO-linked expenses on edit.** Guard 56103 is commented out, and the old cost is never backed out.
   - 2026-09-29: reported by the user and reproduced (32473 / SI#00254, shipment 11012: supplier-only edit, 68.86 → 112.61). Fix = script 12.
     The repost passes `@isLinkedToPO=0` and the edit proc applies ONE net cost delta. Tested on DEV: supplier-only, amount change, unlink, move shipment.
   - Still open: which shipments were already inflated by past edits (no edit log, can't be told from data); pre-2026-09-24 expenses back out inventory legs only.
6. **"Unit cost 0" for PO 11005.** Waiting for the user to name the screen and column.
   - Found so far: every non-DELIVERED PO has `PODETAILS.Cost` and `POSUMMARY.TotalCost` = 0 (new flow). Inventory cost comes from linked expenses.
   - Item Costing Report and Recon both show the correct cost for 11005.
7. **Optional indexes:** `TicketMaster(ReferenceNumber, ReferenceKey)` and `TicketDetails(TicketNumber, ReferenceNumber)`.

## Pre-existing issues found (flagged, not fixed)

- `sp_ReversePaymentClient` mirrors every `TicketMaster`/`TicketDetails`/`ClientLedger` row `WHERE ReferenceNumber = @refno`. Sales tickets hold the PO number in that same column, and the two numbers come from different counters.
  - On COREX001, 34 payments share their reference with another ticket, and 31 of them are still POSTED. Reversing one would also mirror another customer's sales ticket and ledger row.
  - Fix, when the user approves: `Mnemonic LIKE 'OR-%'` on the tickets; `AccountKey = @custkey AND TransCode LIKE 'OR-%'` on the ledger.

- `sp_PostCompoundTicket`: amount type `MIRROR`, or any amount type missing from `@Amounts`, silently becomes GROSS. So `PV-AP-DISC` and `PV-AP-EWT-DISC` post the
  discount leg at the gross amount. No DR = CR check. No PV-AP tickets existed on DEV yet.
- `PV-AP` bank leg uses GROSS, not NET. It's unbalanced when there's a variance or return allowance without a discount.
- The FX loss mapping points at 60302, but COA 60302 is BAD DEBTS; 60323 is the FX account.
- PURCHASE reversal matches invoices on `SequenceNo` only and subtracts `APAccounts` columns that posting never adds to.
- The "already reversed" guard checks only `CheckVoucher`, not Cash or Telegraphic vouchers.
- Multi-branch BATCH: if `@eNetLiability = 0`, branch amounts become NULL.
- `sp_PostExpenseManualMultiBranch` calls `GetTicketNumber` once, before the branch loop, so every branch shares one ticket number.
  `sp_EditExpenseManualMultiBranch` gets a new number per branch. Not changed; confirm which one is intended.

## Gotchas learned (candidates for CLAUDE.md Known Bug Patterns)

- Multi-branch expenses are `PostingMode='MULTI-MANUAL'`. V2 sends everything that isn't SINGLE through its "BATCH" branch.
- V2's CATCH uses `ROLLBACK TRANSACTION PaySupplierV2`, a named rollback. Inside an outer test transaction this masks the real error with error 6401.
  To see the real error, test through a temporary copy with that line replaced, then drop the copy.
- `TransactionPaymentAP.ReferenceNumber` is numeric; `CashVoucher.VoucherID` is `decimal(7,0)`. Test IDs must be numeric and at most 7 digits.
- `APPaymentDetails.ReferenceNumber` is `char(5)`.
- In PowerShell, `SqlConnectionStringBuilder.InitialCatalog` doesn't work as a property. Use `$b["Initial Catalog"]`.

## How DB checks were done (per machine)

Read-only queries and DEV deploys ran through small PowerShell helpers kept in the session scratchpad, not in the repo.
They read the registry connection string: value `dbconn` under `HKCU\AAITCRE\ConnSettingsMain`.
They unprotect it with DPAPI (entropy `CORECS-ConnSettings-v1`, same as `Classes/RegistryProtection.cs`) and switch databases by replacing `Initial Catalog`.
**Default to `COREX001`.** The registry already points there. Don't hard-code `CORECSERP_002_DEV` in the helpers.
In PowerShell, pass the catalog as a `[string]`; a pipeline `PSObject` makes the assignment throw.
Every write test ran inside `BEGIN TRAN … ROLLBACK`, followed by a check that no test rows remained.
No credentials are stored anywhere.
