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
| 11 | `2026-09-26_ItemCostingRecon_ExpenseTickets.sql` | ✅ (by user, 14:24) | ✅ (by user, 14:56) |
| 12 | `2026-09-28_ConversionBarcode_CostComputation.sql` | ✅ (2026-09-28) | ⏳ |
| 13 | `2026-09-28b_UserAccountingReportAccess_NewTable.sql` | ✅ (2026-09-28) | ⏳ ship with the new exe |
| 14 | `2026-09-28c_ItemCostingDetail_SoldVsTransfer.sql` | ✅ (2026-09-28) | ⏳ deploy together with 15 |
| 15 | `2026-09-28d_ItemCostingMaster_TransferTotals.sql` | ✅ (2026-09-28) | ⏳ deploy together with 14 + new exe |
| 16 | `2026-09-29_InventoryUnitActivity_TransferColumn.sql` | ✅ (2026-09-29) | ⏳ ship with the new exe |
| 17 | `2026-09-29b_PostedClientPayments_PaymentDetails.sql` | ✅ (2026-09-29) | ⏳ ship with the new exe (optional: old exe just shows extra columns) |

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

## Feature 8 — Conversion (ConversionPerBarcode) output cost (script 12)

- **Bugs in `spu_PostConversionBarcode`:**
  - The material rate took drip loss off twice (÷ 29.08 instead of 29.54).
  - The whole cutting charge was added per kg.
  - CVB-000045 posted 450.04 / 51.25 per kg.
- **Fix, exactly per the user's worksheet** (Google Sheet, yellow cells):
  - `unit = (SourceCost/Q + CuttingCharge/Q) × (qty/Q)`, where Q = source qty − drip loss.
  - CVB-000045 → 229.68 / 26.16.
- **User-confirmed:** the "× qty/Q" factor means output value < input value when there are 2+ outputs (CVB-000045: 6,170.13 of 7,557.40). The difference lands in the CONV-FINALIZE COGS legs.
- Test data (CVB-000001..45) lives in the old DEV (`CORECSERP_002_DEV`). Posted conversions were not recomputed.
- Tested on COREX001 in a rolled-back transaction: every yellow number matched. Many-to-One = (cost + charge)/Q. sp-reviewer run 2026-09-28.

## Feature 9 — Accounting Reports V2: per-user report visibility (script 13)

- **Table:** new `UserAccountingReportAccess(UserID, ReportKey)`, same pattern as `UserAccountingBoardAccess`.
- **Report form:** each ReportConfig in `AccountingReportsFormV2` has a stable `Key` (e.g. `TRIAL_BALANCE`).
  - The dropdown is filtered in `LoadData()`, and Generate re-checks access.
