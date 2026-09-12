using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Text;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid;
using DevExpress.XtraGrid.Views.Grid;
using SalesInventorySystem.Classes;

namespace SalesInventorySystem.POS
{
    public partial class POSSalesReportDevEx : DevExpress.XtraEditors.XtraForm
    {
        object custkey = null;
        object brcodesummary = null, brcodedetails = null;
        public POSSalesReportDevEx()
        {
            InitializeComponent();
            // Belt-and-suspenders with the explicit ExpandAllGroups() call in
            // LoadCustomerCashReceipts() -- matches Accounting/AgingReports.cs, which sets this
            // once at construction so newly created groups always start expanded regardless of
            // exactly when grouping is applied relative to the grid's own layout pass.
            gridView1.OptionsBehavior.AutoExpandAllGroups = true;

            // Highlight the group footer (the ControlNo totals row) so the per-group summary
            // stands out from the data rows -- same GroupFooter styling approach as
            // HOForms/POSTransactions.cs, just with a warmer accent to read as a "totals" band.
            gridView1.Appearance.GroupFooter.Font = new Font("Tahoma", 9.75F, FontStyle.Bold);
            gridView1.Appearance.GroupFooter.ForeColor = Color.FromArgb(102, 60, 0);
            gridView1.Appearance.GroupFooter.BackColor = Color.FromArgb(255, 244, 214);
            gridView1.Appearance.GroupFooter.Options.UseFont = true;
            gridView1.Appearance.GroupFooter.Options.UseForeColor = true;
            gridView1.Appearance.GroupFooter.Options.UseBackColor = true;

            // Same accent on the grid's bottom-of-page grand totals (ShowFooterTotal already adds
            // a Sum to each amount column's own footer, not just the per-ControlNo GroupFooter
            // above -- this was the one place left unstyled).
            gridView1.Appearance.FooterPanel.Font = new Font("Tahoma", 9.75F, FontStyle.Bold);
            gridView1.Appearance.FooterPanel.ForeColor = Color.FromArgb(102, 60, 0);
            gridView1.Appearance.FooterPanel.BackColor = Color.FromArgb(255, 244, 214);
            gridView1.Appearance.FooterPanel.Options.UseFont = true;
            gridView1.Appearance.FooterPanel.Options.UseForeColor = true;
            gridView1.Appearance.FooterPanel.Options.UseBackColor = true;

            // Wired once here rather than per-load: gridView2 is the single designer-declared
            // instance reused across every "Generate" click (Summary/master-detail-Details/flat-
            // Details), so wiring this inside a load method would stack a duplicate handler on
            // every click. Only fires for summary items that are actually SummaryItemType.Custom
            // with a matching FieldName -- harmless no-op for modes that never add one (see
            // AddDistinctCountGroupSummary, only called from LoadCustomerSalesHistoryDetailsFlat).
            gridView2.CustomSummaryCalculate += gridView2_CustomSummaryCalculate;

            // Same "totals band" highlight as gridView1's GroupFooter above, applied to gridView2
            // across all three places its summaries actually render:
            //  - GroupRow: the group's own caption row -- where the distinct invoice count lands
            //    (AddDistinctCountGroupSummary has no ShowInGroupColumnFooter, so it's appended
            //    to the caption text instead of a footer cell).
            //  - GroupFooter: the per-group subtotal band -- where the ShowInGroupColumnFooter-
            //    based summaries actually render (AddSumFooter/AddCountGroupSummary for PONumber/
            //    QtyDelivered/Amount/CostOfSalesAmount), same mechanism/appearance target as
            //    gridView1's ShowFooterTotal-based ControlNo summaries above.
            //  - FooterPanel: the grid's bottom-of-page grand totals.
            // No visible effect in Summary/master-detail modes, which don't have grouping active.
            gridView2.Appearance.GroupRow.Font = new Font("Tahoma", 9.75F, FontStyle.Bold);
            gridView2.Appearance.GroupRow.ForeColor = Color.FromArgb(102, 60, 0);
            gridView2.Appearance.GroupRow.BackColor = Color.FromArgb(255, 244, 214);
            gridView2.Appearance.GroupRow.Options.UseFont = true;
            gridView2.Appearance.GroupRow.Options.UseForeColor = true;
            gridView2.Appearance.GroupRow.Options.UseBackColor = true;

            gridView2.Appearance.GroupFooter.Font = new Font("Tahoma", 9.75F, FontStyle.Bold);
            gridView2.Appearance.GroupFooter.ForeColor = Color.FromArgb(102, 60, 0);
            gridView2.Appearance.GroupFooter.BackColor = Color.FromArgb(255, 244, 214);
            gridView2.Appearance.GroupFooter.Options.UseFont = true;
            gridView2.Appearance.GroupFooter.Options.UseForeColor = true;
            gridView2.Appearance.GroupFooter.Options.UseBackColor = true;

            gridView2.Appearance.FooterPanel.Font = new Font("Tahoma", 9.75F, FontStyle.Bold);
            gridView2.Appearance.FooterPanel.ForeColor = Color.FromArgb(102, 60, 0);
            gridView2.Appearance.FooterPanel.BackColor = Color.FromArgb(255, 244, 214);
            gridView2.Appearance.FooterPanel.Options.UseFont = true;
            gridView2.Appearance.FooterPanel.Options.UseForeColor = true;
            gridView2.Appearance.FooterPanel.Options.UseBackColor = true;
        }
        private void LoadCustomerSalesHistory(string branchCode)
        {
            // gridControl2's DataSource/DataMember/LevelTree are fully reset in
            // btnsalestransummary_Click before any of the three load methods runs -- see its
            // comment for why that reset has to happen there, once, rather than being
            // half-duplicated across each method.
            string sql = $@"
                SELECT *
                FROM dbo.funcview_CustomerSalesHistory(
                    '{branchCode}',
                    '{datefromsalessum.Value.Date:yyyy-MM-dd}',
                    '{datetosalessum.Value.Date:yyyy-MM-dd}'
                )
                ORDER BY CustomerName";

            Database.display(sql, gridControl2, gridView2);

            // Forces GridControl to fully rebuild its column/view bindings against the new flat
            // DataTable. Without this, a GridControl that was previously in master-detail mode
            // (Database.GridMasterDetail calls this same method internally when it BINDS, but
            // nothing calls it when leaving that mode) can retain stale internal state and fail
            // to (re)populate gridView2's columns at all -- the grid renders with no header.
            gridControl2.ForceInitialize();
        }

