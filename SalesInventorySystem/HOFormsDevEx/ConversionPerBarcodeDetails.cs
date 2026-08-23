using System;
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

            Database.display(
                "SELECT SeqNo, Barcode, ProductCode, Description, Qty, Cost, Amount " +
                "FROM dbo.funcview_ConversionBarcodeSourceDetails('" + conversionRefNo.Replace("'", "''") + "') " +
                "ORDER BY SeqNo",
                gridControlSourceDetails, gridViewSourceDetails);
            gridViewSourceDetails.BestFitColumns();

            Database.display(
                "SELECT SeqNo, ProductCode, Description, Qty, IsDriploss, UnitCost, TotalCost, NewBarcode " +
                "FROM dbo.funcview_ConversionBarcodeOutputDetails('" + conversionRefNo.Replace("'", "''") + "') " +
                "ORDER BY SeqNo",
                gridControlOutputDetails, gridViewOutputDetails);
            gridViewOutputDetails.BestFitColumns();
        }
    }
}
