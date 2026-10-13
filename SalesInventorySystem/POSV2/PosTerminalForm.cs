using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Drawing;
using System.Globalization;
using System.Linq;
using System.Threading;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid;
using DevExpress.XtraGrid.Views.Grid;
using SalesInventorySystem.POSV2.Devices;
using SalesInventorySystem.POSV2.Models;
using SalesInventorySystem.POSV2.Services;

namespace SalesInventorySystem.POSV2
{
    // POS V2 terminal (phases 1-3). UI only: no SQL here. The sale is built in memory, saved locally in one
    // transaction on payment (PosLocalStore), and the background PosSyncService posts it to the server (and
    // deducts the branch's FIFO stock) as soon as the server is reachable — at once when online, later when
    // offline. Keys: Enter scan · F2 quantity · F3 search · F4 price level · F5 refresh products / sync now ·
    // F6 discount · F7 hold / recall · F9 void (phase 2) ·
    // Del remove line · F8 clear sale · F10 pay · F11 reprint last · F12 retry sales that need attention.
    // Phase 3: a shift (cash beginning) must be open to sell · Ctrl+X X-reading · Ctrl+Z Z-reading = close shift ·
    // Ctrl+D no-sale drawer · Ctrl+R reprint a Z-reading · Ctrl+P supervisors (admin) · Ctrl+T return / refund (phase 4;
    // F10 takes cash / card / charge in any mix, a charge over the credit limit needs a supervisor). A void, a discount type that
    // needs approval, clearing a sale, a no-sale drawer opening and closing another cashier's shift need a supervisor's PIN.
    // "2.5*barcode" in the scan box sells 2.5 of that item.
    public sealed class PosTerminalForm : XtraForm
    {
        private PosLocalStore _store;
        private PosSyncService _sync;
        private PosScale _scale;
        private PosDisplayPole _pole;                 // phase 3
        private PosShift _shift;                      // phase 3: the terminal's open shift (null = none)
        private List<PosSupervisor> _supervisors = new List<PosSupervisor>();
        private List<PosCustomer> _customers = new List<PosCustomer>();   // phase 4: charge customers (downloaded)
        private string _discountApprovedBy;           // supervisor who approved a discount on the sale on screen
        private bool _askingShift;
        private bool _shiftPending;                   // ask for the cash beginning when this window is the active one (no other modal up)

        private List<PosProduct> _products = new List<PosProduct>();
        private Dictionary<string, PosProduct> _byCode = new Dictionary<string, PosProduct>(StringComparer.OrdinalIgnoreCase);
        private ILookup<string, PosProduct> _byBarcode = new List<PosProduct>().ToLookup(p => p.Barcode);
        private Dictionary<string, decimal> _stock = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase);
        private readonly BindingList<PosCartLine> _cart = new BindingList<PosCartLine>();
        private string _priceLevel = "MAIN";
        private List<PosDiscountType> _discountTypes = new List<PosDiscountType>();   // phase 2
        private readonly List<PosSaleDiscount> _discounts = new List<PosSaleDiscount>();
        private int _cancelledCount;          // lines removed before payment (counted on the sale)
        private decimal _cancelledAmount;
        private string _branchName = "";
        private bool _ready;

        // controls
        private readonly LabelControl lblBranch = new LabelControl(), lblCashier = new LabelControl(), lblClock = new LabelControl();
        private readonly LabelControl lblStatus = new LabelControl(), lblQueue = new LabelControl(), lblMessage = new LabelControl(), lblShift = new LabelControl();
        private readonly LabelControl lblTotal = new LabelControl(), lblItems = new LabelControl(), lblVatable = new LabelControl();
        private readonly LabelControl lblVat = new LabelControl(), lblExempt = new LabelControl(), lblLevel = new LabelControl(), lblDiscount = new LabelControl();
        private readonly TextEdit txtQty = new TextEdit(), txtScan = new TextEdit();
        private readonly GridControl grid = new GridControl { Dock = DockStyle.Fill };
        private GridView view;
        private readonly System.Windows.Forms.Timer clock = new System.Windows.Forms.Timer { Interval = 1000 };

        public PosTerminalForm()
        {
            Text = "Point of Sale V2";
            WindowState = FormWindowState.Maximized;
            KeyPreview = true;
            MinimumSize = new Size(1000, 640);
            BuildLayout();
        }

