namespace SalesInventorySystem.Orders
{
    partial class ReturnSalesOrder
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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(ReturnSalesOrder));
            this.groupControl1 = new DevExpress.XtraEditors.GroupControl();
            this.labelControl4 = new DevExpress.XtraEditors.LabelControl();
            this.txtstatus = new DevExpress.XtraEditors.TextEdit();
            this.simpleButton1 = new DevExpress.XtraEditors.SimpleButton();
            this.txtdevno = new DevExpress.XtraEditors.TextEdit();
            this.txtpono = new DevExpress.XtraEditors.TextEdit();
            this.txtbrcode = new DevExpress.XtraEditors.TextEdit();
            this.labelControl3 = new DevExpress.XtraEditors.LabelControl();
            this.labelControl2 = new DevExpress.XtraEditors.LabelControl();
            this.labelControl1 = new DevExpress.XtraEditors.LabelControl();
            this.panelControl1 = new DevExpress.XtraEditors.PanelControl();
            this.gridControl1 = new DevExpress.XtraGrid.GridControl();
            this.gridView1 = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.txtreason = new DevExpress.XtraEditors.MemoEdit();
            ((System.ComponentModel.ISupportInitialize)(this.groupControl1)).BeginInit();
            this.groupControl1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtstatus.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtdevno.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtpono.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtbrcode.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl1)).BeginInit();
            this.panelControl1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControl1)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView1)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtreason.Properties)).BeginInit();
            this.SuspendLayout();
            // 
            // groupControl1
            // 
            this.groupControl1.Controls.Add(this.txtreason);
            this.groupControl1.Controls.Add(this.labelControl4);
            this.groupControl1.Controls.Add(this.txtstatus);
            this.groupControl1.Controls.Add(this.simpleButton1);
            this.groupControl1.Controls.Add(this.txtdevno);
            this.groupControl1.Controls.Add(this.txtpono);
            this.groupControl1.Controls.Add(this.txtbrcode);
            this.groupControl1.Controls.Add(this.labelControl3);
            this.groupControl1.Controls.Add(this.labelControl2);
            this.groupControl1.Controls.Add(this.labelControl1);
            this.groupControl1.Dock = System.Windows.Forms.DockStyle.Top;
            this.groupControl1.Location = new System.Drawing.Point(0, 0);
            this.groupControl1.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.groupControl1.Name = "groupControl1";
            this.groupControl1.Size = new System.Drawing.Size(1045, 122);
            this.groupControl1.TabIndex = 0;
            this.groupControl1.Text = "Return All / Specific Items";
            // 
            // labelControl4
            // 
            this.labelControl4.Appearance.Font = new System.Drawing.Font("Tahoma", 9.25F);
            this.labelControl4.Appearance.Options.UseFont = true;
            this.labelControl4.Location = new System.Drawing.Point(436, 44);
            this.labelControl4.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.labelControl4.Name = "labelControl4";
            this.labelControl4.Size = new System.Drawing.Size(53, 18);
            this.labelControl4.TabIndex = 8;
            this.labelControl4.Text = "Reason:";
            // 
            // txtstatus
            // 
            this.txtstatus.Location = new System.Drawing.Point(230, 80);
            this.txtstatus.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtstatus.Name = "txtstatus";
            this.txtstatus.Properties.Appearance.Font = new System.Drawing.Font("Tahoma", 9.25F);
            this.txtstatus.Properties.Appearance.Options.UseFont = true;
            this.txtstatus.Size = new System.Drawing.Size(199, 24);
            this.txtstatus.TabIndex = 7;
            // 
            // simpleButton1
            // 
            this.simpleButton1.ImageOptions.Image = global::SalesInventorySystem.Properties.Resources.Save_16x16__5_;
            this.simpleButton1.ImageOptions.ImageToTextAlignment = DevExpress.XtraEditors.ImageAlignToText.LeftCenter;
            this.simpleButton1.Location = new System.Drawing.Point(771, 44);
            this.simpleButton1.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.simpleButton1.Name = "simpleButton1";
            this.simpleButton1.Size = new System.Drawing.Size(120, 58);
            this.simpleButton1.TabIndex = 6;
            this.simpleButton1.Text = "Submit";
            this.simpleButton1.Click += new System.EventHandler(this.simpleButton1_Click);
            // 
            // txtdevno
            // 
            this.txtdevno.Location = new System.Drawing.Point(313, 43);
            this.txtdevno.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtdevno.Name = "txtdevno";
            this.txtdevno.Properties.Appearance.Font = new System.Drawing.Font("Tahoma", 9.25F);
            this.txtdevno.Properties.Appearance.Options.UseFont = true;
            this.txtdevno.Size = new System.Drawing.Size(117, 24);
            this.txtdevno.TabIndex = 5;
            // 
            // txtpono
            // 
            this.txtpono.Location = new System.Drawing.Point(106, 80);
            this.txtpono.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtpono.Name = "txtpono";
            this.txtpono.Properties.Appearance.Font = new System.Drawing.Font("Tahoma", 9.25F);
            this.txtpono.Properties.Appearance.Options.UseFont = true;
            this.txtpono.Size = new System.Drawing.Size(117, 24);
            this.txtpono.TabIndex = 4;
            // 
            // txtbrcode
            // 
            this.txtbrcode.Location = new System.Drawing.Point(106, 43);
            this.txtbrcode.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtbrcode.Name = "txtbrcode";
            this.txtbrcode.Properties.Appearance.Font = new System.Drawing.Font("Tahoma", 9.25F);
            this.txtbrcode.Properties.Appearance.Options.UseFont = true;
            this.txtbrcode.Size = new System.Drawing.Size(117, 24);
            this.txtbrcode.TabIndex = 3;
            // 
            // labelControl3
            // 
            this.labelControl3.Appearance.Font = new System.Drawing.Font("Tahoma", 9.25F);
            this.labelControl3.Appearance.Options.UseFont = true;
            this.labelControl3.Location = new System.Drawing.Point(230, 46);
            this.labelControl3.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.labelControl3.Name = "labelControl3";
            this.labelControl3.Size = new System.Drawing.Size(79, 18);
            this.labelControl3.TabIndex = 2;
            this.labelControl3.Text = "Delivery No:";
            // 
            // labelControl2
            // 
            this.labelControl2.Appearance.Font = new System.Drawing.Font("Tahoma", 9.25F);
            this.labelControl2.Appearance.Options.UseFont = true;
            this.labelControl2.Location = new System.Drawing.Point(14, 83);
            this.labelControl2.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.labelControl2.Name = "labelControl2";
            this.labelControl2.Size = new System.Drawing.Size(81, 18);
            this.labelControl2.TabIndex = 1;
            this.labelControl2.Text = "PO Number:";
            // 
            // labelControl1
            // 
            this.labelControl1.Appearance.Font = new System.Drawing.Font("Tahoma", 9.25F);
            this.labelControl1.Appearance.Options.UseFont = true;
            this.labelControl1.Location = new System.Drawing.Point(14, 46);
            this.labelControl1.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.labelControl1.Name = "labelControl1";
            this.labelControl1.Size = new System.Drawing.Size(88, 18);
            this.labelControl1.TabIndex = 0;
            this.labelControl1.Text = "Branch Code:";
            // 
            // panelControl1
            // 
            this.panelControl1.Controls.Add(this.gridControl1);
            this.panelControl1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.panelControl1.Location = new System.Drawing.Point(0, 122);
            this.panelControl1.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.panelControl1.Name = "panelControl1";
            this.panelControl1.Size = new System.Drawing.Size(1045, 464);
            this.panelControl1.TabIndex = 1;
            // 
            // gridControl1
            // 
            this.gridControl1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControl1.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControl1.Location = new System.Drawing.Point(2, 2);
            this.gridControl1.MainView = this.gridView1;
            this.gridControl1.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControl1.Name = "gridControl1";
            this.gridControl1.Size = new System.Drawing.Size(1041, 460);
            this.gridControl1.TabIndex = 5;
            this.gridControl1.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridView1});
            // 
            // gridView1
            // 
            this.gridView1.Appearance.HeaderPanel.Font = new System.Drawing.Font("Tahoma", 9.75F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.gridView1.Appearance.HeaderPanel.Options.UseFont = true;
            this.gridView1.Appearance.Row.Font = new System.Drawing.Font("Tahoma", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.gridView1.Appearance.Row.Options.UseFont = true;
            this.gridView1.DetailHeight = 431;
            this.gridView1.GridControl = this.gridControl1;
            this.gridView1.Name = "gridView1";
            this.gridView1.OptionsBehavior.Editable = false;
            this.gridView1.OptionsBehavior.ReadOnly = true;
            this.gridView1.OptionsSelection.MultiSelect = true;
            this.gridView1.OptionsSelection.MultiSelectMode = DevExpress.XtraGrid.Views.Grid.GridMultiSelectMode.CheckBoxRowSelect;
            this.gridView1.OptionsView.ColumnAutoWidth = false;
            this.gridView1.OptionsView.RowAutoHeight = true;
            this.gridView1.OptionsView.ShowIndicator = false;
            this.gridView1.RowStyle += new DevExpress.XtraGrid.Views.Grid.RowStyleEventHandler(this.gridView1_RowStyle);
            this.gridView1.SelectionChanged += new DevExpress.Data.SelectionChangedEventHandler(this.gridView1_SelectionChanged);
            // 
            // txtreason
            // 
            this.txtreason.Location = new System.Drawing.Point(504, 43);
            this.txtreason.Name = "txtreason";
            this.txtreason.Size = new System.Drawing.Size(261, 61);
            this.txtreason.TabIndex = 9;
            // 
            // ReturnSalesOrder
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1045, 586);
            this.Controls.Add(this.panelControl1);
            this.Controls.Add(this.groupControl1);
            this.IconOptions.Icon = ((System.Drawing.Icon)(resources.GetObject("ReturnSalesOrder.IconOptions.Icon")));
            this.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.Name = "ReturnSalesOrder";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "ReturnSalesOrder";
            this.WindowState = System.Windows.Forms.FormWindowState.Maximized;
            this.Load += new System.EventHandler(this.ReturnSalesOrder_Load);
            ((System.ComponentModel.ISupportInitialize)(this.groupControl1)).EndInit();
            this.groupControl1.ResumeLayout(false);
            this.groupControl1.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtstatus.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtdevno.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtpono.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtbrcode.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelControl1)).EndInit();
            this.panelControl1.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControl1)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView1)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtreason.Properties)).EndInit();
            this.ResumeLayout(false);

        }

        #endregion

        private DevExpress.XtraEditors.GroupControl groupControl1;
        private DevExpress.XtraEditors.PanelControl panelControl1;
        private DevExpress.XtraEditors.LabelControl labelControl3;
        private DevExpress.XtraEditors.LabelControl labelControl2;
        private DevExpress.XtraEditors.LabelControl labelControl1;
        private DevExpress.XtraEditors.SimpleButton simpleButton1;
        public DevExpress.XtraEditors.TextEdit txtbrcode;
        public DevExpress.XtraEditors.TextEdit txtdevno;
        public DevExpress.XtraEditors.TextEdit txtpono;
        public DevExpress.XtraGrid.GridControl gridControl1;
        public DevExpress.XtraGrid.Views.Grid.GridView gridView1;
        public DevExpress.XtraEditors.TextEdit txtstatus;
        private DevExpress.XtraEditors.LabelControl labelControl4;
        private DevExpress.XtraEditors.MemoEdit txtreason;
    }
}