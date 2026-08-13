using DevExpress.CodeParser;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid;
using DevExpress.XtraGrid.Columns;
using DevExpress.XtraGrid.Views.Grid;
using DevExpress.XtraReports.UI;
using SalesInventorySystem.Classes;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Text;
using System.Windows.Forms;

// ALL VIEWS
//view_POSummary - FOR APPROVAL gridview1, APPROVED REQUEST gridview2, REJECTED REQUEST gridview 3
//view_OrdersForDelivery -- FOR DELIVERY gridview4
//view_DeliverySummary --DELIVERED gridview5,
//view_BranchOrderDetails
//view_CreditMemoDetails
//view_PurchaseOrderDetails
//view_BranchOrderForReceiving
//funcview_ForDeliveryDetails
//view_DeliveryReciept
//spview_SalesInvoice
//view_ClientChargeSalesDetails


namespace SalesInventorySystem
{
    public partial class POForApproval : DevExpress.XtraEditors.XtraForm
    {
        public static string refno,stat,refno1="",stat1="",brcode,devno="",menu="",invoiceno="";
        public static string requestedBy = "";
        string company = Database.getSingleQuery("CompanyProfile", "CompanyName <> ''", "CompanyName");
        public static bool isupdated = false;
        public POForApproval()
        {
            InitializeComponent();
        }

        private void POForApproval_Load(object sender, EventArgs e)
        {
            HelperFunction.SetDefaultDateRange(datefromforapproval, datetoforapproval,7, 7);
            HelperFunction.SetDefaultDateRange(datefromapproved, datetoapproved, 7, 7);
            HelperFunction.SetDefaultDateRange(datefromrejected, datetorejected, 7, 7);
            HelperFunction.SetDefaultDateRange(datefromdelivered, datetodelivered, 7, 7);
            HelperFunction.SetDefaultDateRange(dateFromDeliv, dateToDeliv, 7, 7);
            HelperFunction.SetDefaultDateRange(dateFromReturned, dateToReturned, 7, 7);
            HelperFunction.SetDefaultDateRange(dateFromPaid, dateToPaid, 7, 7);
            HelperFunction.SetDefaultDateRange(dateFromForApprovalServices, dateToForApprovalServices, 7, 7);
            HelperFunction.SetDefaultDateRange(dateFromApprovedServices, dateToApprovedServices, 7, 7);
            HelperFunction.SetDefaultDateRange(dateTimePicker2, dateTimePicker1, 7, 7);
            //filtertab();
        }


        private void filtertab()
        {
            if (tabMain.SelectedTabPage.Equals(tabForApproval))
            {
                if (tabForApprovalSub.SelectedTabPage.Equals(forApprovalServicesSalesOrder))
                {
                    loadForApprovalServices();
                }
                else
                {
                    Database.display("SELECT * FROM view_POSummary WHERE Status='FOR APPROVAL' and EffectivityDate >= '" + datefromforapproval.Text + "' and EffectivityDate <= '" + datetoforapproval.Text + "' AND BranchCode='" + Login.assignedBranch + "'", gridControl1, gridView1);
                }
            }
            else if (tabMain.SelectedTabPage.Equals(tabApproved))
            {
                if (tabApprovedSub.SelectedTabPage.Equals(approvedServicesSalesOrder))
                {
                    loadApprovedServices();
                }
                else
                {
                    Database.display("SELECT * FROM view_POSummary WHERE Status='APPROVED' and EffectivityDate >= '" + datefromapproved.Text + "' and EffectivityDate <= '" + datetoapproved.Text + "' AND BranchCode='" + Login.assignedBranch + "' ORDER BY DateAdded DESC", gridControl2, gridView2);
                }
            }
            else if (tabMain.SelectedTabPage.Equals(tabRejected))
            {
                if (tabRejectedSub.SelectedTabPage.Equals(rejectedServicesSalesOrder))
                {
                    loadRejectedServices();
                }
                else
                {
                    Database.display("SELECT * FROM view_POSummary WHERE Status='REJECTED' and EffectivityDate >= '" + datefromrejected.Text + "' and EffectivityDate <= '" + datefromrejected.Text + "' AND BranchCode='" + Login.assignedBranch + "'", gridControl3, gridView3);
                }
            }
            else if (tabMain.SelectedTabPage.Equals(tabForDelivery))
            {
                Database.display("SELECT * FROM view_OrdersForDelivery WHERE Status='FOR DELIVERY'  and EffectivityDate >= '" + datefromdelivered.Text + "' and EffectivityDate <= '" + datetodelivered.Text + "' ORDER BY PONumber", gridControl4, gridView4);
                Classes.DevXGridViewSettings.ShowFooterCountTotal(gridView4, "DeliveryNo");
                Classes.DevXGridViewSettings.ShowFooterTotal(gridView4, "TotalItem");
                Classes.DevXGridViewSettings.ShowFooterTotal(gridView4, "TotalQtyDelivered");
            }
            else if (tabMain.SelectedTabPage.Equals(tabDelivered))
            {
                loadDeliveredSalesOrder();
            }
            else if (tabMain.SelectedTabPage.Equals(tabPaid))
            {
                loadPaidSalesOrder();
            }
        }

        // Shared by filtertab() (tab switch) and btnDeliveredSalesOrder_Click (manual refresh) --
        // both must populate gridView5 identically, since gridView5_RowStyle depends on the
        // HasCreditMemo/HasReturnOrder columns added here being present either way.
        void loadDeliveredSalesOrder()
        {
            Database.display(
                "SELECT v.*, " +
                "CASE WHEN EXISTS (SELECT 1 FROM CreditMemo cm WHERE cm.PONumber = v.PONumber) THEN 1 ELSE 0 END AS HasCreditMemo, " +
                "CASE WHEN EXISTS (SELECT 1 FROM ReturnedOrderDetails rod WHERE rod.PONumber = v.PONumber) THEN 1 ELSE 0 END AS HasReturnOrder " +
                "FROM view_DeliverySummary v " +
                "WHERE v.Status='DELIVERED' and v.DateApproved >= '" + dateFromDeliv.Text + "' and v.DateApproved < DATEADD(DAY,1,'" + dateToDeliv.Text + "')  AND v.BranchCode='" + Login.assignedBranch + "' " +
                // Already fully paid (Balance=0) POs are excluded from this list. Only excludes
                // when a TransactionChargeSales row exists AND shows Balance=0 -- a PO with no AR
                // row at all still shows, rather than being silently hidden.
                "AND NOT EXISTS (SELECT 1 FROM TransactionChargeSales t WHERE t.ReferenceNo = v.PONumber AND t.Balance = 0) " +
                "ORDER BY v.PONumber", gridControl5, gridView5);
            gridView5.Columns["HasCreditMemo"].Visible = false;
            gridView5.Columns["HasReturnOrder"].Visible = false;
        }

