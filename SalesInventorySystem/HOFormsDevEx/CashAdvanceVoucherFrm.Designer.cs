namespace SalesInventorySystem.HOFormsDevEx
{
    partial class CashAdvanceVoucherFrm
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null)) components.Dispose();
            base.Dispose(disposing);
        }

        private DevExpress.XtraEditors.GroupControl grpHeader;
        private DevExpress.XtraEditors.LabelControl lblReferenceNo;
        private DevExpress.XtraEditors.TextEdit txtReferenceNo;
        private DevExpress.XtraEditors.LabelControl lblVoucherID;
        private DevExpress.XtraEditors.TextEdit txtVoucherID;

        private DevExpress.XtraEditors.RadioGroup radVoucherType;
        private DevExpress.XtraEditors.LabelControl lblCheckNo;
        private DevExpress.XtraEditors.TextEdit txtCheckNo;
        private DevExpress.XtraEditors.LabelControl lblCheckDate;
        private DevExpress.XtraEditors.DateEdit txtCheckDate;

        private DevExpress.XtraEditors.LabelControl lblBranch;
        private DevExpress.XtraEditors.LookUpEdit cboBranch;

        private DevExpress.XtraEditors.LabelControl lblSupplier;
        private DevExpress.XtraEditors.SearchLookUpEdit cboSupplier;
        private DevExpress.XtraEditors.LabelControl lblPayeeName;
        private DevExpress.XtraEditors.TextEdit txtPayeeName;

        private DevExpress.XtraEditors.LabelControl lblCreditAccount;
        private DevExpress.XtraEditors.LookUpEdit cboCreditAccount;

        private DevExpress.XtraEditors.LabelControl lblRemarks;
        private DevExpress.XtraEditors.MemoEdit txtRemarks;

        // ── Debit lines grid ─────────────────────────────────────
        private DevExpress.XtraEditors.GroupControl grpLines;
        private DevExpress.XtraGrid.GridControl gridControlLines;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewLines;
        private DevExpress.XtraGrid.Columns.GridColumn colAccountCode;
        private DevExpress.XtraGrid.Columns.GridColumn colPayeeName;
        private DevExpress.XtraGrid.Columns.GridColumn colAmount;
        private DevExpress.XtraGrid.Columns.GridColumn colParticulars;
        private DevExpress.XtraEditors.Repository.RepositoryItemLookUpEdit repDebitAccount;
        private DevExpress.XtraEditors.Repository.RepositoryItemTextEdit repPayeeName;
        private DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit repAmount;
        private DevExpress.XtraEditors.Repository.RepositoryItemTextEdit repParticulars;
        private DevExpress.XtraEditors.SimpleButton btnAddLine;
        private DevExpress.XtraEditors.SimpleButton btnRemoveLine;
        private DevExpress.XtraEditors.LabelControl lblTotalCaption;
        private DevExpress.XtraEditors.LabelControl lblTotal;

        private DevExpress.XtraEditors.SimpleButton btnPost;
        private DevExpress.XtraEditors.SimpleButton btnClose;

        private void InitializeComponent()
        {
            this.grpHeader = new DevExpress.XtraEditors.GroupControl();
            this.lblReferenceNo = new DevExpress.XtraEditors.LabelControl();
            this.txtReferenceNo = new DevExpress.XtraEditors.TextEdit();
            this.lblVoucherID = new DevExpress.XtraEditors.LabelControl();
            this.txtVoucherID = new DevExpress.XtraEditors.TextEdit();
            this.radVoucherType = new DevExpress.XtraEditors.RadioGroup();
            this.lblCheckNo = new DevExpress.XtraEditors.LabelControl();
            this.txtCheckNo = new DevExpress.XtraEditors.TextEdit();
            this.lblCheckDate = new DevExpress.XtraEditors.LabelControl();
            this.txtCheckDate = new DevExpress.XtraEditors.DateEdit();
            this.lblBranch = new DevExpress.XtraEditors.LabelControl();
            this.cboBranch = new DevExpress.XtraEditors.LookUpEdit();
            this.lblSupplier = new DevExpress.XtraEditors.LabelControl();
            this.cboSupplier = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.lblPayeeName = new DevExpress.XtraEditors.LabelControl();
            this.txtPayeeName = new DevExpress.XtraEditors.TextEdit();
            this.lblCreditAccount = new DevExpress.XtraEditors.LabelControl();
            this.cboCreditAccount = new DevExpress.XtraEditors.LookUpEdit();
            this.lblRemarks = new DevExpress.XtraEditors.LabelControl();
            this.txtRemarks = new DevExpress.XtraEditors.MemoEdit();
            this.grpLines = new DevExpress.XtraEditors.GroupControl();
            this.gridControlLines = new DevExpress.XtraGrid.GridControl();
            this.gridViewLines = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.colAccountCode = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colPayeeName = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colAmount = new DevExpress.XtraGrid.Columns.GridColumn();
            this.colParticulars = new DevExpress.XtraGrid.Columns.GridColumn();
            this.repDebitAccount = new DevExpress.XtraEditors.Repository.RepositoryItemLookUpEdit();
            this.repPayeeName = new DevExpress.XtraEditors.Repository.RepositoryItemTextEdit();
            this.repAmount = new DevExpress.XtraEditors.Repository.RepositoryItemSpinEdit();
            this.repParticulars = new DevExpress.XtraEditors.Repository.RepositoryItemTextEdit();
            this.btnAddLine = new DevExpress.XtraEditors.SimpleButton();
            this.btnRemoveLine = new DevExpress.XtraEditors.SimpleButton();
            this.lblTotalCaption = new DevExpress.XtraEditors.LabelControl();
            this.lblTotal = new DevExpress.XtraEditors.LabelControl();
            this.btnPost = new DevExpress.XtraEditors.SimpleButton();
            this.btnClose = new DevExpress.XtraEditors.SimpleButton();
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).BeginInit();
            this.grpHeader.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtVoucherID.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.radVoucherType.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtCheckNo.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtCheckDate.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtCheckDate.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranch.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboSupplier.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtPayeeName.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboCreditAccount.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtRemarks.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpLines)).BeginInit();
            this.grpLines.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlLines)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewLines)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repDebitAccount)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repPayeeName)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repAmount)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repParticulars)).BeginInit();
            this.SuspendLayout();
            // 
            // grpHeader
            // 
            this.grpHeader.Controls.Add(this.lblReferenceNo);
            this.grpHeader.Controls.Add(this.txtReferenceNo);
            this.grpHeader.Controls.Add(this.lblVoucherID);
            this.grpHeader.Controls.Add(this.txtVoucherID);
            this.grpHeader.Controls.Add(this.radVoucherType);
            this.grpHeader.Controls.Add(this.lblCheckNo);
            this.grpHeader.Controls.Add(this.txtCheckNo);
            this.grpHeader.Controls.Add(this.lblCheckDate);
            this.grpHeader.Controls.Add(this.txtCheckDate);
            this.grpHeader.Controls.Add(this.lblBranch);
            this.grpHeader.Controls.Add(this.cboBranch);
            this.grpHeader.Controls.Add(this.lblSupplier);
            this.grpHeader.Controls.Add(this.cboSupplier);
            this.grpHeader.Controls.Add(this.lblPayeeName);
            this.grpHeader.Controls.Add(this.txtPayeeName);
            this.grpHeader.Controls.Add(this.lblCreditAccount);
            this.grpHeader.Controls.Add(this.cboCreditAccount);
            this.grpHeader.Controls.Add(this.lblRemarks);
            this.grpHeader.Controls.Add(this.txtRemarks);
            this.grpHeader.Location = new System.Drawing.Point(14, 14);
            this.grpHeader.Name = "grpHeader";
            this.grpHeader.Size = new System.Drawing.Size(1003, 246);
            this.grpHeader.TabIndex = 0;
            this.grpHeader.Text = "Cash Advance Voucher";
            // 
            // lblReferenceNo
            // 
            this.lblReferenceNo.Location = new System.Drawing.Point(19, 36);
            this.lblReferenceNo.Name = "lblReferenceNo";
            this.lblReferenceNo.Size = new System.Drawing.Size(86, 16);
            this.lblReferenceNo.TabIndex = 0;
            this.lblReferenceNo.Text = "Reference No.:";
            // 
            // txtReferenceNo
            // 
            this.txtReferenceNo.Location = new System.Drawing.Point(175, 33);
            this.txtReferenceNo.Name = "txtReferenceNo";
            this.txtReferenceNo.Properties.ReadOnly = true;
            this.txtReferenceNo.Size = new System.Drawing.Size(140, 22);
            this.txtReferenceNo.TabIndex = 1;
            // 
            // lblVoucherID
            // 
            this.lblVoucherID.Location = new System.Drawing.Point(338, 36);
            this.lblVoucherID.Name = "lblVoucherID";
            this.lblVoucherID.Size = new System.Drawing.Size(68, 16);
            this.lblVoucherID.TabIndex = 2;
            this.lblVoucherID.Text = "Voucher ID:";
            // 
            // txtVoucherID
            // 
            this.txtVoucherID.Location = new System.Drawing.Point(467, 33);
            this.txtVoucherID.Name = "txtVoucherID";
            this.txtVoucherID.Properties.ReadOnly = true;
            this.txtVoucherID.Size = new System.Drawing.Size(163, 22);
            this.txtVoucherID.TabIndex = 3;
            // 
            // radVoucherType
            // 
            this.radVoucherType.EditValue = "CASH";
            this.radVoucherType.Location = new System.Drawing.Point(653, 30);
            this.radVoucherType.Name = "radVoucherType";
            this.radVoucherType.Properties.Items.AddRange(new DevExpress.XtraEditors.Controls.RadioGroupItem[] {
            new DevExpress.XtraEditors.Controls.RadioGroupItem("CASH", "Cash"),
            new DevExpress.XtraEditors.Controls.RadioGroupItem("CHECK", "Check")});
            this.radVoucherType.Size = new System.Drawing.Size(233, 29);
            this.radVoucherType.TabIndex = 4;
            this.radVoucherType.SelectedIndexChanged += new System.EventHandler(this.RadVoucherType_SelectedIndexChanged);
            // 
            // lblCheckNo
            // 
            this.lblCheckNo.Location = new System.Drawing.Point(19, 71);
            this.lblCheckNo.Name = "lblCheckNo";
            this.lblCheckNo.Size = new System.Drawing.Size(62, 16);
            this.lblCheckNo.TabIndex = 5;
            this.lblCheckNo.Text = "Check No.:";
            // 
            // txtCheckNo
            // 
            this.txtCheckNo.Enabled = false;
            this.txtCheckNo.Location = new System.Drawing.Point(175, 67);
            this.txtCheckNo.Name = "txtCheckNo";
            this.txtCheckNo.Size = new System.Drawing.Size(163, 22);
            this.txtCheckNo.TabIndex = 6;
            // 
            // lblCheckDate
            // 
            this.lblCheckDate.Location = new System.Drawing.Point(362, 71);
            this.lblCheckDate.Name = "lblCheckDate";
            this.lblCheckDate.Size = new System.Drawing.Size(69, 16);
            this.lblCheckDate.TabIndex = 7;
            this.lblCheckDate.Text = "Check Date:";
            // 
            // txtCheckDate
            // 
            this.txtCheckDate.EditValue = new System.DateTime(2026, 7, 18, 0, 0, 0, 0);
            this.txtCheckDate.Location = new System.Drawing.Point(467, 67);
            this.txtCheckDate.Name = "txtCheckDate";
            this.txtCheckDate.Size = new System.Drawing.Size(163, 22);
            this.txtCheckDate.TabIndex = 8;
            // 
            // lblBranch
            // 
            this.lblBranch.Location = new System.Drawing.Point(19, 105);
            this.lblBranch.Name = "lblBranch";
            this.lblBranch.Size = new System.Drawing.Size(44, 16);
            this.lblBranch.TabIndex = 9;
            this.lblBranch.Text = "Branch:";
            // 
            // cboBranch
            // 
            this.cboBranch.Location = new System.Drawing.Point(175, 102);
            this.cboBranch.Name = "cboBranch";
            this.cboBranch.Size = new System.Drawing.Size(455, 22);
            this.cboBranch.TabIndex = 10;
            // 
            // lblSupplier
            // 
            this.lblSupplier.Location = new System.Drawing.Point(19, 140);
            this.lblSupplier.Name = "lblSupplier";
            this.lblSupplier.Size = new System.Drawing.Size(111, 16);
            this.lblSupplier.TabIndex = 11;
            this.lblSupplier.Text = "Supplier (optional):";
            // 
            // cboSupplier
            // 
            this.cboSupplier.Location = new System.Drawing.Point(175, 136);
            this.cboSupplier.Name = "cboSupplier";
            this.cboSupplier.Properties.NullText = "— none / not in Supplier master —";
            this.cboSupplier.Size = new System.Drawing.Size(455, 22);
            this.cboSupplier.TabIndex = 12;
            this.cboSupplier.EditValueChanged += new System.EventHandler(this.CboSupplier_EditValueChanged);
            // 
            // lblPayeeName
            // 
            this.lblPayeeName.Location = new System.Drawing.Point(19, 174);
            this.lblPayeeName.Name = "lblPayeeName";
            this.lblPayeeName.Size = new System.Drawing.Size(83, 16);
            this.lblPayeeName.TabIndex = 13;
            this.lblPayeeName.Text = "Default Payee:";
            // 
            // txtPayeeName
            // 
            this.txtPayeeName.Location = new System.Drawing.Point(175, 171);
            this.txtPayeeName.Name = "txtPayeeName";
            this.txtPayeeName.Size = new System.Drawing.Size(455, 22);
            this.txtPayeeName.TabIndex = 14;
            // 
            // lblCreditAccount
            // 
            this.lblCreditAccount.Location = new System.Drawing.Point(653, 105);
            this.lblCreditAccount.Name = "lblCreditAccount";
            this.lblCreditAccount.Size = new System.Drawing.Size(80, 16);
            this.lblCreditAccount.TabIndex = 15;
            this.lblCreditAccount.Text = "Credit (Bank):";
            // 
            // cboCreditAccount
            // 
            this.cboCreditAccount.Location = new System.Drawing.Point(653, 127);
            this.cboCreditAccount.Name = "cboCreditAccount";
            this.cboCreditAccount.Size = new System.Drawing.Size(327, 22);
            this.cboCreditAccount.TabIndex = 16;
            // 
            // lblRemarks
            // 
            this.lblRemarks.Location = new System.Drawing.Point(653, 174);
            this.lblRemarks.Name = "lblRemarks";
            this.lblRemarks.Size = new System.Drawing.Size(55, 16);
            this.lblRemarks.TabIndex = 17;
            this.lblRemarks.Text = "Remarks:";
            // 
            // txtRemarks
            // 
            this.txtRemarks.Location = new System.Drawing.Point(653, 196);
            this.txtRemarks.Name = "txtRemarks";
            this.txtRemarks.Size = new System.Drawing.Size(327, 36);
            this.txtRemarks.TabIndex = 18;
            // 
            // grpLines
            // 
            this.grpLines.Controls.Add(this.gridControlLines);
            this.grpLines.Controls.Add(this.btnAddLine);
            this.grpLines.Controls.Add(this.btnRemoveLine);
            this.grpLines.Controls.Add(this.lblTotalCaption);
            this.grpLines.Controls.Add(this.lblTotal);
            this.grpLines.Location = new System.Drawing.Point(14, 270);
            this.grpLines.Name = "grpLines";
            this.grpLines.Size = new System.Drawing.Size(1003, 369);
            this.grpLines.TabIndex = 1;
            this.grpLines.Text = "Debit Lines (Advance Recipients / Accounts)";
            // 
            // gridControlLines
            // 
            this.gridControlLines.Location = new System.Drawing.Point(19, 34);
            this.gridControlLines.MainView = this.gridViewLines;
            this.gridControlLines.Name = "gridControlLines";
            this.gridControlLines.RepositoryItems.AddRange(new DevExpress.XtraEditors.Repository.RepositoryItem[] {
            this.repDebitAccount,
            this.repPayeeName,
            this.repAmount,
            this.repParticulars});
            this.gridControlLines.Size = new System.Drawing.Size(966, 258);
            this.gridControlLines.TabIndex = 0;
            this.gridControlLines.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewLines});
            // 
            // gridViewLines
            // 
            this.gridViewLines.Columns.AddRange(new DevExpress.XtraGrid.Columns.GridColumn[] {
            this.colAccountCode,
            this.colPayeeName,
            this.colAmount,
            this.colParticulars});
            this.gridViewLines.DetailHeight = 431;
            this.gridViewLines.GridControl = this.gridControlLines;
            this.gridViewLines.Name = "gridViewLines";
            this.gridViewLines.OptionsView.ShowGroupPanel = false;
            this.gridViewLines.RowCellStyle += new DevExpress.XtraGrid.Views.Grid.RowCellStyleEventHandler(this.GridViewLines_RowCellStyle);
            this.gridViewLines.CustomRowCellEdit += new DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventHandler(this.GridViewLines_CustomRowCellEdit);
            this.gridViewLines.CellValueChanged += new DevExpress.XtraGrid.Views.Base.CellValueChangedEventHandler(this.GridViewLines_CellValueChanged);
            // 
            // colAccountCode
            // 
            this.colAccountCode.Caption = "Debit Account";
            this.colAccountCode.FieldName = "AccountCode";
            this.colAccountCode.MinWidth = 23;
            this.colAccountCode.Name = "colAccountCode";
            this.colAccountCode.Visible = true;
            this.colAccountCode.VisibleIndex = 0;
            this.colAccountCode.Width = 303;
            // 
            // colPayeeName
            // 
            this.colPayeeName.Caption = "Payee (optional override)";
            this.colPayeeName.FieldName = "PayeeName";
            this.colPayeeName.MinWidth = 23;
            this.colPayeeName.Name = "colPayeeName";
            this.colPayeeName.Visible = true;
            this.colPayeeName.VisibleIndex = 1;
            this.colPayeeName.Width = 233;
            // 
            // colAmount
            // 
            this.colAmount.Caption = "Amount";
            this.colAmount.FieldName = "Amount";
            this.colAmount.MinWidth = 23;
            this.colAmount.Name = "colAmount";
            this.colAmount.Visible = true;
            this.colAmount.VisibleIndex = 2;
            this.colAmount.Width = 152;
            // 
            // colParticulars
            // 
            this.colParticulars.Caption = "Particulars";
            this.colParticulars.FieldName = "Particulars";
            this.colParticulars.MinWidth = 23;
            this.colParticulars.Name = "colParticulars";
            this.colParticulars.Visible = true;
            this.colParticulars.VisibleIndex = 3;
            this.colParticulars.Width = 257;
            // 
            // repDebitAccount
            // 
            this.repDebitAccount.AutoHeight = false;
            this.repDebitAccount.Name = "repDebitAccount";
            this.repDebitAccount.NullText = "";
            // 
            // repPayeeName
            // 
            this.repPayeeName.AutoHeight = false;
            this.repPayeeName.Name = "repPayeeName";
            // 
            // repAmount
            // 
            this.repAmount.AutoHeight = false;
            this.repAmount.DisplayFormat.FormatString = "n2";
            this.repAmount.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.repAmount.Mask.EditMask = "n2";
            this.repAmount.Name = "repAmount";
            // 
            // repParticulars
            // 
            this.repParticulars.AutoHeight = false;
            this.repParticulars.Name = "repParticulars";
            // 
            // btnAddLine
            // 
            this.btnAddLine.Location = new System.Drawing.Point(19, 302);
            this.btnAddLine.Name = "btnAddLine";
            this.btnAddLine.Size = new System.Drawing.Size(128, 34);
            this.btnAddLine.TabIndex = 1;
            this.btnAddLine.Text = "Add Line";
            this.btnAddLine.Click += new System.EventHandler(this.BtnAddLine_Click);
            // 
            // btnRemoveLine
            // 
            this.btnRemoveLine.Location = new System.Drawing.Point(156, 302);
            this.btnRemoveLine.Name = "btnRemoveLine";
            this.btnRemoveLine.Size = new System.Drawing.Size(128, 34);
            this.btnRemoveLine.TabIndex = 2;
            this.btnRemoveLine.Text = "Remove Line";
            this.btnRemoveLine.Click += new System.EventHandler(this.BtnRemoveLine_Click);
            // 
            // lblTotalCaption
            // 
            this.lblTotalCaption.Location = new System.Drawing.Point(793, 310);
            this.lblTotalCaption.Name = "lblTotalCaption";
            this.lblTotalCaption.Size = new System.Drawing.Size(34, 16);
            this.lblTotalCaption.TabIndex = 3;
            this.lblTotalCaption.Text = "Total:";
            // 
            // lblTotal
            // 
            this.lblTotal.Appearance.Font = new System.Drawing.Font("Tahoma", 9.75F, System.Drawing.FontStyle.Bold);
            this.lblTotal.Appearance.Options.UseFont = true;
            this.lblTotal.Location = new System.Drawing.Point(852, 310);
            this.lblTotal.Name = "lblTotal";
            this.lblTotal.Size = new System.Drawing.Size(35, 19);
            this.lblTotal.TabIndex = 4;
            this.lblTotal.Text = "0.00";
            // 
            // btnPost
            // 
            this.btnPost.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.btnPost.Appearance.Options.UseFont = true;
            this.btnPost.Location = new System.Drawing.Point(817, 657);
            this.btnPost.Name = "btnPost";
            this.btnPost.Size = new System.Drawing.Size(99, 39);
            this.btnPost.TabIndex = 2;
            this.btnPost.Text = "Post";
            this.btnPost.Click += new System.EventHandler(this.BtnPost_Click);
            // 
            // btnClose
            // 
            this.btnClose.Location = new System.Drawing.Point(924, 657);
            this.btnClose.Name = "btnClose";
            this.btnClose.Size = new System.Drawing.Size(93, 39);
            this.btnClose.TabIndex = 3;
            this.btnClose.Text = "Close";
            this.btnClose.Click += new System.EventHandler(this.BtnClose_Click);
            // 
            // CashAdvanceVoucherFrm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1031, 713);
            this.Controls.Add(this.grpHeader);
            this.Controls.Add(this.grpLines);
            this.Controls.Add(this.btnPost);
            this.Controls.Add(this.btnClose);
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedSingle;
            this.MaximizeBox = false;
            this.Name = "CashAdvanceVoucherFrm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "Cash Advance Voucher";
            this.Load += new System.EventHandler(this.CashAdvanceVoucherFrm_Load);
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).EndInit();
            this.grpHeader.ResumeLayout(false);
            this.grpHeader.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtVoucherID.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.radVoucherType.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtCheckNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtCheckDate.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtCheckDate.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranch.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboSupplier.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtPayeeName.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboCreditAccount.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtRemarks.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpLines)).EndInit();
            this.grpLines.ResumeLayout(false);
            this.grpLines.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlLines)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewLines)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repDebitAccount)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repPayeeName)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repAmount)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.repParticulars)).EndInit();
            this.ResumeLayout(false);

        }
    }
}