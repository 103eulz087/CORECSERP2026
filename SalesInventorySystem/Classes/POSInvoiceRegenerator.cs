using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows.Forms;

namespace SalesInventorySystem.Classes
{
    /// <summary>
    /// Re-creates the sales-invoice (e-invoice) text files for every sale covered by a
    /// Z-Read, in the SAME format Printing.printReceipt writes at checkout
    /// (POS/POSConfirmPayment.ExecutePayment). Used by POSDevEx/POSXReadReportDevEx
    /// ("Generate Invoices" on a ZREAD row).
    ///
    /// Read-only and file-only: it never prints and never writes to the database, and the
    /// live printReceipt code is untouched. The two receipt layouts are mirrored here
    /// line-for-line but fed from saved data instead of the checkout grid/form:
    ///   - regular sale       -> Printing.printReceipt (no one-time discount overload)
    ///   - one-time discount   -> Printing.printReceipt (SENIOR/PWD/NAAC/SOLOPARENT/MOV/REGULAR
    ///                            overload), written as -CLIENT-COPY and -ACCOUNTING-COPY
    ///
    /// Data sources (all parameterized, one connection per run):
    ///   Z-Read scope  = BatchSalesSummary rows with the Z-Read's branch + machine on the
    ///                   Z-Read date (same filter spr_POSZReading uses for its SI range),
    ///                   Status='SOLD'.
    ///   Lines         = BatchSalesDetails, same columns/filter/order as the checkout grid
    ///                   (PointOfSale.displayHoldTransactions).
    ///   Discount      = SalesDiscount for the order on this branch + machine.
    ///   Amount payable= lines - SUM(DiscountAmount) - SUM(VatAdjustment), exactly as
    ///                   PointOfSale computes netdue before opening POSConfirmPayment
    ///                   (BatchSalesSummary.TotalAmount is NOT net of the VAT adjustment).
    ///   Cashier name  = Users.FullName for BatchSalesSummary.PreparedBy (a user ID).
    ///
    /// Tran# and date/time: sp_saveTransaction writes, per sale, a CashiersBlotter row
    /// (Tran# + amount payable) and a POSTransaction 'SALES' row (Tran# + time), neither with
    /// the order number. Sales are paired with those rows by sequence (user-approved) and
    /// each pair is checked against the blotter amount; if any check fails, pairing falls
    /// back to matching the sale's amount payable. Unresolved sales use
    /// SalesDiscount.TransactionNo when present, otherwise the Tran# prints blank.
    /// Every such case is written to GenerationLog.txt.
    ///
    /// Customer name/address/TIN/business style typed at checkout (POSEncodeCustomerInfo)
    /// are never saved, so they print as blanks.
    /// </summary>
    class POSInvoiceRegenerator
    {
        public const string DefaultRootFolder = @"C:\POSTransaction\ZReadInvoices";

        // The line amounts come back as FORMAT(..., 'N', 'en-us') text ("1,234.50"), so they
        // are parsed with en-US regardless of the PC's regional settings.
        private static readonly CultureInfo EnUs = CultureInfo.GetCultureInfo("en-US");

        public class Result
        {
            public string Folder;
            public int Invoices;
            public int Files;
            public List<string> Warnings = new List<string>();
        }

        // One sale (BatchSalesSummary row) plus everything needed to rebuild its invoice.
        private class Sale
        {
            public string RefNo, CashierId, CustomerNo, PaymentType;
            public DateTime TransDate;
            public decimal TotalAmount, Tendered, Change, VatableSale, VatExemptSale, Vat, ZeroRated;
            public DataTable Lines;
            public DataRow Discount;            // first SalesDiscount row (display fields), null when none
            public double DiscountTotal;        // SUM(DiscountAmount) -- as PointOfSale.getSalesDiscount
            public double VatAdjTotal;          // SUM(VatAdjustment)  -- as PointOfSale.getVatAdjustment
            public string DiscountTransNo = "";
            public string TransNo = "";
            public DateTime? PaidAt;

            public double LinesAmount;          // checkout grid total (TOTAL DUE)
            public double LinesDiscount;        // per-item discount total
            public double NetPayable;           // amount payable at checkout (AMOUNT DUE)
        }

