# Standard: error handling and transactions in posting procedures

**Written:** 2026-10-14 (hardening item H3, script [84]). **Applies to:** every stored procedure that writes a business
record (GL tickets, ledgers, stock, invoices, payments, recon items), in the WinForms exe and in web v2, which share the
database. **Why:** the same database is written by nested procedures (a wrapper calling a poster calling the ticket
writer), by screens that open their own `SqlTransaction`, and by triggers that refuse writes (the GL month lock, 59900).
A procedure that handles errors its own way breaks the one above it: the real error is replaced by a transaction error,
or half of a posting is left committed.

## The pattern

```sql
CREATE PROCEDURE dbo.spu_Example ( ... )
AS
BEGIN
    SET NOCOUNT ON;        -- keep whatever the proc had; not part of this standard
    SET XACT_ABORT ON;     -- any runtime error dooms the transaction instead of continuing on the next statement

    BEGIN TRY
        BEGIN TRANSACTION;             -- FIRST statement inside the TRY: every write is inside it

        -- guards: refuse with THROW only. No ROLLBACK here: the CATCH does it.
        IF <bad input> THROW 5xxxx, 'What is wrong, in the user''s words.', 1;

        -- the writes, nested procs included (they follow this same pattern)

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;   -- 0 = nothing to roll back (already gone), else roll back whatever is open
        THROW;                                        -- the ORIGINAL error number and message, nothing else
    END CATCH;
END
```

## The rules, and what each one prevents

1. **`SET XACT_ABORT ON`.** Without it a statement error inside a proc with no TRY/CATCH continues on the next
   statement and the final COMMIT commits half a posting (`SP_CONFIRMPO` before [84]).
2. **`BEGIN TRANSACTION` is the first statement in the TRY.** Writes before it run in autocommit: `SP_POSTINVENTORY` and
   `sp_FinalizeInventoryUpload` rebuilt the shipment's `Inventory` rows (delete + insert) before opening the
   transaction and before their "already finalized" check, so a repeated call wiped the live lots and kept the damage.
3. **Unnamed transactions only.** `BEGIN TRANSACTION Name` is harmless, but `ROLLBACK TRANSACTION Name` fails with 6401
   when the proc runs inside an outer transaction (the name belongs to the outermost only): the caller gets
   "Cannot roll back PaySupplierV2" instead of the real refusal, and the outer transaction is left doomed
   (`sp_AddPaymentSupplierCompound_V2` / `_Compound` before [84]).
4. **Guards refuse with `THROW` only.** A `ROLLBACK; THROW` guard rolls back the *outer* transaction too when nested, and
   a later `ROLLBACK` by the caller then fails with 3903 "no corresponding BEGIN TRANSACTION", hiding the message.
   Let the CATCH roll back.
5. **The CATCH re-throws with a bare `THROW;`.** `RAISERROR(@msg, 16, 1)` turns every error into 50000 and
   `THROW 50050, 'ERROR SP', 1` loses the message; screens and the Exception Center need the original number (59900 for
   the month lock, 60507 for an unknown supplier, 50022 for an unbalanced ticket).
6. **`IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;`, never a bare `ROLLBACK`.** After XACT_ABORT the transaction may be
   gone already (state 0); a bare ROLLBACK then raises 3903 on top of the real error.
7. **No `RETURN` out of an open transaction.** A guard that returns leaves @@TRANCOUNT raised (error 266, an open
   transaction on the connection). Use THROW.
