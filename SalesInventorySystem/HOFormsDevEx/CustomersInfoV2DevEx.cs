using System;
using System.Data;
using System.Data.SqlClient;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid.Views.Grid;
using SalesInventorySystem.Classes;

namespace SalesInventorySystem.HOFormsDevEx
{
    // Add/Edit/Update only -- no delete. isActive is a show/hide indicator
    // (checkbox column in the grid + checkbox in the entry panel), never a
    // row-removal switch. Uses its own dedicated SQL objects
    // (func_viewCustomerV2 / spitcr_addCustV2, see
    // SQL/2026-09-10_CustomersInfoV2_Module.sql) rather than the ones
    // CustomersInfoDevEx.cs still uses, so the two forms don't interfere.
    public partial class CustomersInfoV2DevEx : DevExpress.XtraEditors.XtraForm
    {
        private bool _dataLoaded;
        private string _editingCustomerKey;

        public CustomersInfoV2DevEx()
        {
            InitializeComponent();
        }

        private void CustomersInfoV2DevEx_Load(object sender, EventArgs e)
        {
            if (!_dataLoaded)
                LoadData();
        }

        public void LoadData()
        {
            if (_dataLoaded)
                return;

            PopulateBranchLookup(txtbrcode);
            PopulateAccountOfficerLookup();
            PopulateBranchFilter();
            SetEntryEnabled(false);
            LoadGrid(string.Empty);

            _dataLoaded = true;
        }

        void PopulateBranchLookup(SearchLookUpEdit edit)
        {
            Database.displaySearchlookupEdit(
                "SELECT BranchCode, BranchName, BranchCode + ' - ' + BranchName AS DisplayText FROM Branches",
                edit, "DisplayText", "BranchCode");
        }

        void PopulateAccountOfficerLookup()
        {
            Database.displaySearchlookupEdit(
                "SELECT AccountID, AccountOfficerName, AccountID + ' - ' + AccountOfficerName AS DisplayText FROM AccountOfficers",
                txtao, "DisplayText", "AccountOfficerName");
        }

        void PopulateBranchFilter()
        {
            Database.displaySearchlookupEdit(
                "SELECT '' AS BranchCode, '(All Branches)' AS BranchName, '(All Branches)' AS DisplayText " +
                "UNION ALL " +
                "SELECT BranchCode, BranchName, BranchCode + ' - ' + BranchName AS DisplayText FROM Branches",
                txtbranchFilter, "DisplayText", "BranchCode");
            txtbranchFilter.EditValue = "";
        }

        void LoadGrid(string branchCode)
        {
            using (SqlConnection con = Database.getConnection())
            {
                con.Open();
                SqlCommand com = new SqlCommand("SELECT * FROM dbo.func_viewCustomerV2(@branch)", con);
                com.Parameters.Add("@branch", SqlDbType.VarChar, 100).Value = branchCode ?? "";
                SqlDataAdapter adapter = new SqlDataAdapter(com);
                DataTable table = new DataTable();
                adapter.Fill(table);
                gridControl1.DataSource = table;
                gridView1.PopulateColumns();
                gridView1.BestFitColumns();
            }
        }

        void SetEntryEnabled(bool editing)
        {
            btnNew.Enabled = !editing;
            btnAdd.Enabled = false;
            btnUpdate.Enabled = false;
            btnCancel.Enabled = editing;
        }

        void ClearFields()
        {
            txtcustkey.Text = "";
            txtcustid.Text = "";
            txtcustname.Text = "";
            txtcusttype.Text = "";
            txtemail.Text = "";
            txtcontactno.Text = "";
            txtaddress.Text = "";
            txtbdate.EditValue = null;
            txtcreditlimit.EditValue = 0m;
            txtterm.EditValue = 0m;
            txtbrcode.EditValue = "";
            txtao.EditValue = "";
            txtrfid.Text = "";
            chkActive.Checked = true;
            _editingCustomerKey = null;
        }

        private void btnNew_Click(object sender, EventArgs e)
        {
            ClearFields();
            int id = IDGenerator.getIDNumber("Customers", "CustomerKey", 1);
            txtcustkey.Text = HelperFunction.sequencePadding1(id.ToString(), 8);
            btnNew.Enabled = false;
            btnAdd.Enabled = true;
            btnUpdate.Enabled = false;
            btnCancel.Enabled = true;
            txtcustid.Focus();
        }

        private void btnCancel_Click(object sender, EventArgs e)
        {
            ClearFields();
            SetEntryEnabled(false);
        }

        bool ValidateFields()
        {
            if (string.IsNullOrWhiteSpace(txtcustid.Text) || string.IsNullOrWhiteSpace(txtcustname.Text) ||
                string.IsNullOrWhiteSpace(Convert.ToString(txtbrcode.EditValue)))
            {
                XtraMessageBox.Show("Customer ID, Customer Name, and Assigned Branch are required.");
                return false;
            }
            return true;
        }

        private void btnAdd_Click(object sender, EventArgs e)
        {
            if (!ValidateFields())
                return;

            try
            {
                SaveCustomer("1");
                XtraMessageBox.Show("Successfully Added!");
                ClearFields();
                SetEntryEnabled(false);
                LoadGrid(Convert.ToString(txtbranchFilter.EditValue));
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message);
            }
        }

