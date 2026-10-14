# [85] — H2 (AR reversal scope) + H4 (atomic postings): what changed, how to test

**Date:** 2026-10-14. **Status:** DEV ✅ 21:43 (amended 22:0x), STAGING ✅ 22:06, PRODUCTION ⏳ (run [83] → [84] → [85]; the [85] guard refuses until [84] is there). **Exe:** built 2026-10-14 21:57; the STS receive screen needs it, everything else works with the old exe.

## 1. SQL changes (script `SQL/[85]-2026-10-14k_H2_H4_ARReversalScope_AtomicWrappers_STSReceive.sql`)

| Object | Change | Why |
|---|---|---|
| `sp_ReversePaymentClient` (anchor patches of the [84] text; backup `_OLD_10152026003000`) | Mirrors only the payment's own ticket: Mnemonic `OR-%`, or no mnemonic with ReferenceKey = the reference (the 33 tickets of 08-01..05), never a REVERSED one. Lines are taken by that ticket number. Ledger rows by AccountKey = the customer AND TransCode `OR-%`. New refusals: **60002** more than one payment ticket under the reference; **60004** the customer's ledger rows of the payment point at a ticket other than the one mirrored; **60003** post-check (the reversal mirrors the payment ticket's lines and balances). | `TicketMaster.ReferenceNumber` holds the AR payment reference for OR tickets and the PO number for sales tickets: different counters, and they meet. The old text mirrored every row under the number. On a collision the ticket primary key refused the whole reversal (2627), so 25 PRODUCTION payments of 08-01..05 could not be reversed at all. |
| `sp_PostSupplierPaymentWithManualLines` (recreated; backup) | One transaction around the invoice leg (`sp_AddPaymentSupplierCompound_V2`), the manual lines (`sp_PostCashAdvance`) and the voucher / recon amount update. 60299 ("already posted … do not re-run") is gone; the real error surfaces. Same parameters, same result set, same rows on success. | The invoice leg used to commit on its own; a failed manual line left cheque ≠ GL. |
| `sp_ReverseCombinedSupplierVoucher` (recreated; backup) | One transaction around `sp_CancelledChequesCS`, `sp_ReverseCashAdvanceEntry` and the voucher flags. | It had no transaction: a refusal of the manual leg (60301 / 60302) left the invoice leg reversed and the voucher voided. |
| **new** `spu_STS_ReceiveTransfer` | One transaction: lock `STSTRANSIT:<PO>` → `spu_PostSTSReceiveFromFIFO` (ticked rows) → `sp_ReverseSTSInventoryTransfer` per unticked line → `sp_ConfirmBranchRecievedOrderJFC` (or the non-JFC confirm with `@UseJFC = 0`) → post-check DELIVERED. Refusals: **59620** lock, **59621** no delivery, **59622** already DELIVERED, **59623** nothing sent, **59624** an unticked row's lines changed since the screen was opened, **59625** post-check, **59626** a line of the transfer is neither ticked nor unticked, **59627** a row sent both ways. Returns the skipped lines (SeqNo, Barcode, Reason) as before. | The screen made three calls, each committed on its own; a failed confirm left branch stock received, the transfer FOR DELIVERY and In Transit not cleared (Exception Center T04). |
| **new type** `tt_STSReceiveReturnRows` (DeliveryNo, SeqNo, LineCount) | The unticked rows. | |
| `spu_PostSTSReceiveFromFIFO` (anchor patch; backup) | When the caller created `#STSRcvSkipped`, the skipped lines go there instead of a result set. Called directly (old exe), unchanged. | A nested proc must not be read through `INSERT … EXEC` (its rollback would raise 3915). |

Exception Center (`tools/ExceptionCenter/SO_STS_ExceptionCheck.sql`): **G04** an AR reversal that mirrored another document (second master on the reversal ticket, or a reversal ledger row on another customer / not OR-coded); **T06** branch received rows on a transfer not DELIVERED. Both 0 on DEV, STAGING and PRODUCTION on 2026-10-14.

## 2. C# change (`SalesInventorySystem/HOFormsDevEx/ReceivedSTSBatchModeFIFO.cs`)

Screen: **Orders › STS › Received STS › "Show for Receiving Items (Source Ref Code)"** (the FIFO receive screen).

- `simpleButton2_Click` (Submit) used to call `ReceiveSelectedItems`, `ReturnUnreceivedItems` (one `sp_ReverseSTSInventoryTransfer` per line of each unticked row, after reading its lines) and `ConfirmBranchReceivedOrder`, each on its own connection. Those five methods are replaced by one `PostReceipt(selected, unselected)`.
- `PostReceipt` builds two table-valued parameters from the grid (ticked rows → `tt_STSReceiveFIFOLines` with the edited ActualQty; unticked rows → `tt_STSReceiveReturnRows` with the row's `LineCount`) and calls `spu_STS_ReceiveTransfer` once (`@GroupedRows = 1`, `@Origin = '888'`, `@UseJFC` = company is JFC). The skipped lines come back as before ("SOME LINES SKIPPED"). Any SQL error shows "RECEIVE FAILED … Nothing was posted" and the form stays open; the form closes only after the proc returned.
- Small hardening from the review: a cleared ActualQty / SellingPrice cell is read as 0 instead of crashing on DBNull.
- Not changed: the grid, the row ticking, the confirm dialog, `cancelLineToolStripMenuItem` (unticks a row), the legacy screen `ReceivedSTSBatchMode` ("Show for Receiving Items") — that one fails on open on every tier because its grid function `funcview_DeliveryDetailsForReceiving` does not exist; candidate to retire.

## 3. SQL test script: `SQL/[85]-2026-10-14k_H2_H4_Test.sql`

Run in SSMS on DEV or STAGING (not PRODUCTION). It picks its own fixtures (first result set shows them), runs every test inside `BEGIN TRAN … ROLLBACK`, and ends with one row per test: PASS / FAIL / BUG SHOWN / SKIP (a fixture missing on that database).

| Test | What it proves |
|---|---|
| H2-1 | The OLD proc on a payment whose reference meets a sales ticket is refused by the ticket PK (2627) — the state before [85]. |
| H2-2 | The NEW proc on the same payment: one reversal master, lines balanced, ledger rows on the payer only, the sales ticket untouched. |
| H2-3 | An ordinary payment: OLD and NEW post identical ticket lines, ledger rows and invoice balances. |
| H2-4 | A second payment ticket under the reference → 60002, header still POSTED. |
| H4-STS-1 | The wrapper receives the whole transfer: DELIVERED, receipt rows, one IT-BR ticket, head-office In Transit 0. |
| H4-STS-2 | The IT-BR-VATEX mapping is switched off inside the test so the LAST step fails: no receipt row, no branch stock, no ledger row remains; the transfer stays unreceived. |
| H4-STS-3a..d | Refusals 59624 (stale row), 59626 (row not on screen), 59623 (nothing sent), 59627 (row sent both ways). |
| H4-STS-4 | First row returned, the rest received: stock back on the origin lots, DELIVERED, In Transit 0. |
| H4-AP-1 / 2 | A combined CHECK voucher (open expense + 1,000 manual line) posts as one: cheque = bank credits = expense + 1,000; its reversal voids the voucher, reopens the expense, reverses the cash advance. |
| H4-AP-3 | The manual line uses an account not on the cash-advance list (60103): nothing of the invoice leg remains, the expense is still open. |
| H4-AP-4 | The cash advance is marked partly liquidated so the manual leg of the reversal refuses (60302): no reversal audit, no reversal ticket, nothing half-reversed. |
| leftovers | No TEST85 rows, no open transaction. |

Results 2026-10-14: all PASS on STAGING and DEV (see the work log row [85]).

## 4. UI test (new exe), STAGING

Pick a saved STS transfer waiting at a branch (DEV / STAGING: `SELECT PONumber, BranchCode FROM DeliverySummary d WHERE Status <> 'DELIVERED' AND EXISTS (SELECT 1 FROM TransferOrderSummary t WHERE t.PONumber = d.PONumber)`), log in as that branch.

1. **Normal receipt.** Received STS › right-click the transfer › Show for Receiving Items (Source Ref Code) › leave every row ticked › Submit › Yes. Expect "INVENTORY RECEIVED"; the transfer leaves the list; Inventory Report shows the branch stock; the Exception Center shows T01/T02/T04/T06 = 0 for the PO.
2. **Partial receipt.** Same, but untick one row (or right-click › Cancel Line). Expect the unticked row's stock back at head office (Inventory Report, 888) and the rest at the branch; one IT-BR ticket; In Transit for the PO = 0.
3. **Stale screen.** Open the receive screen for a transfer twice (two users or two windows). Submit the first. Submit the second: expect "RECEIVE FAILED … 59622 This transfer has already been received by the branch. Nothing was posted" and the screen stays open. Nothing is double-received.
4. **Nothing posted on failure.** With an admin on DEV: `UPDATE JournalEntryMapping SET IsActive = 0 WHERE Mnemonic = 'IT-BR-VATEX'`, submit a receipt: expect "RECEIVE FAILED … No active JournalEntryMapping rows …"; the transfer is still FOR DELIVERY with no branch stock. Put the mapping back (`IsActive = 1`).
5. **AR reversal.** Client Payments › Posted › reverse any payment: works as before. On STAGING, reversing payment 4266 (customer 00005637, ref 14252) used to fail with "Violation of PRIMARY KEY constraint 'PK_TicketMaster'"; now it posts one reversal ticket and the customer's own ledger rows only (check the GL Detail Ledger of 101030101 and the customer's ledger).
6. **Combined voucher.** Supplier Payment › an open expense + a manual debit line › post: one cheque for the total. Reverse it in Supplier Voucher Reversal: both legs reversed together. To see the atomic refusal, post with a manual line on an account that is not on the cash-advance list: expect the error, and the expense still open (before [85] the expense was paid and the error said "do not re-run").
