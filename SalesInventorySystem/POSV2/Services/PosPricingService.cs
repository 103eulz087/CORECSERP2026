using System;
using System.Collections.Generic;
using System.Linq;
using SalesInventorySystem.POSV2.Models;

namespace SalesInventorySystem.POSV2.Services
{
    // Pure arithmetic for a sale: no UI, no database, so it can be tested on its own. Matches the server's
    // checks in spu_POSV2_PostSale exactly (SQL ROUND is "away from zero", hence MidpointRounding.AwayFromZero).
    // Prices are VAT inclusive: VAT = line total x 12/112; VATable sales = VAT lines' total - VAT.
    //
    // Discounts (phase 2), per line (server errors 61022-61028 if not followed):
    //   gross = ROUND(qty x price, 2)
    //   VAT-exempt type (senior / PWD 20%) on a VAT item:  ex-VAT = ROUND(gross / 1.12, 2), VatExemptAmount = gross - ex-VAT,
    //       DiscountAmount = ROUND(ex-VAT x rate, 2), and the line is no longer taxed (IsVat = false)
    //   any other % (incl. a VAT-exempt type on a VAT-exempt item): DiscountAmount = ROUND(gross x rate, 2)
    //   amount (one-time): spread over the lines by value, the last line takes the rounding remainder
    //   LineDiscount = DiscountAmount + VatExemptAmount;  LineTotal = gross - LineDiscount
    public static class PosPricingService
    {
        public const decimal VatRate = 0.12m;
        public static readonly string[] PriceLevels = { "MAIN", "PRICE1", "PRICE2", "PRICE3", "PRICE4" };

        public static decimal R2(decimal v) => Math.Round(v, 2, MidpointRounding.AwayFromZero);

        public static decimal UnitPrice(PosProduct p, string level)
        {
            switch ((level ?? "MAIN").ToUpperInvariant())
            {
                case "PRICE1": return p.Price1;
                case "PRICE2": return p.Price2;
                case "PRICE3": return p.Price3;
                case "PRICE4": return p.Price4;
                default: return p.SellingPrice;
            }
        }

        public static decimal Gross(PosCartLine l) => R2(l.Qty * l.UnitPrice);

        // Fills LineDiscount, LineTotal, IsVat and VatAmount from Qty, UnitPrice and the line's discount fields.
        public static void PriceLine(PosCartLine l)
        {
            l.LineDiscount = l.DiscountAmount + l.VatExemptAmount;
            l.LineTotal = Gross(l) - l.LineDiscount;
            if (l.LineTotal < 0) l.LineTotal = 0;
            l.IsVat = l.IsVatItem && l.VatExemptAmount == 0m;
            l.VatAmount = l.IsVat ? R2(l.LineTotal * VatRate / (1 + VatRate)) : 0m;
        }

        public static void ClearDiscount(PosCartLine l)
        {
            l.DiscNo = null; l.DiscountCode = null; l.DiscountAmount = 0m; l.VatExemptAmount = 0m;
            PriceLine(l);
        }

        // A percentage discount (rate in %, e.g. 20) on the given lines.
        public static void ApplyPercent(IEnumerable<PosCartLine> lines, PosDiscountType type, decimal ratePct, int discNo)
        {
            foreach (var l in lines)
            {
                decimal gross = Gross(l);
                l.DiscNo = discNo; l.DiscountCode = type.DiscountCode;
                if (type.VatExempt && l.IsVatItem)
                {
                    decimal exVat = R2(gross / (1 + VatRate));
                    l.VatExemptAmount = gross - exVat;
                    l.DiscountAmount = R2(exVat * ratePct / 100m);
                }
                else
                {
                    l.VatExemptAmount = 0m;
                    l.DiscountAmount = R2(gross * ratePct / 100m);
                }
                PriceLine(l);
            }
        }

