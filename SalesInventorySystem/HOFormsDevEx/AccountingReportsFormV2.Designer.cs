namespace SalesInventorySystem.HOFormsDevEx
{
    partial class AccountingReportsFormV2
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null)) components.Dispose();
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        // ── Top parameter bar (replaces the old left sidebar) ──
        private DevExpress.XtraEditors.PanelControl pnlTopParams;
        private DevExpress.XtraEditors.LabelControl lblReportTypeCaption;
        private DevExpress.XtraEditors.ComboBoxEdit cboReportType;

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
        private DevExpress.XtraEditors.LabelControl lblSpName;
        private DevExpress.XtraEditors.LabelControl lblStatus;

        private DevExpress.XtraEditors.SimpleButton btnGenerate;
        private DevExpress.XtraEditors.SimpleButton btnExport;
        private DevExpress.XtraEditors.PanelControl pnlReportArea;
        private DevExpress.XtraEditors.PanelControl pnlReportGrid;
        private DevExpress.XtraGrid.GridControl gridControlReport;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewReport;
        private DevExpress.XtraEditors.PanelControl pnlSummaryContainer;
        private DevExpress.XtraEditors.LabelControl lblSummaryCaption;
        private DevExpress.XtraGrid.GridControl gridControlSummary;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewSummary;

        private void InitializeComponent()
        {
            this.pnlTopParams = new DevExpress.XtraEditors.PanelControl();
            this.lblReportTitle = new DevExpress.XtraEditors.LabelControl();
            this.lblReportSubtitle = new DevExpress.XtraEditors.LabelControl();
            this.lblReportTypeCaption = new DevExpress.XtraEditors.LabelControl();
            this.cboReportType = new DevExpress.XtraEditors.ComboBoxEdit();
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
            this.rgConsolidatedMode = new DevExpress.XtraEditors.RadioGroup();
            this.chkAllBranches = new DevExpress.XtraEditors.CheckEdit();
            this.chkAllAccounts = new DevExpress.XtraEditors.CheckEdit();
            this.chkIncludeZeroActivity = new DevExpress.XtraEditors.CheckEdit();
            this.btnGenerate = new DevExpress.XtraEditors.SimpleButton();
            this.btnExport = new DevExpress.XtraEditors.SimpleButton();
            this.lblStatus = new DevExpress.XtraEditors.LabelControl();
            this.lblSpName = new DevExpress.XtraEditors.LabelControl();
            this.pnlReportArea = new DevExpress.XtraEditors.PanelControl();
            this.pnlReportGrid = new DevExpress.XtraEditors.PanelControl();
            this.gridControlReport = new DevExpress.XtraGrid.GridControl();
            this.gridViewReport = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.pnlSummaryContainer = new DevExpress.XtraEditors.PanelControl();
            this.gridControlSummary = new DevExpress.XtraGrid.GridControl();
            this.gridViewSummary = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.lblSummaryCaption = new DevExpress.XtraEditors.LabelControl();
            ((System.ComponentModel.ISupportInitialize)(this.pnlTopParams)).BeginInit();
            this.pnlTopParams.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.cboReportType.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranchCode.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtAccountCode.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteAsOfDate.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteAsOfDate.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteDateFrom.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteDateFrom.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteDateTo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteDateTo.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.rgConsolidatedMode.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkAllBranches.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkAllAccounts.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkIncludeZeroActivity.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlReportArea)).BeginInit();
            this.pnlReportArea.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pnlReportGrid)).BeginInit();
            this.pnlReportGrid.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlReport)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewReport)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlSummaryContainer)).BeginInit();
            this.pnlSummaryContainer.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlSummary)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewSummary)).BeginInit();
            this.SuspendLayout();
            // 
            // pnlTopParams
            // 
            this.pnlTopParams.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(34)))), ((int)(((byte)(40)))), ((int)(((byte)(56)))));
            this.pnlTopParams.Appearance.Options.UseBackColor = true;
            this.pnlTopParams.Controls.Add(this.lblReportTitle);
            this.pnlTopParams.Controls.Add(this.lblReportSubtitle);
            this.pnlTopParams.Controls.Add(this.lblReportTypeCaption);
            this.pnlTopParams.Controls.Add(this.cboReportType);
            this.pnlTopParams.Controls.Add(this.lblBranchCode);
            this.pnlTopParams.Controls.Add(this.cboBranchCode);
            this.pnlTopParams.Controls.Add(this.lblAccountCode);
            this.pnlTopParams.Controls.Add(this.txtAccountCode);
            this.pnlTopParams.Controls.Add(this.lblAsOfDate);
            this.pnlTopParams.Controls.Add(this.dteAsOfDate);
            this.pnlTopParams.Controls.Add(this.lblDateFrom);
            this.pnlTopParams.Controls.Add(this.dteDateFrom);
            this.pnlTopParams.Controls.Add(this.lblDateTo);
            this.pnlTopParams.Controls.Add(this.dteDateTo);
            this.pnlTopParams.Controls.Add(this.rgConsolidatedMode);
            this.pnlTopParams.Controls.Add(this.chkAllBranches);
            this.pnlTopParams.Controls.Add(this.chkAllAccounts);
            this.pnlTopParams.Controls.Add(this.chkIncludeZeroActivity);
            this.pnlTopParams.Controls.Add(this.btnGenerate);
            this.pnlTopParams.Controls.Add(this.btnExport);
            this.pnlTopParams.Controls.Add(this.lblStatus);
            this.pnlTopParams.Controls.Add(this.lblSpName);
            this.pnlTopParams.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlTopParams.Location = new System.Drawing.Point(0, 0);
            this.pnlTopParams.Name = "pnlTopParams";
            this.pnlTopParams.Size = new System.Drawing.Size(1398, 107);
            this.pnlTopParams.TabIndex = 1;
            // 
            // lblReportTitle
            // 
            this.lblReportTitle.Appearance.Font = new System.Drawing.Font("Tahoma", 14F, System.Drawing.FontStyle.Bold);
            this.lblReportTitle.Appearance.ForeColor = System.Drawing.Color.Black;
            this.lblReportTitle.Appearance.Options.UseFont = true;
            this.lblReportTitle.Appearance.Options.UseForeColor = true;
            this.lblReportTitle.Location = new System.Drawing.Point(983, 8);
            this.lblReportTitle.Name = "lblReportTitle";
            this.lblReportTitle.Size = new System.Drawing.Size(123, 23);
            this.lblReportTitle.TabIndex = 21;
            this.lblReportTitle.Text = "Trial Balance";
            // 
            // lblReportSubtitle
            // 
            this.lblReportSubtitle.Appearance.Font = new System.Drawing.Font("Tahoma", 8.5F);
            this.lblReportSubtitle.Appearance.ForeColor = System.Drawing.SystemColors.GrayText;
            this.lblReportSubtitle.Appearance.Options.UseFont = true;
            this.lblReportSubtitle.Appearance.Options.UseForeColor = true;
            this.lblReportSubtitle.Location = new System.Drawing.Point(983, 36);
            this.lblReportSubtitle.Name = "lblReportSubtitle";
            this.lblReportSubtitle.Size = new System.Drawing.Size(178, 13);
            this.lblReportSubtitle.TabIndex = 22;
            this.lblReportSubtitle.Text = "Select parameters and click Generate";
            // 
            // lblReportTypeCaption
            // 
            this.lblReportTypeCaption.Appearance.Font = new System.Drawing.Font("Tahoma", 7.5F, System.Drawing.FontStyle.Bold);
            this.lblReportTypeCaption.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(64)))), ((int)(((byte)(64)))), ((int)(((byte)(64)))));
            this.lblReportTypeCaption.Appearance.Options.UseFont = true;
            this.lblReportTypeCaption.Appearance.Options.UseForeColor = true;
            this.lblReportTypeCaption.Location = new System.Drawing.Point(14, 8);
            this.lblReportTypeCaption.Name = "lblReportTypeCaption";
            this.lblReportTypeCaption.Size = new System.Drawing.Size(72, 12);
            this.lblReportTypeCaption.TabIndex = 0;
            this.lblReportTypeCaption.Text = "REPORT TYPE";
            // 
            // cboReportType
            // 
            this.cboReportType.Location = new System.Drawing.Point(14, 23);
            this.cboReportType.Name = "cboReportType";
            this.cboReportType.Properties.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;
            this.cboReportType.Size = new System.Drawing.Size(228, 20);
            this.cboReportType.TabIndex = 1;
            this.cboReportType.SelectedIndexChanged += new System.EventHandler(this.cboReportType_SelectedIndexChanged);
            // 
            // lblBranchCode
            // 
            this.lblBranchCode.Appearance.Font = new System.Drawing.Font("Tahoma", 7F);
            this.lblBranchCode.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(64)))), ((int)(((byte)(64)))), ((int)(((byte)(64)))));
            this.lblBranchCode.Appearance.Options.UseFont = true;
            this.lblBranchCode.Appearance.Options.UseForeColor = true;
            this.lblBranchCode.Location = new System.Drawing.Point(256, 8);
            this.lblBranchCode.Name = "lblBranchCode";
            this.lblBranchCode.Size = new System.Drawing.Size(71, 11);
            this.lblBranchCode.TabIndex = 2;
            this.lblBranchCode.Text = "BRANCH CODE";
            // 
            // cboBranchCode
            // 
            this.cboBranchCode.Location = new System.Drawing.Point(256, 23);
            this.cboBranchCode.Name = "cboBranchCode";
            this.cboBranchCode.Properties.NullText = "";
            this.cboBranchCode.Size = new System.Drawing.Size(170, 20);
            this.cboBranchCode.TabIndex = 3;
            // 
            // lblAccountCode
            // 
            this.lblAccountCode.Appearance.Font = new System.Drawing.Font("Tahoma", 7F);
            this.lblAccountCode.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(64)))), ((int)(((byte)(64)))), ((int)(((byte)(64)))));
            this.lblAccountCode.Appearance.Options.UseFont = true;
            this.lblAccountCode.Appearance.Options.UseForeColor = true;
            this.lblAccountCode.Location = new System.Drawing.Point(438, 8);
            this.lblAccountCode.Name = "lblAccountCode";
            this.lblAccountCode.Size = new System.Drawing.Size(80, 11);
            this.lblAccountCode.TabIndex = 4;
            this.lblAccountCode.Text = "ACCOUNT CODE";
            // 
            // txtAccountCode
            // 
            this.txtAccountCode.Location = new System.Drawing.Point(438, 23);
            this.txtAccountCode.Name = "txtAccountCode";
            this.txtAccountCode.Properties.NullText = "";
            this.txtAccountCode.Size = new System.Drawing.Size(200, 20);
            this.txtAccountCode.TabIndex = 5;
            // 
            // lblAsOfDate
            // 
            this.lblAsOfDate.Appearance.Font = new System.Drawing.Font("Tahoma", 7F);
            this.lblAsOfDate.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(64)))), ((int)(((byte)(64)))), ((int)(((byte)(64)))));
            this.lblAsOfDate.Appearance.Options.UseFont = true;
            this.lblAsOfDate.Appearance.Options.UseForeColor = true;
            this.lblAsOfDate.Location = new System.Drawing.Point(658, 8);
            this.lblAsOfDate.Name = "lblAsOfDate";
            this.lblAsOfDate.Size = new System.Drawing.Size(59, 11);
            this.lblAsOfDate.TabIndex = 6;
            this.lblAsOfDate.Text = "AS-OF DATE";
            // 
            // dteAsOfDate
            // 
            this.dteAsOfDate.EditValue = null;
            this.dteAsOfDate.Location = new System.Drawing.Point(658, 23);
            this.dteAsOfDate.Name = "dteAsOfDate";
            this.dteAsOfDate.Size = new System.Drawing.Size(150, 20);
            this.dteAsOfDate.TabIndex = 7;
            // 
            // lblDateFrom
            // 
            this.lblDateFrom.Appearance.Font = new System.Drawing.Font("Tahoma", 7F);
            this.lblDateFrom.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(140)))), ((int)(((byte)(148)))), ((int)(((byte)(165)))));
            this.lblDateFrom.Appearance.Options.UseFont = true;
            this.lblDateFrom.Appearance.Options.UseForeColor = true;
            this.lblDateFrom.Location = new System.Drawing.Point(658, 8);
            this.lblDateFrom.Name = "lblDateFrom";
            this.lblDateFrom.Size = new System.Drawing.Size(57, 11);
            this.lblDateFrom.TabIndex = 8;
            this.lblDateFrom.Text = "DATE FROM";
            // 
            // dteDateFrom
            // 
            this.dteDateFrom.EditValue = null;
            this.dteDateFrom.Location = new System.Drawing.Point(658, 23);
            this.dteDateFrom.Name = "dteDateFrom";
            this.dteDateFrom.Size = new System.Drawing.Size(150, 20);
            this.dteDateFrom.TabIndex = 9;
            // 
            // lblDateTo
            // 
            this.lblDateTo.Appearance.Font = new System.Drawing.Font("Tahoma", 7F);
            this.lblDateTo.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(64)))), ((int)(((byte)(64)))), ((int)(((byte)(64)))));
            this.lblDateTo.Appearance.Options.UseFont = true;
            this.lblDateTo.Appearance.Options.UseForeColor = true;
            this.lblDateTo.Location = new System.Drawing.Point(818, 8);
            this.lblDateTo.Name = "lblDateTo";
            this.lblDateTo.Size = new System.Drawing.Size(43, 11);
            this.lblDateTo.TabIndex = 10;
            this.lblDateTo.Text = "DATE TO";
            // 
            // dteDateTo
            // 
            this.dteDateTo.EditValue = null;
            this.dteDateTo.Location = new System.Drawing.Point(818, 23);
            this.dteDateTo.Name = "dteDateTo";
            this.dteDateTo.Size = new System.Drawing.Size(150, 20);
            this.dteDateTo.TabIndex = 11;
            // 
            // rgConsolidatedMode
            // 
            this.rgConsolidatedMode.Location = new System.Drawing.Point(256, 47);
            this.rgConsolidatedMode.Name = "rgConsolidatedMode";
            this.rgConsolidatedMode.Properties.Appearance.ForeColor = System.Drawing.Color.Black;
            this.rgConsolidatedMode.Properties.Appearance.Options.UseForeColor = true;
            this.rgConsolidatedMode.Properties.Items.AddRange(new DevExpress.XtraEditors.Controls.RadioGroupItem[] {
            new DevExpress.XtraEditors.Controls.RadioGroupItem("TB", "Trial Balance (as-of date)"),
            new DevExpress.XtraEditors.Controls.RadioGroupItem("IS", "Income Statement (date range)")});
            this.rgConsolidatedMode.Size = new System.Drawing.Size(367, 27);
            this.rgConsolidatedMode.TabIndex = 12;
            this.rgConsolidatedMode.SelectedIndexChanged += new System.EventHandler(this.rgConsolidatedMode_SelectedIndexChanged);
            // 
            // chkAllBranches
            // 
            this.chkAllBranches.Location = new System.Drawing.Point(14, 54);
            this.chkAllBranches.Name = "chkAllBranches";
            this.chkAllBranches.Properties.Appearance.ForeColor = System.Drawing.Color.Black;
            this.chkAllBranches.Properties.Appearance.Options.UseForeColor = true;
            this.chkAllBranches.Properties.Caption = "All Branches";
            this.chkAllBranches.Size = new System.Drawing.Size(86, 20);
            this.chkAllBranches.TabIndex = 13;
            this.chkAllBranches.CheckedChanged += new System.EventHandler(this.chkAllBranches_CheckedChanged);
            // 
            // chkAllAccounts
            // 
            this.chkAllAccounts.Location = new System.Drawing.Point(14, 76);
            this.chkAllAccounts.Name = "chkAllAccounts";
            this.chkAllAccounts.Properties.Appearance.ForeColor = System.Drawing.Color.Black;
            this.chkAllAccounts.Properties.Appearance.Options.UseForeColor = true;
            this.chkAllAccounts.Properties.Caption = "All Accounts (ignore Account Code filter above)";
            this.chkAllAccounts.Size = new System.Drawing.Size(261, 20);
            this.chkAllAccounts.TabIndex = 14;
            this.chkAllAccounts.CheckedChanged += new System.EventHandler(this.chkAllAccounts_CheckedChanged);
            // 
            // chkIncludeZeroActivity
            // 
            this.chkIncludeZeroActivity.Location = new System.Drawing.Point(281, 76);
            this.chkIncludeZeroActivity.Name = "chkIncludeZeroActivity";
            this.chkIncludeZeroActivity.Properties.Appearance.ForeColor = System.Drawing.Color.Black;
            this.chkIncludeZeroActivity.Properties.Appearance.Options.UseForeColor = true;
            this.chkIncludeZeroActivity.Properties.Caption = "Include accounts with no activity";
            this.chkIncludeZeroActivity.Size = new System.Drawing.Size(208, 20);
            this.chkIncludeZeroActivity.TabIndex = 15;
            // 
            // btnGenerate
            // 
            this.btnGenerate.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(201)))), ((int)(((byte)(162)))), ((int)(((byte)(39)))));
            this.btnGenerate.Appearance.Font = new System.Drawing.Font("Tahoma", 9.5F, System.Drawing.FontStyle.Bold);
            this.btnGenerate.Appearance.ForeColor = System.Drawing.Color.Black;
            this.btnGenerate.Appearance.Options.UseBackColor = true;
            this.btnGenerate.Appearance.Options.UseFont = true;
            this.btnGenerate.Appearance.Options.UseForeColor = true;
            this.btnGenerate.Location = new System.Drawing.Point(658, 47);
            this.btnGenerate.Name = "btnGenerate";
            this.btnGenerate.Size = new System.Drawing.Size(150, 32);
            this.btnGenerate.TabIndex = 16;
            this.btnGenerate.Text = "▶  Generate Report";
            this.btnGenerate.Click += new System.EventHandler(this.btnGenerate_Click);
            // 
            // btnExport
            // 
            this.btnExport.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(21)))), ((int)(((byte)(26)))), ((int)(((byte)(38)))));
            this.btnExport.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(230)))), ((int)(((byte)(230)))), ((int)(((byte)(235)))));
            this.btnExport.Appearance.Options.UseBackColor = true;
            this.btnExport.Appearance.Options.UseForeColor = true;
            this.btnExport.Location = new System.Drawing.Point(818, 47);
            this.btnExport.Name = "btnExport";
            this.btnExport.Size = new System.Drawing.Size(150, 32);
            this.btnExport.TabIndex = 17;
            this.btnExport.Text = "⬇  Export (PDF/Excel)";
            this.btnExport.Click += new System.EventHandler(this.btnExport_Click);
            // 
            // lblStatus
            // 
            this.lblStatus.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(140)))), ((int)(((byte)(148)))), ((int)(((byte)(165)))));
            this.lblStatus.Appearance.Options.UseForeColor = true;
            this.lblStatus.Location = new System.Drawing.Point(834, 83);
            this.lblStatus.Name = "lblStatus";
            this.lblStatus.Size = new System.Drawing.Size(31, 13);
            this.lblStatus.TabIndex = 18;
            this.lblStatus.Text = "Ready";
            // 
            // lblSpName
            // 
            this.lblSpName.Appearance.Font = new System.Drawing.Font("Consolas", 7.5F);
            this.lblSpName.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(90)))), ((int)(((byte)(96)))), ((int)(((byte)(110)))));
            this.lblSpName.Appearance.Options.UseFont = true;
            this.lblSpName.Appearance.Options.UseForeColor = true;
            this.lblSpName.Location = new System.Drawing.Point(14, 122);
            this.lblSpName.Name = "lblSpName";
            this.lblSpName.Size = new System.Drawing.Size(0, 12);
            this.lblSpName.TabIndex = 20;
            // 
            // pnlReportArea
            // 
            this.pnlReportArea.Controls.Add(this.pnlReportGrid);
            this.pnlReportArea.Controls.Add(this.pnlSummaryContainer);
            this.pnlReportArea.Dock = System.Windows.Forms.DockStyle.Fill;
            this.pnlReportArea.Location = new System.Drawing.Point(0, 107);
            this.pnlReportArea.Name = "pnlReportArea";
            this.pnlReportArea.Size = new System.Drawing.Size(1398, 661);
            this.pnlReportArea.TabIndex = 2;
            // 
            // pnlReportGrid
            // 
            this.pnlReportGrid.Controls.Add(this.gridControlReport);
            this.pnlReportGrid.Dock = System.Windows.Forms.DockStyle.Fill;
            this.pnlReportGrid.Location = new System.Drawing.Point(2, 2);
            this.pnlReportGrid.Name = "pnlReportGrid";
            this.pnlReportGrid.Size = new System.Drawing.Size(1394, 437);
            this.pnlReportGrid.TabIndex = 0;
            // 
            // gridControlReport
            // 
            this.gridControlReport.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlReport.Location = new System.Drawing.Point(2, 2);
            this.gridControlReport.MainView = this.gridViewReport;
            this.gridControlReport.Name = "gridControlReport";
            this.gridControlReport.Size = new System.Drawing.Size(1390, 433);
            this.gridControlReport.TabIndex = 0;
            this.gridControlReport.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewReport});
            // 
            // gridViewReport
            // 
            this.gridViewReport.GridControl = this.gridControlReport;
            this.gridViewReport.Name = "gridViewReport";
            this.gridViewReport.OptionsBehavior.Editable = false;
            this.gridViewReport.OptionsEditForm.PopupEditFormWidth = 686;
            this.gridViewReport.OptionsView.ShowGroupPanel = false;
            // 
            // pnlSummaryContainer
            // 
            this.pnlSummaryContainer.Controls.Add(this.gridControlSummary);
            this.pnlSummaryContainer.Controls.Add(this.lblSummaryCaption);
            this.pnlSummaryContainer.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.pnlSummaryContainer.Location = new System.Drawing.Point(2, 439);
            this.pnlSummaryContainer.Name = "pnlSummaryContainer";
            this.pnlSummaryContainer.Size = new System.Drawing.Size(1394, 220);
            this.pnlSummaryContainer.TabIndex = 1;
            // 
            // gridControlSummary
            // 
            this.gridControlSummary.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlSummary.Location = new System.Drawing.Point(2, 26);
            this.gridControlSummary.MainView = this.gridViewSummary;
            this.gridControlSummary.Name = "gridControlSummary";
            this.gridControlSummary.Size = new System.Drawing.Size(1390, 192);
            this.gridControlSummary.TabIndex = 1;
            this.gridControlSummary.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewSummary});
            // 
            // gridViewSummary
            // 
            this.gridViewSummary.GridControl = this.gridControlSummary;
            this.gridViewSummary.Name = "gridViewSummary";
            this.gridViewSummary.OptionsBehavior.Editable = false;
            this.gridViewSummary.OptionsEditForm.PopupEditFormWidth = 686;
            this.gridViewSummary.OptionsView.ShowGroupPanel = false;
            // 
            // lblSummaryCaption
            // 
            this.lblSummaryCaption.Appearance.Font = new System.Drawing.Font("Tahoma", 7.5F, System.Drawing.FontStyle.Bold);
            this.lblSummaryCaption.Appearance.ForeColor = System.Drawing.Color.FromArgb(((int)(((byte)(201)))), ((int)(((byte)(162)))), ((int)(((byte)(39)))));
            this.lblSummaryCaption.Appearance.Options.UseFont = true;
            this.lblSummaryCaption.Appearance.Options.UseForeColor = true;
            this.lblSummaryCaption.Dock = System.Windows.Forms.DockStyle.Top;
            this.lblSummaryCaption.Location = new System.Drawing.Point(2, 2);
            this.lblSummaryCaption.Name = "lblSummaryCaption";
            this.lblSummaryCaption.Padding = new System.Windows.Forms.Padding(2, 6, 2, 6);
            this.lblSummaryCaption.Size = new System.Drawing.Size(57, 24);
            this.lblSummaryCaption.TabIndex = 0;
            this.lblSummaryCaption.Text = "SUMMARY";
            // 
            // AccountingReportsFormV2
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1398, 768);
            this.Controls.Add(this.pnlReportArea);
            this.Controls.Add(this.pnlTopParams);
            this.Name = "AccountingReportsFormV2";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "Financial Report";
            this.WindowState = System.Windows.Forms.FormWindowState.Maximized;
            this.Load += new System.EventHandler(this.AccountingReportsFormV2_Load);
            ((System.ComponentModel.ISupportInitialize)(this.pnlTopParams)).EndInit();
            this.pnlTopParams.ResumeLayout(false);
            this.pnlTopParams.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.cboReportType.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranchCode.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtAccountCode.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteAsOfDate.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteAsOfDate.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteDateFrom.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteDateFrom.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteDateTo.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dteDateTo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.rgConsolidatedMode.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkAllBranches.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkAllAccounts.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkIncludeZeroActivity.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlReportArea)).EndInit();
            this.pnlReportArea.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.pnlReportGrid)).EndInit();
            this.pnlReportGrid.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlReport)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewReport)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlSummaryContainer)).EndInit();
            this.pnlSummaryContainer.ResumeLayout(false);
            this.pnlSummaryContainer.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlSummary)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewSummary)).EndInit();
            this.ResumeLayout(false);

        }

        #endregion

        private DevExpress.XtraEditors.LabelControl lblReportTitle;
        private DevExpress.XtraEditors.LabelControl lblReportSubtitle;
    }
}
