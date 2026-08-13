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
using SalesInventorySystem.Classes;

namespace SalesInventorySystem.Reporting
{
    public partial class ViewTicketDevExRep : DevExpress.XtraEditors.XtraUserControl //,IResettableForm
    {
        public ViewTicketDevExRep()
        {
            InitializeComponent();
        }
        private bool _dataLoaded = false;

        public void LoadData()
        {
            if (_dataLoaded)
                return;


            txtdateto.EditValue = DateTime.Today;
            txtdatefrom.EditValue = ((DateTime)txtdateto.EditValue).AddMonths(-1);

            loadBranch();

            _dataLoaded = true;
        }
        // 2. IMPLEMENT THE INTERFACE METHOD
        //public async Task ResetUIAsync()
        //{
        //    try
        //    {
        //        UseWaitCursor = true;

        //        // Reset Dates to default (1 month range up to today)
        //        txtdateto.EditValue = DateTime.Today;
        //        txtdatefrom.EditValue = DateTime.Today.AddMonths(-1);

        //        // Clear Dropdowns and Checkboxes
        //        txtbrcode.EditValue = null;
        //        chckboxAllBranch.Checked = false;

        //        // Clear the Grid completely
        //        gridControlTicketSummary.DataSource = null;

        //        // We include this to satisfy the "Task" return type of the interface, 
        //        // even though this specific form has no database calls during a reset.
        //        await Task.CompletedTask;
        //    }
        //    catch (Exception ex)
        //    {
        //        XtraMessageBox.Show($"Error resetting form: {ex.Message}", "Warning", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        //    }
        //    finally
        //    {
        //        UseWaitCursor = false;
        //    }
        //}
        private void ViewTicketDevExRep_Load(object sender, EventArgs e)
        {
        }

        void loadBranch()
        {
            Database.displaySearchlookupEdit("Select BranchCode,BranchName FROM Branches Order By BranchCode", txtbrcode, "BranchCode", "BranchCode");
        }

        private void simpleButton1_Click(object sender, EventArgs e)
        {
            //Database.GridMasterDetail("SELECT TicketDate,TicketNumber,ReferenceNumber,ReferenceKey,Owner,Particulars,EnteredBy FROM TicketMaster WHERE TicketDate between '" + txtdatefrom.Text + "' and '" + txtdateto.Text + "' and BranchCode='" + txtbrcode.Text + "'", "SELECT TicketDate,TicketNumber,ReferenceNumber,ReferenceKey,AccountCode,Description,Debit,Credit FROM view_TicketDetails WHERE TicketDate between '" + txtdatefrom.Text + "' and '" + txtdateto.Text + "' and BranchCode='" + txtbrcode.Text + "'", "TicketMaster", "TicketDetails", "TicketNumber", "TicketDate", "TicketNumber", "TicketDate", "TicketDetails", gridControlTicketSummary, gridView3,"");
            display();
        }


        void display()
        {
            DateTime dateFrom = txtdatefrom.EditValue == null
                ? DateTime.MinValue
                : (DateTime)txtdatefrom.EditValue;

            DateTime dateTo = txtdateto.EditValue == null
                ? DateTime.MaxValue
                : ((DateTime)txtdateto.EditValue).AddDays(1);

            bool allBranches = chckboxAllBranch.Checked;

                        string masterQuery = @"
                    SELECT *
                    FROM [viewTicketMaster]
                        WHERE TicketDate >= @DateFrom
                        AND TicketDate < @DateTo ";

                        string detailQuery = @"
                    SELECT d.*
                    FROM view_AccountingTicketReports d
                    WHERE EXISTS
                    (
                        SELECT 1
                        FROM [viewTicketMaster] s
                        WHERE s.TicketNumber = d.TicketNumber
                          AND s.TicketDate >= @DateFrom
                          AND s.TicketDate < @DateTo
                    ) ";

                        // Add branch filter only if not all branches
                        if (!allBranches)
                        {
                            masterQuery += " AND BranchCode = @Branch";
                            //detailQuery += " AND s.BranchCode = @Branch";
                        }
                       masterQuery += " ORDER BY TicketNumber DESC";

                        //detailQuery += ")"; // close EXISTS

                        var masterParams = new List<SqlParameter>
                        {
                            new SqlParameter("@DateFrom", dateFrom),
                            new SqlParameter("@DateTo", dateTo)
                        };

                        var detailParams = new List<SqlParameter>
                        {
                            new SqlParameter("@DateFrom", dateFrom),
                            new SqlParameter("@DateTo", dateTo)
                        };

                        if (!allBranches)
                        {
                            masterParams.Add(new SqlParameter("@Branch", txtbrcode.Text));
                            detailParams.Add(new SqlParameter("@Branch", txtbrcode.Text));
                        }

                        Database.GridMasterDetail(
                            masterQuery,
                            detailQuery,
                            "Master",
                            "Detail",
                            "TicketNumber",
                            "TicketNumber",
                            "TicketDetails",
                            gridControlTicketSummary,
                            masterParams.ToArray(),
                            detailParams.ToArray()
                        );

            gridViewTicketSummary.OptionsView.ColumnAutoWidth = false;
            gridViewTicketSummary.BestFitColumns();

        }


