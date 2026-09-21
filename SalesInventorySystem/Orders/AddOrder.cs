using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Text;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using System.Data.SqlClient;
using DevExpress.XtraGrid.Views.Grid;
using SalesInventorySystem.Classes;
//using Excel = Microsoft.Office.Interop.Excel;

namespace SalesInventorySystem
{
    public partial class AddOrder : DevExpress.XtraEditors.XtraForm
    { 
        
        object objprodcode = null;
        object objcustkey = null;
        object objcreditmlimit = null;
        object objbalance = null;
        object objremaininglimit = null;
        object srvcid = null,srvccustid=null;
        DataTable table;
        DataTable serviceTable;
        // Guards against re-allocating a real PO/SO number on a retried Save after a failed
        // insert -- once true for the current draft, saveAll()/saveAllServices() reuse the
        // already-allocated number instead of burning another one from the atomic counter.
        bool poNumberAllocated = false;
        bool soNumberAllocated = false;
        //string itemno,desc,unitprice,sellingprice,prodname;
        //string number;
        public static string Isconnected = "";
        string company = Database.getSingleQuery("CompanyProfile", "CompanyName <> ''", "CompanyName");
        decimal tot = 0m;
        public AddOrder()
        {
            InitializeComponent();

            // Database.displaySearchlookupEdit() rebinds Properties.DataSource at runtime
            // (populateCustomer(), called from LoadData()) without ever fitting the popup
            // grid's columns, so they render shrunk/cramped. BestFitColumns() has to run on
            // Popup (not right after binding) since the popup grid isn't sized yet at bind
            // time -- same pattern already used for repoaccountcode in AddExpenseDevExFrm.cs.
            // BestFitColumns() alone wasn't enough here: txtcustomer itself is only 192px wide
            // (see Designer.cs), and a SearchLookUpEdit's popup defaults to roughly the
            // editor's own width -- so best-fit columns were computed correctly, then squeezed
            // straight back down to fit that narrow popup. PopupFormMinSize forces the popup
            // itself to open wide enough first.
            txtcustomer.Properties.PopupFormMinSize = new Size(500, 300);
            txtcustomer.Popup += (s, e) => txtcustomer.Properties.View.BestFitColumns();
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
                if (objprodcode == null || objprodcode == DBNull.Value)
                {
                    XtraMessageBox.Show("Please re-select the product from the list before adding.");
                    return;
                }

                if (objcustkey == null || objcustkey == DBNull.Value)
                {
                    XtraMessageBox.Show("Please re-select the customer before adding.");
                    return;
                }

                //var row = Database.getMultipleQuery("Customers", "CustomerName='" + txtcustomer.Text + "'", "CustomerID,isActive,CustomerCreditLimit");
                string custid =  objcustkey.ToString();
                string remaininglimit = objremaininglimit?.ToString() ?? "0";

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

        private void AddOrder_Load(object sender, EventArgs e)
        {
            comboBox1.Text = "Kg";
            panel1.Visible = true;
            checkBox1.Visible = true;
            chckspecialprice.Visible = true;

            // Guarded fallback -- table is only non-null once LoadData() has actually run.
            if (table == null)
            {
                LoadData();
            }
        }

        // Real init entry point for the Products tab: fresh line-item table, new PO#, and the
        // customer/product/metric lookups populated. Called on first Load and again every time
        // "New" is clicked to start a fresh order.
        void LoadData()
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

            // Display-only preview -- does not consume the counter. The real number is
            // allocated atomically (sp_GetPurchaseOrderNumber) once, in saveAll(), at Save time.
            textEdit1.Text = IDGenerator.getIDNumberSP("sp_PeekPurchaseOrderNumber", "PONumber");
            poNumberAllocated = false;

            txtpname.Enabled = true;
            Database.displaySearchlookupEdit("SELECT ProductCategory,ProductCode,Description FROM view_Products WHERE BranchCode='" + Login.assignedBranch + "' ", txtpname, "Description", "ProductCode");
            populateCustomer(txtcustomer);
            loadMetrics();
        }


