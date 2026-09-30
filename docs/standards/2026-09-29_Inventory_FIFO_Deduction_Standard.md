# Inventory FIFO Deduction: analysis and proposed standard

**Status:** approved 2026-09-29. The engine and STS V2 are built (`SQL/2026-09-29b_InvFIFO_Engine.sql`, `SQL/2026-09-29c_STS_V2_FIFOEngine.sql`, form `Orders/AddBranchOrderSTSV2`), tested on DEV in rolled-back transactions, and not yet deployed. The rules in §4 move into `CLAUDE.md` Conventions once STS V2 has passed the user's UI test.

**Answers to §6 (2026-09-29):**
1. BranchInventoryIN's proc is in another database; the user will create it here.
2. `IsWarehouse = 1` is required (ENZO's third-party storage).
3. The non-JFC STS path is still used, so the engine covers both JFC (BATCH) and non-JFC (AUTO).
4. Partial quantity is allowed on a scanned barcode.
5. Fix STS first, as a **new copy** of the form, so it can be tested side by side with the old one.
6. `IsStock`: maybe later. The user filters on `Available > 0` only.
**Date:** 2026-09-29. All procedure text was read from COREX001 (DEV); STAGING has the same procedure list.

---

## 1. What was reviewed

| Module | Form | Live procedure chain (what really runs) |
|---|---|---|
| STS Stock Transfer | `Orders/AddBranchOrderSTS.cs` `addBranchOrder()` | `CompanyProfile.CompanyName = 'JFC'`, so the form calls **`sp_AddBranchOrder_JFC` → `sp_FiFoMappingSTS_JFC` → `sp_SalesQtyToInventoryQtySTS_JFC`**. The non-JFC `sp_AddBranchOrder` → `sp_FiFoMappingSTS` → `sp_SalesQtyToInventoryQtySTS` was also reviewed. |
| Stock Out | `HOFormsDevEx/StockOutPerBarcode.cs` | `sp_GetStockOutFIFOBreakdown[ByShipment]` (preview) → `spu_PostStockOutBarcode` |
| Conversion | `HOFormsDevEx/ConversionPerBarcode.cs` | `sp_GetInventoryFIFOBreakdown[ByShipment]` (preview) → `spu_PostConversionBarcode` |
| Branch Inventory IN | `Branches/BranchInventoryIN.cs` | `sp_BranchInventoryINProcess`, **which exists in no database** (COREX001, STAGING, CORECSERP_002_DEV, VROSSTEST checked; MALLVERSE is not accessible). Its TVP `dbo.InventoryINType` and the grid's `funcview_BranchInventoryIN` are missing too. |

The database has **~15 live FIFO-deduction procedures** besides these, all hand-copied variants:
`sp_SalesQtyToInventoryQty`, `…HRI`, `…HRI_JFC`, `…EODSalesInvDeduct`, `…EODSalesInvDeductPerMachine`,
`…TransferInventory`, `sp_FiFoMapping`, `…HRI`, `…SalesInvDeduct`, `…ForJobs`, `…PerMachine`, `…StockOut`,
`…TransferInventory`, `sp_ConversionFIFO`, `sp_InventoryFIFO`, `sp_doFifo`, `sp_FiFoWithOptions[Inventory]`.
Any standard has to be something these can move onto over time, not just the four modules above.

---

## 2. There are two generations of FIFO code

### Generation A: "loop and pop" (STS, and every `sp_SalesQtyToInventoryQty*` / `sp_FiFoMapping*`)

1. The caller runs a stock check with `NOLOCK`: `SUM(Available)` for the product.
2. A mapping proc expands a BOM (`InventoryMapping` parent → children).
3. For each child, a `WHILE` loop pops the oldest lot: `TOP(1) … WITH (UPDLOCK, ROWLOCK) ORDER BY SequenceNumber`. It sets `Available`, writes a module row (`InventoryDeliveryFIFO`) and an `InventoryLedger` row, and repeats.
4. When no lot is left, the loop does **`BREAK` and carries on without an error**.
5. It is called once per scan, and each scan is its own transaction.

### Generation B: "preview, then post the exact lots" (Stock Out, Conversion; 2026-08)

1. Form methods: Scan Barcode, FIFO Auto, or FIFO Manual (by `Product||ShipmentNo||ReferenceCode`).
2. The FIFO split is **worked out beforehand** by a read-only breakdown proc, a cursor over `NOLOCK` lots that nets out lots already staged.
3. The form checks `totalReturned < qty` and stages one grid row per lot.
4. Submit sends a TVP of **exact lots** (`InventorySeqNo, Qty, Cost`) to one `spu_Post…` proc. That proc:
   - validates first;
   - rejects duplicate lots;
   - runs one set-based `UPDATE … WITH (UPDLOCK)` guarded by `Available >= Qty`, with an `@@ROWCOUNT` check;
   - sets `IsStock = 0` on exhausted lots;
   - does it all in one transaction and re-raises with `THROW`.

Generation B is the right shape and matches the `CLAUDE.md` inventory-out convention. Generation A has the bugs.

---

## 3. Findings

Severity: 🔴 wrong stock/cost possible · 🟠 integrity/UX gap · 🟡 cleanup.

### Generation A (STS)

| # | Sev | Finding | Where |
|---|---|---|---|
| A1 | 🔴 | **The loop can silently deliver less than was recorded.** When the lots run out, the pop loop does `BREAK` and no error is raised. `DeliveryDetails` still records the full `@parmqty`, so the branch receives stock the warehouse never deducted. | `sp_SalesQtyToInventoryQtySTS[_JFC]` |
| A2 | 🔴 | **The stock check can pass twice for the same stock.** It reads with `NOLOCK` and no lock is held until the pop, so two users can both pass it for the same last units. The second user then hits A1. *Checked on DEV and STAGING: 0 short lines in 12,687 STS lines since 2026-08-01. The risk exists but hasn't caused a problem yet.* | `sp_AddBranchOrder[_JFC]` |
| A3 | 🔴 | **The check and the pop use different filters.** The check requires `Available > 0` (non-JFC also requires `isStock = 1 AND IsWarehouse = 1`); the pop uses `ISNULL(Available, Quantity) > 0` and ignores `isStock`. They can disagree about how much stock there is. | both |
| A4 | 🔴 | **For a BOM product, the check looks at the wrong item.** Availability is checked for the **parent** code, but the children are what get deducted. A combo whose parent has no lots can never pass; one whose parent has lots passes without checking the children. | `sp_AddBranchOrder[_JFC]` + `sp_FiFoMappingSTS[_JFC]` |
| A5 | 🔴 | **Non-JFC overwrites `ReferenceCode = 'stsfifo'`** on every lot it touches. That destroys the batch key `Product‖ShipmentNo‖ReferenceCode` (Known Bug Pattern #7). The JFC copy has the line commented out; no lots on DEV carry `stsfifo` today. | `sp_SalesQtyToInventoryQtySTS` |
| A6 | 🔴 | **The JFC shipment scope uses `ShipmentNo` alone**, which Known Bug Pattern #7 forbids. Selecting shipment `CONVERSION` (33 lots on DEV) or `''` (2 lots) pools unrelated batches. | `…STS_JFC` |
| A7 | 🟠 | **`IsStock` is never cleared.** **29,701 of 30,825 lots have `Available ≤ 0` but `IsStock = 1`.** Every eligibility filter therefore has to add `Available > 0`, and the flag means nothing on its own. | all Generation A |
| A8 | 🟠 | One scan = one transaction. A 40-scan transfer isn't atomic: an error on scan 23 leaves 22 posted. The C# code shows the error with `"XYZ"` appended and carries on. | `AddBranchOrderSTS.cs` |
| A9 | 🟠 | Errors go through `RAISERROR(ERROR_MESSAGE())`, so every error number collapses to 50000. The message also casts quantities to `INT` ("requested 5, available 2" for 5.500 / 2.750). | all Generation A |
| A10 | 🟠 | **A quantity of 0 is accepted.** 3 zero-qty lines exist (delivery 12723 / PO 12497). | `sp_AddBranchOrder_JFC` |
| A11 | 🟠 | Line numbers come from `MAX(SeqNo)+1` under `NOLOCK` (no duplicates found yet), and non-JFC writes `DevDetSeqNo = 0`, which breaks the line ↔ FIFO link. | both |
| A12 | 🟡 | `@TotalCost` / `@iCost` are `decimal(18,3)` while `Inventory.Cost` is `(18,2)`. `AddWithValue` is used for every parameter. There are two near-identical copies (JFC and non-JFC) of each proc. | |

### Generation B (Stock Out, Conversion)

| # | Sev | Finding | Where |
|---|---|---|---|
| B1 | 🔴 | **Cost comes from the client.** `TotalCost` / the detail `Cost` come from the TVP (`SUM(Qty*Cost) FROM @Lines`), not from `Inventory.Cost` at post time. A stale grid, or a cost change between preview and submit, posts the wrong cost. This is the same family as Known Bug Pattern #10. For Conversion it feeds the output lots' cost. | `spu_PostStockOutBarcode`, `spu_PostConversionBarcode` |
| B2 | 🟠 | **No `InventoryLedger` rows**, unlike every Generation A proc. Stock-outs and conversion consumption are missing from the movement ledger. | both |
| B3 | 🟠 | **FIFO order isn't enforced at post time.** The server deducts whatever lots the client sends. If a lot changed between preview and submit, it fails safely (rowcount guard), but nothing stops a client sending non-FIFO lots for an "Auto" line. | both |
| B4 | 🟠 | **The breakdown procs return a partial list with no error when stock is short.** Each form catches it (`totalReturned < qty`), but any new caller could forget. | 4 breakdown procs |
| B5 | 🟡 | **The four breakdown procs are really two, each copied twice.** They're identical apart from the name and TVP type (`tt_StockOutStagedLots` vs `tt_ConversionStagedLots`). Each is a cursor over a `NOLOCK` read. | `sp_Get{StockOut,Inventory}FIFOBreakdown[ByShipment]` |
| B6 | 🟡 | **A lot can't be picked twice.** The breakdown nets out already-staged qty and can return a *partly* staged lot again, but the form then rejects it ("LOT ALREADY STAGED"), and the post proc rejects duplicate lots (59503/59213). A second FIFO pick of the same product fails whenever the oldest lot was only partly used. | forms + post procs |
| B7 | 🟡 | A barcode scan always takes the **whole** `Available` of the lot; it can't take part of one. That may be intended for per-piece barcodes; to be confirmed. | forms |

### BranchInventoryIN

| # | Sev | Finding |
|---|---|---|
| C1 | 🔴 | **The procedure it calls doesn't exist** in any database I can reach, and neither do its TVP type or the grid function. The form fails on load and on Save. It is on the menu (`Main.cs:3571`). **I need its source or its intended database before it can be analysed.** |
| C2 | 🟠 | The two variance calculations use opposite signs: `CellValueChanged` shows `Ending − NewQty`, but `BuildPODetailsTable_ByQty` sends `NewQty − Ending`. |
| C3 | 🟠 | It is a physical count ("set to NewQty"), so a negative variance is a deduction and a positive one is a receipt. Under the standard, the negative side must go through the same FIFO engine; the positive side is a receipt and isn't covered. |

### What's good and should be kept

- **Generation B's post procs:** validate before writing; one TVP call; the `UPDLOCK` + `Available >= Qty` + `@@ROWCOUNT` guard; `IsStock = 0` cleanup; `THROW`; `XACT_ABORT`.
- **The composite batch key** `Product‖ShipmentNo‖ReferenceCode` for Manual FIFO.
- **The oldest-first rule:** `ORDER BY SequenceNumber ASC` everywhere. Every module agrees on what "first in" means.
- **Generation A's savepoint pattern** (`SAVE TRANSACTION` when nested) and its per-lot `InventoryLedger` row.

---

## 4. Proposed standard

### 4.1 Rules (these would go into CLAUDE.md)

1. **One engine.** Every inventory-reducing post goes through **one shared deduction proc**, `dbo.spu_InvFIFO_Deduct`. Modules don't write their own lot-picking loop, pop, or `UPDATE Inventory SET Available`.
2. **Oldest first.** FIFO means oldest `SequenceNumber` first, within **Branch + Product** (Auto) or **Branch + Product + ShipmentNo + ReferenceCode** (Manual/Batch). Never scope by `ShipmentNo` alone.
3. **One definition of an eligible lot**, in one inline TVF used everywhere (`dbo.fn_InvEligibleLots`): `Branch = @Branch AND Available > 0 AND IsWarehouse = 1`.
   - `IsWarehouse = 1` is required *(decided 2026-09-29)*: at ENZO, head-office stock held in third-party storage is `IsWarehouse = 0` until it's pulled into the commissary. At JFC every lot is `1`, so it changes nothing there.
   - `IsStock` is **not** a filter (the legacy procs never cleared it), but the engine keeps it right: `0` when a lot empties, `1` when one is restored.
   - `ISNULL(Available, Quantity)` is dropped: 0 lots have a NULL `Available`.
4. **All or nothing.** A shortfall **throws**; it never `BREAK`s and never posts part of a quantity. Checking and deducting happen **under the same lock** (`UPDLOCK, HOLDLOCK`), in the caller's transaction. A `NOLOCK` pre-check is allowed only as a fast, user-friendly early error, never as the real check.
5. **The server decides lots and cost.** For Auto/Batch lines the server allocates lots at post time. For scanned lots it re-checks them. **Cost is always read from `Inventory.Cost` under the lock**; a client-supplied cost is display-only.
6. **One submit, one transaction.** Staged lines go in a TVP to the module's own `spu_Post…`, which opens the transaction, writes its own header and detail tables, calls the engine once, and commits. No per-scan posting.
7. **Clean up and log.** A lot that reaches `Available ≤ 0` gets `IsStock = 0`. Every lot touched gets an `InventoryLedger` row, with `QtyOut`, `Cost`, and a remark in the form `<MODULE> <RefNo>`.
8. **Don't touch lot identity.** The engine never changes `ShipmentNo`, `ReferenceCode`, `Barcode` or `Cost` on the source lot.
9. **Reversal uses the saved allocation.** It restores exactly the lots and quantities saved at post time: `Available += Qty`, `IsStock = 1`, and an `InventoryLedger` `QtyIn` row. It never re-runs FIFO.
10. **Errors:** `THROW` with numbers in **59800–59849** (unused today); re-raise with bare `THROW;`. Quantities in messages use `N3`, not `INT`.
11. **Each module keeps its own tables** (per CLAUDE.md). The engine returns the per-lot allocation to the caller, and the caller stores it in its own detail/FIFO table.

### 4.2 Components

| Object | Kind | Replaces | Purpose |
|---|---|---|---|
| `dbo.tt_InvDeductLine` | TVP type | `tt_StockOutBarcodeLines`, `tt_ConversionBarcodeSourceLines`, `tt_*StagedLots` (new code only; the old types stay for old procs) | `LineNo INT, ProductCode, Qty DECIMAL(18,3), Mode ('LOT','AUTO','BATCH'), InventorySeqNo INT NULL, ShipmentNo NULL, ReferenceCode NULL` |
| `dbo.fn_InvEligibleLots(@Branch)` | inline TVF | the filters copied into every proc | Rule 3, in one place |
| `dbo.sp_InvFIFO_Preview` | read-only proc | the 4 breakdown procs | Same allocation logic as the engine, read-only. Returns per-lot rows **plus a `ShortQty` column** instead of a silent partial list (fixes B4). Takes already-staged lines, so partly staged lots work (fixes B6). |
| `dbo.spu_InvFIFO_Deduct` | engine proc | every pop loop / lot `UPDATE` | Called **inside** the caller's transaction (throws if `@@TRANCOUNT = 0`). Locks, allocates, checks for shortfall, deducts, clears `IsStock`, writes `InventoryLedger`, and returns the allocation. |
| `dbo.spu_InvFIFO_Restore` | engine proc | hand-written reversals | Takes the module's saved allocation rows and restores them (rule 9). |
| `dbo.fn_InvExpandBOM(@Product, @Qty)` | inline TVF | the BOM block in `sp_FiFoMapping*` | For STS/sales only: expands a parent into child lines **before** the engine, so the check covers the children (fixes A4). |
| `Classes/InventoryFifo.cs` | C# helper | copied `GetFifoBreakdown*`/`BuildStagedLotsTVP` in each form | Typed `Preview(...)`, `BuildDeductTVP(...)` and error mapping. Forms keep the Scan / FIFO Auto / FIFO Manual UI from CLAUDE.md. |

### 4.3 Engine contract (sketch)

```sql
-- Caller (a module's spu_Post...) owns the transaction and the allocation table:
CREATE TABLE #InvAlloc (
    LineNo         INT            NOT NULL,
    InventorySeqNo INT            NOT NULL,
    ProductCode    VARCHAR(50)    NOT NULL,
    ShipmentNo     VARCHAR(10)    NULL,
    ReferenceCode  VARCHAR(50)    NULL,
    Qty            DECIMAL(18,3)  NOT NULL,
    Cost           DECIMAL(18,2)  NOT NULL,   -- from Inventory.Cost under lock
    BegQty         DECIMAL(18,3)  NOT NULL,
    EndQty         DECIMAL(18,3)  NOT NULL
);

BEGIN TRANSACTION;
    -- module header/detail inserts ...
    EXEC dbo.spu_InvFIFO_Deduct
        @BranchCode   = @BranchCode,
        @Lines        = @Lines,            -- dbo.tt_InvDeductLine
        @SourceModule = 'STOCKOUT',        -- ledger remark prefix
        @SourceRefNo  = @RefNo,
        @User         = @PreparedBy;       -- fills #InvAlloc
    INSERT INTO dbo.StockOutBarcodeDetails (...) SELECT ... FROM #InvAlloc;   -- module's own table
COMMIT TRANSACTION;
```

Inside the engine:
1. `IF @@TRANCOUNT = 0 THROW 59800`.
2. Validate: qty > 0 (59801); mode and its required keys present (59802); duplicate LOT lines (59803).
3. Lock the candidate lots once:
   `SELECT … INTO #Lots FROM dbo.Inventory WITH (UPDLOCK, HOLDLOCK, ROWLOCK) WHERE <eligible> AND Product IN (products in @Lines)`.
4. Allocate, in this order: **LOT** lines take their named lot first. Then **BATCH** lines take from their batch. Then **AUTO** lines take oldest-first from what's left.
   - Within one line, allocation is set-based, using a running total:
     `cum = SUM(Remaining) OVER (ORDER BY SequenceNumber ROWS UNBOUNDED PRECEDING)`,
     `take = CASE WHEN cum − Remaining >= need THEN 0 WHEN cum <= need THEN Remaining ELSE need − (cum − Remaining) END`.
   - Works at compatibility level 120. Loop over **lines** only (a handful), never over lots one at a time.
5. Any line with `SUM(take) < Qty` → `THROW 59804`, with product, requested and available as `N3`.
6. `UPDATE Inventory … SET Available = Available − a.Qty WHERE Available >= a.Qty`, then check `@@ROWCOUNT` (59805). Then set `IsStock = 0` where `Available <= 0`.
7. `INSERT InventoryLedger` for each allocated lot.

### 4.4 How each module maps onto it

| Module | Change |
|---|---|
| Stock Out | Smallest change. The post proc keeps its header/detail tables and swaps its own `UPDATE` for the engine. Cost comes from `#InvAlloc` (fixes B1), the ledger is added (B2), and FIFO is re-derived at post time (B3). The form's two breakdown calls become `InventoryFifo.Preview`. |
| Conversion | Same as Stock Out. The output lots' cost basis is computed from `#InvAlloc.Cost`, not the TVP. |
| STS (JFC) | The deduction in `sp_AddBranchOrder_JFC` becomes: expand the BOM → engine (still per scan at first, so the UI doesn't change). That fixes A1–A4, A6, A7, A9 and A10 at once. The **UI move** to staged grid + one Submit (A8) is a separate, later phase, because it changes how warehouse staff work. |
| BranchInventoryIN | Negative variances → engine (AUTO lines). Positive variances → receipt path (out of scope). **Blocked until the proc source is found (C1).** |
| Other ~15 procs | Inventory them and move them over one at a time as each module is touched. Don't bulk-rewrite. The old ones keep working and get backed up (`_OLD_<timestamp>`) when replaced. |

---

## 5. Proposed phases

| Phase | Scope | Risk |
|---|---|---|
| **0: Stop-gap on live STS** (optional, small) | In `sp_SalesQtyToInventoryQtySTS_JFC`: after the loop, `IF @RunningQtySold > 0 THROW`. In `sp_AddBranchOrder_JFC`: `@parmqty > 0` check; `UPDLOCK, HOLDLOCK` on the stock check with the same filter as the pop. Closes A1–A3 and A10 without redesigning anything. | low |
| **1: Build the engine** | `tt_InvDeductLine`, `fn_InvEligibleLots`, `sp_InvFIFO_Preview`, `spu_InvFIFO_Deduct`, `spu_InvFIFO_Restore`, `fn_InvExpandBOM`. Tested on DEV in rolled-back transactions: exact fit, spanning lots, shortfall, two sessions at once, BATCH scope with `CONVERSION`/`''` shipments, reversal. | none (nothing calls it yet) |
| **2: Stock Out + Conversion** | Move both post procs and forms onto the engine and `InventoryFifo.cs`. Retire the 4 breakdown procs (kept as backups). | medium: the exe and SQL must deploy together |
| **3: STS (JFC)** | Route `sp_AddBranchOrder_JFC` through BOM expansion + engine. Then decide on staged-grid Submit. | medium-high: daily warehouse flow |
| **4: BranchInventoryIN** | After C1 is resolved. | unknown |
| **5+: others** | As each module is touched. | per module |

---

## 6. Questions for the owner

1. **BranchInventoryIN:** where is `sp_BranchInventoryINProcess` (and `InventoryINType`, `funcview_BranchInventoryIN`)? Another client's database, or not written yet?
2. **`IsWarehouse`:** should FIFO ever skip `IsWarehouse = 0` lots? All lots are `1` today, so leaving it out changes nothing now.
3. **Non-JFC STS path:** is `sp_AddBranchOrder` (non-JFC) still deployed to any other client? If not, only the JFC chain needs moving over.
4. **Barcode scan:** should a scan always take the whole lot (B7), or should staff be able to type a partial quantity for a scanned barcode?
5. **Phase 0:** do you want the stop-gap fix on the live STS procs now, ahead of the engine?
6. **Old `IsStock` flags:** should the 29,701 exhausted lots still marked `IsStock = 1` be cleaned up once (`IsStock = 0 WHERE Available <= 0`)? The engine doesn't need it, but reports that filter on `IsStock` would then be right.
