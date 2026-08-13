using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;

namespace SalesInventorySystem.HOFormsDevEx
{
    /// <summary>
    /// Combined voucher: pick a supplier, check off unpaid invoices to
    /// pay, add manual debit lines (cash advance / EWT / accrued
    /// expense / anything), one voucher total for both. Posts via
    /// sp_PostSupplierPaymentWithManualLines — Leg 1 (invoices) calls
    /// the existing sp_AddPaymentSupplierCompound unchanged; Leg 2
    /// (manual lines) posts separately and is NOT atomic with Leg 1
    /// (see the SP's header comment for why).
    /// </summary>
    public partial class CombinedSupplierVoucherFrm : XtraForm
    {
        private DataTable _invoicesTable;
        private DataTable _manualLinesTable;
        private string _supplierName = "";

        public CombinedSupplierVoucherFrm()
        {
            InitializeComponent();
        }

        private void CombinedSupplierVoucherFrm_Load(object sender, EventArgs e)
        {
            txtReferenceNo.Text = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");
            txtVoucherID.Text = IDGenerator.getIDNumberSP("sp_GetVoucherNumber", "TicketNumber");
            txtCheckDate.DateTime = DateTime.Today;
            txtControlDate.DateTime = DateTime.Today;
            RadVoucherType_SelectedIndexChanged(null, null);

            BindBranchLookup();
            BindSupplierLookup();
            BindAccountCodeLookup();
            BindCreditAccountLookup();

            _invoicesTable = new DataTable();
            _invoicesTable.Columns.Add("Checked", typeof(bool));
            _invoicesTable.Columns.Add("ReferenceNumber", typeof(string));
            _invoicesTable.Columns.Add("InvoiceNo", typeof(string));
            _invoicesTable.Columns.Add("BatchReferenceID", typeof(long));
            _invoicesTable.Columns.Add("BranchCode", typeof(string));
            _invoicesTable.Columns.Add("ExpenseDate", typeof(DateTime));
            _invoicesTable.Columns.Add("Description", typeof(string));
            _invoicesTable.Columns.Add("Amount", typeof(decimal));
            _invoicesTable.Columns.Add("Balance", typeof(decimal));
            gridControlInvoices.DataSource = _invoicesTable;

            _manualLinesTable = new DataTable();
            _manualLinesTable.Columns.Add("BranchCode", typeof(string));
            _manualLinesTable.Columns.Add("AccountCode", typeof(string));
            _manualLinesTable.Columns.Add("Amount", typeof(decimal));
            _manualLinesTable.Columns.Add("Particulars", typeof(string));
            gridControlManual.DataSource = _manualLinesTable;

            UpdateTotals();
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

            // Grid repository (manual lines) shares the same data
            repManBranchCode.DataSource = dt;
            repManBranchCode.DisplayMember = "DisplayText";
            repManBranchCode.ValueMember = "BranchCode";
            repManBranchCode.PopulateColumns();
            HideExtraPopupColumns(repManBranchCode.Columns, "DisplayText");
        }

        private void BindSupplierLookup()
        {
            DataTable dt = GetDataTable("SELECT SupplierID, SupplierName FROM Supplier ORDER BY SupplierName");
            cboSupplier.Properties.DataSource = dt;
            cboSupplier.Properties.DisplayMember = "SupplierName";
            cboSupplier.Properties.ValueMember = "SupplierID";
            cboSupplier.Properties.PopulateViewColumns();
        }

