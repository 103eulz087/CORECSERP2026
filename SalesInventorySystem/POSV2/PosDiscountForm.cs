using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using SalesInventorySystem.POSV2.Models;

namespace SalesInventorySystem.POSV2
{
    // POS V2 discount entry (phase 2). The types come from the server (POSV2_DiscountType, downloaded with the
    // products): fixed rate (senior / PWD), a rate the cashier types (other %), or an amount (one-time).
    // Senior / PWD types require the customer's name and ID no. The arithmetic is PosPricingService's.
    public sealed class PosDiscountForm : XtraForm
    {
        public sealed class Request
        {
            public bool RemoveAll { get; set; }
            public PosDiscountType Type { get; set; }
            public decimal Percent { get; set; }      // PCT / PCT_OPEN
            public decimal Amount { get; set; }       // AMOUNT
            public string CustomerName { get; set; }
            public string IDNo { get; set; }
            public string TIN { get; set; }
            public string Remarks { get; set; }
            public bool AllLines { get; set; }        // else: the highlighted line only
        }

        private readonly LookUpEdit _type = new LookUpEdit();
        private readonly TextEdit _rate = new TextEdit(), _amount = new TextEdit(), _name = new TextEdit(), _id = new TextEdit(), _tin = new TextEdit(), _remarks = new TextEdit();
        private readonly RadioGroup _scope = new RadioGroup();
        public Request Result { get; private set; }

        private PosDiscountForm(List<PosDiscountType> types, string focusedLine)
        {
            Text = "Discount";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterParent;
            MaximizeBox = false; MinimizeBox = false; ShowInTaskbar = false;
            ClientSize = new Size(470, 400);

            int y = 16;
            Func<string, Control, int, LabelControl> row = (cap, ctl, w) =>
            {
                var l = new LabelControl { Text = cap, Location = new Point(16, y + 4) };
                ctl.Location = new Point(140, y);
                ctl.Width = w;
                Controls.Add(l); Controls.Add(ctl);
                y += 34;
                return l;
            };

            _type.Properties.DataSource = types;
            _type.Properties.DisplayMember = "Name";
            _type.Properties.ValueMember = "DiscountCode";
            _type.Properties.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;   // Known Bug #2
            _type.Properties.ShowHeader = false;
            _type.Properties.Columns.Add(new DevExpress.XtraEditors.Controls.LookUpColumnInfo("Name", "Type"));
            _type.Properties.NullText = "";
            row("Discount type", _type, 310);
            row("Rate (%)", _rate, 110);
            row("Amount", _amount, 110);
            row("Customer name", _name, 310);
            row("ID no. (OSCA / PWD)", _id, 200);
            row("TIN (optional)", _tin, 200);
            row("Remarks", _remarks, 310);

            _scope.Properties.Columns = 1;
            _scope.Properties.Items.Add(new DevExpress.XtraEditors.Controls.RadioGroupItem(false, "Highlighted line only: " + (focusedLine ?? "(none)")));
            _scope.Properties.Items.Add(new DevExpress.XtraEditors.Controls.RadioGroupItem(true, "All lines without a discount"));
            _scope.EditValue = true;
            _scope.Location = new Point(16, y + 4);
            _scope.Size = new Size(438, 56);
            Controls.Add(_scope);

            var btnApply = new SimpleButton { Text = "Apply", Location = new Point(176, 352), Size = new Size(90, 30) };
            var btnRemove = new SimpleButton { Text = "Remove all discounts", Location = new Point(16, 352), Size = new Size(150, 30) };
            var btnCancel = new SimpleButton { Text = "Cancel", Location = new Point(364, 352), Size = new Size(90, 30), DialogResult = DialogResult.Cancel };
            Controls.AddRange(new Control[] { btnApply, btnRemove, btnCancel });
            CancelButton = btnCancel;

            _type.EditValueChanged += (s, e) => ShowFields();
            btnApply.Click += (s, e) => Apply();
            btnRemove.Click += (s, e) => { Result = new Request { RemoveAll = true }; DialogResult = DialogResult.OK; };
            if (types.Count > 0) _type.EditValue = types[0].DiscountCode;
            ShowFields();
        }

        private PosDiscountType Picked => _type.GetSelectedDataRow() as PosDiscountType;

        private void ShowFields()
        {
            var t = Picked;
            bool open = t != null && t.Kind == "PCT_OPEN";
            bool amount = t != null && t.Kind == "AMOUNT";
            _rate.Enabled = open;
            _rate.Text = t == null ? "" : (open ? "" : t.Percent.ToString("0.##", CultureInfo.InvariantCulture));
            _amount.Enabled = amount;
            if (!amount) _amount.Text = "";
        }

        private static bool Num(TextEdit t, out decimal v) =>
            decimal.TryParse(t.Text.Replace(",", "").Trim(), NumberStyles.Number, CultureInfo.InvariantCulture, out v);

        private void Apply()
        {
            var t = Picked;
            if (t == null) { XtraMessageBox.Show("Pick the discount type."); return; }
            var r = new Request
            {
                Type = t, CustomerName = _name.Text.Trim(), IDNo = _id.Text.Trim(), TIN = _tin.Text.Trim(), Remarks = _remarks.Text.Trim(),
                AllLines = Equals(_scope.EditValue, true)
            };
            decimal v;
            if (t.Kind == "PCT") r.Percent = t.Percent;
            else if (t.Kind == "PCT_OPEN")
            {
                if (!Num(_rate, out v) || v <= 0 || v > 100) { XtraMessageBox.Show("Enter a rate between 0 and 100."); return; }
                r.Percent = Math.Round(v, 4);
            }
            else
            {
                if (!Num(_amount, out v) || v <= 0) { XtraMessageBox.Show("Enter the discount amount."); return; }
                r.Amount = Math.Round(v, 2, MidpointRounding.AwayFromZero);
            }
            if (t.RequiresID && (r.CustomerName.Length == 0 || r.IDNo.Length == 0))
            {
                XtraMessageBox.Show("This discount needs the customer's name and ID no.");
                return;
            }
            Result = r;
            DialogResult = DialogResult.OK;
        }

        public static Request Ask(IWin32Window owner, List<PosDiscountType> types, string focusedLine)
        {
            using (var f = new PosDiscountForm(types, focusedLine))
                return f.ShowDialog(owner) == DialogResult.OK ? f.Result : null;
        }
    }
}
