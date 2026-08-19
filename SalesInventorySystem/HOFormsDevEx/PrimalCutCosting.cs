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
using DevExpress.XtraGrid.Views.Grid;
using DevExpress.XtraEditors.Repository;
using System.Data.SqlClient;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class PrimalCutCosting : DevExpress.XtraEditors.XtraForm
    {
        public PrimalCutCosting()
        {
            InitializeComponent();
        }

        private void PrimalCutCosting_Load(object sender, EventArgs e)
        {
            populate();
        }

        void populate()
        {
            Database.displaySearchlookupEdit("SELECT ShipmentNo,SupplierName FROM view_POSUMMARYREP ORDER BY ShipmentNo DESC", txtshipmentno,"ShipmentNo","ShipmentNo");
        }

        private void searchLookUpEdit_EditValueChanged(object sender, EventArgs e)
        {
            bool isExists = Database.checkifExist($"SELECT 1 FROM dbo.TempCosting WHERE ShipmentNo='{txtshipmentno.Text}'");
            if (!isExists)
                XtraMessageBox.Show("This Shipment Number has not been defined for costing yet.");

            refreshGrid(isExists);
        }

        // Reloads gridView1 for the currently selected shipment, then reapplies the Cost
        // column's numeric editor -- Database.display() clears and rebinds columns on every
        // call, so any ColumnEdit assigned before a reload is wiped and must be reapplied
        // after. Also called after a successful save so already-transferred/held items are
        // reflected instead of the grid showing stale pre-save state.
        void refreshGrid(bool costingAlreadyDefined)
        {
            if (costingAlreadyDefined)
                Database.display($"SELECT ItemCode as ProductCode,Parts as Description,CostPerKg as Cost FROM dbo.TempCosting WHERE ShipmentNo='{txtshipmentno.Text}'", gridControl1, gridView1);
            else
                Database.display($"SELECT * FROM dbo.view_PrimalCutPartsForCosting", gridControl1, gridView1);

            applyCostSpinEditor();
        }

        void applyCostSpinEditor()
        {
            if (gridView1.Columns["Cost"] == null) return;

            RepositoryItemSpinEdit spinCost = new RepositoryItemSpinEdit();
            spinCost.MinValue = 0;
            spinCost.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            spinCost.DisplayFormat.FormatString = "n2";
            spinCost.EditFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            spinCost.EditFormat.FormatString = "n2";
            gridControl1.RepositoryItems.Add(spinCost);
            gridView1.Columns["Cost"].ColumnEdit = spinCost;
        }

        private void btnsave_Click(object sender, EventArgs e)
        {
            if (string.IsNullOrWhiteSpace(txtshipmentno.Text))
            {
                XtraMessageBox.Show("Please select a Shipment Number.");
                return;
            }

            if (gridView1.RowCount == 0)
            {
                XtraMessageBox.Show("No items to save.");
                return;
            }

            try
            {
                DataTable dtLines = new DataTable();
                dtLines.Columns.Add("ProductCode", typeof(string));
                dtLines.Columns.Add("Description", typeof(string));
                dtLines.Columns.Add("Cost", typeof(decimal));

                for (int i = 0; i <= gridView1.RowCount - 1; i++)
                {
                    // GetRowCellValue can be DBNull (row loaded from view_PrimalCutPartsForCosting
                    // before a cost was ever typed in) -- Convert.ToDecimal on that throws
                    // InvalidCastException, which used to happen outside any try/catch and would
                    // crash mid-loop, losing every other row's entered cost. Default to 0 instead,
                    // which correctly falls into the SP's "held, cost not set" path.
                    object rawCost = gridView1.GetRowCellValue(i, "Cost");
                    decimal cost = (rawCost == null || rawCost == DBNull.Value) ? 0m : Convert.ToDecimal(rawCost);

                    DataRow dr = dtLines.NewRow();
                    dr["ProductCode"] = gridView1.GetRowCellValue(i, "ProductCode").ToString();
                    dr["Description"] = gridView1.GetRowCellValue(i, "Description").ToString();
                    dr["Cost"] = cost;
                    dtLines.Rows.Add(dr);
                }

                using (SqlConnection con = Database.getConnection())
                using (SqlCommand com = new SqlCommand("dbo.spu_UpdatePrimalCutCosting", con))
                {
                    com.CommandType = CommandType.StoredProcedure;

                    var p = com.Parameters.Add("@Lines", SqlDbType.Structured);
                    p.TypeName = "dbo.tt_PrimalCutCostingLines";
                    p.Value = dtLines;

                    com.Parameters.Add("@ShipmentNo", SqlDbType.VarChar, 10).Value = txtshipmentno.Text.Trim();
                    com.Parameters.Add("@Branch", SqlDbType.VarChar, 5).Value = Login.assignedBranch;
                    com.Parameters.Add("@PreparedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;

                    con.Open();
                    int transferredCount = 0;
                    var heldItems = new List<string>();
                    using (SqlDataReader reader = com.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            bool transferred = Convert.ToBoolean(reader["Transferred"]);
                            if (transferred)
                                transferredCount++;
                            else
                                heldItems.Add(reader["Description"].ToString() + " (" + reader["ProductCode"].ToString() + ")");
                        }
                    }

                    string summary = transferredCount + " item(s) transferred to Commissary.";
                    if (heldItems.Count > 0)
                        summary += "\n\n" + heldItems.Count + " item(s) held in BigBlue (zero cost), not transferred:\n" + string.Join("\n", heldItems);

                    XtraMessageBox.Show(summary, "Primal Cut Costing Saved");
                }

                // Refresh so already-transferred/held rows reflect the outcome instead of the
                // grid still showing stale pre-save state (Known Bug Pattern #6).
                refreshGrid(true);
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message, "Save Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message, "Save Failed -- check entered values", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void gridView1_RowCellStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowCellStyleEventArgs e)
        {
            
        }

        private void gridView1_ShowingEditor(object sender, CancelEventArgs e)
        {
           
        }

        private void gridControl1_Click(object sender, EventArgs e)
        {

        }

        private void gridView1_RowCellStyle_1(object sender, RowCellStyleEventArgs e)
        {
            if (e.Column.FieldName == "Cost")
            {
                e.Appearance.BackColor = Color.Salmon;
                e.Appearance.BackColor2 = Color.LightSalmon;
            }
        }

        private void gridView1_ShowingEditor_1(object sender, CancelEventArgs e)
        {
            GridView view = sender as GridView;
            if (view.FocusedColumn.FieldName != "Cost")
                e.Cancel = true;
        }
    }
}