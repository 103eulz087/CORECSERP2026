using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraEditors.Controls;

namespace SalesInventorySystem.HOFormsDevEx
{
    /// <summary>
    /// Post Single Expense — same shape as Manual Voucher Entry (a
    /// free-form GL entry grid), plus the header fields spu_PostExpenseV2
    /// needs: ReferenceNumber, TicketNumber, InvoiceNo, ShipmentNo,
    /// SupplierID, BranchCode, ExpenseDate.
    ///
    /// ASSUMPTION: spu_PostExpenseV2 reads BranchCode / AccountCode /
    /// Particulars / Debit / Credit off @ExpenseDetails, but your grid
    /// has no BranchCode column — so this form stamps the header's
    /// selected branch onto every TVP row when submitting. If
    /// ExpenseDetailType's real column list differs, send me the
    /// CREATE TYPE and I'll correct BuildExpenseDetailsTVP().
    /// </summary>
    public partial class PostSingleExpenseForm : XtraForm
    {
        private DataTable _table;
        private DataTable _accountsCache;
        private object _objbranches;
        private object _objvendor;
        private object _objshipmentno;
        private bool _initialized = false;

        public PostSingleExpenseForm()
        {
            InitializeComponent();
            Load += PostSingleExpenseForm_Load;
            Shown += PostSingleExpenseForm_Shown;
        }

        private void PostSingleExpenseForm_Load(object sender, EventArgs e)
        {
            txtticketno.Text = GetTicketNumber();
            txtrefno.Text = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");
            txtexpdate.DateTime = DateTime.Today;

            PopulateBranches();
            PopulateVendors();

            _table = new DataTable();
            _table.Columns.Add("Particulars");
            _table.Columns.Add("AccountCode");
            _table.Columns.Add("AccountTitle");
            _table.Columns.Add("Debit", typeof(decimal));
            _table.Columns.Add("Credit", typeof(decimal));
            gridControl1.DataSource = _table;

            gridView1.Columns["Debit"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "Debit", "{0:n2}");
            gridView1.Columns["Credit"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "Credit", "{0:n2}");
        }

        private void PostSingleExpenseForm_Shown(object sender, EventArgs e)
        {
            if (_initialized) return;
            _initialized = true;
            LoadChartOfAccounts();
        }

        // ── Lookups ──────────────────────────────────────────────
        private void LoadChartOfAccounts()
        {
            try
            {
                UseWaitCursor = true;
                var accounts = GetDataTable("SELECT AccountCode, Description FROM ChartOfAccounts");
                BindRepositoryItems(accounts);
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show($"Error loading chart of accounts: {ex.Message}", "Error",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                UseWaitCursor = false;
            }
        }

        private void BindRepositoryItems(DataTable accounts)
        {
            _accountsCache = accounts;

            repoaccountcode.BeginUpdate();
            try
            {
                repoaccountcode.DataSource = accounts;
                repoaccountcode.DisplayMember = "AccountCode";
                repoaccountcode.ValueMember = "AccountCode";
            }
            finally
            {
                repoaccountcode.EndUpdate();
            }
        }

        private void PopulateBranches()
        {
            Database.displaySearchlookupEdit(
                "SELECT BranchCode, BranchName FROM Branches ORDER BY BranchCode",
                cmbbranches, "BranchCode", "BranchCode");
            cmbbranches.EditValueChanged += (s, e) => _objbranches = cmbbranches.EditValue;
        }

        private void PopulateVendors()
        {
            Database.displaySearchlookupEdit(
                "SELECT SupplierID, SupplierName FROM Supplier ORDER BY SupplierName",
                cmbvendor, "SupplierID", "SupplierID");
            cmbvendor.EditValueChanged += (s, e) => _objvendor = cmbvendor.EditValue;
        }

        // PLACEHOLDER — I don't have your PO/shipment table schema.
        // Wire this to whatever query your existing "Link to PO" combo
        // elsewhere in the app already uses.
        private void PopulateShipments()
        {
            // Database.displaySearchlookupEdit(
            //     "SELECT ShipmentNo, ShipmentNo AS Display FROM Shipments ORDER BY ShipmentNo",
            //     cmblinktopo, "ShipmentNo", "ShipmentNo");
            cmblinktopo.EditValueChanged += (s, e) => _objshipmentno = cmblinktopo.EditValue;
        }

        private void Chcklinktopo_CheckedChanged(object sender, EventArgs e)
        {
            cmblinktopo.Enabled = chcklinktopo.Checked;
            if (chcklinktopo.Checked && cmblinktopo.Properties.DataSource == null)
                PopulateShipments();
            if (!chcklinktopo.Checked)
            {
                cmblinktopo.EditValue = null;
                _objshipmentno = null;
            }
        }

        // ── Grid handlers ────────────────────────────────────────
        private void BtnAddGLEntry_Click(object sender, EventArgs e)
        {
            DataRow newRow = _table.NewRow();
            newRow["Particulars"] = "";
            newRow["Debit"] = 0m;
            newRow["Credit"] = 0m;
            _table.Rows.Add(newRow);
        }

        private void GridView1_CustomRowCellEdit(object sender, DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "AccountCode") e.RepositoryItem = repoaccountcode;
            if (e.Column.FieldName == "Debit") e.RepositoryItem = spindebit;
            if (e.Column.FieldName == "Credit") e.RepositoryItem = spincredit;
        }

