using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class ClientAdjustmentMemoFrm : DevExpress.XtraEditors.XtraForm
    {
        private DataTable _offsetTable;
        private string _selectedCustomerID = "";
        private string _selectedInvoiceNo = "";

        public ClientAdjustmentMemoFrm()
        {
            InitializeComponent();
        }

        private void ClientAdjustmentMemoFrm_Load(object sender, EventArgs e)
        {
            txtMemoDate.EditValue = DateTime.Today;

            txtReferenceNo.Text = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");

            Database.displaySearchlookupEdit(
                "SELECT CustomerID, CustomerName FROM Customers",
                txtCustomer, "CustomerName", "CustomerName");

            Database.displaySearchlookupEdit(
                "SELECT AccountCode, Description FROM ChartOfAccounts WHERE AccountType='D'",
                txtARAccount, "AccountCode", "AccountCode");

            Database.displayRepositorySearchlookupEdit(
                "SELECT AccountCode, Description FROM ChartOfAccounts WHERE AccountType='D'",
                repAccountCode, "AccountCode", "AccountCode");

            Database.DisplayDevLookupEditItems("SELECT BranchCode FROM Branches", "BranchCode", "BranchCode", cboBranch);

            rgInvoiceType.SelectedIndex = 1;   // default to ON-ACCOUNT
            txtInvoice.Enabled = false;

            _offsetTable = new DataTable();
            _offsetTable.Columns.Add("AccountCode", typeof(string));
            _offsetTable.Columns.Add("Debit", typeof(decimal));
            _offsetTable.Columns.Add("Credit", typeof(decimal));
            _offsetTable.Columns.Add("Particulars", typeof(string));
            gridControlOffset.DataSource = _offsetTable;

            UpdateMemoTypePreview();
            UpdateTotals();
        }

        private void rgInvoiceType_SelectedIndexChanged(object sender, EventArgs e)
        {
            _selectedInvoiceNo = "";
            txtInvoice.EditValue = null;

            string mode = rgInvoiceType.EditValue?.ToString();

            if (mode == "ON-ACCOUNT")
            {
                txtInvoice.Enabled = false;
                return;
            }

            txtInvoice.Enabled = true;

            // NOTE: assumes TransactionChargeSales has an InvoiceNo + Balance
            // shape similar to ExpenseSummary/APACCOUNTS. If it needs a
            // different filter (e.g. only unpaid invoices), adjust the WHERE
            // clause below - I don't have full confirmation of its Status/
            // PayStatus column values.
            Database.displaySearchlookupEdit(
                "SELECT InvoiceNo, Balance " +
                "FROM TransactionChargeSales WHERE PayStatus IN ('UNPAID','PARTIAL')" +
                (string.IsNullOrWhiteSpace(_selectedCustomerID) ? "" : " AND CustomerID='" + _selectedCustomerID + "'"),
                txtInvoice, "InvoiceNo", "InvoiceNo");
        }

        private void txtCustomer_EditValueChanged(object sender, EventArgs e)
        {
            _selectedCustomerID = SearchLookUpClass.getSingleValue(txtCustomer, "CustomerID")?.ToString() ?? "";
            rgInvoiceType_SelectedIndexChanged(sender, e);
        }

        private void rgARDebitCredit_SelectedIndexChanged(object sender, EventArgs e)
        {
            UpdateMemoTypePreview();
        }

        private void txtARAmount_EditValueChanged(object sender, EventArgs e)
        {
            UpdateTotals();
        }

        private void UpdateMemoTypePreview()
        {
            string dc = rgARDebitCredit.EditValue?.ToString();
            if (dc == "D")
            {
                lblMemoTypePreview.Text = "= DEBIT MEMO (client owes MORE)";
                lblMemoTypePreview.Appearance.ForeColor = System.Drawing.Color.DarkOrange;
            }
            else if (dc == "C")
            {
                lblMemoTypePreview.Text = "= CREDIT MEMO (client owes LESS)";
                lblMemoTypePreview.Appearance.ForeColor = System.Drawing.Color.SeaGreen;
            }
            else
            {
                lblMemoTypePreview.Text = "Select Debit/Credit above";
                lblMemoTypePreview.Appearance.ForeColor = System.Drawing.Color.Gray;
            }
        }

        private void btnAddLine_Click(object sender, EventArgs e)
        {
            DataRow row = _offsetTable.NewRow();
            row["Debit"] = 0m;
            row["Credit"] = 0m;
            _offsetTable.Rows.Add(row);
            gridViewOffset.BestFitColumns();
        }

        private void btnRemoveLine_Click(object sender, EventArgs e)
        {
            gridViewOffset.DeleteSelectedRows();
            UpdateTotals();
        }

        private void gridViewOffset_CustomRowCellEdit(object sender, DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "AccountCode") e.RepositoryItem = repAccountCode;
            if (e.Column.FieldName == "Debit") e.RepositoryItem = repDebit;
            if (e.Column.FieldName == "Credit") e.RepositoryItem = repCredit;
            if (e.Column.FieldName == "Particulars") e.RepositoryItem = repParticulars;
        }

        private void gridViewOffset_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            if (e.Column.FieldName == "Debit")
            {
                decimal debit = ToDecimal(gridViewOffset.GetRowCellValue(e.RowHandle, "Debit"));
                if (debit > 0) gridViewOffset.SetRowCellValue(e.RowHandle, "Credit", 0m);
            }
            if (e.Column.FieldName == "Credit")
            {
                decimal credit = ToDecimal(gridViewOffset.GetRowCellValue(e.RowHandle, "Credit"));
                if (credit > 0) gridViewOffset.SetRowCellValue(e.RowHandle, "Debit", 0m);
            }

            UpdateTotals();
        }

        private void gridViewOffset_RowCellStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowCellStyleEventArgs e)
        {
            decimal debit = ToDecimal(gridViewOffset.GetRowCellValue(e.RowHandle, "Debit"));
            decimal credit = ToDecimal(gridViewOffset.GetRowCellValue(e.RowHandle, "Credit"));
            string acct = gridViewOffset.GetRowCellValue(e.RowHandle, "AccountCode")?.ToString();

            if (string.IsNullOrWhiteSpace(acct) || (debit > 0 && credit > 0) || (debit == 0 && credit == 0))
            {
                e.Appearance.BackColor = System.Drawing.Color.LightCoral;
            }
        }

        private void UpdateTotals()
        {
            decimal arAmount = ToDecimal(txtARAmount.EditValue);
            string arSide = rgARDebitCredit.EditValue?.ToString();

            decimal totalDebit = (arSide == "D") ? arAmount : 0m;
            decimal totalCredit = (arSide == "C") ? arAmount : 0m;

            for (int i = 0; i < gridViewOffset.RowCount; i++)
            {
                totalDebit += ToDecimal(gridViewOffset.GetRowCellValue(i, "Debit"));
                totalCredit += ToDecimal(gridViewOffset.GetRowCellValue(i, "Credit"));
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

            string invoiceType = rgInvoiceType.EditValue?.ToString();
            string arDebitCredit = rgARDebitCredit.EditValue?.ToString();
            decimal arAmount = ToDecimal(txtARAmount.EditValue);
            string arAccount = SearchLookUpClass.getSingleValue(txtARAccount, "AccountCode")?.ToString();

            var offsetTvp = BuildOffsetLinesTVP();

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_PostClientAdjustmentMemo", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 60;

                    cmd.Parameters.Add("@parmrefno", SqlDbType.VarChar, 10).Value = txtReferenceNo.Text.Trim();
                    cmd.Parameters.Add("@parmcustomerid", SqlDbType.VarChar, 100).Value = _selectedCustomerID;
                    cmd.Parameters.Add("@parmmemodate", SqlDbType.Date).Value = txtMemoDate.DateTime;
                    cmd.Parameters.Add("@parminvoicetype", SqlDbType.VarChar, 15).Value = invoiceType;

                    cmd.Parameters.Add("@parminvoiceno", SqlDbType.VarChar, 150).Value =
                        invoiceType == "ON-ACCOUNT" ? (object)DBNull.Value : _selectedInvoiceNo;

                    cmd.Parameters.Add("@parmbranchcode", SqlDbType.VarChar, 5).Value = cboBranch.Text.Trim();
                    cmd.Parameters.Add("@parmremarks", SqlDbType.VarChar, 500).Value = txtRemarks.Text.Trim();
                    cmd.Parameters.Add("@parmuser", SqlDbType.VarChar, 50).Value = Login.Fullname;

                    cmd.Parameters.Add("@ARAccountCode", SqlDbType.VarChar, 20).Value = arAccount;
                    cmd.Parameters.Add("@ARDebitCredit", SqlDbType.Char, 1).Value = arDebitCredit;
                    cmd.Parameters.Add("@ARAmount", SqlDbType.Decimal).Value = arAmount;

                    var tvpParam = cmd.Parameters.AddWithValue("@OffsetLines", offsetTvp);
                    tvpParam.SqlDbType = SqlDbType.Structured;
                    tvpParam.TypeName = "dbo.ClientMemoOffsetLineTVP";

                    con.Open();
                    cmd.ExecuteNonQuery();
                }

                XtraMessageBox.Show("Adjustment memo posted successfully.", "Success",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                Close();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Database error ({ex.Number}): {ex.Message}",
                    "Post Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        // Capture InvoiceNo when the user picks one from the lookup
        private void txtInvoice_EditValueChanged(object sender, EventArgs e)
        {
            _selectedInvoiceNo = SearchLookUpClass.getSingleValue(txtInvoice, "InvoiceNo")?.ToString() ?? "";
        }

        private DataTable BuildOffsetLinesTVP()
        {
            var dt = new DataTable();
            dt.Columns.Add("AccountCode", typeof(string));
            dt.Columns.Add("Debit", typeof(decimal));
            dt.Columns.Add("Credit", typeof(decimal));
            dt.Columns.Add("Particulars", typeof(string));

            for (int i = 0; i < gridViewOffset.RowCount; i++)
            {
                string acct = gridViewOffset.GetRowCellValue(i, "AccountCode")?.ToString();
                decimal debit = ToDecimal(gridViewOffset.GetRowCellValue(i, "Debit"));
                decimal credit = ToDecimal(gridViewOffset.GetRowCellValue(i, "Credit"));
                string particulars = gridViewOffset.GetRowCellValue(i, "Particulars")?.ToString() ?? "";

                if (string.IsNullOrWhiteSpace(acct) || (debit == 0 && credit == 0))
                    continue;

                dt.Rows.Add(acct, debit, credit, particulars);
            }

            return dt;
        }

        private bool ValidateForm()
        {
            if (string.IsNullOrWhiteSpace(_selectedCustomerID))
            {
                XtraMessageBox.Show("Please select a customer.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            string mode = rgInvoiceType.EditValue?.ToString();
            if (mode == "INVOICE" && string.IsNullOrWhiteSpace(_selectedInvoiceNo))
            {
                XtraMessageBox.Show("Please select an invoice, or switch to On-Account.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            if (string.IsNullOrWhiteSpace(cboBranch.Text))
            {
                XtraMessageBox.Show("Please select a branch.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            if (rgARDebitCredit.EditValue == null)
            {
                XtraMessageBox.Show("Please select whether the AR leg is a Debit or Credit.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            if (string.IsNullOrWhiteSpace(SearchLookUpClass.getSingleValue(txtARAccount, "AccountCode")?.ToString()))
            {
                XtraMessageBox.Show("Please select the AR account.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            if (ToDecimal(txtARAmount.EditValue) <= 0)
            {
                XtraMessageBox.Show("AR Amount must be greater than zero.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            if (gridViewOffset.RowCount == 0)
            {
                XtraMessageBox.Show("Please add at least one offset line.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            decimal totalDebit = decimal.Parse(lblTotalDebit.Text);
            decimal totalCredit = decimal.Parse(lblTotalCredit.Text);
            if (totalDebit != totalCredit)
            {
                XtraMessageBox.Show("Entry does not balance - total Debit must equal total Credit.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            return true;
        }

        private void btnClose_Click(object sender, EventArgs e)
        {
            Close();
        }

        private static decimal ToDecimal(object value)
        {
            if (value == null || value == DBNull.Value) return 0m;
            decimal.TryParse(value.ToString(), out var result);
            return result;
        }
    }
}