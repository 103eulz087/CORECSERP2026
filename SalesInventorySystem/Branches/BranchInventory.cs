using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Globalization;
using System.Text;
using System.Windows.Forms;
using DevExpress.Utils;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid;
using DevExpress.XtraGrid.Columns;
using DevExpress.XtraGrid.Views.Grid;
using DevExpress.XtraReports.UI;
using DevExpress.XtraSplashScreen;

namespace SalesInventorySystem
{
    // Main › Inventory (barButtonItem13). 2026-10-17 (user): rebuilt in the standard report layout (DevExpress filter
    // panel, numeric figures right-aligned with totals); same columns as before, ReferenceCode shown after Description.
    // Reads the same objects as before, parameterized: Detailed = func_view_BranchInventoryDetails(branch) (one row per
    // lot), Summary = view_BranchInventoryJFC (JFC) / view_BranchInventory (others). Those return Quantity / Available /
    // DateReceived FORMAT()-ed as text and are shared with other screens, so they are not changed; the text is turned
    // into numbers / dates here.
    public partial class BranchInventory : DevExpress.XtraEditors.XtraForm
    {
        private const string ViewDetailed = "DETAILED";
        private Font _boldFont;

        public BranchInventory()
        {
            InitializeComponent();
            Classes.DevXGridViewSettings.ApplyTotalsBandAppearance(gridView1);
            gridView1.BestFitMaxRowCount = 500;
        }

        private bool IsDetailed => Convert.ToString(rdoView.EditValue) == ViewDetailed;

        private void BranchInventory_Load(object sender, EventArgs e)
        {
            lblBranchName.Text = "Branch: " + BranchCaption(Login.assignedBranch);
        }

        // Code - Name, like the other screens
        private static string BranchCaption(string branch)
        {
            if (string.IsNullOrWhiteSpace(branch)) return "(none)";
            try
            {
                using (SqlConnection con = Database.getConnection())
                using (SqlCommand cmd = new SqlCommand("SELECT TOP (1) BranchName FROM dbo.Branches WHERE BranchCode = @branch", con))
                {
                    cmd.Parameters.Add("@branch", SqlDbType.VarChar, 10).Value = branch;
                    con.Open();
                    object name = cmd.ExecuteScalar();
                    return name == null || name == DBNull.Value ? branch : branch + " - " + name;
                }
            }
            catch (SqlException)
            {
                return branch;
            }
        }

        private DataTable Fetch(bool detailed)
        {
            string sql;
            if (detailed)
                sql = "SELECT * FROM dbo.func_view_BranchInventoryDetails(@branch)";
            else if (GlobalCache.CompanyName == "JFC")
                sql = "SELECT * FROM dbo.view_BranchInventoryJFC WHERE Branch = @branch ORDER BY Category, Product";
            else
                sql = "SELECT * FROM dbo.view_BranchInventory WHERE Branch = @branch ORDER BY Category, Product";

            var dt = new DataTable();
            using (SqlConnection con = Database.getConnection())
            using (SqlCommand cmd = new SqlCommand(sql, con))
            using (SqlDataAdapter da = new SqlDataAdapter(cmd))
            {
                cmd.CommandTimeout = 300;
                cmd.Parameters.Add("@branch", SqlDbType.VarChar, 5).Value = Login.assignedBranch ?? "";
                da.Fill(dt);
            }
            ToNumber(dt, "Quantity");
            ToNumber(dt, "Available");
            ToDate(dt, "DateReceived");
            return dt;
        }

        // A FORMAT()-ed text column ("1,234.000") becomes a decimal column at the same position.
        private static void ToNumber(DataTable dt, string name)
        {
            DataColumn col = dt.Columns[name];
            if (col == null || col.DataType != typeof(string)) return;
            Replace(dt, col, typeof(decimal), s =>
                decimal.TryParse(s.Replace(",", ""), NumberStyles.Number, CultureInfo.InvariantCulture, out decimal d) ? (object)d : DBNull.Value);
        }

        private static void ToDate(DataTable dt, string name)
        {
            DataColumn col = dt.Columns[name];
            if (col == null || col.DataType != typeof(string)) return;
            Replace(dt, col, typeof(DateTime), s =>
                DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.None, out DateTime d) ? (object)d : DBNull.Value);
        }

        private static void Replace(DataTable dt, DataColumn col, Type type, Func<string, object> parse)
        {
            int ordinal = col.Ordinal;
            string name = col.ColumnName;
            var typed = new DataColumn(name + "__typed", type);
            dt.Columns.Add(typed);
            foreach (DataRow r in dt.Rows)
            {
                string s = r[col] == DBNull.Value ? null : r[col].ToString().Trim();
                r[typed] = string.IsNullOrEmpty(s) ? DBNull.Value : parse(s);
            }
            dt.Columns.Remove(col);
            typed.ColumnName = name;
            typed.SetOrdinal(ordinal);
        }

