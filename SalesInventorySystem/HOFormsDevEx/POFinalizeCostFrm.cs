using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.HOFormsDevEx
{
    /// <summary>
    /// "Confirm and Finalize Cost" for a received PO shipment (opened from
    /// VIEWPO's FOR CONFIRMATION tab). Receiving (SP_POSTINVENTORY) leaves
    /// the shipment's Inventory at Available = 0 and the PO at FOR
    /// CONFIRMATION; here the user reviews one row per distinct item
    /// (Quantity summed across lots, received Cost retained read-only) and
    /// edits a FINAL COST. CONFIRM posts everything atomically through
    /// spu_ConfirmPOFinalCost (SQL/2026-09-21_POFinalizeCost.sql), which sets
    /// Inventory.Cost = final cost, Inventory.Available = Quantity and
    /// POSUMMARY.Status = 'RECEIVED'. Read-only fetch and post both run on
    /// the UI thread (no Task.Run, so no cross-thread control access).
    /// </summary>
    public partial class POFinalizeCostFrm : DevExpress.XtraEditors.XtraForm
    {
        private readonly string _shipmentNo;
        private readonly string _supplierId;
        private readonly string _supplierName;
        private DataTable _items;
        private bool _dataLoaded = false;

        public POFinalizeCostFrm(string shipmentNo, string supplierId, string supplierName)
        {
            InitializeComponent();
            _shipmentNo = shipmentNo;
            _supplierId = supplierId;
            _supplierName = supplierName;

            Classes.DevXGridViewSettings.ApplyTotalsBandAppearance(gridViewItems);
        }

        // Guarded fallback only - LoadData() is the real init entry point
        // (VIEWPO calls it before ShowDialog so an empty/changed PO never
        // opens a blank dialog).
        private void POFinalizeCostFrm_Load(object sender, EventArgs e)
        {
            if (!_dataLoaded) LoadData();
        }

        /// <summary>
        /// Fetches the items awaiting cost finalization and binds the grid.
        /// Returns false (after telling the user why) when there is nothing
        /// to finalize, so the caller can skip opening the dialog.
        /// </summary>
        public bool LoadData()
        {
            lblShipment.Text = "Shipment No: " + _shipmentNo;
            lblSupplier.Text = "Supplier: " + _supplierId + " - " + _supplierName;

            var table = new DataTable();
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_GetPOFinalCostItems", con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 120 })
                {
                    cmd.Parameters.Add("@parmshipmentno", SqlDbType.VarChar, 50).Value = _shipmentNo;
                    cmd.Parameters.Add("@parmsupplierid", SqlDbType.VarChar, 50).Value = _supplierId;
                    con.Open();
                    new SqlDataAdapter(cmd).Fill(table);
                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load the items for this PO:\n{ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return false;
            }

            if (table.Rows.Count == 0)
            {
                XtraMessageBox.Show(
                    "There are no items awaiting cost confirmation for this PO.\nIts status may have changed - refresh the FOR CONFIRMATION tab.",
                    "Nothing to Finalize", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return false;
            }

            // FINAL COST starts at the received cost, so only the items whose
            // cost actually changed need editing.
            table.Columns.Add("FinalCost", typeof(decimal));
            foreach (DataRow row in table.Rows) row["FinalCost"] = ToDecimal(row["Cost"]);

            // Totals are derived, never typed - expression columns keep them
            // in step with every FinalCost edit.
            table.Columns.Add("Total", typeof(decimal), "Quantity * Cost");
            table.Columns.Add("FinalTotal", typeof(decimal), "Quantity * FinalCost");

            _items = table;
            gridControlItems.DataSource = _items;
            FormatColumns();
            _dataLoaded = true;
            return true;
        }

        private void FormatColumns()
        {
            var view = gridViewItems;

            SetCol("Product", "Product", 0);
            SetCol("Description", "Description", 1);
            SetCol("Quantity", "Qty", 2);
            SetCol("Cost", "Cost", 3);
            SetCol("Total", "Total Cost", 4);
            SetCol("FinalCost", "FINAL COST", 5);
            SetCol("FinalTotal", "Final Total", 6);

            // Only Final Cost is editable.
            foreach (DevExpress.XtraGrid.Columns.GridColumn col in view.Columns)
                col.OptionsColumn.AllowEdit = col.FieldName == "FinalCost";

            // Quantity N3, money N2 - row cells AND footer sums (CLAUDE.md numeric-column rule).
            FormatNumeric("Quantity", "n3");
            FormatNumeric("Cost", "n2");
            FormatNumeric("Total", "n2");
            FormatNumeric("FinalCost", "n2");
            FormatNumeric("FinalTotal", "n2");

            view.Columns["Quantity"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "Quantity", "{0:n3}");
            view.Columns["Total"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "Total", "{0:n2}");
            view.Columns["FinalTotal"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "FinalTotal", "{0:n2}");

            view.BestFitColumns();
        }

        private void SetCol(string field, string caption, int index)
        {
            var col = gridViewItems.Columns[field];
            if (col == null) return;
            col.Caption = caption;
            col.VisibleIndex = index;
        }

        private void FormatNumeric(string field, string format)
        {
            var col = gridViewItems.Columns[field];
            if (col == null) return;
            col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            col.DisplayFormat.FormatString = format;
        }

        private void GridViewItems_CustomRowCellEdit(object sender, DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "FinalCost") e.RepositoryItem = repFinalCost;
        }

        // Tint the editable column, and highlight a Final Cost that differs
        // from the received Cost so changes are easy to spot before Confirm.
        private void GridViewItems_RowCellStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowCellStyleEventArgs e)
        {
            if (e.Column.FieldName != "FinalCost") return;

            decimal cost = ToDecimal(gridViewItems.GetRowCellValue(e.RowHandle, "Cost"));
            decimal finalCost = ToDecimal(gridViewItems.GetRowCellValue(e.RowHandle, "FinalCost"));
            e.Appearance.BackColor = finalCost != cost
                ? System.Drawing.Color.Gold
                : System.Drawing.Color.LightYellow;
        }

        private void BtnCancel_Click(object sender, EventArgs e)
        {
            DialogResult = DialogResult.Cancel;
            Close();
        }

        private void BtnConfirm_Click(object sender, EventArgs e)
        {
            if (_items == null || _items.Rows.Count == 0) return;

            // Commit an edit still open in the cell before reading values.
            gridViewItems.CloseEditor();
            gridViewItems.UpdateCurrentRow();

            for (int i = 0; i < _items.Rows.Count; i++)
            {
                if (ToDecimal(_items.Rows[i]["FinalCost"]) <= 0)
                {
                    XtraMessageBox.Show(
                        $"Item {_items.Rows[i]["Product"]}: Final Cost must be greater than zero.",
                        "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    gridViewItems.FocusedRowHandle = gridViewItems.GetRowHandle(i);
                    gridViewItems.FocusedColumn = gridViewItems.Columns["FinalCost"];
                    return;
                }
            }

            decimal receivedTotal = 0, finalTotal = 0;
            int changed = 0;
            foreach (DataRow r in _items.Rows)
            {
                decimal qty = ToDecimal(r["Quantity"]);
                decimal cost = ToDecimal(r["Cost"]);
                decimal fc = ToDecimal(r["FinalCost"]);
                receivedTotal += qty * cost;
                finalTotal += qty * fc;
                if (fc != cost) changed++;
            }

            string summary =
                $"Finalize the cost of PO shipment {_shipmentNo}?\n\n" +
                $"Items: {_items.Rows.Count}  (cost changed on {changed})\n" +
                $"Received total: {receivedTotal:N2}\n" +
                $"Final total:    {finalTotal:N2}\n\n" +
                "The inventory will become available and the PO will be marked RECEIVED. This cannot be edited afterwards.";

            if (XtraMessageBox.Show(summary, "Confirm and Finalize Cost", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;

            var lines = new DataTable();
            lines.Columns.Add("Product", typeof(string));
            lines.Columns.Add("FinalCost", typeof(decimal));   // must match dbo.POFinalCostTVP's column order
            foreach (DataRow r in _items.Rows)
                lines.Rows.Add(r["Product"].ToString(), ToDecimal(r["FinalCost"]));

            btnConfirm.Enabled = false;   // no double-submit while the post is running
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("spu_ConfirmPOFinalCost", con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 120 })
                {
                    cmd.Parameters.Add("@parmshipmentno", SqlDbType.VarChar, 50).Value = _shipmentNo;
                    cmd.Parameters.Add("@parmsupplierid", SqlDbType.VarChar, 50).Value = _supplierId;
                    cmd.Parameters.Add("@parmuser", SqlDbType.VarChar, 50).Value = Convert.ToString(Login.isglobalUserID) ?? "";

                    var linesParam = cmd.Parameters.AddWithValue("@Lines", lines);
                    linesParam.SqlDbType = SqlDbType.Structured;
                    linesParam.TypeName = "dbo.POFinalCostTVP";

                    con.Open();
                    string message = "Cost finalized and inventory released.";
                    using (var rdr = cmd.ExecuteReader())
                        if (rdr.Read()) message = rdr["Message"]?.ToString() ?? message;

                    XtraMessageBox.Show(message, "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }

                DialogResult = DialogResult.OK;
                Close();
            }
            catch (SqlException ex)
            {
                btnConfirm.Enabled = true;
                XtraMessageBox.Show($"Could not finalize the cost:\n{ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private static decimal ToDecimal(object value)
        {
            if (value == null || value == DBNull.Value) return 0m;
            decimal.TryParse(value.ToString(), out decimal result);
            return result;
        }
    }
}
