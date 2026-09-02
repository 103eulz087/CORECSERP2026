using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using SalesInventorySystem.Classes;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class ConversionPerBarcodeFinalize : DevExpress.XtraEditors.XtraForm
    {
        readonly string conversionRefNo;

        public ConversionPerBarcodeFinalize(string conversionRefNo)
        {
            InitializeComponent();
            this.conversionRefNo = conversionRefNo;
        }

        private void ConversionPerBarcodeFinalize_Load(object sender, EventArgs e)
        {
            Text = "Finalize Conversion - " + conversionRefNo;

            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand(
                "SELECT SeqNo, Barcode, ProductCode, Description, Qty, Cost, Amount " +
                "FROM dbo.funcview_ConversionBarcodeSourceDetails(@RefNo) ORDER BY SeqNo", con))
            {
                cmd.Parameters.Add("@RefNo", SqlDbType.VarChar, 20).Value = conversionRefNo;
                Database.display(cmd, gridControlSourceDetails, gridViewSourceDetails);
            }
            gridViewSourceDetails.BestFitColumns();

            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand(
                "SELECT SeqNo, ProductCode, Description, Qty, IsDriploss, UnitCost, FinalCost, NewBarcode " +
                "FROM dbo.funcview_ConversionBarcodeOutputDetails(@RefNo) ORDER BY SeqNo", con))
            {
                cmd.Parameters.Add("@RefNo", SqlDbType.VarChar, 20).Value = conversionRefNo;
                Database.display(cmd, gridControlOutputDetails, gridViewOutputDetails);
            }
            gridViewOutputDetails.BestFitColumns();

            // Only FinalCost is editable, and only for non-driploss lines --
            // driploss stays at 0, it is never eligible for override (same
            // rule spu_FinalizeConversionBarcode enforces server-side).
            var dt = gridControlOutputDetails.DataSource as DataTable;
            if (dt != null && dt.Columns.Contains("FinalCost"))
                dt.Columns["FinalCost"].ReadOnly = false;

            gridViewOutputDetails.OptionsBehavior.Editable = true;
            gridViewOutputDetails.OptionsBehavior.ReadOnly = false;
            gridViewOutputDetails.OptionsBehavior.EditorShowMode = DevExpress.Utils.EditorShowMode.Click;

            // Same numeric-entry convention as the rest of this form's own
            // input fields (txtFifoQty/txtOutputQty/txtCharge all use
            // SpinEdit) rather than a bare unformatted text cell.
            var finalCostEditor = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit
            {
                DisplayFormat = { FormatType = DevExpress.Utils.FormatType.Numeric, FormatString = "n2" },
                EditFormat = { FormatType = DevExpress.Utils.FormatType.Numeric, FormatString = "n6" },
                MinValue = 0,
                MaxValue = decimal.MaxValue
            };
            gridControlOutputDetails.RepositoryItems.Add(finalCostEditor);

            foreach (DevExpress.XtraGrid.Columns.GridColumn col in gridViewOutputDetails.Columns)
            {
                bool isFinalCost = col.FieldName == "FinalCost";
                col.OptionsColumn.AllowEdit = isFinalCost;
                col.OptionsColumn.ReadOnly = !isFinalCost;
                if (isFinalCost)
                    col.ColumnEdit = finalCostEditor;
            }

            gridViewOutputDetails.RowCellStyle += GridViewOutputDetails_RowCellStyle;
        }

        // Grays out the FinalCost cell on driploss rows so it's visually
        // obvious those aren't editable, matching the disabled-row
        // convention used elsewhere (AddBranchOrderSTSBatchMode) rather than
        // just silently rejecting the edit on save.
        private void GridViewOutputDetails_RowCellStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowCellStyleEventArgs e)
        {
            if (e.RowHandle < 0) return;
            var view = sender as DevExpress.XtraGrid.Views.Grid.GridView;
            object isDriploss = view.GetRowCellValue(e.RowHandle, "IsDriploss");
            if (isDriploss != null && isDriploss != DBNull.Value && Convert.ToBoolean(isDriploss))
            {
                e.Appearance.BackColor = System.Drawing.Color.LightGray;
            }
        }

        private void btnFinalize_Click(object sender, EventArgs e)
        {
            gridViewOutputDetails.CloseEditor();
            gridViewOutputDetails.UpdateCurrentRow();

            var dt = gridControlOutputDetails.DataSource as DataTable;
            if (dt == null) return;

            DataTable tvp = new DataTable();
            tvp.Columns.Add("SeqNo", typeof(int));
            tvp.Columns.Add("FinalCost", typeof(decimal));

            foreach (DataRow row in dt.Rows)
            {
                bool isDriploss = row["IsDriploss"] != DBNull.Value && Convert.ToBoolean(row["IsDriploss"]);
                if (isDriploss) continue;

                decimal finalCost = row["FinalCost"] == DBNull.Value ? 0m : Convert.ToDecimal(row["FinalCost"]);
                if (finalCost < 0)
                {
                    BigAlert.Show("INVALID FINAL COST", "Final Cost cannot be negative (SeqNo " + row["SeqNo"] + ").", MessageBoxIcon.Warning);
                    return;
                }
                tvp.Rows.Add(Convert.ToInt32(row["SeqNo"]), finalCost);
            }

            if (XtraMessageBox.Show(
                    "Finalize this Conversion? This applies the Final Cost to inventory and posts the GL ticket entries. This cannot be undone afterward.",
                    "Finalize Conversion", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;

            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.spu_FinalizeConversionBarcode", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.CommandTimeout = 180;
                cmd.Parameters.Add("@ConversionRefNo", SqlDbType.VarChar, 20).Value = conversionRefNo;
                cmd.Parameters.Add("@FinalizedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;

                var pFinalCosts = cmd.Parameters.AddWithValue("@FinalCosts", tvp);
                pFinalCosts.SqlDbType = SqlDbType.Structured;
                pFinalCosts.TypeName = "dbo.tt_ConversionFinalCostLines";

                try
                {
                    con.Open();
                    cmd.ExecuteNonQuery();
                    BigAlert.Show("FINALIZED", "Conversion finalized and posted successfully.", MessageBoxIcon.Information);
                    DialogResult = DialogResult.OK;
                    Close();
                }
                catch (SqlException ex)
                {
                    BigAlert.Show("FINALIZE FAILED", ex.Message, MessageBoxIcon.Error);
                }
            }
        }

        private void btnClose_Click(object sender, EventArgs e)
        {
            Close();
        }
    }
}
