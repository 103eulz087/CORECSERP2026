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
using DevExpress.XtraReports.UI;
using DevExpress.XtraGrid.Views.Grid;
using System.Data.SqlClient;

namespace SalesInventorySystem.Orders
{
    public partial class STSForApprovalDetails : DevExpress.XtraEditors.XtraForm
    {
        public static string refernceno;
        public static bool isdone = false;
        public STSForApprovalDetails()
        {
            InitializeComponent();
        }

        private void STSForApprovalDetails_Load(object sender, EventArgs e)
        {
            if (POForApprovalSTS.menu == "approvedrequest")
            {
                btnadd.Visible = false;
                simpleButton9.Visible = false;
            }
            else
            {
                btnadd.Visible = true;
                simpleButton9.Visible = true;
            }
        }

        // Only ApprovedQty is editable, and only while the request is still actionable (not when
        // just viewing an already-decided one -- see STSForApprovalDetails_Load's btnadd/
        // simpleButton9 visibility toggle for the same "approvedrequest" check).
        private void gridView1_ShowingEditor(object sender, CancelEventArgs e)
        {
            GridView view = sender as GridView;
            if (POForApprovalSTS.menu == "approvedrequest" || view.FocusedColumn.FieldName != "ApprovedQty")
                e.Cancel = true;
        }

        DataTable BuildApprovedQtyLinesTVP()
        {
            DataTable dt = new DataTable();
            dt.Columns.Add("SeqNo", typeof(decimal));
            dt.Columns.Add("ApprovedQty", typeof(decimal));

            // gridView1 is grouped (by Category -- see POForApprovalSTS.showSTSForApproval()), so
            // RowCount counts group rows too; GetRowCellValue against a group row handle returns
            // null for a plain data field, which is what was throwing here. DataRowCount always
            // reflects actual data rows regardless of grouping/collapsed state.
            for (int i = 0; i <= gridView1.DataRowCount - 1; i++)
            {
                dt.Rows.Add(
                    Convert.ToDecimal(gridView1.GetRowCellValue(i, "SeqNo")),
                    Convert.ToDecimal(gridView1.GetRowCellValue(i, "ApprovedQty")));
            }
            return dt;
        }

        void submitDecision(string action)
        {
            using (SqlConnection con = Database.getConnection())
            {
                con.Open();
                SqlCommand com = new SqlCommand("sp_ApproveTransferOrder", con);
                com.CommandType = CommandType.StoredProcedure;
                com.Parameters.AddWithValue("@parmpono", txtpono.Text);
                com.Parameters.AddWithValue("@parmuser", Login.Fullname);
                com.Parameters.AddWithValue("@parmremarks", richTextBox1.Text.Trim());
                com.Parameters.AddWithValue("@parmaction", action);
                var tvpParam = com.Parameters.AddWithValue("@Lines",
                    action == "APPROVED" ? BuildApprovedQtyLinesTVP() : new DataTable());
                tvpParam.SqlDbType = SqlDbType.Structured;
                tvpParam.TypeName = "dbo.tt_TransferApprovalLines";
                com.ExecuteNonQuery();
            }
        }

        private void btnapprove_Click(object sender, EventArgs e)
        {
            if (richTextBox1.Text == "")
            {
                XtraMessageBox.Show("Please Input Remarks");
            }
            else
            {
                refernceno = POForApproval.refno;//gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "PONumber").ToString();
                try
                {
                    submitDecision("APPROVED");
                    isdone = true;
                    this.Close();
                }
                catch (SqlException sqx)
                {
                    XtraMessageBox.Show(sqx.Message.ToString());
                }
            }
        }

