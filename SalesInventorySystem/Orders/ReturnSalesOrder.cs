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
using DevExpress.XtraEditors.Repository;
using DevExpress.XtraGrid.Views.Grid;
using System.Data.SqlClient;

namespace SalesInventorySystem.Orders
{
    // 2026-10-04: partial return (SQL/2026-10-04_SalesOrder_PartialReturn.sql).
    // Ticking a line fills Return Qty with its billed qty (ActualQty). On a FIFO line
    // (Kind = FIFO) Return Qty can be lowered to return only part of it; a line
    // processed by barcode scan (Kind = SCAN) is one labelled box and is returned
    // whole only. sp_ReturnSalesOrder splits a partly returned line and returns
    // the split-off part; the Return Qty list goes in its optional @ReturnQty.
    // Callers set txtpono / txtdevno / txtbrcode / txtstatus and ShowReturned,
    // then call LoadData().
    public partial class ReturnSalesOrder : DevExpress.XtraEditors.XtraForm
    {
        // Delivered tab: show already-returned lines too (red, can't be ticked).
        public bool ShowReturned { get; set; }

        RepositoryItemSpinEdit repoReturnQty;
        bool _syncing;

        public ReturnSalesOrder()
        {
            InitializeComponent();
            gridView1.ShowingEditor += gridView1_ShowingEditor;
            gridView1.ValidatingEditor += gridView1_ValidatingEditor;
            Classes.DevXGridViewSettings.ApplyTotalsBandAppearance(gridView1);
        }

