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
    // Parallel counterpart to ReceivedSTSBatchMode.cs -- sources its grid from
    // funcview_InventoryDeliveryFIFOForReceiving instead of
    // funcview_DeliveryDetailsForReceiving, so each line carries the true
    // source-lot ReferenceCode (SourceReferenceCode) via InventoryDeliveryFIFO,
    // instead of the destination Inventory row being stamped with the PONumber.
    // ReceivedSTSBatchMode.cs, funcview_DeliveryDetailsForReceiving, and
    // sp_AddBranchInventoryBatch are untouched by this module.
    public partial class ReceivedSTSBatchModeFIFO : DevExpress.XtraEditors.XtraForm
    {
        public static bool isdone = false;

        public ReceivedSTSBatchModeFIFO()
        {
            InitializeComponent();
        }

        private void ReceivedSTSBatchModeFIFO_Load(object sender, EventArgs e)
        {
            // Everything defaults to RECEIVED; the user unchecks whatever did
            // not physically arrive. Grid is expected to already be bound
            // (by the caller, ReceivedSTS.cs) before this form is shown.
            FormatReceiveColumns();
            gridViewRcvd.SelectAll();
        }

        // Columns auto-generate from funcview_InventoryDeliveryFIFOForReceiving.
        // 2026-10-03: a row can be several lines (FIFO lines of one product added up):
        // LineKind = SCAN / FIFO, LineCount = lines in the row.
        void FormatReceiveColumns()
        {
            var kind = gridViewRcvd.Columns["LineKind"];
            if (kind != null) kind.Caption = "Kind";
            var lineCount = gridViewRcvd.Columns["LineCount"];
            if (lineCount != null) lineCount.Caption = "Lines";

            foreach (string name in new[] { "QtyDelivered", "ActualQty" })
                FormatNumber(name, "N3");
            foreach (string name in new[] { "Cost", "SellingPrice" })
                FormatNumber(name, "N2");

            gridViewRcvd.BestFitColumns();
        }

        void FormatNumber(string fieldName, string format)
        {
            var col = gridViewRcvd.Columns[fieldName];
            if (col == null) return;
            col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            col.DisplayFormat.FormatString = format;
        }

        int LinesInRows(int[] rowHandles)
        {
            int lines = 0;
            foreach (int handle in rowHandles)
            {
                object v = gridViewRcvd.GetRowCellValue(handle, "LineCount");
                lines += (v == null || v == DBNull.Value) ? 1 : Convert.ToInt32(v);
            }
            return lines;
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

        // Only rows the user left CHECKED are submitted as received. Calls
        // spu_PostSTSReceiveFromFIFO (dedicated to this module) instead of
        // sp_AddBranchInventoryBatch -- it re-derives ReferenceCode server-side
        // from InventoryDeliveryFIFO and reconciles the destination Inventory
        // row spu_PostSTSDispatch already created, rather than relying on the
        // black-box legacy receive SP.
        bool ReceiveSelectedItems(int[] selectedRowHandles)
         {
            DataTable lines = new DataTable();
            lines.Columns.Add("SeqNo", typeof(int));
            lines.Columns.Add("DeliveryNo", typeof(string));
            lines.Columns.Add("ProductCode", typeof(string));
            lines.Columns.Add("Barcode", typeof(string));
            lines.Columns.Add("ActualQty", typeof(decimal));
            lines.Columns.Add("SellingPrice", typeof(decimal));

            foreach (int handle in selectedRowHandles)
            {
                int seqNo = Convert.ToInt32(gridViewRcvd.GetRowCellValue(handle, "SeqNo"));
                string deliveryNo = gridViewRcvd.GetRowCellValue(handle, "DeliveryNo").ToString();
                string productCode = gridViewRcvd.GetRowCellValue(handle, "ProductNo").ToString();
                string barcode = gridViewRcvd.GetRowCellValue(handle, "BarcodeNo").ToString();
                decimal actualQty = Convert.ToDecimal(gridViewRcvd.GetRowCellValue(handle, "ActualQty"));
                decimal sellingPrice = Convert.ToDecimal(gridViewRcvd.GetRowCellValue(handle, "SellingPrice"));
                lines.Rows.Add(seqNo, deliveryNo, productCode, barcode, actualQty, sellingPrice);
            }

            if (lines.Rows.Count == 0)
                return true; // nothing checked -- not a failure, just nothing to receive

            using (SqlConnection con = Database.getConnection())
            using (SqlCommand cmd = new SqlCommand("spu_PostSTSReceiveFromFIFO", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.CommandTimeout = 120;
                cmd.Parameters.AddWithValue("@PONumber", txtshipmentno.Text);
                cmd.Parameters.AddWithValue("@BranchCode", Login.assignedBranch);
                cmd.Parameters.AddWithValue("@ReceivedBy", Login.isglobalUserID);

                SqlParameter tvpParam = cmd.Parameters.AddWithValue("@Lines", lines);
                tvpParam.SqlDbType = SqlDbType.Structured;
                tvpParam.TypeName = "dbo.tt_STSReceiveFIFOLines";
                // rows come from funcview_InventoryDeliveryFIFOForReceivingV2: a row can be several lines
                cmd.Parameters.Add("@GroupedRows", SqlDbType.Bit).Value = true;

                try
                {
                    con.Open();
                    using (SqlDataReader reader = cmd.ExecuteReader())
                    {
                        var skipped = new List<string>();
                        while (reader.Read())
                            skipped.Add($"{reader["Barcode"]}: {reader["Reason"]}");

                        if (skipped.Count > 0)
                        {
                            BigAlert.Show("SOME LINES SKIPPED",
                                "The following line(s) were not received:\n" + string.Join("\n", skipped),
                                MessageBoxIcon.Warning);
                        }
                    }
                    return true;
                }
                catch (SqlException ex)
                {
                    BigAlert.Show("RECEIVE FAILED", ex.Message, MessageBoxIcon.Error);
                    return false;
                }
            }
        }

        // Rows left UNCHECKED never arrived -- reuses sp_ReverseSTSInventoryTransfer
        // unchanged (same SP ReceivedSTSBatchMode.cs uses): restores origin
        // Inventory, reverses the GL leg if the transfer was confirmed, and
        // corrects DeliverySummary.Status once nothing is left for this dispatch.
        // 2026-10-03: a grid row can stand for several lines (FIFO lines of one
        // product are added up into one row), so each line of the row is returned:
        // funcview_STSReceiveLines, GroupSeqNo = the row's SeqNo.
        DataTable GetRowLines(string deliveryNo, int groupSeqNo)
        {
            DataTable lines = new DataTable();
            using (SqlConnection con = Database.getConnection())
            using (SqlCommand cmd = new SqlCommand(
                "SELECT SeqNo, DeliveryNo, ReferenceNumber, ProductNo, QtyDelivered " +
                "FROM dbo.funcview_STSReceiveLines(@PONumber) " +
                "WHERE DeliveryNo = @DeliveryNo AND GroupSeqNo = @GroupSeqNo ORDER BY SeqNo", con))
            {
                cmd.CommandTimeout = 120;
                cmd.Parameters.Add("@PONumber", SqlDbType.VarChar, 10).Value = txtshipmentno.Text;
                cmd.Parameters.Add("@DeliveryNo", SqlDbType.VarChar, 20).Value = deliveryNo;
                cmd.Parameters.Add("@GroupSeqNo", SqlDbType.Int).Value = groupSeqNo;
                using (SqlDataAdapter da = new SqlDataAdapter(cmd))
                    da.Fill(lines);
            }
            return lines;
        }

        bool ReturnUnreceivedItems(int[] unselectedRowHandles)
        {
            foreach (int handle in unselectedRowHandles)
            {
                string deliveryNo = gridViewRcvd.GetRowCellValue(handle, "DeliveryNo").ToString();
                int groupSeqNo = Convert.ToInt32(gridViewRcvd.GetRowCellValue(handle, "SeqNo"));
                DataTable rowLines;
                try
                {
                    rowLines = GetRowLines(deliveryNo, groupSeqNo);
                }
                catch (SqlException ex)
                {
                    BigAlert.Show("RETURN FAILED", "Could not read the lines of an unchecked item: " + ex.Message, MessageBoxIcon.Error);
                    return false;
                }

                // the row must still be the lines it showed (none received / returned meanwhile)
                int shownLines = LinesInRows(new[] { handle });
                if (rowLines.Rows.Count == 0 || rowLines.Rows.Count != shownLines)
                {
                    BigAlert.Show("RETURN FAILED",
                        "Item " + gridViewRcvd.GetRowCellValue(handle, "ProductNo") + " changed since this screen was opened " +
                        "(a line of it was already received or returned). Close the screen and open the transfer again.", MessageBoxIcon.Error);
                    return false;
                }

                // each line is its own return: if one fails, say which lines of the row went back already
                var returned = new List<string>();
                foreach (DataRow line in rowLines.Rows)
                {
                    string error = ReturnLine(line);
                    if (error != null)
                    {
                        string done = returned.Count == 0
                            ? ""
                            : "\n\nAlready returned to origin from this item: line(s) " + string.Join(", ", returned) +
                              ". Open the transfer again to see what is left.";
                        BigAlert.Show("RETURN FAILED",
                            "Failed to return line " + line["SeqNo"] + " (" + line["ProductNo"] + ") back to origin: " + error + done,
                            MessageBoxIcon.Error);
                        return false;
                    }
                    returned.Add(line["SeqNo"].ToString());
                }
            }
            return true;
        }

        // Returns null when the line went back, else the error message.
        string ReturnLine(DataRow line)
        {
            using (SqlConnection con = Database.getConnection())
            using (SqlCommand cmd = new SqlCommand("sp_ReverseSTSInventoryTransfer", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.CommandTimeout = 120;
                cmd.Parameters.AddWithValue("@parmdevno", line["DeliveryNo"].ToString());
                cmd.Parameters.AddWithValue("@parmrefno", line["ReferenceNumber"].ToString());
                cmd.Parameters.AddWithValue("@parmpono", txtshipmentno.Text);
                cmd.Parameters.AddWithValue("@parmprodno", line["ProductNo"].ToString());
                cmd.Parameters.AddWithValue("@parmqty", Convert.ToDecimal(line["QtyDelivered"]));
                // Roles are flipped from the dispatch side: here the
                // receiving branch IS the destination (@parmbranchcode),
                // and HO (888) is always the origin for this HO-outbound
                // STS flow -- same convention sp_ConfirmBranchOrderSTS
                // itself hardcodes for its GL ticket branch.
                cmd.Parameters.AddWithValue("@parmbranchcode", Login.assignedBranch);
                cmd.Parameters.AddWithValue("@parmorigin", "888");
                cmd.Parameters.AddWithValue("@preparedby", Login.Fullname);
                cmd.Parameters.AddWithValue("@parmdevseqno", Convert.ToInt32(line["SeqNo"]));

                try
                {
                    con.Open();
                    cmd.ExecuteNonQuery();
                }
                catch (SqlException ex)
                {
                    return ex.Message;
                }
            }
            return null;
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

            // a row can be several lines (FIFO lines of one product added up): show both counts
            int selectedLines = LinesInRows(selectedRows), unselectedLines = LinesInRows(unselectedRows);
            string message = unselectedRows.Length > 0
                ? $"{selectedRows.Length} item(s) ({selectedLines} line(s)) will be marked RECEIVED.\n{unselectedRows.Length} unchecked item(s) ({unselectedLines} line(s)) will be marked NOT RECEIVED and returned to origin.\n\nContinue?"
                : $"All {selectedRows.Length} item(s) ({selectedLines} line(s)) will be marked RECEIVED. Continue?";

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

        // Unchecks the row so it flows through ReturnUnreceivedItems() on
        // submit instead of vanishing silently -- same fix ReceivedSTSBatchMode.cs
        // already carries for this exact "floating inventory" gap.
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
