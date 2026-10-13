# POS V2 — hybrid (online / offline) point of sale — plan

Status: **plan only, nothing built** (2026-10-12). Replaces `POS/PointOfSale.cs` with a new module in its own folder, with its own tables, procedures and views. The old POS stays as it is until the new one is accepted.

## 1. What exists today (checked 2026-10-12)

- `POS/PointOfSale.cs`: 2,736 lines, a single `XtraForm` with static state. It mixes UI, SQL (mostly inline, string-concatenated), serial port (scale / display pole) and printing.
- **Each item is posted as it is scanned:** `sp_AddSalesInvoice` writes one `BatchSalesDetails` row and updates `BatchSalesSummary`. A sale is many separate writes, not one transaction.
- **It works local-first:** on a terminal, `ConnSettingsMain` points to a local SQL Server (this laptop: `(local)` / `ITCOREPOSFORDEMO`, **SQL Server 2014**, 23,750 products).
  - `Classes/PosDataDownloader.cs` copies master data down from `ConnSettingsServer`: branches, customers, products, users, categories.
  - `Classes/PosDataUploader.cs` bulk-copies whole tables up, mainly at end of day (`POS/POSEndOfDay.cs`, `POS/POSUploadChecker.cs`). It works by deleting the server's rows for the day, then inserting.
- **No real-time stock deduction:** `sp_AddSalesInvoice` reads `InventorySettings.isRealTimeDeduction` but never uses it.
  - Stock is deducted later, by a head-office batch: `HOFormsDevEx/DeductInventoryDevEx` → `spu_ComputeSalesCosting` (2019).
  - The GL comes from another batch screen (`HOForms/DataAnalysisAndTicketing`).
