namespace SalesInventorySystem.AccountingDevEx
{
    partial class ExpenseManualMultiBranchFrm
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null)) components.Dispose();
            base.Dispose(disposing);
        }

        private DevExpress.XtraTab.XtraTabControl tabMain;
        private DevExpress.XtraTab.XtraTabPage tabNew;
        private DevExpress.XtraTab.XtraTabPage tabPosted;

        private DevExpress.XtraEditors.GroupControl grpHeader;
        private DevExpress.XtraEditors.LabelControl lblReferenceNo;
        private DevExpress.XtraEditors.TextEdit txtReferenceNo;
        private DevExpress.XtraEditors.LabelControl lblExpenseDate;
        private DevExpress.XtraEditors.DateEdit txtExpenseDate;
        private DevExpress.XtraEditors.LabelControl lblDefaultBranch;
        private DevExpress.XtraEditors.LookUpEdit cboDefaultBranch;
        private DevExpress.XtraEditors.LabelControl lblSupplier;
        private DevExpress.XtraEditors.SearchLookUpEdit cboSupplier;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewSupplierPopup;
        private DevExpress.XtraEditors.LabelControl lblInvoiceNo;
        private DevExpress.XtraEditors.TextEdit txtInvoiceNo;
        private DevExpress.XtraEditors.LabelControl lblRemarks;
        private DevExpress.XtraEditors.MemoEdit txtRemarks;
        private DevExpress.XtraEditors.LabelControl lblEditNotice;

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
        private DevExpress.XtraGrid.Views.Grid.GridView repAccountCodeView;
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
        private DevExpress.XtraEditors.CheckEdit chkAllowCrossBranch;
        private DevExpress.XtraEditors.SimpleButton btnPost;
        private DevExpress.XtraEditors.SimpleButton btnClose;

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

        private DevExpress.XtraGrid.GridControl gridControlPostedDetails;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewPostedDetails;

        private void InitializeComponent()
        {
            this.tabMain = new DevExpress.XtraTab.XtraTabControl();
            this.tabNew = new DevExpress.XtraTab.XtraTabPage();
            this.grpLines = new DevExpress.XtraEditors.GroupControl();
            this.panelControl1 = new DevExpress.XtraEditors.PanelControl();
            this.btnAddLine = new DevExpress.XtraEditors.SimpleButton();
            this.chkAllowCrossBranch = new DevExpress.XtraEditors.CheckEdit();
            this.btnPost = new DevExpress.XtraEditors.SimpleButton();
            this.lblBalanceStatus = new DevExpress.XtraEditors.LabelControl();
            this.btnClose = new DevExpress.XtraEditors.SimpleButton();
            this.btnRemoveLine = new DevExpress.XtraEditors.SimpleButton();
            this.lblTotalCredit = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalDebitCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalCreditCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalDebit = new DevExpress.XtraEditors.LabelControl();
            this.gridControlLines = new DevExpress.XtraGrid.GridControl();
            this.gridViewLines = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.colBranchCode = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colAccountCode = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colParticulars = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colDebit = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colCredit = new DevExpress.XtraGrid.Columns.GridColumn();
            this.repBranchCode = new DevExpress.XtraEditors.Repository.RepositoryItemLookUpEdit();
            this.repAccountCode = new DevExpress.XtraEditors.Repository.RepositoryItemSearchLookUpEdit();
            this.repAccountCodeView = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.repParticulars = new DevExpress.XtraEditors.Repository.RepositoryItemTextEdit();
            this.repDebit = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.repCredit = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.grpHeader = new DevExpress.XtraEditors.GroupControl();
            this.lblReferenceNo = new DevExpress.XtraEditors.LabelControl();
            this.txtReferenceNo = new DevExpress.XtraEditors.TextEdit();
            this.lblExpenseDate = new DevExpress.XtraEditors.LabelControl();
            this.txtExpenseDate = new DevExpress.XtraEditors.DateEdit();
            this.lblDefaultBranch = new DevExpress.XtraEditors.LabelControl();
            this.cboDefaultBranch = new DevExpress.XtraEditors.LookUpEdit();
            this.lblSupplier = new DevExpress.XtraEditors.LabelControl();
            this.cboSupplier = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.gridViewSupplierPopup = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.lblInvoiceNo = new DevExpress.XtraEditors.LabelControl();
            this.txtInvoiceNo = new DevExpress.XtraEditors.TextEdit();
            this.lblRemarks = new DevExpress.XtraEditors.LabelControl();
            this.txtRemarks = new DevExpress.XtraEditors.MemoEdit();
            this.lblEditNotice = new DevExpress.XtraEditors.LabelControl();
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
            ((System.ComponentModel.ISupportInitialize)(this.grpLines)).BeginInit();
            this.grpLines.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl1)).BeginInit();
            this.panelControl1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.chkAllowCrossBranch.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlLines)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewLines)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repBranchCode)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repAccountCode)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repAccountCodeView)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repParticulars)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repDebit)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repCredit)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).BeginInit();
            this.grpHeader.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtExpenseDate.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtExpenseDate.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboDefaultBranch.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboSupplier.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewSupplierPopup)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtInvoiceNo.Properties)).BeginInit();
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
            this.tabMain.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.tabMain.Name = "tabMain";
            this.tabMain.SelectedTabPage = this.tabNew;
            this.tabMain.Size = new System.Drawing.Size(1245, 573);
            this.tabMain.TabIndex = 0;
            this.tabMain.TabPages.AddRange(new DevExpress.XtraTab.XtraTabPage[] {
            this.tabNew,
            this.tabPosted});
            this.tabMain.SelectedPageChanged += new DevExpress.XtraTab.TabPageChangedEventHandler(this.TabMain_SelectedPageChanged);
            // 
            // tabNew
            // 
            this.tabNew.Controls.Add(this.grpLines);
            this.tabNew.Controls.Add(this.grpHeader);
            this.tabNew.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.tabNew.Name = "tabNew";
            this.tabNew.Size = new System.Drawing.Size(1243, 548);
            this.tabNew.Text = "Post Expense";
            // 
            // grpLines
            // 
            this.grpLines.Controls.Add(this.panelControl1);
            this.grpLines.Controls.Add(this.gridControlLines);
            this.grpLines.Dock = System.Windows.Forms.DockStyle.Fill;
            this.grpLines.Location = new System.Drawing.Point(0, 152);
            this.grpLines.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.grpLines.Name = "grpLines";
            this.grpLines.Size = new System.Drawing.Size(994, 286);
            this.grpLines.TabIndex = 1;
            this.grpLines.Text = "GL Lines (manual — no mapping)";
            // 
            // panelControl1
            // 
            this.panelControl1.Controls.Add(this.btnAddLine);
            this.panelControl1.Controls.Add(this.chkAllowCrossBranch);
            this.panelControl1.Controls.Add(this.btnPost);
            this.panelControl1.Controls.Add(this.lblBalanceStatus);
            this.panelControl1.Controls.Add(this.btnClose);
            this.panelControl1.Controls.Add(this.btnRemoveLine);
            this.panelControl1.Controls.Add(this.lblTotalCredit);
            this.panelControl1.Controls.Add(this.lblTotalDebitCaption);
            this.panelControl1.Controls.Add(this.lblTotalCreditCaption);
            this.panelControl1.Controls.Add(this.lblTotalDebit);
            this.panelControl1.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.panelControl1.Location = new System.Drawing.Point(2, 219);
            this.panelControl1.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.panelControl1.Name = "panelControl1";
            this.panelControl1.Size = new System.Drawing.Size(990, 65);
            this.panelControl1.TabIndex = 9;
            // 
            // btnAddLine
            // 
            this.btnAddLine.Location = new System.Drawing.Point(21, 4);
            this.btnAddLine.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.btnAddLine.Name = "btnAddLine";
            this.btnAddLine.Size = new System.Drawing.Size(94, 23);
            this.btnAddLine.TabIndex = 1;
            this.btnAddLine.Text = "Add Line";
            this.btnAddLine.Click += new System.EventHandler(this.BtnAddLine_Click);
            // 
            // chkAllowCrossBranch
            // 
            this.chkAllowCrossBranch.Location = new System.Drawing.Point(21, 48);
            this.chkAllowCrossBranch.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.chkAllowCrossBranch.Name = "chkAllowCrossBranch";
            this.chkAllowCrossBranch.Properties.Caption = "Allow Cross-Branch Entry (only overall total needs to balance)";
            this.chkAllowCrossBranch.Size = new System.Drawing.Size(360, 20);
            this.chkAllowCrossBranch.TabIndex = 8;
            this.chkAllowCrossBranch.CheckedChanged += new System.EventHandler(this.ChkAllowCrossBranch_CheckedChanged);
            // 
            // btnPost
            // 
            this.btnPost.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.btnPost.Appearance.Options.UseFont = true;
            this.btnPost.Location = new System.Drawing.Point(781, 39);
            this.btnPost.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.btnPost.Name = "btnPost";
            this.btnPost.Size = new System.Drawing.Size(85, 28);
            this.btnPost.TabIndex = 2;
            this.btnPost.Text = "Post";
            this.btnPost.Click += new System.EventHandler(this.BtnPost_Click);
            // 
            // lblBalanceStatus
            // 
            this.lblBalanceStatus.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblBalanceStatus.Appearance.ForeColor = System.Drawing.Color.Red;
            this.lblBalanceStatus.Appearance.Options.UseFont = true;
            this.lblBalanceStatus.Appearance.Options.UseForeColor = true;
            this.lblBalanceStatus.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblBalanceStatus.Location = new System.Drawing.Point(21, 28);
            this.lblBalanceStatus.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.lblBalanceStatus.Name = "lblBalanceStatus";
            this.lblBalanceStatus.Size = new System.Drawing.Size(600, 15);
            this.lblBalanceStatus.TabIndex = 7;
            // 
            // btnClose
            // 
            this.btnClose.Location = new System.Drawing.Point(871, 39);
            this.btnClose.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.btnClose.Name = "btnClose";
            this.btnClose.Size = new System.Drawing.Size(71, 28);
            this.btnClose.TabIndex = 3;
            this.btnClose.Text = "Close";
            this.btnClose.Click += new System.EventHandler(this.BtnClose_Click);
            // 
            // btnRemoveLine
            // 
            this.btnRemoveLine.Location = new System.Drawing.Point(122, 4);
            this.btnRemoveLine.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.btnRemoveLine.Name = "btnRemoveLine";
            this.btnRemoveLine.Size = new System.Drawing.Size(94, 23);
            this.btnRemoveLine.TabIndex = 2;
            this.btnRemoveLine.Text = "Remove Line";
            this.btnRemoveLine.Click += new System.EventHandler(this.BtnRemoveLine_Click);
            // 
            // lblTotalCredit
            // 
            this.lblTotalCredit.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblTotalCredit.Appearance.Options.UseFont = true;
            this.lblTotalCredit.Location = new System.Drawing.Point(710, 9);
            this.lblTotalCredit.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.lblTotalCredit.Name = "lblTotalCredit";
            this.lblTotalCredit.Size = new System.Drawing.Size(28, 14);
            this.lblTotalCredit.TabIndex = 6;
            this.lblTotalCredit.Text = "0.00";
            // 
            // lblTotalDebitCaption
            // 
            this.lblTotalDebitCaption.Location = new System.Drawing.Point(487, 9);
            this.lblTotalDebitCaption.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.lblTotalDebitCaption.Name = "lblTotalDebitCaption";
            this.lblTotalDebitCaption.Size = new System.Drawing.Size(56, 13);
            this.lblTotalDebitCaption.TabIndex = 3;
            this.lblTotalDebitCaption.Text = "Total Debit:";
            // 
            // lblTotalCreditCaption
            // 
            this.lblTotalCreditCaption.Location = new System.Drawing.Point(641, 9);
            this.lblTotalCreditCaption.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.lblTotalCreditCaption.Name = "lblTotalCreditCaption";
            this.lblTotalCreditCaption.Size = new System.Drawing.Size(60, 13);
            this.lblTotalCreditCaption.TabIndex = 5;
            this.lblTotalCreditCaption.Text = "Total Credit:";
            // 
            // lblTotalDebit
            // 
            this.lblTotalDebit.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblTotalDebit.Appearance.Options.UseFont = true;
            this.lblTotalDebit.Location = new System.Drawing.Point(555, 9);
            this.lblTotalDebit.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.lblTotalDebit.Name = "lblTotalDebit";
            this.lblTotalDebit.Size = new System.Drawing.Size(28, 14);
            this.lblTotalDebit.TabIndex = 4;
            this.lblTotalDebit.Text = "0.00";
            // 
            // gridControlLines
            // 
            this.gridControlLines.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlLines.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.gridControlLines.Location = new System.Drawing.Point(2, 23);
            this.gridControlLines.MainView = this.gridViewLines;
            this.gridControlLines.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.gridControlLines.Name = "gridControlLines";
            this.gridControlLines.RepositoryItems.AddRange(new DevExpress.XtraEditors.Repository.RepositoryItem[] {
            this.repBranchCode,
            this.repAccountCode,
            this.repParticulars,
            this.repDebit,
            this.repCredit});
            this.gridControlLines.Size = new System.Drawing.Size(990, 261);
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
            this.gridViewLines.DetailHeight = 284;
            this.gridViewLines.GridControl = this.gridControlLines;
            this.gridViewLines.Name = "gridViewLines";
            this.gridViewLines.OptionsCustomization.AllowSort = false;
            this.gridViewLines.OptionsEditForm.PopupEditFormWidth = 686;
            this.gridViewLines.OptionsView.ShowFooter = true;
            this.gridViewLines.OptionsView.ShowGroupPanel = false;
            this.gridViewLines.RowCellStyle += new DevExpress.XtraGrid.Views.Grid.RowCellStyleEventHandler(this.GridViewLines_RowCellStyle);
            this.gridViewLines.CustomRowCellEdit += new DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventHandler(this.GridViewLines_CustomRowCellEdit);
            this.gridViewLines.CellValueChanged += new DevExpress.XtraGrid.Views.Base.CellValueChangedEventHandler(this.GridViewLines_CellValueChanged);
            // 
            // colBranchCode
            // 
            this.colBranchCode.Caption = "Branch";
            this.colBranchCode.FieldName = "BranchCode";
            this.colBranchCode.MinWidth = 17;
            this.colBranchCode.Name = "colBranchCode";
            this.colBranchCode.Visible = true;
            this.colBranchCode.VisibleIndex = 0;
            this.colBranchCode.Width = 129;
            // 
            // colAccountCode
            // 
            this.colAccountCode.Caption = "Account Code";
            this.colAccountCode.FieldName = "AccountCode";
            this.colAccountCode.MinWidth = 17;
            this.colAccountCode.Name = "colAccountCode";
            this.colAccountCode.Visible = true;
            this.colAccountCode.VisibleIndex = 1;
            this.colAccountCode.Width = 257;
            // 
            // colParticulars
            // 
            this.colParticulars.Caption = "Particulars";
            this.colParticulars.FieldName = "Particulars";
            this.colParticulars.MinWidth = 17;
            this.colParticulars.Name = "colParticulars";
            this.colParticulars.Visible = true;
            this.colParticulars.VisibleIndex = 2;
            this.colParticulars.Width = 189;
            // 
            // colDebit
            // 
            this.colDebit.Caption = "Debit";
            this.colDebit.FieldName = "Debit";
            this.colDebit.MinWidth = 17;
            this.colDebit.Name = "colDebit";
            this.colDebit.Summary.AddRange(new DevExpress.XtraGrid.GridSummaryItem[] {
            new DevExpress.XtraGrid.GridColumnSummaryItem(DevExpress.Data.SummaryItemType.Sum, "Debit", "{0:n2}")});
            this.colDebit.Visible = true;
            this.colDebit.VisibleIndex = 3;
            this.colDebit.Width = 120;
            // 
            // colCredit
            // 
            this.colCredit.Caption = "Credit";
            this.colCredit.FieldName = "Credit";
            this.colCredit.MinWidth = 17;
            this.colCredit.Name = "colCredit";
            this.colCredit.Summary.AddRange(new DevExpress.XtraGrid.GridSummaryItem[] {
            new DevExpress.XtraGrid.GridColumnSummaryItem(DevExpress.Data.SummaryItemType.Sum, "Credit", "{0:n2}")});
            this.colCredit.Visible = true;
            this.colCredit.VisibleIndex = 4;
            this.colCredit.Width = 120;
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
            this.repAccountCode.PopupView = this.repAccountCodeView;
            // 
            // repAccountCodeView
            // 
            this.repAccountCodeView.DetailHeight = 284;
            this.repAccountCodeView.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.repAccountCodeView.Name = "repAccountCodeView";
            this.repAccountCodeView.OptionsEditForm.PopupEditFormWidth = 686;
            this.repAccountCodeView.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.repAccountCodeView.OptionsView.ShowGroupPanel = false;
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
            this.grpHeader.Controls.Add(this.lblExpenseDate);
            this.grpHeader.Controls.Add(this.txtExpenseDate);
            this.grpHeader.Controls.Add(this.lblDefaultBranch);
            this.grpHeader.Controls.Add(this.cboDefaultBranch);
            this.grpHeader.Controls.Add(this.lblSupplier);
            this.grpHeader.Controls.Add(this.cboSupplier);
            this.grpHeader.Controls.Add(this.lblInvoiceNo);
            this.grpHeader.Controls.Add(this.txtInvoiceNo);
            this.grpHeader.Controls.Add(this.lblRemarks);
            this.grpHeader.Controls.Add(this.txtRemarks);
            this.grpHeader.Controls.Add(this.lblEditNotice);
            this.grpHeader.Dock = System.Windows.Forms.DockStyle.Top;
            this.grpHeader.Location = new System.Drawing.Point(0, 0);
            this.grpHeader.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.grpHeader.Name = "grpHeader";
            this.grpHeader.Size = new System.Drawing.Size(994, 190);
            this.grpHeader.TabIndex = 0;
            this.grpHeader.Text = "Expense Header (Manual, No Mapping, Multi-Branch)";
            // 
            // lblReferenceNo
            // 
            this.lblReferenceNo.Location = new System.Drawing.Point(14, 48);
            this.lblReferenceNo.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.lblReferenceNo.Name = "lblReferenceNo";
            this.lblReferenceNo.Size = new System.Drawing.Size(74, 13);
            this.lblReferenceNo.TabIndex = 0;
            this.lblReferenceNo.Text = "Reference No.:";
            // 
            // txtReferenceNo
            // 
            this.txtReferenceNo.Location = new System.Drawing.Point(129, 46);
            this.txtReferenceNo.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.txtReferenceNo.Name = "txtReferenceNo";
            this.txtReferenceNo.Properties.ReadOnly = true;
            this.txtReferenceNo.Size = new System.Drawing.Size(129, 20);
            this.txtReferenceNo.TabIndex = 1;
            // 
            // lblExpenseDate
            // 
            this.lblExpenseDate.Location = new System.Drawing.Point(309, 48);
            this.lblExpenseDate.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.lblExpenseDate.Name = "lblExpenseDate";
            this.lblExpenseDate.Size = new System.Drawing.Size(71, 13);
            this.lblExpenseDate.TabIndex = 2;
            this.lblExpenseDate.Text = "Expense Date:";
            // 
            // txtExpenseDate
            // 
            this.txtExpenseDate.EditValue = new System.DateTime(2026, 7, 23, 0, 0, 0, 0);
            this.txtExpenseDate.Location = new System.Drawing.Point(423, 46);
            this.txtExpenseDate.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.txtExpenseDate.Name = "txtExpenseDate";
            this.txtExpenseDate.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtExpenseDate.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton()});
            this.txtExpenseDate.Size = new System.Drawing.Size(129, 20);
            this.txtExpenseDate.TabIndex = 3;
            // 
            // lblDefaultBranch
            // 
            this.lblDefaultBranch.Location = new System.Drawing.Point(574, 48);
            this.lblDefaultBranch.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.lblDefaultBranch.Name = "lblDefaultBranch";
            this.lblDefaultBranch.Size = new System.Drawing.Size(75, 13);
            this.lblDefaultBranch.TabIndex = 4;
            this.lblDefaultBranch.Text = "Default Branch:";
            this.lblDefaultBranch.Visible = false;
            // 
            // cboDefaultBranch
            // 
            this.cboDefaultBranch.Location = new System.Drawing.Point(689, 46);
            this.cboDefaultBranch.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.cboDefaultBranch.Name = "cboDefaultBranch";
            this.cboDefaultBranch.Size = new System.Drawing.Size(137, 20);
            this.cboDefaultBranch.TabIndex = 5;
            this.cboDefaultBranch.Visible = false;
            // 
            // lblSupplier
            // 
            this.lblSupplier.Location = new System.Drawing.Point(14, 85);
            this.lblSupplier.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.lblSupplier.Name = "lblSupplier";
            this.lblSupplier.Size = new System.Drawing.Size(86, 13);
            this.lblSupplier.TabIndex = 6;
            this.lblSupplier.Text = "Vendor / Supplier:";
            // 
            // cboSupplier
            // 
            this.cboSupplier.Location = new System.Drawing.Point(129, 83);
            this.cboSupplier.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.cboSupplier.Name = "cboSupplier";
            this.cboSupplier.Properties.PopupView = this.gridViewSupplierPopup;
            this.cboSupplier.Size = new System.Drawing.Size(423, 20);
            this.cboSupplier.TabIndex = 7;
            // 
            // gridViewSupplierPopup
            // 
            this.gridViewSupplierPopup.DetailHeight = 284;
            this.gridViewSupplierPopup.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.gridViewSupplierPopup.Name = "gridViewSupplierPopup";
            this.gridViewSupplierPopup.OptionsEditForm.PopupEditFormWidth = 686;
            this.gridViewSupplierPopup.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.gridViewSupplierPopup.OptionsView.ShowGroupPanel = false;
            // 
            // lblInvoiceNo
            // 
            this.lblInvoiceNo.Location = new System.Drawing.Point(574, 85);
            this.lblInvoiceNo.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.lblInvoiceNo.Name = "lblInvoiceNo";
            this.lblInvoiceNo.Size = new System.Drawing.Size(59, 13);
            this.lblInvoiceNo.TabIndex = 8;
            this.lblInvoiceNo.Text = "Invoice No.:";
            // 
            // txtInvoiceNo
            // 
            this.txtInvoiceNo.Location = new System.Drawing.Point(689, 83);
            this.txtInvoiceNo.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.txtInvoiceNo.Name = "txtInvoiceNo";
            this.txtInvoiceNo.Size = new System.Drawing.Size(137, 20);
            this.txtInvoiceNo.TabIndex = 9;
            // 
            // lblRemarks
            // 
            this.lblRemarks.Location = new System.Drawing.Point(14, 124);
            this.lblRemarks.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.lblRemarks.Name = "lblRemarks";
            this.lblRemarks.Size = new System.Drawing.Size(45, 13);
            this.lblRemarks.TabIndex = 10;
            this.lblRemarks.Text = "Remarks:";
            // 
            // txtRemarks
            // 
            this.txtRemarks.Location = new System.Drawing.Point(129, 121);
            this.txtRemarks.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.txtRemarks.Name = "txtRemarks";
            this.txtRemarks.Size = new System.Drawing.Size(698, 37);
            this.txtRemarks.TabIndex = 11;
            // 
            // lblEditNotice
            // 
            this.lblEditNotice.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblEditNotice.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(180)))), ((int)(((byte)(120)))), ((int)(((byte)(0)))));
            this.lblEditNotice.Appearance.Options.UseFont = true;
            this.lblEditNotice.Appearance.Options.UseForeColor = true;
            this.lblEditNotice.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblEditNotice.Location = new System.Drawing.Point(14, 171);
            this.lblEditNotice.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.lblEditNotice.Name = "lblEditNotice";
            this.lblEditNotice.Size = new System.Drawing.Size(813, 15);
            this.lblEditNotice.TabIndex = 12;
            this.lblEditNotice.Visible = false;
            // 
            // tabPosted
            // 
            this.tabPosted.Controls.Add(this.gridControlPostedDetails);
            this.tabPosted.Controls.Add(this.pnlPostedButtons);
            this.tabPosted.Controls.Add(this.gridControlPosted);
            this.tabPosted.Controls.Add(this.pnlPostedFilter);
            this.tabPosted.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.tabPosted.Name = "tabPosted";
            this.tabPosted.Size = new System.Drawing.Size(1243, 548);
            this.tabPosted.Text = "Posted Expenses";
            // 
            // gridControlPostedDetails
            // 
            this.gridControlPostedDetails.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlPostedDetails.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.gridControlPostedDetails.Location = new System.Drawing.Point(0, 238);
            this.gridControlPostedDetails.MainView = this.gridViewPostedDetails;
            this.gridControlPostedDetails.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.gridControlPostedDetails.Name = "gridControlPostedDetails";
            this.gridControlPostedDetails.Size = new System.Drawing.Size(994, 200);
            this.gridControlPostedDetails.TabIndex = 0;
            this.gridControlPostedDetails.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewPostedDetails});
            // 
            // gridViewPostedDetails
            // 
            this.gridViewPostedDetails.DetailHeight = 284;
            this.gridViewPostedDetails.GridControl = this.gridControlPostedDetails;
            this.gridViewPostedDetails.Name = "gridViewPostedDetails";
            this.gridViewPostedDetails.OptionsBehavior.Editable = false;
            this.gridViewPostedDetails.OptionsCustomization.AllowSort = false;
            this.gridViewPostedDetails.OptionsEditForm.PopupEditFormWidth = 686;
            this.gridViewPostedDetails.OptionsView.ShowGroupPanel = false;
            // 
            // pnlPostedButtons
            // 
            this.pnlPostedButtons.Controls.Add(this.btnViewDetails);
            this.pnlPostedButtons.Controls.Add(this.btnCopyToNew);
            this.pnlPostedButtons.Controls.Add(this.btnEditVoucher);
            this.pnlPostedButtons.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlPostedButtons.Location = new System.Drawing.Point(0, 219);
            this.pnlPostedButtons.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.pnlPostedButtons.Name = "pnlPostedButtons";
            this.pnlPostedButtons.Size = new System.Drawing.Size(994, 24);
            this.pnlPostedButtons.TabIndex = 1;
            // 
            // btnViewDetails
            // 
            this.btnViewDetails.Enabled = false;
            this.btnViewDetails.Location = new System.Drawing.Point(10, 7);
            this.btnViewDetails.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.btnViewDetails.Name = "btnViewDetails";
            this.btnViewDetails.Size = new System.Drawing.Size(103, 23);
            this.btnViewDetails.TabIndex = 0;
            this.btnViewDetails.Text = "View Details";
            this.btnViewDetails.Click += new System.EventHandler(this.BtnViewDetails_Click);
            // 
            // btnCopyToNew
            // 
            this.btnCopyToNew.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(255)))), ((int)(((byte)(244)))), ((int)(((byte)(219)))));
            this.btnCopyToNew.Appearance.Options.UseBackColor = true;
            this.btnCopyToNew.Enabled = false;
            this.btnCopyToNew.Location = new System.Drawing.Point(120, 7);
            this.btnCopyToNew.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.btnCopyToNew.Name = "btnCopyToNew";
            this.btnCopyToNew.Size = new System.Drawing.Size(129, 23);
            this.btnCopyToNew.TabIndex = 1;
            this.btnCopyToNew.Text = "Copy to New Entry";
            this.btnCopyToNew.Click += new System.EventHandler(this.BtnCopyToNew_Click);
            // 
            // btnEditVoucher
            // 
            this.btnEditVoucher.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(220)))), ((int)(((byte)(235)))), ((int)(((byte)(255)))));
            this.btnEditVoucher.Appearance.Options.UseBackColor = true;
            this.btnEditVoucher.Enabled = false;
            this.btnEditVoucher.Location = new System.Drawing.Point(255, 7);
            this.btnEditVoucher.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.btnEditVoucher.Name = "btnEditVoucher";
            this.btnEditVoucher.Size = new System.Drawing.Size(94, 23);
            this.btnEditVoucher.TabIndex = 2;
            this.btnEditVoucher.Text = "Edit";
            this.btnEditVoucher.Click += new System.EventHandler(this.BtnEditVoucher_Click);
            // 
            // gridControlPosted
            // 
            this.gridControlPosted.Dock = System.Windows.Forms.DockStyle.Top;
            this.gridControlPosted.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.gridControlPosted.Location = new System.Drawing.Point(0, 38);
            this.gridControlPosted.MainView = this.gridViewPosted;
            this.gridControlPosted.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.gridControlPosted.Name = "gridControlPosted";
            this.gridControlPosted.Size = new System.Drawing.Size(994, 227);
            this.gridControlPosted.TabIndex = 2;
            this.gridControlPosted.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewPosted});
            // 
            // gridViewPosted
            // 
            this.gridViewPosted.DetailHeight = 284;
            this.gridViewPosted.GridControl = this.gridControlPosted;
            this.gridViewPosted.Name = "gridViewPosted";
            this.gridViewPosted.OptionsBehavior.Editable = false;
            this.gridViewPosted.OptionsEditForm.PopupEditFormWidth = 686;
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
            this.pnlPostedFilter.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.pnlPostedFilter.Name = "pnlPostedFilter";
            this.pnlPostedFilter.Size = new System.Drawing.Size(994, 47);
            this.pnlPostedFilter.TabIndex = 3;
            // 
            // lblDateFrom
            // 
            this.lblDateFrom.Location = new System.Drawing.Point(10, 17);
            this.lblDateFrom.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.lblDateFrom.Name = "lblDateFrom";
            this.lblDateFrom.Size = new System.Drawing.Size(28, 13);
            this.lblDateFrom.TabIndex = 0;
            this.lblDateFrom.Text = "From:";
            // 
            // txtDateFrom
            // 
            this.txtDateFrom.EditValue = new System.DateTime(2026, 7, 23, 0, 0, 0, 0);
            this.txtDateFrom.Location = new System.Drawing.Point(50, 15);
            this.txtDateFrom.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.txtDateFrom.Name = "txtDateFrom";
            this.txtDateFrom.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtDateFrom.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton()});
            this.txtDateFrom.Size = new System.Drawing.Size(103, 20);
            this.txtDateFrom.TabIndex = 1;
            // 
            // lblDateTo
            // 
            this.lblDateTo.Location = new System.Drawing.Point(163, 19);
            this.lblDateTo.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.lblDateTo.Name = "lblDateTo";
            this.lblDateTo.Size = new System.Drawing.Size(16, 13);
            this.lblDateTo.TabIndex = 2;
            this.lblDateTo.Text = "To:";
            // 
            // txtDateTo
            // 
            this.txtDateTo.EditValue = new System.DateTime(2026, 7, 23, 0, 0, 0, 0);
            this.txtDateTo.Location = new System.Drawing.Point(183, 15);
            this.txtDateTo.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.txtDateTo.Name = "txtDateTo";
            this.txtDateTo.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtDateTo.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton()});
            this.txtDateTo.Size = new System.Drawing.Size(103, 20);
            this.txtDateTo.TabIndex = 3;
            // 
            // btnRefreshPosted
            // 
            this.btnRefreshPosted.Location = new System.Drawing.Point(297, 11);
            this.btnRefreshPosted.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.btnRefreshPosted.Name = "btnRefreshPosted";
            this.btnRefreshPosted.Size = new System.Drawing.Size(86, 24);
            this.btnRefreshPosted.TabIndex = 4;
            this.btnRefreshPosted.Text = "Refresh";
            this.btnRefreshPosted.Click += new System.EventHandler(this.BtnRefreshPosted_Click);
            // 
            // ExpenseManualMultiBranchFrm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.Controls.Add(this.tabMain);
            this.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.Name = "ExpenseManualMultiBranchFrm";
            this.Size = new System.Drawing.Size(1245, 573);
            this.Load += new System.EventHandler(this.ExpenseManualMultiBranchFrm_Load);
            ((System.ComponentModel.ISupportInitialize)(this.tabMain)).EndInit();
            this.tabMain.ResumeLayout(false);
            this.tabNew.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.grpLines)).EndInit();
            this.grpLines.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.panelControl1)).EndInit();
            this.panelControl1.ResumeLayout(false);
            this.panelControl1.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.chkAllowCrossBranch.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlLines)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewLines)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repBranchCode)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repAccountCode)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repAccountCodeView)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repParticulars)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repDebit)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repCredit)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).EndInit();
            this.grpHeader.ResumeLayout(false);
            this.grpHeader.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtExpenseDate.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtExpenseDate.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboDefaultBranch.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboSupplier.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewSupplierPopup)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtInvoiceNo.Properties)).EndInit();
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
    }
}