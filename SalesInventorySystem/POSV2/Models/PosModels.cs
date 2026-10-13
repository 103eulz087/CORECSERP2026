using System;
using System.Collections.Generic;
using System.Linq;

namespace SalesInventorySystem.POSV2.Models
{
    // A product as the terminal knows it (downloaded copy of the branch's Products row).
    public sealed class PosProduct
    {
        public string ProductCode { get; set; }
        public string Description { get; set; }
        public string Barcode { get; set; }
        public decimal SellingPrice { get; set; }
        public decimal Price1 { get; set; }
        public decimal Price2 { get; set; }
        public decimal Price3 { get; set; }
        public decimal Price4 { get; set; }
        public bool IsVat { get; set; }
    }

    // One line of the sale on screen (bound to the grid).
    public sealed class PosCartLine
    {
        public int LineNo { get; set; }
        public string ProductCode { get; set; }
        public string Barcode { get; set; }
        public string Description { get; set; }
        public decimal Qty { get; set; }
        public string PriceLevel { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal LineDiscount { get; set; }
        public decimal LineTotal { get; set; }
        public bool IsVat { get; set; }               // taxed in this sale (a senior / PWD VAT-exempt line is false)
        public decimal VatAmount { get; set; }
        // phase 2: discounts
        public bool IsVatItem { get; set; }           // the product's own VAT flag
        public int? DiscNo { get; set; }
        public string DiscountCode { get; set; }
        public decimal DiscountAmount { get; set; }   // the discount proper (e.g. 20%)
        public decimal VatExemptAmount { get; set; }  // VAT removed for a VAT-exempt discount
    }

    // A discount type as configured on the server (POSV2_DiscountType).
    public sealed class PosDiscountType
    {
        public string DiscountCode { get; set; }
        public string Name { get; set; }
        public string Kind { get; set; }              // PCT (fixed rate) / PCT_OPEN (cashier types the rate) / AMOUNT
        public decimal Percent { get; set; }
        public bool VatExempt { get; set; }
        public bool RequiresID { get; set; }
        public bool RequiresApproval { get; set; }    // phase 3: a supervisor's PIN
        public override string ToString() => Name;
    }

    // One discount given on a sale; its lines point to it by DiscNo.
    public sealed class PosSaleDiscount
    {
        public int DiscNo { get; set; }
        public string DiscountCode { get; set; }
        public string Name { get; set; }
        public decimal Percent { get; set; }
        public decimal Amount { get; set; }           // sum of its lines' DiscountAmount
        public decimal VatExemptAmount { get; set; }  // sum of its lines' VatExemptAmount
        public string CustomerName { get; set; }
        public string IDNo { get; set; }
        public string TIN { get; set; }
        public string Remarks { get; set; }
    }

    // A sale shown in the void / reprint pickers.
    public sealed class PosSaleSummary
    {
        public Guid SaleGuid { get; set; }
        public string ORNo { get; set; }
        public DateTime SaleDateTime { get; set; }
        public decimal NetAmount { get; set; }
        public string Status { get; set; }            // PAID / VOIDED
        public string SyncStatus { get; set; }
        public string CashierUserID { get; set; }
    }

    // A held (parked) sale, kept on the terminal only.
    public sealed class PosHeldSale
    {
        public int HoldID { get; set; }
        public string Name { get; set; }
        public DateTime CreatedAt { get; set; }
        public int Lines { get; set; }
        public decimal Total { get; set; }
    }

    public sealed class PosPayment
    {
        public int PayNo { get; set; }
        public string PaymentType { get; set; }
        public decimal Amount { get; set; }
        public string Reference { get; set; }
    }

