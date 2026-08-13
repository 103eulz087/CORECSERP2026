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
using System.Data.SqlClient;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class InventoryQtyAdjustmentDevEx : DevExpress.XtraEditors.XtraForm
    {
        object productcode;
        string adjustmenttype = "";
        public InventoryQtyAdjustmentDevEx()
        {
            InitializeComponent();
        }

        private void InventoryQtyAdjustmentDevEx_Load(object sender, EventArgs e)
        {
            populate();
        }

        void populate()
        {
            Database.displaySearchlookupEdit("SELECT BranchCode,BranchName FROM Branches", txtbranch, "BranchCode", "BranchCode");
            // Product list is independent of the In Transit / Link to Supplier
            // design (not used by this form) - load it directly.
            Database.displaySearchlookupEdit("SELECT ProductCode,Description FROM Products WHERE BranchCode='888'", txtproduct, "Description", "Description");
        }

        private void txtbranch_EditValueChanged(object sender, EventArgs e)
        {
            //GridView view = txtbranch.Properties.View;
            //int rowHandle = view.FocusedRowHandle;
            ////string fieldName = "Name"; // or other field name
            //object branchcode = view.GetRowCellValue(rowHandle, "BranchCode");
            //txtseqno.Text = value.ToString();
            //txtweight.Text = valueAvailable.ToString();
            //txtweight.Focus();
            
        }

        // Supplier / Shipment / In Transit / Link to Supplier design is not
        // used by this form - Supplier, ShipmentNo, Cost/kg, Orig Qty,
        // Available Qty and New Qty fields have been removed from the flow.
        // Only Branch, Product, Qty Adjustment and Add/Deduct drive the
        // adjustment now; these handlers are intentionally left empty.
        private void radlinktosupplier_CheckedChanged(object sender, EventArgs e)
        {
        }

        private void txtsupplier_EditValueChanged(object sender, EventArgs e)
        {
        }

        private void txtshipmentno_EditValueChanged(object sender, EventArgs e)
        {
        }

        private void txtqtyadj_EditValueChanged(object sender, EventArgs e)
        {
        }

        private void radadd_CheckedChanged(object sender, EventArgs e)
        {
            if (radadd.Checked == true)
                adjustmenttype = "ADD";
            else
                adjustmenttype = "DEDUCT";
        }

        private void radintransit_CheckedChanged(object sender, EventArgs e)
        {
        }

        private void button1_Click(object sender, EventArgs e)
        {
            if (txtbranch.Text == "" || productcode == null || productcode.ToString() == "")
            {
                XtraMessageBox.Show("Please select a Branch and Product.");
                return;
            }
            if (!double.TryParse(txtqtyadj.Text, out double qtyToAdjust) || qtyToAdjust <= 0)
            {
                XtraMessageBox.Show("Please enter a valid Qty Adjustment greater than zero.");
                return;
            }

            if (raddeduct.Checked == true)
            {
                double totalavailable = Database.getTotalSummation2("Inventory", "Product='" + productcode + "' and isStock=1 and Available > 0 and isWarehouse=1 and Branch='" + txtbranch.Text + "'", "Available");
                if (totalavailable < qtyToAdjust)
                {
                    XtraMessageBox.Show("Cant Deduct Inventory.. Available Quantity must not less than Qty Adjustment!");
                    return;
                }
            }

            AdjustInventory();
            XtraMessageBox.Show("Successfully Adjusted!");
            this.Dispose();
        }

        private void raddeduct_CheckedChanged(object sender, EventArgs e)
        {
            if (radadd.Checked == false)
                adjustmenttype = "DEDUCT";
            else
                adjustmenttype = "ADD";
        }

        private void txtproduct_EditValueChanged(object sender, EventArgs e)
        {
            productcode = SearchLookUpClass.getSingleValue(txtproduct, "ProductCode");
        }

        // Posts the branch inventory quantity adjustment.
        //   ADD    -> sp_InvQtyAdjustment inserts a brand new Inventory row
        //             for the adjusted quantity, using the product's
        //             LandingCost as the row cost.
        //   DEDUCT -> sp_InvQtyAdjustment consumes existing Inventory rows
        //             for this Branch+Product oldest-first (FIFO) until the
        //             adjustment quantity is fully accounted for, each row
        //             carrying its own actual cost.
        // Only Branch, Product, Qty Adjustment and Adjustment Type drive
        // this now - available qty, cost and new qty are resolved inside
        // the SP itself rather than round-tripped through UI fields.
        void AdjustInventory()
        {
            SqlConnection con = Database.getConnection();
            con.Open();
            try
            {
                string query = "sp_InvQtyAdjustment";
                SqlCommand com = new SqlCommand(query, con);
                com.Parameters.AddWithValue("@parmbranchcode", txtbranch.Text);
                com.Parameters.AddWithValue("@parmprodcode", productcode.ToString());
                com.Parameters.AddWithValue("@parmdesc", txtproduct.Text);
                com.Parameters.AddWithValue("@parmqtyadj", txtqtyadj.Text);
                com.Parameters.AddWithValue("@parmadjustmenttype", adjustmenttype);
                com.Parameters.AddWithValue("@parmuser", Login.Fullname);
                com.CommandType = CommandType.StoredProcedure;
                com.CommandText = query;
                com.ExecuteNonQuery();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
            finally
            {
                con.Close();
            }
        }

    }
}