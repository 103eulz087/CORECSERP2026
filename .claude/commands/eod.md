---
description: Generate an end-of-day report from today's git activity
---

Generate an end-of-day report for today's work session on this project.

Steps:
1. Run `git log --since=midnight --oneline` to see today's commits. If there
   are none, run `git diff` and `git status` instead to capture uncommitted
   work in progress.
2. For each change, briefly note: which module/form/SP was touched, what was
   done (fix / new feature / refactor), and whether it's complete or still
   in progress.
3. Call out any of the known bug patterns from CLAUDE.md that came up today
   (e.g. LoadData/Load, DisableTextEditor, .Text vs .EditValue, gross vs net
   cash) so they're visible at a glance.
4. List anything left open or blocked, and anything that needs the user's
   decision before continuing tomorrow.
5. Write the report to `docs/eod-reports/YYYY-MM-DD.md` (create the folder if
   it doesn't exist), using today's date. Keep it under one page — headers:
   "Completed", "In Progress", "Bugs Encountered", "Open Questions / Next Up".

Do not invent work that wasn't actually done — base everything on the git
history and diffs, not assumptions.