    // A whole sale: what is saved locally in one transaction and posted to the server as one call.
    public sealed class PosSale
    {
        public Guid SaleGuid { get; set; }
        public string ORNo { get; set; }                 // assigned by the local store when saved
        public DateTime SaleDateTime { get; set; }
        public string CashierUserID { get; set; }
        public string CashierName { get; set; }
        public string CustomerKey { get; set; }
        public decimal GrossAmount { get; set; }
        public decimal DiscountAmount { get; set; }
        public decimal NetAmount { get; set; }
        public decimal VatableSales { get; set; }
        public decimal VatAmount { get; set; }
        public decimal VatExemptSales { get; set; }
        public decimal ZeroRatedSales { get; set; }
        public decimal AmountTendered { get; set; }
        public decimal ChangeAmount { get; set; }
        public bool WasOffline { get; set; }
        public DateTime SavedAt { get; set; }
        public int CancelledLineCount { get; set; }        // phase 2: lines removed before payment
        public decimal CancelledLineAmount { get; set; }
        public string Status { get; set; }                 // local: PAID / VOIDED
        public DateTime? VoidedAt { get; set; }
        public string VoidReason { get; set; }
        public string VoidedBy { get; set; }
        public Guid ShiftGuid { get; set; }                // phase 3: every sale belongs to a shift
        public string DiscountApprovedBy { get; set; }     // phase 3: supervisor for a discount that needs approval
        public string VoidApprovedBy { get; set; }
        public string CreditApprovedBy { get; set; }       // phase 4: supervisor for a charge over the credit limit
        public string CustomerName { get; set; }           // phase 4: the charge customer (printed)
        public List<PosCartLine> Lines { get; } = new List<PosCartLine>();
        public List<PosPayment> Payments { get; } = new List<PosPayment>();
        public List<PosSaleDiscount> Discounts { get; } = new List<PosSaleDiscount>();
    }

    // What the terminal registered as on the server.
    public sealed class PosTerminalInfo
    {
        public int TerminalID { get; set; }
        public string BranchCode { get; set; }
        public string TerminalCode { get; set; }
        public string ORPrefix { get; set; }
        public long NextORSeq { get; set; }
        public int NextZNo { get; set; }          // phase 3: the Z-reading counter
        public long NextReturnSeq { get; set; }   // phase 4: the return slip series <prefix>-R<seq>
    }

    // phase 4: a customer who can buy on account (downloaded copy; balance as of the last download).
    public sealed class PosCustomer
    {
        public string CustomerKey { get; set; }
        public string CustomerName { get; set; }
        public string BranchCode { get; set; }
        public decimal CreditLimit { get; set; }
        public decimal Balance { get; set; }
        public string Display => CustomerKey + " - " + CustomerName;            // Code - Name
        public override string ToString() => Display;
    }

    // phase 4: a sale as the return screen needs it: its lines with what earlier returns already took back.
    public sealed class PosReturnSource
    {
        public Guid SaleGuid { get; set; }
        public string ORNo { get; set; }
        public DateTime SaleDateTime { get; set; }
        public string Status { get; set; }            // PAID / POSTED / VOIDED
        public string CustomerKey { get; set; }
        public string CustomerName { get; set; }
        public decimal? ChargeBalance { get; set; }   // open balance of the charge invoice (server only)
        public bool FromServer { get; set; }
        public decimal PaidCash { get; set; }         // cash received less change
        public decimal PaidCard { get; set; }
        public decimal PaidCharge { get; set; }
        public decimal RefundedCash { get; set; }
        public decimal RefundedCard { get; set; }
        public decimal RefundedCharge { get; set; }
        public List<PosReturnSourceLine> Lines { get; } = new List<PosReturnSourceLine>();
    }

    public sealed class PosReturnSourceLine
    {
        public int LineNo { get; set; }
        public string ProductCode { get; set; }
        public string Description { get; set; }
        public decimal Qty { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal Gross { get; set; }            // ROUND(Qty x UnitPrice, 2)
        public decimal DiscountAmount { get; set; }
        public decimal VatExemptAmount { get; set; }
        public decimal LineTotal { get; set; }
        public decimal VatAmount { get; set; }
        public bool IsVat { get; set; }
        public decimal ReturnedQty { get; set; }
        public decimal ReturnedGross { get; set; }
        public decimal ReturnedDiscount { get; set; }
        public decimal ReturnedVatExempt { get; set; }
        public decimal ReturnedNet { get; set; }
        public decimal ReturnedVat { get; set; }
        public decimal Returnable => Qty - ReturnedQty;
        public decimal ReturnQty { get; set; }        // typed on the return screen
    }

    // phase 4: a return / refund slip.
    public sealed class PosReturn
    {
        public Guid ReturnGuid { get; set; }
        public string ReturnNo { get; set; }          // assigned by the local store when saved
        public Guid ShiftGuid { get; set; }
        public Guid OrigSaleGuid { get; set; }
        public string OrigORNo { get; set; }
        public DateTime ReturnDateTime { get; set; }
        public string CashierUserID { get; set; }
        public string CashierName { get; set; }
        public string ApprovedBy { get; set; }
        public string Reason { get; set; }
        public string CustomerKey { get; set; }
        public string CustomerName { get; set; }
        public decimal CashRefund { get; set; }
        public decimal CardRefund { get; set; }
        public decimal ChargeRefund { get; set; }
        public DateTime SavedAt { get; set; }
        public List<PosReturnLine> Lines { get; } = new List<PosReturnLine>();
        public decimal GrossAmount => Lines.Sum(l => l.GrossAmount);
        public decimal DiscountAmount => Lines.Sum(l => l.DiscountAmount + l.VatExemptAmount);
        public decimal NetAmount => Lines.Sum(l => l.NetAmount);
        public decimal VatAmount => Lines.Sum(l => l.VatAmount);
    }

