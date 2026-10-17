# Exception Center

Read-only health checks for the money and stock flows that must never drift.
Every check returns rows **only when something is wrong**, so a healthy database
shows `Found = 0` on every line.

| Script | Covers |
|---|---|
| `SO_STS_ExceptionCheck.sql` | Sales Order (place → process → cancel → confirm → credit memo → return) and STS (save → return → receive) |
| `POSV2_ExceptionCheck.sql` | POS V2 (shift GL ticket balanced / booked once / AR leg; shift cost vs lots; void restock; POS charge invoice vs sale and client ledger; customer credit 20115; BIR: VAT split vs net, grand-total chain; work lists: review flags, open shortages, long shifts, OR gaps). Checks P01-P15; a healthy database shows 0 on CRITICAL / HIGH. The work lists without a "done" marker look back `@SinceDays` (45). Run after any POS V2 proc change and daily once terminals sell. |

## How to run

1. Open the script in SSMS, connected to the database you want to check
   (`COREX001` = DEV, `CORECSJFC2026_STAGING` = STAGING).
2. Execute. Nothing is written; it only uses temp tables.
3. Read result set 1 (one line per check: Found, what it means, what to do),
   then result set 2 (the PO / lot / ticket behind each exception).

Run it:
- after every change to a Sales Order or STS procedure (DEV first, then STAGING after deploy);
- daily while the system is new, then weekly;
- whenever someone reports a stock or balance that looks wrong.

## Checks

| Code | Severity | What it catches |
|---|---|---|
| X01 | CRITICAL | Cancelled / returned line still holds stock from a lot: the stock never went back to the source branch |
| X02 | CRITICAL | Qty put back by a cancel / return differs from what was taken / billed (stock ledger) |
| X03 | CRITICAL | Lot `Available` below 0 or above `Quantity` |
| X04 | INFO | A sold / shipped lot's cost changed after the sale (cost finalized later) |
| X05 | CRITICAL | A partly returned sales line's live lot qty differs from its delivered qty (bad split; lines listed in `SalesReturnLog`, 2026-10-04) |
| S01 | CRITICAL | Confirmed order without exactly one invoice, or without a sales ticket |
| S02 | HIGH | Invoice `Balance` doesn't follow its own columns (the next payment will compute it wrong) |
| S03 | HIGH | Order's AR in the GL (sale − credit memo − return) ≠ invoice |
| S04 | HIGH | Sales ticket cost of sales ≠ invoice COGS rows |
| S05 | MEDIUM | Order and delivery header disagree on DELIVERED (a delivery fully returned before confirm, never invoiced, is valid and not flagged) |
| S06 | HIGH | Invoice no. with several rows: a row's paid amount differs from its own payment lines (script [80]) |
| S07 | HIGH | A customer's account balance differs from the sum of its invoice balances (script [87]) |
| S08 | HIGH | An invoice row's `Balance` doesn't follow its own columns, all rows and dates (script [87]) |
| S09 | MEDIUM | A sales-order delivery's `DeliverySummary` counters (items / sold / returned / qty / actual qty) differ from its lines (script [89]; most rows before [89], 0 after) |
| S10 | HIGH | An AR payment's Other Collections lines (`PaymentType 'OTHER COLLECTION'`, script [104]) are not carried by its own OR ticket, or a line is linked to an invoice (PONumber other than `#OTHER`) |
| S11 | HIGH | A CR recorded as cancelled (`CancelledCollectionReceipt`, script [110]) is also on a live AR payment of the same branch (customer's branch, same series + number). Skipped until [110] is installed |
| T01 | CRITICAL | Saved transfer: head-office In Transit ≠ cost of the stock actually shipped |
| T02 | CRITICAL | Received transfer: In Transit did not clear to 0 |
| T03 | CRITICAL | Transfer received more than once |
| T04 | HIGH | Received status and receipt ticket disagree |
| T05 | CRITICAL | A multi-lot line was received as exactly one lot's qty (receive-screen bug fixed 2026-10-02) |
| T06 | HIGH | Branch received rows on a transfer that is not DELIVERED: the receipt was never confirmed (the three receive steps are one transaction since [85], 2026-10-14) |
| G01 | CRITICAL | Sales / STS ticket out of balance (DR ≠ CR) |
| G02 | HIGH | VAT ticket posted after the all-VAT-exempt rule (2026-10-02) |
| G03 | CRITICAL | A GL ticket of any module out of balance, all dates (the compound writers refuse it since [83], 2026-10-14) |
| G04 | CRITICAL | An AR payment reversal mirrored another document under the same reference: a second master on the reversal ticket, or a reversal ledger row on another customer (scoped since [85], 2026-10-14) |

## Dates

- `@FromDate` (default 2026-10-02, the first full day on the 2026-10-01 fixes) limits the
  money checks. Older history has known gaps from the old procedures; widen it only on purpose.
- `@StsFromDate` (default 2026-08-01) for the In Transit checks: money stuck in transit matters
  whenever it started.
- X01 and X03 always cover everything.

## Adding a check

When a new failure mode is found: add it to the script under its group (X stock, S sales,
T STS, G GL) with the next free code, add its line to the `@Info` table, list it above,
and note it in `docs/CLAUDE_WORKLOG.md`. Check a new rule against DEV and STAGING and
confirm every hit is real before relying on it (a check that cries wolf gets ignored).

## Bank Recon: GL vs recon items (`BankRecon_GLvsRecon_Check.sql`)

A separate read-only script, run before each month's bank reconciliation. For every
cash-in-bank account it matches each GL reference posted since 2026-08-01 with its
Bank Recon item (DIT / OC) and lists every recon period with its figures.
Set 1 = per account, set 2 = exceptions (should be empty), set 3 = recon periods.
Codes: GL ONLY (bank moved, nothing to tick), RECON ONLY (item without GL),
AMOUNT DIFFERS (e.g. Known Bug #9), OTHER MONTH (item filed under another period).
Set 6 (added by [88], hardening H7): items of a LOCKED month added, changed, cleared or uncleared
after the lock (every recon writer refuses a locked month since [88]; a row here came from a hand
edit or an older exe). Should be empty.
Set 7 (added by [101], 2026-10-17): a bank item still ticked CLEARED although its document (AR
payment, cash advance, supplier voucher) was reversed. The reversals void open items only, so the
re-keyed document's new item gets ticked too and the bank side counts the money twice (PRODUCTION
O-CR-011241, refs 38760 -> 45337). Since [101] an AR payment with a cleared deposit can't be reversed
(93030); since [103] a cash advance (93031) and a supplier voucher / cheque (93032) with a cleared
item can't either. Fix a row by setting its ResolvedReason to 'REVERSED' (as [101] did). Should be empty.
