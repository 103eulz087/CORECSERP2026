using DevExpress.XtraEditors;
using System;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Globalization;
using System.Windows.Forms;

namespace SalesInventorySystem.AccountingDevEx
{
    public partial class BankReconItemForm : XtraForm
    {
        // Custom setter (not an auto-property) so that BtnAdd_Click's existing
        // "dlg.ItemType = defaultItemType;" pattern -- called AFTER the dialog is already
        // fully constructed -- actually takes effect. Previously ItemType was a plain
        // auto-property: the dropdown pre-selection only ever ran once, inside BuildDialog()
        // during the constructor, using whatever value ItemType held at THAT moment (always
        // "OC", set two lines above InitializeComponent()). Every caller's post-construction
        // assignment (Add DIT, Add BankSide, etc.) was silently a no-op -- the dialog always
        // opened on "OC" regardless of which Add button was clicked.
        private string _itemType = "OC";
        public string ItemType
        {
            get => _itemType;
            set { _itemType = value; if (cmbType != null) ApplySelectedItemType(); }
        }
        public string ReferenceNo { get; set; }
        public string ControlNo { get; set; }
        public string BranchCode { get; set; }
        public string AccountCode { get; set; }
        public DateTime ItemDate { get; set; }
        public string Payee { get; set; }
        public decimal Amount { get; set; }
        public string Remarks { get; set; }
        public decimal BankStatementBal { get; set; }

        private static readonly Color C_CARD = Color.FromArgb(30, 35, 51);
        private static readonly Color C_TEXT = Color.FromArgb(232, 230, 224);
        private static readonly Color C_MUTED = Color.FromArgb(136, 145, 170);
        private static readonly Color C_GOLD = Color.FromArgb(201, 168, 76);
        private static readonly Font F_MONO = new Font("Courier New", 9f);

        private ComboBoxEdit cmbType;
        private TextEdit txtRef;
        private SearchLookUpEdit cmbControlNo;
        private LabelControl lblControlNo;
        private TextEdit txtPayee;
        private TextEdit txtAmount;
        private TextEdit txtRemarks;
        private DateEdit dtItemDate;

        public BankReconItemForm(bool isNew)
        {
            ItemType = "OC";
            ReferenceNo = "";
            ItemDate = DateTime.Today;
            Payee = "";
            Amount = 0m;
            Remarks = "";
            BankStatementBal = 0m;

            this.Text = isNew ? "Add Reconciling Item" : "Edit Reconciling Item";
            this.BackColor = Color.FromArgb(24, 28, 39);
            this.ForeColor = C_TEXT;
            this.ClientSize = new Size(400, 410); // +50 vs. original for the new Control No field
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.MaximizeBox = false;
            this.StartPosition = FormStartPosition.CenterParent;

            InitializeComponent();
            BuildDialog();
        }

