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
using DevExpress.XtraGrid.Views.Grid;
using DevExpress.XtraGrid.Columns;
using System.IO.Ports;
using System.Data.SqlClient;
using DevExpress.XtraReports.UI;
using DevExpress.XtraGrid;
using SalesInventorySystem.Classes;

namespace SalesInventorySystem.Orders
{
    public partial class AddBranchOrderSTS : DevExpress.XtraEditors.XtraForm
    {
        public delegate void AddDataDelegate(String myString);
        public AddDataDelegate myDelegate;
        object pcode,catcode, referencecode, shipmentno;
        private String weight;
        public string wieght2 = "";
        public static bool isdone = false, ispending = false;
        string productcategorycode = "";
        string globaltxtbarcodescanning = "", globalproductcode = "";
        bool isFifo = Database.checkifExist("SELECT isFifo FROM InventorySettings WHERE isFifo=1");
        bool isusedSearch = false;

       
       
        public AddBranchOrderSTS()
        {         
            this.myDelegate = new AddDataDelegate(AddDataMethod);
            InitializeComponent();
            HelperFunction.AllowNumbersAndPeriodDevEx(txtweight);
        }
        public void AddDataMethod(String myString)
        {
            txtweight.Text += myString;
        }
        private void AddBranchOrderSTS_Load(object sender, EventArgs e)
        {
            getAvailablePort();

            //if (isFifo == true)
            //{
            //    barcodescanning.Checked = false;
            //    panel1.Visible = false;
            //    panel2.Visible = false;
            //    panel3.Visible = false;
            //    panel4.Visible = true;
            //}
            //else
            //{
            //    barcodescanning.Checked = true;
            //    panel1.Visible = true;

            //}
            barcodescanning.Checked = true;
            panel1.Visible = true;
            txtbarcodescanning.Focus();
            Database.displayComboBoxItems("SELECT Description FROM ProductCategory", "Description", txtprodcat);

            bool fExst = Database.checkifExist("SELECT 1 FROM DeliverySummary WHERE PONumber='" + ViewBranchOrderSTS.ponumber + "'");
            //bool fExst = Database.checkifExist("SELECT 1 FROM DeliveryDetails WHERE PONumber='" + ViewBranchOrderSTS.ponumber + "'");
            string getID = Database.getSingleData("DeliveryDetails", "PONumber", ViewBranchOrderSTS.ponumber, "DeliveryNo");
            if (fExst)
            {
                txtdevno.Text = getID;
            }
            else
            {
                txtdevno.Text = IDGenerator.getIDNumberSP("sp_GetDeliveryNumber", "DeliveryNumber");
            }

            txtcomport.Focus();

            //txtbrcode.Text = ViewBranchOrder.branchno;
            //txtponum.Text = ViewBranchOrder.ponumber;
            //txtrefno.Text = IDGenerator.getReferenceNumber();
            //txteffectivedate.Text = ViewBranchOrder.effectivedate;

            GridView view = gridControl1.FocusedView as GridView;
            view.SortInfo.ClearAndAddRange(new GridColumnSortInfo[] {
                new GridColumnSortInfo(view.Columns["Category"],DevExpress.Data.ColumnSortOrder.Ascending)
                }, 1);

        }
        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            bool functionReturnValue = false;
            if (keyData == Keys.F10)
            {
                simpleButton11.PerformClick();
            }
            else if (keyData == Keys.F6)
            {
                simpleButton9.PerformClick();
            }
            else if (keyData == Keys.F8)
            {
                simpleButton10.PerformClick();
            }
            if (keyData == Keys.F1)
            {
                btnfind.PerformClick();
            }
            if (keyData == Keys.F5)
            {
                btnchecker.PerformClick();
            }
            return functionReturnValue;
        }

        private void txtsku_KeyDown(object sender, KeyEventArgs e)
        {
            bool isExist = Database.checkifExist("SELECT BarcodeNo FROM DeliveryDetails WHERE BarcodeNo='" + txtsku.Text + "'");
            if (e.KeyCode == Keys.Enter)
            {
                btnadd.PerformClick();
            }
            else if (e.KeyCode == Keys.F10)
            {
                simpleButton2.PerformClick();
            }
        }

        /*****************************************NEW*****************************/
        private void getAvailablePort()
        {
            string[] ports = SerialPort.GetPortNames();
            txtcomport.Properties.Items.AddRange(ports);
        }

        void displayComboBoxItems()
        {
            Database.displayComboBoxItems("SELECT * FROM Products WHERE BranchCode='888' ORDER BY Description", "Description", txtproduct);
            Database.displayComboBoxItems("SELECT Description FROM ProductCategory", "Description", txtprodcat);
        }

