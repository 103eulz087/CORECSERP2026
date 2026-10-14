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
using System.Data.SqlClient;
using DevExpress.XtraReports.UI;
using SalesInventorySystem.Classes;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class ReceivedTransferInventoryBatchMode : DevExpress.XtraEditors.XtraForm
    {
        public string TransferNo { get; set; }

        public static bool isdone = false;
        object categorycode = null;
        public ReceivedTransferInventoryBatchMode()
        {
            InitializeComponent();
        }

        //void ConfirmBranchReceivedOrder()
        //{
        //    SqlConnection con = Database.getConnection();
        //    con.Open();
        //    try
        //    {

        //        string query = "sp_ConfirmBranchReceivedTransferInventory";
        //        SqlCommand com = new SqlCommand(query, con);

        //        com.Parameters.AddWithValue("@parmtransno", txtshipmentno.Text);
        //        com.Parameters.AddWithValue("@parmbranchcode", Login.assignedBranch);
        //        com.Parameters.AddWithValue("@preparedby", Login.Fullname);
        //        com.CommandType = CommandType.StoredProcedure;
        //        com.CommandText = query;
        //        com.ExecuteNonQuery();
        //    }
        //    catch (SqlException ex)
        //    {
        //        XtraMessageBox.Show(ex.Message.ToString());
        //    }
        //    finally
        //    {
        //        con.Close();
        //    }
        //}
        // 2026-10-14: checked BEFORE anything is saved (it used to run after the items were already received)
        bool ValidateHeader()
        {
            if (string.IsNullOrEmpty(txtcategory.Text) || categorycode == null)
            {
                XtraMessageBox.Show("Please select a Category.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
            if (txtcategory.Text == "Return to Supplier" && string.IsNullOrEmpty(txtsupplier.Text))
            {
                XtraMessageBox.Show("Please select a Supplier.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
            return true;
        }

        // true only when the transfer was confirmed (sp_ConfirmBranchReceivedTransferInventory committed)
        bool ConfirmBranchReceivedOrder()
        {
            using (SqlConnection con = Database.getConnection())
            {
                try
                {
                    con.Open();

                    using (SqlCommand com = new SqlCommand("sp_ConfirmBranchReceivedTransferInventory", con))
                    {
                        com.CommandType = CommandType.StoredProcedure;

                        com.Parameters.Add("@parmtransno", SqlDbType.VarChar).Value = txtshipmentno.Text;
                        com.Parameters.Add("@parmbranchcode", SqlDbType.VarChar).Value = Login.assignedBranch;
                        com.Parameters.Add("@preparedby", SqlDbType.VarChar).Value = Login.Fullname;

                        // ✅ NEW
                        com.Parameters.Add("@category", SqlDbType.VarChar).Value = categorycode.ToString();//txtcategory.Text;
                        com.Parameters.Add("@remarks", SqlDbType.VarChar).Value = txtremarks.Text ?? "";
                        com.Parameters.Add("@suppliername", SqlDbType.VarChar).Value = txtsupplier.Text ?? "";

                        com.ExecuteNonQuery();
                    }
                    return true;
                }
                catch (Exception ex)
                {
                    XtraMessageBox.Show("The items were saved, but the transfer was NOT confirmed:\n" + ex.Message,
                        "Not Confirmed", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return false;
                }
            }
        }

        // Lines of the transfer as sent (TransferInventoryDetails), read fresh
        int CountTransferLines(string transferNo)
        {
            using (SqlConnection con = Database.getConnection())
            using (SqlCommand cmd = new SqlCommand("SELECT COUNT(*) FROM dbo.TransferInventoryDetails WHERE TransferNo = @t", con))
            {
                cmd.Parameters.Add("@t", SqlDbType.VarChar, 20).Value = transferNo;
                con.Open();
                return Convert.ToInt32(cmd.ExecuteScalar());
            }
        }

        // 2026-10-14 bug fix (transfers 1192 / 1214 received only one line): the rows used to be read from what the
        // grid SHOWED (view.RowCount), so a find-panel search, a column filter or grouping on screen sent only the
        // visible rows, and the transfer was then closed as DELIVERED anyway. Now every loaded row is sent, whatever
        // the grid shows, and the count must equal the transfer's lines. Returns true only when all lines were saved.
        private bool executeTransfer()
        {
            try
            {
                GridView view = gridViewRcvd;
                view.CloseEditor();          // an ActualQty still being typed is committed first
                view.UpdateCurrentRow();

                // 1. every loaded row (list source), never the filtered / grouped visible rows
                int rowCount = view.DataController.ListSourceRowCount;
                if (rowCount == 0)
                {
                    XtraMessageBox.Show("There are no items in the grid to receive.", "Empty List", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }

                // 2. Create DataTable for TVP
                DataTable inventoryItems = new DataTable();
                inventoryItems.Columns.Add("ProductCode", typeof(string));
                inventoryItems.Columns.Add("Barcode", typeof(string));
                inventoryItems.Columns.Add("Qty", typeof(float));

                for (int i = 0; i < rowCount; i++)
                {
                    string productCode = view.GetListSourceRowCellValue(i, "ProductNo")?.ToString() ?? "";
                    string barcode = view.GetListSourceRowCellValue(i, "BarcodeNo")?.ToString() ?? "";
                    object q = view.GetListSourceRowCellValue(i, "ActualQty");
                    float qty = (q == null || q == DBNull.Value) ? 0f : Convert.ToSingle(q);
                    inventoryItems.Rows.Add(productCode, barcode, qty);
                }

                // 3. all of the transfer's lines must be on the list (a stale or partly loaded screen is refused)
                int transferLines = CountTransferLines(txtshipmentno.Text);
                if (inventoryItems.Rows.Count != transferLines)
                {
                    XtraMessageBox.Show(
                        $"Transfer {txtshipmentno.Text} has {transferLines} line(s) but the screen holds {inventoryItems.Rows.Count}. " +
                        "Nothing was saved. Close this window and open the transfer again.",
                        "Lines Don't Match", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }

                // 4. Call the batch stored procedure
                using (SqlConnection conn = Database.getConnection())
                {
                    using (SqlCommand cmd = new SqlCommand("sp_AddBranchTransferInventoryBatch", conn))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;

                        cmd.Parameters.AddWithValue("@TransferNo", txtshipmentno.Text);
                        cmd.Parameters.AddWithValue("@BranchCodeRcvr", Login.assignedBranch);
                        cmd.Parameters.AddWithValue("@ReceivedBy", Login.isglobalUserID);

                        SqlParameter tvpParam = cmd.Parameters.AddWithValue("@Items", inventoryItems);
                        tvpParam.SqlDbType = SqlDbType.Structured;
                        tvpParam.TypeName = "dbo.TransferInventoryItemType";

                        conn.Open();
                        cmd.ExecuteNonQuery();
                    }
                }
                return true;
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show("Database Error: " + ex.Message + "\n\nThe transfer was not confirmed.", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return false;
            }
        }
        //void executeTransfer()
        //{
        //    try
        //    {
        //        GridView view = gridControlRcvd.FocusedView as GridView;
        //        view.SortInfo.Clear();

        //        int[] selectedRows = gridViewRcvd.GetSelectedRows();

        //        // Create DataTable for TVP
        //        DataTable inventoryItems = new DataTable();
        //        inventoryItems.Columns.Add("ProductCode", typeof(string));
        //        inventoryItems.Columns.Add("Barcode", typeof(string));
        //        inventoryItems.Columns.Add("Qty", typeof(float));



        //        for (int i = 0; i <= gridViewRcvd.RowCount - 1; i++)
        //        {
        //            string productCode = gridViewRcvd.GetRowCellValue(i, "ProductNo").ToString(); ss
        //            string barcode = gridViewRcvd.GetRowCellValue(i, "BarcodeNo").ToString();
        //            float qty = Convert.ToSingle(gridViewRcvd.GetRowCellValue(i, "ActualQty")); 

        //            inventoryItems.Rows.Add(productCode, barcode, qty);
        //        }

        //        // Call the batch stored procedure
        //        using (SqlConnection conn = Database.getConnection())
        //        {
        //            using (SqlCommand cmd = new SqlCommand("sp_AddBranchTransferInventoryBatch", conn))
        //            {
        //                cmd.CommandType = CommandType.StoredProcedure;

        //                cmd.Parameters.AddWithValue("@TransferNo", txtshipmentno.Text);
        //                cmd.Parameters.AddWithValue("@BranchCodeRcvr", Login.assignedBranch); 
        //                cmd.Parameters.AddWithValue("@ReceivedBy", Login.isglobalUserID);

        //                SqlParameter tvpParam = cmd.Parameters.AddWithValue("@Items", inventoryItems);
        //                tvpParam.SqlDbType = SqlDbType.Structured;
        //                tvpParam.TypeName = "dbo.TransferInventoryItemType";

        //                conn.Open();
        //                cmd.ExecuteNonQuery();
        //            }
        //        }

        //        totalreceive = selectedRows.Length;
        //        isdone = true;
        //    }
        //    catch (SqlException ex)
        //    {
        //        XtraMessageBox.Show("Error: " + ex.Message);
        //    }
        //}

        // 2026-10-14: validate -> save ALL lines -> confirm; each step stops the next one when it fails (before, the
        // transfer was confirmed and the window closed with "Successfully Added!" even after an error)
        private void simpleButton2_Click(object sender, EventArgs e)
        {
            if (!ValidateHeader())
                return;
            if (!HelperFunction.ConfirmDialog("Are you sure you want to save this Inventory?", "Confirm Inventory Entry"))
                return;

            simpleButton2.Enabled = false;
            try
            {
                if (!executeTransfer())
                    return;
                if (!ConfirmBranchReceivedOrder())
                    return;

                isdone = true;
                XtraMessageBox.Show($"Transfer {txtshipmentno.Text}: all items received.", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                this.Close();
            }
            finally
            {
                if (!IsDisposed) simpleButton2.Enabled = true;
            }
        }

        private void gridViewRcvd_RowCellStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowCellStyleEventArgs e)
        {
            GridView view = sender as GridView;
            if (e.Column.FieldName == "ActualQty")
            {
                e.Appearance.BackColor = Color.Salmon;
                e.Appearance.BackColor2 = Color.LightSalmon;
            }
        }

        private void gridViewRcvd_ShowingEditor(object sender, CancelEventArgs e)
        {
            GridView view = sender as GridView;
            if (view.FocusedColumn.FieldName != "ActualQty")
                e.Cancel = true;
        }

        private void gridControlRcvd_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStrip1.Show(gridControlRcvd, e.Location);
        }

        private void cancelLineToolStripMenuItem_Click(object sender, EventArgs e)
        {
            string qtydel = gridViewRcvd.GetRowCellValue(gridViewRcvd.FocusedRowHandle, "QtyDelivered").ToString();
            Barcode.BarcodePrinting bprint = new Barcode.BarcodePrinting();
            bprint.xrshipno.Text = "TRANSFER#:" + txtshipmentno.Text;//gridViewRcvd.GetRowCellValue(gridViewRcvd.FocusedRowHandle, "TransferNo").ToString();
            bprint.xrpalletno.Text = "n/a";
            bprint.lblmanufdate.Text = DateTime.Now.ToShortDateString();
            bprint.lblprodtype.Text = gridViewRcvd.GetRowCellValue(gridViewRcvd.FocusedRowHandle, "ProductName").ToString();
            bprint.lbltotalkilos.Text = qtydel;
            bprint.xrBarCode2.Text = gridViewRcvd.GetRowCellValue(gridViewRcvd.FocusedRowHandle, "BarcodeNo").ToString();
            bprint.lblxpirydate.Text = DateTime.Now.AddYears(1).ToShortDateString();
            ReportPrintTool report = new ReportPrintTool(bprint);
            report.Print();
        }

        private void ReceivedTransferInventoryBatchMode_Load(object sender, EventArgs e)
        {
            populateReceiveCategoryMaster();
            populateSupplier();
        }
        void populateReceiveCategoryMaster()
        {
            Database.displaySearchlookupEdit("SELECT CategoryCode,Description FROM dbo.ReceiveCategoryMaster ", txtcategory, "Description", "Description");
        }
        void populateSupplier()
        {
            Database.displaySearchlookupEdit("SELECT SupplierKey,SupplierName FROM dbo.Supplier ", txtsupplier, "SupplierName", "SupplierName");
        }

        private void txtcategory_EditValueChanged(object sender, EventArgs e)
        {
            categorycode = SearchLookUpClass.getSingleValue(txtcategory, "CategoryCode");
            if (categorycode.ToString() == "2")
            {
                txtsupplier.Enabled = true;
                BigAlert.Show("SELECT SUPPLIER", "You need to select a Supplier, this will not be ADDED to INVENTORY", MessageBoxIcon.Warning);
            }
            else if ((string)categorycode != "1")
            {
                BigAlert.Show("WARNING", "This will not be ADDED to INVENTORY", MessageBoxIcon.Warning);
            }
            //string category = cmbCategory.Text;

            //if (category != "TransferStock")
            //{
            //    lblWarning.Text = "⚠ This will NOT be added to inventory!";
            //    lblWarning.Visible = true;
            //}
            //else
            //{
            //    lblWarning.Visible = false;
            //}

        }

        private void printToolStripMenuItem_Click(object sender, EventArgs e)
        {
            var row = Database.getMultipleQuery("ReportHeaderSettings", "ReportName='ShipmentReport'", "Heading,ImageWidth,ImageHeight,Caption1,Caption2");

            string companyname = row["Heading"].ToString();
            string imagewidth = row["ImageWidth"].ToString();
            string imageheight = row["ImageHeight"].ToString();
            string caption1 = row["Caption1"].ToString();
            string caption2 = row["Caption2"].ToString();

            //HEADER MASTER
            //string pono = gridView1.GetRowCellValue(
            //    gridView1.FocusedRowHandle, "TransferNo"
            //).ToString();

            // Fix: getMultipleQuery returns Dictionary<string, object>, not string
            var supplierRow = Database.getMultipleQuery(
                "SELECT a.TransferNo,a.DateReceived,a.ReceivedBy,a.Remarks,a.SupplierName,b.Description as Category " +
                "FROM dbo.ReceiveTransferInventorySummary a " +
                "INNER JOIN dbo.ReceiveCategoryMaster b " +
                "ON a.ReceiveCategory=b.CategoryCode " +
                $"WHERE a.TransferNo='{TransferNo}' ",
                "TransferNo,DateReceived,ReceivedBy,Remarks,SupplierName,Category"
            );

            string suppliername = supplierRow.ContainsKey("SupplierName") ? supplierRow["SupplierName"].ToString() : string.Empty;
            string transactionumber = supplierRow.ContainsKey("TransferNo") ? supplierRow["TransferNo"].ToString() : string.Empty;
            string returncategory = supplierRow.ContainsKey("Category") ? supplierRow["Category"].ToString() : string.Empty;
            string dateofreturn = supplierRow.ContainsKey("DateReceived") ? supplierRow["DateReceived"].ToString() : string.Empty;
            string remarks = supplierRow.ContainsKey("Remarks") ? supplierRow["Remarks"].ToString() : string.Empty;

            DevExReportTemplate.StockOutReturn xct = new DevExReportTemplate.StockOutReturn();

            Classes.Utilities.GetImageDevEx(xct.xrPictureBox1, "ReportHeaderSettings", "ReportName='ShipmentReport'", "ImageLogo");
            xct.xrPictureBox1.SizeF = new SizeF(float.Parse(imagewidth), float.Parse(imageheight));
            xct.xrcompanyname.Text = companyname;
            xct.xrcaption1.Text = caption1;
            xct.xrcaption2.Text = caption2;

            xct.Landscape = false;
            xct.PaperKind = (DevExpress.Drawing.Printing.DXPaperKind)System.Drawing.Printing.PaperKind.A4;

            //xct.Margins = new System.Drawing.Printing.Margins(100, 100, 15, 100);

            xct.xrrefno.Text = transactionumber;
            xct.xrsupplier.Text = suppliername;
            xct.xrcategory.Text = returncategory;
            xct.xrremarks.Text = remarks;
            xct.xrdate.Text = dateofreturn;
            xct.xrpreparedby.Text = Login.Fullname;

            xct.Bands[BandKind.Detail].Controls.Add(HelperFunction.CopyGridControl(this.gridControlRcvd));
            xct.Bands[BandKind.Detail].Font = new System.Drawing.Font("Tahoma", 10);

            //gridView1.Columns["Cost"].OptionsColumn.Printable = DevExpress.Utils.DefaultBoolean.False;

            ReportPrintTool report = new ReportPrintTool(xct);
            report.ShowRibbonPreviewDialog();
        }
    }
}
//using System;
//using System.Collections.Generic;
//using System.ComponentModel;
//using System.Data;
//using System.Drawing;
//using System.Text;
//using System.Linq;
//using System.Threading.Tasks;
//using System.Windows.Forms;
//using DevExpress.XtraEditors;
//using DevExpress.XtraGrid.Views.Grid;
//using System.Data.SqlClient;
//using DevExpress.XtraReports.UI;

//namespace SalesInventorySystem.HOFormsDevEx
//{
//    public partial class ReceivedTransferInventoryBatchMode : DevExpress.XtraEditors.XtraForm
//    {
//        int totalreceive = 0;
//        public static bool isdone = false;
//        public ReceivedTransferInventoryBatchMode()
//        {
//            InitializeComponent();
//        }

//        void ConfirmBranchReceivedOrder()
//        {
//            SqlConnection con = Database.getConnection();
//            con.Open();
//            try
//            {

//                string query = "sp_ConfirmBranchReceivedTransferInventory";
//                SqlCommand com = new SqlCommand(query, con);

//                com.Parameters.AddWithValue("@parmtransno", txtshipmentno.Text);
//                com.Parameters.AddWithValue("@parmbranchcode", Login.assignedBranch);
//                com.Parameters.AddWithValue("@preparedby", Login.Fullname);
//                com.CommandType = CommandType.StoredProcedure;
//                com.CommandText = query;
//                com.ExecuteNonQuery();
//            }
//            catch (SqlException ex)
//            {
//                XtraMessageBox.Show(ex.Message.ToString());
//            }
//            finally
//            {
//                con.Close();
//            }
//        }

//        private void executeTransfer()
//        {
//            try
//            {
//                GridView view = gridControlRcvd.FocusedView as GridView;

//                // 1. Guard clause: Ensure there is actually data to process
//                if (view == null || view.RowCount == 0)
//                {
//                    XtraMessageBox.Show("There are no items in the grid to receive.", "Empty List", MessageBoxButtons.OK, MessageBoxIcon.Warning);
//                    return;
//                }

//                // 2. Create DataTable for TVP
//                DataTable inventoryItems = new DataTable();
//                inventoryItems.Columns.Add("ProductCode", typeof(string));
//                inventoryItems.Columns.Add("Barcode", typeof(string));
//                inventoryItems.Columns.Add("Qty", typeof(float));

//                // 3. LOOP THROUGH EVERY ROW IN THE GRID
//                for (int i = 0; i < view.RowCount; i++)
//                {
//                    // IsDataRow ignores Group Headers or Auto-Filter rows
//                    if (view.IsDataRow(i))
//                    {
//                        string productCode = view.GetRowCellValue(i, "ProductNo")?.ToString() ?? "";
//                        string barcode = view.GetRowCellValue(i, "BarcodeNo")?.ToString() ?? "";
//                        float qty = Convert.ToSingle(view.GetRowCellValue(i, "ActualQty"));

//                        inventoryItems.Rows.Add(productCode, barcode, qty);
//                    }
//                }

//                // 4. Call the batch stored procedure
//                using (SqlConnection conn = Database.getConnection())
//                {
//                    using (SqlCommand cmd = new SqlCommand("sp_AddBranchTransferInventoryBatch", conn))
//                    {
//                        cmd.CommandType = CommandType.StoredProcedure;

//                        cmd.Parameters.AddWithValue("@TransferNo", txtshipmentno.Text);
//                        cmd.Parameters.AddWithValue("@BranchCodeRcvr", Login.assignedBranch);
//                        cmd.Parameters.AddWithValue("@ReceivedBy", Login.isglobalUserID);

//                        SqlParameter tvpParam = cmd.Parameters.AddWithValue("@Items", inventoryItems);
//                        tvpParam.SqlDbType = SqlDbType.Structured;
//                        tvpParam.TypeName = "dbo.TransferInventoryItemType";

//                        conn.Open();
//                        cmd.ExecuteNonQuery();
//                    }
//                }
//                isdone = true;
//                XtraMessageBox.Show($"Successfully received {inventoryItems.Rows.Count} items!", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);

//                // Optional: Clear the grid or reload it from the database now that they are received
//                // gridControlRcvd.DataSource = null; 
//            }
//            catch (SqlException ex)
//            {
//                XtraMessageBox.Show("Database Error: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
//            }
//        }
//        //void executeTransfer()
//        //{
//        //    try
//        //    {
//        //        GridView view = gridControlRcvd.FocusedView as GridView;
//        //        view.SortInfo.Clear();

//        //        int[] selectedRows = gridViewRcvd.GetSelectedRows();

//        //        // Create DataTable for TVP
//        //        DataTable inventoryItems = new DataTable();
//        //        inventoryItems.Columns.Add("ProductCode", typeof(string));
//        //        inventoryItems.Columns.Add("Barcode", typeof(string));
//        //        inventoryItems.Columns.Add("Qty", typeof(float));



//        //        for (int i = 0; i <= gridViewRcvd.RowCount - 1; i++)
//        //        {
//        //            string productCode = gridViewRcvd.GetRowCellValue(i, "ProductNo").ToString();
//        //            string barcode = gridViewRcvd.GetRowCellValue(i, "BarcodeNo").ToString();
//        //            float qty = Convert.ToSingle(gridViewRcvd.GetRowCellValue(i, "ActualQty")); 

//        //            inventoryItems.Rows.Add(productCode, barcode, qty);
//        //        }

//        //        // Call the batch stored procedure
//        //        using (SqlConnection conn = Database.getConnection())
//        //        {
//        //            using (SqlCommand cmd = new SqlCommand("sp_AddBranchTransferInventoryBatch", conn))
//        //            {
//        //                cmd.CommandType = CommandType.StoredProcedure;

//        //                cmd.Parameters.AddWithValue("@TransferNo", txtshipmentno.Text);
//        //                cmd.Parameters.AddWithValue("@BranchCodeRcvr", Login.assignedBranch); 
//        //                cmd.Parameters.AddWithValue("@ReceivedBy", Login.isglobalUserID);

//        //                SqlParameter tvpParam = cmd.Parameters.AddWithValue("@Items", inventoryItems);
//        //                tvpParam.SqlDbType = SqlDbType.Structured;
//        //                tvpParam.TypeName = "dbo.TransferInventoryItemType";

//        //                conn.Open();
//        //                cmd.ExecuteNonQuery();
//        //            }
//        //        }

//        //        totalreceive = selectedRows.Length;
//        //        isdone = true;
//        //    }
//        //    catch (SqlException ex)
//        //    {
//        //        XtraMessageBox.Show("Error: " + ex.Message);
//        //    }
//        //}

//        private void simpleButton2_Click(object sender, EventArgs e)
//        {
//            int totalorders = Database.getCountData("SELECT COUNT(ProductNo) as Counter FROM dbo.TransferInventoryDetails  WHERE TransferNo=" + txtshipmentno.Text + "", "Counter");

//            bool confirmRcv = HelperFunction.ConfirmDialog("Are you sure you want to save this Inventory?", "Confirm Inventory Entry");

//            if (confirmRcv)
//            {
//                executeTransfer();
//                if (totalorders != totalreceive)
//                {
//                    bool confirm = HelperFunction.ConfirmDialog("The System found out that there are remaining items in OrderDetails that you do not receive.. Are you sure you want to Continue", "Dscrepancy");
//                    if (confirm)
//                    {
//                        ConfirmBranchReceivedOrder();
//                        XtraMessageBox.Show("Successfully Added!");
//                        this.Close();
//                    }
//                    else
//                    {
//                        return;
//                    }
//                }
//                else
//                {
//                    ConfirmBranchReceivedOrder();
//                    XtraMessageBox.Show("Successfully Added!");
//                    this.Close();
//                }
//            }
//            else
//            {
//                return;
//            }
//            isdone = true;
//        }

//        private void gridViewRcvd_RowCellStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowCellStyleEventArgs e)
//        {
//            GridView view = sender as GridView;
//            if (e.Column.FieldName == "ActualQty")
//            {
//                e.Appearance.BackColor = Color.Salmon;
//                e.Appearance.BackColor2 = Color.LightSalmon;
//            }
//        }

//        private void gridViewRcvd_ShowingEditor(object sender, CancelEventArgs e)
//        {
//            GridView view = sender as GridView;
//            if (view.FocusedColumn.FieldName != "ActualQty")
//                e.Cancel = true;
//        }

//        private void gridControlRcvd_MouseUp(object sender, MouseEventArgs e)
//        {
//            if (e.Button == MouseButtons.Right)
//                contextMenuStrip1.Show(gridControlRcvd, e.Location);
//        }

//        private void cancelLineToolStripMenuItem_Click(object sender, EventArgs e)
//        {
//            string qtydel = gridViewRcvd.GetRowCellValue(gridViewRcvd.FocusedRowHandle, "QtyDelivered").ToString();
//            Barcode.BarcodePrinting bprint = new Barcode.BarcodePrinting();
//            bprint.xrshipno.Text = "TRANSFER#:" + txtshipmentno.Text;//gridViewRcvd.GetRowCellValue(gridViewRcvd.FocusedRowHandle, "TransferNo").ToString();
//            bprint.xrpalletno.Text = "n/a";
//            bprint.lblmanufdate.Text = DateTime.Now.ToShortDateString();
//            bprint.lblprodtype.Text = gridViewRcvd.GetRowCellValue(gridViewRcvd.FocusedRowHandle, "ProductName").ToString();
//            bprint.lbltotalkilos.Text = qtydel;
//            bprint.xrBarCode2.Text = gridViewRcvd.GetRowCellValue(gridViewRcvd.FocusedRowHandle, "BarcodeNo").ToString();
//            bprint.lblxpirydate.Text = DateTime.Now.AddYears(1).ToShortDateString();
//            ReportPrintTool report = new ReportPrintTool(bprint);
//            report.Print();
//        }

//        private void ReceivedTransferInventoryBatchMode_Load(object sender, EventArgs e)
//        {

//        }
//    }
//}