        // Details mode for the SalesTransactionSummary tab -- converted to a master-detail grid.
        // Master = funcview_CustomerSalesHistoryDetails (one row per Customer+Invoice, unchanged).
        // Detail = new funcview_CustomerSalesInvoiceDetails (one row per line item within that
        // invoice), modeled on funcview_CustomerSalesJournal's shape per the request, but built as
        // its own dedicated SQL object rather than reusing/mutating that function -- it's still
        // live-used by this form's separate Cash Receipts Book/Sales Journal section.
        //
        // Relation key: a bare Invoice/InvoiceNo join would be unsafe -- verified live that
        // InvoiceNo is NOT globally unique (several values repeat across different BranchCodes),
        // so a naive join could leak another branch's line items into a customer's invoice detail
        // (same shape as CLAUDE.md known bug pattern #7, applied to this new key). Both sides
        // expose/derive a composite InvoiceKey = BranchCode + '|' + Invoice instead.
        private void LoadCustomerSalesHistoryDetails(string branchCode)
        {
            // Branch is always CONCAT(BranchCode,' - ',BranchName) with BranchCode fixed at
            // 3 chars (funcview_CustomerSalesHistoryDetails doesn't expose a raw BranchCode
            // column). LEFT(Branch,3) recovers it without the CHARINDEX/SUBSTRING approach
            // (which throws "Invalid length parameter" if CHARINDEX ever returned 0).
            string masterSql = @"
                SELECT *,
                    LEFT(Branch, 3) + '|' + Invoice AS InvoiceKey
                FROM dbo.funcview_CustomerSalesHistoryDetails(@parmbranchcode, @datefrom, @dateto)
                ORDER BY CustomerName";

            string detailSql = @"
                SELECT *
                FROM dbo.funcview_CustomerSalesInvoiceDetails(@parmbranchcode, @datefrom, @dateto)
                ORDER BY InvoiceKey, PONumber";

            var reportParams = new[]
            {
                new SqlParameter("@parmbranchcode", SqlDbType.VarChar, 3) { Value = branchCode },
                new SqlParameter("@datefrom", SqlDbType.Date) { Value = datefromsalessum.Value.Date },
                new SqlParameter("@dateto", SqlDbType.Date) { Value = datetosalessum.Value.Date }
            };

            Database.GridMasterDetail(
                masterQuery: masterSql,
                detailQuery: detailSql,
                masterTable: "Master",
                detailTable: "LineItems",
                masterKey: "InvoiceKey",
                detailKey: "InvoiceKey",
                relationName: "Invoice Line Items",
                grid: gridControl2,
                masterParams: reportParams,
                detailParams: Database.CloneParams(reportParams));

            var masterView = gridControl2.MainView as GridView;
            if (masterView != null)
            {
                HideColumn(masterView, "InvoiceKey");
                masterView.BestFitColumns();
            }

            var detailView = gridControl2.LevelTree.Nodes["Invoice Line Items"]?.LevelTemplate as GridView;
            if (detailView != null)
            {
                HideColumn(detailView, "InvoiceKey");
                HideColumn(detailView, "CustomerKey");
                HideColumn(detailView, "CustomerID");
                HideColumn(detailView, "CustomerName");
                HideColumn(detailView, "BranchCode");
                HideColumn(detailView, "Branch");
                HideColumn(detailView, "InvoiceNo");
                // Quantity/Amount columns must render as numeric-formatted values, not the
                // default text rendering -- see CLAUDE.md's reporting convention.
                FormatNumericColumn(detailView, "UnitPrice", "N2");
                FormatNumericColumn(detailView, "Cost", "N2");
                AddSumFooter(detailView, "QtyDelivered", "N3");
                AddSumFooter(detailView, "Amount", "N2");
                AddSumFooter(detailView, "CostOfSalesAmount", "N2");
                detailView.OptionsView.ShowFooter = true;
                detailView.BestFitColumns();
            }
        }

