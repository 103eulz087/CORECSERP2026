using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Printing;
using SalesInventorySystem.POSV2.Models;

namespace SalesInventorySystem.POSV2.Devices
{
    // Prints a sale as a plain-text receipt (fixed-width font, 40 characters a line: about 66 mm of text, fits an 80 mm roll;
    // a 58 mm roll needs a smaller font)
    // on PosV2Config.ReceiptPrinter, or the Windows default printer when that is blank.
    // Phase 1 layout; the BIR header and footer (TIN, MIN, accreditation, serial no.) come in phase 5.
    // phase 5: the terminal's BIR registration (its POSInfoDetails row, downloaded at registration), printed on every slip.
    public sealed class PosBirInfo
    {
        public string BusinessName, BusinessAddress, TIN, MIN, SerialNo, AccreditationNo, DateIssued, PermitNumber, PermitStart, PermitEnd;
        public bool Registered => !string.IsNullOrWhiteSpace(TIN);
        public string Doc => Registered ? "SI" : "OR";   // sales invoice (BIR-registered) or receipt: one term per mode
    }

    public static class PosReceiptPrinter
    {
        private const int Width = 40;

        // Set by the terminal from its local copy (blank until the server links this machine to its BIR registration).
        public static PosBirInfo Bir { get; set; } = new PosBirInfo();

        // Business name, address, VAT REG TIN, MIN and serial no. (BIR); the branch name until the machine is linked.
        private static void Header(List<string> t, string branchName)
        {
            var b = Bir ?? new PosBirInfo();
            t.Add(Center(!string.IsNullOrWhiteSpace(b.BusinessName) ? b.BusinessName : (string.IsNullOrWhiteSpace(branchName) ? "BRANCH" : branchName)));
            foreach (var line in Wrap(b.BusinessAddress)) t.Add(Center(line));
            if (b.Registered)
            {
                t.Add(Center("VAT REG TIN: " + b.TIN));
                if (!string.IsNullOrWhiteSpace(b.MIN)) t.Add(Center("MIN: " + b.MIN));
                if (!string.IsNullOrWhiteSpace(b.SerialNo)) t.Add(Center("SN: " + b.SerialNo));
            }
        }

        // The accreditation and permit to use (BIR); a note when the machine isn't linked to its registration yet.
        private static void Footer(List<string> t)
        {
            var b = Bir ?? new PosBirInfo();
            if (t.Count == 0 || t[t.Count - 1] != new string('-', Width)) t.Add(new string('-', Width));
            if (!b.Registered) return;   // nothing on a customer slip; the cashier sees the link status on screen
            if (!string.IsNullOrWhiteSpace(b.AccreditationNo)) t.Add("Accreditation: " + Cut(b.AccreditationNo, Width - 15));
            if (!string.IsNullOrWhiteSpace(b.DateIssued)) t.Add("Date issued  : " + b.DateIssued);
            if (!string.IsNullOrWhiteSpace(b.PermitNumber)) { t.Add("PTU No.:"); t.Add("  " + Cut(b.PermitNumber, Width - 2)); }
            if (!string.IsNullOrWhiteSpace(b.PermitStart) || !string.IsNullOrWhiteSpace(b.PermitEnd))
                t.Add("Valid " + (b.PermitStart ?? "") + " to " + (b.PermitEnd ?? ""));
        }

        private static IEnumerable<string> Wrap(string s)
        {
            if (string.IsNullOrWhiteSpace(s)) yield break;
            var line = "";
            foreach (var w in s.Trim().Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries))
            {
                if (line.Length > 0 && line.Length + 1 + w.Length > Width) { yield return line; line = ""; }
                line = line.Length == 0 ? Cut(w, Width) : line + " " + w;
            }
            if (line.Length > 0) yield return line;
        }

