namespace SalesInventorySystem.AccountingDevEx
{
    partial class TicketInquiryFrm
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null)) components.Dispose();
            base.Dispose(disposing);
        }

        private DevExpress.XtraEditors.GroupControl grpSearch;
        private DevExpress.XtraEditors.LabelControl lblSearchTerm;
        private DevExpress.XtraEditors.TextEdit txtSearchTerm;
        private DevExpress.XtraEditors.LabelControl lblDateFrom;
        private DevExpress.XtraEditors.DateEdit txtDateFrom;
        private DevExpress.XtraEditors.LabelControl lblDateTo;
        private DevExpress.XtraEditors.DateEdit txtDateTo;
        private DevExpress.XtraEditors.SimpleButton btnSearch;

        private DevExpress.XtraEditors.GroupControl grpResults;
        private DevExpress.XtraGrid.GridControl gridControlResults;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewResults;
        private DevExpress.XtraEditors.SimpleButton btnViewDetails;

        private DevExpress.XtraEditors.GroupControl grpDetails;
        private DevExpress.XtraEditors.LabelControl lblTicketHeader;
        private DevExpress.XtraGrid.GridControl gridControlDetails;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewDetails;
        private DevExpress.XtraGrid.Columns.GridColumn colDetailBranchCode;
        private DevExpress.XtraGrid.Columns.GridColumn colDetailAccountCode;
        private DevExpress.XtraGrid.Columns.GridColumn colDetailAccountTitle;
        private DevExpress.XtraGrid.Columns.GridColumn colDetailDebit;
        private DevExpress.XtraGrid.Columns.GridColumn colDetailCredit;

        private void InitializeComponent()
        {
            this.grpSearch = new DevExpress.XtraEditors.GroupControl();
            this.lblSearchTerm = new DevExpress.XtraEditors.LabelControl();
            this.txtSearchTerm = new DevExpress.XtraEditors.TextEdit();
            this.lblDateFrom = new DevExpress.XtraEditors.LabelControl();
            this.txtDateFrom = new DevExpress.XtraEditors.DateEdit();
            this.lblDateTo = new DevExpress.XtraEditors.LabelControl();
            this.txtDateTo = new DevExpress.XtraEditors.DateEdit();
            this.btnSearch = new DevExpress.XtraEditors.SimpleButton();
            this.grpResults = new DevExpress.XtraEditors.GroupControl();
            this.gridControlResults = new DevExpress.XtraGrid.GridControl();
            this.gridViewResults = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.btnViewDetails = new DevExpress.XtraEditors.SimpleButton();
            this.grpDetails = new DevExpress.XtraEditors.GroupControl();
            this.gridControlDetails = new DevExpress.XtraGrid.GridControl();
            this.gridViewDetails = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.colDetailBranchCode = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colDetailAccountCode = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colDetailAccountTitle = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colDetailDebit = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colDetailCredit = new DevExpress.XtraGrid.Columns.GridColumn();
            this.lblTicketHeader = new DevExpress.XtraEditors.LabelControl();
            ((System.ComponentModel.ISupportInitialize)(this.grpSearch)).BeginInit();
            this.grpSearch.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtSearchTerm.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateFrom.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateFrom.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateTo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateTo.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpResults)).BeginInit();
            this.grpResults.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlResults)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewResults)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpDetails)).BeginInit();
            this.grpDetails.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlDetails)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewDetails)).BeginInit();
            this.SuspendLayout();
            // 
            // grpSearch
            // 
            this.grpSearch.Controls.Add(this.lblSearchTerm);
            this.grpSearch.Controls.Add(this.txtSearchTerm);
            this.grpSearch.Controls.Add(this.lblDateFrom);
            this.grpSearch.Controls.Add(this.txtDateFrom);
            this.grpSearch.Controls.Add(this.lblDateTo);
            this.grpSearch.Controls.Add(this.txtDateTo);
            this.grpSearch.Controls.Add(this.btnSearch);
            this.grpSearch.Dock = System.Windows.Forms.DockStyle.Top;
            this.grpSearch.Location = new System.Drawing.Point(0, 0);
            this.grpSearch.Name = "grpSearch";
            this.grpSearch.Size = new System.Drawing.Size(950, 95);
            this.grpSearch.TabIndex = 2;
            this.grpSearch.Text = "Search — Ticket Number or Reference Number";
            // 
            // lblSearchTerm
            // 
            this.lblSearchTerm.Location = new System.Drawing.Point(16, 50);
            this.lblSearchTerm.Name = "lblSearchTerm";
            this.lblSearchTerm.Size = new System.Drawing.Size(45, 16);
            this.lblSearchTerm.TabIndex = 0;
            this.lblSearchTerm.Text = "Search:";
            // 
            // txtSearchTerm
            // 
            this.txtSearchTerm.Location = new System.Drawing.Point(90, 47);
            this.txtSearchTerm.Name = "txtSearchTerm";
            this.txtSearchTerm.Properties.NullText = "Ticket # or Reference #...";
            this.txtSearchTerm.Size = new System.Drawing.Size(260, 22);
            this.txtSearchTerm.TabIndex = 1;
            this.txtSearchTerm.KeyDown += new System.Windows.Forms.KeyEventHandler(this.TxtSearchTerm_KeyDown);
            // 
            // lblDateFrom
            // 
            this.lblDateFrom.Location = new System.Drawing.Point(370, 50);
            this.lblDateFrom.Name = "lblDateFrom";
            this.lblDateFrom.Size = new System.Drawing.Size(35, 16);
            this.lblDateFrom.TabIndex = 2;
            this.lblDateFrom.Text = "From:";
            // 
            // txtDateFrom
            // 
            this.txtDateFrom.EditValue = new System.DateTime(2026, 7, 29, 0, 0, 0, 0);
            this.txtDateFrom.Location = new System.Drawing.Point(410, 47);
            this.txtDateFrom.Name = "txtDateFrom";
            this.txtDateFrom.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtDateFrom.Size = new System.Drawing.Size(120, 22);
            this.txtDateFrom.TabIndex = 3;
            // 
            // lblDateTo
            // 
            this.lblDateTo.Location = new System.Drawing.Point(545, 50);
            this.lblDateTo.Name = "lblDateTo";
            this.lblDateTo.Size = new System.Drawing.Size(20, 16);
            this.lblDateTo.TabIndex = 4;
            this.lblDateTo.Text = "To:";
            // 
            // txtDateTo
            // 
            this.txtDateTo.EditValue = new System.DateTime(2026, 7, 29, 0, 0, 0, 0);
            this.txtDateTo.Location = new System.Drawing.Point(570, 47);
            this.txtDateTo.Name = "txtDateTo";
            this.txtDateTo.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtDateTo.Size = new System.Drawing.Size(120, 22);
            this.txtDateTo.TabIndex = 5;
            // 
            // btnSearch
            // 
            this.btnSearch.Location = new System.Drawing.Point(696, 45);
            this.btnSearch.Name = "btnSearch";
            this.btnSearch.Size = new System.Drawing.Size(110, 26);
            this.btnSearch.TabIndex = 6;
            this.btnSearch.Text = "Search";
            this.btnSearch.Click += new System.EventHandler(this.BtnSearch_Click);
            // 
            // grpResults
            // 
            this.grpResults.Controls.Add(this.gridControlResults);
            this.grpResults.Controls.Add(this.btnViewDetails);
            this.grpResults.Dock = System.Windows.Forms.DockStyle.Top;
            this.grpResults.Location = new System.Drawing.Point(0, 95);
            this.grpResults.Name = "grpResults";
            this.grpResults.Size = new System.Drawing.Size(950, 240);
            this.grpResults.TabIndex = 1;
            this.grpResults.Text = "Matching Tickets (each row is ONE ticket, regardless of how many branches it touc" +
    "hed)";
            // 
            // gridControlResults
            // 
            this.gridControlResults.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlResults.Location = new System.Drawing.Point(2, 28);
            this.gridControlResults.MainView = this.gridViewResults;
            this.gridControlResults.Name = "gridControlResults";
            this.gridControlResults.Size = new System.Drawing.Size(946, 210);
            this.gridControlResults.TabIndex = 0;
            this.gridControlResults.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewResults});
            // 
            // gridViewResults
            // 
            this.gridViewResults.GridControl = this.gridControlResults;
            this.gridViewResults.Name = "gridViewResults";
            this.gridViewResults.OptionsBehavior.Editable = false;
            this.gridViewResults.OptionsView.ShowGroupPanel = false;
            this.gridViewResults.DoubleClick += new System.EventHandler(this.GridViewResults_DoubleClick);
            // 
            // btnViewDetails
            // 
            this.btnViewDetails.Location = new System.Drawing.Point(16, 205);
            this.btnViewDetails.Name = "btnViewDetails";
            this.btnViewDetails.Size = new System.Drawing.Size(130, 28);
            this.btnViewDetails.TabIndex = 1;
            this.btnViewDetails.Text = "View Details";
            this.btnViewDetails.Click += new System.EventHandler(this.BtnViewDetails_Click);
            // 
            // grpDetails
            // 
            this.grpDetails.Controls.Add(this.gridControlDetails);
            this.grpDetails.Controls.Add(this.lblTicketHeader);
            this.grpDetails.Dock = System.Windows.Forms.DockStyle.Fill;
            this.grpDetails.Location = new System.Drawing.Point(0, 335);
            this.grpDetails.Name = "grpDetails";
            this.grpDetails.Size = new System.Drawing.Size(950, 365);
            this.grpDetails.TabIndex = 0;
            this.grpDetails.Text = "Ticket Detail — every leg, across every branch it touched";
            // 
            // gridControlDetails
            // 
            this.gridControlDetails.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlDetails.Location = new System.Drawing.Point(2, 78);
            this.gridControlDetails.MainView = this.gridViewDetails;
            this.gridControlDetails.Name = "gridControlDetails";
            this.gridControlDetails.Size = new System.Drawing.Size(946, 285);
            this.gridControlDetails.TabIndex = 0;
            this.gridControlDetails.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewDetails});
            // 
            // gridViewDetails
            // 
            this.gridViewDetails.Columns.AddRange(new DevExpress.XtraGrid.Columns.GridColumn[] {
            this.colDetailBranchCode,
            this.colDetailAccountCode,
            this.colDetailAccountTitle,
            this.colDetailDebit,
            this.colDetailCredit});
            this.gridViewDetails.GridControl = this.gridControlDetails;
            this.gridViewDetails.GroupCount = 1;
            this.gridViewDetails.GroupSummary.AddRange(new DevExpress.XtraGrid.GridSummaryItem[] {
            new DevExpress.XtraGrid.GridGroupSummaryItem(DevExpress.Data.SummaryItemType.Sum, "Debit", this.colDetailDebit, "Branch Debit: {0:n2}"),
            new DevExpress.XtraGrid.GridGroupSummaryItem(DevExpress.Data.SummaryItemType.Sum, "Credit", this.colDetailCredit, "Branch Credit: {0:n2}")});
            this.gridViewDetails.Name = "gridViewDetails";
            this.gridViewDetails.OptionsBehavior.Editable = false;
            this.gridViewDetails.OptionsView.ShowFooter = true;
            this.gridViewDetails.OptionsView.ShowGroupPanel = false;
            this.gridViewDetails.SortInfo.AddRange(new DevExpress.XtraGrid.Columns.GridColumnSortInfo[] {
            new DevExpress.XtraGrid.Columns.GridColumnSortInfo(this.colDetailBranchCode, DevExpress.Data.ColumnSortOrder.Ascending)});
            // 
            // colDetailBranchCode
            // 
            this.colDetailBranchCode.Caption = "Branch";
            this.colDetailBranchCode.FieldName = "BranchCode";
            this.colDetailBranchCode.Name = "colDetailBranchCode";
            this.colDetailBranchCode.Visible = true;
            this.colDetailBranchCode.VisibleIndex = 0;
            this.colDetailBranchCode.Width = 100;
            // 
            // colDetailAccountCode
            // 
            this.colDetailAccountCode.Caption = "Account Code";
            this.colDetailAccountCode.FieldName = "AccountCode";
            this.colDetailAccountCode.Name = "colDetailAccountCode";
            this.colDetailAccountCode.Visible = true;
            this.colDetailAccountCode.VisibleIndex = 0;
            this.colDetailAccountCode.Width = 150;
            // 
            // colDetailAccountTitle
            // 
            this.colDetailAccountTitle.Caption = "Account Title";
            this.colDetailAccountTitle.FieldName = "AccountTitle";
            this.colDetailAccountTitle.Name = "colDetailAccountTitle";
            this.colDetailAccountTitle.Visible = true;
            this.colDetailAccountTitle.VisibleIndex = 1;
            this.colDetailAccountTitle.Width = 260;
            // 
            // colDetailDebit
            // 
            this.colDetailDebit.Caption = "Debit";
            this.colDetailDebit.FieldName = "Debit";
            this.colDetailDebit.Name = "colDetailDebit";
            this.colDetailDebit.Summary.AddRange(new DevExpress.XtraGrid.GridSummaryItem[] {
            new DevExpress.XtraGrid.GridColumnSummaryItem(DevExpress.Data.SummaryItemType.Sum, "Debit", "{0:n2}")});
            this.colDetailDebit.Visible = true;
            this.colDetailDebit.VisibleIndex = 2;
            this.colDetailDebit.Width = 140;
            // 
            // colDetailCredit
            // 
            this.colDetailCredit.Caption = "Credit";
            this.colDetailCredit.FieldName = "Credit";
            this.colDetailCredit.Name = "colDetailCredit";
            this.colDetailCredit.Summary.AddRange(new DevExpress.XtraGrid.GridSummaryItem[] {
            new DevExpress.XtraGrid.GridColumnSummaryItem(DevExpress.Data.SummaryItemType.Sum, "Credit", "{0:n2}")});
            this.colDetailCredit.Visible = true;
            this.colDetailCredit.VisibleIndex = 3;
            this.colDetailCredit.Width = 140;
            // 
            // lblTicketHeader
            // 
            this.lblTicketHeader.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblTicketHeader.Appearance.Options.UseFont = true;
            this.lblTicketHeader.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblTicketHeader.Dock = System.Windows.Forms.DockStyle.Top;
            this.lblTicketHeader.Location = new System.Drawing.Point(2, 28);
            this.lblTicketHeader.Name = "lblTicketHeader";
            this.lblTicketHeader.Padding = new System.Windows.Forms.Padding(8);
            this.lblTicketHeader.Size = new System.Drawing.Size(946, 50);
            this.lblTicketHeader.TabIndex = 1;
            // 
            // TicketInquiryFrm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.Controls.Add(this.grpDetails);
            this.Controls.Add(this.grpResults);
            this.Controls.Add(this.grpSearch);
            this.Name = "TicketInquiryFrm";
            this.Size = new System.Drawing.Size(950, 700);
            this.Load += new System.EventHandler(this.TicketInquiryFrm_Load);
            ((System.ComponentModel.ISupportInitialize)(this.grpSearch)).EndInit();
            this.grpSearch.ResumeLayout(false);
            this.grpSearch.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtSearchTerm.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateFrom.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateFrom.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateTo.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateTo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpResults)).EndInit();
            this.grpResults.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlResults)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewResults)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpDetails)).EndInit();
            this.grpDetails.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlDetails)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewDetails)).EndInit();
            this.ResumeLayout(false);

        }
    }
}