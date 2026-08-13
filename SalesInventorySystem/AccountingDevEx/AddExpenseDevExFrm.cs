using System;
using System.Data;
using System.Data.SqlClient;
using System.Threading.Tasks;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.AccountingDevEx
{
    /// <summary>
    /// Post Single Expense (SINGLE-mode, no mapping — manual GL entry via
    /// spu_PostExpenseV2). Redesigned to the two-tab pattern used by
    /// Manual JV: "Post Expense" for entry, "Posted Expenses" for
    /// browsing/View Details/Copy/Edit.
    ///
    /// Edit is now wired via sp_EditSingleExpense: blocked when a
    /// payment has been applied OR the expense is linked to a PO
    /// (see BtnEdit_Click / sp_GetSingleExpenseDetails' BlockedReason).
    /// </summary>
    public partial class AddExpenseDevExFrm : DevExpress.XtraEditors.XtraUserControl
    {
        private DataTable _linesTable;
        private DataTable _accountsCache;
        private object _supplierKey;
        private object _branchCode;
        private object _shipmentNo;
        private string _selectedPostedRefNo, _selectedPostedInvoiceNo, _selectedPostedSupplierId;
        private bool _dataLoaded = false;

        public AddExpenseDevExFrm()
        {
            InitializeComponent();
        }

        public async void LoadData()
        {
            if (_dataLoaded) return;
            _dataLoaded = true;
            await InitializeFormAsync();
        }

        private async void AddExpenseDevExFrm_Load(object sender, EventArgs e)
        {
            // Safety net only — the real trigger is LoadData(), called
            // explicitly by whatever hosts this control (same contract
            // as your original form). This just makes sure init still
            // happens if Load DOES fire and LoadData() hasn't been
            // called yet for some reason; the _dataLoaded guard means
            // whichever runs first wins and the other becomes a no-op.
            if (_dataLoaded) return;
            _dataLoaded = true;
            await InitializeFormAsync();
        }

        private async Task InitializeFormAsync()
        {
            BindSupplierLookup();
            BindBranchLookup();
            BindPOLookup_Reset();

            _accountsCache = await GetDataTableAsync("SELECT AccountCode, Description,  AccountCode + '-' + Description AS DisplayText FROM ChartOfAccounts");
            BindAccountCodeLookup(_accountsCache);

            txtDateFrom.DateTime = DateTime.Today.AddMonths(-1);
            txtDateTo.DateTime = DateTime.Today;

            StartNewEntry();
        }

        // ── Lookups ──────────────────────────────────────────────
        private void BindSupplierLookup()
        {
            Database.displaySearchlookupEdit(
                @"SELECT SupplierKey, SupplierID, SupplierName,
                         SupplierKey + ' - ' + SupplierName AS SupplierDisplay
                  FROM Supplier",
                cboSupplier, "SupplierDisplay", "SupplierKey");
        }

        private void BindBranchLookup()
        {
            Database.displaySearchlookupEdit(
                @"SELECT BranchCode, BranchName,
                         BranchCode + ' - ' + BranchName AS DisplayText
                  FROM Branches",
                cboBranch, "DisplayText", "BranchCode");

            // Filter-tab branch combo — plain LookUpEdit, "All Branches" checkbox covers the rest
            var dt = new DataTable();
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("SELECT BranchCode, BranchCode + ' - ' + BranchName AS DisplayText FROM Branches", con))
            using (var da = new SqlDataAdapter(cmd))
            {
                con.Open();
                da.Fill(dt);
            }
            cboFilterBranch.Properties.DataSource = dt;
            cboFilterBranch.Properties.DisplayMember = "DisplayText";
            cboFilterBranch.Properties.ValueMember = "BranchCode";
            cboFilterBranch.Properties.PopulateColumns();
            foreach (DevExpress.XtraEditors.Controls.LookUpColumnInfo col in cboFilterBranch.Properties.Columns)
                col.Visible = (col.FieldName == "DisplayText");
        }

        private void BindPOLookup_Reset()
        {
            cboPO.Properties.DataSource = null;
            cboPO.EditValue = null;
        }

        private void BindAccountCodeLookup(DataTable accounts)
        {
            repAccountCode.DataSource = accounts;
            repAccountCode.DisplayMember = "DisplayText";
            repAccountCode.ValueMember = "AccountCode";
            repAccountCodeView.PopulateColumns();
        }

        private async void ChkLinkToPO_CheckedChanged(object sender, EventArgs e)
        {
            if (chkLinkToPO.Checked)
            {
                cboPO.Enabled = true;
                try
                {
                    var purchaseList = await GetDataTableAsync(@"
                        SELECT ShipmentNo, SupplierId, SupplierName, ShipmentNo + '-' + SupplierName AS DisplayText
                        FROM dbo.view_POSUMMARYREP
                        WHERE Status <> 'CANCELLED'");

                    cboPO.Properties.DataSource = purchaseList;
                    cboPO.Properties.DisplayMember = "DisplayText";
                    cboPO.Properties.ValueMember = "ShipmentNo";
                    cboPO.Properties.PopulateViewColumns();
                }
                catch (SqlException ex)
                {
                    XtraMessageBox.Show(ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
            else
            {
                cboPO.EditValue = null;
                cboPO.Properties.DataSource = null;
                cboPO.Enabled = false;
            }
        }

        private void CboSupplier_EditValueChanged(object sender, EventArgs e)
        {
            _supplierKey = cboSupplier.EditValue;
        }

        // ── New entry ────────────────────────────────────────────
        private string _editingReferenceNo;
        private string _editingOldInvoiceNo;
        private string _editingOldSupplierId;
        private bool _isEditMode = false;

        private void StartNewEntry()
        {
            _isEditMode = false;
            _editingReferenceNo = _editingOldInvoiceNo = _editingOldSupplierId = null;
            lblEditNotice.Visible = false;
            btnSubmit.Text = "Submit";

            txtReferenceNo.Text = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");
            txtTicketNo.Text = GetTicketNumber();
            txtInvoiceNo.Text = "";
            txtExpenseDate.DateTime = DateTime.Today;
            txtRemarks.Text = "";
            cboSupplier.EditValue = null;
            cboBranch.EditValue = null;
            chkLinkToPO.Checked = false;

            _linesTable = new DataTable();
            _linesTable.Columns.Add("AccountCode", typeof(string));
            _linesTable.Columns.Add("AccountTitle", typeof(string));
            _linesTable.Columns.Add("Particulars", typeof(string));
            _linesTable.Columns.Add("Debit", typeof(decimal));
            _linesTable.Columns.Add("Credit", typeof(decimal));
            gridControlLines.DataSource = _linesTable;
            AddLine();
            AddLine();

            UpdateTotals();
        }

        private void BtnNewEntry_Click(object sender, EventArgs e) => StartNewEntry();

        private void AddLine()
        {
            DataRow row = _linesTable.NewRow();
            row["Debit"] = 0m; row["Credit"] = 0m;
            _linesTable.Rows.Add(row);
        }

        private void BtnAddLine_Click(object sender, EventArgs e) => AddLine();

        private void BtnRemoveLine_Click(object sender, EventArgs e)
        {
            gridViewLines.DeleteSelectedRows();
            UpdateTotals();
        }

        private string GetTicketNumber()
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("sp_GetTicketNumber", con) { CommandType = CommandType.StoredProcedure })
            {
                con.Open();
                using (var reader = cmd.ExecuteReader())
                    if (reader.Read()) return reader["TicketNumber"].ToString();
            }
            return "";
        }

        // ── Grid mechanics ───────────────────────────────────────
        private void GridViewLines_CustomRowCellEdit(object sender, CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "AccountCode") e.RepositoryItem = repAccountCode;
            if (e.Column.FieldName == "Particulars") e.RepositoryItem = repParticulars;
            if (e.Column.FieldName == "Debit") e.RepositoryItem = repDebit;
            if (e.Column.FieldName == "Credit") e.RepositoryItem = repCredit;
        }

        private void GridViewLines_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            if (e.Column.FieldName == "AccountCode" && _accountsCache != null)
            {
                string code = e.Value?.ToString();
                if (!string.IsNullOrEmpty(code))
                {
                    var match = _accountsCache.Select($"AccountCode = '{code.Replace("'", "''")}'");
                    if (match.Length > 0)
                        gridViewLines.SetRowCellValue(e.RowHandle, "AccountTitle", match[0]["Description"].ToString());
                }
            }

            if (e.Column.FieldName == "Debit" && ToDecimal(e.Value) > 0)
                gridViewLines.SetRowCellValue(e.RowHandle, "Credit", 0m);
            if (e.Column.FieldName == "Credit" && ToDecimal(e.Value) > 0)
                gridViewLines.SetRowCellValue(e.RowHandle, "Debit", 0m);

            UpdateTotals();
        }

        private void GridViewLines_ShowingEditor(object sender, System.ComponentModel.CancelEventArgs e)
        {
            int row = gridViewLines.FocusedRowHandle;
            string col = gridViewLines.FocusedColumn.FieldName;

            decimal debit = ToDecimal(gridViewLines.GetRowCellValue(row, "Debit"));
            decimal credit = ToDecimal(gridViewLines.GetRowCellValue(row, "Credit"));

            if (col == "Debit" && credit > 0) e.Cancel = true;
            if (col == "Credit" && debit > 0) e.Cancel = true;
            if (col == "AccountTitle") e.Cancel = true;
        }

        private void GridViewLines_RowCellStyle(object sender, RowCellStyleEventArgs e)
        {
            decimal debit = ToDecimal(gridViewLines.GetRowCellValue(e.RowHandle, "Debit"));
            decimal credit = ToDecimal(gridViewLines.GetRowCellValue(e.RowHandle, "Credit"));
            if ((debit > 0 && credit > 0) || (debit == 0 && credit == 0))
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

            if (Math.Abs(totalDebit - totalCredit) > 0.01m)
            {
                lblBalanceStatus.Text = $"Out of balance by {Math.Abs(totalDebit - totalCredit):N2}";
                lblBalanceStatus.Appearance.ForeColor = System.Drawing.Color.Red;
            }
            else if (totalDebit == 0)
            {
                lblBalanceStatus.Text = "Enter at least one debit and one credit line.";
                lblBalanceStatus.Appearance.ForeColor = System.Drawing.Color.Gray;
            }
            else
            {
                lblBalanceStatus.Text = "Balanced.";
                lblBalanceStatus.Appearance.ForeColor = System.Drawing.Color.SeaGreen;
            }
        }

        private decimal ToDecimal(object value)
        {
            if (value == null || value == DBNull.Value) return 0m;
            decimal.TryParse(value.ToString(), out decimal result);
            return result;
        }

        // ── Submit (Post — unchanged spu_PostExpenseV2 call) ─────
        private async void BtnSubmit_Click(object sender, EventArgs e)
        {
            if (_isEditMode)
            {
                await SaveEditAsync();
                return;
            }

            try
            {
                bool invoiceExists = await Task.Run(() => Database.checkifExist(
                    $"SELECT 1 FROM ExpenseSummary WHERE SupplierID='{_supplierKey}' AND InvoiceNo='{txtInvoiceNo.Text.Trim()}'"));

                if (invoiceExists)
                {
                    XtraMessageBox.Show("Invoice No. already exists.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

                if (!ValidateLines()) return;

                var dt = BuildExpenseDetailsTVP();

                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("spu_PostExpenseV2", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.AddWithValue("@ExpenseDetails", dt);
                    cmd.Parameters.AddWithValue("@TicketNumber", txtTicketNo.Text);
                    cmd.Parameters.AddWithValue("@BranchCode", cboBranch.EditValue?.ToString() ?? "");
                    cmd.Parameters.AddWithValue("@ReferenceNumber", txtReferenceNo.Text);
                    cmd.Parameters.AddWithValue("@InvoiceNo", txtInvoiceNo.Text);
                    cmd.Parameters.AddWithValue("@ShipmentNo", _shipmentNo == null ? "" : _shipmentNo.ToString());
                    cmd.Parameters.AddWithValue("@SupplierID", cboSupplier.EditValue?.ToString() ?? "");
                    cmd.Parameters.AddWithValue("@ExpenseDate", txtExpenseDate.DateTime);
                    cmd.Parameters.AddWithValue("@Remarks", txtRemarks.Text);
                    cmd.Parameters.AddWithValue("@isLinkedToPO", chkLinkToPO.Checked ? 1 : 0);
                    cmd.Parameters.AddWithValue("@User", Login.Fullname);

                    con.Open();
                    cmd.ExecuteNonQuery();
                }

                XtraMessageBox.Show("Successfully posted.", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                StartNewEntry();
                LoadPostedExpenses();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private bool ValidateLines()
        {
            if (string.IsNullOrWhiteSpace(txtReferenceNo.Text) || cboBranch.EditValue == null ||
                cboSupplier.EditValue == null || string.IsNullOrWhiteSpace(txtRemarks.Text))
            {
                XtraMessageBox.Show("Please fill in all required fields.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            decimal totalDebit = decimal.Parse(lblTotalDebit.Text);
            decimal totalCredit = decimal.Parse(lblTotalCredit.Text);
            if (totalDebit <= 0 || totalCredit <= 0)
            {
                XtraMessageBox.Show("Please make sure you have GL entries.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
            if (Math.Abs(totalDebit - totalCredit) > 0.01m)
            {
                XtraMessageBox.Show("Entry does not balance — total Debit must equal total Credit.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            for (int i = 0; i < gridViewLines.RowCount; i++)
            {
                decimal debit = ToDecimal(gridViewLines.GetRowCellValue(i, "Debit"));
                decimal credit = ToDecimal(gridViewLines.GetRowCellValue(i, "Credit"));
                string acct = gridViewLines.GetRowCellValue(i, "AccountCode")?.ToString();

                if (string.IsNullOrEmpty(acct) && debit == 0 && credit == 0) continue; // blank row, skip

                if (string.IsNullOrEmpty(acct))
                {
                    XtraMessageBox.Show($"Row {i + 1}: Account is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
                if ((debit > 0 && credit > 0) || (debit == 0 && credit == 0))
                {
                    XtraMessageBox.Show($"Row {i + 1}: enter an amount in either Debit or Credit only.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
            }

            return true;
        }

        private async Task SaveEditAsync()
        {
            if (!ValidateLines()) return;

            if (XtraMessageBox.Show(
                    $"Save changes to {_editingReferenceNo} / Invoice {_editingOldInvoiceNo}?\nThe original posting will be replaced entirely.",
                    "Confirm Save", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes)
                return;

            try
            {
                var dt = BuildExpenseDetailsTVP();

                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_EditSingleExpense", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;

                    cmd.Parameters.Add("@ReferenceNumber", SqlDbType.VarChar, 20).Value = _editingReferenceNo;
                    cmd.Parameters.Add("@OldInvoiceNo", SqlDbType.VarChar, 150).Value = _editingOldInvoiceNo;
                    cmd.Parameters.Add("@OldSupplierID", SqlDbType.VarChar, 20).Value = _editingOldSupplierId;
                    cmd.Parameters.Add("@InvoiceNo", SqlDbType.VarChar, 150).Value = txtInvoiceNo.Text.Trim();
                    cmd.Parameters.Add("@SupplierID", SqlDbType.VarChar, 20).Value = cboSupplier.EditValue.ToString();
                    cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 10).Value = cboBranch.EditValue?.ToString() ?? "";
                    cmd.Parameters.Add("@ExpenseDate", SqlDbType.Date).Value = txtExpenseDate.DateTime;
                    cmd.Parameters.Add("@Remarks", SqlDbType.VarChar, 500).Value = txtRemarks.Text;
                    cmd.Parameters.Add("@User", SqlDbType.VarChar, 100).Value = Login.Fullname;

                    var tvpParam = cmd.Parameters.Add("@ExpenseDetails", SqlDbType.Structured);
                    tvpParam.TypeName = "dbo.ExpenseDetailType";
                    tvpParam.Value = dt;

                    con.Open();
                    string message = "Expense updated successfully.";
                    using (var rdr = cmd.ExecuteReader())
                        if (rdr.Read()) message = rdr["Message"]?.ToString() ?? message;

                    XtraMessageBox.Show(message, "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }

                StartNewEntry();
                LoadPostedExpenses();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Update failed:\n{ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private DataTable BuildExpenseDetailsTVP()
        {
            var dt = new DataTable();
            dt.Columns.Add("BranchCode", typeof(string));
            dt.Columns.Add("AccountCode", typeof(string));
            dt.Columns.Add("AccountTitle", typeof(string));
            
            dt.Columns.Add("Debit", typeof(decimal));
            dt.Columns.Add("Credit", typeof(decimal));

            dt.Columns.Add("Particulars", typeof(string));

            for (int i = 0; i < gridViewLines.RowCount; i++)
            {
                dt.Rows.Add(
                    cboBranch.EditValue?.ToString(),
                    gridViewLines.GetRowCellValue(i, "AccountCode"),
                    gridViewLines.GetRowCellValue(i, "AccountTitle"),
                    ToDecimal(gridViewLines.GetRowCellValue(i, "Debit")),
                    ToDecimal(gridViewLines.GetRowCellValue(i, "Credit")),
                    gridViewLines.GetRowCellValue(i, "Particulars"));
                    
            }
            return dt;
        }

        // ── Posted Expenses tab ──────────────────────────────────
        private void TabMain_SelectedPageChanged(object sender, DevExpress.XtraTab.TabPageChangedEventArgs e)
        {
            if (e.Page == tabPosted && gridControlPosted.DataSource == null)
                LoadPostedExpenses();
        }

        private void ChkAllBranches_CheckedChanged(object sender, EventArgs e)
        {
            cboFilterBranch.Enabled = !chkAllBranches.Checked;
        }

        private void BtnRefreshPosted_Click(object sender, EventArgs e) => LoadPostedExpenses();

        private void LoadPostedExpenses()
        {
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_GetPostedSingleExpenses", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value =
                        txtDateFrom.EditValue == null ? (object)DBNull.Value : txtDateFrom.DateTime;
                    cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value =
                        txtDateTo.EditValue == null ? (object)DBNull.Value : txtDateTo.DateTime;
                    cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 5).Value =
                        chkAllBranches.Checked || cboFilterBranch.EditValue == null
                            ? (object)DBNull.Value : cboFilterBranch.EditValue.ToString();

                    var dt = new DataTable();
                    con.Open();
                    new SqlDataAdapter(cmd).Fill(dt);
                    gridControlPosted.DataSource = dt;
                }

                gridViewPosted.BestFitColumns();
                if (gridViewPosted.Columns["SupplierID"] != null) gridViewPosted.Columns["SupplierID"].Visible = false;
                if (gridViewPosted.Columns["BranchCode"] != null) gridViewPosted.Columns["BranchCode"].Visible = false;

                gridControlPostedDetails.DataSource = null;
                btnViewDetails.Enabled = false;
                btnCopyToNew.Enabled = false;
                btnEdit.Enabled = false;
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

            if (has)
            {
                _selectedPostedRefNo = gridViewPosted.GetFocusedRowCellValue("ReferenceNumber")?.ToString();
                _selectedPostedInvoiceNo = gridViewPosted.GetFocusedRowCellValue("InvoiceNo")?.ToString();
                _selectedPostedSupplierId = gridViewPosted.GetFocusedRowCellValue("SupplierID")?.ToString();

                // AmountPaid/ShipmentNo aren't columns on the LIST grid
                // (sp_GetPostedSingleExpenses), only on the DETAILS query —
                // Edit's real eligibility check happens in BtnEdit_Click
                // itself via sp_GetSingleExpenseDetails' BlockedReason.
                // Enable optimistically here; the click handler is the
                // actual gate.
                btnEdit.Enabled = true;
            }
            else
            {
                _selectedPostedRefNo = _selectedPostedInvoiceNo = _selectedPostedSupplierId = null;
                btnEdit.Enabled = false;
            }
        }

        private void GridViewPosted_DoubleClick(object sender, EventArgs e)
        {
            if (gridViewPosted.FocusedRowHandle >= 0) LoadSelectedDetails();
        }

        private void BtnViewDetails_Click(object sender, EventArgs e) => LoadSelectedDetails();

        private void LoadSelectedDetails()
        {
            if (string.IsNullOrEmpty(_selectedPostedRefNo)) return;

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_GetSingleExpenseDetails", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@ReferenceNumber", SqlDbType.VarChar, 10).Value = _selectedPostedRefNo;
                    cmd.Parameters.Add("@InvoiceNo", SqlDbType.VarChar, 150).Value = _selectedPostedInvoiceNo;
                    cmd.Parameters.Add("@SupplierID", SqlDbType.VarChar, 100).Value = _selectedPostedSupplierId;

                    con.Open();
                    using (var da = new SqlDataAdapter(cmd))
                    {
                        var ds = new DataSet();
                        da.Fill(ds);
                        gridControlPostedDetails.DataSource = ds.Tables.Count > 1 ? ds.Tables[1] : null;
                    }
                }
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

            DataTable header, lines;
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_GetSingleExpenseDetails", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@ReferenceNumber", SqlDbType.VarChar, 10).Value = _selectedPostedRefNo;
                    cmd.Parameters.Add("@InvoiceNo", SqlDbType.VarChar, 150).Value = _selectedPostedInvoiceNo;
                    cmd.Parameters.Add("@SupplierID", SqlDbType.VarChar, 100).Value = _selectedPostedSupplierId;

                    con.Open();
                    using (var da = new SqlDataAdapter(cmd))
                    {
                        var ds = new DataSet();
                        da.Fill(ds);
                        header = ds.Tables.Count > 0 ? ds.Tables[0] : new DataTable();
                        lines = ds.Tables.Count > 1 ? ds.Tables[1] : new DataTable();
                    }
                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load expense for copying: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            if (header.Rows.Count == 0 || lines.Rows.Count == 0)
            {
                XtraMessageBox.Show("This expense has no lines to copy.", "Nothing to Copy", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            var h = header.Rows[0];

            // Fresh Reference No / Ticket No / Invoice No / Expense Date —
            // those are what actually change for a recurring expense.
            // Branch, Supplier, and Remarks carry over.
            StartNewEntry();

            cboSupplier.EditValue = h["SupplierID"]?.ToString();
            cboBranch.EditValue = h["BranchCode"]?.ToString();
            txtRemarks.Text = h["Remarks"]?.ToString() ?? "";

            _linesTable.Rows.Clear();

            foreach (DataRow src in lines.Rows)
            {
                DataRow row = _linesTable.NewRow();
                row["AccountCode"] = src["AccountCode"];
                row["AccountTitle"] = src["AccountTitle"];

                row["Particulars"] = src["Particulars"];
                row["Debit"] = src["Debit"];
                row["Credit"] = src["Credit"];
                _linesTable.Rows.Add(row);
            }

            gridViewLines.BestFitColumns();
            UpdateTotals();
            tabMain.SelectedTabPage = tabEntry;

            XtraMessageBox.Show(
                $"Copied {lines.Rows.Count} line(s) from {_selectedPostedRefNo}, along with Branch/Supplier/Remarks.\nA new Reference No. and Ticket No. were assigned — enter the Invoice No. and Expense Date, then review before posting.",
                "Copied", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private void cboPO_EditValueChanged(object sender, EventArgs e)
        {
            _shipmentNo = cboPO.EditValue;
        }

        private void BtnEdit_Click(object sender, EventArgs e)
        {
            if (string.IsNullOrEmpty(_selectedPostedRefNo)) return;

            DataTable header, lines;
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_GetSingleExpenseDetails", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@ReferenceNumber", SqlDbType.VarChar, 10).Value = _selectedPostedRefNo;
                    cmd.Parameters.Add("@InvoiceNo", SqlDbType.VarChar, 150).Value = _selectedPostedInvoiceNo;
                    cmd.Parameters.Add("@SupplierID", SqlDbType.VarChar, 100).Value = _selectedPostedSupplierId;

                    con.Open();
                    using (var da = new SqlDataAdapter(cmd))
                    {
                        var ds = new DataSet();
                        da.Fill(ds);
                        header = ds.Tables.Count > 0 ? ds.Tables[0] : new DataTable();
                        lines = ds.Tables.Count > 1 ? ds.Tables[1] : new DataTable();
                    }
                }
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

            // Load into the entry tab — KEEP the original identifiers,
            // unlike Copy which regenerates them
            _isEditMode = true;
            _editingReferenceNo = h["ReferenceNumber"].ToString();
            _editingOldInvoiceNo = h["InvoiceNo"].ToString();
            _editingOldSupplierId = h["SupplierID"].ToString();

            txtReferenceNo.Text = _editingReferenceNo;
            txtTicketNo.Text = h["TicketNumber"]?.ToString() ?? "";
            txtInvoiceNo.Text = _editingOldInvoiceNo;       // editable now — just pre-filled
            txtExpenseDate.DateTime = Convert.ToDateTime(h["ExpenseDate"]);
            txtRemarks.Text = h["Remarks"]?.ToString() ?? "";
            cboSupplier.EditValue = _editingOldSupplierId;   // editable now — just pre-filled
            cboBranch.EditValue = h["BranchCode"]?.ToString();
            chkLinkToPO.Checked = false;   // gate above already refused any PO-linked expense

            _linesTable = new DataTable();
            _linesTable.Columns.Add("AccountCode", typeof(string));
            _linesTable.Columns.Add("AccountTitle", typeof(string));
            _linesTable.Columns.Add("Debit", typeof(decimal));
            _linesTable.Columns.Add("Credit", typeof(decimal));
            _linesTable.Columns.Add("Particulars", typeof(string));

            foreach (DataRow src in lines.Rows)
            {
                DataRow row = _linesTable.NewRow();
                row["AccountCode"] = src["AccountCode"];
                row["AccountTitle"] = src["AccountTitle"];
                row["Particulars"] = src["Particulars"];
                row["Debit"] = src["Debit"];
                row["Credit"] = src["Credit"];
                _linesTable.Rows.Add(row);
            }
            gridControlLines.DataSource = _linesTable;
            gridViewLines.BestFitColumns();
            UpdateTotals();

            btnSubmit.Text = "Save Changes";
            lblEditNotice.Text = $"Editing expense {_editingReferenceNo} / Invoice {_editingOldInvoiceNo} — Reference No. cannot change. Saving replaces the original posting entirely (old ticket retired, fresh one issued under the same reference).";
            lblEditNotice.Visible = true;

            tabMain.SelectedTabPage = tabEntry;
        }

        // ── Helpers ──────────────────────────────────────────────
        private async Task<DataTable> GetDataTableAsync(string sql)
        {
            var dt = new DataTable();
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand(sql, con))
            {
                await con.OpenAsync();
                using (var reader = await cmd.ExecuteReaderAsync())
                    dt.Load(reader);
            }
            return dt;
        }
    }
}