        // Flat alternative to LoadCustomerSalesHistoryDetails, for when chkViewAsMasterDetail
        // is unchecked. A master-detail GridView's header (the master level) does not support
        // dragging columns to reorder/group -- that's only available on an ordinary flat GridView.
        // funcview_CustomerSalesInvoiceDetails already returns one row per line item with every
        // master-level field (CustomerName, Branch, InvoiceNo, InvoiceDate, ...) joined in, so no
        // new SQL object is needed -- this just binds it directly instead of routing it through
        // Database.GridMasterDetail.
        private void LoadCustomerSalesHistoryDetailsFlat(string branchCode)
        {
            // gridControl2's DataSource/DataMember/LevelTree are fully reset in
            // btnsalestransummary_Click before any of the three load methods runs -- see its
            // comment for why that reset has to happen there, once, rather than being
            // half-duplicated across each method.
            string sql = @"
                SELECT *
                FROM dbo.funcview_CustomerSalesInvoiceDetails(@parmbranchcode, @datefrom, @dateto)
                ORDER BY CustomerName, InvoiceNo, PONumber";

            using (SqlConnection con = Database.getConnection())
            using (SqlDataAdapter adapter = new SqlDataAdapter(sql, con))
            {
                adapter.SelectCommand.Parameters.Add(new SqlParameter("@parmbranchcode", SqlDbType.VarChar, 3) { Value = branchCode });
                adapter.SelectCommand.Parameters.Add(new SqlParameter("@datefrom", SqlDbType.Date) { Value = datefromsalessum.Value.Date });
                adapter.SelectCommand.Parameters.Add(new SqlParameter("@dateto", SqlDbType.Date) { Value = datetosalessum.Value.Date });

                DataTable table = new DataTable();
                adapter.Fill(table);
                gridControl2.DataSource = table;
            }

            // Forces GridControl to fully rebuild its column/view bindings against the new flat
            // DataTable -- see the identical comment/reasoning in LoadCustomerSalesHistory. This
            // is the fix for the reported bug: switching from "View as Master-Detail" checked to
            // unchecked left the grid with no header columns because nothing forced a rebuild.
            gridControl2.ForceInitialize();

            HideColumn(gridView2, "InvoiceKey");
            HideColumn(gridView2, "CustomerKey");
            // BranchCode is redundant with the already-formatted Branch column ("888 - Head
            // Office" etc) -- CustomerID/CustomerName/InvoiceNo stay visible since, unlike the
            // master-detail version, there's no master row here to show them instead.
            HideColumn(gridView2, "BranchCode");

            // Same numeric/footer formatting the master-detail detail view applies -- see
            // CLAUDE.md's reporting convention (Quantity/Amount columns must render numeric).
            FormatNumericColumn(gridView2, "UnitPrice", "N2");
            FormatNumericColumn(gridView2, "Cost", "N2");
            AddSumFooter(gridView2, "QtyDelivered", "N3");
            AddSumFooter(gridView2, "Amount", "N2");
            AddSumFooter(gridView2, "CostOfSalesAmount", "N2");

            // Now that columns can be dragged into the group panel here, add a per-group line
            // count alongside the sums above -- e.g. group by CustomerName or Product to see how
            // many line items and how much per group, not just the grand total at the bottom.
            AddCountGroupSummary(gridView2, "PONumber");

            // A plain row-count on InvoiceNo would just repeat the PONumber count above -- one
            // invoice can span several line-item rows, so that would count LINES, not invoices.
            // Grouping InvoiceDate -> InvoiceNo (per the reported use case) needs the distinct
            // invoice count under each date instead, hence the Custom/HashSet-based summary.
            AddDistinctCountGroupSummary(gridView2, "InvoiceNo", "Invoices");

            gridView2.OptionsView.ShowFooter = true;
            gridView2.OptionsView.ShowGroupPanel = true;

            // Default grouping: InvoiceDate -> InvoiceNo, matching the reported use case (see how
            // many/which invoices fall under each date, via the distinct-count summary above).
            // User can still drag other columns into the group panel to regroup differently --
            // this is just the starting arrangement instead of requiring a manual drag every time.
            gridView2.BeginSort();
            gridView2.ClearGrouping();
            if (gridView2.Columns["InvoiceDate"] != null)
                gridView2.Columns["InvoiceDate"].GroupIndex = 0;
            if (gridView2.Columns["InvoiceNo"] != null)
                gridView2.Columns["InvoiceNo"].GroupIndex = 1;
            gridView2.EndSort();
            gridView2.ExpandAllGroups();
        }

