namespace SalesInventorySystem.AccountingDevEx
{
    partial class VoucheringManualFrm
    {
        
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null)) components.Dispose();
            base.Dispose(disposing);
        }
        private DevExpress.XtraTab.XtraTabControl tabMain;
        private DevExpress.XtraTab.XtraTabPage tabNewVoucher;
        private DevExpress.XtraTab.XtraTabPage tabPosted;

        private DevExpress.XtraEditors.PanelControl pnlPostedFilter;
        private DevExpress.XtraEditors.LabelControl lblPostedDateFrom;
        private DevExpress.XtraEditors.DateEdit txtPostedDateFrom;
        private DevExpress.XtraEditors.LabelControl lblPostedDateTo;
        private DevExpress.XtraEditors.DateEdit txtPostedDateTo;
        private DevExpress.XtraEditors.SimpleButton btnRefreshPosted;

        private DevExpress.XtraGrid.GridControl gridControlPosted;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewPosted;

        private DevExpress.XtraEditors.PanelControl pnlPostedButtons;
        private DevExpress.XtraEditors.SimpleButton btnViewPostedDetails;
        private DevExpress.XtraEditors.SimpleButton btnCopyPostedToNew;

        private DevExpress.XtraGrid.GridControl gridControlPostedDetails;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewPostedDetails;
        private DevExpress.XtraEditors.GroupControl grpHeader;
        private DevExpress.XtraEditors.LabelControl lblReferenceNo;
        private DevExpress.XtraEditors.TextEdit txtReferenceNo;
        private DevExpress.XtraEditors.LabelControl lblVoucherDate;
        private DevExpress.XtraEditors.DateEdit txtVoucherDate;
        private DevExpress.XtraEditors.LabelControl lblBranch;
        private DevExpress.XtraEditors.LookUpEdit cboBranch;
        private DevExpress.XtraEditors.LabelControl lblSupplier;
        private DevExpress.XtraEditors.SearchLookUpEdit cboSupplier;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewSupplierPopup;
        private System.Windows.Forms.RadioButton radioButtonPurchase;
        private System.Windows.Forms.RadioButton radioButtonExpense;
        private System.Windows.Forms.RadioButton radCheckVoucher;
        private System.Windows.Forms.RadioButton radCashVoucher;
        private System.Windows.Forms.RadioButton radTelegraphic;
        private DevExpress.XtraEditors.LabelControl lblCheckNo;
        private DevExpress.XtraEditors.TextEdit txtCheckNo;
        private DevExpress.XtraEditors.LabelControl lblControlNo;
        private DevExpress.XtraEditors.TextEdit txtControlNo;
        private DevExpress.XtraEditors.LabelControl lblRemarks;
        private DevExpress.XtraEditors.MemoEdit txtRemarks;
        private DevExpress.XtraEditors.SimpleButton btnLoadInvoices;
        private DevExpress.XtraEditors.LabelControl lblCreditGLCode;
        private DevExpress.XtraEditors.SearchLookUpEdit cboCreditGLCode;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewCreditGLPopup;

        private DevExpress.XtraEditors.GroupControl grpInvoices;
        private DevExpress.XtraGrid.GridControl gridControlInvoices;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewInvoices;
        private DevExpress.XtraEditors.Repository.RepositoryItemCheckEdit repPay;
        private DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit repInvAmount;

        private DevExpress.XtraEditors.GroupControl grpGLEntry;
        private DevExpress.XtraGrid.GridControl gridControlGL;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewGL;
        private DevExpress.XtraGrid.Columns.GridColumn colGLAccountCode;
        private DevExpress.XtraGrid.Columns.GridColumn colGLDebit;
        private DevExpress.XtraGrid.Columns.GridColumn colGLCredit;
        private DevExpress.XtraGrid.Columns.GridColumn colGLParticulars;
        private DevExpress.XtraEditors.Repository.RepositoryItemSearchLookUpEdit repGLAccountCode;
        private DevExpress.XtraGrid.Views.Grid.GridView repGLAccountCodeView;
        private DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit repGLDebit;
        private DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit repGLCredit;
        private DevExpress.XtraEditors.Repository.RepositoryItemTextEdit repGLParticulars;
        private DevExpress.XtraEditors.SimpleButton btnAddGLLine;
        private DevExpress.XtraEditors.SimpleButton btnRemoveGLLine;

        private DevExpress.XtraEditors.LabelControl lblTieStatus;
        private DevExpress.XtraEditors.LabelControl lblBalanceStatus;
        private DevExpress.XtraEditors.SimpleButton btnPost;
        private DevExpress.XtraEditors.SimpleButton btnClose;

        private void InitializeComponent()
        {
            this.grpHeader = new DevExpress.XtraEditors.GroupControl();
            this.lblReferenceNo = new DevExpress.XtraEditors.LabelControl();
            this.txtReferenceNo = new DevExpress.XtraEditors.TextEdit();
            this.lblVoucherDate = new DevExpress.XtraEditors.LabelControl();
            this.txtVoucherDate = new DevExpress.XtraEditors.DateEdit();
            this.lblBranch = new DevExpress.XtraEditors.LabelControl();
            this.cboBranch = new DevExpress.XtraEditors.LookUpEdit();
            this.lblSupplier = new DevExpress.XtraEditors.LabelControl();
            this.cboSupplier = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.gridViewSupplierPopup = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.radioButtonPurchase = new System.Windows.Forms.RadioButton();
            this.radioButtonExpense = new System.Windows.Forms.RadioButton();
            this.radCheckVoucher = new System.Windows.Forms.RadioButton();
            this.radCashVoucher = new System.Windows.Forms.RadioButton();
            this.radTelegraphic = new System.Windows.Forms.RadioButton();
            this.lblCheckNo = new DevExpress.XtraEditors.LabelControl();
            this.txtCheckNo = new DevExpress.XtraEditors.TextEdit();
            this.lblControlNo = new DevExpress.XtraEditors.LabelControl();
            this.txtControlNo = new DevExpress.XtraEditors.TextEdit();
            this.lblRemarks = new DevExpress.XtraEditors.LabelControl();
            this.txtRemarks = new DevExpress.XtraEditors.MemoEdit();
            this.btnLoadInvoices = new DevExpress.XtraEditors.SimpleButton();
            this.lblCreditGLCode = new DevExpress.XtraEditors.LabelControl();
            this.cboCreditGLCode = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.gridViewCreditGLPopup = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.grpInvoices = new DevExpress.XtraEditors.GroupControl();
            this.gridControlInvoices = new DevExpress.XtraGrid.GridControl();
            this.gridViewInvoices = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.repPay = new DevExpress.XtraEditors.Repository.RepositoryItemCheckEdit();
            this.repInvAmount = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.grpGLEntry = new DevExpress.XtraEditors.GroupControl();
            this.gridControlGL = new DevExpress.XtraGrid.GridControl();
            this.gridViewGL = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.colGLAccountCode = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colGLParticulars = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colGLDebit = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colGLCredit = new DevExpress.XtraGrid.Columns.GridColumn();
            this.repGLAccountCode = new DevExpress.XtraEditors.Repository.RepositoryItemSearchLookUpEdit();
            this.repGLAccountCodeView = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.repGLDebit = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.repGLCredit = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.repGLParticulars = new DevExpress.XtraEditors.Repository.RepositoryItemTextEdit();
            this.btnAddGLLine = new DevExpress.XtraEditors.SimpleButton();
            this.btnRemoveGLLine = new DevExpress.XtraEditors.SimpleButton();
            this.lblTieStatus = new DevExpress.XtraEditors.LabelControl();
            this.lblBalanceStatus = new DevExpress.XtraEditors.LabelControl();
            this.btnPost = new DevExpress.XtraEditors.SimpleButton();
            this.btnClose = new DevExpress.XtraEditors.SimpleButton();
            this.panelControl1 = new DevExpress.XtraEditors.PanelControl();
            this.tabMain = new DevExpress.XtraTab.XtraTabControl();
            this.tabNewVoucher = new DevExpress.XtraTab.XtraTabPage();
            this.tabPosted = new DevExpress.XtraTab.XtraTabPage();
            this.pnlPostedFilter = new DevExpress.XtraEditors.PanelControl();
            this.lblPostedDateFrom = new DevExpress.XtraEditors.LabelControl();
            this.txtPostedDateFrom = new DevExpress.XtraEditors.DateEdit();
            this.lblPostedDateTo = new DevExpress.XtraEditors.LabelControl();
            this.txtPostedDateTo = new DevExpress.XtraEditors.DateEdit();
            this.btnRefreshPosted = new DevExpress.XtraEditors.SimpleButton();
            this.gridControlPosted = new DevExpress.XtraGrid.GridControl();
            this.gridView1 = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.gridViewPosted = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.pnlPostedButtons = new DevExpress.XtraEditors.PanelControl();
            this.btnViewPostedDetails = new DevExpress.XtraEditors.SimpleButton();
            this.btnCopyPostedToNew = new DevExpress.XtraEditors.SimpleButton();
            this.gridControlPostedDetails = new DevExpress.XtraGrid.GridControl();
            this.gridView2 = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.gridViewPostedDetails = new DevExpress.XtraGrid.Views.Grid.GridView();
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).BeginInit();
            this.grpHeader.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtVoucherDate.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtVoucherDate.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranch.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboSupplier.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewSupplierPopup)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtCheckNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtControlNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtRemarks.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboCreditGLCode.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewCreditGLPopup)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpInvoices)).BeginInit();
            this.grpInvoices.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlInvoices)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewInvoices)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repPay)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repInvAmount)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpGLEntry)).BeginInit();
            this.grpGLEntry.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlGL)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewGL)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repGLAccountCode)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repGLAccountCodeView)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repGLDebit)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repGLCredit)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repGLParticulars)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl1)).BeginInit();
            this.panelControl1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.tabMain)).BeginInit();
            this.tabMain.SuspendLayout();
            this.tabNewVoucher.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pnlPostedFilter)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtPostedDateFrom.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtPostedDateFrom.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtPostedDateTo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtPostedDateTo.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlPosted)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView1)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewPosted)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlPostedButtons)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlPostedDetails)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView2)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewPostedDetails)).BeginInit();
            this.SuspendLayout();
            // 
            // grpHeader
            // 
            this.grpHeader.Controls.Add(this.lblReferenceNo);
            this.grpHeader.Controls.Add(this.txtReferenceNo);
            this.grpHeader.Controls.Add(this.lblVoucherDate);
            this.grpHeader.Controls.Add(this.txtVoucherDate);
            this.grpHeader.Controls.Add(this.lblBranch);
            this.grpHeader.Controls.Add(this.cboBranch);
            this.grpHeader.Controls.Add(this.lblSupplier);
            this.grpHeader.Controls.Add(this.cboSupplier);
            this.grpHeader.Controls.Add(this.radioButtonPurchase);
            this.grpHeader.Controls.Add(this.radioButtonExpense);
            this.grpHeader.Controls.Add(this.radCheckVoucher);
            this.grpHeader.Controls.Add(this.radCashVoucher);
            this.grpHeader.Controls.Add(this.radTelegraphic);
            this.grpHeader.Controls.Add(this.lblCheckNo);
            this.grpHeader.Controls.Add(this.txtCheckNo);
            this.grpHeader.Controls.Add(this.lblControlNo);
            this.grpHeader.Controls.Add(this.txtControlNo);
            this.grpHeader.Controls.Add(this.lblRemarks);
            this.grpHeader.Controls.Add(this.txtRemarks);
            this.grpHeader.Controls.Add(this.btnLoadInvoices);
            this.grpHeader.Controls.Add(this.lblCreditGLCode);
            this.grpHeader.Controls.Add(this.cboCreditGLCode);
            this.grpHeader.Dock = System.Windows.Forms.DockStyle.Top;
            this.grpHeader.Location = new System.Drawing.Point(0, 0);
            this.grpHeader.Name = "grpHeader";
            this.grpHeader.Size = new System.Drawing.Size(996, 299);
            this.grpHeader.TabIndex = 2;
            this.grpHeader.Text = "Voucher Header (Manual, No Mapping)";
            // 
            // lblReferenceNo
            // 
            this.lblReferenceNo.Location = new System.Drawing.Point(15, 55);
            this.lblReferenceNo.Name = "lblReferenceNo";
            this.lblReferenceNo.Size = new System.Drawing.Size(86, 16);
            this.lblReferenceNo.TabIndex = 0;
            this.lblReferenceNo.Text = "Reference No.:";
            // 
            // txtReferenceNo
            // 
            this.txtReferenceNo.Location = new System.Drawing.Point(149, 52);
            this.txtReferenceNo.Name = "txtReferenceNo";
            this.txtReferenceNo.Properties.ReadOnly = true;
            this.txtReferenceNo.Size = new System.Drawing.Size(150, 22);
            this.txtReferenceNo.TabIndex = 1;
            // 
            // lblVoucherDate
            // 
            this.lblVoucherDate.Location = new System.Drawing.Point(359, 55);
            this.lblVoucherDate.Name = "lblVoucherDate";
            this.lblVoucherDate.Size = new System.Drawing.Size(82, 16);
            this.lblVoucherDate.TabIndex = 2;
            this.lblVoucherDate.Text = "Voucher Date:";
            // 
            // txtVoucherDate
            // 
            this.txtVoucherDate.EditValue = new System.DateTime(2026, 7, 23, 0, 0, 0, 0);
            this.txtVoucherDate.Location = new System.Drawing.Point(493, 52);
            this.txtVoucherDate.Name = "txtVoucherDate";
            this.txtVoucherDate.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtVoucherDate.Size = new System.Drawing.Size(150, 22);
            this.txtVoucherDate.TabIndex = 3;
            // 
            // lblBranch
            // 
            this.lblBranch.Location = new System.Drawing.Point(669, 55);
            this.lblBranch.Name = "lblBranch";
            this.lblBranch.Size = new System.Drawing.Size(44, 16);
            this.lblBranch.TabIndex = 4;
            this.lblBranch.Text = "Branch:";
            // 
            // cboBranch
            // 
            this.cboBranch.Location = new System.Drawing.Point(765, 52);
            this.cboBranch.Name = "cboBranch";
            this.cboBranch.Size = new System.Drawing.Size(198, 22);
            this.cboBranch.TabIndex = 5;
            // 
            // lblSupplier
            // 
            this.lblSupplier.Location = new System.Drawing.Point(15, 98);
            this.lblSupplier.Name = "lblSupplier";
            this.lblSupplier.Size = new System.Drawing.Size(106, 16);
            this.lblSupplier.TabIndex = 6;
            this.lblSupplier.Text = "Vendor / Supplier:";
            // 
            // cboSupplier
            // 
            this.cboSupplier.Location = new System.Drawing.Point(149, 95);
            this.cboSupplier.Name = "cboSupplier";
            this.cboSupplier.Properties.PopupView = this.gridViewSupplierPopup;
            this.cboSupplier.Size = new System.Drawing.Size(494, 22);
            this.cboSupplier.TabIndex = 7;
            // 
            // gridViewSupplierPopup
            // 
            this.gridViewSupplierPopup.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.gridViewSupplierPopup.Name = "gridViewSupplierPopup";
            this.gridViewSupplierPopup.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.gridViewSupplierPopup.OptionsView.ShowGroupPanel = false;
            // 
            // radioButtonPurchase
            // 
            this.radioButtonPurchase.Location = new System.Drawing.Point(172, 261);
            this.radioButtonPurchase.Name = "radioButtonPurchase";
            this.radioButtonPurchase.Size = new System.Drawing.Size(90, 22);
            this.radioButtonPurchase.TabIndex = 8;
            this.radioButtonPurchase.Text = "Purchase";
            // 
            // radioButtonExpense
            // 
            this.radioButtonExpense.Location = new System.Drawing.Point(272, 261);
            this.radioButtonExpense.Name = "radioButtonExpense";
            this.radioButtonExpense.Size = new System.Drawing.Size(90, 22);
            this.radioButtonExpense.TabIndex = 9;
            this.radioButtonExpense.Text = "Expense";
            // 
            // radCheckVoucher
            // 
            this.radCheckVoucher.Location = new System.Drawing.Point(148, 136);
            this.radCheckVoucher.Name = "radCheckVoucher";
            this.radCheckVoucher.Size = new System.Drawing.Size(80, 22);
            this.radCheckVoucher.TabIndex = 10;
            this.radCheckVoucher.Text = "Check";
            this.radCheckVoucher.Visible = false;
            this.radCheckVoucher.CheckedChanged += new System.EventHandler(this.RadVoucherType_CheckedChanged);
            // 
            // radCashVoucher
            // 
            this.radCashVoucher.Location = new System.Drawing.Point(238, 136);
            this.radCashVoucher.Name = "radCashVoucher";
            this.radCashVoucher.Size = new System.Drawing.Size(80, 22);
            this.radCashVoucher.TabIndex = 11;
            this.radCashVoucher.Text = "Cash";
            this.radCashVoucher.Visible = false;
            this.radCashVoucher.CheckedChanged += new System.EventHandler(this.RadVoucherType_CheckedChanged);
            // 
            // radTelegraphic
            // 
            this.radTelegraphic.Checked = true;
            this.radTelegraphic.Location = new System.Drawing.Point(328, 136);
            this.radTelegraphic.Name = "radTelegraphic";
            this.radTelegraphic.Size = new System.Drawing.Size(100, 22);
            this.radTelegraphic.TabIndex = 12;
            this.radTelegraphic.TabStop = true;
            this.radTelegraphic.Text = "Telegraphic";
            this.radTelegraphic.CheckedChanged += new System.EventHandler(this.RadVoucherType_CheckedChanged);
            // 
            // lblCheckNo
            // 
            this.lblCheckNo.Location = new System.Drawing.Point(14, 179);
            this.lblCheckNo.Name = "lblCheckNo";
            this.lblCheckNo.Size = new System.Drawing.Size(62, 16);
            this.lblCheckNo.TabIndex = 13;
            this.lblCheckNo.Text = "Check No.:";
            // 
            // txtCheckNo
            // 
            this.txtCheckNo.Location = new System.Drawing.Point(148, 176);
            this.txtCheckNo.Name = "txtCheckNo";
            this.txtCheckNo.Size = new System.Drawing.Size(150, 22);
            this.txtCheckNo.TabIndex = 14;
            // 
            // lblControlNo
            // 
            this.lblControlNo.Location = new System.Drawing.Point(14, 178);
            this.lblControlNo.Name = "lblControlNo";
            this.lblControlNo.Size = new System.Drawing.Size(69, 16);
            this.lblControlNo.TabIndex = 15;
            this.lblControlNo.Text = "Control No.:";
            this.lblControlNo.Visible = false;
            // 
            // txtControlNo
            // 
            this.txtControlNo.Location = new System.Drawing.Point(148, 175);
            this.txtControlNo.Name = "txtControlNo";
            this.txtControlNo.Size = new System.Drawing.Size(150, 22);
            this.txtControlNo.TabIndex = 16;
            this.txtControlNo.Visible = false;
            // 
            // lblRemarks
            // 
            this.lblRemarks.Location = new System.Drawing.Point(358, 192);
            this.lblRemarks.Name = "lblRemarks";
            this.lblRemarks.Size = new System.Drawing.Size(55, 16);
            this.lblRemarks.TabIndex = 17;
            this.lblRemarks.Text = "Remarks:";
            // 
            // txtRemarks
            // 
            this.txtRemarks.Location = new System.Drawing.Point(432, 176);
            this.txtRemarks.Name = "txtRemarks";
            this.txtRemarks.Size = new System.Drawing.Size(530, 44);
            this.txtRemarks.TabIndex = 18;
            // 
            // btnLoadInvoices
            // 
            this.btnLoadInvoices.Location = new System.Drawing.Point(14, 255);
            this.btnLoadInvoices.Name = "btnLoadInvoices";
            this.btnLoadInvoices.Size = new System.Drawing.Size(150, 30);
            this.btnLoadInvoices.TabIndex = 19;
            this.btnLoadInvoices.Text = "Load Invoices";
            this.btnLoadInvoices.Click += new System.EventHandler(this.BtnLoadInvoices_Click);
            // 
            // lblCreditGLCode
            // 
            this.lblCreditGLCode.Location = new System.Drawing.Point(669, 98);
            this.lblCreditGLCode.Name = "lblCreditGLCode";
            this.lblCreditGLCode.Size = new System.Drawing.Size(86, 16);
            this.lblCreditGLCode.TabIndex = 20;
            this.lblCreditGLCode.Text = "Credit GLCode:";
            // 
            // cboCreditGLCode
            // 
            this.cboCreditGLCode.Location = new System.Drawing.Point(765, 95);
            this.cboCreditGLCode.Name = "cboCreditGLCode";
            this.cboCreditGLCode.Properties.PopupView = this.gridViewCreditGLPopup;
            this.cboCreditGLCode.Size = new System.Drawing.Size(198, 22);
            this.cboCreditGLCode.TabIndex = 21;
            // 
            // gridViewCreditGLPopup
            // 
            this.gridViewCreditGLPopup.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.gridViewCreditGLPopup.Name = "gridViewCreditGLPopup";
            this.gridViewCreditGLPopup.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.gridViewCreditGLPopup.OptionsView.ShowGroupPanel = false;
            // 
            // grpInvoices
            // 
            this.grpInvoices.Controls.Add(this.gridControlInvoices);
            this.grpInvoices.Dock = System.Windows.Forms.DockStyle.Top;
            this.grpInvoices.Location = new System.Drawing.Point(0, 299);
            this.grpInvoices.Name = "grpInvoices";
            this.grpInvoices.Size = new System.Drawing.Size(996, 260);
            this.grpInvoices.TabIndex = 1;
            this.grpInvoices.Text = "Outstanding Invoices";
            // 
            // gridControlInvoices
            // 
            this.gridControlInvoices.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlInvoices.Location = new System.Drawing.Point(2, 28);
            this.gridControlInvoices.MainView = this.gridViewInvoices;
            this.gridControlInvoices.Name = "gridControlInvoices";
            this.gridControlInvoices.RepositoryItems.AddRange(new DevExpress.XtraEditors.Repository.RepositoryItem[] {
            this.repPay,
            this.repInvAmount});
            this.gridControlInvoices.Size = new System.Drawing.Size(992, 230);
            this.gridControlInvoices.TabIndex = 0;
            this.gridControlInvoices.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewInvoices});
            // 
            // gridViewInvoices
            // 
            this.gridViewInvoices.GridControl = this.gridControlInvoices;
            this.gridViewInvoices.Name = "gridViewInvoices";
            this.gridViewInvoices.OptionsView.ShowFooter = true;
            this.gridViewInvoices.OptionsView.ShowGroupPanel = false;
            this.gridViewInvoices.RowCellStyle += new DevExpress.XtraGrid.Views.Grid.RowCellStyleEventHandler(this.GridViewInvoices_RowCellStyle);
            this.gridViewInvoices.CustomRowCellEdit += new DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventHandler(this.GridViewInvoices_CustomRowCellEdit);
            this.gridViewInvoices.CellValueChanged += new DevExpress.XtraGrid.Views.Base.CellValueChangedEventHandler(this.GridViewInvoices_CellValueChanged);
            // 
            // repPay
            // 
            this.repPay.AutoHeight = false;
            this.repPay.Name = "repPay";
            this.repPay.ValueChecked = "True";
            this.repPay.ValueUnchecked = "False";
            // 
            // repInvAmount
            // 
            this.repInvAmount.AutoHeight = false;
            this.repInvAmount.DisplayFormat.FormatString = "n2";
            this.repInvAmount.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.repInvAmount.Mask.EditMask = "n2";
            this.repInvAmount.Name = "repInvAmount";
            // 
            // grpGLEntry
            // 
            this.grpGLEntry.Controls.Add(this.gridControlGL);
            this.grpGLEntry.Dock = System.Windows.Forms.DockStyle.Fill;
            this.grpGLEntry.Location = new System.Drawing.Point(0, 559);
            this.grpGLEntry.Name = "grpGLEntry";
            this.grpGLEntry.Size = new System.Drawing.Size(996, 262);
            this.grpGLEntry.TabIndex = 0;
            this.grpGLEntry.Text = "Compound GL Entry (manual — no mapping, covers ALL checked invoices together)";
            // 
            // gridControlGL
            // 
            this.gridControlGL.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlGL.Location = new System.Drawing.Point(2, 28);
            this.gridControlGL.MainView = this.gridViewGL;
            this.gridControlGL.Name = "gridControlGL";
            this.gridControlGL.RepositoryItems.AddRange(new DevExpress.XtraEditors.Repository.RepositoryItem[] {
            this.repGLAccountCode,
            this.repGLDebit,
            this.repGLCredit,
            this.repGLParticulars});
            this.gridControlGL.Size = new System.Drawing.Size(992, 232);
            this.gridControlGL.TabIndex = 0;
            this.gridControlGL.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewGL});
            // 
            // gridViewGL
            // 
            this.gridViewGL.Columns.AddRange(new DevExpress.XtraGrid.Columns.GridColumn[] {
            this.colGLAccountCode,
            this.colGLParticulars,
            this.colGLDebit,
            this.colGLCredit});
            this.gridViewGL.GridControl = this.gridControlGL;
            this.gridViewGL.Name = "gridViewGL";
            this.gridViewGL.OptionsCustomization.AllowSort = false;
            this.gridViewGL.OptionsView.ShowFooter = true;
            this.gridViewGL.OptionsView.ShowGroupPanel = false;
            this.gridViewGL.RowCellStyle += new DevExpress.XtraGrid.Views.Grid.RowCellStyleEventHandler(this.GridViewGL_RowCellStyle);
            this.gridViewGL.CustomRowCellEdit += new DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventHandler(this.GridViewGL_CustomRowCellEdit);
            this.gridViewGL.CellValueChanged += new DevExpress.XtraGrid.Views.Base.CellValueChangedEventHandler(this.GridViewGL_CellValueChanged);
            // 
            // colGLAccountCode
            // 
            this.colGLAccountCode.Caption = "Account Code";
            this.colGLAccountCode.FieldName = "AccountCode";
            this.colGLAccountCode.Name = "colGLAccountCode";
            this.colGLAccountCode.Visible = true;
            this.colGLAccountCode.VisibleIndex = 0;
            this.colGLAccountCode.Width = 320;
            // 
            // colGLParticulars
            // 
            this.colGLParticulars.Caption = "Particulars";
            this.colGLParticulars.FieldName = "Particulars";
            this.colGLParticulars.Name = "colGLParticulars";
            this.colGLParticulars.Visible = true;
            this.colGLParticulars.VisibleIndex = 1;
            this.colGLParticulars.Width = 260;
            // 
            // colGLDebit
            // 
            this.colGLDebit.Caption = "Debit";
            this.colGLDebit.FieldName = "Debit";
            this.colGLDebit.Name = "colGLDebit";
            this.colGLDebit.Summary.AddRange(new DevExpress.XtraGrid.GridSummaryItem[] {
            new DevExpress.XtraGrid.GridColumnSummaryItem(DevExpress.Data.SummaryItemType.Sum, "Debit", "{0:n2}")});
            this.colGLDebit.Visible = true;
            this.colGLDebit.VisibleIndex = 2;
            this.colGLDebit.Width = 150;
            // 
            // colGLCredit
            // 
            this.colGLCredit.Caption = "Credit";
            this.colGLCredit.FieldName = "Credit";
            this.colGLCredit.Name = "colGLCredit";
            this.colGLCredit.Summary.AddRange(new DevExpress.XtraGrid.GridSummaryItem[] {
            new DevExpress.XtraGrid.GridColumnSummaryItem(DevExpress.Data.SummaryItemType.Sum, "Credit", "{0:n2}")});
            this.colGLCredit.Visible = true;
            this.colGLCredit.VisibleIndex = 3;
            this.colGLCredit.Width = 150;
            // 
            // repGLAccountCode
            // 
            this.repGLAccountCode.AutoHeight = false;
            this.repGLAccountCode.Name = "repGLAccountCode";
            this.repGLAccountCode.NullText = "";
            this.repGLAccountCode.PopupView = this.repGLAccountCodeView;
            // 
            // repGLAccountCodeView
            // 
            this.repGLAccountCodeView.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.repGLAccountCodeView.Name = "repGLAccountCodeView";
            this.repGLAccountCodeView.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.repGLAccountCodeView.OptionsView.ShowGroupPanel = false;
            // 
            // repGLDebit
            // 
            this.repGLDebit.AutoHeight = false;
            this.repGLDebit.DisplayFormat.FormatString = "n2";
            this.repGLDebit.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.repGLDebit.Mask.EditMask = "n2";
            this.repGLDebit.Name = "repGLDebit";
            // 
            // repGLCredit
            // 
            this.repGLCredit.AutoHeight = false;
            this.repGLCredit.DisplayFormat.FormatString = "n2";
            this.repGLCredit.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.repGLCredit.Mask.EditMask = "n2";
            this.repGLCredit.Name = "repGLCredit";
            // 
            // repGLParticulars
            // 
            this.repGLParticulars.AutoHeight = false;
            this.repGLParticulars.Name = "repGLParticulars";
            // 
            // btnAddGLLine
            // 
            this.btnAddGLLine.Location = new System.Drawing.Point(5, 15);
            this.btnAddGLLine.Name = "btnAddGLLine";
            this.btnAddGLLine.Size = new System.Drawing.Size(110, 28);
            this.btnAddGLLine.TabIndex = 1;
            this.btnAddGLLine.Text = "Add Line";
            this.btnAddGLLine.Click += new System.EventHandler(this.BtnAddGLLine_Click);
            // 
            // btnRemoveGLLine
            // 
            this.btnRemoveGLLine.Location = new System.Drawing.Point(123, 15);
            this.btnRemoveGLLine.Name = "btnRemoveGLLine";
            this.btnRemoveGLLine.Size = new System.Drawing.Size(110, 28);
            this.btnRemoveGLLine.TabIndex = 2;
            this.btnRemoveGLLine.Text = "Remove Line";
            this.btnRemoveGLLine.Click += new System.EventHandler(this.BtnRemoveGLLine_Click);
            // 
            // lblTieStatus
            // 
            this.lblTieStatus.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblTieStatus.Appearance.Options.UseFont = true;
            this.lblTieStatus.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblTieStatus.Location = new System.Drawing.Point(5, 51);
            this.lblTieStatus.Name = "lblTieStatus";
            this.lblTieStatus.Size = new System.Drawing.Size(940, 18);
            this.lblTieStatus.TabIndex = 3;
            // 
            // lblBalanceStatus
            // 
            this.lblBalanceStatus.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblBalanceStatus.Appearance.ForeColor = System.Drawing.Color.Red;
            this.lblBalanceStatus.Appearance.Options.UseFont = true;
            this.lblBalanceStatus.Appearance.Options.UseForeColor = true;
            this.lblBalanceStatus.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblBalanceStatus.Location = new System.Drawing.Point(5, 73);
            this.lblBalanceStatus.Name = "lblBalanceStatus";
            this.lblBalanceStatus.Size = new System.Drawing.Size(940, 18);
            this.lblBalanceStatus.TabIndex = 4;
            // 
            // btnPost
            // 
            this.btnPost.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.btnPost.Appearance.Options.UseFont = true;
            this.btnPost.Location = new System.Drawing.Point(724, 11);
            this.btnPost.Name = "btnPost";
            this.btnPost.Size = new System.Drawing.Size(120, 34);
            this.btnPost.TabIndex = 5;
            this.btnPost.Text = "Post";
            this.btnPost.Click += new System.EventHandler(this.BtnPost_Click);
            // 
            // btnClose
            // 
            this.btnClose.Location = new System.Drawing.Point(852, 11);
            this.btnClose.Name = "btnClose";
            this.btnClose.Size = new System.Drawing.Size(100, 34);
            this.btnClose.TabIndex = 6;
            this.btnClose.Text = "Close";
            this.btnClose.Click += new System.EventHandler(this.BtnClose_Click);
            // 
            // panelControl1
            // 
            this.panelControl1.Controls.Add(this.btnAddGLLine);
            this.panelControl1.Controls.Add(this.btnClose);
            this.panelControl1.Controls.Add(this.btnRemoveGLLine);
            this.panelControl1.Controls.Add(this.btnPost);
            this.panelControl1.Controls.Add(this.lblBalanceStatus);
            this.panelControl1.Controls.Add(this.lblTieStatus);
            this.panelControl1.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.panelControl1.Location = new System.Drawing.Point(0, 721);
            this.panelControl1.Name = "panelControl1";
            this.panelControl1.Size = new System.Drawing.Size(996, 100);
            this.panelControl1.TabIndex = 7;
            // 
            // tabMain
            // 
            this.tabMain.Dock = System.Windows.Forms.DockStyle.Fill;
            this.tabMain.Location = new System.Drawing.Point(0, 0);
            this.tabMain.Name = "tabMain";
            this.tabMain.SelectedTabPage = this.tabNewVoucher;
            this.tabMain.Size = new System.Drawing.Size(998, 851);
            this.tabMain.TabIndex = 0;
            this.tabMain.TabPages.AddRange(new DevExpress.XtraTab.XtraTabPage[] {
            this.tabNewVoucher,
            this.tabPosted});
            this.tabMain.SelectedPageChanged += new DevExpress.XtraTab.TabPageChangedEventHandler(this.TabMain_SelectedPageChanged);
            // 
            // tabNewVoucher
            // 
            this.tabNewVoucher.Controls.Add(this.panelControl1);
            this.tabNewVoucher.Controls.Add(this.grpGLEntry);
            this.tabNewVoucher.Controls.Add(this.grpInvoices);
            this.tabNewVoucher.Controls.Add(this.grpHeader);
            this.tabNewVoucher.Name = "tabNewVoucher";
            this.tabNewVoucher.Size = new System.Drawing.Size(996, 821);
            this.tabNewVoucher.Text = "New Telegraphic Voucher";
            // 
            // tabPosted
            // 
            this.tabPosted.Name = "tabPosted";
            this.tabPosted.Size = new System.Drawing.Size(996, 821);
            this.tabPosted.Text = "Posted Telegraphic Voucher";
            // 
            // pnlPostedFilter
            // 
            this.pnlPostedFilter.Location = new System.Drawing.Point(0, 0);
            this.pnlPostedFilter.Name = "pnlPostedFilter";
            this.pnlPostedFilter.Size = new System.Drawing.Size(200, 100);
            this.pnlPostedFilter.TabIndex = 0;
            // 
            // lblPostedDateFrom
            // 
            this.lblPostedDateFrom.Location = new System.Drawing.Point(0, 0);
            this.lblPostedDateFrom.Name = "lblPostedDateFrom";
            this.lblPostedDateFrom.Size = new System.Drawing.Size(94, 17);
            this.lblPostedDateFrom.TabIndex = 0;
            // 
            // txtPostedDateFrom
            // 
            this.txtPostedDateFrom.EditValue = new System.DateTime(2026, 7, 24, 0, 0, 0, 0);
            this.txtPostedDateFrom.Location = new System.Drawing.Point(0, 0);
            this.txtPostedDateFrom.Name = "txtPostedDateFrom";
            this.txtPostedDateFrom.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtPostedDateFrom.Size = new System.Drawing.Size(125, 22);
            this.txtPostedDateFrom.TabIndex = 0;
            // 
            // lblPostedDateTo
            // 
            this.lblPostedDateTo.Location = new System.Drawing.Point(0, 0);
            this.lblPostedDateTo.Name = "lblPostedDateTo";
            this.lblPostedDateTo.Size = new System.Drawing.Size(94, 17);
            this.lblPostedDateTo.TabIndex = 0;
            // 
            // txtPostedDateTo
            // 
            this.txtPostedDateTo.EditValue = new System.DateTime(2026, 7, 24, 0, 0, 0, 0);
            this.txtPostedDateTo.Location = new System.Drawing.Point(0, 0);
            this.txtPostedDateTo.Name = "txtPostedDateTo";
            this.txtPostedDateTo.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtPostedDateTo.Size = new System.Drawing.Size(125, 22);
            this.txtPostedDateTo.TabIndex = 0;
            // 
            // btnRefreshPosted
            // 
            this.btnRefreshPosted.Location = new System.Drawing.Point(0, 0);
            this.btnRefreshPosted.Name = "btnRefreshPosted";
            this.btnRefreshPosted.Size = new System.Drawing.Size(94, 29);
            this.btnRefreshPosted.TabIndex = 0;
            // 
            // gridControlPosted
            // 
            this.gridControlPosted.Location = new System.Drawing.Point(0, 0);
            this.gridControlPosted.MainView = this.gridView1;
            this.gridControlPosted.Name = "gridControlPosted";
            this.gridControlPosted.Size = new System.Drawing.Size(400, 200);
            this.gridControlPosted.TabIndex = 0;
            this.gridControlPosted.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridView1});
            // 
            // gridView1
            // 
            this.gridView1.GridControl = this.gridControlPosted;
            this.gridView1.Name = "gridView1";
            // 
            // gridViewPosted
            // 
            this.gridViewPosted.Name = "gridViewPosted";
            // 
            // pnlPostedButtons
            // 
            this.pnlPostedButtons.Location = new System.Drawing.Point(0, 0);
            this.pnlPostedButtons.Name = "pnlPostedButtons";
            this.pnlPostedButtons.Size = new System.Drawing.Size(200, 100);
            this.pnlPostedButtons.TabIndex = 0;
            // 
            // btnViewPostedDetails
            // 
            this.btnViewPostedDetails.Location = new System.Drawing.Point(0, 0);
            this.btnViewPostedDetails.Name = "btnViewPostedDetails";
            this.btnViewPostedDetails.Size = new System.Drawing.Size(94, 29);
            this.btnViewPostedDetails.TabIndex = 0;
            // 
            // btnCopyPostedToNew
            // 
            this.btnCopyPostedToNew.Location = new System.Drawing.Point(0, 0);
            this.btnCopyPostedToNew.Name = "btnCopyPostedToNew";
            this.btnCopyPostedToNew.Size = new System.Drawing.Size(94, 29);
            this.btnCopyPostedToNew.TabIndex = 0;
            // 
            // gridControlPostedDetails
            // 
            this.gridControlPostedDetails.Location = new System.Drawing.Point(0, 0);
            this.gridControlPostedDetails.MainView = this.gridView2;
            this.gridControlPostedDetails.Name = "gridControlPostedDetails";
            this.gridControlPostedDetails.Size = new System.Drawing.Size(400, 200);
            this.gridControlPostedDetails.TabIndex = 0;
            this.gridControlPostedDetails.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridView2});
            // 
            // gridView2
            // 
            this.gridView2.GridControl = this.gridControlPostedDetails;
            this.gridView2.Name = "gridView2";
            // 
            // gridViewPostedDetails
            // 
            this.gridViewPostedDetails.Name = "gridViewPostedDetails";
            // 
            // VoucheringManualFrm
            // 
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Inherit;
            this.Controls.Add(this.tabMain);
            this.Name = "VoucheringManualFrm";
            this.Size = new System.Drawing.Size(998, 851);
            this.Load += new System.EventHandler(this.VoucheringManualFrm_Load);
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).EndInit();
            this.grpHeader.ResumeLayout(false);
            this.grpHeader.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtVoucherDate.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtVoucherDate.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranch.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboSupplier.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewSupplierPopup)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtCheckNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtControlNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtRemarks.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboCreditGLCode.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewCreditGLPopup)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpInvoices)).EndInit();
            this.grpInvoices.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlInvoices)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewInvoices)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repPay)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repInvAmount)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpGLEntry)).EndInit();
            this.grpGLEntry.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlGL)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewGL)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repGLAccountCode)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repGLAccountCodeView)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repGLDebit)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repGLCredit)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repGLParticulars)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl1)).EndInit();
            this.panelControl1.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.tabMain)).EndInit();
            this.tabMain.ResumeLayout(false);
            this.tabNewVoucher.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.pnlPostedFilter)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtPostedDateFrom.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtPostedDateFrom.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtPostedDateTo.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtPostedDateTo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlPosted)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView1)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewPosted)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlPostedButtons)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlPostedDetails)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView2)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewPostedDetails)).EndInit();
            this.ResumeLayout(false);

        }

        private DevExpress.XtraEditors.PanelControl panelControl1;
        private DevExpress.XtraGrid.Views.Grid.GridView gridView1;
        private DevExpress.XtraGrid.Views.Grid.GridView gridView2;
    }
}