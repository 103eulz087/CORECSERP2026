using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;
using System.Linq;

namespace SalesInventorySystem
{
    // ================================================================
    // ACCOUNT RECONCILIATION REPORT (2026-10-16, user: the accountants' format, D:\SQLREF\2.png = Peachtree's)
    // One layout for Bank Recon › Export and Accounting Reports › Bank Reconciliation (screen + Excel):
    //   GL side   Beginning GL + Cash Receipts - Cash Disbursements + Add (Less) Other = Ending GL
    //             (sp_rpt_BankRecon_GLMovement, script [99]: all branches, the month of the period end)
    //   Bank side Ending Bank + open deposits in transit - open outstanding checks + Add (Less) Other
    //             (open bank-side items: a bank credit memo is a LESS, debit memos / charges / NSF /
    //             auto-debits an ADD: the screen books them on the book side, this layout brings the bank
    //             to the GL) + Unreconciled difference = Ending GL.
    //   Unreconciled difference = Ending GL - (bank side) = minus the Bank Recon screen's Difference.
    // Sheet 2 of the workbook lists the GL lines by journal.
    // ================================================================
    public sealed class AccountReconReport
    {
        public sealed class Line
        {
            public DateTime? Date; public string Reference; public string Payee; public decimal Amount;
        }

        public string AccountCode, AccountName;
        public DateTime PeriodEnd;
        public decimal BeginningGL, CashReceipts, CashDisbursements, OtherGL, EndingGL;
        public decimal BankBalance;
        public readonly List<Line> Deposits = new List<Line>(), Checks = new List<Line>(), Others = new List<Line>();
        public DataTable GLLines = new DataTable();
        public readonly List<string> Notes = new List<string>();   // grey lines under the check row
        public string Footer = "";

        public decimal TotalDeposits => Deposits.Sum(l => l.Amount);
        public decimal TotalChecks => Checks.Sum(l => l.Amount);
        public decimal TotalOther => Others.Sum(l => l.Amount);
        public decimal Unreconciled => EndingGL - (BankBalance + TotalDeposits - TotalChecks + TotalOther);
        public decimal EndingGLBank => BankBalance + TotalDeposits - TotalChecks + TotalOther + Unreconciled;

        public string AccountTitle => string.IsNullOrWhiteSpace(AccountName) ? AccountCode : $"{AccountName} ({AccountCode})";

        // GL side + GL lines from sp_rpt_BankRecon_GLMovement ([99]). False when the database doesn't have the
        // proc yet (2812); any other error is thrown.
        public bool TryLoadGLMovement()
        {
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_rpt_BankRecon_GLMovement", con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 180 })
                {
                    cmd.Parameters.Add("@AccountCode", SqlDbType.VarChar, 20).Value = AccountCode;
                    cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = PeriodEnd;
                    var ds = new DataSet();
                    con.Open();
                    new SqlDataAdapter(cmd).Fill(ds);
                    if (ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                        throw new InvalidOperationException("The GL movement came back empty.");
                    var f = ds.Tables[0].Rows[0];
                    BeginningGL = Dec(f["BeginningGL"]);
                    CashReceipts = Dec(f["CashReceipts"]);
                    CashDisbursements = Dec(f["CashDisbursements"]);
                    OtherGL = Dec(f["OtherNet"]);
                    EndingGL = Dec(f["EndingGL"]);
                    string name = Convert.ToString(f["AccountName"]);
                    if (!string.IsNullOrWhiteSpace(name)) AccountName = name;
                    GLLines = ds.Tables.Count > 1 ? ds.Tables[1] : new DataTable();
                    return true;
                }
            }
            catch (SqlException ex) when (ex.Number == 2812)
            {
                return false;
            }
        }

        // One open item, from a sp_BankRecon_GetPeriod row (the screen's columns), by kind:
        // DIT = deposits (Control No / CR No / reference), OC = checks (CV # / cheque no. / control no. / reference),
        // anything else = a bank-side item ("<type> <reference>", a BCM counts negative).
        public void AddItem(string itemType, DataRow r)
        {
            itemType = (itemType ?? "").Trim().ToUpperInvariant();
            var d = Cell(r, "ItemDate");
            var line = new Line
            {
                Date = d == DBNull.Value ? (DateTime?)null : Convert.ToDateTime(d),
                Payee = Convert.ToString(Cell(r, "Payee")),
                Amount = Dec(Cell(r, "Amount"))
            };
            if (itemType == "DIT")
            {
                line.Reference = FirstText(r, "ControlNo", "CRNo", "ReferenceNo");
                Deposits.Add(line);
            }
            else if (itemType == "OC")
            {
                line.Reference = FirstText(r, "CVNo", "CheckNo", "ControlNo", "ReferenceNo");
                Checks.Add(line);
            }
            else
            {
                line.Reference = (itemType + " " + Convert.ToString(Cell(r, "ReferenceNo"))).Trim();
                if (itemType == "BCM") line.Amount = -line.Amount;
                Others.Add(line);
            }
        }