        public static Result GenerateForZRead(string branchCode, string machine, DateTime zreadDate)
        {
            var result = new Result();
            string day = zreadDate.ToString("yyyyMMdd", CultureInfo.InvariantCulture);
            result.Folder = Path.Combine(DefaultRootFolder, SafeName(branchCode), day + "_" + SafeName(machine));

            using (var con = Database.getConnection())
            {
                con.Open();

                var sales = LoadSales(con, branchCode, machine, zreadDate.Date);
                if (sales.Count == 0)
                {
                    result.Warnings.Add("No SOLD sales found for this branch/machine/date.");
                    return result;
                }
                LoadLines(con, branchCode, machine, zreadDate.Date, sales);
                LoadDiscounts(con, branchCode, machine, zreadDate.Date, sales);
                ComputeAmounts(sales, result.Warnings);
                MatchTransNos(con, branchCode, machine, zreadDate.Date, sales, result.Warnings);
                var cashierNames = LoadCashierNames(con, sales);

                if (sales.All(s => s.PaidAt == null) && sales.All(s => s.TransDate.TimeOfDay == TimeSpan.Zero))
                    result.Warnings.Add("No time of day is stored for these sales -- invoice dates print as 12:00:00 AM.");

                // Start from an empty folder so files from an earlier run (e.g. an SI no longer
                // SOLD, or a .txt left next to -CLIENT-COPY files) can't linger.
                Directory.CreateDirectory(result.Folder);
                foreach (string old in Directory.GetFiles(result.Folder, "*.txt"))
                    File.Delete(old);

                string footer = ReadFooter(result.Warnings);
                string header = ReceiptSetup.doHeader(branchCode, machine);   // business name/TIN/SN/MIN for this branch+machine
                if (string.IsNullOrWhiteSpace(header))
                    result.Warnings.Add("No POSInfoDetails header found for branch " + branchCode + " / machine " + machine +
                                        " -- invoices were written without the business name, TIN, S/N and MIN.");

                var ctx = new BuildContext(con, branchCode);
                foreach (var s in sales)
                {
                    string cashier;
                    if (!cashierNames.TryGetValue(s.CashierId ?? "", out cashier) || string.IsNullOrWhiteSpace(cashier))
                        cashier = s.CashierId;

                    try
                    {
                        if (s.Lines.Rows.Count == 0)
                            result.Warnings.Add("SI " + s.RefNo + ": no active (non-void, non-cancelled) lines found -- invoice has no items.");

                        if (s.Discount == null)
                        {
                            File.WriteAllText(Path.Combine(result.Folder, SafeName(s.RefNo) + ".txt"),
                                              BuildRegular(ctx, s, header, cashier, footer));
                            result.Files++;
                        }
                        else
                        {
                            foreach (string copy in new[] { "CLIENT-COPY", "ACCOUNTING-COPY" })
                            {
                                File.WriteAllText(Path.Combine(result.Folder, SafeName(s.RefNo) + "-" + copy + ".txt"),
                                                  BuildDiscounted(ctx, s, header, cashier, footer, copy));
                                result.Files++;
                            }
                        }
                        result.Invoices++;
                    }
                    catch (Exception ex)
                    {
                        result.Warnings.Add("SI " + s.RefNo + ": not generated -- " + ex.Message);
                    }
                }

                try { WriteLog(result, branchCode, machine, zreadDate, sales.Count); }
                catch (Exception ex) { result.Warnings.Add("GenerationLog.txt could not be written: " + ex.Message); }
            }
            return result;
        }

        // ================================================================
        // DATA
        // ================================================================
        private static List<Sale> LoadSales(SqlConnection con, string branch, string machine, DateTime day)
        {
            var list = new List<Sale>();
            const string sql = @"
                SELECT ReferenceNo, PreparedBy, CustomerNo, PaymentType, Transdate,
                       ISNULL(TotalAmount, 0) AS TotalAmount, ISNULL(AmountTendered, 0) AS AmountTendered,
                       ISNULL(AmountChange, 0) AS AmountChange, ISNULL(TotalVatableSale, 0) AS TotalVatableSale,
                       ISNULL(TotalVATExemptSale, 0) AS TotalVATExemptSale, ISNULL(TotalVATSale, 0) AS TotalVATSale,
                       ISNULL(ZeroRatedSale, 0) AS ZeroRatedSale
                FROM dbo.BatchSalesSummary
                WHERE BranchCode = @Branch
                  AND MachineUsed = @Machine
                  AND Transdate >= @Day AND Transdate < DATEADD(DAY, 1, @Day)
                  AND Status = 'SOLD'
                ORDER BY TRY_CAST(ReferenceNo AS BIGINT), ReferenceNo";
            using (var cmd = new SqlCommand(sql, con))
            {
                AddScope(cmd, branch, machine, day);
                using (var r = cmd.ExecuteReader())
                {
                    while (r.Read())
                    {
                        list.Add(new Sale
                        {
                            RefNo = r["ReferenceNo"].ToString().Trim(),
                            CashierId = r["PreparedBy"].ToString().Trim(),
                            CustomerNo = r["CustomerNo"].ToString().Trim(),
                            PaymentType = r["PaymentType"].ToString().Trim(),
                            TransDate = r["Transdate"] == DBNull.Value ? day : Convert.ToDateTime(r["Transdate"]),
                            TotalAmount = Convert.ToDecimal(r["TotalAmount"]),
                            Tendered = Convert.ToDecimal(r["AmountTendered"]),
                            Change = Convert.ToDecimal(r["AmountChange"]),
                            VatableSale = Convert.ToDecimal(r["TotalVatableSale"]),
                            VatExemptSale = Convert.ToDecimal(r["TotalVATExemptSale"]),
                            Vat = Convert.ToDecimal(r["TotalVATSale"]),
                            ZeroRated = Convert.ToDecimal(r["ZeroRatedSale"])
                        });
                    }
                }
            }
            return list;
        }

