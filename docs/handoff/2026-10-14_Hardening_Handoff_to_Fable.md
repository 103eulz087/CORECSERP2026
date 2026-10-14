# Hardening handoff: ERP session → Fable

**From:** the ERP session (Claude Code on this repo; it has run the posting fixes, data repairs, deployments and Exception
Center checks since 2026-09-24). **To:** Fable, the guardrail-hardening session.
**Written:** 2026-10-14. **Verified live:** the "Evidence" lines marked *(PROD 10-14)* were read on PRODUCTION with the
read-only login on 2026-10-14.

**Page:** https://claude.ai/artifact/UjuHjrDDgk87Y5418K5oHR (source `docs/handoff/HardeningBacklog.html`). When an item's status changes here, update the page source the same way and republish it to that URL (pass it as `url`); don't create a new page.

The goal is one shared backlog worked one item at a time, with no two sessions changing the same thing. This file is
the backlog and the coordination point. Read `CLAUDE.md` and `docs/CLAUDE_WORKLOG.md` first: every rule there applies.

---

## 1. How we work together (not against each other)

| Who | Owns |
|---|---|
| **Fable** | Hardening: guardrails in procs, triggers, constraints, shared helpers and C# patterns that make a bug class impossible or loud. One backlog item at a time. |
| **ERP session** | Day-to-day: user requests, data repairs, deploy runs, Exception Center checks and their findings, the work log. Verifies Fable's items independently after each one. |
| **The user** | Picks the next item, approves every STAGING change, runs every PRODUCTION script. |

**Protocol**

1. **Claim before touching.** Set the item's status in section 4 to `FABLE: IN PROGRESS` (with the date) before changing
   any code or object. The ERP session does not touch an object listed under a claimed item; if it must (an urgent user
   fix), it writes a line under that item first, and Fable rebases on the new definition.
2. **Check the live object first.** Before altering a proc, read its current definition and `modify_date` on DEV and
   STAGING; scripts in `SQL/` can be older than the live object (the user also edits procs directly). Patch the live
   text by anchors, or recreate from the live text, never from a repo copy you have not compared.
3. **Script numbers are shared.** One series `[NN]-YYYY-MM-DD<letter>_Name.sql` in `SQL/`. Next free number on
   2026-10-14: **[85]** ([78]-[82] ERP session; [83] H1 and [84] H3 = Fable). Claim it by adding the row to the work log's deployment table when you create the file.
4. **Backward compatible, always.** The WinForms exe and the coming web v2 share this database (CLAUDE.md "Roadmap").
   New parameters are optional; new behaviour is opt-in or provably identical for old callers; old procs are renamed
   `_OLD_<MMDDYYYYHHMMSS>` before recreating.
5. **Prove it.** DEV first; every write test inside `BEGIN TRAN … ROLLBACK`, then a check that nothing was left. Each
   hardening adds or keeps an **Exception Center check** that proves the invariant (section 3). STAGING only on the
   user's go, after a rolled-back rehearsal there. PRODUCTION: the user runs it; verify read-only afterwards.
6. **Record the rule, not just the code.** Every new rule goes in the work log (and `docs/standards/` when it is
   system-wide); v2 reads them.
7. **Hand back.** Fill the item's "Result" line (scripts, tests, what changed for users) and set `DONE (Fable)`.
   The ERP session re-verifies and sets `VERIFIED`.

---

## 2. Environment you need (details in CLAUDE.md)

