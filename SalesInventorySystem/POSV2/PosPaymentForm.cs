using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Linq;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraEditors.Controls;
using SalesInventorySystem.POSV2.Models;

namespace SalesInventorySystem.POSV2
{
    // Payment for POS V2 (phase 4: split payments). Cash, card (with its reference) and charge to a customer's account
    // in any mix: card + charge can't be more than the amount due, and change only comes out of cash. Enter confirms
    // once the payments cover the sale; Esc cancels. The credit-limit check / approval is the caller's (it knows the
    // supervisors and this terminal's unsent charges).
    public sealed class PosPaymentForm : XtraForm
    {
        public sealed class Result
        {
            public List<PosPayment> Payments { get; } = new List<PosPayment>();
            public decimal Tendered { get; set; }
            public decimal Change { get; set; }
            public PosCustomer Customer { get; set; }   // set when something is charged
            public decimal Charge { get; set; }
        }

        private readonly decimal _due;
        private readonly TextEdit _txtCash = new TextEdit(), _txtCard = new TextEdit(), _txtCardRef = new TextEdit(), _txtCharge = new TextEdit();
        private readonly SearchLookUpEdit _lkCustomer = new SearchLookUpEdit();
        private readonly LabelControl _lblLeft = new LabelControl(), _lblLeftCap = new LabelControl();
        private bool _cashTyped;      // UI review S1: until the cashier types the cash, it follows what is left after card + charge
        public Result Paid { get; private set; }

        private PosPaymentForm(decimal due, IList<PosCustomer> customers)
        {
            _due = due;
            Text = "Payment";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterParent;
            MaximizeBox = false; MinimizeBox = false; ShowInTaskbar = false;
            ClientSize = new Size(560, 360);
            KeyPreview = true;

            var big = new Font("Tahoma", 20f, FontStyle.Bold);
            var mid = new Font("Tahoma", 13f, FontStyle.Bold);
            var lblDueCap = new LabelControl { Text = "Amount due", Location = new Point(20, 22) };
            var lblDue = new LabelControl { Text = due.ToString("N2"), Location = new Point(170, 12) };
            lblDue.Appearance.Font = big;

            Func<string, int, TextEdit, Control[]> money = (cap, y, box) =>
            {
                var c = new LabelControl { Text = cap, Location = new Point(20, y + 6) };
                box.Location = new Point(170, y); box.Width = 160;
                box.Properties.Appearance.Font = mid;
                box.Properties.Appearance.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                box.Properties.Mask.MaskType = DevExpress.XtraEditors.Mask.MaskType.Numeric;   // digits only (UI review S6)
                box.Properties.Mask.EditMask = "n2";
                box.Properties.Mask.UseMaskAsDisplayFormat = true;
                box.EditValueChanged += (s, e) => { if (box != _txtCash) FollowCash(); ShowLeft(); };
                return new Control[] { c, box };
            };
            Controls.AddRange(money("Cash tendered", 70, _txtCash));
            Controls.AddRange(money("Card", 115, _txtCard));
            var lblRef = new LabelControl { Text = "Card ref.", Location = new Point(345, 121) };
            _txtCardRef.Location = new Point(400, 115); _txtCardRef.Width = 140;
            _txtCardRef.Properties.NullValuePrompt = "VISA ****1234 APP 123456";
            _txtCardRef.Properties.MaxLength = 100;
            Controls.AddRange(money("Charge to account", 160, _txtCharge));
            var lblCust = new LabelControl { Text = "Customer", Location = new Point(20, 211) };
            _lkCustomer.Location = new Point(170, 205); _lkCustomer.Width = 370;
            _lkCustomer.Properties.DataSource = customers;
            _lkCustomer.Properties.ValueMember = "CustomerKey";
            _lkCustomer.Properties.DisplayMember = "Display";
            _lkCustomer.Properties.TextEditStyle = TextEditStyles.DisableTextEditor;   // pick a row; never free text (Known Bug #2)
            _lkCustomer.Properties.NullText = customers.Count == 0 ? "(no customers downloaded: F5)" : "";
            _lkCustomer.Properties.PopulateViewColumns();
            foreach (DevExpress.XtraGrid.Columns.GridColumn col in _lkCustomer.Properties.View.Columns)
                col.Visible = col.FieldName == "CustomerKey" || col.FieldName == "CustomerName" || col.FieldName == "CreditLimit" || col.FieldName == "Balance";
            foreach (var f in new[] { "CreditLimit", "Balance" })
            {
                var col = _lkCustomer.Properties.View.Columns[f];
                if (col == null) continue;
                col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                col.DisplayFormat.FormatString = "N2";
            }

            _lblLeftCap.Location = new Point(20, 262);
            _lblLeft.Location = new Point(170, 252);
            _lblLeft.Appearance.Font = big;
            var btnOk = new SimpleButton { Text = "Pay (Enter)", Location = new Point(320, 310), Size = new Size(110, 34) };
            var btnCancel = new SimpleButton { Text = "Cancel (Esc)", Location = new Point(436, 310), Size = new Size(104, 34), DialogResult = DialogResult.Cancel };
            btnOk.Click += (s, e) => Confirm();
            KeyDown += (s, e) =>
            {
                // Enter pays, except on a button (Enter on Cancel must cancel: UI review S6) or in the open customer list
                if (e.KeyCode == Keys.Enter && !_lkCustomer.IsPopupOpen && !(ActiveControl is SimpleButton)) { Confirm(); e.Handled = true; e.SuppressKeyPress = true; }
            };
            _txtCash.KeyDown += (s, e) => { if (e.KeyCode != Keys.Enter && e.KeyCode != Keys.Tab) _cashTyped = true; };
            Controls.AddRange(new Control[] { lblDueCap, lblDue, lblRef, _txtCardRef, lblCust, _lkCustomer, _lblLeftCap, _lblLeft, btnOk, btnCancel });
            CancelButton = btnCancel;
            _txtCash.Text = due.ToString("0.00", CultureInfo.InvariantCulture);
            Shown += (s, e) => { _txtCash.Focus(); _txtCash.SelectAll(); };
            ShowLeft();
        }

