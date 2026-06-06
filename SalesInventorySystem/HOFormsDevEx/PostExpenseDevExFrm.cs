using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Text;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using System.Data.SqlClient;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class PostExpenseDevExFrm : DevExpress.XtraEditors.XtraForm
    { // ── resolved at load / lookup time ───────────────────────────
        private string _suppId = "";   // SupplierID (long key)
        private string _suppName = "";

        DataTable table;
        bool ok = false;
        object suppid,shipmentno;
        public PostExpenseDevExFrm()
        {
            InitializeComponent();
           
        }

        private void PostExpenseDevExFrm_Load(object sender, EventArgs e)
        {
            ////Classes.Utilities.setDate(datefrom.Text, dateto.Text);
            //DateTime now = DateTime.Now;

            //DateTime date = new DateTime(now.Year, now.Month, 1);
            //datefrom.Text = date.ToShortDateString();
            //var now2 = DateTime.Now;
            //var startOfMonth = new DateTime(now2.Year, now2.Month, 1);
            //var DaysInMonth = DateTime.DaysInMonth(now2.Year, now2.Month);
            //var lastDay = new DateTime(now2.Year, now2.Month, DaysInMonth);
            //dateto.Text = lastDay.ToShortDateString();
            //txtrefno.Text = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");//IDGenerator.getIDNumberSP("sp_GetExpenseNumber", "expenseno");// IDGenerator.getExpenseNumber();
            //txtbatchid.Text = IDGenerator.getIDNumberSP("sp_GetBatchReferenceID", "BatchReferenceID");//IDGenerator.getIDNumberSP("sp_GetExpenseNumber", "expenseno");// IDGenerator.getExpenseNumber();
            //loadRepositoryItem();
            //populateBranches2();
            //displayvendor();
            //displayPurchaseList();
            //table = new DataTable();
            //table.Columns.Add("BranchCode");
            //table.Columns.Add("TypeOfExpense");
            //table.Columns.Add("Particulars");
            //table.Columns.Add("Amount");
            //gridControl1.DataSource = table;
            // Set default date range
            DateTime now = DateTime.Now;
            datefrom.Text = new DateTime(now.Year, now.Month, 1).ToShortDateString();
            dateto.Text = new DateTime(now.Year, now.Month, DateTime.DaysInMonth(now.Year, now.Month)).ToShortDateString();

            // Initialize empty table
            table = new DataTable();
            table.Columns.Add("BranchCode");
            table.Columns.Add("TypeOfExpense");
            table.Columns.Add("Particulars");
            table.Columns.Add("Amount");
            gridControl1.DataSource = table;
            // Defer heavy DB calls until Shown
            this.Shown += PostExpenseDevExFrm_Shown;

        }
        void populateBranches2()
        {
            Database.displayDevComboBoxItems("SELECT BranchCode FROM Branches", "BranchCode", txtbrcodesum);
        }
        void displayvendor()
        {
            Database.displaySearchlookupEdit("select SupplierID,SupplierName FROM Supplier", txtvendor, "SupplierName", "SupplierName");
        }
        void displayPurchaseList()
        {
            Database.displaySearchlookupEdit("select ShipmentNo, SupplierId, SupplierName FROM dbo.view_POSUMMARYREP WHERE Status <> 'CANCELLED'" , txtpo, "SupplierName", "SupplierName");
        }
        void loadRepositoryItem()
        {
            Database.displayRepositorySearchlookupEdit("SELECT BranchCode,BranchName FROM Branches", repbrcode, "BranchCode", "BranchCode");
            //Database.displayRepositorySearchlookupEdit("SELECT Description FROM CHartOfAccounts WHERE AccountCode like '60%'", reptypeofexpense, "Description", "Description");
            Database.displayRepositorySearchlookupEdit("SELECT * FROM ExpensesList", reptypeofexpense, "ExpenseName", "ExpenseName");
            gridView2.BestFitColumns();
            gridView3.BestFitColumns();
        }

        private void simpleButton3_Click(object sender, EventArgs e)
        {
            DataRow newRow = table.NewRow();
            newRow["Amount"] = 0;
            table.Rows.Add(newRow);
            gridControl1.DataSource = table;
            gridView1.BestFitColumns();
        }


        private void gridView1_CustomRowCellEdit(object sender, DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "BranchCode")
                e.RepositoryItem = repbrcode;
            if (e.Column.FieldName == "TypeOfExpense")
                e.RepositoryItem = reptypeofexpense;
            if (e.Column.FieldName == "Particulars")
                e.RepositoryItem = repparticulars;
            if (e.Column.FieldName == "Amount")
                e.RepositoryItem = repamount;
        }
        private DataTable BuildExpenseTVP()
        {
            //var dt = new DataTable();
            //dt.Columns.Add("BranchCode", typeof(string));
            //dt.Columns.Add("ExpenseName", typeof(string));
            //dt.Columns.Add("Particulars", typeof(string));
            //dt.Columns.Add("Amount", typeof(decimal));

            //for (int i = 0; i < gridView1.RowCount; i++)
            //{
            //    dt.Rows.Add(
            //        gridView1.GetRowCellValue(i, "BranchCode")?.ToString(),
            //        gridView1.GetRowCellValue(i, "TypeOfExpense")?.ToString(),
            //        gridView1.GetRowCellValue(i, "Particulars")?.ToString(),
            //        Convert.ToDecimal(gridView1.GetRowCellValue(i, "Amount"))
            //    );
            //}
            //return dt;

            var dt = new DataTable();
            dt.Columns.Add("BranchCode", typeof(string));
            dt.Columns.Add("ExpenseName", typeof(string));
            dt.Columns.Add("Particulars", typeof(string));
            dt.Columns.Add("Amount", typeof(decimal));

            for (int i = 0; i < gridView1.RowCount; i++)
            {
                var branch = gridView1.GetRowCellValue(i, "BranchCode")?.ToString()?.Trim();
                var expType = gridView1.GetRowCellValue(i, "TypeOfExpense")?.ToString()?.Trim();
                var remarks = gridView1.GetRowCellValue(i, "Particulars")?.ToString()?.Trim() ?? "";

                if (!decimal.TryParse(
                        gridView1.GetRowCellValue(i, "Amount")?.ToString(),
                        out var amount) || amount <= 0)
                    continue;   // skip zero/invalid rows silently (ValidateGridRows catches real errors)

                dt.Rows.Add(branch, expType,  remarks, amount);
            }

            return dt;
        }

        private void simpleButton4_Click(object sender, EventArgs e)
        {
            // Grid must have rows
            if (gridView1.RowCount == 0)
            {
                XtraMessageBox.Show("No expense detail lines entered.", "Validation",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // All rows must have BranchCode and TypeOfExpense
            if (!ValidateGridRows()) return;

            // Invoice number required
            if (string.IsNullOrWhiteSpace(txtinvoiceno.Text))
            {
                XtraMessageBox.Show("Invoice No. is required.", "Validation",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // Build TVP
            var tvpTable = BuildExpenseTVP();
            if (tvpTable == null || tvpTable.Rows.Count == 0)
            {
                XtraMessageBox.Show("No valid expense lines to post (check Amount > 0).", "Validation",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("dbo.sp_PostExpense", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 60;

                    cmd.Parameters.Add("@parmrefno", SqlDbType.VarChar, 10).Value = txtrefno.Text.Trim();
                    cmd.Parameters.Add("@parmbatchrefno", SqlDbType.BigInt).Value = Convert.ToInt64(txtbatchid.Text.Trim());
                    cmd.Parameters.Add("@parmsupplierid", SqlDbType.VarChar, 100).Value = suppid.ToString();
                    cmd.Parameters.Add("@parminvoiceno", SqlDbType.VarChar, 150).Value = txtinvoiceno.Text.Trim();
                    cmd.Parameters.Add("@parmexpensedate", SqlDbType.Date).Value = Convert.ToDateTime(txtexpdate.Text);
                    cmd.Parameters.Add("@parmremarks", SqlDbType.VarChar, 2000).Value = txtremarks.Text.Trim();
                    cmd.Parameters.Add("@parmuser", SqlDbType.VarChar, 40).Value = Login.Fullname;

                    var tvpParam = cmd.Parameters.AddWithValue("@Lines", tvpTable);
                    tvpParam.SqlDbType = SqlDbType.Structured;
                    tvpParam.TypeName = "dbo.ExpenseEntryTVP";

                    con.Open();
                    cmd.ExecuteNonQuery();
                }

                XtraMessageBox.Show("Expense successfully submitted for approval.", "Success",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                Close();
            }
            catch (SqlException ex)
            {
                // Show SQL error number + message for easier debugging
                XtraMessageBox.Show(
                    $"Database error ({ex.Number}): {ex.Message}",
                    "Post Expense Failed",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            //if (gridView1.RowCount == 0)
            //{
            //    XtraMessageBox.Show("No Expense Details Entry");
            //    return;
            //}

            //for (int i = 0; i < gridView1.RowCount; i++)
            //{
            //    if (string.IsNullOrWhiteSpace(Convert.ToString(gridView1.GetRowCellValue(i, "BranchCode"))) ||
            //        string.IsNullOrWhiteSpace(Convert.ToString(gridView1.GetRowCellValue(i, "TypeOfExpense"))))
            //    {
            //        XtraMessageBox.Show("Some Fields are Empty..");
            //        return;
            //    }
            //}

            //if (string.IsNullOrWhiteSpace(txtinvoiceno.Text))
            //{
            //    XtraMessageBox.Show("Please Input All Valid Fields");
            //    return;
            //}

            //try
            //{
            //    using (var con = Database.getConnection())
            //    using (var cmd = new SqlCommand("dbo.sp_PostExpense", con))
            //    {
            //        cmd.CommandType = CommandType.StoredProcedure;

            //        cmd.Parameters.Add("@parmrefno", SqlDbType.VarChar, 10).Value = txtrefno.Text.Trim();
            //        cmd.Parameters.Add("@parmbatchrefno", SqlDbType.BigInt).Value = Convert.ToInt64(txtbatchid.Text);
            //        cmd.Parameters.Add("@parmsupplierid", SqlDbType.VarChar, 100).Value = suppid.ToString();
            //        cmd.Parameters.Add("@parminvoiceno", SqlDbType.VarChar, 150).Value = txtinvoiceno.Text.Trim();
            //        cmd.Parameters.Add("@parmexpensedate", SqlDbType.Date).Value = Convert.ToDateTime(txtexpdate.Text);
            //        cmd.Parameters.Add("@parmremarks", SqlDbType.VarChar, 2000).Value = txtremarks.Text.Trim();
            //        cmd.Parameters.Add("@parmuser", SqlDbType.VarChar, 40).Value = Login.Fullname;

            //        var tvp = BuildExpenseTVP();
            //        var p = cmd.Parameters.AddWithValue("@Lines", tvp);
            //        p.SqlDbType = SqlDbType.Structured;
            //        p.TypeName = "dbo.ExpenseEntryTVP";

            //        con.Open();
            //        cmd.ExecuteNonQuery();
            //    }

            //    XtraMessageBox.Show("Successfully Added!");
            //    this.Close();
            //}
            //catch (SqlException ex)
            //{
            //    XtraMessageBox.Show(ex.Message);
            //}

            //try
            //{
            //    string supplierkey = Database.getSingleQuery("Supplier", "SupplierID='" + suppid.ToString() + "'", "SupplierKey");
            //    string branchcode, expname, particulars, amount;
            //    bool isEmpty = false;
            //    int ctr = 1;
            //    for (int i = 0; i <= gridView1.RowCount - 1; i++)
            //    {
            //        if (String.IsNullOrEmpty(gridView1.GetRowCellValue(i, "BranchCode").ToString()) || String.IsNullOrEmpty(gridView1.GetRowCellValue(i, "TypeOfExpense").ToString()))
            //        {
            //            isEmpty = true;
            //            break;
            //        }
            //    }
            //    if(gridView1.RowCount==0)
            //    {
            //        XtraMessageBox.Show("No Expense Details Entry");
            //        return;
            //    }
            //    if (isEmpty)
            //    {
            //        XtraMessageBox.Show("Some Fields are Empty..");
            //        return;
            //    }
            //    if (txtinvoiceno.Text == "")
            //    {
            //        XtraMessageBox.Show("Please Input All Valid Fields");
            //    }
            //    else
            //    {
            //        for (int i = 0; i <= gridView1.RowCount - 1; i++)
            //        {

            //            branchcode = gridView1.GetRowCellValue(i, "BranchCode").ToString();
            //            expname = gridView1.GetRowCellValue(i, "TypeOfExpense").ToString();
            //            particulars = gridView1.GetRowCellValue(i, "Particulars").ToString();
            //            amount = gridView1.GetRowCellValue(i, "Amount").ToString();

            //           Database.ExecuteQuery("INSERT INTO ExpenseMaster VALUES ('" + ctr + "','" + branchcode + "','" + supplierkey + "','" + txtrefno.Text + "','" + txtinvoiceno.Text + "','" + expname + "','" + txtexpdate.Text + "','" + amount + "','" + particulars + "','UNPAID','" + amount + "',0,0,0,0,0,'"+txtbatchid.Text+"','"+ shipmentno .ToString()+ "')");
            //              ctr += 1;
            //        }
            //        postExpense();
            //        XtraMessageBox.Show("Successfully Added!");
            //        this.Close();
            //    }
            //}
            //catch(SqlException ex)
            //{
            //    XtraMessageBox.Show(ex.Message.ToString());
            //}
        }
        private bool ValidateGridRows()
        {
            for (int i = 0; i < gridView1.RowCount; i++)
            {
                var branch = gridView1.GetRowCellValue(i, "BranchCode")?.ToString();
                var expType = gridView1.GetRowCellValue(i, "TypeOfExpense")?.ToString();

                if (string.IsNullOrWhiteSpace(branch) || string.IsNullOrWhiteSpace(expType))
                {
                    gridView1.FocusedRowHandle = i;
                    XtraMessageBox.Show(
                        $"Row {i + 1}: BranchCode and Type of Expense are required.",
                        "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }

                // Amount must be numeric and > 0
                var rawAmt = gridView1.GetRowCellValue(i, "Amount")?.ToString();
                if (!decimal.TryParse(rawAmt, out var amt) || amt <= 0)
                {
                    gridView1.FocusedRowHandle = i;
                    XtraMessageBox.Show(
                        $"Row {i + 1}: Amount must be a positive number.",
                        "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
            }
            return true;
        }
        //void postExpense()
        //{
        //    using (var con = Database.getConnection())
        //    using (var cmd = new SqlCommand("dbo.sp_PostExpenseUnified", con))
        //    {
        //        cmd.CommandType = CommandType.StoredProcedure;

        //        cmd.Parameters.Add("@parmrefno", SqlDbType.VarChar, 10).Value = txtrefno.Text;
        //        cmd.Parameters.Add("@parmbatchrefno", SqlDbType.BigInt).Value = Convert.ToInt64(txtbatchid.Text);
        //        cmd.Parameters.Add("@parmsupplierid", SqlDbType.VarChar, 100).Value = suppid;
        //        cmd.Parameters.Add("@parminvoiceno", SqlDbType.VarChar, 150).Value = txtinvoiceno.Text;
        //        cmd.Parameters.Add("@parmexpensedate", SqlDbType.Date).Value = Convert.ToDateTime(txtexpdate.Text);
        //        cmd.Parameters.Add("@parmremarks", SqlDbType.VarChar, 2000).Value = txtremarks.Text;
        //        cmd.Parameters.Add("@parmuser", SqlDbType.VarChar, 40).Value = Login.Fullname;

        //        var tvp = BuildExpenseTVP();
        //        var p = cmd.Parameters.AddWithValue("@Lines", tvp);
        //        p.SqlDbType = SqlDbType.Structured;
        //        p.TypeName = "dbo.ExpenseEntryTVP";

        //        con.Open();
        //        cmd.ExecuteNonQuery();
        //    }
        //    //try
        //    //{

        //    //    SqlConnection con = Database.getConnection();
        //    //    con.Open();
        //    //    string query = "sp_UpdateExpense";
        //    //    SqlCommand com = new SqlCommand(query, con);
        //    //    com.Parameters.AddWithValue("@parmrefno", txtrefno.Text);
        //    //    com.Parameters.AddWithValue("@parmbatchrefno", txtbatchid.Text);
        //    //    com.Parameters.AddWithValue("@parmsupplierid", suppid.ToString());
        //    //    com.Parameters.AddWithValue("@parminvoiceno", txtinvoiceno.Text);
        //    //    com.Parameters.AddWithValue("@parmexpensedate", txtexpdate.Text);
        //    //    com.Parameters.AddWithValue("@parmremarks", txtremarks.Text); //DESCRIPTION
        //    //    com.Parameters.AddWithValue("@parmuser", Login.Fullname);
        //    //    com.CommandType = CommandType.StoredProcedure;
        //    //    com.CommandText = query;
        //    //    com.ExecuteNonQuery();
        //    //    con.Close();
        //    //}
        //    //catch (SqlException ex)
        //    //{
        //    //    XtraMessageBox.Show(ex.Message.ToString());
        //    //}
        //}

        private void gridControl1_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStrip1.Show(gridControl1, e.Location);
        }

        private void cancelLineToolStripMenuItem_Click(object sender, EventArgs e)
        {
            gridView1.DeleteSelectedRows();
        }

        private void btnget_Click(object sender, EventArgs e)
        {
            getquery();
        }
        void getquery()
        {

            if (checkBox1.Checked == true) //if all branch
            {
                ok = true;
            }
            else
            {
                ok = false;
            }

            if (ok)
            {
                Database.display("SELECT * FROM view_ExpenseMaster WHERE ExpenseDate >= '" + datefrom.Text + "' and ExpenseDate <= '" + dateto.Text + "'", gridControl2, gridView2);
            }
            else
            {
                Database.display("SELECT * FROM view_ExpenseMaster WHERE ExpenseDate >= '" + datefrom.Text + "' and ExpenseDate <= '" + dateto.Text + "' AND BranchCode='" + txtbrcodesum.Text + "'", gridControl2, gridView2);
            }
        }

        private void checkBox1_CheckedChanged(object sender, EventArgs e)
        {
            if (checkBox1.Checked == true)
            {
                ok = true;
                txtbrcodesum.Text = "";
                txtbrcodesum.Enabled = false;
            }
            else
            {
                ok = false;
                txtbrcodesum.Enabled = true;
                Database.displayDevComboBoxItems("SELECT BranchCode from Branches", "BranchCode", txtbrcodesum);
            }
        }

        private void gridControl2_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStrip2.Show(gridControl2, e.Location);
        }

        private void toolStripMenuItem1_Click(object sender, EventArgs e)
        {
            if (Convert.ToBoolean(gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "isErrorCorrect").ToString()) == true)
            {
                XtraMessageBox.Show("Entry Already Corrected!");
                return;
            }
            else
            {
                reverseExpense();
                XtraMessageBox.Show("Success");
                btnget.PerformClick();
            }
        }
        void reverseExpense()
        {
            try
            {

                SqlConnection con = Database.getConnection();
                con.Open();
                string query = "sp_ExpenseReversal";
                SqlCommand com = new SqlCommand(query, con);
                com.Parameters.AddWithValue("@parmvoucherid", txtrefno.Text);
                com.Parameters.AddWithValue("@parmuser", Login.Fullname);
                com.Parameters.AddWithValue("@parmseq", gridView2.GetRowCellValue(gridView2.FocusedRowHandle,"SequenceNumber").ToString());
                com.CommandType = CommandType.StoredProcedure;
                com.CommandText = query;
                com.ExecuteNonQuery();
                con.Close();
            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }

        private void gridView2_RowStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowStyleEventArgs e)
        {
            GridView view = (GridView)sender;
            bool check = Convert.ToBoolean(view.GetRowCellValue(e.RowHandle, "isErrorCorrect"));
            if (check)
            {
                e.Appearance.Font = new System.Drawing.Font(e.Appearance.Font, FontStyle.Strikeout);
                e.Appearance.ForeColor = Color.Red;
            }
        }

        private void txtvendor_EditValueChanged(object sender, EventArgs e)
        {
            suppid = SearchLookUpClass.getSingleValue(txtvendor, "SupplierID");
        }

        private void chcklinktopo_CheckedChanged(object sender, EventArgs e)
        {
            if (chcklinktopo.Checked == true)
                txtpo.Enabled = true;
            else txtpo.Enabled = false;
        }

        private async void PostExpenseDevExFrm_Shown(object sender, EventArgs e)
        {
            // Run DB calls asynchronously so UI stays responsive
            await Task.Run(() =>
            {
                txtrefno.Invoke((Action)(() =>
                    txtrefno.Text = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber")));

                txtbatchid.Invoke((Action)(() =>
                    txtbatchid.Text = IDGenerator.getIDNumberSP("sp_GetBatchReferenceID", "BatchReferenceID")));

                // Repository items
                Invoke((Action)(() => loadRepositoryItem()));

                // Branches, vendors, PO list
                Invoke((Action)(() =>
                {
                    populateBranches2();
                    displayvendor();
                    displayPurchaseList();
                }));
            });
        }

        private void txtpo_EditValueChanged(object sender, EventArgs e)
        {
            shipmentno = SearchLookUpClass.getSingleValue(txtpo, "ShipmentNo");
        }
    }
}