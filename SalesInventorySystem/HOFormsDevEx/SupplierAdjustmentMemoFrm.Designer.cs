namespace SalesInventorySystem.HOFormsDevEx
{
    partial class SupplierAdjustmentMemoFrm
    {
        /// <summary>
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        // ── Header controls ──
        private DevExpress.XtraEditors.GroupControl grpHeader;
        private DevExpress.XtraEditors.LabelControl lblReferenceNo;
        private DevExpress.XtraEditors.TextEdit txtReferenceNo;
        private DevExpress.XtraEditors.LabelControl lblSupplier;
        private DevExpress.XtraEditors.SearchLookUpEdit txtSupplier;
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

        // ── AP leg controls ──
        private DevExpress.XtraEditors.GroupControl grpAPLeg;
        private DevExpress.XtraEditors.LabelControl lblAPAccount;
        private DevExpress.XtraEditors.SearchLookUpEdit txtAPAccount;
        private DevExpress.XtraEditors.LabelControl lblAPDebitCredit;
        private DevExpress.XtraEditors.RadioGroup rgAPDebitCredit;
        private DevExpress.XtraEditors.LabelControl lblAPAmount;
        private DevExpress.XtraEditors.SpinEdit txtAPAmount;
        private DevExpress.XtraEditors.LabelControl lblMemoTypePreview;

        // ── Offset lines grid ──
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

        // ── Totals + action buttons ──
        private DevExpress.XtraEditors.LabelControl lblTotalDebitCaption;
        private DevExpress.XtraEditors.LabelControl lblTotalDebit;
        private DevExpress.XtraEditors.LabelControl lblTotalCreditCaption;
        private DevExpress.XtraEditors.LabelControl lblTotalCredit;
        private DevExpress.XtraEditors.LabelControl lblBalanceStatus;
        private DevExpress.XtraEditors.SimpleButton btnPost;
        private DevExpress.XtraEditors.SimpleButton btnClose;

        private void InitializeComponent()
        {
            this.grpHeader = new DevExpress.XtraEditors.GroupControl();
            this.lblReferenceNo = new DevExpress.XtraEditors.LabelControl();
            this.txtReferenceNo = new DevExpress.XtraEditors.TextEdit();
            this.lblSupplier = new DevExpress.XtraEditors.LabelControl();
            this.txtSupplier = new DevExpress.XtraEditors.SearchLookUpEdit();
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
            this.grpAPLeg = new DevExpress.XtraEditors.GroupControl();
            this.lblAPAccount = new DevExpress.XtraEditors.LabelControl();
            this.txtAPAccount = new DevExpress.XtraEditors.SearchLookUpEdit();
            this.lblAPDebitCredit = new DevExpress.XtraEditors.LabelControl();
            this.rgAPDebitCredit = new DevExpress.XtraEditors.RadioGroup();
            this.lblAPAmount = new DevExpress.XtraEditors.LabelControl();
            this.txtAPAmount = new DevExpress.XtraEditors.SpinEdit();
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
            ((System.ComponentModel.ISupportInitialize)(this.txtSupplier.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtMemoDate.Properties.CalendarTimeProperties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtMemoDate.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranch.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.rgInvoiceType.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtInvoice.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtRemarks.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpAPLeg)).BeginInit();
            this.grpAPLeg.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtAPAccount.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.rgAPDebitCredit.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtAPAmount.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpOffsetLines)).BeginInit();
            this.grpOffsetLines.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlOffset)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewOffset)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repAccountCode)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repDebit)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repCredit)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.repParticulars)).BeginInit();
            this.SuspendLayout();
            // 
            // grpHeader
            // 
            this.grpHeader.Controls.Add(this.lblReferenceNo);
            this.grpHeader.Controls.Add(this.txtReferenceNo);
            this.grpHeader.Controls.Add(this.lblSupplier);
            this.grpHeader.Controls.Add(this.txtSupplier);
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
            this.grpHeader.Location = new System.Drawing.Point(14, 15);
            this.grpHeader.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.grpHeader.Name = "grpHeader";
            this.grpHeader.Size = new System.Drawing.Size(1003, 222);
            this.grpHeader.TabIndex = 0;
            this.grpHeader.Text = "Memo Header";
            // 
            // lblReferenceNo
            // 
            this.lblReferenceNo.Location = new System.Drawing.Point(19, 37);
            this.lblReferenceNo.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblReferenceNo.Name = "lblReferenceNo";
            this.lblReferenceNo.Size = new System.Drawing.Size(86, 16);
            this.lblReferenceNo.TabIndex = 0;
            this.lblReferenceNo.Text = "Reference No.:";
            // 
            // txtReferenceNo
            // 
            this.txtReferenceNo.Location = new System.Drawing.Point(140, 33);
            this.txtReferenceNo.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtReferenceNo.Name = "txtReferenceNo";
            this.txtReferenceNo.Properties.ReadOnly = true;
            this.txtReferenceNo.Size = new System.Drawing.Size(152, 22);
            this.txtReferenceNo.TabIndex = 1;
            // 
            // lblSupplier
            // 
            this.lblSupplier.Location = new System.Drawing.Point(327, 37);
            this.lblSupplier.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblSupplier.Name = "lblSupplier";
            this.lblSupplier.Size = new System.Drawing.Size(52, 16);
            this.lblSupplier.TabIndex = 2;
            this.lblSupplier.Text = "Supplier:";
            // 
            // txtSupplier
            // 
            this.txtSupplier.Location = new System.Drawing.Point(420, 33);
            this.txtSupplier.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtSupplier.Name = "txtSupplier";
            this.txtSupplier.Properties.NullText = "";
            this.txtSupplier.Size = new System.Drawing.Size(373, 22);
            this.txtSupplier.TabIndex = 3;
            this.txtSupplier.EditValueChanged += new System.EventHandler(this.txtSupplier_EditValueChanged);
            // 
            // lblMemoDate
            // 
            this.lblMemoDate.Location = new System.Drawing.Point(19, 76);
            this.lblMemoDate.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblMemoDate.Name = "lblMemoDate";
            this.lblMemoDate.Size = new System.Drawing.Size(70, 16);
            this.lblMemoDate.TabIndex = 4;
            this.lblMemoDate.Text = "Memo Date:";
            // 
            // txtMemoDate
            // 
            this.txtMemoDate.EditValue = new System.DateTime(2026, 7, 14, 0, 0, 0, 0);
            this.txtMemoDate.Location = new System.Drawing.Point(140, 73);
            this.txtMemoDate.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtMemoDate.Name = "txtMemoDate";
            this.txtMemoDate.Size = new System.Drawing.Size(152, 22);
            this.txtMemoDate.TabIndex = 5;
            // 
            // lblBranch
            // 
            this.lblBranch.Location = new System.Drawing.Point(327, 76);
            this.lblBranch.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblBranch.Name = "lblBranch";
            this.lblBranch.Size = new System.Drawing.Size(44, 16);
            this.lblBranch.TabIndex = 6;
            this.lblBranch.Text = "Branch:";
            // 
            // cboBranch
            // 
            this.cboBranch.Location = new System.Drawing.Point(420, 73);
            this.cboBranch.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.cboBranch.Name = "cboBranch";
            this.cboBranch.Size = new System.Drawing.Size(233, 22);
            this.cboBranch.TabIndex = 7;
            this.cboBranch.EditValueChanged += new System.EventHandler(this.cboBranch_EditValueChanged);
            // 
            // lblInvoiceType
            // 
            this.lblInvoiceType.Location = new System.Drawing.Point(19, 118);
            this.lblInvoiceType.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblInvoiceType.Name = "lblInvoiceType";
            this.lblInvoiceType.Size = new System.Drawing.Size(112, 16);
            this.lblInvoiceType.TabIndex = 8;
            this.lblInvoiceType.Text = "Adjustment Target:";
            // 
            // rgInvoiceType
            // 
            this.rgInvoiceType.Location = new System.Drawing.Point(140, 113);
            this.rgInvoiceType.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.rgInvoiceType.Name = "rgInvoiceType";
            this.rgInvoiceType.Properties.Appearance.BackColor = System.Drawing.Color.Transparent;
            this.rgInvoiceType.Properties.Appearance.Options.UseBackColor = true;
            this.rgInvoiceType.Properties.Items.AddRange(new DevExpress.XtraEditors.Controls.RadioGroupItem[] {
            new DevExpress.XtraEditors.Controls.RadioGroupItem("PURCHASE", "Purchase Invoice"),
            new DevExpress.XtraEditors.Controls.RadioGroupItem("EXPENSE", "Expense Invoice"),
            new DevExpress.XtraEditors.Controls.RadioGroupItem("ON-ACCOUNT", "On-Account (no invoice)")});
            this.rgInvoiceType.Size = new System.Drawing.Size(467, 32);
            this.rgInvoiceType.TabIndex = 9;
            this.rgInvoiceType.SelectedIndexChanged += new System.EventHandler(this.rgInvoiceType_SelectedIndexChanged);
            // 
            // lblInvoice
            // 
            this.lblInvoice.Location = new System.Drawing.Point(19, 160);
            this.lblInvoice.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblInvoice.Name = "lblInvoice";
            this.lblInvoice.Size = new System.Drawing.Size(68, 16);
            this.lblInvoice.TabIndex = 10;
            this.lblInvoice.Text = "Invoice No.:";
            // 
            // txtInvoice
            // 
            this.txtInvoice.Location = new System.Drawing.Point(140, 156);
            this.txtInvoice.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtInvoice.Name = "txtInvoice";
            this.txtInvoice.Size = new System.Drawing.Size(373, 22);
            this.txtInvoice.TabIndex = 11;
            this.txtInvoice.EditValueChanged += new System.EventHandler(this.txtInvoice_EditValueChanged);
            // 
            // lblRemarks
            // 
            this.lblRemarks.Location = new System.Drawing.Point(537, 160);
            this.lblRemarks.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblRemarks.Name = "lblRemarks";
            this.lblRemarks.Size = new System.Drawing.Size(110, 16);
            this.lblRemarks.TabIndex = 12;
            this.lblRemarks.Text = "Reason / Remarks:";
            // 
            // txtRemarks
            // 
            this.txtRemarks.Location = new System.Drawing.Point(653, 156);
            this.txtRemarks.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtRemarks.Name = "txtRemarks";
            this.txtRemarks.Size = new System.Drawing.Size(327, 49);
            this.txtRemarks.TabIndex = 13;
            // 
            // grpAPLeg
            // 
            this.grpAPLeg.Controls.Add(this.lblAPAccount);
            this.grpAPLeg.Controls.Add(this.txtAPAccount);
            this.grpAPLeg.Controls.Add(this.lblAPDebitCredit);
            this.grpAPLeg.Controls.Add(this.rgAPDebitCredit);
            this.grpAPLeg.Controls.Add(this.lblAPAmount);
            this.grpAPLeg.Controls.Add(this.txtAPAmount);
            this.grpAPLeg.Controls.Add(this.lblMemoTypePreview);
            this.grpAPLeg.Location = new System.Drawing.Point(14, 246);
            this.grpAPLeg.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.grpAPLeg.Name = "grpAPLeg";
            this.grpAPLeg.Size = new System.Drawing.Size(1003, 111);
            this.grpAPLeg.TabIndex = 1;
            this.grpAPLeg.Text = "Supplier Balance (AP) Leg";
            // 
            // lblAPAccount
            // 
            this.lblAPAccount.Location = new System.Drawing.Point(19, 42);
            this.lblAPAccount.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblAPAccount.Name = "lblAPAccount";
            this.lblAPAccount.Size = new System.Drawing.Size(69, 16);
            this.lblAPAccount.TabIndex = 0;
            this.lblAPAccount.Text = "AP Account:";
            // 
            // txtAPAccount
            // 
            this.txtAPAccount.Location = new System.Drawing.Point(140, 38);
            this.txtAPAccount.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtAPAccount.Name = "txtAPAccount";
            this.txtAPAccount.Size = new System.Drawing.Size(327, 22);
            this.txtAPAccount.TabIndex = 1;
            this.txtAPAccount.EditValueChanged += new System.EventHandler(this.txtAPAccount_EditValueChanged);
            // 
            // lblAPDebitCredit
            // 
            this.lblAPDebitCredit.Location = new System.Drawing.Point(490, 42);
            this.lblAPDebitCredit.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblAPDebitCredit.Name = "lblAPDebitCredit";
            this.lblAPDebitCredit.Size = new System.Drawing.Size(81, 16);
            this.lblAPDebitCredit.TabIndex = 2;
            this.lblAPDebitCredit.Text = "Debit / Credit:";
            // 
            // rgAPDebitCredit
            // 
            this.rgAPDebitCredit.Location = new System.Drawing.Point(583, 37);
            this.rgAPDebitCredit.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.rgAPDebitCredit.Name = "rgAPDebitCredit";
            this.rgAPDebitCredit.Properties.Appearance.BackColor = System.Drawing.Color.Transparent;
            this.rgAPDebitCredit.Properties.Appearance.Options.UseBackColor = true;
            this.rgAPDebitCredit.Properties.Items.AddRange(new DevExpress.XtraEditors.Controls.RadioGroupItem[] {
            new DevExpress.XtraEditors.Controls.RadioGroupItem("D", "Debit"),
            new DevExpress.XtraEditors.Controls.RadioGroupItem("C", "Credit")});
            this.rgAPDebitCredit.Size = new System.Drawing.Size(210, 32);
            this.rgAPDebitCredit.TabIndex = 3;
            this.rgAPDebitCredit.SelectedIndexChanged += new System.EventHandler(this.rgAPDebitCredit_SelectedIndexChanged);
            // 
            // lblAPAmount
            // 
            this.lblAPAmount.Location = new System.Drawing.Point(19, 79);
            this.lblAPAmount.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblAPAmount.Name = "lblAPAmount";
            this.lblAPAmount.Size = new System.Drawing.Size(68, 16);
            this.lblAPAmount.TabIndex = 4;
            this.lblAPAmount.Text = "AP Amount:";
            // 
            // txtAPAmount
            // 
            this.txtAPAmount.EditValue = new decimal(new int[] {
            0,
            0,
            0,
            0});
            this.txtAPAmount.Location = new System.Drawing.Point(140, 75);
            this.txtAPAmount.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.txtAPAmount.Name = "txtAPAmount";
            this.txtAPAmount.Properties.DisplayFormat.FormatString = "n2";
            this.txtAPAmount.Properties.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.txtAPAmount.Properties.EditFormat.FormatString = "n2";
            this.txtAPAmount.Properties.EditFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.txtAPAmount.Properties.Mask.EditMask = "n2";
            this.txtAPAmount.Properties.MaxValue = new decimal(new int[] {
            999999999,
            0,
            0,
            0});
            this.txtAPAmount.Size = new System.Drawing.Size(175, 22);
            this.txtAPAmount.TabIndex = 5;
            this.txtAPAmount.EditValueChanged += new System.EventHandler(this.txtAPAmount_EditValueChanged);
            // 
            // lblMemoTypePreview
            // 
            this.lblMemoTypePreview.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblMemoTypePreview.Appearance.ForeColor = System.Drawing.Color.Gray;
            this.lblMemoTypePreview.Appearance.Options.UseFont = true;
            this.lblMemoTypePreview.Appearance.Options.UseForeColor = true;
            this.lblMemoTypePreview.Location = new System.Drawing.Point(490, 79);
            this.lblMemoTypePreview.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblMemoTypePreview.Name = "lblMemoTypePreview";
            this.lblMemoTypePreview.Size = new System.Drawing.Size(195, 18);
            this.lblMemoTypePreview.TabIndex = 6;
            this.lblMemoTypePreview.Text = "Select Debit/Credit above";
            // 
            // grpOffsetLines
            // 
            this.grpOffsetLines.Controls.Add(this.gridControlOffset);
            this.grpOffsetLines.Controls.Add(this.btnAddLine);
            this.grpOffsetLines.Controls.Add(this.btnRemoveLine);
            this.grpOffsetLines.Controls.Add(this.lblTotalDebitCaption);
            this.grpOffsetLines.Controls.Add(this.lblTotalDebit);
            this.grpOffsetLines.Controls.Add(this.lblTotalCreditCaption);
            this.grpOffsetLines.Controls.Add(this.lblTotalCredit);
            this.grpOffsetLines.Controls.Add(this.lblBalanceStatus);
            this.grpOffsetLines.Location = new System.Drawing.Point(14, 367);
            this.grpOffsetLines.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.grpOffsetLines.Name = "grpOffsetLines";
            this.grpOffsetLines.Size = new System.Drawing.Size(1003, 320);
            this.grpOffsetLines.TabIndex = 2;
            this.grpOffsetLines.Text = "Offset Lines (the other side of the entry)";
            // 
            // gridControlOffset
            // 
            this.gridControlOffset.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlOffset.Location = new System.Drawing.Point(19, 34);
            this.gridControlOffset.MainView = this.gridViewOffset;
            this.gridControlOffset.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlOffset.Name = "gridControlOffset";
            this.gridControlOffset.RepositoryItems.AddRange(new DevExpress.XtraEditors.Repository.RepositoryItem[] {
            this.repAccountCode,
            this.repDebit,
            this.repCredit,
            this.repParticulars});
            this.gridControlOffset.Size = new System.Drawing.Size(966, 222);
            this.gridControlOffset.TabIndex = 0;
            this.gridControlOffset.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewOffset});
            // 
            // gridViewOffset
            // 
            this.gridViewOffset.Columns.AddRange(new DevExpress.XtraGrid.Columns.GridColumn[] {
            this.colAccountCode,
            this.colDebit,
            this.colCredit,
            this.colParticulars});
            this.gridViewOffset.DetailHeight = 431;
            this.gridViewOffset.GridControl = this.gridControlOffset;
            this.gridViewOffset.Name = "gridViewOffset";
            this.gridViewOffset.OptionsView.ShowGroupPanel = false;
            this.gridViewOffset.RowCellStyle += new DevExpress.XtraGrid.Views.Grid.RowCellStyleEventHandler(this.gridViewOffset_RowCellStyle);
            this.gridViewOffset.CustomRowCellEdit += new DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventHandler(this.gridViewOffset_CustomRowCellEdit);
            this.gridViewOffset.CellValueChanged += new DevExpress.XtraGrid.Views.Base.CellValueChangedEventHandler(this.gridViewOffset_CellValueChanged);
            // 
            // colAccountCode
            // 
            this.colAccountCode.Caption = "Account Code";
            this.colAccountCode.FieldName = "AccountCode";
            this.colAccountCode.MinWidth = 23;
            this.colAccountCode.Name = "colAccountCode";
            this.colAccountCode.Visible = true;
            this.colAccountCode.VisibleIndex = 0;
            this.colAccountCode.Width = 303;
            // 
            // colDebit
            // 
            this.colDebit.Caption = "Debit";
            this.colDebit.FieldName = "Debit";
            this.colDebit.MinWidth = 23;
            this.colDebit.Name = "colDebit";
            this.colDebit.Visible = true;
            this.colDebit.VisibleIndex = 1;
            this.colDebit.Width = 163;
            // 
            // colCredit
            // 
            this.colCredit.Caption = "Credit";
            this.colCredit.FieldName = "Credit";
            this.colCredit.MinWidth = 23;
            this.colCredit.Name = "colCredit";
            this.colCredit.Visible = true;
            this.colCredit.VisibleIndex = 2;
            this.colCredit.Width = 163;
            // 
            // colParticulars
            // 
            this.colParticulars.Caption = "Particulars";
            this.colParticulars.FieldName = "Particulars";
            this.colParticulars.MinWidth = 23;
            this.colParticulars.Name = "colParticulars";
            this.colParticulars.Visible = true;
            this.colParticulars.VisibleIndex = 3;
            this.colParticulars.Width = 303;
            // 
            // repAccountCode
            // 
            this.repAccountCode.AutoHeight = false;
            this.repAccountCode.Name = "repAccountCode";
            this.repAccountCode.NullText = "";
            this.repAccountCode.PopupFilterMode = DevExpress.XtraEditors.PopupFilterMode.Contains;
            // 
            // repDebit
            // 
            this.repDebit.AutoHeight = false;
            this.repDebit.DisplayFormat.FormatString = "n2";
            this.repDebit.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.repDebit.Mask.EditMask = "n2";
            this.repDebit.Name = "repDebit";
            // 
            // repCredit
            // 
            this.repCredit.AutoHeight = false;
            this.repCredit.DisplayFormat.FormatString = "n2";
            this.repCredit.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.repCredit.Mask.EditMask = "n2";
            this.repCredit.Name = "repCredit";
            // 
            // repParticulars
            // 
            this.repParticulars.AutoHeight = false;
            this.repParticulars.Name = "repParticulars";
            // 
            // btnAddLine
            // 
            this.btnAddLine.Location = new System.Drawing.Point(19, 266);
            this.btnAddLine.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnAddLine.Name = "btnAddLine";
            this.btnAddLine.Size = new System.Drawing.Size(128, 34);
            this.btnAddLine.TabIndex = 1;
            this.btnAddLine.Text = "Add Line";
            this.btnAddLine.Click += new System.EventHandler(this.btnAddLine_Click);
            // 
            // btnRemoveLine
            // 
            this.btnRemoveLine.Location = new System.Drawing.Point(156, 266);
            this.btnRemoveLine.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnRemoveLine.Name = "btnRemoveLine";
            this.btnRemoveLine.Size = new System.Drawing.Size(128, 34);
            this.btnRemoveLine.TabIndex = 2;
            this.btnRemoveLine.Text = "Remove Line";
            this.btnRemoveLine.Click += new System.EventHandler(this.btnRemoveLine_Click);
            // 
            // lblTotalDebitCaption
            // 
            this.lblTotalDebitCaption.Location = new System.Drawing.Point(560, 273);
            this.lblTotalDebitCaption.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblTotalDebitCaption.Name = "lblTotalDebitCaption";
            this.lblTotalDebitCaption.Size = new System.Drawing.Size(67, 16);
            this.lblTotalDebitCaption.TabIndex = 3;
            this.lblTotalDebitCaption.Text = "Total Debit:";
            // 
            // lblTotalDebit
            // 
            this.lblTotalDebit.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblTotalDebit.Appearance.Options.UseFont = true;
            this.lblTotalDebit.Location = new System.Drawing.Point(653, 273);
            this.lblTotalDebit.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblTotalDebit.Name = "lblTotalDebit";
            this.lblTotalDebit.Size = new System.Drawing.Size(35, 18);
            this.lblTotalDebit.TabIndex = 4;
            this.lblTotalDebit.Text = "0.00";
            // 
            // lblTotalCreditCaption
            // 
            this.lblTotalCreditCaption.Location = new System.Drawing.Point(758, 273);
            this.lblTotalCreditCaption.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblTotalCreditCaption.Name = "lblTotalCreditCaption";
            this.lblTotalCreditCaption.Size = new System.Drawing.Size(72, 16);
            this.lblTotalCreditCaption.TabIndex = 5;
            this.lblTotalCreditCaption.Text = "Total Credit:";
            // 
            // lblTotalCredit
            // 
            this.lblTotalCredit.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblTotalCredit.Appearance.Options.UseFont = true;
            this.lblTotalCredit.Location = new System.Drawing.Point(852, 273);
            this.lblTotalCredit.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblTotalCredit.Name = "lblTotalCredit";
            this.lblTotalCredit.Size = new System.Drawing.Size(35, 18);
            this.lblTotalCredit.TabIndex = 6;
            this.lblTotalCredit.Text = "0.00";
            // 
            // lblBalanceStatus
            // 
            this.lblBalanceStatus.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.lblBalanceStatus.Appearance.ForeColor = System.Drawing.Color.Red;
            this.lblBalanceStatus.Appearance.Options.UseFont = true;
            this.lblBalanceStatus.Appearance.Options.UseForeColor = true;
            this.lblBalanceStatus.Location = new System.Drawing.Point(19, 246);
            this.lblBalanceStatus.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.lblBalanceStatus.Name = "lblBalanceStatus";
            this.lblBalanceStatus.Size = new System.Drawing.Size(0, 18);
            this.lblBalanceStatus.TabIndex = 7;
            // 
            // btnPost
            // 
            this.btnPost.Appearance.Font = new System.Drawing.Font("Tahoma", 9F, System.Drawing.FontStyle.Bold);
            this.btnPost.Appearance.Options.UseFont = true;
            this.btnPost.Location = new System.Drawing.Point(817, 702);
            this.btnPost.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnPost.Name = "btnPost";
            this.btnPost.Size = new System.Drawing.Size(99, 39);
            this.btnPost.TabIndex = 3;
            this.btnPost.Text = "Post";
            this.btnPost.Click += new System.EventHandler(this.btnPost_Click);
            // 
            // btnClose
            // 
            this.btnClose.Location = new System.Drawing.Point(924, 702);
            this.btnClose.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.btnClose.Name = "btnClose";
            this.btnClose.Size = new System.Drawing.Size(93, 39);
            this.btnClose.TabIndex = 4;
            this.btnClose.Text = "Close";
            this.btnClose.Click += new System.EventHandler(this.btnClose_Click);
            // 
            // SupplierAdjustmentMemoFrm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1031, 758);
            this.Controls.Add(this.grpHeader);
            this.Controls.Add(this.grpAPLeg);
            this.Controls.Add(this.grpOffsetLines);
            this.Controls.Add(this.btnPost);
            this.Controls.Add(this.btnClose);
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedSingle;
            this.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.MaximizeBox = false;
            this.Name = "SupplierAdjustmentMemoFrm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "Supplier Debit / Credit Memo";
            this.Load += new System.EventHandler(this.SupplierAdjustmentMemoFrm_Load);
            ((System.ComponentModel.ISupportInitialize)(this.grpHeader)).EndInit();
            this.grpHeader.ResumeLayout(false);
            this.grpHeader.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtReferenceNo.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtSupplier.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtMemoDate.Properties.CalendarTimeProperties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtMemoDate.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.cboBranch.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.rgInvoiceType.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtInvoice.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtRemarks.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpAPLeg)).EndInit();
            this.grpAPLeg.ResumeLayout(false);
            this.grpAPLeg.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtAPAccount.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.rgAPDebitCredit.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtAPAmount.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.grpOffsetLines)).EndInit();
            this.grpOffsetLines.ResumeLayout(false);
            this.grpOffsetLines.PerformLayout();
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