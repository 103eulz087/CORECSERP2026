using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.AccountingDevEx
{
    /// <summary>
    /// Vouchering — Manual, with auto AP-Trade/Variance legs. Checking
    /// an invoice to pay no longer needs a matching AP-Trade line typed
    /// into the GL grid — Amount to Apply and Variance each auto-post
    /// their OWN two-leg pair directly (see
    /// SQL/2026-09-15_VoucheringManual_AutoAPTradeLegs.sql):
    ///   Amount-To-Apply: Debit AP-Trade / Credit Credit-GLCode, both = AmountToApply
    ///   Variance (loss): Debit 60323 / Credit AP-Trade, both = Variance
    ///   Variance (gain): Debit AP-Trade / Credit 60323, both = -Variance
    /// AP-Trade account is resolved server-side per payment method via
    /// dbo.JournalEntryMapping (Mnemonic='VOUCHER-MANUAL-APTRADE',
    /// ConditionFlag='PURCHASE'->20101, 'EXPENSE'->20103 fallback when
    /// ExpenseSummary.PayableAccountCode isn't set) — this form has no
    /// say in which account gets used. All auto legs tag BranchCode as
    /// the voucher's PAYING branch (cboBranch/@parmbranch), never the
    /// invoice's own branch.
    ///
    /// This module is Telegraphic-only in practice — the Check/Cash
    /// radio buttons are hidden (Designer: Visible=false) and
    /// Telegraphic defaults checked; their code paths still exist
    /// (dead but harmless) since Copy-to-New reads the type off old
    /// historical vouchers that may predate this restriction.
    ///
    /// The GL grid below (gridViewGL) is independent of the invoices —
    /// pure free-form manual entry (e.g. a cash advance: just a single
    /// Debit "Advances to Supplier" line, no invoice attached). When NO
    /// invoices are checked, the grid does NOT need to self-balance —
    /// whatever it nets to auto-posts as the offsetting leg against the
    /// selected Credit GLCode (see SQL/2026-09-16_VoucheringManual_
    /// ResidualAutoPost.sql), same as SupplierPaymentDevEx.cs. When
    /// invoices ARE being paid, the grid must balance on its own (no
    /// AP-Trade line required there — Amount to Apply/Variance already
    /// auto-post their own AP-Trade legs against Credit GLCode, so a
    /// second unbalanced residual would double up on that account). It
    /// is NOT mandatory — paying an invoice with zero manual GL lines is
    /// valid and posts fine. Checking Pay defaults Amount to Apply to the
    /// invoice's Balance; editing Amount to Apply auto-fills Variance
    /// with the difference (an FX gain/loss, the invoice still settles
    /// in full). To pay only PART of an invoice, lower Amount to Apply
    /// and then set Variance to 0 — the row turns amber, the invoice is
    /// reduced by Amount to Apply only (status PARTIAL) and no FX leg
    /// posts (SQL/2026-09-21_VoucheringManual_PartialPayment.sql).
    /// Variance is editable ONLY to 0 (any other typed value reverts to
    /// the computed one); partial + FX on the same row isn't supported.
    ///
    /// Reuses your existing splist_Accounts SP for the invoice list
    /// (same one the original SupplierPaymentDevEx uses) — assumed
    /// stable in shape; only SequenceNumber/BatchReferenceID/
    /// BranchCode/InvoiceNo/InvoiceDate/ActualCost/Balance are read
    /// from it, everything EWT/Discount-related is ignored. Variance
    /// is this module's OWN client-side-computed column, not read
    /// from splist_Accounts.
    /// </summary>
    public partial class VoucheringManualFrm : DevExpress.XtraEditors.XtraUserControl
    {
        private DataTable _invoicesTable;
        private DataTable _glTable;
        private bool _dataLoaded = false;
        private string _selectedPostedRefNo;
        private bool _isRecalculating = false;   // guards AmountToApply/Variance cascade in GridViewInvoices_CellValueChanged
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
            // Missing calendar dropdown button -- without this a DateEdit
            // renders with no visible way to open the calendar picker,
            // reading as a plain textbox despite being a real DateEdit.
            this.txtPostedDateFrom.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
                new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo) });

            this.lblPostedDateTo.Text = "To:";
            this.lblPostedDateTo.Location = new System.Drawing.Point(190, 18);
            this.txtPostedDateTo.Location = new System.Drawing.Point(214, 13);
            this.txtPostedDateTo.Size = new System.Drawing.Size(120, 20);
            this.txtPostedDateTo.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
                new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo) });

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

            // The invoice grid holds Balances as of the last Load Invoices —
            // after a post (esp. a partial, where the invoice stays open)
            // they're stale, so drop them; the user reloads for the next entry.
            ClearInvoiceGrid();

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

        // Drops the loaded invoices (and their Balances) — used after a post
        // and when copying a posted voucher into a new entry.
        private void ClearInvoiceGrid()
        {
            _invoicesTable = null;
            gridControlInvoices.DataSource = null;
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
            // Known Bug Pattern #2: without this, free text bypasses ValueMember.
            repGLAccountCode.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;
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
                    // NO EWTAmount/DiscountAmount/OffsetAmount. Variance
                    // IS used here (unlike the mapping-driven module) —
                    // it's the FX difference between Amount to Apply and
                    // Balance, always reset fresh on load, never trusted
                    // from whatever splist_Accounts happens to return.
                    if (!table.Columns.Contains("Pay")) table.Columns.Add("Pay", typeof(bool));
                    if (!table.Columns.Contains("AmountToApply")) table.Columns.Add("AmountToApply", typeof(decimal));
                    if (!table.Columns.Contains("Variance")) table.Columns.Add("Variance", typeof(decimal));
                    foreach (DataRow row in table.Rows) { row["AmountToApply"] = 0m; row["Variance"] = 0m; }

                    _invoicesTable = table;
                    gridControlInvoices.DataSource = _invoicesTable;
                }

                HideUnusedInvoiceColumns();
                FormatInvoiceColumns();
                gridViewInvoices.BestFitColumns();   // after formatting, so Variance's caption/n2 format is sized in
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
            // use them at all. Variance is NOT hidden — it's this
            // module's own FX-variance column (Amount to Apply minus
            // Balance), not the mapping-driven module's field.
            string[] hide = { "EWTAmount", "DiscountAmount", "OffsetAmount", "ReturnAllowances", "AmountPaid", "ShipmentNo", "Type" };
            foreach (var name in hide)
                if (gridViewInvoices.Columns[name] != null) gridViewInvoices.Columns[name].Visible = false;
        }

        private void FormatInvoiceColumns()
        {
            // Variance is derived (Amount to Apply - Balance). The only
            // manual edit allowed is setting it to 0 to mark a partial
            // payment — GridViewInvoices_CellValueChanged reverts any
            // other typed value to the computed one.
            var varianceCol = gridViewInvoices.Columns["Variance"];
            if (varianceCol != null)
            {
                varianceCol.Caption = "Variance (FX)";
                varianceCol.ToolTip = "Auto-filled as Amount to Apply - Balance (FX gain/loss). Set to 0 to pay this invoice only partially.";
                varianceCol.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                varianceCol.DisplayFormat.FormatString = "n2";
                varianceCol.OptionsColumn.AllowEdit = true;
            }

            // Let a cleared Variance cell commit as null (instead of 0) so
            // GridViewInvoices_CellValueChanged can tell "cleared" apart from
            // a deliberate 0 = partial and snap it back.
            repInvAmount.AllowNullInput = DevExpress.Utils.DefaultBoolean.True;

            // Everything else splist_Accounts returns (Balance, InvoiceNo,
            // ...) is reference data — only Pay / Amount to Apply / Variance
            // are user-editable. Balance in particular feeds Variance,
            // IsPartialRow and the ExpectedBalance sent to the SP.
            foreach (DevExpress.XtraGrid.Columns.GridColumn col in gridViewInvoices.Columns)
                col.OptionsColumn.AllowEdit = col.FieldName == "Pay" || col.FieldName == "AmountToApply" || col.FieldName == "Variance";
        }

        private void GridViewInvoices_CustomRowCellEdit(object sender, CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "Pay") e.RepositoryItem = repPay;
            if (e.Column.FieldName == "AmountToApply" || e.Column.FieldName == "Variance") e.RepositoryItem = repInvAmount;
        }

        // A checked row whose Variance was zeroed while Amount to Apply is
        // still below Balance = a deliberate partial payment.
        private bool IsPartialRow(int rowHandle)
        {
            if (!ToBool(gridViewInvoices.GetRowCellValue(rowHandle, "Pay"))) return false;
            decimal amt = ToDecimal(gridViewInvoices.GetRowCellValue(rowHandle, "AmountToApply"));
            decimal balance = ToDecimal(gridViewInvoices.GetRowCellValue(rowHandle, "Balance"));
            decimal variance = ToDecimal(gridViewInvoices.GetRowCellValue(rowHandle, "Variance"));
            return amt > 0 && Math.Round(variance, 2) == 0 && Math.Round(amt, 2) < Math.Round(balance, 2);
        }

        private void GridViewInvoices_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            if (_isRecalculating) return;   // suppress cascading SetRowCellValue re-entrancy

            if (e.Column.FieldName == "Pay")
            {
                bool isChecked = ToBool(e.Value);
                _isRecalculating = true;
                try
                {
                    // Checking Pay always fully settles the invoice —
                    // Amount to Apply defaults to Balance and Variance
                    // resets to 0 until the user edits Amount to Apply
                    // to reflect the actual (FX-converted) cash figure.
                    if (isChecked)
                    {
                        decimal balance = ToDecimal(gridViewInvoices.GetRowCellValue(e.RowHandle, "Balance"));
                        gridViewInvoices.SetRowCellValue(e.RowHandle, "AmountToApply", balance);
                    }
                    else
                    {
                        gridViewInvoices.SetRowCellValue(e.RowHandle, "AmountToApply", 0m);
                    }
                    gridViewInvoices.SetRowCellValue(e.RowHandle, "Variance", 0m);
                }
                finally
                {
                    _isRecalculating = false;
                }

                UpdateTieStatus();
                return;
            }

            if (e.Column.FieldName == "Variance")
            {
                // Only 0 (= partial payment) may be typed — anything else
                // snaps back to the computed FX variance, so Variance can't
                // be used to fudge an arbitrary gain/loss. Unchecked rows
                // just stay at 0.
                decimal balanceV = ToDecimal(gridViewInvoices.GetRowCellValue(e.RowHandle, "Balance"));
                decimal amtV = ToDecimal(gridViewInvoices.GetRowCellValue(e.RowHandle, "AmountToApply"));
                decimal entered = ToDecimal(e.Value);
                bool paying = ToBool(gridViewInvoices.GetRowCellValue(e.RowHandle, "Pay"));
                decimal allowed = paying ? amtV - balanceV : 0m;

                // Snap back to the computed value when: the cell was
                // cleared (blank must not silently mean "partial"), a value
                // other than 0/computed was typed, or 0 was typed while
                // Amount to Apply is ABOVE Balance (0 only means "partial"
                // when there is something left over to leave open).
                bool blank = e.Value == null || e.Value == DBNull.Value;
                entered = Math.Round(entered, 2);
                allowed = Math.Round(allowed, 2);
                bool zeroButOverBalance = paying && entered == 0 && Math.Round(amtV, 2) > Math.Round(balanceV, 2);

                if (blank || zeroButOverBalance || (entered != 0 && entered != allowed))
                {
                    _isRecalculating = true;
                    try { gridViewInvoices.SetRowCellValue(e.RowHandle, "Variance", allowed); }
                    finally { _isRecalculating = false; }
                }

                UpdateTieStatus();
                return;
            }

            if (e.Column.FieldName == "AmountToApply" && ToBool(gridViewInvoices.GetRowCellValue(e.RowHandle, "Pay")))
            {
                // Variance = the difference between what's actually
                // being paid and the invoice's recorded Balance — this
                // is always FX movement (USD-invoiced supplier,
                // converted at today's rate vs. the invoice's booking
                // rate), since the invoice is still being paid in full.
                decimal balance = ToDecimal(gridViewInvoices.GetRowCellValue(e.RowHandle, "Balance"));
                decimal amountToApply = ToDecimal(e.Value);
                _isRecalculating = true;
                try
                {
                    gridViewInvoices.SetRowCellValue(e.RowHandle, "Variance", Math.Round(amountToApply - balance, 2));
                }
                finally
                {
                    _isRecalculating = false;
                }
            }

            UpdateTieStatus();
        }

        private void GridViewInvoices_RowCellStyle(object sender, RowCellStyleEventArgs e)
        {
            bool isChecked = ToBool(gridViewInvoices.GetRowCellValue(e.RowHandle, "Pay"));
            if (isChecked) e.Appearance.BackColor = IsPartialRow(e.RowHandle)
                ? System.Drawing.Color.Gold          // partial payment — invoice stays open
                : System.Drawing.Color.LightGreen;
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

        // ── Live status ──────────────────────────────────────────
        private void UpdateTieStatus()
        {
            // NEW: no more AP-Trade tie-check — Amount to Apply and
            // Variance each auto-post their own AP-Trade leg now (see
            // sp_PostVoucherManual). This is just a preview of what
            // will auto-post, for the user's own sanity check before
            // hitting Post.
            decimal totalAmountToApply = 0, totalVariance = 0;
            var partialNotes = new System.Collections.Generic.List<string>();
            if (gridViewInvoices.GridControl != null && _invoicesTable != null)
                for (int i = 0; i < gridViewInvoices.RowCount; i++)
                    if (ToBool(gridViewInvoices.GetRowCellValue(i, "Pay")))
                    {
                        totalAmountToApply += ToDecimal(gridViewInvoices.GetRowCellValue(i, "AmountToApply"));
                        totalVariance += ToDecimal(gridViewInvoices.GetRowCellValue(i, "Variance"));

                        if (IsPartialRow(i))
                        {
                            decimal pAmt = ToDecimal(gridViewInvoices.GetRowCellValue(i, "AmountToApply"));
                            decimal pBal = ToDecimal(gridViewInvoices.GetRowCellValue(i, "Balance"));
                            partialNotes.Add($"{gridViewInvoices.GetRowCellValue(i, "InvoiceNo")}: paying {pAmt:N2}, {pBal - pAmt:N2} stays open");
                        }
                    }

            if (totalAmountToApply <= 0)
            {
                lblTieStatus.Text = "No invoices checked — nothing will auto-post for AP-Trade/Cash/FX.";
                lblTieStatus.Appearance.ForeColor = System.Drawing.Color.Gray;
            }
            else
            {
                string fxPart = totalVariance == 0 ? ""
                    : totalVariance > 0
                        ? $" + FX loss {totalVariance:N2} (Debit 60323 / Credit AP-Trade)"
                        : $" + FX gain {-totalVariance:N2} (Debit AP-Trade / Credit 60323)";
                string partialPart = partialNotes.Count == 0 ? ""
                    : " PARTIAL — " + string.Join("; ", partialNotes) + ".";
                lblTieStatus.Text = $"Auto-posts: Debit AP-Trade / Credit Credit-GLCode {totalAmountToApply:N2}{fxPart}.{partialPart}";
                lblTieStatus.Appearance.ForeColor = partialNotes.Count == 0
                    ? System.Drawing.Color.SeaGreen
                    : System.Drawing.Color.DarkGoldenrod;
            }

            // CHANGED 2026-09-16: when no invoices are checked, the
            // manual GL grid no longer needs to self-balance — any
            // leftover Debit/Credit difference auto-posts to the
            // selected Credit GLCode (e.g. a lone "Advances to
            // Supplier" Debit line, no invoice attached). When invoices
            // ARE checked, the grid still must balance on its own —
            // Amount to Apply/Variance already auto-post their own
            // AP-Trade legs against Credit GLCode there.
            decimal totalDebit = 0, totalCredit = 0;
            for (int i = 0; i < gridViewGL.RowCount; i++)
            {
                totalDebit += ToDecimal(gridViewGL.GetRowCellValue(i, "Debit"));
                totalCredit += ToDecimal(gridViewGL.GetRowCellValue(i, "Credit"));
            }
            decimal glDiff = totalDebit - totalCredit;
            bool payingInvoices = totalAmountToApply > 0;

            if (totalDebit == 0 && totalCredit == 0)
            {
                lblBalanceStatus.Text = "";
                lblBalanceStatus.Visible = false;
            }
            else if (glDiff != 0 && payingInvoices)
            {
                lblBalanceStatus.Text = $"Manual GL entry is out of balance: Debit {totalDebit:N2} vs Credit {totalCredit:N2} — when paying invoices it must balance on its own (Amount to Apply/Variance already auto-post their own AP-Trade legs).";
                lblBalanceStatus.Appearance.ForeColor = System.Drawing.Color.DarkOrange;
                lblBalanceStatus.Visible = true;
            }
            else if (glDiff != 0)
            {
                string side = glDiff > 0 ? "Credit" : "Debit";
                lblBalanceStatus.Text = $"Manual GL entry: Debit {totalDebit:N2} vs Credit {totalCredit:N2} — residual {Math.Abs(glDiff):N2} auto-posts as a {side} to the selected Credit GLCode.";
                lblBalanceStatus.Appearance.ForeColor = System.Drawing.Color.SeaGreen;
                lblBalanceStatus.Visible = true;
            }
            else
            {
                lblBalanceStatus.Text = $"Manual GL entry balances: Debit {totalDebit:N2} = Credit {totalCredit:N2}. ✓";
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
            dt.Columns.Add("Variance", typeof(decimal));
            dt.Columns.Add("ExpectedBalance", typeof(decimal));   // NEW — must stay LAST, matches dbo.VoucherManualInvoiceTVP_v3's column order

            for (int i = 0; i < gridViewInvoices.RowCount; i++)
            {
                if (!ToBool(gridViewInvoices.GetRowCellValue(i, "Pay"))) continue;

                decimal amt = ToDecimal(gridViewInvoices.GetRowCellValue(i, "AmountToApply"));
                if (amt <= 0) continue;

                decimal variance = ToDecimal(gridViewInvoices.GetRowCellValue(i, "Variance"));

                string branch = gridViewInvoices.GetRowCellValue(i, "BranchCode")?.ToString() ?? cboBranch.EditValue?.ToString();
                string invoiceNo = gridViewInvoices.GetRowCellValue(i, "InvoiceNo")?.ToString();

                object seqRefObj = gridViewInvoices.GetRowCellValue(i, "SequenceNumber");
                object batchRefObj = gridViewInvoices.GetRowCellValue(i, "BatchReferenceID");

                dt.Rows.Add(
                    branch, invoiceNo,
                    seqRefObj == null || seqRefObj == DBNull.Value ? (object)DBNull.Value : seqRefObj.ToString(),
                    batchRefObj == null || batchRefObj == DBNull.Value ? (object)DBNull.Value : Convert.ToInt64(batchRefObj),
                    amt, variance,
                    // The Balance this grid row was loaded with — the SP
                    // rejects the post if the invoice's live Balance differs
                    // (stale grid), which is what makes a partial safe.
                    ToDecimal(gridViewInvoices.GetRowCellValue(i, "Balance")));
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

            // NEW: a checked invoice with Amount to Apply left/cleared
            // to 0 would otherwise be silently dropped by
            // BuildInvoiceLinesTVP()'s `if (amt <= 0) continue;` — the
            // row still shows checked (green) with whatever stale
            // Variance was last computed, but never actually posts.
            // Catch it explicitly instead of a silent no-op, for every
            // voucher type (this isn't specific to the Check/Cash
            // overpayment guard below, which only fires for those two
            // types).
            for (int i = 0; i < gridViewInvoices.RowCount; i++)
            {
                if (!ToBool(gridViewInvoices.GetRowCellValue(i, "Pay"))) continue;

                decimal amt = ToDecimal(gridViewInvoices.GetRowCellValue(i, "AmountToApply"));
                if (amt <= 0)
                {
                    string invNo = gridViewInvoices.GetRowCellValue(i, "InvoiceNo")?.ToString();
                    XtraMessageBox.Show(
                        $"Invoice {invNo} is checked but Amount to Apply is {amt:N2}.\nUncheck it or enter a positive amount.",
                        "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
            }

            // NEW 2026-09-21: Variance may be zeroed to mark a partial
            // payment, but zero Variance with Amount to Apply ABOVE Balance
            // is an unexplained overpayment — reject it (also enforced
            // server-side, sp_PostVoucherManual THROW 58030).
            for (int i = 0; i < gridViewInvoices.RowCount; i++)
            {
                if (!ToBool(gridViewInvoices.GetRowCellValue(i, "Pay"))) continue;

                decimal amt = ToDecimal(gridViewInvoices.GetRowCellValue(i, "AmountToApply"));
                decimal balance = ToDecimal(gridViewInvoices.GetRowCellValue(i, "Balance"));
                decimal variance = ToDecimal(gridViewInvoices.GetRowCellValue(i, "Variance"));
                if (Math.Round(variance, 2) == 0 && Math.Round(amt, 2) > Math.Round(balance, 2))
                {
                    string invNo = gridViewInvoices.GetRowCellValue(i, "InvoiceNo")?.ToString();
                    XtraMessageBox.Show(
                        $"Invoice {invNo}: Amount to Apply ({amt:N2}) is above its Balance ({balance:N2}) with Variance 0.\nFor a partial payment lower Amount to Apply; for an FX difference leave Variance as computed.",
                        "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
            }

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

                // NEW: Variance only makes sense for Telegraphic (FX
                // movement on a USD-invoiced supplier) — a Check/Cash
                // voucher is always same-currency, so a nonzero
                // Variance here would post a spurious FX gain/loss.
                // Also enforced server-side (sp_PostVoucherManual THROW 58022).
                for (int i = 0; i < gridViewInvoices.RowCount; i++)
                {
                    if (!ToBool(gridViewInvoices.GetRowCellValue(i, "Pay"))) continue;

                    decimal variance = ToDecimal(gridViewInvoices.GetRowCellValue(i, "Variance"));
                    string invNo = gridViewInvoices.GetRowCellValue(i, "InvoiceNo")?.ToString();

                    if (variance != 0)
                    {
                        XtraMessageBox.Show(
                            $"Invoice {invNo}: Amount to Apply must equal Balance exactly for Check/Cash vouchers (Variance {variance:N2}).\nUse Telegraphic for a payment with an FX difference.",
                            "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        return false;
                    }
                }
            }
            var glLines = BuildGLLinesTVP();

            // NEW: invoices alone are enough now (their own auto legs
            // fully balance the ticket) — only block a truly empty
            // voucher (no invoices AND no manual GL lines).
            if (invLines.Rows.Count == 0 && glLines.Rows.Count == 0)
            {
                XtraMessageBox.Show("Nothing to post — check at least one invoice or add at least one manual GL line.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            decimal totalDebit = 0, totalCredit = 0;
            foreach (DataRow r in glLines.Rows)
            {
                totalDebit += Convert.ToDecimal(r["Debit"]);
                totalCredit += Convert.ToDecimal(r["Credit"]);
            }
            bool glNeedsResidual = glLines.Rows.Count > 0 && totalDebit != totalCredit;

            // CHANGED 2026-09-16: Credit GLCode is required whenever it
            // will actually be used — either invoices are being paid
            // (Amount-To-Apply auto leg), or the manual GL grid doesn't
            // balance on its own and needs its residual auto-posted
            // there (e.g. a lone "Advances to Supplier" Debit line, no
            // invoice attached — see SQL/2026-09-16_VoucheringManual_
            // ResidualAutoPost.sql).
            if ((invLines.Rows.Count > 0 || glNeedsResidual) && cboCreditGLCode.EditValue == null)
            {
                XtraMessageBox.Show("Select a Credit GLCode.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            // CHANGED 2026-09-16: the manual GL grid only needs to
            // balance on its own when invoices ARE being paid — Amount
            // to Apply/Variance already auto-post their own AP-Trade
            // legs against Credit GLCode there, so a second unbalanced
            // residual would double up on that account. With no
            // invoices, an unbalanced grid is fine — its residual
            // auto-posts to Credit GLCode instead.
            if (invLines.Rows.Count > 0 && glNeedsResidual)
            {
                XtraMessageBox.Show(
                    $"The manual GL entry is out of balance: Debit {totalDebit:N2} vs Credit {totalCredit:N2}.\nWhen paying invoices, it must balance on its own — Amount to Apply/Variance already auto-post their own AP-Trade legs.",
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
                    // NEW: Credit GLCode is now optional (only required/used
                    // when paying invoices — enforced in ValidateForm()).
                    cmd.Parameters.Add("@parmcreditglcode", SqlDbType.VarChar, 20).Value =
                        cboCreditGLCode.EditValue != null ? (object)cboCreditGLCode.EditValue.ToString() : DBNull.Value;

                    var invParam = cmd.Parameters.AddWithValue("@InvoiceLines", invLines);
                    invParam.SqlDbType = SqlDbType.Structured;
                    invParam.TypeName = "dbo.VoucherManualInvoiceTVP_v3";

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

                if (gridViewPosted.Columns["SupplierID"] != null) gridViewPosted.Columns["SupplierID"].Visible = false;

                // Amount is already a native MONEY value from
                // sp_GetPostedVouchersManual (not FORMAT()-ed) -- just needs
                // the grid-side numeric display + right-align, same as the
                // sibling Posted Expenses/Posted Vouchers grids elsewhere.
                if (gridViewPosted.Columns["Amount"] != null)
                {
                    gridViewPosted.Columns["Amount"].DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                    gridViewPosted.Columns["Amount"].DisplayFormat.FormatString = "N2";
                    gridViewPosted.Columns["Amount"].AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                    gridViewPosted.Columns["Amount"].AppearanceCell.Options.UseTextOptions = true;
                }

                // VoucherDate is a DateTime-typed column but PopulateColumns()
                // (invoked implicitly by binding) doesn't set a DateTime
                // DisplayFormat on its own -- without this it renders via
                // plain ToString() (e.g. "7/31/2026 12:00:00 AM"), reading
                // as a raw text field rather than a date field.
                if (gridViewPosted.Columns["VoucherDate"] != null)
                {
                    gridViewPosted.Columns["VoucherDate"].DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                    gridViewPosted.Columns["VoucherDate"].DisplayFormat.FormatString = "MM/dd/yyyy";
                }

                gridViewPosted.BestFitColumns();

                gridControlPostedDetails.DataSource = null;
                // NEW -- was previously hardcoded to false/null here, which
                // silently undid whatever FocusedRowChanged had already set
                // moments earlier when binding DataSource auto-focused row 0.
                // That auto-focus highlighted the first row but left
                // View Details/Copy to New Entry disabled until the user
                // clicked away and back. Re-sync from the actual focused row
                // instead of blindly resetting.
                SyncPostedButtonState();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load posted vouchers: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void GridViewPosted_FocusedRowChanged(object sender, DevExpress.XtraGrid.Views.Base.FocusedRowChangedEventArgs e)
        {
            SyncPostedButtonState();
        }

        private void SyncPostedButtonState()
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

                // Debit/Credit are already real DECIMAL from
                // sp_GetVoucherManualDetails's GL result set -- just needs
                // the grid-side numeric display + right-align.
                foreach (string col in new[] { "Debit", "Credit" })
                {
                    if (gridViewPostedDetails.Columns[col] == null) continue;
                    gridViewPostedDetails.Columns[col].DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                    gridViewPostedDetails.Columns[col].DisplayFormat.FormatString = "N2";
                    gridViewPostedDetails.Columns[col].AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                    gridViewPostedDetails.Columns[col].AppearanceCell.Options.UseTextOptions = true;
                }

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

                // CHANGED 2026-09-16: an invoice-driven voucher's
                // "glLines" (sp_GetVoucherManualDetails) is the
                // COMPOUNDED, already-netted TicketDetails — it can't
                // tell an auto-generated AP-Trade/Variance/Credit-
                // GLCode leg apart from a manually-typed one. Copying
                // those into a fresh Reference No. and posting as-is
                // (invoices left unchecked, the default after Copy)
                // debits AP-Trade in the GL with nothing removed from
                // APAccounts/ExpenseSummary or recorded in
                // APPaymentDetails/SupplierLedger - a phantom posting
                // the duplicate-post guard (THROW 58020) can't catch
                // since it's keyed on ReferenceNumber, which is new
                // here. A warning dialog alone didn't prevent this, so
                // block it outright. A pure no-invoice voucher (its
                // only possible auto-leg is the residual against
                // Credit GLCode) stays safe to copy - it just becomes
                // a self-balanced manual entry in the copy.
                if (result.invoices.Rows.Count > 0)
                {
                    XtraMessageBox.Show(
                        $"{_selectedPostedRefNo} paid one or more invoices — its GL entry includes auto-generated AP-Trade/Variance/Credit-GLCode legs that can't be told apart from manually-typed lines.\n\n" +
                        "Copying those into a new voucher risks a phantom AP-Trade posting (nothing removed from the invoice's Balance) or a double-post if invoices are re-checked.\n\n" +
                        "To repeat a similar payment, start a new entry, select the supplier/invoices to pay, and add any extra manual GL lines (e.g. a cash advance) fresh.",
                        "Cannot Copy — Invoice-Paid Voucher", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

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
            ClearInvoiceGrid();   // don't let previously loaded/checked rows (and their stale Balances) ride into the copy
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

            // CHANGED 2026-09-16: an invoice-driven voucher is now
            // blocked above before reaching here, so this only ever
            // copies a pure no-invoice voucher's lines — including its
            // auto residual leg against Credit GLCode (see SQL/2026-09-
            // 16_VoucheringManual_ResidualAutoPost.sql), which is safe
            // to copy as-is (it just becomes a self-balanced manual
            // entry; there's no invoice-driven auto-leg to double-post
            // here).
            XtraMessageBox.Show(
                $"Copied {glLines.Rows.Count} GL line(s) from {_selectedPostedRefNo}.\n\n" +
                "A new Reference No. was assigned. Review the amounts before posting.",
                "Copied — Review Before Posting", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
    }
}