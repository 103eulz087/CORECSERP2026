---
name: gl-posting-reversal
description: Adds GL ticket posting to an approval workflow that currently only updates a status column, plus the matching reversal trap for when an approved record is later cancelled. Use for any CORECS ERP module of the shape "approve → should post GL entries, cancel-after-approve → should reverse them" that doesn't have this yet.
---

# GL posting + reversal on approval

This encodes the pattern from any module with GL posting: a module has
an approval flow that currently just flips a status column, and needs real
GL ticket entries on approve, with a matching reversal if an already-approved
record is later cancelled.

## Step 1 — Chart of Accounts selection, if not already present

If the source table doesn't yet have a GL account tied to each record:
- Alter the table to add a `GLCode` column (or equivalent, matching this
  module's naming)
- In the CRUD form, add a `SearchLookUpEdit` populated from Chart of Accounts
  for the user to pick the account at entry time
- Apply the same LookUpEdit rules as everywhere else in this codebase:
  `TextEditStyle = DisableTextEditor`, Code-Name display convention,
  `.EditValue` for the stored code

## Step 2 — Posting logic on approval (SP-side)

Keep the logic in the stored procedure, not the form code-behind — this
is a deliberate choice for this codebase so the posting/reversal rules stay
adjustable in one place.

- Write a posting SP that runs when status moves to Approved. It should:
  - Generate/attach a ticket number (if multi-branch, fetch it once, not
    per-branch — see CLAUDE.md)
  - Insert the GL entries using the record's GLCode and self-accumulated net
    amount (don't trust a passed-in total)
  - Guard against double-posting the same record (check it isn't already
    posted before inserting)

## Step 3 — Reversal trap for cancel-after-approve

- Write a reversal SP that runs when an already-Approved record is cancelled.
  It should:
  - Check whether the posting has been touched by any downstream activity
    (payment, further processing) — if so, block the reversal and require a
    different manual path, don't silently reverse into an inconsistent state
  - If untouched, reverse the exact GL entries created in Step 2 (not a
    guessed opposite entry) — reference the original ticket number
  - Update the status column only after the reversal succeeds, not before

## Step 4 — Review

Once implemented, dispatch `sp-reviewer` on both new procedures before
considering the feature done — this pattern is exactly the risk area it's
built to catch (reversal correctness, dup-post guards).

## Notes

- If the module is multi-branch, confirm the shared-TicketNumber pattern
  from CLAUDE.md is followed.
- Ask before assuming what "downstream activity" means for this specific
  module if it's not obvious from the schema — it differs across modules
  (e.g. AmountPaid > 0 for expenses vs. a different flag elsewhere).