        // Same columns, filter and order as the checkout grid (PointOfSale.displayHoldTransactions),
        // so each printed line reads exactly as it did at checkout.
        private static void LoadLines(SqlConnection con, string branch, string machine, DateTime day, List<Sale> sales)
        {
            const string sql = @"
                SELECT d.ReferenceNo,
                       d.Description AS Particulars,
                       ISNULL(FORMAT(d.SellingPrice, 'N', 'en-us'), '0.00') AS UnitPrice,
                       d.QtySold AS Qty,
                       ISNULL(FORMAT(d.DiscountTotal, 'N', 'en-us'), '0.00') AS Discount,
                       ISNULL(FORMAT(d.TotalAmount, 'N', 'en-us'), '0.00') AS Amount,
                       ISNULL(d.isVat, 0) AS isVat
                FROM dbo.BatchSalesDetails d
                WHERE d.BranchCode = @Branch
                  AND d.MachineUsed = @Machine
                  AND d.isVoid = 0
                  AND d.isCancelled = 0
                  AND d.ReferenceNo IN (SELECT s.ReferenceNo FROM dbo.BatchSalesSummary s
                                        WHERE s.BranchCode = @Branch AND s.MachineUsed = @Machine
                                          AND s.Transdate >= @Day AND s.Transdate < DATEADD(DAY, 1, @Day)
                                          AND s.Status = 'SOLD')
                ORDER BY d.ReferenceNo, d.SequenceNumber DESC";
            var all = new DataTable();
            using (var cmd = new SqlCommand(sql, con))
            using (var da = new SqlDataAdapter(cmd))
            {
                AddScope(cmd, branch, machine, day);
                da.Fill(all);
            }

            var byRef = new Dictionary<string, DataTable>();
            foreach (var s in sales)
                byRef[s.RefNo] = s.Lines = all.Clone();
            foreach (DataRow r in all.Rows)
            {
                DataTable t;
                if (byRef.TryGetValue(r["ReferenceNo"].ToString().Trim(), out t))
                    t.ImportRow(r);
            }
        }

        private static void LoadDiscounts(SqlConnection con, string branch, string machine, DateTime day, List<Sale> sales)
        {
            const string sql = @"
                SELECT OrderNo, TransactionNo, DiscountType, DiscountAmount, VatAdjustment, DiscName, DiscIDNo,
                       DiscRemarks, DiscountPercentage, DateExecute
                FROM dbo.SalesDiscount
                WHERE BranchCode = @Branch AND MachineUsed = @Machine AND isErrorCorrect = 0
                  AND OrderNo IN (SELECT s.ReferenceNo FROM dbo.BatchSalesSummary s
                                  WHERE s.BranchCode = @Branch AND s.MachineUsed = @Machine
                                    AND s.Transdate >= @Day AND s.Transdate < DATEADD(DAY, 1, @Day)
                                    AND s.Status = 'SOLD')
                ORDER BY OrderNo, DateExecute";
            var all = new DataTable();
            using (var cmd = new SqlCommand(sql, con))
            using (var da = new SqlDataAdapter(cmd))
            {
                AddScope(cmd, branch, machine, day);
                da.Fill(all);
            }

            foreach (var s in sales)
            {
                foreach (DataRow r in all.Rows)
                {
                    if (r["OrderNo"].ToString().Trim() != s.RefNo) continue;
                    if (s.Discount == null)
                    {
                        s.Discount = r;
                        s.DiscountTransNo = r["TransactionNo"].ToString().Trim();
                    }
                    s.DiscountTotal += r["DiscountAmount"] == DBNull.Value ? 0 : Convert.ToDouble(r["DiscountAmount"]);
                    s.VatAdjTotal += r["VatAdjustment"] == DBNull.Value ? 0 : Convert.ToDouble(r["VatAdjustment"]);
                }
            }
        }

        // Amount payable exactly as checkout computes it (PointOfSale, before opening
        // POSConfirmPayment): grid total - one-time discount - VAT adjustment.
        private static void ComputeAmounts(List<Sale> sales, List<string> warnings)
        {
            foreach (var s in sales)
            {
                s.LinesAmount = SumLines(s, "Amount");
                s.LinesDiscount = SumLines(s, "Discount");
                s.NetPayable = s.LinesAmount - Math.Round(s.DiscountTotal, 2) - Math.Round(s.VatAdjTotal, 2);

                // Regular sale: sp_saveTransaction stores TotalAmount = grid total, so a
                // difference means lines were voided/cancelled/changed after the sale.
                if (s.Discount == null && Math.Abs(s.LinesAmount - (double)s.TotalAmount) > 0.01)
                    warnings.Add(string.Format(EnUs, "SI {0}: line total {1:N2} differs from the saved sale total {2:N2} (lines changed after the sale?) -- invoice generated from the current lines.",
                        s.RefNo, s.LinesAmount, (double)s.TotalAmount));

                // Cross-check against what was actually collected (cash sales).
                if (s.Tendered > 0 && Math.Abs((double)(s.Tendered - s.Change) - s.NetPayable) > 0.01)
                    warnings.Add(string.Format(EnUs, "SI {0}: amount payable rebuilt as {1:N2} but tendered - change = {2:N2} -- check this invoice.",
                        s.RefNo, s.NetPayable, (double)(s.Tendered - s.Change)));
            }
        }