        // Same shape as loadDeliveredSalesOrder(), inverted: only POs that ARE fully paid
        // (TransactionChargeSales.Balance = 0) -- the ones loadDeliveredSalesOrder() excludes.
        void loadPaidSalesOrder()
        {
            Database.display(
                "SELECT v.*, " +
                "CASE WHEN EXISTS (SELECT 1 FROM CreditMemo cm WHERE cm.PONumber = v.PONumber) THEN 1 ELSE 0 END AS HasCreditMemo, " +
                "CASE WHEN EXISTS (SELECT 1 FROM ReturnedOrderDetails rod WHERE rod.PONumber = v.PONumber) THEN 1 ELSE 0 END AS HasReturnOrder " +
                "FROM view_DeliverySummary v " +
                "WHERE v.Status='DELIVERED' and v.DateApproved >= '" + dateFromPaid.Text + "' and v.DateApproved < DATEADD(DAY,1,'" + dateToPaid.Text + "')  AND v.BranchCode='" + Login.assignedBranch + "' " +
                "AND EXISTS (SELECT 1 FROM TransactionChargeSales t WHERE t.ReferenceNo = v.PONumber AND t.Balance = 0) " +
                "ORDER BY v.PONumber", gridControlPaid, gridViewPaid);
            gridViewPaid.Columns["HasCreditMemo"].Visible = false;
            gridViewPaid.Columns["HasReturnOrder"].Visible = false;
        }

        // Services Sales Order sub-tabs (dedicated ServiceOrderSummary/ServiceOrderDetails tables --
        // see SQL/2026-08-09_ServiceOrder_NewTables_And_SPs.sql. Services never go through the
        // Delivery/BatchSales/ConfirmOrder pipeline the Products sub-tabs above use.)
        void loadForApprovalServices()
        {
            Database.display("SELECT * FROM view_ServiceOrderSummary WHERE Status='FOR APPROVAL' and DateAdded >= '" + dateFromForApprovalServices.Text + "' and DateAdded < DATEADD(DAY,1,'" + dateToForApprovalServices.Text + "') AND BranchCode='" + Login.assignedBranch + "' ORDER BY DateAdded DESC", gridControlForApprovalServices, gridViewForApprovalServices);
        }

        void loadApprovedServices()
        {
            Database.display("SELECT * FROM view_ServiceOrderSummary WHERE Status='APPROVED' and DateApproved >= '" + dateFromApprovedServices.Text + "' and DateApproved < DATEADD(DAY,1,'" + dateToApprovedServices.Text + "') AND BranchCode='" + Login.assignedBranch + "' ORDER BY DateApproved DESC", gridControlApprovedServices, gridViewApprovedServices);
        }

        // NOTE: this sub-tab's controls are still under their DevExpress-assigned default
        // names (never renamed in the designer) -- dateTimePicker2=From, dateTimePicker1=To,
        // simpleButton7="Generate"/load, gridControl6/gridView6=the list grid. Rename via the
        // VS Designer's Properties panel (safe, updates all references) whenever convenient.
        void loadRejectedServices()
        {
            Database.display("SELECT * FROM view_ServiceOrderSummary WHERE Status='REJECTED' and DateRejected >= '" + dateTimePicker2.Text + "' and DateRejected < DATEADD(DAY,1,'" + dateTimePicker1.Text + "') AND BranchCode='" + Login.assignedBranch + "' ORDER BY DateRejected DESC", gridControl6, gridView6);
        }

        private void btnApproveService_Click(object sender, EventArgs e)
        {
            loadForApprovalServices();
        }

        private void btnApprovedServices_Click(object sender, EventArgs e)
        {
            loadApprovedServices();
        }

        private void simpleButton7_Click(object sender, EventArgs e)
        {
            loadRejectedServices();
        }

        private void tabForApprovalSub_SelectedPageChanged(object sender, DevExpress.XtraTab.TabPageChangedEventArgs e)
        {
            filtertab();
        }

        private void tabApprovedSub_SelectedPageChanged(object sender, DevExpress.XtraTab.TabPageChangedEventArgs e)
        {
            filtertab();
        }

        private void tabRejectedSub_SelectedPageChanged(object sender, DevExpress.XtraTab.TabPageChangedEventArgs e)
        {
            filtertab();
        }

        private void gridViewForApprovalServices_DoubleClick(object sender, EventArgs e)
        {
            if (gridViewForApprovalServices.FocusedRowHandle < 0)
                return;

            if (Convert.ToBoolean(Login.isglobalApprover) != true)
            {
                XtraMessageBox.Show("You are not authorized to approve/reject Service Orders.");
                return;
            }

            string svcNumber = gridViewForApprovalServices.GetRowCellValue(gridViewForApprovalServices.FocusedRowHandle, "SVCNumber").ToString();
            string custName = gridViewForApprovalServices.GetRowCellValue(gridViewForApprovalServices.FocusedRowHandle, "Customer").ToString();
            decimal totalAmount = Convert.ToDecimal(gridViewForApprovalServices.GetRowCellValue(gridViewForApprovalServices.FocusedRowHandle, "TotalAmount"));

            StringBuilder detail = new StringBuilder();
            detail.AppendLine("Service Order: " + svcNumber);
            detail.AppendLine("Customer: " + custName);
            detail.AppendLine();
            DataTable lines = Database.GetDataTable("SELECT ServiceName, Qty, SellingPrice, Amount FROM funcview_ServiceOrderDetails('" + svcNumber + "')");
            foreach (DataRow r in lines.Rows)
            {
                detail.AppendLine("  " + r["ServiceName"] + "  x" + r["Qty"] + "  @ " + Convert.ToDecimal(r["SellingPrice"]).ToString("n2") + " = " + Convert.ToDecimal(r["Amount"]).ToString("n2"));
            }
            detail.AppendLine();
            detail.AppendLine("Total: " + totalAmount.ToString("n2"));
            detail.AppendLine();
            detail.AppendLine("Yes = Approve, No = Reject, Cancel = do nothing.");

            DialogResult result = XtraMessageBox.Show(detail.ToString(), "Service Order Approval", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
            if (result == DialogResult.Yes)
            {
                try
                {
                    using (SqlConnection con = Database.getConnection())
                    {
                        con.Open();
                        SqlCommand com = new SqlCommand("sp_ApproveServiceOrder", con);
                        com.CommandType = CommandType.StoredProcedure;
                        com.Parameters.AddWithValue("@SVCNumber", svcNumber);
                        com.Parameters.AddWithValue("@ApprovedBy", Login.Fullname);
                        com.ExecuteNonQuery();
                    }
                    XtraMessageBox.Show("Service Order Approved.");
                    loadForApprovalServices();
                }
                catch (SqlException ex)
                {
                    XtraMessageBox.Show(ex.Message.ToString());
                }
            }
            else if (result == DialogResult.No)
            {
                string reason = XtraInputBox.Show("Enter rejection reason:", "Reject Service Order", "");
                if (string.IsNullOrWhiteSpace(reason))
                    return;
                try
                {
                    using (SqlConnection con = Database.getConnection())
                    {
                        con.Open();
                        SqlCommand com = new SqlCommand("sp_RejectServiceOrder", con);
                        com.CommandType = CommandType.StoredProcedure;
                        com.Parameters.AddWithValue("@SVCNumber", svcNumber);
                        com.Parameters.AddWithValue("@RejectedBy", Login.Fullname);
                        com.Parameters.AddWithValue("@Reason", reason);
                        com.ExecuteNonQuery();
                    }
                    XtraMessageBox.Show("Service Order Rejected.");
                    loadForApprovalServices();
                }
                catch (SqlException ex)
                {
                    XtraMessageBox.Show(ex.Message.ToString());
                }
            }
        }

        private void gridControl1_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
            {
                contextMenuStrip1.Show(gridControl1, e.Location);
            }
        }

