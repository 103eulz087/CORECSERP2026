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
    public partial class AccountingReportsForm : DevExpress.XtraEditors.XtraUserControl
    {
        // ── How to slice each SP's result sets into (main grid, summary grid).
        //    Verified against the actual SP bodies (GLREPORTS_BODY.txt) -
        //    shapes genuinely differ per report, so this isn't guessable
        //    from parameters alone. ──
        private enum ResultShape
        {
            Standard2Set,        // Set1 = main, Set2 = summary (Trial Balance, Income Statement, Balance Sheet, Consolidated GL)
            SingleSet,           // Set1 = main only, no summary (GL Detail Transaction, General Ledger WithRunningBal)
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

        private readonly Dictionary<string, ReportConfig> _reportConfigs = new Dictionary<string, ReportConfig>
        {
            ["GL Detail Ledger"] = new ReportConfig
            {
                SpName = "sp_rpt_GLDetailLedgerWithDate",
                Mode = ParamMode.BranchAccountDateRange,
                Shape = ResultShape.GLDetailLedgerLegacy,
                Description = "Day-by-day account activity from GLSummary (pre-aggregated). Opening balance, daily rows, period totals. Requires a specific account. Check 'All Branches' for a combined ledger across every branch.",
                AllowAllBranches = true
            },
            ["GL Detail Transaction"] = new ReportConfig
            {
                SpName = "sp_rpt_GLDetailTransactionReport",
                Mode = ParamMode.BranchAccountDateRange,
                Shape = ResultShape.SingleSet,
                Description = "Transaction-level detail straight from TicketDetails/TicketMaster - one row per posting leg, not pre-aggregated. Check 'All Accounts' and/or 'All Branches' to widen the scope.",
                AllowAllBranches = true,
                SupportsAllAccounts = true
            },
            ["General Ledger (All Accounts)"] = new ReportConfig
            {
                SpName = "sp_rpt_GeneralLedger_WithRunningBal",
                Mode = ParamMode.BranchDateRange,
                Shape = ResultShape.SingleSet,
                Description = "All accounts, running balance, one flat report - Beginning/Transaction/Period/Ending rows per account. Check 'All Branches' for every branch combined.",
                AllowAllBranches = true
            },
            ["Trial Balance"] = new ReportConfig
            {
                SpName = "sp_rpt_TrialBalanceWithDate",
                Mode = ParamMode.BranchAsOfDate,
                Shape = ResultShape.Standard2Set,
                Description = "Snapshot of all account balances at a specific date. Works for any date - not just month-end. Debit must equal Credit. Check 'All Branches' for a company-wide consolidated snapshot.",
                AllowAllBranches = true
            },
            ["Income Statement"] = new ReportConfig
            {
                SpName = "sp_rpt_IncomeStatementWithDate",
                Mode = ParamMode.BranchDateRange,
                Shape = ResultShape.Standard2Set,
                Description = "Revenue and expense activity for a date range, single branch. Check 'All Branches' for a side-by-side pivot with Grand Total.",
                SupportsAllBranchPivot = true,
                PivotSpName = "sp_rpt_IncomeStatementAllBranchesPivot_TEST"   // TODO: not yet built - see note in form
            },
            ["Balance Sheet"] = new ReportConfig
            {
                SpName = "sp_rpt_BalanceSheetWithDate",
                Mode = ParamMode.BranchAsOfDate,
                Shape = ResultShape.Standard2Set,
                Description = "Assets, Liabilities, and Equity as of a specific date, single branch. Check 'All Branches' for a company-wide consolidated snapshot.",
                AllowAllBranches = true
            },
            ["Bank Reconciliation"] = new ReportConfig
            {
                SpName = "sp_rpt_BankReconciliationWithDate",
                Mode = ParamMode.BranchAccountAsOfDate,
                Shape = ResultShape.BankReconShape,
                Description = "GL side vs Bank side for a specific bank account, as of a specific date. Check 'All Branches' if this account's activity is recorded across multiple branches.",
                AllowAllBranches = true
            },
            ["Consolidated GL"] = new ReportConfig
            {
                SpName = "sp_rpt_ConsolidatedGLWithDate",
                Mode = ParamMode.ConsolidatedGL,
                Shape = ResultShape.Standard2Set,
                Description = "All branches combined. Trial Balance mode uses an as-of date; Income Statement mode uses a date range. (TB mode also returns a 3rd 'intercompany check' set, not yet shown here.)"
            }
        };

        private ReportConfig CurrentConfig =>
            lstReportType.SelectedItem != null && _reportConfigs.ContainsKey(lstReportType.SelectedItem.ToString())
                ? _reportConfigs[lstReportType.SelectedItem.ToString()]
                : null;

        public AccountingReportsForm()
        {
            InitializeComponent();
        }
        private bool _dataLoaded = false;
        private ContextMenuStrip _reportContextMenu;
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

            lstReportType.SelectedIndex = 0;
            ApplyParamModeForSelection();
            SetupReportContextMenu();

            _dataLoaded = true;
        }
        private void SetupReportContextMenu()
        {
            _reportContextMenu = new ContextMenuStrip();
            _reportContextMenu.Items.Add("View Related Entries (Same Ticket)", null, ViewRelatedEntries_Click);

            gridControlReport.MouseUp += GridControlReport_MouseUp;
        }
        //private void GridControlReport_MouseUp(object sender, MouseEventArgs e)
        //{
        //    if (e.Button != MouseButtons.Right) return;

        //    var hitInfo = gridViewReport.CalcHitInfo(e.Location);
        //    if (hitInfo.InRow || hitInfo.InRowCell)
        //    {
        //        gridViewReport.FocusedRowHandle = hitInfo.RowHandle;

        //        bool hasTicketNumber = gridViewReport.Columns["TicketNumber"] != null
        //            && gridViewReport.GetRowCellValue(hitInfo.RowHandle, "TicketNumber") != null
        //            && gridViewReport.GetRowCellValue(hitInfo.RowHandle, "TicketNumber") != DBNull.Value;

        //        if (hasTicketNumber)
        //            _reportContextMenu.Show(gridControlReport, e.Location);
        //    }
        //}
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
                // DIAGNOSTIC: list the actual column names so we can see
                // what sp_rpt_GLDetailTransactionReport really calls it,
                // instead of guessing again
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

                // Same money/date formatting as the main report grids —
                // reuses your existing FormatGridColumns/RowCellStyle logic
                // so this popup looks consistent with everything else
                gridView.PopulateColumns();
                FormatGridColumns(gridView);
                gridView.BestFitColumns();

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
        private void AccountingReportsForm_Load(object sender, EventArgs e)
        {
          

           
        }

        private void lstReportType_SelectedIndexChanged(object sender, EventArgs e)
        {
            ApplyParamModeForSelection();
        }

        // ── Show/hide the right parameter controls for whichever report is selected ──
        private void ApplyParamModeForSelection()
        {
            var cfg = CurrentConfig;
            if (cfg == null) return;

            lblReportTitle.Text = lstReportType.SelectedItem.ToString();
            lblReportSubtitle.Text = $"Branch: {cboBranchCode.Text} · Select parameters and click Generate";
            lblDescription.Text = cfg.Description;
            lblSpName.Text = "SP: " + cfg.SpName;

            bool showAccount = cfg.Mode == ParamMode.BranchAccountDateRange || cfg.Mode == ParamMode.BranchAccountAsOfDate;
            bool showAsOf = cfg.Mode == ParamMode.BranchAsOfDate || cfg.Mode == ParamMode.BranchAccountAsOfDate;
            bool showDateRange = cfg.Mode == ParamMode.BranchAccountDateRange || cfg.Mode == ParamMode.BranchDateRange;
            bool showAllBranch = cfg.SupportsAllBranchPivot || cfg.AllowAllBranches;
            bool showAllAccounts = cfg.SupportsAllAccounts;
            bool showZeroChk = cfg.SpName == "sp_rpt_GLDetailTransactionReport";
            bool showConsolidated = cfg.Mode == ParamMode.ConsolidatedGL;
            bool showBranch = !showConsolidated; // consolidated is always all-branch

            lblBranchCode.Visible = showBranch;
            cboBranchCode.Visible = showBranch;

            lblAccountCode.Visible = showAccount;
            txtAccountCode.Visible = showAccount;

            lblAsOfDate.Visible = showAsOf || (showConsolidated && rgConsolidatedMode.EditValue?.ToString() == "TB");
            dteAsOfDate.Visible = lblAsOfDate.Visible;

            lblDateFrom.Visible = showDateRange || (showConsolidated && rgConsolidatedMode.EditValue?.ToString() == "IS");
            dteDateFrom.Visible = lblDateFrom.Visible;
            lblDateTo.Visible = lblDateFrom.Visible;
            dteDateTo.Visible = lblDateFrom.Visible;

            chkAllBranches.Visible = showAllBranch;
            if (!showAllBranch) chkAllBranches.Checked = false;
            if (showAllBranch)
            {
                string caption = cfg.SupportsAllBranchPivot
                    ? "All Branches (Pivot - one column per branch + Grand Total)"
                    : "All Branches (Consolidated - combined across every branch)";
                chkAllBranches.Text = caption;
                chkAllBranches.Properties.Caption = caption;
            }

            chkAllAccounts.Visible = showAllAccounts;
            if (!showAllAccounts) chkAllAccounts.Checked = false;

            chkIncludeZeroActivity.Visible = showZeroChk;

            rgConsolidatedMode.Visible = showConsolidated;
            if (showConsolidated && rgConsolidatedMode.EditValue == null)
                rgConsolidatedMode.EditValue = "TB";

            // If All-Branches is checked, hide the single-branch selector -
            // either the pivot query or the NULL-branch consolidation
            // covers every branch on its own
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

            // All Branches and All Accounts are independent toggles —
            // "one specific account, viewed across every branch" is a
            // legitimate, common report shape on its own. (Previously
            // this cascaded All Branches into force-checking All
            // Accounts too, which blocked exactly that case.)

            lblReportSubtitle.Text = allBranches
                ? (isPivot ? "All Branches (pivot) · Select date range and click Generate"
                           : "All Branches (Consolidated) · Select parameters and click Generate")
                : $"Branch: {cboBranchCode.Text} · Select parameters and click Generate";
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
                            //cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 5).Value =
                            //    (cfg.AllowAllBranches && chkAllBranches.Checked) ? (object)DBNull.Value : cboBranchCode.Text.Trim();
                            cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 5).Value =
                              (cfg.AllowAllBranches && chkAllBranches.Checked) ? (object)DBNull.Value : cboBranchCode.EditValue?.ToString();
                            cmd.Parameters.Add("@AccountCode", SqlDbType.VarChar, 20).Value =
                                (cfg.SupportsAllAccounts && chkAllAccounts.Checked) ? (object)DBNull.Value
                                : string.IsNullOrWhiteSpace(txtAccountCode.Text) ? (object)DBNull.Value : txtAccountCode.Text.Trim();
                            cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value = dteDateFrom.DateTime;
                            cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value = dteDateTo.DateTime;
                            if (cfg.SpName == "sp_rpt_GLDetailTransactionReport")
                                cmd.Parameters.Add("@IncludeZeroActivity", SqlDbType.Bit).Value = chkIncludeZeroActivity.Checked;
                            break;

                        case ParamMode.BranchAsOfDate:
                            cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 5).Value =
                                (cfg.AllowAllBranches && chkAllBranches.Checked) ? (object)DBNull.Value : cboBranchCode.Text.Trim();
                            cmd.Parameters.Add("@AsOfDate", SqlDbType.Date).Value = dteAsOfDate.DateTime;
                            break;

                        case ParamMode.BranchDateRange:
                            cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 5).Value =
                                (cfg.AllowAllBranches && chkAllBranches.Checked) ? (object)DBNull.Value : cboBranchCode.Text.Trim();
                            cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value = dteDateFrom.DateTime;
                            cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value = dteDateTo.DateTime;
                            // sp_rpt_GeneralLedger_WithRunningBal has two extra optional params -
                            // @AccountType is not yet exposed in the UI (always NULL = all types);
                            // @SkipZero is the inverse of the "include zero activity" checkbox.
                            if (cfg.SpName == "sp_rpt_GeneralLedger_WithRunningBal")
                            {
                                cmd.Parameters.Add("@AccountType", SqlDbType.VarChar, 10).Value = DBNull.Value;
                                cmd.Parameters.Add("@SkipZero", SqlDbType.Bit).Value = !chkIncludeZeroActivity.Checked;
                            }
                            break;

                        case ParamMode.BranchAccountAsOfDate:
                            cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 5).Value =
                                (cfg.AllowAllBranches && chkAllBranches.Checked) ? (object)DBNull.Value : cboBranchCode.Text.Trim();
                            cmd.Parameters.Add("@AccountCode", SqlDbType.VarChar, 20).Value = txtAccountCode.Text.Trim();
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
                            // FIX: actual parameter name is @ReportType, not @Mode
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

                    BindResults(ds, cfg);
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
        private void BindResults(DataSet ds, ReportConfig cfg)
        {
            // FIX: GridView does NOT auto-regenerate columns when the
            // DataSource is swapped to a differently-shaped DataTable - it
            // keeps whichever columns were built for the FIRST report ever
            // bound in this session, and just matches field names where
            // possible for anything bound afterward. Since every report
            // here has a different real schema, that silently produced
            // blank columns for every field that isn't coincidentally
            // named the same as the first report's (e.g. "AccountCode"
            // exists in every report, so it kept working; "Debits"/
            // "Credits"/"PostingDate" etc. only exist in GL Detail
            // Ledger's actual result set, so they showed blank everywhere
            // else). Clearing columns before every bind forces a full
            // regeneration against whatever DataTable is actually current.
            gridViewReport.Columns.Clear();
            gridViewSummary.Columns.Clear();

            switch (cfg.Shape)
            {
                case ResultShape.SingleSet:
                    gridControlReport.DataSource = ds.Tables.Count > 0 ? ds.Tables[0] : null;
                    gridControlSummary.DataSource = null;
                    break;

                case ResultShape.GLDetailLedgerLegacy:
                    // Set1 = account header (single row, shown in subtitle only)
                    // Set2 = opening balance row, Set3 = daily detail rows -
                    //   same column shape, so merge them into one ledger view
                    // Set4 = period summary
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

            FormatGridColumns(gridViewReport);
            FormatGridColumns(gridViewSummary);

            if (gridViewReport.Columns["TicketNumber"] != null)
                gridViewReport.Columns["TicketNumber"].Visible = false;

            // ColumnAutoWidth defaults to true, which keeps stretching/shrinking columns
            // to exactly fill the grid's visible width on every layout pass - that fights
            // BestFitColumns() below and squeezes everything down whenever a report's
            // content is wider than the grid (GL Detail Transaction has more/wider
            // columns than most reports here, so the shrinking was most visible there).
            // Disabling it lets BestFitColumns' widths actually stick, with horizontal
            // scrolling instead of forced compression.
            gridViewReport.OptionsView.ColumnAutoWidth = false;
            gridViewSummary.OptionsView.ColumnAutoWidth = false;

            gridViewReport.BestFitColumns();
            gridViewSummary.BestFitColumns();
        }

        // ═══════════════════════════════════════════════════════════════
        // COSMETIC FORMATTING — applied to every report uniformly, since
        // column names vary per SP but follow consistent naming patterns
        // (Debit/Credit/Balance/Amount/Total/Date etc.) across all of them.
        // ═══════════════════════════════════════════════════════════════

        // Same palette as InitializeComponent's dark theme, kept local here
        // since these are only needed for grid cell coloring, not layout.
        private static readonly Color G_DEBIT = Color.FromArgb(0, 72, 118);  // blue
        //private static readonly Color G_DEBIT = Color.FromArgb(120, 190, 235);  // blue
        //private static readonly Color G_CREDIT = Color.FromArgb(240, 175, 105);  // amber/orange
        private static readonly Color G_CREDIT = Color.FromArgb(255, 132, 0);  // amber/orange
        private static readonly Color G_BALANCE = Color.FromArgb(230, 230, 235);  // light text
        private static readonly Color G_NEGATIVE = Color.FromArgb(240, 120, 130);  // red
        private static readonly Color G_POSITIVE = Color.FromArgb(150, 215, 160);  // green
        private static readonly Color G_GOLD = Color.FromArgb(201, 162, 39);
        private static readonly Color G_MUTED = Color.FromArgb(140, 148, 165);
        // Structural rows (Beginning/Period Change/Ending Balance) - noticeably
        // lighter background + bright white bold text on EVERY column, not just
        // a background tint left to fall back on whatever the default text
        // color happens to be (that's what made these unreadable before).
        private static readonly Color G_ROW_MARK_BG = Color.FromArgb(56, 64, 92);
        private static readonly Color G_ROW_MARK_FG = Color.FromArgb(255, 255, 255);
        // Reversal rows - warm dark background + bright orange bold text
        private static readonly Color G_ROW_REV_BG = Color.FromArgb(110, 55, 40);
        private static readonly Color G_ROW_REV_FG = Color.FromArgb(255, 195, 150);

        private void FormatGridColumns(GridView view)
        {
            foreach (DevExpress.XtraGrid.Columns.GridColumn col in view.Columns)
            {
                string fn = col.FieldName.ToLowerInvariant();
                bool isMoney = fn.Contains("debit") || fn.Contains("credit") || fn.Contains("balance")
                            || fn.Contains("amount") || fn.Contains("total") || fn.Contains("difference")
                            || fn.Contains("income") || fn.Contains("expense") || fn.Contains("revenue")
                            || fn.Contains("cogs") || fn.Contains("profit");
                bool isDate = fn.Contains("date");

                if (isMoney)
                {
                    col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                    col.DisplayFormat.FormatString = "N2";
                    col.AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                    col.AppearanceCell.Options.UseTextOptions = true;

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
        // Period Change/Ending Balance/Header/Period/Ending row markers),
        // a distinct highlight for (REVERSAL) entries, and red/green for
        // negative/positive money values so out-of-balance or abnormal
        // figures are visible at a glance without reading every number.
        private void GridView_RowCellStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowCellStyleEventArgs e)
        {
            var view = (GridView)sender;
            if (e.RowHandle < 0) return;

            string fn = e.Column.FieldName.ToLowerInvariant();

            // ── Structural row detection: an explicit RowType/Row Type
            //    column if the report has one, else fall back to scanning
            //    Particulars/description text for the same markers ──
            bool isStructuralRow = false;
            bool isReversalRow = false;

            object rowTypeVal = view.Columns["RowType"] != null
                ? view.GetRowCellValue(e.RowHandle, "RowType") : null;
            if (rowTypeVal != null)
            {
                string rt = rowTypeVal.ToString().ToUpperInvariant();
                isStructuralRow = rt == "OPENING" || rt == "HEADER" || rt == "PERIOD" || rt == "ENDING";
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

            if (isReversalRow)
            {
                e.Appearance.BackColor = G_ROW_REV_BG;
                e.Appearance.ForeColor = G_ROW_REV_FG;
                e.Appearance.Font = new Font(e.Appearance.Font ?? new Font("Segoe UI", 8.5f), FontStyle.Bold);
                e.Appearance.Options.UseBackColor = true;
                e.Appearance.Options.UseForeColor = true;
                e.Appearance.Options.UseFont = true;
                return;   // don't let the money-column logic below override this row's color
            }
            else if (isStructuralRow)
            {
                e.Appearance.BackColor = G_ROW_MARK_BG;
                e.Appearance.ForeColor = G_ROW_MARK_FG;
                e.Appearance.Font = new Font(e.Appearance.Font ?? new Font("Segoe UI", 8.5f), FontStyle.Bold);
                e.Appearance.Options.UseBackColor = true;
                e.Appearance.Options.UseForeColor = true;
                e.Appearance.Options.UseFont = true;
                return;   // same - keep this row's treatment uniform, no per-cell overrides
            }

            // ── Value-based coloring for money columns (only reached for
            //    ordinary DETAIL/TRANSACTION rows, not structural/reversal
            //    ones handled above): negative red, zero/near-zero on a
            //    Difference column green (balanced) ──
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

            // ── Boolean flag columns (IsAbnormalBalance, IsReconciled, etc.) -
            //    highlight when TRUE/1 for an abnormal condition ──
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

            using (var sfd = new SaveFileDialog { Filter = "Excel Files|*.xlsx", FileName = $"{lstReportType.SelectedItem}_{DateTime.Now:yyyyMMdd_HHmmss}.xlsx" })
            {
                if (sfd.ShowDialog() != DialogResult.OK) return;

                try
                {
                    // BUG: this used to export gridViewReport only. Most report shapes
                    // (Standard2Set, GLDetailLedgerLegacy, BankReconShape - everything
                    // except SingleSet, see BindResults()/ResultShape above) also populate
                    // a second, genuinely meaningful SUMMARY grid (gridControlSummary,
                    // visibly docked below the detail grid with its own "SUMMARY"
                    // caption) that got silently dropped from every export. Combine both
                    // into one workbook via a CompositeLink instead of exporting the
                    // detail grid alone.
                    using (var ps = new DevExpress.XtraPrinting.PrintingSystem())
                    using (var compositeLink = new CompositeLink(ps))
                    {
                        var detailLink = new DevExpress.XtraPrinting.PrintableComponentLink(ps) { Component = gridControlReport };
                        compositeLink.Links.Add(detailLink);

                        if (gridControlSummary.DataSource != null && gridViewSummary.RowCount > 0)
                        {
                            var summaryLink = new DevExpress.XtraPrinting.PrintableComponentLink(ps) { Component = gridControlSummary };
                            compositeLink.Links.Add(summaryLink);
                        }

                        compositeLink.CreateDocument();
                        // XlsxExportOptions has no "ExportType"/WYSIWYG property in this
                        // DevExpress version - its defaults (ExportMode=SingleFile,
                        // RawDataMode=false) already give the same single-file, formatted
                        // export that was intended, so no explicit options are needed.
                        compositeLink.ExportToXlsx(sfd.FileName, new DevExpress.XtraPrinting.XlsxExportOptions());
                    }
                    XtraMessageBox.Show("Exported successfully.", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                catch (Exception ex)
                {
                    XtraMessageBox.Show($"Export failed: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }
    }
}