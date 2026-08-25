# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**CORECS / SPIRE** ("CORECS ERP") is a large single-project Windows Forms desktop application (`SalesInventorySystem.csproj`, currently targeting .NET Framework 4.6.1, `OutputType=WinExe`; the project is being migrated to .NET Framework 4.8 under VS 2022/2026 — check the `.csproj`'s `TargetFrameworkVersion` before assuming which one is current). It is an all-in-one back-office system covering POS, sales, inventory/warehousing, accounting/GL, branch/forwarding logistics, and hotel management for what appears to be a retail/distribution business with a head office and multiple branches.

UI framework is DevExpress v26.1 (WinForms/XtraForms/Ribbon). The backing database engine is Microsoft SQL Server (2022).
 
There is no test project, no CI configuration, and no build/lint scripts in the repo — this is developed and run directly from Visual Studio.

## Strict AI operating rules

1. **Output style:** provide targeted code snippets for the fix/change requested. Avoid full class/file rewrites unless explicitly asked.
2. **SQL formatting:** write T-SQL with UPPERCASE keywords and structured indentation; always use parameterized queries (`SqlParameter`), never string-concatenated SQL.
3. **DevExpress version lock:** do not suggest or use DevExpress controls/APIs introduced after v26.1.
4. **Legacy/unused code:** do not auto-delete or refactor legacy non-DevEx forms or the scratch folders (`zzzDemozzz/`, `Samples/`, `txtBackup/`) or classes that look unused — they may hold live business logic or still be reachable from a menu.
5. **Credentials & registry:** never hardcode real database credentials or registry connection paths into `app.config` or any source file.

## Known Bug Patterns
check for these before and after any change
1. LoadData() is the real init entry point. Never gut LoadData() into a no-op and move init logic into Load alone — hosted UserControl Load is unreliable and this has broken every lookup on a form before. Keep LoadData() as the real entry; Load is only a guarded fallback.
2. Grid LookUpEdit columns need TextEditStyle = DisableTextEditor. Without it, free-text bypasses ValueMember and silently truncates/corrupts data. Hit repeatedly across modules — always set this on new lookup grid columns.
3. .Text vs .EditValue mixups. .Text reads the DisplayMember, .EditValue reads the ValueMember. Using the wrong one is a recurring bug class — double check which one a lookup/combo access actually needs.
4. Edit pattern depends on whether the record's "shape" can change.
If shape can change (JV, Approved/Single/Multi-Branch Expense, Voucher): edit = delete-and-repost under the same ReferenceNo.
If always single-shape (Simple Posting): true in-place edit is fine.
Once a payment or other activity has touched a posting, fall back to the reversal SP instead of editing.
5. Gross vs net cash bugs. Always self-accumulate net amounts; don't trust a caller-supplied parmcheckamount parameter at face value.
6. Reset Entry not call after submitting or hit save button in UserControl Forms.
7. `Inventory.ShipmentNo` alone is NOT a unique per-batch key — do not group/filter a "select this specific shipment" dropdown or FIFO breakdown by `ShipmentNo` alone. Conversion-output lots all carry the literal `ShipmentNo='CONVERSION'` and quantity-adjustment lots carry `ShipmentNo=''`, so multiple unrelated batches collapse into one row/scope. Group/filter by `Product+ShipmentNo+ReferenceCode` instead (composite `ValueMember` on the lookup control: `Product||ShipmentNo||ReferenceCode`). Hit and fixed in Conversion's and Dispatch's Manual-FIFO dropdowns; built correctly from the start in StockOutPerBarcode.
8. `Task.Run(() => Method())` where `Method()` touches a form control (grid, TextEdit, etc.) throws `Cross-thread operation not valid` — but only once the form's window handle already exists, so it passes silently during initial `Load` and only surfaces later (e.g. on a "Reset Entry"/"New Entry" button click after the form is already shown). Split any such method into a DB-only fetch (safe inside `Task.Run`) and a UI-only bind/assign (run after the `await`, back on the UI thread). Hit and fixed in `DispatchPerBarcode.cs` and `ConversionPerBarcode.cs`'s `ResetUIAsync()`.

## Conventions