        private void Repoaccountcode_EditValueChanged(object sender, EventArgs e)
        {
            // ValueMember="AccountCode" already writes the code into the
            // grid cell on commit — no manual SetRowCellValue needed here.
            gridView1.CloseEditor();
            gridView1.FocusedColumn = gridView1.Columns["Debit"];
            gridView1.ShowEditor();
        }

        private void GridView1_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            // AccountTitle lookup — only when AccountCode changed
            if (e.Column.FieldName == "AccountCode" && _accountsCache != null)
            {
                string code = e.Value?.ToString();
                if (!string.IsNullOrEmpty(code))
                {
                    DataRow[] match = _accountsCache.Select($"AccountCode = '{code.Replace("'", "''")}'");
                    if (match.Length > 0)
                        gridView1.SetRowCellValue(e.RowHandle, "AccountTitle", match[0]["Description"].ToString());
                }
            }

            // Debit/Credit mutual exclusivity
            if (e.Column.FieldName == "Debit")
            {
                decimal debit = Convert.ToDecimal(gridView1.GetRowCellValue(e.RowHandle, "Debit") ?? 0);
                if (debit > 0) gridView1.SetRowCellValue(e.RowHandle, "Credit", 0);
            }
            if (e.Column.FieldName == "Credit")
            {
                decimal credit = Convert.ToDecimal(gridView1.GetRowCellValue(e.RowHandle, "Credit") ?? 0);
                if (credit > 0) gridView1.SetRowCellValue(e.RowHandle, "Debit", 0);
            }

            // Recompute totals — runs on every relevant change
            decimal totalDebit = 0, totalCredit = 0;
            for (int i = 0; i < gridView1.RowCount; i++)
            {
                totalDebit += Convert.ToDecimal(gridView1.GetRowCellValue(i, "Debit") ?? 0);
                totalCredit += Convert.ToDecimal(gridView1.GetRowCellValue(i, "Credit") ?? 0);
            }
            lbltotaldebit.Text = totalDebit.ToString("N2");
            lbltotalcredit.Text = totalCredit.ToString("N2");
        }

        // ── Submit ───────────────────────────────────────────────
        private void BtnSubmit_Click(object sender, EventArgs e)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(txtrefno.Text) ||
                    _objbranches == null || string.IsNullOrWhiteSpace(_objbranches.ToString()) ||
                    _objvendor == null || string.IsNullOrWhiteSpace(_objvendor.ToString()) ||
                    string.IsNullOrWhiteSpace(txtremakrs.Text))
                {
                    XtraMessageBox.Show("Please input all required fields (Branch, Vendor, Particulars).");
                    return;
                }

                if (Convert.ToDouble(lbltotaldebit.Text) <= 0 || Convert.ToDouble(lbltotalcredit.Text) <= 0)
                {
                    XtraMessageBox.Show("Please make sure you have GL Entries.");
                    return;
                }