        public void LoadData()
        {
            const string sql = @"
SELECT v.SeqNo, v.BranchCode, v.DeliveryNo, v.ReferenceNumber, v.ProductNo, v.BarcodeNo, v.PONumber, v.ProductName,
       v.QtyDelivered, v.ActualQty, v.Variance, v.Cost, v.SellingPrice, v.Status, v.isVat, v.ProcessedBy, v.isSettled, v.isReturned,
       CASE WHEN EXISTS (SELECT 1
                         FROM dbo.InventoryDeliveryFIFO f
                         INNER JOIN dbo.Inventory i ON i.SequenceNumber = f.SequenceReferenceNumber
                         WHERE f.PONumber = v.PONumber AND f.DeliveryNo = v.DeliveryNo AND f.DevDetSeqNo = v.SeqNo
                           AND NULLIF(LTRIM(RTRIM(i.Barcode)), '') = LTRIM(RTRIM(v.BarcodeNo)))
            THEN 'SCAN' ELSE 'FIFO' END AS Kind,
       CAST(0 AS DECIMAL(10,3)) AS ReturnQty
FROM dbo.view_BranchOrderDetails v
WHERE v.PONumber = @po AND v.DeliveryNo = @dev AND (@showReturned = 1 OR v.isReturned = 0)
ORDER BY v.SeqNo;";

            DataTable table = new DataTable();
            try
            {
                using (SqlConnection con = Database.getConnection())
                using (SqlCommand com = new SqlCommand(sql, con))
                {
                    com.Parameters.Add("@po", SqlDbType.VarChar, 20).Value = txtpono.Text.Trim();
                    com.Parameters.Add("@dev", SqlDbType.VarChar, 20).Value = txtdevno.Text.Trim();
                    com.Parameters.Add("@showReturned", SqlDbType.Bit).Value = ShowReturned;
                    using (SqlDataAdapter da = new SqlDataAdapter(com))
                        da.Fill(table);
                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show("Failed to load the order lines: " + ex.Message);
                return;
            }

            table.Columns["ReturnQty"].ReadOnly = false;
            table.Columns.Add("ReturnAmount", typeof(decimal), "ReturnQty * SellingPrice");

            gridControl1.BeginUpdate();
            try
            {
                gridView1.Columns.Clear();
                gridControl1.DataSource = table;
                gridView1.PopulateColumns();
                SetupGrid();
            }
            finally
            {
                gridControl1.EndUpdate();
            }
            gridView1.BestFitColumns();
        }

        void SetupGrid()
        {
            // only Return Qty is editable (the designer has the view read-only)
            gridView1.OptionsBehavior.ReadOnly = false;
            gridView1.OptionsBehavior.Editable = true;
            // the tick / Return Qty sync walks row handles 0..DataRowCount-1: keep the grid ungrouped
            gridView1.OptionsCustomization.AllowGroup = false;
            gridView1.OptionsView.ShowGroupPanel = false;
            foreach (DevExpress.XtraGrid.Columns.GridColumn col in gridView1.Columns)
                col.OptionsColumn.AllowEdit = col.FieldName == "ReturnQty";

            if (repoReturnQty == null)
            {
                repoReturnQty = new RepositoryItemSpinEdit();
                repoReturnQty.MinValue = 0;
                repoReturnQty.MaxValue = 9999999;
                repoReturnQty.IsFloatValue = true;
                repoReturnQty.Increment = 1m;
                repoReturnQty.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                repoReturnQty.DisplayFormat.FormatString = "N3";
                repoReturnQty.EditFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                repoReturnQty.EditFormat.FormatString = "N3";
                gridControl1.RepositoryItems.Add(repoReturnQty);
            }
            gridView1.Columns["ReturnQty"].ColumnEdit = repoReturnQty;
            gridView1.Columns["ReturnQty"].Caption = "Return Qty";
            gridView1.Columns["ReturnAmount"].Caption = "Return Amount";
            gridView1.Columns["Kind"].ToolTip = "FIFO: part of the line can be returned. SCAN: a labelled box, returned whole only.";

            foreach (string c in new[] { "QtyDelivered", "ActualQty", "Variance", "ReturnQty" })
                FormatCol(c, "N3");
            foreach (string c in new[] { "Cost", "SellingPrice", "ReturnAmount" })
                FormatCol(c, "N2");

            gridView1.OptionsView.ShowFooter = true;
            gridView1.Columns["ReturnQty"].Summary.Clear();
            gridView1.Columns["ReturnQty"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "ReturnQty", "{0:N3}");
            gridView1.Columns["ReturnAmount"].Summary.Clear();
            gridView1.Columns["ReturnAmount"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "ReturnAmount", "{0:N2}");
        }

        void FormatCol(string field, string format)
        {
            var col = gridView1.Columns[field];
            if (col == null) return;
            col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            col.DisplayFormat.FormatString = format;
        }

        static bool IsRowAlreadyReturned(GridView view, int rowHandle)
        {
            object val = view.GetRowCellValue(rowHandle, "isReturned");
            return val != null && val != DBNull.Value && Convert.ToBoolean(val);
        }

        static bool IsScanRow(GridView view, int rowHandle)
        {
            return string.Equals(Convert.ToString(view.GetRowCellValue(rowHandle, "Kind")), "SCAN", StringComparison.OrdinalIgnoreCase);
        }

        static decimal CellDecimal(GridView view, int rowHandle, string field)
        {
            object v = view.GetRowCellValue(rowHandle, field);
            return v == null || v == DBNull.Value ? 0m : Convert.ToDecimal(v);
        }

        // Rows already returned (isReturned=1 in view_BranchOrderDetails / DeliveryDetails) are
        // highlighted red and can't stay checked -- same "veto the checkbox in SelectionChanged"
        // pattern already used for CheckBoxRowSelect grids elsewhere (see
        // Orders/AddBranchOrderSTSBatchMode.cs, Orders/SearchProductBatchMode.cs).
        private void gridView1_RowStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowStyleEventArgs e)
        {
            GridView view = sender as GridView;
            if (e.RowHandle < 0)
                return;

            if (IsRowAlreadyReturned(view, e.RowHandle))
            {
                e.Appearance.BackColor = Color.Red;
                e.Appearance.BackColor2 = Color.IndianRed;
                e.Appearance.ForeColor = Color.White;
                e.HighPriority = true;
            }
        }

