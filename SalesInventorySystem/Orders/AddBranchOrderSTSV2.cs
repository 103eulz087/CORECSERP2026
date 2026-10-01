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
using DevExpress.XtraGrid.Views.Grid;
using DevExpress.XtraGrid.Columns;
using System.IO.Ports;
using System.Data.SqlClient;
using DevExpress.XtraReports.UI;
using DevExpress.XtraGrid;
using SalesInventorySystem.Classes;
using DevExpress.XtraRichEdit.Commands;

namespace SalesInventorySystem.Orders
{
    // STS V2 (2026-09-29) -- a copy of AddBranchOrderSTS moved onto the
    // standard FIFO engine (docs/standards/2026-09-29_Inventory_FIFO_Deduction_Standard.md,
    // SQL/2026-09-29b_InvFIFO_Engine.sql + 2026-09-29c_STS_V2_FIFOEngine.sql).
    // The original form and its procs are untouched; this one is opened from
    // ViewBranchOrderSTS > Process this Order > "FIFO V2 (Test)" (admins only).
    //
    // Same workflow as the original: every scan / pick is posted straight
    // away as one PENDING line (Save as Draft / resume and Save (Confirm)
    // work as before), but each post is now ONE atomic call to
    // spu_PostSTSLineV2 for every company:
    //   Scan Barcode            -> SCAN  (that lot; partial qty allowed)
    //   FIFO Auto (By Sequence) -> AUTO  (oldest warehouse lots; combos expand)
    //   FIFO Manual (By Shipment)-> BATCH (Product||ShipmentNo||ReferenceCode)
    // Cancel Line -> spu_ReverseSTSLineV2 (restores exactly the lots the line took).
    public partial class AddBranchOrderSTSV2 : DevExpress.XtraEditors.XtraForm
    {
        public delegate void AddDataDelegate(String myString);
        public AddDataDelegate myDelegate;
        object pcode,catcode, referencecode, shipmentno;
        // Scan-with-partial-qty: the lot scanned last, waiting for a qty + Add.
        string _scannedBarcode = null;
        decimal _scannedAvailable = 0m;
        const string FifoAuto = "AUTO", FifoManual = "MANUAL";
        private String weight;
        public string wieght2 = "";
        public static bool isdone = false, ispending = false;
        string productcategorycode = "";
        string globaltxtbarcodescanning = "", globalproductcode = "";
        bool isFifo = Database.checkifExist("SELECT isFifo FROM InventorySettings WHERE isFifo=1");
        bool isusedSearch = false;

       
       
