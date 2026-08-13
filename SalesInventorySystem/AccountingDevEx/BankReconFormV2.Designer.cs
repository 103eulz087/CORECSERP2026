namespace SalesInventorySystem.AccountingDevEx
{
    partial class BankReconFormV2
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null)) components.Dispose();
            base.Dispose(disposing);
        }

        // ── Header bar ──────────────────────────────────────────
        private DevExpress.XtraEditors.PanelControl pnlHeader;
        private DevExpress.XtraEditors.LabelControl lblBranchCaption;
        private DevExpress.XtraEditors.SearchLookUpEdit cmbBranch;
        private DevExpress.XtraEditors.LabelControl lblAccountCaption;
        private DevExpress.XtraEditors.SearchLookUpEdit cmbAccount;
        private DevExpress.XtraEditors.LabelControl lblPeriodCaption;
        private DevExpress.XtraEditors.DateEdit dtPeriod;
        private DevExpress.XtraEditors.SimpleButton btnLoad;
        private DevExpress.XtraEditors.LabelControl lblStatus;

        // ── Balances bar ────────────────────────────────────────
        private DevExpress.XtraEditors.PanelControl pnlBalances;
        private DevExpress.XtraEditors.LabelControl lblBookBalCaption;
        private DevExpress.XtraEditors.LabelControl lblBookBal;
        private DevExpress.XtraEditors.LabelControl lblBankBalCaption;
        private DevExpress.XtraEditors.TextEdit txtBankBal;
        private DevExpress.XtraEditors.SimpleButton btnSaveHeader;

        // ── Tabs: DIT / OC / Bank-Side ──────────────────────────
        private DevExpress.XtraTab.XtraTabControl tabItems;
        private DevExpress.XtraTab.XtraTabPage tabOC;
        private DevExpress.XtraTab.XtraTabPage tabBankSide;

        private DevExpress.XtraGrid.GridControl gridDIT;
        private DevExpress.XtraGrid.Views.Grid.GridView viewDIT;

        private DevExpress.XtraGrid.GridControl gridOC;
        private DevExpress.XtraGrid.Views.Grid.GridView viewOC;
        private DevExpress.XtraEditors.SimpleButton btnAddOC;
        private DevExpress.XtraEditors.SimpleButton btnResolveOC;
        private DevExpress.XtraEditors.SimpleButton btnDeleteOC;
        private DevExpress.XtraEditors.SimpleButton btnAutoMatch;

        private DevExpress.XtraGrid.GridControl gridBankSide;
        private DevExpress.XtraGrid.Views.Grid.GridView viewBankSide;
        private DevExpress.XtraEditors.PanelControl pnlBankSideButtons;
        private DevExpress.XtraEditors.SimpleButton btnAddBankSide;
        private DevExpress.XtraEditors.SimpleButton btnResolveBankSide;
        private DevExpress.XtraEditors.SimpleButton btnDeleteBankSide;
        private DevExpress.XtraEditors.SimpleButton btnPostAutoDebit;   // NEW — posts payment for an ADB row

        // ── Summary panel ───────────────────────────────────────
        private DevExpress.XtraEditors.GroupControl grpSummary;
        private DevExpress.XtraEditors.LabelControl lblBankStmtCaption, lblBankStmt;
        private DevExpress.XtraEditors.LabelControl lblDITCaption, lblDIT;
        private DevExpress.XtraEditors.LabelControl lblOCCaption, lblOC;
        private DevExpress.XtraEditors.LabelControl lblAdjBankCaption, lblAdjBank;
        private DevExpress.XtraEditors.LabelControl lblBookSideCaption, lblBookSide;
        private DevExpress.XtraEditors.LabelControl lblBCMCaption, lblBCM;
        private DevExpress.XtraEditors.LabelControl lblBDMCaption, lblBDM;
        private DevExpress.XtraEditors.LabelControl lblAdjBookCaption, lblAdjBook;
        private DevExpress.XtraEditors.LabelControl lblDiffCaption, lblDiff;

        // ── Footer ──────────────────────────────────────────────
        private DevExpress.XtraEditors.PanelControl pnlFooter;
        private DevExpress.XtraEditors.SimpleButton btnLock;
        private DevExpress.XtraEditors.SimpleButton btnPrint;

        private void InitializeComponent()
        {
            this.components = new System.ComponentModel.Container();
            this.pnlHeader = new DevExpress.XtraEditors.PanelControl();
            this.lblBranchCaption = new DevExpress.XtraEditors.LabelControl();
            this.cmbBranch = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.lblAccountCaption = new DevExpress.XtraEditors.LabelControl();
            this.cmbAccount = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.lblPeriodCaption = new DevExpress.XtraEditors.LabelControl();
            this.dtPeriod = new DevExpress.XtraEditors.DateEdit();
            this.btnLoad = new DevExpress.XtraEditors.SimpleButton();
            this.lblStatus = new DevExpress.XtraEditors.LabelControl();
            this.pnlBalances = new DevExpress.XtraEditors.PanelControl();
            this.lblBookBalCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblBookBal = new DevExpress.XtraEditors.LabelControl();
            this.lblBankBalCaption = new DevExpress.XtraEditors.LabelControl();
            this.txtBankBal = new DevExpress.XtraEditors.TextEdit();
            this.btnSaveHeader = new DevExpress.XtraEditors.SimpleButton();
            this.tabItems = new DevExpress.XtraTab.XtraTabControl();
            this.tabOC = new DevExpress.XtraTab.XtraTabPage();
            this.panelControl5 = new DevExpress.XtraEditors.PanelControl();
            this.tablePanel1 = new DevExpress.Utils.Layout.TablePanel();
            this.panelControl7 = new DevExpress.XtraEditors.PanelControl();
            this.gridOC = new DevExpress.XtraGrid.GridControl();
            this.viewOC = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.panelControl1 = new DevExpress.XtraEditors.PanelControl();
            this.gridDIT = new DevExpress.XtraGrid.GridControl();
            this.viewDIT = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.panelControl3 = new DevExpress.XtraEditors.PanelControl();
            this.panelControl4 = new DevExpress.XtraEditors.PanelControl();
            this.panelControl6 = new DevExpress.XtraEditors.PanelControl();
            this.btnAutoMatch = new DevExpress.XtraEditors.SimpleButton();
            this.btnDeleteOC = new DevExpress.XtraEditors.SimpleButton();
            this.simpleButton1 = new DevExpress.XtraEditors.SimpleButton();
            this.btnAddOC = new DevExpress.XtraEditors.SimpleButton();
            this.btnResolveOC = new DevExpress.XtraEditors.SimpleButton();
            this.tabDIT = new DevExpress.XtraTab.XtraTabPage();
            this.pnlDITButtons = new DevExpress.XtraEditors.PanelControl();
            this.tabBankSide = new DevExpress.XtraTab.XtraTabPage();
            this.gridBankSide = new DevExpress.XtraGrid.GridControl();
            this.viewBankSide = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.pnlBankSideButtons = new DevExpress.XtraEditors.PanelControl();
            this.btnAddBankSide = new DevExpress.XtraEditors.SimpleButton();
            this.btnResolveBankSide = new DevExpress.XtraEditors.SimpleButton();
            this.btnDeleteBankSide = new DevExpress.XtraEditors.SimpleButton();
            this.btnPostAutoDebit = new DevExpress.XtraEditors.SimpleButton();
            this.grpSummary = new DevExpress.XtraEditors.GroupControl();
            this.lblBankStmtCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblBankStmt = new DevExpress.XtraEditors.LabelControl();
            this.lblDITCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblDIT = new DevExpress.XtraEditors.LabelControl();
            this.lblOCCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblOC = new DevExpress.XtraEditors.LabelControl();
            this.lblAdjBankCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblAdjBank = new DevExpress.XtraEditors.LabelControl();
            this.lblBookSideCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblBookSide = new DevExpress.XtraEditors.LabelControl();
            this.lblBCMCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblBCM = new DevExpress.XtraEditors.LabelControl();
            this.lblBDMCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblBDM = new DevExpress.XtraEditors.LabelControl();
            this.lblAdjBookCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblAdjBook = new DevExpress.XtraEditors.LabelControl();
            this.lblDiffCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblDiff = new DevExpress.XtraEditors.LabelControl();
            this.pnlFooter = new DevExpress.XtraEditors.PanelControl();
            this.btnLock = new DevExpress.XtraEditors.SimpleButton();
            this.btnPrint = new DevExpress.XtraEditors.SimpleButton();
            this.btnDeleteDIT = new DevExpress.XtraEditors.SimpleButton();
            this.btnResolveDIT = new DevExpress.XtraEditors.SimpleButton();
            this.btnAddDIT = new DevExpress.XtraEditors.SimpleButton();
            this.contextMenuStripDIT = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.markAsClearedToolStripMenuItem1 = new System.Windows.Forms.ToolStripMenuItem();
            this.contextMenuStripOC = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.markAsClearedToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            ((System.ComponentModel.ISupportInitialize)(this.pnlHeader)).BeginInit();
            this.pnlHeader.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.cmbBranch.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbAccount.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtPeriod.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtPeriod.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlBalances)).BeginInit();
            this.pnlBalances.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtBankBal.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.tabItems)).BeginInit();
            this.tabItems.SuspendLayout();
            this.tabOC.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl5)).BeginInit();
            this.panelControl5.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.tablePanel1)).BeginInit();
            this.tablePanel1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl7)).BeginInit();
            this.panelControl7.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridOC)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.viewOC)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl1)).BeginInit();
            this.panelControl1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridDIT)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.viewDIT)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl3)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl4)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl6)).BeginInit();
            this.panelControl6.SuspendLayout();
            this.tabDIT.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pnlDITButtons)).BeginInit();
            this.tabBankSide.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridBankSide)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.viewBankSide)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlBankSideButtons)).BeginInit();
            this.pnlBankSideButtons.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.grpSummary)).BeginInit();
            this.grpSummary.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pnlFooter)).BeginInit();
            this.pnlFooter.SuspendLayout();
            this.contextMenuStripDIT.SuspendLayout();
            this.contextMenuStripOC.SuspendLayout();
            this.SuspendLayout();
            // 
            // pnlHeader
            // 
            this.pnlHeader.Controls.Add(this.lblBranchCaption);
            this.pnlHeader.Controls.Add(this.cmbBranch);
            this.pnlHeader.Controls.Add(this.lblAccountCaption);
            this.pnlHeader.Controls.Add(this.cmbAccount);
            this.pnlHeader.Controls.Add(this.lblPeriodCaption);
            this.pnlHeader.Controls.Add(this.dtPeriod);
            this.pnlHeader.Controls.Add(this.btnLoad);
            this.pnlHeader.Controls.Add(this.lblStatus);
            this.pnlHeader.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlHeader.Location = new System.Drawing.Point(0, 0);
            this.pnlHeader.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.pnlHeader.Name = "pnlHeader";
            this.pnlHeader.Size = new System.Drawing.Size(1337, 69);
            this.pnlHeader.TabIndex = 4;
            // 
            // lblBranchCaption
            // 
            this.lblBranchCaption.Location = new System.Drawing.Point(13, 20);
            this.lblBranchCaption.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblBranchCaption.Name = "lblBranchCaption";
            this.lblBranchCaption.Size = new System.Drawing.Size(44, 16);
            this.lblBranchCaption.TabIndex = 0;
            this.lblBranchCaption.Text = "Branch:";
            // 
            // cmbBranch
            // 
            this.cmbBranch.Location = new System.Drawing.Point(75, 15);
            this.cmbBranch.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.cmbBranch.Name = "cmbBranch";
            this.cmbBranch.Properties.NullText = "";
            this.cmbBranch.Size = new System.Drawing.Size(127, 22);
            this.cmbBranch.TabIndex = 1;
            // 
            // lblAccountCaption
            // 
            this.lblAccountCaption.Location = new System.Drawing.Point(216, 20);
            this.lblAccountCaption.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblAccountCaption.Name = "lblAccountCaption";
            this.lblAccountCaption.Size = new System.Drawing.Size(81, 16);
            this.lblAccountCaption.TabIndex = 2;
            this.lblAccountCaption.Text = "Bank Account:";
            // 
            // cmbAccount
            // 
            this.cmbAccount.Location = new System.Drawing.Point(313, 15);
            this.cmbAccount.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.cmbAccount.Name = "cmbAccount";
            this.cmbAccount.Properties.NullText = "Select bank GL account...";
            this.cmbAccount.Size = new System.Drawing.Size(257, 22);
            this.cmbAccount.TabIndex = 3;
            // 
            // lblPeriodCaption
            // 
            this.lblPeriodCaption.Location = new System.Drawing.Point(582, 20);
            this.lblPeriodCaption.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblPeriodCaption.Name = "lblPeriodCaption";
            this.lblPeriodCaption.Size = new System.Drawing.Size(66, 16);
            this.lblPeriodCaption.TabIndex = 4;
            this.lblPeriodCaption.Text = "Period End:";
            // 
            // dtPeriod
            // 
            this.dtPeriod.EditValue = new System.DateTime(2026, 7, 15, 0, 0, 0, 0);
            this.dtPeriod.Location = new System.Drawing.Point(663, 15);
            this.dtPeriod.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.dtPeriod.Name = "dtPeriod";
            this.dtPeriod.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.dtPeriod.Properties.Mask.EditMask = "yyyy-MM-dd";
            this.dtPeriod.Size = new System.Drawing.Size(127, 22);
            this.dtPeriod.TabIndex = 5;
            // 
            // btnLoad
            // 
            this.btnLoad.Location = new System.Drawing.Point(804, 14);
            this.btnLoad.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.btnLoad.Name = "btnLoad";
            this.btnLoad.Size = new System.Drawing.Size(104, 32);
            this.btnLoad.TabIndex = 6;
            this.btnLoad.Text = "Load";
            this.btnLoad.Click += new System.EventHandler(this.btnLoad_Click);
            // 
            // lblStatus
            // 
            this.lblStatus.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblStatus.Location = new System.Drawing.Point(13, 47);
            this.lblStatus.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblStatus.Name = "lblStatus";
            this.lblStatus.Size = new System.Drawing.Size(887, 17);
            this.lblStatus.TabIndex = 7;
            // 
            // pnlBalances
            // 
            this.pnlBalances.Controls.Add(this.lblBookBalCaption);
            this.pnlBalances.Controls.Add(this.lblBookBal);
            this.pnlBalances.Controls.Add(this.lblBankBalCaption);
            this.pnlBalances.Controls.Add(this.txtBankBal);
            this.pnlBalances.Controls.Add(this.btnSaveHeader);
            this.pnlBalances.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlBalances.Location = new System.Drawing.Point(0, 69);
            this.pnlBalances.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.pnlBalances.Name = "pnlBalances";
            this.pnlBalances.Size = new System.Drawing.Size(1337, 49);
            this.pnlBalances.TabIndex = 3;
            // 
            // lblBookBalCaption
            // 
            this.lblBookBalCaption.Location = new System.Drawing.Point(13, 16);
            this.lblBookBalCaption.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblBookBalCaption.Name = "lblBookBalCaption";
            this.lblBookBalCaption.Size = new System.Drawing.Size(98, 16);
            this.lblBookBalCaption.TabIndex = 0;
            this.lblBookBalCaption.Text = "GL Book Balance:";
            // 
            // lblBookBal
            // 
            this.lblBookBal.Appearance.Font = new System.Drawing.Font("Courier New", 9.75F, System.Drawing.FontStyle.Bold);
            this.lblBookBal.Appearance.Options.UseFont = true;
            this.lblBookBal.Location = new System.Drawing.Point(152, 15);
            this.lblBookBal.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblBookBal.Name = "lblBookBal";
            this.lblBookBal.Size = new System.Drawing.Size(40, 18);
            this.lblBookBal.TabIndex = 1;
            this.lblBookBal.Text = "0.00";
            // 
            // lblBankBalCaption
            // 
            this.lblBankBalCaption.Location = new System.Drawing.Point(327, 16);
            this.lblBankBalCaption.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblBankBalCaption.Name = "lblBankBalCaption";
            this.lblBankBalCaption.Size = new System.Drawing.Size(143, 16);
            this.lblBankBalCaption.TabIndex = 2;
            this.lblBankBalCaption.Text = "Bank Statement Balance:";
            // 
            // txtBankBal
            // 
            this.txtBankBal.Location = new System.Drawing.Point(502, 11);
            this.txtBankBal.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.txtBankBal.Name = "txtBankBal";
            this.txtBankBal.Properties.Appearance.Options.UseTextOptions = true;
            this.txtBankBal.Properties.Appearance.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
            this.txtBankBal.Properties.Mask.EditMask = "n2";
            this.txtBankBal.Size = new System.Drawing.Size(139, 22);
            this.txtBankBal.TabIndex = 3;
            // 
            // btnSaveHeader
            // 
            this.btnSaveHeader.Location = new System.Drawing.Point(652, 10);
            this.btnSaveHeader.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.btnSaveHeader.Name = "btnSaveHeader";
            this.btnSaveHeader.Size = new System.Drawing.Size(127, 32);
            this.btnSaveHeader.TabIndex = 4;
            this.btnSaveHeader.Text = "Save Balance";
            // 
            // tabItems
            // 
            this.tabItems.Dock = System.Windows.Forms.DockStyle.Fill;
            this.tabItems.Location = new System.Drawing.Point(0, 118);
            this.tabItems.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.tabItems.Name = "tabItems";
            this.tabItems.SelectedTabPage = this.tabOC;
            this.tabItems.Size = new System.Drawing.Size(1337, 526);
            this.tabItems.TabIndex = 0;
            this.tabItems.TabPages.AddRange(new DevExpress.XtraTab.XtraTabPage[] {
            this.tabDIT,
            this.tabOC,
            this.tabBankSide});
            // 
            // tabOC
            // 
            this.tabOC.Controls.Add(this.panelControl5);
            this.tabOC.Controls.Add(this.panelControl6);
            this.tabOC.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.tabOC.Name = "tabOC";
            this.tabOC.Size = new System.Drawing.Size(1335, 496);
            this.tabOC.Text = "Deposit In Transit || Outstanding Checks";
            // 
            // panelControl5
            // 
            this.panelControl5.Controls.Add(this.tablePanel1);
            this.panelControl5.Controls.Add(this.panelControl3);
            this.panelControl5.Controls.Add(this.panelControl4);
            this.panelControl5.Dock = System.Windows.Forms.DockStyle.Fill;
            this.panelControl5.Location = new System.Drawing.Point(0, 0);
            this.panelControl5.Name = "panelControl5";
            this.panelControl5.Size = new System.Drawing.Size(1335, 446);
            this.panelControl5.TabIndex = 3;
            // 
            // tablePanel1
            // 
            this.tablePanel1.Columns.AddRange(new DevExpress.Utils.Layout.TablePanelColumn[] {
            new DevExpress.Utils.Layout.TablePanelColumn(DevExpress.Utils.Layout.TablePanelEntityStyle.Relative, 29.66F),
            new DevExpress.Utils.Layout.TablePanelColumn(DevExpress.Utils.Layout.TablePanelEntityStyle.Relative, 30.34F)});
            this.tablePanel1.Controls.Add(this.panelControl7);
            this.tablePanel1.Controls.Add(this.panelControl1);
            this.tablePanel1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.tablePanel1.Location = new System.Drawing.Point(2, 2);
            this.tablePanel1.Name = "tablePanel1";
            this.tablePanel1.Rows.AddRange(new DevExpress.Utils.Layout.TablePanelRow[] {
            new DevExpress.Utils.Layout.TablePanelRow(DevExpress.Utils.Layout.TablePanelEntityStyle.Absolute, 26F)});
            this.tablePanel1.Size = new System.Drawing.Size(1331, 442);
            this.tablePanel1.TabIndex = 4;
            // 
            // panelControl7
            // 
            this.tablePanel1.SetColumn(this.panelControl7, 1);
            this.panelControl7.Controls.Add(this.gridOC);
            this.panelControl7.Dock = System.Windows.Forms.DockStyle.Fill;
            this.panelControl7.Location = new System.Drawing.Point(661, 3);
            this.panelControl7.Name = "panelControl7";
            this.tablePanel1.SetRow(this.panelControl7, 0);
            this.panelControl7.Size = new System.Drawing.Size(667, 436);
            this.panelControl7.TabIndex = 1;
            // 
            // gridOC
            // 
            this.gridOC.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridOC.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.gridOC.Location = new System.Drawing.Point(2, 2);
            this.gridOC.MainView = this.viewOC;
            this.gridOC.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.gridOC.Name = "gridOC";
            this.gridOC.Size = new System.Drawing.Size(663, 432);
            this.gridOC.TabIndex = 0;
            this.gridOC.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.viewOC});
            this.gridOC.MouseUp += new System.Windows.Forms.MouseEventHandler(this.gridOC_MouseUp);
            // 
            // viewOC
            // 
            this.viewOC.DetailHeight = 431;
            this.viewOC.GridControl = this.gridOC;
            this.viewOC.Name = "viewOC";
            this.viewOC.OptionsBehavior.Editable = false;
            this.viewOC.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.viewOC.OptionsView.ShowGroupPanel = false;
            // 
            // panelControl1
            // 
            this.tablePanel1.SetColumn(this.panelControl1, 0);
            this.panelControl1.Controls.Add(this.gridDIT);
            this.panelControl1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.panelControl1.Location = new System.Drawing.Point(3, 3);
            this.panelControl1.Name = "panelControl1";
            this.tablePanel1.SetRow(this.panelControl1, 0);
            this.panelControl1.Size = new System.Drawing.Size(652, 436);
            this.panelControl1.TabIndex = 0;
            // 
            // gridDIT
            // 
            this.gridDIT.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridDIT.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.gridDIT.Location = new System.Drawing.Point(2, 2);
            this.gridDIT.MainView = this.viewDIT;
            this.gridDIT.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.gridDIT.Name = "gridDIT";
            this.gridDIT.Size = new System.Drawing.Size(648, 432);
            this.gridDIT.TabIndex = 0;
            this.gridDIT.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.viewDIT});
            this.gridDIT.MouseUp += new System.Windows.Forms.MouseEventHandler(this.gridDIT_MouseUp);
            // 
            // viewDIT
            // 
            this.viewDIT.DetailHeight = 431;
            this.viewDIT.GridControl = this.gridDIT;
            this.viewDIT.Name = "viewDIT";
            this.viewDIT.OptionsBehavior.Editable = false;
            this.viewDIT.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.viewDIT.OptionsView.ShowGroupPanel = false;
            // 
            // panelControl3
            // 
            this.panelControl3.Location = new System.Drawing.Point(287, 220);
            this.panelControl3.Name = "panelControl3";
            this.panelControl3.Size = new System.Drawing.Size(0, 0);
            this.panelControl3.TabIndex = 2;
            // 
            // panelControl4
            // 
            this.panelControl4.Location = new System.Drawing.Point(96, 69);
            this.panelControl4.Name = "panelControl4";
            this.panelControl4.Size = new System.Drawing.Size(0, 0);
            this.panelControl4.TabIndex = 3;
            // 
            // panelControl6
            // 
            this.panelControl6.Controls.Add(this.btnAutoMatch);
            this.panelControl6.Controls.Add(this.btnDeleteOC);
            this.panelControl6.Controls.Add(this.simpleButton1);
            this.panelControl6.Controls.Add(this.btnAddOC);
            this.panelControl6.Controls.Add(this.btnResolveOC);
            this.panelControl6.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.panelControl6.Location = new System.Drawing.Point(0, 446);
            this.panelControl6.Name = "panelControl6";
            this.panelControl6.Size = new System.Drawing.Size(1335, 50);
            this.panelControl6.TabIndex = 4;
            // 
            // btnAutoMatch
            // 
            this.btnAutoMatch.Location = new System.Drawing.Point(614, 11);
            this.btnAutoMatch.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.btnAutoMatch.Name = "btnAutoMatch";
            this.btnAutoMatch.Size = new System.Drawing.Size(197, 32);
            this.btnAutoMatch.TabIndex = 3;
            this.btnAutoMatch.Text = "Auto-Match Cleared Checks";
            // 
            // btnDeleteOC
            // 
            this.btnDeleteOC.Enabled = false;
            this.btnDeleteOC.Location = new System.Drawing.Point(518, 11);
            this.btnDeleteOC.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.btnDeleteOC.Name = "btnDeleteOC";
            this.btnDeleteOC.Size = new System.Drawing.Size(92, 32);
            this.btnDeleteOC.TabIndex = 2;
            this.btnDeleteOC.Text = "Delete";
            this.btnDeleteOC.Click += new System.EventHandler(this.btnDeleteOC_Click);
            // 
            // simpleButton1
            // 
            this.simpleButton1.Location = new System.Drawing.Point(4, 11);
            this.simpleButton1.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.simpleButton1.Name = "simpleButton1";
            this.simpleButton1.Size = new System.Drawing.Size(187, 32);
            this.simpleButton1.TabIndex = 1;
            this.simpleButton1.Text = "Add Deposit in Transit";
            this.simpleButton1.Click += new System.EventHandler(this.simpleButton1_Click);
            // 
            // btnAddOC
            // 
            this.btnAddOC.Location = new System.Drawing.Point(195, 11);
            this.btnAddOC.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.btnAddOC.Name = "btnAddOC";
            this.btnAddOC.Size = new System.Drawing.Size(187, 32);
            this.btnAddOC.TabIndex = 0;
            this.btnAddOC.Text = "Add Outstanding Check";
            this.btnAddOC.Click += new System.EventHandler(this.btnAddOC_Click);
            // 
            // btnResolveOC
            // 
            this.btnResolveOC.Enabled = false;
            this.btnResolveOC.Location = new System.Drawing.Point(387, 11);
            this.btnResolveOC.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.btnResolveOC.Name = "btnResolveOC";
            this.btnResolveOC.Size = new System.Drawing.Size(127, 32);
            this.btnResolveOC.TabIndex = 1;
            this.btnResolveOC.Text = "Mark Cleared";
            this.btnResolveOC.Click += new System.EventHandler(this.btnResolveOC_Click);
            // 
            // tabDIT
            // 
            this.tabDIT.Controls.Add(this.pnlDITButtons);
            this.tabDIT.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.tabDIT.Name = "tabDIT";
            this.tabDIT.PageVisible = false;
            this.tabDIT.Size = new System.Drawing.Size(1335, 496);
            // 
            // pnlDITButtons
            // 
            this.pnlDITButtons.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.pnlDITButtons.Location = new System.Drawing.Point(0, 444);
            this.pnlDITButtons.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.pnlDITButtons.Name = "pnlDITButtons";
            this.pnlDITButtons.Size = new System.Drawing.Size(1335, 52);
            this.pnlDITButtons.TabIndex = 1;
            // 
            // tabBankSide
            // 
            this.tabBankSide.Controls.Add(this.gridBankSide);
            this.tabBankSide.Controls.Add(this.pnlBankSideButtons);
            this.tabBankSide.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.tabBankSide.Name = "tabBankSide";
            this.tabBankSide.PageVisible = false;
            this.tabBankSide.Size = new System.Drawing.Size(1335, 496);
            this.tabBankSide.Text = "Bank-Side Items (BDM / BCM / Auto-Debit)";
            // 
            // gridBankSide
            // 
            this.gridBankSide.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridBankSide.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.gridBankSide.Location = new System.Drawing.Point(0, 0);
            this.gridBankSide.MainView = this.viewBankSide;
            this.gridBankSide.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.gridBankSide.Name = "gridBankSide";
            this.gridBankSide.Size = new System.Drawing.Size(1335, 453);
            this.gridBankSide.TabIndex = 0;
            this.gridBankSide.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.viewBankSide});
            // 
            // viewBankSide
            // 
            this.viewBankSide.DetailHeight = 431;
            this.viewBankSide.GridControl = this.gridBankSide;
            this.viewBankSide.Name = "viewBankSide";
            this.viewBankSide.OptionsBehavior.Editable = false;
            this.viewBankSide.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.viewBankSide.OptionsView.ShowGroupPanel = false;
            // 
            // pnlBankSideButtons
            // 
            this.pnlBankSideButtons.Controls.Add(this.btnAddBankSide);
            this.pnlBankSideButtons.Controls.Add(this.btnResolveBankSide);
            this.pnlBankSideButtons.Controls.Add(this.btnDeleteBankSide);
            this.pnlBankSideButtons.Controls.Add(this.btnPostAutoDebit);
            this.pnlBankSideButtons.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.pnlBankSideButtons.Location = new System.Drawing.Point(0, 453);
            this.pnlBankSideButtons.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.pnlBankSideButtons.Name = "pnlBankSideButtons";
            this.pnlBankSideButtons.Size = new System.Drawing.Size(1335, 43);
            this.pnlBankSideButtons.TabIndex = 1;
            // 
            // btnAddBankSide
            // 
            this.btnAddBankSide.Location = new System.Drawing.Point(8, 10);
            this.btnAddBankSide.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.btnAddBankSide.Name = "btnAddBankSide";
            this.btnAddBankSide.Size = new System.Drawing.Size(139, 32);
            this.btnAddBankSide.TabIndex = 0;
            this.btnAddBankSide.Text = "Add Bank Item";
            // 
            // btnResolveBankSide
            // 
            this.btnResolveBankSide.Enabled = false;
            this.btnResolveBankSide.Location = new System.Drawing.Point(159, 10);
            this.btnResolveBankSide.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.btnResolveBankSide.Name = "btnResolveBankSide";
            this.btnResolveBankSide.Size = new System.Drawing.Size(127, 32);
            this.btnResolveBankSide.TabIndex = 1;
            this.btnResolveBankSide.Text = "Mark Cleared";
            // 
            // btnDeleteBankSide
            // 
            this.btnDeleteBankSide.Enabled = false;
            this.btnDeleteBankSide.Location = new System.Drawing.Point(295, 10);
            this.btnDeleteBankSide.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.btnDeleteBankSide.Name = "btnDeleteBankSide";
            this.btnDeleteBankSide.Size = new System.Drawing.Size(92, 32);
            this.btnDeleteBankSide.TabIndex = 2;
            this.btnDeleteBankSide.Text = "Delete";
            // 
            // btnPostAutoDebit
            // 
            this.btnPostAutoDebit.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(255)))), ((int)(((byte)(244)))), ((int)(((byte)(219)))));
            this.btnPostAutoDebit.Appearance.Options.UseBackColor = true;
            this.btnPostAutoDebit.Enabled = false;
            this.btnPostAutoDebit.Location = new System.Drawing.Point(398, 10);
            this.btnPostAutoDebit.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.btnPostAutoDebit.Name = "btnPostAutoDebit";
            this.btnPostAutoDebit.Size = new System.Drawing.Size(139, 32);
            this.btnPostAutoDebit.TabIndex = 3;
            this.btnPostAutoDebit.Text = "Post Payment...";
            // 
            // grpSummary
            // 
            this.grpSummary.Controls.Add(this.lblBankStmtCaption);
            this.grpSummary.Controls.Add(this.lblBankStmt);
            this.grpSummary.Controls.Add(this.lblDITCaption);
            this.grpSummary.Controls.Add(this.lblDIT);
            this.grpSummary.Controls.Add(this.lblOCCaption);
            this.grpSummary.Controls.Add(this.lblOC);
            this.grpSummary.Controls.Add(this.lblAdjBankCaption);
            this.grpSummary.Controls.Add(this.lblAdjBank);
            this.grpSummary.Controls.Add(this.lblBookSideCaption);
            this.grpSummary.Controls.Add(this.lblBookSide);
            this.grpSummary.Controls.Add(this.lblBCMCaption);
            this.grpSummary.Controls.Add(this.lblBCM);
            this.grpSummary.Controls.Add(this.lblBDMCaption);
            this.grpSummary.Controls.Add(this.lblBDM);
            this.grpSummary.Controls.Add(this.lblAdjBookCaption);
            this.grpSummary.Controls.Add(this.lblAdjBook);
            this.grpSummary.Controls.Add(this.lblDiffCaption);
            this.grpSummary.Controls.Add(this.lblDiff);
            this.grpSummary.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.grpSummary.Location = new System.Drawing.Point(0, 644);
            this.grpSummary.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.grpSummary.Name = "grpSummary";
            this.grpSummary.Size = new System.Drawing.Size(1337, 185);
            this.grpSummary.TabIndex = 1;
            this.grpSummary.Text = "Reconciliation Summary";
            // 
            // lblBankStmtCaption
            // 
            this.lblBankStmtCaption.Location = new System.Drawing.Point(19, 37);
            this.lblBankStmtCaption.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblBankStmtCaption.Name = "lblBankStmtCaption";
            this.lblBankStmtCaption.Size = new System.Drawing.Size(138, 16);
            this.lblBankStmtCaption.TabIndex = 0;
            this.lblBankStmtCaption.Text = "Bank Statement Balance";
            // 
            // lblBankStmt
            // 
            this.lblBankStmt.Appearance.Font = new System.Drawing.Font("Courier New", 9.75F);
            this.lblBankStmt.Appearance.Options.UseFont = true;
            this.lblBankStmt.Location = new System.Drawing.Point(257, 37);
            this.lblBankStmt.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblBankStmt.Name = "lblBankStmt";
            this.lblBankStmt.Size = new System.Drawing.Size(0, 18);
            this.lblBankStmt.TabIndex = 1;
            // 
            // lblDITCaption
            // 
            this.lblDITCaption.Location = new System.Drawing.Point(19, 64);
            this.lblDITCaption.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblDITCaption.Name = "lblDITCaption";
            this.lblDITCaption.Size = new System.Drawing.Size(137, 16);
            this.lblDITCaption.TabIndex = 2;
            this.lblDITCaption.Text = "Add: Deposits in Transit";
            // 
            // lblDIT
            // 
            this.lblDIT.Appearance.Font = new System.Drawing.Font("Courier New", 9.75F);
            this.lblDIT.Appearance.Options.UseFont = true;
            this.lblDIT.Location = new System.Drawing.Point(257, 64);
            this.lblDIT.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblDIT.Name = "lblDIT";
            this.lblDIT.Size = new System.Drawing.Size(0, 18);
            this.lblDIT.TabIndex = 3;
            // 
            // lblOCCaption
            // 
            this.lblOCCaption.Location = new System.Drawing.Point(19, 91);
            this.lblOCCaption.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblOCCaption.Name = "lblOCCaption";
            this.lblOCCaption.Size = new System.Drawing.Size(146, 16);
            this.lblOCCaption.TabIndex = 4;
            this.lblOCCaption.Text = "Less: Outstanding Checks";
            // 
            // lblOC
            // 
            this.lblOC.Appearance.Font = new System.Drawing.Font("Courier New", 9.75F);
            this.lblOC.Appearance.Options.UseFont = true;
            this.lblOC.Location = new System.Drawing.Point(257, 91);
            this.lblOC.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblOC.Name = "lblOC";
            this.lblOC.Size = new System.Drawing.Size(0, 18);
            this.lblOC.TabIndex = 5;
            // 
            // lblAdjBankCaption
            // 
            this.lblAdjBankCaption.Appearance.Font = new System.Drawing.Font("Tahoma", 8.25F, System.Drawing.FontStyle.Bold);
            this.lblAdjBankCaption.Appearance.Options.UseFont = true;
            this.lblAdjBankCaption.Location = new System.Drawing.Point(19, 123);
            this.lblAdjBankCaption.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblAdjBankCaption.Name = "lblAdjBankCaption";
            this.lblAdjBankCaption.Size = new System.Drawing.Size(159, 17);
            this.lblAdjBankCaption.TabIndex = 6;
            this.lblAdjBankCaption.Text = "Adjusted Bank Balance";
            // 
            // lblAdjBank
            // 
            this.lblAdjBank.Appearance.Font = new System.Drawing.Font("Courier New", 9.75F);
            this.lblAdjBank.Appearance.Options.UseFont = true;
            this.lblAdjBank.Location = new System.Drawing.Point(257, 123);
            this.lblAdjBank.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblAdjBank.Name = "lblAdjBank";
            this.lblAdjBank.Size = new System.Drawing.Size(0, 18);
            this.lblAdjBank.TabIndex = 7;
            // 
            // lblBookSideCaption
            // 
            this.lblBookSideCaption.Location = new System.Drawing.Point(489, 37);
            this.lblBookSideCaption.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblBookSideCaption.Name = "lblBookSideCaption";
            this.lblBookSideCaption.Size = new System.Drawing.Size(93, 16);
            this.lblBookSideCaption.TabIndex = 8;
            this.lblBookSideCaption.Text = "GL Book Balance";
            // 
            // lblBookSide
            // 
            this.lblBookSide.Appearance.Font = new System.Drawing.Font("Courier New", 9.75F);
            this.lblBookSide.Appearance.Options.UseFont = true;
            this.lblBookSide.Location = new System.Drawing.Point(727, 37);
            this.lblBookSide.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblBookSide.Name = "lblBookSide";
            this.lblBookSide.Size = new System.Drawing.Size(0, 18);
            this.lblBookSide.TabIndex = 9;
            // 
            // lblBCMCaption
            // 
            this.lblBCMCaption.Location = new System.Drawing.Point(489, 64);
            this.lblBCMCaption.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblBCMCaption.Name = "lblBCMCaption";
            this.lblBCMCaption.Size = new System.Drawing.Size(141, 16);
            this.lblBCMCaption.TabIndex = 10;
            this.lblBCMCaption.Text = "Add: Bank Credit Memos";
            // 
            // lblBCM
            // 
            this.lblBCM.Appearance.Font = new System.Drawing.Font("Courier New", 9.75F);
            this.lblBCM.Appearance.Options.UseFont = true;
            this.lblBCM.Location = new System.Drawing.Point(727, 64);
            this.lblBCM.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblBCM.Name = "lblBCM";
            this.lblBCM.Size = new System.Drawing.Size(0, 18);
            this.lblBCM.TabIndex = 11;
            // 
            // lblBDMCaption
            // 
            this.lblBDMCaption.Location = new System.Drawing.Point(489, 91);
            this.lblBDMCaption.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblBDMCaption.Name = "lblBDMCaption";
            this.lblBDMCaption.Size = new System.Drawing.Size(218, 16);
            this.lblBDMCaption.TabIndex = 12;
            this.lblBDMCaption.Text = "Less: Bank Debit Memos / Auto-Debits";
            // 
            // lblBDM
            // 
            this.lblBDM.Appearance.Font = new System.Drawing.Font("Courier New", 9.75F);
            this.lblBDM.Appearance.Options.UseFont = true;
            this.lblBDM.Location = new System.Drawing.Point(727, 91);
            this.lblBDM.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblBDM.Name = "lblBDM";
            this.lblBDM.Size = new System.Drawing.Size(0, 18);
            this.lblBDM.TabIndex = 13;
            // 
            // lblAdjBookCaption
            // 
            this.lblAdjBookCaption.Appearance.Font = new System.Drawing.Font("Tahoma", 8.25F, System.Drawing.FontStyle.Bold);
            this.lblAdjBookCaption.Appearance.Options.UseFont = true;
            this.lblAdjBookCaption.Location = new System.Drawing.Point(489, 123);
            this.lblAdjBookCaption.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblAdjBookCaption.Name = "lblAdjBookCaption";
            this.lblAdjBookCaption.Size = new System.Drawing.Size(160, 17);
            this.lblAdjBookCaption.TabIndex = 14;
            this.lblAdjBookCaption.Text = "Adjusted Book Balance";
            // 
            // lblAdjBook
            // 
            this.lblAdjBook.Appearance.Font = new System.Drawing.Font("Courier New", 9.75F);
            this.lblAdjBook.Appearance.Options.UseFont = true;
            this.lblAdjBook.Location = new System.Drawing.Point(727, 123);
            this.lblAdjBook.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblAdjBook.Name = "lblAdjBook";
            this.lblAdjBook.Size = new System.Drawing.Size(0, 18);
            this.lblAdjBook.TabIndex = 15;
            // 
            // lblDiffCaption
            // 
            this.lblDiffCaption.Location = new System.Drawing.Point(19, 155);
            this.lblDiffCaption.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblDiffCaption.Name = "lblDiffCaption";
            this.lblDiffCaption.Size = new System.Drawing.Size(63, 16);
            this.lblDiffCaption.TabIndex = 16;
            this.lblDiffCaption.Text = "Difference:";
            // 
            // lblDiff
            // 
            this.lblDiff.Appearance.Font = new System.Drawing.Font("Courier New", 12F, System.Drawing.FontStyle.Bold);
            this.lblDiff.Appearance.Options.UseFont = true;
            this.lblDiff.Location = new System.Drawing.Point(139, 153);
            this.lblDiff.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.lblDiff.Name = "lblDiff";
            this.lblDiff.Size = new System.Drawing.Size(0, 23);
            this.lblDiff.TabIndex = 17;
            // 
            // pnlFooter
            // 
            this.pnlFooter.Controls.Add(this.btnLock);
            this.pnlFooter.Controls.Add(this.btnPrint);
            this.pnlFooter.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.pnlFooter.Location = new System.Drawing.Point(0, 829);
            this.pnlFooter.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.pnlFooter.Name = "pnlFooter";
            this.pnlFooter.Size = new System.Drawing.Size(1337, 57);
            this.pnlFooter.TabIndex = 2;
            // 
            // btnLock
            // 
            this.btnLock.Location = new System.Drawing.Point(722, 12);
            this.btnLock.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.btnLock.Name = "btnLock";
            this.btnLock.Size = new System.Drawing.Size(127, 34);
            this.btnLock.TabIndex = 0;
            this.btnLock.Text = "Lock Period";
            // 
            // btnPrint
            // 
            this.btnPrint.Location = new System.Drawing.Point(862, 12);
            this.btnPrint.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.btnPrint.Name = "btnPrint";
            this.btnPrint.Size = new System.Drawing.Size(104, 34);
            this.btnPrint.TabIndex = 1;
            this.btnPrint.Text = "Print";
            // 
            // btnDeleteDIT
            // 
            this.btnDeleteDIT.Enabled = false;
            this.btnDeleteDIT.Location = new System.Drawing.Point(293, 10);
            this.btnDeleteDIT.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.btnDeleteDIT.Name = "btnDeleteDIT";
            this.btnDeleteDIT.Size = new System.Drawing.Size(79, 32);
            this.btnDeleteDIT.TabIndex = 2;
            // 
            // btnResolveDIT
            // 
            this.btnResolveDIT.Enabled = false;
            this.btnResolveDIT.Location = new System.Drawing.Point(175, 10);
            this.btnResolveDIT.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.btnResolveDIT.Name = "btnResolveDIT";
            this.btnResolveDIT.Size = new System.Drawing.Size(109, 32);
            this.btnResolveDIT.TabIndex = 1;
            // 
            // btnAddDIT
            // 
            this.btnAddDIT.Location = new System.Drawing.Point(7, 10);
            this.btnAddDIT.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.btnAddDIT.Name = "btnAddDIT";
            this.btnAddDIT.Size = new System.Drawing.Size(160, 32);
            this.btnAddDIT.TabIndex = 0;
            // 
            // contextMenuStripDIT
            // 
            this.contextMenuStripDIT.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.contextMenuStripDIT.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.markAsClearedToolStripMenuItem1});
            this.contextMenuStripDIT.Name = "contextMenuStripDIT";
            this.contextMenuStripDIT.Size = new System.Drawing.Size(185, 28);
            // 
            // markAsClearedToolStripMenuItem1
            // 
            this.markAsClearedToolStripMenuItem1.Name = "markAsClearedToolStripMenuItem1";
            this.markAsClearedToolStripMenuItem1.Size = new System.Drawing.Size(184, 24);
            this.markAsClearedToolStripMenuItem1.Text = "Mark as Cleared";
            this.markAsClearedToolStripMenuItem1.Click += new System.EventHandler(this.markAsClearedToolStripMenuItem1_Click);
            // 
            // contextMenuStripOC
            // 
            this.contextMenuStripOC.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.contextMenuStripOC.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.markAsClearedToolStripMenuItem});
            this.contextMenuStripOC.Name = "contextMenuStripDIT";
            this.contextMenuStripOC.Size = new System.Drawing.Size(185, 28);
            // 
            // markAsClearedToolStripMenuItem
            // 
            this.markAsClearedToolStripMenuItem.Name = "markAsClearedToolStripMenuItem";
            this.markAsClearedToolStripMenuItem.Size = new System.Drawing.Size(184, 24);
            this.markAsClearedToolStripMenuItem.Text = "Mark as Cleared";
            this.markAsClearedToolStripMenuItem.Click += new System.EventHandler(this.markAsClearedToolStripMenuItem_Click);
            // 
            // BankReconFormV2
            // 
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Inherit;
            this.Controls.Add(this.tabItems);
            this.Controls.Add(this.grpSummary);
            this.Controls.Add(this.pnlFooter);
            this.Controls.Add(this.pnlBalances);
            this.Controls.Add(this.pnlHeader);
            this.Margin = new System.Windows.Forms.Padding(2, 4, 2, 4);
            this.MinimumSize = new System.Drawing.Size(957, 600);
            this.Name = "BankReconFormV2";
            this.Size = new System.Drawing.Size(1337, 886);
            ((System.ComponentModel.ISupportInitialize)(this.pnlHeader)).EndInit();
            this.pnlHeader.ResumeLayout(false);
            this.pnlHeader.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.cmbBranch.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbAccount.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtPeriod.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtPeriod.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlBalances)).EndInit();
            this.pnlBalances.ResumeLayout(false);
            this.pnlBalances.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtBankBal.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.tabItems)).EndInit();
            this.tabItems.ResumeLayout(false);
            this.tabOC.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.panelControl5)).EndInit();
            this.panelControl5.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.tablePanel1)).EndInit();
            this.tablePanel1.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.panelControl7)).EndInit();
            this.panelControl7.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridOC)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.viewOC)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl1)).EndInit();
            this.panelControl1.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridDIT)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.viewDIT)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl3)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl4)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl6)).EndInit();
            this.panelControl6.ResumeLayout(false);
            this.tabDIT.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.pnlDITButtons)).EndInit();
            this.tabBankSide.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridBankSide)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.viewBankSide)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlBankSideButtons)).EndInit();
            this.pnlBankSideButtons.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.grpSummary)).EndInit();
            this.grpSummary.ResumeLayout(false);
            this.grpSummary.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pnlFooter)).EndInit();
            this.pnlFooter.ResumeLayout(false);
            this.contextMenuStripDIT.ResumeLayout(false);
            this.contextMenuStripOC.ResumeLayout(false);
            this.ResumeLayout(false);

        }

        private DevExpress.XtraTab.XtraTabPage tabDIT;
        private DevExpress.XtraEditors.PanelControl pnlDITButtons;
        private DevExpress.XtraEditors.SimpleButton btnDeleteDIT;
        private DevExpress.XtraEditors.SimpleButton btnResolveDIT;
        private DevExpress.XtraEditors.SimpleButton btnAddDIT;
        private System.Windows.Forms.ContextMenuStrip contextMenuStripDIT;
        private System.Windows.Forms.ContextMenuStrip contextMenuStripOC;
        private DevExpress.XtraEditors.PanelControl panelControl4;
        private DevExpress.XtraEditors.PanelControl panelControl3;
        private System.Windows.Forms.ToolStripMenuItem markAsClearedToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem markAsClearedToolStripMenuItem1;
        private DevExpress.XtraEditors.PanelControl panelControl5;
        private DevExpress.XtraEditors.SimpleButton simpleButton1;
        private DevExpress.Utils.Layout.TablePanel tablePanel1;
        private DevExpress.XtraEditors.PanelControl panelControl7;
        private DevExpress.XtraEditors.PanelControl panelControl1;
        private DevExpress.XtraEditors.PanelControl panelControl6;
    }
}