        public void SortItems()
        {
            // a fixed order (date, reference, payee, amount), so both screens list the same items the same way
            void Order(List<Line> lines)
            {
                var sorted = lines.OrderBy(l => l.Date ?? DateTime.MinValue)
                                  .ThenBy(l => l.Reference ?? "", StringComparer.OrdinalIgnoreCase)
                                  .ThenBy(l => l.Payee ?? "", StringComparer.OrdinalIgnoreCase)
                                  .ThenBy(l => l.Amount).ToList();
                lines.Clear(); lines.AddRange(sorted);
            }
            Order(Deposits); Order(Checks); Order(Others);
        }

        // ── the report as rows, for a grid on screen (same lines as sheet 1 of the workbook) ──
        // RowType: HEADING (title), DETAIL, SUBTOTAL (Ending GL Balance), NOTE (grey lines).
        public DataTable ToTable()
        {
            var t = new DataTable("AccountReconciliation");
            t.Columns.Add("RowType", typeof(string));
            t.Columns.Add("Description", typeof(string));
            t.Columns.Add("Date", typeof(DateTime));
            t.Columns.Add("Reference", typeof(string));
            t.Columns.Add("Payee", typeof(string));
            t.Columns.Add("Item Amount", typeof(decimal));
            t.Columns.Add("Total", typeof(decimal));

            void Add(string type, string text, decimal? total = null, Line l = null, bool showLabel = true)
            {
                var r = t.NewRow();
                r["RowType"] = type;
                r["Description"] = showLabel ? (object)text : DBNull.Value;
                if (l != null)
                {
                    if (l.Date.HasValue) r["Date"] = l.Date.Value;
                    r["Reference"] = l.Reference;
                    r["Payee"] = l.Payee;
                    r["Item Amount"] = l.Amount;
                }
                if (total.HasValue) r["Total"] = total.Value;
                t.Rows.Add(r);
            }
            void Blank() => Add("BLANK", null, showLabel: false);
            void Items(string label, List<Line> lines, string totalLabel, decimal total)
            {
                if (lines.Count == 0) Add("DETAIL", label + " (none)");
                for (int i = 0; i < lines.Count; i++) Add("DETAIL", label, l: lines[i], showLabel: i == 0);
                Add("DETAIL", totalLabel, total);
            }

            Add("HEADING", "ACCOUNT RECONCILIATION REPORT");
            Add("HEADING", PeriodEnd.ToString("MMMM d, yyyy", CultureInfo.InvariantCulture).ToUpperInvariant());
            Add("HEADING", AccountTitle);
            Blank();
            Add("DETAIL", "Beginning GL Balance", BeginningGL);
            Add("DETAIL", "Add: Cash Receipts", CashReceipts);
            Add("DETAIL", "Less: Cash Disbursements", CashDisbursements);
            Add("DETAIL", "Add (Less) Other", OtherGL);
            Add("SUBTOTAL", "Ending GL Balance", EndingGL);
            Blank();
            Add("DETAIL", "Ending Bank Balance", BankBalance);
            Items("Add back deposits in transit", Deposits, "Total deposits in transit", TotalDeposits);
            Blank();
            Items("(Less) outstanding checks", Checks, "Total outstanding checks", -TotalChecks);
            Blank();
            Items("Add (Less) Other", Others, "Total other", TotalOther);
            Blank();
            Add("DETAIL", "Unreconciled difference", Unreconciled);
            Add("SUBTOTAL", "Ending GL Balance", EndingGLBank);
            Add("NOTE", "Check (Ending GL above - Ending GL here)", EndingGL - EndingGLBank);
            foreach (var n in Notes) Add("NOTE", n);
            if (!string.IsNullOrEmpty(Footer)) Add("NOTE", Footer);
            return t;
        }

