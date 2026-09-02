namespace SalesInventorySystem
{
    partial class Login
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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(Login));
            this.txtuserid = new DevExpress.XtraEditors.TextEdit();
            this.txtpassword = new DevExpress.XtraEditors.TextEdit();
            this.buttonLogin = new DevExpress.XtraEditors.SimpleButton();
            this.btnclose = new DevExpress.XtraEditors.SimpleButton();
            this.PictureBox1 = new System.Windows.Forms.PictureBox();
            ((System.ComponentModel.ISupportInitialize)(this.txtuserid.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtpassword.Properties)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.PictureBox1)).BeginInit();
            this.SuspendLayout();
            // 
            // txtuserid
            // 
            this.txtuserid.Location = new System.Drawing.Point(840, 351);
            this.txtuserid.Margin = new System.Windows.Forms.Padding(1, 4, 1, 4);
            this.txtuserid.Name = "txtuserid";
            this.txtuserid.Properties.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(2)))), ((int)(((byte)(14)))), ((int)(((byte)(28)))));
            this.txtuserid.Properties.Appearance.Font = new System.Drawing.Font("Segoe UI", 13F);
            this.txtuserid.Properties.Appearance.ForeColor = System.Drawing.Color.White;
            this.txtuserid.Properties.Appearance.Options.UseBackColor = true;
            this.txtuserid.Properties.Appearance.Options.UseFont = true;
            this.txtuserid.Properties.Appearance.Options.UseForeColor = true;
            this.txtuserid.Properties.AppearanceFocused.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(2)))), ((int)(((byte)(14)))), ((int)(((byte)(28)))));
            this.txtuserid.Properties.AppearanceFocused.Options.UseBackColor = true;
            this.txtuserid.Properties.BorderStyle = DevExpress.XtraEditors.Controls.BorderStyles.NoBorder;
            this.txtuserid.Properties.NullValuePrompt = "Username or Email";
            this.txtuserid.Size = new System.Drawing.Size(334, 28);
            this.txtuserid.TabIndex = 2;
            this.txtuserid.EditValueChanged += new System.EventHandler(this.txtuserid_EditValueChanged);
            this.txtuserid.KeyDown += new System.Windows.Forms.KeyEventHandler(this.txtuserid_KeyDown);
            // 
            // txtpassword
            // 
            this.txtpassword.Location = new System.Drawing.Point(840, 437);
            this.txtpassword.Margin = new System.Windows.Forms.Padding(1, 4, 1, 4);
            this.txtpassword.Name = "txtpassword";
            this.txtpassword.Properties.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(2)))), ((int)(((byte)(14)))), ((int)(((byte)(28)))));
            this.txtpassword.Properties.Appearance.Font = new System.Drawing.Font("Segoe UI", 13F);
            this.txtpassword.Properties.Appearance.ForeColor = System.Drawing.Color.White;
            this.txtpassword.Properties.Appearance.Options.UseBackColor = true;
            this.txtpassword.Properties.Appearance.Options.UseFont = true;
            this.txtpassword.Properties.Appearance.Options.UseForeColor = true;
            this.txtpassword.Properties.AppearanceFocused.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(2)))), ((int)(((byte)(14)))), ((int)(((byte)(28)))));
            this.txtpassword.Properties.AppearanceFocused.Options.UseBackColor = true;
            this.txtpassword.Properties.BorderStyle = DevExpress.XtraEditors.Controls.BorderStyles.NoBorder;
            this.txtpassword.Properties.NullValuePrompt = "Password";
            this.txtpassword.Properties.UseSystemPasswordChar = true;
            this.txtpassword.Size = new System.Drawing.Size(253, 28);
            this.txtpassword.TabIndex = 3;
            this.txtpassword.EditValueChanged += new System.EventHandler(this.txtpassword_EditValueChanged);
            this.txtpassword.KeyDown += new System.Windows.Forms.KeyEventHandler(this.txtpassword_KeyDown);
            // 
            // buttonLogin
            // 
            this.buttonLogin.Appearance.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(1)))), ((int)(((byte)(95)))), ((int)(((byte)(200)))));
            this.buttonLogin.Appearance.BackColor2 = System.Drawing.Color.FromArgb(((int)(((byte)(90)))), ((int)(((byte)(169)))), ((int)(((byte)(36)))));
            this.buttonLogin.Appearance.Font = new System.Drawing.Font("Segoe UI", 12F, System.Drawing.FontStyle.Bold);
            this.buttonLogin.Appearance.ForeColor = System.Drawing.Color.White;
            this.buttonLogin.Appearance.Options.UseBackColor = true;
            this.buttonLogin.Appearance.Options.UseFont = true;
            this.buttonLogin.Appearance.Options.UseForeColor = true;
            this.buttonLogin.Location = new System.Drawing.Point(771, 533);
            this.buttonLogin.Margin = new System.Windows.Forms.Padding(1, 2, 1, 2);
            this.buttonLogin.Name = "buttonLogin";
            this.buttonLogin.Size = new System.Drawing.Size(411, 63);
            this.buttonLogin.TabIndex = 18;
            this.buttonLogin.Text = "LOGIN";
            this.buttonLogin.Click += new System.EventHandler(this.buttonLogin_Click);
            // 
            // btnclose
            // 
            this.btnclose.Appearance.BackColor = System.Drawing.Color.Transparent;
            this.btnclose.Appearance.Options.UseBackColor = true;
            this.btnclose.ImageOptions.SvgImage = ((DevExpress.Utils.Svg.SvgImage)(resources.GetObject("btnclose.ImageOptions.SvgImage")));
            this.btnclose.Location = new System.Drawing.Point(1269, 8);
            this.btnclose.Margin = new System.Windows.Forms.Padding(1, 2, 1, 2);
            this.btnclose.Name = "btnclose";
            this.btnclose.Size = new System.Drawing.Size(39, 27);
            this.btnclose.TabIndex = 20;
            this.btnclose.Click += new System.EventHandler(this.btnclose_Click);
            // 
            // PictureBox1
            // 
            this.PictureBox1.BackColor = System.Drawing.Color.Transparent;
            this.PictureBox1.Image = global::SalesInventorySystem.Properties.Resources.COREXXX;
            this.PictureBox1.Location = new System.Drawing.Point(0, 0);
            this.PictureBox1.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.PictureBox1.Name = "PictureBox1";
            this.PictureBox1.Size = new System.Drawing.Size(1317, 832);
            this.PictureBox1.SizeMode = System.Windows.Forms.PictureBoxSizeMode.StretchImage;
            this.PictureBox1.TabIndex = 17;
            this.PictureBox1.TabStop = false;
            this.PictureBox1.Click += new System.EventHandler(this.PictureBox1_Click_1);
            // 
            // Login
            // 
            this.Appearance.BackColor = System.Drawing.Color.Transparent;
            this.Appearance.Options.UseBackColor = true;
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1317, 832);
            this.Controls.Add(this.btnclose);
            this.Controls.Add(this.buttonLogin);
            this.Controls.Add(this.txtpassword);
            this.Controls.Add(this.txtuserid);
            this.Controls.Add(this.PictureBox1);
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.None;
            this.Margin = new System.Windows.Forms.Padding(1, 4, 1, 4);
            this.Name = "Login";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "IT CORE SYSTEM Inc. version 1.0";
            this.Load += new System.EventHandler(this.Login_Load);
            ((System.ComponentModel.ISupportInitialize)(this.txtuserid.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.txtpassword.Properties)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.PictureBox1)).EndInit();
            this.ResumeLayout(false);

        }

        #endregion
        private DevExpress.XtraEditors.TextEdit txtpassword;

        public DevExpress.XtraEditors.TextEdit txtuserid;
        internal System.Windows.Forms.PictureBox PictureBox1;
        private DevExpress.XtraEditors.SimpleButton buttonLogin;
        private DevExpress.XtraEditors.SimpleButton btnclose;
    }
}
