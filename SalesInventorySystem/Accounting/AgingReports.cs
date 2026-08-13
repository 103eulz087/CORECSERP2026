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
using DevExpress.XtraGrid;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.Accounting
{
    public partial class AgingReports : DevExpress.XtraEditors.XtraForm
    {
        public AgingReports()
        {
            InitializeComponent();
            gridView1.OptionsBehavior.AutoExpandAllGroups = true;
            gridView1.OptionsView.ShowGroupPanel = true;
            gridView1.OptionsView.ShowFooter = true;
            gridView1.OptionsBehavior.Editable = false;
            gridView1.OptionsView.ColumnAutoWidth = false;
        }
        private void ExecuteReport()
        {
            DataTable dt = new DataTable();

            using (SqlConnection con = Database.getConnection())
            using (SqlCommand cmd = new SqlCommand("sp_Aging", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.Add("@parmdatefrom", SqlDbType.Date).Value = datefrom.DateTime.Date;
                cmd.Parameters.Add("@parmdateto", SqlDbType.Date).Value = dateto.DateTime.Date;
                cmd.Parameters.Add("@parmtype", SqlDbType.VarChar, 12).Value = txtagingtype.Text;

                using (SqlDataAdapter da = new SqlDataAdapter(cmd))
                {
                    da.Fill(dt);
                }
            }

            gridView1.Columns.Clear();

            gridControl1.DataSource = null;
            gridControl1.DataSource = dt;

            gridView1.PopulateColumns();
            gridView1.RefreshData();
            gridControl1.Refresh();


            gridView1.BestFitColumns();
        }
        public static void AddGroupSum(GridView view, string fieldName)
        {
            if (view.Columns[fieldName] == null)
                return;

            GridGroupSummaryItem item = new GridGroupSummaryItem()
            {
                FieldName = fieldName,
                SummaryType = DevExpress.Data.SummaryItemType.Sum,
                ShowInGroupColumnFooter = view.Columns[fieldName],
                DisplayFormat = "{0:n2}"
            };

            view.GroupSummary.Add(item);

            view.Columns[fieldName].Summary.Clear();
            view.Columns[fieldName].Summary.Add(
                DevExpress.Data.SummaryItemType.Sum,
                fieldName,
                "{0:n2}"
            );
        }

        private void btnextract_Click(object sender, EventArgs e)
        {
            try
            {
                ExecuteReport();
              
                gridView1.OptionsView.ShowFooter = true;
                gridView1.GroupSummary.Clear();
                 
                AddGroupSum(gridView1, "0 to 30");
                AddGroupSum(gridView1, "31 to 60");
                AddGroupSum(gridView1, "61 to 90");

                if (gridView1.Columns["91 to 120"] != null)
                    AddGroupSum(gridView1, "91 to 120");

                if (gridView1.Columns["Over 120"] != null)
                    AddGroupSum(gridView1, "Over 120");

                // Group by Customer
                gridView1.BeginSort();
                gridView1.ClearGrouping();

                if (txtagingtype.Text == "AR")
                {
                    if (gridView1.Columns["CustomerName"] != null)
                        gridView1.Columns["CustomerName"].GroupIndex = 0;
                }
                else
                {
                    if (gridView1.Columns["SupplierName"] != null)
                        gridView1.Columns["SupplierName"].GroupIndex = 0;
                }


                gridView1.EndSort();
                // Auto Expand
                gridView1.ExpandAllGroups();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message, "Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
        }
        

        private void simpleButton2_Click(object sender, EventArgs e)
        {
            string filepath = "C:\\MyFiles\\";
            Classes.Utilities.createDirectoryFolder(filepath);
            string filename = "AGINGREPORTS" + "_" + txtagingtype.Text + '-' + datefrom.Text.Replace('/', '-') + ".xls";
            string file = filepath + filename;
            gridView1.ExportToXls(file);
            XtraMessageBox.Show("Successfully Exported.. Please Check your Drive C://MyFiles/folder");
        }
    }
}