        private static decimal Amount(TextEdit t)
        {
            decimal v;
            return decimal.TryParse((t.Text ?? "").Replace(",", "").Trim(), NumberStyles.Number, CultureInfo.InvariantCulture, out v) && v > 0
                ? Math.Round(v, 2, MidpointRounding.AwayFromZero) : 0m;
        }

        // Until the cashier types the cash, it is what is left after card + charge (so a card payment of the whole amount
        // doesn't leave a fake cash tender and change behind; UI review S1).
        private void FollowCash()
        {
            if (_cashTyped) return;
            decimal left = Math.Max(0m, _due - Amount(_txtCard) - Amount(_txtCharge));
            _txtCash.Text = left.ToString("0.00", CultureInfo.InvariantCulture);
        }

        private void ShowLeft()
        {
            decimal cash = Amount(_txtCash), card = Amount(_txtCard), charge = Amount(_txtCharge);
            decimal left = _due - cash - card - charge;
            if (card + charge > _due) { _lblLeftCap.Text = "Too much"; _lblLeft.Text = "card + charge > due"; _lblLeft.ForeColor = Color.Firebrick; }
            else if (left > 0) { _lblLeftCap.Text = "Still to pay"; _lblLeft.Text = left.ToString("N2"); _lblLeft.ForeColor = Color.Firebrick; }
            else { _lblLeftCap.Text = "Change"; _lblLeft.Text = (-left).ToString("N2"); _lblLeft.ForeColor = Color.DarkGreen; }
        }

        private void Confirm()
        {
            decimal cash = Amount(_txtCash), card = Amount(_txtCard), charge = Amount(_txtCharge);
            if (card + charge > _due) { XtraMessageBox.Show("Card + charge can't be more than the amount due (change only comes out of cash)."); return; }
            if (cash + card + charge < _due) { XtraMessageBox.Show("The payments don't cover the amount due yet."); return; }
            if (card > 0 && string.IsNullOrWhiteSpace(_txtCardRef.Text)) { XtraMessageBox.Show("Type the card reference (card, last 4 digits, approval code)."); _txtCardRef.Focus(); return; }
            PosCustomer cust = null;
            if (charge > 0)
            {
                cust = _lkCustomer.GetSelectedDataRow() as PosCustomer;   // the picked row, read from the editor (Known Bug #3)
                if (cust == null || !Equals(_lkCustomer.EditValue, cust.CustomerKey)) { XtraMessageBox.Show("Pick the customer to charge."); _lkCustomer.Focus(); return; }
            }
            if (cash > 0 && cash <= cash + card + charge - _due) cash = 0m;   // all of the cash would come back as change: there is no cash tender
            if (cash + card + charge - _due > cash) { XtraMessageBox.Show("Change can only come out of cash."); return; }
            var r = new Result { Tendered = cash + card + charge, Change = cash + card + charge - _due, Customer = cust, Charge = charge };
            int n = 1;
            if (cash > 0) r.Payments.Add(new PosPayment { PayNo = n++, PaymentType = "CASH", Amount = cash });
            if (card > 0) r.Payments.Add(new PosPayment { PayNo = n++, PaymentType = "CARD", Amount = card, Reference = _txtCardRef.Text.Trim() });
            if (charge > 0) r.Payments.Add(new PosPayment { PayNo = n++, PaymentType = "CHARGE", Amount = charge, Reference = cust.CustomerKey });
            Paid = r;
            DialogResult = DialogResult.OK;
        }

        public static Result Ask(IWin32Window owner, decimal due, IList<PosCustomer> customers)
        {
            using (var f = new PosPaymentForm(due, customers ?? new List<PosCustomer>()))
                return f.ShowDialog(owner) == DialogResult.OK ? f.Paid : null;
        }
    }
}
