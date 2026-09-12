namespace SalesInventorySystem.HOFormsDevEx
{
    partial class PrimalCutCosting
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
            this.groupControl1 = new DevExpress.XtraEditors.GroupControl();
            this.labelBatchCode = new System.Windows.Forms.Label();
            this.txtbatchcode = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.searchLookUpEdit2View = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.labelCostingMethod = new System.Windows.Forms.Label();
            this.radioGroupCostingMethod = new DevExpress.XtraEditors.RadioGroup();
            this.btnsave = new DevExpress.XtraEditors.SimpleButton();
            this.txtshipmentno = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.searchLookUpEdit1View = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.label5 = new System.Windows.Forms.Label();
            this.panel1 = new System.Windows.Forms.Panel();
            this.gridControl1 = new DevExpress.XtraGrid.GridControl();
            this.gridView1 = new DevExpress.XtraGrid.Views.Grid.GridView();
            ((System.ComponentModel.ISupportInitialize)(this.groupControl1)).BeginInit();
            this.groupControl1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtbatchcode.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.searchLookUpEdit2View)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.radioGroupCostingMethod.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtshipmentno.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.searchLookUpEdit1View)).BeginInit();
            this.panel1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControl1)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView1)).BeginInit();
            this.SuspendLayout();
            // 
            // groupControl1
            // 
            this.groupControl1.Controls.Add(this.labelBatchCode);
            this.groupControl1.Controls.Add(this.txtbatchcode);
            this.groupControl1.Controls.Add(this.labelCostingMethod);
            this.groupControl1.Controls.Add(this.radioGroupCostingMethod);
            this.groupControl1.Controls.Add(this.btnsave);
            this.groupControl1.Controls.Add(this.txtshipmentno);
            this.groupControl1.Controls.Add(this.label5);
            this.groupControl1.Dock = System.Windows.Forms.DockStyle.Top;
            this.groupControl1.Location = new System.Drawing.Point(0, 0);
            this.groupControl1.Margin = new System.Windows.Forms.Padding(2);
            this.groupControl1.Name = "groupControl1";
            this.groupControl1.Size = new System.Drawing.Size(852, 118);
            this.groupControl1.TabIndex = 0;
            // 
            // labelBatchCode
            // 
            this.labelBatchCode.AutoSize = true;
            this.labelBatchCode.Font = new System.Drawing.Font("Tahoma", 9.75F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.labelBatchCode.Location = new System.Drawing.Point(375, 36);
            this.labelBatchCode.Name = "labelBatchCode";
            this.labelBatchCode.Size = new System.Drawing.Size(85, 16);
            this.labelBatchCode.TabIndex = 33;
            this.labelBatchCode.Text = "Batch Code:";
            this.labelBatchCode.Visible = false;
            // 
            // txtbatchcode
            // 
            this.txtbatchcode.Location = new System.Drawing.Point(480, 33);
            this.txtbatchcode.Margin = new System.Windows.Forms.Padding(2);
            this.txtbatchcode.Name = "txtbatchcode";
            this.txtbatchcode.Properties.Appearance.Font = new System.Drawing.Font("Tahoma", 8.875F);
            this.txtbatchcode.Properties.Appearance.Options.UseFont = true;
            this.txtbatchcode.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtbatchcode.Properties.NullText = "";
            this.txtbatchcode.Properties.PopupView = this.searchLookUpEdit2View;
            this.txtbatchcode.Size = new System.Drawing.Size(129, 20);
            this.txtbatchcode.TabIndex = 34;
            this.txtbatchcode.Visible = false;
            this.txtbatchcode.EditValueChanged += new System.EventHandler(this.txtbatchcode_EditValueChanged);
            // 
            // searchLookUpEdit2View
            // 
            this.searchLookUpEdit2View.DetailHeight = 182;
            this.searchLookUpEdit2View.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.searchLookUpEdit2View.Name = "searchLookUpEdit2View";
            this.searchLookUpEdit2View.OptionsEditForm.PopupEditFormWidth = 257;
            this.searchLookUpEdit2View.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.searchLookUpEdit2View.OptionsView.ShowGroupPanel = false;
            // 
            // labelCostingMethod
            // 
            this.labelCostingMethod.AutoSize = true;
            this.labelCostingMethod.Font = new System.Drawing.Font("Tahoma", 9.75F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.labelCostingMethod.Location = new System.Drawing.Point(8, 73);
            this.labelCostingMethod.Name = "labelCostingMethod";
            this.labelCostingMethod.Size = new System.Drawing.Size(113, 16);
            this.labelCostingMethod.TabIndex = 35;
            this.labelCostingMethod.Text = "Costing Method:";
            // 
            // radioGroupCostingMethod
            // 
            this.radioGroupCostingMethod.EditValue = 0;
            this.radioGroupCostingMethod.Location = new System.Drawing.Point(144, 67);
            this.radioGroupCostingMethod.Margin = new System.Windows.Forms.Padding(2);
            this.radioGroupCostingMethod.Name = "radioGroupCostingMethod";
            this.radioGroupCostingMethod.Properties.Appearance.Font = new System.Drawing.Font("Tahoma", 8.875F);
            this.radioGroupCostingMethod.Properties.Appearance.Options.UseFont = true;
            this.radioGroupCostingMethod.Properties.Items.AddRange(new DevExpress.XtraEditors.Controls.RadioGroupItem[] {
            new DevExpress.XtraEditors.Controls.RadioGroupItem(0, "Per Shipment"),
            new DevExpress.XtraEditors.Controls.RadioGroupItem(1, "Per Shipment + Batch Code")});
            this.radioGroupCostingMethod.Size = new System.Drawing.Size(375, 22);
            this.radioGroupCostingMethod.TabIndex = 36;
            this.radioGroupCostingMethod.EditValueChanged += new System.EventHandler(this.radioGroupCostingMethod_EditValueChanged);
            // 
            // btnsave
            // 
            this.btnsave.Location = new System.Drawing.Point(305, 33);
            this.btnsave.Name = "btnsave";
            this.btnsave.Size = new System.Drawing.Size(52, 23);
            this.btnsave.TabIndex = 32;
            this.btnsave.Text = "Save";
            this.btnsave.Click += new System.EventHandler(this.btnsave_Click);
            // 
            // txtshipmentno
            // 
            this.txtshipmentno.Location = new System.Drawing.Point(144, 33);
            this.txtshipmentno.Margin = new System.Windows.Forms.Padding(2);
            this.txtshipmentno.Name = "txtshipmentno";
            this.txtshipmentno.Properties.Appearance.Font = new System.Drawing.Font("Tahoma", 8.875F);
            this.txtshipmentno.Properties.Appearance.Options.UseFont = true;
            this.txtshipmentno.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtshipmentno.Properties.NullText = "";
            this.txtshipmentno.Properties.PopupView = this.searchLookUpEdit1View;
            this.txtshipmentno.Size = new System.Drawing.Size(157, 20);
            this.txtshipmentno.TabIndex = 31;
            this.txtshipmentno.EditValueChanged += new System.EventHandler(this.searchLookUpEdit_EditValueChanged);
            // 
            // searchLookUpEdit1View
            // 
            this.searchLookUpEdit1View.DetailHeight = 182;
            this.searchLookUpEdit1View.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.searchLookUpEdit1View.Name = "searchLookUpEdit1View";
            this.searchLookUpEdit1View.OptionsEditForm.PopupEditFormWidth = 400;
            this.searchLookUpEdit1View.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.searchLookUpEdit1View.OptionsView.ShowGroupPanel = false;
            // 
            // label5
            // 
            this.label5.AutoSize = true;
            this.label5.Font = new System.Drawing.Font("Tahoma", 9.75F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label5.Location = new System.Drawing.Point(8, 36);
            this.label5.Name = "label5";
            this.label5.Size = new System.Drawing.Size(129, 16);
            this.label5.TabIndex = 30;
            this.label5.Text = "Select Shipment #:";
            // 
            // panel1
            // 
            this.panel1.Controls.Add(this.gridControl1);
            this.panel1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.panel1.Location = new System.Drawing.Point(0, 118);
            this.panel1.Margin = new System.Windows.Forms.Padding(2);
            this.panel1.Name = "panel1";
            this.panel1.Size = new System.Drawing.Size(852, 548);
            this.panel1.TabIndex = 1;
            // 
            // gridControl1
            // 
            this.gridControl1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControl1.Location = new System.Drawing.Point(0, 0);
            this.gridControl1.MainView = this.gridView1;
            this.gridControl1.Name = "gridControl1";
            this.gridControl1.Size = new System.Drawing.Size(852, 548);
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
            this.gridView1.FixedLineWidth = 3;
            this.gridView1.GridControl = this.gridControl1;
            this.gridView1.Name = "gridView1";
            this.gridView1.OptionsEditForm.PopupEditFormWidth = 400;
            this.gridView1.OptionsView.ColumnAutoWidth = false;
            this.gridView1.OptionsView.RowAutoHeight = true;
            this.gridView1.OptionsView.ShowFooter = true;
            this.gridView1.RowCellStyle += new DevExpress.XtraGrid.Views.Grid.RowCellStyleEventHandler(this.gridView1_RowCellStyle_1);
            this.gridView1.ShowingEditor += new System.ComponentModel.CancelEventHandler(this.gridView1_ShowingEditor_1);
            // 
            // PrimalCutCosting
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(852, 666);
            this.Controls.Add(this.panel1);
            this.Controls.Add(this.groupControl1);
            this.Margin = new System.Windows.Forms.Padding(2);
            this.Name = "PrimalCutCosting";
            this.Text = "PrimalCutCosting";
            this.Load += new System.EventHandler(this.PrimalCutCosting_Load);
            ((System.ComponentModel.ISupportInitialize)(this.groupControl1)).EndInit();
            this.groupControl1.ResumeLayout(false);
            this.groupControl1.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtbatchcode.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.searchLookUpEdit2View)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.radioGroupCostingMethod.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtshipmentno.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.searchLookUpEdit1View)).EndInit();
            this.panel1.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControl1)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView1)).EndInit();
            this.ResumeLayout(false);

        }

        #endregion

        private DevExpress.XtraEditors.GroupControl groupControl1;
        private System.Windows.Forms.Panel panel1;
        private DevExpress.XtraEditors.SearchLookUpEdit txtshipmentno;
        private DevExpress.XtraGrid.Views.Grid.GridView searchLookUpEdit1View;
        private System.Windows.Forms.Label label5;
        private DevExpress.XtraEditors.SimpleButton btnsave;
        public DevExpress.XtraGrid.GridControl gridControl1;
        public DevExpress.XtraGrid.Views.Grid.GridView gridView1;
        private System.Windows.Forms.Label labelCostingMethod;
        private DevExpress.XtraEditors.RadioGroup radioGroupCostingMethod;
        private System.Windows.Forms.Label labelBatchCode;
        private DevExpress.XtraEditors.SearchLookUpEdit txtbatchcode;
        private DevExpress.XtraGrid.Views.Grid.GridView searchLookUpEdit2View;
    }
}