        public AddBranchOrderSTSV2()
        {         
            this.myDelegate = new AddDataDelegate(AddDataMethod);
            InitializeComponent();
            HelperFunction.AllowNumbersAndPeriodDevEx(txtweight);
        }
        public void AddDataMethod(String myString)
        {
            txtweight.Text += myString;
        }
        private void AddBranchOrderSTS_Load(object sender, EventArgs e)
        {
            getAvailablePort();

            //if (isFifo == true)
            //{
            //    barcodescanning.Checked = false;
            //    panel1.Visible = false;
            //    panel2.Visible = false;
            //    panel3.Visible = false;
            //    panel4.Visible = true;
            //}
            //else
            //{
            //    barcodescanning.Checked = true;
            //    panel1.Visible = true;

            //}
            barcodescanning.Checked = true;
            panel1.Visible = true;
            txtbarcodescanning.Focus();
            Database.displayComboBoxItems("SELECT Description FROM ProductCategory", "Description", txtprodcat);

            // The opener (ViewBranchOrderSTS.openBranchOrderV2) already resolved
            // the Delivery No. before LoadData(); only fall back here if it didn't.
            if (string.IsNullOrWhiteSpace(txtdevno.Text))
                txtdevno.Text = ResolveDeliveryNo(ViewBranchOrderSTS.ponumber);

            txtcomport.Focus();

            //txtbrcode.Text = ViewBranchOrder.branchno;
            //txtponum.Text = ViewBranchOrder.ponumber;
            //txtrefno.Text = IDGenerator.getReferenceNumber();
            //txteffectivedate.Text = ViewBranchOrder.effectivedate;

            GridView view = gridControl1.FocusedView as GridView;
            view.SortInfo.ClearAndAddRange(new GridColumnSortInfo[] {
                new GridColumnSortInfo(view.Columns["Category"],DevExpress.Data.ColumnSortOrder.Ascending)
                }, 1);

            // Guarded fallback only (Known Bug Pattern #1): the opener normally
            // calls LoadData() before ShowDialog.
            if (!_dataLoaded) LoadData();
        }
        // The PO's open delivery (same rule as the original form: reuse the
        // DeliveryNo already started for this PO, else take a new number).
        public static string ResolveDeliveryNo(string poNumber)
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("SELECT TOP (1) DeliveryNo FROM dbo.DeliverySummary WHERE PONumber = @PONumber", con))
            {
                cmd.Parameters.Add("@PONumber", SqlDbType.VarChar, 20).Value = poNumber ?? "";
                con.Open();
                object existing = cmd.ExecuteScalar();
                if (existing != null && existing != DBNull.Value && !string.IsNullOrWhiteSpace(existing.ToString()))
                    return existing.ToString();
            }
            return IDGenerator.getIDNumberSP("sp_GetDeliveryNumber", "DeliveryNumber");
        }

        // Real init entry point (CLAUDE.md Known Bug Pattern #1): the opener
        // calls this after setting txtbrcode/txtponum/txtdevno/txtrefno and
        // before ShowDialog, so everything here sees the order's values.
        bool _dataLoaded = false;

        public void LoadData()
        {
            if (_dataLoaded) return;
            _dataLoaded = true;
            this.Text = (string.IsNullOrWhiteSpace(this.Text) ? "STS" : this.Text) + "  [FIFO V2 - TEST]";
            // JFC picks a specific batch; other companies take any warehouse lot.
            // Setting EditValue fires rdoFifoType_SelectedIndexChanged -> LoadProductLookup().
            string defaultType = GlobalCache.CompanyName == "JFC" ? FifoManual : FifoAuto;
            if (Equals(rdoFifoType.EditValue, defaultType)) LoadProductLookup();
            else rdoFifoType.EditValue = defaultType;
            displayForDelivery();
        }

        bool IsManualFifo => Equals(rdoFifoType.EditValue, FifoManual);

        private void rdoFifoType_SelectedIndexChanged(object sender, EventArgs e)
        {
            LoadProductLookup();
        }

        // FIFO Auto: one row per requested product (ValueMember ProductCode).
        // FIFO Manual: one row per batch (ValueMember LotKey =
        // Product||ShipmentNo||ReferenceCode -- Known Bug Pattern #7).
        // TextEditStyle = DisableTextEditor is set in the designer (Pattern #2).
        void LoadProductLookup()
        {
            string fn = IsManualFifo ? "dbo.funcview_STSV2_ProductLots" : "dbo.funcview_STSV2_Products";
            var dt = new DataTable();
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("SELECT * FROM " + fn + "(@OriginBranch, @PONumber) ORDER BY ProductCode", con))
                {
                    cmd.Parameters.Add("@OriginBranch", SqlDbType.VarChar, 5).Value = Login.assignedBranch ?? "";
                    cmd.Parameters.Add("@PONumber", SqlDbType.VarChar, 10).Value = txtponum.Text.Trim();
                    using (var da = new SqlDataAdapter(cmd))
                        da.Fill(dt);
                }
            }
            catch (SqlException ex)
            {
                BigAlert.Show("PRODUCT LIST ERROR", ex.Message, MessageBoxIcon.Error);
                return;
            }

            txtsearchlookupproduct.EditValue = null;
            if (!barcodescanning.Checked) txtsku.Text = "";   // sticker barcode belonged to the previous pick
            txtsearchlookupproduct.Properties.DataSource = dt;
            txtsearchlookupproduct.Properties.DisplayMember = "DisplayText";
            txtsearchlookupproduct.Properties.ValueMember = IsManualFifo ? "LotKey" : "ProductCode";

            GridView v = txtsearchlookupproduct.Properties.View;
            v.PopulateColumns(dt);
            foreach (string hide in new[] { "LotKey", "DisplayText", "OldestReceived" })
                if (v.Columns[hide] != null) v.Columns[hide].Visible = false;
            FormatNumeric(v, "Available", "N3");
            v.BestFitColumns();

            pcode = null; catcode = null; referencecode = null; shipmentno = null;
        }

        // One atomic post: SCAN / AUTO / BATCH. Returns false (after telling
        // the user) when the proc rejects it -- nothing was posted then.
        bool PostLine(string method, decimal qty, string barcode, string productCode, string shipment, string reference)
        {
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("dbo.spu_PostSTSLineV2", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 120;
                    cmd.Parameters.Add("@DeliveryNo", SqlDbType.VarChar, 20).Value = txtdevno.Text.Trim();
                    cmd.Parameters.Add("@RefNo", SqlDbType.VarChar, 10).Value = txtrefno.Text.Trim();
                    cmd.Parameters.Add("@PONumber", SqlDbType.VarChar, 10).Value = txtponum.Text.Trim();
                    cmd.Parameters.Add("@DestinationBranch", SqlDbType.VarChar, 10).Value = txtbrcode.Text.Trim();
                    cmd.Parameters.Add("@OriginBranch", SqlDbType.VarChar, 10).Value = Login.assignedBranch ?? "";
                    cmd.Parameters.Add("@PreparedBy", SqlDbType.VarChar, 30).Value = Login.Fullname ?? "";
                    cmd.Parameters.Add("@Method", SqlDbType.VarChar, 5).Value = method;
                    var pQty = cmd.Parameters.Add("@Qty", SqlDbType.Decimal);
                    pQty.Precision = 18; pQty.Scale = 3; pQty.Value = qty;
                    cmd.Parameters.Add("@ProductCode", SqlDbType.VarChar, 10).Value = string.IsNullOrWhiteSpace(productCode) ? (object)DBNull.Value : productCode;
                    cmd.Parameters.Add("@Barcode", SqlDbType.VarChar, 100).Value = string.IsNullOrWhiteSpace(barcode) ? (object)DBNull.Value : barcode;
                    cmd.Parameters.Add("@ShipmentNo", SqlDbType.VarChar, 10).Value = shipment == null ? (object)DBNull.Value : shipment;
                    cmd.Parameters.Add("@ReferenceCode", SqlDbType.VarChar, 100).Value = reference == null ? (object)DBNull.Value : reference;

                    con.Open();
                    cmd.ExecuteNonQuery();
                }
            }
            catch (SqlException ex)
            {
                BigAlert.Show("NOT POSTED", ex.Message, MessageBoxIcon.Warning);
                return false;
            }

            displayForDelivery();
            return true;
        }

        static void FormatNumeric(GridView v, string field, string format)
        {
            if (v.Columns[field] == null) return;
            v.Columns[field].DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            v.Columns[field].DisplayFormat.FormatString = format;
        }

        static bool TryParseQty(string text, out decimal qty)
        {
            return decimal.TryParse((text ?? "").Trim(), System.Globalization.NumberStyles.Number,
                                    System.Globalization.CultureInfo.CurrentCulture, out qty) && qty > 0;
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            bool functionReturnValue = false;
            if (keyData == Keys.F10)
            {
                simpleButton11.PerformClick();
            }
            else if (keyData == Keys.F6)
            {
                simpleButton9.PerformClick();
            }
            else if (keyData == Keys.F8)
            {
                simpleButton10.PerformClick();
            }
            if (keyData == Keys.F1)
            {
                btnfind.PerformClick();
            }
            if (keyData == Keys.F5)
            {
                btnchecker.PerformClick();
            }
            return functionReturnValue;
        }

        private void txtsku_KeyDown(object sender, KeyEventArgs e)
        {
            // (the original ran an unused, string-built DeliveryDetails lookup on every key press)
            if (e.KeyCode == Keys.Enter)
            {
                btnadd.PerformClick();
            }
            else if (e.KeyCode == Keys.F10)
            {
                simpleButton2.PerformClick();
            }
        }

        /*****************************************NEW*****************************/
        private void getAvailablePort()
        {
            string[] ports = SerialPort.GetPortNames();
            txtcomport.Properties.Items.AddRange(ports);
        }

        void displayComboBoxItems()
        {
            Database.displayComboBoxItems("SELECT * FROM Products WHERE BranchCode='888' ORDER BY Description", "Description", txtproduct);
            Database.displayComboBoxItems("SELECT Description FROM ProductCategory", "Description", txtprodcat);
        }

        /*****************************************NEW*****************************/
        private void displayForDelivery()
        {
            gridControl2.BeginUpdate();
            //     Database.display("SELECT QtyDelivered,BarcodeNo,ProductNo,ProductName,FORMAT(Cost,'N','en-us')AS Cost,SequenceNo FROM DeliveryDetails WHERE DeliveryNo='" + txtdevno.Text + "'", gridControl2, gridView2);

            // One row per delivery line (the unit Cancel Line acts on), for every
            // company -- scoped by DeliveryNo AND PONumber.
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("SELECT * FROM dbo.funcview_STSV2_DeliveryLines(@DeliveryNo, @PONumber) ORDER BY SeqNo DESC", con))
            {
                cmd.Parameters.Add("@DeliveryNo", SqlDbType.VarChar, 20).Value = txtdevno.Text.Trim();
                cmd.Parameters.Add("@PONumber", SqlDbType.VarChar, 10).Value = txtponum.Text.Trim();
                Database.display(cmd, gridControl2, gridView2);
            }
            FormatNumeric(gridView2, "QtyDelivered", "N3");
            FormatNumeric(gridView2, "TotalCost", "N2");


            //Database.display("SELECT SeqNo,ProductNo,ProductName,BarcodeNo,QtyDelivered " +
            //    "FROM dbo.DeliveryDetails with(nolock) WHERE PONumber='"+txtponum.Text+"' AND DeliveryNo='" + txtdevno.Text + "' AND Status='PENDING' ORDER BY SeqNo DESC", gridControl2, gridView2);

            //gridView2.Columns[0].Visible = false;

            //GridView view = gridControl2.FocusedView as GridView;
            //view.SortInfo.ClearAndAddRange(new GridColumnSortInfo[] {
            //    new GridColumnSortInfo(view.Columns["ProductName"],DevExpress.Data.ColumnSortOrder.Ascending)
            //    }, 1); 
            //gridView2.ExpandAllGroups();


            //GridGroupSummaryItem itez = new GridGroupSummaryItem();
            //itez.FieldName = "ProductNo";
            //itez.SummaryType = DevExpress.Data.SummaryItemType.Count;
            //itez.ShowInGroupColumnFooter = gridView2.Columns["ProductNo"];
            //gridView2.GroupSummary.Add(itez);
            //gridView2.Focus();

            //GridGroupSummaryItem ite = new GridGroupSummaryItem();
            //ite.FieldName = "QtyDelivered";
            //ite.SummaryType = DevExpress.Data.SummaryItemType.Sum;
            //ite.ShowInGroupColumnFooter = gridView2.Columns["QtyDelivered"];
            //gridView2.GroupSummary.Add(ite);
            //gridView2.Focus();


            gridView2.Columns["ProductNo"].Summary.Clear();
            gridView2.Columns["ProductNo"].Summary.Add(DevExpress.Data.SummaryItemType.Count, "ProductNo", "{0:n2}");
            gridView2.Columns["QtyDelivered"].Summary.Clear();
            gridView2.Columns["QtyDelivered"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "QtyDelivered", "{0:n2}");
            gridControl2.EndUpdate();
        }

        private void simpleButton2_Click(object sender, EventArgs e)
        {
            if (gridView2.RowCount == 0)
            {
                XtraMessageBox.Show("Cant Save no Order to be Processed!");
                return;
            }

            if (!HelperFunction.ConfirmDialog("Are you sure all order has been Processed?", "Save Transaction"))
                return;

            if (!ConfirmBranchOrder())
                return;
            isdone = true;
            XtraMessageBox.Show("Transaction Successfully Saved!");
            this.Close();
        }

        private void txtsku_KeyPress(object sender, KeyPressEventArgs e)
        {
            if (!char.IsControl(e.KeyChar) && !char.IsDigit(e.KeyChar))
            {
                e.Handled = true;
            }
        }

        // Unchanged proc (sp_ConfirmBranchOrderSTS) -- V2 writes the same STS
        // rows, verified on DEV. Returns false when it failed: the original
        // swallowed the error and the caller still showed "SUCCESS".
        bool ConfirmBranchOrder()
        {
            try
            {
                using (var con = Database.getConnection())
                using (var com = new SqlCommand("dbo.sp_ConfirmBranchOrderSTS", con))
                {
                    com.CommandType = CommandType.StoredProcedure;
                    com.CommandTimeout = 180;
                    com.Parameters.Add("@parmdevno", SqlDbType.VarChar, 20).Value = txtdevno.Text.Trim();
                    com.Parameters.Add("@parmrefno", SqlDbType.VarChar, 10).Value = txtrefno.Text.Trim();
                    // The proc re-reads EffectivityDate from TransferOrderSummary; this is only its fallback.
                    DateTime eff;
                    com.Parameters.Add("@parmeffectivitydate", SqlDbType.Date).Value =
                        DateTime.TryParse(txteffectivedate.Text, out eff) ? (object)eff.Date : DBNull.Value;
                    com.Parameters.Add("@parmpono", SqlDbType.VarChar, 10).Value = txtponum.Text.Trim();
                    com.Parameters.Add("@parmbarcode", SqlDbType.VarChar, 50).Value = txtsku.Text;
                    com.Parameters.Add("@parmbranchcode", SqlDbType.VarChar, 10).Value = txtbrcode.Text.Trim();
                    com.Parameters.Add("@parmorigin", SqlDbType.VarChar, 10).Value = Login.assignedBranch ?? "";
                    com.Parameters.Add("@preparedby", SqlDbType.VarChar, 30).Value = Login.Fullname ?? "";
                    con.Open();
                    com.ExecuteNonQuery();
                }
                return true;
            }
            catch (SqlException ex)
            {
                BigAlert.Show("NOT SAVED", ex.Message, MessageBoxIcon.Error);
                return false;
            }
        }

        // Cancel Line: restores exactly the lots/qty this line took
        // (spu_ReverseSTSLineV2). If the transfer was already saved, the proc
        // also brings In Transit back in line with the remaining lots
        // (spu_STS_SyncInTransit, 2026-10-01f). Works on lines posted by the original form too.
        void ReturnLine()
        {
            if (gridView2.FocusedRowHandle < 0 || !gridView2.IsDataRow(gridView2.FocusedRowHandle))
            {
                BigAlert.Show("NO LINE SELECTED", "Select the line to cancel first.", MessageBoxIcon.Warning);
                return;
            }

            object seqObj = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "SeqNo");
            int seqNo;
            if (seqObj == null || seqObj == DBNull.Value || !int.TryParse(seqObj.ToString(), out seqNo))
            {
                BigAlert.Show("NO LINE SELECTED", "The selected row has no line number.", MessageBoxIcon.Warning);
                return;
            }

            string product = Convert.ToString(gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "ProductName"));
            decimal qty = Convert.ToDecimal(gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "QtyDelivered") ?? 0m);
            if (!HelperFunction.ConfirmDialog($"Cancel line {seqNo} ({product}, {qty:N3}) and put the stock back?", "Cancel Line"))
                return;

            try
            {
                using (var con = Database.getConnection())
                using (var com = new SqlCommand("dbo.spu_ReverseSTSLineV2", con))
                {
                    com.CommandType = CommandType.StoredProcedure;
                    com.CommandTimeout = 120;
                    com.Parameters.Add("@DeliveryNo", SqlDbType.VarChar, 20).Value = txtdevno.Text.Trim();
                    com.Parameters.Add("@PONumber", SqlDbType.VarChar, 10).Value = txtponum.Text.Trim();
                    com.Parameters.Add("@SeqNo", SqlDbType.Int).Value = seqNo;
                    com.Parameters.Add("@OriginBranch", SqlDbType.VarChar, 10).Value = Login.assignedBranch ?? "";
                    com.Parameters.Add("@PreparedBy", SqlDbType.VarChar, 30).Value = Login.Fullname ?? "";
                    con.Open();
                    com.ExecuteNonQuery();
                }
                BigAlert.Show("LINE CANCELLED", "The line was cancelled and its stock restored.", MessageBoxIcon.Information);
            }
            catch (SqlException ex)
            {
                BigAlert.Show("NOT CANCELLED", ex.Message, MessageBoxIcon.Warning);
            }
        }
        String getProductCategoryCode()
        {
            string str;
            if (isusedSearch == true)
            {
                str = productcategorycode;
            }
            else
            {
                str = Database.getSingleQuery("ProductCategory", "Description='" + txtprodcat.Text.Trim() + "'", "ProductCategoryID");
            }
            return str;
        }

        private void txtcomport_SelectedIndexChanged(object sender, EventArgs e)
        {
            serialPort1.PortName = txtcomport.Text.Trim();
            serialPort1.Open();
            serialPort1.DataReceived += new SerialDataReceivedEventHandler(serialPort1_DataReceived);
            serialPort1.RtsEnable = true;
            serialPort1.DtrEnable = true;
            txtprodcat.Focus();
        }

        private void serialPort1_DataReceived(object sender, SerialDataReceivedEventArgs e)
        {
            try
            {
                weight = serialPort1.ReadExisting();
                if (weight == String.Empty || txtcomport.Text == "")
                {
                    XtraMessageBox.Show("NODATARECEVD");
                    return;
                }
                else
                {
                    string tempweight = weight.Substring(0, 6).Trim(); //01.234
                    if (tempweight.Length == 5)
                    {
                        wieght2 = "0" + tempweight;
                    }
                    else
                    {
                        wieght2 = tempweight;
                    }
                }
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show(ex.Message.ToString() + "CHECK YOUR COMPORT OR RESTART THE WEIGHING SCALE");
            }
        }

        private void txtweight_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
            {
                // Scan with a partial qty: Enter posts the scanned lot. The
                // weight-scale path (displayweight) is only for FIFO picks.
                if (barcodescanning.Checked && _scannedBarcode != null)
                    btnadd.PerformClick();
                else
                    displayweight();
            }
        }

        private void txtproduct_Click(object sender, EventArgs e)
        {
            isusedSearch = false;
            if (txtprodcat.Text == "")
            {
                txtprodcat.Focus();
            }
            else
            {
                Database.displayComboBoxItems("SELECT Description FROM Products WHERE BranchCode='888' AND ProductCategoryCode='" + getProductCategoryCode() + "' ORDER BY Description", "Description", txtproduct);
            }
        }

        private void txtprodcat_SelectedIndexChanged(object sender, EventArgs e)
        {
            txtproduct.Text = "";
            txtproduct.Focus();
            Database.displayComboBoxItems("SELECT * FROM Products WHERE BranchCode='888'  AND ProductCategoryCode='" + getProductCategoryCode() + "' ORDER BY Description", "Description", txtproduct);

        }

        private void simpleButton4_Click(object sender, EventArgs e)
        {
            displayweight();
        }

        private void btnclear_Click(object sender, EventArgs e)
        {
            txtsku.Text = "";
            txtweight.Text = "";
            txtweight.Focus();
        }

        private void simpleButton5_Click(object sender, EventArgs e)
        {
            Barcode.BarcodePrinting bprint = new Barcode.BarcodePrinting();
            bprint.lblmanufdate.Text = DateTime.Now.ToShortDateString();
            bprint.lblprodtype.Text = txtproduct.Text;
            bprint.lbltotalkilos.Text = txtweight.Text;
            bprint.xrBarCode2.Text = txtsku.Text.Trim(); //productcategorycode + primalcode + txtweight.Text.Remove(2, 1);
            ReportPrintTool report = new ReportPrintTool(bprint);
            report.Print();
        }

        private void txtproduct_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
                btnfind.PerformClick();
        }

        private void txtsearch_Click(object sender, EventArgs e)
        {
            HOForms.SearchProducts searchProd = new HOForms.SearchProducts();
            searchProd.ShowDialog(this);
            Database.displayLocalGrid("SELECT * FROM view_CommissaryInventory ORDER BY Description ASC", searchProd.dataGridView1);
            if (HOForms.SearchProducts.isdone == true)
            {
                productcategorycode = HOForms.SearchProducts.prodcode.Substring(0, 2);
                string productcategorydesc = Database.getSingleQuery("ProductCategory", "ProductCategoryID='" + productcategorycode + "'", "Description");
                txtprodcat.Text = productcategorydesc;
                txtproduct.Text = HOForms.SearchProducts.prodname;
                txtweight.Focus();
                HOForms.SearchProducts.isdone = false;
                isusedSearch = true;
                searchProd.Dispose();
            }

        }

        private void searchLookUpEdit1_EditValueChanged(object sender, EventArgs e)
        {
            bool isFifo = Database.checkifExist("SELECT isFifo FROM InventorySettings WHERE isFifo=1");
            if (isFifo == false)
            {
                try
                {
                    GridView view = searchLookUpEdit1.Properties.View;
                    int rowHandle = view.FocusedRowHandle;
                    object value = view.GetRowCellValue(rowHandle, "SeqNo");
                    object valueAvailable = view.GetRowCellValue(rowHandle, "Available");
                    txtseqno.Text = value.ToString();
                    txtweight.Text = valueAvailable.ToString();
                    txtweight.Focus();
                }
                catch (Exception ex)
                {
                    XtraMessageBox.Show(ex.Message.ToString() + "---");
                }
            }
        }

        private void txtproduct_SelectedIndexChanged(object sender, EventArgs e)
        {
            bool isFifo = Database.checkifExist("SELECT isFifo FROM InventorySettings WHERE isFifo=1");
            if (isFifo == false)
            {
                if (barcodescanning.Checked == false)
                {
                    Database.displaySearchlookupEdit("SELECT BranchCode,BranchName FROM Branches", searchLookUpEditBranch, "BranchCode", "BranchCode");
                    searchLookUpEditBranch.Text = Login.assignedBranch;
                    Database.displaySearchlookupEdit("SELECT SequenceNumber as SeqNo,DateReceived,Barcode,Quantity,Available FROM Inventory WHERE Branch='" + searchLookUpEditBranch.Text + "' and isStock=1 and Available > 0  and Product='" + getProductCode() + "'", searchLookUpEdit1, "Barcode", "Barcode");
                    searchLookUpEdit1.Focus();
                }
                else
                {
                    txtbarcodescanning.Focus();
                }
            }
            else
            {
                if (barcodescanning.Checked == false)
                {
                    //OLD
                    //Database.displaySearchlookupEdit("SELECT BranchCode,BranchName FROM Branches", searchLookUpEditBranch, "BranchCode", "BranchCode");
                    //searchLookUpEditBranch.Text = Login.assignedBranch;
                    //Database.displaySearchlookupEdit("SELECT SequenceNumber as SeqNo,DateReceived,Barcode,Quantity,Available FROM Inventory WHERE Branch='" + searchLookUpEditBranch.Text + "' and isStock=1 and Available > 0 and isWarehouse = 1 and Product='" + getProductCode() + "'", searchLookUpEdit1, "Barcode", "Barcode");
                    //searchLookUpEdit1.Focus();
                    txtweight.Focus();
                }
                else
                {
                    txtbarcodescanning.Focus();
                }
            }
        }

        private void gridControl2_MouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
                contextMenuStrip1.Show(gridControl2, e.Location);
        }

        private void printBarcodeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            string qtydel = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "QtyDelivered").ToString();
            Barcode.BarcodePrinting bprint = new Barcode.BarcodePrinting();
            bprint.lblmanufdate.Text = DateTime.Now.ToShortDateString();
            bprint.lblprodtype.Text = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "ProductName").ToString();
            bprint.lbltotalkilos.Text = qtydel;
            bprint.xrBarCode2.Text = gridView2.GetRowCellValue(gridView2.FocusedRowHandle, "BarcodeNo").ToString();
            bprint.lblxpirydate.Text = DateTime.Now.AddYears(1).ToShortDateString();
            ReportPrintTool report = new ReportPrintTool(bprint);
            report.Print();
        }

        private void barcodescanning_CheckedChanged(object sender, EventArgs e)
        {
            if (barcodescanning.Checked == true)
            {
                isFifo = false;
                panel2.Visible = true;
                panel4.Visible = false;
                panel3.Visible = false;
                panel1.Visible = false;
                txtbarcodescanning.Focus();
                btnfind.Visible = false;
            }
            else
            {
                //panel2.Visible = false;
                //panel3.Visible = true;
                //panel1.Visible = true;
                //btnfind.Visible = true;
                barcodescanning.Checked = false;
                panel1.Visible = false;
                panel2.Visible = false;
                panel3.Visible = false;
                panel4.Visible = true;
            }
        }

        private void txtbarcodescanning_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode != Keys.Enter) return;

            string barcode = txtbarcodescanning.Text.Trim();
            if (barcode.Length == 0) return;

            // Same eligibility rule the post uses (fn_InvEligibleLots). The
            // post re-checks everything under lock; this is only for the prompt.
            decimal available;
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand(
                    "SELECT TOP (1) Available FROM dbo.fn_InvEligibleLots(@Branch) WHERE Barcode = @Barcode ORDER BY SequenceNumber", con))
                {
                    cmd.Parameters.Add("@Branch", SqlDbType.VarChar, 5).Value = Login.assignedBranch ?? "";
                    cmd.Parameters.Add("@Barcode", SqlDbType.VarChar, 35).Value = barcode;
                    con.Open();
                    object o = cmd.ExecuteScalar();
                    if (o == null || o == DBNull.Value)
                    {
                        BigAlert.Show("NOT FOUND", "No available warehouse stock for barcode " + barcode + ".", MessageBoxIcon.Warning);
                        txtbarcodescanning.Text = "";
                        txtbarcodescanning.Focus();
                        return;
                    }
                    available = Convert.ToDecimal(o);
                }
            }
            catch (SqlException ex)
            {
                BigAlert.Show("BARCODE SCANNING ERROR", ex.Message, MessageBoxIcon.Error);
                return;
            }

            if (Convert.ToBoolean(chkScanFullLot.EditValue))
            {
                // Full lot, posted straight away (the original behaviour).
                // On failure keep the barcode so the user can retry.
                if (PostLine("SCAN", available, barcode, null, null, null))
                    ClearScan();
                else
                    txtbarcodescanning.SelectAll();
                return;
            }

            // Partial: remember the lot, pre-fill its qty, wait for Add / Enter.
            _scannedBarcode = barcode;
            _scannedAvailable = available;
            txtsku.Text = barcode;
            txtweight.Text = available.ToString("0.000");
            txtweight.Focus();
            txtweight.SelectAll();
        }

        private void simpleButton7_Click(object sender, EventArgs e)
        {
            bool confirm = HelperFunction.ConfirmDialog("Are you sure you want to print all barcodes?", "Print All Barcode");
            if (confirm)
            {
                for (int i = 0; i <= gridView2.RowCount - 1; i++)
                {
                    //string qtydel = gridView2.GetRowCellValue(i, "QtyDelivered").ToString();
                    Barcode.BarcodePrinting bprint = new Barcode.BarcodePrinting();
                    bprint.lblmanufdate.Text = DateTime.Now.ToShortDateString();
                    bprint.lblprodtype.Text = gridView2.GetRowCellValue(i, "ProductName").ToString();
                    bprint.lbltotalkilos.Text = gridView2.GetRowCellValue(i, "QtyDelivered").ToString();
                    bprint.xrBarCode2.Text = gridView2.GetRowCellValue(i, "BarcodeNo").ToString();
                    bprint.lblxpirydate.Text = DateTime.Now.AddYears(1).ToShortDateString();
                    ReportPrintTool report = new ReportPrintTool(bprint);
                    //report.ShowRibbonPreviewDialog();
                    report.Print();
                }
            }
            else
            {
                return;
            }
        }

        private void simpleButton8_Click(object sender, EventArgs e)
        {
            Orders.OrderCheckerDevEx oread = new Orders.OrderCheckerDevEx();

            Database.display("SELECT ProductName,Qty FROM TransferOrderDetails WHERE PONumber='" + txtponum.Text + "'", oread.gridControlDelivByComm, oread.gridViewDelivByComm);
            Database.display("SELECT ProductName,QtyDelivered FROM DeliveryDetails WHERE PONumber='" + txtponum.Text + "'", oread.gridControlActualRcvd, oread.gridViewActualRcvd);
            Database.display("SELECT ProductName,Qty FROM TransferOrderDetails WHERE ProductCode not in (Select ProductNo FROM DeliveryDetails WHERE PONumber='" + txtponum.Text + "') AND PONumber='" + txtponum.Text + "' ", oread.gridControlMyStsReq, oread.gridViewMyStsReq);

            oread.ShowDialog(this);
        }

        private void simpleButton6_Click(object sender, EventArgs e)
        {
            if (gridView2.RowCount <= 0)
            {
                XtraMessageBox.Show("The System found out that there are no items to be pending!..");
                this.Close();
            }
            else
            {
                ispending = true;
                XtraMessageBox.Show("Transaction Save as Pending!");
                this.Close();   // opener owns disposal (using + ShowDialog)
            }
        }

        String getProductCode()
        {
            string str;
            str = Database.getSingleQuery("Products", "Description='" + txtproduct.Text.Trim() + "' AND ProductCategoryCode='" + getProductCategoryCode() + "'", "ProductCode");
            return str;
        }

        void displayweight()
        {
            try
            {
                
                int ctr2 = 1;
                decimal quantity;
                string strquantity;
                string productcode = "";
                if (txtcomport.Text == "" || txtcomport.Text == null)
                {
                    XtraMessageBox.Show("Please Select COM-PORT");
                }
                //else if(String.IsNullOrEmpty(txtsearchlookupproduct.Text))
                //{
                //    XtraMessageBox.Show("Please Select Product");
                //}
                else
                {
                    for (int i = 0; i <= gridView2.RowCount - 1; i++)
                    {
                        ctr2++;
                    }
                    txtweight.Invoke(this.myDelegate, new Object[] { wieght2 });

                    quantity = Decimal.Parse(txtweight.Text);
                    strquantity = String.Format("{0:00.000}", quantity);

                    if (barcodescanning.Checked == true)
                    {
                        productcode = globalproductcode;//Database.getSingleQuery("Inventory", "Barcode='" + globaltxtbarcodescanning + "' and isWarehouse=1 and Available > 0 and Branch='888' and IsStock=1", "Product");
                        txtsku.Text = txtbarcodescanning.Text;
                    }
                    else
                    {
                        productcode = pcode.ToString();//getProductCode();
                                                       //txtsku.Text = Database.getSingleQuery("Products", "BranchCode='" + Login.assignedBranch + "' AND ProductCode='" + pcode + "' ", "Barcode");
                        string barcode = "";
                        //        if (GlobalCache.CompanyName=="JFC")
                        //        {
                        //            if(String.IsNullOrEmpty(referencecode.ToString()))
                        //            {
                        //                XtraMessageBox.Show("No Reference Code");
                        //                return;
                        //            }
                        //            else
                        //            {
                        //                barcode = referencecode.ToString();
                        //            }
                        //        }
                        //        else
                        //        {
                        //            barcode = Database.getSingleResultSet($"SELECT dbo.func_GenerateBarcodeSTS" +
                        //$"('{Login.assignedBranch}',0,'{txtponum.Text}','{productcode.ToString()}','{strquantity}','2') ");
                        //        }
                        barcode = Database.getSingleResultSet($"SELECT dbo.func_GenerateBarcodeSTS" +
               $"('{Login.assignedBranch}',0,'{txtponum.Text}','{productcode.ToString()}','{strquantity}','2') ");

                        txtsku.Text = barcode;

                        btnadd.Focus();
                    }



                }

            }
            catch (SqlException ex)
            {
                XtraMessageBox.Show(ex.Message.ToString() + "ABC");
            }
        }

        // FIFO pick (Auto or Manual). txtsku is the STS sticker barcode that
        // displayweight() generates (Enter in Quantity / Get Weight), as before.
        void addByFIFO()
        {
            if (txtsku.Text == "")
            {
                BigAlert.Show("BARCODE EMPTY", "Barcode/SKU must not Empty!..", MessageBoxIcon.Warning);
                return;
            }
            if (pcode == null || string.IsNullOrWhiteSpace(pcode.ToString()))
            {
                BigAlert.Show("NO PRODUCT", "Select a product first.", MessageBoxIcon.Warning);
                txtsearchlookupproduct.Focus();
                return;
            }
            decimal qty;
            if (!TryParseQty(txtweight.Text, out qty))
            {
                BigAlert.Show("INVALID QTY", "Enter a quantity greater than zero.", MessageBoxIcon.Warning);
                txtweight.Focus();
                return;
            }

            bool manual = IsManualFifo;
            if (!PostLine(manual ? "BATCH" : "AUTO", qty, txtsku.Text.Trim(), pcode.ToString(),
                          manual ? (shipmentno?.ToString() ?? "") : null,
                          manual ? (referencecode?.ToString() ?? "") : null))
                return;   // nothing posted; keep the inputs so the user can correct them

            txtweight.Text = "";
            txtproduct.Text = "";
            // EditValue = null re-fires txtsearchlookupproduct_EditValueChanged;
            // the explicit nulls below stay AFTER it so they win.
            txtsearchlookupproduct.EditValue = null;
            txtsku.Text = "";
            pcode = null;
            catcode = null;
            referencecode = null;
            shipmentno = null;
            txtsearchlookupproduct.Focus();
        }

        // Scan with a partial qty (the full-lot case posts from the scan box).
        void addByBarcodeMethod()
        {
            if (_scannedBarcode == null)
            {
                BigAlert.Show("SCAN FIRST", "Scan a barcode first.", MessageBoxIcon.Warning);
                txtbarcodescanning.Focus();
                return;
            }
            decimal qty;
            if (!TryParseQty(txtweight.Text, out qty))
            {
                BigAlert.Show("INVALID QTY", "Enter a quantity greater than zero.", MessageBoxIcon.Warning);
                txtweight.Focus();
                return;
            }
            if (qty > _scannedAvailable)
            {
                BigAlert.Show("TOO MUCH", $"This lot only has {_scannedAvailable:N3} available.", MessageBoxIcon.Warning);
                txtweight.Focus();
                return;
            }

            if (PostLine("SCAN", qty, _scannedBarcode, null, null, null))
                ClearScan();
        }

        void ClearScan()
        {
            _scannedBarcode = null;
            _scannedAvailable = 0m;
            txtsku.Text = "";
            txtweight.Text = "";
            txtbarcodescanning.Text = "";
            txtbarcodescanning.Focus();
        }

        private void btnadd_Click(object sender, EventArgs e)
        {
            if (barcodescanning.Checked)
                addByBarcodeMethod();
            else
                addByFIFO();
        }

        private void simpleButton9_Click(object sender, EventArgs e)
        {
            _scannedBarcode = null;
            _scannedAvailable = 0m;
            txtsku.Text = "";
            txtweight.Text = "";
            txtweight.Focus();
        }

        private void simpleButton10_Click(object sender, EventArgs e)
        {
            Barcode.BarcodePrinting bprint = new Barcode.BarcodePrinting();
            bprint.lblmanufdate.Text = DateTime.Now.ToShortDateString();
            bprint.lblprodtype.Text = txtproduct.Text;
            bprint.lbltotalkilos.Text = txtweight.Text;
            bprint.xrBarCode2.Text = txtsku.Text.Trim(); //productcategorycode + primalcode + txtweight.Text.Remove(2, 1);
            ReportPrintTool report = new ReportPrintTool(bprint);
            report.Print();
        }

        // One return path for every line type and company (spu_ReverseSTSLineV2).
        private void btncancel_Click(object sender, EventArgs e)
        {
            ReturnLine();
            displayForDelivery();
        }

        private void simpleButton11_Click(object sender, EventArgs e)
        {
            if (gridView2.RowCount == 0)
            {
                BigAlert.Show(
                   "NO STOCKS PROCESS",
                   "No Records Found!...",
                   MessageBoxIcon.Warning);
                return;
            }

            // gridView2 only shows active PENDING lines -- re-check against the DB
            // so a desync (everything cancelled since the grid loaded) gets a clear
            // message instead of the SP's empty-delivery guard.
            bool hasConfirmableLines;
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand(
                "SELECT CASE WHEN EXISTS (SELECT 1 FROM dbo.DeliveryDetails WHERE DeliveryNo = @DeliveryNo AND PONumber = @PONumber " +
                "AND ISNULL(isReturned, 0) = 0 AND ISNULL(isCancelled, 0) = 0) THEN 1 ELSE 0 END", con))
            {
                cmd.Parameters.Add("@DeliveryNo", SqlDbType.VarChar, 20).Value = txtdevno.Text.Trim();
                cmd.Parameters.Add("@PONumber", SqlDbType.VarChar, 20).Value = txtponum.Text.Trim();
                con.Open();
                hasConfirmableLines = Convert.ToInt32(cmd.ExecuteScalar()) == 1;
            }
            if (!hasConfirmableLines)
            {
                XtraMessageBox.Show("Cant Save: No valid line items found for this delivery. Please add at least one product.");
                return;
            }

            if (!HelperFunction.ConfirmDialog("Are you sure all order has been Processed?", "Save Transaction"))
                return;

            // Only report success when Confirm actually succeeded (the original
            // showed SUCCESS even after sp_ConfirmBranchOrderSTS threw).
            if (!ConfirmBranchOrder())
                return;

            isdone = true;
            BigAlert.Show(
              "SUCCESS",
              "Transaction Successfully Saved!...",
              MessageBoxIcon.Information);
            this.Close();
        }

        private void simpleButton1_Click_1(object sender, EventArgs e)
        {
            displayweight();
        }

        private void btnsaveasdraft_Click(object sender, EventArgs e)
        {
            if (gridView2.RowCount <= 0)
            {
                XtraMessageBox.Show("The System found out that there are no items to be pending!..");
                this.Close();
            }
            else
            {
                ispending = true;
                XtraMessageBox.Show("Transaction Save as Pending!");
                this.Close();   // opener owns disposal (using + ShowDialog)
            }
        }

        private void txtsearchlookupproduct_EditValueChanged(object sender, EventArgs e)
        {
            catcode = null;
            pcode = null;
            referencecode = null;
            shipmentno = null;
            // A sticker barcode generated for the previous product must not be
            // posted against this one -- Enter in Quantity / Get Weight makes a new one.
            if (!barcodescanning.Checked) txtsku.Text = "";
            if (txtsearchlookupproduct.EditValue == null || txtsearchlookupproduct.EditValue == DBNull.Value)
                return;

            // Read the row that matches the SELECTED value (EditValue), not the
            // popup's focused row, which can be stale.
            var row = txtsearchlookupproduct.Properties.GetRowByKeyValue(txtsearchlookupproduct.EditValue) as DataRowView;
            if (row == null) return;

            pcode = row["ProductCode"];
            if (IsManualFifo)
            {
                // LotKey = Product||ShipmentNo||ReferenceCode -- the batch the post is confined to.
                shipmentno = row["ShipmentNo"];
                referencecode = row["ReferenceCode"];
            }
            txtweight.Focus();
        }

        private void btnchecker_Click(object sender, EventArgs e)
        {
            Orders.OrderCheckerDevEx oread = new Orders.OrderCheckerDevEx();

            Database.display("SELECT ProductName,Qty FROM dbo.TransferOrderDetails WHERE PONumber='" + txtponum.Text + "'  ORDER BY ProductCode ", oread.gridControlMyStsReq, oread.gridViewMyStsReq);

            Database.display("SELECT ProductName,QtyDelivered FROM dbo.DeliveryDetails WHERE PONumber='" + txtponum.Text + "' AND Status='PENDING' ORDER BY ProductNo", oread.gridControlDelivByComm, oread.gridViewDelivByComm);
            GridView view = oread.gridControlDelivByComm.FocusedView as GridView;
            view.SortInfo.ClearAndAddRange(new GridColumnSortInfo[] {
                new GridColumnSortInfo(view.Columns["ProductName"],DevExpress.Data.ColumnSortOrder.Ascending)
                }, 1);
            oread.gridViewDelivByComm.ExpandAllGroups();


            GridGroupSummaryItem itez = new GridGroupSummaryItem();
            itez.FieldName = "ProductNo";
            itez.SummaryType = DevExpress.Data.SummaryItemType.Count;
            itez.ShowInGroupColumnFooter = oread.gridViewDelivByComm.Columns["ProductNo"];
            oread.gridViewDelivByComm.GroupSummary.Add(itez);
            oread.gridViewDelivByComm.Focus();

            GridGroupSummaryItem ite = new GridGroupSummaryItem();
            ite.FieldName = "QtyDelivered";
            ite.SummaryType = DevExpress.Data.SummaryItemType.Sum;
            ite.ShowInGroupColumnFooter = oread.gridViewDelivByComm.Columns["QtyDelivered"];
            oread.gridViewDelivByComm.GroupSummary.Add(ite);
            oread.gridViewDelivByComm.Focus();

            oread.gridViewDelivByComm.Columns["QtyDelivered"].Summary.Clear();
            oread.gridViewDelivByComm.Columns["QtyDelivered"].Summary.Add(DevExpress.Data.SummaryItemType.Sum, "QtyDelivered", "{0:n2}");


            // Database.display("SELECT ProductName,SUM(QtyDelivered) as TotalKilos,COUNT(distinct BarcodeNo) as TotalBox FROM DeliveryDetails WHERE PONumber='" + txtponum.Text + "' GROUP BY ProductName", oread.gridControlActualRcvd, oread.gridViewActualRcvd);


            oread.ShowDialog(this);
        }

        private void simpleButton2_Click_1(object sender, EventArgs e)
        {
            bool confirm = HelperFunction.ConfirmDialog("Are you sure you want to print all barcodes?", "Print All Barcode");
            if (confirm)
            {
                for (int i = 0; i <= gridView2.RowCount - 1; i++)
                {
                    //string qtydel = gridView2.GetRowCellValue(i, "QtyDelivered").ToString();
                    Barcode.BarcodePrinting bprint = new Barcode.BarcodePrinting();
                    bprint.xrLabel3.Text = "PONumber:";
                    bprint.xrLabel6.Text = "";
                    bprint.lblmanufdate.Text = DateTime.Now.ToShortDateString();
                    bprint.lblprodtype.Text = gridView2.GetRowCellValue(i, "ProductName").ToString();
                    bprint.lbltotalkilos.Text = gridView2.GetRowCellValue(i, "QtyDelivered").ToString();
                    bprint.xrBarCode2.Text = gridView2.GetRowCellValue(i, "BarcodeNo").ToString();
                    bprint.lblxpirydate.Text = DateTime.Now.AddYears(1).ToShortDateString();
                    ReportPrintTool report = new ReportPrintTool(bprint);
                    //report.ShowRibbonPreviewDialog();
                    report.Print();
                }
            }
            else
            {
                return;
            }
        }

        private void simpleButton3_Click_1(object sender, EventArgs e)
        {
            HOForms.SearchProducts searchProd = new HOForms.SearchProducts();
            searchProd.ShowDialog(this);
            Database.displayLocalGrid("SELECT * FROM view_CommissaryInventory ORDER BY Description ASC", searchProd.dataGridView1);
            if (HOForms.SearchProducts.isdone == true)
            {
                productcategorycode = HOForms.SearchProducts.prodcatcode;
                string productcategorydesc = Database.getSingleQuery("ProductCategory", "ProductCategoryID='" + productcategorycode + "'", "Description");
                txtprodcat.Text = productcategorydesc;
                txtproduct.Text = HOForms.SearchProducts.prodname;
                txtweight.Focus();
                HOForms.SearchProducts.isdone = false;
                isusedSearch = true;
                searchProd.Dispose();
            }
        }

    }
}