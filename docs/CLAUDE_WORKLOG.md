# Claude Work Log (session handoff)

Imported into every Claude Code session via `CLAUDE.md`, so a fresh terminal on any
machine picks up where the last one stopped. **Keep it short and current:** update
the Status / Open items when something changes; move finished items to "Done" in one
line. Durable rules belong in `CLAUDE.md` itself, not here.

Last updated: **2026-10-01**

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
| 8 | `2026-09-25d_ExpenseManualMultiBranch_PreserveLineOrder.sql` | ✅ | ⏳ ship with the new exe |
| 9 | `2026-09-25e_ManualJV_PreserveLineOrder.sql` | ✅ | ⏳ ship with the new exe |
| 10 | `2026-09-25f_IncomeStatementPivot_HeadOfficeFirst.sql` | ✅ | ⏳ |
| 11 | `2026-09-26_ItemCostingRecon_ExpenseTickets.sql` | ✅ (by user, 14:24) | ✅ (by user, 14:56) |
| 12 | `2026-09-29_EditSingleExpense_NoDoubleCosting.sql` | ✅ already applied 2026-09-29 14:50 (outside this log); matches the script, backup = original; smoke-tested 2026-09-30 | ⏳ |
| 13 | `2026-09-29b_InvFIFO_Engine.sql` | ✅ 2026-09-30 13:33 (smoke-tested, rolled back) | ⏳ |
| 14 | `2026-09-29c_STS_V2_FIFOEngine.sql` (needs 13) | ✅ 2026-09-30 13:33 | ⏳ ship with the new exe |
| 15 | `2026-09-30_GL_RealTime_Reports.sql` | ✅ 2026-09-30 23:08 (smoke-tested) | ⏳ ship with the new exe |
| 16 | `2026-09-30_GL_PeriodLock.sql` | ✅ 2026-09-30 23:08; nothing closed yet; two-session race test passed | ⏳ ship with the new exe |
| 17 | `2026-09-30b_SupplierLedger_Rebuild.sql` | ✅ 2026-09-30 23:24 (829 rows / 33 accounts fixed; audit now 0/0/0) | ✅ 2026-09-30 23:26, user-approved (801 rows / 38 accounts fixed; rehearsed rolled back first; audit now 0/0/0) |
| 18 | `2026-09-30c_ClientLedger_RecalcTrigger.sql` | ✅ 2026-09-30 (3 rows / 2 accounts fixed; audit now 0/0/0) | ✅ 2026-09-30, user-approved (6 rows / 2 accounts fixed; rehearsed rolled back first; audit now 0/0/0) |

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
  - Module 1 = AR Payment. Samples: 5155 (cheque + EWT, 3 invoices) and 5591 → reversed → 6163 (cash + overpay).
  - **Next module: user to pick** (Supplier Payment / Expense / STS).
- `tools/ProcessTrace/` and `docs/process-trace/` were not committed yet as of this entry.
- Git: on 10-01 `main`'s uncommitted `ClientPaymentsDevExAcctg.Designer.cs` / `.resx` + build output were stashed (`stash@{0}`, "main WIP …") before switching back to `laptopdell`. They're still in the stash; nothing is applied.

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
