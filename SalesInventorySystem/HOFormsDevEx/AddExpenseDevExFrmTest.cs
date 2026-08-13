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
using SalesInventorySystem.Accounting;
using DevExpress.XtraGrid.Views.Grid;
using DevExpress.XtraEditors.Controls;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class AddExpenseDevExFrmTest : DevExpress.XtraEditors.XtraForm
    {
        DataTable table;
        string acctcode, accttitle, deb, cred;
        bool ok = false;
        private bool _initialized = false;
        object objbranches, objvendor,objshipmentno;
        public AddExpenseDevExFrmTest()
        {
            InitializeComponent();
            repoaccountcode.Popup += (s, e) =>
            {
                var edit = s as DevExpress.XtraEditors.SearchLookUpEdit;
                edit.Properties.View.BestFitColumns();
            };
            repoaccountcode.NullText = "";
            repoaccountcode.View.OptionsView.ColumnAutoWidth = false;
            repoaccountcode.View.BestFitColumns();

            repoaccountcode.AutoHeight = false;

        }

        private void AddExpenseDevExFrm_Load(object sender, EventArgs e)
        { 
            txtticketno.Text = getTicketNumber(); //IDGenerator.getLastTicketNumber().ToString();//getTicketNo();
            txtrefno.Text = IDGenerator.getIDNumberSP("sp_GetReferenceNumber", "ReferenceNumber");//IDGenerator.getExpenseNumber();
            displayvendor();
            populateBranches();
            populateBranches2();
            table = new DataTable();
            table.Columns.Add("Particulars");
            table.Columns.Add("AccountCode");
            table.Columns.Add("AccountTitle");

            table.Columns.Add("Debit", typeof(decimal));
            table.Columns.Add("Credit", typeof(decimal));
            //table.Columns.Add("Debit");
            //table.Columns.Add("Credit");
            gridControl1.DataSource = table;
            gridView1.Columns["Debit"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "Debit", "{0:n2}");
            gridView1.Columns["Credit"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "Credit", "{0:n2}");

            gridView1.Columns["Debit"].DisplayFormat.FormatType =
                DevExpress.Utils.FormatType.Numeric;
            gridView1.Columns["Debit"].DisplayFormat.FormatString = "n2";

            gridView1.Columns["Credit"].DisplayFormat.FormatType =
                DevExpress.Utils.FormatType.Numeric;
            gridView1.Columns["Credit"].DisplayFormat.FormatString = "n2";


            // ✅ IMPORTANT: attach Shown event    
            this.Shown -= AddExpenseDevExFrm_Shown;
            this.Shown += AddExpenseDevExFrm_Shown;
        }


        //private void loadRepositoryItem()
        //{
        //    Database.displayRepositorySearchlookupEdit(
        //        "SELECT AccountCode,Description FROM ChartOfAccounts",
        //        repoaccountcode,
        //        "AccountCode",
        //        "AccountCode");

        //    repoaccountcode.NullText = "";
        //    repoaccountcode.PopupFilterMode = PopupFilterMode.Contains;
        //    repoaccountcode.TextEditStyle = TextEditStyles.Standard;
        //    repoaccountcode.ImmediatePopup = true;

        //    GridView view = repoaccountcode.PopupView as GridView;

        //    if (view == null)
        //    {
        //        MessageBox.Show("PopupView is null");
        //        return;
        //    }

        //    view.PopulateColumns();


        //    if (view.Columns["AccountCode"] != null)
        //        view.Columns["AccountCode"].Caption = "Account Code";

        //    if (view.Columns["Description"] != null)
        //        view.Columns["Description"].Caption = "Account Title";

        //    //view.Columns["AccountCode"].Caption = "Account Code";
        //    //view.Columns["Description"].Caption = "Account Title";
        //    view.OptionsFind.FindFilterColumns = "*";
        //    view.OptionsFind.AlwaysVisible = true;
        //    //view.OptionsFind.FindFilterColumns = "AccountCode;Description";

        //    view.OptionsView.ShowAutoFilterRow = false;
        //    view.OptionsView.ColumnAutoWidth = false;

        //    view.BestFitColumns();

        //    repoaccountcode.EditValueChanged -= Repoaccountcode_EditValueChanged;
        //    repoaccountcode.EditValueChanged += Repoaccountcode_EditValueChanged;
        //}

        //void loadRepositoryItem()
        //{


        //    //Database.displayRepositorySearchlookupEdit(
        //    //    "SELECT AccountCode,Description FROM ChartOfAccounts",
        //    //    repoaccountcode,
        //    //    "AccountCode",     // ✅ ValueMember
        //    //    "AccountCode"      // ✅ DisplayMember
        //    //);
        //    Database.displayRepositorySearchlookupEdit(
        //        "SELECT AccountCode,Description FROM ChartOfAccounts",
        //        repoaccountcode,
        //        "AccountCode",
        //        "AccountCode"
        //    );

        //    //GridView view = repoaccountcode.View;
        //    var view = repoaccountcode.View;


        //    // ✅ Now safely access columns
        //    if (view.Columns["AccountCode"] != null)
        //        view.Columns["AccountCode"].Caption = "Account Code";


        //    if (view.Columns["Description"] != null)
        //        view.Columns["Description"].Caption = "Account Title";

        //    view.Columns["AccountCode"].Caption = "Account Code";
        //    view.Columns["Description"].Caption = "Account Title";
        //    view.PopulateColumns();
        //    view.OptionsView.ShowAutoFilterRow = false;
        //    view.OptionsFind.AlwaysVisible = true;
        //    view.OptionsFind.FindFilterColumns = "AccountCode;Description";


        //    //repoaccountcode.NullText = "";
        //    //repoaccountcode.PopupFilterMode = DevExpress.XtraEditors.PopupFilterMode.Contains;
        //    //repoaccountcode.TextEditStyle = DevExpress.XtraEditors.Controls.TextEditStyles.Standard;
        //    //repoaccountcode.ImmediatePopup = true;


        //    // ✅ Configure popup view (this is the key part)







        //    view.OptionsFind.FindFilterColumns = "AccountCode;Description";

        //    view.OptionsView.ShowAutoFilterRow = false; // ✅ this enables filtering UI
        //    view.OptionsView.ColumnAutoWidth = false;
        //    view.BestFitColumns();


        //    // ✅ Show BOTH Code + Description in dropdown
        //    //repoaccountcode.Popup += (s, e) =>
        //    //{
        //    //    ((SearchLookUpEdit)s).Properties.View.BestFitColumns();
        //    //};
        //    //repoaccountcode.View.BestFitColumns();
        //    //repoaccountcode.PopupFilterMode = PopupFilterMode.Contains;

        //    // ✅ When selecting → fill BOTH columns in grid
        //    repoaccountcode.EditValueChanged += Repoaccountcode_EditValueChanged;


        //    spindebit.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
        //    spindebit.DisplayFormat.FormatString = "n2";
        //    spindebit.EditFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
        //    spindebit.EditFormat.FormatString = "n2";
        //    spindebit.Mask.EditMask = "n2";
        //    spindebit.Mask.UseMaskAsDisplayFormat = true;
        //    spindebit.IsFloatValue = true;

        //    spincredit.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
        //    spincredit.DisplayFormat.FormatString = "n2";
        //    spincredit.EditFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
        //    spincredit.EditFormat.FormatString = "n2";
        //    spincredit.Mask.EditMask = "n2";
        //    spincredit.Mask.UseMaskAsDisplayFormat = true;
        //    spincredit.IsFloatValue = true;

        //    //repoaccountcode.CustomDisplayText += (s, e) =>
        //    //{
        //    //    if (e.Value == null) return;
        //    //    var row = view.GetFocusedDataRow();
        //    //    if (row != null)
        //    //    {
        //    //        e.DisplayText = row["AccountCode"] + " - " + row["Description"];
        //    //    }
        //    //};
        //    //repoaccountcode.CustomDisplayText += (s, e) =>
        //    //{
        //    //    if (e.Value == null) return;

        //    //    GridView gv = repoaccountcode.View;
        //    //    int rowHandle = gv.LocateByValue("AccountCode", e.Value);

        //    //    if (rowHandle >= 0)
        //    //    {
        //    //        string code = gv.GetRowCellValue(rowHandle, "AccountCode")?.ToString();
        //    //        string desc = gv.GetRowCellValue(rowHandle, "Description")?.ToString();

        //    //        e.DisplayText = $"{code} - {desc}";
        //    //    }
        //    //};


        //}
        //void loadRepositoryItem()
        //{


        //    DataTable dt = new DataTable();

        //    using (SqlConnection con = Database.getConnection())
        //    {
        //        SqlDataAdapter da = new SqlDataAdapter(
        //            "SELECT AccountCode,Description FROM ChartOfAccounts",
        //            con);

        //        da.Fill(dt);
        //    }

        //    repoaccountcode.DataSource = dt;
        //    repoaccountcode.ValueMember = "AccountCode";
        //    repoaccountcode.DisplayMember = "Description";
        //    repoaccountcode.View.PopulateColumns();

        //    repoaccountcode.NullText = "";
        //    repoaccountcode.PopupFilterMode = PopupFilterMode.Contains;

        //    repoaccountcode.View.OptionsFilter.AllowFilterEditor = true;
        //    repoaccountcode.View.OptionsFind.AlwaysVisible = true;
        //    repoaccountcode.View.OptionsFind.FindMode = DevExpress.XtraEditors.FindMode.Always;
        //    repoaccountcode.View.OptionsFind.SearchInPreview = false;

        //    repoaccountcode.View.OptionsFind.FindFilterColumns =
        //        "AccountCode;Description";

        //    // ✅ Configure popup view (this is the key part)
        //    var view = repoaccountcode.View;

        //    view.OptionsFind.AlwaysVisible = true;
        //    view.OptionsFind.FindMode = DevExpress.XtraEditors.FindMode.Always;
        //    view.OptionsFind.FindFilterColumns = "AccountCode;Description";
        //    view.OptionsFind.HighlightFindResults = true;
        //    view.OptionsFilter.AllowFilterEditor = true;

        //    // ✅ Force column creation
        //    view.PopulateColumns();

        //    // ✅ Now safely access columns
        //    if (view.Columns["AccountCode"] != null)
        //        view.Columns["AccountCode"].Caption = "Account Code";

        //    if (view.Columns["Description"] != null)
        //        view.Columns["Description"].Caption = "Account Title";

        //    if (view.Columns["Description"] != null)
        //    {
        //        view.Columns["Description"].OptionsFilter.AllowFilter = true;
        //    }


        //    view.OptionsView.ColumnAutoWidth = false;
        //    view.BestFitColumns();

        //    // ✅ Show BOTH Code + Description in dropdown
        //    repoaccountcode.Popup += (s, e) =>
        //    {
        //        ((SearchLookUpEdit)s).Properties.View.BestFitColumns();
        //    };

        //    // ✅ When selecting → fill BOTH columns in grid
        //    repoaccountcode.EditValueChanged += Repoaccountcode_EditValueChanged;


        //    repoaccountcode.CustomDisplayText += (s, e) =>
        //    {
        //        if (e.Value == null) return;

        //        GridView gv = repoaccountcode.View;
        //        int rowHandle = gv.LocateByValue("AccountCode", e.Value);

        //        if (rowHandle >= 0)
        //        {
        //            string code = gv.GetRowCellValue(rowHandle, "AccountCode").ToString();
        //            string desc = gv.GetRowCellValue(rowHandle, "Description").ToString();

        //            e.DisplayText = $"{code} - {desc}";
        //        }
        //    };


        //}

        private void Repoaccountcode_EditValueChanged(object sender, EventArgs e)
        {
            //SearchLookUpEdit editor = sender as SearchLookUpEdit;
            //if (editor == null) return;

            //DataRowView row =
            //    editor.Properties.GetRowByKeyValue(editor.EditValue) as DataRowView;

            //if (row == null) return;

            //int handle = gridView1.FocusedRowHandle;

            //gridView1.SetRowCellValue(handle, "AccountCode",
            //    row["AccountCode"].ToString());

            //gridView1.SetRowCellValue(handle, "AccountTitle",
            //    row["Description"].ToString());

            //gridView1.CloseEditor();
            //gridView1.UpdateCurrentRow();

            //gridView1.FocusedColumn = gridView1.Columns["Debit"];
            //gridView1.ShowEditor();
            gridView1.CloseEditor();
            gridView1.FocusedColumn = gridView1.Columns["Debit"];
            gridView1.ShowEditor();
        }


        void populateBranches()
        {
            //Database.displayDevComboBoxItems("SELECT BranchCode FROM Branches", "BranchCode", txtbrcode);
                        Database.displaySearchlookupEdit(
                @"SELECT
                    BranchCode,
                    BranchName,
                    BranchCode + ' - ' + BranchName AS DisplayText
                  FROM Branches",
                txtbranches,
               
                "DisplayText",   // DisplayMember
                 "BranchCode"       // ValueMember
            );
        }



        void populateBranches2()
        {
            Database.displayDevComboBoxItems("SELECT BranchCode FROM Branches", "BranchCode", txtbrcodesum);
        }
       
        String getTicketNumber()
        {
            string num = "";
            SqlConnection con = Database.getConnection();
            con.Open();
            string query = "sp_GetTicketNumber";
            SqlCommand com = new SqlCommand(query, con);
            com.CommandType = CommandType.StoredProcedure;
            com.CommandText = query;
            SqlDataReader reader = com.ExecuteReader();
            if (reader != null)
            {
                while (reader.Read())
                {
                    num = reader["TicketNumber"].ToString();
                }
            }
            return num;
            //  con.Close();
        }

        private void simpleButton3_Click(object sender, EventArgs e)
        {
            DataRow newRow = table.NewRow();
            newRow["Particulars"] = "";
            newRow["Debit"] = 0m;
            newRow["Credit"] = 0m;
            table.Rows.Add(newRow);
            gridControl1.DataSource = table;
        }

        private void gridView1_CustomRowCellEdit(object sender, DevExpress.XtraGrid.Views.Grid.CustomRowCellEditEventArgs e)
        {
            if (e.Column.FieldName == "AccountCode")
                e.RepositoryItem = repoaccountcode;
            if (e.Column.FieldName == "Debit")
                e.RepositoryItem = spindebit;
            if (e.Column.FieldName == "Credit")
                e.RepositoryItem = spincredit;
        }
        
        private void simpleButton4_Click(object sender, EventArgs e)
        {

            try
            {
                if (string.IsNullOrWhiteSpace(txtrefno.Text) || string.IsNullOrWhiteSpace(txtbranches.Text) || string.IsNullOrWhiteSpace(txtvendor.Text) ||
                    string.IsNullOrWhiteSpace(txtremakrs.Text))
                {
                    XtraMessageBox.Show("Please Input All Valid Fields");
                    return;
                }
                if(Convert.ToDouble(lbltotaldebit.Text) <= 0 || Convert.ToDouble(lbltotalcredit.Text) <= 0)
                {
                    XtraMessageBox.Show("Please make sure you have GL Entries");
                    return;
                }

                for (int i = 0; i < gridView1.RowCount; i++)
                {
                    decimal debit = Convert.ToDecimal(gridView1.GetRowCellValue(i, "Debit") ?? 0);
                    decimal credit = Convert.ToDecimal(gridView1.GetRowCellValue(i, "Credit") ?? 0);
                    string acct = gridView1.GetRowCellValue(i, "AccountCode")?.ToString();

                    if (string.IsNullOrEmpty(acct))
                    {
                        XtraMessageBox.Show($"Row {i + 1}: Account is required.");
                        return;
                    }

                    if ((debit > 0 && credit > 0) || (debit == 0 && credit == 0))
                    {
                        XtraMessageBox.Show($"Row {i + 1}: Enter amount in either Debit OR Credit only.");
                        return;
                    }
                }


                var dt = BuildExpenseDetailsTVP();

                using (SqlConnection con = Database.getConnection())
                {
                    con.Open();

                    using (SqlCommand cmd = new SqlCommand("spu_PostExpenseV2", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;

                        cmd.Parameters.AddWithValue("@ExpenseDetails", dt);
                        cmd.Parameters.AddWithValue("@TicketNumber", txtticketno.Text);
                        cmd.Parameters.AddWithValue("@BranchCode", objbranches.ToString() ?? "");
                        cmd.Parameters.AddWithValue("@ReferenceNumber", txtrefno.Text);
                        cmd.Parameters.AddWithValue("@InvoiceNo", txtinvoiceno.Text);
                        cmd.Parameters.AddWithValue("@ShipmentNo", objshipmentno == null ? "" : objshipmentno.ToString());

                        cmd.Parameters.AddWithValue("@SupplierID", objvendor.ToString() ?? "");
                        //cmd.Parameters.AddWithValue("@ExpenseName", txtexpname.Text);
                        cmd.Parameters.AddWithValue("@ExpenseDate", txtexpdate.DateTime);
                        //cmd.Parameters.AddWithValue("@ExpenseAmount", txtexpamount.Text);
                        cmd.Parameters.AddWithValue("@Remarks", txtremakrs.Text);
                        cmd.Parameters.AddWithValue("@isLinkedToPO", chcklinktopo.Checked ? 1 : 0);

                        cmd.Parameters.AddWithValue("@User", Login.Fullname);
                        //cmd.Parameters.AddWithValue("@Mode", batchmode.Checked ? "BATCH" : "SINGLE");

                        cmd.ExecuteNonQuery();
                    }
                }

                XtraMessageBox.Show("Successfully Added!");
                this.Close();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message);
            }
        }

        private void gridView1_CellValueChanged(object sender, DevExpress.XtraGrid.Views.Base.CellValueChangedEventArgs e)
        {
            // AccountTitle lookup — only when AccountCode changed
            if (e.Column.FieldName == "AccountCode" && _accountsCache != null)
            {
                string code = e.Value?.ToString();
                if (!string.IsNullOrEmpty(code))
                {
                    DataRow[] match = _accountsCache.Select($"AccountCode = '{code.Replace("'", "''")}'");
                    if (match.Length > 0)
                        gridView1.SetRowCellValue(e.RowHandle, "AccountTitle", match[0]["Description"].ToString());
                }
            }

            // Debit/Credit mutual exclusivity
            if (e.Column.FieldName == "Debit")
            {
                decimal debit = Convert.ToDecimal(gridView1.GetRowCellValue(e.RowHandle, "Debit") ?? 0);
                if (debit > 0)
                    gridView1.SetRowCellValue(e.RowHandle, "Credit", 0);
            }
            if (e.Column.FieldName == "Credit")
            {
                decimal credit = Convert.ToDecimal(gridView1.GetRowCellValue(e.RowHandle, "Credit") ?? 0);
                if (credit > 0)
                    gridView1.SetRowCellValue(e.RowHandle, "Debit", 0);
            }

            // Recompute totals — now runs on every relevant change, not just AccountCode
            decimal totalDebit = 0;
            decimal totalCredit = 0;
            for (int i = 0; i < gridView1.RowCount; i++)
            {
                totalDebit += Convert.ToDecimal(gridView1.GetRowCellValue(i, "Debit") ?? 0);
                totalCredit += Convert.ToDecimal(gridView1.GetRowCellValue(i, "Credit") ?? 0);
            }
            lbltotaldebit.Text = totalDebit.ToString("N2");
            lbltotalcredit.Text = totalCredit.ToString("N2");
            //if (e.Column.FieldName != "AccountCode" || _accountsCache == null) return;

            //string code = e.Value?.ToString();
            //if (string.IsNullOrEmpty(code)) return;

            //DataRow[] match = _accountsCache.Select($"AccountCode = '{code.Replace("'", "''")}'");
            //if (match.Length > 0)
            //    gridView1.SetRowCellValue(e.RowHandle, "AccountTitle", match[0]["Description"].ToString());

            //if (e.Column.FieldName == "Debit")
            //{
            //    decimal debit = Convert.ToDecimal(gridView1.GetRowCellValue(e.RowHandle, "Debit") ?? 0);

            //    if (debit > 0)
            //    {
            //        gridView1.SetRowCellValue(e.RowHandle, "Credit", 0);
            //    }
            //}

            //if (e.Column.FieldName == "Credit")
            //{
            //    decimal credit = Convert.ToDecimal(gridView1.GetRowCellValue(e.RowHandle, "Credit") ?? 0);

            //    if (credit > 0)
            //    {
            //        gridView1.SetRowCellValue(e.RowHandle, "Debit", 0);
            //    }
            //}

            //// ✅ recompute totals
            //decimal totalDebit = 0;
            //decimal totalCredit = 0;

            //for (int i = 0; i < gridView1.RowCount; i++)
            //{
            //    totalDebit += Convert.ToDecimal(gridView1.GetRowCellValue(i, "Debit") ?? 0);
            //    totalCredit += Convert.ToDecimal(gridView1.GetRowCellValue(i, "Credit") ?? 0);
            //}

            //lbltotaldebit.Text = totalDebit.ToString("N2");
            //lbltotalcredit.Text = totalCredit.ToString("N2");
        }


        private void repositoryItemButtonEdit1_Click(object sender, EventArgs e)
        {
            SearchAccountCode sacForm = new SearchAccountCode();
            sacForm.FormClosed += new FormClosedEventHandler(SacForm_FormClosed);
            sacForm.Show();
        }

        private void SacForm_FormClosed(object sender, FormClosedEventArgs e)
        {
            gridView1.SetRowCellValue(gridView1.FocusedRowHandle, "AccountCode", SearchAccountCode.acctcode);
            gridView1.SetRowCellValue(gridView1.FocusedRowHandle, "AccountTitle", SearchAccountCode.acctdesc);
            gridView1.FocusedColumn = gridView1.Columns["Debit"];
        }

        private void gridView1_ShowingEditor(object sender, CancelEventArgs e)
        {


            int row = gridView1.FocusedRowHandle;
            string column = gridView1.FocusedColumn.FieldName;

            decimal debit = Convert.ToDecimal(gridView1.GetRowCellValue(row, "Debit") ?? 0);
            decimal credit = Convert.ToDecimal(gridView1.GetRowCellValue(row, "Credit") ?? 0);

            if (column == "Debit" && credit > 0)
                e.Cancel = true;

            if (column == "Credit" && debit > 0)
                e.Cancel = true;

            if (column == "AccountTitle")
                e.Cancel = true;


        }

        private void checkBox1_CheckedChanged(object sender, EventArgs e)
        {
            if(checkBox1.Checked==true)
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
            if(ok)
            {
                Database.display("SELECT * FROM view_ExpenseSummary WHERE ExpenseDate >= '" + datefrom.Text + "' and ExpenseDate <= '" + dateto.Text + "'", gridControl2, gridView2);
            }
            else
            {
                Database.display("SELECT * FROM view_ExpenseSummary WHERE ExpenseDate >= '" + datefrom.Text + "' and ExpenseDate <= '" + dateto.Text + "' AND BranchCode='"+txtbrcodesum.Text+"'", gridControl2, gridView2);
            }
        }

        private void cancelLineToolStripMenuItem_Click(object sender, EventArgs e)
        {
            gridView1.DeleteSelectedRows();
            double debittt = 0.0, creditt = 0.0;
            for (int i = 0; i <= gridView1.RowCount - 1; i++)
            {
                acctcode = gridView1.GetRowCellValue(i, "AccountCode").ToString();
                accttitle = gridView1.GetRowCellValue(i, "AccountTitle").ToString();
                deb = gridView1.GetRowCellValue(i, "Debit").ToString();
                cred = gridView1.GetRowCellValue(i, "Credit").ToString();
                debittt += Convert.ToDouble(deb);
                creditt += Convert.ToDouble(cred);
            }
            lbltotaldebit.Text = debittt.ToString();
            lbltotalcredit.Text = creditt.ToString();
        }

        private void gridView1_RowCellStyle(object sender, DevExpress.XtraGrid.Views.Grid.RowCellStyleEventArgs e)
        {

            decimal debit = Convert.ToDecimal(gridView1.GetRowCellValue(e.RowHandle, "Debit") ?? 0);
            decimal credit = Convert.ToDecimal(gridView1.GetRowCellValue(e.RowHandle, "Credit") ?? 0);

            if ((debit > 0 && credit > 0) || (debit == 0 && credit == 0))
            {
                e.Appearance.BackColor = Color.LightCoral;
                e.Appearance.ForeColor = Color.Black;
            }

        }

        private void gridView1_KeyDown(object sender, KeyEventArgs e)
        {


            if (e.KeyCode == Keys.Enter)
            {
                e.Handled = true;

                var view = gridView1;
                view.CloseEditor();
                view.UpdateCurrentRow();

                int row = view.FocusedRowHandle;
                string col = view.FocusedColumn.FieldName;

                decimal debit = Convert.ToDecimal(view.GetRowCellValue(row, "Debit") ?? 0);
                decimal credit = Convert.ToDecimal(view.GetRowCellValue(row, "Credit") ?? 0);

                // ✅ If on Debit and still 0 → go to Credit
                if (col == "Debit" && debit == 0)
                {
                    view.FocusedColumn = view.Columns["Credit"];
                    view.ShowEditor();
                    return;
                }

                // ✅ If on Credit and still 0 → go back to Debit
                if (col == "Credit" && credit == 0)
                {
                    view.FocusedColumn = view.Columns["Debit"];
                    view.ShowEditor();
                    return;
                }

                // ✅ Move to next column
                int colIndex = view.FocusedColumn.VisibleIndex;

                if (colIndex < view.VisibleColumns.Count - 1)
                {
                    view.FocusedColumn = view.VisibleColumns[colIndex + 1];
                    view.ShowEditor();
                }
                else
                {
                    // ✅ Move to next row
                    view.FocusedRowHandle++;

                    if (view.FocusedRowHandle == view.RowCount)
                    {
                        DataRow newRow = table.NewRow();
                        newRow["Debit"] = 0m;
                        newRow["Credit"] = 0m;
                        table.Rows.Add(newRow);
                    }

                    view.FocusedColumn = view.Columns["AccountCode"];
                    view.ShowEditor();
                }
            }


        }

        private void gridView1_ValidateRow(object sender, DevExpress.XtraGrid.Views.Base.ValidateRowEventArgs e)
        {


            //var view = sender as DevExpress.XtraGrid.Views.Grid.GridView;

            //decimal debit = Convert.ToDecimal(view.GetRowCellValue(e.RowHandle, "Debit") ?? 0);
            //decimal credit = Convert.ToDecimal(view.GetRowCellValue(e.RowHandle, "Credit") ?? 0);

            //if (debit == 0 && credit == 0)
            //{
            //    e.Valid = false;
            //    view.SetColumnError(view.Columns["Debit"], "Enter Debit or Credit");
            //    view.SetColumnError(view.Columns["Credit"], "Enter Debit or Credit");
            //}

        }

        private async void AddExpenseDevExFrm_Shown(object sender, EventArgs e)
        {
            //loadRepositoryItem(); 07162026
            if (_initialized) return;
            _initialized = true;

            await InitializeFormAsync();
        }

        private async Task InitializeFormAsync()
        {
            try
            {
                UseWaitCursor = true;
  
                var accounts = await GetDataTableAsync("SELECT AccountCode,Description FROM ChartOfAccounts");

                // NEW: pull the EWT-bearing mappings once
                //var ewtRows = await GetDataTableAsync(@"
                //    SELECT ExpenseName, AccountCode AS EWTAccountCode,
                //           ATCCode, ATCRate, IsRateAmbiguous
                //    FROM ExpenseJournalMapping
                //    WHERE AmountType = 'EWT' AND DebitCredit = 'C' AND IsActive = 1");

                //BuildEWTMapCache(ewtRows);   // NEW
                 
                BindRepositoryItems(accounts);
            }
            catch (Exception ex)
            {
                DevExpress.XtraEditors.XtraMessageBox.Show(
                    $"Error loading form: {ex.Message}",
                    "Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            finally
            {
                UseWaitCursor = false;
            }
        }
        private DataTable _accountsCache;

        private void BindRepositoryItems(DataTable accounts)
        {
            _accountsCache = accounts;
            repoaccountcode.BeginUpdate();
            try
            {
                repoaccountcode.DataSource = accounts;
                repoaccountcode.DisplayMember = "AccountCode";
                repoaccountcode.ValueMember = "AccountCode";
            }
            finally
            {
                repoaccountcode.EndUpdate();
            }
        }

        private void gridControl2_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStrip2.Show(gridControl2, e.Location);
        }
        void LoadPreviousEntry(string ReferenceNumber)
        {
            DataTable dt = Database.GetDataTable($@"
                    SELECT '' as Particulars,AccountCode,Description as AccountTitle,Debit,Credit
                    FROM view_TicketDetails 
                    WHERE ReferenceNumber IN (SELECT ReferenceNumber FROM ExpenseSummary WHERE ReferenceNumber='{ReferenceNumber}') 
                ");

            table.Rows.Clear(); // ✅ clear current rows

            foreach (DataRow row in dt.Rows)
            {
                DataRow newRow = table.NewRow();

                newRow["AccountCode"] = row["AccountCode"];
                newRow["AccountTitle"] = row["AccountTitle"];
                newRow["Debit"] = Convert.ToDecimal(row["Debit"]);
                newRow["Credit"] = Convert.ToDecimal(row["Credit"]);
                newRow["Particulars"] = row["Particulars"];

                table.Rows.Add(newRow);
            }

            gridControl1.DataSource = table;

            gridView1.BestFitColumns();
        }

        private void copyTicketEntriesToolStripMenuItem_Click(object sender, EventArgs e)
        {

            string prevTicket = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "ReferenceNumber").ToString();

            LoadPreviousEntry(prevTicket);

            // ✅ SWITCH TO FIRST TAB
            xtraTabControl1.SelectedTabPage = xtraTabPage1;

            // ✅ OPTIONAL: focus grid for better UX
            gridControl1.Focus();
            gridView1.FocusedRowHandle = 0;


        }

        private void labelControl5_Click(object sender, EventArgs e)
        {

        }
        private async Task<DataTable> GetDataTableAsync(string sql)
        {
            var dt = new DataTable();

            using (var con = Database.getConnection()) // replace with your actual connection string
            using (var cmd = new SqlCommand(sql, con))
            {
                await con.OpenAsync();

                using (var reader = await cmd.ExecuteReaderAsync())
                {
                    dt.Load(reader);
                }
            }

            return dt;
        }
        private void BindPurchaseList(DataTable purchaseList)
        {
            txtpo.Properties.BeginUpdate();
            try
            {
                txtpo.Properties.DataSource = purchaseList;
                txtpo.Properties.DisplayMember = "DisplayText";
                txtpo.Properties.ValueMember = "ShipmentNo"; // better unique key if PO selection is by shipment
                txtpo.Properties.PopulateViewColumns();

                if (txtpo.Properties.View.Columns["SupplierId"] != null)
                    txtpo.Properties.View.Columns["SupplierId"].Visible = false;
            }
            finally
            {
                txtpo.Properties.EndUpdate();
            }
        }
        private bool _poLoaded = false;
        private bool _isLoadingPO = false;
        private async void chcklinktopo_CheckedChanged(object sender, EventArgs e)
        {
            if (chcklinktopo.Checked)
            {
                txtpo.Enabled = false; // disable while loading
                // Prevent duplicate calls
                if (_poLoaded || _isLoadingPO)
                {
                    txtpo.Enabled = true;
                    return;
                }
                try
                {
                    _isLoadingPO = true;
                    Cursor = Cursors.WaitCursor;

                    var purchaseList = await GetDataTableAsync(@"
                            SELECT ShipmentNo, SupplierId, SupplierName, ShipmentNo+'-'+SupplierName AS DisplayText 
                            FROM dbo.view_POSUMMARYREP
                            WHERE Status <> 'CANCELLED'");

                    BindPurchaseList(purchaseList);

                    _poLoaded = true;
                }
                catch (Exception ex)
                {
                    DevExpress.XtraEditors.XtraMessageBox.Show(
                        ex.Message,
                        "Error",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                }
                finally
                {
                    _isLoadingPO = false;
                    txtpo.Enabled = true;
                    Cursor = Cursors.Default;
                }
            }
            else
            {
                // Disable AND clear selection
                txtpo.EditValue = null;
                txtpo.Properties.DataSource = null;
                txtpo.Enabled = false;

                // Optional: if you want reload every time user checks again
                // _poLoaded = false;
            }

        }

        private void txtvendor_EditValueChanged(object sender, EventArgs e)
        {
            objvendor = null;
            objvendor = SearchLookUpClass.getSingleValue(txtvendor, "SupplierKey");
        }

        private void insertRowAboveToolStripMenuItem_Click(object sender, EventArgs e)
        {

            int rowHandle = gridView1.FocusedRowHandle;

            DataRow newRow = table.NewRow();
            newRow["Particulars"] = "";
            newRow["Debit"] = 0m;
            newRow["Credit"] = 0m;

            if (rowHandle >= 0)
                table.Rows.InsertAt(newRow, rowHandle);
            else
                table.Rows.Add(newRow);

            gridView1.FocusedRowHandle = rowHandle;

        }

        private void insertRowBelowToolStripMenuItem_Click(object sender, EventArgs e)
        {
            int rowHandle = gridView1.FocusedRowHandle;

            DataRow newRow = table.NewRow();
            newRow["Particulars"] = "";
            newRow["Debit"] = 0m;
            newRow["Credit"] = 0m;

            if (rowHandle >= 0)
                table.Rows.InsertAt(newRow, rowHandle + 1);
            else
                table.Rows.Add(newRow);

            gridView1.FocusedRowHandle = rowHandle + 1;

        }

        private void txtpo_EditValueChanged(object sender, EventArgs e)
        {
            objshipmentno = null;
            objshipmentno = SearchLookUpClass.getSingleValue(txtpo, "ShipmentNo");
        }

        private void txtbranches_EditValueChanged(object sender, EventArgs e)
        {
            objbranches = null;
            objbranches = SearchLookUpClass.getSingleValue(txtbranches, "BranchCode");
        }

        private void gridControl1_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
            {
                contextMenuStrip1.Show(gridControl1, e.Location);
            }
        }

        void displayvendor()
        {
            //Database.displaySearchlookupEdit("select SupplierID,SupplierName FROM Supplier", txtvendor, "SupplierID", "SupplierID");

            Database.displaySearchlookupEdit(
                  @"SELECT
                    SupplierKey,
                    SupplierID,
                    SupplierName,
                    SupplierKey + ' - ' + SupplierName AS SupplierDisplay
                  FROM Supplier",
                  txtvendor,
                 
                  "SupplierDisplay",   // DisplayMember
                   "SupplierKey"       // ValueMember
              );

        }

        private DataTable BuildExpenseDetailsTVP()
        {
            var dt = new DataTable();

            dt.Columns.Add("BranchCode", typeof(string));
            dt.Columns.Add("AccountCode", typeof(string));
            dt.Columns.Add("AccountTitle", typeof(string));
            dt.Columns.Add("Debit", typeof(decimal));
            dt.Columns.Add("Credit", typeof(decimal));
            dt.Columns.Add("Particulars", typeof(string));

            for (int i = 0; i < gridView1.RowCount; i++)
            {
                dt.Rows.Add(
                    objbranches.ToString(),
                    gridView1.GetRowCellValue(i, "AccountCode"),
                    gridView1.GetRowCellValue(i, "AccountTitle"),
                    Convert.ToDecimal(gridView1.GetRowCellValue(i, "Debit") ?? 0),
                    Convert.ToDecimal(gridView1.GetRowCellValue(i, "Credit") ?? 0),
                    gridView1.GetRowCellValue(i, "Particulars")
                );
            }

            return dt;
        }

    }
}