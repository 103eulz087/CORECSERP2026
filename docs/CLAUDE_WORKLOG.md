# Claude Work Log (session handoff)

Imported into every Claude Code session via `CLAUDE.md`, so a fresh terminal on any
machine picks up where the last one stopped. **Keep it short and current:** update
the Status / Open items when something changes; move finished items to "Done" in one
line. Durable rules belong in `CLAUDE.md` itself, not here.

Last updated: **2026-09-25**

---

## Deployment status

DEV = `CORECSERP_002_DEV` · STAGING = `CORECSJFC2026_STAGING` (same server). Per CLAUDE.md, STAGING only after the user confirms.

| # | Script (`SQL/`) | DEV | STAGING |
|---|---|---|---|
| 1 | `2026-09-24_SupplierPayment_OverpaymentCredit.sql` | ✅ | ⏳ pending go-ahead |
| 2 | `2026-09-24c_SupplierPayment_OverpaymentCredit_ExpenseSingle.sql` | ✅ | ⏳ |
| 3 | `2026-09-25_SupplierPayment_OverpaymentCredit_ExpenseMultiBranch.sql` | ✅ | ⏳ |
| 4 | `2026-09-25b_CancelledChequesCS_ExpenseMasterNullBalance.sql` | ✅ | ⏳ |
| 5 | `2026-09-24_ExpenseInventoryCosting_InventoryLegsOnly.sql` | ✅ | ⏳ |
| 6 | `2026-09-24b_ItemCostingRecon_MasterDetail.sql` | ✅ | ⏳ |

Run on STAGING **in this order** (1→6). Each script renames the live object to
`<name>_OLD_<timestamp>` before recreating it. Scripts 2–4 recreate procs that
script 1 also creates, so order matters. The DEV redeploys along the way
used fresh backup suffixes, and each file's current suffix is unique.

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

## Gotchas learned (candidates for CLAUDE.md Known Bug Patterns)

- Multi-branch expenses are `PostingMode='MULTI-MANUAL'`. V2 sends everything that isn't SINGLE through its "BATCH" branch.
- V2's CATCH uses `ROLLBACK TRANSACTION PaySupplierV2`, a named rollback. Inside an outer test transaction this masks the real error with error 6401.
  To see the real error, test through a temporary copy with that line replaced, then drop the copy.
- `TransactionPaymentAP.ReferenceNumber` is numeric; `CashVoucher.VoucherID` is `decimal(7,0)`. Test IDs must be numeric and at most 7 digits.
- `APPaymentDetails.ReferenceNumber` is `char(5)`.
- In PowerShell, `SqlConnectionStringBuilder.InitialCatalog` doesn't work as a property. Use `$b["Initial Catalog"]`.

## How DB checks were done (per machine)

Read-only queries and DEV deploys ran through small PowerShell helpers kept in the session scratchpad, not in the repo.
They read the registry connection string (`HKCU\AAITCRE\ConnSettingsMain`), unprotect it with DPAPI (entropy `CORECS-ConnSettings-v1`,
same as `Classes/RegistryProtection.cs`), and switch to STAGING by replacing `Initial Catalog`.
Every write test ran inside `BEGIN TRAN … ROLLBACK`, followed by a check that no test rows remained.
No credentials are stored anywhere.