**Standard inventory-out module design.** For any new module whose job is to *reduce* inventory (stock-out/write-off, dispatch, conversion source-consumption, etc.), use the Barcode-scan + FIFO-Auto + FIFO-Manual pattern, not a fresh design. Reference implementations: `HOFormsDevEx/ConversionPerBarcode.cs` (source-only deduction, no destination/GL side — closest template for a pure write-off), `HOFormsDevEx/DispatchPerBarcode.cs` (same pattern plus a destination branch + GL posting, for actual transfers), `HOFormsDevEx/StockOutPerBarcode.cs` (the plain write-off case — Branch + Category + Remarks header, no destination, no GL). Shape:
- **Source Method** radio: `Scan Barcode` vs `Select Product (FIFO)`.
- **FIFO Type** radio (only shown for the FIFO source method): `Auto (By Sequence)` walks a product's lots oldest-`SequenceNumber`-first; `Manual (By Shipment)` lets the user target one specific batch via a `SearchLookUpEdit` bound to a composite `ValueMember` of `Product||ShipmentNo||ReferenceCode` (`ShipmentNo` alone is NOT a unique batch key — see the known bug pattern below) and must not spill into other batches if that one is short.
- Staged lines accumulate in an in-memory grid; Submit posts everything atomically via one TVP-taking `spu_Post...` SP (race-safe `UPDLOCK`+rowcount-guard deduction, `IsStock=0` cleanup for exhausted lots) — never one row at a time.
- New Entry / Posted tabs; Posted supports View Details (drill into the line detail table/view) and Reverse (restore `Available`/`IsStock`, flip header `Status`).
- Give each new module its own dedicated tables/TVPs/SPs — do not reuse another module's or a legacy module's tables even if the shape looks similar (avoids conflicting lifecycles/isDone-flag semantics).

Module UI pattern (for modules with no formal mapping/approval step): two tabs — New Entry and Posted (View Details, Copy, Edit actions).
Naming: sp_ for general procs, spu_ for update/posting procs.
Code-Name display convention is used system-wide for dropdowns/grids (show Code - Name, not just one or the other).
SP Backup Renaming: add suffix timestamp in sp name for backup before creating new one

## Build & run

- Solution: `SalesInventorySystemGENERALVERSION.sln` → single project `SalesInventorySystem/SalesInventorySystem.csproj`.
- IDE: Visual Studio 2022 / 2026, DevExpress v26.1 toolset. Or via MSBuild:
  ```cmd
  msbuild SalesInventorySystemGENERALVERSION.sln /p:Configuration=Debug /p:Platform="Any CPU"
  ```
- There is no `dotnet` CLI support (old-style .csproj, `packages.config`-based NuGet restore, many DLL references via `HintPath` pointing outside the repo, e.g. `..\..\IDProject\IDProject\bin\Debug\*.dll`). Building outside the original dev machine will likely fail on missing `HintPath` references (AForge libraries, `DocumentFormat.OpenXml.dll` under a `Downloads` folder, DevExpress v26.1 GAC assemblies, Crystal Reports runtime) — these must be present/installed locally; don't try to "fix" broken paths by guessing replacements without checking with the user first.
- No automated tests exist. Verifying a change means building successfully and, where practical, exercising the relevant form manually against a configured database.

## Data access & configuration architecture

- There is **no ORM**. Data access is raw ADO.NET (`System.Data.SqlClient`) scattered across forms and `Classes/*.cs`, despite DevExpress.Xpo being referenced.
- Connection strings are **not** primarily read from `app.config` (that file only holds a few stale/legacy entries with placeholder credentials — never trust it as the source of truth, and never hardcode real credentials into source in this repo). The real connection strings are stored per-machine in the **Windows Registry** under `HKCU\...` keys such as `AAITCRE\ConnSettingsMain` (main SalesAndInventory DB), plus other keys for accounting/HRM/Postgres/cloud-upload targets. See `Classes/Database.cs` (`getConnection()`, `getConnection(string regkeyname)`, `getConnectionString(string regkeypath)`, `getPgConnection()`) and `Connection.cs` (the UI that writes these registry keys via `btnsave_Click`).
- `GlobalCache.InitializeCompanyData()` is called first thing in `Program.Main` and opens a DB connection immediately at startup to load company info — DB connectivity (registry key configured) is a hard prerequisite for the app to even start.
- `Classes/GlobalVariables.cs` holds static, process-wide mutable state (current user, session flags, shared `SqlConnection`/`OleDbConnection`/`DataSet` instances) that most forms read/write directly instead of passing state explicitly. Many other classes (e.g. `Database`) inherit from `GlobalVariables` to get this state in scope.
- SQL Server databases are involved: `CORECSERP_002_DEV` (sales/inventory/POS/Accounting), if there are changes has been made in `CORECSERP_002_DEV` should also apply in `CORECSJFC2026_STAGING` database but ask confirmation first.

## Module / folder structure