        private void gridViewTicketSummary_MasterRowGetLevelDefaultView(object sender, DevExpress.XtraGrid.Views.Grid.MasterRowGetLevelDefaultViewEventArgs e)
        {
            //e.DefaultView = new GridView(gridControlTicketSummary);
        }

        private void gridControlTicketSummary_ViewRegistered(object sender, DevExpress.XtraGrid.ViewOperationEventArgs e)
        {
            GridView view = e.View as GridView;
            if (view == null) return;

            // ✅ Apply to ALL views (master + detail)
            view.OptionsView.ColumnAutoWidth = false;
            view.OptionsView.RowAutoHeight = true;
            view.OptionsBehavior.ReadOnly = true;
            view.OptionsBehavior.Editable = false;

            view.PopulateColumns();
            view.BestFitColumns();
        }

        private void gridViewTicketSummary_MasterRowExpanded(object sender, CustomMasterRowEventArgs e)
        {
            GridView masterView = sender as GridView;

            // ✅ Get actual detail view
            GridView detailView = masterView.GetDetailView(e.RowHandle, e.RelationIndex) as GridView;

            if (detailView != null)
            {
                detailView.OptionsView.ColumnAutoWidth = false;
                detailView.PopulateColumns();

                // ✅ SHOW FOOTER
                detailView.OptionsView.ShowFooter = true;

                // ✅ Footer styling
                detailView.Appearance.FooterPanel.BackColor = Color.LightYellow;
                detailView.Appearance.FooterPanel.ForeColor = Color.Black;
                detailView.Appearance.FooterPanel.Font = new Font("Segoe UI", 9, FontStyle.Bold);

                // ✅ ADD SUM FOR DEBIT
                if (detailView.Columns["Debit"] != null)
                {
                    detailView.Columns["Debit"].Summary.Clear();
                    detailView.Columns["Debit"].Summary.Add(
                        DevExpress.Data.SummaryItemType.Sum,
                        "Debit",
                        "Total: {0:n2}"
                    );
                }

                // ✅ ADD SUM FOR CREDIT
                if (detailView.Columns["Credit"] != null)
                {
                    detailView.Columns["Credit"].Summary.Clear();
                    detailView.Columns["Credit"].Summary.Add(
                        DevExpress.Data.SummaryItemType.Sum,
                        "Credit",
                        "Total: {0:n2}"
                    ); 
                }

                detailView.BestFitColumns();

                // ✅ HIDE COLUMNS
                detailView.Columns["BranchCode"].Visible = false;
                detailView.Columns["TicketDate"].Visible = false;
                detailView.Columns["TicketNumber"].Visible = false;
                detailView.Columns["ReferenceNumber"].Visible = false;
                detailView.Columns["ReferenceKey"].Visible = false;

                // ✅ MIN WIDTH FOR DETAIL
                foreach (DevExpress.XtraGrid.Columns.GridColumn col in detailView.Columns)
                {
                    col.MinWidth = 100;
                }
            }

            // ✅ MIN WIDTH FOR MASTER
            foreach (DevExpress.XtraGrid.Columns.GridColumn col in gridViewTicketSummary.Columns)
            {
                col.MinWidth = 100;
            }

            masterView.BestFitColumns();
        }

        private void chckboxAllBranch_CheckedChanged(object sender, EventArgs e)
        {

        }
    }
}