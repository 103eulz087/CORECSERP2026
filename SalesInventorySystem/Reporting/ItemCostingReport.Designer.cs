namespace SalesInventorySystem.Reporting
{
    partial class ItemCostingReport
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
            this.lblReferenceCode = new DevExpress.XtraEditors.LabelControl();
            this.txtReferenceCode = new DevExpress.XtraEditors.TextEdit();
            this.lblShipmentNo = new DevExpress.XtraEditors.LabelControl();
            this.txtShipmentNo = new DevExpress.XtraEditors.TextEdit();
            this.lblTo = new DevExpress.XtraEditors.LabelControl();
            this.dtTo = new DevExpress.XtraEditors.DateEdit();
            this.lblFrom = new DevExpress.XtraEditors.LabelControl();
            this.dtFrom = new DevExpress.XtraEditors.DateEdit();
            this.lblBranch = new DevExpress.XtraEditors.LabelControl();
            this.cmbBranch = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.gridItemCosting = new DevExpress.XtraGrid.GridControl();
            ((System.ComponentModel.ISupportInitialize)(this.pnlFilters)).BeginInit();
            this.pnlFilters.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceCode.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtShipmentNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtTo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtTo.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtFrom.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtFrom.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbBranch.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridItemCosting)).BeginInit();
            this.SuspendLayout();
            //
            // pnlFilters
            //
            this.pnlFilters.Controls.Add(this.btnExport);
            this.pnlFilters.Controls.Add(this.btnLoad);
            this.pnlFilters.Controls.Add(this.lblReferenceCode);
            this.pnlFilters.Controls.Add(this.txtReferenceCode);
            this.pnlFilters.Controls.Add(this.lblShipmentNo);
            this.pnlFilters.Controls.Add(this.txtShipmentNo);
            this.pnlFilters.Controls.Add(this.lblTo);
            this.pnlFilters.Controls.Add(this.dtTo);
            this.pnlFilters.Controls.Add(this.lblFrom);
            this.pnlFilters.Controls.Add(this.dtFrom);
            this.pnlFilters.Controls.Add(this.lblBranch);
            this.pnlFilters.Controls.Add(this.cmbBranch);
            this.pnlFilters.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlFilters.Location = new System.Drawing.Point(0, 0);
            this.pnlFilters.Name = "pnlFilters";
            this.pnlFilters.Size = new System.Drawing.Size(1150, 72);
            this.pnlFilters.TabIndex = 0;
            //
            // lblBranch
            //
            this.lblBranch.Location = new System.Drawing.Point(10, 12);
            this.lblBranch.Name = "lblBranch";
            this.lblBranch.Size = new System.Drawing.Size(37, 13);
            this.lblBranch.TabIndex = 0;
            this.lblBranch.Text = "Branch:";
            //
            // cmbBranch
            //
            this.cmbBranch.Location = new System.Drawing.Point(65, 10);
            this.cmbBranch.Name = "cmbBranch";
            // Known Bug Pattern #2: DisableTextEditor -- must only accept a picked branch,
            // never free-typed text that could bypass ValueMember.
            this.cmbBranch.Properties.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;
            this.cmbBranch.Properties.NullText = "(All Branches)";
            this.cmbBranch.Size = new System.Drawing.Size(200, 24);
            this.cmbBranch.TabIndex = 1;
            //
            // lblFrom
            //
            this.lblFrom.Location = new System.Drawing.Point(275, 12);
            this.lblFrom.Name = "lblFrom";
            this.lblFrom.Size = new System.Drawing.Size(28, 13);
            this.lblFrom.TabIndex = 2;
            this.lblFrom.Text = "From:";
            //
            // dtFrom
            //
            this.dtFrom.EditValue = null;
            this.dtFrom.Location = new System.Drawing.Point(317, 10);
            this.dtFrom.Name = "dtFrom";
            this.dtFrom.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.dtFrom.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton()});
            this.dtFrom.Size = new System.Drawing.Size(95, 24);
            this.dtFrom.TabIndex = 3;
            //
            // lblTo
            //
            this.lblTo.Location = new System.Drawing.Point(420, 12);
            this.lblTo.Name = "lblTo";
            this.lblTo.Size = new System.Drawing.Size(14, 13);
            this.lblTo.TabIndex = 4;
            this.lblTo.Text = "To:";
            //
            // dtTo
            //
            this.dtTo.EditValue = null;
            this.dtTo.Location = new System.Drawing.Point(445, 10);
            this.dtTo.Name = "dtTo";
            this.dtTo.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.dtTo.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton()});
            this.dtTo.Size = new System.Drawing.Size(95, 24);
            this.dtTo.TabIndex = 5;
            //
            // lblShipmentNo
            //
            this.lblShipmentNo.Location = new System.Drawing.Point(555, 12);
            this.lblShipmentNo.Name = "lblShipmentNo";
            this.lblShipmentNo.Size = new System.Drawing.Size(65, 13);
            this.lblShipmentNo.TabIndex = 6;
            this.lblShipmentNo.Text = "Shipment No:";
            //
            // txtShipmentNo
            //
            this.txtShipmentNo.Location = new System.Drawing.Point(625, 10);
            this.txtShipmentNo.Name = "txtShipmentNo";
            this.txtShipmentNo.Size = new System.Drawing.Size(90, 24);
            this.txtShipmentNo.TabIndex = 7;
            //
            // lblReferenceCode
            //
            this.lblReferenceCode.Location = new System.Drawing.Point(725, 12);
            this.lblReferenceCode.Name = "lblReferenceCode";
            this.lblReferenceCode.Size = new System.Drawing.Size(78, 13);
            this.lblReferenceCode.TabIndex = 8;
            this.lblReferenceCode.Text = "Reference Code:";
            //
            // txtReferenceCode
            //
            this.txtReferenceCode.Location = new System.Drawing.Point(808, 10);
            this.txtReferenceCode.Name = "txtReferenceCode";
            this.txtReferenceCode.Size = new System.Drawing.Size(140, 24);
            this.txtReferenceCode.TabIndex = 9;
            //
            // btnLoad
            //
            this.btnLoad.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(180)))), ((int)(((byte)(140)))), ((int)(((byte)(20)))));
            this.btnLoad.Appearance.Options.UseBackColor = true;
            this.btnLoad.Location = new System.Drawing.Point(958, 8);
            this.btnLoad.Name = "btnLoad";
            this.btnLoad.Size = new System.Drawing.Size(90, 28);
            this.btnLoad.TabIndex = 10;
            this.btnLoad.Text = "Load";
            this.btnLoad.Click += new System.EventHandler(this.btnLoad_Click);
            //
            // btnExport
            //
            this.btnExport.Location = new System.Drawing.Point(1058, 8);
            this.btnExport.Name = "btnExport";
            this.btnExport.Size = new System.Drawing.Size(80, 28);
            this.btnExport.TabIndex = 11;
            this.btnExport.Text = "Export";
            this.btnExport.Click += new System.EventHandler(this.btnExport_Click);
            //
            // gridItemCosting
            //
            this.gridItemCosting.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridItemCosting.Location = new System.Drawing.Point(0, 72);
            this.gridItemCosting.Name = "gridItemCosting";
            this.gridItemCosting.Size = new System.Drawing.Size(1150, 578);
            this.gridItemCosting.TabIndex = 1;
            //
            // ItemCostingReport
            //
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1150, 650);
            this.Controls.Add(this.gridItemCosting);
            this.Controls.Add(this.pnlFilters);
            this.Name = "ItemCostingReport";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "Item Costing Report";
            this.WindowState = System.Windows.Forms.FormWindowState.Maximized;
            this.Load += new System.EventHandler(this.ItemCostingReport_Load);
            ((System.ComponentModel.ISupportInitialize)(this.pnlFilters)).EndInit();
            this.pnlFilters.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceCode.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtShipmentNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtTo.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtTo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtFrom.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.dtFrom.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbBranch.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridItemCosting)).EndInit();
            this.ResumeLayout(false);

        }

        #endregion

        private DevExpress.XtraEditors.PanelControl pnlFilters;
        private DevExpress.XtraEditors.LabelControl lblBranch;
        private DevExpress.XtraEditors.SearchLookUpEdit cmbBranch;
        private DevExpress.XtraEditors.LabelControl lblFrom;
        private DevExpress.XtraEditors.DateEdit dtFrom;
        private DevExpress.XtraEditors.LabelControl lblTo;
        private DevExpress.XtraEditors.DateEdit dtTo;
        private DevExpress.XtraEditors.LabelControl lblShipmentNo;
        private DevExpress.XtraEditors.TextEdit txtShipmentNo;
        private DevExpress.XtraEditors.LabelControl lblReferenceCode;
        private DevExpress.XtraEditors.TextEdit txtReferenceCode;
        private DevExpress.XtraEditors.SimpleButton btnLoad;
        private DevExpress.XtraEditors.SimpleButton btnExport;
        private DevExpress.XtraGrid.GridControl gridItemCosting;
    }
}