The project is organized by business domain rather than by layer. Within most domains you'll find **two parallel sets of forms**: legacy plain WinForms and a `...DevEx` counterpart (e.g. `Accounting/` vs `AccountingDevEx/`, `HOForms/` vs `HOFormsDevEx/`, `POS/` vs `POSDevEx/`). The `DevEx` versions use DevExpress `XtraForms`/`Ribbon` controls and are the actively developed line — new work generally goes into the `DevEx` variant of a form unless told otherwise. Don't assume the non-DevEx form is dead code without checking whether `Main.cs` still routes to it.

- `Accounting/`, `AccountingDevEx/` — GL posting, check vouchers, tickets, aging/balance sheet/income statement reports.
- `Branches/` — branch-level inventory (receiving, quantity adjustments, branch POS).
- `HOForms/`, `HOFormsDevEx/` — head-office forms: inventory intake, shipments, supplier accounts, DB backup/upload tooling.
- `POS/`, `POSDevEx/`, `POSStandAloneSetup/` — point-of-sale screens, cash wallet/tapper, discount handling, standalone POS configuration.
- `Orders/` — branch ordering workflows (including "STS" and batch-mode variants).
- `Forwarding/` — trucking/logistics (trucks, staff, shipments) for the forwarding/distribution side of the business.
- `HotelManagement/` (+ `HotelManagement/Classes/`) — a largely self-contained hotel front-desk module (check-in/out, housekeeping, charges) sharing the same app shell.
- `CIF/` — customer information file forms.
- `Reporting/` (incl. `Reporting/BIR/`) — the large reporting surface, including Philippine BIR (tax bureau) compliance reports (2550M, EWT, E-Sales, etc.) — treat these as regulatory/compliance-sensitive when touching report logic or number formatting.
- `DevExReportTemplate/` — DevExpress `XtraReport` print/report templates (vouchers, invoices, credit/debit memos, stickers).
- `Barcode/`, `Sticker/` — barcode/label printing components.
- `Classes/` — shared domain and infrastructure code: `Database.cs`, `GlobalVariables.cs`, `GlobalCache.cs`, `HelperFunction.cs`, `SearchLookUpClass.cs`, entity-ish classes (`Product.cs`, `Customers.cs`, `Suppliers.cs`, `Inventory.cs`, ...), plus infra utilities (`PasswordHasher.cs`, `PasswordPolicy.cs`, `IDGenerator.cs`, `AutoUpdater.cs`, `WebSocketDashboardClient.cs`).
- `Samples/`, `zzzDemozzz/`, `txtBackup/`, forms named things like `asdasd.cs`/`TestTestTest.cs`/`PivotPractice.cs` — scratch/demo/experimental code left in the tree. Don't treat these as authoritative examples of current patterns, and don't delete them without asking (may still be wired into a menu somewhere).

## App shell & navigation

- `Program.cs` boots a `SingleInstanceApp` (`SingleInstanceApp.cs`, via `Microsoft.VisualBasic.ApplicationServices.WindowsFormsApplicationBase`) enforcing single-instance execution, then shows `StartupForm` → `Login` → `Main`.
- `Main.cs` (`DevExpress.XtraBars.Ribbon.RibbonForm`) is the MDI-style shell: one ribbon with a page per module (Sales, Inventory, Accounting, Hotel, Forwarding, CIF, Admin). Menu/page visibility is toggled per role based on flags set at login (`Login.isglobalAdmin`, `isglobalWarehouseOfficer`, etc.) rather than a generalized permissions system — when adding a new module entry point, follow this same role-flag-gating pattern.
- Forms implementing `Classes/Interface/IResettableForm.cs` expose `Task ResetUIAsync()` for clearing grids/inputs and re-fetching IDs — implement this on new reusable/reopenable forms instead of inventing a new reset convention.

## Conventions to follow when editing

- This is a single developer's long-running project committed in dated snapshots (commit messages like `eulzdell_06282026`) directly to `main` — there's no branch/PR workflow to infer conventions from; match the style of the surrounding file instead.
- Match existing patterns per file rather than introducing new architecture (e.g. don't introduce an ORM or DI container into a form that uses raw `SqlConnection`/`SqlCommand`).
- `*.Designer.cs` and `*.resx` files are generated by the WinForms/DevExpress designer — hand-edit only for small, surgical fixes; prefer regenerating via the designer for layout changes.

## Working Agreement

- When starting work on a module, confirm which module/form/SP set is in scope before making changes.
- Flag any deviation from the patterns above rather than silently "fixing" them — some are deliberate (e.g. locked fields during edit) and were changed for a specific reason; check history before reversing a prior decision.
- Prefer surfacing a question over guessing when a screen's live file differs from what's expected (e.g. an extra control not in the original build) — add to it, don't guess at replacing it.