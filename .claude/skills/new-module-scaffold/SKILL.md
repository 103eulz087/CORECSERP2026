---
name: new-module-scaffold
description: Scaffolds a new "no mapping" module for the CORECS ERP (WinForms/DevExpress) — the two-tab New Entry / Posted pattern used across expense, voucher, and JV-style modules. Use when starting a brand new module of this shape, not for one-off form tweaks.
---

# New module scaffold

Use this when the user asks to build a new module that follows the
established "no mapping, auto-post" pattern (e.g. a new expense type, voucher
type, or similar posting screen). This is a procedural skill — follow it
step by step and confirm scope with the user before generating code if
anything below is ambiguous for their specific module.

## Before starting

Ask (or confirm from context) if not already clear:
- What does this module post to (which ledger/table)? Does it need a
  `TicketNumber`, and if multi-branch, confirm shared-ticket-number handling
  is needed.
- Is this module's record shape fixed (Simple Posting) or can it change after
  creation (JV/Expense/Voucher-style)? This determines the Edit strategy.
- Does it need EWT/tax handling, or a Batch vs Single distinction, like the
  Expense modules do?

## Structure to generate

**Form/UserControl:**
- Two tabs: **New Entry** and **Posted**
- Posted tab: grid with View Details, Copy, and Edit actions. Copy and Edit function is for Accounting Module only.
- `LoadData()` as the real initialization entry point; `Load` event handler
  only as a guarded fallback that calls `LoadData()` if not already run
- All grid columns bound to a LookUpEdit MUST set
  `TextEditStyle = DisableTextEditor`
- Use `.EditValue` for underlying IDs, `.Text` only for display strings
- Dropdowns/grids for reference data use the Code-Name display convention
- If the module should match existing look and feel, apply the shared
  `AppTheme` helpers (`StyleCard`, `StylePrimaryButton`, `StyleSecondaryButton`,
  `StyleGrid`, `StyleInput`, `StyleRoot`) and reuse the debit/credit/
  positive/negative color meanings from `AccountingReportsForm`

**Stored procedures, naming convention:**
- `sp_` prefix for read/lookup procs, `spu_` prefix for post/update procs
- Post procedure: self-accumulate net amounts rather than trusting a
  caller-supplied total
- If multi-branch: fetch the shared TicketNumber ONCE outside the per-branch
  loop
- Include a duplicate-post guard
# - Edit procedure:
  # - If shape can change: implement as delete-and-repost under the same
    # ReferenceNo (single transaction: validate → delete → repost), gated so it
    # refuses to run if the record has been touched by payment/other downstream
    # activity (fall back to a reversal SP instead)
  # - If shape is always fixed: a straightforward in-place UPDATE is fine
- Copy action on the Posted tab should carry over the fields that make sense
  to reuse (branch, supplier/party, remarks) but not the reference/ticket
  identity

## After generating

Run the `sp-reviewer` and `ui-form-reviewer` subagents against the new code
before considering the module done, and report back what they found rather
than silently fixing everything.
