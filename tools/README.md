# CORECS ERP tools: Dependency Atlas and Process Trace

Two read-only tools that turn the source code and the database into a browsable HTML page.

| Tool | What it shows | Builder | Output page |
|---|---|---|---|
| **Dependency Atlas** | Every form, report and class, and the stored procedures, views, functions, tables and table types it uses, directly and through SQL. | `tools\DependencyAtlas\Build-DependencyAtlas.ps1` | `docs\atlas\DependencyAtlas.html` |
| **Process Trace** | One real transaction followed step by step through every table a module writes, with the linking keys color-coded. Modules: Sales Order, AR Payment. | `tools\ProcessTrace\Build-ProcessTrace.ps1` | `docs\process-trace\ProcessTrace.html` |

Neither tool ever writes to the database. They only run `SELECT` queries.

---

## Only want to look at the pages?

You don't need the repo or a database:

- Open the shared links you were sent, **or**
- Double-click `docs\atlas\DependencyAtlas.html` or `docs\process-trace\ProcessTrace.html`. Each is a single self-contained file, and the data is inside it.

Everything below is only for someone who needs to **rebuild** the pages.

---

## 1. Get the right branch: `laptopdell`

The tools exist **only on the `laptopdell` branch**. `main` and `laptop` are older and don't have them. If you build from the wrong branch, the `tools` folder will be missing or out of date.

### First time (no copy of the repo yet)

```powershell
git clone https://github.com/103eulz087/CORECSERP2026.git
cd CORECSERP2026
git checkout laptopdell
```

### Already have the repo

```powershell
cd <your CORECSERP2026 folder>
git fetch origin
git checkout laptopdell
git pull origin laptopdell
```

If `git checkout` refuses because you have local changes, stash them first (`git stash`), then check out the branch.

### Check you're on the right branch

```powershell
git branch --show-current
```

It must print **`laptopdell`**. Then check the tools are there:

```powershell
dir tools\DependencyAtlas, tools\ProcessTrace
```

You should see `Build-DependencyAtlas.ps1` and `Build-ProcessTrace.ps1`. If you don't, you're on the wrong branch or haven't pulled. Go back to the commands above.

Before every rebuild, run `git pull origin laptopdell` so your copy has the latest modules.

---

## 2. One-time setup on your PC

1. **Build the solution once** in Visual Studio (`SalesInventorySystemGENERALVERSION.sln`, Debug). The tools use `SalesInventorySystem\bin\Debug\SalesInventorySystem.exe` only to decrypt the saved connection; none of the app runs. Skip this if you use `-ConnectionString` (step 3).
2. **Save a database connection under your own Windows login.** Open the app's Connection screen and save the server and database. The saved connection is encrypted for one Windows user on one PC, so someone else's saved setting won't work on yours.
3. **Database rights:** read access to the database. The Dependency Atlas also needs **View Definition**, so it can read which procedures use which tables.
4. **Windows PowerShell 5.1** is already part of Windows 10/11. Nothing else to install.

Which database you build from: DEV is `COREX001` (normally what the saved connection points to); STAGING is `CORECSJFC2026_STAGING`.

---

## 3. Run

Open PowerShell **in the repo root** (the folder that contains `CLAUDE.md` and `tools`).

### Dependency Atlas

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\DependencyAtlas\Build-DependencyAtlas.ps1 -RegistryKey "AAITCRE\ConnSettingsMain"
```

### Process Trace (all modules)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\ProcessTrace\Build-ProcessTrace.ps1 -RegistryKey "AAITCRE\ConnSettingsMain"
```

Each takes about a minute and ends with a `Wrote ...html` line. Open that file in a browser.

### Options

| Option | Works with | What it does |
|---|---|---|
| `-Catalog CORECSJFC2026_STAGING` | both | Build from another database on the same server instead of the saved one. |
| `-ConnectionString "Server=...;Database=...;User ID=...;Password=..."` | both | Use this connection instead of the saved one; the exe isn't needed. Type it on the command line; never save it in a file in the repo. |
| `-Modules SalesOrder` | Process Trace | Build only the named module(s), e.g. `-Modules SalesOrder,ARPayment`. |
| `-NoMask` | Process Trace | Show real customer and user names. By default they become "Customer A" / "User 1"; keys and amounts are always real. Don't share a page built with `-NoMask` outside the company. |

---

## 4. Common problems

| Message | Fix |
|---|---|
| `Build the solution first: ...SalesInventorySystem.exe not found` | Build the solution in Visual Studio (step 2.1), or use `-ConnectionString`. |
| `No 'dbconn' value under HKCU\...` | No connection is saved for your Windows login. Save one in the app's Connection screen (step 2.2). |
| `Login failed` or a decrypt error | The saved connection was made under another Windows user. Save it again under your own login. |
| `...cannot be loaded because running scripts is disabled` | You left out `-ExecutionPolicy Bypass`. Copy the command exactly. |
| `The term 'tools\...' is not recognized` / file not found | You're not in the repo root, or you're not on `laptopdell` (section 1). |
| The page has fewer modules than expected | `git pull origin laptopdell`, then build again. |

---

## 5. Sharing a rebuilt page

The generated `.html` file is all you need: send it, or put it on a shared drive. Updating the published claude.ai links requires edit access from the page owner, or asking the owner to republish.

---

## 6. Adding a Process Trace module

Each module is a pair of files in `tools\ProcessTrace\modules\`:

- `<Name>.json`: the steps (who writes what), the tables with the key columns that link them, sample transaction IDs, and findings.
- `<Name>.sql`: a read-only query that takes `@Ids` and returns one result set per table, each starting with a `_t` column naming the table.

Copy `SalesOrder.json` / `SalesOrder.sql` as the pattern, then run the Process Trace command again. Details are in `CLAUDE.md` under "Process Trace".
