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
using System.IO.Ports;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace SalesInventorySystem
{
    public partial class AddBranchOrder : DevExpress.XtraEditors.XtraForm
    {
        public delegate void AddDataDelegate(String myString);
        public AddDataDelegate myDelegate;
        private String weight;
        public string wieght2 = "";
        public static bool isdone = false,ispending=false;
        string productcategorycode="";
        string primalproductcode="";
        string globaltxtbarcodescanning = "",globalproductcode="";
        bool isFifo = Database.checkifExist("SELECT isFifo FROM InventorySettings WHERE isFifo=1");
        object pcode, catcode, referencecode, shipmentno;
        // string reamrks = "", specialprice = "", sellingprice = "";
        public AddBranchOrder()
        {
            InitializeComponent();
            HelperFunction.AllowNumbersAndPeriodDevEx(txtweight);
            serialPort1.WriteTimeout = 500;
            serialPort1.ReadTimeout = 500;
            this.myDelegate = new AddDataDelegate(AddDataMethod);
        }
        public void AddDataMethod(String myString)
        {
            txtweight.Text += myString;
        }
        
        private void AddBranchOrder_Load(object sender, EventArgs e)
        {
            
            getAvailablePort();

            if(isFifo==true)
            {
                barcodescanning.Checked = false;
                panel1.Visible = false;
                panel2.Visible = false;
                panel4.Visible = true;
            }
            else
            {
                barcodescanning.Checked = true;
                panel1.Visible = false;
                panel2.Visible = true;
                panel4.Visible = false;
            }

            bool fExst = Database.checkifExist("SELECT TOP 1 PONumber FROM DeliveryDetails WHERE PONumber='" + ViewBranchOrder.ponumber + "'");
            string getID=Database.getSingleData("DeliveryDetails","PONumber",ViewBranchOrder.ponumber,"DeliveryNo");
            if (fExst)
            {
                txtdevno.Text = getID;
            }
            else
            {
                txtdevno.Text = IDGenerator.getIDNumberSP("sp_GetDeliveryNumber", "DeliveryNumber");
            }
           
            txtcomport.Focus();

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
            if (keyData == Keys.F5)
            {
                btnchecker.PerformClick();
            }
            return functionReturnValue;
        }
        /*****************************************NEW*****************************/
        private void getAvailablePort()
        {
            string[] ports = SerialPort.GetPortNames();
            txtcomport.Properties.Items.AddRange(ports);
        }

        /*****************************************NEW*****************************/

        private void txtsku_KeyDown(object sender, KeyEventArgs e)
        {
            //bool isExist = Database.checkifExist("SELECT TOP 1 BarcodeNo FROM DeliveryDetails WHERE BarcodeNo='" + txtsku.Text + "'");
            btnadd.PerformClick();
        }

        private void displayForDelivery()
        {
            gridControl2.BeginUpdate();
            //     Database.display("SELECT QtyDelivered,BarcodeNo,ProductNo,ProductName,FORMAT(Cost,'N','en-us')AS Cost,SequenceNo FROM DeliveryDetails WHERE DeliveryNo='" + txtdevno.Text + "'", gridControl2, gridView2);

            if(GlobalCache.CompanyName=="JFC")
            {

                Database.display($"SELECT * FROM dbo.funcview_ProcessOrderItemsSales('{txtponum.Text}')  ORDER BY SeqNo ASC", gridControl2, gridView2);
            }
            else
            {
                Database.display("SELECT SeqNo" +
               ",ProductNo" +
               ",ProductName" +
               ",BarcodeNo" +
               ",QtyDelivered " +
               "FROM DeliveryDetails " +
               "WHERE DeliveryNo='" + txtdevno.Text + "' " +
               "AND Status='PENDING' AND isCancelled=0 ORDER BY SeqNo ASC", gridControl2, gridView2);
            }
           

            //gridView2.Columns["SeqNo"].Visible = false;
            gridView2.Columns["ProductNo"].Summary.Clear();
            gridView2.Columns["ProductNo"].Summary.Add(DevExpress.Data.SummaryItemType.Count, "ProductNo", "{0:n2}");
            gridControl2.EndUpdate();
        }

        private void add()
        {
            if (barcodescanning.Checked == true)
            {
                addbyBarcode();
            }
            else
            {
                addBranchOrder();
            }
        }

        void addBranchOrder()
        {
            string sourceseqnum = "";
            sourceseqnum = txtseqno.Text;
            SqlConnection con = Database.getConnection();
            con.Open();
            string query = "sp_AddBranchOrderHRI";
            if (GlobalCache.CompanyName == "JFC") { query = "sp_AddBranchOrderHRI_JFC"; }
            try
            {
                SqlCommand com = new SqlCommand(query, con);
                com.Parameters.AddWithValue("@parmdevno", txtdevno.Text);
                com.Parameters.AddWithValue("@parmrefno", txtrefno.Text);
                com.Parameters.AddWithValue("@parmpono", txtponum.Text);
                com.Parameters.AddWithValue("@parmprodcatcode", productcategorycode);
                com.Parameters.AddWithValue("@parmprodcode", primalproductcode);

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
            string query = "sp_AddHRIOrderByBarcode";
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

        void ConfirmBranchOrder()
        {
            SqlConnection con = Database.getConnection();
            con.Open();
            string query = "sp_ConfirmBranchOrder";
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
        

        private void txtsku_KeyPress(object sender, KeyPressEventArgs e)
        {
            if (!char.IsControl(e.KeyChar) && !char.IsDigit(e.KeyChar))
            {
                e.Handled = true;
            }
        }

        void returnOrder()
        {
            SqlConnection con = Database.getConnection();
            con.Open();
            string query = "sp_CancelDelivery";
            if (GlobalCache.CompanyName == "JFC")
            {
                query = "sp_CancelDeliveryFIFOJFC";
            }
            else
            {
                query = "sp_CancelDelivery";
            }
            try
            {
                string prodno = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "ProductNo").ToString();
                string qtydeliv = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "QtyDelivered").ToString();
                string seqno = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "SeqNo").ToString();

                SqlCommand com = new SqlCommand(query, con);
                com.Parameters.AddWithValue("@parmdevno", txtdevno.Text);
                com.Parameters.AddWithValue("@parmrefno", txtrefno.Text);
                com.Parameters.AddWithValue("@parmpono", txtponum.Text);
                com.Parameters.AddWithValue("@parmprodno", prodno);
                com.Parameters.AddWithValue("@parmqty", qtydeliv);
                com.Parameters.AddWithValue("@parmbranchcode", txtbrcode.Text);
                com.Parameters.AddWithValue("@parmorigin", Login.assignedBranch);
                com.Parameters.AddWithValue("@preparedby", Login.isglobalUserID);
                com.Parameters.AddWithValue("@parmdevseqno", Convert.ToInt32(seqno));
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

        void displayweight()
        {
            try
            {
                bool isBarcodeLong = false;
                isBarcodeLong = Database.checkifExist("SELECT isLong FROM BarcodeSettings WHERE isLong=1");
                int ctr2 = 1;
                decimal quantity;
                string strquantity;
                string productcode = "";
                if (txtcomport.Text == "")
                {
                    XtraMessageBox.Show("Please Select COM-PORT");
                }
                else
                {
                    for (int i = 0; i <= gridView2.RowCount - 1; i++)
                    {
                        ctr2++;
                    }
                    Random rand = new Random();
                    int ctr = rand.Next(0, 9);
                    txtweight.Invoke(this.myDelegate, new Object[] { wieght2 });

                    quantity = Decimal.Parse(txtweight.Text);
                    strquantity = String.Format("{0:00.000}", quantity);

                    if(barcodescanning.Checked==true)
                    {
                        productcode = globalproductcode;//Database.getSingleQuery("Inventory", "Barcode='" + globaltxtbarcodescanning + "' and isWarehouse=1 and Available > 0 and Branch='888' and IsStock=1", "Product");
                        txtsku.Text = txtbarcodescanning.Text;
                    }
                    else
                    {
                        productcode = pcode?.ToString() ?? "";
                        if (isBarcodeLong == true)
                        {
                            txtsku.Text = "33333" + productcode + strquantity.Replace(".", "") + Classes.Utilities.sequencePadding(ctr2.ToString());
                        }
                        else
                        {
                            txtsku.Text = productcode + strquantity.Replace(".", "") + Classes.Utilities.sequencePadding(ctr2.ToString());
                        }
                        //if (txtsku.Text.Length < 19)
                        //{
                        //    XtraMessageBox.Show("Please Enter Again.. Barcode Length must Greater than or Equal to 19 digits!...");
                        //    return;
                        //}
                        //else
                        //{
                        //    btnadd.Focus();
                        //}
                    }

                    
                   
                }
                btnadd.Focus();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString()+"ABC");
            }
        }

        private void txtcomport_SelectedIndexChanged(object sender, EventArgs e)
        {
            serialPort1.PortName = txtcomport.Text.Trim();
            serialPort1.Open();
            serialPort1.DataReceived += new SerialDataReceivedEventHandler(serialPort1_DataReceived);
            serialPort1.RtsEnable = true;
            serialPort1.DtrEnable = true;
            txtsearchlookupproduct.Focus();
        }

        void serialPort1_DataReceived(object sender, SerialDataReceivedEventArgs e)
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

        private void txtweight_KeyDown_1(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
            {
                displayweight();
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

        private void searchLookUpEditBranch_EditValueChanged(object sender, EventArgs e)
        {
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
            if(barcodescanning.Checked==true)
            {
                isFifo = false;
                panel1.Visible = false;
                panel2.Visible = true;
                panel4.Visible = false;
                txtbarcodescanning.Focus();
            }
            else
            {
                Database.ExecuteQuery("UPDATE InventorySettings SET isFifo=1");
                isFifo = true;
                panel1.Visible = false;
                panel2.Visible = false;
                panel4.Visible = true;
                txtsearchlookupproduct.Focus();
            }
        }

        private void txtbarcodescanning_KeyDown(object sender, KeyEventArgs e)
        {
            ///OLD
            //if (e.KeyCode == Keys.Enter)
            //{
            //    bool isBarcodeLong = false;
            //    isBarcodeLong = Database.checkifExist("SELECT isLong FROM BarcodeSettings WHERE isLong=1");
            //    string pcode = "", desc = "", qty = "", barcode = "", qty1 = "", qty2 = "";
            //    //bool isExist = Database.checkifExist("SELECT * FROM Inventory WHERE Barcode='" + txtbarcodescanning.Text + "' AND isWarehouse=1 AND isStock=1 AND Available > 0 AND Branch='888' ");
            //    //globaltxtbarcodescanning = "";
            //    //globaltxtbarcodescanning = txtbarcodescanning.Text;
            //    //if (isExist)
            //    //{
            //    //    string valueAvailable = Database.getSingleQuery("Inventory", "Barcode='" + txtbarcodescanning.Text + "' and isWarehouse=1 and Available > 0 and Branch='888' and IsStock=1", "Available");
            //    //    txtweight.Text = valueAvailable;
            //    //    txtweight.Focus();
            //    //    displayweight();
            //    //    simpleButton1.PerformClick();
            //    //    txtbarcodescanning.Text = "";
            //    //    txtbarcodescanning.Focus();
            //    //}
            //    //else
            //    //{
            //    //    XtraMessageBox.Show("Barcode Not Exist in Inventory!");
            //    //    return;
            //    //}
            //    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////
            //    globaltxtbarcodescanning = "";
            //    globaltxtbarcodescanning = txtbarcodescanning.Text;
            //    if (isBarcodeLong == false)
            //    {
            //        if (txtbarcodescanning.Text.Length == 14) //tens 10015 10123 0001
            //        {
            //            pcode = txtbarcodescanning.Text.Substring(0, 5);
            //            desc = Database.getSingleQuery("Products", "ProductCode='" + pcode + "' and BranchCode='888'", "Description");
            //            qty1 = txtbarcodescanning.Text.Substring(5, 2); //1001512345
            //            qty2 = txtbarcodescanning.Text.Substring(7, 3);
            //            qty = qty1 + "." + qty2;
            //            barcode = txtbarcodescanning.Text;
            //        }
            //        else if (txtbarcodescanning.Text.Length == 15) //hundred
            //        {
            //            pcode = txtbarcodescanning.Text.Substring(0, 5);
            //            desc = Database.getSingleQuery("Products", "ProductCode='" + pcode + "' and BranchCode='888'", "Description");
            //            qty1 = txtbarcodescanning.Text.Substring(5, 3); //10015100345
            //            qty2 = txtbarcodescanning.Text.Substring(8, 3);
            //            qty = qty1 + "." + qty2;
            //            barcode = txtbarcodescanning.Text;
            //        }
            //        else if (txtbarcodescanning.Text.Length == 16) //thousand
            //        {
            //            pcode = txtbarcodescanning.Text.Substring(0, 5);
            //            desc = Database.getSingleQuery("Products", "ProductCode='" + pcode + "' and BranchCode='888'", "Description");
            //            qty1 = txtbarcodescanning.Text.Substring(5, 4); //10015100345
            //            qty2 = txtbarcodescanning.Text.Substring(9, 3);
            //            qty = qty1 + "." + qty2;
            //            barcode = txtbarcodescanning.Text;
            //        }
            //        else
            //        {
            //            XtraMessageBox.Show("Invalid Barcode Type!.. Please use manual input!..");
            //            return;
            //        }
            //    }else //if barcode is longtype
            //    {
            //        if (txtbarcodescanning.Text.Length == 19) //tens 11111 10015 10123 0001 --10.123 kilos
            //        {
            //            pcode = txtbarcodescanning.Text.Substring(5, 5);
            //            desc = Database.getSingleQuery("Products", "ProductCode='" + pcode + "' and BranchCode='888'", "Description");
            //            qty1 = txtbarcodescanning.Text.Substring(10, 2); //1001512345
            //            qty2 = txtbarcodescanning.Text.Substring(12, 3);
            //            qty = qty1 + "." + qty2;
            //            barcode = txtbarcodescanning.Text;
            //        }
            //        else if (txtbarcodescanning.Text.Length == 20) //hundred 11111 10015 100123 0001 --100.123 kilos
            //        {
            //            pcode = txtbarcodescanning.Text.Substring(5, 5);
            //            desc = Database.getSingleQuery("Products", "ProductCode='" + pcode + "' and BranchCode='888'", "Description");
            //            qty1 = txtbarcodescanning.Text.Substring(10, 3); //10015100345
            //            qty2 = txtbarcodescanning.Text.Substring(13, 3);
            //            qty = qty1 + "." + qty2;
            //            barcode = txtbarcodescanning.Text;
            //        }
            //        else if (txtbarcodescanning.Text.Length == 21) //thousand  11111 10015 1000123 0001 --1000.123 kilos
            //        {
            //            pcode = txtbarcodescanning.Text.Substring(5, 5);
            //            desc = Database.getSingleQuery("Products", "ProductCode='" + pcode + "' and BranchCode='888'", "Description");
            //            qty1 = txtbarcodescanning.Text.Substring(10, 4); //10015100345
            //            qty2 = txtbarcodescanning.Text.Substring(14, 3);
            //            qty = qty1 + "." + qty2;
            //            barcode = txtbarcodescanning.Text;
            //        }
            //        else
            //        {
            //            XtraMessageBox.Show("Invalid Barcode Type!.. Please use manual input!..");
            //            return;
            //        }
            //    }
            //    globalproductcode = pcode;
            //    txtweight.Text = qty;
            //    txtweight.Focus();
            //    displayweight();
            //    btnadd.PerformClick();
            //    txtbarcodescanning.Text = "";
            //    txtbarcodescanning.Focus();
            //    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////
            //}
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
                }
                catch (Exception ex)
                {
                    BigAlert.Show("BARCODE SCANINNG ERROR", ex.Message.ToString(), MessageBoxIcon.Error);
                }
                //////////////////////////////////////////////////////////////////////////////////////////////////////////////////
            }

        }

        private void groupBox2_Enter(object sender, EventArgs e)
        {

        }

        private void btnadd_Click(object sender, EventArgs e)
        {
            gridControl2.BeginUpdate();
            try
            {
                if (txtsku.Text == "")
                {
                    XtraMessageBox.Show("Please Input Valid Fields");
                    return;
                }
                else
                {
                    string qty = txtweight.Text;
                    if (barcodescanning.Checked == false)
                    {
                        primalproductcode = pcode?.ToString() ?? "";
                        productcategorycode = catcode?.ToString() ?? "";
                    }
                    else
                    {
                        primalproductcode = globalproductcode;
                        productcategorycode = primalproductcode.Substring(0, 2);
                    }
                    bool requestedProductExist = false;
                    for (int j = 0; j <= gridView1.RowCount - 1; j++)
                    {
                        if (gridView1.GetRowCellValue(j, "ProductCode").ToString() == primalproductcode)
                            requestedProductExist = true;
                        if (requestedProductExist)
                            break;
                    }
                    bool inventoryExist = Database.checkifExist("SELECT 1 FROM dbo.Inventory WHERE Product='" + primalproductcode + "' AND Branch='" + Login.assignedBranch + "' AND Available > 0 and isWarehouse=1 ");
                    // if ((txtsku.Text.Substring(0, 2).Trim() != getProductCategoryCode()) && barcodescanning.Checked==false)//!isnvalidproduct)
                    //if ((txtsku.Text.Substring(0, 2).Trim() != getProductCategoryCode()) && barcodescanning.Checked == false)//!isnvalidproduct)
                    //{
                    //    XtraMessageBox.Show("Invalid ProductCategoryCode for this Product");
                    //    txtsku.Text = "";
                    //}
                    //else

                    if (!requestedProductExist)
                    {
                        XtraMessageBox.Show("You cant add this Product because it is not available in Purchase Order List!");
                        txtsku.Text = "";
                    }
                    else if (!inventoryExist)
                    {
                        XtraMessageBox.Show("No Product Inventory");
                        txtsku.Text = "";
                    }
                    //else if (GlobalCache.CompanyName == "JFC" && Convert.ToDouble(txtweight.Text) > Database.getTotalSummation2("Inventory", "ShipmentNo='" + (shipmentno?.ToString() ?? "") + "' AND Branch='" + Login.assignedBranch + "' AND Product = '" + primalproductcode + "' and Available > 0 ", "Available")) //Database.getTotalSummation("Inventory", "Product", txtsku.Text.Substring(1, 6), "Quantity"))
                    //{
                    //    BigAlert.Show("INSUFFICENT STOCKS", "Insuficient Stocks for this Product.. Your Available Quantity is ", MessageBoxIcon.Warning);
                    //}
                    //kung imong gi encode na quantity is greater than sa total quantity sa imong Inventory sa commisary
                    else if (GlobalCache.CompanyName != "JFC" && Convert.ToDouble(txtweight.Text) > Database.getTotalSummation2("Inventory", "Product = '" + primalproductcode + "' AND Branch='" + Login.assignedBranch + "' AND isWarehouse='1' and Available > 0 ", "Available")) //Database.getTotalSummation("Inventory", "Product", txtsku.Text.Substring(1, 6), "Quantity"))
                    {
                        string mark = Database.getTotalSummation2("Inventory", "Product = '" + primalproductcode + "' AND Branch='" + Login.assignedBranch + "' AND isWarehouse='1'  and Available > 0 ", "Available").ToString();
                        XtraMessageBox.Show("Insuficient Stocks for this Product.. Your Available Quantity is " + mark);
                    }
                    else
                    {
                        add();
                        displayForDelivery();
                        //if(isFifo==false)
                        //{
                        //    searchLookUpEdit1.Text = "";
                        //}
                        txtweight.Text = "";
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
                        if (barcodescanning.Checked == true)
                        {
                            txtbarcodescanning.Focus();
                        }
                        else
                        {
                            txtsearchlookupproduct.Focus();
                        }
                    }
                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString() + "123");
            }
            gridControl2.EndUpdate();
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
            bprint.lblprodtype.Text = txtsearchlookupproduct.Text;
            bprint.lbltotalkilos.Text = txtweight.Text;
            bprint.xrBarCode2.Text = txtsku.Text.Trim(); //productcategorycode + primalcode + txtweight.Text.Remove(2, 1);
            ReportPrintTool report = new ReportPrintTool(bprint);
            report.Print();
        }

        private void btncancel_Click(object sender, EventArgs e)
        {
            returnOrder();
            displayForDelivery();
        }

        private void simpleButton11_Click(object sender, EventArgs e)
        {
            //bool isnot = Database.checkifExist("SELECT * FROM PurchaseOrderDetails where ProductCode not in (SELECT ProductNo FROM DeliveryDetails WHERE PONumber='" + txtponum.Text + "') and PONumber='" + txtponum.Text + "' ");
            if (gridView2.RowCount == 0)
            {
                XtraMessageBox.Show("Cant Save no Order to be Processed!");
                return;
            }
            //if (isnot == true)
            //{
            //    XtraMessageBox.Show("Cant Proceed there are some items that you need to processed!...");
            //    return;
            //}

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

        private void btnchecker_Click(object sender, EventArgs e)
        {
            Orders.OrderCheckerDevEx oread = new Orders.OrderCheckerDevEx();

            Database.display("SELECT ProductName,Qty FROM PurchaseOrderDetails WHERE PONumber='" + txtponum.Text + "'", oread.gridControlDelivByComm, oread.gridViewDelivByComm);
            Database.display("SELECT ProductName,SUM(QtyDelivered) as TotalKilos,COUNT(distinct BarcodeNo) as TotalBox FROM DeliveryDetails WHERE PONumber='" + txtponum.Text + "' GROUP BY ProductName", oread.gridControlActualRcvd, oread.gridViewActualRcvd);
            Database.display("SELECT ProductName,Qty FROM PurchaseOrderDetails WHERE ProductCode not in (Select ProductNo FROM DeliveryDetails WHERE PONumber='" + txtponum.Text + "') AND PONumber='" + txtponum.Text + "' ", oread.gridControlMyStsReq, oread.gridViewMyStsReq);

            oread.ShowDialog(this);
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

        private void simpleButton1_Click_1(object sender, EventArgs e)
        {
            displayweight();
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

        private void simpleButton2_Click_1(object sender, EventArgs e)
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

    }
}