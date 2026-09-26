# Claude Work Log (session handoff)

Imported into every Claude Code session via `CLAUDE.md`, so a fresh terminal on any
machine picks up where the last one stopped. **Keep it short and current:** update
the Status / Open items when something changes; move finished items to "Done" in one
line. Durable rules belong in `CLAUDE.md` itself, not here.

Last updated: **2026-09-25 (evening)**

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

## Open decisions (ask the user)

1. **1-cent rounding in multi-branch payments.** In `sp_AddPaymentSupplierCompound_V2`'s BATCH branch, the last branch's gross = eGross − SUM(**unrounded**
   shares), so branch grosses can sum to eGross + 0.01. Fix: remainder from the running sum of rounded shares.
2. **Reversal zeroes each line's accrual EWT/Discount/Offset** in `sp_CancelledChequesCS` (it subtracts the line's own value from itself). A reversed-and-repaid
   multi-branch invoice may withhold no EWT.
3. **Show overpayments and advances on supplier statements (`SupplierLedger`)?** Would need to be done for all modes together.
4. **Correct historical `Inventory.Cost`** that past whole-invoice costing overstated? It touches stock that may already be sold.
5. **`sp_EditSingleExpense` double-costs PO-linked expenses on edit.** Guard 56103 is commented out, and the old cost is never backed out.
6. **"Unit cost 0" for PO 11005.** Waiting for the user to name the screen and column.
   - Found so far: every non-DELIVERED PO has `PODETAILS.Cost` and `POSUMMARY.TotalCost` = 0 (new flow). Inventory cost comes from linked expenses.
   - Item Costing Report and Recon both show the correct cost for 11005.
7. **Optional indexes:** `TicketMaster(ReferenceNumber, ReferenceKey)` and `TicketDetails(TicketNumber, ReferenceNumber)`.

## Pre-existing issues found (flagged, not fixed)

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
