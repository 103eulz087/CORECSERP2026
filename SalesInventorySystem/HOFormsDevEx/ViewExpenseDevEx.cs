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
using DevExpress.XtraSplashScreen;
using System.Data.SqlClient;
using System.Threading;
using SalesInventorySystem.AccountingDevEx;
using SalesInventorySystem.Classes;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class ViewExpenseDevEx : DevExpress.XtraEditors.XtraForm
    {
        string action = "", reason="";
        public ViewExpenseDevEx()
        {
            InitializeComponent();
        }

        private void gridControl2_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStripForApproval.Show(gridControl2,e.Location);
        }

        private void ViewExpenseDevEx_Load(object sender, EventArgs e)
        {
            DateTime today = DateTime.Now;
            //txtdatefromforapproval.Text = HelperFunction.GetPreviousMonthSameDay(today).ToShortDateString();
            //txtdatetoforapproval.Text = today.ToShortDateString();

            HelperFunction.SetQuarterDateRange(txtdatefromforapproval, txtdatetoforapproval);
            HelperFunction.SetQuarterDateRange(txtdatefrom, txtdateto);
            HelperFunction.SetQuarterDateRange(dateFromCancelled, dateToCancelled);
            HelperFunction.SetQuarterDateRange(dateFromPaid, dateToPaid);

            //txtdatefrom.Text = HelperFunction.GetPreviousMonthSameDay(today).ToShortDateString();
            //txtdateto.Text = today.ToShortDateString();


            //dateFromCancelled.Text = HelperFunction.GetPreviousMonthSameDay(today).ToShortDateString();
            //dateToCancelled.Text = today.ToShortDateString();

            //dateFromPaid.Text = HelperFunction.GetPreviousMonthSameDay(today).ToShortDateString();
            //dateToPaid.Text = today.ToShortDateString();

            gridControl1.ViewRegistered += GridControl1_ViewRegistered;
            //filtertab();
        }
        private void GridControl1_ViewRegistered(object sender,DevExpress.XtraGrid.ViewOperationEventArgs e)
        {
            GridView view = e.View as GridView;

            if (view == null)
                return;

            view.CellValueChanged -= DetailView_CellValueChanged;
            view.CellValueChanged += DetailView_CellValueChanged;
        }
        private void DetailView_CellValueChanged(
                    object sender,
                    DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            GridView view = sender as GridView;

            // Only process editable columns
            if (e.Column.FieldName != "Debit" &&
                e.Column.FieldName != "Credit")
                return;

            string ticketNumber = view.GetRowCellValue(
                e.RowHandle,
                "TicketNumber").ToString();
            string accountCode = view.GetRowCellValue(
                e.RowHandle,
                "AccountCode").ToString();

            decimal value = Convert.ToDecimal(e.Value);

            try
            {
                using (SqlConnection con = Database.getConnection())
                {
                    con.Open();

                    string query = $@"
                UPDATE TicketDetails
                SET [{e.Column.FieldName}] = @Value
                WHERE TicketNumber = @TicketNumber and AccountCode=@AccountCode";

                    using (SqlCommand cmd = new SqlCommand(query, con))
                    {
                        cmd.Parameters.AddWithValue("@Value", value);
                        cmd.Parameters.AddWithValue("@TicketNumber", ticketNumber);
                        cmd.Parameters.AddWithValue("@AccountCode", accountCode);

                        cmd.ExecuteNonQuery();
                    }
                }
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message);
            }
        }


        private void showDetailsToolStripMenuItem_Click(object sender, EventArgs e)
        {
          
            displayDetails();
        }

        void displayDetails()
        {
            string invoiceno = "", refno = "",suppid="";
            ViewExpenseDetailsDevEx viewdetdevex = new ViewExpenseDetailsDevEx();
            if (Convert.ToBoolean(Login.isglobalBranchOfficer) == true)
            {
                viewdetdevex.btnApproved.Visible = true;
                viewdetdevex.btncancel.Visible = true;
            }
            else if (Convert.ToBoolean(Login.isglobalBranchOfficer) == false)
            {
                viewdetdevex.btnApproved.Visible = false;
                viewdetdevex.btncancel.Visible = false;
            }

            if (action == "APPROVED")
            {
                invoiceno= gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "InvoiceNo").ToString();
                refno = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "ReferenceNumber").ToString();
                suppid = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SupplierID").ToString();
               
              
                viewdetdevex.txtinvoiceno.Text = invoiceno;
                viewdetdevex.txtrefno.Text = refno;
                viewdetdevex.txtsuppid.Text = suppid;
                viewdetdevex.btnApproved.Visible = false;
                viewdetdevex.btncancel.Visible = false;
            }
            else if (action == "CANCELLED")
            {
                invoiceno = gridViewCancelled.GetRowCellValue(gridViewCancelled.FocusedRowHandle, "InvoiceNo").ToString();
                refno = gridViewCancelled.GetRowCellValue(gridViewCancelled.FocusedRowHandle, "ReferenceNumber").ToString();
                suppid = gridViewCancelled.GetRowCellValue(gridViewCancelled.FocusedRowHandle, "SupplierID").ToString();
             
                viewdetdevex.txtinvoiceno.Text = invoiceno;
                viewdetdevex.txtrefno.Text = refno;
                viewdetdevex.txtsuppid.Text = suppid;
                viewdetdevex.btnApproved.Visible = false;
                viewdetdevex.btncancel.Visible = false;
            }
            else if (action == "PAID")
            {
                invoiceno = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "InvoiceNo").ToString();
                refno = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "ReferenceNumber").ToString();
                suppid = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "SupplierID").ToString();

                viewdetdevex.txtinvoiceno.Text = invoiceno;
                viewdetdevex.txtrefno.Text = refno;
                viewdetdevex.txtsuppid.Text = suppid;
                viewdetdevex.btnApproved.Visible = false;
                viewdetdevex.btncancel.Visible = false;
            }
            else
            {
                invoiceno = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "InvoiceNo").ToString();
                refno = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "ReferenceNumber").ToString();
                suppid = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "SupplierID").ToString();

                viewdetdevex.txtinvoiceno.Text = invoiceno;
                viewdetdevex.txtrefno.Text = refno;
                viewdetdevex.txtsuppid.Text = suppid;

            }

            Database.display($"SELECT * FROM dbo.view_ExpenseMasterDetails with(nolock) " +
               $"WHERE ReferenceNumber='{refno}' " +
               $"AND InvoiceNo='{invoiceno}' ", viewdetdevex.gridControl2, viewdetdevex.gridView2);
            //Database.display($"SELECT * FROM dbo.ExpenseDetails " +
            //    $"WHERE ReferenceNumber='{refno}' " +
            //    $"AND InvoiceNo='{invoiceno}' ", viewdetdevex.gridControl2, viewdetdevex.gridView2);

            Classes.DevXGridViewSettings.ShowFooterTotal(viewdetdevex.gridView2, "Amount");
            viewdetdevex.ShowDialog(this);
            if (ViewExpenseDetailsDevEx.isdone == true)
            {
                //filtertab();
                ViewExpenseDetailsDevEx.isdone = false;
                viewdetdevex.Dispose();

            }
        }

        private void xtraTabControl1_SelectedPageChanged(object sender, DevExpress.XtraTab.TabPageChangedEventArgs e)
        {
            //filtertab();
        }

        private void gridControl1_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStripApproved.Show(gridControl1, e.Location);
        }

        private void gridControl3_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStripCancelled.Show(gridControlCancelled, e.Location);
        }

        private void toolStripMenuItem1_Click(object sender, EventArgs e)
        {
            action = "APPROVED";
            displayDetails();
        }

        private void toolStripMenuItem2_Click(object sender, EventArgs e)
        {
            action = "CANCELLED";
            displayDetails();
        }

        private void LoadExpenseSummaryByStatus(
            string status,
            string fromDateText,
            string toDateText,
            DevExpress.XtraGrid.GridControl grid,
            DevExpress.XtraGrid.Views.Grid.GridView view)
        {
            DateTime fromDate = Convert.ToDateTime(fromDateText).Date;
            DateTime toDateExclusive = Convert.ToDateTime(toDateText).Date.AddDays(1);

            try
            {
                Cursor.Current = Cursors.WaitCursor;
                this.UseWaitCursor = true;

                using (SqlConnection con = Database.getConnection())
                using (SqlCommand cmd = new SqlCommand(@"
            SELECT *
            FROM dbo.view_ExpenseSummary
            WHERE Status = @status
              AND ExpenseDate >= @fromDate
              AND ExpenseDate <  @toDateExclusive
            ORDER BY ExpenseDate DESC", con))
                {
                    cmd.Parameters.Add("@status", SqlDbType.VarChar, 50).Value = status;
                    cmd.Parameters.Add("@fromDate", SqlDbType.DateTime).Value = fromDate;
                    cmd.Parameters.Add("@toDateExclusive", SqlDbType.DateTime).Value = toDateExclusive;

                    Database.display(cmd, grid, view);
                }

                view.Focus();
                Classes.DevXGridViewSettings.ShowFooterTotal(view, "Amount");
            }
            finally
            {
                this.UseWaitCursor = false;
                Cursor.Current = Cursors.Default;
            }
        }
        private void DisplayExpenseSummary(
                                                string status,
                                                DateTime dateFrom,
                                                DateTime dateTo,
                                                DevExpress.XtraGrid.GridControl grid,
                                                DevExpress.XtraGrid.Views.Grid.GridView view)
        {
            // Add one day to make the end date exclusive
            DateTime dateToExclusive = dateTo.AddDays(1);

            string masterQuery = @"
                SELECT *
                FROM view_ExpenseSummary
                WHERE Status = @Stat
                  AND ExpenseDate >= @DateFrom
                  AND ExpenseDate < @DateTo
                ORDER BY BatchReferenceID DESC";

                    string detailQuery = @"
                SELECT d.*
                FROM view_ExpenseMasterDetails d
                WHERE EXISTS
                (
                    SELECT 1
                    FROM view_ExpenseSummary s
                    WHERE s.Status = @Stat
                      AND s.BatchReferenceID = d.BatchReferenceID
                      AND s.ExpenseDate >= @DateFrom
                      AND s.ExpenseDate < @DateTo
                )";

            var masterParams = new List<SqlParameter>
                        {
                            new SqlParameter("@DateFrom", dateFrom),
                            new SqlParameter("@DateTo", dateTo),
                            new SqlParameter("@Stat", status)
                        };

            var detailParams = new List<SqlParameter>
                            {
                                new SqlParameter("@DateFrom", dateFrom),
                                new SqlParameter("@DateTo", dateTo),
                                new SqlParameter("@Stat", status)
                            };

            //Database.GridMasterDetail(
            //            masterQuery,
            //            detailQuery,
            //            "Master",
            //            "Detail",
            //            "BatchReferenceID",
            //            "BatchReferenceID",
            //            "ExpenseMaster",
            //            grid,
            //            masterParams.ToArray(),
            //            detailParams.ToArray() // reuse the same parameter array
            //        );

            GridView detailView = Database.GridMasterDetailWithUpdate(
                    masterQuery,
                    detailQuery,
                    "Master",
                    "Detail",
                    "BatchReferenceID",
                    "BatchReferenceID",
                    "ExpenseMaster",
                    gridControl1,
                    masterParams.ToArray(),
                    detailParams.ToArray());

            detailView.CellValueChanged += DetailView_CellValueChanged;

            view.OptionsView.ColumnAutoWidth = false;
            view.BestFitColumns();

          
        }


        //void display()
        //{
        //    DateTime dateFrom = txtdatefrom.EditValue == null
        //        ? DateTime.MinValue
        //        : (DateTime)txtdatefrom.EditValue;

        //    DateTime dateTo = txtdateto.EditValue == null
        //        ? DateTime.MaxValue
        //        : ((DateTime)txtdateto.EditValue).AddDays(1);

           
        //    string masterQuery = @"
        //            SELECT *
        //            FROM [view_ExpenseSummary]
        //                WHERE Status=@Stat and ExpenseDate >= @DateFrom
        //                AND ExpenseDate < @DateTo ORDER BY BatchReferenceID DESC";

        //    string detailQuery = @"
        //            SELECT d.*
        //            FROM view_ExpenseMasterDetails d
        //            WHERE EXISTS
        //            (
        //                SELECT 1
        //                FROM [view_ExpenseSummary] s
        //                WHERE s.Status=@Stat and s.BatchReferenceID = d.BatchReferenceID
        //                  AND s.ExpenseDate >= @DateFrom
        //                  AND s.ExpenseDate < @DateTo
        //            ) ";

        
        //    var masterParams = new List<SqlParameter>
        //                {
        //                    new SqlParameter("@DateFrom", dateFrom),
        //                    new SqlParameter("@DateTo", dateTo),
        //                    new SqlParameter("@Stat", "POSTED")
        //                };

        //    var detailParams = new List<SqlParameter>
        //                {
        //                    new SqlParameter("@DateFrom", dateFrom),
        //                    new SqlParameter("@DateTo", dateTo),
        //                    new SqlParameter("@Stat", "POSTED")
        //                };

           
        //    Database.GridMasterDetail(
        //        masterQuery,
        //        detailQuery,
        //        "Master",
        //        "Detail",
        //        "BatchReferenceID",
        //        "BatchReferenceID",
        //        "ExpenseMaster",
        //        gridControl1,
        //        masterParams.ToArray(),
        //        detailParams.ToArray()
        //    );

        //    gridView1.OptionsView.ColumnAutoWidth = false;
        //    gridView1.BestFitColumns();
        //}

        private void btnPendingGenerate_Click(object sender, EventArgs e)
        {
            //DateTime fromDate = txtdatefrom.EditValue == null ? DateTime.MinValue : (DateTime)txtdatefrom.EditValue;
            //DateTime toDate = txtdateto.EditValue == null ? DateTime.MaxValue : (DateTime)txtdateto.EditValue;

            DateTime fromDate = txtdatefrom.DateTime == DateTime.MinValue
                ? DateTime.MinValue
                : txtdatefrom.DateTime;

            DateTime toDate = txtdateto.DateTime == DateTime.MinValue
                ? DateTime.MaxValue
                : txtdateto.DateTime.AddDays(1);


            DisplayExpenseSummary("POSTED", fromDate, toDate, gridControl1, gridView1);
            //LoadExpenseSummaryByStatus(
            //        "POSTED",
            //        datefromapproved.Text,
            //        datetoapproved.Text,
            //        gridControl1,
            //        gridView1);
            //display();

        }

        private void simpleButton1_Click(object sender, EventArgs e)
        {
          
            DateTime fromDate = dateFromPaid.DateTime == DateTime.MinValue
               ? DateTime.MinValue
               : dateFromPaid.DateTime;

            DateTime toDate = dateToPaid.DateTime == DateTime.MinValue
                ? DateTime.MaxValue
                : dateToPaid.DateTime.AddDays(1);

            DisplayExpenseSummary("PAID", fromDate, toDate, gridControl4, gridView4);
            //LoadExpenseSummaryByStatus(
            //        "PAID",
            //        dateFromPaid.Text,
            //        dateToPaid.Text,
            //        gridControl4,
            //        gridView4);

            //Database.display($"SELECT * FROM view_ExpenseSummary WHERE Status='PAID' AND CAST(ExpenseDate as date) between '{dateFromPaid.Text}' AND '{dateToPaid.Text}' ", gridControl4, gridView4);
            //string query = $"SELECT * FROM view_ExpenseSummary WHERE Status='PAID' AND CAST(ExpenseDate as date) between '{dateFromPaid.Text}' AND '{dateToPaid.Text}'  ";
            //HelperFunction.ShowWaitAndDisplayNonAsync(query, gridControl4, gridView4, "Please wait", "Populating data into the database...");
            //gridView4.Focus();
            //Classes.DevXGridViewSettings.ShowFooterTotal(gridView4, "Amount");
        }

        private void toolStripMenuItem3_Click(object sender, EventArgs e)
        {
            action = "PAID";
            displayDetails();
        }

        private void editDetailsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            EditExpenseDevEx editxpns = new EditExpenseDevEx();
            editxpns.txtrefno.Text = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "ReferenceNumber").ToString();
            editxpns.txtinvoiceno.Text = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "InvoiceNo").ToString();
            editxpns.txtexpdate.Text = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "ExpenseDate").ToString();
            editxpns.txtremarks.Text = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "Description").ToString();
            editxpns.txtvendor.Text = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "SupplierName").ToString();
            Database.display($"Select ReferenceNumber,InvoiceNo,ExpenseName,Remarks,Amount " +
                $"FROM dbo.ExpenseDetails " +
                $"WHERE ReferenceNumber='{editxpns.txtrefno.Text}' " +
                $"AND InvoiceNo='{editxpns.txtinvoiceno.Text}'", editxpns.gridControl1, editxpns.gridView1);

            editxpns.ShowDialog(this);
        }

        private void gridControl4_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStripPaid.Show(gridControl4, e.Location);
            
        }

        private void errorCorrectToolStripMenuItem_Click(object sender, EventArgs e)
        {
            bool confirm = HelperFunction.ConfirmDialog("Are you sure you want to Cancel this Cheque? if yes All Ticket Entries in this Transaction Voucher will automatically create reversal entries..", "Cancelled Cheque");
            if (confirm)
            {
                CancelledCheckVoucher canfrm = new CancelledCheckVoucher();
                canfrm.ShowDialog(this);
                if (CancelledCheckVoucher.isdone == true)
                {
                    reason = CancelledCheckVoucher.reason;
                    errorCorrect();
                    canfrm.Dispose();
                }

            }
            else
            {
                return;
            }
        }
        private void errorCorrect()
        {
            if (gridView1.FocusedRowHandle < 0)
            {
                XtraMessageBox.Show("Please select an Expense to cancel.");
                return;
            }

            if (XtraMessageBox.Show(
                "This will reverse all posted Expense and GL entries.\n\nContinue?",
                "Confirm Reversal",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning) != DialogResult.Yes)
            {
                return;
            }

            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.sp_ReverseApprovedExpense", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.Add("@parmrefno", SqlDbType.VarChar, 10)
                    .Value = gridView1.GetFocusedRowCellValue("ReferenceNumber");
                cmd.Parameters.Add("@parminvoiceno", SqlDbType.VarChar, 150)
                    .Value = gridView1.GetFocusedRowCellValue("InvoiceNo");
                cmd.Parameters.Add("@parmsupplierid", SqlDbType.VarChar, 20)
                     .Value = gridView1.GetFocusedRowCellValue("SupplierID");
                cmd.Parameters.Add("@parmreason", SqlDbType.VarChar, 300)
                    .Value = reason.Trim();
                cmd.Parameters.Add("@parmuser", SqlDbType.VarChar, 50)
                   .Value = Login.Fullname;
               

                try
                {
                    con.Open();
                    cmd.ExecuteNonQuery();
                    BigAlert.Show("SUCESS","Expense successfully reversed.",MessageBoxIcon.Information);
                    //btnsearch_Click(null, null); // refresh grid
                    btnPendingGenerate_Click(null, null);
                }
                catch (SqlException ex)
                {
                    XtraMessageBox.Show(ex.Message);
                }
            }
        }
        

        private void btnforapproval_Click(object sender, EventArgs e)
        {
            LoadExpenseSummaryByStatus(
                    "FOR APPROVAL",
                    txtdatefromforapproval.Text,
                    txtdatetoforapproval.Text,
                    gridControl2,
                    gridView2);


        }

        private void editDetailsToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            AddExpenseDevExFrmTest addtest = new AddExpenseDevExFrmTest();
            addtest.Show();
        }

        private void btnGenerateCancelled_Click(object sender, EventArgs e)
        {
          
            DateTime fromDate = dateFromCancelled.DateTime == DateTime.MinValue
               ? DateTime.MinValue
               : dateFromCancelled.DateTime;

            DateTime toDate = dateToCancelled.DateTime == DateTime.MinValue
                ? DateTime.MaxValue
                : dateToCancelled.DateTime.AddDays(1);


            DisplayExpenseSummary("CANCELLED", fromDate, toDate, gridControlCancelled, gridViewCancelled);
        }
        
    }
}