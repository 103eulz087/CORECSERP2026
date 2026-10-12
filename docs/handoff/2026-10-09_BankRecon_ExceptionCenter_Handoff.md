# Handoff: Bank Recon checks → Web Exception Center

**From:** CORECS ERP (WinForms, `AccountingDevEx/BankReconFormV2.cs`)
**To:** the ASP.NET Core + Blazor web reporting tool, its Exception Center (`sp_rpt_ExceptionCenter_Summary` / `_Detail`, `dbo.ExceptionDefinition`)
**Date:** 2026-10-09
**SQL to use:** `docs/handoff/2026-10-09_BankRecon_ExceptionCenter_Checks.sql`. It has four marked parts: the function, the definitions, the Summary blocks and the Detail blocks. All of it is tested; see section 6.

---

## 1. Why

The ERP's Bank Recon compares, per bank account and month, the bank statement with the GL:

```
Adjusted Bank = Bank Statement Balance + open Deposits in Transit (DIT) − open Outstanding Checks (OC)
Adjusted Book = GL Book Balance (all branches) + open Bank Credit Memos − open Bank Debits
Difference    = Adjusted Bank − Adjusted Book        (0 = reconciled)
```

Accountants clear (tick) items until the Difference is 0. A reconciliation can be blocked for two kinds of reasons:
- **The month can never reach 0.** A bank movement has no item to tick, an item has the wrong amount, an item is filed under the wrong month, or there is a duplicate.
- **Nobody can tell why it doesn't reach 0.**