        /*****************************************NEW*****************************/
        private void displayForDelivery()
        {
            gridControl2.BeginUpdate();
            //     Database.display("SELECT QtyDelivered,BarcodeNo,ProductNo,ProductName,FORMAT(Cost,'N','en-us')AS Cost,SequenceNo FROM DeliveryDetails WHERE DeliveryNo='" + txtdevno.Text + "'", gridControl2, gridView2);

            if (GlobalCache.CompanyName == "JFC")
            {

                Database.display($"SELECT * FROM dbo.funcview_ProcessOrderItemsSales('{txtponum.Text}')", gridControl2, gridView2);
            }
            else
            {
                Database.display("SELECT SeqNo" +
               ",ProductNo" +
               ",ProductName" +
               ",BarcodeNo" +
               ",QtyDelivered " +
               "FROM DeliveryDetails " +
               "WHERE PONumber='" + txtponum.Text + "' AND DeliveryNo='" + txtdevno.Text + "' AND isCancelled=0 " +
               "AND Status='PENDING'", gridControl2, gridView2);
            }


            //Database.display("SELECT SeqNo,ProductNo,ProductName,BarcodeNo,QtyDelivered " +
            //    "FROM dbo.DeliveryDetails with(nolock) WHERE PONumber='"+txtponum.Text+"' AND DeliveryNo='" + txtdevno.Text + "' AND Status='PENDING' ORDER BY SeqNo DESC", gridControl2, gridView2);

            //gridView2.Columns[0].Visible = false;

            //GridView view = gridControl2.FocusedView as GridView;
            //view.SortInfo.ClearAndAddRange(new GridColumnSortInfo[] {
            //    new GridColumnSortInfo(view.Columns["ProductName"],DevExpress.Data.ColumnSortOrder.Ascending)
            //    }, 1); 
            //gridView2.ExpandAllGroups();


            //GridGroupSummaryItem itez = new GridGroupSummaryItem();
            //itez.FieldName = "ProductNo";
            //itez.SummaryType = DevExpress.Data.SummaryItemType.Count;
            //itez.ShowInGroupColumnFooter = gridView2.Columns["ProductNo"];
            //gridView2.GroupSummary.Add(itez);
            //gridView2.Focus();

            //GridGroupSummaryItem ite = new GridGroupSummaryItem();
            //ite.FieldName = "QtyDelivered";
            //ite.SummaryType = DevExpress.Data.SummaryItemType.Sum;
            //ite.ShowInGroupColumnFooter = gridView2.Columns["QtyDelivered"];
            //gridView2.GroupSummary.Add(ite);
            //gridView2.Focus();


            gridView2.Columns["ProductNo"].Summary.Clear();
            gridView2.Columns["ProductNo"].Summary.Add(DevExpress.Data.SummaryItemType.Count, "ProductNo", "{0:n2}");
            gridView2.Columns["QtyDelivered"].Summary.Clear();
            gridView2.Columns["QtyDelivered"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "QtyDelivered", "{0:n2}");
            gridControl2.EndUpdate();
        }

        private void simpleButton2_Click(object sender, EventArgs e)
        {
            if (gridView2.RowCount == 0)
            {
                XtraMessageBox.Show("Cant Save no Order to be Processed!");
                return;
            }
          

            bool confirm = HelperFunction.ConfirmDialog("Are you sure all order has been Processed?", "Save Transaction");
            if (!confirm)
            {
                return;
            }
            else
            {
                ConfirmBranchOrder();
                isdone = true;
                XtraMessageBox.Show("Transaction Successfully Saved!");
                this.Close();
            }
        }

        private void txtsku_KeyPress(object sender, KeyPressEventArgs e)
        {
            if (!char.IsControl(e.KeyChar) && !char.IsDigit(e.KeyChar))
            {
                e.Handled = true;
            }
        }

