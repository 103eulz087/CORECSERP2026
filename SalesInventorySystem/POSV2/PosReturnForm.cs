using System;
using System.ComponentModel;
using System.Drawing;
using System.Globalization;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid;
using DevExpress.XtraGrid.Views.Grid;
using SalesInventorySystem.POSV2.Models;
using SalesInventorySystem.POSV2.Services;

namespace SalesInventorySystem.POSV2
{
    // Return / refund (phase 4). Type the OR no. of a posted sale of this branch: the sale comes from the server when it is
    // reachable (it knows every terminal's returns and the charge invoice's open balance), else from this terminal's own
    // copy. Type the qty to return per line, a reason; the refund is split "same as paid" (account, card, then cash).
    // Returns the return to save (the caller asks for the supervisor's PIN, saves it and prints the slip), or null.
    public sealed class PosReturnForm : XtraForm
    {
        private readonly PosLocalStore _store;
        private readonly string _branch;
        private readonly Func<bool> _online;     // asked at each lookup (UI review S7)
        private int _lookupSeq;                  // a newer lookup wins; Return is off while one runs (S3)
        private bool _busy;
        private bool _localFallback;             // the server was unreachable although online: other terminals' returns unknown (B2)
        private readonly TextEdit _txtOR = new TextEdit(), _txtReason = new TextEdit();
        private readonly SimpleButton _btnFind = new SimpleButton(), _btnOk = new SimpleButton();
        private readonly LabelControl _lblSale = new LabelControl(), _lblRefund = new LabelControl();
        private readonly GridControl _grid = new GridControl();
        private readonly GridView _view;
        private readonly BindingList<PosReturnSourceLine> _lines = new BindingList<PosReturnSourceLine>();
        private PosReturnSource _src;
        public PosReturn Result { get; private set; }

