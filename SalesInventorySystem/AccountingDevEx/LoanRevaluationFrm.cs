using System;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraEditors.Controls;
using DevExpress.XtraGrid;
using DevExpress.XtraGrid.Views.Grid;
using DevExpress.XtraTab;

namespace SalesInventorySystem.AccountingDevEx
{
    /// <summary>
    /// Loan Revaluation (SQL/[65]-2026-10-12h_LoanRevaluation.sql; plan docs/plans/2026-10-12_PROFOOD_Loan_FX_Plan.md).
    /// Month-end revaluation of a foreign-currency loan (first: PROFOOD GMBH, EUR 800,000, GL 20203): the user enters the
    /// month-end rate; spu_Loan_PostRevaluation posts the difference (DR forex loss / CR liability, or DR liability / CR forex
    /// gain), dated the month end. Posted tab: the loan's history, its GL lines, and Reverse (latest revaluation only; this
    /// module has no Edit / Copy: a revaluation is corrected by reversing it and posting again).
    /// Built in code (no designer file). Accounting Settings menu, admins + accounting (Main.SetupLoanRevaluationMenu).
    /// </summary>
    // 2026-10-14 (user): a page of the Accounting Board (was a window opened from Accounting Settings), so an
    // XtraUserControl like the board's other screens.
    public class LoanRevaluationFrm : XtraUserControl
    {
        private readonly LookUpEdit cboLoan = new LookUpEdit();
        private readonly LabelControl lblLoanInfo = new LabelControl();
        private readonly LabelControl lblGLCheck = new LabelControl();
        private readonly XtraTabControl tabs = new XtraTabControl();
        private readonly XtraTabPage tabNew = new XtraTabPage { Text = "New Revaluation" };
        private readonly XtraTabPage tabPosted = new XtraTabPage { Text = "Posted" };

        private readonly DateEdit dtReval = new DateEdit();
        private readonly SpinEdit spnRate = new SpinEdit();
        // [81] 2026-10-14 (user): the foreign balance is an editable box (pre-filled with the loan's), plus a Control No.
        private readonly SpinEdit spnForeign = new SpinEdit();
        private readonly LabelControl lblForeignCap = Caption("Loan balance to revalue:");
        private readonly TextEdit txtControlNo = new TextEdit();
        private readonly TextEdit txtDescription = new TextEdit();
        private readonly LabelControl lblPreview = new LabelControl();
        // [105] 2026-10-17 (user): the automatic entry as a grid (it was lines of text in the preview)
        private readonly GridControl gridEntry = new GridControl();
        private readonly GridView viewEntry = new GridView();
        private readonly DataTable _entry = NewEntryTable();
        private readonly SimpleButton btnPost = new SimpleButton { Text = "Post Revaluation" };

        private readonly GridControl gridTxn = new GridControl();
        private readonly GridView viewTxn = new GridView();
        private readonly GridControl gridLines = new GridControl();
        private readonly GridView viewLines = new GridView();
        private readonly SimpleButton btnRefresh = new SimpleButton { Text = "Refresh" };
        private readonly SimpleButton btnReverse = new SimpleButton { Text = "Reverse Revaluation..." };

        private DataTable _loans;
        private bool _dataLoaded;
        private bool _quiet;           // true while the code itself changes editors (their events are ignored)
        private bool _bindingTxn;      // true while the history grid is rebound (one LoadLines at the end)
        private bool _txnSized, _linesSized;
        private bool _txnFormatted, _linesFormatted;   // the grid creates its columns on DataSource, so a column count can't tell

        public LoanRevaluationFrm()
        {
            Text = "Loan Revaluation";
            Size = new Size(1150, 740);
            BuildLayout();
            Load += (s, e) => LoadData();   // fallback only; the caller calls LoadData() (Known Bug Pattern #1)
            VisibleChanged += (s, e) => { if (Visible) SizeGrids(); };
        }

        // ── layout ───────────────────────────────────────────────
        private static LabelControl Caption(string text) =>
            new LabelControl { Text = text, Anchor = AnchorStyles.Left, AutoSizeMode = LabelAutoSizeMode.Default };