        // ── layout ─────────────────────────────────────────────────────
        private void BuildLayout()
        {
            var top = new PanelControl { Dock = DockStyle.Top, Height = 84 };
            Place(top, lblBranch, 12, 8, 11f, true);
            Place(top, lblCashier, 12, 34, 9.5f, false);
            Place(top, lblShift, 12, 58, 9.5f, true);
            Place(top, lblStatus, 460, 8, 11f, true);
            Place(top, lblQueue, 460, 34, 9.5f, false);
            lblClock.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            Place(top, lblClock, 0, 18, 11f, true);
            top.Resize += (s, e) => lblClock.Left = top.Width - lblClock.Width - 16;

            var right = new PanelControl { Dock = DockStyle.Right, Width = 360 };
            int y = 14;
            Func<string, LabelControl, float, int> row = (cap, val, size) =>
            {
                var c = new LabelControl { Text = cap, Location = new Point(14, y + 4) };
                c.Appearance.Font = new Font("Tahoma", 10f);
                val.AutoSizeMode = LabelAutoSizeMode.None;
                val.Size = new Size(200, (int)(size * 2.2f));
                val.Location = new Point(146, y);
                val.Appearance.Font = new Font("Tahoma", size, FontStyle.Bold);
                val.Appearance.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                right.Controls.Add(c); right.Controls.Add(val);
                y += (int)(size * 2.2f) + 8;
                return y;
            };
            row("TOTAL", lblTotal, 26f);
            row("Items", lblItems, 12f);
            row("VATable sales", lblVatable, 12f);
            row("VAT (12%)", lblVat, 12f);
            row("Discount", lblDiscount, 12f);
            row("VAT-exempt", lblExempt, 12f);
            row("Price level", lblLevel, 12f);
            lblMessage.AutoSizeMode = LabelAutoSizeMode.Vertical;
            lblMessage.Width = 330;
            lblMessage.Location = new Point(14, y + 10);
            lblMessage.Appearance.Font = new Font("Tahoma", 9.5f);
            right.Controls.Add(lblMessage);
            var keys = new LabelControl
            {
                Text = "Enter scan    F2 qty    F3 search\nF4 price level    F5 refresh / sync\nF6 discount    F7 hold / recall\n" +
                       "Del remove line    F8 clear sale\nF9 void    F10 PAY    F11 reprint\nF12 retry\n" +
                       "Ctrl+X X-reading    Ctrl+Z close shift (Z)\nCtrl+D no-sale drawer    Ctrl+R reprint Z\nCtrl+T return / refund    Ctrl+P supervisors",
                Dock = DockStyle.Bottom, AutoSizeMode = LabelAutoSizeMode.Vertical, Padding = new Padding(12)
            };
            keys.Appearance.Font = new Font("Tahoma", 9f);
            keys.Appearance.ForeColor = Color.DimGray;
            right.Controls.Add(keys);

            var bottom = new PanelControl { Dock = DockStyle.Bottom, Height = 70 };
            var lblQtyCap = new LabelControl { Text = "Qty", Location = new Point(12, 24) };
            lblQtyCap.Appearance.Font = new Font("Tahoma", 11f);
            txtQty.Location = new Point(50, 14); txtQty.Width = 120;
            txtQty.Properties.Appearance.Font = new Font("Tahoma", 16f, FontStyle.Bold);
            txtQty.Properties.Appearance.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
            txtQty.Text = "1";
            var lblScanCap = new LabelControl { Text = "Scan / code", Location = new Point(190, 24) };
            lblScanCap.Appearance.Font = new Font("Tahoma", 11f);
            txtScan.Location = new Point(290, 14);
            txtScan.Width = 420;
            txtScan.Properties.Appearance.Font = new Font("Tahoma", 16f, FontStyle.Bold);
            txtScan.KeyDown += (s, e) =>
            {
                if (e.KeyCode != Keys.Enter) return;
                e.Handled = true; e.SuppressKeyPress = true;
                string code = txtScan.Text;
                txtScan.Text = "";
                Scan(code);
            };
            var btnPay = new SimpleButton { Text = "PAY (F10)", Location = new Point(730, 12), Size = new Size(140, 44) };
            btnPay.Appearance.Font = new Font("Tahoma", 13f, FontStyle.Bold);
            btnPay.Click += (s, e) => Pay();
            var btnSearch = new SimpleButton { Text = "Search (F3)", Location = new Point(880, 12), Size = new Size(110, 44) };
            btnSearch.Click += (s, e) => Search();
            bottom.Controls.AddRange(new Control[] { lblQtyCap, txtQty, lblScanCap, txtScan, btnPay, btnSearch });

            view = new GridView(grid);
            grid.MainView = view;
            view.OptionsBehavior.Editable = false;
            view.OptionsView.ShowGroupPanel = false;
            view.OptionsCustomization.AllowSort = false;
            view.OptionsCustomization.AllowFilter = false;
            view.OptionsSelection.EnableAppearanceFocusedCell = false;
            view.Appearance.Row.Font = new Font("Tahoma", 13f);
            view.Appearance.HeaderPanel.Font = new Font("Tahoma", 10f, FontStyle.Bold);
            view.RowHeight = 30;
            // columns added explicitly: PopulateColumns() creates none while the grid isn't on a shown form yet (constructor),
            // which made Columns["LineNo"] null here. ProductCode, Barcode, VAT / discount details stay on the bound line only.
            Col(view, "LineNo", "#", 40);
            Col(view, "Description", "Description", 420);
            Col(view, "Qty", "Qty", 90);
            Col(view, "PriceLevel", "Level", 70);
            Col(view, "UnitPrice", "Price", 110);
            Col(view, "LineDiscount", "Discount", 100);
            Col(view, "LineTotal", "Amount", 120);
            Col(view, "IsVat", "VAT", 50);
            Col(view, "DiscountCode", "Disc.", 70);
            grid.DataSource = _cart;
            Num(view, "Qty", "N3"); Num(view, "UnitPrice", "N2"); Num(view, "LineTotal", "N2"); Num(view, "LineDiscount", "N2");

            Controls.Add(grid);
            Controls.Add(right);
            Controls.Add(bottom);
            Controls.Add(top);
            grid.BringToFront();

            clock.Tick += (s, e) => lblClock.Text = DateTime.Now.ToString("ddd yyyy-MM-dd  HH:mm:ss");
        }

        private static void Place(Control parent, LabelControl l, int x, int y, float size, bool bold)
        {
            l.Location = new Point(x, y);
            l.Appearance.Font = new Font("Tahoma", size, bold ? FontStyle.Bold : FontStyle.Regular);
            parent.Controls.Add(l);
        }

        private static void Col(GridView v, string field, string caption, int width)
        {
            var c = v.Columns.AddVisible(field, caption);
            c.Width = width;
        }

        private static void Num(GridView v, string field, string fmt)
        {
            var c = v.Columns[field];
            if (c == null) return;
            c.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            c.DisplayFormat.FormatString = fmt;
            c.AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
            c.AppearanceCell.Options.UseTextOptions = true;
            c.AppearanceHeader.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
            c.AppearanceHeader.Options.UseTextOptions = true;
        }

