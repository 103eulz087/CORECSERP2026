using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraEditors.Controls;
using SalesInventorySystem.Classes;

namespace SalesInventorySystem.AccountingDevEx
{
    /// <summary>
    /// Chart of Accounts maintenance — add/edit ChartOfAccounts rows via
    /// spu_UpsertChartOfAccount (parameterized), replacing the legacy
    /// Accounting/COA.cs form, which built its INSERT/UPDATE via raw
    /// string-concatenated textbox values. AccountCode is immutable once
    /// a row exists (it's the key TicketDetails/JournalEntryMapping/every
    /// lookup elsewhere references) — the grid lets you browse and pick a
    /// row to edit, but Account Code locks as soon as an existing row is
    /// loaded; only Add uses an editable Account Code field.
    /// Delete is guarded server-side (spu_DeleteChartOfAccount) against
    /// posted GL activity, hierarchy references, and JournalEntryMapping
    /// — see that procedure's header comment for exactly what is (and
    /// isn't) checked.
    /// </summary>
    public partial class ChartOfAccountsDevEx : DevExpress.XtraEditors.XtraForm
    {
        public ChartOfAccountsDevEx()
        {
            InitializeComponent();
        }

        private void ChartOfAccountsDevEx_Load(object sender, EventArgs e)
        {
            try
            {
                PopulateLookups();
                LoadGrid();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show($"Could not load Chart of Accounts: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }

            SetBrowseMode();
        }

        // ── Data access ─────────────────────────────────────────
        // Only ever called with hardcoded literal SQL below (no user
        // input concatenated in) — mutations go through the
        // parameterized stored procedure calls in btnSave_Click/
        // btnDelete_Click instead.
        private DataTable GetDataTable(string sql)
        {
            var dt = new DataTable();
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand(sql, con))
            {
                con.Open();
                new SqlDataAdapter(cmd).Fill(dt);
            }
            return dt;
        }

        private DataTable GetDataTableFromSp(string spName)
        {
            var dt = new DataTable();
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand(spName, con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                con.Open();
                new SqlDataAdapter(cmd).Fill(dt);
            }
            return dt;
        }

        private static readonly (string Field, string Caption)[] GridCaptions =
        {
            ("AccountCode", "Account Code"),
            ("Description", "Description"),
            ("AccountType", "Type"),
            ("LevelNumber", "Level"),
            ("SummaryAccount", "Summary Account"),
            ("SummaryAccountDescription", "Summary Account Name"),
            ("GLSL", "GLSL"),
            ("BranchCode", "Branch"),
            ("BranchName", "Branch Name"),
            ("YearEndIndicator", "Year-End"),
            ("Nature", "Nature"),
            ("DueToFromIndicator", "Due To/From"),
        };

        private void LoadGrid()
        {
            // Columns are auto-generated from the DataTable (no
            // explicit GridColumns in the Designer) — DevExpress'
            // default captions are derived straight from the SP's raw
            // column names, so relabel them here rather than relying
            // on that to look right.
            gridControlAccounts.DataSource = GetDataTableFromSp("sp_GetChartOfAccountsList");
            foreach (var (field, caption) in GridCaptions)
            {
                var col = gridViewAccounts.Columns[field];
                if (col != null) col.Caption = caption;
            }
            gridViewAccounts.BestFitColumns();
        }

        // Code-Name convention (per project convention) for every
        // lookup/combo on this form — DisableTextEditor so free text
        // can't bypass the ValueMember (see Known Bug Pattern: Grid
        // LookUpEdit columns need TextEditStyle = DisableTextEditor).
        private void PopulateLookups()
        {
            SetupCodeLookup(lueAccountType, BuildCodeTable(
                ("D", "D - Detail (Postable)"),
                ("S", "S - Summary (Header)")));

            SetupCodeLookup(lueGLSL, BuildCodeTable(
                ("G", "G - General Ledger"),
                ("S", "S - Sub-Ledger")));

            SetupCodeLookup(lueNature, BuildCodeTable(
                ("D", "D - Debit-normal"),
                ("C", "C - Credit-normal")));

            SetupCodeLookup(lueYearEndIndicator, BuildCodeTable(
                ("BS", "BS - Balance Sheet"),
                ("IS", "IS - Income Statement")));

            SetupCodeLookup(lueDueToFromIndicator, BuildCodeTable(
                ("", "(none)"),
                ("DFR", "DFR - Due From (reserved)"),
                ("DTO", "DTO - Due To (reserved)")));

            SetupCodeLookup(lueSummaryAccount, GetDataTable(
                "SELECT AccountCode, AccountCode + ' - ' + ISNULL(Description,'') AS Display FROM ChartOfAccounts ORDER BY AccountCode"),
                "AccountCode", "Display");

            SetupCodeLookup(lueBranchCode, GetDataTable(
                "SELECT BranchCode, BranchCode + ' - ' + BranchName AS Display FROM Branches ORDER BY BranchCode"),
                "BranchCode", "Display");
        }

        private DataTable BuildCodeTable(params (string Code, string Display)[] rows)
        {
            var dt = new DataTable();
            dt.Columns.Add("Code", typeof(string));
            dt.Columns.Add("Display", typeof(string));
            foreach (var row in rows) dt.Rows.Add(row.Code, row.Display);
            return dt;
        }

        private void SetupCodeLookup(LookUpEdit edit, DataTable source, string valueMember = "Code", string displayMember = "Display")
        {
            edit.Properties.DataSource = source;
            edit.Properties.ValueMember = valueMember;
            edit.Properties.DisplayMember = displayMember;
            edit.Properties.PopulateColumns();
            // PopulateColumns() adds a popup grid column per source column,
            // including the raw code — ShowHeader=false only hides the
            // header row, not the column itself, so without this the
            // popup shows both "D" and "D - Detail (Postable)" side by
            // side. Only the Display column should be visible.
            if (edit.Properties.Columns[valueMember] != null)
                edit.Properties.Columns[valueMember].Visible = false;
            edit.Properties.ShowHeader = false;
            edit.Properties.NullText = "";
            edit.Properties.TextEditStyle = TextEditStyles.DisableTextEditor;
        }

        // ── Grid selection → edit panel ─────────────────────────
        private void gridViewAccounts_FocusedRowChanged(object sender, DevExpress.XtraGrid.Views.Base.FocusedRowChangedEventArgs e)
        {
            if (e.FocusedRowHandle < 0) return;
            LoadRowIntoForm(e.FocusedRowHandle);
        }

        private void LoadRowIntoForm(int rowHandle)
        {
            txtAccountCode.EditValue = gridViewAccounts.GetRowCellValue(rowHandle, "AccountCode");
            txtDescription.EditValue = gridViewAccounts.GetRowCellValue(rowHandle, "Description");
            lueAccountType.EditValue = gridViewAccounts.GetRowCellValue(rowHandle, "AccountType");
            spinLevelNumber.EditValue = gridViewAccounts.GetRowCellValue(rowHandle, "LevelNumber");
            lueSummaryAccount.EditValue = gridViewAccounts.GetRowCellValue(rowHandle, "SummaryAccount");
            lueGLSL.EditValue = gridViewAccounts.GetRowCellValue(rowHandle, "GLSL");
            lueBranchCode.EditValue = gridViewAccounts.GetRowCellValue(rowHandle, "BranchCode");
            lueYearEndIndicator.EditValue = gridViewAccounts.GetRowCellValue(rowHandle, "YearEndIndicator");
            lueNature.EditValue = gridViewAccounts.GetRowCellValue(rowHandle, "Nature");
            lueDueToFromIndicator.EditValue = gridViewAccounts.GetRowCellValue(rowHandle, "DueToFromIndicator");

            SetEditMode();
        }

        // ── Form modes ───────────────────────────────────────────
        private void SetBrowseMode()
        {
            ClearForm();
            groupControlEdit.Enabled = false;
            btnSave.Enabled = false;
            btnDelete.Enabled = false;
        }

        private void SetNewMode()
        {
            ClearForm();
            groupControlEdit.Enabled = true;
            txtAccountCode.Properties.ReadOnly = false;
            btnSave.Enabled = true;
            btnDelete.Enabled = false;
            txtAccountCode.Focus();
        }

        private void SetEditMode()
        {
            groupControlEdit.Enabled = true;
            txtAccountCode.Properties.ReadOnly = true; // immutable once it exists
            btnSave.Enabled = true;
            btnDelete.Enabled = true;
        }

        private void ClearForm()
        {
            txtAccountCode.EditValue = null;
            txtDescription.EditValue = null;
            lueAccountType.EditValue = null;
            spinLevelNumber.EditValue = null;
            lueSummaryAccount.EditValue = null;
            lueGLSL.EditValue = null;
            lueBranchCode.EditValue = null;
            lueYearEndIndicator.EditValue = null;
            lueNature.EditValue = null;
            lueDueToFromIndicator.EditValue = null;
        }

        // ── Buttons ──────────────────────────────────────────────
        private void btnNew_Click(object sender, EventArgs e) => SetNewMode();

        private void btnRefresh_Click(object sender, EventArgs e)
        {
            LoadGrid();
            SetBrowseMode();
        }

        private void btnSave_Click(object sender, EventArgs e)
        {
            if (!ValidateForm()) return;

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("spu_UpsertChartOfAccount", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@AccountCode", SqlDbType.VarChar, 50).Value = txtAccountCode.Text.Trim();
                    cmd.Parameters.Add("@Description", SqlDbType.VarChar, 256).Value = ToDbValue(txtDescription.Text);
                    cmd.Parameters.Add("@AccountType", SqlDbType.VarChar, 1).Value = ToDbValue(lueAccountType.EditValue);
                    cmd.Parameters.Add("@LevelNumber", SqlDbType.SmallInt).Value =
                        spinLevelNumber.EditValue == null ? (object)DBNull.Value : Convert.ToInt16(spinLevelNumber.Value);
                    cmd.Parameters.Add("@SummaryAccount", SqlDbType.VarChar, 20).Value = ToDbValue(lueSummaryAccount.EditValue);
                    cmd.Parameters.Add("@GLSL", SqlDbType.Char, 1).Value = ToDbValue(lueGLSL.EditValue);
                    cmd.Parameters.Add("@BranchCode", SqlDbType.Char, 5).Value = ToDbValue(lueBranchCode.EditValue);
                    cmd.Parameters.Add("@YearEndIndicator", SqlDbType.Char, 2).Value = ToDbValue(lueYearEndIndicator.EditValue);
                    cmd.Parameters.Add("@Nature", SqlDbType.Char, 1).Value = ToDbValue(lueNature.EditValue);
                    cmd.Parameters.Add("@DueToFromIndicator", SqlDbType.VarChar, 50).Value = ToDbValue(lueDueToFromIndicator.EditValue);
                    var isNewParam = cmd.Parameters.Add("@IsNew", SqlDbType.Bit);
                    isNewParam.Direction = ParameterDirection.Output;

                    con.Open();
                    cmd.ExecuteNonQuery();

                    bool wasNew = isNewParam.Value != DBNull.Value && (bool)isNewParam.Value;
                    XtraMessageBox.Show(wasNew ? "Account added." : "Account updated.", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }

                LoadGrid();
                SetBrowseMode();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void btnDelete_Click(object sender, EventArgs e)
        {
            string code = txtAccountCode.Text.Trim();
            if (string.IsNullOrEmpty(code)) return;

            if (XtraMessageBox.Show($"Delete account '{code}'? This cannot be undone.", "Confirm Delete", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes)
                return;

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("spu_DeleteChartOfAccount", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@AccountCode", SqlDbType.VarChar, 50).Value = code;
                    con.Open();
                    cmd.ExecuteNonQuery();
                }

                XtraMessageBox.Show("Account deleted.", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                LoadGrid();
                SetBrowseMode();
            }
            catch (SqlException ex)
            {
                // spu_DeleteChartOfAccount THROWs a specific, readable
                // reason for every guard it enforces (posted GL activity,
                // hierarchy reference, JournalEntryMapping reference) —
                // surface it as-is rather than a generic failure message.
                XtraMessageBox.Show(ex.Message, "Cannot Delete", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private bool ValidateForm()
        {
            if (string.IsNullOrWhiteSpace(txtAccountCode.Text))
            {
                XtraMessageBox.Show("Account Code is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                txtAccountCode.Focus();
                return false;
            }
            return true;
        }

        private object ToDbValue(object editValue)
        {
            if (editValue == null || editValue == DBNull.Value) return DBNull.Value;
            string s = editValue.ToString();
            return string.IsNullOrWhiteSpace(s) ? (object)DBNull.Value : s;
        }
    }
}
