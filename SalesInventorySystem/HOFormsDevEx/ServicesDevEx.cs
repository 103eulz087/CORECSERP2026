using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Text;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Data.SqlClient;
using DevExpress.XtraEditors;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class ServicesDevEx : DevExpress.XtraEditors.XtraForm
    {
        string deptid, deptname;
        public ServicesDevEx()
        {
            InitializeComponent();
        }

        private void ServicesDevEx_Load(object sender, EventArgs e)
        {
            disablefields();
            display();
            populateGLCode();
            btnadd.Enabled = false;
            btnupdate.Enabled = false;
            btncancel.Enabled = false;
        }

        void populateGLCode()
        {
            Database.displaySearchlookupEdit("SELECT AccountCode, Description FROM ChartOfAccounts WHERE AccountType='D'", txtglcode, "AccountCode", "AccountCode");
        }

        void clear()
        {
            txtdeptid.Text = "";
            txtdeptname.Text = "";
            txtglcode.EditValue = null;
        }

        void disablefields()
        {
            txtdeptid.Enabled = false;
            txtdeptname.Enabled = false;
            txtglcode.Enabled = false;
        }
        void enablefields()
        {
            txtdeptid.Enabled = true;
            txtdeptname.Enabled = true;
            txtglcode.Enabled = true;
        }

        private void btnnew_Click(object sender, EventArgs e)
        {
            int id = IDGenerator.getIDNumber("Services", "SRVC_ID", 10000);
            txtdeptid.Text = id.ToString();
            enablefields();
            display();
            btnnew.Enabled = false;
            btnadd.Enabled = true;
            btnupdate.Enabled = false;
            btncancel.Enabled = true;
        }

        private void btnadd_Click(object sender, EventArgs e)
        {

            bool ok = Database.checkifExist("SELECT SRVC_ID FROM Services WHERE SRVC_ID='" + txtdeptid.Text.Trim() + "' AND SRVC_DESC='" + txtdeptname.Text.Trim() + "'");
            if (ok)
            {
                XtraMessageBox.Show("Already Exist in Services Table.. Please use Edit Function");
                return;
            }
            else
            {
                using (SqlConnection con = Database.getConnection())
                {
                    con.Open();
                    SqlCommand com = new SqlCommand("INSERT INTO Services (SRVC_ID, SRVC_DESC, GLCode) VALUES (@srvcid, @srvcdesc, @glcode)", con);
                    com.Parameters.AddWithValue("@srvcid", txtdeptid.Text);
                    com.Parameters.AddWithValue("@srvcdesc", txtdeptname.Text);
                    com.Parameters.AddWithValue("@glcode", (object)txtglcode.EditValue ?? DBNull.Value);
                    com.ExecuteNonQuery();
                }
                XtraMessageBox.Show("Successfully Added");
                clear();

                btnnew.Enabled = true;
                btnadd.Enabled = false;
                btnupdate.Enabled = false;
                btncancel.Enabled = false;

                disablefields();
                display();
            }
        }

        private void btnupdate_Click(object sender, EventArgs e)
        {
            using (SqlConnection con = Database.getConnection())
            {
                con.Open();
                SqlCommand com = new SqlCommand("UPDATE Services SET SRVC_ID=@srvcid, SRVC_DESC=@srvcdesc, GLCode=@glcode WHERE SRVC_ID=@oldid AND SRVC_DESC=@olddesc", con);
                com.Parameters.AddWithValue("@srvcid", txtdeptid.Text);
                com.Parameters.AddWithValue("@srvcdesc", txtdeptname.Text);
                com.Parameters.AddWithValue("@glcode", (object)txtglcode.EditValue ?? DBNull.Value);
                com.Parameters.AddWithValue("@oldid", deptid);
                com.Parameters.AddWithValue("@olddesc", deptname);
                com.ExecuteNonQuery();
            }
            XtraMessageBox.Show("Successfully Updated!");
            clear();
            disablefields();
            btnnew.Enabled = true;
            btnadd.Enabled = false;
            btnupdate.Enabled = false;
            btncancel.Enabled = false;
            display();
        }

        private void gridControl1_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStrip1.Show(gridControl1, e.Location);
        }

        private void btncancel_Click(object sender, EventArgs e)
        {
            clear();
            disablefields();

            btnnew.Enabled = true;
            btnadd.Enabled = false;
            btnupdate.Enabled = false;
            btncancel.Enabled = false;
        }

        private void deleteToolStripMenuItem_Click(object sender, EventArgs e)
        {
            bool ok = HelperFunction.ConfirmDialog("Are you sure you want to delete this item?", "Delete Department");
            if (ok)
            {
                Database.ExecuteQuery("DELETE FROM Services WHERE SRVC_ID='" + gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SRVC_ID").ToString() + "' AND SRVC_DESC='" + gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SRVC_DESC").ToString() + "'", "Successfully Deleted");
                display();
            }
            else
            {
                return;
            }
        }

        private void editItemsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            deptid = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SRVC_ID").ToString();
            deptname = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SRVC_DESC").ToString();
            txtdeptid.Text = deptid;
            txtdeptname.Text = deptname;
            object glcode = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "GLCode");
            txtglcode.EditValue = (glcode == DBNull.Value) ? null : glcode;
            enablefields();

            btnnew.Enabled = false;
            btnadd.Enabled = false;
            btnupdate.Enabled = true;
            btncancel.Enabled = true;
        }

        void display()
        {
            Database.display("SELECT * FROM Services", gridControl1, gridView1);
        }
    }
}