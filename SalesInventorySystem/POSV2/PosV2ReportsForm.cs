using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;
using DevExpress.Data;
using DevExpress.XtraEditors;
using DevExpress.XtraEditors.Controls;
using DevExpress.XtraGrid;
using DevExpress.XtraGrid.Views.Grid;
using DevExpress.XtraTab;
using SalesInventorySystem.Classes;

namespace SalesInventorySystem.POSV2
{
    // POS V2 reports (phase 5), in the main app (server data, not a terminal's): Z-readings (one row per shift, with the
    // accumulated grand total and the GL ticket), the sales journal (one row per OR), returns (one row per returned line)
    // and Needs attention (flagged sales / returns, open shortages, customer credits, shifts whose GL isn't booked, shifts
    // open too long). A global admin picks any branch or all; everyone else sees their own branch. Data is fetched off
    // the UI thread and bound after (Known Bug #8). Numbers stay numeric: N2 money, N3 quantities, footer sums.
    public sealed class PosV2ReportsForm : XtraForm
    {
        private readonly LookUpEdit _cboBranch = new LookUpEdit();
        private readonly DateEdit _dtFrom = new DateEdit(), _dtTo = new DateEdit();
        private readonly SimpleButton _btnLoad = new SimpleButton(), _btnExport = new SimpleButton();
        private readonly LabelControl _lblStatus = new LabelControl();
        private readonly XtraTabControl _tabs = new XtraTabControl { Dock = DockStyle.Fill };
        private readonly Dictionary<string, GridView> _views = new Dictionary<string, GridView>();
        private readonly bool _admin;
        private int _loadSeq;

        private static readonly string[][] Reports =
        {
            new[] { "Z-readings (shifts)", "dbo.sp_rpt_POSV2_Shifts" },
            new[] { "Sales journal", "dbo.sp_rpt_POSV2_SalesJournal" },
            new[] { "Returns", "dbo.sp_rpt_POSV2_Returns" },
            new[] { "Needs attention", "dbo.sp_rpt_POSV2_NeedsAttention" }
        };

        public PosV2ReportsForm()
        {
            Text = "POS V2 Reports";
            ClientSize = new Size(1200, 700);
            StartPosition = FormStartPosition.CenterScreen;
            bool a; _admin = bool.TryParse(Login.isglobalAdmin, out a) && a;

            var top = new PanelControl { Dock = DockStyle.Top, Height = 48 };
            var lblB = new LabelControl { Text = "Branch", Location = new Point(10, 16) };
            _cboBranch.Location = new Point(60, 12); _cboBranch.Width = 260;
            _cboBranch.Properties.TextEditStyle = TextEditStyles.DisableTextEditor;   // pick from the list (Known Bug #2)
            _cboBranch.Properties.ValueMember = "BranchCode";
            _cboBranch.Properties.DisplayMember = "Display";                         // Code - Name
            _cboBranch.Properties.Columns.Add(new LookUpColumnInfo("Display", "Branch"));
            _cboBranch.Properties.ShowHeader = false;
            var lblF = new LabelControl { Text = "From", Location = new Point(335, 16) };
            _dtFrom.Location = new Point(370, 12); _dtFrom.Width = 110;
            var lblT = new LabelControl { Text = "To", Location = new Point(490, 16) };
            _dtTo.Location = new Point(510, 12); _dtTo.Width = 110;
            foreach (var d in new[] { _dtFrom, _dtTo })
            {
                d.Properties.DisplayFormat.FormatString = "yyyy-MM-dd";
                d.Properties.EditFormat.FormatString = "yyyy-MM-dd";
                d.Properties.Mask.EditMask = "yyyy-MM-dd";
            }
            _dtFrom.DateTime = DateTime.Today.AddDays(1 - DateTime.Today.Day);
            _dtTo.DateTime = DateTime.Today;
            _btnLoad.Text = "Load"; _btnLoad.Location = new Point(635, 10); _btnLoad.Size = new Size(80, 28);
            _btnLoad.Click += async (s, e) => await LoadAsync();
            _btnExport.Text = "Export to Excel"; _btnExport.Location = new Point(722, 10); _btnExport.Size = new Size(120, 28);
            _btnExport.Click += (s, e) => Export();
            _lblStatus.Location = new Point(855, 16); _lblStatus.AutoSizeMode = LabelAutoSizeMode.Horizontal;
            top.Controls.AddRange(new Control[] { lblB, _cboBranch, lblF, _dtFrom, lblT, _dtTo, _btnLoad, _btnExport, _lblStatus });

            foreach (var r in Reports)
            {
                var page = new XtraTabPage { Text = r[0] };
                var grid = new GridControl { Dock = DockStyle.Fill };
                var view = new GridView(grid);
                grid.MainView = view;
                view.OptionsBehavior.Editable = false;
                view.OptionsView.ShowFooter = true;
                view.OptionsView.ColumnAutoWidth = false;
                view.OptionsFind.AlwaysVisible = true;
                DevXGridViewSettings.ApplyTotalsBandAppearance(view);
                page.Controls.Add(grid);
                _tabs.TabPages.Add(page);
                _views[r[1]] = view;
            }
            // a grid on a tab not opened yet can't be formatted at load (no columns yet): format it when its tab opens
            _tabs.SelectedPageChanged += (s, e) =>
            {
                var view = _views[Reports[_tabs.SelectedTabPageIndex][1]];
                var data = view.GridControl.DataSource as DataTable;
                if (data != null && !Equals(view.Tag, "formatted")) Bind(view, data);
            };
            Controls.Add(_tabs);
            Controls.Add(top);
            Shown += async (s, e) => { await LoadBranchesAsync(); await LoadAsync(); };
        }

