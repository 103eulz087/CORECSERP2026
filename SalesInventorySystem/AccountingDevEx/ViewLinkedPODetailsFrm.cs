using System;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.AccountingDevEx
{
    /// <summary>
    /// Read-only "View PO Details" popup for a posted expense that is linked
    /// to a Purchase Order (AddExpenseDevExFrm.cs Posted Expenses tab).
    /// Header comes from view_POSUMMARYREP; line items from the same
    /// funcview_PODetails / funcview_PODetails_JFC functions VIEWPO.cs uses,
    /// gated the same way (GlobalCache.CompanyName == "JFC"), but with
    /// SqlParameter values instead of string concatenation.
    /// </summary>
    public class ViewLinkedPODetailsFrm : XtraForm
    {
        private readonly string _shipmentNo;
        private readonly string _supplierId;
        private string _orderType = "";

        private LabelControl lblSupplierValue;
        private LabelControl lblStatusValue;
        private LabelControl lblOrderDateValue;
        private LabelControl lblTotalCostValue;
        private GridControl gridControlLines;
        private GridView gridViewLines;

        public ViewLinkedPODetailsFrm(string shipmentNo, string supplierId)
        {
            _shipmentNo = shipmentNo;
            _supplierId = supplierId;
            BuildUI();
            Load += (s, e) => LoadPODetails();
        }

        private void BuildUI()
        {
            Text = "Linked PO Details — " + _shipmentNo;
            Size = new Size(760, 520);
            StartPosition = FormStartPosition.CenterParent;
            MaximizeBox = false;
            MinimizeBox = false;

            var grpHeader = new GroupControl { Text = "Purchase Order", Dock = DockStyle.Top, Height = 110 };

            LabelControl MakeCaption(string text, int x, int y) =>
                new LabelControl { Text = text, Location = new Point(x, y), AutoSizeMode = LabelAutoSizeMode.None, Size = new Size(90, 16) };
            LabelControl MakeValue(int x, int y) =>
                new LabelControl { Text = "", Location = new Point(x, y), AutoSizeMode = LabelAutoSizeMode.None, Size = new Size(220, 16), Appearance = { Font = new Font("Tahoma", 9F, FontStyle.Bold), Options = { UseFont = true } } };

            var lblShipmentCap = MakeCaption("Shipment No.:", 16, 20);
            var lblShipmentValue = MakeValue(150, 20);
            lblShipmentValue.Text = _shipmentNo;

            var lblSupplierCap = MakeCaption("Supplier:", 16, 46);
            lblSupplierValue = MakeValue(150, 46);

            var lblStatusCap = MakeCaption("Status:", 400, 20);
            lblStatusValue = MakeValue(470, 20);

            var lblOrderDateCap = MakeCaption("Order Date:", 400, 46);
            lblOrderDateValue = MakeValue(470, 46);

            var lblTotalCostCap = MakeCaption("Total Cost:", 16, 72);
            lblTotalCostValue = MakeValue(150, 72);

            grpHeader.Controls.AddRange(new Control[]
            {
                lblShipmentCap, lblShipmentValue, lblSupplierCap, lblSupplierValue,
                lblStatusCap, lblStatusValue, lblOrderDateCap, lblOrderDateValue,
                lblTotalCostCap, lblTotalCostValue
            });

            gridControlLines = new GridControl { Dock = DockStyle.Fill };
            gridViewLines = new GridView(gridControlLines) { OptionsBehavior = { Editable = false }, OptionsView = { ShowGroupPanel = false } };
            gridControlLines.MainView = gridViewLines;

            var pnlBottom = new PanelControl { Dock = DockStyle.Bottom, Height = 46 };
            var btnClose = new SimpleButton { Text = "Close", Size = new Size(100, 28), Location = new Point(632, 9), DialogResult = DialogResult.OK };
            pnlBottom.Controls.Add(btnClose);

            Controls.Add(gridControlLines);
            Controls.Add(pnlBottom);
            Controls.Add(grpHeader);
            AcceptButton = btnClose;
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
