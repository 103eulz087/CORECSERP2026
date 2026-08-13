namespace SalesInventorySystem.HOFormsDevEx
{
    partial class ManualJournalVoucherFrm
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

        // ── tabNew: New Voucher ──────────────────────────────────
        private DevExpress.XtraEditors.GroupControl grpHeader;
        private DevExpress.XtraEditors.LabelControl lblReferenceNo;
        private DevExpress.XtraEditors.TextEdit txtReferenceNo;
        private DevExpress.XtraEditors.LabelControl lblVoucherDate;
        private DevExpress.XtraEditors.DateEdit txtVoucherDate;
        private DevExpress.XtraEditors.LabelControl lblBranch;
        private DevExpress.XtraEditors.LookUpEdit cboBranch;
        private DevExpress.XtraEditors.LabelControl lblRemarks;
        private DevExpress.XtraEditors.MemoEdit txtRemarks;

        private DevExpress.XtraEditors.GroupControl grpLines;
        private DevExpress.XtraGrid.GridControl gridControlLines;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewLines;
        private DevExpress.XtraGrid.Columns.GridColumn colAccountCode;
        private DevExpress.XtraGrid.Columns.GridColumn colDebit;
        private DevExpress.XtraGrid.Columns.GridColumn colCredit;
        private DevExpress.XtraGrid.Columns.GridColumn colParticulars;
        private DevExpress.XtraEditors.Repository.RepositoryItemSearchLookUpEdit repAccountCode;
        private DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit repDebit;
        private DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit repCredit;
        private DevExpress.XtraEditors.Repository.RepositoryItemTextEdit repParticulars;
        private DevExpress.XtraEditors.SimpleButton btnAddLine;
        private DevExpress.XtraEditors.SimpleButton btnRemoveLine;

        private DevExpress.XtraEditors.LabelControl lblTotalDebitCaption;
        private DevExpress.XtraEditors.LabelControl lblTotalDebit;
        private DevExpress.XtraEditors.LabelControl lblTotalCreditCaption;
        private DevExpress.XtraEditors.LabelControl lblTotalCredit;
        private DevExpress.XtraEditors.LabelControl lblBalanceStatus;
        private DevExpress.XtraEditors.SimpleButton btnPost;
        private DevExpress.XtraEditors.SimpleButton btnClose;

        // ── tabPosted: Posted Vouchers ────────────────────────────
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

        private DevExpress.XtraGrid.GridControl gridControlPostedDetails;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewPostedDetails;

        private void InitializeComponent()
        {
            this.tabMain = new DevExpress.XtraTab.XtraTabControl();
            this.tabNew = new DevExpress.XtraTab.XtraTabPage();
            this.panelControl1 = new DevExpress.XtraEditors.PanelControl();
            this.btnAddLine = new DevExpress.XtraEditors.SimpleButton();
            this.lblBalanceStatus = new DevExpress.XtraEditors.LabelControl();
            this.btnRemoveLine = new DevExpress.XtraEditors.SimpleButton();
            this.lblTotalCredit = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalDebitCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalCreditCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalDebit = new DevExpress.XtraEditors.LabelControl();
            this.panelControl2 = new DevExpress.XtraEditors.PanelControl();
            this.btnPost = new DevExpress.XtraEditors.SimpleButton();
            this.btnClose = new DevExpress.XtraEditors.SimpleButton();
            this.grpLines = new DevExpress.XtraEditors.GroupControl();
            this.gridControlLines = new DevExpress.XtraGrid.GridControl();
            this.gridViewLines = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.colAccountCode = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colParticulars = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colDebit = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colCredit = new DevExpress.XtraGrid.Columns.GridColumn();
            this.repAccountCode = new DevExpress.XtraEditors.Repository.RepositoryItemSearchLookUpEdit();
            this.repParticulars = new DevExpress.XtraEditors.Repository.RepositoryItemTextEdit();
            this.repDebit = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.repCredit = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.grpHeader = new DevExpress.XtraEditors.GroupControl();
            this.lblReferenceNo = new DevExpress.XtraEditors.LabelControl();
            this.txtReferenceNo = new DevExpress.XtraEditors.TextEdit();
            this.lblVoucherDate = new DevExpress.XtraEditors.LabelControl();
            this.txtVoucherDate = new DevExpress.XtraEditors.DateEdit();
            this.lblBranch = new DevExpress.XtraEditors.LabelControl();
            this.cboBranch = new DevExpress.XtraEditors.LookUpEdit();
            this.lblRemarks = new DevExpress.XtraEditors.LabelControl();
            this.txtRemarks = new DevExpress.XtraEditors.MemoEdit();
            this.tabPosted = new DevExpress.XtraTab.XtraTabPage();
            this.gridControlPostedDetails = new DevExpress.XtraGrid.GridControl();
            this.gridViewPostedDetails = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.pnlPostedButtons = new DevExpress.XtraEditors.PanelControl();
            this.btnViewDetails = new DevExpress.XtraEditors.SimpleButton();
            this.btnCopyToNew = new DevExpress.XtraEditors.SimpleButton();
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
            ((System.ComponentModel.ISupportInitialize)(this.panelControl2)).BeginInit();
            this.panelControl2.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.grpLines)).BeginInit();
            this.grpLines.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlLines)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewLines)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repAccountCode)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repParticulars)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repDebit)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repCredit)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).BeginInit();
            this.grpHeader.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtVoucherDate.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtVoucherDate.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranch.Properties)).BeginInit();
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
            ((System.ComponentModel.ISupportInitialize)(this.txtDateFrom.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateFrom.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateTo.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateTo.Properties)).BeginInit();
            this.SuspendLayout();
            // 
            // tabMain
            // 
            this.tabMain.Dock = System.Windows.Forms.DockStyle.Fill;
            this.tabMain.Location = new System.Drawing.Point(0, 0);
            this.tabMain.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.tabMain.Name = "tabMain";
            this.tabMain.SelectedTabPage = this.tabNew;
            this.tabMain.Size = new System.Drawing.Size(915, 884);
            this.tabMain.TabIndex = 0;
            this.tabMain.TabPages.AddRange(new DevExpress.XtraTab.XtraTabPage[] {
            this.tabNew,
            this.tabPosted});
            this.tabMain.SelectedPageChanged += new DevExpress.XtraTab.TabPageChangedEventHandler(this.TabMain_SelectedPageChanged);
            // 
            // tabNew
            // 
            this.tabNew.Controls.Add(this.panelControl1);
            this.tabNew.Controls.Add(this.panelControl2);
            this.tabNew.Controls.Add(this.grpLines);
            this.tabNew.Controls.Add(this.grpHeader);
            this.tabNew.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.tabNew.Name = "tabNew";
            this.tabNew.Size = new System.Drawing.Size(913, 854);
            this.tabNew.Text = "New Voucher";
            // 
            // panelControl1
            // 
            this.panelControl1.Controls.Add(this.btnAddLine);
            this.panelControl1.Controls.Add(this.lblBalanceStatus);
            this.panelControl1.Controls.Add(this.btnRemoveLine);
            this.panelControl1.Controls.Add(this.lblTotalCredit);
            this.panelControl1.Controls.Add(this.lblTotalDebitCaption);
            this.panelControl1.Controls.Add(this.lblTotalCreditCaption);
            this.panelControl1.Controls.Add(this.lblTotalDebit);
            this.panelControl1.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.panelControl1.Location = new System.Drawing.Point(0, 719);
            this.panelControl1.Name = "panelControl1";
            this.panelControl1.Size = new System.Drawing.Size(913, 82);
            this.panelControl1.TabIndex = 4;
            // 
            // btnAddLine
            // 
            this.btnAddLine.Location = new System.Drawing.Point(8, 6);
            this.btnAddLine.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnAddLine.Name = "btnAddLine";
            this.btnAddLine.Size = new System.Drawing.Size(128, 34);
            this.btnAddLine.TabIndex = 1;
            this.btnAddLine.Text = "Add Line";
            this.btnAddLine.Click += new System.EventHandler(this.btnAddLine_Click);
            // 
            // lblBalanceStatus
            // 
            this.lblBalanceStatus.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblBalanceStatus.Appearance.ForeColor = System.Drawing.Color.Red;
            this.lblBalanceStatus.Appearance.Options.UseFont = true;
            this.lblBalanceStatus.Appearance.Options.UseForeColor = true;
            this.lblBalanceStatus.Location = new System.Drawing.Point(8, 43);
            this.lblBalanceStatus.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblBalanceStatus.Name = "lblBalanceStatus";
            this.lblBalanceStatus.Size = new System.Drawing.Size(0, 18);
            this.lblBalanceStatus.TabIndex = 7;
            // 
            // btnRemoveLine
            // 
            this.btnRemoveLine.Location = new System.Drawing.Point(145, 6);
            this.btnRemoveLine.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnRemoveLine.Name = "btnRemoveLine";
            this.btnRemoveLine.Size = new System.Drawing.Size(128, 34);
            this.btnRemoveLine.TabIndex = 2;
            this.btnRemoveLine.Text = "Remove Line";
            this.btnRemoveLine.Click += new System.EventHandler(this.btnRemoveLine_Click);
            // 
            // lblTotalCredit
            // 
            this.lblTotalCredit.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblTotalCredit.Appearance.Options.UseFont = true;
            this.lblTotalCredit.Location = new System.Drawing.Point(724, 14);
            this.lblTotalCredit.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblTotalCredit.Name = "lblTotalCredit";
            this.lblTotalCredit.Size = new System.Drawing.Size(35, 18);
            this.lblTotalCredit.TabIndex = 6;
            this.lblTotalCredit.Text = "0.00";
            // 
            // lblTotalDebitCaption
            // 
            this.lblTotalDebitCaption.Location = new System.Drawing.Point(432, 14);
            this.lblTotalDebitCaption.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblTotalDebitCaption.Name = "lblTotalDebitCaption";
            this.lblTotalDebitCaption.Size = new System.Drawing.Size(67, 16);
            this.lblTotalDebitCaption.TabIndex = 3;
            this.lblTotalDebitCaption.Text = "Total Debit:";
            // 
            // lblTotalCreditCaption
            // 
            this.lblTotalCreditCaption.Location = new System.Drawing.Point(631, 14);
            this.lblTotalCreditCaption.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblTotalCreditCaption.Name = "lblTotalCreditCaption";
            this.lblTotalCreditCaption.Size = new System.Drawing.Size(72, 16);
            this.lblTotalCreditCaption.TabIndex = 5;
            this.lblTotalCreditCaption.Text = "Total Credit:";
            // 
            // lblTotalDebit
            // 
            this.lblTotalDebit.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblTotalDebit.Appearance.Options.UseFont = true;
            this.lblTotalDebit.Location = new System.Drawing.Point(526, 14);
            this.lblTotalDebit.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblTotalDebit.Name = "lblTotalDebit";
            this.lblTotalDebit.Size = new System.Drawing.Size(35, 18);
            this.lblTotalDebit.TabIndex = 4;
            this.lblTotalDebit.Text = "0.00";
            // 
            // panelControl2
            // 
            this.panelControl2.Controls.Add(this.btnPost);
            this.panelControl2.Controls.Add(this.btnClose);
            this.panelControl2.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.panelControl2.Location = new System.Drawing.Point(0, 801);
            this.panelControl2.Name = "panelControl2";
            this.panelControl2.Size = new System.Drawing.Size(913, 53);
            this.panelControl2.TabIndex = 5;
            // 
            // btnPost
            // 
            this.btnPost.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.btnPost.Appearance.Options.UseFont = true;
            this.btnPost.Location = new System.Drawing.Point(5, 6);
            this.btnPost.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnPost.Name = "btnPost";
            this.btnPost.Size = new System.Drawing.Size(99, 39);
            this.btnPost.TabIndex = 2;
            this.btnPost.Text = "Post";
            this.btnPost.Click += new System.EventHandler(this.btnPost_Click);
            // 
            // btnClose
            // 
            this.btnClose.Location = new System.Drawing.Point(112, 6);
            this.btnClose.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
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
            this.grpLines.Location = new System.Drawing.Point(0, 148);
            this.grpLines.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.grpLines.Name = "grpLines";
            this.grpLines.Size = new System.Drawing.Size(913, 706);
            this.grpLines.TabIndex = 1;
            this.grpLines.Text = "Journal Entry Lines";
            // 
            // gridControlLines
            // 
            this.gridControlLines.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlLines.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlLines.Location = new System.Drawing.Point(2, 28);
            this.gridControlLines.MainView = this.gridViewLines;
            this.gridControlLines.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlLines.Name = "gridControlLines";
            this.gridControlLines.RepositoryItems.AddRange(new DevExpress.XtraEditors.Repository.RepositoryItem[] {
            this.repAccountCode,
            this.repParticulars,
            this.repDebit,
            this.repCredit});
            this.gridControlLines.Size = new System.Drawing.Size(909, 676);
            this.gridControlLines.TabIndex = 0;
            this.gridControlLines.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewLines});
            // 
            // gridViewLines
            // 
            this.gridViewLines.Columns.AddRange(new DevExpress.XtraGrid.Columns.GridColumn[] {
            this.colAccountCode,
            this.colParticulars,
            this.colDebit,
            this.colCredit});
            this.gridViewLines.DetailHeight = 431;
            this.gridViewLines.GridControl = this.gridControlLines;
            this.gridViewLines.Name = "gridViewLines";
            this.gridViewLines.OptionsCustomization.AllowSort = false;
            this.gridViewLines.OptionsView.ShowGroupPanel = false;
            this.gridViewLines.RowCellStyle += new DevExpress.XtraGrid.Views.Grid.RowCellStyleEventHandler(this.gridViewLines_RowCellStyle);
            this.gridViewLines.CustomRowCellEdit += new DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventHandler(this.gridViewLines_CustomRowCellEdit);
            this.gridViewLines.CellValueChanged += new DevExpress.XtraGrid.Views.Base.CellValueChangedEventHandler(this.gridViewLines_CellValueChanged);
            // 
            // colAccountCode
            // 
            this.colAccountCode.Caption = "Account Code";
            this.colAccountCode.FieldName = "AccountCode";
            this.colAccountCode.MinWidth = 23;
            this.colAccountCode.Name = "colAccountCode";
            this.colAccountCode.Visible = true;
            this.colAccountCode.VisibleIndex = 0;
            this.colAccountCode.Width = 303;
            // 
            // colParticulars
            // 
            this.colParticulars.Caption = "Particulars";
            this.colParticulars.FieldName = "Particulars";
            this.colParticulars.MinWidth = 23;
            this.colParticulars.Name = "colParticulars";
            this.colParticulars.Visible = true;
            this.colParticulars.VisibleIndex = 1;
            this.colParticulars.Width = 233;
            // 
            // colDebit
            // 
            this.colDebit.Caption = "Debit";
            this.colDebit.FieldName = "Debit";
            this.colDebit.MinWidth = 23;
            this.colDebit.Name = "colDebit";
            this.colDebit.Visible = true;
            this.colDebit.VisibleIndex = 2;
            this.colDebit.Width = 152;
            // 
            // colCredit
            // 
            this.colCredit.Caption = "Credit";
            this.colCredit.FieldName = "Credit";
            this.colCredit.MinWidth = 23;
            this.colCredit.Name = "colCredit";
            this.colCredit.Visible = true;
            this.colCredit.VisibleIndex = 3;
            this.colCredit.Width = 152;
            // 
            // repAccountCode
            // 
            this.repAccountCode.AutoHeight = false;
            this.repAccountCode.Name = "repAccountCode";
            this.repAccountCode.NullText = "";
            this.repAccountCode.PopupFilterMode = DevExpress.XtraEditors.PopupFilterMode.Contains;
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
            // grpHeader
            // 
            this.grpHeader.Controls.Add(this.lblReferenceNo);
            this.grpHeader.Controls.Add(this.txtReferenceNo);
            this.grpHeader.Controls.Add(this.lblVoucherDate);
            this.grpHeader.Controls.Add(this.txtVoucherDate);
            this.grpHeader.Controls.Add(this.lblBranch);
            this.grpHeader.Controls.Add(this.cboBranch);
            this.grpHeader.Controls.Add(this.lblRemarks);
            this.grpHeader.Controls.Add(this.txtRemarks);
            this.grpHeader.Dock = System.Windows.Forms.DockStyle.Top;
            this.grpHeader.Location = new System.Drawing.Point(0, 0);
            this.grpHeader.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.grpHeader.Name = "grpHeader";
            this.grpHeader.Size = new System.Drawing.Size(913, 148);
            this.grpHeader.TabIndex = 0;
            this.grpHeader.Text = "Journal Voucher Header";
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
            this.txtReferenceNo.Location = new System.Drawing.Point(140, 33);
            this.txtReferenceNo.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtReferenceNo.Name = "txtReferenceNo";
            this.txtReferenceNo.Properties.ReadOnly = true;
            this.txtReferenceNo.Size = new System.Drawing.Size(152, 22);
            this.txtReferenceNo.TabIndex = 1;
            // 
            // lblVoucherDate
            // 
            this.lblVoucherDate.Location = new System.Drawing.Point(327, 37);
            this.lblVoucherDate.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblVoucherDate.Name = "lblVoucherDate";
            this.lblVoucherDate.Size = new System.Drawing.Size(82, 16);
            this.lblVoucherDate.TabIndex = 2;
            this.lblVoucherDate.Text = "Voucher Date:";
            // 
            // txtVoucherDate
            // 
            this.txtVoucherDate.EditValue = new System.DateTime(2026, 7, 23, 0, 0, 0, 0);
            this.txtVoucherDate.Location = new System.Drawing.Point(443, 33);
            this.txtVoucherDate.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtVoucherDate.Name = "txtVoucherDate";
            this.txtVoucherDate.Size = new System.Drawing.Size(152, 22);
            this.txtVoucherDate.TabIndex = 3;
            // 
            // lblBranch
            // 
            this.lblBranch.Location = new System.Drawing.Point(630, 37);
            this.lblBranch.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblBranch.Name = "lblBranch";
            this.lblBranch.Size = new System.Drawing.Size(44, 16);
            this.lblBranch.TabIndex = 4;
            this.lblBranch.Text = "Branch:";
            // 
            // cboBranch
            // 
            this.cboBranch.Location = new System.Drawing.Point(700, 33);
            this.cboBranch.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.cboBranch.Name = "cboBranch";
            this.cboBranch.Size = new System.Drawing.Size(163, 22);
            this.cboBranch.TabIndex = 5;
            // 
            // lblRemarks
            // 
            this.lblRemarks.Location = new System.Drawing.Point(19, 76);
            this.lblRemarks.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblRemarks.Name = "lblRemarks";
            this.lblRemarks.Size = new System.Drawing.Size(55, 16);
            this.lblRemarks.TabIndex = 6;
            this.lblRemarks.Text = "Remarks:";
            // 
            // txtRemarks
            // 
            this.txtRemarks.Location = new System.Drawing.Point(140, 73);
            this.txtRemarks.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtRemarks.Name = "txtRemarks";
            this.txtRemarks.Size = new System.Drawing.Size(723, 59);
            this.txtRemarks.TabIndex = 7;
            // 
            // tabPosted
            // 
            this.tabPosted.Controls.Add(this.gridControlPostedDetails);
            this.tabPosted.Controls.Add(this.pnlPostedButtons);
            this.tabPosted.Controls.Add(this.gridControlPosted);
            this.tabPosted.Controls.Add(this.pnlPostedFilter);
            this.tabPosted.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.tabPosted.Name = "tabPosted";
            this.tabPosted.Size = new System.Drawing.Size(913, 854);
            this.tabPosted.Text = "Posted Vouchers";
            // 
            // gridControlPostedDetails
            // 
            this.gridControlPostedDetails.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlPostedDetails.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlPostedDetails.Location = new System.Drawing.Point(0, 496);
            this.gridControlPostedDetails.MainView = this.gridViewPostedDetails;
            this.gridControlPostedDetails.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlPostedDetails.Name = "gridControlPostedDetails";
            this.gridControlPostedDetails.Size = new System.Drawing.Size(913, 358);
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
            this.pnlPostedButtons.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlPostedButtons.Location = new System.Drawing.Point(0, 444);
            this.pnlPostedButtons.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.pnlPostedButtons.Name = "pnlPostedButtons";
            this.pnlPostedButtons.Size = new System.Drawing.Size(913, 52);
            this.pnlPostedButtons.TabIndex = 1;
            // 
            // btnViewDetails
            // 
            this.btnViewDetails.Enabled = false;
            this.btnViewDetails.Location = new System.Drawing.Point(14, 10);
            this.btnViewDetails.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnViewDetails.Name = "btnViewDetails";
            this.btnViewDetails.Size = new System.Drawing.Size(128, 32);
            this.btnViewDetails.TabIndex = 0;
            this.btnViewDetails.Text = "View Details";
            this.btnViewDetails.Click += new System.EventHandler(this.BtnViewDetails_Click);
            // 
            // btnCopyToNew
            // 
            this.btnCopyToNew.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(255)))), ((int)(((byte)(244)))), ((int)(((byte)(219)))));
            this.btnCopyToNew.Appearance.Options.UseBackColor = true;
            this.btnCopyToNew.Enabled = false;
            this.btnCopyToNew.Location = new System.Drawing.Point(152, 10);
            this.btnCopyToNew.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnCopyToNew.Name = "btnCopyToNew";
            this.btnCopyToNew.Size = new System.Drawing.Size(163, 32);
            this.btnCopyToNew.TabIndex = 1;
            this.btnCopyToNew.Text = "Copy to New Entry";
            this.btnCopyToNew.Click += new System.EventHandler(this.BtnCopyToNew_Click);
            // 
            // gridControlPosted
            // 
            this.gridControlPosted.Dock = System.Windows.Forms.DockStyle.Top;
            this.gridControlPosted.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlPosted.Location = new System.Drawing.Point(0, 54);
            this.gridControlPosted.MainView = this.gridViewPosted;
            this.gridControlPosted.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlPosted.Name = "gridControlPosted";
            this.gridControlPosted.Size = new System.Drawing.Size(913, 390);
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
            this.pnlPostedFilter.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.pnlPostedFilter.Name = "pnlPostedFilter";
            this.pnlPostedFilter.Size = new System.Drawing.Size(913, 54);
            this.pnlPostedFilter.TabIndex = 3;
            // 
            // lblDateFrom
            // 
            this.lblDateFrom.Location = new System.Drawing.Point(14, 18);
            this.lblDateFrom.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblDateFrom.Name = "lblDateFrom";
            this.lblDateFrom.Size = new System.Drawing.Size(35, 16);
            this.lblDateFrom.TabIndex = 0;
            this.lblDateFrom.Text = "From:";
            // 
            // txtDateFrom
            // 
            this.txtDateFrom.EditValue = new System.DateTime(2026, 7, 23, 0, 0, 0, 0);
            this.txtDateFrom.Location = new System.Drawing.Point(58, 14);
            this.txtDateFrom.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtDateFrom.Name = "txtDateFrom";
            this.txtDateFrom.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtDateFrom.Size = new System.Drawing.Size(128, 22);
            this.txtDateFrom.TabIndex = 1;
            // 
            // lblDateTo
            // 
            this.lblDateTo.Location = new System.Drawing.Point(203, 18);
            this.lblDateTo.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblDateTo.Name = "lblDateTo";
            this.lblDateTo.Size = new System.Drawing.Size(20, 16);
            this.lblDateTo.TabIndex = 2;
            this.lblDateTo.Text = "To:";
            // 
            // txtDateTo
            // 
            this.txtDateTo.EditValue = new System.DateTime(2026, 7, 23, 0, 0, 0, 0);
            this.txtDateTo.Location = new System.Drawing.Point(233, 14);
            this.txtDateTo.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtDateTo.Name = "txtDateTo";
            this.txtDateTo.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtDateTo.Size = new System.Drawing.Size(128, 22);
            this.txtDateTo.TabIndex = 3;
            // 
            // btnRefreshPosted
            // 
            this.btnRefreshPosted.Location = new System.Drawing.Point(378, 11);
            this.btnRefreshPosted.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnRefreshPosted.Name = "btnRefreshPosted";
            this.btnRefreshPosted.Size = new System.Drawing.Size(105, 32);
            this.btnRefreshPosted.TabIndex = 4;
            this.btnRefreshPosted.Text = "Refresh";
            this.btnRefreshPosted.Click += new System.EventHandler(this.BtnRefreshPosted_Click);
            // 
            // ManualJournalVoucherFrm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(915, 884);
            this.Controls.Add(this.tabMain);
            this.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.Name = "ManualJournalVoucherFrm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "Manual Journal Voucher";
            this.Load += new System.EventHandler(this.ManualJournalVoucherFrm_Load);
            ((System.ComponentModel.ISupportInitialize)(this.tabMain)).EndInit();
            this.tabMain.ResumeLayout(false);
            this.tabNew.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.panelControl1)).EndInit();
            this.panelControl1.ResumeLayout(false);
            this.panelControl1.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl2)).EndInit();
            this.panelControl2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.grpLines)).EndInit();
            this.grpLines.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlLines)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewLines)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repAccountCode)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repParticulars)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repDebit)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repCredit)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).EndInit();
            this.grpHeader.ResumeLayout(false);
            this.grpHeader.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtVoucherDate.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtVoucherDate.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranch.Properties)).EndInit();
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
    }
}