        private async Task LoadBranchesAsync()
        {
            try
            {
                var dt = await Task.Run(() =>
                {
                    var t = new DataTable();
                    using (var con = Database.getConnection())
                    using (var cmd = new SqlCommand("SELECT BranchCode, BranchCode + ' - ' + BranchName AS Display FROM dbo.Branches ORDER BY BranchCode", con))
                        new SqlDataAdapter(cmd).Fill(t);
                    return t;
                });
                if (IsDisposed) return;
                if (_admin)
                {
                    var all = dt.NewRow(); all["BranchCode"] = ""; all["Display"] = "(all branches)";
                    dt.Rows.InsertAt(all, 0);
                }
                else
                {
                    var mine = dt.AsEnumerable().Where(r => r.Field<string>("BranchCode") == Login.assignedBranch).ToList();
                    dt = mine.Count > 0 ? mine.CopyToDataTable() : dt.Clone();
                    _cboBranch.Enabled = false;   // own branch only
                }
                _cboBranch.Properties.DataSource = dt;
                _cboBranch.EditValue = _admin ? "" : Login.assignedBranch;
            }
            catch (Exception ex) { _lblStatus.Text = "Branches: " + ex.Message; }
        }

        // every report of the tabs, in one background fetch; bound on the UI thread after (a newer load wins)
        private async Task LoadAsync()
        {
            if (_dtFrom.EditValue == null || _dtTo.EditValue == null) return;
            int seq = ++_loadSeq;
            string branch = Convert.ToString(_cboBranch.EditValue);   // the ValueMember, never the text (Known Bug #3)
            if (!_admin)
            {
                branch = Login.assignedBranch;
                // UI review B1: a blank branch must never become "every branch" (the procs read NULL as all branches)
                if (string.IsNullOrWhiteSpace(branch)) { _lblStatus.Text = "Your user has no branch assigned: ask an admin."; return; }
            }
            DateTime from = _dtFrom.DateTime.Date, to = _dtTo.DateTime.Date;
            _btnLoad.Enabled = false;
            _lblStatus.Text = "Loading…";
            try
            {
                var results = await Task.Run(() =>
                {
                    var map = new Dictionary<string, DataTable>();
                    using (var con = Database.getConnection())
                        foreach (var r in Reports)
                            using (var cmd = new SqlCommand(r[1], con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 300 })
                            {
                                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 10).Value = string.IsNullOrEmpty(branch) ? (object)DBNull.Value : branch;
                                if (r[1] != "dbo.sp_rpt_POSV2_NeedsAttention")
                                {
                                    cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value = from;
                                    cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value = to;
                                }
                                var t = new DataTable();
                                new SqlDataAdapter(cmd).Fill(t);
                                map[r[1]] = t;
                            }
                    return map;
                });
                if (IsDisposed || seq != _loadSeq) return;
                foreach (var kv in results) Bind(_views[kv.Key], kv.Value);
                _lblStatus.Text = results["dbo.sp_rpt_POSV2_Shifts"].Rows.Count + " shift(s), " + results["dbo.sp_rpt_POSV2_SalesJournal"].Rows.Count +
                                  " sale(s), " + results["dbo.sp_rpt_POSV2_NeedsAttention"].Rows.Count + " item(s) need attention";
            }
            catch (Exception ex) { if (!IsDisposed) _lblStatus.Text = "Load failed: " + ex.Message; }
            finally { if (!IsDisposed) _btnLoad.Enabled = true; }
        }

