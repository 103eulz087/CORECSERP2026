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
using DevExpress.XtraReports.UI;
using SalesInventorySystem.Classes;
using System.Globalization;

namespace SalesInventorySystem.AccountingDevEx
{
    public partial class SupplierPaymentDevEx : DevExpress.XtraEditors.XtraUserControl
    { // ── State ────────────────────────────────────────────────────────────
        object _suppid = "";
        private string _referenceNo = "";
        private string _voucherId = "";
        private string _voucherType = "";
        private string _payMethod = "";  // "PURCHASE" | "EXPENSE"
        private DataTable _linesTable;
        // ✅ Put this near the top with your fields (referenceno, voucherid, etc.)
        private class PaymentLine
        {
            public long SequenceNumber { get; set; }
            public long BatchReferenceID { get; set; }
            public string BranchCode { get; set; }
            public string InvoiceNo { get; set; }
            //public string SequenceReferenceNumber { get; set; }
            public DateTime InvoiceDate { get; set; }
            public decimal ActualCost { get; set; }
            public decimal AmountPaid { get; set; }
            public decimal Balance { get; set; }
            public decimal DiscountAmount { get; set; }
            public decimal EWTAmount { get; set; }
            public decimal ReturnAllowances { get; set; }

            public decimal Variance { get; set; }   // NEW
            public decimal OffsetAmount { get; set; }
            public string DiscountAccountCode { get; set; }   // NEW — null/blank = use default '508'
            public string Description { get; set; }
        }
        private bool _isRecalculating = false;
        private int _loadedYear = 0;
        private int _loadedMonth = 0;
        private int _currentYearSequence = 0;
        private int _currentMonthSequence = 0;
        private void GenerateVoucherNumber()
        {
            // Validate Check Date
            if (txtcheckdate.EditValue == null ||
                !DateTime.TryParse(txtcheckdate.EditValue.ToString(), out DateTime checkDate))
            {
                txtcheckcoding.Text = "";
                txtcheckno.Text = "";
                return;
            }

            // Validate Credit GL Code / Bank Selection
            if (searchLookUpEdit1.EditValue == null ||
                string.IsNullOrWhiteSpace(searchLookUpEdit1.EditValue.ToString()))
            {
                txtcheckcoding.Text = "";
                txtcheckno.Text = "";
                return;
            }

            int year = checkDate.Year;
            int month = checkDate.Month;

            string yy = checkDate.ToString("yy");
            string mm = checkDate.ToString("MM");

            if (_loadedMonth != month)
            {
                _currentMonthSequence = GetNextSequenceForMonth(year, month);
                _loadedMonth = month;
            }

            string seq = _currentMonthSequence.ToString("D3");

            string bankCodeStr = searchLookUpEdit1.EditValue.ToString();

            string bank = GetBank(bankCodeStr);
            string actualCheck = GetLastCheckNo();

            txtcheckcoding.Text = $"CV{yy}{mm}-{seq}{bank}";
            txtcheckno.Text = actualCheck;
        }

        private string GetLastCheckNo()
        {
            if (searchLookUpEdit1.EditValue == null)
                return "100000000";

            string sql = @"
        SELECT TOP(1) CheckNo
        FROM dbo.CheckVoucher
       WHERE OfficialReceiptNo=@bankglcode
        ORDER BY VoucherID DESC, SequenceNumber DESC";

            string lastCheckNo = null;

            using (SqlConnection conn = Database.getConnection())
            using (SqlCommand cmd = new SqlCommand(sql, conn))
            {
                cmd.Parameters.AddWithValue(
                    "@bankglcode",
                    searchLookUpEdit1.EditValue.ToString());

                conn.Open();

                object result = cmd.ExecuteScalar();

                if (result != null && result != DBNull.Value)
                    lastCheckNo = result.ToString();
            }

            if (string.IsNullOrEmpty(lastCheckNo))
                return "100000000";

            return lastCheckNo;
        }


        private string GetBank(string AcctCode)
        {
            // Grab the value and safely convert it to a string
            return Database.getSingleQuery($"SELECT TOP(1) Bank FROM dbo.BankCoa WHERE AccountCode='{AcctCode}'", "Bank");
        }
        private bool CanGenerateVoucher()
        {
            return txtcheckdate.EditValue != null &&
                   searchLookUpEdit1.EditValue != null;
        }
        private void WireEvents()
        {
            txtcheckdate.EditValueChanged += (s, e) =>
            {
                if (CanGenerateVoucher())
                    GenerateVoucherNumber();
            };

            searchLookUpEdit1.EditValueChanged += (s, e) =>
            {
                if (CanGenerateVoucher())
                    GenerateVoucherNumber();
            };
        }

