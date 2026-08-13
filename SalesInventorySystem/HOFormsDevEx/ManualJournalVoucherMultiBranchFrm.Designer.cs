namespace SalesInventorySystem.HOFormsDevEx
{
    partial class ManualJournalVoucherMultiBranchFrm
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null)) components.Dispose();
            base.Dispose(disposing);
        }

        // ── Tabs ─────────────────────────────────────────────────
        private DevExpress.XtraTab.XtraTabControl tabMain;
        private DevExpress.XtraTab.XtraTabPage tabNew;
        private DevExpress.XtraTab.XtraTabPage tabPosted;

        // ── tabNew: New Voucher (unchanged from before) ──────────
        private DevExpress.XtraEditors.GroupControl grpHeader;
        private DevExpress.XtraEditors.LabelControl lblReferenceNo;
        private DevExpress.XtraEditors.TextEdit txtReferenceNo;
        private DevExpress.XtraEditors.LabelControl lblVoucherDate;
        private DevExpress.XtraEditors.DateEdit txtVoucherDate;
        private DevExpress.XtraEditors.LabelControl lblDefaultBranch;
        private DevExpress.XtraEditors.LookUpEdit cboDefaultBranch;
        private DevExpress.XtraEditors.LabelControl lblRemarks;
        private DevExpress.XtraEditors.MemoEdit txtRemarks;

        private DevExpress.XtraEditors.GroupControl grpLines;
        private DevExpress.XtraGrid.GridControl gridControlLines;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewLines;
        private DevExpress.XtraGrid.Columns.GridColumn colBranchCode;
        private DevExpress.XtraGrid.Columns.GridColumn colAccountCode;
        private DevExpress.XtraGrid.Columns.GridColumn colDebit;
        private DevExpress.XtraGrid.Columns.GridColumn colCredit;
        private DevExpress.XtraGrid.Columns.GridColumn colParticulars;
        private DevExpress.XtraEditors.Repository.RepositoryItemLookUpEdit repBranchCode;
        private DevExpress.XtraEditors.Repository.RepositoryItemSearchLookUpEdit repAccountCode;
        private DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit repDebit;
        private DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit repCredit;
        private DevExpress.XtraEditors.Repository.RepositoryItemTextEdit repParticulars;

        private DevExpress.XtraEditors.SimpleButton btnAddLine;
        private DevExpress.XtraEditors.SimpleButton btnRemoveLine;
        private DevExpress.XtraEditors.CheckEdit chkAllowCrossBranch;

        private DevExpress.XtraEditors.LabelControl lblTotalDebitCaption;
        private DevExpress.XtraEditors.LabelControl lblTotalDebit;
        private DevExpress.XtraEditors.LabelControl lblTotalCreditCaption;
        private DevExpress.XtraEditors.LabelControl lblTotalCredit;
        private DevExpress.XtraEditors.LabelControl lblBalanceStatus;
        private DevExpress.XtraEditors.SimpleButton btnPost;
        private DevExpress.XtraEditors.SimpleButton btnClose;

        // ── tabPosted: Posted Vouchers (NEW) ─────────────────────
        private DevExpress.XtraEditors.PanelControl pnlPostedFilter;
        private DevExpress.XtraEditors.LabelControl lblDateFrom;
        private DevExpress.XtraEditors.DateEdit txtDateFrom;
        private DevExpress.XtraEditors.LabelControl lblDateTo;
        private DevExpress.XtraEditors.DateEdit txtDateTo;
        private DevExpress.XtraEditors.SimpleButton btnRefreshPosted;

        private DevExpress.XtraGrid.GridControl gridControlPosted;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewPosted;

        private DevExpress.XtraEditors.PanelControl pnlPostedButtons;
        private DevExpress.XtraEditors.SimpleButton btnViewDetails;
        private DevExpress.XtraEditors.SimpleButton btnCopyToNew;
        private DevExpress.XtraEditors.SimpleButton btnEditVoucher;
        private DevExpress.XtraEditors.LabelControl lblEditNotice;

        private DevExpress.XtraGrid.GridControl gridControlPostedDetails;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewPostedDetails;

        private void InitializeComponent()
        {
            this.tabMain = new DevExpress.XtraTab.XtraTabControl();
            this.tabNew = new DevExpress.XtraTab.XtraTabPage();
            this.panelControl1 = new DevExpress.XtraEditors.PanelControl();
            this.btnAddLine = new DevExpress.XtraEditors.SimpleButton();
            this.chkAllowCrossBranch = new DevExpress.XtraEditors.CheckEdit();
            this.btnRemoveLine = new DevExpress.XtraEditors.SimpleButton();
            this.lblBalanceStatus = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalDebitCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalCredit = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalDebit = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalCreditCaption = new DevExpress.XtraEditors.LabelControl();
            this.panelControl2 = new DevExpress.XtraEditors.PanelControl();
            this.btnPost = new DevExpress.XtraEditors.SimpleButton();
            this.btnClose = new DevExpress.XtraEditors.SimpleButton();
            this.grpLines = new DevExpress.XtraEditors.GroupControl();
            this.gridControlLines = new DevExpress.XtraGrid.GridControl();
            this.gridViewLines = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.colBranchCode = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colAccountCode = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colParticulars = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colDebit = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colCredit = new DevExpress.XtraGrid.Columns.GridColumn();
            this.repBranchCode = new DevExpress.XtraEditors.Repository.RepositoryItemLookUpEdit();
            this.repAccountCode = new DevExpress.XtraEditors.Repository.RepositoryItemSearchLookUpEdit();
            this.repParticulars = new DevExpress.XtraEditors.Repository.RepositoryItemTextEdit();
            this.repDebit = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.repCredit = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.lblEditNotice = new DevExpress.XtraEditors.LabelControl();
            this.grpHeader = new DevExpress.XtraEditors.GroupControl();
            this.txtcontrolno = new DevExpress.XtraEditors.TextEdit();
            this.labelControl1 = new DevExpress.XtraEditors.LabelControl();
            this.lblReferenceNo = new DevExpress.XtraEditors.LabelControl();
            this.txtReferenceNo = new DevExpress.XtraEditors.TextEdit();
            this.lblVoucherDate = new DevExpress.XtraEditors.LabelControl();
            this.txtVoucherDate = new DevExpress.XtraEditors.DateEdit();
            this.lblDefaultBranch = new DevExpress.XtraEditors.LabelControl();
            this.cboDefaultBranch = new DevExpress.XtraEditors.LookUpEdit();
            this.lblRemarks = new DevExpress.XtraEditors.LabelControl();
            this.txtRemarks = new DevExpress.XtraEditors.MemoEdit();
            this.tabPosted = new DevExpress.XtraTab.XtraTabPage();
            this.gridControlPostedDetails = new DevExpress.XtraGrid.GridControl();
            this.gridViewPostedDetails = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.pnlPostedButtons = new DevExpress.XtraEditors.PanelControl();
            this.btnViewDetails = new DevExpress.XtraEditors.SimpleButton();
            this.btnCopyToNew = new DevExpress.XtraEditors.SimpleButton();
            this.btnEditVoucher = new DevExpress.XtraEditors.SimpleButton();
            this.gridControlPosted = new DevExpress.XtraGrid.GridControl();
            this.gridViewPosted = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.pnlPostedFilter = new DevExpress.XtraEditors.PanelControl();
            this.lblDateFrom = new DevExpress.XtraEditors.LabelControl();
            this.txtDateFrom = new DevExpress.XtraEditors.DateEdit();
            this.lblDateTo = new DevExpress.XtraEditors.LabelControl();
            this.txtDateTo = new DevExpress.XtraEditors.DateEdit();
            this.btnRefreshPosted = new DevExpress.XtraEditors.SimpleButton();
            ((System.ComponentModel.ISupportInitialize)(this.tabMain)).BeginInit();
            this.tabMain.SuspendLayout();
            this.tabNew.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl1)).BeginInit();
            this.panelControl1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.chkAllowCrossBranch.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl2)).BeginInit();
            this.panelControl2.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.grpLines)).BeginInit();
            this.grpLines.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlLines)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewLines)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repBranchCode)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repAccountCode)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repParticulars)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repDebit)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repCredit)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).BeginInit();
            this.grpHeader.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtcontrolno.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtVoucherDate.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtVoucherDate.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboDefaultBranch.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtRemarks.Properties)).BeginInit();
            this.tabPosted.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlPostedDetails)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewPostedDetails)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlPostedButtons)).BeginInit();
            this.pnlPostedButtons.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlPosted)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewPosted)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlPostedFilter)).BeginInit();
            this.pnlPostedFilter.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateFrom.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateFrom.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateTo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateTo.Properties.CalendarTimeProperties)).BeginInit();
            this.SuspendLayout();
            // 
            // tabMain
            // 
            this.tabMain.Dock = System.Windows.Forms.DockStyle.Fill;
            this.tabMain.Location = new System.Drawing.Point(0, 0);
            this.tabMain.Name = "tabMain";
            this.tabMain.SelectedTabPage = this.tabNew;
            this.tabMain.Size = new System.Drawing.Size(1078, 939);
            this.tabMain.TabIndex = 0;
            this.tabMain.TabPages.AddRange(new DevExpress.XtraTab.XtraTabPage[] {
            this.tabNew,
            this.tabPosted});
            this.tabMain.SelectedPageChanged += new DevExpress.XtraTab.TabPageChangedEventHandler(this.TabMain_SelectedPageChanged);
            this.tabMain.Click += new System.EventHandler(this.tabMain_Click);
            // 
            // tabNew
            // 
            this.tabNew.Controls.Add(this.panelControl1);
            this.tabNew.Controls.Add(this.panelControl2);
            this.tabNew.Controls.Add(this.grpLines);
            this.tabNew.Controls.Add(this.lblEditNotice);
            this.tabNew.Controls.Add(this.grpHeader);
            this.tabNew.Name = "tabNew";
            this.tabNew.Size = new System.Drawing.Size(1076, 909);
            this.tabNew.Text = "New Voucher";
            // 
            // panelControl1
            // 
            this.panelControl1.Controls.Add(this.btnAddLine);
            this.panelControl1.Controls.Add(this.chkAllowCrossBranch);
            this.panelControl1.Controls.Add(this.btnRemoveLine);
            this.panelControl1.Controls.Add(this.lblBalanceStatus);
            this.panelControl1.Controls.Add(this.lblTotalDebitCaption);
            this.panelControl1.Controls.Add(this.lblTotalCredit);
            this.panelControl1.Controls.Add(this.lblTotalDebit);
            this.panelControl1.Controls.Add(this.lblTotalCreditCaption);
            this.panelControl1.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.panelControl1.Location = new System.Drawing.Point(0, 759);
            this.panelControl1.Name = "panelControl1";
            this.panelControl1.Size = new System.Drawing.Size(1076, 100);
            this.panelControl1.TabIndex = 5;
            // 
            // btnAddLine
            // 
            this.btnAddLine.Location = new System.Drawing.Point(19, 5);
            this.btnAddLine.Name = "btnAddLine";
            this.btnAddLine.Size = new System.Drawing.Size(128, 34);
            this.btnAddLine.TabIndex = 1;
            this.btnAddLine.Text = "Add Line";
            this.btnAddLine.Click += new System.EventHandler(this.btnAddLine_Click);
            // 
            // chkAllowCrossBranch
            // 
            this.chkAllowCrossBranch.Location = new System.Drawing.Point(19, 70);
            this.chkAllowCrossBranch.Name = "chkAllowCrossBranch";
            this.chkAllowCrossBranch.Properties.Caption = "Allow Cross-Branch Entry (only overall total needs to balance)";
            this.chkAllowCrossBranch.Size = new System.Drawing.Size(420, 24);
            this.chkAllowCrossBranch.TabIndex = 8;
            this.chkAllowCrossBranch.CheckedChanged += new System.EventHandler(this.ChkAllowCrossBranch_CheckedChanged);
            // 
            // btnRemoveLine
            // 
            this.btnRemoveLine.Location = new System.Drawing.Point(156, 5);
            this.btnRemoveLine.Name = "btnRemoveLine";
            this.btnRemoveLine.Size = new System.Drawing.Size(128, 34);
            this.btnRemoveLine.TabIndex = 2;
            this.btnRemoveLine.Text = "Remove Line";
            this.btnRemoveLine.Click += new System.EventHandler(this.btnRemoveLine_Click);
            // 
            // lblBalanceStatus
            // 
            this.lblBalanceStatus.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblBalanceStatus.Appearance.ForeColor = System.Drawing.Color.Red;
            this.lblBalanceStatus.Appearance.Options.UseFont = true;
            this.lblBalanceStatus.Appearance.Options.UseForeColor = true;
            this.lblBalanceStatus.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblBalanceStatus.Location = new System.Drawing.Point(19, 40);
            this.lblBalanceStatus.Name = "lblBalanceStatus";
            this.lblBalanceStatus.Size = new System.Drawing.Size(700, 22);
            this.lblBalanceStatus.TabIndex = 7;
            // 
            // lblTotalDebitCaption
            // 
            this.lblTotalDebitCaption.Location = new System.Drawing.Point(666, 5);
            this.lblTotalDebitCaption.Name = "lblTotalDebitCaption";
            this.lblTotalDebitCaption.Size = new System.Drawing.Size(67, 16);
            this.lblTotalDebitCaption.TabIndex = 3;
            this.lblTotalDebitCaption.Text = "Total Debit:";
            // 
            // lblTotalCredit
            // 
            this.lblTotalCredit.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblTotalCredit.Appearance.Options.UseFont = true;
            this.lblTotalCredit.Location = new System.Drawing.Point(970, 5);
            this.lblTotalCredit.Name = "lblTotalCredit";
            this.lblTotalCredit.Size = new System.Drawing.Size(35, 18);
            this.lblTotalCredit.TabIndex = 6;
            this.lblTotalCredit.Text = "0.00";
            // 
            // lblTotalDebit
            // 
            this.lblTotalDebit.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblTotalDebit.Appearance.Options.UseFont = true;
            this.lblTotalDebit.Location = new System.Drawing.Point(760, 5);
            this.lblTotalDebit.Name = "lblTotalDebit";
            this.lblTotalDebit.Size = new System.Drawing.Size(35, 18);
            this.lblTotalDebit.TabIndex = 4;
            this.lblTotalDebit.Text = "0.00";
            // 
            // lblTotalCreditCaption
            // 
            this.lblTotalCreditCaption.Location = new System.Drawing.Point(876, 5);
            this.lblTotalCreditCaption.Name = "lblTotalCreditCaption";
            this.lblTotalCreditCaption.Size = new System.Drawing.Size(72, 16);
            this.lblTotalCreditCaption.TabIndex = 5;
            this.lblTotalCreditCaption.Text = "Total Credit:";
            // 
            // panelControl2
            // 
            this.panelControl2.Controls.Add(this.btnPost);
            this.panelControl2.Controls.Add(this.btnClose);
            this.panelControl2.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.panelControl2.Location = new System.Drawing.Point(0, 859);
            this.panelControl2.Name = "panelControl2";
            this.panelControl2.Size = new System.Drawing.Size(1076, 50);
            this.panelControl2.TabIndex = 6;
            // 
            // btnPost
            // 
            this.btnPost.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.btnPost.Appearance.Options.UseFont = true;
            this.btnPost.Location = new System.Drawing.Point(19, 5);
            this.btnPost.Name = "btnPost";
            this.btnPost.Size = new System.Drawing.Size(99, 39);
            this.btnPost.TabIndex = 2;
            this.btnPost.Text = "Post";
            this.btnPost.Click += new System.EventHandler(this.btnPost_Click);
            // 
            // btnClose
            // 
            this.btnClose.Location = new System.Drawing.Point(127, 5);
            this.btnClose.Name = "btnClose";
            this.btnClose.Size = new System.Drawing.Size(93, 39);
            this.btnClose.TabIndex = 3;
            this.btnClose.Text = "Close";
            this.btnClose.Click += new System.EventHandler(this.btnClose_Click);
            // 
            // grpLines
            // 
            this.grpLines.Controls.Add(this.gridControlLines);
            this.grpLines.Dock = System.Windows.Forms.DockStyle.Fill;
            this.grpLines.Location = new System.Drawing.Point(0, 147);
            this.grpLines.Name = "grpLines";
            this.grpLines.Size = new System.Drawing.Size(1076, 762);
            this.grpLines.TabIndex = 1;
            this.grpLines.Text = "Journal Entry Lines";
            // 
            // gridControlLines
            // 
            this.gridControlLines.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlLines.Location = new System.Drawing.Point(2, 28);
            this.gridControlLines.MainView = this.gridViewLines;
            this.gridControlLines.Name = "gridControlLines";
            this.gridControlLines.RepositoryItems.AddRange(new DevExpress.XtraEditors.Repository.RepositoryItem[] {
            this.repBranchCode,
            this.repAccountCode,
            this.repParticulars,
            this.repDebit,
            this.repCredit});
            this.gridControlLines.Size = new System.Drawing.Size(1072, 732);
            this.gridControlLines.TabIndex = 0;
            this.gridControlLines.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewLines});
            // 
            // gridViewLines
            // 
            this.gridViewLines.Columns.AddRange(new DevExpress.XtraGrid.Columns.GridColumn[] {
            this.colBranchCode,
            this.colAccountCode,
            this.colParticulars,
            this.colDebit,
            this.colCredit});
            this.gridViewLines.DetailHeight = 431;
            this.gridViewLines.GridControl = this.gridControlLines;
            this.gridViewLines.Name = "gridViewLines";
            this.gridViewLines.OptionsCustomization.AllowSort = false;
            this.gridViewLines.RowCellStyle += new DevExpress.XtraGrid.Views.Grid.RowCellStyleEventHandler(this.gridViewLines_RowCellStyle);
            this.gridViewLines.CustomRowCellEdit += new DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventHandler(this.gridViewLines_CustomRowCellEdit);
            this.gridViewLines.CellValueChanged += new DevExpress.XtraGrid.Views.Base.CellValueChangedEventHandler(this.gridViewLines_CellValueChanged);
            // 
            // colBranchCode
            // 
            this.colBranchCode.Caption = "Branch";
            this.colBranchCode.FieldName = "BranchCode";
            this.colBranchCode.MinWidth = 23;
            this.colBranchCode.Name = "colBranchCode";
            this.colBranchCode.Visible = true;
            this.colBranchCode.VisibleIndex = 0;
            this.colBranchCode.Width = 152;
            // 
            // colAccountCode
            // 
            this.colAccountCode.Caption = "Account Code";
            this.colAccountCode.FieldName = "AccountCode";
            this.colAccountCode.MinWidth = 23;
            this.colAccountCode.Name = "colAccountCode";
            this.colAccountCode.Visible = true;
            this.colAccountCode.VisibleIndex = 1;
            this.colAccountCode.Width = 280;
            // 
            // colParticulars
            // 
            this.colParticulars.Caption = "Particulars";
            this.colParticulars.FieldName = "Particulars";
            this.colParticulars.MinWidth = 23;
            this.colParticulars.Name = "colParticulars";
            this.colParticulars.Visible = true;
            this.colParticulars.VisibleIndex = 2;
            this.colParticulars.Width = 233;
            // 
            // colDebit
            // 
            this.colDebit.Caption = "Debit";
            this.colDebit.FieldName = "Debit";
            this.colDebit.MinWidth = 23;
            this.colDebit.Name = "colDebit";
            this.colDebit.Visible = true;
            this.colDebit.VisibleIndex = 3;
            this.colDebit.Width = 140;
            // 
            // colCredit
            // 
            this.colCredit.Caption = "Credit";
            this.colCredit.FieldName = "Credit";
            this.colCredit.MinWidth = 23;
            this.colCredit.Name = "colCredit";
            this.colCredit.Visible = true;
            this.colCredit.VisibleIndex = 4;
            this.colCredit.Width = 140;
            // 
            // repBranchCode
            // 
            this.repBranchCode.AutoHeight = false;
            this.repBranchCode.Name = "repBranchCode";
            this.repBranchCode.NullText = "";
            // 
            // repAccountCode
            // 
            this.repAccountCode.AutoHeight = false;
            this.repAccountCode.Name = "repAccountCode";
            this.repAccountCode.NullText = "";
            // 
            // repParticulars
            // 
            this.repParticulars.AutoHeight = false;
            this.repParticulars.Name = "repParticulars";
            // 
            // repDebit
            // 
            this.repDebit.AutoHeight = false;
            this.repDebit.DisplayFormat.FormatString = "n2";
            this.repDebit.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.repDebit.Mask.EditMask = "n2";
            this.repDebit.Name = "repDebit";
            // 
            // repCredit
            // 
            this.repCredit.AutoHeight = false;
            this.repCredit.DisplayFormat.FormatString = "n2";
            this.repCredit.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.repCredit.Mask.EditMask = "n2";
            this.repCredit.Name = "repCredit";
            // 
            // lblEditNotice
            // 
            this.lblEditNotice.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblEditNotice.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(180)))), ((int)(((byte)(120)))), ((int)(((byte)(0)))));
            this.lblEditNotice.Appearance.Options.UseFont = true;
            this.lblEditNotice.Appearance.Options.UseForeColor = true;
            this.lblEditNotice.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblEditNotice.Location = new System.Drawing.Point(14, 690);
            this.lblEditNotice.Name = "lblEditNotice";
            this.lblEditNotice.Size = new System.Drawing.Size(840, 18);
            this.lblEditNotice.TabIndex = 4;
            this.lblEditNotice.Visible = false;
            // 
            // grpHeader
            // 
            this.grpHeader.Controls.Add(this.txtcontrolno);
            this.grpHeader.Controls.Add(this.labelControl1);
            this.grpHeader.Controls.Add(this.lblReferenceNo);
            this.grpHeader.Controls.Add(this.txtReferenceNo);
            this.grpHeader.Controls.Add(this.lblVoucherDate);
            this.grpHeader.Controls.Add(this.txtVoucherDate);
            this.grpHeader.Controls.Add(this.lblDefaultBranch);
            this.grpHeader.Controls.Add(this.cboDefaultBranch);
            this.grpHeader.Controls.Add(this.lblRemarks);
            this.grpHeader.Controls.Add(this.txtRemarks);
            this.grpHeader.Dock = System.Windows.Forms.DockStyle.Top;
            this.grpHeader.Location = new System.Drawing.Point(0, 0);
            this.grpHeader.Name = "grpHeader";
            this.grpHeader.Size = new System.Drawing.Size(1076, 147);
            this.grpHeader.TabIndex = 0;
            this.grpHeader.Text = "Journal Voucher Header";
            // 
            // txtcontrolno
            // 
            this.txtcontrolno.Location = new System.Drawing.Point(725, 33);
            this.txtcontrolno.Name = "txtcontrolno";
            this.txtcontrolno.Size = new System.Drawing.Size(152, 22);
            this.txtcontrolno.TabIndex = 9;
            // 
            // labelControl1
            // 
            this.labelControl1.Location = new System.Drawing.Point(636, 36);
            this.labelControl1.Name = "labelControl1";
            this.labelControl1.Size = new System.Drawing.Size(69, 16);
            this.labelControl1.TabIndex = 8;
            this.labelControl1.Text = "Control No:.";
            // 
            // lblReferenceNo
            // 
            this.lblReferenceNo.Location = new System.Drawing.Point(19, 36);
            this.lblReferenceNo.Name = "lblReferenceNo";
            this.lblReferenceNo.Size = new System.Drawing.Size(86, 16);
            this.lblReferenceNo.TabIndex = 0;
            this.lblReferenceNo.Text = "Reference No.:";
            // 
            // txtReferenceNo
            // 
            this.txtReferenceNo.Location = new System.Drawing.Point(140, 33);
            this.txtReferenceNo.Name = "txtReferenceNo";
            this.txtReferenceNo.Properties.ReadOnly = true;
            this.txtReferenceNo.Size = new System.Drawing.Size(152, 22);
            this.txtReferenceNo.TabIndex = 1;
            // 
            // lblVoucherDate
            // 
            this.lblVoucherDate.Location = new System.Drawing.Point(327, 36);
            this.lblVoucherDate.Name = "lblVoucherDate";
            this.lblVoucherDate.Size = new System.Drawing.Size(82, 16);
            this.lblVoucherDate.TabIndex = 2;
            this.lblVoucherDate.Text = "Voucher Date:";
            // 
            // txtVoucherDate
            // 
            this.txtVoucherDate.EditValue = new System.DateTime(2026, 7, 18, 0, 0, 0, 0);
            this.txtVoucherDate.Location = new System.Drawing.Point(443, 33);
            this.txtVoucherDate.Name = "txtVoucherDate";
            this.txtVoucherDate.Size = new System.Drawing.Size(152, 22);
            this.txtVoucherDate.TabIndex = 3;
            // 
            // lblDefaultBranch
            // 
            this.lblDefaultBranch.Location = new System.Drawing.Point(19, 115);
            this.lblDefaultBranch.Name = "lblDefaultBranch";
            this.lblDefaultBranch.Size = new System.Drawing.Size(88, 16);
            this.lblDefaultBranch.TabIndex = 4;
            this.lblDefaultBranch.Text = "Default Branch:";
            this.lblDefaultBranch.Visible = false;
            // 
            // cboDefaultBranch
            // 
            this.cboDefaultBranch.Location = new System.Drawing.Point(14, 125);
            this.cboDefaultBranch.Name = "cboDefaultBranch";
            this.cboDefaultBranch.Size = new System.Drawing.Size(120, 22);
            this.cboDefaultBranch.TabIndex = 5;
            this.cboDefaultBranch.Visible = false;
            // 
            // lblRemarks
            // 
            this.lblRemarks.Location = new System.Drawing.Point(19, 76);
            this.lblRemarks.Name = "lblRemarks";
            this.lblRemarks.Size = new System.Drawing.Size(55, 16);
            this.lblRemarks.TabIndex = 6;
            this.lblRemarks.Text = "Remarks:";
            // 
            // txtRemarks
            // 
            this.txtRemarks.Location = new System.Drawing.Point(140, 72);
            this.txtRemarks.Name = "txtRemarks";
            this.txtRemarks.Size = new System.Drawing.Size(887, 59);
            this.txtRemarks.TabIndex = 7;
            // 
            // tabPosted
            // 
            this.tabPosted.Controls.Add(this.gridControlPostedDetails);
            this.tabPosted.Controls.Add(this.pnlPostedButtons);
            this.tabPosted.Controls.Add(this.gridControlPosted);
            this.tabPosted.Controls.Add(this.pnlPostedFilter);
            this.tabPosted.Name = "tabPosted";
            this.tabPosted.Size = new System.Drawing.Size(1076, 909);
            this.tabPosted.Text = "Posted Vouchers";
            // 
            // gridControlPostedDetails
            // 
            this.gridControlPostedDetails.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlPostedDetails.Location = new System.Drawing.Point(0, 490);
            this.gridControlPostedDetails.MainView = this.gridViewPostedDetails;
            this.gridControlPostedDetails.Name = "gridControlPostedDetails";
            this.gridControlPostedDetails.Size = new System.Drawing.Size(1076, 419);
            this.gridControlPostedDetails.TabIndex = 0;
            this.gridControlPostedDetails.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewPostedDetails});
            // 
            // gridViewPostedDetails
            // 
            this.gridViewPostedDetails.DetailHeight = 431;
            this.gridViewPostedDetails.GridControl = this.gridControlPostedDetails;
            this.gridViewPostedDetails.Name = "gridViewPostedDetails";
            this.gridViewPostedDetails.OptionsBehavior.Editable = false;
            this.gridViewPostedDetails.OptionsView.ShowGroupPanel = false;
            // 
            // pnlPostedButtons
            // 
            this.pnlPostedButtons.Controls.Add(this.btnViewDetails);
            this.pnlPostedButtons.Controls.Add(this.btnCopyToNew);
            this.pnlPostedButtons.Controls.Add(this.btnEditVoucher);
            this.pnlPostedButtons.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlPostedButtons.Location = new System.Drawing.Point(0, 445);
            this.pnlPostedButtons.Name = "pnlPostedButtons";
            this.pnlPostedButtons.Size = new System.Drawing.Size(1076, 45);
            this.pnlPostedButtons.TabIndex = 1;
            // 
            // btnViewDetails
            // 
            this.btnViewDetails.Enabled = false;
            this.btnViewDetails.Location = new System.Drawing.Point(14, 9);
            this.btnViewDetails.Name = "btnViewDetails";
            this.btnViewDetails.Size = new System.Drawing.Size(128, 31);
            this.btnViewDetails.TabIndex = 0;
            this.btnViewDetails.Text = "View Details";
            this.btnViewDetails.Click += new System.EventHandler(this.BtnViewDetails_Click);
            // 
            // btnCopyToNew
            // 
            this.btnCopyToNew.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(255)))), ((int)(((byte)(244)))), ((int)(((byte)(219)))));
            this.btnCopyToNew.Appearance.Options.UseBackColor = true;
            this.btnCopyToNew.Enabled = false;
            this.btnCopyToNew.Location = new System.Drawing.Point(152, 9);
            this.btnCopyToNew.Name = "btnCopyToNew";
            this.btnCopyToNew.Size = new System.Drawing.Size(163, 31);
            this.btnCopyToNew.TabIndex = 1;
            this.btnCopyToNew.Text = "Copy to New Entry";
            this.btnCopyToNew.Click += new System.EventHandler(this.BtnCopyToNew_Click);
            // 
            // btnEditVoucher
            // 
            this.btnEditVoucher.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(220)))), ((int)(((byte)(235)))), ((int)(((byte)(255)))));
            this.btnEditVoucher.Appearance.Options.UseBackColor = true;
            this.btnEditVoucher.Enabled = false;
            this.btnEditVoucher.Location = new System.Drawing.Point(324, 9);
            this.btnEditVoucher.Name = "btnEditVoucher";
            this.btnEditVoucher.Size = new System.Drawing.Size(128, 31);
            this.btnEditVoucher.TabIndex = 2;
            this.btnEditVoucher.Text = "Edit Voucher";
            this.btnEditVoucher.Click += new System.EventHandler(this.BtnEditVoucher_Click);
            // 
            // gridControlPosted
            // 
            this.gridControlPosted.Dock = System.Windows.Forms.DockStyle.Top;
            this.gridControlPosted.Location = new System.Drawing.Point(0, 58);
            this.gridControlPosted.MainView = this.gridViewPosted;
            this.gridControlPosted.Name = "gridControlPosted";
            this.gridControlPosted.Size = new System.Drawing.Size(1076, 387);
            this.gridControlPosted.TabIndex = 2;
            this.gridControlPosted.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewPosted});
            // 
            // gridViewPosted
            // 
            this.gridViewPosted.DetailHeight = 431;
            this.gridViewPosted.GridControl = this.gridControlPosted;
            this.gridViewPosted.Name = "gridViewPosted";
            this.gridViewPosted.OptionsBehavior.Editable = false;
            this.gridViewPosted.OptionsView.ShowGroupPanel = false;
            this.gridViewPosted.FocusedRowChanged += new DevExpress.XtraGrid.Views.Base.FocusedRowChangedEventHandler(this.GridViewPosted_FocusedRowChanged);
            this.gridViewPosted.DoubleClick += new System.EventHandler(this.GridViewPosted_DoubleClick);
            // 
            // pnlPostedFilter
            // 
            this.pnlPostedFilter.Controls.Add(this.lblDateFrom);
            this.pnlPostedFilter.Controls.Add(this.txtDateFrom);
            this.pnlPostedFilter.Controls.Add(this.lblDateTo);
            this.pnlPostedFilter.Controls.Add(this.txtDateTo);
            this.pnlPostedFilter.Controls.Add(this.btnRefreshPosted);
            this.pnlPostedFilter.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlPostedFilter.Location = new System.Drawing.Point(0, 0);
            this.pnlPostedFilter.Name = "pnlPostedFilter";
            this.pnlPostedFilter.Size = new System.Drawing.Size(1076, 58);
            this.pnlPostedFilter.TabIndex = 3;
            // 
            // lblDateFrom
            // 
            this.lblDateFrom.Location = new System.Drawing.Point(14, 22);
            this.lblDateFrom.Name = "lblDateFrom";
            this.lblDateFrom.Size = new System.Drawing.Size(35, 16);
            this.lblDateFrom.TabIndex = 0;
            this.lblDateFrom.Text = "From:";
            // 
            // txtDateFrom
            // 
            this.txtDateFrom.EditValue = new System.DateTime(2026, 7, 18, 0, 0, 0, 0);
            this.txtDateFrom.Location = new System.Drawing.Point(58, 17);
            this.txtDateFrom.Name = "txtDateFrom";
            this.txtDateFrom.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtDateFrom.Size = new System.Drawing.Size(128, 22);
            this.txtDateFrom.TabIndex = 1;
            // 
            // lblDateTo
            // 
            this.lblDateTo.Location = new System.Drawing.Point(203, 22);
            this.lblDateTo.Name = "lblDateTo";
            this.lblDateTo.Size = new System.Drawing.Size(20, 16);
            this.lblDateTo.TabIndex = 2;
            this.lblDateTo.Text = "To:";
            // 
            // txtDateTo
            // 
            this.txtDateTo.EditValue = new System.DateTime(2026, 7, 18, 0, 0, 0, 0);
            this.txtDateTo.Location = new System.Drawing.Point(233, 17);
            this.txtDateTo.Name = "txtDateTo";
            this.txtDateTo.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtDateTo.Size = new System.Drawing.Size(128, 22);
            this.txtDateTo.TabIndex = 3;
            // 
            // btnRefreshPosted
            // 
            this.btnRefreshPosted.Location = new System.Drawing.Point(376, 13);
            this.btnRefreshPosted.Name = "btnRefreshPosted";
            this.btnRefreshPosted.Size = new System.Drawing.Size(105, 31);
            this.btnRefreshPosted.TabIndex = 4;
            this.btnRefreshPosted.Text = "Refresh";
            this.btnRefreshPosted.Click += new System.EventHandler(this.BtnRefreshPosted_Click);
            // 
            // ManualJournalVoucherMultiBranchFrm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.Controls.Add(this.tabMain);
            this.Name = "ManualJournalVoucherMultiBranchFrm";
            this.Size = new System.Drawing.Size(1078, 939);
            this.Load += new System.EventHandler(this.ManualJournalVoucherMultiBranchFrm_Load);
            ((System.ComponentModel.ISupportInitialize)(this.tabMain)).EndInit();
            this.tabMain.ResumeLayout(false);
            this.tabNew.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.panelControl1)).EndInit();
            this.panelControl1.ResumeLayout(false);
            this.panelControl1.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.chkAllowCrossBranch.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl2)).EndInit();
            this.panelControl2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.grpLines)).EndInit();
            this.grpLines.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlLines)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewLines)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repBranchCode)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repAccountCode)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repParticulars)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repDebit)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repCredit)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).EndInit();
            this.grpHeader.ResumeLayout(false);
            this.grpHeader.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtcontrolno.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtVoucherDate.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtVoucherDate.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboDefaultBranch.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtRemarks.Properties)).EndInit();
            this.tabPosted.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlPostedDetails)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewPostedDetails)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlPostedButtons)).EndInit();
            this.pnlPostedButtons.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlPosted)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewPosted)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlPostedFilter)).EndInit();
            this.pnlPostedFilter.ResumeLayout(false);
            this.pnlPostedFilter.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateFrom.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateFrom.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateTo.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateTo.Properties)).EndInit();
            this.ResumeLayout(false);

        }

        private DevExpress.XtraEditors.PanelControl panelControl1;
        private DevExpress.XtraEditors.PanelControl panelControl2;
        private DevExpress.XtraEditors.LabelControl labelControl1;
        private DevExpress.XtraEditors.TextEdit txtcontrolno;
    }
}