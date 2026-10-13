using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;

namespace SalesInventorySystem.AccountingDevEx
{
    /// <summary>
    /// Read-only "View PO Details" popup for a posted expense that is linked
    /// to a Purchase Order (AddExpenseDevExFrm.cs Posted Expenses tab).
    /// Header comes from view_POSUMMARYREP; line items from the same
    /// funcview_PODetails / funcview_PODetails_JFC functions VIEWPO.cs uses,
    /// gated the same way (GlobalCache.CompanyName == "JFC"), but with
    /// SqlParameter values instead of string concatenation.
    /// Layout lives in ViewLinkedPODetailsFrm.Designer.cs (edit it in the VS designer).
    /// </summary>
    public partial class ViewLinkedPODetailsFrm : XtraForm
    {
        private readonly string _shipmentNo;
        private readonly string _supplierId;
        private string _orderType = "";

        public ViewLinkedPODetailsFrm(string shipmentNo, string supplierId)
        {
            InitializeComponent();
            _shipmentNo = shipmentNo;
            _supplierId = supplierId;
            Text = "Linked PO Details — " + _shipmentNo;
            lblShipmentValue.Text = _shipmentNo;
        }

        private void ViewLinkedPODetailsFrm_Load(object sender, EventArgs e)
        {
            LoadPODetails();
        }

        private void LoadPODetails()
        {
            try
            {
                LoadHeader();
                LoadLines();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show($"Could not load PO details: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void LoadHeader()
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand(
                @"SELECT SupplierName, Status, DateOrder, TotalActualCost, OrderType
                  FROM view_POSUMMARYREP
                  WHERE ShipmentNo = @ShipmentNo", con))
            {
                cmd.Parameters.Add("@ShipmentNo", SqlDbType.VarChar, 50).Value = _shipmentNo;
                //cmd.Parameters.Add("@SupplierID", SqlDbType.VarChar, 50).Value = (object)_supplierId ?? DBNull.Value;

                con.Open();
                using (var rdr = cmd.ExecuteReader())
                {
                    if (rdr.Read())
                    {
                        lblSupplierValue.Text = rdr["SupplierName"]?.ToString() ?? "";
                        lblStatusValue.Text = rdr["Status"]?.ToString() ?? "";
                        lblOrderDateValue.Text = rdr["DateOrder"] == DBNull.Value ? "" : Convert.ToDateTime(rdr["DateOrder"]).ToString("MM/dd/yyyy");
                        lblTotalCostValue.Text = rdr["TotalActualCost"] == DBNull.Value ? "0.00" : Convert.ToDecimal(rdr["TotalActualCost"]).ToString("N2");
                        _orderType = rdr["OrderType"]?.ToString() ?? "";
                    }
                    else
                    {
                        lblStatusValue.Text = "(PO header not found)";
                    }
                }
            }
        }

        private void LoadLines()
        {
            string funcName = GlobalCache.CompanyName == "JFC" ? "funcview_PODetails_JFC" : "funcview_PODetails";

            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand($"SELECT * FROM {funcName}(@ShipmentNo, @SupplierID, @OrderType)", con))
            {
                string supplierId = Database.getSingleQuery("POSUMMARY", $"ShipmentNo='{_shipmentNo}'", "SupplierID");
                cmd.Parameters.Add("@ShipmentNo", SqlDbType.VarChar, 50).Value = _shipmentNo;
                cmd.Parameters.Add("@SupplierID", SqlDbType.VarChar, 50).Value = (object)supplierId ?? DBNull.Value;
                cmd.Parameters.Add("@OrderType", SqlDbType.VarChar, 10).Value = _orderType;

                var dt = new DataTable();
                con.Open();
                new SqlDataAdapter(cmd).Fill(dt);
                gridControlLines.DataSource = dt;
            }

            if (gridViewLines.Columns["Quantity"] != null)
            {
                gridViewLines.Columns["Quantity"].DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                gridViewLines.Columns["Quantity"].DisplayFormat.FormatString = "N3";
            }
            Classes.DevXGridViewSettings.FormatNumericColumns(gridViewLines, "Cost", "TotalCost");

            // Right-align -- FormatNumericColumns/DisplayFormat only sets how
            // the value is formatted, not its alignment; a DevExpress
            // GridColumn doesn't auto-right-align numeric-formatted cells.
            foreach (string col in new[] { "Quantity", "Cost", "TotalCost" })
            {
                if (gridViewLines.Columns[col] == null) continue;
                gridViewLines.Columns[col].AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                gridViewLines.Columns[col].AppearanceCell.Options.UseTextOptions = true;
            }

            gridViewLines.BestFitColumns();
        }
    }
}
