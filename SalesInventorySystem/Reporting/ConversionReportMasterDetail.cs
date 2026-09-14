using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.Reporting
{
    // New Conversion report -- master/detail(-detail) view of the barcode-based Conversion
    // system (ConversionBarcodeSummary/Output/Source), not the older ConversionSummary/
    // ConversionDetails/ConversionFIFO tables Reporting/ConversionReports.cs uses (that
    // system has 8 rows through 2026-08-24 and is superseded by this one's 56+ rows).
    // One master row (a conversion) expands to two SIBLING detail levels: "Inventory
    // Deducted" (ConversionBarcodeSourceDetails -- the actual source-lot deduction) and
    // "Output Produced" (ConversionBarcodeOutputDetails).
    public partial class ConversionReportMasterDetail : XtraForm
    {
        public ConversionReportMasterDetail()
        {
            InitializeComponent();
        }

        private void ConversionReportMasterDetail_Load(object sender, EventArgs e)
        {
            PopulateFilters();
            // No auto-load on open -- matches Reporting/ConversionReports.cs and
            // Reporting/InventoryReport.cs, both of which require an explicit button click
            // before their first query.
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
                // Matches the role-scoping pattern already used in ConversionReports.cs and
                // InventoryReport.cs. All conversions today are BranchCode='888' (Head
                // Office, where cutting/conversion is actually performed), so a
                // non-HeadOffice user would simply see an empty report either way -- this
                // just keeps the filter consistent with the rest of the app.
                cmbBranch.EditValue = Login.assignedBranch;
                cmbBranch.Enabled = false;
            }

            cmbStatus.SelectedIndex = 0;
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

                object statusParam = DBNull.Value;
                if (cmbStatus.Text != "All" && !string.IsNullOrEmpty(cmbStatus.Text))
                    statusParam = cmbStatus.Text;

                object dateFromParam = dtFrom.EditValue is DateTime df ? (object)df : DBNull.Value;
                object dateToParam = dtTo.EditValue is DateTime dtt ? (object)dtt : DBNull.Value;

                // One shared array is enough -- GridMasterDetail2Children clones it
                // independently per adapter via Database.CloneParams(...) internally, so
                // there's no risk of the same SqlParameter instance being added to more
                // than one SqlCommand.Parameters collection.
                var reportParams = new[]
                {
                    new SqlParameter("@Branch", SqlDbType.VarChar, 5) { Value = branchParam },
                    new SqlParameter("@Status", SqlDbType.VarChar, 20) { Value = statusParam },
                    new SqlParameter("@DateFrom", SqlDbType.Date) { Value = dateFromParam },
                    new SqlParameter("@DateTo", SqlDbType.Date) { Value = dateToParam }
                };

                Database.GridMasterDetail2Children(
                    masterQuery: "EXEC dbo.sp_rpt_ConversionReport_Master @Branch, @Status, @DateFrom, @DateTo",
                    detail1Query: "EXEC dbo.sp_rpt_ConversionReport_Source @Branch, @Status, @DateFrom, @DateTo",
                    detail2Query: "EXEC dbo.sp_rpt_ConversionReport_Output @Branch, @Status, @DateFrom, @DateTo",
                    masterTable: "Master",
                    detail1Table: "InventoryDeducted",
                    detail2Table: "OutputProduced",
                    relMasterDetail1: "Inventory Deducted",
                    relMasterDetail2: "Output Produced",
                    masterKey: "ConversionRefNo",
                    detail1FKToMaster: "ConversionRefNo",
                    detail2FKToMaster: "ConversionRefNo",
                    grid: gridConversion,
                    masterParams: reportParams,
                    detail1Params: reportParams,
                    detail2Params: reportParams,
                    detail1SumColumns: new[] { "Qty", "Cost", "Amount" },
                    detail2SumColumns: new[] { "Qty", "UnitCost", "TotalCost", "FinalCost" }
                );

                var masterView = gridConversion.MainView as GridView;
                if (masterView != null)
                {
                    SetColumnCaption(masterView, "BranchCode", null, hide: true);
                    SetColumnCaption(masterView, "BranchName", "Branch");
                    SetColumnCaption(masterView, "ConversionRefNo", "Conversion #");
                    SetColumnCaption(masterView, "ConversionType", "Type");
                    SetColumnCaption(masterView, "TotalSourceQty", "Total Source Qty");
                    SetColumnCaption(masterView, "TotalSourceCost", "Total Source Cost");
                    SetColumnCaption(masterView, "TotalDriplossQty", "Total Driploss Qty");

                    FormatNumericColumn(masterView, "TotalSourceQty", "N3");
                    FormatNumericColumn(masterView, "TotalSourceCost", "N2");
                    FormatNumericColumn(masterView, "TotalDriplossQty", "N3");

                    masterView.OptionsView.ShowFooter = true;
                    masterView.BestFitColumns();
                }

                // Quantity/Amount columns must render as numeric-formatted values, not the
                // default text rendering -- see CLAUDE.md's reporting convention. The
                // GridMasterDetail2Children/AddFooterSums_Whitelist helpers only add a footer
                // Sum summary; they never touch the column's own DisplayFormat, so the row
                // cells above the footer would otherwise show raw unformatted numbers.
                var detail1View = gridConversion.LevelTree.Nodes["Inventory Deducted"]?.LevelTemplate as GridView;
                if (detail1View != null)
                {
                    FormatNumericColumn(detail1View, "Qty", "N3");
                    FormatNumericColumn(detail1View, "Cost", "N2");
                    FormatNumericColumn(detail1View, "Amount", "N2");
                    detail1View.BestFitColumns();
                }

                var detail2View = gridConversion.LevelTree.Nodes["Output Produced"]?.LevelTemplate as GridView;
                if (detail2View != null)
                {
                    FormatNumericColumn(detail2View, "Qty", "N3");
                    FormatNumericColumn(detail2View, "UnitCost", "N2");
                    FormatNumericColumn(detail2View, "TotalCost", "N2");
                    FormatNumericColumn(detail2View, "FinalCost", "N2");
                    detail2View.BestFitColumns();
                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message, "Load Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void SetColumnCaption(GridView view, string field, string caption, bool hide = false)
        {
            var col = view.Columns[field];
            if (col == null) return;
            if (hide) col.Visible = false;
            if (caption != null) col.Caption = caption;
        }

        private void FormatNumericColumn(GridView view, string field, string formatString)
        {
            var col = view.Columns[field];
            if (col == null) return;
            col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            col.DisplayFormat.FormatString = formatString;
        }

        // ================================================================
        // EXPORT (master level only -- the detail levels are inspected on screen by
        // expanding a master row; exporting a multi-level master-detail grid to a flat
        // Excel sheet doesn't map cleanly, so this keeps the export scoped and correct
        // rather than attempting something ambiguous).
        // ================================================================
        private void btnExport_Click(object sender, EventArgs e)
        {
            var masterView = gridConversion.MainView as GridView;
            if (masterView == null) return;
            HelperFunction.exporttoexcel(masterView, "CONVERSION_REPORT_" + DateTime.Now.ToString("yyyyMMdd_HHmmss"));
        }
    }
}
