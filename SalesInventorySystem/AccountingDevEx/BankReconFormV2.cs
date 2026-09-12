using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.AccountingDevEx
{
    public partial class BankReconFormV2 : XtraUserControl
    {
        // ── Theme (kept local so this file has no external dependency) ──
        private static readonly System.Drawing.Color C_GOLD = System.Drawing.Color.FromArgb(180, 140, 20);
        private static readonly System.Drawing.Color C_TEXT = System.Drawing.Color.FromArgb(40, 40, 40);
        private static readonly System.Drawing.Color C_DR = System.Drawing.Color.FromArgb(20, 90, 40);
        private static readonly System.Drawing.Color C_CR = System.Drawing.Color.FromArgb(150, 30, 30);
        private static readonly System.Drawing.Color C_OK = System.Drawing.Color.FromArgb(20, 120, 60);
        private static readonly System.Drawing.Color C_ERR = System.Drawing.Color.FromArgb(190, 40, 40);
        private static readonly System.Drawing.Color C_MUTED = System.Drawing.Color.Gray;
        private static readonly System.Drawing.Color C_AUTO = System.Drawing.Color.FromArgb(232, 244, 255);
        private static readonly System.Drawing.Font F_MONO = new System.Drawing.Font("Courier New", 9.75f);

        // ── State ─────────────────────────────────────────────────────
        private string _branch = Login.assignedBranch;
        private string _account = "";
        private DateTime _period = DateTime.Today;
        private decimal _bookBal = 0m;
        private decimal _bankBal = 0m;
        private int _headerID = 0;
        private int _selDitID = 0;
        private int _selOcID = 0;
        private int _selBankSideID = 0;
        private string _selBankSideType = "";
        private bool _isLocked = false;

        private DataTable _dtDIT = new DataTable();
        private DataTable _dtOC = new DataTable();
        private DataTable _dtBankSide = new DataTable();

        public BankReconFormV2()
        {
            InitializeComponent();
            WireEvents();
            PopulateLookups();
            SetDefaultPeriod();

            viewDIT.RowCellStyle += View_RowCellStyle;
            viewOC.RowCellStyle += View_RowCellStyle;
            viewBankSide.RowCellStyle += View_RowCellStyle;
        }

        private void View_RowCellStyle(object sender, RowCellStyleEventArgs e)
        {
            var v = (GridView)sender;
            if (e.RowHandle < 0) return;
            var isAuto = v.GetRowCellValue(e.RowHandle, "IsAutoInserted");
            if (isAuto != null && isAuto != DBNull.Value && Convert.ToBoolean(isAuto))
            {
                e.Appearance.BackColor = C_AUTO;
                e.Appearance.Options.UseBackColor = true;
            }
        }

        // ================================================================
        // WIRE EVENTS
        // ================================================================
        private void WireEvents()
        {
            btnLoad.Click += (s, e) => LoadRecon();
            btnSaveHeader.Click += BtnSaveHeader_Click;

            btnAddDIT.Click += (s, e) => BtnAdd_Click("DIT");
            btnResolveDIT.Click += (s, e) => BtnResolve_Click(_selDitID);
            btnDeleteDIT.Click += (s, e) => BtnDelete_Click(_selDitID);
            chkSelectAllDIT.CheckedChanged += ChkSelectAllDIT_CheckedChanged;
            btnBulkResolveDIT.Click += BtnBulkResolveDIT_Click;
            btnResolveGroupDIT.Click += BtnResolveGroupDIT_Click;

            btnAddOC.Click += (s, e) => BtnAdd_Click("OC");
            btnResolveOC.Click += (s, e) => BtnResolve_Click(_selOcID);
            btnDeleteOC.Click += (s, e) => BtnDelete_Click(_selOcID);
            btnAutoMatch.Click += BtnAutoMatch_Click;
            chkSelectAllOC.CheckedChanged += ChkSelectAllOC_CheckedChanged;
            btnBulkResolveOC.Click += BtnBulkResolveOC_Click;

            btnAddBankSide.Click += (s, e) => BtnAdd_Click("BDM"); // dialog lets user switch to BCM/BC/NSF/ADB
            btnResolveBankSide.Click += (s, e) => BtnResolve_Click(_selBankSideID);
            btnDeleteBankSide.Click += (s, e) => BtnDelete_Click(_selBankSideID);
            btnPostAutoDebit.Click += BtnPostAutoDebit_Click;

            btnLock.Click += BtnLock_Click;
            btnPrint.Click += BtnPrint_Click;

            dtPeriod.EditValueChanged += (s, e) =>
            {
                if (dtPeriod.EditValue is DateTime dt)
                {
                    var eom = new DateTime(dt.Year, dt.Month, DateTime.DaysInMonth(dt.Year, dt.Month));
                    if (dt != eom) dtPeriod.EditValue = eom;
                }
            };

            viewDIT.FocusedRowChanged += (s, e) =>
            {
                bool has = viewDIT.FocusedRowHandle >= 0;
                btnResolveDIT.Enabled = has && !_isLocked;
                btnDeleteDIT.Enabled = has && !_isLocked;
                _selDitID = has ? SafeInt(viewDIT.GetRowCellValue(viewDIT.FocusedRowHandle, "ReconID")) : 0;

                // Works whether the focused row is a plain data row or a collapsed/expanded
                // ControlNo group row -- GetRowCellValue on the grouped column returns the
                // group's key value either way. Only enabled when that ControlNo is real (not
                // blank), since a blank-ControlNo "group" is just every unrelated plain DIT item
                // with no batch reference, not something that should ever be bulk-resolved together.
                string focusedControlNo = null;
                if (viewDIT.FocusedRowHandle != DevExpress.XtraGrid.GridControl.InvalidRowHandle)
                    focusedControlNo = Convert.ToString(viewDIT.GetRowCellValue(viewDIT.FocusedRowHandle, "ControlNo"));
                btnResolveGroupDIT.Enabled = !_isLocked && !string.IsNullOrWhiteSpace(focusedControlNo);
            };

            viewOC.FocusedRowChanged += (s, e) =>
            {
                bool has = viewOC.FocusedRowHandle >= 0;
                btnResolveOC.Enabled = has && !_isLocked;
                btnDeleteOC.Enabled = has && !_isLocked;
                _selOcID = has ? SafeInt(viewOC.GetRowCellValue(viewOC.FocusedRowHandle, "ReconID")) : 0;
            };

            viewBankSide.FocusedRowChanged += (s, e) =>
            {
                bool has = viewBankSide.FocusedRowHandle >= 0;
                bool isResolved = has && Convert.ToBoolean(viewBankSide.GetRowCellValue(viewBankSide.FocusedRowHandle, "IsResolved") ?? false);
                _selBankSideID = has ? SafeInt(viewBankSide.GetRowCellValue(viewBankSide.FocusedRowHandle, "ReconID")) : 0;
                _selBankSideType = has ? Convert.ToString(viewBankSide.GetRowCellValue(viewBankSide.FocusedRowHandle, "ItemType")) : "";

                btnResolveBankSide.Enabled = has && !isResolved && !_isLocked;
                btnDeleteBankSide.Enabled = has && !isResolved && !_isLocked;
                // Post Payment only makes sense for an unresolved Auto-Debit Broker row
                btnPostAutoDebit.Enabled = has && !isResolved && !_isLocked && _selBankSideType == "ADB";
            };
        }

        // ================================================================
        // POPULATE LOOKUPS
        // ================================================================
        private void PopulateLookups()
        {
            Database.displaySearchlookupEdit(
                "SELECT BranchCode, BranchName FROM Branches ORDER BY BranchCode",
                cmbBranch, "BranchCode", "BranchCode");
            cmbBranch.EditValue = Login.assignedBranch;

            // DisplayMember is the combined "Code - Description" text (Code-Name display
            // convention) so the closed editor is readable; ValueMember stays AccountCode
            // alone since _account (read via cmbAccount.EditValue) is used as a bare account
            // code in every downstream WHERE clause and SqlParameter.
            Database.displaySearchlookupEdit(
                "SELECT AccountCode, Description, AccountCode + ' - ' + Description AS DisplayText FROM ChartOfAccounts WHERE AccountCode LIKE '10102%' AND AccountType='D' ORDER BY AccountCode",
                cmbAccount, "DisplayText", "AccountCode");
            if (cmbAccount.Properties.View.Columns["DisplayText"] != null)
                cmbAccount.Properties.View.Columns["DisplayText"].Visible = false;
        }

        private void SetDefaultPeriod()
        {
            var today = DateTime.Today;
            _period = new DateTime(today.Year, today.Month, 1).AddDays(-1);
            dtPeriod.EditValue = _period;
        }

        // ================================================================
        // LOAD RECON
        // ================================================================
        private void LoadRecon()
        {
            _branch = cmbBranch.EditValue?.ToString() ?? Login.assignedBranch;
            _account = cmbAccount.EditValue?.ToString() ?? "";
            _period = dtPeriod.EditValue is DateTime dt ? dt : DateTime.TryParse(dtPeriod.Text, out var pd) ? pd : DateTime.Today;

            if (string.IsNullOrWhiteSpace(_account))
            {
                XtraMessageBox.Show("Please select a bank GL account.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            try
            {
                LoadPeriod();
                RefreshSummary();
                SetStatus($"Loaded: {_account}  |  Period: {_period:yyyy-MM-dd}" + (_isLocked ? "  |  LOCKED" : ""));
            }
            catch (SqlException ex)
            {
                SetStatus($"Load failed: {ex.Message}", err: true);
            }
        }

        private void LoadPeriod()
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("sp_BankRecon_GetPeriod", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@BranchCode", SqlDbType.Char, 3).Value = _branch;
                cmd.Parameters.Add("@AccountCode", SqlDbType.VarChar, 20).Value = _account;
                cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = _period;

                var ds = new DataSet();
                con.Open();
                new SqlDataAdapter(cmd).Fill(ds);

                if (ds.Tables.Count > 0 && ds.Tables[0].Rows.Count > 0)
                {
                    var hdr = ds.Tables[0].Rows[0];
                    _headerID = SafeInt(hdr["HeaderID"]);
                    _bookBal = SafeDec(hdr["GLBookBalance"]);
                    _bankBal = SafeDec(hdr["BankStatementBal"]);
                    _isLocked = hdr["Status"]?.ToString() == "LOCKED";

                    lblBookBal.Text = _bookBal.ToString("N2");
                    txtBankBal.Text = _bankBal.ToString("N2");
                }
                else
                {
                    CreateHeaderSilent();
                    LoadPeriod();
                    return;
                }

                _dtDIT = ds.Tables.Count > 1 ? ds.Tables[1] : new DataTable();
                // In-memory only, never persisted -- backs the Check-All / bulk-resolve
                // checkbox column. Added before binding so BindGrid's DataSource assignment
                // auto-generates a real grid column for it.
                if (!_dtDIT.Columns.Contains("Selected")) _dtDIT.Columns.Add("Selected", typeof(bool));
                BindGrid(gridDIT, viewDIT, _dtDIT);
                ConfigureDitGridExtras();

                _dtOC = ds.Tables.Count > 2 ? ds.Tables[2] : new DataTable();
                if (!_dtOC.Columns.Contains("Selected")) _dtOC.Columns.Add("Selected", typeof(bool));
                BindGrid(gridOC, viewOC, _dtOC);
                ConfigureOcGridExtras();

                // NEW — third result set: BCM/BDM/BC/NSF/ADB
                _dtBankSide = ds.Tables.Count > 3 ? ds.Tables[3] : new DataTable();
                BindBankSideGrid(_dtBankSide);
            }

            SetLockedState(_isLocked);
        }

        private void CreateHeaderSilent()
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("sp_BankRecon_GetOrCreateHeader", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@BranchCode", SqlDbType.Char, 3).Value = _branch;
                cmd.Parameters.Add("@AccountCode", SqlDbType.VarChar, 20).Value = _account;
                cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = _period;
                cmd.Parameters.Add("@CreatedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;
                cmd.Parameters.Add("@HeaderID", SqlDbType.Int).Direction = ParameterDirection.Output;

                con.Open();
                cmd.ExecuteNonQuery();
                _headerID = SafeInt(cmd.Parameters["@HeaderID"].Value);
            }
        }

        private void SetLockedState(bool locked)
        {
            txtBankBal.Properties.ReadOnly = locked;
            btnSaveHeader.Enabled = !locked;
            btnAddDIT.Enabled = !locked;
            btnAddOC.Enabled = !locked;
            btnAddBankSide.Enabled = !locked;
            btnLock.Enabled = !locked;
            btnAutoMatch.Enabled = !locked;
            chkSelectAllDIT.Enabled = !locked;
            btnBulkResolveDIT.Enabled = !locked;
            if (locked) btnResolveGroupDIT.Enabled = false; // re-enabled per-focus by viewDIT.FocusedRowChanged once unlocked
            chkSelectAllOC.Enabled = !locked;
            btnBulkResolveOC.Enabled = !locked;
        }

        private void BindGrid(DevExpress.XtraGrid.GridControl grid, GridView view, DataTable dt)
        {
            view.Columns.Clear();
            grid.DataSource = dt;

            FormatCol(view, "ReconID", 50, false);
            FormatCol(view, "ItemDate", 90, false, isDate: true);
            FormatCol(view, "ReferenceNo", 120, false);
            FormatCol(view, "Payee", 160, false);
            FormatCol(view, "Amount", 110, true);
            FormatCol(view, "IsResolved", 60, false);
            FormatCol(view, "ResolvedReason", 110, false);
            FormatCol(view, "SourceModule", 80, false);
            FormatCol(view, "IsAutoInserted", 0, false);

            if (view.Columns["IsAutoInserted"] != null) view.Columns["IsAutoInserted"].Visible = false;
            view.BestFitColumns();
        }

        private void BindBankSideGrid(DataTable dt)
        {
            viewBankSide.Columns.Clear();
            gridBankSide.DataSource = dt;

            FormatCol(viewBankSide, "ReconID", 50, false);
            FormatCol(viewBankSide, "ItemType", 60, false);
            FormatCol(viewBankSide, "ItemDate", 90, false, isDate: true);
            FormatCol(viewBankSide, "ReferenceNo", 120, false);
            FormatCol(viewBankSide, "Payee", 160, false);
            FormatCol(viewBankSide, "Amount", 110, true);
            FormatCol(viewBankSide, "IsResolved", 60, false);
            FormatCol(viewBankSide, "PostedPaymentRef", 100, false);
            FormatCol(viewBankSide, "ResolvedReason", 130, false);
            FormatCol(viewBankSide, "IsAutoInserted", 0, false);
            FormatCol(viewBankSide, "MatchedExpenseMasterID", 0, false);

            if (viewBankSide.Columns["IsAutoInserted"] != null) viewBankSide.Columns["IsAutoInserted"].Visible = false;
            if (viewBankSide.Columns["MatchedExpenseMasterID"] != null) viewBankSide.Columns["MatchedExpenseMasterID"].Visible = false;
            viewBankSide.BestFitColumns();
        }

        private void FormatCol(GridView view, string field, int width, bool money, bool isDate = false)
        {
            var col = view.Columns[field];
            if (col == null) return;

            col.Width = width;
            col.AppearanceHeader.ForeColor = C_GOLD;
            col.AppearanceHeader.Font = new System.Drawing.Font("Courier New", 7.5f, System.Drawing.FontStyle.Bold);
            col.AppearanceHeader.Options.UseForeColor = true;
            col.AppearanceHeader.Options.UseFont = true;

            if (money)
            {
                col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                col.DisplayFormat.FormatString = "N2";
                col.AppearanceCell.Font = F_MONO;
                col.AppearanceCell.ForeColor = C_DR;
                col.AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                col.AppearanceCell.Options.UseFont = true;
                col.AppearanceCell.Options.UseForeColor = true;
                col.Summary.Add(DevExpress.Data.SummaryItemType.Sum, field, "{0:N2}");
            }
            if (isDate)
            {
                col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                col.DisplayFormat.FormatString = "yyyy-MM-dd";
            }
        }

        // Adds the ControlNo column and turns the in-memory "Selected" column into a real
        // checkbox -- while keeping every other column locked to read-only, since
        // viewDIT.OptionsBehavior.Editable now has to be true at the view level for
        // the checkbox to be togglable at all. Filtering (e.g. by ControlNo) is done via
        // the grid's normal column-header filter dropdown, not a separate auto-filter row.
        private void ConfigureDitGridExtras()
        {
            FormatCol(viewDIT, "ControlNo", 100, false);

            foreach (DevExpress.XtraGrid.Columns.GridColumn col in viewDIT.Columns)
                col.OptionsColumn.AllowEdit = col.FieldName == "Selected";

            var colSelected = viewDIT.Columns["Selected"];
            if (colSelected != null)
            {
                var repoCheck = new DevExpress.XtraEditors.Repository.RepositoryItemCheckEdit();
                gridDIT.RepositoryItems.Add(repoCheck);
                colSelected.ColumnEdit = repoCheck;
                colSelected.Caption = "";
                colSelected.OptionsColumn.AllowSort = DevExpress.Utils.DefaultBoolean.False;
                colSelected.VisibleIndex = 0;
            }

            // Group by ControlNo so line items belonging to the same real collection batch
            // (see BankReconItemForm's ControlNo picker -- sourced from
            // sp_BankRecon_GetControlNoCandidates, a genuine shared batch reference, not a
            // free-typed value) display as one line with a summed total instead of N separate
            // rows, matching the same ControlNo-grouping pattern already used in
            // POSSalesReportDevEx.cs's Cash Receipts Book grid. Expanded by default so nothing
            // is hidden vs. the pre-grouping flat-grid behavior -- the user can manually collapse
            // a batch's group to see just the one summary line if they want. A collapsed group's
            // children fall out of ChkSelectAllDIT/GetVisibleRowHandle's traversal by design --
            // that's fine, a collapsed batch is meant to be resolved via btnResolveGroupDIT below,
            // not via the per-row checkbox + Bulk Resolve path.
            var colControlNo = viewDIT.Columns["ControlNo"];
            if (colControlNo != null)
            {
                colControlNo.GroupIndex = 0;
                viewDIT.OptionsView.ShowGroupPanel = false;

                viewDIT.GroupSummary.Clear();
                viewDIT.GroupSummary.Add(DevExpress.Data.SummaryItemType.Count, "ControlNo", colControlNo, "{0} item(s)");
                var colAmount = viewDIT.Columns["Amount"];
                if (colAmount != null)
                    viewDIT.GroupSummary.Add(DevExpress.Data.SummaryItemType.Sum, "Amount", colAmount, "Total: {0:N2}");
            }

            viewDIT.BestFitColumns();
            if (colSelected != null) colSelected.Width = 30;

            viewDIT.ExpandAllGroups();

            chkSelectAllDIT.Checked = false;
        }

        // Only affects rows currently passing the filter row -- GetVisibleRowHandle
        // walks the filtered/visible row set, not every underlying row in _dtDIT. Now that
        // viewDIT is grouped by ControlNo, that traversal also yields group-row handles
        // (negative, one per ControlNo band) alongside real data-row handles -- skip those,
        // since "Selected" isn't the grouped column and a group row can't carry a per-row
        // checkbox value. A collapsed group's children are correctly excluded from this loop
        // entirely (not just skipped) -- see the comment on btnResolveGroupDIT below for why
        // that's the intended split between the two resolve paths.
        private void ChkSelectAllDIT_CheckedChanged(object sender, EventArgs e)
        {
            for (int i = 0; i < viewDIT.RowCount; i++)
            {
                int handle = viewDIT.GetVisibleRowHandle(i);
                if (viewDIT.IsGroupRow(handle)) continue;
                viewDIT.SetRowCellValue(handle, "Selected", chkSelectAllDIT.Checked);
            }
        }

        private void BtnBulkResolveDIT_Click(object sender, EventArgs e)
        {
            if (_isLocked) return;

            var ids = new List<int>();
            foreach (DataRow row in _dtDIT.Rows)
                if (row["Selected"] is bool sel && sel)
                    ids.Add(SafeInt(row["ReconID"]));

            if (ids.Count == 0)
            {
                XtraMessageBox.Show("No items checked. Filter by Control No and check the rows you want to resolve.");
                return;
            }

            if (XtraMessageBox.Show($"Mark {ids.Count} checked item(s) as cleared by the bank?", "Confirm Bulk Resolve", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;

            ResolveReconIDs(ids, "DIT");
        }

        // Resolves every unresolved DIT row sharing the focused row's/group's ControlNo in one
        // click -- the counterpart to btnBulkResolveDIT's checkbox-driven flow, for the case
        // where the user just wants to clear an entire collection batch without expanding its
        // group and checking each row individually. Reuses the exact same
        // sp_BankRecon_BulkResolveItems SP via ResolveReconIDs, just sourced from a ControlNo
        // match instead of the "Selected" column.
        private void BtnResolveGroupDIT_Click(object sender, EventArgs e)
        {
            if (_isLocked) return;

            int handle = viewDIT.FocusedRowHandle;
            string controlNo = handle != DevExpress.XtraGrid.GridControl.InvalidRowHandle
                ? Convert.ToString(viewDIT.GetRowCellValue(handle, "ControlNo"))
                : null;

            if (string.IsNullOrWhiteSpace(controlNo))
            {
                XtraMessageBox.Show("Select a row or group with a Control No first.");
                return;
            }

            var ids = new List<int>();
            foreach (DataRow row in _dtDIT.Rows)
            {
                if (Convert.ToString(row["ControlNo"]) != controlNo) continue;
                if (row["IsResolved"] is bool resolved && resolved) continue;
                ids.Add(SafeInt(row["ReconID"]));
            }

            if (ids.Count == 0)
            {
                XtraMessageBox.Show("All items under this Control No are already cleared.");
                return;
            }

            if (XtraMessageBox.Show($"Mark all {ids.Count} item(s) under Control No '{controlNo}' as cleared by the bank?", "Confirm Resolve Batch", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;

            ResolveReconIDs(ids, "DIT");
        }

        // Shared by BtnBulkResolveDIT_Click, BtnResolveGroupDIT_Click, and BtnBulkResolveOC_Click --
        // all three just differ in how they gather the ReconID list beforehand.
        private void ResolveReconIDs(List<int> ids, string itemType)
        {
            try
            {
                var dtIds = new DataTable();
                dtIds.Columns.Add("ReconID", typeof(int));
                foreach (var id in ids) dtIds.Rows.Add(id);

                int resolved = 0;
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_BankRecon_BulkResolveItems", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    var p = cmd.Parameters.Add("@ReconIDs", SqlDbType.Structured);
                    p.TypeName = "dbo.tt_BankReconIDList";
                    p.Value = dtIds;
                    cmd.Parameters.Add("@ResolvedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    cmd.Parameters.Add("@ItemType", SqlDbType.VarChar, 5).Value = itemType;

                    con.Open();
                    using (var rdr = cmd.ExecuteReader())
                        if (rdr.Read()) resolved = SafeInt(rdr["ResolvedCount"]);
                }

                LoadPeriod();
                RefreshSummary();
                SetStatus($"{resolved} item(s) marked cleared.");
            }
            catch (SqlException ex) { SetStatus(ex.Message, err: true); }
        }

        // Same Selected-checkbox / Check-All / Bulk Resolve pattern as the DIT grid --
        // OC has no ControlNo column, so no extra column formatting is needed here.
        private void ConfigureOcGridExtras()
        {
            foreach (DevExpress.XtraGrid.Columns.GridColumn col in viewOC.Columns)
                col.OptionsColumn.AllowEdit = col.FieldName == "Selected";

            var colSelected = viewOC.Columns["Selected"];
            if (colSelected != null)
            {
                var repoCheck = new DevExpress.XtraEditors.Repository.RepositoryItemCheckEdit();
                gridOC.RepositoryItems.Add(repoCheck);
                colSelected.ColumnEdit = repoCheck;
                colSelected.Caption = "";
                colSelected.OptionsColumn.AllowSort = DevExpress.Utils.DefaultBoolean.False;
                colSelected.VisibleIndex = 0;
            }

            viewOC.BestFitColumns();
            if (colSelected != null) colSelected.Width = 30;

            chkSelectAllOC.Checked = false;
        }

        private void ChkSelectAllOC_CheckedChanged(object sender, EventArgs e)
        {
            for (int i = 0; i < viewOC.RowCount; i++)
            {
                int handle = viewOC.GetVisibleRowHandle(i);
                viewOC.SetRowCellValue(handle, "Selected", chkSelectAllOC.Checked);
            }
        }

        private void BtnBulkResolveOC_Click(object sender, EventArgs e)
        {
            if (_isLocked) return;

            var ids = new List<int>();
            foreach (DataRow row in _dtOC.Rows)
                if (row["Selected"] is bool sel && sel)
                    ids.Add(SafeInt(row["ReconID"]));

            if (ids.Count == 0)
            {
                XtraMessageBox.Show("No items checked.");
                return;
            }

            if (XtraMessageBox.Show($"Mark {ids.Count} checked item(s) as cleared by the bank?", "Confirm Bulk Resolve", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;

            ResolveReconIDs(ids, "OC");
        }

        private void RefreshSummary()
        {
            decimal dit = 0, oc = 0, bcm = 0, bdm = 0;
            foreach (DataRow row in _dtDIT.Rows)
            {
                if (row["IsResolved"] is bool b && b) continue;
                dit += SafeDec(row["Amount"]);
            }
            foreach (DataRow row in _dtOC.Rows)
            {
                if (row["IsResolved"] is bool b && b) continue;
                oc += SafeDec(row["Amount"]);
            }
            // BCM adds to book side; BDM/BC/NSF/ADB all reduce book side until posted/resolved
            foreach (DataRow row in _dtBankSide.Rows)
            {
                if (row["IsResolved"] is bool b && b) continue;
                string t = row["ItemType"]?.ToString();
                decimal amt = SafeDec(row["Amount"]);
                if (t == "BCM") bcm += amt;
                else bdm += amt; // BDM, BC, NSF, ADB
            }

            decimal adjBank = _bankBal + dit - oc;
            decimal adjBook = _bookBal + bcm - bdm;
            decimal diff = adjBank - adjBook;
            bool balanced = Math.Abs(diff) < 0.01m;

            SetLbl(lblBankStmt, _bankBal.ToString("N2"), C_TEXT);
            SetLbl(lblDIT, $"+{dit:N2}", C_DR);
            SetLbl(lblOC, $"-{oc:N2}", C_CR);
            SetLbl(lblAdjBank, adjBank.ToString("N2"), C_OK);
            SetLbl(lblBookSide, _bookBal.ToString("N2"), C_TEXT);
            SetLbl(lblBCM, $"+{bcm:N2}", C_DR);
            SetLbl(lblBDM, $"-{bdm:N2}", C_CR);
            SetLbl(lblAdjBook, adjBook.ToString("N2"), C_OK);

            if (balanced)
            {
                SetLbl(lblDiff, "0.00  RECONCILED", C_OK);
            }
            else
            {
                SetLbl(lblDiff, $"{Math.Abs(diff):N2}  OUT OF BALANCE", C_ERR);
            }
        }

        private void SetLbl(LabelControl lbl, string text, System.Drawing.Color color)
        {
            if (lbl == null) return;
            lbl.Text = text;
            lbl.ForeColor = color;
            lbl.Appearance.Options.UseForeColor = true;
        }

        // ================================================================
        // CRUD HANDLERS
        // ================================================================
        private void BtnSaveHeader_Click(object sender, EventArgs e)
        {
            if (_headerID == 0) { XtraMessageBox.Show("Load a period first."); return; }
            if (!decimal.TryParse(txtBankBal.Text.Replace(",", ""), NumberStyles.Any, CultureInfo.InvariantCulture, out var bal))
            { XtraMessageBox.Show("Enter a valid amount."); return; }

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_BankRecon_SaveHeader", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@HeaderID", SqlDbType.Int).Value = _headerID;
                    cmd.Parameters.Add("@BankStatementBal", SqlDbType.Decimal).Value = Math.Round(bal, 2);
                    cmd.Parameters.Add("@Remarks", SqlDbType.VarChar, 500).Value = "";
                    cmd.Parameters.Add("@UpdatedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    con.Open();
                    cmd.ExecuteNonQuery();
                }
                _bankBal = bal;
                LoadPeriod();
                RefreshSummary();
                SetStatus("Bank statement balance saved.");
            }
            catch (SqlException ex) { SetStatus(ex.Message, err: true); }
        }

        private void BtnAdd_Click(string defaultItemType)
        {
            if (_headerID == 0) { XtraMessageBox.Show("Load a period first."); return; }

            using (var dlg = new BankReconItemForm(isNew: true))
            {
                dlg.ItemType = defaultItemType;
                dlg.BranchCode = _branch;
                dlg.AccountCode = _account;
                dlg.LoadControlNoCandidates();
                if (dlg.ShowDialog(this) != DialogResult.OK) return;

                try
                {
                    using (var con = Database.getConnection())
                    using (var cmd = new SqlCommand("sp_BankRecon_SaveItem", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 5).Value = _branch;
                        cmd.Parameters.Add("@AccountCode", SqlDbType.VarChar, 20).Value = _account;
                        cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = _period;
                        cmd.Parameters.Add("@BankStatementBal", SqlDbType.Decimal).Value = _bankBal;
                        cmd.Parameters.Add("@ItemType", SqlDbType.VarChar, 5).Value = dlg.ItemType;
                        cmd.Parameters.Add("@ReferenceNo", SqlDbType.VarChar, 150).Value = dlg.ReferenceNo;
                        cmd.Parameters.Add("@ItemDate", SqlDbType.Date).Value = dlg.ItemDate;
                        cmd.Parameters.Add("@Payee", SqlDbType.VarChar, 200).Value = dlg.Payee;
                        cmd.Parameters.Add("@Amount", SqlDbType.Decimal).Value = Math.Round(dlg.Amount, 2);
                        cmd.Parameters.Add("@Remarks", SqlDbType.VarChar, 500).Value = dlg.Remarks;
                        cmd.Parameters.Add("@User", SqlDbType.VarChar, 50).Value = Login.Fullname;
                        con.Open();
                        cmd.ExecuteNonQuery();
                    }
                    LoadPeriod();
                    RefreshSummary();
                    SetStatus($"{dlg.ItemType} item added.");
                }
                catch (SqlException ex) { SetStatus(ex.Message, err: true); }
            }
        }

        private void BtnResolve_Click(int reconID)
        {
            if (reconID <= 0) return;
            if (XtraMessageBox.Show("Mark this item as cleared by the bank?", "Confirm", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_BankRecon_ResolveItem", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@ReconID", SqlDbType.Int).Value = reconID;
                    cmd.Parameters.Add("@IsResolved", SqlDbType.Bit).Value = true;
                    cmd.Parameters.Add("@ResolvedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    con.Open();
                    cmd.ExecuteNonQuery();
                }
                LoadPeriod(); RefreshSummary();
                SetStatus("Item marked as cleared.");
            }
            catch (SqlException ex) { SetStatus(ex.Message, err: true); }
        }

        private void MarkAsUncleared(int reconID)
        {
            if (reconID <= 0) return;
            if (XtraMessageBox.Show("Mark this item as uncleared by the bank?", "Confirm", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_BankRecon_ResolveItem", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@ReconID", SqlDbType.Int).Value = reconID;
                    cmd.Parameters.Add("@IsResolved", SqlDbType.Bit).Value = false;
                    cmd.Parameters.Add("@ResolvedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    con.Open();
                    cmd.ExecuteNonQuery();
                }
                LoadPeriod(); RefreshSummary();
                SetStatus("Item marked as uncleared.");
            }
            catch (SqlException ex) { SetStatus(ex.Message, err: true); }
        }

        private void BtnDelete_Click(int reconID)
        {
            if (reconID <= 0) return;
            if (XtraMessageBox.Show("Delete this item? Auto-inserted items should not be deleted.", "Confirm Delete", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_BankRecon_DeleteItem", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@ReconID", SqlDbType.Int).Value = reconID;
                    cmd.Parameters.Add("@User", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    con.Open();
                    cmd.ExecuteNonQuery();
                }
                LoadPeriod(); RefreshSummary();
                SetStatus("Item deleted.");
            }
            catch (SqlException ex) { SetStatus(ex.Message, err: true); }
        }

        // ── NEW: Post Payment for an Auto-Debit Broker (ADB) row ────────
        // Opens a picker of open SINGLE-mode invoices for AUTODEBIT
        // suppliers, then posts the payment through
        // sp_AddPaymentSupplierCompound — same call your manual Payment
        // screen (PostSupplierPayment) makes — and resolves this row.
        private void BtnPostAutoDebit_Click(object sender, EventArgs e)
        {
            if (_selBankSideID <= 0 || _selBankSideType != "ADB") return;

            int reconRowHandle = viewBankSide.FocusedRowHandle;
            decimal amount = SafeDec(viewBankSide.GetRowCellValue(reconRowHandle, "Amount"));
            DateTime itemDate = viewBankSide.GetRowCellValue(reconRowHandle, "ItemDate") is DateTime d ? d : DateTime.Today;
            string bankRef = Convert.ToString(viewBankSide.GetRowCellValue(reconRowHandle, "ReferenceNo") ?? "");

            using (var dlg = new BankReconAutoDebitMatchForm(amount))
            {
                if (dlg.ShowDialog(this) != DialogResult.OK || string.IsNullOrEmpty(dlg.SelectedInvoiceNo)) return;

                if (XtraMessageBox.Show(
                        $"Post payment of {amount:N2} against invoice #{dlg.SelectedInvoiceNo} ({dlg.SelectedSupplierName})?\nThis will settle the supplier's payable and cannot be undone from here.",
                        "Confirm Payment", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                    return;

                try
                {
                    string referenceNo = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");
                    string voucherId = IDGenerator.getIDNumberSP("sp_GetVoucherNumber", "TicketNumber");

                    using (var con = Database.getConnection())
                    using (var cmd = new SqlCommand("sp_AddPaymentSupplierCompound", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.CommandTimeout = 180;

                        cmd.Parameters.Add("@parmrefno", SqlDbType.VarChar, 10).Value = referenceNo;
                        cmd.Parameters.Add("@parmvoucherid", SqlDbType.VarChar, 10).Value = voucherId;
                        cmd.Parameters.Add("@parmsupplierid", SqlDbType.VarChar, 50).Value = dlg.SelectedSupplierID;
                        cmd.Parameters.Add("@parmsuppliername", SqlDbType.VarChar, 150).Value = dlg.SelectedSupplierName;
                        cmd.Parameters.Add("@parmcheckamount", SqlDbType.Decimal).Value = amount;
                        cmd.Parameters.Add("@parmcheckcoding", SqlDbType.VarChar, 50).Value = "AUTODEBIT" + bankRef;
                        cmd.Parameters.Add("@parmcheckno", SqlDbType.VarChar, 50).Value = bankRef;
                        cmd.Parameters.Add("@parmcheckdate", SqlDbType.Date).Value = itemDate;
                        cmd.Parameters.Add("@parmcheckremarks", SqlDbType.VarChar, 2000).Value =
                            $"Auto-debit broker payment matched via Bank Recon | ReconID: {_selBankSideID}";
                        cmd.Parameters.Add("@parmpreparedby", SqlDbType.VarChar, 30).Value = Login.Fullname;
                        cmd.Parameters.Add("@parmglcode", SqlDbType.VarChar, 30).Value = _account;
                        cmd.Parameters.Add("@parmpaymethod", SqlDbType.VarChar, 20).Value = "EXPENSE";
                        cmd.Parameters.Add("@parmforliquidation", SqlDbType.Bit).Value = false;
                        // "CASH" (not "CHECK") — this resolves an existing bank line;
                        // we don't want the SP auto-inserting a *new* OC recon row for it.
                        cmd.Parameters.Add("@parmvouchertype", SqlDbType.VarChar, 10).Value = "CASH";
                        cmd.Parameters.Add("@parmPayingBranch", SqlDbType.VarChar, 10).Value = _branch;

                        var tvpParam = cmd.Parameters.AddWithValue("@Lines", BuildAutoDebitPaymentLineTVP(dlg, amount));
                        tvpParam.SqlDbType = SqlDbType.Structured;
                        tvpParam.TypeName = "dbo.AP_PaymentLineTVP";

                        con.Open();
                        cmd.ExecuteNonQuery();
                    }

                    using (var con = Database.getConnection())
                    using (var cmd = new SqlCommand("sp_BankRecon_ResolveAutoDebitItem", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.Add("@ReconID", SqlDbType.Int).Value = _selBankSideID;
                        cmd.Parameters.Add("@SupplierID", SqlDbType.VarChar, 50).Value = dlg.SelectedSupplierID;
                        cmd.Parameters.Add("@BatchReferenceID", SqlDbType.BigInt).Value = dlg.SelectedBatchReferenceID;
                        cmd.Parameters.Add("@InvoiceNo", SqlDbType.VarChar, 150).Value = dlg.SelectedInvoiceNo;
                        cmd.Parameters.Add("@ReferenceNo", SqlDbType.VarChar, 10).Value = referenceNo;
                        cmd.Parameters.Add("@VoucherID", SqlDbType.VarChar, 10).Value = voucherId;
                        cmd.Parameters.Add("@User", SqlDbType.VarChar, 50).Value = Login.Fullname;
                        con.Open();
                        cmd.ExecuteNonQuery();
                    }

                    LoadPeriod();
                    RefreshSummary();
                    SetStatus($"Payment {referenceNo} posted and item resolved.");
                }
                catch (SqlException ex)
                {
                    XtraMessageBox.Show(
                        $"Payment posting failed:\n{ex.Message}\n\nIf the payment itself succeeded but the resolve step failed, resolve this recon row manually — do not re-post, or the supplier will be paid twice.",
                        "Cannot Post Payment", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        // Single-row TVP for a SINGLE-mode invoice settlement — no EWT/
        // discount/offset splitting, sp_AddPaymentSupplierCompound's
        // SINGLE-mode branch just pays AmountPaid against PayableAccountCode.
        private DataTable BuildAutoDebitPaymentLineTVP(BankReconAutoDebitMatchForm dlg, decimal amount)
        {
            var dt = new DataTable();
            dt.Columns.Add("InvoiceNo", typeof(string));
            dt.Columns.Add("InvoiceDate", typeof(DateTime));
            dt.Columns.Add("SequenceReferenceNumber", typeof(string));
            dt.Columns.Add("BatchReferenceID", typeof(long));
            dt.Columns.Add("ActualCost", typeof(decimal));
            dt.Columns.Add("AmountPaid", typeof(decimal));
            dt.Columns.Add("EWTAmount", typeof(decimal));
            dt.Columns.Add("DiscountAmount", typeof(decimal));
            dt.Columns.Add("OffsetAmount", typeof(decimal));
            dt.Columns.Add("Description", typeof(string));

            dt.Rows.Add(
                dlg.SelectedInvoiceNo,
                dlg.SelectedExpenseDate,
                "",                          // SequenceReferenceNumber — unused in the EXPENSE flow
                dlg.SelectedBatchReferenceID,
                dlg.SelectedBalance,         // ActualCost — unused in SINGLE mode, kept for completeness
                amount,                      // AmountPaid — this is what SINGLE mode actually pays
                0m, 0m, 0m,                  // no EWT/discount/offset splitting in SINGLE mode
                dlg.SelectedDescription ?? "");

            return dt;
        }

        private void BtnAutoMatch_Click(object sender, EventArgs e)
        {
            if (_headerID == 0) { XtraMessageBox.Show("Load a period first."); return; }
            if (XtraMessageBox.Show("Auto-match outstanding checks against GL payments?\nMatched items will be marked Resolved.", "Auto-Match", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            try
            {
                int matched = 0;
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_BankRecon_AutoMatch", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 5).Value = _branch;
                    cmd.Parameters.Add("@AccountCode", SqlDbType.VarChar, 20).Value = _account;
                    cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = _period;
                    cmd.Parameters.Add("@User", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    con.Open();
                    using (var rdr = cmd.ExecuteReader())
                        if (rdr.Read()) matched = SafeInt(rdr["MatchedItems"]);
                }
                LoadPeriod(); RefreshSummary();
                SetStatus($"Auto-match: {matched} item(s) resolved.");
            }
            catch (SqlException ex) { SetStatus(ex.Message, err: true); }
        }

        private void BtnLock_Click(object sender, EventArgs e)
        {
            if (_headerID == 0) { XtraMessageBox.Show("Load a period first."); return; }
            if (XtraMessageBox.Show("Lock this reconciliation period?\nNo further changes will be allowed after locking.", "Lock Period", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_BankRecon_LockPeriod", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@HeaderID", SqlDbType.Int).Value = _headerID;
                    cmd.Parameters.Add("@LockedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    cmd.Parameters.Add("@StrictMode", SqlDbType.Bit).Value = true;
                    con.Open();
                    cmd.ExecuteNonQuery();
                }
                XtraMessageBox.Show("Period locked successfully.", "Locked", MessageBoxButtons.OK, MessageBoxIcon.Information);
                LoadPeriod(); RefreshSummary();
                SetStatus($"Period {_period:yyyy-MM-dd} locked by {Login.Fullname}.");
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message, "Cannot Lock", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        private void BtnPrint_Click(object sender, EventArgs e)
        {
            XtraMessageBox.Show("Wire to your XtraReport template here.", "Print", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private void SetStatus(string msg, bool err = false)
        {
            if (lblStatus == null) return;
            lblStatus.Text = msg;
            lblStatus.ForeColor = err ? C_ERR : C_MUTED;
            lblStatus.Appearance.Options.UseForeColor = true;
            Application.DoEvents();
        }

        private static decimal SafeDec(object v)
        {
            if (v == null || v == DBNull.Value) return 0m;
            return decimal.TryParse(v.ToString().Replace(",", ""), NumberStyles.Any, CultureInfo.InvariantCulture, out var r) ? r : 0m;
        }

        private static int SafeInt(object v) => v == null || v == DBNull.Value ? 0 : int.TryParse(v.ToString(), out var r) ? r : 0;

        private void btnLoad_Click(object sender, EventArgs e)
        {

        }

        private void btnAddOC_Click(object sender, EventArgs e)
        {

        }

        private void BankReconFormV2_Load(object sender, EventArgs e)
        {
            tabItems.TabPages[2].Hide();
        }

        private void btnResolveOC_Click(object sender, EventArgs e)
        {

        }

        private void gridOC_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStripOC.Show(gridOC, e.Location);
        }

        private void gridDIT_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStripDIT.Show(gridDIT, e.Location);
        }

        private void markAsClearedToolStripMenuItem_Click(object sender, EventArgs e)
        {
           
           BtnResolve_Click(_selOcID);
        }

        private void markAsClearedToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            BtnResolve_Click(_selDitID);
        }

        private void simpleButton1_Click(object sender, EventArgs e) => BtnAdd_Click("DIT");

        private void btnDeleteOC_Click(object sender, EventArgs e)
        {

        }

        private void markAsUnclearedToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            MarkAsUncleared(_selOcID);
        }

        private void markAsUnclearedToolStripMenuItem_Click(object sender, EventArgs e)
        {
            MarkAsUncleared(_selDitID);
        }

        private void btnPrint_Click_1(object sender, EventArgs e)
        {

        }

        private void panelControl6_Paint(object sender, PaintEventArgs e)
        {

        }
    }
}