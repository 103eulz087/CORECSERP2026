namespace SalesInventorySystem.AccountingDevEx
{
    partial class AddExpenseDevExFrm
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null)) components.Dispose();
            base.Dispose(disposing);
        }

        // ── Tabs ─────────────────────────────────────────────────
        private DevExpress.XtraTab.XtraTabControl tabMain;
        private DevExpress.XtraTab.XtraTabPage tabEntry;
        private DevExpress.XtraTab.XtraTabPage tabPosted;

        // ── tabEntry: Post Expense ────────────────────────────────
        private DevExpress.XtraEditors.GroupControl grpHeader;
        private DevExpress.XtraEditors.LabelControl lblReferenceNo;
        private DevExpress.XtraEditors.TextEdit txtReferenceNo;
        private DevExpress.XtraEditors.LabelControl lblTicketNo;
        private DevExpress.XtraEditors.TextEdit txtTicketNo;
        private DevExpress.XtraEditors.LabelControl lblBranch;
        private DevExpress.XtraEditors.SearchLookUpEdit cboBranch;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewBranchPopup;
        private DevExpress.XtraEditors.LabelControl lblSupplier;
        private DevExpress.XtraEditors.SearchLookUpEdit cboSupplier;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewSupplierPopup;
        private DevExpress.XtraEditors.LabelControl lblInvoiceNo;
        private DevExpress.XtraEditors.TextEdit txtInvoiceNo;
        private DevExpress.XtraEditors.LabelControl lblExpenseDate;
        private DevExpress.XtraEditors.DateEdit txtExpenseDate;
        private DevExpress.XtraEditors.CheckEdit chkLinkToPO;
        private DevExpress.XtraEditors.SearchLookUpEdit cboPO;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewPOPopup;
        private DevExpress.XtraEditors.LabelControl lblRemarks;
        private DevExpress.XtraEditors.MemoEdit txtRemarks;
        private DevExpress.XtraEditors.LabelControl lblEditNotice;

        private DevExpress.XtraEditors.GroupControl grpLines;
        private DevExpress.XtraGrid.GridControl gridControlLines;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewLines;
        private DevExpress.XtraGrid.Columns.GridColumn colAccountCode;
        private DevExpress.XtraGrid.Columns.GridColumn colAccountTitle;
        private DevExpress.XtraGrid.Columns.GridColumn colDebit;
        private DevExpress.XtraGrid.Columns.GridColumn colCredit;
        private DevExpress.XtraGrid.Columns.GridColumn colParticulars;
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
        private DevExpress.XtraEditors.SimpleButton btnSubmit;
        private DevExpress.XtraEditors.SimpleButton btnNewEntry;

        // ── tabPosted: Posted Expenses ─────────────────────────────
        private DevExpress.XtraEditors.PanelControl pnlPostedFilter;
        private DevExpress.XtraEditors.LabelControl lblDateFrom;
        private DevExpress.XtraEditors.DateEdit txtDateFrom;
        private DevExpress.XtraEditors.LabelControl lblDateTo;
        private DevExpress.XtraEditors.DateEdit txtDateTo;
        private DevExpress.XtraEditors.LabelControl lblFilterBranch;
        private DevExpress.XtraEditors.CheckEdit chkAllBranches;
        private DevExpress.XtraEditors.LookUpEdit cboFilterBranch;
        private DevExpress.XtraEditors.SimpleButton btnRefreshPosted;

        private DevExpress.XtraGrid.GridControl gridControlPosted;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewPosted;

        private DevExpress.XtraEditors.PanelControl pnlPostedButtons;
        private DevExpress.XtraEditors.SimpleButton btnViewDetails;
        private DevExpress.XtraEditors.SimpleButton btnCopyToNew;
        private DevExpress.XtraEditors.SimpleButton btnEdit;

        private DevExpress.XtraGrid.GridControl gridControlPostedDetails;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewPostedDetails;

        private void InitializeComponent()
        {
            this.tabMain = new DevExpress.XtraTab.XtraTabControl();
            this.tabEntry = new DevExpress.XtraTab.XtraTabPage();
            this.grpLines = new DevExpress.XtraEditors.GroupControl();
            this.gridControlLines = new DevExpress.XtraGrid.GridControl();
            this.gridViewLines = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.colAccountCode = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colAccountTitle = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colParticulars = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colDebit = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colCredit = new DevExpress.XtraGrid.Columns.GridColumn();
            this.repAccountCode = new DevExpress.XtraEditors.Repository.RepositoryItemSearchLookUpEdit();
            this.repAccountCodeView = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.repDebit = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.repCredit = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.repParticulars = new DevExpress.XtraEditors.Repository.RepositoryItemTextEdit();
            this.lblBalanceStatus = new DevExpress.XtraEditors.LabelControl();
            this.panelControl2 = new DevExpress.XtraEditors.PanelControl();
            this.btnAddLine = new DevExpress.XtraEditors.SimpleButton();
            this.lblTotalDebitCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalDebit = new DevExpress.XtraEditors.LabelControl();
            this.btnRemoveLine = new DevExpress.XtraEditors.SimpleButton();
            this.lblTotalCreditCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalCredit = new DevExpress.XtraEditors.LabelControl();
            this.panelControl1 = new DevExpress.XtraEditors.PanelControl();
            this.btnSubmit = new DevExpress.XtraEditors.SimpleButton();
            this.grpHeader = new DevExpress.XtraEditors.GroupControl();
            this.labelControl1 = new DevExpress.XtraEditors.LabelControl();
            this.lblReferenceNo = new DevExpress.XtraEditors.LabelControl();
            this.txtReferenceNo = new DevExpress.XtraEditors.TextEdit();
            this.lblTicketNo = new DevExpress.XtraEditors.LabelControl();
            this.txtTicketNo = new DevExpress.XtraEditors.TextEdit();
            this.lblBranch = new DevExpress.XtraEditors.LabelControl();
            this.cboBranch = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.gridViewBranchPopup = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.lblSupplier = new DevExpress.XtraEditors.LabelControl();
            this.cboSupplier = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.gridViewSupplierPopup = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.lblInvoiceNo = new DevExpress.XtraEditors.LabelControl();
            this.txtInvoiceNo = new DevExpress.XtraEditors.TextEdit();
            this.lblExpenseDate = new DevExpress.XtraEditors.LabelControl();
            this.txtExpenseDate = new DevExpress.XtraEditors.DateEdit();
            this.chkLinkToPO = new DevExpress.XtraEditors.CheckEdit();
            this.cboPO = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.gridViewPOPopup = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.lblRemarks = new DevExpress.XtraEditors.LabelControl();
            this.txtRemarks = new DevExpress.XtraEditors.MemoEdit();
            this.lblEditNotice = new DevExpress.XtraEditors.LabelControl();
            this.tabPosted = new DevExpress.XtraTab.XtraTabPage();
            this.gridControlPostedDetails = new DevExpress.XtraGrid.GridControl();
            this.gridViewPostedDetails = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.pnlPostedButtons = new DevExpress.XtraEditors.PanelControl();
            this.btnViewDetails = new DevExpress.XtraEditors.SimpleButton();
            this.btnCopyToNew = new DevExpress.XtraEditors.SimpleButton();
            this.btnEdit = new DevExpress.XtraEditors.SimpleButton();
            this.gridControlPosted = new DevExpress.XtraGrid.GridControl();
            this.gridViewPosted = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.pnlPostedFilter = new DevExpress.XtraEditors.PanelControl();
            this.lblDateFrom = new DevExpress.XtraEditors.LabelControl();
            this.txtDateFrom = new DevExpress.XtraEditors.DateEdit();
            this.lblDateTo = new DevExpress.XtraEditors.LabelControl();
            this.txtDateTo = new DevExpress.XtraEditors.DateEdit();
            this.lblFilterBranch = new DevExpress.XtraEditors.LabelControl();
            this.cboFilterBranch = new DevExpress.XtraEditors.LookUpEdit();
            this.chkAllBranches = new DevExpress.XtraEditors.CheckEdit();
            this.btnRefreshPosted = new DevExpress.XtraEditors.SimpleButton();
            this.btnNewEntry = new DevExpress.XtraEditors.SimpleButton();
            ((System.ComponentModel.ISupportInitialize)(this.tabMain)).BeginInit();
            this.tabMain.SuspendLayout();
            this.tabEntry.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.grpLines)).BeginInit();
            this.grpLines.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlLines)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewLines)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repAccountCode)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repAccountCodeView)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repDebit)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repCredit)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repParticulars)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl2)).BeginInit();
            this.panelControl2.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl1)).BeginInit();
            this.panelControl1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).BeginInit();
            this.grpHeader.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtTicketNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranch.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewBranchPopup)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboSupplier.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewSupplierPopup)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtInvoiceNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtExpenseDate.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtExpenseDate.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkLinkToPO.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboPO.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewPOPopup)).BeginInit();
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
            ((System.ComponentModel.ISupportInitialize)(this.cboFilterBranch.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkAllBranches.Properties)).BeginInit();
            this.SuspendLayout();
            // 
            // tabMain
            // 
            this.tabMain.Dock = System.Windows.Forms.DockStyle.Fill;
            this.tabMain.Location = new System.Drawing.Point(0, 0);
            this.tabMain.Name = "tabMain";
            this.tabMain.SelectedTabPage = this.tabEntry;
            this.tabMain.Size = new System.Drawing.Size(938, 790);
            this.tabMain.TabIndex = 0;
            this.tabMain.TabPages.AddRange(new DevExpress.XtraTab.XtraTabPage[] {
            this.tabEntry,
            this.tabPosted});
            this.tabMain.SelectedPageChanged += new DevExpress.XtraTab.TabPageChangedEventHandler(this.TabMain_SelectedPageChanged);
            // 
            // tabEntry
            // 
            this.tabEntry.Controls.Add(this.grpLines);
            this.tabEntry.Controls.Add(this.panelControl2);
            this.tabEntry.Controls.Add(this.panelControl1);
            this.tabEntry.Controls.Add(this.grpHeader);
            this.tabEntry.Name = "tabEntry";
            this.tabEntry.Size = new System.Drawing.Size(936, 760);
            this.tabEntry.Text = "Post Expense";
            // 
            // grpLines
            // 
            this.grpLines.Controls.Add(this.gridControlLines);
            this.grpLines.Controls.Add(this.lblBalanceStatus);
            this.grpLines.Dock = System.Windows.Forms.DockStyle.Fill;
            this.grpLines.Location = new System.Drawing.Point(0, 322);
            this.grpLines.Name = "grpLines";
            this.grpLines.Size = new System.Drawing.Size(936, 339);
            this.grpLines.TabIndex = 0;
            this.grpLines.Text = "GL Entries";
            // 
            // gridControlLines
            // 
            this.gridControlLines.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlLines.Location = new System.Drawing.Point(2, 28);
            this.gridControlLines.MainView = this.gridViewLines;
            this.gridControlLines.Name = "gridControlLines";
            this.gridControlLines.RepositoryItems.AddRange(new DevExpress.XtraEditors.Repository.RepositoryItem[] {
            this.repAccountCode,
            this.repDebit,
            this.repCredit,
            this.repParticulars});
            this.gridControlLines.Size = new System.Drawing.Size(932, 309);
            this.gridControlLines.TabIndex = 0;
            this.gridControlLines.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewLines});
            // 
            // gridViewLines
            // 
            this.gridViewLines.Columns.AddRange(new DevExpress.XtraGrid.Columns.GridColumn[] {
            this.colAccountCode,
            this.colAccountTitle,
            this.colParticulars,
            this.colDebit,
            this.colCredit});
            this.gridViewLines.GridControl = this.gridControlLines;
            this.gridViewLines.Name = "gridViewLines";
            this.gridViewLines.OptionsCustomization.AllowSort = false;
            this.gridViewLines.OptionsView.ShowFooter = true;
            this.gridViewLines.OptionsView.ShowGroupPanel = false;
            this.gridViewLines.RowCellStyle += new DevExpress.XtraGrid.Views.Grid.RowCellStyleEventHandler(this.GridViewLines_RowCellStyle);
            this.gridViewLines.CustomRowCellEdit += new DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventHandler(this.GridViewLines_CustomRowCellEdit);
            this.gridViewLines.ShowingEditor += new System.ComponentModel.CancelEventHandler(this.GridViewLines_ShowingEditor);
            this.gridViewLines.CellValueChanged += new DevExpress.XtraGrid.Views.Base.CellValueChangedEventHandler(this.GridViewLines_CellValueChanged);
            // 
            // colAccountCode
            // 
            this.colAccountCode.Caption = "Account Code";
            this.colAccountCode.FieldName = "AccountCode";
            this.colAccountCode.Name = "colAccountCode";
            this.colAccountCode.Visible = true;
            this.colAccountCode.VisibleIndex = 0;
            this.colAccountCode.Width = 260;
            // 
            // colAccountTitle
            // 
            this.colAccountTitle.Caption = "Account Title";
            this.colAccountTitle.FieldName = "AccountTitle";
            this.colAccountTitle.Name = "colAccountTitle";
            this.colAccountTitle.OptionsColumn.AllowEdit = false;
            this.colAccountTitle.Visible = true;
            this.colAccountTitle.VisibleIndex = 1;
            this.colAccountTitle.Width = 220;
            // 
            // colParticulars
            // 
            this.colParticulars.Caption = "Particulars";
            this.colParticulars.FieldName = "Particulars";
            this.colParticulars.Name = "colParticulars";
            this.colParticulars.Visible = true;
            this.colParticulars.VisibleIndex = 2;
            this.colParticulars.Width = 220;
            // 
            // colDebit
            // 
            this.colDebit.Caption = "Debit";
            this.colDebit.FieldName = "Debit";
            this.colDebit.Name = "colDebit";
            this.colDebit.Summary.AddRange(new DevExpress.XtraGrid.GridSummaryItem[] {
            new DevExpress.XtraGrid.GridColumnSummaryItem(DevExpress.Data.SummaryItemType.Sum, "Debit", "{0:n2}")});
            this.colDebit.Visible = true;
            this.colDebit.VisibleIndex = 3;
            this.colDebit.Width = 130;
            // 
            // colCredit
            // 
            this.colCredit.Caption = "Credit";
            this.colCredit.FieldName = "Credit";
            this.colCredit.Name = "colCredit";
            this.colCredit.Summary.AddRange(new DevExpress.XtraGrid.GridSummaryItem[] {
            new DevExpress.XtraGrid.GridColumnSummaryItem(DevExpress.Data.SummaryItemType.Sum, "Credit", "{0:n2}")});
            this.colCredit.Visible = true;
            this.colCredit.VisibleIndex = 4;
            this.colCredit.Width = 130;
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
            this.repAccountCodeView.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.repAccountCodeView.Name = "repAccountCodeView";
            this.repAccountCodeView.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.repAccountCodeView.OptionsView.ShowGroupPanel = false;
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
            // repParticulars
            // 
            this.repParticulars.AutoHeight = false;
            this.repParticulars.Name = "repParticulars";
            // 
            // lblBalanceStatus
            // 
            this.lblBalanceStatus.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblBalanceStatus.Appearance.ForeColor = System.Drawing.Color.Red;
            this.lblBalanceStatus.Appearance.Options.UseFont = true;
            this.lblBalanceStatus.Appearance.Options.UseForeColor = true;
            this.lblBalanceStatus.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblBalanceStatus.Location = new System.Drawing.Point(16, 316);
            this.lblBalanceStatus.Name = "lblBalanceStatus";
            this.lblBalanceStatus.Size = new System.Drawing.Size(880, 18);
            this.lblBalanceStatus.TabIndex = 7;
            // 
            // panelControl2
            // 
            this.panelControl2.Controls.Add(this.btnAddLine);
            this.panelControl2.Controls.Add(this.lblTotalDebitCaption);
            this.panelControl2.Controls.Add(this.lblTotalDebit);
            this.panelControl2.Controls.Add(this.btnRemoveLine);
            this.panelControl2.Controls.Add(this.lblTotalCreditCaption);
            this.panelControl2.Controls.Add(this.lblTotalCredit);
            this.panelControl2.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.panelControl2.Location = new System.Drawing.Point(0, 661);
            this.panelControl2.Name = "panelControl2";
            this.panelControl2.Size = new System.Drawing.Size(936, 42);
            this.panelControl2.TabIndex = 4;
            // 
            // btnAddLine
            // 
            this.btnAddLine.Location = new System.Drawing.Point(5, 5);
            this.btnAddLine.Name = "btnAddLine";
            this.btnAddLine.Size = new System.Drawing.Size(110, 28);
            this.btnAddLine.TabIndex = 1;
            this.btnAddLine.Text = "Add Line";
            this.btnAddLine.Click += new System.EventHandler(this.BtnAddLine_Click);
            // 
            // lblTotalDebitCaption
            // 
            this.lblTotalDebitCaption.Location = new System.Drawing.Point(239, 11);
            this.lblTotalDebitCaption.Name = "lblTotalDebitCaption";
            this.lblTotalDebitCaption.Size = new System.Drawing.Size(67, 16);
            this.lblTotalDebitCaption.TabIndex = 3;
            this.lblTotalDebitCaption.Text = "Total Debit:";
            // 
            // lblTotalDebit
            // 
            this.lblTotalDebit.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblTotalDebit.Appearance.Options.UseFont = true;
            this.lblTotalDebit.Location = new System.Drawing.Point(319, 11);
            this.lblTotalDebit.Name = "lblTotalDebit";
            this.lblTotalDebit.Size = new System.Drawing.Size(35, 18);
            this.lblTotalDebit.TabIndex = 4;
            this.lblTotalDebit.Text = "0.00";
            // 
            // btnRemoveLine
            // 
            this.btnRemoveLine.Location = new System.Drawing.Point(123, 5);
            this.btnRemoveLine.Name = "btnRemoveLine";
            this.btnRemoveLine.Size = new System.Drawing.Size(110, 28);
            this.btnRemoveLine.TabIndex = 2;
            this.btnRemoveLine.Text = "Remove Line";
            this.btnRemoveLine.Click += new System.EventHandler(this.BtnRemoveLine_Click);
            // 
            // lblTotalCreditCaption
            // 
            this.lblTotalCreditCaption.Location = new System.Drawing.Point(419, 11);
            this.lblTotalCreditCaption.Name = "lblTotalCreditCaption";
            this.lblTotalCreditCaption.Size = new System.Drawing.Size(72, 16);
            this.lblTotalCreditCaption.TabIndex = 5;
            this.lblTotalCreditCaption.Text = "Total Credit:";
            // 
            // lblTotalCredit
            // 
            this.lblTotalCredit.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblTotalCredit.Appearance.Options.UseFont = true;
            this.lblTotalCredit.Location = new System.Drawing.Point(499, 11);
            this.lblTotalCredit.Name = "lblTotalCredit";
            this.lblTotalCredit.Size = new System.Drawing.Size(35, 18);
            this.lblTotalCredit.TabIndex = 6;
            this.lblTotalCredit.Text = "0.00";
            // 
            // panelControl1
            // 
            this.panelControl1.Controls.Add(this.btnSubmit);
            this.panelControl1.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.panelControl1.Location = new System.Drawing.Point(0, 703);
            this.panelControl1.Name = "panelControl1";
            this.panelControl1.Size = new System.Drawing.Size(936, 57);
            this.panelControl1.TabIndex = 3;
            // 
            // btnSubmit
            // 
            this.btnSubmit.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.btnSubmit.Appearance.Options.UseFont = true;
            this.btnSubmit.Location = new System.Drawing.Point(9, 12);
            this.btnSubmit.Name = "btnSubmit";
            this.btnSubmit.Size = new System.Drawing.Size(113, 40);
            this.btnSubmit.TabIndex = 1;
            this.btnSubmit.Text = "Submit";
            this.btnSubmit.Click += new System.EventHandler(this.BtnSubmit_Click);
            // 
            // grpHeader
            // 
            this.grpHeader.Controls.Add(this.labelControl1);
            this.grpHeader.Controls.Add(this.lblReferenceNo);
            this.grpHeader.Controls.Add(this.txtReferenceNo);
            this.grpHeader.Controls.Add(this.lblTicketNo);
            this.grpHeader.Controls.Add(this.txtTicketNo);
            this.grpHeader.Controls.Add(this.lblBranch);
            this.grpHeader.Controls.Add(this.cboBranch);
            this.grpHeader.Controls.Add(this.lblSupplier);
            this.grpHeader.Controls.Add(this.cboSupplier);
            this.grpHeader.Controls.Add(this.lblInvoiceNo);
            this.grpHeader.Controls.Add(this.txtInvoiceNo);
            this.grpHeader.Controls.Add(this.lblExpenseDate);
            this.grpHeader.Controls.Add(this.txtExpenseDate);
            this.grpHeader.Controls.Add(this.chkLinkToPO);
            this.grpHeader.Controls.Add(this.cboPO);
            this.grpHeader.Controls.Add(this.lblRemarks);
            this.grpHeader.Controls.Add(this.txtRemarks);
            this.grpHeader.Controls.Add(this.lblEditNotice);
            this.grpHeader.Dock = System.Windows.Forms.DockStyle.Top;
            this.grpHeader.Location = new System.Drawing.Point(0, 0);
            this.grpHeader.Name = "grpHeader";
            this.grpHeader.Size = new System.Drawing.Size(936, 322);
            this.grpHeader.TabIndex = 2;
            this.grpHeader.Text = "Expense Header";
            // 
            // labelControl1
            // 
            this.labelControl1.Location = new System.Drawing.Point(306, 69);
            this.labelControl1.Name = "labelControl1";
            this.labelControl1.Size = new System.Drawing.Size(69, 16);
            this.labelControl1.TabIndex = 17;
            this.labelControl1.Text = "Ticket Date:";
            // 
            // lblReferenceNo
            // 
            this.lblReferenceNo.Location = new System.Drawing.Point(16, 34);
            this.lblReferenceNo.Name = "lblReferenceNo";
            this.lblReferenceNo.Size = new System.Drawing.Size(86, 16);
            this.lblReferenceNo.TabIndex = 0;
            this.lblReferenceNo.Text = "Reference No.:";
            // 
            // txtReferenceNo
            // 
            this.txtReferenceNo.Location = new System.Drawing.Point(150, 31);
            this.txtReferenceNo.Name = "txtReferenceNo";
            this.txtReferenceNo.Properties.ReadOnly = true;
            this.txtReferenceNo.Size = new System.Drawing.Size(150, 22);
            this.txtReferenceNo.TabIndex = 1;
            // 
            // lblTicketNo
            // 
            this.lblTicketNo.Location = new System.Drawing.Point(16, 69);
            this.lblTicketNo.Name = "lblTicketNo";
            this.lblTicketNo.Size = new System.Drawing.Size(62, 16);
            this.lblTicketNo.TabIndex = 2;
            this.lblTicketNo.Text = "Ticket No.:";
            // 
            // txtTicketNo
            // 
            this.txtTicketNo.Location = new System.Drawing.Point(150, 66);
            this.txtTicketNo.Name = "txtTicketNo";
            this.txtTicketNo.Properties.ReadOnly = true;
            this.txtTicketNo.Size = new System.Drawing.Size(150, 22);
            this.txtTicketNo.TabIndex = 3;
            // 
            // lblBranch
            // 
            this.lblBranch.Location = new System.Drawing.Point(16, 105);
            this.lblBranch.Name = "lblBranch";
            this.lblBranch.Size = new System.Drawing.Size(44, 16);
            this.lblBranch.TabIndex = 4;
            this.lblBranch.Text = "Branch:";
            // 
            // cboBranch
            // 
            this.cboBranch.Location = new System.Drawing.Point(150, 102);
            this.cboBranch.Name = "cboBranch";
            this.cboBranch.Properties.PopupView = this.gridViewBranchPopup;
            this.cboBranch.Size = new System.Drawing.Size(300, 22);
            this.cboBranch.TabIndex = 5;
            // 
            // gridViewBranchPopup
            // 
            this.gridViewBranchPopup.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.gridViewBranchPopup.Name = "gridViewBranchPopup";
            this.gridViewBranchPopup.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.gridViewBranchPopup.OptionsView.ShowGroupPanel = false;
            // 
            // lblSupplier
            // 
            this.lblSupplier.Location = new System.Drawing.Point(16, 141);
            this.lblSupplier.Name = "lblSupplier";
            this.lblSupplier.Size = new System.Drawing.Size(106, 16);
            this.lblSupplier.TabIndex = 6;
            this.lblSupplier.Text = "Vendor / Supplier:";
            // 
            // cboSupplier
            // 
            this.cboSupplier.Location = new System.Drawing.Point(150, 138);
            this.cboSupplier.Name = "cboSupplier";
            this.cboSupplier.Properties.PopupView = this.gridViewSupplierPopup;
            this.cboSupplier.Size = new System.Drawing.Size(494, 22);
            this.cboSupplier.TabIndex = 7;
            this.cboSupplier.EditValueChanged += new System.EventHandler(this.CboSupplier_EditValueChanged);
            // 
            // gridViewSupplierPopup
            // 
            this.gridViewSupplierPopup.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.gridViewSupplierPopup.Name = "gridViewSupplierPopup";
            this.gridViewSupplierPopup.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.gridViewSupplierPopup.OptionsView.ShowGroupPanel = false;
            // 
            // lblInvoiceNo
            // 
            this.lblInvoiceNo.Location = new System.Drawing.Point(16, 177);
            this.lblInvoiceNo.Name = "lblInvoiceNo";
            this.lblInvoiceNo.Size = new System.Drawing.Size(68, 16);
            this.lblInvoiceNo.TabIndex = 8;
            this.lblInvoiceNo.Text = "Invoice No.:";
            // 
            // txtInvoiceNo
            // 
            this.txtInvoiceNo.Location = new System.Drawing.Point(150, 174);
            this.txtInvoiceNo.Name = "txtInvoiceNo";
            this.txtInvoiceNo.Size = new System.Drawing.Size(300, 22);
            this.txtInvoiceNo.TabIndex = 9;
            // 
            // lblExpenseDate
            // 
            this.lblExpenseDate.Location = new System.Drawing.Point(534, 141);
            this.lblExpenseDate.Name = "lblExpenseDate";
            this.lblExpenseDate.Size = new System.Drawing.Size(82, 16);
            this.lblExpenseDate.TabIndex = 10;
            this.lblExpenseDate.Text = "Expense Date:";
            // 
            // txtExpenseDate
            // 
            this.txtExpenseDate.EditValue = new System.DateTime(2026, 7, 22, 0, 0, 0, 0);
            this.txtExpenseDate.Location = new System.Drawing.Point(384, 66);
            this.txtExpenseDate.Name = "txtExpenseDate";
            this.txtExpenseDate.Size = new System.Drawing.Size(150, 22);
            this.txtExpenseDate.TabIndex = 11;
            // 
            // chkLinkToPO
            // 
            this.chkLinkToPO.Location = new System.Drawing.Point(16, 212);
            this.chkLinkToPO.Name = "chkLinkToPO";
            this.chkLinkToPO.Properties.Caption = "Link to PO";
            this.chkLinkToPO.Size = new System.Drawing.Size(100, 24);
            this.chkLinkToPO.TabIndex = 12;
            this.chkLinkToPO.CheckedChanged += new System.EventHandler(this.ChkLinkToPO_CheckedChanged);
            // 
            // cboPO
            // 
            this.cboPO.Enabled = false;
            this.cboPO.Location = new System.Drawing.Point(150, 210);
            this.cboPO.Name = "cboPO";
            this.cboPO.Properties.PopupView = this.gridViewPOPopup;
            this.cboPO.Size = new System.Drawing.Size(494, 22);
            this.cboPO.TabIndex = 13;
            this.cboPO.EditValueChanged += new System.EventHandler(this.cboPO_EditValueChanged);
            // 
            // gridViewPOPopup
            // 
            this.gridViewPOPopup.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.gridViewPOPopup.Name = "gridViewPOPopup";
            this.gridViewPOPopup.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.gridViewPOPopup.OptionsView.ShowGroupPanel = false;
            // 
            // lblRemarks
            // 
            this.lblRemarks.Location = new System.Drawing.Point(16, 250);
            this.lblRemarks.Name = "lblRemarks";
            this.lblRemarks.Size = new System.Drawing.Size(128, 16);
            this.lblRemarks.TabIndex = 14;
            this.lblRemarks.Text = "Remarks / Particulars:";
            // 
            // txtRemarks
            // 
            this.txtRemarks.Location = new System.Drawing.Point(150, 247);
            this.txtRemarks.Name = "txtRemarks";
            this.txtRemarks.Size = new System.Drawing.Size(494, 46);
            this.txtRemarks.TabIndex = 15;
            // 
            // lblEditNotice
            // 
            this.lblEditNotice.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblEditNotice.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(180)))), ((int)(((byte)(120)))), ((int)(((byte)(0)))));
            this.lblEditNotice.Appearance.Options.UseFont = true;
            this.lblEditNotice.Appearance.Options.UseForeColor = true;
            this.lblEditNotice.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblEditNotice.Location = new System.Drawing.Point(16, 299);
            this.lblEditNotice.Name = "lblEditNotice";
            this.lblEditNotice.Size = new System.Drawing.Size(880, 18);
            this.lblEditNotice.TabIndex = 16;
            this.lblEditNotice.Visible = false;
            // 
            // tabPosted
            // 
            this.tabPosted.Controls.Add(this.gridControlPostedDetails);
            this.tabPosted.Controls.Add(this.pnlPostedButtons);
            this.tabPosted.Controls.Add(this.gridControlPosted);
            this.tabPosted.Controls.Add(this.pnlPostedFilter);
            this.tabPosted.Name = "tabPosted";
            this.tabPosted.Size = new System.Drawing.Size(936, 760);
            this.tabPosted.Text = "Posted Expenses";
            // 
            // gridControlPostedDetails
            // 
            this.gridControlPostedDetails.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlPostedDetails.Location = new System.Drawing.Point(0, 430);
            this.gridControlPostedDetails.MainView = this.gridViewPostedDetails;
            this.gridControlPostedDetails.Name = "gridControlPostedDetails";
            this.gridControlPostedDetails.Size = new System.Drawing.Size(936, 330);
            this.gridControlPostedDetails.TabIndex = 0;
            this.gridControlPostedDetails.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewPostedDetails});
            // 
            // gridViewPostedDetails
            // 
            this.gridViewPostedDetails.GridControl = this.gridControlPostedDetails;
            this.gridViewPostedDetails.Name = "gridViewPostedDetails";
            this.gridViewPostedDetails.OptionsBehavior.Editable = false;
            this.gridViewPostedDetails.OptionsView.ShowGroupPanel = false;
            // 
            // pnlPostedButtons
            // 
            this.pnlPostedButtons.Controls.Add(this.btnViewDetails);
            this.pnlPostedButtons.Controls.Add(this.btnCopyToNew);
            this.pnlPostedButtons.Controls.Add(this.btnEdit);
            this.pnlPostedButtons.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlPostedButtons.Location = new System.Drawing.Point(0, 384);
            this.pnlPostedButtons.Name = "pnlPostedButtons";
            this.pnlPostedButtons.Size = new System.Drawing.Size(936, 46);
            this.pnlPostedButtons.TabIndex = 1;
            // 
            // btnViewDetails
            // 
            this.btnViewDetails.Enabled = false;
            this.btnViewDetails.Location = new System.Drawing.Point(12, 9);
            this.btnViewDetails.Name = "btnViewDetails";
            this.btnViewDetails.Size = new System.Drawing.Size(120, 28);
            this.btnViewDetails.TabIndex = 0;
            this.btnViewDetails.Text = "View Details";
            this.btnViewDetails.Click += new System.EventHandler(this.BtnViewDetails_Click);
            // 
            // btnCopyToNew
            // 
            this.btnCopyToNew.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(255)))), ((int)(((byte)(244)))), ((int)(((byte)(219)))));
            this.btnCopyToNew.Appearance.Options.UseBackColor = true;
            this.btnCopyToNew.Enabled = false;
            this.btnCopyToNew.Location = new System.Drawing.Point(140, 9);
            this.btnCopyToNew.Name = "btnCopyToNew";
            this.btnCopyToNew.Size = new System.Drawing.Size(150, 28);
            this.btnCopyToNew.TabIndex = 1;
            this.btnCopyToNew.Text = "Copy to New Entry";
            this.btnCopyToNew.Click += new System.EventHandler(this.BtnCopyToNew_Click);
            // 
            // btnEdit
            // 
            this.btnEdit.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(220)))), ((int)(((byte)(235)))), ((int)(((byte)(255)))));
            this.btnEdit.Appearance.Options.UseBackColor = true;
            this.btnEdit.Enabled = false;
            this.btnEdit.Location = new System.Drawing.Point(298, 9);
            this.btnEdit.Name = "btnEdit";
            this.btnEdit.Size = new System.Drawing.Size(110, 28);
            this.btnEdit.TabIndex = 2;
            this.btnEdit.Text = "Edit";
            this.btnEdit.Click += new System.EventHandler(this.BtnEdit_Click);
            // 
            // gridControlPosted
            // 
            this.gridControlPosted.Dock = System.Windows.Forms.DockStyle.Top;
            this.gridControlPosted.Location = new System.Drawing.Point(0, 59);
            this.gridControlPosted.MainView = this.gridViewPosted;
            this.gridControlPosted.Name = "gridControlPosted";
            this.gridControlPosted.Size = new System.Drawing.Size(936, 325);
            this.gridControlPosted.TabIndex = 2;
            this.gridControlPosted.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewPosted});
            // 
            // gridViewPosted
            // 
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
            this.pnlPostedFilter.Controls.Add(this.lblFilterBranch);
            this.pnlPostedFilter.Controls.Add(this.cboFilterBranch);
            this.pnlPostedFilter.Controls.Add(this.chkAllBranches);
            this.pnlPostedFilter.Controls.Add(this.btnRefreshPosted);
            this.pnlPostedFilter.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlPostedFilter.Location = new System.Drawing.Point(0, 0);
            this.pnlPostedFilter.Name = "pnlPostedFilter";
            this.pnlPostedFilter.Size = new System.Drawing.Size(936, 59);
            this.pnlPostedFilter.TabIndex = 3;
            // 
            // lblDateFrom
            // 
            this.lblDateFrom.Location = new System.Drawing.Point(12, 21);
            this.lblDateFrom.Name = "lblDateFrom";
            this.lblDateFrom.Size = new System.Drawing.Size(35, 16);
            this.lblDateFrom.TabIndex = 0;
            this.lblDateFrom.Text = "From:";
            // 
            // txtDateFrom
            // 
            this.txtDateFrom.EditValue = new System.DateTime(2026, 7, 22, 0, 0, 0, 0);
            this.txtDateFrom.Location = new System.Drawing.Point(58, 16);
            this.txtDateFrom.Name = "txtDateFrom";
            this.txtDateFrom.Size = new System.Drawing.Size(120, 22);
            this.txtDateFrom.TabIndex = 1;
            // 
            // lblDateTo
            // 
            this.lblDateTo.Location = new System.Drawing.Point(190, 21);
            this.lblDateTo.Name = "lblDateTo";
            this.lblDateTo.Size = new System.Drawing.Size(20, 16);
            this.lblDateTo.TabIndex = 2;
            this.lblDateTo.Text = "To:";
            // 
            // txtDateTo
            // 
            this.txtDateTo.EditValue = new System.DateTime(2026, 7, 22, 0, 0, 0, 0);
            this.txtDateTo.Location = new System.Drawing.Point(214, 16);
            this.txtDateTo.Name = "txtDateTo";
            this.txtDateTo.Size = new System.Drawing.Size(120, 22);
            this.txtDateTo.TabIndex = 3;
            // 
            // lblFilterBranch
            // 
            this.lblFilterBranch.Location = new System.Drawing.Point(346, 21);
            this.lblFilterBranch.Name = "lblFilterBranch";
            this.lblFilterBranch.Size = new System.Drawing.Size(44, 16);
            this.lblFilterBranch.TabIndex = 4;
            this.lblFilterBranch.Text = "Branch:";
            // 
            // cboFilterBranch
            // 
            this.cboFilterBranch.Location = new System.Drawing.Point(394, 16);
            this.cboFilterBranch.Name = "cboFilterBranch";
            this.cboFilterBranch.Size = new System.Drawing.Size(160, 22);
            this.cboFilterBranch.TabIndex = 5;
            // 
            // chkAllBranches
            // 
            this.chkAllBranches.Location = new System.Drawing.Point(566, 18);
            this.chkAllBranches.Name = "chkAllBranches";
            this.chkAllBranches.Properties.Caption = "All Branches";
            this.chkAllBranches.Size = new System.Drawing.Size(110, 24);
            this.chkAllBranches.TabIndex = 6;
            this.chkAllBranches.CheckedChanged += new System.EventHandler(this.ChkAllBranches_CheckedChanged);
            // 
            // btnRefreshPosted
            // 
            this.btnRefreshPosted.Location = new System.Drawing.Point(692, 12);
            this.btnRefreshPosted.Name = "btnRefreshPosted";
            this.btnRefreshPosted.Size = new System.Drawing.Size(100, 30);
            this.btnRefreshPosted.TabIndex = 7;
            this.btnRefreshPosted.Text = "Refresh";
            this.btnRefreshPosted.Click += new System.EventHandler(this.BtnRefreshPosted_Click);
            // 
            // btnNewEntry
            // 
            this.btnNewEntry.Location = new System.Drawing.Point(0, 0);
            this.btnNewEntry.Name = "btnNewEntry";
            this.btnNewEntry.Size = new System.Drawing.Size(94, 29);
            this.btnNewEntry.TabIndex = 0;
            // 
            // AddExpenseDevExFrm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.Controls.Add(this.tabMain);
            this.Name = "AddExpenseDevExFrm";
            this.Size = new System.Drawing.Size(938, 790);
            this.Load += new System.EventHandler(this.AddExpenseDevExFrm_Load);
            ((System.ComponentModel.ISupportInitialize)(this.tabMain)).EndInit();
            this.tabMain.ResumeLayout(false);
            this.tabEntry.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.grpLines)).EndInit();
            this.grpLines.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlLines)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewLines)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repAccountCode)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repAccountCodeView)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repDebit)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repCredit)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repParticulars)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl2)).EndInit();
            this.panelControl2.ResumeLayout(false);
            this.panelControl2.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl1)).EndInit();
            this.panelControl1.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).EndInit();
            this.grpHeader.ResumeLayout(false);
            this.grpHeader.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtTicketNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranch.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewBranchPopup)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboSupplier.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewSupplierPopup)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtInvoiceNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtExpenseDate.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtExpenseDate.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkLinkToPO.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboPO.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewPOPopup)).EndInit();
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
            ((System.ComponentModel.ISupportInitialize)(this.cboFilterBranch.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkAllBranches.Properties)).EndInit();
            this.ResumeLayout(false);

        }

        private DevExpress.XtraEditors.PanelControl panelControl2;
        private DevExpress.XtraEditors.PanelControl panelControl1;
        private DevExpress.XtraEditors.LabelControl labelControl1;
    }
}