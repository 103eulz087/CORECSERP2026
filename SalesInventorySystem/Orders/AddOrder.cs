using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Text;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using System.Data.SqlClient;
using System.Net.Sockets;
using System.Threading;
using System.Net;
using System.Web;
using DevExpress.XtraGrid.Views.Grid;
using SalesInventorySystem.Classes;
//using Excel = Microsoft.Office.Interop.Excel;

namespace SalesInventorySystem
{
    public partial class AddOrder : DevExpress.XtraEditors.XtraForm
    { 
        
        object objprodcode = null;
        object objprodcatname = null;
        private const int portNum = 8888;
        delegate void SetTextCallback(string text);
        object objcustkey = null;
        object objcreditmlimit = null;
        object objbalance = null;
        object objremaininglimit = null;
        object srvcid = null,srvccustid=null;
        private const string hostName = "192.168.99.143";
        DataTable table;
        DataTable serviceTable;
        //string itemno,desc,unitprice,sellingprice,prodname;
        //string number;
        public static string text_to_send="";
        public static string Isconnected = "";
        string company = Database.getSingleQuery("CompanyProfile", "CompanyName <> ''", "CompanyName");
        decimal tot = 0m;
        public AddOrder()
        {
            InitializeComponent();
            
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            bool functionReturnValue = false;
            //if (keyData == Keys.F1)
            //{
            //    simpleButton5.PerformClick();
            //}
            if (keyData == Keys.F5)
            {
                btnsave.PerformClick();
            }
            else if (keyData == Keys.Escape)
            {

                simpleButton9.PerformClick();
            }
            return functionReturnValue;
        }


        private void simpleButton1_Click(object sender, EventArgs e)
        {
            
            if (panel1.Visible == true && txtcustomer.Text=="")
            {
                XtraMessageBox.Show("Customer Name Must Not Empty");
                return;
            }

            if (txtqty.Text == "" || txtpname.Text.Trim()=="" || comboBox1.Text=="")
            {
                XtraMessageBox.Show("Fields must not Empty");
            }
            //else if (Convert.ToDouble(spinEdit1.Text) < 1)
            //{
            //    XtraMessageBox.Show("Quantity must Non Negative Value!");
            //}
            else
            {
                int count = 0;
                bool checkifexists = Database.checkifExist("SELECT TOP(1) PONumber FROM PurchaseOrderDetails WHERE PONumber='" + textEdit1.Text + "' AND ProductName='" + txtpname.Text.Trim() + "'");
                
                for(int i=0;i<=gridView1.RowCount-1;i++)
                {
                    if (gridView1.GetRowCellValue(i, "ProductName").ToString() == txtpname.Text.Trim())
                    {
                        //gridView1.SetRowCellValue(gridView1.FocusedRowHandle, "Qty", Convert.ToDouble(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "Qty").ToString()) + Convert.ToDouble(spinEdit1.Text));
                        count = 1;
                    }
                    else
                    {
                        count += 0;
                    }
                }
                if(count > 0)
                {
                    XtraMessageBox.Show("Product Already Exist");
                    return;
                }
                if (checkifexists)
                {
                    bool ok = HelperFunction.ConfirmDialog("Product is Already Exist!. Are you Sure you want to Continue?", "Product Exists");
                    if (ok)
                    {
                        add2();
                       // display();
                    }
                }
              
                else
                {
                    add2();
                   // display();
                }
            }
            txteffectivedate.Enabled = false;
            gridView1.MoveLast();
            //MydataGridView1.CurrentCell = MydataGridView1.Rows[MydataGridView1.Rows.Count - 1].Cells[0];
        }

