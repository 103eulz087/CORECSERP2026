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

            // 2026-10-17 (Accounting Board): a type from the list only, AR by default; dates default to every open
            // item up to today (the range filters the invoice / expense date)
            txtagingtype.Properties.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;
            if (string.IsNullOrWhiteSpace(txtagingtype.Text)) txtagingtype.Text = "AR";
            if (datefrom.EditValue == null) datefrom.EditValue = new DateTime(2000, 1, 1);
            if (dateto.EditValue == null) dateto.EditValue = DateTime.Today;
            Classes.DevXGridViewSettings.ApplyTotalsBandAppearance(gridView1);
        }

        // 2026-10-17: the figure columns sp_Aging returns. Before [109] it returned them FORMAT()-ed as text, which the
        // grid can't total; ToNumeric turns such a column into decimal so this screen works on either version.
        private static readonly string[] FigureColumns =
            { "Amount", "0 to 30", "31 to 60", "61 to 90", "91 to 120", "Over 90", "Over 120", "CustomerCreditLimit" };

        private static DataTable ToNumeric(DataTable dt)
        {
            foreach (string name in FigureColumns)
            {
                DataColumn col = dt.Columns[name];
                if (col == null || col.DataType != typeof(string)) continue;

                int ordinal = col.Ordinal;
                var num = new DataColumn(name + "__num", typeof(decimal));
                dt.Columns.Add(num);
                foreach (DataRow r in dt.Rows)
                {
                    string s = r[col] == DBNull.Value ? null : r[col].ToString().Replace(",", "").Trim();
                    r[num] = decimal.TryParse(s, System.Globalization.NumberStyles.Number,
                                              System.Globalization.CultureInfo.InvariantCulture, out decimal d)
                        ? (object)d : DBNull.Value;
                }
                dt.Columns.Remove(col);
                num.ColumnName = name;
                num.SetOrdinal(ordinal);
            }
            return dt;
        }

        private void FormatFigures()
        {
            foreach (DevExpress.XtraGrid.Columns.GridColumn c in gridView1.Columns)
            {
                bool money = Array.IndexOf(FigureColumns, c.FieldName) >= 0;
                if (!money && c.FieldName != "Age") continue;
                c.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                c.DisplayFormat.FormatString = money ? "N2" : "N0";
                c.AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                c.AppearanceCell.Options.UseTextOptions = true;
                c.AppearanceHeader.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                c.AppearanceHeader.Options.UseTextOptions = true;
            }
            var dateCol = gridView1.Columns["TransactionDate"];
            if (dateCol != null)
            {
                dateCol.DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                dateCol.DisplayFormat.FormatString = "yyyy-MM-dd";
            }
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

            ToNumeric(dt);

            gridView1.Columns.Clear();

            gridControl1.DataSource = null;
            gridControl1.DataSource = dt;

            gridView1.PopulateColumns();
            FormatFigures();
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
            if (datefrom.EditValue == null || dateto.EditValue == null || datefrom.DateTime.Date > dateto.DateTime.Date)
            {
                XtraMessageBox.Show("Pick a From date on or before the To date.", "Aging", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            try
            {
                ExecuteReport();

                gridView1.OptionsView.ShowFooter = true;
                gridView1.GroupSummary.Clear();

                // 2026-10-17: AR's last bucket is "Over 90" (it had no total); Amount totals too. AddGroupSum skips a
                // column the chosen type doesn't return.
                AddGroupSum(gridView1, "Amount");
                AddGroupSum(gridView1, "0 to 30");
                AddGroupSum(gridView1, "31 to 60");
                AddGroupSum(gridView1, "61 to 90");
                AddGroupSum(gridView1, "Over 90");
                AddGroupSum(gridView1, "91 to 120");
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