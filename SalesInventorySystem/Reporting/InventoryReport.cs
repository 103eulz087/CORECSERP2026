using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.Reporting
{
    // New Inventory Viewing/Report module -- shows dbo.Inventory readably (Branch/Product
    // Category names instead of raw codes) via view_InventoryReport, with Summary
    // (grouped sum/count) and Detail (per-barcode) tabs, and filters for Branch,
    // Location (IsWarehouse -- HeadOffice only), Conversion status, date range, and
    // active-stock-only.
    public partial class InventoryReport : XtraForm
    {
        public InventoryReport()
        {
            InitializeComponent();
        }

        private void InventoryReport_Load(object sender, EventArgs e)
        {
            PopulateFilters();
            // No auto-load of report data here -- for a HeadOffice user with no branch
            // selected, that would immediately query every branch's inventory (23k+ rows)
            // before they've had a chance to narrow the filters. Matches
            // Reporting/ConversionReports.cs, which also requires an explicit button click
            // before its first query.
        }

        // ================================================================
        // FILTERS
        // ================================================================
        private void PopulateFilters()
        {
            bool isHeadOffice = Login.assignedBranch == "888";

            Database.displaySearchlookupEdit(
                "SELECT BranchCode, BranchName, BranchCode + ' - ' + BranchName AS DisplayText FROM Branches ORDER BY BranchCode",
                cmbBranch, "DisplayText", "BranchCode");
            if (cmbBranch.Properties.View.Columns["DisplayText"] != null)
                cmbBranch.Properties.View.Columns["DisplayText"].Visible = false;

            if (!isHeadOffice)
            {
                // Non-HeadOffice users only ever see their own branch's inventory --
                // matches the existing role-scoping pattern in Reporting/ConversionReports.cs.
                cmbBranch.EditValue = Login.assignedBranch;
                cmbBranch.Enabled = false;
            }

            cmbLocation.SelectedIndex = 0;
            cmbConversion.SelectedIndex = 0;
            UpdateLocationFilterVisibility();
        }

        private void cmbBranch_EditValueChanged(object sender, EventArgs e)
        {
            UpdateLocationFilterVisibility();
        }

        // IsWarehouse is only meaningful for HeadOffice (888) per business rule -- hide the
        // Location filter entirely for any other branch so users aren't offered a filter
        // that can never match anything (view_InventoryReport.LocationLabel is NULL there).
        private void UpdateLocationFilterVisibility()
        {
            bool showLocation = string.IsNullOrEmpty(Convert.ToString(cmbBranch.EditValue)) || Convert.ToString(cmbBranch.EditValue) == "888";
            lblLocation.Visible = showLocation;
            cmbLocation.Visible = showLocation;
            if (!showLocation) cmbLocation.SelectedIndex = 0;
        }

        // ================================================================
        // LOAD
        // ================================================================
        private void btnLoad_Click(object sender, EventArgs e)
        {
            LoadReport();
        }

        private void LoadReport()
        {
            try
            {
                object branchParam = cmbBranch.EditValue ?? (object)DBNull.Value;

                object isWarehouseParam = DBNull.Value;
                if (cmbLocation.Visible)
                {
                    if (cmbLocation.Text == "Warehouse") isWarehouseParam = true;
                    else if (cmbLocation.Text == "Third-Party Storage") isWarehouseParam = false;
                }

                object isConversionParam = DBNull.Value;
                if (cmbConversion.Text == "Converted Only") isConversionParam = true;
                else if (cmbConversion.Text == "Original/Unconverted Only") isConversionParam = false;

                object dateFromParam = dtFrom.EditValue is DateTime df ? (object)df : DBNull.Value;
                object dateToParam = dtTo.EditValue is DateTime dtt ? (object)dtt : DBNull.Value;

                LoadSummary(branchParam, isWarehouseParam, isConversionParam, dateFromParam, dateToParam);
                LoadDetail(branchParam, isWarehouseParam, isConversionParam, dateFromParam, dateToParam);
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message, "Load Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void LoadSummary(object branch, object isWarehouse, object isConversion, object dateFrom, object dateTo)
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.sp_rpt_InventoryReport_Summary", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@Branch", SqlDbType.VarChar, 5).Value = branch;
                cmd.Parameters.Add("@IsWarehouse", SqlDbType.Bit).Value = isWarehouse;
                cmd.Parameters.Add("@IsConversion", SqlDbType.Bit).Value = isConversion;
                cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value = dateFrom;
                cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value = dateTo;
                cmd.Parameters.Add("@IsStockOnly", SqlDbType.Bit).Value = chkStockOnly.Checked;

                var dt = new DataTable();
                con.Open();
                new SqlDataAdapter(cmd).Fill(dt);

                // Must clear existing columns before rebinding -- without this, DevExpress
                // reuses the same GridColumn objects across reloads (it only creates new
                // columns for fields it doesn't already have), so ApplySummaryFormat()'s
                // col.Summary.Add(...) calls kept appending another summary item onto the
                // same column every time Load was clicked -- 5 clicks meant the footer total
                // was the correct sum counted 5 times over. Matches the existing
                // Database.display()/BindGrid() pattern elsewhere in this codebase, which
                // always calls view.Columns.Clear() before reassigning DataSource.
                viewSummary.Columns.Clear();
                gridSummary.DataSource = dt;
            }

            ApplySummaryFormat();
        }

        private void LoadDetail(object branch, object isWarehouse, object isConversion, object dateFrom, object dateTo)
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.sp_rpt_InventoryReport_Detail", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@Branch", SqlDbType.VarChar, 5).Value = branch;
                cmd.Parameters.Add("@IsWarehouse", SqlDbType.Bit).Value = isWarehouse;
                cmd.Parameters.Add("@IsConversion", SqlDbType.Bit).Value = isConversion;
                cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value = dateFrom;
                cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value = dateTo;
                cmd.Parameters.Add("@IsStockOnly", SqlDbType.Bit).Value = chkStockOnly.Checked;

                var dt = new DataTable();
                con.Open();
                new SqlDataAdapter(cmd).Fill(dt);

                // Same reason as LoadSummary above.
                viewDetail.Columns.Clear();
                gridDetail.DataSource = dt;
            }

            ApplyDetailFormat();
        }

        // ================================================================
        // FORMATTING (reapplied after every load -- DataSource reassignment
        // regenerates columns and wipes any previous per-column formatting).
        // ================================================================
        private void ApplySummaryFormat()
        {
            HideColumn(viewSummary, "Branch");
            HideColumn(viewSummary, "Product");
            SetColumnCaption(viewSummary, "BranchName", "Branch");
            SetColumnCaption(viewSummary, "Description", "Product");
            SetColumnCaption(viewSummary, "ProductCategoryDescription", "Category");
            SetColumnCaption(viewSummary, "LocationLabel", "Location");
            SetColumnCaption(viewSummary, "ConversionStatusLabel", "Status");
            SetColumnCaption(viewSummary, "LotCount", "Lots");
            SetColumnCaption(viewSummary, "TotalQuantity", "Total Qty");
            SetColumnCaption(viewSummary, "TotalAvailable", "Total Available");
            SetColumnCaption(viewSummary, "TotalValue", "Total Value");

            FormatMoneyColumn(viewSummary, "TotalValue");
            FormatNumericColumn(viewSummary, "TotalQuantity");
            FormatNumericColumn(viewSummary, "TotalAvailable");

            viewSummary.BestFitColumns();
        }

        private void ApplyDetailFormat()
        {
            HideColumn(viewDetail, "Branch");
            HideColumn(viewDetail, "Product");
            HideColumn(viewDetail, "ProductMasterDescription");
            HideColumn(viewDetail, "SequenceNumber");
            HideColumn(viewDetail, "isProcess");
            HideColumn(viewDetail, "isSource");
            HideColumn(viewDetail, "isConversion");
            HideColumn(viewDetail, "IsWarehouse");

            SetColumnCaption(viewDetail, "BranchName", "Branch");
            SetColumnCaption(viewDetail, "Description", "Product");
            SetColumnCaption(viewDetail, "ProductCategoryDescription", "Category");
            SetColumnCaption(viewDetail, "LocationLabel", "Location");
            SetColumnCaption(viewDetail, "ConversionStatusLabel", "Status");
            SetColumnCaption(viewDetail, "AvailableValue", "Available Value");

            FormatMoneyColumn(viewDetail, "Cost");
            FormatMoneyColumn(viewDetail, "AvailableValue");
            FormatNumericColumn(viewDetail, "Quantity");
            FormatNumericColumn(viewDetail, "Available");
            FormatNumericColumn(viewDetail, "QtyBigBlue");

            viewDetail.BestFitColumns();
        }

        private void HideColumn(GridView view, string field)
        {
            if (view.Columns[field] != null) view.Columns[field].Visible = false;
        }

        private void SetColumnCaption(GridView view, string field, string caption)
        {
            if (view.Columns[field] != null) view.Columns[field].Caption = caption;
        }

        private void FormatMoneyColumn(GridView view, string field)
        {
            var col = view.Columns[field];
            if (col == null) return;
            col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            col.DisplayFormat.FormatString = "N2";
            col.Summary.Add(DevExpress.Data.SummaryItemType.Sum, field, "{0:N2}");
        }

        private void FormatNumericColumn(GridView view, string field)
        {
            var col = view.Columns[field];
            if (col == null) return;
            col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            col.DisplayFormat.FormatString = "N3";
            col.Summary.Add(DevExpress.Data.SummaryItemType.Sum, field, "{0:N3}");
        }

        // ================================================================
        // EXPORT
        // ================================================================
        private void btnExport_Click(object sender, EventArgs e)
        {
            bool onSummary = tabViews.SelectedTabPage == tabSummary;
            GridView activeView = onSummary ? viewSummary : viewDetail;
            string filename = (onSummary ? "INVENTORY_SUMMARY_" : "INVENTORY_DETAIL_") + DateTime.Now.ToString("yyyyMMdd_HHmmss");
            HelperFunction.exporttoexcel(activeView, filename);
        }
    }
}
