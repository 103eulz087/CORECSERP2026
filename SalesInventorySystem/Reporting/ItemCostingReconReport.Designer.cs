namespace SalesInventorySystem.Reporting
{
    partial class ItemCostingReconReport
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        private void InitializeComponent()
        {
            this.pnlFilters = new DevExpress.XtraEditors.PanelControl();
            this.lblDateFrom = new DevExpress.XtraEditors.LabelControl();
            this.dtFrom = new DevExpress.XtraEditors.DateEdit();
            this.lblDateTo = new DevExpress.XtraEditors.LabelControl();
            this.dtTo = new DevExpress.XtraEditors.DateEdit();
            this.lblShipmentNo = new DevExpress.XtraEditors.LabelControl();
            this.cboShipmentNo = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.chkOnlyWithExpenses = new DevExpress.XtraEditors.CheckEdit();
            this.btnLoad = new DevExpress.XtraEditors.SimpleButton();
            this.btnExport = new DevExpress.XtraEditors.SimpleButton();
            this.gridRecon = new DevExpress.XtraGrid.GridControl();
            this.gridViewMaster = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.gridViewExpenses = new DevExpress.XtraGrid.Views.Grid.GridView();
            ((System.ComponentModel.ISupportInitialize)(this.pnlFilters)).BeginInit();
            this.pnlFilters.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.dtFrom.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtFrom.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtTo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtTo.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboShipmentNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkOnlyWithExpenses.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridRecon)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewMaster)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewExpenses)).BeginInit();
            this.SuspendLayout();
            // 
            // pnlFilters
            // 
            this.pnlFilters.Controls.Add(this.lblDateFrom);
            this.pnlFilters.Controls.Add(this.dtFrom);
            this.pnlFilters.Controls.Add(this.lblDateTo);
            this.pnlFilters.Controls.Add(this.dtTo);
            this.pnlFilters.Controls.Add(this.lblShipmentNo);
            this.pnlFilters.Controls.Add(this.cboShipmentNo);
            this.pnlFilters.Controls.Add(this.chkOnlyWithExpenses);
            this.pnlFilters.Controls.Add(this.btnLoad);
            this.pnlFilters.Controls.Add(this.btnExport);
            this.pnlFilters.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlFilters.Location = new System.Drawing.Point(0, 0);
            this.pnlFilters.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.pnlFilters.Name = "pnlFilters";
            this.pnlFilters.Size = new System.Drawing.Size(1342, 59);
            this.pnlFilters.TabIndex = 0;
            // 
            // lblDateFrom
            // 
            this.lblDateFrom.Location = new System.Drawing.Point(14, 21);
            this.lblDateFrom.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.lblDateFrom.Name = "lblDateFrom";
            this.lblDateFrom.Size = new System.Drawing.Size(85, 16);
            this.lblDateFrom.TabIndex = 0;
            this.lblDateFrom.Text = "PO Date From:";
            // 
            // dtFrom
            // 
            this.dtFrom.EditValue = null;
            this.dtFrom.Location = new System.Drawing.Point(103, 17);
            this.dtFrom.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.dtFrom.Name = "dtFrom";
            this.dtFrom.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.dtFrom.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.dtFrom.Properties.NullText = "(any)";
            this.dtFrom.Size = new System.Drawing.Size(122, 22);
            this.dtFrom.TabIndex = 1;
            // 
            // lblDateTo
            // 
            this.lblDateTo.Location = new System.Drawing.Point(234, 21);
            this.lblDateTo.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.lblDateTo.Name = "lblDateTo";
            this.lblDateTo.Size = new System.Drawing.Size(20, 16);
            this.lblDateTo.TabIndex = 2;
            this.lblDateTo.Text = "To:";
            // 
            // dtTo
            // 
            this.dtTo.EditValue = null;
            this.dtTo.Location = new System.Drawing.Point(260, 17);
            this.dtTo.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.dtTo.Name = "dtTo";
            this.dtTo.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.dtTo.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.dtTo.Properties.NullText = "(any)";
            this.dtTo.Size = new System.Drawing.Size(122, 22);
            this.dtTo.TabIndex = 3;
            // 
            // lblShipmentNo
            // 
            this.lblShipmentNo.Location = new System.Drawing.Point(399, 21);
            this.lblShipmentNo.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.lblShipmentNo.Name = "lblShipmentNo";
            this.lblShipmentNo.Size = new System.Drawing.Size(78, 16);
            this.lblShipmentNo.TabIndex = 4;
            this.lblShipmentNo.Text = "Shipment No:";
            // 
            // cboShipmentNo
            // 
            this.cboShipmentNo.Location = new System.Drawing.Point(482, 17);
            this.cboShipmentNo.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.cboShipmentNo.Name = "cboShipmentNo";
            this.cboShipmentNo.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo),
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Delete)});
            this.cboShipmentNo.Properties.NullText = "(all shipments)";
            this.cboShipmentNo.Size = new System.Drawing.Size(338, 22);
            this.cboShipmentNo.TabIndex = 5;
            this.cboShipmentNo.ButtonClick += new DevExpress.XtraEditors.Controls.ButtonPressedEventHandler(this.cboShipmentNo_ButtonClick);
            // 
            // chkOnlyWithExpenses
            // 
            this.chkOnlyWithExpenses.EditValue = true;
            this.chkOnlyWithExpenses.Location = new System.Drawing.Point(832, 17);
            this.chkOnlyWithExpenses.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.chkOnlyWithExpenses.Name = "chkOnlyWithExpenses";
            this.chkOnlyWithExpenses.Properties.Caption = "Only with linked expenses";
            this.chkOnlyWithExpenses.Size = new System.Drawing.Size(192, 24);
            this.chkOnlyWithExpenses.TabIndex = 6;
            // 
            // btnLoad
            // 
            this.btnLoad.Location = new System.Drawing.Point(1036, 12);
            this.btnLoad.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.btnLoad.Name = "btnLoad";
            this.btnLoad.Size = new System.Drawing.Size(105, 34);
            this.btnLoad.TabIndex = 7;
            this.btnLoad.Text = "Load";
            this.btnLoad.Click += new System.EventHandler(this.btnLoad_Click);
            // 
            // btnExport
            // 
            this.btnExport.Location = new System.Drawing.Point(1150, 12);
            this.btnExport.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.btnExport.Name = "btnExport";
            this.btnExport.Size = new System.Drawing.Size(93, 34);
            this.btnExport.TabIndex = 8;
            this.btnExport.Text = "Export";
            this.btnExport.Click += new System.EventHandler(this.btnExport_Click);
            // 
            // gridRecon
            // 
            this.gridRecon.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridRecon.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.gridRecon.Location = new System.Drawing.Point(0, 59);
            this.gridRecon.MainView = this.gridViewMaster;
            this.gridRecon.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.gridRecon.Name = "gridRecon";
            this.gridRecon.Size = new System.Drawing.Size(1342, 741);
            this.gridRecon.TabIndex = 1;
            this.gridRecon.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewMaster,
            this.gridViewExpenses});
            // 
            // gridViewMaster
            // 
            this.gridViewMaster.DetailHeight = 431;
            this.gridViewMaster.GridControl = this.gridRecon;
            this.gridViewMaster.Name = "gridViewMaster";
            this.gridViewMaster.OptionsBehavior.Editable = false;
            this.gridViewMaster.OptionsDetail.ShowDetailTabs = false;
            this.gridViewMaster.OptionsEditForm.PopupEditFormWidth = 933;
            this.gridViewMaster.OptionsPrint.ExpandAllDetails = true;
            this.gridViewMaster.OptionsPrint.PrintDetails = true;
            this.gridViewMaster.OptionsView.ShowFooter = true;
            this.gridViewMaster.OptionsView.ShowGroupPanel = false;
            this.gridViewMaster.RowCellStyle += new DevExpress.XtraGrid.Views.Grid.RowCellStyleEventHandler(this.gridViewMaster_RowCellStyle);
            // 
            // gridViewExpenses
            // 
            this.gridViewExpenses.DetailHeight = 431;
            this.gridViewExpenses.GridControl = this.gridRecon;
            this.gridViewExpenses.Name = "gridViewExpenses";
            this.gridViewExpenses.OptionsBehavior.Editable = false;
            this.gridViewExpenses.OptionsEditForm.PopupEditFormWidth = 933;
            this.gridViewExpenses.OptionsView.ShowFooter = true;
            this.gridViewExpenses.OptionsView.ShowGroupPanel = false;
            this.gridViewExpenses.ViewCaption = "Linked Expenses";
            // 
            // ItemCostingReconReport
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1342, 800);
            this.Controls.Add(this.gridRecon);
            this.Controls.Add(this.pnlFilters);
            this.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.Name = "ItemCostingReconReport";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "Item Costing Recon";
            this.WindowState = System.Windows.Forms.FormWindowState.Maximized;
            this.Load += new System.EventHandler(this.ItemCostingReconReport_Load);
            ((System.ComponentModel.ISupportInitialize)(this.pnlFilters)).EndInit();
            this.pnlFilters.ResumeLayout(false);
            this.pnlFilters.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.dtFrom.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtFrom.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtTo.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtTo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboShipmentNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.chkOnlyWithExpenses.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridRecon)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewMaster)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewExpenses)).EndInit();
            this.ResumeLayout(false);

        }

        #endregion

        private DevExpress.XtraEditors.PanelControl pnlFilters;
        private DevExpress.XtraEditors.LabelControl lblDateFrom;
        private DevExpress.XtraEditors.DateEdit dtFrom;
        private DevExpress.XtraEditors.LabelControl lblDateTo;
        private DevExpress.XtraEditors.DateEdit dtTo;
        private DevExpress.XtraEditors.LabelControl lblShipmentNo;
        private DevExpress.XtraEditors.SearchLookUpEdit cboShipmentNo;
        private DevExpress.XtraEditors.CheckEdit chkOnlyWithExpenses;
        private DevExpress.XtraEditors.SimpleButton btnLoad;
        private DevExpress.XtraEditors.SimpleButton btnExport;
        private DevExpress.XtraGrid.GridControl gridRecon;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewMaster;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewExpenses;
    }
}
