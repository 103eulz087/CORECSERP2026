using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class SupplierAdjustmentMemoFrm : DevExpress.XtraEditors.XtraForm
    {
        private DataTable _offsetTable;
        private string _selectedSupplierID = "";
        private string _selectedAccountCode = "";
        private string _selectedBranchCode = "";
        private string _selectedInvoiceNo = "";
        private decimal _selectedSequenceNo = 0;    // PURCHASE (APACCOUNTS.SequenceNo)
        private long _selectedBatchRefNo = 0;       // EXPENSE (ExpenseSummary.BatchReferenceID)

        public SupplierAdjustmentMemoFrm()
        {
            InitializeComponent();
        }

        private void SupplierAdjustmentMemoFrm_Load(object sender, EventArgs e)
        {
            txtMemoDate.EditValue = DateTime.Today;

            // Pre-generate the reference number for display, same convention
            // as your other posting forms (Post Expense, etc.)
            txtReferenceNo.Text = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");

            Database.displaySearchlookupEdit(
                "SELECT SupplierID, SupplierName FROM Supplier",
                txtSupplier, "SupplierName", "SupplierName");

            Database.displaySearchlookupEdit(
                "SELECT AccountCode, Description FROM ChartOfAccounts WHERE AccountType='D'",
                txtAPAccount, "Description", "Description");

            Database.displayRepositorySearchlookupEdit(
                "SELECT AccountCode, Description FROM ChartOfAccounts WHERE AccountType='D'",
                repAccountCode, "AccountCode", "AccountCode");

            Database.DisplayDevLookupEditItems("SELECT BranchCode,BranchName FROM Branches", "BranchName", "BranchName", cboBranch);

            rgInvoiceType.SelectedIndex = 2;   // default to ON-ACCOUNT
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

        // ── Invoice Type switch: reconfigure the Invoice lookup source ──
        private void rgInvoiceType_SelectedIndexChanged(object sender, EventArgs e)
        {
            _selectedInvoiceNo = "";
            _selectedSequenceNo = 0;
            _selectedBatchRefNo = 0;
            txtInvoice.EditValue = null;

            string mode = rgInvoiceType.EditValue?.ToString();

            if (mode == "ON-ACCOUNT")
            {
                txtInvoice.Enabled = false;
                return;
            }

            txtInvoice.Enabled = true;

            if (mode == "PURCHASE")
            {
                Database.displaySearchlookupEdit(
                    "SELECT InvoiceNo, SequenceNo, Balance " +
                    "FROM APACCOUNTS WHERE PayStatus IN ('UNPAID','PARTIAL')" +
                    (string.IsNullOrWhiteSpace(_selectedSupplierID) ? "" : " AND SupplierID='" + _selectedSupplierID + "'"),
                    txtInvoice, "InvoiceNo", "InvoiceNo");
            }
            else if (mode == "EXPENSE")
            {
                Database.displaySearchlookupEdit(
                    "SELECT InvoiceNo, BatchReferenceID, Balance " +
                    "FROM ExpenseSummary WHERE Status NOT IN ('PAID','VOID','CANCELLED')" +
                    (string.IsNullOrWhiteSpace(_selectedSupplierID) ? "" : " AND SupplierID='" + _selectedSupplierID + "'"),
                    txtInvoice, "InvoiceNo", "InvoiceNo");
            }
        }

        // ── Supplier selection: capture SupplierID, re-filter the invoice list ──
        private void txtSupplier_EditValueChanged(object sender, EventArgs e)
        {
            _selectedSupplierID = SearchLookUpClass.getSingleValue(txtSupplier, "SupplierID")?.ToString() ?? "";
            // Re-apply the current InvoiceType filter now that we know the supplier
            rgInvoiceType_SelectedIndexChanged(sender, e);
        }

        // ── Invoice selection: capture the identifying keys needed by the SP ──
        private void txtInvoice_EditValueChanged(object sender, EventArgs e)
        {
            string mode = rgInvoiceType.EditValue?.ToString();
            if (mode == "PURCHASE")
            {
                _selectedInvoiceNo = SearchLookUpClass.getSingleValue(txtInvoice, "InvoiceNo")?.ToString() ?? "";
                decimal.TryParse(SearchLookUpClass.getSingleValue(txtInvoice, "SequenceNo")?.ToString(), out _selectedSequenceNo);
            }
            else if (mode == "EXPENSE")
            {
                _selectedInvoiceNo = SearchLookUpClass.getSingleValue(txtInvoice, "InvoiceNo")?.ToString() ?? "";
                long.TryParse(SearchLookUpClass.getSingleValue(txtInvoice, "BatchReferenceID")?.ToString(), out _selectedBatchRefNo);
            }
        }

        // ── AP leg: keep the Debit-Memo/Credit-Memo label in sync ──
        private void rgAPDebitCredit_SelectedIndexChanged(object sender, EventArgs e)
        {
            UpdateMemoTypePreview();
        }

        private void txtAPAmount_EditValueChanged(object sender, EventArgs e)
        {
            UpdateTotals();
        }

        private void UpdateMemoTypePreview()
        {
            string dc = rgAPDebitCredit.EditValue?.ToString();
            if (dc == "C")
            {
                lblMemoTypePreview.Text = "= DEBIT MEMO (balance owed increases)";
                lblMemoTypePreview.Appearance.ForeColor = System.Drawing.Color.DarkOrange;
            }
            else if (dc == "D")
            {
                lblMemoTypePreview.Text = "= CREDIT MEMO (balance owed decreases)";
                lblMemoTypePreview.Appearance.ForeColor = System.Drawing.Color.SeaGreen;
            }
            else
            {
                lblMemoTypePreview.Text = "Select Debit/Credit above";
                lblMemoTypePreview.Appearance.ForeColor = System.Drawing.Color.Gray;
            }
        }

        // ── Offset lines grid ──
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

        // Mutually exclusive Debit/Credit per row, same pattern as your
        // existing Single Mode manual GL entry grid (AddExpenseDevExFrm)
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

        // Flag rows with neither (or both) Debit/Credit populated - same
        // visual pattern as AddExpenseDevExFrm's gridView1_RowCellStyle
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
            decimal apAmount = ToDecimal(txtAPAmount.EditValue);
            string apSide = rgAPDebitCredit.EditValue?.ToString();

            decimal totalDebit = (apSide == "D") ? apAmount : 0m;
            decimal totalCredit = (apSide == "C") ? apAmount : 0m;

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

        // ── Post ──
        private void btnPost_Click(object sender, EventArgs e)
        {
            if (!ValidateForm()) return;

            string invoiceType = rgInvoiceType.EditValue?.ToString();
            string apDebitCredit = rgAPDebitCredit.EditValue?.ToString();
            decimal apAmount = ToDecimal(txtAPAmount.EditValue);
            string apAccount = _selectedAccountCode;//SearchLookUpClass.getSingleValue(txtAPAccount, "AccountCode")?.ToString();

            var offsetTvp = BuildOffsetLinesTVP();

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_PostSupplierAdjustmentMemo", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 60;

                    cmd.Parameters.Add("@parmrefno", SqlDbType.VarChar, 10).Value = txtReferenceNo.Text.Trim();
                    cmd.Parameters.Add("@parmsupplierid", SqlDbType.VarChar, 100).Value = _selectedSupplierID;
                    cmd.Parameters.Add("@parmmemodate", SqlDbType.Date).Value = txtMemoDate.DateTime;
                    cmd.Parameters.Add("@parminvoicetype", SqlDbType.VarChar, 15).Value = invoiceType;

                    cmd.Parameters.Add("@parminvoiceno", SqlDbType.VarChar, 150).Value =
                        invoiceType == "ON-ACCOUNT" ? (object)DBNull.Value : _selectedInvoiceNo;

                    cmd.Parameters.Add("@parmbatchrefno", SqlDbType.BigInt).Value =
                        invoiceType == "EXPENSE" ? (object)_selectedBatchRefNo : (object)DBNull.Value;

                    cmd.Parameters.Add("@parmsequenceno", SqlDbType.Decimal).Value =
                        invoiceType == "PURCHASE" ? (object)_selectedSequenceNo : (object)DBNull.Value;

                    cmd.Parameters.Add("@parmbranchcode", SqlDbType.VarChar, 5).Value = _selectedBranchCode;//cboBranch.Text.Trim();
                    cmd.Parameters.Add("@parmremarks", SqlDbType.VarChar, 500).Value = txtRemarks.Text.Trim();
                    cmd.Parameters.Add("@parmuser", SqlDbType.VarChar, 50).Value = Login.Fullname;

                    cmd.Parameters.Add("@APAccountCode", SqlDbType.VarChar, 20).Value = apAccount;
                    cmd.Parameters.Add("@APDebitCredit", SqlDbType.Char, 1).Value = apDebitCredit;
                    cmd.Parameters.Add("@APAmount", SqlDbType.Decimal).Value = apAmount;

                    var tvpParam = cmd.Parameters.AddWithValue("@OffsetLines", offsetTvp);
                    tvpParam.SqlDbType = SqlDbType.Structured;
                    tvpParam.TypeName = "dbo.SupplierMemoOffsetLineTVP";

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
            if (string.IsNullOrWhiteSpace(_selectedSupplierID))
            {
                XtraMessageBox.Show("Please select a supplier.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            string mode = rgInvoiceType.EditValue?.ToString();
            if ((mode == "PURCHASE" || mode == "EXPENSE") && string.IsNullOrWhiteSpace(_selectedInvoiceNo))
            {
                XtraMessageBox.Show("Please select an invoice, or switch to On-Account.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            if (string.IsNullOrWhiteSpace(cboBranch.Text))
            {
                XtraMessageBox.Show("Please select a branch.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            if (rgAPDebitCredit.EditValue == null)
            {
                XtraMessageBox.Show("Please select whether the AP leg is a Debit or Credit.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            if (string.IsNullOrWhiteSpace(SearchLookUpClass.getSingleValue(txtAPAccount, "AccountCode")?.ToString()))
            {
                XtraMessageBox.Show("Please select the AP account.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            if (ToDecimal(txtAPAmount.EditValue) <= 0)
            {
                XtraMessageBox.Show("AP Amount must be greater than zero.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
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

        private void txtAPAccount_EditValueChanged(object sender, EventArgs e)
        {
            _selectedAccountCode = SearchLookUpClass.getSingleValue(txtAPAccount, "AccountCode")?.ToString() ?? "";
        }

        private void cboBranch_EditValueChanged(object sender, EventArgs e)
        {
            _selectedBranchCode = SearchLookUpClass.GetSingleValueLookUpEdit(cboBranch, "BranchCode")?.ToString() ?? "";
        }
    }
}