        // Shared by the credit-limit trap and the invoice-lapsing trap: try the branch's remote
        // approval relay first (Classes/ApprovalRelaySession.cs), falling back to the local
        // AuthorizedConfirmationFrm flow if the relay isn't connected, the supervisor declines
        // explicitly returns false immediately, or nobody responds within the timeout.
        // Returns true if the transaction may proceed, false if it should be blocked.
        bool RequestOverrideApproval(string alertTitle, string alertMessage, string reason,
            decimal orderAmount, decimal referenceAmount, string logContext)
        {
            bool approved = false;

            Classes.ApprovalRelaySession.Log(
                $"{logContext}: Client={(Classes.ApprovalRelaySession.Client == null ? "null" : "present")}, " +
                $"IsConnected={(Classes.ApprovalRelaySession.Client != null && Classes.ApprovalRelaySession.Client.IsConnected)}, " +
                $"LastError={Classes.ApprovalRelaySession.Client?.LastError}");

            if (Classes.ApprovalRelaySession.Client != null && Classes.ApprovalRelaySession.Client.IsConnected)
            {
                DialogResult confirm = BigAlert.Show(alertTitle, alertMessage, MessageBoxIcon.Warning, MessageBoxButtons.YesNo);

                if (confirm == DialogResult.Yes)
                {
                    var request = new Classes.ApprovalRequest
                    {
                        RequestId = Guid.NewGuid().ToString(),
                        Branch = Login.assignedBranch,
                        RequestingUserID = Login.isglobalUserID,
                        RequestingUserName = Login.Fullname,
                        MachineName = GlobalVariables.computerName,
                        CustomerName = txtcustomer.Text,
                        OrderAmount = orderAmount,
                        CreditLimit = referenceAmount,
                        Reason = reason,
                        RequestedAtUtc = DateTime.UtcNow
                    };

                    Classes.ApprovalRelaySession.Log($"Sending approval request {request.RequestId} ({reason}) for Branch {request.Branch}, amount {request.OrderAmount:N2}.");

                    DevExpress.XtraSplashScreen.SplashScreenManager.ShowDefaultWaitForm();
                    DevExpress.XtraSplashScreen.SplashScreenManager.Default.SetWaitFormCaption("Waiting for Supervisor Approval");
                    DevExpress.XtraSplashScreen.SplashScreenManager.Default.SetWaitFormDescription("Your request has been sent -- waiting for a supervisor to respond...");
                    Classes.ApprovalResponse response;
                    try
                    {
                        response = Classes.ApprovalRelaySession.Client
                            .RequestApprovalAsync(request, TimeSpan.FromSeconds(60))
                            .GetAwaiter().GetResult();
                    }
                    finally
                    {
                        DevExpress.XtraSplashScreen.SplashScreenManager.CloseDefaultWaitForm();
                    }

                    Classes.ApprovalRelaySession.Log(response == null
                        ? $"No response for request {request.RequestId} within timeout."
                        : $"Response for request {request.RequestId}: {response.Message} by {response.ApproverUserID}.");

                    if (response != null && response.Approved)
                    {
                        approved = true;
                    }
                    else if (response != null && !response.Approved)
                    {
                        XtraMessageBox.Show("The request was declined by " + response.ApproverName + ".");
                        return false;
                    }
                    // response == null -> no reply within the timeout; fall through to the local
                    // fallback below rather than blocking the cashier.
                }
                else
                {
                    return false;
                }
            }

            if (!approved)
            {
                AuthorizedConfirmationFrm authfrm = new AuthorizedConfirmationFrm();
                authfrm.ShowDialog(this);
                if (AuthorizedConfirmationFrm.isconfirmedLogin == true)
                {
                    AuthorizedConfirmationFrm.isconfirmedLogin = false;
                    authfrm.Dispose();
                    approved = true;
                    // Supervisor override confirmed -- allow this order despite the trap.
                }
                else
                {
                    authfrm.Dispose();
                    return false;
                }
            }

            return approved;
        }

        // Detail text for the invoice-lapsing override prompt -- which invoices, balance, days
        // overdue. Same Balance>0 + term-exceeded condition as func_checkLapseInvoice (see
        // SQL/2026-08-09_CheckLapseInvoice_BalanceFilter.sql).
        string BuildLapsedInvoiceDetail(string custkey)
        {
            var sb = new StringBuilder();
            using (SqlConnection con = Database.getConnection())
            {
                con.Open();
                SqlCommand com = new SqlCommand(
                    "SELECT TOP 5 t.InvoiceNo, t.Balance, DATEDIFF(DAY, t.TransactionDate, GETDATE()) AS DaysOverdue " +
                    "FROM TransactionChargeSales t " +
                    "JOIN Customers c ON c.CustomerKey = t.CustomerKey " +
                    "WHERE t.CustomerKey = @custkey AND t.Balance > 0 " +
                    "AND DATEDIFF(DAY, t.TransactionDate, GETDATE()) > c.Term " +
                    "ORDER BY t.TransactionDate ASC", con);
                com.Parameters.AddWithValue("@custkey", custkey);
                using (SqlDataReader reader = com.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        sb.AppendLine("Invoice " + reader["InvoiceNo"] + ": Balance " +
                            Convert.ToDecimal(reader["Balance"]).ToString("N2") + ", " +
                            reader["DaysOverdue"] + " day(s) overdue");
                    }
                }
            }
            return sb.ToString();
        }