                if (lbltotaldebit.Text != lbltotalcredit.Text)
                {
                    XtraMessageBox.Show("Total Debit must equal Total Credit before submitting.");
                    return;
                }

                for (int i = 0; i < gridView1.RowCount; i++)
                {
                    decimal debit = Convert.ToDecimal(gridView1.GetRowCellValue(i, "Debit") ?? 0);
                    decimal credit = Convert.ToDecimal(gridView1.GetRowCellValue(i, "Credit") ?? 0);
                    string acct = gridView1.GetRowCellValue(i, "AccountCode")?.ToString();

                    if (string.IsNullOrEmpty(acct))
                    {
                        XtraMessageBox.Show($"Row {i + 1}: Account is required.");
                        return;
                    }
                    if ((debit > 0 && credit > 0) || (debit == 0 && credit == 0))
                    {
                        XtraMessageBox.Show($"Row {i + 1}: Enter amount in either Debit OR Credit only.");
                        return;
                    }
                }

                var dt = BuildExpenseDetailsTVP();

                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("spu_PostExpenseV2", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 180;

                    var tvpParam = cmd.Parameters.AddWithValue("@ExpenseDetails", dt);
                    tvpParam.SqlDbType = SqlDbType.Structured;
                    tvpParam.TypeName = "ExpenseDetailType";

                    cmd.Parameters.AddWithValue("@TicketNumber", txtticketno.Text);
                    cmd.Parameters.AddWithValue("@BranchCode", _objbranches.ToString());
                    cmd.Parameters.AddWithValue("@ReferenceNumber", txtrefno.Text);
                    cmd.Parameters.AddWithValue("@InvoiceNo", txtinvoiceno.Text);
                    cmd.Parameters.AddWithValue("@ShipmentNo", _objshipmentno == null ? "" : _objshipmentno.ToString());
                    cmd.Parameters.AddWithValue("@SupplierID", _objvendor.ToString());
                    cmd.Parameters.AddWithValue("@ExpenseDate", txtexpdate.DateTime);
                    cmd.Parameters.AddWithValue("@Remarks", txtremakrs.Text);
                    cmd.Parameters.AddWithValue("@isLinkedToPO", chcklinktopo.Checked ? 1 : 0);
                    cmd.Parameters.AddWithValue("@User", Login.Fullname);
                    // @PayableAccountCode left at its SP default ('20103')

                    con.Open();
                    cmd.ExecuteNonQuery();
                }

                XtraMessageBox.Show("Successfully Added!");
                Close();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message);
            }
        }

        // BranchCode column stamped from the header field on every row,
        // per the assumption flagged in the class remarks above.
        private DataTable BuildExpenseDetailsTVP()
        {
            var dt = new DataTable();
            dt.Columns.Add("BranchCode", typeof(string));
            dt.Columns.Add("AccountCode", typeof(string));
            dt.Columns.Add("Particulars", typeof(string));
            dt.Columns.Add("Debit", typeof(decimal));
            dt.Columns.Add("Credit", typeof(decimal));

            string branch = _objbranches.ToString();

            for (int i = 0; i < gridView1.RowCount; i++)
            {
                string particulars = gridView1.GetRowCellValue(i, "Particulars")?.ToString() ?? "";
                string acct = gridView1.GetRowCellValue(i, "AccountCode")?.ToString() ?? "";
                decimal debit = Convert.ToDecimal(gridView1.GetRowCellValue(i, "Debit") ?? 0);
                decimal credit = Convert.ToDecimal(gridView1.GetRowCellValue(i, "Credit") ?? 0);

                dt.Rows.Add(branch, acct, particulars, debit, credit);
            }

            return dt;
        }

        // ── Small local DB helpers (kept consistent with the rest of
        //    the module rather than pulling in async plumbing) ──────
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

        private string GetTicketNumber()
        {
            // Mirrors your existing getTicketNumber() helper — replace with
            // that call directly if it's available as a shared utility.
            return IDGenerator.getIDNumberSP("sp_GetVoucherNumber", "TicketNumber");
        }
    }
}