        private void HideColumn(GridView view, string field)
        {
            if (view.Columns[field] != null) view.Columns[field].Visible = false;
        }

        private void FormatNumericColumn(GridView view, string field, string formatString)
        {
            var col = view.Columns[field];
            if (col == null) return;
            col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            col.DisplayFormat.FormatString = formatString;
        }

        // Removes any existing GroupSummary item for this field before a helper adds its own --
        // self-defense so AddSumFooter/AddCountGroupSummary don't depend entirely on the caller
        // having cleared view.GroupSummary first (that clear happens today in
        // btnsalestransummary_Click, but a future edit could reorder/bypass it, and a stale item
        // here would hold a ShowInGroupColumnFooter reference to a GridColumn that's about to be
        // replaced by Columns.Clear()).
        private void RemoveGroupSummary(GridView view, string field)
        {
            for (int i = view.GroupSummary.Count - 1; i >= 0; i--)
            {
                if (view.GroupSummary[i].FieldName == field)
                    view.GroupSummary.RemoveAt(i);
            }
        }

        private void AddSumFooter(GridView view, string field, string formatString = "N2")
        {
            var col = view.Columns[field];
            if (col == null) return;
            FormatNumericColumn(view, field, formatString);
            // Database.GridMasterDetail already adds a Sum summary to any detail column named
            // "QtyDelivered" (its internal whitelist) -- clear first so re-adding one here for
            // that same column doesn't stack a second, duplicate Sum item in the footer cell.
            col.Summary.Clear();
            col.Summary.Add(DevExpress.Data.SummaryItemType.Sum, field, "{0:" + formatString + "}");

            // Per-group subtotal, shown inline in this column's own cell within the group footer
            // row -- relevant now that the flat Details grid (gridView2) supports drag-to-group.
            RemoveGroupSummary(view, field);
            var groupItem = new GridGroupSummaryItem();
            groupItem.FieldName = field;
            groupItem.SummaryType = DevExpress.Data.SummaryItemType.Sum;
            groupItem.ShowInGroupColumnFooter = col;
            groupItem.DisplayFormat = "{0:" + formatString + "}";
            view.GroupSummary.Add(groupItem);
        }

        // Per-group row count, shown inline in the given column's group footer cell (plus the
        // overall count in the grid's bottom footer) -- same GroupSummary contract as AddSumFooter.
        private void AddCountGroupSummary(GridView view, string field, string label = "Count")
        {
            var col = view.Columns[field];
            if (col == null) return;

            col.Summary.Clear();
            col.Summary.Add(DevExpress.Data.SummaryItemType.Count, field, label + ": {0}");

            RemoveGroupSummary(view, field);
            var groupItem = new GridGroupSummaryItem();
            groupItem.FieldName = field;
            groupItem.SummaryType = DevExpress.Data.SummaryItemType.Count;
            groupItem.ShowInGroupColumnFooter = col;
            groupItem.DisplayFormat = label + ": {0}";
            view.GroupSummary.Add(groupItem);
        }

