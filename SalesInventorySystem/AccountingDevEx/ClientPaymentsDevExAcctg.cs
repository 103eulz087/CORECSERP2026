using System;
using System.Collections.Generic;
using System.Data;
using System.Drawing;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using System.Data.SqlClient;
using DevExpress.XtraGrid.Views.Grid;
using DevExpress.XtraGrid.Columns;
using SalesInventorySystem.Classes;
using DevExpress.XtraEditors.Repository;
using SalesInventorySystem.HOFormsDevEx;

namespace SalesInventorySystem.AccountingDevEx
{
    public partial class ClientPaymentsDevExAcctg : UserControl
    {
        object objcustid, objcustname;
        bool isglobalSales = false, isglobalCharge = false;
        string paymenttype = "", custkey = "", refno;
        int lasttransseqno;
        RepositoryItemCheckEdit chkPay;

        public ClientPaymentsDevExAcctg()
        {
            InitializeComponent();

            chkPay = new RepositoryItemCheckEdit();
            chkPay.ValueChecked = true;
            chkPay.ValueUnchecked = false;
            chkPay.AllowGrayed = false;

            gridControl2.RepositoryItems.Add(chkPay);
        }

        // ── LOAD ────────────────────────────────────────────────────────
        private void ClientPaymentsDevExAcctg_Load(object sender, EventArgs e)
        {
            custkey = txtcustid.Text;
            groupControl1.Text = custkey;
            populateCustname();
            populateRepositorySearchLookUp();
            populateCOA();
            display();

            Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "InvoiceAmount");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "Balance");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "AmountPaid");
            //Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "AdvancePayment");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "OverPay");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "EWTAmount");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "DiscountAmount");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "OffsetAmount");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "ServicesAmount");

            gridView2.OptionsBehavior.EditorShowMode = DevExpress.Utils.EditorShowMode.MouseDown;
            gridView2.OptionsBehavior.ImmediateUpdateRowPosition = true;
            gridView2.Columns["Pay"].ColumnEdit = chkPay;
            gridView2.Columns["Pay"].OptionsColumn.AllowEdit = true;
            gridView2.Columns["Pay"].OptionsColumn.ReadOnly = false;
            gridView2.CloseEditor();
            gridView2.UpdateCurrentRow();

            gridView9.RowCellStyle += gridView9_RowCellStyle;
            xtraTabControl1.SelectedPageChanged += XtraTabControl1_SelectedPageChanged;
            gridView9.FocusedRowChanged += GridView9_FocusedRowChanged;
        }

        // Clears the details grid on focus change rather than auto-loading it -
        // View Details stays an explicit action (per how this was asked for),
        // but leaving a previous row's GL entries on screen while a different
        // row is focused would misleadingly look like they belong to it.
        private void GridView9_FocusedRowChanged(object sender, DevExpress.XtraGrid.Views.Base.FocusedRowChangedEventArgs e)
        {
            gridControlPaymentDetails.DataSource = null;
        }

        // Lazy-load, same as AddExpenseDevExFrm's Posted Expenses tab -
        // only queries when the user actually switches to FullyPaid Invoice.
        private void XtraTabControl1_SelectedPageChanged(object sender, DevExpress.XtraTab.TabPageChangedEventArgs e)
        {
            if (xtraTabControl1.SelectedTabPage == xtraTabPage2)
                LoadPostedClientPayments();
        }


        void populateCustname()
        {
            Database.displaySearchlookupEdit("SELECT CustomerKey,CustomerName FROM view_Customers", txtcustname, "CustomerName", "CustomerName");
        }
        // ── DISPLAY ─────────────────────────────────────────────────────
        void display()
        {
            using (SqlConnection con = Database.getConnection())
            using (SqlCommand com = new SqlCommand("splist_ARAccounts", con))
            {
                com.CommandType = CommandType.StoredProcedure;
                com.Parameters.Add("@parmcustkey", SqlDbType.VarChar).Value = txtcustid.Text;

                DataTable table = new DataTable();
                con.Open();
                using (SqlDataReader dr = com.ExecuteReader())
                    table.Load(dr);

                // Unlock editable columns (SP returns them as read-only by default)
                //string[] editableColumns = { "Pay", "AmountPaid", "EWTAmount", "DiscountAmount", "OffsetAmount", "AdvancePayment" };
                string[] editableColumns = { "Pay", "AmountPaid", "EWTAmount", "DiscountAmount", "OffsetAmount", "OverPay", "ServicesAmount" };
                foreach (string col in editableColumns)
                    if (table.Columns.Contains(col))
                        table.Columns[col].ReadOnly = false;

                gridControl2.DataSource = null;
                gridControl2.DataSource = table;
            }

            gridView2.OptionsBehavior.Editable = true;
            gridView2.OptionsBehavior.ReadOnly = false;
            gridView2.OptionsBehavior.EditorShowMode = DevExpress.Utils.EditorShowMode.Click;

            foreach (GridColumn col in gridView2.Columns)
            {
                col.OptionsColumn.AllowEdit = true;
                col.OptionsColumn.ReadOnly = false;
            }

            gridView2.Columns["Pay"].ColumnEdit = chkPay;
            gridView2.BestFitColumns();
        }

        // ── PAYMENT TYPE PANEL VISIBILITY ────────────────────────────────
        // [CLEAN] Single method drives all radio states — no duplication.
        void ApplyPaymentTypeVisibility()
        {
            groupCheque.Visible = radioButton2.Checked;
            panelOnline.Visible = radioButton3.Checked; 
            groupCreditCardDetails.Visible = radCreditCard.Checked;

            //if (radioButton4.Checked)
            //    txtacctbalance.Text = Math.Round(
            //        Convert.ToDouble(Database.getSingleQuery(
            //            "ClientSavingsAccounts", "AccountKey='" + txtcustid.Text + "'", "AccountBalance")), 2
            //    ).ToString();
        }

        private void radioButton1_CheckedChanged(object sender, EventArgs e) => ApplyPaymentTypeVisibility();
        private void radioButton2_CheckedChanged(object sender, EventArgs e) => ApplyPaymentTypeVisibility();
        private void radioButton3_CheckedChanged(object sender, EventArgs e) => ApplyPaymentTypeVisibility();
        private void radioButton4_CheckedChanged(object sender, EventArgs e) => ApplyPaymentTypeVisibility();
        private void radCreditCard_CheckedChanged(object sender, EventArgs e) => ApplyPaymentTypeVisibility();

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            switch (keyData)
            {
                case Keys.F1: radioButton1.Checked = true; break;
                case Keys.F2: radioButton2.Checked = true; break;
                case Keys.F3: radioButton3.Checked = true; break;
              
                case Keys.F5: radCreditCard.Checked = true; break;
                default: return base.ProcessCmdKey(ref msg, keyData);
            }
            return true;
        }

        // ── COA LOOKUPS ─────────────────────────────────────────────────
        void populateCOA()
        {
            const string sql = "SELECT AccountCode, Description FROM ChartOfAccounts WHERE AccountType='D'";
            Database.displaySearchlookupEdit(sql, txtdebitglcode, "AccountCode", "AccountCode");
            Database.displaySearchlookupEdit(sql, txtcreditglcode, "AccountCode", "AccountCode");
        }

        void populateRepositorySearchLookUp()
        {
            const string sql = "Select AccountCode, Description FROM ChartOfAccounts WHERE AccountType='D'";
            Database.displayRepositorySearchlookupEdit(sql, repositoryItemSearchLookUpEditglcode, "AccountCode", "AccountCode");
            Database.displayRepositorySearchlookupEdit(sql, repositoryItemSearchLookUpEditOffsetGLCode, "AccountCode", "AccountCode");
            Database.displayRepositorySearchlookupEdit(sql, repositoryItemSearchLookUpEditOffsetCreditGLCode, "AccountCode", "AccountCode");
            Database.displayRepositorySearchlookupEdit(sql, repositoryItemSearchLookUpEditEWTDebitGLCode, "AccountCode", "AccountCode");
            Database.displayRepositorySearchlookupEdit(sql, repositoryItemSearchLookUpEditEWTCreditGLCode, "AccountCode", "AccountCode");
        }

        // ── GRID EVENTS ─────────────────────────────────────────────────
        private void gridView2_CellValueChanging(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            if (e.Column.FieldName == "Pay")
                gridView2.PostEditor();
        }

        private void gridView2_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            int row = e.RowHandle;
            if (row < 0) return;

            if (e.Column.FieldName == "Pay")
            {
                bool isPay = Convert.ToBoolean(e.Value);
                if (isPay)
                {
                    double balance = Convert.ToDouble(gridView2.GetRowCellValue(row, "Balance") ?? 0);
                    // Default: full balance, no deductions
                    gridView2.SetRowCellValue(row, "EWTAmount", 0);
                    gridView2.SetRowCellValue(row, "DiscountAmount", 0);
                    gridView2.SetRowCellValue(row, "OffsetAmount", 0);
                    gridView2.SetRowCellValue(row, "OverPay", 0);
                    gridView2.SetRowCellValue(row, "ServicesAmount", 0);
                    gridView2.SetRowCellValue(row, "AmountPaid", balance);
                }
                else
                {
                    gridView2.SetRowCellValue(row, "EWTAmount", 0);
                    gridView2.SetRowCellValue(row, "DiscountAmount", 0);
                    gridView2.SetRowCellValue(row, "OffsetAmount", 0);
                    gridView2.SetRowCellValue(row, "OverPay", 0);
                    gridView2.SetRowCellValue(row, "ServicesAmount", 0);
                    gridView2.SetRowCellValue(row, "AmountPaid", 0);
                }
                ComputeTotal();
                return;
            }

            if (e.Column.FieldName == "EWTAmount" ||
                e.Column.FieldName == "DiscountAmount" ||
                e.Column.FieldName == "OverPay" ||
                e.Column.FieldName == "OffsetAmount" ||
                e.Column.FieldName == "ServicesAmount")
            {
                RecalculateRow(row);
            }

            if (e.Column.FieldName == "EWTAmount" ||
                e.Column.FieldName == "DiscountAmount" ||
                e.Column.FieldName == "OffsetAmount" ||
                e.Column.FieldName == "OverPay" ||
                e.Column.FieldName == "ServicesAmount" ||
                e.Column.FieldName == "AmountPaid")
            {
                ComputeTotal();
                gridView2.UpdateCurrentRow();
            }
        }

        // RecalculateRow: AmountPaid (net cash) = balance - all deductions
        // This is display-only. Gross is reconstructed at save time.
        private void RecalculateRow(int row)
        {
            bool isPay = Convert.ToBoolean(gridView2.GetRowCellValue(row, "Pay"));
            if (!isPay) return;

            double balance = Convert.ToDouble(gridView2.GetRowCellValue(row, "Balance") ?? 0);
            double ewt = Convert.ToDouble(gridView2.GetRowCellValue(row, "EWTAmount") ?? 0);
            double discount = Convert.ToDouble(gridView2.GetRowCellValue(row, "DiscountAmount") ?? 0);
            double offset = Convert.ToDouble(gridView2.GetRowCellValue(row, "OffsetAmount") ?? 0);
            double overpay = Convert.ToDouble(gridView2.GetRowCellValue(row, "OverPay") ?? 0);
            double servicesAmount = Convert.ToDouble(gridView2.GetRowCellValue(row, "ServicesAmount") ?? 0);

            // ServicesAmount (e.g. cutting fee) is ADDITIVE -- an extra charge
            // billed to the client on top of the invoice balance, unlike
            // EWT/Discount/Offset which are deducted from it.
            double netPayment = (balance - ewt - discount - offset) + overpay + servicesAmount;
            if (netPayment < 0) netPayment = 0;

            double current = Convert.ToDouble(gridView2.GetRowCellValue(row, "AmountPaid") ?? 0);
            if (current == netPayment) return;

            // Write directly to the bound DataRow instead of SetRowCellValue.
            // SetRowCellValue from inside another column's own CellValueChanged
            // handler is unreliable in this DevExpress version - the row can
            // still be mid-commit for the column that triggered this call, so
            // the sibling cell update doesn't always stick. Setting the DataRow
            // directly goes through the DataTable's own change notification,
            // which the bound grid always picks up correctly.
            DataRow dr = gridView2.GetDataRow(row);
            if (dr != null)
                dr["AmountPaid"] = netPayment;
            else
                gridView2.SetRowCellValue(row, "AmountPaid", netPayment);
        }

        // ComputeTotal: txtamounttopay shows total NET cash across selected rows
        private void ComputeTotal()
        {
            double total = 0;
            for (int i = 0; i < gridView2.RowCount; i++)
            {
                if (Convert.ToBoolean(gridView2.GetRowCellValue(i, "Pay")))
                    total += Convert.ToDouble(gridView2.GetRowCellValue(i, "AmountPaid") ?? 0);
            }
            txtamounttopay.Text = total.ToString("N2");
        }

        // ── GRID VALIDATION ─────────────────────────────────────────────
        private void gridView2_ValidatingEditor(object sender, DevExpress.XtraEditors.Controls.BaseContainerValidateEditorEventArgs e)
        {
            var view = sender as GridView;
            int row = view.FocusedRowHandle;
            string field = view.FocusedColumn.FieldName;

            if (field != "AmountPaid" && field != "EWTAmount" &&
                field != "DiscountAmount" && field != "OffsetAmount" &&
                field != "ServicesAmount")
                return;

            if (!double.TryParse(e.Value?.ToString(), out double value))
            {
                e.Valid = false;
                e.ErrorText = "Invalid number format.";
                return;
            }
            if (value < 0)
            {
                e.Valid = false;
                e.ErrorText = "Negative values are not allowed.";
                return;
            }

            bool isPay = Convert.ToBoolean(view.GetRowCellValue(row, "Pay"));
            if (!isPay)
            {
                e.Valid = false;
                e.ErrorText = "Please check the 'Pay' box first.";
                return;
            }

            double balance = Convert.ToDouble(view.GetRowCellValue(row, "Balance") ?? 0);
            double ewt = Convert.ToDouble(view.GetRowCellValue(row, "EWTAmount") ?? 0);
            double discount = Convert.ToDouble(view.GetRowCellValue(row, "DiscountAmount") ?? 0);
            double offset = Convert.ToDouble(view.GetRowCellValue(row, "OffsetAmount") ?? 0);
            double overpay = Convert.ToDouble(view.GetRowCellValue(row, "OverPay") ?? 0);
            double amtPaid = Convert.ToDouble(view.GetRowCellValue(row, "AmountPaid") ?? 0);

            // Apply the pending value to test
            if (field == "EWTAmount") ewt = value;
            if (field == "DiscountAmount") discount = value;
            if (field == "OffsetAmount") offset = value;
            if (field == "AmountPaid") amtPaid = value;

            //if ((ewt + discount + offset) > balance)
            //{
            //    e.Valid = false;
            //    e.ErrorText = "Total deductions (EWT + Discount + Offset) cannot exceed the Balance.";
            //    return;
            //}
            //// OverPay legitimately lets AmountPaid exceed Balance - allow that room.
            //if (amtPaid > balance + overpay)
            //{
            //    e.Valid = false;
            //    e.ErrorText = "Amount Paid cannot exceed the Balance plus Overpay.";
            //    return;
            //}

            e.Valid = true;
        }

        // ── ROW COLOR CODING ────────────────────────────────────────────
        private void gridView2_RowCellStyle(object sender, RowCellStyleEventArgs e)
        {
            GridView view = sender as GridView;
            if (e.RowHandle < 0) return;

            object val = view.GetRowCellValue(e.RowHandle, "Pay");
            bool isPay = val != null && val != DBNull.Value && bool.TryParse(val.ToString(), out bool b) && b;

            if (!isPay)
            {
                e.Appearance.BackColor = Color.LightGray;
                return;
            }

            double balance = Convert.ToDouble(view.GetRowCellValue(e.RowHandle, "Balance") ?? 0);
            double ewt = Convert.ToDouble(view.GetRowCellValue(e.RowHandle, "EWTAmount") ?? 0);
            double discount = Convert.ToDouble(view.GetRowCellValue(e.RowHandle, "DiscountAmount") ?? 0);
            double offset = Convert.ToDouble(view.GetRowCellValue(e.RowHandle, "OffsetAmount") ?? 0);
            double overpay = Convert.ToDouble(view.GetRowCellValue(e.RowHandle, "OverPay") ?? 0);
            double servicesAmount = Convert.ToDouble(view.GetRowCellValue(e.RowHandle, "ServicesAmount") ?? 0);
            double amtPaid = Convert.ToDouble(view.GetRowCellValue(e.RowHandle, "AmountPaid") ?? 0);

            double expectedNet = balance - ewt - discount - offset + overpay + servicesAmount;

            if ((ewt + discount + offset) > balance || amtPaid < 0)
            {
                e.Appearance.BackColor = Color.LightCoral;
                e.Appearance.ForeColor = Color.White;
                return;
            }
            if (Math.Abs(amtPaid - expectedNet) > 0.01)
            {
                e.Appearance.BackColor = Color.Khaki;
                e.Appearance.ForeColor = Color.Black;
                return;
            }

            e.Appearance.BackColor = Color.LightGreen;
            e.Appearance.ForeColor = Color.Black;
        }

        // ── GRID CUSTOM EDITORS ─────────────────────────────────────────
        private void gridView2_CustomRowCellEdit(object sender, CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "DiscountGLCode")
                e.RepositoryItem = repositoryItemSearchLookUpEditglcode;
            if (e.Column.FieldName == "OffsetGLCode")
                e.RepositoryItem = repositoryItemSearchLookUpEditOffsetGLCode;
            if (e.Column.FieldName == "OffsetCreditGLCode")
                e.RepositoryItem = repositoryItemSearchLookUpEditOffsetCreditGLCode;
            if (e.Column.FieldName == "EWTDebitGLCode")
                e.RepositoryItem = repositoryItemSearchLookUpEditEWTDebitGLCode;
            if (e.Column.FieldName == "EWTCreditGLCode")
                e.RepositoryItem = repositoryItemSearchLookUpEditEWTCreditGLCode;
        }

        // ── GL CODE DESCRIPTION DISPLAY ──────────────────────────────────
        private void txtcreditglcode_EditValueChanged(object sender, EventArgs e)
        {
            GridView view = txtdebitglcode.Properties.View;
            object value = view.GetRowCellValue(view.FocusedRowHandle, "Description");
            txtdebitdesc.Text = value?.ToString() ?? "";
        }

        private void searchLookUpEditcreditglcode_EditValueChanged(object sender, EventArgs e)
        {
            GridView view = txtcreditglcode.Properties.View;
            object value = view.GetRowCellValue(view.FocusedRowHandle, "Description");
            txtcreditdesc.Text = value?.ToString() ?? "";
        }

        // ── CONTEXT MENU ─────────────────────────────────────────────────
        private void gridControl2_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStrip1.Show(gridControl2, e.Location);
        }

        private void editPaymentToolStripMenuItem_Click(object sender, EventArgs e)
        {
            HOFormsDevEx.ClientEditPayment clientedit = new ClientEditPayment();
            int focused = gridView2.FocusedRowHandle;

            clientedit.txtdelivdate.Text = gridView2.GetRowCellValue(focused, "TransactionDate").ToString();
            clientedit.txtinvoiceno.Text = gridView2.GetRowCellValue(focused, "InvoiceNo").ToString();
            clientedit.txtinvoiceamount.Text = gridView2.GetRowCellValue(focused, "InvoiceAmount").ToString();
            clientedit.txtewtamount.Text = gridView2.GetRowCellValue(focused, "EWTAmount").ToString();
            clientedit.txtduedate.Text = gridView2.GetRowCellValue(focused, "DueDate").ToString();
            clientedit.txtterms.Text = Database.getSingleQuery("Customers", "CustomerID='" + txtcustid.Text + "'", "Term");
            clientedit.ShowDialog(this);

            if (ClientEditPayment.isdone)
            {
                if (ClientEditPayment.isdiscount)
                {
                    gridView2.SetRowCellValue(focused, "DiscountAmount", ClientEditPayment.discamount);
                    gridView2.SetRowCellValue(focused, "DiscountGLCode", ClientEditPayment.discdebit);
                }
                if (ClientEditPayment.isoffset)
                {
                    gridView2.SetRowCellValue(focused, "OffsetAmount", ClientEditPayment.offsetamount);
                    gridView2.SetRowCellValue(focused, "OffsetGLCode", ClientEditPayment.offsetdebit);
                    gridView2.SetRowCellValue(focused, "OffsetCreditGLCode", ClientEditPayment.offsetcredit);
                }
                if (ClientEditPayment.isewt)
                {
                    gridView2.SetRowCellValue(focused, "EWTAmount", ClientEditPayment.ewtamount);
                    gridView2.SetRowCellValue(focused, "EWTDebitGLCode", ClientEditPayment.ewtdebit);
                    gridView2.SetRowCellValue(focused, "EWTCreditGLCode", ClientEditPayment.ewtcredit);
                }
                ClientEditPayment.isdone = false;
                clientedit.Dispose();
            }
        }

        private void clearFieldsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            int row = gridView2.FocusedRowHandle;
            gridView2.SetRowCellValue(row, "DiscountAmount", "0");
            gridView2.SetRowCellValue(row, "DiscountGLCode", "");
            gridView2.SetRowCellValue(row, "OffsetAmount", "0");
            gridView2.SetRowCellValue(row, "OffsetGLCode", "");
            gridView2.SetRowCellValue(row, "OffsetCreditGLCode", "");
            gridView2.SetRowCellValue(row, "EWTAmount", "0");
            gridView2.SetRowCellValue(row, "EWTDebitGLCode", "");
            gridView2.SetRowCellValue(row, "EWTCreditGLCode", "");
            RecalculateRow(row);
        }

        // ── CONFIRM PAYMENT ──────────────────────────────────────────────
        void confirmPayment()
        {
            if (!HelperFunction.ConfirmDialog("Are you sure?", "Confirm Payment"))
                return;

            if (!radioButton1.Checked && !radioButton2.Checked &&
                !radioButton3.Checked && !radCreditCard.Checked)
            {
                XtraMessageBox.Show("Please select a Payment Type.");
                return;
            }

            int ctr = 0;
            int advpymntctr = 0;
            double totalBalance = 0;
            double totalAmtPaid = 0;
            double totalOverpay = 0;
            double totalServicesAmount = 0;
            double totalDeductions = 0; // EWT + Discount + Offset + OverPay, across checked rows
            double advncepymentval = 0;
            bool isSales = false;
            bool isCharge = false;

            for (int i = 0; i < gridView2.RowCount; i++)
            {
                bool isPay = gridView2.GetRowCellValue(i, "Pay").ToString() == "True";
                if (!isPay) continue;

                ctr++;
                totalBalance += Convert.ToDouble(gridView2.GetRowCellValue(i, "Balance") ?? 0);
                totalAmtPaid += Convert.ToDouble(gridView2.GetRowCellValue(i, "AmountPaid") ?? 0);
                totalOverpay += Convert.ToDouble(gridView2.GetRowCellValue(i, "OverPay") ?? 0);
                totalServicesAmount += Convert.ToDouble(gridView2.GetRowCellValue(i, "ServicesAmount") ?? 0);
                advncepymentval += Convert.ToDouble(gridView2.GetRowCellValue(i, "AmountPaid") ?? 0);
                totalDeductions +=
                    Convert.ToDouble(gridView2.GetRowCellValue(i, "EWTAmount") ?? 0) +
                    Convert.ToDouble(gridView2.GetRowCellValue(i, "DiscountAmount") ?? 0) +
                    Convert.ToDouble(gridView2.GetRowCellValue(i, "OffsetAmount") ?? 0) +
                    Convert.ToDouble(gridView2.GetRowCellValue(i, "OverPay") ?? 0);

                string invType = gridView2.GetRowCellValue(i, "InvoiceType")?.ToString();
                if (invType == "SALES") isSales = true;
                if (invType == "CHARGE") isCharge = true;

                //if (Convert.ToDouble(gridView2.GetRowCellValue(i, "AdvancePayment") ?? 0) > 0)
                if (Convert.ToDouble(gridView2.GetRowCellValue(i, "OverPay") ?? 0) > 0)
                    advpymntctr++;
            }

            if (ctr == 0)
            {
                XtraMessageBox.Show("No invoices selected. Please check the 'Pay' checkbox.");
                return;
            }

            // Round to cents before comparing - totalAmtPaid is a double sum of
            // grid cells, sp_AddPaymentClient re-derives its own net cash in
            // decimal(18,2) from what actually gets written to
            // ARPaymentDetails. Comparing raw doubles risked the UI deciding
            // "net cash" on one side of zero while the SP's decimal math lands
            // on the other, which would surface as a confusing 92004 THROW
            // instead of the intended zero-cash confirm prompt.
            double roundedNetCash = Math.Round(totalAmtPaid, 2);
            bool hasNetCash = roundedNetCash > 0;

            // A checked row with nothing entered anywhere (AmountPaid, EWT,
            // Discount, Offset, OverPay all 0) reconstructs to gross=0 in
            // InsertARPaymentDetails() and is silently skipped from the
            // INVOICE PAYMENT insert entirely - i.e. it looks selected but
            // nothing would actually post for it. Block this outright rather
            // than let it fall into the zero-net-cash confirm path, which is
            // meant for genuine EWT/Discount/Offset-only corrections, not an
            // empty selection.
            if (!hasNetCash && Math.Round(totalDeductions, 2) == 0)
            {
                XtraMessageBox.Show(
                    "No amount, EWT, Discount, or Offset was entered for the selected invoice(s) - " +
                    "nothing would be posted. Enter an amount or uncheck 'Pay'.",
                    "Nothing To Post", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // Debit GL Code / Control No / CR No are only mandatory when this
            // submission actually moves cash. An EWT-only (or discount/offset-
            // only) correction - e.g. recording a 2307-backed EWT weeks after
            // the cash portion of an invoice was already paid separately -
            // nets to exactly 0 here, has no bank leg to post and no receipt
            // to reference. sp_AddPaymentClient enforces the same rule
            // server-side (THROW 92004) as a backstop.
            if (hasNetCash &&
                (string.IsNullOrEmpty(txtdebitglcode.Text) ||
                 string.IsNullOrEmpty(txtcontrolno.Text) ||
                 string.IsNullOrEmpty(txtcrno.Text)))
            {
                XtraMessageBox.Show("Please fill up mandatory fields.");
                return;
            }
            if (!hasNetCash &&
                !HelperFunction.ConfirmDialog(
                    "This payment has no net cash amount (EWT/Discount/Offset only) - " +
                    "Debit GL Code will not be posted. Continue?",
                    "Zero Net Cash"))
                return;

            if (advpymntctr > 1)
            {
                XtraMessageBox.Show("OverPay must be assigned to only one invoice.");
                return;
            }
            if (isSales && isCharge)
            {
                XtraMessageBox.Show("Cannot mix CHARGE and SALES invoice payments. Process one type at a time.");
                return;
            }
            //if (radioButton4.Checked && advncepymentval > Convert.ToDouble(txtacctbalance.Text))
            //{
            //    XtraMessageBox.Show("Total Amount Paid exceeds available savings balance.");
            //    return;
            //}
            // OverPay is deliberate excess cash, and ServicesAmount is an
            // additive charge billed on top of the invoice (e.g. a cutting
            // fee) - AmountPaid is expected to exceed Balance by exactly
            // their combined total, so both must be added to the allowed
            // ceiling here instead of being treated as an error.
            if (totalAmtPaid > totalBalance + totalOverpay + totalServicesAmount)
            {
                XtraMessageBox.Show("Total Amount Paid cannot exceed Total Balance plus Overpay plus Services Amount.");
                return;
            }

            isglobalCharge = isCharge;
            isglobalSales = isSales;
            ProcessPayment();
        }

        private void simpleButton4_Click(object sender, EventArgs e) => confirmPayment();

        // ── PAYMENT PROCESSING ───────────────────────────────────────────
        void ProcessPayment()
        {
            using (SqlConnection con = Database.getConnection())
            {
                con.Open();
                using (SqlTransaction tran = con.BeginTransaction())
                {
                    try
                    {
                        int paymentHeaderId = InsertPaymentHeader(con, tran);
                        InsertPaymentMethod(con, tran, paymentHeaderId);
                        InsertARPaymentDetails(con, tran, paymentHeaderId);
                        ExecutePostingSP(con, tran, paymentHeaderId);

                        tran.Commit();
                        BigAlert.Show("SUCCESS", "Payment Successfully Posted!", MessageBoxIcon.Information);
                        // Was this.Dispose() - fine for a one-shot ShowDialog() usage, but this
                        // control is now a persistent Accounting Board accordion page (see
                        // AccountingBoard.cs's PagePostClientPayment), reused across many
                        // payments/customers in one session. Disposing it here killed the whole
                        // "Post Client Payment" module after the very first successful post
                        // (Known Bug Pattern #6 - Reset Entry not called after save).
                        ResetEntry();
                    }
                    catch (Exception ex)
                    {
                        // sp_AddPaymentClient (called via ExecutePostingSP above, on this
                        // same tran) does its own BEGIN TRAN/ROLLBACK internally. SQL
                        // Server's ROLLBACK always unwinds to the OUTERMOST transaction
                        // regardless of nesting - confirmed live: after the SP's internal
                        // ROLLBACK fires, @@TRANCOUNT on this connection is already 0. That
                        // means tran.Rollback() here is rolling back a server-side
                        // transaction that's already gone, and SqlTransaction throws
                        // InvalidOperationException ("This SqlTransaction has completed")
                        // when that happens - which would otherwise skip the BigAlert below
                        // entirely and swallow the real error message (including every THROW
                        // in sp_AddPaymentClient, not just the new zero-cash guardrail one).
                        try { tran.Rollback(); } catch { /* already rolled back server-side by the SP */ }
                        BigAlert.Show("Error", ex.Message, MessageBoxIcon.Error);
                    }
                }
            }
        }

        // ── RESET ENTRY ────────────────────────────────────────────────────
        // Clears the payment entry fields back to a blank state after a
        // successful post, same intent as AddExpenseDevExFrm's StartNewEntry():
        // mint-ready for the next payment instead of disposing the control.
        // Customer selection (txtcustname/txtcustid/custkey) is deliberately
        // left as-is - re-fetching the customer's now-updated balances via
        // display() below is more useful than forcing a re-pick, since
        // recording another payment for the same customer right after is the
        // common case this screen is used for.
        void ResetEntry()
        {
            radioButton1.Checked = false;
            radioButton2.Checked = false;
            radioButton3.Checked = false;
            
            radCreditCard.Checked = false;
            ApplyPaymentTypeVisibility();

            txtcontrolno.Text = "";
            txtcrno.Text = "";
            txtremakrs.Text = "";
            txtdate.EditValue = DateTime.Today;
            txtdebitglcode.Text = "";
            txtcreditglcode.Text = "";
            txtdebitdesc.Text = "";
            txtcreditdesc.Text = "";
            txtamounttopay.Text = "0.00";

            txtchecknum.Text = "";
            txtcheckname.Text = "";
            txtcheckbankname.Text = "";
            txtcheckamount.Text = "";
            txtcheckdate.EditValue = null;

            txtrefnoonline.Text = "";
            txtdepbankonline.Text = "";
            txtdatedeponline.EditValue = null;

            display();
            LoadPostedClientPayments();
        }

        int InsertPaymentHeader(SqlConnection con, SqlTransaction tran)
        {
            refno = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");

            using (SqlCommand cmd = new SqlCommand(@"
                INSERT INTO PaymentHeader
                    (CustomerKey, ReferenceNo, ControlNo, CRNo, PaymentType,
                     TotalAmount, PaymentDate, Remarks, CreatedBy)
                OUTPUT INSERTED.PaymentHeaderID
                VALUES
                    (@custkey, @refno, @control, @crno, @type,
                     @amount, @date, @remarks, @user)", con, tran))
            {
                cmd.Parameters.Add("@custkey", SqlDbType.Char, 8).Value = custkey;
                cmd.Parameters.Add("@refno", SqlDbType.VarChar, 20).Value = refno;
                cmd.Parameters.Add("@control", SqlDbType.VarChar, 30).Value = txtcontrolno.Text;
                cmd.Parameters.Add("@crno", SqlDbType.VarChar, 20).Value = txtcrno.Text;
                cmd.Parameters.Add("@type", SqlDbType.VarChar, 30).Value = GetPaymentType();
                cmd.Parameters.Add("@amount", SqlDbType.Decimal).Value = Convert.ToDecimal(txtamounttopay.Text);
                cmd.Parameters.Add("@date", SqlDbType.Date).Value = Convert.ToDateTime(txtdate.Text);
                cmd.Parameters.Add("@remarks", SqlDbType.VarChar, 500).Value = txtremakrs.Text;
                cmd.Parameters.Add("@user", SqlDbType.VarChar, 50).Value = Login.Fullname;

                return Convert.ToInt32(cmd.ExecuteScalar());
            }
        }

        void InsertPaymentMethod(SqlConnection con, SqlTransaction tran, int paymentHeaderId)
        {
            string type = GetPaymentType();
            decimal netAmount = Convert.ToDecimal(txtamounttopay.Text);

            if (type == "CASH")
            {
                using (SqlCommand cmd = new SqlCommand(@"
                    INSERT INTO TransactionCashCollection
                        (PaymentHeaderID, CustomerKey, AmountPaid, Remarks, DatePaid, TransactedBy, isErrorCorrect)
                    VALUES
                        (@phid, @custkey, @amount, @remarks, @date, @user, 0)", con, tran))
                {
                    cmd.Parameters.Add("@phid", SqlDbType.Int).Value = paymentHeaderId;
                    cmd.Parameters.Add("@custkey", SqlDbType.VarChar, 118).Value = custkey;
                    cmd.Parameters.Add("@amount", SqlDbType.Decimal).Value = netAmount;
                    cmd.Parameters.Add("@remarks", SqlDbType.VarChar, 500).Value = txtremakrs.Text;
                    cmd.Parameters.Add("@date", SqlDbType.Date).Value = Convert.ToDateTime(txtdate.Text);
                    cmd.Parameters.Add("@user", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    cmd.ExecuteNonQuery();
                }
            }
            else if (type == "CHECK")
            {
                using (SqlCommand cmd = new SqlCommand(@"
                    INSERT INTO TransactionCheque
                        (PaymentHeaderID, BranchCode, ControlNo, CRNo, CustomerID, CustomerName,
                         CheckNo, CheckName, CheckBankName, CheckAmount, CheckDate,
                         Amount, Remarks, DatePaid, TransactedBy, CreditGLCode)
                    VALUES
                        (@phid, @branch, @control, @crno, @custid, @custname,
                         @checkno, @checkname, @bank, @checkamount, @checkdate,
                         @amount, @remarks, @date, @user, @glcode)", con, tran))
                {
                    cmd.Parameters.Add("@phid", SqlDbType.Int).Value = paymentHeaderId;
                    cmd.Parameters.Add("@branch", SqlDbType.Char, 3).Value = Customers.getCustBranch(txtcustid.Text);
                    cmd.Parameters.Add("@control", SqlDbType.VarChar, 30).Value = txtcontrolno.Text;
                    cmd.Parameters.Add("@crno", SqlDbType.VarChar, 20).Value = txtcrno.Text;
                    cmd.Parameters.Add("@custid", SqlDbType.VarChar, 20).Value = txtcustid.Text;
                    cmd.Parameters.Add("@custname", SqlDbType.VarChar, 120).Value = txtcustname.Text;
                    cmd.Parameters.Add("@checkno", SqlDbType.VarChar, 50).Value = txtchecknum.Text;
                    cmd.Parameters.Add("@checkname", SqlDbType.VarChar, 50).Value = txtcheckname.Text;
                    cmd.Parameters.Add("@bank", SqlDbType.VarChar, 50).Value = txtcheckbankname.Text;
                    cmd.Parameters.Add("@checkamount", SqlDbType.Money).Value = Convert.ToDecimal(txtcheckamount.Text);
                    cmd.Parameters.Add("@checkdate", SqlDbType.Date).Value = Convert.ToDateTime(txtcheckdate.Text);
                    cmd.Parameters.Add("@amount", SqlDbType.Money).Value = netAmount;
                    cmd.Parameters.Add("@remarks", SqlDbType.VarChar, 500).Value = txtremakrs.Text;
                    cmd.Parameters.Add("@date", SqlDbType.Date).Value = Convert.ToDateTime(txtdate.Text);
                    cmd.Parameters.Add("@user", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    // CreditGLCode stored here so SP can resolve the bank account
                    cmd.Parameters.Add("@glcode", SqlDbType.VarChar, 20).Value = txtdebitglcode.Text;
                    cmd.ExecuteNonQuery();
                }
            }
            else if (type == "ONLINE")
            {
                using (SqlCommand cmd = new SqlCommand(@"
                    INSERT INTO TransactionOnline
                        (PaymentHeaderID, BranchCode, ControlNo, CRNo,CustomerID, CustomerName, BankRefNumber, BankName, DateDeposit,
                         Amount, Remarks, DatePaid, TransactedBy)
                    VALUES
                        (@phid,@branch, @control, @crno, @custid, @custname, @refno, @bank, @depdate,
                         @amount, @remarks, @date, @user)", con, tran))
                {
                    cmd.Parameters.Add("@phid", SqlDbType.Int).Value = paymentHeaderId;
                    cmd.Parameters.Add("@branch", SqlDbType.Char, 3).Value = Customers.getCustBranch(txtcustid.Text);
                    cmd.Parameters.Add("@control", SqlDbType.VarChar, 30).Value = txtcontrolno.Text;
                    cmd.Parameters.Add("@crno", SqlDbType.VarChar, 20).Value = txtcrno.Text;
                    cmd.Parameters.Add("@custid", SqlDbType.VarChar, 20).Value = txtcustid.Text;
                    cmd.Parameters.Add("@custname", SqlDbType.VarChar, 120).Value = txtcustname.Text;
                    cmd.Parameters.Add("@refno", SqlDbType.VarChar, 50).Value = txtrefnoonline.Text;
                    cmd.Parameters.Add("@bank", SqlDbType.VarChar, 50).Value = txtdepbankonline.Text;
                    cmd.Parameters.Add("@depdate", SqlDbType.Date).Value = Convert.ToDateTime(txtdatedeponline.Text);
                    cmd.Parameters.Add("@amount", SqlDbType.Decimal).Value = netAmount;
                    cmd.Parameters.Add("@remarks", SqlDbType.VarChar, 500).Value = txtremakrs.Text;
                    cmd.Parameters.Add("@date", SqlDbType.Date).Value = Convert.ToDateTime(txtdate.Text);
                    cmd.Parameters.Add("@user", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    cmd.ExecuteNonQuery();
                }
            }
        }

        // ── AR PAYMENT DETAILS INSERT ────────────────────────────────────
        // [BUG-1] FIX: INVOICE PAYMENT row now stores GROSS (balance being settled),
        //         not net cash. The SP derives net cash as Gross - EWT - Discount - Offset.
        //
        //  Grid columns meaning:
        //    AmountPaid    = net cash physically received  (balance - deductions)
        //    EWTAmount     = EWT withheld
        //    DiscountAmount= discount granted
        //    OffsetAmount  = advance/deposit offset
        //    Balance       = original invoice balance (= gross being settled)
        //
        //  ARPaymentDetails rows:
        //    INVOICE PAYMENT → Amount = Balance (gross)   ← THE FIX
        //    EWT             → Amount = EWTAmount
        //    DISCOUNT        → Amount = DiscountAmount
        //    OFFSET          → Amount = OffsetAmount
        // ─────────────────────────────────────────────────────────────────
        void InsertARPaymentDetails(SqlConnection con, SqlTransaction tran, int paymentHeaderId)
        {
            for (int i = 0; i < gridView2.RowCount; i++)
            {
                bool pay = Convert.ToBoolean(gridView2.GetRowCellValue(i, "Pay"));
                if (!pay) continue;

                string invoiceNo = gridView2.GetRowCellValue(i, "InvoiceNo").ToString();
                string orderNo = gridView2.GetRowCellValue(i, "OrderNo").ToString();
                DateTime transDate = Convert.ToDateTime(gridView2.GetRowCellValue(i, "TransactionDate"));

                decimal ewt = Convert.ToDecimal(gridView2.GetRowCellValue(i, "EWTAmount") ?? 0);
                decimal discount = Convert.ToDecimal(gridView2.GetRowCellValue(i, "DiscountAmount") ?? 0);
                decimal offset = Convert.ToDecimal(gridView2.GetRowCellValue(i, "OffsetAmount") ?? 0);
                decimal overpay = Convert.ToDecimal(gridView2.GetRowCellValue(i, "OverPay") ?? 0);
                decimal servicesAmount = Convert.ToDecimal(gridView2.GetRowCellValue(i, "ServicesAmount") ?? 0);
                decimal amountPaid = Convert.ToDecimal(gridView2.GetRowCellValue(i, "AmountPaid") ?? 0);

                // GROSS = however much of the invoice is being cleared THIS
                // transaction, not necessarily the whole Balance - AmountPaid
                // can legitimately be less than Balance for a genuine partial
                // payment (no EWT/Discount/Offset, just paying less than owed).
                // Reconstruct it as net cash + deductions withheld/applied,
                // minus OverPay and ServicesAmount since RecalculateRow() already
                // baked both +overpay and +servicesAmount into AmountPaid
                // (balance - ewt - discount - offset + overpay + servicesAmount) -
                // without subtracting them back out here, both would double
                // count into gross.
                decimal gross = amountPaid + ewt + discount + offset - overpay - servicesAmount;

                // INVOICE PAYMENT: always insert using the gross amount
                if (gross > 0)
                    InsertDetail(con, tran, paymentHeaderId, orderNo, invoiceNo, transDate, gross, "INVOICE PAYMENT");

                if (ewt > 0)
                    InsertDetail(con, tran, paymentHeaderId, orderNo, invoiceNo, transDate, ewt, "EWT");

                if (discount > 0)
                    InsertDetail(con, tran, paymentHeaderId, orderNo, invoiceNo, transDate, discount, "DISCOUNT");

                if (offset > 0)
                    InsertDetail(con, tran, paymentHeaderId, orderNo, invoiceNo, transDate, offset, "OFFSET");

                if (overpay > 0)
                    InsertDetail(con, tran, paymentHeaderId, orderNo, invoiceNo, transDate, overpay, "OVERPAY");

                if (servicesAmount > 0)
                    InsertDetail(con, tran, paymentHeaderId, orderNo, invoiceNo, transDate, servicesAmount, "SERVICES");
            }
        }

        void InsertDetail(SqlConnection con, SqlTransaction tran, int phid,
                          string po, string invoice, DateTime date, decimal amount, string type)
        {
            using (SqlCommand cmd = new SqlCommand(@"
                INSERT INTO ARPaymentDetails
                    (PaymentHeaderID, CustomerKey, ReferenceNo, PONumber, InvoiceNo,
                     InvoiceDate, Amount, PaymentType, PaymentMethod,
                     DebitGLCode, CreditGLCode, TicketNumber)
                VALUES
                    (@phid, @custkey, @refno, @po, @invoice,
                     @date, @amount, @type, 'PAYMENT',
                     @debit, @credit, '')", con, tran))
            {
                cmd.Parameters.Add("@phid", SqlDbType.Int).Value = phid;
                cmd.Parameters.Add("@custkey", SqlDbType.Char, 8).Value = custkey;
                cmd.Parameters.Add("@refno", SqlDbType.VarChar, 20).Value = refno;
                cmd.Parameters.Add("@po", SqlDbType.VarChar, 10).Value = po;
                cmd.Parameters.Add("@invoice", SqlDbType.VarChar, 50).Value = invoice;
                cmd.Parameters.Add("@date", SqlDbType.Date).Value = date;
                cmd.Parameters.Add("@amount", SqlDbType.Decimal).Value = amount;
                cmd.Parameters.Add("@type", SqlDbType.VarChar, 20).Value = type;
                // Blank means "not applicable" (e.g. an EWT-only, zero-net-cash
                // entry) - store NULL rather than a literal empty string so it
                // reads honestly and sp_AddPaymentClient's own ISNULL/blank
                // check treats it consistently.
                cmd.Parameters.Add("@debit", SqlDbType.VarChar, 20).Value =
                    string.IsNullOrEmpty(txtdebitglcode.Text) ? (object)DBNull.Value : txtdebitglcode.Text;
                cmd.Parameters.Add("@credit", SqlDbType.VarChar, 20).Value =
                    string.IsNullOrEmpty(txtcreditglcode.Text) ? (object)DBNull.Value : txtcreditglcode.Text;
                cmd.ExecuteNonQuery();
            }
        }

        void ExecutePostingSP(SqlConnection con, SqlTransaction tran, int paymentHeaderId)
        {
            using (SqlCommand cmd = new SqlCommand("sp_AddPaymentClient", con, tran))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@PaymentHeaderID", SqlDbType.Int).Value = paymentHeaderId;
                cmd.ExecuteNonQuery();
            }
        }

        string GetPaymentType()
        {
            if (radioButton1.Checked) return "CASH";
            if (radioButton2.Checked) return "CHECK";
            if (radioButton3.Checked) return "ONLINE";
            //if (radioButton4.Checked) return "ADVANCEPAYMENT";
            if (radCreditCard.Checked) return "CREDITCARD";
            throw new Exception("No payment type selected.");
        }

        // ── POSTED CLIENT PAYMENTS (FullyPaid Invoice tab) ───────────────
        // Lists this customer's payment headers via sp_GetPostedClientPayments,
        // one row per PaymentHeader with a server-computed BlockedReason
        // (non-null once Status='REVERSED'). Replaces the old master-detail
        // grid so a flat row now maps 1:1 to what View/Edit Details act on.
        void LoadPostedClientPayments()
        {
            // @DateFrom/@DateTo are both inclusive and NULL-able on the SP
            // side now (sp_GetPostedClientPayments owns the +1-day exclusive
            // conversion internally) - passing DBNull here instead of
            // DateTime.MaxValue avoids a DATEADD(DAY,1,...) overflow on the
            // SP side when no end date is chosen.
            object dateFromParam = txtdatefrom.EditValue == null
                ? (object)DBNull.Value : (DateTime)txtdatefrom.EditValue;
            object dateToParam = txtdateto.EditValue == null
                ? (object)DBNull.Value : (DateTime)txtdateto.EditValue;

            using (SqlConnection con = Database.getConnection())
            using (SqlCommand cmd = new SqlCommand("sp_GetPostedClientPayments", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@CustomerKey", SqlDbType.Char, 8).Value = custkey;
                cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value = dateFromParam;
                cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value = dateToParam;

                DataTable table = new DataTable();
                con.Open();
                using (SqlDataReader dr = cmd.ExecuteReader())
                    table.Load(dr);

                gridControl1.DataSource = table;
            }

            gridControlPaymentDetails.DataSource = null;
            gridView9.OptionsView.ColumnAutoWidth = false;
            if (gridView9.Columns["BlockedReason"] != null)
                gridView9.Columns["BlockedReason"].VisibleIndex = 0;
            gridView9.BestFitColumns();
        }

        private void gridView9_RowCellStyle(object sender, RowCellStyleEventArgs e)
        {
            GridView view = sender as GridView;
            if (e.RowHandle < 0) return;

            object blocked = view.GetRowCellValue(e.RowHandle, "BlockedReason");
            if (blocked != null && blocked != DBNull.Value && blocked.ToString().Length > 0)
            {
                e.Appearance.ForeColor = Color.Gray;
                e.Appearance.Font = new Font(e.Appearance.Font, FontStyle.Strikeout);
            }
        }

        // ── VIEW DETAILS (inline GL-entries grid, same pattern as AddExpenseDevExFrm's
        // Posted Expenses tab: gridControlPosted on top, gridControlPostedDetails
        // below) ────────────────────────────────────────────────────────
        private void BtnViewDetails_Click(object sender, EventArgs e)
        {
            if (gridView9.FocusedRowHandle < 0)
            {
                XtraMessageBox.Show("Select a payment first.");
                return;
            }

            int paymentHeaderId = Convert.ToInt32(gridView9.GetFocusedRowCellValue("PaymentHeaderID"));

            DataTable header, glEntries, lines;
            if (!TryLoadPaymentDetails(paymentHeaderId, out header, out glEntries, out lines))
                return;

            if (header.Rows.Count == 0)
            {
                XtraMessageBox.Show("Payment header not found.");
                return;
            }

            gridControlPaymentDetails.DataSource = glEntries;
            gridViewPaymentDetails.PopulateColumns();
            if (gridViewPaymentDetails.Columns["Debit"] != null)
                gridViewPaymentDetails.Columns["Debit"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "Debit", "{0:n2}");
            if (gridViewPaymentDetails.Columns["Credit"] != null)
                gridViewPaymentDetails.Columns["Credit"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "Credit", "{0:n2}");
            gridViewPaymentDetails.BestFitColumns();
        }

        bool TryLoadPaymentDetails(int paymentHeaderId, out DataTable header, out DataTable glEntries, out DataTable lines)
        {
            header = new DataTable();
            glEntries = new DataTable();
            lines = new DataTable();
            try
            {
                using (SqlConnection con = Database.getConnection())
                using (SqlCommand cmd = new SqlCommand("sp_GetClientPaymentDetails", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@PaymentHeaderID", SqlDbType.Int).Value = paymentHeaderId;

                    con.Open();
                    using (SqlDataAdapter da = new SqlDataAdapter(cmd))
                    {
                        DataSet ds = new DataSet();
                        da.Fill(ds);
                        if (ds.Tables.Count > 0) header = ds.Tables[0];
                        if (ds.Tables.Count > 1) glEntries = ds.Tables[1];
                        if (ds.Tables.Count > 2) lines = ds.Tables[2];
                    }
                }
                return true;
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load payment details: {ex.Message}", "Error",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return false;
            }
        }

        // ── EDIT DETAILS (reverse + re-enter as a new payment) ────────────
        // A Client Payment IS the thing that touches TransactionChargeSales/
        // ClientLedger/TicketMaster/BankStatementRecon the moment
        // sp_AddPaymentClient runs, so per Known Bug Pattern #4 this can't be
        // a delete-and-repost in place - it has to go through the reversal
        // SP first. sp_ReversePaymentClient already exists and is tested; it
        // just wasn't wired to any screen yet. After reversing, the affected
        // invoice(s) go back to having a real balance, so re-showing the
        // Invoice w/Balances tab and pre-filling from the reversed values is
        // enough - no separate "SaveEdit" SP is needed, Confirm Payment posts
        // the correction the same way it posts any new payment.
        private void BtnEditDetails_Click(object sender, EventArgs e)
        {
            if (gridView9.FocusedRowHandle < 0)
            {
                XtraMessageBox.Show("Select a payment first.");
                return;
            }

            object blockedObj = gridView9.GetFocusedRowCellValue("BlockedReason");
            string blockedReason = (blockedObj == null || blockedObj == DBNull.Value) ? null : blockedObj.ToString();
            if (!string.IsNullOrEmpty(blockedReason))
            {
                XtraMessageBox.Show(blockedReason, "Cannot Edit", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            int paymentHeaderId = Convert.ToInt32(gridView9.GetFocusedRowCellValue("PaymentHeaderID"));
            string referenceNo = gridView9.GetFocusedRowCellValue("ReferenceNo")?.ToString();
            decimal totalAmount = Convert.ToDecimal(gridView9.GetFocusedRowCellValue("TotalAmount") ?? 0m);

            if (!HelperFunction.ConfirmDialog(
                $"This will reverse payment {referenceNo} ({totalAmount:N2}) and let you re-enter the corrected details as a new payment. Continue?",
                "Edit Payment"))
                return;

            DataTable header, glEntries, lines;
            if (!TryLoadPaymentDetails(paymentHeaderId, out header, out glEntries, out lines))
                return;
            if (header.Rows.Count == 0)
            {
                XtraMessageBox.Show("Payment header not found.");
                return;
            }

            try
            {
                using (SqlConnection con = Database.getConnection())
                using (SqlCommand cmd = new SqlCommand("sp_ReversePaymentClient", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@PaymentHeaderID", SqlDbType.Int).Value = paymentHeaderId;
                    cmd.Parameters.Add("@ReversedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    con.Open();
                    cmd.ExecuteNonQuery();
                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Reversal failed:\n{ex.Message}", "Error",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            // The reversal above already committed - it cannot be undone from
            // here. Everything past this point is just refreshing the UI, so
            // a failure here must not look like the reversal itself failed;
            // tell the user plainly that the payment IS reversed regardless.
            try
            {
                xtraTabControl1.SelectedTabPage = xtraTabPage1;
                display();
                PrefillEntryFromReversedPayment(header.Rows[0], lines);
                LoadPostedClientPayments();

                XtraMessageBox.Show(
                    $"Payment {referenceNo} has been reversed. Review the corrected details below and click Confirm Payment to repost.",
                    "Reversed — Ready for Correction", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(
                    $"Payment {referenceNo} WAS reversed successfully, but the screen could not be refreshed automatically:\n{ex.Message}\n\n" +
                    "Please re-select the invoice(s) manually on the Invoice w/Balances tab.",
                    "Reversed — Manual Refresh Needed", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        void PrefillEntryFromReversedPayment(DataRow h, DataTable lines)
        {
            string payType = h["PaymentType"]?.ToString();
            switch (payType)
            {
                case "CASH": radioButton1.Checked = true; break;
                case "CHECK": radioButton2.Checked = true; break;
                case "ONLINE": radioButton3.Checked = true; break;
                //case "ADVANCEPAYMENT": radioButton4.Checked = true; break;
                case "CREDITCARD": radCreditCard.Checked = true; break;
            }

            txtcontrolno.Text = h["ControlNo"]?.ToString();
            txtcrno.Text = h["CRNo"]?.ToString();
            txtremakrs.Text = h["Remarks"]?.ToString();
            if (h["PaymentDate"] != DBNull.Value)
                txtdate.EditValue = Convert.ToDateTime(h["PaymentDate"]);
            txtdebitglcode.Text = h["DebitGLCode"]?.ToString();
            txtcreditglcode.Text = h["CreditGLCode"]?.ToString();

            if (payType == "CHECK")
            {
                if (h["CheckNo"] != DBNull.Value) txtchecknum.Text = h["CheckNo"].ToString();
                if (h["CheckName"] != DBNull.Value) txtcheckname.Text = h["CheckName"].ToString();
                if (h["CheckBankName"] != DBNull.Value) txtcheckbankname.Text = h["CheckBankName"].ToString();
                if (h["CheckAmount"] != DBNull.Value) txtcheckamount.Text = Convert.ToDecimal(h["CheckAmount"]).ToString("N2");
                if (h["CheckDate"] != DBNull.Value) txtcheckdate.EditValue = Convert.ToDateTime(h["CheckDate"]);
            }
            else if (payType == "ONLINE")
            {
                if (h["BankRefNumber"] != DBNull.Value) txtrefnoonline.Text = h["BankRefNumber"].ToString();
                if (h["BankName"] != DBNull.Value) txtdepbankonline.Text = h["BankName"].ToString();
                if (h["DateDeposit"] != DBNull.Value) txtdatedeponline.EditValue = Convert.ToDateTime(h["DateDeposit"]);
            }

            // CellValueChanged is unhooked for this loop - gridView2's handler
            // resets EWT/Discount/Offset/OverPay to 0 and AmountPaid=Balance
            // the moment Pay flips true, then RecalculateRow recomputes
            // AmountPaid again after each subsequent SetRowCellValue. Letting
            // that cascade run mid-loop only produced the right end result by
            // accident of field ordering; writing all values first and
            // recalculating once after is the same approach RecalculateRow's
            // own comment already documents as necessary in this DevExpress
            // version.
            gridView2.CellValueChanged -= gridView2_CellValueChanged;
            var notFound = new List<string>();
            try
            {
                foreach (DataRow line in lines.Rows)
                {
                    string invoiceNo = line["InvoiceNo"]?.ToString()?.Trim();
                    int rowHandle = gridView2.LocateByValue("InvoiceNo", invoiceNo);
                    if (rowHandle == DevExpress.XtraGrid.GridControl.InvalidRowHandle)
                    {
                        notFound.Add(invoiceNo);
                        continue;
                    }

                    gridView2.SetRowCellValue(rowHandle, "Pay", true);
                    gridView2.SetRowCellValue(rowHandle, "EWTAmount", DBNullToDecimal(line["EWTAmount"]));
                    gridView2.SetRowCellValue(rowHandle, "DiscountAmount", DBNullToDecimal(line["DiscountAmount"]));
                    gridView2.SetRowCellValue(rowHandle, "OffsetAmount", DBNullToDecimal(line["OffsetAmount"]));
                    gridView2.SetRowCellValue(rowHandle, "OverPay", DBNullToDecimal(line["OverPay"]));
                    gridView2.SetRowCellValue(rowHandle, "ServicesAmount", DBNullToDecimal(line["ServicesAmount"]));
                    gridView2.SetRowCellValue(rowHandle, "AmountPaid", DBNullToDecimal(line["SuggestedAmountPaid"]));
                }
            }
            finally
            {
                gridView2.CellValueChanged += gridView2_CellValueChanged;
            }

            ComputeTotal();

            if (notFound.Count > 0)
                XtraMessageBox.Show(
                    "The following invoice(s) from the reversed payment are no longer in the outstanding list " +
                    "(may have since been settled by another payment) and were not pre-filled:\n\n" +
                    string.Join(", ", notFound),
                    "Some Invoices Not Pre-filled", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        static decimal DBNullToDecimal(object value) =>
            (value == null || value == DBNull.Value) ? 0m : Convert.ToDecimal(value);

        // ── HISTORY SEARCH ──────────────────────────────────────────────
        // [BUG-4] FIX: was raw string concatenation (SQL injection risk).
        // Now uses parameterized query.
        private void simpleButton1_Click_1(object sender, EventArgs e)
        {
            //using (SqlConnection con = Database.getConnection())
            //using (SqlCommand cmd = new SqlCommand(@"
            //    SELECT TransactionDate, CustomerKey, ReferenceNo,
            //           TotalAmount, AmountPaid, Balance, PayStatus
            //    FROM TransactionChargeSales
            //    WHERE CAST(TransactionDate AS DATE) BETWEEN @from AND @to
            //      AND CustomerKey = @custkey
            //      AND Balance = 0", con))
            //{
            //    cmd.Parameters.Add("@from", SqlDbType.Date).Value = Convert.ToDateTime(txtdatefrom.Text);
            //    cmd.Parameters.Add("@to", SqlDbType.Date).Value = Convert.ToDateTime(txtdateto.Text);
            //    cmd.Parameters.Add("@custkey", SqlDbType.Char, 8).Value = custkey;

            //    DataTable table = new DataTable();
            //    con.Open();
            //    using (SqlDataReader dr = cmd.ExecuteReader())
            //        table.Load(dr);

            //    gridControl1.DataSource = table;
            //    gridView9.BestFitColumns();
            //}
            LoadPostedClientPayments();
        }

        private void simpleButton2_Click(object sender, EventArgs e) { /* reserved */ }

        private void gridControl1_ViewRegistered(object sender, DevExpress.XtraGrid.ViewOperationEventArgs e)
        {
            GridView view = e.View as GridView;
            if (view == null) return;

            // ✅ Apply to ALL views (master + detail)
            view.OptionsView.ColumnAutoWidth = false;
            view.OptionsView.RowAutoHeight = true;
            view.OptionsBehavior.ReadOnly = true;
            view.OptionsBehavior.Editable = false;

            view.PopulateColumns();
            view.BestFitColumns();
        }

        private void gridView9_MasterRowExpanded(object sender, CustomMasterRowEventArgs e)
        {
            GridView masterView = sender as GridView;

            // ✅ Get actual detail view
            GridView detailView = masterView.GetDetailView(e.RowHandle, e.RelationIndex) as GridView;

            if (detailView != null)
            {
                detailView.OptionsView.ColumnAutoWidth = false;
                detailView.PopulateColumns();

                // ✅ SHOW FOOTER
                detailView.OptionsView.ShowFooter = true;

                // ✅ Footer styling
                detailView.Appearance.FooterPanel.BackColor = Color.LightYellow;
                detailView.Appearance.FooterPanel.ForeColor = Color.Black;
                detailView.Appearance.FooterPanel.Font = new Font("Segoe UI", 9, FontStyle.Bold);

                // ✅ ADD SUM FOR DEBIT
                if (detailView.Columns["TotalAmount"] != null)
                {
                    detailView.Columns["TotalAmount"].Summary.Clear();
                    detailView.Columns["TotalAmount"].Summary.Add(
                        DevExpress.Data.SummaryItemType.Sum,
                        "TotalAmount",
                        "Total: {0:n2}"
                    );
                }

                // ✅ ADD SUM FOR CREDIT
                if (detailView.Columns["EWTAmount"] != null)
                {
                    detailView.Columns["EWTAmount"].Summary.Clear();
                    detailView.Columns["EWTAmount"].Summary.Add(
                        DevExpress.Data.SummaryItemType.Sum,
                        "EWTAmount",
                        "Total: {0:n2}"
                    );
                }

                detailView.BestFitColumns();

                //// ✅ HIDE COLUMNS
                //detailView.Columns["BranchCode"].Visible = false;
                //detailView.Columns["TicketDate"].Visible = false;
                //detailView.Columns["TicketNumber"].Visible = false;
                //detailView.Columns["ReferenceNumber"].Visible = false;
                //detailView.Columns["ReferenceKey"].Visible = false;

                // ✅ MIN WIDTH FOR DETAIL
                foreach (DevExpress.XtraGrid.Columns.GridColumn col in detailView.Columns)
                {
                    col.MinWidth = 100;
                }

                // ✅ MIN WIDTH FOR MASTER
                foreach (DevExpress.XtraGrid.Columns.GridColumn col in gridView9.Columns)
                {
                    col.MinWidth = 100;
                }

                masterView.BestFitColumns();
            }

        }

        private void txtcustname_EditValueChanged(object sender, EventArgs e)
        {
            objcustid = SearchLookUpClass.getSingleValue(txtcustname, "CustomerKey");
            if (objcustid == null || objcustid == DBNull.Value)
                return;

            txtcustid.Text = objcustid.ToString();

            // custkey previously only got set once, in Load(), from whatever
            // txtcustid.Text happened to be at that moment. That was fine as
            // long as this control was only ever opened by a caller that
            // pre-set txtcustid before showing it (its only prior caller);
            // now that it's reachable standalone from the Accounting Board
            // menu with no pre-set customer, picking one here has to re-key
            // every downstream query or it keeps hitting the stale/blank
            // customer from Load.
            custkey = txtcustid.Text;
            groupControl1.Text = custkey;
            display();
            if (xtraTabControl1.SelectedTabPage == xtraTabPage2)
                LoadPostedClientPayments();
        }

        private void groupBox1_Enter(object sender, EventArgs e)
        {

        }

        private void simpleButton5_Click(object sender, EventArgs e) { /* reserved */ }
        private void txtremakrs_EditValueChanged(object sender, EventArgs e) { }
        private void gridView2_ShowingEditor(object sender, System.ComponentModel.CancelEventArgs e) { }
        // ── DATA MODEL ───────────────────────────────────────────────────────
        class PaymentRow
        {
            public bool Pay { get; set; }
            public string InvoiceNo { get; set; }
            public string OrderNo { get; set; }
            public DateTime TransactionDate { get; set; }
            public decimal AmountPaid { get; set; }   // net cash
            public decimal EWTAmount { get; set; }
            public decimal DiscountAmount { get; set; }
            public decimal OffsetAmount { get; set; }
        }
    }
}