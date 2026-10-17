using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.Utils;
using DevExpress.XtraEditors;

namespace SalesInventorySystem.Reporting
{
    // Inventory Unit Activity report over dbo.spr_InventoryUnitActivity (@parmbrcode, @datefrom, @dateto).
    // Since script [102] (2026-10-17) the proc works per lot: Beginning Qty = everything before the period,
    // then every IN (Unit Purchased, STS In, Branch Transfer In, Conversion In, Inventory In, Sales Return)
    // and OUT (Unit Sold, STS Out, Branch Transfer Out, Conversion Out) of the period, Adjustment (+/-),
    // Qty On Hand (= next period's Beginning Qty), values at each lot's own cost. Rules: the [102] script.
    // Head office can pick "ALL BRANCHES" (the proc gets a NULL branch). The older
    // Reporting/InventoryUnitActivity.cs is hidden (it calls the proc with wrong parameter names).
    public partial class InventoryUnitActivityReport : XtraForm
    {
        private const string AllBranches = "ALL";

        public InventoryUnitActivityReport()
        {
            InitializeComponent();
            Classes.DevXGridViewSettings.ApplyTotalsBandAppearance(gridView1);
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

            // Head office gets an "ALL BRANCHES" row first (value ALL -> NULL to the proc).
            string query = isHeadOffice
                ? "SELECT 'ALL' AS BranchCode, 'ALL BRANCHES' AS BranchName, 'ALL BRANCHES' AS DisplayText, 0 AS SortKey " +
                  "UNION ALL SELECT BranchCode, BranchName, BranchCode + ' - ' + BranchName, 1 FROM Branches ORDER BY SortKey, BranchCode"
                : "SELECT BranchCode, BranchName, BranchCode + ' - ' + BranchName AS DisplayText FROM Branches ORDER BY BranchCode";
            Database.displaySearchlookupEdit(query, cmbBranch, "DisplayText", "BranchCode");
            // The helper clears the popup's columns and the view only creates them when first shown, so
            // hiding them here would silently do nothing: add the two visible ones explicitly instead.
            cmbBranch.Properties.View.Columns.Clear();
            cmbBranch.Properties.View.Columns.AddVisible("BranchCode", "Code");
            cmbBranch.Properties.View.Columns.AddVisible("BranchName", "Branch");
            cmbBranch.Properties.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;

            if (!isHeadOffice)
            {
                // Matches the role-scoping pattern used in every other report built this
                // session (ConversionReports.cs, InventoryReport.cs, ConversionReportMasterDetail.cs).
                cmbBranch.EditValue = Login.assignedBranch;
                cmbBranch.Enabled = false;
            }

            // default to the user's own branch rather than leaving it blank
            if (cmbBranch.EditValue == null)
                cmbBranch.EditValue = Login.assignedBranch;

            // default to the current month to date
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
            if (cmbBranch.EditValue == null || cmbBranch.EditValue == DBNull.Value)
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

            string branch = cmbBranch.EditValue.ToString();
            bool allBranches = branch == AllBranches;
            if (allBranches && Login.assignedBranch != "888")
            {
                XtraMessageBox.Show("Only head office can run the report for all branches.");
                return;
            }

            try
            {
                btnLoad.Enabled = false;   // one run at a time (ALL BRANCHES can take a few seconds)
                Cursor = Cursors.WaitCursor;
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("dbo.spr_InventoryUnitActivity", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 300;
                    cmd.Parameters.Add("@parmbrcode", SqlDbType.Char, 3).Value = allBranches ? (object)DBNull.Value : branch;
                    cmd.Parameters.Add("@datefrom", SqlDbType.Date).Value = dateFrom.Date;
                    cmd.Parameters.Add("@dateto", SqlDbType.Date).Value = dateTo.Date;

                    var dt = new DataTable();
                    con.Open();
                    using (var da = new SqlDataAdapter(cmd))
                        da.Fill(dt);

                    // Code - Name for the branch column (shown only for ALL BRANCHES)
                    if (dt.Columns.Contains("BranchName") && dt.Columns.Contains("BranchCode"))
                    {
                        dt.Columns["BranchName"].ReadOnly = false;
                        dt.Columns["BranchName"].MaxLength = -1;
                        foreach (DataRow r in dt.Rows)
                            r["BranchName"] = Convert.ToString(r["BranchCode"]) + " - " + Convert.ToString(r["BranchName"]);
                    }

                    // Must clear before rebinding -- otherwise repeated Load clicks reuse the
                    // same GridColumn objects and stack duplicate footer summary items (the
                    // exact bug found and fixed in Reporting/InventoryReport.cs earlier).
                    gridView1.Columns.Clear();
                    gridControl1.DataSource = dt;
                }

                ApplyFormat(allBranches);

                lblBranchName.Text = "Branch: " + (cmbBranch.Text ?? branch);
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message, "Load Failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                Cursor = Cursors.Default;
                btnLoad.Enabled = true;
            }
        }

