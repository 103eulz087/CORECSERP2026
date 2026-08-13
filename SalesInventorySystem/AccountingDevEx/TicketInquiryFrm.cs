using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;

namespace SalesInventorySystem.AccountingDevEx
{
    /// <summary>
    /// Standalone "what does this ticket actually look like" lookup —
    /// search by Ticket Number or Reference Number, see the full
    /// compound entry across every branch it touched. Complements
    /// (doesn't replace) branch-scoped reports like GL Detail
    /// Transaction — this is purely a ticket-centric view, reusing
    /// sp_GetTicketDetailsByTicketNumber built for that report's
    /// drill-down.
    /// </summary>
    public partial class TicketInquiryFrm : DevExpress.XtraEditors.XtraUserControl
    {
        private bool _dataLoaded = false;

        public TicketInquiryFrm()
        {
            InitializeComponent();
        }

        public void LoadData()
        {
            if (_dataLoaded) return;
            _dataLoaded = true;
            HelperFunction.SetDefaultDateRange(txtDateFrom,txtDateTo); 
            InitializeForm();
        }

        private void TicketInquiryFrm_Load(object sender, EventArgs e)
        {
            // Safety net — LoadData() is the real trigger if this is
            // hosted inside another control; both guarded, whichever
            // fires first wins.
            if (_dataLoaded) return;
            _dataLoaded = true;
            InitializeForm();
        }

        private void InitializeForm()
        {
            
            //txtDateFrom.EditValue = null;
            //txtDateTo.EditValue = null;
            lblTicketHeader.Text = "Search above and select a ticket to see its detail.";
            gridControlDetails.DataSource = null;
        }

        private void TxtSearchTerm_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
            {
                e.Handled = true;
                RunSearch();
            }
        }

        private void BtnSearch_Click(object sender, EventArgs e) => RunSearch();

        private void RunSearch()
        {
            string term = txtSearchTerm.Text.Trim();
            //if (string.IsNullOrEmpty(term))
            //{
            //    XtraMessageBox.Show("Enter a Ticket Number or Reference Number to search.", "Search",
            //        MessageBoxButtons.OK, MessageBoxIcon.Information);
            //    return;
            //}

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_SearchTickets", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@SearchTerm", SqlDbType.VarChar, 150).Value = term;
                    cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value =
                        txtDateFrom.EditValue == null ? (object)DBNull.Value : txtDateFrom.DateTime;
                    cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value =
                        txtDateTo.EditValue == null ? (object)DBNull.Value : txtDateTo.DateTime;

                    var dt = new DataTable();
                    con.Open();
                    new SqlDataAdapter(cmd).Fill(dt);
                    gridControlResults.DataSource = dt;
                }

                gridViewResults.BestFitColumns();
                gridControlDetails.DataSource = null;
                lblTicketHeader.Text = gridViewResults.RowCount == 0
                    ? "No matching tickets found."
                    : "Select a ticket below to see its detail.";
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Search failed: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void BtnViewDetails_Click(object sender, EventArgs e)
        {
            if (gridViewResults.FocusedRowHandle < 0)
            {
                XtraMessageBox.Show("Select a ticket first.", "View Details", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            LoadTicketDetail();
        }

        private void GridViewResults_DoubleClick(object sender, EventArgs e)
        {
            if (gridViewResults.FocusedRowHandle < 0) return;
            LoadTicketDetail();
        }

        private void LoadTicketDetail()
        {
            string ticketNumber = gridViewResults.GetFocusedRowCellValue("TicketNumber")?.ToString();
            if (string.IsNullOrWhiteSpace(ticketNumber)) return;

            DataTable header, lines;
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_GetTicketDetailsByTicketNumber", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@TicketNumber", SqlDbType.VarChar, 20).Value = ticketNumber;

                    con.Open();
                    using (var da = new SqlDataAdapter(cmd))
                    {
                        var ds = new DataSet();
                        da.Fill(ds);
                        header = ds.Tables.Count > 0 ? ds.Tables[0] : new DataTable();
                        lines = ds.Tables.Count > 1 ? ds.Tables[1] : new DataTable();
                    }
                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load ticket detail: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            if (header.Rows.Count > 0)
            {
                var h = header.Rows[0];
                int branchCount = Convert.ToInt32(gridViewResults.GetFocusedRowCellValue("BranchCount") ?? 1);
                string branches = gridViewResults.GetFocusedRowCellValue("Branches")?.ToString() ?? h["BranchCode"]?.ToString();

                lblTicketHeader.Text =
                    $"Ticket {h["TicketNumber"]}   |   Reference No.: {h["ReferenceNumber"]}   |   Date: {Convert.ToDateTime(h["TicketDate"]):yyyy-MM-dd}   |   " +
                    $"Origin/Mnemonic: {h["Origin"]}/{h["Mnemonic"]}   |   {branchCount} branch(es): {branches}\n" +
                    $"Remarks: {h["Remarks"]}";
            }
            else
            {
                lblTicketHeader.Text = $"Ticket {ticketNumber} — header not found, showing legs only.";
            }

            gridControlDetails.DataSource = lines;
            gridViewDetails.BestFitColumns();
            gridViewDetails.ExpandAllGroups();
        }
    }
}