---
name: tsql-sp-authoring
description: House templates and rules for writing or altering SQL Server 2022 stored procedures, views, and functions in this codebase. Use this whenever creating a new stored procedure, modifying an existing one, adding a view or table-valued function, or writing a deployment script for a database object — even for something that looks like a simple lookup proc. Also use when the user asks how a proc "should" be structured here.
---

# Authoring database objects

This codebase puts business logic in the database so it can be `ALTER`ed
without redeploying the app. That makes proc quality load-bearing. Follow these
templates rather than writing from scratch.

Before writing anything: **do not invent table or column names.** If the schema
isn't in context, ask for the DDL or the existing proc source. If you're
altering an existing proc, ask for its current text — several procs here have
local modifications that a reconstruction would erase.

**This codebase does not use `CREATE OR ALTER`.** Every deployment script in
this repo (see `SQL/YYYY-MM-DD_*.sql`) follows a rename-to-backup-then-create
convention instead: `sp_rename` the existing object to a timestamped backup
name, then `CREATE PROCEDURE` fresh. This keeps a live, queryable copy of the
prior version in the database itself (via `OBJECT_DEFINITION`) rather than
relying solely on source control, and it's the pattern `sp-reviewer` and the
rest of this project expect. Every template below uses it — do not substitute
`CREATE OR ALTER` even though it's shorter.

## Choosing the object type

| Need | Use | Prefix |
|---|---|---|
| Return data, no side effects | Procedure | `sp_` |
| Mutate state, own a transaction | Procedure | `spu_` |
| Report, possibly multi-result-set | Procedure | `sp_rpt_` |
| Reusable read shape, no parameters | View | `vw_` |
| Reusable read shape, parameterized | Inline TVF | `fn_` |

Prefer an inline TVF over a multi-statement TVF or a scalar UDF. Inline TVFs
merge into the caller's plan; the others are estimation hazards. Never place a
scalar UDF in a `WHERE` or `JOIN` predicate.

## Template — read procedure

```sql
-- Backup-then-create, not CREATE OR ALTER (see note above). The rename
-- block is only needed when the object already exists.
IF OBJECT_ID('dbo.sp_GetSomethingList', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetSomethingList', 'sp_GetSomethingList_OLD_MMddyyyyHHmmss';
GO

CREATE PROCEDURE dbo.sp_GetSomethingList
    @BranchCode varchar(10),
    @DateFrom   date,
    @DateTo     date
AS
/*
    Returns: one result set — <named columns and their meaning>
    Assumes: <preconditions>
    Callers: <form / endpoint>
*/
BEGIN
    SET NOCOUNT ON;

    SELECT
        h.HeaderID,
        h.ReferenceNo,
        h.TransDate,
        h.BranchCode,
        b.BranchName,
        ISNULL(h.NetAmount, 0) AS NetAmount
    FROM dbo.SomethingHeader AS h
    INNER JOIN dbo.Branch AS b
        ON b.BranchCode = h.BranchCode
    WHERE h.BranchCode = @BranchCode
      AND h.TransDate >= @DateFrom
      AND h.TransDate <  DATEADD(day, 1, @DateTo)
    ORDER BY h.TransDate, h.ReferenceNo;
END
```

Points that matter: explicit column list (the C# DTO binds by name, and
`SELECT *` breaks it the moment a column is added); half-open date range instead
of `BETWEEN` so a `datetime` column doesn't drop the last day; `ISNULL` on
amounts; no function wrapped around `h.TransDate` so the index can seek.

## Template — posting procedure

```sql
IF OBJECT_ID('dbo.spu_PostSomething', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_PostSomething', 'spu_PostSomething_OLD_MMddyyyyHHmmss';
GO

CREATE PROCEDURE dbo.spu_PostSomething
    @BranchCode  varchar(10),
    @TransDate   date,
    @SupplierID  int,
    @Details     dbo.SomethingDetailType READONLY,
    @UserId      int,
    @ReferenceNo varchar(30) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        ------------------------------------------------------------------
        -- 1. Validate everything BEFORE any write
        ------------------------------------------------------------------
        IF NOT EXISTS (SELECT 1 FROM dbo.Branch WHERE BranchCode = @BranchCode)
            THROW 50000, 'Invalid branch.', 1;

        IF NOT EXISTS (SELECT 1 FROM @Details)
            THROW 50000, 'No detail lines supplied.', 1;

        -- duplicate-post guard
        IF EXISTS (SELECT 1 FROM dbo.SomethingHeader
                   WHERE BranchCode = @BranchCode AND ReferenceNo = @ReferenceNo)
            THROW 50000, 'This document has already been posted.', 1;

        ------------------------------------------------------------------
        -- 2. Resolve configuration — never hardcode GL accounts
        ------------------------------------------------------------------
        DECLARE @GLExpense varchar(20), @GLPayable varchar(20);
        SELECT @GLExpense = ExpenseAccount, @GLPayable = PayableAccount
        FROM dbo.AccountingSetup
        WHERE CompanyCode = dbo.fn_CurrentCompany();

        IF @GLExpense IS NULL OR @GLPayable IS NULL
            THROW 50000, 'Accounting setup is incomplete.', 1;

        ------------------------------------------------------------------
        -- 3. Accumulate totals from the details — never trust a parameter
        ------------------------------------------------------------------
        DECLARE @Gross decimal(18,4), @Tax decimal(18,4), @Net decimal(18,4);

        SELECT @Gross = SUM(ISNULL(d.Amount, 0)),
               @Tax   = SUM(ISNULL(d.TaxAmount, 0))
        FROM @Details AS d;

        SET @Net = @Gross - @Tax;

        BEGIN TRANSACTION;

        ------------------------------------------------------------------
        -- 4. One ticket number for the whole document, fetched ONCE
        ------------------------------------------------------------------
        DECLARE @TicketNumber varchar(30);
        EXEC dbo.spu_GetTicketNumber @BranchCode, @TicketNumber OUTPUT;

        -- 5. Header, details, GL legs, subledger — all inside this transaction
        --    (explicit column lists on every INSERT)

        ------------------------------------------------------------------
        -- 6. Prove the entry balances before committing
        ------------------------------------------------------------------
        IF EXISTS (
            SELECT 1 FROM dbo.GeneralLedger
            WHERE TicketNumber = @TicketNumber
            GROUP BY TicketNumber
            HAVING ABS(SUM(Debit) - SUM(Credit)) > 0.0001
        )
            THROW 50000, 'Journal entry is out of balance.', 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
```