        void addBranchOrder()
        {
            string sourceseqnum = "";
            sourceseqnum = txtseqno.Text;
            SqlConnection con = Database.getConnection();
            con.Open();
            string query = "";
            if(GlobalCache.CompanyName=="JFC")
            {
                query = "sp_AddBranchOrder_JFC";
            }
            else
            {
                query = "sp_AddBranchOrder";
            }
            try
            {
                SqlCommand com = new SqlCommand(query, con);

                com.Parameters.AddWithValue("@parmdevno",
                    string.IsNullOrWhiteSpace(txtdevno.Text) ? "" : txtdevno.Text);

                com.Parameters.AddWithValue("@parmrefno",
                    string.IsNullOrWhiteSpace(txtrefno.Text) ? "" : txtrefno.Text);

                com.Parameters.AddWithValue("@parmpono",
                    string.IsNullOrWhiteSpace(txtponum.Text) ? "" : txtponum.Text);

                com.Parameters.AddWithValue("@parmprodcatcode", catcode?.ToString() ?? "");
                com.Parameters.AddWithValue("@parmprodcode", pcode?.ToString() ?? "");
                if (GlobalCache.CompanyName == "JFC")
                {
                    com.Parameters.AddWithValue("@parmshipmentno", shipmentno?.ToString() ?? "");
                }
                com.Parameters.AddWithValue("@parmqty", txtweight.Text);
                com.Parameters.AddWithValue("@parmbarcode", txtsku.Text);

                com.Parameters.AddWithValue("@parmbranchcode", txtbrcode.Text); //initiating branhc
                com.Parameters.AddWithValue("@parmorigin", Login.assignedBranch);
                com.Parameters.AddWithValue("@preparedby", Login.Fullname);
                //com.Parameters.AddWithValue("@parmeffectivitydate", txteffectivedate.Text);
                com.Parameters.AddWithValue("@parmsourceseqno", sourceseqnum);
                com.Parameters.AddWithValue("@parmbarcodescanning", "");
                com.CommandType = CommandType.StoredProcedure;
                com.CommandText = query;
                com.ExecuteNonQuery();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString() + "XYZ");
            }
            con.Close();
        }

        void addbyBarcode()
        {
            SqlConnection con = Database.getConnection();
            con.Open();
            string query = "sp_AddBranchOrderByBarcode";
            try
            {
                SqlCommand com = new SqlCommand(query, con);
                com.Parameters.AddWithValue("@parmdevno", txtdevno.Text);
                com.Parameters.AddWithValue("@parmrefno", txtrefno.Text);
                com.Parameters.AddWithValue("@parmpono", txtponum.Text);
               
                com.Parameters.AddWithValue("@parmbarcode", txtsku.Text);
                com.Parameters.AddWithValue("@parmbranchcode", txtbrcode.Text); //initiating branhc
                com.Parameters.AddWithValue("@parmorigin", Login.assignedBranch);
                com.Parameters.AddWithValue("@preparedby", Login.Fullname); 
                com.CommandType = CommandType.StoredProcedure;
                com.CommandText = query;
                com.ExecuteNonQuery();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString() + "XYZ");
            }
            con.Close();
        }

        private void simpleButton3_Click(object sender, EventArgs e)
        {
            returnOrder();
            displayForDelivery();
        }

        void ConfirmBranchOrder()
        {
            SqlConnection con = Database.getConnection();
            con.Open();
            string query = "sp_ConfirmBranchOrderSTS";
            try
            {
                SqlCommand com = new SqlCommand(query, con);
                com.Parameters.AddWithValue("@parmdevno", txtdevno.Text);
                com.Parameters.AddWithValue("@parmrefno", txtrefno.Text);
                com.Parameters.AddWithValue("@parmeffectivitydate", txteffectivedate.Text);
                com.Parameters.AddWithValue("@parmpono", txtponum.Text);
                com.Parameters.AddWithValue("@parmbarcode", txtsku.Text);
                com.Parameters.AddWithValue("@parmbranchcode", txtbrcode.Text);
                com.Parameters.AddWithValue("@parmorigin", Login.assignedBranch);
                com.Parameters.AddWithValue("@preparedby", Login.Fullname);
                com.CommandType = CommandType.StoredProcedure;
                com.CommandText = query;
                com.ExecuteNonQuery();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message);
            }
            con.Close();
        }
        void returnOrder()
        {
            SqlConnection con = Database.getConnection();
            con.Open();
            string query = "";
            if(GlobalCache.CompanyName=="JFC")
            {
                query = "sp_CancelDeliveryFIFOJFC";
            }
            else
            {
                query = "sp_CancelDelivery";
            }
            try
            {
                string seqno = Convert.ToInt32(gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "SeqNo")).ToString();
                string prodno = Convert.ToInt32(gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "ProductNo")).ToString();
                string qtydeliv = Convert.ToInt32(gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "QtyDelivered")).ToString();
                SqlCommand com = new SqlCommand(query, con);
                com.Parameters.AddWithValue("@parmdevno", txtdevno.Text);
                com.Parameters.AddWithValue("@parmrefno", txtrefno.Text);
                com.Parameters.AddWithValue("@parmpono", txtponum.Text);
                com.Parameters.AddWithValue("@parmprodno", prodno);
                com.Parameters.AddWithValue("@parmqty", qtydeliv);
                com.Parameters.AddWithValue("@parmbranchcode", txtbrcode.Text);
                com.Parameters.AddWithValue("@parmorigin", Login.assignedBranch);
                com.Parameters.AddWithValue("@preparedby", Login.Fullname);
                com.Parameters.AddWithValue("@parmdevseqno", seqno);
                com.CommandType = CommandType.StoredProcedure;
                com.CommandText = query;
                com.ExecuteNonQuery();
                XtraMessageBox.Show("Successfully Deleted");
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message);
            }
            con.Close();
        }
        void returnOrderByBarcode()
        {
            SqlConnection con = Database.getConnection();
            con.Open();
            string query = "sp_CancelDeliveryByBarcode";
            try
            {
                SqlCommand com = new SqlCommand(query, con);
                com.Parameters.AddWithValue("@parmbranchcode", txtbrcode.Text);
                com.Parameters.AddWithValue("@parmorigin", Login.assignedBranch);
                com.Parameters.AddWithValue("@parmdevno", txtdevno.Text);
                com.Parameters.AddWithValue("@parmrefno", txtrefno.Text);
                com.Parameters.AddWithValue("@parmpono", txtponum.Text);
                com.Parameters.AddWithValue("@parmbarcode", gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "BarcodeNo").ToString());
                com.Parameters.AddWithValue("@preparedby", Login.Fullname);
                com.CommandType = CommandType.StoredProcedure;
                com.CommandText = query;
                com.ExecuteNonQuery();
                XtraMessageBox.Show("Successfully Deleted");
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message);
            }
            con.Close();
        }
        String getProductCategoryCode()
        {
            string str;
            if (isusedSearch == true)
            {
                str = productcategorycode;
            }
            else
            {
                str = Database.getSingleQuery("ProductCategory", "Description='" + txtprodcat.Text.Trim() + "'", "ProductCategoryID");
            }
            return str;
        }

        private void txtcomport_SelectedIndexChanged(object sender, EventArgs e)
        {
            serialPort1.PortName = txtcomport.Text.Trim();
            serialPort1.Open();
            serialPort1.DataReceived += new SerialDataReceivedEventHandler(serialPort1_DataReceived);
            serialPort1.RtsEnable = true;
            serialPort1.DtrEnable = true;
            txtprodcat.Focus();
        }

        private void serialPort1_DataReceived(object sender, SerialDataReceivedEventArgs e)
        {
            try
            {
                weight = serialPort1.ReadExisting();
                if (weight == String.Empty || txtcomport.Text == "")
                {
                    XtraMessageBox.Show("NODATARECEVD");
                    return;
                }
                else
                {
                    string tempweight = weight.Substring(0, 6).Trim(); //01.234
                    if (tempweight.Length == 5)
                    {
                        wieght2 = "0" + tempweight;
                    }
                    else
                    {
                        wieght2 = tempweight;
                    }
                }
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message.ToString() + "CHECK YOUR COMPORT OR RESTART THE WEIGHING SCALE");
            }
        }

        private void txtweight_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
            {
                displayweight();
             
            }
        }

        private void txtproduct_Click(object sender, EventArgs e)
        {
            isusedSearch = false;
            if (txtprodcat.Text == "")
            {
                txtprodcat.Focus();
            }
            else
            {
                Database.displayComboBoxItems("SELECT Description FROM Products WHERE BranchCode='888' AND ProductCategoryCode='" + getProductCategoryCode() + "' ORDER BY Description", "Description", txtproduct);
            }
        }

        private void txtprodcat_SelectedIndexChanged(object sender, EventArgs e)
        {
            txtproduct.Text = "";
            txtproduct.Focus();
            Database.displayComboBoxItems("SELECT * FROM Products WHERE BranchCode='888'  AND ProductCategoryCode='" + getProductCategoryCode() + "' ORDER BY Description", "Description", txtproduct);

        }

        private void simpleButton4_Click(object sender, EventArgs e)
        {
            displayweight();
        }

        private void btnclear_Click(object sender, EventArgs e)
        {
            txtsku.Text = "";
            txtweight.Text = "";
            txtweight.Focus();
        }

        private void simpleButton5_Click(object sender, EventArgs e)
        {
            Barcode.BarcodePrinting bprint = new Barcode.BarcodePrinting();
            bprint.lblmanufdate.Text = DateTime.Now.ToShortDateString();
            bprint.lblprodtype.Text = txtproduct.Text;
            bprint.lbltotalkilos.Text = txtweight.Text;
            bprint.xrBarCode2.Text = txtsku.Text.Trim(); //productcategorycode + primalcode + txtweight.Text.Remove(2, 1);
            ReportPrintTool report = new ReportPrintTool(bprint);
            report.Print();
        }

        private void txtproduct_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
                btnfind.PerformClick();
        }

        private void txtsearch_Click(object sender, EventArgs e)
        {
            HOForms.SearchProducts searchProd = new HOForms.SearchProducts();
            searchProd.ShowDialog(this);
            Database.displayLocalGrid("SELECT * FROM view_CommissaryInventory ORDER BY Description ASC", searchProd.dataGridView1);
            if (HOForms.SearchProducts.isdone == true)
            {
                productcategorycode = HOForms.SearchProducts.prodcode.Substring(0, 2);
                string productcategorydesc = Database.getSingleQuery("ProductCategory", "ProductCategoryID='" + productcategorycode + "'", "Description");
                txtprodcat.Text = productcategorydesc;
                txtproduct.Text = HOForms.SearchProducts.prodname;
                txtweight.Focus();
                HOForms.SearchProducts.isdone = false;
                isusedSearch = true;
                searchProd.Dispose();
            }

        }

        private void searchLookUpEdit1_EditValueChanged(object sender, EventArgs e)
        {
            bool isFifo = Database.checkifExist("SELECT isFifo FROM InventorySettings WHERE isFifo=1");
            if (isFifo == false)
            {
                try
                {
                    GridView view = searchLookUpEdit1.Properties.View;
                    int rowHandle = view.FocusedRowHandle;
                    object value = view.GetRowCellValue(rowHandle, "SeqNo");
                    object valueAvailable = view.GetRowCellValue(rowHandle, "Available");
                    txtseqno.Text = value.ToString();
                    txtweight.Text = valueAvailable.ToString();
                    txtweight.Focus();
                }
                catch (Exception ex)
                {
                    XtraMessageBox.Show(ex.Message.ToString() + "---");
                }
            }
        }

        private void txtproduct_SelectedIndexChanged(object sender, EventArgs e)
        {
            bool isFifo = Database.checkifExist("SELECT isFifo FROM InventorySettings WHERE isFifo=1");
            if (isFifo == false)
            {
                if (barcodescanning.Checked == false)
                {
                    Database.displaySearchlookupEdit("SELECT BranchCode,BranchName FROM Branches", searchLookUpEditBranch, "BranchCode", "BranchCode");
                    searchLookUpEditBranch.Text = Login.assignedBranch;
                    Database.displaySearchlookupEdit("SELECT SequenceNumber as SeqNo,DateReceived,Barcode,Quantity,Available FROM Inventory WHERE Branch='" + searchLookUpEditBranch.Text + "' and isStock=1 and Available > 0  and Product='" + getProductCode() + "'", searchLookUpEdit1, "Barcode", "Barcode");
                    searchLookUpEdit1.Focus();
                }
                else
                {
                    txtbarcodescanning.Focus();
                }
            }
            else
            {
                if (barcodescanning.Checked == false)
                {
                    //OLD
                    //Database.displaySearchlookupEdit("SELECT BranchCode,BranchName FROM Branches", searchLookUpEditBranch, "BranchCode", "BranchCode");
                    //searchLookUpEditBranch.Text = Login.assignedBranch;
                    //Database.displaySearchlookupEdit("SELECT SequenceNumber as SeqNo,DateReceived,Barcode,Quantity,Available FROM Inventory WHERE Branch='" + searchLookUpEditBranch.Text + "' and isStock=1 and Available > 0 and isWarehouse = 1 and Product='" + getProductCode() + "'", searchLookUpEdit1, "Barcode", "Barcode");
                    //searchLookUpEdit1.Focus();
                    txtweight.Focus();
                }
                else
                {
                    txtbarcodescanning.Focus();
                }
            }
        }

        private void gridControl2_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStrip1.Show(gridControl2, e.Location);
        }

        private void printBarcodeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            string qtydel = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "QtyDelivered").ToString();
            Barcode.BarcodePrinting bprint = new Barcode.BarcodePrinting();
            bprint.lblmanufdate.Text = DateTime.Now.ToShortDateString();
            bprint.lblprodtype.Text = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "ProductName").ToString();
            bprint.lbltotalkilos.Text = qtydel;
            bprint.xrBarCode2.Text = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "BarcodeNo").ToString();
            bprint.lblxpirydate.Text = DateTime.Now.AddYears(1).ToShortDateString();
            ReportPrintTool report = new ReportPrintTool(bprint);
            report.Print();
        }

        private void barcodescanning_CheckedChanged(object sender, EventArgs e)
        {
            if (barcodescanning.Checked == true)
            {
                isFifo = false;
                panel2.Visible = true;
                panel4.Visible = false;
                panel3.Visible = false;
                panel1.Visible = false;
                txtbarcodescanning.Focus();
                btnfind.Visible = false;
            }
            else
            {
                //panel2.Visible = false;
                //panel3.Visible = true;
                //panel1.Visible = true;
                //btnfind.Visible = true;
                barcodescanning.Checked = false;
                panel1.Visible = false;
                panel2.Visible = false;
                panel3.Visible = false;
                panel4.Visible = true;
            }
        }

        private void txtbarcodescanning_KeyDown(object sender, KeyEventArgs e)
        {
            ///OLD
            if (e.KeyCode == Keys.Enter)
            {
                try
                {
                    string pcode = "", qty = "", barcode = "";// qty1 = "", qty2 = "";desc = "",
                    var rows = Database.getMultipleQuery($"SELECT TOP(1) Product,Available FROM dbo.Inventory WHERE Branch='{Login.assignedBranch}' AND Barcode='{txtbarcodescanning.Text}' AND Available > 0 AND isWarehouse=1 ", "Product,Available");

                    pcode = rows["Product"].ToString();
                    qty = rows["Available"].ToString();
                    barcode = txtbarcodescanning.Text;

                    globalproductcode = pcode;
                    txtweight.Text = qty;
                    txtweight.Focus();
                    displayweight();
                    btnadd.PerformClick();
                    txtbarcodescanning.Text = "";
                    txtbarcodescanning.Focus();
                }catch(Exception ex)
                {
                    BigAlert.Show("BARCODE SCANINNG ERROR", ex.Message.ToString(), MessageBoxIcon.Error);
                }
                //////////////////////////////////////////////////////////////////////////////////////////////////////////////////
            }
        }

        private void simpleButton7_Click(object sender, EventArgs e)
        {
            bool confirm = HelperFunction.ConfirmDialog("Are you sure you want to print all barcodes?", "Print All Barcode");
            if (confirm)
            {
                for (int i = 0; i <= gridView2.RowCount - 1; i++)
                {
                    //string qtydel = gridView2.GetRowCellValue(i, "QtyDelivered").ToString();
                    Barcode.BarcodePrinting bprint = new Barcode.BarcodePrinting();
                    bprint.lblmanufdate.Text = DateTime.Now.ToShortDateString();
                    bprint.lblprodtype.Text = gridView2.GetRowCellValue(i, "ProductName").ToString();
                    bprint.lbltotalkilos.Text = gridView2.GetRowCellValue(i, "QtyDelivered").ToString();
                    bprint.xrBarCode2.Text = gridView2.GetRowCellValue(i, "BarcodeNo").ToString();
                    bprint.lblxpirydate.Text = DateTime.Now.AddYears(1).ToShortDateString();
                    ReportPrintTool report = new ReportPrintTool(bprint);
                    //report.ShowRibbonPreviewDialog();
                    report.Print();
                }
            }
            else
            {
                return;
            }
        }

        private void simpleButton8_Click(object sender, EventArgs e)
        {
            Orders.OrderCheckerDevEx oread = new Orders.OrderCheckerDevEx();

            Database.display("SELECT ProductName,Qty FROM TransferOrderDetails WHERE PONumber='" + txtponum.Text + "'", oread.gridControlDelivByComm, oread.gridViewDelivByComm);
            Database.display("SELECT ProductName,QtyDelivered FROM DeliveryDetails WHERE PONumber='" + txtponum.Text + "'", oread.gridControlActualRcvd, oread.gridViewActualRcvd);
            Database.display("SELECT ProductName,Qty FROM TransferOrderDetails WHERE ProductCode not in (Select ProductNo FROM DeliveryDetails WHERE PONumber='" + txtponum.Text + "') AND PONumber='" + txtponum.Text + "' ", oread.gridControlMyStsReq, oread.gridViewMyStsReq);

            oread.ShowDialog(this);
        }

        private void simpleButton6_Click(object sender, EventArgs e)
        {
            if (gridView2.RowCount <= 0)
            {
                XtraMessageBox.Show("The System found out that there are no items to be pending!..");
                this.Close();
            }
            else
            {
                ispending = true;
                XtraMessageBox.Show("Transaction Save as Pending!");
                this.Dispose();
            }
        }

        String getProductCode()
        {
            string str;
            str = Database.getSingleQuery("Products", "Description='" + txtproduct.Text.Trim() + "' AND ProductCategoryCode='" + getProductCategoryCode() + "'", "ProductCode");
            return str;
        }

        void displayweight()
        {
            try
            {
                
                int ctr2 = 1;
                decimal quantity;
                string strquantity;
                string productcode = "";
                if (txtcomport.Text == "" || txtcomport.Text == null)
                {
                    XtraMessageBox.Show("Please Select COM-PORT");
                }
                else
                {
                    for (int i = 0; i <= gridView2.RowCount - 1; i++)
                    {
                        ctr2++;
                    }
                    txtweight.Invoke(this.myDelegate, new Object[] { wieght2 });

                    quantity = Decimal.Parse(txtweight.Text);
                    strquantity = String.Format("{0:00.000}", quantity);

                    if (barcodescanning.Checked == true)
                    {
                        productcode = globalproductcode;//Database.getSingleQuery("Inventory", "Barcode='" + globaltxtbarcodescanning + "' and isWarehouse=1 and Available > 0 and Branch='888' and IsStock=1", "Product");
                        txtsku.Text = txtbarcodescanning.Text;
                    }
                    else
                    {
                        productcode = pcode.ToString();//getProductCode();
                                                       //txtsku.Text = Database.getSingleQuery("Products", "BranchCode='" + Login.assignedBranch + "' AND ProductCode='" + pcode + "' ", "Barcode");
                        string barcode = "";
                //        if (GlobalCache.CompanyName=="JFC")
                //        {
                //            if(String.IsNullOrEmpty(referencecode.ToString()))
                //            {
                //                XtraMessageBox.Show("No Reference Code");
                //                return;
                //            }
                //            else
                //            {
                //                barcode = referencecode.ToString();
                //            }
                //        }
                //        else
                //        {
                //            barcode = Database.getSingleResultSet($"SELECT dbo.func_GenerateBarcodeSTS" +
                //$"('{Login.assignedBranch}',0,'{txtponum.Text}','{productcode.ToString()}','{strquantity}','2') ");
                //        }
                        barcode = Database.getSingleResultSet($"SELECT dbo.func_GenerateBarcodeSTS" +
               $"('{Login.assignedBranch}',0,'{txtponum.Text}','{productcode.ToString()}','{strquantity}','2') ");

                        txtsku.Text = barcode;
                       
                        btnadd.Focus();
                    }



                }

            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString() + "ABC");
            }
        }

        void addByFIFO()
        {
            gridControl2.BeginUpdate();
            try
            {
                if (txtsku.Text == "")
                {
                    //XtraMessageBox.Show("Please Input Valid Fields");
                    BigAlert.Show(
                      "BARCODE EMPTY",
                      "Barcode/SKU must not Empty!..",
                      MessageBoxIcon.Warning);
                    return;
                }
                else
                {
                   
                    //    add();
                    addBranchOrder();

                    //gridView2.Columns["SeqNo"].Summary.Clear();
                    //gridView2.Columns["SeqNo"].Summary.Add(DevExpress.Data.SummaryItemType.Count, "SeqNo", "{0}");
                    gridView2.Columns["QtyDelivered"].Summary.Clear();
                    gridView2.Columns["QtyDelivered"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "QtyDelivered", "{0}");

                    displayForDelivery();

                    txtweight.Text = "";
                        txtproduct.Text = "";
                        // EditValue = null re-fires txtsearchlookupproduct_EditValueChanged, which
                        // re-sets pcode/catcode/referencecode/shipmentno from the popup grid's
                        // (possibly stale) focused row -- the explicit nulls below must stay AFTER
                        // this line so they're the last write and actually win.
                        txtsearchlookupproduct.EditValue = null;
                        txtsku.Text = "";
                        pcode = null;
                        catcode = null;
                        referencecode = null;
                        shipmentno = null;
                    txtsearchlookupproduct.Focus();
                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString() + "123");
            }
            gridControl2.EndUpdate();
        }

        void addByBarcodeMethod()
        {
            gridControl2.BeginUpdate();
            try
            {
                if (txtsku.Text == "")
                {
                    //XtraMessageBox.Show("Please Input Valid Fields");
                    BigAlert.Show(
                      "BARCODE EMPTY",
                      "Barcode/SKU must not Empty!..",
                      MessageBoxIcon.Warning);
                    return;
                }
                else
                {
                    //add();
                    addbyBarcode();
                    gridView2.Columns["SeqNo"].Summary.Clear();
                    gridView2.Columns["SeqNo"].Summary.Add(DevExpress.Data.SummaryItemType.Count, "SeqNo", "{0}");
                    gridView2.Columns["QtyDelivered"].Summary.Clear();
                    gridView2.Columns["QtyDelivered"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "QtyDelivered", "{0}");

                    displayForDelivery();
                        txtweight.Text = "";
                        txtproduct.Text = "";
                        // EditValue = null re-fires txtsearchlookupproduct_EditValueChanged, which
                        // re-sets pcode/catcode/referencecode/shipmentno from the popup grid's
                        // (possibly stale) focused row -- the explicit nulls below must stay AFTER
                        // this line so they're the last write and actually win.
                        txtsearchlookupproduct.EditValue = null;
                        txtsku.Text = "";
                        pcode = null;
                        catcode = null;
                        referencecode = null;
                        shipmentno = null;

                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString() + "123");
            }
            gridControl2.EndUpdate();
        }

        private void btnadd_Click(object sender, EventArgs e)
        {
            if(barcodescanning.Checked==true)
            {
                addByBarcodeMethod();
            }
            else
            {
                addByFIFO();
            }
        }

        private void simpleButton9_Click(object sender, EventArgs e)
        {
            txtsku.Text = "";
            txtweight.Text = "";
            txtweight.Focus();
        }

        private void simpleButton10_Click(object sender, EventArgs e)
        {
            Barcode.BarcodePrinting bprint = new Barcode.BarcodePrinting();
            bprint.lblmanufdate.Text = DateTime.Now.ToShortDateString();
            bprint.lblprodtype.Text = txtproduct.Text;
            bprint.lbltotalkilos.Text = txtweight.Text;
            bprint.xrBarCode2.Text = txtsku.Text.Trim(); //productcategorycode + primalcode + txtweight.Text.Remove(2, 1);
            ReportPrintTool report = new ReportPrintTool(bprint);
            report.Print();
        }

        private void btncancel_Click(object sender, EventArgs e)
        {
        
            if(barcodescanning.Checked == true)
            {
                
                if(GlobalCache.CompanyName=="JFC")
                {
                    var barcodeObj = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "BarcodeNo");
                    string barcode = barcodeObj?.ToString() ?? string.Empty; 
                    if (barcode.StartsWith("A01") || barcode.StartsWith("B01"))
                    {
                        returnOrderByBarcode();
                    }
                    else
                    {
                        returnOrder();
                    }
                }
                else
                {
                    returnOrderByBarcode();
                }
            }
            else
            {
                returnOrder();
            }
            displayForDelivery();
        }

        private void simpleButton11_Click(object sender, EventArgs e)
        {
            if (gridView2.RowCount == 0)
            {
                XtraMessageBox.Show("Cant Save no Order to be Processed!");
                BigAlert.Show(
                   "NO STOCKS PROCESS",
                   "No Records Found!...",
                   MessageBoxIcon.Warning);
                return;
            }


            bool confirm = HelperFunction.ConfirmDialog("Are you sure all order has been Processed?", "Save Transaction");
            if (!confirm)
            {
                return;
            }
            else
            {
                ConfirmBranchOrder();
                isdone = true;
                //XtraMessageBox.Show("Transaction Successfully Saved!");
                BigAlert.Show(
                  "SUCCESS",
                  "Transaction Successfully Saved!...",
                  MessageBoxIcon.Information);
                this.Close();
            }
        }

        private void simpleButton1_Click_1(object sender, EventArgs e)
        {
            displayweight();
        }

        private void btnsaveasdraft_Click(object sender, EventArgs e)
        {
            if (gridView2.RowCount <= 0)
            {
                XtraMessageBox.Show("The System found out that there are no items to be pending!..");
                this.Close();
            }
            else
            {
                ispending = true;
                XtraMessageBox.Show("Transaction Save as Pending!");
                this.Dispose();
            }
        }

        private void txtsearchlookupproduct_EditValueChanged(object sender, EventArgs e)
        {
            catcode = null;
            pcode = null;
            referencecode = null;
            shipmentno = null;
            try
            {
                catcode = SearchLookUpClass.getSingleValue(txtsearchlookupproduct, "CategoryCode");
                pcode = SearchLookUpClass.getSingleValue(txtsearchlookupproduct, "ProductCode");
                referencecode = SearchLookUpClass.getSingleValue(txtsearchlookupproduct, "ReferenceCode");
                shipmentno = SearchLookUpClass.getSingleValue(txtsearchlookupproduct, "ShipmentNo");
                txtweight.Focus();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message.ToString() + "---");
            }
        }

        private void btnchecker_Click(object sender, EventArgs e)
        {
            Orders.OrderCheckerDevEx oread = new Orders.OrderCheckerDevEx();

            Database.display("SELECT ProductName,Qty FROM dbo.TransferOrderDetails WHERE PONumber='" + txtponum.Text + "'  ORDER BY ProductCode ", oread.gridControlMyStsReq, oread.gridViewMyStsReq);

            Database.display("SELECT ProductName,QtyDelivered FROM dbo.DeliveryDetails WHERE PONumber='" + txtponum.Text + "' AND Status='PENDING' ORDER BY ProductNo", oread.gridControlDelivByComm, oread.gridViewDelivByComm);
            GridView view = oread.gridControlDelivByComm.FocusedView as GridView;
            view.SortInfo.ClearAndAddRange(new GridColumnSortInfo[] {
                new GridColumnSortInfo(view.Columns["ProductName"],DevExpress.Data.ColumnSortOrder.Ascending)
                }, 1);
            oread.gridViewDelivByComm.ExpandAllGroups();


            GridGroupSummaryItem itez = new GridGroupSummaryItem();
            itez.FieldName = "ProductNo";
            itez.SummaryType = DevExpress.Data.SummaryItemType.Count;
            itez.ShowInGroupColumnFooter = oread.gridViewDelivByComm.Columns["ProductNo"];
            oread.gridViewDelivByComm.GroupSummary.Add(itez);
            oread.gridViewDelivByComm.Focus();

            GridGroupSummaryItem ite = new GridGroupSummaryItem();
            ite.FieldName = "QtyDelivered";
            ite.SummaryType = DevExpress.Data.SummaryItemType.Sum;
            ite.ShowInGroupColumnFooter = oread.gridViewDelivByComm.Columns["QtyDelivered"];
            oread.gridViewDelivByComm.GroupSummary.Add(ite);
            oread.gridViewDelivByComm.Focus();

            oread.gridViewDelivByComm.Columns["QtyDelivered"].Summary.Clear();
            oread.gridViewDelivByComm.Columns["QtyDelivered"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "QtyDelivered", "{0:n2}");


            // Database.display("SELECT ProductName,SUM(QtyDelivered) as TotalKilos,COUNT(distinct BarcodeNo) as TotalBox FROM DeliveryDetails WHERE PONumber='" + txtponum.Text + "' GROUP BY ProductName", oread.gridControlActualRcvd, oread.gridViewActualRcvd);


            oread.ShowDialog(this);
        }

        private void simpleButton2_Click_1(object sender, EventArgs e)
        {
            bool confirm = HelperFunction.ConfirmDialog("Are you sure you want to print all barcodes?", "Print All Barcode");
            if (confirm)
            {
                for (int i = 0; i <= gridView2.RowCount - 1; i++)
                {
                    //string qtydel = gridView2.GetRowCellValue(i, "QtyDelivered").ToString();
                    Barcode.BarcodePrinting bprint = new Barcode.BarcodePrinting();
                    bprint.xrLabel3.Text = "PONumber:";
                    bprint.xrLabel6.Text = "";
                    bprint.lblmanufdate.Text = DateTime.Now.ToShortDateString();
                    bprint.lblprodtype.Text = gridView2.GetRowCellValue(i, "ProductName").ToString();
                    bprint.lbltotalkilos.Text = gridView2.GetRowCellValue(i, "QtyDelivered").ToString();
                    bprint.xrBarCode2.Text = gridView2.GetRowCellValue(i, "BarcodeNo").ToString();
                    bprint.lblxpirydate.Text = DateTime.Now.AddYears(1).ToShortDateString();
                    ReportPrintTool report = new ReportPrintTool(bprint);
                    //report.ShowRibbonPreviewDialog();
                    report.Print();
                }
            }
            else
            {
                return;
            }
        }

        private void simpleButton3_Click_1(object sender, EventArgs e)
        {
            HOForms.SearchProducts searchProd = new HOForms.SearchProducts();
            searchProd.ShowDialog(this);
            Database.displayLocalGrid("SELECT * FROM view_CommissaryInventory ORDER BY Description ASC", searchProd.dataGridView1);
            if (HOForms.SearchProducts.isdone == true)
            {
                productcategorycode = HOForms.SearchProducts.prodcatcode;
                string productcategorydesc = Database.getSingleQuery("ProductCategory", "ProductCategoryID='" + productcategorycode + "'", "Description");
                txtprodcat.Text = productcategorydesc;
                txtproduct.Text = HOForms.SearchProducts.prodname;
                txtweight.Focus();
                HOForms.SearchProducts.isdone = false;
                isusedSearch = true;
                searchProd.Dispose();
            }
        }

    }
}