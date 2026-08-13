namespace SalesInventorySystem.HOFormsDevEx
{
    partial class ClientAdjustmentMemoFrm
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null)) components.Dispose();
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        private DevExpress.XtraEditors.GroupControl grpHeader;
        private DevExpress.XtraEditors.LabelControl lblReferenceNo;
        private DevExpress.XtraEditors.TextEdit txtReferenceNo;
        private DevExpress.XtraEditors.LabelControl lblCustomer;
        private DevExpress.XtraEditors.SearchLookUpEdit txtCustomer;
        private DevExpress.XtraEditors.LabelControl lblMemoDate;
        private DevExpress.XtraEditors.DateEdit txtMemoDate;
        private DevExpress.XtraEditors.LabelControl lblBranch;
        private DevExpress.XtraEditors.LookUpEdit cboBranch;
        private DevExpress.XtraEditors.LabelControl lblInvoiceType;
        private DevExpress.XtraEditors.RadioGroup rgInvoiceType;
        private DevExpress.XtraEditors.LabelControl lblInvoice;
        private DevExpress.XtraEditors.SearchLookUpEdit txtInvoice;
        private DevExpress.XtraEditors.LabelControl lblRemarks;
        private DevExpress.XtraEditors.MemoEdit txtRemarks;

        private DevExpress.XtraEditors.GroupControl grpARLeg;
        private DevExpress.XtraEditors.LabelControl lblARAccount;
        private DevExpress.XtraEditors.SearchLookUpEdit txtARAccount;
        private DevExpress.XtraEditors.LabelControl lblARDebitCredit;
        private DevExpress.XtraEditors.RadioGroup rgARDebitCredit;
        private DevExpress.XtraEditors.LabelControl lblARAmount;
        private DevExpress.XtraEditors.SpinEdit txtARAmount;
        private DevExpress.XtraEditors.LabelControl lblMemoTypePreview;

        private DevExpress.XtraEditors.GroupControl grpOffsetLines;
        private DevExpress.XtraGrid.GridControl gridControlOffset;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewOffset;
        private DevExpress.XtraGrid.Columns.GridColumn colAccountCode;
        private DevExpress.XtraGrid.Columns.GridColumn colDebit;
        private DevExpress.XtraGrid.Columns.GridColumn colCredit;
        private DevExpress.XtraGrid.Columns.GridColumn colParticulars;
        private DevExpress.XtraEditors.Repository.RepositoryItemSearchLookUpEdit repAccountCode;
        private DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit repDebit;
        private DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit repCredit;
        private DevExpress.XtraEditors.Repository.RepositoryItemTextEdit repParticulars;
        private DevExpress.XtraEditors.SimpleButton btnAddLine;
        private DevExpress.XtraEditors.SimpleButton btnRemoveLine;

        private DevExpress.XtraEditors.LabelControl lblTotalDebitCaption;
        private DevExpress.XtraEditors.LabelControl lblTotalDebit;
        private DevExpress.XtraEditors.LabelControl lblTotalCreditCaption;
        private DevExpress.XtraEditors.LabelControl lblTotalCredit;
        private DevExpress.XtraEditors.LabelControl lblBalanceStatus;
        private DevExpress.XtraEditors.SimpleButton btnPost;
        private DevExpress.XtraEditors.SimpleButton btnClose;

        private void InitializeComponent()
        {
            this.components = new System.ComponentModel.Container();

            this.grpHeader = new DevExpress.XtraEditors.GroupControl();
            this.lblReferenceNo = new DevExpress.XtraEditors.LabelControl();
            this.txtReferenceNo = new DevExpress.XtraEditors.TextEdit();
            this.lblCustomer = new DevExpress.XtraEditors.LabelControl();
            this.txtCustomer = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.lblMemoDate = new DevExpress.XtraEditors.LabelControl();
            this.txtMemoDate = new DevExpress.XtraEditors.DateEdit();
            this.lblBranch = new DevExpress.XtraEditors.LabelControl();
            this.cboBranch = new DevExpress.XtraEditors.LookUpEdit();
            this.lblInvoiceType = new DevExpress.XtraEditors.LabelControl();
            this.rgInvoiceType = new DevExpress.XtraEditors.RadioGroup();
            this.lblInvoice = new DevExpress.XtraEditors.LabelControl();
            this.txtInvoice = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.lblRemarks = new DevExpress.XtraEditors.LabelControl();
            this.txtRemarks = new DevExpress.XtraEditors.MemoEdit();

            this.grpARLeg = new DevExpress.XtraEditors.GroupControl();
            this.lblARAccount = new DevExpress.XtraEditors.LabelControl();
            this.txtARAccount = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.lblARDebitCredit = new DevExpress.XtraEditors.LabelControl();
            this.rgARDebitCredit = new DevExpress.XtraEditors.RadioGroup();
            this.lblARAmount = new DevExpress.XtraEditors.LabelControl();
            this.txtARAmount = new DevExpress.XtraEditors.SpinEdit();
            this.lblMemoTypePreview = new DevExpress.XtraEditors.LabelControl();

            this.grpOffsetLines = new DevExpress.XtraEditors.GroupControl();
            this.gridControlOffset = new DevExpress.XtraGrid.GridControl();
            this.gridViewOffset = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.colAccountCode = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colDebit = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colCredit = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colParticulars = new DevExpress.XtraGrid.Columns.GridColumn();
            this.repAccountCode = new DevExpress.XtraEditors.Repository.RepositoryItemSearchLookUpEdit();
            this.repDebit = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.repCredit = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.repParticulars = new DevExpress.XtraEditors.Repository.RepositoryItemTextEdit();
            this.btnAddLine = new DevExpress.XtraEditors.SimpleButton();
            this.btnRemoveLine = new DevExpress.XtraEditors.SimpleButton();

            this.lblTotalDebitCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalDebit = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalCreditCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblTotalCredit = new DevExpress.XtraEditors.LabelControl();
            this.lblBalanceStatus = new DevExpress.XtraEditors.LabelControl();
            this.btnPost = new DevExpress.XtraEditors.SimpleButton();
            this.btnClose = new DevExpress.XtraEditors.SimpleButton();

            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).BeginInit();
            this.grpHeader.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtCustomer.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtMemoDate.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtMemoDate.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranch.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.rgInvoiceType.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtInvoice.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtRemarks.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpARLeg)).BeginInit();
            this.grpARLeg.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtARAccount.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.rgARDebitCredit.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtARAmount.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpOffsetLines)).BeginInit();
            this.grpOffsetLines.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlOffset)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewOffset)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repAccountCode)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repDebit)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repCredit)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repParticulars)).BeginInit();
            this.SuspendLayout();

            // ── grpHeader ──
            this.grpHeader.Location = new System.Drawing.Point(12, 12);
            this.grpHeader.Name = "grpHeader";
            this.grpHeader.Size = new System.Drawing.Size(860, 180);
            this.grpHeader.Text = "Memo Header";
            this.grpHeader.TabIndex = 0;

            this.lblReferenceNo.Location = new System.Drawing.Point(16, 30);
            this.lblReferenceNo.Text = "Reference No.:";
            this.txtReferenceNo.Location = new System.Drawing.Point(120, 27);
            this.txtReferenceNo.Size = new System.Drawing.Size(130, 20);
            this.txtReferenceNo.Properties.ReadOnly = true;

            this.lblCustomer.Location = new System.Drawing.Point(280, 30);
            this.lblCustomer.Text = "Customer:";
            this.txtCustomer.Location = new System.Drawing.Point(360, 27);
            this.txtCustomer.Size = new System.Drawing.Size(320, 20);
            this.txtCustomer.Properties.NullText = "";
            this.txtCustomer.EditValueChanged += new System.EventHandler(this.txtCustomer_EditValueChanged);

            this.lblMemoDate.Location = new System.Drawing.Point(16, 62);
            this.lblMemoDate.Text = "Memo Date:";
            this.txtMemoDate.Location = new System.Drawing.Point(120, 59);
            this.txtMemoDate.Size = new System.Drawing.Size(130, 20);

            this.lblBranch.Location = new System.Drawing.Point(280, 62);
            this.lblBranch.Text = "Branch:";
            this.cboBranch.Location = new System.Drawing.Point(360, 59);
            this.cboBranch.Size = new System.Drawing.Size(200, 20);

            this.lblInvoiceType.Location = new System.Drawing.Point(16, 96);
            this.lblInvoiceType.Text = "Adjustment Target:";
            this.rgInvoiceType.Location = new System.Drawing.Point(120, 92);
            this.rgInvoiceType.Size = new System.Drawing.Size(400, 26);
            this.rgInvoiceType.Properties.Items.AddRange(new DevExpress.XtraEditors.Controls.RadioGroupItem[] {
                new DevExpress.XtraEditors.Controls.RadioGroupItem("INVOICE", "Specific Invoice"),
                new DevExpress.XtraEditors.Controls.RadioGroupItem("ON-ACCOUNT", "On-Account (no invoice)")});
            this.rgInvoiceType.Properties.Appearance.BackColor = System.Drawing.Color.Transparent;
            this.rgInvoiceType.SelectedIndexChanged += new System.EventHandler(this.rgInvoiceType_SelectedIndexChanged);

            this.lblInvoice.Location = new System.Drawing.Point(16, 130);
            this.lblInvoice.Text = "Invoice No.:";
            this.txtInvoice.Location = new System.Drawing.Point(120, 127);
            this.txtInvoice.Size = new System.Drawing.Size(320, 20);
            this.txtInvoice.EditValueChanged += new System.EventHandler(this.txtInvoice_EditValueChanged);

            this.lblRemarks.Location = new System.Drawing.Point(460, 130);
            this.lblRemarks.Text = "Reason / Remarks:";
            this.txtRemarks.Location = new System.Drawing.Point(560, 127);
            this.txtRemarks.Size = new System.Drawing.Size(280, 40);

            this.grpHeader.Controls.Add(this.lblReferenceNo);
            this.grpHeader.Controls.Add(this.txtReferenceNo);
            this.grpHeader.Controls.Add(this.lblCustomer);
            this.grpHeader.Controls.Add(this.txtCustomer);
            this.grpHeader.Controls.Add(this.lblMemoDate);
            this.grpHeader.Controls.Add(this.txtMemoDate);
            this.grpHeader.Controls.Add(this.lblBranch);
            this.grpHeader.Controls.Add(this.cboBranch);
            this.grpHeader.Controls.Add(this.lblInvoiceType);
            this.grpHeader.Controls.Add(this.rgInvoiceType);
            this.grpHeader.Controls.Add(this.lblInvoice);
            this.grpHeader.Controls.Add(this.txtInvoice);
            this.grpHeader.Controls.Add(this.lblRemarks);
            this.grpHeader.Controls.Add(this.txtRemarks);

            // ── grpARLeg ──
            this.grpARLeg.Location = new System.Drawing.Point(12, 200);
            this.grpARLeg.Name = "grpARLeg";
            this.grpARLeg.Size = new System.Drawing.Size(860, 90);
            this.grpARLeg.Text = "Client Balance (AR) Leg";
            this.grpARLeg.TabIndex = 1;

            this.lblARAccount.Location = new System.Drawing.Point(16, 34);
            this.lblARAccount.Text = "AR Account:";
            this.txtARAccount.Location = new System.Drawing.Point(120, 31);
            this.txtARAccount.Size = new System.Drawing.Size(280, 20);

            this.lblARDebitCredit.Location = new System.Drawing.Point(420, 34);
            this.lblARDebitCredit.Text = "Debit / Credit:";
            this.rgARDebitCredit.Location = new System.Drawing.Point(500, 30);
            this.rgARDebitCredit.Size = new System.Drawing.Size(180, 26);
            this.rgARDebitCredit.Properties.Items.AddRange(new DevExpress.XtraEditors.Controls.RadioGroupItem[] {
                new DevExpress.XtraEditors.Controls.RadioGroupItem("D", "Debit"),
                new DevExpress.XtraEditors.Controls.RadioGroupItem("C", "Credit")});
            this.rgARDebitCredit.Properties.Appearance.BackColor = System.Drawing.Color.Transparent;
            this.rgARDebitCredit.SelectedIndexChanged += new System.EventHandler(this.rgARDebitCredit_SelectedIndexChanged);

            this.lblARAmount.Location = new System.Drawing.Point(16, 64);
            this.lblARAmount.Text = "AR Amount:";
            this.txtARAmount.Location = new System.Drawing.Point(120, 61);
            this.txtARAmount.Size = new System.Drawing.Size(150, 20);
            this.txtARAmount.Properties.Mask.EditMask = "n2";
            this.txtARAmount.Properties.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.txtARAmount.Properties.DisplayFormat.FormatString = "n2";
            this.txtARAmount.Properties.EditFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.txtARAmount.Properties.EditFormat.FormatString = "n2";
            this.txtARAmount.Properties.MaxValue = new decimal(new int[] { 999999999, 0, 0, 0 });
            this.txtARAmount.EditValueChanged += new System.EventHandler(this.txtARAmount_EditValueChanged);

            this.lblMemoTypePreview.Location = new System.Drawing.Point(420, 64);
            this.lblMemoTypePreview.Text = "Select Debit/Credit above";
            this.lblMemoTypePreview.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblMemoTypePreview.Appearance.ForeColor = System.Drawing.Color.Gray;

            this.grpARLeg.Controls.Add(this.lblARAccount);
            this.grpARLeg.Controls.Add(this.txtARAccount);
            this.grpARLeg.Controls.Add(this.lblARDebitCredit);
            this.grpARLeg.Controls.Add(this.rgARDebitCredit);
            this.grpARLeg.Controls.Add(this.lblARAmount);
            this.grpARLeg.Controls.Add(this.txtARAmount);
            this.grpARLeg.Controls.Add(this.lblMemoTypePreview);

            // ── grpOffsetLines ──
            this.grpOffsetLines.Location = new System.Drawing.Point(12, 298);
            this.grpOffsetLines.Name = "grpOffsetLines";
            this.grpOffsetLines.Size = new System.Drawing.Size(860, 260);
            this.grpOffsetLines.Text = "Offset Lines (the other side of the entry)";
            this.grpOffsetLines.TabIndex = 2;

            this.gridControlOffset.Location = new System.Drawing.Point(16, 28);
            this.gridControlOffset.Size = new System.Drawing.Size(828, 180);
            this.gridControlOffset.MainView = this.gridViewOffset;
            this.gridControlOffset.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] { this.gridViewOffset });
            this.gridControlOffset.RepositoryItems.AddRange(new DevExpress.XtraEditors.Repository.RepositoryItem[] {
                this.repAccountCode, this.repDebit, this.repCredit, this.repParticulars });

            this.gridViewOffset.GridControl = this.gridControlOffset;
            this.gridViewOffset.Name = "gridViewOffset";
            this.gridViewOffset.OptionsView.ShowGroupPanel = false;
            this.gridViewOffset.Columns.AddRange(new DevExpress.XtraGrid.Columns.GridColumn[] {
                this.colAccountCode, this.colDebit, this.colCredit, this.colParticulars });
            this.gridViewOffset.CustomRowCellEdit += new DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventHandler(this.gridViewOffset_CustomRowCellEdit);
            this.gridViewOffset.CellValueChanged += new DevExpress.XtraGrid.Views.Base.CellValueChangedEventHandler(this.gridViewOffset_CellValueChanged);
            this.gridViewOffset.RowCellStyle += new DevExpress.XtraGrid.Views.Grid.RowCellStyleEventHandler(this.gridViewOffset_RowCellStyle);

            this.colAccountCode.Caption = "Account Code";
            this.colAccountCode.FieldName = "AccountCode";
            this.colAccountCode.Visible = true;
            this.colAccountCode.VisibleIndex = 0;
            this.colAccountCode.Width = 260;

            this.colDebit.Caption = "Debit";
            this.colDebit.FieldName = "Debit";
            this.colDebit.Visible = true;
            this.colDebit.VisibleIndex = 1;
            this.colDebit.Width = 140;

            this.colCredit.Caption = "Credit";
            this.colCredit.FieldName = "Credit";
            this.colCredit.Visible = true;
            this.colCredit.VisibleIndex = 2;
            this.colCredit.Width = 140;

            this.colParticulars.Caption = "Particulars";
            this.colParticulars.FieldName = "Particulars";
            this.colParticulars.Visible = true;
            this.colParticulars.VisibleIndex = 3;
            this.colParticulars.Width = 260;

            this.repAccountCode.AutoHeight = false;
            this.repAccountCode.NullText = "";
            this.repAccountCode.PopupFilterMode = DevExpress.XtraEditors.PopupFilterMode.Contains;

            this.repDebit.AutoHeight = false;
            this.repDebit.Mask.EditMask = "n2";
            this.repDebit.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.repDebit.DisplayFormat.FormatString = "n2";

            this.repCredit.AutoHeight = false;
            this.repCredit.Mask.EditMask = "n2";
            this.repCredit.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.repCredit.DisplayFormat.FormatString = "n2";

            this.repParticulars.AutoHeight = false;

            this.btnAddLine.Location = new System.Drawing.Point(16, 216);
            this.btnAddLine.Size = new System.Drawing.Size(110, 28);
            this.btnAddLine.Text = "Add Line";
            this.btnAddLine.Click += new System.EventHandler(this.btnAddLine_Click);

            this.btnRemoveLine.Location = new System.Drawing.Point(134, 216);
            this.btnRemoveLine.Size = new System.Drawing.Size(110, 28);
            this.btnRemoveLine.Text = "Remove Line";
            this.btnRemoveLine.Click += new System.EventHandler(this.btnRemoveLine_Click);

            this.lblTotalDebitCaption.Location = new System.Drawing.Point(480, 222);
            this.lblTotalDebitCaption.Text = "Total Debit:";
            this.lblTotalDebit.Location = new System.Drawing.Point(560, 222);
            this.lblTotalDebit.Text = "0.00";
            this.lblTotalDebit.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);

            this.lblTotalCreditCaption.Location = new System.Drawing.Point(650, 222);
            this.lblTotalCreditCaption.Text = "Total Credit:";
            this.lblTotalCredit.Location = new System.Drawing.Point(730, 222);
            this.lblTotalCredit.Text = "0.00";
            this.lblTotalCredit.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);

            this.lblBalanceStatus.Location = new System.Drawing.Point(16, 200);
            this.lblBalanceStatus.Text = "";
            this.lblBalanceStatus.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblBalanceStatus.Appearance.ForeColor = System.Drawing.Color.Red;

            this.grpOffsetLines.Controls.Add(this.gridControlOffset);
            this.grpOffsetLines.Controls.Add(this.btnAddLine);
            this.grpOffsetLines.Controls.Add(this.btnRemoveLine);
            this.grpOffsetLines.Controls.Add(this.lblTotalDebitCaption);
            this.grpOffsetLines.Controls.Add(this.lblTotalDebit);
            this.grpOffsetLines.Controls.Add(this.lblTotalCreditCaption);
            this.grpOffsetLines.Controls.Add(this.lblTotalCredit);
            this.grpOffsetLines.Controls.Add(this.lblBalanceStatus);

            // ── action buttons ──
            this.btnPost.Location = new System.Drawing.Point(700, 570);
            this.btnPost.Size = new System.Drawing.Size(85, 32);
            this.btnPost.Text = "Post";
            this.btnPost.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.btnPost.Click += new System.EventHandler(this.btnPost_Click);

            this.btnClose.Location = new System.Drawing.Point(792, 570);
            this.btnClose.Size = new System.Drawing.Size(80, 32);
            this.btnClose.Text = "Close";
            this.btnClose.Click += new System.EventHandler(this.btnClose_Click);

            // ── form ──
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(884, 616);
            this.Controls.Add(this.grpHeader);
            this.Controls.Add(this.grpARLeg);
            this.Controls.Add(this.grpOffsetLines);
            this.Controls.Add(this.btnPost);
            this.Controls.Add(this.btnClose);
            this.Name = "ClientAdjustmentMemoFrm";
            this.Text = "Client Debit / Credit Memo";
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedSingle;
            this.MaximizeBox = false;
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Load += new System.EventHandler(this.ClientAdjustmentMemoFrm_Load);

            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).EndInit();
            this.grpHeader.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtCustomer.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtMemoDate.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtMemoDate.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranch.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.rgInvoiceType.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtInvoice.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtRemarks.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpARLeg)).EndInit();
            this.grpARLeg.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.txtARAccount.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.rgARDebitCredit.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtARAmount.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpOffsetLines)).EndInit();
            this.grpOffsetLines.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlOffset)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewOffset)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repAccountCode)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repDebit)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repCredit)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repParticulars)).EndInit();
            this.ResumeLayout(false);
        }

        #endregion
    }
}