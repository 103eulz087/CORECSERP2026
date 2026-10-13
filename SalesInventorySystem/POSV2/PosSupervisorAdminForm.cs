using System;
using System.Data;
using System.Drawing;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid;
using DevExpress.XtraGrid.Views.Grid;
using SalesInventorySystem.POSV2.Services;

namespace SalesInventorySystem.POSV2
{
    // POS V2 supervisors (phase 3, admins only, online): who may approve voids, discounts, cleared sales, no-sale drawer
    // openings and closing another cashier's shift, on which branch, and their PIN. Terminals pick the change up at their
    // next product refresh (F5, or within 30 minutes).
    public sealed class PosSupervisorAdminForm : XtraForm
    {
        private readonly GridControl _grid = new GridControl { Dock = DockStyle.Fill };
        private readonly GridView _view;

        public PosSupervisorAdminForm()
        {
            Text = "POS V2 Supervisors";
            StartPosition = FormStartPosition.CenterParent;
            ClientSize = new Size(860, 520);
            MinimizeBox = false; ShowInTaskbar = false;
            _view = new GridView(_grid);
            _grid.MainView = _view;
            _view.OptionsBehavior.Editable = false;
            _view.OptionsView.ShowGroupPanel = false;
            _view.OptionsFind.AlwaysVisible = true;
            _view.OptionsSelection.EnableAppearanceFocusedCell = false;

            var bar = new PanelControl { Dock = DockStyle.Bottom, Height = 52 };
            var btnPin = new SimpleButton { Text = "Make supervisor / set PIN…", Location = new Point(10, 10), Size = new Size(190, 32) };
            var btnBranch = new SimpleButton { Text = "Branch…", Location = new Point(206, 10), Size = new Size(100, 32) };
            var btnToggle = new SimpleButton { Text = "Activate / deactivate", Location = new Point(312, 10), Size = new Size(160, 32) };
            var btnClose = new SimpleButton { Text = "Close", Location = new Point(760, 10), Size = new Size(88, 32), DialogResult = DialogResult.Cancel };
            btnClose.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            btnPin.Click += (s, e) => SetPin();
            btnBranch.Click += (s, e) => SetBranch();
            btnToggle.Click += (s, e) => Toggle();
            bar.Controls.AddRange(new Control[] { btnPin, btnBranch, btnToggle, btnClose });
            Controls.Add(_grid);
            Controls.Add(bar);
            CancelButton = btnClose;
            Load += (s, e) => Reload();
        }

        private void Reload()
        {
            try
            {
                _grid.DataSource = PosSupervisorAdmin.List();
                _view.PopulateColumns();
                if (_view.Columns["UpdatedAt"] != null)
                {
                    _view.Columns["UpdatedAt"].DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                    _view.Columns["UpdatedAt"].DisplayFormat.FormatString = "yyyy-MM-dd HH:mm";
                }
                _view.BestFitColumns();
            }
            catch (Exception ex) { XtraMessageBox.Show("The supervisor list needs the server: " + ex.Message, Text); }
        }

        private DataRow FocusedRow() => _view.GetFocusedDataRow();

        private static string Branch(DataRow r)
        {
            string b = r["SupervisorBranch"] == DBNull.Value ? "" : r["SupervisorBranch"].ToString();
            return b == "(all)" ? "" : b;
        }

        private void SetPin()
        {
            var r = FocusedRow();
            if (r == null) return;
            string user = r["UserID"].ToString();
            string pin = XtraInputBox.Show(new XtraInputBoxArgs { Caption = Text, Prompt = "New PIN for " + user + " (at least " + PosSupervisorAdmin.MinPinLength + " digits):", Editor = PinEditor() }) as string;
            if (string.IsNullOrEmpty(pin)) return;
            string again = XtraInputBox.Show(new XtraInputBoxArgs { Caption = Text, Prompt = "Type the PIN again:", Editor = PinEditor() }) as string;
            if (again != pin) { XtraMessageBox.Show("The two PINs differ; nothing changed.", Text); return; }
            bool isSup = (bool)r["IsSupervisor"];
            string branch = isSup ? Branch(r) : (r["AssignedBranch"] == DBNull.Value ? "" : r["AssignedBranch"].ToString().Trim());
            Run(() => PosSupervisorAdmin.Set(user, branch, pin, true), user + " can approve" + (branch == "" ? " on every branch." : " on branch " + branch + "."));
        }

        private static TextEdit PinEditor()
        {
            var t = new TextEdit();
            t.Properties.UseSystemPasswordChar = true;
            return t;
        }

        private void SetBranch()
        {
            var r = FocusedRow();
            if (r == null) return;
            if (!(bool)r["IsSupervisor"]) { XtraMessageBox.Show("Make the user a supervisor first (set a PIN).", Text); return; }
            string user = r["UserID"].ToString();
            string b = XtraInputBox.Show("Branch code where " + user + " may approve (blank = every branch):", Text, Branch(r));
            if (b == null) return;
            Run(() => PosSupervisorAdmin.Set(user, b.Trim(), null, (bool)r["IsActive"]), "Saved.");
        }

        private void Toggle()
        {
            var r = FocusedRow();
            if (r == null) return;
            if (!(bool)r["IsSupervisor"]) { XtraMessageBox.Show("Make the user a supervisor first (set a PIN).", Text); return; }
            string user = r["UserID"].ToString();
            bool active = (bool)r["IsActive"];
            Run(() => PosSupervisorAdmin.Set(user, Branch(r), null, !active), user + (active ? " can no longer approve." : " can approve again."));
        }

        private void Run(Action a, string done)
        {
            try { a(); Reload(); XtraMessageBox.Show(done + "\nTerminals get it at their next product refresh (F5).", Text); }
            catch (Exception ex) { XtraMessageBox.Show(ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning); }
        }

        public static bool CurrentUserIsAdmin()
        {
            bool b;
            return bool.TryParse(Login.isglobalAdmin, out b) && b;
        }
    }
}
