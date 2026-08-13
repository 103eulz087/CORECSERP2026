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
using System.Threading;

namespace SalesInventorySystem.Accounting
{
    public partial class GLPostingDevEx : DevExpress.XtraEditors.XtraForm
    {
       
        public GLPostingDevEx()
        {
            InitializeComponent();
        }

        struct DataParameter
        {
            public int Process;
            public int Delay;
        }

        private DataParameter _inputParameter;

        private void simpleButton1_Click(object sender, EventArgs e)
        {
            progressBarControl1.Position = 0;

            if(String.IsNullOrEmpty(monthEdit1.Text) || String.IsNullOrEmpty(comboBoxEdit1.Text))
            {
                XtraMessageBox.Show("All Fields are Mandatory!...");
                return;
            }
            else
            {
                if (!backgroundWorker1.IsBusy)
                {
                    _inputParameter.Delay = 100;
                    _inputParameter.Process = 1200;
                    backgroundWorker1.RunWorkerAsync(_inputParameter);
                  
                    //XtraMessageBox.Show("Succesfully Posted!");
                   
                }
               
            }
        }

        private void backgroundWorker1_RunWorkerCompleted(object sender, RunWorkerCompletedEventArgs e)
        {
            XtraMessageBox.Show("Process has been Completed!");
        }

        private void backgroundWorker1_ProgressChanged(object sender, ProgressChangedEventArgs e)
        {
            progressBarControl1.EditValue = e.ProgressPercentage;
            progressBarControl1.Update();
            //progressBar1.Value = e.ProgressPercentage;
            //progressBar1.Update();
        }

        private void backgroundWorker1_DoWork(object sender, DoWorkEventArgs e)
        {
            try
            {
                ExecutePosting();

                backgroundWorker1.ReportProgress(100);
            }
            catch(Exception ex)
            {
                backgroundWorker1.CancelAsync();
                XtraMessageBox.Show(ex.Message,"Message",MessageBoxButtons.OK,MessageBoxIcon.Error);
            }
        }

        private void ExecutePosting()
        {
            DateTime selectedDate =
                DateTime.Parse($"{monthEdit1.Text} {comboBoxEdit1.Text}");

            List<string> branchCodes = new List<string>();
            using (SqlConnection con = Database.getConnection())
            using (SqlCommand cmd = new SqlCommand("SELECT BranchCode FROM Branches", con))
            {
                con.Open();
                using (SqlDataReader reader = cmd.ExecuteReader())
                {
                    while (reader.Read())
                        branchCodes.Add(reader["BranchCode"].ToString());
                }
            }

            int completed = 0;
            foreach (string branchCode in branchCodes)
            {
                using (SqlConnection con = Database.getConnection())
                using (SqlCommand cmd = new SqlCommand("sp_GLPosting", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 3600;

                    cmd.Parameters.Add("@Branch", SqlDbType.VarChar, 5)
                        .Value = branchCode;

                    cmd.Parameters.Add("@PPostDate", SqlDbType.Date)
                        .Value = selectedDate;

                    con.Open();
                    cmd.ExecuteNonQuery();
                }

                completed++;
                backgroundWorker1.ReportProgress((int)(completed * 100.0 / branchCodes.Count));
            }
        }
    }
}