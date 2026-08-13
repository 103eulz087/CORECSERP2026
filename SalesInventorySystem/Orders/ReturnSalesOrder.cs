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

namespace SalesInventorySystem.Orders
{
    public partial class ReturnSalesOrder : DevExpress.XtraEditors.XtraForm
    {
        public ReturnSalesOrder()
        {
            InitializeComponent();
        }

        static bool IsRowAlreadyReturned(GridView view, int rowHandle)
        {
            object val = view.GetRowCellValue(rowHandle, "isReturned");
            return val != null && val != DBNull.Value && Convert.ToBoolean(val);
        }

        // Rows already returned (isReturned=1 in view_BranchOrderDetails / DeliveryDetails) are
        // highlighted red and can't stay checked -- same "veto the checkbox in SelectionChanged"
        // pattern already used for CheckBoxRowSelect grids elsewhere (see
        // Orders/AddBranchOrderSTSBatchMode.cs, Orders/SearchProductBatchMode.cs).
        private void gridView1_RowStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowStyleEventArgs e)
        {
            GridView view = sender as GridView;
            if (e.RowHandle < 0)
                return;

            if (IsRowAlreadyReturned(view, e.RowHandle))
            {
                e.Appearance.BackColor = Color.Red;
                e.Appearance.BackColor2 = Color.IndianRed;
                e.Appearance.ForeColor = Color.White;
                e.HighPriority = true;
            }
        }

        private void gridView1_SelectionChanged(object sender, DevExpress.Data.SelectionChangedEventArgs e)
        {
            int rowHandle = e.ControllerRow;
            if (rowHandle >= 0 && IsRowAlreadyReturned(gridView1, rowHandle))
            {
                gridView1.UnselectRow(rowHandle);
            }

            if (gridView1.SelectedRowsCount == gridView1.DataRowCount) // "Select All" clicked
            {
                for (int i = 0; i < gridView1.DataRowCount; i++)
                {
                    if (IsRowAlreadyReturned(gridView1, i))
                    {
                        gridView1.UnselectRow(i);
                    }
                }
            }
        }

        void executeTransfer()
        {
            try
            {
                GridView view = gridControl1.FocusedView as GridView;
                view.SortInfo.Clear();

                int[] selectedRows = gridView1.GetSelectedRows();

                DataTable dt = new DataTable();
                dt.Columns.Add("SeqNo", typeof(decimal));
                dt.Columns.Add("ProductNo", typeof(string));
                dt.Columns.Add("ProductName", typeof(string));
                dt.Columns.Add("BarcodeNo", typeof(string));
                dt.Columns.Add("QtyDelivered", typeof(decimal));
                dt.Columns.Add("Cost", typeof(decimal));
                dt.Columns.Add("SellingPrice", typeof(decimal));
                dt.Columns.Add("ActualQty", typeof(decimal));
                dt.Columns.Add("Variance", typeof(double));
                dt.Columns.Add("isVat", typeof(bool));

                foreach (int rowHandle in selectedRows)
                {
                    if (rowHandle >= 0)
                    {
                        dt.Rows.Add(
                            Convert.ToDecimal(gridView1.GetRowCellValue(rowHandle, "SeqNo")),
                            gridView1.GetRowCellValue(rowHandle, "ProductNo").ToString(),
                            gridView1.GetRowCellValue(rowHandle, "ProductName").ToString(),
                            gridView1.GetRowCellValue(rowHandle, "BarcodeNo").ToString(),
                            Convert.ToDecimal(gridView1.GetRowCellValue(rowHandle, "QtyDelivered")),
                            Convert.ToDecimal(gridView1.GetRowCellValue(rowHandle, "Cost")),
                            Convert.ToDecimal(gridView1.GetRowCellValue(rowHandle, "SellingPrice")),
                            Convert.ToDecimal(gridView1.GetRowCellValue(rowHandle, "ActualQty")),
                            Convert.ToDouble(gridView1.GetRowCellValue(rowHandle, "Variance")),
                            Convert.ToBoolean(gridView1.GetRowCellValue(rowHandle, "isVat")));
                    }
                }

                if (dt.Rows.Count == 0)
                {
                    XtraMessageBox.Show("Please select at least one item to return (Checked column).");
                    return;
                }

                sp(dt);
                XtraMessageBox.Show("Successfully Returned!..");
                this.Dispose();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }

        void sp(DataTable lines)
        {
            SqlConnection con = Database.getConnection();
            con.Open();
            try
            {
                string query = "sp_ReturnSalesOrder";
                SqlCommand com = new SqlCommand(query, con);
                com.Parameters.AddWithValue("@parmbranchcode", txtbrcode.Text);
                com.Parameters.AddWithValue("@parmpono", txtpono.Text);
                com.Parameters.AddWithValue("@parmdevno", txtdevno.Text);
                com.Parameters.AddWithValue("@parmuser", Login.Fullname);
                com.Parameters.AddWithValue("@parmreturnstatus", txtstatus.Text);
                com.Parameters.AddWithValue("@parmreason", txtreason.Text);
                com.Parameters.AddWithValue("@parmmachinename", GlobalVariables.computerName);
                var tvpParam = com.Parameters.AddWithValue("@Lines", lines);
                tvpParam.SqlDbType = SqlDbType.Structured;
                tvpParam.TypeName = "dbo.tt_ReturnSalesOrderLines";
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
        private void simpleButton1_Click(object sender, EventArgs e)
        {
            if(String.IsNullOrEmpty(txtreason.Text))
            {
                XtraMessageBox.Show("Please enter a reason for the return.");
                return;
            }
            else
            {
                executeTransfer();
            }
        }

        private void ReturnSalesOrder_Load(object sender, EventArgs e)
        {

        }
    }
}