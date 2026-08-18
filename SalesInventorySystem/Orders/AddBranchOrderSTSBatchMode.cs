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
using SalesInventorySystem.Classes;

namespace SalesInventorySystem.Orders
{
    public partial class AddBranchOrderSTSBatchMode : DevExpress.XtraEditors.XtraForm
    {
        int totalreceive = 0;
        public static bool isdone = false;
        public AddBranchOrderSTSBatchMode()
        {
            InitializeComponent();
        }

        private void AddBranchOrderSTSBatchMode_Load(object sender, EventArgs e)
        {

        }

        // transferredCount = rows actually processed. skippedItems = human-readable reasons,
        // covering both rows filtered out here (requested > available) and any the SP itself
        // skipped (sp_AddBranchOrderBatch isolates each row and reports failures instead of
        // aborting the whole batch -- covers the race-condition case where inventory changed
        // between grid-load and Save-click).
        private bool executeTransfer(out int transferredCount, out List<string> skippedItems)
        {
            transferredCount = 0;
            skippedItems = new List<string>();
            try
            {
                DataTable dtTransfer = new DataTable();
                dtTransfer.Columns.Add("ProductCategoryCode", typeof(string));
                dtTransfer.Columns.Add("ProductCode", typeof(string));
                dtTransfer.Columns.Add("ProductName", typeof(string));
                dtTransfer.Columns.Add("QtyRequested", typeof(decimal));
                dtTransfer.Columns.Add("Qty", typeof(decimal));

                int[] selectedRows = gridView1.GetSelectedRows();
                if (selectedRows == null || selectedRows.Length == 0)
                {
                    XtraMessageBox.Show("No items selected.");
                    return false;
                }

                foreach (int rowHandle in selectedRows)
                {
                    if (rowHandle < 0) continue;

                    double available = Convert.ToDouble(gridView1.GetRowCellValue(rowHandle, "AvailableInv"));
                    double requested = Convert.ToDouble(gridView1.GetRowCellValue(rowHandle, "QtyRequested"));
                    string productName = Convert.ToString(gridView1.GetRowCellValue(rowHandle, "ProductName"));

                    // Don't send rows that exceed available inventory at all -- skip, don't deduct.
                    if (requested > available)
                    {
                        skippedItems.Add(productName + ": requested " + requested + ", only " + available + " available");
                        continue;
                    }

                    DataRow dr = dtTransfer.NewRow();
                    dr["ProductCategoryCode"] =
                        Classes.Product.getProductCategoryCode(
                            Convert.ToString(gridView1.GetRowCellValue(rowHandle, "Category")));

                    dr["ProductCode"] = Convert.ToString(gridView1.GetRowCellValue(rowHandle, "ProductCode"));
                    dr["ProductName"] = productName;
                    dr["QtyRequested"] = Convert.ToDecimal(requested);
                    dr["Qty"] = Convert.ToDecimal(gridView1.GetRowCellValue(rowHandle, "Qty"));

                    dtTransfer.Rows.Add(dr);
                }

                if (dtTransfer.Rows.Count == 0)
                {
                    XtraMessageBox.Show("No valid rows to transfer (all selected items exceed available inventory).");
                    return false;
                }

                using (SqlConnection conn = Database.getConnection())
                using (SqlCommand cmd = new SqlCommand("sp_AddBranchOrderBatch", conn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;

                    // IMPORTANT: Structured TVP should be typed, not AddWithValue guessing.
                    var p = cmd.Parameters.Add("@TransferItems", SqlDbType.Structured);
                    p.TypeName = "dbo.TransferItemType";
                    p.Value = dtTransfer;

                    cmd.Parameters.Add("@PONumber", SqlDbType.VarChar, 10).Value = txtponum.Text.Trim();
                    cmd.Parameters.Add("@DeliveryNo", SqlDbType.VarChar, 10).Value = txtdevno.Text.Trim();
                    cmd.Parameters.Add("@ReferenceNo", SqlDbType.VarChar, 10).Value = txtrefno.Text.Trim();
                    cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 10).Value = txtbrcode.Text.Trim();
                    cmd.Parameters.Add("@PreparedBy", SqlDbType.VarChar, 60).Value = Login.Fullname;

                    conn.Open();
                    var serverSkipped = new List<string>();
                    using (SqlDataReader reader = cmd.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            serverSkipped.Add(reader["ProductName"].ToString() + ": " + reader["Reason"].ToString());
                        }
                    }
                    skippedItems.AddRange(serverSkipped);
                    transferredCount = dtTransfer.Rows.Count - serverSkipped.Count;
                }

                return true; // ✅ success
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message, "Transfer Failed",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return false; // ✅ failure
            }
        }
        private bool ConfirmBranchOrder()
        {
            try
            {
                using (SqlConnection con = Database.getConnection())
                using (SqlCommand cmd = new SqlCommand("dbo.sp_ConfirmBranchOrderSTS", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 120;

                    cmd.Parameters.Add("@parmdevno", SqlDbType.VarChar, 20).Value = txtdevno.Text.Trim();
                    cmd.Parameters.Add("@parmrefno", SqlDbType.VarChar, 10).Value = txtrefno.Text.Trim();
                    cmd.Parameters.Add("@parmeffectivitydate", SqlDbType.Date).Value = DBNull.Value;
                    cmd.Parameters.Add("@parmpono", SqlDbType.VarChar, 10).Value = txtponum.Text.Trim();
                    cmd.Parameters.Add("@parmbarcode", SqlDbType.VarChar, 50).Value = DBNull.Value;
                    cmd.Parameters.Add("@parmbranchcode", SqlDbType.VarChar, 10).Value = txtbrcode.Text.Trim();
                    cmd.Parameters.Add("@parmorigin", SqlDbType.VarChar, 10).Value = Login.assignedBranch;
                    cmd.Parameters.Add("@preparedby", SqlDbType.VarChar, 30).Value = Login.Fullname;

                    con.Open();
                    cmd.ExecuteNonQuery();
                }

                return true;
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message, "Confirm Branch Order Failed",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return false;
            }
        }
        private void simpleButton2_Click(object sender, EventArgs e)
        {

            int totalorders = Database.getCountData(
                    "SELECT COUNT(ProductNo) as Counter FROM DeliveryDetails WHERE PONumber=" + txtponum.Text + " AND isReturned=0 AND isCancelled=0",
                    "Counter");

            if (!HelperFunction.ConfirmDialog("Are you sure you want to save this Inventory?", "Confirm Inventory Entry"))
                return;

            // ✅ check for negative inventory BEFORE transfer
            if (HasNegativeInventorySelected())
            {
                bool confirmNegative = HelperFunction.ConfirmDialog(
                    "Some selected items exceed available inventory and will be SKIPPED (not deducted).\n\nDo you want to continue processing the remaining valid items?",
                    "Negative Inventory Warning");

                if (!confirmNegative)
                    return; // ❌ stop process
            }

            // ✅ Stop if executeTransfer fails
            if (!executeTransfer(out int transferredCount, out List<string> skippedItems))
                return;

            totalreceive = transferredCount;

            // discrepancy prompt
            if (totalorders != totalreceive)
            {
                if (!HelperFunction.ConfirmDialog(
                    "The System found out that there are remaining items in OrderDetails that you do not receive.. Are you sure you want to Continue",
                    "Discrepancy"))
                    return;
            }

            // ✅ Stop if confirm fails
            if (!ConfirmBranchOrder())
                return;

            isdone = true;

            string summary = transferredCount + " item(s) transferred successfully.";
            if (skippedItems.Count > 0)
            {
                summary += "\n\n" + skippedItems.Count + " item(s) skipped:\n" + string.Join("\n", skippedItems);
            }
            BigAlert.Show("SUCCESS", summary, MessageBoxIcon.Information);
            this.Close();
        }

        private void gridView1_RowCellStyle(object sender, RowCellStyleEventArgs e)
        {
            //GridView view = sender as GridView;
            //if (e.Column.FieldName == "Qty")
            //{
            //    e.Appearance.BackColor = Color.Salmon;
            //    e.Appearance.BackColor2 = Color.LightSalmon;
            //}
            //if (e.RowHandle >= 0)
            //{
            //    string status = gridView1.GetRowCellValue(e.RowHandle, "Status")?.ToString();
            //    if (status == "NEGATIVE INVENTORY" || status == "NO INVENTORY")
            //    {
            //        e.Appearance.BackColor = Color.LightGray; // Grays out the row
            //        e.Appearance.ForeColor = Color.DarkGray;
            //    }
            //}
            if (e.RowHandle >= 0)
            {
                double available = Convert.ToDouble(gridView1.GetRowCellValue(e.RowHandle, "AvailableInv"));

                if (available <= 0)
                {
                    // ❌ Disable only when NO inventory
                    e.Appearance.BackColor = Color.LightGray;
                    e.Appearance.ForeColor = Color.DarkGray;
                }
                else if (Convert.ToDouble(gridView1.GetRowCellValue(e.RowHandle, "QtyRequested")) > available)
                {
                    // ⚠ NEGATIVE INVENTORY (visual only, not disabled)
                    e.Appearance.BackColor = Color.Khaki;
                    e.Appearance.ForeColor = Color.Black;
                }
            }
        }

        private void gridView1_ShowingEditor(object sender, CancelEventArgs e)
        {
            GridView view = sender as GridView;
            if (view.FocusedColumn.FieldName != "Qty")
                e.Cancel = true;
        }

        private void gridView1_CustomRowCellEdit(object sender, CustomRowCellEditEventArgs e)
        {
            
        }

        private void gridView1_SelectionChanged(object sender, DevExpress.Data.SelectionChangedEventArgs e)
        {
            int rowHandle = e.ControllerRow;
            if (rowHandle >= 0)
            {
                //string status = gridView1.GetRowCellValue(rowHandle, "Status")?.ToString();
                //if (status == "NEGATIVE INVENTORY" || status == "NO INVENTORY")
                //{
                //    gridView1.UnselectRow(rowHandle); // Manually unselect the row
                //}

                double available = Convert.ToDouble(gridView1.GetRowCellValue(rowHandle, "AvailableInv"));
                if (available <= 0)
                {
                    // only block if NO inventory
                    gridView1.UnselectRow(rowHandle);
                }

            }
            if (gridView1.SelectedRowsCount == gridView1.DataRowCount) // Check if "Select All" was clicked
            {
                for (int i = 0; i < gridView1.DataRowCount; i++)
                {
                    //string status = gridView1.GetRowCellValue(i, "Status")?.ToString();
                    //if (status == "NEGATIVE INVENTORY" || status == "NO INVENTORY")
                    //{
                    //    gridView1.UnselectRow(i); // Exclude rows with NEGATIVE INVENTORY
                    //}

                    double available = Convert.ToDouble(gridView1.GetRowCellValue(i, "AvailableInv"));

                    if (available <= 0)
                    {
                        gridView1.UnselectRow(i);
                    }

                }
            }
        }
        private bool HasNegativeInventorySelected()
        {
            int[] selectedRows = gridView1.GetSelectedRows();

            foreach (int rowHandle in selectedRows)
            {
                if (rowHandle < 0) continue;

                double available = Convert.ToDouble(gridView1.GetRowCellValue(rowHandle, "AvailableInv"));
                double requested = Convert.ToDouble(gridView1.GetRowCellValue(rowHandle, "QtyRequested"));

                // ✅ Negative inventory condition
                if (available > 0 && requested > available)
                {
                    return true;
                }
            }

            return false;
        }

        private void gridView1_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            if (e.Column.FieldName == "Qty")
            {
                double qtyrequested = Convert.ToDouble(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "QtyRequested").ToString());
                double qtytosend = Convert.ToDouble(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "Qty").ToString());
                double qtyavailable = Convert.ToDouble(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "AvailableInv").ToString());
                if(qtytosend > qtyavailable)
                {
                    gridView1.SetRowCellValue(gridView1.FocusedRowHandle, "Qty", qtyrequested.ToString());
                    XtraMessageBox.Show("Greater than Available Inventory Quantity!");
                    return;
                }
                else if(qtytosend > qtyrequested)
                {
                    bool confirm = HelperFunction.ConfirmDialog("You are about to send above quantity that requested", "Greater than Quantity Requested");
                    if (!confirm) { gridView1.SetRowCellValue(gridView1.FocusedRowHandle, "Qty", qtyrequested.ToString());  }
                }
            }
        }
    }
}