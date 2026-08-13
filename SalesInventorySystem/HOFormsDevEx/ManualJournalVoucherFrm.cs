using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class ManualJournalVoucherFrm : DevExpress.XtraEditors.XtraForm
    {
        private DataTable _linesTable;
        private string _selectedPostedRefNo;

        public ManualJournalVoucherFrm()
        {
            InitializeComponent();
        }

        private void ManualJournalVoucherFrm_Load(object sender, EventArgs e)
        {
            BindAccountCodeLookup();
            BindBranchLookup();

            _linesTable = new DataTable();
            _linesTable.Columns.Add("AccountCode", typeof(string));
            _linesTable.Columns.Add("Debit", typeof(decimal));
            _linesTable.Columns.Add("Credit", typeof(decimal));
            _linesTable.Columns.Add("Particulars", typeof(string));
            gridControlLines.DataSource = _linesTable;

            ResetForNewEntry(clearRemarks: true, clearBranch: false);
        }

        // Fresh Reference No + today's Voucher Date, empty grid with two
        // starter rows. Used on load AND after "Copy to New Entry."
        private void ResetForNewEntry(bool clearRemarks, bool clearBranch)
        {
            txtVoucherDate.EditValue = DateTime.Today;
            txtReferenceNo.Text = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");

            if (clearRemarks) txtRemarks.Text = "";
            if (clearBranch) cboBranch.EditValue = null;

            _linesTable.Rows.Clear();
            AddLine();
            AddLine();

            UpdateTotals();
        }

        // Combined "Code-Name" display text, computed in SQL so it's a
        // single column DisplayMember can point at.
        private void BindBranchLookup()
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

            cboBranch.Properties.DataSource = dt;
            cboBranch.Properties.DisplayMember = "DisplayText";
            cboBranch.Properties.ValueMember = "BranchCode";
            cboBranch.Properties.PopulateColumns();
            HideExtraPopupColumns(cboBranch.Properties.Columns, "DisplayText");
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
        }

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
            if (e.Column.FieldName == "AccountCode") e.RepositoryItem = repAccountCode;
            if (e.Column.FieldName == "Debit") e.RepositoryItem = repDebit;
            if (e.Column.FieldName == "Credit") e.RepositoryItem = repCredit;
            if (e.Column.FieldName == "Particulars") e.RepositoryItem = repParticulars;
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

            if (string.IsNullOrWhiteSpace(acct) || (debit > 0 && credit > 0) || (debit == 0 && credit == 0))
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

            if (totalDebit != totalCredit)
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

        private void btnPost_Click(object sender, EventArgs e)
        {
            if (!ValidateForm()) return;

            var lines = BuildLinesTVP();

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_PostManualJournalVoucher", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 60;

                    cmd.Parameters.Add("@parmrefno", SqlDbType.VarChar, 10).Value = txtReferenceNo.Text.Trim();
                    cmd.Parameters.Add("@parmvoucherdate", SqlDbType.Date).Value = txtVoucherDate.DateTime;
                    cmd.Parameters.Add("@parmbranchcode", SqlDbType.VarChar, 5).Value = cboBranch.EditValue?.ToString().Trim();
                    cmd.Parameters.Add("@parmremarks", SqlDbType.VarChar, 500).Value = txtRemarks.Text.Trim();
                    cmd.Parameters.Add("@parmuser", SqlDbType.VarChar, 50).Value = Login.Fullname;

                    var tvpParam = cmd.Parameters.AddWithValue("@Lines", lines);
                    tvpParam.SqlDbType = SqlDbType.Structured;
                    tvpParam.TypeName = "dbo.JournalVoucherLineTVP";

                    con.Open();
                    cmd.ExecuteNonQuery();
                }

                XtraMessageBox.Show("Journal voucher posted successfully.", "Success",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                //Close();
                ResetForNewEntry(clearRemarks: true, clearBranch: false);
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Database error ({ex.Number}): {ex.Message}",
                    "Post Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private DataTable BuildLinesTVP()
        {
            var dt = new DataTable();
            dt.Columns.Add("AccountCode", typeof(string));
            dt.Columns.Add("Debit", typeof(decimal));
            dt.Columns.Add("Credit", typeof(decimal));
            dt.Columns.Add("Particulars", typeof(string));

            for (int i = 0; i < gridViewLines.RowCount; i++)
            {
                string acct = gridViewLines.GetRowCellValue(i, "AccountCode")?.ToString();
                decimal debit = ToDecimal(gridViewLines.GetRowCellValue(i, "Debit"));
                decimal credit = ToDecimal(gridViewLines.GetRowCellValue(i, "Credit"));
                string particulars = gridViewLines.GetRowCellValue(i, "Particulars")?.ToString() ?? "";

                if (string.IsNullOrWhiteSpace(acct) || (debit == 0 && credit == 0))
                    continue;

                dt.Rows.Add(acct, debit, credit, particulars);
            }

            return dt;
        }

        private bool ValidateForm()
        {
            if (cboBranch.EditValue == null || string.IsNullOrWhiteSpace(cboBranch.EditValue.ToString()))
            {
                XtraMessageBox.Show("Please select a branch.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            if (gridViewLines.RowCount < 2)
            {
                XtraMessageBox.Show("A journal voucher needs at least two lines.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            for (int i = 0; i < gridViewLines.RowCount; i++)
            {
                string acct = gridViewLines.GetRowCellValue(i, "AccountCode")?.ToString();
                decimal debit = ToDecimal(gridViewLines.GetRowCellValue(i, "Debit"));
                decimal credit = ToDecimal(gridViewLines.GetRowCellValue(i, "Credit"));

                if (debit == 0 && credit == 0) continue;

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

            decimal totalDebit = decimal.Parse(lblTotalDebit.Text);
            decimal totalCredit = decimal.Parse(lblTotalCredit.Text);
            if (totalDebit != totalCredit)
            {
                XtraMessageBox.Show("Entry does not balance - total Debit must equal total Credit.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
            if (totalDebit <= 0)
            {
                XtraMessageBox.Show("Entry total must be greater than zero.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            return true;
        }

        private void btnClose_Click(object sender, EventArgs e)
        {
            Close();
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
                    // Single-branch form only offers vouchers that were
                    // actually posted single-branch — copying a multi-
                    // branch voucher in here would silently drop the
                    // other branches' lines.
                    cmd.Parameters.Add("@SingleBranchOnly", SqlDbType.Bit).Value = true;

                    var dt = new DataTable();
                    con.Open();
                    new SqlDataAdapter(cmd).Fill(dt);
                    gridControlPosted.DataSource = dt;
                }

                gridViewPosted.BestFitColumns();
                gridControlPostedDetails.DataSource = null;
                btnViewDetails.Enabled = false;
                btnCopyToNew.Enabled = false;
                _selectedPostedRefNo = null;
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load posted vouchers: {ex.Message}",
                    "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void GridViewPosted_FocusedRowChanged(object sender, DevExpress.XtraGrid.Views.Base.FocusedRowChangedEventArgs e)
        {
            bool has = gridViewPosted.FocusedRowHandle >= 0;
            btnViewDetails.Enabled = has;
            btnCopyToNew.Enabled = has;
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

        // Loads the selected posted voucher's Account/Debit/Credit/
        // Particulars lines (and its single Branch) into a brand-new
        // entry — Reference No. and Voucher Date are freshly generated,
        // same as the multi-branch form's copy feature.
        private void BtnCopyToNew_Click(object sender, EventArgs e)
        {
            if (string.IsNullOrEmpty(_selectedPostedRefNo)) return;

            DataTable lines;
            string remarks;
            string branchCode;

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_GetManualJournalVoucherDetails", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@ReferenceNo", SqlDbType.VarChar, 10).Value = _selectedPostedRefNo;
                    lines = new DataTable();
                    con.Open();
                    new SqlDataAdapter(cmd).Fill(lines);
                }

                remarks = gridViewPosted.GetFocusedRowCellValue("Remarks")?.ToString() ?? "";
                branchCode = gridViewPosted.GetFocusedRowCellValue("BranchCode")?.ToString();
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

            ResetForNewEntry(clearRemarks: false, clearBranch: false);
            txtRemarks.Text = remarks;
            if (!string.IsNullOrEmpty(branchCode))
                cboBranch.EditValue = branchCode;

            _linesTable.Rows.Clear();
            foreach (DataRow src in lines.Rows)
            {
                DataRow row = _linesTable.NewRow();
                row["AccountCode"] = src["AccountCode"];
                row["Debit"] = src["Debit"];
                row["Credit"] = src["Credit"];
                row["Particulars"] = src["Particulars"];
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
    }
}