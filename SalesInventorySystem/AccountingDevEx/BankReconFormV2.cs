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
        private decimal? _previewBankBal;   // 2026-10-12: the statement balance typed but not saved yet (null = none)
        private int _headerID = 0;
        // 2026-10-09: Export to Excel (the figures shown in the summary box, and the account name of the loaded period)
        private DevExpress.XtraEditors.SimpleButton btnExportXlsx;
        private string _accountName = "";
        private decimal _figDIT, _figOC, _figBCM, _figBDM;
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
            HandleDestroyed += (s, e) => WaitForTickSaves();   // 2026-10-10: closing the screen lets queued ticks finish
            WireEvents();
            PopulateLookups();
            SetDefaultPeriod();

            viewDIT.RowCellStyle += View_RowCellStyle;
            viewOC.RowCellStyle += View_RowCellStyle;
            viewBankSide.RowCellStyle += View_RowCellStyle;

            // 2026-10-02: one combined Deposits-in-Transit + Outstanding-Checks grid replaces the
            // side-by-side grids (built in code, the designer file stays untouched).
            BuildCombinedView();
        }

        private void View_RowCellStyle(object sender, RowCellStyleEventArgs e)
        {
            var v = (GridView)sender;
            if (e.RowHandle < 0) return;
            // 2026-10-06: leave the focused row to the skin. Painting it light kept the skin's white
            // selected-row text on a light background, which was unreadable.
            if (e.RowHandle == v.FocusedRowHandle) return;
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
            txtBankBal.EditValueChanged += TxtBankBal_EditValueChanged;   // 2026-10-12: live preview of the summary

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
            btnAutoMatch.Visible = false;   // 2026-10-08 (user): hidden, see btnAllAutoMatch
            chkSelectAllOC.CheckedChanged += ChkSelectAllOC_CheckedChanged;
            btnBulkResolveOC.Click += BtnBulkResolveOC_Click;

            btnAddBankSide.Click += (s, e) => BtnAdd_Click("BDM"); // dialog lets user switch to BCM/BC/NSF/ADB
            btnResolveBankSide.Click += (s, e) => BtnResolve_Click(_selBankSideID);
            btnDeleteBankSide.Click += (s, e) => BtnDelete_Click(_selBankSideID);
            btnPostAutoDebit.Click += BtnPostAutoDebit_Click;

            btnLock.Click += BtnLock_Click;
            btnPrint.Click += BtnPrint_Click;

            // 2026-10-09 (user): Export to Excel, next to Print in the footer
            btnExportXlsx = new DevExpress.XtraEditors.SimpleButton
            {
                Name = "btnExportXlsx",
                Text = "Export to Excel",
                Size = new System.Drawing.Size(124, btnPrint.Height),
                Location = new System.Drawing.Point(btnPrint.Right + 10, btnPrint.Top),
                Margin = btnPrint.Margin
            };
            btnExportXlsx.Click += BtnExportXlsx_Click;
            btnPrint.Parent?.Controls.Add(btnExportXlsx);

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

                // 2026-10-08c: an item cleared in a later month shows as open here; it must not be posted or deleted again
                bool clearedLater = has && viewBankSide.GetRowCellValue(viewBankSide.FocusedRowHandle, "ClearedPeriodEnd") is DateTime;

                btnResolveBankSide.Enabled = has && !isResolved && !_isLocked;
                btnDeleteBankSide.Enabled = has && !isResolved && !clearedLater && !_isLocked;
                // Post Payment only makes sense for an unresolved Auto-Debit Broker row
                btnPostAutoDebit.Enabled = has && !isResolved && !clearedLater && !_isLocked && _selBankSideType == "ADB";
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
            var picked = dtPeriod.EditValue is DateTime dt ? dt : DateTime.TryParse(dtPeriod.Text, out var pd) ? pd : DateTime.Today;
            // 2026-10-07: a recon period is a calendar month; client payments / vouchers file their items
            // under the month-end header, so any date picked means that month's end.
            picked = new DateTime(picked.Year, picked.Month, DateTime.DaysInMonth(picked.Year, picked.Month));
            if (!(dtPeriod.EditValue is DateTime cur) || cur.Date != picked) dtPeriod.EditValue = picked;

            if (string.IsNullOrWhiteSpace(_account))
            {
                XtraMessageBox.Show("Please select a bank GL account.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // 2026-10-08c: _period is the month the clear / unclear calls send as @PeriodEnd, so it only moves
            // to the picked month once that month is on screen; a failed load keeps the month still shown.
            var previous = _period;
            _period = picked;
            try
            {
                LoadPeriod();
                RefreshSummary();
                SetStatus($"Loaded: {_account}  |  Period: {_period:yyyy-MM-dd}" + (_isLocked ? "  |  LOCKED" : ""));
            }
            catch (SqlException ex)
            {
                _period = previous;
                SetStatus($"Load failed: {ex.Message}", err: true);
            }
        }

        private void LoadPeriod()
        {
            WaitForTickSaves();   // 2026-10-10: queued ticks are saved before anything is read back
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
                    _accountName = hdr.Table.Columns.Contains("AccountName") ? Convert.ToString(hdr["AccountName"]) : "";

                    lblBookBal.Text = _bookBal.ToString("N2");
                    _previewBankBal = null;   // a (re)load shows the saved balance
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

                BindCombined();   // the combined DIT + OC grid, from _dtDIT / _dtOC
                LoadSummary();    // 2026-10-06: the one-row-per-batch view (sp_BankRecon_GetPeriodSummary)
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
            SetCombinedLocked(locked);
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
            FormatCol(view, "ClearedPeriodEnd", 90, false, isDate: true);   // 2026-10-08c
            if (view.Columns["ClearedPeriodEnd"] != null) view.Columns["ClearedPeriodEnd"].Caption = "Cleared In";
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
            FormatCol(viewBankSide, "ClearedPeriodEnd", 90, false, isDate: true);   // 2026-10-08c
            if (viewBankSide.Columns["ClearedPeriodEnd"] != null) viewBankSide.Columns["ClearedPeriodEnd"].Caption = "Cleared In";
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
            // 2026-10-02e: sp_BankRecon_GetPeriod now returns the client payment's control
            // number (the deposit batch the user reconciles by), its CR No. and payment type.
            FormatCol(viewDIT, "CRNo", 100, false);
            FormatCol(viewDIT, "PaymentType", 70, false);
            if (viewDIT.Columns["ControlNo"] != null) viewDIT.Columns["ControlNo"].Caption = "Control No";
            if (viewDIT.Columns["CRNo"] != null) viewDIT.Columns["CRNo"].Caption = "CR No";
            if (viewDIT.Columns["ReferenceNo"] != null) viewDIT.Columns["ReferenceNo"].Caption = "Payment Ref";
            if (viewDIT.Columns["PaymentType"] != null) viewDIT.Columns["PaymentType"].Caption = "Type";

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
            int? resolved = ResolveReconIDsNoReload(ids, itemType);
            if (resolved == null) return;   // the error is already on the status bar
            LoadPeriod();
            RefreshSummary();
            SetStatus($"{resolved} item(s) marked cleared.");
        }

        // Clears the items without reloading; null when the proc failed (message shown).
        // 2026-10-06: split out so the summary view can clear DIT + OC with one reload and one message.
        private int? ResolveReconIDsNoReload(List<int> ids, string itemType)
        {
            _lastError = null;
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
                    cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = _period;   // 2026-10-08c: cleared in this month

                    con.Open();
                    using (var rdr = cmd.ExecuteReader())
                        if (rdr.Read()) resolved = SafeInt(rdr["ResolvedCount"]);
                }
                return resolved;
            }
            catch (SqlException ex) { _lastError = ex.Message; SetStatus(ex.Message, err: true); return null; }
        }

        private string _lastError;   // 2026-10-10: the last bulk-clear refusal, for the tick handlers' message

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

            // 2026-10-02f: sp_BankRecon_GetPeriod returns the issuing voucher's control no.,
            // cheque no., voucher no. and source for each outstanding cheque.
            if (viewOC.Columns["ControlNo"] != null) viewOC.Columns["ControlNo"].Caption = "Control No";
            if (viewOC.Columns["CheckNo"] != null) viewOC.Columns["CheckNo"].Caption = "Check No";
            if (viewOC.Columns["CVNo"] != null) viewOC.Columns["CVNo"].Caption = "CV #";
            if (viewOC.Columns["ReferenceNo"] != null) viewOC.Columns["ReferenceNo"].Caption = "Voucher No";
            if (viewOC.Columns["SourceModule"] != null) viewOC.Columns["SourceModule"].Caption = "Source";

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

            // 2026-10-12 (user): while a new statement balance is being typed, the summary shows it (preview, not saved)
            decimal bankBal = _previewBankBal ?? _bankBal;
            decimal adjBank = bankBal + dit - oc;
            decimal adjBook = _bookBal + bcm - bdm;
            decimal diff = adjBank - adjBook;
            bool balanced = Math.Abs(diff) < 0.01m;
            _figDIT = dit; _figOC = oc; _figBCM = bcm; _figBDM = bdm;   // for Export to Excel

            SetLbl(lblBankStmt, bankBal.ToString("N2"), _previewBankBal == null ? C_TEXT : C_GOLD);   // gold = typed, not saved yet
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

        // 2026-10-12 (user): typing the bank statement balance recomputes the summary at once, so the
        // Difference can be checked before Save. Nothing is saved: Save still writes it, and Lock / Export
        // use the saved balance. The typed figure shows in gold until it is saved.
        private void TxtBankBal_EditValueChanged(object sender, EventArgs e)
        {
            if (_headerID == 0 || _isLocked || _dtDIT == null || _dtOC == null || _dtBankSide == null) return;
            string text = txtBankBal.Text.Replace(",", "").Trim();
            if (!decimal.TryParse(text, NumberStyles.Any, CultureInfo.InvariantCulture, out var typed)) return;   // half-typed ("-", "")
            typed = Math.Round(typed, 2);
            _previewBankBal = typed == _bankBal ? (decimal?)null : typed;
            RefreshSummary();
            if (_previewBankBal != null)
                SetStatus($"Preview with statement balance {typed:N2} (saved: {_bankBal:N2}). Click Save to keep it.");
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
                _previewBankBal = null;
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
                    cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = _period;   // 2026-10-08c: cleared in this month
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
                    cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = _period;   // 2026-10-08c: only the month it was cleared in can unclear it
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

                // 2026-10-08c: re-read the row just before paying. The payment posts before the row is marked,
                // so a stale screen (another user cleared it, or it was cleared in a later month) would pay twice.
                try
                {
                    using (var con = Database.getConnection())
                    using (var cmd = new SqlCommand("SELECT ISNULL(IsResolved, 0) FROM dbo.BankStatementRecon WHERE ReconID = @ReconID", con))
                    {
                        cmd.Parameters.Add("@ReconID", SqlDbType.Int).Value = _selBankSideID;
                        con.Open();
                        object done = cmd.ExecuteScalar();
                        if (done == null || Convert.ToBoolean(done))
                        {
                            XtraMessageBox.Show("This auto-debit has already been cleared or no longer exists. Load the period again.",
                                "Post Payment", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                            LoadPeriod(); RefreshSummary();
                            return;
                        }
                    }
                }
                catch (SqlException ex) { SetStatus(ex.Message, err: true); return; }

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
                        cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = _period;   // 2026-10-08c: cleared in this month
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

        // ================================================================
        // EXPORT TO EXCEL (2026-10-09)
        // Exports what is on screen: the Summary or Detailed list of the Deposits in Transit &
        // Outstanding Checks tab, or the Bank-Side Items tab. Data-aware .xlsx (real numbers,
        // groups expanded, footer sums kept), with the period and the summary-box figures on top.
        // ================================================================
        // 2026-10-16 (user): Export offers the accountants' "Account Reconciliation Report" (D:\SQLREF\2.png,
        // Peachtree's layout) first; the grid export stays as the second choice.
        private void BtnExportXlsx_Click(object sender, EventArgs e)
        {
            if (_headerID == 0)
            {
                XtraMessageBox.Show("Load a period first.", "Export to Excel", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            var menu = new ContextMenuStrip();
            menu.Items.Add("Account Reconciliation Report (accountants' format)...", null, (s, ev) => ExportAccountReconReport());
            menu.Items.Add("Grid as shown on screen...", null, (s, ev) => ExportGridXlsx());
            menu.Closed += (s, ev) => BeginInvoke((Action)(() => menu.Dispose()));
            menu.Show(btnExportXlsx, new System.Drawing.Point(0, btnExportXlsx.Height));
        }

        private void ExportGridXlsx()
        {
            DevExpress.XtraGrid.GridControl grid;
            GridView view;
            string what;
            if (tabItems.SelectedTabPage == tabBankSide) { grid = gridBankSide; view = viewBankSide; what = "Bank-Side Items"; }
            else if (_summaryMode && gridSum != null) { grid = gridSum; view = viewSum; what = "Summary"; }
            else { grid = gridAll; view = viewAll; what = "Detailed"; }
            if (grid == null || view == null) return;

            using (var sfd = new SaveFileDialog
            {
                Filter = "Excel workbook (*.xlsx)|*.xlsx",
                FileName = $"BankRecon_{_account}_{_period:yyyy-MM}_{what.Replace(" ", "").Replace("-", "")}.xlsx"
            })
            {
                if (sfd.ShowDialog(this) != DialogResult.OK) return;

                // the tick-box column is for the screen only
                var sel = view.Columns["Selected"];
                int selIndex = sel != null && sel.Visible ? sel.VisibleIndex : -1;
                try
                {
                    if (selIndex >= 0) sel.Visible = false;

                    var options = new DevExpress.XtraPrinting.XlsxExportOptionsEx
                    {
                        ExportType = DevExpress.Export.ExportType.DataAware,
                        SheetName = what,
                        GroupState = DevExpress.Export.GroupState.ExpandAll
                    };
                    options.CustomizeSheetHeader += ev => AddExportHeader(ev.ExportContext, what);
                    grid.ExportToXlsx(sfd.FileName, options);
                }
                catch (Exception ex)
                {
                    XtraMessageBox.Show($"Export failed: {ex.Message}", "Export to Excel", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }
                finally
                {
                    if (selIndex >= 0) sel.VisibleIndex = selIndex;
                }

                SetStatus($"Exported to {sfd.FileName}");
                if (XtraMessageBox.Show("Exported. Open the file now?", "Export to Excel", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
                {
                    try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(sfd.FileName) { UseShellExecute = true }); }
                    catch (Exception ex) { SetStatus(ex.Message, err: true); }
                }
            }
        }

        // Rows above the exported table: the period and the same figures as the summary box.
        private void AddExportHeader(DevExpress.Printing.ExportHelpers.IExportContext ctx, string what)
        {
            var title = new DevExpress.Export.XlFormattingObject { Font = new DevExpress.Export.XlCellFont { Bold = true, Size = 14 } };
            var bold = new DevExpress.Export.XlFormattingObject { Font = new DevExpress.Export.XlCellFont { Bold = true } };
            var money = new DevExpress.Export.XlFormattingObject { FormatType = DevExpress.Utils.FormatType.Numeric, FormatString = "#,##0.00;-#,##0.00" };
            var moneyBold = new DevExpress.Export.XlFormattingObject { FormatType = DevExpress.Utils.FormatType.Numeric, FormatString = "#,##0.00;-#,##0.00", Font = new DevExpress.Export.XlCellFont { Bold = true } };
            DevExpress.Printing.ExportHelpers.CellObject C(object v, DevExpress.Export.XlFormattingObject f = null) =>
                new DevExpress.Printing.ExportHelpers.CellObject { Value = v, Formatting = f };

            decimal adjBank = _bankBal + _figDIT - _figOC;
            decimal adjBook = _bookBal + _figBCM - _figBDM;
            decimal diff = adjBank - adjBook;

            ctx.AddRow(new[] { C("Bank Reconciliation - " + what, title) });
            ctx.AddRow(new[] { C("Bank Account", bold), C(string.IsNullOrWhiteSpace(_accountName) ? _account : $"{_account} - {_accountName}") });
            ctx.AddRow(new[] { C("Branch", bold), C(_branch) });
            ctx.AddRow(new[] { C("Period End", bold), C(_period.ToString("yyyy-MM-dd")) });
            ctx.AddRow(new[] { C("Status", bold), C(_isLocked ? "LOCKED" : "OPEN") });
            ctx.AddRow(new[] { C("Exported", bold), C($"{DateTime.Now:yyyy-MM-dd HH:mm} by {Login.Fullname}") });
            ctx.AddRow();
            ctx.AddRow(new[] { C("Bank Statement Balance"), C(_bankBal, money) });
            ctx.AddRow(new[] { C("Add: Deposits in Transit"), C(_figDIT, money) });
            ctx.AddRow(new[] { C("Less: Outstanding Checks"), C(_figOC, money) });
            ctx.AddRow(new[] { C("Adjusted Bank Balance", bold), C(adjBank, moneyBold) });
            ctx.AddRow(new[] { C("GL Book Balance"), C(_bookBal, money) });
            ctx.AddRow(new[] { C("Add: Bank Credit Memos"), C(_figBCM, money) });
            ctx.AddRow(new[] { C("Less: Bank Debit Memos / Auto-Debits"), C(_figBDM, money) });
            ctx.AddRow(new[] { C("Adjusted Book Balance", bold), C(adjBook, moneyBold) });
            ctx.AddRow(new[] { C("Difference (Adjusted Bank - Adjusted Book)", bold), C(diff, moneyBold),
                               C(Math.Abs(diff) < 0.01m ? "RECONCILED" : "OUT OF BALANCE", bold) });
            ctx.AddRow();
        }

        // ================================================================
        // ACCOUNT RECONCILIATION REPORT (2026-10-16, user: the accountants' format, D:\SQLREF\2.png)
        // GL side from sp_rpt_BankRecon_GLMovement (script [99]): Beginning GL + Cash Receipts - Cash
        // Disbursements + Add (Less) Other = Ending GL (all branches, the month of the period). Bank side
        // from the items on screen, the same ones the summary box counts: open deposits in transit, open
        // outstanding checks, and the open bank-side items as "Add (Less) Other" (a bank credit memo is a
        // LESS here, debit memos / charges / NSF / auto-debits an ADD: the screen books them on the book
        // side, this layout brings the bank to the GL). Unreconciled difference = Ending GL - (Ending Bank
        // + deposits - checks + other) = minus the screen's Difference. Sheet 2 lists the GL lines by journal.
        // ================================================================
        private void ExportAccountReconReport()
        {
            if (_previewBankBal != null && _previewBankBal.Value != _bankBal)
            {
                XtraMessageBox.Show("The bank statement balance on screen is not saved yet.\n\nSave it first: the report uses the saved balance.",
                    "Account Reconciliation Report", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            string fileName;
            using (var sfd = new SaveFileDialog
            {
                Filter = "Excel workbook (*.xlsx)|*.xlsx",
                FileName = $"AccountReconciliation_{_account}_{_period:yyyy-MM}.xlsx"
            })
            {
                if (sfd.ShowDialog(this) != DialogResult.OK) return;
                fileName = sfd.FileName;
            }

            string error;
            Cursor.Current = Cursors.WaitCursor;
            try { error = WriteAccountReconReport(fileName); }
            catch (Exception ex) { error = $"Export failed: {ex.Message}"; }
            finally { Cursor.Current = Cursors.Default; }
            if (error != null)
            {
                XtraMessageBox.Show(error, "Account Reconciliation Report", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            SetStatus($"Exported to {fileName}");
            if (XtraMessageBox.Show("Exported. Open the file now?", "Account Reconciliation Report", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
            {
                try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(fileName) { UseShellExecute = true }); }
                catch (Exception ex) { SetStatus(ex.Message, err: true); }
            }
        }

        // Reads the GL side, builds the bank side from the loaded period and writes the workbook; returns null
        // when done, else the message to show (no dialogs here, so a harness can call it). The layout and the
        // workbook are Classes/AccountReconReport.cs, shared with Accounting Reports › Bank Reconciliation.
        private string WriteAccountReconReport(string fileName)
        {
            var report = new AccountReconReport { AccountCode = _account, PeriodEnd = _period, BankBalance = _bankBal };
            try
            {
                if (!report.TryLoadGLMovement())
                    return "This database does not have the report's procedure yet (script [99], sp_rpt_BankRecon_GLMovement).\n\nUse \"Grid as shown on screen\" until it is installed.";
            }
            catch (SqlException ex) { return $"Could not read the GL movement: {ex.Message}"; }
            catch (InvalidOperationException ex) { return ex.Message; }

            // bank side: the same open items as RefreshSummary
            foreach (DataRow r in _dtDIT.Rows)
                if (!(r["IsResolved"] is bool b && b)) report.AddItem("DIT", r);
            foreach (DataRow r in _dtOC.Rows)
                if (!(r["IsResolved"] is bool b && b)) report.AddItem("OC", r);
            foreach (DataRow r in _dtBankSide.Rows)
                if (!(r["IsResolved"] is bool b && b)) report.AddItem(Convert.ToString(r["ItemType"]), r);
            report.SortItems();

            if (_isLocked && Math.Abs(_bookBal - report.EndingGL) >= 0.01m)
                report.Notes.Add($"Note: the GL changed after this period was locked (locked GL balance {_bookBal:N2}, GL today {report.EndingGL:N2}).");
            report.Footer = $"Bank Recon {(_isLocked ? "LOCKED" : "OPEN")} | GL all branches | prepared {DateTime.Now:yyyy-MM-dd HH:mm} by {Login.Fullname}";

            report.WriteXlsx(fileName);
            return null;
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

        // ================================================================
        // COMBINED GRID: Deposits in Transit + Outstanding Checks (2026-10-02)
        // ================================================================
        // One grid replaces the side-by-side DIT / OC grids on the tab: a Kind column tells
        // the two apart, rows are grouped by Kind then Control No (count + total per group;
        // no grand total across kinds, since deposits add to and checks subtract from the
        // bank balance). _dtDIT / _dtOC still load as before (RefreshSummary uses them);
        // _dtAll is built from them after every LoadPeriod. Every action reuses the existing
        // single-item / bulk methods (BtnAdd_Click, BtnResolve_Click, MarkAsUncleared,
        // BtnDelete_Click, ResolveReconIDs, BtnAutoMatch_Click).
        private const string KIND_DIT = "Deposit in Transit";
        private const string KIND_OC = "Outstanding Check";

        private DevExpress.XtraGrid.GridControl gridAll;
        private GridView viewAll;
        private DataTable _dtAll = new DataTable();
        private int _selAllID = 0;
        private SimpleButton btnAllAddDIT, btnAllAddOC, btnAllResolve, btnAllUnresolve, btnAllDelete,
                             btnAllBulkResolve, btnAllResolveBatch, btnAllAutoMatch, btnAllCheckCtl;
        private ToolStripMenuItem miAllCheckCtl, miAllUncheckCtl, miAllResolve, miAllUnresolve, miAllResolveBatch;
        private CheckEdit chkAllSelect;
        private ContextMenuStrip cmsAll;

        private void BuildCombinedView()
        {
            tablePanel1.Visible = false;     // the two old grids and their button bars
            panelControl6.Visible = false;   // the old Outstanding-Check button bar
            tabOC.Text = "Deposits in Transit & Outstanding Checks";

            gridAll = new DevExpress.XtraGrid.GridControl { Dock = DockStyle.Fill };
            viewAll = new GridView(gridAll);
            gridAll.MainView = viewAll;
            gridAll.ViewCollection.Add(viewAll);

            viewAll.OptionsBehavior.Editable = true;   // only "Selected" is editable (set per column in BindCombined)
            viewAll.OptionsView.ShowGroupPanel = false;
            // 2026-10-06: a check box on each Control No group row ticks / unticks that whole batch
            _groupCheck.AllowGrayed = true;   // grey = part of the batch ticked
            _groupCheck.Appearance.BackColor = System.Drawing.Color.Transparent;
            _groupCheck.Appearance.Options.UseBackColor = true;
            viewAll.CustomDrawGroupRow += ViewAll_CustomDrawGroupRow;
            viewAll.MouseDown += ViewAll_MouseDown;
            viewAll.GroupRowCollapsing += (s, e) => { if (DateTime.Now < _boxClickedUntil) e.Allow = false; };   // a double-click on the box
            viewAll.GroupRowExpanding += (s, e) => { if (DateTime.Now < _boxClickedUntil) e.Allow = false; };    // doesn't fold the group
            viewAll.CellValueChanged += (s, e) =>
            {
                if (e.Column != null && e.Column.FieldName == "Selected") { _groupState = null; gridAll.Invalidate(); }
            };
            // 2026-10-10 (user): nothing is edited in place; the Cleared box is clicked (ViewAll_MouseDown) or Space on the row
            viewAll.ShowingEditor += (s, e) => e.Cancel = true;
            viewAll.KeyDown += (s, e) =>
            {
                if (e.KeyCode != Keys.Space || _isLocked) return;
                int h = viewAll.FocusedRowHandle;
                if (viewAll.IsDataRow(h)) ToggleItemCleared(SafeInt(viewAll.GetRowCellValue(h, "ReconID")));
                else if (viewAll.IsGroupRow(h) && GroupControlNo(h, out string t) is string c) ToggleBatchCleared(t, c);
                else return;
                e.Handled = true;
            };
            viewAll.OptionsView.ShowFooter = false;
            viewAll.OptionsSelection.EnableAppearanceFocusedCell = false;
            viewAll.RowCellStyle += View_RowCellStyle;
            viewAll.FocusedRowChanged += (s, e) => UpdateCombinedButtons();
            viewAll.CustomColumnDisplayText += (s, e) =>
            {
                if (e.Column != null && e.Column.FieldName == "ControlNo" && (e.Value == null || e.Value == DBNull.Value))
                    e.DisplayText = "(no control no.)";
            };

            cmsAll = new ContextMenuStrip();
            miAllCheckCtl = new ToolStripMenuItem("Check all in this Control No", null, (s, e) => CheckControlNoGroup(true));
            miAllUncheckCtl = new ToolStripMenuItem("Uncheck all in this Control No", null, (s, e) => CheckControlNoGroup(false));
            miAllResolve = new ToolStripMenuItem("Mark as Cleared", null, (s, e) => BtnResolve_Click(_selAllID));
            miAllUnresolve = new ToolStripMenuItem("Mark as Uncleared", null, (s, e) => MarkAsUncleared(_selAllID));
            // 2026-10-06 (user): same as the "Resolve Entire Batch (Control No)" button
            miAllResolveBatch = new ToolStripMenuItem("Clear Entire Batch (Control No)", null, (s, e) => BtnAllResolveBatch_Click(s, e));
            // 2026-10-09 (user): undo an accidental batch clear in one step
            miAllUnresolveBatch = new ToolStripMenuItem("Unclear Entire Batch (Control No)", null, (s, e) => BtnAllUnresolveBatch_Click(s, e));
            // 2026-10-10 (user): ticking the Cleared box (row) or the group box (batch) clears at once, so the
            // check / mark items are no longer on the menu; the whole-batch clear / unclear stays
            cmsAll.Items.AddRange(new ToolStripItem[] { miAllResolveBatch, miAllUnresolveBatch });
            gridAll.MouseUp += (s, e) =>
            {
                if (e.Button != MouseButtons.Right || _isLocked) return;
                // focus the row / group under the mouse first, so the menu acts on what was clicked
                var hit = viewAll.CalcHitInfo(e.Location);
                if (hit.InRow) viewAll.FocusedRowHandle = hit.RowHandle;
                UpdateCombinedButtons();
                bool hasCtl = !string.IsNullOrWhiteSpace(FocusedControlNo(out _));
                miAllCheckCtl.Enabled = hasCtl;
                miAllUncheckCtl.Enabled = hasCtl;
                miAllResolveBatch.Enabled = hasCtl;
                miAllUnresolveBatch.Enabled = hasCtl;
                miAllResolve.Enabled = _selAllID > 0;
                miAllUnresolve.Enabled = _selAllID > 0;
                if (hasCtl) cmsAll.Show(gridAll, e.Location);
            };

            var bar = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 40, Padding = new Padding(4), WrapContents = false, AutoScroll = true };
            // 2026-10-06: two displays; Summary (one row per Control No / CV #) is the default
            rgView = new RadioGroup { Width = 190, Height = 28, Margin = new Padding(3, 4, 12, 3) };
            rgView.Properties.Columns = 2;
            rgView.Properties.Items.Add(new DevExpress.XtraEditors.Controls.RadioGroupItem(true, "Summary"));
            rgView.Properties.Items.Add(new DevExpress.XtraEditors.Controls.RadioGroupItem(false, "Detailed"));
            rgView.EditValue = true;
            rgView.EditValueChanged += (s, e) => SetViewMode(Equals(rgView.EditValue, true));
            bar.Controls.Add(rgView);
            btnAllAddDIT = NewBarButton(bar, "Add Deposit in Transit", (s, e) => BtnAdd_Click("DIT"));
            btnAllAddOC = NewBarButton(bar, "Add Outstanding Check", (s, e) => BtnAdd_Click("OC"));
            btnAllResolve = NewBarButton(bar, "Mark Cleared", (s, e) => BtnResolve_Click(_selAllID));
            btnAllUnresolve = NewBarButton(bar, "Mark Uncleared", (s, e) => MarkAsUncleared(_selAllID));
            btnAllDelete = NewBarButton(bar, "Delete", (s, e) => BtnDelete_Click(_selAllID));
            chkAllSelect = new CheckEdit { Text = "Select All (visible)", Width = 140, Margin = new Padding(12, 6, 3, 3) };
            chkAllSelect.CheckedChanged += ChkAllSelect_CheckedChanged;
            bar.Controls.Add(chkAllSelect);
            btnAllCheckCtl = NewBarButton(bar, "Check Control No", (s, e) => CheckControlNoGroup(true));
            btnAllBulkResolve = NewBarButton(bar, "Bulk Resolve", BtnAllBulkResolve_Click);
            btnAllResolveBatch = NewBarButton(bar, "Resolve Entire Batch (Control No)", BtnAllResolveBatch_Click);
            btnAllUnresolveBatch = NewBarButton(bar, "Unclear Entire Batch (Control No)", BtnAllUnresolveBatch_Click);   // 2026-10-09
            btnAllBulkUnresolve = NewBarButton(bar, "Bulk Unclear", BtnAllBulkUnresolve_Click);                           // 2026-10-09
            btnAllAutoMatch = NewBarButton(bar, "Auto-Match Cleared Checks", BtnAutoMatch_Click);
            // 2026-10-08 (user): hidden. sp_BankRecon_AutoMatch clears an outstanding check when its own payment
            // is in the GL, not when the bank shows it, so it ticked cheques that never reached the bank.
            btnAllAutoMatch.Visible = false;

            BuildSummaryGrid();
            panelControl5.Controls.Add(gridAll);
            panelControl5.Controls.Add(gridSum);
            panelControl5.Controls.Add(bar);
            gridAll.BringToFront();   // Fill docks after the bottom bar
            gridSum.BringToFront();
            SetViewMode(true);

            UpdateCombinedButtons();
        }

        // ================================================================
        // 2026-10-06: SUMMARY VIEW -- one row per batch, no grouping
        //   Deposits in transit by Control No (Debit), outstanding checks by CV # (Credit);
        //   an item with no Control No / CV # is its own row. Data: sp_BankRecon_GetPeriodSummary
        //   (same items as sp_BankRecon_GetPeriod). Staff clear by row: a row's OpenReconIDs go to
        //   the existing sp_BankRecon_BulkResolveItems (ResolveReconIDs). "Detailed" switches back
        //   to the grouped grid above.
        // ================================================================
        private RadioGroup rgView;
        private bool _summaryMode;
        private DevExpress.XtraGrid.GridControl gridSum;
        private GridView viewSum;
        private DataTable _dtSum;
        private ContextMenuStrip cmsSum;
        private ToolStripMenuItem miSumClearBatch;
        // 2026-10-09: unclear (undo a clear) in one step
        private ToolStripMenuItem miSumUnclearBatch, miAllUnresolveBatch;
        private SimpleButton btnAllUnresolveBatch, btnAllBulkUnresolve;

        private void BuildSummaryGrid()
        {
            gridSum = new DevExpress.XtraGrid.GridControl { Dock = DockStyle.Fill };
            viewSum = new GridView(gridSum);
            gridSum.MainView = viewSum;
            gridSum.ViewCollection.Add(viewSum);

            viewSum.OptionsBehavior.Editable = true;   // only "Selected"
            viewSum.OptionsView.ShowGroupPanel = false;
            viewSum.OptionsCustomization.AllowGroup = false;
            viewSum.OptionsView.ShowFooter = true;
            viewSum.OptionsSelection.EnableAppearanceFocusedCell = false;
            Classes.DevXGridViewSettings.ApplyTotalsBandAppearance(viewSum);
            viewSum.FocusedRowChanged += (s, e) => UpdateCombinedButtons();
            // 2026-10-10 (user): the Cleared box is the action (tick = clear the batch, untick = unclear it), on the
            // click itself; nothing is edited in place
            viewSum.ShowingEditor += (s, e) => e.Cancel = true;
            viewSum.MouseDown += (s, e) =>
            {
                if (e.Button != MouseButtons.Left || _isLocked) return;
                var hit = viewSum.CalcHitInfo(e.Location);
                if (hit.InRowCell && hit.RowHandle >= 0 && hit.Column != null && hit.Column.FieldName == "IsCleared")
                    ToggleSummaryRow(viewSum.GetDataRow(hit.RowHandle));
            };
            viewSum.KeyDown += (s, e) =>
            {
                if (e.KeyCode != Keys.Space || _isLocked || viewSum.FocusedRowHandle < 0) return;
                ToggleSummaryRow(viewSum.GetDataRow(viewSum.FocusedRowHandle));
                e.Handled = true;
            };
            viewSum.RowStyle += (s, e) =>   // fully cleared batch: same soft green as the detailed view (focused row left to the skin)
            {
                if (e.RowHandle < 0 || e.RowHandle == viewSum.FocusedRowHandle) return;
                if (Convert.ToString(viewSum.GetRowCellValue(e.RowHandle, "Status")) != "CLEARED") return;
                e.Appearance.BackColor = ClearedBack;
                e.Appearance.BackColor2 = ClearedBack;
                e.Appearance.ForeColor = ClearedFore;
                e.HighPriority = true;
            };
            viewSum.CustomColumnDisplayText += (s, e) =>
            {
                if (e.ListSourceRowIndex < 0 || e.Column == null || e.Column.FieldName != "BatchNo" || !(e.Value == null || e.Value == DBNull.Value)) return;
                string type = Convert.ToString(viewSum.GetListSourceRowCellValue(e.ListSourceRowIndex, "ItemType"));
                e.DisplayText = type == "OC" ? "(no CV #)" : "(no control no.)";
            };

            cmsSum = new ContextMenuStrip();
            miSumClearBatch = new ToolStripMenuItem("Clear Entire Batch", null, (s, e) => BtnAllResolveBatch_Click(s, e));
            miSumUnclearBatch = new ToolStripMenuItem("Unclear Entire Batch", null, (s, e) => BtnAllUnresolveBatch_Click(s, e));   // 2026-10-09
            cmsSum.Items.Add(miSumClearBatch);
            cmsSum.Items.Add(miSumUnclearBatch);
            gridSum.MouseUp += (s, e) =>
            {
                if (e.Button != MouseButtons.Right || _isLocked) return;
                var hit = viewSum.CalcHitInfo(e.Location);
                if (!hit.InRow || hit.RowHandle < 0) return;
                viewSum.FocusedRowHandle = hit.RowHandle;
                miSumClearBatch.Enabled = !string.IsNullOrWhiteSpace(Convert.ToString(viewSum.GetRowCellValue(hit.RowHandle, "OpenReconIDs")));
                miSumUnclearBatch.Enabled = SafeInt(viewSum.GetRowCellValue(hit.RowHandle, "ClearedItems")) > 0;
                cmsSum.Show(gridSum, e.Location);
            };
        }

        private void SetViewMode(bool summary)
        {
            _summaryMode = summary && gridSum != null;
            if (_summaryMode && _sumStale && _headerID != 0) LoadSummary();   // 2026-10-10: items were ticked in the detailed view
            if (gridSum != null) gridSum.Visible = _summaryMode;
            gridAll.Visible = !_summaryMode;
            if (rgView != null && !Equals(rgView.EditValue, _summaryMode)) rgView.EditValue = _summaryMode;
            chkAllSelect.CheckedChanged -= ChkAllSelect_CheckedChanged;
            chkAllSelect.Checked = false;
            chkAllSelect.CheckedChanged += ChkAllSelect_CheckedChanged;
            UpdateCombinedButtons();
        }

        private bool _summaryUnavailable;   // set once the summary proc fails; Summary stays off until the form reopens
        private bool _sumStale;             // 2026-10-10: a tick in the detailed view changed items; reload the summary when shown

        private void LoadSummary()
        {
            if (viewSum == null || _summaryUnavailable) return;
            try
            {
                var dt = new DataTable();
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_BankRecon_GetPeriodSummary", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@BranchCode", SqlDbType.Char, 3).Value = _branch;
                    cmd.Parameters.Add("@AccountCode", SqlDbType.VarChar, 20).Value = _account;
                    cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = _period;
                    con.Open();
                    new SqlDataAdapter(cmd).Fill(dt);
                }
                var sel = new DataColumn("Selected", typeof(bool)) { DefaultValue = false };
                dt.Columns.Add(sel);
                sel.SetOrdinal(0);
                foreach (DataRow r in dt.Rows) r["Selected"] = false;
                // 2026-10-10: the batch's Cleared box = every item of the row cleared
                var clr = new DataColumn("IsCleared", typeof(bool)) { DefaultValue = false };
                dt.Columns.Add(clr);
                clr.SetOrdinal(1);
                foreach (DataRow r in dt.Rows) r["IsCleared"] = Convert.ToString(r["Status"]) == "CLEARED";
                _dtSum = dt;
                _sumStale = false;
                BindSummary();
            }
            catch (Exception ex)
            {
                // e.g. the proc isn't on this database yet: fall back to the detailed view, for good
                // (catching everything so a bad result shape can't stop LoadPeriod before the lock state is set)
                _summaryUnavailable = true;
                _dtSum = null;
                gridSum.DataSource = null;
                SetViewMode(false);
                rgView.Properties.Items[0].Enabled = false;
                rgView.ToolTip = "Summary view unavailable: " + ex.Message;
                XtraMessageBox.Show("The summary view is not available on this database, so the detailed view is shown.\n\n" + ex.Message,
                                    "Bank Recon", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        private void BindSummary()
        {
            viewSum.BeginUpdate();
            try
            {
                viewSum.Columns.Clear();
                gridSum.DataSource = _dtSum;
                viewSum.PopulateColumns();

                foreach (DevExpress.XtraGrid.Columns.GridColumn col in viewSum.Columns)
                    col.OptionsColumn.AllowEdit = false;   // 2026-10-10: the Cleared box is clicked, not edited

                var captions = new Dictionary<string, string>
                {
                    { "IsCleared", "Cleared" }, { "BatchNo", "Control No / CV #" }, { "LastDate", "Date" }, { "CRNo", "CR No" },
                    { "Items", "Items" }, { "ClearedItems", "Items Cleared" }
                };
                foreach (var kv in captions)
                    if (viewSum.Columns[kv.Key] != null) viewSum.Columns[kv.Key].Caption = kv.Value;
                // 2026-10-14 (user): show only these, in this order; every other column stays in the data (the
                // clearing logic reads them) but is hidden. Replaces the 2026-10-10 hide list.
                string[] shown = { "IsCleared", "LastDate", "BatchNo", "Payee", "Debit", "Credit", "Status" };
                foreach (DevExpress.XtraGrid.Columns.GridColumn col in viewSum.Columns)
                    col.Visible = Array.IndexOf(shown, col.FieldName) >= 0;
                for (int i = 0; i < shown.Length; i++)
                    if (viewSum.Columns[shown[i]] != null) viewSum.Columns[shown[i]].VisibleIndex = i;

                var colSel = viewSum.Columns["IsCleared"];
                var repo = new DevExpress.XtraEditors.Repository.RepositoryItemCheckEdit();
                // 2026-10-10: display only; a click on the cell toggles it (BuildSummaryGrid's MouseDown), no editor = no delay
                gridSum.RepositoryItems.Clear();
                gridSum.RepositoryItems.Add(repo);
                colSel.ColumnEdit = repo;
                colSel.OptionsColumn.AllowSort = DevExpress.Utils.DefaultBoolean.False;
                colSel.VisibleIndex = 0;

                foreach (string money in new[] { "Debit", "Credit" })
                {
                    var c = viewSum.Columns[money];
                    if (c == null) continue;
                    c.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                    c.DisplayFormat.FormatString = "N2";
                    c.AppearanceCell.Font = F_MONO;
                    c.AppearanceCell.Options.UseFont = true;
                    c.AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                    c.Summary.Clear();
                    c.Summary.Add(DevExpress.Data.SummaryItemType.Sum, money, "{0:N2}");
                }
                var colDate = viewSum.Columns["LastDate"];
                if (colDate != null)
                {
                    colDate.DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                    colDate.DisplayFormat.FormatString = "yyyy-MM-dd";
                }

                viewSum.BestFitColumns();
                colSel.Width = 55;
            }
            finally { viewSum.EndUpdate(); }

            chkAllSelect.CheckedChanged -= ChkAllSelect_CheckedChanged;
            chkAllSelect.Checked = false;
            chkAllSelect.CheckedChanged += ChkAllSelect_CheckedChanged;
            UpdateCombinedButtons();
        }

        private void UpdateSummaryButtons()
        {
            int h = viewSum.FocusedRowHandle;
            bool hasOpen = h >= 0 && !string.IsNullOrWhiteSpace(Convert.ToString(viewSum.GetRowCellValue(h, "OpenReconIDs")));
            bool open = !_isLocked && _headerID != 0;

            // single-item actions belong to the detailed view
            btnAllResolve.Visible = btnAllUnresolve.Visible = btnAllDelete.Visible = btnAllCheckCtl.Visible = false;
            btnAllAddDIT.Enabled = open;
            btnAllAddOC.Enabled = open;
            // 2026-10-10 (user): the Cleared box clears / unclears at once; no select-then-resolve step
            chkAllSelect.Visible = btnAllBulkResolve.Visible = false;
            btnAllResolveBatch.Text = "Clear Entire Batch";
            btnAllResolveBatch.Enabled = open && hasOpen;
            btnAllAutoMatch.Enabled = open;
            // 2026-10-09: undo the focused batch's clears; Bulk Unclear (ticked rows) is a detailed-view action
            btnAllUnresolveBatch.Text = "Unclear Entire Batch";
            btnAllUnresolveBatch.Enabled = open && h >= 0 && SafeInt(viewSum.GetRowCellValue(h, "ClearedItems")) > 0;
            btnAllBulkUnresolve.Visible = false;
        }

        // Ticked rows (Bulk Resolve), or the focused row (Clear Entire Batch).
        private List<DataRow> SummaryRows(bool selectedOnly)
        {
            viewSum.CloseEditor();
            viewSum.UpdateCurrentRow();
            var rows = new List<DataRow>();
            if (_dtSum == null) return rows;
            if (selectedOnly)
            {
                // visible rows only: a ticked row hidden by a column filter is not cleared
                for (int i = 0; i < viewSum.RowCount; i++)
                {
                    var r = viewSum.GetDataRow(viewSum.GetVisibleRowHandle(i));
                    if (r != null && r["Selected"] is bool sel && sel) rows.Add(r);
                }
            }
            else
            {
                var r = viewSum.GetDataRow(viewSum.FocusedRowHandle);
                if (r != null) rows.Add(r);
            }
            return rows;
        }

        // Clears every uncleared item behind the given summary rows, after a confirmation that spells out
        // what goes (same procs as the detailed view).
        private void SummaryResolve(List<DataRow> rows, string title)
        {
            var dit = new List<int>();
            var oc = new List<int>();
            int batches = 0;
            foreach (DataRow r in rows)
            {
                string ids = Convert.ToString(r["OpenReconIDs"]);
                if (string.IsNullOrWhiteSpace(ids)) continue;
                batches++;
                var target = Convert.ToString(r["ItemType"]) == "OC" ? oc : dit;
                foreach (string part in ids.Split(','))
                    if (int.TryParse(part.Trim(), out int id)) target.Add(id);
            }

            if (dit.Count + oc.Count == 0)
            {
                XtraMessageBox.Show(rows.Count == 0 ? "Tick the rows to clear first (or select a row for Clear Entire Batch)."
                                                    : "Everything in the selected row(s) is already cleared.");
                return;
            }

            string msg = $"Mark {dit.Count + oc.Count} uncleared item(s) in {batches} row(s) as cleared by the bank?\n\n" +
                         $"  Deposits in transit: {dit.Count}\n  Outstanding checks: {oc.Count}";
            if (XtraMessageBox.Show(msg, "Confirm " + title, MessageBoxButtons.YesNo,
                                    batches > 1 ? MessageBoxIcon.Warning : MessageBoxIcon.Question) != DialogResult.Yes)
                return;

            // one reload and one message for both kinds; stop at the first failure (its message stays)
            int done = 0;
            if (dit.Count > 0)
            {
                int? n = ResolveReconIDsNoReload(dit, "DIT");
                if (n == null) { LoadPeriod(); RefreshSummary(); return; }
                done += n.Value;
            }
            if (oc.Count > 0)
            {
                int? n = ResolveReconIDsNoReload(oc, "OC");
                if (n == null)
                {
                    LoadPeriod(); RefreshSummary();
                    SetStatus($"{done} deposit(s) in transit cleared, but the outstanding checks failed: see the message. Try again.", err: true);
                    return;
                }
                done += n.Value;
            }
            LoadPeriod();
            RefreshSummary();
            SetStatus($"{done} item(s) marked cleared.");
        }

        private static SimpleButton NewBarButton(FlowLayoutPanel bar, string text, EventHandler onClick)
        {
            var b = new SimpleButton { Text = text, AutoSize = true, Height = 28, Margin = new Padding(3) };
            b.Click += onClick;
            bar.Controls.Add(b);
            return b;
        }

        private static object Cell(DataRow r, string col) => r.Table.Columns.Contains(col) ? r[col] : DBNull.Value;

        private static object Blank2Null(object v) => v == null || v == DBNull.Value || string.IsNullOrWhiteSpace(v.ToString()) ? (object)DBNull.Value : v.ToString().Trim();

        // 2026-10-08c: the month an item was cleared in ("Aug 2026"); "(later)" when that month is after the
        // period on screen, where the item still counts as open.
        private object ClearedInText(object clearedPeriodEnd)
        {
            if (!(clearedPeriodEnd is DateTime d)) return DBNull.Value;
            return d.ToString("MMM yyyy") + (d.Date > _period.Date ? " (later)" : "");
        }

        private void BindCombined()
        {
            var dt = new DataTable();
            dt.Columns.Add("Selected", typeof(bool));
            dt.Columns.Add("Kind", typeof(string));
            dt.Columns.Add("ItemType", typeof(string));
            dt.Columns.Add("ReconID", typeof(int));
            dt.Columns.Add("ItemDate", typeof(DateTime));
            dt.Columns.Add("ControlNo", typeof(string));
            dt.Columns.Add("CRNo", typeof(string));
            dt.Columns.Add("CheckNo", typeof(string));
            dt.Columns.Add("CVNo", typeof(string));   // outstanding checks: the voucher's CV # (2026-10-02g)
            dt.Columns.Add("ReferenceNo", typeof(string));
            dt.Columns.Add("Payee", typeof(string));
            dt.Columns.Add("PaymentType", typeof(string));
            dt.Columns.Add("SourceModule", typeof(string));
            dt.Columns.Add("Amount", typeof(decimal));
            dt.Columns.Add("IsResolved", typeof(bool));
            dt.Columns.Add("ClearedIn", typeof(string));   // 2026-10-08c
            dt.Columns.Add("ResolvedReason", typeof(string));
            dt.Columns.Add("IsAutoInserted", typeof(bool));

            foreach (var src in new[] { new { Rows = _dtDIT, Type = "DIT", Kind = KIND_DIT }, new { Rows = _dtOC, Type = "OC", Kind = KIND_OC } })
            {
                if (src.Rows == null) continue;
                foreach (DataRow r in src.Rows.Rows)
                {
                    var n = dt.NewRow();
                    n["Selected"] = false;
                    n["Kind"] = src.Kind;
                    n["ItemType"] = src.Type;
                    n["ReconID"] = SafeInt(Cell(r, "ReconID"));
                    var d = Cell(r, "ItemDate");
                    n["ItemDate"] = d == DBNull.Value ? (object)DBNull.Value : Convert.ToDateTime(d);
                    n["ControlNo"] = Blank2Null(Cell(r, "ControlNo"));
                    n["CRNo"] = Blank2Null(Cell(r, "CRNo"));
                    n["CheckNo"] = Blank2Null(Cell(r, "CheckNo"));
                    n["CVNo"] = Blank2Null(Cell(r, "CVNo"));
                    n["ReferenceNo"] = Blank2Null(Cell(r, "ReferenceNo"));
                    n["Payee"] = Blank2Null(Cell(r, "Payee"));
                    n["PaymentType"] = Blank2Null(Cell(r, "PaymentType"));
                    n["SourceModule"] = Blank2Null(Cell(r, "SourceModule"));
                    n["Amount"] = SafeDec(Cell(r, "Amount"));
                    var res = Cell(r, "IsResolved");
                    n["IsResolved"] = res != DBNull.Value && Convert.ToBoolean(res);
                    n["ClearedIn"] = ClearedInText(Cell(r, "ClearedPeriodEnd"));
                    n["ResolvedReason"] = Blank2Null(Cell(r, "ResolvedReason"));
                    var auto = Cell(r, "IsAutoInserted");
                    n["IsAutoInserted"] = auto != DBNull.Value ? Convert.ToBoolean(auto) : n["SourceModule"] != DBNull.Value;
                    dt.Rows.Add(n);
                }
            }

            _dtAll = dt;
            _groupState = null;
            viewAll.BeginUpdate();
            try
            {
                viewAll.Columns.Clear();
                gridAll.DataSource = _dtAll;
                viewAll.PopulateColumns();

                foreach (DevExpress.XtraGrid.Columns.GridColumn col in viewAll.Columns)
                    col.OptionsColumn.AllowEdit = false;   // 2026-10-10: the Cleared box is clicked, not edited

                var captions = new Dictionary<string, string>
                {
                    { "ControlNo", "Control No" }, { "CRNo", "CR No" }, { "CheckNo", "Check No" }, { "CVNo", "CV #" },
                    { "ReferenceNo", "Payment Ref / Voucher No" }, { "PaymentType", "Pay Type" }, { "SourceModule", "Source" },
                    { "ItemDate", "Date" }, { "IsResolved", "Cleared" }, { "ClearedIn", "Cleared In" }, { "ResolvedReason", "Reason" }
                };
                foreach (var kv in captions)
                    if (viewAll.Columns[kv.Key] != null) viewAll.Columns[kv.Key].Caption = kv.Value;

                // 2026-10-06 (user): Check No, Pay Type and Source hidden too (still in the data / bulk-resolve logic)
                // 2026-10-10: "Selected" (tick, then Bulk Resolve) is replaced by the Cleared box itself
                foreach (string hide in new[] { "Selected", "ItemType", "IsAutoInserted", "ReconID", "CheckNo", "PaymentType", "SourceModule", "ReferenceNo" })
                    if (viewAll.Columns[hide] != null) viewAll.Columns[hide].Visible = false;

                var colSel = viewAll.Columns["IsResolved"];
                var repoCheck = new DevExpress.XtraEditors.Repository.RepositoryItemCheckEdit();
                // 2026-10-10: display only; a click on the cell toggles it (ViewAll_MouseDown), no editor = no delay
                gridAll.RepositoryItems.Clear();   // one editor, not one more per reload
                gridAll.RepositoryItems.Add(repoCheck);
                colSel.ColumnEdit = repoCheck;
                colSel.OptionsColumn.AllowSort = DevExpress.Utils.DefaultBoolean.False;
                colSel.VisibleIndex = 0;

                var colAmt = viewAll.Columns["Amount"];
                colAmt.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                colAmt.DisplayFormat.FormatString = "N2";
                colAmt.AppearanceCell.Font = F_MONO;
                colAmt.AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                colAmt.AppearanceCell.Options.UseFont = true;
                var colDate = viewAll.Columns["ItemDate"];
                colDate.DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                colDate.DisplayFormat.FormatString = "yyyy-MM-dd";

                // Kind, then Control No; count + total per group (Amount only, no cross-kind grand total)
                viewAll.Columns["Kind"].GroupIndex = 0;
                viewAll.Columns["ControlNo"].GroupIndex = 1;
                viewAll.GroupSummary.Clear();
                viewAll.GroupSummary.Add(DevExpress.Data.SummaryItemType.Count, "ReconID", null, "{0} item(s)");
                viewAll.GroupSummary.Add(DevExpress.Data.SummaryItemType.Sum, "Amount", null, "Total: {0:N2}");
                // group rows use DevExpress's default GroupFormat, whose {2} shows both summaries

                viewAll.BestFitColumns();
                colSel.Width = 55;
            }
            finally { viewAll.EndUpdate(); }
            // On load: Kind groups open, Control No groups closed (user, 2026-10-06), so the batches show
            // as one line each with their count / total; users open the ones they need.
            // After EndUpdate: inside BeginUpdate the groups aren't built yet.
            viewAll.CollapseAllGroups();
            for (int gh = -1; viewAll.IsValidRowHandle(gh); gh--)   // group row handles are -1, -2, ...
                if (viewAll.GetRowLevel(gh) == 0)
                    viewAll.SetRowExpanded(gh, true, false);         // not recursive: the Control No groups stay closed

            chkAllSelect.CheckedChanged -= ChkAllSelect_CheckedChanged;
            chkAllSelect.Checked = false;
            chkAllSelect.CheckedChanged += ChkAllSelect_CheckedChanged;
            UpdateCombinedButtons();
        }

        // The data row behind the focused row: itself, or (for a group row) its first child.
        private int FocusedDataRowHandle()
        {
            int h = viewAll.FocusedRowHandle;
            if (h == DevExpress.XtraGrid.GridControl.InvalidRowHandle) return h;
            return viewAll.IsGroupRow(h) ? viewAll.GetDataRowHandleByGroupRowHandle(h) : h;
        }

        private void UpdateCombinedButtons()
        {
            if (viewAll == null) return;
            if (_summaryMode) { UpdateSummaryButtons(); return; }
            btnAllResolveBatch.Text = "Clear Entire Batch (Control No)";
            // 2026-10-10 (user): the Cleared box (row) and the group box (batch) clear / unclear at once, so
            // Mark Cleared / Uncleared, Select All, Check Control No, Bulk Resolve and Bulk Unclear are hidden
            btnAllResolve.Visible = btnAllUnresolve.Visible = btnAllCheckCtl.Visible = false;
            chkAllSelect.Visible = btnAllBulkResolve.Visible = btnAllBulkUnresolve.Visible = false;
            btnAllDelete.Visible = true;
            int h = viewAll.FocusedRowHandle;
            bool isData = h >= 0 && viewAll.IsDataRow(h);
            _selAllID = isData ? SafeInt(viewAll.GetRowCellValue(h, "ReconID")) : 0;

            // Resolve Entire Batch / Check Control No: a row or a Control No group (level 1) with a real control number
            string ctl = FocusedControlNo(out _);

            bool open = !_isLocked && _headerID != 0;
            btnAllAddDIT.Enabled = open;
            btnAllAddOC.Enabled = open;
            btnAllResolve.Enabled = open && isData;
            btnAllUnresolve.Enabled = open && isData;
            btnAllDelete.Enabled = open && isData;
            chkAllSelect.Enabled = open;
            btnAllBulkResolve.Enabled = open;
            btnAllResolveBatch.Enabled = open && !string.IsNullOrWhiteSpace(ctl);
            btnAllCheckCtl.Enabled = open && !string.IsNullOrWhiteSpace(ctl);
            btnAllAutoMatch.Enabled = open;
            btnAllUnresolveBatch.Text = "Unclear Entire Batch (Control No)";
            btnAllUnresolveBatch.Enabled = open && !string.IsNullOrWhiteSpace(ctl);
        }

        // The control number (and kind) of the focused data row or Control No group row; null on a
        // Kind-level group row (level 0), so nothing spanning several control numbers is ever picked.
        private string FocusedControlNo(out string itemType)
        {
            itemType = null;
            int h = viewAll.FocusedRowHandle;
            if (h == DevExpress.XtraGrid.GridControl.InvalidRowHandle) return null;
            bool isData = h >= 0 && viewAll.IsDataRow(h);
            if (!isData && viewAll.GetRowLevel(h) < 1) return null;
            int dh = FocusedDataRowHandle();
            if (dh < 0) return null;
            itemType = Convert.ToString(viewAll.GetRowCellValue(dh, "ItemType"));
            string ctl = Convert.ToString(viewAll.GetRowCellValue(dh, "ControlNo"));
            return string.IsNullOrWhiteSpace(ctl) ? null : ctl;
        }

        // Ticks (or unticks) every uncleared item of the focused Control No -- same kind, whole grid,
        // collapsed groups included -- so a batch can be checked in one go and then Bulk Resolved.
        private void CheckControlNoGroup(bool check)
        {
            if (_isLocked) return;
            string type;
            string ctl = FocusedControlNo(out type);
            if (string.IsNullOrWhiteSpace(ctl)) { XtraMessageBox.Show("Select a row or a Control No group first."); return; }
            SetControlNoChecked(type, ctl, check);
        }

        private void SetControlNoChecked(string type, string ctl, bool check)
        {
            viewAll.CloseEditor();
            int n = 0;
            foreach (DataRow row in _dtAll.Rows)
            {
                if (Convert.ToString(row["ItemType"]) != type || Convert.ToString(row["ControlNo"]) != ctl) continue;
                if (check && row["IsResolved"] is bool done && done) continue;   // cleared items can't be resolved again
                row["Selected"] = check;
                n++;
            }
            // no RefreshData(): the edits reach the view through the binding, and a refresh would
            // reopen every group the user had collapsed
            _groupState = null;
            gridAll.Invalidate();
            SetStatus($"{(check ? "Checked" : "Unchecked")} {n} item(s) under Control No '{ctl}'.");
        }

        // ---- 2026-10-06: check box on the Control No group rows (level 1) ----
        // Not on Kind rows (level 0) or on the "(no control no.)" group: those aren't one batch,
        // same rule as Check Control No / Resolve Entire Batch.
        private readonly DevExpress.XtraEditors.Repository.RepositoryItemCheckEdit _groupCheck =
            new DevExpress.XtraEditors.Repository.RepositoryItemCheckEdit();

        // The kind and control number behind a Control No group row (level 1); "" = the "(no control no.)" group.
        private bool GroupKey(int groupRowHandle, out string itemType, out string ctl)
        {
            itemType = null; ctl = null;
            if (!viewAll.IsGroupRow(groupRowHandle) || viewAll.GetRowLevel(groupRowHandle) != 1) return false;
            int dh = viewAll.GetDataRowHandleByGroupRowHandle(groupRowHandle);
            if (dh < 0) return false;
            itemType = Convert.ToString(viewAll.GetRowCellValue(dh, "ItemType"));
            ctl = Convert.ToString(viewAll.GetRowCellValue(dh, "ControlNo")).Trim();
            return true;
        }

        // The batch behind a group row: its kind and control number, or null when it has no check box.
        private string GroupControlNo(int groupRowHandle, out string itemType)
        {
            string ctl;
            if (!GroupKey(groupRowHandle, out itemType, out ctl)) return null;
            return ctl.Length == 0 ? null : ctl;
        }

        // Per batch (ItemType|ControlNo): [0] uncleared items, [1] of them ticked, [2] all items.
        // Built once per change (reload, a tick, a box click), not on every paint.
        private Dictionary<string, int[]> _groupState;
        private DateTime _boxClickedUntil = DateTime.MinValue;

        private int[] GroupState(string type, string ctl)
        {
            if (_groupState == null)
            {
                var map = new Dictionary<string, int[]>(StringComparer.Ordinal);
                foreach (DataRow row in _dtAll.Rows)
                {
                    string key = Convert.ToString(row["ItemType"]) + "|" + Convert.ToString(row["ControlNo"]).Trim();
                    if (!map.TryGetValue(key, out var c)) map[key] = c = new int[3];
                    c[2]++;
                    if (row["IsResolved"] is bool done && done) continue;
                    c[0]++;
                    if (row["Selected"] is bool sel && sel) c[1]++;
                }
                _groupState = map;
            }
            return _groupState.TryGetValue(type + "|" + ctl, out var s) ? s : new int[3];
        }

        // Highlights (2026-10-06): Kind rows bold; a Control No row whose items are all CLEARED soft green.
        private System.Drawing.Font _kindFont, _kindFontBase;
        private static readonly System.Drawing.Color ClearedBack = System.Drawing.Color.FromArgb(226, 239, 218);
        private static readonly System.Drawing.Color ClearedFore = System.Drawing.Color.FromArgb(56, 87, 35);
        private static readonly System.Drawing.Color KindBack = System.Drawing.Color.FromArgb(214, 228, 245);
        private static readonly System.Drawing.Color KindFore = System.Drawing.Color.FromArgb(31, 56, 100);

        // Checked = every uncleared item of the batch is ticked (and there is at least one).
        private bool IsControlNoChecked(string type, string ctl)
        {
            var s = GroupState(type, ctl);
            return s[0] > 0 && s[1] == s[0];
        }

        // Where the check box sits: just right of the group row's expand button.
        private static System.Drawing.Rectangle GroupCheckBounds(DevExpress.XtraGrid.Views.Grid.ViewInfo.GridGroupRowInfo info)
        {
            var b = info.ButtonBounds;
            int size = Math.Max(14, Math.Min(18, info.Bounds.Height - 4));
            return new System.Drawing.Rectangle(b.Right + 4, info.Bounds.Top + (info.Bounds.Height - size) / 2, size, size);
        }

        private void ViewAll_CustomDrawGroupRow(object sender, DevExpress.XtraGrid.Views.Base.RowObjectCustomDrawEventArgs e)
        {
            var info = e.Info as DevExpress.XtraGrid.Views.Grid.ViewInfo.GridGroupRowInfo;
            if (info == null || _dtAll == null) return;

            if (viewAll.GetRowLevel(e.RowHandle) == 0)   // Kind row: bold, default drawing
            {
                var baseFont = e.Appearance.Font;
                if (_kindFont == null || !ReferenceEquals(_kindFontBase, baseFont))
                {
                    _kindFont?.Dispose();
                    _kindFontBase = baseFont;
                    _kindFont = new System.Drawing.Font(baseFont, System.Drawing.FontStyle.Bold);
                }
                e.Appearance.Font = _kindFont;
                e.Appearance.BackColor = KindBack;    // highlighted band (user, 2026-10-06); fore + back both set,
                e.Appearance.BackColor2 = KindBack;   // so it stays readable in any skin (Black included)
                e.Appearance.ForeColor = KindFore;
                return;
            }

            string type, ctl;
            if (!GroupKey(e.RowHandle, out type, out ctl)) return;
            var s = GroupState(type, ctl);
            if (s[2] > 0 && s[0] == 0)   // every item of this Control No is cleared
            {
                e.Appearance.BackColor = ClearedBack;
                e.Appearance.BackColor2 = ClearedBack;
                e.Appearance.ForeColor = ClearedFore;
            }

            // check box: not while locked, not on "(no control no.)"
            // 2026-10-10: it shows the batch's cleared state (ticked = all cleared, grey = part) and clicking it
            // clears / unclears the batch at once
            if (_isLocked || ctl.Length == 0 || s[2] == 0) return;

            var r = GroupCheckBounds(info);
            // room for the box: as many spaces as its width needs in this font (follows DPI / skin font)
            var font = e.Appearance.Font ?? info.Appearance.Font;
            float space = e.Cache.Graphics.MeasureString("x x", font).Width - e.Cache.Graphics.MeasureString("xx", font).Width;
            int pad = space > 0 ? (int)Math.Ceiling((r.Width + 6) / space) : 6;
            info.GroupText = new string(' ', pad) + info.GroupText.TrimStart();
            e.DefaultDraw();

            if (_groupCheckInfo == null)
            {
                _groupCheckInfo = (DevExpress.XtraEditors.ViewInfo.CheckEditViewInfo)_groupCheck.CreateViewInfo();
                _groupCheckPainter = (DevExpress.XtraEditors.Drawing.CheckEditPainter)_groupCheck.CreatePainter();
            }
            _groupCheckInfo.EditValue = s[0] == 0 ? (object)true : s[0] < s[2] ? null : (object)false;   // null = grey (part cleared)
            _groupCheckInfo.Bounds = r;
            _groupCheckInfo.CalcViewInfo(e.Cache.Graphics);
            _groupCheckPainter.Draw(new DevExpress.XtraEditors.Drawing.ControlGraphicsInfoArgs(_groupCheckInfo, e.Cache, r));
            e.Handled = true;
        }

        private DevExpress.XtraEditors.ViewInfo.CheckEditViewInfo _groupCheckInfo;
        private DevExpress.XtraEditors.Drawing.CheckEditPainter _groupCheckPainter;

        private void ViewAll_MouseDown(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left || _isLocked || _dtAll == null) return;
            var hit = viewAll.CalcHitInfo(e.Location);
            // 2026-10-10: a click on an item's Cleared box toggles it at once (the row still gets the focus)
            if (hit.InRowCell && hit.Column != null && hit.Column.FieldName == "IsResolved" && viewAll.IsDataRow(hit.RowHandle))
            {
                ToggleItemCleared(SafeInt(viewAll.GetRowCellValue(hit.RowHandle, "ReconID")));
                return;
            }
            if (!hit.InGroupRow) return;
            var gvi = viewAll.GetViewInfo() as DevExpress.XtraGrid.Views.Grid.ViewInfo.GridViewInfo;
            var info = gvi?.GetGridRowInfo(hit.RowHandle) as DevExpress.XtraGrid.Views.Grid.ViewInfo.GridGroupRowInfo;
            if (info == null) return;
            string type;
            string ctl = GroupControlNo(hit.RowHandle, out type);
            if (ctl == null || !GroupCheckBounds(info).Contains(e.Location)) return;
            if (GroupState(type, ctl)[2] == 0) return;

            _boxClickedUntil = DateTime.Now.AddMilliseconds(SystemInformation.DoubleClickTime);
            viewAll.FocusedRowHandle = hit.RowHandle;
            UpdateCombinedButtons();
            DevExpress.Utils.DXMouseEventArgs.GetMouseArgs(e).Handled = true;   // don't also expand / collapse the group
            // 2026-10-10: empty or grey -> clear the rest of the batch; ticked -> unclear it (on screen at once, saved in the background)
            ToggleBatchCleared(type, ctl);
        }

        // ================================================================
        // 2026-10-10 (user): TICK = CLEARED, at once and without waiting
        //   A click on an item's Cleared box (detailed view; Space on the focused row too), on a Control No
        //   group's box, or on a batch row's Cleared box (summary view) clears it in the month on screen;
        //   another click unclears it. No confirmation: an untick undoes a tick.
        //   Seamless (user, same day: "the user will tick fast"): the box and the figures change on the
        //   click itself, and the database write goes into a queue that a background worker sends in
        //   click order (sp_BankRecon_ResolveItem for one item, the bulk resolve / unresolve procs for a
        //   batch: the same rules as before). If the database refuses or skips anything, the period is
        //   reloaded once the queue is empty, so the screen shows what was saved, and the reason is shown.
        //   The worker touches no control (Known Bug #8): it only runs SQL and posts its results back.
        //   LoadPeriod waits for the queue first, so a reload never shows a half-saved state.
        // ================================================================
        private sealed class TickOp
        {
            public List<int> Ids;      // Bulk = false: one id, sp_BankRecon_ResolveItem
            public bool Clear;
            public bool Bulk;
            public string ItemType;    // bulk resolve: DIT / OC
            public DateTime Period;
            public string User;
            public string What;        // for messages
        }

        private readonly Queue<TickOp> _tickQueue = new Queue<TickOp>();
        private readonly object _tickLock = new object();
        private readonly List<string> _tickProblems = new List<string>();
        private System.Threading.Tasks.Task _tickWorker = System.Threading.Tasks.Task.FromResult(0);
        private bool _tickRunning;
        private int _tickPending;

        // An item's box: flip it on screen, queue the save.
        private void ToggleItemCleared(int reconID)
        {
            if (_isLocked || _headerID == 0 || reconID <= 0 || _dtAll == null) return;
            DataRow row = null;
            foreach (DataRow r in _dtAll.Rows)
                if (SafeInt(r["ReconID"]) == reconID) { row = r; break; }
            if (row == null) return;

            // cleared in a later month: shown open here, and only that month can change it (same rule as the proc, 93013)
            string clearedIn = Convert.ToString(row["ClearedIn"]);
            if (clearedIn.EndsWith("(later)"))
            {
                XtraMessageBox.Show($"This item was cleared in {clearedIn.Replace(" (later)", "")}. Open that month and untick it there first.",
                                    "Bank Recon", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            bool clear = !(row["IsResolved"] is bool b && b);
            string what = $"{Convert.ToString(row["Kind"])} {SafeDec(row["Amount"]):N2}";
            ApplyClearedLocally(new List<int> { reconID }, clear);
            EnqueueTick(new TickOp { Ids = new List<int> { reconID }, Clear = clear, Bulk = false, What = what });
        }

        // Group box: clears what is still open in the batch, or (all cleared) unclears the whole batch.
        private void ToggleBatchCleared(string type, string ctl)
        {
            if (_isLocked || _headerID == 0 || _dtAll == null) return;
            bool clear = GroupState(type, ctl)[0] > 0;
            var ids = new List<int>();
            foreach (DataRow row in _dtAll.Rows)
            {
                if (Convert.ToString(row["ItemType"]) != type || Convert.ToString(row["ControlNo"]).Trim() != ctl) continue;
                bool done = row["IsResolved"] is bool d && d;
                if (done != clear) ids.Add(SafeInt(row["ReconID"]));
            }
            if (ids.Count == 0) return;
            ApplyClearedLocally(ids, clear);
            EnqueueTick(new TickOp { Ids = ids, Clear = clear, Bulk = true, ItemType = type, What = $"Control No '{ctl}'" });
        }

        // Summary view: a batch row's box.
        private void ToggleSummaryRow(DataRow sumRow)
        {
            if (_isLocked || _headerID == 0 || sumRow == null) return;
            bool clear = !(sumRow["IsCleared"] is bool b && b);
            var ids = SummaryRowItems(sumRow, cleared: !clear);   // clear: its open items; unclear: its cleared ones
            if (ids.Count == 0) return;
            string batch = Convert.ToString(sumRow["BatchNo"]);
            ApplyClearedLocally(ids, clear);
            EnqueueTick(new TickOp { Ids = ids, Clear = clear, Bulk = true, ItemType = Convert.ToString(sumRow["ItemType"]) == "OC" ? "OC" : "DIT",
                                     What = string.IsNullOrWhiteSpace(batch) ? "the selected row" : $"batch '{batch}'" });
        }

        // The batch a source item belongs to in the summary view: Control No (DIT) / CV # (OC), else the item
        // itself. Same keys as sp_BankRecon_GetPeriodSummary's BatchKey (see CollectSummaryCleared).
        private static string SummaryKey(DataRow src, bool isOC)
        {
            string field = isOC ? "CVNo" : "ControlNo";
            string no = src.Table.Columns.Contains(field) ? Convert.ToString(src[field]).Trim() : "";
            return no.Length > 0 ? "NO:" + no : "ID:" + SafeInt(src["ReconID"]);
        }

        // The items behind a summary row that are cleared (cleared = true) or still open (false).
        private List<int> SummaryRowItems(DataRow sumRow, bool cleared)
        {
            var ids = new List<int>();
            bool isOC = Convert.ToString(sumRow["ItemType"]) == "OC";
            DataTable src = isOC ? _dtOC : _dtDIT;
            if (src == null) return ids;
            string key = Convert.ToString(sumRow["BatchKey"]).Trim();
            foreach (DataRow r in src.Rows)
            {
                bool done = r["IsResolved"] is bool d && d;
                if (done == cleared && SummaryKey(r, isOC) == key) ids.Add(SafeInt(r["ReconID"]));
            }
            return ids;
        }

        // Shows the change at once: the item rows (sources and the detailed grid), the summary rows involved,
        // the group boxes and the figures. Mirrors what the procs write (IsResolved, ResolvedReason 'CLEARED' /
        // NULL, ClearedPeriodEnd = this month / NULL).
        private void ApplyClearedLocally(List<int> ids, bool clear)
        {
            var set = new HashSet<int>(ids);
            object reason = clear ? (object)"CLEARED" : DBNull.Value;
            object month = clear ? (object)new DateTime(_period.Year, _period.Month, DateTime.DaysInMonth(_period.Year, _period.Month)) : DBNull.Value;
            var keys = new HashSet<string>(StringComparer.Ordinal);   // summary rows to recount ("DIT|NO:123")

            foreach (var src in new[] { _dtDIT, _dtOC })
            {
                if (src == null || !src.Columns.Contains("ReconID")) continue;
                bool isOC = ReferenceEquals(src, _dtOC);
                foreach (DataRow r in src.Rows)
                {
                    if (!set.Contains(SafeInt(r["ReconID"]))) continue;
                    r["IsResolved"] = clear;
                    if (src.Columns.Contains("ResolvedReason")) r["ResolvedReason"] = reason;
                    if (src.Columns.Contains("ClearedPeriodEnd")) r["ClearedPeriodEnd"] = month;
                    keys.Add((isOC ? "OC|" : "DIT|") + SummaryKey(r, isOC));
                }
            }
            foreach (DataRow r in _dtAll.Rows)
            {
                if (!set.Contains(SafeInt(r["ReconID"]))) continue;
                r["IsResolved"] = clear;
                r["ResolvedReason"] = reason;
                r["ClearedIn"] = ClearedInText(month);
            }
            if (_dtSum != null && keys.Count > 0) RecountSummaryRows(keys);

            _groupState = null;
            RefreshSummary();
            gridAll.Invalidate();
        }

        // Status / Cleared count / open items of the summary rows whose batch changed (same rules as the proc).
        private void RecountSummaryRows(HashSet<string> keys)
        {
            var count = new Dictionary<string, int[]>(StringComparer.Ordinal);          // [0] items, [1] cleared
            var open = new Dictionary<string, List<int>>(StringComparer.Ordinal);
            var openAmt = new Dictionary<string, decimal>(StringComparer.Ordinal);
            foreach (var src in new[] { _dtDIT, _dtOC })
            {
                if (src == null || !src.Columns.Contains("ReconID")) continue;
                bool isOC = ReferenceEquals(src, _dtOC);
                foreach (DataRow r in src.Rows)
                {
                    string k = (isOC ? "OC|" : "DIT|") + SummaryKey(r, isOC);
                    if (!keys.Contains(k)) continue;
                    if (!count.TryGetValue(k, out var c)) { count[k] = c = new int[2]; open[k] = new List<int>(); openAmt[k] = 0m; }
                    c[0]++;
                    if (r["IsResolved"] is bool d && d) c[1]++;
                    else { open[k].Add(SafeInt(r["ReconID"])); openAmt[k] += SafeDec(r["Amount"]); }
                }
            }
            foreach (DataRow s in _dtSum.Rows)
            {
                string k = (Convert.ToString(s["ItemType"]) == "OC" ? "OC|" : "DIT|") + Convert.ToString(s["BatchKey"]).Trim();
                if (!count.TryGetValue(k, out var c)) continue;
                s["ClearedItems"] = c[1];
                s["Status"] = c[1] == c[0] ? "CLEARED" : c[1] > 0 ? "PARTLY CLEARED" : "OPEN";
                s["IsCleared"] = c[1] == c[0];
                if (_dtSum.Columns.Contains("OpenReconIDs")) s["OpenReconIDs"] = open[k].Count == 0 ? (object)DBNull.Value : string.Join(",", open[k]);
                if (_dtSum.Columns.Contains("OpenAmount")) s["OpenAmount"] = openAmt[k];
            }
        }

        private void EnqueueTick(TickOp op)
        {
            op.Period = _period;
            op.User = Login.Fullname;
            lock (_tickLock)
            {
                _tickQueue.Enqueue(op);
                _tickPending++;
                if (!_tickRunning)
                {
                    _tickRunning = true;
                    _tickWorker = System.Threading.Tasks.Task.Run(() => DrainTicks());
                }
            }
            ShowTickStatus();
        }

        // Background worker: SQL only, in click order; results go back to the UI thread by BeginInvoke.
        private void DrainTicks()
        {
            while (true)
            {
                TickOp op;
                lock (_tickLock)
                {
                    if (_tickQueue.Count == 0) { _tickRunning = false; break; }
                    op = _tickQueue.Dequeue();
                }
                string problem;
                try { problem = SaveTick(op); }
                catch (Exception ex) { problem = $"{op.What}: {ex.Message}"; }   // a refusal (SqlException) or a lost connection
                lock (_tickLock)
                {
                    _tickPending--;
                    if (problem != null) _tickProblems.Add(problem);
                }
                PostToUi(ShowTickStatus);
            }
            PostToUi(OnTicksSaved);
        }

        // One queued change; null = saved exactly as clicked, else what differed.
        private static string SaveTick(TickOp op)
        {
            var dtIds = new DataTable();
            dtIds.Columns.Add("ReconID", typeof(int));
            foreach (int id in op.Ids) dtIds.Rows.Add(id);

            using (var con = Database.getConnection())
            {
                con.Open();
                if (!op.Bulk)
                {
                    using (var cmd = new SqlCommand("sp_BankRecon_ResolveItem", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.Add("@ReconID", SqlDbType.Int).Value = op.Ids[0];
                        cmd.Parameters.Add("@IsResolved", SqlDbType.Bit).Value = op.Clear;
                        cmd.Parameters.Add("@ResolvedBy", SqlDbType.VarChar, 50).Value = op.User;
                        cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = op.Period;
                        cmd.ExecuteNonQuery();
                    }
                    return null;
                }
                if (op.Clear)
                {
                    using (var cmd = new SqlCommand("sp_BankRecon_BulkResolveItems", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        var p = cmd.Parameters.Add("@ReconIDs", SqlDbType.Structured);
                        p.TypeName = "dbo.tt_BankReconIDList";
                        p.Value = dtIds;
                        cmd.Parameters.Add("@ResolvedBy", SqlDbType.VarChar, 50).Value = op.User;
                        cmd.Parameters.Add("@ItemType", SqlDbType.VarChar, 5).Value = op.ItemType;
                        cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = op.Period;
                        int n = 0;
                        using (var rdr = cmd.ExecuteReader())
                            if (rdr.Read()) n = SafeInt(rdr["ResolvedCount"]);
                        return n == op.Ids.Count ? null
                             : $"{op.What}: {op.Ids.Count - n} of {op.Ids.Count} item(s) were left as they are (already cleared in another month).";
                    }
                }
                using (var cmd = new SqlCommand("sp_BankRecon_BulkUnresolveItems", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    var p = cmd.Parameters.Add("@ReconIDs", SqlDbType.Structured);
                    p.TypeName = "dbo.tt_BankReconIDList";
                    p.Value = dtIds;
                    cmd.Parameters.Add("@ResolvedBy", SqlDbType.VarChar, 50).Value = op.User;
                    cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = op.Period;
                    int done = 0, otherMonth = 0, system = 0;
                    using (var rdr = cmd.ExecuteReader())
                        if (rdr.Read())
                        {
                            done = SafeInt(rdr["UnclearedCount"]);
                            otherMonth = SafeInt(rdr["SkippedOtherMonth"]);
                            system = SafeInt(rdr["SkippedSystem"]);
                        }
                    if (done == op.Ids.Count) return null;
                    string why = otherMonth > 0 ? $"{otherMonth} cleared in another month (untick them in that month)" : "";
                    if (system > 0) why += (why.Length > 0 ? ", " : "") + $"{system} closed by a reversal or a posted auto-debit";
                    return $"{op.What}: {op.Ids.Count - done} of {op.Ids.Count} item(s) were left cleared" + (why.Length > 0 ? $" ({why})." : ".");
                }
            }
        }

        private void PostToUi(Action a)
        {
            try { if (!IsDisposed && IsHandleCreated) BeginInvoke(a); }
            catch (InvalidOperationException) { }   // the screen is closing
        }

        private void ShowTickStatus()
        {
            int n;
            lock (_tickLock) n = _tickPending;
            if (n > 0) SetStatus($"Saving {n} change(s)…");
        }

        // The queue is empty: done, or (something was refused / skipped) reload and say why.
        private void OnTicksSaved()
        {
            List<string> problems;
            lock (_tickLock)
            {
                if (_tickRunning || _tickPending > 0) return;   // more clicks came in; their worker reports
                problems = new List<string>(_tickProblems);
                _tickProblems.Clear();
            }
            if (problems.Count == 0) { SetStatus("All changes saved."); return; }

            ReloadKeepingView();
            var shown = problems.Count > 12 ? problems.GetRange(0, 12) : problems;
            string msg = "Not every tick could be saved as clicked, so the screen now shows what the database has:\n\n" +
                         string.Join("\n", shown) + (problems.Count > 12 ? $"\n… and {problems.Count - 12} more." : "");
            SetStatus(problems[0], err: true);
            XtraMessageBox.Show(msg, "Bank Recon", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        // Called before any reload (LoadPeriod) and when the screen closes: lets the queued saves finish.
        // Safe to block on: the worker never waits for the UI thread (it only posts).
        private void WaitForTickSaves()
        {
            System.Threading.Tasks.Task t;
            lock (_tickLock) t = _tickWorker;
            if (t.IsCompleted) return;
            SetStatus("Saving your ticks first…");
            var old = Cursor.Current;
            Cursor.Current = Cursors.WaitCursor;
            try { t.Wait(); } catch (AggregateException) { }
            finally { Cursor.Current = old; }
        }

        // Reloads the period but keeps what the user was looking at: the open Control No groups, the
        // scroll position and the focused row (detailed view), the focused row and scroll (summary view).
        private void ReloadKeepingView()
        {
            var open = new HashSet<string>(StringComparer.Ordinal);
            int top = 0, focusID = 0, sumTop = 0, sumFocus = 0;
            string focusGroup = null;
            if (viewAll != null && _dtAll != null)
            {
                for (int gh = -1; viewAll.IsValidRowHandle(gh); gh--)
                    if (viewAll.GetRowLevel(gh) == 1 && viewAll.GetRowExpanded(gh) && GroupKey(gh, out var t, out var c)) open.Add(t + "|" + c);
                top = viewAll.TopRowIndex;
                int fh = viewAll.FocusedRowHandle;
                if (viewAll.IsDataRow(fh)) focusID = SafeInt(viewAll.GetRowCellValue(fh, "ReconID"));
                else if (GroupKey(fh, out var ft, out var fc)) focusGroup = ft + "|" + fc;
            }
            if (viewSum != null) { sumTop = viewSum.TopRowIndex; sumFocus = viewSum.FocusedRowHandle; }

            try { LoadPeriod(); RefreshSummary(); }
            catch (SqlException ex) { SetStatus(ex.Message, err: true); return; }

            if (viewAll != null)
            {
                // no BeginUpdate here: the groups were built by BindCombined, and expanding them must take effect now
                for (int gh = -1; viewAll.IsValidRowHandle(gh); gh--)
                {
                    if (viewAll.GetRowLevel(gh) != 1 || !GroupKey(gh, out var t, out var c)) continue;
                    string key = t + "|" + c;
                    if (open.Contains(key)) viewAll.SetRowExpanded(gh, true, false);
                    if (key == focusGroup) viewAll.FocusedRowHandle = gh;
                }
                if (focusID > 0)
                {
                    int h = viewAll.LocateByValue("ReconID", focusID);
                    if (h != DevExpress.XtraGrid.GridControl.InvalidRowHandle) viewAll.FocusedRowHandle = h;
                }
                viewAll.TopRowIndex = top;
            }
            if (viewSum != null && _dtSum != null && viewSum.RowCount > 0)
            {
                viewSum.FocusedRowHandle = Math.Max(0, Math.Min(sumFocus, viewSum.RowCount - 1));
                viewSum.TopRowIndex = sumTop;
            }
            UpdateCombinedButtons();
        }

        private void SetCombinedLocked(bool locked)
        {
            if (viewAll == null) return;
            // 2026-10-10: the Cleared boxes are the editable columns (tick = clear at once)
            foreach (DevExpress.XtraGrid.Columns.GridColumn col in viewAll.Columns)
                col.OptionsColumn.AllowEdit = false;
            if (viewSum != null)
                foreach (DevExpress.XtraGrid.Columns.GridColumn col in viewSum.Columns)
                    col.OptionsColumn.AllowEdit = false;
            UpdateCombinedButtons();
            gridAll.Invalidate();   // the group check boxes are drawn only while unlocked
        }

        // Ticks only the data rows currently visible (filtered, in expanded groups).
        private void ChkAllSelect_CheckedChanged(object sender, EventArgs e)
        {
            if (_summaryMode)
            {
                for (int i = 0; i < viewSum.RowCount; i++)
                {
                    int sh = viewSum.GetVisibleRowHandle(i);
                    if (sh < 0) continue;
                    bool cleared = Convert.ToString(viewSum.GetRowCellValue(sh, "Status")) == "CLEARED";
                    viewSum.SetRowCellValue(sh, "Selected", chkAllSelect.Checked && !cleared);
                }
                return;
            }
            for (int i = 0; i < viewAll.RowCount; i++)
            {
                int handle = viewAll.GetVisibleRowHandle(i);
                if (viewAll.IsGroupRow(handle)) continue;
                viewAll.SetRowCellValue(handle, "Selected", chkAllSelect.Checked);
            }
        }

        private void BtnAllBulkResolve_Click(object sender, EventArgs e)
        {
            if (_isLocked) return;
            if (_summaryMode) { SummaryResolve(SummaryRows(selectedOnly: true), "Bulk Resolve"); return; }
            viewAll.CloseEditor();
            viewAll.UpdateCurrentRow();

            var dit = new List<int>();
            var oc = new List<int>();
            var controls = new HashSet<string>();
            foreach (DataRow row in _dtAll.Rows)
            {
                if (!(row["Selected"] is bool sel && sel)) continue;
                if (row["IsResolved"] is bool done && done) continue;
                (Convert.ToString(row["ItemType"]) == "OC" ? oc : dit).Add(SafeInt(row["ReconID"]));
                string ctlNo = Convert.ToString(row["ControlNo"]);
                if (!string.IsNullOrWhiteSpace(ctlNo)) controls.Add(ctlNo);   // "(no control no.)" isn't a batch
            }

            if (dit.Count + oc.Count == 0)
            {
                XtraMessageBox.Show("No uncleared items are checked. Filter or expand a group and check the rows you want to resolve.");
                return;
            }

            // Spells out what is about to be cleared, so a Select All across many batches isn't a surprise
            string msg = $"Mark {dit.Count + oc.Count} checked item(s) as cleared by the bank?\n\n" +
                         $"  Deposits in transit: {dit.Count}\n  Outstanding checks: {oc.Count}\n  Control numbers involved: {controls.Count}";
            if (XtraMessageBox.Show(msg, "Confirm Bulk Resolve", MessageBoxButtons.YesNo,
                                    controls.Count > 1 ? MessageBoxIcon.Warning : MessageBoxIcon.Question) != DialogResult.Yes)
                return;

            if (dit.Count > 0) ResolveReconIDs(dit, "DIT");
            if (oc.Count > 0) ResolveReconIDs(oc, "OC");
        }

        // Clears every uncleared item of the same Kind with the focused row's / group's Control No.
        private void BtnAllResolveBatch_Click(object sender, EventArgs e)
        {
            if (_isLocked) return;
            if (_summaryMode) { SummaryResolve(SummaryRows(selectedOnly: false), "Clear Entire Batch"); return; }
            int dh = FocusedDataRowHandle();
            if (dh < 0) { XtraMessageBox.Show("Select a row or a Control No group first."); return; }

            string ctl = Convert.ToString(viewAll.GetRowCellValue(dh, "ControlNo"));
            string type = Convert.ToString(viewAll.GetRowCellValue(dh, "ItemType"));
            if (string.IsNullOrWhiteSpace(ctl)) { XtraMessageBox.Show("This item has no Control No."); return; }

            var ids = new List<int>();
            foreach (DataRow row in _dtAll.Rows)
            {
                if (Convert.ToString(row["ItemType"]) != type || Convert.ToString(row["ControlNo"]) != ctl) continue;
                if (row["IsResolved"] is bool done && done) continue;
                ids.Add(SafeInt(row["ReconID"]));
            }

            if (ids.Count == 0) { XtraMessageBox.Show("All items under this Control No are already cleared."); return; }

            string kind = type == "OC" ? KIND_OC.ToLower() + "(s)" : KIND_DIT.ToLower() + "(s)";
            if (XtraMessageBox.Show($"Mark all {ids.Count} {kind} under Control No '{ctl}' as cleared by the bank?", "Confirm Resolve Batch",
                                    MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;

            ResolveReconIDs(ids, type);
        }

        // ================================================================
        // UNCLEAR IN ONE STEP (2026-10-09): the opposite of Clear Entire Batch / Bulk Resolve,
        // through sp_BankRecon_BulkUnresolveItems (all or nothing). Only items cleared in the month
        // on screen are undone; the rest are skipped and counted.
        // ================================================================

        // Unclear Entire Batch: the focused Control No (detailed view) or the focused batch row (summary view).
        private void BtnAllUnresolveBatch_Click(object sender, EventArgs e)
        {
            if (_isLocked) return;
            var ids = new List<int>();
            decimal amount = 0m;
            string what;

            if (_summaryMode)
            {
                var r = viewSum.GetDataRow(viewSum.FocusedRowHandle);
                if (r == null) { XtraMessageBox.Show("Select a batch row first."); return; }
                CollectSummaryCleared(r, ids, ref amount);
                string batch = Convert.ToString(r["BatchNo"]);
                what = string.IsNullOrWhiteSpace(batch) ? "in the selected row" : $"in batch '{batch}'";
            }
            else
            {
                int dh = FocusedDataRowHandle();
                if (dh < 0) { XtraMessageBox.Show("Select a row or a Control No group first."); return; }
                string ctl = Convert.ToString(viewAll.GetRowCellValue(dh, "ControlNo"));
                string type = Convert.ToString(viewAll.GetRowCellValue(dh, "ItemType"));
                if (string.IsNullOrWhiteSpace(ctl)) { XtraMessageBox.Show("This item has no Control No."); return; }
                foreach (DataRow row in _dtAll.Rows)
                {
                    if (Convert.ToString(row["ItemType"]) != type || Convert.ToString(row["ControlNo"]) != ctl) continue;
                    if (!(row["IsResolved"] is bool done && done)) continue;
                    ids.Add(SafeInt(row["ReconID"]));
                    amount += SafeDec(row["Amount"]);
                }
                what = $"under Control No '{ctl}'";
            }

            if (ids.Count == 0) { XtraMessageBox.Show("Nothing in this batch is cleared."); return; }
            UnresolveReconIDs(ids, amount, what, "Unclear Entire Batch");
        }

        // Bulk Unclear (detailed view): the ticked rows that are cleared.
        private void BtnAllBulkUnresolve_Click(object sender, EventArgs e)
        {
            if (_isLocked || _summaryMode) return;
            viewAll.CloseEditor();
            viewAll.UpdateCurrentRow();

            var ids = new List<int>();
            decimal amount = 0m;
            var controls = new HashSet<string>();
            foreach (DataRow row in _dtAll.Rows)
            {
                if (!(row["Selected"] is bool sel && sel)) continue;
                if (!(row["IsResolved"] is bool done && done)) continue;
                ids.Add(SafeInt(row["ReconID"]));
                amount += SafeDec(row["Amount"]);
                string ctlNo = Convert.ToString(row["ControlNo"]);
                if (!string.IsNullOrWhiteSpace(ctlNo)) controls.Add(ctlNo);
            }

            if (ids.Count == 0)
            {
                XtraMessageBox.Show("No cleared items are checked. Check the cleared rows you want to mark uncleared.");
                return;
            }
            UnresolveReconIDs(ids, amount, $"in {controls.Count} control number(s)", "Bulk Unclear");
        }

        // The cleared items behind one summary row: its batch (Control No for deposits, CV # for checks)
        // or, for a row without one, its single item. Same keys as sp_BankRecon_GetPeriodSummary.
        private void CollectSummaryCleared(DataRow sumRow, List<int> ids, ref decimal amount)
        {
            bool isOC = Convert.ToString(sumRow["ItemType"]) == "OC";
            DataTable src = isOC ? _dtOC : _dtDIT;
            if (src == null) return;
            string key = Convert.ToString(sumRow["BatchKey"]);
            string field = isOC ? "CVNo" : "ControlNo";
            foreach (DataRow row in src.Rows)
            {
                if (!(row["IsResolved"] is bool done && done)) continue;
                bool match = key.StartsWith("ID:")
                    ? SafeInt(row["ReconID"]) == SafeInt(key.Substring(3))
                    : key.StartsWith("NO:") && src.Columns.Contains(field) && Convert.ToString(row[field]).Trim() == key.Substring(3).Trim();
                if (!match) continue;
                ids.Add(SafeInt(row["ReconID"]));
                amount += SafeDec(row["Amount"]);
            }
        }

        private void UnresolveReconIDs(List<int> ids, decimal amount, string what, string title)
        {
            string msg = $"Mark {ids.Count} cleared item(s) {what} as uncleared?\n\n" +
                         $"  Amount: {amount:N2}\n\n" +
                         $"Only items cleared in {_period:MMM yyyy} are undone; items cleared in another month are left as they are.";
            if (XtraMessageBox.Show(msg, "Confirm " + title, MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes)
                return;

            if (!UnresolveCore(ids, title)) return;
            LoadPeriod();
            RefreshSummary();
        }

        // sp_BankRecon_BulkUnresolveItems without a confirmation and without a reload (2026-10-10: the batch
        // boxes call it directly). False when the proc refused (message shown); the result goes to the status bar.
        private bool UnresolveCore(List<int> ids, string title)
        {
            int done = 0, otherMonth = 0, notCleared = 0, system = 0;
            try
            {
                var dtIds = new DataTable();
                dtIds.Columns.Add("ReconID", typeof(int));
                foreach (var id in ids) dtIds.Rows.Add(id);

                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_BankRecon_BulkUnresolveItems", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    var p = cmd.Parameters.Add("@ReconIDs", SqlDbType.Structured);
                    p.TypeName = "dbo.tt_BankReconIDList";
                    p.Value = dtIds;
                    cmd.Parameters.Add("@ResolvedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = _period;
                    con.Open();
                    using (var rdr = cmd.ExecuteReader())
                        if (rdr.Read())
                        {
                            done = SafeInt(rdr["UnclearedCount"]);
                            otherMonth = SafeInt(rdr["SkippedOtherMonth"]);
                            notCleared = SafeInt(rdr["SkippedNotCleared"]);
                            system = SafeInt(rdr["SkippedSystem"]);
                        }
                }
            }
            catch (SqlException ex) { SetStatus(ex.Message, err: true); XtraMessageBox.Show(ex.Message, title, MessageBoxButtons.OK, MessageBoxIcon.Warning); return false; }

            string result = $"{done} item(s) marked uncleared.";
            if (otherMonth > 0) result += $"\n{otherMonth} item(s) were cleared in another month: open that month to undo them.";
            if (system > 0) result += $"\n{system} item(s) were closed by a reversal or a posted auto-debit and were left as they are.";
            if (notCleared > 0) result += $"\n{notCleared} item(s) were not cleared.";
            SetStatus(result.Replace("\n", "  "));
            if (otherMonth + system + notCleared > 0) XtraMessageBox.Show(result, title, MessageBoxButtons.OK, MessageBoxIcon.Information);
            return true;
        }

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