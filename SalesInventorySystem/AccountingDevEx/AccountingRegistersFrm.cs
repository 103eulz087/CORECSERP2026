using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Windows.Forms;
using DevExpress.Data;
using DevExpress.Utils;
using DevExpress.XtraEditors;
using DevExpress.XtraEditors.Controls;
using DevExpress.XtraGrid;
using DevExpress.XtraGrid.Columns;
using DevExpress.XtraGrid.Views.Grid;
using DevExpress.XtraTab;

namespace SalesInventorySystem.AccountingDevEx
{
    /// <summary>
    /// Registers (SQL/[92]-2026-10-15f_Registers_Invoice_CollectionReceipt_EWTPayable.sql), read-only, a page of the
    /// Accounting Board:
    ///   Invoice Register             sp_rpt_InvoiceRegister            sales invoices per branch series, sequential
    ///   Collection Receipt Register  sp_rpt_CollectionReceiptRegister  AR payments (CR No.) per branch series, sequential
    ///   EWT Payable                  sp_rpt_EWTPayableLedger           the 20104 ledger, withheld lines PAID / UNPAID (FIFO)
    /// The registers flag DUPLICATE numbers and GAP / JUMP (skipped numbers) inside a branch's series; the numbers are typed
    /// by staff, one series per branch. Built in code (no designer file), like LoanRevaluationFrm.
    /// </summary>
    public class AccountingRegistersFrm : XtraUserControl
    {
        private readonly LookUpEdit cboBranch = new LookUpEdit();
        private readonly DateEdit dtFrom = new DateEdit();
        private readonly DateEdit dtTo = new DateEdit();
        private readonly SimpleButton btnGenerate = new SimpleButton { Text = "Generate" };
        private readonly SimpleButton btnExport = new SimpleButton { Text = "Export to Excel" };
        private readonly LabelControl lblHint = new LabelControl();

        private readonly XtraTabControl tabs = new XtraTabControl();
        private readonly Dictionary<XtraTabPage, Tab> _tabs = new Dictionary<XtraTabPage, Tab>();

        private bool _dataLoaded;
        private bool _allBranchesAllowed;
        private Font _bold;

        private const string AllBranches = "ALL";

        private sealed class Tab
        {
            public XtraTabPage Page;
            public GridControl Grid;
            public GridView View;
            public string Proc;
            public string FilePrefix;
            public string Hint;
            public bool Formatted;   // the grid creates its columns on DataSource, so a column count can't tell
            public bool Stale = true;
        }

        public AccountingRegistersFrm()
        {
            Text = "Registers";
            Size = new Size(1200, 720);
            BuildLayout();
            Load += (s, e) => LoadData();   // fallback only; the board calls LoadData() (Known Bug Pattern #1)
        }

        // ── layout ───────────────────────────────────────────────
        private static LabelControl Caption(string text) =>
            new LabelControl { Text = text, Anchor = AnchorStyles.Left, AutoSizeMode = LabelAutoSizeMode.Default };