        // sp_saveTransaction logs, per sale, CashiersBlotter (Tran# + amount payable) and
        // POSTransaction 'SALES' (Tran# + time) -- without the order number. Pair by sequence,
        // verify each pair by amount, and fall back to amount matching if any check fails.
        private static void MatchTransNos(SqlConnection con, string branch, string machine, DateTime day,
                                          List<Sale> sales, List<string> warnings)
        {
            var salesRows = new List<Tuple<string, DateTime?>>();     // Tran#, time (payment order)
            const string sqlTrans = @"
                SELECT TransactionNo, DateAdded
                FROM dbo.POSTransaction
                WHERE BranchCode = @Branch AND MachineUsed = @Machine AND Type = 'SALES'
                  AND DateAdded >= @Day AND DateAdded < DATEADD(DAY, 1, @Day)
                ORDER BY DateAdded, TRY_CAST(TransactionNo AS BIGINT), TransactionNo";
            using (var cmd = new SqlCommand(sqlTrans, con))
            {
                AddScope(cmd, branch, machine, day);
                using (var r = cmd.ExecuteReader())
                    while (r.Read())
                        salesRows.Add(Tuple.Create(r["TransactionNo"].ToString().Trim(),
                                                   r["DateAdded"] == DBNull.Value ? (DateTime?)null : Convert.ToDateTime(r["DateAdded"])));
            }

            var blotterAmount = new Dictionary<string, double>();        // Tran# -> amount payable
            const string sqlBlotter = @"
                SELECT ReferenceNo, CashIn
                FROM dbo.CashiersBlotter
                WHERE Branch = @Branch AND MachineUsed = @Machine AND Transcode = 'CshSls'
                  AND TransactionDate = @Day";
            using (var cmd = new SqlCommand(sqlBlotter, con))
            {
                AddScope(cmd, branch, machine, day);
                using (var r = cmd.ExecuteReader())
                    while (r.Read())
                    {
                        string tn = r["ReferenceNo"].ToString().Trim();
                        if (!blotterAmount.ContainsKey(tn) && r["CashIn"] != DBNull.Value)
                            blotterAmount[tn] = Convert.ToDouble(r["CashIn"]);
                    }
            }

            var timeOf = salesRows.GroupBy(x => x.Item1).ToDictionary(g => g.Key, g => g.First().Item2);
            Func<double, double, bool> same = (a, b) => Math.Abs(a - b) <= 0.01;

            // 1) Sequence pairing (sales by SI No., 'SALES' rows by time), verified by amount.
            bool sequenceOk = salesRows.Count == sales.Count;
            if (sequenceOk)
            {
                for (int i = 0; i < sales.Count; i++)
                {
                    double amt;
                    if (blotterAmount.TryGetValue(salesRows[i].Item1, out amt) && !same(amt, sales[i].NetPayable))
                    {
                        sequenceOk = false;
                        break;
                    }
                }
            }

            if (sequenceOk)
            {
                for (int i = 0; i < sales.Count; i++)
                {
                    sales[i].TransNo = salesRows[i].Item1;
                    sales[i].PaidAt = salesRows[i].Item2;
                }
                return;
            }

            warnings.Add(salesRows.Count == sales.Count
                ? "Tran# by sequence did not match the cashier's blotter amounts (e.g. a held sale paid later) -- matched by amount payable instead."
                : string.Format("Tran# by sequence not possible: {0} POSTransaction 'SALES' rows vs {1} sold invoices -- matched by amount payable instead.",
                                salesRows.Count, sales.Count));

            // 2) Amount matching: each sale takes the earliest unused Tran# whose blotter amount
            //    equals its amount payable. Ties (same amount) are assigned in payment order and
            //    listed in the log.
            var used = new HashSet<string>();
            var ordered = salesRows.Select(x => x.Item1).Where(blotterAmount.ContainsKey).ToList();
            foreach (var s in sales)
            {
                var candidates = ordered.Where(tn => !used.Contains(tn) && same(blotterAmount[tn], s.NetPayable)).ToList();
                if (candidates.Count > 0)
                {
                    s.TransNo = candidates[0];
                    DateTime? t;
                    if (timeOf.TryGetValue(candidates[0], out t)) s.PaidAt = t;
                    used.Add(candidates[0]);
                    if (candidates.Count > 1)
                        warnings.Add("SI " + s.RefNo + ": " + candidates.Count + " sales share this amount -- Tran# " + s.TransNo + " assigned by payment order.");
                }
                else if (!string.IsNullOrEmpty(s.DiscountTransNo))
                {
                    s.TransNo = s.DiscountTransNo;
                    warnings.Add("SI " + s.RefNo + ": no blotter match -- Tran# taken from SalesDiscount (" + s.TransNo + "), may differ from the printed one.");
                }
                else
                {
                    warnings.Add("SI " + s.RefNo + ": no blotter match -- Tran# left blank.");
                }
            }
        }

        private static Dictionary<string, string> LoadCashierNames(SqlConnection con, List<Sale> sales)
        {
            var names = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (string id in sales.Select(x => x.CashierId).Where(x => !string.IsNullOrEmpty(x)).Distinct())
            {
                using (var cmd = new SqlCommand("SELECT TOP 1 FullName FROM dbo.Users WHERE UserID = @UserID", con))
                {
                    cmd.Parameters.Add("@UserID", SqlDbType.VarChar, 50).Value = id;
                    object o = cmd.ExecuteScalar();
                    if (o != null && o != DBNull.Value) names[id] = o.ToString();
                }
            }
            return names;
        }

        // Shared, open connection + per-run caches for the layout builders.
        private class BuildContext
        {
            public readonly SqlConnection Con;
            public readonly string Branch;
            public readonly Dictionary<string, bool> DiscountableProduct = new Dictionary<string, bool>(StringComparer.Ordinal);
            public readonly Dictionary<string, Tuple<string, string>> NetOfVat = new Dictionary<string, Tuple<string, string>>();
            public BuildContext(SqlConnection con, string branch) { Con = con; Branch = branch; }
        }

