namespace SalesInventorySystem.Reporting
{
    partial class InventoryReport
    {
        /// <summary>
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary>
        /// Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            this.pnlFilters = new DevExpress.XtraEditors.PanelControl();
            this.btnExport = new DevExpress.XtraEditors.SimpleButton();
            this.btnLoad = new DevExpress.XtraEditors.SimpleButton();
            this.chkStockOnly = new DevExpress.XtraEditors.CheckEdit();
            this.lblTo = new DevExpress.XtraEditors.LabelControl();
            this.dtTo = new DevExpress.XtraEditors.DateEdit();
            this.lblFrom = new DevExpress.XtraEditors.LabelControl();
            this.dtFrom = new DevExpress.XtraEditors.DateEdit();
            this.lblConversion = new DevExpress.XtraEditors.LabelControl();
            this.cmbConversion = new DevExpress.XtraEditors.ComboBoxEdit();
            this.lblLocation = new DevExpress.XtraEditors.LabelControl();
            this.cmbLocation = new DevExpress.XtraEditors.ComboBoxEdit();
            this.lblBranch = new DevExpress.XtraEditors.LabelControl();
            this.cmbBranch = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.tabViews = new DevExpress.XtraTab.XtraTabControl();
            this.tabSummary = new DevExpress.XtraTab.XtraTabPage();
            this.gridSummary = new DevExpress.XtraGrid.GridControl();
            this.viewSummary = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.tabDetail = new DevExpress.XtraTab.XtraTabPage();
            this.gridDetail = new DevExpress.XtraGrid.GridControl();
            this.viewDetail = new DevExpress.XtraGrid.Views.Grid.GridView();
            ((System.ComponentModel.ISupportInitialize)(this.pnlFilters)).BeginInit();
            this.pnlFilters.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.chkStockOnly.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtTo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtTo.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtFrom.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtFrom.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbConversion.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbLocation.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbBranch.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.tabViews)).BeginInit();
            this.tabViews.SuspendLayout();
            this.tabSummary.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridSummary)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.viewSummary)).BeginInit();
            this.tabDetail.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridDetail)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.viewDetail)).BeginInit();
            this.SuspendLayout();
            //
            // pnlFilters
            //
            this.pnlFilters.Controls.Add(this.btnExport);
            this.pnlFilters.Controls.Add(this.btnLoad);
            this.pnlFilters.Controls.Add(this.chkStockOnly);
            this.pnlFilters.Controls.Add(this.lblTo);
            this.pnlFilters.Controls.Add(this.dtTo);
            this.pnlFilters.Controls.Add(this.lblFrom);
            this.pnlFilters.Controls.Add(this.dtFrom);
            this.pnlFilters.Controls.Add(this.lblConversion);
            this.pnlFilters.Controls.Add(this.cmbConversion);
            this.pnlFilters.Controls.Add(this.lblLocation);
            this.pnlFilters.Controls.Add(this.cmbLocation);
            this.pnlFilters.Controls.Add(this.lblBranch);
            this.pnlFilters.Controls.Add(this.cmbBranch);
            this.pnlFilters.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlFilters.Location = new System.Drawing.Point(0, 0);
            this.pnlFilters.Name = "pnlFilters";
            this.pnlFilters.Size = new System.Drawing.Size(1100, 72);
            this.pnlFilters.TabIndex = 0;
            //
            // lblBranch
            //
            this.lblBranch.Location = new System.Drawing.Point(10, 10);
            this.lblBranch.Name = "lblBranch";
            this.lblBranch.Size = new System.Drawing.Size(37, 13);
            this.lblBranch.TabIndex = 0;
            this.lblBranch.Text = "Branch:";
            //
            // cmbBranch
            //
            this.cmbBranch.Location = new System.Drawing.Point(65, 8);
            this.cmbBranch.Name = "cmbBranch";
            // Known Bug Pattern #2: DisableTextEditor -- must only accept a picked branch,
            // never free-typed text that could bypass ValueMember.
            this.cmbBranch.Properties.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;
            this.cmbBranch.Properties.NullText = "(All Branches)";
            this.cmbBranch.Size = new System.Drawing.Size(220, 24);
            this.cmbBranch.TabIndex = 1;
            this.cmbBranch.EditValueChanged += new System.EventHandler(this.cmbBranch_EditValueChanged);
            //
            // lblLocation
            //
            this.lblLocation.Location = new System.Drawing.Point(295, 10);
            this.lblLocation.Name = "lblLocation";
            this.lblLocation.Size = new System.Drawing.Size(48, 13);
            this.lblLocation.TabIndex = 2;
            this.lblLocation.Text = "Location:";
            //
            // cmbLocation
            //
            this.cmbLocation.Location = new System.Drawing.Point(357, 8);
            this.cmbLocation.Name = "cmbLocation";
            this.cmbLocation.Properties.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;
            this.cmbLocation.Properties.Items.AddRange(new object[] {
            "All",
            "Warehouse",
            "Third-Party Storage"});
            this.cmbLocation.Size = new System.Drawing.Size(150, 24);
            this.cmbLocation.TabIndex = 3;
            //
            // lblConversion
            //
            this.lblConversion.Location = new System.Drawing.Point(517, 10);
            this.lblConversion.Name = "lblConversion";
            this.lblConversion.Size = new System.Drawing.Size(60, 13);
            this.lblConversion.TabIndex = 4;
            this.lblConversion.Text = "Conversion:";
            //
            // cmbConversion
            //
            this.cmbConversion.Location = new System.Drawing.Point(592, 8);
            this.cmbConversion.Name = "cmbConversion";
            this.cmbConversion.Properties.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;
            this.cmbConversion.Properties.Items.AddRange(new object[] {
            "All",
            "Converted Only",
            "Original/Unconverted Only"});
            this.cmbConversion.Size = new System.Drawing.Size(180, 24);
            this.cmbConversion.TabIndex = 5;
            //
            // lblFrom
            //
            this.lblFrom.Location = new System.Drawing.Point(777, 10);
            this.lblFrom.Name = "lblFrom";
            this.lblFrom.Size = new System.Drawing.Size(28, 13);
            this.lblFrom.TabIndex = 6;
            this.lblFrom.Text = "From:";
            //
            // dtFrom
            //
            this.dtFrom.EditValue = null;
            this.dtFrom.Location = new System.Drawing.Point(819, 8);
            this.dtFrom.Name = "dtFrom";
            this.dtFrom.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.dtFrom.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton()});
            this.dtFrom.Size = new System.Drawing.Size(95, 24);
            this.dtFrom.TabIndex = 7;
            //
            // lblTo
            //
            this.lblTo.Location = new System.Drawing.Point(922, 10);
            this.lblTo.Name = "lblTo";
            this.lblTo.Size = new System.Drawing.Size(14, 13);
            this.lblTo.TabIndex = 8;
            this.lblTo.Text = "To:";
            //
            // dtTo
            //
            this.dtTo.EditValue = null;
            this.dtTo.Location = new System.Drawing.Point(947, 8);
            this.dtTo.Name = "dtTo";
            this.dtTo.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.dtTo.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton()});
            this.dtTo.Size = new System.Drawing.Size(95, 24);
            this.dtTo.TabIndex = 9;
            //
            // chkStockOnly
            //
            this.chkStockOnly.Location = new System.Drawing.Point(10, 40);
            this.chkStockOnly.Name = "chkStockOnly";
            this.chkStockOnly.Properties.Caption = "Active Stock Only";
            this.chkStockOnly.Size = new System.Drawing.Size(150, 22);
            this.chkStockOnly.TabIndex = 10;
            //
            // btnLoad
            //
            this.btnLoad.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(180)))), ((int)(((byte)(140)))), ((int)(((byte)(20)))));
            this.btnLoad.Appearance.Options.UseBackColor = true;
            this.btnLoad.Location = new System.Drawing.Point(170, 38);
            this.btnLoad.Name = "btnLoad";
            this.btnLoad.Size = new System.Drawing.Size(90, 28);
            this.btnLoad.TabIndex = 11;
            this.btnLoad.Text = "Load";
            this.btnLoad.Click += new System.EventHandler(this.btnLoad_Click);
            //
            // btnExport
            //
            this.btnExport.Location = new System.Drawing.Point(270, 38);
            this.btnExport.Name = "btnExport";
            this.btnExport.Size = new System.Drawing.Size(110, 28);
            this.btnExport.TabIndex = 12;
            this.btnExport.Text = "Export to Excel";
            this.btnExport.Click += new System.EventHandler(this.btnExport_Click);
            //
            // tabViews
            //
            this.tabViews.Dock = System.Windows.Forms.DockStyle.Fill;
            this.tabViews.Location = new System.Drawing.Point(0, 72);
            this.tabViews.Name = "tabViews";
            this.tabViews.SelectedTabPage = this.tabSummary;
            this.tabViews.Size = new System.Drawing.Size(1100, 578);
            this.tabViews.TabIndex = 1;
            this.tabViews.TabPages.AddRange(new DevExpress.XtraTab.XtraTabPage[] {
            this.tabSummary,
            this.tabDetail});
            //
            // tabSummary
            //
            this.tabSummary.Controls.Add(this.gridSummary);
            this.tabSummary.Name = "tabSummary";
            this.tabSummary.Size = new System.Drawing.Size(1093, 550);
            this.tabSummary.Text = "Summary";
            //
            // gridSummary
            //
            this.gridSummary.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridSummary.Location = new System.Drawing.Point(0, 0);
            this.gridSummary.MainView = this.viewSummary;
            this.gridSummary.Name = "gridSummary";
            this.gridSummary.Size = new System.Drawing.Size(1093, 550);
            this.gridSummary.TabIndex = 0;
            this.gridSummary.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.viewSummary});
            //
            // viewSummary
            //
            this.viewSummary.GridControl = this.gridSummary;
            this.viewSummary.Name = "viewSummary";
            this.viewSummary.OptionsBehavior.Editable = false;
            this.viewSummary.OptionsView.ShowFooter = true;
            this.viewSummary.OptionsView.ShowGroupPanel = false;
            //
            // tabDetail
            //
            this.tabDetail.Controls.Add(this.gridDetail);
            this.tabDetail.Name = "tabDetail";
            this.tabDetail.Size = new System.Drawing.Size(1093, 550);
            this.tabDetail.Text = "Detail";
            //
            // gridDetail
            //
            this.gridDetail.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridDetail.Location = new System.Drawing.Point(0, 0);
            this.gridDetail.MainView = this.viewDetail;
            this.gridDetail.Name = "gridDetail";
            this.gridDetail.Size = new System.Drawing.Size(1093, 550);
            this.gridDetail.TabIndex = 0;
            this.gridDetail.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.viewDetail});
            //
            // viewDetail
            //
            this.viewDetail.GridControl = this.gridDetail;
            this.viewDetail.Name = "viewDetail";
            this.viewDetail.OptionsBehavior.Editable = false;
            this.viewDetail.OptionsView.ShowFooter = true;
            this.viewDetail.OptionsView.ShowGroupPanel = false;
            //
            // InventoryReport
            //
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1100, 650);
            this.Controls.Add(this.tabViews);
            this.Controls.Add(this.pnlFilters);
            this.Name = "InventoryReport";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "Inventory Report";
            this.WindowState = System.Windows.Forms.FormWindowState.Maximized;
            this.Load += new System.EventHandler(this.InventoryReport_Load);
            ((System.ComponentModel.ISupportInitialize)(this.pnlFilters)).EndInit();
            this.pnlFilters.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.chkStockOnly.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtTo.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtTo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtFrom.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtFrom.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbConversion.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbLocation.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbBranch.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.tabViews)).EndInit();
            this.tabViews.ResumeLayout(false);
            this.tabSummary.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridSummary)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.viewSummary)).EndInit();
            this.tabDetail.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridDetail)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.viewDetail)).EndInit();
            this.ResumeLayout(false);

        }

        #endregion

        private DevExpress.XtraEditors.PanelControl pnlFilters;
        private DevExpress.XtraEditors.LabelControl lblBranch;
        private DevExpress.XtraEditors.SearchLookUpEdit cmbBranch;
        private DevExpress.XtraEditors.LabelControl lblLocation;
        private DevExpress.XtraEditors.ComboBoxEdit cmbLocation;
        private DevExpress.XtraEditors.LabelControl lblConversion;
        private DevExpress.XtraEditors.ComboBoxEdit cmbConversion;
        private DevExpress.XtraEditors.LabelControl lblFrom;
        private DevExpress.XtraEditors.DateEdit dtFrom;
        private DevExpress.XtraEditors.LabelControl lblTo;
        private DevExpress.XtraEditors.DateEdit dtTo;
        private DevExpress.XtraEditors.CheckEdit chkStockOnly;
        private DevExpress.XtraEditors.SimpleButton btnLoad;
        private DevExpress.XtraEditors.SimpleButton btnExport;
        private DevExpress.XtraTab.XtraTabControl tabViews;
        private DevExpress.XtraTab.XtraTabPage tabSummary;
        private DevExpress.XtraTab.XtraTabPage tabDetail;
        private DevExpress.XtraGrid.GridControl gridSummary;
        private DevExpress.XtraGrid.Views.Grid.GridView viewSummary;
        private DevExpress.XtraGrid.GridControl gridDetail;
        private DevExpress.XtraGrid.Views.Grid.GridView viewDetail;
    }
}