        // Per-group DISTINCT count of the given field (not a row count) -- e.g. grouping by
        // InvoiceDate then InvoiceNo: AddCountGroupSummary on PONumber counts LINE-ITEM ROWS per
        // date, but an invoice with several line items would inflate that same count if reused
        // for "how many invoices" -- SummaryItemType.Count has no distinct-value mode built in,
        // so this drives a SummaryItemType.Custom summary via gridView2_CustomSummaryCalculate
        // (wired once in the constructor) to actually count unique values instead of rows.
        private void AddDistinctCountGroupSummary(GridView view, string field, string label = "Count")
        {
            var col = view.Columns[field];
            if (col == null) return;

            col.Summary.Clear();
            col.Summary.Add(DevExpress.Data.SummaryItemType.Custom, field, label + ": {0}");

            RemoveGroupSummary(view, field);
            var groupItem = new GridGroupSummaryItem();
            groupItem.FieldName = field;
            groupItem.SummaryType = DevExpress.Data.SummaryItemType.Custom;
            // Deliberately NOT setting ShowInGroupColumnFooter here (unlike AddSumFooter/
            // AddCountGroupSummary): this summary's whole purpose is to be read while the field
            // itself is the active GROUPED column (e.g. group by InvoiceDate then InvoiceNo, to
            // see "how many invoices per date"). A grouped column is hidden from the row's normal
            // cell area (OptionsView.ShowGroupedColumns is false by default), so pointing
            // ShowInGroupColumnFooter at that same column's cell has nowhere to draw -- the value
            // computes fine but never renders. Leaving it unset falls back to DevExpress's default
            // of appending the summary text to the group row's own caption instead, which always
            // has somewhere to show regardless of which column is currently grouped.
            groupItem.DisplayFormat = label + ": {0}";
            view.GroupSummary.Add(groupItem);
        }

        // Generic distinct-value counter for any SummaryItemType.Custom summary on gridView2 --
        // DevExpress resets/isolates e.TotalValue independently per summary instance and per
        // active group scope, so one handler correctly serves the group-level AND grid-footer
        // Custom summaries added by AddDistinctCountGroupSummary without cross-contamination.
        private void gridView2_CustomSummaryCalculate(object sender, DevExpress.Data.CustomSummaryEventArgs e)
        {
            // e.Item is untyped object -- it's a GridGroupSummaryItem for a group summary or a
            // GridColumnSummaryItem for the grid's bottom footer; both expose SummaryType.
            DevExpress.Data.SummaryItemType summaryType;
            if (e.Item is GridGroupSummaryItem groupSummaryItem)
                summaryType = groupSummaryItem.SummaryType;
            else if (e.Item is DevExpress.XtraGrid.GridColumnSummaryItem columnSummaryItem)
                summaryType = columnSummaryItem.SummaryType;
            else
                return;

            if (summaryType != DevExpress.Data.SummaryItemType.Custom)
                return;

            switch (e.SummaryProcess)
            {
                case DevExpress.Data.CustomSummaryProcess.Start:
                    e.TotalValue = new HashSet<string>();
                    break;
                case DevExpress.Data.CustomSummaryProcess.Calculate:
                    string value = Convert.ToString(e.FieldValue);
                    if (!string.IsNullOrEmpty(value))
                        ((HashSet<string>)e.TotalValue).Add(value);
                    break;
                case DevExpress.Data.CustomSummaryProcess.Finalize:
                    e.TotalValue = ((HashSet<string>)e.TotalValue).Count;
                    break;
            }
        }

        // Collapse/Expand All for gridView2's groups (Sales Transaction Summary tab -- Summary
        // mode or flat Details mode, whichever is currently grouped; a no-op if nothing is
        // grouped, and irrelevant to master-detail Details, which doesn't use GroupIndex at all).
        private void btnCollapseAllGroups_Click(object sender, EventArgs e)
        {
            gridView2.CollapseAllGroups();
        }

        private void btnExpandAllGroups_Click(object sender, EventArgs e)
        {
            gridView2.ExpandAllGroups();
        }