        private void BuildDialog()
        {
            int y = 16;

            // Item Type
            cmbType = new ComboBoxEdit();
            cmbType.Font = F_MONO;
            cmbType.Properties.Appearance.BackColor = C_CARD;
            cmbType.Properties.Appearance.ForeColor = C_TEXT;
            cmbType.Properties.Items.AddRange(new object[]
            {
                "OC - Outstanding Check",
                "DIT - Deposit in Transit",
                "BCM - Bank Credit Memo",
                "BDM - Bank Debit Memo",
                "BC - Bank Charges",
                "NSF - NSF / Returned Check"
            });
            cmbType.SelectedIndex = 0;
            cmbType.SelectedIndexChanged += (s, e) => UpdateControlNoVisibility();
            AddField("Item Type", cmbType, ref y);

            // Reference No
            txtRef = new TextEdit();
            txtRef.Font = F_MONO;
            StyleText(txtRef);
            AddField("Reference No (check/OR number)", txtRef, ref y);

            // Control No -- DIT only. Picked from a real collection batch
            // (TransactionCheque/TransactionOnline.ControlNo) rather than freely typed,
            // so it's guaranteed to match an actual deposit slip -- confirmed with user
            // 2026-09-03. Populated by LoadControlNoCandidates(), called by the caller
            // once BranchCode/AccountCode are set (both are unknown at construction time).
            cmbControlNo = new SearchLookUpEdit();
            cmbControlNo.Font = F_MONO;
            cmbControlNo.Properties.Appearance.BackColor = C_CARD;
            cmbControlNo.Properties.Appearance.ForeColor = C_TEXT;
            // Known Bug Pattern #2: DisableTextEditor -- must only accept a picked
            // ControlNo, never free-typed text that could bypass ValueMember.
            cmbControlNo.Properties.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.DisableTextEditor;
            cmbControlNo.Properties.NullText = "(none -- optional)";
            cmbControlNo.EditValueChanged += CmbControlNo_EditValueChanged;
            lblControlNo = AddField("Control No (real collection batch -- DIT only)", cmbControlNo, ref y);

            // Date
            dtItemDate = new DateEdit();
            dtItemDate.Font = F_MONO;
            dtItemDate.Properties.DisplayFormat.FormatString = "yyyy-MM-dd";
            dtItemDate.Properties.DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
            dtItemDate.Properties.EditFormat.FormatString = "yyyy-MM-dd";
            dtItemDate.Properties.EditFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
            dtItemDate.Properties.Appearance.BackColor = C_CARD;
            dtItemDate.Properties.Appearance.ForeColor = C_TEXT;
            dtItemDate.EditValue = DateTime.Today;
            AddField("Item Date", dtItemDate, ref y);

            // Payee
            txtPayee = new TextEdit();
            txtPayee.Font = F_MONO;
            StyleText(txtPayee);
            AddField("Payee / Depositor", txtPayee, ref y);

            // Amount
            txtAmount = new TextEdit();
            txtAmount.Font = F_MONO;
            StyleText(txtAmount);
            txtAmount.Text = "0.00";
            AddField("Amount (PHP)", txtAmount, ref y);

            // Remarks
            txtRemarks = new TextEdit();
            txtRemarks.Font = F_MONO;
            StyleText(txtRemarks);
            AddField("Remarks", txtRemarks, ref y);

            // Buttons
            SimpleButton btnOK = new SimpleButton();
            btnOK.Text = "Save";
            btnOK.DialogResult = DialogResult.None;
            btnOK.Bounds = new Rectangle(216, y, 80, 30);
            btnOK.Appearance.BackColor = C_GOLD;
            btnOK.Appearance.ForeColor = Color.FromArgb(15, 17, 23);
            btnOK.Font = new Font("Segoe UI", 9f, FontStyle.Bold);

            SimpleButton btnCancel = new SimpleButton();
            btnCancel.Text = "Cancel";
            btnCancel.DialogResult = DialogResult.Cancel;
            btnCancel.Bounds = new Rectangle(304, y, 72, 30);
            btnCancel.Appearance.BackColor = C_CARD;
            btnCancel.Appearance.ForeColor = C_MUTED;
            btnCancel.Appearance.BorderColor = Color.FromArgb(42, 48, 80);
            btnCancel.Font = new Font("Segoe UI", 9f);

            btnOK.Click += BtnOK_Click;

            this.Controls.Add(btnOK);
            this.Controls.Add(btnCancel);

            // Populate edit values
            if (!string.IsNullOrEmpty(ItemType))
            {
                ApplySelectedItemType();

                txtRef.Text = ReferenceNo;
                dtItemDate.EditValue = ItemDate;
                txtPayee.Text = Payee;
                txtAmount.Text = Amount.ToString("N2");
                txtRemarks.Text = Remarks;
            }

            UpdateControlNoVisibility();
        }

        // Shared by the ItemType property setter (so BtnAdd_Click's post-construction
        // "dlg.ItemType = ..." actually takes effect) and BuildDialog's initial population.
        private void ApplySelectedItemType()
        {
            for (int i = 0; i < cmbType.Properties.Items.Count; i++)
            {
                if (cmbType.Properties.Items[i].ToString().StartsWith(_itemType))
                {
                    cmbType.SelectedIndex = i;
                    break;
                }
            }
            UpdateControlNoVisibility();
        }

        private void UpdateControlNoVisibility()
        {
            if (cmbControlNo == null || lblControlNo == null) return;
            bool isDit = cmbType.Text.StartsWith("DIT");
            lblControlNo.Visible = isDit;
            cmbControlNo.Visible = isDit;
        }

