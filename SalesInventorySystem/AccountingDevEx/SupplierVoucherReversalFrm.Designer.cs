namespace SalesInventorySystem.AccountingDevEx
{
    partial class SupplierVoucherReversalFrm
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null)) components.Dispose();
            base.Dispose(disposing);
        }

        private DevExpress.XtraEditors.PanelControl pnlFilter;
        private DevExpress.XtraEditors.LabelControl lblSupplier;
        private DevExpress.XtraEditors.SearchLookUpEdit cboSupplier;
        private DevExpress.XtraEditors.LabelControl lblDateFrom;
        private DevExpress.XtraEditors.DateEdit txtDateFrom;
        private DevExpress.XtraEditors.LabelControl lblDateTo;
        private DevExpress.XtraEditors.DateEdit txtDateTo;
        private DevExpress.XtraEditors.SimpleButton btnRefresh;

        private DevExpress.XtraGrid.GridControl gridControlVouchers;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewVouchers;

        private DevExpress.XtraEditors.PanelControl pnlButtons;
        private DevExpress.XtraEditors.SimpleButton btnReverse;
        private DevExpress.XtraEditors.SimpleButton btnClose;

        private void InitializeComponent()
        {
            this.components = new System.ComponentModel.Container();
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(SupplierVoucherReversalFrm));
            this.pnlFilter = new DevExpress.XtraEditors.PanelControl();
            this.lblSupplier = new DevExpress.XtraEditors.LabelControl();
            this.cboSupplier = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.lblDateFrom = new DevExpress.XtraEditors.LabelControl();
            this.txtDateFrom = new DevExpress.XtraEditors.DateEdit();
            this.lblDateTo = new DevExpress.XtraEditors.LabelControl();
            this.txtDateTo = new DevExpress.XtraEditors.DateEdit();
            this.btnRefresh = new DevExpress.XtraEditors.SimpleButton();
            this.gridControlVouchers = new DevExpress.XtraGrid.GridControl();
            this.gridViewVouchers = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.pnlButtons = new DevExpress.XtraEditors.PanelControl();
            this.btnReverse = new DevExpress.XtraEditors.SimpleButton();
            this.btnClose = new DevExpress.XtraEditors.SimpleButton();
            this.panelControl1 = new DevExpress.XtraEditors.PanelControl();
            this.contextMenuStrip1 = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.viewDetailsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            ((System.ComponentModel.ISupportInitialize)(this.pnlFilter)).BeginInit();
            this.pnlFilter.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.cboSupplier.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateFrom.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateFrom.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateTo.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateTo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlVouchers)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewVouchers)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlButtons)).BeginInit();
            this.pnlButtons.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl1)).BeginInit();
            this.panelControl1.SuspendLayout();
            this.contextMenuStrip1.SuspendLayout();
            this.SuspendLayout();
            // 
            // pnlFilter
            // 
            this.pnlFilter.Controls.Add(this.lblSupplier);
            this.pnlFilter.Controls.Add(this.cboSupplier);
            this.pnlFilter.Controls.Add(this.lblDateFrom);
            this.pnlFilter.Controls.Add(this.txtDateFrom);
            this.pnlFilter.Controls.Add(this.lblDateTo);
            this.pnlFilter.Controls.Add(this.txtDateTo);
            this.pnlFilter.Controls.Add(this.btnRefresh);
            this.pnlFilter.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlFilter.Location = new System.Drawing.Point(2, 2);
            this.pnlFilter.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.pnlFilter.Name = "pnlFilter";
            this.pnlFilter.Size = new System.Drawing.Size(929, 54);
            this.pnlFilter.TabIndex = 2;
            // 
            // lblSupplier
            // 
            this.lblSupplier.Location = new System.Drawing.Point(14, 18);
            this.lblSupplier.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblSupplier.Name = "lblSupplier";
            this.lblSupplier.Size = new System.Drawing.Size(52, 16);
            this.lblSupplier.TabIndex = 0;
            this.lblSupplier.Text = "Supplier:";
            // 
            // cboSupplier
            // 
            this.cboSupplier.Location = new System.Drawing.Point(82, 14);
            this.cboSupplier.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.cboSupplier.Name = "cboSupplier";
            this.cboSupplier.Properties.NullText = "— all suppliers —";
            this.cboSupplier.Size = new System.Drawing.Size(303, 22);
            this.cboSupplier.TabIndex = 1;
            // 
            // lblDateFrom
            // 
            this.lblDateFrom.Location = new System.Drawing.Point(404, 18);
            this.lblDateFrom.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblDateFrom.Name = "lblDateFrom";
            this.lblDateFrom.Size = new System.Drawing.Size(35, 16);
            this.lblDateFrom.TabIndex = 2;
            this.lblDateFrom.Text = "From:";
            // 
            // txtDateFrom
            // 
            this.txtDateFrom.EditValue = new System.DateTime(2026, 7, 20, 0, 0, 0, 0);
            this.txtDateFrom.Location = new System.Drawing.Point(448, 14);
            this.txtDateFrom.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtDateFrom.Name = "txtDateFrom";
            this.txtDateFrom.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtDateFrom.Size = new System.Drawing.Size(128, 22);
            this.txtDateFrom.TabIndex = 3;
            // 
            // lblDateTo
            // 
            this.lblDateTo.Location = new System.Drawing.Point(588, 18);
            this.lblDateTo.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblDateTo.Name = "lblDateTo";
            this.lblDateTo.Size = new System.Drawing.Size(20, 16);
            this.lblDateTo.TabIndex = 4;
            this.lblDateTo.Text = "To:";
            // 
            // txtDateTo
            // 
            this.txtDateTo.EditValue = new System.DateTime(2026, 7, 20, 0, 0, 0, 0);
            this.txtDateTo.Location = new System.Drawing.Point(618, 14);
            this.txtDateTo.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtDateTo.Name = "txtDateTo";
            this.txtDateTo.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtDateTo.Size = new System.Drawing.Size(128, 22);
            this.txtDateTo.TabIndex = 5;
            // 
            // btnRefresh
            // 
            this.btnRefresh.Location = new System.Drawing.Point(763, 11);
            this.btnRefresh.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnRefresh.Name = "btnRefresh";
            this.btnRefresh.Size = new System.Drawing.Size(105, 32);
            this.btnRefresh.TabIndex = 6;
            this.btnRefresh.Text = "Refresh";
            this.btnRefresh.Click += new System.EventHandler(this.BtnRefresh_Click);
            // 
            // gridControlVouchers
            // 
            this.gridControlVouchers.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlVouchers.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlVouchers.Location = new System.Drawing.Point(2, 56);
            this.gridControlVouchers.MainView = this.gridViewVouchers;
            this.gridControlVouchers.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlVouchers.Name = "gridControlVouchers";
            this.gridControlVouchers.Size = new System.Drawing.Size(929, 525);
            this.gridControlVouchers.TabIndex = 0;
            this.gridControlVouchers.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewVouchers});
            this.gridControlVouchers.MouseUp += new System.Windows.Forms.MouseEventHandler(this.gridControlVouchers_MouseUp);
            // 
            // gridViewVouchers
            // 
            this.gridViewVouchers.DetailHeight = 431;
            this.gridViewVouchers.GridControl = this.gridControlVouchers;
            this.gridViewVouchers.Name = "gridViewVouchers";
            this.gridViewVouchers.OptionsBehavior.Editable = false;
            this.gridViewVouchers.OptionsView.ShowGroupPanel = false;
            this.gridViewVouchers.RowCellStyle += new DevExpress.XtraGrid.Views.Grid.RowCellStyleEventHandler(this.gridViewVouchers_RowCellStyle);
            this.gridViewVouchers.FocusedRowChanged += new DevExpress.XtraGrid.Views.Base.FocusedRowChangedEventHandler(this.GridViewVouchers_FocusedRowChanged);
            // 
            // pnlButtons
            // 
            this.pnlButtons.Controls.Add(this.btnReverse);
            this.pnlButtons.Controls.Add(this.btnClose);
            this.pnlButtons.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.pnlButtons.Location = new System.Drawing.Point(2, 581);
            this.pnlButtons.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.pnlButtons.Name = "pnlButtons";
            this.pnlButtons.Size = new System.Drawing.Size(929, 57);
            this.pnlButtons.TabIndex = 1;
            // 
            // btnReverse
            // 
            this.btnReverse.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(255)))), ((int)(((byte)(220)))), ((int)(((byte)(220)))));
            this.btnReverse.Appearance.Options.UseBackColor = true;
            this.btnReverse.Enabled = false;
            this.btnReverse.Location = new System.Drawing.Point(14, 11);
            this.btnReverse.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnReverse.Name = "btnReverse";
            this.btnReverse.Size = new System.Drawing.Size(175, 34);
            this.btnReverse.TabIndex = 0;
            this.btnReverse.Text = "Reverse Voucher...";
            this.btnReverse.Click += new System.EventHandler(this.BtnReverse_Click);
            // 
            // btnClose
            // 
            this.btnClose.Location = new System.Drawing.Point(817, 11);
            this.btnClose.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnClose.Name = "btnClose";
            this.btnClose.Size = new System.Drawing.Size(105, 34);
            this.btnClose.TabIndex = 1;
            this.btnClose.Text = "Close";
            this.btnClose.Click += new System.EventHandler(this.BtnClose_Click);
            // 
            // panelControl1
            // 
            this.panelControl1.Controls.Add(this.gridControlVouchers);
            this.panelControl1.Controls.Add(this.pnlFilter);
            this.panelControl1.Controls.Add(this.pnlButtons);
            this.panelControl1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.panelControl1.Location = new System.Drawing.Point(0, 0);
            this.panelControl1.Name = "panelControl1";
            this.panelControl1.Size = new System.Drawing.Size(933, 640);
            this.panelControl1.TabIndex = 3;
            // 
            // contextMenuStrip1
            // 
            this.contextMenuStrip1.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.contextMenuStrip1.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.viewDetailsToolStripMenuItem});
            this.contextMenuStrip1.Name = "contextMenuStrip1";
            this.contextMenuStrip1.Size = new System.Drawing.Size(165, 30);
            // 
            // viewDetailsToolStripMenuItem
            // 
            this.viewDetailsToolStripMenuItem.Image = ((System.Drawing.Image)(resources.GetObject("viewDetailsToolStripMenuItem.Image")));
            this.viewDetailsToolStripMenuItem.Name = "viewDetailsToolStripMenuItem";
            this.viewDetailsToolStripMenuItem.Size = new System.Drawing.Size(164, 26);
            this.viewDetailsToolStripMenuItem.Text = "View Details";
            this.viewDetailsToolStripMenuItem.Click += new System.EventHandler(this.viewDetailsToolStripMenuItem_Click);
            // 
            // SupplierVoucherReversalFrm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.Controls.Add(this.panelControl1);
            this.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.Name = "SupplierVoucherReversalFrm";
            this.Size = new System.Drawing.Size(933, 640);
            this.Load += new System.EventHandler(this.SupplierVoucherReversalFrm_Load);
            ((System.ComponentModel.ISupportInitialize)(this.pnlFilter)).EndInit();
            this.pnlFilter.ResumeLayout(false);
            this.pnlFilter.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.cboSupplier.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateFrom.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateFrom.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateTo.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDateTo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlVouchers)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewVouchers)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.pnlButtons)).EndInit();
            this.pnlButtons.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.panelControl1)).EndInit();
            this.panelControl1.ResumeLayout(false);
            this.contextMenuStrip1.ResumeLayout(false);
            this.ResumeLayout(false);

        }

        private DevExpress.XtraEditors.PanelControl panelControl1;
        private System.Windows.Forms.ContextMenuStrip contextMenuStrip1;
        private System.Windows.Forms.ToolStripMenuItem viewDetailsToolStripMenuItem;
    }
}