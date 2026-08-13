namespace SalesInventorySystem.Accounting
{
    partial class AddCheckVoucher
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
            this.groupBox2 = new System.Windows.Forms.GroupBox();
            this.gridControl1 = new DevExpress.XtraGrid.GridControl();
            this.gridView1 = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.buttonaccountcode = new DevExpress.XtraEditors.Repository.RepositoryItemButtonEdit();
            this.invoiceamount = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.amountpaid = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.datepaid = new DevExpress.XtraEditors.Repository.RepositoryItemDateEdit();
            this.groupBox1 = new System.Windows.Forms.GroupBox();
            this.txtamount = new DevExpress.XtraEditors.TextEdit();
            this.txtcheckno = new DevExpress.XtraEditors.TextEdit();
            this.txtpaidto = new DevExpress.XtraEditors.TextEdit();
            this.labelControl7 = new DevExpress.XtraEditors.LabelControl();
            this.labelControl6 = new DevExpress.XtraEditors.LabelControl();
            this.labelControl5 = new DevExpress.XtraEditors.LabelControl();
            this.txtremarks = new DevExpress.XtraEditors.MemoEdit();
            this.labelControl1 = new DevExpress.XtraEditors.LabelControl();
            this.txtcheckdate = new DevExpress.XtraEditors.DateEdit();
            this.labelControl4 = new DevExpress.XtraEditors.LabelControl();
            this.groupBox3 = new System.Windows.Forms.GroupBox();
            this.simpleButton3 = new DevExpress.XtraEditors.SimpleButton();
            this.simpleButton1 = new DevExpress.XtraEditors.SimpleButton();
            this.simpleButton2 = new DevExpress.XtraEditors.SimpleButton();
            this.groupBox2.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControl1)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView1)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.buttonaccountcode)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.invoiceamount)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.amountpaid)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.datepaid)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.datepaid.CalendarTimeProperties)).BeginInit();
            this.groupBox1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtamount.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtcheckno.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtpaidto.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtremarks.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtcheckdate.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtcheckdate.Properties)).BeginInit();
            this.groupBox3.SuspendLayout();
            this.SuspendLayout();
            // 
            // groupBox2
            // 
            this.groupBox2.BackColor = System.Drawing.Color.White;
            this.groupBox2.Controls.Add(this.gridControl1);
            this.groupBox2.Dock = System.Windows.Forms.DockStyle.Fill;
            this.groupBox2.Location = new System.Drawing.Point(0, 272);
            this.groupBox2.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.groupBox2.Name = "groupBox2";
            this.groupBox2.Padding = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.groupBox2.Size = new System.Drawing.Size(841, 478);
            this.groupBox2.TabIndex = 20;
            this.groupBox2.TabStop = false;
            // 
            // gridControl1
            // 
            this.gridControl1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControl1.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.gridControl1.Location = new System.Drawing.Point(4, 19);
            this.gridControl1.MainView = this.gridView1;
            this.gridControl1.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.gridControl1.Name = "gridControl1";
            this.gridControl1.RepositoryItems.AddRange(new DevExpress.XtraEditors.Repository.RepositoryItem[] {
            this.buttonaccountcode,
            this.invoiceamount,
            this.amountpaid,
            this.datepaid});
            this.gridControl1.Size = new System.Drawing.Size(833, 455);
            this.gridControl1.TabIndex = 0;
            this.gridControl1.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridView1});
            // 
            // gridView1
            // 
            this.gridView1.Appearance.HeaderPanel.Font = new System.Drawing.Font("Tahoma", 8.25F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.gridView1.Appearance.HeaderPanel.Options.UseFont = true;
            this.gridView1.DetailHeight = 431;
            this.gridView1.GridControl = this.gridControl1;
            this.gridView1.Name = "gridView1";
            this.gridView1.OptionsView.ShowFooter = true;
            this.gridView1.OptionsView.ShowGroupPanel = false;
            this.gridView1.CustomRowCellEdit += new DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventHandler(this.gridView1_CustomRowCellEdit);
            // 
            // buttonaccountcode
            // 
            this.buttonaccountcode.AutoHeight = false;
            this.buttonaccountcode.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton()});
            this.buttonaccountcode.Name = "buttonaccountcode";
            this.buttonaccountcode.Click += new System.EventHandler(this.buttonaccountcode_Click);
            // 
            // invoiceamount
            // 
            this.invoiceamount.AutoHeight = false;
            this.invoiceamount.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton()});
            this.invoiceamount.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.invoiceamount.EditFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.invoiceamount.Name = "invoiceamount";
            this.invoiceamount.NullText = "0";
            this.invoiceamount.NullValuePrompt = "0";
            // 
            // amountpaid
            // 
            this.amountpaid.AutoHeight = false;
            this.amountpaid.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton()});
            this.amountpaid.Name = "amountpaid";
            this.amountpaid.NullText = "0";
            // 
            // datepaid
            // 
            this.datepaid.AutoHeight = false;
            this.datepaid.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.datepaid.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.datepaid.Name = "datepaid";
            // 
            // groupBox1
            // 
            this.groupBox1.BackColor = System.Drawing.Color.White;
            this.groupBox1.Controls.Add(this.txtamount);
            this.groupBox1.Controls.Add(this.txtcheckno);
            this.groupBox1.Controls.Add(this.txtpaidto);
            this.groupBox1.Controls.Add(this.labelControl7);
            this.groupBox1.Controls.Add(this.labelControl6);
            this.groupBox1.Controls.Add(this.labelControl5);
            this.groupBox1.Controls.Add(this.txtremarks);
            this.groupBox1.Controls.Add(this.labelControl1);
            this.groupBox1.Controls.Add(this.txtcheckdate);
            this.groupBox1.Controls.Add(this.labelControl4);
            this.groupBox1.Dock = System.Windows.Forms.DockStyle.Top;
            this.groupBox1.Location = new System.Drawing.Point(0, 0);
            this.groupBox1.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.groupBox1.Name = "groupBox1";
            this.groupBox1.Padding = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.groupBox1.Size = new System.Drawing.Size(841, 272);
            this.groupBox1.TabIndex = 19;
            this.groupBox1.TabStop = false;
            // 
            // txtamount
            // 
            this.txtamount.Location = new System.Drawing.Point(639, 58);
            this.txtamount.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.txtamount.Name = "txtamount";
            this.txtamount.Properties.Appearance.Font = new System.Drawing.Font("Tahoma", 10.25F);
            this.txtamount.Properties.Appearance.Options.UseFont = true;
            this.txtamount.Size = new System.Drawing.Size(168, 28);
            this.txtamount.TabIndex = 22;
            this.txtamount.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.txtamount_KeyPress);
            // 
            // txtcheckno
            // 
            this.txtcheckno.Location = new System.Drawing.Point(123, 20);
            this.txtcheckno.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.txtcheckno.Name = "txtcheckno";
            this.txtcheckno.Properties.Appearance.Font = new System.Drawing.Font("Tahoma", 10.25F);
            this.txtcheckno.Properties.Appearance.Options.UseFont = true;
            this.txtcheckno.Size = new System.Drawing.Size(401, 28);
            this.txtcheckno.TabIndex = 21;
            // 
            // txtpaidto
            // 
            this.txtpaidto.Location = new System.Drawing.Point(123, 58);
            this.txtpaidto.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.txtpaidto.Name = "txtpaidto";
            this.txtpaidto.Properties.Appearance.Font = new System.Drawing.Font("Tahoma", 10.25F);
            this.txtpaidto.Properties.Appearance.Options.UseFont = true;
            this.txtpaidto.Size = new System.Drawing.Size(401, 28);
            this.txtpaidto.TabIndex = 13;
            // 
            // labelControl7
            // 
            this.labelControl7.Appearance.Font = new System.Drawing.Font("Tahoma", 10.25F);
            this.labelControl7.Appearance.Options.UseFont = true;
            this.labelControl7.Location = new System.Drawing.Point(24, 23);
            this.labelControl7.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.labelControl7.Name = "labelControl7";
            this.labelControl7.Size = new System.Drawing.Size(80, 21);
            this.labelControl7.TabIndex = 11;
            this.labelControl7.Text = "Check No.:";
            // 
            // labelControl6
            // 
            this.labelControl6.Appearance.Font = new System.Drawing.Font("Tahoma", 10.25F);
            this.labelControl6.Appearance.Options.UseFont = true;
            this.labelControl6.Location = new System.Drawing.Point(48, 62);
            this.labelControl6.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.labelControl6.Name = "labelControl6";
            this.labelControl6.Size = new System.Drawing.Size(61, 21);
            this.labelControl6.TabIndex = 10;
            this.labelControl6.Text = "Paid To:";
            // 
            // labelControl5
            // 
            this.labelControl5.Appearance.Font = new System.Drawing.Font("Tahoma", 10.25F);
            this.labelControl5.Appearance.Options.UseFont = true;
            this.labelControl5.Location = new System.Drawing.Point(37, 164);
            this.labelControl5.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.labelControl5.Name = "labelControl5";
            this.labelControl5.Size = new System.Drawing.Size(71, 21);
            this.labelControl5.TabIndex = 8;
            this.labelControl5.Text = "Remarks:";
            // 
            // txtremarks
            // 
            this.txtremarks.Location = new System.Drawing.Point(123, 95);
            this.txtremarks.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.txtremarks.Name = "txtremarks";
            this.txtremarks.Properties.Appearance.Font = new System.Drawing.Font("Tahoma", 10.25F);
            this.txtremarks.Properties.Appearance.Options.UseFont = true;
            this.txtremarks.Size = new System.Drawing.Size(687, 162);
            this.txtremarks.TabIndex = 9;
            // 
            // labelControl1
            // 
            this.labelControl1.Appearance.Font = new System.Drawing.Font("Tahoma", 10.25F);
            this.labelControl1.Appearance.Options.UseFont = true;
            this.labelControl1.Location = new System.Drawing.Point(532, 23);
            this.labelControl1.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.labelControl1.Name = "labelControl1";
            this.labelControl1.Size = new System.Drawing.Size(91, 21);
            this.labelControl1.TabIndex = 0;
            this.labelControl1.Text = "Check Date:";
            // 
            // txtcheckdate
            // 
            this.txtcheckdate.EditValue = null;
            this.txtcheckdate.Location = new System.Drawing.Point(639, 20);
            this.txtcheckdate.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.txtcheckdate.Name = "txtcheckdate";
            this.txtcheckdate.Properties.Appearance.Font = new System.Drawing.Font("Tahoma", 10.25F);
            this.txtcheckdate.Properties.Appearance.Options.UseFont = true;
            this.txtcheckdate.Properties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton(DevExpress.XtraEditors.Controls.ButtonPredefines.Combo)});
            this.txtcheckdate.Properties.CalendarTimeProperties.Buttons.AddRange(new DevExpress.XtraEditors.Controls.EditorButton[] {
            new DevExpress.XtraEditors.Controls.EditorButton()});
            this.txtcheckdate.Size = new System.Drawing.Size(168, 28);
            this.txtcheckdate.TabIndex = 1;
            // 
            // labelControl4
            // 
            this.labelControl4.Appearance.Font = new System.Drawing.Font("Tahoma", 10.25F);
            this.labelControl4.Appearance.Options.UseFont = true;
            this.labelControl4.Location = new System.Drawing.Point(559, 62);
            this.labelControl4.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.labelControl4.Name = "labelControl4";
            this.labelControl4.Size = new System.Drawing.Size(64, 21);
            this.labelControl4.TabIndex = 6;
            this.labelControl4.Text = "Amount:";
            // 
            // groupBox3
            // 
            this.groupBox3.BackColor = System.Drawing.Color.White;
            this.groupBox3.Controls.Add(this.simpleButton3);
            this.groupBox3.Controls.Add(this.simpleButton1);
            this.groupBox3.Controls.Add(this.simpleButton2);
            this.groupBox3.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.groupBox3.Location = new System.Drawing.Point(0, 691);
            this.groupBox3.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.groupBox3.Name = "groupBox3";
            this.groupBox3.Padding = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.groupBox3.Size = new System.Drawing.Size(841, 59);
            this.groupBox3.TabIndex = 21;
            this.groupBox3.TabStop = false;
            // 
            // simpleButton3
            // 
            this.simpleButton3.Location = new System.Drawing.Point(116, 18);
            this.simpleButton3.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.simpleButton3.Name = "simpleButton3";
            this.simpleButton3.Size = new System.Drawing.Size(100, 28);
            this.simpleButton3.TabIndex = 13;
            this.simpleButton3.Text = "Print";
            this.simpleButton3.Click += new System.EventHandler(this.simpleButton3_Click);
            // 
            // simpleButton1
            // 
            this.simpleButton1.Location = new System.Drawing.Point(8, 18);
            this.simpleButton1.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.simpleButton1.Name = "simpleButton1";
            this.simpleButton1.Size = new System.Drawing.Size(100, 28);
            this.simpleButton1.TabIndex = 11;
            this.simpleButton1.Text = "Add Entry";
            this.simpleButton1.Click += new System.EventHandler(this.simpleButton1_Click);
            // 
            // simpleButton2
            // 
            this.simpleButton2.Location = new System.Drawing.Point(709, 18);
            this.simpleButton2.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.simpleButton2.Name = "simpleButton2";
            this.simpleButton2.Size = new System.Drawing.Size(100, 28);
            this.simpleButton2.TabIndex = 12;
            this.simpleButton2.Text = "Submit";
            this.simpleButton2.Click += new System.EventHandler(this.simpleButton2_Click);
            // 
            // AddCheckVoucher
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.BackColor = System.Drawing.Color.White;
            this.ClientSize = new System.Drawing.Size(841, 750);
            this.Controls.Add(this.groupBox3);
            this.Controls.Add(this.groupBox2);
            this.Controls.Add(this.groupBox1);
            this.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.Name = "AddCheckVoucher";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "AddCheckVoucher";
            this.Load += new System.EventHandler(this.AddCheckVoucher_Load);
            this.groupBox2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControl1)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView1)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.buttonaccountcode)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.invoiceamount)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.amountpaid)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.datepaid.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.datepaid)).EndInit();
            this.groupBox1.ResumeLayout(false);
            this.groupBox1.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtamount.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtcheckno.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtpaidto.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtremarks.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtcheckdate.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtcheckdate.Properties)).EndInit();
            this.groupBox3.ResumeLayout(false);
            this.ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.GroupBox groupBox2;
        public DevExpress.XtraGrid.GridControl gridControl1;
        public DevExpress.XtraGrid.Views.Grid.GridView gridView1;
        private DevExpress.XtraEditors.Repository.RepositoryItemButtonEdit buttonaccountcode;
        private DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit invoiceamount;
        private DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit amountpaid;
        private System.Windows.Forms.GroupBox groupBox1;
        private DevExpress.XtraEditors.TextEdit txtcheckno;
        private DevExpress.XtraEditors.TextEdit txtpaidto;
        private DevExpress.XtraEditors.LabelControl labelControl7;
        private DevExpress.XtraEditors.LabelControl labelControl6;
        private DevExpress.XtraEditors.LabelControl labelControl5;
        private DevExpress.XtraEditors.MemoEdit txtremarks;
        private DevExpress.XtraEditors.LabelControl labelControl1;
        private DevExpress.XtraEditors.DateEdit txtcheckdate;
        private DevExpress.XtraEditors.LabelControl labelControl4;
        private DevExpress.XtraEditors.TextEdit txtamount;
        private System.Windows.Forms.GroupBox groupBox3;
        private DevExpress.XtraEditors.SimpleButton simpleButton1;
        private DevExpress.XtraEditors.SimpleButton simpleButton2;
        private DevExpress.XtraEditors.Repository.RepositoryItemDateEdit datepaid;
        private DevExpress.XtraEditors.SimpleButton simpleButton3;
    }
}