        private void gridView1_SelectionChanged(object sender, DevExpress.Data.SelectionChangedEventArgs e)
        {
            if (_syncing) return;
            _syncing = true;
            try
            {
                // post (or drop) a Return Qty being typed first, so the sync below isn't overwritten by it
                gridView1.CloseEditor();

                // already returned, or nothing billed left (ActualQty 0 after a credit memo): can't be ticked
                for (int i = 0; i < gridView1.DataRowCount; i++)
                {
                    if (gridView1.IsRowSelected(i)
                        && (IsRowAlreadyReturned(gridView1, i) || CellDecimal(gridView1, i, "ActualQty") <= 0))
                    {
                        gridView1.UnselectRow(i);
                    }
                }

                // ticked = return the whole billed qty unless already lowered; unticked = nothing
                for (int i = 0; i < gridView1.DataRowCount; i++)
                {
                    decimal qty = CellDecimal(gridView1, i, "ReturnQty");
                    if (gridView1.IsRowSelected(i))
                    {
                        if (qty <= 0) gridView1.SetRowCellValue(i, "ReturnQty", CellDecimal(gridView1, i, "ActualQty"));
                    }
                    else if (qty != 0)
                    {
                        gridView1.SetRowCellValue(i, "ReturnQty", 0m);
                    }
                }
            }
            finally
            {
                _syncing = false;
            }
        }

        // Return Qty can be edited only on a ticked, not yet returned FIFO line.
        private void gridView1_ShowingEditor(object sender, CancelEventArgs e)
        {
            int h = gridView1.FocusedRowHandle;
            if (gridView1.FocusedColumn == null || gridView1.FocusedColumn.FieldName != "ReturnQty"
                || h < 0 || !gridView1.IsRowSelected(h) || IsRowAlreadyReturned(gridView1, h) || IsScanRow(gridView1, h))
            {
                e.Cancel = true;
            }
        }

        private void gridView1_ValidatingEditor(object sender, DevExpress.XtraEditors.Controls.BaseContainerValidateEditorEventArgs e)
        {
            if (gridView1.FocusedColumn == null || gridView1.FocusedColumn.FieldName != "ReturnQty") return;
            decimal qty;
            if (e.Value == null || !decimal.TryParse(e.Value.ToString(), out qty))
            {
                e.Valid = false; e.ErrorText = "Enter the quantity to return.";
                return;
            }
            qty = Math.Round(qty, 3);   // quantities are DECIMAL(10,3): what is shown is what gets posted
            decimal actual = CellDecimal(gridView1, gridView1.FocusedRowHandle, "ActualQty");
            if (qty <= 0 || qty > actual)
            {
                e.Valid = false;
                e.ErrorText = "Return Qty must be more than 0 and at most the billed qty (" + actual.ToString("N3") + "). Untick the line to leave it out.";
                return;
            }
            e.Value = qty;
        }

