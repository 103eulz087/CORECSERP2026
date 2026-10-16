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
    public partial class AddSupplierDevEx : DevExpress.XtraEditors.XtraForm
    {
        string buttonexec = "";
        string id = "", name = "", key = "";
        public AddSupplierDevEx()
        {
            InitializeComponent();
        }
        private void AddSupplier_Load(object sender, EventArgs e)
        {
            display();
            HelperFunction.DisableTextFields(this);
        }

        private void simpleButton1_Click(object sender, EventArgs e)
        {
            HelperFunction.EnableTextFields(this);
            int id = IDGenerator.getIDNumber("Supplier", "SupplierKey", 1);
            txtsupplierkey.Text = HelperFunction.sequencePadding1(id.ToString(), 6); //pad 6 zeros
            txtsupplierid.Text = txtsupplierkey.Text;// "000" +IDGenerator.getSupplierNumber().ToString();
            chckpayableboth.Checked = false;   // ClearAllText clears text boxes only; a new supplier starts as one-way
            simpleButton1.Enabled = false;
            addbtn.Enabled = true;
            updatebtn.Enabled = false;
            btncancel.Enabled = true;
        }

        private void btncancel_Click(object sender, EventArgs e)
        {
            HelperFunction.ClearAllText(this);
            HelperFunction.DisableTextFields(this);
            chckpayableboth.Checked = false;
            simpleButton1.Enabled = true;
            addbtn.Enabled = false;
            updatebtn.Enabled = false;
            btncancel.Enabled = false;
        }

        private void addbtn_Click(object sender, EventArgs e)
        {
            buttonexec = "ADD";
            if (HelperFunction.isTextBoxEmpty(txtsupplieraddress, txtsuppliercontactno, txtsupplierid, txtsuppliername, txtsupplierofficer, txttinno, txtlineofbusiness, txttradename, txtsupplierkey))
            {
                XtraMessageBox.Show("Please Input All Fields");
            }
            else
            {
                executor();
                XtraMessageBox.Show("Successfully Added!");
                HelperFunction.ClearAllText(this);
                HelperFunction.DisableTextFields(this);
                simpleButton1.Enabled = true;
                addbtn.Enabled = false;
                updatebtn.Enabled = false;
                btncancel.Enabled = false;
                display();
            }

        }

        private void display()
        {
            // Database.displayLocalGrid("SELECT * FROM Supplier", dataGridView1);
            Database.display("SELECT * FROM dbo.Supplier", gridControl1, gridView1);
        }

        private void executor()
        {
            bool isvat = false, islocal = false;
            if (chckisvat.Checked == true)
            {
                isvat = true;
            }
            if (chcklocalsupplier.Checked == true)
            {
                islocal = true;
            }
            SqlConnection con = Database.getConnection();
            con.Open();
            string query = "sp_addSupplier";
            SqlCommand com = new SqlCommand(query, con);
            com.Parameters.AddWithValue("@parmsuppkey", txtsupplierkey.Text);
            com.Parameters.AddWithValue("@parmid", txtsupplierid.Text);
            com.Parameters.AddWithValue("@parmsuppliername", txtsuppliername.Text);
            com.Parameters.AddWithValue("@parmaddress", txtsupplieraddress.Text);
            com.Parameters.AddWithValue("@parmcontact", txtsuppliercontactno.Text);
            com.Parameters.AddWithValue("@parmofficer", txtsupplierofficer.Text);
            com.Parameters.AddWithValue("@parmtinno", txttinno.Text);
            com.Parameters.AddWithValue("@parmtradename", txttradename.Text);
            com.Parameters.AddWithValue("@parmlineofbusiness", txtlineofbusiness.Text);
            com.Parameters.AddWithValue("@parmisvat", isvat);
            com.Parameters.AddWithValue("@parmislocal", islocal);
            com.Parameters.AddWithValue("@exectype", buttonexec);
            // 2026-10-15 (SQL [93]): shown in Supplier Payment (cash / check) AND Vouchering Telegraphic
            com.Parameters.Add("@parmisboth", SqlDbType.Bit).Value = chckpayableboth.Checked;
            com.CommandType = CommandType.StoredProcedure;
            com.CommandText = query;
            com.ExecuteNonQuery();
            con.Close();
        }

        private void dataGridView1_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
            {
                contextMenuStrip1.Show(gridControl1, e.Location);
            }
        }

        private void editDetailsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            key = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SupplierKey").ToString();
            id = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SupplierID").ToString();
            name = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SupplierName").ToString();
            HelperFunction.ClearAllText(this);
            HelperFunction.EnableTextFields(this);
            //int cord = dataGridView1.CurrentCellAddress.Y;
            txtsupplierkey.Text = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SupplierKey").ToString();//dataGridView1.Rows[cord].Cells[0].Value.ToString();
            txtsupplierid.Text = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SupplierID").ToString();//dataGridView1.Rows[cord].Cells[0].Value.ToString();
            txtsuppliername.Text = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SupplierName").ToString(); //dataGridView1.Rows[cord].Cells[1].Value.ToString();
            txtsupplieraddress.Text = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "Address").ToString(); //dataGridView1.Rows[cord].Cells[2].Value.ToString();
            txtsuppliercontactno.Text = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "ContactNo").ToString(); //dataGridView1.Rows[cord].Cells[3].Value.ToString();
            txtsupplierofficer.Text = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "Officer").ToString(); //dataGridView1.Rows[cord].Cells[4].Value.ToString();
            txttinno.Text = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "TinNo").ToString(); //dataGridView1.Rows[cord].Cells[4].Value.ToString();
            txttradename.Text = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "TradeName").ToString(); //dataGridView1.Rows[cord].Cells[4].Value.ToString();
            txtlineofbusiness.Text = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "LineOfBusiness").ToString(); //dataGridView1.Rows[cord].Cells[4].Value.ToString();

            chckisvat.Checked = Convert.ToBoolean(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "isVat").ToString());
            chcklocalsupplier.Checked = Convert.ToBoolean(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "isLocal").ToString());
            object both = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "isPayableBoth");
            chckpayableboth.Checked = both != null && both != DBNull.Value && Convert.ToBoolean(both);

            simpleButton1.Enabled = false;
            addbtn.Enabled = false;
            updatebtn.Enabled = true;
            btncancel.Enabled = true;
        }

        private void updatebtn_Click(object sender, EventArgs e)
        {
            bool isvat = false, islocal = false;
            if (chckisvat.Checked == true)
            {
                isvat = true;
            }
            if (chcklocalsupplier.Checked == true)
            {
                islocal = true;
            }
            if (HelperFunction.isTextBoxEmpty(txtsupplierofficer, txtsuppliername, txtsupplierid, txtsuppliercontactno, txtsupplieraddress, txttradename, txtlineofbusiness))
            {
                XtraMessageBox.Show("Please Supply All Fields");
            }
            else
            {
                if (id != txtsupplierid.Text || name != txtsuppliername.Text)
                {
                    Database.ExecuteQuery("UPDATE dbo.SupplierAccounts SET SupplierID='" + txtsupplierid.Text + "',SupplierName='" + txtsuppliername.Text + "' WHERE SupplierKey='" + key + "'");
                    Database.ExecuteQuery("UPDATE dbo.InventoryCost SET SupplierID='" + txtsupplierid.Text + "',SupplierName='" + txtsuppliername.Text + "'  WHERE SupplierKey='" + key + "'");
                    Database.ExecuteQuery("UPDATE dbo.POSUMMARY SET SupplierID='" + txtsupplierid.Text + "' WHERE SupplierID='" + id + "'");
                    Database.ExecuteQuery("UPDATE dbo.PODETAILS SET SupplierID='" + txtsupplierid.Text + "' WHERE SupplierID='" + id + "'");
                }
                // 2026-10-15 (SQL [93]): parameterized (was string-built) and saves isPayableBoth too
                try
                {
                using (SqlConnection con = Database.getConnection())
                using (SqlCommand com = new SqlCommand(
                    @"UPDATE dbo.Supplier
                      SET SupplierID = @SupplierID, SupplierName = @SupplierName, Address = @Address, ContactNo = @ContactNo,
                          Officer = @Officer, TinNo = @TinNo, TradeName = @TradeName, LineOfBusiness = @LineOfBusiness,
                          isVat = @isVat, isLocal = @isLocal, isPayableBoth = @isPayableBoth
                      WHERE SupplierKey = @SupplierKey", con))
                {
                    com.Parameters.Add("@SupplierID", SqlDbType.VarChar, 10).Value = txtsupplierid.Text;
                    com.Parameters.Add("@SupplierName", SqlDbType.VarChar, 50).Value = txtsuppliername.Text;
                    com.Parameters.Add("@Address", SqlDbType.VarChar, 100).Value = txtsupplieraddress.Text;
                    com.Parameters.Add("@ContactNo", SqlDbType.VarChar, 20).Value = txtsuppliercontactno.Text;
                    com.Parameters.Add("@Officer", SqlDbType.VarChar, 30).Value = txtsupplierofficer.Text;
                    com.Parameters.Add("@TinNo", SqlDbType.VarChar, 30).Value = txttinno.Text;
                    com.Parameters.Add("@TradeName", SqlDbType.VarChar, 50).Value = txttradename.Text;
                    com.Parameters.Add("@LineOfBusiness", SqlDbType.VarChar, 50).Value = txtlineofbusiness.Text;
                    com.Parameters.Add("@isVat", SqlDbType.Bit).Value = isvat;
                    com.Parameters.Add("@isLocal", SqlDbType.Bit).Value = islocal;
                    com.Parameters.Add("@isPayableBoth", SqlDbType.Bit).Value = chckpayableboth.Checked;
                    com.Parameters.Add("@SupplierKey", SqlDbType.VarChar, 15).Value = key;
                    con.Open();
                    com.ExecuteNonQuery();
                }
                }
                catch (SqlException ex)
                {
                    XtraMessageBox.Show("Update failed:\n" + ex.Message);
                    return;   // keep what was typed
                }
                XtraMessageBox.Show("Successfully Updated!");
                HelperFunction.ClearAllText(this);
                HelperFunction.DisableTextFields(this);
                display();

                simpleButton1.Enabled = true;
                addbtn.Enabled = false;
                updatebtn.Enabled = false;
                btncancel.Enabled = false;
            }
        }

        private void deleteSupplierToolStripMenuItem_Click(object sender, EventArgs e)
        {
            //int cord = dataGridView1.CurrentCellAddress.Y;
            bool ok = HelperFunction.ConfirmDialog("Are you sure?", "Delete Supplier");
            if (ok)
            {
                Database.ExecuteQuery("DELETE FROM dbo.Supplier WHERE SupplierKey='" + gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SupplierKey").ToString() + "'", "Successfully Deleted");
                Database.ExecuteQuery("DELETE FROM dbo.SupplierAccounts WHERE SupplierKey='" + gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SupplierKey").ToString() + "'", "Successfully Deleted");
                display();
            }
        }

        private void gridControl1_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == System.Windows.Forms.MouseButtons.Right)
                contextMenuStrip1.Show(gridControl1, e.Location);
            contextMenuStrip1.Items[1].Visible = false;
        }
    }
}