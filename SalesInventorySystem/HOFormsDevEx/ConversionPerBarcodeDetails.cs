using System;
using System.Data;
using System.Data.SqlClient;
using SalesInventorySystem.Classes;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class ConversionPerBarcodeDetails : DevExpress.XtraEditors.XtraForm
    {
        readonly string conversionRefNo;

        public ConversionPerBarcodeDetails(string conversionRefNo)
        {
            InitializeComponent();
            this.conversionRefNo = conversionRefNo;
        }

        private void ConversionPerBarcodeDetails_Load(object sender, EventArgs e)
        {
            Text = "Conversion Details - " + conversionRefNo;

            // ReferenceCode = the source lot's own Inventory.ReferenceCode (the function doesn't return it)
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand(
                "SELECT d.SeqNo, d.Barcode, i.ReferenceCode, d.ProductCode, d.Description, d.Qty, d.Cost, d.Amount " +
                "FROM dbo.funcview_ConversionBarcodeSourceDetails(@RefNo) AS d " +
                "LEFT JOIN dbo.Inventory AS i ON i.SequenceNumber = d.InventorySeqNo " +
                "ORDER BY d.SeqNo", con))
            {
                cmd.Parameters.Add("@RefNo", SqlDbType.VarChar, 20).Value = conversionRefNo;
                Database.display(cmd, gridControlSourceDetails, gridViewSourceDetails);
            }
            if (gridViewSourceDetails.Columns["ReferenceCode"] != null)
                gridViewSourceDetails.Columns["ReferenceCode"].Caption = "Reference Code";
            FormatFigure(gridViewSourceDetails, "Qty", "N3");
            FormatFigure(gridViewSourceDetails, "Cost", "N2");
            FormatFigure(gridViewSourceDetails, "Amount", "N2");
            gridViewSourceDetails.BestFitColumns();

            // the output's cost = the Final Cost set at Finalize (what the lot and the GL ticket carry); before
            // Finalize FinalCost is seeded with the system UnitCost, and very old rows may have none (NULL)
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand(
                "SELECT SeqNo, ProductCode, Description, Qty, IsDriploss, " +
                "ISNULL(FinalCost, UnitCost) AS UnitCost, " +
                "CAST(ROUND(Qty * ISNULL(FinalCost, UnitCost), 2) AS DECIMAL(18,2)) AS TotalCost, NewBarcode " +
                "FROM dbo.funcview_ConversionBarcodeOutputDetails(@RefNo) " +
                "ORDER BY SeqNo", con))
            {
                cmd.Parameters.Add("@RefNo", SqlDbType.VarChar, 20).Value = conversionRefNo;
                Database.display(cmd, gridControlOutputDetails, gridViewOutputDetails);
            }
            if (gridViewOutputDetails.Columns["UnitCost"] != null) gridViewOutputDetails.Columns["UnitCost"].Caption = "Unit Cost";
            if (gridViewOutputDetails.Columns["TotalCost"] != null) gridViewOutputDetails.Columns["TotalCost"].Caption = "Total Cost";
            FormatFigure(gridViewOutputDetails, "Qty", "N3");
            FormatFigure(gridViewOutputDetails, "UnitCost", "N2");
            FormatFigure(gridViewOutputDetails, "TotalCost", "N2");
            gridViewOutputDetails.BestFitColumns();
        }

        // a figure column: numeric format, right-aligned cell and header (CLAUDE.md numeric rule)
        static void FormatFigure(DevExpress.XtraGrid.Views.Grid.GridView view, string field, string format)
        {
            var c = view.Columns[field];
            if (c == null) return;
            c.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            c.DisplayFormat.FormatString = format;
            c.AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
            c.AppearanceCell.Options.UseTextOptions = true;
            c.AppearanceHeader.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
            c.AppearanceHeader.Options.UseTextOptions = true;
        }
    }
}