        private int GetNextSequenceForMonth(int year,int month)
        {
            try
            {
                using (var con = Database.getConnection())
                {
                    // Counts all checks issued in the selected year based on your CheckVoucher table
                    string query = "SELECT COUNT(*) FROM CheckVoucher WHERE YEAR(CheckDate)=@Year AND MONTH(CheckDate) = @Month";

                    using (var cmd = new SqlCommand(query, con))
                    {
                        cmd.Parameters.AddWithValue("@Year", year);
                        cmd.Parameters.AddWithValue("@Month", month);
                        con.Open();

                        object result = cmd.ExecuteScalar();
                        int currentCount = (result != null && result != DBNull.Value) ? Convert.ToInt32(result) : 0;

                        // Return the next available number
                        return currentCount + 1;
                    }
                }
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show($"Error fetching check sequence: {ex.Message}", "Database Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1; // Default to 1 if it fails
            }
        }
        // ✅ Put this below PaymentLine (order doesn’t matter as long as both are inside the class)
        private List<PaymentLine> GetSelectedLines()
        {
            var lines = new List<PaymentLine>();

            for (int i = 0; i < gridViewMaster.RowCount; i++)
            {
                bool pay = ToBool(gridViewMaster.GetRowCellValue(i, "Pay"));
                if (!pay) continue;

                lines.Add(new PaymentLine
                {
                    SequenceNumber = Convert.ToInt64(gridViewMaster.GetRowCellValue(i, "SequenceNumber") ?? 0),
                    BatchReferenceID = Convert.ToInt64(gridViewMaster.GetRowCellValue(i, "BatchReferenceID") ?? 0),
                    BranchCode = "",//Convert.ToString(gridViewMaster.GetRowCellValue(i, "BranchCode") ?? ""),
                    InvoiceNo = Convert.ToString(gridViewMaster.GetRowCellValue(i, "InvoiceNo") ?? ""),
                    //SequenceReferenceNumber = Convert.ToString(gridViewMaster.GetRowCellValue(i, "SequenceReferenceNumber") ?? ""),
                    InvoiceDate = Convert.ToDateTime(gridViewMaster.GetRowCellValue(i, "InvoiceDate") ?? DateTime.MinValue),
                    ActualCost = Convert.ToDecimal(gridViewMaster.GetRowCellValue(i, "ActualCost") ?? 0m), //NET
                    AmountPaid = Convert.ToDecimal(gridViewMaster.GetRowCellValue(i, "AmountPaid") ?? 0m), //NET
                    Balance = SafeToDecimal(gridViewMaster.GetRowCellValue(i, "Balance")),
                    DiscountAmount = Convert.ToDecimal(gridViewMaster.GetRowCellValue(i, "DiscountAmount") ?? 0m),
                    EWTAmount = Convert.ToDecimal(gridViewMaster.GetRowCellValue(i, "EWTAmount") ?? 0m),
                    ReturnAllowances = Convert.ToDecimal(gridViewMaster.GetRowCellValue(i, "ReturnAllowances") ?? 0m),
                    OffsetAmount = Convert.ToDecimal(gridViewMaster.GetRowCellValue(i, "OffsetAmount") ?? 0m),
                    Variance = Convert.ToDecimal(gridViewMaster.GetRowCellValue(i, "Variance") ?? 0m),   // NEW
                    DiscountAccountCode = Convert.ToString(gridViewMaster.GetRowCellValue(i, "DiscountAccountCode") ?? ""),
                    Description = Convert.ToString(gridViewMaster.GetRowCellValue(i, "Description") ?? "")
                });
            }

            return lines;
        }
        private static decimal SafeToDecimal(object value)
        {
            if (value == null || value == DBNull.Value) return 0m;

            if (value is decimal d) return d;
            if (value is double db) return (decimal)db;
            if (value is float f) return (decimal)f;
            if (value is int i) return i;
            if (value is long l) return l;

            var s = value.ToString().Trim();

            // remove thousands separators
            s = s.Replace(",", "");

            if (decimal.TryParse(s,
                System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture,
                out var result))
            {
                return result;
            }

            throw new InvalidCastException($"Cannot convert value '{value}' to decimal.");
        }

        
        public static bool isdone = false, forliquidation = false;
        public SupplierPaymentDevEx()
        {
            InitializeComponent();
            WireEvents();
            repositoryItemCheckEditStat.EditValueChanged += RepositoryItemCheckEditStat_EditValueChanged;
        }
        private void RepositoryItemCheckEditStat_EditValueChanged(object sender, EventArgs e)
        {
            gridViewMaster.PostEditor();        // commit immediately
            gridViewMaster.UpdateCurrentRow();  // trigger CellValueChanged
        }


        void radChanged()
        {
            if (radCashVoucher.Checked == true)
            {
                panelCheckVoucher.Visible = false;
              
            }
            else if (radCheckVoucher.Checked == true)
            {
                panelCheckVoucher.Visible = true;
              
            }
            else if (radtelegraphic.Checked == true)
            {
                panelCheckVoucher.Visible = false;
               
            }
        }
        private bool _dataLoaded = false;

        public void LoadData()
        {
            if (_dataLoaded)
                return;

            Database.displaySearchlookupEdit(
                "SELECT SupplierID,SupplierName FROM Supplier",
                searchLookUpSupplier,
                "SupplierName",
                "SupplierName");

            populateCOA();
            radChanged();
            BindDebitAccountLookup();
            BindBranchLineLookup();

            _dataLoaded = true;
        }
        private void SupplierPaymentDevEx_Load(object sender, EventArgs e)
        {
            _linesTable = new DataTable();
            _linesTable.Columns.Add("BranchCode", typeof(string));   // NEW
            _linesTable.Columns.Add("AccountCode", typeof(string));
            _linesTable.Columns.Add("PayeeName", typeof(string));
            _linesTable.Columns.Add("Amount", typeof(decimal));
            _linesTable.Columns.Add("Particulars", typeof(string));
            gridControlLines.DataSource = _linesTable;

            gridViewLines.Columns["PayeeName"].Visible = false;

            AddLine();
            UpdateTotal();

            //ResetForNewEntry(clearRemarks: true);
        }
        public void RefreshVoucher()
        {
            // Reset cached values
            _loadedMonth = 0;
            _currentMonthSequence = 0;

            // Clear controls if desired
            txtcheckcoding.Text = string.Empty;
            txtcheckno.Text = string.Empty;

            // Generate new values based on current selections
            GenerateVoucherNumber();
        }
        private void ResetForNewEntry(bool clearRemarks)
        {
            RefreshVoucher();

            _linesTable.Rows.Clear();
            AddLine();
            AddLine();

            UpdateTotal();
        }
         
        private void BindBranchLineLookup()
        {
            DataTable dt = GetDataTable(
        "SELECT BranchCode, BranchName, BranchCode + '-' + BranchName AS DisplayText FROM Branches ORDER BY BranchCode");

            repBranchLine.DataSource = dt;
            repBranchLine.DisplayMember = "DisplayText";
            repBranchLine.ValueMember = "BranchCode";
            repBranchLineView.PopulateColumns();      // CHANGED — populate the popup grid's own View
            repBranchLineView.OptionsView.ShowGroupPanel = false;
        }
        private void BindDebitAccountLookup()
        {
            DataTable dt = GetDataTable(@"
                        SELECT coa.AccountCode, coa.Description,
                               coa.AccountCode + '-' + coa.Description AS DisplayText
                        FROM ChartOfAccounts coa
                        ORDER BY coa.AccountCode");

            repDebitAccount.DataSource = dt;
            repDebitAccount.DisplayMember = "DisplayText";
            repDebitAccount.ValueMember = "AccountCode";
            repDebitAccountView.PopulateColumns();    // CHANGED — populate the popup grid's own View
                                                      // Keeping AccountCode/Description/DisplayText all visible here —
                                                      // the search box filters across every visible column, so typing
                                                      // either the code or a word from the description both work.

            if (dt.Rows.Count == 0)
                XtraMessageBox.Show(
                    "No accounts found in ChartOfAccounts.",
                    "Setup Needed", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

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
        private void AddLine()
        {
            DataRow row = _linesTable.NewRow();
            row["Amount"] = 0m;
            row["BranchCode"] = Login.assignedBranch;   // NEW — default, not locked
            _linesTable.Rows.Add(row);
            gridViewLines.BestFitColumns();
        }
        private void UpdateTotal()
        {
            decimal total = 0;
            for (int i = 0; i < gridViewLines.RowCount; i++)
                total += ToDecimal(gridViewLines.GetRowCellValue(i, "Amount"));

            lblTotal.Text = total.ToString("N2");
        }
        
        private void BindCreditGLCodeLookup()
        {
            var dt = GetDataTable("SELECT AccountCode, Description FROM ChartOfAccounts WHERE AccountType='D' ORDER BY AccountCode");
            searchLookUpEdit1.Properties.DataSource = dt;
            searchLookUpEdit1.Properties.DisplayMember = "Description";
            searchLookUpEdit1.Properties.ValueMember = "AccountCode";
            searchLookUpEdit1.Properties.PopulateViewColumns();

        }
        void populateCOA()
        {
            BindCreditGLCodeLookup();
            //Database.displaySearchlookupEdit("SELECT AccountCode,Description FROM ChartOfAccounts WHERE AccountType='D'", searchLookUpEdit1, "AccountCode", "AccountCode");
            Database.displayRepositorySearchlookupEdit("SELECT AccountCode,Description FROM ChartOfAccounts WHERE AccountType='D'", repositoryItemSearchLookUpEditoffsetdebitglcode, "AccountCode", "AccountCode");
            Database.displayRepositorySearchlookupEdit("SELECT AccountCode,Description FROM ChartOfAccounts WHERE AccountType='D'", repositoryItemSearchLookUpEditoffsetCreditGLCode, "AccountCode", "AccountCode");
            Database.displayRepositorySearchlookupEdit("SELECT AccountCode,Description FROM ChartOfAccounts WHERE AccountType='D'", repositoryItemSearchLookUpEditdiscountglcode, "AccountCode", "AccountCode");
            // NEW — same helper, same pattern, defaults the popup to show 508 near the top
            Database.displayRepositorySearchlookupEdit(
                "SELECT AccountCode, Description FROM ChartOfAccounts ORDER BY CASE WHEN AccountCode = '508' THEN 0 ELSE 1 END, AccountCode",
                repDiscountAccount, "AccountCode", "AccountCode");
        }
        
        private bool HasValidDebitLines()
        {
            for (int i = 0; i < gridViewLines.RowCount; i++)
            {
                string acct = gridViewLines.GetRowCellValue(i, "AccountCode")?.ToString();
                decimal amount = ToDecimal(gridViewLines.GetRowCellValue(i, "Amount"));
                if (!string.IsNullOrWhiteSpace(acct) && amount > 0) return true;
            }
            return false;
        }

        private void btnadd_Click(object sender, EventArgs e)
        {
            var lines = GetSelectedLines();
            bool hasInvoices = lines.Count > 0;
            bool hasDebitLines = HasValidDebitLines();

            if (!hasInvoices && !hasDebitLines)
            {
                XtraMessageBox.Show("No Payments Executed!");
                return;
            }

            if (radCheckVoucher.Checked && (String.IsNullOrEmpty(txtcheckno.Text) || String.IsNullOrEmpty(txtcheckdate.Text)))
            {
                XtraMessageBox.Show("Control No and Date must not Empty");
                return;
            }
            else if (radCashVoucher.Checked && (String.IsNullOrEmpty(txtctrlno.Text) ))
            {
                XtraMessageBox.Show("Control No and Date must not Empty");
                return;
            }
            else if (radtelegraphic.Checked && (String.IsNullOrEmpty(txtctrlno.Text)))
            {
                XtraMessageBox.Show("Control No and Date must not Empty");
                return;
            }

            if (hasDebitLines && !ValidateDebitLines()) return;

            PostCombinedVoucher(lines, hasInvoices, hasDebitLines);
        }
        
        private bool ValidateDebitLines()
        {
            bool hasValidLine = false;
            for (int i = 0; i < gridViewLines.RowCount; i++)
            {
                string acct = gridViewLines.GetRowCellValue(i, "AccountCode")?.ToString();
                decimal amount = ToDecimal(gridViewLines.GetRowCellValue(i, "Amount"));

                if (string.IsNullOrWhiteSpace(acct) && amount == 0) continue; // blank row, skip

                if (string.IsNullOrWhiteSpace(acct))
                {
                    XtraMessageBox.Show($"Debit line row {i + 1}: Account is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
                if (amount <= 0)
                {
                    XtraMessageBox.Show($"Debit line row {i + 1}: Amount must be greater than zero.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
                hasValidLine = true;
            }

            if (!hasValidLine)
            {
                XtraMessageBox.Show("Add at least one complete debit line.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
            return true;
        }

        private DataTable BuildManualDebitLinesTVP()
        {
            var dt = new DataTable();
            dt.Columns.Add("BranchCode", typeof(string));
            dt.Columns.Add("AccountCode", typeof(string));
            dt.Columns.Add("Amount", typeof(decimal));
            dt.Columns.Add("Particulars", typeof(string));

            for (int i = 0; i < gridViewLines.RowCount; i++)
            {
                string branch = gridViewLines.GetRowCellValue(i, "BranchCode")?.ToString();
                string acct = gridViewLines.GetRowCellValue(i, "AccountCode")?.ToString();
                decimal amount = ToDecimal(gridViewLines.GetRowCellValue(i, "Amount"));
                string particulars = gridViewLines.GetRowCellValue(i, "Particulars")?.ToString() ?? "";

                if (string.IsNullOrWhiteSpace(acct) || amount <= 0) continue;

                dt.Rows.Add(branch, acct, amount, particulars);
            }

            return dt;
        }
        private void PostCombinedVoucher(List<PaymentLine> lines, bool hasInvoices, bool hasDebitLines)
        {
            _referenceNo = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");
            _voucherId = IDGenerator.getIDNumberSP("sp_GetVoucherNumber", "TicketNumber");

            if (radCheckVoucher.Checked) _voucherType = "CHECK";
            else if (radCashVoucher.Checked) _voucherType = "CASH";
            else if (radtelegraphic.Checked) _voucherType = "TELEGRAPHIC";

            _payMethod = radioButtonPurchase.Checked ? "PURCHASE" : "EXPENSE";

            
            decimal invoiceLegAmount = 0;
            foreach (var ln in lines)
                invoiceLegAmount += ln.AmountPaid;

            var invoiceLinesTvp = BuildPaymentLinesTVP(hasInvoices ? lines : new List<PaymentLine>());
            var manualLinesTvp = BuildManualDebitLinesTVP(); // empty-but-correctly-shaped if hasDebitLines is false

            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("sp_PostSupplierPaymentWithManualLines", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.CommandTimeout = 180;

                cmd.Parameters.Add("@parmrefno", SqlDbType.VarChar, 10).Value = _referenceNo;
                cmd.Parameters.Add("@parmvoucherid", SqlDbType.VarChar, 10).Value = _voucherId;
                cmd.Parameters.Add("@parmsupplierid", SqlDbType.VarChar, 50).Value = txtsupplierid.Text.Trim();
                cmd.Parameters.Add("@parmsuppliername", SqlDbType.VarChar, 150).Value = searchLookUpSupplier.Text;
                cmd.Parameters.Add("@parmcheckcoding", SqlDbType.VarChar, 50).Value = txtcheckcoding.Text.Trim() + txtcheckno.Text.Trim();

                cmd.Parameters.Add("@parmcheckno", SqlDbType.VarChar, 50).Value =
                    radCheckVoucher.Checked ? (object)txtcheckno.Text.Trim() : DBNull.Value;
                cmd.Parameters.Add("@parmcheckdate", SqlDbType.Date).Value =
                    radCheckVoucher.Checked && !string.IsNullOrWhiteSpace(txtcheckdate.Text)
                        ? (object)DateTime.Parse(txtcheckdate.Text) : DBNull.Value;
                cmd.Parameters.Add("@parmcontrolno", SqlDbType.VarChar, 50).Value = txtctrlno.Text.Trim();
                 
                cmd.Parameters.Add("@parmcheckremarks", SqlDbType.VarChar, 2000).Value = txtremakrs.Text.Trim();
                cmd.Parameters.Add("@parmpreparedby", SqlDbType.VarChar, 30).Value = Login.Fullname;
                //cmd.Parameters.Add("@parmglcode", SqlDbType.VarChar, 30).Value = searchLookUpEdit1.Text.Trim();
                cmd.Parameters.Add("@parmglcode", SqlDbType.VarChar, 30).Value = searchLookUpEdit1.EditValue?.ToString();

                cmd.Parameters.Add("@parmpaymethod", SqlDbType.VarChar, 20).Value = _payMethod;
                cmd.Parameters.Add("@parmforliquidation", SqlDbType.Bit).Value = checkforliquidation.Checked;
                cmd.Parameters.Add("@parmvouchertype", SqlDbType.VarChar, 10).Value = _voucherType;
                cmd.Parameters.Add("@parmPayingBranch", SqlDbType.VarChar, 5).Value = Login.assignedBranch;
                cmd.Parameters.Add("@InvoiceLegAmount", SqlDbType.Decimal).Value = invoiceLegAmount;

                var invParam = cmd.Parameters.AddWithValue("@InvoiceLines", invoiceLinesTvp);
                invParam.SqlDbType = SqlDbType.Structured;
                invParam.TypeName = "dbo.AP_PaymentLineTVP";

                var manParam = cmd.Parameters.AddWithValue("@ManualLines", manualLinesTvp);
                manParam.SqlDbType = SqlDbType.Structured;
                manParam.TypeName = "dbo.ManualVoucherDebitLineTVP";

                try
                {
                    con.Open();

                    string message = "Payment successfully posted.";
                    using (var rdr = cmd.ExecuteReader())
                        if (rdr.Read()) message = rdr["Message"]?.ToString() ?? message;

                    BigAlert.Show("SUCCESS", message, MessageBoxIcon.Information);

                    populate();

                    txtctrlno.Text = "";
                     
                    txtlastchecknum.Text = "";
                    txtcheckno.Text = "";
                    txtcheckcoding.Text = "";
                    txtcheckdate.Text = "";
                    searchLookUpEdit1.Text = "";

                    ResetForNewEntry(clearRemarks: true);
                }
                catch (SqlException ex)
                {
                    XtraMessageBox.Show($"Payment failed:\n{ex.Message}", "Error",
                        MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
           
        }


        private void populate()
        {
            //if (!DateTime.TryParse(dateFrom.Text, out var fromDate)) fromDate = DateTime.Today.AddMonths(-1);
            //if (!DateTime.TryParse(dateTo.Text, out var toDate)) toDate = DateTime.Today;

            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("splist_Accounts", con)
            { CommandType = CommandType.StoredProcedure, CommandTimeout = 3600 })
            {
                //cmd.Parameters.Add("@parmdatefrom", SqlDbType.Date).Value = fromDate;
                //cmd.Parameters.Add("@parmdateto", SqlDbType.Date).Value = toDate;
                cmd.Parameters.Add("@parmsupplierid", SqlDbType.VarChar, 30).Value = txtsupplierid.Text.Trim();
                cmd.Parameters.Add("@parmispurchase", SqlDbType.Bit).Value = radioButtonPurchase.Checked;
                cmd.Parameters.Add("@parmisexpense", SqlDbType.Bit).Value = radioButtonExpense.Checked;

                var table = new DataTable();
                try
                {
                    Cursor.Current = Cursors.WaitCursor;
                    UseWaitCursor = true;
                    con.Open();
                    new SqlDataAdapter(cmd).Fill(table);

                    gridControlMaster.BeginUpdate();
                    gridViewMaster.Columns.Clear();
                    gridControlMaster.DataSource = table;
                    gridViewMaster.BestFitColumns();
                    FormatGridColumns();
                }
                catch (SqlException ex)
                {
                    XtraMessageBox.Show($"Error retrieving accounts: {ex.Message}",
                        "Database Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
                finally
                {
                    gridControlMaster.EndUpdate();
                    UseWaitCursor = false;
                    Cursor.Current = Cursors.Default;
                }
            }
            gridViewMaster.Columns[0].Visible = false;

            gridViewMaster.Columns["ShipmentNo"].Visible = false;
            gridViewMaster.Columns["BranchCode"].Visible = false;
            gridViewMaster.Columns["ReferenceNo"].Visible = false;
            gridViewMaster.Columns["BatchReferenceID"].Visible = false;
            gridViewMaster.Columns["ReturnAllowances"].Visible = false;
            Classes.DevXGridViewSettings.ShowFooterTotal(gridViewMaster, "ActualCost");

            if (radioButtonPurchase.Checked == true)
            {
                Classes.DevXGridViewSettings.ShowFooterTotal(gridViewMaster, "AmountPaid");
                Classes.DevXGridViewSettings.ShowFooterTotal(gridViewMaster, "DiscountAmount");
                Classes.DevXGridViewSettings.ShowFooterTotal(gridViewMaster, "EWTAmount");
                Classes.DevXGridViewSettings.ShowFooterTotal(gridViewMaster, "ReturnAllowances");
            }
            else
            {
            }
        }   
        // Helper method to handle DevExpress UI formatting
        private void FormatGridColumns()
        {
            if (gridViewMaster.Columns["ActualCost"] != null)
            {
                gridViewMaster.Columns["ActualCost"].DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                gridViewMaster.Columns["ActualCost"].DisplayFormat.FormatString = "n2";
            }

            if (gridViewMaster.Columns["Balance"] != null)
            {
                gridViewMaster.Columns["Balance"].DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                gridViewMaster.Columns["Balance"].DisplayFormat.FormatString = "n2";
            }
        }
        
        private DataTable BuildPaymentLinesTVP(List<PaymentLine> lines)
        {
            var dt = new DataTable();
            dt.Columns.Add("BranchCode", typeof(string));
            dt.Columns.Add("InvoiceNo", typeof(string));
            dt.Columns.Add("InvoiceDate", typeof(DateTime));
            dt.Columns.Add("SequenceReferenceNumber", typeof(string));
            dt.Columns.Add("BatchReferenceID", typeof(long));
            dt.Columns.Add("ActualCost", typeof(decimal));
            dt.Columns.Add("AmountPaid", typeof(decimal));
            dt.Columns.Add("EWTAmount", typeof(decimal));
            dt.Columns.Add("DiscountAmount", typeof(decimal));
            dt.Columns.Add("ReturnAllowances", typeof(decimal));
            dt.Columns.Add("Description", typeof(string));
            dt.Columns.Add("Variance", typeof(decimal));   // NEW - must stay last
            dt.Columns.Add("DiscountAccountCode", typeof(string));   // NEW — must stay LAST (position 13)

            foreach (var ln in lines)
            {
                dt.Rows.Add(
                    ln.BranchCode,
                    ln.InvoiceNo,
                    ln.InvoiceDate,
                    ln.SequenceNumber,          // note: string
                    ln.BatchReferenceID,
                    ln.ActualCost,
                    ln.AmountPaid,
                    ln.EWTAmount,
                    ln.DiscountAmount,
                    ln.ReturnAllowances,
                    ln.Description,
                    ln.Variance,                 // NEW - appended last
                    string.IsNullOrWhiteSpace(ln.DiscountAccountCode) ? (object)DBNull.Value : ln.DiscountAccountCode   // NEW
                );
              

            }
            return dt;
        }
        private static bool ToBool(object value)
        {
            if (value == null || value == DBNull.Value) return false;

            if (value is bool b) return b;

            var s = value.ToString().Trim();

            if (string.Equals(s, "true", StringComparison.OrdinalIgnoreCase)) return true;
            if (string.Equals(s, "false", StringComparison.OrdinalIgnoreCase)) return false;

            // common alternatives
            if (s == "1" || s.Equals("y", StringComparison.OrdinalIgnoreCase) || s.Equals("yes", StringComparison.OrdinalIgnoreCase))
                return true;

            if (s == "0" || s.Equals("n", StringComparison.OrdinalIgnoreCase) || s.Equals("no", StringComparison.OrdinalIgnoreCase))
                return false;

            // your case: "NONE" should mean unchecked
            if (s.Equals("none", StringComparison.OrdinalIgnoreCase) || s == "") return false;

            // last resort: try parse
            if (bool.TryParse(s, out var parsed)) return parsed;

            return false;
        }

        private void UpdateTotalAmountToPay()
        {
            decimal total = 0;

            // Invoices grid — same as before
            for (int i = 0; i < gridViewMaster.RowCount; i++)
            {
                if (ToBool(gridViewMaster.GetRowCellValue(i, "Pay")))
                {
                    total += ToDecimal(gridViewMaster.GetRowCellValue(i, "AmountPaid"));
                }
            }

            // Debit entries grid — NEW
            for (int i = 0; i < gridViewLines.RowCount; i++)
            {
                string acct = gridViewLines.GetRowCellValue(i, "AccountCode")?.ToString();
                decimal amount = ToDecimal(gridViewLines.GetRowCellValue(i, "Amount"));
                if (!string.IsNullOrWhiteSpace(acct) && amount > 0)
                    total += amount;
            }

            txtamounttopay.Text = total.ToString("N2");
        }
        private void ResetRowPayment(int rowHandle)
        {
            // Turn off amounts when Pay is unchecked
            _isRecalculating = true;
            try
            {
                gridViewMaster.SetRowCellValue(rowHandle, "AmountPaid", 0m);
                gridViewMaster.SetRowCellValue(rowHandle, "DiscountAmount", 0m);
                gridViewMaster.SetRowCellValue(rowHandle, "EWTAmount", 0m);
                gridViewMaster.SetRowCellValue(rowHandle, "ReturnAllowances", 0m);
                gridViewMaster.SetRowCellValue(rowHandle, "Variance", 0m);   // NEW
            }
            finally
            {
                _isRecalculating = false;
            }
        }

        private void InitializeRowPayment(int rowHandle)
        {
            decimal balance = ToDecimal(gridViewMaster.GetRowCellValue(rowHandle, "Balance"));

            _isRecalculating = true;
            try
            {
                gridViewMaster.SetRowCellValue(rowHandle, "EWTAmount", 0m);
                gridViewMaster.SetRowCellValue(rowHandle, "DiscountAmount", 0m);
                gridViewMaster.SetRowCellValue(rowHandle, "ReturnAllowances", 0m);
                gridViewMaster.SetRowCellValue(rowHandle, "Variance", 0m);   // NEW

                // AmountPaid starts as full balance (no variance assumed until
                // the user actually types a different actual-cash figure)
                gridViewMaster.SetRowCellValue(rowHandle, "AmountPaid", balance);
            }
            finally
            {
                _isRecalculating = false;
            }
        }
        private void RecalculateRowAmount(int rowHandle)
        {
            decimal balance = ToDecimal(gridViewMaster.GetRowCellValue(rowHandle, "Balance"));
            decimal ewt = ToDecimal(gridViewMaster.GetRowCellValue(rowHandle, "EWTAmount"));
            decimal discount = ToDecimal(gridViewMaster.GetRowCellValue(rowHandle, "DiscountAmount"));
            decimal offset = ToDecimal(gridViewMaster.GetRowCellValue(rowHandle, "ReturnAllowances"));
            //decimal variance = ToDecimal(gridViewMaster.GetRowCellValue(rowHandle, "Variance"));   // NEW

            decimal totalDeduction = ewt + discount + offset;

            if (totalDeduction > balance)
            {
                ShowRowError(rowHandle, "Total deductions exceed Balance");
                return;
            }

            // Variance adjusts the expected cash outlay - positive means MORE
            // cash goes out (FX Loss), negative means LESS (FX Gain)
            decimal newAmount = balance - totalDeduction;// + variance;

            if (newAmount < 0)
                newAmount = 0;

            _isRecalculating = true;
            try
            {
                gridViewMaster.SetRowCellValue(rowHandle, "AmountPaid", newAmount);
            }
            finally
            {
                _isRecalculating = false;
            }

            gridViewMaster.ClearColumnErrors();
        }


        private void gridViewMaster_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            if (_isRecalculating) return;   // NEW - suppress nested/cascading recalculation

            string col = e.Column.FieldName;

            if (col == "Pay")
            {
                bool isChecked = Convert.ToBoolean(e.Value);

                if (isChecked)
                    InitializeRowPayment(e.RowHandle);
                else
                    ResetRowPayment(e.RowHandle);

                UpdateTotalAmountToPay();
                return;
            }

            if (!ToBool(gridViewMaster.GetRowCellValue(e.RowHandle, "Pay")))
                return; // do nothing if row isn't checked for payment

            if (col == "EWTAmount" || col == "DiscountAmount" || col == "ReturnAllowances" )//|| col == "Variance")
            {
                RecalculateRowAmount(e.RowHandle);
                UpdateTotalAmountToPay();
            }
            else if (col == "AmountPaid")
            {
                //RecalculateRowVariance(e.RowHandle);   // NEW - back-solve Variance
                UpdateTotalAmountToPay();
            }

        }

        private decimal ToDecimal(object value)
        {
            if (value == null || value == DBNull.Value)
                return 0m;

            decimal.TryParse(value.ToString(), out decimal result);
            return result;
        }

        private void gridViewMaster_CustomRowCellEdit(object sender, DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "Pay")
                e.RepositoryItem = repositoryItemCheckEditStat;
            if (e.Column.FieldName == "DiscountAccountCode")   // NEW
                e.RepositoryItem = repDiscountAccount;
        }

        private void gridViewMaster_RowCellStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowCellStyleEventArgs e)
        {

            bool isChecked = ToBool(gridViewMaster.GetRowCellValue(e.RowHandle, "Pay"));

            if (isChecked)
            {
                e.Appearance.BackColor = Color.LightGreen;
            }

        }
        private void ShowRowError(int rowHandle, string message)
        {
            gridViewMaster.SetColumnError(
                gridViewMaster.Columns["AmountPaid"],
                message);

            gridViewMaster.FocusedRowHandle = rowHandle;
        }
        
        //USED TO EDIT CELL 
        private void gridViewMaster_ShowingEditor(object sender, CancelEventArgs e)
        {
            var editor = gridViewMaster.ActiveEditor;
            if (editor is DevExpress.XtraEditors.TextEdit textEdit)
            {
                textEdit.SelectAll();
            }
        }

        private void btnextract_Click(object sender, EventArgs e)
        {
            populate();
        }

        void printVoucher()
        {
            btnfilter.PerformClick();
            try
            {
                var row = Database.getMultipleQuery("ReportHeaderSettings", "ReportName='CheckVoucher'", "Heading,ImageWidth,ImageHeight,Caption1,Caption2");

                string companyname = row["Heading"].ToString();
                string imagewidth = row["ImageWidth"].ToString();
                string imageheight = row["ImageHeight"].ToString();
                string caption1 = row["Caption1"].ToString();
                string caption2 = row["Caption2"].ToString();

                DevExReportTemplate.CheckVoucher xct = new DevExReportTemplate.CheckVoucher();
                xct.Landscape = false;

                Classes.Utilities.GetImageDevEx(xct.xrPictureBox1, "ReportHeaderSettings", "ReportName='CheckVoucher'", "ImageLogo");
                xct.xrPictureBox1.SizeF = new SizeF(float.Parse(imagewidth), float.Parse(imageheight));
                xct.xrPictureBox1.ImageAlignment = DevExpress.XtraPrinting.ImageAlignment.MiddleCenter;
                xct.xrcompanyname.Text = companyname;
                xct.xrcaption1.Text = caption1;
                xct.xrcaption2.Text = caption2;
                xct.xrcheckno.Text = txtcheckno.Text;

                xct.PaperKind = (DevExpress.Drawing.Printing.DXPaperKind)System.Drawing.Printing.PaperKind.A4; 
                double amounttopay = Convert.ToDouble(txtamounttopay.Text);

                string paytype = "";
                if (radioButtonPurchase.Checked == true) { paytype = "PURCHASE"; } else { paytype = "EXPENSE"; }

                xct.xrcheckdate.Text = txtcheckdate.Text;
                xct.xrpaytype.Text = paytype;
                xct.xrpaidto.Text = searchLookUpSupplier.Text;//txtsuppliername.Text;
                xct.xrparticular.Text = txtremakrs.Text;
                xct.xramount.Text = String.Format("{0:0,0.00}", amounttopay);
              
                string str = Classes.DecimalToWordExtension.ToWords(Convert.ToDecimal(txtamounttopay.Text));

                gridViewMaster.Columns["Balance"].Visible = false;
                gridViewMaster.Columns["BranchCode"].Visible = false;
               
                if (paytype == "EXPENSE")
                {
                    gridViewMaster.Columns["BatchReferenceID"].Visible = false;
                    gridViewMaster.Columns["BatchReferenceID"].OptionsColumn.ShowInCustomizationForm = true;
                }

                gridViewMaster.Columns["Type"].Visible = false;
            
                gridViewMaster.Columns["Balance"].OptionsColumn.ShowInCustomizationForm = true;
                gridViewMaster.Columns["BranchCode"].OptionsColumn.ShowInCustomizationForm = true;
                gridViewMaster.Columns["Type"].OptionsColumn.ShowInCustomizationForm = true;
                gridViewMaster.Columns["Pay"].Visible = false;

                xct.xramountinwords.Text = str.ToString().ToUpper();
                xct.xrpreparedby.Text = Login.Fullname;
                xct.xrLabel3.Text = Database.getSingleQuery("Approvers", "UserID<>''", "UserID");
                xct.Bands[BandKind.Detail].Controls.Add(HelperFunction.CopyGridControl(gridControlMaster, gridViewMaster, "Pay"));
                xct.Bands[BandKind.Detail].Font = new System.Drawing.Font("Tahoma", 10);
                ReportPrintTool report = new ReportPrintTool(xct);
                report.ShowRibbonPreviewDialog();

            }
            catch (FormatException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }

        void printCashVoucher()
        {
            btnfilter.PerformClick();
            try
            {
                var row = Database.getMultipleQuery("ReportHeaderSettings", "ReportName='CheckVoucher'", "Heading,ImageWidth,ImageHeight,Caption1,Caption2");

                string companyname = row["Heading"].ToString();
                string imagewidth = row["ImageWidth"].ToString();
                string imageheight = row["ImageHeight"].ToString();
                string caption1 = row["Caption1"].ToString();
                string caption2 = row["Caption2"].ToString();

                DevExReportTemplate.Cash5Voucher xct = new DevExReportTemplate.Cash5Voucher();
                xct.Landscape = false;

                Classes.Utilities.GetImageDevEx(xct.xrPictureBox1, "ReportHeaderSettings", "ReportName='CheckVoucher'", "ImageLogo");
                xct.xrPictureBox1.SizeF = new SizeF(float.Parse(imagewidth), float.Parse(imageheight));
                xct.xrPictureBox1.ImageAlignment = DevExpress.XtraPrinting.ImageAlignment.MiddleCenter;
                xct.xrcompanyname.Text = companyname;
                xct.xrcaption1.Text = caption1;
                xct.xrcaption2.Text = caption2;

                xct.PaperKind = (DevExpress.Drawing.Printing.DXPaperKind)System.Drawing.Printing.PaperKind.A4; 
                double amounttopay = Convert.ToDouble(txtamounttopay.Text);


                xct.xrcheckdate.Text = txtcheckdate.Text;
                xct.xrpaidto.Text = searchLookUpSupplier.Text;//txtsuppliername.Text;
                xct.xrparticular.Text = txtremakrs.Text;
                xct.xramount.Text = String.Format("{0:0,0.00}", amounttopay);
                
                string str = Classes.DecimalToWordExtension.ToWords(Convert.ToDecimal(txtamounttopay.Text));

                gridViewMaster.Columns["Balance"].Visible = false;
                gridViewMaster.Columns["BranchCode"].Visible = false;
                gridViewMaster.Columns["Pay"].Visible = false;
                gridViewMaster.Columns["Variance"].Visible = false;

                xct.xramountinwords.Text = str.ToString().ToUpper(); 
                xct.xrpreparedby.Text = Login.Fullname;
                xct.xrLabel3.Text = Database.getSingleQuery("Approvers", "UserID<>''", "UserID");
                xct.Bands[BandKind.Detail].Controls.Add(HelperFunction.CopyGridControl(gridControlMaster, gridViewMaster, "Pay"));
                xct.Bands[BandKind.Detail].Font = new System.Drawing.Font("Tahoma", 10);
                ReportPrintTool report = new ReportPrintTool(xct);
                report.ShowRibbonPreviewDialog();

            }
            catch (FormatException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }

        private void btnprint_Click(object sender, EventArgs e)
        {
            ClearUncheckedPayRows();
            if (radCashVoucher.Checked == true)
            {
                printCashVoucher();
            }
            else if (radCheckVoucher.Checked == true)
            {
                if (String.IsNullOrEmpty(txtcheckno.Text) || String.IsNullOrEmpty(txtcheckdate.Text))
                {
                    XtraMessageBox.Show("Please Filled-out the CheckNo/CheckDate Field");
                }
                else
                {
                    printVoucher();
                }
            }

        }
      
        private void radCashVoucher_CheckedChanged(object sender, EventArgs e)
        {
            radChanged();
        }

        private void radCheckVoucher_CheckedChanged(object sender, EventArgs e)
        {
            radChanged();
        }

        private void removeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            string refno = gridViewMaster.GetRowCellValue(gridViewMaster.FocusedRowHandle, "ReferenceNo").ToString();
            string invoiceno = gridViewMaster.GetRowCellValue(gridViewMaster.FocusedRowHandle, "InvoiceNo").ToString();
            if (radioButtonExpense.Checked == true && gridViewMaster.RowCount > 0)
            {
                bool checkifNotYetProcessed = Database.checkifExist("SELECT TOP(1) InvoiceNo " +
                "FROM dbo.ExpenseSummary " +
                "WHERE InvoiceNo='" + invoiceno + "' " +
                "AND SupplierID='" + txtsupplierid.Text + "' " +
                "AND ReferenceNumber='" + refno + "' " +
                "AND Status='APPROVED' ");

                if (checkifNotYetProcessed)
                {
                    bool confirm = HelperFunction.ConfirmDialog("Are you sure you want to Execute as ErrorCorrect this Transaction? ", "Confirm Error Correct");
                    if (confirm)
                    {
                    }
                    else
                    {
                        return;
                    }
                    //btnextract.PerformClick();
                }
                else
                {
                    XtraMessageBox.Show("You cannot Cancel this Invoice, because it is already processed...");
                    return;
                }
            }
        }

        private void gridControlMaster_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                //contextMenuStrip1.Show(gridControlMaster, e.Location);
                contextMenuShowInvoices.Show(gridControlMaster, e.Location);
        }

        void ClearUncheckedPayRows()
        {
            for (int i = gridViewMaster.RowCount - 1; i >= 0; i--)
            {
                var val = gridViewMaster.GetRowCellValue(i, "Pay")?.ToString();

                if (string.IsNullOrEmpty(val) || val == "NONE")
                {
                    gridViewMaster.DeleteRow(i);
                }
            }
        }

      
        private void gridViewMaster_KeyDown(object sender, KeyEventArgs e)
        {

            if (e.KeyCode == Keys.Enter)
            {
                if (gridViewMaster.FocusedColumn.FieldName == "ReturnAllowances")
                {
                    int nextRow = gridViewMaster.FocusedRowHandle + 1;

                    if (nextRow < gridViewMaster.RowCount)
                    {
                        gridViewMaster.FocusedRowHandle = nextRow;
                        gridViewMaster.FocusedColumn = gridViewMaster.Columns["Pay"];
                    }

                    e.Handled = true;
                }
            }

        }

        private void labelControl6_Click(object sender, EventArgs e)
        {

        }

        private void showInvoiceDetailsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if(radioButtonExpense.Checked==true)
            {
                HOFormsDevEx.ViewExpenseDetailsDevEx viewdetdevex = new HOFormsDevEx.ViewExpenseDetailsDevEx();
                viewdetdevex.groupControl1.Visible = false;
                Database.display($"SELECT * FROM dbo.view_ExpenseMasterDetails with(nolock) " +
                 $"WHERE BatchReferenceID ='{Convert.ToInt64(gridViewMaster.GetRowCellValue(gridViewMaster.FocusedRowHandle, "BatchReferenceID") ?? 0)}' " +
                 $"AND InvoiceNo='{Convert.ToString(gridViewMaster.GetRowCellValue(gridViewMaster.FocusedRowHandle, "InvoiceNo") ?? "")}' ", viewdetdevex.gridControl2, viewdetdevex.gridView2);
                viewdetdevex.ShowDialog(this);
            }
        }

        private void radtelegraphic_CheckedChanged(object sender, EventArgs e)
        {
            radChanged();
        }

        private void btnAddLine_Click(object sender, EventArgs e)
        {
            AddLine();
            UpdateTotalAmountToPay();
        }

        private void btnRemoveLine_Click(object sender, EventArgs e)
        {
            gridViewLines.DeleteSelectedRows();
            UpdateTotal();
            UpdateTotalAmountToPay();
        }
         
       
         

        private void searchLookUpSupplier_EditValueChanged(object sender, EventArgs e)
        {
            _suppid = SearchLookUpClass.getSingleValue(searchLookUpSupplier, "SupplierID");
            txtsupplierid.Text = _suppid.ToString();
            populate();
        }

        private void gridViewLines_CustomRowCellEdit(object sender, CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "BranchCode") e.RepositoryItem = repBranchLine;   // NEW
            if (e.Column.FieldName == "AccountCode") e.RepositoryItem = repDebitAccount;
            if (e.Column.FieldName == "PayeeName") e.RepositoryItem = repPayeeName;
            if (e.Column.FieldName == "Amount") e.RepositoryItem = repAmount;
            if (e.Column.FieldName == "Particulars") e.RepositoryItem = repParticulars;
        }

        private void gridViewLines_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            UpdateTotal();
            UpdateTotalAmountToPay(); 
        }

        private void gridViewLines_RowCellStyle(object sender, RowCellStyleEventArgs e)
        {
            string acct = gridViewLines.GetRowCellValue(e.RowHandle, "AccountCode")?.ToString();
            string branch = gridViewLines.GetRowCellValue(e.RowHandle, "BranchCode")?.ToString();   // NEW
            decimal amount = ToDecimal(gridViewLines.GetRowCellValue(e.RowHandle, "Amount"));

            if (string.IsNullOrWhiteSpace(acct) || string.IsNullOrWhiteSpace(branch) || amount <= 0)
                e.Appearance.BackColor = System.Drawing.Color.LightCoral;
        }

        private void radioButtonPurchase_CheckedChanged(object sender, EventArgs e)
        {
            populate();
        }

        private void radioButtonExpense_CheckedChanged(object sender, EventArgs e)
        {
            populate();
        }

        private void gridViewMaster_CustomColumnDisplayText(object sender, DevExpress.XtraGrid.Views.Base.CustomColumnDisplayTextEventArgs e)
        {
            if (e.Column.FieldName == "AmountPaid" && e.Value != null)
            {
                e.DisplayText = string.Format("{0:n2}", e.Value);
            }
            if (e.Column.FieldName == "EWTAmount" && e.Value != null)
            {
                e.DisplayText = string.Format("{0:n2}", e.Value);
            }
            if (e.Column.FieldName == "DiscountAmount" && e.Value != null)
            {
                e.DisplayText = string.Format("{0:n2}", e.Value);
            }
        }

        private void btnfilter_Click(object sender, EventArgs e)
        {
            ClearUncheckedPayRows();
        }
    }
}
