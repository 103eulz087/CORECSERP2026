using System;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Globalization;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraEditors.Controls;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.AccountingDevEx
{
    // ================================================================
    // BankReconForm v3
    //
    // CHANGES FROM v2:
    //
    // [1] SP names updated to match new header-based structure:
    //       sp_BankRecon_GetHeader  → sp_BankRecon_GetPeriod
    //         (returns 3 result sets: header, DIT rows, OC rows)
    //       sp_BankRecon_GetItems   → removed (merged into GetPeriod)
    //       sp_BankRecon_SaveHeader → unchanged name, new @HeaderID param
    //       sp_BankRecon_UpdateItem → sp_BankRecon_ResolveItem (for resolve)
    //                                 sp_BankRecon_SaveItem    (for add/edit)
    //
    // [2] LoadRecon() now calls ONE SP (sp_BankRecon_GetPeriod) that
    //     returns header + DIT + OC in three result sets.
    //     LoadHeader() and LoadItems() are merged into LoadPeriod().
    //
    // [3] _headerID field added — stored after load, passed to SaveHeader
    //     and LockPeriod calls. Eliminates repeated account+period lookups.
    //
    // [4] BtnResolve_Click now calls sp_BankRecon_ResolveItem
    //     (not sp_BankRecon_UpdateItem with DBNull params).
    //
    // [5] Lock Period button added to toolbar.
    //     Calls sp_BankRecon_LockPeriod. Form goes read-only when locked.
    //
    // [6] DIT and OC split into TWO grids side by side in the body panel.
    //     Previously a single grid showed all items mixed together.
    //     This matches the standard bank recon layout accountants expect.
    //
    // [7] Auto-inserted items (SourceModule IS NOT NULL) show a light
    //     blue row tint so accountant knows not to manually delete them.
    //
    // [8] BtnSaveHeader_Click now passes @HeaderID (not account+period).
    //     SP signature updated accordingly — see sp_BankRecon_SaveHeader.
    //
    // [9] Period DateEdit snaps to end-of-month on value change.
    //
    // [10] RefreshSummary() now reads from the two separate DataTables
    //      (dtDIT, dtOC) instead of scanning a single mixed grid.
    //
    // LAYOUT (unchanged from v2 — TableLayoutPanel, 5 rows):
    //   Row 0 (52px)   — Banner
    //   Row 1 (142px)  — Filter
    //   Row 2 (64px)   — Header (GL bal + bank stmt bal)
    //   Row 3 (*)      — Body: SplitContainer (grids | summary)
    //   Row 4 (44px)   — Toolbar
    // ================================================================

    public partial class BankReconForm : XtraForm
    {
        // ── Colours ──────────────────────────────────────────────────
        private static readonly Color C_DARK = Color.FromArgb(15, 17, 23);
        private static readonly Color C_SURFACE = Color.FromArgb(24, 28, 39);
        private static readonly Color C_CARD = Color.FromArgb(30, 35, 51);
        private static readonly Color C_BORDER = Color.FromArgb(42, 48, 80);
        private static readonly Color C_GOLD = Color.FromArgb(201, 168, 76);
        private static readonly Color C_TEXT = Color.FromArgb(232, 230, 224);
        private static readonly Color C_MUTED = Color.FromArgb(136, 145, 170);
        private static readonly Color C_DR = Color.FromArgb(107, 174, 214);
        private static readonly Color C_CR = Color.FromArgb(252, 141, 89);
        private static readonly Color C_OK = Color.FromArgb(116, 196, 118);
        private static readonly Color C_ERR = Color.FromArgb(251, 107, 75);
        private static readonly Color C_AUTO = Color.FromArgb(30, 60, 100); // auto-insert tint

        private static readonly Font F_MONO = new Font("Courier New", 9f);
        private static readonly Font F_SMALL = new Font("Segoe UI", 8.5f);
        private static readonly Font F_BOLD = new Font("Segoe UI", 9f, FontStyle.Bold);
        private static readonly Font F_TITLE = new Font("Georgia", 14f, FontStyle.Bold);

        // ── State ─────────────────────────────────────────────────────
        private string _branch = Login.assignedBranch;
        private string _account = "";
        private DateTime _period = DateTime.Today;
        private decimal _bookBal = 0m;
        private decimal _bankBal = 0m;
        private int _headerID = 0;       // [3] NEW — BankReconHeader.HeaderID
        private int _selDitID = 0;
        private int _selOcID = 0;
        private bool _isLocked = false;

        // DataTables — kept for RefreshSummary() [10]
        private DataTable _dtDIT = new DataTable();
        private DataTable _dtOC = new DataTable();

        // ── Controls ──────────────────────────────────────────────────
        private SearchLookUpEdit cmbBranch, cmbAccount;
        private DateEdit dtPeriod;
        private LabelControl lblBookBal;
        private TextEdit txtBankBal;
        private SimpleButton btnSaveHeader;

        // DIT grid
        private DevExpress.XtraGrid.GridControl gridDIT;
        private GridView viewDIT;

        // OC grid
        private DevExpress.XtraGrid.GridControl gridOC;
        private GridView viewOC;

        // Summary labels
        private LabelControl lblBankStmt, lblDIT, lblOC, lblAdjBank;
        private LabelControl lblBookSide, lblBCM, lblBDM, lblAdjBook;
        private LabelControl lblDiff;

        // Toolbar
        private SimpleButton btnAddDIT, btnAddOC,
                             btnResolveDIT, btnResolveOC,
                             btnDeleteDIT, btnDeleteOC,
                             btnAutoMatch, btnLock, btnPrint;
        private LabelControl lblStatus;

        public BankReconForm()
        {
            this.Text = "Bank Reconciliation";
            this.BackColor = C_DARK;
            this.ForeColor = C_TEXT;
            this.WindowState = FormWindowState.Maximized;
            this.MinimumSize = new Size(1100, 640);
            InitializeComponent();
            BuildUI();
            WireEvents();
            PopulateLookups();
            SetDefaultPeriod();
        }

        // ================================================================
        // MASTER LAYOUT
        // ================================================================
        private void BuildUI()
        {
            var tlp = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 1,
                RowCount = 5,
                BackColor = C_DARK,
                Padding = Padding.Empty,
                Margin = Padding.Empty,
                CellBorderStyle = TableLayoutPanelCellBorderStyle.None,
            };
            tlp.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
            tlp.RowStyles.Add(new RowStyle(SizeType.Absolute, 52f));  // 0 banner
            tlp.RowStyles.Add(new RowStyle(SizeType.Absolute, 142f));  // 1 filter
            tlp.RowStyles.Add(new RowStyle(SizeType.Absolute, 64f));  // 2 header
            tlp.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));  // 3 body
            tlp.RowStyles.Add(new RowStyle(SizeType.Absolute, 44f));  // 4 toolbar

            tlp.Controls.Add(BuildBanner(), 0, 0);
            tlp.Controls.Add(BuildFilter(), 0, 1);
            tlp.Controls.Add(BuildHeader(), 0, 2);
            tlp.Controls.Add(BuildBody(), 0, 3);
            tlp.Controls.Add(BuildToolbar(), 0, 4);

            this.Controls.Add(tlp);
        }

        // ── Row 0: Banner ─────────────────────────────────────────────
        private Panel BuildBanner()
        {
            var pnl = new Panel { Dock = DockStyle.Fill, BackColor = C_SURFACE };
            pnl.Controls.Add(new Panel { Dock = DockStyle.Left, Width = 3, BackColor = C_GOLD });
            pnl.Controls.Add(new Panel { Dock = DockStyle.Bottom, Height = 2, BackColor = C_GOLD });

            pnl.Controls.Add(new LabelControl
            {
                Text = "Bank Reconciliation",
                Font = F_TITLE,
                ForeColor = C_TEXT,
                AutoSizeMode = LabelAutoSizeMode.None,
                Location = new Point(14, 13),
                Size = new Size(340, 28),
                BackColor = Color.Transparent,
            });

            var lblBranch = new LabelControl
            {
                Text = $"Branch: {_branch}",
                Font = new Font("Courier New", 9f, FontStyle.Bold),
                ForeColor = C_GOLD,
                AutoSizeMode = LabelAutoSizeMode.None,
                Anchor = AnchorStyles.Top | AnchorStyles.Right,
                Size = new Size(160, 18),
                BackColor = Color.Transparent,
            };
            pnl.SizeChanged += (s, e) => lblBranch.Location = new Point(pnl.Width - 170, 17);
            pnl.Controls.Add(lblBranch);
            return pnl;
        }

        // ── Row 1: Filter ─────────────────────────────────────────────
        private Panel BuildFilter()
        {
            var pnl = new Panel
            {
                Dock = DockStyle.Fill,
                BackColor = C_CARD,
                Padding = new Padding(10, 8, 10, 6),
            };
            pnl.Controls.Add(new Panel { Dock = DockStyle.Bottom, Height = 1, BackColor = C_BORDER });

            var flow = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                FlowDirection = FlowDirection.LeftToRight,
                WrapContents = false,
                BackColor = Color.Transparent,
            };

            cmbBranch = new SearchLookUpEdit(); StyleLookUp(cmbBranch);
            cmbAccount = new SearchLookUpEdit(); StyleLookUp(cmbAccount);
            dtPeriod = new DateEdit(); StyleDate(dtPeriod);
            dtPeriod.Properties.DisplayFormat.FormatString = "yyyy-MM-dd";
            dtPeriod.Properties.EditFormat.FormatString = "yyyy-MM-dd";

            flow.Controls.Add(MakeFilterGroup("Branch", cmbBranch, 100));
            flow.Controls.Add(MakeFilterGroup("Bank GL Account", cmbAccount, 280));
            flow.Controls.Add(MakeFilterGroup("Period End (month-end)", dtPeriod, 140));

            var btnLoad = MakeBtn("▶  Load", C_GOLD, C_DARK);
            btnLoad.Click += (s, e) => LoadRecon();
            btnLoad.Margin = new Padding(4, 20, 0, 0);
            btnLoad.Size = new Size(90, 26);
            flow.Controls.Add(btnLoad);

            pnl.Controls.Add(flow);
            return pnl;
        }

        private Panel MakeFilterGroup(string caption, Control ctrl, int width)
        {
            var grp = new Panel
            {
                Width = width + 4,
                Height = 52,
                BackColor = Color.Transparent,
                Margin = new Padding(0, 4, 10, 0),
            };
            grp.Controls.Add(new LabelControl
            {
                Text = caption.ToUpper(),
                Font = new Font("Courier New", 7f, FontStyle.Bold),
                ForeColor = C_MUTED,
                AutoSizeMode = LabelAutoSizeMode.None,
                Location = new Point(0, 0),
                Size = new Size(width, 14),
                BackColor = Color.Transparent,
            });
            ctrl.Location = new Point(0, 16);
            ctrl.Size = new Size(width, 24);
            grp.Controls.Add(ctrl);
            return grp;
        }

        // ── Row 2: Header (GL balance + bank statement balance) ───────
        private Panel BuildHeader()
        {
            var pnl = new Panel
            {
                Dock = DockStyle.Fill,
                BackColor = C_SURFACE,
                Padding = new Padding(14, 10, 14, 8),
            };
            pnl.Controls.Add(new Panel { Dock = DockStyle.Bottom, Height = 1, BackColor = C_BORDER });

            var flow = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                FlowDirection = FlowDirection.LeftToRight,
                WrapContents = false,
                BackColor = Color.Transparent,
            };

            // GL book balance (read-only, computed from TicketDetails)
            var grpBook = new Panel { Width = 260, Height = 50, BackColor = Color.Transparent, Margin = new Padding(0, 0, 30, 0) };
            grpBook.Controls.Add(MakeCap("BALANCE PER GL (BOOK)", 260));
            lblBookBal = MakeValLabel("0.00", C_DR, 260);
            lblBookBal.Location = new Point(0, 16);
            grpBook.Controls.Add(lblBookBal);

            // Bank statement balance (editable)
            var grpBank = new Panel { Width = 360, Height = 50, BackColor = Color.Transparent };
            grpBank.Controls.Add(MakeCap("BALANCE PER BANK STATEMENT", 360));
            txtBankBal = new TextEdit { Location = new Point(0, 16), Size = new Size(180, 24), Font = F_MONO, Text = "0.00" };
            txtBankBal.Properties.Appearance.BackColor = C_CARD;
            txtBankBal.Properties.Appearance.ForeColor = C_TEXT;
            grpBank.Controls.Add(txtBankBal);

            btnSaveHeader = MakeBtn("💾  Save Balance", C_CARD, C_MUTED);
            btnSaveHeader.Location = new Point(188, 16);
            btnSaveHeader.Size = new Size(130, 24);
            btnSaveHeader.Appearance.BorderColor = C_BORDER;
            grpBank.Controls.Add(btnSaveHeader);

            flow.Controls.AddRange(new Control[] { grpBook, grpBank });
            pnl.Controls.Add(flow);
            return pnl;
        }

        private LabelControl MakeCap(string text, int width)
            => new LabelControl
            {
                Text = text,
                Font = new Font("Courier New", 7f, FontStyle.Bold),
                ForeColor = C_MUTED,
                AutoSizeMode = LabelAutoSizeMode.None,
                Location = new Point(0, 0),
                Size = new Size(width, 14),
                BackColor = Color.Transparent,
            };

        private LabelControl MakeValLabel(string text, Color color, int width)
            => new LabelControl
            {
                Text = text,
                Font = new Font("Courier New", 14f, FontStyle.Bold),
                ForeColor = color,
                AutoSizeMode = LabelAutoSizeMode.None,
                Size = new Size(width, 26),
                BackColor = Color.Transparent,
            };

        // ── Row 3: Body — two grids + summary ─────────────────────────
        // [6] Split into DIT grid | OC grid | summary panel
        private Control BuildBody()
        {
            // Outer split: grids (left 70%) | summary (right 30%)
            var outer = new SplitContainerControl
            {
                Dock = DockStyle.Fill,
                SplitterPosition = 820,
                BackColor = C_DARK,
            };
            outer.Panel1.BackColor = C_DARK;
            outer.Panel2.BackColor = C_SURFACE;

            // Inner split: DIT (top) | OC (bottom)
            var inner = new SplitContainerControl
            {
                Dock = DockStyle.Fill,
                Horizontal = true,        // horizontal splitter
                SplitterPosition = 300,
                BackColor = C_DARK,
            };
            inner.Panel1.BackColor = C_DARK;
            inner.Panel2.BackColor = C_DARK;

            // DIT grid
            inner.Panel1.Controls.Add(BuildGridPanel(
                "DEPOSITS IN TRANSIT",
                out gridDIT, out viewDIT));

            // OC grid
            inner.Panel2.Controls.Add(BuildGridPanel(
                "OUTSTANDING CHECKS",
                out gridOC, out viewOC));

            outer.Panel1.Controls.Add(inner);
            outer.Panel2.Controls.Add(BuildSummaryPanel());
            return outer;
        }

        private Panel BuildGridPanel(string title,
            out DevExpress.XtraGrid.GridControl grid,
            out GridView view)
        {
            var pnl = new Panel { Dock = DockStyle.Fill, BackColor = C_DARK };

            // Section header label
            var lblTitle = new LabelControl
            {
                Text = title,
                Font = new Font("Courier New", 8f, FontStyle.Bold),
                ForeColor = C_GOLD,
                AutoSizeMode = LabelAutoSizeMode.None,
                Dock = DockStyle.Top,
                Height = 20,
                BackColor = C_CARD,
            };
            pnl.Controls.Add(lblTitle);

            grid = new DevExpress.XtraGrid.GridControl { Dock = DockStyle.Fill, BackColor = C_DARK };
            view = new GridView(grid);

            // Appearance
            view.OptionsView.ShowGroupPanel = false;
            view.OptionsView.ShowIndicator = false;
            view.OptionsView.ShowFooter = true;
            view.OptionsView.EnableAppearanceEvenRow = true;
            view.OptionsBehavior.Editable = false;

            view.Appearance.HeaderPanel.BackColor = C_CARD;
            view.Appearance.HeaderPanel.ForeColor = C_GOLD;
            view.Appearance.HeaderPanel.Font = new Font("Courier New", 8f, FontStyle.Bold);
            view.Appearance.HeaderPanel.Options.UseBackColor = true;
            view.Appearance.HeaderPanel.Options.UseForeColor = true;
            view.Appearance.HeaderPanel.Options.UseFont = true;

            view.Appearance.Row.BackColor = C_DARK;
            view.Appearance.Row.ForeColor = C_TEXT;
            view.Appearance.Row.Options.UseBackColor = true;
            view.Appearance.Row.Options.UseForeColor = true;

            view.Appearance.EvenRow.BackColor = C_SURFACE;
            view.Appearance.EvenRow.Options.UseBackColor = true;

            view.Appearance.FocusedRow.BackColor = C_BORDER;
            view.Appearance.FocusedRow.ForeColor = C_TEXT;
            view.Appearance.FocusedRow.Options.UseBackColor = true;
            view.Appearance.FocusedRow.Options.UseForeColor = true;

            view.Appearance.FooterPanel.BackColor = C_CARD;
            view.Appearance.FooterPanel.ForeColor = C_GOLD;
            view.Appearance.FooterPanel.Font = new Font("Courier New", 8.5f, FontStyle.Bold);
            view.Appearance.FooterPanel.Options.UseBackColor = true;
            view.Appearance.FooterPanel.Options.UseForeColor = true;
            view.Appearance.FooterPanel.Options.UseFont = true;

            // [7] Row style for auto-inserted items
            view.RowCellStyle += (s, e) =>
            {
                var v = (GridView)s;
                if (e.RowHandle < 0) return;
                var isAuto = v.GetRowCellValue(e.RowHandle, "IsAutoInserted");
                if (isAuto != null && isAuto != DBNull.Value && Convert.ToBoolean(isAuto))
                {
                    e.Appearance.BackColor = C_AUTO;
                    e.Appearance.Options.UseBackColor = true;
                }
            };

            grid.MainView = view;
            pnl.Controls.Add(grid);  // grid added after label so it fills below it
            return pnl;
        }

        // ── Summary Panel ─────────────────────────────────────────────
        private Control BuildSummaryPanel()
        {
            var tlp = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 2,
                BackColor = C_SURFACE,
                Padding = new Padding(14, 12, 14, 12),
                CellBorderStyle = TableLayoutPanelCellBorderStyle.None,
            };
            tlp.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 60f));
            tlp.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 40f));

            int r = 0;
            LabelControl dummy = null;

            void Section(string text)
            {
                tlp.RowStyles.Add(new RowStyle(SizeType.Absolute, 22f));
                var lbl = new LabelControl
                {
                    Text = text.ToUpper(),
                    Font = new Font("Courier New", 7.5f, FontStyle.Bold),
                    ForeColor = C_GOLD,
                    Dock = DockStyle.Fill,
                    BackColor = Color.Transparent,
                    AutoSizeMode = LabelAutoSizeMode.None,
                };
                lbl.Appearance.TextOptions.VAlignment = DevExpress.Utils.VertAlignment.Center;
                tlp.Controls.Add(lbl, 0, r);
                tlp.Controls.Add(new Panel { BackColor = Color.Transparent }, 1, r);
                r++;
            }

            void Row(string caption, ref LabelControl val, Color color, bool isTotal = false)
            {
                int h = isTotal ? 32 : 24;
                tlp.RowStyles.Add(new RowStyle(SizeType.Absolute, h));

                var cap = new LabelControl
                {
                    Text = caption,
                    Font = isTotal ? F_BOLD : F_SMALL,
                    ForeColor = C_MUTED,
                    Dock = DockStyle.Fill,
                    BackColor = Color.Transparent,
                    AutoSizeMode = LabelAutoSizeMode.None,
                };
                cap.Appearance.TextOptions.VAlignment = DevExpress.Utils.VertAlignment.Center;

                val = new LabelControl
                {
                    Text = "0.00",
                    Font = isTotal ? new Font("Courier New", 12f, FontStyle.Bold) : F_MONO,
                    ForeColor = color,
                    Dock = DockStyle.Fill,
                    BackColor = Color.Transparent,
                    AutoSizeMode = LabelAutoSizeMode.None,
                };
                val.Appearance.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                val.Appearance.TextOptions.VAlignment = DevExpress.Utils.VertAlignment.Center;

                tlp.Controls.Add(cap, 0, r);
                tlp.Controls.Add(val, 1, r);
                r++;
            }

            void Spacer()
            {
                tlp.RowStyles.Add(new RowStyle(SizeType.Absolute, 8f));
                tlp.Controls.Add(new Panel { BackColor = Color.Transparent }, 0, r);
                tlp.Controls.Add(new Panel { BackColor = Color.Transparent }, 1, r);
                r++;
            }

            // Bank side
            Section("Bank Statement Side");
            Row("Balance per bank statement", ref lblBankStmt, C_TEXT);
            Row("Add: Deposits in transit", ref lblDIT, C_DR);
            Row("Less: Outstanding checks", ref lblOC, C_CR);
            Row("Adjusted Bank Balance", ref lblAdjBank, C_OK, isTotal: true);
            Spacer();

            // Book side
            Section("Book (GL) Side");
            Row("Balance per GL", ref lblBookSide, C_TEXT);
            Row("Add: Bank credit memos", ref lblBCM, C_DR);
            Row("Less: Bank debit memos / charges", ref lblBDM, C_CR);
            Row("Adjusted Book Balance", ref lblAdjBook, C_OK, isTotal: true);
            Spacer();

            // Difference
            Section("Difference (must be 0.00)");
            Row("", ref lblDiff, C_OK, isTotal: true);

            // Fill remaining
            tlp.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
            tlp.Controls.Add(new Panel { BackColor = Color.Transparent }, 0, r);
            tlp.Controls.Add(new Panel { BackColor = Color.Transparent }, 1, r);

            return tlp;
        }

        // ── Row 4: Toolbar ────────────────────────────────────────────
        private Panel BuildToolbar()
        {
            var pnl = new Panel { Dock = DockStyle.Fill, BackColor = C_CARD };
            pnl.Controls.Add(new Panel { Dock = DockStyle.Top, Height = 1, BackColor = C_BORDER });

            var flow = new FlowLayoutPanel
            {
                Dock = DockStyle.Left,
                FlowDirection = FlowDirection.LeftToRight,
                WrapContents = false,
                BackColor = Color.Transparent,
                AutoSize = true,
                Padding = new Padding(6, 6, 0, 6),
            };

            btnAddDIT = MakeBtn("＋ Add DIT", C_GOLD, C_DARK);
            btnAddOC = MakeBtn("＋ Add OC", Color.FromArgb(40, 60, 30), C_OK);
            btnResolveDIT = MakeBtn("✔ Resolve DIT", C_CARD, C_MUTED);
            btnResolveOC = MakeBtn("✔ Resolve OC", C_CARD, C_MUTED);
            btnDeleteDIT = MakeBtn("✖ Del DIT", Color.FromArgb(80, 20, 20), C_ERR);
            btnDeleteOC = MakeBtn("✖ Del OC", Color.FromArgb(80, 20, 20), C_ERR);
            btnAutoMatch = MakeBtn("⚡ Auto-Match", C_CARD, C_MUTED);
            btnLock = MakeBtn("🔒 Lock Period", C_CARD, C_GOLD);   // [5]
            btnPrint = MakeBtn("🖨 Print", C_CARD, C_MUTED);

            foreach (var b in new[] { btnAddDIT, btnAddOC,
                                      btnResolveDIT, btnResolveOC,
                                      btnDeleteDIT, btnDeleteOC,
                                      btnAutoMatch, btnLock, btnPrint })
            {
                b.Margin = new Padding(0, 0, 5, 0);
                b.AutoSize = true;
                b.Size = new Size(0, 30);
                flow.Controls.Add(b);
            }

            // Initially disabled until a row is selected
            btnResolveDIT.Enabled = false;
            btnResolveOC.Enabled = false;
            btnDeleteDIT.Enabled = false;
            btnDeleteOC.Enabled = false;

            lblStatus = new LabelControl
            {
                Font = new Font("Courier New", 7.5f),
                ForeColor = C_MUTED,
                Dock = DockStyle.Right,
                Width = 420,
                BackColor = Color.Transparent,
                Text = "Select a bank account and click Load.",
                AutoSizeMode = LabelAutoSizeMode.None,
            };
            lblStatus.Appearance.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
            lblStatus.Appearance.TextOptions.VAlignment = DevExpress.Utils.VertAlignment.Center;

            pnl.Controls.Add(lblStatus);
            pnl.Controls.Add(flow);
            return pnl;
        }

        // ================================================================
        // WIRE EVENTS
        // ================================================================
        private void WireEvents()
        {
            btnSaveHeader.Click += BtnSaveHeader_Click;
            btnAddDIT.Click += (s, e) => BtnAdd_Click("DIT");
            btnAddOC.Click += (s, e) => BtnAdd_Click("OC");
            btnResolveDIT.Click += (s, e) => BtnResolve_Click(_selDitID);
            btnResolveOC.Click += (s, e) => BtnResolve_Click(_selOcID);
            btnDeleteDIT.Click += (s, e) => BtnDelete_Click(_selDitID);
            btnDeleteOC.Click += (s, e) => BtnDelete_Click(_selOcID);
            btnAutoMatch.Click += BtnAutoMatch_Click;
            btnLock.Click += BtnLock_Click;
            btnPrint.Click += BtnPrint_Click;

            // [9] Snap period to end of month on change
            dtPeriod.EditValueChanged += (s, e) =>
            {
                if (dtPeriod.EditValue is DateTime dt)
                {
                    var eom = new DateTime(dt.Year, dt.Month,
                        DateTime.DaysInMonth(dt.Year, dt.Month));
                    if (dt != eom) dtPeriod.EditValue = eom;
                }
            };

            // DIT grid selection
            viewDIT.FocusedRowChanged += (s, e) =>
            {
                bool has = viewDIT.FocusedRowHandle >= 0;
                btnResolveDIT.Enabled = has && !_isLocked;
                btnDeleteDIT.Enabled = has && !_isLocked;
                _selDitID = has
                    ? SafeInt(viewDIT.GetRowCellValue(viewDIT.FocusedRowHandle, "ReconID"))
                    : 0;
            };

            // OC grid selection
            viewOC.FocusedRowChanged += (s, e) =>
            {
                bool has = viewOC.FocusedRowHandle >= 0;
                btnResolveOC.Enabled = has && !_isLocked;
                btnDeleteOC.Enabled = has && !_isLocked;
                _selOcID = has
                    ? SafeInt(viewOC.GetRowCellValue(viewOC.FocusedRowHandle, "ReconID"))
                    : 0;
            };
        }

        // ================================================================
        // POPULATE LOOKUPS
        // ================================================================
        private void PopulateLookups()
        {
            Database.displaySearchlookupEdit(
                "SELECT BranchCode, BranchName FROM Branches ORDER BY BranchCode",
                cmbBranch, "BranchCode", "BranchCode");
            cmbBranch.EditValue = Login.assignedBranch;

            Database.displaySearchlookupEdit(
                "SELECT AccountCode, Description FROM ChartOfAccounts " +
                "WHERE AccountCode LIKE '10102%' AND AccountType='D' " +
                "ORDER BY AccountCode",
                cmbAccount, "AccountCode", "AccountCode");
        }

        private void SetDefaultPeriod()
        {
            var today = DateTime.Today;
            // Default to last day of previous month
            _period = new DateTime(today.Year, today.Month, 1).AddDays(-1);
            dtPeriod.EditValue = _period;
        }

        // ================================================================
        // LOAD — [2] single SP call returns 3 result sets
        // ================================================================
        private void LoadRecon()
        {
            _branch = cmbBranch.EditValue?.ToString() ?? Login.assignedBranch;
            _account = cmbAccount.EditValue?.ToString() ?? "";
            _period = dtPeriod.EditValue is DateTime dt ? dt
                     : DateTime.TryParse(dtPeriod.Text, out var pd) ? pd : DateTime.Today;

            if (string.IsNullOrWhiteSpace(_account))
            {
                XtraMessageBox.Show("Please select a bank GL account.",
                    "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            try
            {
                LoadPeriod();
                RefreshSummary();
                SetStatus($"Loaded: {_account}  |  Period: {_period:yyyy-MM-dd}" +
                          (_isLocked ? "  |  🔒 LOCKED" : ""));
            }
            catch (SqlException ex)
            { SetStatus($"Load failed: {ex.Message}", err: true); }
        }

        // [2] Merged LoadHeader + LoadItems into one call
        private void LoadPeriod()
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("sp_BankRecon_GetPeriod", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@BranchCode", SqlDbType.Char, 3).Value = _branch;
                cmd.Parameters.Add("@AccountCode", SqlDbType.VarChar, 20).Value = _account;
                cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = _period;

                var ds = new DataSet();
                con.Open();
                new SqlDataAdapter(cmd).Fill(ds);

                // Result set 0 — header row
                if (ds.Tables.Count > 0 && ds.Tables[0].Rows.Count > 0)
                {
                    var hdr = ds.Tables[0].Rows[0];
                    _headerID = SafeInt(hdr["HeaderID"]);          // [3]
                    _bookBal = SafeDec(hdr["GLBookBalance"]);
                    _bankBal = SafeDec(hdr["BankStatementBal"]);
                    _isLocked = hdr["Status"]?.ToString() == "LOCKED";

                    lblBookBal.Text = _bookBal.ToString("N2");
                    txtBankBal.Text = _bankBal.ToString("N2");
                }
                else
                {
                    // No header yet — auto-created by payment SPs but
                    // if user loads a period with no transactions, create it.
                    CreateHeaderSilent();
                    LoadPeriod();
                    return;
                }

                // Result set 1 — DIT rows
                _dtDIT = ds.Tables.Count > 1 ? ds.Tables[1] : new DataTable();
                BindGrid(gridDIT, viewDIT, _dtDIT);

                // Result set 2 — OC rows
                _dtOC = ds.Tables.Count > 2 ? ds.Tables[2] : new DataTable();
                BindGrid(gridOC, viewOC, _dtOC);
            }

            // Lock UI if period is locked [5]
            SetLockedState(_isLocked);
        }

        private void CreateHeaderSilent()
        {
            int dummy = 0;
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("sp_BankRecon_GetOrCreateHeader", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@BranchCode", SqlDbType.Char, 3).Value = _branch;
                cmd.Parameters.Add("@AccountCode", SqlDbType.VarChar, 20).Value = _account;
                cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = _period;
                cmd.Parameters.Add("@CreatedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;
                cmd.Parameters.Add("@HeaderID", SqlDbType.Int).Direction = ParameterDirection.Output;
                con.Open();
                cmd.ExecuteNonQuery();
                _headerID = SafeInt(cmd.Parameters["@HeaderID"].Value);
            }
        }

        private void SetLockedState(bool locked)
        {
            txtBankBal.Properties.ReadOnly = locked;
            btnSaveHeader.Enabled = !locked;
            btnAddDIT.Enabled = !locked;
            btnAddOC.Enabled = !locked;
            btnLock.Enabled = !locked;
            btnAutoMatch.Enabled = !locked;
            // Resolve/Delete depend on row selection too — handled in FocusedRowChanged
        }

        // ── Grid binding ──────────────────────────────────────────────
        private void BindGrid(DevExpress.XtraGrid.GridControl grid,
                              GridView view, DataTable dt)
        {
            view.Columns.Clear();
            grid.DataSource = dt;

            FormatCol(view, "ReconID", 50, false);
            FormatCol(view, "ItemDate", 90, false, isDate: true);
            FormatCol(view, "ReferenceNo", 120, false);
            FormatCol(view, "Description", 180, false);
            FormatCol(view, "Amount", 110, true);
            FormatCol(view, "IsResolved", 60, false);
            FormatCol(view, "ResolvedReason", 90, false);
            FormatCol(view, "SourceModule", 80, false);
            FormatCol(view, "IsAutoInserted", 0, false);  // hidden, used for row tint

            if (view.Columns["IsAutoInserted"] != null)
                view.Columns["IsAutoInserted"].Visible = false;

            view.BestFitColumns();
        }

        private void FormatCol(GridView view, string field, int width,
                               bool money, bool isDate = false)
        {
            var col = view.Columns[field];
            if (col == null) return;
            col.Width = width;
            col.AppearanceHeader.ForeColor = C_GOLD;
            col.AppearanceHeader.Font = new Font("Courier New", 7.5f, FontStyle.Bold);
            col.AppearanceHeader.Options.UseForeColor = true;
            col.AppearanceHeader.Options.UseFont = true;
            if (money)
            {
                col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                col.DisplayFormat.FormatString = "N2";
                col.AppearanceCell.Font = F_MONO;
                col.AppearanceCell.ForeColor = C_DR;
                col.AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                col.AppearanceCell.Options.UseFont = true;
                col.AppearanceCell.Options.UseForeColor = true;
                col.Summary.Add(DevExpress.Data.SummaryItemType.Sum, field, "{0:N2}");
            }
            if (isDate)
            {
                col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                col.DisplayFormat.FormatString = "yyyy-MM-dd";
            }
        }

        // ================================================================
        // SUMMARY REFRESH — [10] reads from _dtDIT and _dtOC separately
        // ================================================================
        private void RefreshSummary()
        {
            decimal dit = 0, oc = 0, bcm = 0, bdm = 0;

            foreach (DataRow row in _dtDIT.Rows)
            {
                if (row["IsResolved"] is bool b && b) continue;
                dit += SafeDec(row["Amount"]);
            }
            foreach (DataRow row in _dtOC.Rows)
            {
                if (row["IsResolved"] is bool b && b) continue;
                string t = row["ItemType"]?.ToString();
                decimal amt = SafeDec(row["Amount"]);
                switch (t)
                {
                    case "OC": oc += amt; break;
                    case "BCM": bcm += amt; break;
                    case "BDM":
                    case "BC":
                    case "NSF": bdm += amt; break;
                }
            }

            decimal adjBank = _bankBal + dit - oc;
            decimal adjBook = _bookBal + bcm - bdm;
            decimal diff = adjBank - adjBook;
            bool balanced = Math.Abs(diff) < 0.01m;

            SetLbl(lblBankStmt, _bankBal.ToString("N2"), C_TEXT);
            SetLbl(lblDIT, $"+{dit:N2}", C_DR);
            SetLbl(lblOC, $"-{oc:N2}", C_CR);
            SetLbl(lblAdjBank, adjBank.ToString("N2"), C_OK);
            SetLbl(lblBookSide, _bookBal.ToString("N2"), C_TEXT);
            SetLbl(lblBCM, $"+{bcm:N2}", C_DR);
            SetLbl(lblBDM, $"-{bdm:N2}", C_CR);
            SetLbl(lblAdjBook, adjBook.ToString("N2"), C_OK);

            if (balanced)
            {
                SetLbl(lblDiff, "0.00  ✓  RECONCILED", C_OK);
                lblDiff.Font = new Font("Courier New", 12f, FontStyle.Bold);
            }
            else
            {
                SetLbl(lblDiff,
                    $"{Math.Abs(diff):N2}  ⚠  OUT OF BALANCE", C_ERR);
                lblDiff.Font = new Font("Courier New", 12f, FontStyle.Bold);
            }
        }

        private void SetLbl(LabelControl lbl, string text, Color color)
        {
            if (lbl == null) return;
            lbl.Text = text;
            lbl.ForeColor = color;
            lbl.Appearance.Options.UseForeColor = true;
        }

        // ================================================================
        // CRUD HANDLERS
        // ================================================================

        // [8] SaveHeader now passes @HeaderID
        private void BtnSaveHeader_Click(object sender, EventArgs e)
        {
            if (_headerID == 0) { XtraMessageBox.Show("Load a period first."); return; }
            if (!decimal.TryParse(txtBankBal.Text.Replace(",", ""),
                NumberStyles.Any, CultureInfo.InvariantCulture, out var bal))
            { XtraMessageBox.Show("Enter a valid amount."); return; }

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_BankRecon_SaveHeader", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@HeaderID", SqlDbType.Int).Value = _headerID;
                    cmd.Parameters.Add("@BankStatementBal", SqlDbType.Decimal).Value = Math.Round(bal, 2);
                    cmd.Parameters.Add("@Remarks", SqlDbType.VarChar, 500).Value = "";
                    cmd.Parameters.Add("@UpdatedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    con.Open();
                    cmd.ExecuteNonQuery();
                }
                _bankBal = bal;
                LoadPeriod();   // refresh GLBookBalance computed by SP
                RefreshSummary();
                SetStatus("Bank statement balance saved.");
            }
            catch (SqlException ex) { SetStatus(ex.Message, err: true); }
        }

        private void BtnAdd_Click(string itemType)
        {
            if (_headerID == 0) { XtraMessageBox.Show("Load a period first."); return; }

            using (var dlg = new BankReconItemForm(isNew: true))
            {
                dlg.ItemType = itemType;
                if (dlg.ShowDialog(this) != DialogResult.OK) return;

                try
                {
                    using (var con = Database.getConnection())
                    using (var cmd = new SqlCommand("sp_BankRecon_SaveItem", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.Add("@HeaderID", SqlDbType.Int).Value = _headerID;
                        cmd.Parameters.Add("@ItemType", SqlDbType.VarChar, 5).Value = dlg.ItemType;
                        cmd.Parameters.Add("@ReferenceNo", SqlDbType.VarChar, 150).Value = dlg.ReferenceNo;
                        cmd.Parameters.Add("@ItemDate", SqlDbType.Date).Value = dlg.ItemDate;
                        cmd.Parameters.Add("@Description", SqlDbType.VarChar, 200).Value = dlg.Payee;
                        cmd.Parameters.Add("@Amount", SqlDbType.Decimal).Value = Math.Round(dlg.Amount, 2);
                        cmd.Parameters.Add("@Remarks", SqlDbType.VarChar, 500).Value = dlg.Remarks;
                        cmd.Parameters.Add("@CreatedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;
                        con.Open();
                        cmd.ExecuteNonQuery();
                    }
                    LoadPeriod(); RefreshSummary();
                    SetStatus($"{itemType} item added.");
                }
                catch (SqlException ex) { SetStatus(ex.Message, err: true); }
            }
        }

        // [4] Calls sp_BankRecon_ResolveItem (not UpdateItem with DBNull)
        private void BtnResolve_Click(int reconID)
        {
            if (reconID <= 0) return;
            if (XtraMessageBox.Show("Mark this item as CLEARED by bank?",
                "Confirm", MessageBoxButtons.YesNo, MessageBoxIcon.Question)
                != DialogResult.Yes) return;
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_BankRecon_ResolveItem", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@ReconID", SqlDbType.Int).Value = reconID;
                    cmd.Parameters.Add("@IsResolved", SqlDbType.Bit).Value = true;
                    cmd.Parameters.Add("@ResolvedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    con.Open();
                    cmd.ExecuteNonQuery();
                }
                LoadPeriod(); RefreshSummary();
                SetStatus("Item marked as cleared.");
            }
            catch (SqlException ex) { SetStatus(ex.Message, err: true); }
        }

        private void BtnDelete_Click(int reconID)
        {
            if (reconID <= 0) return;
            if (XtraMessageBox.Show("Delete this item? Auto-inserted items should not be deleted.",
                "Confirm Delete", MessageBoxButtons.YesNo, MessageBoxIcon.Warning)
                != DialogResult.Yes) return;
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_BankRecon_DeleteItem", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@ReconID", SqlDbType.Int).Value = reconID;
                    cmd.Parameters.Add("@DeletedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    con.Open();
                    cmd.ExecuteNonQuery();
                }
                LoadPeriod(); RefreshSummary();
                SetStatus("Item deleted.");
            }
            catch (SqlException ex) { SetStatus(ex.Message, err: true); }
        }

        private void BtnAutoMatch_Click(object sender, EventArgs e)
        {
            if (_headerID == 0) { XtraMessageBox.Show("Load a period first."); return; }
            if (XtraMessageBox.Show(
                "Auto-match outstanding checks against GL payments?\n" +
                "Matched items will be marked Resolved.",
                "Auto-Match", MessageBoxButtons.YesNo, MessageBoxIcon.Question)
                != DialogResult.Yes) return;
            try
            {
                int matched = 0;
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_BankRecon_AutoMatch", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@BranchCode", SqlDbType.Char, 3).Value = _branch;
                    cmd.Parameters.Add("@AccountCode", SqlDbType.VarChar, 20).Value = _account;
                    cmd.Parameters.Add("@PeriodEnd", SqlDbType.Date).Value = _period;
                    cmd.Parameters.Add("@User", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    con.Open();
                    using (var rdr = cmd.ExecuteReader())
                        if (rdr.Read()) matched = SafeInt(rdr["MatchedItems"]);
                }
                LoadPeriod(); RefreshSummary();
                SetStatus($"Auto-match: {matched} item(s) resolved.");
            }
            catch (SqlException ex) { SetStatus(ex.Message, err: true); }
        }

        // [5] Lock period
        private void BtnLock_Click(object sender, EventArgs e)
        {
            if (_headerID == 0) { XtraMessageBox.Show("Load a period first."); return; }
            if (XtraMessageBox.Show(
                "Lock this reconciliation period?\n" +
                "No further changes will be allowed after locking.",
                "Lock Period", MessageBoxButtons.YesNo, MessageBoxIcon.Warning)
                != DialogResult.Yes) return;
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_BankRecon_LockPeriod", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@HeaderID", SqlDbType.Int).Value = _headerID;
                    cmd.Parameters.Add("@LockedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;
                    cmd.Parameters.Add("@StrictMode", SqlDbType.Bit).Value = true;
                    con.Open();
                    cmd.ExecuteNonQuery();
                }
                XtraMessageBox.Show("Period locked successfully.",
                    "Locked", MessageBoxButtons.OK, MessageBoxIcon.Information);
                LoadPeriod(); RefreshSummary();
                SetStatus($"Period {_period:yyyy-MM-dd} locked by {Login.Fullname}.");
            }
            catch (SqlException ex)
            {
                // SP throws 93005 if not balanced — show the message clearly
                XtraMessageBox.Show(ex.Message, "Cannot Lock",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        private void BtnPrint_Click(object sender, EventArgs e)
        {
            XtraMessageBox.Show("Wire to your XtraReport template here.",
                "Print", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        // ================================================================
        // HELPERS
        // ================================================================
        private void SetStatus(string msg, bool err = false)
        {
            if (lblStatus == null) return;
            lblStatus.Text = msg;
            lblStatus.ForeColor = err ? C_ERR : C_MUTED;
            lblStatus.Appearance.Options.UseForeColor = true;
            Application.DoEvents();
        }

        private SimpleButton MakeBtn(string text, Color bg, Color fg)
        {
            var btn = new SimpleButton
            {
                Text = text,
                Font = F_SMALL,
                Appearance = { BackColor = bg, ForeColor = fg, BorderColor = C_BORDER },
            };
            btn.Appearance.Options.UseBackColor = true;
            btn.Appearance.Options.UseForeColor = true;
            return btn;
        }

        private void StyleLookUp(SearchLookUpEdit c)
        {
            c.Properties.Appearance.BackColor = C_CARD;
            c.Properties.Appearance.ForeColor = C_TEXT;
            c.Properties.Appearance.Options.UseBackColor = true;
            c.Properties.Appearance.Options.UseForeColor = true;
        }

        private void StyleDate(DateEdit c)
        {
            c.Properties.Appearance.BackColor = C_CARD;
            c.Properties.Appearance.ForeColor = C_TEXT;
            c.Properties.Appearance.Options.UseBackColor = true;
            c.Properties.Appearance.Options.UseForeColor = true;
        }

        private static decimal SafeDec(object v)
        {
            if (v == null || v == DBNull.Value) return 0m;
            return decimal.TryParse(v.ToString().Replace(",", ""),
                NumberStyles.Any, CultureInfo.InvariantCulture, out var r) ? r : 0m;
        }

        private static int SafeInt(object v)
            => v == null || v == DBNull.Value ? 0
             : int.TryParse(v.ToString(), out var r) ? r : 0;

        private static DateTime SafeDate(object v)
            => v is DateTime dt ? dt
             : DateTime.TryParse(v?.ToString(), out var r) ? r : DateTime.Today;

        private void InitializeComponent()
        {
            this.SuspendLayout();
            this.AutoScaleDimensions = new SizeF(6F, 13F);
            this.AutoScaleMode = AutoScaleMode.Font;
            this.ClientSize = new Size(1280, 800);
            this.Name = "BankReconForm";
            this.ResumeLayout(false);
        }
    }
}