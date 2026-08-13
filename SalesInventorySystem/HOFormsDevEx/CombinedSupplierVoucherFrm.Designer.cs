namespace SalesInventorySystem.HOFormsDevEx
{
    partial class CombinedSupplierVoucherFrm
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null)) components.Dispose();
            base.Dispose(disposing);
        }

        // ── Header ───────────────────────────────────────────────
        private DevExpress.XtraEditors.GroupControl grpHeader;
        private DevExpress.XtraEditors.LabelControl lblReferenceNo;
        private DevExpress.XtraEditors.TextEdit txtReferenceNo;
        private DevExpress.XtraEditors.LabelControl lblVoucherID;
        private DevExpress.XtraEditors.TextEdit txtVoucherID;
        private DevExpress.XtraEditors.RadioGroup radVoucherType;
        private DevExpress.XtraEditors.LabelControl lblCheckNo;
        private DevExpress.XtraEditors.TextEdit txtCheckNo;
        private DevExpress.XtraEditors.LabelControl lblCheckDate;
        private DevExpress.XtraEditors.DateEdit txtCheckDate;
        private DevExpress.XtraEditors.LabelControl lblControlNo;
        private DevExpress.XtraEditors.TextEdit txtControlNo;
        private DevExpress.XtraEditors.LabelControl lblControlDate;
        private DevExpress.XtraEditors.DateEdit txtControlDate;
        private DevExpress.XtraEditors.LabelControl lblBranch;
        private DevExpress.XtraEditors.LookUpEdit cboBranch;
        private DevExpress.XtraEditors.LabelControl lblSupplier;
        private DevExpress.XtraEditors.SearchLookUpEdit cboSupplier;
        private DevExpress.XtraEditors.LabelControl lblCreditAccount;
        private DevExpress.XtraEditors.LookUpEdit cboCreditAccount;
        private DevExpress.XtraEditors.LabelControl lblRemarks;
        private DevExpress.XtraEditors.MemoEdit txtRemarks;

        // ── Tabs ─────────────────────────────────────────────────
        private DevExpress.XtraTab.XtraTabControl tabMain;
        private DevExpress.XtraTab.XtraTabPage tabInvoices;
        private DevExpress.XtraTab.XtraTabPage tabManual;

        private DevExpress.XtraGrid.GridControl gridControlInvoices;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewInvoices;
        private DevExpress.XtraGrid.Columns.GridColumn colInvChecked;
        private DevExpress.XtraGrid.Columns.GridColumn colInvReferenceNumber;
        private DevExpress.XtraGrid.Columns.GridColumn colInvInvoiceNo;
        private DevExpress.XtraGrid.Columns.GridColumn colInvExpenseDate;
        private DevExpress.XtraGrid.Columns.GridColumn colInvDescription;
        private DevExpress.XtraGrid.Columns.GridColumn colInvBalance;
        private DevExpress.XtraEditors.Repository.RepositoryItemCheckEdit repCheck;

        private DevExpress.XtraGrid.GridControl gridControlManual;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewManual;
        private DevExpress.XtraGrid.Columns.GridColumn colManBranchCode;
        private DevExpress.XtraGrid.Columns.GridColumn colManAccountCode;
        private DevExpress.XtraGrid.Columns.GridColumn colManAmount;
        private DevExpress.XtraGrid.Columns.GridColumn colManParticulars;
        private DevExpress.XtraEditors.Repository.RepositoryItemLookUpEdit repManBranchCode;
        private DevExpress.XtraEditors.Repository.RepositoryItemSearchLookUpEdit repManAccountCode;
        private DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit repManAmount;
        private DevExpress.XtraEditors.Repository.RepositoryItemTextEdit repManParticulars;
        private DevExpress.XtraEditors.SimpleButton btnAddManualLine;
        private DevExpress.XtraEditors.SimpleButton btnRemoveManualLine;

        // ── Footer (spans both tabs) ─────────────────────────────
        private DevExpress.XtraEditors.PanelControl pnlFooter;
        private DevExpress.XtraEditors.LabelControl lblInvoiceTotalCaption;
        private DevExpress.XtraEditors.LabelControl lblInvoiceTotal;
        private DevExpress.XtraEditors.LabelControl lblManualTotalCaption;
        private DevExpress.XtraEditors.LabelControl lblManualTotal;
        private DevExpress.XtraEditors.LabelControl lblGrandTotalCaption;
        private DevExpress.XtraEditors.LabelControl lblGrandTotal;
        private DevExpress.XtraEditors.SimpleButton btnPost;
        private DevExpress.XtraEditors.SimpleButton btnClose;

        private void InitializeComponent()
        {
            this.grpHeader = new DevExpress.XtraEditors.GroupControl();
            this.lblReferenceNo = new DevExpress.XtraEditors.LabelControl();
            this.txtReferenceNo = new DevExpress.XtraEditors.TextEdit();
            this.lblVoucherID = new DevExpress.XtraEditors.LabelControl();
            this.txtVoucherID = new DevExpress.XtraEditors.TextEdit();
            this.radVoucherType = new DevExpress.XtraEditors.RadioGroup();
            this.lblCheckNo = new DevExpress.XtraEditors.LabelControl();
            this.txtCheckNo = new DevExpress.XtraEditors.TextEdit();
            this.lblCheckDate = new DevExpress.XtraEditors.LabelControl();
            this.txtCheckDate = new DevExpress.XtraEditors.DateEdit();
            this.lblControlNo = new DevExpress.XtraEditors.LabelControl();
            this.txtControlNo = new DevExpress.XtraEditors.TextEdit();
            this.lblControlDate = new DevExpress.XtraEditors.LabelControl();
            this.txtControlDate = new DevExpress.XtraEditors.DateEdit();
            this.lblBranch = new DevExpress.XtraEditors.LabelControl();
            this.cboBranch = new DevExpress.XtraEditors.LookUpEdit();
            this.lblSupplier = new DevExpress.XtraEditors.LabelControl();
            this.cboSupplier = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.lblCreditAccount = new DevExpress.XtraEditors.LabelControl();
            this.cboCreditAccount = new DevExpress.XtraEditors.LookUpEdit();
            this.lblRemarks = new DevExpress.XtraEditors.LabelControl();
            this.txtRemarks = new DevExpress.XtraEditors.MemoEdit();
            this.tabMain = new DevExpress.XtraTab.XtraTabControl();
            this.tabInvoices = new DevExpress.XtraTab.XtraTabPage();
            this.gridControlInvoices = new DevExpress.XtraGrid.GridControl();
            this.gridViewInvoices = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.colInvChecked = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colInvReferenceNumber = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colInvInvoiceNo = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colInvExpenseDate = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colInvDescription = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colInvBalance = new DevExpress.XtraGrid.Columns.GridColumn();
            this.repCheck = new DevExpress.XtraEditors.Repository.RepositoryItemCheckEdit();
            this.tabManual = new DevExpress.XtraTab.XtraTabPage();
            this.gridControlManual = new DevExpress.XtraGrid.GridControl();
            this.gridViewManual = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.colManBranchCode = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colManAccountCode = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colManAmount = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colManParticulars = new DevExpress.XtraGrid.Columns.GridColumn();
            this.repManBranchCode = new DevExpress.XtraEditors.Repository.RepositoryItemLookUpEdit();
            this.repManAccountCode = new DevExpress.XtraEditors.Repository.RepositoryItemSearchLookUpEdit();
            this.repManAmount = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.repManParticulars = new DevExpress.XtraEditors.Repository.RepositoryItemTextEdit();
            this.btnRemoveManualLine = new DevExpress.XtraEditors.SimpleButton();
            this.btnAddManualLine = new DevExpress.XtraEditors.SimpleButton();
            this.pnlFooter = new DevExpress.XtraEditors.PanelControl();
            this.lblInvoiceTotalCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblInvoiceTotal = new DevExpress.XtraEditors.LabelControl();
            this.lblManualTotalCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblManualTotal = new DevExpress.XtraEditors.LabelControl();
            this.lblGrandTotalCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblGrandTotal = new DevExpress.XtraEditors.LabelControl();
            this.btnPost = new DevExpress.XtraEditors.SimpleButton();
            this.btnClose = new DevExpress.XtraEditors.SimpleButton();
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).BeginInit();
            this.grpHeader.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtVoucherID.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.radVoucherType.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtCheckNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtCheckDate.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtCheckDate.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtControlNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtControlDate.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtControlDate.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranch.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboSupplier.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboCreditAccount.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtRemarks.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.tabMain)).BeginInit();
            this.tabMain.SuspendLayout();
            this.tabInvoices.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlInvoices)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewInvoices)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repCheck)).BeginInit();
            this.tabManual.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlManual)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewManual)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repManBranchCode)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repManAccountCode)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repManAmount)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repManParticulars)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlFooter)).BeginInit();
            this.pnlFooter.SuspendLayout();
            this.SuspendLayout();
            // 
            // grpHeader
            // 
            this.grpHeader.Controls.Add(this.lblReferenceNo);
            this.grpHeader.Controls.Add(this.txtReferenceNo);
            this.grpHeader.Controls.Add(this.lblVoucherID);
            this.grpHeader.Controls.Add(this.txtVoucherID);
            this.grpHeader.Controls.Add(this.radVoucherType);
            this.grpHeader.Controls.Add(this.lblCheckNo);
            this.grpHeader.Controls.Add(this.txtCheckNo);
            this.grpHeader.Controls.Add(this.lblCheckDate);
            this.grpHeader.Controls.Add(this.txtCheckDate);
            this.grpHeader.Controls.Add(this.lblControlNo);
            this.grpHeader.Controls.Add(this.txtControlNo);
            this.grpHeader.Controls.Add(this.lblControlDate);
            this.grpHeader.Controls.Add(this.txtControlDate);
            this.grpHeader.Controls.Add(this.lblBranch);
            this.grpHeader.Controls.Add(this.cboBranch);
            this.grpHeader.Controls.Add(this.lblSupplier);
            this.grpHeader.Controls.Add(this.cboSupplier);
            this.grpHeader.Controls.Add(this.lblCreditAccount);
            this.grpHeader.Controls.Add(this.cboCreditAccount);
            this.grpHeader.Controls.Add(this.lblRemarks);
            this.grpHeader.Controls.Add(this.txtRemarks);
            this.grpHeader.Dock = System.Windows.Forms.DockStyle.Top;
            this.grpHeader.Location = new System.Drawing.Point(0, 0);
            this.grpHeader.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.grpHeader.Name = "grpHeader";
            this.grpHeader.Size = new System.Drawing.Size(1120, 207);
            this.grpHeader.TabIndex = 2;
            this.grpHeader.Text = "Combined Supplier Voucher";
            // 
            // lblReferenceNo
            // 
            this.lblReferenceNo.Location = new System.Drawing.Point(19, 37);
            this.lblReferenceNo.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblReferenceNo.Name = "lblReferenceNo";
            this.lblReferenceNo.Size = new System.Drawing.Size(86, 16);
            this.lblReferenceNo.TabIndex = 0;
            this.lblReferenceNo.Text = "Reference No.:";
            // 
            // txtReferenceNo
            // 
            this.txtReferenceNo.Location = new System.Drawing.Point(175, 33);
            this.txtReferenceNo.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtReferenceNo.Name = "txtReferenceNo";
            this.txtReferenceNo.Properties.ReadOnly = true;
            this.txtReferenceNo.Size = new System.Drawing.Size(140, 22);
            this.txtReferenceNo.TabIndex = 1;
            // 
            // lblVoucherID
            // 
            this.lblVoucherID.Location = new System.Drawing.Point(338, 37);
            this.lblVoucherID.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblVoucherID.Name = "lblVoucherID";
            this.lblVoucherID.Size = new System.Drawing.Size(68, 16);
            this.lblVoucherID.TabIndex = 2;
            this.lblVoucherID.Text = "Voucher ID:";
            // 
            // txtVoucherID
            // 
            this.txtVoucherID.Location = new System.Drawing.Point(467, 33);
            this.txtVoucherID.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtVoucherID.Name = "txtVoucherID";
            this.txtVoucherID.Properties.ReadOnly = true;
            this.txtVoucherID.Size = new System.Drawing.Size(163, 22);
            this.txtVoucherID.TabIndex = 3;
            // 
            // radVoucherType
            // 
            this.radVoucherType.EditValue = "CASH";
            this.radVoucherType.Location = new System.Drawing.Point(653, 31);
            this.radVoucherType.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.radVoucherType.Name = "radVoucherType";
            this.radVoucherType.Properties.Items.AddRange(new DevExpress.XtraEditors.Controls.RadioGroupItem[] {
            new DevExpress.XtraEditors.Controls.RadioGroupItem("CASH", "Cash"),
            new DevExpress.XtraEditors.Controls.RadioGroupItem("CHECK", "Check"),
            new DevExpress.XtraEditors.Controls.RadioGroupItem("TELEGRAPHIC", "Telegraphic")});
            this.radVoucherType.Size = new System.Drawing.Size(327, 30);
            this.radVoucherType.TabIndex = 4;
            this.radVoucherType.SelectedIndexChanged += new System.EventHandler(this.RadVoucherType_SelectedIndexChanged);
            // 
            // lblCheckNo
            // 
            this.lblCheckNo.Location = new System.Drawing.Point(19, 71);
            this.lblCheckNo.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblCheckNo.Name = "lblCheckNo";
            this.lblCheckNo.Size = new System.Drawing.Size(62, 16);
            this.lblCheckNo.TabIndex = 5;
            this.lblCheckNo.Text = "Check No.:";
            // 
            // txtCheckNo
            // 
            this.txtCheckNo.Enabled = false;
            this.txtCheckNo.Location = new System.Drawing.Point(175, 68);
            this.txtCheckNo.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtCheckNo.Name = "txtCheckNo";
            this.txtCheckNo.Size = new System.Drawing.Size(163, 22);
            this.txtCheckNo.TabIndex = 6;
            // 
            // lblCheckDate
            // 
            this.lblCheckDate.Location = new System.Drawing.Point(362, 71);
            this.lblCheckDate.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblCheckDate.Name = "lblCheckDate";
            this.lblCheckDate.Size = new System.Drawing.Size(69, 16);
            this.lblCheckDate.TabIndex = 7;
            this.lblCheckDate.Text = "Check Date:";
            // 
            // txtCheckDate
            // 
            this.txtCheckDate.EditValue = new System.DateTime(2026, 7, 26, 0, 0, 0, 0);
            this.txtCheckDate.Enabled = false;
            this.txtCheckDate.Location = new System.Drawing.Point(467, 68);
            this.txtCheckDate.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtCheckDate.Name = "txtCheckDate";
            this.txtCheckDate.Size = new System.Drawing.Size(163, 22);
            this.txtCheckDate.TabIndex = 8;
            // 
            // lblControlNo
            // 
            this.lblControlNo.Location = new System.Drawing.Point(19, 71);
            this.lblControlNo.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblControlNo.Name = "lblControlNo";
            this.lblControlNo.Size = new System.Drawing.Size(69, 16);
            this.lblControlNo.TabIndex = 9;
            this.lblControlNo.Text = "Control No.:";
            // 
            // txtControlNo
            // 
            this.txtControlNo.Location = new System.Drawing.Point(175, 68);
            this.txtControlNo.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtControlNo.Name = "txtControlNo";
            this.txtControlNo.Size = new System.Drawing.Size(163, 22);
            this.txtControlNo.TabIndex = 10;
            // 
            // lblControlDate
            // 
            this.lblControlDate.Location = new System.Drawing.Point(362, 71);
            this.lblControlDate.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblControlDate.Name = "lblControlDate";
            this.lblControlDate.Size = new System.Drawing.Size(76, 16);
            this.lblControlDate.TabIndex = 11;
            this.lblControlDate.Text = "Control Date:";
            // 
            // txtControlDate
            // 
            this.txtControlDate.EditValue = new System.DateTime(2026, 7, 26, 0, 0, 0, 0);
            this.txtControlDate.Location = new System.Drawing.Point(467, 68);
            this.txtControlDate.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtControlDate.Name = "txtControlDate";
            this.txtControlDate.Size = new System.Drawing.Size(163, 22);
            this.txtControlDate.TabIndex = 12;
            // 
            // lblBranch
            // 
            this.lblBranch.Location = new System.Drawing.Point(19, 106);
            this.lblBranch.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblBranch.Name = "lblBranch";
            this.lblBranch.Size = new System.Drawing.Size(85, 16);
            this.lblBranch.TabIndex = 13;
            this.lblBranch.Text = "Paying Branch:";
            // 
            // cboBranch
            // 
            this.cboBranch.Location = new System.Drawing.Point(175, 102);
            this.cboBranch.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.cboBranch.Name = "cboBranch";
            this.cboBranch.Size = new System.Drawing.Size(455, 22);
            this.cboBranch.TabIndex = 14;
            // 
            // lblSupplier
            // 
            this.lblSupplier.Location = new System.Drawing.Point(19, 140);
            this.lblSupplier.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblSupplier.Name = "lblSupplier";
            this.lblSupplier.Size = new System.Drawing.Size(52, 16);
            this.lblSupplier.TabIndex = 15;
            this.lblSupplier.Text = "Supplier:";
            // 
            // cboSupplier
            // 
            this.cboSupplier.Location = new System.Drawing.Point(175, 137);
            this.cboSupplier.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.cboSupplier.Name = "cboSupplier";
            this.cboSupplier.Size = new System.Drawing.Size(455, 22);
            this.cboSupplier.TabIndex = 16;
            this.cboSupplier.EditValueChanged += new System.EventHandler(this.CboSupplier_EditValueChanged);
            // 
            // lblCreditAccount
            // 
            this.lblCreditAccount.Location = new System.Drawing.Point(653, 106);
            this.lblCreditAccount.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblCreditAccount.Name = "lblCreditAccount";
            this.lblCreditAccount.Size = new System.Drawing.Size(80, 16);
            this.lblCreditAccount.TabIndex = 17;
            this.lblCreditAccount.Text = "Credit (Bank):";
            // 
            // cboCreditAccount
            // 
            this.cboCreditAccount.Location = new System.Drawing.Point(653, 128);
            this.cboCreditAccount.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.cboCreditAccount.Name = "cboCreditAccount";
            this.cboCreditAccount.Size = new System.Drawing.Size(327, 22);
            this.cboCreditAccount.TabIndex = 18;
            // 
            // lblRemarks
            // 
            this.lblRemarks.Location = new System.Drawing.Point(653, 140);
            this.lblRemarks.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblRemarks.Name = "lblRemarks";
            this.lblRemarks.Size = new System.Drawing.Size(55, 16);
            this.lblRemarks.TabIndex = 19;
            this.lblRemarks.Text = "Remarks:";
            // 
            // txtRemarks
            // 
            this.txtRemarks.Location = new System.Drawing.Point(653, 162);
            this.txtRemarks.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtRemarks.Name = "txtRemarks";
            this.txtRemarks.Size = new System.Drawing.Size(327, 34);
            this.txtRemarks.TabIndex = 20;
            // 
            // tabMain
            // 
            this.tabMain.Dock = System.Windows.Forms.DockStyle.Fill;
            this.tabMain.Location = new System.Drawing.Point(0, 207);
            this.tabMain.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.tabMain.Name = "tabMain";
            this.tabMain.SelectedTabPage = this.tabInvoices;
            this.tabMain.Size = new System.Drawing.Size(1120, 507);
            this.tabMain.TabIndex = 0;
            this.tabMain.TabPages.AddRange(new DevExpress.XtraTab.XtraTabPage[] {
            this.tabInvoices,
            this.tabManual});
            // 
            // tabInvoices
            // 
            this.tabInvoices.Controls.Add(this.gridControlInvoices);
            this.tabInvoices.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.tabInvoices.Name = "tabInvoices";
            this.tabInvoices.Size = new System.Drawing.Size(1118, 477);
            this.tabInvoices.Text = "Unpaid Invoices";
            // 
            // gridControlInvoices
            // 
            this.gridControlInvoices.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlInvoices.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlInvoices.Location = new System.Drawing.Point(0, 0);
            this.gridControlInvoices.MainView = this.gridViewInvoices;
            this.gridControlInvoices.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlInvoices.Name = "gridControlInvoices";
            this.gridControlInvoices.RepositoryItems.AddRange(new DevExpress.XtraEditors.Repository.RepositoryItem[] {
            this.repCheck});
            this.gridControlInvoices.Size = new System.Drawing.Size(1118, 477);
            this.gridControlInvoices.TabIndex = 0;
            this.gridControlInvoices.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewInvoices});
            // 
            // gridViewInvoices
            // 
            this.gridViewInvoices.Columns.AddRange(new DevExpress.XtraGrid.Columns.GridColumn[] {
            this.colInvChecked,
            this.colInvReferenceNumber,
            this.colInvInvoiceNo,
            this.colInvExpenseDate,
            this.colInvDescription,
            this.colInvBalance});
            this.gridViewInvoices.DetailHeight = 431;
            this.gridViewInvoices.GridControl = this.gridControlInvoices;
            this.gridViewInvoices.Name = "gridViewInvoices";
            this.gridViewInvoices.OptionsView.ShowGroupPanel = false;
            this.gridViewInvoices.CustomRowCellEdit += new DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventHandler(this.GridViewInvoices_CustomRowCellEdit);
            this.gridViewInvoices.CellValueChanged += new DevExpress.XtraGrid.Views.Base.CellValueChangedEventHandler(this.GridViewInvoices_CellValueChanged);
            // 
            // colInvChecked
            // 
            this.colInvChecked.Caption = "Pay";
            this.colInvChecked.FieldName = "Checked";
            this.colInvChecked.MinWidth = 23;
            this.colInvChecked.Name = "colInvChecked";
            this.colInvChecked.Visible = true;
            this.colInvChecked.VisibleIndex = 0;
            this.colInvChecked.Width = 47;
            // 
            // colInvReferenceNumber
            // 
            this.colInvReferenceNumber.Caption = "Ref No.";
            this.colInvReferenceNumber.FieldName = "ReferenceNumber";
            this.colInvReferenceNumber.MinWidth = 23;
            this.colInvReferenceNumber.Name = "colInvReferenceNumber";
            this.colInvReferenceNumber.Visible = true;
            this.colInvReferenceNumber.VisibleIndex = 1;
            this.colInvReferenceNumber.Width = 105;
            // 
            // colInvInvoiceNo
            // 
            this.colInvInvoiceNo.Caption = "Invoice No.";
            this.colInvInvoiceNo.FieldName = "InvoiceNo";
            this.colInvInvoiceNo.MinWidth = 23;
            this.colInvInvoiceNo.Name = "colInvInvoiceNo";
            this.colInvInvoiceNo.Visible = true;
            this.colInvInvoiceNo.VisibleIndex = 2;
            this.colInvInvoiceNo.Width = 152;
            // 
            // colInvExpenseDate
            // 
            this.colInvExpenseDate.Caption = "Date";
            this.colInvExpenseDate.FieldName = "ExpenseDate";
            this.colInvExpenseDate.MinWidth = 23;
            this.colInvExpenseDate.Name = "colInvExpenseDate";
            this.colInvExpenseDate.Visible = true;
            this.colInvExpenseDate.VisibleIndex = 3;
            this.colInvExpenseDate.Width = 105;
            // 
            // colInvDescription
            // 
            this.colInvDescription.Caption = "Description";
            this.colInvDescription.FieldName = "Description";
            this.colInvDescription.MinWidth = 23;
            this.colInvDescription.Name = "colInvDescription";
            this.colInvDescription.Visible = true;
            this.colInvDescription.VisibleIndex = 4;
            this.colInvDescription.Width = 257;
            // 
            // colInvBalance
            // 
            this.colInvBalance.Caption = "Balance";
            this.colInvBalance.DisplayFormat.FormatString = "n2";
            this.colInvBalance.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.colInvBalance.FieldName = "Balance";
            this.colInvBalance.MinWidth = 23;
            this.colInvBalance.Name = "colInvBalance";
            this.colInvBalance.Visible = true;
            this.colInvBalance.VisibleIndex = 5;
            this.colInvBalance.Width = 140;
            // 
            // repCheck
            // 
            this.repCheck.AutoHeight = false;
            this.repCheck.Name = "repCheck";
            // 
            // tabManual
            // 
            this.tabManual.Controls.Add(this.gridControlManual);
            this.tabManual.Controls.Add(this.btnRemoveManualLine);
            this.tabManual.Controls.Add(this.btnAddManualLine);
            this.tabManual.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.tabManual.Name = "tabManual";
            this.tabManual.Size = new System.Drawing.Size(348, 339);
            this.tabManual.Text = "Manual Debit Entries";
            // 
            // gridControlManual
            // 
            this.gridControlManual.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlManual.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlManual.Location = new System.Drawing.Point(0, 0);
            this.gridControlManual.MainView = this.gridViewManual;
            this.gridControlManual.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlManual.Name = "gridControlManual";
            this.gridControlManual.RepositoryItems.AddRange(new DevExpress.XtraEditors.Repository.RepositoryItem[] {
            this.repManBranchCode,
            this.repManAccountCode,
            this.repManAmount,
            this.repManParticulars});
            this.gridControlManual.Size = new System.Drawing.Size(348, 265);
            this.gridControlManual.TabIndex = 0;
            this.gridControlManual.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewManual});
            // 
            // gridViewManual
            // 
            this.gridViewManual.Columns.AddRange(new DevExpress.XtraGrid.Columns.GridColumn[] {
            this.colManBranchCode,
            this.colManAccountCode,
            this.colManAmount,
            this.colManParticulars});
            this.gridViewManual.DetailHeight = 431;
            this.gridViewManual.GridControl = this.gridControlManual;
            this.gridViewManual.Name = "gridViewManual";
            this.gridViewManual.OptionsView.ShowGroupPanel = false;
            this.gridViewManual.RowCellStyle += new DevExpress.XtraGrid.Views.Grid.RowCellStyleEventHandler(this.GridViewManual_RowCellStyle);
            this.gridViewManual.CustomRowCellEdit += new DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventHandler(this.GridViewManual_CustomRowCellEdit);
            this.gridViewManual.CellValueChanged += new DevExpress.XtraGrid.Views.Base.CellValueChangedEventHandler(this.GridViewManual_CellValueChanged);
            // 
            // colManBranchCode
            // 
            this.colManBranchCode.Caption = "Branch";
            this.colManBranchCode.FieldName = "BranchCode";
            this.colManBranchCode.MinWidth = 23;
            this.colManBranchCode.Name = "colManBranchCode";
            this.colManBranchCode.Visible = true;
            this.colManBranchCode.VisibleIndex = 0;
            this.colManBranchCode.Width = 152;
            // 
            // colManAccountCode
            // 
            this.colManAccountCode.Caption = "Debit Account (any)";
            this.colManAccountCode.FieldName = "AccountCode";
            this.colManAccountCode.MinWidth = 23;
            this.colManAccountCode.Name = "colManAccountCode";
            this.colManAccountCode.Visible = true;
            this.colManAccountCode.VisibleIndex = 1;
            this.colManAccountCode.Width = 303;
            // 
            // colManAmount
            // 
            this.colManAmount.Caption = "Amount";
            this.colManAmount.FieldName = "Amount";
            this.colManAmount.MinWidth = 23;
            this.colManAmount.Name = "colManAmount";
            this.colManAmount.Visible = true;
            this.colManAmount.VisibleIndex = 2;
            this.colManAmount.Width = 152;
            // 
            // colManParticulars
            // 
            this.colManParticulars.Caption = "Particulars";
            this.colManParticulars.FieldName = "Particulars";
            this.colManParticulars.MinWidth = 23;
            this.colManParticulars.Name = "colManParticulars";
            this.colManParticulars.Visible = true;
            this.colManParticulars.VisibleIndex = 3;
            this.colManParticulars.Width = 257;
            // 
            // repManBranchCode
            // 
            this.repManBranchCode.AutoHeight = false;
            this.repManBranchCode.Name = "repManBranchCode";
            this.repManBranchCode.NullText = "";
            // 
            // repManAccountCode
            // 
            this.repManAccountCode.AutoHeight = false;
            this.repManAccountCode.Name = "repManAccountCode";
            this.repManAccountCode.NullText = "";
            this.repManAccountCode.PopupFilterMode = DevExpress.XtraEditors.PopupFilterMode.Contains;
            // 
            // repManAmount
            // 
            this.repManAmount.AutoHeight = false;
            this.repManAmount.DisplayFormat.FormatString = "n2";
            this.repManAmount.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.repManAmount.Mask.EditMask = "n2";
            this.repManAmount.Name = "repManAmount";
            // 
            // repManParticulars
            // 
            this.repManParticulars.AutoHeight = false;
            this.repManParticulars.Name = "repManParticulars";
            // 
            // btnRemoveManualLine
            // 
            this.btnRemoveManualLine.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.btnRemoveManualLine.Location = new System.Drawing.Point(0, 265);
            this.btnRemoveManualLine.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnRemoveManualLine.Name = "btnRemoveManualLine";
            this.btnRemoveManualLine.Size = new System.Drawing.Size(348, 37);
            this.btnRemoveManualLine.TabIndex = 1;
            this.btnRemoveManualLine.Text = "Remove Line";
            this.btnRemoveManualLine.Click += new System.EventHandler(this.BtnRemoveManualLine_Click);
            // 
            // btnAddManualLine
            // 
            this.btnAddManualLine.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.btnAddManualLine.Location = new System.Drawing.Point(0, 302);
            this.btnAddManualLine.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnAddManualLine.Name = "btnAddManualLine";
            this.btnAddManualLine.Size = new System.Drawing.Size(348, 37);
            this.btnAddManualLine.TabIndex = 2;
            this.btnAddManualLine.Text = "Add Line";
            this.btnAddManualLine.Click += new System.EventHandler(this.BtnAddManualLine_Click);
            // 
            // pnlFooter
            // 
            this.pnlFooter.Controls.Add(this.lblInvoiceTotalCaption);
            this.pnlFooter.Controls.Add(this.lblInvoiceTotal);
            this.pnlFooter.Controls.Add(this.lblManualTotalCaption);
            this.pnlFooter.Controls.Add(this.lblManualTotal);
            this.pnlFooter.Controls.Add(this.lblGrandTotalCaption);
            this.pnlFooter.Controls.Add(this.lblGrandTotal);
            this.pnlFooter.Controls.Add(this.btnPost);
            this.pnlFooter.Controls.Add(this.btnClose);
            this.pnlFooter.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.pnlFooter.Location = new System.Drawing.Point(0, 714);
            this.pnlFooter.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.pnlFooter.Name = "pnlFooter";
            this.pnlFooter.Size = new System.Drawing.Size(1120, 74);
            this.pnlFooter.TabIndex = 1;
            // 
            // lblInvoiceTotalCaption
            // 
            this.lblInvoiceTotalCaption.Location = new System.Drawing.Point(19, 15);
            this.lblInvoiceTotalCaption.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblInvoiceTotalCaption.Name = "lblInvoiceTotalCaption";
            this.lblInvoiceTotalCaption.Size = new System.Drawing.Size(84, 16);
            this.lblInvoiceTotalCaption.TabIndex = 0;
            this.lblInvoiceTotalCaption.Text = "Invoices Total:";
            // 
            // lblInvoiceTotal
            // 
            this.lblInvoiceTotal.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblInvoiceTotal.Appearance.Options.UseFont = true;
            this.lblInvoiceTotal.Location = new System.Drawing.Point(128, 15);
            this.lblInvoiceTotal.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblInvoiceTotal.Name = "lblInvoiceTotal";
            this.lblInvoiceTotal.Size = new System.Drawing.Size(35, 18);
            this.lblInvoiceTotal.TabIndex = 1;
            this.lblInvoiceTotal.Text = "0.00";
            // 
            // lblManualTotalCaption
            // 
            this.lblManualTotalCaption.Location = new System.Drawing.Point(257, 15);
            this.lblManualTotalCaption.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblManualTotalCaption.Name = "lblManualTotalCaption";
            this.lblManualTotalCaption.Size = new System.Drawing.Size(112, 16);
            this.lblManualTotalCaption.TabIndex = 2;
            this.lblManualTotalCaption.Text = "Manual Debit Total:";
            // 
            // lblManualTotal
            // 
            this.lblManualTotal.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblManualTotal.Appearance.Options.UseFont = true;
            this.lblManualTotal.Location = new System.Drawing.Point(397, 15);
            this.lblManualTotal.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblManualTotal.Name = "lblManualTotal";
            this.lblManualTotal.Size = new System.Drawing.Size(35, 18);
            this.lblManualTotal.TabIndex = 3;
            this.lblManualTotal.Text = "0.00";
            // 
            // lblGrandTotalCaption
            // 
            this.lblGrandTotalCaption.Appearance.Font = new System.Drawing.Font("Tahoma", 10F, System.Drawing.FontStyle.Bold);
            this.lblGrandTotalCaption.Appearance.Options.UseFont = true;
            this.lblGrandTotalCaption.Location = new System.Drawing.Point(19, 42);
            this.lblGrandTotalCaption.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblGrandTotalCaption.Name = "lblGrandTotalCaption";
            this.lblGrandTotalCaption.Size = new System.Drawing.Size(149, 21);
            this.lblGrandTotalCaption.TabIndex = 4;
            this.lblGrandTotalCaption.Text = "VOUCHER TOTAL:";
            // 
            // lblGrandTotal
            // 
            this.lblGrandTotal.Appearance.Font = new System.Drawing.Font("Tahoma", 12F, System.Drawing.FontStyle.Bold);
            this.lblGrandTotal.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(20)))), ((int)(((byte)(90)))), ((int)(((byte)(40)))));
            this.lblGrandTotal.Appearance.Options.UseFont = true;
            this.lblGrandTotal.Appearance.Options.UseForeColor = true;
            this.lblGrandTotal.Location = new System.Drawing.Point(175, 42);
            this.lblGrandTotal.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblGrandTotal.Name = "lblGrandTotal";
            this.lblGrandTotal.Size = new System.Drawing.Size(45, 24);
            this.lblGrandTotal.TabIndex = 5;
            this.lblGrandTotal.Text = "0.00";
            // 
            // btnPost
            // 
            this.btnPost.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.btnPost.Appearance.Options.UseFont = true;
            this.btnPost.Location = new System.Drawing.Point(887, 18);
            this.btnPost.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnPost.Name = "btnPost";
            this.btnPost.Size = new System.Drawing.Size(105, 39);
            this.btnPost.TabIndex = 6;
            this.btnPost.Text = "Post";
            this.btnPost.Click += new System.EventHandler(this.BtnPost_Click);
            // 
            // btnClose
            // 
            this.btnClose.Location = new System.Drawing.Point(999, 18);
            this.btnClose.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnClose.Name = "btnClose";
            this.btnClose.Size = new System.Drawing.Size(93, 39);
            this.btnClose.TabIndex = 7;
            this.btnClose.Text = "Close";
            this.btnClose.Click += new System.EventHandler(this.BtnClose_Click);
            // 
            // CombinedSupplierVoucherFrm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1120, 788);
            this.Controls.Add(this.tabMain);
            this.Controls.Add(this.pnlFooter);
            this.Controls.Add(this.grpHeader);
            this.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.Name = "CombinedSupplierVoucherFrm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "Combined Supplier Voucher";
            this.Load += new System.EventHandler(this.CombinedSupplierVoucherFrm_Load);
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).EndInit();
            this.grpHeader.ResumeLayout(false);
            this.grpHeader.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtVoucherID.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.radVoucherType.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtCheckNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtCheckDate.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtCheckDate.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtControlNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtControlDate.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtControlDate.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranch.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboSupplier.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboCreditAccount.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtRemarks.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.tabMain)).EndInit();
            this.tabMain.ResumeLayout(false);
            this.tabInvoices.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlInvoices)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewInvoices)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repCheck)).EndInit();
            this.tabManual.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlManual)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewManual)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repManBranchCode)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repManAccountCode)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repManAmount)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repManParticulars)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlFooter)).EndInit();
            this.pnlFooter.ResumeLayout(false);
            this.pnlFooter.PerformLayout();
            this.ResumeLayout(false);

        }
    }
}