        // ── the workbook: sheet 1 the report, sheet 2 the GL lines by journal (DevExpress XL Export API) ──
        public void WriteXlsx(string fileName)
        {
            const string MONEY = "#,##0.00;(#,##0.00);0.00";
            DevExpress.Export.Xl.XlCellFormatting Fmt(bool bold = false, bool money = false, bool date = false,
                DevExpress.Export.Xl.XlBorderLineStyle bottom = DevExpress.Export.Xl.XlBorderLineStyle.None, bool grey = false, double size = 0)
            {
                var font = DevExpress.Export.Xl.XlFont.BodyFont();
                font.Bold = bold;
                if (size > 0) font.Size = size;
                if (grey) font.Color = System.Drawing.Color.Gray;
                var fm = new DevExpress.Export.Xl.XlCellFormatting { Font = font };
                if (money)
                {
                    fm.NumberFormat = MONEY;
                    fm.Alignment = new DevExpress.Export.Xl.XlCellAlignment { HorizontalAlignment = DevExpress.Export.Xl.XlHorizontalAlignment.Right };
                }
                if (date) fm.NumberFormat = "dd-mmm-yy";
                if (bottom != DevExpress.Export.Xl.XlBorderLineStyle.None)
                    fm.Border = new DevExpress.Export.Xl.XlBorder { BottomLineStyle = bottom, BottomColor = System.Drawing.Color.Black };
                return fm;
            }

            var exporter = DevExpress.Export.Xl.XlExport.CreateExporter(DevExpress.Export.Xl.XlDocumentFormat.Xlsx);
            using (var stream = new System.IO.FileStream(fileName, System.IO.FileMode.Create, System.IO.FileAccess.ReadWrite))
            using (var document = exporter.CreateDocument(stream))
            {
                // ── Sheet 1: the report ──
                using (var sheet = document.CreateSheet())
                {
                    sheet.Name = "Reconciliation";
                    foreach (int w in new[] { 250, 80, 120, 220, 115, 130 })      // A label, B date, C reference, D payee, E item, F total
                        using (var col = sheet.CreateColumn()) col.WidthInPixels = w;

                    // one row: (column, value, format) triples; a value of null leaves the cell out
                    void Row(params (int Col, object Value, DevExpress.Export.Xl.XlCellFormatting Format)[] cells)
                    {
                        using (var row = sheet.CreateRow())
                            foreach (var c in cells)
                            {
                                if (c.Value == null && c.Format == null) continue;
                                using (var cell = row.CreateCell(c.Col))
                                {
                                    if (c.Value is decimal dv) cell.Value = (double)dv;
                                    else if (c.Value is DateTime dt) cell.Value = dt;
                                    else if (c.Value != null) cell.Value = c.Value.ToString();
                                    if (c.Format != null) cell.ApplyFormatting(c.Format);
                                }
                            }
                    }
                    void Blank() { using (sheet.CreateRow()) { } }
                    void Items(string label, List<Line> lines, string totalLabel, decimal total)
                    {
                        if (lines.Count == 0)
                            Row((0, label, Fmt()), (4, 0m, Fmt(money: true, bottom: DevExpress.Export.Xl.XlBorderLineStyle.Thin)));
                        for (int i = 0; i < lines.Count; i++)
                        {
                            var l = lines[i];
                            bool last = i == lines.Count - 1;
                            Row((0, i == 0 ? label : null, i == 0 ? Fmt() : null),
                                (1, l.Date, l.Date.HasValue ? Fmt(date: true) : null),
                                (2, l.Reference, Fmt()),
                                (3, l.Payee, Fmt()),
                                (4, l.Amount, Fmt(money: true, bottom: last ? DevExpress.Export.Xl.XlBorderLineStyle.Thin : DevExpress.Export.Xl.XlBorderLineStyle.None)));
                        }
                        Row((0, totalLabel, Fmt()), (5, total, Fmt(money: true)));
                    }

                    var thin = DevExpress.Export.Xl.XlBorderLineStyle.Thin;
                    var dbl = DevExpress.Export.Xl.XlBorderLineStyle.Double;
                    decimal endGLBank = EndingGLBank;

                    Row((0, "ACCOUNT RECONCILIATION REPORT", Fmt(bold: true, size: 12)));
                    Row((0, PeriodEnd.ToString("MMMM d, yyyy", CultureInfo.InvariantCulture).ToUpperInvariant(), Fmt(bold: true)));
                    Row((0, AccountTitle, Fmt(bold: true)));
                    Blank();
                    Row((0, "Beginning GL Balance", Fmt()), (5, BeginningGL, Fmt(money: true)));
                    Row((0, "Add: Cash Receipts", Fmt()), (5, CashReceipts, Fmt(money: true)));
                    Row((0, "Less: Cash Disbursements", Fmt()), (5, CashDisbursements, Fmt(money: true)));
                    Row((0, "Add (Less) Other", Fmt()), (5, OtherGL, Fmt(money: true, bottom: thin)));
                    Row((0, "Ending GL Balance", Fmt()), (5, EndingGL, Fmt(bold: true, money: true, bottom: dbl)));
                    Blank();
                    Blank();
                    Row((0, "Ending Bank Balance", Fmt()), (5, BankBalance, Fmt(money: true)));
                    Items("Add back deposits in transit", Deposits, "Total deposits in transit", TotalDeposits);
                    Blank();
                    Items("(Less) outstanding checks", Checks, "Total outstanding checks", -TotalChecks);
                    Blank();
                    Items("Add (Less) Other", Others, "Total other", TotalOther);
                    Blank();
                    Row((0, "Unreconciled difference", Fmt()), (5, Unreconciled, Fmt(money: true, bottom: thin)));
                    Blank();
                    Row((0, "Ending GL Balance", Fmt()), (5, endGLBank, Fmt(bold: true, money: true, bottom: dbl)));
                    Blank();
                    Row((0, "Check (Ending GL above - Ending GL here)", Fmt(grey: true)), (5, EndingGL - endGLBank, Fmt(money: true, grey: true)));
                    foreach (var n in Notes)
                    {
                        Blank();
                        Row((0, n, Fmt(grey: true)));
                    }
                    if (!string.IsNullOrEmpty(Footer))
                    {
                        Blank();
                        Row((0, Footer, Fmt(grey: true)));
                    }
                }

                // ── Sheet 2: the GL lines behind the GL side, by journal ──
                using (var sheet = document.CreateSheet())
                {
                    sheet.Name = "GL Movement";
                    string[] heads = { "Journal", "Date", "Branch", "Ticket No.", "Reference", "Reference Key", "Mnemonic", "Particulars", "Debit", "Credit" };
                    string[] cols = { "Journal", "TicketDate", "BranchCode", "TicketNumber", "ReferenceNumber", "ReferenceKey", "Mnemonic", "Particulars", "Debit", "Credit" };
                    int[] widths = { 110, 80, 60, 80, 100, 130, 130, 320, 110, 110 };
                    foreach (int w in widths)
                        using (var col = sheet.CreateColumn()) col.WidthInPixels = w;

                    using (var row = sheet.CreateRow())
                        for (int i = 0; i < heads.Length; i++)
                            using (var cell = row.CreateCell(i))
                            {
                                cell.Value = heads[i];
                                cell.ApplyFormatting(Fmt(bold: true, bottom: DevExpress.Export.Xl.XlBorderLineStyle.Thin));
                            }

                    var moneyFmt = Fmt(money: true);
                    var dateFmt = Fmt(date: true);
                    foreach (DataRow r in GLLines.Rows)
                        using (var row = sheet.CreateRow())
                        {
                            for (int i = 0; i < heads.Length; i++)
                                using (var cell = row.CreateCell(i))
                                {
                                    object v = Cell(r, cols[i]);
                                    if (i == 1) { if (v != DBNull.Value) { cell.Value = Convert.ToDateTime(v); cell.ApplyFormatting(dateFmt); } }
                                    else if (i >= 8) { cell.Value = (double)Dec(v); cell.ApplyFormatting(moneyFmt); }
                                    else cell.Value = Convert.ToString(v);
                                }
                        }

                    using (sheet.CreateRow()) { }
                    foreach (var tot in new[] { ("Cash Receipts (debit - credit)", CashReceipts), ("Cash Disbursements (credit - debit)", CashDisbursements), ("Add (Less) Other (debit - credit)", OtherGL) })
                        using (var row = sheet.CreateRow())
                        {
                            using (var cell = row.CreateCell(7)) { cell.Value = tot.Item1; cell.ApplyFormatting(Fmt(bold: true)); }
                            using (var cell = row.CreateCell(9)) { cell.Value = (double)tot.Item2; cell.ApplyFormatting(Fmt(bold: true, money: true)); }
                        }
                }
            }
        }

        private static object Cell(DataRow r, string col) => r.Table.Columns.Contains(col) ? r[col] : DBNull.Value;

        private static string FirstText(DataRow r, params string[] cols)
        {
            foreach (var c in cols)
            {
                var v = Cell(r, c);
                if (v != DBNull.Value && v != null && !string.IsNullOrWhiteSpace(v.ToString())) return v.ToString().Trim();
            }
            return "";
        }

        public static decimal Dec(object v)
        {
            if (v == null || v == DBNull.Value) return 0m;
            return decimal.TryParse(v.ToString().Replace(",", ""), NumberStyles.Any, CultureInfo.InvariantCulture, out var r) ? r : 0m;
        }
    }
}