        private void LoadCustomerCashReceipts()
        {
            // 'I' = ARPaymentDetails.InvoiceDate, 'P' = PaymentHeader.PaymentDate -- see
            // SQL/2026-09-11_CustomerCashReceipts_DateFilterTypeOption.sql. Caller
            // (populateCashReceiptsBook) already brackets this with
            // BeginDataUpdate/Columns.Clear/EndDataUpdate/BestFitColumns.
            string dateFilterType = radDateFilterInvoice.Checked ? "I" : "P";

            using (SqlConnection con = Database.getConnection())
            using (SqlCommand com = new SqlCommand("SELECT * FROM dbo.funcview_CustomerCashReceipts(@datefrom, @dateto, @dateFilterType)", con))
            {
                com.Parameters.Add("@datefrom", SqlDbType.Date).Value = datefromcashreceipts.Value.Date;
                com.Parameters.Add("@dateto", SqlDbType.Date).Value = datetocashreceipts.Value.Date;
                com.Parameters.Add("@dateFilterType", SqlDbType.Char, 1).Value = dateFilterType;

                using (SqlDataAdapter adapter = new SqlDataAdapter(com))
                {
                    DataTable table = new DataTable();
                    adapter.Fill(table);
                    gridControl1.DataSource = null; // clean slate -- same idiom Database.display uses
                    gridControl1.DataSource = table;
                }
            }

            // Group by ControlNo, expanded by default, with per-group totals -- amounts come back
            // as numeric decimal now (see SQL/2026-08-07_CustomerCashReceipts_NumericAmounts.sql;
            // the prior FORMAT()-string columns couldn't be summed).
            gridView1.BeginSort();
            gridView1.ClearGrouping();
            if (gridView1.Columns["ControlNo"] != null)
                gridView1.Columns["ControlNo"].GroupIndex = 0;
            gridView1.EndSort();
            gridView1.ExpandAllGroups();

            gridView1.GroupSummary.Clear();
            string[] amountColumns = { "TotalAmount", "InvoicePaymentAmount", "EwtAmount", "DiscountAmount" };
            foreach (string col in amountColumns)
            {
                Classes.DevXGridViewSettings.ShowFooterTotal(gridView1, col);

                // ShowFooterTotal formats the bottom-of-grid footer panel ("{0:n2}") and the data
                // rows pick up the column DisplayFormat set below, but the GridGroupSummaryItem it
                // adds to GroupSummary (the per-ControlNo group footer -- the one that actually
                // matters here) has no DisplayFormat of its own and does NOT fall back to the
                // column's -- it has to be set directly on that summary item.
                gridView1.Columns[col].DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                gridView1.Columns[col].DisplayFormat.FormatString = "n2";

                foreach (GridGroupSummaryItem item in gridView1.GroupSummary)
                {
                    if (item.FieldName == col)
                        item.DisplayFormat = "{0:n2}";
                }
            }
        }
        private void LoadCustomerSalesJournal()
        {
            string sql = $@"
                SELECT *
                FROM dbo.funcview_CustomerSalesJournal(
                    '{datefromcashreceipts.Value.Date:yyyy-MM-dd}',
                    '{datetocashreceipts.Value.Date:yyyy-MM-dd}'
                )";
            //ORDER BY CustomerName";

            Database.display(sql, gridControl1, gridView1);
        }
        private void LoadSalesData(string viewName, string dateColumn, string branchCode)
        {
            string sql = $@"
                SELECT *
                FROM {viewName}
                WHERE BranchCode = '{branchCode}'
                AND {dateColumn} >= '{datefromsalessum.Value.Date:yyyy-MM-dd}'
                AND {dateColumn} < DATEADD(DAY,1,'{datetosalessum.Value.Date:yyyy-MM-dd}')
                ORDER BY ReferenceNo";

            Database.display(sql, gridControl2, gridView2);
        }
        private string GetBranchCode(string selectedBranch)
        {
            return Login.assignedBranch == "888"
                ? selectedBranch
                : Login.assignedBranch;
        }