        // No AccountType filter — any account, per your call not to
        // constrain this screen the way Cash Advance's whitelist does.
        private void BindAccountCodeLookup()
        {
            DataTable dt = GetDataTable(@"
                SELECT AccountCode, Description, AccountCode + '-' + Description AS DisplayText
                FROM ChartOfAccounts
                ORDER BY AccountCode");

            repManAccountCode.DataSource = dt;
            repManAccountCode.DisplayMember = "DisplayText";
            repManAccountCode.ValueMember = "AccountCode";
        }

        private void BindCreditAccountLookup()
        {
            DataTable dt = GetDataTable(@"
                SELECT AccountCode, Description, AccountCode + '-' + Description AS DisplayText
                FROM ChartOfAccounts
                WHERE AccountCode LIKE '10102%' AND AccountType = 'D'
                ORDER BY AccountCode");

            cboCreditAccount.Properties.DataSource = dt;
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

        // ── Supplier selection loads that supplier's unpaid invoices ──
        private void CboSupplier_EditValueChanged(object sender, EventArgs e)
        {
            _invoicesTable.Rows.Clear();
            UpdateTotals();

            if (cboSupplier.EditValue == null) return;

            var row = cboSupplier.Properties.GetRowByKeyValue(cboSupplier.EditValue) as DataRowView;
            _supplierName = row?["SupplierName"]?.ToString() ?? "";

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_GetUnpaidInvoicesForSupplier", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@SupplierID", SqlDbType.VarChar, 100).Value = cboSupplier.EditValue.ToString();

                    con.Open();
                    using (var rdr = cmd.ExecuteReader())
                    {
                        while (rdr.Read())
                        {
                            DataRow r = _invoicesTable.NewRow();
                            r["Checked"] = false;
                            r["ReferenceNumber"] = rdr["ReferenceNumber"];
                            r["InvoiceNo"] = rdr["InvoiceNo"];
                            r["BatchReferenceID"] = rdr["BatchReferenceID"];
                            r["BranchCode"] = rdr["BranchCode"] == DBNull.Value ? (object)DBNull.Value : rdr["BranchCode"];
                            r["ExpenseDate"] = rdr["ExpenseDate"];
                            r["Description"] = rdr["Description"];
                            r["Amount"] = rdr["Amount"];
                            r["Balance"] = rdr["Balance"];
                            _invoicesTable.Rows.Add(r);
                        }
                    }
                }
                gridViewInvoices.BestFitColumns();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load unpaid invoices: {ex.Message}",
                    "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void RadVoucherType_SelectedIndexChanged(object sender, EventArgs e)
        {
            bool isCheck = radVoucherType.EditValue?.ToString() == "CHECK";

            txtCheckNo.Visible = isCheck;
            lblCheckNo.Visible = isCheck;
            txtCheckDate.Visible = isCheck;
            lblCheckDate.Visible = isCheck;
            txtCheckNo.Enabled = isCheck;
            txtCheckDate.Enabled = isCheck;

            txtControlNo.Visible = !isCheck;
            lblControlNo.Visible = !isCheck;
            txtControlDate.Visible = !isCheck;
            lblControlDate.Visible = !isCheck;
            txtControlNo.Enabled = !isCheck;
            txtControlDate.Enabled = !isCheck;
        }

        // ── Invoices tab ─────────────────────────────────────────
        private void GridViewInvoices_CustomRowCellEdit(object sender, DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "Checked") e.RepositoryItem = repCheck;
        }

        private void GridViewInvoices_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            if (e.Column.FieldName == "Checked") UpdateTotals();
        }

        // ── Manual debit lines tab ───────────────────────────────
        private void BtnAddManualLine_Click(object sender, EventArgs e)
        {
            DataRow row = _manualLinesTable.NewRow();
            row["Amount"] = 0m;
            row["BranchCode"] = cboBranch.EditValue?.ToString() ?? "";
            _manualLinesTable.Rows.Add(row);
            gridViewManual.BestFitColumns();
        }

        private void BtnRemoveManualLine_Click(object sender, EventArgs e)
        {
            gridViewManual.DeleteSelectedRows();
            UpdateTotals();
        }

        private void GridViewManual_CustomRowCellEdit(object sender, DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "BranchCode") e.RepositoryItem = repManBranchCode;
            if (e.Column.FieldName == "AccountCode") e.RepositoryItem = repManAccountCode;
            if (e.Column.FieldName == "Amount") e.RepositoryItem = repManAmount;
            if (e.Column.FieldName == "Particulars") e.RepositoryItem = repManParticulars;
        }