        private void btnUpdate_Click(object sender, EventArgs e)
        {
            if (!ValidateFields())
                return;

            if (string.IsNullOrEmpty(_editingCustomerKey))
            {
                XtraMessageBox.Show("Select a customer to edit first (right-click a row > Edit Details).");
                return;
            }

            try
            {
                SaveCustomer("2");
                XtraMessageBox.Show("Successfully Updated!");
                ClearFields();
                SetEntryEnabled(false);
                LoadGrid(Convert.ToString(txtbranchFilter.EditValue));
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message);
            }
        }

        void SaveCustomer(string parmcmd)
        {
            using (SqlConnection con = Database.getConnection())
            {
                con.Open();
                SqlCommand com = new SqlCommand("spitcr_addCustV2", con) { CommandType = CommandType.StoredProcedure };
                com.Parameters.Add("@CustomerKey", SqlDbType.Char, 8).Value = txtcustkey.Text.Trim();
                com.Parameters.Add("@CustomerID", SqlDbType.VarChar, 150).Value = txtcustid.Text.Trim();
                com.Parameters.Add("@CustomerName", SqlDbType.VarChar, 150).Value = txtcustname.Text.Trim();
                com.Parameters.Add("@CustomerEmail", SqlDbType.VarChar, 50).Value = txtemail.Text.Trim();
                com.Parameters.Add("@CustomerContactNo", SqlDbType.VarChar, 50).Value = txtcontactno.Text.Trim();
                com.Parameters.Add("@CustomerAddress", SqlDbType.VarChar, 1000).Value = txtaddress.Text.Trim();
                com.Parameters.Add("@CustomerBirthDate", SqlDbType.Date).Value =
                    txtbdate.EditValue == null ? (object)DBNull.Value : Convert.ToDateTime(txtbdate.EditValue);
                com.Parameters.Add("@CustomerCreditLimit", SqlDbType.Money).Value = Convert.ToDecimal(txtcreditlimit.EditValue ?? 0m);
                com.Parameters.Add("@CustomerType", SqlDbType.VarChar, 100).Value = txtcusttype.Text.Trim();
                com.Parameters.Add("@BranchCode", SqlDbType.VarChar, 100).Value = Convert.ToString(txtbrcode.EditValue);
                com.Parameters.Add("@Term", SqlDbType.Float).Value = Convert.ToDouble(txtterm.EditValue ?? 0m);
                com.Parameters.Add("@isActive", SqlDbType.Bit).Value = chkActive.Checked;
                com.Parameters.Add("@AccountOfficer", SqlDbType.VarChar, 50).Value = Convert.ToString(txtao.EditValue);
                com.Parameters.Add("@TinNo", SqlDbType.VarChar, 50).Value = txtrfid.Text.Trim();
                com.Parameters.Add("@ActingUser", SqlDbType.VarChar, 50).Value = Login.isglobalUserID;
                com.Parameters.Add("@parmcmd", SqlDbType.Char, 1).Value = parmcmd;
                com.ExecuteNonQuery();
            }
        }

        private void gridControl1_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
            {
                var hit = gridView1.CalcHitInfo(e.Location);
                if (hit.InRow || hit.InRowCell)
                {
                    gridView1.FocusedRowHandle = hit.RowHandle;
                    contextMenuStrip1.Show(gridControl1, e.Location);
                }
            }
        }

        private void editDetailsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            try
            {
                if (gridView1.FocusedRowHandle < 0)
                    return;

                ClearFields();

                txtcustkey.Text = Convert.ToString(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "CustomerKey"));
                txtcustid.Text = Convert.ToString(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "CustomerID"));
                txtcustname.Text = Convert.ToString(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "CustomerName"));
                txtcusttype.Text = Convert.ToString(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "CustomerType"));
                txtemail.Text = Convert.ToString(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "CustomerEmail"));
                txtcontactno.Text = Convert.ToString(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "CustomerContactNo"));
                txtaddress.Text = Convert.ToString(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "CustomerAddress"));

                object bdate = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "CustomerBirthDate");
                txtbdate.EditValue = (bdate == null || bdate == DBNull.Value) ? (object)null : bdate;

                object credit = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "CustomerCreditLimit");
                txtcreditlimit.EditValue = (credit == null || credit == DBNull.Value) ? 0m : Convert.ToDecimal(credit);

                object term = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "Term");
                txtterm.EditValue = (term == null || term == DBNull.Value) ? 0m : Convert.ToDecimal(term);

                txtbrcode.EditValue = Convert.ToString(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "BranchCode"));
                txtao.EditValue = Convert.ToString(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "AccountOfficer"));
                txtrfid.Text = Convert.ToString(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "TinNo"));

                object active = gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "isActive");
                chkActive.Checked = active is bool b && b;

                _editingCustomerKey = txtcustkey.Text;

                btnNew.Enabled = false;
                btnAdd.Enabled = false;
                btnUpdate.Enabled = true;
                btnCancel.Enabled = true;
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message);
            }
        }

        private void txtbranchFilter_EditValueChanged(object sender, EventArgs e)
        {
            if (!_dataLoaded)
                return;

            LoadGrid(Convert.ToString(txtbranchFilter.EditValue));
        }
    }
}