        private void approveToolStripMenuItem_Click(object sender, EventArgs e)
        {
            showApproval();
        }

        
       
        void showApproval()
        {
            menu = "";
            requestedBy = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "RequestedBy").ToString();
            refno = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "PONumber").ToString();
            stat = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "Status").ToString();
            GlobalVariables.ponumber = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "PONumber").ToString();
            if (stat == "FOR APPROVAL")
            {
                POForApprovalDetails podetails = new POForApprovalDetails();
                podetails.FormClosed += new FormClosedEventHandler(podetails_FormClosed);
                podetails.Show();
                if (Convert.ToBoolean(Login.isglobalWarehouseOfficer) == true)
                {

                    Database.display("SELECT * FROM view_PurchaseOrderDetails WHERE PONumber = '" + refno + "' ORDER BY SeqNo", podetails.gridControl1, podetails.gridView1);
                    podetails.txtpono.Text = refno;
                    GridView view = podetails.gridControl1.FocusedView as GridView;
                    view.SortInfo.ClearAndAddRange(new GridColumnSortInfo[] {
                        new GridColumnSortInfo(view.Columns["Category"],DevExpress.Data.ColumnSortOrder.Ascending)
                        }, 1);
                    podetails.gridView1.Columns["SeqNo"].Visible = false;
                    podetails.gridView1.ExpandAllGroups();
                }
                if (Convert.ToBoolean(Login.isglobalApprover) == true)
                {

                    Database.display("SELECT * FROM view_PurchaseOrderDetails WHERE PONumber = '" + refno + "' ORDER BY SeqNo", podetails.gridControl1, podetails.gridView1);
                    podetails.txtpono.Text = refno;
                    GridView view = podetails.gridControl1.FocusedView as GridView;
                    view.SortInfo.ClearAndAddRange(new GridColumnSortInfo[] {
                        new GridColumnSortInfo(view.Columns["Category"],DevExpress.Data.ColumnSortOrder.Ascending)
                        }, 1);
                    podetails.gridView1.Columns["SeqNo"].Visible = false;
                    podetails.gridView1.ExpandAllGroups();
                }
                else
                {
                    Database.display("SELECT SeqNo,PONumber,ProductName,Qty,Units FROM view_PurchaseOrderDetails WHERE PONumber = '" + refno + "' ORDER BY SeqNo ", podetails.gridControl1, podetails.gridView1);
                    podetails.txtpono.Text = refno;
                    podetails.gridView1.Columns["SeqNo"].Visible = false;
                }
                GridGroupSummaryItem ite = new GridGroupSummaryItem();
                ite.FieldName = "Qty";
                ite.SummaryType = DevExpress.Data.SummaryItemType.Sum;
                ite.ShowInGroupColumnFooter = podetails.gridView1.Columns["Qty"];
                podetails.gridView1.GroupSummary.Add(ite);
            }
            else
            {
                XtraMessageBox.Show("You Already Approved this Order!");
            }
        }

        private void gridView1_DoubleClick(object sender, EventArgs e)
        {
            showApproval();
        }

        void podetails_FormClosed(object sender, FormClosedEventArgs e)
        {
            filtertab();
        }

        private void tabControl1_SelectedIndexChanged(object sender, EventArgs e)
        {
            filtertab();
        }

        private void gridView1_KeyDown(object sender, KeyEventArgs e)
        {
            menu = "";
            if (e.KeyCode == Keys.Enter)
            {
                showApproval();
            }
        }

       
        private void confirmOrderToolStripMenuItem_Click(object sender, EventArgs e)
        {
            devno = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "DeliveryNo").ToString();
            refno1 = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "PONumber").ToString();
            stat1 = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "Status").ToString();
            brcode = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "BranchCode").ToString();

            AddBranchInventoryFrm addbrnchfrm = new AddBranchInventoryFrm();
            addbrnchfrm.txtdevno.Text = devno;
            addbrnchfrm.txtpono.Text = refno1;
           
            addbrnchfrm.Show();
            Database.display("SELECT * FROM view_BranchOrderForReceiving WHERE DeliveryNo='" + devno + "'", addbrnchfrm.gridControl2, addbrnchfrm.gridView2);
            Database.display("SELECT ProductCode,Barcode,ProductName,Qty,DateReceived,ReceivedBy FROM ReceivedOrderDetails WHERE DeliveryNo='" + devno + "'", addbrnchfrm.gridControl1, addbrnchfrm.gridView1);

        }

        private void gridControl4_MouseUp(object sender, MouseEventArgs e)
        {
           
               // contextdelivered.Show(gridControl4, e.Location);
        }

        private void printDeliveryReceiptToolStripMenuItem_Click(object sender, EventArgs e)
        {
            refno1 = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "PONumber").ToString();
            HOForms.ViewForDeliveryDetails viewdet = new HOForms.ViewForDeliveryDetails();
            viewdet.ShowDialog(this);
        }

        private void confirmOrderToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            //XtraMessageBox.Show("ILOVEYOU 3000x .. . .. .....");
            try
            {
                bool isInvoiceUpdated = Database.checkifExist("Select isInvoiceUpdate FROM DeliverySummary WHERE PONumber='" + gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "PONumber").ToString() + "' and isInvoiceUpdate=1");
                if (isInvoiceUpdated == false)
                {
                    BigAlert.Show("UPDATE INVOICE",
                        "Invoice Number must be updated first..please go to Print Delivery Receipt Option!...",
                        MessageBoxIcon.Warning);
                    return;
                }
                else
                {
                    HOFormsDevEx.ConfirmOrderDevEx confi = new HOFormsDevEx.ConfirmOrderDevEx();
                    confi.txtdevno.Text = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "DeliveryNo").ToString();
                    confi.txtpono.Text = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "PONumber").ToString();
                    confi.txteffectivitydate.Text = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "EffectivityDate").ToString();
                    string custkey = Database.getSingleQuery("PurchaseOrderSummary", "PONumber='" + confi.txtpono.Text + "'", "Customer");
                    confi.txtcustname.Text = Database.getSingleQuery("Customers", "CustomerKey='" + custkey + "'", "CustomerName");
                    confi.txtpreparedby.Text = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "PreparedBy").ToString();
                    confi.txtrefkey.Text = Database.getSingleQuery("DeliverySummary", "PONumber='" + confi.txtpono.Text + "'", "InvoiceNo");
                    confi.txtstatus.Text = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "Status").ToString();
                    confi.txttotalitem.Text = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "TotalItem").ToString();
                    confi.txttotalqty.Text = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "TotalQtyDelivered").ToString();
                    //Database.display("Select SequenceNo,ProductNo,ProductName,QtyDelivered,Cost,SellingPrice,DateProcessed,ProcessedBy FROM DeliveryDetails WHERE PONumber='" + confi.txtpono.Text + "'", confi.gridControl2, confi.gridView2);
                    Database.display("Select * FROM funcview_ForDeliveryDetails('" + confi.txtpono.Text + "')", confi.gridControl2, confi.gridView2);
                    confi.gridView2.Columns["SeqNo"].Visible = false;
                    //FOR JUDPHILAN ONLY DEBIT MEMO CHARGES
                    //Database.GridMasterDetail("ClientChargeSalesSummary", "ClientChargeSalesDetails","PONumber='"+confi.txtpono.Text+"'", "PONumber='" + confi.txtpono.Text + "' ", "ChargeNo", "ChargeNo", "DeliveryChargeDetails", confi.gridControlChargesSum);
                    confi.ShowDialog(this);
                    if (HOFormsDevEx.ConfirmOrderDevEx.isdone == true)
                    {
                        filtertab();
                        HOFormsDevEx.ConfirmOrderDevEx.isdone = false;
                        confi.Dispose();
                    }
                    // confirmOrder();
                    //filtertab();
                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }

        private void returnOrderToolStripMenuItem_Click(object sender, EventArgs e)
        {
            
            devno = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "DeliveryNo").ToString();
            refno1 = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "PONumber").ToString();
            //invoiceno = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "PONumber").ToString();
            Orders.ReturnSalesOrder salesret = new Orders.ReturnSalesOrder();
            salesret.Show();
            Database.display("SELECT * FROM view_BranchOrderDetails WHERE PONumber='" + refno1 + "' and isReturned=0", salesret.gridControl1, salesret.gridView1);
            salesret.txtpono.Text = refno1;
            salesret.txtdevno.Text = devno;
            //salesret.txtbrcode.Text = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "BranchCode").ToString();
            salesret.txtstatus.Text = "FOR DELIVERY";
        }

        private void printDeliveryReceiptToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            //view_DeliveryReciept is selected DeliveryDetails tables only with condition of isReturned=0
            refno1 = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "PONumber").ToString();
            HOForms.ViewForDeliveryDetails viewdet = new HOForms.ViewForDeliveryDetails();
            viewdet.Show();
            Database.display("SELECT ProductNo" +
                ",ProductName" +
                ",BarcodeNo" +
                ",QtyDelivered" +
                ",FORMAT(SellingPrice, 'N','en-US')  AS Price" +
                ",FORMAT((QtyDelivered*SellingPrice), 'N','en-US') AS Amount " +
                "FROM view_DeliveryReciept " +
                "WHERE PONumber = '" + refno1 + "'", viewdet.gridControl4, viewdet.gridView4);
            viewdet.txtpono.Text = refno1;
            viewdet.gridView4.Columns["Amount"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "Amount", "{0:n2}");
            bool isInvoiceUpdate = Database.checkifExist("Select isnull(isInvoiceUpdate,0) FROM DeliverySummary WHERE PONumber='" + viewdet.txtpono.Text + "'");
            if (isInvoiceUpdate == true)
            {
                string InvoiceNo = Database.getSingleQuery("DeliverySummary", "PONumber='" + viewdet.txtpono.Text + "'", "InvoiceNo");
                viewdet.txtsino.Text = InvoiceNo;
            }
           
        }

        private void editOrderDetailsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            HOFormsDevEx.EditOrderDetailsDevEx addorder = new HOFormsDevEx.EditOrderDetailsDevEx();
            addorder.Show();
         
            Database.display("SELECT PONumber,BranchCode,ProductCode,ProductName,Qty,Units,'' as SellingPrice,Status,Remarks FROM PurchaseOrderDetails WHERE PONumber='" + gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "PONumber").ToString() + "'",addorder.gridControl1,addorder.gridView1);
            addorder.txtponum.Text = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "PONumber").ToString();
        }

        private void btnforappothers_Click(object sender, EventArgs e)
        {
            //Database.display("SELECT * FROM view_POSummary WHERE Status='FOR APPROVAL' and DateAdded >= '" + datefromforapproval.Text + "' and DateAdded <= '" + datetoforapproval.Text + "' AND RequestType='Others'", gridControlforappothers, gridViewforappothers);
        }

        private void gridViewforappothers_DoubleClick(object sender, EventArgs e)
        {
            showApproval();
        }

        private void cancelThisOrderToolStripMenuItem_Click(object sender, EventArgs e)
        {
            bool isexist = Database.checkifExist("SELECT TOP(1) 1 FROM DeliveryDetails WHERE PONumber='" + gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "PONumber").ToString() + "' AND isReturned=0");
            if(isexist)
            {
                XtraMessageBox.Show("This PO is Already Processed in your Commissary..To Cancel this Order, Please Delete All Item/s Processed in this PO.");
                return;
            }
            bool ok = HelperFunction.ConfirmDialog("Are you sure you want to Cancel this Order?..", "Cancel Purchase Order");
            if (ok)
            {
                string actionlogs = "CANCEL REJECTED REQUEST with PONumber=" + gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "PONumber").ToString() + " ";
                Database.ExecuteQuery("insert into HistoryLogs values('" + Login.Fullname + "','" + DateTime.Now.ToShortDateString() + "','"+ actionlogs + "','" + Login.assignedBranch + "')");
                Database.ExecuteQuery("Update PurchaseOrderSummary SET Status='REJECTED' WHERE PONumber='" + gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "PONumber").ToString() + "'", "Successfully Executed");
            }
            else
                return;
        }

        private void gridControl5_MouseUp(object sender, MouseEventArgs e)
        {
            
        }

        private void toolStripMenuItem3_Click(object sender, EventArgs e)
        {
            
        }
        void analyze(string spname,string pono,GridControl cont,GridView view)
        {
            SqlConnection con = Database.getConnection();
            con.Open();
            gridControl1.BeginUpdate();
            try
            {
                string sp = spname;
                SqlCommand com = new SqlCommand(sp, con);
                com.Parameters.AddWithValue("@parmpono", pono);
               
                com.CommandType = CommandType.StoredProcedure;
                com.CommandTimeout = 3600;
                com.CommandText = sp;
                SqlDataAdapter adapter = new SqlDataAdapter(com);
                DataTable table = new DataTable();
                view.Columns.Clear();
                cont.DataSource = null;
                adapter.Fill(table);
                cont.DataSource = table;
                view.BestFitColumns();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
            finally
            {
                gridControl1.EndUpdate();
                con.Close();
            }
        }

        void printSalesInvoice(GridView view)
        {
            string custname = "", custaddress = "", custterm = "",tinno="";
            custname = view.GetRowCellValue(view.FocusedRowHandle, "CustomerName").ToString();
            var row = Database.getMultipleQuery("Customers", "CustomerName='" + custname + "'", "CustomerAddress,Term,TinNo");
            custaddress = row["CustomerAddress"].ToString();//Database.getSingleQuery("Customers", "CustomerName='" + custname + "'", "CustomerAddress");
            custterm = row["Term"].ToString();// Database.getSingleQuery("Customers", "CustomerName='" + custname + "'", "Term");
            tinno = row["TinNo"].ToString();// Database.getSingleQuery("Customers", "CustomerName='" + custname + "'", "Term");
            refno1 = view.GetRowCellValue(view.FocusedRowHandle, "PONumber").ToString();
            Reporting.SalesInvoiceDexEx viewdet = new Reporting.SalesInvoiceDexEx();
            viewdet.Show();
            
            //analyze("spview_SalesInvoice", refno1, viewdet.gridControl4, viewdet.gridView4);
            if (GlobalCache.CompanyName == "JFC")
            {
                analyze("spview_SalesInvoiceJFC", refno1, viewdet.gridControl4, viewdet.gridView4);
            }
            else
            {
                analyze("spview_SalesInvoice", refno1, viewdet.gridControl4, viewdet.gridView4);
            }

            string compname = Database.getSingleQuery("CompanyProfile", "CompanyName='JFC'", "CompanyName");
            if (compname == "JFC")
            {
                Classes.DevXGridViewSettings.ShowFooterCountTotal(viewdet.gridView4, "Cnt"); //NEW
            }
            viewdet.txtinvoiceno.Text = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "InvoiceNo").ToString(); ;
            viewdet.txtpono.Text = refno1;
            viewdet.txtcusttin.Text = tinno;
            double vatablesales = 0.0, vatexemptsale = 0.0, vatamount = 0.0, totalsales = 0.0, lessvat = 0.0, netofvat = 0.0, amountdue = 0.0, addvat = 0.0, vatsales = 0.0, totalamountdue = 0.0;
            for (int i = 0; i <= viewdet.gridView4.RowCount - 1; i++)
            {
                if (Convert.ToBoolean(viewdet.gridView4.GetRowCellValue(i, "isVat").ToString()) == true)
                {
                    vatablesales += Convert.ToDouble(viewdet.gridView4.GetRowCellValue(i, "Amount").ToString());
                }
                if (Convert.ToBoolean(viewdet.gridView4.GetRowCellValue(i, "isVat").ToString()) == false)
                {
                    vatexemptsale += Convert.ToDouble(viewdet.gridView4.GetRowCellValue(i, "Amount").ToString());
                }
            }
            vatsales = Math.Round(vatablesales / 1.12, 2);
            vatamount = Math.Round(vatsales * 0.12, 2);
            totalsales = Math.Round(vatablesales + vatexemptsale, 2);
            lessvat = vatamount;
            netofvat = totalsales - vatamount;
            amountdue = netofvat;
            addvat = vatamount;
            totalamountdue = totalsales;

            viewdet.txtcustname.Text = custname;
            viewdet.txtcustaddress.Text = custaddress;
            viewdet.txtterm.Text = custterm;

            viewdet.txtvatablesale.Text = vatsales.ToString();
            viewdet.txtvatexemptsale.Text = vatexemptsale.ToString();
            viewdet.txtvatamount.Text = vatamount.ToString();
            viewdet.txttotalsales.Text = totalsales.ToString();
            viewdet.txtlessvat.Text = lessvat.ToString();
            viewdet.txtamountnetofvat.Text = netofvat.ToString();
            viewdet.txtamountdue.Text = amountdue.ToString();
            viewdet.txtaddvat.Text = addvat.ToString();
            viewdet.txttotalamountdue.Text = totalamountdue.ToString();
        }

        private void printSalesInvoiceToolStripMenuItem_Click(object sender, EventArgs e)
        {
            printSalesInvoice(gridView4);
        }

        private void creditMemoToolStripMenuItem_Click(object sender, EventArgs e)
        {
            
          
        }

        private void creditMemoToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            //view_CreditMemoDetails is DeliveryDetails Table
            refno1 = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "PONumber").ToString();
            //brcode = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "BranchCode").ToString();

            HOFormsDevEx.CreditMemoDevEx viewdet = new HOFormsDevEx.CreditMemoDevEx();
            viewdet.Show();
            viewdet.txtpono.Text = refno1;
          
            viewdet.txtstatus.Text = "FOR DELIVERY";
            Database.display("SELECT * FROM view_CreditMemoDetails WHERE PONumber='" + viewdet.txtpono.Text + "' ", viewdet.gridControl4, viewdet.gridView4);
        }


        void addCharges(GridView grdview)
        {
            refno1 = grdview.GetRowCellValue(grdview.FocusedRowHandle, "PONumber").ToString();
            bool isinvoiceupdate = Database.checkifExist("Select isInvoiceUpdate FROM DeliverySummary WHERE isInvoiceUpdate=1 and PONumber='" + refno1 + "'");
            bool isalreadyadded = Database.checkifExist("Select ChargeNo FROM ClientChargeSalesSummary WHERE PONumber='" + refno1 + "'");
            if (isalreadyadded == true)
            {
                bool confirm = HelperFunction.ConfirmDialog("The System found out that you already added charges in this transaction.. would like to add additional charges?", "Edit Charges");
                if (confirm == true)
                {
                    string custname = grdview.GetRowCellValue(grdview.FocusedRowHandle, "Customer").ToString();
                    string invoiceno = grdview.GetRowCellValue(grdview.FocusedRowHandle, "InvoiceNo").ToString();
                    string custid = Database.getSingleQuery("Customers", "CustomerName='" + custname + "'", "CustomerID");
                    var rowz = Database.getMultipleQuery("ClientChargeSalesSummary", "PONumber='" + refno1 + "'", "ChargeNo,ReferenceNo,Description");

                    string chargeNo = rowz["ChargeNo"].ToString();
                    string referenceno = rowz["ReferenceNo"].ToString();
                    string remarks = rowz["Description"].ToString();
                    HOFormsDevEx.ClientChargesDevExUpdate viewdet = new HOFormsDevEx.ClientChargesDevExUpdate();

                    viewdet.txtchargeno.Text = chargeNo.ToString();
                    viewdet.txtpono.Text = refno1;
                    viewdet.txtinvoiceno.Text = invoiceno;
                    viewdet.txtfreno.Text = referenceno;
                    viewdet.txtremarks.Text = remarks;
                    viewdet.groupControl1.Text = custid;
                    Database.display("Select * FROM view_ClientChargeSalesDetails WHERE ChargeNo='" + chargeNo + "'", viewdet.gridControl1, viewdet.gridView1);
                    viewdet.ShowDialog(this);
                    isupdated = true;
                }
                else
                {
                    return;
                }
                //XtraMessageBox.Show("You Already Add Charges of this Invoice..please review charges in confirm order!...");
                //return;
            }
            else if (isinvoiceupdate == true)
            {
                string custname = grdview.GetRowCellValue(grdview.FocusedRowHandle, "Customer").ToString();
                string invoiceno = grdview.GetRowCellValue(grdview.FocusedRowHandle, "InvoiceNo").ToString();
                string custid = Database.getSingleQuery("Customers", "CustomerName='" + custname + "'", "CustomerID");
                HOFormsDevEx.ClientChargesDevEx viewdet = new HOFormsDevEx.ClientChargesDevEx();
                int chargeNo = 0;
                chargeNo = IDGenerator.getIDNumber("ClientChargeSalesSummary", "ChargeNo is not null", "ChargeNo", 10000);
                viewdet.txtchargeno.Text = chargeNo.ToString();
                viewdet.txtpono.Text = refno1;
                viewdet.txtinvoiceno.Text = invoiceno;
                viewdet.groupControl1.Text = custid;
                viewdet.simpleButton1.Enabled = true;
                viewdet.ShowDialog(this);
            }
            else
            {
                XtraMessageBox.Show("You need to Update the Invoice Number First...please go to Print Delivery Receipt to Update Invoice!...");
                return;
            }

        }

        private void addChargesToolStripMenuItem_Click(object sender, EventArgs e)
        {
            //addCharges(gridView4); //NOT APPLICABLE FOR ENZO
            XtraMessageBox.Show("Not Applicable!..");
        }

        void printDebitMemo(GridView view)
        {
            refno1 = view.GetRowCellValue(view.FocusedRowHandle, "PONumber").ToString();
            brcode = view.GetRowCellValue(view.FocusedRowHandle, "BranchCode").ToString();

            HOFormsDevEx.DebitMemoDevEx viewdet = new HOFormsDevEx.DebitMemoDevEx();
            viewdet.Show();
            viewdet.txtpono.Text = refno1;
            viewdet.txtbrcode.Text = brcode;
            Database.display("SELECT Description,Amount FROM ClientChargeSalesDetails WHERE PONumber='" + viewdet.txtpono.Text + "' ", viewdet.gridControl4, viewdet.gridView4);
        }

        private void printDebitMemoChargesToolStripMenuItem_Click(object sender, EventArgs e)
        {
            //printDebitMemo(gridView4); //not applicable FOR ENZO
            XtraMessageBox.Show("Not Applicable");
        }

        void showItems(GridView view)
        {
            try
            {
                bool isInvoiceUpdated = Database.checkifExist("Select isInvoiceUpdate FROM DeliverySummary WHERE PONumber='" + view.GetRowCellValue(view.FocusedRowHandle, "PONumber").ToString() + "' and isInvoiceUpdate=1");
                if (isInvoiceUpdated == false)
                {
                    XtraMessageBox.Show("Invoice Number must be updated first..please go to Print Delivery Receipt Option!...");
                    return;
                }

                HOFormsDevEx.ClientShowItemsDevEx confi = new HOFormsDevEx.ClientShowItemsDevEx();
                confi.txtdevno.Text = view.GetRowCellValue(view.FocusedRowHandle, "DeliveryNo").ToString();
                confi.txtpono.Text = view.GetRowCellValue(view.FocusedRowHandle, "PONumber").ToString();
                confi.txteffectivitydate.Text = view.GetRowCellValue(view.FocusedRowHandle, "EffectivityDate").ToString();
                string custkey = Database.getSingleQuery("PurchaseOrderSummary", "PONumber='" + confi.txtpono.Text + "'", "Customer");
                confi.txtcustname.Text = Database.getSingleQuery("Customers", "CustomerKey='" + custkey + "'", "CustomerName");
                confi.txtpreparedby.Text = view.GetRowCellValue(view.FocusedRowHandle, "PreparedBy").ToString();
                confi.txtrefkey.Text = Database.getSingleQuery("DeliverySummary", "PONumber='" + confi.txtpono.Text + "'", "InvoiceNo");
                confi.txtstatus.Text = view.GetRowCellValue(view.FocusedRowHandle, "Status").ToString();
                confi.txttotalitem.Text = view.GetRowCellValue(view.FocusedRowHandle, "TotalItem").ToString();
                confi.txttotalqty.Text = view.GetRowCellValue(view.FocusedRowHandle, "TotalQtyDelivered").ToString();
                Database.display("Select * FROM funcview_ForDeliveryDetails('" + confi.txtpono.Text + "')", confi.gridControl2, confi.gridView2);


                Classes.DevXGridViewSettings.ShowFooterTotal(confi.gridView2, "QtyDelivered");
                Classes.DevXGridViewSettings.ShowFooterCountTotal(confi.gridView2, "ProductName");

                confi.gridView2.Columns["SeqNo"].Visible = false;
                confi.ShowDialog(this);
                if (HOFormsDevEx.ClientShowItemsDevEx.isdone == true)
                {
                    filtertab();
                    HOFormsDevEx.ClientShowItemsDevEx.isdone = false;
                    confi.Dispose();
                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }
        void showItemsReturned(GridView view)
        {
            try
            {
                bool isInvoiceUpdated = Database.checkifExist("Select isInvoiceUpdate FROM DeliverySummary WHERE PONumber='" + view.GetRowCellValue(view.FocusedRowHandle, "PONumber").ToString() + "' and isInvoiceUpdate=1");
                if (isInvoiceUpdated == false)
                {
                    XtraMessageBox.Show("Invoice Number must be updated first..please go to Print Delivery Receipt Option!...");
                    return;
                }

                HOFormsDevEx.ClientShowItemsDevEx confi = new HOFormsDevEx.ClientShowItemsDevEx();
              
                confi.txtpono.Text = view.GetRowCellValue(view.FocusedRowHandle, "PONumber").ToString();
                confi.txteffectivitydate.Text = view.GetRowCellValue(view.FocusedRowHandle, "EffectivityDate").ToString();
                string custkey = Database.getSingleQuery("PurchaseOrderSummary", "PONumber='" + confi.txtpono.Text + "'", "Customer");
                confi.txtcustname.Text = Database.getSingleQuery("Customers", "CustomerKey='" + custkey + "'", "CustomerName");
                confi.txtpreparedby.Text = view.GetRowCellValue(view.FocusedRowHandle, "PreparedBy").ToString();
                confi.txtrefkey.Text = Database.getSingleQuery("DeliverySummary", "PONumber='" + confi.txtpono.Text + "'", "InvoiceNo");
                confi.txtstatus.Text = "RETURNED";
                confi.txttotalitem.Text = view.GetRowCellValue(view.FocusedRowHandle, "TotalItemReturned").ToString();
                confi.txttotalqty.Text = view.GetRowCellValue(view.FocusedRowHandle, "TotalQtyReturned").ToString();
                Database.display("Select * FROM funcview_ForDeliveryDetails('" + confi.txtpono.Text + "')", confi.gridControl2, confi.gridView2);


                Classes.DevXGridViewSettings.ShowFooterTotal(confi.gridView2, "QtyDelivered");
                Classes.DevXGridViewSettings.ShowFooterCountTotal(confi.gridView2, "ProductName");

                confi.gridView2.Columns["SeqNo"].Visible = false;
                confi.ShowDialog(this);
                if (HOFormsDevEx.ClientShowItemsDevEx.isdone == true)
                {
                    filtertab();
                    HOFormsDevEx.ClientShowItemsDevEx.isdone = false;
                    confi.Dispose();
                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }

        private void showItemsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            showItems(gridView4);
        }

      
        private void button5_Click(object sender, EventArgs e)
        {
        }

        

        private void toolStripMenuItem4_Click(object sender, EventArgs e)
        {

        }

        private void gridControl2_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
            {
                contextMenuApprovedG2.Show(gridControl2, e.Location); 
            }
        }

        private void toolStripMenuItem1_Click(object sender, EventArgs e)
        {
            //this will show purchase order details
            menu = "approvedrequest";
            requestedBy = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "RequestedBy").ToString();
            refno = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "PONumber").ToString();
            stat = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "Status").ToString();
            GlobalVariables.ponumber = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "PONumber").ToString();
            POForApprovalDetails podetails = new POForApprovalDetails();
            podetails.FormClosed += new FormClosedEventHandler(podetails_FormClosed);
            podetails.Show();
            if (Convert.ToBoolean(Login.isglobalWarehouseOfficer) == true)
            {

                Database.display("SELECT * FROM view_PurchaseOrderDetails WHERE PONumber = '" + refno + "'", podetails.gridControl1, podetails.gridView1);
                podetails.txtpono.Text = refno;
                GridView view = podetails.gridControl1.FocusedView as GridView;
                view.SortInfo.ClearAndAddRange(new GridColumnSortInfo[] {
                        new GridColumnSortInfo(view.Columns["Category"],DevExpress.Data.ColumnSortOrder.Ascending)
                        }, 1);
                podetails.gridView1.Columns["SeqNo"].Visible = false;
                podetails.gridView1.ExpandAllGroups();
            }
            if (Convert.ToBoolean(Login.isglobalApprover) == true)
            {
             
                Database.display("SELECT * FROM view_PurchaseOrderDetails WHERE PONumber = '" + refno + "'", podetails.gridControl1, podetails.gridView1);
                podetails.txtpono.Text = refno;
                GridView view = podetails.gridControl1.FocusedView as GridView;
                view.SortInfo.ClearAndAddRange(new GridColumnSortInfo[] {
                        new GridColumnSortInfo(view.Columns["Category"],DevExpress.Data.ColumnSortOrder.Ascending)
                        }, 1);
                podetails.gridView1.Columns["SeqNo"].Visible = false;
                podetails.gridView1.ExpandAllGroups();
            }
            else
            {
                Database.display("SELECT SeqNo,PONumber,ProductName,Qty,Units FROM view_PurchaseOrderDetails WHERE PONumber = '" + refno + "' ", podetails.gridControl1, podetails.gridView1);
                podetails.txtpono.Text = refno;
                podetails.gridView1.Columns["SeqNo"].Visible = false;
            }
            GridGroupSummaryItem ite = new GridGroupSummaryItem();
            ite.FieldName = "Qty";
            ite.SummaryType = DevExpress.Data.SummaryItemType.Sum;
            ite.ShowInGroupColumnFooter = podetails.gridView1.Columns["Qty"];
            podetails.gridView1.GroupSummary.Add(ite);
        }

        private void gridView4_DoubleClick(object sender, EventArgs e)
        {
          
        }

        private void gridView2_DoubleClick(object sender, EventArgs e)
        {
            //this will show purchase order details
            menu = "approvedrequest";
            refno = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "PONumber").ToString();
            stat = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "Status").ToString();
            GlobalVariables.ponumber = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "PONumber").ToString();
            POForApprovalDetails podetails = new POForApprovalDetails();
            podetails.FormClosed += new FormClosedEventHandler(podetails_FormClosed);
            podetails.Show();
            podetails.txtpono.Text = refno;
            if (Convert.ToBoolean(Login.isglobalWarehouseOfficer).Equals(true))
            {
                Database.display("SELECT * FROM view_PurchaseOrderDetails WHERE PONumber = '" + refno + "'", podetails.gridControl1, podetails.gridView1);
                GridView view = podetails.gridControl1.FocusedView as GridView;
                view.SortInfo.ClearAndAddRange(new GridColumnSortInfo[] {
                new GridColumnSortInfo(view.Columns["Category"],DevExpress.Data.ColumnSortOrder.Ascending)
                }, 1);
                podetails.gridView1.Columns["SeqNo"].Visible = false;
                podetails.gridView1.ExpandAllGroups();
            }
            if (Convert.ToBoolean(Login.isglobalApprover).Equals(true))
            {
                Database.display("SELECT * FROM view_PurchaseOrderDetails WHERE PONumber = '" + refno + "'", podetails.gridControl1, podetails.gridView1);
                GridView view = podetails.gridControl1.FocusedView as GridView;
                view.SortInfo.ClearAndAddRange(new GridColumnSortInfo[] {
                new GridColumnSortInfo(view.Columns["Category"],DevExpress.Data.ColumnSortOrder.Ascending)
                }, 1);
                podetails.gridView1.Columns["SeqNo"].Visible = false;
                podetails.gridView1.ExpandAllGroups();
            }
            else
            {
                Database.display("SELECT PONumber,ProductName,Qty,Units FROM view_PurchaseOrderDetails WHERE PONumber = '" + refno + "' ", podetails.gridControl1, podetails.gridView1);
                podetails.gridView1.Columns["SeqNo"].Visible = false;
            }
            GridGroupSummaryItem ite = new GridGroupSummaryItem();
            ite.FieldName = "Qty";
            ite.SummaryType = DevExpress.Data.SummaryItemType.Sum;
            ite.ShowInGroupColumnFooter = podetails.gridView1.Columns["Qty"];
            podetails.gridView1.GroupSummary.Add(ite);
            podetails.gridView1.Focus();
        }

        void rowstyle(object sender, RowStyleEventArgs e)
        {
            GridView View = sender as GridView;
            if (e.RowHandle >= 0)
            {
                string category = View.GetRowCellDisplayText(e.RowHandle, View.Columns["OrderType"]);
                if (category != "MAIN")
                {
                    e.Appearance.BackColor = Color.Salmon;
                    e.Appearance.BackColor2 = Color.SeaShell;
                    e.HighPriority = true;
                }
            }
        }

        private void gridView4_RowStyle(object sender, RowStyleEventArgs e)
        {
            rowstyle(sender, e);
        }

        private void gridView5_RowStyle(object sender, RowStyleEventArgs e)
        {
            rowstyle(sender, e);
            if (e.HighPriority || e.RowHandle < 0)
                return;

            GridView view = sender as GridView;
            bool hasCreditMemo = Convert.ToBoolean(view.GetRowCellValue(e.RowHandle, "HasCreditMemo"));
            bool hasReturnOrder = Convert.ToBoolean(view.GetRowCellValue(e.RowHandle, "HasReturnOrder"));
            if (hasCreditMemo || hasReturnOrder)
            {
                e.Appearance.BackColor = Color.Gold;
                e.Appearance.BackColor2 = Color.LightYellow;
                e.HighPriority = true;
            }
        }

        private void gridView1_RowStyle(object sender, RowStyleEventArgs e)
        {
            rowstyle(sender, e);
        }

        private void btnForApprovalSalesOrder_Click(object sender, EventArgs e)
        {
            Database.display("SELECT * FROM view_POSummary WHERE Status='FOR APPROVAL' and EffectivityDate >= '" + datefromforapproval.Text + "' and EffectivityDate < DATEADD(DAY,1,'" + datetoforapproval.Text + "')  AND BranchCode='" + Login.assignedBranch + "'", gridControl1, gridView1);
        }

      
        private void btnApprovedSalesReq_Click(object sender, EventArgs e)
        {
            Database.display("SELECT * FROM view_POSummary WHERE Status='APPROVED' and EffectivityDate >= '" + datefromapproved.Text + "' and EffectivityDate < DATEADD(DAY,1,'" + datetoapproved.Text + "') AND BranchCode='" + Login.assignedBranch + "' ORDER BY DateAdded DESC", gridControl2, gridView2);
        }


        private void simpleButton1_Click(object sender, EventArgs e)
        {
            Database.display("SELECT * FROM view_POSummary WHERE Status='REJECTED' and EffectivityDate >= '" + datefromrejected.Text + "' and EffectivityDate < DATEADD(DAY,1,'" + datefromrejected.Text + "') AND BranchCode='" + Login.assignedBranch + "'", gridControl3, gridView3);
        }

        private void btnForDelivSalesOrder_Click(object sender, EventArgs e)
        {
            //WHERE DateAdded >= @DateFrom
            //          AND DateAdded<DATEADD(day,1,@DateTo)
            //view_OrdersForDelivery  is combination of 2 views view_ForDelivery(PurchaseOrderSummary,DeliverySummary,Customers) and view_DeliveryReciept(DeliveryDetails)
            Database.display("SELECT * FROM view_OrdersForDelivery WHERE Status='FOR DELIVERY' and EffectivityDate >= '" + datefromdelivered.Text + "' and EffectivityDate < DATEADD(day,1,'" + datetodelivered.Text + "')  ORDER BY PONumber", gridControl4, gridView4);
            Classes.DevXGridViewSettings.ShowFooterCountTotal(gridView4, "DeliveryNo");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView4, "TotalItem");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView4, "TotalQtyDelivered");
        }

       

        private void btnDeliveredSalesOrder_Click(object sender, EventArgs e)
        {
            loadDeliveredSalesOrder();
        }

        private void btnPaidSalesOrder_Click(object sender, EventArgs e)
        {
            loadPaidSalesOrder();
        }

    
        private void tabMain_SelectedPageChanged(object sender, DevExpress.XtraTab.TabPageChangedEventArgs e)
        {
            filtertab();
        }

        void exporttoexcel(GridView view,string title)
        {
            if (view.RowCount == 0)
            {
                XtraMessageBox.Show("No Data to Import!..");
                return;
            }
            else
            {
                
                string filepath = "C:\\MyFiles\\";
                Classes.Utilities.createDirectoryFolder(filepath);
                string filename = title + ".xls";
                string file = filepath + filename;
                view.ExportToXls(file);
                XtraMessageBox.Show("Successfully Exported.. Please Check your Drive C://MyFiles/folder");
            }
        }
        
        private void btnforapprovalsalesorderexcel_Click(object sender, EventArgs e)
        {
            string filename = "FORAPPROVAL_SALESORDER" + DateTime.Now.ToShortDateString().Replace(@"\","-");
            exporttoexcel(gridView1, filename);
        }

        private void btnapprovedreqsalesorderexcel_Click(object sender, EventArgs e)
        {
            string filename = "APPROVED_SALESORDER" + DateTime.Now.ToShortDateString().Replace(@"\","-");
            exporttoexcel(gridView2, filename);
        }

      
        private void btnrejectedsalesorderexcel_Click(object sender, EventArgs e)
        {
            string filename = "REJECTED_SALESORDER" + DateTime.Now.ToShortDateString().Replace(@"\","-");
            exporttoexcel(gridView3, filename);
        }

       
        private void btnfordelivsalesorderexcel_Click(object sender, EventArgs e)
        {
            string filename = "FORDELIVERY_SALESORDER" + DateTime.Now.ToShortDateString().Replace(@"\", "-");
            exporttoexcel(gridView4, filename);
        }

        private void btndeliveredsalesorderexcel_Click(object sender, EventArgs e)
        {
            string filename = "DELIVERED_SALESORDER" + DateTime.Now.ToShortDateString().Replace(@"\", "-");
            exporttoexcel(gridView5, filename);
        }

     
        private void gridControl4_MouseUp_1(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
            {
                contextMenuForDelivery.Show(gridControl4, e.Location);
                //contextMenuForDelivery.Items[1].Visible = false;
                //contextMenuForDelivery.Items[2].Visible = false;
            }
        }

        private void gridControl5_MouseUp_1(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStripDelivered.Show(gridControl5, e.Location);
        }

        private void toolStripMenuItem12_Click(object sender, EventArgs e)
        {
            addCharges(gridView5);
        }

        private void toolStripMenuItem2_Click(object sender, EventArgs e)
        {

        }

        private void btnReturnedGenerate_Click(object sender, EventArgs e)
        {
            Database.display(
               "SELECT v.* FROM [view_ReturnedSummary] v " +
               "WHERE v.DateAdded >= '" + dateFromReturned.Text + "' and v.DateAdded < DATEADD(DAY,1,'" + dateToReturned.Text + "') AND v.BranchCode='" + Login.assignedBranch + "' " +
               "ORDER BY v.PONumber", gridControlReturned, gridViewReturned);
        }

        private void gridControlReturned_MouseUp(object sender, MouseEventArgs e)
        {
            if(e.Button == MouseButtons.Right)
                contextMenuStripReturned.Show(gridControlReturned,e.Location);
        }

        private void toolStripMenuItem21_Click(object sender, EventArgs e)
        {
            stat = "RETURNED";
            showItemsReturned(gridViewReturned);
        }

        private void toolStripMenuItem13_Click(object sender, EventArgs e)
        {
            devno = gridView5.GetRowCellValue(gridView5.FocusedRowHandle, "DeliveryNo").ToString();
            refno1 = gridView5.GetRowCellValue(gridView5.FocusedRowHandle, "PONumber").ToString();
            invoiceno = gridView5.GetRowCellValue(gridView5.FocusedRowHandle, "PONumber").ToString();
            Orders.ReturnSalesOrder salesret = new Orders.ReturnSalesOrder();
            salesret.Show();
            Database.display("SELECT * FROM view_BranchOrderDetails WHERE PONumber='" + refno1 + "' ", salesret.gridControl1, salesret.gridView1);
            salesret.txtpono.Text = refno1;
            salesret.txtdevno.Text = devno;
            salesret.txtbrcode.Text = gridView5.GetRowCellValue(gridView5.FocusedRowHandle, "BranchCode").ToString();
            salesret.txtstatus.Text = "DELIVERED";
        }

        private void toolStripMenuItem14_Click(object sender, EventArgs e)
        {
            refno1 = gridView5.GetRowCellValue(gridView5.FocusedRowHandle, "PONumber").ToString();
            brcode = gridView5.GetRowCellValue(gridView5.FocusedRowHandle, "BranchCode").ToString();

            HOFormsDevEx.CreditMemoDevEx viewdet = new HOFormsDevEx.CreditMemoDevEx();
            viewdet.Show();
            viewdet.txtpono.Text = refno1;
           
            viewdet.txtstatus.Text = "DELIVERED";
            Database.display("SELECT * FROM view_CreditMemoDetails WHERE PONumber='" + viewdet.txtpono.Text + "' ", viewdet.gridControl4, viewdet.gridView4);
        }

        private void toolStripMenuItem16_Click(object sender, EventArgs e)
        {
            printSalesInvoice(gridView5);
        }

        private void toolStripMenuItem17_Click(object sender, EventArgs e)
        {
            printDebitMemo(gridView5);
        }

        private void toolStripMenuItem18_Click(object sender, EventArgs e)
        {
            stat = "DELIVERED";
            showItems(gridView5);
        }

        private void gridControlDelivSts_MouseUp(object sender, MouseEventArgs e)
        {

        }

        private void toolStripMenuItem7_Click(object sender, EventArgs e)
        {

        }

        //private void gridControl2_DoubleClick(object sender, EventArgs e)
        //{
        //    POForApprovalDetails podetails = new POForApprovalDetails();
        //    podetails.FormClosed += new FormClosedEventHandler(podetails_FormClosed);
        //    podetails.Show();
        //}
    }
}