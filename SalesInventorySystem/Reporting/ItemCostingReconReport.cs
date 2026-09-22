using System;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Windows.Forms;
using DevExpress.XtraEditors;

namespace SalesInventorySystem.Reporting
{
    // Item Costing Recon -- shows, for one PO ShipmentNo, exactly how
    // spu_PostExpenseV2 built up Inventory.Cost one linked SINGLE-mode
    // expense at a time (Amount / shipment total ordered Quantity, added
    // cumulatively), so a user can see which expenses contributed how much
    // instead of only seeing the final Inventory.Cost with no paper trail.
    //
    // Only PostingMode='SINGLE' expenses ever incorporate PO cost this way
    // -- verified against this DB that spu_PostExpenseV2 (and its edit
    // wrapper sp_EditSingleExpense) are the only procs referencing
    // isLinkedToPO; there is no BATCH-mode equivalent today.
    //
    // Header shows a Variance (current live Inventory.Cost vs. the sum of
    // this report's own derived contributions) -- should normally be 0;
    // a nonzero value flags a manual cost override, a since-reversed/edited
    // linked expense, or some other write path this report doesn't model.
    public partial class ItemCostingReconReport : XtraForm
    {
        public ItemCostingReconReport()
        {
            InitializeComponent();
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
        }

        private void btnLoad_Click(object sender, EventArgs e)
        {
            LoadReport();
        }

        private void LoadReport()
        {
            string shipmentNo = cboShipmentNo.EditValue?.ToString();
            if (string.IsNullOrWhiteSpace(shipmentNo))
            {
                XtraMessageBox.Show("Select a Shipment No. first.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            try
            {
                if (LoadHeader(shipmentNo))
                    LoadDetail(shipmentNo);
                else
                    gridDetail.DataSource = null;
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message, "Load Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private static decimal ReadDecimal(SqlDataReader rdr, string column) =>
            rdr[column] == DBNull.Value ? 0m : Convert.ToDecimal(rdr[column]);

        private static int ReadInt(SqlDataReader rdr, string column) =>
            rdr[column] == DBNull.Value ? 0 : Convert.ToInt32(rdr[column]);

        // Returns true when a PO header row was found (and populated); false
        // when the Shipment No. doesn't resolve to a PO -- LoadReport uses
        // this to skip the detail query entirely rather than firing it
        // against a shipment already confirmed not to exist.
        private bool LoadHeader(string shipmentNo)
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("sp_rpt_ItemCostingRecon_Header", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@ShipmentNo", SqlDbType.VarChar, 10).Value = shipmentNo;

                con.Open();
                using (var rdr = cmd.ExecuteReader())
                {
                    if (!rdr.Read())
                    {
                        ClearHeader();
                        XtraMessageBox.Show("No purchase order found for this Shipment No.", "Not Found", MessageBoxButtons.OK, MessageBoxIcon.Information);
                        return false;
                    }

                    lblSupplierValue.Text = rdr["SupplierName"]?.ToString() ?? "";
                    lblStatusValue.Text = rdr["Status"]?.ToString() ?? "";
                    lblOrderDateValue.Text = rdr["DateOrder"] == DBNull.Value ? "" : Convert.ToDateTime(rdr["DateOrder"]).ToString("MM/dd/yyyy");
                    lblTotalQtyValue.Text = ReadDecimal(rdr, "TotalQty").ToString("N3");

                    decimal minCost = ReadDecimal(rdr, "CurrentMinCost");
                    decimal maxCost = ReadDecimal(rdr, "CurrentMaxCost");
                    lblCurrentCostValue.Text = minCost == maxCost
                        ? minCost.ToString("N4")
                        : $"{minCost:N4} – {maxCost:N4} (lots diverge)";

                    int expenseCount = ReadInt(rdr, "LinkedExpenseCount");
                    decimal totalIncorporated = ReadDecimal(rdr, "TotalCostIncorporated");
                    lblTotalIncorporatedValue.Text = $"{totalIncorporated:N4}  ({expenseCount} expense(s))";

                    decimal variance = ReadDecimal(rdr, "Variance");
                    bool isMatched = rdr["IsMatched"] != DBNull.Value && Convert.ToBoolean(rdr["IsMatched"]);
                    lblVarianceValue.Text = isMatched ? $"{variance:N4} (matches)" : variance.ToString("N4") + " — DOES NOT MATCH";
                    lblVarianceValue.ForeColor = isMatched ? Color.SeaGreen : Color.Red;
                    return true;
                }
            }
        }

        private void ClearHeader()
        {
            lblSupplierValue.Text = lblStatusValue.Text = lblOrderDateValue.Text =
                lblTotalQtyValue.Text = lblCurrentCostValue.Text =
                lblTotalIncorporatedValue.Text = lblVarianceValue.Text = "";
        }

        private void LoadDetail(string shipmentNo)
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("sp_rpt_ItemCostingRecon_Detail", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@ShipmentNo", SqlDbType.VarChar, 10).Value = shipmentNo;

                var dt = new DataTable();
                con.Open();
                using (var da = new SqlDataAdapter(cmd))
                    da.Fill(dt);
                gridDetail.DataSource = dt;
            }

            SetCaption("ReferenceNumber", "Reference No.");
            SetCaption("InvoiceNo", "Invoice No.");
            SetCaption("SupplierName", "Supplier");
            SetCaption("ExpenseDate", "Date");
            SetCaption("Remarks", "Remarks");
            SetCaption("CostDerived", "Cost Derived");
            SetCaption("RunningTotal", "Running Total");

            FormatNumericColumn("Amount", "N2");
            FormatNumericColumn("CostDerived", "N4");
            FormatNumericColumn("RunningTotal", "N4");
            AddSumFooter("Amount", "N2");

            gridViewDetail.BestFitColumns();
        }

        private void SetCaption(string field, string caption)
        {
            if (gridViewDetail.Columns[field] != null) gridViewDetail.Columns[field].Caption = caption;
        }

        private void FormatNumericColumn(string field, string formatString)
        {
            var col = gridViewDetail.Columns[field];
            if (col == null) return;
            col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            col.DisplayFormat.FormatString = formatString;
        }

        private void AddSumFooter(string field, string formatString)
        {
            var col = gridViewDetail.Columns[field];
            if (col == null) return;
            col.Summary.Add(DevExpress.Data.SummaryItemType.Sum, field, "{0:" + formatString + "}");
        }

        private void btnExport_Click(object sender, EventArgs e)
        {
            HelperFunction.exporttoexcel(gridViewDetail, "ITEM_COSTING_RECON_" + DateTime.Now.ToString("yyyyMMdd_HHmmss"));
        }
    }
}