- **Rules (user's choice):**
  - A user with no rows sees all reports.
  - Global admins always see all.
  - Only the V2 form is filtered; V1 is untouched.
- **Admin:** new "Accounting Reports" tab in User Access (`UserAccessDevEx`).
  - It's filled from `AccountingReportsFormV2.ReportAccessCatalog`, so new reports appear automatically.
- **Status:** compiled; exe copy blocked while the app was open in the debugger. ui-form-reviewer run. Needs a UI test.

## Feature 10 — Item Costing Report: Sold vs Transfer (script 14)

- `sp_rpt_ItemCostingReport_Detail`: a delivery's MovementType is `Transfer` if its PONumber is in `TransferOrderSummary`, else `Sold`.
- Data on COREX001:
  - 7,070 POs are in PurchaseOrderSummary, 25 in TransferOrderSummary, 0 in both.
  - 14 are in neither (branch 004, 2026-09-09). They have C- charge invoices, so they're treated as Sold. Their PO headers are missing, which is worth a data fix.
- `ServiceOrderSummary` was not used: SVCNumber overlaps PONumber (164 collisions).
- Verified old vs new: same 13,683 rows, identical rows by content, identical per-lot net qty/value. 104 rows changed Sold → Transfer.
- **Pre-existing:** the running-balance ORDER BY has ties, so tied rows' running values shuffle between runs. Candidate fix: add a tiebreaker.
- **Master (script 15):** Sold totals now cover sales only; new `TotalTransferQty` and `TotalTransferCost` columns.
  - Captions and N3/N2 formats added in `Reporting/ItemCostingReport.cs`.
  - Verified: same 1,196 rows, and Sold + Transfer = old Sold for every lot. Master matches Detail for all lots (50 have transfers).
- Why the bare PONumber match is safe: Purchase and Transfer orders share one counter (`dbo.ponumber`).

## Feature 11 — Inventory Unit Activity report: transfers (script 16)

- **Key fact:** on a transfer row, `InventoryDeliveryFIFO.BranchCode` = the requesting (destination) branch. The stock leaves the source lot's `Inventory.Branch` (all 108 rows). Sales rows have BranchCode = lot branch.
- **`spr_InventoryUnitActivity` changes:**
  - New `InventoryTransfer` column: transfer-out, credited to the source lot's branch.
  - UnitSold and Sales now cover sales only, and are date-filtered (they were all-time).
  - One row per item; it used to split into a stock row + a zero-cost row.
  - UnitCost = weighted average over all the branch's lots, so COGS is no longer 0.
- Form: caption + N3 + footer sum.
- **Verified on COREX001 for branches 888 and 004 (Sept):**
  - Beginning and Purchased unchanged.
  - Sold and Transfer equal direct queries (888 transfer-out 81,449.78).
  - 0 split rows, 0 zero-cost moved rows.
- **Pre-existing, not fixed:**
  - Unit Purchased join multiplies PODETAILS qty by lots per shipment (888 Sept = 106M).
  - "Adjustment" is always 0.
  - "Beginning" = lots received in the range.

## Feature 12 — POS X/Z-Read: "Generate Invoices" for a Z-Read (C# only)

- **New `Classes/POSInvoiceRegenerator.cs`** (in the csproj):
  - Rebuilds each sale's invoice text in the checkout format. It mirrors both `Printing.printReceipt` overloads (regular, and one-time discount, which writes CLIENT/ACCOUNTING copies).
  - Reads saved data: BatchSalesSummary/Details, SalesDiscount, Users.
  - Writes files to `C:\POSTransaction\ZReadInvoices\<Branch>\<yyyyMMdd>_<Machine>\` plus a `GenerationLog.txt`. No printing, no DB writes; the live `printReceipt` is untouched.
- **`POSXReadReportDevEx`:** new context-menu item "Generate Invoices", shown for ZREAD only.
  - Right-click now focuses the clicked row; this also affects Print and Show Credit Details.
- **User's choices:** exact copy, files only, Tran# matched by sequence to POSTransaction 'SALES' rows (blank if counts differ).
- **Known limits:**
  - Customer name/address/TIN typed at checkout are never saved → blanks.
  - Date/time comes from the paired POSTransaction.DateAdded, else Transdate.
- **Not tested with data:** no reachable DB has POS sales or Z-Reads. The user will test on a terminal, comparing files against `C:\POSTransaction\DailySales`.
- **Review fixes (csharp-data-reviewer):**
  - Amount payable = lines − SUM(DiscountAmount) − SUM(VatAdjustment), as checkout computes it. `BatchSalesSummary.TotalAmount` is NOT net of the VAT adjustment.
  - Tran# pairing is checked against CashiersBlotter (Tran# + amount, written for every sale) and falls back to amount matching.
  - TOTAL DISCOUNT uses {0:n2}; SalesDiscount is filtered by machine; FORMAT text is parsed in en-US.
  - The log flags an empty header and line/total mismatches.
  - One connection per run, with caches; the folder is cleared before each run.
- **Tran# facts:** the branch-wide counter is MAX(POSTransaction)+1. Discount, cancel-line, void, reprint and error-correct also bump it. So `SalesDiscount.TransactionNo` can differ from the printed Tran#; it's used only as a fallback.

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
