---
name: sql-deploy-script
description: House template and rules for a numbered SQL deployment script in CORECS ERP (SQL/[NN]-YYYY-MM-DDx_Name.sql) that creates or patches procs, functions, views, triggers, tables or data. Use whenever a change has to reach DEV / STAGING / PRODUCTION as a script — new objects, a full recreate, an anchor patch of a long live proc, a data repair — and before re-applying a script after a review. Covers the guard batch, hash guards, anchor patches, one transaction with NOEXEC between batches, backups, post-check, and the T-SQL traps that broke scripts before.
---

# Numbered deployment script

Every change that reaches a database is one file `SQL/[NN]-YYYY-MM-DDx_Name.sql`. The user runs it on PRODUCTION
in SSMS, often without us watching, so the script must protect itself: refuse the wrong database state, never
half-apply, and say clearly what happened. Start from `template.sql` in this folder.

Read `CLAUDE.md` first (standing rules: no `CREATE OR ALTER`, parameterized SQL, posting-proc error standard,
known bug patterns) and the tsql-sp-authoring skill for the procs themselves.

## Before writing

1. **Claim the number.** Next free number = "Next free script number" in `docs/CLAUDE_WORKLOG.md`. Add the
   work-log row as soon as the script exists and bump the counter. Shared with the Fable session.
2. **Is any object claimed by Fable?** (`docs/handoff/2026-10-14_Hardening_Handoff_to_Fable.md`). Don't patch a
   claimed object; if you must build on top of Fable's pending script, guard on *its* text (the script then requires
   it first) and leave a note under that item.
3. **Measure every tier first** (read-only on PRODUCTION): the objects' current text hashes on DEV / STAGING /
   PRODUCTION (they can differ: PRODUCTION had hand edits, e.g. `sp_rpt_ItemCostingRecon_List` TargetDate), the
   data the change touches, how many rows a guard would refuse. Put the numbers in the header.
4. **Free error codes**: `grep -rhoE "THROW 5[0-9]{4}" SQL | sort -u` around the range you want.
5. **Live text, not the repo copy.** Patch what `OBJECT_DEFINITION` returns on DEV; the repo file may be stale.

## Shape (see template.sql)

```
header comment      what the user asked + their decisions, RULES, dependencies, guard, backups, exe compatibility,
                    web v2 note; measured facts per tier
SET options         XACT_ABORT, NOCOUNT, QUOTED_IDENTIFIER, ANSI_NULLS, LOCK_TIMEOUT 10000
guard batch         open transaction? -> stop | already applied (marker / new object exists)? -> stop (severity 10)
                    | prerequisites missing? -> stop | live text hash <> expected? -> stop     (RAISERROR + SET NOEXEC ON)
BEGIN TRANSACTION
each section        IF @@TRANCOUNT = 0 SET NOEXEC ON;  GO   <section>   GO
post-check          every object carries the marker, every backup exists, data checks -> else ROLLBACK + THROW 59897
COMMIT; SET NOEXEC OFF
```

- **Why `IF @@TRANCOUNT = 0 SET NOEXEC ON` before every batch:** under XACT_ABORT a failed CREATE rolls the
  transaction back and the *later* batches would otherwise run and commit on their own (found in [85]).
- **Hash guard** (whitespace-insensitive, survives SSMS reformatting):
  `CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.X')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)`.
  Take the expected value from DEV *before* applying and check STAGING / PRODUCTION have the same.
- **Backups**: `sp_rename 'dbo.X', 'X_OLD_MMddyyyyHHmmss'` with one suffix per script (unique across all scripts).
  A re-run must not collide: the "already applied" check stops it first.
- **Marker**: put `[NN]` in a comment of every created / patched object; the post-check and later scripts find it.

## Full recreate vs anchor patch