        // ── start / stop ───────────────────────────────────────────────
        protected override void OnLoad(EventArgs e)
        {
            base.OnLoad(e);
            try
            {
                _store = new PosLocalStore();
                _store.EnsureDatabase();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show("POS V2 can't open this terminal's local database:\n\n" + ex.Message +
                                    "\n\nCheck the local SQL Server and the POS V2 settings (HKCU\\AAITCRE\\POSV2).", "POS V2",
                                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                BeginInvoke(new Action(Close));
                return;
            }

            lblCashier.Text = "Cashier: " + (Login.Fullname ?? Login.isglobalUserID) + "    Terminal: " + PosV2Config.TerminalCode;
            ReloadLocalData();
            UpdateTotals();

            _sync = new PosSyncService(_store, SynchronizationContext.Current);
            _sync.StatusChanged += (s, st) => ShowStatus(st);
            _sync.MasterDataRefreshed += (s, a) => ReloadLocalData();
            _sync.Start();

            try
            {
                if (!string.IsNullOrWhiteSpace(PosV2Config.ScalePort))
                {
                    _scale = new PosScale();
                    _scale.WeightChanged += w => BeginInvoke(new Action(() => { if (!txtQty.Focused && w > 0) txtQty.Text = w.ToString("0.###", CultureInfo.InvariantCulture); }));
                    _scale.Open(PosV2Config.ScalePort);
                }
            }
            catch (Exception ex) { Say("Scale not available (" + PosV2Config.ScalePort + "): " + ex.Message, true); }

            try
            {
                if (!string.IsNullOrWhiteSpace(PosV2Config.PolePort))
                {
                    _pole = new PosDisplayPole();
                    _pole.Open(PosV2Config.PolePort, PosV2Config.PoleBaud);
                    _pole.Welcome(_branchName);
                }
            }
            catch (Exception ex) { _pole = null; Say("Display pole not available (" + PosV2Config.PolePort + "): " + ex.Message, true); }

            clock.Tick += (s, a) => { if (_shiftPending) EnsureShift(); };   // the shift prompt waits until no other window is up
            clock.Start();
            txtScan.Focus();
            _shiftPending = _ready;
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (_cart.Count > 0 && _store != null)
            {
                if (e.CloseReason == CloseReason.UserClosing)
                {
                    // discarding the sale on screen is a cleared sale: same approval and Z-reading count as F8
                    if (XtraMessageBox.Show("There is a sale on screen that is not paid. Discard it (needs a supervisor)?\n\nNo = keep the window open (F7 holds it).",
                                            "POS V2", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes || !ClearSaleApproved())
                    {
                        e.Cancel = true;
                        return;
                    }
                }
                else
                {
                    // Windows shutdown / log-off: nobody to ask, so the sale is held (F7 recalls it)
                    try { _store.SaveHold("Held at shutdown " + DateTime.Now.ToString("MM-dd HH:mm"), Login.isglobalUserID, _priceLevel, _cart.ToList(), BuildSale().Discounts, _cancelledCount, _cancelledAmount); }
                    catch (Exception) { }
                }
            }
            clock.Stop();
            _scale?.Dispose();
            _pole?.Dispose();
            _sync?.Dispose();   // lets an upload in progress finish
            base.OnFormClosing(e);
        }

        private void ReloadLocalData()
        {
            try
            {
                _products = _store.LoadProducts();
                _byCode = _products.GroupBy(p => p.ProductCode, StringComparer.OrdinalIgnoreCase).ToDictionary(g => g.Key, g => g.First(), StringComparer.OrdinalIgnoreCase);
                _byBarcode = _products.Where(p => !string.IsNullOrWhiteSpace(p.Barcode)).ToLookup(p => p.Barcode.Trim(), StringComparer.OrdinalIgnoreCase);
                _stock = _store.LoadStock();
                _discountTypes = _store.LoadDiscountTypes();
                _supervisors = _store.LoadSupervisors();
                _customers = _store.LoadCustomers();
                _branchName = _store.GetMeta("BranchName") ?? "";
                PosReceiptPrinter.Bir = _store.LoadBirInfo();   // phase 5: BIR header / footer of every slip
                var term = _store.GetTerminal();
                lblBranch.Text = (term == null ? PosV2Config.BranchCode : term.BranchCode) + " " + _branchName +
                                 (term == null ? "    (terminal not registered yet)" : "    OR series " + term.ORPrefix) +
                                 (PosReceiptPrinter.Bir.Registered ? "    BIR: TIN " + PosReceiptPrinter.Bir.TIN : "    (not linked to its BIR registration: POSV2 BIRMachine)");
                bool wasReady = _ready;
                _ready = term != null && _products.Count > 0;
                _shift = _store.GetOpenShift();
                ShowShift();
                if (!_ready)
                    Say(term == null ? "Waiting for the first connection to the server to register this terminal and load products."
                                     : "Waiting for the product list from the server.", true);
                else if (!wasReady && IsHandleCreated && Visible) _shiftPending = true;   // first time ready since the window opened (the clock asks)
            }
            catch (Exception ex) { Say("Local data: " + ex.Message, true); }
        }

        // ── phase 3: shifts ────────────────────────────────────────────
        private bool MyShift => _shift != null && string.Equals(_shift.CashierUserID, Login.isglobalUserID ?? "", StringComparison.OrdinalIgnoreCase);

        private void ShowShift()
        {
            if (_shift == null) { lblShift.Text = "No shift open: Ctrl+Z opens one (cash beginning)"; lblShift.ForeColor = Color.Firebrick; return; }
            lblShift.Text = "Shift Z#" + _shift.ZNo + " of " + (_shift.CashierName ?? _shift.CashierUserID) + " since " + _shift.OpenedAt.ToString("MM-dd HH:mm") +
                            "    cash beginning " + _shift.BeginningCash.ToString("N2") + (MyShift ? "" : "    (not yours: close it with Ctrl+Z to sell)");
            lblShift.ForeColor = MyShift ? Color.Empty : Color.Firebrick;
        }

        // Asks for the cash beginning when no shift is open (works offline: the shift is queued like a sale).
        private void EnsureShift()
        {
            if (_askingShift || !_ready || _store == null) return;
            // never stack the prompt on another window (a picker, the supervisor screen, a message): wait for the clock (UI review 4)
            if (Form.ActiveForm != this || !Enabled) { _shiftPending = true; return; }
            _shiftPending = false;
            _askingShift = true;
            try
            {
                _shift = _store.GetOpenShift();
                if (_shift == null)
                {
                    decimal? beg = PosAmountForm.Ask(this, "Open Shift", "Cash beginning (the change fund in the drawer) for " +
                                                     (Login.Fullname ?? Login.isglobalUserID) + ":", 0m);
                    if (beg == null) { Say("No shift open: selling needs a shift (Ctrl+Z opens one).", true); return; }
                    _shift = _store.OpenShift(Login.isglobalUserID ?? "", Login.Fullname, beg.Value);
                    _sync?.Nudge();
                    Say("Shift Z#" + _shift.ZNo + " opened with " + _shift.BeginningCash.ToString("N2") + ".", false);
                }
                else if (!MyShift)
                    Say("Shift Z#" + _shift.ZNo + " of " + (_shift.CashierName ?? _shift.CashierUserID) + " is still open on this terminal. " +
                        "Close it with Ctrl+Z (Z-reading) before selling.", true);
            }
            catch (Exception ex) { Say("Shift: " + ex.Message, true); }
            finally { _askingShift = false; ShowShift(); txtScan.Focus(); }
        }

        private string Approve(string purpose) => PosApprovalForm.Ask(this, _supervisors, purpose);

        // Ctrl+X: the shift so far; nothing is closed. It shows the expected cash, so it needs a supervisor:
        // otherwise a cashier could read it and type it at the blind Z count (UI review 1).
        private void XReading()
        {
            try
            {
                if (_shift == null) { Say("No shift open.", true); return; }
                string approver = Approve("X-reading of shift Z#" + _shift.ZNo + " (shows the expected cash)");
                if (approver == null) return;
                PosReceiptPrinter.PrintReading(_store.ComputeReading(_shift.ShiftGuid), _branchName, PosV2Config.TerminalCode, false, false);
                Say("X-reading printed for shift Z#" + _shift.ZNo + ".", false);
            }
            catch (Exception ex) { Say("X-reading failed: " + ex.Message, true); }
            finally { txtScan.Focus(); }
        }

        // Ctrl+Z: the Z-reading closes the shift with the cash counted (blind count: the expected cash shows only after).
        private void CloseShift()
        {
            try
            {
                if (_shift == null) { EnsureShift(); return; }
                if (_cart.Count > 0) { Say("Pay, hold (F7) or clear (F8) the sale on screen first.", true); return; }
                int held = _store.ListHolds().Count;
                if (held > 0 && XtraMessageBox.Show(held + " held sale(s) are on this terminal; they stay held into the next shift.\nClose the shift anyway?",
                                                    "Close Shift", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
                string approver = null;
                if (!MyShift)
                {
                    approver = Approve("Close shift Z#" + _shift.ZNo + " of " + (_shift.CashierName ?? _shift.CashierUserID) + " (another cashier's shift)");
                    if (approver == null) return;
                }
                decimal? counted = PosAmountForm.Ask(this, "Close Shift (Z-reading)", "Count the cash in the drawer, beginning cash included, and type the total:", 0m);
                if (counted == null) return;
                if (XtraMessageBox.Show("Close shift Z#" + _shift.ZNo + " with " + counted.Value.ToString("N2") + " counted?\nNo more sales or voids on this shift after this.",
                                        "Close Shift", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;

                var rd = _store.CloseShift(_shift.ShiftGuid, counted.Value, Login.isglobalUserID ?? "", approver);
                _sync?.Nudge();
                decimal os = counted.Value - rd.ExpectedCash;
                try { PosReceiptPrinter.PrintReading(rd, _branchName, PosV2Config.TerminalCode, true, false); }
                catch (Exception ex) { Say("Shift closed, but the Z-reading didn't print: " + ex.Message + " (Ctrl+R reprint)", true); }
                XtraMessageBox.Show("Shift Z#" + rd.Shift.ZNo + " closed.\n\nExpected cash: " + rd.ExpectedCash.ToString("N2") + "\nCounted: " + counted.Value.ToString("N2") +
                                    "\n" + (os < 0 ? "SHORT: " : os > 0 ? "OVER: " : "Over / short: ") + Math.Abs(os).ToString("N2"),
                                    "Z-reading", MessageBoxButtons.OK, os == 0 ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
                _shift = null;
                ShowShift();
                EnsureShift();   // the next cashier (or the same one) opens a new shift
            }
            catch (Exception ex) { Say("Close shift failed: " + ex.Message, true); }
            finally { txtScan.Focus(); }
        }

        // Ctrl+R: reprint one of the last Z-readings.
        private void ReprintZ()
        {
            try
            {
                var shifts = _store.RecentClosedShifts(30);
                if (shifts.Count == 0) { Say("No closed shift yet.", true); return; }
                var pick = PosListPickerForm.Pick(this, "Reprint a Z-reading", shifts, x => new { Z = x.ZNo, Cashier = x.CashierName ?? x.CashierUserID, Opened = x.OpenedAt, Closed = x.ClosedAt, Counted = x.CountedCash });
                if (pick == null) return;
                PosReceiptPrinter.PrintReading(_store.ComputeReading(pick.ShiftGuid), _branchName, PosV2Config.TerminalCode, true, true);
                Say("Z-reading " + pick.ZNo + " reprinted.", false);
            }
            catch (Exception ex) { Say("Reprint failed: " + ex.Message, true); }
            finally { txtScan.Focus(); }
        }

        // Ctrl+D: open the drawer without a sale (counted on the Z-reading).
        private void NoSaleDrawer()
        {
            try
            {
                if (_shift == null || !MyShift) { Say("Open your shift first.", true); return; }
                if (!PosCashDrawer.Enabled) { Say("No cash drawer is set up on this terminal (POSV2 DrawerKick).", true); return; }
                string reason = XtraInputBox.Show("Reason for opening the drawer without a sale:", "No-sale drawer", "");
                if (string.IsNullOrWhiteSpace(reason)) return;
                string approver = Approve("Open the cash drawer without a sale: " + reason.Trim());
                if (approver == null) return;
                // recorded first: an opening that can't be logged doesn't happen (UI review 8)
                _store.AddShiftEvent(_shift.ShiftGuid, "DRAWER", 0, 0m, Login.isglobalUserID, approver, reason.Trim());
                PosCashDrawer.Open();
                Say("Drawer opened (approved by " + approver + ").", false);
            }
            catch (Exception ex) { Say("Drawer: " + ex.Message, true); }
            finally { txtScan.Focus(); }
        }

        // Ctrl+T: a return / refund of a posted sale (any earlier shift or terminal of the branch), with a supervisor's PIN.
        private void ReturnSale()
        {
            try
            {
                if (_store == null) return;
                if (!MyShift) { Say("Open your own shift first: the refund comes out of your drawer.", true); return; }
                if (_cart.Count > 0) { Say("Pay, hold (F7) or clear (F8) the sale on screen first.", true); return; }
                var rt = PosReturnForm.Ask(this, _store, PosV2Config.BranchCode, () => _sync != null && _sync.IsOnline);
                if (rt == null) return;
                rt.ApprovedBy = Approve("Return " + rt.Lines.Count + " line(s) of OR " + rt.OrigORNo + ": refund " + rt.NetAmount.ToString("N2") +
                                        (rt.CashRefund > 0 ? " (cash " + rt.CashRefund.ToString("N2") + ")" : "") + " - " + rt.Reason);
                if (rt.ApprovedBy == null) return;
                rt.ShiftGuid = _shift.ShiftGuid;
                rt.CashierUserID = Login.isglobalUserID ?? "";
                rt.CashierName = Login.Fullname;
                rt.ReturnDateTime = DateTime.Now;
                rt.SavedAt = rt.ReturnDateTime;
                _store.SaveReturn(rt);
                _sync?.Nudge();
                if (rt.CashRefund > 0)
                    try { PosCashDrawer.Open(); }
                    catch (Exception ex) { Say("Return " + rt.ReturnNo + " saved, but the drawer didn't open: " + ex.Message, true); }
                _pole?.ShowLeftRight("REFUND", rt.NetAmount.ToString("N2"), "CASH", rt.CashRefund.ToString("N2"));
                try { PosReceiptPrinter.PrintReturn(rt, _branchName, PosV2Config.TerminalCode, false); }
                catch (Exception ex) { Say("Return " + rt.ReturnNo + " saved, but the slip didn't print: " + ex.Message, true); return; }
                Say("Return " + rt.ReturnNo + ": refund " + rt.NetAmount.ToString("N2") + "  (cash " + rt.CashRefund.ToString("N2") + ", card " +
                    rt.CardRefund.ToString("N2") + ", account " + rt.ChargeRefund.ToString("N2") + ")", false);
            }
            catch (Exception ex) { Say("Return failed: " + ex.Message, true); }
            finally { txtScan.Focus(); }
        }

        private void Supervisors()
        {
            if (_store == null) return;
            if (!PosSupervisorAdminForm.CurrentUserIsAdmin()) { Say("Only an admin can set POS supervisors.", true); return; }
            using (var f = new PosSupervisorAdminForm()) f.ShowDialog(this);
            _sync?.RequestMasterRefresh();   // pick the change up here at once
            txtScan.Focus();
        }

        private void PoleShowTotal(string line1Left, string line1Right)
        {
            if (_pole == null) return;
            var s = BuildSale();
            _pole.ShowLeftRight(line1Left, line1Right, "TOTAL", s.NetAmount.ToString("N2"));
        }

        private void ShowStatus(PosSyncStatus st)
        {
            lblStatus.Text = st.Online ? "● ONLINE" : "● OFFLINE (sales are kept on this terminal)";
            lblStatus.ForeColor = st.Online ? Color.SeaGreen : Color.Firebrick;
            lblQueue.Text = "To upload: " + st.Pending + (st.Failed > 0 ? "    Needs attention: " + st.Failed + " (F12 retry)" : "") +
                            (st.ProductsRefreshedAt.HasValue ? "    Products as of " + st.ProductsRefreshedAt.Value.ToString("MM-dd HH:mm") : "");
            lblQueue.ForeColor = st.Failed > 0 ? Color.Firebrick : Color.Empty;
            if (!_ready && st.Registered) ReloadLocalData();
            if (!string.IsNullOrEmpty(st.Message) && (st.Failed > 0 || !st.Online)) Say(st.Message, true);
            else if (!string.IsNullOrEmpty(st.Message) && st.Message.StartsWith("Shift closed")) Say("Server: " + st.Message, st.Message.Contains("not booked"));
        }

        private void Say(string text, bool warn)
        {
            lblMessage.Text = text;
            lblMessage.ForeColor = warn ? Color.DarkOrange : Color.Empty;
        }

        // ── keys ───────────────────────────────────────────────────────
        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            switch (keyData)
            {
                case Keys.F2: txtQty.Focus(); txtQty.SelectAll(); return true;
                case Keys.F3: Search(); return true;
                case Keys.F4: NextPriceLevel(); return true;
                case Keys.F5: _sync?.RequestMasterRefresh(); Say("Refreshing products and uploading…", false); return true;
                case Keys.Delete: if (!txtScan.Focused && !txtQty.Focused) { RemoveLine(); return true; } break;
                case Keys.F8: ClearSale(true); return true;
                case Keys.F10: Pay(); return true;
                case Keys.F6: Discount(); return true;
                case Keys.F7: HoldOrRecall(); return true;
                case Keys.F9: VoidSale(); return true;
                case Keys.F11: Reprint(); return true;
                case Keys.F12: RetryFailed(); return true;
                case Keys.Control | Keys.X: if (txtScan.ContainsFocus && txtScan.SelectionLength > 0) break; XReading(); return true;   // cut still works on selected text
                case Keys.Control | Keys.Z: if (txtScan.ContainsFocus && !string.IsNullOrEmpty(txtScan.Text)) break; CloseShift(); return true;   // undo still works while typing a code
                case Keys.Control | Keys.D: NoSaleDrawer(); return true;
                case Keys.Control | Keys.R: ReprintZ(); return true;
                case Keys.Control | Keys.P: Supervisors(); return true;
                case Keys.Control | Keys.T: ReturnSale(); return true;
            }
            return base.ProcessCmdKey(ref msg, keyData);
        }

        // ── selling ────────────────────────────────────────────────────
        private decimal ReadQty()
        {
            decimal q;
            return decimal.TryParse(txtQty.Text.Replace(",", "").Trim(), NumberStyles.Number, CultureInfo.InvariantCulture, out q) && q > 0
                ? Math.Round(q, 3, MidpointRounding.AwayFromZero) : 1m;
        }

        private void Scan(string code)
        {
            code = (code ?? "").Trim();
            if (code.Length == 0) return;
            if (!_ready) { Say("Not ready yet: the terminal needs to connect to the server once.", true); return; }
            if (!MyShift) { Say(_shift == null ? "Open your shift first (Ctrl+Z, cash beginning)." : "The open shift is " + (_shift.CashierName ?? _shift.CashierUserID) + "'s: close it with Ctrl+Z first.", true); return; }

            decimal qty = ReadQty();
            int star = code.IndexOf('*');
            if (star > 0)
            {
                decimal q;
                if (decimal.TryParse(code.Substring(0, star), NumberStyles.Number, CultureInfo.InvariantCulture, out q) && q > 0) qty = q;
                code = code.Substring(star + 1).Trim();
            }

            var matches = _byBarcode[code].ToList();
            PosProduct byCode;
            if (matches.Count == 0 && _byCode.TryGetValue(code, out byCode)) matches.Add(byCode);
            if (matches.Count == 0) { System.Media.SystemSounds.Beep.Play(); Say("Not found: " + code + "   (F3 search, F5 refresh products)", true); return; }

            var product = matches.Count == 1 ? matches[0] : PosProductSearchForm.Pick(this, matches, "Barcode " + code + " belongs to " + matches.Count + " products: pick one");
            if (product != null) AddLine(product, code, qty);
            txtScan.Focus();
        }

        private void Search()
        {
            if (!_ready) { Say("Not ready yet: the terminal needs to connect to the server once.", true); return; }
            if (!MyShift) { Say(_shift == null ? "Open your shift first (Ctrl+Z, cash beginning)." : "The open shift is " + (_shift.CashierName ?? _shift.CashierUserID) + "'s: close it with Ctrl+Z first.", true); return; }
            var product = PosProductSearchForm.Pick(this, _products, "Search products");
            if (product != null) AddLine(product, product.Barcode, ReadQty());
            txtScan.Focus();
        }

        private void AddLine(PosProduct p, string scanned, decimal qty)
        {
            decimal price = PosPricingService.UnitPrice(p, _priceLevel);
            string level = _priceLevel;
            if (price <= 0)
            {
                string typed = XtraInputBox.Show(p.Description + " has no " + _priceLevel + " price.\nEnter the selling price:", "Price", "");
                decimal tp;
                if (string.IsNullOrWhiteSpace(typed) ||
                    !decimal.TryParse(typed.Replace(",", "").Trim(), NumberStyles.Number, CultureInfo.InvariantCulture, out tp) || tp <= 0)
                    return;
                price = PosPricingService.R2(tp);
                level = "MANUAL";
            }

            var line = new PosCartLine
            {
                ProductCode = p.ProductCode, Barcode = string.IsNullOrWhiteSpace(scanned) ? p.Barcode : scanned, Description = p.Description,
                Qty = qty, PriceLevel = level, UnitPrice = price, IsVatItem = p.IsVat
            };
            PosPricingService.PriceLine(line);
            _cart.Add(line);
            PosPricingService.Renumber(_cart);
            view.FocusedRowHandle = view.GetRowHandle(_cart.Count - 1);
            txtQty.Text = "1";
            UpdateTotals();

            // stock warning from the downloaded copy (the sale is still allowed: the server is the authority)
            decimal avail;
            decimal inCart = _cart.Where(l => string.Equals(l.ProductCode, p.ProductCode, StringComparison.OrdinalIgnoreCase)).Sum(l => l.Qty);
            if (!_stock.TryGetValue(p.ProductCode, out avail)) Say(p.Description + ": no stock on record for this branch (the sale is allowed).", true);
            else if (inCart > avail) Say(p.Description + ": only " + avail.ToString("0.###") + " in stock on record (the sale is allowed).", true);
            else Say(p.Description + "  " + qty.ToString("0.###") + " x " + price.ToString("N2"), false);
            PoleShowTotal(p.Description, line.LineTotal.ToString("N2"));
        }

        // Del: the line comes off the sale; it is counted as a cancelled line on the sale (Z-reading, phase 3).
        private void RemoveLine()
        {
            int i = view.GetDataSourceRowIndex(view.FocusedRowHandle);
            if (i < 0 || i >= _cart.Count) return;
            _cancelledCount++;
            _cancelledAmount += _cart[i].LineTotal;
            _cart.RemoveAt(i);
            PosPricingService.Renumber(_cart);
            view.RefreshData();
            UpdateTotals();
            txtScan.Focus();
        }

        // F8: the whole sale off the screen. Phase 3: needs a supervisor and is counted on the Z-reading.
        private void ClearSale(bool ask)
        {
            if (_cart.Count == 0) return;
            if (ask && XtraMessageBox.Show("Clear the sale on screen?", "POS V2", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            ClearSaleApproved();
            txtScan.Focus();
        }

        // The supervisor's PIN, then the cleared sale on the Z-reading (with the lines already removed from it), then off the screen.
        // Returns false (nothing changed) when not approved or not recorded.
        private bool ClearSaleApproved()
        {
            var s = BuildSale();
            if (_shift == null) { Say("No shift open.", true); return false; }
            string approver = Approve("Clear the sale on screen: " + _cart.Count + " line(s), " + s.NetAmount.ToString("N2"));
            if (approver == null) return false;
            try { _store.AddShiftEvent(_shift.ShiftGuid, "CLEARED", _cart.Count, s.NetAmount, Login.isglobalUserID, approver, null, _cancelledCount, _cancelledAmount); }
            catch (Exception ex) { Say("The sale was not cleared: " + ex.Message, true); return false; }
            ResetSale();
            Say("Sale cleared (approved by " + approver + ").", false);
            return true;
        }

        private void ResetSale()
        {
            _cart.Clear();
            _discounts.Clear();
            _discountApprovedBy = null;
            _cancelledCount = 0;
            _cancelledAmount = 0m;
            _priceLevel = "MAIN";
            UpdateTotals();
        }

        // phase 3: a discount type that needs approval on the sale (also after a recall: holds don't keep the approver)
        // only discounts a line still carries (a removed line's discount is dropped at payment); a code missing from this
        // terminal's list counts as needing approval (UI review 2 / 3)
        private bool NeedsDiscountApproval() =>
            _discounts.Any(d => _cart.Any(l => l.DiscNo == d.DiscNo) &&
                                !_discountTypes.Any(t => t.DiscountCode == d.DiscountCode && !t.RequiresApproval));

        private void NextPriceLevel()
        {
            int i = Array.IndexOf(PosPricingService.PriceLevels, _priceLevel);
            _priceLevel = PosPricingService.PriceLevels[(i + 1) % PosPricingService.PriceLevels.Length];
            UpdateTotals();
            Say("Price level for the next items: " + _priceLevel, false);
        }

        private PosSale BuildSale()
        {
            var s = new PosSale
            {
                SaleGuid = Guid.NewGuid(), CashierUserID = Login.isglobalUserID ?? "", CashierName = Login.Fullname,
                CancelledLineCount = _cancelledCount, CancelledLineAmount = _cancelledAmount
            };
            foreach (var l in _cart) s.Lines.Add(l);
            foreach (var d in _discounts)
                s.Discounts.Add(new PosSaleDiscount
                {
                    DiscNo = d.DiscNo, DiscountCode = d.DiscountCode, Name = d.Name, Percent = d.Percent,
                    CustomerName = d.CustomerName, IDNo = d.IDNo, TIN = d.TIN, Remarks = d.Remarks
                });
            PosPricingService.Total(s);
            return s;
        }

        private void UpdateTotals()
        {
            var s = BuildSale();
            lblTotal.Text = s.NetAmount.ToString("N2");
            lblItems.Text = _cart.Count.ToString();
            lblDiscount.Text = s.DiscountAmount.ToString("N2");
            lblVatable.Text = s.VatableSales.ToString("N2");
            lblVat.Text = s.VatAmount.ToString("N2");
            lblExempt.Text = s.VatExemptSales.ToString("N2");
            lblLevel.Text = _priceLevel;
        }

        // ── F6 discount ────────────────────────────────────────────────
        private void Discount()
        {
            if (_cart.Count == 0) { Say("Add the items first.", true); return; }
            if (_discountTypes.Count == 0) { Say("No discount types yet: they download with the products (F5).", true); return; }
            int fi = view.GetDataSourceRowIndex(view.FocusedRowHandle);
            var focused = fi >= 0 && fi < _cart.Count ? _cart[fi] : null;

            var r = PosDiscountForm.Ask(this, _discountTypes, focused == null ? null : focused.Description);
            if (r == null) { txtScan.Focus(); return; }

            if (r.RemoveAll)
            {
                foreach (var l in _cart) PosPricingService.ClearDiscount(l);
                _discounts.Clear();
                _discountApprovedBy = null;
                view.RefreshData(); UpdateTotals();
                Say("Discounts removed.", false);
                txtScan.Focus();
                return;
            }

            var targets = r.AllLines ? _cart.Where(l => l.DiscNo == null).ToList()
                                     : (focused == null ? new List<PosCartLine>() : new List<PosCartLine> { focused });
            if (targets.Count == 0) { Say(r.AllLines ? "Every line already has a discount (remove them first)." : "Highlight a line first.", true); return; }
            if (r.Type.RequiresApproval)
            {
                string who = Approve(r.Type.Name + (r.Type.Kind == "AMOUNT" ? " " + r.Amount.ToString("N2") : " " + r.Percent.ToString("0.##") + "%") +
                                     " on " + targets.Count + " line(s)");
                if (who == null) { txtScan.Focus(); return; }
                _discountApprovedBy = who;
            }

            foreach (var l in targets) PosPricingService.ClearDiscount(l);   // a line carries one discount
            int discNo = (_discounts.Count == 0 ? 0 : _discounts.Max(d => d.DiscNo)) + 1;
            if (r.Type.Kind == "AMOUNT")
            {
                if (!PosPricingService.ApplyAmount(targets, r.Type, r.Amount, discNo))
                {
                    foreach (var l in targets) PosPricingService.ClearDiscount(l);
                    Say("The discount is more than the lines are worth.", true);
                    view.RefreshData(); UpdateTotals();
                    return;
                }
            }
            else PosPricingService.ApplyPercent(targets, r.Type, r.Percent, discNo);

            _discounts.Add(new PosSaleDiscount
            {
                DiscNo = discNo, DiscountCode = r.Type.DiscountCode, Name = r.Type.Name, Percent = r.Type.Kind == "AMOUNT" ? 0m : r.Percent,
                CustomerName = NullIfEmpty(r.CustomerName), IDNo = NullIfEmpty(r.IDNo), TIN = NullIfEmpty(r.TIN), Remarks = NullIfEmpty(r.Remarks)
            });
            _discounts.RemoveAll(d => !_cart.Any(l => l.DiscNo == d.DiscNo));   // a replaced discount with no line left
            view.RefreshData();
            UpdateTotals();
            Say(r.Type.Name + " applied to " + targets.Count + " line(s).", false);
            txtScan.Focus();
        }

        private static string NullIfEmpty(string s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

        // ── F7 hold / recall (this terminal only; no OR number until paid) ──
        private void HoldOrRecall()
        {
            try
            {
                if (_cart.Count > 0)
                {
                    string name = XtraInputBox.Show("Name for this held sale (e.g. the customer):", "Hold sale", "Hold " + DateTime.Now.ToString("HH:mm"));
                    if (name == null) return;
                    _store.SaveHold(name, Login.isglobalUserID, _priceLevel, _cart.ToList(), BuildSale().Discounts, _cancelledCount, _cancelledAmount);
                    ResetSale();
                    Say("Sale held: " + name + "  (F7 with an empty sale to recall it)", false);
                }
                else
                {
                    var holds = _store.ListHolds();
                    var h = PosListPickerForm.Pick(this, "Held sales", holds, x => new { x.HoldID, x.Name, Held = x.CreatedAt, x.Lines, x.Total });
                    if (h == null) return;
                    var lines = new List<PosCartLine>(); var discs = new List<PosSaleDiscount>();
                    string level; int cc; decimal ca;
                    if (!_store.TakeHold(h.HoldID, lines, discs, out level, out cc, out ca)) { Say("That held sale is gone (recalled elsewhere?).", true); return; }
                    foreach (var l in lines) { PosPricingService.PriceLine(l); _cart.Add(l); }
                    _discounts.AddRange(discs);
                    _priceLevel = level; _cancelledCount = cc; _cancelledAmount = ca;
                    PosPricingService.Renumber(_cart);
                    view.RefreshData();
                    UpdateTotals();
                    Say("Recalled: " + h.Name, false);
                }
            }
            catch (Exception ex) { Say("Hold / recall failed: " + ex.Message, true); }
            finally { txtScan.Focus(); }
        }

        // ── F9 void a paid sale (phase 3: a sale of the open shift, with a supervisor's PIN) ──
        private void VoidSale()
        {
            try
            {
                string me = Login.isglobalUserID ?? "";
                if (_shift == null) { Say("No shift open: only sales of the open shift can be voided.", true); return; }
                var sales = _store.ShiftSales(_shift.ShiftGuid).Where(x => x.Status == "PAID").ToList();
                if (sales.Count == 0) { Say("No sale of this shift to void.", true); return; }
                var pick = PosListPickerForm.Pick(this, "Void a sale (this shift)", sales, x => new { x.ORNo, Time = x.SaleDateTime, Amount = x.NetAmount, Upload = x.SyncStatus });
                if (pick == null) return;
                string reason = XtraInputBox.Show("Reason for voiding OR " + pick.ORNo + " (" + pick.NetAmount.ToString("N2") + "):", "Void sale", "");
                if (string.IsNullOrWhiteSpace(reason)) return;
                string approver = Approve("Void OR " + pick.ORNo + " for " + pick.NetAmount.ToString("N2") + ": " + reason.Trim());
                if (approver == null) return;
                if (XtraMessageBox.Show("Void OR " + pick.ORNo + " for " + pick.NetAmount.ToString("N2") + "?\nThe stock is given back when the server gets the void.",
                                        "Void sale", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;

                _store.VoidSale(pick.SaleGuid, reason.Trim(), me, approver);
                _sync?.Nudge();
                var s = _store.LoadSale(pick.SaleGuid);
                try { PosReceiptPrinter.Print(s, _branchName, PosV2Config.TerminalCode, false); }
                catch (Exception ex) { Say("Voided, but the void slip didn't print: " + ex.Message, true); return; }
                Say("Voided OR " + pick.ORNo + ".", false);
            }
            catch (Exception ex) { Say("Void failed: " + ex.Message, true); }
            finally { txtScan.Focus(); }
        }

        private void Pay()
        {
            if (_cart.Count == 0) { Say("Nothing to pay.", true); return; }
            if (_shift == null) { EnsureShift(); if (_shift == null) return; }
            if (!MyShift) { Say("This terminal's open shift is " + (_shift.CashierName ?? _shift.CashierUserID) + "'s: close it with Ctrl+Z first.", true); return; }
            if (NeedsDiscountApproval() && string.IsNullOrEmpty(_discountApprovedBy))
            {
                _discountApprovedBy = Approve("A discount on this sale needs approval");
                if (_discountApprovedBy == null) { txtScan.Focus(); return; }
            }
            var sale = BuildSale();
            _pole?.ShowLeftRight("TOTAL", sale.NetAmount.ToString("N2"), "", "");
            var paid = PosPaymentForm.Ask(this, sale.NetAmount, _customers);
            if (paid == null) { txtScan.Focus(); return; }

            // phase 4: a charge over the credit limit (last downloaded balance + this terminal's unsent charges) needs a supervisor
            if (paid.Charge > 0)
            {
                // A credit limit of 0 = unlimited (user, 2026-10-13). For a customer with a limit, an unknown balance (lookup failed)
                // or a customer list older than a day (offline for long) needs approval too: the check fails closed (UI review B3)
                var c = paid.Customer;
                decimal owing = 0m; string why = null;
                if (c.CreditLimit > 0)
                {
                    try { owing = c.Balance + _store.UnsentCharges(c.CustomerKey); } catch (Exception) { why = "the balance can't be read"; }
                    DateTime asOf;
                    if (why == null && (!DateTime.TryParse(_store.GetMeta("CustomersRefreshedAt"), out asOf) || (DateTime.Now - asOf).TotalHours > 24))
                        why = "the customer list is more than a day old";
                    if (why == null && owing + paid.Charge > c.CreditLimit) why = "over the credit limit " + c.CreditLimit.ToString("N2") + " (owing " + owing.ToString("N2") + ")";
                }
                if (why != null)
                {
                    sale.CreditApprovedBy = Approve("Charge " + paid.Charge.ToString("N2") + " to " + c.Display + ": " + why);
                    if (sale.CreditApprovedBy == null) { txtScan.Focus(); return; }
                }
                sale.CustomerKey = c.CustomerKey;
                sale.CustomerName = c.CustomerName;
            }

            sale.AmountTendered = paid.Tendered;
            sale.ChangeAmount = paid.Change;
            sale.Payments.AddRange(paid.Payments);
            sale.SaleDateTime = DateTime.Now;
            sale.SavedAt = sale.SaleDateTime;
            sale.WasOffline = _sync == null || !_sync.IsOnline;
            sale.ShiftGuid = _shift.ShiftGuid;
            sale.DiscountApprovedBy = NeedsDiscountApproval() ? _discountApprovedBy : null;

            try { _store.SaveSale(sale); }
            catch (Exception ex)
            {
                XtraMessageBox.Show("The sale could NOT be saved on this terminal; nothing was recorded:\n\n" + ex.Message, "POS V2",
                                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            _sync?.Nudge();   // online: posted and deducted within seconds
            if (sale.Payments.Exists(p => p.PaymentType == "CASH"))
                try { PosCashDrawer.Open(); }
                catch (Exception ex) { Say("Sale " + sale.ORNo + " saved, but the drawer didn't open: " + ex.Message, true); }
            _pole?.ShowLeftRight("TOTAL", sale.NetAmount.ToString("N2"), "CHANGE", sale.ChangeAmount.ToString("N2"));
            try { PosReceiptPrinter.Print(sale, _branchName, PosV2Config.TerminalCode, false); }
            catch (Exception ex) { Say("Sale " + sale.ORNo + " saved, but the receipt didn't print: " + ex.Message + " (F11 reprint)", true); }

            Say("Paid: OR " + sale.ORNo + "    change " + sale.ChangeAmount.ToString("N2") + (sale.WasOffline ? "    (offline: uploads when back online)" : ""), false);
            ResetSale();
            txtScan.Focus();
        }

        // ── F11 reprint any of today's receipts (marked REPRINT) ────────
        private void Reprint()
        {
            try
            {
                var sales = _store.RecentSales(DateTime.Today);
                if (sales.Count == 0) { Say("No sale today to reprint.", true); return; }
                var pick = PosListPickerForm.Pick(this, "Reprint a receipt (today)", sales, x => new { x.ORNo, Time = x.SaleDateTime, Amount = x.NetAmount, x.Status });
                if (pick == null) return;
                var s = _store.LoadSale(pick.SaleGuid);
                PosReceiptPrinter.Print(s, _branchName, PosV2Config.TerminalCode, true);
                _store.AddReprint(pick.SaleGuid);
                Say("Reprinted OR " + s.ORNo, false);
            }
            catch (Exception ex) { Say("Reprint failed: " + ex.Message, true); }
            finally { txtScan.Focus(); }
        }

        private void RetryFailed()
        {
            try
            {
                int n = _store.RetryFailed();
                _sync?.Nudge();
                Say(n == 0 ? "Nothing needs attention." : n + " upload(s) sent to the queue again, in their original order (sales first, then the shift close).", false);
            }
            catch (Exception ex) { Say("Retry failed: " + ex.Message, true); }
        }
    }
}