        private void BuildLayout()
        {
            // rows sized for the taller WXI skin (PRODUCTION opens in it)
            var top = new TableLayoutPanel { Dock = DockStyle.Top, Height = 90, ColumnCount = 9, RowCount = 2, Padding = new Padding(8, 6, 8, 2) };
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 62));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 280));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 52));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 140));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 36));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 140));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 112));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 140));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            top.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
            top.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));

            cboBranch.Anchor = AnchorStyles.Left | AnchorStyles.Right;
            cboBranch.Properties.TextEditStyle = TextEditStyles.DisableTextEditor;   // Known Bug Pattern #2
            cboBranch.Properties.ShowHeader = false;
            cboBranch.Properties.ShowFooter = false;
            cboBranch.EditValueChanged += (s, e) => FiltersChanged();

            foreach (var d in new[] { dtFrom, dtTo })
            {
                d.Anchor = AnchorStyles.Left | AnchorStyles.Right;
                d.Properties.DisplayFormat.FormatString = "yyyy-MM-dd";
                d.Properties.DisplayFormat.FormatType = FormatType.DateTime;
                d.Properties.EditFormat.FormatString = "yyyy-MM-dd";
                d.Properties.EditFormat.FormatType = FormatType.DateTime;
                d.Properties.Mask.EditMask = "yyyy-MM-dd";
                d.EditValueChanged += (s, e) => FiltersChanged();
            }

            btnGenerate.Size = new Size(104, 30);
            btnGenerate.Anchor = AnchorStyles.Left;
            btnGenerate.Appearance.Font = new Font("Tahoma", 9F, FontStyle.Bold);
            btnGenerate.Appearance.Options.UseFont = true;
            btnGenerate.Click += (s, e) => Generate(ActiveTab, true);

            btnExport.Size = new Size(132, 30);
            btnExport.Anchor = AnchorStyles.Left;
            btnExport.Click += (s, e) => ExportActive();

            lblHint.AutoSizeMode = LabelAutoSizeMode.None;
            lblHint.Dock = DockStyle.Fill;
            lblHint.Appearance.ForeColor = Color.DimGray;
            lblHint.Appearance.Options.UseForeColor = true;
            lblHint.Appearance.TextOptions.VAlignment = VertAlignment.Center;
            lblHint.Appearance.TextOptions.WordWrap = WordWrap.Wrap;
            lblHint.Appearance.Options.UseTextOptions = true;

            top.Controls.Add(Caption("Branch:"), 0, 0);
            top.Controls.Add(cboBranch, 1, 0);
            top.Controls.Add(Caption("From:"), 2, 0);
            top.Controls.Add(dtFrom, 3, 0);
            top.Controls.Add(Caption("To:"), 4, 0);
            top.Controls.Add(dtTo, 5, 0);
            top.Controls.Add(btnGenerate, 6, 0);
            top.Controls.Add(btnExport, 7, 0);
            top.Controls.Add(lblHint, 0, 1); top.SetColumnSpan(lblHint, 9);

            AddTab("Invoice Register", "sp_rpt_InvoiceRegister", "INVOICE_REGISTER",
                "Sales invoices by branch series and number (invoice date in the range). DUPLICATE = the number is on more than one delivery; " +
                "GAP / JUMP = numbers skipped in the branch's series (JUMP = more than 50 at once, likely a typing slip).");
            AddTab("Collection Receipt Register", "sp_rpt_CollectionReceiptRegister", "CR_REGISTER",
                "AR payments by CR No. series and number (payment date in the range; branch = the customer's). DUPLICATE = the CR No. is on " +
                "more than one payment that is not reversed; GAP / JUMP = numbers skipped in the branch's series; CANCELLED = a CR recorded " +
                "as cancelled (Client Payments › Cancelled CR…), which fills its place in the series.");
            AddTab("EWT Payable", "sp_rpt_EWTPayableLedger", "EWT_PAYABLE",
                "The EWT payable ledger (20104 WTAX PAYABLE - EXPANDED) in date order. Remittances pay the oldest withheld amounts first: " +
                "Paid / Unpaid / Status as of the To date. Remittances and the running balance are company-wide.");

            tabs.Dock = DockStyle.Fill;
            // a tab shows what it was last generated with; changing a filter clears every tab (FiltersChanged), so a grid
            // can never hold rows of other dates than the boxes show (nor be exported under the new dates' file name)
            tabs.SelectedPageChanged += (s, e) => ShowHint();
            Controls.Add(tabs);
            Controls.Add(top);
        }

        private void AddTab(string caption, string proc, string filePrefix, string hint)
        {
            var page = new XtraTabPage { Text = caption };
            var grid = new GridControl { Dock = DockStyle.Fill };
            var view = new GridView();
            grid.MainView = view;
            grid.ViewCollection.Add(view);
            view.GridControl = grid;
            view.OptionsBehavior.Editable = false;
            // 2026-10-15 (user): the group panel is on, so users can drag a column (branch, series, payee, status ...) there
            // and read the report by group; every figure column has a per-group subtotal (FormatColumns)
            view.OptionsView.ShowGroupPanel = true;
            view.GroupPanelText = "Drag a column header here to group by it (e.g. Branch, Series, Customer, Payee, Status)";
            view.OptionsView.GroupFooterShowMode = DevExpress.XtraGrid.Views.Grid.GroupFooterShowMode.VisibleIfExpanded;
            view.OptionsView.ShowFooter = true;
            view.OptionsView.ColumnAutoWidth = false;
            view.OptionsSelection.EnableAppearanceFocusedCell = false;
            view.BestFitMaxRowCount = 500;   // a year of invoices is tens of thousands of rows
            Classes.DevXGridViewSettings.ApplyTotalsBandAppearance(view);
            view.RowStyle += View_RowStyle;
            page.Controls.Add(grid);
            tabs.TabPages.Add(page);
            _tabs[page] = new Tab { Page = page, Grid = grid, View = view, Proc = proc, FilePrefix = filePrefix, Hint = hint };
        }

        private Tab ActiveTab => tabs.SelectedTabPage != null && _tabs.TryGetValue(tabs.SelectedTabPage, out var t) ? t : null;

        private void FiltersChanged()
        {
            foreach (var t in _tabs.Values)
            {
                t.Stale = true;
                if (t.Grid.DataSource != null) t.Grid.DataSource = null;   // the columns and their formats stay
            }
            ShowHint();
        }

        private void ShowHint()
        {
            var t = ActiveTab;
            if (t == null) { lblHint.Text = ""; return; }
            lblHint.Text = t.Stale && _dataLoaded ? t.Hint + "   Press Generate for the dates and branch above." : t.Hint;
        }

        // ── data ─────────────────────────────────────────────────
        public void LoadData()
        {
            if (_dataLoaded) return;
            _dataLoaded = true;

            bool.TryParse(Login.isglobalAdmin, out bool isAdmin);
            bool.TryParse(Login.isglobalAccounting, out bool isAcctg);
            _allBranchesAllowed = isAdmin || isAcctg;

            // EWT payable is company-level (remittances, beginning and running balance are company-wide): admins and
            // accounting only; a branch user who may open the board page sees the two registers of their own branch
            if (!_allBranchesAllowed)
                foreach (var t in _tabs.Values)
                    if (t.Proc == "sp_rpt_EWTPayableLedger")
                        tabs.TabPages.Remove(t.Page);

            var branches = new DataTable();
            branches.Columns.Add("BranchCode", typeof(string));
            branches.Columns.Add("Display", typeof(string));
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("SELECT BranchCode, BranchName FROM dbo.Branches ORDER BY BranchCode", con))
                {
                    con.Open();
                    using (var rdr = cmd.ExecuteReader())
                        while (rdr.Read())
                        {
                            string code = rdr["BranchCode"].ToString();
                            if (_allBranchesAllowed || code == Login.assignedBranch)
                                branches.Rows.Add(code, code + " - " + rdr["BranchName"]);
                        }
                }
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show("Could not load the branches:\n" + ex.Message, "Registers", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            if (_allBranchesAllowed)
                branches.Rows.InsertAt(MakeRow(branches, AllBranches, "(All branches)"), 0);

            cboBranch.Properties.DataSource = branches;
            cboBranch.Properties.ValueMember = "BranchCode";
            cboBranch.Properties.DisplayMember = "Display";
            cboBranch.Properties.Columns.Clear();
            cboBranch.Properties.Columns.Add(new LookUpColumnInfo("Display", "Branch"));
            cboBranch.EditValue = _allBranchesAllowed ? AllBranches : Login.assignedBranch;
            cboBranch.Enabled = _allBranchesAllowed;

            DateTime today = DateTime.Today;
            dtFrom.DateTime = new DateTime(today.Year, today.Month, 1);
            dtTo.DateTime = today;
            FiltersChanged();
        }

        private static DataRow MakeRow(DataTable t, string code, string display)
        {
            var r = t.NewRow();
            r["BranchCode"] = code;
            r["Display"] = display;
            return r;
        }

        private void Generate(Tab t, bool userClick)
        {
            if (t == null) return;
            if (dtFrom.EditValue == null || dtTo.EditValue == null)
            {
                XtraMessageBox.Show("Pick the From and To dates.", "Registers", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            if (dtFrom.DateTime.Date > dtTo.DateTime.Date)
            {
                XtraMessageBox.Show("The From date is after the To date.", "Registers", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            string branch;
            if (_allBranchesAllowed)
            {
                branch = cboBranch.EditValue?.ToString();
                if (string.IsNullOrWhiteSpace(branch)) branch = AllBranches;
            }
            else
            {
                // never trust the box for a branch user; a blank branch would read as "all branches" in the procs
                branch = (Login.assignedBranch ?? "").Trim();
                if (branch.Length == 0)
                {
                    XtraMessageBox.Show("Your user has no branch assigned, so these registers can't be shown. Ask an administrator.",
                        "Registers", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
            }

            var table = new DataTable();
            Cursor = Cursors.WaitCursor;
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand(t.Proc, con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 180 })
                using (var da = new SqlDataAdapter(cmd))
                {
                    cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value = dtFrom.DateTime.Date;
                    cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value = dtTo.DateTime.Date;
                    cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 10).Value = branch;
                    con.Open();
                    da.Fill(table);
                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message, "Registers", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            finally
            {
                Cursor = Cursors.Default;
            }

            t.View.BeginUpdate();
            try
            {
                t.Grid.DataSource = table;
                if (t.View.Columns.Count == 0) t.View.PopulateColumns();
                if (!t.Formatted && t.View.Columns.Count > 0)
                {
                    FormatColumns(t);
                    t.Formatted = true;
                }
            }
            finally
            {
                t.View.EndUpdate();
            }
            t.View.BestFitColumns();
            CapWidth(t.View, "Particulars", 380);
            CapWidth(t.View, "Invoices", 260);
            CapWidth(t.View, "Note", 420);
            CapWidth(t.View, "Customer", 320);
            t.Stale = false;
            ShowHint();

            if (userClick && table.Rows.Count == 0)
                XtraMessageBox.Show("Nothing in this range.", "Registers", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private static void CapWidth(GridView v, string field, int max)
        {
            var c = v.Columns[field];
            if (c != null && c.Width > max) c.Width = max;
        }

        // ── formatting ───────────────────────────────────────────
        private static readonly string[] MoneyColumns =
            { "Amount", "AmountPaid", "Balance", "AmountReceived", "AppliedToInvoices", "EWT", "Discount",
              "Withheld", "Remitted", "Paid", "Unpaid", "RunningBalance" };

        private static readonly Dictionary<string, string> Captions = new Dictionary<string, string>
        {
            ["InvoiceNo"] = "Invoice No.", ["SeqNo"] = "No.", ["InvoiceDate"] = "Invoice Date", ["PONumber"] = "PO No.",
            ["AmountPaid"] = "Amount Paid", ["PayStatus"] = "Pay Status", ["DeliveryStatus"] = "Delivery Status",
            ["CRNo"] = "CR No.", ["PaymentDate"] = "Payment Date", ["ControlNo"] = "Control No.", ["ReferenceNo"] = "Reference No.",
            ["PaymentType"] = "Payment Type", ["AmountReceived"] = "Amount Received", ["AppliedToInvoices"] = "Applied to Invoices",
            ["TicketDate"] = "Date", ["TicketNumber"] = "Ticket No.", ["ReferenceNumber"] = "Reference No.",
            ["RunningBalance"] = "Balance (all branches)",
            // 2026-10-17 (user): on the Collection Receipt Register the customer's withholding is CWT (creditable
            // withholding tax); the proc column stays EWT. No other tab returns an EWT column.
            ["EWT"] = "CWT"
        };

        private static void FormatColumns(Tab t)
        {
            GridView v = t.View;
            foreach (GridColumn c in v.Columns)
            {
                if (Captions.TryGetValue(c.FieldName, out string cap)) c.Caption = cap;
                if (c.ColumnType == typeof(DateTime))
                {
                    c.DisplayFormat.FormatType = FormatType.DateTime;
                    c.DisplayFormat.FormatString = "yyyy-MM-dd";
                }
            }

            foreach (string f in MoneyColumns)
            {
                var c = v.Columns[f];
                if (c == null) continue;
                c.DisplayFormat.FormatType = FormatType.Numeric;
                c.DisplayFormat.FormatString = "N2";
                RightAlign(c);
                // a running balance is not summed
                if (f != "RunningBalance")
                {
                    c.Summary.Clear();
                    c.Summary.Add(SummaryItemType.Sum, f, "{0:N2}");
                    // per-group subtotal under the column (group footer) when the user groups the grid
                    v.GroupSummary.Add(new GridGroupSummaryItem(SummaryItemType.Sum, f, c, "{0:N2}"));
                }
            }

            var seq = v.Columns["SeqNo"];
            if (seq != null)
            {
                seq.DisplayFormat.FormatType = FormatType.Numeric;
                seq.DisplayFormat.FormatString = "0";
                RightAlign(seq);
            }

            // a row count on the document number column
            string countField = v.Columns["InvoiceNo"] != null ? "InvoiceNo" : v.Columns["CRNo"] != null ? "CRNo" : "Kind";
            var cc = v.Columns[countField];
            if (cc != null)
            {
                cc.Summary.Clear();
                cc.Summary.Add(SummaryItemType.Count, countField, countField == "Kind" ? "{0:N0} rows incl. beginning" : "{0:N0} rows");
                v.GroupSummary.Add(new GridGroupSummaryItem(SummaryItemType.Count, countField, null, "({0:N0} rows)"));   // in the group row
            }

            var note = v.Columns["Note"];
            if (note != null)
            {
                note.AppearanceCell.ForeColor = Color.FromArgb(150, 40, 20);
                note.AppearanceCell.Options.UseForeColor = true;
            }
        }

        private static void RightAlign(GridColumn c)
        {
            c.AppearanceCell.TextOptions.HAlignment = HorzAlignment.Far;
            c.AppearanceCell.Options.UseTextOptions = true;
            c.AppearanceHeader.TextOptions.HAlignment = HorzAlignment.Far;
            c.AppearanceHeader.Options.UseTextOptions = true;
        }

        // DUPLICATE: light red; GAP / JUMP: light amber; RETURNED / REVERSED: grey text.
        // EWT: PAID green, PARTIAL amber, REMITTANCE light blue, BEGINNING bold.
        // A coloured row always gets dark text (the Black skin's default text is light), and the focused / selected row is
        // left to the skin so the selection stays visible (the Bank Recon lesson of 2026-10-06).
        private static readonly Color DarkText = Color.FromArgb(30, 30, 30);

        private void View_RowStyle(object sender, RowStyleEventArgs e)
        {
            var v = (GridView)sender;
            if (e.RowHandle < 0 || e.RowHandle == v.FocusedRowHandle || v.IsRowSelected(e.RowHandle)) return;

            Color? back = null;
            bool grey = false;

            if (v.Columns["Note"] != null)
            {
                string note = Convert.ToString(v.GetRowCellValue(e.RowHandle, "Note"));
                if (string.IsNullOrEmpty(note)) return;
                if (note.Contains("DUPLICATE"))
                    back = Color.FromArgb(253, 222, 222);
                else if (note.Contains("GAP") || note.Contains("JUMP") || note.Contains("NO NUMBER") || note.Contains("NO CR NO"))
                    back = Color.FromArgb(255, 241, 204);
                else if (note.StartsWith("CANCELLED"))   // [110] a recorded cancelled CR: light lavender, grey text
                {
                    back = Color.FromArgb(236, 232, 246);
                    grey = true;
                }
                grey = grey || note.Contains("RETURNED") || note.Contains("REVERSED");
            }
            else if (v.Columns["Kind"] != null)
            {
                string kind = Convert.ToString(v.GetRowCellValue(e.RowHandle, "Kind"));
                string status = Convert.ToString(v.GetRowCellValue(e.RowHandle, "Status"));
                if (kind == "BEGINNING")
                    e.Appearance.Font = _bold ?? (_bold = new Font(v.Appearance.Row.GetFont(), FontStyle.Bold));   // one font, not one per paint
                else if (kind == "REMITTANCE")
                    back = Color.FromArgb(219, 234, 250);
                else if (status == "PAID")
                    back = Color.FromArgb(226, 239, 218);
                else if (status == "PARTIAL")
                    back = Color.FromArgb(255, 241, 204);
                else if (status == "REVERSED" || kind == "REVERSAL")
                    grey = true;
            }
            else return;

            if (back.HasValue)
            {
                e.Appearance.BackColor = back.Value;
                e.Appearance.ForeColor = grey ? Color.DimGray : DarkText;
            }
            else if (grey)
                e.Appearance.ForeColor = Color.Gray;
            e.HighPriority = true;
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) _bold?.Dispose();
            base.Dispose(disposing);
        }

        // ── export ───────────────────────────────────────────────
        private void ExportActive()
        {
            var t = ActiveTab;
            if (t == null || t.View.RowCount == 0)
            {
                XtraMessageBox.Show("Generate the report first.", "Registers", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            using (var dlg = new SaveFileDialog
            {
                Filter = "Excel workbook (*.xlsx)|*.xlsx",
                FileName = t.FilePrefix + "_" + dtFrom.DateTime.ToString("yyyyMMdd") + "_" + dtTo.DateTime.ToString("yyyyMMdd") + ".xlsx"
            })
            {
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                try
                {
                    t.View.ExportToXlsx(dlg.FileName);
                    if (XtraMessageBox.Show("Exported. Open it now?", "Registers", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
                        System.Diagnostics.Process.Start(dlg.FileName);
                }
                catch (Exception ex)
                {
                    XtraMessageBox.Show("Export failed:\n" + ex.Message, "Registers", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }
    }
}