        // ================================================================
        // LAYOUT -- regular sale (mirrors Printing.printReceipt, no one-time discount)
        // ================================================================
        private static string BuildRegular(BuildContext ctx, Sale s, string header, string cashier, string footer)
        {
            // Checkout: total = convertToNumericFormat(totaldue); peritemdiscount = the "{0:n2}"
            // label; VAT figures, tendered and change = "{0:n2}".
            string total = HelperFunction.convertToNumericFormat(s.LinesAmount);
            string peritemdiscount = N2(s.LinesDiscount);
            string vatablesale = N2((double)s.VatableSale), vatexemptsale = N2((double)s.VatExemptSale), vat = N2((double)s.Vat);
            string cash = N2((double)s.Tendered), change = N2((double)s.Change);
            bool iszerorated = s.ZeroRated != 0;
            string paytype = s.PaymentType;

            var d = new StringBuilder();
            d.Append("" + (Char)27 + (Char)112 + (Char)0 + (Char)25 + "");
            d.Append(header);
            d.Append(ReceiptSetup.doTitle("SALES INVOICE"));
            d.Append(HeaderDetails(s, cashier));
            d.Append(HelperFunction.createDottedLine() + Environment.NewLine);

            foreach (DataRow line in s.Lines.Rows)
            {
                string addV = Convert.ToBoolean(line["isVat"]) ? "V" : "";
                double lineDisc = Num(line["Discount"]);
                string addD = lineDisc > 0 ? "  - (Less: Discount)" : "";
                d.Append(HelperFunction.PrintLeftText(line["Particulars"].ToString()) + Environment.NewLine);
                string a = "  - " + line["Qty"] + " @ " + line["UnitPrice"];
                double cleanbalance = Num(line["Amount"]) + lineDisc;
                string b = " " + HelperFunction.convertToNumericFormat(cleanbalance) + addV;
                d.Append(HelperFunction.PrintLeftRigthText(a, b) + Environment.NewLine);
                if (lineDisc > 0)
                    d.Append(HelperFunction.PrintLeftRigthText(addD, "(" + line["Discount"].ToString() + ")") + Environment.NewLine);
            }
            d.Append(HelperFunction.PrinttoRight("----------") + Environment.NewLine);
            if (s.LinesDiscount > 0)
                d.Append(HelperFunction.PrintLeftRigthText("TOTAL DISCOUNT:", peritemdiscount) + Environment.NewLine);
            d.Append(HelperFunction.PrintLeftRigthText("TOTAL DUE:", total) + Environment.NewLine);
            d.Append(HelperFunction.PrinttoRight("==========") + Environment.NewLine);

            if (paytype == "Credit")
            {
                d.Append(HelperFunction.PrintLeftRigthText("TENDERED:", HelperFunction.convertToNumericFormat(s.NetPayable)) + Environment.NewLine + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("CHANGE  :", "0.00") + Environment.NewLine + Environment.NewLine);
            }
            d.Append(HelperFunction.PrintLeftRigthText("TENDERED:", cash) + Environment.NewLine);
            d.Append(HelperFunction.PrintLeftRigthText("CHANGE  :", change) + Environment.NewLine + Environment.NewLine);
            if (iszerorated)
            {
                d.Append(HelperFunction.PrintLeftRigthText("VATable Sales", "0.00") + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("VAT Amount", "0.00") + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("VAT-EXEMPT SALES", "0.00") + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("ZERO RATED SALES", total) + Environment.NewLine + Environment.NewLine);
            }
            else
            {
                d.Append(HelperFunction.PrintLeftRigthText("VATable Sales", vatablesale) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("VAT Amount", vat) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("VAT-EXEMPT SALES", vatexemptsale) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("ZERO RATED SALES", "0.00") + Environment.NewLine + Environment.NewLine);
            }
            AppendPaymentDetails(ctx, d, s);

            d.Append(HelperFunction.PrintCenterText(footer) + Environment.NewLine);
            d.Append(HelperFunction.LastPagePaper());
            return d.ToString();
        }

        // Credit-card / merchant blocks of the regular layout (same lookups, parameterized).
        private static void AppendPaymentDetails(BuildContext ctx, StringBuilder d, Sale s)
        {
            if (s.PaymentType == "Credit")
            {
                string cardtype = "", cardrefno = "", last4 = "";
                using (var cmd = new SqlCommand("SELECT TOP 1 CCType, CCPaymentReferenceNo, RIGHT(CCNumber, 4) AS Last4 FROM dbo.POSCreditCardTransactions WHERE ReferenceNo = @OrderNo AND BranchCode = @Branch", ctx.Con))
                {
                    cmd.Parameters.Add("@OrderNo", SqlDbType.VarChar, 20).Value = s.RefNo;
                    cmd.Parameters.Add("@Branch", SqlDbType.VarChar, 10).Value = ctx.Branch;
                    using (var r = cmd.ExecuteReader())
                        if (r.Read()) { cardtype = r["CCType"].ToString(); cardrefno = r["CCPaymentReferenceNo"].ToString(); last4 = r["Last4"].ToString(); }
                }
                d.Append(HelperFunction.createDottedLine() + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftText("PAYMENT TYPE: Credit Card") + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftText("Card Number: XXXX-XXXX-XXXX-" + last4) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftText("Card Type: " + cardtype) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftText("Reference No.: " + cardrefno) + Environment.NewLine);
                d.Append(HelperFunction.createDottedLine() + Environment.NewLine);
            }
            else if (s.PaymentType == "Merchant")
            {
                string refno = "", merchant = "", voucher = "";
                using (var cmd = new SqlCommand("SELECT TOP 1 ReferenceNo, MerchantName, VoucherCode FROM dbo.POSMerchantTransactions WHERE OrderNo = @OrderNo", ctx.Con))
                {
                    cmd.Parameters.Add("@OrderNo", SqlDbType.VarChar, 20).Value = s.RefNo;
                    using (var r = cmd.ExecuteReader())
                        if (r.Read()) { refno = r["ReferenceNo"].ToString(); merchant = r["MerchantName"].ToString(); voucher = r["VoucherCode"].ToString(); }
                }
                d.Append(HelperFunction.createDottedLine() + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftText("PAYMENT TYPE: Merchant " + merchant) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftText("VoucherCode: " + voucher) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftText("Reference No.: " + refno) + Environment.NewLine);
                d.Append(HelperFunction.createDottedLine() + Environment.NewLine);
            }
        }

