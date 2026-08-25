using System;
using System.Data;
using System.Data.SqlClient;
using SalesInventorySystem.Classes;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class StockOutPerBarcodeDetails : DevExpress.XtraEditors.XtraForm
    {
        readonly string refNo;

        public StockOutPerBarcodeDetails(string refNo)
        {
            InitializeComponent();
            this.refNo = refNo;
        }

        private void StockOutPerBarcodeDetails_Load(object sender, EventArgs e)
        {
            Text = "Stock-Out Details - " + refNo;

            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand(
                "SELECT SeqNo, Barcode, ProductCode, Description, Qty, Cost, Amount " +
                "FROM dbo.StockOutBarcodeDetails WITH (NOLOCK) " +
                "WHERE RefNo = @RefNo " +
                "ORDER BY SeqNo", con))
            {
                cmd.Parameters.Add("@RefNo", SqlDbType.VarChar, 20).Value = refNo;
                Database.display(cmd, gridControlDetails, gridViewDetails);
            }
        }
    }
}