        public static List<string> Format(PosSale s, string branchName, string terminalCode, bool reprint)
        {
            var t = new List<string>();
            bool voided = s.Status == "VOIDED";
            Header(t, branchName);
            t.Add(Center((voided ? "*** VOIDED *** " : "") + (Bir.Registered ? "SALES INVOICE" : "SALES RECEIPT") + (reprint ? " - REPRINT" : "")));
            t.Add(new string('-', Width));
            t.Add((Bir.Registered ? "SI No.  : " : "OR No.  : ") + s.ORNo);
            t.Add("Date    : " + s.SaleDateTime.ToString("yyyy-MM-dd HH:mm"));
            t.Add("Cashier : " + Cut(s.CashierName ?? s.CashierUserID, Width - 10));
            t.Add("Terminal: " + terminalCode);
            t.Add(new string('-', Width));
            foreach (var l in s.Lines)
            {
                t.Add(Cut(l.Description ?? l.ProductCode, Width));
                t.Add(LeftRight("  " + l.Qty.ToString("0.###") + " x " + l.UnitPrice.ToString("N2") + (l.IsVat ? "" : " (VAT-EX)"),
                                (l.Qty * l.UnitPrice).ToString("N2")));
                if (l.VatExemptAmount > 0) t.Add(LeftRight("    less VAT exemption", "-" + l.VatExemptAmount.ToString("N2")));
                if (l.DiscountAmount > 0) t.Add(LeftRight("    less " + (l.DiscountCode ?? "discount"), "-" + l.DiscountAmount.ToString("N2")));
            }
            t.Add(new string('-', Width));
            if (s.DiscountAmount > 0) t.Add(LeftRight("Gross", s.GrossAmount.ToString("N2")));
            foreach (var d in s.Discounts)
            {
                // short label so it never gets cut: "Less SC20 (20%)", "Less ONETIME"
                t.Add(LeftRight("Less " + d.DiscountCode + (d.Percent > 0 ? " (" + d.Percent.ToString("0.##") + "%)" : ""), "-" + d.Amount.ToString("N2")));
                if (d.VatExemptAmount > 0) t.Add(LeftRight("Less VAT exemption", "-" + d.VatExemptAmount.ToString("N2")));
                if (!string.IsNullOrWhiteSpace(d.CustomerName)) t.Add("  Name : " + Cut(d.CustomerName, Width - 9));
                if (!string.IsNullOrWhiteSpace(d.IDNo)) t.Add("  ID No: " + Cut(d.IDNo, Width - 9));
                if (!string.IsNullOrWhiteSpace(d.TIN)) t.Add("  TIN  : " + Cut(d.TIN, Width - 9));
            }
            t.Add(LeftRight("TOTAL", s.NetAmount.ToString("N2")));
            foreach (var p in s.Payments)
            {
                t.Add(LeftRight(p.PaymentType == "CHARGE" ? "CHARGE TO ACCOUNT" : p.PaymentType, p.Amount.ToString("N2")));
                if (p.PaymentType == "CARD" && !string.IsNullOrWhiteSpace(p.Reference)) t.Add("  " + Cut(p.Reference, Width - 2));
            }
            t.Add(LeftRight("CHANGE", s.ChangeAmount.ToString("N2")));
            if (s.Payments.Exists(p => p.PaymentType == "CHARGE"))
            {
                t.Add("Charged to: " + Cut(s.CustomerKey + " " + (s.CustomerName ?? ""), Width - 12));
                t.Add("Customer signature:");
                t.Add("");
                t.Add("________________________________");
            }
            t.Add(new string('-', Width));
            t.Add(LeftRight("VATable Sales", s.VatableSales.ToString("N2")));
            t.Add(LeftRight("VAT Amount (12%)", s.VatAmount.ToString("N2")));
            t.Add(LeftRight("VAT-Exempt Sales", s.VatExemptSales.ToString("N2")));
            t.Add(LeftRight("Zero-Rated Sales", s.ZeroRatedSales.ToString("N2")));
            if (s.Discounts.Exists(d => d.VatExemptAmount > 0 || !string.IsNullOrWhiteSpace(d.IDNo)))
            {
                t.Add(new string('-', Width));
                t.Add("Customer signature:");
                t.Add("");
                t.Add("________________________________");
            }
            if (voided)
            {
                t.Add(new string('-', Width));
                t.Add("VOIDED " + (s.VoidedAt.HasValue ? s.VoidedAt.Value.ToString("yyyy-MM-dd HH:mm") : "") + " by " + (s.VoidedBy ?? ""));
                t.Add("Reason: " + Cut(s.VoidReason, Width - 8));
                if (!string.IsNullOrEmpty(s.VoidApprovedBy)) t.Add("Approved by: " + Cut(s.VoidApprovedBy, Width - 13));
            }
            t.Add(new string('-', Width));
            Footer(t);
            t.Add(Center("Thank you!"));
            return t;
        }

