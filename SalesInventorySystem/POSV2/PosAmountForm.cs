using System;
using System.Drawing;
using System.Globalization;
using System.Windows.Forms;
using DevExpress.XtraEditors;

namespace SalesInventorySystem.POSV2
{
    // An amount prompt for POS V2 (phase 3): beginning cash when a shift opens, cash counted at the Z-reading.
    // Enter confirms (0 or more, 2 decimals), Esc cancels. The count is blind: the expected cash is not shown here.
    public sealed class PosAmountForm : XtraForm
    {
        private readonly TextEdit _txt = new TextEdit();
        public decimal Amount { get; private set; }

        private PosAmountForm(string title, string caption, decimal initial)
        {
            Text = title;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterParent;
            MaximizeBox = false; MinimizeBox = false; ShowInTaskbar = false; KeyPreview = true;
            ClientSize = new Size(420, 170);
            var lbl = new LabelControl { Text = caption, Location = new Point(18, 16), AutoSizeMode = LabelAutoSizeMode.Vertical, Width = 384 };
            lbl.Appearance.Font = new Font("Tahoma", 10f);
            _txt.Location = new Point(18, 64); _txt.Width = 384;
            _txt.Properties.Appearance.Font = new Font("Tahoma", 20f, FontStyle.Bold);
            _txt.Properties.Appearance.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
            _txt.Text = initial.ToString("0.00", CultureInfo.InvariantCulture);
            var btnOk = new SimpleButton { Text = "OK (Enter)", Location = new Point(188, 120), Size = new Size(104, 34) };
            var btnCancel = new SimpleButton { Text = "Cancel (Esc)", Location = new Point(298, 120), Size = new Size(104, 34), DialogResult = DialogResult.Cancel };
            btnOk.Click += (s, e) => Confirm();
            KeyDown += (s, e) => { if (e.KeyCode == Keys.Enter) { Confirm(); e.Handled = true; e.SuppressKeyPress = true; } };
            Controls.AddRange(new Control[] { lbl, _txt, btnOk, btnCancel });
            CancelButton = btnCancel;
            Shown += (s, e) => { _txt.Focus(); _txt.SelectAll(); };
        }

        private void Confirm()
        {
            decimal v;
            if (!decimal.TryParse((_txt.Text ?? "").Replace(",", "").Trim(), NumberStyles.Number, CultureInfo.InvariantCulture, out v) || v < 0)
            {
                XtraMessageBox.Show("Type an amount of 0 or more.");
                return;
            }
            Amount = Math.Round(v, 2, MidpointRounding.AwayFromZero);
            DialogResult = DialogResult.OK;
        }

        public static decimal? Ask(IWin32Window owner, string title, string caption, decimal initial)
        {
            using (var f = new PosAmountForm(title, caption, initial))
                return f.ShowDialog(owner) == DialogResult.OK ? f.Amount : (decimal?)null;
        }
    }
}