        private static void Bind(GridView view, DataTable data)
        {
            // the columns are built once; a reload keeps the user's order, widths and filters (UI review S4)
            // formatted once, flagged in Tag (not by Columns.Count: a grid on a tab not shown yet gets no columns from
            // PopulateColumns, then makes its own when shown, which skipped the formatting for good; CLAUDE.md numeric rule 4)
            view.GridControl.DataSource = data;
            if (Equals(view.Tag, "formatted")) return;
            view.PopulateColumns();
            if (view.Columns.Count == 0) return;   // not bound yet: the next load formats it
            view.Tag = "formatted";
            bool attention = data.Columns.Contains("Kind");   // Needs attention: Amount mixes pesos and qty, so no sums
            if (data.Columns.Contains("ORNo") && data.Columns.Contains("Status") && !data.Columns.Contains("ReturnNo"))
                view.ActiveFilterString = "[Status] <> 'VOIDED'";   // sales journal: footers = sales that count (clear the filter to see voids)
            foreach (DevExpress.XtraGrid.Columns.GridColumn c in view.Columns)
            {
                if (c.ColumnType == typeof(int) && c.FieldName.EndsWith("Count"))
                {
                    c.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                    c.DisplayFormat.FormatString = "N0";
                    c.Summary.Add(SummaryItemType.Sum, c.FieldName, "{0:N0}");
                    continue;
                }
                if (attention && c.FieldName == "Amount")
                {
                    c.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                    c.DisplayFormat.FormatString = "#,0.###";   // pesos, or a qty for a shortage
                    continue;
                }
                if (c.ColumnType == typeof(decimal) || c.ColumnType == typeof(double))
                {
                    bool qty = c.FieldName.IndexOf("Qty", StringComparison.OrdinalIgnoreCase) >= 0 || c.FieldName.IndexOf("Quantity", StringComparison.OrdinalIgnoreCase) >= 0;
                    c.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                    c.DisplayFormat.FormatString = qty ? "N3" : "N2";
                    bool notSummed = c.FieldName.StartsWith("Accumulated") || c.FieldName == "BeginningCash" || c.FieldName == "ExpectedCash";
                    if (!notSummed) c.Summary.Add(SummaryItemType.Sum, c.FieldName, qty ? "{0:N3}" : "{0:N2}");
                }
                else if (c.ColumnType == typeof(DateTime))
                {
                    c.DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                    c.DisplayFormat.FormatString = c.FieldName == "BusinessDate" || c.FieldName == "OrigSaleDate" ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm";
                }
            }
            view.BestFitColumns();
        }

        private void Export()
        {
            var view = _views[Reports[_tabs.SelectedTabPageIndex][1]];
            if (view.RowCount == 0) { XtraMessageBox.Show("Nothing to export on this tab."); return; }
            using (var dlg = new SaveFileDialog { Filter = "Excel workbook (*.xlsx)|*.xlsx", FileName = "POSV2_" + _tabs.SelectedTabPage.Text.Replace(" ", "_").Replace("(", "").Replace(")", "") +
                                                                                                      "_" + _dtFrom.DateTime.ToString("yyyyMMdd") + "-" + _dtTo.DateTime.ToString("yyyyMMdd") + ".xlsx" })
            {
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                view.ExportToXlsx(dlg.FileName, new DevExpress.XtraPrinting.XlsxExportOptionsEx { ExportType = DevExpress.Export.ExportType.DataAware });
                _lblStatus.Text = "Exported to " + dlg.FileName;
            }
        }
    }
}