        // Called by the caller once BranchCode/AccountCode are known (BtnAdd_Click, after
        // construction) -- the dialog itself has no access to which branch/account the
        // parent BankReconFormV2 currently has loaded.
        public void LoadControlNoCandidates()
        {
            if (string.IsNullOrWhiteSpace(BranchCode) || string.IsNullOrWhiteSpace(AccountCode)) return;

            try
            {
                var table = new DataTable();
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("dbo.sp_BankRecon_GetControlNoCandidates", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 5).Value = BranchCode;
                    cmd.Parameters.Add("@AccountCode", SqlDbType.VarChar, 20).Value = AccountCode;

                    con.Open();
                    new SqlDataAdapter(cmd).Fill(table);
                }

                cmbControlNo.Properties.View.Columns.Clear();
                cmbControlNo.Properties.DataSource = null;
                cmbControlNo.Properties.DataSource = table;
                cmbControlNo.Properties.DisplayMember = "ControlNo";
                cmbControlNo.Properties.ValueMember = "ControlNo";
            }
            catch (SqlException)
            {
                // Fail silently, same as Database.displaySearchlookupEdit -- the picker
                // just shows empty instead of crashing the dialog.
            }
        }

        // Auto-fills Amount/Date from the real collection batch total once a Control No is
        // picked -- Payee is left for manual entry (a deposit slip can bundle multiple
        // customers, so there's no single correct payee to default to) unless still blank.
        private void CmbControlNo_EditValueChanged(object sender, EventArgs e)
        {
            var row = cmbControlNo.Properties.View.GetFocusedDataRow();
            if (row == null) return;

            if (row.Table.Columns.Contains("TotalAmount") && row["TotalAmount"] != DBNull.Value)
                txtAmount.Text = Convert.ToDecimal(row["TotalAmount"]).ToString("N2");

            if (row.Table.Columns.Contains("ItemDate") && row["ItemDate"] != DBNull.Value)
                dtItemDate.EditValue = Convert.ToDateTime(row["ItemDate"]);

            if (string.IsNullOrWhiteSpace(txtPayee.Text))
                txtPayee.Text = "Collections - Control #" + cmbControlNo.EditValue;
        }

        private void BtnOK_Click(object sender, EventArgs e)
        {
            decimal amt;

            if (string.IsNullOrWhiteSpace(txtRef.Text))
            {
                XtraMessageBox.Show("Reference No is required.");
                return;
            }

            if (!decimal.TryParse(txtAmount.Text.Replace(",", ""),
                NumberStyles.Any,
                CultureInfo.InvariantCulture,
                out amt) || amt <= 0)
            {
                XtraMessageBox.Show("Enter a valid positive amount.");
                return;
            }

            ItemType = cmbType.Text.Split(' ')[0];
            ReferenceNo = txtRef.Text.Trim();

            if (dtItemDate.EditValue != null && dtItemDate.EditValue is DateTime)
                ItemDate = (DateTime)dtItemDate.EditValue;
            else
                ItemDate = DateTime.Today;

            Payee = txtPayee.Text.Trim();
            Amount = Math.Round(amt, 2);
            Remarks = txtRemarks.Text.Trim();
            ControlNo = (cmbControlNo.Visible && cmbControlNo.EditValue != null && cmbControlNo.EditValue != DBNull.Value)
                ? cmbControlNo.EditValue.ToString() : null;

            this.DialogResult = DialogResult.OK;
            this.Close();
        }

        private LabelControl AddField(string label, Control ctrl, ref int y)
        {
            LabelControl lbl = new LabelControl();
            lbl.Text = label.ToUpper();
            lbl.Font = new Font("Courier New", 7f, FontStyle.Bold);
            lbl.ForeColor = C_MUTED;
            lbl.AutoSizeMode = LabelAutoSizeMode.None;
            lbl.Bounds = new Rectangle(16, y, 360, 14);

            ctrl.Bounds = new Rectangle(16, y + 16, 360, 24);

            this.Controls.Add(lbl);
            this.Controls.Add(ctrl);

            y += 50;
            return lbl;
        }

        private void StyleText(TextEdit ctl)
        {
            ctl.Properties.Appearance.BackColor = C_CARD;
            ctl.Properties.Appearance.ForeColor = C_TEXT;
        }

        private void InitializeComponent()
        {
            this.SuspendLayout();
            this.AutoScaleDimensions = new SizeF(6F, 13F);
            this.AutoScaleMode = AutoScaleMode.Font;
            this.Name = "BankReconItemForm";
            this.ResumeLayout(false);
        }
    }
}
