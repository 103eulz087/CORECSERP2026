using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.Reporting
{
    // New Item Costing Report -- a per-lot "stock card" master-detail report, requested with
    // a reference spreadsheet example showing: one lot per ShipmentNo+ReferenceCode, a
    // Beginning Balance, then chronological Received/Sold/Adjusted movement rows with a
    // running qty/value balance. Built master-detail rather than mirroring the flat/grouped
    // spreadsheet layout directly (user's explicit choice) -- scales better once there are
    // thousands of lots, and reuses the same Database.GridMasterDetail helper already proven
    // by other reports this session.
    //
    // IMPORTANT, communicated to the user: the detail ledger's running balance is NOT a
    // complete reconciliation of every way Inventory.Available can change -- it models
    // Received/Sold/Adjusted(qty)/Converted(as conversion source material), which is
    // everything with clear, well-understood schema support, but verified live that a real
    // lot still has a residual gap against the live Available snapshot (likely branch
    // transfers, POS stock-outs, or another write-path not covered here). The MASTER row's
    // CurrentAvailable/RemainingValue columns are pulled straight from live Inventory and are
    // always correct regardless of any gap in the detail ledger.
    public partial class ItemCostingReport : XtraForm
    {
        public ItemCostingReport()
        {
            InitializeComponent();
        }

        private void ItemCostingReport_Load(object sender, EventArgs e)
        {
            PopulateFilters();
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
                cmbBranch.EditValue = Login.assignedBranch;
                cmbBranch.Enabled = false;
            }
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
                object dateFromParam = dtFrom.EditValue is DateTime df ? (object)df : DBNull.Value;
                object dateToParam = dtTo.EditValue is DateTime dtt ? (object)dtt : DBNull.Value;
                object shipmentNoParam = string.IsNullOrWhiteSpace(txtShipmentNo.Text) ? (object)DBNull.Value : txtShipmentNo.Text.Trim();
                object referenceCodeParam = string.IsNullOrWhiteSpace(txtReferenceCode.Text) ? (object)DBNull.Value : txtReferenceCode.Text.Trim();

                // Database.GridMasterDetail does NOT clone parameters internally -- passing the
                // same SqlParameter instances to both masterParams and detailParams throws
                // "SqlParameter is already contained by another SqlParameterCollection" on the
                // second adapter's AddRange, silently swallowed by GridMasterDetail's own catch
                // (leaves the grid empty). Build one array and pass a cloned copy to detailParams.
                var reportParams = new[]
                {
                    new SqlParameter("@Branch", SqlDbType.VarChar, 5) { Value = branchParam },
                    new SqlParameter("@DateFrom", SqlDbType.Date) { Value = dateFromParam },
                    new SqlParameter("@DateTo", SqlDbType.Date) { Value = dateToParam },
                    new SqlParameter("@ShipmentNo", SqlDbType.VarChar, 10) { Value = shipmentNoParam },
                    new SqlParameter("@ReferenceCode", SqlDbType.VarChar, 100) { Value = referenceCodeParam }
                };

                Database.GridMasterDetail(
                    masterQuery: "EXEC dbo.sp_rpt_ItemCostingReport_Master @Branch, @DateFrom, @DateTo, @ShipmentNo, @ReferenceCode",
                    detailQuery: "EXEC dbo.sp_rpt_ItemCostingReport_Detail @Branch, @DateFrom, @DateTo, @ShipmentNo, @ReferenceCode",
                    masterTable: "Master",
                    detailTable: "Ledger",
                    masterKey: "LotKey",
                    detailKey: "LotKey",
                    relationName: "Movement Ledger",
                    grid: gridItemCosting,
                    masterParams: reportParams,
                    detailParams: Database.CloneParams(reportParams)
                );

                var masterView = gridItemCosting.MainView as GridView;
                if (masterView != null)
                {
                    HideColumn(masterView, "LotKey");
                    HideColumn(masterView, "Branch");
                    HideColumn(masterView, "Product");
                    // Category is shown as-is -- its default auto-generated caption
                    // ("Category") already matches what we'd want to rename it to.
                    SetCaption(masterView, "BranchName", "Branch");
                    SetCaption(masterView, "ShipmentNo", "Shipment No");
                    SetCaption(masterView, "ReferenceCode", "Reference Code");
                    SetCaption(masterView, "Description", "Product");
                    SetCaption(masterView, "DateReceived", "Date Received");
                    SetCaption(masterView, "BeginningQty", "Beginning Qty");
                    SetCaption(masterView, "UnitCost", "Unit Cost");
                    SetCaption(masterView, "CurrentAvailable", "Current Available");
                    SetCaption(masterView, "TotalSoldQty", "Total Sold Qty");
                    SetCaption(masterView, "TotalCostOfSales", "Cost of Sales");
                    SetCaption(masterView, "TotalSalesRevenue", "Sales Revenue");
                    SetCaption(masterView, "TotalAdjustedQty", "Adjusted Qty");
                    SetCaption(masterView, "TotalAdjustedAmount", "Adjusted Amount");
                    SetCaption(masterView, "TotalConvertedQty", "Converted Qty");
                    SetCaption(masterView, "TotalConvertedAmount", "Converted Amount");
                    SetCaption(masterView, "RemainingValue", "Remaining Value");

                    // Quantity/Amount columns must render as numeric-formatted values, not the
                    // default text rendering -- see CLAUDE.md's reporting convention.
                    FormatNumericColumn(masterView, "BeginningQty", "N3");
                    FormatNumericColumn(masterView, "UnitCost", "N2");
                    FormatNumericColumn(masterView, "CurrentAvailable", "N3");
                    FormatNumericColumn(masterView, "TotalSoldQty", "N3");
                    FormatNumericColumn(masterView, "TotalCostOfSales", "N2");
                    FormatNumericColumn(masterView, "TotalSalesRevenue", "N2");
                    FormatNumericColumn(masterView, "TotalAdjustedQty", "N3");
                    FormatNumericColumn(masterView, "TotalAdjustedAmount", "N2");
                    FormatNumericColumn(masterView, "TotalConvertedQty", "N3");
                    FormatNumericColumn(masterView, "TotalConvertedAmount", "N2");
                    FormatNumericColumn(masterView, "RemainingValue", "N2");

                    masterView.BestFitColumns();
                }

                // Database.GridMasterDetail's footer-sum whitelist is hardcoded to
                // ("QtyDelivered","ActualQty","Variance") for a different caller's schema --
                // none of those exist here, so it silently adds no footer sums at all. Add
                // them ourselves for this ledger's actual numeric movement columns.
                var detailView = gridItemCosting.LevelTree.Nodes["Movement Ledger"]?.LevelTemplate as GridView;
                if (detailView != null)
                {
                    SetCaption(detailView, "MovementDate", "Date");
                    SetCaption(detailView, "MovementType", "Type");
                    AddSumFooter(detailView, "QtyIn", "N3");
                    AddSumFooter(detailView, "QtyOut", "N3");
                    AddSumFooter(detailView, "AmountIn", "N2");
                    AddSumFooter(detailView, "AmountOut", "N2");
                    AddSumFooter(detailView, "SalesAmount", "N2");
                    detailView.OptionsView.ShowFooter = true;
                    detailView.BestFitColumns();
                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message, "Load Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void HideColumn(GridView view, string field)
        {
            if (view.Columns[field] != null) view.Columns[field].Visible = false;
        }

        private void SetCaption(GridView view, string field, string caption)
        {
            if (view.Columns[field] != null) view.Columns[field].Caption = caption;
        }

        private void FormatNumericColumn(GridView view, string field, string formatString)
        {
            var col = view.Columns[field];
            if (col == null) return;
            col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            col.DisplayFormat.FormatString = formatString;
        }

        private void AddSumFooter(GridView view, string field, string formatString = "N2")
        {
            var col = view.Columns[field];
            if (col == null) return;
            FormatNumericColumn(view, field, formatString);
            col.Summary.Add(DevExpress.Data.SummaryItemType.Sum, field, "{0:" + formatString + "}");
        }

        // ================================================================
        // EXPORT (master level only -- same reasoning as ConversionReportMasterDetail.cs:
        // a multi-level master-detail grid doesn't map cleanly to a flat Excel sheet).
        // ================================================================
        private void btnExport_Click(object sender, EventArgs e)
        {
            var masterView = gridItemCosting.MainView as GridView;
            if (masterView == null) return;
            HelperFunction.exporttoexcel(masterView, "ITEM_COSTING_REPORT_" + DateTime.Now.ToString("yyyyMMdd_HHmmss"));
        }
    }
}