        // phase 3: the X-reading (shift so far, nothing closes) or the Z-reading (the close, with the cash count).
        public static List<string> FormatReading(PosShiftReading rd, string branchName, string terminalCode, bool isZ, bool reprint)
        {
            var sh = rd.Shift;
            var t = new List<string>();
            Header(t, branchName);
            t.Add(Center((isZ ? "Z-READING (SHIFT CLOSE)" : "X-READING") + (reprint ? " - REPRINT" : "")));
            t.Add(new string('-', Width));
            t.Add("Z No.   : " + sh.ZNo);
            t.Add("Terminal: " + terminalCode);
            t.Add("Cashier : " + Cut(sh.CashierName ?? sh.CashierUserID, Width - 10));
            t.Add("Opened  : " + sh.OpenedAt.ToString("yyyy-MM-dd HH:mm"));
            if (isZ && sh.ClosedAt.HasValue) t.Add(Cut("Closed  : " + sh.ClosedAt.Value.ToString("yyyy-MM-dd HH:mm") + (string.IsNullOrEmpty(sh.ClosedBy) || sh.ClosedBy == sh.CashierUserID ? "" : " by " + sh.ClosedBy), Width));
            if (!string.IsNullOrEmpty(sh.CloseApprovedBy)) t.Add("Approved: " + Cut(sh.CloseApprovedBy, Width - 10));
            if (!isZ) t.Add("Printed : " + DateTime.Now.ToString("yyyy-MM-dd HH:mm"));
            t.Add(Bir.Doc + " from : " + (rd.FirstORNo ?? "-"));
            t.Add(Bir.Doc + " to   : " + (rd.LastORNo ?? "-"));
            t.Add(new string('-', Width));
            t.Add(LeftRight("Sales (" + Bir.Doc + "s issued)", rd.SaleCount.ToString()));
            t.Add(LeftRight("Gross sales", rd.GrossAmount.ToString("N2")));
            t.Add(LeftRight("Less discounts", Neg(rd.DiscountAmount)));
            t.Add(LeftRight("Less VAT exemption", Neg(rd.VatExemptAmount)));
            t.Add(LeftRight("NET SALES", rd.NetAmount.ToString("N2")));
            t.Add(LeftRight("  cash", rd.CashSales.ToString("N2")));
            t.Add(LeftRight("  card", rd.CardSales.ToString("N2")));
            t.Add(LeftRight("  charge to account", rd.ChargeSales.ToString("N2")));
            foreach (var d in rd.DiscountsByType)
                t.Add(LeftRight("  " + d.Item1 + " (" + d.Item2 + ")", d.Item3.ToString("N2")));
            t.Add(new string('-', Width));
            t.Add(LeftRight("VATable Sales", rd.VatableSales.ToString("N2")));
            t.Add(LeftRight("VAT Amount (12%)", rd.VatAmount.ToString("N2")));
            t.Add(LeftRight("VAT-Exempt Sales", rd.VatExemptSales.ToString("N2")));
            t.Add(LeftRight("Zero-Rated Sales", rd.ZeroRatedSales.ToString("N2")));
            t.Add(new string('-', Width));
            t.Add(LeftRight("Voided sales (" + rd.VoidCount + ")", rd.VoidAmount.ToString("N2")));
            t.Add(LeftRight("Lines removed (" + (rd.CancelledLineCount + rd.ClearedLineCount) + ")", (rd.CancelledLineAmount + rd.ClearedLineAmount).ToString("N2")));
            t.Add(LeftRight("Sales cleared (" + rd.ClearedSaleCount + ")", rd.ClearedSaleAmount.ToString("N2")));
            t.Add(LeftRight("No-sale drawer opens", rd.DrawerOpenCount.ToString()));
            t.Add(LeftRight("Receipt reprints", rd.ReprintCount.ToString()));
            t.Add(new string('-', Width));
            t.Add(LeftRight("Returns (" + rd.ReturnCount + ")", rd.ReturnNet.ToString("N2")));
            t.Add(LeftRight("  refunded cash", rd.CashRefunds.ToString("N2")));
            t.Add(LeftRight("  refunded card", rd.CardRefunds.ToString("N2")));
            t.Add(LeftRight("  credited to accounts", rd.ChargeRefunds.ToString("N2")));
            t.Add(new string('-', Width));
            if (isZ && sh.AccumulatedAfter.HasValue)
            {
                t.Add(LeftRight("Z counter", sh.ZNo.ToString()));
                t.Add(LeftRight("Reset counter", "0"));   // the grand total never resets (counters only move up, also after a reinstall)
                t.Add(LeftRight("Accumulated sales before", (sh.AccumulatedBefore ?? 0m).ToString("N2")));
                t.Add(LeftRight("Accumulated sales after", sh.AccumulatedAfter.Value.ToString("N2")));
                t.Add(new string('-', Width));
            }
            t.Add(LeftRight("Beginning cash", sh.BeginningCash.ToString("N2")));
            t.Add(LeftRight("Cash sales", rd.CashSales.ToString("N2")));
            t.Add(LeftRight("Less cash refunds", Neg(rd.CashRefunds)));
            t.Add(LeftRight("EXPECTED CASH", rd.ExpectedCash.ToString("N2")));
            if (isZ && sh.CountedCash.HasValue)
            {
                decimal os = sh.CountedCash.Value - rd.ExpectedCash;
                t.Add(LeftRight("CASH COUNTED", sh.CountedCash.Value.ToString("N2")));
                t.Add(LeftRight(os < 0 ? "SHORT" : (os > 0 ? "OVER" : "OVER / SHORT"), Math.Abs(os).ToString("N2")));
                t.Add(new string('-', Width));
                t.Add("Cashier:");
                t.Add("");
                t.Add("________________________________");
                t.Add("Supervisor:");
                t.Add("");
                t.Add("________________________________");
            }
            if (isZ) Footer(t);
            t.Add(new string('-', Width));
            return t;
        }