        void executeTransfer()
        {
            try
            {
                gridView1.CloseEditor();
                if (!gridView1.UpdateCurrentRow())
                    return;   // the Return Qty being typed is invalid; the editor shows why

                int[] selectedRows = gridView1.GetSelectedRows();

                DataTable dt = new DataTable();
                dt.Columns.Add("SeqNo", typeof(decimal));
                dt.Columns.Add("ProductNo", typeof(string));
                dt.Columns.Add("ProductName", typeof(string));
                dt.Columns.Add("BarcodeNo", typeof(string));
                dt.Columns.Add("QtyDelivered", typeof(decimal));
                dt.Columns.Add("Cost", typeof(decimal));
                dt.Columns.Add("SellingPrice", typeof(decimal));
                dt.Columns.Add("ActualQty", typeof(decimal));
                dt.Columns.Add("Variance", typeof(double));
                dt.Columns.Add("isVat", typeof(bool));

                DataTable qtyTable = new DataTable();
                qtyTable.Columns.Add("SeqNo", typeof(decimal));
                qtyTable.Columns.Add("ProductNo", typeof(string));
                qtyTable.Columns.Add("ReturnQty", typeof(decimal));

                StringBuilder summary = new StringBuilder();
                decimal totalAmount = 0m;

                foreach (int rowHandle in selectedRows)
                {
                    if (rowHandle < 0 || IsRowAlreadyReturned(gridView1, rowHandle))
                        continue;

                    decimal seq = Convert.ToDecimal(gridView1.GetRowCellValue(rowHandle, "SeqNo"));
                    string prod = Convert.ToString(gridView1.GetRowCellValue(rowHandle, "ProductNo"));
                    string name = Convert.ToString(gridView1.GetRowCellValue(rowHandle, "ProductName"));
                    decimal actual = CellDecimal(gridView1, rowHandle, "ActualQty");
                    decimal price = CellDecimal(gridView1, rowHandle, "SellingPrice");
                    decimal retQty = Math.Round(CellDecimal(gridView1, rowHandle, "ReturnQty"), 3);
                    object variance = gridView1.GetRowCellValue(rowHandle, "Variance");

                    if (IsScanRow(gridView1, rowHandle))
                        retQty = actual;   // a scanned box goes back whole
                    if (retQty <= 0 || retQty > actual)
                    {
                        XtraMessageBox.Show("Line " + seq + " (" + name.Trim() + "): Return Qty must be more than 0 and at most " + actual.ToString("N3") + ".");
                        return;
                    }

                    dt.Rows.Add(
                        seq,
                        prod,
                        name,
                        Convert.ToString(gridView1.GetRowCellValue(rowHandle, "BarcodeNo")),
                        CellDecimal(gridView1, rowHandle, "QtyDelivered"),
                        CellDecimal(gridView1, rowHandle, "Cost"),
                        price,
                        actual,
                        variance == null || variance == DBNull.Value ? 0d : Convert.ToDouble(variance),
                        Convert.ToBoolean(gridView1.GetRowCellValue(rowHandle, "isVat")));
                    qtyTable.Rows.Add(seq, prod, retQty);

                    decimal amount = Math.Round(retQty * price, 2);
                    totalAmount += amount;
                    summary.AppendLine("Line " + seq + "  " + name.Trim() + ":  " + retQty.ToString("N3")
                        + (retQty < actual ? " of " + actual.ToString("N3") + " (partial)" : " (whole line)")
                        + "  =  " + amount.ToString("N2"));
                }

                if (dt.Rows.Count == 0)
                {
                    XtraMessageBox.Show("Please select at least one item to return (Checked column).");
                    return;
                }

                summary.AppendLine();
                summary.AppendLine("Total return amount:  " + totalAmount.ToString("N2"));
                if (XtraMessageBox.Show(summary.ToString(), "Confirm Sales Return", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                    return;

                sp(dt, qtyTable);
                // Only reached when sp_ReturnSalesOrder committed: sp() lets its SqlException through.
                XtraMessageBox.Show("Successfully Returned!..");
                this.Close();
            }
            catch (SqlException ex)
            {
                // Nothing was returned (the proc rolls back on any error); keep the form open.
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }

        // No catch here on purpose: it used to swallow the SqlException, so executeTransfer()
        // showed "Successfully Returned!" and closed the form even when the return had failed.
        void sp(DataTable lines, DataTable returnQty)
        {
            using (SqlConnection con = Database.getConnection())
            using (SqlCommand com = new SqlCommand("sp_ReturnSalesOrder", con))
            {
                com.CommandType = CommandType.StoredProcedure;
                com.Parameters.AddWithValue("@parmbranchcode", txtbrcode.Text);
                com.Parameters.AddWithValue("@parmpono", txtpono.Text);
                com.Parameters.AddWithValue("@parmdevno", txtdevno.Text);
                com.Parameters.AddWithValue("@parmuser", Login.Fullname);
                com.Parameters.AddWithValue("@parmreturnstatus", txtstatus.Text);
                com.Parameters.AddWithValue("@parmreason", txtreason.Text);
                com.Parameters.AddWithValue("@parmmachinename", GlobalVariables.computerName);
                var tvpParam = com.Parameters.AddWithValue("@Lines", lines);
                tvpParam.SqlDbType = SqlDbType.Structured;
                tvpParam.TypeName = "dbo.tt_ReturnSalesOrderLines";
                var qtyParam = com.Parameters.AddWithValue("@ReturnQty", returnQty);
                qtyParam.SqlDbType = SqlDbType.Structured;
                qtyParam.TypeName = "dbo.tt_ReturnSalesOrderQty";
                con.Open();
                com.ExecuteNonQuery();
            }
        }
        private void simpleButton1_Click(object sender, EventArgs e)
        {
            if(String.IsNullOrEmpty(txtreason.Text))
            {
                XtraMessageBox.Show("Please enter a reason for the return.");
                return;
            }

            // A second click while the return posts would submit the same lines again.
            simpleButton1.Enabled = false;
            try
            {
                executeTransfer();
            }
            finally
            {
                if (!IsDisposed)
                    simpleButton1.Enabled = true;
            }
        }

        private void ReturnSalesOrder_Load(object sender, EventArgs e)
        {

        }
    }
}
