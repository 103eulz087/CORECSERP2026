namespace SalesInventorySystem.AccountingDevEx
{
    partial class ManualTicketFormV1
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        private void InitializeComponent()
        {
            this.tableLayoutPanelMain = new System.Windows.Forms.TableLayoutPanel();
            this.panelBanner = new System.Windows.Forms.Panel();
            this.lblBannerTitle = new DevExpress.XtraEditors.LabelControl();
            this.lblBannerSub = new DevExpress.XtraEditors.LabelControl();
            this.panelHeader = new System.Windows.Forms.Panel();
            this.flowLayoutPanelHeader = new System.Windows.Forms.FlowLayoutPanel();
            this.radSourceType = new DevExpress.XtraEditors.RadioGroup();
            this.cmbAdjType = new DevExpress.XtraEditors.ComboBoxEdit();
            this.cmbSupplier = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.cmbSupplierView = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.cmbInvoice = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.cmbInvoiceView = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.lblInvoiceBalance = new DevExpress.XtraEditors.LabelControl();
            this.txtAdjAmount = new DevExpress.XtraEditors.TextEdit();
            this.cmbAPImpact = new DevExpress.XtraEditors.ComboBoxEdit();
            this.txtOrigTicket = new DevExpress.XtraEditors.TextEdit();
            this.txtDocRef = new DevExpress.XtraEditors.TextEdit();
            this.txtRemarks = new DevExpress.XtraEditors.TextEdit();
            this.splitContainerControl1 = new DevExpress.XtraEditors.SplitContainerControl();
            this.tableLayoutPanelLeft = new System.Windows.Forms.TableLayoutPanel();
            this.lblLegs = new DevExpress.XtraEditors.LabelControl();
            this.flowLayoutPanelLegBar = new System.Windows.Forms.FlowLayoutPanel();
            this.cmbLegAccount = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.cmbLegAccountView = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.cmbLegDC = new DevExpress.XtraEditors.ComboBoxEdit();
            this.txtLegAmount = new DevExpress.XtraEditors.TextEdit();
            this.txtLegDesc = new DevExpress.XtraEditors.TextEdit();
            this.btnAddLeg = new DevExpress.XtraEditors.SimpleButton();
            this.btnRemoveLeg = new DevExpress.XtraEditors.SimpleButton();
            this.gridLegs = new DevExpress.XtraGrid.GridControl();
            this.viewLegs = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.tableLayoutPanelRight = new System.Windows.Forms.TableLayoutPanel();
            this.lblPend = new DevExpress.XtraEditors.LabelControl();
            this.gridPending = new DevExpress.XtraGrid.GridControl();
            this.viewPending = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.panelToolbar = new System.Windows.Forms.Panel();
            this.lblStatus = new DevExpress.XtraEditors.LabelControl();
            this.flowLayoutPanelToolbar = new System.Windows.Forms.FlowLayoutPanel();
            this.btnPost = new DevExpress.XtraEditors.SimpleButton();
            this.btnApprove = new DevExpress.XtraEditors.SimpleButton();
            this.btnReject = new DevExpress.XtraEditors.SimpleButton();
            this.btnRefresh = new DevExpress.XtraEditors.SimpleButton();
            this.tableLayoutPanelMain.SuspendLayout();
            this.panelBanner.SuspendLayout();
            this.panelHeader.SuspendLayout();
            this.flowLayoutPanelHeader.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.radSourceType.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbAdjType.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbSupplier.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbSupplierView)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbInvoice.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbInvoiceView)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtAdjAmount.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbAPImpact.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtOrigTicket.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDocRef.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtRemarks.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.splitContainerControl1)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.splitContainerControl1.Panel1)).BeginInit();
            this.splitContainerControl1.Panel1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.splitContainerControl1.Panel2)).BeginInit();
            this.splitContainerControl1.Panel2.SuspendLayout();
            this.splitContainerControl1.SuspendLayout();
            this.tableLayoutPanelLeft.SuspendLayout();
            this.flowLayoutPanelLegBar.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.cmbLegAccount.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbLegAccountView)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbLegDC.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtLegAmount.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtLegDesc.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridLegs)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.viewLegs)).BeginInit();
            this.tableLayoutPanelRight.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridPending)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.viewPending)).BeginInit();
            this.panelToolbar.SuspendLayout();
            this.flowLayoutPanelToolbar.SuspendLayout();
            this.SuspendLayout();
            // 
            // tableLayoutPanelMain
            // 
            this.tableLayoutPanelMain.ColumnCount = 1;
            this.tableLayoutPanelMain.ColumnStyles.Add(new System.Windows.Forms.ColumnStyle(System.Windows.Forms.SizeType.Percent, 100F));
            this.tableLayoutPanelMain.Controls.Add(this.panelBanner, 0, 0);
            this.tableLayoutPanelMain.Controls.Add(this.panelHeader, 0, 1);
            this.tableLayoutPanelMain.Controls.Add(this.splitContainerControl1, 0, 2);
            this.tableLayoutPanelMain.Controls.Add(this.panelToolbar, 0, 3);
            this.tableLayoutPanelMain.Dock = System.Windows.Forms.DockStyle.Fill;
            this.tableLayoutPanelMain.Location = new System.Drawing.Point(0, 0);
            this.tableLayoutPanelMain.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.tableLayoutPanelMain.Name = "tableLayoutPanelMain";
            this.tableLayoutPanelMain.RowCount = 4;
            this.tableLayoutPanelMain.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Absolute, 52F));
            this.tableLayoutPanelMain.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Absolute, 196F));
            this.tableLayoutPanelMain.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Percent, 100F));
            this.tableLayoutPanelMain.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Absolute, 44F));
            this.tableLayoutPanelMain.Size = new System.Drawing.Size(1279, 800);
            this.tableLayoutPanelMain.TabIndex = 0;
            // 
            // panelBanner
            // 
            this.panelBanner.Controls.Add(this.lblBannerTitle);
            this.panelBanner.Controls.Add(this.lblBannerSub);
            this.panelBanner.Dock = System.Windows.Forms.DockStyle.Fill;
            this.panelBanner.Location = new System.Drawing.Point(2, 3);
            this.panelBanner.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.panelBanner.Name = "panelBanner";
            this.panelBanner.Size = new System.Drawing.Size(1275, 46);
            this.panelBanner.TabIndex = 0;
            // 
            // lblBannerTitle
            // 
            this.lblBannerTitle.Location = new System.Drawing.Point(13, 12);
            this.lblBannerTitle.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.lblBannerTitle.Name = "lblBannerTitle";
            this.lblBannerTitle.Size = new System.Drawing.Size(79, 13);
            this.lblBannerTitle.TabIndex = 0;
            this.lblBannerTitle.Text = "Manual Ticketing";
            // 
            // lblBannerSub
            // 
            this.lblBannerSub.Location = new System.Drawing.Point(13, 29);
            this.lblBannerSub.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.lblBannerSub.Name = "lblBannerSub";
            this.lblBannerSub.Size = new System.Drawing.Size(385, 13);
            this.lblBannerSub.TabIndex = 1;
            this.lblBannerSub.Text = "Purchase Adjustments (APACCOUNTS) · Expense Adjustments (ExpenseMaster)";
            // 
            // panelHeader
            // 
            this.panelHeader.Controls.Add(this.flowLayoutPanelHeader);
            this.panelHeader.Dock = System.Windows.Forms.DockStyle.Fill;
            this.panelHeader.Location = new System.Drawing.Point(2, 55);
            this.panelHeader.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.panelHeader.Name = "panelHeader";
            this.panelHeader.Size = new System.Drawing.Size(1275, 190);
            this.panelHeader.TabIndex = 1;
            // 
            // flowLayoutPanelHeader
            // 
            this.flowLayoutPanelHeader.Controls.Add(this.radSourceType);
            this.flowLayoutPanelHeader.Controls.Add(this.cmbAdjType);
            this.flowLayoutPanelHeader.Controls.Add(this.cmbSupplier);
            this.flowLayoutPanelHeader.Controls.Add(this.cmbInvoice);
            this.flowLayoutPanelHeader.Controls.Add(this.lblInvoiceBalance);
            this.flowLayoutPanelHeader.Controls.Add(this.txtAdjAmount);
            this.flowLayoutPanelHeader.Controls.Add(this.cmbAPImpact);
            this.flowLayoutPanelHeader.Controls.Add(this.txtOrigTicket);
            this.flowLayoutPanelHeader.Controls.Add(this.txtDocRef);
            this.flowLayoutPanelHeader.Controls.Add(this.txtRemarks);
            this.flowLayoutPanelHeader.Dock = System.Windows.Forms.DockStyle.Fill;
            this.flowLayoutPanelHeader.Location = new System.Drawing.Point(0, 0);
            this.flowLayoutPanelHeader.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.flowLayoutPanelHeader.Name = "flowLayoutPanelHeader";
            this.flowLayoutPanelHeader.Padding = new System.Windows.Forms.Padding(10, 10, 10, 10);
            this.flowLayoutPanelHeader.Size = new System.Drawing.Size(1275, 190);
            this.flowLayoutPanelHeader.TabIndex = 0;
            // 
            // radSourceType
            // 
            this.radSourceType.Location = new System.Drawing.Point(12, 13);
            this.radSourceType.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.radSourceType.Name = "radSourceType";
            this.radSourceType.Size = new System.Drawing.Size(149, 40);
            this.radSourceType.TabIndex = 0;
            // 
            // cmbAdjType
            // 
            this.cmbAdjType.Location = new System.Drawing.Point(165, 13);
            this.cmbAdjType.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.cmbAdjType.Name = "cmbAdjType";
            this.cmbAdjType.Size = new System.Drawing.Size(139, 20);
            this.cmbAdjType.TabIndex = 1;
            // 
            // cmbSupplier
            // 
            this.cmbSupplier.Location = new System.Drawing.Point(308, 13);
            this.cmbSupplier.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.cmbSupplier.Name = "cmbSupplier";
            this.cmbSupplier.Properties.PopupView = this.cmbSupplierView;
            this.cmbSupplier.Size = new System.Drawing.Size(199, 20);
            this.cmbSupplier.TabIndex = 2;
            // 
            // cmbSupplierView
            // 
            this.cmbSupplierView.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.cmbSupplierView.Name = "cmbSupplierView";
            this.cmbSupplierView.OptionsEditForm.PopupEditFormWidth = 686;
            this.cmbSupplierView.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.cmbSupplierView.OptionsView.ShowGroupPanel = false;
            // 
            // cmbInvoice
            // 
            this.cmbInvoice.Location = new System.Drawing.Point(511, 13);
            this.cmbInvoice.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.cmbInvoice.Name = "cmbInvoice";
            this.cmbInvoice.Properties.PopupView = this.cmbInvoiceView;
            this.cmbInvoice.Size = new System.Drawing.Size(199, 20);
            this.cmbInvoice.TabIndex = 3;
            // 
            // cmbInvoiceView
            // 
            this.cmbInvoiceView.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.cmbInvoiceView.Name = "cmbInvoiceView";
            this.cmbInvoiceView.OptionsEditForm.PopupEditFormWidth = 686;
            this.cmbInvoiceView.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.cmbInvoiceView.OptionsView.ShowGroupPanel = false;
            // 
            // lblInvoiceBalance
            // 
            this.lblInvoiceBalance.Location = new System.Drawing.Point(714, 13);
            this.lblInvoiceBalance.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.lblInvoiceBalance.Name = "lblInvoiceBalance";
            this.lblInvoiceBalance.Size = new System.Drawing.Size(0, 13);
            this.lblInvoiceBalance.TabIndex = 4;
            // 
            // txtAdjAmount
            // 
            this.txtAdjAmount.Location = new System.Drawing.Point(718, 13);
            this.txtAdjAmount.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.txtAdjAmount.Name = "txtAdjAmount";
            this.txtAdjAmount.Size = new System.Drawing.Size(100, 20);
            this.txtAdjAmount.TabIndex = 5;
            // 
            // cmbAPImpact
            // 
            this.cmbAPImpact.Location = new System.Drawing.Point(822, 13);
            this.cmbAPImpact.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.cmbAPImpact.Name = "cmbAPImpact";
            this.cmbAPImpact.Size = new System.Drawing.Size(100, 20);
            this.cmbAPImpact.TabIndex = 6;
            // 
            // txtOrigTicket
            // 
            this.txtOrigTicket.Location = new System.Drawing.Point(926, 13);
            this.txtOrigTicket.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.txtOrigTicket.Name = "txtOrigTicket";
            this.txtOrigTicket.Size = new System.Drawing.Size(119, 20);
            this.txtOrigTicket.TabIndex = 7;
            // 
            // txtDocRef
            // 
            this.txtDocRef.Location = new System.Drawing.Point(1049, 13);
            this.txtDocRef.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.txtDocRef.Name = "txtDocRef";
            this.txtDocRef.Size = new System.Drawing.Size(119, 20);
            this.txtDocRef.TabIndex = 8;
            // 
            // txtRemarks
            // 
            this.txtRemarks.Location = new System.Drawing.Point(12, 59);
            this.txtRemarks.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.txtRemarks.Name = "txtRemarks";
            this.txtRemarks.Size = new System.Drawing.Size(299, 20);
            this.txtRemarks.TabIndex = 9;
            // 
            // splitContainerControl1
            // 
            this.splitContainerControl1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.splitContainerControl1.Location = new System.Drawing.Point(2, 251);
            this.splitContainerControl1.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.splitContainerControl1.Name = "splitContainerControl1";
            // 
            // splitContainerControl1.Panel1
            // 
            this.splitContainerControl1.Panel1.Controls.Add(this.tableLayoutPanelLeft);
            this.splitContainerControl1.Panel1.Text = "Panel1";
            // 
            // splitContainerControl1.Panel2
            // 
            this.splitContainerControl1.Panel2.Controls.Add(this.tableLayoutPanelRight);
            this.splitContainerControl1.Panel2.Text = "Panel2";
            this.splitContainerControl1.Size = new System.Drawing.Size(1275, 502);
            this.splitContainerControl1.SplitterPosition = 600;
            this.splitContainerControl1.TabIndex = 2;
            // 
            // tableLayoutPanelLeft
            // 
            this.tableLayoutPanelLeft.ColumnCount = 1;
            this.tableLayoutPanelLeft.ColumnStyles.Add(new System.Windows.Forms.ColumnStyle(System.Windows.Forms.SizeType.Percent, 100F));
            this.tableLayoutPanelLeft.Controls.Add(this.lblLegs, 0, 0);
            this.tableLayoutPanelLeft.Controls.Add(this.flowLayoutPanelLegBar, 0, 1);
            this.tableLayoutPanelLeft.Controls.Add(this.gridLegs, 0, 2);
            this.tableLayoutPanelLeft.Dock = System.Windows.Forms.DockStyle.Fill;
            this.tableLayoutPanelLeft.Location = new System.Drawing.Point(0, 0);
            this.tableLayoutPanelLeft.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.tableLayoutPanelLeft.Name = "tableLayoutPanelLeft";
            this.tableLayoutPanelLeft.RowCount = 3;
            this.tableLayoutPanelLeft.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Absolute, 20F));
            this.tableLayoutPanelLeft.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Absolute, 69F));
            this.tableLayoutPanelLeft.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Percent, 100F));
            this.tableLayoutPanelLeft.Size = new System.Drawing.Size(600, 502);
            this.tableLayoutPanelLeft.TabIndex = 0;
            // 
            // lblLegs
            // 
            this.lblLegs.Dock = System.Windows.Forms.DockStyle.Fill;
            this.lblLegs.Location = new System.Drawing.Point(2, 3);
            this.lblLegs.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.lblLegs.Name = "lblLegs";
            this.lblLegs.Size = new System.Drawing.Size(596, 14);
            this.lblLegs.TabIndex = 0;
            this.lblLegs.Text = "GL LEGS";
            // 
            // flowLayoutPanelLegBar
            // 
            this.flowLayoutPanelLegBar.Controls.Add(this.cmbLegAccount);
            this.flowLayoutPanelLegBar.Controls.Add(this.cmbLegDC);
            this.flowLayoutPanelLegBar.Controls.Add(this.txtLegAmount);
            this.flowLayoutPanelLegBar.Controls.Add(this.txtLegDesc);
            this.flowLayoutPanelLegBar.Controls.Add(this.btnAddLeg);
            this.flowLayoutPanelLegBar.Controls.Add(this.btnRemoveLeg);
            this.flowLayoutPanelLegBar.Dock = System.Windows.Forms.DockStyle.Fill;
            this.flowLayoutPanelLegBar.Location = new System.Drawing.Point(2, 23);
            this.flowLayoutPanelLegBar.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.flowLayoutPanelLegBar.Name = "flowLayoutPanelLegBar";
            this.flowLayoutPanelLegBar.Size = new System.Drawing.Size(596, 63);
            this.flowLayoutPanelLegBar.TabIndex = 1;
            // 
            // cmbLegAccount
            // 
            this.cmbLegAccount.Location = new System.Drawing.Point(2, 3);
            this.cmbLegAccount.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.cmbLegAccount.Name = "cmbLegAccount";
            this.cmbLegAccount.Properties.PopupView = this.cmbLegAccountView;
            this.cmbLegAccount.Size = new System.Drawing.Size(149, 20);
            this.cmbLegAccount.TabIndex = 0;
            // 
            // cmbLegAccountView
            // 
            this.cmbLegAccountView.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.cmbLegAccountView.Name = "cmbLegAccountView";
            this.cmbLegAccountView.OptionsEditForm.PopupEditFormWidth = 686;
            this.cmbLegAccountView.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.cmbLegAccountView.OptionsView.ShowGroupPanel = false;
            // 
            // cmbLegDC
            // 
            this.cmbLegDC.Location = new System.Drawing.Point(155, 3);
            this.cmbLegDC.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.cmbLegDC.Name = "cmbLegDC";
            this.cmbLegDC.Size = new System.Drawing.Size(79, 20);
            this.cmbLegDC.TabIndex = 1;
            // 
            // txtLegAmount
            // 
            this.txtLegAmount.Location = new System.Drawing.Point(238, 3);
            this.txtLegAmount.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.txtLegAmount.Name = "txtLegAmount";
            this.txtLegAmount.Size = new System.Drawing.Size(100, 20);
            this.txtLegAmount.TabIndex = 2;
            // 
            // txtLegDesc
            // 
            this.txtLegDesc.Location = new System.Drawing.Point(342, 3);
            this.txtLegDesc.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.txtLegDesc.Name = "txtLegDesc";
            this.txtLegDesc.Size = new System.Drawing.Size(149, 20);
            this.txtLegDesc.TabIndex = 3;
            // 
            // btnAddLeg
            // 
            this.btnAddLeg.Location = new System.Drawing.Point(495, 3);
            this.btnAddLeg.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.btnAddLeg.Name = "btnAddLeg";
            this.btnAddLeg.Size = new System.Drawing.Size(94, 29);
            this.btnAddLeg.TabIndex = 4;
            this.btnAddLeg.Text = "Add";
            this.btnAddLeg.Click += new System.EventHandler(this.btnAddLeg_Click_1);
            // 
            // btnRemoveLeg
            // 
            this.btnRemoveLeg.Location = new System.Drawing.Point(2, 38);
            this.btnRemoveLeg.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.btnRemoveLeg.Name = "btnRemoveLeg";
            this.btnRemoveLeg.Size = new System.Drawing.Size(94, 29);
            this.btnRemoveLeg.TabIndex = 5;
            this.btnRemoveLeg.Text = "Remove";
            // 
            // gridLegs
            // 
            this.gridLegs.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridLegs.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.gridLegs.Location = new System.Drawing.Point(2, 92);
            this.gridLegs.MainView = this.viewLegs;
            this.gridLegs.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.gridLegs.Name = "gridLegs";
            this.gridLegs.Size = new System.Drawing.Size(596, 407);
            this.gridLegs.TabIndex = 2;
            this.gridLegs.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.viewLegs});
            // 
            // viewLegs
            // 
            this.viewLegs.GridControl = this.gridLegs;
            this.viewLegs.Name = "viewLegs";
            this.viewLegs.OptionsEditForm.PopupEditFormWidth = 686;
            // 
            // tableLayoutPanelRight
            // 
            this.tableLayoutPanelRight.ColumnCount = 1;
            this.tableLayoutPanelRight.ColumnStyles.Add(new System.Windows.Forms.ColumnStyle(System.Windows.Forms.SizeType.Percent, 100F));
            this.tableLayoutPanelRight.Controls.Add(this.lblPend, 0, 0);
            this.tableLayoutPanelRight.Controls.Add(this.gridPending, 0, 1);
            this.tableLayoutPanelRight.Dock = System.Windows.Forms.DockStyle.Fill;
            this.tableLayoutPanelRight.Location = new System.Drawing.Point(0, 0);
            this.tableLayoutPanelRight.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.tableLayoutPanelRight.Name = "tableLayoutPanelRight";
            this.tableLayoutPanelRight.RowCount = 2;
            this.tableLayoutPanelRight.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Absolute, 20F));
            this.tableLayoutPanelRight.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Percent, 100F));
            this.tableLayoutPanelRight.Size = new System.Drawing.Size(665, 502);
            this.tableLayoutPanelRight.TabIndex = 0;
            // 
            // lblPend
            // 
            this.lblPend.Dock = System.Windows.Forms.DockStyle.Fill;
            this.lblPend.Location = new System.Drawing.Point(2, 3);
            this.lblPend.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.lblPend.Name = "lblPend";
            this.lblPend.Size = new System.Drawing.Size(661, 14);
            this.lblPend.TabIndex = 0;
            this.lblPend.Text = "PENDING APPROVAL";
            // 
            // gridPending
            // 
            this.gridPending.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridPending.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.gridPending.Location = new System.Drawing.Point(2, 23);
            this.gridPending.MainView = this.viewPending;
            this.gridPending.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.gridPending.Name = "gridPending";
            this.gridPending.Size = new System.Drawing.Size(661, 476);
            this.gridPending.TabIndex = 1;
            this.gridPending.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.viewPending});
            // 
            // viewPending
            // 
            this.viewPending.GridControl = this.gridPending;
            this.viewPending.Name = "viewPending";
            this.viewPending.OptionsEditForm.PopupEditFormWidth = 686;
            // 
            // panelToolbar
            // 
            this.panelToolbar.Controls.Add(this.lblStatus);
            this.panelToolbar.Controls.Add(this.flowLayoutPanelToolbar);
            this.panelToolbar.Dock = System.Windows.Forms.DockStyle.Fill;
            this.panelToolbar.Location = new System.Drawing.Point(2, 759);
            this.panelToolbar.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.panelToolbar.Name = "panelToolbar";
            this.panelToolbar.Size = new System.Drawing.Size(1275, 38);
            this.panelToolbar.TabIndex = 3;
            // 
            // lblStatus
            // 
            this.lblStatus.Dock = System.Windows.Forms.DockStyle.Right;
            this.lblStatus.Location = new System.Drawing.Point(1244, 0);
            this.lblStatus.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.lblStatus.Name = "lblStatus";
            this.lblStatus.Size = new System.Drawing.Size(31, 13);
            this.lblStatus.TabIndex = 0;
            this.lblStatus.Text = "Status";
            // 
            // flowLayoutPanelToolbar
            // 
            this.flowLayoutPanelToolbar.AutoSize = true;
            this.flowLayoutPanelToolbar.Controls.Add(this.btnPost);
            this.flowLayoutPanelToolbar.Controls.Add(this.btnApprove);
            this.flowLayoutPanelToolbar.Controls.Add(this.btnReject);
            this.flowLayoutPanelToolbar.Controls.Add(this.btnRefresh);
            this.flowLayoutPanelToolbar.Dock = System.Windows.Forms.DockStyle.Left;
            this.flowLayoutPanelToolbar.Location = new System.Drawing.Point(0, 0);
            this.flowLayoutPanelToolbar.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.flowLayoutPanelToolbar.Name = "flowLayoutPanelToolbar";
            this.flowLayoutPanelToolbar.Size = new System.Drawing.Size(98, 38);
            this.flowLayoutPanelToolbar.TabIndex = 1;
            // 
            // btnPost
            // 
            this.btnPost.Location = new System.Drawing.Point(2, 3);
            this.btnPost.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.btnPost.Name = "btnPost";
            this.btnPost.Size = new System.Drawing.Size(94, 29);
            this.btnPost.TabIndex = 0;
            this.btnPost.Text = "Post Ticket";
            // 
            // btnApprove
            // 
            this.btnApprove.Location = new System.Drawing.Point(2, 38);
            this.btnApprove.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.btnApprove.Name = "btnApprove";
            this.btnApprove.Size = new System.Drawing.Size(94, 29);
            this.btnApprove.TabIndex = 1;
            this.btnApprove.Text = "Approve";
            // 
            // btnReject
            // 
            this.btnReject.Location = new System.Drawing.Point(2, 73);
            this.btnReject.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.btnReject.Name = "btnReject";
            this.btnReject.Size = new System.Drawing.Size(94, 29);
            this.btnReject.TabIndex = 2;
            this.btnReject.Text = "Reject";
            // 
            // btnRefresh
            // 
            this.btnRefresh.Location = new System.Drawing.Point(2, 108);
            this.btnRefresh.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.btnRefresh.Name = "btnRefresh";
            this.btnRefresh.Size = new System.Drawing.Size(94, 29);
            this.btnRefresh.TabIndex = 3;
            this.btnRefresh.Text = "Refresh";
            // 
            // ManualTicketFormV1
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1279, 800);
            this.Controls.Add(this.tableLayoutPanelMain);
            this.Margin = new System.Windows.Forms.Padding(2, 3, 2, 3);
            this.Name = "ManualTicketFormV1";
            this.Text = "Manual Ticketing v1";
            this.tableLayoutPanelMain.ResumeLayout(false);
            this.panelBanner.ResumeLayout(false);
            this.panelBanner.PerformLayout();
            this.panelHeader.ResumeLayout(false);
            this.flowLayoutPanelHeader.ResumeLayout(false);
            this.flowLayoutPanelHeader.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.radSourceType.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbAdjType.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbSupplier.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbSupplierView)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbInvoice.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbInvoiceView)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtAdjAmount.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbAPImpact.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtOrigTicket.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDocRef.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtRemarks.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.splitContainerControl1.Panel1)).EndInit();
            this.splitContainerControl1.Panel1.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.splitContainerControl1.Panel2)).EndInit();
            this.splitContainerControl1.Panel2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.splitContainerControl1)).EndInit();
            this.splitContainerControl1.ResumeLayout(false);
            this.tableLayoutPanelLeft.ResumeLayout(false);
            this.tableLayoutPanelLeft.PerformLayout();
            this.flowLayoutPanelLegBar.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.cmbLegAccount.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbLegAccountView)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbLegDC.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtLegAmount.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtLegDesc.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridLegs)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.viewLegs)).EndInit();
            this.tableLayoutPanelRight.ResumeLayout(false);
            this.tableLayoutPanelRight.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridPending)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.viewPending)).EndInit();
            this.panelToolbar.ResumeLayout(false);
            this.panelToolbar.PerformLayout();
            this.flowLayoutPanelToolbar.ResumeLayout(false);
            this.ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.TableLayoutPanel tableLayoutPanelMain;
        private System.Windows.Forms.Panel panelBanner;
        private DevExpress.XtraEditors.LabelControl lblBannerTitle;
        private DevExpress.XtraEditors.LabelControl lblBannerSub;
        private System.Windows.Forms.Panel panelHeader;
        private System.Windows.Forms.FlowLayoutPanel flowLayoutPanelHeader;

        // Header Controls
        private DevExpress.XtraEditors.RadioGroup radSourceType;
        private DevExpress.XtraEditors.ComboBoxEdit cmbAdjType;
        private DevExpress.XtraEditors.SearchLookUpEdit cmbSupplier;
        private DevExpress.XtraGrid.Views.Grid.GridView viewSupplier;
        private DevExpress.XtraEditors.SearchLookUpEdit cmbInvoice;
        private DevExpress.XtraGrid.Views.Grid.GridView viewInvoice;
        private DevExpress.XtraEditors.LabelControl lblInvoiceBalance;
        private DevExpress.XtraEditors.TextEdit txtAdjAmount;
        private DevExpress.XtraEditors.ComboBoxEdit cmbAPImpact;
        private DevExpress.XtraEditors.TextEdit txtOrigTicket;
        private DevExpress.XtraEditors.TextEdit txtDocRef;
        private DevExpress.XtraEditors.TextEdit txtRemarks;

        // Body
        private DevExpress.XtraEditors.SplitContainerControl splitContainerControl1;
        private System.Windows.Forms.TableLayoutPanel tableLayoutPanelLeft;
        private DevExpress.XtraEditors.LabelControl lblLegs;
        private System.Windows.Forms.FlowLayoutPanel flowLayoutPanelLegBar;

        // Leg controls
        private DevExpress.XtraEditors.SearchLookUpEdit cmbLegAccount;
        private DevExpress.XtraGrid.Views.Grid.GridView viewLegAccount;
        private DevExpress.XtraEditors.ComboBoxEdit cmbLegDC;
        private DevExpress.XtraEditors.TextEdit txtLegAmount;
        private DevExpress.XtraEditors.TextEdit txtLegDesc;
        private DevExpress.XtraEditors.SimpleButton btnAddLeg;
        private DevExpress.XtraEditors.SimpleButton btnRemoveLeg;
        private DevExpress.XtraGrid.GridControl gridLegs;
        private DevExpress.XtraGrid.Views.Grid.GridView viewLegs;

        private System.Windows.Forms.TableLayoutPanel tableLayoutPanelRight;
        private DevExpress.XtraEditors.LabelControl lblPend;
        private DevExpress.XtraGrid.GridControl gridPending;
        private DevExpress.XtraGrid.Views.Grid.GridView viewPending;

        // Toolbar
        private System.Windows.Forms.Panel panelToolbar;
        private System.Windows.Forms.FlowLayoutPanel flowLayoutPanelToolbar;
        private DevExpress.XtraEditors.LabelControl lblStatus;
        private DevExpress.XtraEditors.SimpleButton btnPost;
        private DevExpress.XtraEditors.SimpleButton btnApprove;
        private DevExpress.XtraEditors.SimpleButton btnReject;
        private DevExpress.XtraEditors.SimpleButton btnRefresh;
        private DevExpress.XtraGrid.Views.Grid.GridView cmbSupplierView;
        private DevExpress.XtraGrid.Views.Grid.GridView cmbInvoiceView;
        private DevExpress.XtraGrid.Views.Grid.GridView cmbLegAccountView;
    }
}