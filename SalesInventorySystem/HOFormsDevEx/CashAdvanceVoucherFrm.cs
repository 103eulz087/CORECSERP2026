using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;

namespace SalesInventorySystem.HOFormsDevEx
{
    /// <summary>
    /// Standalone cash advance voucher — bypasses PostExpense/accrual
    /// entirely. Debit side is a multi-line grid (several accounts/
    /// payees per voucher); credit side stays a single bank/cash line.
    /// Debit accounts are constrained to CashAdvanceAllowedAccounts.
    /// </summary>
    public partial class CashAdvanceVoucherFrm : XtraForm
    {
        private DataTable _linesTable;

        public CashAdvanceVoucherFrm()
        {
            InitializeComponent();
        }

        private void CashAdvanceVoucherFrm_Load(object sender, EventArgs e)
        {
            txtReferenceNo.Text = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");
            txtVoucherID.Text = IDGenerator.getIDNumberSP("sp_GetVoucherNumber", "TicketNumber");
            txtCheckDate.DateTime = DateTime.Today;

            BindBranchLookup();
            BindSupplierLookup();
            BindDebitAccountLookup();
            BindCreditAccountLookup();

            _linesTable = new DataTable();
            _linesTable.Columns.Add("AccountCode", typeof(string));
            _linesTable.Columns.Add("PayeeName", typeof(string));
            _linesTable.Columns.Add("Amount", typeof(decimal));
            _linesTable.Columns.Add("Particulars", typeof(string));
            gridControlLines.DataSource = _linesTable;

            AddLine();
            UpdateTotal();
        }

        private void BindBranchLookup()
        {
            DataTable dt = GetDataTable(
                "SELECT BranchCode, BranchName, BranchCode + '-' + BranchName AS DisplayText FROM Branches ORDER BY BranchCode");

            cboBranch.Properties.DataSource = dt;
            cboBranch.Properties.DisplayMember = "DisplayText";
            cboBranch.Properties.ValueMember = "BranchCode";
            cboBranch.Properties.PopulateColumns();
            HideExtraPopupColumns(cboBranch.Properties.Columns, "DisplayText");
        }

        private void BindSupplierLookup()
        {
            DataTable dt = GetDataTable("SELECT SupplierID, SupplierName FROM Supplier ORDER BY SupplierName");

            cboSupplier.Properties.DataSource = dt;
            cboSupplier.Properties.DisplayMember = "SupplierName";
            cboSupplier.Properties.ValueMember = "SupplierID";
            cboSupplier.Properties.PopulateViewColumns();
        }

