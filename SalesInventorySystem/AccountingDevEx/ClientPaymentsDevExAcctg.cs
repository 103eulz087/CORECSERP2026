using System;
using System.Collections.Generic;
using System.Data;
using System.Drawing;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using System.Data.SqlClient;
using DevExpress.XtraGrid.Views.Grid;
using DevExpress.XtraGrid.Columns;
using SalesInventorySystem.Classes;
using DevExpress.XtraEditors.Repository;
using SalesInventorySystem.HOFormsDevEx;

namespace SalesInventorySystem.AccountingDevEx
{
    public partial class ClientPaymentsDevExAcctg : UserControl
    {
        object objcustid, objcustname;
        bool isglobalSales = false, isglobalCharge = false;
        string paymenttype = "", custkey = "", refno;
        int lasttransseqno;
        RepositoryItemCheckEdit chkPay;

        public ClientPaymentsDevExAcctg()
        {
            InitializeComponent();

            chkPay = new RepositoryItemCheckEdit();
            chkPay.ValueChecked = true;
            chkPay.ValueUnchecked = false;
            chkPay.AllowGrayed = false;

            gridControl2.RepositoryItems.Add(chkPay);

            // Uniform "totals band" styling across the app's report/grid footers -- same
            // reference appearance as POS/POSSalesReportDevEx.cs's SalesTransactionSummary tab.
            // See DevXGridViewSettings.ApplyTotalsBandAppearance and CLAUDE.md's "Grid footer/
            // totals band styling" convention.
            Classes.DevXGridViewSettings.ApplyTotalsBandAppearance(gridView2);
            Classes.DevXGridViewSettings.ApplyTotalsBandAppearance(gridViewPaymentDetails);

            BuildEntryTabs();   // [104] Invoices / Other Collections
            BuildCancelledCRButton();   // [110] cancelled CRs
        }

        // ── CANCELLED CR ([110], 2026-10-18) ────────────────────────────
        // Like "Cancelled Cheque…" on Supplier Payment: a collection receipt that was spoiled / misprinted / damaged /
        // lost / voided and never used for a payment is recorded with its reason (dbo.spu_RecordCancelledCR). It posts
        // nothing; the Collection Receipt Register lists it in its series (CANCELLED, no GAP). The button opens the list
        // (sp_GetCancelledCRs) with New… / Edit… (spu_EditCancelledCR, old / new values logged). A CR already used by a
        // payment is reversed instead.
        private SimpleButton btnCancelledCR;

        private void BuildCancelledCRButton()
        {
            btnCancelledCR = new SimpleButton
            {
                Name = "btnCancelledCR",
                Text = "Cancelled CR…",
                Location = new Point(346, 207),
                Size = new Size(130, 30),
                ToolTip = "Record a spoiled / misprinted / lost collection receipt with its reason. No payment, no GL entry."
            };
            btnCancelledCR.Click += BtnCancelledCR_Click;
            groupBox1.Controls.Add(btnCancelledCR);
            btnCancelledCR.BringToFront();
        }

        private static DataTable FetchTable(string sql, Action<SqlCommand> addParams = null, CommandType type = CommandType.Text)
        {
            var dt = new DataTable();
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand(sql, con) { CommandType = type })
            using (var da = new SqlDataAdapter(cmd))
            {
                addParams?.Invoke(cmd);
                da.Fill(dt);
            }
            return dt;
        }

