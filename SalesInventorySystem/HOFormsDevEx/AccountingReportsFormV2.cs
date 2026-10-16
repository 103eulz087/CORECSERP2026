using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid.Views.Grid;
using DevExpress.XtraPrinting;
using DevExpress.XtraPrintingLinks;

namespace SalesInventorySystem.HOFormsDevEx
{
    // V2 of AccountingReportsForm -- same report catalog/generate/export logic
    // (kept in sync deliberately, not shared, per this codebase's "give each
    // new module its own dedicated objects" convention), with two changes:
    //   1. Layout: the parameter panel moves from a left sidebar (which ate a
    //      fixed ~280px regardless of report width) to a horizontal bar
    //      across the top, so the report grid gets the full control width.
    //   2. "Balance Sheet" now points at sp_rpt_BalanceSheetPerBranchInventorySingleGrid
    //      (a new, separate SP -- see SQL/2026-09-11_sp_rpt_BalanceSheetPerBranchInventorySingleGrid_NewReport.sql),
    //      which folds the section/grand-total rows that used to live in a
    //      separate SUMMARY grid into the SAME result set as the line items
    //      (RowType='DETAIL'/'SUBTOTAL'/'GRANDTOTAL'), so this report renders
    //      as ONE grid instead of a detail grid + summary grid pair.
    // The original AccountingReportsForm is untouched and still reachable
    // from its own nav entry -- this is an additional, parallel module.
    public partial class AccountingReportsFormV2 : DevExpress.XtraEditors.XtraForm
    {
        // ── How to slice each SP's result sets into (main grid, summary grid).
        //    Verified against the actual SP bodies (GLREPORTS_BODY.txt) -
        //    shapes genuinely differ per report, so this isn't guessable
        //    from parameters alone. ──
        private enum ResultShape
        {
            Standard2Set,        // Set1 = main, Set2 = summary (Trial Balance, Income Statement, Consolidated GL)
            SingleSet,           // Set1 = main only, no summary (GL Detail Transaction, General Ledger WithRunningBal, Balance Sheet -- single-grid)
            GLDetailLedgerLegacy,// Set1 = header text, Set2+Set3 merged = main (same columns), Set4 = summary
            BankReconShape       // Set1 = header text, Set2 = main (reconciling items), Set3 = summary
        }

        private enum ParamMode
        {
            BranchAccountDateRange,   // GL Detail Ledger, GL Detail Transaction
            BranchAsOfDate,           // Trial Balance, Balance Sheet
            BranchDateRange,          // Income Statement (single-branch mode), General Ledger WithRunningBal
            BranchAccountAsOfDate,    // Bank Reconciliation
            ConsolidatedGL            // Consolidated GL (TB or IS sub-mode)
        }

        private class ReportConfig
        {
            public string SpName;
            public ParamMode Mode;
            public ResultShape Shape;
            public string Description;
            public bool SupportsAllBranchPivot;   // Income Statement only, for now
            public bool SupportsAllAccounts;      // GL Detail Transaction, for now
            public string PivotSpName;             // set once sp_rpt_IncomeStatementAllBranchesPivot exists
            public bool AllowAllBranches;          // branch selector can be left blank -> passes NULL
        }

        // 2026-10-07: only reports that tie to the ledger are listed (checked on STAGING against
        // TicketDetails, every account): the ledger-based procs (2026-09-30 "Real-Time" set, now
        // shown under the plain names) plus the fixed General Ledger (2026-10-07b). The older
        // GLSummary-based entries are kept below, commented out: GLSummary is stale since the daily
        // GL posting was retired (2026-09-30), so they showed wrong balances (e.g. a bank account
        // stuck at its July opening). Their procs still exist.
        private readonly Dictionary<string, ReportConfig> _reportConfigs = new Dictionary<string, ReportConfig>
        {
            ["Trial Balance"] = new ReportConfig
            {
                SpName = "sp_rpt_TrialBalanceRealTime",
                Mode = ParamMode.BranchAsOfDate,
                Shape = ResultShape.Standard2Set,
                Description = "Every account's balance as of a date, straight from the posted tickets. Debit must equal Credit for all branches (a single branch may not balance: cross-branch entries post each side under a different branch). Check 'All Branches' for the company-wide snapshot.",
                AllowAllBranches = true
            },
            ["Balance Sheet"] = new ReportConfig
            {
                SpName = "sp_rpt_BalanceSheetRealTimeSingleGrid",
                Mode = ParamMode.BranchAsOfDate,
                Shape = ResultShape.SingleSet,
                Description = "Assets, Liabilities and Equity as of a date, straight from the posted tickets, in one grid with section subtotals and grand totals. Current Period Earnings = the net of all income and expense accounts. Check 'All Branches' for the company-wide balance sheet.",
                AllowAllBranches = true
            },
            ["Income Statement"] = new ReportConfig
            {
                SpName = "sp_rpt_IncomeStatementRealTimeSingleGrid",
                Mode = ParamMode.BranchDateRange,
                Shape = ResultShape.SingleSet,
                Description = "Revenue, Cost of Goods Sold and Operating Expenses for a date range, straight from the posted tickets, in one grid. Check 'All Branches' for the side-by-side branch pivot with Grand Total.",
                AllowAllBranches = true,
                SupportsAllBranchPivot = true,
                PivotSpName = "sp_rpt_IncomeStatementRealTimeAllBranchesPivot"
            },
            ["General Ledger (All Accounts)"] = new ReportConfig
            {
                SpName = "sp_rpt_GeneralLedger_WithRunningBal",
                Mode = ParamMode.BranchDateRange,
                Shape = ResultShape.SingleSet,
                Description = "All accounts, running balance, one flat report - Beginning/Transaction/Period/Ending rows per account. Every ticket line counted once (2026-10-07b). Check 'All Branches' for every branch combined.",
                AllowAllBranches = true
            },
            ["GL Detail Ledger"] = new ReportConfig
            {
                SpName = "sp_rpt_GLDetailLedgerRealTime",
                Mode = ParamMode.BranchAccountDateRange,
                Shape = ResultShape.GLDetailLedgerLegacy,
                Description = "Day-by-day activity of one account with opening and running balance, straight from the posted tickets. Requires a specific account. Check 'All Branches' for a combined ledger across every branch.",
                AllowAllBranches = true
            },
            ["GL Detail Transaction"] = new ReportConfig
            {
                SpName = "sp_rpt_GLDetailTransactionRealTime",
                Mode = ParamMode.BranchAccountDateRange,
                Shape = ResultShape.SingleSet,
                Description = "One row per posting leg with opening and ending balance, straight from the posted tickets (the opening ties to the Trial Balance). Check 'All Accounts' and/or 'All Branches' to widen the scope.",
                AllowAllBranches = true,
                SupportsAllAccounts = true
            },
            ["Bank Reconciliation"] = new ReportConfig
            {
                SpName = "sp_rpt_BankReconciliationRealTime",
                // Date range: the reconciliation proc takes @DateFrom/@DateTo.
                Mode = ParamMode.BranchAccountDateRange,
                Shape = ResultShape.BankReconShape,
                Description = "The Bank Recon screen's reconciliation for one bank account as of the period end (Date To = month end): GL ending balance across all branches, bank statement balance, open deposits in transit / outstanding checks / bank items, adjusted bank vs adjusted book (2026-10-07c). Pick branch 888.",
                AllowAllBranches = true
            },
            ["Consolidated GL"] = new ReportConfig
            {
                SpName = "sp_rpt_ConsolidatedGLRealTime",
                Mode = ParamMode.ConsolidatedGL,
                Shape = ResultShape.Standard2Set,
                Description = "All branches combined, straight from the posted tickets. Trial Balance mode uses an as-of date; Income Statement mode uses a date range."
            }

            // ── Retired 2026-10-07 (GLSummary-based, stale; procs kept) ──────────────────────
            //["Trial Balance (old, GLSummary)"]         = sp_rpt_TrialBalanceWithDate,                  Standard2Set, BranchAsOfDate
            //["Balance Sheet V2) (old, GLSummary)"]     = sp_rpt_BalanceSheetLiveWithDateSingleGrid,    SingleSet, BranchAsOfDate
            //["Income Statement (v2) (old, GLSummary)"] = sp_rpt_IncomeStatementLiveWithDateSingleGrid, SingleSet, BranchDateRange,
            //                                             pivot sp_rpt_IncomeStatementLiveAllBranchesPivot
            //["GL Detail Ledger (old, GLSummary)"]      = sp_rpt_GLDetailLedgerWithDate,                GLDetailLedgerLegacy, BranchAccountDateRange
            //["GL Detail Transaction (old)"]            = sp_rpt_GLDetailTransactionReport,             SingleSet, BranchAccountDateRange, all accounts
            //["Bank Reconciliation (old, GLSummary)"]   = sp_rpt_BankReconciliationWithDate,            BankReconShape, BranchAccountAsOfDate
            //["Consolidated GL (old, GLSummary)"]       = sp_rpt_ConsolidatedGLWithDate,                Standard2Set, ConsolidatedGL
            // Older still (already retired before 2026-10-07): "Income Statement" =
            // sp_rpt_IncomeStatementWithDateSingleGrid (+ pivot sp_rpt_IncomeStatementAllBranchesPivot_TEST),
            // "Balance Sheet" = sp_rpt_BalanceSheetPerBranchInventorySingleGrid.
        };

