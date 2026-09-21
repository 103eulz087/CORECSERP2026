namespace SalesInventorySystem.AccountingDevEx
{
    partial class ChartOfAccountsDevEx
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null)) components.Dispose();
            base.Dispose(disposing);
        }

        // ── Grid ─────────────────────────────────────────────────
        private DevExpress.XtraGrid.GridControl gridControlAccounts;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewAccounts;

        // ── Edit panel ───────────────────────────────────────────
        private DevExpress.XtraEditors.GroupControl groupControlEdit;

        private DevExpress.XtraEditors.LabelControl lblAccountCode;
        private DevExpress.XtraEditors.TextEdit txtAccountCode;
        private DevExpress.XtraEditors.LabelControl lblDescription;
        private DevExpress.XtraEditors.TextEdit txtDescription;

        private DevExpress.XtraEditors.LabelControl lblAccountType;
        private DevExpress.XtraEditors.LookUpEdit lueAccountType;
        private DevExpress.XtraEditors.LabelControl lblNature;
        private DevExpress.XtraEditors.LookUpEdit lueNature;

        private DevExpress.XtraEditors.LabelControl lblGLSL;
        private DevExpress.XtraEditors.LookUpEdit lueGLSL;
        private DevExpress.XtraEditors.LabelControl lblYearEndIndicator;
        private DevExpress.XtraEditors.LookUpEdit lueYearEndIndicator;

        private DevExpress.XtraEditors.LabelControl lblLevelNumber;
        private DevExpress.XtraEditors.SpinEdit spinLevelNumber;
        private DevExpress.XtraEditors.LabelControl lblDueToFromIndicator;
        private DevExpress.XtraEditors.LookUpEdit lueDueToFromIndicator;

        private DevExpress.XtraEditors.LabelControl lblSummaryAccount;
        private DevExpress.XtraEditors.LookUpEdit lueSummaryAccount;

        private DevExpress.XtraEditors.LabelControl lblBranchCode;
        private DevExpress.XtraEditors.LookUpEdit lueBranchCode;

        private DevExpress.XtraEditors.SimpleButton btnNew;
        private DevExpress.XtraEditors.SimpleButton btnSave;
        private DevExpress.XtraEditors.SimpleButton btnDelete;
        private DevExpress.XtraEditors.SimpleButton btnRefresh;

        private void InitializeComponent()
        {
            this.components = new System.ComponentModel.Container();

            this.gridControlAccounts = new DevExpress.XtraGrid.GridControl();
            this.gridViewAccounts = new DevExpress.XtraGrid.Views.Grid.GridView();

            this.groupControlEdit = new DevExpress.XtraEditors.GroupControl();

            this.lblAccountCode = new DevExpress.XtraEditors.LabelControl();
            this.txtAccountCode = new DevExpress.XtraEditors.TextEdit();
            this.lblDescription = new DevExpress.XtraEditors.LabelControl();
            this.txtDescription = new DevExpress.XtraEditors.TextEdit();

            this.lblAccountType = new DevExpress.XtraEditors.LabelControl();
            this.lueAccountType = new DevExpress.XtraEditors.LookUpEdit();
            this.lblNature = new DevExpress.XtraEditors.LabelControl();
            this.lueNature = new DevExpress.XtraEditors.LookUpEdit();

            this.lblGLSL = new DevExpress.XtraEditors.LabelControl();
            this.lueGLSL = new DevExpress.XtraEditors.LookUpEdit();
            this.lblYearEndIndicator = new DevExpress.XtraEditors.LabelControl();
            this.lueYearEndIndicator = new DevExpress.XtraEditors.LookUpEdit();

            this.lblLevelNumber = new DevExpress.XtraEditors.LabelControl();
            this.spinLevelNumber = new DevExpress.XtraEditors.SpinEdit();
            this.lblDueToFromIndicator = new DevExpress.XtraEditors.LabelControl();
            this.lueDueToFromIndicator = new DevExpress.XtraEditors.LookUpEdit();

            this.lblSummaryAccount = new DevExpress.XtraEditors.LabelControl();
            this.lueSummaryAccount = new DevExpress.XtraEditors.LookUpEdit();

            this.lblBranchCode = new DevExpress.XtraEditors.LabelControl();
            this.lueBranchCode = new DevExpress.XtraEditors.LookUpEdit();

            this.btnNew = new DevExpress.XtraEditors.SimpleButton();
            this.btnSave = new DevExpress.XtraEditors.SimpleButton();
            this.btnDelete = new DevExpress.XtraEditors.SimpleButton();
            this.btnRefresh = new DevExpress.XtraEditors.SimpleButton();

            ((System.ComponentModel.ISupportInitialize)(this.gridControlAccounts)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewAccounts)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.groupControlEdit)).BeginInit();
            this.groupControlEdit.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtAccountCode.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDescription.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.lueAccountType.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.lueNature.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.lueGLSL.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.lueYearEndIndicator.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.spinLevelNumber.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.lueDueToFromIndicator.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.lueSummaryAccount.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.lueBranchCode.Properties)).BeginInit();
            this.SuspendLayout();

            // ── Grid ─────────────────────────────────────────────
            this.gridControlAccounts.Location = new System.Drawing.Point(16, 16);
            this.gridControlAccounts.Size = new System.Drawing.Size(860, 260);
            this.gridControlAccounts.Anchor = ((System.Windows.Forms.AnchorStyles)(
                ((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left)
                | System.Windows.Forms.AnchorStyles.Right)));
            this.gridControlAccounts.MainView = this.gridViewAccounts;
            this.gridControlAccounts.ViewCollection.Add(this.gridViewAccounts);

            this.gridViewAccounts.GridControl = this.gridControlAccounts;
            this.gridViewAccounts.OptionsView.ShowGroupPanel = false;
            this.gridViewAccounts.OptionsBehavior.Editable = false;
            this.gridViewAccounts.FocusRectStyle = DevExpress.XtraGrid.Views.Grid.DrawFocusRectStyle.RowFocus;
            this.gridViewAccounts.FocusedRowChanged += new DevExpress.XtraGrid.Views.Base.FocusedRowChangedEventHandler(this.gridViewAccounts_FocusedRowChanged);

            // ── Edit panel ───────────────────────────────────────
            this.groupControlEdit.Text = "Account Details";
            this.groupControlEdit.Location = new System.Drawing.Point(16, 286);
            this.groupControlEdit.Size = new System.Drawing.Size(860, 330);
            this.groupControlEdit.Anchor = ((System.Windows.Forms.AnchorStyles)(
                ((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left)
                | System.Windows.Forms.AnchorStyles.Right)));

            // CHANGED: rows widened from 34px to 40px spacing and 22px
            // to 24px control height — the WXI skin renders controls
            // larger at runtime than these hand-picked design-time
            // coordinates assume (this file was hand-authored without
            // a live designer to preview against), so the extra margin
            // avoids clipped/overlapping rows.
            this.lblAccountCode.Text = "Account Code:";
            this.lblAccountCode.Location = new System.Drawing.Point(16, 34);
            this.txtAccountCode.Location = new System.Drawing.Point(140, 30);
            this.txtAccountCode.Size = new System.Drawing.Size(150, 24);
            this.txtAccountCode.Properties.MaxLength = 50;

            this.lblDescription.Text = "Description:";
            this.lblDescription.Location = new System.Drawing.Point(320, 34);
            this.txtDescription.Location = new System.Drawing.Point(410, 30);
            this.txtDescription.Size = new System.Drawing.Size(430, 24);
            this.txtDescription.Properties.MaxLength = 256;

            this.lblAccountType.Text = "Account Type:";
            this.lblAccountType.Location = new System.Drawing.Point(16, 74);
            this.lueAccountType.Location = new System.Drawing.Point(140, 70);
            this.lueAccountType.Size = new System.Drawing.Size(150, 24);

            this.lblNature.Text = "Nature:";
            this.lblNature.Location = new System.Drawing.Point(320, 74);
            this.lueNature.Location = new System.Drawing.Point(410, 70);
            this.lueNature.Size = new System.Drawing.Size(150, 24);

            this.lblGLSL.Text = "GLSL:";
            this.lblGLSL.Location = new System.Drawing.Point(16, 114);
            this.lueGLSL.Location = new System.Drawing.Point(140, 110);
            this.lueGLSL.Size = new System.Drawing.Size(150, 24);

            this.lblYearEndIndicator.Text = "Year-End Indicator:";
            this.lblYearEndIndicator.Location = new System.Drawing.Point(320, 114);
            this.lueYearEndIndicator.Location = new System.Drawing.Point(410, 110);
            this.lueYearEndIndicator.Size = new System.Drawing.Size(150, 24);

            this.lblLevelNumber.Text = "Level Number:";
            this.lblLevelNumber.Location = new System.Drawing.Point(16, 154);
            this.spinLevelNumber.Location = new System.Drawing.Point(140, 150);
            this.spinLevelNumber.Size = new System.Drawing.Size(150, 24);
            this.spinLevelNumber.Properties.MaxValue = new decimal(new int[] { 6, 0, 0, 0 });
            this.spinLevelNumber.Properties.MinValue = new decimal(new int[] { 0, 0, 0, 0 });
            this.spinLevelNumber.Properties.IsFloatValue = false;
            this.spinLevelNumber.Properties.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.spinLevelNumber.Properties.DisplayFormat.FormatString = "N0";
            this.spinLevelNumber.Properties.EditFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            this.spinLevelNumber.Properties.EditFormat.FormatString = "N0";
            this.spinLevelNumber.Properties.NullText = "";

            this.lblDueToFromIndicator.Text = "Due To/From:";
            this.lblDueToFromIndicator.Location = new System.Drawing.Point(320, 154);
            this.lueDueToFromIndicator.Location = new System.Drawing.Point(410, 150);
            this.lueDueToFromIndicator.Size = new System.Drawing.Size(150, 24);

            this.lblSummaryAccount.Text = "Summary Account:";
            this.lblSummaryAccount.Location = new System.Drawing.Point(16, 194);
            this.lueSummaryAccount.Location = new System.Drawing.Point(140, 190);
            this.lueSummaryAccount.Size = new System.Drawing.Size(430, 24);

            this.lblBranchCode.Text = "Branch Code:";
            this.lblBranchCode.Location = new System.Drawing.Point(16, 234);
            this.lueBranchCode.Location = new System.Drawing.Point(140, 230);
            this.lueBranchCode.Size = new System.Drawing.Size(430, 24);

            this.btnNew.Text = "New";
            this.btnNew.Location = new System.Drawing.Point(16, 274);
            this.btnNew.Size = new System.Drawing.Size(90, 34);
            this.btnNew.Click += new System.EventHandler(this.btnNew_Click);

            this.btnSave.Text = "Save";
            this.btnSave.Location = new System.Drawing.Point(114, 274);
            this.btnSave.Size = new System.Drawing.Size(90, 34);
            this.btnSave.Click += new System.EventHandler(this.btnSave_Click);

            this.btnDelete.Text = "Delete";
            this.btnDelete.Location = new System.Drawing.Point(212, 274);
            this.btnDelete.Size = new System.Drawing.Size(90, 34);
            this.btnDelete.Click += new System.EventHandler(this.btnDelete_Click);

            this.btnRefresh.Text = "Refresh";
            this.btnRefresh.Location = new System.Drawing.Point(310, 274);
            this.btnRefresh.Size = new System.Drawing.Size(90, 34);
            this.btnRefresh.Click += new System.EventHandler(this.btnRefresh_Click);

            this.groupControlEdit.Controls.Add(this.lblAccountCode);
            this.groupControlEdit.Controls.Add(this.txtAccountCode);
            this.groupControlEdit.Controls.Add(this.lblDescription);
            this.groupControlEdit.Controls.Add(this.txtDescription);
            this.groupControlEdit.Controls.Add(this.lblAccountType);
            this.groupControlEdit.Controls.Add(this.lueAccountType);
            this.groupControlEdit.Controls.Add(this.lblNature);
            this.groupControlEdit.Controls.Add(this.lueNature);
            this.groupControlEdit.Controls.Add(this.lblGLSL);
            this.groupControlEdit.Controls.Add(this.lueGLSL);
            this.groupControlEdit.Controls.Add(this.lblYearEndIndicator);
            this.groupControlEdit.Controls.Add(this.lueYearEndIndicator);
            this.groupControlEdit.Controls.Add(this.lblLevelNumber);
            this.groupControlEdit.Controls.Add(this.spinLevelNumber);
            this.groupControlEdit.Controls.Add(this.lblDueToFromIndicator);
            this.groupControlEdit.Controls.Add(this.lueDueToFromIndicator);
            this.groupControlEdit.Controls.Add(this.lblSummaryAccount);
            this.groupControlEdit.Controls.Add(this.lueSummaryAccount);
            this.groupControlEdit.Controls.Add(this.lblBranchCode);
            this.groupControlEdit.Controls.Add(this.lueBranchCode);
            this.groupControlEdit.Controls.Add(this.btnNew);
            this.groupControlEdit.Controls.Add(this.btnSave);
            this.groupControlEdit.Controls.Add(this.btnDelete);
            this.groupControlEdit.Controls.Add(this.btnRefresh);

            // ── Form ─────────────────────────────────────────────
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(892, 632);
            this.Controls.Add(this.gridControlAccounts);
            this.Controls.Add(this.groupControlEdit);
            this.MinimumSize = new System.Drawing.Size(700, 540);
            this.Name = "ChartOfAccountsDevEx";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "Chart of Accounts";
            this.Load += new System.EventHandler(this.ChartOfAccountsDevEx_Load);

            ((System.ComponentModel.ISupportInitialize)(this.gridControlAccounts)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewAccounts)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtAccountCode.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtDescription.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.lueAccountType.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.lueNature.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.lueGLSL.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.lueYearEndIndicator.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.spinLevelNumber.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.lueDueToFromIndicator.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.lueSummaryAccount.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.lueBranchCode.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.groupControlEdit)).EndInit();
            this.groupControlEdit.ResumeLayout(false);
            this.ResumeLayout(false);
        }
    }
}
