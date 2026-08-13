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
using System.Data.SqlClient;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class ConfirmOrderUpdateSPriceDevEx : DevExpress.XtraEditors.XtraForm
    {
        public static bool isdone = false;
        public ConfirmOrderUpdateSPriceDevEx()
        {
            InitializeComponent();
        }

        private void ConfirmOrderUpdateSPriceDevEx_Load(object sender, EventArgs e)
        {
            this.ActiveControl = txtsprice;
            txtsprice.Focus();
        }

        private void simpleButton1_Click(object sender, EventArgs e)
        {
            bool success = false;
            SqlConnection con = Database.getConnection();
            con.Open();
            try
            {
                SqlCommand com = new SqlCommand("sp_UpdateDeliverySellingPrice", con);
                com.CommandType = CommandType.StoredProcedure;
                com.Parameters.AddWithValue("@parmpono", txtpono.Text);
                com.Parameters.AddWithValue("@parmseqno", Convert.ToDecimal(txtseqno.Text));
                com.Parameters.AddWithValue("@parmprodname", txtdesc.Text);
                com.Parameters.AddWithValue("@parmsellingprice", txtsprice.Value);
                com.Parameters.AddWithValue("@parmapplytoall", checkapplytoall.Checked);
                com.Parameters.AddWithValue("@parmuser", Login.Fullname);
                com.ExecuteNonQuery();
                success = true;
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
            finally
            {
                con.Close();
            }

            if (success)
            {
                XtraMessageBox.Show("Successfully Updated!");
                isdone = true;
                this.Close();
            }
        }

        private void txtsprice_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
                simpleButton1.PerformClick();
        }
    }
}