        // ================================================================
        // LAYOUT -- one-time discount (mirrors the SENIOR/PWD/... printReceipt overload)
        // ================================================================
        private static string BuildDiscounted(BuildContext ctx, Sale s, string header, string cashier, string footer, string footerlabel)
        {
            DataRow disc = s.Discount;
            string disctype = disc["DiscountType"].ToString().Trim();
            string discremarks = disc["DiscRemarks"].ToString();
            double discountpercentage = disc["DiscountPercentage"] == DBNull.Value ? 0 : Convert.ToDouble(disc["DiscountPercentage"]);
            double discamount = disc["DiscountAmount"] == DBNull.Value ? 0 : Convert.ToDouble(disc["DiscountAmount"]);
            string discname = disc["DiscName"].ToString();
            string discidno = disc["DiscIDNo"].ToString();
            double discpercent = discountpercentage * 100;

            string total = HelperFunction.convertToNumericFormat(s.LinesAmount);
            string peritemdiscount = N2(s.LinesDiscount);
            double netamountpayable = s.NetPayable;
            string vatexemptsale = N2((double)s.VatExemptSale);
            string cash = N2((double)s.Tendered);
            string paytype = s.PaymentType;

            // func_getNetOfVatIn(Non)DiscountedItems -- computed once per sale, reused by both copies.
            Tuple<string, string> nov;
            if (!ctx.NetOfVat.TryGetValue(s.RefNo, out nov))
            {
                using (var cmd = new SqlCommand("SELECT dbo.func_getNetOfVatInDiscountedItems(@Branch, @OrderNo), dbo.func_getNetOfVatInNonDiscountedItems(@Branch, @OrderNo)", ctx.Con))
                {
                    cmd.Parameters.Add("@Branch", SqlDbType.VarChar, 10).Value = ctx.Branch;
                    cmd.Parameters.Add("@OrderNo", SqlDbType.VarChar, 20).Value = s.RefNo;
                    using (var r = cmd.ExecuteReader())
                    {
                        string a = "0", b = "0";
                        if (r.Read())
                        {
                            a = r[0] == DBNull.Value ? "0" : Convert.ToString(r[0], CultureInfo.InvariantCulture);
                            b = r[1] == DBNull.Value ? "0" : Convert.ToString(r[1], CultureInfo.InvariantCulture);
                        }
                        nov = Tuple.Create(a, b);
                    }
                }
                ctx.NetOfVat[s.RefNo] = nov;
            }
            double netofvatindiscitems = Convert.ToDouble(nov.Item1, CultureInfo.InvariantCulture);
            double netofnonscdisc = Convert.ToDouble(nov.Item2, CultureInfo.InvariantCulture);

            var d = new StringBuilder();
            d.Append("" + (Char)27 + (Char)112 + (Char)0 + (Char)25 + "");
            d.Append(header);
            d.Append(ReceiptSetup.doTitle("SALES INVOICE"));
            d.Append(HeaderDetails(s, cashier));
            d.Append(HelperFunction.createDottedLine() + Environment.NewLine);

            double totalvatitems = 0.0;
            foreach (DataRow line in s.Lines.Rows)
            {
                string addV = "";
                if (Convert.ToBoolean(line["isVat"]))
                {
                    addV = "V";
                    totalvatitems += Num(line["Amount"]);
                }
                double lineDisc = Num(line["Discount"]);
                string addD = lineDisc > 0 ? "  - (Less: Discount)" : "";

                d.Append(HelperFunction.PrintLeftText(line["Particulars"].ToString()) + Environment.NewLine);
                string a = "  - " + line["Qty"] + " @ " + line["UnitPrice"];
                double cleanbalance = Num(line["Amount"]) + lineDisc;
                string b = " " + HelperFunction.convertToNumericFormat(cleanbalance) + addV;
                d.Append(HelperFunction.PrintLeftRigthText(a, b) + Environment.NewLine);
                if (lineDisc > 0)
                    d.Append(HelperFunction.PrintLeftRigthText(addD, "(" + line["Discount"].ToString() + ")") + Environment.NewLine);

                if (disctype == "REGULAR" || IsDiscountableProduct(ctx, line["Particulars"].ToString()))
                    d.Append(HelperFunction.PrintLeftText("  - (Less: Discount " + discpercent.ToString() + "%)") + Environment.NewLine);
            }
            d.Append(HelperFunction.PrinttoRight("----------") + Environment.NewLine);
            if (s.LinesDiscount > 0)
                d.Append(HelperFunction.PrintLeftRigthText("TOTAL DISCOUNT:", peritemdiscount) + Environment.NewLine);
            d.Append(HelperFunction.PrintLeftRigthText("TOTAL DUE:", total) + Environment.NewLine);
            d.Append(HelperFunction.PrinttoRight("==========") + Environment.NewLine);

            double lessvat = 0.0, netofvat = 0.0, lessscdisc = 0.0, netofscdisc = 0.0, addvat = 0.0, totaltotal = 0.0;

            // SENIOR / PWD / NAAC / SOLOPARENT / MOV share one block (only labels differ).
            string title = null, idLabel = null, lessLabel = null, netLabel = null;
            switch (disctype)
            {
                case "SENIOR":     title = "SENIOR DISCOUNT";      idLabel = "OSCA SC/ID: "; lessLabel = "Less SC Discount:";   netLabel = "Net SC Discount:";   break;
                case "PWD":        title = "PWD DISCOUNT";         idLabel = "PWD ID: ";     lessLabel = "Less PWD Discount:";  netLabel = "Net PWD Discount:";  break;
                case "NAAC":       title = "NAAC DISCOUNT";        idLabel = "NAAC ID: ";    lessLabel = "Less NAAC Discount:"; netLabel = "Net NAAC Discount:"; break;
                case "SOLOPARENT": title = "SOLO PARENT DISCOUNT"; idLabel = "ID: ";         lessLabel = "Less SP Discount:";   netLabel = "Net SP Discount:";   break;
                case "MOV":        title = "MOV DISCOUNT";         idLabel = "ID: ";         lessLabel = "Less MOV Discount:";  netLabel = "Net MOV Discount:";  break;
            }

            if (title != null)
            {
                d.Append(HelperFunction.createDottedLine() + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftText(title) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftText(idLabel + discidno) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftText("Name: " + discname) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("Discount Amount:", HelperFunction.convertToNumericFormat(discamount)) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftText("Signature: _______________") + Environment.NewLine);
                d.Append(HelperFunction.createDottedLine() + Environment.NewLine);

                lessvat = Math.Round(netofvatindiscitems * 0.12, 2);
                netofvat = Math.Round(netofvatindiscitems, 2);
                lessscdisc = Math.Round(netofvat * discountpercentage, 2);
                netofscdisc = Math.Round(netofvat - lessscdisc, 2);
                addvat = Math.Round(netofscdisc * .12, 2);
                totaltotal = Math.Round(netofscdisc + addvat, 2);
                d.Append(HelperFunction.PrintLeftRigthText("Less VAT:", HelperFunction.convertToNumericFormat(lessvat)) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("Net of VAT:", HelperFunction.convertToNumericFormat(netofvat)) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText(lessLabel, HelperFunction.convertToNumericFormat(lessscdisc)) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText(netLabel, HelperFunction.convertToNumericFormat(netofscdisc)) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("Add VAT:", HelperFunction.convertToNumericFormat(addvat)) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("Total:", HelperFunction.convertToNumericFormat(totaltotal)) + Environment.NewLine);
                d.Append(HelperFunction.createDottedLine() + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("AMOUNT DUE:", HelperFunction.convertToNumericFormat(netamountpayable)) + Environment.NewLine + Environment.NewLine);
            }
            else if (disctype == "REGULAR")
            {
                d.Append(HelperFunction.createDottedLine() + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftText("REGULAR DISCOUNT") + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftText("Remarks: " + discremarks) + Environment.NewLine + Environment.NewLine);
                d.Append(HelperFunction.createDottedLine() + Environment.NewLine);

                lessvat = Math.Round(totalvatitems / 1.12 * 0.12, 2);
                netofvat = Math.Round(totalvatitems / 1.12, 2);
                lessscdisc = Math.Round(netofvat * discountpercentage, 2);
                netofscdisc = Math.Round(netofvat - lessscdisc, 2);
                addvat = Math.Round(netofscdisc * .12, 2);
                totaltotal = Math.Round(netofscdisc + addvat, 2);
                d.Append(HelperFunction.PrintLeftRigthText("Less VAT:", HelperFunction.convertToNumericFormat(lessvat)) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("Net of VAT:", HelperFunction.convertToNumericFormat(netofvat)) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("Less Reg Discount:", HelperFunction.convertToNumericFormat(lessscdisc)) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("Net Reg Discount:", HelperFunction.convertToNumericFormat(netofscdisc)) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("Add VAT:", HelperFunction.convertToNumericFormat(addvat)) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("Total:", HelperFunction.convertToNumericFormat(totaltotal)) + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("AMOUNT DUE:", HelperFunction.convertToNumericFormat(s.LinesAmount - discamount)) + Environment.NewLine + Environment.NewLine);
            }

            if (paytype == "Credit")
            {
                d.Append(HelperFunction.PrintLeftRigthText("TENDERED:", HelperFunction.convertToNumericFormat(netamountpayable)) + Environment.NewLine + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftRigthText("CHANGE  :", "0.00") + Environment.NewLine + Environment.NewLine);
            }
            d.Append(HelperFunction.PrintLeftRigthText("TENDERED:", cash) + Environment.NewLine);
            d.Append(HelperFunction.PrintLeftRigthText("CHANGE  :", HelperFunction.convertToNumericFormat((double)s.Tendered - netamountpayable)) + Environment.NewLine + Environment.NewLine);

            double totalvatableSales = netofscdisc + netofnonscdisc;
            double totalVatInputSale = totalvatableSales * 0.12;
            d.Append(HelperFunction.PrintLeftRigthText("VATable Sales", HelperFunction.convertToNumericFormat(totalvatableSales)) + Environment.NewLine);
            d.Append(HelperFunction.PrintLeftRigthText("VAT Amount", HelperFunction.convertToNumericFormat(totalVatInputSale)) + Environment.NewLine);
            d.Append(HelperFunction.PrintLeftRigthText("VAT-EXEMPT SALES", vatexemptsale) + Environment.NewLine);
            d.Append(HelperFunction.PrintLeftRigthText("ZERO RATED SALES", "0.00") + Environment.NewLine + Environment.NewLine);
            if (paytype == "Credit")
            {
                // The discount layout prints the card block with blank values (as at checkout).
                d.Append(HelperFunction.createDottedLine() + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftText("PAYMENT TYPE: Credit Card") + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftText("Card Number: XXXX-XXXX-XXXX-") + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftText("Card Type: ") + Environment.NewLine);
                d.Append(HelperFunction.PrintLeftText("Reference No.: ") + Environment.NewLine);
                d.Append(HelperFunction.createDottedLine() + Environment.NewLine);
            }

            d.Append(HelperFunction.PrintCenterText(footer) + Environment.NewLine);
            d.Append(HelperFunction.PrintCenterText(footerlabel));
            d.Append(HelperFunction.LastPagePaper());
            return d.ToString();
        }

