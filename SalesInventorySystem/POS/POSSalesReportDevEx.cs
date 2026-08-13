using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Text;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid;

namespace SalesInventorySystem.POS
{
    public partial class POSSalesReportDevEx : DevExpress.XtraEditors.XtraForm
    {
        object custkey = null;
        object brcodesummary = null, brcodedetails = null;
        public POSSalesReportDevEx()
        {
            InitializeComponent();
            // Belt-and-suspenders with the explicit ExpandAllGroups() call in
            // LoadCustomerCashReceipts() -- matches Accounting/AgingReports.cs, which sets this
            // once at construction so newly created groups always start expanded regardless of
            // exactly when grouping is applied relative to the grid's own layout pass.
            gridView1.OptionsBehavior.AutoExpandAllGroups = true;

            // Highlight the group footer (the ControlNo totals row) so the per-group summary
            // stands out from the data rows -- same GroupFooter styling approach as
            // HOForms/POSTransactions.cs, just with a warmer accent to read as a "totals" band.
            gridView1.Appearance.GroupFooter.Font = new Font("Tahoma", 9.75F, FontStyle.Bold);
            gridView1.Appearance.GroupFooter.ForeColor = Color.FromArgb(102, 60, 0);
            gridView1.Appearance.GroupFooter.BackColor = Color.FromArgb(255, 244, 214);
            gridView1.Appearance.GroupFooter.Options.UseFont = true;
            gridView1.Appearance.GroupFooter.Options.UseForeColor = true;
            gridView1.Appearance.GroupFooter.Options.UseBackColor = true;
        }
        private void LoadCustomerSalesHistory(string branchCode)
        {
            string sql = $@"
                SELECT *
                FROM dbo.funcview_CustomerSalesHistory(
                    '{branchCode}',
                    '{datefromsalessum.Value.Date:yyyy-MM-dd}',
                    '{datetosalessum.Value.Date:yyyy-MM-dd}'
                )
                ORDER BY CustomerName";

            Database.display(sql, gridControl2, gridView2);
        }
        private void LoadCustomerSalesHistoryDetails(string branchCode)
        {
            string sql = $@"
                SELECT *
                FROM dbo.funcview_CustomerSalesHistoryDetails(
                    '{branchCode}',
                    '{datefromsalessum.Value.Date:yyyy-MM-dd}',
                    '{datetosalessum.Value.Date:yyyy-MM-dd}'
                )
                ORDER BY CustomerName";

            Database.display(sql, gridControl2, gridView2);
        }
        private void LoadCustomerCashReceipts()
        {
            string sql = $@"
                SELECT *
                FROM dbo.funcview_CustomerCashReceipts(
                    '{datefromcashreceipts.Value.Date:yyyy-MM-dd}',
                    '{datetocashreceipts.Value.Date:yyyy-MM-dd}'
                )";
                //ORDER BY CustomerName";

            Database.display(sql, gridControl1, gridView1);

            // Group by ControlNo, expanded by default, with per-group totals -- amounts come back
            // as numeric decimal now (see SQL/2026-08-07_CustomerCashReceipts_NumericAmounts.sql;
            // the prior FORMAT()-string columns couldn't be summed).
            gridView1.BeginSort();
            gridView1.ClearGrouping();
            if (gridView1.Columns["ControlNo"] != null)
                gridView1.Columns["ControlNo"].GroupIndex = 0;
            gridView1.EndSort();
            gridView1.ExpandAllGroups();

            gridView1.GroupSummary.Clear();
            string[] amountColumns = { "TotalAmount", "InvoicePaymentAmount", "EwtAmount", "DiscountAmount" };
            foreach (string col in amountColumns)
            {
                Classes.DevXGridViewSettings.ShowFooterTotal(gridView1, col);

                // ShowFooterTotal formats the bottom-of-grid footer panel ("{0:n2}") and the data
                // rows pick up the column DisplayFormat set below, but the GridGroupSummaryItem it
                // adds to GroupSummary (the per-ControlNo group footer -- the one that actually
                // matters here) has no DisplayFormat of its own and does NOT fall back to the
                // column's -- it has to be set directly on that summary item.
                gridView1.Columns[col].DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                gridView1.Columns[col].DisplayFormat.FormatString = "n2";

                foreach (GridGroupSummaryItem item in gridView1.GroupSummary)
                {
                    if (item.FieldName == col)
                        item.DisplayFormat = "{0:n2}";
                }
            }
        }
        private void LoadCustomerSalesJournal()
        {
            string sql = $@"
                SELECT *
                FROM dbo.funcview_CustomerSalesJournal(
                    '{datefromcashreceipts.Value.Date:yyyy-MM-dd}',
                    '{datetocashreceipts.Value.Date:yyyy-MM-dd}'
                )";
            //ORDER BY CustomerName";

            Database.display(sql, gridControl1, gridView1);
        }
        private void LoadSalesData(string viewName, string dateColumn, string branchCode)
        {
            string sql = $@"
                SELECT *
                FROM {viewName}
                WHERE BranchCode = '{branchCode}'
                AND {dateColumn} >= '{datefromsalessum.Value.Date:yyyy-MM-dd}'
                AND {dateColumn} < DATEADD(DAY,1,'{datetosalessum.Value.Date:yyyy-MM-dd}')
                ORDER BY ReferenceNo";

            Database.display(sql, gridControl2, gridView2);
        }
        private string GetBranchCode(string selectedBranch)
        {
            return Login.assignedBranch == "888"
                ? selectedBranch
                : Login.assignedBranch;
        }

