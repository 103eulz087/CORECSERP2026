namespace SalesInventorySystem.HOFormsDevEx
{
    partial class PostSingleExpenseForm
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null)) components.Dispose();
            base.Dispose(disposing);
        }

        // ── Header fields ────────────────────────────────────────
        private DevExpress.XtraEditors.LabelControl lblRefNo;
        private DevExpress.XtraEditors.TextEdit txtrefno;
        private DevExpress.XtraEditors.LabelControl lblTicketNo;
        private DevExpress.XtraEditors.TextEdit txtticketno;

        private DevExpress.XtraEditors.CheckEdit chcklinktopo;
        private DevExpress.XtraEditors.SearchLookUpEdit cmblinktopo;

        private DevExpress.XtraEditors.LabelControl lblBranch;
        private DevExpress.XtraEditors.SearchLookUpEdit cmbbranches;

        private DevExpress.XtraEditors.LabelControl lblVendor;
        private DevExpress.XtraEditors.SearchLookUpEdit cmbvendor;

        private DevExpress.XtraEditors.LabelControl lblInvoiceNo;
        private DevExpress.XtraEditors.TextEdit txtinvoiceno;

        private DevExpress.XtraEditors.LabelControl lblExpenseDate;
        private DevExpress.XtraEditors.DateEdit txtexpdate;

        private DevExpress.XtraEditors.LabelControl lblRemarks;
        private DevExpress.XtraEditors.MemoEdit txtremakrs;

        private DevExpress.XtraEditors.LabelControl lblDebitTotal;
        private DevExpress.XtraEditors.LabelControl lbltotaldebit;
        private DevExpress.XtraEditors.LabelControl lblCreditTotal;
        private DevExpress.XtraEditors.LabelControl lbltotalcredit;

        // ── GL entry grid ────────────────────────────────────────
        private DevExpress.XtraEditors.SimpleButton btnAddGLEntry;
        private DevExpress.XtraGrid.GridControl gridControl1;
        private DevExpress.XtraGrid.Views.Grid.GridView gridView1;
        private DevExpress.XtraEditors.Repository.RepositoryItemSearchLookUpEdit repoaccountcode;
        private DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit spindebit;
        private DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit spincredit;

        private DevExpress.XtraEditors.SimpleButton btnSubmit;

        private void InitializeComponent()
        {
            this.components = new System.ComponentModel.Container();

            this.lblRefNo = new DevExpress.XtraEditors.LabelControl();
            this.txtrefno = new DevExpress.XtraEditors.TextEdit();
            this.lblTicketNo = new DevExpress.XtraEditors.LabelControl();
            this.txtticketno = new DevExpress.XtraEditors.TextEdit();

            this.chcklinktopo = new DevExpress.XtraEditors.CheckEdit();
            this.cmblinktopo = new DevExpress.XtraEditors.SearchLookUpEdit();

            this.lblBranch = new DevExpress.XtraEditors.LabelControl();
            this.cmbbranches = new DevExpress.XtraEditors.SearchLookUpEdit();

            this.lblVendor = new DevExpress.XtraEditors.LabelControl();
            this.cmbvendor = new DevExpress.XtraEditors.SearchLookUpEdit();

            this.lblInvoiceNo = new DevExpress.XtraEditors.LabelControl();
            this.txtinvoiceno = new DevExpress.XtraEditors.TextEdit();

            this.lblExpenseDate = new DevExpress.XtraEditors.LabelControl();
            this.txtexpdate = new DevExpress.XtraEditors.DateEdit();

            this.lblRemarks = new DevExpress.XtraEditors.LabelControl();
            this.txtremakrs = new DevExpress.XtraEditors.MemoEdit();

            this.lblDebitTotal = new DevExpress.XtraEditors.LabelControl();
            this.lbltotaldebit = new DevExpress.XtraEditors.LabelControl();
            this.lblCreditTotal = new DevExpress.XtraEditors.LabelControl();
            this.lbltotalcredit = new DevExpress.XtraEditors.LabelControl();

            this.btnAddGLEntry = new DevExpress.XtraEditors.SimpleButton();
            this.gridControl1 = new DevExpress.XtraGrid.GridControl();
            this.gridView1 = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.repoaccountcode = new DevExpress.XtraEditors.Repository.RepositoryItemSearchLookUpEdit();
            this.spindebit = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.spincredit = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();

            this.btnSubmit = new DevExpress.XtraEditors.SimpleButton();

            ((System.ComponentModel.ISupportInitialize)(this.txtrefno.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtticketno.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.chcklinktopo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmblinktopo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbbranches.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbvendor.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtinvoiceno.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtexpdate.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtremakrs.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControl1)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView1)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repoaccountcode)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.spindebit)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.spincredit)).BeginInit();
            this.SuspendLayout();

            // ── Header fields (left column) ───────────────────
            this.lblRefNo.Text = "Reference No:";
            this.lblRefNo.Location = new System.Drawing.Point(16, 20);

            this.txtrefno.Location = new System.Drawing.Point(120, 16);
            this.txtrefno.Size = new System.Drawing.Size(120, 22);
            this.txtrefno.Properties.ReadOnly = true;

            this.lblTicketNo.Text = "Ticket No.:";
            this.lblTicketNo.Location = new System.Drawing.Point(252, 20);

            this.txtticketno.Location = new System.Drawing.Point(324, 16);
            this.txtticketno.Size = new System.Drawing.Size(110, 22);
            this.txtticketno.Properties.ReadOnly = true;

            this.chcklinktopo.Text = "Link to PO";
            this.chcklinktopo.Location = new System.Drawing.Point(446, 18);
            this.chcklinktopo.Properties.Caption = "Link to PO";
            this.chcklinktopo.CheckedChanged += new System.EventHandler(this.Chcklinktopo_CheckedChanged);

            this.cmblinktopo.Location = new System.Drawing.Point(120, 46);
            this.cmblinktopo.Size = new System.Drawing.Size(314, 22);
            this.cmblinktopo.Properties.NullText = "";
            this.cmblinktopo.Enabled = false;

            this.lblBranch.Text = "Branch Code:";
            this.lblBranch.Location = new System.Drawing.Point(16, 78);
            this.cmbbranches.Location = new System.Drawing.Point(120, 74);
            this.cmbbranches.Size = new System.Drawing.Size(314, 22);
            this.cmbbranches.Properties.NullText = "";

            this.lblVendor.Text = "Vendor / Supplier:";
            this.lblVendor.Location = new System.Drawing.Point(16, 106);
            this.cmbvendor.Location = new System.Drawing.Point(120, 102);
            this.cmbvendor.Size = new System.Drawing.Size(314, 22);
            this.cmbvendor.Properties.NullText = "";

            this.lblInvoiceNo.Text = "Invoice No.:";
            this.lblInvoiceNo.Location = new System.Drawing.Point(16, 134);
            this.txtinvoiceno.Location = new System.Drawing.Point(120, 130);
            this.txtinvoiceno.Size = new System.Drawing.Size(314, 22);

            this.lblExpenseDate.Text = "Expense Date:";
            this.lblExpenseDate.Location = new System.Drawing.Point(16, 162);
            this.txtexpdate.Location = new System.Drawing.Point(120, 158);
            this.txtexpdate.Size = new System.Drawing.Size(150, 22);
            this.txtexpdate.Properties.Mask.EditMask = "yyyy-MM-dd";
            this.txtexpdate.Properties.Mask.UseMaskAsDisplayFormat = true;

            this.lblRemarks.Text = "Particulars:";
            this.lblRemarks.Location = new System.Drawing.Point(16, 194);
            this.txtremakrs.Location = new System.Drawing.Point(120, 190);
            this.txtremakrs.Size = new System.Drawing.Size(314, 60);

            this.lblDebitTotal.Text = "Debit:";
            this.lblDebitTotal.Location = new System.Drawing.Point(460, 100);
            this.lbltotaldebit.Text = "0.00";
            this.lbltotaldebit.Font = new System.Drawing.Font("Tahoma", 9.75f, System.Drawing.FontStyle.Bold);
            this.lbltotaldebit.Location = new System.Drawing.Point(510, 100);

            this.lblCreditTotal.Text = "Credit:";
            this.lblCreditTotal.Location = new System.Drawing.Point(460, 122);
            this.lbltotalcredit.Text = "0.00";
            this.lbltotalcredit.Font = new System.Drawing.Font("Tahoma", 9.75f, System.Drawing.FontStyle.Bold);
            this.lbltotalcredit.Location = new System.Drawing.Point(510, 122);

            // ── Add GL Entries button ──────────────────────────
            this.btnAddGLEntry.Text = "Add GL Entries";
            this.btnAddGLEntry.Location = new System.Drawing.Point(120, 262);
            this.btnAddGLEntry.Size = new System.Drawing.Size(150, 30);
            this.btnAddGLEntry.Click += new System.EventHandler(this.BtnAddGLEntry_Click);

            // ── Submit button ───────────────────────────────────
            this.btnSubmit.Text = "Submit";
            this.btnSubmit.Location = new System.Drawing.Point(16, 262);
            this.btnSubmit.Size = new System.Drawing.Size(90, 30);
            this.btnSubmit.Click += new System.EventHandler(this.BtnSubmit_Click);

            // ── Repository items ────────────────────────────────
            this.repoaccountcode.AutoHeight = false;
            this.repoaccountcode.DisplayMember = "AccountCode";
            this.repoaccountcode.ValueMember = "AccountCode";
            this.repoaccountcode.Name = "repoaccountcode";
            this.repoaccountcode.EditValueChanged += new System.EventHandler(this.Repoaccountcode_EditValueChanged);

            this.spindebit.AutoHeight = false;
            this.spindebit.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.spindebit.DisplayFormat.FormatString = "n2";
            this.spindebit.EditFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.spindebit.EditFormat.FormatString = "n2";
            this.spindebit.MaxValue = new decimal(new int[] { 999999999, 0, 0, 0 });
            this.spindebit.MinValue = new decimal(new int[] { 0, 0, 0, 0 });
            this.spindebit.Name = "spindebit";

            this.spincredit.AutoHeight = false;
            this.spincredit.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.spincredit.DisplayFormat.FormatString = "n2";
            this.spincredit.EditFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.spincredit.EditFormat.FormatString = "n2";
            this.spincredit.MaxValue = new decimal(new int[] { 999999999, 0, 0, 0 });
            this.spincredit.MinValue = new decimal(new int[] { 0, 0, 0, 0 });
            this.spincredit.Name = "spincredit";

            // ── Grid ─────────────────────────────────────────────
            this.gridControl1.Location = new System.Drawing.Point(560, 16);
            this.gridControl1.Size = new System.Drawing.Size(700, 690);
            this.gridControl1.Anchor = ((System.Windows.Forms.AnchorStyles)(
                (((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom)
                | System.Windows.Forms.AnchorStyles.Left)
                | System.Windows.Forms.AnchorStyles.Right)));
            this.gridControl1.MainView = this.gridView1;
            this.gridControl1.RepositoryItems.AddRange(new DevExpress.XtraEditors.Repository.RepositoryItem[] {
                this.repoaccountcode, this.spindebit, this.spincredit });
            this.gridControl1.ViewCollection.Add(this.gridView1);

            this.gridView1.GridControl = this.gridControl1;
            this.gridView1.OptionsView.ShowGroupPanel = false;
            this.gridView1.CustomRowCellEdit += new DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventHandler(this.GridView1_CustomRowCellEdit);
            this.gridView1.CellValueChanged += new DevExpress.XtraGrid.Views.Base.CellValueChangedEventHandler(this.GridView1_CellValueChanged);

            // ── Form ─────────────────────────────────────────────
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1276, 720);
            this.Controls.Add(this.lblRefNo);
            this.Controls.Add(this.txtrefno);
            this.Controls.Add(this.lblTicketNo);
            this.Controls.Add(this.txtticketno);
            this.Controls.Add(this.chcklinktopo);
            this.Controls.Add(this.cmblinktopo);
            this.Controls.Add(this.lblBranch);
            this.Controls.Add(this.cmbbranches);
            this.Controls.Add(this.lblVendor);
            this.Controls.Add(this.cmbvendor);
            this.Controls.Add(this.lblInvoiceNo);
            this.Controls.Add(this.txtinvoiceno);
            this.Controls.Add(this.lblExpenseDate);
            this.Controls.Add(this.txtexpdate);
            this.Controls.Add(this.lblRemarks);
            this.Controls.Add(this.txtremakrs);
            this.Controls.Add(this.lblDebitTotal);
            this.Controls.Add(this.lbltotaldebit);
            this.Controls.Add(this.lblCreditTotal);
            this.Controls.Add(this.lbltotalcredit);
            this.Controls.Add(this.btnAddGLEntry);
            this.Controls.Add(this.btnSubmit);
            this.Controls.Add(this.gridControl1);
            this.MinimumSize = new System.Drawing.Size(1100, 620);
            this.Text = "Post Single Expense";

            ((System.ComponentModel.ISupportInitialize)(this.txtrefno.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtticketno.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.chcklinktopo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmblinktopo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbbranches.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cmbvendor.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtinvoiceno.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtexpdate.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtremakrs.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControl1)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridView1)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repoaccountcode)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.spindebit)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.spincredit)).EndInit();
            this.ResumeLayout(false);
        }
    }
}