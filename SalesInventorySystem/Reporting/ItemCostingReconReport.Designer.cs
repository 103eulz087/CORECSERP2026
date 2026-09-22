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
            this.btnExport = new DevExpress.XtraEditors.SimpleButton();
            this.btnLoad = new DevExpress.XtraEditors.SimpleButton();
            this.lblShipmentNo = new DevExpress.XtraEditors.LabelControl();
            this.cboShipmentNo = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.grpHeader = new DevExpress.XtraEditors.GroupControl();
            this.lblSupplierCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblSupplierValue = new DevExpress.XtraEditors.LabelControl();
            this.lblStatusCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblStatusValue = new DevExpress.XtraEditors.LabelControl();
            this.lblOrderDateCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblOrderDateValue = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalQtyCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalQtyValue = new DevExpress.XtraEditors.LabelControl();
            this.lblCurrentCostCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblCurrentCostValue = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalIncorporatedCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalIncorporatedValue = new DevExpress.XtraEditors.LabelControl();
            this.lblVarianceCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblVarianceValue = new DevExpress.XtraEditors.LabelControl();
            this.gridDetail = new DevExpress.XtraGrid.GridControl();
            this.gridViewDetail = new DevExpress.XtraGrid.Views.Grid.GridView();
            ((System.ComponentModel.ISupportInitialize)(this.pnlFilters)).BeginInit();
            this.pnlFilters.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.cboShipmentNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).BeginInit();
            this.grpHeader.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridDetail)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewDetail)).BeginInit();
            this.SuspendLayout();
            //
            // pnlFilters
            //
            this.pnlFilters.Controls.Add(this.btnExport);
            this.pnlFilters.Controls.Add(this.btnLoad);
            this.pnlFilters.Controls.Add(this.lblShipmentNo);
            this.pnlFilters.Controls.Add(this.cboShipmentNo);
            this.pnlFilters.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlFilters.Location = new System.Drawing.Point(0, 0);
            this.pnlFilters.Name = "pnlFilters";
            this.pnlFilters.Size = new System.Drawing.Size(1150, 48);
            this.pnlFilters.TabIndex = 0;
            //
            // lblShipmentNo
            //
            this.lblShipmentNo.Location = new System.Drawing.Point(12, 17);
            this.lblShipmentNo.Name = "lblShipmentNo";
            this.lblShipmentNo.Size = new System.Drawing.Size(65, 13);
            this.lblShipmentNo.TabIndex = 0;
            this.lblShipmentNo.Text = "Shipment No:";
            //
            // cboShipmentNo
            //
            this.cboShipmentNo.Location = new System.Drawing.Point(85, 14);
            this.cboShipmentNo.Name = "cboShipmentNo";
            this.cboShipmentNo.Properties.NullText = "(select a shipment)";
            this.cboShipmentNo.Properties.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;
            this.cboShipmentNo.Size = new System.Drawing.Size(360, 20);
            this.cboShipmentNo.TabIndex = 1;
            //
            // btnLoad
            //
            this.btnLoad.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(180)))), ((int)(((byte)(140)))), ((int)(((byte)(20)))));
            this.btnLoad.Appearance.Options.UseBackColor = true;
            this.btnLoad.Location = new System.Drawing.Point(455, 12);
            this.btnLoad.Name = "btnLoad";
            this.btnLoad.Size = new System.Drawing.Size(90, 28);
            this.btnLoad.TabIndex = 2;
            this.btnLoad.Text = "Load";
            this.btnLoad.Click += new System.EventHandler(this.btnLoad_Click);
            //
            // btnExport
            //
            this.btnExport.Location = new System.Drawing.Point(555, 12);
            this.btnExport.Name = "btnExport";
            this.btnExport.Size = new System.Drawing.Size(80, 28);
            this.btnExport.TabIndex = 3;
            this.btnExport.Text = "Export";
            this.btnExport.Click += new System.EventHandler(this.btnExport_Click);
            //
            // grpHeader
            //
            this.grpHeader.Controls.Add(this.lblSupplierCaption);
            this.grpHeader.Controls.Add(this.lblSupplierValue);
            this.grpHeader.Controls.Add(this.lblStatusCaption);
            this.grpHeader.Controls.Add(this.lblStatusValue);
            this.grpHeader.Controls.Add(this.lblOrderDateCaption);
            this.grpHeader.Controls.Add(this.lblOrderDateValue);
            this.grpHeader.Controls.Add(this.lblTotalQtyCaption);
            this.grpHeader.Controls.Add(this.lblTotalQtyValue);
            this.grpHeader.Controls.Add(this.lblCurrentCostCaption);
            this.grpHeader.Controls.Add(this.lblCurrentCostValue);
            this.grpHeader.Controls.Add(this.lblTotalIncorporatedCaption);
            this.grpHeader.Controls.Add(this.lblTotalIncorporatedValue);
            this.grpHeader.Controls.Add(this.lblVarianceCaption);
            this.grpHeader.Controls.Add(this.lblVarianceValue);
            this.grpHeader.Dock = System.Windows.Forms.DockStyle.Top;
            this.grpHeader.Location = new System.Drawing.Point(0, 48);
            this.grpHeader.Name = "grpHeader";
            this.grpHeader.Size = new System.Drawing.Size(1150, 96);
            this.grpHeader.TabIndex = 1;
            this.grpHeader.Text = "Purchase Order / Shipment Summary";
            //
            // lblSupplierCaption
            //
            this.lblSupplierCaption.Location = new System.Drawing.Point(16, 30);
            this.lblSupplierCaption.Name = "lblSupplierCaption";
            this.lblSupplierCaption.Size = new System.Drawing.Size(48, 13);
            this.lblSupplierCaption.TabIndex = 0;
            this.lblSupplierCaption.Text = "Supplier:";
            //
            // lblSupplierValue
            //
            this.lblSupplierValue.Appearance.Font = new System.Drawing.Font("Tahoma", 8.25F, System.Drawing.FontStyle.Bold);
            this.lblSupplierValue.Appearance.Options.UseFont = true;
            this.lblSupplierValue.Location = new System.Drawing.Point(120, 30);
            this.lblSupplierValue.Name = "lblSupplierValue";
            this.lblSupplierValue.Size = new System.Drawing.Size(280, 13);
            this.lblSupplierValue.TabIndex = 1;
            //
            // lblStatusCaption
            //
            this.lblStatusCaption.Location = new System.Drawing.Point(420, 30);
            this.lblStatusCaption.Name = "lblStatusCaption";
            this.lblStatusCaption.Size = new System.Drawing.Size(38, 13);
            this.lblStatusCaption.TabIndex = 2;
            this.lblStatusCaption.Text = "Status:";
            //
            // lblStatusValue
            //
            this.lblStatusValue.Appearance.Font = new System.Drawing.Font("Tahoma", 8.25F, System.Drawing.FontStyle.Bold);
            this.lblStatusValue.Appearance.Options.UseFont = true;
            this.lblStatusValue.Location = new System.Drawing.Point(500, 30);
            this.lblStatusValue.Name = "lblStatusValue";
            this.lblStatusValue.Size = new System.Drawing.Size(140, 13);
            this.lblStatusValue.TabIndex = 3;
            //
            // lblOrderDateCaption
            //
            this.lblOrderDateCaption.Location = new System.Drawing.Point(660, 30);
            this.lblOrderDateCaption.Name = "lblOrderDateCaption";
            this.lblOrderDateCaption.Size = new System.Drawing.Size(63, 13);
            this.lblOrderDateCaption.TabIndex = 4;
            this.lblOrderDateCaption.Text = "Order Date:";
            //
            // lblOrderDateValue
            //
            this.lblOrderDateValue.Appearance.Font = new System.Drawing.Font("Tahoma", 8.25F, System.Drawing.FontStyle.Bold);
            this.lblOrderDateValue.Appearance.Options.UseFont = true;
            this.lblOrderDateValue.Location = new System.Drawing.Point(730, 30);
            this.lblOrderDateValue.Name = "lblOrderDateValue";
            this.lblOrderDateValue.Size = new System.Drawing.Size(140, 13);
            this.lblOrderDateValue.TabIndex = 5;
            //
            // lblTotalQtyCaption
            //
            this.lblTotalQtyCaption.Location = new System.Drawing.Point(16, 56);
            this.lblTotalQtyCaption.Name = "lblTotalQtyCaption";
            this.lblTotalQtyCaption.Size = new System.Drawing.Size(90, 13);
            this.lblTotalQtyCaption.TabIndex = 6;
            this.lblTotalQtyCaption.Text = "Total Ordered Qty:";
            //
            // lblTotalQtyValue
            //
            this.lblTotalQtyValue.Appearance.Font = new System.Drawing.Font("Tahoma", 8.25F, System.Drawing.FontStyle.Bold);
            this.lblTotalQtyValue.Appearance.Options.UseFont = true;
            this.lblTotalQtyValue.Location = new System.Drawing.Point(120, 56);
            this.lblTotalQtyValue.Name = "lblTotalQtyValue";
            this.lblTotalQtyValue.Size = new System.Drawing.Size(140, 13);
            this.lblTotalQtyValue.TabIndex = 7;
            //
            // lblCurrentCostCaption
            //
            this.lblCurrentCostCaption.Location = new System.Drawing.Point(420, 56);
            this.lblCurrentCostCaption.Name = "lblCurrentCostCaption";
            this.lblCurrentCostCaption.Size = new System.Drawing.Size(96, 13);
            this.lblCurrentCostCaption.TabIndex = 8;
            this.lblCurrentCostCaption.Text = "Current Unit Cost:";
            //
            // lblCurrentCostValue
            //
            this.lblCurrentCostValue.Appearance.Font = new System.Drawing.Font("Tahoma", 8.25F, System.Drawing.FontStyle.Bold);
            this.lblCurrentCostValue.Appearance.Options.UseFont = true;
            this.lblCurrentCostValue.Location = new System.Drawing.Point(520, 56);
            this.lblCurrentCostValue.Name = "lblCurrentCostValue";
            this.lblCurrentCostValue.Size = new System.Drawing.Size(180, 13);
            this.lblCurrentCostValue.TabIndex = 9;
            //
            // lblTotalIncorporatedCaption
            //
            this.lblTotalIncorporatedCaption.Location = new System.Drawing.Point(16, 76);
            this.lblTotalIncorporatedCaption.Name = "lblTotalIncorporatedCaption";
            this.lblTotalIncorporatedCaption.Size = new System.Drawing.Size(150, 13);
            this.lblTotalIncorporatedCaption.TabIndex = 10;
            this.lblTotalIncorporatedCaption.Text = "Total Cost Incorporated:";
            //
            // lblTotalIncorporatedValue
            //
            this.lblTotalIncorporatedValue.Appearance.Font = new System.Drawing.Font("Tahoma", 8.25F, System.Drawing.FontStyle.Bold);
            this.lblTotalIncorporatedValue.Appearance.Options.UseFont = true;
            this.lblTotalIncorporatedValue.Location = new System.Drawing.Point(160, 76);
            this.lblTotalIncorporatedValue.Name = "lblTotalIncorporatedValue";
            this.lblTotalIncorporatedValue.Size = new System.Drawing.Size(140, 13);
            this.lblTotalIncorporatedValue.TabIndex = 11;
            //
            // lblVarianceCaption
            //
            this.lblVarianceCaption.Location = new System.Drawing.Point(420, 76);
            this.lblVarianceCaption.Name = "lblVarianceCaption";
            this.lblVarianceCaption.Size = new System.Drawing.Size(53, 13);
            this.lblVarianceCaption.TabIndex = 12;
            this.lblVarianceCaption.Text = "Variance:";
            //
            // lblVarianceValue
            //
            this.lblVarianceValue.Appearance.Font = new System.Drawing.Font("Tahoma", 8.25F, System.Drawing.FontStyle.Bold);
            this.lblVarianceValue.Appearance.Options.UseFont = true;
            this.lblVarianceValue.Location = new System.Drawing.Point(480, 76);
            this.lblVarianceValue.Name = "lblVarianceValue";
            this.lblVarianceValue.Size = new System.Drawing.Size(220, 13);
            this.lblVarianceValue.TabIndex = 13;
            //
            // gridDetail
            //
            this.gridDetail.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridDetail.Location = new System.Drawing.Point(0, 144);
            this.gridDetail.MainView = this.gridViewDetail;
            this.gridDetail.Name = "gridDetail";
            this.gridDetail.Size = new System.Drawing.Size(1150, 506);
            this.gridDetail.TabIndex = 2;
            this.gridDetail.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewDetail});
            //
            // gridViewDetail
            //
            this.gridViewDetail.GridControl = this.gridDetail;
            this.gridViewDetail.Name = "gridViewDetail";
            this.gridViewDetail.OptionsBehavior.Editable = false;
            this.gridViewDetail.OptionsView.ShowFooter = true;
            this.gridViewDetail.OptionsView.ShowGroupPanel = false;
            //
            // ItemCostingReconReport
            //
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1150, 650);
            this.Controls.Add(this.gridDetail);
            this.Controls.Add(this.grpHeader);
            this.Controls.Add(this.pnlFilters);
            this.Name = "ItemCostingReconReport";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "Item Costing Recon";
            this.WindowState = System.Windows.Forms.FormWindowState.Maximized;
            this.Load += new System.EventHandler(this.ItemCostingReconReport_Load);
            ((System.ComponentModel.ISupportInitialize)(this.pnlFilters)).EndInit();
            this.pnlFilters.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.cboShipmentNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).EndInit();
            this.grpHeader.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridDetail)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewDetail)).EndInit();
            this.ResumeLayout(false);

        }

        #endregion

        private DevExpress.XtraEditors.PanelControl pnlFilters;
        private DevExpress.XtraEditors.LabelControl lblShipmentNo;
        private DevExpress.XtraEditors.SearchLookUpEdit cboShipmentNo;
        private DevExpress.XtraEditors.SimpleButton btnLoad;
        private DevExpress.XtraEditors.SimpleButton btnExport;
        private DevExpress.XtraEditors.GroupControl grpHeader;
        private DevExpress.XtraEditors.LabelControl lblSupplierCaption;
        private DevExpress.XtraEditors.LabelControl lblSupplierValue;
        private DevExpress.XtraEditors.LabelControl lblStatusCaption;
        private DevExpress.XtraEditors.LabelControl lblStatusValue;
        private DevExpress.XtraEditors.LabelControl lblOrderDateCaption;
        private DevExpress.XtraEditors.LabelControl lblOrderDateValue;
        private DevExpress.XtraEditors.LabelControl lblTotalQtyCaption;
        private DevExpress.XtraEditors.LabelControl lblTotalQtyValue;
        private DevExpress.XtraEditors.LabelControl lblCurrentCostCaption;
        private DevExpress.XtraEditors.LabelControl lblCurrentCostValue;
        private DevExpress.XtraEditors.LabelControl lblTotalIncorporatedCaption;
        private DevExpress.XtraEditors.LabelControl lblTotalIncorporatedValue;
        private DevExpress.XtraEditors.LabelControl lblVarianceCaption;
        private DevExpress.XtraEditors.LabelControl lblVarianceValue;
        private DevExpress.XtraGrid.GridControl gridDetail;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewDetail;
    }
}