        private void btnsalestransummary_Click(object sender, EventArgs e)
        {

            try
            {
                gridView2.BeginDataUpdate();

                //gridView2.GroupSummary.Clear();
                gridView2.Columns.Clear();

                string branchCode =
                    chckboxAllBranch.Checked
                    ? "ALL"
                    : (Login.assignedBranch == "888"
                        ? brcodesummary.ToString()
                        : Login.assignedBranch);

                if (radbuttonsummary.Checked)
                {
                    LoadCustomerSalesHistory(branchCode);
                }
                else
                {
                    LoadCustomerSalesHistoryDetails(branchCode);
                }

                gridView2.BestFitColumns();

                //gridView2.Columns["SalesPerson"].GroupIndex = 0;
                //gridView2.Columns["CustomerName"].GroupIndex = 1;

                //gridView2.ExpandAllGroups();
                //gridView2.OptionsBehavior.AutoExpandAllGroups = true;
                //gridView2.ExpandAllGroups();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(
                    ex.Message,
                    "Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            finally
            {
                gridView2.EndDataUpdate();
            }

        }
        //private void btnsalestransummary_Click(object sender, EventArgs e)
        //{
        //    if(radbuttonsummary.Checked == true)
        //    {
        //        if (Login.assignedBranch != "888")
        //        {
        //            Database.display("SELECT * FROM view_batchTransactionSummary " +
        //                  "WHERE BranchCode='" + Login.assignedBranch + "' " +
        //                  "AND CAST(TransDate as Date) >= '" + datefromsalessum.Text + "' AND CAST(TransDate as Date) <= '" + datetosalessum.Text + "' ORDER BY ReferenceNo", gridControl2, gridView2);
        //        }
        //        else
        //        {
        //            Database.display("SELECT * FROM view_batchTransactionSummary " +
        //                   $"WHERE BranchCode='{brcodesummary.ToString()}' " +
        //                   "AND CAST(TransDate as Date) >= '" + datefromsalessum.Text + "' AND CAST(TransDate as Date) <= '" + datetosalessum.Text + "' ORDER BY ReferenceNo", gridControl2, gridView2);
        //        }
        //    }
        //    else if(radbuttondetails.Checked == true)
        //    { 
        //        gridControl2.BeginUpdate();
        //        gridView2.GroupSummary.Clear();
        //        gridView2.Columns.Clear();
        //        if (Login.assignedBranch != "888")
        //        {
        //            Database.display("SELECT * FROM view_detailTransactionHistory " +
        //             "WHERE BranchCode='" + Login.assignedBranch + "' " +
        //             "AND CAST(DateOrder as date) >= '" + datefromsalessum.Text + "' AND CAST(DateOrder as date) <= '" + datetosalessum.Text + "' ORDER BY ReferenceNo", gridControl2, gridView2);
        //        }
        //        else
        //        {
        //            Database.display("SELECT * FROM view_detailTransactionHistory " +
        //         $"WHERE BranchCode='{brcodedetails.ToString()}' " +
        //         "AND CAST(DateOrder as date) >= '" + datefromsalessum.Text + "' AND CAST(DateOrder as date) <= '" + datetosalessum.Text + "' ORDER BY ReferenceNo", gridControl2, gridView2);
        //        }
        //        Classes.DevXGridViewSettings.ShowFooterCountTotal(gridView2, "BranchCode");
        //        Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "QtySold");
        //        Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "TotalAmount");
        //        gridControl2.EndUpdate();
        //    }

        //}


        private void POSSalesReportDevEx_Load(object sender, EventArgs e)
        {
            DateTime now = DateTime.Now;
            DateTime date = new DateTime(now.Year, now.Month, 1);

            var now2 = DateTime.Now;
            //var startOfMonth = new DateTime(now2.Year, now2.Month, 1);
            var DaysInMonth = DateTime.DaysInMonth(now2.Year, now2.Month);
            var lastDay = new DateTime(now2.Year, now2.Month, DaysInMonth);


            datefromsalessum.Text = date.ToShortDateString();
            datetosalessum.Text = lastDay.ToShortDateString();

            
            populate();
        }

        void populate()
        {
            if(Login.assignedBranch != "888")
            {
                txtbranchsummary.Visible = false;
               
            }
            else
            {
                Database.displaySearchlookupEdit("Select distinct BranchCode,BranchName FROM Branches Order By BranchCode", txtbranchsummary, "BranchName", "BranchName");
             }
            Database.displaySearchlookupEdit("SELECT CustomerKey,CustomerID,CustomerName From dbo.Customers", searchLookUpEdit1,"CustomerName", "CustomerName");
        }

        private void searchLookUpEdit1_EditValueChanged(object sender, EventArgs e)
        {
            custkey = SearchLookUpClass.getSingleValue(searchLookUpEdit1, "CustomerKey");
        }

        private void btnTransactionPayment_Click(object sender, EventArgs e)
        {
            var rowz = Database.getMultipleQuery("SELECT * FROM dbo.Customers WHERE CustomerKey='" + custkey.ToString() + "'", "CustomerKey,CustomerID ,CustomerName,CustomerEmail,CustomerContactNo,CustomerAddress,CustomerBirthDate,CustomerCreditLimit,BranchCode,Term,isActive,DateAdded,AddedBy,UpdatedBy,AccountOfficer,TinNo");
            string CustomerKey = rowz["CustomerKey"].ToString();
            string CustomerID = rowz["CustomerID"].ToString();
            string CustomerName = rowz["CustomerName"].ToString();
            string CustomerEmail = rowz["CustomerEmail"].ToString();
            string CustomerContactNo = rowz["CustomerContactNo"].ToString();
            string CustomerAddress = rowz["CustomerAddress"].ToString();
            string CustomerBirthDate = rowz["CustomerBirthDate"].ToString();
            string CustomerCreditLimit = rowz["CustomerCreditLimit"].ToString();
            string BranchCode = rowz["BranchCode"].ToString();
            string Term = rowz["Term"].ToString();
            string isActive = rowz["isActive"].ToString();
            string DateAdded = rowz["DateAdded"].ToString();
            string AddedBy = rowz["AddedBy"].ToString();
            string UpdatedBy = rowz["UpdatedBy"].ToString();
            string AccountOfficer = rowz["AccountOfficer"].ToString();
            string TinNo = rowz["TinNo"].ToString();
            txtid.Text = CustomerKey;
            txtname.Text = CustomerName;
            txtcontactno.Text = CustomerContactNo;
            txtaddress.Text = CustomerAddress;
            getData();
        }

        void getData()
        {
            var rowz = Database.getMultipleQuery($"SELECT * FROM func_CustomerSalesBoard('{custkey.ToString()}','{Environment.MachineName}') ", "TotalInvoice,SubTotal,TotalAmount,Average");
            string TotalInvoice = rowz["TotalInvoice"].ToString();
            string SubTotal = rowz["SubTotal"].ToString();
            string TotalAmount = rowz["TotalAmount"].ToString();
            string Average = rowz["Average"].ToString();
            txtavg.Text = Average;
            txttotinvoice.Text = TotalInvoice;
            txttotasalesb4tax.Text = SubTotal;
            txttotsalesnet.Text = TotalAmount;
            Database.display("SELECT a.DateOrder,a.ReferenceNo,a.Category,a.Description,a.QtySold,a.TotalAmount " +
                "FROM dbo.view_detailTransactionHistory a with(nolock) LEFT OUTER JOIN BatchSalesSummary b with(nolock) " +
                "ON a.ReferenceNo=b.ReferenceNo WHERE b.CustomerNo='" + custkey.ToString() + "' ORDER BY ReferenceNo DESC", gridControl3, gridView3);
        }

        private void txtbranchsummary_EditValueChanged(object sender, EventArgs e)
        {
            brcodesummary = SearchLookUpClass.getSingleValue(txtbranchsummary, "BranchCode");
        }

        

        private void btnforapprovalstsexcel_Click(object sender, EventArgs e)
        {
            string filename = "HRI_SalesTransactionSummary" + DateTime.Now.ToString("yyyyMMdd_HHmmss");
            HelperFunction.exporttoexcel(gridView2, filename);
        }

        private void simpleButton2_Click(object sender, EventArgs e)
        {
            if(radcashreceipts.Checked==true)
            {
                populateCashReceiptsBook();
            }
            else if(radsalesjournal.Checked==true)
            {
                populateSalesJournal();
            }
        }

        void populateCashReceiptsBook()
        {
            try
            {
                gridView1.BeginDataUpdate();

               
                gridView1.Columns.Clear();
                LoadCustomerCashReceipts();
                
                gridView1.BestFitColumns();
                gridView1.ExpandAllGroups();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(
                    ex.Message,
                    "Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            finally
            {
                gridView1.EndDataUpdate();
            }
        }
        void populateSalesJournal()
        {
            try
            {
                gridView1.BeginDataUpdate();


                gridView1.Columns.Clear();
                LoadCustomerSalesJournal();

                gridView1.BestFitColumns();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(
                    ex.Message,
                    "Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            finally
            {
                gridView1.EndDataUpdate();
            }
        }

        private void label15_Click(object sender, EventArgs e)
        {
            
        }
    }
}