namespace SalesInventorySystem.HOFormsDevEx
{
    partial class InventoryQtyAdjustmentDevEx
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
            this.labelControl5 = new DevExpress.XtraEditors.LabelControl();
            this.button2 = new System.Windows.Forms.Button();
            this.button1 = new System.Windows.Forms.Button();
            this.txtqtyadj = new DevExpress.XtraEditors.TextEdit();
            this.labelControl3 = new DevExpress.XtraEditors.LabelControl();
            this.txtbranch = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.gridView1 = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.radadd = new System.Windows.Forms.RadioButton();
            this.raddeduct = new System.Windows.Forms.RadioButton();
            this.labelControl7 = new DevExpress.XtraEditors.LabelControl();
            this.txtproduct = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.gridView3 = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.panel2 = new System.Windows.Forms.Panel();
            ((System.ComponentModel.ISupportInitialize)(this.txtqtyadj.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtbranch.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView1)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtproduct.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView3)).BeginInit();
            this.panel2.SuspendLayout();
            this.SuspendLayout();
            // 
            // labelControl5
            // 
            this.labelControl5.Appearance.Font = new System.Drawing.Font("Tahoma", 10F);
            this.labelControl5.Appearance.Options.UseFont = true;
            this.labelControl5.Location = new System.Drawing.Point(69, 50);
            this.labelControl5.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.labelControl5.Name = "labelControl5";
            this.labelControl5.Size = new System.Drawing.Size(57, 21);
            this.labelControl5.TabIndex = 72;
            this.labelControl5.Text = "Branch:";
            // 
            // button2
            // 
            this.button2.Font = new System.Drawing.Font("Tahoma", 10F);
            this.button2.Location = new System.Drawing.Point(228, 155);
            this.button2.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.button2.Name = "button2";
            this.button2.Size = new System.Drawing.Size(87, 36);
            this.button2.TabIndex = 71;
            this.button2.Text = "Cancel";
            this.button2.UseVisualStyleBackColor = true;
            // 
            // button1
            // 
            this.button1.Font = new System.Drawing.Font("Tahoma", 10F);
            this.button1.Location = new System.Drawing.Point(134, 155);
            this.button1.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.button1.Name = "button1";
            this.button1.Size = new System.Drawing.Size(87, 36);
            this.button1.TabIndex = 70;
            this.button1.Text = "Save";
            this.button1.UseVisualStyleBackColor = true;
            this.button1.Click += new System.EventHandler(this.button1_Click);
            // 
            // txtqtyadj
            // 
            this.txtqtyadj.EditValue = "0";
            this.txtqtyadj.Location = new System.Drawing.Point(134, 119);
            this.txtqtyadj.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtqtyadj.Name = "txtqtyadj";
            this.txtqtyadj.Properties.Appearance.Font = new System.Drawing.Font("Tahoma", 10F);
            this.txtqtyadj.Properties.Appearance.Options.UseFont = true;
            this.txtqtyadj.Size = new System.Drawing.Size(116, 28);
            this.txtqtyadj.TabIndex = 68;
            this.txtqtyadj.EditValueChanged += new System.EventHandler(this.txtqtyadj_EditValueChanged);
            // 
            // labelControl3
            // 
            this.labelControl3.Appearance.Font = new System.Drawing.Font("Tahoma", 10F);
            this.labelControl3.Appearance.Options.UseFont = true;
            this.labelControl3.Location = new System.Drawing.Point(10, 123);
            this.labelControl3.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.labelControl3.Name = "labelControl3";
            this.labelControl3.Size = new System.Drawing.Size(123, 21);
            this.labelControl3.TabIndex = 64;
            this.labelControl3.Text = "Qty Adjustment:";
            // 
            // txtbranch
            // 
            this.txtbranch.Location = new System.Drawing.Point(132, 47);
            this.txtbranch.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtbranch.Name = "txtbranch";
            this.txtbranch.Properties.Appearance.Font = new System.Drawing.Font("Tahoma", 10F);
            this.txtbranch.Properties.Appearance.Options.UseFont = true;
            this.txtbranch.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtbranch.Properties.NullText = "";
            this.txtbranch.Properties.PopupView = this.gridView1;
            this.txtbranch.Size = new System.Drawing.Size(280, 28);
            this.txtbranch.TabIndex = 81;
            this.txtbranch.EditValueChanged += new System.EventHandler(this.txtbranch_EditValueChanged);
            // 
            // gridView1
            // 
            this.gridView1.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.gridView1.Name = "gridView1";
            this.gridView1.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.gridView1.OptionsView.ShowGroupPanel = false;
            // 
            // radadd
            // 
            this.radadd.AutoSize = true;
            this.radadd.Font = new System.Drawing.Font("Tahoma", 9.25F);
            this.radadd.Location = new System.Drawing.Point(2, 4);
            this.radadd.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.radadd.Name = "radadd";
            this.radadd.Size = new System.Drawing.Size(63, 23);
            this.radadd.TabIndex = 82;
            this.radadd.Text = "ADD";
            this.radadd.UseVisualStyleBackColor = true;
            this.radadd.CheckedChanged += new System.EventHandler(this.radadd_CheckedChanged);
            // 
            // raddeduct
            // 
            this.raddeduct.AutoSize = true;
            this.raddeduct.Font = new System.Drawing.Font("Tahoma", 9.25F);
            this.raddeduct.Location = new System.Drawing.Point(69, 4);
            this.raddeduct.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.raddeduct.Name = "raddeduct";
            this.raddeduct.Size = new System.Drawing.Size(92, 23);
            this.raddeduct.TabIndex = 83;
            this.raddeduct.TabStop = true;
            this.raddeduct.Text = "DEDUCT";
            this.raddeduct.UseVisualStyleBackColor = true;
            this.raddeduct.CheckedChanged += new System.EventHandler(this.raddeduct_CheckedChanged);
            // 
            // labelControl7
            // 
            this.labelControl7.Appearance.Font = new System.Drawing.Font("Tahoma", 10F);
            this.labelControl7.Appearance.Options.UseFont = true;
            this.labelControl7.Location = new System.Drawing.Point(62, 87);
            this.labelControl7.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.labelControl7.Name = "labelControl7";
            this.labelControl7.Size = new System.Drawing.Size(62, 21);
            this.labelControl7.TabIndex = 88;
            this.labelControl7.Text = "Product:";
            // 
            // txtproduct
            // 
            this.txtproduct.Location = new System.Drawing.Point(131, 83);
            this.txtproduct.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtproduct.Name = "txtproduct";
            this.txtproduct.Properties.Appearance.Font = new System.Drawing.Font("Tahoma", 10F);
            this.txtproduct.Properties.Appearance.Options.UseFont = true;
            this.txtproduct.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtproduct.Properties.NullText = "";
            this.txtproduct.Properties.PopupView = this.gridView3;
            this.txtproduct.Size = new System.Drawing.Size(278, 28);
            this.txtproduct.TabIndex = 89;
            this.txtproduct.EditValueChanged += new System.EventHandler(this.txtproduct_EditValueChanged);
            // 
            // gridView3
            // 
            this.gridView3.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.gridView3.Name = "gridView3";
            this.gridView3.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.gridView3.OptionsView.ShowGroupPanel = false;
            // 
            // panel2
            // 
            this.panel2.Controls.Add(this.raddeduct);
            this.panel2.Controls.Add(this.radadd);
            this.panel2.Location = new System.Drawing.Point(132, 7);
            this.panel2.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.panel2.Name = "panel2";
            this.panel2.Size = new System.Drawing.Size(234, 32);
            this.panel2.TabIndex = 91;
            // 
            // InventoryQtyAdjustmentDevEx
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(430, 204);
            this.Controls.Add(this.panel2);
            this.Controls.Add(this.txtproduct);
            this.Controls.Add(this.labelControl7);
            this.Controls.Add(this.txtbranch);
            this.Controls.Add(this.labelControl5);
            this.Controls.Add(this.button2);
            this.Controls.Add(this.button1);
            this.Controls.Add(this.txtqtyadj);
            this.Controls.Add(this.labelControl3);
            this.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.Name = "InventoryQtyAdjustmentDevEx";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "InventoryQtyAdjustmentDevEx";
            this.Load += new System.EventHandler(this.InventoryQtyAdjustmentDevEx_Load);
            ((System.ComponentModel.ISupportInitialize)(this.txtqtyadj.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtbranch.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView1)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtproduct.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView3)).EndInit();
            this.panel2.ResumeLayout(false);
            this.panel2.PerformLayout();
            this.ResumeLayout(false);
            this.PerformLayout();

        }

        #endregion
        private DevExpress.XtraEditors.LabelControl labelControl5;
        private System.Windows.Forms.Button button2;
        private System.Windows.Forms.Button button1;
        public DevExpress.XtraEditors.TextEdit txtqtyadj;
        private DevExpress.XtraEditors.LabelControl labelControl3;
        private DevExpress.XtraEditors.SearchLookUpEdit txtbranch;
        private DevExpress.XtraGrid.Views.Grid.GridView gridView1;
        private System.Windows.Forms.RadioButton radadd;
        private System.Windows.Forms.RadioButton raddeduct;
        private DevExpress.XtraEditors.LabelControl labelControl7;
        private DevExpress.XtraEditors.SearchLookUpEdit txtproduct;
        private DevExpress.XtraGrid.Views.Grid.GridView gridView3;
        private System.Windows.Forms.Panel panel2;
    }
}