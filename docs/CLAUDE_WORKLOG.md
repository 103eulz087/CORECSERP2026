# Claude Work Log (session handoff)

Imported into every Claude Code session via `CLAUDE.md`, so a fresh terminal on any
machine picks up where the last one stopped. **Keep it short and current:** update
the Status / Open items when something changes; move finished items to "Done" in one
line. Durable rules belong in `CLAUDE.md` itself, not here.

Last updated: **2026-10-03** (scripts 13, 14, 24–27, 34, 35 deployed to STAGING)

---

## Deployment status

**DEV = `COREX001`** on `corex.itcoreapps.com` (default instance). Unchanged.
STAGING = `CORECSJFC2026_STAGING` (default instance; the "STAGING" column below).
**Moving (2026-10-04)** to a new instance: `corex.itcoreapps.com,6601`, database `CORECSJFC2026_STAGING` (same name as today's, on the new instance). Not live yet; once it exists, re-check every script below on it.
PRODUCTION = `PRODJFC_COREX` on `corex.itcoreapps.com,7701`. The old DEV, `CORECSERP_002_DEV`, is no longer a target. See CLAUDE.md.
Per CLAUDE.md, STAGING changes need the user's confirmation first.

Status checked 2026-09-25 by probing each script's actual feature in each database:

| # | Script (`SQL/`) | COREX001 (DEV) | STAGING |
|---|---|---|---|
| 1 | `2026-09-24_SupplierPayment_OverpaymentCredit.sql` | ✅ | ✅ (applied outside this log) |
| 2 | `2026-09-24c_SupplierPayment_OverpaymentCredit_ExpenseSingle.sql` | ✅ | ✅ |
| 3 | `2026-09-25_SupplierPayment_OverpaymentCredit_ExpenseMultiBranch.sql` | ✅ | ✅ |
| 4 | `2026-09-25b_CancelledChequesCS_ExpenseMasterNullBalance.sql` | ✅ | ✅ |
| 5 | `2026-09-24_ExpenseInventoryCosting_InventoryLegsOnly.sql` | ✅ | ✅ |
| 6 | `2026-09-24b_ItemCostingRecon_MasterDetail.sql` | ✅ | ✅ |
| 7 | `2026-09-25c_CashReceipts_SalesJournal_BranchFilter.sql` | ✅ (incl. EWT) | ✅ |
| 8 | `2026-09-25d_ExpenseManualMultiBranch_PreserveLineOrder.sql` | ✅ | ✅ found applied 2026-09-26 00:54 (same as DEV) — STAGING users need the new exe |
| 9 | `2026-09-25e_ManualJV_PreserveLineOrder.sql` | ✅ | ✅ found applied 2026-09-26 00:53 (same as DEV) — STAGING users need the new exe |
| 10 | `2026-09-25f_IncomeStatementPivot_HeadOfficeFirst.sql` | ✅ | ✅ found applied 2026-09-26 00:54 (same as DEV) |
| 11 | `2026-09-26_ItemCostingRecon_ExpenseTickets.sql` | ✅ (by user, 14:24) | ✅ (by user, 14:56) |
| 12 | `2026-09-29_EditSingleExpense_NoDoubleCosting.sql` | ✅ already applied 2026-09-29 14:50 (outside this log); matches the script, backup = original; smoke-tested 2026-09-30 | ✅ found applied 2026-09-29 22:30 (same as DEV) |
| 13 | `2026-09-29b_InvFIFO_Engine.sql` | ✅ 2026-09-30 13:33 (smoke-tested, rolled back) | ✅ 2026-10-03 22:56, user-approved: all 8 (35, 13, 14, 24, 25, 26, 27, 34) in ONE transaction; the 2 table types were created committed first. Rehearsed rolled back first; definitions = DEV (whitespace only). Rolled-back tests on the live procs, with in-transaction fixture lots copied from DEV (scratchpad `h/stg_*.ps1`): STS V2 V1–V10, Sales V2 V1–V11, old-form SO A–H, old-form STS S1–S11 all tie or PASS. Exception Center: only the known 11911 / 11913 / 14100 (T02, T05) and SO 13902 (X01). Works with the current exe; the new exe adds the V2 screens and the summed receive screen |
| 14 | `2026-09-29c_STS_V2_FIFOEngine.sql` (needs 13) | ✅ 2026-09-30 13:33 | ✅ 2026-10-03 22:56 (see 13) |
| 15 | `2026-09-30_GL_RealTime_Reports.sql` | ✅ 2026-09-30 23:08 (smoke-tested) | ✅ found applied 2026-09-30 23:34 (same as DEV) |
| 16 | `2026-09-30_GL_PeriodLock.sql` | ✅ 2026-09-30 23:08; nothing closed yet; two-session race test passed | ✅ found applied 2026-09-30 23:34 (same as DEV); no month closed yet |
| 17 | `2026-09-30b_SupplierLedger_Rebuild.sql` | ✅ 2026-09-30 23:24 (829 rows / 33 accounts fixed; audit now 0/0/0) | ✅ 2026-09-30 23:26, user-approved (801 rows / 38 accounts fixed; rehearsed rolled back first; audit now 0/0/0) |
| 18 | `2026-09-30c_ClientLedger_RecalcTrigger.sql` | ✅ 2026-09-30 (3 rows / 2 accounts fixed; audit now 0/0/0) | ✅ 2026-09-30, user-approved (6 rows / 2 accounts fixed; rehearsed rolled back first; audit now 0/0/0) |
| 19 | `2026-10-01_SalesOrder_Lifecycle_Fixes.sql` | ✅ 2026-10-01 13:22 (one transaction; 10 lifecycle scenarios re-tested on the live procs) | ✅ 2026-10-01 21:52, run by the user; verified same as DEV |
| 20 | `2026-10-01b_STS_Lifecycle_Fixes.sql` (needs 19) | ✅ 2026-10-01 (one transaction; 9 STS scenarios re-tested on the live procs) | ✅ 2026-10-01 21:52, run by the user; verified same as DEV |
| 21 | `2026-10-01c_STS_InTransit_Correction.sql` (data fix; needs 20) | ✅ 2026-10-01: corrected 11699, 11700, 11702; skipped 11701 (stock never restored, DEV copy only); residuals now empty | — not needed: checked 2026-10-01 after 19/20/23, nothing to correct. The duplicate tickets 18547 / 18554 had been deleted by hand (master + details); each PO's IT-HO-VATEX equals its live FIFO cost |
| 23 | `2026-10-01e_GL_AllVatExempt.sql` (needs 19 + 20; run before 21) | ✅ 2026-10-01 21:22 (sales A/C/D/E/G + STS S1/S2/S3/S5/S8 re-tested rolled back: no VAT legs, all tie); script 21 (updated) re-run: VAT reclass on 11699/11700/11702 reversed (tickets 15881–15886) | ✅ 2026-10-01 21:53, run by the user; verified same as DEV (all 5 procs carry the patch note) |
| 22 | `2026-10-01d_SalesCost_SeptemberFinalCost.sql` (data fix for STAGING) | — | ✅ 2026-10-01, user-approved (rehearsed rolled back first): 20 FIFO rows, 16 SI-VATEX tickets, COGS −3,375.36; backups `CostFix_20261001_*` |
| 24 | `2026-10-01f_STS_V2_Alignment.sql` (needs 13 + 14 + 20 + 23; patches 4 procs) | ✅ 2026-10-02 09:5x (rehearsed rolled back first). Test script fixed (PRINT with a subquery doesn't compile, 1046; NULL barcode on AUTO lines) and run on request 13435 as anthony: 18/18 PASS, nothing left behind. Old-form STS scenarios S1/S2/S3/S5/S8/S9 re-run on the live procs: all tie. Exception Center: only the known 11701 | ✅ 2026-10-03 22:56 (see 13) |
| 25 | `2026-10-02_STS_ReceiveFIFO_OneRowPerLine.sql` | ✅ 2026-10-02 11:12 (bug reproduced, then fixed; S1/S8/S10/S11 rolled back, all tie) | ✅ 2026-10-03 22:56 (see 13) |
| 33 | `2026-10-02i_CheckVoucher_CVNo.sql` (needs 31; `CheckVoucher.CVNo` backfilled from NotedBy; `sp_Payment_CreateVoucherHeader` / `sp_PostCashAdvance` / `sp_AddPaymentSupplierCompound` write it; `sp_BankRecon_GetPeriod` recreated: OC CV # from CVNo, reversed items (REVERSED / VOIDED%) not listed; removes 32) | ✅ 2026-10-02 (65 vouchers) | ✅ 2026-10-02, user-approved (rehearsed rolled back first: 176 vouchers; new voucher gets CVNo; 84 reversed rows hidden). Works with the current exe; new exe 2026-10-03 |
| 32 | `2026-10-02h_VoucherCVNo.sql` — **superseded by 33, never on STAGING; removed from DEV by 33** | (removed) | — do not run |
| 31 | `2026-10-02g_BankRecon_OC_CVNo.sql` (needs 30; OC rows add CV #: cheque = CheckVoucher.NotedBy, telegraphic / cash = ControlNo) | ✅ 2026-10-02 | ✅ 2026-10-02, user-approved (rehearsed rolled back first). No exe needed |
| 30 | `2026-10-02f_BankRecon_OC_ControlNo.sql` (needs 29; OC grid: ControlNo / CheckNo / voucher no. / source from the issuing voucher; patches the OC block only) | ✅ 2026-10-02 | ✅ 2026-10-02, user-approved (rehearsed rolled back first: AP 140 / 143 with control no.; 174 with cheque no.). No exe needed |
| 29 | `2026-10-02e_BankRecon_ControlNo.sql` (Bank Recon control no.; `@ItemType` optional = 'DIT' so any exe works) | ✅ 2026-10-02 (2,663 rows filled) | ✅ 2026-10-02, user-approved (4,980 rows filled; rehearsed rolled back incl. old- and new-exe Bulk Resolve calls). No exe needed; new exe only adds captions |
| 28 | `2026-10-02d_SalesViews_OneRowPerLine.sql` (fixes the user's 10-02 edits of `funcview_ForDeliveryDetails` / `funcview_ProcessOrderItemsSales`: keeps their one-row-per-line fix; puts `BarcodeNo` back — old sales and STS forms print / cancel / return by it; shows returned lines again; OUTER APPLY for the lot ReferenceCode) | ✅ 2026-10-02 15:20 | ✅ 2026-10-02 15:20, user-approved (rehearsed rolled back: 342 → 351 rows = +9 returned lines, all of the user's rows identical, no duplicates) |
| 27 | `2026-10-02c_SalesOrder_V2_FIFOEngine.sql` (needs 13 + 19 + 23) | ✅ 2026-10-02 (rehearsed rolled back; old-form A–H + V2 harness pass) | ✅ 2026-10-03 22:56 (see 13) |
| 26 | `2026-10-02b_STS_ReceiveFIFO_PerLot.sql` (needs 25) | ✅ 2026-10-02 13:06 (S1/S5/S6/S8/S10/S11 rolled back, all tie) | ✅ 2026-10-03 22:56 (see 13) |
| 35 | `2026-10-03b_SalesInvoiceJFC_NoLotDuplication.sql` (Sales Invoice view: a line taken from N lots showed N × its qty / amount; discount once per product) | ✅ 2026-10-03 (rehearsed: new output = delivery lines on all 4,532 POs; 6 POs change) | ✅ 2026-10-03 22:56 (see 13) |
| 34 | `2026-10-03_STS_V2_NoBarcodeFIFO_ReceiveGrouped.sql` (needs 13, 14, 24, 26, 27; Feature 22) | ✅ 2026-10-03 14:11 (one transaction; V1–V10, S1–S11, Sales V2 harness rolled back first; Exception Center: nothing new) | ✅ 2026-10-03 22:56 (see 13) |
| 36 | `2026-10-04_SalesOrder_PartialReturn.sql` (Feature 17; type `tt_ReturnSalesOrderQty` created committed first) | ✅ 2026-10-04 14:33 (one transaction with post-check; sp-reviewer fixes in; P1–P17 + old A–H rolled back on the live procs = identical to the rehearsal; Exception Center: nothing new, X05 = 0) | ✅ 2026-10-07 10:43 by Claude on 6601, user-approved. The type was created committed first. Rehearsed rolled back with in-transaction fixture lots: P1–P17 and old A–H identical to DEV. Live rerun = rehearsal (only lot IDs differ). Exception Center: only the known 11911 / 11913 / 14100 / 13902. The new exe adds the Return Qty column |
| 37 | `2026-10-05_InvFIFO_StickerRule.sql` (FIFO skips stickered lots only, A01 / 19-digit; new `fn_InvIsStickerBarcode`; Feature 22) | ✅ 2026-10-05 18:19 (one transaction with post-check; rehearsed rolled back; STS V2 + Sales V2 harnesses live = rehearsal). sp-reviewer: no blocker; its hardening (strip CR/LF/TAB/NBSP, case-insensitive A01) is in script 37 now and reached DEV via `2026-10-05b_StickerRule_Hardening_DEVonly.sql` (19:xx, backup `_OLD_10052026190000`) | ✅ by the user 2026-10-05; verified 2026-10-07 on 6601 (same content as DEV, hardening included) |
| 38 | `2026-10-06_BankRecon_PeriodSummary.sql` (new read-only `sp_BankRecon_GetPeriodSummary`, Bank Recon summary view) | ✅ 2026-10-06; parity with `sp_BankRecon_GetPeriod` on all 25 DEV periods (items, Debit = DIT total, Credit = OC total, batch counts, uncleared IDs) | ✅ by the user; verified 2026-10-07 on 6601 (identical to DEV) |
| 39 | `2026-10-07_BankRecon_GLBalance_Header.sql` (Bank Recon: this month's header, GL ending balance across all branches, one set of figures; new `fn_BankRecon_GLBalance` + `fn_BankRecon_Figures`) | ✅ 2026-10-07. Rehearsed rolled back. GL = an independent ledger sum on all 25 headers. Screen math = proc = lock check on all 25. Rolled-back Save -> reconcile -> Lock stored the GL snapshot; a locked period refuses Save (93001); an out-of-balance period refuses Lock (93005) | ✅ by the user; verified 2026-10-07 on 6601 (same content as DEV; BDO Aug GL −15,933,885.11 = ledger). The new exe snaps Period End to month end |
| 40 | `2026-10-07b_GLConsolidated_AllLinesOnce.sql` (GL Consolidated report `sp_rpt_GeneralLedger_WithRunningBal`: each ticket line once, reversals included) | ✅ 2026-10-07 10:31. Rehearsed rolled back: ENDING = ledger on all 196 accounts for Jul / Aug / Sep / Jan–Oct, all branches and branches 888 / 001; Aug lists 36,345 lines = ledger | ✅ 2026-10-07 10:40 by Claude on 6601, user-approved (rehearsed rolled back first). Live: Aug ENDING = ledger on all 196 accounts; BDO PESO1 −15,933,885.11 = Bank Recon |
| 41 | `2026-10-07c_BankReconReport_SameAsScreen.sql` (Bank Reconciliation report = the Bank Recon screen: GL across all branches, bank-side items, open items by recon period, difference = bank − book) | ✅ 2026-10-07; report summary = `fn_BankRecon_Figures` on all 25 headers (rehearsed, then committed only if still 0 mismatches) | ✅ 2026-10-07, same test (25 / 25), user-approved |
| 42 | `2026-10-07d_BankRecon_July_PeachtreeBF.sql` (data only: Peachtree July uncleared items as a balance forward; see Feature 21) | ✅ 2026-10-07 14:55, run by the user; verified same as STAGING |
| 43 | `2026-10-07e_AR_BalanceForward_PartPaidFix.sql` (data only: AR balance-forward rows loaded at the invoice amount; see Feature 9 "⚠️ Urgent") | ⏳ rehearsed rolled back: 760 rows; all 671 BF customers then tie (account = ledger = open invoices) | ✅ run by the user (DEV 19:08, STAGING 19:09); 671 / 671 tie. Report for the accountants: `docs/reports/2026-10-07_AR_BalanceForward_Correction_STAGING.xlsx` (not in git) |
| 44 | `2026-10-08_BankRecon_DataFix_DupTransfer_AugCheques_JV32412.sql` (data only; ReconIDs are PRODUCTION's) | — (DEV has different data) | ✅ 2026-10-08 by Claude, user-approved (rehearsed rolled back first). 14 rows: duplicate transfer 13157 voided (BDO1 OC / BDO2 DIT 1,294,034.25), 11 BDO2 cheques (2,469,007.48) moved to the August period, JV 32412 OC 3,746.25 → 383,499.06. ⏳ PRODUCTION: the user runs the same script |
| 45 | `2026-10-08b_JV_BankRecon_OneItemPerAccount.sql` (`sp_JV_PostBankReconForLines`: one item per JV, bank account and side; Known Bug #9) | ✅ 2026-10-08 (old vs new on all 19 bank JVs: 29 items identical) | ✅ 2026-10-08 (25 JVs: 47 identical, 32412 now full). ⏳ PRODUCTION: the user runs it; no exe change |
| 46 | `2026-10-08c_BankRecon_ClearedPeriod.sql` (new column `BankStatementRecon.ClearedPeriodEnd`; open for P = uncleared OR cleared after P; lock check over the periods that would change; patched fn_BankRecon_Figures / GetPeriod / GetPeriodSummary / report / AutoMatch; ResolveItem / BulkResolve / ResolveAutoDebitItem get optional `@PeriodEnd`; backups `_OLD_10082026180000`) | ✅ 2026-10-08 21:5x. Rolled-back S1–S14 + parity (29 periods / 6,806 screen rows identical) all PASS first | ✅ 2026-10-08, user-approved (rehearsed rolled back first: S1–S14 + parity 34 periods / 19,759 rows PASS). ⏳ PRODUCTION: user's option A = run 44, 45, 46 and give the accountant the new exe before the BDO PESO 1 August work. Works with the current exe too (ticks go to the item's own period, as before) |
| 48 | `2026-10-08e_BankRecon_ClearedPeriod_NoSilentMove.sql` (needs 46; from the 10-08 reviews: ticking an item already cleared in a later month is refused, 93013; Bulk leaves already-cleared items alone; old-exe stamp = own period as stored; backups `_OLD_10082026220000`) | ✅ 2026-10-08 (S1–S14 + parity pass; S11 now refused 93013 as intended; S15 bulk skip PASS) | ✅ 2026-10-08 by Claude, user-approved; verify script 08z all OK. PRODUCTION: run by the user 10-08 (with 44, 45, 46), verification with 08z pending |
| 49 | `2026-10-09_BankRecon_BulkUnresolve.sql` (new `sp_BankRecon_BulkUnresolveItems`, all or nothing: unclears hand-cleared items of the month on screen; skips + counts other-month / not cleared / system-closed; 93113 if a locked period would change) | ✅ 2026-10-09 (U1–U7 rolled back first, all PASS) | ✅ run by the user on STAGING and PRODUCTION (2026-10-09); needs the new exe (10:32) to be used |
| 50 | `2026-10-09b_BankRecon_ReversalInSourceMonth_DataFix.sql` (data only, production's tickets: 18 reversal tickets of 12 references re-dated to their source entry's date, + ledger reversal rows + 16 recon items; 5 `_RevDate_Backup_20261009` tables) | — (DEV has different data) | ✅ 2026-10-09 14:3x by Claude, user-approved (rehearsed rolled back first; live = rehearsal: 18 tickets / 38 lines, 12 SL + 1 CL rows, 16 recon items; later-month reversals 0). ✅ PRODUCTION: run by the user 2026-10-09 |
| 51 | `2026-10-09c_Reversal_SourceMonthDate.sql` (reversals dated like their source entry: `sp_ReverseTicketsAP`, `sp_ReverseCashAdvanceEntry`, ledger rows in `sp_CancelledChequesCS` / `sp_ReversePaymentClient`; backups `_OLD_10092026150000`; no exe change) | ✅ 2026-10-09. Rolled back first: cheque 690, cash advance 712 and AR 6883 reversed with the source dates; a closed August refuses (59900) | ✅ 2026-10-09 14:34 by Claude, user-approved (rehearsed rolled back first). ✅ PRODUCTION: run by the user 2026-10-09 |
| 52 | `2026-10-09d_ReverseApprovedExpense_SourceDate.sql` (same rule for `sp_ReverseApprovedExpense`, ViewExpenseDevEx: reversal ticket + lines dated like the expense, supplier-ledger reversal row = the reversed row's TransactionDate; backup `_OLD_10092026170000`; no exe change) | ✅ 2026-10-09. Rolled back first: expense 32475 reversed dated 09-29, ledger txdate 09-29; a closed September refuses (59900) | ✅ 2026-10-09 14:45 by Claude, user-approved (rehearsed rolled back first). ✅ PRODUCTION: run by the user 2026-10-09 |
| 53 | `2026-10-10_ItemCostingReport_Detail_SoldReference.sql` (`sp_rpt_ItemCostingReport_Detail`, Item Costing Report movement ledger: Sold Reference = DeliverySummary.InvoiceNo + " | " + customer BranchCode-CustomerName (PurchaseOrderSummary.Customer -> Customers); Transfer = PO no.; anchor patch, backup `_OLD_10102026120000`. C#: `Reporting/ItemCostingReport.cs` hides BranchName) | ✅ 2026-10-10 (old vs new rolled back first: 13,824 rows, same totals and lot endings) | ✅ 2026-10-10 14:58 by Claude, user-approved (rehearsed rolled back first; live: 15,626 rows, same totals as before, 13,931 / 13,963 sales with a customer). ⏳ PRODUCTION: the user runs it; the new exe hides BranchName |
| 54 | `2026-10-10b_Inventory_CostFix_Lots1109_1110.sql` (data only, production lots: 1109 / 1110 back to their cost at the 09-11 sale, 229.87 / 109.50. They had +54,922,375.00 = expense 17959's inventory leg 2,746,118.75 / 0.05 kg remaining, a second application of a cost already in lot 1112 / shipment 10955. Nothing moved since, so no GL; backup `Inventory_CostFix_Backup_20261010`) | — (DEV has different data) | ✅ 2026-10-10 by Claude, user-approved (rehearsed rolled back first): 1109 = 229.87, 1110 = 109.50, backup table created, no lot above 100,000. ⏳ PRODUCTION: the user runs it (before the 0.05 kg on lot 1109 moves) |
| 55 | `2026-10-12_SupplierPayment_RecordCancelledCheque.sql` (new `sp_RecordCancelledCheque`: a spoiled / misprinted / lost cheque uses up its cheque no., a CV no. (same rule as the screen), a voucher no. and a reference no.; one CheckVoucher row (amount 0, PaidTo CANCELLED, voided) + a CheckVoucherCancelled log row; no GL, recon, AP or ledger rows; a number already used on the bank is refused 60607, older out-of-sequence numbers allowed. C#: `SupplierPaymentDevEx` "Cancelled Cheque…" button, CANCELLED supplier hidden, the next-cheque suggestion skips every number already used on the bank) | ✅ 2026-10-12 (C1–C6 rolled back first, all as intended) | ✅ 2026-10-12 by Claude, user-approved (C1–C6 rehearsed rolled back first, same results as DEV). ⏳ PRODUCTION: the user runs it; run it with 56; users need the new exe (11:21) |
| 56 | `2026-10-12b_RecordCancelledCheque_CVNoField.sql` (needs 55: `sp_RecordCancelledCheque` gets an optional @CVNo, the CV no. typed in the new "CV no." field; blank = next of the series; a CV no. already used is refused 60610; backup `_OLD_10122026160000`) | ✅ 2026-10-12 (D1–D5 rolled back first) | ✅ 2026-10-12 by Claude, user-approved (D1–D5 rehearsed rolled back first). ⏳ PRODUCTION: the user runs 55 + 56 together; **the exe from 11:21 on sends @CVNo, so it needs 56** |
| 57 | `2026-10-12c_CancelledCheque_ListEdit.sql` (needs 55 + 56: new `sp_GetCancelledCheques` (list), `sp_EditCancelledCheque` (typo fixes: bank, cheque no., date, CV no., reason, remarks; only records made by sp_RecordCancelledCheque, 60621; another voucher's cheque no. 60622 / CV no. 60623 refused), table `CancelledChequeEditLog` (old / new values, who, when). C#: "Cancelled Cheque…" opens the list with New / Edit) | ✅ 2026-10-12 (E1–E6 rolled back first) | ✅ 2026-10-12 by Claude, user-approved (E1–E6 rehearsed rolled back first; the list shows the test record 2384564 / CV2610-001BDO2384564 made in the app). ⏳ PRODUCTION: the user runs 55 → 56 → 57, then the exe from 12:38 |
| 58 | `POSV2/2026-10-12_POSV2_01_Types.sql` (POS V2 phases 1–4: TVPs `tt_POSV2_SaleLine`, `tt_POSV2_Payment`, `tt_POSV2_SaleDiscount`, `tt_POSV2_ReturnLine`; run before 59) | ✅ 2026-10-12 | ⏳ with 59 |
| 59 | `POSV2/2026-10-12_POSV2_02_Server.sql` (POS V2 phases 1–5: tables `POSV2_Terminal / Shift / Sale / SaleLine / SaleLot / Payment / Shortage / DiscountType / SaleDiscount / Supervisor(Log) / Return / ReturnLine / ReturnLot` + the `POSV2-SHIFT` JournalEntryMapping rows + COA 60340; charge sales write TransactionChargeSales + ClientLedger; `spu_POSV2_RegisterTerminal`, `sp_POSV2_GetProducts`, `sp_POSV2_GetStock`, `spu_POSV2_PostSale` (idempotent by SaleGUID, FIFO deduction via the engine, short stock → POSV2_Shortage); new objects only) | ✅ 2026-10-12, re-created with phase 3 (reset + 01 + 02) 2026-10-12; phase 3: S1–S19 rolled back, GL-failure path committed + cleaned, end-to-end with the real terminal code, then DEV restored | ⏳ waiting for the user's go; nothing uses it until a machine sets POSV2 Enabled = 1 |
| 60 | `POSV2/2026-10-13_POSV2_03_BIRReports_PeriodClose.sql` (needs 58 + 59; anchor patches, backups `_OLD_10132026120000`: BIR reports `spr_ESalesDetails` / `spr_POSSalesReportSummary` / `spr_POSSalesReportSummary2` (2550M via `spr_SalesReportSummary2`) / `spr_SalesReportSummary` (older BIR2550M screen, still on the menu) add POS V2 Z-readings next to the old POS; `spu_GLPeriod_Close` refuses 59908 while a POS V2 shift of the month is open or its GL is not booked, 59909 while a terminal used in the month hasn't connected since it ended) | ✅ 2026-10-13, re-installed after the sp-review (reset + 58 + 59 + 60): F1–F9b + phase 3 / 4 suites + EC1–EC3 rolled back; end-to-end with the real classes, then DEV restored | ⏳ with 58 + 59 (the 5 patched procs had the same definitions on STAGING as DEV, checked 2026-10-13) |
| 61 | `2026-10-12d_SupplierPayment_MultiBranchSplit_InvoiceView.sql` (multi-branch split fix in `sp_AddPaymentSupplierCompound_V2`: last branch = amount settled − the rounded shares; backup `_OLD_10122026200000`. New read-only `sp_GetSupplierVoucherInvoiceView` for SupplierVoucherReversalFrm › View Details › "Invoices (as paid)"; the new exe shows it, an old exe ignores it) | ✅ 2026-10-12 17:07 (first version 16:55 reverted and re-applied after the reviews). Rolled back first: the bug reproduced on CEB-PCF-081826 / 082726 (+0.48 / +0.18), fixed = legs = screen = cheque = bank, ledger 0; partial then final; EWT 1,000 split per branch; single-branch unchanged; purchase with EWT row + partial purchase; refusals 60523 (net liability 0) / 60524 (negative last share). Backup = the original (hash) | ✅ 2026-10-12 17:07 by Claude, user-approved. Rehearsed rolled back: 13-branch payment 20,183.04 = legs = cheque (was +0.06); real vouchers 688 / 913 show Balance After −0.06. Backup = original. ✅ PRODUCTION: run by the user 2026-10-12 (users need the new exe for the "Invoices (as paid)" tab) |
| 62 | `2026-10-12e_SupplierVoucherReversal_TelegraphicVariance.sql` (`sp_CancelledChequesCS`, Supplier Voucher Reversal: purchase / expense balance back by the amount settled = cash − the Variance column of telegraphic rows; purchase AmountPaid back by the telegraphic cash only, EWTAmount / Discount / OffsetAmount untouched (a cash / check purchase reversal drove them negative); PayStatus PARTIAL while another payment stands; telegraphic / cash vouchers can't be reversed twice + applock `APREV:<supplier>:<voucher>`; backup `_OLD_10122026230000`. Data repair of purchases the old rule left short, only when the dropped variance explains the whole gap; backup table `APACCOUNTS_RevVariance_Backup_20261012`; no exe change) | ✅ 2026-10-12 17:22 (rolled back first R1–R5: telegraphic purchase with FX gain 386,428.57 → 396,428.57; partial-then-rest → 296,428.57 PARTIAL; telegraphic expense 285,000 → 285,365; cash / check purchase AmountPaid −396,128.57 → 0; double reversal refused). Repair: nothing to fix (RIBS 32339 already right) | ✅ 2026-10-12 17:22 by Claude, user-approved (rehearsed rolled back first). Repair: PRIBLET 000125/15 0.00 FULLYPAID → 70,000.00 PARTIAL (1 row, backup kept); the voucher view of 38581 now shows Balance After = Balance Now = 70,000. ✅ PRODUCTION: run by the user 2026-10-12 (its repaired / skipped list not seen yet) |
| 63 | `2026-10-12f_SupplierPayment_SplitBug_VoucherCorrection.sql` (data only. User 2026-10-12: the cheques were written for the screen's total. Vouchers inflated by the split bug corrected on the leg, ticket DR/CR, supplier-ledger row, CheckVoucher and bank-recon OC; listed refs only: 28500 / 688 and 38626 / 913, 199,999.06 → 199,999.00; every value checked first, else nothing changes (tested: listing 35103 is refused); backups `SplitFix_Backup_20261012_*`) | ✅ 2026-10-12 (28500 only; 38626 isn't on DEV). Rehearsed rolled back first | ✅ 2026-10-12 by Claude, user-approved (rehearsed rolled back first): both vouchers cheque = legs = bank credit = recon = 199,999.00, ledger net 0, supplier 000047 +0.12. ✅ PRODUCTION: run by the user 2026-10-12. The other 6 affected vouchers: 684 was reversed; 787, 803, 823, 837, 867 → script 66 |
| 64 | `2026-10-12g_GLDetailLedger_ReferenceKey.sql` (`sp_rpt_GLDetailLedgerRealTime`, Accounting Reports › GL Detail Ledger: new 2nd column ReferenceKey = the day's distinct TicketMaster.ReferenceKey values, comma-separated, as TicketNumbers; backup `_OLD_10122026233000`; no exe change) | ✅ 2026-10-12 18:01 (old vs new rolled back first: same rows and amounts apart from the new column) | ✅ 2026-10-12 18:01 by Claude, user-approved (same rehearsal). ✅ PRODUCTION: run by the user 2026-10-12 |
| 65 | `[65]-2026-10-12h_LoanRevaluation.sql` (Loan Revaluation, Feature 23 / plan `docs/plans/2026-10-12_PROFOOD_Loan_FX_Plan.md`: tables `LoanAccount` / `LoanTransaction`, mapping `LOAN-REVAL` FXLOSS / FXGAIN = 60323, procs `sp_Loan_GetAccounts` / `_GetTransactions` / `_GetTicketLines`, `spu_Loan_PostRevaluation` (month end, in order, stale guard, 62001–62009) / `spu_Loan_ReverseRevaluation` (latest only, dated like the original, 62011–62015); loan LOAN051618 PROFOOD GMBH EUR 800,000 opening 07-31 @70.5095 = 56,407,600 = GL 20203. C#: new `AccountingDevEx/LoanRevaluationFrm` (code-only), Accounting Settings › "Loan Revaluation" (admins + accounting)) | ✅ 2026-10-12 23:3x (same as STAGING) | ✅ 2026-10-12 23:3x by Claude, user-approved ("apply directly in staging"). Rehearsed rolled back first: 08-31 @71.9305 = +1,136,800 loss, 09-30 @70.2158 = −1,371,760 gain → 56,172,640 = Peachtree = GL 20203; reversal of 09-30 back to 57,544,400; refusals 62002 / 62004 / 62005 / 62012 / 62015. The 08-31 / 09-30 revaluations are NOT posted yet (to be posted from the screen). **2026-10-13 08:47 reinstalled (reviewed version) on DEV + STAGING** after sp-reviewer / ui-form-reviewer: install stops unless COA 60323 / 20203 exist and GL 20203/888 before 08-01 = 56,407,600; next date must be the following month end, not after this month (62016); GL liability on the branch up to the date must equal the loan balance (62020, catches a hand-booked JV); mapping accounts checked in the COA; reference no. from the counter inline. Form: loan pick kept on a transient null, Code - Name account column, preview rounding = server, grids sized on show. Tests rolled back again + UI harness 6 / 6 runs clean. Later 10-13 (C# only): the Posted grids' figures were never formatted (the `Columns.Count == 0` check is never true after DataSource), now N2 / rates `#,##0.0000##`, right-aligned cells + headers + rate box; CLAUDE.md numeric rule items 3 / 4. ⏳ PRODUCTION: the user runs it + the new exe. 2026-10-13 (C# only): the menu item opened the form with `Show()` inside a `using` block, so it was disposed at once and never appeared; now non-modal, one instance (`Main.SetupLoanRevaluationMenu`) |
| 66 | `[66]-2026-10-13_SupplierPayment_SplitBug_VoucherCorrection_Remaining.sql` (data only, after 63: the other split-bug vouchers, corrected to the screen's total like 688 / 913: 787 −0.52, 803 −0.01, 823 −0.48, 837 −0.06, 867 −0.18; 684 was reversed, nothing to fix. The extra is recomputed from ExpenseMaster with the old formula (it also gives +0.06 on 688 / 913) and must equal legs − screen; fixes the last-branch leg (highest BranchCode) of the one multi-branch invoice, its ticket DR / CR, ledger row, CheckVoucher and the open recon OC item; backups `SplitFix_Backup_20261013_*`) | — (none of the 5 on DEV) | ✅ 2026-10-13 by Claude, user-approved (user confirmed the cheques were for the screen's total; rehearsed rolled back first). Live = rehearsal: all 5 legs = cheque = bank credit = recon OC = screen, tickets balanced; suppliers 000016 / 000142 → 0.00, 000047 799,853.16 (+0.66), 000051 237,919.96 (+0.06); account = ledger sum. ✅ PRODUCTION: run by the user 2026-10-13; verified 10-13 with the read-only login (5 vouchers + 688 tie; 913 / 38626 is not on PRODUCTION) |
| 67 | `[67]-2026-10-13b_ConversionBarcode_ConversionDate.sql` (Conversion Date, like the SO effectivity date; user: catching up last month's conversions. `ConversionBarcodeSummary.DateConverted` = the date picked on screen + the time keyed; new column `DateEntered` = when keyed (backfilled = DateConverted); view adds it last; `spu_PostConversionBarcode` optional `@DateConversion DATE = NULL` (NULL = today, old exe unchanged; future 59217, GL-closed month 59218), output lots' DateReceived = it; `spu_FinalizeConversionBarcode` dates the CONV-FINALIZE ticket (master + details) with it, DateFinalized stays now; reports already filter on DateConverted. Backups `_OLD_10132026180000`. C#: `ConversionPerBarcode` "Conversion Date" box (designer; default today, max today, kept between entries, confirm when back-dated), For Posting / Posted show Conversion Date + Entered; `ConversionPerBarcodeFinalize` shows the date in the title and confirm. **The new exe needs this script** (it selects DateEntered and sends @DateConversion)) | ✅ 2026-10-13 (rehearsed rolled back first: 09-30 conversion → summary / lots / ticket 09-30, DR = CR; no date = today; Sept report range finds it; 13 old rows backfilled. Live: R1 future 59217, R2 closed month 59218, nothing written) | ✅ 2026-10-13 16:2x by Claude, user-approved (rehearsed rolled back first with STAGING lots 60647 / 60644: same as DEV; 7 old rows backfilled). Live: backups, column, view, both procs patched, 0 rows without DateEntered; R1 59217 / R2 59218, nothing written. ✅ PRODUCTION: run by the user; verified 10-13 with the read-only login (column + patched proc); users need the new exe |
| 68 | `[68]-2026-10-13c_BankRecon_July_PeachtreeBF_BPI_PNB.sql` (data only, part 2 of [42]: the accountant's second July Peachtree workbook (Google Sheet, 10-13). July 31 headers + BF-PEACHTREE items: BPI PESO 1 bank 2,589,835.21 + 3 OC (CV2605-126/127/128, 1,300,000.00); PNB PESO bank 8,733,642.29 + 14 DIT (1,673,899.70); PNB PESO 2 bank 21,195,077.57, no items. WEALTHBANK sheet = part 1 (still 1,000,050.00 on Peachtree's side). Post-check: all 3 July differences 0.00. Found: AR collection ref 31459 (275.00, control F2608-24-A) dated 07-24, probably 08-24; PNB PESO Aug header 1144 carries July's bank balance 8,733,642.29; a stray PNB PESO Aug header 1150 on branch 008 (0 items)) | ✅ 2026-10-13 by Claude, user-approved (rehearsed rolled back first): headers 1253 / 1160 / 1254, 3 OC + 14 DIT, July 0.00 on all 3 | ✅ 2026-10-13 by Claude, user-approved (rehearsed rolled back first): headers 1186 / 1160 / 1187, 3 OC + 14 DIT, July 0.00 on all 3 (PNB PESO Aug −1,673,899.70 → 0.00, only because Aug has July's bank balance and nothing ticked). ✅ PRODUCTION: run by the user; verified 10-13 with the read-only login (17 items) |
| 69 | `[69]-2026-10-13d_Repair_STS_MultiLotReceipts_SO13902_Cancel.sql` (data only; Exception Center findings on PRODUCTION 10-13 = STAGING's since 10-01. A: STS 11911 / 11913 / 14100, line of 13025 received as one lot's qty (T05 + T02): the rest per batch as the fixed receive proc writes it (branch Inventory, ReceivedOrderDetails, 'STS RCVD ITEM' ledger, ActualQty / totals) + IT-BR-VATEX under the ORIGINAL receipt reference and date (10-01; T03 stays 1); 14100 also moves 34,434.00 VAT In Transit → VAT-exempt In Transit (its 10-01 receipt credited VAT transit for the TVP line); rounding residue → STS-SHORT / OVER (0.00 in practice). B: SO 13902 line 2: lot 30778 +840, ledger 'STS CANCEL ITEM PO#13902', FIFO 23561 flagged (X01). Backups `Repair69_Backup_*`; ProcessedBy / EnteredBy 'REPAIR [69]') | — (not run on DEV) | rehearsed rolled back 2026-10-13: tickets 224,976.73 / 109,907.78 / 275,683.95 (+34,434 reclass), branch 012 +3,021.06 kg, 005 +2,487.00 kg, lot 30778 840 / 2,010; Exception Center inside the tx: every check 0. ✅ STAGING 2026-10-13 by Claude, user-approved: tickets 20673 / 20674 / 20675, residue 0.00, 4 ledger rows, lot 30778 = 840; Exception Center on STAGING afterwards: every check 0 (first time since 10-01). ✅ PRODUCTION: run by the user 2026-10-13; verified with the read-only login: tickets 23112 / 23113 / 23114 balanced, branch 012 +3,021.06 / 005 +2,487.00 kg, lot 30778 = 840; Exception Center on PRODUCTION: every check 0 |
| 70 | `[70]-2026-10-13e_ExceptionCenter_AP_Provider.sql` (Exception Center phase 1, AP: new read-only `fn_rpt_exc_AP_Findings` + `sp_rpt_exc_AP_Summary / _Detail` in the portal's contract (TOP 500 + TotalMatchCount + Hint; unknown code → error). 10 checks: AP-VOUCHER-LEGS, AP-TICKET-UNBALANCED (cross-branch expenses balanced per reference: one ticket per branch), AP-SUPPLIER-LEDGER-CHAIN, AP-ACCOUNT-VS-LEDGER, AP-INVOICE-VS-LEDGER (invoice balance = supplier-ledger net; purchases only with a cost: cost-0 rows are PO-linked placeholders), AP-LEDGER-PAYMENT-SIDE, AP-REVERSAL-NOT-RESTORED, AP-CREDIT-NEGATIVE, AP-STATUS-VS-BALANCE (broker-advance liquidations excluded), AP-CHEQUE-REUSED. Dropped after validation: duplicate cash advances (30 legit groups on PRODUCTION); AP subledger vs GL deferred (needs the accountant's mapping). Registry rows wait for the portal's sql/43) | ✅ 2026-10-13 (validated: findings 1 / 4 / 2 = test data; recreated after [71] / [72]: the chain check now also flags NULL ledger amounts) | ✅ 2026-10-14 00:20 by Claude, user-approved (with [77]); 3 findings, all AP-INVOICE-VS-LEDGER (the 2 BF invoices + BAC-PCF-080626 0.01) | — not installed; validated read-only with the read-only login: **25 findings, all explained** (see "AP findings 2026-10-13" under Feature 16) |
| 71 | `[71]-2026-10-13f_SupplierLedger_PurchasePayment_DebitSide.sql` (AP finding 1: `sp_PostCompoundTicket`'s supplier-ledger write was hard-coded Debit 0 / Credit GROSS; new optional `@LedgerSide CHAR(1) = 'C'` (default = old behaviour for the accrual callers SP_POSTINVENTORY / sp_FinalizeInventoryUpload; else 50026); `sp_AddPaymentSupplierCompound_V2` and `sp_AddPaymentSupplierCompound` pass `'D'` on their PV-AP call; data: PV-AP COMPOUND credit rows → debits (refused if a reversed voucher's), trigger re-chains. Backups `_OLD_10132026210000`, `SupplierLedger_PVAPSide_Backup_20261013`; no exe change) | ✅ 2026-10-13 (2 rows; GELTECH 1,846,000 → 0, PREMIER FRESH 2,600,088.40 → 0; direct proc test: default = credit, 'D' = debit) | ✅ 2026-10-13 by Claude, user-approved (rehearsed rolled back first). Live = rehearsal: 4 rows (DR-00565-TVP 923,000.00, SI-457557 / SI-457594-FRIES 1,744,285.71 + 396,428.57, RF-2241 BELLY 1,300,044.20) now debits; GELTECH / GLOBAL PACIFIC / PREMIER FRESH 0.00; 3 procs patched, backups kept. AP checks after [71] + [72]: only SI-1000066010, RIBS SI-202511383 (BF, accountant), BAC-PCF-080626 0.01 and cheque 2384570 left | ✅ run by the user 2026-10-13; verified with the read-only login: the 4 rows are debits, 3 procs patched, backups kept; AP-LEDGER-PAYMENT-SIDE 0 |
| 72 | `[72]-2026-10-13g_ExpensePosting_NoPayable_ZeroNotNull.sql` (AP finding 3, corrected: the 6 "NULL balance" entries are reclasses keyed on the expense screen with **no payable line** (DR Inventory / CR Prepayment - Others; light and water / storage cost), nothing owed — not unpaid invoices. `spu_PostExpenseV2`: `@PayableAmount = ISNULL(…, 0)` and lines Balance 0 when nothing is payable (the 56001 guard stays commented out on purpose); data: those entries' summary / lines Balance 0, ledger NULL Debit / Credit / TotalAmount → 0 (only when no payable credit and no payment). Backups `spu_PostExpenseV2_OLD_10132026220000`, `Expense_NoPayable_Backup_20261013_*`; no exe change. Also [70]'s chain check now flags NULL ledger amounts (they escaped it)) | ✅ 2026-10-13 (proc patched; DEV had no such entries; test: a no-payable entry owes 0, a normal one its payable) | ✅ 2026-10-13 by Claude, user-approved (rehearsed rolled back first). Live: the 6 entries (34761 / 34765 / 34815 / 34819 / 34822 / 34955) balance 0.00; no NULL ledger amounts or NULL balances left; proc patched, backups kept | ✅ run by the user 2026-10-13; verified with the read-only login: the 6 entries 0.00, no NULL ledger amounts / balances. AP checks on PRODUCTION after [71] + [72]: SUPPLIER-LEDGER-CHAIN 0, LEDGER-PAYMENT-SIDE 0; INVOICE-VS-LEDGER 17 → 7 (2 BF for the accountant + 5 cent rows of the split-bug vouchers); VOUCHER-LEGS 4 = 684 / 914 / 934 / 967 (1.23) |
| 73 | `[73]-2026-10-13h_SupplierPayment_SplitBug_VoucherCorrection_Last4.sql` (data only, after [63] / [66]: the last 4 split-bug vouchers found on PRODUCTION by [70], corrected to the screen total (user 2026-10-13: the cheques were for the screen total): 684 / 28473 BAC-PCF-080626 −0.01, 914 / 39390 BUT-PCF-083126 −0.02, 934 / 39611 CEB-PCF-083126 −0.03 + CEB-PCF-090526 −0.46, 967 / 40881 SOA-091426 −0.71 (a partial payment). Unlike [66]: several multi-branch invoices per voucher, partial payments allowed, the amount settled per invoice = its ledger payable credit − its balance now (must add up to the screen total), a reversed voucher is skipped. Same 5 tables as [66] (leg, ticket DR / CR, ledger row, CheckVoucher, open recon OC); backups `SplitFix_Backup_20261013b_*`) | ✅ 2026-10-13 (684 only; rehearsed rolled back first): legs = cheque = recon OC = bank credit = 41,941.02, ticket balanced, invoice ledger net 0, supplier 000046 account = ledger | — not needed: 684 was reversed there (rehearsal: SKIPPED, nothing changed); the others aren't on STAGING | ✅ run by the user 2026-10-13; verified with the read-only login: all 4 vouchers legs = cheque = recon OC = bank credit = screen, 5 tickets balanced, the 5 invoices' ledger net = balance (SOA-091426 131,250.00 PARTIAL), 4 suppliers account = ledger, backups 5 / 10 / 5 / 4 / 4 rows. AP checks on PRODUCTION now: only the 2 balance-forward invoices (SI-1000066010, RIBS SI-202511383) |
| 74 | `[74]-2026-10-13i_CheckVoucher_CancelledChequeGuard.sql` (AP finding 5: new trigger `trg_CheckVoucher_NoCancelledChequeReuse` (AFTER INSERT, UPDATE) refuses 60631 a live cheque voucher on a cheque no. recorded as cancelled ([55]) on the same bank. Cancelled record = PaidTo CANCELLED, Amount 0, isErrorCorrect 1 + its CheckVoucherCancelled row (same proof as sp_EditCancelledCheque); bank matched in CreditGLCode / OfficialReceiptNo / NotedBy (the writers keep it in different columns); on UPDATE only rows whose cheque no. / bank / status changed. One rule for every writer (header proc via V2, sp_PostCashAdvance, sp_AddPaymentSupplierCompound, retired screens, web v2). **Rule (2026-10-13): a reversed voucher's cheque no. may be issued again** (PRODUCTION does it 11 times); live-vs-live duplicates not blocked (none anywhere). New object only, CREATE OR ALTER; no exe change; existing rows untouched) | ✅ 2026-10-13 23:35; T1–T9 each in its own rolled-back tx all PASS (refused: header proc, cheque no. changed by UPDATE, old-proc shape, real sp_PostCashAdvance; saved: other bank, other no., existing pair edit + reversal, reversed no. re-issued, sp_RecordCancelledCheque); no test rows left | ✅ 2026-10-13 23:37 by Claude, user-approved (rehearsed rolled back first: voucher 917 edit saves, a free number saves, cheque 2384570 refused 60631). Live: trigger enabled; T1–T9 rerun on STAGING all PASS, no test rows left (voucher / reference counters are tables, rolled back with the tests) | ✅ run by the user 2026-10-13 23:48; verified with the read-only login: trigger enabled, AFTER INSERT + UPDATE, the only trigger on CheckVoucher, definition identical to STAGING (hash) |
| 75 | `[75]-2026-10-14_STAGING_Delete_TestChequePair_916_917.sql` (STAGING only, data: user 2026-10-14 "delete the 916 / 917 test pair on staging". Test data of 10-13 (ADMINISTRATOR): 916 / ref 38651 = cancelled-cheque record of cheque 2384570; 917 / ref 38657 = payment 29,660.71 on the same cheque to ALPA (000142) for test invoice SI#00224 / expense 38654. Deletes 916 (CheckVoucher, CheckVoucherCancelled) and 917 (CheckVoucher, TransactionPaymentAP, 6 APPaymentDetails, 6 TicketMaster + 12 TicketDetails, 6 SupplierLedger, open recon OC); invoice 38654 back to POSTED, balance 29,660.71, lines UNPAID. Every value checked first (59979), DB must be STAGING; post-check 59980; backups `TestPair916917_Backup_20261014_*`) | — | ✅ 2026-10-14 by Claude, user-approved (rehearsed rolled back first). Live = rehearsal: a scan of every reference column finds nothing of 38651 / 38657; invoice 38654 POSTED 29,660.71; supplier 000142 account = ledger = 29,660.71. AP checks on STAGING: AP-CHEQUE-REUSED 0; only the 2 BF invoices + BAC-PCF-080626 0.01 (684 is reversed on STAGING, so [73] doesn't apply there). Test invoice 38654 and test cancelled cheque 915 deleted by [76] | — STAGING only |
| 76 | `[76]-2026-10-14b_STAGING_Delete_TestCheque915_TestInvoice38654.sql` (STAGING only, data: user 2026-10-14 "delete 915 and the test invoice 38654 too". Test data of 10-13: 915 / ref 38650 = cancelled-cheque record of cheque 2384568; expense 38654 = ALPA SI#00224 (copy of 9680), unpaid since [75]. Deletes 915 (CheckVoucher, CheckVoucherCancelled) and 38654 (ExpenseSummary, 6 ExpenseMaster, 8 ExpenseManualLines, ticket 20655: 7 masters + 8 lines, 1 SupplierLedger). Refused unless STAGING, the invoice unpaid and every row as found (59981); post-check 59982; backups `TestCleanup_Backup_20261014_*`) | — | ✅ 2026-10-14 by Claude, user-approved (rehearsed rolled back first). Live: the rescan finds only the unrelated AR balance-forward rows that use 915 / 2338 as their own reference numbers; supplier 000142 account = ledger = 0.00; AP checks unchanged (2 BF invoices + BAC 0.01) | — STAGING only |
| 77 | `[77]-2026-10-14c_ExceptionCenter_AP_Registry.sql` (needs [70] + the portal's sql/43: new router `sp_rpt_exc_AP_Provider` (sql/43's dispatchers call ONE ProviderProc in two shapes: Summary without , Detail with it; the router hands off to [70]'s _Summary / _Detail) + the 10 AP rows in ExceptionDefinition (reply section 8: Owner erp, Module AP, Kind INTEGRITY, SortOrder 100–109, Action text; insert if missing else update, IsActive kept). Prerequisite guard stops every batch (NOEXEC). No grants needed: no object grants exist on any tier, the portal runs as db_owner) | ✅ 2026-10-14 00:1x. Portal summary called directly: 48 cards, 0 UNAVAILABLE, AP figures = fn_rpt_exc_AP_Findings (AP-INVOICE-VS-LEDGER 1 = RIBS 3,387,259.01). Drill-downs through sp_rpt_ExceptionCenter_Detail: AP-INVOICE-VS-LEDGER rows + hint, AP-CHEQUE-REUSED empty, BRC-STALE-DIT (inline) unchanged. Note: calling the summary through INSERT..EXEC shows the AP cards UNAVAILABLE by design (the portal skips providers inside a transaction) | ✅ 2026-10-14 00:20 by Claude, user-approved (after [70]). Portal summary called directly: 48 cards, 0 UNAVAILABLE, AP-INVOICE-VS-LEDGER 3 / 3,514,403.57 = the provider's function; its drill-down lists the 3 rows. Dependency Atlas rebuilt from DEV 00:21 (1,364 SQL objects) and republished (version 8) | ⏳ after the portal's sql/43 reaches PRODUCTION (still 19 checks, no dispatcher on 10-14); then [70] + [77] by the user |
| 47 | `2026-10-08d_BankRecon_StampClearedMonth.sql` (data; after 46: moves old-exe ticks of earlier-period items to the month that was on screen; set branch / account / month / tick dates) | — | rehearsed on STAGING with 46 (old-exe ticks → July 0.00 again, Aug unchanged). For PRODUCTION if the accountant ticks BDO PESO 1 Aug with the old exe from 10-09 | ✅ 2026-10-07 14:46, run by the user; verified: 34 rows, July 31 differences = Peachtree's, no duplicates |

- **2026-10-14, PRODUCTION status (read-only probe of each script's footprint):** 43, 44, 45, 46, 48, 49, 53, 54 (lots 1109 = 229.87 / 1110 = 109.50), 55, 56, 57 and 65 are applied, so their "⏳ PRODUCTION" notes above are done. Not on PRODUCTION: POS V2 58 / 59 / 60 (not on STAGING either; waits for the user's go). Loan Revaluation: only the 07-31 opening is in LoanTransaction; the 08-31 / 09-30 revaluations are not posted yet (GL 20203 = 56,407,600.00; Peachtree 56,172,640). Bank recon: 439 items cleared since August (the accountant is working). on both DBs was changed by the user (14:13 DEV / 14:18 STAGING): `BranchCode` → `BranchName` via `INNER JOIN dbo.Branches`. The repo copy in script 6 (`2026-09-24b`) still has `BranchCode`.
- Web reporting handoff for the recon: `docs/handoff/2026-09-26_ItemCostingRecon_WebReporting_Handoff.md`.

- Earlier testing and deploys this session went to `CORECSERP_002_DEV`, the old DEV.
- COREX001 already had all 10 scripts when checked, and STAGING had 1–7; it's unclear who or what applied them.
- Each script renames the live object to `<name>_OLD_<timestamp>` before recreating it. Every file's suffix is unique.
- Re-running a script on a database that already has that backup name fails at the rename, so check first.

C# changes (uncommitted as of this entry) — build succeeded:
- `AccountingDevEx/SupplierPaymentDevEx.cs` + `.Designer.cs`
- `Reporting/ItemCostingReconReport.cs` + `.Designer.cs`

---

## Hardening backlog shared with Fable (2026-10-14)

- Handoff + backlog: `docs/handoff/2026-10-14_Hardening_Handoff_to_Fable.md` (page: https://claude.ai/artifact/UjuHjrDDgk87Y5418K5oHR, source `docs/handoff/HardeningBacklog.html`; republish to the same URL when a status changes) (user: Fable hardens the guardrails, the ERP session keeps operating; collaborate, don't compete). 13 items H1–H13 in priority order; Tier A: H1 compound-ticket balance / error text, H2 AR reversal reference collision, H3 error-handling standard, H4 non-atomic postings, H5 client-supplied amounts / AR balance formula, H6 lookups picking the wrong record. Open items were re-checked on PRODUCTION 10-14 (read-only).
- Protocol: claim the item in that file before touching code; the other session leaves claimed objects alone; DEV → rehearsed STAGING on the user's go → PRODUCTION by the user; each item adds an Exception Center check. Next free script number on 10-14: [78].

## Feature 1 — Supplier Payment: OverPay / Advance credit (AP)

**Problem:** the client's Peachtree habit is to overpay an invoice (Balance 1,000, pay 1,200),
leave it at -200, and net it off the next invoice. We post GL per invoice, so a negative
balance is wrong. Modeled on the AR version (`ClientPaymentsDevExAcctg.cs`, account 20115).

**Design:**
- Grid columns in `AccountingDevEx/SupplierPaymentDevEx.cs`, added client-side in `populate()`,
  **not** in `splist_Accounts`, because that proc also feeds `VoucheringManualFrm` and `HOFormsDevEx/SupplierPaymentDevEx`:
  - **OverPay (Credit)**: DR `101030208` Advances to Suppliers. Carried forward as credit.
  - **OverPay (Expense)**: DR `60339` Misc Expense. Written off, not carried forward.
  - **Advance Applied**: CR `101030208`. Consumes earlier credit instead of cash.
- **Adv. Credit** label = `sp_GetSupplierAvailableCredit` = SUM(OVERPAY) − SUM(ADVANCEAPPLIED) from
  `APPaymentDetails`, excluding vouchers found in `PaymentReversalAudit`. **Shared across PURCHASE and EXPENSE.**
- Extras reach the SP through the optional TVP `dbo.AP_PaymentLineExtraTVP`
  (`@InvoiceLineExtras` → `@LineExtras`). An omitted TVP arrives as empty (tested), so `CombinedSupplierVoucherFrm` is unaffected.
- **Rules (SP plus client mirror):**
  - 60511: amounts can't be negative.
  - 60512: only one of the three per invoice.
  - 60513: OverPay on only one invoice per voucher.
  - 60514: Advance can't exceed credit; re-derived under `sp_getapplock 'APCREDIT:'+SupplierID`.
  - 60515: OverPay only when the invoice is fully settled.
  - 60518: the ticket must balance, DR = CR.
  - 60519 (reversal): a voucher whose credit has already been used can't be reversed first.
- **By mode:**
  - **PURCHASE:** new mnemonics `PV-AP-OVERPAY / -OVERPAYEXP / -ADVAPPLIED`, each with explicit amount types, never `MIRROR`.
  - **EXPENSE SINGLE:** extra legs via `sp_Payment_PostSettlementTicket`, which gained 6 optional params that default to 0.
  - **Multi-branch expense:** real data is tagged `PostingMode='MULTI-MANUAL'`, **not** 'BATCH'. User chose: book the extras on the
    **head-office 888 ticket** only.
    - No 888 share + OverPay: a separate `EXP-OVERPAY-HO` ticket, DR advances / CR bank.
    - No 888 share + Advance: rejected (60522).
    - Advance larger than 888's share: rejected (60522).
- Overpayments are **not** written to `SupplierLedger` in any mode. It records only the payable amount settled. This is deliberate.
- User guide for staff was written in chat (2026-09-24). It explains the three columns, the day-1 / day-2 example, the rules and the reversal order.

**Status:** done on DEV and fully tested (rolled-back transactions) for all modes, reversals and negative cases. The reviewer agents passed it.
**Next:** UI test by the user, then STAGING.

## Feature 2 — Item Costing: inventory legs only + master-detail report

- **Bug:** PO-linked expense costing used the **whole invoice amount**. Example: ExpenseSummary 30437 on STAGING has 151,359.27 total but only a
  118,199.35 inventory leg on ticket 14287.
  - **Fixed in `spu_PostExpenseV2`, forward-only:** the cost increment is now the net Debit − Credit on the `10104` inventory subtree, via config row
    `JournalEntryMapping` mnemonic `EXP-INVCOST-ROOT` and `dbo.fn_InventoryCostAccounts()`.
  - Historical `Inventory.Cost` is **not** corrected.
- `spu_PostExpenseV2` CATCH now uses `THROW;`. RAISERROR had been turning every error into 50000.
- `Reporting/ItemCostingReconReport` rewritten as a master-detail view: all shipments, expand a row to see its linked expenses.
  - New SP `sp_rpt_ItemCostingRecon_List` returns 2 result sets. It's set-based and ticket aggregation is scoped to the expenses in scope.
  - The old `_Header/_Detail` procs are kept but no longer called.
- ReconStatus values: MATCHED / VARIANCE / LOTS DIVERGE / NO INVENTORY / NO EXPENSES.

- 2026-09-26: right-click or double-click a Linked Expense row → "View Related Tickets" popup (posting ticket, payment-voucher tickets, reversals, each with GL lines).
  New read-only SP `sp_rpt_ItemCostingRecon_ExpenseTickets` (script 11). Payments link via `APPaymentDetails.BatchReferenceID` → voucher (`ReferenceNumber`+`VoucherID`) → `TicketMaster`.

**Status:** done on DEV. **Next:** UI check, including whether Export includes the expense rows, then STAGING.

## Feature 3 — Reversal NULL balance (`sp_CancelledChequesCS`)

EXPENSE reversal wrote `ExpenseMaster.Balance = NULL` whenever a line's EWT/Discount/Offset was NULL.
The fix adds ISNULL guards, computes values once in a CROSS APPLY, and sets Status to UNPAID / PARTIAL / FULLYPAID.
Tested full / partial / two-step on multi-branch and SINGLE invoices. **Status:** done on DEV.

## Feature 4 — POS Sales Report: Cash Receipts / Sales Journal (script 7)

- Branch filter on both tabs: a global admin picks a branch or all branches; everyone else is locked to `Login.assignedBranch`.
- Cash Receipts `InvoicePaymentAmount` = INVOICE PAYMENT + OVERPAY − OFFSET − EWT. INVOICE PAYMENT is stored gross.
- C#: `POS/POSSalesReportDevEx.cs` + `.Designer.cs`. Built.
- **Open:** should DISCOUNT be deducted too? Asked the user.
- On DEV with the EWT change. **Next:** UI check, then STAGING.

## Feature 5 — Expense Manual Multi-Branch: keep GL line order (script 8)

- **Bug:** the Details SP sorted by `BranchCode, LineID`, so Edit/View/Copy showed lines regrouped by branch, and saving an edit locked that order in.
- **Fix:**
  - New column `ExpenseManualLines.LineNo` and TVP `ExpenseManualLineTVP_V2`. The old type is kept for the `_OLD_` backup procs.
  - Post/Edit insert `ORDER BY LineNo`. Details sorts by `LineNo, LineID`.
  - Rows posted before the fix have LineNo NULL and fall back to LineID order.
- C#: `ExpenseManualMultiBranchFrm.BuildLinesTVP()` sends LineNo. **The exe and the SQL must deploy together**: an old exe calling the new procs fails on the TVP type.
- Tested on DEV (post, then edit in a different order, rolled back, 0 leftover rows).
- **Same fix for Manual JV (script 9):** `HOFormsDevEx/ManualJournalVoucherFrm.cs` and `ManualJournalVoucherMultiBranchFrm.cs`.
  - New column `ManualJournalVoucherDetails.LineNo`, new types `JournalVoucherLineTVP_V2` and `JournalVoucherLineMultiTVP_V2`.
  - The details SP previously sorted by BranchCode, AccountCode.
  - Tested single post, multi post and edit on DEV (rolled back).
- **Single Expense (`AccountingDevEx/AddExpenseDevExFrm`) skipped (user's call).**
  - Its lines come from `TicketDetails`, which has no order column.
  - Adding a column there would break 43 SPs and 3 old forms that insert without a column list.
  - `spu_PostExpenseV2` is shared with 3 other forms, so its TVP can't change.
  - If revisited: a side table plus an optional V2 TVP on `spu_PostExpenseV2`.

## Feature 6 — AccountingReportsFormV2 (`HOFormsDevEx/`)

- The date fields had no calendar button; the Combo button was missing in `.Designer.cs`. Fixed.
- **Income Statement pivot (script 10):** HEAD OFFICE CEBU ('888') is now the first branch column.
  - Verified the output matches the old proc (67 rows, 0 differing cells).
- **Pivot view:**
  - AccountCode and AccountDescription are pinned left in the grid.
  - Excel export for pivot results uses a data-aware XLSX (`ExportPivotToXlsx`), so the header row and those two columns are frozen. Verified the pane in an exported file.
  - PDF and every non-pivot export still use the old print-layout path.
  - The pivot export has no title rows (user's choice): DevExpress won't freeze the header row with rows above it.

## Feature 7 — Posted tabs: draggable splitter (C# only)

- **Forms:** ManualJournalVoucherMultiBranchFrm, ManualJournalVoucherFrm, AddExpenseDevExFrm (AccountingDevEx), ExpenseManualMultiBranchFrm, VoucheringManualFrm.
- **Change:** each form's Posted tab now puts the posted grid on top and buttons + details below, in a `SplitContainerControl` named `splitPosted`.
  - VoucheringManualFrm builds it in code, in `BuildPostedTab()`.
- **Why a helper:** `DevXGridViewSettings.KeepSplitterRatio()` holds the split ratio on resize and remembers a user's drag.
  - Plain `FixedPanel.None` lost the ratio when the control was first laid out tiny: the details panel got squeezed to 0.
- Verified in a harness at 900 px and 560 px window heights, and a simulated drag + resize.
- The ratio is not persisted between sessions.

---

## Feature 8 — Inventory FIFO deduction standard + STS V2 (2026-09-29)

- Analysis + standard: `docs/standards/2026-09-29_Inventory_FIFO_Deduction_Standard.md`.
- User answers: BranchInventoryIN proc lives in another DB (user will create it); **eligible lot = `Available > 0 AND IsWarehouse = 1`** (ENZO keeps 3rd-party-storage HO stock at IsWarehouse=0); non-JFC STS still used elsewhere; partial qty on scan allowed; IsStock not a filter.
- Built (scripts 13/14, not deployed): engine (`spu_InvFIFO_Deduct` / `_Restore` / `sp_InvFIFO_Preview`, LOT/BATCH/AUTO modes) + STS V2 (`spu_PostSTSLineV2`, `spu_ReverseSTSLineV2`).
  - Form `Orders/AddBranchOrderSTSV2` = copy of `AddBranchOrderSTS`; opened from ViewBranchOrderSTS > Process this Order > **FIFO V2 (Test)**, admins only. Old form/procs untouched.
  - Per-scan posting kept; same STS tables (so the unchanged `sp_ConfirmBranchOrderSTS` works — verified on DEV).
- **Testing gotcha:** a table TYPE created inside a transaction can't be used in that transaction (SQL Server deadlocks itself). The 2 types were created committed on COREX001 for testing.
- Found, not fixed: `sp_CancelDeliveryFIFOJFC` restores only ONE lot per line; `sp_CancelDeliveryByBarcode` resets a lot to full `Quantity`. Deliveries 13652/PO 11700 and 13642/PO 11701 (24–25 Sep): 20 cancelled FIFO rows never marked corrected, 19 with no restore ledger row (up to 35,733.47 qty) — needs checking. `funcview_populateProductsInPOJFC` AND/OR precedence bug.
- Reviews (2026-09-30): sp-reviewer + ui-form-reviewer, no blockers. Fixed and retested:
  - SQL: IsWarehouse re-checked under lock; per-product applocks in ProductCode order (`sp_InvFIFO_LockProducts`, 59810) against deadlocks; reverse guard 59833.
  - Form: stale sticker barcode cleared on product/type change; failed full-lot scan keeps the barcode; Save-as-Draft `Close()` instead of `Dispose()`; Load falls back to LoadData.
- Open (user to decide): prune dead handlers copied into the V2 form; pre-existing `displayweight()` FormatException/NullReference; `sp_PostCompoundTicket` re-throws every error as `50050 'ERROR SP'` (real message lost); no idempotency key on a retried scan (by design: one scan = one event).
- Next: user UI test on DEV (after deploying 13+14), then Stock Out / Conversion onto the engine.

## Feature 10 — Retire daily GL posting: real-time reports + month-end lock (2026-09-30)

- **Why:** `GLSummary`, built by `GLPostingDevEx` → `sp_GLPosting` → `GLPosting`, was stale for the months it covers.
  - Jul–Aug vs `TicketDetails`: DEV 459 branch/accounts, 353M; STAGING 513 branch/accounts, 585M. Cause: back-dated / edited / reversed tickets entered after posting.
  - The "Live" hybrid reports inherit the gap (they read `GLSummary` up to the cutoff): 888 AR-Trade as of 08-31 shows 178.69M, the tickets say 156.19M.
  - `TicketDetails` is small (about 40k lines): a full live aggregation takes 47–94 ms.
- **User decisions:**
  - Nothing external uses `GLSummary`.
  - Lock is company-wide; an admin can reopen the last closed month, with a reason, logged.
  - The lock covers GL tickets only.
  - `GLPosting`'s BOSNET netting and auto-reject of unapproved tickets are not needed.
  - Add live versions next to the old reports.
- **Built:**
  - Script 15: 8 `sp_rpt_*RealTime*` procs = their sources with only the `GLSummary` block replaced.
  - Script 16: `GLPeriodLock` + log, close/reopen procs, triggers on `TicketDetails` / `TicketMaster` (59900).
  - C#: 7 "(Real-Time)" entries in `AccountingReportsFormV2` (the Income Statement one also has a real-time pivot).
  - New admin form `AccountingDevEx/GLPeriodClosingFrm`, added in code to Accounting Settings.
  - `btnGLPosting` hidden. Old forms and procs kept.
- **Tested on DEV (rolled back):** 16 report tie-outs and 17 lock scenarios, including the real `sp_EditSingleExpense` being refused after its month is closed.
- **Reviews:**
  - ui-form-reviewer: no bugs.
  - sp-reviewer, fixed + retested:
    - GL Detail Transaction `BETWEEN` on DATETIME: 27 DEV / 3 STAGING lines carry a time of day. The old report misses 19.08M on 2026-09-29.
    - GL Detail Ledger day labels now use a LEFT join.
    - Lock triggers read the lock row `WITH (HOLDLOCK)`, closing the close-vs-posting race.
    - `SupplementaryNumber` added to the guarded columns.
  - Its `STRING_AGG`-at-compat-120 blocker was false: **STAGING now reports compat 160**.
  - Not fixed (existing procs): an unguarded or named rollback can mask 59900 with a "no BEGIN TRANSACTION" error — `sp_AddPaymentSupplierCompound*` (named), `sp_AddPaymentClient`, `SP_CONFIRMPO`, `sp_ReversePaymentClient`, `SP_UPLOADINVENTORY`. Nothing gets posted, but the message is confusing.
  - The two-session close-vs-posting race couldn't be tested before deploying.
- **Found, not fixed:**
  - The existing "Bank Reconciliation" entry fails: the form sends `@AsOfDate`, the proc wants `@DateFrom`/`@DateTo`.
  - Opening-balance ticket 1 has a blank `TicketMaster.BranchCode`; some CONV-FINALIZE lines sit under a different branch than their master. 858 lines are dropped by any 4-part master join.
  - The old bank recon's POSTED/UPDATED filter drops reversal tickets (Status 'REVERSED' is on the reversal itself).
  - Delete-and-repost edit procs are refused for closed months (intended).
  - Year-end closing entries: not designed yet.

## Feature 11 — SupplierLedger / SupplierAccounts audit (2026-09-30, read-only, nothing changed)

- **Rule** (trigger `InsertSupplierLedger`, INSERT only): Ending = Beginning + Credit − Debit, chained per `SupplierKey` in `TRN_SEQ_NO` order. `SupplierAccounts.AccountBalance` = the last row's Ending.
- **STAGING:** 1,416 rows / 87 suppliers.
  - 403 rows with bad math; 69 chain breaks; 82 suppliers affected.
  - 36 accounts wrong vs SUM(Credit − Debit): total 829.47M vs correct 856.13M.
- **DEV:** 824 bad rows, 77 of 80 suppliers, 33 accounts wrong.
- **Causes found:**
  1. Historical cross-supplier overwrite: rows with the same `TRN_SEQ_NO` carry the SAME Ending across suppliers. DEV: every seq, 969 rows. STAGING: 414 rows, mostly seq 1–8, e.g. 9,775.00 on 78 suppliers.
     - The current trigger (2026-07-13) was tested on DEV (rolled back) and is correct: other suppliers untouched.
     - So this came from an older version or an outside script, then propagated down each chain.
  2. The trigger ignores DELETE/UPDATE. Edit procs delete ledger rows (`sp_EditSingleExpense`, `sp_EditApprovedExpense`, `sp_EditExpenseManualMultiBranch`): later rows and the account are never recomputed. Gaps: BUREAU OF CUSTOMS seqs 1, 24, 27, 34, 47.
  3. 11 accounts stuck at 0.00 (e.g. SURE GOOD FOODS 18.78M, CANADA PACKERS 12.55M): their `SupplierAccounts` row was created (7 / 10 Sep, by `sp_TrgInsertSupplierInfo` at 0) after the ledger rows, so the ledger trigger had nothing to update.
- **Also found:**
  - `sp_ReverseApprovedExpense` sets `ErrorCorrectTag = 1 WHERE TRN_SEQ_NO IN (...)` without `SupplierKey`, which tags other suppliers' rows.
  - `func_getLastID` takes the max seq per SupplierID under `NOLOCK` (race; no duplicates today).
- **Fixed (script 17, applied on DEV 2026-09-30):**
  - Backups `SupplierLedger_Backup_20260930` / `SupplierAccounts_Backup_20260930`.
  - Rebuild from Debit/Credit in `TRN_SEQ_NO` order (amounts untouched).
  - New trigger `trg_SupplierLedger_Recalc` (INSERT/UPDATE/DELETE, recomputes affected suppliers' full chains + accounts). The old `InsertSupplierLedger` is renamed `_OLD_09302026180000` and DISABLED.
  - `sp_ReverseApprovedExpense` tags by supplier + seq.
- **Tested first in a rolled-back tx:** audit 824/37/33 → 0/0/0; insert, delete-middle, credit change, 2-supplier insert and hand-edit heal all tie; the real reversal tags only its supplier.
- **STAGING:** applied 2026-09-30 23:26 after a rolled-back rehearsal there (403/75/36 → 0/0/0). Backups `SupplierLedger_Backup_20260930` (1,416 rows) / `SupplierAccounts_Backup_20260930` (145 rows) exist on both DBs.
- **Still open:** optional tie-out of ledger balances to open payables (`ExpenseSummary` + `APAccounts`).

## Feature 12 — ClientLedger / ClientAccounts fix (script 18, 2026-09-30, on DEV + STAGING)

- **Audit (before):** the client ledger was sound (0 bad math, 0 cross-account overwrites, AR ties at 231,213,012.65 on STAGING). The only problems were 2 chain breaks, both JELO'S PLACE (00007479 branch 011 / 00009065 branch 006):
  - BF T_036537 (136,338.20) had been moved to 00009065 by editing `AccountKey`. `AccountID` still said 00007479 and nothing was recomputed, because the old trigger was INSERT-only.
  - BF T_036293 (307,929.20) was still on 00007479, though `TransactionChargeSales` and its payment are on 00009065.
- **Script 18:**
  - Backups `ClientLedger_Backup_20260930` / `ClientAccounts_Backup_20260930`.
  - Moves the T_036293 BF row to 00009065 (seq 4) and fixes `AccountID` on both moved rows.
  - Full chain recompute; only rows that differ are written.
  - `InsertClientLedger` → `InsertClientLedger_OLD_09302026190000` (DISABLED); new `trg_ClientLedger_Recalc` (INSERT/UPDATE/DELETE). It recomputes every touched account, both sides of a move included, and sets `AccountBalance` only (not `CashWalletBalance`).
- **Result:** each JELO'S PLACE account equals its open TCS invoices: STAGING 455,284.60 / 207,768.40; DEV 648,762.20 / 207,768.40 (R-005362 is unpaid on DEV). Trigger tests passed on both DBs: insert, middle delete, amount change, move between accounts, hand-edit heals, emptied account → 0, other accounts untouched.
- **Cosmetic:** on 00009065 the T_036293 OR-EWT (seq 2) now comes before its BF row (seq 4), so the running balance dips negative mid-statement. The final balance is right. Renumbering would shift other rows; left as is.
- Like the old trigger, the new one doesn't create a missing `ClientAccounts` row (0 are missing today).

## Feature 9 — AR: negative balance-forward invoices as credits (DISCUSSION, on hold 2026-09-30)

**On hold:** the user is checking the classification and the EWT entry with the accountant. Nothing built or changed.

- **Ask:** show the negative balance-forward rows of `TransactionChargeSales` in `AccountingDevEx/ClientPaymentsDevExAcctg.cs`, and use them against open invoices, as in Peachtree (tick −300 row + 300 row → both 0). `splist_ARAccounts` lists `Balance > 0` only.
- **Data (COREX001):**
  - 208 negative rows, 147 customers, −2,089,800.34. 106 of those customers also have open invoices.
  - 205 were loaded with `AmountPaid = 0` and a directly-set negative `Balance`: customer-level credits parked on one invoice, e.g. C-000900 is a 295,319.20 invoice carrying −1,146,104.62.
- **Not all negatives are overpayments.** Some are EWT awaiting the 2307 certificate and must NOT be offsettable credit.
  - Data can't classify them reliably: 128 rows are EWT-sized (≤6% of their invoice, 124,570.17), but only 5 exactly match an EWT rate of their own invoice.
  - Needs a per-row list: OVERPAY / EWT-PENDING / OTHER. I offered an Excel export with an "EWT-sized" hint.
- **GL:** the opening ticket (mnemonic `*`, 2026-07-31, AR-Trade 101030101 = 165,433,465.56) has no 20115 leg, so the credits are probably inside AR (net, as in Peachtree). Accountant to confirm.
- **Options:**
  - **A (Peachtree style):** list negatives as CREDIT rows, tick them into a per-voucher credit pool, new payment type (e.g. `BFCREDIT`), post + reversal changes; no GL if the credits are inside AR.
  - **B (recommended):** one-time load of each negative as a typed opening credit, recorded as payment detail rows under one "Peachtree BF" header, and close the rows to 0.
    - `OVERPAY` rows then feed `sp_GetCustomerAvailableCredit` and the inline copy of that formula in `sp_AddPaymentClient` unchanged; `EWT-PENDING` rows are excluded automatically.
    - Reclass ticket DR 101030101 / CR 20115 for the OVERPAY part only. Staff use the existing Offset column.
    - First check that no report reads payment detail rows as cash collected.
- **⚠️ Urgent, separate, not fixed: 504 positive balance-forward rows (60.75M) were partly paid in Peachtree.** `Balance` was loaded directly while `AmountPaid = 0`.
  - `sp_AddPaymentClient` recomputes `Balance = TotalAmount − (AmountPaid + EWT + Discount + Offset)`, so the first payment leaves a wrong balance. Example: D_122462, total 3,450, balance 1,150 → paying 1,150 leaves 2,300.
  - None touched yet. Same trap for any negative row sent through today's post (C-000900 would become +295,319.20).
  - Fix choice: one-time `AmountPaid = TotalAmount − Balance` on inconsistent balance-forward rows, with a backup table first (recommended), OR incremental balance math in post + `sp_ReversePaymentClient`.
  - **2026-10-07, script 43 built (user's choice: TotalAmount = the Peachtree balance).** Source `ARAGING3$` (INVOICEAMOUNT / BALANCE), matched on InvoiceNo + TransactionDate. 760 rows on DEV and on STAGING, the same ones as the user's `TransactionChargeSalesForCorrection10072026` (on DEV).
    - TotalAmount = BALANCE; Balance = BALANCE − what was settled here; PayStatus FULLYPAID / PARTIAL.
    - The ClientLedger BF rows were also at INVOICEAMOUNT (DEV +33,996,341.98). Negatives were posted as a debit of the full invoice (B_045745: Debit 65,894.50 for a −2,138.60 credit). They now carry the balance; negatives go to Credit. `trg_ClientLedger_Recalc` recomputes the chains.
    - The GL is untouched: the opening ticket was built from the balances.
    - Paid more than the Peachtree balance (left negative, for the accountant): 3 × 0.01 (00009542), DR 2607-059 −1,157.80 (00003902), and on STAGING also R-005414 −500.70 (00009053). Each one paid the full invoice amount, so either the customer overpaid or the Peachtree payment was counted twice.
    - Not checked yet: PRODUCTION (7701), which most likely has the same rows.
- **Questions for the user / accountant:**
  1. Is the opening AR net of these credits?
  2. The Peachtree entry that created the EWT negatives, and the entry when the 2307 arrives (DR Creditable Withholding Tax / CR ?).
  3. The classification list.
  4. Option A or B.
  5. The 504-row fix choice (can be done before the rest).
  6. Is 20115 (COA says "ADVANCES FROM ACCOUNT MANAGERS") the right customer-credit account?
- Unverified: 3 other negative rows (−10,190, FULLYPAID) whose columns are consistent, i.e. some screen let a payment exceed the invoice. Query blocked by a transient permission-check error.

## Feature 13 — Tooling: Dependency Atlas + Process Trace (2026-09-30 / 10-01)

- **Dependency Atlas** rebuilt with tables + table types and a builder script (see CLAUDE.md). Artifact https://claude.ai/artifact/ExWdEYaxmbU9VMZbLpumWa.
- **Process Trace**, the replacement for the user's Excel trace sheets (see CLAUDE.md). Artifact https://claude.ai/artifact/Bmoqk3GnfkQefi74rbnRkU.
  - AR Payment. Samples: 5155 (cheque + EWT, 3 invoices) and 5591 → reversed → 6163 (cash + overpay).
  - Sales Order (added 10-01, listed first). Samples: PO 9496 (VAT + VAT-exempt, 2 SI tickets) and PO 7375 (3 lines cancelled and re-scanned).
    - The user's name `AddSalesOrder.cs` doesn't exist; the form is `Orders/AddOrder.cs`.
    - Findings (on the page, not fixed):
      - `sp_CancelDeliveryFIFOJFC` restores one lot only.
      - Approval, reject and invoice-number updates are string-built SQL.
      - `sp_ConfirmOrder` overwrites `DateApproved`. With auto-approval, `ApprovedBy` is blank on every order.
      - Inventory ledger remarks say "STS" for sales orders.
      - Invoice uniqueness is checked only against DeliverySummary.
  - Supplier Payment (added 10-01, expense mode). Samples:
    - 686: single-branch cheque.
    - 688: multi-branch, 3 branch shares.
    - 735 → 736 → 737: overpay credit applied, reversed, applied again.
    - 628: cash voucher reversed.
    - Findings (on the page, not fixed):
      - `spu_PostExpenseV2` writes `SupplierLedger.TicketReference` from a second `GetTicketNumber` call. All 379 SNGLE ledger rows point to a ticket that doesn't exist.
      - `sp_PostSupplierPaymentWithManualLines` isn't atomic (V2 commits before the manual lines run).
      - The reversal's "already reversed" guard checks `CheckVoucher` only, and the `sp_ReverseCombinedSupplierVoucher` wrapper has no transaction.
      - Reversal tickets keep Status POSTED and the original Mnemonic.
      - SupplierKey vs SupplierID naming is mixed (equal for all 138 suppliers today).
    - PURCHASE mode not traced yet (only 3 vouchers on DEV).
  - Static bundle for colleagues: `CORECS_Tools_Static.zip` in the repo root (not committed). Rebuild it after republishing.
  - **Next module: user to pick** (Expense / STS / Conversion / …).
- **2026-10-08: Vouchering: Telegraphic added** (`modules/VoucheringTelegraphic.json/.sql`: `VoucheringManualFrm` → `sp_PostVoucherManual`). The old "Supplier Payment" module is renamed "Vouchering: Cash / Check".
  - Samples are production vouchers 897 (FX gain), 896 + 906 (partial, then final with FX loss) and 799 (13 invoices). All telegraphic vouchers pay PURCHASE invoices (APAccounts).
  - The page is now built from STAGING (production copy), names masked. The other modules give identical tables there. Republished as version 4.
  - Findings on the page: TelegraphicVoucher.CreditGLCode is blank (the bank account is in OfficialReceiptNo); APAccounts.AmountPaid = cash (an FX loss makes it exceed ActualCost); TransactionPaymentAP.DatePaid = the posting date. No reversed telegraphic voucher yet.
  - `CORECS_Tools_Static.zip` not rebuilt yet.
- `tools/ProcessTrace/` and `docs/process-trace/` were not committed yet as of this entry.
- Git: on 10-01 `main`'s uncommitted `ClientPaymentsDevExAcctg.Designer.cs` / `.resx` + build output were stashed (`stash@{0}`, "main WIP …") before switching back to `laptopdell`. They're still in the stash; nothing is applied.

## Feature 14 — Sales Order lifecycle fixes (script 19, 2026-10-01, on DEV)

- **Scope:** place → approve → process (scan) → cancel line → save → invoice no. → confirm → credit memo → return.
  - Forms: `Orders/AddOrder`, `Orders/POForApproval(Details)`, `Orders/AddBranchOrder`, `HOForms/ViewForDeliveryDetails`, `HOFormsDevEx/ConfirmOrderDevEx`, `HOFormsDevEx/CreditMemoDevEx`, `Orders/ReturnSalesOrder`.
  - No C# change: every procedure keeps its parameters.
- **User rules (10-01):**
  - Credit memo = shrinkage. The missing qty's cost goes to COS OTHERS (503 VAT-exempt / 504 VAT); no stock back.
  - A credit memo or return larger than the unpaid balance → the excess becomes customer credit (OVERPAY in the AR pool, GL 20115).
  - A return restores and credits ActualQty (the billed qty).
- **Bugs fixed (proven with rolled-back lifecycle tests on DEV):**
  - Cancel restored only the last lot of a scan that spanned lots.
  - Credit memo before confirm credited the client ledger and confirm billed the reduced qty too (counted twice).
  - Return ignored payments (reset the invoice to UNPAID).
  - A second return subtracted the running total of all returns again (invoice went negative).
  - Return after a credit memo credited the delivered qty, not the billed qty.
  - VAT-exempt returns never reversed COGS (CM-CLIENT-VATEX cost rows inactive). STAGING history: 135 lines, 2,125,661.70.
  - BatchSalesSummary was never updated by returns (CashierTransNo filter). STAGING: 59 POs.
  - Credit memo on a VAT item put cost back into GL inventory without stock.
  - Line cost after Save came from one arbitrary lot, not the weighted cost.
- **Script 19:**
  - New mnemonics SO-SHRINK / SO-CM / SO-RET (VAT and VATEX).
  - New shared proc `spu_SO_PostInvoiceReduction`.
  - Rewrote `sp_CancelDeliveryFIFOJFC`, `sp_CreditMemo` and `sp_ReturnSalesOrder`; patched `sp_ConfirmBranchOrder`.
  - Tickets are dated today, VAT is rounded per line like `sp_ConfirmOrder`, and every ticket is checked DR = CR.
- **Testing:**
  - The sp-reviewer's 3 should-fix items are in: DeliveryNo in the weighted cost, one credit row per ticket, per-line VAT.
  - Its XACT_ABORT "leak" claim was not taken: SET options revert when a procedure returns.
  - Harness: scratchpad `lc/test_so.ps1`. 10 scenarios (A, A2, B, B2, B3, C to H), rolled back, all tie: invoice = client ledger = GL AR, GL inventory = stock movement, tickets balance, credit pool correct.
  - Deployed to COREX001 in one transaction (scratchpad `deploy_tx.ps1`), then re-tested against the live procs.
- **Next:** user UI test on DEV → STAGING. Then STS (same cancel bug; STAGING POs 11700 / 11701 have 35,733.47 stuck).
- **Open (user to decide):**
  - Repair the STAGING history (VAT-exempt return COGS 2.1M; 59 sales headers; 11 returned invoices whose balance ≠ ledger).
  - There is no reversal for a posted credit memo / return.
  - Hide the dead legacy return menu (`viewBranchOrderDetails` → `ReturnCustomerOrder` → `sp_ReturnDeliveredOrder`: wrong parameter count, never used).
  - Conversion lots carry cost 0, so sales of converted items post 0 COGS.
  - 184 sales-order invoices with plain payments don't match the client ledger (STAGING); not yet investigated (AR side).

## Feature 15 — STS lifecycle fixes (scripts 20 + 21, 2026-10-01, tested on DEV, not deployed)

- **Flow:**
  - Request: `Orders/AddOrderSTS` → `sp_AddTransferOrderRequest`.
  - Approve: `Orders/STSForApprovalDetails` → `sp_ApproveTransferOrder`.
  - Process: `Orders/ViewBranchOrderSTS` → `Orders/AddBranchOrderSTS`.
    - Scan: `sp_AddBranchOrder_JFC` → `sp_SalesQtyToInventoryQtySTS_JFC`; barcode: `sp_AddBranchOrderByBarcode`.
    - Save: `sp_ConfirmBranchOrderSTS` posts IT-HO-*.
    - Return: `sp_ReverseSTSInventoryTransfer`.
  - Receive: `Orders/ReceivedSTS` → `HOFormsDevEx/ReceivedSTSBatchModeFIFO` (the one STAGING uses: `spu_PostSTSReceiveFromFIFO`, which writes branch Inventory rows) or `ReceivedSTSBatchMode` (`sp_AddBranchInventoryBatch`). Then `sp_ConfirmBranchRecievedOrderJFC` posts IT-BR-*.
- **Bugs proven by rolled-back tests (scratchpad `sts/test_sts.ps1`, 9 scenarios):**
  - Saving twice posted the whole transfer-out again.
  - The VAT split used `InventoryDeliveryFIFO.isVat`, which the JFC deduction always wrote as 0; receipt splits by the line flag. STAGING: 309,906.00 of VAT cost was booked as VAT-exempt.
  - A short receipt left the missing cost in In Transit.
  - The line cost after Save was one arbitrary lot's cost.
  - A barcode return reset a lot to its full original quantity.
  - The normal receive skipped a second line of the same product and wrote ledger rows for cancelled lots.
- **User rule (10-01):** a short receipt is a loss at head office: DR COS OTHERS 503/504 / CR In Transit on 888.
- **Script 20 (`2026-10-01b_STS_Lifecycle_Fixes.sql`):**
  - New `spu_STS_SyncInTransit`: head office's In Transit for a PO equals the cost of its live FIFO lots, split by line VAT; it posts only the difference. Save and returns call it.
  - FIFO rows get the product VAT flag.
  - Save: weighted line cost; refused after the PO is received.
  - Return (JFC): always lot-based.
  - Receipt: posts STS-SHORT-* / STS-OVER-*.
  - Normal receive matches per barcode.
  - New mnemonics STS-SHORT-* / STS-OVER-*. Needs script 19 first.
- **Script 21 (`2026-10-01c_STS_InTransit_Correction.sql`):** runs the sync for every saved STS whose In Transit differs.
  - STAGING: POs 11699 (VAT reclass), 11700 (duplicate + VAT), 11701 (duplicate 1,900,713.41), 14100 (VAT reclass, not yet received).
  - Tested on DEV (rolled back): residuals empty afterwards; a second run posts nothing.
- **STAGING incident 10-01:**
  - POs 11700 / 11701 were hand-un-cancelled and re-saved at 13:09 / 13:18, which created the duplicate IT-HO tickets 18547 / 18554. They were received at 13:22 / 13:25.
  - Their stock is now consistent; only the GL needs script 21.
  - Someone else edited data then (and overwrote scratchpad `q.ps1` at 13:07).
- **Review and deploy:**
  - sp-reviewer blocker taken in a different form: the sync now refuses a PO whose cancelled or returned lines still have active lots (stock never restored), and the correction skips and lists such POs instead of posting (its suggested filter alone would have put GL out of step with stock).
  - Also taken: target and posted both use the whole PO; receive / return / Save share the `STSTRANSIT:<PO>` applock; THROW instead of RAISERROR in the receipt procs; deterministic TOP 1.
  - Deployed 20 + 21 to DEV 2026-10-01.
- **Next:** user UI test on DEV → STAGING (20, then 21).
- **Open:** DEV's PO 11701 (10 lots / 18,644.94 on cancelled lines never restored) needs a decision on DEV only; STAGING's copy was fixed by hand.
- **Open:**
  - Barcode scans write no stock-ledger row.
  - The receive screens make 3 separate calls (not atomic; C# change).
  - DEV's copy of PO 11701 still has cancelled lines with active lots (STAGING was fixed by hand).

## ⚠️ 2026-10-01 rule: the GL is all VAT-exempt (rework needed in scripts 19/20/21)

- User: every item posts as VAT-exempt in the GL (sales, credit memo, return, shrinkage, STS). VAT shows only on printed invoices; the month-end VAT is computed by hand. Keep the line `isVat` and VAT amounts for printing.
- Done (script 23, DEV): `sp_ConfirmOrder` (one SI-VATEX ticket per invoice), `sp_CreditMemo`, `sp_ReturnSalesOrder`, `spu_STS_SyncInTransit`, `sp_ConfirmBranchRecievedOrderJFC` all post VATEX only. Script 21 updated to the same target. Line VAT data (BSD SubTotal/TaxTotal, BSS VAT columns, TCSD SI-VAT/COGS-VAT rows) kept for printing / the month-end VAT.
- Not done (user didn't ask yet): reclass STAGING history — 348 SI-VAT tickets (Aug 1 – Sep 4; 20112 = 225,569.66) and 4 IT-BR-VAT receipts.

## Feature 16 — Exception Center (2026-10-01)

- `tools/ExceptionCenter/SO_STS_ExceptionCheck.sql` (read-only, 15 checks; see CLAUDE.md and its README).
- First run, open findings (nothing fixed yet, user to decide):
  - **STAGING X01, SO 13902:** line 2 (14016, 1,500 kg) cancelled 10-01 18:06 on the OLD cancel proc (before the 21:52 deploy). Only lot 30784 (660) was restored; **840 kg still out of lot 30778**. Repair = restore lot 30778 + ledger row + flag the FIFO row.
  - **STAGING T02, STS 11911 / 11913 / 14100:** In Transit left 224,976.73 / 109,907.78 / 275,683.95 after receipt. In each, product **13025** shipped 2,034.31 / 1,002.60 / 2,506.80 kg but was received as 4.75 / 11.10 / 19.80. **Corrected 2026-10-02: not a unit error.** Each 13025 line came from 124 / 58 / 146 lots, and the FIFO receive screen listed one row per lot; only the first lot (4.75 / 11.10 / 19.80) was received, the rest skipped as "duplicate PONumber+Barcode" (Feature 19). Old receipt proc, so no STS-SHORT: the rest is still in In Transit.
  - **DEV X01, STS 11701:** known (cancelled lines never restored, DEV copy only).
- Checked and not a problem: returns 13809 / 13821 / 14061 and cancel 14044 on 10-01 ran on the old procs, which restored stock without stock-ledger rows (hence `@FromDate` = 2026-10-02 for X02).

- **2026-10-13: consolidation plan** `docs/plans/2026-10-13_ExceptionCenter_Consolidation_AP_BankRecon_Plan.md` (user: run daily, add every module, use the web portal's Exception Center). The portal's checks are in the DB (`ExceptionDefinition`, `sp_rpt_ExceptionCenter_Summary / _Detail`): 38 on DEV (10-12), only 19 on PRODUCTION (09-25). Plan: per-module `sp_exc_<Module>_*` providers the portal procs dispatch to; registry columns (Module, Kind INTEGRITY / WATCH, ProviderProc, Owner, ThresholdDays, Action); daily SQL Agent job (PRODUCTION is 2022 Standard) with run history + "new since last run"; phase 1 = AP (10 checks) + 4 bank recon checks. Portal handoff received (`D:\SQLREF\webportal.md`): provider model accepted as `sp_rpt_exc_<Module>_*` with 4 conditions; STAGING is also on 19; no scheduler / email in the portal. Reply: `docs/handoff/2026-10-13_ExceptionCenter_ERP_Reply_to_Portal.md` (copy `D:\SQLREF\erp_reply.md`). User decisions 10-13 (plan section 7): portal only + daily digest email (counts + link) to 3 recipients via Database Mail after the 05:30 PRODUCTION snapshot job; DEV / STAGING on demand; portal session approved to apply sql/23, 26, 42 to STAGING. ⏳ portal steps 1–2 (catch-up + `sql/43` dispatcher) before the ERP builds the AP providers; Database Mail profile on 7701 = `COREX_Mail` (set up by the user 10-13; Claude's read-only login can't read msdb, so the user sends the test mail).
  - **⏳ PENDING (user, 2026-10-13): daily digest email, set up later; findings are read in the portal meanwhile.** Done so far on 7701: `Database Mail XPs` enabled; profile `COREX_Mail` + account `COREX_Mail_Account` (smtp.gmail.com : 587, SSL on, sender eulen.avancena@itcsi.com.ph). Test mail 1 (22:36) **failed**: the account has no SMTP login (`username` NULL). To finish: `sysmail_update_account_sp` with the login + a Google App Password (needs 2-Step Verification), or the Workspace SMTP relay (`smtp-relay.gmail.com`, server IP allow-listed, no password); a dedicated sender mailbox is suggested. Then resend the test, check `msdb.dbo.sysmail_allitems` = sent. The digest itself is built with the phase-2 snapshot job (plan section 7).

- **AP findings 2026-10-13 (PRODUCTION, from the [70] checks; nothing fixed yet, user to decide):**
  1. **PV-AP purchase payments write the supplier-ledger row as a CREDIT** (4 rows, 4,363,758.48: DR-00565-TVP, RF-2241 BELLY, SI-457557 / SI-457594-FRIES). Supplier balances overstated by 2× = 8,727,516.96. GL / cheque side fine. Needs a proc fix (the ledger side of PV-AP posting, `sp_AddPaymentSupplierCompound_V2` PURCHASE → `sp_PostCompoundTicket` ledger write) + a data repair of the 4 rows (the recalc trigger re-chains).
  2. **Split-bug vouchers on PRODUCTION not covered by [66]:** → fixed by script [73] (DEV + PRODUCTION 10-13). 684 (+0.01, live on PRODUCTION, reversed only on STAGING), 914 (+0.02), 934 (+0.49), 967 (+0.71, partial payment of SOA-091426); keyed 10-09 / 10-10 before [61]; recon items open. Correction like [66] once the cheque amounts are confirmed (967 is a partial: [66]'s FULLYPAID guard needs adapting).
  3. **6 expense entries with Balance NULL** (5 × supplier 000023 "BOXES FOR … (REVERSED PREPAYMENT)" keyed 09-29 by merlyn borres, + CI-0002483-REVERSAL). **Corrected 10-13:** they are reclasses with no payable line, nothing owed (the first reading "can't be paid / ledger under another invoice no." was wrong: the ledger Credit was NULL). Fixed by [72] (DEV + STAGING + PRODUCTION 10-13).
  - Finding 1 → fixed by [71] (DEV + STAGING + PRODUCTION 10-13).
  4. **Balance-forward mismatches (accountant):** SI-1000066010 (expense loaded at 213,305.16, ledger BF 86,160.61 → shows 127,144.55 owed, ledger 0); SI-202511383 RIBS (ledger BF 5,289,699.77 vs purchase 1,902,440.76 → ledger shows 3,387,259.01 owed on a paid invoice).
  5. **STAGING only:** cheque 2384570 recorded cancelled (916) then issued on live voucher 917 (10-13): the payment screen doesn't refuse a cheque no. spent on a cancelled record. → guard [74] (DEV + STAGING + PRODUCTION 10-13). The test pair 916 / 917 was deleted from STAGING by [75] (2026-10-14).

## Feature 17 — Partial return, Sales Order + STS (PLAN ONLY, 2026-10-01, nothing built)

- Plan: `docs/plans/2026-10-01_PartialReturn_SO_STS_Plan.md`. Ask: return 50 of a 100-qty line from Orders for Approval › Delivered › Return Order.
- Today a return is whole-line only: the line is the unit of state in 4 tables (`DeliveryDetails.isReturned`, `InventoryDeliveryFIFO.isErrorCorrect`, `BatchSalesDetails.isCancelled`, `TransactionChargeSalesDetails.ErrorTag`).
  - Adding a qty column would touch 54 / 39 / 43 SQL objects.
  - `InventoryDeliveryFIFO` is inserted positionally by the DispatchPerBarcode posting proc.
- Proposed: split the line (and its FIFO, sales and AR detail rows) into kept + returned parts, then run the existing whole-line return on the returned part.
  - New optional TVP `@ReturnQty` on `sp_ReturnSalesOrder`, so the old exe still works.
  - The return is costed at the cost of the lots put back.
  - STS: phase 2, before receipt only.
- **Fixed (C# only, commit bb48873, not yet built or UI-tested on Windows):** `ReturnSalesOrder.cs` showed "Successfully Returned!" even when the proc failed (`sp()` swallowed the SqlException).
  - It now shows success only after a commit; on an error the form stays open.
  - Submit is disabled while the proc runs.
  - `HOFormsDevEx/CreditMemoDevEx.cs` has the same pattern ("Payment Successfully Posted" after a swallowed error); not fixed.
- Found, not fixed:
  - Fully paid POs can't be returned or credit-memo'd (the Paid tab has no menu).
  - The return tags `TransactionChargeSalesDetails` by product + barcode only, so it tags every line with that product + barcode.
  - `ReturnedOrderSummary` keeps the first return's reason and the latest return's tickets only.
  - At STS receiving, a partial qty is booked as a loss (STS-SHORT), never as stock back at head office.
- Waiting on the user: decisions D1–D6 in the plan, and the DEV checks in its section 5.

### 2026-10-04 — Sales Order partial return BUILT (script 36 on DEV 14:33; C# compiles)

- **User decisions (10-04):**
  - FIFO lines only. A barcode-scanned line is one labelled box: whole return only, never partial (otherwise staff open a 10 kg box and send back part of it).
  - Both tabs: For Delivery (before confirm) and Delivered.
  - Return cost = cost of the lots put back.
  - GL return dated today; the original order's sales rows are adjusted, as with whole-line returns.
  - STS, the Paid tab and credit memo are out of scope.
- **How a line is classified:** no flag exists. A barcode-scanned line's `BarcodeNo` is the source lot's own `Inventory.Barcode`; a FIFO line carries a generated sticker. On DEV: 11,763 delivered FIFO lines, 7 scanned.
- **SQL `SQL/2026-10-04_SalesOrder_PartialReturn.sql`:**
  - New type `tt_ReturnSalesOrderQty`; it must be created committed first (done on DEV).
  - New table `SalesReturnLog`: one row per returned line, with source → twin, qty, amount, lot cost, ticket and reason.
  - New `spu_SO_SplitDeliveryLine` (59110–59118):
    - Splits a live FIFO line into kept + twin (next SeqNo of the PO; max 99, because `ReturnedOrderDetails.SeqNo` is DECIMAL(2,0)).
    - The newest lot qty moves to the twin; a boundary lot row is split.
    - After confirm, the `BatchSalesDetails` row and the `TransactionChargeSalesDetails` rows are split too. Totals are preserved; the returned part is written already cancelled / ErrorTag = 1.
  - `sp_ReturnSalesOrder` gets an optional `@ReturnQty` (backup `_OLD_10042026120000`). An old exe that omits it gets whole-line returns as before.
    - New checks: stale screen 59107, qty above billed 59106, qty ≤ 0 59105.
    - Fixed: whole-line ErrorTag tagging now covers one set per cancelled sales row (product + barcode + qty), not every row of the product + barcode.
- **C#:**
  - `Orders/ReturnSalesOrder.cs` loads its own grid (parameterized) and adds:
    - a Kind column (FIFO / SCAN);
    - an editable Return Qty (ticked FIFO rows only; ticking fills ActualQty);
    - a Return Amount column with footer sums and N3 / N2 formats;
    - a confirm dialog.
  - `POForApproval` (both menus) sets the header fields, then calls `LoadData()`. Compiles; the bin copy was blocked because the app was running.
- **Tests (rolled back, scratchpad `pr/test_pr.ps1`, script applied in-tx):**
  - Partial scenarios all tie: P1–P4, P6, P7, P8a–d, P10, P13a/b. Checked each time: invoice = client ledger = GL AR; returned stock-ledger cost = GL inventory put back; all TCSD COGS = SI cost; no unbalanced ticket.
  - Old A–H scenarios are unchanged.
  - Harness note: a refusal rolls back the whole test transaction, so each refusal test has to be its own scenario.
- **Exception Center:** X05 added (a split line's live lot qty ≠ its qty; it is skipped until `SalesReturnLog` exists).
- **Exception Center S05 (2026-10-05):** a delivery fully returned before confirm (never invoiced) is no longer flagged. It had flagged POs 13747 and 13775, valid pre-confirm returns; DEV now shows S05 = 0.
- **Found, not fixed (pre-existing):** `spu_SO_PostInvoiceReduction` returns early when the gross is 0. A zero-priced line's return puts the stock back but never reverses its cost in the GL.
- **Reviews:**
  - sp-reviewer: no proven blocker. Taken:
    - The partial's sales amount = the split-off sales row (fixes a 1-cent drift on fractional weights).
    - Its invoice COGS row = the lot cost (same as the GL).
    - 59119 when a partial has no invoice rows; whole-line tagging falls back to the old match.
    - 59108 for a line that is no longer open.
    - No HOLDLOCK.
    - One transaction with a post-check; no grants exist.
  - sp-reviewer, not taken: S8 (variable types already match the columns). S7 / S9 are existing patterns and moot with one sticker barcode per line.
  - ui-form-reviewer: no blocker. Fixed:
    - CloseEditor in SelectionChanged;
    - rows with ActualQty 0 can't be ticked;
    - Return Qty rounded to 3 decimals;
    - grouping off;
    - the stray SortInfo.Clear removed.
  - ui-form-reviewer, not done (cosmetic): hide internal columns (isSettled, ProcessedBy...).
- New tests P14 (10.005 kg at 1.50: the invoice ends exactly at the remaining line) and P15 (lots at 193.29 / 250: returned COGS row = GL = 1,829.87) pass.
- Dependency Atlas rebuilt from DEV (`-RegistryKey AAITCRE\ConnSettingsServer -Catalog COREX001`) and republished.
- **Next:** user UI test on DEV with the new exe (close the running app, then rebuild); then STAGING on the user's go.

## Feature 18 — Dispatch Per Barcode (STS) review (2026-10-01, review only, nothing changed)

- Review: `docs/reviews/2026-10-01_DispatchPerBarcode_Review.md`. The user plans to replace `AddBranchOrderSTS` with `HOFormsDevEx/DispatchPerBarcode` (08-24, never used; its menu is hidden).
- **Not on COREX001:** all 8 of its SQL objects are missing in the Atlas snapshot (09-30), so the form fails on open.
- It predates the 09-29 FIFO standard and the 10-01 STS redesign.
- Critical:
  - Destination stock is created at dispatch, and a reverse or an unticked receipt line never removes it.
  - A reverse on a partly dispatched PO (`isProcess = 0`) leaves In Transit posted.
  - A non-888 origin posts In Transit on the origin, but the sync counts 888 only.
- High:
  - Answering "No" on a PO switch posts under the wrong PO.
  - Applock is on DeliveryNo, not `STSTRANSIT:<PO>`.
  - No stock-ledger rows.
  - The Posted tab lists every delivery, sales orders included.
  - Barcode is used as a line key.
  - Eligibility ignores the IsWarehouse rule.
  - Latent: the positional FIFO insert likely writes the lot VAT flag into `isErrorCorrect`.
- The user's concern is confirmed: no requested-items panel (`AddBranchOrderSTS` and V2 show the PO's items).
- **User decision (10-01): V2 (`Orders/AddBranchOrderSTSV2`) replaces `AddBranchOrderSTS`.** Dispatch Per Barcode stays hidden and unused.
- **Alignment pass = script 24 `SQL/2026-10-01f_STS_V2_Alignment.sql`.**
  - It patches the live text of 4 procs by exact anchors; nothing changes if the text differs.
  - It keeps backups `_OLD_10012026230000`, and the rename + create runs in a TRY/CATCH with a post-check.
  - Every STS writer now takes `STSTRANSIT:<PO>` first.
  - `spu_PostSTSLineV2`:
    - Takes the lock.
    - Refuses once the branch has received or started receiving (59834; receive step 1 writes `ReceivedOrderDetails` before step 3 sets DELIVERED).
    - Refuses once the transfer is saved (59835; the form closes after Save, so only a stale screen can still add lines). It no longer calls the sync, so no posting runs nested under its `XACT_ABORT ON`.
    - Refuses a second DeliveryNo for the PO (59836).
    - FIFO and line isVat come from the product flag.
  - `spu_ReverseSTSLineV2`:
    - The same lock and 59834 guard.
    - `spu_STS_SyncInTransit`, dated today, replaces its own ITR-HO-VAT/VATEX tickets.
  - `sp_ConfirmBranchOrderSTS` (Save, shared with the old form): takes the lock first. It used to take it last, inside the sync, which could deadlock with the V2 procs.
  - `spu_PostSTSReceiveFromFIFO`: locks `STSTRANSIT:<PO>` instead of the bare PO number.
  - No parameter changes; only a comment changed in `AddBranchOrderSTSV2.cs`.
- **Verified so far:**
  - Simulated on the repo copies: all 12 anchors and the block banners match once.
  - The patched procs and both scripts parse (sqlfluff T-SQL; negative control flagged deliberate errors).
  - sp-reviewer: no blocker. Its should-fixes are all in: receive lock and guard, no sync in post, deploy post-check, and a test that proves its claims.
- **Not yet run on any database.**
  - Next on DEV: script 24, then `SQL/2026-10-01f_STS_V2_Alignment_Test.sql`, then the Exception Center, then rebuild the Atlas.
    - The test needs `@PONumber` (a fresh request) and `@User` set; leaving `@PONumber` NULL lists candidates.
    - It has 7 rolled-back parts with PASS/FAIL lines, plus an optional two-session lock check described in its header.
  - STAGING: after 13 + 14, with the new exe.
- **Known limits (not fixed):**
  - `sp_PostCompoundTicket` source isn't in the repo.
  - The non-JFC receive proc isn't on the lock protocol.
  - Old-form scan procs take no PO lock, so they can deadlock with V2 on the same PO (the victim rolls back cleanly); hide the old form once V2 is live.
  - DEV PO 11701 (X01): V2 post and cancel there fail with 59605, by design.
- Still open (Dispatch-only, moot unless revived): non-888 origins; over-dispatch tolerance; eligibility per branch.

## Feature 19 — STS FIFO receive skipped all but one lot of a line (2026-10-02, script 25)

- **Report:** DEV PO 13721 (V2), 100 kg of 13035 → receiving said "duplicate PONumber + Barcode".
- **Cause:** `funcview_InventoryDeliveryFIFOForReceiving` (rows of `HOFormsDevEx/ReceivedSTSBatchModeFIFO`) returned one row per FIFO lot. A line taken from several lots showed several rows with the same barcode; `spu_PostSTSReceiveFromFIFO` received the first and skipped the rest. The new receipt proc then booked the rest as STS-SHORT (DEV 13721: 31.45 kg, 2,278.92); the old one left it in In Transit.
- **Fix (script 25, DEV):** function = one row per line (qty = its live lots; source = largest lot; matches DeliveryNo). Proc adds up rows per line (stale screens), resets per-line variables (DECLARE in the loop kept the previous line's lot), picks the largest lot deterministically. No exe change.
  - Multi-lot lines are received at the line's 2-dp weighted cost, so a few cents can go to STS-SHORT (e.g. 7,246.05 shipped vs 7,246.00); GL stays consistent with branch stock.
- **Exception Center T05** added (multi-lot line received as exactly one lot's qty). Finds STAGING 11911 (2,029.56 kg not booked) / 11913 (991.50) / 14100 (2,487.00) and DEV 13721 (31.45).
- **Open (user):** deploy script 25 to STAGING; repair the 4 receipts (complete branch stock + ReceivedOrderDetails + IT-BR for the rest; on DEV 13721 also reverse the STS-SHORT 2,278.92). Confirm with branches 012 / 005 that the full qty arrived first.
- **Per lot (script 26, DEV, user rule 2026-10-02 on PO 13727):** the receipt must mirror the dispatch stock ledger. `spu_PostSTSReceiveFromFIFO` now writes, per source lot, one `ReceivedOrderDetails` row (lot ReferenceCode + cost), one branch `Inventory` row (lot ShipmentNo / ReferenceCode / cost, line barcode) and one `InventoryLedger` row `STS RCVD ITEM PO#<po>`.
  - The line's received qty fills its lots in dispatch order; a short comes off the last lot(s) (user's choice); an over receipt goes on the last lot. Received cost is exact per lot (no average-cost cents).
  - Two branch rows can now share a line barcode. Checked: branch stock is consumed by product + lot SequenceNumber (`sp_doFifo`, branch transfer), POS finds products via `Products.Barcode`; STAGING branches have 0 shared barcodes today, head office already has 12.
  - Exception Center T05 now ignores receipts that wrote `STS RCVD ITEM` ledger rows (fixed proc), so a real short equal to one lot isn't flagged.
  - DEV PO 13727 was received before script 26 (one 30 kg row under lot 12); not repaired.
## Feature 20 — Process Sales Order V2 (2026-10-02, built on DEV)

- Plan: `docs/plans/2026-10-02_AddBranchOrderV2_Sales_Plan.md`. Why: the product scan (`sp_AddBranchOrderHRI_JFC` → `sp_FiFoMappingHRI_JFC`) ignores `IsWarehouse = 1` and takes no lock (oversell race); no order-level lock; nothing stopped lines after Save.
- **User answers:** start on DEV now; no cancel once the invoice number is set; accept over / short as scanned; default method SCAN; old-form scan procs take the lock too; partial return as in STS. JFC vs ENZO IsWarehouse: JFC keeps all lots at 1 (checked: every lot with stock is 1 on both DBs).
- **SQL (script 27, `2026-10-02c_SalesOrder_V2_FIFOEngine.sql`, on DEV 2026-10-02):** `sp_SOOrder_Lock` ('SOORDER:<PO>'), `funcview_SOV2_*`, `spu_PostSOLineV2` (59840–59846, ledger `SO OUT PO#`), `spu_ReverseSOLineV2` (59850–59854, ledger `SO CANCEL ITEM PO#`). Patched (backups `_OLD_10022026160000`): Save `sp_ConfirmBranchOrder` now one transaction + lock + refused after invoice (59847); Confirm, credit memo, return, cancel line and the 3 old scan procs take the lock.
- **Tests (rolled back):** old-form scenarios A–H all tie with the patch (39 steps); V2 harness `lc/test_so_v2.ps1` 13 scenarios pass (AUTO multi-lot, BATCH exact / short refused, SCAN lot, IsWarehouse=0 skipped, not on order, cancel, Save guards, invoice guards, confirm, CM + return, pay + return all).
- **C#:** `Orders/AddBranchOrderV2` (copy of STS V2, sales procs, parameterized checker / sticker queries) + admin "FIFO V2 (Test)" in `ViewBranchOrder`. Compiles; the bin copy failed only because the app was running in the debugger.
- Exception Center X02 and the Process Trace SalesOrder module now know the `SO OUT` / `SO CANCEL ITEM` / `SO RETURN` remarks.
- **Known, pre-existing:** Confirm's COGS = line cost (2-dp weighted) × qty, so it can differ from the lots' exact cost by cents (0.62 on 205 kg in the test). Same in the old form.
- **Next:** reviews (running), user UI test on DEV, then STAGING after STS V2 (needs 13 + 14 + 24 + new exe).

## Feature 21 — Bank Recon: deposits grouped by Control No (2026-10-02, script 29)

- Ask: `AccountingDevEx/BankReconFormV2` should show / group deposits in transit by the control number entered at client payment (`PaymentHeader.ControlNo`, which carries the deposit batch's CR numbers).
- **Found:** (1) `BankStatementRecon.ControlNo` never filled — `sp_AddPaymentClient` inserts one DIT per payment without it (STAGING 4,980 / DEV 2,663 rows blank; all match a PaymentHeader with a ControlNo, 576 control numbers; CASH payments have no cheque/online lines, so the header is the only source). The grid grouping / "Resolve group" (09-03 work) therefore showed one blank group. (2) `SQL/2026-09-04_BankRecon_OCBulkResolve.sql` never deployed, but the form (09-12) passes `@ItemType` → every Bulk Resolve / Resolve group failed. (3) The manual "add DIT by control number" picker would double-count auto-inserted collections.
- **Script 29 `2026-10-02e_BankRecon_ControlNo.sql`:** backfill (backup `BankStatementRecon_ControlNo_Backup_20261002`); `sp_AddPaymentClient` writes ControlNo; `sp_BankRecon_GetPeriod` DIT rows add CRNo / ReferenceNo / PaymentType / ResolvedReason (ControlNo falls back to the payment's); `sp_BankRecon_BulkResolveItems` with `@ItemType`; candidates exclude control numbers already covered. Backups `_OLD_10022026180000`. C#: captions / widths for the new DIT columns.
- Applied to DEV and STAGING 2026-10-02 after rolled-back rehearsals (DEV 2,663 filled, busiest account 2,102 rows → 239 groups; STAGING 4,980 filled, PNB 3,968 rows → 373 groups; a new payment.s DIT carries its ControlNo; bulk resolve works from old and new exe).
- Cash-advance / manual-JV DITs have no control number (stay in the blank group).
- **Reviews:** sp-reviewer — no blocker; fixed: explicit transaction + per-step `@@TRANCOUNT` guards (the script claimed one transaction but relied on the deploy helper), NULL-definition guard before renaming `sp_AddPaymentClient`. Re-rehearsed both DBs. ui-form-reviewer — no blocker.
- **Script 30 (`2026-10-02f`, DEV + STAGING):** OC grid shows ControlNo / CheckNo / voucher no. / source from the issuing voucher (STAGING AP 140 / 143 with control no.; 174 cheques with cheque no.; manual JV has no voucher).
- **Combined grid (C#, needs the new exe):** one grid on the tab replaces the side-by-side DIT / OC grids (built in code; `tablePanel1` / `panelControl6` hidden): Kind column, grouped Kind → Control No with count + Amount total (user: no cross-kind grand total), one button bar reusing the existing methods, Bulk Resolve shows counts by kind and control numbers (warning icon when > 1). ui-form-reviewer: no blocker (its GroupFormat finding was wrong — the string was DevExpress's default; the line was removed).
- **CV # (scripts 31–32):** the CV number is kept in the vouchers' `NotedBy` as a stopgap (`sp_Payment_CreateVoucherHeader` writes `@CheckCoding` there). A new column on `CheckVoucher` is NOT safe: `Accounting/AddCheckVoucher.cs` and `HOForms/TransactionPayment.cs` (still on the menu) insert positionally. User first chose a separate table (script 32), then confirmed both screens are retired, so: `CheckVoucher.CVNo` (script 33), filled by the three in-use writers from the CV number they already receive; NotedBy still written for now (printouts may read it). Telegraphic / cash CV # = ControlNo. The retired screens (AddCheckVoucher, TransactionPayment → `sp_AddPaymentSupplier`) will fail if opened — consider hiding their menu entries. Bank Recon no longer lists reversed items (ResolvedReason REVERSED / VOIDED%).
- **2026-10-06, combined grid (C# only, built):**
  - Hidden (user): Check No, Pay Type, Source, Payment Ref / Voucher No. The data is still loaded; Bulk Resolve is unchanged.
  - On load, Kind groups are open and Control No groups closed (user changed it the same day; it had been all open).
  - Highlights (user): Kind rows bold on a light-blue band (214,228,245, navy text); a Control No row whose items are all cleared is soft green (226,239,218 with dark-green text, readable in the Black skin too), "(no control no.)" included. A fully cleared batch has no check box.
  - Right-click menu: "Clear Entire Batch (Control No)" added. It runs the same code as the "Resolve Entire Batch" button and is enabled on a row or Control No group that has a control number.
  - Fixed: a selected auto-inserted row showed white text on its light row colour (`View_RowCellStyle` overrode the skin's selection background). The focused row is now left to the skin.
  - Period End (`dtPeriod`) now has its calendar drop-down: the designer had no `Properties.Buttons` Combo button (same as Feature 6).
  - **2026-10-07, AccountingReportsFormV2 audit (STAGING, every account vs TicketDetails, Aug all / Aug 888 / Sep).**
    - All ledger-based ("Real-Time") reports tie: TB, BS (current earnings = net of the P&L accounts; A = L + E), IS + pivot, GL Detail Ledger, GL Detail Transaction, Consolidated GL, General Ledger (after 40).
    - All GLSummary-based ones are wrong (up to 90 of 167 accounts; BDO stuck at the July opening).
    - Bank Reconciliation (Real-Time) used the branch's GL only and no bank items: fixed by script 41.
    - C# (user): the 7 GLSummary entries are commented out; the ledger-based ones are renamed to the plain names ("Trial Balance", ...). Built. The old `Reporting.AccountingReportsForm` is only behind a hidden button.
    - Note for the accountant: a single-branch TB doesn't balance (888 Aug −780.46M), because cross-branch entries have no due-to / due-from.
    - 2026-10-08 (user): the description column (TransDescription / Trans Description / Particulars) of General Ledger, GL Detail Ledger and GL Detail Transaction opens at most 260 px (`TransDescriptionWidth`) after the best-fit. It is still resizable and cut-off text shows as a hint. PDF / print use the same width (offered: wrap in exports only). Built 22:36.
  - **2026-10-07, GL Consolidated report wrong (script 40).** Found while checking the recon's GL (STAGING BDO Aug: report −15,779,218.29 vs recon −15,933,885.11).
    - The report joined lines to TicketMaster without BranchCode, so a cross-branch JV with 13 branch masters (e.g. 13243) counted each line 13×. Salaries Aug 34.8M vs a true 20.7M; 20103 off by 20.9M; BPI bank by 12.5M.
    - It also excluded Status REVERSED, which is on the reversal entry, so reversed OR payments kept counting.
    - Fixed: amounts from TicketDetails alone, the same rule as the real-time Trial Balance and the recon. The recon figure was right.
  - **2026-10-07, figures fixed (script 39).** User: GL Book Balance = cumulative GL ending balance, all branches.
    - Bugs (DEV):
      - the header query returned every header up to the picked period and the form took the first, so picking September used July's header for Save, figures and Lock;
      - GL Book Balance was the month's net movement, computed only on Save, own branch only;
      - Lock compared a stale GL figure, this month's items only, without bank-side items.
    - Now:
      - one function (`fn_BankRecon_Figures`) gives every figure, the same formula as the screen;
      - GL is live while open and a snapshot once locked;
      - the form snaps Period End to month end.
    - The accountant's procedure was written for the user in chat (2026-10-07).
  - **Summary view (user, 2026-10-06), a second display beside the grouped one.** A View switch (Summary default / Detailed) sits on the button bar.
    - No Kind grouping and no expandable details: one row per deposit-in-transit Control No (amount in Debit) and per outstanding-check CV # (Credit). An item without one is its own row.
    - Status per row: CLEARED (green) / PARTLY CLEARED / OPEN. Footer sums Debit and Credit.
    - Clearing by row: Bulk Resolve (ticked rows), Clear Entire Batch (button and right-click), Select All. Detail-only buttons are hidden in this view.
    - Data: `sp_BankRecon_GetPeriodSummary` (script 38). Its DIT / OC rows are copied from `sp_BankRecon_GetPeriod`; keep the two in step.
    - ui-form-reviewer: no blocker. Fixed:
      - any load error falls back once to Detailed (Summary disabled, one message) without skipping the lock state;
      - a DIT + OC clear is one reload with one message and stops at the first failure (`ResolveReconIDsNoReload`);
      - Bulk Resolve uses visible ticked rows only;
      - display-text guard.
  - The first group under each Kind is "(no control no.)" (blanks sort first), so it has no check box, by design (user agreed).
  - Each Control No group row has a check box. It ticks or unticks every uncleared item of that batch, collapsed rows included, and shows grey when only part of the batch is ticked.
  - No box on Kind rows, on the "(no control no.)" group, or while the period is locked.
  - Groups open by default: `ExpandAllGroups` now runs after `EndUpdate`; inside `BeginUpdate` it never took effect.
  - ui-form-reviewer: no blocker. Fixed:
    - a box click no longer re-opens collapsed groups (no `RefreshData`);
    - the tick state is cached, not rescanned on every paint;
    - the gap before the text is sized from the font;
    - the box has a transparent background;
    - a double-click on the box doesn't fold the group.
- **2026-10-07, July balance forward from Peachtree (script 42).** Source: the accountant's July Peachtree recon workbook (sheets BDO PESO 1 / BDO PESO 2 / WB / MBTC 1-1 / MBTC 2 → 101020101 / 102 / 104 / 107 / 108).
  - Each account gets a July 31 header on 888 with Peachtree's ending bank balance. DIT → DIT, outstanding checks → OC, and "Add (Less) Other" GJ items → DIT if positive, OC if negative. Every row is `SourceModule = 'BF-PEACHTREE'`, keeps its original date, and has `ControlNo` = the Peachtree reference. The items carry forward until cleared.
  - July 31 differences: 0 on 101 / 107 / 108; −1,978,452.67 (BDO PESO 2) and −1,000,050.00 (WB). Both are Peachtree's own unreconciled differences, for the accountant to explain. The BDO PESO 2 sheet's Cash Disbursements is entered as a positive 9,363,742.65.
  - Left out: BDO PESO 2 OC X2607-067 (15,898.47). Our July 31 GL is exactly that much above the sheet, because the opening ticket doesn't include the check. If it was really issued, book it with a Manual JV, whose auto-OC creates the item.
  - August differences move until staff tick the July items that cleared in August (e.g. BDO PESO 1 Aug 250,535.38 → −6,973,407.99).
- **2026-10-08, GL vs recon check (STAGING = a restore of PRODUCTION, 19:21).** New read-only `tools/ExceptionCenter/BankRecon_GLvsRecon_Check.sql`: every GL reference on a bank account since 08-01 has its DIT / OC item, except 3 findings, which scripts 44 / 45 fixed. It is clean now.
  - No August or later period is reconciled: only 2 statement balances are entered (BDO PESO 1, PNB PESO Aug), and no item is ticked.
  - **No July opening list** for PNB PESO, PNB PESO 2, BPI PESO 1, UNION PESO 1 and the USD / EUR accounts. The Peachtree workbook had 5 accounts only, so their August can't reach 0. Asked for their July Peachtree reconciliations.
  - USD / EUR: the GL is in pesos and the statements aren't. Open: what to type as the statement balance.
  - Cash advance 133 (ref 13157, the duplicate of 694) still shows 1,294,034.25 to liquidate; left for the accountant.
  - **Design gap fixed by script 46 (DEV 10-08):** before it, an item had no "cleared in which month", so a July item ticked in August also left July, and a locked July's items could never be cleared in August.
    - C# `BankReconFormV2`: passes `@PeriodEnd` on Mark Cleared / Uncleared, Bulk / Batch / summary and Post Payment.
    - New "Cleared In" column; "(later)" when the month on screen is earlier.
    - An auto-debit cleared in a later month can't be posted or deleted again from an earlier month: the payment posts before the item is marked, so this would double-pay.
    - Built 22:07 (bin). Reviews 10-08:
      - ui-form-reviewer: fixed: `_period` only moves after a successful load; Post Payment re-reads the row before paying.
      - sp-reviewer: fixed: script 48 (no silent move; old-exe stamp); lock guard (93411) added to script 44 before production.
      - Checked on the production copy: RCSI off; no non-month-end headers; nothing locked.
      - Not fixed (pre-existing, noted): `sp_BankRecon_UpdateItem` (old forms, not on the menu) doesn't stamp the month; lock-vs-clear can deadlock (1205, the victim rolls back; retry).
      - Not fixed: DeleteItem / SaveItem have no lock check.
      - Not fixed: JV / multi-branch expense edit deletes and re-posts recon rows, so a cleared JV item comes back open after an edit.
      - Not fixed: `sp_PostSupplierPaymentWithManualLines` updates an OC amount without checking cleared / locked.
      - Not fixed: the old GLSummary bank recon reports aren't period-aware (retired).
  - **⚠️ Auto-Match Cleared Checks (`sp_BankRecon_AutoMatch`) clears outstanding checks from their own GL credit, not from the bank.** Rolled back on STAGING Aug: BDO PESO 1 21 cheques (3.57M), BDO PESO 2 37 (15.96M), MBTC PESO 2 20 (28.07M) ... cleared with no bank evidence. User 10-08: both Auto-Match buttons hidden in `BankReconFormV2` (new exe); the proc is kept.
- **⏰ REMIND THE USER (open since 2026-10-09):** the reversal answer came 10-09 (scripts 50 / 51 below). Still waiting: July Peachtree lists for PNB PESO / PNB PESO 2 / BPI PESO 1 / UNION PESO 1 / USD-EUR accounts; USD / EUR statement-balance rule; cancel cash advance 133.
- **2026-10-09, Export to Excel (C# only, built 10:22).** `BankReconFormV2`: an "Export to Excel" button next to Print.
  - It exports what is on screen: Summary or Detailed list, or Bank-Side Items.
  - Data-aware .xlsx: real numbers, groups exported open, footer sums kept, the tick-box column left out.
  - Above the table: account, branch, period, status, who / when, and the summary-box figures (Difference signed, with RECONCILED / OUT OF BALANCE).
  - Runtime-checked in a harness (header rows, open groups, Selected column restored). Not yet clicked in the app.
- **2026-10-09, undo a clear in one step (user: accidental clears).** Before this, Mark Uncleared was one item at a time and existed in the Detailed view only.
  - New: "Unclear Entire Batch (Control No)" (Detailed right-click + button), "Unclear Entire Batch" (Summary right-click + button) and "Bulk Unclear" (ticked cleared rows, Detailed view). All go through script 49.
  - Summary rows find their cleared items client-side (Control No for DIT, CV # for OC, else the row's own item). Checked against the server's ClearedItems: DEV 43 / STAGING 33 rows, 0 mismatches.
  - Built 10:32.
- **2026-10-10, tick = cleared at once (user: "if they ticked it just update immediately").** C# only, `BankReconFormV2`; no SQL change.
  - Detailed view: the **Cleared** column is the editable box. A tick calls `sp_BankRecon_ResolveItem` with the month on screen; an untick uncleares it. The row and figures update in place, with no reload and no confirmation (an untick undoes a tick).
  - Detailed view: the box on a Control No group row now shows the batch's cleared state (ticked = all cleared, grey = part). A click clears the rest of the batch (`sp_BankRecon_BulkResolveItems`); on a fully cleared batch it uncleares it (`sp_BankRecon_BulkUnresolveItems`). The reload keeps the open groups, the scroll position and the focus.
  - Summary view: a **Cleared** box per batch row, same rules (tick clears the row's open items, untick uncleares its cleared items).
  - Hidden: the Selected column, Select All, Check Control No, Mark Cleared / Uncleared (buttons and right-click), Bulk Resolve, Bulk Unclear. Kept: Clear / Unclear Entire Batch (buttons and right-click), Delete, Add.
  - The procs' rules are unchanged: an item cleared in a later month is refused (93013, message shown, box unchanged), a locked period can't be edited, and system-closed items are skipped.
  - **Made seamless the same day (user: a tick felt delayed; "the user will tick fast").**
    - A click changes the box, the group / summary row and the figures at once. The save goes into a queue that a background worker sends in click order, so ticking never waits for the database. The status bar shows "Saving n change(s)…", then "All changes saved."
    - If anything is refused or skipped, the period reloads when the queue is empty (open groups, scroll and focus kept) and a message says why.
    - `LoadPeriod` and closing the screen wait for the queue first. The worker only runs SQL and posts back (Known Bug #8).
    - The boxes are no longer grid editors: the click is caught in MouseDown, so there's no editor delay. Space toggles the focused row too.
    - An item cleared in a later month ("(later)") is refused on the click, before anything is queued.
  - Built 10:33 (bin). Not yet clicked in the app.
- **2026-10-12, statement balance preview (C# only, built 11:25).** Typing in the bank statement balance box recomputes the summary at once (Adjusted Bank, Difference); the typed figure shows in gold until Save, and the status bar shows the saved one. Lock and Export to Excel still use the saved balance. A reload (period load, Save, a refused tick) puts the saved balance back.
- **2026-10-12, Accounting Board opens screens faster (C# only, built 12:24).** The first open of a menu item builds the screen and runs its lookups; each lookup is a network round trip (~55 ms, a new connection ~400 ms).
  - `AccountingBoard.SelectAndLoad`: page transition animation off; the page switches and paints at once with DevExpress's loading overlay (`SplashScreenManager.ShowOverlayForm`) while the screen loads.
  - New `Database.FetchTables(dict)`: several constant SELECTs in **one batch, one round trip**. Parallel queries were tried and measured slower (each needs its own connection).
  - `SupplierPaymentDevEx.LoadData`: 8 round trips → 1 (lookups 515–735 ms → 68–139 ms; screen 0.8–0.9 s → 0.36–0.47 s).
  - `ClientPaymentsDevExAcctg` Load: the customer list (10,731 rows, ~2.8 s of network transfer, 15 ms on the server) loads in the background; the dropdown shows "Loading customers…" until then. The account list is fetched once for the 7 lookups (screen 1.1–1.4 s → 0.44–0.58 s).
  - Other board screens are unchanged (0.2–0.6 s each); the same `FetchTables` pattern applies if needed. Timed in a harness loading the built exe; not yet clicked in the app.  - `AccountingBoard.SelectAndLoad`: page transition animation off; the page switches and paints at once with DevExpress's loading overlay (`SplashScreenManager.ShowOverlayForm`) while the screen loads.  - New `Database.FetchTables(dict)`: several constant SELECTs in **one batch, one round trip**. Parallel queries were tried and measured slower (each needs its own connection).  - `SupplierPaymentDevEx.LoadData`: 8 round trips → 1 (lookups 515–735 ms → 68–139 ms; screen 0.8–0.9 s → 0.36–0.47 s).  - `ClientPaymentsDevExAcctg` Load: the customer list (10,731 rows, ~2.8 s of network transfer, 15 ms on the server) loads in the background; the dropdown shows "Loading customers…" until then. The account list is fetched once for the 7 lookups (screen 1.1–1.4 s → 0.44–0.58 s).  - Other board screens are unchanged (0.2–0.6 s each); the same `FetchTables` pattern applies if needed. Not yet clicked in the app (timed in a harness loading the built exe).
- **2026-10-09, reversals in a later month (found; fix built, scripts 50 + 51).**
  - Reversed / voided items are hidden in every month. For 16 items (14.87M, mostly Aug → Sep) that hid them from their original month, while the GL still had the original entry there. Example: BDO PESO 2 X2608-023, 5,914,761.28, voided Sep 26.
  - Sent to the accountants: `docs/reports/2026-10-09_BankRecon_ReversedInLaterMonth_STAGING.xlsx`.
  - **Accountants' rule (2026-10-09): a reversal falls into the month of its source entry, dated like the source entry.** So the GL moves, not the recon. A reversed item stays hidden in every month, and the reversal ticket carries the source date. (The rejected alternative was a reversal "cleared in its reversal month".)
  - **Script 50** (`2026-10-09b`, production data): re-dates the 18 reversal tickets of the 12 references to their source ticket's date (all lines and accounts, so they stay balanced), plus the supplier / client ledger reversal rows' TransactionDate. The recon items get ClearedPeriodEnd = source month, and ReconID 38 moves to the August period.
    - Effect on August: BDO PESO 1 Difference 2,290,814.93 → 2,204,535.35; PNB PESO −606,950.30 → −1,673,899.70 (transfer 27019 + AR 14107 now reversed in Aug).
    - Other accounts: AP 20103 Aug −70.30M → −77.49M; 404 Other Income: 870.40 moves Sep → Aug.
    - 37271 (Sep 8 → reversed Oct 6) moves to September.
  - **Script 51** (`2026-10-09c`, all DBs): reversal tickets are dated like their source from now on. Covers `sp_ReverseTicketsAP` (cheque / cash / telegraphic) and `sp_ReverseCashAdvanceEntry`. The ledger reversal rows in `sp_CancelledChequesCS` and `sp_ReversePaymentClient` take the reversed row's TransactionDate.
    - `sp_ReversePaymentClient`'s GL already used the payment date (since 09-11).
    - Audit dates (PostingDate, CancelledDate, ReversedDate) stay "today".
    - A source month closed in GLPeriodLock refuses the reversal (59900).
  - 50 + 51 on all three DBs 2026-10-09 (production by the user). Every cheque-cancel screen goes through `sp_CancelledChequesCS`, so all bank reversals are covered.
  - `sp_ReverseApprovedExpense` (`ViewExpenseDevEx`, an expense reversal with no bank leg) dated its GL ticket and supplier-ledger row today; fixed by script 52. `sp_ExpenseReversal` already uses the expense date, and `sp_CancelApprovedServiceOrder` takes the cancel date from the screen. Inventory reversals (STS / SO / stock out / conversion) are physical events and stay dated today. User 10-09: extend it to `sp_ReverseApprovedExpense` (script 52).
  - **Rule (user, 2026-10-09): a reversal whose source month is closed in the GL stays refused** (lock trigger 59900). To reverse, an admin reopens the month (GLPeriodClosingFrm), or the accountant books a correction in an open month. v2 must keep the same rule.
- **2026-10-09, handoff to the web Exception Center:** `docs/handoff/2026-10-09_BankRecon_ExceptionCenter_Handoff.md` + `..._Checks.sql`. 13 `BRC-*` checks, a shared function `fn_rpt_BankRecon_GLvsRecon`, Summary / Detail blocks in the web procs' shape.
  - Tested rolled back on STAGING + DEV: DEV still shows the duplicate transfer and the 11 wrong-period cheques fixed on production 10-08. Summary runs in ≈ 1.7 s.
- **Open (user):** "Select All" ticks rows across every control-number group (could bulk-resolve unrelated batches); `@ItemType` allow-list has no ADB (bank-side grid has no bulk resolve today); `sp_AddPaymentClient` has no double-post guard (a second run would add a second DIT to the group); open DITs carry `ResolvedDate = 1900-01-01` (written as ' '); GetPeriod lists every period ≤ the selected one, so a group can span months while the header totals are one period.

## Feature 22 — STS V2: FIFO only from unbarcoded lots; receive summed (2026-10-03, script 34)

- **User rules (10-03):**
  - FIFO (Auto / By Shipment) offers and takes only lots with a blank `Inventory.Barcode`, so it never takes part of a lot that will be scanned. Scanning is unchanged. The same applies to Sales V2 (same engine).
  - FIFO placements keep their generated sticker barcode.
  - Receive screen: FIFO lines of one product show as one summed row; a scanned line stays its own row.
  - Receipt / branch stock / ledger rows: one per line and batch (ShipmentNo + ReferenceCode + cost), no longer per lot.
  - A short comes off the last line / batch; an over receipt goes on the last one.
- **Found on DEV PO 13764:**
  - Line 2 (100 kg from 5 lots of one batch) was received as 5 rows of 20 (script 26).
  - `sp_ConfirmBranchRecievedOrderJFC` then set `ActualQty` = 20 from one joined row, and Variance = 80.
  - The engine let FIFO take barcoded lots: Auto 6,000 of 13035 took 658.34 from barcoded lots.
- **Script 34:**
  - The engine gets `@SkipBarcodedLots` (default 0; LOT mode always allowed). The STS and Sales V2 posting procs pass 1.
  - The four V2 dropdown functions count / list unbarcoded lots only.
  - New `funcview_STSReceiveLines` (LineKind SCAN / FIFO, GroupSeqNo). The receive function returns one row per group.
  - `spu_PostSTSReceiveFromFIFO` is set-based: group → lines → batches. A stale per-line screen keeps each line's own qty.
  - Confirm adds up a line's receipt rows; TotalItem = lines.
- **Grouping is opt-in (after sp-reviewer):**
  - `funcview_InventoryDeliveryFIFOForReceiving` is unchanged (one row per line), and the new grouped `...ForReceivingV2` sits beside it.
  - `spu_PostSTSReceiveFromFIFO` gets `@GroupedRows BIT = 0`. Without it, each row is one line, as before.
  - So an old exe keeps working on the new SQL (tested: V7, and V9 with partial untick + over).
  - A line whose source lot is missing is not received; it ends up in STS-SHORT. The guard 58171 refuses any line whose qty doesn't land on its batches.
- **C#:**
  - `ReceivedSTS.cs` reads V2.
  - `ReceivedSTSBatchModeFIFO.cs`:
    - passes `@GroupedRows = 1`;
    - returns each line of an unticked row and refuses a row whose line count changed;
    - names the lines already returned when one line fails;
    - Kind / Lines captions, N3 / N2 formats; the confirm dialog shows rows and lines.
  - Built.
- **Reviews:**
  - sp-reviewer: blocker (orphaned lot → phantom receipt) fixed. The rollout risk was fixed by the opt-in.
  - The rounding claim was not taken: rounding per batch is closer to the shipped TotalCost than rounding per lot.
  - Left as is: the `#Pre` path (hidden Dispatch module), a perf note on V2's OUTER APPLY, and `sp_InvFIFO_Preview` having no callers.
  - ui-form-reviewer: items 1, 2, 3, 5 and 6 fixed. Item 4 (an unticked row's edited ActualQty is ignored) is intended. Item 7 was wrong: the return proc does take the lock.
- **Tests (rolled back, scratchpad `sts/test_sts_v3.ps1`):**
  - V1–V8 all tie: In Transit 0, branch GL = branch stock = received cost, no unbalanced tickets.
  - Short / over amounts: STS-SHORT 9,004.30, STS-OVER 1,851.30.
  - Old-form S1–S11: only S10's row grouping differs (3 rows → 2, same amounts).
  - Sales V2 harness: only the refusal text differs.
- **On DEV, 3 products have only barcoded stock** and can now only be scanned.
- **2026-10-05, Sales V2 form (C# only):** `AddBranchOrderV2.displayForDelivery()` hides `TotalCost` from `funcview_SOV2_DeliveryLines`, and keeps it out of the column chooser (user: sales staff don't see cost). STS V2 (`AddBranchOrderSTSV2`) hides it the same way (user, same day).
- **2026-10-05: rule replaced by script 37 (`SQL/2026-10-05_InvFIFO_StickerRule.sql`, on DEV 18:19).**
  - FIFO now skips only **stickered** lots (user): `A01…` (supplier receiving) or 19 digits (offline app). `B01` / `C01` / `D01` are tags (no sticker), so FIFO may take them; blank too.
  - Why: branches receive STS stock with a `B01` tag barcode, so under the 10-03 rule that stock had vanished from every FIFO dropdown at the branch.
  - The rule lives in one place, the new `dbo.fn_InvIsStickerBarcode`. It's used by `sp_InvFIFO_Allocate` (anchor patch) and the 4 V2 dropdown functions; the `spu_InvFIFO_Deduct` message was reworded. Backups `_OLD_10052026120000`.
  - The user's own DEV edit of `funcview_STSV2_ProductLots` (17:10, `LEN(Barcode) <> 19`) is now its `_OLD_` backup. It let A01 supplier stickers through.
  - Effect on DEV:
    - FIFO now reaches B01 tags (HO 74,885 kg, branches 41,692 kg) plus C01 / D01.
    - A01 stays scan-only (HO 60,420 kg, branches 155,442 kg).
    - The HO B01 lots of 13035 (30735 / 30738) are FIFO-able now (user: tags, no sticker).
  - Tests (rolled back, then live):
    - The rule holds on every barcode shape.
    - Preview: a B01 batch at a branch allocates in full; an A01-only product gets 0 via Auto but its full qty via scan.
    - STS V2 / Sales V2 harnesses: identical except the intended flips (V5a / b / d) and the reworded message.
    - Exception Center: nothing new from this change.

- **2026-10-03, V2 forms (`AddBranchOrderSTSV2` / `AddBranchOrderV2`, C# only, built):**
  - Both now open on FIFO instead of Scan Barcode (user request); JFC opens on Manual (By Shipment).
  - Fixed: the Manual dropdown was empty until the user switched to Auto and back. `LoadData()` runs before the form is shown and relied on the RadioGroup's `SelectedIndexChanged`, which doesn't fire before the window exists. It now sets the type quietly and loads the list itself.
## Feature 24 — POS V2, hybrid online / offline (phases 1–5 BUILT on DEV 2026-10-12 / 13)
## Feature 24 — POS V2, hybrid online / offline (phases 1–4 BUILT on DEV 2026-10-12)

- **User 2026-10-12: all 5 recommendations.** Q1: terminals keep a local SQL Server and the local schema runs on SQL Server 2014. Q2: GL once per shift (phase 3). Q3: short stock → post anyway + shortage list. Q4: new tables, old reports rebuilt in phase 5. Q5: no restaurant / hotel options.
- **Phase 1 built:**
  - SQL scripts 58 + 59 (`SQL/POSV2/`), on DEV.
  - C# in `SalesInventorySystem/POSV2/`:
    - `PosV2Config` (registry HKCU\AAITCRE\POSV2, no credentials);
    - `Models/PosModels`;
    - `Services/PosPricingService` (VAT 12/112, the server's rounding);
    - `PosLocalSchema` + `PosLocalStore` (local DB `CORECS_POSV2`, created on first run; one transaction per sale with its OR no. and outbox row);
    - `PosSyncService` (background worker: register, master data every 30 min, outbox in order; 61010–61021 = needs attention, else retry; no UI access);
    - `Devices/PosReceiptPrinter`, `Devices/PosScale`;
    - `PosProductSearchForm`, `PosPaymentForm`, `PosTerminalForm` (keys Enter / F2–F5 / Del / F8 / F10–F12, "2.5*code").
  - `Main.openPOS()` opens V2 only when the machine has POSV2 `Enabled = 1`.
- **Tests:**
  - P1–P7 rolled back on DEV.
  - End-to-end with the real classes (harness exe): register (`001T01`, 156 products); offline (unreachable server) 2 sales kept locally; back online, both posted in 1.45 s, one line short (15125 3.41 of 5); forced re-upload = DUPLICATE, no second deduction; online sale posted 231 ms after saving. Server stock / ledger / lots verified.
  - DEV then restored exactly (14017 427,930.000 / 13035 116,814.250 / 15125 3.410), test DB, keys and exe removed.
- **Not yet clicked in the app:** the screens (PosTerminalForm, search, payment) were built and compile, but only the services were exercised.
- **Phase 1 limits (later phases):** no discounts / void / hold / shifts / X-Z read / GL / card / charge / returns. No LOT mode for stickered lots (POS takes any eligible lot by FIFO). The stock ledger is dated at upload, not at the sale time, for offline sales. The BIR receipt header is phase 5. The first run needs the server once (registration).
- The ledger remark is `POS SALE OR#<terminal prefix>-<seq>`.
- **Phase 2 BUILT on DEV 2026-10-12** (user: one STAGING update at the end, so phase 2 is folded into scripts 58 / 59; DEV re-created with `SQL/POSV2/DEVONLY_2026-10-12_POSV2_Reset.sql`, which refuses if any POS V2 sale exists):
  - Discounts: `POSV2_DiscountType` (configurable; seeded SC20 / PWD20 = 20% VAT-exempt + name and ID required, SC5 / PWD5 = 5% basic necessities, OTHER = cashier %, ONETIME = amount spread by value) + `POSV2_SaleDiscount` + line DiscountAmount / VatExemptAmount. The server re-checks every line (61022–61028).
    - Senior on a VAT item: ex-VAT = ROUND(gross / 1.12, 2), exemption = gross − ex-VAT, discount = ROUND(ex-VAT × 20%, 2), and the line is no longer taxed.
  - Void after payment: `spu_POSV2_VoidSale` restores the sale's own lots (ledger `POS VOID OR#…`), sets shortages to VOIDED, idempotent. On the terminal: the cashier's own sales of today, with a reason, as a VOID outbox event behind the SALE.
  - Hold / recall: on the terminal only (PosHold*), no OR number used.
  - Lines removed before payment: counted on the sale (CancelledLineCount / Amount) for the phase-3 Z-reading. A whole sale cleared with F8 is not recorded yet.
  - Reprint any of today's receipts (local ReprintCount).
  - New keys: F6 discount, F7 hold / recall, F9 void, F11 reprint picker. New windows: PosDiscountForm, PosListPickerForm.
- **Phase 2 tests:**
  - Server: P1–P7 + D1–D5 + V1–V2, all rolled back.
  - End-to-end with the real classes: offline senior sale 725.00 → 526.43 (exemption 66.96, discounts 111.61 + 20.00) and a one-time sale voided offline; back online, 3 events in order in 0.78 s; stock and ledger verified (void = out and back in); hold / recall round trip OK.
  - DEV then restored exactly; test DB, keys and exe removed.
- **Open for later phases:** supervisor approval for voids and large discounts (phase 3, with shifts); recording a whole sale cancelled with F8. (Both done in phase 3.)
- **Phase 3 BUILT on DEV 2026-10-12** (user: "go ahead start it"; folded into scripts 58 / 59 like phase 2; DEV re-created with the reset script).
  - **Shifts:** `POSV2_Shift`. The cashier opens a shift with the cash beginning (works offline), every sale belongs to one (`POSV2_Sale.ShiftGUID` required, 61030 / 61031), and the Z-reading closes it with a blind cash count. One open shift per terminal (filtered unique index; 61052). The Z counter is per terminal, never resets, and resumes after a reinstall (`RegisterTerminal` returns LastZNo + the open shift).
  - **Close (`spu_POSV2_CloseShift`):** re-derives every figure from the server's own rows. It refuses (61057) when the terminal's sale count / void count / net differ, i.e. a sale of the shift is still "needs attention". F12 re-queues both in order.
  - **GL once per shift (user Q2), `spu_POSV2_PostShiftGL`:** ONE ticket, mnemonic `POSV2-SHIFT`, dated the shift's opening day, on its branch, all VAT-exempt.
    - Accounts from JournalEntryMapping:
      - CASH (counted − beginning) → DR 10101 Cash on Hand;
      - DISCOUNT + VATEXEMPT → DR 40103 Sales Discount;
      - GROSS → CR 401;
      - COST → DR 501 / CR 101040201;
      - SHORT → DR 60340 CASH SHORTAGE - POS (an expense; user + accountant 2026-10-13; new account added by script 59 under 603, same placement as 60339);
      - OVER → CR 404 Other Income.
    - Legs are netted per account (#Legs), so a short bigger than the sales still balances.
    - A GL failure (closed month 59900, mapping missing 61062, ...) never undoes the close: GLStatus FAILED with the reason, and `spu_POSV2_PostPendingShiftGL` retries it (the terminal's sync calls it every 30 minutes).
    - Note: the old unused `CR-CASH` mapping uses 1010101 Petty Cash; POS V2 uses 10101 Cash on Hand.
  - **Supervisors:** `POSV2_Supervisor` holds the PIN as a PBKDF2 hash (PasswordHasher, ≥ 6 digits), separate from the login password on purpose. Admins set them with Ctrl+P (`spu_POSV2_SetSupervisor` checks Users.isAdmin, 61083). Terminals download the hashes, so approvals work offline; 5 wrong PINs lock approvals for a minute.
    - Approval needed for: a void (61045 / 61046), a discount type with `RequiresApproval` (seeded OTHER / ONETIME; 61032 / 61033), clearing a sale (F8), a no-sale drawer opening (Ctrl+D), and closing another cashier's shift (61058).
    - The server records the approver and refuses an unknown one.
  - **Void only while the sale's shift is open** (61044). After the Z-reading it needs a return (phase 4).
  - **Terminal:** shift line in the header; Ctrl+X X-reading, Ctrl+Z close (Z), Ctrl+R reprint Z, Ctrl+D no-sale drawer, Ctrl+P supervisors. A cleared sale and drawer openings are counted on the Z (local `PosShiftEvent`, sent with the close).
    - New windows: `PosApprovalForm`, `PosAmountForm`, `PosSupervisorAdminForm`.
    - New devices: `PosCashDrawer` (ESC/POS pulse through the receipt printer, RAW; registry DrawerKick / DrawerPrinter / DrawerCode) and `PosDisplayPole` (serial 2×20; PolePort / PoleBaud; failures never stop a sale).
  - **Tests:**
    - Server: S1–S19 rolled back (over 30.00 → CR 404; short 25.00 → DR 101030201; short 750 > sales nets 10101 to a credit; void out of the GL; empty shift = no ticket; retry proc; every refusal).
    - GL-failure path committed then cleaned (OVER mapping off → CLOSED + FAILED 61062 → on → retry → POSTED).
    - End-to-end with the real classes: PIN set via the admin service and checked offline; shift opened online; offline sale + approved ONETIME sale + approved void + cleared sale + drawer + Z close (counted 1,185 vs 1,180); back online, 4 events in 1.4 s; server figures = terminal's; ticket 10101 185 / 40103 20 / 401 200 / 404 5 / 501 = 101040201 = 159.02 = lot cost, DR = CR; Z#2 opened.
    - DEV restored exactly (14017 427,930.000 / 13035 116,814.250; no POS V2 rows, tickets or ledger rows); test DB, keys and exe removed. Built 2026-10-12.
  - **Reviews (2026-10-12), fixed and retested** (S1–S19 + R1–R13 rolled back, end-to-end rerun, DEV restored again):
    - sp-reviewer B1: money checks at post are now exact (61015 / 61016 / 61018 / 61022; the terminal rounds the same way), so a one-cent drift can't make every close fail. The close's own post-check now has its own code, 61065.
    - B3: a configuration change after an offline sale (type deactivated, approval / ID newly required, PCT rate changed) posts the sale with `NeedsReview` + `ReviewNote` instead of refusing it for good. New admin `spu_POSV2_ForceCloseShift` (61066) closes a stuck shift with the server's figures (ForcedBy / ForceReason); the terminal's later close = DUPLICATE.
    - B2 (trust model, system-wide: `@User` comes from the client over the shared SQL login): approvers are now checked per branch (61033 / 46 / 59). PIN hashes need ≥ 100,000 iterations. `POSV2_SupervisorLog` records every change with SUSER_SNAME / HOST_NAME.
    - S1 lock order shift → sale → stock everywhere. S2 SetSupervisor: NULL keeps the branch, '' = every branch. S3 a terminal clock ahead > 1 day refused at open (61050); close before open 61056. S4 SET QUOTED_IDENTIFIER / ANSI_NULLS ON in the script. S6 a FAILED GL update never overwrites POSTED. S7 void DUPLICATE before the approver checks. S8 the COA check covers only the legs used.
    - R11: a closed GL month (lock through 10-31) makes PostShiftGL throw the trigger's 59900, which the close records as FAILED.
    - ui-form-reviewer:
      - X-reading needs a supervisor (it shows the expected cash, which would defeat the blind count).
      - SaveSale refuses a sale under another cashier's shift, and a discount needing approval (or missing from the local list) without an approver.
      - Orphan discounts no longer prompt.
      - The shift prompt waits until the terminal window is active (no stacked dialogs).
      - Ctrl+X / Ctrl+Z still cut / undo while typing in the scan box.
      - Scanning needs your own open shift.
      - The drawer event is logged before the drawer opens.
      - A cleared sale also counts its removed lines on the Z (`@ClearedLineCount / Amount`).
      - Closing the window with a sale on screen = cleared sale (approval); a Windows shutdown holds it.
      - The close warns about held sales.
      - A FAILED sale can't be voided.
      - F12's count / message is fixed.
    - **Rule (user, 2026-10-13): a supervisor MAY approve their own action** (some branches have only one person on duty). Not blocked; the approver is recorded.
    - Not changed, noted: PIN hashes on terminals are brute-forceable offline by someone with the local DB (inherent to offline approvals); CLEARED / DRAWER details (approver, reason) stay on the terminal, only counts reach the server.
  - **Phase 3 limits / open:** no cash pull-out (mid-shift pick-up) yet, so the count must include everything taken in; a terminal reinstalled while the server still has its shift open gets 61052 until that shift is closed (no admin force-close screen yet); the BIR accumulated grand total and the MIN / serial on the Z are phase 5; the close's post-check assumes cash only (phase 4 must extend it for card / charge); screens not yet clicked in the app.
  - **Accountant (2026-10-13):** cash short = an expense (60340); senior / PWD VAT exemption → 40103 with the discounts (as built).
- **Phase 4 BUILT on DEV 2026-10-13** (user: go; folded into scripts 58 / 59; DEV re-created with the reset script).
  - **User decisions (10-13):**
    - Cash short → new account 60340 CASH SHORTAGE - POS.
    - A charge over the credit limit needs a supervisor's PIN.
    - Refunds "same as paid".
  - **Payments CASH / CARD / CHARGE in any mix** (`PosPaymentForm`):
    - Change comes only out of cash (61019).
    - A card needs its reference (61036).
    - A charge needs the customer (61034 / 61035). The customer list is downloaded per branch (`sp_POSV2_GetCustomers`, 1,570 on DEV 001).
  - **A charge sale writes the AR invoice at once:** `TransactionChargeSales` (PaymentType CREDIT, InvoiceNo = ReferenceNo = the OR no., DueDate = date + Term) and a `ClientLedger` debit (TransCode POSV2-CHARGE). Client Payments collects it like any invoice.
    - The GL AR leg posts with the shift (POSV2-SHIFT CHARGE → DR 101030101). **Within an open shift, AR subledger > GL AR by the shift's charges** (timing, closes at the Z-reading).
    - Credit check on the terminal: downloaded balance + this terminal's unsent charges. Over the limit → supervisor (`CreditApprovedBy`). The server re-checks the live balance and flags NeedsReview when there's no approver.
  - **Void of a charge sale:** the invoice → CANCELLED (0) + a ClientLedger credit dated like the sale. Refused (61047) once anything was paid on it; the cashier does a return instead.
  - **Returns (Ctrl+T, `PosReturnForm`, `spu_POSV2_PostReturn`, event RETURN, slip series `<prefix>-R<seq>`):**
    - Any posted sale of the branch, part or all of a line, with a supervisor. The sale comes from the server when online (every terminal's returns + the invoice's live open balance), else from this terminal's own copy.
    - Amounts are the line's rounded share; returning all that's left takes the exact remainder.
    - Stock goes back to the sale's own lots, newest first, capped by earlier returns (`POSV2_ReturnLot`, ledger `POS RETURN <no> OR#<or>`). A qty that was sold short closes its shortage instead.
    - Refund split: account first (up to the invoice's open balance; any excess → CUSTCREDIT 20115 + NeedsReview), then card, then cash from the current drawer. The return slip prints, and the drawer opens only for cash.
    - Over-returns (stale terminal) are posted flagged, and the restock is capped.
  - **Shift GL legs added (mapping rows 9–15):** CARD DR 101030105; CHARGE DR 101030101; RETGROSS DR 401; RETDISC CR 40103; RETCOST DR 101040201 / CR 501; CUSTCREDIT CR 20115.
    - Expected cash = beginning + cash sales − cash refunds.
    - The close compares the terminal's returns too (@ReturnCount / @ReturnNet, 61057). The post-check covers both identities (61065).
  - **Tests:**
    - Server: C1–C7 + R1–R10 rolled back (split sale, invoice + ledger, credit flag / approval, charge void + refusal, returns with charge / card / cash refunds, over-return flag, short line unshorted, excess → 20115, duplicate, every refusal); all tickets DR = CR.
    - End-to-end with the real classes: customers downloaded; offline split sale 600 (cash 150, change 50 / card 200 / charge 300) → Z1; offline return in Z2 of 1 + 1 (350 = account 300 + card 50) → Z2; back online, 5 events in 0.8 s.
      - Invoice RETURNED; ledger +300 / −300.
      - Z1: 10101 100 / 101030101 300 / 101030105 200 / 401 600 / COGS 185.37. Z2: 401 350 / 101030101 −300 / 101030105 −50 / restock 132.44 = lot cost.
      - Another terminal's live view sees the right returnable qty.
    - DEV restored exactly (stock, no POS V2 / AR / ledger / ticket rows; customer balance 0); test DB, keys and exe removed. Built.
  - **Reviews (2026-10-13), fixed and retested** (C1–C7, R1–R10, V1, L1, K1, P1, P2 rolled back; end-to-end rerun; DEV restored again):
    - sp-reviewer B2 (confirmed live, DEV + STAGING): Client Payments holds the invoice reference in 10 characters (`splist_ARAccounts` OrderNo varchar(10); `ARPaymentDetails.PONumber` varchar(10) and its C# parameter). An OR no. there would break the AR list and silently cut the payment's match.
      - POS charge invoices now use `ReferenceNo` = 'P' + 9 digits (new SEQUENCE `seq_POSV2_ARRef`, kept on `POSV2_Sale.ARReferenceNo`); the OR no. stays in `InvoiceNo`. No shared proc / table changed.
      - P1 proves it: the list shows the invoice and `sp_AddPaymentClient` pays it in full (ledger 300 / −300, balance 0). A later void is refused (P2).
    - Both reviews' B1: a sale with a return can't be voided (server 61048, terminal too).
    - UI B2: the return screen adds this terminal's not-yet-uploaded returns to the server's view, and `SaveReturn` re-checks qty / amount under lock. A server-unreachable fallback and an unconfirmed account refund need a Yes.
    - UI B3 + sp S8: **rule (user, 2026-10-13): a credit limit of 0 = unlimited** (no approval, no flag). For a customer with a limit, a failed balance read or a customer list older than a day needs approval too. Charges posted after the last customer download count as owing. (L1 retested: a 0 limit posts clean; C5 over-limit still flagged.)
    - sp S1: a return's cash beyond what was paid in cash, and a line amount off its pro-rata share (±0.02), are flagged.
    - S3 / S4: restock order = highest Inventory SequenceNumber first, one row per lot. The piece that empties a lot takes exactly what's left of its sale cost (K1: three returns = sale cost 238.53).
    - S7: the credit check reads ClientAccounts without a lock (the same order as Client Payments).
    - S9: TransactionChargeSales updates must hit exactly one row (61047 / 61069).
    - TransactionChargeSales.BranchCode is `LEFT(@Branch, 3)`.
    - UI S1: cash follows what's left after card + charge until typed; a cash tender that is all change is dropped. Enter on a button doesn't pay; numeric masks; card ref max 100.
    - UI S2: return qty is a spin box capped at what's returnable; Return is blocked while an edit is invalid.
    - UI S3: lookups are sequenced and the screen is cleared first.
    - UI S4: the return series resumes after a reinstall (RegisterTerminal LastReturnSeq). UI S7: online is re-checked at each lookup.
    - Receipt lines are clipped to 40 columns.
    - The reset script refuses on a named instance or with POSV2 tickets present, and drops the sequence.
    - **Not changed, noted:**
      - a void of a charge sale already paid stays refused (61047). Offline + paid in between is rare; it needs a force close.
      - A ChargeExcess (customer credit to 20115) isn't in the AR credit pool (`sp_GetCustomerAvailableCredit`); NeedsReview is the trace. Exception Center check in phase 5.
      - GL date = the shift's opening day, while AR dates = the sale / return day (a shift across midnight or a month end splits them).
      - Block the month-end close while a POSV2 shift is OPEN / PENDING / FAILED (phase 5).
      - The restock goes back at the sale-time lot cost, while `spu_InvFIFO_Restore` may value the ledger at the lot's current cost.
  - **Not yet / open:** a void of a charge sale made offline and paid in between is refused (61047) → force close. Card settlement with the bank (101030105 → bank) is outside POS. A return can't be voided (a new sale re-sells). Reports / BIR / Exception Center / Process Trace = phase 5. Screens not yet clicked in the app.
- **Phase 5 BUILT on DEV 2026-10-13** (user: go).
  - **BIR registration on the terminal:** `POSV2_Terminal.BIRMachine` = its `POSInfoDetails.MachineUsed` on the branch (old-POS table: business name, address, TIN, MIN, serial no., accreditation, PTU no. and validity).
    - Set per machine in the registry (POSV2 `BIRMachine`). Sent at registration, which now also re-runs at every master refresh (idempotent; counters only move up).
    - Receipt / return slip / Z-reading print the BIR header (name, wrapped address, VAT REG TIN, MIN, SN) and footer (accreditation, date issued, PTU, validity).
    - A linked terminal prints "SALES INVOICE" / "SI No."; an unlinked one says so in the footer.
  - **Accumulated grand total** (`AccumulatedBefore / After` on the shift, terminal and server): + net sales of the shift; voids are out and returns don't lower it. It resumes after a reinstall (RegisterTerminal LastAccumulated, max rule). The Z prints the Z counter, reset counter 0, and accumulated before / after. **Accountant to confirm the basis (net sales).**
  - **BIR reports (script 60):** E-Sales, POS Sales Summary, 2550M add POS V2 from `fn_POSV2_ZReadings` (closed shifts = sales less returns, split by the original line's VAT). A terminal not linked to POSInfoDetails is listed with TIN / MIN blank, never left out. Old-POS rows unchanged (both old Z tables are empty on DEV).
  - **GL month close (script 60):** `spu_GLPeriod_Close` refuses (59908) while a POS V2 shift of the month (or earlier) is open or its GL isn't booked.
  - **Reports in the main app:** "POS V2 Reports" (Accounting Settings menu, admins + accounting; added in code, Main.Designer untouched): Z-readings, Sales journal, Returns, Needs attention. N2 / N3, footer sums, data-aware Excel export. Procs `sp_rpt_POSV2_Shifts / _SalesJournal / _Returns / _NeedsAttention`.
  - **Exception Center:** `tools/ExceptionCenter/POSV2_ExceptionCheck.sql`, P01–P15 (P14 / P15 added after the review):
    - GL: ticket balanced / booked once / AR leg = charges − charge refunds / GL not booked.
    - Cost: shift cost vs lots, return cost vs restocked lots.
    - Stock: void restock.
    - AR: POS invoice vs sale − returns; client-ledger rows vs balance; customer credit 20115.
    - Work lists: NeedsReview, open shortages, shifts open > 1 day, OR-series gaps.
    - Tested: clean data = 0; injected faults found (P01 −50.00, P05 +1.00).
  - **Credit limit rule (user, 10-13): 0 = unlimited** (terminal + server; L1 retested clean).
  - **Tests:** F1 (BIR register), F2 (two shifts + return: grand total 0 → 600 → 800; E-Sales / Summary / 2550M rows net of the return: VATable 223.22, VAT 26.78), F3 (59908) rolled back. End-to-end with the real classes: BIR header / footer on the receipt and Z; grand total terminal = server (500 → 600); E-Sales feed. DEV restored, test BIR row removed.
  - **Process Trace module: deferred** until POS V2 has real sales (the builder needs sample transactions; none exist anywhere yet).
  - **Phase 5 reviews (2026-10-13), fixed and re-tested:**
    - sp-reviewer B1: the older `BIR2550M` screen (two menu buttons) reads `spr_SalesReportSummary`, which had no POS V2 → patched too (F4: branch 001 gains exactly the Z feed, no other branch moves).
    - VAT split exact at the source: `spu_POSV2_PostSale` 61017 has no 0.01 tolerance any more and requires zero-rated = 0 (a line has no zero-rated flag; the terminal always sends 0). A return line can't carry VAT on a non-VAT line or more VAT than its amount (61072); a VAT share off by > 0.02 is a review flag, like the net. The close post-check 61065 now also checks VATable + VAT + exempt + zero-rated = net, for sales and returns.
    - Grand total: `CloseShift` resumes from the last shift that has one (`AccumulatedAfter IS NOT NULL`, also in Register), stores what the terminal printed (`TerminalAccumulatedAfter`, sent by the terminal from now on), and Needs attention lists "GRAND TOTAL DIFFERS".
    - The BIR machine is stored on the shift at close (`POSV2_Shift.BIRMachine`), so editing the mapping later doesn't move filed months. The POSInfoDetails row is picked by the latest PTU (two rows for one machine).
    - Month close: the guard reads the shifts `UPDLOCK, HOLDLOCK`; 59908 names `spu_POSV2_ForceCloseShift`; new 59909 (a terminal used in the month, not seen since it ended, may hold offline sales). Limit: a terminal offline the WHOLE month isn't known; its shift's GL then fails 59900 and shows in Needs attention.
    - Reports: date filters sargable, `OPTION (RECOMPILE)` for the optional branch, index `POSV2_Return(ReturnDateTime)` and `POSV2_Shift(BusinessDate)`. E-Sales OR range cut to its 20-char column.
    - Exception Center: P01 also finds POSTED-without-ticket; P03 one finding when the mapping row is missing; P07 compares the restored qty; P08 counts invoice rows (a duplicate shows); P07 / P10 / P11 / P13 look back `@SinceDays` (45) because they have no "done" marker; P10 now MEDIUM; new P14 (VAT split vs net) and P15 (grand total chain / printed vs server). EC3 finds both injected faults.
    - Recorded, not changed: a shift counts on its BusinessDate (cross-midnight sales count on the opening day in the Z / BIR / GL, while the sales journal lists each OR by its own date); voided ORs are in the OR range and the transaction count; a day with more returns than sales shows negative; P09 assumes every ledger row of a POS invoice carries the OR no. in InvoiceNo (check on the first real Client Payments of one); credit limit NULL is treated like 0 (unlimited), and the server's check doesn't see the terminal's unsent charges (only NeedsReview, never a refusal).
    - ui-form-reviewer: blank branch for a non-admin → message, no load; register at refresh can't break the sync loop; counters reset to the server's when the terminal ID changes; report columns built once, count columns N0; receipt: "registered" = TIN on file, MIN only if present, nothing internal on a customer slip (the terminal header shows the BIR link status instead), SI/OR wording.
  - Harness note: the phase 3 / 4 test scripts needed the phase-5 register result shape (scratchpad only).
  - Built 2026-10-13 into bin\Debug. Not yet clicked in the app: the reports screen and the BIR printouts.
  - Dependency Atlas rebuilt from DEV (`-RegistryKey AAITCRE\ConnSettingsServer -Catalog COREX001`) with every POS V2 object and republished (version 5).

### Phase 1 plan notes (2026-10-12)

- Plan: `docs/plans/2026-10-12_POS_V2_Hybrid_Plan.md`. Ask: rebuild `POS/PointOfSale.cs` as a new module (own folder, tables, procs, views). Online = real-time stock deduction and posting; offline = kept locally, uploaded and deducted automatically when back online.
- Found:
  - the old POS posts line by line (`sp_AddSalesInvoice` → BatchSalesDetails / Summary), local-first, uploaded at end of day by table copy;
  - stock is deducted later by an HO batch (`spu_ComputeSalesCosting`), and `isRealTimeDeduction` is unused;
  - numbering is MAX+1 and a text file;
  - production JFC has no POS rows (the POS serves another deployment);
  - this laptop's local POS DB is SQL Server 2014.
- Proposed: always local first, plus an outbox and a background sync worker (online = posted within seconds). The server proc is idempotent by sale GUID and deducts via the FIFO engine. Numbering is per terminal. New `POSV2_*` tables. Five phases.
- Waiting on the user: Q1 where it runs / local SQL version; Q2 GL per shift vs per sale; Q3 offline oversell; Q4 old reports; Q5 drop restaurant / hotel options.

## Feature 23 — PROFOOD GMBH loan payment (ON HOLD 2026-10-04, plan only, nothing built)

- **2026-10-12: new plan `docs/plans/2026-10-12_PROFOOD_Loan_FX_Plan.md`** (revised after the Peachtree screenshots): the loan is **EUR 800,000**, revalued every month end (07-31 @70.5095 = our 20203 opening 56,407,600). Peachtree booked revaluations as a "payment" of invoice LOAN051618 with the forex account 6041 as cash account. **Our GL lacks the 08-31 (+1,136,800 loss) and 09-30 (−1,371,760 gain) revaluations** (STAGING); interim = 2 Manual JVs. Proposal: a Loan Revaluation screen (not VoucheringManualFrm), payments mode later. A 09-25 Manual JV (ticket 15949) allocated 833,362.65 of loan forex to 12 branches: basis to ask. Waiting on the accountant (plan section 4).
  - **Answered 2026-10-13 (user):** only 60323 and 20203 (rate up = DR 60323 / CR 20203, down = DR 20203 / CR 60323); 888 only, no branch allocation; principal / interest / withholding set aside. Script 65 already posts exactly this, so no change was needed.

- **Ask:** pay the PROFOOD GMBH loan and interest the way AP is paid. Old system: DR "advance from other company" / CR forex gain/loss.
- **User answers:**
  - The loan is USD, but there is no rate math on our side. They agree the amount (the "negotiated payment") outside the system, pay it, and the balance goes down. No debit note to reference.
  - The loan is the 56.4M only.
- **Data (DEV):**
  - The loan exists only as the 07-31 opening ticket 1 on branch 888: `20203 ADVANCES FROM MOTHER COMPANY` CR 56,407,600.00. Nothing has posted to 20203 since.
  - It has no payable rows and no supplier-ledger rows. PROFOOD GMBH (000125) supplier balance 372.6M is trade only.
  - 60313 = interest expense, 60323 = realized FX.
- **Proposed (no new posting code):** load the 56.4M as payable rows and pay them through `VoucheringManualFrm` (Telegraphic).
  - Rows: `ExpenseSummary` + `ExpenseMaster`, `PayableAccountCode = '20203'`, tagged as loan, with a supplier-ledger balance-forward row. **No GL ticket**: ticket 1 already has it.
  - `sp_PostVoucherManual` already does what's needed:
    - DR the row's own account / CR bank, and lowers the row balance under UPDLOCK.
    - Variance goes to 60323 (paying less = gain), which is the old "DR advance / CR forex" entry.
    - Partial payment works with Variance 0.
  - The reversal goes through `SupplierVoucherReversalFrm`. Not yet verified that it puts the 20203 rows back.
  - Steps:
    1. Create a separate supplier "PROFOOD GMBH - LOAN".
    2. Load script on DEV.
    3. Rolled-back tests: full + gain, full + loss, partial, reversal. Also check that AP aging / AP-vs-20103 reports exclude the loan rows.
    4. Exception Center check: open loan rows = GL 20203.
    5. Only if new interest gets added later: a small "Loan Charge" entry (DR 60313 or bank / CR 20203 + payable row). `spu_PostExpenseV2` can't do it: its payable amount counts 20101/20102/20103 only, and it's shared by 4 forms.
- **Waiting on the accountant (user, 10-04):**
  1. The 56.4M split: principal vs interest, and how many rows.
  2. A separate loan supplier, or keep it under 000125?
  3. Will new interest or loan amounts be added to 20203 later? If not, step 5 is skipped.
  4. Withholding tax on interest paid to PROFOOD?

## Open decisions (ask the user)

1. **1-cent rounding in multi-branch payments.** In `sp_AddPaymentSupplierCompound_V2`'s BATCH branch, the last branch's gross = eGross − SUM(**unrounded**
   shares), so branch grosses can sum to eGross + 0.01. Fix: remainder from the running sum of rounded shares.
   - **2026-10-12, confirmed on STAGING and worse than 1 cent** (user's case: expense 17710 / CEB-PCF-080626, 199,999.00 paid by voucher 688 / ref 28500 as 199,999.06).
     Line 842's `SUM(BranchNetLiability/@eNetLiability * @eGross)` divides a SUM column, DECIMAL(38,2), so the ratio is cut to 6 decimals (6220/199999 → 0.031100).
     The other branches are therefore under-counted (12,559.9372 instead of 12,560), and the last branch (888) gets the rest: 187,439.06 instead of 187,439.00.
     Line 840 (variables) keeps 20 decimals, so the other branches are exact.
     The extra reaches the APPaymentDetails leg, the GL (DR 20103 / CR bank), SupplierLedger (invoice nets −0.06), the voucher / cheque amount (= sum of the legs) and the bank-recon OC. TransactionPaymentAP keeps the screen's 199,999.00.
     8 of the 9 multi-branch vouchers on STAGING are affected, +0.01 to +0.52, 1.38 in all: 684, 688, 803, 823, 837, 787, 867, and 913 (10-12).
     Corrected: those 5 invoices (refs 32956 / 34730 / 35103 / 32949 / 36453) were not edited after payment; their Balance was booked below the Amount at posting (net payable), and the payments matched the Balance.
   - **Fixed by script 61** (DEV + STAGING 2026-10-12; production by the user). The 1.38 already overpaid on the 8 STAGING vouchers is for the accountant (the cheques went out at those amounts).
   - **Found 2026-10-12, fixed by script 62 the same day: a telegraphic reversal restored the cash, not the settled amount.** STAGING PRIBLET (SI-202511470, 3,279,561.30): voucher 38580 settled it with 3,209,561.30 cash + 70,000 FX gain; its reversal put back only 3,209,561.30, so 38581 paid that and the invoice shows FULLYPAID while the supplier ledger still owes 70,000. (Same family as "PURCHASE reversal ... subtracts APAccounts columns posting never adds to".) The new voucher view shows it: 38581 Balance After 70,000 vs Balance Now 0.
2. **Reversal zeroes each line's accrual EWT/Discount/Offset** in `sp_CancelledChequesCS` (it subtracts the line's own value from itself). A reversed-and-repaid
   multi-branch invoice may withhold no EWT.
3. **Show overpayments and advances on supplier statements (`SupplierLedger`)?** Would need to be done for all modes together.
4. **Correct historical `Inventory.Cost`** that past whole-invoice costing overstated? It touches stock that may already be sold.
5. **`sp_EditSingleExpense` double-costs PO-linked expenses on edit.** Guard 56103 is commented out, and the old cost is never backed out.
   - 2026-09-29: reported by the user and reproduced (32473 / SI#00254, shipment 11012: supplier-only edit, 68.86 → 112.61). Fix = script 12.
     The repost passes `@isLinkedToPO=0` and the edit proc applies ONE net cost delta. Tested on DEV: supplier-only, amount change, unlink, move shipment.
   - Still open: which shipments were already inflated by past edits (no edit log, can't be told from data); pre-2026-09-24 expenses back out inventory legs only.
6. **"Unit cost 0" for PO 11005.** Waiting for the user to name the screen and column.
   - Found so far: every non-DELIVERED PO has `PODETAILS.Cost` and `POSUMMARY.TotalCost` = 0 (new flow). Inventory cost comes from linked expenses.
   - Item Costing Report and Recon both show the correct cost for 11005.
7. **Optional indexes:** `TicketMaster(ReferenceNumber, ReferenceKey)` and `TicketDetails(TicketNumber, ReferenceNumber)`.

## Pre-existing issues found (flagged, not fixed)

- `sp_ReversePaymentClient` mirrors every `TicketMaster`/`TicketDetails`/`ClientLedger` row `WHERE ReferenceNumber = @refno`. Sales tickets hold the PO number in that same column, and the two numbers come from different counters.
  - On COREX001, 34 payments share their reference with another ticket, and 31 of them are still POSTED. Reversing one would also mirror another customer's sales ticket and ledger row.
  - Fix, when the user approves: `Mnemonic LIKE 'OR-%'` on the tickets; `AccountKey = @custkey AND TransCode LIKE 'OR-%'` on the ledger.

- `sp_PostCompoundTicket`: amount type `MIRROR`, or any amount type missing from `@Amounts`, silently becomes GROSS. So `PV-AP-DISC` and `PV-AP-EWT-DISC` post the
  discount leg at the gross amount. No DR = CR check. No PV-AP tickets existed on DEV yet.
- `PV-AP` bank leg uses GROSS, not NET. It's unbalanced when there's a variance or return allowance without a discount.
- The FX loss mapping points at 60302, but COA 60302 is BAD DEBTS; 60323 is the FX account.
- PURCHASE reversal matches invoices on `SequenceNo` only. (Its subtracting of `APAccounts` columns that posting never adds to was fixed by script 62, 2026-10-12.)
- ~~The "already reversed" guard checks only `CheckVoucher`~~: fixed by script 62 (audit + Telegraphic / Cash + applock), 2026-10-12.
- Multi-branch BATCH: if `@eNetLiability = 0`, branch amounts become NULL.
- `sp_PostExpenseManualMultiBranch` calls `GetTicketNumber` once, before the branch loop, so every branch shares one ticket number.
  `sp_EditExpenseManualMultiBranch` gets a new number per branch. Not changed; confirm which one is intended.

## Gotchas learned (candidates for CLAUDE.md Known Bug Patterns)

- **`GridView.PopulateColumns()` creates NO columns while the grid isn't on a shown form** (constructor, a tab never opened), for a BindingList and a DataTable alike; `ForceInitialize()` doesn't help (tested 2026-10-13 against the v26.1 assemblies). A later `view.Columns["X"].Width = …` then throws NullReference. Found when POS V2 was first opened: `PosTerminalForm.cs:169` crashed. Fixed (C# only): the terminal and return grids add their columns explicitly (`Columns.AddVisible`); product search, list picker and supervisors format on `Shown`; POS V2 Reports flags a formatted view in `Tag` and formats a tab's grid when the tab opens. Build compiled 2026-10-13 (bin copy blocked: the app was running in the debugger).

- **A SearchLookUpEdit / LookUpEdit `ValueMember` must be a unique key, and the picked row must be read from `EditValue` (or `GetSelectedDataRow()`), never from `Properties.View.FocusedRowHandle`.** Found 2026-10-10 in `AccountingDevEx/ClientPaymentsDevExAcctg` (customer dropdown).
  - It had ValueMember = CustomerName, which 938 customers share (e.g. DAQUIZ, ARNOLD at branches 009 and 001), so picking the second one changed nothing.
  - `SearchLookUpClass.getSingleValue` reads the popup's focused row, which isn't the picked row on the first pick after load.
  - Fixed: ValueMember = CustomerKey, and the key comes from EditValue (C# only, built 14:21). `getSingleValue` is used elsewhere too, so other dropdowns may have the same first-pick bug.
- Multi-branch expenses are `PostingMode='MULTI-MANUAL'`. V2 sends everything that isn't SINGLE through its "BATCH" branch.
- V2's CATCH uses `ROLLBACK TRANSACTION PaySupplierV2`, a named rollback. Inside an outer test transaction this masks the real error with error 6401.
  To see the real error, test through a temporary copy with that line replaced, then drop the copy.
- `TransactionPaymentAP.ReferenceNumber` is numeric; `CashVoucher.VoucherID` is `decimal(7,0)`. Test IDs must be numeric and at most 7 digits.
- `APPaymentDetails.ReferenceNumber` is `char(5)`.
- In PowerShell, `SqlConnectionStringBuilder.InitialCatalog` doesn't work as a property. Use `$b["Initial Catalog"]`.

## How DB checks were done (per machine)

Read-only queries and DEV deploys ran through small PowerShell helpers kept in the session scratchpad, not in the repo.
They read the registry connection string: value `dbconn` under `HKCU\AAITCRE\ConnSettingsMain`.
They unprotect it with DPAPI (entropy `CORECS-ConnSettings-v1`, same as `Classes/RegistryProtection.cs`) and switch databases by replacing `Initial Catalog`.
**Default to `COREX001`, and check the instance as well as the catalog.**
- `ConnSettingsMain` on the dev laptop normally points to DEV, but the user switches it on purpose at times (e.g. to PRODUCTION, `PRODJFC_COREX` on 7701, on 2026-10-04). A catalog swap on a 7701 connection can never reach DEV.
- Print `Data Source` and `Initial Catalog` before any check or deploy.
- Reach DEV and the current STAGING through a default-instance connection (e.g. `ConnSettingsServer`). Reach the new STAGING through a connection to `,6601`.
- Don't hard-code `CORECSERP_002_DEV` in the helpers.
In PowerShell, pass the catalog as a `[string]`; a pipeline `PSObject` makes the assignment throw.
Every write test ran inside `BEGIN TRAN … ROLLBACK`, followed by a check that no test rows remained.
No credentials are stored in any file; they stay in the registry (DPAPI).