        private static bool IsDiscountableProduct(BuildContext ctx, string description)
        {
            bool yes;
            if (ctx.DiscountableProduct.TryGetValue(description, out yes)) return yes;
            using (var cmd = new SqlCommand("SELECT TOP 1 1 FROM dbo.Products WHERE BranchCode = @Branch AND Description = @Description AND isDiscount = 1", ctx.Con))
            {
                cmd.Parameters.Add("@Branch", SqlDbType.VarChar, 10).Value = ctx.Branch;
                cmd.Parameters.Add("@Description", SqlDbType.VarChar, 250).Value = description;
                yes = cmd.ExecuteScalar() != null;
            }
            ctx.DiscountableProduct[description] = yes;
            return yes;
        }

        // ================================================================
        // HEADER -- same lines as ReceiptSetup.doHeaderDetails(ordercode, transcode, ...),
        // but with the ORIGINAL sale's cashier, customer no., Tran# and date instead of the
        // current login / checkout statics / DateTime.Now.
        // ================================================================
        private static string HeaderDetails(Sale s, string cashierName)
        {
            string details = "";
            string cashier = "CASHIER : " + cashierName;
            string custno = "CUST #: " + s.CustomerNo;
            details += HelperFunction.PrintLeftRigthText(cashier, custno) + Environment.NewLine;
            details += HelperFunction.PrintLeftText("SI No.: " + s.RefNo) + Environment.NewLine;
            details += HelperFunction.PrintLeftText("Tran#: " + s.TransNo) + Environment.NewLine;

            // Customer details typed at checkout are never saved -> blank lines, as printed
            // whenever nothing was typed.
            string blank = "__________________";
            DateTime dt = s.PaidAt ?? s.TransDate;
            string format = "dd-MMM-yyyy ddd hh:mm:ss tt";
            details += HelperFunction.PrintLeftText("Date:" + dt.ToString(format)) + Environment.NewLine + Environment.NewLine;
            details += HelperFunction.PrintLeftText("NAME : " + blank) + Environment.NewLine;
            details += HelperFunction.PrintLeftText("ADDRESS : " + blank) + Environment.NewLine;
            details += HelperFunction.PrintLeftText("TIN: " + blank) + Environment.NewLine;
            details += HelperFunction.PrintLeftText("Business Style : " + blank) + Environment.NewLine + Environment.NewLine;
            return details;
        }

