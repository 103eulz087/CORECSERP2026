using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.AccountingDevEx
{
    /// <summary>
    /// Vouchering — Manual (no mapping). User builds the FULL compound
    /// GL entry themselves in one shared grid for the whole voucher —
    /// no EWTAmount/DiscountAmount/Variance columns, nothing auto-
    /// derived. The only enforced link: SUM(checked invoices' amount)
    /// must equal SUM(GL entry's Debit lines on an AP-Trade account,
    /// 20101/20102/20103).
    ///
    /// Reuses your existing splist_Accounts SP for the invoice list
    /// (same one the original SupplierPaymentDevEx uses) — assumed
    /// stable in shape; only SequenceNumber/BatchReferenceID/
    /// BranchCode/InvoiceNo/InvoiceDate/ActualCost/Balance are read
    /// from it, everything EWT/Discount/Variance-related is ignored.
    /// </summary>
    public partial class VoucheringManualFrm : DevExpress.XtraEditors.XtraUserControl
    {
        private DataTable _invoicesTable;
        private DataTable _glTable;
        private bool _dataLoaded = false;
        private string _selectedPostedRefNo;
        public VoucheringManualFrm()
        {
            InitializeComponent();
            BuildPostedTab();
        }
        private void BuildPostedTab()
        {
            this.pnlPostedFilter.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlPostedFilter.Height = 54;

            this.lblPostedDateFrom.Text = "From:";
            this.lblPostedDateFrom.Location = new System.Drawing.Point(12, 18);
            this.txtPostedDateFrom.Location = new System.Drawing.Point(58, 13);
            this.txtPostedDateFrom.Size = new System.Drawing.Size(120, 20);

            this.lblPostedDateTo.Text = "To:";
            this.lblPostedDateTo.Location = new System.Drawing.Point(190, 18);
            this.txtPostedDateTo.Location = new System.Drawing.Point(214, 13);
            this.txtPostedDateTo.Size = new System.Drawing.Size(120, 20);

            this.btnRefreshPosted.Text = "Refresh";
            this.btnRefreshPosted.Location = new System.Drawing.Point(346, 9);
            this.btnRefreshPosted.Size = new System.Drawing.Size(100, 30);
            this.btnRefreshPosted.Click += new System.EventHandler(this.BtnRefreshPosted_Click);

            this.pnlPostedFilter.Controls.Add(this.lblPostedDateFrom);
            this.pnlPostedFilter.Controls.Add(this.txtPostedDateFrom);
            this.pnlPostedFilter.Controls.Add(this.lblPostedDateTo);
            this.pnlPostedFilter.Controls.Add(this.txtPostedDateTo);
            this.pnlPostedFilter.Controls.Add(this.btnRefreshPosted);

            this.gridControlPosted.Dock = System.Windows.Forms.DockStyle.Top;
            this.gridControlPosted.Height = 280;
            this.gridControlPosted.MainView = this.gridViewPosted;
            this.gridControlPosted.ViewCollection.Add(this.gridViewPosted);
            this.gridViewPosted.GridControl = this.gridControlPosted;
            this.gridViewPosted.OptionsBehavior.Editable = false;
            this.gridViewPosted.OptionsView.ShowGroupPanel = false;
            this.gridViewPosted.FocusedRowChanged += new DevExpress.XtraGrid.Views.Base.FocusedRowChangedEventHandler(this.GridViewPosted_FocusedRowChanged);
            this.gridViewPosted.DoubleClick += new System.EventHandler(this.GridViewPosted_DoubleClick);

            this.pnlPostedButtons.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlPostedButtons.Height = 46;

            this.btnViewPostedDetails.Text = "View Details";
            this.btnViewPostedDetails.Location = new System.Drawing.Point(12, 9);
            this.btnViewPostedDetails.Size = new System.Drawing.Size(120, 28);
            this.btnViewPostedDetails.Enabled = false;
            this.btnViewPostedDetails.Click += new System.EventHandler(this.BtnViewPostedDetails_Click);

            this.btnCopyPostedToNew.Text = "Copy to New Entry";
            this.btnCopyPostedToNew.Location = new System.Drawing.Point(140, 9);
            this.btnCopyPostedToNew.Size = new System.Drawing.Size(150, 28);
            this.btnCopyPostedToNew.Enabled = false;
            this.btnCopyPostedToNew.Appearance.BackColor = System.Drawing.Color.FromArgb(255, 244, 219);
            this.btnCopyPostedToNew.Appearance.Options.UseBackColor = true;
            this.btnCopyPostedToNew.Click += new System.EventHandler(this.BtnCopyPostedToNew_Click);

            this.pnlPostedButtons.Controls.Add(this.btnViewPostedDetails);
            this.pnlPostedButtons.Controls.Add(this.btnCopyPostedToNew);

            this.gridControlPostedDetails.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlPostedDetails.MainView = this.gridViewPostedDetails;
            this.gridControlPostedDetails.ViewCollection.Add(this.gridViewPostedDetails);
            this.gridViewPostedDetails.GridControl = this.gridControlPostedDetails;
            this.gridViewPostedDetails.OptionsBehavior.Editable = false;
            this.gridViewPostedDetails.OptionsView.ShowGroupPanel = false;

            this.tabPosted.Text = "Posted Vouchers";
            this.tabPosted.Controls.Add(this.gridControlPostedDetails);
            this.tabPosted.Controls.Add(this.pnlPostedButtons);
            this.tabPosted.Controls.Add(this.gridControlPosted);
            this.tabPosted.Controls.Add(this.pnlPostedFilter);
        }
        public void LoadData()
        {
            if (_dataLoaded) return;
            _dataLoaded = true;
            InitializeForm();
        }

        private void VoucheringManualFrm_Load(object sender, EventArgs e)
        {
            // Safety net — LoadData() is the real trigger if this form
            // is hosted inside another control; both are guarded so
            // whichever fires first wins.
            if (_dataLoaded) return;
            _dataLoaded = true;
            InitializeForm();

        }

        private void InitializeForm()
        {
            BindBranchLookup();
            BindSupplierLookup();
            BindGLAccountLookup();
            BindCreditGLCodeLookup();

            txtReferenceNo.Text = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");
            txtVoucherDate.DateTime = DateTime.Today;

            _glTable = new DataTable();
            _glTable.Columns.Add("AccountCode", typeof(string));
            _glTable.Columns.Add("Debit", typeof(decimal));
            _glTable.Columns.Add("Credit", typeof(decimal));
            _glTable.Columns.Add("Particulars", typeof(string));
            gridControlGL.DataSource = _glTable;
            AddGLLine();
            AddGLLine();

            RadVoucherType_CheckedChanged(null, null);
            UpdateTieStatus();
        }

        void ResetForNewEntry()
        {
            txtReferenceNo.Text = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");
            txtVoucherDate.DateTime = DateTime.Today;

            _glTable = new DataTable();
            _glTable.Columns.Add("AccountCode", typeof(string));
            _glTable.Columns.Add("Debit", typeof(decimal));
            _glTable.Columns.Add("Credit", typeof(decimal));
            _glTable.Columns.Add("Particulars", typeof(string));
            gridControlGL.DataSource = _glTable;
            AddGLLine();
            AddGLLine();

            RadVoucherType_CheckedChanged(null, null);
            UpdateTieStatus();
        }

        private void BindBranchLookup()
        {
            var dt = GetDataTable("SELECT BranchCode, BranchCode + '-' + BranchName AS DisplayText FROM Branches ORDER BY BranchCode");
            cboBranch.Properties.DataSource = dt;
            cboBranch.Properties.DisplayMember = "DisplayText";
            cboBranch.Properties.ValueMember = "BranchCode";
            cboBranch.Properties.PopulateColumns();
            foreach (DevExpress.XtraEditors.Controls.LookUpColumnInfo col in cboBranch.Properties.Columns)
                col.Visible = (col.FieldName == "DisplayText");
        }

        private void BindSupplierLookup()
        {
            Database.displaySearchlookupEdit(
                @"SELECT SupplierKey, SupplierID, SupplierName,
                         SupplierKey + ' - ' + SupplierName AS SupplierDisplay
                  FROM Supplier",
                cboSupplier, "SupplierDisplay", "SupplierKey");
        }
        private void BindCreditGLCodeLookup()
        {
            var dt = GetDataTable("SELECT AccountCode, Description FROM ChartOfAccounts WHERE AccountType='D' ORDER BY AccountCode");
            cboCreditGLCode.Properties.DataSource = dt;
            cboCreditGLCode.Properties.DisplayMember = "Description";
            cboCreditGLCode.Properties.ValueMember = "AccountCode";
            cboCreditGLCode.Properties.PopulateViewColumns();
            //cboCreditGLCode.Properties.View.Columns["DisplayText"].Visible = false;

        }
        private void BindGLAccountLookup()
        {
            var dt = GetDataTable("SELECT AccountCode, Description, AccountCode + '-' + Description AS DisplayText FROM ChartOfAccounts WHERE AccountType='D' ORDER BY AccountCode");
            repGLAccountCode.DataSource = dt;
            repGLAccountCode.DisplayMember = "DisplayText";
            repGLAccountCode.ValueMember = "AccountCode";
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

        private void RadVoucherType_CheckedChanged(object sender, EventArgs e)
        {
            bool isCheck = radCheckVoucher.Checked;
            lblCheckNo.Visible = isCheck;
            txtCheckNo.Visible = isCheck;
            lblControlNo.Visible = !isCheck;
            txtControlNo.Visible = !isCheck;
        }

        // ── Invoices ─────────────────────────────────────────────
        private void BtnLoadInvoices_Click(object sender, EventArgs e)
        {
            if (cboSupplier.EditValue == null)
            {
                XtraMessageBox.Show("Select a Supplier first.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("splist_Accounts", con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 120 })
                {
                    cmd.Parameters.Add("@parmsupplierid", SqlDbType.VarChar, 30).Value = cboSupplier.EditValue.ToString();
                    cmd.Parameters.Add("@parmispurchase", SqlDbType.Bit).Value = radioButtonPurchase.Checked;
                    cmd.Parameters.Add("@parmisexpense", SqlDbType.Bit).Value = radioButtonExpense.Checked;

                    var table = new DataTable();
                    con.Open();
                    new SqlDataAdapter(cmd).Fill(table);

                    // Client-side columns this module actually needs —
                    // NO EWTAmount/DiscountAmount/OffsetAmount/Variance
                    if (!table.Columns.Contains("Pay")) table.Columns.Add("Pay", typeof(bool));
                    if (!table.Columns.Contains("AmountToApply")) table.Columns.Add("AmountToApply", typeof(decimal));
                    foreach (DataRow row in table.Rows) row["AmountToApply"] = 0m;

                    _invoicesTable = table;
                    gridControlInvoices.DataSource = _invoicesTable;
                }

                gridViewInvoices.BestFitColumns();
                HideUnusedInvoiceColumns();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load invoices: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void HideUnusedInvoiceColumns()
        {
            // Hide whatever splist_Accounts still returns for the
            // old mapping-driven module's columns — this one doesn't
            // use them at all.
            string[] hide = { "EWTAmount", "DiscountAmount", "OffsetAmount", "ReturnAllowances", "Variance", "AmountPaid", "ShipmentNo", "Type" };
            foreach (var name in hide)
                if (gridViewInvoices.Columns[name] != null) gridViewInvoices.Columns[name].Visible = false;
        }

        private void GridViewInvoices_CustomRowCellEdit(object sender, CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "Pay") e.RepositoryItem = repPay;
            if (e.Column.FieldName == "AmountToApply") e.RepositoryItem = repInvAmount;
        }

        private void GridViewInvoices_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            if (e.Column.FieldName == "Pay")
            {
                bool isChecked = ToBool(e.Value);
                if (isChecked)
                {
                    decimal balance = ToDecimal(gridViewInvoices.GetRowCellValue(e.RowHandle, "Balance"));
                    gridViewInvoices.SetRowCellValue(e.RowHandle, "AmountToApply", balance);
                }
                else
                {
                    gridViewInvoices.SetRowCellValue(e.RowHandle, "AmountToApply", 0m);
                }
            }

            UpdateTieStatus();
        }

        private void GridViewInvoices_RowCellStyle(object sender, RowCellStyleEventArgs e)
        {
            bool isChecked = ToBool(gridViewInvoices.GetRowCellValue(e.RowHandle, "Pay"));
            if (isChecked) e.Appearance.BackColor = System.Drawing.Color.LightGreen;
        }

        // ── GL Entry ─────────────────────────────────────────────
        private void AddGLLine()
        {
            DataRow row = _glTable.NewRow();
            row["Debit"] = 0m; row["Credit"] = 0m;
            _glTable.Rows.Add(row);
        }

        private void BtnAddGLLine_Click(object sender, EventArgs e) => AddGLLine();

        private void BtnRemoveGLLine_Click(object sender, EventArgs e)
        {
            gridViewGL.DeleteSelectedRows();
            UpdateTieStatus();
        }

        private void GridViewGL_CustomRowCellEdit(object sender, CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "AccountCode") e.RepositoryItem = repGLAccountCode;
            if (e.Column.FieldName == "Debit") e.RepositoryItem = repGLDebit;
            if (e.Column.FieldName == "Credit") e.RepositoryItem = repGLCredit;
            if (e.Column.FieldName == "Particulars") e.RepositoryItem = repGLParticulars;
        }

        private void GridViewGL_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            if (e.Column.FieldName == "Debit" && ToDecimal(e.Value) > 0)
                gridViewGL.SetRowCellValue(e.RowHandle, "Credit", 0m);
            if (e.Column.FieldName == "Credit" && ToDecimal(e.Value) > 0)
                gridViewGL.SetRowCellValue(e.RowHandle, "Debit", 0m);

            UpdateTieStatus();
        }

        private void GridViewGL_RowCellStyle(object sender, RowCellStyleEventArgs e)
        {
            string acct = gridViewGL.GetRowCellValue(e.RowHandle, "AccountCode")?.ToString();
            decimal debit = ToDecimal(gridViewGL.GetRowCellValue(e.RowHandle, "Debit"));
            decimal credit = ToDecimal(gridViewGL.GetRowCellValue(e.RowHandle, "Credit"));
            if (string.IsNullOrWhiteSpace(acct) || (debit > 0 && credit > 0) || (debit == 0 && credit == 0))
                e.Appearance.BackColor = System.Drawing.Color.LightCoral;
        }

        // ── Live tie-check ───────────────────────────────────────
        private static readonly string[] APTradeAccounts = { "20101", "20102", "20103" };

        private void UpdateTieStatus()
        {
            decimal totalAmountToApply = 0;
            if (gridViewInvoices.GridControl != null && _invoicesTable != null)
                for (int i = 0; i < gridViewInvoices.RowCount; i++)
                    if (ToBool(gridViewInvoices.GetRowCellValue(i, "Pay")))
                        totalAmountToApply += ToDecimal(gridViewInvoices.GetRowCellValue(i, "AmountToApply"));

            decimal apTradeDebit = 0, totalDebit = 0, totalCredit = 0;
            for (int i = 0; i < gridViewGL.RowCount; i++)
            {
                string acct = gridViewGL.GetRowCellValue(i, "AccountCode")?.ToString();
                decimal debit = ToDecimal(gridViewGL.GetRowCellValue(i, "Debit"));
                decimal credit = ToDecimal(gridViewGL.GetRowCellValue(i, "Credit"));
                totalDebit += debit;
                totalCredit += credit;
                if (Array.IndexOf(APTradeAccounts, acct) >= 0) apTradeDebit += debit;
            }

            // This tie-check is unchanged — still the critical link
            // between "what's being paid" and "what AP-Trade extinguishes"
            if (apTradeDebit == totalAmountToApply && totalAmountToApply > 0)
            {
                lblTieStatus.Text = $"Invoices total {totalAmountToApply:N2} — matches AP-Trade debit {apTradeDebit:N2}. ✓";
                lblTieStatus.Appearance.ForeColor = System.Drawing.Color.SeaGreen;
            }
            else
            {
                lblTieStatus.Text = $"Invoices total {totalAmountToApply:N2} — AP-Trade debit (20101/20102/20103) is {apTradeDebit:N2}. These must match.";
                lblTieStatus.Appearance.ForeColor = System.Drawing.Color.DarkOrange;
            }

            // NEW: the grid no longer needs Debit == Credit on its own —
            // whatever's left over (Debit total − Credit total) is the
            // cash amount that auto-posts to Credit GLCode. Only flag a
            // problem if the residual is negative (credits exceed debits
            // — nothing to credit against Cash, the entry is backwards)
            // or zero when the grid actually has content (no cash
            // movement at all, unusual for a payment voucher).
            decimal residualCash = totalDebit - totalCredit;

            if (totalDebit == 0 && totalCredit == 0)
            {
                lblBalanceStatus.Text = "";
                lblBalanceStatus.Visible = false;
            }
            else if (residualCash < 0)
            {
                lblBalanceStatus.Text = $"GL entry's Credit total exceeds Debit total by {Math.Abs(residualCash):N2} — check your entries.";
                lblBalanceStatus.Visible = true;
            }
            else if (residualCash == 0)
            {
                lblBalanceStatus.Text = "No residual cash — Debit and Credit in the grid already balance, so nothing would post to Credit GLCode.";
                lblBalanceStatus.Visible = true;
            }
            else
            {
                lblBalanceStatus.Text = $"Residual cash to Credit GLCode: {residualCash:N2}";
                lblBalanceStatus.Appearance.ForeColor = System.Drawing.Color.SeaGreen;
                lblBalanceStatus.Visible = true;
            }
        }

        // ── Helpers ──────────────────────────────────────────────
        private decimal ToDecimal(object value)
        {
            if (value == null || value == DBNull.Value) return 0m;
            decimal.TryParse(value.ToString(), out decimal result);
            return result;
        }

        private bool ToBool(object value)
        {
            if (value == null || value == DBNull.Value) return false;
            if (value is bool b) return b;
            bool.TryParse(value.ToString(), out bool result);
            return result;
        }

        // ── Post ─────────────────────────────────────────────────
        private DataTable BuildInvoiceLinesTVP()
        {
            var dt = new DataTable();
            dt.Columns.Add("BranchCode", typeof(string));
            dt.Columns.Add("InvoiceNo", typeof(string));
            dt.Columns.Add("SequenceReferenceNumber", typeof(string));
            dt.Columns.Add("BatchReferenceID", typeof(long));
            dt.Columns.Add("AmountPaid", typeof(decimal));

            for (int i = 0; i < gridViewInvoices.RowCount; i++)
            {
                if (!ToBool(gridViewInvoices.GetRowCellValue(i, "Pay"))) continue;

                decimal amt = ToDecimal(gridViewInvoices.GetRowCellValue(i, "AmountToApply"));
                if (amt <= 0) continue;

                string branch = gridViewInvoices.GetRowCellValue(i, "BranchCode")?.ToString() ?? cboBranch.EditValue?.ToString();
                string invoiceNo = gridViewInvoices.GetRowCellValue(i, "InvoiceNo")?.ToString();

                object seqRefObj = gridViewInvoices.GetRowCellValue(i, "SequenceNumber");
                object batchRefObj = gridViewInvoices.GetRowCellValue(i, "BatchReferenceID");

                dt.Rows.Add(
                    branch, invoiceNo,
                    seqRefObj == null || seqRefObj == DBNull.Value ? (object)DBNull.Value : seqRefObj.ToString(),
                    batchRefObj == null || batchRefObj == DBNull.Value ? (object)DBNull.Value : Convert.ToInt64(batchRefObj),
                    amt);
            }
            return dt;
        }

        private DataTable BuildGLLinesTVP()
        {
            var dt = new DataTable();
            dt.Columns.Add("AccountCode", typeof(string));
            dt.Columns.Add("Debit", typeof(decimal));
            dt.Columns.Add("Credit", typeof(decimal));
            dt.Columns.Add("Particulars", typeof(string));

            for (int i = 0; i < gridViewGL.RowCount; i++)
            {
                string acct = gridViewGL.GetRowCellValue(i, "AccountCode")?.ToString();
                decimal debit = ToDecimal(gridViewGL.GetRowCellValue(i, "Debit"));
                decimal credit = ToDecimal(gridViewGL.GetRowCellValue(i, "Credit"));
                string particulars = gridViewGL.GetRowCellValue(i, "Particulars")?.ToString() ?? "";

                if (string.IsNullOrWhiteSpace(acct) || (debit == 0 && credit == 0)) continue;

                dt.Rows.Add(acct, debit, credit, particulars);
            }
            return dt;
        }

        private bool ValidateForm()
        {
            if (cboSupplier.EditValue == null)
            {
                XtraMessageBox.Show("Select a Supplier.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
            if (cboBranch.EditValue == null)
            {
                XtraMessageBox.Show("Select a Branch.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
            if (radCheckVoucher.Checked && string.IsNullOrWhiteSpace(txtCheckNo.Text))
            {
                XtraMessageBox.Show("Check No. is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
            if (!radCheckVoucher.Checked && string.IsNullOrWhiteSpace(txtControlNo.Text))
            {
                XtraMessageBox.Show("Control No. is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            // Invoices are OPTIONAL — this module also supports pure
            // GL-to-GL fund transfers (Cash to Cash, no invoice paid)
            var invLines = BuildInvoiceLinesTVP();
            // NEW: block overpayment for Check/Cash — Telegraphic is
            // exempt since the excess can be booked via the manual GL
            // entry (bank charges, FX differences, etc.)
            bool blocksOverpayment = radCheckVoucher.Checked || radCashVoucher.Checked;
            if (blocksOverpayment)
            {
                for (int i = 0; i < gridViewInvoices.RowCount; i++)
                {
                    if (!ToBool(gridViewInvoices.GetRowCellValue(i, "Pay"))) continue;

                    decimal amt = ToDecimal(gridViewInvoices.GetRowCellValue(i, "AmountToApply"));
                    decimal balance = ToDecimal(gridViewInvoices.GetRowCellValue(i, "Balance"));
                    string invNo = gridViewInvoices.GetRowCellValue(i, "InvoiceNo")?.ToString();

                    if (amt > balance)
                    {
                        XtraMessageBox.Show(
                            $"Invoice {invNo}: Amount to Apply ({amt:N2}) exceeds its Balance ({balance:N2}).\nNot allowed for Check/Cash vouchers — use Telegraphic if the excess needs to be booked via GL entries.",
                            "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        return false;
                    }
                }
            }
            var glLines = BuildGLLinesTVP();
            if (glLines.Rows.Count == 0)
            {
                XtraMessageBox.Show("The GL entry needs at least one line.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            if (cboCreditGLCode.EditValue == null)
            {
                XtraMessageBox.Show("Select a Credit GLCode.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            decimal totalDebit = 0, totalCredit = 0, apTradeDebit = 0, totalApplied = 0;
            foreach (DataRow r in glLines.Rows)
            {
                decimal d = Convert.ToDecimal(r["Debit"]), c = Convert.ToDecimal(r["Credit"]);
                totalDebit += d; totalCredit += c;
                if (Array.IndexOf(APTradeAccounts, r["AccountCode"].ToString()) >= 0) apTradeDebit += d;
            }
            foreach (DataRow r in invLines.Rows) totalApplied += Convert.ToDecimal(r["AmountPaid"]);

            if (apTradeDebit != totalApplied)
            {
                XtraMessageBox.Show(
                    $"The GL entry's AP-Trade debit total ({apTradeDebit:N2}) does not match the sum of invoice amounts ({totalApplied:N2}).",
                    "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            decimal residualCash = totalDebit - totalCredit;
            if (residualCash <= 0)
            {
                XtraMessageBox.Show(
                    residualCash < 0
                        ? $"GL entry's Credit total exceeds Debit total by {Math.Abs(residualCash):N2} — check your entries."
                        : "No residual cash — nothing would post to Credit GLCode.",
                    "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            return true;
        }
    

        private void BtnPost_Click(object sender, EventArgs e)
        {
            if (!ValidateForm()) return;

            if (XtraMessageBox.Show("Post this voucher?", "Confirm", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;

            var invLines = BuildInvoiceLinesTVP();
            var glLines = BuildGLLinesTVP();

            string voucherType = radCheckVoucher.Checked ? "CHECK" : radCashVoucher.Checked ? "CASH" : "TELEGRAPHIC";
            string payMethod = radioButtonPurchase.Checked ? "PURCHASE" : "EXPENSE";
            string voucherId = IDGenerator.getIDNumberSP("sp_GetVoucherNumber", "TicketNumber");

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_PostVoucherManual", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 120;

                    cmd.Parameters.Add("@parmrefno", SqlDbType.VarChar, 10).Value = txtReferenceNo.Text.Trim();
                    cmd.Parameters.Add("@parmvoucherid", SqlDbType.VarChar, 10).Value = voucherId;
                    cmd.Parameters.Add("@parmsupplierid", SqlDbType.VarChar, 50).Value = cboSupplier.EditValue.ToString();
                    cmd.Parameters.Add("@parmsuppliername", SqlDbType.VarChar, 150).Value = cboSupplier.Text;
                    cmd.Parameters.Add("@parmpaymethod", SqlDbType.VarChar, 20).Value = payMethod;
                    cmd.Parameters.Add("@parmvouchertype", SqlDbType.VarChar, 50).Value = voucherType;
                    cmd.Parameters.Add("@parmcheckno", SqlDbType.VarChar, 50).Value =
                        radCheckVoucher.Checked ? (object)txtCheckNo.Text.Trim() : DBNull.Value;
                    cmd.Parameters.Add("@parmcontrolno", SqlDbType.VarChar, 50).Value =
                        !radCheckVoucher.Checked ? (object)txtControlNo.Text.Trim() : DBNull.Value;
                    cmd.Parameters.Add("@parmvoucherdate", SqlDbType.Date).Value = txtVoucherDate.DateTime;
                    cmd.Parameters.Add("@parmremarks", SqlDbType.VarChar, 2000).Value = txtRemarks.Text.Trim();
                    cmd.Parameters.Add("@parmpreparedby", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    cmd.Parameters.Add("@parmbranch", SqlDbType.VarChar, 5).Value = cboBranch.EditValue.ToString();
                    cmd.Parameters.Add("@parmcreditglcode", SqlDbType.VarChar, 20).Value = cboCreditGLCode.EditValue.ToString();

                    var invParam = cmd.Parameters.AddWithValue("@InvoiceLines", invLines);
                    invParam.SqlDbType = SqlDbType.Structured;
                    invParam.TypeName = "dbo.VoucherManualInvoiceTVP";

                    var glParam = cmd.Parameters.AddWithValue("@GLLines", glLines);
                    glParam.SqlDbType = SqlDbType.Structured;
                    glParam.TypeName = "dbo.VoucherManualGLLineTVP";

                    con.Open();
                    string message = "Voucher posted successfully.";
                    using (var rdr = cmd.ExecuteReader())
                        if (rdr.Read()) message = rdr["Message"]?.ToString() ?? message;

                    XtraMessageBox.Show(message, "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }

                //Close();
                ResetForNewEntry();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Post failed:\n{ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void BtnClose_Click(object sender, EventArgs e) => ResetForNewEntry(); //Close();

        private void TabMain_SelectedPageChanged(object sender, DevExpress.XtraTab.TabPageChangedEventArgs e)
        {
            if (e.Page == tabPosted && gridControlPosted.DataSource == null)
                LoadPostedVouchers();
        }

        private void BtnRefreshPosted_Click(object sender, EventArgs e) => LoadPostedVouchers();

        private void LoadPostedVouchers()
        {
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_GetPostedVouchersManual", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value =
                        txtPostedDateFrom.EditValue == null ? (object)DBNull.Value : txtPostedDateFrom.DateTime;
                    cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value =
                        txtPostedDateTo.EditValue == null ? (object)DBNull.Value : txtPostedDateTo.DateTime;

                    var dt = new DataTable();
                    con.Open();
                    new SqlDataAdapter(cmd).Fill(dt);
                    gridControlPosted.DataSource = dt;
                }

                gridViewPosted.BestFitColumns();
                if (gridViewPosted.Columns["SupplierID"] != null) gridViewPosted.Columns["SupplierID"].Visible = false;

                gridControlPostedDetails.DataSource = null;
                btnViewPostedDetails.Enabled = false;
                btnCopyPostedToNew.Enabled = false;
                _selectedPostedRefNo = null;
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load posted vouchers: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void GridViewPosted_FocusedRowChanged(object sender, DevExpress.XtraGrid.Views.Base.FocusedRowChangedEventArgs e)
        {
            bool has = gridViewPosted.FocusedRowHandle >= 0;
            btnViewPostedDetails.Enabled = has;
            btnCopyPostedToNew.Enabled = has;
            _selectedPostedRefNo = has ? gridViewPosted.GetFocusedRowCellValue("ReferenceNumber")?.ToString() : null;
        }

        private void GridViewPosted_DoubleClick(object sender, EventArgs e)
        {
            if (gridViewPosted.FocusedRowHandle >= 0) LoadSelectedPostedDetails();
        }

        private void BtnViewPostedDetails_Click(object sender, EventArgs e) => LoadSelectedPostedDetails();

        private (DataTable header, DataTable invoices, DataTable glLines) FetchPostedDetails(string refNo)
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("sp_GetVoucherManualDetails", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@ReferenceNumber", SqlDbType.VarChar, 10).Value = refNo;

                con.Open();
                using (var da = new SqlDataAdapter(cmd))
                {
                    var ds = new DataSet();
                    da.Fill(ds);
                    var header = ds.Tables.Count > 0 ? ds.Tables[0] : new DataTable();
                    var invoices = ds.Tables.Count > 1 ? ds.Tables[1] : new DataTable();
                    var glLines = ds.Tables.Count > 2 ? ds.Tables[2] : new DataTable();
                    return (header, invoices, glLines);
                }
            }
        }

        private void LoadSelectedPostedDetails()
        {
            if (string.IsNullOrEmpty(_selectedPostedRefNo)) return;

            try
            {
                var (header, invoices, glLines) = FetchPostedDetails(_selectedPostedRefNo);
                // Simple combined view: GL lines are the more useful
                // detail to see at a glance; swap to `invoices` if you'd
                // rather default to the invoice list instead
                gridControlPostedDetails.DataSource = glLines;
                gridViewPostedDetails.BestFitColumns();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load details: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void BtnCopyPostedToNew_Click(object sender, EventArgs e)
        {
            if (string.IsNullOrEmpty(_selectedPostedRefNo)) return;

            DataTable glLines;
            try
            {
                var result = FetchPostedDetails(_selectedPostedRefNo);
                glLines = result.glLines;
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load voucher for copying: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            if (glLines.Rows.Count == 0)
            {
                XtraMessageBox.Show("This voucher has no GL lines to copy.", "Nothing to Copy", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            // --- NEW: Grab the Voucher Type and Check No. directly from the Grid ---
            string voucherType = gridViewPosted.GetFocusedRowCellValue("VoucherType")?.ToString();
            string physicalRef = gridViewPosted.GetFocusedRowCellValue("PhysicalRef")?.ToString();
            // Check the right radio button (which triggers visibility) and paste the number
            if (voucherType == "CHECK")
            {
                radCheckVoucher.Checked = true;
                txtCheckNo.Text = physicalRef;
            }
            else if (voucherType == "CASH")
            {
                radCashVoucher.Checked = true;
                txtControlNo.Text = physicalRef;
            }
            else if (voucherType == "TELEGRAPHIC")
            {
                radTelegraphic.Checked = true;
                txtControlNo.Text = physicalRef;
            }
            // -----------------------------------------------------------------------
            // Fresh Reference No, empty invoice grid (invoices aren't
            // copied — a copy is for repeating a similar GL pattern,
            // not re-paying the same invoices) — adjust the reset call
            // to whatever your actual "start new entry" method is named
            txtReferenceNo.Text = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");
            _glTable.Rows.Clear();

            foreach (DataRow src in glLines.Rows)
            {
                DataRow row = _glTable.NewRow();
                row["AccountCode"] = src["AccountCode"];
                row["Debit"] = src["Debit"];
                row["Credit"] = src["Credit"];
                row["Particulars"] = src["Particulars"];
                _glTable.Rows.Add(row);
            }

            gridViewGL.BestFitColumns();
            UpdateTieStatus();
            tabMain.SelectedTabPage = tabNewVoucher;

            // IMPORTANT: flags the double-credit risk explicitly rather
            // than letting it happen silently — see note above this file
            XtraMessageBox.Show(
                $"Copied {glLines.Rows.Count} GL line(s) from {_selectedPostedRefNo}.\n\n" +
                "IMPORTANT: this includes the original voucher's Credit GLCode leg as a regular line. " +
                "Since posting will auto-generate a NEW Credit GLCode leg for whatever residual remains, " +
                "review the copied lines and remove the old cash-credit line before posting, or you may " +
                "double-credit the cash account.\n\nA new Reference No. was assigned — no invoices were copied.",
                "Copied — Review Before Posting", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }
}