        private void BuildLayout()
        {
            // header: loan picker + its position + the GL tie check (rows sized for the taller WXI skin)
            var top = new TableLayoutPanel { Dock = DockStyle.Top, Height = 104, ColumnCount = 2, RowCount = 3, Padding = new Padding(8, 6, 8, 4) };
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 60));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            for (int i = 0; i < 3; i++) top.RowStyles.Add(new RowStyle(SizeType.Absolute, 31));
            cboLoan.Width = 440;
            cboLoan.Anchor = AnchorStyles.Left;
            cboLoan.Properties.TextEditStyle = TextEditStyles.DisableTextEditor;   // Known Bug Pattern #2
            cboLoan.Properties.NullText = "— select a loan —";
            cboLoan.EditValueChanged += (s, e) => OnLoanPicked();
            foreach (var l in new[] { lblLoanInfo, lblGLCheck })
            {
                l.AutoSizeMode = LabelAutoSizeMode.None;
                l.Dock = DockStyle.Fill;
                l.Appearance.TextOptions.VAlignment = DevExpress.Utils.VertAlignment.Center;
                l.Appearance.Options.UseTextOptions = true;
            }
            top.Controls.Add(Caption("Loan:"), 0, 0);
            top.Controls.Add(cboLoan, 1, 0);
            top.Controls.Add(lblLoanInfo, 0, 1); top.SetColumnSpan(lblLoanInfo, 2);
            top.Controls.Add(lblGLCheck, 0, 2); top.SetColumnSpan(lblGLCheck, 2);