        private PosReturnForm(PosLocalStore store, string branch, Func<bool> online)
        {
            _store = store; _branch = branch; _online = online;
            Text = "Return / Refund";
            StartPosition = FormStartPosition.CenterParent;
            ClientSize = new Size(900, 560);
            MinimizeBox = false; ShowInTaskbar = false; KeyPreview = true;

            var top = new PanelControl { Dock = DockStyle.Top, Height = 78 };
            var lblOR = new LabelControl { Text = "OR no.", Location = new Point(12, 16) };
            _txtOR.Location = new Point(70, 10); _txtOR.Width = 240;
            _txtOR.Properties.Appearance.Font = new Font("Tahoma", 12f, FontStyle.Bold);
            _btnFind.Text = "Find (Enter)"; _btnFind.Location = new Point(320, 9); _btnFind.Size = new Size(100, 30);
            _btnFind.Click += async (s, e) => await FindAsync();
            _txtOR.KeyDown += async (s, e) => { if (e.KeyCode == Keys.Enter) { e.Handled = true; e.SuppressKeyPress = true; await FindAsync(); } };
            _lblSale.Location = new Point(12, 50); _lblSale.AutoSizeMode = LabelAutoSizeMode.Horizontal;
            top.Controls.AddRange(new Control[] { lblOR, _txtOR, _btnFind, _lblSale });

            var bottom = new PanelControl { Dock = DockStyle.Bottom, Height = 100 };
            var lblReason = new LabelControl { Text = "Reason", Location = new Point(12, 16) };
            _txtReason.Location = new Point(70, 10); _txtReason.Width = 560;
            _lblRefund.Location = new Point(12, 50); _lblRefund.AutoSizeMode = LabelAutoSizeMode.Horizontal;
            _lblRefund.Appearance.Font = new Font("Tahoma", 11f, FontStyle.Bold);
            _btnOk.Text = "Return (Ctrl+Enter)"; _btnOk.Location = new Point(650, 52); _btnOk.Size = new Size(130, 34); _btnOk.Enabled = false;
            _btnOk.Click += (s, e) => Confirm();
            var btnCancel = new SimpleButton { Text = "Cancel (Esc)", Location = new Point(786, 52), Size = new Size(100, 34), DialogResult = DialogResult.Cancel };
            bottom.Controls.AddRange(new Control[] { lblReason, _txtReason, _lblRefund, _btnOk, btnCancel });
            CancelButton = btnCancel;

            _grid.Dock = DockStyle.Fill;
            _view = new GridView(_grid);
            _grid.MainView = _view;
            _view.OptionsView.ShowGroupPanel = false;
            _view.OptionsCustomization.AllowSort = false;
            _view.OptionsCustomization.AllowFilter = false;
            _view.OptionsView.ShowFooter = true;
            // columns added explicitly: PopulateColumns() creates none while the form isn't shown yet (constructor)
            var caps = new[] { new[] { "LineNo", "#" }, new[] { "Description", "Description" }, new[] { "Qty", "Sold" }, new[] { "ReturnedQty", "Returned" },
                               new[] { "Returnable", "Returnable" }, new[] { "ReturnQty", "Return now" }, new[] { "UnitPrice", "Price" }, new[] { "LineTotal", "Paid (line)" } };
            foreach (var cap in caps)
            {
                var c = _view.Columns.AddVisible(cap[0], cap[1]);
                c.OptionsColumn.AllowEdit = cap[0] == "ReturnQty";   // only the qty to return is typed
            }
            _grid.DataSource = _lines;
            foreach (var f in new[] { "Qty", "ReturnedQty", "Returnable", "ReturnQty" }) Num(f, "N3");
            foreach (var f in new[] { "UnitPrice", "LineTotal" }) Num(f, "N2");
            _view.Columns["ReturnQty"].AppearanceCell.BackColor = Color.LightYellow;
            // the qty to return: a spin box, 0 up to what this line still has (UI review S2); the preview follows each keystroke
            var spin = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit { MinValue = 0m, IsFloatValue = true, AllowNullInput = DevExpress.Utils.DefaultBoolean.False };
            spin.Mask.EditMask = "n3";
            spin.Mask.UseMaskAsDisplayFormat = true;
            spin.EditValueChanged += (s, e) => _view.PostEditor();
            _grid.RepositoryItems.Add(spin);
            _view.Columns["ReturnQty"].ColumnEdit = spin;
            _view.ShowingEditor += (s, e) =>
            {
                var row = _view.GetFocusedRow() as PosReturnSourceLine;
                if (row == null || row.Returnable <= 0) e.Cancel = true;   // nothing left to return on this line
            };
            _view.ShownEditor += (s, e) =>
            {
                var row = _view.GetFocusedRow() as PosReturnSourceLine;
                var ed = _view.ActiveEditor as SpinEdit;
                if (row != null && ed != null) ed.Properties.MaxValue = row.Returnable;
            };
            _view.CellValueChanged += (s, e) => ShowRefund();
            _view.ValidatingEditor += (s, e) =>
            {
                var row = _view.GetFocusedRow() as PosReturnSourceLine;
                decimal q;
                if (row == null) return;
                if (e.Value == null || !decimal.TryParse(Convert.ToString(e.Value, CultureInfo.CurrentCulture), NumberStyles.Number, CultureInfo.CurrentCulture, out q))
                { e.Valid = false; e.ErrorText = "Type a quantity."; return; }
                if (q < 0 || q > row.Returnable) { e.Valid = false; e.ErrorText = "Between 0 and " + row.Returnable.ToString("0.###") + "."; }
                else e.Value = Math.Round(q, 3, MidpointRounding.AwayFromZero);
            };

            Controls.Add(_grid);
            Controls.Add(bottom);
            Controls.Add(top);
            _grid.BringToFront();
            KeyDown += (s, e) => { if (e.KeyCode == Keys.Enter && e.Control) { Confirm(); e.Handled = true; } };
            Shown += (s, e) => _txtOR.Focus();
        }

        private void Num(string field, string fmt)
        {
            var c = _view.Columns[field];
            if (c == null) return;
            c.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            c.DisplayFormat.FormatString = fmt;
            c.AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
            c.AppearanceCell.Options.UseTextOptions = true;
            c.AppearanceHeader.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
            c.AppearanceHeader.Options.UseTextOptions = true;
        }

