using System;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.AccountingDevEx
{
    public partial class BankReconFormV2 : XtraForm
    {
        // ── State ─────────────────────────────────────────────────────
        private string _branch = Login.assignedBranch;
        private string _account = "";
        private DateTime _period = DateTime.Today;
        private decimal _bookBal = 0m;
        private decimal _bankBal = 0m;
        private int _headerID = 0;
        private int _selDitID = 0;
        private int _selOcID = 0;
        private bool _isLocked = false;

        // DataTables 
        private DataTable _dtDIT = new DataTable();
        private DataTable _dtOC = new DataTable();

        public BankReconFormV2()
        {
            InitializeComponent();
            WireEvents();
            PopulateLookups();
            SetDefaultPeriod();

            // Grid conditional row coloring
            viewDIT.RowCellStyle += View_RowCellStyle;
            viewOC.RowCellStyle += View_RowCellStyle;
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
            btnAddOC.Click += (s, e) => BtnAdd_Click("OC");
            btnResolveDIT.Click += (s, e) => BtnResolve_Click(_selDitID);
            btnResolveOC.Click += (s, e) => BtnResolve_Click(_selOcID);
            btnDeleteDIT.Click += (s, e) => BtnDelete_Click(_selDitID);
            btnDeleteOC.Click += (s, e) => BtnDelete_Click(_selOcID);
            btnAutoMatch.Click += BtnAutoMatch_Click;
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
            };

            viewOC.FocusedRowChanged += (s, e) =>
            {
                bool has = viewOC.FocusedRowHandle >= 0;
                btnResolveOC.Enabled = has && !_isLocked;
                btnDeleteOC.Enabled = has && !_isLocked;
                _selOcID = has ? SafeInt(viewOC.GetRowCellValue(viewOC.FocusedRowHandle, "ReconID")) : 0;
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

            Database.displaySearchlookupEdit(
                "SELECT AccountCode, Description FROM ChartOfAccounts WHERE AccountCode LIKE '10102%' AND AccountType='D' ORDER BY AccountCode",
                cmbAccount, "AccountCode", "AccountCode");
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
                SetStatus($"Loaded: {_account}  |  Period: {_period:yyyy-MM-dd}" + (_isLocked ? "  |  🔒 LOCKED" : ""));
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
                BindGrid(gridDIT, viewDIT, _dtDIT);

                _dtOC = ds.Tables.Count > 2 ? ds.Tables[2] : new DataTable();
                BindGrid(gridOC, viewOC, _dtOC);
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
            btnLock.Enabled = !locked;
            btnAutoMatch.Enabled = !locked;
        }

        private void BindGrid(DevExpress.XtraGrid.GridControl grid, GridView view, DataTable dt)
        {
            view.Columns.Clear();
            grid.DataSource = dt;

            FormatCol(view, "ReconID", 50, false);
            FormatCol(view, "ItemDate", 90, false, isDate: true);
            FormatCol(view, "ReferenceNo", 120, false);
            FormatCol(view, "Description", 180, false);
            FormatCol(view, "Amount", 110, true);
            FormatCol(view, "IsResolved", 60, false);
            FormatCol(view, "ResolvedReason", 90, false);
            FormatCol(view, "SourceModule", 80, false);
            FormatCol(view, "IsAutoInserted", 0, false);

            if (view.Columns["IsAutoInserted"] != null) view.Columns["IsAutoInserted"].Visible = false;
            view.BestFitColumns();
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
                string t = row["ItemType"]?.ToString();
                decimal amt = SafeDec(row["Amount"]);
                switch (t)
                {
                    case "OC": oc += amt; break;
                    case "BCM": bcm += amt; break;
                    case "BDM":
                    case "BC":
                    case "NSF": bdm += amt; break;
                }
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
                SetLbl(lblDiff, "0.00  ✓  RECONCILED", C_OK);
                lblDiff.Font = new System.Drawing.Font("Courier New", 12f, System.Drawing.FontStyle.Bold);
            }
            else
            {
                SetLbl(lblDiff, $"{Math.Abs(diff):N2}  ⚠  OUT OF BALANCE", C_ERR);
                lblDiff.Font = new System.Drawing.Font("Courier New", 12f, System.Drawing.FontStyle.Bold);
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

        private void BtnAdd_Click(string itemType)
        {
            if (_headerID == 0) { XtraMessageBox.Show("Load a period first."); return; }

            using (var dlg = new BankReconItemForm(isNew: true))
            {
                dlg.ItemType = itemType;
                if (dlg.ShowDialog(this) != DialogResult.OK) return;

                try
                {
                    using (var con = Database.getConnection())
                    using (var cmd = new SqlCommand("sp_BankRecon_SaveItem", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.Add("@HeaderID", SqlDbType.Int).Value = _headerID;
                        cmd.Parameters.Add("@ItemType", SqlDbType.VarChar, 5).Value = dlg.ItemType;
                        cmd.Parameters.Add("@ReferenceNo", SqlDbType.VarChar, 150).Value = dlg.ReferenceNo;
                        cmd.Parameters.Add("@ItemDate", SqlDbType.Date).Value = dlg.ItemDate;
                        cmd.Parameters.Add("@Description", SqlDbType.VarChar, 200).Value = dlg.Payee;
                        cmd.Parameters.Add("@Amount", SqlDbType.Decimal).Value = Math.Round(dlg.Amount, 2);
                        cmd.Parameters.Add("@Remarks", SqlDbType.VarChar, 500).Value = dlg.Remarks;
                        cmd.Parameters.Add("@CreatedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;
                        con.Open();
                        cmd.ExecuteNonQuery();
                    }
                    LoadPeriod();
                    RefreshSummary();
                    SetStatus($"{itemType} item added.");
                }
                catch (SqlException ex) { SetStatus(ex.Message, err: true); }
            }
        }

        private void BtnResolve_Click(int reconID)
        {
            if (reconID <= 0) return;
            if (XtraMessageBox.Show("Mark this item as CLEARED by bank?", "Confirm", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
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
                    cmd.Parameters.Add("@DeletedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    con.Open();
                    cmd.ExecuteNonQuery();
                }
                LoadPeriod(); RefreshSummary();
                SetStatus("Item deleted.");
            }
            catch (SqlException ex) { SetStatus(ex.Message, err: true); }
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
                    cmd.Parameters.Add("@BranchCode", SqlDbType.Char, 3).Value = _branch;
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

        private static DateTime SafeDate(object v) => v is DateTime dt ? dt : DateTime.TryParse(v?.ToString(), out var r) ? r : DateTime.Today;
    }
}