        // ================================================================
        // HELPERS
        // ================================================================
        private static void AddScope(SqlCommand cmd, string branch, string machine, DateTime day)
        {
            cmd.Parameters.Add("@Branch", SqlDbType.VarChar, 10).Value = branch;
            cmd.Parameters.Add("@Machine", SqlDbType.VarChar, 50).Value = machine;
            cmd.Parameters.Add("@Day", SqlDbType.Date).Value = day;
        }

        // Parses the FORMAT(..., 'N', 'en-us') text columns.
        private static double Num(object value) =>
            value == null || value == DBNull.Value ? 0 : Convert.ToDouble(value.ToString(), EnUs);

        private static double SumLines(Sale s, string col)
        {
            double total = 0.0;
            foreach (DataRow r in s.Lines.Rows)
                total += Num(r[col]);
            return total;
        }

        // Same "{0:n2}" formatting POSConfirmPayment/PointOfSale apply before printing.
        private static string N2(double value) => String.Format("{0:n2}", value);

        private static string ReadFooter(List<string> warnings)
        {
            string path = Path.Combine(Application.StartupPath, "FOOTER.txt");
            if (File.Exists(path)) return File.ReadAllText(path);
            warnings.Add("FOOTER.txt not found in " + Application.StartupPath + " -- invoices generated without the footer text.");
            return "";
        }

        private static string SafeName(string s)
        {
            if (string.IsNullOrEmpty(s)) return "_";
            foreach (char c in Path.GetInvalidFileNameChars()) s = s.Replace(c, '_');
            return s.Trim();
        }

        private static void WriteLog(Result result, string branch, string machine, DateTime day, int saleCount)
        {
            var log = new StringBuilder();
            log.AppendLine("Z-Read invoice regeneration");
            log.AppendLine("Generated : " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture));
            log.AppendLine("Branch    : " + branch);
            log.AppendLine("Machine   : " + machine);
            log.AppendLine("Z-Read    : " + day.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture));
            log.AppendLine("Sold sales: " + saleCount + "  |  invoices written: " + result.Invoices + "  |  files: " + result.Files);
            log.AppendLine();
            log.AppendLine(result.Warnings.Count == 0 ? "No warnings." : "Warnings:");
            foreach (string w in result.Warnings) log.AppendLine(" - " + w);
            File.WriteAllText(Path.Combine(result.Folder, "GenerationLog.txt"), log.ToString());
        }
    }
}
