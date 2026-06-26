namespace SalesInventorySystem.HOFormsDevEx
{
    partial class ReceivedTransferInventoryBatchMode
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
            this.components = new System.ComponentModel.Container();
            this.groupControl2 = new DevExpress.XtraEditors.GroupControl();
            this.gridControlRcvd = new DevExpress.XtraGrid.GridControl();
            this.gridViewRcvd = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.labelControl1 = new DevExpress.XtraEditors.LabelControl();
            this.txtshipmentno = new DevExpress.XtraEditors.TextEdit();
            this.groupControl1 = new DevExpress.XtraEditors.GroupControl();
            this.labelsupplier = new DevExpress.XtraEditors.LabelControl();
            this.txtsupplier = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.gridView1 = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.txtremarks = new System.Windows.Forms.RichTextBox();
            this.labelControl3 = new DevExpress.XtraEditors.LabelControl();
            this.txtcategory = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.searchLookUpEdit1View = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.labelControl2 = new DevExpress.XtraEditors.LabelControl();
            this.simpleButton2 = new DevExpress.XtraEditors.SimpleButton();
            this.contextMenuStrip1 = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.cancelLineToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.printToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            ((System.ComponentModel.ISupportInitialize)(this.groupControl2)).BeginInit();
            this.groupControl2.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlRcvd)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewRcvd)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtshipmentno.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.groupControl1)).BeginInit();
            this.groupControl1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtsupplier.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView1)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtcategory.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.searchLookUpEdit1View)).BeginInit();
            this.contextMenuStrip1.SuspendLayout();
            this.SuspendLayout();
            // 
            // groupControl2
            // 
            this.groupControl2.Controls.Add(this.gridControlRcvd);
            this.groupControl2.Dock = System.Windows.Forms.DockStyle.Fill;
            this.groupControl2.Location = new System.Drawing.Point(0, 139);
            this.groupControl2.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.groupControl2.Name = "groupControl2";
            this.groupControl2.Size = new System.Drawing.Size(1267, 599);
            this.groupControl2.TabIndex = 30;
            // 
            // gridControlRcvd
            // 
            this.gridControlRcvd.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlRcvd.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlRcvd.Location = new System.Drawing.Point(2, 28);
            this.gridControlRcvd.MainView = this.gridViewRcvd;
            this.gridControlRcvd.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlRcvd.Name = "gridControlRcvd";
            this.gridControlRcvd.Size = new System.Drawing.Size(1263, 569);
            this.gridControlRcvd.TabIndex = 4;
            this.gridControlRcvd.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewRcvd});
            this.gridControlRcvd.MouseUp += new System.Windows.Forms.MouseEventHandler(this.gridControlRcvd_MouseUp);
            // 
            // gridViewRcvd
            // 
            this.gridViewRcvd.Appearance.HeaderPanel.Font = new System.Drawing.Font("Tahoma", 9.75F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.gridViewRcvd.Appearance.HeaderPanel.Options.UseFont = true;
            this.gridViewRcvd.Appearance.Row.Font = new System.Drawing.Font("Tahoma", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.gridViewRcvd.Appearance.Row.Options.UseFont = true;
            this.gridViewRcvd.DetailHeight = 431;
            this.gridViewRcvd.GridControl = this.gridControlRcvd;
            this.gridViewRcvd.Name = "gridViewRcvd";
            this.gridViewRcvd.OptionsView.ColumnAutoWidth = false;
            this.gridViewRcvd.OptionsView.RowAutoHeight = true;
            this.gridViewRcvd.OptionsView.ShowFooter = true;
            this.gridViewRcvd.RowCellStyle += new DevExpress.XtraGrid.Views.Grid.RowCellStyleEventHandler(this.gridViewRcvd_RowCellStyle);
            this.gridViewRcvd.ShowingEditor += new System.ComponentModel.CancelEventHandler(this.gridViewRcvd_ShowingEditor);
            // 
            // labelControl1
            // 
            this.labelControl1.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.labelControl1.Appearance.Options.UseFont = true;
            this.labelControl1.Location = new System.Drawing.Point(15, 41);
            this.labelControl1.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.labelControl1.Name = "labelControl1";
            this.labelControl1.Size = new System.Drawing.Size(85, 18);
            this.labelControl1.TabIndex = 18;
            this.labelControl1.Text = "Transfer #:";
            // 
            // txtshipmentno
            // 
            this.txtshipmentno.Location = new System.Drawing.Point(154, 36);
            this.txtshipmentno.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtshipmentno.Name = "txtshipmentno";
            this.txtshipmentno.Properties.Appearance.Font = new System.Drawing.Font("Microsoft Sans Serif", 10F);
            this.txtshipmentno.Properties.Appearance.Options.UseFont = true;
            this.txtshipmentno.Properties.MaxLength = 13;
            this.txtshipmentno.Properties.ReadOnly = true;
            this.txtshipmentno.Size = new System.Drawing.Size(136, 26);
            this.txtshipmentno.TabIndex = 19;
            // 
            // groupControl1
            // 
            this.groupControl1.Controls.Add(this.labelsupplier);
            this.groupControl1.Controls.Add(this.txtsupplier);
            this.groupControl1.Controls.Add(this.txtremarks);
            this.groupControl1.Controls.Add(this.labelControl3);
            this.groupControl1.Controls.Add(this.txtcategory);
            this.groupControl1.Controls.Add(this.labelControl2);
            this.groupControl1.Controls.Add(this.simpleButton2);
            this.groupControl1.Controls.Add(this.labelControl1);
            this.groupControl1.Controls.Add(this.txtshipmentno);
            this.groupControl1.Dock = System.Windows.Forms.DockStyle.Top;
            this.groupControl1.Location = new System.Drawing.Point(0, 0);
            this.groupControl1.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.groupControl1.Name = "groupControl1";
            this.groupControl1.Size = new System.Drawing.Size(1267, 139);
            this.groupControl1.TabIndex = 29;
            this.groupControl1.Text = "Receive PO/Inventory";
            // 
            // labelsupplier
            // 
            this.labelsupplier.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.labelsupplier.Appearance.Options.UseFont = true;
            this.labelsupplier.Location = new System.Drawing.Point(15, 106);
            this.labelsupplier.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.labelsupplier.Name = "labelsupplier";
            this.labelsupplier.Size = new System.Drawing.Size(68, 18);
            this.labelsupplier.TabIndex = 97;
            this.labelsupplier.Text = "Supplier:";
            // 
            // txtsupplier
            // 
            this.txtsupplier.Enabled = false;
            this.txtsupplier.Location = new System.Drawing.Point(154, 101);
            this.txtsupplier.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.txtsupplier.Name = "txtsupplier";
            this.txtsupplier.Properties.Appearance.Font = new System.Drawing.Font("Tahoma", 9.8F);
            this.txtsupplier.Properties.Appearance.Options.UseFont = true;
            this.txtsupplier.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtsupplier.Properties.NullText = "";
            this.txtsupplier.Properties.PopupView = this.gridView1;
            this.txtsupplier.Size = new System.Drawing.Size(136, 26);
            this.txtsupplier.TabIndex = 96;
            // 
            // gridView1
            // 
            this.gridView1.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.gridView1.Name = "gridView1";
            this.gridView1.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.gridView1.OptionsView.ShowGroupPanel = false;
            // 
            // txtremarks
            // 
            this.txtremarks.Location = new System.Drawing.Point(370, 32);
            this.txtremarks.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtremarks.Name = "txtremarks";
            this.txtremarks.Size = new System.Drawing.Size(322, 95);
            this.txtremarks.TabIndex = 95;
            this.txtremarks.Text = "";
            // 
            // labelControl3
            // 
            this.labelControl3.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.labelControl3.Appearance.Options.UseFont = true;
            this.labelControl3.Location = new System.Drawing.Point(297, 41);
            this.labelControl3.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.labelControl3.Name = "labelControl3";
            this.labelControl3.Size = new System.Drawing.Size(71, 18);
            this.labelControl3.TabIndex = 94;
            this.labelControl3.Text = "Remarks:";
            // 
            // txtcategory
            // 
            this.txtcategory.Location = new System.Drawing.Point(154, 69);
            this.txtcategory.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.txtcategory.Name = "txtcategory";
            this.txtcategory.Properties.Appearance.Font = new System.Drawing.Font("Tahoma", 9.8F);
            this.txtcategory.Properties.Appearance.Options.UseFont = true;
            this.txtcategory.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtcategory.Properties.NullText = "";
            this.txtcategory.Properties.PopupView = this.searchLookUpEdit1View;
            this.txtcategory.Size = new System.Drawing.Size(136, 26);
            this.txtcategory.TabIndex = 93;
            this.txtcategory.EditValueChanged += new System.EventHandler(this.txtcategory_EditValueChanged);
            // 
            // searchLookUpEdit1View
            // 
            this.searchLookUpEdit1View.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.searchLookUpEdit1View.Name = "searchLookUpEdit1View";
            this.searchLookUpEdit1View.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.searchLookUpEdit1View.OptionsView.ShowGroupPanel = false;
            // 
            // labelControl2
            // 
            this.labelControl2.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.labelControl2.Appearance.Options.UseFont = true;
            this.labelControl2.Location = new System.Drawing.Point(15, 74);
            this.labelControl2.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.labelControl2.Name = "labelControl2";
            this.labelControl2.Size = new System.Drawing.Size(141, 18);
            this.labelControl2.TabIndex = 92;
            this.labelControl2.Text = "Transfer Category:";
            // 
            // simpleButton2
            // 
            this.simpleButton2.ImageOptions.Image = global::SalesInventorySystem.Properties.Resources.Save_16x16__5_;
            this.simpleButton2.Location = new System.Drawing.Point(700, 32);
            this.simpleButton2.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.simpleButton2.Name = "simpleButton2";
            this.simpleButton2.Size = new System.Drawing.Size(110, 96);
            this.simpleButton2.TabIndex = 91;
            this.simpleButton2.Text = "Save";
            this.simpleButton2.Click += new System.EventHandler(this.simpleButton2_Click);
            // 
            // contextMenuStrip1
            // 
            this.contextMenuStrip1.ImageScalingSize = new System.Drawing.Size(32, 32);
            this.contextMenuStrip1.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.cancelLineToolStripMenuItem,
            this.printToolStripMenuItem});
            this.contextMenuStrip1.Name = "contextMenuStrip1";
            this.contextMenuStrip1.Size = new System.Drawing.Size(211, 80);
            // 
            // cancelLineToolStripMenuItem
            // 
            this.cancelLineToolStripMenuItem.Name = "cancelLineToolStripMenuItem";
            this.cancelLineToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            this.cancelLineToolStripMenuItem.Text = "Reprint Barcode";
            this.cancelLineToolStripMenuItem.Click += new System.EventHandler(this.cancelLineToolStripMenuItem_Click);
            // 
            // printToolStripMenuItem
            // 
            this.printToolStripMenuItem.Name = "printToolStripMenuItem";
            this.printToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            this.printToolStripMenuItem.Text = "Print";
            this.printToolStripMenuItem.Click += new System.EventHandler(this.printToolStripMenuItem_Click);
            // 
            // ReceivedTransferInventoryBatchMode
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1267, 738);
            this.Controls.Add(this.groupControl2);
            this.Controls.Add(this.groupControl1);
            this.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.Name = "ReceivedTransferInventoryBatchMode";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "Received Transfer Inventory";
            this.Load += new System.EventHandler(this.ReceivedTransferInventoryBatchMode_Load);
            ((System.ComponentModel.ISupportInitialize)(this.groupControl2)).EndInit();
            this.groupControl2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlRcvd)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewRcvd)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtshipmentno.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.groupControl1)).EndInit();
            this.groupControl1.ResumeLayout(false);
            this.groupControl1.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtsupplier.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView1)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtcategory.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.searchLookUpEdit1View)).EndInit();
            this.contextMenuStrip1.ResumeLayout(false);
            this.ResumeLayout(false);

        }

        #endregion

        private DevExpress.XtraEditors.GroupControl groupControl2;
        public DevExpress.XtraGrid.GridControl gridControlRcvd;
        public DevExpress.XtraGrid.Views.Grid.GridView gridViewRcvd;
        private DevExpress.XtraEditors.SimpleButton simpleButton2;
        private DevExpress.XtraEditors.LabelControl labelControl1;
        public DevExpress.XtraEditors.TextEdit txtshipmentno;
        private System.Windows.Forms.ContextMenuStrip contextMenuStrip1;
        private System.Windows.Forms.ToolStripMenuItem cancelLineToolStripMenuItem;
        public DevExpress.XtraEditors.GroupControl groupControl1;
        private DevExpress.XtraEditors.LabelControl labelControl2;
        private DevExpress.XtraEditors.SearchLookUpEdit txtcategory;
        private DevExpress.XtraGrid.Views.Grid.GridView searchLookUpEdit1View;
        private DevExpress.XtraEditors.LabelControl labelControl3;
        private System.Windows.Forms.RichTextBox txtremarks;
        private DevExpress.XtraEditors.LabelControl labelsupplier;
        private DevExpress.XtraEditors.SearchLookUpEdit txtsupplier;
        private DevExpress.XtraGrid.Views.Grid.GridView gridView1;
        private System.Windows.Forms.ToolStripMenuItem printToolStripMenuItem;
    }
}
//namespace SalesInventorySystem.HOFormsDevEx
//{
//    partial class ReceivedTransferInventoryBatchMode
//    {
//        /// <summary>
//        /// Required designer variable.
//        /// </summary>
//        private System.ComponentModel.IContainer components = null;

