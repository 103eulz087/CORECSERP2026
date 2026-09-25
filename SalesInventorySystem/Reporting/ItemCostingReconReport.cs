using System;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.Reporting
{
    // Item Costing Recon -- master-detail view of how PO-linked SINGLE-mode
    // expenses built up each shipment's landed cost (spu_PostExpenseV2).
    //
    // Master: one row per PO shipment (sp_rpt_ItemCostingRecon_List result
    // set 1) -- expense count, invoice vs INVENTORY cost, per-unit cost
    // incorporated, live Inventory.Cost, variance and a ReconStatus.
    // Detail ("Linked Expenses", expand a row): each linked expense with its
    // invoice Amount (reference only), InventoryCost (net 10104 INVENTORY
    // legs of its own ticket -- the part actually costed, see
    // SQL/2026-09-24_ExpenseInventoryCosting_InventoryLegsOnly.sql), per-unit
    // Cost Derived and a per-shipment Running Total. The master's Cost
    // Incorporated equals the last Running Total of its details by
    // construction (same SUM in the SP).
    //
    // ReconStatus: MATCHED (live cost = incorporated within 0.01), VARIANCE
    // (manual override, spu_ConfirmPOFinalCost final cost, pre-2026-09-24
    // whole-invoice costing, an edited linked expense...), LOTS DIVERGE,
    // NO INVENTORY, NO EXPENSES.
    public partial class ItemCostingReconReport : XtraForm
    {
        private const string RelationName = "Linked Expenses";
        private Font _statusFont;   // cached - RowCellStyle fires on every paint

        public ItemCostingReconReport()
        {
            InitializeComponent();
            Classes.DevXGridViewSettings.ApplyTotalsBandAppearance(gridViewMaster);
            Classes.DevXGridViewSettings.ApplyTotalsBandAppearance(gridViewExpenses);
        }

        private void ItemCostingReconReport_Load(object sender, EventArgs e)
        {
            Database.displaySearchlookupEdit(
                @"SELECT ShipmentNo, SupplierName,
                         ShipmentNo + ' - ' + SupplierName AS DisplayText
                  FROM view_POSUMMARYREP
                  ORDER BY ShipmentNo DESC",
                cboShipmentNo, "DisplayText", "ShipmentNo");
            if (cboShipmentNo.Properties.View.Columns["DisplayText"] != null)
                cboShipmentNo.Properties.View.Columns["DisplayText"].Visible = false;

            // Default window: start of last month to today. Either date can be
            // cleared to leave that side open. No auto-load -- matches the other
            // Reporting/ forms, which wait for an explicit Load click.
            DateTime today = DateTime.Today;
            dtFrom.EditValue = new DateTime(today.Year, today.Month, 1).AddMonths(-1);
            dtTo.EditValue = today;
        }

        private void cboShipmentNo_ButtonClick(object sender, DevExpress.XtraEditors.Controls.ButtonPressedEventArgs e)
        {
            if (e.Button.Kind == DevExpress.XtraEditors.Controls.ButtonPredefines.Delete)
                cboShipmentNo.EditValue = null;   // back to "(all shipments)"
        }

        private void btnLoad_Click(object sender, EventArgs e)
        {
            LoadReport();
        }

        private void LoadReport()
        {
            DateTime? dateFrom = dtFrom.EditValue as DateTime?;
            DateTime? dateTo = dtTo.EditValue as DateTime?;
            if (dateFrom.HasValue && dateTo.HasValue && dateFrom.Value.Date > dateTo.Value.Date)
            {
                XtraMessageBox.Show("PO Date From cannot be later than To.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            string shipmentNo = cboShipmentNo.EditValue?.ToString();

            try
            {
                var ds = new DataSet();
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_rpt_ItemCostingRecon_List", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 300;
                    cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value = dateFrom.HasValue ? (object)dateFrom.Value.Date : DBNull.Value;
                    cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value = dateTo.HasValue ? (object)dateTo.Value.Date : DBNull.Value;
                    cmd.Parameters.Add("@ShipmentNo", SqlDbType.VarChar, 10).Value =
                        string.IsNullOrWhiteSpace(shipmentNo) ? (object)DBNull.Value : shipmentNo;
                    cmd.Parameters.Add("@OnlyWithExpenses", SqlDbType.Bit).Value = chkOnlyWithExpenses.Checked;

                    using (var da = new SqlDataAdapter(cmd))
                    {
                        // Result-set order is the SP's documented contract: 1 = Master, 2 = Detail.
                        da.TableMappings.Add("Table", "Master");
                        da.TableMappings.Add("Table1", "Detail");
                        Cursor.Current = Cursors.WaitCursor;
                        da.Fill(ds);
                    }
                }

                BindMasterDetail(ds);

                if (ds.Tables["Master"].Rows.Count == 0)
                    XtraMessageBox.Show("No shipments found for the selected filters.", "No Data", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message, "Load Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                Cursor.Current = Cursors.Default;
            }
        }

        private void BindMasterDetail(DataSet ds)
        {
            // createConstraints=false: a detail row can never be orphaned by the
            // SP today, but don't let a future filter change turn that into a
            // "constraint cannot be enabled" exception.
            ds.Relations.Add(new DataRelation(RelationName,
                ds.Tables["Master"].Columns["ShipmentNo"],
                ds.Tables["Detail"].Columns["ShipmentNo"],
                false));

            gridRecon.BeginUpdate();
            try
            {
                // Clear before rebinding: DevExpress otherwise reuses the same
                // GridColumn objects across loads and every Summary.Add below
                // would stack another footer total onto them (same fix as
                // Reporting/InventoryReport.cs).
                gridRecon.DataSource = null;
                gridRecon.LevelTree.Nodes.Clear();
                gridViewMaster.Columns.Clear();

                gridRecon.LevelTree.Nodes.Add(RelationName, gridViewExpenses);
                gridRecon.DataSource = ds;
                gridRecon.DataMember = "Master";
                gridRecon.ForceInitialize();

                // The detail view is a template (clones are made per expanded
                // row), so build its columns explicitly from the detail table.
                // Cleared first for the same reason as the master above -
                // PopulateColumns reuses same-named columns and their summaries.
                gridViewExpenses.Columns.Clear();
                gridViewExpenses.PopulateColumns(ds.Tables["Detail"]);

                FormatMaster();
                FormatExpenses();
            }
            finally
            {
                gridRecon.EndUpdate();
            }
        }

        private void FormatMaster()
        {
            GridView v = gridViewMaster;
            Hide(v, "SupplierID", "BranchCode", "IsMatched", "CurrentMinCost");

            Caption(v, "ShipmentNo", "Shipment / PO #");
            Caption(v, "SupplierName", "Supplier");
            Caption(v, "DateOrder", "PO Date");
            Caption(v, "TotalQty", "Total Qty");
            Caption(v, "CurrentMaxCost", "Live Unit Cost");
            Caption(v, "LinkedExpenseCount", "Expenses");
            Caption(v, "TotalInvoiceAmount", "Invoice Amount");
            Caption(v, "TotalInventoryCost", "Inventory Cost");
            Caption(v, "TotalCostIncorporated", "Cost Incorporated / Unit");
            Caption(v, "ReconStatus", "Recon Status");

            if (v.Columns["DateOrder"] != null)
            {
                v.Columns["DateOrder"].DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                v.Columns["DateOrder"].DisplayFormat.FormatString = "MM/dd/yyyy";
            }

            Numeric(v, "TotalQty", "N3");
            Numeric(v, "CurrentMaxCost", "N4");
            Numeric(v, "LinkedExpenseCount", "N0");
            Numeric(v, "TotalInvoiceAmount", "N2");
            Numeric(v, "TotalInventoryCost", "N2");
            Numeric(v, "TotalCostIncorporated", "N4");
            Numeric(v, "Variance", "N4");

            SumFooter(v, "LinkedExpenseCount", "N0");
            SumFooter(v, "TotalInvoiceAmount", "N2");
            SumFooter(v, "TotalInventoryCost", "N2");

            v.BestFitColumns();
        }

        private void FormatExpenses()
        {
            GridView v = gridViewExpenses;
            Hide(v, "ShipmentNo");   // relation key - already shown on the master row

            Caption(v, "ReferenceNumber", "Reference No.");
            Caption(v, "InvoiceNo", "Invoice No.");
            Caption(v, "SupplierName", "Supplier");
            Caption(v, "ExpenseDate", "Date");
            Caption(v, "Remarks", "Remarks");
            Caption(v, "Amount", "Invoice Amount");
            Caption(v, "InventoryCost", "Inventory Cost");
            Caption(v, "CostDerived", "Cost Derived / Unit");
            Caption(v, "RunningTotal", "Running Total");

            if (v.Columns["ExpenseDate"] != null)
            {
                v.Columns["ExpenseDate"].DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                v.Columns["ExpenseDate"].DisplayFormat.FormatString = "MM/dd/yyyy";
            }

            Numeric(v, "Amount", "N2");
            Numeric(v, "InventoryCost", "N2");
            Numeric(v, "CostDerived", "N4");
            Numeric(v, "RunningTotal", "N4");

            SumFooter(v, "Amount", "N2");
            SumFooter(v, "InventoryCost", "N2");

            v.BestFitColumns();
        }

        private static void Hide(GridView v, params string[] fields)
        {
            foreach (string f in fields)
                if (v.Columns[f] != null) v.Columns[f].Visible = false;
        }

        private static void Caption(GridView v, string field, string caption)
        {
            if (v.Columns[field] != null) v.Columns[field].Caption = caption;
        }

        private static void Numeric(GridView v, string field, string formatString)
        {
            var col = v.Columns[field];
            if (col == null) return;
            col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            col.DisplayFormat.FormatString = formatString;
        }

        private static void SumFooter(GridView v, string field, string formatString)
        {
            var col = v.Columns[field];
            if (col == null) return;
            col.Summary.Clear();   // idempotent even if a column object is ever reused
            col.Summary.Add(DevExpress.Data.SummaryItemType.Sum, field, "{0:" + formatString + "}");
        }

        private void gridViewMaster_RowCellStyle(object sender, RowCellStyleEventArgs e)
        {
            if (e.Column.FieldName != "ReconStatus" && e.Column.FieldName != "Variance") return;

            string status = gridViewMaster.GetRowCellValue(e.RowHandle, "ReconStatus")?.ToString();
            switch (status)
            {
                case "MATCHED":
                    e.Appearance.ForeColor = Color.SeaGreen;
                    break;
                case "VARIANCE":
                    e.Appearance.ForeColor = Color.Red;
                    break;
                case "LOTS DIVERGE":
                case "NO INVENTORY":
                    e.Appearance.ForeColor = Color.DarkOrange;
                    break;
                default:
                    e.Appearance.ForeColor = Color.Gray;
                    break;
            }
            if (e.Column.FieldName == "ReconStatus")
            {
                if (_statusFont == null) _statusFont = new Font(e.Appearance.Font, FontStyle.Bold);
                e.Appearance.Font = _statusFont;
            }
        }

        // Exports the master rows; OptionsPrint.PrintDetails/ExpandAllDetails
        // (set in the designer) ask the grid to include each shipment's linked
        // expenses under it.
        private void btnExport_Click(object sender, EventArgs e)
        {
            HelperFunction.exporttoexcel(gridViewMaster, "ITEM_COSTING_RECON_" + DateTime.Now.ToString("yyyyMMdd_HHmmss"));
        }
    }
}
