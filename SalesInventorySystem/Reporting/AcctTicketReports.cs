using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using DevExpress.XtraGrid.Views.Grid;
using DevExpress.XtraEditors;
using System.Data.SqlClient;

namespace SalesInventorySystem.Reporting
{
    public partial class AcctTicketReports : Form
    {
        //public static string debitvalue="", creditvalue = "";

        //private Dictionary<object, bool> ticketColorMap = new Dictionary<object, bool>();
        //private bool currentFlag = false;

        private object lastTicket = null;
        private bool alternate = false;


        public AcctTicketReports()
        {
            InitializeComponent();
        }

        private void button1_Click(object sender, EventArgs e)
        {
            
        }

        void populateComboBox()
        {
            Database.displaySearchlookupEdit("SELECT BranchCode,BranchName FROM Branches", txtbrcode,"BranchCode","BranchCode");
        }


        private void LoadTickets(
           string brcode,
           DateTime fromDate,
           DateTime toDateExclusive,
           DevExpress.XtraGrid.GridControl grid,
           DevExpress.XtraGrid.Views.Grid.GridView view,
           string dateColumn,
           string orderByClause = "")
        {
            string sql = $@"
        SELECT *
        FROM view_AccountingTicketReports
        WHERE BranchCode = @brcode
          AND {dateColumn} >= @fromDate
          AND {dateColumn} <  @toDateExclusive
      
        {orderByClause}";

            try
            {
                Cursor.Current = Cursors.WaitCursor;
                this.UseWaitCursor = true;

                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand(sql, con))
                {
                    cmd.Parameters.Add("@brcode", SqlDbType.VarChar, 10).Value = brcode;
                    cmd.Parameters.Add("@fromDate", SqlDbType.DateTime).Value = fromDate;
                    cmd.Parameters.Add("@toDateExclusive", SqlDbType.DateTime).Value = toDateExclusive;
                    

                    // Use your overload that accepts SqlCommand
                    Database.display(cmd, grid, view);
                }

                view.Focus();
            }
            finally
            {
                this.UseWaitCursor = false;
                Cursor.Current = Cursors.Default;
            }
        }
        void populateRows()
        {
            try
            {
                DateTime from = txtdate.Value.Date;
                DateTime toExclusive = txtdate.Value.Date.AddDays(1);

                if (chcktickets.Checked==true)
                {
                   
                    LoadTickets(
                        brcode: Login.assignedBranch,
                        fromDate: from,
                        toDateExclusive: toExclusive,
                        grid: gridControl1,
                        view: gridView1,
                        dateColumn: "TicketDate",
                        orderByClause: "ORDER BY TicketDate ASC"
                    );
                }
                else
                {

                    LoadTickets(
                        brcode: txtbrcode.Text,
                        fromDate: from,
                        toDateExclusive: toExclusive,
                        grid: gridControl1,
                        view: gridView1,
                        dateColumn: "TicketDate",
                        orderByClause: "ORDER BY TicketDate ASC"
                    );
                }
                
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
          //  Database.displayLocalGrid("SELECT TicketDetails.TicketNumber, TicketMaster.Mnemonic, TicketDetails.AccountCode, ChartOfAccounts.Description, TicketDetails.Debit, TicketDetails.Credit, TicketMaster.Particulars, TicketMaster.EnteredBy, TicketMaster.CheckedBy, TicketMaster.ApprovedBy FROM TicketDetails INNER JOIN TicketMaster ON TicketDetails.TicketNumber=TicketMaster.TicketNumber INNER JOIN ChartOfAccounts ON TicketDetails.AccountCode=ChartOfAccounts.AccountCode WHERE TicketDetails.BranchCode='" + txtbrcode.Text + "' AND TicketDetails.TicketDate='" + txtdate.Text+ "' ORDER BY TicketDetails.TicketNumber ASC, TicketDetails.Debit ASC", dataGridView1);
        }

        Double computeTotalDebits()
        {
            double totaldebits = 0.0;
            totaldebits = Database.getTotalSummation2("view_AccountingTicketReports", "BranchCode='" + txtbrcode.Text + "' AND TicketDate='" + txtdate.Text+ "'", "Debit");
            //totaldebits =  Database.getTotalSummation("SELECT SUM(Debits) FROM FROM view_AccountingTicketReports WHERE BranchCode='" + txtbrcode.Text + "' AND TicketDate='" + txtdate.Text+ "'");
            return totaldebits;
        }

        Double computeTotalCredits()
        {
            double totalcredits = 0.0;
            totalcredits = Database.getTotalSummation2("view_AccountingTicketReports", "BranchCode='" + txtbrcode.Text + "' AND TicketDate='" + txtdate.Text+ "'", "Credit");
            //totaldebits =  Database.getTotalSummation("SELECT SUM(Debits) FROM FROM view_AccountingTicketReports WHERE BranchCode='" + txtbrcode.Text + "' AND TicketDate='" + txtdate.Text+ "'");
            return totalcredits;
        }

        private void AcctTicketReports_Load(object sender, EventArgs e)
        {
            populateComboBox();
        }

    
        private void label8_Click(object sender, EventArgs e)
        {

        }

        private void lblcredit_Click(object sender, EventArgs e)
        {

        }

        private void lbldebit_Click(object sender, EventArgs e)
        {

        }

        private void label5_Click(object sender, EventArgs e)
        {

        }

        private void label4_Click(object sender, EventArgs e)
        {

        }

        private void label9_Click(object sender, EventArgs e)
        {

        }

        private void dateTimePicker1_ValueChanged(object sender, EventArgs e)
        {

        }

        private void lblbranchname_Click(object sender, EventArgs e)
        {

        }

        private void label3_Click(object sender, EventArgs e)
        {

        }

        private void label2_Click(object sender, EventArgs e)
        {

        }

        private void label1_Click(object sender, EventArgs e)
        {

        }

        private void gridControl1_MouseUp(object sender, MouseEventArgs e)
        {
            if (Convert.ToBoolean(Login.isglobalAdmin) == true)
            {
                if (e.Button == MouseButtons.Right)
                    contextMenuStrip1.Show(gridControl1, e.Location);
            }
        }

        private void updateTicketToolStripMenuItem_Click(object sender, EventArgs e)
        {

            Accounting.UpdateTIckets updtick = new Accounting.UpdateTIckets();
            Database.display("SELECT * FROM TicketMaster WHERE TicketDate='" + txtdate.Text+ "' and BranchCode='" + txtbrcode.Text + "' AND TicketNumber='" + gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "TicketNumber").ToString() + "' ", updtick.gridControlMaster, updtick.gridViewMaster);
            Database.display("SELECT TicketDate,BranchCode,ReferenceKey,TicketNumber,AccountCode,Debit,Credit,Debit as OrigDebit,Credit as OrigCredit, AccountCode as OrigAcctCode FROM TicketDetails WHERE TicketDate='" + txtdate.Text+ "' and BranchCode='" + txtbrcode.Text + "' AND TicketNumber='" + gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "TicketNumber").ToString() + "' ", updtick.gridControlDetails, updtick.gridViewDetails);
            updtick.ShowDialog(this);
        }

        private void txtbrcode_EditValueChanged(object sender, EventArgs e)
        {
            GridView view = txtbrcode.Properties.View;
            int rowHandle = view.FocusedRowHandle;
            //string fieldName = "Name"; // or other field name
            object value = view.GetRowCellValue(rowHandle, "BranchName");
            lblbranchname.Text = value.ToString();
        }

        private void simpleButton1_Click(object sender, EventArgs e)
        {
            try
            {
                populateRows();
                lbldebit.Text = computeTotalDebits().ToString();
                lblcredit.Text = computeTotalCredits().ToString();

            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
            
        }

        private void groupControl1_Paint(object sender, PaintEventArgs e)
        {

        }

        private void gridView1_RowStyle(object sender, RowStyleEventArgs e)
        {

            if (e.RowHandle < 0) return;

            var view = sender as DevExpress.XtraGrid.Views.Grid.GridView;
            object ticket = view.GetRowCellValue(e.RowHandle, "TicketNumber");

            if (ticket == null) return;

            if (!ticket.Equals(lastTicket))
            {
                alternate = !alternate;
                lastTicket = ticket;
            }

            if (alternate)
                e.Appearance.BackColor = Color.LightBlue;


        }
    }
}
