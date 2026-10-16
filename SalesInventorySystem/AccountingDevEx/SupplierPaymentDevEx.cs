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
            public string DiscountAccountCode { get; set; }   // NEW — null/blank = use default '508'
            public string Description { get; set; }

            // 2026-09-24 - PURCHASE-only overpayment/advance columns, sent via
            // dbo.AP_PaymentLineExtraTVP (see SQL/2026-09-24_SupplierPayment_OverpaymentCredit.sql)
            public decimal OverPay { get; set; }          // excess cash -> supplier advance credit (101030208)
            public decimal OverPayExpense { get; set; }   // excess cash -> written off (60339), not carried forward
            public decimal AdvanceApplied { get; set; }   // prior OverPay credit consumed instead of cash
            public string Type { get; set; }              // [97] PURCHASE / EXPENSE (splist_Accounts' Type)
        }

        // Grid-only columns added client-side in populate() for PURCHASE mode
        // (splist_Accounts doesn't return them - it's shared with Expense mode).
        private const string ColOverPay = "OverPay";
        private const string ColOverPayExpense = "OverPayExpense";
        private const string ColAdvanceApplied = "AdvanceApplied";
        private decimal _availableCredit = 0m;
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
            return GetNextCheckNo(searchLookUpEdit1.EditValue.ToString());
        }

        // The next cheque number of a bank account: the last voucher's cheque + 1, as before.
        // 2026-10-12: a cancelled cheque recorded with "Cancelled Cheque…" (PaidTo 'CANCELLED', amount 0,
        // voided) never counts as the last voucher, since one recorded out of sequence (an older number)
        // must not pull the suggestion back; and any number already used on that bank is skipped (on the
        // production copy BDO PESO 2 and PNB PESO 2 were suggesting cheque numbers already issued).
        private string GetNextCheckNo(string bankGLCode)
        {
            string sql = @"
        SELECT TOP(1) CheckNo
        FROM dbo.CheckVoucher
       WHERE OfficialReceiptNo=@bankglcode
         AND NOT (PaidTo = 'CANCELLED' AND ISNULL(Amount, 0) = 0 AND ISNULL(isErrorCorrect, 0) = 1)
        ORDER BY VoucherID DESC, SequenceNumber DESC;

        SELECT DISTINCT LTRIM(RTRIM(CheckNo)) AS CheckNo
        FROM dbo.CheckVoucher
       WHERE (OfficialReceiptNo=@bankglcode OR CreditGLCode=@bankglcode)
         AND ISNULL(CheckNo, '') <> '';";

            string lastCheckNo = null;
            var used = new HashSet<string>(StringComparer.OrdinalIgnoreCase);   // every number already used on the bank

            using (SqlConnection conn = Database.getConnection())
            using (SqlCommand cmd = new SqlCommand(sql, conn))
            {
                cmd.Parameters.Add("@bankglcode", SqlDbType.VarChar, 100).Value = bankGLCode;

                conn.Open();

                using (var rdr = cmd.ExecuteReader())
                {
                    if (rdr.Read() && rdr[0] != DBNull.Value)
                        lastCheckNo = rdr[0].ToString();
                    if (rdr.NextResult())
                        while (rdr.Read())
                            if (rdr[0] != DBNull.Value) used.Add(rdr[0].ToString());
                }
            }

            string next = IncrementCheckNo(lastCheckNo);
            for (int guard = 0; guard < 10000 && used.Contains(next); guard++)
                next = IncrementCheckNo(next);
            return next;
        }

        private static string IncrementCheckNo(string lastCheckNo)
        {
            // If there is no previous check number, start from a sensible default
            if (string.IsNullOrEmpty(lastCheckNo))
                return "100000000";

            // Try to parse the last check number as a long, increment and return.
            // If parsing fails (non-numeric content), attempt to extract the first
            // numeric sequence and increment that. If everything fails, return the
            // original value unchanged.
            if (long.TryParse(lastCheckNo, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out long n))
            {
                return (n + 1).ToString();
            }

            try
            {
                // fallback: extract consecutive digits from the string
                var m = System.Text.RegularExpressions.Regex.Match(lastCheckNo, "\\d+");
                if (m.Success && long.TryParse(m.Value, out long extracted))
                {
                    return (extracted + 1).ToString();
                }
            }
            catch
            {
                // ignore and fall through
            }

            // couldn't increment — return the raw value as a last resort
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
                    // [97] DBNull-safe (a legacy expense row can carry a NULL BatchReferenceID)
                    SequenceNumber = (long)SafeToDecimal(gridViewMaster.GetRowCellValue(i, "SequenceNumber")),
                    BatchReferenceID = (long)SafeToDecimal(gridViewMaster.GetRowCellValue(i, "BatchReferenceID")),
                    BranchCode = "",//Convert.ToString(gridViewMaster.GetRowCellValue(i, "BranchCode") ?? ""),
                    InvoiceNo = Convert.ToString(gridViewMaster.GetRowCellValue(i, "InvoiceNo") ?? ""),
                    //SequenceReferenceNumber = Convert.ToString(gridViewMaster.GetRowCellValue(i, "SequenceReferenceNumber") ?? ""),
                    InvoiceDate = Convert.ToDateTime(gridViewMaster.GetRowCellValue(i, "InvoiceDate") ?? DateTime.MinValue),
                    ActualCost = SafeToDecimal(gridViewMaster.GetRowCellValue(i, "ActualCost")), //NET
                    AmountPaid = SafeToDecimal(gridViewMaster.GetRowCellValue(i, "AmountPaid")), //NET
                    Balance = SafeToDecimal(gridViewMaster.GetRowCellValue(i, "Balance")),
                    DiscountAmount = SafeToDecimal(gridViewMaster.GetRowCellValue(i, "DiscountAmount")),
                    EWTAmount = SafeToDecimal(gridViewMaster.GetRowCellValue(i, "EWTAmount")),
                    ReturnAllowances = SafeToDecimal(gridViewMaster.GetRowCellValue(i, "ReturnAllowances")),
                    Variance = SafeToDecimal(gridViewMaster.GetRowCellValue(i, "Variance")),   // NEW
                    DiscountAccountCode = Convert.ToString(gridViewMaster.GetRowCellValue(i, "DiscountAccountCode") ?? ""),
                    Description = Convert.ToString(gridViewMaster.GetRowCellValue(i, "Description") ?? ""),
                    OverPay = ToDecimal(gridViewMaster.GetRowCellValue(i, ColOverPay)),
                    OverPayExpense = ToDecimal(gridViewMaster.GetRowCellValue(i, ColOverPayExpense)),
                    AdvanceApplied = ToDecimal(gridViewMaster.GetRowCellValue(i, ColAdvanceApplied)),
                    Type = RowType(i)   // [97]
                });
            }

            return lines;
        }
        // Single source of truth for "Gross" (Amount Paid + EWT + Discount +
        // Offset - Variance), so the in-grid warning and the pre-submit gate
        // can't drift apart. Variance is always 0 today (splist_Accounts
        // hardcodes it; InitializeRowPayment/ResetRowPayment force the cell
        // back to 0m), but the commented-out RecalculateRowVariance
        // scaffolding elsewhere in this file shows it's meant to go live --
        // this keeps every caller consistent when it does.
        // 2026-09-24: + AdvanceApplied - OverPay - OverPayExpense, matching
        // sp_AddPaymentSupplierCompound_V2's PURCHASE @pGross exactly (all
        // three are 0 in Expense mode, where the columns don't exist).
        private static decimal ComputeGross(decimal amountPaid, decimal ewt, decimal discount, decimal offset, decimal variance,
                                            decimal overPay = 0m, decimal overPayExpense = 0m, decimal advanceApplied = 0m)
            => amountPaid + ewt + discount + offset + advanceApplied - variance - overPay - overPayExpense;

        // Reads the row's settlement figures once, so every caller computes
        // Gross from the same columns.
        private decimal ComputeRowGross(int rowHandle)
            => ComputeGross(
                ToDecimal(gridViewMaster.GetRowCellValue(rowHandle, "AmountPaid")),
                ToDecimal(gridViewMaster.GetRowCellValue(rowHandle, "EWTAmount")),
                ToDecimal(gridViewMaster.GetRowCellValue(rowHandle, "DiscountAmount")),
                ToDecimal(gridViewMaster.GetRowCellValue(rowHandle, "ReturnAllowances")),
                ToDecimal(gridViewMaster.GetRowCellValue(rowHandle, "Variance")),
                ToDecimal(gridViewMaster.GetRowCellValue(rowHandle, ColOverPay)),
                ToDecimal(gridViewMaster.GetRowCellValue(rowHandle, ColOverPayExpense)),
                ToDecimal(gridViewMaster.GetRowCellValue(rowHandle, ColAdvanceApplied)));

        // No-op when the column isn't in the current grid (Expense mode).
        private void SetCellIfExists(int rowHandle, string fieldName, object value)
        {
            if (gridViewMaster.Columns[fieldName] != null)
                gridViewMaster.SetRowCellValue(rowHandle, fieldName, value);
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
            BuildCancelledChequeButton();

            // [97] 2026-10-15 (user): purchases and expenses in one list, one voucher may pay both (cash / check).
            // The Purchase / Expense radio buttons are hidden (kept in the designer); the list shows each row's Type.
            radioButtonPurchase.Visible = false;
            radioButtonExpense.Visible = false;
        }

        // [97] the kind of a grid row (splist_Accounts' Type column): "PURCHASE", "EXPENSE", or "" when unknown
        // (a posting refuses unknown rows rather than guessing their kind)
        private string RowType(int rowHandle)
        {
            if (rowHandle < 0 || gridViewMaster.Columns["Type"] == null) return "";
            string t = Convert.ToString(gridViewMaster.GetRowCellValue(rowHandle, "Type"))?.Trim().ToUpperInvariant() ?? "";
            return t == "PURCHASE" || t == "EXPENSE" ? t : "";
        }

        // [97] footer totals of the ticked rows only (see populate)
        private static readonly string[] TickedSumColumns = { "AmountPaid", "DiscountAmount", "EWTAmount", "ReturnAllowances" };
        private bool _tickedSummaryWired;
        private decimal _tickedSum;

        private void GridViewMaster_CustomSummaryCalculate(object sender, DevExpress.Data.CustomSummaryEventArgs e)
        {
            var item = e.Item as DevExpress.XtraGrid.GridSummaryItem;
            if (item == null || Array.IndexOf(TickedSumColumns, item.FieldName) < 0) return;
            switch (e.SummaryProcess)
            {
                case DevExpress.Data.CustomSummaryProcess.Start:
                    _tickedSum = 0m;
                    break;
                case DevExpress.Data.CustomSummaryProcess.Calculate:
                    if (ToBool(gridViewMaster.GetRowCellValue(e.RowHandle, "Pay")))
                        _tickedSum += ToDecimal(e.FieldValue);
                    break;
                case DevExpress.Data.CustomSummaryProcess.Finalize:
                    e.TotalValue = _tickedSum;
                    break;
            }
        }

        // [97] the kinds among the ticked rows: "PURCHASE", "EXPENSE", "PURCHASE / EXPENSE" or "" (none ticked)
        private string TickedKinds()
        {
            bool p = false, e = false;
            for (int i = 0; i < gridViewMaster.RowCount; i++)
            {
                if (!ToBool(gridViewMaster.GetRowCellValue(i, "Pay"))) continue;
                string t = RowType(i);
                if (t == "PURCHASE") p = true; else if (t == "EXPENSE") e = true;
            }
            return p && e ? "PURCHASE / EXPENSE" : p ? "PURCHASE" : e ? "EXPENSE" : "";
        }

        // ── 2026-10-12: RECORD A CANCELLED (SPOILED) CHEQUE ─────────────────────
        // Spoiled / misprinted / lost cheques used to be "paid" to a fake supplier CANCELLED. Now:
        // one button in the Check Voucher panel -> dbo.sp_RecordCancelledCheque, which uses up the
        // cheque no., a CV no., a voucher no. and a reference no., and makes no GL entry, no bank
        // recon item and no AP / ledger row. A cheque already posted to pay a supplier is not this:
        // it is reversed (Supplier Voucher Reversal).
        private SimpleButton btnRecordCancelledCheque;

        private void BuildCancelledChequeButton()
        {
            txtlastchecknum.Width = 130;   // room for the button in the Check Voucher panel (409 px wide)
            btnRecordCancelledCheque = new SimpleButton
            {
                Text = "Cancelled Cheque…",
                Location = new Point(294, 2),
                Size = new Size(108, 24),
                ToolTip = "Record a spoiled / misprinted / lost cheque: uses up its cheque no. and a CV no. No payment, no GL entry."
            };
            btnRecordCancelledCheque.Click += BtnRecordCancelledCheque_Click;
            panelCheckVoucher.Controls.Add(btnRecordCancelledCheque);
            btnRecordCancelledCheque.BringToFront();
        }

        // 2026-10-12 (user: fix typos after recording): the button opens the list of cancelled cheques recorded
        // so far (sp_GetCancelledCheques), with New… / Edit…; Edit corrects one through sp_EditCancelledCheque
        // (SQL/2026-10-12c), which also logs the old and new values in CancelledChequeEditLog.
        private void BtnRecordCancelledCheque_Click(object sender, EventArgs e)
        {
            DataTable banks;
            try
            {
                banks = GetDataTable(@"SELECT c.AccountCode, c.AccountCode + ' - ' + c.Description AS DisplayText
                                       FROM dbo.ChartOfAccounts c
                                       WHERE EXISTS (SELECT 1 FROM dbo.BankCoa b WHERE b.AccountCode = c.AccountCode)
                                       ORDER BY c.AccountCode");
            }
            catch (SqlException ex) { XtraMessageBox.Show(ex.Message, "Cancelled Cheque", MessageBoxButtons.OK, MessageBoxIcon.Error); return; }

            bool changed = false;
            using (var dlg = new XtraForm
            {
                Text = "Cancelled Cheques",
                StartPosition = FormStartPosition.CenterParent,
                MinimizeBox = false,
                ShowInTaskbar = false,
                ClientSize = new Size(980, 480),
                MinimumSize = new Size(700, 360)
            })
            {
                var top = new PanelControl { Dock = DockStyle.Top, Height = 44 };
                var lblFrom = new LabelControl { Text = "Cheque date from", Location = new Point(10, 14) };
                var dtFrom = new DateEdit { Location = new Point(115, 10), Width = 110 };
                var lblTo = new LabelControl { Text = "to", Location = new Point(234, 14) };
                var dtTo = new DateEdit { Location = new Point(252, 10), Width = 110 };
                var today = DateTime.Today;
                dtFrom.EditValue = new DateTime(today.Year, today.Month, 1).AddMonths(-2);
                dtTo.EditValue = today;
                var btnShow = new SimpleButton { Text = "Show", Location = new Point(372, 8), Size = new Size(70, 26) };
                top.Controls.AddRange(new Control[] { lblFrom, dtFrom, lblTo, dtTo, btnShow });

                var bottom = new PanelControl { Dock = DockStyle.Bottom, Height = 44 };
                var btnNew = new SimpleButton { Text = "New…", Location = new Point(10, 8), Size = new Size(90, 28) };
                var btnEdit = new SimpleButton { Text = "Edit…", Location = new Point(106, 8), Size = new Size(90, 28) };
                var btnClose = new SimpleButton { Text = "Close", Size = new Size(90, 28), DialogResult = DialogResult.Cancel,
                                                  Anchor = AnchorStyles.Top | AnchorStyles.Right };
                btnClose.Location = new Point(bottom.Width - 100, 8);
                bottom.Controls.AddRange(new Control[] { btnNew, btnEdit, btnClose });

                var grid = new DevExpress.XtraGrid.GridControl { Dock = DockStyle.Fill };
                var view = new GridView(grid);
                grid.MainView = view;
                view.OptionsBehavior.Editable = false;
                view.OptionsView.ShowGroupPanel = false;
                view.OptionsSelection.EnableAppearanceFocusedCell = false;

                Action load = () =>
                {
                    try
                    {
                        var dt = new DataTable();
                        using (var con = Database.getConnection())
                        using (var cmd = new SqlCommand("dbo.sp_GetCancelledCheques", con) { CommandType = CommandType.StoredProcedure })
                        {
                            cmd.Parameters.Add("@DateFrom", SqlDbType.Date).Value = dtFrom.EditValue is DateTime f ? (object)f.Date : DBNull.Value;
                            cmd.Parameters.Add("@DateTo", SqlDbType.Date).Value = dtTo.EditValue is DateTime t ? (object)t.Date : DBNull.Value;
                            con.Open();
                            new SqlDataAdapter(cmd).Fill(dt);
                        }
                        grid.DataSource = dt;
                        view.PopulateColumns();
                        foreach (string hide in new[] { "VoucherID", "ReferenceNumber", "BankGLCode" })
                            if (view.Columns[hide] != null) view.Columns[hide].Visible = false;
                        var captions = new Dictionary<string, string>
                        {
                            { "CheckDate", "Cheque Date" }, { "BankName", "Bank" }, { "CheckNo", "Cheque No." }, { "CVNo", "CV No." },
                            { "RecordedBy", "Recorded By" }, { "RecordedAt", "Recorded" }, { "Edits", "Edits" }
                        };
                        foreach (var kv in captions)
                            if (view.Columns[kv.Key] != null) view.Columns[kv.Key].Caption = kv.Value;
                        if (view.Columns["CheckDate"] != null)
                        {
                            view.Columns["CheckDate"].DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                            view.Columns["CheckDate"].DisplayFormat.FormatString = "yyyy-MM-dd";
                        }
                        if (view.Columns["RecordedAt"] != null)
                        {
                            view.Columns["RecordedAt"].DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                            view.Columns["RecordedAt"].DisplayFormat.FormatString = "yyyy-MM-dd HH:mm";
                        }
                        view.BestFitColumns();
                        btnEdit.Enabled = dt.Rows.Count > 0;
                    }
                    catch (SqlException ex) { XtraMessageBox.Show(ex.Message, "Cancelled Cheques", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
                };
                Action edit = () =>
                {
                    var row = view.GetFocusedDataRow();
                    if (row == null) { XtraMessageBox.Show("Select a cancelled cheque first."); return; }
                    if (ShowCancelledChequeEntry(banks, row)) { changed = true; load(); }
                };

                btnShow.Click += (s, a) => load();
                btnNew.Click += (s, a) => { if (ShowCancelledChequeEntry(banks, null)) { changed = true; load(); } };
                btnEdit.Click += (s, a) => edit();
                view.DoubleClick += (s, a) =>
                {
                    var hit = view.CalcHitInfo(grid.PointToClient(Control.MousePosition));
                    if (hit.InRow) edit();
                };

                dlg.Controls.Add(grid);
                dlg.Controls.Add(top);
                dlg.Controls.Add(bottom);
                grid.BringToFront();
                dlg.CancelButton = btnClose;
                load();
                dlg.ShowDialog(this);
            }

            if (changed && CanGenerateVoucher())
                RefreshVoucher();   // the next cheque / CV no. on the main screen move past the ones used
        }

        // The entry window: new (existing == null) or a correction of a recorded cancelled cheque. True when saved.
        private bool ShowCancelledChequeEntry(DataTable banks, DataRow existing)
        {
            bool isEdit = existing != null;
            using (var dlg = new XtraForm
            {
                Text = isEdit ? "Edit Cancelled Cheque" : "Record Cancelled Cheque",
                FormBorderStyle = FormBorderStyle.FixedDialog,
                StartPosition = FormStartPosition.CenterParent,
                MaximizeBox = false,
                MinimizeBox = false,
                ShowInTaskbar = false,
                ClientSize = new Size(470, 362)
            })
            {
                var info = new LabelControl
                {
                    Text = isEdit
                        ? "Correct the details of this cancelled cheque (typos). It stays a cancelled cheque:\n" +
                          "no payment, no GL entry. The old and new values are kept in the edit log."
                        : "For a cheque that was spoiled, misprinted or lost and never paid anyone.\n" +
                          "It uses up the cheque no. and a CV no. No payment, no GL entry.\n" +
                          "A cheque already posted to pay a supplier is reversed instead (Supplier Voucher Reversal).",
                    Location = new Point(14, 10),
                    AutoSizeMode = LabelAutoSizeMode.Vertical,
                    Width = 442
                };
                var lblBank = new LabelControl { Text = "Bank account", Location = new Point(14, 76) };
                var cboBank = new LookUpEdit { Location = new Point(120, 72), Width = 336 };
                cboBank.Properties.DataSource = banks;
                cboBank.Properties.ValueMember = "AccountCode";
                cboBank.Properties.DisplayMember = "DisplayText";
                cboBank.Properties.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;   // Known Bug #2
                cboBank.Properties.ShowHeader = false;
                cboBank.Properties.Columns.Add(new DevExpress.XtraEditors.Controls.LookUpColumnInfo("DisplayText", "Bank account"));
                cboBank.Properties.NullText = "";

                var lblNo = new LabelControl { Text = "Cheque no.", Location = new Point(14, 108) };
                var txtNo = new TextEdit { Location = new Point(120, 104), Width = 160 };
                var lblDate = new LabelControl { Text = "Cheque date", Location = new Point(14, 140) };
                var dtDate = new DateEdit { Location = new Point(120, 136), Width = 160 };
                dtDate.EditValue = txtcheckdate.EditValue is DateTime cd ? cd : DateTime.Today;

                // 2026-10-12 (user): the CV no. the cheque uses up; filled with the next one of the series
                // (same rule as GenerateVoucherNumber), may be overwritten (SQL/2026-10-12b refuses one already used)
                var lblCV = new LabelControl { Text = "CV no.", Location = new Point(14, 172) };
                var txtCV = new TextEdit { Location = new Point(120, 168), Width = 220 };
                txtCV.Properties.MaxLength = 50;

                var lblReason = new LabelControl { Text = "Reason", Location = new Point(14, 204) };
                var cboReason = new ComboBoxEdit { Location = new Point(120, 200), Width = 160 };
                cboReason.Properties.Items.AddRange(new object[] { "SPOILED", "MISPRINTED", "DAMAGED", "LOST", "WRONG PAYEE", "OTHER" });
                cboReason.Properties.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;
                cboReason.SelectedIndex = 0;

                var lblRemarks = new LabelControl { Text = "Remarks", Location = new Point(14, 236) };
                var memo = new MemoEdit { Location = new Point(120, 232), Size = new Size(336, 70) };
                memo.Properties.MaxLength = 1000;

                var btnSave = new SimpleButton { Text = isEdit ? "Save" : "Record", Location = new Point(270, 320), Size = new Size(90, 28) };
                var btnClose = new SimpleButton { Text = "Close", Location = new Point(366, 320), Size = new Size(90, 28), DialogResult = DialogResult.Cancel };

                // new: the next cheque no. of the chosen bank, and the CV no., follow the inputs until the user types
                // their own; edit: they start as recorded and only change when the user changes them
                bool typed = isEdit, settingNo = false;
                txtNo.EditValueChanging += (s, a) => { if (!settingNo) typed = true; };
                cboBank.EditValueChanged += (s, a) =>
                {
                    if (typed || cboBank.EditValue == null) return;
                    try { settingNo = true; txtNo.Text = GetNextCheckNo(cboBank.EditValue.ToString()); }
                    catch (SqlException ex) { XtraMessageBox.Show(ex.Message, "Cancelled Cheque"); }
                    finally { settingNo = false; }
                };
                bool cvTyped = isEdit, settingCV = false;
                txtCV.EditValueChanging += (s, a) => { if (!settingCV) cvTyped = true; };
                Action fillCV = () =>
                {
                    if (cvTyped || cboBank.EditValue == null || !(dtDate.EditValue is DateTime d)) return;
                    try
                    {
                        settingCV = true;
                        int seq = GetNextSequenceForMonth(d.Year, d.Month);
                        txtCV.Text = $"CV{d:yy}{d:MM}-{seq:D3}{GetBank(cboBank.EditValue.ToString())}{txtNo.Text.Trim()}";
                    }
                    finally { settingCV = false; }
                };
                cboBank.EditValueChanged += (s, a) => fillCV();
                dtDate.EditValueChanged += (s, a) => fillCV();
                txtNo.EditValueChanged += (s, a) => fillCV();

                string oldNo = "";
                if (isEdit)
                {
                    cboBank.EditValue = Convert.ToString(existing["BankGLCode"]);
                    oldNo = Convert.ToString(existing["CheckNo"]).Trim();
                    txtNo.Text = oldNo;
                    dtDate.EditValue = existing["CheckDate"] is DateTime ed ? ed : (object)DateTime.Today;
                    txtCV.Text = Convert.ToString(existing["CVNo"]).Trim();
                    string r0 = Convert.ToString(existing["Reason"]).Trim();
                    if (r0.Length > 0 && !cboReason.Properties.Items.Contains(r0)) cboReason.Properties.Items.Add(r0);
                    cboReason.EditValue = r0.Length > 0 ? r0 : "SPOILED";
                    memo.Text = Convert.ToString(existing["Remarks"]);
                    // a corrected cheque no. carries into the CV no. when the CV no. ends with the old one (as the series does)
                    txtNo.EditValueChanged += (s, a) =>
                    {
                        string cv = txtCV.Text.Trim(), nw = txtNo.Text.Trim();
                        if (oldNo.Length > 0 && cv.EndsWith(oldNo, StringComparison.OrdinalIgnoreCase) && nw.Length > 0)
                        {
                            settingCV = true;
                            txtCV.Text = cv.Substring(0, cv.Length - oldNo.Length) + nw;
                            settingCV = false;
                            oldNo = nw;
                        }
                    };
                }
                else
                {
                    // start on the bank already picked on the voucher, if it is a bank account
                    string picked = searchLookUpEdit1.EditValue?.ToString();
                    if (!string.IsNullOrEmpty(picked))
                        foreach (DataRow r in banks.Rows)
                            if (Convert.ToString(r["AccountCode"]) == picked) { cboBank.EditValue = picked; break; }
                }

                btnSave.Click += (s, a) =>
                {
                    string bank = cboBank.EditValue?.ToString();
                    string no = txtNo.Text.Trim();
                    if (string.IsNullOrWhiteSpace(bank)) { XtraMessageBox.Show("Select the bank account."); return; }
                    if (no.Length == 0) { XtraMessageBox.Show("Enter the cheque number."); return; }
                    if (!(dtDate.EditValue is DateTime date)) { XtraMessageBox.Show("Enter the cheque date."); return; }
                    string reason = cboReason.Text.Trim();
                    if (reason.Length == 0) { XtraMessageBox.Show("Select the reason."); return; }
                    string cvNo = txtCV.Text.Trim();
                    if (cvNo.Length == 0) { XtraMessageBox.Show("Enter the CV number."); return; }

                    string ask = isEdit
                        ? $"Save the corrected details of this cancelled cheque?\n\nCheque {no}, {cboBank.Text}, CV no. {cvNo} ({reason})."
                        : $"Record cheque {no} of {cboBank.Text} as CANCELLED ({reason}), CV no. {cvNo}?\n\n" +
                          "It uses up this cheque no. and CV no.";
                    if (XtraMessageBox.Show(ask, dlg.Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                        return;

                    try
                    {
                        string message = isEdit ? "Cancelled cheque updated." : "Cancelled cheque recorded.";
                        using (var con = Database.getConnection())
                        using (var cmd = new SqlCommand(isEdit ? "dbo.sp_EditCancelledCheque" : "dbo.sp_RecordCancelledCheque", con) { CommandType = CommandType.StoredProcedure })
                        {
                            if (isEdit)
                            {
                                cmd.Parameters.Add("@VoucherID", SqlDbType.VarChar, 10).Value = Convert.ToString(existing["VoucherID"]);
                                cmd.Parameters.Add("@ReferenceNumber", SqlDbType.VarChar, 10).Value = Convert.ToString(existing["ReferenceNumber"]);
                            }
                            cmd.Parameters.Add("@BankGLCode", SqlDbType.VarChar, 30).Value = bank;
                            cmd.Parameters.Add("@CheckNo", SqlDbType.VarChar, 50).Value = no;
                            cmd.Parameters.Add("@CheckDate", SqlDbType.Date).Value = date.Date;
                            cmd.Parameters.Add("@Reason", SqlDbType.VarChar, 100).Value = reason;
                            cmd.Parameters.Add("@Remarks", SqlDbType.VarChar, 1000).Value = memo.Text.Trim();
                            cmd.Parameters.Add("@User", SqlDbType.VarChar, 50).Value = Login.Fullname;
                            cmd.Parameters.Add("@CVNo", SqlDbType.VarChar, 50).Value = cvNo;   // SQL/2026-10-12b / 12c
                            con.Open();
                            using (var rdr = cmd.ExecuteReader())
                                if (rdr.Read()) message = rdr["Message"]?.ToString() ?? message;
                        }
                        BigAlert.Show("SUCCESS", message, MessageBoxIcon.Information);
                        dlg.DialogResult = DialogResult.OK;
                    }
                    catch (SqlException ex)
                    {
                        XtraMessageBox.Show(ex.Message, dlg.Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    }
                };

                dlg.Controls.AddRange(new Control[] { info, lblBank, cboBank, lblNo, txtNo, lblDate, dtDate, lblCV, txtCV, lblReason, cboReason, lblRemarks, memo, btnSave, btnClose });
                dlg.CancelButton = btnClose;
                return dlg.ShowDialog(this) == DialogResult.OK;
            }
        }
        private void RepositoryItemCheckEditStat_EditValueChanged(object sender, EventArgs e)
        {
            gridViewMaster.PostEditor();        // commit immediately
            gridViewMaster.UpdateCurrentRow();  // trigger CellValueChanged
            gridViewMaster.UpdateTotalSummary();   // [97] the footers add up the ticked rows only
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

            // 2026-10-12 (user: the screen took a second to open): its 5 distinct lookup queries go in one
            // batch, one round trip (Database.FetchTables), then bind exactly as before. They used to run one after
            // another, 8 round trips (the 3 grid account lookups repeated the credit-account query).
            Dictionary<string, DataTable> t;
            try
            {
                t = Database.FetchTables(new Dictionary<string, string>
                {
                    // 2026-10-12 (user): the "CANCELLED" supplier was only a workaround for recording spoiled cheques;
                    // that is now "Cancelled Cheque…" (sp_RecordCancelledCheque), so it is hidden here
                    // 2026-10-15 (user, SQL [93]): cash / check pays LOCAL suppliers, plus an import supplier marked
                    // "Pay by Cash/Check and Telegraphic" (Supplier.isPayableBoth); imports go through Vouchering Telegraphic
                    ["suppliers"] = "SELECT SupplierID,SupplierName FROM Supplier WHERE LTRIM(RTRIM(SupplierName)) <> 'CANCELLED' AND (ISNULL(isLocal, 1) = 1 OR isPayableBoth = 1)",
                    ["coaD"] = "SELECT AccountCode, Description FROM ChartOfAccounts WHERE AccountType='D' ORDER BY AccountCode",
                    ["coa508"] = "SELECT AccountCode, Description FROM ChartOfAccounts ORDER BY CASE WHEN AccountCode = '508' THEN 0 ELSE 1 END, AccountCode",
                    ["coaAll"] = "SELECT coa.AccountCode, coa.Description, coa.AccountCode + '-' + coa.Description AS DisplayText FROM ChartOfAccounts coa ORDER BY coa.AccountCode",
                    ["branches"] = "SELECT BranchCode, BranchName, BranchCode + '-' + BranchName AS DisplayText FROM Branches ORDER BY BranchCode",
                });
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show("Failed to load dropdown data: " + ex.Message, "Database Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;   // not marked loaded: the next LoadData tries again
            }

            // same binding as Database.displaySearchlookupEdit
            searchLookUpSupplier.Properties.View.Columns.Clear();
            searchLookUpSupplier.Properties.DataSource = null;
            searchLookUpSupplier.Properties.DataSource = t["suppliers"];
            searchLookUpSupplier.Properties.DisplayMember = "SupplierName";
            searchLookUpSupplier.Properties.ValueMember = "SupplierID";   // 2026-10-15 (H6): the key, not the name
            searchLookUpSupplier.Properties.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;

            populateCOA(t["coaD"], t["coa508"]);
            radChanged();
            BindDebitAccountLookup(t["coaAll"]);
            BindBranchLineLookup(t["branches"]);

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
         
        private void BindBranchLineLookup(DataTable dt = null)   // 2026-10-12: dt = already fetched by LoadData
        {
            if (dt == null) dt = GetDataTable(
        "SELECT BranchCode, BranchName, BranchCode + '-' + BranchName AS DisplayText FROM Branches ORDER BY BranchCode");

            repBranchLine.DataSource = dt;
            repBranchLine.DisplayMember = "DisplayText";
            repBranchLine.ValueMember = "BranchCode";
            repBranchLineView.PopulateColumns();      // CHANGED — populate the popup grid's own View
            repBranchLineView.OptionsView.ShowGroupPanel = false;
        }
        private void BindDebitAccountLookup(DataTable dt = null)   // 2026-10-12: dt = already fetched by LoadData
        {
            if (dt == null) dt = GetDataTable(@"
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
        
        private void BindCreditGLCodeLookup(DataTable dt = null)   // 2026-10-12: dt = already fetched by LoadData
        {
            if (dt == null) dt = GetDataTable("SELECT AccountCode, Description FROM ChartOfAccounts WHERE AccountType='D' ORDER BY AccountCode");
            searchLookUpEdit1.Properties.DataSource = dt;
            searchLookUpEdit1.Properties.DisplayMember = "Description";
            searchLookUpEdit1.Properties.ValueMember = "AccountCode";
            searchLookUpEdit1.Properties.PopulateViewColumns();

        }
        void populateCOA(DataTable coaD = null, DataTable coa508 = null)   // 2026-10-12: tables already fetched by LoadData
        {
            if (coaD == null || coa508 == null)
            {
                var t = Database.FetchTables(new Dictionary<string, string>
                {
                    ["coaD"] = "SELECT AccountCode, Description FROM ChartOfAccounts WHERE AccountType='D' ORDER BY AccountCode",
                    ["coa508"] = "SELECT AccountCode, Description FROM ChartOfAccounts ORDER BY CASE WHEN AccountCode = '508' THEN 0 ELSE 1 END, AccountCode",
                });
                coaD = t["coaD"];
                coa508 = t["coa508"];
            }
            BindCreditGLCodeLookup(coaD);
            //Database.displaySearchlookupEdit("SELECT AccountCode,Description FROM ChartOfAccounts WHERE AccountType='D'", searchLookUpEdit1, "AccountCode", "AccountCode");
            // the 3 grid account lookups used the same AccountType='D' list: one fetch, a copy each
            // (same binding as Database.displayRepositorySearchlookupEdit)
            foreach (var rep in new[] { repositoryItemSearchLookUpEditoffsetdebitglcode, repositoryItemSearchLookUpEditoffsetCreditGLCode, repositoryItemSearchLookUpEditdiscountglcode })
            {
                rep.DataSource = coaD.Copy();
                rep.DisplayMember = "AccountCode";
                rep.ValueMember = "AccountCode";
            }
            // NEW — same helper, same pattern, defaults the popup to show 508 near the top
            repDiscountAccount.DataSource = coa508;
            repDiscountAccount.DisplayMember = "AccountCode";
            repDiscountAccount.ValueMember = "AccountCode";
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
            if (hasInvoices && !ValidateInvoiceLines()) return;

            // [97] every ticked row must say what it is (checked before any voucher / reference number is drawn)
            if (lines.Exists(l => l.Type != "PURCHASE" && l.Type != "EXPENSE"))
            {
                XtraMessageBox.Show("A ticked invoice has no Kind (purchase / expense). Reload the supplier's invoices and try again; nothing was posted.",
                    "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // [97] purchases + expenses on one voucher: cash / check only (the SQL refuses it too, 60232)
            if (radtelegraphic.Checked && TickedKinds() == "PURCHASE / EXPENSE")
            {
                XtraMessageBox.Show("A telegraphic voucher pays one kind at a time: tick only purchase invoices or only expense invoices,\n"
                    + "or use a cash / check voucher to pay both together.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            PostCombinedVoucher(lines, hasInvoices, hasDebitLines);
        }

        // NEW - client-side mirror of sp_AddPaymentSupplierCompound_V2's
        // overpayment guard (THROW 60502/60503/60504), so a bad row is
        // caught here with a clear message instead of only via a
        // SqlException after a full round-trip. The SP is still the real
        // guard (see SQL/2026-09-22_SupplierPayment_OverpaymentGuard.sql) --
        // this is purely fail-fast UX, not a substitute for it.
        // Iterates grid rows directly (not the already-built PaymentLine
        // list) so the offending row can be focused/flagged via
        // ShowRowError, same as the in-grid AmountPaid check.
        private bool ValidateInvoiceLines()
        {
            int overPayInvoiceCount = 0;
            decimal totalAdvanceApplied = 0m;

            for (int i = 0; i < gridViewMaster.RowCount; i++)
            {
                if (!ToBool(gridViewMaster.GetRowCellValue(i, "Pay"))) continue;

                string invoiceNo = gridViewMaster.GetRowCellValue(i, "InvoiceNo")?.ToString() ?? "";
                decimal balance = ToDecimal(gridViewMaster.GetRowCellValue(i, "Balance"));
                decimal gross = ComputeRowGross(i);
                decimal overPay = ToDecimal(gridViewMaster.GetRowCellValue(i, ColOverPay));
                decimal overPayExpense = ToDecimal(gridViewMaster.GetRowCellValue(i, ColOverPayExpense));
                decimal advanceApplied = ToDecimal(gridViewMaster.GetRowCellValue(i, ColAdvanceApplied));


                if (overPay < 0 || overPayExpense < 0 || advanceApplied < 0)
                {
                    ShowRowError(i, "OverPay / Advance Applied cannot be negative.", overPay < 0 ? ColOverPay : overPayExpense < 0 ? ColOverPayExpense : ColAdvanceApplied);
                    XtraMessageBox.Show($"Invoice {invoiceNo}: OverPay, OverPay (Expense), and Advance Applied cannot be negative.",
                        "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }

                // Mirrors THROW 60512 - each variant posts a different GL mnemonic.
                int variants = (overPay > 0 ? 1 : 0) + (overPayExpense > 0 ? 1 : 0) + (advanceApplied > 0 ? 1 : 0);
                if (variants > 1)
                {
                    ShowRowError(i, "Choose only one of OverPay / OverPay (Expense) / Advance Applied.", advanceApplied > 0 ? ColAdvanceApplied : ColOverPayExpense);
                    XtraMessageBox.Show($"Invoice {invoiceNo}: OverPay, OverPay (Expense), and Advance Applied cannot be combined on the same invoice - choose only one.",
                        "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }

                if (Math.Round(gross - balance, 2) > 0)
                {
                    ShowRowError(i, $"Amount Paid ({gross:N2} incl. EWT/Discount/Offset) exceeds Balance ({balance:N2}).");
                    XtraMessageBox.Show(
                        $"Invoice {invoiceNo}: the amount being settled ({gross:N2}) exceeds its Balance ({balance:N2}).\nLower Amount Paid, or put the excess in the OverPay (Credit) or OverPay (Expense) column.",
                        "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }

                // Mirrors THROW 60515 - an "overpayment" on a partially paid
                // invoice is really unpaid balance and must stay on the invoice.
                if ((overPay > 0 || overPayExpense > 0) && Math.Round(balance - gross, 2) != 0)
                {
                    ShowRowError(i, "OverPay is only allowed when the invoice is fully settled.", overPay > 0 ? ColOverPay : ColOverPayExpense);
                    XtraMessageBox.Show(
                        $"Invoice {invoiceNo}: OverPay is only allowed when the invoice is fully settled (Balance {balance:N2}, settled {gross:N2}).",
                        "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }

                if (overPay > 0 || overPayExpense > 0) overPayInvoiceCount++;
                totalAdvanceApplied += advanceApplied;
            }

            // Mirrors THROW 60513 - same one-invoice rule as the AR side.
            if (overPayInvoiceCount > 1)
            {
                XtraMessageBox.Show("OverPay / OverPay (Expense) must be assigned to only one invoice per voucher.",
                    "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }

            // Fail-fast only - re-fetched fresh here rather than trusting the
            // label, and the SP re-derives it again under a lock (THROW 60514).
            if (totalAdvanceApplied > 0)
            {
                RefreshAvailableCredit();
                if (totalAdvanceApplied > _availableCredit)
                {
                    XtraMessageBox.Show(
                        $"Advance Applied ({totalAdvanceApplied:N2}) exceeds this supplier's available advance credit ({_availableCredit:N2}).",
                        "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
            }
            return true;
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

            // [97] the kind comes from the ticked rows (the radio buttons are gone): one kind = today's call;
            // both kinds = MIXED: purchases in @PurchaseLines, expenses in @InvoiceLines, one voucher / cheque.
            var purchaseLines = lines.FindAll(l => l.Type == "PURCHASE");
            var expenseLines = lines.FindAll(l => l.Type == "EXPENSE");
            bool mixed = purchaseLines.Count > 0 && expenseLines.Count > 0;
            _payMethod = mixed ? "MIXED" : (purchaseLines.Count > 0 ? "PURCHASE" : "EXPENSE");
            var invoiceSide = mixed ? expenseLines : lines;          // @InvoiceLines
            var purchaseSide = mixed ? purchaseLines : new List<PaymentLine>();   // @PurchaseLines (mixed only)

            decimal invoiceLegAmount = 0;
            foreach (var ln in lines)
                invoiceLegAmount += ln.AmountPaid;

            var invoiceLinesTvp = BuildPaymentLinesTVP(hasInvoices ? invoiceSide : new List<PaymentLine>());
            var manualLinesTvp = BuildManualDebitLinesTVP(); // empty-but-correctly-shaped if hasDebitLines is false
            var lineExtrasTvp = BuildPaymentLineExtrasTVP(hasInvoices ? invoiceSide : new List<PaymentLine>());
            var purchaseLinesTvp = BuildPaymentLinesTVP(purchaseSide);
            var purchaseExtrasTvp = BuildPaymentLineExtrasTVP(purchaseSide);

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
                cmd.Parameters.Add("@parmcheckdate", SqlDbType.Date).Value = txtcheckdate.Text.Trim();
                    //radCheckVoucher.Checked && !string.IsNullOrWhiteSpace(txtcheckdate.Text)
                    //    ? (object)DateTime.Parse(txtcheckdate.Text) : DBNull.Value;
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

                var extrasParam = cmd.Parameters.AddWithValue("@InvoiceLineExtras", lineExtrasTvp);
                extrasParam.SqlDbType = SqlDbType.Structured;
                extrasParam.TypeName = "dbo.AP_PaymentLineExtraTVP";

                if (mixed)   // [97] sent only for a mixed voucher (the SQL side treats them as optional)
                {
                    var purParam = cmd.Parameters.AddWithValue("@PurchaseLines", purchaseLinesTvp);
                    purParam.SqlDbType = SqlDbType.Structured;
                    purParam.TypeName = "dbo.AP_PaymentLineTVP";

                    var purExtrasParam = cmd.Parameters.AddWithValue("@PurchaseLineExtras", purchaseExtrasTvp);
                    purExtrasParam.SqlDbType = SqlDbType.Structured;
                    purExtrasParam.TypeName = "dbo.AP_PaymentLineExtraTVP";
                }

                try
                {
                    con.Open();

                    string message = "Payment successfully posted.";
                    using (var rdr = cmd.ExecuteReader())
                        if (rdr.Read()) message = rdr["Message"]?.ToString() ?? message;

                    BigAlert.Show("SUCCESS", message, MessageBoxIcon.Information);

                    populate();
                    RefreshAvailableCredit();

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
                // [97] both kinds in one list (splist_Accounts both flags; Type tells the kind)
                cmd.Parameters.Add("@parmispurchase", SqlDbType.Bit).Value = true;
                cmd.Parameters.Add("@parmisexpense", SqlDbType.Bit).Value = true;

                var table = new DataTable();
                bool loadedOk = false;
                try
                {
                    Cursor.Current = Cursors.WaitCursor;
                    UseWaitCursor = true;
                    con.Open();
                    new SqlDataAdapter(cmd).Fill(table);

                    // 2026-09-24 - overpayment/advance columns, added client-side
                    // rather than in splist_Accounts (also feeds VoucheringManualFrm
                    // and HOFormsDevEx/SupplierPaymentDevEx, which would display them).
                    // 2026-09-24c/25 - Purchase and every Expense invoice (SINGLE and
                    // multi-branch). Multi-branch rules (booked on the head-office
                    // ticket) are enforced by sp_AddPaymentSupplierCompound_V2 (60522).
                    foreach (string extraCol in new[] { ColOverPay, ColOverPayExpense, ColAdvanceApplied })
                        if (!table.Columns.Contains(extraCol))
                            table.Columns.Add(new DataColumn(extraCol, typeof(decimal)) { DefaultValue = 0m });
                    foreach (DataRow r in table.Rows)
                        foreach (string extraCol in new[] { ColOverPay, ColOverPayExpense, ColAdvanceApplied })
                            if (r[extraCol] == DBNull.Value) r[extraCol] = 0m;

                    gridControlMaster.BeginUpdate();
                    gridViewMaster.Columns.Clear();
                    gridControlMaster.DataSource = table;
                    gridViewMaster.BestFitColumns();
                    FormatGridColumns();
                    loadedOk = true;
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

                // NEW - the SP failed or returned no columns: nothing below is safe to touch.
                // Previously this ran unconditionally and NullReferenceException'd on
                // gridViewMaster.Columns["..."] whenever Fill() threw or the result set
                // didn't carry one of these column names (e.g. Expense vs Purchase shape).
                if (!loadedOk || gridViewMaster.Columns.Count == 0)
                    return;
            }

            if (gridViewMaster.Columns.Count > 0)
                gridViewMaster.Columns[0].Visible = false;

            if (gridViewMaster.Columns["ShipmentNo"] != null) gridViewMaster.Columns["ShipmentNo"].Visible = false;
            if (gridViewMaster.Columns["BranchCode"] != null) gridViewMaster.Columns["BranchCode"].Visible = false;
            if (gridViewMaster.Columns["ReferenceNo"] != null) gridViewMaster.Columns["ReferenceNo"].Visible = false;
            if (gridViewMaster.Columns["BatchReferenceID"] != null) gridViewMaster.Columns["BatchReferenceID"].Visible = false;
            if (gridViewMaster.Columns["ReturnAllowances"] != null) gridViewMaster.Columns["ReturnAllowances"].Visible = false;
            Classes.DevXGridViewSettings.ShowFooterTotal(gridViewMaster, "ActualCost");

            // [97] one list for both kinds. These footers add up the TICKED rows only: an unticked expense row still
            // carries what was already paid and the accrued EWT / discount / offset left (zeroed when it is ticked),
            // so a plain column sum would mix "already paid" with "to pay" (GridViewMaster_CustomSummaryCalculate).
            foreach (string col in TickedSumColumns)
            {
                var c = gridViewMaster.Columns[col];
                if (c == null) continue;
                c.Summary.Clear();
                c.Summary.Add(DevExpress.Data.SummaryItemType.Custom, col, "{0:n2}");
            }
            if (!_tickedSummaryWired)
            {
                gridViewMaster.CustomSummaryCalculate += GridViewMaster_CustomSummaryCalculate;
                _tickedSummaryWired = true;
            }
            if (gridViewMaster.Columns["Type"] != null)
            {
                gridViewMaster.Columns["Type"].Visible = true;
                gridViewMaster.Columns["Type"].Caption = "Kind";
                gridViewMaster.Columns["Type"].OptionsColumn.AllowEdit = false;
            }

            // Overpayment/advance columns - both modes since 2026-09-24c.
            Classes.DevXGridViewSettings.ShowFooterTotal(gridViewMaster, ColOverPay);
            Classes.DevXGridViewSettings.ShowFooterTotal(gridViewMaster, ColOverPayExpense);
            Classes.DevXGridViewSettings.ShowFooterTotal(gridViewMaster, ColAdvanceApplied);
            if (gridViewMaster.Columns[ColOverPay] != null) gridViewMaster.Columns[ColOverPay].Caption = "OverPay (Credit)";
            if (gridViewMaster.Columns[ColOverPayExpense] != null) gridViewMaster.Columns[ColOverPayExpense].Caption = "OverPay (Expense)";
            if (gridViewMaster.Columns[ColAdvanceApplied] != null) gridViewMaster.Columns[ColAdvanceApplied].Caption = "Advance Applied";
            gridViewMaster.BestFitColumns();   // re-fit: captions above are longer than the field names populate() sized for
        }
        // Helper method to handle DevExpress UI formatting
        private void FormatGridColumns()
        {
            FormatNumericColumn(gridViewMaster.Columns["ActualCost"]);
            FormatNumericColumn(gridViewMaster.Columns["Balance"]);

            // NEW - AmountPaid, EWTAmount, DiscountAmount, ReturnAllowances are
            // auto-generated (typed as decimal in the DataTable) but previously had no
            // DisplayFormat/ColumnEdit set, so the grid rendered/edited them as plain
            // text and only the footer sum (ShowFooterTotal) looked numeric.
            // Row cells still stored the underlying decimal correctly, but reused
            // repAmount (the same numeric SpinEdit already used for gridViewLines'
            // "Amount" column) so the in-cell editor is numeric too, not free text.
            FormatNumericColumn(gridViewMaster.Columns["AmountPaid"], repAmount);
            FormatNumericColumn(gridViewMaster.Columns["EWTAmount"], repAmount);
            FormatNumericColumn(gridViewMaster.Columns["DiscountAmount"], repAmount);
            FormatNumericColumn(gridViewMaster.Columns["ReturnAllowances"], repAmount);
            FormatNumericColumn(gridViewMaster.Columns[ColOverPay], repAmount);
            FormatNumericColumn(gridViewMaster.Columns[ColOverPayExpense], repAmount);
            FormatNumericColumn(gridViewMaster.Columns[ColAdvanceApplied], repAmount);
        }

        private void FormatNumericColumn(DevExpress.XtraGrid.Columns.GridColumn col, DevExpress.XtraEditors.Repository.RepositoryItem edit = null)
        {
            if (col == null) return;

            col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            col.DisplayFormat.FormatString = "n2";

            if (edit != null)
            {
                col.ColumnEdit = edit;
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

        // dbo.AP_PaymentLineExtraTVP - one row per invoice line that actually
        // carries an OverPay / OverPayExpense / AdvanceApplied amount, keyed
        // by the same InvoiceNo + SequenceReferenceNumber the main TVP sends
        // (SequenceNumber stringified the same way BuildPaymentLinesTVP does).
        private DataTable BuildPaymentLineExtrasTVP(List<PaymentLine> lines)
        {
            var dt = new DataTable();
            dt.Columns.Add("InvoiceNo", typeof(string));
            dt.Columns.Add("SequenceReferenceNumber", typeof(string));
            dt.Columns.Add("OverPay", typeof(decimal));
            dt.Columns.Add("OverPayExpense", typeof(decimal));
            dt.Columns.Add("AdvanceApplied", typeof(decimal));

            foreach (var ln in lines)
            {
                if (ln.OverPay == 0m && ln.OverPayExpense == 0m && ln.AdvanceApplied == 0m) continue;
                dt.Rows.Add(ln.InvoiceNo, ln.SequenceNumber.ToString(), ln.OverPay, ln.OverPayExpense, ln.AdvanceApplied);
            }
            return dt;
        }

        // ── AVAILABLE ADVANCE CREDIT (unapplied supplier OverPay) ──────────
        // Mirrors ClientPaymentsDevExAcctg.RefreshAvailableCredit(). Display /
        // fail-fast only - sp_AddPaymentSupplierCompound_V2 re-derives it
        // under a per-supplier lock before accepting any Advance Applied.
        void RefreshAvailableCredit()
        {
            _availableCredit = 0m;
            string supplierId = txtsupplierid.Text.Trim();
            if (string.IsNullOrWhiteSpace(supplierId) || supplierId == "[Supplier Id]")
            {
                lblAvailableCredit.Text = "0.00";
                lblAvailableCredit.ForeColor = Color.Gray;
                return;
            }

            try
            {
                using (SqlConnection con = Database.getConnection())
                using (SqlCommand cmd = new SqlCommand("sp_GetSupplierAvailableCredit", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@SupplierID", SqlDbType.VarChar, 50).Value = supplierId;

                    con.Open();
                    object result = cmd.ExecuteScalar();
                    _availableCredit = (result == null || result == DBNull.Value) ? 0m : Convert.ToDecimal(result);
                    lblAvailableCredit.Text = _availableCredit.ToString("N2");
                    lblAvailableCredit.ForeColor = _availableCredit > 0 ? Color.DarkGreen : Color.Gray;
                }
            }
            catch (Exception ex)
            {
                // Non-critical display field - don't block supplier selection.
                System.Diagnostics.Debug.WriteLine("RefreshAvailableCredit failed: " + ex.Message);
                lblAvailableCredit.Text = "N/A";
            }
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
                SetCellIfExists(rowHandle, ColOverPay, 0m);
                SetCellIfExists(rowHandle, ColOverPayExpense, 0m);
                SetCellIfExists(rowHandle, ColAdvanceApplied, 0m);
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
                SetCellIfExists(rowHandle, ColOverPay, 0m);
                SetCellIfExists(rowHandle, ColOverPayExpense, 0m);
                SetCellIfExists(rowHandle, ColAdvanceApplied, 0m);

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
            decimal overPay = ToDecimal(gridViewMaster.GetRowCellValue(rowHandle, ColOverPay));
            decimal overPayExpense = ToDecimal(gridViewMaster.GetRowCellValue(rowHandle, ColOverPayExpense));
            decimal advanceApplied = ToDecimal(gridViewMaster.GetRowCellValue(rowHandle, ColAdvanceApplied));

            // Advance Applied settles the invoice like any other non-cash deduction.
            decimal totalDeduction = ewt + discount + offset + advanceApplied;

            if (totalDeduction > balance)
            {
                ShowRowError(rowHandle, "Total deductions exceed Balance");
                return;
            }

            // Variance adjusts the expected cash outlay - positive means MORE
            // cash goes out (FX Loss), negative means LESS (FX Gain).
            // OverPay/OverPayExpense are extra cash on top of a full settlement.
            decimal newAmount = balance - totalDeduction + overPay + overPayExpense;// + variance;

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

            if (col == "EWTAmount" || col == "DiscountAmount" || col == "ReturnAllowances"
                || col == ColOverPay || col == ColOverPayExpense || col == ColAdvanceApplied)//|| col == "Variance")
            {
                RecalculateRowAmount(e.RowHandle);

                // Live hint for the one-variant-per-invoice rule (hard block is
                // in ValidateInvoiceLines + the SP's THROW 60512).
                int variants = (ToDecimal(gridViewMaster.GetRowCellValue(e.RowHandle, ColOverPay)) > 0 ? 1 : 0)
                             + (ToDecimal(gridViewMaster.GetRowCellValue(e.RowHandle, ColOverPayExpense)) > 0 ? 1 : 0)
                             + (ToDecimal(gridViewMaster.GetRowCellValue(e.RowHandle, ColAdvanceApplied)) > 0 ? 1 : 0);
                if (variants > 1)
                    ShowRowError(e.RowHandle, "Choose only one of OverPay / OverPay (Expense) / Advance Applied.", col);

                UpdateTotalAmountToPay();
            }
            else if (col == "AmountPaid")
            {
                //RecalculateRowVariance(e.RowHandle);   // NEW - back-solve Variance

                // NEW - AmountPaid is directly editable and, unlike the
                // EWT/Discount/Offset path above (which always recomputes
                // AmountPaid = Balance - deductions, so Gross can never
                // exceed Balance by construction), had no check at all here.
                // A typed-in overpayment used to post fine and then corrupt
                // Balance on reversal (sp_AddPaymentSupplierCompound_V2 floors
                // Balance at 0 instead of rejecting it, then the reversal SP
                // adds the full paid amount back on top of that floor,
                // landing on the paid amount instead of the true original
                // Balance). The SP now rejects this server-side too (THROW
                // 60502/60503/60504) -- this is the earlier, in-grid warning.
                decimal balance = ToDecimal(gridViewMaster.GetRowCellValue(e.RowHandle, "Balance"));
                decimal gross = ComputeRowGross(e.RowHandle);

                if (Math.Round(gross - balance, 2) > 0)
                    ShowRowError(e.RowHandle, $"Amount Paid ({gross:N2} incl. EWT/Discount/Offset) exceeds Balance ({balance:N2})."
                        + " Put the excess in OverPay (Credit) or OverPay (Expense).");
                else
                    gridViewMaster.ClearColumnErrors();

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
            if (e.Column.FieldName == "DiscountAccountCode")   
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
        // fieldName defaults to AmountPaid (every pre-existing caller); the
        // OverPay/Advance checks pass their own column so the red mark lands
        // on the cell the user actually has to fix.
        private void ShowRowError(int rowHandle, string message, string fieldName = "AmountPaid")
        {
            gridViewMaster.SetColumnError(
                gridViewMaster.Columns[fieldName] ?? gridViewMaster.Columns["AmountPaid"],
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

                // [97] from the ticked rows: PURCHASE, EXPENSE or PURCHASE / EXPENSE (blank when nothing is ticked)
                string paytype = TickedKinds();
                bool mixedPrint = paytype == "PURCHASE / EXPENSE";

                xct.xrcheckdate.Text = txtcheckdate.Text;
                xct.xrpaytype.Text = paytype;
                xct.xrpaidto.Text = searchLookUpSupplier.Text;//txtsuppliername.Text;
                xct.xrparticular.Text = txtremakrs.Text;
                xct.xramount.Text = String.Format("{0:0,0.00}", amounttopay);
              
                string str = Classes.DecimalToWordExtension.ToWords(Convert.ToDecimal(txtamounttopay.Text));

                gridViewMaster.Columns["Balance"].Visible = false;
                gridViewMaster.Columns["BranchCode"].Visible = false;
               
                if (paytype != "PURCHASE")   // [97] expense rows present (alone or with purchases)
                {
                    gridViewMaster.Columns["BatchReferenceID"].Visible = false;
                    gridViewMaster.Columns["BatchReferenceID"].OptionsColumn.ShowInCustomizationForm = true;
                }

                if (gridViewMaster.Columns["Type"] != null)
                {
                    gridViewMaster.Columns["Type"].Visible = mixedPrint;   // [97] a mixed voucher prints each invoice's kind
                    gridViewMaster.Columns["Type"].OptionsColumn.ShowInCustomizationForm = true;
                }

                gridViewMaster.Columns["Balance"].OptionsColumn.ShowInCustomizationForm = true;
                gridViewMaster.Columns["BranchCode"].OptionsColumn.ShowInCustomizationForm = true;
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
            if (gridViewMaster.RowCount > 0 && RowType(gridViewMaster.FocusedRowHandle) == "EXPENSE")   // [97] the row's kind
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
            if (gridViewMaster.FocusedRowHandle >= 0 && RowType(gridViewMaster.FocusedRowHandle) == "EXPENSE")   // [97] the row's kind
            {
                HOFormsDevEx.ViewExpenseDetailsDevEx viewdetdevex = new HOFormsDevEx.ViewExpenseDetailsDevEx();
                viewdetdevex.groupControl1.Visible = false;
                Database.display($"SELECT * FROM dbo.view_ExpenseMasterDetails with(nolock) " +
                 $"WHERE BatchReferenceID ='{Convert.ToInt64(gridViewMaster.GetRowCellValue(gridViewMaster.FocusedRowHandle, "BatchReferenceID") ?? 0)}' " +
                 $"AND InvoiceNo='{Convert.ToString(gridViewMaster.GetRowCellValue(gridViewMaster.FocusedRowHandle, "InvoiceNo") ?? "")}' ", viewdetdevex.gridControl2, viewdetdevex.gridView2);
                viewdetdevex.ShowDialog(this);
            }
            else if (gridViewMaster.FocusedRowHandle >= 0)   // [97] purchases are in the same list now
            {
                XtraMessageBox.Show("Invoice details are shown for expense invoices only. This row is a purchase invoice (see the Kind column).",
                    "Invoice Details", MessageBoxButtons.OK, MessageBoxIcon.Information);
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
            txtsupplierid.Text = _suppid?.ToString() ?? "";
            if (_suppid == null) return;   // 2026-10-15 (H6): nothing picked / cleared: no supplier to load
            populate();
            RefreshAvailableCredit();
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
