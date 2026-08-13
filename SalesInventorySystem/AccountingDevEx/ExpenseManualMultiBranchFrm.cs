using System;
using System.Data;
using System.Data.SqlClient;
using System.Linq;
using System.Windows.Forms;
using DevExpress.XtraEditors;

namespace SalesInventorySystem.AccountingDevEx
{
    /// <summary>
    /// Post Expense — Manual Multi-Branch (no mapping). Auto-posted
    /// (no FOR APPROVAL stage), user picks every GL line directly —
    /// same freedom as Manual JV Multi-Branch, tagged to a Supplier/
    /// InvoiceNo/Date for AP tracking. Modeled closely on
    /// ManualJournalVoucherMultiBranchFrm's structure.
    ///
    /// PAYMENT-SIDE SETTLEMENT NOT YET WIRED for this posting mode
    /// (ExpenseSummary.PostingMode = 'MULTI-MANUAL') — see chat.
    /// </summary>
    public partial class ExpenseManualMultiBranchFrm : DevExpress.XtraEditors.XtraUserControl
    {
        private DataTable _linesTable;
        private string _selectedPostedRefNo, _selectedPostedInvoiceNo, _selectedPostedSupplierId;
        private bool _isEditMode = false;
        private bool _dataLoaded = false;
        private string _editingOldInvoiceNo;
        private string _editingOldSupplierId;

        public ExpenseManualMultiBranchFrm()
        {
            InitializeComponent();
        }

        public void LoadData()
        {
            if (_dataLoaded) return;
            _dataLoaded = true;
            InitializeForm();
        }

        private void ExpenseManualMultiBranchFrm_Load(object sender, EventArgs e)
        {
            // Safety net only — LoadData() is the real trigger, called
            // explicitly by whatever hosts this control (this is a new,
            // not-yet-hosted form, so its actual hosting pattern isn't
            // confirmed — see the AddExpenseDevExFrm bug earlier this
            // session for why this matters). The _dataLoaded guard means
            // whichever fires first wins and the other becomes a no-op.
            if (_dataLoaded) return;
            _dataLoaded = true;
            InitializeForm();
        }

        private void InitializeForm()
        {
            BindBranchLookups();
            BindAccountCodeLookup();
            BindSupplierLookup();

            _linesTable = new DataTable();
            _linesTable.Columns.Add("BranchCode", typeof(string));
            _linesTable.Columns.Add("AccountCode", typeof(string));
            _linesTable.Columns.Add("Particulars", typeof(string));
            _linesTable.Columns.Add("Debit", typeof(decimal));
            _linesTable.Columns.Add("Credit", typeof(decimal));
            gridControlLines.DataSource = _linesTable;

            gridViewLines.GroupSummary.Add(DevExpress.Data.SummaryItemType.Sum, "Debit", colDebit, "Branch Debit: {0:n2}");
            gridViewLines.GroupSummary.Add(DevExpress.Data.SummaryItemType.Sum, "Credit", colCredit, "Branch Credit: {0:n2}");

            txtDateFrom.DateTime = DateTime.Today.AddMonths(-1);
            txtDateTo.DateTime = DateTime.Today;

            ResetForNewEntry(clearRemarks: true);
        }

        private void HideExtraPopupColumns(DevExpress.XtraEditors.Controls.LookUpColumnInfoCollection columns, string keepFieldName)
        {
            foreach (DevExpress.XtraEditors.Controls.LookUpColumnInfo col in columns)
                col.Visible = (col.FieldName == keepFieldName);
        }

        private void BindBranchLookups()
        {
            DataTable dt;
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand(
                "SELECT BranchCode, BranchName, BranchCode + '-' + BranchName AS DisplayText FROM Branches ORDER BY BranchCode", con))
            using (var da = new SqlDataAdapter(cmd))
            {
                con.Open();
                dt = new DataTable();
                da.Fill(dt);
            }

            cboDefaultBranch.Properties.DataSource = dt;
            cboDefaultBranch.Properties.DisplayMember = "DisplayText";
            cboDefaultBranch.Properties.ValueMember = "BranchCode";
            cboDefaultBranch.Properties.PopulateColumns();
            cboDefaultBranch.Properties.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;
            HideExtraPopupColumns(cboDefaultBranch.Properties.Columns, "DisplayText");