        // Fetch (database only, no control) runs off the UI thread; binding happens back on it (Known Bug #8)
        private async System.Threading.Tasks.Task display()
        {
            bool detailed = IsDetailed;
            DataTable dt;
            try
            {
                SplashScreenManager.ShowDefaultWaitForm();
                SplashScreenManager.Default.SetWaitFormCaption("Please wait");
                SplashScreenManager.Default.SetWaitFormDescription("Loading the branch inventory...");
                dt = await System.Threading.Tasks.Task.Run(() => Fetch(detailed));
            }
            catch (Exception ex)
            {
                if (SplashScreenManager.Default != null && SplashScreenManager.Default.IsSplashFormVisible)
                    SplashScreenManager.CloseDefaultWaitForm();
                XtraMessageBox.Show("Could not load the inventory:\n" + ex.Message, "Branch Inventory", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            if (SplashScreenManager.Default != null && SplashScreenManager.Default.IsSplashFormVisible)
                SplashScreenManager.CloseDefaultWaitForm();

            gridControl1.BeginUpdate();
            try
            {
                gridView1.Columns.Clear();
                gridView1.GroupSummary.Clear();
                gridControl1.DataSource = dt;
                gridView1.PopulateColumns();
                FormatColumns(detailed);
            }
            finally
            {
                gridControl1.EndUpdate();
            }
            gridView1.BestFitColumns();
            CapWidth("Description", 360);
            gridView1.Focus();

            if (dt.Rows.Count == 0)
                XtraMessageBox.Show("No stock on hand for this branch.", "Branch Inventory", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private static readonly Dictionary<string, string> Captions = new Dictionary<string, string>
        {
            ["DateReceived"] = "Date Received", ["ReferenceCode"] = "Reference Code", ["ReOrderLevel"] = "Re-order Level",
            ["IsStock"] = "In Stock"
        };

        private void FormatColumns(bool detailed)
        {
            foreach (GridColumn c in gridView1.Columns)
                if (Captions.TryGetValue(c.FieldName, out string cap)) c.Caption = cap;

            // same columns as before; ReferenceCode right after Description
            string[] order = detailed
                ? new[] { "Branch", "DateReceived", "Product", "Description", "ReferenceCode", "Barcode", "Quantity", "Available", "IsStock", "SN" }
                : new[] { "Branch", "Category", "Product", "Description", "ReferenceCode", "Quantity", "Available", "ReOrderLevel" };
            int index = 0;
            foreach (string f in order)
            {
                GridColumn c = gridView1.Columns[f];
                if (c != null) c.VisibleIndex = index++;
            }

            FormatFigure("Quantity", "N3", true);
            FormatFigure("Available", "N3", true);
            FormatFigure("ReOrderLevel", "N3", false);

            GridColumn date = gridView1.Columns["DateReceived"];
            if (date != null)
            {
                date.DisplayFormat.FormatType = FormatType.DateTime;
                date.DisplayFormat.FormatString = "yyyy-MM-dd";
            }
            GridColumn product = gridView1.Columns["Product"];
            if (product != null)
                product.Summary.Add(DevExpress.Data.SummaryItemType.Count, "Product", "{0:N0} rows");
        }

        private void FormatFigure(string field, string format, bool withSum)
        {
            GridColumn c = gridView1.Columns[field];
            if (c == null) return;
            c.DisplayFormat.FormatType = FormatType.Numeric;
            c.DisplayFormat.FormatString = format;
            c.AppearanceCell.TextOptions.HAlignment = HorzAlignment.Far;
            c.AppearanceCell.Options.UseTextOptions = true;
            c.AppearanceHeader.TextOptions.HAlignment = HorzAlignment.Far;
            c.AppearanceHeader.Options.UseTextOptions = true;
            if (withSum)
                c.Summary.Add(DevExpress.Data.SummaryItemType.Sum, field, "{0:" + format + "}");
        }

        private void CapWidth(string field, int max)
        {
            GridColumn c = gridView1.Columns[field];
            if (c != null && c.Width > max) c.Width = max;
        }

        private void gridView1_RowCellStyle(object sender, RowCellStyleEventArgs e)
        {
            if (e.Column.FieldName == "Available" && e.RowHandle >= 0)
            {
                if (_boldFont == null) _boldFont = new Font(e.Appearance.Font, FontStyle.Bold);
                e.Appearance.BackColor = Color.LightBlue;
                e.Appearance.BackColor2 = Color.LightCyan;
                e.Appearance.ForeColor = Color.FromArgb(0, 32, 96);   // dark text: readable in the dark skins too
                e.Appearance.Font = _boldFont;
            }
        }

        // Summary: a product below its re-order level is shown in salmon (as before)
        private void gridView1_RowStyle(object sender, RowStyleEventArgs e)
        {
            GridView view = (GridView)sender;
            if (IsDetailed || e.RowHandle < 0 || e.RowHandle == view.FocusedRowHandle) return;   // focused row: the skin's colours
            if (view.Columns["Available"] == null || view.Columns["ReOrderLevel"] == null) return;
            object available = view.GetRowCellValue(e.RowHandle, "Available");
            object reorder = view.GetRowCellValue(e.RowHandle, "ReOrderLevel");
            if (available == null || available == DBNull.Value || reorder == null || reorder == DBNull.Value) return;
            if (Convert.ToDecimal(available) < Convert.ToDecimal(reorder))
            {
                e.Appearance.BackColor = Color.Salmon;
                e.Appearance.BackColor2 = Color.SeaShell;
                e.Appearance.ForeColor = Color.Black;
            }
        }

        private void deleteThisItemToolStripMenuItem_Click(object sender, EventArgs e)
        {
            //Database.ExecuteQuery("UPDATE Inventory SET isWarehouse=1,Branch='888' WHERE Barcode='" + gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "Barcode").ToString() + "' AND Branch='" + gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "Branch").ToString() + "'", "Successfully Updated");
            //display();
        }

        private void gridControl1_MouseUp(object sender, MouseEventArgs e)
        {
            //if (e.Button == MouseButtons.Right)
            //    contextMenuStrip1.Show(gridControl1, e.Location);
            if (IsDetailed && e.Button == MouseButtons.Right && gridView1.Columns["SN"] != null)
                contextMenuStrip2.Show(gridControl1, e.Location);
        }

        private void btnforapprovalsalesorderexcel_Click(object sender, EventArgs e)
        {
            string filename = "BRANCHINVENTORY_" + DateTime.Now.ToShortDateString().Replace(@"/", "-");
            HelperFunction.exporttoexcel(gridView1, filename);
        }

        private async void simpleButton1_Click(object sender, EventArgs e)
        {
            simpleButton1.Enabled = false;
            rdoView.Enabled = false;
            Cursor = Cursors.WaitCursor;
            try
            {
                await display();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message, "Branch Inventory", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                rdoView.Enabled = true;
                Cursor = Cursors.Default;
                simpleButton1.Enabled = true;
            }
        }

        // 2026-10-17: the label needs the lot's shipment, pallet and expiry, which the Detailed view doesn't return (the
        // reprint failed on them); read the lot itself by its SN (Inventory.SequenceNumber) at this branch.
        private void reprintBarcodeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            try
            {
                object sn = gridView1.GetFocusedRowCellValue("SN");
                if (sn == null || sn == DBNull.Value)
                {
                    XtraMessageBox.Show("Pick a lot first.", "Reprint Barcode", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }

                DataRow lot;
                using (SqlConnection con = Database.getConnection())
                using (SqlCommand cmd = new SqlCommand(
                    "SELECT TOP (1) ShipmentNo, DateReceived, Description, Quantity, PalletNo, Product, ExpiryDate, Barcode " +
                    "FROM dbo.Inventory WHERE SequenceNumber = @sn AND Branch = @branch", con))
                using (SqlDataAdapter da = new SqlDataAdapter(cmd))
                {
                    cmd.Parameters.Add("@sn", SqlDbType.Int).Value = Convert.ToInt32(sn);
                    cmd.Parameters.Add("@branch", SqlDbType.VarChar, 5).Value = Login.assignedBranch ?? "";
                    var t = new DataTable();
                    da.Fill(t);
                    if (t.Rows.Count == 0)
                    {
                        XtraMessageBox.Show("This lot is no longer in the branch's inventory.", "Reprint Barcode", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        return;
                    }
                    lot = t.Rows[0];
                }

                string compname = Database.getSingleQuery("CompanyProfile", "BranchCode='888'", "CompanyName");
                Barcode.BarcodePrinting bprint = new Barcode.BarcodePrinting();
                bprint.xrshipno.Text = Convert.ToString(lot["ShipmentNo"]);
                bprint.lblmanufdate.Text = lot["DateReceived"] == DBNull.Value ? "" : Convert.ToDateTime(lot["DateReceived"]).ToShortDateString();
                bprint.xrLabel1.Text = compname;
                bprint.lblprodtype.Text = Convert.ToString(lot["Description"]);
                bprint.lbltotalkilos.Text = lot["Quantity"] == DBNull.Value ? "" : Convert.ToDecimal(lot["Quantity"]).ToString("N3");
                bprint.xrpalletno.Text = Convert.ToString(lot["PalletNo"]);
                bprint.xrsku.Text = Convert.ToString(lot["Product"]);
                bprint.lblxpirydate.Text = lot["ExpiryDate"] == DBNull.Value ? "" : Convert.ToDateTime(lot["ExpiryDate"]).ToShortDateString();
                bprint.xrBarCode2.Text = Convert.ToString(lot["Barcode"]);

                ReportPrintTool report = new ReportPrintTool(bprint);
                //report.ShowRibbonPreviewDialog();
                //report.PrintDialog();
                report.Print();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }
    }
}