- **Numbering:**
  - The OR number comes from `MAX(ReferenceNo)+1` on `BatchSalesSummary`.
  - The transaction number comes from `MAX+1` on `POSTransaction`.
  - A text file holds the OR series (`C:\POSTransaction\ORSeries\`).
  - None of these is safe for offline or for several terminals.
- **Production JFC (`PRODJFC_COREX`, via the 10-08 copy) has no POS data:**
  - no Z-reading, cashier session or POS transaction rows;
  - every `BatchSalesDetails` row is from sales orders (cashier 99999).
  - So the POS serves another deployment. The tables are shared with sales orders (`BatchSalesSummary` / `Details`), which is another reason for new tables.
- **Readers of the old tables:**
  - about 30 POS forms;
  - `POS/POSSalesReportDevEx`, `Reporting/BIR/BIR2550M(2)`, `Reporting/SalesInvoiceDexEx`;
  - `POSDevEx/*` reports.

## 2. Goal (user, 2026-10-12)

- **Online:** a sale deducts branch inventory and is posted at once.
- **Offline:** the sale is kept on the terminal. When the network is back, every offline sale uploads automatically and deducts inventory then.
- Code that is properly organized: no inline SQL in the form, no static state shared between forms.

## 3. Recommended design: always local first, then sync at once (outbox)

**One path for every sale, not two:**

1. Payment saves the whole sale **in one local transaction**: header, lines, payments, discounts, plus an **outbox** row. The receipt prints from this. The cashier is never blocked by the network.
2. A background **sync worker** sends the outbox to the server as soon as there is a connection:
   - online, that's about a second after payment, which is effectively real time;
   - offline, the outbox waits and drains on its own when the connection returns.
3. The server procedure posts the sale and deducts FIFO stock **in one server transaction**. It is **idempotent by the sale's GUID**, so a retry after a dropped connection never posts twice.

**Why not "online → write to the server, offline → write locally"?**

- That needs two code paths and a failover in the middle of a sale. If the network drops halfway, the sale is half on the server and half nowhere.
- Local-first gives the same result online (deducted within seconds) with one tested path.
- It is the pattern the current POS already half-uses (local DB plus uploader), done per sale instead of per day.

**Rules:**

- **The server is the authority for stock.**
  - The terminal keeps a downloaded copy of branch availability, for warnings only (e.g. "only 2.5 kg left").
  - Deduction uses the existing FIFO engine (`spu_InvFIFO_Deduct`, AUTO by sequence at the branch). So POS stock moves the same way as STS / Sales V2: `IsWarehouse`, the sticker-barcode rule (scanning a stickered lot = LOT mode), applocks, ledger rows.
- **Offline oversell** (decision Q3): when an offline sale arrives and the branch is short, recommended:
  - post the sale anyway (it happened);
  - deduct what exists;
  - record the shortfall on a POS shortage list (Exception Center), instead of refusing.
- **Numbering per terminal, not per server:** the OR / SI series and the transaction number come from a local counter per machine, prefixed by the terminal (BIR: each accredited machine has its own series, `POSInfoDetails.MachineUsed` / MIN). This works offline and can't collide between terminals.
- **Master data down:** products, prices (Price1–4), categories, discounts, users and customers are pulled by delta (changed since the last pull), not the full table each time. Prices are kept per branch, as now.
- **Void / cancel after payment:** a void is a new outbox event on the original sale's GUID. The server restores the stock with `spu_InvFIFO_Restore`. A void of a sale still in the outbox (never uploaded) is sent with it, in order.

## 4. Data

**Server, new tables** (CLAUDE.md: each new module gets its own tables):

| Table | One row per |
|---|---|
| `POSV2_Terminal` | terminal (branch, machine, MIN, OR prefix, last series seen) |
| `POSV2_Shift` | cashier shift (open / close, beginning cash, X / Z read figures) |
| `POSV2_Sale` | sale (GUID, terminal, OR no., date, customer, totals, VAT / VAT-exempt / zero-rated, status, uploaded-at, posted-at) |
| `POSV2_SaleLine` | line (product, barcode, qty, price level, unit price, line discount, VAT flag, cost from FIFO) |
| `POSV2_SaleLot` | FIFO lot taken by a line (lot, qty, cost), for void / restore and costing |
| `POSV2_Payment` | payment (cash, card, charge account, …) |
| `POSV2_Discount` | SC / PWD / other / one-time discount (ID no., name, VAT adjustment) |
| `POSV2_SyncLog` | upload attempt (result, error), for support |
| `POSV2_Shortage` | offline sale line that found less stock than sold |

**Terminal (local DB, must run on SQL Server 2014):** master-data copies (`Product`, `Price`, `Category`, `Discount`, `User`, `Customer`, `StockSnapshot`), the same sale / line / payment / discount tables, `Outbox`, `Counter`.

**Procedures (server):**

| Procedure | Does |
|---|---|
| `spu_POSV2_PostSale` | TVPs for header / lines / payments / discounts; idempotent; FIFO deduction; returns the lots taken |
| `spu_POSV2_VoidSale` | void after payment; restores the lots |
| `spu_POSV2_OpenShift`, `spu_POSV2_CloseShift` | open and close a cashier shift (X / Z read) |
| `sp_POSV2_GetMasterDelta` | master data changed since a version |
| `sp_POSV2_GetStock` | branch availability for the terminal's copy |
| `spu_POSV2_PostShiftGL` | the GL for a shift (decision Q2) |

**Views:** `vw_POSV2_SalesJournal`, `vw_POSV2_ZRead`, and a compatibility view for the existing BIR / sales reports if decision Q4 keeps them.

## 5. Code layout

New folder **`SalesInventorySystem/POSV2/`**:

| File / folder | Holds |
|---|---|
| `PosTerminalForm.cs` | the DevExpress form: UI only, no SQL |
| `Services/PosLocalStore.cs` | local DB access, one transaction per sale |
| `Services/PosSyncService.cs` | background outbox worker; DB only, never touches a control (Known Bug #8) |
| `Services/PosMasterDataService.cs` | master-data delta download |
| `Services/PosPricingService.cs` | price levels, VAT, SC / PWD computations; pure code, unit-testable |
| `Devices/` | scale and display pole (serial), receipt printer, cash drawer |
| `Models/` | Sale, SaleLine, Payment, Discount |

SQL goes in `SQL/POSV2/` (server scripts) and `SQL/POSV2/Local/` (terminal schema, 2014-compatible).

## 6. Phases

1. **Core sale:**
   - scan / search / weigh;
   - price levels;
   - cash payment;
   - receipt;
   - local save + outbox;
   - server post + FIFO deduction;
   - terminal numbering;
   - connection indicator and outbox count on screen.
2. **Discounts and corrections:** SC / PWD / other / one-time (BIR computation), cancel line, hold / recall, void, reprint.
3. **Shift:** cash beginning, X-read, Z-read, close shift, GL posting (Q2), display pole, cash drawer.
4. **Other payments:** charge account (AR to `TransactionChargeSales`, the same pattern as sales orders), card, returns / refunds.
5. **Reports and checks:**
   - sales journal and Z-read report;
   - BIR feed (Q4);
   - Exception Center checks: outbox older than N minutes, shortages, sale posted twice, gaps in the OR series;
   - Process Trace module.

Each phase: rolled-back server tests on DEV, a local-DB test on this laptop's `ITCOREPOSFORDEMO`, then the user's UI test; STAGING on the user's go.

## 7. Decisions needed

- **Q1 — Where it runs.**
  - Which deployment and branches will use it? (Production JFC has no POS today.)
  - Do the terminals keep a local SQL Server (this one is 2014; Express 2019 or later would allow the newer SQL features)?
- **Q2 — GL timing.** Recommended: stock is deducted per sale, and the GL posts **once per shift (Z-read)**: sales, VAT-exempt sales, discounts, cash / card / AR, COGS. One ticket per sale is the alternative, but it would add thousands of GL tickets a month.
- **Q3 — Offline oversell.** Recommended: post the sale anyway, deduct what exists, and list the shortage for review. The alternative is to hold the sale until stock is fixed.
- **Q4 — Existing reports.** Recommended: new tables, plus the old POS / BIR reports rebuilt on them in phase 5. The alternative is to also write `BatchSalesSummary` / `Details`, so the old reports keep working unchanged; those tables are shared with sales orders.
- **Q5 — Scope.** The old form also has restaurant (table no.) and hotel (room / booking) options. Leave them out of V2? Recommended: yes.
