---
name: staging-rollout
description: Checklist and helper scripts for taking a numbered SQL script ([NN]) from DEV to STAGING and for verifying it on PRODUCTION read-only in CORECS ERP. Use when the user says "apply it on staging", "go ahead on staging", "I already ran [NN] in production, please verify", or asks whether a script is on a tier. Covers the rolled-back rehearsal, the live apply, hash comparison against DEV, tests on the live procs, the Exception Center runs, and the work-log / handoff / Atlas updates.
---

# STAGING rollout and PRODUCTION verification

Tiers (CLAUDE.md "Databases"): DEV = `corex.itcoreapps.com` / COREX001 (key `ConnSettingsServer`, catalog
COREX001); STAGING = `corex.itcoreapps.com,6601` / CORECSJFC2026_STAGING (key `ConnSettingsStaging`, db_owner);
PRODUCTION = `corex.itcoreapps.com,7701` / PRODJFC_COREX (key `ConnSettingsProdReadOnly`, **read-only: SELECT
only, no EXEC**; the user runs every PRODUCTION write). `ConnSettingsMain` on the laptop points wherever the user
last set it: never assume. Every helper prints `# server / catalog` first: read it.

STAGING changes need the user's explicit go in this conversation ("apply it on staging"). Approval for one script
does not cover the next one.

## Helper scripts (this folder, `scripts\`)

| Script | Use |
|---|---|
| `db.ps1 -Key K [-Catalog C] -Sql "..." / -SqlFile f [-NonQuery] [-OutFile f]` | one query or a GO-split file; `-OutFile` saves the first cell (proc text) |
| `batchrun.ps1 -Key K [-Catalog C] -SqlFile f` | runs a script batch by batch in ONE connection, stops at the first failing batch and prints its line numbers, rolls back anything left open. Use for applies, rehearsals and tests |
| `mkrehearsal.ps1 -Script s [-Before p1,p2] [-Tests t] [-Check "SELECT…"] -Out f` | builds a rolled-back rehearsal: BEGIN TRAN + prerequisites + the script (its open-transaction guard neutralised) + tests + ROLLBACK |
| `hashcompare.ps1 -Objects a,b [-Backup _OLD_…] [-Keys …]` | object hashes (whitespace-insensitive SHA-256) per tier side by side, "same" / "DIFFERS" / "MISSING on <tier>"; full 64-hex values (= the script guards) listed under `# full hashes` |

`db.ps1 -OutFile` needs a Windows-style path; from Git Bash pass `$(cygpath -m <path>)` (forward slashes; `-w` backslashes get eaten by the shell).

Run them with `powershell -NoProfile -ExecutionPolicy Bypass -File <path>`. Credentials stay in the registry (DPAPI,
same entropy as `Classes/RegistryProtection.cs`); never copy a connection string into a file.

## STAGING, step by step

1. **Prerequisites on STAGING.** Every script the new one needs is there (e.g. [97] needs [88]). The objects it
   patches have the hashes the guard expects (`hashcompare.ps1` DEV-backup vs STAGING-live). A difference means
   someone changed STAGING: stop and find out, don't widen the guard.
2. **Fixtures.** STAGING data differs from DEV (other invoices, vouchers, lots). Pick STAGING rows with a read-only
   query and make a STAGING copy of the test file (`sed` the ids). Choose rows nothing else is touching.
3. **Rehearse rolled back.** `mkrehearsal.ps1` (+ `-Before` for a prerequisite applied in the same run) →
   `batchrun.ps1`. Only success-path tests here: a refusal rolls back the whole transaction, install included.
   Confirm the last line shows the original state (objects back to their old text, no new objects).
4. **Apply live.** `batchrun.ps1 -Key ConnSettingsStaging -SqlFile SQL\[NN]-….sql`. The script commits itself.
5. **Compare with DEV.** `hashcompare.ps1` on every created / patched object and its backups: STAGING = DEV.
6. **Test on the live procs.** The success tests wrapped in `BEGIN TRANSACTION … ROLLBACK`; the refusal tests,
   each in its own `BEGIN TRY BEGIN TRANSACTION … END TRY BEGIN CATCH … END CATCH; IF @@TRANCOUNT > 0 ROLLBACK`
   capturing ERROR_NUMBER into a result table; a final "rows left behind = 0" check. If the script has an owner's
   test file in `SQL/` (e.g. `[88]-…_Test.sql`), run that too and compare with its DEV result.
7. **Exception Center on STAGING** (all read-only):
   - `tools/ExceptionCenter/SO_STS_ExceptionCheck.sql` → every check `Found = 0`, or only known findings
   - `tools/ExceptionCenter/BankRecon_GLvsRecon_Check.sql` → no gl_only / recon_only / amt_diff; also read section 5
     (GL dated after today; known 2026-10-15: tickets 19682 / 19683, ref 37136, 10-29, net 0) and section 6 (locked
     month changed after the lock)
   - `SELECT ExceptionCode, COUNT(*) FROM dbo.fn_rpt_exc_AP_Findings() GROUP BY ExceptionCode` (+ `fn_rpt_exc_AP_ShipmentCosting()`)
   - `tools/ExceptionCenter/POSV2_ExceptionCheck.sql` when POS V2 is involved
   Compare with the last known run in the work log; anything new must be explained before calling it done.
8. **Records.** Work-log row: the STAGING cell (rehearsal, live, tests, Exception Center, fixtures used). Fable's
   objects → a note under the item in `docs/handoff/2026-10-14_Hardening_Handoff_to_Fable.md` and the backlog page
   (republish `docs/handoff/HardeningBacklog.html` to its URL with `edits`). Atlas: rebuild + republish when the SQL
   surface changed (CLAUDE.md "Dependency Atlas").
9. **Tell the user** what to run on PRODUCTION, in which order, and whether users need the new exe.

## PRODUCTION verification (read-only)

1. `hashcompare.ps1` with STAGING and PRODUCTION: every object and backup "same". A PRODUCTION object that
   differs before the script (a hand edit) is expected only if the script was written for it.
2. Structure: markers in the patched objects, backups, new tables / columns / indexes / triggers (enabled?).
3. The script's own effect as SELECTs (the login cannot EXEC procs or scalar functions): repaired rows, counts,
   new rows in its tables, nothing half-done (a first attempt that installed nothing is common: say so).
4. Exception Center scripts as above (they are SELECT-only and run under the read-only login).
5. Activity since the install (payments, tickets, recon items posted after `modify_date`): first real use?
6. Work-log PRODUCTION cell (time from `modify_date`, what was verified); handoff / backlog for Fable's items.

## When something already happened on STAGING

- Users test on STAGING. Before undoing or re-applying, check the new tables for real rows (e.g. [96]: the user had
  reversed a test expense and a test JV). Undo procs / triggers / patches only; keep data and tables, then re-apply.
- Undo on DEV / STAGING = drop the new procs / triggers, `sp_rename` each `_OLD_` backup back, hash-check the
  originals against the guard, and only then run the corrected script.

## Gotchas seen in rollouts

- A rehearsal that "passes" because the script's guard said "already applied" and skipped: check the guard message.
- `INSERT … EXEC` of a wrapper captures every result set of nested procs: pick the wrapper's row explicitly.
- STAGING has no locked bank-recon month and few cleared JV items: create the condition inside the test transaction.
- The Exception Center's known findings drift (test vouchers on STAGING): note the known list with the date.