On 2026-10-08/09 the ERP developer found several real cases on production by matching the GL against the recon items:
- a duplicate fund transfer of 1.29M;
- 11 cheques filed under the wrong month (2.47M);
- a Manual JV that lost 5 of its 6 bank lines (Known Bug #9);
- 16 voided items hidden from their own month (14.87M).

Each case was fixed or sent to the accountants with **the likely cause and exactly what to verify**. The user wants that, permanently, in the Exception Center: each check shows the likely causes and the rows to verify, so staff can go straight to the problem.

---

## 2. What to build

A new category **"Bank Recon"** with 13 checks (`BRC-*` codes, sort order 70–82), in the same shape as the existing checks:

| Piece | Where | Notes |
|---|---|---|
| `dbo.fn_rpt_BankRecon_GLvsRecon()` | new inline table function (part 1 of the SQL) | Read-only. One row per bank account + reference: GL movement vs recon items, with a `Result` code. Shared by four checks. |
| 13 `ExceptionDefinition` rows | part 2 | Category `Bank Recon`, Severity `Critical` / `Warning`, drill route `/ExceptionCenter/Detail?code=…`. |
| Summary blocks | part 3 → `sp_rpt_ExceptionCenter_Summary`, at the "Future checks land here" marker | Uses the proc's existing `@Start`, `@End`, `@StaleAsOf`, `@AsOf`, `#Result`. |
| Detail blocks | part 4 → `sp_rpt_ExceptionCenter_Detail` | `TOP (500)`, typed columns, a `Hint` column on every row. |
| New variable in both procs | `DECLARE @DITStaleDays int = 7;` | Placeholder, like `@StaleDays`. |

Put it in the web tool's next `sql/NN` file, the same way the other checks were added. **Only read ERP tables and functions. Change no ERP object.** `fn_BankRecon_Figures` and the recon tables are shared with the WinForms exe.

---

## 3. What the web tool must know about the data

| Fact | Detail |
|---|---|
| Recon period | `dbo.BankReconHeader`, one row per branch + bank account + `PeriodEnd` (a month end). Every recon file is under branch **888**; the GL side always covers **all branches**. |
| Recon items | `dbo.BankStatementRecon`. `ItemType` DIT / OC are book-side timing items; BCM / BDM / BC / NSF / ADB are bank-side items. `HeaderID` is the period the item belongs to. |
| Link to the GL | `BankStatementRecon.SourceRef` = `TicketDetails.ReferenceNumber` on the same `AccountCode`. `ReferenceNo` is the voucher no. (or payment ref). Bank accounts are `AccountCode LIKE '10102%'`. |
| Cleared | `IsResolved = 1`. Since 2026-10-08 (ERP script 08c) `ClearedPeriodEnd` = the month it was cleared in. An item is **open for month P** when its period ≤ P and it is uncleared **or** was cleared after P. |
| Reversed / voided | `ResolvedReason = 'REVERSED'` or `LIKE 'VOIDED%'`. These are hidden from the recon. |
| Figures | `dbo.fn_BankRecon_Figures(@HeaderID)` gives exactly what the screen shows: `OpenDIT`, `OpenOC`, `OpenBCM`, `OpenBankDebits`, `AdjustedBankBalance`, `AdjustedBookBalance`, `Difference`, `GLBookBalance` (a snapshot once `Status = 'LOCKED'`). **Use it; don't recompute.** |
| Go-live | The ERP GL starts with the opening ticket of **2026-07-31**. July's uncleared items were loaded from Peachtree as `SourceModule = 'BF-PEACHTREE'` (no GL entry of their own, on purpose). GL matching starts **2026-08-01**. |

---

## 4. The 13 checks

For each check: what it means, the likely causes (show these in the UI next to the count), and what the user should verify. Every Detail row also carries a `Hint` with the row-specific cause.

| Code | Sev. | Means | Likely causes | What to verify | ValueAtRisk |
|---|---|---|---|---|---|
| **BRC-GL-NO-RECON-ITEM** | Critical | The bank account moved in the GL, but there is no DIT / OC to tick. That month can **never** reach 0. | A posting proc didn't call the recon helper; a module that posts to the bank without creating items; a manual ticket. | Open the GL ticket: was it a real bank movement? Then the item must be created (ERP fix). | \|GL amount\| |
| **BRC-AMOUNT-MISMATCH** | Critical | The item's amount ≠ its GL entry. | Several GL lines, one item: lines after the first dropped (**Known Bug Pattern #9**); gross vs net cash; an item edited by hand. | Compare the GL lines with the item; the `Hint` says which pattern. | \|GL − item\| |
| **BRC-RECON-NO-GL** | Warning | An item has no GL entry on that bank account. | A duplicate entry; posted to a different bank account; a voucher without its ticket. | Find the payment / voucher; check which bank account the GL used. | \|item\| |
| **BRC-DUP-RECON-ITEM** | Warning | The same reference twice on an account, or an item with no GL that is a twin (same account, type, amount, date) of another item. | The same transfer entered twice (e.g. two cash advances for one fund transfer); a re-post. | Keep the one with the GL entry; the other is voided in the ERP. | item amount |
| **BRC-WRONG-PERIOD** | Warning | The item is filed under a different month than its GL entry, so it is missing from the GL month's list. | The voucher was entered or posted later (back-dated GL, item dated at entry); manual move. | The cheque / deposit date on the voucher; it should sit in the GL month. | \|GL amount\| |
| **BRC-REVERSED-LATER-MONTH** | Warning | Voided / reversed **in a later month** than the original entry, but already hidden in the original month (or filed after it). At the original month end it was a real outstanding item. | Every cross-month void (cheque issued Aug 14, voided Sep 26). This is how the ERP works today; an ERP fix is planned (section 7). | It does **not** appear on the original month's bank statement, and the void date. `DifferenceChange` = effect on that month. | item amount |
| **BRC-CLEARED-NO-REASON** | Warning | Cleared without the screen's reason ('CLEARED'). | **Auto-Match**, which cleared cheques from their own GL entry, not from the bank (hidden in the ERP since 10-08), or an old screen. | Each item against the bank statement; untick if it isn't there. | item amount |
| **BRC-CLEARED-MONTH-INCONSISTENT** | Critical | The cleared flag and the cleared month disagree: cleared with no month, uncleared with a month, or cleared before its own period. | A writer that bypasses the ERP's clear procs (old screens, scripts, direct updates). | Should always be 0; report it to the ERP developer. | item amount |
| **BRC-LOCKED-OUT-OF-BALANCE** | Critical | A locked (closed) month's Difference ≠ 0. | Its figures changed after locking: an item deleted / edited / cleared outside the lock rules. | Report to the ERP developer; a closed month must not move. | \|Difference\| |
| **BRC-PERIOD-OUT-OF-BALANCE** | Warning | A statement balance has been entered but the Difference ≠ 0 (not locked). | Still being reconciled; unticked or wrongly ticked lines; bank charges / interest not entered; posting errors; a Peachtree opening difference. | Read the `Hint`: amount = one item → that item; twice an item → wrong side; divisible by 9 → swapped digits. | \|Difference\| |
| **BRC-NO-STATEMENT-BALANCE** | Warning | The month has ended but its bank statement balance is still 0. | Not started. | Enter the statement balance in Bank Recon. | \|GL balance\| |
| **BRC-NO-OPENING-LIST** | Warning | A bank account had a balance at go-live but no July 31 statement balance / Peachtree outstanding list. | The Peachtree recon for that account was never loaded. Its August can't reach 0, because July's items that cleared in August have nothing to tick. | Get the account's July 31 Peachtree reconciliation; the ERP loads it as a balance forward. | \|opening GL\| |
| **BRC-STALE-DIT** | Warning | A deposit in transit is still open after `@DITStaleDays` (7). | Not ticked yet; deposited to another account; never deposited. | The deposit slip / bank statement. | sum of deposits |

Detail columns are in part 4 of the SQL. Every row has the keys a user needs to find it in the ERP: account, reference, voucher / CV # / control no., check no., dates, ticket numbers, amounts, the item's period and its cleared month.

---

## 5. UI suggestions (these made the 2026-10-09 verification easy)

1. **Show the causes, not just the count.** On the check's card, list the "Likely causes" and "What to verify" from section 4. On each Detail row, show `Hint`.
2. **Verification columns.** Let the user mark each Detail row **Verified Y / N** with a remark, and keep that in a **web-owned** table, e.g. `ExceptionVerification (ExceptionCode, RowKey, Verified, Remarks, VerifiedBy, VerifiedAt)`. RowKey per check:
   - `ReconID` for item checks;
   - `AccountCode + '|' + Reference` for the GL-vs-recon checks;
   - `AccountCode + '|' + PeriodEnd` for period checks.

   Don't write to ERP tables.
3. **Export to Excel**, with the two verification columns, so accountants can work offline. That is what the ERP developer sent them on 10-09 (`docs/reports/2026-10-09_BankRecon_ReversedInLaterMonth_STAGING.xlsx`).
4. **Group the Detail by account,** with sum footers for the money columns (and `DifferenceChange` per account for BRC-REVERSED-LATER-MONTH: that is how much the month's target moves).
5. **Thresholds** (`@DITStaleDays`) as settings, like the other placeholders.

---

## 6. Tested results (rolled back, nothing written)

`@DateFrom = 2026-07-01`, `@DateTo = 2026-10-31`, `@AsOfDate = 2026-10-09`. The function, the definitions insert and both procs' blocks ran inside one transaction that was rolled back. Summary findings = Detail row count for every check (except BRC-STALE-DIT, which is capped at 500 rows).

| Code | STAGING (production copy, 10-08) | DEV (COREX001) |
|---|---|---|
| BRC-GL-NO-RECON-ITEM | 0 | 0 |
| BRC-AMOUNT-MISMATCH | 0 (JV 32412 fixed 10-08) | 0 |
| BRC-RECON-NO-GL | 0 | 2 · 2,588,068.50 |
| BRC-DUP-RECON-ITEM | 0 (voided 10-08) | 2 · 2,588,068.50 |
| BRC-WRONG-PERIOD | 0 (moved 10-08) | 11 · 2,469,007.48 |
| BRC-REVERSED-LATER-MONTH | **16 · 14,868,927.07** | 9 · 7,631,282.94 |
| BRC-CLEARED-NO-REASON | 0 | 0 |
| BRC-CLEARED-MONTH-INCONSISTENT | 0 | 0 |
| BRC-LOCKED-OUT-OF-BALANCE | 0 | 0 |
| BRC-PERIOD-OUT-OF-BALANCE | 4 · 5,876,267.90 | 3 · 3,359,951.60 |
| BRC-NO-STATEMENT-BALANCE | 19 | 20 |
| BRC-NO-OPENING-LIST | 13 · 35,649,277.85 | 13 · 35,649,277.85 |
| BRC-STALE-DIT | 5,759 | 2,638 |

- **DEV proves the checks catch real problems.** DEV never got the 10-08 data fix. Its RECON-NO-GL / DUP rows are the duplicate 1,294,034.25 fund transfer pair (vouchers 627 / 694), and its WRONG-PERIOD rows are the 11 BDO PESO 2 cheques filed under September. Those are the exact cases found and fixed by hand on production.
- **BRC-REVERSED-LATER-MONTH on STAGING** = the 16 items now being verified by the accountants.
- **Timing** on STAGING: the whole Summary ≈ 1.7 s; each Detail 0.1–0.5 s, BRC-STALE-DIT ≈ 2.6 s.

---

## 7. Notes and gotchas

- **BRC-STALE-DIT is noisy until the accountants start ticking.** Nothing was ticked yet on 10-09, so almost every August deposit is "stale". It becomes useful once a month is being reconciled. Consider a default view that hides it, or sort it last.
- **BRC-REVERSED-LATER-MONTH will shrink by itself.** A planned ERP change stamps a reversal's month into `ClearedPeriodEnd` and keeps the item open until then. The check is written for that: it only flags items whose recorded month is earlier than the reversal month, or that are filed after their GL month. After the ERP fix and its backfill, only real problems stay (e.g. GJ 2608-001, filed under September for an August entry).
- **Needs `BankStatementRecon.ClearedPeriodEnd`**, which has been on production since 2026-10-08 (ERP script `2026-10-08c`). Check `COL_LENGTH('dbo.BankStatementRecon','ClearedPeriodEnd')` before deploying anywhere else.
- **The go-live date (2026-08-01 / 2026-07-31) is a literal** in the function and in BRC-NO-OPENING-LIST, on purpose (one company, one go-live). Make it a setting if the tool will serve another company.
- **`'10102%'` = cash in bank** (local and foreign). The USD / EUR accounts' GL is in pesos, while their bank statements aren't; their statement-balance handling is still an open question in the ERP.
- **The ERP's own copy** of the GL-vs-recon rule is `tools/ExceptionCenter/BankRecon_GLvsRecon_Check.sql`. Keep the two in step: if the rule changes, the ERP developer updates both.
