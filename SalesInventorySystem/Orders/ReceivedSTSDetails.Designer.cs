namespace SalesInventorySystem.Orders
{
    partial class ReceivedSTSDetails
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
            this.gridControlMyReq = new DevExpress.XtraGrid.GridControl();
            this.gridViewMyReq = new DevExpress.XtraGrid.Views.Grid.GridView();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlMyReq)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewMyReq)).BeginInit();
            this.SuspendLayout();
            // 
            // gridControlMyReq
            // 
            this.gridControlMyReq.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlMyReq.EmbeddedNavigator.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlMyReq.Location = new System.Drawing.Point(0, 0);
            this.gridControlMyReq.MainView = this.gridViewMyReq;
            this.gridControlMyReq.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.gridControlMyReq.Name = "gridControlMyReq";
            this.gridControlMyReq.Size = new System.Drawing.Size(1578, 922);
            this.gridControlMyReq.TabIndex = 3;
            this.gridControlMyReq.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewMyReq});
            // 
            // gridViewMyReq
            // 
            this.gridViewMyReq.Appearance.HeaderPanel.Font = new System.Drawing.Font("Tahoma", 9.75F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.gridViewMyReq.Appearance.HeaderPanel.Options.UseFont = true;
            this.gridViewMyReq.Appearance.Row.Font = new System.Drawing.Font("Tahoma", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.gridViewMyReq.Appearance.Row.Options.UseFont = true;
            this.gridViewMyReq.DetailHeight = 431;
            this.gridViewMyReq.GridControl = this.gridControlMyReq;
            this.gridViewMyReq.Name = "gridViewMyReq";
            this.gridViewMyReq.OptionsBehavior.Editable = false;
            this.gridViewMyReq.OptionsBehavior.ReadOnly = true;
            this.gridViewMyReq.OptionsView.ColumnAutoWidth = false;
            this.gridViewMyReq.OptionsView.RowAutoHeight = true;
            this.gridViewMyReq.OptionsView.ShowFooter = true;
            // 
            // ReceivedSTSDetails
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1578, 922);
            this.Controls.Add(this.gridControlMyReq);
            this.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.Name = "ReceivedSTSDetails";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "ReceivedSTSDetails";
            this.Load += new System.EventHandler(this.ReceivedSTSDetails_Load);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlMyReq)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewMyReq)).EndInit();
            this.ResumeLayout(false);

        }

        #endregion
        public DevExpress.XtraGrid.GridControl gridControlMyReq;
        public DevExpress.XtraGrid.Views.Grid.GridView gridViewMyReq;
    }
}