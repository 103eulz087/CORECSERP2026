---
name: reporting-sp
description: Builds reporting stored procedures for this codebase — general ledger, trial balance, aging, inventory movement, sales and payroll summaries, and reconciliation reports with beginning/period/ending balance rows or multi-result-set Excel-shaped output. Use whenever the user asks for a new report, a report that ties out to another report, drill-down from a summary row, or a fix to report totals that disagree with the ledger.
---

# Building report procedures

Reports here are `sp_rpt_` procedures. They are read-only, often return several
result sets, and are frequently checked against each other — so the hard part is
not the query, it's making the numbers tie out.

## Decide the shape first

Ask, or confirm from context:

- **Grain.** One row per what — transaction, document, account, account-per-
  period, branch-per-account? Get this wrong and every total is wrong.
- **Period semantics.** Is the date filter on transaction date, posting date, or
  document date? Are these different columns in this schema? They usually are.
- **Balance style.** Does the report need Beginning Balance / Period Change /
  Ending Balance rows, or just a flat listing?
- **Scope.** All branches, one branch, a set? All accounts or a range? Do *not*
  assume "All Branches" implies "All Accounts" — cascading those filters has
  produced wrong reports here before. Treat them as independent.
- **Consumer.** A grid, an Excel export with a fixed layout, or a printed
  report? An Excel-shaped report usually means multiple result sets in a fixed
  order.
- **Drill-down.** Should a summary row open the underlying transactions? If so
  the report must expose the key that identifies them (usually `TicketNumber`) —
  even when the query only joins on it internally. A summary that can't be
  drilled into gets rebuilt later.

## Balance-row pattern

Beginning / period / ending is a union of three differently-scoped queries with
a row-type discriminator that controls sort order:

```sql
;WITH Beginning AS (
    SELECT g.AccountCode,
           SUM(ISNULL(g.Debit,0) - ISNULL(g.Credit,0)) AS Amount
    FROM dbo.GeneralLedger AS g
    WHERE g.TransDate < @DateFrom
      AND (@BranchCode IS NULL OR g.BranchCode = @BranchCode)
    GROUP BY g.AccountCode
),
Period AS (
    SELECT g.AccountCode, g.TicketNumber, g.TransDate, g.ReferenceNo,
           ISNULL(g.Debit,0) AS Debit, ISNULL(g.Credit,0) AS Credit
    FROM dbo.GeneralLedger AS g
    WHERE g.TransDate >= @DateFrom
      AND g.TransDate <  DATEADD(day, 1, @DateTo)
      AND (@BranchCode IS NULL OR g.BranchCode = @BranchCode)
)
SELECT 1 AS RowType, 'BEGINNING BALANCE' AS Description, ...
FROM Beginning
UNION ALL
SELECT 2 AS RowType, p.ReferenceNo, ...
FROM Period AS p
UNION ALL
SELECT 3 AS RowType, 'ENDING BALANCE', ...
FROM ...
ORDER BY AccountCode, RowType, TransDate;
```

Rules that keep it correct:

- The beginning balance uses `< @DateFrom`, the period uses `>= @DateFrom AND
  < DATEADD(day,1,@DateTo)`. Half-open, so a `datetime` column doesn't silently
  drop the last day. Never `BETWEEN` on a datetime.
- Ending must equal beginning plus period change **computed the same way** —
  derive it from the other two rather than running a third independent query,
  or the two will drift when the filter logic changes.
- Every optional filter uses the `(@Param IS NULL OR col = @Param)` form so one
  proc serves both "all" and "specific". Add `OPTION (RECOMPILE)` if the plan
  for "all" is bad for "specific" — measure before adding it.
- Every amount gets `ISNULL`. A single NULL debit nulls the whole `SUM` in some
  expression shapes.
- Sign convention: pick signed-amount or separate-debit-credit and use it
  consistently across every report, or reports won't tie out to each other.

## Running balances

Use a window function rather than a self-join or a loop:

```sql
SUM(Debit - Credit) OVER (
    PARTITION BY AccountCode
    ORDER BY TransDate, TicketNumber
    ROWS UNBOUNDED PRECEDING) AS RunningBalance
```

The `ROWS UNBOUNDED PRECEDING` frame matters — the default is `RANGE`, which
lumps together all rows with an equal `ORDER BY` value and gives the wrong
running balance whenever two entries share a date.

SQL Server 2022's named `WINDOW` clause keeps this readable when several
columns share the same frame.

## Multi-result-set (Excel-shaped) reports

When the report mirrors a fixed spreadsheet layout, return one result set per
block, in the sheet's order, and document the order in the proc header:

```sql
/*
    Result set 1: header — period, branch, prepared-by
    Result set 2: outstanding checks
    Result set 3: deposits in transit
    Result set 4: reconciliation summary
*/
```

The C# side reads them with `QueryMultiple` in exactly that order, so the header
comment is the contract. Changing the order or inserting a block is a breaking
change — update both sides in one commit.

## Drill-down

If a report supports right-click or double-click to open the underlying
transactions:

- The report result set must **expose the drill key** as a column, even if it's
  only used internally in a join. A proc that groups by `TicketNumber` but
  doesn't select it cannot be drilled into.
- The drill-down proc should be self-contained — take the key, return everything
  the popup needs, and not depend on state held by the calling form.
- Don't gate the context menu on conditions that can silently be false. A menu
  that never appears reads as a broken feature; show it and let the handler
  explain why a row can't be drilled.

## Performance

Reports are the queries most likely to scan. Before finishing:

- No function wrapped around a filtered date or code column.
- No scalar UDF in a predicate.
- Check whether a filtered index on the status column would serve the common
  "unposted / open documents" case.
- Set a generous `CommandTimeout` on the C# side for period-end reports.

If the report is slow, hand it to the `db-perf-tuner` agent with the plan rather
than guessing at indexes.

## Before calling it done

Run `sp-reviewer` for mechanics. Then verify the tie-out by hand on one period:
does this report agree with the general ledger, and with any subledger it
overlaps? State the check you ran and its result — "it compiles" is not the same
as "it balances."