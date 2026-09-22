namespace SalesInventorySystem.HOFormsDevEx
{
    partial class POFinalizeCostFrm
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
            this.pnlHeader = new DevExpress.XtraEditors.PanelControl();
            this.lblSupplier = new DevExpress.XtraEditors.LabelControl();
            this.lblShipment = new DevExpress.XtraEditors.LabelControl();
            this.lblHint = new DevExpress.XtraEditors.LabelControl();
            this.gridControlItems = new DevExpress.XtraGrid.GridControl();
            this.gridViewItems = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.repFinalCost = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.pnlButtons = new DevExpress.XtraEditors.PanelControl();
            this.btnCancel = new DevExpress.XtraEditors.SimpleButton();
            this.btnConfirm = new DevExpress.XtraEditors.SimpleButton();
            ((System.ComponentModel.ISupportInitialize)(this.pnlHeader)).BeginInit();
            this.pnlHeader.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlItems)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewItems)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repFinalCost)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlButtons)).BeginInit();
            this.pnlButtons.SuspendLayout();
            this.SuspendLayout();
            //
            // pnlHeader
            //
            this.pnlHeader.Controls.Add(this.lblHint);
            this.pnlHeader.Controls.Add(this.lblSupplier);
            this.pnlHeader.Controls.Add(this.lblShipment);
            this.pnlHeader.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlHeader.Location = new System.Drawing.Point(0, 0);
            this.pnlHeader.Name = "pnlHeader";
            this.pnlHeader.Size = new System.Drawing.Size(900, 78);
            this.pnlHeader.TabIndex = 0;
            //
            // lblShipment
            //
            this.lblShipment.Appearance.Font = new System.Drawing.Font("Tahoma", 9.75F, System.Drawing.FontStyle.Bold);
            this.lblShipment.Appearance.Options.UseFont = true;
            this.lblShipment.Location = new System.Drawing.Point(12, 10);
            this.lblShipment.Name = "lblShipment";
            this.lblShipment.Size = new System.Drawing.Size(80, 16);
            this.lblShipment.TabIndex = 0;
            this.lblShipment.Text = "Shipment No:";
            //
            // lblSupplier
            //
            this.lblSupplier.Appearance.Font = new System.Drawing.Font("Tahoma", 9.75F, System.Drawing.FontStyle.Bold);
            this.lblSupplier.Appearance.Options.UseFont = true;
            this.lblSupplier.Location = new System.Drawing.Point(12, 32);
            this.lblSupplier.Name = "lblSupplier";
            this.lblSupplier.Size = new System.Drawing.Size(60, 16);
            this.lblSupplier.TabIndex = 1;
            this.lblSupplier.Text = "Supplier:";
            //
            // lblHint
            //
            this.lblHint.Appearance.ForeColor = System.Drawing.Color.DimGray;
            this.lblHint.Appearance.Options.UseForeColor = true;
            this.lblHint.Location = new System.Drawing.Point(12, 54);
            this.lblHint.Name = "lblHint";
            this.lblHint.Size = new System.Drawing.Size(470, 13);
            this.lblHint.TabIndex = 2;
            this.lblHint.Text = "Quantities are totals per item. Edit Final Cost where it differs from the received Cost, then Confirm.";
            //
            // gridControlItems
            //
            this.gridControlItems.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlItems.Location = new System.Drawing.Point(0, 78);
            this.gridControlItems.MainView = this.gridViewItems;
            this.gridControlItems.Name = "gridControlItems";
            this.gridControlItems.RepositoryItems.AddRange(new DevExpress.XtraEditors.Repository.RepositoryItem[] {
            this.repFinalCost});
            this.gridControlItems.Size = new System.Drawing.Size(900, 402);
            this.gridControlItems.TabIndex = 1;
            this.gridControlItems.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewItems});
            //
            // gridViewItems
            //
            this.gridViewItems.GridControl = this.gridControlItems;
            this.gridViewItems.Name = "gridViewItems";
            this.gridViewItems.OptionsView.ShowFooter = true;
            this.gridViewItems.OptionsView.ShowGroupPanel = false;
            this.gridViewItems.CustomRowCellEdit += new DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventHandler(this.GridViewItems_CustomRowCellEdit);
            this.gridViewItems.RowCellStyle += new DevExpress.XtraGrid.Views.Grid.RowCellStyleEventHandler(this.GridViewItems_RowCellStyle);
            //
            // repFinalCost
            //
            this.repFinalCost.AutoHeight = false;
            this.repFinalCost.DisplayFormat.FormatString = "n2";
            this.repFinalCost.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.repFinalCost.Increment = new decimal(new int[] {
            0,
            0,
            0,
            0});
            this.repFinalCost.Mask.EditMask = "n2";
            this.repFinalCost.Mask.UseMaskAsDisplayFormat = true;
            this.repFinalCost.MinValue = new decimal(new int[] {
            0,
            0,
            0,
            0});
            this.repFinalCost.Name = "repFinalCost";
            //
            // pnlButtons
            //
            this.pnlButtons.Controls.Add(this.btnCancel);
            this.pnlButtons.Controls.Add(this.btnConfirm);
            this.pnlButtons.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.pnlButtons.Location = new System.Drawing.Point(0, 480);
            this.pnlButtons.Name = "pnlButtons";
            this.pnlButtons.Size = new System.Drawing.Size(900, 50);
            this.pnlButtons.TabIndex = 2;
            //
            // btnConfirm
            //
            this.btnConfirm.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.btnConfirm.Location = new System.Drawing.Point(676, 10);
            this.btnConfirm.Name = "btnConfirm";
            this.btnConfirm.Size = new System.Drawing.Size(100, 30);
            this.btnConfirm.TabIndex = 0;
            this.btnConfirm.Text = "CONFIRM";
            this.btnConfirm.Click += new System.EventHandler(this.BtnConfirm_Click);
            //
            // btnCancel
            //
            this.btnCancel.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.btnCancel.Location = new System.Drawing.Point(786, 10);
            this.btnCancel.Name = "btnCancel";
            this.btnCancel.Size = new System.Drawing.Size(100, 30);
            this.btnCancel.TabIndex = 1;
            this.btnCancel.Text = "CANCEL";
            this.btnCancel.Click += new System.EventHandler(this.BtnCancel_Click);
            //
            // POFinalizeCostFrm
            //
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(900, 530);
            this.Controls.Add(this.gridControlItems);
            this.Controls.Add(this.pnlButtons);
            this.Controls.Add(this.pnlHeader);
            this.MinimizeBox = false;
            this.Name = "POFinalizeCostFrm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "Confirm and Finalize Cost";
            this.Load += new System.EventHandler(this.POFinalizeCostFrm_Load);
            ((System.ComponentModel.ISupportInitialize)(this.pnlHeader)).EndInit();
            this.pnlHeader.ResumeLayout(false);
            this.pnlHeader.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlItems)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewItems)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repFinalCost)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlButtons)).EndInit();
            this.pnlButtons.ResumeLayout(false);
            this.ResumeLayout(false);

        }

        #endregion

        private DevExpress.XtraEditors.PanelControl pnlHeader;
        private DevExpress.XtraEditors.LabelControl lblSupplier;
        private DevExpress.XtraEditors.LabelControl lblShipment;
        private DevExpress.XtraEditors.LabelControl lblHint;
        private DevExpress.XtraGrid.GridControl gridControlItems;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewItems;
        private DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit repFinalCost;
        private DevExpress.XtraEditors.PanelControl pnlButtons;
        private DevExpress.XtraEditors.SimpleButton btnCancel;
        private DevExpress.XtraEditors.SimpleButton btnConfirm;
    }
}
