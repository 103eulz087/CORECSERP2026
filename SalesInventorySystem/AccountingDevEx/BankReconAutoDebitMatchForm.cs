using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;

namespace SalesInventorySystem.AccountingDevEx
{
    /// <summary>
    /// Lets the accountant pick which open SINGLE-mode, auto-debit-
    /// supplier invoice a bank statement debit line is settling.
    /// </summary>
    public partial class BankReconAutoDebitMatchForm : XtraForm
    {
        private decimal _amount = 0m;

        public string SelectedSupplierID { get; private set; }
        public string SelectedSupplierName { get; private set; }
        public long SelectedBatchReferenceID { get; private set; }
        public string SelectedInvoiceNo { get; private set; }
        public DateTime SelectedExpenseDate { get; private set; }
        public string SelectedDescription { get; private set; }
        public decimal SelectedBalance { get; private set; }

        // Parameterless constructor kept so the VS designer can host this form.
        public BankReconAutoDebitMatchForm()
        {
            InitializeComponent();
        }

        public BankReconAutoDebitMatchForm(decimal amount) : this()
        {
            _amount = amount;
            lblHint.Text = $"Bank debit amount: {_amount:N2}  —  select the invoice this payment settles.";

            if (!DesignMode)
                LoadCandidates();
        }

        private void LoadCandidates()
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("sp_BankRecon_GetAutoDebitCandidates", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@Amount", SqlDbType.Decimal).Value = _amount;
                cmd.Parameters.Add("@SupplierSearch", SqlDbType.VarChar, 100).Value = DBNull.Value;

                var dt = new DataTable();
                con.Open();
                new SqlDataAdapter(cmd).Fill(dt);
                grid.DataSource = dt;
            }

            view.Columns.Clear();
            view.PopulateColumns();
            if (view.Columns["AmountDiff"] != null) view.Columns["AmountDiff"].Caption = "Diff vs. Bank Amount";
            if (view.Columns["Balance"] != null) view.Columns["Balance"].DisplayFormat.FormatString = "N2";
            view.BestFitColumns();

            if (view.RowCount == 0)
            {
                XtraMessageBox.Show(
                    "No open SINGLE-mode invoices found for an auto-debit supplier.\nMake sure the supplier is flagged PaymentMode = 'AUTODEBIT' and has an approved, unpaid SINGLE-mode invoice.",
                    "No Candidates", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        private void View_DoubleClick(object sender, EventArgs e)
        {
            if (view.FocusedRowHandle >= 0) AcceptSelection();
        }

        private void BtnOK_Click(object sender, EventArgs e)
        {
            AcceptSelection();
        }

        private void BtnCancel_Click(object sender, EventArgs e)
        {
            DialogResult = DialogResult.Cancel;
            Close();
        }

        private void AcceptSelection()
        {
            if (view.FocusedRowHandle < 0)
            {
                XtraMessageBox.Show("Select an invoice first.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            SelectedSupplierID = Convert.ToString(view.GetRowCellValue(view.FocusedRowHandle, "SupplierID"));
            SelectedSupplierName = Convert.ToString(view.GetRowCellValue(view.FocusedRowHandle, "SupplierName"));
            SelectedBatchReferenceID = Convert.ToInt64(view.GetRowCellValue(view.FocusedRowHandle, "BatchReferenceID"));
            SelectedInvoiceNo = Convert.ToString(view.GetRowCellValue(view.FocusedRowHandle, "InvoiceNo"));
            SelectedExpenseDate = Convert.ToDateTime(view.GetRowCellValue(view.FocusedRowHandle, "ExpenseDate"));
            SelectedDescription = Convert.ToString(view.GetRowCellValue(view.FocusedRowHandle, "Description"));
            SelectedBalance = Convert.ToDecimal(view.GetRowCellValue(view.FocusedRowHandle, "Balance"));

            DialogResult = DialogResult.OK;
            Close();
        }
    }
}