//        /// <summary>
//        /// Clean up any resources being used.
//        /// </summary>
//        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
//        protected override void Dispose(bool disposing)
//        {
//            if (disposing && (components != null))
//            {
//                components.Dispose();
//            }
//            base.Dispose(disposing);
//        }

//        #region Windows Form Designer generated code

//        /// <summary>
//        /// Required method for Designer support - do not modify
//        /// the contents of this method with the code editor.
//        /// </summary>
//        private void InitializeComponent()
//        {
//            this.components = new System.ComponentModel.Container();
//            this.groupControl2 = new DevExpress.XtraEditors.GroupControl();
//            this.gridControlRcvd = new DevExpress.XtraGrid.GridControl();
//            this.gridViewRcvd = new DevExpress.XtraGrid.Views.Grid.GridView();
//            this.gridControl1 = new DevExpress.XtraGrid.GridControl();
//            this.gridView1 = new DevExpress.XtraGrid.Views.Grid.GridView();
//            this.txtrefno = new DevExpress.XtraEditors.TextEdit();
//            this.labelControl1 = new DevExpress.XtraEditors.LabelControl();
//            this.txtshipmentno = new DevExpress.XtraEditors.TextEdit();
//            this.groupControl1 = new DevExpress.XtraEditors.GroupControl();
//            this.simpleButton2 = new DevExpress.XtraEditors.SimpleButton();
//            this.contextMenuStrip1 = new System.Windows.Forms.ContextMenuStrip(this.components);
//            this.cancelLineToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
//            ((System.ComponentModel.ISupportInitialize)(this.groupControl2)).BeginInit();
//            this.groupControl2.SuspendLayout();
//            ((System.ComponentModel.ISupportInitialize)(this.gridControlRcvd)).BeginInit();
//            ((System.ComponentModel.ISupportInitialize)(this.gridViewRcvd)).BeginInit();
//            ((System.ComponentModel.ISupportInitialize)(this.gridControl1)).BeginInit();
//            ((System.ComponentModel.ISupportInitialize)(this.gridView1)).BeginInit();
//            ((System.ComponentModel.ISupportInitialize)(this.txtrefno.Properties)).BeginInit();
//            ((System.ComponentModel.ISupportInitialize)(this.txtshipmentno.Properties)).BeginInit();
//            ((System.ComponentModel.ISupportInitialize)(this.groupControl1)).BeginInit();
//            this.groupControl1.SuspendLayout();
//            this.contextMenuStrip1.SuspendLayout();
//            this.SuspendLayout();
//            // 
//            // groupControl2
//            // 
//            this.groupControl2.Controls.Add(this.gridControlRcvd);
//            this.groupControl2.Dock = System.Windows.Forms.DockStyle.Fill;
//            this.groupControl2.Location = new System.Drawing.Point(0, 81);
//            this.groupControl2.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
//            this.groupControl2.Name = "groupControl2";
//            this.groupControl2.Size = new System.Drawing.Size(1267, 657);
//            this.groupControl2.TabIndex = 30;
//            // 
//            // gridControlRcvd
//            // 
//            this.gridControlRcvd.Dock = System.Windows.Forms.DockStyle.Fill;
//            this.gridControlRcvd.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
//            this.gridControlRcvd.Location = new System.Drawing.Point(2, 28);
//            this.gridControlRcvd.MainView = this.gridViewRcvd;
//            this.gridControlRcvd.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
//            this.gridControlRcvd.Name = "gridControlRcvd";
//            this.gridControlRcvd.Size = new System.Drawing.Size(1263, 627);
//            this.gridControlRcvd.TabIndex = 4;
//            this.gridControlRcvd.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
//            this.gridViewRcvd});
//            this.gridControlRcvd.MouseUp += new System.Windows.Forms.MouseEventHandler(this.gridControlRcvd_MouseUp);
//            // 
//            // gridViewRcvd
//            // 
//            this.gridViewRcvd.Appearance.HeaderPanel.Font = new System.Drawing.Font("Tahoma", 9.75F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
//            this.gridViewRcvd.Appearance.HeaderPanel.Options.UseFont = true;
//            this.gridViewRcvd.Appearance.Row.Font = new System.Drawing.Font("Tahoma", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
//            this.gridViewRcvd.Appearance.Row.Options.UseFont = true;
//            this.gridViewRcvd.DetailHeight = 431;
//            this.gridViewRcvd.GridControl = this.gridControlRcvd;
//            this.gridViewRcvd.Name = "gridViewRcvd";
//            this.gridViewRcvd.OptionsView.ColumnAutoWidth = false;
//            this.gridViewRcvd.OptionsView.RowAutoHeight = true;
//            this.gridViewRcvd.OptionsView.ShowFooter = true;
//            this.gridViewRcvd.RowCellStyle += new DevExpress.XtraGrid.Views.Grid.RowCellStyleEventHandler(this.gridViewRcvd_RowCellStyle);
//            this.gridViewRcvd.ShowingEditor += new System.ComponentModel.CancelEventHandler(this.gridViewRcvd_ShowingEditor);
//            // 
//            // gridControl1
//            // 
//            this.gridControl1.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
//            this.gridControl1.Location = new System.Drawing.Point(444, 38);
//            this.gridControl1.MainView = this.gridView1;
//            this.gridControl1.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
//            this.gridControl1.Name = "gridControl1";
//            this.gridControl1.Size = new System.Drawing.Size(1402, 778);
//            this.gridControl1.TabIndex = 5;
//            this.gridControl1.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
//            this.gridView1});
//            this.gridControl1.Visible = false;
//            // 
//            // gridView1
//            // 
//            this.gridView1.Appearance.HeaderPanel.Font = new System.Drawing.Font("Tahoma", 9.75F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
//            this.gridView1.Appearance.HeaderPanel.Options.UseFont = true;
//            this.gridView1.Appearance.Row.Font = new System.Drawing.Font("Tahoma", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
//            this.gridView1.Appearance.Row.Options.UseFont = true;
//            this.gridView1.DetailHeight = 431;
//            this.gridView1.GridControl = this.gridControl1;
//            this.gridView1.Name = "gridView1";
//            this.gridView1.OptionsSelection.MultiSelect = true;
//            this.gridView1.OptionsSelection.MultiSelectMode = DevExpress.XtraGrid.Views.Grid.GridMultiSelectMode.CheckBoxRowSelect;
//            this.gridView1.OptionsView.ColumnAutoWidth = false;
//            this.gridView1.OptionsView.RowAutoHeight = true;
//            this.gridView1.OptionsView.ShowIndicator = false;
//            // 
//            // txtrefno
//            // 
//            this.txtrefno.Location = new System.Drawing.Point(326, 34);
//            this.txtrefno.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
//            this.txtrefno.Name = "txtrefno";
//            this.txtrefno.Properties.Appearance.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F);
//            this.txtrefno.Properties.Appearance.Options.UseFont = true;
//            this.txtrefno.Properties.MaxLength = 13;
//            this.txtrefno.Properties.ReadOnly = true;
//            this.txtrefno.Size = new System.Drawing.Size(78, 32);
//            this.txtrefno.TabIndex = 102;
//            this.txtrefno.Visible = false;
//            // 
//            // labelControl1
//            // 
//            this.labelControl1.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
//            this.labelControl1.Appearance.Options.UseFont = true;
//            this.labelControl1.Location = new System.Drawing.Point(15, 41);
//            this.labelControl1.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
//            this.labelControl1.Name = "labelControl1";
//            this.labelControl1.Size = new System.Drawing.Size(85, 18);
//            this.labelControl1.TabIndex = 18;
//            this.labelControl1.Text = "Transfer #:";
//            // 
//            // txtshipmentno
//            // 
//            this.txtshipmentno.Location = new System.Drawing.Point(106, 37);
//            this.txtshipmentno.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
//            this.txtshipmentno.Name = "txtshipmentno";
//            this.txtshipmentno.Properties.Appearance.Font = new System.Drawing.Font("Microsoft Sans Serif", 10F);
//            this.txtshipmentno.Properties.Appearance.Options.UseFont = true;
//            this.txtshipmentno.Properties.MaxLength = 13;
//            this.txtshipmentno.Properties.ReadOnly = true;
//            this.txtshipmentno.Size = new System.Drawing.Size(87, 26);
//            this.txtshipmentno.TabIndex = 19;
//            // 
//            // groupControl1
//            // 
//            this.groupControl1.Controls.Add(this.gridControl1);
//            this.groupControl1.Controls.Add(this.txtrefno);
//            this.groupControl1.Controls.Add(this.simpleButton2);
//            this.groupControl1.Controls.Add(this.labelControl1);
//            this.groupControl1.Controls.Add(this.txtshipmentno);
//            this.groupControl1.Dock = System.Windows.Forms.DockStyle.Top;
//            this.groupControl1.Location = new System.Drawing.Point(0, 0);
//            this.groupControl1.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
//            this.groupControl1.Name = "groupControl1";
//            this.groupControl1.Size = new System.Drawing.Size(1267, 81);
//            this.groupControl1.TabIndex = 29;
//            this.groupControl1.Text = "Receive PO/Inventory";
//            // 
//            // simpleButton2
//            // 
//            this.simpleButton2.ImageOptions.Image = global::SalesInventorySystem.Properties.Resources.Save_16x16__5_;
//            this.simpleButton2.Location = new System.Drawing.Point(200, 37);
//            this.simpleButton2.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
//            this.simpleButton2.Name = "simpleButton2";
//            this.simpleButton2.Size = new System.Drawing.Size(100, 26);
//            this.simpleButton2.TabIndex = 91;
//            this.simpleButton2.Text = "Save";
//            this.simpleButton2.Click += new System.EventHandler(this.simpleButton2_Click);
//            // 
//            // contextMenuStrip1
//            // 
//            this.contextMenuStrip1.ImageScalingSize = new System.Drawing.Size(32, 32);
//            this.contextMenuStrip1.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
//            this.cancelLineToolStripMenuItem});
//            this.contextMenuStrip1.Name = "contextMenuStrip1";
//            this.contextMenuStrip1.Size = new System.Drawing.Size(186, 28);
//            // 
//            // cancelLineToolStripMenuItem
//            // 
//            this.cancelLineToolStripMenuItem.Name = "cancelLineToolStripMenuItem";
//            this.cancelLineToolStripMenuItem.Size = new System.Drawing.Size(185, 24);
//            this.cancelLineToolStripMenuItem.Text = "Reprint Barcode";
//            this.cancelLineToolStripMenuItem.Click += new System.EventHandler(this.cancelLineToolStripMenuItem_Click);
//            // 
//            // ReceivedTransferInventoryBatchMode
//            // 
//            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
//            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
//            this.ClientSize = new System.Drawing.Size(1267, 738);
//            this.Controls.Add(this.groupControl2);
//            this.Controls.Add(this.groupControl1);
//            this.Name = "ReceivedTransferInventoryBatchMode";
//            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
//            this.Text = "Received Transfer Inventory";
//            this.Load += new System.EventHandler(this.ReceivedTransferInventoryBatchMode_Load);
//            ((System.ComponentModel.ISupportInitialize)(this.groupControl2)).EndInit();
//            this.groupControl2.ResumeLayout(false);
//            ((System.ComponentModel.ISupportInitialize)(this.gridControlRcvd)).EndInit();
//            ((System.ComponentModel.ISupportInitialize)(this.gridViewRcvd)).EndInit();
//            ((System.ComponentModel.ISupportInitialize)(this.gridControl1)).EndInit();
//            ((System.ComponentModel.ISupportInitialize)(this.gridView1)).EndInit();
//            ((System.ComponentModel.ISupportInitialize)(this.txtrefno.Properties)).EndInit();
//            ((System.ComponentModel.ISupportInitialize)(this.txtshipmentno.Properties)).EndInit();
//            ((System.ComponentModel.ISupportInitialize)(this.groupControl1)).EndInit();
//            this.groupControl1.ResumeLayout(false);
//            this.groupControl1.PerformLayout();
//            this.contextMenuStrip1.ResumeLayout(false);
//            this.ResumeLayout(false);

//        }

//        #endregion

//        private DevExpress.XtraEditors.GroupControl groupControl2;
//        public DevExpress.XtraGrid.GridControl gridControlRcvd;
//        public DevExpress.XtraGrid.Views.Grid.GridView gridViewRcvd;
//        public DevExpress.XtraGrid.GridControl gridControl1;
//        public DevExpress.XtraGrid.Views.Grid.GridView gridView1;
//        private DevExpress.XtraEditors.TextEdit txtrefno;
//        private DevExpress.XtraEditors.SimpleButton simpleButton2;
//        private DevExpress.XtraEditors.LabelControl labelControl1;
//        public DevExpress.XtraEditors.TextEdit txtshipmentno;
//        private System.Windows.Forms.ContextMenuStrip contextMenuStrip1;
//        private System.Windows.Forms.ToolStripMenuItem cancelLineToolStripMenuItem;
//        public DevExpress.XtraEditors.GroupControl groupControl1;
//    }
//}