        // phase 4: the return / refund slip (customer copy; the customer signs when cash goes back).
        public static List<string> FormatReturn(PosReturn r, string branchName, string terminalCode, bool reprint)
        {
            var t = new List<string>();
            Header(t, branchName);
            t.Add(Center("RETURN / REFUND SLIP" + (reprint ? " - REPRINT" : "")));
            t.Add(new string('-', Width));
            t.Add("Return  : " + r.ReturnNo);
            t.Add("Of " + Bir.Doc + "   : " + r.OrigORNo);
            t.Add("Date    : " + r.ReturnDateTime.ToString("yyyy-MM-dd HH:mm"));
            t.Add("Cashier : " + Cut(r.CashierName ?? r.CashierUserID, Width - 10));
            t.Add("Terminal: " + terminalCode);
            t.Add("Approved: " + Cut(r.ApprovedBy, Width - 10));
            t.Add("Reason  : " + Cut(r.Reason, Width - 10));
            if (!string.IsNullOrEmpty(r.CustomerKey)) t.Add("Customer: " + Cut(r.CustomerKey + " " + (r.CustomerName ?? ""), Width - 10));
            t.Add(new string('-', Width));
            foreach (var l in r.Lines)
            {
                t.Add(Cut(l.Description ?? l.ProductCode, Width));
                t.Add(LeftRight("  " + l.Qty.ToString("0.###") + " returned", l.GrossAmount.ToString("N2")));
                if (l.DiscountAmount + l.VatExemptAmount > 0) t.Add(LeftRight("    less discount given", "-" + (l.DiscountAmount + l.VatExemptAmount).ToString("N2")));
            }
            t.Add(new string('-', Width));
            t.Add(LeftRight("TOTAL REFUND", r.NetAmount.ToString("N2")));
            if (r.ChargeRefund > 0) t.Add(LeftRight("  credited to account", r.ChargeRefund.ToString("N2")));
            if (r.CardRefund > 0) t.Add(LeftRight("  refunded to card", r.CardRefund.ToString("N2")));
            if (r.CashRefund > 0) t.Add(LeftRight("  CASH REFUNDED", r.CashRefund.ToString("N2")));
            t.Add(LeftRight("VAT included", r.VatAmount.ToString("N2")));
            Footer(t);
            t.Add(new string('-', Width));
            t.Add("Customer signature:");
            t.Add("");
            t.Add("________________________________");
            t.Add(new string('-', Width));
            return t;
        }

