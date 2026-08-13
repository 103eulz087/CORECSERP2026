using System;
using System.Data;
using System.Data.SqlClient;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;
using DevExpress.XtraEditors;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class ManualJournalVoucherMultiBranchFrm : DevExpress.XtraEditors.XtraUserControl
    {
        private DataTable _linesTable;
        private string _selectedPostedRefNo;
        private bool _isEditMode = false;

        public ManualJournalVoucherMultiBranchFrm()
        {
            InitializeComponent();
        }
        private bool _dataLoaded = false;
        public void LoadData()
        {
            if (_dataLoaded)
                return;

            BindAccountCodeLookup();
            BindBranchLookups();

            _dataLoaded = true;
        }
        private void ManualJournalVoucherMultiBranchFrm_Load(object sender, EventArgs e)
        {
           

            _linesTable = new DataTable();
            _linesTable.Columns.Add("BranchCode", typeof(string));
            _linesTable.Columns.Add("AccountCode", typeof(string));

            _linesTable.Columns.Add("Particulars", typeof(string));
            _linesTable.Columns.Add("Debit", typeof(decimal));
            _linesTable.Columns.Add("Credit", typeof(decimal));
            gridControlLines.DataSource = _linesTable;

            gridViewLines.GroupSummary.Add(DevExpress.Data.SummaryItemType.Sum, "Debit", colDebit, "Branch Debit: {0:n2}");
            gridViewLines.GroupSummary.Add(DevExpress.Data.SummaryItemType.Sum, "Credit", colCredit, "Branch Credit: {0:n2}");

            ResetForNewEntry(clearRemarks: true);
        }

        // Fresh Reference No + today's Voucher Date, empty grid with two
        // starter rows. Used on initial load AND after "Copy to New Entry"
        // resets the identifiers before the copied lines are added.
        private void ResetForNewEntry(bool clearRemarks)
        {
            txtVoucherDate.EditValue = DateTime.Today;
            txtReferenceNo.Text = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");
            chkAllowCrossBranch.Checked = false;

            if (clearRemarks) txtRemarks.Text = "";
            txtcontrolno.Text = "";

            _linesTable.Rows.Clear();
            AddLine();
            AddLine();

            UpdateTotals();
        }

        // Combined "Code-Name" display text, computed in SQL so it's a
        // single column DisplayMember can point at. Binds both the header
        // combo and the grid's repository item from one query.
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

            // Header combo (standalone LookUpEdit)
            cboDefaultBranch.Properties.DataSource = dt;
            cboDefaultBranch.Properties.DisplayMember = "DisplayText";
            cboDefaultBranch.Properties.ValueMember = "BranchCode";
            cboDefaultBranch.Properties.PopulateColumns();
            HideExtraPopupColumns(cboDefaultBranch.Properties.Columns, "DisplayText");

            // Grid repository item
            repBranchCode.DataSource = dt;
            repBranchCode.DisplayMember = "DisplayText";
            repBranchCode.ValueMember = "BranchCode";
            repBranchCode.PopulateColumns();
            HideExtraPopupColumns(repBranchCode.Columns, "DisplayText");
        }

        private void BindAccountCodeLookup()
        {
            DataTable dt;
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand(
                "SELECT AccountCode, Description, AccountCode + '-' + Description AS DisplayText FROM ChartOfAccounts WHERE AccountType='D' ORDER BY AccountCode", con))
            using (var da = new SqlDataAdapter(cmd))
            {
                con.Open();
                dt = new DataTable();
                da.Fill(dt);
            }

            repAccountCode.DataSource = dt;
            repAccountCode.DisplayMember = "DisplayText";
            repAccountCode.ValueMember = "AccountCode";
            // SearchLookUpEdit's popup is a full grid — keep all three
            // columns visible here since the search box filters across
            // them, unlike the plain LookUpEdit dropdowns above.
        }

        // Keeps only the combined DisplayText column visible in a
        // LookUpEdit's popup grid, hiding the raw source columns.
        private void HideExtraPopupColumns(DevExpress.XtraEditors.Controls.LookUpColumnInfoCollection columns, string keepFieldName)
        {
            foreach (DevExpress.XtraEditors.Controls.LookUpColumnInfo col in columns)
                col.Visible = (col.FieldName == keepFieldName);
        }

        private void btnAddLine_Click(object sender, EventArgs e)
        {
            AddLine();
        }

        private void AddLine()
        {
            DataRow row = _linesTable.NewRow();
            row["Debit"] = 0m;
            row["Credit"] = 0m;
            // Pre-fill from the header's default branch — still editable per row
            row["BranchCode"] = cboDefaultBranch.EditValue?.ToString() ?? "";
            _linesTable.Rows.Add(row);
            gridViewLines.BestFitColumns();
        }

        private void btnRemoveLine_Click(object sender, EventArgs e)
        {
            gridViewLines.DeleteSelectedRows();
            UpdateTotals();
        }

        private void gridViewLines_CustomRowCellEdit(object sender, DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "BranchCode") e.RepositoryItem = repBranchCode;
            if (e.Column.FieldName == "AccountCode") e.RepositoryItem = repAccountCode;

            if (e.Column.FieldName == "Particulars") e.RepositoryItem = repParticulars;
            if (e.Column.FieldName == "Debit") e.RepositoryItem = repDebit;
            if (e.Column.FieldName == "Credit") e.RepositoryItem = repCredit;
        }

        private void gridViewLines_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
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

        private void gridViewLines_RowCellStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowCellStyleEventArgs e)
        {
            decimal debit = ToDecimal(gridViewLines.GetRowCellValue(e.RowHandle, "Debit"));
            decimal credit = ToDecimal(gridViewLines.GetRowCellValue(e.RowHandle, "Credit"));
            string acct = gridViewLines.GetRowCellValue(e.RowHandle, "AccountCode")?.ToString();
            string branch = gridViewLines.GetRowCellValue(e.RowHandle, "BranchCode")?.ToString();

            if (string.IsNullOrWhiteSpace(acct) || string.IsNullOrWhiteSpace(branch)
                || (debit > 0 && credit > 0) || (debit == 0 && credit == 0))
            {
                e.Appearance.BackColor = System.Drawing.Color.LightCoral;
            }
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

            // Per-branch check only drives the warning when cross-branch
            // entry is OFF — the grand-total check always applies either way.
            var unbalancedBranches = chkAllowCrossBranch.Checked
                ? new System.Collections.Generic.List<string>()
                : GetUnbalancedBranches();

            if (unbalancedBranches.Any())
            {
                lblBalanceStatus.Text = "Out of balance in branch(es): " + string.Join(", ", unbalancedBranches)
                    + " — check \"Allow Cross-Branch Entry\" if this is intentional.";
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

        private void btnPost_Click(object sender, EventArgs e)
        {
            if (!ValidateForm()) return;

            var lines = BuildLinesTVP();
            string spName = _isEditMode ? "sp_EditManualJournalVoucher" : "sp_PostManualJournalVoucherMultiBranch";
            string defaultMessage = _isEditMode ? "Journal voucher updated successfully." : "Journal voucher posted successfully.";

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand(spName, con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 60;

                    cmd.Parameters.Add("@parmrefno", SqlDbType.VarChar, 10).Value = txtReferenceNo.Text.Trim();
                    cmd.Parameters.Add("@parmcontrolno", SqlDbType.VarChar, 50).Value = txtcontrolno.Text.Trim();
                    cmd.Parameters.Add("@parmvoucherdate", SqlDbType.Date).Value = txtVoucherDate.DateTime;
                    cmd.Parameters.Add("@parmremarks", SqlDbType.VarChar, 500).Value = txtRemarks.Text.Trim();
                    cmd.Parameters.Add("@parmuser", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    cmd.Parameters.Add("@AllowCrossBranch", SqlDbType.Bit).Value = chkAllowCrossBranch.Checked;

                    var tvpParam = cmd.Parameters.AddWithValue("@Lines", lines);
                    tvpParam.SqlDbType = SqlDbType.Structured;
                    tvpParam.TypeName = "dbo.JournalVoucherLineMultiTVP";

                    con.Open();

                    string message = defaultMessage;
                    using (var rdr = cmd.ExecuteReader())
                        if (rdr.Read()) message = rdr["Message"]?.ToString() ?? message;

                    XtraMessageBox.Show(message, "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }

                ResetForNewEntry(clearRemarks: true);
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Database error ({ex.Number}): {ex.Message}",
                    _isEditMode ? "Update Failed" : "Post Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
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

                dt.Rows.Add(branch, acct, debit, credit, particulars);
            }

            return dt;
        }

        private bool ValidateForm()
        {
            if (gridViewLines.RowCount < 2)
            {
                XtraMessageBox.Show("A journal voucher needs at least two lines.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            for (int i = 0; i < gridViewLines.RowCount; i++)
            {
                string branch = gridViewLines.GetRowCellValue(i, "BranchCode")?.ToString();
                string acct = gridViewLines.GetRowCellValue(i, "AccountCode")?.ToString();
                decimal debit = ToDecimal(gridViewLines.GetRowCellValue(i, "Debit"));
                decimal credit = ToDecimal(gridViewLines.GetRowCellValue(i, "Credit"));

                if (debit == 0 && credit == 0) continue; // blank/unused row, skip

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
                    XtraMessageBox.Show($"Row {i + 1}: Enter an amount in either Debit or Credit, not both.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
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

        private void btnClose_Click(object sender, EventArgs e)
        {
            ResetForNewEntry(true);//Dispose();
        }

        // ================================================================
        // POSTED VOUCHERS TAB
        // ================================================================
        private void TabMain_SelectedPageChanged(object sender, DevExpress.XtraTab.TabPageChangedEventArgs e)
        {
            if (e.Page == tabPosted && gridControlPosted.DataSource == null)
                LoadPostedVouchers();
        }

        private void BtnRefreshPosted_Click(object sender, EventArgs e)
        {
            LoadPostedVouchers();
        }

        private void LoadPostedVouchers()
        {
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_GetPostedManualJournalVouchers", con))
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
                gridControlPostedDetails.DataSource = null;
                btnViewDetails.Enabled = false;
                btnCopyToNew.Enabled = true;
                btnEditVoucher.Enabled = false;
                _selectedPostedRefNo = null;
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load posted vouchers: {ex.Message}",
                    "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
        private void ChkAllowCrossBranch_CheckedChanged(object sender, EventArgs e)
        {
            UpdateTotals();   // re-evaluate the balance message under the new rule
        }
        private void BtnEditVoucher_Click(object sender, EventArgs e)
        {
            if (string.IsNullOrEmpty(_selectedPostedRefNo)) return;

            DataTable lines;
            string remarks;
            DateTime voucherDate;

            try
            {
                using (var con = Database.getConnection())
                {
                    con.Open();

                    using (var cmd = new SqlCommand("sp_GetManualJournalVoucherDetails", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.Add("@ReferenceNo", SqlDbType.VarChar, 10).Value = _selectedPostedRefNo;
                        lines = new DataTable();
                        new SqlDataAdapter(cmd).Fill(lines);
                    }
                }

                remarks = gridViewPosted.GetFocusedRowCellValue("Remarks")?.ToString() ?? "";
                voucherDate = Convert.ToDateTime(gridViewPosted.GetFocusedRowCellValue("VoucherDate"));
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load voucher for editing: {ex.Message}",
                    "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            if (lines.Rows.Count == 0)
            {
                XtraMessageBox.Show("This voucher has no lines to edit.", "Nothing to Edit",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            // UNLIKE Copy: keep the SAME Reference No and Voucher Date —
            // this is an edit of the existing posting, not a new one.
            string editingRefNo = _selectedPostedRefNo;

            _linesTable.Rows.Clear();
            txtRemarks.Text = remarks;
            txtVoucherDate.EditValue = voucherDate;
            txtReferenceNo.Text = editingRefNo;   // already ReadOnly=true in the Designer either way

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

            _isEditMode = true;
            btnPost.Text = "Save Changes";
            lblEditNotice.Text = $"Editing voucher {editingRefNo} — Reference No cannot change. Saving replaces the original posting entirely (old tickets retired, fresh ones issued under the same reference).";
            lblEditNotice.Visible = true;

            tabMain.SelectedTabPage = tabNew;
        }
        private void GridViewPosted_FocusedRowChanged(object sender, DevExpress.XtraGrid.Views.Base.FocusedRowChangedEventArgs e)
        {
            bool has = gridViewPosted.FocusedRowHandle >= 0;
            btnViewDetails.Enabled = has;
            btnCopyToNew.Enabled = has;
            btnEditVoucher.Enabled = has;
            _selectedPostedRefNo = has ? gridViewPosted.GetFocusedRowCellValue("ReferenceNo")?.ToString() : null;
        }

        private void GridViewPosted_DoubleClick(object sender, EventArgs e)
        {
            if (gridViewPosted.FocusedRowHandle >= 0) LoadSelectedVoucherDetails();
        }

        private void BtnViewDetails_Click(object sender, EventArgs e)
        {
            LoadSelectedVoucherDetails();
        }

        private void LoadSelectedVoucherDetails()
        {
            if (string.IsNullOrEmpty(_selectedPostedRefNo)) return;

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_GetManualJournalVoucherDetails", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@ReferenceNo", SqlDbType.VarChar, 10).Value = _selectedPostedRefNo;

                    var dt = new DataTable();
                    con.Open();
                    new SqlDataAdapter(cmd).Fill(dt);
                    gridControlPostedDetails.DataSource = dt;
                }
                gridViewPostedDetails.BestFitColumns();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load voucher details: {ex.Message}",
                    "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        // Loads the selected posted voucher's branch/account/amount/
        // particulars lines into a brand-new entry — everything EXCEPT
        // Reference No and Voucher Date carries over, per the recurring-
        // monthly-entry use case. Remarks carries over too since it's
        // part of "the entries and details," just those two identifiers
        // are deliberately regenerated/reset.
        private void BtnCopyToNew_Click(object sender, EventArgs e)
        {
            if (string.IsNullOrEmpty(_selectedPostedRefNo)) return;

            DataTable lines;
            string remarks;

            try
            {
                using (var con = Database.getConnection())
                {
                    con.Open();

                    using (var cmd = new SqlCommand("sp_GetManualJournalVoucherDetails", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.Add("@ReferenceNo", SqlDbType.VarChar, 10).Value = _selectedPostedRefNo;
                        lines = new DataTable();
                        new SqlDataAdapter(cmd).Fill(lines);
                    }
                }

                remarks = gridViewPosted.GetFocusedRowCellValue("Remarks")?.ToString() ?? "";
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load voucher for copying: {ex.Message}",
                    "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            if (lines.Rows.Count == 0)
            {
                XtraMessageBox.Show("This voucher has no lines to copy.", "Nothing to Copy",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            // Fresh Reference No + today's date, empty grid — then repopulate
            ResetForNewEntry(clearRemarks: false);
            txtRemarks.Text = remarks;
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
                $"Copied {lines.Rows.Count} line(s) from {_selectedPostedRefNo}.\nA new Reference No. and today's date were assigned — review before posting.",
                "Copied", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private static decimal ToDecimal(object value)
        {
            if (value == null || value == DBNull.Value) return 0m;
            decimal.TryParse(value.ToString(), out var result);
            return result;
        }

        private void tabMain_Click(object sender, EventArgs e)
        {

        }
    }
}