    public sealed class PosReturnLine
    {
        public int LineNo { get; set; }
        public int OrigLineNo { get; set; }
        public string ProductCode { get; set; }
        public string Description { get; set; }
        public decimal Qty { get; set; }
        public decimal GrossAmount { get; set; }
        public decimal DiscountAmount { get; set; }
        public decimal VatExemptAmount { get; set; }
        public decimal NetAmount { get; set; }
        public decimal VatAmount { get; set; }
    }

    // phase 3: a cashier shift on this terminal (opened with the beginning cash, closed by the Z-reading).
    public sealed class PosShift
    {
        public Guid ShiftGuid { get; set; }
        public int ZNo { get; set; }
        public string CashierUserID { get; set; }
        public string CashierName { get; set; }
        public DateTime OpenedAt { get; set; }
        public decimal BeginningCash { get; set; }
        public string Status { get; set; }        // OPEN / CLOSED
        public DateTime? ClosedAt { get; set; }
        public decimal? CountedCash { get; set; }
        public string ClosedBy { get; set; }
        public string CloseApprovedBy { get; set; }
        public decimal? AccumulatedBefore { get; set; }   // phase 5 (BIR): grand total before / after this Z-reading
        public decimal? AccumulatedAfter { get; set; }
    }

    // phase 3: the X / Z reading of a shift, computed from this terminal's own sales.
    public sealed class PosShiftReading
    {
        public PosShift Shift { get; set; }
        public int SaleCount { get; set; }        // every OR, voided included
        public int VoidCount { get; set; }
        public decimal VoidAmount { get; set; }
        public decimal GrossAmount { get; set; }  // the amounts below: sales not voided
        public decimal DiscountAmount { get; set; }
        public decimal VatExemptAmount { get; set; }
        public decimal NetAmount { get; set; }
        public decimal VatableSales { get; set; }
        public decimal VatAmount { get; set; }
        public decimal VatExemptSales { get; set; }
        public decimal ZeroRatedSales { get; set; }
        public decimal CashSales { get; set; }    // cash received less change
        public decimal CardSales { get; set; }    // phase 4
        public decimal ChargeSales { get; set; }
        public int ReturnCount { get; set; }      // phase 4: returns paid back in this shift
        public decimal ReturnGross { get; set; }
        public decimal ReturnDiscount { get; set; }
        public decimal ReturnNet { get; set; }
        public decimal CashRefunds { get; set; }
        public decimal CardRefunds { get; set; }
        public decimal ChargeRefunds { get; set; }
        public int CancelledLineCount { get; set; }
        public decimal CancelledLineAmount { get; set; }
        public int ClearedSaleCount { get; set; }
        public decimal ClearedSaleAmount { get; set; }
        public int ClearedLineCount { get; set; }      // lines removed (Del) from sales that were then cleared
        public decimal ClearedLineAmount { get; set; }
        public int DrawerOpenCount { get; set; }
        public int ReprintCount { get; set; }
        public string FirstORNo { get; set; }
        public string LastORNo { get; set; }
        public List<Tuple<string, int, decimal>> DiscountsByType { get; } = new List<Tuple<string, int, decimal>>();   // code, sales, amount (incl. VAT exemption)
        public decimal ExpectedCash => (Shift == null ? 0m : Shift.BeginningCash) + CashSales - CashRefunds;
    }

    // phase 3: a supervisor who may approve on this terminal (downloaded hash, never the PIN).
    public sealed class PosSupervisor
    {
        public string UserID { get; set; }
        public string FullName { get; set; }
        public byte[] PinHash { get; set; }
        public byte[] PinSalt { get; set; }
        public int PinIterations { get; set; }
    }

    public sealed class PosSyncStatus
    {
        public bool Online { get; set; }
        public bool Registered { get; set; }
        public int Pending { get; set; }          // saved, not yet on the server
        public int Failed { get; set; }           // refused by the server: needs attention
        public DateTime? LastPostedAt { get; set; }
        public DateTime? ProductsRefreshedAt { get; set; }
        public string Message { get; set; }
    }
}