            // New Revaluation tab: label / editor rows, the preview (fills), the Post button
            var form = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 7, Padding = new Padding(12, 10, 12, 10) };
            form.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 230));
            form.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            for (int i = 0; i < 5; i++) form.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));   // date, balance, rate, control no., description
            form.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            form.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));

            // [81] the balance to revalue: pre-filled with the loan's, editable (a principal payment lowers it)
            spnForeign.Width = 180;
            spnForeign.Anchor = AnchorStyles.Left;
            spnForeign.Properties.IsFloatValue = true;
            spnForeign.Properties.Increment = 0;
            spnForeign.Properties.MinValue = 0;
            spnForeign.Properties.MaxValue = 99999999999m;
            spnForeign.Properties.Mask.EditMask = "n2";
            spnForeign.Properties.Mask.UseMaskAsDisplayFormat = true;
            spnForeign.Properties.Buttons.Clear();
            spnForeign.Properties.Appearance.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
            spnForeign.Properties.Appearance.Options.UseTextOptions = true;
            spnForeign.EditValueChanged += (s, e) => { if (!_quiet) UpdatePreview(); };

            txtControlNo.Width = 220;
            txtControlNo.Anchor = AnchorStyles.Left;
            txtControlNo.Properties.MaxLength = 30;
            txtControlNo.Properties.CharacterCasing = CharacterCasing.Upper;
            txtControlNo.EditValueChanged += (s, e) => { if (!_quiet) UpdatePreview(); };

            dtReval.Width = 150;
            dtReval.Anchor = AnchorStyles.Left;
            dtReval.EditValueChanged += (s, e) => { if (!_quiet) { SnapToMonthEnd(); UpdatePreview(); } };

            spnRate.Width = 150;
            spnRate.Anchor = AnchorStyles.Left;
            spnRate.Properties.IsFloatValue = true;
            spnRate.Properties.Increment = 0;
            spnRate.Properties.MinValue = 0;
            spnRate.Properties.MaxValue = 100000;
            spnRate.Properties.Mask.EditMask = "n6";
            spnRate.Properties.Mask.UseMaskAsDisplayFormat = true;
            spnRate.Properties.Buttons.Clear();
            spnRate.Properties.Appearance.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
            spnRate.Properties.Appearance.Options.UseTextOptions = true;
            spnRate.EditValueChanged += (s, e) => { if (!_quiet) UpdatePreview(); };

            txtDescription.Anchor = AnchorStyles.Left | AnchorStyles.Right;
            txtDescription.Properties.MaxLength = 300;

            lblPreview.AutoSizeMode = LabelAutoSizeMode.Vertical;   // [105] grows with its lines (5-7 with a payable / control no.)
            lblPreview.Dock = DockStyle.Top;
            lblPreview.Padding = new Padding(0, 0, 0, 6);
            lblPreview.Appearance.Font = new Font("Tahoma", 9.75F);
            lblPreview.Appearance.Options.UseFont = true;
            lblPreview.Appearance.TextOptions.VAlignment = DevExpress.Utils.VertAlignment.Top;
            lblPreview.Appearance.TextOptions.WordWrap = DevExpress.Utils.WordWrap.Wrap;
            lblPreview.Appearance.Options.UseTextOptions = true;

            btnPost.Size = new Size(180, 36);
            btnPost.Anchor = AnchorStyles.Left;
            btnPost.Appearance.Font = new Font("Tahoma", 9F, FontStyle.Bold);
            btnPost.Appearance.Options.UseFont = true;
            btnPost.Click += (s, e) => PostRevaluation();

            form.Controls.Add(Caption("Revaluation date (month end):"), 0, 0);
            form.Controls.Add(dtReval, 1, 0);
            form.Controls.Add(lblForeignCap, 0, 1);
            form.Controls.Add(spnForeign, 1, 1);
            form.Controls.Add(Caption("Month-end rate (pesos per unit):"), 0, 2);
            form.Controls.Add(spnRate, 1, 2);
            form.Controls.Add(Caption("Control No.:"), 0, 3);
            form.Controls.Add(txtControlNo, 1, 3);
            form.Controls.Add(Caption("Description (blank = automatic):"), 0, 4);
            form.Controls.Add(txtDescription, 1, 4);
            // [105] the preview text on top, the entry it will post in a grid below it
            gridEntry.Dock = DockStyle.Fill;
            gridEntry.MinimumSize = new Size(0, 120);   // header, two lines and the totals always show
            gridEntry.MainView = viewEntry;
            gridEntry.ViewCollection.Add(viewEntry);
            viewEntry.GridControl = gridEntry;
            viewEntry.OptionsBehavior.Editable = false;
            viewEntry.OptionsView.ShowGroupPanel = false;
            viewEntry.OptionsView.ShowFooter = true;
            viewEntry.OptionsView.ShowIndicator = false;
            viewEntry.OptionsCustomization.AllowSort = false;
            viewEntry.OptionsCustomization.AllowGroup = false;
            Classes.DevXGridViewSettings.ApplyTotalsBandAppearance(viewEntry);
            // columns added explicitly: PopulateColumns makes none while the grid isn't on a shown form
            var cAcct = viewEntry.Columns.AddVisible("AccountCode", "Account");
            cAcct.Width = 110;
            var cName = viewEntry.Columns.AddVisible("AccountName", "Account Name");
            cName.Width = 360;
            foreach (var f in new[] { "Debit", "Credit" })
            {
                var c = viewEntry.Columns.AddVisible(f, f);
                c.Width = 170;
                c.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                c.DisplayFormat.FormatString = "N2";
                c.AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                c.AppearanceCell.Options.UseTextOptions = true;
                c.AppearanceHeader.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                c.AppearanceHeader.Options.UseTextOptions = true;
                c.Summary.Add(DevExpress.Data.SummaryItemType.Sum, f, "{0:N2}");
            }
            gridEntry.DataSource = _entry;
            var previewPanel = new PanelControl { Dock = DockStyle.Fill, BorderStyle = DevExpress.XtraEditors.Controls.BorderStyles.NoBorder };
            previewPanel.Controls.Add(gridEntry);    // Fill first (it docks last), then the Top text
            previewPanel.Controls.Add(lblPreview);
            form.Controls.Add(previewPanel, 0, 5); form.SetColumnSpan(previewPanel, 2);
            form.Controls.Add(btnPost, 0, 6);
            tabNew.Controls.Add(form);

            // Posted tab: history on top, its GL lines below
            var bar = new PanelControl { Dock = DockStyle.Top, Height = 44 };
            btnRefresh.Location = new Point(8, 7);
            btnRefresh.Size = new Size(100, 30);
            btnRefresh.Click += (s, e) => RefreshAll();
            btnReverse.Location = new Point(116, 7);
            btnReverse.Size = new Size(180, 30);
            btnReverse.Click += (s, e) => ReverseSelected();
            bar.Controls.AddRange(new Control[] { btnRefresh, btnReverse });

            var split = new SplitContainerControl { Dock = DockStyle.Fill, Horizontal = false, ShowCaption = false };
            gridTxn.Dock = DockStyle.Fill;
            gridTxn.MainView = viewTxn;
            gridTxn.ViewCollection.Add(viewTxn);
            viewTxn.GridControl = gridTxn;
            gridLines.Dock = DockStyle.Fill;
            gridLines.MainView = viewLines;
            gridLines.ViewCollection.Add(viewLines);
            viewLines.GridControl = gridLines;
            foreach (var v in new[] { viewTxn, viewLines })
            {
                v.OptionsBehavior.Editable = false;
                v.OptionsView.ShowGroupPanel = false;
                v.OptionsView.ShowFooter = true;
                Classes.DevXGridViewSettings.ApplyTotalsBandAppearance(v);
            }
            viewTxn.FocusedRowChanged += (s, e) => { if (!_bindingTxn) LoadLines(); };
            viewTxn.RowCellStyle += (s, e) =>
            {
                if (Convert.ToString(viewTxn.GetRowCellValue(e.RowHandle, "Status")) == "REVERSED")
                    e.Appearance.ForeColor = Color.Gray;
            };
            split.Panel1.Controls.Add(gridTxn);
            split.Panel2.Controls.Add(gridLines);
            tabPosted.Controls.Add(split);
            tabPosted.Controls.Add(bar);
            Classes.DevXGridViewSettings.KeepSplitterRatio(split, 0.6);

            tabs.Dock = DockStyle.Fill;
            tabs.TabPages.AddRange(new[] { tabNew, tabPosted });
            tabs.SelectedPageChanged += (s, e) => { if (e.Page == tabPosted) SizeGrids(); };
            Controls.Add(tabs);
            Controls.Add(top);
        }

        // ── data ─────────────────────────────────────────────────
        public void LoadData()
        {
            if (_dataLoaded) return;
            _dataLoaded = true;
            RefreshAll();
        }

        private static DataTable Fetch(string proc, Action<SqlCommand> parms = null)
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand(proc, con) { CommandType = CommandType.StoredProcedure })
            {
                parms?.Invoke(cmd);
                var dt = new DataTable();
                con.Open();
                new SqlDataAdapter(cmd).Fill(dt);
                return dt;
            }
        }

        private static decimal Dec(object v) => v == null || v == DBNull.Value ? 0m : Convert.ToDecimal(v);

        // The selected loan is kept here, not read back from the dropdown: while its window is being created the LookUpEdit
        // can report a transient empty EditValue (seen on a cold first start: it cleared the whole screen). The dropdown's
        // text editor is disabled, so a user can never blank it; an empty value is put back instead of acted on.
        private int? _loanId;
        private int? SelectedLoanID => _loanId;

        private void OnLoanPicked()
        {
            if (_quiet) return;
            var v = cboLoan.EditValue;
            if (v == null || v == DBNull.Value)
            {
                if (_loanId != null)
                {
                    _quiet = true;
                    try { cboLoan.EditValue = _loanId; }
                    finally { _quiet = false; }
                }
                return;
            }
            int id = Convert.ToInt32(v);
            if (id == _loanId) return;
            _loanId = id;
            ShowLoan();
        }

        private DataRow SelectedLoan
        {
            get
            {
                if (_loans == null || SelectedLoanID == null) return null;
                foreach (DataRow r in _loans.Rows)
                    if (Convert.ToInt32(r["LoanID"]) == SelectedLoanID.Value) return r;
                return null;
            }
        }

        // a loan can be revalued only once it has a position (an opening entry)
        private static bool HasPosition(DataRow r) => r != null && r["LastTxnDate"] != DBNull.Value && r["LastRate"] != DBNull.Value;

        // reload the loans (keeps the selection), the Posted grid and the preview
        private void RefreshAll()
        {
            try
            {
                int? keep = SelectedLoanID;
                _loans = Fetch("sp_Loan_GetAccounts");
                _quiet = true;
                try
                {
                    cboLoan.Properties.DataSource = _loans;
                    cboLoan.Properties.DisplayMember = "DisplayText";
                    cboLoan.Properties.ValueMember = "LoanID";
                    cboLoan.Properties.Columns.Clear();
                    cboLoan.Properties.Columns.Add(new LookUpColumnInfo("DisplayText", "Loan"));
                    cboLoan.Properties.Columns.Add(new LookUpColumnInfo("Currency", "Currency"));
                    bool keepExists = false;
                    if (keep != null)
                        foreach (DataRow row in _loans.Rows)
                            if (Convert.ToInt32(row["LoanID"]) == keep.Value) { keepExists = true; break; }
                    _loanId = keepExists ? keep : (_loans.Rows.Count > 0 ? (int?)Convert.ToInt32(_loans.Rows[0]["LoanID"]) : null);
                    cboLoan.EditValue = _loanId;
                }
                finally { _quiet = false; }
                ShowLoan();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show($"Could not load the loans: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void ShowLoan()
        {
            var r = SelectedLoan;
            btnPost.Enabled = HasPosition(r);
            _entry.Rows.Clear();   // [105]
            if (r == null)
            {
                lblLoanInfo.Text = lblGLCheck.Text = lblPreview.Text = "";
                gridTxn.DataSource = gridLines.DataSource = null;
                return;
            }
            if (!HasPosition(r))
            {
                lblLoanInfo.Text = $"{r["DisplayText"]}: no opening balance yet — it can't be revalued.";
                lblGLCheck.Text = lblPreview.Text = "";
                LoadTransactions();
                return;
            }
            decimal php = Dec(r["PhpBalance"]), gl = Dec(r["GLBalance"]);
            lblLoanInfo.Text = $"{r["Currency"]} {Dec(r["ForeignBalance"]):N2}   ·   last rate {Dec(r["LastRate"]):0.0000##} " +
                               $"({Convert.ToDateTime(r["LastTxnDate"]):MM/dd/yyyy}, {r["LastTxnType"]})   ·   peso balance {php:N2}   ·   " +
                               $"branch {r["BranchCode"]} - {r["BranchName"]}   ·   {r["LiabilityAccount"]} - {r["LiabilityAccountName"]}";
            bool ties = php == gl;
            lblGLCheck.Text = ties ? $"GL {r["LiabilityAccount"]} on branch {r["BranchCode"]}: {gl:N2} (same as the loan)"
                                   : $"GL {r["LiabilityAccount"]} on branch {r["BranchCode"]}: {gl:N2} — differs from the loan by {gl - php:N2}: a principal payment (type the loan's new balance) or something else was posted to that account";
            // [105] the payable must equal the GL (the post refuses otherwise, 62030)
            bool payTies = true;
            if (HasPayable(r))
            {
                decimal pay = Dec(r["PayableBalance"]);
                payTies = pay == gl;
                lblGLCheck.Text += payTies
                    ? $"   ·   payable {r["PayableInvoiceNo"]} {pay:N2} (paid so far {Dec(r["PayableAmountPaid"]):N2})"
                    : $"   ·   payable {r["PayableInvoiceNo"]} {pay:N2} does NOT equal GL: a payment outside Vouchering Telegraphic? (posting is refused until it is sorted out)";
            }
            lblGLCheck.Appearance.ForeColor = ties && payTies ? Color.SeaGreen : Color.Firebrick;
            lblGLCheck.Appearance.Options.UseForeColor = true;

            // next month end after the last entry, and a fresh entry
            _quiet = true;
            try
            {
                dtReval.DateTime = MonthEnd(Convert.ToDateTime(r["LastTxnDate"]).AddDays(1));
                spnRate.EditValue = null;
                spnForeign.EditValue = Dec(r["ForeignBalance"]);   // [81] pre-filled, editable
                lblForeignCap.Text = $"Loan balance to revalue ({r["Currency"]}):";
                txtControlNo.Text = "";
                txtDescription.Text = "";
            }
            finally { _quiet = false; }
            UpdatePreview();
            LoadTransactions();
        }

        private static DateTime MonthEnd(DateTime d) => new DateTime(d.Year, d.Month, DateTime.DaysInMonth(d.Year, d.Month));

        private bool HasDate => dtReval.EditValue != null && dtReval.EditValue != DBNull.Value && dtReval.DateTime.Year > 1900;

        private void SnapToMonthEnd()
        {
            if (!HasDate) return;
            var me = MonthEnd(dtReval.DateTime);
            if (dtReval.DateTime.Date == me) return;
            _quiet = true;
            try { dtReval.DateTime = me; }
            finally { _quiet = false; }
        }

        // [81] the typed balance to revalue (null = blank or 0)
        private decimal? Foreign
        {
            get
            {
                if (spnForeign.EditValue == null || spnForeign.EditValue == DBNull.Value) return null;
                decimal v = Math.Round(spnForeign.Value, 2);
                return v > 0 ? v : (decimal?)null;
            }
        }

        private decimal? Rate
        {
            get
            {
                if (spnRate.EditValue == null || spnRate.EditValue == DBNull.Value) return null;
                decimal v = spnRate.Value;
                return v > 0 ? v : (decimal?)null;
            }
        }

        private static DataTable NewEntryTable()
        {
            var t = new DataTable("Entry");
            t.Columns.Add("AccountCode", typeof(string));
            t.Columns.Add("AccountName", typeof(string));
            t.Columns.Add("Debit", typeof(decimal));
            t.Columns.Add("Credit", typeof(decimal));
            return t;
        }

        // [105] the loan's payable in Vouchering Telegraphic (columns only where [105] is installed)
        private static bool HasPayable(DataRow r) =>
            r != null && r.Table.Columns.Contains("PayableBalance") && r["PayableBalance"] != DBNull.Value;

        // what the post will do, before it is done
        private void UpdatePreview()
        {
            var r = SelectedLoan;
            lblPreview.Appearance.Options.UseForeColor = false;
            _entry.Rows.Clear();
            if (!HasPosition(r)) { lblPreview.Text = ""; return; }
            if (!HasDate) { lblPreview.Text = "Pick the revaluation date (a month end)."; return; }
            if (Rate == null) { lblPreview.Text = "Enter the month-end rate to see the entry."; return; }
            if (Foreign == null) { lblPreview.Text = "Enter the loan balance to revalue (greater than 0)."; return; }
            decimal recBal = Dec(r["ForeignBalance"]), fBal = Foreign.Value, php = Dec(r["PhpBalance"]);
            decimal lastRate = Dec(r["LastRate"]), rate = Rate.Value;
            // [81] a changed balance (principal payment) is measured against GL, which already holds the payment (same as the proc)
            bool principalChanged = fBal != recBal;
            decimal basis = principalChanged ? Dec(r["GLBalance"]) : php;
            // same rounding as the proc: T-SQL ROUND(@fBal * @Rate, 2) rounds half away from zero
            decimal newBal = Math.Round(fBal * rate, 2, MidpointRounding.AwayFromZero), change = newBal - basis;
            // [105] the entry goes to the grid: loss = DR forex loss / CR loan; gain = DR loan / CR forex gain
            if (change > 0)
            {
                _entry.Rows.Add(r["LossAccount"], r["LossAccountName"], change, 0m);
                _entry.Rows.Add(r["LiabilityAccount"], r["LiabilityAccountName"], 0m, change);
            }
            else if (change < 0)
            {
                _entry.Rows.Add(r["LiabilityAccount"], r["LiabilityAccountName"], -change, 0m);
                _entry.Rows.Add(r["GainAccount"], r["GainAccountName"], 0m, -change);
            }
            string payable = "";
            bool payableTies = true;
            if (HasPayable(r))
            {
                decimal pBal = Dec(r["PayableBalance"]);
                payableTies = pBal == Dec(r["GLBalance"]);
                payable = payableTies
                    ? $"Loan payable {r["PayableInvoiceNo"]} (Vouchering Telegraphic): Actual Cost and Balance {pBal:N2} → {pBal + change:N2}\n"
                    : $"Loan payable {r["PayableInvoiceNo"]} shows {pBal:N2} but GL is {Dec(r["GLBalance"]):N2}: posting is refused until that is sorted out.\n";
            }
            btnPost.Enabled = payableTies;
            lblPreview.Text =
                $"{r["Currency"]} {fBal:N2} × {rate:0.0000##} = new peso balance {newBal:N2}   (was {php:N2} at {lastRate:0.0000##}; rate change {rate - lastRate:+0.0000##;-0.0000##;0})\n" +
                (principalChanged
                    ? $"Balance changed from {r["Currency"]} {recBal:N2} ({fBal - recBal:+#,##0.00;-#,##0.00}): the entry is measured against GL {r["LiabilityAccount"]} = {basis:N2}, " +
                      "which must already hold the principal payment.\n"
                    : "") +
                (string.IsNullOrWhiteSpace(txtControlNo.Text) ? "" : $"Control No. {txtControlNo.Text.Trim()}\n") + payable +
                (change == 0 ? "No change: nothing to post at this rate." :
                 $"{(change > 0 ? "Forex LOSS" : "Forex GAIN")} {Math.Abs(change):N2}, dated {dtReval.DateTime:MM/dd/yyyy}, branch {r["BranchCode"]}: the entry below.");
            if (change != 0 || !payableTies)
            {
                lblPreview.Appearance.ForeColor = !payableTies || change > 0 ? Color.Firebrick : Color.SeaGreen;
                lblPreview.Appearance.Options.UseForeColor = true;
            }
        }

        // ── post ─────────────────────────────────────────────────
        private void PostRevaluation()
        {
            var r = SelectedLoan;
            if (!HasPosition(r)) return;
            if (!HasDate)
            {
                XtraMessageBox.Show("Pick the revaluation date (a month end).", "Missing Date", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                dtReval.Focus();
                return;
            }
            if (Rate == null)
            {
                XtraMessageBox.Show("Enter the month-end rate.", "Missing Rate", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                spnRate.Focus();
                return;
            }
            if (Foreign == null)
            {
                XtraMessageBox.Show("Enter the loan balance to revalue (greater than 0).", "Missing Balance", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                spnForeign.Focus();
                return;
            }
            if (_entry.Rows.Count == 0)   // [105] no change at this rate (or the preview isn't complete): nothing to post
            {
                XtraMessageBox.Show(string.IsNullOrWhiteSpace(lblPreview.Text) ? "Nothing to post." : lblPreview.Text, "Loan Revaluation",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            string lines = "";   // [105] the entry is in the grid now; the confirmation repeats it
            foreach (DataRow e in _entry.Rows)
                lines += $"\n   {(Dec(e["Debit"]) > 0 ? "DR" : "CR")} {e["AccountCode"]} - {e["AccountName"]}   {Math.Max(Dec(e["Debit"]), Dec(e["Credit"])):N2}";
            if (XtraMessageBox.Show($"Post this revaluation?\n\n{lblPreview.Text}{lines}", "Confirm Revaluation",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;

            btnPost.Enabled = false;
            try
            {
                var dt = Fetch("spu_Loan_PostRevaluation", cmd =>
                {
                    cmd.Parameters.Add("@LoanID", SqlDbType.Int).Value = Convert.ToInt32(r["LoanID"]);
                    cmd.Parameters.Add("@RevalDate", SqlDbType.Date).Value = dtReval.DateTime.Date;
                    var p = cmd.Parameters.Add("@Rate", SqlDbType.Decimal); p.Precision = 18; p.Scale = 6; p.Value = Rate.Value;
                    var q = cmd.Parameters.Add("@ExpectedPhpBalance", SqlDbType.Decimal); q.Precision = 18; q.Scale = 2; q.Value = Dec(r["PhpBalance"]);
                    cmd.Parameters.Add("@User", SqlDbType.VarChar, 60).Value = Login.Fullname ?? "";
                    cmd.Parameters.Add("@Description", SqlDbType.VarChar, 300).Value =
                        string.IsNullOrWhiteSpace(txtDescription.Text) ? (object)DBNull.Value : txtDescription.Text.Trim();
                    // [81] needs SQL [81] (the proc's two new parameters)
                    var f = cmd.Parameters.Add("@ForeignBalance", SqlDbType.Decimal); f.Precision = 18; f.Scale = 2; f.Value = Foreign.Value;
                    cmd.Parameters.Add("@ControlNo", SqlDbType.VarChar, 30).Value =
                        string.IsNullOrWhiteSpace(txtControlNo.Text) ? (object)DBNull.Value : txtControlNo.Text.Trim();
                });
                string msg = dt.Rows.Count > 0 ? Convert.ToString(dt.Rows[0]["Message"]) : "Revaluation posted.";
                XtraMessageBox.Show(msg, "Posted", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message, "Revaluation Not Posted", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            RefreshAll();   // fresh balance, next month end, empty rate (Known Bug Pattern #6: reset after save)
        }

        // ── posted ───────────────────────────────────────────────
        private void LoadTransactions()
        {
            var id = SelectedLoanID;
            if (id == null) { gridTxn.DataSource = null; return; }
            try
            {
                var dt = Fetch("sp_Loan_GetTransactions", cmd => cmd.Parameters.Add("@LoanID", SqlDbType.Int).Value = id.Value);
                _bindingTxn = true;
                try
                {
                    gridTxn.DataSource = dt;
                    if (!_txnFormatted) { FormatTxnColumns(); _txnFormatted = true; }
                    if (viewTxn.RowCount > 0) viewTxn.FocusedRowHandle = viewTxn.RowCount - 1;
                }
                finally { _bindingTxn = false; }
                LoadLines();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show($"Could not load the loan's history: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private static void Num(GridView v, string col, string fmt, bool sum)
        {
            var c = v.Columns[col];
            if (c == null) return;
            c.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            c.DisplayFormat.FormatString = fmt;
            c.AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;     // figures right-aligned
            c.AppearanceCell.Options.UseTextOptions = true;
            c.AppearanceHeader.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
            c.AppearanceHeader.Options.UseTextOptions = true;
            if (sum && c.Summary.Count == 0) c.Summary.Add(DevExpress.Data.SummaryItemType.Sum, col, "{0:" + fmt + "}");
        }

        private void FormatTxnColumns()
        {
            Num(viewTxn, "PrevRate", "#,##0.0000##", false);
            Num(viewTxn, "Rate", "#,##0.0000##", false);
            Num(viewTxn, "RateChange", "+0.0000##;-0.0000##;0", false);
            Num(viewTxn, "ForeignChange", "N2", false);
            Num(viewTxn, "PhpChange", "N2", false);
            Num(viewTxn, "ForeignBalance", "N2", false);
            Num(viewTxn, "PhpBalance", "N2", false);
            foreach (var hide in new[] { "TxnID", "ReversedBy", "ReversedAt", "ReverseReason" })
                if (viewTxn.Columns[hide] != null) viewTxn.Columns[hide].Visible = false;
            if (viewTxn.Columns["ControlNo"] != null)   // [81] next to the reference no.
            {
                viewTxn.Columns["ControlNo"].Caption = "Control No";
                if (viewTxn.Columns["ReferenceNumber"] != null)
                    viewTxn.Columns["ControlNo"].VisibleIndex = viewTxn.Columns["ReferenceNumber"].VisibleIndex;
            }
            if (viewTxn.Columns["TxnDate"] != null)
            {
                viewTxn.Columns["TxnDate"].DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                viewTxn.Columns["TxnDate"].DisplayFormat.FormatString = "MM/dd/yyyy";
            }
        }

        private void FormatLineColumns()
        {
            Num(viewLines, "Debit", "N2", true);
            Num(viewLines, "Credit", "N2", true);
            foreach (var hide in new[] { "AccountCode", "AccountName" })   // shown together as Account (Code - Name)
                if (viewLines.Columns[hide] != null) viewLines.Columns[hide].Visible = false;
            if (viewLines.Columns["TicketDate"] != null)
            {
                viewLines.Columns["TicketDate"].DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                viewLines.Columns["TicketDate"].DisplayFormat.FormatString = "MM/dd/yyyy";
            }
        }

        // best-fit only once the grids are on screen (a hidden tab page has no real sizes yet)
        private void SizeGrids()
        {
            if (!tabPosted.Visible && tabs.SelectedTabPage != tabPosted) return;
            if (!_txnSized && viewTxn.Columns.Count > 0)
            {
                viewTxn.BestFitColumns();
                if (viewTxn.Columns["Description"] != null && viewTxn.Columns["Description"].Width > 320) viewTxn.Columns["Description"].Width = 320;
                _txnSized = true;
            }
            if (!_linesSized && viewLines.Columns.Count > 0)
            {
                viewLines.BestFitColumns();
                _linesSized = true;
            }
        }

        private int? FocusedTxnID => viewTxn.FocusedRowHandle >= 0 ? (int?)Convert.ToInt32(viewTxn.GetFocusedRowCellValue("TxnID")) : null;

        private void LoadLines()
        {
            var txn = FocusedTxnID;
            string type = viewTxn.FocusedRowHandle >= 0 ? Convert.ToString(viewTxn.GetFocusedRowCellValue("TxnType")) : "";
            string status = viewTxn.FocusedRowHandle >= 0 ? Convert.ToString(viewTxn.GetFocusedRowCellValue("Status")) : "";
            btnReverse.Enabled = txn != null && type == "REVALUATION" && status == "POSTED";
            if (txn == null) { gridLines.DataSource = null; return; }
            try
            {
                var dt = Fetch("sp_Loan_GetTicketLines", cmd => cmd.Parameters.Add("@TxnID", SqlDbType.Int).Value = txn.Value);
                if (dt.Columns.Contains("AccountCode") && dt.Columns.Contains("AccountName") && !dt.Columns.Contains("Account"))
                {
                    var acc = dt.Columns.Add("Account", typeof(string), "AccountCode + ' - ' + ISNULL(AccountName, '')");
                    acc.SetOrdinal(dt.Columns["AccountCode"].Ordinal);
                }
                gridLines.DataSource = dt;
                if (!_linesFormatted) { FormatLineColumns(); _linesFormatted = true; }
                SizeGrids();
            }
            catch (Exception ex)
            {
                gridLines.DataSource = null;
                XtraMessageBox.Show($"Could not load the GL lines: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void ReverseSelected()
        {
            var txn = FocusedTxnID;
            if (txn == null) return;
            string desc = Convert.ToString(viewTxn.GetFocusedRowCellValue("Description"));
            string reason = XtraInputBox.Show($"Reverse this revaluation?\n{desc}\n\nOnly the latest revaluation of the loan can be reversed. Reason:",
                "Reverse Revaluation", "");
            if (string.IsNullOrWhiteSpace(reason)) return;
            try
            {
                var dt = Fetch("spu_Loan_ReverseRevaluation", cmd =>
                {
                    cmd.Parameters.Add("@TxnID", SqlDbType.Int).Value = txn.Value;
                    cmd.Parameters.Add("@User", SqlDbType.VarChar, 60).Value = Login.Fullname ?? "";
                    cmd.Parameters.Add("@Reason", SqlDbType.VarChar, 300).Value = reason.Trim();
                });
                XtraMessageBox.Show(dt.Rows.Count > 0 ? Convert.ToString(dt.Rows[0]["Message"]) : "Revaluation reversed.",
                    "Reversed", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message, "Not Reversed", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            RefreshAll();
        }
    }
}
