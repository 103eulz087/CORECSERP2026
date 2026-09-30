using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;

namespace SalesInventorySystem.AccountingDevEx
{
    // GL month-end closing (2026-09-30, SQL/2026-09-30_GL_PeriodLock.sql).
    // Company-wide: one "books closed through" date for every branch. Months
    // are closed in order (spu_GLPeriod_Close); only the LAST closed month can
    // be reopened, with a reason (spu_GLPeriod_Reopen). Once a month is
    // closed, triggers on TicketDetails/TicketMaster refuse any GL entry dated
    // in it, so every posting module is covered without changes.
    // Opened from Main > Accounting Settings > GL Period Closing (global
    // admins only); the buttons are also disabled here for non-admins.
    public partial class GLPeriodClosingFrm : XtraForm
    {
        private bool _dataLoaded = false;
        private DateTime? _locked;
        private DateTime? _next;
        private bool _canCloseNext;

        public GLPeriodClosingFrm()
        {
            InitializeComponent();
        }

        private static bool IsAdmin()
        {
            bool isAdmin;
            return bool.TryParse(Login.isglobalAdmin, out isAdmin) && isAdmin;
        }

        public void LoadData()
        {
            if (_dataLoaded) return;
            _dataLoaded = true;
            RefreshStatus();
        }

        private void GLPeriodClosingFrm_Load(object sender, EventArgs e)
        {
            // Guarded fallback only (Known Bug Pattern #1).
            if (!_dataLoaded) LoadData();
        }

        private void RefreshStatus()
        {
            var ds = new DataSet();
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("dbo.sp_GLPeriod_Status", con) { CommandType = CommandType.StoredProcedure })
                using (var da = new SqlDataAdapter(cmd))
                    da.Fill(ds);
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message, "GL Period Closing", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            DataRow s = ds.Tables[0].Rows[0];
            _locked = s["LockedThroughDate"] == DBNull.Value ? (DateTime?)null : Convert.ToDateTime(s["LockedThroughDate"]);
            _next = s["NextPeriodToClose"] == DBNull.Value ? (DateTime?)null : Convert.ToDateTime(s["NextPeriodToClose"]);
            _canCloseNext = Convert.ToBoolean(s["CanCloseNext"]);

            lblLocked.Text = _locked.HasValue
                ? $"Books closed through: {_locked.Value:MMMM dd, yyyy}"
                : "Books closed through: (no month closed yet)";
            lblNext.Text = _next.HasValue
                ? $"Next month to close: {_next.Value:MMMM yyyy}   ·   {Convert.ToInt32(s["NextPeriodLines"]):N0} GL lines, " +
                  $"debits {Convert.ToDecimal(s["NextPeriodDebits"]):N2}, credits {Convert.ToDecimal(s["NextPeriodCredits"]):N2}" +
                  (_canCloseNext ? "" : "   (month not finished yet)")
                : "Next month to close: -";

            bool admin = IsAdmin();
            btnClosePeriod.Text = _next.HasValue ? $"Close {_next.Value:MMMM yyyy}" : "Close Month";
            btnClosePeriod.Enabled = admin && _next.HasValue && _canCloseNext;
            btnReopenPeriod.Text = _locked.HasValue ? $"Reopen {_locked.Value:MMMM yyyy}" : "Reopen Last Closed Month";
            btnReopenPeriod.Enabled = admin && _locked.HasValue;

            gridLog.DataSource = ds.Tables[1];
            foreach (string col in new[] { "PeriodEnd", "PreviousLockedThrough", "NewLockedThrough" })
                if (gridViewLog.Columns[col] != null)
                {
                    gridViewLog.Columns[col].DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                    gridViewLog.Columns[col].DisplayFormat.FormatString = "MM/dd/yyyy";
                }
            if (gridViewLog.Columns["ActionAt"] != null)
            {
                gridViewLog.Columns["ActionAt"].DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                gridViewLog.Columns["ActionAt"].DisplayFormat.FormatString = "MM/dd/yyyy hh:mm tt";
            }
            if (gridViewLog.Columns["LogID"] != null) gridViewLog.Columns["LogID"].Visible = false;
            gridViewLog.BestFitColumns();
        }

        private void btnRefresh_Click(object sender, EventArgs e)
        {
            RefreshStatus();
        }

        private void btnClosePeriod_Click(object sender, EventArgs e)
        {
            if (!IsAdmin() || !_next.HasValue) return;

            if (XtraMessageBox.Show(
                    $"Close {_next.Value:MMMM yyyy}?\n\nAfter closing, no GL entry dated on or before {_next.Value:MMMM dd, yyyy} " +
                    "can be added, changed or deleted in any module, for any branch. Corrections go into an open month.",
                    "Close Month", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes)
                return;

            RunLockProc("dbo.spu_GLPeriod_Close", cmd =>
            {
                cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = _next.Value.Date;
                cmd.Parameters.Add("@User", SqlDbType.VarChar, 60).Value = Login.Fullname ?? "";
                cmd.Parameters.Add("@Reason", SqlDbType.VarChar, 500).Value =
                    string.IsNullOrWhiteSpace(txtReason.Text) ? (object)DBNull.Value : txtReason.Text.Trim();
            });
        }

        private void btnReopenPeriod_Click(object sender, EventArgs e)
        {
            if (!IsAdmin() || !_locked.HasValue) return;

            if (string.IsNullOrWhiteSpace(txtReason.Text))
            {
                XtraMessageBox.Show("Enter the reason for reopening first.", "Reopen Month", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                txtReason.Focus();
                return;
            }

            if (XtraMessageBox.Show(
                    $"Reopen {_locked.Value:MMMM yyyy}?\n\nGL entries dated in that month can be added, changed or deleted again until it is closed again.",
                    "Reopen Month", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes)
                return;

            RunLockProc("dbo.spu_GLPeriod_Reopen", cmd =>
            {
                cmd.Parameters.Add("@User", SqlDbType.VarChar, 60).Value = Login.Fullname ?? "";
                cmd.Parameters.Add("@Reason", SqlDbType.VarChar, 500).Value = txtReason.Text.Trim();
            });
        }

        private void RunLockProc(string procName, Action<SqlCommand> addParams)
        {
            try
            {
                string message = null;
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand(procName, con) { CommandType = CommandType.StoredProcedure })
                {
                    addParams(cmd);
                    con.Open();
                    using (var rdr = cmd.ExecuteReader())
                        if (rdr.Read()) message = Convert.ToString(rdr["Message"]);
                }
                txtReason.Text = "";
                XtraMessageBox.Show(message ?? "Done.", "GL Period Closing", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message, "GL Period Closing", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            RefreshStatus();
        }
    }
}