        // An amount discount spread over the given lines by their value. False when it is more than they're worth.
        public static bool ApplyAmount(IList<PosCartLine> lines, PosDiscountType type, decimal amount, int discNo)
        {
            decimal total = lines.Sum(Gross);
            if (lines.Count == 0 || amount <= 0 || amount > total) return false;
            decimal left = amount;
            for (int i = 0; i < lines.Count; i++)
            {
                var l = lines[i];
                decimal share = i == lines.Count - 1 ? left : R2(amount * Gross(l) / total);
                if (share > Gross(l)) share = Gross(l);
                left -= share;
                l.DiscNo = discNo; l.DiscountCode = type.DiscountCode;
                l.VatExemptAmount = 0m;
                l.DiscountAmount = share;
                PriceLine(l);
            }
            return left == 0m;
        }

        // Fills the sale's totals from its lines, and each discount's amounts from its lines (unused discounts dropped).
        public static void Total(PosSale s)
        {
            s.GrossAmount = s.Lines.Sum(l => Gross(l));
            s.NetAmount = s.Lines.Sum(l => l.LineTotal);
            s.DiscountAmount = s.GrossAmount - s.NetAmount;
            s.VatAmount = s.Lines.Where(l => l.IsVat).Sum(l => l.VatAmount);
            s.VatableSales = s.Lines.Where(l => l.IsVat).Sum(l => l.LineTotal - l.VatAmount);
            s.VatExemptSales = s.Lines.Where(l => !l.IsVat).Sum(l => l.LineTotal);
            s.ZeroRatedSales = 0m;
            foreach (var d in s.Discounts)
            {
                d.Amount = s.Lines.Where(l => l.DiscNo == d.DiscNo).Sum(l => l.DiscountAmount);
                d.VatExemptAmount = s.Lines.Where(l => l.DiscNo == d.DiscNo).Sum(l => l.VatExemptAmount);
            }
            s.Discounts.RemoveAll(d => !s.Lines.Any(l => l.DiscNo == d.DiscNo));
        }

        public static void Renumber(IList<PosCartLine> lines)
        {
            for (int i = 0; i < lines.Count; i++) lines[i].LineNo = i + 1;
        }

        // ── phase 4: returns ───────────────────────────────────────────
        // The returned share of a sale line: ROUND(amount x qty / sold qty, 2) of its gross, discount, VAT exemption and VAT;
        // returning everything still returnable takes exactly what is left (so a line never refunds more than it was paid).
        // Net = gross - discount - VAT exemption (the server checks exactly that).
        public static PosReturnLine ReturnShare(PosReturnSourceLine l, decimal qty, int lineNo)
        {
            bool all = qty >= l.Returnable;
            Func<decimal, decimal, decimal> share = (total, done) => all ? total - done : R2(total * qty / l.Qty);
            var r = new PosReturnLine
            {
                LineNo = lineNo, OrigLineNo = l.LineNo, ProductCode = l.ProductCode, Description = l.Description, Qty = all ? l.Returnable : qty,
                GrossAmount = share(l.Gross, l.ReturnedGross), DiscountAmount = share(l.DiscountAmount, l.ReturnedDiscount),
                VatExemptAmount = share(l.VatExemptAmount, l.ReturnedVatExempt), VatAmount = share(l.VatAmount, l.ReturnedVat)
            };
            r.NetAmount = r.GrossAmount - r.DiscountAmount - r.VatExemptAmount;
            return r;
        }

        // "Same as paid" (user 2026-10-13): back to the customer's account first (no more than was charged, nor than the
        // invoice's open balance when the server told us), then to the card, then cash from the drawer.
        public static void SplitRefund(PosReturn rt, PosReturnSource src)
        {
            decimal left = rt.NetAmount;
            decimal charge = Math.Max(0m, src.PaidCharge - src.RefundedCharge);
            if (src.ChargeBalance.HasValue) charge = Math.Min(charge, Math.Max(0m, src.ChargeBalance.Value));
            rt.ChargeRefund = Math.Min(left, charge); left -= rt.ChargeRefund;
            rt.CardRefund = Math.Min(left, Math.Max(0m, src.PaidCard - src.RefundedCard)); left -= rt.CardRefund;
            rt.CashRefund = left;
        }
    }
}