            repBranchCode.DataSource = dt;
            repBranchCode.DisplayMember = "DisplayText";
            repBranchCode.ValueMember = "BranchCode";
            repBranchCode.PopulateColumns();
            repBranchCode.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;
            HideExtraPopupColumns(repBranchCode.Columns, "DisplayText");
        }

        private void BindAccountCodeLookup()
        {
            DataTable dt;
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand(
                "SELECT AccountCode, Description, AccountCode + '-' + Description AS DisplayText FROM ChartOfAccounts ORDER BY AccountCode", con))
            using (var da = new SqlDataAdapter(cmd))
            {
                con.Open();
                dt = new DataTable();
                da.Fill(dt);
            }

            repAccountCode.DataSource = dt;
            repAccountCode.DisplayMember = "DisplayText";
            repAccountCode.ValueMember = "AccountCode";
        }

        private void BindSupplierLookup()
        {
            Database.displaySearchlookupEdit(
                @"SELECT SupplierKey, SupplierID, SupplierName,
                         SupplierKey + ' - ' + SupplierName AS SupplierDisplay
                  FROM Supplier",
                cboSupplier, "SupplierDisplay", "SupplierKey");
        }

        // ── New entry / reset ────────────────────────────────────
        private void ResetForNewEntry(bool clearRemarks)
        {
            _isEditMode = false;
            lblEditNotice.Visible = false;
            btnPost.Text = "Post";
            txtReferenceNo.Properties.ReadOnly = true;
            cboSupplier.Enabled = true;
            txtInvoiceNo.Properties.ReadOnly = false;

            txtExpenseDate.EditValue = DateTime.Today;
            txtReferenceNo.Text = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");
            chkAllowCrossBranch.Checked = false;

            if (clearRemarks)
            {
                txtRemarks.Text = "";
                cboSupplier.EditValue = null;
                txtInvoiceNo.Text = "";
            }

            _linesTable.Rows.Clear();
            AddLine();
            AddLine();

            UpdateTotals();
        }

        private void AddLine()
        {
            DataRow row = _linesTable.NewRow();
            row["Debit"] = 0m; row["Credit"] = 0m;
            row["BranchCode"] = cboDefaultBranch.EditValue?.ToString() ?? "";
            _linesTable.Rows.Add(row);
            gridViewLines.BestFitColumns();
        }

        private void BtnAddLine_Click(object sender, EventArgs e) => AddLine();

        private void BtnRemoveLine_Click(object sender, EventArgs e)
        {
            gridViewLines.DeleteSelectedRows();
            UpdateTotals();
        }

        private void ChkAllowCrossBranch_CheckedChanged(object sender, EventArgs e) => UpdateTotals();

        // ── Grid mechanics ───────────────────────────────────────
        private void GridViewLines_CustomRowCellEdit(object sender, DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "BranchCode") e.RepositoryItem = repBranchCode;
            if (e.Column.FieldName == "AccountCode") e.RepositoryItem = repAccountCode;
            if (e.Column.FieldName == "Particulars") e.RepositoryItem = repParticulars;
            if (e.Column.FieldName == "Debit") e.RepositoryItem = repDebit;
            if (e.Column.FieldName == "Credit") e.RepositoryItem = repCredit;
        }

        private void GridViewLines_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            if (e.Column.FieldName == "Debit")
            {
                decimal debit = ToDecimal(gridViewLines.GetRowCellValue(e.RowHandle, "Debit"));
                if (debit > 0) gridViewLines.SetRowCellValue(e.RowHandle, "Credit", 0m);
            }
            if (e.Column.FieldName == "Credit")
            {
                decimal credit = ToDecimal(gridViewLines.GetRowCellValue(e.RowHandle, "Credit"));
                if (credit > 0) gridViewLines.SetRowCellValue(e.RowHandle, "Debit", 0m);
            }
            UpdateTotals();
        }

        private void GridViewLines_RowCellStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowCellStyleEventArgs e)
        {
            decimal debit = ToDecimal(gridViewLines.GetRowCellValue(e.RowHandle, "Debit"));
            decimal credit = ToDecimal(gridViewLines.GetRowCellValue(e.RowHandle, "Credit"));
            string acct = gridViewLines.GetRowCellValue(e.RowHandle, "AccountCode")?.ToString();
            string branch = gridViewLines.GetRowCellValue(e.RowHandle, "BranchCode")?.ToString();

            if (string.IsNullOrWhiteSpace(acct) || string.IsNullOrWhiteSpace(branch)
                || (debit > 0 && credit > 0) || (debit == 0 && credit == 0))
                e.Appearance.BackColor = System.Drawing.Color.LightCoral;
        }

        private void UpdateTotals()
        {
            decimal totalDebit = 0, totalCredit = 0;
            for (int i = 0; i < gridViewLines.RowCount; i++)
            {
                totalDebit += ToDecimal(gridViewLines.GetRowCellValue(i, "Debit"));
                totalCredit += ToDecimal(gridViewLines.GetRowCellValue(i, "Credit"));
            }
            lblTotalDebit.Text = totalDebit.ToString("N2");
            lblTotalCredit.Text = totalCredit.ToString("N2");

            var unbalancedBranches = chkAllowCrossBranch.Checked
                ? new System.Collections.Generic.List<string>()
                : GetUnbalancedBranches();

            if (unbalancedBranches.Any())
            {
                lblBalanceStatus.Text = "Out of balance in branch(es): " + string.Join(", ", unbalancedBranches)
                    + " — check \"Allow Cross-Branch Entry\" if intentional.";
                lblBalanceStatus.Visible = true;
            }
            else if (totalDebit != totalCredit)
            {
                lblBalanceStatus.Text = $"Out of balance by {Math.Abs(totalDebit - totalCredit):N2}";
                lblBalanceStatus.Visible = true;
            }
            else
            {
                lblBalanceStatus.Text = "";
                lblBalanceStatus.Visible = false;
            }
        }

        private System.Collections.Generic.List<string> GetUnbalancedBranches()
        {
            var totals = new System.Collections.Generic.Dictionary<string, (decimal Debit, decimal Credit)>();
            for (int i = 0; i < gridViewLines.RowCount; i++)
            {
                string branch = gridViewLines.GetRowCellValue(i, "BranchCode")?.ToString();
                if (string.IsNullOrWhiteSpace(branch)) continue;
                decimal debit = ToDecimal(gridViewLines.GetRowCellValue(i, "Debit"));
                decimal credit = ToDecimal(gridViewLines.GetRowCellValue(i, "Credit"));
                if (!totals.ContainsKey(branch)) totals[branch] = (0, 0);
                totals[branch] = (totals[branch].Debit + debit, totals[branch].Credit + credit);
            }
            return totals.Where(kv => kv.Value.Debit != kv.Value.Credit).Select(kv => kv.Key).ToList();
        }

        private decimal ToDecimal(object value)
        {
            if (value == null || value == DBNull.Value) return 0m;
            decimal.TryParse(value.ToString(), out decimal result);
            return result;
        }

        // ── Post / Save ──────────────────────────────────────────
        private bool ValidateForm()
        {
            if (cboSupplier.EditValue == null)
            {
                XtraMessageBox.Show("Select a Supplier.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
            if (string.IsNullOrWhiteSpace(txtInvoiceNo.Text))
            {
                XtraMessageBox.Show("Invoice No. is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
            if (gridViewLines.RowCount < 2)
            {
                XtraMessageBox.Show("An entry needs at least two lines.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            for (int i = 0; i < gridViewLines.RowCount; i++)
            {
                string branch = gridViewLines.GetRowCellValue(i, "BranchCode")?.ToString();
                string acct = gridViewLines.GetRowCellValue(i, "AccountCode")?.ToString();
                decimal debit = ToDecimal(gridViewLines.GetRowCellValue(i, "Debit"));
                decimal credit = ToDecimal(gridViewLines.GetRowCellValue(i, "Credit"));

                if (debit == 0 && credit == 0) continue;

                if (string.IsNullOrWhiteSpace(branch))
                {
                    XtraMessageBox.Show($"Row {i + 1}: Branch is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
                if (string.IsNullOrWhiteSpace(acct))
                {
                    XtraMessageBox.Show($"Row {i + 1}: Account Code is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
                if (debit > 0 && credit > 0)
                {
                    XtraMessageBox.Show($"Row {i + 1}: enter an amount in either Debit or Credit, not both.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
            }

            if (!chkAllowCrossBranch.Checked)
            {
                var unbalanced = GetUnbalancedBranches();
                if (unbalanced.Any())
                {
                    XtraMessageBox.Show(
                        "Entry does not balance per branch. Out-of-balance branch(es): " + string.Join(", ", unbalanced)
                        + "\nCheck \"Allow Cross-Branch Entry\" if this is intentional.",
                        "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
            }

            decimal totalDebit = decimal.Parse(lblTotalDebit.Text);
            if (totalDebit <= 0)
            {
                XtraMessageBox.Show("Entry total must be greater than zero.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            return true;
        }

        private DataTable BuildLinesTVP()
        {
            var dt = new DataTable();
            dt.Columns.Add("BranchCode", typeof(string));
            dt.Columns.Add("AccountCode", typeof(string));
            dt.Columns.Add("Debit", typeof(decimal));
            dt.Columns.Add("Credit", typeof(decimal));
            dt.Columns.Add("Particulars", typeof(string));

            for (int i = 0; i < gridViewLines.RowCount; i++)
            {
                string branch = gridViewLines.GetRowCellValue(i, "BranchCode")?.ToString();
                string acct = gridViewLines.GetRowCellValue(i, "AccountCode")?.ToString();
                string particulars = gridViewLines.GetRowCellValue(i, "Particulars")?.ToString() ?? "";
                decimal debit = ToDecimal(gridViewLines.GetRowCellValue(i, "Debit"));
                decimal credit = ToDecimal(gridViewLines.GetRowCellValue(i, "Credit"));

                if (string.IsNullOrWhiteSpace(acct) || string.IsNullOrWhiteSpace(branch) || (debit == 0 && credit == 0))
                    continue;

                // Defensive: catch a bad BranchCode HERE, with a row
                // number the user can act on, instead of a generic SQL
                // truncation error after the round-trip
                if (branch.Length > 5)
                {
                    throw new InvalidOperationException(
                        $"Row {i + 1}: Branch value '{branch}' looks wrong (expected a short code like '002', got the full branch name too). Please re-select the branch from the dropdown.");
                }

                dt.Rows.Add(branch, acct, debit, credit, particulars);
            }
            return dt;
        }

        private void BtnPost_Click(object sender, EventArgs e)
        {
            if (!ValidateForm()) return;

            DataTable lines;
            try
            {
                lines = BuildLinesTVP();
            }
            catch (InvalidOperationException ex)
            {
                XtraMessageBox.Show(ex.Message, "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            string spName = _isEditMode ? "sp_EditExpenseManualMultiBranch" : "sp_PostExpenseManualMultiBranch";
            string defaultMessage = _isEditMode ? "Expense updated successfully." : "Expense posted successfully.";

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand(spName, con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 60;

                    cmd.Parameters.Add("@parmrefno", SqlDbType.VarChar, 20).Value = txtReferenceNo.Text.Trim();
                    if(_isEditMode)
                    {
                        cmd.Parameters.Add("@parmoldinvoiceno", SqlDbType.VarChar, 150).Value = _editingOldInvoiceNo;
                        cmd.Parameters.Add("@parmoldsupplierid", SqlDbType.VarChar, 20).Value = _editingOldSupplierId;
                    }
                    cmd.Parameters.Add("@parminvoiceno", SqlDbType.VarChar, 150).Value = txtInvoiceNo.Text.Trim();
                    cmd.Parameters.Add("@parmsupplierid", SqlDbType.VarChar, 20).Value = cboSupplier.EditValue.ToString();
                    cmd.Parameters.Add("@parmexpensedate", SqlDbType.Date).Value = txtExpenseDate.DateTime;
                    cmd.Parameters.Add("@parmremarks", SqlDbType.VarChar, 500).Value = txtRemarks.Text.Trim();
                    cmd.Parameters.Add("@parmuser", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    cmd.Parameters.Add("@AllowCrossBranch", SqlDbType.Bit).Value = chkAllowCrossBranch.Checked;

                    var tvpParam = cmd.Parameters.AddWithValue("@Lines", lines);
                    tvpParam.SqlDbType = SqlDbType.Structured;
                    tvpParam.TypeName = "dbo.ExpenseManualLineTVP";

                    con.Open();
                    string message = defaultMessage;
                    using (var rdr = cmd.ExecuteReader())
                        if (rdr.Read()) message = rdr["Message"]?.ToString() ?? message;

                    XtraMessageBox.Show(message, "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }

                ResetForNewEntry(clearRemarks: true);
                LoadPostedExpenses();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"{(_isEditMode ? "Update" : "Post")} failed:\n{ex.Message}",
                    "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void BtnClose_Click(object sender, EventArgs e) => ResetForNewEntry(clearRemarks: true);// Dispose();

        // ── Posted Expenses tab ──────────────────────────────────
        private void TabMain_SelectedPageChanged(object sender, DevExpress.XtraTab.TabPageChangedEventArgs e)
        {
            if (e.Page == tabPosted && gridControlPosted.DataSource == null)
                LoadPostedExpenses();
        }

        private void BtnRefreshPosted_Click(object sender, EventArgs e) => LoadPostedExpenses();

        private void LoadPostedExpenses()
        {
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_GetPostedExpenseManualMultiBranch", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value =
                        txtDateFrom.EditValue == null ? (object)DBNull.Value : txtDateFrom.DateTime;
                    cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value =
                        txtDateTo.EditValue == null ? (object)DBNull.Value : txtDateTo.DateTime;

                    var dt = new DataTable();
                    con.Open();
                    new SqlDataAdapter(cmd).Fill(dt);
                    gridControlPosted.DataSource = dt;
                }

                gridViewPosted.BestFitColumns();
                if (gridViewPosted.Columns["SupplierID"] != null) gridViewPosted.Columns["SupplierID"].Visible = false;

                gridControlPostedDetails.DataSource = null;
                btnViewDetails.Enabled = false;
                btnCopyToNew.Enabled = false;
                btnEditVoucher.Enabled = false;
                _selectedPostedRefNo = null;
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load posted expenses: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void GridViewPosted_FocusedRowChanged(object sender, DevExpress.XtraGrid.Views.Base.FocusedRowChangedEventArgs e)
        {
            bool has = gridViewPosted.FocusedRowHandle >= 0;
            btnViewDetails.Enabled = has;
            btnCopyToNew.Enabled = has;
            btnEditVoucher.Enabled = has;   // real eligibility checked in BtnEditVoucher_Click via BlockedReason

            if (has)
            {
                _selectedPostedRefNo = gridViewPosted.GetFocusedRowCellValue("ReferenceNumber")?.ToString();
                _selectedPostedInvoiceNo = gridViewPosted.GetFocusedRowCellValue("InvoiceNo")?.ToString();
                _selectedPostedSupplierId = gridViewPosted.GetFocusedRowCellValue("SupplierID")?.ToString();
            }
            else
            {
                _selectedPostedRefNo = _selectedPostedInvoiceNo = _selectedPostedSupplierId = null;
            }
        }

        private void GridViewPosted_DoubleClick(object sender, EventArgs e)
        {
            if (gridViewPosted.FocusedRowHandle >= 0) LoadSelectedDetails();
        }

        private void BtnViewDetails_Click(object sender, EventArgs e) => LoadSelectedDetails();

        private (DataTable header, DataTable lines) FetchDetails()
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("sp_GetExpenseManualMultiBranchDetails", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@ReferenceNumber", SqlDbType.VarChar, 20).Value = _selectedPostedRefNo;
                cmd.Parameters.Add("@InvoiceNo", SqlDbType.VarChar, 150).Value = _selectedPostedInvoiceNo;
                cmd.Parameters.Add("@SupplierID", SqlDbType.VarChar, 20).Value = _selectedPostedSupplierId;

                con.Open();
                using (var da = new SqlDataAdapter(cmd))
                {
                    var ds = new DataSet();
                    da.Fill(ds);
                    var header = ds.Tables.Count > 0 ? ds.Tables[0] : new DataTable();
                    var lines = ds.Tables.Count > 1 ? ds.Tables[1] : new DataTable();
                    return (header, lines);
                }
            }
        }

        private void LoadSelectedDetails()
        {
            if (string.IsNullOrEmpty(_selectedPostedRefNo)) return;

            try
            {
                var (header, lines) = FetchDetails();
                gridControlPostedDetails.DataSource = lines;
                gridViewPostedDetails.BestFitColumns();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load details: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void BtnCopyToNew_Click(object sender, EventArgs e)
        {
            if (string.IsNullOrEmpty(_selectedPostedRefNo)) return;

            DataTable lines;
            try
            {
                var result = FetchDetails();
                lines = result.lines;
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load expense for copying: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            if (lines.Rows.Count == 0)
            {
                XtraMessageBox.Show("This expense has no lines to copy.", "Nothing to Copy", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            // Fresh Reference No — Supplier/Invoice deliberately NOT
            // carried over, since a copy is a new AP transaction, not
            // a duplicate of the same invoice
            ResetForNewEntry(clearRemarks: true);
            _linesTable.Rows.Clear();

            foreach (DataRow src in lines.Rows)
            {
                DataRow row = _linesTable.NewRow();
                row["BranchCode"] = src["BranchCode"];
                row["AccountCode"] = src["AccountCode"];
                row["Particulars"] = src["Particulars"];
                row["Debit"] = src["Debit"];
                row["Credit"] = src["Credit"];
                _linesTable.Rows.Add(row);
            }

            gridViewLines.BestFitColumns();
            UpdateTotals();
            tabMain.SelectedTabPage = tabNew;

            XtraMessageBox.Show(
                $"Copied {lines.Rows.Count} line(s) from {_selectedPostedRefNo}.\nA new Reference No. was assigned — fill in Supplier/Invoice and review before posting.",
                "Copied", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private void BtnEditVoucher_Click(object sender, EventArgs e)
        {
            if (string.IsNullOrEmpty(_selectedPostedRefNo)) return;

            DataTable header, lines;
            try
            {
                var result = FetchDetails();
                header = result.header;
                lines = result.lines;
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load expense for editing: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            if (header.Rows.Count == 0)
            {
                XtraMessageBox.Show("Expense not found.", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            var h = header.Rows[0];
            string blockedReason = h["BlockedReason"] == DBNull.Value ? null : h["BlockedReason"].ToString();
            if (!string.IsNullOrEmpty(blockedReason))
            {
                XtraMessageBox.Show(blockedReason, "Cannot Edit", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            if (lines.Rows.Count == 0)
            {
                XtraMessageBox.Show("This expense has no lines to edit.", "Nothing to Edit", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            _isEditMode = true;
            _editingOldInvoiceNo = h["InvoiceNo"].ToString();
            _editingOldSupplierId = h["SupplierID"].ToString();

            txtReferenceNo.Text = h["ReferenceNumber"].ToString();
            txtInvoiceNo.Text = _editingOldInvoiceNo;      // editable now — just pre-filled
            cboSupplier.EditValue = _editingOldSupplierId;  // editable now — just pre-filled

            txtExpenseDate.EditValue = Convert.ToDateTime(h["ExpenseDate"]);
            txtRemarks.Text = h["Remarks"]?.ToString() ?? "";
            chkAllowCrossBranch.Checked = false;        // re-check manually if this was a cross-branch entry

            _linesTable.Rows.Clear();
            foreach (DataRow src in lines.Rows)
            {
                DataRow row = _linesTable.NewRow();
                row["BranchCode"] = src["BranchCode"];
                row["AccountCode"] = src["AccountCode"];

                row["Particulars"] = src["Particulars"];
                row["Debit"] = src["Debit"];
                row["Credit"] = src["Credit"];
                _linesTable.Rows.Add(row);
            }
            gridViewLines.BestFitColumns();
            UpdateTotals();

            btnPost.Text = "Save Changes";
            lblEditNotice.Text = $"Editing expense {txtReferenceNo.Text} / Invoice {txtInvoiceNo.Text} — Reference No. cannot change. Saving replaces the original posting entirely (old tickets retired, fresh ones issued).";
            lblEditNotice.Visible = true;

            tabMain.SelectedTabPage = tabNew;
        }
    }
}