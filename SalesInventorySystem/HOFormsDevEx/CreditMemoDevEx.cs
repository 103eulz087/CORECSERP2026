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
using System.Data.SqlClient;
using DevExpress.XtraGrid.Views.Grid;
using DevExpress.XtraReports.UI;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class CreditMemoDevEx : DevExpress.XtraEditors.XtraForm
    {
        public CreditMemoDevEx()
        {
            InitializeComponent();
        }

        static bool IsRowAlreadyReturned(GridView view, int rowHandle)
        {
            object val = view.GetRowCellValue(rowHandle, "isReturned");
            return val != null && val != DBNull.Value && Convert.ToBoolean(val);
        }

        private void gridView4_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            double sellingprice = 0.0,qty=0.0,variance=0.0,actualqty=0.0,total=0.0,totalamount=0.0,discountamount=0.0;
            bool isReturned = IsRowAlreadyReturned((GridView)sender, gridView4.FocusedRowHandle);
            totalamount = Convert.ToDouble(gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "TotalAmount").ToString());
            qty = Convert.ToDouble(gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "QtyDelivered").ToString());
            actualqty = Convert.ToDouble(gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "ActualQty").ToString());
            sellingprice = Convert.ToDouble(gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "SellingPrice").ToString());
            variance = qty - actualqty;
            total = variance * sellingprice;
            discountamount = totalamount - total;
            if (isReturned==true)
            {
                XtraMessageBox.Show("This item is Already Returned!..");
                return;
            }
            if (e.Column.FieldName == "ActualQty")
            {
                gridView4.SetRowCellValue(gridView4.FocusedRowHandle, "Variance", variance.ToString());
            }
            if (e.Column.FieldName == "Variance")
            {
                gridView4.SetRowCellValue(gridView4.FocusedRowHandle, "DiscountAmount", total.ToString());
            }
            
        }

        private void button1_Click(object sender, EventArgs e)
        {
            try
            {
                bool isInvoiceUpdated = false;
                isInvoiceUpdated = Database.checkifExist("Select isInvoiceUpdate FROM DeliverySummary WHERE PONumber='" + txtpono.Text + "' and isInvoiceUpdate=1");
                if(isInvoiceUpdated==false)
                {
                    XtraMessageBox.Show("Invoice Number must be updated first..please go to Print Delivery Receipt Option!...");
                    return;
                }
                executeSP(BuildCreditMemoLinesTVP());
                XtraMessageBox.Show("Payment Successfully Posted");
                //this.Dispose();
                //button2.PerformClick();
            }
            catch(Exception ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }

        // Rows the user edited in the grid (Variance <> 0), as the (SeqNo, ProductNo,
        // ActualQty) TVP sp_CreditMemo now applies server-side -- ActualQty, Variance,
        // and isCreditMemo are all set together in one statement inside the SP's
        // transaction, instead of a per-row UPDATE loop from here.
        DataTable BuildCreditMemoLinesTVP()
        {
            DataTable dt = new DataTable();
            dt.Columns.Add("SeqNo", typeof(decimal));
            dt.Columns.Add("ProductNo", typeof(string));
            dt.Columns.Add("ActualQty", typeof(decimal));

            for (int i = 0; i <= gridView4.RowCount - 1; i++)
            {
                if (IsRowAlreadyReturned(gridView4, i))
                    continue;

                if (Convert.ToDouble(gridView4.GetRowCellValue(i, "Variance").ToString()) != 0)
                {
                    dt.Rows.Add(
                        Convert.ToDecimal(gridView4.GetRowCellValue(i, "SeqNo")),
                        gridView4.GetRowCellValue(i, "ProductNo").ToString(),
                        Convert.ToDecimal(gridView4.GetRowCellValue(i, "ActualQty")));
                }
            }
            return dt;
        }

        void executeSP(DataTable lines)
        {
            SqlConnection con = Database.getConnection();
            con.Open();
            try
            {
                string query = "sp_CreditMemo";
                SqlCommand com = new SqlCommand(query, con);
                com.Parameters.AddWithValue("@parmpono", txtpono.Text);
                com.Parameters.AddWithValue("@parmuser", Login.Fullname);
                com.Parameters.AddWithValue("@parmstat", txtstatus.Text);
                var tvpParam = com.Parameters.AddWithValue("@Lines", lines);
                tvpParam.SqlDbType = SqlDbType.Structured;
                tvpParam.TypeName = "dbo.tt_CreditMemoLines";
                com.CommandType = CommandType.StoredProcedure;
                com.CommandText = query;
                com.ExecuteNonQuery();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
            finally
            {
                con.Close();
            }
        }


        private void gridView4_ShowingEditor(object sender, CancelEventArgs e)
        {
            GridView view = sender as GridView;
            if (view.FocusedColumn.FieldName != "ActualQty")
            {
                e.Cancel = true;
                return;
            }
            if (IsRowAlreadyReturned(view, view.FocusedRowHandle))
            {
                e.Cancel = true;
            }
        }

        // Rows already returned (isReturned=1 in view_CreditMemoDetails) are highlighted red
        // and can't be edited (see gridView4_ShowingEditor) -- they've already been reversed
        // via Sales Return, so there's nothing left to adjust here.
        private void gridView4_RowStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowStyleEventArgs e)
        {
            GridView view = sender as GridView;
            if (e.RowHandle < 0)
                return;

            if (IsRowAlreadyReturned(view, e.RowHandle))
            {
                e.Appearance.BackColor = Color.Red;
                e.Appearance.BackColor2 = Color.IndianRed;
                e.Appearance.ForeColor = Color.White;
                e.HighPriority = true;
            }
        }

        private void CreditMemoDevEx_Load(object sender, EventArgs e)
        {

        }

        private void button2_Click(object sender, EventArgs e)
        {
            try
            {
                //Database.display("SELECT PONumber,QtyDelivered as Qty,ProductName as Description,SellingPrice as UnitCost,FORMAT(TotalAmount , 'N', 'en-us') as Amount FROM view_CreditMemoDetails WHERE Variance > 0 and PONumber='" + txtpono.Text + "' ", gridControl4, gridView4);
                Database.display("SELECT * FROM view_CreditMemoDetails WHERE PONumber='" + txtpono.Text + "' AND isCreditMemo='1'", gridControl4, gridView4);

                //button3.PerformClick();
                DevExReportTemplate.Creditmemo xct = new DevExReportTemplate.Creditmemo();
                xct.Landscape = false;

                string custname = Database.getSingleQuery("PurchaseOrderSummary", " PONumber='" + txtpono.Text + "'", "Customer");
                string refno = Database.getSingleQuery("DeliverySummary", " PONumber='" + txtpono.Text + "'", "ReferenceNumber");
                string invoiceno = Database.getSingleQuery("DeliverySummary", " PONumber='" + txtpono.Text + "'", "InvoiceNo");
                //string refno = Database.getSingleQuery("DeliveryDetails", " PONumber='" + txtpono.Text + "'", "ReferenceNumber");

                xct.xrcustname.Text = custname;
                xct.xrinvoiceno.Text = invoiceno;
                xct.xrdate.Text = DateTime.Now.ToShortDateString();
                xct.xrPreparedBy.Text = Login.Fullname;

                xct.xrtitle.Text = "Credit Memo";

                gridView4.Columns["PONumber"].Visible = false;
                gridView4.Columns["ProductNo"].Visible = false;
                gridView4.Columns["QtyDelivered"].Visible = false;
                gridView4.Columns["ActualQty"].Visible = false;
                gridView4.Columns["Cost"].Visible = false;
                gridView4.Columns["TotalAmount"].Visible = false;
                gridView4.Columns["Status"].Visible = false;
                gridView4.Columns["DateProcessed"].Visible = false;
                gridView4.Columns["isVat"].Visible = false;
                gridView4.Columns["ProcessedBy"].Visible = false;
                gridView4.Columns["SequenceNo"].Visible = false;
                gridView4.Columns["isSettled"].Visible = false;
                gridView4.Columns["isCreditMemo"].Visible = false;
                gridView4.Columns["isReturned"].Visible = false;

                xct.xrPreparedBy.Text = Login.Fullname;
                xct.Bands[BandKind.Detail].Controls.Add(HelperFunction.CopyGridControlCredMemo(gridControl4,gridView4,"Variance"));
                xct.Bands[BandKind.Detail].Font = new System.Drawing.Font("Tahoma", 10);
                ReportPrintTool report = new ReportPrintTool(xct);
                report.PreviewRibbonForm.FormClosed += PreviewRibbonForm_FormClosed;
                report.ShowRibbonPreviewDialog();

            }
            catch (FormatException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }

        private void PreviewRibbonForm_FormClosed(object sender, FormClosedEventArgs e)
        {
            gridView4.Columns["PONumber"].Visible = true;
            gridView4.Columns["ProductNo"].Visible = true;
            gridView4.Columns["QtyDelivered"].Visible = true;
            gridView4.Columns["ActualQty"].Visible = true;
            gridView4.Columns["Cost"].Visible = true;
            gridView4.Columns["TotalAmount"].Visible = true;
            gridView4.Columns["Status"].Visible = true;
            gridView4.Columns["DateProcessed"].Visible = true;
            gridView4.Columns["isVat"].Visible = true;
            gridView4.Columns["ProcessedBy"].Visible = true;
            gridView4.Columns["SequenceNo"].Visible = true;
            gridView4.Columns["isSettled"].Visible = true;
            gridView4.Columns["isCreditMemo"].Visible = true;
            gridView4.Columns["isReturned"].Visible = true;
        }

        private void button3_Click(object sender, EventArgs e)
        {
            for (int i = 0; i <= gridView4.RowCount - 1; i++)
            {
                if (Convert.ToDouble(gridView4.GetRowCellValue(i, "Variance").ToString()) <= 0)
                {
                    gridView4.DeleteRow(i);
                }
            }
        }
        void submitCM()
        {
            try
            {
                bool isInvoiceUpdated = false;
                isInvoiceUpdated = Database.checkifExist("Select 1 FROM DeliverySummary WHERE PONumber='" + txtpono.Text + "' and isInvoiceUpdate=1");
                if (isInvoiceUpdated == false)
                {
                    XtraMessageBox.Show("Invoice Number must be updated first..please go to Print Delivery Receipt Option!...");
                    return;
                }
                else
                {
                    bool confirm = HelperFunction.ConfirmDialog("Are you sure?", "Confirm Transaction");
                    if (confirm)
                    {
                        executeSP(BuildCreditMemoLinesTVP());
                        XtraMessageBox.Show("Successfully Executed!..");
                    }
                    else
                    {
                        return;
                    }

                }
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }
        private void simpleButton1_Click(object sender, EventArgs e)
        {
            submitCM();
            this.Dispose();
        }
        void printCM()
        {
            try
            {
                //Database.display("SELECT PONumber,QtyDelivered as Qty,ProductName as Description,SellingPrice as UnitCost,FORMAT(TotalAmount , 'N', 'en-us') as Amount FROM view_CreditMemoDetails WHERE Variance > 0 and PONumber='" + txtpono.Text + "' ", gridControl4, gridView4);
                Database.display("SELECT * FROM view_CreditMemoDetails WHERE PONumber='" + txtpono.Text + "' AND isCreditMemo='1'", gridControl4, gridView4);

                //button3.PerformClick();
                DevExReportTemplate.Creditmemo xct = new DevExReportTemplate.Creditmemo();
                xct.Landscape = false;

                string custname = Database.getSingleQuery("PurchaseOrderSummary", " PONumber='" + txtpono.Text + "'", "Customer");
                string refno = Database.getSingleQuery("DeliverySummary", " PONumber='" + txtpono.Text + "'", "ReferenceNumber");
                string invoiceno = Database.getSingleQuery("DeliverySummary", " PONumber='" + txtpono.Text + "'", "InvoiceNo");
                //string refno = Database.getSingleQuery("DeliveryDetails", " PONumber='" + txtpono.Text + "'", "ReferenceNumber");

                xct.xrcustname.Text = custname;
                xct.xrinvoiceno.Text = invoiceno;
                xct.xrdate.Text = DateTime.Now.ToShortDateString();
                xct.xrPreparedBy.Text = Login.Fullname;

                xct.xrtitle.Text = "Credit Memo";

                gridView4.Columns["PONumber"].Visible = false;
                gridView4.Columns["ProductNo"].Visible = false;
                gridView4.Columns["QtyDelivered"].Visible = false;
                gridView4.Columns["ActualQty"].Visible = false;
                gridView4.Columns["Cost"].Visible = false;
                gridView4.Columns["TotalAmount"].Visible = false;
                gridView4.Columns["Status"].Visible = false;
                gridView4.Columns["DateProcessed"].Visible = false;
                gridView4.Columns["isVat"].Visible = false;
                gridView4.Columns["ProcessedBy"].Visible = false;
                gridView4.Columns["SequenceNo"].Visible = false;
                gridView4.Columns["isSettled"].Visible = false;
                gridView4.Columns["isCreditMemo"].Visible = false;
                gridView4.Columns["isReturned"].Visible = false;

                xct.xrPreparedBy.Text = Login.Fullname;
                xct.Bands[BandKind.Detail].Controls.Add(HelperFunction.CopyGridControlCredMemo(gridControl4, gridView4, "Variance"));
                xct.Bands[BandKind.Detail].Font = new System.Drawing.Font("Tahoma", 10);
                ReportPrintTool report = new ReportPrintTool(xct);
                report.PreviewRibbonForm.FormClosed += PreviewRibbonForm_FormClosed;
                report.ShowRibbonPreviewDialog();

            }
            catch (FormatException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }
        private void simpleButton2_Click(object sender, EventArgs e)
        {
            printCM();
        }
    }
}