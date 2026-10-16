# Supplier Payment (Cash / Check): purchases and expenses in one list and one voucher — plan

**Asked by the user, 2026-10-14:** in `AccountingDevEx/SupplierPaymentDevEx.cs`, drop the Purchase / Expense radio buttons,
show both kinds of invoices together, and let one voucher pay both (they sometimes pay a supplier's purchase and
expense invoices with one cheque). **Status: GO (user, 2026-10-15), cash / check only (the Telegraphic screen stays as it is); built as script [97] (see `docs/CLAUDE_WORKLOG.md`). Was: pending; nothing was
built until then.** Reminder kept in `docs/CLAUDE_WORKLOG.md`, "Open decisions" item 0.

## What exists today (read 2026-10-14, DEV = STAGING = PRODUCTION text)

- **List:** `splist_Accounts(@parmsupplierid, @parmispurchase, @parmisexpense)` returns one kind at a time. Both shapes are
  identical and already carry `Type` = PURCHASE / EXPENSE. With both flags on it returns purchases only (no caller
  does that: both screens use radio buttons). Other callers: `VoucheringManualFrm` (telegraphic) and the old
  `HOFormsDevEx/SupplierPaymentDevEx`.
- **Post:** the screen calls `sp_PostSupplierPaymentWithManualLines` (one transaction since [85]) →
  `sp_AddPaymentSupplierCompound_V2` with `@parmpaymethod` = PURCHASE or EXPENSE. One V2 call writes, per voucher:
  one `TransactionPaymentAP` row, the per-invoice tickets / `APPaymentDetails` / supplier-ledger rows, **one** bank-recon
  OC item (`sp_Payment_PostBankReconEntry`) and **one** voucher header (`sp_Payment_CreateVoucherHeader`).
  Calling V2 twice for one voucher (purchases, then expenses) would write two voucher headers for one voucher no., two
  `TransactionPaymentAP` rows, and the second OC would be **silently dropped** (the recon helper is idempotent by
  reference + account + type: Known Bug #9). So the combination has to happen inside the posting, not by two calls.
- **Reverse:** `SupplierVoucherReversalFrm` → `sp_ReverseCombinedSupplierVoucher` → `sp_CancelledChequesCS` with
  `@parmvouchertype` = PURCHASE or EXPENSE (taken from the voucher's `APPaymentDetails.PaymentMethod`). Its purchase and
  expense blocks each filter `APPaymentDetails` by their own PaymentMethod, so running both blocks for one voucher is
  safe by construction.
- **PRODUCTION (read-only, 10-14):** 198 expense vouchers, 12 purchase vouchers, none mixed; 2 suppliers have both kinds
  open right now; 1 past case of a supplier paid on the same day by one purchase and one expense voucher.

## Design (recommended)

Single-kind vouchers keep today's exact path; only a voucher that really mixes both kinds takes the new path.

1. **List** (`splist_Accounts`): both flags on = purchases and expenses together (UNION ALL, by invoice date), `Type`
   shows which. Existing calls (one flag) unchanged.
2. **Post** (`sp_AddPaymentSupplierCompound_V2`, optional parameters only):
   - `@SkipVoucherWrap BIT = 0` — when 1, V2 posts the invoice lines (tickets, payment rows, ledger, invoice balances)
     but not the voucher-level rows (`TransactionPaymentAP`, OC, header), and returns its net cash in `@NetCashOut`.
   - `sp_PostSupplierPaymentWithManualLines` gets an optional `@PurchaseLines` / `@PurchaseLineExtras` pair. With lines
     of both kinds it calls V2 twice with `@SkipVoucherWrap = 1` (PURCHASE, then EXPENSE), then writes ONE
     `TransactionPaymentAP` row, ONE OC for the combined net cash, ONE voucher header (cheque = combined total), all in
     its one transaction (as [85]). Manual debit lines work as today.
   - Voucher-wide rules checked once across both kinds: OverPay on one invoice per voucher (60513); Advance Applied
     can't exceed the supplier's credit (shared pool, already re-read under the supplier applock — the second call sees
     the first call's rows in the same transaction).
3. **Reverse** (`sp_CancelledChequesCS`): new value `@parmvouchertype = 'MIXED'` runs the purchase block and the expense
   block; everything after them (tickets, ledger, recon void, voucher void, audit) already works per voucher. The
   reversal screen sends MIXED when the voucher's lines carry both payment methods. A mixed voucher is reversed whole
   (one cheque).
4. **Views / print:** "Invoices (as paid)" (`sp_GetSupplierVoucherInvoiceView`) checked for mixed vouchers; the printed
   voucher's type reads "PURCHASE / EXPENSE" when mixed.
5. **Screen** (`SupplierPaymentDevEx`): radio buttons removed (hidden), the list loads both kinds with a visible Type
   column; the 9 spots that branch on the radio switch to the row's Type (EWT / discount / return-allowance rules
   differ per kind today and stay per row); Post decides PURCHASE / EXPENSE / mixed from the ticked rows.
6. **Out of scope unless asked:** the Telegraphic screen (`VoucheringManualFrm`) keeps its radio buttons.
7. **Checks:** rolled-back tests on DEV — single-kind vouchers identical old vs new (purchase, expense single,
   multi-branch expense, with OverPay / Advance / EWT / discount); mixed voucher: one header, one OC = cheque = bank
   credits, both invoice kinds settled, ledger right; mixed reversal restores both; refusals. Exception Center AP checks
   (AP-VOUCHER-LEGS etc.) stay 0; a new check "voucher with more than one header / OC ≠ cheque" if not already covered.
   Process Trace "Vouchering: Cash / Check" gets a mixed sample. Script [87], DEV → STAGING on the user's go → PRODUCTION
   by the user; the new exe is needed for the screen (the SQL works with the old exe).
