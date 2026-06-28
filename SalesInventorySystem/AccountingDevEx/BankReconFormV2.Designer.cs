using System;
using System.Drawing;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.AccountingDevEx
{
    public partial class BankReconFormV2
    {
        // ── Colours & Fonts ───────────────────────────────────────────
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
        private static readonly Color C_AUTO = Color.FromArgb(30, 60, 100);

        private static readonly Font F_MONO = new Font("Courier New", 9f);
        private static readonly Font F_SMALL = new Font("Segoe UI", 8.5f);
        private static readonly Font F_BOLD = new Font("Segoe UI", 9f, FontStyle.Bold);
        private static readonly Font F_TITLE = new Font("Georgia", 14f, FontStyle.Bold);

        // ── Controls ──────────────────────────────────────────────────
        private SearchLookUpEdit cmbBranch, cmbAccount;
        private DateEdit dtPeriod;
        private LabelControl lblBookBal;
        private TextEdit txtBankBal;
        private SimpleButton btnSaveHeader;

        private DevExpress.XtraGrid.GridControl gridDIT;
        private GridView viewDIT;
        private DevExpress.XtraGrid.GridControl gridOC;
        private GridView viewOC;

        private LabelControl lblBankStmt, lblDIT, lblOC, lblAdjBank;
        private LabelControl lblBookSide, lblBCM, lblBDM, lblAdjBook;
        private LabelControl lblDiff;

        private SimpleButton btnAddDIT, btnAddOC,
                             btnResolveDIT, btnResolveOC,
                             btnDeleteDIT, btnDeleteOC,
                             btnAutoMatch, btnLock, btnPrint, btnLoad;
        private LabelControl lblStatus;

        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null)) components.Dispose();
            base.Dispose(disposing);
        }

        private void InitializeComponent()
        {
            this.SuspendLayout();

            // Base Form Properties
            this.Text = "Bank Reconciliation";
            this.BackColor = C_DARK;
            this.ForeColor = C_TEXT;
            this.WindowState = FormWindowState.Maximized;
            this.MinimumSize = new Size(1100, 640);
            this.AutoScaleDimensions = new SizeF(6F, 13F);
            this.AutoScaleMode = AutoScaleMode.Font;
            this.ClientSize = new Size(1280, 800);
            this.Name = "BankReconForm";

            // Trigger our custom UI builder
            BuildUI();

            this.ResumeLayout(false);
        }

        // ================================================================
        // MASTER LAYOUT BUILDER
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
            tlp.RowStyles.Add(new RowStyle(SizeType.Absolute, 52f));   // Banner
            tlp.RowStyles.Add(new RowStyle(SizeType.Absolute, 142f));  // Filter
            tlp.RowStyles.Add(new RowStyle(SizeType.Absolute, 64f));   // Header
            tlp.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));   // Body grids
            tlp.RowStyles.Add(new RowStyle(SizeType.Absolute, 44f));   // Toolbar

            tlp.Controls.Add(BuildBanner(), 0, 0);
            tlp.Controls.Add(BuildFilter(), 0, 1);
            tlp.Controls.Add(BuildHeader(), 0, 2);
            tlp.Controls.Add(BuildBody(), 0, 3);
            tlp.Controls.Add(BuildToolbar(), 0, 4);

            this.Controls.Add(tlp);
        }

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
            return pnl;
        }

        private Panel BuildFilter()
        {
            var pnl = new Panel { Dock = DockStyle.Fill, BackColor = C_CARD, Padding = new Padding(10, 8, 10, 6) };
            pnl.Controls.Add(new Panel { Dock = DockStyle.Bottom, Height = 1, BackColor = C_BORDER });

            var flow = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight, WrapContents = false, BackColor = Color.Transparent };

            cmbBranch = new SearchLookUpEdit(); StyleLookUp(cmbBranch);
            cmbAccount = new SearchLookUpEdit(); StyleLookUp(cmbAccount);
            dtPeriod = new DateEdit(); StyleDate(dtPeriod);
            dtPeriod.Properties.DisplayFormat.FormatString = "yyyy-MM-dd";
            dtPeriod.Properties.EditFormat.FormatString = "yyyy-MM-dd";

            flow.Controls.Add(MakeFilterGroup("Branch", cmbBranch, 100));
            flow.Controls.Add(MakeFilterGroup("Bank GL Account", cmbAccount, 280));
            flow.Controls.Add(MakeFilterGroup("Period End (month-end)", dtPeriod, 140));

            btnLoad = MakeBtn("▶  Load", C_GOLD, C_DARK);
            btnLoad.Margin = new Padding(4, 20, 0, 0);
            btnLoad.Size = new Size(90, 26);
            flow.Controls.Add(btnLoad);

            pnl.Controls.Add(flow);
            return pnl;
        }

        private Panel MakeFilterGroup(string caption, Control ctrl, int width)
        {
            var grp = new Panel { Width = width + 4, Height = 52, BackColor = Color.Transparent, Margin = new Padding(0, 4, 10, 0) };
            grp.Controls.Add(new LabelControl { Text = caption.ToUpper(), Font = new Font("Courier New", 7f, FontStyle.Bold), ForeColor = C_MUTED, AutoSizeMode = LabelAutoSizeMode.None, Location = new Point(0, 0), Size = new Size(width, 14), BackColor = Color.Transparent });
            ctrl.Location = new Point(0, 16);
            ctrl.Size = new Size(width, 24);
            grp.Controls.Add(ctrl);
            return grp;
        }

        private Panel BuildHeader()
        {
            var pnl = new Panel { Dock = DockStyle.Fill, BackColor = C_SURFACE, Padding = new Padding(14, 10, 14, 8) };
            pnl.Controls.Add(new Panel { Dock = DockStyle.Bottom, Height = 1, BackColor = C_BORDER });

            var flow = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight, WrapContents = false, BackColor = Color.Transparent };

            var grpBook = new Panel { Width = 260, Height = 50, BackColor = Color.Transparent, Margin = new Padding(0, 0, 30, 0) };
            grpBook.Controls.Add(MakeCap("BALANCE PER GL (BOOK)", 260));
            lblBookBal = MakeValLabel("0.00", C_DR, 260);
            lblBookBal.Location = new Point(0, 16);
            grpBook.Controls.Add(lblBookBal);

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

        private LabelControl MakeCap(string text, int width) => new LabelControl { Text = text, Font = new Font("Courier New", 7f, FontStyle.Bold), ForeColor = C_MUTED, AutoSizeMode = LabelAutoSizeMode.None, Location = new Point(0, 0), Size = new Size(width, 14), BackColor = Color.Transparent };
        private LabelControl MakeValLabel(string text, Color color, int width) => new LabelControl { Text = text, Font = new Font("Courier New", 14f, FontStyle.Bold), ForeColor = color, AutoSizeMode = LabelAutoSizeMode.None, Size = new Size(width, 26), BackColor = Color.Transparent };

        private Control BuildBody()
        {
            var outer = new SplitContainerControl { Dock = DockStyle.Fill, SplitterPosition = 820, BackColor = C_DARK };
            outer.Panel1.BackColor = C_DARK;
            outer.Panel2.BackColor = C_SURFACE;

            var inner = new SplitContainerControl { Dock = DockStyle.Fill, Horizontal = true, SplitterPosition = 300, BackColor = C_DARK };
            inner.Panel1.BackColor = C_DARK;
            inner.Panel2.BackColor = C_DARK;

            inner.Panel1.Controls.Add(BuildGridPanel("DEPOSITS IN TRANSIT", out gridDIT, out viewDIT));
            inner.Panel2.Controls.Add(BuildGridPanel("OUTSTANDING CHECKS", out gridOC, out viewOC));

            outer.Panel1.Controls.Add(inner);
            outer.Panel2.Controls.Add(BuildSummaryPanel());

            return outer;
        }

        private Panel BuildGridPanel(string title, out DevExpress.XtraGrid.GridControl grid, out GridView view)
        {
            var pnl = new Panel { Dock = DockStyle.Fill, BackColor = C_DARK };
            pnl.Controls.Add(new LabelControl { Text = title, Font = new Font("Courier New", 8f, FontStyle.Bold), ForeColor = C_GOLD, AutoSizeMode = LabelAutoSizeMode.None, Dock = DockStyle.Top, Height = 20, BackColor = C_CARD });

            grid = new DevExpress.XtraGrid.GridControl { Dock = DockStyle.Fill, BackColor = C_DARK };
            view = new GridView(grid);

            view.OptionsView.ShowGroupPanel = false;
            view.OptionsView.ShowIndicator = false;
            view.OptionsView.ShowFooter = true;
            view.OptionsView.EnableAppearanceEvenRow = true;
            view.OptionsBehavior.Editable = false;

            view.Appearance.HeaderPanel.BackColor = C_CARD;
            view.Appearance.HeaderPanel.ForeColor = C_GOLD;
            view.Appearance.HeaderPanel.Font = new Font("Courier New", 8f, FontStyle.Bold);
            view.Appearance.Row.BackColor = C_DARK;
            view.Appearance.Row.ForeColor = C_TEXT;
            view.Appearance.EvenRow.BackColor = C_SURFACE;
            view.Appearance.FocusedRow.BackColor = C_BORDER;
            view.Appearance.FocusedRow.ForeColor = C_TEXT;
            view.Appearance.FooterPanel.BackColor = C_CARD;
            view.Appearance.FooterPanel.ForeColor = C_GOLD;
            view.Appearance.FooterPanel.Font = new Font("Courier New", 8.5f, FontStyle.Bold);

            grid.MainView = view;
            pnl.Controls.Add(grid);
            return pnl;
        }

        private Control BuildSummaryPanel()
        {
            var tlp = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, BackColor = C_SURFACE, Padding = new Padding(14, 12, 14, 12), CellBorderStyle = TableLayoutPanelCellBorderStyle.None };
            tlp.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 60f));
            tlp.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 40f));
            int r = 0;

            void Section(string text)
            {
                tlp.RowStyles.Add(new RowStyle(SizeType.Absolute, 22f));
                var lbl = new LabelControl { Text = text.ToUpper(), Font = new Font("Courier New", 7.5f, FontStyle.Bold), ForeColor = C_GOLD, Dock = DockStyle.Fill, BackColor = Color.Transparent, AutoSizeMode = LabelAutoSizeMode.None };
                lbl.Appearance.TextOptions.VAlignment = DevExpress.Utils.VertAlignment.Center;
                tlp.Controls.Add(lbl, 0, r);
                tlp.Controls.Add(new Panel { BackColor = Color.Transparent }, 1, r);
                r++;
            }

            void Row(string caption, ref LabelControl val, Color color, bool isTotal = false)
            {
                tlp.RowStyles.Add(new RowStyle(SizeType.Absolute, isTotal ? 32 : 24));
                var cap = new LabelControl { Text = caption, Font = isTotal ? F_BOLD : F_SMALL, ForeColor = C_MUTED, Dock = DockStyle.Fill, BackColor = Color.Transparent, AutoSizeMode = LabelAutoSizeMode.None };
                cap.Appearance.TextOptions.VAlignment = DevExpress.Utils.VertAlignment.Center;

                val = new LabelControl { Text = "0.00", Font = isTotal ? new Font("Courier New", 12f, FontStyle.Bold) : F_MONO, ForeColor = color, Dock = DockStyle.Fill, BackColor = Color.Transparent, AutoSizeMode = LabelAutoSizeMode.None };
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

            Section("Bank Statement Side");
            Row("Balance per bank statement", ref lblBankStmt, C_TEXT);
            Row("Add: Deposits in transit", ref lblDIT, C_DR);
            Row("Less: Outstanding checks", ref lblOC, C_CR);
            Row("Adjusted Bank Balance", ref lblAdjBank, C_OK, isTotal: true);
            Spacer();

            Section("Book (GL) Side");
            Row("Balance per GL", ref lblBookSide, C_TEXT);
            Row("Add: Bank credit memos", ref lblBCM, C_DR);
            Row("Less: Bank debit memos / charges", ref lblBDM, C_CR);
            Row("Adjusted Book Balance", ref lblAdjBook, C_OK, isTotal: true);
            Spacer();

            Section("Difference (must be 0.00)");
            Row("", ref lblDiff, C_OK, isTotal: true);

            tlp.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
            tlp.Controls.Add(new Panel { BackColor = Color.Transparent }, 0, r);
            tlp.Controls.Add(new Panel { BackColor = Color.Transparent }, 1, r);

            return tlp;
        }

        private Panel BuildToolbar()
        {
            var pnl = new Panel { Dock = DockStyle.Fill, BackColor = C_CARD };
            pnl.Controls.Add(new Panel { Dock = DockStyle.Top, Height = 1, BackColor = C_BORDER });

            var flow = new FlowLayoutPanel { Dock = DockStyle.Left, FlowDirection = FlowDirection.LeftToRight, WrapContents = false, BackColor = Color.Transparent, AutoSize = true, Padding = new Padding(6, 6, 0, 6) };

            btnAddDIT = MakeBtn("＋ Add DIT", C_GOLD, C_DARK);
            btnAddOC = MakeBtn("＋ Add OC", Color.FromArgb(40, 60, 30), C_OK);
            btnResolveDIT = MakeBtn("✔ Resolve DIT", C_CARD, C_MUTED);
            btnResolveOC = MakeBtn("✔ Resolve OC", C_CARD, C_MUTED);
            btnDeleteDIT = MakeBtn("✖ Del DIT", Color.FromArgb(80, 20, 20), C_ERR);
            btnDeleteOC = MakeBtn("✖ Del OC", Color.FromArgb(80, 20, 20), C_ERR);
            btnAutoMatch = MakeBtn("⚡ Auto-Match", C_CARD, C_MUTED);
            btnLock = MakeBtn("🔒 Lock Period", C_CARD, C_GOLD);
            btnPrint = MakeBtn("🖨 Print", C_CARD, C_MUTED);

            foreach (var b in new[] { btnAddDIT, btnAddOC, btnResolveDIT, btnResolveOC, btnDeleteDIT, btnDeleteOC, btnAutoMatch, btnLock, btnPrint })
            {
                b.Margin = new Padding(0, 0, 5, 0);
                b.AutoSize = true;
                b.Size = new Size(0, 30);
                flow.Controls.Add(b);
            }

            btnResolveDIT.Enabled = false;
            btnResolveOC.Enabled = false;
            btnDeleteDIT.Enabled = false;
            btnDeleteOC.Enabled = false;

            lblStatus = new LabelControl { Font = new Font("Courier New", 7.5f), ForeColor = C_MUTED, Dock = DockStyle.Right, Width = 420, BackColor = Color.Transparent, Text = "Select a bank account and click Load.", AutoSizeMode = LabelAutoSizeMode.None };
            lblStatus.Appearance.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
            lblStatus.Appearance.TextOptions.VAlignment = DevExpress.Utils.VertAlignment.Center;

            pnl.Controls.Add(lblStatus);
            pnl.Controls.Add(flow);
            return pnl;
        }

        private SimpleButton MakeBtn(string text, Color bg, Color fg)
        {
            var btn = new SimpleButton { Text = text, Font = F_SMALL, Appearance = { BackColor = bg, ForeColor = fg, BorderColor = C_BORDER } };
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
    }
}