namespace SalesInventorySystem.HOFormsDevEx
{
    partial class ConversionPerBarcodeDetails
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
            this.tableLayoutPanel1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlSourceDetails)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewSourceDetails)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlOutputDetails)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewOutputDetails)).BeginInit();
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
            this.tableLayoutPanel1.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Percent, 50F));
            this.tableLayoutPanel1.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Absolute, 26F));
            this.tableLayoutPanel1.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Percent, 50F));
            this.tableLayoutPanel1.Size = new System.Drawing.Size(900, 600);
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
            this.gridControlSourceDetails.Size = new System.Drawing.Size(894, 261);
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
            this.labelControlOutput.Location = new System.Drawing.Point(3, 299);
            this.labelControlOutput.Name = "labelControlOutput";
            this.labelControlOutput.Size = new System.Drawing.Size(894, 20);
            this.labelControlOutput.TabIndex = 2;
            this.labelControlOutput.Text = "Destination / Output Items";
            //
            // gridControlOutputDetails
            //
            this.gridControlOutputDetails.Dock = System.Windows.Forms.DockStyle.Fill;
            this.gridControlOutputDetails.Location = new System.Drawing.Point(3, 328);
            this.gridControlOutputDetails.MainView = this.gridViewOutputDetails;
            this.gridControlOutputDetails.Name = "gridControlOutputDetails";
            this.gridControlOutputDetails.Size = new System.Drawing.Size(894, 269);
            this.gridControlOutputDetails.TabIndex = 3;
            this.gridControlOutputDetails.ViewCollection.AddRange(new DevExpress.XtraGrid.Views.Base.BaseView[] {
            this.gridViewOutputDetails});
            //
            // gridViewOutputDetails
            //
            this.gridViewOutputDetails.GridControl = this.gridControlOutputDetails;
            this.gridViewOutputDetails.Name = "gridViewOutputDetails";
            this.gridViewOutputDetails.OptionsBehavior.Editable = false;
            this.gridViewOutputDetails.OptionsBehavior.ReadOnly = true;
            this.gridViewOutputDetails.OptionsView.ShowFooter = true;
            //
            // ConversionPerBarcodeDetails
            //
            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(900, 600);
            this.Controls.Add(this.tableLayoutPanel1);
            this.Margin = new System.Windows.Forms.Padding(2, 2, 2, 2);
            this.Name = "ConversionPerBarcodeDetails";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "Conversion Details";
            this.Load += new System.EventHandler(this.ConversionPerBarcodeDetails_Load);
            this.tableLayoutPanel1.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.gridControlSourceDetails)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewSourceDetails)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridControlOutputDetails)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.gridViewOutputDetails)).EndInit();
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
    }
}