        void add2()
        {
            try
            {
                //var row = Database.getMultipleQuery("Customers", "CustomerName='" + txtcustomer.Text + "'", "CustomerID,isActive,CustomerCreditLimit");
                string custid =  objcustkey.ToString();
                string creditlimit = objcreditmlimit.ToString();
                string balance = objbalance.ToString();
                string remaininglimit = objremaininglimit.ToString();

                //string custid = row["CustomerID"].ToString();
                //string isactive = row["isActive"].ToString();//Database.getSingleQuery("Customers", "CustomerName='" + txtcustomer.Text + "'", "isActive");//Classes.ClientAccount.getClientID(txtcust.Text);
                //string creditlimit = row["CustomerCreditLimit"].ToString();//Database.getSingleQuery("Customers", "CustomerName='" + txtcustomer.Text + "'", "isActive");//Classes.ClientAccount.getClientID(txtcust.Text);
                string lapseTerm = Database.getSingleQuery("SalesSettings", "EnableInvoiceLapsingTerm is not null", "EnableInvoiceLapsingTerm");
                string reamrks = "",specialprice="",sellingprice=""; 
                //string itemcode = Database.getSingleQuery("Products", "DescriBption='" + txtpname.Text + "' and ProductCategoryCode='" + prodcatcode + "' and BranchCode='888'", "ProductCode");
                string itemcode = objprodcode.ToString();
                string rs =Database.getSingleResultSet("SELECT dbo.func_checkLapseInvoice('" + custid + "')");
                decimal totalamount = 0;                                               
               

                //if (Login.assignedBranch == "888")
                //{
                 if(checkBox1.Checked==true)
                 {
                     reamrks = txtItemRemarks.Text.Trim();
                 }
                 else
                 {
                     reamrks = Database.getSingleQuery("CustomerProductSetting", "ProductCode = '" + itemcode + "' AND CustID='" + custid + "' ", "Remarks");
                 }
                 //check if item exist in customer table
                 // bool prodexist = Database.checkifExist("SELECT * FROM Customers WHERE ItemCode = '" + itemcode + "' AND CustomerID='" + custid + "' ");// Database.getSingleQuery("Customers","ItemCode = '"+Classes.Product.getProductCode(txtprodname.Text,prodcatcode)+"',"sdd");
                 bool prodexist = Database.checkifExist("SELECT 1 FROM view_custprodsettings WHERE ProductCode = '" + itemcode + "' AND CustID='" + custid + "' ");// Database.getSingleQuery("Customers","ItemCode = '"+Classes.Product.getProductCode(txtprodname.Text,prodcatcode)+"',"sdd");

                 //reamrks = Database.getSingleQuery("Customers", "ItemCode = '" + itemcode + "' AND CustomerID='" + custid + "' ", "Remarks");
                 //specialprice = Database.getSingleQuery("Customers", "ItemCode = '" + itemcode + "' AND CustomerID='" + custid + "' ", "SpecialPriceAmount");
                 if (chckspecialprice.Checked == true)
                 {
                     specialprice = Database.getSingleQuery("CustomerProductSetting", "ProductCode = '" + itemcode + "' AND CustID='" + custid + "' ", "SpecialPriceAmount");
                     if (String.IsNullOrEmpty(specialprice))
                     {
                         XtraMessageBox.Show("Please check your customer product settings.. No Special Price defined");
                         return;
                     }
                     else
                     {
                         sellingprice = specialprice;
                     }

                 }
                 else
                 {
                     sellingprice = Database.getSingleQuery("Products", "ProductCode = '" + itemcode + "' AND BranchCode='" + Login.assignedBranch + "' ", "SellingPrice");
                 }

                //decimal overalltotal = 0m;
                totalamount = (Convert.ToDecimal(txtqty.Text) * Convert.ToDecimal(sellingprice));

                if (Convert.ToBoolean(lapseTerm) == true)
                 {
                     if (Convert.ToInt32(rs) > 0)
                     {
                         string lapseDetail = BuildLapsedInvoiceDetail(custid);
                         bool lapseOk = RequestOverrideApproval(
                             "INVOICE LAPSING DETECTED",
                             "The System found out that one or more invoices for this customer are already past their credit term.\n\n" +
                             lapseDetail + "\nIf you want to continue, get it approved by your supervisor.",
                             "Invoice lapsing term exceeded on Sales Order",
                             totalamount, 0m,
                             $"Invoice lapse trapped for customer {custid}, PO {textEdit1.Text}");
                         if (!lapseOk)
                             return;
                     }
                 }
                //for (int i = 0;i<=gridView1.RowCount-1;i++)
                //{
                //    overalltotal += Convert.ToDecimal(gridView1.GetRowCellValue(i,"Qty").ToString()) * Convert.ToDecimal(gridView1.GetRowCellValue(i, "SellingPrice").ToString());
                //}
                //double getCurrentBalance = Database.getTotalSummation2("ClientAccounts", "AccountID='" + custid + "'", "AccountBalance");
                tot += totalamount;
                string amountPending = Database.getSingleResultSet($"SELECT dbo.[func_getTotalAmountOfPendingPO]('{textEdit1.Text}','{custid}')");
                decimal outstandinglimitbalance = (Convert.ToDecimal(remaininglimit) - Convert.ToDecimal(amountPending));
                // EnableCreditLimit gate was missing here -- addServices()/other flows in this same
                // file already check it before enforcing the limit; this one didn't, so the credit
                // limit was always enforced regardless of the setting.
                string enableCreditLimit = Database.getSingleQuery("SalesSettings", "EnableCreditLimit is not null", "EnableCreditLimit");
                if (Convert.ToBoolean(enableCreditLimit) == true && tot > outstandinglimitbalance)
                 {
                     bool creditOk = RequestOverrideApproval(
                         "CREDIT LIMIT REACHED",
                         "The customer has reached their credit limit. The remaining limit is only " + remaininglimit +
                         ".\n\nIf you want to continue, get it approved by your supervisor.",
                         "Credit limit exceeded on Sales Order",
                         tot, Convert.ToDecimal(remaininglimit),
                         $"Credit limit trapped for PO {textEdit1.Text}");
                     if (!creditOk)
                         return;
                 }

                //if(chckfinal.Checked.Equals(true))
                //{
                //    if (Convert.ToInt32(txtqty.Text) > Database.getTotalSummation2("Inventory", "Branch='" + Login.assignedBranch + "' and Available > 0 and Product='" + getProductCode() + "' ", "Available"))
                //    {
                //        XtraMessageBox.Show("The System found out that the Quantity you Entered is Greater than your Inventory Stocks..");
                //        return;
                //    }
                //    else
                //    {
                //        Database.ExecuteQuery($"EXEC dbo.sp_FiFoMapping '{DateTime.Now.ToShortDateString()}','{Login.assignedBranch}','{getProductCode()}','{txtqty.Text}','1' ");
                //    }
                //}
                //string itemremarks = richTextBox1.Text.Trim();
              
                string prodcode = Database.getSingleQuery("Products", "Description='" + txtpname.Text + "'", "ProductCode");
                DataRow newRow = table.NewRow();
                //newRow["PONumber"] = textEdit1.Text;
                //newRow["BranchCode"] = Login.assignedBranch;
                newRow["ProductCode"] = objprodcode.ToString();
                newRow["ProductName"] = txtpname.Text;
                newRow["Qty"] = txtqty.Text;
                newRow["Units"] = comboBox1.Text;
                newRow["SellingPrice"] = sellingprice;
                //newRow["Status"] = "FOR APPROVAL";
                newRow["Remarks"] = reamrks;
                
                table.Rows.Add(newRow);
                gridControl1.DataSource = table;
                txtqty.Text = "";
                txtpname.Text = "";
                txtItemRemarks.Text = "";
                txtpname.Focus();
            }
            catch(Exception ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }

        void addServices()
        {
            try
            {

                string custkey = srvccustid?.ToString() ?? "";
                string lapseTerm = Database.getSingleQuery("SalesSettings", "EnableInvoiceLapsingTerm is not null", "EnableInvoiceLapsingTerm");

                string sellingprice = "";
                string rs = Database.getSingleResultSet("SELECT dbo.func_checkLapseInvoice('" + custkey + "')");


                if (Login.assignedBranch == "888")
                {
                    sellingprice = Database.getSingleQuery("CustomerProductSetting", "ProductCode = '" + srvcid + "' AND CustID='"+srvccustid+"'  ", "SpecialPriceAmount");

                    if (Convert.ToBoolean(lapseTerm) == true)
                    {
                        if (Convert.ToInt32(rs) > 0)
                        {
                            decimal svcAmount = Convert.ToDecimal(txtqtyservices.Text) * Convert.ToDecimal(sellingprice);
                            string lapseDetail = BuildLapsedInvoiceDetail(custkey);
                            bool lapseOk = RequestOverrideApproval(
                                "INVOICE LAPSING DETECTED",
                                "The System found out that one or more invoices for this customer are already past their credit term.\n\n" +
                                lapseDetail + "\nIf you want to continue, get it approved by your supervisor.",
                                "Invoice lapsing term exceeded on Sales Order (Services)",
                                svcAmount, 0m,
                                $"Invoice lapse trapped for customer {custkey}, SVC {txtposervices.Text} (services)");
                            if (!lapseOk)
                                return;
                        }
                    }
                }
              
                 
                DataRow newRow = serviceTable.NewRow();
                newRow["ServiceCode"] = srvcid;
                newRow["ServiceName"] = txtservices.Text;
                newRow["Qty"] = txtqtyservices.Text;
                newRow["SellingPrice"] = sellingprice;

                serviceTable.Rows.Add(newRow);
                gridControlitem.DataSource = serviceTable;
                txtqtyservices.Text = "";
                txtservices.Text = "";
                txtservices.Focus();
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }

        private void display()
        {
            Database.display("SELECT * FROM PurchaseOrderDetails WHERE PONumber='" + textEdit1.Text + "'", gridControl1, gridView1);
            gridView1.Columns[8].Visible = false;
        }

       
        private void AddOrder_Load(object sender, EventArgs e)
        {
            //this.ActiveControl = txtprodcat;
            comboBox1.Text = "Kg";
            panel1.Visible = true;
            checkBox1.Visible = true;
            chckspecialprice.Visible = true;
            //if (Login.assignedBranch == "888")
            //{

            //}
           

        }


        void loadMetrics()
        { 
            Database.displayDevComboBoxItems("SELECT * FROM Metrics", "Metrics", comboBox1);
        }
      

        void populateCustomer(SearchLookUpEdit edit)
        {
            //Database.displayComboBoxItems("SELECT CustomerName FROM Customers", "CustomerName", txtcustomer);
            Database.displaySearchlookupEdit("Select * FROM view_CustomerWithCreditLimit", edit, "CustomerName", "CustomerName");
        }
        
        private void simpleButton2_Click(object sender, EventArgs e)
        {
            string creditlimit = Database.getSingleQuery("Customers", "CustomerName='" + txtcustomer.Text + "'", "CustomerCreditLimit");
            string accountbalance = Database.getSingleQuery("ClientAccounts", "AccountID='" + Customers.getCustAccountID(txtcustomer.Text) + "'", "AccountBalance");
            if(Convert.ToDouble(accountbalance) > Convert.ToDouble(creditlimit))
            {
                XtraMessageBox.Show("Credit Limit Exceeded!...");
                return;
            }
            if(ordertype.Text=="" || ordertype == null)
            {
                XtraMessageBox.Show("Please Select Order Type!");
                return;
            }
            if (gridView1.RowCount <= 0)
            {
                XtraMessageBox.Show("Please Input Product Details!");
                return;
            }
            else
            {
                saveAll();
            }
        }

        void saveAll()
        {
            try
            {
                if (panel1.Visible == true)
                {
                    if (txtcustomer.Enabled == true && txtcustomer.Text == "")
                    {
                        XtraMessageBox.Show("Customer Field must be Selected!");
                        return;
                    }
                }

                DataTable lines = new DataTable();
                lines.Columns.Add("ProductCode", typeof(string));
                lines.Columns.Add("ProductName", typeof(string));
                lines.Columns.Add("Qty", typeof(decimal));
                lines.Columns.Add("Units", typeof(string));
                lines.Columns.Add("Remarks", typeof(string));
                lines.Columns.Add("SellingPrice", typeof(decimal));

                for (int i = 0; i <= gridView1.RowCount - 1; i++)
                {
                    lines.Rows.Add(
                        gridView1.GetRowCellValue(i, "ProductCode").ToString(),
                        gridView1.GetRowCellValue(i, "ProductName").ToString(),
                        Convert.ToDecimal(gridView1.GetRowCellValue(i, "Qty")),
                        gridView1.GetRowCellValue(i, "Units").ToString(),
                        gridView1.GetRowCellValue(i, "Remarks")?.ToString() ?? "",
                        Convert.ToDecimal(gridView1.GetRowCellValue(i, "SellingPrice")));
                }

                using (SqlConnection con = Database.getConnection())
                {
                    con.Open();
                    SqlCommand com = new SqlCommand("sp_AddSalesOrderRequest", con);
                    com.CommandType = CommandType.StoredProcedure;
                    com.Parameters.AddWithValue("@parmpono", textEdit1.Text);
                    com.Parameters.AddWithValue("@parmcustomerkey", objcustkey.ToString());
                    com.Parameters.AddWithValue("@parmbranchcode", Login.assignedBranch);
                    com.Parameters.AddWithValue("@parmeffectivitydate", Convert.ToDateTime(txteffectivedate.Text));
                    com.Parameters.AddWithValue("@parmrequestedby", Login.Fullname);
                    com.Parameters.AddWithValue("@parmnotes", txtnote.Text);
                    com.Parameters.AddWithValue("@parmordertype", ordertype.Text);
                    com.Parameters.AddWithValue("@parmpaymenttype", txtpaytype.Text);
                    var tvpParam = com.Parameters.AddWithValue("@Lines", lines);
                    tvpParam.SqlDbType = SqlDbType.Structured;
                    tvpParam.TypeName = "dbo.tt_PurchaseOrderLines";
                    com.ExecuteNonQuery();
                }

                table.Clear();
                gridControl1.DataSource = null;
                gridView1.Columns.Clear();

                XtraMessageBox.Show("Succesfully Saved");
              
                Isconnected = "OK";
                if(chckfinal.Checked.Equals(true))
                {
                    saveFinalSalesOrder();
                }
                this.Dispose();
            }
            catch (SqlException sqx)
            {
                XtraMessageBox.Show(sqx.Message.ToString());
            }
        }

        void saveFinalSalesOrder()
        {
            SqlConnection con = Database.getConnection();
            con.Open();
            try
            {
                string query = "spitcr_AddSalesOrderFinal";
                SqlCommand com = new SqlCommand(query, con);
                com.Parameters.AddWithValue("@parmpono",textEdit1.Text);
                com.Parameters.AddWithValue("@parmuser", Login.isglobalUserID);
                com.CommandType = CommandType.StoredProcedure;
                com.CommandText = query;
                com.ExecuteNonQuery();
            }
            catch(SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
            finally
            {
                con.Close();
            }
        }


        void saveAllServices()
        {
            try
            {
                if (panel1.Visible == true)
                {
                    if (txtcustomer.Enabled == true && txtcustomer.Text == "")
                    {
                        XtraMessageBox.Show("Customer Field must be Selected!");
                        return;
                    }
                }

                DataTable lines = new DataTable();
                lines.Columns.Add("ServiceCode", typeof(string));
                lines.Columns.Add("ServiceName", typeof(string));
                lines.Columns.Add("Qty", typeof(decimal));
                lines.Columns.Add("SellingPrice", typeof(decimal));

                for (int i = 0; i <= gridViewitem.RowCount - 1; i++)
                {
                    lines.Rows.Add(
                        gridViewitem.GetRowCellValue(i, "ServiceCode").ToString(),
                        gridViewitem.GetRowCellValue(i, "ServiceName").ToString(),
                        Convert.ToDecimal(gridViewitem.GetRowCellValue(i, "Qty")),
                        Convert.ToDecimal(gridViewitem.GetRowCellValue(i, "SellingPrice")));
                }

                using (SqlConnection con = Database.getConnection())
                {
                    con.Open();
                    SqlCommand com = new SqlCommand("sp_AddServiceOrderRequest", con);
                    com.CommandType = CommandType.StoredProcedure;
                    com.Parameters.AddWithValue("@SVCNumber", txtposervices.Text);
                    com.Parameters.AddWithValue("@CustomerKey", srvccustid.ToString());
                    com.Parameters.AddWithValue("@BranchCode", Login.assignedBranch);
                    com.Parameters.AddWithValue("@PaymentType", txtpaytypeservices.Text);
                    com.Parameters.AddWithValue("@RequestedBy", Login.Fullname);
                    var tvpParam = com.Parameters.AddWithValue("@Lines", lines);
                    tvpParam.SqlDbType = SqlDbType.Structured;
                    tvpParam.TypeName = "dbo.tt_ServiceOrderLines";
                    com.ExecuteNonQuery();
                }

                XtraMessageBox.Show("Request Successfully Updated!");

                serviceTable.Clear();
                gridControlitem.DataSource = null;
                gridViewitem.Columns.Clear();

                Isconnected = "OK";
                this.Dispose();
            }
            catch (SqlException sqx)
            {
                XtraMessageBox.Show(sqx.Message.ToString());
            }
        }


        private void clear()
        {
            txtqty.Text = "";
            txtpname.Text = "";
        }

        private void simpleButton3_Click(object sender, EventArgs e)
        {
            if (gridView1.RowCount ==0)
            {
                XtraMessageBox.Show("No Such Line to cancel!");
            }
            else
            {
               
                gridView1.DeleteSelectedRows();
            }
        }

        private void gridView1_KeyDown(object sender, KeyEventArgs e)
        {
         
        }

        private void AddOrder_FormClosing(object sender, FormClosingEventArgs e)
        {
            if (gridView1.RowCount == 0)
            {
                this.Dispose();
                this.Close();
            }
            else
            {
                bool ok = HelperFunction.ConfirmDialog("Are you sure you want to Force Close the form? \n Note: All Transactions will be cancelled", "Force Close");
                if (ok)
                {
                    //  Database.ExecuteQuery("DELETE FROM Inventory WHERE ReferenceCode='" + txtcarcasssku.Text + "'");
                    this.Dispose();
                    this.Close();
                }
                else
                {
                    e.Cancel = true;
                }
            }
            ///this.Close();
        }

        private void simpleButton4_Click(object sender, EventArgs e)
        {
            if (gridView1.RowCount == 0)
            {
                this.Dispose();
                this.Close();
            }
            else
            {
                bool ok = HelperFunction.ConfirmDialog("Are you sure you want to Force Close the form? \n Note: All Transactions will be cancelled", "Force Close");
                if (ok)
                {
                   this.Dispose();
                    this.Close();
                }
                
            }
        }

        private void txtprodcat_Click(object sender, EventArgs e)
        {
            //Database.displayComboBoxItems("SELECT Description FROM ProductCategory", "Description", txtprodcat);
        }

       
        private void txtprodname_SelectedIndexChanged(object sender, EventArgs e)
        {
            txtqty.Focus();
        }

        
       
        private void simpleButton6_Click(object sender, EventArgs e)
        {
       
            FolderBrowserDialog folder = new FolderBrowserDialog();
            try
            {
                if (folder.ShowDialog() == System.Windows.Forms.DialogResult.OK)
                {
                
                    Main main = new Main();
                    main.notifyIcon1.BalloonTipIcon = ToolTipIcon.Info;
                    main.notifyIcon1.BalloonTipTitle = "Successfully Exported";
                    main.notifyIcon1.BalloonTipText = "Your file successfully exported at " + folder.SelectedPath + "\\" +this.Text+ ".xls";
                    main.notifyIcon1.ShowBalloonTip(1000);
                }
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }

      
   
        private void btnitemcancel_Click(object sender, EventArgs e)
        {
            if (gridViewitem.RowCount == 0)
            {
                XtraMessageBox.Show("No Such Line to cancel!");
            }
            else
            {
                gridViewitem.DeleteSelectedRows();
            }
        }

        

        private void btnitemclose_Click(object sender, EventArgs e)
        {
            if (gridViewitem.RowCount == 0)
            {
                this.Dispose();
                this.Close();
            }
            else
            {
                bool ok = HelperFunction.ConfirmDialog("Are you sure you want to Force Close the form? \n Note: All Transactions will be cancelled", "Force Close");
                if (ok)
                {
                    this.Dispose();
                    this.Close();
                }

            }
        }

        private void btnitemexport_Click(object sender, EventArgs e)
        {
            FolderBrowserDialog folder = new FolderBrowserDialog();
            try
            {
                if (folder.ShowDialog() == System.Windows.Forms.DialogResult.OK)
                {
                    Main main = new Main();
                    main.notifyIcon1.BalloonTipIcon = ToolTipIcon.Info;
                    main.notifyIcon1.BalloonTipTitle = "Successfully Exported";
                    main.notifyIcon1.BalloonTipText = "Your file successfully exported at " + folder.SelectedPath + "\\" + this.Text + ".xls";
                    main.notifyIcon1.ShowBalloonTip(1000);
                }
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }

       
        private void simpleButton8_Click(object sender, EventArgs e)
        {
            textEdit1.Text = IDGenerator.getIDNumberSP("sp_GetPurchaseOrderNumber", "PONumber"); //IDGenerator.getPONumber();
            
            txtpname.Enabled = true;
            

            populateCustomer(txtcustomer);
            loadMetrics();

        }

        private void txtqty_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
                btnadd.PerformClick();
        }

        private void txtqty_KeyPress(object sender, KeyPressEventArgs e)
        {
            HelperFunction.isEnableAlphaWithDecimal(e);
        }

        private void txtpname_EditValueChanged(object sender, EventArgs e)
        {
            objprodcode = SearchLookUpClass.getSingleValue(txtpname, "ProductCode");
            objprodcatname = SearchLookUpClass.getSingleValue(txtpname, "ProductCategory");
            txtqty.Focus();
        }

        private void btnnew_Click(object sender, EventArgs e)
        {
            
            table = new DataTable();
            table.Columns.Add("ProductCode");
            table.Columns.Add("ProductName"); //UnitPrice
            table.Columns.Add("Qty"); //Total UnitPrice * weight
            table.Columns.Add("Units");
            table.Columns.Add("SellingPrice");
            table.Columns.Add("Remarks");
            gridControl1.DataSource = table;
            gridView1.BestFitColumns();

            textEdit1.Text = IDGenerator.getIDNumberSP("sp_GetPurchaseOrderNumber", "PONumber"); //IDGenerator.getPONumber();
           
            txtpname.Enabled = true;
            Database.displaySearchlookupEdit("SELECT ProductCategory,ProductCode,Description FROM view_Products WHERE BranchCode='" + Login.assignedBranch + "' ", txtpname, "Description", "Description");
            populateCustomer(txtcustomer);
            loadMetrics();
        }

        private void btnadd_Click(object sender, EventArgs e)
        {


            if (panel1.Visible == true && txtcustomer.Text == "")
            {
                XtraMessageBox.Show("Customer Name Must Not Empty");
                return;
            }

            if (txtqty.Text == "" || txtpname.Text.Trim() == "" || comboBox1.Text == "")
            {
                XtraMessageBox.Show("Fields must not Empty");
            }
             
            else
            {
                int count = 0;
                bool checkifexists = Database.checkifExist("SELECT TOP(1) PONumber FROM PurchaseOrderDetails WHERE PONumber='" + textEdit1.Text + "' AND ProductName='" + txtpname.Text.Trim() + "'");

                for (int i = 0; i <= gridView1.RowCount - 1; i++)
                {
                    if (gridView1.GetRowCellValue(i, "ProductName").ToString() == txtpname.Text.Trim())
                    {
                        //gridView1.SetRowCellValue(gridView1.FocusedRowHandle, "Qty", Convert.ToDouble(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "Qty").ToString()) + Convert.ToDouble(spinEdit1.Text));
                        count = 1;
                    }
                    else
                    {
                        count += 0;
                    }
                }
                if (count > 0)
                {
                    XtraMessageBox.Show("Product Already Exist");
                    return;
                }
                if (checkifexists)
                {
                    bool ok = HelperFunction.ConfirmDialog("Product is Already Exist!. Are you Sure you want to Continue?", "Product Exists");
                    if (ok)
                    {
                        add2();
                        // display();
                    }
                }

                else
                {
                    add2();
                    // display();
                }
            }
            txteffectivedate.Enabled = false;
            gridView1.MoveLast();
        }

        private void btnsave_Click(object sender, EventArgs e)
        {
            string creditlimit = Database.getSingleQuery("Customers", "CustomerName='" + txtcustomer.Text + "'", "CustomerCreditLimit");
            //string accountbalance = Database.getSingleQuery("ClientAccounts", "AccountID='" + Customers.getCustAccountID(txtcustomer.Text) + "'", "AccountBalance");
            string accountbalance = Database.getSingleQuery("ClientAccounts", "AccountKey='" + objcustkey.ToString() + "'", "AccountBalance");
            string enableCreditLimit = Database.getSingleQuery("SalesSettings", "EnableCreditLimit is not null", "EnableCreditLimit"); //temporary 0 no effect

            if (Convert.ToBoolean(enableCreditLimit) == true)
            {
                if (Convert.ToDouble(accountbalance) > Convert.ToDouble(creditlimit))
                {
                    XtraMessageBox.Show("Credit Limit Exceeded!...");
                    return;
                }
            }
            if (String.IsNullOrEmpty(ordertype.Text))
            {
                XtraMessageBox.Show("Please Select Order Type!");
                return;
            }
            if (String.IsNullOrEmpty(txtpaytype.Text))
            {
                XtraMessageBox.Show("Please Select Payment Type!");
                return;
            }
            if (gridView1.RowCount <= 0)
            {
                XtraMessageBox.Show("Please Input Product Details!");
                return;
            }
            else
            {
                saveAll();
                tot = 0;
            }
        }

        private void btncancel_Click(object sender, EventArgs e)
        {
            if (gridView1.RowCount == 0)
            {
                XtraMessageBox.Show("No Such Line to cancel!");
            }
            else
            {
                gridView1.DeleteSelectedRows();
                tot -= Convert.ToDecimal(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "Qty").ToString()) * Convert.ToDecimal(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SellingPrice").ToString());
            }
        }

        private void simpleButton9_Click(object sender, EventArgs e)
        {
            if (gridView1.RowCount == 0)
            {
                this.Dispose();
                this.Close();
            }
            else
            {
                bool ok = HelperFunction.ConfirmDialog("Are you sure you want to Force Close the form? \n Note: All Transactions will be cancelled", "Force Close");
                if (ok)
                {
                    
                    this.Dispose();
                    this.Close();
                }

            }
        }

        private void btnexport_Click(object sender, EventArgs e)
        {
           
            FolderBrowserDialog folder = new FolderBrowserDialog();
            try
            {
                if (folder.ShowDialog() == System.Windows.Forms.DialogResult.OK)
                {
                    
                    Main main = new Main();
                    main.notifyIcon1.BalloonTipIcon = ToolTipIcon.Info;
                    main.notifyIcon1.BalloonTipTitle = "Successfully Exported";
                    main.notifyIcon1.BalloonTipText = "Your file successfully exported at " + folder.SelectedPath + "\\" + this.Text + ".xls";
                    main.notifyIcon1.ShowBalloonTip(1000);
                }
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message.ToString());
            }
        }

        private void txtcustomer_EditValueChanged(object sender, EventArgs e)
        {
            objcustkey = SearchLookUpClass.getSingleValue(txtcustomer, "CustomerKey");
            objcreditmlimit = SearchLookUpClass.getSingleValue(txtcustomer, "CreditLimit");
            objbalance = SearchLookUpClass.getSingleValue(txtcustomer, "Balance");
            objremaininglimit = SearchLookUpClass.getSingleValue(txtcustomer, "RemainingLimit");
        }

        void populateServices()
        {
            Database.displaySearchlookupEdit("Select * FROM SERVICES",txtservices,"SRVC_DESC","SRVC_DESC");
        }
        private void btnnewservices_Click(object sender, EventArgs e)
        {
            serviceTable = new DataTable();
            serviceTable.Columns.Add("ServiceCode");
            serviceTable.Columns.Add("ServiceName"); //UnitPrice
            serviceTable.Columns.Add("Qty"); //Total UnitPrice * weight
            serviceTable.Columns.Add("SellingPrice");
            gridControlitem.DataSource = serviceTable;
            gridViewitem.BestFitColumns();

            txtposervices.Text = IDGenerator.getIDNumberSP("sp_GetPurchaseOrderNumber", "PONumber"); //IDGenerator.getPONumber();
            txtservices.Enabled = true;
            populateCustomer(txtcustomersservices);
            populateServices();
        }

        private void simpleButton5_Click(object sender, EventArgs e)
        {

 
            if (String.IsNullOrEmpty(txtqtyservices.Text)  || String.IsNullOrEmpty(txtcustomersservices.Text) || String.IsNullOrEmpty(txtpaytypeservices.Text))
            {
                XtraMessageBox.Show("Fields must not Empty");
            }
            
            else
            {
                int count = 0;
                bool checkifexists = Database.checkifExist("SELECT top 1 PONumber FROM PurchaseOrderDetails WHERE PONumber='" + txtposervices.Text + "' AND ProductName='" + txtservices.Text.Trim() + "'");

                for (int i = 0; i <= gridViewitem.RowCount - 1; i++)
                {
                    if (gridViewitem.GetRowCellValue(i, "ServiceName").ToString() == txtservices.Text.Trim())
                    {
                        //gridView1.SetRowCellValue(gridView1.FocusedRowHandle, "Qty", Convert.ToDouble(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "Qty").ToString()) + Convert.ToDouble(spinEdit1.Text));
                        count = 1;
                    }
                    else
                    {
                        count += 0;
                    }
                }
                if (count > 0)
                {
                    XtraMessageBox.Show("Services Already Exist");
                    return;
                }
                if (checkifexists)
                {
                    bool ok = HelperFunction.ConfirmDialog("Services is Already Exist!. Are you Sure you want to Continue?", "Services Exists");
                    if (ok)
                    {
                        addServices();
                        // display();
                    }
                }

                else
                {
                    addServices();
                    // display();
                }
            }
            gridViewitem.MoveLast();
        }

        private void txtservices_EditValueChanged(object sender, EventArgs e)
        {
            srvcid = SearchLookUpClass.getSingleValue(txtservices, "SRVC_ID");
        }

        double getCustBalance()
        {
            double balance = 0.0;
            balance = Database.getTotalSummation2("TransactionChargeSales", "CustomerKey='" + Classes.ClientAccount.getClientKey(srvccustid.ToString()) + "' AND PayStatus <> 'FULLYPAID' ", "Balance");
            return Math.Round(balance, 2);
        }

        private void simpleButton4_Click_1(object sender, EventArgs e)
        {
            string creditlimit = Database.getSingleQuery("Customers", "CustomerName='" + txtcustomersservices.Text + "'", "CustomerCreditLimit");
            string accountbalance = getCustBalance().ToString();
            string enableCreditLimit = Database.getSingleQuery("SalesSettings", "EnableCreditLimit is not null", "EnableCreditLimit");

            if (Convert.ToBoolean(enableCreditLimit) == true)
            {
                if (Convert.ToDouble(accountbalance) > Convert.ToDouble(creditlimit))
                {
                    XtraMessageBox.Show("Credit Limit Exceeded!...");
                    return;
                }
            }
           
            if (String.IsNullOrEmpty(txtpaytypeservices.Text))
            {
                XtraMessageBox.Show("Please Select Payment Type!");
                return;
            }
            if (gridViewitem.RowCount <= 0)
            {
                XtraMessageBox.Show("Please Input Product Details!");
                return;
            }
            else
            {
                saveAllServices();
            }
        }

        private void simpleButton3_Click_1(object sender, EventArgs e)
        {
            if (gridViewitem.RowCount == 0)
            {
                XtraMessageBox.Show("No Such Line to cancel!");
            }
            else
            {
                gridViewitem.DeleteSelectedRows();
            }
        }

        private void simpleButton2_Click_1(object sender, EventArgs e)
        {
            if (gridViewitem.RowCount == 0)
            {
                this.Dispose();
                this.Close();
            }
            else
            {
                bool ok = HelperFunction.ConfirmDialog("Are you sure you want to Force Close the form? \n Note: All Transactions will be cancelled", "Force Close");
                if (ok)
                {

                    this.Dispose();
                    this.Close();
                }

            }
        }

        private void gridViewitem_ShowingEditor(object sender, CancelEventArgs e)
        {
            GridView view = sender as GridView;
            if (view.FocusedColumn.FieldName != "SellingPrice" )
            {
                e.Cancel = true;
            }
        }

        private void txtqty_KeyDown_1(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
                btnadd.PerformClick();
        }

        private void txtcustomersservices_EditValueChanged(object sender, EventArgs e)
        {
            srvccustid = SearchLookUpClass.getSingleValue(txtcustomersservices, "CustomerKey");
        }
    }
}