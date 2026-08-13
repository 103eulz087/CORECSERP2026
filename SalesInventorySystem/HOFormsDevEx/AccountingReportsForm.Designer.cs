namespace SalesInventorySystem.HOFormsDevEx
{
    partial class AccountingReportsForm
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null)) components.Dispose();
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        // ── Header ──
        private DevExpress.XtraEditors.PanelControl pnlHeader;
        private DevExpress.XtraEditors.LabelControl lblTitle;
        private DevExpress.XtraEditors.LabelControl lblBreadcrumb;

        // ── Left sidebar: report type + parameters ──
        private DevExpress.XtraEditors.PanelControl pnlSidebar;
        private DevExpress.XtraEditors.LabelControl lblReportTypeCaption;
        private DevExpress.XtraEditors.ListBoxControl lstReportType;
        private DevExpress.XtraEditors.LabelControl lblParametersCaption;

        private DevExpress.XtraEditors.LabelControl lblBranchCode;
        private DevExpress.XtraEditors.LookUpEdit cboBranchCode;
        private DevExpress.XtraEditors.LabelControl lblAccountCode;
        private DevExpress.XtraEditors.SearchLookUpEdit txtAccountCode;
        private DevExpress.XtraEditors.LabelControl lblAsOfDate;
        private DevExpress.XtraEditors.DateEdit dteAsOfDate;
        private DevExpress.XtraEditors.LabelControl lblDateFrom;
        private DevExpress.XtraEditors.DateEdit dteDateFrom;
        private DevExpress.XtraEditors.LabelControl lblDateTo;
        private DevExpress.XtraEditors.DateEdit dteDateTo;
        private DevExpress.XtraEditors.CheckEdit chkAllBranches;
        private DevExpress.XtraEditors.CheckEdit chkAllAccounts;
        private DevExpress.XtraEditors.CheckEdit chkIncludeZeroActivity;
        private DevExpress.XtraEditors.RadioGroup rgConsolidatedMode;

        private DevExpress.XtraEditors.LabelControl lblDescription;
        private DevExpress.XtraEditors.LabelControl lblSpName;

        private DevExpress.XtraEditors.SimpleButton btnGenerate;
        private DevExpress.XtraEditors.SimpleButton btnExport;

        // ── Right: report display ──
        private DevExpress.XtraEditors.LabelControl lblReportTitle;
        private DevExpress.XtraEditors.LabelControl lblReportSubtitle;
        private DevExpress.XtraGrid.GridControl gridControlReport;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewReport;
        private DevExpress.XtraEditors.LabelControl lblSummaryCaption;
        private DevExpress.XtraGrid.GridControl gridControlSummary;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewSummary;
        private DevExpress.XtraEditors.LabelControl lblStatus;

        private void InitializeComponent()
        {
            this.pnlHeader = new DevExpress.XtraEditors.PanelControl();
            this.lblReportTitle = new DevExpress.XtraEditors.LabelControl();
            this.lblReportSubtitle = new DevExpress.XtraEditors.LabelControl();
            this.lblTitle = new DevExpress.XtraEditors.LabelControl();
            this.lblBreadcrumb = new DevExpress.XtraEditors.LabelControl();
            this.pnlSidebar = new DevExpress.XtraEditors.PanelControl();
            this.lblReportTypeCaption = new DevExpress.XtraEditors.LabelControl();
            this.lstReportType = new DevExpress.XtraEditors.ListBoxControl();
            this.lblParametersCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblStatus = new DevExpress.XtraEditors.LabelControl();
            this.lblBranchCode = new DevExpress.XtraEditors.LabelControl();
            this.cboBranchCode = new DevExpress.XtraEditors.LookUpEdit();
            this.lblAccountCode = new DevExpress.XtraEditors.LabelControl();
            this.txtAccountCode = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.lblAsOfDate = new DevExpress.XtraEditors.LabelControl();
            this.dteAsOfDate = new DevExpress.XtraEditors.DateEdit();
            this.lblDateFrom = new DevExpress.XtraEditors.LabelControl();
            this.dteDateFrom = new DevExpress.XtraEditors.DateEdit();
            this.lblDateTo = new DevExpress.XtraEditors.LabelControl();
            this.dteDateTo = new DevExpress.XtraEditors.DateEdit();
            this.chkAllBranches = new DevExpress.XtraEditors.CheckEdit();
            this.chkAllAccounts = new DevExpress.XtraEditors.CheckEdit();
            this.chkIncludeZeroActivity = new DevExpress.XtraEditors.CheckEdit();
            this.rgConsolidatedMode = new DevExpress.XtraEditors.RadioGroup();
            this.lblDescription = new DevExpress.XtraEditors.LabelControl();
            this.lblSpName = new DevExpress.XtraEditors.LabelControl();
            this.btnGenerate = new DevExpress.XtraEditors.SimpleButton();
            this.btnExport = new DevExpress.XtraEditors.SimpleButton();
            this.gridControlReport = new DevExpress.XtraGrid.GridControl();
            this.gridViewReport = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.lblSummaryCaption = new DevExpress.XtraEditors.LabelControl();
            this.gridControlSummary = new DevExpress.XtraGrid.GridControl();
            this.gridViewSummary = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.tablePanel1 = new DevExpress.Utils.Layout.TablePanel();
            this.panelControl2 = new DevExpress.XtraEditors.PanelControl();
            this.panelControl1 = new DevExpress.XtraEditors.PanelControl();
            ((System.ComponentModel.ISupportInitialize)(this.pnlHeader)).BeginInit();
            this.pnlHeader.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pnlSidebar)).BeginInit();
            this.pnlSidebar.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.lstReportType)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranchCode.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtAccountCode.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteAsOfDate.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteAsOfDate.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteDateFrom.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteDateFrom.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteDateTo.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteDateTo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkAllBranches.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkAllAccounts.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkIncludeZeroActivity.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.rgConsolidatedMode.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlReport)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewReport)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlSummary)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewSummary)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.tablePanel1)).BeginInit();
            this.tablePanel1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl2)).BeginInit();
            this.panelControl2.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl1)).BeginInit();
            this.panelControl1.SuspendLayout();
            this.SuspendLayout();
            // 
            // pnlHeader
            // 
            this.pnlHeader.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(27)))), ((int)(((byte)(32)))), ((int)(((byte)(46)))));
            this.pnlHeader.Appearance.BorderColor = System.Drawing.Color.FromArgb(((int)(((byte)(201)))), ((int)(((byte)(162)))), ((int)(((byte)(39)))));
            this.pnlHeader.Appearance.Options.UseBackColor = true;
            this.pnlHeader.Appearance.Options.UseBorderColor = true;
            this.pnlHeader.Controls.Add(this.lblReportTitle);
            this.pnlHeader.Controls.Add(this.lblReportSubtitle);
            this.pnlHeader.Controls.Add(this.lblTitle);
            this.pnlHeader.Controls.Add(this.lblBreadcrumb);
            this.pnlHeader.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlHeader.Location = new System.Drawing.Point(0, 0);
            this.pnlHeader.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.pnlHeader.Name = "pnlHeader";
            this.pnlHeader.Size = new System.Drawing.Size(1400, 79);
            this.pnlHeader.TabIndex = 7;
            // 
            // lblReportTitle
            // 
            this.lblReportTitle.Appearance.Font = new System.Drawing.Font("Tahoma", 14F, System.Drawing.FontStyle.Bold);
            this.lblReportTitle.Appearance.ForeColor = System.Drawing.Color.Black;
            this.lblReportTitle.Appearance.Options.UseFont = true;
            this.lblReportTitle.Appearance.Options.UseForeColor = true;
            this.lblReportTitle.Location = new System.Drawing.Point(579, 11);
            this.lblReportTitle.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblReportTitle.Name = "lblReportTitle";
            this.lblReportTitle.Size = new System.Drawing.Size(151, 28);
            this.lblReportTitle.TabIndex = 0;
            this.lblReportTitle.Text = "Trial Balance";
            // 
            // lblReportSubtitle
            // 
            this.lblReportSubtitle.Appearance.Font = new System.Drawing.Font("Tahoma", 8.5F);
            this.lblReportSubtitle.Appearance.ForeColor = System.Drawing.SystemColors.GrayText;
            this.lblReportSubtitle.Appearance.Options.UseFont = true;
            this.lblReportSubtitle.Appearance.Options.UseForeColor = true;
            this.lblReportSubtitle.Location = new System.Drawing.Point(579, 46);
            this.lblReportSubtitle.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblReportSubtitle.Name = "lblReportSubtitle";
            this.lblReportSubtitle.Size = new System.Drawing.Size(224, 17);
            this.lblReportSubtitle.TabIndex = 1;
            this.lblReportSubtitle.Text = "Select parameters and click Generate";
            // 
            // lblTitle
            // 
            this.lblTitle.Appearance.BackColor = System.Drawing.SystemColors.Control;
            this.lblTitle.Appearance.Font = new System.Drawing.Font("Tahoma", 13F, System.Drawing.FontStyle.Bold);
            this.lblTitle.Appearance.ForeColor = DevExpress.LookAndFeel.DXSkinColors.ForeColors.ControlText;
            this.lblTitle.Appearance.Options.UseBackColor = true;
            this.lblTitle.Appearance.Options.UseFont = true;
            this.lblTitle.Appearance.Options.UseForeColor = true;
            this.lblTitle.Location = new System.Drawing.Point(19, 12);
            this.lblTitle.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblTitle.Name = "lblTitle";
            this.lblTitle.Size = new System.Drawing.Size(243, 27);
            this.lblTitle.TabIndex = 0;
            this.lblTitle.Text = "JFC ERP  ·  GL Reports";
            // 
            // lblBreadcrumb
            // 
            this.lblBreadcrumb.Appearance.BackColor = System.Drawing.SystemColors.Control;
            this.lblBreadcrumb.Appearance.Font = new System.Drawing.Font("Tahoma", 8F);
            this.lblBreadcrumb.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(64)))), ((int)(((byte)(64)))), ((int)(((byte)(64)))));
            this.lblBreadcrumb.Appearance.Options.UseBackColor = true;
            this.lblBreadcrumb.Appearance.Options.UseFont = true;
            this.lblBreadcrumb.Appearance.Options.UseForeColor = true;
            this.lblBreadcrumb.Location = new System.Drawing.Point(19, 44);
            this.lblBreadcrumb.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblBreadcrumb.Name = "lblBreadcrumb";
            this.lblBreadcrumb.Size = new System.Drawing.Size(514, 16);
            this.lblBreadcrumb.TabIndex = 1;
            this.lblBreadcrumb.Text = "GL Detail · Trial Balance · Income Statement · Balance Sheet · Bank Recon · Conso" +
    "lidated";
            // 
            // pnlSidebar
            // 
            this.pnlSidebar.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(27)))), ((int)(((byte)(32)))), ((int)(((byte)(46)))));
            this.pnlSidebar.Appearance.Options.UseBackColor = true;
            this.pnlSidebar.Controls.Add(this.lblReportTypeCaption);
            this.pnlSidebar.Controls.Add(this.lstReportType);
            this.pnlSidebar.Controls.Add(this.lblParametersCaption);
            this.pnlSidebar.Controls.Add(this.lblStatus);
            this.pnlSidebar.Controls.Add(this.lblBranchCode);
            this.pnlSidebar.Controls.Add(this.cboBranchCode);
            this.pnlSidebar.Controls.Add(this.lblAccountCode);
            this.pnlSidebar.Controls.Add(this.txtAccountCode);
            this.pnlSidebar.Controls.Add(this.lblAsOfDate);
            this.pnlSidebar.Controls.Add(this.dteAsOfDate);
            this.pnlSidebar.Controls.Add(this.lblDateFrom);
            this.pnlSidebar.Controls.Add(this.dteDateFrom);
            this.pnlSidebar.Controls.Add(this.lblDateTo);
            this.pnlSidebar.Controls.Add(this.dteDateTo);
            this.pnlSidebar.Controls.Add(this.chkAllBranches);
            this.pnlSidebar.Controls.Add(this.chkAllAccounts);
            this.pnlSidebar.Controls.Add(this.chkIncludeZeroActivity);
            this.pnlSidebar.Controls.Add(this.rgConsolidatedMode);
            this.pnlSidebar.Controls.Add(this.lblDescription);
            this.pnlSidebar.Controls.Add(this.lblSpName);
            this.pnlSidebar.Controls.Add(this.btnGenerate);
            this.pnlSidebar.Controls.Add(this.btnExport);
            this.pnlSidebar.Dock = System.Windows.Forms.DockStyle.Left;
            this.pnlSidebar.Location = new System.Drawing.Point(0, 79);
            this.pnlSidebar.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.pnlSidebar.Name = "pnlSidebar";
            this.pnlSidebar.Size = new System.Drawing.Size(329, 906);
            this.pnlSidebar.TabIndex = 6;
            // 
            // lblReportTypeCaption
            // 
            this.lblReportTypeCaption.Appearance.BackColor = System.Drawing.SystemColors.Control;
            this.lblReportTypeCaption.Appearance.Font = new System.Drawing.Font("Tahoma", 7.5F, System.Drawing.FontStyle.Bold);
            this.lblReportTypeCaption.Appearance.ForeColor = DevExpress.LookAndFeel.DXSkinColors.ForeColors.ControlText;
            this.lblReportTypeCaption.Appearance.Options.UseBackColor = true;
            this.lblReportTypeCaption.Appearance.Options.UseFont = true;
            this.lblReportTypeCaption.Appearance.Options.UseForeColor = true;
            this.lblReportTypeCaption.Location = new System.Drawing.Point(19, 15);
            this.lblReportTypeCaption.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblReportTypeCaption.Name = "lblReportTypeCaption";
            this.lblReportTypeCaption.Size = new System.Drawing.Size(84, 16);
            this.lblReportTypeCaption.TabIndex = 0;
            this.lblReportTypeCaption.Text = "REPORT TYPE";
            // 
            // lstReportType
            // 
            this.lstReportType.Appearance.BackColor = System.Drawing.SystemColors.Control;
            this.lstReportType.Appearance.ForeColor = System.Drawing.Color.Black;
            this.lstReportType.Appearance.Options.UseBackColor = true;
            this.lstReportType.Appearance.Options.UseForeColor = true;
            this.lstReportType.AppearanceSelected.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(201)))), ((int)(((byte)(162)))), ((int)(((byte)(39)))));
            this.lstReportType.AppearanceSelected.ForeColor = System.Drawing.Color.Black;
            this.lstReportType.AppearanceSelected.Options.UseBackColor = true;
            this.lstReportType.AppearanceSelected.Options.UseForeColor = true;
            this.lstReportType.Items.AddRange(new object[] {
            "GL Detail Ledger",
            "GL Detail Transaction",
            "General Ledger (All Accounts)",
            "Trial Balance",
            "Income Statement",
            "Balance Sheet",
            "Bank Reconciliation",
            "Consolidated GL"});
            this.lstReportType.Location = new System.Drawing.Point(19, 37);
            this.lstReportType.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lstReportType.Name = "lstReportType";
            this.lstReportType.Size = new System.Drawing.Size(289, 207);
            this.lstReportType.TabIndex = 1;
            this.lstReportType.SelectedIndexChanged += new System.EventHandler(this.lstReportType_SelectedIndexChanged);
            // 
            // lblParametersCaption
            // 
            this.lblParametersCaption.Appearance.BackColor = System.Drawing.SystemColors.Control;
            this.lblParametersCaption.Appearance.Font = new System.Drawing.Font("Tahoma", 7.5F, System.Drawing.FontStyle.Bold);
            this.lblParametersCaption.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(140)))), ((int)(((byte)(148)))), ((int)(((byte)(165)))));
            this.lblParametersCaption.Appearance.Options.UseBackColor = true;
            this.lblParametersCaption.Appearance.Options.UseFont = true;
            this.lblParametersCaption.Appearance.Options.UseForeColor = true;
            this.lblParametersCaption.Location = new System.Drawing.Point(19, 258);
            this.lblParametersCaption.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblParametersCaption.Name = "lblParametersCaption";
            this.lblParametersCaption.Size = new System.Drawing.Size(86, 16);
            this.lblParametersCaption.TabIndex = 2;
            this.lblParametersCaption.Text = "PARAMETERS";
            // 
            // lblStatus
            // 
            this.lblStatus.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(140)))), ((int)(((byte)(148)))), ((int)(((byte)(165)))));
            this.lblStatus.Appearance.Options.UseForeColor = true;
            this.lblStatus.Location = new System.Drawing.Point(12, 801);
            this.lblStatus.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblStatus.Name = "lblStatus";
            this.lblStatus.Size = new System.Drawing.Size(35, 16);
            this.lblStatus.TabIndex = 5;
            this.lblStatus.Text = "Ready";
            // 
            // lblBranchCode
            // 
            this.lblBranchCode.Appearance.BackColor = System.Drawing.SystemColors.Control;
            this.lblBranchCode.Appearance.Font = new System.Drawing.Font("Tahoma", 7F);
            this.lblBranchCode.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(64)))), ((int)(((byte)(64)))), ((int)(((byte)(64)))));
            this.lblBranchCode.Appearance.Options.UseBackColor = true;
            this.lblBranchCode.Appearance.Options.UseFont = true;
            this.lblBranchCode.Appearance.Options.UseForeColor = true;
            this.lblBranchCode.Location = new System.Drawing.Point(19, 337);
            this.lblBranchCode.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblBranchCode.Name = "lblBranchCode";
            this.lblBranchCode.Size = new System.Drawing.Size(80, 14);
            this.lblBranchCode.TabIndex = 3;
            this.lblBranchCode.Text = "BRANCH CODE";
            // 
            // cboBranchCode
            // 
            this.cboBranchCode.Location = new System.Drawing.Point(19, 356);
            this.cboBranchCode.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.cboBranchCode.Name = "cboBranchCode";
            this.cboBranchCode.Properties.NullText = "";
            this.cboBranchCode.Size = new System.Drawing.Size(289, 22);
            this.cboBranchCode.TabIndex = 4;
            // 
            // lblAccountCode
            // 
            this.lblAccountCode.Appearance.BackColor = System.Drawing.SystemColors.Control;
            this.lblAccountCode.Appearance.Font = new System.Drawing.Font("Tahoma", 7F);
            this.lblAccountCode.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(64)))), ((int)(((byte)(64)))), ((int)(((byte)(64)))));
            this.lblAccountCode.Appearance.Options.UseBackColor = true;
            this.lblAccountCode.Appearance.Options.UseFont = true;
            this.lblAccountCode.Appearance.Options.UseForeColor = true;
            this.lblAccountCode.Location = new System.Drawing.Point(19, 286);
            this.lblAccountCode.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblAccountCode.Name = "lblAccountCode";
            this.lblAccountCode.Size = new System.Drawing.Size(90, 14);
            this.lblAccountCode.TabIndex = 5;
            this.lblAccountCode.Text = "ACCOUNT CODE";
            // 
            // txtAccountCode
            // 
            this.txtAccountCode.Location = new System.Drawing.Point(19, 305);
            this.txtAccountCode.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtAccountCode.Name = "txtAccountCode";
            this.txtAccountCode.Properties.NullText = "";
            this.txtAccountCode.Size = new System.Drawing.Size(289, 22);
            this.txtAccountCode.TabIndex = 6;
            // 
            // lblAsOfDate
            // 
            this.lblAsOfDate.Appearance.BackColor = System.Drawing.SystemColors.Control;
            this.lblAsOfDate.Appearance.Font = new System.Drawing.Font("Tahoma", 7F);
            this.lblAsOfDate.Appearance.ForeColor = DevExpress.LookAndFeel.DXSkinColors.ForeColors.ControlText;
            this.lblAsOfDate.Appearance.Options.UseBackColor = true;
            this.lblAsOfDate.Appearance.Options.UseFont = true;
            this.lblAsOfDate.Appearance.Options.UseForeColor = true;
            this.lblAsOfDate.Location = new System.Drawing.Point(19, 386);
            this.lblAsOfDate.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblAsOfDate.Name = "lblAsOfDate";
            this.lblAsOfDate.Size = new System.Drawing.Size(69, 14);
            this.lblAsOfDate.TabIndex = 7;
            this.lblAsOfDate.Text = "AS-OF DATE";
            // 
            // dteAsOfDate
            // 
            this.dteAsOfDate.EditValue = new System.DateTime(2026, 7, 14, 0, 0, 0, 0);
            this.dteAsOfDate.Location = new System.Drawing.Point(19, 405);
            this.dteAsOfDate.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.dteAsOfDate.Name = "dteAsOfDate";
            this.dteAsOfDate.Size = new System.Drawing.Size(289, 22);
            this.dteAsOfDate.TabIndex = 8;
            // 
            // lblDateFrom
            // 
            this.lblDateFrom.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(27)))), ((int)(((byte)(32)))), ((int)(((byte)(46)))));
            this.lblDateFrom.Appearance.Font = new System.Drawing.Font("Tahoma", 7F);
            this.lblDateFrom.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(140)))), ((int)(((byte)(148)))), ((int)(((byte)(165)))));
            this.lblDateFrom.Appearance.Options.UseBackColor = true;
            this.lblDateFrom.Appearance.Options.UseFont = true;
            this.lblDateFrom.Appearance.Options.UseForeColor = true;
            this.lblDateFrom.Location = new System.Drawing.Point(19, 386);
            this.lblDateFrom.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblDateFrom.Name = "lblDateFrom";
            this.lblDateFrom.Size = new System.Drawing.Size(66, 14);
            this.lblDateFrom.TabIndex = 9;
            this.lblDateFrom.Text = "DATE FROM";
            // 
            // dteDateFrom
            // 
            this.dteDateFrom.EditValue = new System.DateTime(2026, 7, 14, 0, 0, 0, 0);
            this.dteDateFrom.Location = new System.Drawing.Point(19, 405);
            this.dteDateFrom.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.dteDateFrom.Name = "dteDateFrom";
            this.dteDateFrom.Size = new System.Drawing.Size(289, 22);
            this.dteDateFrom.TabIndex = 10;
            // 
            // lblDateTo
            // 
            this.lblDateTo.Appearance.BackColor = System.Drawing.SystemColors.Control;
            this.lblDateTo.Appearance.Font = new System.Drawing.Font("Tahoma", 7F);
            this.lblDateTo.Appearance.ForeColor = DevExpress.LookAndFeel.DXSkinColors.ForeColors.ControlText;
            this.lblDateTo.Appearance.Options.UseBackColor = true;
            this.lblDateTo.Appearance.Options.UseFont = true;
            this.lblDateTo.Appearance.Options.UseForeColor = true;
            this.lblDateTo.Location = new System.Drawing.Point(19, 435);
            this.lblDateTo.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblDateTo.Name = "lblDateTo";
            this.lblDateTo.Size = new System.Drawing.Size(52, 14);
            this.lblDateTo.TabIndex = 11;
            this.lblDateTo.Text = "DATE TO";
            // 
            // dteDateTo
            // 
            this.dteDateTo.EditValue = new System.DateTime(2026, 7, 14, 0, 0, 0, 0);
            this.dteDateTo.Location = new System.Drawing.Point(19, 454);
            this.dteDateTo.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.dteDateTo.Name = "dteDateTo";
            this.dteDateTo.Size = new System.Drawing.Size(289, 22);
            this.dteDateTo.TabIndex = 12;
            // 
            // chkAllBranches
            // 
            this.chkAllBranches.Location = new System.Drawing.Point(19, 547);
            this.chkAllBranches.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.chkAllBranches.Name = "chkAllBranches";
            this.chkAllBranches.Properties.Caption = "All Branches (Pivot - one column per branch + Grand Total)";
            this.chkAllBranches.Size = new System.Drawing.Size(289, 24);
            this.chkAllBranches.TabIndex = 13;
            this.chkAllBranches.CheckedChanged += new System.EventHandler(this.chkAllBranches_CheckedChanged);
            // 
            // chkAllAccounts
            // 
            this.chkAllAccounts.Location = new System.Drawing.Point(19, 547);
            this.chkAllAccounts.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.chkAllAccounts.Name = "chkAllAccounts";
            this.chkAllAccounts.Properties.Caption = "All Accounts (ignore Account Code filter above)";
            this.chkAllAccounts.Size = new System.Drawing.Size(289, 24);
            this.chkAllAccounts.TabIndex = 14;
            this.chkAllAccounts.CheckedChanged += new System.EventHandler(this.chkAllAccounts_CheckedChanged);
            // 
            // chkIncludeZeroActivity
            // 
            this.chkIncludeZeroActivity.Location = new System.Drawing.Point(19, 547);
            this.chkIncludeZeroActivity.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.chkIncludeZeroActivity.Name = "chkIncludeZeroActivity";
            this.chkIncludeZeroActivity.Properties.Caption = "Include accounts with no activity";
            this.chkIncludeZeroActivity.Size = new System.Drawing.Size(289, 24);
            this.chkIncludeZeroActivity.TabIndex = 15;
            // 
            // rgConsolidatedMode
            // 
            this.rgConsolidatedMode.Location = new System.Drawing.Point(19, 484);
            this.rgConsolidatedMode.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.rgConsolidatedMode.Name = "rgConsolidatedMode";
            this.rgConsolidatedMode.Properties.Appearance.BackColor = System.Drawing.SystemColors.Control;
            this.rgConsolidatedMode.Properties.Appearance.ForeColor = System.Drawing.Color.Black;
            this.rgConsolidatedMode.Properties.Appearance.Options.UseBackColor = true;
            this.rgConsolidatedMode.Properties.Appearance.Options.UseForeColor = true;
            this.rgConsolidatedMode.Properties.Items.AddRange(new DevExpress.XtraEditors.Controls.RadioGroupItem[] {
            new DevExpress.XtraEditors.Controls.RadioGroupItem("TB", "Trial Balance (as-of date)"),
            new DevExpress.XtraEditors.Controls.RadioGroupItem("IS", "Income Statement (date range)")});
            this.rgConsolidatedMode.Size = new System.Drawing.Size(289, 51);
            this.rgConsolidatedMode.TabIndex = 16;
            this.rgConsolidatedMode.SelectedIndexChanged += new System.EventHandler(this.rgConsolidatedMode_SelectedIndexChanged);
            // 
            // lblDescription
            // 
            this.lblDescription.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(27)))), ((int)(((byte)(32)))), ((int)(((byte)(46)))));
            this.lblDescription.Appearance.Font = new System.Drawing.Font("Tahoma", 8F, System.Drawing.FontStyle.Italic);
            this.lblDescription.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(140)))), ((int)(((byte)(148)))), ((int)(((byte)(165)))));
            this.lblDescription.Appearance.Options.UseBackColor = true;
            this.lblDescription.Appearance.Options.UseFont = true;
            this.lblDescription.Appearance.Options.UseForeColor = true;
            this.lblDescription.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblDescription.Location = new System.Drawing.Point(12, 592);
            this.lblDescription.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblDescription.Name = "lblDescription";
            this.lblDescription.Size = new System.Drawing.Size(289, 74);
            this.lblDescription.TabIndex = 17;
            // 
            // lblSpName
            // 
            this.lblSpName.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(27)))), ((int)(((byte)(32)))), ((int)(((byte)(46)))));
            this.lblSpName.Appearance.Font = new System.Drawing.Font("Consolas", 7.5F);
            this.lblSpName.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(140)))), ((int)(((byte)(148)))), ((int)(((byte)(165)))));
            this.lblSpName.Appearance.Options.UseBackColor = true;
            this.lblSpName.Appearance.Options.UseFont = true;
            this.lblSpName.Appearance.Options.UseForeColor = true;
            this.lblSpName.Location = new System.Drawing.Point(12, 833);
            this.lblSpName.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblSpName.Name = "lblSpName";
            this.lblSpName.Size = new System.Drawing.Size(0, 15);
            this.lblSpName.TabIndex = 18;
            // 
            // btnGenerate
            // 
            this.btnGenerate.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(201)))), ((int)(((byte)(162)))), ((int)(((byte)(39)))));
            this.btnGenerate.Appearance.Font = new System.Drawing.Font("Tahoma", 9.5F, System.Drawing.FontStyle.Bold);
            this.btnGenerate.Appearance.ForeColor = System.Drawing.Color.Black;
            this.btnGenerate.Appearance.Options.UseBackColor = true;
            this.btnGenerate.Appearance.Options.UseFont = true;
            this.btnGenerate.Appearance.Options.UseForeColor = true;
            this.btnGenerate.Location = new System.Drawing.Point(12, 702);
            this.btnGenerate.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnGenerate.Name = "btnGenerate";
            this.btnGenerate.Size = new System.Drawing.Size(289, 44);
            this.btnGenerate.TabIndex = 19;
            this.btnGenerate.Text = "▶  Generate Report";
            this.btnGenerate.Click += new System.EventHandler(this.btnGenerate_Click);
            // 
            // btnExport
            // 
            this.btnExport.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(21)))), ((int)(((byte)(26)))), ((int)(((byte)(38)))));
            this.btnExport.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(230)))), ((int)(((byte)(230)))), ((int)(((byte)(235)))));
            this.btnExport.Appearance.Options.UseBackColor = true;
            this.btnExport.Appearance.Options.UseForeColor = true;
            this.btnExport.Location = new System.Drawing.Point(12, 754);
            this.btnExport.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnExport.Name = "btnExport";
            this.btnExport.Size = new System.Drawing.Size(289, 39);
            this.btnExport.TabIndex = 20;
            this.btnExport.Text = "⬇  Export to Excel";
            this.btnExport.Click += new System.EventHandler(this.btnExport_Click);
            // 
            // gridControlReport
            // 
            this.gridControlReport.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlReport.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlReport.Location = new System.Drawing.Point(2, 2);
            this.gridControlReport.MainView = this.gridViewReport;
            this.gridControlReport.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlReport.Name = "gridControlReport";
            this.gridControlReport.Size = new System.Drawing.Size(1061, 604);
            this.gridControlReport.TabIndex = 2;
            this.gridControlReport.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewReport});
            // 
            // gridViewReport
            // 
            this.gridViewReport.DetailHeight = 431;
            this.gridViewReport.GridControl = this.gridControlReport;
            this.gridViewReport.Name = "gridViewReport";
            this.gridViewReport.OptionsBehavior.Editable = false;
            this.gridViewReport.OptionsView.ShowGroupPanel = false;
            // 
            // lblSummaryCaption
            // 
            this.lblSummaryCaption.Appearance.Font = new System.Drawing.Font("Tahoma", 7.5F, System.Drawing.FontStyle.Bold);
            this.lblSummaryCaption.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(201)))), ((int)(((byte)(162)))), ((int)(((byte)(39)))));
            this.lblSummaryCaption.Appearance.Options.UseFont = true;
            this.lblSummaryCaption.Appearance.Options.UseForeColor = true;
            this.lblSummaryCaption.Location = new System.Drawing.Point(5, 6);
            this.lblSummaryCaption.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblSummaryCaption.Name = "lblSummaryCaption";
            this.lblSummaryCaption.Size = new System.Drawing.Size(66, 16);
            this.lblSummaryCaption.TabIndex = 3;
            this.lblSummaryCaption.Text = "SUMMARY";
            // 
            // gridControlSummary
            // 
            this.tablePanel1.SetColumn(this.gridControlSummary, 0);
            this.gridControlSummary.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlSummary.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlSummary.Location = new System.Drawing.Point(3, 657);
            this.gridControlSummary.MainView = this.gridViewSummary;
            this.gridControlSummary.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlSummary.Name = "gridControlSummary";
            this.tablePanel1.SetRow(this.gridControlSummary, 2);
            this.gridControlSummary.Size = new System.Drawing.Size(1065, 245);
            this.gridControlSummary.TabIndex = 4;
            this.gridControlSummary.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewSummary});
            // 
            // gridViewSummary
            // 
            this.gridViewSummary.DetailHeight = 431;
            this.gridViewSummary.GridControl = this.gridControlSummary;
            this.gridViewSummary.Name = "gridViewSummary";
            this.gridViewSummary.OptionsBehavior.Editable = false;
            this.gridViewSummary.OptionsView.ShowGroupPanel = false;
            // 
            // tablePanel1
            // 
            this.tablePanel1.Columns.AddRange(new DevExpress.Utils.Layout.TablePanelColumn[] {
            new DevExpress.Utils.Layout.TablePanelColumn(DevExpress.Utils.Layout.TablePanelEntityStyle.Relative, 36.28F)});
            this.tablePanel1.Controls.Add(this.panelControl2);
            this.tablePanel1.Controls.Add(this.gridControlSummary);
            this.tablePanel1.Controls.Add(this.panelControl1);
            this.tablePanel1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.tablePanel1.Location = new System.Drawing.Point(329, 79);
            this.tablePanel1.Name = "tablePanel1";
            this.tablePanel1.Rows.AddRange(new DevExpress.Utils.Layout.TablePanelRow[] {
            new DevExpress.Utils.Layout.TablePanelRow(DevExpress.Utils.Layout.TablePanelEntityStyle.Absolute, 613.9998F),
            new DevExpress.Utils.Layout.TablePanelRow(DevExpress.Utils.Layout.TablePanelEntityStyle.Absolute, 38.79974F),
            new DevExpress.Utils.Layout.TablePanelRow(DevExpress.Utils.Layout.TablePanelEntityStyle.Absolute, 26F)});
            this.tablePanel1.Size = new System.Drawing.Size(1071, 906);
            this.tablePanel1.TabIndex = 8;
            // 
            // panelControl2
            // 
            this.tablePanel1.SetColumn(this.panelControl2, 0);
            this.panelControl2.Controls.Add(this.lblSummaryCaption);
            this.panelControl2.Dock = System.Windows.Forms.DockStyle.Fill;
            this.panelControl2.Location = new System.Drawing.Point(3, 617);
            this.panelControl2.Name = "panelControl2";
            this.tablePanel1.SetRow(this.panelControl2, 1);
            this.panelControl2.Size = new System.Drawing.Size(1065, 33);
            this.panelControl2.TabIndex = 1;
            // 
            // panelControl1
            // 
            this.tablePanel1.SetColumn(this.panelControl1, 0);
            this.panelControl1.Controls.Add(this.gridControlReport);
            this.panelControl1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.panelControl1.Location = new System.Drawing.Point(3, 3);
            this.panelControl1.Name = "panelControl1";
            this.tablePanel1.SetRow(this.panelControl1, 0);
            this.panelControl1.Size = new System.Drawing.Size(1065, 608);
            this.panelControl1.TabIndex = 0;
            // 
            // AccountingReportsForm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.Controls.Add(this.tablePanel1);
            this.Controls.Add(this.pnlSidebar);
            this.Controls.Add(this.pnlHeader);
            this.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.Name = "AccountingReportsForm";
            this.Size = new System.Drawing.Size(1400, 985);
            this.Load += new System.EventHandler(this.AccountingReportsForm_Load);
            ((System.ComponentModel.ISupportInitialize)(this.pnlHeader)).EndInit();
            this.pnlHeader.ResumeLayout(false);
            this.pnlHeader.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pnlSidebar)).EndInit();
            this.pnlSidebar.ResumeLayout(false);
            this.pnlSidebar.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.lstReportType)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranchCode.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtAccountCode.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteAsOfDate.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteAsOfDate.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteDateFrom.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteDateFrom.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteDateTo.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteDateTo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkAllBranches.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkAllAccounts.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkIncludeZeroActivity.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.rgConsolidatedMode.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlReport)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewReport)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlSummary)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewSummary)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.tablePanel1)).EndInit();
            this.tablePanel1.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.panelControl2)).EndInit();
            this.panelControl2.ResumeLayout(false);
            this.panelControl2.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl1)).EndInit();
            this.panelControl1.ResumeLayout(false);
            this.ResumeLayout(false);

        }

        #endregion

        private DevExpress.Utils.Layout.TablePanel tablePanel1;
        private DevExpress.XtraEditors.PanelControl panelControl2;
        private DevExpress.XtraEditors.PanelControl panelControl1;
    }
}