### Why each guard is there

- **Validate before mutate** — a rejection after a partial insert leaves orphan
  rows that nothing cleans up.
- **Duplicate-post guard** — a slow proc plus an impatient user equals two
  postings. The guard is the only real defense.
- **Config-driven GL accounts** — hardcoded account codes have caused
  misposting in this system more than once.
- **Self-accumulated totals** — a caller-supplied `@TotalAmount` drifts from the
  detail rows and the ledger ends up disagreeing with the document.
- **Ticket number outside any per-branch loop** — one number per document, not
  one per branch. Fetching it inside the loop fragments every downstream report
  that groups by ticket.
- **Balance assertion** — cheap, and it catches an entire class of leg bugs at
  post time instead of at month-end.
- **`XACT_STATE()` before rollback** — with `XACT_ABORT ON` the transaction may
  already be doomed or already gone; an unconditional `ROLLBACK` raises its own
  error and hides the real one.

### The XACT_ABORT + nested-call trap

If a `TRY` block `EXEC`s several procedures in sequence and one fails,
`XACT_ABORT ON` dooms the transaction. Every statement after that point raises
error 3930 ("the current transaction cannot be committed"), which masks the
original error. Either do the whole unit of work in one proc, or check
`XACT_STATE()` between calls and stop immediately on a doomed transaction.

## Editing a posted document

Pick the strategy by whether the document's *shape* can change:

- **Shape can vary** (line count differs — JV, expense, voucher): edit is
  delete-and-repost under the same reference number, in one transaction:
  validate eligibility → restore every side effect the original created
  (balances, applied payments, reconciliation state) → delete → repost. Gate it
  so it refuses when downstream activity has already touched the posting; fall
  back to the reversal proc in that case.
- **Shape is always fixed**: a plain in-place `UPDATE` is correct and simpler.

## Views and functions

```sql
IF OBJECT_ID('dbo.vw_SomethingPosted', 'V') IS NOT NULL
    EXEC sp_rename 'dbo.vw_SomethingPosted', 'vw_SomethingPosted_OLD_MMddyyyyHHmmss';
GO

CREATE VIEW dbo.vw_SomethingPosted
AS
SELECT h.HeaderID, h.ReferenceNo, ...
FROM dbo.SomethingHeader AS h
...;
```

The same rename-then-create shape applies to inline TVFs (`OBJECT_ID(..., 'IF')`).

No `SELECT *`, no `ORDER BY` in a view, schema-qualify every reference. If a
view is consumed by procs that filter on a status column, consider a filtered
index on the base table to match.

## SQL Server 2022 conveniences — compat level 120, not 160

The engine is SQL Server 2022, but `CORECSERP_002_DEV` and
`CORECSJFC2026_STAGING` both run database **compatibility level 120**
(confirmed via `sys.databases.compatibility_level`), not 160. Compat level
gates a lot of newer T-SQL surface regardless of the engine version — verified
directly against dev before trusting this list:

- **Work today:** `GREATEST`/`LEAST`, `DATE_BUCKET`, `IS [NOT] DISTINCT FROM`.
  Safe to use in new code.
- **Do NOT use — `Invalid object name` at compat 120:** `GENERATE_SERIES`,
  `STRING_SPLIT` (with or without the ordinal argument — it's unavailable
  outright here, not just missing the ordinal). Fall back to a numbers/tally
  table for series generation, and the existing string-splitting helper (or a
  recursive CTE) instead of `STRING_SPLIT`.
- Parameter Sensitive Plan optimization does **not** apply here (requires
  compat 160) — see `db-perf-tuner`'s parameter-sniffing section; manual
  workarounds (`OPTIMIZE FOR UNKNOWN`, statement-level `RECOMPILE`) are the
  real options, not "check if PSP already handles it."
- Don't rewrite working procs just to adopt the ones that do work; use them in
  new code where they're clearer.
- If a future migration bumps compat level, re-verify this list — don't
  assume the rest of SQL Server 2022's surface area opens up uniformly.

## Deployment

One object per file, rename-existing-to-timestamped-backup-then-`CREATE`
(never `CREATE OR ALTER` — see above), re-runnable, saved as
`SQL/YYYY-MM-DD_Description.sql` and committed to source control. Table
changes go in separate guarded migration scripts:

```sql
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.SomethingHeader')
                 AND name = 'TicketNumber')
    ALTER TABLE dbo.SomethingHeader ADD TicketNumber varchar(30) NULL;
```

## Before calling it done

Run the `sp-reviewer` agent on the new procedure, and `ledger-integrity-auditor`
if it writes to a ledger. Report what they found rather than quietly fixing
everything — the findings are often worth the user's attention.