        private void BtnCancelledCR_Click(object sender, EventArgs e)
        {
            DataTable branches;
            try
            {
                branches = FetchTable("SELECT BranchCode, BranchCode + ' - ' + ISNULL(BranchName, '') AS DisplayText FROM dbo.Branches ORDER BY BranchCode");
                // a database without [110]: say so instead of opening a list that can't load
                if (FetchTable("SELECT OBJECT_ID('dbo.sp_GetCancelledCRs', 'P') AS Id").Rows[0]["Id"] == DBNull.Value)
                {
                    XtraMessageBox.Show("Cancelled CR needs script [110] on this database. Ask the administrator to install it.",
                        "Cancelled CR", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
            }
            catch (Exception ex) { XtraMessageBox.Show(ex.Message, "Cancelled CR", MessageBoxButtons.OK, MessageBoxIcon.Error); return; }

            using (var dlg = new XtraForm
            {
                Text = "Cancelled CRs",
                StartPosition = FormStartPosition.CenterParent,
                MinimizeBox = false,
                ShowInTaskbar = false,
                ClientSize = new Size(980, 480),
                MinimumSize = new Size(700, 360)
            })
            {
                var top = new PanelControl { Dock = DockStyle.Top, Height = 44 };
                var lblFrom = new LabelControl { Text = "CR date from", Location = new Point(10, 14) };
                var dtFrom = new DateEdit { Location = new Point(90, 10), Width = 110 };
                var lblTo = new LabelControl { Text = "to", Location = new Point(209, 14) };
                var dtTo = new DateEdit { Location = new Point(227, 10), Width = 110 };
                var today = DateTime.Today;
                dtFrom.EditValue = new DateTime(today.Year, today.Month, 1).AddMonths(-2);
                dtTo.EditValue = today;
                var btnShow = new SimpleButton { Text = "Show", Location = new Point(347, 8), Size = new Size(70, 26) };
                top.Controls.AddRange(new Control[] { lblFrom, dtFrom, lblTo, dtTo, btnShow });

                var bottom = new PanelControl { Dock = DockStyle.Bottom, Height = 44 };
                var btnNew = new SimpleButton { Text = "New…", Location = new Point(10, 8), Size = new Size(90, 28) };
                var btnEdit = new SimpleButton { Text = "Edit…", Location = new Point(106, 8), Size = new Size(90, 28) };
                var btnClose = new SimpleButton { Text = "Close", Size = new Size(90, 28), DialogResult = DialogResult.Cancel,
                                                  Anchor = AnchorStyles.Top | AnchorStyles.Right };
                btnClose.Location = new Point(bottom.Width - 100, 8);
                bottom.Controls.AddRange(new Control[] { btnNew, btnEdit, btnClose });

                var grid = new DevExpress.XtraGrid.GridControl { Dock = DockStyle.Fill };
                var view = new GridView(grid);
                grid.MainView = view;
                view.OptionsBehavior.Editable = false;
                view.OptionsView.ShowGroupPanel = false;
                view.OptionsSelection.EnableAppearanceFocusedCell = false;
                view.BestFitMaxRowCount = 500;

                Action load = () =>
                {
                    try
                    {
                        var dt = FetchTable("dbo.sp_GetCancelledCRs", cmd =>
                        {
                            cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value = dtFrom.EditValue is DateTime f ? (object)f.Date : DBNull.Value;
                            cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value = dtTo.EditValue is DateTime t ? (object)t.Date : DBNull.Value;
                        }, CommandType.StoredProcedure);
                        grid.DataSource = dt;
                        view.PopulateColumns();
                        foreach (string hide in new[] { "CancelledCRID", "BranchCode" })
                            if (view.Columns[hide] != null) view.Columns[hide].Visible = false;
                        var captions = new Dictionary<string, string>
                        {
                            { "CRNo", "CR No." }, { "CRDate", "CR Date" }, { "RecordedBy", "Recorded By" }, { "RecordedAt", "Recorded" },
                            { "ModifiedBy", "Last Edited By" }, { "ModifiedAt", "Last Edited" }
                        };
                        foreach (var kv in captions)
                            if (view.Columns[kv.Key] != null) view.Columns[kv.Key].Caption = kv.Value;
                        if (view.Columns["CRDate"] != null)
                        {
                            view.Columns["CRDate"].DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                            view.Columns["CRDate"].DisplayFormat.FormatString = "yyyy-MM-dd";
                        }
                        foreach (var dc in new[] { "RecordedAt", "ModifiedAt" })
                            if (view.Columns[dc] != null)
                            {
                                view.Columns[dc].DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                                view.Columns[dc].DisplayFormat.FormatString = "yyyy-MM-dd HH:mm";
                            }
                        if (view.Columns["Edits"] != null)
                        {
                            view.Columns["Edits"].AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                            view.Columns["Edits"].AppearanceCell.Options.UseTextOptions = true;
                            view.Columns["Edits"].AppearanceHeader.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                            view.Columns["Edits"].AppearanceHeader.Options.UseTextOptions = true;
                        }
                        view.BestFitColumns();
                        if (view.Columns["Remarks"] != null && view.Columns["Remarks"].Width > 320) view.Columns["Remarks"].Width = 320;
                        btnEdit.Enabled = dt.Rows.Count > 0;
                    }
                    catch (Exception ex) { XtraMessageBox.Show(ex.Message, "Cancelled CRs", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
                };
                Action edit = () =>
                {
                    var row = view.GetFocusedDataRow();
                    if (row == null) { XtraMessageBox.Show("Select a cancelled CR first.", "Cancelled CRs", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
                    if (ShowCancelledCREntry(branches, row)) load();
                };

                btnShow.Click += (s, a) => load();
                btnNew.Click += (s, a) => { if (ShowCancelledCREntry(branches, null)) load(); };
                btnEdit.Click += (s, a) => edit();
                view.DoubleClick += (s, a) =>
                {
                    var hit = view.CalcHitInfo(grid.PointToClient(Control.MousePosition));
                    if (hit.InRow) edit();
                };

                dlg.Controls.Add(grid);
                dlg.Controls.Add(top);
                dlg.Controls.Add(bottom);
                grid.BringToFront();
                dlg.CancelButton = btnClose;
                dlg.Shown += (s, a) => load();   // the grid gets its columns once the window is on screen
                dlg.ShowDialog(this);
            }
        }

        // The entry window: new (existing == null) or a correction of a recorded cancelled CR. True when saved.
        private bool ShowCancelledCREntry(DataTable branches, DataRow existing)
        {
            bool isEdit = existing != null;
            using (var dlg = new XtraForm
            {
                Text = isEdit ? "Edit Cancelled CR" : "Record Cancelled CR",
                FormBorderStyle = FormBorderStyle.FixedDialog,
                StartPosition = FormStartPosition.CenterParent,
                MaximizeBox = false,
                MinimizeBox = false,
                ShowInTaskbar = false,
                ClientSize = new Size(470, 330)
            })
            {
                var info = new LabelControl
                {
                    Text = isEdit
                        ? "Correct the details of this cancelled CR (typos). It stays a cancelled CR:\n" +
                          "no payment, no GL entry. The old and new values are kept in the edit log."
                        : "For a collection receipt that was spoiled, misprinted, damaged or lost and never used\n" +
                          "for a payment. It is listed as CANCELLED in the Collection Receipt Register.\n" +
                          "A CR already used by a payment is reversed instead (Edit / reverse the payment).",
                    Location = new Point(14, 10),
                    AutoSizeMode = LabelAutoSizeMode.Vertical,
                    Width = 442
                };
                var lblBranch = new LabelControl { Text = "Branch", Location = new Point(14, 76) };
                var cboBranch = new LookUpEdit { Location = new Point(120, 72), Width = 336 };
                cboBranch.Properties.DataSource = branches;
                cboBranch.Properties.ValueMember = "BranchCode";
                cboBranch.Properties.DisplayMember = "DisplayText";
                cboBranch.Properties.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;   // Known Bug #2
                cboBranch.Properties.ShowHeader = false;
                cboBranch.Properties.Columns.Add(new DevExpress.XtraEditors.Controls.LookUpColumnInfo("DisplayText", "Branch"));
                cboBranch.Properties.NullText = "";

                var lblNo = new LabelControl { Text = "CR no.", Location = new Point(14, 108) };
                var txtNo = new TextEdit { Location = new Point(120, 104), Width = 200 };
                txtNo.Properties.MaxLength = 20;
                txtNo.Properties.CharacterCasing = CharacterCasing.Upper;
                var lblDate = new LabelControl { Text = "CR date", Location = new Point(14, 140) };
                var dtDate = new DateEdit { Location = new Point(120, 136), Width = 160 };
                dtDate.Properties.MaxValue = DateTime.Today;
                dtDate.EditValue = DateTime.Today;

                var lblReason = new LabelControl { Text = "Reason", Location = new Point(14, 172) };
                var cboReason = new ComboBoxEdit { Location = new Point(120, 168), Width = 200 };
                cboReason.Properties.Items.AddRange(new object[] { "SPOILED", "MISPRINTED", "DAMAGED", "LOST", "WRONG ENTRY", "VOIDED", "OTHER" });
                cboReason.Properties.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;
                cboReason.SelectedIndex = 0;

                var lblRemarks = new LabelControl { Text = "Remarks", Location = new Point(14, 204) };
                var memo = new MemoEdit { Location = new Point(120, 200), Size = new Size(336, 70) };
                memo.Properties.MaxLength = 1000;

                var btnSave = new SimpleButton { Text = isEdit ? "Save" : "Record", Location = new Point(270, 288), Size = new Size(90, 28) };
                var btnClose = new SimpleButton { Text = "Close", Location = new Point(366, 288), Size = new Size(90, 28), DialogResult = DialogResult.Cancel };

                if (isEdit)
                {
                    cboBranch.EditValue = Convert.ToString(existing["BranchCode"]);
                    txtNo.Text = Convert.ToString(existing["CRNo"]).Trim();
                    dtDate.EditValue = existing["CRDate"] is DateTime ed ? ed : (object)DateTime.Today;
                    string r0 = Convert.ToString(existing["Reason"]).Trim();
                    if (r0.Length > 0 && !cboReason.Properties.Items.Contains(r0)) cboReason.Properties.Items.Add(r0);
                    cboReason.EditValue = r0.Length > 0 ? r0 : "SPOILED";
                    memo.Text = Convert.ToString(existing["Remarks"]);
                }
                else
                {
                    // start on the CR booklet's branch: the picked customer's, else the user's own; and the CR no. typed
                    // on the payment, if any
                    string branch = null;
                    try { branch = CustomerBranch(txtcustid.Text); }
                    catch (Exception) { branch = null; }
                    if (string.IsNullOrWhiteSpace(branch)) branch = Login.assignedBranch;
                    foreach (DataRow r in branches.Rows)
                        if (string.Equals(Convert.ToString(r["BranchCode"]).Trim(), (branch ?? "").Trim(), StringComparison.OrdinalIgnoreCase))
                        { cboBranch.EditValue = Convert.ToString(r["BranchCode"]); break; }
                    txtNo.Text = txtcrno.Text.Trim().ToUpperInvariant();
                }

                btnSave.Click += (s, a) =>
                {
                    string branch = cboBranch.EditValue?.ToString();
                    string no = txtNo.Text.Trim();
                    if (string.IsNullOrWhiteSpace(branch)) { XtraMessageBox.Show("Select the branch whose CR booklet it is.", dlg.Text, MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
                    if (no.Length == 0) { XtraMessageBox.Show("Enter the CR number.", dlg.Text, MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
                    if (!(dtDate.EditValue is DateTime date)) { XtraMessageBox.Show("Enter the CR date.", dlg.Text, MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
                    string reason = cboReason.Text.Trim();
                    if (reason.Length == 0) { XtraMessageBox.Show("Select the reason.", dlg.Text, MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }

                    string ask = isEdit
                        ? $"Save the corrected details of this cancelled CR?\n\nCR {no}, {cboBranch.Text}, {date:yyyy-MM-dd} ({reason})."
                        : $"Record CR {no} of {cboBranch.Text} as CANCELLED ({reason}), dated {date:yyyy-MM-dd}?\n\n" +
                          "It can't be used for a payment afterwards.";
                    if (XtraMessageBox.Show(ask, dlg.Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                        return;

                    try
                    {
                        string message = isEdit ? "Cancelled CR updated." : "Cancelled CR recorded.";
                        using (var con = Database.getConnection())
                        using (var cmd = new SqlCommand(isEdit ? "dbo.spu_EditCancelledCR" : "dbo.spu_RecordCancelledCR", con) { CommandType = CommandType.StoredProcedure })
                        {
                            if (isEdit)
                                cmd.Parameters.Add("@CancelledCRID", SqlDbType.Int).Value = Convert.ToInt32(existing["CancelledCRID"]);
                            cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 10).Value = branch;
                            cmd.Parameters.Add("@CRNo", SqlDbType.VarChar, 20).Value = no;
                            cmd.Parameters.Add("@CRDate", SqlDbType.Date).Value = date.Date;
                            cmd.Parameters.Add("@Reason", SqlDbType.VarChar, 100).Value = reason;
                            cmd.Parameters.Add("@Remarks", SqlDbType.VarChar, 1000).Value = memo.Text.Trim();
                            cmd.Parameters.Add("@User", SqlDbType.VarChar, 50).Value = Login.Fullname ?? "";
                            con.Open();
                            using (var rdr = cmd.ExecuteReader())
                                if (rdr.Read()) message = rdr["Message"]?.ToString() ?? message;
                        }
                        XtraMessageBox.Show(message, dlg.Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
                        dlg.DialogResult = DialogResult.OK;
                    }
                    catch (Exception ex)
                    {
                        XtraMessageBox.Show(ex.Message, dlg.Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    }
                };

                dlg.Controls.AddRange(new Control[] { info, lblBranch, cboBranch, lblNo, txtNo, lblDate, dtDate, lblReason, cboReason, lblRemarks, memo, btnSave, btnClose });
                dlg.CancelButton = btnClose;
                return dlg.ShowDialog(this) == DialogResult.OK;
            }
        }

        // [110] before posting: a CR no. recorded as cancelled at the customer's branch can't be used. Null = free (or a
        // database without [110]: nothing to check there).
        // The CR booklet's branch = the customer's (Customers.BranchCode by CustomerKey, the key this screen posts;
        // CustomerID differs from it on a few customers)
        private static string CustomerBranch(string custKey)
        {
            if (string.IsNullOrWhiteSpace(custKey)) return null;
            DataTable t = FetchTable("SELECT TOP (1) BranchCode FROM dbo.Customers WHERE CustomerKey = @key",
                                     cmd => cmd.Parameters.Add("@key", SqlDbType.VarChar, 20).Value = custKey.Trim());
            return t.Rows.Count == 0 ? null : Convert.ToString(t.Rows[0]["BranchCode"]).Trim();
        }

        private string FindCancelledCR(string custKey, string crNo)
        {
            if (string.IsNullOrWhiteSpace(crNo) || string.IsNullOrWhiteSpace(custKey)) return null;
            string branch = CustomerBranch(custKey);
            if (string.IsNullOrWhiteSpace(branch)) return null;   // no such customer: the payment itself is refused later
            DataTable t;
            try
            {
                t = FetchTable("dbo.sp_FindCancelledCR", cmd =>
                {
                    cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 10).Value = branch.Trim();
                    cmd.Parameters.Add("@CRNo", SqlDbType.VarChar, 20).Value = crNo.Trim();
                }, CommandType.StoredProcedure);
            }
            catch (SqlException ex) when (ex.Number == 2812) { return null; }   // proc not installed ([110] missing)
            if (t.Rows.Count == 0) return null;
            DataRow r = t.Rows[0];
            return $"CR no. {r["CRNo"]} of branch {r["BranchCode"]} was recorded as CANCELLED on " +
                   $"{Convert.ToDateTime(r["CRDate"]):yyyy-MM-dd} ({r["Reason"]}, by {r["RecordedBy"]}).";
        }

        // ── OTHER COLLECTIONS ([104], 2026-10-17) ───────────────────────
        // The entry grid sits in two tabs: Invoices (the customer's invoices and balance-forward credits, as before)
        // and Other Collections: free lines, each an account from the accountant's list (JournalEntryMapping
        // OR-OTHERCOLL) + amount + remarks, for money that settles no invoice (a long-term debt paid in parts, or
        // balance-forward credits that were really interest: tick the credit, put the same amount to Other Income).
        // They post in the same payment (same control no. / CR no. / GL entry / deposit) as an ARPaymentDetails line
        // PaymentType 'OTHER COLLECTION', PONumber '#OTHER'; sp_AddPaymentClient re-checks every rule (92020-92024).
        const string OtherPaymentType = "OTHER COLLECTION";
        const string OtherPONumber = "#OTHER";
        private const string OtherAccountsSql =
            "SELECT M.AccountCode, C.Description, M.AccountCode + ' - ' + C.Description AS Display " +
            "FROM dbo.JournalEntryMapping M INNER JOIN dbo.ChartOfAccounts C ON C.AccountCode = M.AccountCode " +
            "WHERE M.Origin = 'OR' AND M.Mnemonic = 'OR-OTHERCOLL' AND M.IsActive = 1 ORDER BY M.Seq, M.AccountCode";

        DevExpress.XtraTab.XtraTabControl tabEntry;
        DevExpress.XtraTab.XtraTabPage pageInvoices, pageOther;
        DevExpress.XtraGrid.GridControl gridOther;
        GridView viewOther;
        RepositoryItemSearchLookUpEdit repOtherAccount;
        LabelControl lblOtherHint;
        readonly DataTable otherLines = NewOtherLinesTable();
        DataTable otherAccounts = new DataTable();

        static DataTable NewOtherLinesTable()
        {
            var t = new DataTable("OtherCollections");
            t.Columns.Add("AccountCode", typeof(string));
            t.Columns.Add("Amount", typeof(decimal));
            t.Columns.Add("Remarks", typeof(string));
            return t;
        }

        void BuildEntryTabs()
        {
            tabEntry = new DevExpress.XtraTab.XtraTabControl { Dock = DockStyle.Fill };
            pageInvoices = tabEntry.TabPages.Add("Invoices");
            pageOther = tabEntry.TabPages.Add("Other Collections");

            groupBox2.Controls.Remove(gridControl2);
            pageInvoices.Controls.Add(gridControl2);

            repOtherAccount = new RepositoryItemSearchLookUpEdit
            {
                ValueMember = "AccountCode",
                DisplayMember = "Display",
                NullText = "",
                TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor   // Known Bug #2 / #14
            };
            // popup: Code and Name only (the bound list also carries the Display text the cell shows)
            repOtherAccount.View.Columns.AddVisible("AccountCode", "Code");
            repOtherAccount.View.Columns.AddVisible("Description", "Account");
            var repAmount = new RepositoryItemSpinEdit { IsFloatValue = true, MinValue = 0m, MaxValue = 999999999999m, Increment = 0m };
            repAmount.Buttons.Clear();
            repAmount.Mask.EditMask = "n2";
            repAmount.Mask.UseMaskAsDisplayFormat = true;
            repAmount.Appearance.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
            repAmount.Appearance.Options.UseTextOptions = true;
            var repRemarks = new RepositoryItemTextEdit { MaxLength = 50 };

            gridOther = new DevExpress.XtraGrid.GridControl { Dock = DockStyle.Fill };
            viewOther = new GridView(gridOther);
            gridOther.MainView = viewOther;
            gridOther.RepositoryItems.AddRange(new DevExpress.XtraEditors.Repository.RepositoryItem[] { repOtherAccount, repAmount, repRemarks });

            // columns added explicitly: PopulateColumns makes none while the grid isn't on a shown form (work-log gotcha)
            var colAccount = viewOther.Columns.AddVisible("AccountCode", "Account");
            colAccount.ColumnEdit = repOtherAccount;
            colAccount.Width = 320;
            var colAmount = viewOther.Columns.AddVisible("Amount", "Amount");
            colAmount.ColumnEdit = repAmount;
            colAmount.Width = 160;
            colAmount.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            colAmount.DisplayFormat.FormatString = "N2";
            colAmount.AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
            colAmount.AppearanceCell.Options.UseTextOptions = true;
            colAmount.AppearanceHeader.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
            colAmount.AppearanceHeader.Options.UseTextOptions = true;
            colAmount.Summary.Add(DevExpress.Data.SummaryItemType.Sum, "Amount", "{0:N2}");
            var colRemarks = viewOther.Columns.AddVisible("Remarks", "Remarks");
            colRemarks.ColumnEdit = repRemarks;
            colRemarks.Width = 420;

            viewOther.OptionsView.ShowGroupPanel = false;
            viewOther.OptionsView.ShowFooter = true;
            viewOther.OptionsView.NewItemRowPosition = NewItemRowPosition.Bottom;
            viewOther.OptionsBehavior.EditorShowMode = DevExpress.Utils.EditorShowMode.Click;
            viewOther.OptionsCustomization.AllowGroup = false;
            Classes.DevXGridViewSettings.ApplyTotalsBandAppearance(viewOther);
            // the total follows the table itself: a line typed on the new-item row only reaches it when the row is committed
            otherLines.RowChanged += (s, e) => ComputeTotal();
            otherLines.RowDeleted += (s, e) => ComputeTotal();
            otherLines.TableCleared += (s, e) => ComputeTotal();
            viewOther.ValidatingEditor += ViewOther_ValidatingEditor;
            viewOther.KeyDown += (s, e) =>
            {
                if (e.KeyCode == Keys.Delete && viewOther.ActiveEditor == null)
                {
                    RemoveFocusedOtherLine();
                    e.Handled = true;
                }
            };
            gridOther.DataSource = otherLines;
            // leaving the tab commits the line being typed (the credit is ticked on the Invoices tab and needs it)
            tabEntry.SelectedPageChanging += (s, e) => CommitOtherLines();

            var top = new PanelControl { Dock = DockStyle.Top, Height = 42 };
            lblOtherHint = new LabelControl
            {
                Text = "Money that settles no invoice: pick the account, type the amount. It posts with this payment (same control no. / CR no.). " +
                       "To close a balance-forward credit to income, add the line here first, then tick the credit on the Invoices tab.",
                Dock = DockStyle.Fill,
                AutoSizeMode = LabelAutoSizeMode.None,
                Padding = new Padding(6, 4, 6, 0)
            };
            lblOtherHint.Appearance.TextOptions.WordWrap = DevExpress.Utils.WordWrap.Wrap;
            lblOtherHint.Appearance.Options.UseTextOptions = true;
            var btnRemove = new SimpleButton { Text = "Remove Line", Width = 110, Dock = DockStyle.Right };
            btnRemove.Click += (s, e) => RemoveFocusedOtherLine();
            top.Controls.Add(lblOtherHint);   // Fill first, then the Right button
            top.Controls.Add(btnRemove);
            pageOther.Controls.Add(gridOther);   // Fill first (it docks last), then the Top panel
            pageOther.Controls.Add(top);

            groupBox2.Controls.Add(tabEntry);
        }

        // the accountant's list; empty on a database without [104] (the tab then says so and takes no lines)
        void BindOtherAccounts(DataTable accounts)
        {
            otherAccounts = accounts ?? new DataTable();
            repOtherAccount.DataSource = otherAccounts;
            bool available = otherAccounts.Rows.Count > 0;
            viewOther.OptionsBehavior.Editable = available;
            viewOther.OptionsView.NewItemRowPosition = available ? NewItemRowPosition.Bottom : NewItemRowPosition.None;
            if (!available)
                lblOtherHint.Text = "Other Collections are not available on this database yet (database update [104]); ask the administrator.";
        }

        private void ViewOther_ValidatingEditor(object sender, DevExpress.XtraEditors.Controls.BaseContainerValidateEditorEventArgs e)
        {
            if (viewOther.FocusedColumn?.FieldName != "Amount" || e.Value == null || e.Value == DBNull.Value) return;
            if (!decimal.TryParse(e.Value.ToString(), out decimal v) || v <= 0)
            {
                e.Valid = false;
                e.ErrorText = "Enter the amount received (more than 0).";
            }
        }

        // the lines with anything in them (the empty new-item row and blank rows are left out)
        IEnumerable<DataRow> OtherLineRows()
        {
            foreach (DataRow r in otherLines.Rows)
            {
                if (r.RowState == DataRowState.Deleted) continue;
                bool blank = string.IsNullOrWhiteSpace(r["AccountCode"]?.ToString())
                             && (r["Amount"] == DBNull.Value || Convert.ToDecimal(r["Amount"]) == 0m)
                             && string.IsNullOrWhiteSpace(r["Remarks"]?.ToString());
                if (!blank) yield return r;
            }
        }

        double OtherTotal()
        {
            double total = 0;
            foreach (DataRow r in OtherLineRows())
                if (r["Amount"] != DBNull.Value) total += Convert.ToDouble(r["Amount"]);
            return Math.Round(total, 2);
        }

        string OtherAccountDescription(string code)
        {
            foreach (DataRow a in otherAccounts.Rows)
                if (string.Equals(a["AccountCode"]?.ToString(), code, StringComparison.OrdinalIgnoreCase))
                    return a["Description"]?.ToString() ?? "";
            return null;   // not on the list (any more)
        }

        void ClearOtherLines()
        {
            viewOther?.CancelUpdateCurrentRow();
            otherLines.Rows.Clear();
        }

        // commits the cell being edited and the new-item row into otherLines (its RowChanged recomputes the total)
        void CommitOtherLines()
        {
            if (viewOther == null) return;
            viewOther.CloseEditor();
            viewOther.UpdateCurrentRow();
        }

        void RemoveFocusedOtherLine()
        {
            int h = viewOther.FocusedRowHandle;
            if (h < 0) return;   // nothing focused, or the new-item row
            string acct = viewOther.GetRowCellDisplayText(h, "AccountCode");
            if (!HelperFunction.ConfirmDialog($"Remove the Other Collections line {acct} ({viewOther.GetRowCellDisplayText(h, "Amount")})?", "Remove Line"))
                return;
            viewOther.DeleteRow(h);
        }

        // ── LOAD ────────────────────────────────────────────────────────
        private void ClientPaymentsDevExAcctg_Load(object sender, EventArgs e)
        {
            custkey = txtcustid.Text;
            groupControl1.Text = custkey;
            // 2026-10-12 (user: the screen took a second+ to open): the customer list (10,731 rows, about 2.8 s
            // over the network) now fills in the background while the screen is already usable, and the 7
            // account lookups below share one query instead of running it 7 times.
            populateCustnameInBackground();
            DataTable coa = null, others = null;
            try
            {
                var lists = Database.FetchTables(new Dictionary<string, string> { ["coa"] = CoaDebitSql, ["oc"] = OtherAccountsSql });   // [104] one round trip
                coa = lists["coa"];
                others = lists["oc"];
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show("Failed to load dropdown data: " + ex.Message, "Database Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            if (coa != null)
            {
                populateRepositorySearchLookUp(coa);
                populateCOA(coa);
            }
            BindOtherAccounts(others);
            display();
            RefreshAvailableCredit();

            Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "InvoiceAmount");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "Balance");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "AmountPaid");
            //Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "AdvancePayment");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "OverPay");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "OverPayIncome");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "EWTAmount");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "DiscountAmount");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "OffsetAmount");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "ServicesAmount");

            // NEW: ShowFooterTotal above only formats the footer sum, not the row
            // cells above it (CLAUDE.md's "Reporting Quantity/Amount columns must
            // be numeric" convention) -- splist_ARAccounts returns all of these as
            // real decimal(12,2) columns, but the grid rendered them unformatted.
            Classes.DevXGridViewSettings.FormatNumericColumns(gridView2,
                "InvoiceAmount", "Balance", "AmountPaid", "OverPay", "OverPayIncome",
                "EWTAmount", "DiscountAmount", "OffsetAmount", "ServicesAmount");

            gridView2.OptionsBehavior.EditorShowMode = DevExpress.Utils.EditorShowMode.MouseDown;
            gridView2.OptionsBehavior.ImmediateUpdateRowPosition = true;
            gridView2.Columns["Pay"].ColumnEdit = chkPay;
            gridView2.Columns["Pay"].OptionsColumn.AllowEdit = true;
            gridView2.Columns["Pay"].OptionsColumn.ReadOnly = false;
            gridView2.CloseEditor();
            gridView2.UpdateCurrentRow();

            gridView9.RowCellStyle += gridView9_RowCellStyle;
            xtraTabControl1.SelectedPageChanged += XtraTabControl1_SelectedPageChanged;
            gridView9.FocusedRowChanged += GridView9_FocusedRowChanged;
        }

        // Clears the details grid on focus change rather than auto-loading it -
        // View Details stays an explicit action (per how this was asked for),
        // but leaving a previous row's GL entries on screen while a different
        // row is focused would misleadingly look like they belong to it.
        private void GridView9_FocusedRowChanged(object sender, DevExpress.XtraGrid.Views.Base.FocusedRowChangedEventArgs e)
        {
            gridControlPaymentDetails.DataSource = null;
        }

        // Lazy-load, same as AddExpenseDevExFrm's Posted Expenses tab -
        // only queries when the user actually switches to FullyPaid Invoice.
        private void XtraTabControl1_SelectedPageChanged(object sender, DevExpress.XtraTab.TabPageChangedEventArgs e)
        {
            if (xtraTabControl1.SelectedTabPage == xtraTabPage2)
                LoadPostedClientPayments();
        }


        // 2026-10-12: the customer list is fetched on a background thread (DB only, Known Bug #8) and bound
        // on the UI thread when it arrives; until then the dropdown is disabled and says so.
        void populateCustnameInBackground()
        {
            txtcustname.Enabled = false;
            txtcustname.Properties.NullText = "Loading customers…";
            const string sql = "SELECT BranchName,CustomerKey,CustomerName FROM view_Customers";
            System.Threading.Tasks.Task.Run(() => Database.FetchTables(new Dictionary<string, string> { ["c"] = sql })["c"])
                .ContinueWith(t =>
                {
                    if (IsDisposed || txtcustname.IsDisposed) return;
                    txtcustname.Properties.NullText = "";
                    txtcustname.Enabled = true;
                    if (t.IsFaulted)
                    {
                        var ex = t.Exception.GetBaseException();
                        XtraMessageBox.Show("Failed to load the customer list: " + ex.Message, "Database Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        return;
                    }
                    // same binding as Database.displaySearchlookupEdit (ValueMember CustomerKey, 2026-10-10)
                    txtcustname.Properties.View.Columns.Clear();
                    txtcustname.Properties.DataSource = null;
                    txtcustname.Properties.DataSource = t.Result;
                    txtcustname.Properties.DisplayMember = "CustomerName";
                    txtcustname.Properties.ValueMember = "CustomerKey";
                }, System.Threading.Tasks.TaskScheduler.FromCurrentSynchronizationContext());
        }

        void populateCustname()
        {
            // 2026-10-10: ValueMember = CustomerKey (unique). It was CustomerName, which 938 customers share
            // (e.g. DAQUIZ, ARNOLD at 009 and at 001): picking the second one didn't change the value, so the
            // first customer stayed. The name is still what the box shows.
            Database.displaySearchlookupEdit("SELECT BranchName,CustomerKey,CustomerName FROM view_Customers", txtcustname, "CustomerName", "CustomerKey");
        }

        // ── AVAILABLE CREDIT (unapplied OverPay balance) ───────────────────
        // See SQL/2026-09-23_CustomerOverpaymentCredit.sql -- OverPay now
        // credits a real liability account (20115) instead of Other Income,
        // and this surfaces the running balance so the user knows there's
        // credit to apply via OffsetAmount before typing a payment in blind.
        void RefreshAvailableCredit()
        {
            if (string.IsNullOrWhiteSpace(custkey))
            {
                lblAvailableCredit.Text = "0.00";
                return;
            }

            try
            {
                using (SqlConnection con = Database.getConnection())
                using (SqlCommand cmd = new SqlCommand("sp_GetCustomerAvailableCredit", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@CustomerKey", SqlDbType.Char, 8).Value = custkey;

                    con.Open();
                    object result = cmd.ExecuteScalar();
                    decimal credit = (result == null || result == DBNull.Value) ? 0m : Convert.ToDecimal(result);
                    lblAvailableCredit.Text = credit.ToString("N2");
                    lblAvailableCredit.ForeColor = credit > 0 ? Color.DarkGreen : Color.Gray;
                }
            }
            catch (Exception ex)
            {
                // Non-critical display field -- a failed lookup (SqlException,
                // or a bad cast if the SP ever returns something unexpected)
                // shouldn't block the rest of Load/EditValueChanged/ResetEntry.
                System.Diagnostics.Debug.WriteLine("RefreshAvailableCredit failed: " + ex.Message);
                lblAvailableCredit.Text = "N/A";
            }
        }
        // ── DISPLAY ─────────────────────────────────────────────────────
        void display()
        {
            using (SqlConnection con = Database.getConnection())
            using (SqlCommand com = new SqlCommand("splist_ARAccounts", con))
            {
                com.CommandType = CommandType.StoredProcedure;
                com.Parameters.Add("@parmcustkey", SqlDbType.VarChar).Value = txtcustid.Text;
                // [79] 2026-10-14: also list the open balance-forward credits (InvoiceType 'BF CREDIT', negative Balance)
                com.Parameters.Add("@IncludeCredits", SqlDbType.Bit).Value = true;

                DataTable table = new DataTable();
                con.Open();
                using (SqlDataReader dr = com.ExecuteReader())
                    table.Load(dr);

                // Unlock editable columns (SP returns them as read-only by default)
                //string[] editableColumns = { "Pay", "AmountPaid", "EWTAmount", "DiscountAmount", "OffsetAmount", "AdvancePayment" };
                string[] editableColumns = { "Pay", "AmountPaid", "EWTAmount", "DiscountAmount", "OffsetAmount", "OverPay", "OverPayIncome", "ServicesAmount" };
                foreach (string col in editableColumns)
                    if (table.Columns.Contains(col))
                        table.Columns[col].ReadOnly = false;

                gridControl2.DataSource = null;
                gridControl2.DataSource = table;
            }

            gridView2.OptionsBehavior.Editable = true;
            gridView2.OptionsBehavior.ReadOnly = false;
            gridView2.OptionsBehavior.EditorShowMode = DevExpress.Utils.EditorShowMode.Click;

            foreach (GridColumn col in gridView2.Columns)
            {
                col.OptionsColumn.AllowEdit = true;
                col.OptionsColumn.ReadOnly = false;
            }

            gridView2.Columns["Pay"].ColumnEdit = chkPay;
            // 2026-10-16 (user): captions only; the field names (and what each posts) are unchanged
            if (gridView2.Columns["OverPay"] != null) gridView2.Columns["OverPay"].Caption = "Overpay(Credits)";
            if (gridView2.Columns["OverPayIncome"] != null) gridView2.Columns["OverPayIncome"].Caption = "Overpay(OtherIncome)";
            gridView2.BestFitColumns();
        }

        // ── PAYMENT TYPE PANEL VISIBILITY ────────────────────────────────
        // [CLEAN] Single method drives all radio states — no duplication.
        void ApplyPaymentTypeVisibility()
        {
            groupCheque.Visible = radioButton2.Checked;
            panelOnline.Visible = radioButton3.Checked; 
            groupCreditCardDetails.Visible = radCreditCard.Checked;

            //if (radioButton4.Checked)
            //    txtacctbalance.Text = Math.Round(
            //        Convert.ToDouble(Database.getSingleQuery(
            //            "ClientSavingsAccounts", "AccountKey='" + txtcustid.Text + "'", "AccountBalance")), 2
            //    ).ToString();
        }

        private void radioButton1_CheckedChanged(object sender, EventArgs e) => ApplyPaymentTypeVisibility();
        private void radioButton2_CheckedChanged(object sender, EventArgs e) => ApplyPaymentTypeVisibility();
        private void radioButton3_CheckedChanged(object sender, EventArgs e) => ApplyPaymentTypeVisibility();
        private void radioButton4_CheckedChanged(object sender, EventArgs e) => ApplyPaymentTypeVisibility();
        private void radCreditCard_CheckedChanged(object sender, EventArgs e) => ApplyPaymentTypeVisibility();

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            switch (keyData)
            {
                case Keys.F1: radioButton1.Checked = true; break;
                case Keys.F2: radioButton2.Checked = true; break;
                case Keys.F3: radioButton3.Checked = true; break;
              
                case Keys.F5: radCreditCard.Checked = true; break;
                default: return base.ProcessCmdKey(ref msg, keyData);
            }
            return true;
        }

        // ── COA LOOKUPS ─────────────────────────────────────────────────
        // 2026-10-12: one query for all 7 account lookups (it used to run once per lookup)
        private const string CoaDebitSql = "SELECT AccountCode, Description FROM ChartOfAccounts WHERE AccountType='D'";

        void populateCOA(DataTable coa)
        {
            // same binding as Database.displaySearchlookupEdit, one copy of the list each
            foreach (var edit in new[] { txtdebitglcode, txtcreditglcode })
            {
                edit.Properties.View.Columns.Clear();
                edit.Properties.DataSource = null;
                edit.Properties.DataSource = coa.Copy();
                edit.Properties.DisplayMember = "AccountCode";
                edit.Properties.ValueMember = "AccountCode";
            }
        }

        void populateRepositorySearchLookUp(DataTable coa)
        {
            // same binding as Database.displayRepositorySearchlookupEdit, one copy of the list each
            foreach (var rep in new[] { repositoryItemSearchLookUpEditglcode, repositoryItemSearchLookUpEditOffsetGLCode,
                                        repositoryItemSearchLookUpEditOffsetCreditGLCode, repositoryItemSearchLookUpEditEWTDebitGLCode,
                                        repositoryItemSearchLookUpEditEWTCreditGLCode })
            {
                rep.DataSource = coa.Copy();
                rep.DisplayMember = "AccountCode";
                rep.ValueMember = "AccountCode";
            }
        }

        // ── GRID EVENTS ─────────────────────────────────────────────────
        private void gridView2_CellValueChanging(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            if (e.Column.FieldName == "Pay")
                gridView2.PostEditor();
        }

        private void gridView2_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            int row = e.RowHandle;
            if (row < 0) return;

            if (e.Column.FieldName == "Pay" && IsCreditRow(row))
            {
                ApplyCreditTick(row, Convert.ToBoolean(e.Value));
                ComputeTotal();
                return;
            }

            if (e.Column.FieldName == "Pay")
            {
                bool isPay = Convert.ToBoolean(e.Value);
                if (isPay)
                {
                    double balance = Convert.ToDouble(gridView2.GetRowCellValue(row, "Balance") ?? 0);
                    // Default: full balance, no deductions
                    gridView2.SetRowCellValue(row, "EWTAmount", 0);
                    gridView2.SetRowCellValue(row, "DiscountAmount", 0);
                    gridView2.SetRowCellValue(row, "OffsetAmount", 0);
                    gridView2.SetRowCellValue(row, "OverPay", 0);
                    gridView2.SetRowCellValue(row, "OverPayIncome", 0);
                    gridView2.SetRowCellValue(row, "ServicesAmount", 0);
                    gridView2.SetRowCellValue(row, "AmountPaid", balance);
                }
                else
                {
                    gridView2.SetRowCellValue(row, "EWTAmount", 0);
                    gridView2.SetRowCellValue(row, "DiscountAmount", 0);
                    gridView2.SetRowCellValue(row, "OffsetAmount", 0);
                    gridView2.SetRowCellValue(row, "OverPay", 0);
                    gridView2.SetRowCellValue(row, "OverPayIncome", 0);
                    gridView2.SetRowCellValue(row, "ServicesAmount", 0);
                    gridView2.SetRowCellValue(row, "AmountPaid", 0);
                }
                ComputeTotal();
                return;
            }

            if (e.Column.FieldName == "EWTAmount" ||
                e.Column.FieldName == "DiscountAmount" ||
                e.Column.FieldName == "OverPay" ||
                e.Column.FieldName == "OverPayIncome" ||
                e.Column.FieldName == "OffsetAmount" ||
                e.Column.FieldName == "ServicesAmount")
            {
                RecalculateRow(row);
            }

            if (e.Column.FieldName == "EWTAmount" ||
                e.Column.FieldName == "DiscountAmount" ||
                e.Column.FieldName == "OffsetAmount" ||
                e.Column.FieldName == "OverPay" ||
                e.Column.FieldName == "OverPayIncome" ||
                e.Column.FieldName == "ServicesAmount" ||
                e.Column.FieldName == "AmountPaid")
            {
                ComputeTotal();
                gridView2.UpdateCurrentRow();
            }
        }

        // RecalculateRow: AmountPaid (net cash) = balance - all deductions
        // This is display-only. Gross is reconstructed at save time.
        private void RecalculateRow(int row)
        {
            bool isPay = Convert.ToBoolean(gridView2.GetRowCellValue(row, "Pay"));
            if (!isPay) return;
            if (IsCreditRow(row)) return;   // [79] a credit row's AmountPaid is the credit used, set by ApplyCreditTick

            double balance = Convert.ToDouble(gridView2.GetRowCellValue(row, "Balance") ?? 0);
            double ewt = Convert.ToDouble(gridView2.GetRowCellValue(row, "EWTAmount") ?? 0);
            double discount = Convert.ToDouble(gridView2.GetRowCellValue(row, "DiscountAmount") ?? 0);
            double offset = Convert.ToDouble(gridView2.GetRowCellValue(row, "OffsetAmount") ?? 0);
            double overpay = Convert.ToDouble(gridView2.GetRowCellValue(row, "OverPay") ?? 0);
            double overpayIncome = Convert.ToDouble(gridView2.GetRowCellValue(row, "OverPayIncome") ?? 0);
            double servicesAmount = Convert.ToDouble(gridView2.GetRowCellValue(row, "ServicesAmount") ?? 0);

            // ServicesAmount (e.g. cutting fee) is ADDITIVE -- an extra charge
            // billed to the client on top of the invoice balance, unlike
            // EWT/Discount/Offset which are deducted from it. OverPayIncome
            // behaves exactly like OverPay here -- both are excess cash
            // received; they only differ in which GL account absorbs it.
            double netPayment = (balance - ewt - discount - offset) + overpay + overpayIncome + servicesAmount;
            if (netPayment < 0) netPayment = 0;

            double current = Convert.ToDouble(gridView2.GetRowCellValue(row, "AmountPaid") ?? 0);
            if (current == netPayment) return;

            // Write directly to the bound DataRow instead of SetRowCellValue.
            // SetRowCellValue from inside another column's own CellValueChanged
            // handler is unreliable in this DevExpress version - the row can
            // still be mid-commit for the column that triggered this call, so
            // the sibling cell update doesn't always stick. Setting the DataRow
            // directly goes through the DataTable's own change notification,
            // which the bound grid always picks up correctly.
            DataRow dr = gridView2.GetDataRow(row);
            if (dr != null)
                dr["AmountPaid"] = netPayment;
            else
                gridView2.SetRowCellValue(row, "AmountPaid", netPayment);
        }

        // ── BALANCE-FORWARD CREDITS ([79], 2026-10-14) ──────────────────
        // Peachtree credits loaded at go-live (negative invoices) are listed one by one so a customer
        // can trace each credit by invoice. Ticking one applies it to the invoices ticked in the same
        // payment: AmountPaid = the credit used, as a NEGATIVE amount (invoice 1,000 + credit -300 =
        // amount to pay 700). It is saved as a negative INVOICE PAYMENT line; sp_AddPaymentClient
        // re-checks it against the credit's live balance (92010-92014). Only the credit itself goes on
        // a credit row: EWT, discount, offset, overpay and services stay on the invoice being paid.
        const string BFCreditType = "BF CREDIT";

        bool IsCreditRow(int row) =>
            row >= 0 && gridView2.GetRowCellValue(row, "InvoiceType")?.ToString() == BFCreditType;

        // What the ticked invoices still need in cash, i.e. how much credit can still be applied
        // (the server's rule: credits can't take the amount to pay below 0). exceptRow is left out.
        double CreditRoom(int exceptRow)
        {
            double room = 0;
            for (int i = 0; i < gridView2.RowCount; i++)
            {
                if (i == exceptRow || !Convert.ToBoolean(gridView2.GetRowCellValue(i, "Pay"))) continue;
                double amtPaid = Convert.ToDouble(gridView2.GetRowCellValue(i, "AmountPaid") ?? 0);
                if (IsCreditRow(i))
                    room += amtPaid;   // already negative
                else
                    room += amtPaid
                          - Convert.ToDouble(gridView2.GetRowCellValue(i, "OverPay") ?? 0)
                          - Convert.ToDouble(gridView2.GetRowCellValue(i, "OverPayIncome") ?? 0)
                          - Convert.ToDouble(gridView2.GetRowCellValue(i, "ServicesAmount") ?? 0);
            }
            room += OtherTotal();   // [104] Other Collections lines can cover credits too (credit + Other Income = no cash)
            return Math.Round(room, 2);
        }

        // Tick = the whole credit, capped at what the ticked invoices still need; untick = nothing used.
        // Written to the DataRow (same reason as RecalculateRow: SetRowCellValue from inside
        // CellValueChanged doesn't always stick in this DevExpress version).
        void ApplyCreditTick(int row, bool isPay)
        {
            DataRow dr = gridView2.GetDataRow(row);
            if (dr == null) return;
            foreach (string col in new[] { "EWTAmount", "DiscountAmount", "OffsetAmount", "OverPay", "OverPayIncome", "ServicesAmount" })
                dr[col] = 0;

            double credit = dr["Balance"] == DBNull.Value ? 0 : -Convert.ToDouble(dr["Balance"]);   // positive: what is left of the credit
            double room = isPay ? CreditRoom(row) : 0;
            dr["AmountPaid"] = (isPay && room > 0) ? -Math.Round(Math.Min(credit, room), 2) : 0;
        }

        // ComputeTotal: txtamounttopay shows total NET cash across selected rows
        private void ComputeTotal()
        {
            double total = 0;
            for (int i = 0; i < gridView2.RowCount; i++)
            {
                if (Convert.ToBoolean(gridView2.GetRowCellValue(i, "Pay")))
                    total += Convert.ToDouble(gridView2.GetRowCellValue(i, "AmountPaid") ?? 0);
            }
            total += OtherTotal();   // [104]
            txtamounttopay.Text = total.ToString("N2");
        }

        // ── GRID VALIDATION ─────────────────────────────────────────────
        private void gridView2_ValidatingEditor(object sender, DevExpress.XtraEditors.Controls.BaseContainerValidateEditorEventArgs e)
        {
            var view = sender as GridView;
            int row = view.FocusedRowHandle;
            string field = view.FocusedColumn.FieldName;

            if (field != "AmountPaid" && field != "EWTAmount" &&
                field != "DiscountAmount" && field != "OffsetAmount" &&
                field != "ServicesAmount")
                return;

            if (!double.TryParse(e.Value?.ToString(), out double value))
            {
                e.Valid = false;
                e.ErrorText = "Invalid number format.";
                return;
            }

            // [79] balance-forward credit: only the credit used, from 0 down to what is left of it
            if (IsCreditRow(row))
            {
                double left = -Convert.ToDouble(view.GetRowCellValue(row, "Balance") ?? 0);
                double room = CreditRoom(row);
                if (field != "AmountPaid")
                {
                    e.Valid = false;
                    e.ErrorText = "A balance-forward credit only takes the amount of credit used. Put EWT, discount, offset, overpay or services on the invoice being paid.";
                }
                else if (!Convert.ToBoolean(view.GetRowCellValue(row, "Pay")))
                {
                    e.Valid = false;
                    e.ErrorText = "Please check the 'Pay' box first.";
                }
                else if (value > 0)
                {
                    e.Valid = false;
                    e.ErrorText = "Enter the credit used as a negative amount (e.g. -300.00).";
                }
                else if (-value > left + 0.005)
                {
                    e.Valid = false;
                    e.ErrorText = $"Only {left:N2} is left of this credit.";
                }
                else if (-value > room + 0.005)
                {
                    e.Valid = false;
                    e.ErrorText = $"The invoices ticked only need {Math.Max(room, 0):N2}; the amount to pay can't go below 0.";
                }
                else
                    e.Valid = true;
                return;
            }

            if (value < 0)
            {
                e.Valid = false;
                e.ErrorText = "Negative values are not allowed.";
                return;
            }

            bool isPay = Convert.ToBoolean(view.GetRowCellValue(row, "Pay"));
            if (!isPay)
            {
                e.Valid = false;
                e.ErrorText = "Please check the 'Pay' box first.";
                return;
            }

            double balance = Convert.ToDouble(view.GetRowCellValue(row, "Balance") ?? 0);
            double ewt = Convert.ToDouble(view.GetRowCellValue(row, "EWTAmount") ?? 0);
            double discount = Convert.ToDouble(view.GetRowCellValue(row, "DiscountAmount") ?? 0);
            double offset = Convert.ToDouble(view.GetRowCellValue(row, "OffsetAmount") ?? 0);
            double overpay = Convert.ToDouble(view.GetRowCellValue(row, "OverPay") ?? 0);
            double amtPaid = Convert.ToDouble(view.GetRowCellValue(row, "AmountPaid") ?? 0);

            // Apply the pending value to test
            if (field == "EWTAmount") ewt = value;
            if (field == "DiscountAmount") discount = value;
            if (field == "OffsetAmount") offset = value;
            if (field == "AmountPaid") amtPaid = value;

            //if ((ewt + discount + offset) > balance)
            //{
            //    e.Valid = false;
            //    e.ErrorText = "Total deductions (EWT + Discount + Offset) cannot exceed the Balance.";
            //    return;
            //}
            //// OverPay legitimately lets AmountPaid exceed Balance - allow that room.
            //if (amtPaid > balance + overpay)
            //{
            //    e.Valid = false;
            //    e.ErrorText = "Amount Paid cannot exceed the Balance plus Overpay.";
            //    return;
            //}

            e.Valid = true;
        }

        // ── ROW COLOR CODING ────────────────────────────────────────────
        private void gridView2_RowCellStyle(object sender, RowCellStyleEventArgs e)
        {
            GridView view = sender as GridView;
            if (e.RowHandle < 0) return;

            object val = view.GetRowCellValue(e.RowHandle, "Pay");
            bool isPay = val != null && val != DBNull.Value && bool.TryParse(val.ToString(), out bool b) && b;

            // [79] balance-forward credits: blue family (lavender = available, light blue = applied)
            if (IsCreditRow(e.RowHandle))
            {
                e.Appearance.BackColor = isPay ? Color.FromArgb(198, 224, 255) : Color.Lavender;
                e.Appearance.ForeColor = Color.FromArgb(0, 32, 96);
                return;
            }

            if (!isPay)
            {
                e.Appearance.BackColor = Color.LightGray;
                return;
            }

            double balance = Convert.ToDouble(view.GetRowCellValue(e.RowHandle, "Balance") ?? 0);
            double ewt = Convert.ToDouble(view.GetRowCellValue(e.RowHandle, "EWTAmount") ?? 0);
            double discount = Convert.ToDouble(view.GetRowCellValue(e.RowHandle, "DiscountAmount") ?? 0);
            double offset = Convert.ToDouble(view.GetRowCellValue(e.RowHandle, "OffsetAmount") ?? 0);
            double overpay = Convert.ToDouble(view.GetRowCellValue(e.RowHandle, "OverPay") ?? 0);
            double overpayIncome = Convert.ToDouble(view.GetRowCellValue(e.RowHandle, "OverPayIncome") ?? 0);
            double servicesAmount = Convert.ToDouble(view.GetRowCellValue(e.RowHandle, "ServicesAmount") ?? 0);
            double amtPaid = Convert.ToDouble(view.GetRowCellValue(e.RowHandle, "AmountPaid") ?? 0);

            double expectedNet = balance - ewt - discount - offset + overpay + overpayIncome + servicesAmount;

            if ((ewt + discount + offset) > balance || amtPaid < 0)
            {
                e.Appearance.BackColor = Color.LightCoral;
                e.Appearance.ForeColor = Color.White;
                return;
            }
            if (Math.Abs(amtPaid - expectedNet) > 0.01)
            {
                e.Appearance.BackColor = Color.Khaki;
                e.Appearance.ForeColor = Color.Black;
                return;
            }

            e.Appearance.BackColor = Color.LightGreen;
            e.Appearance.ForeColor = Color.Black;
        }

        // ── GRID CUSTOM EDITORS ─────────────────────────────────────────
        private void gridView2_CustomRowCellEdit(object sender, CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "DiscountGLCode")
                e.RepositoryItem = repositoryItemSearchLookUpEditglcode;
            if (e.Column.FieldName == "OffsetGLCode")
                e.RepositoryItem = repositoryItemSearchLookUpEditOffsetGLCode;
            if (e.Column.FieldName == "OffsetCreditGLCode")
                e.RepositoryItem = repositoryItemSearchLookUpEditOffsetCreditGLCode;
            if (e.Column.FieldName == "EWTDebitGLCode")
                e.RepositoryItem = repositoryItemSearchLookUpEditEWTDebitGLCode;
            if (e.Column.FieldName == "EWTCreditGLCode")
                e.RepositoryItem = repositoryItemSearchLookUpEditEWTCreditGLCode;
        }

        // ── GL CODE DESCRIPTION DISPLAY ──────────────────────────────────
        private void txtcreditglcode_EditValueChanged(object sender, EventArgs e)
        {
            GridView view = txtdebitglcode.Properties.View;
            object value = view.GetRowCellValue(view.FocusedRowHandle, "Description");
            txtdebitdesc.Text = value?.ToString() ?? "";
        }

        private void searchLookUpEditcreditglcode_EditValueChanged(object sender, EventArgs e)
        {
            GridView view = txtcreditglcode.Properties.View;
            object value = view.GetRowCellValue(view.FocusedRowHandle, "Description");
            txtcreditdesc.Text = value?.ToString() ?? "";
        }

        // ── CONTEXT MENU ─────────────────────────────────────────────────
        private void gridControl2_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStrip1.Show(gridControl2, e.Location);
        }

        private void editPaymentToolStripMenuItem_Click(object sender, EventArgs e)
        {
            HOFormsDevEx.ClientEditPayment clientedit = new ClientEditPayment();
            int focused = gridView2.FocusedRowHandle;
            if (IsCreditRow(focused))   // [79]
            {
                XtraMessageBox.Show("A balance-forward credit only takes the amount of credit used; put EWT, discount or offset on the invoice being paid.");
                return;
            }

            clientedit.txtdelivdate.Text = gridView2.GetRowCellValue(focused, "TransactionDate").ToString();
            clientedit.txtinvoiceno.Text = gridView2.GetRowCellValue(focused, "InvoiceNo").ToString();
            clientedit.txtinvoiceamount.Text = gridView2.GetRowCellValue(focused, "InvoiceAmount").ToString();
            clientedit.txtewtamount.Text = gridView2.GetRowCellValue(focused, "EWTAmount").ToString();
            clientedit.txtduedate.Text = gridView2.GetRowCellValue(focused, "DueDate").ToString();
            clientedit.txtterms.Text = Database.getSingleQuery("Customers", "CustomerID='" + txtcustid.Text + "'", "Term");
            clientedit.ShowDialog(this);

            if (ClientEditPayment.isdone)
            {
                if (ClientEditPayment.isdiscount)
                {
                    gridView2.SetRowCellValue(focused, "DiscountAmount", ClientEditPayment.discamount);
                    gridView2.SetRowCellValue(focused, "DiscountGLCode", ClientEditPayment.discdebit);
                }
                if (ClientEditPayment.isoffset)
                {
                    gridView2.SetRowCellValue(focused, "OffsetAmount", ClientEditPayment.offsetamount);
                    gridView2.SetRowCellValue(focused, "OffsetGLCode", ClientEditPayment.offsetdebit);
                    gridView2.SetRowCellValue(focused, "OffsetCreditGLCode", ClientEditPayment.offsetcredit);
                }
                if (ClientEditPayment.isewt)
                {
                    gridView2.SetRowCellValue(focused, "EWTAmount", ClientEditPayment.ewtamount);
                    gridView2.SetRowCellValue(focused, "EWTDebitGLCode", ClientEditPayment.ewtdebit);
                    gridView2.SetRowCellValue(focused, "EWTCreditGLCode", ClientEditPayment.ewtcredit);
                }
                ClientEditPayment.isdone = false;
                clientedit.Dispose();
            }
        }

        private void clearFieldsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            int row = gridView2.FocusedRowHandle;
            if (IsCreditRow(row)) return;   // [79] nothing but the credit used on a credit row
            gridView2.SetRowCellValue(row, "DiscountAmount", "0");
            gridView2.SetRowCellValue(row, "DiscountGLCode", "");
            gridView2.SetRowCellValue(row, "OffsetAmount", "0");
            gridView2.SetRowCellValue(row, "OffsetGLCode", "");
            gridView2.SetRowCellValue(row, "OffsetCreditGLCode", "");
            gridView2.SetRowCellValue(row, "EWTAmount", "0");
            gridView2.SetRowCellValue(row, "EWTDebitGLCode", "");
            gridView2.SetRowCellValue(row, "EWTCreditGLCode", "");
            RecalculateRow(row);
        }

        // ── CONFIRM PAYMENT ──────────────────────────────────────────────
        void confirmPayment()
        {
            if (!HelperFunction.ConfirmDialog("Are you sure?", "Confirm Payment"))
                return;

            if (!radioButton1.Checked && !radioButton2.Checked &&
                !radioButton3.Checked && !radCreditCard.Checked)
            {
                XtraMessageBox.Show("Please select a Payment Type.");
                return;
            }

            int ctr = 0;
            int advpymntctr = 0;
            double totalBalance = 0;
            double totalAmtPaid = 0;
            double totalOverpay = 0;
            double totalOverpayIncome = 0;
            double totalServicesAmount = 0;
            double totalDeductions = 0; // EWT + Discount + Offset + OverPay + OverPayIncome, across checked rows
            double advncepymentval = 0;
            bool isSales = false;
            bool isCharge = false;
            double totalCredit = 0;      // [79] balance-forward credits applied (positive)
            double creditRoom = 0;       // [79] cash the ticked invoices need before credits
            int invoiceCtr = 0;

            for (int i = 0; i < gridView2.RowCount; i++)
            {
                bool isPay = gridView2.GetRowCellValue(i, "Pay").ToString() == "True";
                if (!isPay) continue;

                // [79] a ticked balance-forward credit: only the credit used, between 0 and what is left of it
                if (IsCreditRow(i))
                {
                    double used = -Convert.ToDouble(gridView2.GetRowCellValue(i, "AmountPaid") ?? 0);
                    double left = -Convert.ToDouble(gridView2.GetRowCellValue(i, "Balance") ?? 0);
                    string inv = gridView2.GetRowCellValue(i, "InvoiceNo")?.ToString();
                    if (Math.Round(used, 2) <= 0 || Math.Round(used, 2) > Math.Round(left, 2))
                    {
                        XtraMessageBox.Show(
                            $"Balance-forward credit {inv}: the credit used must be between 0.01 and {left:N2} (entered as a negative amount), or untick it.",
                            "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        return;
                    }
                    ctr++;
                    totalCredit += used;
                    totalAmtPaid -= used;
                    continue;
                }
                invoiceCtr++;
                creditRoom += Convert.ToDouble(gridView2.GetRowCellValue(i, "AmountPaid") ?? 0)
                            - Convert.ToDouble(gridView2.GetRowCellValue(i, "OverPay") ?? 0)
                            - Convert.ToDouble(gridView2.GetRowCellValue(i, "OverPayIncome") ?? 0)
                            - Convert.ToDouble(gridView2.GetRowCellValue(i, "ServicesAmount") ?? 0);

                double rowOverpay = Convert.ToDouble(gridView2.GetRowCellValue(i, "OverPay") ?? 0);
                double rowOverpayIncome = Convert.ToDouble(gridView2.GetRowCellValue(i, "OverPayIncome") ?? 0);
                double rowOffset = Convert.ToDouble(gridView2.GetRowCellValue(i, "OffsetAmount") ?? 0);

                ctr++;
                totalBalance += Convert.ToDouble(gridView2.GetRowCellValue(i, "Balance") ?? 0);
                totalAmtPaid += Convert.ToDouble(gridView2.GetRowCellValue(i, "AmountPaid") ?? 0);
                totalOverpay += rowOverpay;
                totalOverpayIncome += rowOverpayIncome;
                totalServicesAmount += Convert.ToDouble(gridView2.GetRowCellValue(i, "ServicesAmount") ?? 0);
                advncepymentval += Convert.ToDouble(gridView2.GetRowCellValue(i, "AmountPaid") ?? 0);
                totalDeductions +=
                    Convert.ToDouble(gridView2.GetRowCellValue(i, "EWTAmount") ?? 0) +
                    Convert.ToDouble(gridView2.GetRowCellValue(i, "DiscountAmount") ?? 0) +
                    rowOffset + rowOverpay + rowOverpayIncome;

                string invType = gridView2.GetRowCellValue(i, "InvoiceType")?.ToString();
                if (invType == "SALES") isSales = true;
                if (invType == "CHARGE") isCharge = true;

                //if (Convert.ToDouble(gridView2.GetRowCellValue(i, "AdvancePayment") ?? 0) > 0)
                if (rowOverpay > 0 || rowOverpayIncome > 0)
                    advpymntctr++;

                // Client-side mirror of sp_AddPaymentClient's structural
                // Offset/Overpay/OverPayIncome mutual-exclusivity guard --
                // catch it here with a clear per-row message instead of
                // letting it round-trip to the server first.
                if ((rowOffset > 0 ? 1 : 0) + (rowOverpay > 0 ? 1 : 0) + (rowOverpayIncome > 0 ? 1 : 0) > 1)
                {
                    XtraMessageBox.Show(
                        $"Row for invoice {gridView2.GetRowCellValue(i, "InvoiceNo")}: Offset, Overpay(Credits) and Overpay(OtherIncome) cannot be combined on the same invoice - choose only one.",
                        "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }
            }

            // [104] Other Collections lines: each needs an account from the list and an amount above 0
            CommitOtherLines();
            ComputeTotal();   // the header / cash rows post txtamounttopay: it must include a line just committed
            int otherCtr = 0;
            foreach (DataRow r in OtherLineRows())
            {
                string acct = r["AccountCode"]?.ToString()?.Trim();
                decimal amt = r["Amount"] == DBNull.Value ? 0m : Convert.ToDecimal(r["Amount"]);
                if (string.IsNullOrEmpty(acct) || OtherAccountDescription(acct) == null)
                {
                    XtraMessageBox.Show("Other Collections: every line needs an account from the list.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    tabEntry.SelectedTabPage = pageOther;
                    return;
                }
                if (Math.Round(amt, 2) <= 0)
                {
                    XtraMessageBox.Show($"Other Collections: the line for account {acct} needs an amount above 0 (or remove the line).", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    tabEntry.SelectedTabPage = pageOther;
                    return;
                }
                otherCtr++;
            }
            double otherTotal = OtherTotal();

            if (ctr == 0 && otherCtr == 0)
            {
                XtraMessageBox.Show("No invoices selected and no Other Collections lines. Please check the 'Pay' checkbox or add a line.");
                return;
            }

            // Round to cents before comparing - totalAmtPaid is a double sum of
            // grid cells, sp_AddPaymentClient re-derives its own net cash in
            // decimal(18,2) from what actually gets written to
            // ARPaymentDetails. Comparing raw doubles risked the UI deciding
            // "net cash" on one side of zero while the SP's decimal math lands
            // on the other, which would surface as a confusing 92004 THROW
            // instead of the intended zero-cash confirm prompt.
            // [79] credits need an invoice to go on, and can't take the amount to pay below 0
            // (the server refuses the same, 92014). totalAmtPaid is already net of them.
            if (totalCredit > 0 && invoiceCtr == 0 && otherCtr == 0)
            {
                XtraMessageBox.Show("A balance-forward credit has to be applied to an invoice (or closed to an Other Collections line): tick the invoice(s) being paid too, or add the line.",
                    "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            // [104] Other Collections lines can cover credits too (the server's 92014)
            if (Math.Round(totalCredit, 2) > Math.Round(creditRoom + otherTotal, 2))
            {
                XtraMessageBox.Show(
                    $"The balance-forward credits applied ({totalCredit:N2}) are more than the invoices ticked and the Other Collections lines cover ({Math.Max(creditRoom + otherTotal, 0):N2}). " +
                    "Use less of a credit or untick one.",
                    "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            // [104] credits beyond the invoices: the rest is covered by Other Collections only, so no EWT / discount /
            // offset / overpay / services on the invoices (the server's 92023)
            if (Math.Round(totalCredit, 2) > Math.Round(Math.Max(creditRoom, 0), 2)
                && Math.Round(totalDeductions + totalServicesAmount, 2) > 0)
            {
                XtraMessageBox.Show(
                    "The credits ticked are more than the invoices ticked, so the rest is covered by the Other Collections lines: " +
                    "remove EWT, discount, offset, overpay and services from the invoices in this payment (post them separately).",
                    "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            double roundedNetCash = Math.Round(totalAmtPaid + otherTotal, 2);   // [104] + Other Collections
            bool hasNetCash = roundedNetCash > 0;

            // A checked row with nothing entered anywhere (AmountPaid, EWT,
            // Discount, Offset, OverPay all 0) reconstructs to gross=0 in
            // InsertARPaymentDetails() and is silently skipped from the
            // INVOICE PAYMENT insert entirely - i.e. it looks selected but
            // nothing would actually post for it. Block this outright rather
            // than let it fall into the zero-net-cash confirm path, which is
            // meant for genuine EWT/Discount/Offset-only corrections, not an
            // empty selection.
            if (!hasNetCash && Math.Round(totalDeductions, 2) == 0 && Math.Round(totalCredit, 2) == 0 && otherCtr == 0)
            {
                XtraMessageBox.Show(
                    "No amount, EWT, Discount, or Offset was entered for the selected invoice(s) - " +
                    "nothing would be posted. Enter an amount or uncheck 'Pay'.",
                    "Nothing To Post", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // Debit GL Code / Control No / CR No are only mandatory when this
            // submission actually moves cash. An EWT-only (or discount/offset-
            // only) correction - e.g. recording a 2307-backed EWT weeks after
            // the cash portion of an invoice was already paid separately -
            // nets to exactly 0 here, has no bank leg to post and no receipt
            // to reference. sp_AddPaymentClient enforces the same rule
            // server-side (THROW 92004) as a backstop.
            if (hasNetCash &&
                (string.IsNullOrEmpty(txtdebitglcode.Text) ||
                 string.IsNullOrEmpty(txtcontrolno.Text) ||
                 string.IsNullOrEmpty(txtcrno.Text)))
            {
                XtraMessageBox.Show("Please fill up mandatory fields.");
                return;
            }
            // [110] a CR recorded as cancelled (Cancelled CR…) can't be used for a payment
            if (!string.IsNullOrWhiteSpace(txtcrno.Text))
            {
                string cancelled;
                try { cancelled = FindCancelledCR(txtcustid.Text, txtcrno.Text); }
                catch (Exception ex)
                {
                    XtraMessageBox.Show("Could not check the CR no.: " + ex.Message + "\nNothing was posted.", "CR No.", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }
                if (cancelled != null)
                {
                    XtraMessageBox.Show(cancelled + "\n\nUse another CR no. (or correct the cancelled record in Cancelled CR… if it was recorded by mistake). Nothing was posted.",
                        "CR No.", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }
            }
            if (!hasNetCash &&
                !HelperFunction.ConfirmDialog(
                    totalCredit > 0 && otherCtr > 0
                        ? $"No cash is received: the balance-forward credits ({totalCredit:N2}) are closed against the invoice(s) and the " +
                          $"Other Collections line(s) ({otherTotal:N2}). The GL entry debits AR and credits the Other Collections account(s). Continue?"
                    : totalCredit > 0
                        ? "The balance-forward credits cover the invoice(s) in full - no cash is received and " +
                          "no GL entry is made (the opening AR is already net of these credits). Continue?"
                        : "This payment has no net cash amount (EWT/Discount/Offset only) - " +
                          "Debit GL Code will not be posted. Continue?",
                    "Zero Net Cash"))
                return;

            if (advpymntctr > 1)
            {
                XtraMessageBox.Show("Overpay(Credits) / Overpay(OtherIncome) must be assigned to only one invoice.");
                return;
            }
            if (isSales && isCharge)
            {
                XtraMessageBox.Show("Cannot mix CHARGE and SALES invoice payments. Process one type at a time.");
                return;
            }
            //if (radioButton4.Checked && advncepymentval > Convert.ToDouble(txtacctbalance.Text))
            //{
            //    XtraMessageBox.Show("Total Amount Paid exceeds available savings balance.");
            //    return;
            //}
            // OverPay/OverPayIncome are both deliberate excess cash (they're
            // mutually exclusive per row, but summed together here since
            // either one raises the same ceiling), and ServicesAmount is an
            // additive charge billed on top of the invoice (e.g. a cutting
            // fee) - AmountPaid is expected to exceed Balance by exactly
            // their combined total, so all must be added to the allowed
            // ceiling here instead of being treated as an error.
            // [79] invoice rows only: credit rows are left out of totalBalance, so add their amount back
            if (totalAmtPaid + totalCredit > totalBalance + totalOverpay + totalOverpayIncome + totalServicesAmount)
            {
                XtraMessageBox.Show("Total Amount Paid cannot exceed Total Balance plus Overpay(Credits) / Overpay(OtherIncome) plus Services Amount.");
                return;
            }

            isglobalCharge = isCharge;
            isglobalSales = isSales;
            ProcessPayment();
        }

        private void simpleButton4_Click(object sender, EventArgs e) => confirmPayment();

        // ── PAYMENT PROCESSING ───────────────────────────────────────────
        void ProcessPayment()
        {
            using (SqlConnection con = Database.getConnection())
            {
                con.Open();
                using (SqlTransaction tran = con.BeginTransaction())
                {
                    try
                    {
                        int paymentHeaderId = InsertPaymentHeader(con, tran);
                        InsertPaymentMethod(con, tran, paymentHeaderId);
                        InsertARPaymentDetails(con, tran, paymentHeaderId);
                        ExecutePostingSP(con, tran, paymentHeaderId);

                        tran.Commit();
                        BigAlert.Show("SUCCESS", "Payment Successfully Posted!", MessageBoxIcon.Information);
                        // Was this.Dispose() - fine for a one-shot ShowDialog() usage, but this
                        // control is now a persistent Accounting Board accordion page (see
                        // AccountingBoard.cs's PagePostClientPayment), reused across many
                        // payments/customers in one session. Disposing it here killed the whole
                        // "Post Client Payment" module after the very first successful post
                        // (Known Bug Pattern #6 - Reset Entry not called after save).
                        ResetEntry();
                    }
                    catch (Exception ex)
                    {
                        // sp_AddPaymentClient (called via ExecutePostingSP above, on this
                        // same tran) does its own BEGIN TRAN/ROLLBACK internally. SQL
                        // Server's ROLLBACK always unwinds to the OUTERMOST transaction
                        // regardless of nesting - confirmed live: after the SP's internal
                        // ROLLBACK fires, @@TRANCOUNT on this connection is already 0. That
                        // means tran.Rollback() here is rolling back a server-side
                        // transaction that's already gone, and SqlTransaction throws
                        // InvalidOperationException ("This SqlTransaction has completed")
                        // when that happens - which would otherwise skip the BigAlert below
                        // entirely and swallow the real error message (including every THROW
                        // in sp_AddPaymentClient, not just the new zero-cash guardrail one).
                        try { tran.Rollback(); } catch { /* already rolled back server-side by the SP */ }
                        BigAlert.Show("Error", ex.Message, MessageBoxIcon.Error);
                    }
                }
            }
        }

        // ── RESET ENTRY ────────────────────────────────────────────────────
        // Clears the payment entry fields back to a blank state after a
        // successful post, same intent as AddExpenseDevExFrm's StartNewEntry():
        // mint-ready for the next payment instead of disposing the control.
        // Customer selection (txtcustname/txtcustid/custkey) is deliberately
        // left as-is - re-fetching the customer's now-updated balances via
        // display() below is more useful than forcing a re-pick, since
        // recording another payment for the same customer right after is the
        // common case this screen is used for.
        void ResetEntry()
        {
            radioButton1.Checked = false;
            radioButton2.Checked = false;
            radioButton3.Checked = false;
            
            radCreditCard.Checked = false;
            ApplyPaymentTypeVisibility();

            txtcontrolno.Text = "";
            txtcrno.Text = "";
            txtremakrs.Text = "";
            txtdate.EditValue = DateTime.Today;
            txtdebitglcode.Text = "";
            txtcreditglcode.Text = "";
            txtdebitdesc.Text = "";
            txtcreditdesc.Text = "";
            txtamounttopay.Text = "0.00";

            txtchecknum.Text = "";
            txtcheckname.Text = "";
            txtcheckbankname.Text = "";
            txtcheckamount.Text = "";
            txtcheckdate.EditValue = null;

            txtrefnoonline.Text = "";
            txtdepbankonline.Text = "";
            txtdatedeponline.EditValue = null;

            ClearOtherLines();   // [104]
            tabEntry.SelectedTabPage = pageInvoices;
            display();
            RefreshAvailableCredit();
            LoadPostedClientPayments();
        }

        int InsertPaymentHeader(SqlConnection con, SqlTransaction tran)
        {
            refno = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");

            using (SqlCommand cmd = new SqlCommand(@"
                INSERT INTO PaymentHeader
                    (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType,
                     TotalAmount, PaymentDate, Remarks, CreatedBy)
                OUTPUT INSERTED.PaymentHeaderID
                VALUES
                    (@custkey, @refno, @control, @crno, @type,
                     @amount, @date, @remarks, @user)", con, tran))
            {
                cmd.Parameters.Add("@custkey", SqlDbType.Char, 8).Value = custkey;
                cmd.Parameters.Add("@refno", SqlDbType.VarChar, 20).Value = refno;
                cmd.Parameters.Add("@control", SqlDbType.VarChar, 30).Value = txtcontrolno.Text;
                cmd.Parameters.Add("@crno", SqlDbType.VarChar, 20).Value = txtcrno.Text;
                cmd.Parameters.Add("@type", SqlDbType.VarChar, 30).Value = GetPaymentType();
                cmd.Parameters.Add("@amount", SqlDbType.Decimal).Value = Convert.ToDecimal(txtamounttopay.Text);
                cmd.Parameters.Add("@date", SqlDbType.Date).Value = Convert.ToDateTime(txtdate.Text);
                cmd.Parameters.Add("@remarks", SqlDbType.VarChar, 500).Value = txtremakrs.Text;
                cmd.Parameters.Add("@user", SqlDbType.VarChar, 50).Value = Login.Fullname;

                return Convert.ToInt32(cmd.ExecuteScalar());
            }
        }

        void InsertPaymentMethod(SqlConnection con, SqlTransaction tran, int paymentHeaderId)
        {
            string type = GetPaymentType();
            decimal netAmount = Convert.ToDecimal(txtamounttopay.Text);

            if (type == "CASH")
            {
                using (SqlCommand cmd = new SqlCommand(@"
                    INSERT INTO TransactionCashCollection
                        (PaymentHeaderID, CustomerKey, AmountPaid, Remarks, DatePaid, TransactedBy, isErrorCorrect)
                    VALUES
                        (@phid, @custkey, @amount, @remarks, @date, @user, 0)", con, tran))
                {
                    cmd.Parameters.Add("@phid", SqlDbType.Int).Value = paymentHeaderId;
                    cmd.Parameters.Add("@custkey", SqlDbType.VarChar, 118).Value = custkey;
                    cmd.Parameters.Add("@amount", SqlDbType.Decimal).Value = netAmount;
                    cmd.Parameters.Add("@remarks", SqlDbType.VarChar, 500).Value = txtremakrs.Text;
                    cmd.Parameters.Add("@date", SqlDbType.Date).Value = Convert.ToDateTime(txtdate.Text);
                    cmd.Parameters.Add("@user", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    cmd.ExecuteNonQuery();
                }
            }
            else if (type == "CHECK")
            {
                using (SqlCommand cmd = new SqlCommand(@"
                    INSERT INTO TransactionCheque
                        (PaymentHeaderID, BranchCode, ControlNo, CRNo, CustomerID, CustomerName,
                         CheckNo, CheckName, CheckBankName, CheckAmount, CheckDate,
                         Amount, Remarks, DatePaid, TransactedBy, CreditGLCode)
                    VALUES
                        (@phid, @branch, @control, @crno, @custid, @custname,
                         @checkno, @checkname, @bank, @checkamount, @checkdate,
                         @amount, @remarks, @date, @user, @glcode)", con, tran))
                {
                    cmd.Parameters.Add("@phid", SqlDbType.Int).Value = paymentHeaderId;
                    cmd.Parameters.Add("@branch", SqlDbType.Char, 3).Value = Customers.getCustBranch(txtcustid.Text);
                    cmd.Parameters.Add("@control", SqlDbType.VarChar, 30).Value = txtcontrolno.Text;
                    cmd.Parameters.Add("@crno", SqlDbType.VarChar, 20).Value = txtcrno.Text;
                    cmd.Parameters.Add("@custid", SqlDbType.VarChar, 20).Value = txtcustid.Text;
                    cmd.Parameters.Add("@custname", SqlDbType.VarChar, 120).Value = txtcustname.Text;
                    cmd.Parameters.Add("@checkno", SqlDbType.VarChar, 50).Value = txtchecknum.Text;
                    cmd.Parameters.Add("@checkname", SqlDbType.VarChar, 50).Value = txtcheckname.Text;
                    cmd.Parameters.Add("@bank", SqlDbType.VarChar, 50).Value = txtcheckbankname.Text;
                    cmd.Parameters.Add("@checkamount", SqlDbType.Money).Value = Convert.ToDecimal(txtcheckamount.Text);
                    cmd.Parameters.Add("@checkdate", SqlDbType.Date).Value = Convert.ToDateTime(txtcheckdate.Text);
                    cmd.Parameters.Add("@amount", SqlDbType.Money).Value = netAmount;
                    cmd.Parameters.Add("@remarks", SqlDbType.VarChar, 500).Value = txtremakrs.Text;
                    cmd.Parameters.Add("@date", SqlDbType.Date).Value = Convert.ToDateTime(txtdate.Text);
                    cmd.Parameters.Add("@user", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    // CreditGLCode stored here so SP can resolve the bank account
                    cmd.Parameters.Add("@glcode", SqlDbType.VarChar, 20).Value = txtdebitglcode.Text;
                    cmd.ExecuteNonQuery();
                }
            }
            else if (type == "ONLINE")
            {
                using (SqlCommand cmd = new SqlCommand(@"
                    INSERT INTO TransactionOnline
                        (PaymentHeaderID, BranchCode, ControlNo, CRNo,CustomerID, CustomerName, BankRefNumber, BankName, DateDeposit,
                         Amount, Remarks, DatePaid, TransactedBy)
                    VALUES
                        (@phid,@branch, @control, @crno, @custid, @custname, @refno, @bank, @depdate,
                         @amount, @remarks, @date, @user)", con, tran))
                {
                    cmd.Parameters.Add("@phid", SqlDbType.Int).Value = paymentHeaderId;
                    cmd.Parameters.Add("@branch", SqlDbType.Char, 3).Value = Customers.getCustBranch(txtcustid.Text);
                    cmd.Parameters.Add("@control", SqlDbType.VarChar, 30).Value = txtcontrolno.Text;
                    cmd.Parameters.Add("@crno", SqlDbType.VarChar, 20).Value = txtcrno.Text;
                    cmd.Parameters.Add("@custid", SqlDbType.VarChar, 20).Value = txtcustid.Text;
                    cmd.Parameters.Add("@custname", SqlDbType.VarChar, 120).Value = txtcustname.Text;
                    cmd.Parameters.Add("@refno", SqlDbType.VarChar, 50).Value = txtrefnoonline.Text;
                    cmd.Parameters.Add("@bank", SqlDbType.VarChar, 50).Value = txtdepbankonline.Text;
                    cmd.Parameters.Add("@depdate", SqlDbType.Date).Value = Convert.ToDateTime(txtdatedeponline.Text);
                    cmd.Parameters.Add("@amount", SqlDbType.Decimal).Value = netAmount;
                    cmd.Parameters.Add("@remarks", SqlDbType.VarChar, 500).Value = txtremakrs.Text;
                    cmd.Parameters.Add("@date", SqlDbType.Date).Value = Convert.ToDateTime(txtdate.Text);
                    cmd.Parameters.Add("@user", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    cmd.ExecuteNonQuery();
                }
            }
        }

        // ── AR PAYMENT DETAILS INSERT ────────────────────────────────────
        // [BUG-1] FIX: INVOICE PAYMENT row now stores GROSS (balance being settled),
        //         not net cash. The SP derives net cash as Gross - EWT - Discount - Offset.
        //
        //  Grid columns meaning:
        //    AmountPaid    = net cash physically received  (balance - deductions)
        //    EWTAmount     = EWT withheld
        //    DiscountAmount= discount granted
        //    OffsetAmount  = advance/deposit offset
        //    Balance       = original invoice balance (= gross being settled)
        //
        //  ARPaymentDetails rows:
        //    INVOICE PAYMENT → Amount = Balance (gross)   ← THE FIX
        //    EWT             → Amount = EWTAmount
        //    DISCOUNT        → Amount = DiscountAmount
        //    OFFSET          → Amount = OffsetAmount
        // ─────────────────────────────────────────────────────────────────
        void InsertARPaymentDetails(SqlConnection con, SqlTransaction tran, int paymentHeaderId)
        {
            for (int i = 0; i < gridView2.RowCount; i++)
            {
                bool pay = Convert.ToBoolean(gridView2.GetRowCellValue(i, "Pay"));
                if (!pay) continue;

                string invoiceNo = gridView2.GetRowCellValue(i, "InvoiceNo").ToString();
                string orderNo = gridView2.GetRowCellValue(i, "OrderNo").ToString();
                DateTime transDate = Convert.ToDateTime(gridView2.GetRowCellValue(i, "TransactionDate"));

                // [79] balance-forward credit: one INVOICE PAYMENT line with the credit used as a NEGATIVE amount
                if (IsCreditRow(i))
                {
                    decimal creditUsed = Math.Round(Convert.ToDecimal(gridView2.GetRowCellValue(i, "AmountPaid") ?? 0), 2);
                    if (creditUsed < 0)
                        InsertDetail(con, tran, paymentHeaderId, orderNo, invoiceNo, transDate, creditUsed, "INVOICE PAYMENT");
                    continue;
                }

                decimal ewt = Convert.ToDecimal(gridView2.GetRowCellValue(i, "EWTAmount") ?? 0);
                decimal discount = Convert.ToDecimal(gridView2.GetRowCellValue(i, "DiscountAmount") ?? 0);
                decimal offset = Convert.ToDecimal(gridView2.GetRowCellValue(i, "OffsetAmount") ?? 0);
                decimal overpay = Convert.ToDecimal(gridView2.GetRowCellValue(i, "OverPay") ?? 0);
                decimal overpayIncome = Convert.ToDecimal(gridView2.GetRowCellValue(i, "OverPayIncome") ?? 0);
                decimal servicesAmount = Convert.ToDecimal(gridView2.GetRowCellValue(i, "ServicesAmount") ?? 0);
                decimal amountPaid = Convert.ToDecimal(gridView2.GetRowCellValue(i, "AmountPaid") ?? 0);

                // GROSS = however much of the invoice is being cleared THIS
                // transaction, not necessarily the whole Balance - AmountPaid
                // can legitimately be less than Balance for a genuine partial
                // payment (no EWT/Discount/Offset, just paying less than owed).
                // Reconstruct it as net cash + deductions withheld/applied,
                // minus OverPay/OverPayIncome and ServicesAmount since
                // RecalculateRow() already baked +overpay, +overpayIncome, and
                // +servicesAmount into AmountPaid (balance - ewt - discount -
                // offset + overpay + overpayIncome + servicesAmount) - without
                // subtracting them back out here, they'd double count into gross.
                decimal gross = amountPaid + ewt + discount + offset - overpay - overpayIncome - servicesAmount;

                // INVOICE PAYMENT: always insert using the gross amount
                if (gross > 0)
                    InsertDetail(con, tran, paymentHeaderId, orderNo, invoiceNo, transDate, gross, "INVOICE PAYMENT");

                if (ewt > 0)
                    InsertDetail(con, tran, paymentHeaderId, orderNo, invoiceNo, transDate, ewt, "EWT");

                if (discount > 0)
                    InsertDetail(con, tran, paymentHeaderId, orderNo, invoiceNo, transDate, discount, "DISCOUNT");

                if (offset > 0)
                    InsertDetail(con, tran, paymentHeaderId, orderNo, invoiceNo, transDate, offset, "OFFSET");

                if (overpay > 0)
                    InsertDetail(con, tran, paymentHeaderId, orderNo, invoiceNo, transDate, overpay, "OVERPAY");

                if (overpayIncome > 0)
                    InsertDetail(con, tran, paymentHeaderId, orderNo, invoiceNo, transDate, overpayIncome, "OVERPAYINCOME");

                if (servicesAmount > 0)
                    InsertDetail(con, tran, paymentHeaderId, orderNo, invoiceNo, transDate, servicesAmount, "SERVICES");
            }

            // [104] Other Collections: PONumber '#OTHER' (no invoice), CreditGLCode = the account, InvoiceNo = the remarks
            // (the account's name when blank), dated like the payment
            DateTime payDate = Convert.ToDateTime(txtdate.Text);
            foreach (DataRow r in OtherLineRows())
            {
                string acct = r["AccountCode"].ToString().Trim();
                string remarks = r["Remarks"]?.ToString()?.Trim();
                if (string.IsNullOrEmpty(remarks)) remarks = "OTHER COLLECTION - " + (OtherAccountDescription(acct) ?? acct);
                if (remarks.Length > 50) remarks = remarks.Substring(0, 50);
                decimal amt = Math.Round(Convert.ToDecimal(r["Amount"]), 2);
                InsertDetail(con, tran, paymentHeaderId, OtherPONumber, remarks, payDate, amt, OtherPaymentType, acct);
            }
        }

        void InsertDetail(SqlConnection con, SqlTransaction tran, int phid,
                          string po, string invoice, DateTime date, decimal amount, string type, string creditGLCode = null)
        {
            using (SqlCommand cmd = new SqlCommand(@"
                INSERT INTO ARPaymentDetails
                    (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo,
                     InvoiceDate, Amount, PaymentType, PaymentMethod,
                     DebitGLCode, CreditGLCode, TicketNumber)
                VALUES
                    (@phid, @custkey, @refno, @po, @invoice,
                     @date, @amount, @type, 'PAYMENT',
                     @debit, @credit, '')", con, tran))
            {
                cmd.Parameters.Add("@phid", SqlDbType.Int).Value = phid;
                cmd.Parameters.Add("@custkey", SqlDbType.Char, 8).Value = custkey;
                cmd.Parameters.Add("@refno", SqlDbType.VarChar, 20).Value = refno;
                cmd.Parameters.Add("@po", SqlDbType.VarChar, 10).Value = po;
                cmd.Parameters.Add("@invoice", SqlDbType.VarChar, 50).Value = invoice;
                cmd.Parameters.Add("@date", SqlDbType.Date).Value = date;
                cmd.Parameters.Add("@amount", SqlDbType.Decimal).Value = amount;
                cmd.Parameters.Add("@type", SqlDbType.VarChar, 20).Value = type;
                // Blank means "not applicable" (e.g. an EWT-only, zero-net-cash
                // entry) - store NULL rather than a literal empty string so it
                // reads honestly and sp_AddPaymentClient's own ISNULL/blank
                // check treats it consistently.
                cmd.Parameters.Add("@debit", SqlDbType.VarChar, 20).Value =
                    string.IsNullOrEmpty(txtdebitglcode.Text) ? (object)DBNull.Value : txtdebitglcode.Text;
                string credit = creditGLCode ?? txtcreditglcode.Text;   // [104] an Other Collections line carries its own account
                cmd.Parameters.Add("@credit", SqlDbType.VarChar, 20).Value =
                    string.IsNullOrEmpty(credit) ? (object)DBNull.Value : credit;
                cmd.ExecuteNonQuery();
            }
        }

        void ExecutePostingSP(SqlConnection con, SqlTransaction tran, int paymentHeaderId)
        {
            using (SqlCommand cmd = new SqlCommand("sp_AddPaymentClient", con, tran))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@PaymentHeaderID", SqlDbType.Int).Value = paymentHeaderId;
                cmd.ExecuteNonQuery();
            }
        }

        string GetPaymentType()
        {
            if (radioButton1.Checked) return "CASH";
            if (radioButton2.Checked) return "CHECK";
            if (radioButton3.Checked) return "ONLINE";
            //if (radioButton4.Checked) return "ADVANCEPAYMENT";
            if (radCreditCard.Checked) return "CREDITCARD";
            throw new Exception("No payment type selected.");
        }

        // ── POSTED CLIENT PAYMENTS (FullyPaid Invoice tab) ───────────────
        // Lists this customer's payment headers via sp_GetPostedClientPayments,
        // one row per PaymentHeader with a server-computed BlockedReason
        // (non-null once Status='REVERSED'). Replaces the old master-detail
        // grid so a flat row now maps 1:1 to what View/Edit Details act on.
        void LoadPostedClientPayments()
        {
            // @DateFrom/@DateTo are both inclusive and NULL-able on the SP
            // side now (sp_GetPostedClientPayments owns the +1-day exclusive
            // conversion internally) - passing DBNull here instead of
            // DateTime.MaxValue avoids a DATEADD(DAY,1,...) overflow on the
            // SP side when no end date is chosen.
            object dateFromParam = txtdatefrom.EditValue == null
                ? (object)DBNull.Value : (DateTime)txtdatefrom.EditValue;
            object dateToParam = txtdateto.EditValue == null
                ? (object)DBNull.Value : (DateTime)txtdateto.EditValue;

            using (SqlConnection con = Database.getConnection())
            using (SqlCommand cmd = new SqlCommand("sp_GetPostedClientPayments", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@CustomerKey", SqlDbType.Char, 8).Value = custkey;
                cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value = dateFromParam;
                cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value = dateToParam;

                DataTable table = new DataTable();
                con.Open();
                using (SqlDataReader dr = cmd.ExecuteReader())
                    table.Load(dr);

                gridControl1.DataSource = table;
            }

            gridControlPaymentDetails.DataSource = null;
            gridView9.OptionsView.ColumnAutoWidth = false;
            if (gridView9.Columns["BlockedReason"] != null)
                gridView9.Columns["BlockedReason"].VisibleIndex = 0;
            gridView9.BestFitColumns();
        }

        private void gridView9_RowCellStyle(object sender, RowCellStyleEventArgs e)
        {
            GridView view = sender as GridView;
            if (e.RowHandle < 0) return;

            object blocked = view.GetRowCellValue(e.RowHandle, "BlockedReason");
            if (blocked != null && blocked != DBNull.Value && blocked.ToString().Length > 0)
            {
                e.Appearance.ForeColor = Color.Gray;
                e.Appearance.Font = new Font(e.Appearance.Font, FontStyle.Strikeout);
            }
        }

        // ── VIEW DETAILS (inline GL-entries grid, same pattern as AddExpenseDevExFrm's
        // Posted Expenses tab: gridControlPosted on top, gridControlPostedDetails
        // below) ────────────────────────────────────────────────────────
        private void BtnViewDetails_Click(object sender, EventArgs e)
        {
            if (gridView9.FocusedRowHandle < 0)
            {
                XtraMessageBox.Show("Select a payment first.");
                return;
            }

            int paymentHeaderId = Convert.ToInt32(gridView9.GetFocusedRowCellValue("PaymentHeaderID"));

            DataTable header, glEntries, lines;
            if (!TryLoadPaymentDetails(paymentHeaderId, out header, out glEntries, out lines))
                return;

            if (header.Rows.Count == 0)
            {
                XtraMessageBox.Show("Payment header not found.");
                return;
            }

            gridControlPaymentDetails.DataSource = glEntries;
            gridViewPaymentDetails.PopulateColumns();
            if (gridViewPaymentDetails.Columns["Debit"] != null)
                gridViewPaymentDetails.Columns["Debit"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "Debit", "{0:n2}");
            if (gridViewPaymentDetails.Columns["Credit"] != null)
                gridViewPaymentDetails.Columns["Credit"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "Credit", "{0:n2}");
            gridViewPaymentDetails.BestFitColumns();
        }

        bool TryLoadPaymentDetails(int paymentHeaderId, out DataTable header, out DataTable glEntries, out DataTable lines)
            => TryLoadPaymentDetails(paymentHeaderId, out header, out glEntries, out lines, out _);

        // [104] set 4 = the payment's Other Collections lines (empty on a database without [104])
        bool TryLoadPaymentDetails(int paymentHeaderId, out DataTable header, out DataTable glEntries, out DataTable lines, out DataTable others)
        {
            header = new DataTable();
            glEntries = new DataTable();
            lines = new DataTable();
            others = new DataTable();
            try
            {
                using (SqlConnection con = Database.getConnection())
                using (SqlCommand cmd = new SqlCommand("sp_GetClientPaymentDetails", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@PaymentHeaderID", SqlDbType.Int).Value = paymentHeaderId;

                    con.Open();
                    using (SqlDataAdapter da = new SqlDataAdapter(cmd))
                    {
                        DataSet ds = new DataSet();
                        da.Fill(ds);
                        if (ds.Tables.Count > 0) header = ds.Tables[0];
                        if (ds.Tables.Count > 1) glEntries = ds.Tables[1];
                        if (ds.Tables.Count > 2) lines = ds.Tables[2];
                        if (ds.Tables.Count > 3) others = ds.Tables[3];
                    }
                }
                return true;
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load payment details: {ex.Message}", "Error",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return false;
            }
        }

        // ── EDIT DETAILS (reverse + re-enter as a new payment) ────────────
        // A Client Payment IS the thing that touches TransactionChargeSales/
        // ClientLedger/TicketMaster/BankStatementRecon the moment
        // sp_AddPaymentClient runs, so per Known Bug Pattern #4 this can't be
        // a delete-and-repost in place - it has to go through the reversal
        // SP first. sp_ReversePaymentClient already exists and is tested; it
        // just wasn't wired to any screen yet. After reversing, the affected
        // invoice(s) go back to having a real balance, so re-showing the
        // Invoice w/Balances tab and pre-filling from the reversed values is
        // enough - no separate "SaveEdit" SP is needed, Confirm Payment posts
        // the correction the same way it posts any new payment.
        private void BtnEditDetails_Click(object sender, EventArgs e)
        {
            if (gridView9.FocusedRowHandle < 0)
            {
                XtraMessageBox.Show("Select a payment first.");
                return;
            }

            object blockedObj = gridView9.GetFocusedRowCellValue("BlockedReason");
            string blockedReason = (blockedObj == null || blockedObj == DBNull.Value) ? null : blockedObj.ToString();
            if (!string.IsNullOrEmpty(blockedReason))
            {
                XtraMessageBox.Show(blockedReason, "Cannot Edit", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            int paymentHeaderId = Convert.ToInt32(gridView9.GetFocusedRowCellValue("PaymentHeaderID"));
            string referenceNo = gridView9.GetFocusedRowCellValue("ReferenceNo")?.ToString();
            decimal totalAmount = Convert.ToDecimal(gridView9.GetFocusedRowCellValue("TotalAmount") ?? 0m);

            if (!HelperFunction.ConfirmDialog(
                $"This will reverse payment {referenceNo} ({totalAmount:N2}) and let you re-enter the corrected details as a new payment. Continue?",
                "Edit Payment"))
                return;

            DataTable header, glEntries, lines, others;
            if (!TryLoadPaymentDetails(paymentHeaderId, out header, out glEntries, out lines, out others))
                return;
            if (header.Rows.Count == 0)
            {
                XtraMessageBox.Show("Payment header not found.");
                return;
            }

            try
            {
                using (SqlConnection con = Database.getConnection())
                using (SqlCommand cmd = new SqlCommand("sp_ReversePaymentClient", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@PaymentHeaderID", SqlDbType.Int).Value = paymentHeaderId;
                    cmd.Parameters.Add("@ReversedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    con.Open();
                    cmd.ExecuteNonQuery();
                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Reversal failed:\n{ex.Message}", "Error",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            // The reversal above already committed - it cannot be undone from
            // here. Everything past this point is just refreshing the UI, so
            // a failure here must not look like the reversal itself failed;
            // tell the user plainly that the payment IS reversed regardless.
            try
            {
                xtraTabControl1.SelectedTabPage = xtraTabPage1;
                display();
                RefreshAvailableCredit();
                PrefillOtherLines(others);   // [104] before the invoices: a credit closed to Other Income needs the line's room
                PrefillEntryFromReversedPayment(header.Rows[0], lines);
                LoadPostedClientPayments();

                XtraMessageBox.Show(
                    $"Payment {referenceNo} has been reversed. Review the corrected details below and click Confirm Payment to repost.",
                    "Reversed — Ready for Correction", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(
                    $"Payment {referenceNo} WAS reversed successfully, but the screen could not be refreshed automatically:\n{ex.Message}\n\n" +
                    "Please re-select the invoice(s) manually on the Invoice w/Balances tab.",
                    "Reversed — Manual Refresh Needed", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        void PrefillEntryFromReversedPayment(DataRow h, DataTable lines)
        {
            string payType = h["PaymentType"]?.ToString();
            switch (payType)
            {
                case "CASH": radioButton1.Checked = true; break;
                case "CHECK": radioButton2.Checked = true; break;
                case "ONLINE": radioButton3.Checked = true; break;
                //case "ADVANCEPAYMENT": radioButton4.Checked = true; break;
                case "CREDITCARD": radCreditCard.Checked = true; break;
            }

            txtcontrolno.Text = h["ControlNo"]?.ToString();
            txtcrno.Text = h["CRNo"]?.ToString();
            txtremakrs.Text = h["Remarks"]?.ToString();
            if (h["PaymentDate"] != DBNull.Value)
                txtdate.EditValue = Convert.ToDateTime(h["PaymentDate"]);
            txtdebitglcode.Text = h["DebitGLCode"]?.ToString();
            txtcreditglcode.Text = h["CreditGLCode"]?.ToString();

            if (payType == "CHECK")
            {
                if (h["CheckNo"] != DBNull.Value) txtchecknum.Text = h["CheckNo"].ToString();
                if (h["CheckName"] != DBNull.Value) txtcheckname.Text = h["CheckName"].ToString();
                if (h["CheckBankName"] != DBNull.Value) txtcheckbankname.Text = h["CheckBankName"].ToString();
                if (h["CheckAmount"] != DBNull.Value) txtcheckamount.Text = Convert.ToDecimal(h["CheckAmount"]).ToString("N2");
                if (h["CheckDate"] != DBNull.Value) txtcheckdate.EditValue = Convert.ToDateTime(h["CheckDate"]);
            }
            else if (payType == "ONLINE")
            {
                if (h["BankRefNumber"] != DBNull.Value) txtrefnoonline.Text = h["BankRefNumber"].ToString();
                if (h["BankName"] != DBNull.Value) txtdepbankonline.Text = h["BankName"].ToString();
                if (h["DateDeposit"] != DBNull.Value) txtdatedeponline.EditValue = Convert.ToDateTime(h["DateDeposit"]);
            }

            // CellValueChanged is unhooked for this loop - gridView2's handler
            // resets EWT/Discount/Offset/OverPay/OverPayIncome to 0 and
            // AmountPaid=Balance the moment Pay flips true, then
            // RecalculateRow recomputes AmountPaid again after each
            // subsequent SetRowCellValue. Letting that cascade run mid-loop
            // only produced the right end result by accident of field
            // ordering; writing all values first and recalculating once
            // after is the same approach RecalculateRow's own comment
            // already documents as necessary in this DevExpress version.
            gridView2.CellValueChanged -= gridView2_CellValueChanged;
            var notFound = new List<string>();
            try
            {
                foreach (DataRow line in lines.Rows)
                {
                    string invoiceNo = line["InvoiceNo"]?.ToString()?.Trim();
                    string orderNo = line["OrderNo"]?.ToString()?.Trim();
                    // [80] 2026-10-14: match invoice no. AND PO. One invoice no. can have several rows (a returned PO
                    // re-invoiced under the same no.); locating by invoice no. alone pre-filled the first one, and on
                    // 10-08 a re-entered payment was posted on the returned row (C-048113) instead of the real invoice.
                    int rowHandle = FindInvoiceRow(invoiceNo, orderNo);
                    if (rowHandle == DevExpress.XtraGrid.GridControl.InvalidRowHandle)
                    {
                        notFound.Add(string.IsNullOrEmpty(orderNo) ? invoiceNo : $"{invoiceNo} (PO {orderNo})");
                        continue;
                    }

                    gridView2.SetRowCellValue(rowHandle, "Pay", true);
                    gridView2.SetRowCellValue(rowHandle, "EWTAmount", DBNullToDecimal(line["EWTAmount"]));
                    gridView2.SetRowCellValue(rowHandle, "DiscountAmount", DBNullToDecimal(line["DiscountAmount"]));
                    gridView2.SetRowCellValue(rowHandle, "OffsetAmount", DBNullToDecimal(line["OffsetAmount"]));
                    gridView2.SetRowCellValue(rowHandle, "OverPay", DBNullToDecimal(line["OverPay"]));
                    gridView2.SetRowCellValue(rowHandle, "OverPayIncome", DBNullToDecimal(line["OverPayIncome"]));
                    gridView2.SetRowCellValue(rowHandle, "ServicesAmount", DBNullToDecimal(line["ServicesAmount"]));
                    gridView2.SetRowCellValue(rowHandle, "AmountPaid", DBNullToDecimal(line["SuggestedAmountPaid"]));
                }
            }
            finally
            {
                gridView2.CellValueChanged += gridView2_CellValueChanged;
            }

            ComputeTotal();

            if (notFound.Count > 0)
                XtraMessageBox.Show(
                    "The following invoice(s) from the reversed payment are no longer in the outstanding list " +
                    "(may have since been settled by another payment) and were not pre-filled:\n\n" +
                    string.Join(", ", notFound),
                    "Some Invoices Not Pre-filled", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        // [104] the reversed payment's Other Collections lines back on their tab. An account no longer on the list can't
        // show in the dropdown: its code goes into the remarks and the account is left blank, so Confirm asks for one.
        void PrefillOtherLines(DataTable others)
        {
            ClearOtherLines();
            if (others == null || !others.Columns.Contains("AccountCode")) return;
            foreach (DataRow o in others.Rows)
            {
                string acct = o["AccountCode"]?.ToString()?.Trim();
                string remarks = o["Remarks"]?.ToString();
                if (OtherAccountDescription(acct) == null)
                {
                    remarks = $"(was {acct}, no longer on the list) {remarks}";
                    if (remarks.Length > 50) remarks = remarks.Substring(0, 50);
                    acct = null;
                }
                otherLines.Rows.Add(acct, DBNullToDecimal(o["Amount"]), remarks);
            }
            if (otherLines.Rows.Count > 0)
                tabEntry.SelectedTabPage = pageOther;
        }

        // [80] the grid row of one invoice: invoice no. AND PO (OrderNo), never the invoice no. alone
        int FindInvoiceRow(string invoiceNo, string orderNo)
        {
            for (int i = 0; i < gridView2.RowCount; i++)
            {
                if (string.Equals(gridView2.GetRowCellValue(i, "InvoiceNo")?.ToString()?.Trim(), invoiceNo, StringComparison.OrdinalIgnoreCase)
                    && string.Equals(gridView2.GetRowCellValue(i, "OrderNo")?.ToString()?.Trim(), orderNo, StringComparison.OrdinalIgnoreCase))
                    return i;
            }
            return DevExpress.XtraGrid.GridControl.InvalidRowHandle;
        }

        static decimal DBNullToDecimal(object value) =>
            (value == null || value == DBNull.Value) ? 0m : Convert.ToDecimal(value);

        // ── HISTORY SEARCH ──────────────────────────────────────────────
        // [BUG-4] FIX: was raw string concatenation (SQL injection risk).
        // Now uses parameterized query.
        private void simpleButton1_Click_1(object sender, EventArgs e)
        {
            //using (SqlConnection con = Database.getConnection())
            //using (SqlCommand cmd = new SqlCommand(@"
            //    SELECT TransactionDate, CustomerKey, ReferenceNo,
            //           TotalAmount, AmountPaid, Balance, PayStatus
            //    FROM TransactionChargeSales
            //    WHERE CAST(TransactionDate AS DATE) BETWEEN @from AND @to
            //      AND CustomerKey = @custkey
            //      AND Balance = 0", con))
            //{
            //    cmd.Parameters.Add("@from", SqlDbType.Date).Value = Convert.ToDateTime(txtdatefrom.Text);
            //    cmd.Parameters.Add("@to", SqlDbType.Date).Value = Convert.ToDateTime(txtdateto.Text);
            //    cmd.Parameters.Add("@custkey", SqlDbType.Char, 8).Value = custkey;

            //    DataTable table = new DataTable();
            //    con.Open();
            //    using (SqlDataReader dr = cmd.ExecuteReader())
            //        table.Load(dr);

            //    gridControl1.DataSource = table;
            //    gridView9.BestFitColumns();
            //}
            LoadPostedClientPayments();
        }

        private void simpleButton2_Click(object sender, EventArgs e) { /* reserved */ }

        private void gridControl1_ViewRegistered(object sender, DevExpress.XtraGrid.ViewOperationEventArgs e)
        {
            GridView view = e.View as GridView;
            if (view == null) return;

            // ✅ Apply to ALL views (master + detail)
            view.OptionsView.ColumnAutoWidth = false;
            view.OptionsView.RowAutoHeight = true;
            view.OptionsBehavior.ReadOnly = true;
            view.OptionsBehavior.Editable = false;

            view.PopulateColumns();
            view.BestFitColumns();
        }

        private void gridView9_MasterRowExpanded(object sender, CustomMasterRowEventArgs e)
        {
            GridView masterView = sender as GridView;

            // ✅ Get actual detail view
            GridView detailView = masterView.GetDetailView(e.RowHandle, e.RelationIndex) as GridView;

            if (detailView != null)
            {
                detailView.OptionsView.ColumnAutoWidth = false;
                detailView.PopulateColumns();

                // ✅ SHOW FOOTER
                detailView.OptionsView.ShowFooter = true;

                // ✅ Footer styling
                detailView.Appearance.FooterPanel.BackColor = Color.LightYellow;
                detailView.Appearance.FooterPanel.ForeColor = Color.Black;
                detailView.Appearance.FooterPanel.Font = new Font("Segoe UI", 9, FontStyle.Bold);

                // ✅ ADD SUM FOR DEBIT
                if (detailView.Columns["TotalAmount"] != null)
                {
                    detailView.Columns["TotalAmount"].Summary.Clear();
                    detailView.Columns["TotalAmount"].Summary.Add(
                        DevExpress.Data.SummaryItemType.Sum,
                        "TotalAmount",
                        "Total: {0:n2}"
                    );
                }

                // ✅ ADD SUM FOR CREDIT
                if (detailView.Columns["EWTAmount"] != null)
                {
                    detailView.Columns["EWTAmount"].Summary.Clear();
                    detailView.Columns["EWTAmount"].Summary.Add(
                        DevExpress.Data.SummaryItemType.Sum,
                        "EWTAmount",
                        "Total: {0:n2}"
                    );
                }

                detailView.BestFitColumns();

                //// ✅ HIDE COLUMNS
                //detailView.Columns["BranchCode"].Visible = false;
                //detailView.Columns["TicketDate"].Visible = false;
                //detailView.Columns["TicketNumber"].Visible = false;
                //detailView.Columns["ReferenceNumber"].Visible = false;
                //detailView.Columns["ReferenceKey"].Visible = false;

                // ✅ MIN WIDTH FOR DETAIL
                foreach (DevExpress.XtraGrid.Columns.GridColumn col in detailView.Columns)
                {
                    col.MinWidth = 100;
                }

                // ✅ MIN WIDTH FOR MASTER
                foreach (DevExpress.XtraGrid.Columns.GridColumn col in gridView9.Columns)
                {
                    col.MinWidth = 100;
                }

                masterView.BestFitColumns();
            }

        }

        private void txtcustname_EditValueChanged(object sender, EventArgs e)
        {
            // 2026-10-10: the picked customer is the EditValue itself (ValueMember = CustomerKey). It used to be read
            // from the popup grid's focused row, which on the first pick after load isn't the picked row yet.
            objcustid = txtcustname.EditValue;
            if (objcustid == null || objcustid == DBNull.Value || string.IsNullOrWhiteSpace(objcustid.ToString()))
                return;

            txtcustid.Text = objcustid.ToString();

            // custkey previously only got set once, in Load(), from whatever
            // txtcustid.Text happened to be at that moment. That was fine as
            // long as this control was only ever opened by a caller that
            // pre-set txtcustid before showing it (its only prior caller);
            // now that it's reachable standalone from the Accounting Board
            // menu with no pre-set customer, picking one here has to re-key
            // every downstream query or it keeps hitting the stale/blank
            // customer from Load.
            custkey = txtcustid.Text;
            groupControl1.Text = custkey;
            ClearOtherLines();   // [104] lines typed for the previous customer must not post on this one
            display();
            ComputeTotal();
            RefreshAvailableCredit();
            if (xtraTabControl1.SelectedTabPage == xtraTabPage2)
                LoadPostedClientPayments();
        }

        private void groupBox1_Enter(object sender, EventArgs e)
        {

        }

        private void simpleButton5_Click(object sender, EventArgs e) { /* reserved */ }
        private void txtremakrs_EditValueChanged(object sender, EventArgs e) { }
        // [79] balance-forward credit rows: only Pay and AmountPaid (the credit used) can be edited, and a
        // credit can't be ticked before there is an invoice ticked for it to cover.
        private void gridView2_ShowingEditor(object sender, System.ComponentModel.CancelEventArgs e)
        {
            int row = gridView2.FocusedRowHandle;
            if (!IsCreditRow(row)) return;

            string field = gridView2.FocusedColumn?.FieldName;
            if (field == "Pay")
            {
                bool ticked = Convert.ToBoolean(gridView2.GetRowCellValue(row, "Pay"));
                if (!ticked && CreditRoom(row) <= 0)
                {
                    e.Cancel = true;
                    XtraMessageBox.Show("Tick the invoice(s) to be paid first (or add the Other Collections line that the credit closes to, e.g. Other Income), then the balance-forward credit to apply to them.",
                        "Balance-Forward Credit", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                return;
            }
            if (field != "AmountPaid")
                e.Cancel = true;
        }
        // ── DATA MODEL ───────────────────────────────────────────────────────
        class PaymentRow
        {
            public bool Pay { get; set; }
            public string InvoiceNo { get; set; }
            public string OrderNo { get; set; }
            public DateTime TransactionDate { get; set; }
            public decimal AmountPaid { get; set; }   // net cash
            public decimal EWTAmount { get; set; }
            public decimal DiscountAmount { get; set; }
            public decimal OffsetAmount { get; set; }
        }
    }
}