        // Report procs that take @IncludeZeroActivity (drives the checkbox and the parameter).
        private static readonly HashSet<string> _takesIncludeZero = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "sp_rpt_GLDetailTransactionReport",
            "sp_rpt_BalanceSheetLiveWithDate",
            "sp_rpt_BalanceSheetLiveWithDateSingleGrid",
            "sp_rpt_IncomeStatementLiveWithDate",
            "sp_rpt_IncomeStatementLiveWithDateSingleGrid",
            "sp_rpt_GLDetailTransactionRealTime",
            "sp_rpt_BalanceSheetRealTimeSingleGrid",
            "sp_rpt_IncomeStatementRealTimeSingleGrid"
        };

        // Accounts are optional only where the report offers 'All Accounts'.
        private static bool RequiresAccount(ReportConfig cfg) =>
            (cfg.Mode == ParamMode.BranchAccountDateRange || cfg.Mode == ParamMode.BranchAccountAsOfDate) && !cfg.SupportsAllAccounts;

        private ReportConfig CurrentConfig =>
            cboReportType.SelectedItem != null && _reportConfigs.ContainsKey(cboReportType.SelectedItem.ToString())
                ? _reportConfigs[cboReportType.SelectedItem.ToString()]
                : null;

        public AccountingReportsFormV2()
        {
            InitializeComponent();
        }

        // 2026-10-14: one-report mode. The Accounting Board hosts this form with only GL Detail Transaction
        // (staff trace what they just posted without leaving the board). The report list holds that one
        // report and can't be changed; everything else (parameters, Generate, ticket drill-down, exports)
        // is the same code as the full Accounting Reports screen.
        public const string GLDetailTransactionReport = "GL Detail Transaction";
        private readonly string _onlyReport;

        public AccountingReportsFormV2(string onlyReport) : this()
        {
            _onlyReport = onlyReport;
        }
        private bool _dataLoaded = false;
        private ContextMenuStrip _reportContextMenu;
        // True while gridControlReport is showing an All-Branches pivot result --
        // Export uses it to pick the data-aware XLSX path (frozen columns).
        private bool _isPivotResultShown = false;
        public void LoadData()
        {
            if (_dataLoaded)
                return;

            Database.DisplayDevLookupEditItems(
                "SELECT BranchCode, BranchCode + '-' + BranchName AS DisplayText FROM Branches",
                "DisplayText", "BranchCode", cboBranchCode);
            Database.displaySearchlookupEdit(
                "SELECT AccountCode, Description FROM ChartOfAccounts WHERE AccountType='D'",
                txtAccountCode, "AccountCode", "AccountCode");

            dteAsOfDate.EditValue = DateTime.Today;
            dteDateFrom.EditValue = new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1);
            dteDateTo.EditValue = DateTime.Today;

            cboReportType.Properties.Items.Clear();
            foreach (var key in _reportConfigs.Keys)
                if (string.IsNullOrEmpty(_onlyReport) || key == _onlyReport)
                    cboReportType.Properties.Items.Add(key);
            cboReportType.SelectedIndex = 0;
            if (!string.IsNullOrEmpty(_onlyReport))
                cboReportType.Properties.ReadOnly = true;   // one-report mode: nothing else to pick
            ApplyParamModeForSelection();
            SetupReportContextMenu();

            // No report has been generated yet, so there's nothing for the summary panel to
            // show -- same reasoning as the Visible toggle in BindResults.
            pnlSummaryContainer.Visible = false;

