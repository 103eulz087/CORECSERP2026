namespace SalesInventorySystem.AccountingDevEx
{
    partial class ViewLinkedPODetailsFrm
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
            this.grpHeader = new DevExpress.XtraEditors.GroupControl();
            this.lblShipmentCap = new DevExpress.XtraEditors.LabelControl();
            this.lblShipmentValue = new DevExpress.XtraEditors.LabelControl();
            this.lblSupplierCap = new DevExpress.XtraEditors.LabelControl();
            this.lblSupplierValue = new DevExpress.XtraEditors.LabelControl();
            this.lblStatusCap = new DevExpress.XtraEditors.LabelControl();
            this.lblStatusValue = new DevExpress.XtraEditors.LabelControl();
            this.lblOrderDateCap = new DevExpress.XtraEditors.LabelControl();
            this.lblOrderDateValue = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalCostCap = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalCostValue = new DevExpress.XtraEditors.LabelControl();
            this.gridControlLines = new DevExpress.XtraGrid.GridControl();
            this.gridViewLines = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.pnlBottom = new DevExpress.XtraEditors.PanelControl();
            this.btnClose = new DevExpress.XtraEditors.SimpleButton();
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).BeginInit();
            this.grpHeader.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlLines)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewLines)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlBottom)).BeginInit();
            this.pnlBottom.SuspendLayout();
            this.SuspendLayout();
            // 
            // grpHeader
            // 
            this.grpHeader.Controls.Add(this.lblShipmentCap);
            this.grpHeader.Controls.Add(this.lblShipmentValue);
            this.grpHeader.Controls.Add(this.lblSupplierCap);
            this.grpHeader.Controls.Add(this.lblSupplierValue);
            this.grpHeader.Controls.Add(this.lblStatusCap);
            this.grpHeader.Controls.Add(this.lblStatusValue);
            this.grpHeader.Controls.Add(this.lblOrderDateCap);
            this.grpHeader.Controls.Add(this.lblOrderDateValue);
            this.grpHeader.Controls.Add(this.lblTotalCostCap);
            this.grpHeader.Controls.Add(this.lblTotalCostValue);
            this.grpHeader.Dock = System.Windows.Forms.DockStyle.Top;
            this.grpHeader.Location = new System.Drawing.Point(0, 0);
            this.grpHeader.Name = "grpHeader";
            this.grpHeader.Size = new System.Drawing.Size(744, 110);
            this.grpHeader.TabIndex = 2;
            this.grpHeader.Text = "Purchase Order";
            // 
            // lblShipmentCap
            // 
            this.lblShipmentCap.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblShipmentCap.Location = new System.Drawing.Point(16, 20);
            this.lblShipmentCap.Name = "lblShipmentCap";
            this.lblShipmentCap.Size = new System.Drawing.Size(76, 16);
            this.lblShipmentCap.TabIndex = 0;
            this.lblShipmentCap.Text = "Shipment No.:";
            // 
            // lblShipmentValue
            // 
            this.lblShipmentValue.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblShipmentValue.Appearance.Options.UseFont = true;
            this.lblShipmentValue.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblShipmentValue.Location = new System.Drawing.Point(98, 20);
            this.lblShipmentValue.Name = "lblShipmentValue";
            this.lblShipmentValue.Size = new System.Drawing.Size(384, 20);
            this.lblShipmentValue.TabIndex = 1;
            // 
            // lblSupplierCap
            // 
            this.lblSupplierCap.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblSupplierCap.Location = new System.Drawing.Point(16, 46);
            this.lblSupplierCap.Name = "lblSupplierCap";
            this.lblSupplierCap.Size = new System.Drawing.Size(57, 20);
            this.lblSupplierCap.TabIndex = 2;
            this.lblSupplierCap.Text = "Supplier:";
            // 
            // lblSupplierValue
            // 
            this.lblSupplierValue.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblSupplierValue.Appearance.Options.UseFont = true;
            this.lblSupplierValue.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblSupplierValue.Location = new System.Drawing.Point(92, 46);
            this.lblSupplierValue.Name = "lblSupplierValue";
            this.lblSupplierValue.Size = new System.Drawing.Size(404, 20);
            this.lblSupplierValue.TabIndex = 3;
            // 
            // lblStatusCap
            // 
            this.lblStatusCap.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblStatusCap.Location = new System.Drawing.Point(502, 20);
            this.lblStatusCap.Name = "lblStatusCap";
            this.lblStatusCap.Size = new System.Drawing.Size(45, 16);
            this.lblStatusCap.TabIndex = 4;
            this.lblStatusCap.Text = "Status:";
            // 
            // lblStatusValue
            // 
            this.lblStatusValue.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblStatusValue.Appearance.Options.UseFont = true;
            this.lblStatusValue.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblStatusValue.Location = new System.Drawing.Point(577, 20);
            this.lblStatusValue.Name = "lblStatusValue";
            this.lblStatusValue.Size = new System.Drawing.Size(143, 16);
            this.lblStatusValue.TabIndex = 5;
            // 
            // lblOrderDateCap
            // 
            this.lblOrderDateCap.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblOrderDateCap.Location = new System.Drawing.Point(502, 46);
            this.lblOrderDateCap.Name = "lblOrderDateCap";
            this.lblOrderDateCap.Size = new System.Drawing.Size(64, 16);
            this.lblOrderDateCap.TabIndex = 6;
            this.lblOrderDateCap.Text = "Order Date:";
            // 
            // lblOrderDateValue
            // 
            this.lblOrderDateValue.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblOrderDateValue.Appearance.Options.UseFont = true;
            this.lblOrderDateValue.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblOrderDateValue.Location = new System.Drawing.Point(577, 46);
            this.lblOrderDateValue.Name = "lblOrderDateValue";
            this.lblOrderDateValue.Size = new System.Drawing.Size(155, 16);
            this.lblOrderDateValue.TabIndex = 7;
            // 
            // lblTotalCostCap
            // 
            this.lblTotalCostCap.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblTotalCostCap.Location = new System.Drawing.Point(16, 72);
            this.lblTotalCostCap.Name = "lblTotalCostCap";
            this.lblTotalCostCap.Size = new System.Drawing.Size(57, 16);
            this.lblTotalCostCap.TabIndex = 8;
            this.lblTotalCostCap.Text = "Total Cost:";
            // 
            // lblTotalCostValue
            // 
            this.lblTotalCostValue.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblTotalCostValue.Appearance.Options.UseFont = true;
            this.lblTotalCostValue.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblTotalCostValue.Location = new System.Drawing.Point(150, 72);
            this.lblTotalCostValue.Name = "lblTotalCostValue";
            this.lblTotalCostValue.Size = new System.Drawing.Size(250, 16);
            this.lblTotalCostValue.TabIndex = 9;
            // 
            // gridControlLines
            // 
            this.gridControlLines.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlLines.Location = new System.Drawing.Point(0, 110);
            this.gridControlLines.MainView = this.gridViewLines;
            this.gridControlLines.Name = "gridControlLines";
            this.gridControlLines.Size = new System.Drawing.Size(744, 325);
            this.gridControlLines.TabIndex = 0;
            this.gridControlLines.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewLines});
            // 
            // gridViewLines
            // 
            this.gridViewLines.GridControl = this.gridControlLines;
            this.gridViewLines.Name = "gridViewLines";
            this.gridViewLines.OptionsBehavior.Editable = false;
            this.gridViewLines.OptionsView.ShowGroupPanel = false;
            // 
            // pnlBottom
            // 
            this.pnlBottom.Controls.Add(this.btnClose);
            this.pnlBottom.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.pnlBottom.Location = new System.Drawing.Point(0, 435);
            this.pnlBottom.Name = "pnlBottom";
            this.pnlBottom.Size = new System.Drawing.Size(744, 46);
            this.pnlBottom.TabIndex = 1;
            // 
            // btnClose
            // 
            this.btnClose.DialogResult = System.Windows.Forms.DialogResult.OK;
            this.btnClose.Location = new System.Drawing.Point(632, 9);
            this.btnClose.Name = "btnClose";
            this.btnClose.Size = new System.Drawing.Size(100, 28);
            this.btnClose.TabIndex = 0;
            this.btnClose.Text = "Close";
            // 
            // ViewLinkedPODetailsFrm
            // 
            this.AcceptButton = this.btnClose;
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(744, 481);
            this.Controls.Add(this.gridControlLines);
            this.Controls.Add(this.pnlBottom);
            this.Controls.Add(this.grpHeader);
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.Name = "ViewLinkedPODetailsFrm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "Linked PO Details";
            this.Load += new System.EventHandler(this.ViewLinkedPODetailsFrm_Load);
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).EndInit();
            this.grpHeader.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlLines)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewLines)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlBottom)).EndInit();
            this.pnlBottom.ResumeLayout(false);
            this.ResumeLayout(false);

        }

        #endregion

        private DevExpress.XtraEditors.GroupControl grpHeader;
        private DevExpress.XtraEditors.LabelControl lblShipmentCap;
        private DevExpress.XtraEditors.LabelControl lblShipmentValue;
        private DevExpress.XtraEditors.LabelControl lblSupplierCap;
        private DevExpress.XtraEditors.LabelControl lblSupplierValue;
        private DevExpress.XtraEditors.LabelControl lblStatusCap;
        private DevExpress.XtraEditors.LabelControl lblStatusValue;
        private DevExpress.XtraEditors.LabelControl lblOrderDateCap;
        private DevExpress.XtraEditors.LabelControl lblOrderDateValue;
        private DevExpress.XtraEditors.LabelControl lblTotalCostCap;
        private DevExpress.XtraEditors.LabelControl lblTotalCostValue;
        private DevExpress.XtraGrid.GridControl gridControlLines;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewLines;
        private DevExpress.XtraEditors.PanelControl pnlBottom;
        private DevExpress.XtraEditors.SimpleButton btnClose;
    }
}
