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

            ShowVoucherDetailsPopup(referenceNo, paidTo, amount, hasInvoiceLeg, hasManualLeg, invoiceLegs, glLegs);
        }
        private void ShowVoucherDetailsPopup(string referenceNo, string paidTo, decimal amount,
            bool hasInvoiceLeg, bool hasManualLeg, DataTable invoiceLegs, DataTable glLegs)
        {
            using (var popup = new XtraForm())
            {
                popup.Text = $"Voucher Detail — {referenceNo}";
                popup.Size = new Size(820, 520);
                popup.StartPosition = FormStartPosition.CenterParent;
                popup.MinimizeBox = false;
                popup.MaximizeBox = true;

                var legDescription = (hasInvoiceLeg && hasManualLeg) ? "Invoice payment AND manual/advance entries"
                    : hasInvoiceLeg ? "Invoice payment only"
                    : hasManualLeg ? "Manual/advance entries only"
                    : "(no leg flags set)";

                var lblHeader = new LabelControl
                {
                    Dock = DockStyle.Top,
                    AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None,
                    Height = 50,
                    Padding = new Padding(10),
                    Text = $"Reference No.: {referenceNo}   |   Paid To: {paidTo}   |   Amount: {amount:N2}   |   Contains: {legDescription}"
                };

                var tabs = new DevExpress.XtraTab.XtraTabControl { Dock = DockStyle.Fill };

                if (invoiceLegs.Rows.Count > 0)
                {
                    var tabInv = new DevExpress.XtraTab.XtraTabPage { Text = "Invoice Legs" };
                    var gridInv = new DevExpress.XtraGrid.GridControl { Dock = DockStyle.Fill };
                    var viewInv = new GridView(gridInv);
                    gridInv.MainView = viewInv;
                    gridInv.ViewCollection.Add(viewInv);
                    viewInv.OptionsBehavior.Editable = false;
                    viewInv.OptionsView.ShowGroupPanel = false;
                    gridInv.DataSource = invoiceLegs;
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
                popup.Controls.Add(lblHeader);
                popup.Controls.Add(btnClose);

                if (invoiceLegs.Rows.Count > 0)
                {
                    var viewInv = ((DevExpress.XtraGrid.GridControl)((DevExpress.XtraTab.XtraTabPage)tabs.TabPages[0]).Controls[0]).MainView as GridView;
                    viewInv?.PopulateColumns();
                    viewInv?.BestFitColumns();
                }

                popup.ShowDialog(this);
            }
        }

    }
}