            _dataLoaded = true;
        }
        private void SetupReportContextMenu()
        {
            _reportContextMenu = new ContextMenuStrip();
            _reportContextMenu.Items.Add("View Related Entries (Same Ticket)", null, ViewRelatedEntries_Click);

            gridControlReport.MouseUp += GridControlReport_MouseUp;
        }
        private void GridControlReport_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Right) return;
            if (gridControlReport.DataSource == null) return;

            var hitInfo = gridViewReport.CalcHitInfo(e.Location);
            if (hitInfo.InRow || hitInfo.InRowCell)
            {
                gridViewReport.FocusedRowHandle = hitInfo.RowHandle;
                _reportContextMenu.Show(gridControlReport, e.Location);
            }
        }
        private void ViewRelatedEntries_Click(object sender, EventArgs e)
        {
            if (gridViewReport.FocusedRowHandle < 0) return;

            if (gridViewReport.Columns["TicketNumber"] == null)
            {
                var colNames = new List<string>();
                foreach (DevExpress.XtraGrid.Columns.GridColumn c in gridViewReport.Columns)
                    colNames.Add(c.FieldName);

                XtraMessageBox.Show(
                    "This report's grid has no 'TicketNumber' column.\n\nActual columns available:\n" + string.Join(", ", colNames),
                    "Not Available", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            string ticketNumber = gridViewReport.GetFocusedRowCellValue("TicketNumber")?.ToString();
            if (string.IsNullOrWhiteSpace(ticketNumber))
            {
                XtraMessageBox.Show("This row's Ticket Number is blank.", "Not Available",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            DataTable header, lines;
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_GetTicketDetailsByTicketNumber", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@TicketNumber", SqlDbType.VarChar, 20).Value = ticketNumber;

                    con.Open();
                    using (var da = new SqlDataAdapter(cmd))
                    {
                        var ds = new DataSet();
                        da.Fill(ds);
                        header = ds.Tables.Count > 0 ? ds.Tables[0] : new DataTable();
                        lines = ds.Tables.Count > 1 ? ds.Tables[1] : new DataTable();
                    }
                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load related entries: {ex.Message}", "Error",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            ShowTicketDetailsPopup(ticketNumber, header, lines);
        }
        private void ShowTicketDetailsPopup(string ticketNumber, DataTable header, DataTable lines)
        {
            using (var popup = new XtraForm())
            {
                popup.Text = $"Related Entries — Ticket {ticketNumber}";
                popup.Size = new Size(760, 480);
                popup.StartPosition = FormStartPosition.CenterParent;
                popup.MinimizeBox = false;
                popup.MaximizeBox = true;

                var lblHeader = new LabelControl
                {
                    Dock = DockStyle.Top,
                    AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None,
                    Height = 60,
                    Padding = new Padding(10)
                };
                if (header.Rows.Count > 0)
                {
                    var h = header.Rows[0];
                    lblHeader.Text =
                        $"Reference No.: {h["ReferenceNumber"]}   |   Date: {Convert.ToDateTime(h["TicketDate"]):yyyy-MM-dd}   |   Branch: {h["BranchCode"]}   |   Origin/Mnemonic: {h["Origin"]}/{h["Mnemonic"]}\n" +
                        $"Remarks: {h["Remarks"]}";
                }
                else
                {
                    lblHeader.Text = "(Ticket header not found — showing legs only.)";
                }

                var gridControl = new DevExpress.XtraGrid.GridControl { Dock = DockStyle.Fill };
                var gridView = new GridView(gridControl);
                gridControl.MainView = gridView;
                gridControl.ViewCollection.Add(gridView);
                gridView.OptionsBehavior.Editable = false;
                gridView.OptionsView.ShowGroupPanel = false;
                gridView.OptionsView.ShowFooter = true;

                gridControl.DataSource = lines;

                // 2026-10-14 (user): Debit / Credit showed unformatted. The grid creates no columns while the popup
                // isn't shown yet (PopulateColumns / FormatGridColumns found nothing to format here), so the columns
                // are built and formatted once the popup is on screen: N2, right-aligned, footer totals.
                popup.Shown += (s, e) =>
                {
                    gridView.PopulateColumns();
                    FormatGridColumns(gridView);
                    foreach (string name in new[] { "Debit", "Credit" })
                    {
                        var col = gridView.Columns[name];
                        if (col == null) continue;
                        col.Summary.Clear();
                        col.Summary.Add(DevExpress.Data.SummaryItemType.Sum, name, "{0:N2}");
                    }
                    gridView.BestFitColumns();
                };

                var btnClose = new SimpleButton
                {
                    Text = "Close",
                    Dock = DockStyle.Bottom,
                    Height = 36
                };
                btnClose.Click += (s, e) => popup.Close();

                popup.Controls.Add(gridControl);
                popup.Controls.Add(lblHeader);
                popup.Controls.Add(btnClose);

                popup.ShowDialog(this);
            }
        }
        private void AccountingReportsFormV2_Load(object sender, EventArgs e)
        {
            LoadData();
        }

        private void cboReportType_SelectedIndexChanged(object sender, EventArgs e)
        {
            ApplyParamModeForSelection();
        }

        // ── Show/hide the right parameter controls for whichever report is selected ──
        private void ApplyParamModeForSelection()
        {
            var cfg = CurrentConfig;
            if (cfg == null) return;

            lblReportTitle.Text = cboReportType.SelectedItem.ToString();
            lblReportSubtitle.Text = $"Branch: {cboBranchCode.Text} · Select parameters and click Generate";
            //lblDescription.Text = cfg.Description;
            lblSpName.Text = "SP: " + cfg.SpName;

            bool showAccount = cfg.Mode == ParamMode.BranchAccountDateRange || cfg.Mode == ParamMode.BranchAccountAsOfDate;
            bool showAsOf = cfg.Mode == ParamMode.BranchAsOfDate || cfg.Mode == ParamMode.BranchAccountAsOfDate;
            bool showDateRange = cfg.Mode == ParamMode.BranchAccountDateRange || cfg.Mode == ParamMode.BranchDateRange;
            bool showAllBranch = cfg.SupportsAllBranchPivot || cfg.AllowAllBranches;
            bool showAllAccounts = cfg.SupportsAllAccounts;
            bool showZeroChk = _takesIncludeZero.Contains(cfg.SpName);
            bool showConsolidated = cfg.Mode == ParamMode.ConsolidatedGL;
            bool showBranch = !showConsolidated; // consolidated is always all-branch

            lblBranchCode.Visible = showBranch;
            cboBranchCode.Visible = showBranch;

            lblAccountCode.Visible = showAccount;
            txtAccountCode.Visible = showAccount;

            // 2026-10-14: from local flags, not by reading lblAsOfDate.Visible / lblDateFrom.Visible back. The
            // Visible getter is false while the form isn't shown yet (the Accounting Board loads this screen
            // before showing it), which hid the date boxes there.
            bool asOfVisible = showAsOf || (showConsolidated && rgConsolidatedMode.EditValue?.ToString() == "TB");
            lblAsOfDate.Visible = asOfVisible;
            dteAsOfDate.Visible = asOfVisible;

            bool dateRangeVisible = showDateRange || (showConsolidated && rgConsolidatedMode.EditValue?.ToString() == "IS");
            lblDateFrom.Visible = dateRangeVisible;
            dteDateFrom.Visible = dateRangeVisible;
            lblDateTo.Visible = dateRangeVisible;
            dteDateTo.Visible = dateRangeVisible;

            chkAllBranches.Visible = showAllBranch;
            if (!showAllBranch) chkAllBranches.Checked = false;
            if (showAllBranch)
            {
                string caption = cfg.SupportsAllBranchPivot
                    ? "All Branches (Pivot)"
                    : "All Branches (Consolidated)";
                chkAllBranches.Text = caption;
                chkAllBranches.Properties.Caption = caption;
            }

            chkAllAccounts.Visible = showAllAccounts;
            if (!showAllAccounts) chkAllAccounts.Checked = false;

            chkIncludeZeroActivity.Visible = showZeroChk;

            rgConsolidatedMode.Visible = showConsolidated;
            if (showConsolidated && rgConsolidatedMode.EditValue == null)
                rgConsolidatedMode.EditValue = "TB";

            if (showAllBranch && chkAllBranches.Checked)
            {
                lblBranchCode.Visible = false;
                cboBranchCode.Visible = false;
            }
        }

        private void chkAllBranches_CheckedChanged(object sender, EventArgs e)
        {
            bool allBranches = chkAllBranches.Checked;
            lblBranchCode.Visible = !allBranches;
            cboBranchCode.Visible = !allBranches;

            var cfg = CurrentConfig;
            bool isPivot = cfg != null && cfg.SupportsAllBranchPivot;

            lblReportSubtitle.Text = allBranches
                ? (isPivot ? "All Branches (pivot) · Select date range and click Generate"
                           : "All Branches (Consolidated) · Select parameters and click Generate")
                : $"Branch: {cboBranchCode.Text} · Select parameters and click Generate";

            // Pivot SPs only ever receive @DateFrom/@DateTo (see RunPivotReport) -- "Include Zero
            // Activity" has no effect once All Branches routes to the pivot path, so hide it
            // rather than leave a control checked/visible that's silently ignored.
            if (isPivot && allBranches)
                chkIncludeZeroActivity.Visible = false;
            else if (cfg != null)
                ApplyParamModeForSelection();
        }

        private void chkAllAccounts_CheckedChanged(object sender, EventArgs e)
        {
            bool allAccounts = chkAllAccounts.Checked;
            txtAccountCode.Enabled = !allAccounts;
            if (allAccounts) txtAccountCode.EditValue = null;
        }

        private void rgConsolidatedMode_SelectedIndexChanged(object sender, EventArgs e)
        {
            ApplyParamModeForSelection();
        }

        // ── Generate ──
        private void btnGenerate_Click(object sender, EventArgs e)
        {
            var cfg = CurrentConfig;
            if (cfg == null) return;

            if (cfg.SupportsAllBranchPivot && chkAllBranches.Checked)
            {
                if (string.IsNullOrWhiteSpace(cfg.PivotSpName))
                {
                    XtraMessageBox.Show(
                        "The All-Branches pivot report hasn't been built yet for this report type.",
                        "Not Available", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
                RunPivotReport(cfg);
                return;
            }

            RunSingleBranchReport(cfg);
        }

        private void RunSingleBranchReport(ReportConfig cfg)
        {
            if (cboBranchCode.Visible && cboBranchCode.EditValue == null)
            {
                XtraMessageBox.Show("Select a Branch Code.", "Missing Parameter", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            bool noAccountPicked = string.IsNullOrWhiteSpace(txtAccountCode.EditValue?.ToString());
            if (RequiresAccount(cfg) && noAccountPicked)
            {
                XtraMessageBox.Show("Select an Account Code.", "Missing Parameter", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            try
            {
                lblStatus.Text = "Generating...";
                Cursor.Current = Cursors.WaitCursor;

                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand(cfg.SpName, con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 120 })
                {
                    switch (cfg.Mode)
                    {
                        case ParamMode.BranchAccountDateRange:
                            cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 5).Value =
                              (cfg.AllowAllBranches && chkAllBranches.Checked) ? (object)DBNull.Value : cboBranchCode.EditValue?.ToString();
                            cmd.Parameters.Add("@AccountCode", SqlDbType.VarChar, 20).Value =
                                (cfg.SupportsAllAccounts && chkAllAccounts.Checked) ? (object)DBNull.Value
                                : string.IsNullOrWhiteSpace(txtAccountCode.EditValue?.ToString()) ? (object)DBNull.Value : txtAccountCode.EditValue.ToString();
                            cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value = dteDateFrom.DateTime;
                            cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value = dteDateTo.DateTime;
                            if (_takesIncludeZero.Contains(cfg.SpName))
                                cmd.Parameters.Add("@IncludeZeroActivity", SqlDbType.Bit).Value = chkIncludeZeroActivity.Checked;
                            break;

                        case ParamMode.BranchAsOfDate:
                            cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 5).Value =
                                (cfg.AllowAllBranches && chkAllBranches.Checked) ? (object)DBNull.Value : cboBranchCode.EditValue?.ToString();
                            cmd.Parameters.Add("@AsOfDate", SqlDbType.Date).Value = dteAsOfDate.DateTime;
                            if (_takesIncludeZero.Contains(cfg.SpName))
                                cmd.Parameters.Add("@IncludeZeroActivity", SqlDbType.Bit).Value = chkIncludeZeroActivity.Checked;
                            break;

                        case ParamMode.BranchDateRange:
                            cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 5).Value =
                                (cfg.AllowAllBranches && chkAllBranches.Checked) ? (object)DBNull.Value : cboBranchCode.EditValue?.ToString();
                            cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value = dteDateFrom.DateTime;
                            cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value = dteDateTo.DateTime;
                            if (cfg.SpName == "sp_rpt_GeneralLedger_WithRunningBal")
                            {
                                cmd.Parameters.Add("@AccountType", SqlDbType.VarChar, 10).Value = DBNull.Value;
                                cmd.Parameters.Add("@SkipZero", SqlDbType.Bit).Value = !chkIncludeZeroActivity.Checked;
                            }
                            if (_takesIncludeZero.Contains(cfg.SpName))
                                cmd.Parameters.Add("@IncludeZeroActivity", SqlDbType.Bit).Value = chkIncludeZeroActivity.Checked;
                            break;

                        case ParamMode.BranchAccountAsOfDate:
                            cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 5).Value =
                                (cfg.AllowAllBranches && chkAllBranches.Checked) ? (object)DBNull.Value : cboBranchCode.EditValue?.ToString();
                            cmd.Parameters.Add("@AccountCode", SqlDbType.VarChar, 20).Value = txtAccountCode.EditValue?.ToString();
                            cmd.Parameters.Add("@AsOfDate", SqlDbType.Date).Value = dteAsOfDate.DateTime;
                            break;

                        case ParamMode.ConsolidatedGL:
                            string mode = rgConsolidatedMode.EditValue?.ToString() ?? "TB";
                            cmd.Parameters.Add("@AsOfDate", SqlDbType.Date).Value =
                                mode == "TB" ? (object)dteAsOfDate.DateTime : DBNull.Value;
                            cmd.Parameters.Add("@PeriodFrom", SqlDbType.Date).Value =
                                mode == "IS" ? (object)dteDateFrom.DateTime : DBNull.Value;
                            cmd.Parameters.Add("@PeriodTo", SqlDbType.Date).Value =
                                mode == "IS" ? (object)dteDateTo.DateTime : DBNull.Value;
                            cmd.Parameters.Add("@ReportType", SqlDbType.VarChar, 5).Value = mode;
                            break;
                    }

                    var ds = new DataSet();
                    new SqlDataAdapter(cmd).Fill(ds);

                    BindResults(ds, cfg);
                }

                lblReportSubtitle.Text = $"Branch: {(cboBranchCode.Visible ? cboBranchCode.Text : "ALL")} · Generated {DateTime.Now:g}";
                lblStatus.Text = "Ready";
            }
            catch (SqlException ex)
            {
                lblStatus.Text = "Error";
                XtraMessageBox.Show($"Database error ({ex.Number}): {ex.Message}", "Report Failed",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                Cursor.Current = Cursors.Default;
            }
        }

        // ── All-Branches pivot (Income Statement, for now) ──
        private void RunPivotReport(ReportConfig cfg)
        {
            try
            {
                lblStatus.Text = "Generating pivot...";
                Cursor.Current = Cursors.WaitCursor;

                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand(cfg.PivotSpName, con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 180 })
                {
                    cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value = dteDateFrom.DateTime;
                    cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value = dteDateTo.DateTime;

                    var ds = new DataSet();
                    new SqlDataAdapter(cmd).Fill(ds);

                    BindResults(ds, cfg, isPivotResult: true);
                }

                lblReportSubtitle.Text = $"All Branches (pivot) · Generated {DateTime.Now:g}";
                lblStatus.Text = "Ready";
            }
            catch (SqlException ex)
            {
                lblStatus.Text = "Error";
                XtraMessageBox.Show($"Database error ({ex.Number}): {ex.Message}", "Report Failed",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                Cursor.Current = Cursors.Default;
            }
        }

        // ── Binds each SP's result sets according to its verified shape.
        //    Not all reports return "Set1=main, Set2=summary" - see the
        //    ResultShape enum and each ReportConfig's Shape value. ──
        private void BindResults(DataSet ds, ReportConfig cfg, bool isPivotResult = false)
        {
            gridViewReport.Columns.Clear();
            gridViewSummary.Columns.Clear();

            switch (cfg.Shape)
            {
                case ResultShape.SingleSet:
                    gridControlReport.DataSource = ds.Tables.Count > 0 ? ds.Tables[0] : null;
                    gridControlSummary.DataSource = null;
                    break;

                case ResultShape.GLDetailLedgerLegacy:
                    if (ds.Tables.Count >= 1 && ds.Tables[0].Rows.Count > 0)
                    {
                        var hdr = ds.Tables[0].Rows[0];
                        lblReportSubtitle.Text =
                            $"{hdr["AccountCode"]} - {hdr["AccountDescription"]} · " +
                            $"Branch: {cboBranchCode.Text} · Generated {DateTime.Now:g}";
                    }

                    DataTable mergedLedger = null;
                    if (ds.Tables.Count >= 2) mergedLedger = ds.Tables[1].Clone();
                    if (ds.Tables.Count >= 2) foreach (DataRow r in ds.Tables[1].Rows) mergedLedger.ImportRow(r);
                    if (ds.Tables.Count >= 3) foreach (DataRow r in ds.Tables[2].Rows) mergedLedger.ImportRow(r);

                    gridControlReport.DataSource = mergedLedger;
                    gridControlSummary.DataSource = ds.Tables.Count >= 4 ? ds.Tables[3] : null;
                    break;

                case ResultShape.BankReconShape:
                    if (ds.Tables.Count >= 1 && ds.Tables[0].Rows.Count > 0)
                    {
                        var hdr = ds.Tables[0].Rows[0];
                        lblReportSubtitle.Text =
                            $"{hdr["AccountCode"]} - {hdr["AccountDescription"]} · " +
                            $"Branch: {cboBranchCode.Text} · Generated {DateTime.Now:g}";
                    }
                    gridControlReport.DataSource = ds.Tables.Count >= 2 ? ds.Tables[1] : null;
                    gridControlSummary.DataSource = ds.Tables.Count >= 3 ? ds.Tables[2] : null;
                    break;

                case ResultShape.Standard2Set:
                default:
                    gridControlReport.DataSource = ds.Tables.Count > 0 ? ds.Tables[0] : null;
                    gridControlSummary.DataSource = ds.Tables.Count > 1 ? ds.Tables[1] : null;
                    break;
            }

            // pnlSummaryContainer is a fixed Dock=Bottom/Height=220 panel -- it stays visible
            // and keeps reserving that space even with gridControlSummary.DataSource == null
            // unless explicitly hidden. SingleSet reports (Balance Sheet included -- the whole
            // point of its new SP is ONE grid, no separate summary) never populate it, so an
            // empty "SUMMARY" panel would sit there for no reason, eating into the report
            // grid's height. Hide it whenever there's nothing to show, let pnlReportGrid's
            // Dock=Fill reclaim the space; show it again for shapes that do have a summary.
            pnlSummaryContainer.Visible = gridControlSummary.DataSource != null;

            // A pivot result's per-branch columns are named after actual branches, so
            // FormatGridColumns' keyword heuristic below can never match them by name --
            // treat every column not explicitly a known text/id column as numeric instead.
            FormatGridColumns(gridViewReport, treatUnknownColumnsAsMoney: isPivotResult);
            FormatGridColumns(gridViewSummary);

            if (gridViewReport.Columns["TicketNumber"] != null)
                gridViewReport.Columns["TicketNumber"].Visible = false;

            // BSSection/ISSection/ExpenseSubSection/RowType are used purely to drive row
            // ordering/styling for the single-grid Balance Sheet and Income Statement --
            // redundant to show as their own columns once every row is already grouped/bolded
            // by section on screen.
            if (gridViewReport.Columns["BSSection"] != null)
                gridViewReport.Columns["BSSection"].Visible = false;
            if (gridViewReport.Columns["ISSection"] != null)
                gridViewReport.Columns["ISSection"].Visible = false;
            if (gridViewReport.Columns["ExpenseSubSection"] != null)
                gridViewReport.Columns["ExpenseSubSection"].Visible = false;
            if (gridViewReport.Columns["RowType"] != null)
                gridViewReport.Columns["RowType"].Visible = false;
            // Internal sign-flip helper for the Income Statement single-grid SPs' COGS section
            // subtotal (see their header comments) -- not meant for display, and its name would
            // otherwise incidentally match FormatGridColumns' "cogs" substring check and render
            // as "0.00"/"1.00" instead of being hidden.
            if (gridViewReport.Columns["IsContraCOGS"] != null)
                gridViewReport.Columns["IsContraCOGS"].Visible = false;

            gridViewReport.OptionsView.ColumnAutoWidth = false;
            gridViewSummary.OptionsView.ColumnAutoWidth = false;

            // Pivot: keep AccountCode/AccountDescription pinned while scrolling across
            // the branch columns (also exported as frozen columns -- see ExportPivotToXlsx).
            // Columns are rebuilt on every Generate, so non-pivot reports start unpinned.
            _isPivotResultShown = isPivotResult;
            if (isPivotResult)
            {
                foreach (string fixedCol in new[] { "AccountCode", "AccountDescription" })
                    if (gridViewReport.Columns[fixedCol] != null)
                        gridViewReport.Columns[fixedCol].Fixed = DevExpress.XtraGrid.Columns.FixedStyle.Left;
            }

            gridViewReport.BestFitColumns();
            gridViewSummary.BestFitColumns();

            // 2026-10-09 (user): the transaction description (General Ledger, GL Detail Ledger, GL Detail
            // Transaction) best-fits to its longest line and pushed the amounts off the page. It opens at
            // most TransDescriptionWidth wide; the user can still drag it wider, and a cut-off cell shows
            // its full text as a hint.
            foreach (string descCol in new[] { "TransDescription", "Trans Description", "Particulars" })
            {
                var col = gridViewReport.Columns[descCol];
                if (col == null) continue;
                col.OptionsColumn.AllowSize = true;
                if (col.Width > TransDescriptionWidth) col.Width = TransDescriptionWidth;
            }
        }

        private const int TransDescriptionWidth = 260;

        // ═══════════════════════════════════════════════════════════════
        // COSMETIC FORMATTING — applied to every report uniformly, since
        // column names vary per SP but follow consistent naming patterns
        // (Debit/Credit/Balance/Amount/Total/Date etc.) across all of them.
        // ═══════════════════════════════════════════════════════════════

        private static readonly Color G_DEBIT = Color.FromArgb(0, 72, 118);  // blue
        private static readonly Color G_CREDIT = Color.FromArgb(255, 132, 0);  // amber/orange
        private static readonly Color G_BALANCE = Color.FromArgb(230, 230, 235);  // light text
        private static readonly Color G_NEGATIVE = Color.FromArgb(240, 120, 130);  // red
        private static readonly Color G_POSITIVE = Color.FromArgb(150, 215, 160);  // green
        private static readonly Color G_GOLD = Color.FromArgb(201, 162, 39);
        private static readonly Color G_MUTED = Color.FromArgb(140, 148, 165);
        private static readonly Color G_ROW_MARK_BG = Color.FromArgb(56, 64, 92);
        private static readonly Color G_ROW_MARK_FG = Color.FromArgb(255, 255, 255);
        private static readonly Color G_ROW_REV_BG = Color.FromArgb(110, 55, 40);
        private static readonly Color G_ROW_REV_FG = Color.FromArgb(255, 195, 150);
        // GRANDTOTAL rows (single-grid Balance Sheet) get the brand gold accent
        // instead of the plain structural-row color, so "TOTAL ASSETS"/"TOTAL
        // LIABILITIES & EQUITY"/"DIFFERENCE" stand out even against SUBTOTAL rows.
        private static readonly Color G_ROW_GRANDTOTAL_BG = Color.FromArgb(74, 61, 15);
        private static readonly Color G_ROW_GRANDTOTAL_FG = Color.FromArgb(255, 221, 130);

        // Columns that are never money values even in a pivot grid, where every OTHER column
        // (AccountCode/AccountDescription aside) is an arbitrary branch name and therefore
        // can't be recognized by the keyword heuristic below.
        private static readonly HashSet<string> G_PIVOT_NON_MONEY_COLUMNS =
            new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "RowType", "ISSection", "ExpenseSubSection", "BSSection",
                "AccountCode", "AccountDescription", "IsContraCOGS", "TicketNumber"
            };

        private void FormatGridColumns(GridView view, bool treatUnknownColumnsAsMoney = false)
        {
            foreach (DevExpress.XtraGrid.Columns.GridColumn col in view.Columns)
            {
                string fn = col.FieldName.ToLowerInvariant();
                bool isMoney = fn.Contains("debit") || fn.Contains("credit") || fn.Contains("balance")
                            || fn.Contains("amount") || fn.Contains("total") || fn.Contains("difference")
                            || fn.Contains("income") || fn.Contains("expense") || fn.Contains("revenue")
                            || fn.Contains("cogs") || fn.Contains("profit");
                bool isDate = fn.Contains("date");

                if (!isMoney && !isDate && treatUnknownColumnsAsMoney
                    && !G_PIVOT_NON_MONEY_COLUMNS.Contains(col.FieldName))
                    isMoney = true;

                if (isMoney)
                {
                    col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                    col.DisplayFormat.FormatString = "N2";
                    col.AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                    col.AppearanceCell.Options.UseTextOptions = true;
                    col.AppearanceHeader.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;   // CLAUDE.md: figures and their headers right-aligned
                    col.AppearanceHeader.Options.UseTextOptions = true;

                    if (fn.Contains("debit"))
                    {
                        col.AppearanceCell.ForeColor = G_DEBIT;
                        col.AppearanceCell.Options.UseForeColor = true;
                    }
                    else if (fn.Contains("credit"))
                    {
                        col.AppearanceCell.ForeColor = G_CREDIT;
                        col.AppearanceCell.Options.UseForeColor = true;
                    }
                }
                else if (isDate)
                {
                    col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                    col.DisplayFormat.FormatString = "yyyy-MM-dd";
                }

                col.AppearanceHeader.Font = new Font(col.AppearanceHeader.Font ?? new Font("Segoe UI", 8.5f), FontStyle.Bold);
                col.AppearanceHeader.Options.UseFont = true;
            }

            view.RowCellStyle -= GridView_RowCellStyle;
            view.RowCellStyle += GridView_RowCellStyle;
        }

        // Bold + subtle highlight for structural rows (Opening/Beginning/
        // Period Change/Ending Balance/Header/Period/Ending row markers, plus
        // this form's own SUBTOTAL/GRANDTOTAL rows from the single-grid
        // Balance Sheet), a distinct highlight for (REVERSAL) entries, and
        // red/green for negative/positive money values so out-of-balance or
        // abnormal figures are visible at a glance without reading every number.
        private void GridView_RowCellStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowCellStyleEventArgs e)
        {
            var view = (GridView)sender;
            if (e.RowHandle < 0) return;

            string fn = e.Column.FieldName.ToLowerInvariant();

            bool isStructuralRow = false;
            bool isReversalRow = false;
            bool isGrandTotalRow = false;

            bool isGrandTotalDiffRow = false;

            object rowTypeVal = view.Columns["RowType"] != null
                ? view.GetRowCellValue(e.RowHandle, "RowType") : null;
            if (rowTypeVal != null)
            {
                string rt = rowTypeVal.ToString().ToUpperInvariant();
                isStructuralRow = rt == "OPENING" || rt == "HEADER" || rt == "PERIOD" || rt == "ENDING" || rt == "SUBTOTAL"
                    || rt == "SECTION_SUBTOTAL" || rt == "SUBSECTION_SUBTOTAL";
                isGrandTotalRow = rt == "GRANDTOTAL" || rt == "GRANDTOTAL_DIFF";
                isGrandTotalDiffRow = rt == "GRANDTOTAL_DIFF";
            }
            else
            {
                foreach (var textField in new[] { "Particulars", "TransDescription", "Trans Description" })
                {
                    if (view.Columns[textField] == null) continue;
                    string txt = view.GetRowCellValue(e.RowHandle, textField)?.ToString() ?? "";
                    if (txt.IndexOf("Beginning Balance", StringComparison.OrdinalIgnoreCase) >= 0
                     || txt.IndexOf("BeginningBalance Forward", StringComparison.OrdinalIgnoreCase) >= 0
                     || txt.IndexOf("Current Period Change", StringComparison.OrdinalIgnoreCase) >= 0
                     || txt.IndexOf("Ending Balance", StringComparison.OrdinalIgnoreCase) >= 0
                     || txt.IndexOf("OPENING BALANCE", StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        isStructuralRow = true;
                    }
                    if (txt.IndexOf("(REVERSAL)", StringComparison.OrdinalIgnoreCase) >= 0)
                        isReversalRow = true;
                    break;
                }
            }

            if (isGrandTotalRow)
            {
                e.Appearance.BackColor = G_ROW_GRANDTOTAL_BG;
                e.Appearance.ForeColor = G_ROW_GRANDTOTAL_FG;
                e.Appearance.Font = new Font(e.Appearance.Font ?? new Font("Segoe UI", 8.5f), FontStyle.Bold);
                e.Appearance.Options.UseBackColor = true;
                e.Appearance.Options.UseForeColor = true;
                e.Appearance.Options.UseFont = true;

                // GRANDTOTAL_DIFF is a live balance check, not a fixed label -- a non-zero
                // value here means the statement genuinely doesn't balance, so it still
                // needs to override even the gold accent. Discriminated by RowType (set by
                // the SP), not by matching the AccountDescription text -- that would silently
                // stop working if either side's wording ever changed.
                if (isGrandTotalDiffRow && (fn.Contains("amount") || fn.Contains("difference")))
                {
                    object val = view.GetRowCellValue(e.RowHandle, e.Column);
                    if (val != null && val != DBNull.Value && decimal.TryParse(val.ToString(), out var diffNum)
                        && Math.Abs(diffNum) >= 0.01m)
                    {
                        e.Appearance.ForeColor = G_NEGATIVE;
                        e.Appearance.Options.UseForeColor = true;
                    }
                }
                return;
            }
            else if (isReversalRow)
            {
                e.Appearance.BackColor = G_ROW_REV_BG;
                e.Appearance.ForeColor = G_ROW_REV_FG;
                e.Appearance.Font = new Font(e.Appearance.Font ?? new Font("Segoe UI", 8.5f), FontStyle.Bold);
                e.Appearance.Options.UseBackColor = true;
                e.Appearance.Options.UseForeColor = true;
                e.Appearance.Options.UseFont = true;
                return;
            }
            else if (isStructuralRow)
            {
                e.Appearance.BackColor = G_ROW_MARK_BG;
                e.Appearance.ForeColor = G_ROW_MARK_FG;
                e.Appearance.Font = new Font(e.Appearance.Font ?? new Font("Segoe UI", 8.5f), FontStyle.Bold);
                e.Appearance.Options.UseBackColor = true;
                e.Appearance.Options.UseForeColor = true;
                e.Appearance.Options.UseFont = true;
                return;
            }

            bool isMoney = fn.Contains("debit") || fn.Contains("credit") || fn.Contains("balance")
                        || fn.Contains("amount") || fn.Contains("total") || fn.Contains("difference");
            if (isMoney)
            {
                object val = view.GetRowCellValue(e.RowHandle, e.Column);
                if (val != null && val != DBNull.Value && decimal.TryParse(val.ToString(), out var num))
                {
                    if (fn.Contains("difference"))
                    {
                        e.Appearance.ForeColor = Math.Abs(num) < 0.01m ? G_POSITIVE : G_NEGATIVE;
                        e.Appearance.Options.UseForeColor = true;
                        if (Math.Abs(num) >= 0.01m)
                        {
                            e.Appearance.Font = new Font(e.Appearance.Font ?? new Font("Segoe UI", 8.5f), FontStyle.Bold);
                            e.Appearance.Options.UseFont = true;
                        }
                    }
                    else if (num < 0)
                    {
                        e.Appearance.ForeColor = G_NEGATIVE;
                        e.Appearance.Options.UseForeColor = true;
                    }
                }
            }

            if (fn.Contains("isabnormalbalance") && GetBoolLike(view, e.RowHandle, e.Column))
            {
                e.Appearance.ForeColor = G_NEGATIVE;
                e.Appearance.Font = new Font(e.Appearance.Font ?? new Font("Segoe UI", 8.5f), FontStyle.Bold);
                e.Appearance.Options.UseForeColor = true;
                e.Appearance.Options.UseFont = true;
            }
        }

        private static bool GetBoolLike(GridView view, int rowHandle, DevExpress.XtraGrid.Columns.GridColumn col)
        {
            var v = view.GetRowCellValue(rowHandle, col);
            if (v == null || v == DBNull.Value) return false;
            if (v is bool b) return b;
            return v.ToString() == "1" || string.Equals(v.ToString(), "true", StringComparison.OrdinalIgnoreCase);
        }

        // ── Export ──
        private void btnExport_Click(object sender, EventArgs e)
        {
            if (gridControlReport.DataSource == null)
            {
                XtraMessageBox.Show("Generate a report first.", "Nothing to Export",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            using (var sfd = new SaveFileDialog
            {
                Filter = "PDF File (*.pdf)|*.pdf|Excel Workbook (*.xlsx)|*.xlsx",
                FileName = $"{cboReportType.SelectedItem}_{DateTime.Now:yyyyMMdd_HHmmss}"
            })
            {
                if (sfd.ShowDialog() != DialogResult.OK) return;

                // Pivot -> Excel: data-aware export, so the header row and
                // AccountCode/AccountDescription (pinned left in BindResults) come out as
                // frozen panes. The print-layout path below can't freeze anything.
                if (_isPivotResultShown && sfd.FileName.EndsWith(".xlsx", StringComparison.OrdinalIgnoreCase))
                {
                    try
                    {
                        ExportPivotToXlsx(sfd.FileName);
                        XtraMessageBox.Show("Exported successfully.", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    }
                    catch (Exception ex)
                    {
                        XtraMessageBox.Show($"Export failed: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    }
                    return;
                }

                try
                {
                    ExportPrintLayout(sfd.FileName);
                    XtraMessageBox.Show("Exported successfully.", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                catch (Exception ex)
                {
                    XtraMessageBox.Show($"Export failed: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        // PDF / non-pivot Excel: a title band (report name + details) above the report grid and the
        // summary grid, as one print layout.
        private void ExportPrintLayout(string fileName)
        {
            using (var ps = new DevExpress.XtraPrinting.PrintingSystem())
            using (var compositeLink = new CompositeLink(ps))
            using (var headerGrid = new DevExpress.XtraGrid.GridControl())
            using (var headerView = new GridView())
            {
                // The title grid is never placed on a form, so it has no BindingContext of its own:
                // without one, PopulateColumns() creates no columns (Columns["Report"] was null ->
                // "Object reference not set", 2026-10-12) and the band prints empty. Give it one and
                // define its two columns explicitly.
                headerGrid.BindingContext = new BindingContext();
                headerGrid.ViewCollection.Add(headerView);
                headerGrid.MainView = headerView;
                headerView.GridControl = headerGrid;
                var headerData = new DataTable();
                headerData.Columns.Add("Report", typeof(string));
                headerData.Columns.Add("Details", typeof(string));
                headerData.Rows.Add(lblReportTitle.Text, lblReportSubtitle.Text);
                var colReport = headerView.Columns.AddVisible("Report");
                headerView.Columns.AddVisible("Details");
                headerGrid.DataSource = headerData;
                headerGrid.ForceInitialize();
                headerView.OptionsView.ShowColumnHeaders = false;
                headerView.OptionsView.ShowGroupPanel = false;
                headerView.OptionsView.ShowIndicator = false;
                colReport.AppearanceCell.Font = new Font("Tahoma", 12F, FontStyle.Bold);
                colReport.AppearanceCell.Options.UseFont = true;
                headerView.BestFitColumns();

                var headerLink = new DevExpress.XtraPrinting.PrintableComponentLink(ps) { Component = headerGrid };
                compositeLink.Links.Add(headerLink);

                var detailLink = new DevExpress.XtraPrinting.PrintableComponentLink(ps) { Component = gridControlReport };
                compositeLink.Links.Add(detailLink);

                if (gridControlSummary.DataSource != null && gridViewSummary.RowCount > 0)
                {
                    var summaryLink = new DevExpress.XtraPrinting.PrintableComponentLink(ps) { Component = gridControlSummary };
                    compositeLink.Links.Add(summaryLink);
                }

                compositeLink.CreateDocument();

                if (fileName.EndsWith(".pdf", StringComparison.OrdinalIgnoreCase))
                    compositeLink.ExportToPdf(fileName);
                else
                    compositeLink.ExportToXlsx(fileName, new DevExpress.XtraPrinting.XlsxExportOptions());
            }
        }

        // Data-aware XLSX export of the pivot grid: the column header row and the
        // fixed-left columns (AccountCode, AccountDescription) are frozen, and structural
        // rows (subtotals / grand totals) keep the grid's highlight.
        // No title/subtitle rows above the header on purpose: DevExpress only freezes the
        // header ROW when no sheet-header rows are added (verified in an exported file).
        private void ExportPivotToXlsx(string fileName)
        {
            var options = new XlsxExportOptionsEx
            {
                ExportType = DevExpress.Export.ExportType.DataAware,
                AllowFixedColumns = DevExpress.Utils.DefaultBoolean.True,
                AllowFixedColumnHeaderPanel = DevExpress.Utils.DefaultBoolean.True,
                SheetName = "Income Statement Pivot"
            };

            options.CustomizeCell += e =>
            {
                if (e.RowHandle < 0 || gridViewReport.Columns["RowType"] == null) return;

                string rt = gridViewReport.GetRowCellValue(e.RowHandle, "RowType")?.ToString().ToUpperInvariant() ?? "";
                bool isGrandTotal = rt == "GRANDTOTAL" || rt == "GRANDTOTAL_DIFF";
                bool isStructural = rt == "SUBTOTAL" || rt == "SECTION_SUBTOTAL" || rt == "SUBSECTION_SUBTOTAL"
                                 || rt == "HEADER" || rt == "OPENING" || rt == "PERIOD" || rt == "ENDING";
                if (!isGrandTotal && !isStructural) return;

                e.Formatting.BackColor = isGrandTotal ? G_ROW_GRANDTOTAL_BG : G_ROW_MARK_BG;
                e.Formatting.Font = new DevExpress.Export.XlCellFont
                {
                    Bold = true,
                    Color = isGrandTotal ? G_ROW_GRANDTOTAL_FG : G_ROW_MARK_FG
                };
                e.Handled = true;
            };

            gridControlReport.ExportToXlsx(fileName, options);
        }
    }
}
