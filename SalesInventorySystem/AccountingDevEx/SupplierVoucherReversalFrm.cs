using System;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.AccountingDevEx
{
    /// <summary>
    /// Lists not-yet-reversed supplier vouchers (Check/Cash/Telegraphic)
    /// with badges showing whether an invoice leg, a manual/cash-advance
    /// leg, or both exist under that Reference No — then reverses the
    /// selected one via sp_ReverseCombinedSupplierVoucher, which handles
    /// whichever leg(s) actually exist together (see that SP's header
    /// comment for why this is all-or-nothing rather than per-leg).
    /// </summary>
    public partial class SupplierVoucherReversalFrm : XtraUserControl
    {
        public SupplierVoucherReversalFrm()
        {
            InitializeComponent();
        }

        private void SupplierVoucherReversalFrm_Load(object sender, EventArgs e)
        {
            //txtDateFrom.DateTime = DateTime.Today.AddMonths(-3);
            //txtDateTo.DateTime = DateTime.Today;

            HelperFunction.SetQuarterDateRange(txtDateFrom, txtDateTo);

            BindSupplierLookup();
            LoadVouchers();
        }

        private void BindSupplierLookup()
        {
            var dt = GetDataTable("SELECT SupplierID, SupplierName FROM Supplier ORDER BY SupplierName");
            cboSupplier.Properties.DataSource = dt;
            cboSupplier.Properties.DisplayMember = "SupplierName";
            cboSupplier.Properties.ValueMember = "SupplierID";
            cboSupplier.Properties.PopulateViewColumns();
        }

        private void BtnRefresh_Click(object sender, EventArgs e)
        {
            LoadVouchers();
        }

        private void LoadVouchers()
        {
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_GetReversibleSupplierVouchers", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@SupplierID", SqlDbType.VarChar, 50).Value =
                        cboSupplier.EditValue == null ? (object)DBNull.Value : cboSupplier.EditValue.ToString();
                    cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value = txtDateFrom.DateTime;
                    cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value = txtDateTo.DateTime;

                    var dt = new DataTable();
                    con.Open();
                    new SqlDataAdapter(cmd).Fill(dt);
                    gridControlVouchers.DataSource = dt;
                }

                gridViewVouchers.BestFitColumns();
                if (gridViewVouchers.Columns["SupplierID"] != null)
                    gridViewVouchers.Columns["SupplierID"].Visible = false;
                if (gridViewVouchers.Columns["PaymentMethod"] != null)
                    gridViewVouchers.Columns["PaymentMethod"].Visible = false;

                // Same captions used in the View Details popup header below,
                // so the list and the popup describe the same fields the same way.
                if (gridViewVouchers.Columns["PhysicalRef"] != null)
                    gridViewVouchers.Columns["PhysicalRef"].Caption = "Control No.";
                if (gridViewVouchers.Columns["VoucherID"] != null)
                    gridViewVouchers.Columns["VoucherID"].Caption = "Voucher ID";
                if (gridViewVouchers.Columns["VoucherDate"] != null)
                    gridViewVouchers.Columns["VoucherDate"].Caption = "Voucher Date";
                if (gridViewVouchers.Columns["PhysicalVoucherType"] != null)
                    gridViewVouchers.Columns["PhysicalVoucherType"].Caption = "Voucher Type";

                // Amount is now a real DECIMAL from sp_GetReversibleSupplierVouchers
                // (was FORMAT()-ed VARCHAR) -- numeric DisplayFormat right-aligns it
                // and lets it sort by value; footer sum needs ShowFooter turned on.
                gridViewVouchers.OptionsView.ShowFooter = true;
                Classes.DevXGridViewSettings.FormatNumericColumns(gridViewVouchers, "Amount");
                Classes.DevXGridViewSettings.ShowFooterTotal(gridViewVouchers, "Amount");

                btnReverse.Enabled = false;
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load vouchers: {ex.Message}",
                    "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void GridViewVouchers_FocusedRowChanged(object sender, DevExpress.XtraGrid.Views.Base.FocusedRowChangedEventArgs e)
        {
            btnReverse.Enabled = gridViewVouchers.FocusedRowHandle >= 0;
        }

        private void BtnReverse_Click(object sender, EventArgs e)
        {
            if (gridViewVouchers.FocusedRowHandle < 0) return;

            string supplierId = gridViewVouchers.GetFocusedRowCellValue("SupplierID")?.ToString();
            string referenceNo = gridViewVouchers.GetFocusedRowCellValue("ReferenceNumber")?.ToString();
            string voucherId = gridViewVouchers.GetFocusedRowCellValue("VoucherID")?.ToString();
            string physicalRef = gridViewVouchers.GetFocusedRowCellValue("PhysicalRef")?.ToString();
            string paidTo = gridViewVouchers.GetFocusedRowCellValue("PaidTo")?.ToString();
            decimal amount = Convert.ToDecimal(gridViewVouchers.GetFocusedRowCellValue("Amount") ?? 0m);
            bool hasInvoiceLeg = Convert.ToBoolean(gridViewVouchers.GetFocusedRowCellValue("HasInvoiceLeg") ?? false);
            bool hasManualLeg = Convert.ToBoolean(gridViewVouchers.GetFocusedRowCellValue("HasManualLeg") ?? false);
            string paymentMethod = gridViewVouchers.GetFocusedRowCellValue("PaymentMethod")?.ToString();

            // sp_CancelledChequesCS's @parmvouchertype means PURCHASE/EXPENSE
            // (the payment method) — NOT the physical CHECK/CASH/TELEGRAPHIC
            // type. Derive it from APPaymentDetails.PaymentMethod when an
            // invoice leg exists; default EXPENSE for manual-only vouchers
            // (that branch never actually uses this value).
            string parmVoucherType = hasInvoiceLeg && !string.IsNullOrEmpty(paymentMethod)
                ? paymentMethod : "EXPENSE";

            string legDescription = (hasInvoiceLeg && hasManualLeg) ? "invoice payment AND manual/advance entries"
                : hasInvoiceLeg ? "invoice payment"
                : "manual/advance entries";

            string reason = XtraInputBox.Show(
                $"Reverse voucher {referenceNo} ({paidTo}, {amount:N2})?\nThis will reverse: {legDescription}.\n\nReason for reversal:",
                "Reverse Voucher", "");

            if (string.IsNullOrWhiteSpace(reason)) return;

            if (XtraMessageBox.Show(
                    $"Confirm: reverse voucher {referenceNo} for {amount:N2}?\nThis cannot be undone from this screen.",
                    "Confirm Reversal", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes)
                return;

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_ReverseCombinedSupplierVoucher", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@parmsupplierid", SqlDbType.VarChar, 50).Value = supplierId;
                    cmd.Parameters.Add("@parmreferenceno", SqlDbType.VarChar, 10).Value = referenceNo;
                    cmd.Parameters.Add("@parmvoucherid", SqlDbType.VarChar, 10).Value = voucherId;
                    cmd.Parameters.Add("@parmvouchertype", SqlDbType.VarChar, 20).Value = parmVoucherType;
                    cmd.Parameters.Add("@parmcheckno", SqlDbType.VarChar, 50).Value = (object)physicalRef ?? DBNull.Value;
                    cmd.Parameters.Add("@parmglcode", SqlDbType.VarChar, 30).Value = DBNull.Value;
                    cmd.Parameters.Add("@parmbranch", SqlDbType.VarChar, 5).Value = DBNull.Value;
                    cmd.Parameters.Add("@parmreason", SqlDbType.VarChar, 300).Value = reason.Trim();
                    cmd.Parameters.Add("@parmuser", SqlDbType.VarChar, 50).Value = Login.Fullname;

                    con.Open();

                    string message = "Voucher reversed.";
                    using (var rdr = cmd.ExecuteReader())
                        if (rdr.Read()) message = rdr["Message"]?.ToString() ?? message;

                    XtraMessageBox.Show(message, "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }

                LoadVouchers();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Reversal failed:\n{ex.Message}", "Error",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void BtnClose_Click(object sender, EventArgs e)
        {
            //Close();
        }

        private string GetFocusedCellString(string fieldName) =>
            gridViewVouchers.Columns[fieldName] != null
                ? gridViewVouchers.GetFocusedRowCellValue(fieldName)?.ToString()
                : null;

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
       

        private void gridViewVouchers_RowCellStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowCellStyleEventArgs e)
        {
            GridView view = (GridView)sender;
            bool check = Convert.ToBoolean(view.GetRowCellValue(e.RowHandle, "isErrorCorrect"));
            if (check)
            {
                //e.Appearance.Font = new System.Drawing.Font(e.Appearance.Font, FontStyle.Strikeout);
                e.Appearance.ForeColor = Color.Red;
            }
        }

        private void gridControlVouchers_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStrip1.Show(gridControlVouchers, e.Location);
        }

        private void viewDetailsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (gridViewVouchers.FocusedRowHandle < 0) return;

            string supplierId = gridViewVouchers.GetFocusedRowCellValue("SupplierID")?.ToString();
            string referenceNo = gridViewVouchers.GetFocusedRowCellValue("ReferenceNumber")?.ToString();
            string paidTo = gridViewVouchers.GetFocusedRowCellValue("PaidTo")?.ToString();
            decimal amount = Convert.ToDecimal(gridViewVouchers.GetFocusedRowCellValue("Amount") ?? 0m);
            bool hasInvoiceLeg = Convert.ToBoolean(gridViewVouchers.GetFocusedRowCellValue("HasInvoiceLeg") ?? false);
            bool hasManualLeg = Convert.ToBoolean(gridViewVouchers.GetFocusedRowCellValue("HasManualLeg") ?? false);

            // NEW -- same identifying info SupplierPaymentDevEx.cs shows at
            // entry time (Control No., Voucher ID, Voucher Date, Voucher
            // Type), so the "View Details" popup reads as familiar/consistent
            // with the payment screen instead of just Reference/Paid To/Amount.
            // Guarded the same way LoadVouchers() guards its caption lookups --
            // sp_GetReversibleSupplierVouchers always returns these columns
            // today, but a future shape change shouldn't NullReferenceException here.
            string voucherId = GetFocusedCellString("VoucherID");
            string physicalRef = GetFocusedCellString("PhysicalRef");
            string voucherType = GetFocusedCellString("PhysicalVoucherType");
            string paymentMethod = GetFocusedCellString("PaymentMethod");
            object voucherDateVal = gridViewVouchers.Columns["VoucherDate"] != null
                ? gridViewVouchers.GetFocusedRowCellValue("VoucherDate") : null;
            string voucherDate = voucherDateVal is DateTime dt ? dt.ToString("MM/dd/yyyy") : voucherDateVal?.ToString() ?? "";

            if (string.IsNullOrEmpty(referenceNo)) return;

            DataTable invoiceLegs, glLegs;
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_GetSupplierVoucherDetails", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@SupplierID", SqlDbType.VarChar, 50).Value = supplierId;
                    cmd.Parameters.Add("@ReferenceNumber", SqlDbType.VarChar, 10).Value = referenceNo;

                    con.Open();
                    using (var da = new SqlDataAdapter(cmd))
                    {
                        var ds = new DataSet();
                        da.Fill(ds);
                        invoiceLegs = ds.Tables.Count > 0 ? ds.Tables[0] : new DataTable();
                        glLegs = ds.Tables.Count > 1 ? ds.Tables[1] : new DataTable();
                    }
                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load voucher details: {ex.Message}", "Error",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            DataSet invoiceView = hasInvoiceLeg ? LoadInvoiceView(supplierId, referenceNo) : null;

            try
            {
                ShowVoucherDetailsPopup(referenceNo, voucherId, paidTo, amount, physicalRef, voucherDate,
                    voucherType, paymentMethod, hasInvoiceLeg, hasManualLeg, invoiceLegs, glLegs, invoiceView);
            }
            finally
            {
                invoiceView?.Dispose();
            }
        }

        // NEW 2026-10-12 -- the voucher's invoices the way the payment screen
        // (splist_Accounts) showed them: one row per invoice (balance before,
        // amount paid, EWT, discount, ... balance after), each expanding into
        // its branch legs. sp_GetSupplierVoucherInvoiceView returns the two
        // result sets linked by InvKey. Returns null when the proc isn't there
        // (an older database) so the popup still opens with its other tabs.
        private DataSet LoadInvoiceView(string supplierId, string referenceNo)
        {
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_GetSupplierVoucherInvoiceView", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@SupplierID", SqlDbType.VarChar, 50).Value = supplierId;
                    cmd.Parameters.Add("@ReferenceNumber", SqlDbType.VarChar, 10).Value = referenceNo;
                    con.Open();
                    using (var da = new SqlDataAdapter(cmd))
                    {
                        var ds = new DataSet();
                        da.TableMappings.Add("Table", "Invoices");
                        da.TableMappings.Add("Table1", "Legs");
                        da.Fill(ds);
                        if (!ds.Tables.Contains("Invoices") || !ds.Tables.Contains("Legs") || ds.Tables["Invoices"].Rows.Count == 0
                            || !ds.Tables["Invoices"].Columns.Contains("InvKey") || !ds.Tables["Legs"].Columns.Contains("InvKey"))
                            return null;
                        // Code - Name, the system-wide convention for a branch
                        var legs = ds.Tables["Legs"];
                        if (legs.Columns.Contains("BranchCode") && legs.Columns.Contains("BranchName"))
                            legs.Columns.Add("Branch", typeof(string), "BranchCode + ' - ' + ISNULL(BranchName, '')");
                        ds.Relations.Add("Branch Legs", ds.Tables["Invoices"].Columns["InvKey"], legs.Columns["InvKey"], false);
                        return ds;
                    }
                }
            }
            catch (Exception ex)
            {
                // the tab is optional: the popup still opens with the other tabs
                System.Diagnostics.Debug.WriteLine("sp_GetSupplierVoucherInvoiceView: " + ex.Message);
                return null;
            }
        }

        private static void FormatMoneyColumns(GridView view, string[] fields, bool footerSum)
        {
            foreach (var f in fields)
            {
                var col = view.Columns[f];
                if (col == null) continue;
                col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                col.DisplayFormat.FormatString = "N2";
                col.AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                col.AppearanceCell.Options.UseTextOptions = true;
                if (footerSum) col.Summary.Add(DevExpress.Data.SummaryItemType.Sum, f, "{0:n2}");
            }
        }

        private static void AddColumn(GridView view, string field, string caption)
        {
            var col = view.Columns.AddVisible(field, caption);
            col.OptionsColumn.AllowEdit = false;
        }

        // The "Invoices (as paid)" tab: master = invoices, detail = branch legs.
        private static DevExpress.XtraTab.XtraTabPage BuildInvoiceViewTab(DataSet invoiceView)
        {
            var tab = new DevExpress.XtraTab.XtraTabPage { Text = "Invoices (as paid)" };
            var grid = new DevExpress.XtraGrid.GridControl { Dock = DockStyle.Fill };
            var master = new GridView(grid);
            var detail = new GridView(grid);
            grid.MainView = master;
            grid.LevelTree.Nodes.Add("Branch Legs", detail);

            foreach (var v in new[] { master, detail })
            {
                v.OptionsBehavior.Editable = false;
                v.OptionsView.ShowGroupPanel = false;
                v.OptionsView.ShowFooter = true;
                v.OptionsView.ColumnAutoWidth = false;
                Classes.DevXGridViewSettings.ApplyTotalsBandAppearance(v);
            }

            AddColumn(master, "Type", "Type");
            AddColumn(master, "InvoiceNo", "Invoice No.");
            AddColumn(master, "ReferenceNo", "Ref No.");
            AddColumn(master, "InvoiceDate", "Invoice Date");
            AddColumn(master, "Description", "Description");
            AddColumn(master, "Branches", "Branches");
            AddColumn(master, "InvoiceAmount", "Invoice Amount");
            AddColumn(master, "BalanceBefore", "Balance Before");
            AddColumn(master, "AmountPaid", "Amount Paid");
            AddColumn(master, "Variance", "Variance");
            AddColumn(master, "EWTAmount", "EWT");
            AddColumn(master, "DiscountAmount", "Discount");
            AddColumn(master, "ReturnAllowances", "Return Allowances");
            AddColumn(master, "OverPay", "OverPay (Credit)");
            AddColumn(master, "OverPayExpense", "OverPay (Expense)");
            AddColumn(master, "AdvanceApplied", "Advance Applied");
            AddColumn(master, "AmountSettled", "Amount Settled");
            AddColumn(master, "BalanceAfter", "Balance After");
            AddColumn(master, "BalanceNow", "Balance Now");
            AddColumn(master, "Status", "Status");
            master.Columns["InvoiceDate"].DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
            master.Columns["InvoiceDate"].DisplayFormat.FormatString = "MM/dd/yyyy";
            master.Columns["InvoiceNo"].Summary.Add(DevExpress.Data.SummaryItemType.Count, "InvoiceNo", "Count: {0}");
            FormatMoneyColumns(master, new[] { "InvoiceAmount", "BalanceBefore", "AmountPaid", "Variance", "EWTAmount", "DiscountAmount",
                "ReturnAllowances", "OverPay", "OverPayExpense", "AdvanceApplied", "AmountSettled", "BalanceAfter", "BalanceNow" }, true);
            // a negative balance after this voucher = paid more than was owed (e.g. the 2026-10-12 split-rounding bug); shown in red
            var boldFont = new Font(master.Appearance.Row.Font, FontStyle.Bold);
            grid.Disposed += (s, e) => boldFont.Dispose();
            master.RowCellStyle += (s, e) =>
            {
                if (e.Column.FieldName != "BalanceAfter") return;
                var v = master.GetRowCellValue(e.RowHandle, "BalanceAfter");
                if (v != null && v != DBNull.Value && Convert.ToDecimal(v) < 0)
                {
                    e.Appearance.ForeColor = Color.Firebrick;
                    e.Appearance.Font = boldFont;
                }
            };

            AddColumn(detail, "Branch", "Branch");
            AddColumn(detail, "BranchShare", "Branch Share");
            AddColumn(detail, "AmountPaid", "Amount Paid");
            AddColumn(detail, "Variance", "Variance");
            AddColumn(detail, "EWTAmount", "EWT");
            AddColumn(detail, "DiscountAmount", "Discount");
            AddColumn(detail, "ReturnAllowances", "Return Allowances");
            AddColumn(detail, "OverPay", "OverPay (Credit)");
            AddColumn(detail, "OverPayExpense", "OverPay (Expense)");
            AddColumn(detail, "AdvanceApplied", "Advance Applied");
            AddColumn(detail, "AmountSettled", "Amount Settled");
            AddColumn(detail, "TicketNumber", "Ticket No.");
            FormatMoneyColumns(detail, new[] { "BranchShare", "AmountPaid", "Variance", "EWTAmount", "DiscountAmount", "ReturnAllowances",
                "OverPay", "OverPayExpense", "AdvanceApplied", "AmountSettled" }, true);
            detail.ViewCaption = "Branch legs";

            grid.DataSource = invoiceView;
            grid.DataMember = "Invoices";
            // best-fit once the grid exists (the popup isn't shown yet here), and each detail when it opens
            grid.HandleCreated += (s, e) =>
            {
                master.BestFitColumns();
                if (master.Columns["Description"].Width > 260) master.Columns["Description"].Width = 260;
            };
            master.MasterRowExpanded += (s, e) =>
            {
                if (master.GetDetailView(e.RowHandle, e.RelationIndex) is GridView dv) dv.BestFitColumns();
            };
            tab.Controls.Add(grid);
            return tab;
        }
        private void ShowVoucherDetailsPopup(string referenceNo, string voucherId, string paidTo, decimal amount,
            string physicalRef, string voucherDate, string voucherType, string paymentMethod,
            bool hasInvoiceLeg, bool hasManualLeg, DataTable invoiceLegs, DataTable glLegs, DataSet invoiceView)
        {
            using (var popup = new XtraForm())
            {
                popup.Text = $"Voucher Detail — {referenceNo}";
                popup.Size = invoiceView != null ? new Size(1180, 640) : new Size(820, 600);
                popup.StartPosition = FormStartPosition.CenterParent;
                popup.MinimizeBox = false;
                popup.MaximizeBox = true;

                var legDescription = (hasInvoiceLeg && hasManualLeg) ? "Invoice payment AND manual/advance entries"
                    : hasInvoiceLeg ? "Invoice payment only"
                    : hasManualLeg ? "Manual/advance entries only"
                    : "(no leg flags set)";

                // NEW -- labeled field pairs instead of one inline text blob,
                // matching SupplierPaymentDevEx.cs's GroupControl/label-value
                // arrangement so this popup reads as familiar/consistent with
                // the payment entry screen it mirrors.
                var grpHeader = new GroupControl { Text = "Voucher", Dock = DockStyle.Top, Height = 155 };

                LabelControl MakeCaption(string text, int x, int y) =>
                    new LabelControl { Text = text, Location = new Point(x, y), AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None, Size = new Size(90, 16) };
                LabelControl MakeValue(string text, int x, int y) =>
                    new LabelControl
                    {
                        Text = text ?? "",
                        Location = new Point(x, y),
                        AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None,
                        Size = new Size(220, 16),
                        Appearance = { Font = new Font("Tahoma", 8.25F, FontStyle.Bold), Options = { UseFont = true } }
                    };

                grpHeader.Controls.AddRange(new Control[]
                {
                    MakeCaption("Reference No.:", 16, 30), MakeValue(referenceNo, 130, 30),
                    MakeCaption("Voucher ID:", 400, 30), MakeValue(voucherId, 500, 30),

                    MakeCaption("Paid To:", 16, 52), MakeValue(paidTo, 130, 52),
                    MakeCaption("Amount:", 400, 52), MakeValue(amount.ToString("N2"), 500, 52),

                    MakeCaption("Check No.:", 16, 74), MakeValue(physicalRef, 130, 74),
                    MakeCaption("Voucher Date:", 400, 74), MakeValue(voucherDate, 500, 74),

                    MakeCaption("Voucher Type:", 16, 96), MakeValue(voucherType, 130, 96),
                    MakeCaption("Pay Method:", 400, 96), MakeValue(paymentMethod, 500, 96),

                    MakeCaption("Contains:", 16, 118), MakeValue(legDescription, 130, 118)
                });

                var tabs = new DevExpress.XtraTab.XtraTabControl { Dock = DockStyle.Fill };

                // NEW 2026-10-12 -- first tab: the invoices as they were paid (payment-screen shape)
                if (invoiceView != null)
                    tabs.TabPages.Add(BuildInvoiceViewTab(invoiceView));

                if (invoiceLegs.Rows.Count > 0)
                {
                    var tabInv = new DevExpress.XtraTab.XtraTabPage { Text = "Invoice Legs" };
                    var gridInv = new DevExpress.XtraGrid.GridControl { Dock = DockStyle.Fill };
                    var viewInv = new GridView(gridInv);
                    gridInv.MainView = viewInv;
                    viewInv.OptionsBehavior.Editable = false;
                    viewInv.OptionsView.ShowGroupPanel = false;
                    viewInv.OptionsView.ShowFooter = true;
                    gridInv.DataSource = invoiceLegs;
                    viewInv.PopulateColumns();

                    // NEW -- captions/formatting matching SupplierPaymentDevEx.cs's
                    // INVOICES tab, so a posted voucher's leg detail reads the
                    // same way the payment screen presented it at entry time.
                    if (viewInv.Columns["InvoiceNo"] != null)
                    {
                        viewInv.Columns["InvoiceNo"].Caption = "Invoice No.";
                        // Footer count -- how many invoice legs make up this voucher.
                        viewInv.Columns["InvoiceNo"].Summary.Add(DevExpress.Data.SummaryItemType.Count, "InvoiceNo", "Count: {0}");
                    }
                    // "Branch Code", not "Branch" -- sp_GetSupplierVoucherDetails
                    // returns the raw code with no Branches join, so a friendlier
                    // caption would misleadingly imply a name is shown.
                    if (viewInv.Columns["BranchCode"] != null) viewInv.Columns["BranchCode"].Caption = "Branch Code";
                    if (viewInv.Columns["InvoiceDate"] != null)
                    {
                        // Explicit DateTime FormatType -- PopulateColumns() alone
                        // renders a DateTime-typed column via plain ToString()
                        // (e.g. "7/31/2026 12:00:00 AM"), not a clean date.
                        viewInv.Columns["InvoiceDate"].Caption = "Invoice Date";
                        viewInv.Columns["InvoiceDate"].DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                        viewInv.Columns["InvoiceDate"].DisplayFormat.FormatString = "MM/dd/yyyy";
                    }
                    if (viewInv.Columns["PaymentType"] != null) viewInv.Columns["PaymentType"].Caption = "Type";
                    if (viewInv.Columns["TicketNumber"] != null) viewInv.Columns["TicketNumber"].Caption = "Ticket No.";
                    if (viewInv.Columns["PaymentMethod"] != null) viewInv.Columns["PaymentMethod"].Visible = false; // already shown in the header above

                    if (viewInv.Columns["Amount"] != null)
                    {
                        // Captioned "Amount Paid" rather than "Invoice Amount" --
                        // APPaymentDetails only ever stores what was actually paid
                        // on this leg (net cash for PURCHASE, gross for EXPENSE),
                        // never the invoice's original balance; renaming it to
                        // "Invoice Amount" would misrepresent what this number is.
                        viewInv.Columns["Amount"].Caption = "Amount Paid";
                        viewInv.Columns["Amount"].DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                        viewInv.Columns["Amount"].DisplayFormat.FormatString = "N2";
                        viewInv.Columns["Amount"].AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                        viewInv.Columns["Amount"].AppearanceCell.Options.UseTextOptions = true;
                        viewInv.Columns["Amount"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "Amount", "{0:n2}");
                    }

                    viewInv.BestFitColumns();
                    tabInv.Controls.Add(gridInv);
                    tabs.TabPages.Add(tabInv);
                }

                var tabGL = new DevExpress.XtraTab.XtraTabPage { Text = "Full GL Detail" };
                var gridGL = new DevExpress.XtraGrid.GridControl { Dock = DockStyle.Fill };
                var viewGL = new GridView(gridGL);
                gridGL.MainView = viewGL;
                gridGL.ViewCollection.Add(viewGL);
                viewGL.OptionsBehavior.Editable = false;
                viewGL.OptionsView.ShowGroupPanel = false;
                viewGL.OptionsView.ShowFooter = true;
                gridGL.DataSource = glLegs;
                viewGL.PopulateColumns();
                if (viewGL.Columns["Debit"] != null)
                    viewGL.Columns["Debit"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "Debit", "{0:n2}");
                if (viewGL.Columns["Credit"] != null)
                    viewGL.Columns["Credit"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "Credit", "{0:n2}");
                viewGL.BestFitColumns();
                tabGL.Controls.Add(gridGL);
                tabs.TabPages.Add(tabGL);

                var btnClose = new SimpleButton { Text = "Close", Dock = DockStyle.Bottom, Height = 36 };
                btnClose.Click += (s, e) => popup.Close();

                popup.Controls.Add(tabs);
                popup.Controls.Add(grpHeader);
                popup.Controls.Add(btnClose);

                popup.ShowDialog(this);
            }
        }

    }
}