        // ================================================================
        // FORMATTING (reapplied after every load -- DataSource reassignment
        // regenerates columns and wipes any previous per-column formatting).
        // ================================================================
        private static readonly string[] QtyColumns =
        {
            "BeginningQty", "UnitPurchased", "STSIn", "BranchTransferIn", "ConversionIn", "InventoryIn", "SalesReturn",
            "UnitSold", "STSOut", "BranchTransferOut", "ConversionOut", "Adjustment", "QtyOnHand"
        };

        private void ApplyFormat(bool allBranches)
        {
            HideColumn("BranchCode");
            HideColumn("ProductCode");
            if (!allBranches) HideColumn("BranchName");

            SetCaption("BranchName", "Branch");
            SetCaption("ItemCode", "Item Code");
            SetCaption("Description", "Product");
            SetCaption("BeginningQty", "Beginning Qty");
            SetCaption("UnitPurchased", "Unit Purchased");
            SetCaption("STSIn", "STS In");
            SetCaption("BranchTransferIn", "Branch Transfer In");
            SetCaption("ConversionIn", "Conversion In");
            SetCaption("InventoryIn", "Inventory In");
            SetCaption("SalesReturn", "Sales Return");
            SetCaption("UnitSold", "Unit Sold");
            SetCaption("STSOut", "STS Out");
            SetCaption("BranchTransferOut", "Branch Transfer Out");
            SetCaption("ConversionOut", "Conversion Out");
            SetCaption("Adjustment", "Adjustment (+/-)");
            SetCaption("QtyOnHand", "Qty On Hand");
            SetCaption("UnitCost", "Unit Cost");
            SetCaption("ItemValue", "Item Value");
            SetCaption("Sales", "Sales");
            SetCaption("Cost", "Cost of Sales");

            foreach (string field in QtyColumns)
                FormatNumericColumn(field, "N3", true);
            FormatNumericColumn("UnitCost", "N2", false);   // a sum of unit costs means nothing
            FormatNumericColumn("ItemValue", "N2", true);
            FormatNumericColumn("Sales", "N2", true);
            FormatNumericColumn("Cost", "N2", true);

            gridView1.BestFitMaxRowCount = 500;
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

        private void FormatNumericColumn(string field, string formatString, bool withSum)
        {
            var col = gridView1.Columns[field];
            if (col == null) return;
            col.DisplayFormat.FormatType = FormatType.Numeric;
            col.DisplayFormat.FormatString = formatString;
            col.AppearanceCell.TextOptions.HAlignment = HorzAlignment.Far;
            col.AppearanceCell.Options.UseTextOptions = true;
            col.AppearanceHeader.TextOptions.HAlignment = HorzAlignment.Far;
            col.AppearanceHeader.Options.UseTextOptions = true;
            if (withSum)
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