        private void btnsalestransummary_Click(object sender, EventArgs e)
        {
           
            try
            {
                gridView2.BeginDataUpdate();

                // Full reset before every generation -- a prior Master-Detail bind
                // (Database.GridMasterDetail, used when "View as Master-Detail" is checked)
                // leaves gridControl2.DataMember="Master" and a LevelTree relation node behind.
                // DataSource is nulled FIRST (same order Database.display/GridMasterDetail
                // themselves use) so DataMember is never touched while a stale multi-table
                // DataSet is still attached; without this, switching back to an ordinary flat
                // bind (Summary, or Details with the checkbox unchecked) could leave the grid
                // showing no header columns at all.
                gridControl2.DataSource = null;
                gridControl2.DataMember = "";
                gridControl2.LevelTree.Nodes.Clear();
                gridView2.ClearGrouping();
                gridView2.GroupSummary.Clear();
                gridView2.Columns.Clear();

                string branchCode =
                    chckboxAllBranch.Checked
                    ? "ALL"
                    : (Login.assignedBranch == "888"
                        ? brcodesummary.ToString()
                        : Login.assignedBranch);

                if (radbuttonsummary.Checked)
                {
                    LoadCustomerSalesHistory(branchCode);
                }
                else if (chkViewAsMasterDetail.Checked)
                {
                    LoadCustomerSalesHistoryDetails(branchCode);
                }
                else
                {
                    LoadCustomerSalesHistoryDetailsFlat(branchCode);
                }

                gridView2.BestFitColumns();

                //gridView2.Columns["SalesPerson"].GroupIndex = 0;
                //gridView2.Columns["CustomerName"].GroupIndex = 1;

                //gridView2.ExpandAllGroups();
                //gridView2.OptionsBehavior.AutoExpandAllGroups = true;
                //gridView2.ExpandAllGroups();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(
                    ex.Message,
                    "Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            finally
            {
                gridView2.EndDataUpdate();
            }

        }
        //private void btnsalestransummary_Click(object sender, EventArgs e)
        //{
        //    if(radbuttonsummary.Checked == true)
        //    {
        //        if (Login.assignedBranch != "888")
        //        {
        //            Database.display("SELECT * FROM view_batchTransactionSummary " +
        //                  "WHERE BranchCode='" + Login.assignedBranch + "' " +
        //                  "AND CAST(TransDate as Date) >= '" + datefromsalessum.Text + "' AND CAST(TransDate as Date) <= '" + datetosalessum.Text + "' ORDER BY ReferenceNo", gridControl2, gridView2);
        //        }
        //        else
        //        {
        //            Database.display("SELECT * FROM view_batchTransactionSummary " +
        //                   $"WHERE BranchCode='{brcodesummary.ToString()}' " +
        //                   "AND CAST(TransDate as Date) >= '" + datefromsalessum.Text + "' AND CAST(TransDate as Date) <= '" + datetosalessum.Text + "' ORDER BY ReferenceNo", gridControl2, gridView2);
        //        }
        //    }
        //    else if(radbuttondetails.Checked == true)
        //    { 
        //        gridControl2.BeginUpdate();
        //        gridView2.GroupSummary.Clear();
        //        gridView2.Columns.Clear();
        //        if (Login.assignedBranch != "888")
        //        {
        //            Database.display("SELECT * FROM view_detailTransactionHistory " +
        //             "WHERE BranchCode='" + Login.assignedBranch + "' " +
        //             "AND CAST(DateOrder as date) >= '" + datefromsalessum.Text + "' AND CAST(DateOrder as date) <= '" + datetosalessum.Text + "' ORDER BY ReferenceNo", gridControl2, gridView2);
        //        }
        //        else
        //        {
        //            Database.display("SELECT * FROM view_detailTransactionHistory " +
        //         $"WHERE BranchCode='{brcodedetails.ToString()}' " +
        //         "AND CAST(DateOrder as date) >= '" + datefromsalessum.Text + "' AND CAST(DateOrder as date) <= '" + datetosalessum.Text + "' ORDER BY ReferenceNo", gridControl2, gridView2);
        //        }
        //        Classes.DevXGridViewSettings.ShowFooterCountTotal(gridView2, "BranchCode");
        //        Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "QtySold");
        //        Classes.DevXGridViewSettings.ShowFooterTotal(gridView2, "TotalAmount");
        //        gridControl2.EndUpdate();
        //    }

        //}


        private void POSSalesReportDevEx_Load(object sender, EventArgs e)
        {
            if(!Convert.ToBoolean(Login.isglobalAdmin))
            {
                chckboxAllBranch.Visible = false;
            }
            xtraTabPage1.PageVisible = false;
            DateTime now = DateTime.Now;
            DateTime date = new DateTime(now.Year, now.Month, 1);

            var now2 = DateTime.Now;
            //var startOfMonth = new DateTime(now2.Year, now2.Month, 1);
            var DaysInMonth = DateTime.DaysInMonth(now2.Year, now2.Month);
            var lastDay = new DateTime(now2.Year, now2.Month, DaysInMonth);


            datefromsalessum.Text = date.ToShortDateString();
            datetosalessum.Text = lastDay.ToShortDateString();

            // Sets the initial visibility explicitly rather than relying on the Designer's
            // default (radcashreceipts.Checked = true) matching it by coincidence.
            radReportType_CheckedChanged(this, EventArgs.Empty);

            populate();
        }

        // The Invoice Date/Payment Date filter-type choice only means anything for Cash
        // Receipts (funcview_CustomerCashReceipts) -- Sales Journal (funcview_CustomerSalesJournal)
        // doesn't take that parameter, so hide it rather than leave a control that does nothing.
        private void radReportType_CheckedChanged(object sender, EventArgs e)
        {
            labelDateFilterType.Visible = radcashreceipts.Checked;
            panelDateFilterType.Visible = radcashreceipts.Checked;
        }

        void populate()
        {
            if(Login.assignedBranch != "888")
            {
                txtbranchsummary.Visible = false;
               
            }
            else
            {
                Database.displaySearchlookupEdit("Select distinct BranchCode,BranchName FROM Branches Order By BranchCode", txtbranchsummary, "BranchName", "BranchName");
             }
            Database.displaySearchlookupEdit("SELECT CustomerKey,CustomerID,CustomerName From dbo.Customers", searchLookUpEdit1,"CustomerName", "CustomerName");
        }

        private void searchLookUpEdit1_EditValueChanged(object sender, EventArgs e)
        {
            custkey = SearchLookUpClass.getSingleValue(searchLookUpEdit1, "CustomerKey");
        }

        private void btnTransactionPayment_Click(object sender, EventArgs e)
        {
            var rowz = Database.getMultipleQuery("SELECT * FROM dbo.Customers WHERE CustomerKey='" + custkey.ToString() + "'", "CustomerKey,CustomerID ,CustomerName,CustomerEmail,CustomerContactNo,CustomerAddress,CustomerBirthDate,CustomerCreditLimit,BranchCode,Term,isActive,DateAdded,AddedBy,UpdatedBy,AccountOfficer,TinNo");
            string CustomerKey = rowz["CustomerKey"].ToString();
            string CustomerID = rowz["CustomerID"].ToString();
            string CustomerName = rowz["CustomerName"].ToString();
            string CustomerEmail = rowz["CustomerEmail"].ToString();
            string CustomerContactNo = rowz["CustomerContactNo"].ToString();
            string CustomerAddress = rowz["CustomerAddress"].ToString();
            string CustomerBirthDate = rowz["CustomerBirthDate"].ToString();
            string CustomerCreditLimit = rowz["CustomerCreditLimit"].ToString();
            string BranchCode = rowz["BranchCode"].ToString();
            string Term = rowz["Term"].ToString();
            string isActive = rowz["isActive"].ToString();
            string DateAdded = rowz["DateAdded"].ToString();
            string AddedBy = rowz["AddedBy"].ToString();
            string UpdatedBy = rowz["UpdatedBy"].ToString();
            string AccountOfficer = rowz["AccountOfficer"].ToString();
            string TinNo = rowz["TinNo"].ToString();
            txtid.Text = CustomerKey;
            txtname.Text = CustomerName;
            txtcontactno.Text = CustomerContactNo;
            txtaddress.Text = CustomerAddress;
            getData();
        }

        void getData()
        {
            var rowz = Database.getMultipleQuery($"SELECT * FROM func_CustomerSalesBoard('{custkey.ToString()}','{Environment.MachineName}') ", "TotalInvoice,SubTotal,TotalAmount,Average");
            string TotalInvoice = rowz["TotalInvoice"].ToString();
            string SubTotal = rowz["SubTotal"].ToString();
            string TotalAmount = rowz["TotalAmount"].ToString();
            string Average = rowz["Average"].ToString();
            txtavg.Text = Average;
            txttotinvoice.Text = TotalInvoice;
            txttotasalesb4tax.Text = SubTotal;
            txttotsalesnet.Text = TotalAmount;
            Database.display("SELECT a.DateOrder,a.ReferenceNo,a.Category,a.Description,a.QtySold,a.TotalAmount " +
                "FROM dbo.view_detailTransactionHistory a with(nolock) LEFT OUTER JOIN BatchSalesSummary b with(nolock) " +
                "ON a.ReferenceNo=b.ReferenceNo WHERE b.CustomerNo='" + custkey.ToString() + "' ORDER BY ReferenceNo DESC", gridControl3, gridView3);
        }

        private void txtbranchsummary_EditValueChanged(object sender, EventArgs e)
        {
            brcodesummary = SearchLookUpClass.getSingleValue(txtbranchsummary, "BranchCode");
        }

        

        private void btnforapprovalstsexcel_Click(object sender, EventArgs e)
        {
            string filename = "HRI_SalesTransactionSummary" + DateTime.Now.ToString("yyyyMMdd_HHmmss");
            HelperFunction.exporttoexcel(gridView2, filename);
        }

        private void simpleButton2_Click(object sender, EventArgs e)
        {
            if(radcashreceipts.Checked==true)
            {
                populateCashReceiptsBook();
            }
            else if(radsalesjournal.Checked==true)
            {
                populateSalesJournal();
            }
        }

        void populateCashReceiptsBook()
        {
            try
            {
                gridView1.BeginDataUpdate();

               
                gridView1.Columns.Clear();
                LoadCustomerCashReceipts();
                
                gridView1.BestFitColumns();
                gridView1.ExpandAllGroups();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(
                    ex.Message,
                    "Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            finally
            {
                gridView1.EndDataUpdate();
            }
        }
        void populateSalesJournal()
        {
            try
            {
                gridView1.BeginDataUpdate();


                gridView1.Columns.Clear();
                LoadCustomerSalesJournal();

                gridView1.BestFitColumns();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(
                    ex.Message,
                    "Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            finally
            {
                gridView1.EndDataUpdate();
            }
        }

        private void label15_Click(object sender, EventArgs e)
        {
            
        }
    }
}