        private void btnreject_Click(object sender, EventArgs e)
        {
            if (richTextBox1.Text == "")
            {
                XtraMessageBox.Show("Please Input Remarks");
            }
            else
            {
                bool ok = HelperFunction.ConfirmDialog("Are you sure you want to Reject this Transaction?", "Rejected!!");
                if (ok)
                {
                    try
                    {
                        submitDecision("REJECTED");
                        this.Close();
                    }
                    catch (SqlException sqx)
                    {
                        XtraMessageBox.Show(sqx.Message.ToString());
                    }
                }
            }
        }
        void printSts()
        {
            var row = Database.getMultipleQuery("ReportHeaderSettings", "ReportName='StockOrderRep' ", "Heading,ImageWidth,ImageHeight,Caption1,Caption2");

            string companyname = row["Heading"].ToString();
            string imagewidth = row["ImageWidth"].ToString();
            string imageheight = row["ImageHeight"].ToString();
            string caption1 = row["Caption1"].ToString();
            string caption2 = row["Caption2"].ToString();
           
            gridView1.FocusedRowHandle = 2;
            DevExReportTemplate.StockOrderRep xct = new DevExReportTemplate.StockOrderRep();

            Classes.Utilities.GetImageDevEx(xct.xrPictureBox1, "ReportHeaderSettings", "ReportName='StockOrderRep'", "ImageLogo");
            xct.xrPictureBox1.SizeF = new SizeF(float.Parse(imagewidth), float.Parse(imageheight));

            xct.xrcompanyname.Text = companyname;
            xct.xrcaption1.Text = caption1;
            xct.xrcaption2.Text = caption2;

            xct.Landscape = false;
            xct.PaperKind = (DevExpress.Drawing.Printing.DXPaperKind)System.Drawing.Printing.PaperKind.A4;
          
            var rowz = Database.getMultipleQuery("TransferOrderSummary", "PONumber='" + txtpono.Text + "' ", "RequestedBy,InitiatingBranch,BranchCode,EffectivityDate");

            string requestedby = rowz["RequestedBy"].ToString();
            string brcode = rowz["BranchCode"].ToString();
            string InitiatingBranch = rowz["InitiatingBranch"].ToString();
            string effecitivitydate = rowz["EffectivityDate"].ToString();
            string branchname = Database.getSingleQuery("Branches", "BranchCode='" + InitiatingBranch + "'", "BranchName");
            string branchaddress = Database.getSingleQuery("Branches", "BranchCode='" + InitiatingBranch + "'", "Address");

            xct.xrdateprocessed.Text = DateTime.Today.ToShortDateString();
            xct.xrbranchname.Text = branchname;
            xct.xrbranchaddress.Text = branchaddress;
            xct.xrdate.Text = Convert.ToDateTime(effecitivitydate).ToShortDateString();//dt.ToShortDateString();
            xct.xrrequestedby.Text = requestedby;//POForApproval.requestedBy;
            xct.xrpono.Text = txtpono.Text;
            xct.xrpreparedby.Text = Login.Fullname;

            gridView1.Columns["ProductName"].AppearanceCell.TextOptions.WordWrap = DevExpress.Utils.WordWrap.Wrap;
           

            //gridView1.Columns["ProductCategoryCode"].OptionsColumn.Printable = DevExpress.Utils.DefaultBoolean.False;
            gridView1.Columns["Category"].OptionsColumn.Printable = DevExpress.Utils.DefaultBoolean.False;
            gridView1.Columns["ProductCode"].OptionsColumn.Printable = DevExpress.Utils.DefaultBoolean.False;
            gridView1.Columns["ProductName"].OptionsColumn.Printable = DevExpress.Utils.DefaultBoolean.False;
            //gridView1.Columns["Qty"].OptionsColumn.Printable = DevExpress.Utils.DefaultBoolean.False; 

            this.gridView1.Columns["PONumber"].Visible = false;
            this.gridView1.Columns["Category"].Visible = false;
            this.gridView1.Columns["ProductCode"].Visible = false;
            //this.gridView1.Columns["ProductCategoryCode"].Visible = false;
            if (GlobalCache.CompanyName == "ENZO" || GlobalCache.CompanyName == "JFC")
            {
                this.gridView1.Columns["Barcode"].Visible = false;
            }
           
            this.gridView1.Columns["Status"].Visible = false;
         

            xct.Bands[BandKind.Detail].Controls.Add(HelperFunction.CopyGridControl(this.gridControl1));
            xct.Bands[BandKind.Detail].Font = new System.Drawing.Font("Tahoma", 9);
            // Ensure detail band doesn’t force page breaks

            xct.Bands[BandKind.Detail].PageBreak = DevExpress.XtraReports.UI.PageBreak.None;
            xct.Margins = new System.Drawing.Printing.Margins(50, 50, 50, 50);
            xct.PaperKind = (DevExpress.Drawing.Printing.DXPaperKind)System.Drawing.Printing.PaperKind.A4;
            var gridCopy = HelperFunction.CopyGridControl(this.gridControl1);
            gridCopy.SizeF = new SizeF(xct.PageWidth - xct.Margins.Left - xct.Margins.Right, gridCopy.SizeF.Height);
            xct.Bands[BandKind.Detail].Controls.Add(gridCopy);

            ReportPrintTool report = new ReportPrintTool(xct);
            report.ShowRibbonPreviewDialog();
        }


        private void button1_Click(object sender, EventArgs e)
        {
            printSts();
        }

        private void btnadd_Click(object sender, EventArgs e)
        {
            if (richTextBox1.Text == "")
            {
                XtraMessageBox.Show("Please Input Remarks");
            }
            else
            {
                refernceno = POForApproval.refno;//gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "PONumber").ToString();
                try
                {
                    submitDecision("APPROVED");
                    isdone = true;
                    this.Close();
                }
                catch (SqlException sqx)
                {
                    XtraMessageBox.Show(sqx.Message.ToString());
                }
            }
        }

        private void simpleButton9_Click(object sender, EventArgs e)
        {
            if (String.IsNullOrEmpty(richTextBox1.Text))
            {
                XtraMessageBox.Show("Please Input Remarks");
            }
            else
            {
                bool ok = HelperFunction.ConfirmDialog("Are you sure you want to Reject this Transaction?", "Rejected!!");
                if (ok)
                {
                    try
                    {
                        string pono = txtpono.Text;
                        if (XtraMessageBox.Show("Are you sure you want to cancel this STS Request?", "Cancel STS Request", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
                        {
                            bool checkifexistsindelivery = Database.checkifExist("SELECT TOP(1) 1 FROM DeliverySummary WHERE PONumber='" + pono + "'");
                            if (checkifexistsindelivery)
                            {
                                XtraMessageBox.Show("This STS Request is already in delivery. " +
                                    "You cannot cancel it, unless you will cancel all the items that has been processed already",
                                    "Cancel STS Request", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                            }
                            else
                            {
                                Database.ExecuteQuery("UPDATE TransferOrderSummary SET Status='REJECTED' WHERE PONumber='" + pono + "'");
                                XtraMessageBox.Show("STS Request Rejected successfully.", "Rejected STS Request", MessageBoxButtons.OK, MessageBoxIcon.Information);
                                this.Close();
                            }
                        }
                        
                    }
                    catch (SqlException sqx)
                    {
                        XtraMessageBox.Show(sqx.Message.ToString());
                    }
                }
            }
        }

        private void simpleButton10_Click(object sender, EventArgs e)
        {
            printSts();
        }
    }
}
