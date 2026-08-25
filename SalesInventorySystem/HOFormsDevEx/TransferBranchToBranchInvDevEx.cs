using DevExpress.XtraEditors;
using DevExpress.XtraReports.UI;
using SalesInventorySystem.Classes;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Drawing.Printing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class TransferBranchToBranchInvDevEx : Form
    {
        object objprodcode = null;
        object objbrcode = null;
        string globalprodcode = "", globalbranchcode = "";
        // add() clears txtsearchlookupproduct.Text after a successful save, which re-fires
        // EditValueChanged with the popup's FocusedRowHandle still at its invalid sentinel --
        // without this flag, the "no product resolved" warning below would fire spuriously
        // after every successful add, not just on an actual bad selection.
        bool _suppressProductChanged;
        public delegate void AddDataDelegate(String myString);
        public AddDataDelegate myDelegate;
        public string wieght2 = "";
        bool isdone = false;
        public TransferBranchToBranchInvDevEx()
        {
            InitializeComponent();
            HelperFunction.AllowNumbersAndPeriod(txtweight);

        }

        private void TransferBranchToBranchInvDevEx_Load(object sender, EventArgs e)
        {
           
            bool fExst = Database.checkifExist($"SELECT 1 FROM TransferInventoryDetails WHERE TransferNo='{txttransferno.Text}'");
            string getID = Database.getSingleData("TransferInventoryDetails", "TransferNo", $"{txttransferno.Text}", "TransferNo");
            if (fExst)
            {
                txttransferno.Text = getID;
            }
            else
            {
                txttransferno.Text = IDGenerator.getIDNumberSP("sp_GetTransferInventoryNumber", "TransferNo");
            }

            Database.displaySearchlookupEdit($"SELECT DISTINCT Product,Description FROM dbo.Inventory WHERE Branch='{Login.assignedBranch}' and Available > 0", txtsearchlookupproduct, "Description", "Description");
            Database.displaySearchlookupEdit($"SELECT BranchCode,BranchName FROM dbo.Branches ", txtbranch);
            radchanged();
            txtsearchlookupproduct.Focus();
        }

        void radchanged()
        {
            if(radothers.Checked==true)
            {
                panelbranchselection.Visible = true;
            }
            else
            {
                panelbranchselection.Visible = false;
                globalbranchcode = "888";
            }
        }

        private void txtsearchlookupproduct_EditValueChanged(object sender, EventArgs e)
        {
            if (_suppressProductChanged) return;

            objprodcode = SearchLookUpClass.getSingleValue(txtsearchlookupproduct, "Product");
            // getSingleValue() reads Properties.View.FocusedRowHandle, which is only set once
            // the popup grid has actually focused a row (mouse click / arrow-navigate). If the
            // EditValue instead got resolved by typing matching text without ever opening/
            // navigating the popup, FocusedRowHandle stays at its unset sentinel and
            // GetRowCellValue returns null -- objprodcode.ToString() then threw
            // "Object reference not set to an instance of an object", intermittently,
            // depending purely on how the user picked the product. Guard instead of crash.
            if (objprodcode == null)
            {
                globalprodcode = "";
                BigAlert.Show("PRODUCT NOT SELECTED",
                    "Could not resolve the selected product. Please reselect it from the dropdown list (use the mouse or arrow keys to pick a row).",
                    MessageBoxIcon.Warning);
                txtsearchlookupproduct.Focus();
                return;
            }
            globalprodcode = objprodcode.ToString();
            txtweight.Focus();
        }
        void displayweight()
        {
            try
            {

                //int ctr2 = 1;
                decimal quantity;
                string strquantity;
               
                    //for (int i = 0; i <= gridView2.RowCount - 1; i++)
                    //{
                    //    ctr2++;
                    //}
                    //txtweight.Invoke(this.myDelegate, new Object[] { wieght2 });

                    // TryParse instead of Parse -- Parse throws FormatException (uncaught here,
                    // since the only catch below is for SqlException) on empty/invalid input,
                    // e.g. hitting Enter before typing a quantity or after backspacing it out.
                    if (!Decimal.TryParse(txtweight.Text, out quantity))
                    {
                        BigAlert.Show("INVALID QUANTITY", "Please enter a valid quantity.", MessageBoxIcon.Warning);
                        txtweight.Focus();
                        return;
                    }
                    strquantity = String.Format("{0:00.000}", quantity);

                    string barcode = Database.getSingleResultSet($"SELECT dbo.func_GenerateBarcodeReturnTransfer" +
                          $"('{Login.assignedBranch}','{globalbranchcode}','{txttransferno.Text}','{globalprodcode}','{strquantity}') ");
                    txtsku.Text = barcode;
                    btnadd.Focus();
               
                

            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString() + "ABC");
            }
        }
        private void txtweight_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
            {
                btngetweight.PerformClick();
            }
        }

        private void simpleButton2_Click(object sender, EventArgs e)
        {
            Barcode.BarcodePrinting bprint = new Barcode.BarcodePrinting();
            bprint.xrshipno.Text = "TRANSFER#-" + txttransferno.Text;
            bprint.lblmanufdate.Text = DateTime.Now.ToShortDateString();
            bprint.lblprodtype.Text = txtsearchlookupproduct.Text;
            bprint.lbltotalkilos.Text = txtweight.Text;
            bprint.xrpalletno.Text = "n/a";
            bprint.xrsku.Text = globalprodcode;
            bprint.lblxpirydate.Text = DateTime.Now.AddYears(1).ToShortDateString();
            bprint.xrBarCode2.Text = txtsku.Text.Trim();

            ReportPrintTool report = new ReportPrintTool(bprint);

            // Trap if no printer is installed
            if (PrinterSettings.InstalledPrinters.Count > 0)
            {
                try
                {
                    report.Print();
                }
                catch (Exception ex)
                {
                    MessageBox.Show("Printing failed: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
            else
            {
                MessageBox.Show("No printer available. Printing skipped.", "Warning", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        private void btngetweight_Click(object sender, EventArgs e)
        {
            displayweight();
        }
        private void displayForDelivery()
        {
            gridControl2.BeginUpdate();
            Database.display("SELECT SeqNo,ProductNo,ProductName,BarcodeNo,QtyDelivered FROM dbo.TransferInventoryDetails with(nolock) WHERE TransferNo='" + txttransferno.Text + "'  AND Status='PENDING' ORDER BY SeqNo DESC", gridControl2, gridView2);

            gridView2.Columns["ProductNo"].Summary.Clear();
            gridView2.Columns["ProductNo"].Summary.Add(DevExpress.Data.SummaryItemType.Count, "ProductNo", "{0:n2}");
            gridView2.Columns["QtyDelivered"].Summary.Clear();
            gridView2.Columns["QtyDelivered"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "QtyDelivered", "{0:n2}");
            gridControl2.EndUpdate();
        }

        void SPTransferInventory()
        {
            string sourceseqnum = "";
            sourceseqnum = txtseqno.Text;
            SqlConnection con = Database.getConnection();
            con.Open();
            string query = "sp_AddBranchTransferInventory";
            try
            {
                SqlCommand com = new SqlCommand(query, con); 
                com.Parameters.AddWithValue("@parmtransno", txttransferno.Text); 
                com.Parameters.AddWithValue("@parmprodcode", globalprodcode);
                com.Parameters.AddWithValue("@parmqty", txtweight.Text);
                com.Parameters.AddWithValue("@parmbarcode", txtsku.Text);
                com.Parameters.AddWithValue("@parmsourcebranchcode", Login.assignedBranch);
                com.Parameters.AddWithValue("@parmdestbranchcode", globalbranchcode);
                com.Parameters.AddWithValue("@parmaddedby", Login.Fullname);
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

        void add()
        {
            // Defensive second guard -- see txtsearchlookupproduct_EditValueChanged's comment
            // for why objprodcode can be null here (a stale/never-resolved product selection).
            if (objprodcode == null)
            {
                BigAlert.Show("NO PRODUCT", "Please select a product first.", MessageBoxIcon.Warning);
                return;
            }

            if (Convert.ToDouble(txtweight.Text) > Database.getTotalSummation2("Inventory", "Product = '" + objprodcode.ToString() + "' AND Branch='" + Login.assignedBranch + "' AND isWarehouse=1 and Available > 0 ", "Available")) //Database.getTotalSummation("Inventory", "Product", txtsku.Text.Substring(1, 6), "Quantity"))
            {
                string mark = Database.getTotalSummation2("Inventory", "Product = '" + objprodcode.ToString() + "' AND Branch='" + Login.assignedBranch + "' AND isWarehouse=1  and Available > 0 ", "Available").ToString();
                XtraMessageBox.Show("Insuficient Stocks for this Product.. Your Available Quantity is " + mark);
            }
            else
            {
                SPTransferInventory();
                displayForDelivery();
                txtsearchlookupproduct.Focus();
                txtweight.Text = "";
                // Suppressed: clearing Text re-fires EditValueChanged with FocusedRowHandle
                // back at its invalid sentinel (nothing focused in an empty popup), which
                // would otherwise trip the "no product resolved" warning right after a
                // successful add. objprodcode/globalprodcode are reset here directly instead.
                _suppressProductChanged = true;
                txtsearchlookupproduct.Text = "";
                _suppressProductChanged = false;
                objprodcode = null;
                globalprodcode = "";
                txtsku.Text = "";
            }
        }

        private void btnadd_Click(object sender, EventArgs e)
        {
           
            if(radho.Checked==false && radothers.Checked==false)
            {
                XtraMessageBox.Show("Please select Destination for your Transfer!.. ");
                return;
            }
            else if(radothers.Checked && String.IsNullOrEmpty(txtbranch.Text))
            {
                XtraMessageBox.Show("Please Select your Branch Destination ");
                return;
            }
            else
            {
                if (String.IsNullOrEmpty(txtsku.Text))
                {
                    BigAlert.Show("EMPTY SKU",
                        "BARCODE NUMBER MUST NOT EMPTY.. PLEASE RE-PROCESS AGAIN",
                        MessageBoxIcon.Warning);
                    return;
                }
                else
                {
                    btnprintbarcode.PerformClick();
                    add();
                }
            }
        }
        void ConfirmBranchTransferInventory()
        {
            SqlConnection con = Database.getConnection();
            con.Open();
            string query = "sp_ConfirmBranchTransferInventory"; //not yet created
            try
            {
                SqlCommand com = new SqlCommand(query, con);
                com.Parameters.AddWithValue("@parmtransno", txttransferno.Text);
                com.Parameters.AddWithValue("@parmbarcode", txtsku.Text);
                com.Parameters.AddWithValue("@parmsourcebranchcode", Login.assignedBranch);
                com.Parameters.AddWithValue("@parmdestbranchcode", globalbranchcode);
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

        private void txtbranch_EditValueChanged(object sender, EventArgs e)
        {
            objbrcode = SearchLookUpClass.getSingleValue(txtbranch, "BranchCode");
            // Same class of bug as txtsearchlookupproduct_EditValueChanged -- see its comment.
            globalbranchcode = objbrcode?.ToString() ?? "";
        }

        void cancelLine()
        {
            SqlConnection con = Database.getConnection();
            con.Open();
            string query = "sp_CancelTranferInventoryItems";
            try
            {
                SqlCommand com = new SqlCommand(query, con);
             
                com.Parameters.AddWithValue("@parmtransno", txttransferno.Text);
                com.Parameters.AddWithValue("@parmprodno", gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "ProductNo").ToString());
                com.Parameters.AddWithValue("@parmqty", gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "QtyDelivered").ToString());
                com.Parameters.AddWithValue("@parmsourcebranchcode", Login.assignedBranch);
                com.Parameters.AddWithValue("@parmdestbranchcode", globalbranchcode);
                com.Parameters.AddWithValue("@preparedby", Login.Fullname);
                com.Parameters.AddWithValue("@parmseqno", Convert.ToInt32(gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "SeqNo").ToString()));
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

        private void btncancel_Click(object sender, EventArgs e)
        {
            cancelLine();
            displayForDelivery();
        }

        private void radho_CheckedChanged(object sender, EventArgs e)
        {
            radchanged();
        }

        private void radothers_CheckedChanged(object sender, EventArgs e)
        {
            radchanged();
        }

        private void printBarcodeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            string qtydel = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "QtyDelivered").ToString();
            Barcode.BarcodePrinting bprint = new Barcode.BarcodePrinting();
            bprint.xrshipno.Text = "TRANSFER#:" + txttransferno.Text;
            bprint.xrpalletno.Text = "n/a";
            bprint.lblmanufdate.Text = DateTime.Now.ToShortDateString();
            bprint.lblprodtype.Text = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "ProductName").ToString();
            bprint.lbltotalkilos.Text = qtydel;
            bprint.xrBarCode2.Text = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "BarcodeNo").ToString();
            bprint.lblxpirydate.Text = DateTime.Now.AddYears(1).ToShortDateString();
            ReportPrintTool report = new ReportPrintTool(bprint);
            report.Print();
        }

        private void gridControl2_KeyDown(object sender, KeyEventArgs e)
        {
            
        }

        private void gridControl2_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStrip1.Show(gridControl2, e.Location);
        }

        private void txtweight_KeyPress(object sender, KeyPressEventArgs e)
        {
          

        }

        private void simpleButton11_Click(object sender, EventArgs e)
        {
            bool confirm = HelperFunction.ConfirmDialog("Are you sure all order has been Processed?", "Save Transaction");
            if (gridView2.RowCount == 0)
            {
                XtraMessageBox.Show("Cant Save no Order to be Processed!");
                return;
            }else if (!confirm)
            {
                return;
            }
            else
            {
                ConfirmBranchTransferInventory();
                isdone = true;
                XtraMessageBox.Show("Transaction Successfully Saved!");
                this.Close();
            }
        }
    }
}
