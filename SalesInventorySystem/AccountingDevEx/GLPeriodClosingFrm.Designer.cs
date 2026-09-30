namespace SalesInventorySystem.AccountingDevEx
{
    partial class GLPeriodClosingFrm
    {
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

        private void InitializeComponent()
        {
            this.panelTop = new DevExpress.XtraEditors.PanelControl();
            this.lblLocked = new DevExpress.XtraEditors.LabelControl();
            this.lblNext = new DevExpress.XtraEditors.LabelControl();
            this.lblReason = new DevExpress.XtraEditors.LabelControl();
            this.txtReason = new DevExpress.XtraEditors.TextEdit();
            this.btnClosePeriod = new DevExpress.XtraEditors.SimpleButton();
            this.btnReopenPeriod = new DevExpress.XtraEditors.SimpleButton();
            this.btnRefresh = new DevExpress.XtraEditors.SimpleButton();
            this.gridLog = new DevExpress.XtraGrid.GridControl();
            this.gridViewLog = new DevExpress.XtraGrid.Views.Grid.GridView();
            ((System.ComponentModel.ISupportInitialize)(this.panelTop)).BeginInit();
            this.panelTop.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtReason.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridLog)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewLog)).BeginInit();
            this.SuspendLayout();
            //
            // panelTop
            //
            this.panelTop.Controls.Add(this.lblLocked);
            this.panelTop.Controls.Add(this.lblNext);
            this.panelTop.Controls.Add(this.lblReason);
            this.panelTop.Controls.Add(this.txtReason);
            this.panelTop.Controls.Add(this.btnClosePeriod);
            this.panelTop.Controls.Add(this.btnReopenPeriod);
            this.panelTop.Controls.Add(this.btnRefresh);
            this.panelTop.Dock = System.Windows.Forms.DockStyle.Top;
            this.panelTop.Location = new System.Drawing.Point(0, 0);
            this.panelTop.Name = "panelTop";
            this.panelTop.Size = new System.Drawing.Size(784, 150);
            this.panelTop.TabIndex = 0;
            //
            // lblLocked
            //
            this.lblLocked.Appearance.Font = new System.Drawing.Font("Tahoma", 12F, System.Drawing.FontStyle.Bold);
            this.lblLocked.Appearance.Options.UseFont = true;
            this.lblLocked.Location = new System.Drawing.Point(16, 14);
            this.lblLocked.Name = "lblLocked";
            this.lblLocked.Size = new System.Drawing.Size(180, 19);
            this.lblLocked.TabIndex = 0;
            this.lblLocked.Text = "Books closed through: -";
            //
            // lblNext
            //
            this.lblNext.Appearance.Font = new System.Drawing.Font("Tahoma", 9F);
            this.lblNext.Appearance.Options.UseFont = true;
            this.lblNext.Location = new System.Drawing.Point(16, 44);
            this.lblNext.Name = "lblNext";
            this.lblNext.Size = new System.Drawing.Size(140, 14);
            this.lblNext.TabIndex = 1;
            this.lblNext.Text = "Next month to close: -";
            //
            // lblReason
            //
            this.lblReason.Appearance.Font = new System.Drawing.Font("Tahoma", 8F, System.Drawing.FontStyle.Bold);
            this.lblReason.Appearance.Options.UseFont = true;
            this.lblReason.Location = new System.Drawing.Point(16, 77);
            this.lblReason.Name = "lblReason";
            this.lblReason.Size = new System.Drawing.Size(130, 13);
            this.lblReason.TabIndex = 2;
            this.lblReason.Text = "Reason / remarks:";
            //
            // txtReason
            //
            this.txtReason.Location = new System.Drawing.Point(150, 74);
            this.txtReason.Name = "txtReason";
            this.txtReason.Properties.MaxLength = 500;
            this.txtReason.Size = new System.Drawing.Size(610, 20);
            this.txtReason.TabIndex = 3;
            //
            // btnClosePeriod
            //
            this.btnClosePeriod.Location = new System.Drawing.Point(150, 106);
            this.btnClosePeriod.Name = "btnClosePeriod";
            this.btnClosePeriod.Size = new System.Drawing.Size(200, 30);
            this.btnClosePeriod.TabIndex = 4;
            this.btnClosePeriod.Text = "Close Month";
            this.btnClosePeriod.Click += new System.EventHandler(this.btnClosePeriod_Click);
            //
            // btnReopenPeriod
            //
            this.btnReopenPeriod.Location = new System.Drawing.Point(360, 106);
            this.btnReopenPeriod.Name = "btnReopenPeriod";
            this.btnReopenPeriod.Size = new System.Drawing.Size(200, 30);
            this.btnReopenPeriod.TabIndex = 5;
            this.btnReopenPeriod.Text = "Reopen Last Closed Month";
            this.btnReopenPeriod.Click += new System.EventHandler(this.btnReopenPeriod_Click);
            //
            // btnRefresh
            //
            this.btnRefresh.Location = new System.Drawing.Point(570, 106);
            this.btnRefresh.Name = "btnRefresh";
            this.btnRefresh.Size = new System.Drawing.Size(100, 30);
            this.btnRefresh.TabIndex = 6;
            this.btnRefresh.Text = "Refresh";
            this.btnRefresh.Click += new System.EventHandler(this.btnRefresh_Click);
            //
            // gridLog
            //
            this.gridLog.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridLog.Location = new System.Drawing.Point(0, 150);
            this.gridLog.MainView = this.gridViewLog;
            this.gridLog.Name = "gridLog";
            this.gridLog.Size = new System.Drawing.Size(784, 311);
            this.gridLog.TabIndex = 1;
            this.gridLog.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewLog});
            //
            // gridViewLog
            //
            this.gridViewLog.GridControl = this.gridLog;
            this.gridViewLog.Name = "gridViewLog";
            this.gridViewLog.OptionsBehavior.Editable = false;
            this.gridViewLog.OptionsView.ShowGroupPanel = false;
            this.gridViewLog.ViewCaption = "Close / Reopen History";
            this.gridViewLog.OptionsView.ShowViewCaption = true;
            //
            // GLPeriodClosingFrm
            //
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(784, 461);
            this.Controls.Add(this.gridLog);
            this.Controls.Add(this.panelTop);
            this.MinimumSize = new System.Drawing.Size(700, 400);
            this.Name = "GLPeriodClosingFrm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "GL Period Closing";
            this.Load += new System.EventHandler(this.GLPeriodClosingFrm_Load);
            ((System.ComponentModel.ISupportInitialize)(this.panelTop)).EndInit();
            this.panelTop.ResumeLayout(false);
            this.panelTop.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.txtReason.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridLog)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewLog)).EndInit();
            this.ResumeLayout(false);
        }

        #endregion

        private DevExpress.XtraEditors.PanelControl panelTop;
        private DevExpress.XtraEditors.LabelControl lblLocked;
        private DevExpress.XtraEditors.LabelControl lblNext;
        private DevExpress.XtraEditors.LabelControl lblReason;
        private DevExpress.XtraEditors.TextEdit txtReason;
        private DevExpress.XtraEditors.SimpleButton btnClosePeriod;
        private DevExpress.XtraEditors.SimpleButton btnReopenPeriod;
        private DevExpress.XtraEditors.SimpleButton btnRefresh;
        private DevExpress.XtraGrid.GridControl gridLog;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewLog;
    }
}
