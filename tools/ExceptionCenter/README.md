# Exception Center

Read-only health checks for the money and stock flows that must never drift.
Every check returns rows **only when something is wrong**, so a healthy database
shows `Found = 0` on every line.

| Script | Covers |
|---|---|
| `SO_STS_ExceptionCheck.sql` | Sales Order (place → process → cancel → confirm → credit memo → return) and STS (save → return → receive) |

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
| S01 | CRITICAL | Confirmed order without exactly one invoice, or without a sales ticket |
| S02 | HIGH | Invoice `Balance` doesn't follow its own columns (the next payment will compute it wrong) |
| S03 | HIGH | Order's AR in the GL (sale − credit memo − return) ≠ invoice |
| S04 | HIGH | Sales ticket cost of sales ≠ invoice COGS rows |
| S05 | MEDIUM | Order and delivery header disagree on DELIVERED |
| T01 | CRITICAL | Saved transfer: head-office In Transit ≠ cost of the stock actually shipped |
| T02 | CRITICAL | Received transfer: In Transit did not clear to 0 |
| T03 | CRITICAL | Transfer received more than once |
| T04 | HIGH | Received status and receipt ticket disagree |
| T05 | CRITICAL | A multi-lot line was received as exactly one lot's qty (receive-screen bug fixed 2026-10-02) |
| G01 | CRITICAL | Sales / STS ticket out of balance (DR ≠ CR) |
| G02 | HIGH | VAT ticket posted after the all-VAT-exempt rule (2026-10-02) |

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
