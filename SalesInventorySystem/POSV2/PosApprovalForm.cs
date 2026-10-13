using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraEditors.Controls;
using SalesInventorySystem.POSV2.Models;

namespace SalesInventorySystem.POSV2
{
    // Supervisor approval (phase 3): the supervisor picks their name and types their PIN; the PIN is checked on this
    // terminal against the downloaded PBKDF2 hash (PasswordHasher), so it works offline. Returns the approver's
    // user ID, or null when cancelled. Five wrong PINs lock approvals on this terminal for a minute.
    public sealed class PosApprovalForm : XtraForm
    {
        private static int _failures;
        private static DateTime _lockedUntil = DateTime.MinValue;

        private readonly ComboBoxEdit _cboSupervisor = new ComboBoxEdit();
        private readonly TextEdit _txtPin = new TextEdit();
        private readonly LabelControl _lblMsg = new LabelControl();
        public string ApprovedBy { get; private set; }

        private sealed class Item
        {
            public PosSupervisor S;
            public override string ToString() => S.UserID + " - " + S.FullName;   // Code - Name
        }

        private PosApprovalForm(IList<PosSupervisor> supervisors, string purpose)
        {
            Text = "Supervisor Approval";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterParent;
            MaximizeBox = false; MinimizeBox = false; ShowInTaskbar = false; KeyPreview = true;
            ClientSize = new Size(440, 230);

            var lblPurpose = new LabelControl { Text = purpose, Location = new Point(16, 14), AutoSizeMode = LabelAutoSizeMode.Vertical, Width = 408 };
            lblPurpose.Appearance.Font = new Font("Tahoma", 10f, FontStyle.Bold);
            var lblSup = new LabelControl { Text = "Supervisor", Location = new Point(16, 74) };
            _cboSupervisor.Location = new Point(110, 70); _cboSupervisor.Width = 314;
            _cboSupervisor.Properties.TextEditStyle = TextEditStyles.DisableTextEditor;   // pick from the list only
            foreach (var s in supervisors.OrderBy(x => x.UserID)) _cboSupervisor.Properties.Items.Add(new Item { S = s });
            if (_cboSupervisor.Properties.Items.Count == 1) _cboSupervisor.SelectedIndex = 0;
            var lblPin = new LabelControl { Text = "PIN", Location = new Point(16, 112) };
            _txtPin.Location = new Point(110, 108); _txtPin.Width = 160;
            _txtPin.Properties.UseSystemPasswordChar = true;
            _txtPin.Properties.Appearance.Font = new Font("Tahoma", 14f, FontStyle.Bold);
            _lblMsg.Location = new Point(16, 148); _lblMsg.ForeColor = Color.Firebrick;
            var btnOk = new SimpleButton { Text = "Approve (Enter)", Location = new Point(194, 180), Size = new Size(120, 34) };
            var btnCancel = new SimpleButton { Text = "Cancel (Esc)", Location = new Point(320, 180), Size = new Size(104, 34), DialogResult = DialogResult.Cancel };
            btnOk.Click += (s, e) => Confirm();
            KeyDown += (s, e) => { if (e.KeyCode == Keys.Enter) { Confirm(); e.Handled = true; e.SuppressKeyPress = true; } };
            Controls.AddRange(new Control[] { lblPurpose, lblSup, _cboSupervisor, lblPin, _txtPin, _lblMsg, btnOk, btnCancel });
            CancelButton = btnCancel;
            Shown += (s, e) => { if (_cboSupervisor.SelectedIndex >= 0) _txtPin.Focus(); else _cboSupervisor.Focus(); };
        }

        private void Confirm()
        {
            if (DateTime.Now < _lockedUntil) { _lblMsg.Text = "Too many wrong PINs: try again at " + _lockedUntil.ToString("HH:mm:ss") + "."; return; }
            var item = _cboSupervisor.SelectedItem as Item;   // the picked row itself, never the typed text
            if (item == null) { _lblMsg.Text = "Pick the supervisor."; return; }
            string pin = _txtPin.Text ?? "";
            bool ok;
            try { ok = pin.Length > 0 && PasswordHasher.VerifyPassword(pin, item.S.PinSalt, item.S.PinIterations, item.S.PinHash); }
            catch (Exception) { ok = false; }
            if (!ok)
            {
                _txtPin.Text = "";
                if (++_failures >= 5) { _failures = 0; _lockedUntil = DateTime.Now.AddMinutes(1); _lblMsg.Text = "Too many wrong PINs: locked for a minute."; }
                else _lblMsg.Text = "Wrong PIN.";
                _txtPin.Focus();
                return;
            }
            _failures = 0;
            ApprovedBy = item.S.UserID;
            DialogResult = DialogResult.OK;
        }

        // Returns the approver, or null (cancelled / no supervisor downloaded yet: the caller says why).
        public static string Ask(IWin32Window owner, IList<PosSupervisor> supervisors, string purpose)
        {
            if (supervisors == null || supervisors.Count == 0)
            {
                XtraMessageBox.Show("No POS supervisor is set up for this branch yet (or the list hasn't downloaded: F5).\n" +
                                    "An admin sets supervisors and their PINs with Ctrl+P on a connected terminal.", "Supervisor Approval",
                                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return null;
            }
            using (var f = new PosApprovalForm(supervisors, purpose))
                return f.ShowDialog(owner) == DialogResult.OK ? f.ApprovedBy : null;
        }
    }
}