        public static void PrintReturn(PosReturn r, string branchName, string terminalCode, bool reprint) =>
            PrintLines(FormatReturn(r, branchName, terminalCode, reprint), "Return " + r.ReturnNo);

        public static void PrintReading(PosShiftReading rd, string branchName, string terminalCode, bool isZ, bool reprint) =>
            PrintLines(FormatReading(rd, branchName, terminalCode, isZ, reprint), (isZ ? "Z-reading " : "X-reading ") + rd.Shift.ZNo);

        public static void Print(PosSale s, string branchName, string terminalCode, bool reprint) =>
            PrintLines(Format(s, branchName, terminalCode, reprint), "Receipt " + s.ORNo);

        private static void PrintLines(List<string> lines, string documentName)
        {
            using (var doc = new PrintDocument())
            {
                if (!string.IsNullOrWhiteSpace(PosV2Config.ReceiptPrinter)) doc.PrinterSettings.PrinterName = PosV2Config.ReceiptPrinter;
                doc.DocumentName = documentName;
                int next = 0;
                using (var font = new Font("Consolas", 8.5f))
                {
                    doc.PrintPage += (o, e) =>
                    {
                        float y = e.MarginBounds.Top > 20 ? 10 : e.MarginBounds.Top;
                        float lh = font.GetHeight(e.Graphics);
                        while (next < lines.Count)
                        {
                            if (y + lh > e.PageBounds.Height - 10 && next > 0) { e.HasMorePages = true; return; }
                            e.Graphics.DrawString(lines[next++], font, Brushes.Black, 5, y);
                            y += lh;
                        }
                        e.HasMorePages = false;
                    };
                    doc.Print();
                }
            }
        }

        private static string Center(string s)
        {
            s = Cut(s, Width);
            return new string(' ', (Width - s.Length) / 2) + s;
        }

        private static string LeftRight(string left, string right)
        {
            left = Cut(left, Width - right.Length - 1);
            return left + new string(' ', Math.Max(1, Width - left.Length - right.Length)) + right;
        }

        private static string Neg(decimal v) => v == 0 ? "0.00" : "-" + v.ToString("N2");

        private static string Cut(string s, int max) => s == null ? "" : (s.Length <= max ? s : s.Substring(0, max));
    }
}