- **Small object or a rewrite** → rename + `CREATE` with the full new text in the script (guard on the old hash).
- **Long live proc, a few lines change** → anchor patch:
  ```sql
  DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.X')), @a NVARCHAR(400) = N'<one exact line>', @cnt INT;
  SET @cnt = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @a, N''))) / DATALENGTH(@a);
  IF @cnt <> 1 THROW 59898, '[NN] X anchor not found exactly once.', 1;
  SET @def = REPLACE(@def, @a, <replacement>);
  EXEC sp_rename 'dbo.X', 'X_OLD_...';  EXEC (@def);
  ```
  - Anchors are **single lines**. Stored definitions can be **LF-only** (DEV's are) or CRLF (an SSMS run). For a
    multi-line anchor build both variants (`NCHAR(10)` / `NCHAR(13)+NCHAR(10)`) and use the one that counts 1.
  - Build line endings in the replacement with `NCHAR(13) + NCHAR(10)`; never `CASE … THEN CHAR(13)+CHAR(10) ELSE CHAR(10)`
    (typed char(2): a lone LF comes back as LF + space).
  - **Start every long concatenation with `CAST(N'' AS NVARCHAR(MAX)) +`.** `N'…' + N'…'` is NVARCHAR(4000): the
    replacement text was silently cut mid-line in [97] ("Must declare the scalar variable "@"" from the generated proc).
  - Several anchors on one object: a `@p TABLE (n, Anchor, Repl)` + loop, each counted once (see [97] section 1).
  - Optional readers (installed on some tiers only): patch only `IF OBJECT_ID(...) IS NOT NULL`, skip when the
    marker is already there, and put the same rule in the object's own source script for later installs ([96] / [70]).

## Rules learned the hard way

- **Tables / columns**: `IF OBJECT_ID('dbo.T','U') IS NULL CREATE TABLE …`; `IF COL_LENGTH('dbo.T','C') IS NULL ALTER TABLE …`.
  A new column on a table some proc inserts into *without a column list* breaks that proc: find them first.
- **Table types**: a TYPE created inside a transaction can't be used in it: create it committed in its own batch first.
- **Triggers**: `SET XACT_ABORT ON` inside, so a THROW dooms the caller's transaction even when the caller runs with it OFF.
- **Data repairs**: backup table first (`X_Backup_YYYYMMDD`), change only rows still as found (else SKIPPED / refuse),
  post-check the result, log ProcessedBy 'REPAIR [NN]'.
- **New / patched posting procs** follow `docs/standards/2026-10-14_Posting_Proc_Error_Handling.md`
  (BEGIN TRANSACTION first in TRY, THROW guards, `IF XACT_STATE() <> 0 ROLLBACK; THROW;`).
- **Never trust a caller's total** (Known Bug #5): recompute from what the lines really did ([97] `@GrandTotal`).
- T-SQL traps: `EXEC p @x = @a - @b` doesn't parse (compute first); variable names are case-insensitive
  (`@R` and `@r` collide); `Backup` / `IDENTITYCOL` are reserved as aliases; no subquery inside an aggregate
  (`SUM(CASE WHEN … (SELECT …))` → compute into a variable); a proc called through `INSERT … EXEC` must not roll back
  (3915) and every result set of nested procs lands in the INSERT (the wrapper + sp_PostCashAdvance gave two rows).
- **Anchor inside a line**: an addition inserted *after an anchor that ends mid-line* lands before whatever followed it
  on that line. A trailing `-- [NN] …` comment then swallows it: [96] put its comment before the line's `;` in
  `sp_rpt_ItemCostingRecon_List`, so the terminator now sits inside the comment (harmless only because an UPDATE
  follows). Anchor the whole line including its `;`, or put the marker in `/* [NN] */` instead of `--`.
- **Compatibility**: say in the header whether the old exe still works and whether the new exe *needs* the script;
  prefer optional parameters / TVPs so the old exe keeps working (web v2 shares the database).

## After writing

1. `sp-reviewer` on the script (and `ledger-integrity-auditor` when it posts to a ledger); take or answer every point.
2. Rehearse on DEV rolled back, apply, test, then the staging-rollout skill for STAGING / PRODUCTION.
3. If a review changes an applied script: undo on DEV (drop new objects, rename the backups back, hash-check the
   originals), then re-apply the corrected file. Keep new tables that already hold real rows ([96] on STAGING).
4. Work-log row: what / why / rules / guard / backups / exe, per-tier cells; Atlas rebuild + republish when the SQL
   surface changed.