- **Databases:** DEV `COREX001` (default instance; key `AAITCRE\ConnSettingsServer`, catalog COREX001) · STAGING
  `corex.itcoreapps.com,6601` / `CORECSJFC2026_STAGING` (key `AAITCRE\ConnSettingsStaging`, db_owner) · PRODUCTION
  `,7701` / `PRODJFC_COREX` (key `AAITCRE\ConnSettingsProdReadOnly`: `claude_readonly`, SELECT + VIEW DEFINITION only;
  procs and scalar functions can't run under it, write checks as SELECT). Print `Data Source` + `Initial Catalog`
  before every check.
- **Connection strings** are DPAPI-protected in HKCU (entropy `CORECS-ConnSettings-v1`, `Classes/RegistryProtection.cs`);
  `ConnSettingsServer` is legacy plain text. Never put credentials in a file.
- **Map and invariants:** Dependency Atlas (https://claude.ai/artifact/ExWdEYaxmbU9VMZbLpumWa, builder
  `tools/DependencyAtlas/`), Process Trace (`tools/ProcessTrace/`), Exception Center
  (`tools/ExceptionCenter/SO_STS_ExceptionCheck.sql`, `POSV2_ExceptionCheck.sql`, `BankRecon_GLvsRecon_Check.sql`,
  and the AP provider `sp_rpt_exc_AP_*` registered in the web portal's `ExceptionDefinition`, scripts [70] / [77]).
- **Gotchas that cost time:**
  - A table TYPE created inside a transaction can't be used in it: create types committed first.
  - `INSERT … EXEC` can't nest (a proc that itself does `INSERT … EXEC`, e.g. `sp_RecordCancelledCheque`, fails inside
    one), and counts as a transaction (the portal's summary skips providers then).
  - Named rollbacks (`ROLLBACK TRANSACTION PaySupplierV2`) inside an outer test transaction raise 6401 and hide the real
    error: test through a temporary copy with the line replaced.
  - A refusal (THROW) dooms the whole test transaction: one refusal per test transaction.
  - A guard batch with `THROW` stops only its batch; use `RAISERROR` + `SET NOEXEC ON` to stop the script.
  - PowerShell: `$b["Initial Catalog"] = [string]$x`, not `.InitialCatalog`.
  - `TransactionPaymentAP.ReferenceNumber` is numeric; `CashVoucher.VoucherID` decimal(7,0); `APPaymentDetails.ReferenceNumber`
    char(5); `ARPaymentDetails.PONumber` varchar(10).
- **Number counters:** `sp_GetVoucherNumber` / `sp_GetReferenceNumber` keep theirs in tables (`vouchernumber`,
  `ReferenceNumber`), so a rolled-back test gives the numbers back. Check any other generator before relying on that.

---

## 3. Already hardened (don't redo; build on)

| Area | Guardrail in place | Script |
|---|---|---|
| Supplier / client ledgers | Recalc triggers on INSERT / UPDATE / DELETE (`trg_SupplierLedger_Recalc`, `trg_ClientLedger_Recalc`) | 17, 18 |
| GL month close | `GLPeriodLock` + triggers on TicketDetails / TicketMaster (59900); reversals dated like their source | 16, 51, 52 |
| FIFO stock | Engine `spu_InvFIFO_*`, per-product applocks, IsWarehouse rule, sticker rule | 13, 34, 37 |
| SO / STS lifecycle | Per-order applocks (`SOORDER:` / `STSTRANSIT:`), In Transit = live FIFO cost, cancel restores every lot | 19, 20, 24, 27 |
| Multi-branch payment split | Last branch = settled − rounded shares (60523 / 60524) | 61 |
| Supplier reversal | Settled amount incl. FX variance; double reversal refused; applock | 62 |
| Supplier ledger side | Payments written as debits (`@LedgerSide`) | 71 |
| Expense with no payable | Balance 0, never NULL | 72 |
| Cancelled cheques | Number used up; trigger refuses reuse (60631) | 55–57, 74 |
| Bank recon | Cleared-in-month stamp, no silent moves, lock checks on resolve / bulk | 46, 48, 49 |
| Voucher (telegraphic) | Gross re-derived from UPDLOCK'd balance (Known Bug #10); one recon call per account (#9) | (sp_PostVoucherManual) |
| Shipment costing base | `fn_InvShipmentBase()`: a shipment's per-kg cost uses its PO-branch lots, never every row with the ShipmentNo (STS copies count moved stock twice); drift + ambiguous-base checks in the AP provider | 78 (DEV + STAGING + PRODUCTION; its 2 checks reach the PRODUCTION portal when [78] is re-run after sql/43 + [70] + [77]) |
| Compound ticket writers | `sp_PostCompoundTicket` / `sp_PostCompoundTicketSales` stage and check every leg (50021–50023, 50040, 50041) before writing; real error re-thrown; PV-AP mapping balanced (bank NET, DISCRETALLOW, FX 60323); Exception Center G03 | 83 (DEV + STAGING; PRODUCTION pending) |
| Posting proc error handling | One pattern (standard doc): XACT_ABORT, transaction first, guards THROW, CATCH rolls back and re-throws the real error; 8 procs converted, 2 retired candidates named | 84 (DEV + STAGING; PRODUCTION pending) |

---

## 4. Backlog: what still needs hardening (priority order)

Status values: `OPEN` · `FABLE: IN PROGRESS (date)` · `DONE (Fable)` · `VERIFIED`.

| # | Item | Tier | Status |
|---|---|---|---|
| H1 | `sp_PostCompoundTicket`: no DR = CR assertion, silent amount-type fallback, lost error text | A | FABLE: IN PROGRESS (2026-10-14; DEV + STAGING done, PRODUCTION pending) |
| H2 | AR payment reversal can mirror another document's tickets (shared ReferenceNumber) | A | FABLE: IN PROGRESS (2026-10-14; DEV + STAGING done, PRODUCTION pending) |
| H3 | Error handling standard: named / unguarded rollbacks and re-throws that hide the real error | A | FABLE: IN PROGRESS (2026-10-14; DEV + STAGING done, PRODUCTION pending) |
| H4 | Multi-step postings that are not atomic | A | FABLE: IN PROGRESS (2026-10-14; DEV + STAGING done, PRODUCTION pending) |
| H5 | Client-supplied amounts and balance formulas (Known Bug #10 beyond the telegraphic voucher) | A | OPEN |
| H6 | Lookups that pick the wrong record (`getSingleValue`, non-unique ValueMember) | A | OPEN |
| H7 | Bank recon loopholes (silent no-op helper, edits that reopen cleared items, unguarded writes, Auto-Match) | B | OPEN |
| H8 | Broken cross-references and racy sequence numbers in expense / ledger posting | B | OPEN |
| H9 | Period lock covers the GL only (before the first month is closed) | B | OPEN |
| H10 | String-built SQL in C# posting / approval paths | B | OPEN |
| H11 | Swallowed exceptions that report success | B | OPEN |
| H12 | Zero-value and zero-cost edge cases in sales / conversion costing | C | OPEN |
| H13 | Trust model: `@User` comes from the client over a shared SQL login | C (design) | OPEN |

Tier A = money or a ledger can go wrong silently today. B = a loophole that needs a specific sequence or a manual
action. C = needs a user / accountant decision before code.

---

### H1. `sp_PostCompoundTicket` can post an unbalanced ticket and hides its errors (Tier A)

- **Problem.** The shared mnemonic-driven ticket writer (callers: `sp_AddPaymentSupplierCompound_V2` / `_Compound` PV-AP
  legs, `SP_POSTINVENTORY`, `sp_FinalizeInventoryUpload`, others in the Atlas) trusts `JournalEntryMapping`:
  - no DR = CR check before insert *(PROD 10-14: no such check in the definition)*;
  - an amount type missing from `@Amounts` falls back to GROSS, so `PV-AP-DISC` / `PV-AP-EWT-DISC` post the discount
    leg at the gross amount; the `PV-AP` bank leg uses GROSS, not NET (unbalanced with a variance or return allowance);
  - every error is re-thrown as `50050 'ERROR SP'` *(PROD 10-14: still so)*, so the screen never shows the real cause;
  - mapping data: FX loss points at 60302 (COA: BAD DEBTS); 60323 is the FX account (accountant to confirm).
- **Hardening.** Assert balanced (per ticket and branch) before the insert, with its own error number; refuse an
  amount type the caller didn't supply instead of defaulting; `THROW;` the original error; validate every mapped
  account against the COA. Keep the signature (the `@LedgerSide` parameter from [71] stays).
- **Acceptance.** Rolled-back tests per caller mnemonic: balanced cases unchanged (compare ticket lines old vs new),
  unbalanced / missing-type cases refused with the new codes; Exception Center check "any ticket with DR ≠ CR" (all
  modules, not only AP; AP-TICKET-UNBALANCED is the AP slice) = 0 on all three databases.
- **Result (Fable, 2026-10-14):** script `[83]-2026-10-14i_H1_CompoundTicketWriter_BalanceCheck_PVAPMapping.sql`. Both writers (`sp_PostCompoundTicket`, `sp_PostCompoundTicketSales`) stage the legs and refuse 50021 (amount type not supplied) / 50022 (DR ≠ CR) / 50023 (no active leg) / 50040 (token unresolved) / 50041 (account not in COA); `THROW;` re-throws the real error; MIRROR = GROSS kept; number taken after the checks. Extra finding: `SELECT @var = …` with no match kept the previous leg's value, so a missing amount type / flag / token silently reused the previous leg's amount / flag / account (old writer posted DR AR / CR AR for SVC-REVENUE with one token). Mapping: 17 PV-AP rows (bank leg NET, discount legs DISCRETALLOW, FX legs 60323), backup `JournalEntryMapping_PVAP_Backup_20261014`; V2 / old Compound supply DISCRETALLOW and treat a return allowance like a discount. Exception Center G03 (all modules) = 0 on all three databases. Tests: 37 old-vs-new regressions identical for 15 caller mnemonics (+ ledger rows), 8 refusals, 6 V2 purchase payments end to end. DEV ✅ 18:14; STAGING ✅ 18:18 (user-approved; same tests on the live procs, Exception Center 19 / 19 = 0); PRODUCTION by the user, then `DONE (Fable)` after the read-only check.

### H2. AR payment reversal can mirror another document's tickets (Tier A)

- **Problem.** `sp_ReversePaymentClient` mirrors every `TicketMaster` / `TicketDetails` / `ClientLedger` row
  `WHERE ReferenceNumber = @refno`. Sales tickets keep the PO number in that same column, from a different counter.
  When the numbers meet, reversing a payment also reverses another customer's sales ticket and ledger row.
  *(PROD 10-14: not scoped; 0 OR payments share a reference with another ticket today; DEV had 34, so it is a matter
  of time.)*
- **Hardening.** Scope tickets to the payment's own mnemonics (`OR-%`) and the ledger to `AccountKey = @custkey AND
  TransCode LIKE 'OR-%'`; refuse (new code) when the scoped set is empty or touches a second customer. Same review for
  every other reversal proc that selects by `ReferenceNumber` alone (search the Atlas).
- **Acceptance.** Rolled-back test on DEV with a forced collision: only the payment's rows mirrored; the normal reversal
  produces identical rows to today's. Exception Center check: "reversal rows whose source is not a payment" = 0.
- **Note (ERP session, 2026-10-14):** [79] (AR balance-forward credits, user's go on DEV) patches `sp_AddPaymentClient`, `sp_ReversePaymentClient` and `splist_ARAccounts`: credit-line rules under UPDLOCK, credits-only payment with no ticket, PayStatus keeps a part-used credit open. Behaviour for ordinary invoices unchanged. Rebase on the patched text (marker `[79]`) when this item is taken.
- **Note (ERP session, 2026-10-14, [80]):** the invoice-row part of this item is done: `sp_ReversePaymentClient` now matches `TransactionChargeSales` by InvoiceNo + PONumber + customer (it moved other rows of the same invoice no. on PRODUCTION: C-048113, E2608-01-A), and the Edit pre-fill in `ClientPaymentsDevExAcctg` finds the row by invoice no. AND PO. Exception Center S06 watches it. Still open here: the ticket / ledger mirroring by `ReferenceNumber` alone.
- **Result (Fable, 2026-10-14):** script `[85]-2026-10-14k_H2_H4_ARReversalScope_AtomicWrappers_STSReceive.sql` (with H4). `sp_ReversePaymentClient` (anchor patches of the [84] text) mirrors only the payment's own ticket (Mnemonic 'OR-%', or no mnemonic with ReferenceKey = the reference, the 33 tickets of 08-01..05 on every tier; never a REVERSED one), its lines by that ticket number, and the ledger rows by AccountKey = the customer AND TransCode 'OR-%'; refusals 60002 (more than one payment ticket under the reference), 60004 (the customer's ledger rows of the payment point at a ticket other than the one mirrored: a missed own ticket would otherwise reopen the invoices with no GL reversal; sp-reviewer) and 60003 (post-check: the reversal mirrors the payment ticket's lines and balances). Measured first (read-only, all tiers): no reversal had mirrored anything yet (0 reversal tickets with two masters, 0 reversal ledger rows on another customer); PRODUCTION has 25 live payments of 08-01..05 (508,036.75) whose reference is also the PO number of another customer's SI ticket (STAGING 26, DEV 22). **What the old text really did on one of those:** the two mirrored masters get the same TicketDate / branch 888 / reversal ticket number, so the `TicketMaster` primary key refuses the whole reversal with 2627 (shown on DEV payment 4262 and STAGING 4266); the silent mirroring would only happen for a payment with no ticket of its own (none live on PRODUCTION / STAGING). The reversals of those 25 payments are therefore blocked today and work after [85]. Reviewed and left alone: `sp_ReverseTicketsAP` (ReferenceNumber + ReferenceKey = voucher id: only the voucher's own SINGLE-PAY / EXP-ACCRUAL-PAY / VOUCHER-MANUAL / PV-AP tickets sit under that pair on all tiers), `sp_ReverseCashAdvanceEntry` (ticket number), `sp_ReverseApprovedExpense` (+ ReferenceKey), `sp_CancelApprovedServiceOrder` (+ Mnemonic), `spu_Loan_ReverseRevaluation` (ticket number + branch), `sp_CancelledChequesCS` (supplier + reference). Exception Center **G04** = 0 on DEV / STAGING / PRODUCTION. Tests on DEV: old vs new identical rows on a normal payment (EWT, 6900); 4262 with the new text: one master, two lines balanced, ledger on 00001191 only, sales ticket 14662 untouched; 60002 fires and leaves the header POSTED. DEV ✅ 21:43; STAGING ✅ 22:06 (user-approved; the test script `SQL/[85]-2026-10-14k_H2_H4_Test.sql` passes there and on DEV); PRODUCTION after [84] (its `sp_ReversePaymentClient` is still the pre-[84] text, the guard stops [85] until then).

### H3. Error-handling standard (Tier A, a prerequisite for H4)

- **Problem.** Named rollbacks and unguarded `ROLLBACK` mask real errors: V2's `ROLLBACK TRANSACTION PaySupplierV2`
  (6401 when nested), and `sp_AddPaymentSupplierCompound*`, `sp_AddPaymentClient`, `SP_CONFIRMPO`,
  `sp_ReversePaymentClient`, `SP_UPLOADINVENTORY` turn the period-lock refusal (59900) into "no BEGIN TRANSACTION".
  `RAISERROR(@msg)` re-throws as 50000.
- **Hardening.** One pattern for every posting proc: `SET XACT_ABORT ON`; `BEGIN TRY / BEGIN TRAN … COMMIT`;
  `CATCH: IF XACT_STATE() <> 0 ROLLBACK; THROW;`. Nested-safe (works whether or not the caller has a transaction).
  Write it into `docs/standards/` and convert the listed procs (anchor patches; behaviour otherwise unchanged).
- **Acceptance.** Each converted proc: success path identical (rolled-back old vs new); a forced 59900 surfaces as
  59900; called inside an outer transaction, no 6401.
- **Note (ERP session, 2026-10-14):** [79] (AR balance-forward credits, user's go on DEV) patches `sp_AddPaymentClient`, `sp_ReversePaymentClient` and `splist_ARAccounts`: credit-line rules under UPDLOCK, credits-only payment with no ticket, PayStatus keeps a part-used credit open. Behaviour for ordinary invoices unchanged. Rebase on the patched text (marker `[79]`) when this item is taken.
- **Result (Fable, 2026-10-14):** standard `docs/standards/2026-10-14_Posting_Proc_Error_Handling.md`; script `[84]-2026-10-14j_H3_PostingProcs_ErrorHandlingStandard.sql` (needs [83]). Converted: `sp_AddPaymentSupplierCompound_V2` / `_Compound` (unnamed transactions), `sp_AddPaymentClient` / `sp_ReversePaymentClient` (TRY/CATCH, 17 guard ROLLBACKs removed), `SP_POSTINVENTORY` / `sp_FinalizeInventoryUpload` (transaction first: the Inventory rebuild ran outside it and before the "already finalized" check, so a second click wiped the live lots and kept the damage; RAISERROR+RETURN → THROW 50061 / 50062; real error re-thrown), `sp_PostCompoundTicket` / `Sales` (no DDL in the CATCH: the DROP in the doomed transaction raised 3930 over 59900). Not converted: `SP_UPLOADINVENTORY` (no caller) and `SP_CONFIRMPO` (its 2019 text no longer compiles, 213; unused): retire both. Measured on DEV: nested refusal 6401 → 60507; month closed nested 6401 / 3930 → 59900 everywhere; finalized shipment re-posted 50000 → 50061 with nothing changed; 36 old-vs-new success rows identical. DEV ✅ 18:44; STAGING ✅ 18:54 (user-approved; same suites on the live procs); PRODUCTION by the user ([83] then [84]), then `DONE (Fable)` after the read-only check.

### H4. Multi-step postings that are not atomic (Tier A)

- **Problem.** *(PROD 10-14, all still so.)*
  - `sp_PostSupplierPaymentWithManualLines`: V2 commits the invoice payment, then the manual lines run separately; on
    failure it says "already posted … do not re-run" (60299). A half-posted voucher has cheque ≠ GL.
  - `sp_ReverseCombinedSupplierVoucher` has no transaction.
  - STS receive screens make 3 separate calls from C# (receive → confirm → GL).
- **Hardening.** One outer transaction per business action (after H3, so the inner procs nest safely), or move the
  orchestration into one proc. C# keeps one call per action.
- **Acceptance.** Rolled-back tests that force a failure in the last step: nothing of the earlier steps remains.
- **Result (Fable, 2026-10-14):** script `[85]` (with H2). `sp_PostSupplierPaymentWithManualLines` and `sp_ReverseCombinedSupplierVoucher` recreated as one transaction each (backups `_OLD_10152026003000`): the invoice leg no longer commits before the manual lines run, and a refusal of the manual leg (60301 / 60302) no longer leaves the invoice leg reversed; 60299 ("already posted, do not re-run") is gone, the real error surfaces. STS receive: new `dbo.spu_STS_ReceiveTransfer` (lock -> `spu_PostSTSReceiveFromFIFO` -> `sp_ReverseSTSInventoryTransfer` per unticked line -> `sp_ConfirmBranchRecievedOrderJFC` -> post-check, one transaction; stale screen refused 59624 / 59626, a row sent both ways 59627; new type `tt_STSReceiveReturnRows`; the receive proc hands its skipped lines to the caller's `#STSRcvSkipped`), and `HOFormsDevEx/ReceivedSTSBatchModeFIFO.cs` makes ONE call (built 21:41; an old exe keeps working on the three unchanged procs). The legacy `ReceivedSTSBatchMode` screen is not converted: its grid function `funcview_DeliveryDetailsForReceiving` does not exist on DEV, STAGING or PRODUCTION, so it fails on open (candidate to retire). Tests on DEV, live procs: old vs new identical rows for a combined CHECK voucher (expense 32629 + 1,000 manual line: cheque 26,000 = bank credits), for its reversal, and for the STS receipt of 13682 (full, partial with 2 rows returned, all returned) and 13725 (one grouped row of 6 lines); forced failure in the last step (manual line on an account not allowed 60103; cash advance partly liquidated 60302; IT-BR-VATEX mapping off 50030): the new procs leave nothing and `@@TRANCOUNT` = 0 on the caller, the old paths leave the first leg committed (shown); refusals 59622 / 59623 / 59624 / 59626. Exception Center **T06** (received rows on a transfer not DELIVERED) = 0 on DEV / STAGING / PRODUCTION. DEV ✅ 21:43 (test fixtures removed, DEV restored); STAGING ✅ 22:06 (user-approved; test script `SQL/[85]-2026-10-14k_H2_H4_Test.sql`, summary + UI steps `docs/handoff/2026-10-14_85_H2_H4_Changes_and_Tests.md`); PRODUCTION after [84]; the new exe for the STS receive screen.

### H5. Client-supplied amounts and balance formulas (Tier A)

- **Problem.** Known Bug #10 is fixed only in `sp_PostVoucherManual`. Elsewhere the settled amount comes from the
  screen:
  - `sp_AddPaymentSupplierCompound_V2` (expense SINGLE / multi-branch, purchase);
  - `sp_AddPaymentClient`, which also recomputes `Balance = TotalAmount − (AmountPaid + EWT + Discount + Offset)`
    *(PROD 10-14)*. Any invoice whose Balance was set directly (balance-forward loads; fixed once by [43]) is silently
    reset by its next payment;
  - credit memo, return and cash advance: not audited yet for this pattern (check them as part of this item).
- **Hardening.** Re-read every invoice balance under `UPDLOCK`; refuse when the client's balance is stale (new code)
  rather than settling against it; make balance updates incremental, or assert `Balance = TotalAmount − components`
  before applying and refuse otherwise.
- **Acceptance.** Rolled-back two-session test (load the grid, pay the same invoice elsewhere, submit) is refused;
  the normal path is identical. Exception Center: AP-INVOICE-VS-LEDGER (AP) and an AR equivalent (invoice balance =
  client ledger) stay 0.
- **Note (ERP session, 2026-10-14):** [79] (AR balance-forward credits, user's go on DEV) patches `sp_AddPaymentClient`, `sp_ReversePaymentClient` and `splist_ARAccounts`: credit-line rules under UPDLOCK, credits-only payment with no ticket, PayStatus keeps a part-used credit open. Behaviour for ordinary invoices unchanged. Rebase on the patched text (marker `[79]`) when this item is taken.
- **Result:** _

### H6. Lookups that pick the wrong record (Tier A, C#)

- **Problem.** `SearchLookUpClass.getSingleValue` reads the popup's focused row, not the picked one: the first pick
  after load can return another row. It has 131 calls in 55 files (10-14). Combined with a non-unique `ValueMember`
  (e.g. customer name: 938 customers share names), a payment or order can post to the wrong party with no error.
  Fixed so far only in `ClientPaymentsDevExAcctg` (CustomerKey + `EditValue`).
- **Hardening.** Fix the helper centrally (read `EditValue` / `GetSelectedDataRow()`), then audit every lookup's
  `ValueMember` for uniqueness (composite keys as in Known Bug #7) and `TextEditStyle = DisableTextEditor`
  (Known Bug #2). Posting screens first: payments, orders, expenses, vouchers.
- **Acceptance.** Harness or UI check per converted screen: the first pick after load returns the picked row; a
  duplicate-name pair resolves to the right key. Hand the list of converted screens to the user for a UI pass.
- **Result:** _

### H7. Bank recon loopholes (Tier B)

- **Problem.**
  - `sp_Payment_PostBankReconEntry` silently does nothing on a second call with the same (ReferenceNo, AccountCode,
    ItemType) (Known Bug #9). A caller that posts two amounts loses the second with no error.
  - JV and multi-branch expense **edits** delete and re-post their recon rows, so a cleared item comes back open.
  - `sp_PostSupplierPaymentWithManualLines` updates an OC amount without checking cleared / locked.
  - `sp_BankRecon_DeleteItem` / `SaveItem` have no period-lock check.
  - `sp_BankRecon_AutoMatch` (clears outstanding cheques from their own GL credit, not the bank) is still installed
    *(PROD 10-14)*; only its buttons are hidden.
- **Hardening.** Make the helper refuse (or return a status) when a second call would change the amount; keep a cleared
  item cleared across an edit (update in place, or refuse the edit once cleared); lock checks on every recon writer;
  drop or hard-disable Auto-Match (user decision).
- **Acceptance.** Rolled-back tests per case; the 13 `BRC-*` portal checks unchanged on DEV / STAGING.
- **Result:** _

### H8. Broken cross-references and racy sequence numbers (Tier B)

- **Problem.**
  - `spu_PostExpenseV2` writes `SupplierLedger.TicketReference` from a second `GetTicketNumber` call, so the ledger
    points at a ticket that doesn't exist (and burns a number). *(PROD 10-14: 389 SNGLE rows.)*
  - `sp_PostExpenseManualMultiBranch` gets one ticket number for all branches; its edit proc gets one per branch.
  - `func_getLastID` takes the max seq per supplier under `NOLOCK` *(PROD 10-14)*, so concurrent postings can reuse a
    sequence.
- **Hardening.** Use the posted ticket's own number (plus a backfill of the 389 rows from `ExpenseMaster.TicketReference`);
  decide one rule for multi-branch numbering (user); sequence under lock or a SEQUENCE / identity.
- **Result:** _

### H9. Period lock covers the GL only (Tier B, before the first month is closed)

- **Problem.** No month is closed yet *(PROD 10-14)*. When one is, the triggers stop GL tickets only: supplier / client
  ledgers, stock movements, recon items and expense / invoice tables can still be written or deleted for that month
  (delete-and-repost edits included), so a closed month's subledgers can drift from its GL.
- **Hardening.** Decide with the user which tables follow the lock; add the same trigger pattern (lock row read
  `WITH (HOLDLOCK)`), or a shared check in the writers. Mind the reversal rule (a reversal is dated in its source
  month and is refused when that month is closed).
- **Result:** _

### H10. String-built SQL in C# (Tier B, incremental)

- **Problem.** About 498 `INSERT` / `UPDATE` / `DELETE` statements are built by string concatenation (10-14 count;
  most in `HOFormsDevEx`, `HOForms`, `POS`, `HotelManagement`, `Orders`). Posting and approval paths are known cases:
  order approval / reject / invoice-number updates, `ViewLinkedPODetailsFrm.LoadLines`. CLAUDE.md rule 2 requires
  parameters.
- **Hardening.** Convert the posting / approval paths first (parameterized `SqlCommand`, or move into a proc); leave
  scratch folders alone (rule 4).
- **Result:** _

### H11. Swallowed exceptions that report success (Tier B, C#)

- **Problem.** 26 empty `catch {}` blocks (10-14 count). `HOFormsDevEx/CreditMemoDevEx` shows "Payment Successfully
  Posted" after a swallowed SQL error (the same bug was fixed in `ReturnSalesOrder`).
- **Hardening.** A success message only after the commit returns; failures show `ex.Number` + message; review the 26
  blocks, posting screens first.
- **Result:** _

### H12. Zero-value and zero-cost edge cases (Tier C)

- **Problem.** `spu_SO_PostInvoiceReduction` returns early when the gross is 0, so a zero-priced line's return puts
  the stock back but never reverses its cost. Conversion output lots carry cost 0, so their sales post 0 COGS. POS V2
  restocks at the sale-time cost while `spu_InvFIFO_Restore` may value the ledger at the current cost.
- **Hardening.** After an accountant decision on each: cost-side legs posted independently of the sales amount; a
  costing rule for conversion output.
- **Result:** _

### H13. Trust model (Tier C, design)

- **Problem.** Every proc takes `@User` from the client over one shared SQL login, so approvals, period reopen, POS
  supervisors and audit columns trust whatever the exe sends. POS V2 narrowed it (approver checked per branch,
  SUSER_SNAME / HOST_NAME logged).
- **Hardening.** A design note with the user before code (per-user logins, `SESSION_CONTEXT` set once per connection,
  or v2's own auth). v2 must not inherit the gap.
- **Result:** _

---

## 5. Suggested order

H1 → H3 → H2 → H4 → H5 → H6, then the user picks among H7–H13. H1 and H3 change shared plumbing that H4 / H5 build
on; H2 is small, and its failure mode (another customer's sales reversed) is the most damaging. Before starting an
item, send the user the scope (procs / forms touched, tests planned) and wait for the go, as the ERP session does.
