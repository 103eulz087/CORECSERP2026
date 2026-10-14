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

        // 2026-10-14 ([85], hardening H4): the ticked rows (received), the unticked rows
        // (returned to the origin, line by line) and the confirmation (IT-BR / STS-SHORT /
        // STS-OVER tickets, DELIVERED) are ONE call, spu_STS_ReceiveTransfer, which runs the
        // same three procs this screen used to call one by one (spu_PostSTSReceiveFromFIFO,
        // sp_ReverseSTSInventoryTransfer, sp_ConfirmBranchRecievedOrderJFC) in one
        // transaction under the transfer's lock. A failure anywhere leaves nothing posted.
        // The proc also refuses a stale screen (59624 a row's lines changed, 59626 a line
        // not on the screen) and returns the lines the receive step skipped, as before.
        // Rows come from funcview_InventoryDeliveryFIFOForReceivingV2: a row can be several
        // lines (@GroupedRows = 1), LineCount = the lines it showed.
        bool PostReceipt(int[] selectedRowHandles, int[] unselectedRowHandles)
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
                object qtyCell = gridViewRcvd.GetRowCellValue(handle, "ActualQty");
                object priceCell = gridViewRcvd.GetRowCellValue(handle, "SellingPrice");
                decimal actualQty = qtyCell == null || qtyCell == DBNull.Value ? 0m : Convert.ToDecimal(qtyCell);
                decimal sellingPrice = priceCell == null || priceCell == DBNull.Value ? 0m : Convert.ToDecimal(priceCell);
                lines.Rows.Add(seqNo, deliveryNo, productCode, barcode, actualQty, sellingPrice);
            }

            DataTable returnRows = new DataTable();
            returnRows.Columns.Add("DeliveryNo", typeof(string));
            returnRows.Columns.Add("SeqNo", typeof(int));
            returnRows.Columns.Add("LineCount", typeof(int));

            foreach (int handle in unselectedRowHandles)
            {
                string deliveryNo = gridViewRcvd.GetRowCellValue(handle, "DeliveryNo").ToString();
                int groupSeqNo = Convert.ToInt32(gridViewRcvd.GetRowCellValue(handle, "SeqNo"));
                returnRows.Rows.Add(deliveryNo, groupSeqNo, LinesInRows(new[] { handle }));
            }

            using (SqlConnection con = Database.getConnection())
            using (SqlCommand cmd = new SqlCommand("spu_STS_ReceiveTransfer", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.CommandTimeout = 180;
                cmd.Parameters.Add("@PONumber", SqlDbType.VarChar, 10).Value = txtshipmentno.Text;
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 10).Value = Login.assignedBranch;
                cmd.Parameters.Add("@ReceivedBy", SqlDbType.VarChar, 40).Value = Login.isglobalUserID;
                cmd.Parameters.Add("@PreparedBy", SqlDbType.VarChar, 30).Value = Login.Fullname;

                SqlParameter linesParam = cmd.Parameters.AddWithValue("@Lines", lines);
                linesParam.SqlDbType = SqlDbType.Structured;
                linesParam.TypeName = "dbo.tt_STSReceiveFIFOLines";

                SqlParameter returnParam = cmd.Parameters.AddWithValue("@ReturnRows", returnRows);
                returnParam.SqlDbType = SqlDbType.Structured;
                returnParam.TypeName = "dbo.tt_STSReceiveReturnRows";

                cmd.Parameters.Add("@GroupedRows", SqlDbType.Bit).Value = true;
                // Roles are flipped from the dispatch side: the receiving branch is the
                // destination, and HO (888) is always the origin of this HO-outbound STS flow
                // (the same convention sp_ConfirmBranchOrderSTS hardcodes for its GL ticket).
                cmd.Parameters.Add("@Origin", SqlDbType.VarChar, 10).Value = "888";
                cmd.Parameters.Add("@UseJFC", SqlDbType.Bit).Value = GlobalCache.CompanyName == "JFC";

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
                                "The following line(s) were not received (the rest of the transfer was posted):\n" + string.Join("\n", skipped),
                                MessageBoxIcon.Warning);
                        }
                    }
                    return true;
                }
                catch (SqlException ex)
                {
                    BigAlert.Show("RECEIVE FAILED", "Nothing was posted (if the connection dropped, reopen the transfer to check). " + ex.Message, MessageBoxIcon.Error);
                    return false;
                }
            }
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

            // 2026-10-14 ([85], hardening H4): ONE call does the three steps in one transaction
            // (receive the ticked rows, return the unticked rows to the origin, confirm the
            // receipt). Before, ReceiveSelectedItems / ReturnUnreceivedItems /
            // ConfirmBranchReceivedOrder each committed on their own, so a failure in a later
            // step left the earlier ones posted (branch stock received, transfer still FOR
            // DELIVERY, In Transit not cleared).
            if (!PostReceipt(selectedRows, unselectedRows))
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

        // Unchecks the row so PostReceipt() sends it as an unticked row (returned
        // to the origin) on submit instead of vanishing silently -- same fix
        // ReceivedSTSBatchMode.cs already carries for this exact "floating inventory" gap.
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
