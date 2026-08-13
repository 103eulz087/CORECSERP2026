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
using DevExpress.XtraGrid;
using SalesInventorySystem.Classes;
using System.IO;
using DevExpress.XtraGrid.Views.Grid;
using DevExpress.XtraGrid.Columns;
using DevExpress.XtraReports.UI;

namespace SalesInventorySystem
{
    public partial class ReInventoryIn : DevExpress.XtraEditors.XtraForm
    {
        //DataTable table;
        object brcode = null,prodcode=null,brcodetab2=null;
        public static bool ispriceused = false, isusedbarcode = false;
        bool isusedsearchform = false;//, isusedbarcode = false;//, ispriceused=false;
        public static string seqno = "",branchcode="";
        public static bool iswarehouse = false;
        public ReInventoryIn()
        {
            InitializeComponent();
        }
        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            bool functionReturnValue = false;
            //if (keyData == Keys.Enter)
            //{
            //    simpleButton1.PerformClick();
            //}
            if (keyData == Keys.F1)
            {
                simpleButton6.PerformClick();
            }
            else if (keyData == Keys.F2)
            {
                btnclear.PerformClick();
            }
            else if (keyData == Keys.Delete)
            {
                simpleButton3.PerformClick();
            }
            else if (keyData == Keys.Down)
            {
                gridView1.Focus();
            }
            return functionReturnValue;
        }

      
        void display()
        {
            Database.display("SELECT * " +
                $"FROM dbo.funcview_InventoryIN('{txtid.Text}') ORDER BY SequenceNumber ASC", gridControl1, gridView1);

            GridGroupSummaryItem ite = new GridGroupSummaryItem();
            ite.FieldName = "Quantity";
            ite.SummaryType = DevExpress.Data.SummaryItemType.Sum;
            ite.ShowInGroupColumnFooter = gridView1.Columns["Quantity"];
            gridView1.GroupSummary.Add(ite);
            gridView1.Focus();

            Classes.DevXGridViewSettings.ShowFooterCountTotal(gridView1, "SequenceNumber");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView1, "Quantity");
        }

        void displayTab2()
        {
            Database.display("SELECT * " +
                //$"FROM dbo.funcview_InventoryINManualEntry('{tab2batchid.Text}') ORDER BY SequenceNumber ASC", gridControltab2, gridViewtab2);
                $"FROM dbo.funcview_InventoryINManualEntry('{tab2batchid.Text}') ORDER BY SequenceNumber ASC", gridControltab2, gridView4);

            GridGroupSummaryItem ite = new GridGroupSummaryItem();
            ite.FieldName = "Quantity";
            ite.SummaryType = DevExpress.Data.SummaryItemType.Sum;
            ite.ShowInGroupColumnFooter = gridView4.Columns["Quantity"];
            //ite.ShowInGroupColumnFooter = gridViewtab2.Columns["Quantity"];
            //gridViewtab2.GroupSummary.Add(ite);
            //gridViewtab2.Focus();
            gridView4.GroupSummary.Add(ite);
            gridView4.Focus();
            
            //Classes.DevXGridViewSettings.ShowFooterTotal(gridViewtab2, "Quantity");
        }

        private void ReInventoryIn_Load(object sender, EventArgs e)
        { 
            string branchname = Database.getSingleQuery("Branches", "BranchCode='" + Login.assignedBranch + "'", "BranchName");
            Database.displaySearchlookupEdit("SELECT ProductCode,Description FROM Products WHERE BranchCode='888' order by Description", txtproduct, "Description", "Description");
            loadInvNum();
            populateBranch();
            txtbarcodescanning.Focus();
        }
            

        void loadInvNum()
        {
            txtid.Text = IDGenerator.getIDNumberSP("sp_GetInventoryINNumber", "InventoryID"); //IDGenerator.getInventoryINNumber();

        }

        void populateBranch()
        {
           
            Database.displaySearchlookupEdit("Select BranchCode,BranchName FROM Branches", txtbranch,"BranchName","BranchName");
            Database.displaySearchlookupEdit("Select BranchCode,BranchName FROM Branches", tab2brcode,"BranchName","BranchName");
        }

     

        private void simpleButton1_Click(object sender, EventArgs e)
        {
            if(String.IsNullOrEmpty(txtbranch.Text))
            {
                XtraMessageBox.Show("Branch must not empty");
                return;
            }
            else
            {
                AddEntryNew();
            }
        }


        private void btnclear_Click(object sender, EventArgs e)
        {
            seqno = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SequenceNumber").ToString();
            string desc = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "Description").ToString();
            string qty = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "Quantity").ToString();
            string cost = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "Cost").ToString();
            ReInventoryInEditLine editln = new ReInventoryInEditLine();
            editln.txtprodname.Text = desc;
            editln.txtqty1.Text = qty;
            editln.txtcost.Text = cost;
            editln.ShowDialog(this);
            if (ReInventoryInEditLine.isdone == true)
            {
                display();
                ReInventoryInEditLine.isdone = false;
                editln.Dispose();
                gridView1.MoveLast();
            }
            txtbarcodescanning.Focus();
            
        }

        private void simpleButton3_Click(object sender, EventArgs e)
        {
             //Database.ExecuteQuery("DELETE FROM InventoryIN WHERE SequenceNumber='" + gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SequenceNumber").ToString() + "'");
            Database.ExecuteQuery("DELETE FROM InventoryINMonthEnd WHERE SequenceNumber='" + gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SequenceNumber").ToString() + "'");
            display();
            txtbarcodescanning.Focus();
        }

        void recoverInventoryNew()
        {
            ReInventoryINRecovery revin = new ReInventoryINRecovery();
            revin.ShowDialog(this);
            if (ReInventoryINRecovery.isdone == true)
            {
                bool checkfirst = Database.checkifExist("SELECT ID FROM [InventoryINMonthEnd] WHERE ID = '" + ReInventoryINRecovery.id + "'");
                if (checkfirst)
                {
                    Database.display("SELECT * FROM [InventoryINMonthEnd] WHERE ID='" + ReInventoryINRecovery.id + "'", gridControl1, gridView1);
                    txtid.Text = ReInventoryINRecovery.id;
                }
                else
                {
                    XtraMessageBox.Show("Inventory ID Not Exist in Temporary Container, This Number is either not exist OR it is already Uploaded in Inventory Table");
                    return;
                }
                ReInventoryINRecovery.isdone = false;
                revin.Dispose();
            }
        }

        //NOT USED
        void recoverInventory()
        {
            ReInventoryINRecovery revin = new ReInventoryINRecovery();
            revin.ShowDialog(this);
            if (ReInventoryINRecovery.isdone == true)
            {
                bool checkfirst = Database.checkifExist("SELECT ID FROM TempInventoryIN WHERE ID = '" + ReInventoryINRecovery.id + "'");
                if (checkfirst)
                {
                    Database.display("SELECT * FROM TempInventoryIN WHERE ID='" + ReInventoryINRecovery.id + "'", gridControl1, gridView1);
                    txtid.Text = ReInventoryINRecovery.id;
                }
                else
                {
                    XtraMessageBox.Show("Inventory ID Not Exist in Temporary Container, This Number is either not exist OR it is already Uploaded in Inventory Table");
                    return;
                }
                ReInventoryINRecovery.isdone = false;
                revin.Dispose();
            }
        }
        private void simpleButton4_Click(object sender, EventArgs e)
        {
            recoverInventoryNew();
        }
        void save()
        {
            SqlConnection con = Database.getConnection();
            con.Open();
            int ctr = gridView1.RowCount - 1;
            try
            {
                string query = "sp_UploadTempInventoryIN";
                SqlCommand com = new SqlCommand(query, con);
                com.Parameters.AddWithValue("@parmid", txtid.Text);
                com.Parameters.AddWithValue("@parmuser", Login.isglobalUserID);
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

            XtraMessageBox.Show("Successfully Added!");
            this.Dispose();
        }

        void export()
        {
            if (gridView1.Focus())
            {
                string filename = "MONTHEND_REINVENTORY" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + "_" + txtid.Text;
                HelperFunction.exporttoexcel(gridView1, filename);
                BigAlert.Show("SUCCESS", "SUCCESFULLY EXPORTED!, Please check in Drive C:/MyFiles/", MessageBoxIcon.Information);
            }
        }

        private void simpleButton2_Click(object sender, EventArgs e)
        {
            export();
            Commit();
        }

        private void txtbarcodescanning_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
                simpleButton1.PerformClick();
        }

        private void simpleButton6_Click(object sender, EventArgs e)
        {
            searchProductItems();
        }

        private void btnanalyze_Click(object sender, EventArgs e)
        {
            bool confirm = HelperFunction.ConfirmDialog("This function is need to Authorized by Inventory Admin.. Are you Sure you want to Proceed?...", "Confirm");
            if (confirm)
            {
                AuthorizedConfirmationFrm authfrm = new AuthorizedConfirmationFrm();
                authfrm.ShowDialog(this);
                if (AuthorizedConfirmationFrm.isconfirmedLogin == true)
                {
                    branchcode = brcode.ToString();
                    ReInventoryAnalyzer asd = new ReInventoryAnalyzer();
                    asd.Show();
                    analyze();
                    //asd.ShowDialog(this);
                    if (POS.POSErrrorCorrect.isdone == true)
                    {
                        POS.POSErrrorCorrect.isdone = false;
                        asd.Dispose();
                    }
                    AuthorizedConfirmationFrm.isconfirmedLogin = false;
                    authfrm.Dispose();
                }
            }
            else
            {
                return;
            }
        }


        void analyze()
        {
            ReInventoryAnalyzer asd = new ReInventoryAnalyzer();
            asd.Show();
            SqlConnection con = Database.getConnection();
            con.Open();
            asd.gridControl1.BeginUpdate();
            try
            {
                string sp = "sp_ReInventoryAnalyzer";
                SqlCommand com = new SqlCommand(sp, con);
                com.Parameters.AddWithValue("@parmbatchid", txtid.Text);
                com.Parameters.AddWithValue("@parmbranchcode",brcode.ToString());
                com.CommandType = CommandType.StoredProcedure;
                com.CommandTimeout = 3600;
                com.CommandText = sp;
                SqlDataAdapter adapter = new SqlDataAdapter(com);
                DataTable table = new DataTable();
                asd.gridView1.Columns.Clear();
                asd.gridControl1.DataSource = null;
                adapter.Fill(table);
                asd.gridControl1.DataSource = table;
                asd.gridView1.BestFitColumns();

                GridGroupSummaryItem ite = new GridGroupSummaryItem();
                ite.FieldName = "Qty";
                ite.SummaryType = DevExpress.Data.SummaryItemType.Sum;
                ite.ShowInGroupColumnFooter = asd.gridView1.Columns["Qty"];
                asd.gridView1.GroupSummary.Add(ite);
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
            finally
            {
                asd.gridControl1.EndUpdate();
                con.Close();
            }
        }
        
        void searchProductItems()
        {
            try
            {
                SearchProductItems searchprod = new SearchProductItems();
                searchprod.ShowDialog(this);
                if (SearchProductItems.isUsedSearchForm == true) //isUsedSearchForm indicator ni cya sa searchproduct form kng nigamit ba cya og searchform
                {
                    isusedsearchform = true; //is isusedsearchform is a local variable declare in this class
                    if (SearchProductItems.havebarcode == true) //kng pag select nya kay naay barcode
                    {
                        txtbarcodescanning.Text = SearchProductItems.barcode; // 
                        isusedbarcode = true;
                        SearchProductItems.isUsedSearchForm = false;
                    }
                    else //kung pag select nya sa item sa search product kay wlaay barcode
                    {
                        //txtbarcodescanning.Text = SearchProduct.prodcode.Substring(0, 2) + SearchProduct.prodcode + SearchProduct.qty.Replace(".", "");
                        txtbarcodescanning.Text = SearchProductItems.prodcode;
                        isusedbarcode = false;
                        SearchProductItems.isUsedSearchForm = false;
                    }
                    //SearchProduct.isUsedSearchForm = false; public static bool ispriceused=false,isusedbarcode=false;
                    //ispriceused = SearchProduct.priceused;
                    searchprod.Dispose();
                    txtbarcodescanning.Focus();
                }
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }
        public static async Task PlayNotificationSoundAsync(string soundFilePath)
        {
            // Use Task.Run to offload the sound loading and playback logic to a background thread.
            // This prevents the main UI thread from becoming unresponsive, even if the sound file
            // is large or there are delays in accessing it.
            await Task.Run(() =>
            {
                try
                {
                    // 1. Check if the specified sound file actually exists.
                    if (!File.Exists(soundFilePath))
                    {
                        Console.WriteLine($"Error: Sound file not found at '{soundFilePath}'. Please verify the path.");
                        // Optionally, you could play a default system sound here if the file is missing.
                        // SystemSounds.Exclamation.Play();
                        return; // Exit the method if the file is not found.
                    }

                    // 2. Create a new SoundPlayer instance with the provided file path.
                    // The 'using' statement ensures that the SoundPlayer object is properly
                    // disposed of after it's no longer needed, releasing system resources.
                    using (System.Media.SoundPlayer player = new System.Media.SoundPlayer(soundFilePath))
                    {
                        // 3. Load the sound into memory. This operation can be synchronous
                        // but since it's inside Task.Run, it won't block the main thread.
                        player.Load();

                        // 4. Play the sound. The Play() method plays the sound asynchronously
                        // on an internal thread managed by SoundPlayer, and returns immediately.
                        player.Play();

                        //Console.WriteLine($"Notification: Playing sound from '{soundFilePath}'");
                    }
                }
                // 5. Implement robust error handling for common issues.
                catch (FileNotFoundException)
                {
                    Console.WriteLine($"Error: The sound file was not found at '{soundFilePath}'. Double-check the file path and ensure it's accessible.");
                }
                catch (InvalidOperationException ex)
                {
                    // This typically occurs if the sound file is not a valid .wav format
                    // or if there's an issue with the audio device.
                    Console.WriteLine($"Error playing sound from '{soundFilePath}': {ex.Message}. Ensure the file is a valid .wav format and your audio device is working.");
                }
                catch (Exception ex)
                {
                    // Catch any other unexpected errors during sound playback.
                    Console.WriteLine($"An unexpected error occurred while attempting to play sound from '{soundFilePath}': {ex.Message}");
                }
            });
        }

        private void Commit()
        {
            if (gridView1.RowCount == 0)
            {
                //XtraMessageBox.Show("Nothing to save.");
                BigAlert.Show(
                 "NOTHING TO SAVE",
                 "No items to be transferred",
                 MessageBoxIcon.Warning);
                return;
            }
           
         
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.sp_CommitReInventoryIN", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@parmid", SqlDbType.Int).Value = int.Parse(txtid.Text);

                try
                {
                    con.Open();
                    cmd.ExecuteNonQuery();
                    //XtraMessageBox.Show("Inventory successfully transferred.");
                    BigAlert.Show(
                          "SUCCESS",
                          "Inventory successfully transferred!..",
                          MessageBoxIcon.Information);
                    this.Dispose();
                }
                catch (SqlException ex)
                {
                    //XtraMessageBox.Show(ex.Message, "Commit failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    BigAlert.Show(
                         "COMMIT FAILED",
                         ex.Message.ToString(),
                         MessageBoxIcon.Error);
                    display(); // show which lines are error/processed
                }
            }
        }

        async void AddEntryNew() //STAGING
        {
            if (string.IsNullOrWhiteSpace(txtbarcodescanning.Text))
            {
                //XtraMessageBox.Show("Please scan or enter a barcode.");
                BigAlert.Show(
                  "BARCODE EMPTY",
                  "Please scan or enter a barcode.",
                  MessageBoxIcon.Warning);
                txtbarcodescanning.Focus();
                return;
            }

         
            using (var con = Database.getConnection()) // assumes your helper returns SqlConnection
            using (var cmd = new SqlCommand("dbo.sp_StageBarcodeForReInventoryIN", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@parmid", SqlDbType.Int).Value = int.Parse(txtid.Text);
                cmd.Parameters.Add("@parmbranch", SqlDbType.VarChar, 5).Value = brcode.ToString();
                cmd.Parameters.Add("@parmbarcode", SqlDbType.VarChar, 120).Value = txtbarcodescanning.Text.Trim();
                cmd.Parameters.Add("@parmuser", SqlDbType.VarChar, 50).Value = Login.isglobalUserID; 

                try
                {
                    con.Open();
                    cmd.ExecuteNonQuery();
                    display();
                    gridView1.BestFitColumns(); 

                }
                catch (SqlException ex)
                {

                    await PlayNotificationSoundAsync(Application.StartupPath + "\\error.wav");
                    //XtraMessageBox.Show(ex.Message, "Stage failed", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    BigAlert.Show(
                     "STAGE FAILED",
                     ex.Message.ToString(),
                     MessageBoxIcon.Error);
                }
            }
            gridView1.MoveLast();
            txtbarcodescanning.Text = "";
            txtbarcodescanning.Focus();
        }

        private void txtproduct_EditValueChanged(object sender, EventArgs e)
        {
            prodcode = SearchLookUpClass.getSingleValue(txtproduct, "ProductCode");
            txtqty.Text = "";
            txtqty.Focus();
        }
        void displaSKU()
        {
            try
            {
                decimal quantity;
                string strquantity;
                string productcode = "";     
                quantity = Decimal.Parse(txtqty.Text);
                strquantity = String.Format("{0:00.000}", quantity);
                productcode = prodcode.ToString();//getProductCode();
                                                   //txtsku.Text = Database.getSingleQuery("Products", "BranchCode='" + Login.assignedBranch + "' AND ProductCode='" + pcode + "' ", "Barcode");
                string barcode = "";
                    
                barcode = Database.getSingleResultSet($"SELECT dbo.[func_GenerateBarcodeReInventoryIN]" +
                                                            $"('{txtid.Text}','{productcode}','{strquantity}' ) ");
                txtsku.Text = barcode;
                tab2AddBtn.Focus();

            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString() + "ABC");
            }
        }
        private void txtqty_KeyDown(object sender, KeyEventArgs e)
        {
            if(e.KeyCode == Keys.Enter)
            {
                displaSKU();
            }
        }

        private void tab2btnnew_Click(object sender, EventArgs e)
        {
            tab2batchid.Text = IDGenerator.getIDNumberSP("sp_GetInventoryINNumber", "InventoryID");
            txtproduct.Enabled = true;
            txtqty.Enabled = true;
            txtsku.Enabled = true;
            tab2btnnew.Enabled = false;
        }


        void addManualInventory()
        {
            bool isWarehouse = false;
            if(tab2radbigblue.Checked==true)
            {
                isWarehouse = false;
            }else
            {
                isWarehouse = true;
            }
         
            SqlConnection con = Database.getConnection();
            con.Open();
            int ctr = gridView1.RowCount - 1;
            try
            {
                string query = "[sp_StageManualEntryForReInventoryIN]";
                SqlCommand com = new SqlCommand(query, con);
                com.Parameters.AddWithValue("@parmid", tab2batchid.Text);
                com.Parameters.AddWithValue("@parmbranch", brcodetab2.ToString());
                com.Parameters.AddWithValue("@parmdatereceived", tab2datereceived.Text);
                com.Parameters.AddWithValue("@parmexpirydate", tab2expirydate.Text);
                com.Parameters.AddWithValue("@parmproductcode", prodcode.ToString());
                com.Parameters.AddWithValue("@parmbarcode", txtsku.Text);
                com.Parameters.AddWithValue("@parmqty", txtqty.Text);
                com.Parameters.AddWithValue("@parmcost", tab2cost.Text);                                                                      
                com.Parameters.AddWithValue("@parmiswarehouse", isWarehouse);
                com.Parameters.AddWithValue("@parmuser", Login.isglobalUserID);

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

            XtraMessageBox.Show("Successfully Added!");
           
        }
        private void PrintQr(string barcodeValue)
        {
            var rpt = new Barcode.BarcodePrinting();

            rpt.DataSource = null;
            rpt.DataMember = "";

            rpt.xrshipno.Text = "INVIN-" + tab2batchid.Text;
            rpt.xrpalletno.Text = "";
            rpt.lblmanufdate.Text = Convert.ToDateTime(tab2datereceived.Text).ToShortDateString();
            rpt.lblprodtype.Text = txtproduct.Text;
            rpt.xrsku.Text = prodcode.ToString();
            rpt.lbltotalkilos.Text = txtqty.Text.Trim();
            rpt.lblxpirydate.Text = Convert.ToDateTime(tab2expirydate.Text).ToShortDateString();

            // KEY: force QR payload
            rpt.xrBarCode2.AutoModule = false; // override designer
            rpt.xrBarCode2.Text = barcodeValue.Trim();

            rpt.CreateDocument();

            try
            {
                new ReportPrintTool(rpt).Print();
            }
            catch (System.Drawing.Printing.InvalidPrinterException ex)
            {
                // Handle gracefully
                XtraMessageBox.Show("Printing failed: " + ex.Message +
                                    "\nPlease install or configure a printer before printing.",
                                    "Printer Error",
                                    MessageBoxButtons.OK,
                                    MessageBoxIcon.Error);
            }
        }

        void printBarcode()
        {
            PrintQr(txtsku.Text);
        }
        private void tab2AddBtn_Click(object sender, EventArgs e)
        {
            if (String.IsNullOrEmpty(tab2batchid.Text) || String.IsNullOrEmpty(tab2datereceived.Text) || String.IsNullOrEmpty(tab2brcode.Text))
            {
                XtraMessageBox.Show("No Empty Fields");
                return;
            }
            else
            {
               
                addManualInventory();
                printBarcode();
                displayTab2();
                
                txtqty.Text = "";
                txtsku.Text = "";

                txtproduct.Focus();
            }
        }

        private void tab2cancelbtn_Click(object sender, EventArgs e)
        {
            string seqno = gridView4.GetRowCellValue(gridView4.FocusedRowHandle, "SequenceNumber").ToString();
            Database.ExecuteQuery($"DELETE FROM TempInventoryIN WHERE ID='{tab2batchid.Text}' " +
                $"AND SequenceNumber='{seqno}'", "Successfully Deleted");
            displayTab2();
        }


        void saveManualInventoryEntry()
        {
            SqlConnection con = Database.getConnection();
            con.Open();
            //int ctr = gridView1.RowCount - 1;
            try
            {
                string query = "sp_CommitReInventoryINManualEntry";
                SqlCommand com = new SqlCommand(query, con);
                com.Parameters.AddWithValue("@parmid", tab2batchid.Text);
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
        private void tab2savebtn_Click(object sender, EventArgs e)
        {
            if(gridView4.RowCount <= 0)
            {
                XtraMessageBox.Show("No Records to Save");
            }
            else
            {
                saveManualInventoryEntry();
                XtraMessageBox.Show("Successfully Saved!");

                tab2batchid.Text = "";
                txtproduct.Text = "";
                txtqty.Text = "";
                txtsku.Text = "";

                txtproduct.Enabled = false;
                txtqty.Enabled = false;
                txtsku.Enabled = false;

                gridControltab2.DataSource = null;
                gridView4.Columns.Clear();

                tab2btnnew.Enabled = true;
            }
        }

        private void simpleButton8_Click(object sender, EventArgs e)
        {
            recoverInventoryForManualSelection();
        }

        void recoverInventoryForManualSelection()
        {
            ReInventoryINRecovery revin = new ReInventoryINRecovery();
            revin.ShowDialog(this);
            if (ReInventoryINRecovery.isdone == true)
            {
                bool checkfirst = Database.checkifExist("SELECT ID FROM [TempInventoryIN] WHERE ID = '" + ReInventoryINRecovery.id + "'");
                if (checkfirst)
                {
                    Database.display("SELECT * FROM [TempInventoryIN] WHERE ID='" + ReInventoryINRecovery.id + "'", gridControltab2, gridView4);
                    tab2batchid.Text = ReInventoryINRecovery.id;
                }
                else
                {
                    XtraMessageBox.Show("Inventory ID Not Exist in Temporary Container, This Number is either not exist OR it is already Uploaded in Inventory Table");
                    return;
                }
                ReInventoryINRecovery.isdone = false;
                revin.Dispose();
            }
        }

        private void tab2brcode_EditValueChanged(object sender, EventArgs e)
        {
            brcodetab2 = SearchLookUpClass.getSingleValue(tab2brcode, "BranchCode");
        }

        private void txtbranch_EditValueChanged(object sender, EventArgs e)
        {
            brcode = SearchLookUpClass.getSingleValue(txtbranch, "BranchCode");
        }

        private void Commissary_CheckedChanged(object sender, EventArgs e)
        {
            if (Commissary.Checked == true)
                iswarehouse = true;
            else
                iswarehouse = false;
        }

        private void bigblue_CheckedChanged(object sender, EventArgs e)
        {
            if (bigblue.Checked == true)
                iswarehouse = false;
            else
                iswarehouse = true;
        }
    }
}