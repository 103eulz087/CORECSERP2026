namespace SalesInventorySystem.AccountingDevEx
{
    partial class BankReconAutoDebitMatchForm
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null)) components.Dispose();
            base.Dispose(disposing);
        }

        private DevExpress.XtraEditors.LabelControl lblHint;
        private DevExpress.XtraGrid.GridControl grid;
        private DevExpress.XtraGrid.Views.Grid.GridView view;
        private DevExpress.XtraEditors.PanelControl pnlButtons;
        private DevExpress.XtraEditors.SimpleButton btnOK;
        private DevExpress.XtraEditors.SimpleButton btnCancel;

        private void InitializeComponent()
        {
            this.components = new System.ComponentModel.Container();

            this.lblHint = new DevExpress.XtraEditors.LabelControl();
            this.grid = new DevExpress.XtraGrid.GridControl();
            this.view = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.pnlButtons = new DevExpress.XtraEditors.PanelControl();
            this.btnOK = new DevExpress.XtraEditors.SimpleButton();
            this.btnCancel = new DevExpress.XtraEditors.SimpleButton();

            ((System.ComponentModel.ISupportInitialize)(this.grid)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.view)).BeginInit();
            this.SuspendLayout();

            // ── lblHint ──────────────────────────────────────
            this.lblHint.Dock = System.Windows.Forms.DockStyle.Top;
            this.lblHint.Height = 28;
            this.lblHint.Padding = new System.Windows.Forms.Padding(8);
            this.lblHint.AutoSizeMode = DevExpress.XtraEditors.LabelAutoSizeMode.None;
            this.lblHint.Text = "Select the broker invoice this bank debit settles.";

            // ── grid / view ──────────────────────────────────
            this.grid.Dock = System.Windows.Forms.DockStyle.Fill;
            this.grid.MainView = this.view;
            this.grid.ViewCollection.Add(this.view);
            this.view.GridControl = this.grid;
            this.view.OptionsBehavior.Editable = false;
            this.view.OptionsView.ShowGroupPanel = false;
            this.view.OptionsSelection.EnableAppearanceFocusedCell = false;
            this.view.DoubleClick += new System.EventHandler(this.View_DoubleClick);

            // ── pnlButtons ───────────────────────────────────
            this.pnlButtons.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.pnlButtons.Height = 46;
            this.pnlButtons.Controls.Add(this.btnOK);
            this.pnlButtons.Controls.Add(this.btnCancel);

            this.btnOK.Text = "Select";
            this.btnOK.Location = new System.Drawing.Point(420, 10);
            this.btnOK.Size = new System.Drawing.Size(90, 28);
            this.btnOK.Click += new System.EventHandler(this.BtnOK_Click);

            this.btnCancel.Text = "Cancel";
            this.btnCancel.Location = new System.Drawing.Point(516, 10);
            this.btnCancel.Size = new System.Drawing.Size(90, 28);
            this.btnCancel.Click += new System.EventHandler(this.BtnCancel_Click);

            // ── Form ─────────────────────────────────────────
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(620, 420);
            this.Controls.Add(this.grid);
            this.Controls.Add(this.pnlButtons);
            this.Controls.Add(this.lblHint);
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.MinimizeBox = false;
            this.MaximizeBox = false;
            this.ShowInTaskbar = false;
            this.Text = "Match Auto-Debit to Broker Invoice";

            ((System.ComponentModel.ISupportInitialize)(this.grid)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.view)).EndInit();
            this.ResumeLayout(false);
        }
    }
}