8. **Cursors are `LOCAL`.** A global cursor left open by an error blocks the next call ("a cursor with the name … already
   exists"); if a proc must keep a global one, the CATCH closes and deallocates it before THROW.
9. **Error numbers:** each proc owns a range (see the work log); messages say what is wrong and what to do, in plain words.
10. **One transaction per business action ([85], hardening H4).** When a business action needs several posting procs
    (an invoice leg + manual lines, receive + return + confirm), a wrapper proc opens the transaction and calls them;
    the screen makes ONE call. A screen that calls the procs one by one commits each on its own, and a failure in a
    later step leaves the earlier ones posted (`sp_PostSupplierPaymentWithManualLines`, `sp_ReverseCombinedSupplierVoucher`
    and the STS receive screen before [85]). The inner procs nest safely because of rules 3-6.
11. **Rows a nested proc hands back to its caller go through a temp table the caller created**, never `INSERT ... EXEC`:
    a `ROLLBACK` inside a proc run by `INSERT ... EXEC` raises 3915 over the real error, and the portal's dispatcher
    skips providers for the same reason. `spu_PostSTSReceiveFromFIFO` writes its skipped lines into `#STSRcvSkipped`
    when the caller (`spu_STS_ReceiveTransfer`) created it, and returns them as a result set otherwise.
12. **Bank reconciliation items ([88], hardening H7).** Every outstanding-cheque (OC) / deposit-in-transit (DIT) item is
    written through `sp_Payment_PostBankReconEntry`, ONE call per reference + bank account + side with the cash movement
    already added up (Known Bug #9). The helper keeps one item per (ReferenceNo, AccountCode, ItemType): the same posting
    again is a no-op, another amount or another document under that key is refused (93021), a LOCKED reconciliation
    month is refused (93022). **A locked month at or after the item's month counts**: an open item carries forward
    into every later month, so a July item changes a locked August (the range `sp_BankRecon_ResolveItem` already
    uses); read the headers `WITH (HOLDLOCK)`. Every writer of `BankStatementRecon` checks that lock
    (`sp_BankRecon_SaveItem` / `_DeleteItem` / `_UpdateItem` 93002, the AR reversal 93028, the cash-advance reversal
    93027) and matches a document's items by `ReferenceNo + SourceModule + SourceRef`, never by `ReferenceNo` alone
    (voucher ids and reference numbers are different counters; the reference counter is shared by every module). An edit that re-posts a voucher
    reconciles its items (`sp_JV_PostBankReconForLines @Mode = 'SYNC'`): a cleared item stays as the bank cleared it
    (else 93023), open items keep their ReconID. Items a document posted are never deleted by hand (60005): reverse
    the document.

## Anchor-patch deploy scripts

Decide an object's line ending with `IF CHARINDEX(CHAR(13) + CHAR(10), @def) > 0 SET @nl = CHAR(13) + CHAR(10); ELSE SET @nl = CHAR(10);`,
not with a `CASE`: a `CASE` whose branches are `char(2)` and `char(1)` returns `char(2)`, so a lone LF comes out padded to
LF + space and every anchor on an LF-only object fails ("anchor found 0 times"). `spu_PostSTSReceiveFromFIFO` (script 34)
is LF-only; every [84] object was CRLF, so [84]'s loop never hit it. Found while writing [85].
   New codes from [84]: 50060 (`SP_CONFIRMPO` no mnemonic), 50061 (shipment already finalized), 50062 (no purchase row).

## Nesting, in practice

- Called alone from a screen: the proc commits or rolls back itself; the screen sees the real error.
- Called inside an outer transaction (a wrapper proc, or a screen's `SqlTransaction`): `BEGIN TRANSACTION` only raises
  @@TRANCOUNT, `COMMIT` only lowers it; on an error the inner CATCH rolls back *everything* (that is the only thing a
  nested proc can do once XACT_ABORT has doomed the transaction) and re-throws. The outer code must therefore also use
  `IF XACT_STATE() <> 0 ROLLBACK` and must expect its `SqlTransaction.Rollback()` to throw "already completed"
  (`ClientPaymentsDevExAcctg` guards it; older screens show that text instead of the real error).
- A refusal is a THROW: inside a test transaction it dooms the whole test. Test refusals one per transaction, and
  capture `ERROR_NUMBER()` / `ERROR_MESSAGE()` into variables before rolling back.

## Checklist for a review

- [ ] `SET XACT_ABORT ON` present
- [ ] `BEGIN TRANSACTION` is the first statement of the TRY; no write before it
- [ ] no transaction names; no `ROLLBACK` outside the CATCH; no `RETURN` inside the transaction
- [ ] CATCH = `IF XACT_STATE() <> 0 ROLLBACK TRANSACTION; THROW;` (plus cursor cleanup if any)
- [ ] every error number is the proc's own; no `RAISERROR` re-throw
- [ ] a forced 59900 (month lock) reaches the caller as 59900; a refusal inside an outer transaction reaches it with its
      own number and no 6401 / 3903

Converted by [84] (2026-10-14): `sp_AddPaymentSupplierCompound_V2`, `sp_AddPaymentSupplierCompound`, `sp_AddPaymentClient`,
`sp_ReversePaymentClient`, `SP_POSTINVENTORY`, `sp_FinalizeInventoryUpload`. Already on the pattern:
`sp_PostCompoundTicket` / `Sales` ([83]), `spu_Loan_PostRevaluation`, `sp_PostVoucherManual`, the POS V2 procs.
Not converted: `SP_UPLOADINVENTORY` (no caller left; `UPLOADINVENTORY.cs` calls `sp_FinalizeInventoryUpload`) and
`SP_CONFIRMPO` (its 2019 text no longer compiles: a positional `INSERT … VALUES` against a table that has since gained a
column, error 213; the VIEWPO › CONFIRMPO screen therefore fails before writing anything, and its `SERVICESCOST` source is
empty on every tier). Both are candidates to retire with their screens; the new codes 50060 (no services mnemonic) is
reserved but unused.