        // The server is asked off the UI thread; the grid is bound back on it (Known Bug #8). A newer lookup wins, the screen
        // is cleared first, and Return is off until the result is on screen (UI review S3).
        private async Task FindAsync()
        {
            string or = (_txtOR.Text ?? "").Trim();
            if (or.Length == 0) return;
            int seq = ++_lookupSeq;
            _busy = true;
            _btnFind.Enabled = false; _btnOk.Enabled = false;
            _src = null; _lines.Clear(); _localFallback = false;
            _lblSale.Text = "Looking up " + or + "…";
            PosReturnSource src = null; string note = null; bool fallback = false;
            try
            {
                bool online = _online();
                if (online)
                {
                    try
                    {
                        src = await Task.Run(() =>
                        {
                            var s = PosSyncService.FetchReturnSource(_branch, or);
                            if (s != null) _store.AddUnsentReturns(s);   // this terminal's returns of it the server doesn't have yet (B2)
                            return s;
                        });
                    }
                    catch (Exception ex) { note = "server not reachable (" + ex.Message + "): using this terminal's copy"; fallback = true; }
                }
                if (src == null)
                {
                    src = await Task.Run(() => _store.LocalReturnSource(or));   // not on the server yet, or offline
                    if (src != null && !online) fallback = true;
                }
                if (src != null && src.Status != "VOIDED" && await Task.Run(() => _store.IsVoidedHere(src.SaleGuid))) src.Status = "VOIDED";   // B1
            }
            catch (Exception ex) { note = ex.Message; src = null; }
            if (IsDisposed || seq != _lookupSeq) return;
            try
            {
                _busy = false;
                _btnFind.Enabled = true;
                _src = src;
                if (src == null) { _lblSale.Text = "OR " + or + " not found" + (note == null ? "." : ": " + note); return; }
                if (src.Status == "VOIDED") { _lblSale.Text = "OR " + or + " was voided: nothing to return."; _src = null; return; }
                _localFallback = fallback && !src.FromServer;
                foreach (var l in src.Lines) _lines.Add(l);
                _lblSale.Text = "OR " + src.ORNo + "  " + src.SaleDateTime.ToString("yyyy-MM-dd HH:mm") +
                                (string.IsNullOrEmpty(src.CustomerKey) ? "" : "   customer " + src.CustomerKey + " " + src.CustomerName) +
                                "   paid: cash " + src.PaidCash.ToString("N2") + ", card " + src.PaidCard.ToString("N2") + ", charge " + src.PaidCharge.ToString("N2") +
                                (src.FromServer ? "" : "   (this terminal's copy)") + (note == null ? "" : "   " + note);
                ShowRefund();
                _view.FocusedColumn = _view.Columns["ReturnQty"];
                _grid.Focus();
            }
            catch (Exception ex) { _lblSale.Text = "Lookup failed: " + ex.Message; _src = null; _lines.Clear(); }
        }

        private PosReturn Build()
        {
            if (_src == null) return null;
            var rt = new PosReturn { ReturnGuid = Guid.NewGuid(), OrigSaleGuid = _src.SaleGuid, OrigORNo = _src.ORNo,
                                     CustomerKey = _src.CustomerKey, CustomerName = _src.CustomerName };
            int n = 1;
            foreach (var l in _lines.Where(x => x.ReturnQty > 0))
                rt.Lines.Add(PosPricingService.ReturnShare(l, Math.Min(l.ReturnQty, l.Returnable), n++));
            PosPricingService.SplitRefund(rt, _src);
            return rt;
        }

        private void ShowRefund()
        {
            var rt = Build();
            if (rt == null || rt.Lines.Count == 0) { _lblRefund.Text = "Type the qty to return."; _btnOk.Enabled = false; return; }
            _lblRefund.Text = "Refund " + rt.NetAmount.ToString("N2") + ":   account " + rt.ChargeRefund.ToString("N2") +
                              "   card " + rt.CardRefund.ToString("N2") + "   CASH " + rt.CashRefund.ToString("N2");
            _btnOk.Enabled = true;
        }

        private void Confirm()
        {
            if (_busy || _src == null) return;
            _view.CloseEditor();
            if (_view.IsEditing) return;          // the qty didn't pass validation: the editor stays open (UI review S2)
            _view.UpdateCurrentRow();
            var rt = Build();
            if (rt == null || rt.Lines.Count == 0) { XtraMessageBox.Show("Type the qty to return on at least one line."); return; }
            if (string.IsNullOrWhiteSpace(_txtReason.Text)) { XtraMessageBox.Show("Type the reason for the return."); _txtReason.Focus(); return; }
            // B2 / S5: without the server, other terminals' returns of this sale and the invoice's open balance are unknown
            if ((_localFallback || (!_src.FromServer && rt.ChargeRefund > 0)) &&
                XtraMessageBox.Show("The server couldn't be asked about this sale: returns made on other terminals and the customer's open invoice are not known." +
                                    (rt.ChargeRefund > 0 ? "\n\n" + rt.ChargeRefund.ToString("N2") + " goes back to the customer's account without checking its balance." : "") +
                                    "\n\nRefund anyway?", "Return / Refund", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            rt.Reason = _txtReason.Text.Trim();
            Result = rt;
            DialogResult = DialogResult.OK;
        }

        public static PosReturn Ask(IWin32Window owner, PosLocalStore store, string branch, Func<bool> online)
        {
            using (var f = new PosReturnForm(store, branch, online))
                return f.ShowDialog(owner) == DialogResult.OK ? f.Result : null;
        }
    }
}
