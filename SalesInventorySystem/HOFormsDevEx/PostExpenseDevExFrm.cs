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
using System.Data.SqlClient;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.HOFormsDevEx
{// ── NEW: small holder for what we need from ExpenseJournalMapping ──
   
    public partial class PostExpenseDevExFrm : XtraUserControl
    { // ── resolved at load / lookup time ───────────────────────────
       
        private Dictionary<string, ExpenseEWTMapping> _ewtMap
           = new Dictionary<string, ExpenseEWTMapping>(StringComparer.OrdinalIgnoreCase);
        private bool _isAutoCalculating = false;

        private string _suppId = "";   // SupplierID (long key)
        private string _suppName = "";
        private bool _initialized = false;
        DataTable table;
        bool ok = false;
        object suppid, shipmentno;
        public void ResetData()
        {
            ResetForm();
        }
        private void ResetForm()
        {
            txtinvoiceno.Text="";
            txtremarks.Clear();

            txtvendor.EditValue = null;
            txtpo.EditValue = null;

            suppid = null;
            shipmentno = null;

            table.Rows.Clear();

            txtrefno.Text =
                IDGenerator.getIDNumberSP(
                    "sp_GetReferenceNumber",
                    "ReferenceNumber");

            txtbatchid.Text =
                IDGenerator.getIDNumberSP(
                    "sp_GetBatchReferenceID",
                    "BatchReferenceID");
        }
        public PostExpenseDevExFrm()
        {
            InitializeComponent();
            repbrcode.Popup += (s, e) =>
            {
                var edit = s as DevExpress.XtraEditors.SearchLookUpEdit;
                //edit.Properties.View.BestFitColumns();
            };
            reptypeofexpense.Popup += (s, e) =>
            {
                var edit = s as DevExpress.XtraEditors.SearchLookUpEdit;
                //edit.Properties.View.BestFitColumns();
            };


            repbrcode.View.OptionsView.ColumnAutoWidth = false;
            repbrcode.View.BestFitColumns();

            reptypeofexpense.View.OptionsView.ColumnAutoWidth = false;
            reptypeofexpense.View.BestFitColumns();

            repamount.Mask.MaskType = DevExpress.XtraEditors.Mask.MaskType.Numeric;
            repamount.Mask.EditMask = "n2";   // "n2" = number with commas and 2 decimals
            repamount.Mask.UseMaskAsDisplayFormat = true;

       

            repbrcode.AutoHeight = false;
            //repbrcode.BestFitMode = DevExpress.XtraEditors.Controls.BestFitMode.BestFit;

            reptypeofexpense.AutoHeight = false;
            //reptypeofexpense.BestFitMode = DevExpress.XtraEditors.Controls.BestFitMode.BestFit;

            repparticulars.AutoHeight = false;

            repamount.AutoHeight = false;

        }

        private bool _dataLoaded = false;

        public async void LoadData()
        {
            if (_dataLoaded)
                return;

            DateTime now = DateTime.Now;
            //datefrom.Text = new DateTime(now.Year, now.Month, 1).ToShortDateString();
            //dateto.Text = new DateTime(now.Year, now.Month, DateTime.DaysInMonth(now.Year, now.Month)).ToShortDateString();
            datefrom.EditValue = new DateTime(now.Year, now.Month, 1);
            dateto.EditValue = new DateTime(now.Year, now.Month, DateTime.DaysInMonth(now.Year, now.Month));
            // Initialize empty table
            table = new DataTable();
            table.Columns.Add("BranchCode");
            table.Columns.Add("TypeOfExpense");
            table.Columns.Add("Particulars");
            table.Columns.Add("Amount");
            table.Columns.Add("EWTAmount", typeof(decimal));   // NEW - must be added LAST,
                                                               // matching ExpenseEntryTVP's
                                                               // column order (SqlClient maps
                                                               // TVP columns by ORDINAL
                                                               // POSITION, not name)
            table.Columns.Add("EWTManual", typeof(bool));      // NEW - tracking only, not sent to the TVP
            gridControl1.DataSource = table;
            // Defer heavy DB calls until Shown

            Classes.DevXGridViewSettings.ShowFooterTotal(gridView1, "Amount");
            Classes.DevXGridViewSettings.ShowFooterTotal(gridView1, "EWTAmount");

            if (_initialized) return;
            _initialized = true;

            await InitializeFormAsync();
            await ReloadReferenceNumbersAsync();

            _dataLoaded = true;
        }
        public async Task ReloadReferenceNumbersAsync()
        {
            txtrefno.Text =
                await Task.Run(() =>
                    IDGenerator.getIDNumberSP(
                        "sp_GetReferenceNumber",
                        "ReferenceNumber"));

            txtbatchid.Text =
                await Task.Run(() =>
                    IDGenerator.getIDNumberSP(
                        "sp_GetBatchReferenceID",
                        "BatchReferenceID"));
        }

        private void PostExpenseDevExFrm_Load(object sender, EventArgs e)
        {

            //this.Shown -= PostExpenseDevExFrm_Shown;
            //this.Shown += PostExpenseDevExFrm_Shown;

            // Better to wire this once in designer or constructor,
            // but if you do it here, make sure it only runs once per form instance



        }
        void populateBranches2()
        {
            Database.displayDevComboBoxItems("SELECT BranchCode FROM Branches", "BranchCode", txtbrcodesum);
        }
        void displayvendor()
        {
            Database.displaySearchlookupEdit("select SupplierID,SupplierName FROM Supplier", txtvendor, "SupplierName", "SupplierName");
        }
        void displayPurchaseList()
        {
            Database.displaySearchlookupEdit("select ShipmentNo, SupplierId, SupplierName FROM dbo.view_POSUMMARYREP WHERE Status <> 'CANCELLED'", txtpo, "SupplierName", "SupplierName");
        }
        //void loadRepositoryItem()
        //{
        //    Database.displayRepositorySearchlookupEdit("SELECT BranchCode,BranchName FROM Branches", repbrcode, "BranchCode", "BranchCode");
        //    //Database.displayRepositorySearchlookupEdit("SELECT Description FROM CHartOfAccounts WHERE AccountCode like '60%'", reptypeofexpense, "Description", "Description");
        //    Database.displayRepositorySearchlookupEdit("SELECT * FROM ExpensesList", reptypeofexpense, "ExpenseName", "ExpenseName");

        //    foreach (DevExpress.XtraGrid.Columns.GridColumn col in gridView1.Columns)
        //    {
        //        col.BestFit();
        //    }


        //    gridView1.Columns["BranchCode"].MinWidth = 100;
        //    gridView1.Columns["TypeOfExpense"].MinWidth = 150;
        //    gridView1.Columns["Particulars"].MinWidth = 200;
        //    gridView1.Columns["Amount"].MinWidth = 100;

        //    //gridView2.BestFitColumns();
        //    //gridView3.BestFitColumns();
        //}

        private void simpleButton3_Click(object sender, EventArgs e)
        {
            DataRow newRow = table.NewRow();
            newRow["Amount"] = 0;
            newRow["EWTAmount"] = 0m;      // NEW
            newRow["EWTManual"] = false;   // NEW
            table.Rows.Add(newRow);
            gridControl1.DataSource = table;
            gridView1.BestFitColumns();
        }


        private void gridView1_CustomRowCellEdit(object sender, DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventArgs e)
        {
            //if (e.Column.FieldName == "BranchCode")
            //    e.RepositoryItem = repbrcode;
            //if (e.Column.FieldName == "TypeOfExpense")
            //    e.RepositoryItem = reptypeofexpense;
            //if (e.Column.FieldName == "Particulars")
            //    e.RepositoryItem = repparticulars;
            //if (e.Column.FieldName == "Amount")
            //    e.RepositoryItem = repamount;

            if (e.Column.FieldName == "BranchCode")
                e.RepositoryItem = repbrcode;
            if (e.Column.FieldName == "TypeOfExpense")
                e.RepositoryItem = reptypeofexpense;
            if (e.Column.FieldName == "Particulars")
                e.RepositoryItem = repparticulars;
            if (e.Column.FieldName == "Amount")
                e.RepositoryItem = repamount;
            if (e.Column.FieldName == "EWTAmount")          // NEW
                e.RepositoryItem = repamount;                // reuse the same numeric editor;
                                                             // add a dedicated repewtamount in
                                                             // the designer if you want different
                                                             // formatting/read-only behavior
        }
        private DataTable BuildExpenseTVP()
        {
            var dt = new DataTable();
            dt.Columns.Add("BranchCode", typeof(string));
            dt.Columns.Add("ExpenseName", typeof(string));
            dt.Columns.Add("Particulars", typeof(string));
            dt.Columns.Add("Amount", typeof(decimal));
            dt.Columns.Add("EWTAmount", typeof(decimal));   // NEW - must stay last

            for (int i = 0; i < gridView1.RowCount; i++)
            {
                var branch = gridView1.GetRowCellValue(i, "BranchCode")?.ToString()?.Trim();
                var expType = gridView1.GetRowCellValue(i, "TypeOfExpense")?.ToString()?.Trim();
                var remarks = gridView1.GetRowCellValue(i, "Particulars")?.ToString()?.Trim() ?? "";

                if (!decimal.TryParse(
                        gridView1.GetRowCellValue(i, "Amount")?.ToString(),
                        out var amount) || amount <= 0)
                    continue;   // skip zero/invalid rows silently (ValidateGridRows catches real errors)
                decimal.TryParse(gridView1.GetRowCellValue(i, "EWTAmount")?.ToString(), out var ewtAmount); // NEW

                dt.Rows.Add(branch, expType, remarks, amount, ewtAmount);  // NEW: ewtAmount appended
                //dt.Rows.Add(branch, expType, remarks, amount);
            }

            return dt;
        }

        private async void simpleButton4_Click(object sender, EventArgs e)
        {
            bool isInvoiceExists = Database.checkifExist($"SELECT 1 FROM ExpenseSummary WHERE SupplierID='{suppid.ToString()}' and InvoiceNo='{txtinvoiceno.Text.Trim()}'");
            // Grid must have rows
            if (gridView1.RowCount == 0)
            {
                XtraMessageBox.Show("No expense detail lines entered.", "Validation",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            if(isInvoiceExists)
            {
                XtraMessageBox.Show("Invoice No. already Exists.", "Validation",
                 MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            // All rows must have BranchCode and TypeOfExpense
            if (!ValidateGridRows()) return;

            // Invoice number required
            if (string.IsNullOrWhiteSpace(txtinvoiceno.Text))
            {
                XtraMessageBox.Show("Invoice No. is required.", "Validation",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // Build TVP
            var tvpTable = BuildExpenseTVP();
            if (tvpTable == null || tvpTable.Rows.Count == 0)
            {
                XtraMessageBox.Show("No valid expense lines to post (check Amount > 0).", "Validation",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("dbo.sp_PostExpense", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 60;

                    cmd.Parameters.Add("@parmrefno", SqlDbType.VarChar, 10).Value = txtrefno.Text.Trim();
                    cmd.Parameters.Add("@parmbatchrefno", SqlDbType.BigInt).Value = Convert.ToInt64(txtbatchid.Text.Trim());
                    cmd.Parameters.Add("@parmsupplierid", SqlDbType.VarChar, 100).Value = suppid.ToString();
                    cmd.Parameters.Add("@parminvoiceno", SqlDbType.VarChar, 150).Value = txtinvoiceno.Text.Trim();
                    cmd.Parameters.Add("@parmshipmentno", SqlDbType.VarChar, 150).Value = txtpo.Text.Trim();
                    cmd.Parameters.Add("@parmexpensedate", SqlDbType.Date).Value = Convert.ToDateTime(txtexpdate.Text);
                    cmd.Parameters.Add("@parmremarks", SqlDbType.VarChar, 2000).Value = txtremarks.Text.Trim();
                    cmd.Parameters.Add("@parmuser", SqlDbType.VarChar, 40).Value = Login.Fullname;

                    var tvpParam = cmd.Parameters.AddWithValue("@Lines", tvpTable);
                    tvpParam.SqlDbType = SqlDbType.Structured;
                    tvpParam.TypeName = "dbo.ExpenseEntryTVP";

                    con.Open();
                    cmd.ExecuteNonQuery();
                }

                XtraMessageBox.Show("Expense successfully submitted for approval.", "Success",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                //Dispose();
                await ResetUIAsync();

            }
            catch (SqlException ex)
            {
                // Show SQL error number + message for easier debugging
                XtraMessageBox.Show(
                    $"Database error ({ex.Number}): {ex.Message}",
                    "Post Expense Failed",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
        // Add this method to handle clearing out the old transaction details
        private async Task ResetUIAsync()
        {
            try
            {
                UseWaitCursor = true;

                // 1. Clear the grid data
                if (table != null)
                {
                    table.Rows.Clear();
                }

                // 2. Clear user inputs
                txtinvoiceno.Text = string.Empty;
                txtremarks.Text = string.Empty;
                txtvendor.EditValue = null;

                chcklinktopo.Checked = false;
                txtpo.EditValue = null;
                txtpo.Enabled = false;

                // 3. Generate new reference IDs for the next transaction
                txtrefno.Text = await Task.Run(() => IDGenerator.getIDNumberSP("spGetReferenceNumber", "ReferenceNumber"));
                txtbatchid.Text = await Task.Run(() => IDGenerator.getIDNumberSP("sp_GetBatchReferenceID", "BatchReferenceID"));
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show($"Error resetting form: {ex.Message}", "Warning", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            finally
            {
                UseWaitCursor = false;
            }
        }
        private bool ValidateGridRows()
        {
            for (int i = 0; i < gridView1.RowCount; i++)
            {
                var branch = gridView1.GetRowCellValue(i, "BranchCode")?.ToString();
                var expType = gridView1.GetRowCellValue(i, "TypeOfExpense")?.ToString();

                if (string.IsNullOrWhiteSpace(branch) || string.IsNullOrWhiteSpace(expType))
                {
                    gridView1.FocusedRowHandle = i;
                    XtraMessageBox.Show(
                        $"Row {i + 1}: BranchCode and Type of Expense are required.",
                        "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }

                // Amount must be numeric and > 0
                var rawAmt = gridView1.GetRowCellValue(i, "Amount")?.ToString();
                if (!decimal.TryParse(rawAmt, out var amt) || amt <= 0)
                {
                    gridView1.FocusedRowHandle = i;
                    XtraMessageBox.Show(
                        $"Row {i + 1}: Amount must be a positive number.",
                        "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
            }
            return true;
        }


        private void gridControl1_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStrip1.Show(gridControl1, e.Location);
        }

        private void cancelLineToolStripMenuItem_Click(object sender, EventArgs e)
        {
            gridView1.DeleteSelectedRows();
        }

        private void btnget_Click(object sender, EventArgs e)
        {
            getquery();
        }
        void getquery()
        {

            if (checkBox1.Checked == true) //if all branch
            {
                ok = true;
            }
            else
            {
                ok = false;
            }

            if (ok)
            {
                Database.display("SELECT * FROM view_ExpenseMaster WHERE ExpenseDate >= '" + datefrom.Text + "' and ExpenseDate <= '" + dateto.Text + "'", gridControl2, gridView2);
            }
            else
            {
                Database.display("SELECT * FROM view_ExpenseMaster WHERE ExpenseDate >= '" + datefrom.Text + "' and ExpenseDate <= '" + dateto.Text + "' AND BranchCode='" + txtbrcodesum.Text + "'", gridControl2, gridView2);
            }
        }

        private void checkBox1_CheckedChanged(object sender, EventArgs e)
        {
            if (checkBox1.Checked == true)
            {
                ok = true;
                txtbrcodesum.Text = "";
                txtbrcodesum.Enabled = false;
            }
            else
            {
                ok = false;
                txtbrcodesum.Enabled = true;
                Database.displayDevComboBoxItems("SELECT BranchCode from Branches", "BranchCode", txtbrcodesum);
            }
        }

        private void gridControl2_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStrip2.Show(gridControl2, e.Location);
        }

        private void toolStripMenuItem1_Click(object sender, EventArgs e)
        {
            if (Convert.ToBoolean(gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "isErrorCorrect").ToString()) == true)
            {
                XtraMessageBox.Show("Entry Already Corrected!");
                return;
            }
            else
            {
                reverseExpense();
                XtraMessageBox.Show("Success");
                btnget.PerformClick();
            }
        }
        void reverseExpense()
        {
            try
            {

                SqlConnection con = Database.getConnection();
                con.Open();
                string query = "sp_ExpenseReversal";
                SqlCommand com = new SqlCommand(query, con);
                com.Parameters.AddWithValue("@parmvoucherid", txtrefno.Text);
                com.Parameters.AddWithValue("@parmuser", Login.Fullname);
                com.Parameters.AddWithValue("@parmseq", gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "SequenceNumber").ToString());
                com.CommandType = CommandType.StoredProcedure;
                com.CommandText = query;
                com.ExecuteNonQuery();
                con.Close();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }

        private void gridView2_RowStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowStyleEventArgs e)
        {
            //GridView view = (GridView)sender;
            //bool check = Convert.ToBoolean(view.GetRowCellValue(e.RowHandle, "isErrorCorrect"));
            //if (check)
            //{
            //    e.Appearance.Font = new System.Drawing.Font(e.Appearance.Font, FontStyle.Strikeout);
            //    e.Appearance.ForeColor = Color.Red;
            //}
            var view = (GridView)sender;
            string expenseName = view.GetRowCellValue(e.RowHandle, "TypeOfExpense")?.ToString();
            var mapping = GetEWTMapping(expenseName);

            if (mapping.HasEWT && mapping.IsRateAmbiguous)
            {
                e.Appearance.ForeColor = Color.DarkOrange;
                // Optional: e.Appearance.Font = new Font(e.Appearance.Font, FontStyle.Bold);
            }
        }

        private void txtvendor_EditValueChanged(object sender, EventArgs e)
        {
            suppid = SearchLookUpClass.getSingleValue(txtvendor, "SupplierID");
        }

        private bool _poLoaded = false;
        private bool _isLoadingPO = false;

        private async void chcklinktopo_CheckedChanged(object sender, EventArgs e)
        {

            if (chcklinktopo.Checked)
            {
                txtpo.Enabled = false; // disable while loading

                // Prevent duplicate calls
                if (_poLoaded || _isLoadingPO)
                {
                    txtpo.Enabled = true;
                    return;
                }

                try
                {
                    _isLoadingPO = true;
                    Cursor = Cursors.WaitCursor;

                    var purchaseList = await GetDataTableAsync(@"
                SELECT ShipmentNo, SupplierId, SupplierName
                FROM dbo.view_POSUMMARYREP
                WHERE Status <> 'CANCELLED'");

                    BindPurchaseList(purchaseList);

                    _poLoaded = true;
                }
                catch (Exception ex)
                {
                    DevExpress.XtraEditors.XtraMessageBox.Show(
                        ex.Message,
                        "Error",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                }
                finally
                {
                    _isLoadingPO = false;
                    txtpo.Enabled = true;
                    Cursor = Cursors.Default;
                }
            }
            else
            {
                // Disable AND clear selection
                txtpo.EditValue = null;
                txtpo.Properties.DataSource = null;
                txtpo.Enabled = false;

                // Optional: if you want reload every time user checks again
                // _poLoaded = false;
            }

        }

        private async void PostExpenseDevExFrm_Shown(object sender, EventArgs e)
        {

            if (_initialized) return;
            _initialized = true;

            await InitializeFormAsync();

        }
        private async Task InitializeFormAsync()
        {
            try
            {
                UseWaitCursor = true;

                txtrefno.Text = await Task.Run(() =>
                    IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber"));

                txtbatchid.Text = await Task.Run(() =>
                    IDGenerator.getIDNumberSP("sp_GetBatchReferenceID", "BatchReferenceID"));

                var branches = await GetDataTableAsync("SELECT BranchCode, BranchName FROM Branches");
                var vendors = await GetDataTableAsync("SELECT SupplierID, SupplierName FROM Supplier");
                var expenses = await GetDataTableAsync("SELECT ExpenseName FROM ExpensesList");

            //NEW: pull the EWT - bearing mappings once
                var ewtRows = await GetDataTableAsync(@"
                    SELECT ExpenseName, AccountCode AS EWTAccountCode,
                           ATCCode, ATCRate, IsRateAmbiguous
                    FROM ExpenseJournalMapping
                    WHERE AmountType = 'EWT' AND DebitCredit = 'C' AND IsActive = 1");

                BuildEWTMapCache(ewtRows);   // NEW

                BindBranchesToComboBox(branches);
                BindVendors(vendors);
                BindRepositoryItems(branches, expenses);
            }
            catch (Exception ex)
            {
                DevExpress.XtraEditors.XtraMessageBox.Show(
                    $"Error loading form: {ex.Message}",
                    "Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            finally
            {
                UseWaitCursor = false;
            }
        }
        private void BuildEWTMapCache(DataTable ewtRows)
        {
            _ewtMap.Clear();
            foreach (DataRow row in ewtRows.Rows)
            {
                string name = row["ExpenseName"].ToString();
                if (_ewtMap.ContainsKey(name)) continue; // keep first (lowest Seq) per name
                _ewtMap[name] = new ExpenseEWTMapping
                {
                    HasEWT = true,
                    EWTAccountCode = row["EWTAccountCode"]?.ToString(),
                    ATCCode = row["ATCCode"] as string,
                    ATCRate = row["ATCRate"] == DBNull.Value ? 0m : Convert.ToDecimal(row["ATCRate"]),
                    IsRateAmbiguous = row["IsRateAmbiguous"] != DBNull.Value && Convert.ToBoolean(row["IsRateAmbiguous"])
                };
            }
        }
        private ExpenseEWTMapping GetEWTMapping(string expenseName)
        {
            if (!string.IsNullOrWhiteSpace(expenseName) && _ewtMap.TryGetValue(expenseName, out var m))
                return m;
            return new ExpenseEWTMapping { HasEWT = false };
        }
        // ── NEW ──
        //private void BuildEWTMapCache(DataTable ewtRows)
        //{
        //    _ewtMap.Clear();
        //    foreach (DataRow row in ewtRows.Rows)
        //    {
        //        string name = row["ExpenseName"].ToString();
        //        _ewtMap[name] = new ExpenseEWTMapping
        //        {
        //            HasEWT = true,
        //            EWTAccountCode = row["EWTAccountCode"]?.ToString(),
        //            ATCCode = row["ATCCode"] as string,
        //            ATCRate = row["ATCRate"] == DBNull.Value ? 0m : Convert.ToDecimal(row["ATCRate"]),
        //            IsRateAmbiguous = row["IsRateAmbiguous"] != DBNull.Value && Convert.ToBoolean(row["IsRateAmbiguous"])
        //        };
        //    }
        //}

        // ── NEW: looks up the cache; returns HasEWT=false for anything not in it ──
        //private ExpenseEWTMapping GetEWTMapping(string expenseName)
        //{
        //    //if (!string.IsNullOrWhiteSpace(expenseName) && _ewtMap.TryGetValue(expenseName, out var m))
        //    //    return m;
        //    //return new ExpenseEWTMapping { HasEWT = false };
        //    var result = new ExpenseEWTMapping { HasEWT = false };
        //    if (string.IsNullOrWhiteSpace(expenseName)) return result;

        //    const string sql = @"
        //        SELECT TOP 1
        //            AccountCode AS EWTAccountCode, ATCCode, ATCRate, IsRateAmbiguous
        //        FROM ExpenseJournalMapping
        //        WHERE ExpenseName = @ExpenseName
        //          AND AmountType  = 'EWT'
        //          AND DebitCredit = 'C'
        //          AND IsActive    = 1
        //        ORDER BY Seq;";

        //    using (var con = Database.getConnection())
        //    using (var cmd = new SqlCommand(sql, con))
        //    {
        //        cmd.Parameters.AddWithValue("@ExpenseName", expenseName);
        //        con.Open();
        //        using (var reader = cmd.ExecuteReader())
        //        {
        //            if (reader.Read())
        //            {
        //                result.HasEWT = true;
        //                result.EWTAccountCode = reader["EWTAccountCode"] as string;
        //                result.ATCCode = reader["ATCCode"] as string;
        //                result.ATCRate = reader["ATCRate"] == DBNull.Value ? 0m : Convert.ToDecimal(reader["ATCRate"]);
        //                result.IsRateAmbiguous = reader["IsRateAmbiguous"] != DBNull.Value && Convert.ToBoolean(reader["IsRateAmbiguous"]);
        //            }
        //        }
        //    }
        //    return result;
        //}

       
        private async Task<DataTable> GetDataTableAsync(string sql)
        {
            var dt = new DataTable();

            using (var con = Database.getConnection()) // replace with your actual connection string
            using (var cmd = new SqlCommand(sql, con))
            {
                await con.OpenAsync();

                using (var reader = await cmd.ExecuteReaderAsync())
                {
                    dt.Load(reader);
                }
            }

            return dt;
        }

        private void BindBranchesToComboBox(DataTable branches)
        {
            txtbrcodesum.Properties.BeginUpdate();
            try
            {
                txtbrcodesum.Properties.Items.Clear();

                foreach (DataRow row in branches.Rows)
                {
                    txtbrcodesum.Properties.Items.Add(row["BranchCode"]?.ToString());
                }

                // Optional: no default selected item
                txtbrcodesum.SelectedIndex = -1;
                txtbrcodesum.EditValue = null;
            }
            finally
            {
                txtbrcodesum.Properties.EndUpdate();
            }
        }

        private void BindVendors(DataTable vendors)
        {
            txtvendor.Properties.BeginUpdate();
            try
            {
                txtvendor.Properties.DataSource = vendors;
                txtvendor.Properties.DisplayMember = "SupplierName";
                txtvendor.Properties.ValueMember = "SupplierID";
                txtvendor.Properties.PopulateViewColumns();

                if (txtvendor.Properties.View.Columns["SupplierID"] != null)
                    txtvendor.Properties.View.Columns["SupplierID"].Visible = false;
            }
            finally
            {
                txtvendor.Properties.EndUpdate();
            }
        }
        private void BindPurchaseList(DataTable purchaseList)
        {
            txtpo.Properties.BeginUpdate();
            try
            {
                txtpo.Properties.DataSource = purchaseList;
                txtpo.Properties.DisplayMember = "SupplierName";
                txtpo.Properties.ValueMember = "ShipmentNo"; // better unique key if PO selection is by shipment
                txtpo.Properties.PopulateViewColumns();

                if (txtpo.Properties.View.Columns["SupplierId"] != null)
                    txtpo.Properties.View.Columns["SupplierId"].Visible = false;
            }
            finally
            {
                txtpo.Properties.EndUpdate();
            }
        }
        private void BindRepositoryItems(DataTable branches, DataTable expenses)
        {
            repbrcode.BeginUpdate();
            reptypeofexpense.BeginUpdate();

            try
            {

                // Add computed column for display
                if (!branches.Columns.Contains("DisplayText"))
                {
                    branches.Columns.Add("DisplayText", typeof(string));

                    foreach (DataRow row in branches.Rows)
                    {
                        row["DisplayText"] = $"{row["BranchCode"]} - {row["BranchName"]}";
                    }
                }

                // Bind to repository
                repbrcode.DataSource = branches;
                repbrcode.DisplayMember = "DisplayText";   // what user sees
                repbrcode.ValueMember = "BranchCode";      // what gets saved


                //repbrcode.DataSource = branches;
                //repbrcode.DisplayMember = "BranchCode";
                //repbrcode.ValueMember = "BranchCode";

                reptypeofexpense.DataSource = expenses;
                reptypeofexpense.DisplayMember = "ExpenseName";
                reptypeofexpense.ValueMember = "ExpenseName";


                //repbrcode.AutoHeight = false;
                //reptypeofexpense.AutoHeight = false;
                //repparticulars.AutoHeight = false;
                //repamount.AutoHeight = false;

                //repbrcode.PopupFormSize = new Size(400, 300);
                //reptypeofexpense.PopupFormSize = new Size(400, 300);

            }
            finally
            {
                repbrcode.EndUpdate();
                reptypeofexpense.EndUpdate();
            }

            // BestFit can be costly, so keep it after binding
            gridView2.BestFitColumns();
            gridView3.BestFitColumns();
        }

        private void gridView1_CellValueChanging(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {

        }

        private void gridView1_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            //if (e.Column.FieldName == "TypeOfExpense" || e.Column.FieldName == "Amount")
            //    RecalculateRowEWT(e.RowHandle);

            //gridView1.BestFitColumns();
            if (e.Column.FieldName == "TypeOfExpense")
            {
                // Category changed - any prior manual EWT is now stale, re-suggest
                RecalculateRowEWT(e.RowHandle, forceRecalc: true);
            }
            else if (e.Column.FieldName == "Amount")
            {
                // Only auto-recalc if the user hasn't manually overridden EWT for this row
                RecalculateRowEWT(e.RowHandle, forceRecalc: false);
            }
            else if (e.Column.FieldName == "EWTAmount" && !_isAutoCalculating)
            {
                // Real user keystroke into EWTAmount - remember it as an override
                gridView1.SetRowCellValue(e.RowHandle, "EWTManual", true);
                // ── NEW VALIDATION ──
                decimal.TryParse(gridView1.GetRowCellValue(e.RowHandle, "Amount")?.ToString(), out var amount);
                decimal.TryParse(gridView1.GetRowCellValue(e.RowHandle, "EWTAmount")?.ToString(), out var ewt);

                if (ewt > amount)
                {
                    MessageBox.Show("EWT Amount must not be greater than Amount.",
                                    "Validation Error",
                                    MessageBoxButtons.OK,
                                    MessageBoxIcon.Warning);

                    // Reset to safe value
                    gridView1.SetRowCellValue(e.RowHandle, "EWTAmount", 0m);
                }
            }

            //gridView1.BestFitColumns();
        }
        // ── NEW ──
        private void RecalculateRowEWT(int rowHandle, bool forceRecalc)
        {
            var manualVal = gridView1.GetRowCellValue(rowHandle, "EWTManual");
            bool isManual = manualVal != null && manualVal != DBNull.Value && Convert.ToBoolean(manualVal);
            if (isManual && !forceRecalc)
                return;   // user already set this by hand - leave it alone

            string expenseName = gridView1.GetRowCellValue(rowHandle, "TypeOfExpense")?.ToString();
            decimal.TryParse(gridView1.GetRowCellValue(rowHandle, "Amount")?.ToString(), out var amount);

            var mapping = GetEWTMapping(expenseName);

            decimal ewt = mapping.HasEWT
                ? Math.Round(amount * mapping.ATCRate, 2, MidpointRounding.AwayFromZero)
                : 0m;

            _isAutoCalculating = true;
            try
            {
                gridView1.SetRowCellValue(rowHandle, "EWTAmount", ewt);
                if (forceRecalc)
                    gridView1.SetRowCellValue(rowHandle, "EWTManual", false);
            }
            finally
            {
                _isAutoCalculating = false;
            }
            //string expenseName = gridView1.GetRowCellValue(rowHandle, "TypeOfExpense")?.ToString();
            //decimal.TryParse(gridView1.GetRowCellValue(rowHandle, "Amount")?.ToString(), out var amount);

            //var mapping = GetEWTMapping(expenseName);

            //decimal ewt = mapping.HasEWT
            //    ? Math.Round(amount * mapping.ATCRate, 2, MidpointRounding.AwayFromZero)
            //    : 0m;

            //// Setting via SetRowCellValue (not table row directly) keeps the
            //// grid's own change-tracking consistent
            //gridView1.SetRowCellValue(rowHandle, "EWTAmount", ewt);
        }

        private void gridView1_ShowingEditor(object sender, CancelEventArgs e)
        {
            if (gridView1.FocusedColumn?.FieldName != "EWTAmount")
                return;

            string expenseName = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "TypeOfExpense")?.ToString();
            var mapping = GetEWTMapping(expenseName);

            if (!mapping.HasEWT)
                e.Cancel = true;
        }

        private void gridView1_RowCellStyle(object sender, RowCellStyleEventArgs e)
        {
            if (e.Column.FieldName != "EWTAmount")
                return;

            string expenseName = gridView1.GetRowCellValue(e.RowHandle, "TypeOfExpense")?.ToString();
            var mapping = GetEWTMapping(expenseName);

            if (!mapping.HasEWT)
            {
                e.Appearance.BackColor = Color.WhiteSmoke;
                e.Appearance.ForeColor = Color.Gray;
            }
        }

        private void txtpo_EditValueChanged(object sender, EventArgs e)
        {
            shipmentno = SearchLookUpClass.getSingleValue(txtpo, "ShipmentNo");
        }

    }
    public class ExpenseEWTMapping
    {
        public bool HasEWT { get; set; }
        public string ATCCode { get; set; }
        public decimal ATCRate { get; set; }        // fraction, e.g. 0.10 = 10%
        public bool IsRateAmbiguous { get; set; }
        public string EWTAccountCode { get; set; }
    }

}