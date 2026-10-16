using System;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Windows.Forms;
using DevExpress.Utils;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.HOFormsDevEx
{
    /// <summary>
    /// Account Officers (Admin Tools › General Administration), SQL/[95]-2026-10-15i_AccountOfficers_Maintenance.sql.
    /// Maintains dbo.AccountOfficers, the agents of the customer screens' Account Officer dropdown. Customers store the
    /// officer's NAME (Customers.AccountOfficer), so a rename also renames the officer on their customers, and an officer
    /// that still has customers can't be deleted (both enforced by the procs). Built in code (no designer file).
    /// </summary>
    public class AccountOfficersDevEx : XtraForm
    {
        private readonly GridControl grid = new GridControl();
        private readonly GridView view = new GridView();
        private readonly TextEdit txtId = new TextEdit();
        private readonly TextEdit txtName = new TextEdit();
        private readonly LabelControl lblInfo = new LabelControl();
        private readonly SimpleButton btnNew = new SimpleButton { Text = "New" };
        private readonly SimpleButton btnSave = new SimpleButton { Text = "Save" };
        private readonly SimpleButton btnDelete = new SimpleButton { Text = "Delete" };
        private readonly SimpleButton btnRefresh = new SimpleButton { Text = "Refresh" };

        private bool _dataLoaded;

        public AccountOfficersDevEx()
        {
            Text = "Account Officers";
            Size = new Size(900, 600);
            StartPosition = FormStartPosition.CenterScreen;
            BuildLayout();
            Load += (s, e) => LoadData();   // fallback only; the opener calls LoadData() (Known Bug Pattern #1)
        }

        private void BuildLayout()
        {
            // right: the edit panel
            var panel = new TableLayoutPanel { Dock = DockStyle.Right, Width = 340, ColumnCount = 2, RowCount = 6, Padding = new Padding(12, 12, 12, 8) };
            panel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 90));
            panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
            panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
            panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
            panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
            panel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));

            txtId.Anchor = AnchorStyles.Left | AnchorStyles.Right;
            txtId.Properties.ReadOnly = true;
            txtId.Properties.NullText = "(new)";
            txtName.Anchor = AnchorStyles.Left | AnchorStyles.Right;
            txtName.Properties.MaxLength = 50;

            var buttons1 = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
            foreach (var b in new[] { btnNew, btnSave })
            {
                b.Size = new Size(104, 34);
                buttons1.Controls.Add(b);
            }
            btnSave.Appearance.Font = new Font(btnSave.Appearance.Font ?? Font, FontStyle.Bold);
            btnSave.Appearance.Options.UseFont = true;
            var buttons2 = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
            foreach (var b in new[] { btnDelete, btnRefresh })
            {
                b.Size = new Size(104, 34);
                buttons2.Controls.Add(b);
            }

            lblInfo.AutoSizeMode = LabelAutoSizeMode.None;
            lblInfo.Dock = DockStyle.Fill;
            lblInfo.Appearance.TextOptions.WordWrap = WordWrap.Wrap;
            lblInfo.Appearance.TextOptions.VAlignment = VertAlignment.Top;
            lblInfo.Appearance.Options.UseTextOptions = true;
            lblInfo.Text = "Customers store the officer's name: renaming an officer renames them on all their customers. " +
                           "An officer who still has customers can't be deleted.";

            panel.Controls.Add(new LabelControl { Text = "Account ID:", Anchor = AnchorStyles.Left }, 0, 0);
            panel.Controls.Add(txtId, 1, 0);
            panel.Controls.Add(new LabelControl { Text = "Name:", Anchor = AnchorStyles.Left }, 0, 1);
            panel.Controls.Add(txtName, 1, 1);
            panel.Controls.Add(buttons1, 0, 2); panel.SetColumnSpan(buttons1, 2);
            panel.Controls.Add(buttons2, 0, 3); panel.SetColumnSpan(buttons2, 2);
            panel.Controls.Add(lblInfo, 0, 4); panel.SetColumnSpan(lblInfo, 2);

            // left: the list
            grid.Dock = DockStyle.Fill;
            grid.MainView = view;
            grid.ViewCollection.Add(view);
            view.GridControl = grid;
            view.OptionsBehavior.Editable = false;
            view.OptionsView.ShowGroupPanel = false;
            view.OptionsView.ShowFooter = true;
            view.OptionsSelection.EnableAppearanceFocusedCell = false;
            Classes.DevXGridViewSettings.ApplyTotalsBandAppearance(view);
            // the columns are created here, not by the DataSource: LoadData can run from Load, before the form is shown,
            // and a grid that isn't on a shown form creates no columns (PopulateColumns gotcha, 2026-10-13)
            view.Columns.AddVisible("AccountID", "Account ID");
            view.Columns.AddVisible("AccountOfficerName", "Account Officer");
            view.Columns.AddVisible("Customers", "Customers");
            Format();
            view.FocusedRowChanged += (s, e) => ShowFocused();

            btnNew.Click += (s, e) => StartNew();
            btnSave.Click += (s, e) => SaveOfficer();
            btnDelete.Click += (s, e) => DeleteOfficer();
            btnRefresh.Click += (s, e) => RefreshList(null);
            txtName.KeyDown += (s, e) => { if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; SaveOfficer(); } };

            Controls.Add(grid);    // Fill first: it docks last
            Controls.Add(panel);
        }

        // ── data ─────────────────────────────────────────────────
        public void LoadData()
        {
            if (_dataLoaded) return;
            _dataLoaded = true;
            RefreshList(null);
        }

        private void RefreshList(string focusId)
        {
            var table = new DataTable();
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("dbo.sp_AccountOfficer_List", con) { CommandType = CommandType.StoredProcedure })
                using (var da = new SqlDataAdapter(cmd))
                {
                    con.Open();
                    da.Fill(table);
                }
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show("Could not load the account officers:\n" + ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            grid.DataSource = table;   // the columns exist already (BuildLayout)
            view.BestFitColumns();

            int handle = -1;
            if (!string.IsNullOrEmpty(focusId))
                handle = view.LocateByValue("AccountID", focusId);
            if (handle >= 0) view.FocusedRowHandle = handle;
            ShowFocused();
        }

        private void Format()
        {
            var id = view.Columns["AccountID"];
            if (id != null) id.Caption = "Account ID";
            var name = view.Columns["AccountOfficerName"];
            if (name != null)
            {
                name.Caption = "Account Officer";
                name.Summary.Clear();
                name.Summary.Add(DevExpress.Data.SummaryItemType.Count, "AccountOfficerName", "{0:N0} officers");
            }
            var cust = view.Columns["Customers"];
            if (cust != null)
            {
                cust.DisplayFormat.FormatType = FormatType.Numeric;
                cust.DisplayFormat.FormatString = "N0";
                cust.AppearanceCell.TextOptions.HAlignment = HorzAlignment.Far;
                cust.AppearanceCell.Options.UseTextOptions = true;
                cust.AppearanceHeader.TextOptions.HAlignment = HorzAlignment.Far;
                cust.AppearanceHeader.Options.UseTextOptions = true;
                cust.Summary.Clear();
                cust.Summary.Add(DevExpress.Data.SummaryItemType.Sum, "Customers", "{0:N0}");
            }
        }

        private void ShowFocused()
        {
            int h = view.FocusedRowHandle;
            if (h < 0) { StartNew(); return; }
            txtId.EditValue = Convert.ToString(view.GetRowCellValue(h, "AccountID"));
            txtName.EditValue = Convert.ToString(view.GetRowCellValue(h, "AccountOfficerName"));
            btnDelete.Enabled = true;
        }

        private void StartNew()
        {
            txtId.EditValue = null;
            txtName.EditValue = "";
            btnDelete.Enabled = false;
            txtName.Focus();
        }

        // ── save / delete ────────────────────────────────────────
        private void SaveOfficer()
        {
            string id = Convert.ToString(txtId.EditValue)?.Trim();
            string name = Convert.ToString(txtName.EditValue)?.Trim() ?? "";
            if (name.Length == 0)
            {
                XtraMessageBox.Show("Type the account officer's name.", Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
                txtName.Focus();
                return;
            }

            // a rename moves every customer of the officer to the new name: say how many before doing it
            if (!string.IsNullOrEmpty(id) && view.FocusedRowHandle >= 0)
            {
                string oldName = Convert.ToString(view.GetRowCellValue(view.FocusedRowHandle, "AccountOfficerName"));
                int customers = Convert.ToInt32(view.GetRowCellValue(view.FocusedRowHandle, "Customers") ?? 0);
                if (oldName == name) { XtraMessageBox.Show("Nothing changed.", Text); return; }
                if (XtraMessageBox.Show($"Rename \"{oldName}\" to \"{name}\"?\n\n{customers:N0} customer(s) will show the new name.",
                        Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                    return;
            }

            try
            {
                string savedId, action;
                int moved;
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("dbo.spu_AccountOfficer_Save", con) { CommandType = CommandType.StoredProcedure })
                {
                    cmd.Parameters.Add("@AccountID", SqlDbType.VarChar, 15).Value = string.IsNullOrEmpty(id) ? (object)DBNull.Value : id;
                    cmd.Parameters.Add("@OfficerName", SqlDbType.VarChar, 50).Value = name;
                    cmd.Parameters.Add("@UserID", SqlDbType.VarChar, 50).Value = (object)Login.isglobalUserID ?? DBNull.Value;
                    con.Open();
                    using (var rdr = cmd.ExecuteReader())
                    {
                        rdr.Read();
                        savedId = rdr["AccountID"].ToString();
                        action = rdr["Action"].ToString();
                        moved = Convert.ToInt32(rdr["CustomersUpdated"]);
                    }
                }
                RefreshList(savedId);
                XtraMessageBox.Show(action == "ADDED" ? $"Added (Account ID {savedId})."
                                  : action == "RENAMED" ? $"Renamed; {moved:N0} customer(s) updated."
                                  : "Nothing changed.", Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        private void DeleteOfficer()
        {
            int h = view.FocusedRowHandle;
            if (h < 0) return;
            string id = Convert.ToString(view.GetRowCellValue(h, "AccountID"));
            string name = Convert.ToString(view.GetRowCellValue(h, "AccountOfficerName"));
            if (XtraMessageBox.Show($"Delete account officer \"{name}\"?", Text, MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes)
                return;
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("dbo.spu_AccountOfficer_Delete", con) { CommandType = CommandType.StoredProcedure })
                {
                    cmd.Parameters.Add("@AccountID", SqlDbType.VarChar, 15).Value = id;
                    cmd.Parameters.Add("@UserID", SqlDbType.VarChar, 50).Value = (object)Login.isglobalUserID ?? DBNull.Value;
                    con.Open();
                    cmd.ExecuteNonQuery();
                }
                RefreshList(null);
                XtraMessageBox.Show("Deleted.", Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (SqlException ex)
            {
                // 59712: customers still have the officer (the message says how many)
                XtraMessageBox.Show(ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
    }
}
