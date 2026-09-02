namespace SalesInventorySystem.HOFormsDevEx
{
    partial class ConversionPerBarcodeFinalize
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
            this.tableLayoutPanel1 = new System.Windows.Forms.TableLayoutPanel();
            this.labelControlSource = new DevExpress.XtraEditors.LabelControl();
            this.gridControlSourceDetails = new DevExpress.XtraGrid.GridControl();
            this.gridViewSourceDetails = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.labelControlOutput = new DevExpress.XtraEditors.LabelControl();
            this.gridControlOutputDetails = new DevExpress.XtraGrid.GridControl();
            this.gridViewOutputDetails = new DevExpress.XtraGrid.Views.Grid.GridView();
            this.panelButtons = new DevExpress.XtraEditors.PanelControl();
            this.btnFinalize = new DevExpress.XtraEditors.SimpleButton();
            this.btnClose = new DevExpress.XtraEditors.SimpleButton();
            this.tableLayoutPanel1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlSourceDetails)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewSourceDetails)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlOutputDetails)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewOutputDetails)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelButtons)).BeginInit();
            this.panelButtons.SuspendLayout();
            this.SuspendLayout();
            //
            // tableLayoutPanel1
            //
            this.tableLayoutPanel1.ColumnCount = 1;
            this.tableLayoutPanel1.ColumnStyles.Add(new System.Windows.Forms.ColumnStyle(System.Windows.Forms.SizeType.Percent, 100F));
            this.tableLayoutPanel1.Controls.Add(this.labelControlSource, 0, 0);
            this.tableLayoutPanel1.Controls.Add(this.gridControlSourceDetails, 0, 1);
            this.tableLayoutPanel1.Controls.Add(this.labelControlOutput, 0, 2);
            this.tableLayoutPanel1.Controls.Add(this.gridControlOutputDetails, 0, 3);
            this.tableLayoutPanel1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.tableLayoutPanel1.Location = new System.Drawing.Point(0, 0);
            this.tableLayoutPanel1.Name = "tableLayoutPanel1";
            this.tableLayoutPanel1.RowCount = 4;
            this.tableLayoutPanel1.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Absolute, 26F));
            this.tableLayoutPanel1.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Percent, 40F));
            this.tableLayoutPanel1.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Absolute, 26F));
            this.tableLayoutPanel1.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Percent, 60F));
            this.tableLayoutPanel1.Size = new System.Drawing.Size(900, 552);
            this.tableLayoutPanel1.TabIndex = 0;
            //
            // labelControlSource
            //
            this.labelControlSource.Dock = System.Windows.Forms.DockStyle.Fill;
            this.labelControlSource.Location = new System.Drawing.Point(3, 3);
            this.labelControlSource.Name = "labelControlSource";
            this.labelControlSource.Size = new System.Drawing.Size(894, 20);
            this.labelControlSource.TabIndex = 0;
            this.labelControlSource.Text = "Source Items";
            //
            // gridControlSourceDetails
            //
            this.gridControlSourceDetails.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlSourceDetails.Location = new System.Drawing.Point(3, 32);
            this.gridControlSourceDetails.MainView = this.gridViewSourceDetails;
            this.gridControlSourceDetails.Name = "gridControlSourceDetails";
            this.gridControlSourceDetails.Size = new System.Drawing.Size(894, 189);
            this.gridControlSourceDetails.TabIndex = 1;
            this.gridControlSourceDetails.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewSourceDetails});
            //
            // gridViewSourceDetails
            //
            this.gridViewSourceDetails.GridControl = this.gridControlSourceDetails;
            this.gridViewSourceDetails.Name = "gridViewSourceDetails";
            this.gridViewSourceDetails.OptionsBehavior.Editable = false;
            this.gridViewSourceDetails.OptionsBehavior.ReadOnly = true;
            this.gridViewSourceDetails.OptionsView.ShowFooter = true;
            //
            // labelControlOutput
            //
            this.labelControlOutput.Dock = System.Windows.Forms.DockStyle.Fill;
            this.labelControlOutput.Location = new System.Drawing.Point(3, 227);
            this.labelControlOutput.Name = "labelControlOutput";
            this.labelControlOutput.Size = new System.Drawing.Size(894, 20);
            this.labelControlOutput.TabIndex = 2;
            this.labelControlOutput.Text = "Destination / Output Items -- Final Cost is editable (except driploss lines)";
            //
            // gridControlOutputDetails
            //
            this.gridControlOutputDetails.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlOutputDetails.Location = new System.Drawing.Point(3, 256);
            this.gridControlOutputDetails.MainView = this.gridViewOutputDetails;
            this.gridControlOutputDetails.Name = "gridControlOutputDetails";
            this.gridControlOutputDetails.Size = new System.Drawing.Size(894, 293);
            this.gridControlOutputDetails.TabIndex = 3;
            this.gridControlOutputDetails.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewOutputDetails});
            //
            // gridViewOutputDetails
            //
            this.gridViewOutputDetails.GridControl = this.gridControlOutputDetails;
            this.gridViewOutputDetails.Name = "gridViewOutputDetails";
            this.gridViewOutputDetails.OptionsView.ShowFooter = true;
            //
            // panelButtons
            //
            this.panelButtons.Controls.Add(this.btnFinalize);
            this.panelButtons.Controls.Add(this.btnClose);
            this.panelButtons.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.panelButtons.Location = new System.Drawing.Point(0, 552);
            this.panelButtons.Name = "panelButtons";
            this.panelButtons.Size = new System.Drawing.Size(900, 48);
            this.panelButtons.TabIndex = 1;
            //
            // btnFinalize
            //
            this.btnFinalize.Appearance.Font = new System.Drawing.Font("Arial", 10.25F);
            this.btnFinalize.Appearance.Options.UseFont = true;
            this.btnFinalize.Location = new System.Drawing.Point(694, 10);
            this.btnFinalize.Name = "btnFinalize";
            this.btnFinalize.Size = new System.Drawing.Size(100, 30);
            this.btnFinalize.TabIndex = 0;
            this.btnFinalize.Text = "Finalize";
            this.btnFinalize.Click += new System.EventHandler(this.btnFinalize_Click);
            //
            // btnClose
            //
            this.btnClose.Location = new System.Drawing.Point(800, 10);
            this.btnClose.Name = "btnClose";
            this.btnClose.Size = new System.Drawing.Size(88, 30);
            this.btnClose.TabIndex = 1;
            this.btnClose.Text = "Close";
            this.btnClose.Click += new System.EventHandler(this.btnClose_Click);
            //
            // ConversionPerBarcodeFinalize
            //
            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(900, 600);
            this.Controls.Add(this.tableLayoutPanel1);
            this.Controls.Add(this.panelButtons);
            this.Margin = new System.Windows.Forms.Padding(2, 2, 2, 2);
            this.Name = "ConversionPerBarcodeFinalize";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "Finalize Conversion";
            this.Load += new System.EventHandler(this.ConversionPerBarcodeFinalize_Load);
            this.tableLayoutPanel1.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlSourceDetails)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewSourceDetails)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlOutputDetails)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewOutputDetails)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.panelButtons)).EndInit();
            this.panelButtons.ResumeLayout(false);
            this.ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.TableLayoutPanel tableLayoutPanel1;
        private DevExpress.XtraEditors.LabelControl labelControlSource;
        private DevExpress.XtraGrid.GridControl gridControlSourceDetails;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewSourceDetails;
        private DevExpress.XtraEditors.LabelControl labelControlOutput;
        private DevExpress.XtraGrid.GridControl gridControlOutputDetails;
        private DevExpress.XtraGrid.Views.Grid.GridView gridViewOutputDetails;
        private DevExpress.XtraEditors.PanelControl panelButtons;
        private DevExpress.XtraEditors.SimpleButton btnFinalize;
        private DevExpress.XtraEditors.SimpleButton btnClose;
    }
}
