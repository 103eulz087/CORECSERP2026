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
using DevExpress.XtraGrid.Columns;
using System.Data.SqlClient;

namespace SalesInventorySystem.Reporting
{
    public partial class InventoryMonthEndReInventory : DevExpress.XtraEditors.XtraForm
    {
        public static string supplierid, suppliername, dateorder, pono, approvedby, preparedby;

        private void PurchaseOrderRepDevEx_Load(object sender, EventArgs e)
        {
            DateTime now = DateTime.Now;
            DateTime date = new DateTime(now.Year, now.Month, 1);
            dateFrom.Text = date.ToShortDateString();
            var now2 = DateTime.Now;
            var DaysInMonth = DateTime.DaysInMonth(now2.Year, now2.Month);
            var lastDay = new DateTime(now2.Year, now2.Month, DaysInMonth);
            dateTo.Text = lastDay.ToShortDateString();
        }

        private void btnforapprovalstsexcel_Click(object sender, EventArgs e)
        {
            string filename = "MONTHEND_REINVENTORY" + DateTime.Now.ToString("yyyyMMdd_HHmmss");
            HelperFunction.exporttoexcel(gridView1, filename);
        }

        public InventoryMonthEndReInventory()
        {
            InitializeComponent();
        }

        void submit()
        {
            if (dateFrom.EditValue == null || dateTo.EditValue == null)
            {
                MessageBox.Show("Please select both dates.");
                return;
            }

            // Safe cast
            DateTime from = Convert.ToDateTime(dateFrom.EditValue).Date;
            DateTime toExclusive = Convert.ToDateTime(dateTo.EditValue).Date.AddDays(1);

            // Best practice: use parameters instead of concatenating strings
            string sql = "SELECT * FROM view_MonthEndReInventoryReport " +
                         $"WHERE DateAdded >= '{from.ToString()}' AND DateAdded < '{toExclusive.ToString()}'";

            Database.display(sql, gridControl1, gridView1);
        }


        private void button1_Click(object sender, EventArgs e)
        {
            
        }

        private void gridView1_DoubleClick(object sender, EventArgs e)
        {
            //supplierid = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SupplierID").ToString();
            ////suppliername = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SupplierName").ToString();
            //dateorder = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "DateOrder").ToString();
            //pono = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "ShipmentNo").ToString();
            //preparedby = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "OrderedBy").ToString();
            //approvedby = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "ApprovedBy").ToString();

            //Reporting.PurchaseOrderRepDetailsDevEx purchdet = new PurchaseOrderRepDetailsDevEx();
            //Database.display("SELECT * FROM view_PODETAILS WHERE ShipmentNo='" + pono + "' and SupplierID='" + supplierid + "'", purchdet.gridControl1, purchdet.gridView1);
            //Classes.DevXGridViewSettings.ShowFooterTotal(purchdet.gridView1, "ActualTotalCost");
            //purchdet.ShowDialog(this);
       }

        private void simpleButton1_Click(object sender, EventArgs e)
        {
            submit();
        }
    }
}