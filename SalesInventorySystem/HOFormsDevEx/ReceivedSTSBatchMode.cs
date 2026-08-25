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

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class ReceivedSTSBatchMode : DevExpress.XtraEditors.XtraForm
    {
        public static bool isdone = false;

        public ReceivedSTSBatchMode()
        {
            InitializeComponent();
        }

        private void ReceivedSTSBatchMode_Load(object sender, EventArgs e)
        {
            // Everything defaults to RECEIVED; the user unchecks whatever did
            // not physically arrive. Grid is expected to already be bound
            // (by the caller, ReceivedSTS.cs) before this form is shown.
            gridViewRcvd.SelectAll();
        }

        bool ConfirmBranchReceivedOrder()
        {
            using (SqlConnection con = Database.getConnection())
            using (SqlCommand com = new SqlCommand(
                GlobalCache.CompanyName == "JFC" ? "sp_ConfirmBranchRecievedOrderJFC" : "sp_ConfirmBranchRecievedOrder", con))
            {
                com.CommandType = CommandType.StoredProcedure;
                com.Parameters.AddWithValue("@parmdevno", "");
                com.Parameters.AddWithValue("@parmpono", txtshipmentno.Text);
                com.Parameters.AddWithValue("@parmbarcode", "");
                com.Parameters.AddWithValue("@parmbranchcode", Login.assignedBranch);
                com.Parameters.AddWithValue("@preparedby", Login.Fullname);

                try
                {
                    con.Open();
                    com.ExecuteNonQuery();
                    return true;
                }
                catch (SqlException ex)
                {
                    BigAlert.Show("ERROR", ex.Message, MessageBoxIcon.Error);
                    return false;
                }
            }
        }

        // Only rows the user left CHECKED are submitted as received -- this is
        // the actual fix: previously every row in the grid was submitted
        // regardless of checkbox/selection state.
        bool ReceiveSelectedItems(int[] selectedRowHandles)
        {
            DataTable inventoryItems = new DataTable();
            inventoryItems.Columns.Add("ProductCode", typeof(string));
            inventoryItems.Columns.Add("Barcode", typeof(string));
            inventoryItems.Columns.Add("Qty", typeof(float));
            inventoryItems.Columns.Add("SellingPrice", typeof(decimal));
            inventoryItems.Columns.Add("IsScan", typeof(bool));

            foreach (int handle in selectedRowHandles)
            {
                string productCode = gridViewRcvd.GetRowCellValue(handle, "ProductNo").ToString();
                string barcode = gridViewRcvd.GetRowCellValue(handle, "BarcodeNo").ToString();
                float qty = Convert.ToSingle(gridViewRcvd.GetRowCellValue(handle, "ActualQty"));
                decimal sellingPrice = Convert.ToDecimal(gridViewRcvd.GetRowCellValue(handle, "SellingPrice"));
                inventoryItems.Rows.Add(productCode, barcode, qty, sellingPrice, false);
            }

            if (inventoryItems.Rows.Count == 0)
                return true; // nothing checked -- not a failure, just nothing to receive

            using (SqlConnection con = Database.getConnection())
            using (SqlCommand cmd = new SqlCommand("sp_AddBranchInventoryBatch", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@PONumber", txtshipmentno.Text);
                cmd.Parameters.AddWithValue("@BranchCode", Login.assignedBranch);
                cmd.Parameters.AddWithValue("@ReceivedBy", Login.isglobalUserID);

                SqlParameter tvpParam = cmd.Parameters.AddWithValue("@Items", inventoryItems);
                tvpParam.SqlDbType = SqlDbType.Structured;
                tvpParam.TypeName = "dbo.InventoryItemType";

                try
                {
                    con.Open();
                    cmd.ExecuteNonQuery();
                    return true;
                }
                catch (SqlException ex)
                {
                    BigAlert.Show("RECEIVE FAILED", ex.Message, MessageBoxIcon.Error);
                    return false;
                }
            }
        }

        // Rows left UNCHECKED never arrived -- restore origin Inventory,
        // reverse the GL leg if the transfer was confirmed, and correct
        // DeliverySummary.Status once nothing is left for this dispatch.
        // Previously these rows just silently vanished from the batch with
        // no server-side effect at all: permanently unaccounted-for stock.
        bool ReturnUnreceivedItems(int[] unselectedRowHandles)
        {
            foreach (int handle in unselectedRowHandles)
            {
                using (SqlConnection con = Database.getConnection())
                using (SqlCommand cmd = new SqlCommand("sp_ReverseSTSInventoryTransfer", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 120;
                    cmd.Parameters.AddWithValue("@parmdevno", gridViewRcvd.GetRowCellValue(handle, "DeliveryNo").ToString());
                    cmd.Parameters.AddWithValue("@parmrefno", gridViewRcvd.GetRowCellValue(handle, "ReferenceNumber").ToString());
                    cmd.Parameters.AddWithValue("@parmpono", txtshipmentno.Text);
                    cmd.Parameters.AddWithValue("@parmprodno", gridViewRcvd.GetRowCellValue(handle, "ProductNo").ToString());
                    cmd.Parameters.AddWithValue("@parmqty", Convert.ToDecimal(gridViewRcvd.GetRowCellValue(handle, "ActualQty")));
                    // Roles are flipped from the dispatch side: here the
                    // receiving branch IS the destination (@parmbranchcode),
                    // and HO (888) is always the origin for this HO-outbound
                    // STS flow -- same convention sp_ConfirmBranchOrderSTS
                    // itself hardcodes for its GL ticket branch.
                    cmd.Parameters.AddWithValue("@parmbranchcode", Login.assignedBranch);
                    cmd.Parameters.AddWithValue("@parmorigin", "888");
                    cmd.Parameters.AddWithValue("@preparedby", Login.Fullname);
                    cmd.Parameters.AddWithValue("@parmdevseqno", Convert.ToInt32(gridViewRcvd.GetRowCellValue(handle, "SeqNo")));

                    try
                    {
                        con.Open();
                        cmd.ExecuteNonQuery();
                    }
                    catch (SqlException ex)
                    {
                        BigAlert.Show("RETURN FAILED", "Failed to return an undelivered item back to origin: " + ex.Message, MessageBoxIcon.Error);
                        return false;
                    }
                }
            }
            return true;
        }

        private void simpleButton2_Click(object sender, EventArgs e)
        {
            gridViewRcvd.CloseEditor();
            gridViewRcvd.UpdateCurrentRow();

            int totalRows = gridViewRcvd.RowCount;
            if (totalRows == 0)
            {
                BigAlert.Show("NOTHING TO PROCESS", "There are no items for this delivery.", MessageBoxIcon.Warning);
                return;
            }

            int[] selectedRows = gridViewRcvd.GetSelectedRows();
            int[] unselectedRows = Enumerable.Range(0, totalRows).Except(selectedRows).ToArray();

            string message = unselectedRows.Length > 0
                ? $"{selectedRows.Length} item(s) will be marked RECEIVED.\n{unselectedRows.Length} unchecked item(s) will be marked NOT RECEIVED and returned to origin.\n\nContinue?"
                : $"All {selectedRows.Length} item(s) will be marked RECEIVED. Continue?";

            bool confirmRcv = HelperFunction.ConfirmDialog(message, "Confirm Inventory Entry");
            if (!confirmRcv)
                return;

            if (!ReceiveSelectedItems(selectedRows))
                return;

            if (!ReturnUnreceivedItems(unselectedRows))
                return;

            if (!ConfirmBranchReceivedOrder())
                return;

            BigAlert.Show("INVENTORY RECEIVED", "ITEMS SUCCESSFULLY PROCESSED, PLEASE CHECK NOW YOUR INVENTORY!..", MessageBoxIcon.Information);
            isdone = true;
            this.Close();
        }

        private void gridView1_RowCellStyle(object sender, RowCellStyleEventArgs e)
        {
            if (e.Column.FieldName == "ActualQty")
            {
                e.Appearance.BackColor = Color.Salmon;
                e.Appearance.BackColor2 = Color.LightSalmon;
            }
        }

        private void gridView1_ShowingEditor(object sender, CancelEventArgs e)
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

        // Renamed from "Cancel Line": previously did a pure client-side grid
        // delete with zero server-side effect (the row's quantity stayed
        // deducted at origin, never received, never marked returned -- the
        // exact "floating inventory" gap this file fixes). Now just
        // unchecks the row so it flows through ReturnUnreceivedItems() on
        // submit instead of vanishing silently.
        private void cancelLineToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (gridViewRcvd.FocusedRowHandle < 0) return;
            gridViewRcvd.UnselectRow(gridViewRcvd.FocusedRowHandle);
        }

        private void gridViewRcvd_RowCellStyle(object sender, RowCellStyleEventArgs e)
        {
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
    }
}