        private void GridViewManual_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            UpdateTotals();
        }

        private void GridViewManual_RowCellStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowCellStyleEventArgs e)
        {
            string branch = gridViewManual.GetRowCellValue(e.RowHandle, "BranchCode")?.ToString();
            string acct = gridViewManual.GetRowCellValue(e.RowHandle, "AccountCode")?.ToString();
            decimal amount = ToDecimal(gridViewManual.GetRowCellValue(e.RowHandle, "Amount"));

            if (string.IsNullOrWhiteSpace(branch) || string.IsNullOrWhiteSpace(acct) || amount <= 0)
                e.Appearance.BackColor = System.Drawing.Color.LightCoral;
        }

        // ── Totals ───────────────────────────────────────────────
        private void UpdateTotals()
        {
            decimal invoiceTotal = 0;
            for (int i = 0; i < gridViewInvoices.RowCount; i++)
            {
                bool chk = Convert.ToBoolean(gridViewInvoices.GetRowCellValue(i, "Checked") ?? false);
                if (chk) invoiceTotal += ToDecimal(gridViewInvoices.GetRowCellValue(i, "Balance"));
            }

            decimal manualTotal = 0;
            for (int i = 0; i < gridViewManual.RowCount; i++)
                manualTotal += ToDecimal(gridViewManual.GetRowCellValue(i, "Amount"));

            lblInvoiceTotal.Text = invoiceTotal.ToString("N2");
            lblManualTotal.Text = manualTotal.ToString("N2");
            lblGrandTotal.Text = (invoiceTotal + manualTotal).ToString("N2");
        }

        // ── Submit ───────────────────────────────────────────────
        private void BtnPost_Click(object sender, EventArgs e)
        {
            if (!ValidateForm()) return;

            bool isCheck = radVoucherType.EditValue?.ToString() == "CHECK";
            string voucherType = radVoucherType.EditValue?.ToString() ?? "CASH";
            decimal invoiceTotal = decimal.Parse(lblInvoiceTotal.Text);

            var invoiceLines = BuildInvoiceLinesTVP();
            var manualLines = BuildManualLinesTVP();

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_PostSupplierPaymentWithManualLines", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 120;

                    cmd.Parameters.Add("@parmrefno", SqlDbType.VarChar, 10).Value = txtReferenceNo.Text.Trim();
                    cmd.Parameters.Add("@parmvoucherid", SqlDbType.VarChar, 10).Value = txtVoucherID.Text.Trim();
                    cmd.Parameters.Add("@parmsupplierid", SqlDbType.VarChar, 50).Value = cboSupplier.EditValue.ToString();
                    cmd.Parameters.Add("@parmsuppliername", SqlDbType.VarChar, 150).Value = _supplierName;
                    cmd.Parameters.Add("@parmcheckcoding", SqlDbType.VarChar, 50).Value = "COMBINED" + txtReferenceNo.Text.Trim();
                    cmd.Parameters.Add("@parmcheckno", SqlDbType.VarChar, 50).Value =
                        isCheck ? (object)txtCheckNo.Text.Trim() : DBNull.Value;
                    cmd.Parameters.Add("@parmcheckdate", SqlDbType.Date).Value =
                        isCheck ? (object)txtCheckDate.DateTime : DBNull.Value;
                    cmd.Parameters.Add("@parmcontrolno", SqlDbType.VarChar, 50).Value =
                        isCheck ? DBNull.Value : (object)txtControlNo.Text.Trim();
                    cmd.Parameters.Add("@parmdate", SqlDbType.Date).Value =
                        isCheck ? DBNull.Value : (object)txtControlDate.DateTime;
                    cmd.Parameters.Add("@parmcheckremarks", SqlDbType.VarChar, 2000).Value = txtRemarks.Text.Trim();
                    cmd.Parameters.Add("@parmpreparedby", SqlDbType.VarChar, 30).Value = Login.Fullname;
                    cmd.Parameters.Add("@parmglcode", SqlDbType.VarChar, 30).Value = cboCreditAccount.EditValue?.ToString();
                    cmd.Parameters.Add("@parmvouchertype", SqlDbType.VarChar, 10).Value = voucherType;
                    cmd.Parameters.Add("@parmPayingBranch", SqlDbType.VarChar, 5).Value = cboBranch.EditValue?.ToString();
                    cmd.Parameters.Add("@InvoiceLegAmount", SqlDbType.Decimal).Value = invoiceTotal;

                    var invParam = cmd.Parameters.AddWithValue("@InvoiceLines", invoiceLines);
                    invParam.SqlDbType = SqlDbType.Structured;
                    invParam.TypeName = "dbo.AP_PaymentLineTVP";

                    var manParam = cmd.Parameters.AddWithValue("@ManualLines", manualLines);
                    manParam.SqlDbType = SqlDbType.Structured;
                    manParam.TypeName = "dbo.ManualVoucherDebitLineTVP";

                    con.Open();

                    string message = "Combined voucher posted successfully.";
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

        // CRITICAL: SqlClient maps a DataTable-as-TVP by ORDINAL POSITION,
        // not by column name — this order must exactly match the real
        // dbo.AP_PaymentLineTVP: BranchCode, InvoiceNo, InvoiceDate,
        // SequenceReferenceNumber, BatchReferenceID, ActualCost,
        // AmountPaid, EWTAmount, DiscountAmount, OffsetAmount,
        // Description, Variance (12 columns). Full payoff only (v1) —
        // Variance stays 0, matching your reference code's
        // InitializeRowPayment default (no variance until the user
        // types an actual-cash figure different from Balance).
        private DataTable BuildInvoiceLinesTVP()
        {
            var dt = new DataTable();
            dt.Columns.Add("BranchCode", typeof(string));
            dt.Columns.Add("InvoiceNo", typeof(string));
            dt.Columns.Add("InvoiceDate", typeof(DateTime));
            dt.Columns.Add("SequenceReferenceNumber", typeof(string));
            dt.Columns.Add("BatchReferenceID", typeof(long));
            dt.Columns.Add("ActualCost", typeof(decimal));
            dt.Columns.Add("AmountPaid", typeof(decimal));
            dt.Columns.Add("EWTAmount", typeof(decimal));
            dt.Columns.Add("DiscountAmount", typeof(decimal));
            dt.Columns.Add("OffsetAmount", typeof(decimal));
            dt.Columns.Add("Description", typeof(string));
            dt.Columns.Add("Variance", typeof(decimal));

            for (int i = 0; i < gridViewInvoices.RowCount; i++)
            {
                bool chk = Convert.ToBoolean(gridViewInvoices.GetRowCellValue(i, "Checked") ?? false);
                if (!chk) continue;

                dt.Rows.Add(
                    gridViewInvoices.GetRowCellValue(i, "BranchCode") ?? "",
                    gridViewInvoices.GetRowCellValue(i, "InvoiceNo"),
                    gridViewInvoices.GetRowCellValue(i, "ExpenseDate"),
                    "",
                    gridViewInvoices.GetRowCellValue(i, "BatchReferenceID"),
                    gridViewInvoices.GetRowCellValue(i, "Amount"),
                    gridViewInvoices.GetRowCellValue(i, "Balance"),
                    0m, 0m, 0m,
                    gridViewInvoices.GetRowCellValue(i, "Description"),
                    0m);
            }

            return dt;
        }

        private DataTable BuildManualLinesTVP()
        {
            var dt = new DataTable();
            dt.Columns.Add("BranchCode", typeof(string));
            dt.Columns.Add("AccountCode", typeof(string));
            dt.Columns.Add("Amount", typeof(decimal));
            dt.Columns.Add("Particulars", typeof(string));

            for (int i = 0; i < gridViewManual.RowCount; i++)
            {
                string branch = gridViewManual.GetRowCellValue(i, "BranchCode")?.ToString();
                string acct = gridViewManual.GetRowCellValue(i, "AccountCode")?.ToString();
                decimal amount = ToDecimal(gridViewManual.GetRowCellValue(i, "Amount"));
                string particulars = gridViewManual.GetRowCellValue(i, "Particulars")?.ToString() ?? "";

                if (string.IsNullOrWhiteSpace(branch) || string.IsNullOrWhiteSpace(acct) || amount <= 0) continue;

                dt.Rows.Add(branch, acct, amount, particulars);
            }

            return dt;
        }

        private bool ValidateForm()
        {
            if (cboSupplier.EditValue == null)
            {
                XtraMessageBox.Show("Please select a supplier.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
            if (cboBranch.EditValue == null || string.IsNullOrWhiteSpace(cboBranch.EditValue.ToString()))
            {
                XtraMessageBox.Show("Please select a paying branch.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
            if (cboCreditAccount.EditValue == null || string.IsNullOrWhiteSpace(cboCreditAccount.EditValue.ToString()))
            {
                XtraMessageBox.Show("Please select the credit (bank) account.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            bool isCheck = radVoucherType.EditValue?.ToString() == "CHECK";
            if (isCheck && string.IsNullOrWhiteSpace(txtCheckNo.Text))
            {
                XtraMessageBox.Show("Check No. is required for a Check voucher.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
            if (!isCheck && string.IsNullOrWhiteSpace(txtControlNo.Text))
            {
                XtraMessageBox.Show("Control No. is required for Cash/Telegraphic vouchers.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            bool anyInvoiceChecked = false;
            for (int i = 0; i < gridViewInvoices.RowCount; i++)
                if (Convert.ToBoolean(gridViewInvoices.GetRowCellValue(i, "Checked") ?? false)) { anyInvoiceChecked = true; break; }

            bool anyManualLine = false;
            for (int i = 0; i < gridViewManual.RowCount; i++)
            {
                string acct = gridViewManual.GetRowCellValue(i, "AccountCode")?.ToString();
                decimal amt = ToDecimal(gridViewManual.GetRowCellValue(i, "Amount"));
                if (!string.IsNullOrWhiteSpace(acct) && amt > 0) { anyManualLine = true; break; }
            }

            if (!anyInvoiceChecked && !anyManualLine)
            {
                XtraMessageBox.Show("Check at least one invoice, or add at least one manual debit line.",
                    "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            for (int i = 0; i < gridViewManual.RowCount; i++)
            {
                string branch = gridViewManual.GetRowCellValue(i, "BranchCode")?.ToString();
                string acct = gridViewManual.GetRowCellValue(i, "AccountCode")?.ToString();
                decimal amt = ToDecimal(gridViewManual.GetRowCellValue(i, "Amount"));

                if (string.IsNullOrWhiteSpace(branch) && string.IsNullOrWhiteSpace(acct) && amt == 0) continue; // blank row

                if (string.IsNullOrWhiteSpace(branch))
                {
                    XtraMessageBox.Show($"Manual line row {i + 1}: Branch is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
                if (string.IsNullOrWhiteSpace(acct))
                {
                    XtraMessageBox.Show($"Manual line row {i + 1}: Account is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
                if (amt <= 0)
                {
                    XtraMessageBox.Show($"Manual line row {i + 1}: Amount must be greater than zero.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
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