        void loadMetrics()
        { 
            Database.displayDevComboBoxItems("SELECT * FROM Metrics", "Metrics", comboBox1);
        }
      

        void populateCustomer(SearchLookUpEdit edit)
        {
            //Database.displayComboBoxItems("SELECT CustomerName FROM Customers", "CustomerName", txtcustomer);
            // ValueMember was "CustomerName" (same as DisplayMember), so EditValue could never be
            // used as a real key -- callers had to chase the popup grid's FocusedRowHandle instead
            // (see txtcustomer_EditValueChanged), which is what caused the intermittent
            // "Object reference not set to an instance of an object" on Add. Bound to the real
            // CustomerKey now; DisplayMember (and therefore .Text) is unchanged.
            Database.displaySearchlookupEdit($"Select * FROM [funcview_CustomerWithCreditLimit]('{Login.assignedBranch}')", edit, "CustomerName", "CustomerKey");
        }
        
        void saveAll()
        {
            try
            {
                if (panel1.Visible == true)
                {
                    if (txtcustomer.Enabled == true && txtcustomer.Text == "")
                    {
                        BigAlert.Show("SELECT CUSTOMER","Customer Field must be Selected!",MessageBoxIcon.Warning);
                        return;
                    }

                    // txtcustomer.Text (the displayed name) can be non-empty while objcustkey is
                    // still null/stale -- see txtcustomer_EditValueChanged. Catch that here too
                    // instead of letting objcustkey.ToString() below throw.
                    if (objcustkey == null || objcustkey == DBNull.Value)
                    {
                        BigAlert.Show("EMPTY","Please re-select the customer before submitting.", MessageBoxIcon.Warning);
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

                // Allocate the real, final PO number now -- textEdit1.Text so far only held the
                // non-consuming preview from LoadData(); saveFinalSalesOrder() below reads the
                // same field, so it picks up this real number too. Guarded so a retried Save
                // after a failed insert reuses this draft's already-allocated number instead of
                // burning another one.
                if (!poNumberAllocated)
                {
                    textEdit1.Text = IDGenerator.getIDNumberSP("sp_GetPurchaseOrderNumber", "PONumber");
                    poNumberAllocated = true;
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

                BigAlert.Show("SUCESS","Succesfully Saved", MessageBoxIcon.Information);
              
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
                    // NOTE: this checks txtcustomer.Text (the main-tab customer field), but the
                    // @CustomerKey sent below is srvccustid, which comes from txtcustomersservices
                    // (a separate control on the Services tab). Left as-is rather than silently
                    // changed -- flagging in case this mismatch is intentional; if not, this check
                    // should probably read txtcustomersservices.Text instead.
                    if (txtcustomer.Enabled == true && txtcustomer.Text == "")
                    {
                        XtraMessageBox.Show("Customer Field must be Selected!");
                        return;
                    }

                    if (srvccustid == null || srvccustid == DBNull.Value)
                    {
                        XtraMessageBox.Show("Please re-select the customer before submitting.");
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

                // Allocate the real, final Service Order number now -- txtposervices.Text so far
                // only held the non-consuming preview from btnnewservices_Click(). Guarded so a
                // retried Save after a failed insert reuses this draft's already-allocated
                // number instead of burning another one.
                if (!soNumberAllocated)
                {
                    txtposervices.Text = IDGenerator.getIDNumberSP("sp_GetServiceOrderNumber", "SONumber");
                    soNumberAllocated = true;
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
                    com.Parameters.AddWithValue("@EffectivityDate", txteffectivitydateservices.Text);
                    com.Parameters.AddWithValue("@ControlNo", txtcontrolno.Text);
                    var tvpParam = com.Parameters.AddWithValue("@Lines", lines);
                    tvpParam.SqlDbType = SqlDbType.Structured;
                    tvpParam.TypeName = "dbo.tt_ServiceOrderLines";
                    com.ExecuteNonQuery();
                }

                BigAlert.Show("SUCCESS","Request Successfully Added!",MessageBoxIcon.Warning);

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
            // Was: SearchLookUpClass.getSingleValue(txtpname, "ProductCode"), which reads the popup
            // grid's FocusedRowHandle instead of the control's committed value -- goes stale/null
            // right after txtpname.Text is cleared (line ~306) or during incremental search, causing
            // "Object reference not set to an instance of an object" at add2() (was line 197).
            // ValueMember is now bound to ProductCode (see LoadData()), so EditValue is reliable.
            objprodcode = txtpname.EditValue;
            txtqty.Focus();
        }

        private void btnnew_Click(object sender, EventArgs e)
        {
            LoadData();
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
                // Removed dead PurchaseOrderDetails.PONumber existence trap: textEdit1.Text here
                // is always the peeked (sp_PeekPurchaseOrderNumber), not-yet-allocated PONumber --
                // rows for it are only inserted at Save via sp_AddSalesOrderRequest, and this form
                // has no "reopen an existing PONumber" flow, so it can never already be in the
                // table. Also fixes a duplicate-add bug: add2() used to run once inside the
                // if/else below AND unconditionally again after it, double-adding every line.
                int count = 0;
                for (int i = 0; i <= gridView1.RowCount - 1; i++)
                {
                    if (gridView1.GetRowCellValue(i, "ProductName").ToString() == txtpname.Text.Trim())
                    {
                        count = 1;
                    }
                }
                if (count > 0)
                {
                    XtraMessageBox.Show("Product Already Exist");
                    return;
                }
                add2();
            }
            txteffectivedate.Enabled = true;
            gridView1.MoveLast();
        }

        private void btnsave_Click(object sender, EventArgs e)
        {
            // objcustkey can be null/stale here (see txtcustomer_EditValueChanged) if the customer
            // lookup never committed -- guard before .ToString() below throws on Save/F5.
            if (panel1.Visible == true && (objcustkey == null || objcustkey == DBNull.Value))
            {
                XtraMessageBox.Show("Please re-select the customer before saving.");
                return;
            }

            string creditlimit = Database.getSingleQuery("Customers", "CustomerName='" + txtcustomer.Text + "'", "CustomerCreditLimit");
            //string accountbalance = Database.getSingleQuery("ClientAccounts", "AccountID='" + Customers.getCustAccountID(txtcustomer.Text) + "'", "AccountBalance");
            string accountbalance = Database.getSingleQuery("ClientAccounts", "AccountKey='" + objcustkey.ToString() + "'", "AccountBalance");
            string enableCreditLimit = Database.getSingleQuery("SalesSettings", "EnableCreditLimit is not null", "EnableCreditLimit"); //temporary 0 no effect

            //if (Convert.ToBoolean(enableCreditLimit) == true)
            //{
            //    if (Convert.ToDouble(accountbalance) > Convert.ToDouble(creditlimit))
            //    {
            //        XtraMessageBox.Show("Credit Limit Exceeded!...");
            //        return;
            //    }
            //}
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
            var selected = gridView1.GetSelectedRows();
            if (selected == null || selected.Length == 0)
            {
                XtraMessageBox.Show("No Such Line to cancel!");
                return;
            }

            decimal delta = 0m;
            foreach (int handle in selected)
            {
                if (handle < 0) continue; // skip invalid handles
                object qtyObj = gridView1.GetRowCellValue(handle, "Qty");
                object priceObj = gridView1.GetRowCellValue(handle, "SellingPrice");

                if (qtyObj == null || priceObj == null || qtyObj == DBNull.Value || priceObj == DBNull.Value)
                    continue;

                if (decimal.TryParse(qtyObj.ToString(), out decimal qty) &&
                    decimal.TryParse(priceObj.ToString(), out decimal price))
                {
                    delta += qty * price;
                }
            }

            gridView1.DeleteSelectedRows();
            tot -= delta;
            //if (gridView1.RowCount == 0)
            //{
            //    XtraMessageBox.Show("No Such Line to cancel!");
            //}
            //else
            //{
            //    gridView1.DeleteSelectedRows();
            //    tot -= Convert.ToDecimal(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "Qty").ToString()) * Convert.ToDecimal(gridView1.GetRowCellValue(gridView1.FocusedRowHandle, "SellingPrice").ToString());
            //}
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
            // Was: SearchLookUpClass.getSingleValue(txtcustomer, "..."), which reads the popup
            // grid's FocusedRowHandle instead of the control's committed value -- desyncs (goes
            // stale/invalid) during incremental search or right after the form resets the field,
            // causing "Object reference not set to an instance of an object" wherever objcustkey
            // is later .ToString()'d in add2()/saveAll(). ValueMember is now bound to CustomerKey
            // (see populateCustomer()), so EditValue is reliable; the other three fields are looked
            // up from the already-loaded customer DataTable by that key instead of a focused row.
            objcustkey = txtcustomer.EditValue;
            objcreditmlimit = null;
            objbalance = null;
            objremaininglimit = null;

            DataRow row = FindLookupRow(txtcustomer, "CustomerKey", objcustkey);
            if (row != null)
            {
                objcreditmlimit = row["CreditLimit"];
                objbalance = row["Balance"];
                objremaininglimit = row["RemainingLimit"];
            }
        }

        // Looks up a row in a SearchLookUpEdit's own bound DataTable by key column/value --
        // deterministic, unlike reading the popup grid's FocusedRowHandle (see note above).
        static DataRow FindLookupRow(SearchLookUpEdit edit, string keyColumn, object keyValue)
        {
            if (keyValue == null || keyValue == DBNull.Value)
                return null;

            if (!(edit.Properties.DataSource is DataTable table))
                return null;

            string escaped = keyValue.ToString().Replace("'", "''");
            DataRow[] rows = table.Select($"{keyColumn} = '{escaped}'");
            return rows.Length > 0 ? rows[0] : null;
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

            // Display-only preview from its own counter (sonumber) -- Services no longer shares
            // the Products PO sequence. Real number is allocated atomically in saveAllServices().
            txtposervices.Text = IDGenerator.getIDNumberSP("sp_PeekServiceOrderNumber", "SONumber");
            soNumberAllocated = false;
            txtservices.Enabled = true;
            populateCustomer(txtcustomersservices);
            populateServices();
        }

        private void simpleButton5_Click(object sender, EventArgs e)
        {

 
            if (String.IsNullOrEmpty(txtqtyservices.Text)  || String.IsNullOrEmpty(txtcustomersservices.Text) || String.IsNullOrEmpty(txtpaytypeservices.Text) || String.IsNullOrEmpty(txteffectivitydateservices.Text))
            {
                XtraMessageBox.Show("Fields must not Empty");
            }
            
            else
            {
                int count = 0;
                bool checkifexists = Database.checkifExist("SELECT TOP(1) PONumber FROM PurchaseOrderDetails WHERE PONumber='" + txtposervices.Text + "' AND ProductName='" + txtservices.Text.Trim() + "'");

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
            if (srvccustid == null || srvccustid == DBNull.Value)
                return 0.0;

            double balance = Database.getTotalSummation2("TransactionChargeSales", "CustomerKey='" + Classes.ClientAccount.getClientKey(srvccustid.ToString()) + "' AND PayStatus <> 'FULLYPAID' ", "Balance");
            return Math.Round(balance, 2);
        }

        private void simpleButton4_Click_1(object sender, EventArgs e)
        {
            if (srvccustid == null || srvccustid == DBNull.Value)
            {
                XtraMessageBox.Show("Please re-select the customer before checking credit limit.");
                return;
            }

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
            // Same FocusedRowHandle desync issue as txtcustomer_EditValueChanged -- see its comment.
            srvccustid = txtcustomersservices.EditValue;
        }
    }
}