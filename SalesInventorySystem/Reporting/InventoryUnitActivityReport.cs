using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;

namespace SalesInventorySystem.Reporting
{
    // New Inventory Unit Activity report, built against the existing dbo.spr_InventoryUnitActivity
    // SP (not modified here -- treated as a given dependency per the task). The older
    // Reporting/InventoryUnitActivity.cs form already references this same SP but calls it with
    // the wrong parameter names (@parmdatefrom/@parmdateto instead of the SP's actual
    // @datefrom/@dateto), which would throw every time it ran -- that's why its ribbon button
    // (btnInventoryUnitActivity) is set to Visibility.Never. Left untouched/dead per this task's
    // "create also another" framing; this is a fresh, correctly-wired replacement.
    //
    // The SP's @datefrom/@dateto ARE kept as user-facing filters here: BeginningQty,
    // UnitPurchased, Adjustment, and Cost are all filtered by that range inside the SP, so
    // omitting them would silently produce wrong figures for whatever period the user actually
    // wants. Note for whoever next touches the SP itself: UnitSold and Sales have their own date
    // filters commented out in the SP, so those two columns are always all-time regardless of
    // the picked range -- a pre-existing inconsistency in the SP, not something changed here.
    public partial class InventoryUnitActivityReport : XtraForm
    {
        public InventoryUnitActivityReport()
        {
            InitializeComponent();
        }

        private void InventoryUnitActivityReport_Load(object sender, EventArgs e)
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
                // Matches the role-scoping pattern used in every other report built this
                // session (ConversionReports.cs, InventoryReport.cs, ConversionReportMasterDetail.cs).
                cmbBranch.EditValue = Login.assignedBranch;
                cmbBranch.Enabled = false;
            }

            // @parmbrcode has no default in the SP -- a branch must always be selected, so
            // default to the current/only branch rather than leaving it blank for a
            // HeadOffice user.
            if (cmbBranch.EditValue == null)
                cmbBranch.EditValue = Login.assignedBranch;

            // @datefrom/@dateto have no defaults in the SP either -- default to the current
            // month to date rather than leaving them blank.
            var today = DateTime.Today;
            dtFrom.EditValue = new DateTime(today.Year, today.Month, 1);
            dtTo.EditValue = today;
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
            if (cmbBranch.EditValue == null)
            {
                XtraMessageBox.Show("Please select a Branch.");
                return;
            }
            if (!(dtFrom.EditValue is DateTime dateFrom) || !(dtTo.EditValue is DateTime dateTo))
            {
                XtraMessageBox.Show("Please select both a From and a To date.");
                return;
            }
            if (dateFrom > dateTo)
            {
                XtraMessageBox.Show("From date cannot be after the To date.");
                return;
            }

            try
            {
                string branch = cmbBranch.EditValue.ToString();

                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("dbo.spr_InventoryUnitActivity", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@parmbrcode", SqlDbType.Char, 3).Value = branch;
                    cmd.Parameters.Add("@datefrom", SqlDbType.Date).Value = dateFrom;
                    cmd.Parameters.Add("@dateto", SqlDbType.Date).Value = dateTo;

                    var dt = new DataTable();
                    con.Open();
                    new SqlDataAdapter(cmd).Fill(dt);

                    // Must clear before rebinding -- otherwise repeated Load clicks reuse the
                    // same GridColumn objects and stack duplicate footer summary items (the
                    // exact bug found and fixed in Reporting/InventoryReport.cs earlier).
                    gridView1.Columns.Clear();
                    gridControl1.DataSource = dt;
                }

                ApplyFormat();

                lblBranchName.Text = "Branch: " + (cmbBranch.Text ?? branch);
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message, "Load Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        // ================================================================
        // FORMATTING (reapplied after every load -- DataSource reassignment
        // regenerates columns and wipes any previous per-column formatting).
        // ================================================================
        private void ApplyFormat()
        {
            HideColumn("BranchCode");
            HideColumn("ProductCode");

            SetCaption("ItemCode", "Item Code");
            SetCaption("Description", "Product");
            SetCaption("BeginningQty", "Beginning Qty");
            SetCaption("UnitPurchased", "Unit Purchased");
            SetCaption("Adjustment", "Adjustment");
            SetCaption("UnitSold", "Unit Sold");
            SetCaption("QtyOnHand", "Qty On Hand");
            SetCaption("UnitCost", "Unit Cost");
            SetCaption("ItemValue", "Item Value");
            SetCaption("Sales", "Sales");
            SetCaption("Cost", "Cost of Goods Sold");

            FormatNumericColumn("BeginningQty", "N3");
            FormatNumericColumn("UnitPurchased", "N3");
            FormatNumericColumn("Adjustment", "N3");
            FormatNumericColumn("UnitSold", "N3");
            FormatNumericColumn("QtyOnHand", "N3");
            FormatNumericColumn("UnitCost", "N2");
            FormatNumericColumn("ItemValue", "N2");
            FormatNumericColumn("Sales", "N2");
            FormatNumericColumn("Cost", "N2");

            gridView1.BestFitColumns();
        }

        private void HideColumn(string field)
        {
            if (gridView1.Columns[field] != null) gridView1.Columns[field].Visible = false;
        }

        private void SetCaption(string field, string caption)
        {
            if (gridView1.Columns[field] != null) gridView1.Columns[field].Caption = caption;
        }

        private void FormatNumericColumn(string field, string formatString)
        {
            var col = gridView1.Columns[field];
            if (col == null) return;
            col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            col.DisplayFormat.FormatString = formatString;
            col.Summary.Add(DevExpress.Data.SummaryItemType.Sum, field, "{0:" + formatString + "}");
        }

        // ================================================================
        // EXPORT
        // ================================================================
        private void btnExport_Click(object sender, EventArgs e)
        {
            HelperFunction.exporttoexcel(gridView1, "INVENTORY_UNIT_ACTIVITY_" + DateTime.Now.ToString("yyyyMMdd_HHmmss"));
        }
    }
}