        // Constrained whitelist, now bound to the GRID's repository item
        // (repDebitAccount) instead of a single header dropdown.
        private void BindDebitAccountLookup()
        {
            DataTable dt = GetDataTable(@"
                SELECT coa.AccountCode, coa.Description,
                       coa.AccountCode + '-' + coa.Description AS DisplayText
                FROM ChartOfAccounts coa
                JOIN CashAdvanceAllowedAccounts caa ON caa.AccountCode = coa.AccountCode
                ORDER BY coa.AccountCode");

            repDebitAccount.DataSource = dt;
            repDebitAccount.DisplayMember = "DisplayText";
            repDebitAccount.ValueMember = "AccountCode";
            repDebitAccount.PopulateColumns();
            HideExtraPopupColumns(repDebitAccount.Columns, "DisplayText");

            if (dt.Rows.Count == 0)
                XtraMessageBox.Show(
                    "No accounts are configured in CashAdvanceAllowedAccounts yet — seed that table before this form can be used.",
                    "Setup Needed", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        private void BindCreditAccountLookup()
        {
            DataTable dt = GetDataTable(@"
                SELECT AccountCode, Description, AccountCode + '-' + Description AS DisplayText
                FROM ChartOfAccounts
               
                ORDER BY AccountCode");

            cboCreditAccount.Properties.DataSource = dt; // //WHERE AccountCode LIKE '10102%' AND AccountType = 'D'
            cboCreditAccount.Properties.DisplayMember = "DisplayText";
            cboCreditAccount.Properties.ValueMember = "AccountCode";
            cboCreditAccount.Properties.PopulateColumns();
            HideExtraPopupColumns(cboCreditAccount.Properties.Columns, "DisplayText");
        }

        private void HideExtraPopupColumns(DevExpress.XtraEditors.Controls.LookUpColumnInfoCollection columns, string keepFieldName)
        {
            foreach (DevExpress.XtraEditors.Controls.LookUpColumnInfo col in columns)
                col.Visible = (col.FieldName == keepFieldName);
        }

        private void CboSupplier_EditValueChanged(object sender, EventArgs e)
        {
            // Defaults the header payee — per-line PayeeName can still
            // override it for any individual debit line.
            if (cboSupplier.EditValue == null) return;

            var row = cboSupplier.Properties.GetRowByKeyValue(cboSupplier.EditValue) as DataRowView;
            if (row != null)
                txtPayeeName.Text = row["SupplierName"]?.ToString() ?? "";
        }

        private void RadVoucherType_SelectedIndexChanged(object sender, EventArgs e)
        {
            bool isCheck = radVoucherType.EditValue?.ToString() == "CHECK";
            txtCheckNo.Enabled = isCheck;
            txtCheckDate.Enabled = isCheck;
        }

        // ── Grid handlers ────────────────────────────────────────
        private void BtnAddLine_Click(object sender, EventArgs e)
        {
            AddLine();
        }

        private void AddLine()
        {
            DataRow row = _linesTable.NewRow();
            row["Amount"] = 0m;
            _linesTable.Rows.Add(row);
            gridViewLines.BestFitColumns();
        }

        private void BtnRemoveLine_Click(object sender, EventArgs e)
        {
            gridViewLines.DeleteSelectedRows();
            UpdateTotal();
        }

        private void GridViewLines_CustomRowCellEdit(object sender, DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "AccountCode") e.RepositoryItem = repDebitAccount;
            if (e.Column.FieldName == "PayeeName") e.RepositoryItem = repPayeeName;
            if (e.Column.FieldName == "Amount") e.RepositoryItem = repAmount;
            if (e.Column.FieldName == "Particulars") e.RepositoryItem = repParticulars;
        }

        private void GridViewLines_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            UpdateTotal();
        }

        private void GridViewLines_RowCellStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowCellStyleEventArgs e)
        {
            string acct = gridViewLines.GetRowCellValue(e.RowHandle, "AccountCode")?.ToString();
            decimal amount = ToDecimal(gridViewLines.GetRowCellValue(e.RowHandle, "Amount"));

            if (string.IsNullOrWhiteSpace(acct) || amount <= 0)
                e.Appearance.BackColor = System.Drawing.Color.LightCoral;
        }

        private void UpdateTotal()
        {
            decimal total = 0;
            for (int i = 0; i < gridViewLines.RowCount; i++)
                total += ToDecimal(gridViewLines.GetRowCellValue(i, "Amount"));

            lblTotal.Text = total.ToString("N2");
        }

        // ── Submit ───────────────────────────────────────────────
        private void BtnPost_Click(object sender, EventArgs e)
        {
            if (!ValidateForm()) return;

            var lines = BuildLinesTVP();
            bool isCheck = radVoucherType.EditValue?.ToString() == "CHECK";

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_PostCashAdvance", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 60;

                    cmd.Parameters.Add("@parmrefno", SqlDbType.VarChar, 10).Value = txtReferenceNo.Text.Trim();
                    cmd.Parameters.Add("@parmvoucherid", SqlDbType.VarChar, 10).Value = txtVoucherID.Text.Trim();
                    cmd.Parameters.Add("@parmsupplierid", SqlDbType.VarChar, 50).Value =
                        cboSupplier.EditValue == null ? (object)DBNull.Value : cboSupplier.EditValue.ToString();
                    cmd.Parameters.Add("@parmpayeename", SqlDbType.VarChar, 150).Value = txtPayeeName.Text.Trim();
                    cmd.Parameters.Add("@parmbranchcode", SqlDbType.VarChar, 5).Value = cboBranch.EditValue?.ToString();
                    cmd.Parameters.Add("@parmcreditaccount", SqlDbType.VarChar, 20).Value = cboCreditAccount.EditValue?.ToString();
                    cmd.Parameters.Add("@parmvouchertype", SqlDbType.VarChar, 10).Value = isCheck ? "CHECK" : "CASH";
                    cmd.Parameters.Add("@parmcheckno", SqlDbType.VarChar, 50).Value =
                        isCheck ? (object)txtCheckNo.Text.Trim() : DBNull.Value;
                    cmd.Parameters.Add("@parmcheckdate", SqlDbType.Date).Value =
                        isCheck ? (object)txtCheckDate.DateTime : DBNull.Value;
                    cmd.Parameters.Add("@parmremarks", SqlDbType.VarChar, 500).Value = txtRemarks.Text.Trim();
                    cmd.Parameters.Add("@parmuser", SqlDbType.VarChar, 50).Value = Login.Fullname;

                    var tvpParam = cmd.Parameters.AddWithValue("@Lines", lines);
                    tvpParam.SqlDbType = SqlDbType.Structured;
                    tvpParam.TypeName = "dbo.CashAdvanceLineTVP";

                    con.Open();

                    string message = "Cash advance posted successfully.";
                    using (var rdr = cmd.ExecuteReader())
                        if (rdr.Read()) message = rdr["Message"]?.ToString() ?? message;

                    XtraMessageBox.Show(message, "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }

                Close();
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
            dt.Columns.Add("PayeeName", typeof(string));
            dt.Columns.Add("Amount", typeof(decimal));
            dt.Columns.Add("Particulars", typeof(string));

            for (int i = 0; i < gridViewLines.RowCount; i++)
            {
                string acct = gridViewLines.GetRowCellValue(i, "AccountCode")?.ToString();
                string payee = gridViewLines.GetRowCellValue(i, "PayeeName")?.ToString() ?? "";
                decimal amount = ToDecimal(gridViewLines.GetRowCellValue(i, "Amount"));
                string particulars = gridViewLines.GetRowCellValue(i, "Particulars")?.ToString() ?? "";

                if (string.IsNullOrWhiteSpace(acct) || amount <= 0) continue;

                dt.Rows.Add(acct, payee, amount, particulars);
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
            if (string.IsNullOrWhiteSpace(txtPayeeName.Text))
            {
                XtraMessageBox.Show("Default Payee is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
            if (cboCreditAccount.EditValue == null || string.IsNullOrWhiteSpace(cboCreditAccount.EditValue.ToString()))
            {
                XtraMessageBox.Show("Please select the credit (bank) account.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            if (gridViewLines.RowCount == 0)
            {
                XtraMessageBox.Show("Add at least one debit line.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            bool hasValidLine = false;
            for (int i = 0; i < gridViewLines.RowCount; i++)
            {
                string acct = gridViewLines.GetRowCellValue(i, "AccountCode")?.ToString();
                decimal amount = ToDecimal(gridViewLines.GetRowCellValue(i, "Amount"));

                if (string.IsNullOrWhiteSpace(acct) && amount == 0) continue; // blank row, skip

                if (string.IsNullOrWhiteSpace(acct))
                {
                    XtraMessageBox.Show($"Row {i + 1}: Debit Account is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
                if (amount <= 0)
                {
                    XtraMessageBox.Show($"Row {i + 1}: Amount must be greater than zero.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
                hasValidLine = true;
            }

            if (!hasValidLine)
            {
                XtraMessageBox.Show("Add at least one complete debit line.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            bool isCheck = radVoucherType.EditValue?.ToString() == "CHECK";
            if (isCheck && string.IsNullOrWhiteSpace(txtCheckNo.Text))
            {
                XtraMessageBox.Show("Check No. is required for a Check voucher.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            return true;
        }

        private void BtnClose_Click(object sender, EventArgs e)
        {
            Close();
        }

        private DataTable GetDataTable(string sql)
        {
            var dt = new DataTable();
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand(sql, con))
            {
                con.Open();
                new SqlDataAdapter(cmd).Fill(dt);
            }
            return dt;
        }

        private static decimal ToDecimal(object value)
        {
            if (value == null || value == DBNull.Value) return 0m;
            decimal.TryParse(value.ToString(), out var result);
            return result;
        }
    }
}