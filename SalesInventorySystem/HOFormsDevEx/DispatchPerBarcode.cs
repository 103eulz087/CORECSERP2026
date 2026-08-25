using System;
using System.Data;
using System.Data.SqlClient;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using SalesInventorySystem.Classes;

namespace SalesInventorySystem.HOFormsDevEx
{
    public partial class DispatchPerBarcode : DevExpress.XtraEditors.XtraForm, IResettableForm
    {
        // Origin is whichever branch the dispatching user is logged into -- NOT
        // hardcoded to HO/888. Any branch can be the supplying side of a transfer;
        // spu_PostSTSDispatch independently verifies this branch is the one the
        // approved Transfer Order request actually expects to supply it.
        static string OriginBranch => Login.assignedBranch;

        private DataTable tableSource;
        private DataTable tablePOLookup;
        private bool _dataLoaded;
        private bool _suppressSourceMethodChanged;
        private bool _suppressFifoTypeChanged;

        bool IsBarcodeMethod => Convert.ToString(radioGroupSourceMethod.EditValue) == "Barcode";
        bool IsManualFifo => Convert.ToString(radioGroupFifoType.EditValue) == "Manual";

        public DispatchPerBarcode()
        {
            InitializeComponent();
        }

        private void DispatchPerBarcode_Load(object sender, EventArgs e)
        {
            if (!_dataLoaded)
                LoadData();
        }

        public void LoadData()
        {
            if (_dataLoaded)
                return;

            txtBranch.Text = OriginBranch;
            BuildSourceGridShape();
            LoadPONumberDropdown();
            LoadFifoProductDropdown();
            UpdateSourceMethodVisibility();
            ClearHeaderForNewPO();
            LoadPostedGrid();

            _dataLoaded = true;
        }

        // ------------------------------------------------------------------
        // PO Number (header)
        // ------------------------------------------------------------------
        void LoadPONumberDropdown()
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.sp_GetApprovedTransferOrdersForDispatch", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@OriginBranch", SqlDbType.VarChar, 10).Value = OriginBranch;

                var dt = new DataTable();
                con.Open();
                using (var da = new SqlDataAdapter(cmd))
                    da.Fill(dt);

                tablePOLookup = dt;

                slkPONumber.Properties.View.Columns.Clear();
                slkPONumber.Properties.DataSource = null;
                slkPONumber.Properties.DataSource = dt;
                slkPONumber.Properties.DisplayMember = "DisplayText";
                slkPONumber.Properties.ValueMember = "PONumber";
            }
        }

        private void slkPONumber_EditValueChanged(object sender, EventArgs e)
        {
            if (tableSource.Rows.Count > 0)
            {
                if (XtraMessageBox.Show(
                        "Switching the PO Number will clear the items already staged for dispatch. Continue?",
                        "Change PO Number", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                {
                    return;
                }
                tableSource.Rows.Clear();
                RecalculateTotals();
            }

            if (slkPONumber.EditValue == null || string.IsNullOrEmpty(slkPONumber.EditValue.ToString()))
            {
                ClearHeaderForNewPO();
                return;
            }

            string ponumber = slkPONumber.EditValue.ToString();
            DataRow[] rows = tablePOLookup == null ? new DataRow[0] : tablePOLookup.Select($"PONumber = '{ponumber.Replace("'", "''")}'");
            if (rows.Length == 0)
            {
                ClearHeaderForNewPO();
                return;
            }

            txtDestinationBranch.Text = rows[0]["DestinationBranch"].ToString();
            txtEffectivityDate.Text = Convert.ToDateTime(rows[0]["EffectivityDate"]).ToString("yyyy-MM-dd");

            // Reuse the DeliveryNo already assigned to this PO if a prior partial
            // dispatch created one (same lookup AddBranchOrderSTS.cs already uses);
            // otherwise generate a fresh one. ReferenceNo is not tracked as an
            // independent identity anywhere downstream for this flow, so the
            // DeliveryNo itself is reused as the ReferenceNo tag.
            string existingDevNo = Database.getSingleData("DeliverySummary", "PONumber", ponumber, "DeliveryNo");
            txtRefNo.Text = string.IsNullOrEmpty(existingDevNo)
                ? IDGenerator.getIDNumberSP("sp_GetDeliveryNumber", "DeliveryNumber")
                : existingDevNo;

            EnableEntryControls(true);
            if (IsBarcodeMethod) txtScanBarcode.Focus(); else slueFifoProduct.Focus();
        }

        void ClearHeaderForNewPO()
        {
            txtDestinationBranch.Text = "";
            txtEffectivityDate.Text = "";
            txtRefNo.Text = "";
            EnableEntryControls(false);
        }

        void EnableEntryControls(bool enabled)
        {
            txtScanBarcode.Enabled = enabled;
            btnAddScan.Enabled = enabled;
            radioGroupFifoType.Enabled = enabled;
            slueFifoProduct.Enabled = enabled;
            txtFifoQty.Enabled = enabled;
            btnAddFifo.Enabled = enabled;
            btnSubmit.Enabled = enabled;
        }

        public async Task ResetUIAsync()
        {
            try
            {
                UseWaitCursor = true;
                await Task.Run(() => LoadPONumberDropdown());
                ClearEntryOnly();
            }
            finally
            {
                UseWaitCursor = false;
            }
        }

        void ClearEntryOnly()
        {
            // IResettableForm is documented as being for reusable/reopenable forms, so a
            // host could in principle call ResetUIAsync() before LoadData() has ever run.
            if (tableSource == null)
                return;

            tableSource.Rows.Clear();
            slueFifoProduct.EditValue = null;
            txtFifoQty.Value = 0;
            txtScanBarcode.Text = "";
            slkPONumber.EditValue = null;

            _suppressSourceMethodChanged = true;
            radioGroupSourceMethod.EditValue = "Barcode";
            _suppressSourceMethodChanged = false;

            _suppressFifoTypeChanged = true;
            radioGroupFifoType.EditValue = "Auto";
            _suppressFifoTypeChanged = false;
            LoadFifoProductDropdown();

            UpdateSourceMethodVisibility();
            ClearHeaderForNewPO();
            RecalculateTotals();
        }

        // ------------------------------------------------------------------
        // Source method (Barcode / FIFO)
        // ------------------------------------------------------------------
        void LoadFifoProductDropdown()
        {
            if (IsManualFifo)
                LoadFifoProductDropdownManual();
            else
                LoadFifoProductDropdownAuto();
        }

        void LoadFifoProductDropdownAuto()
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.sp_GetInventoryForDispatchDropdown", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 50).Value = OriginBranch;

                var dt = new DataTable();
                con.Open();
                using (var da = new SqlDataAdapter(cmd))
                    da.Fill(dt);

                slueFifoProduct.Properties.View.Columns.Clear();
                slueFifoProduct.Properties.DataSource = null;
                slueFifoProduct.Properties.DataSource = dt;
                slueFifoProduct.Properties.DisplayMember = "DisplayText";
                slueFifoProduct.Properties.ValueMember = "ProductCode";
            }
        }

        void LoadFifoProductDropdownManual()
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.sp_GetInventoryForDispatchManualDropdown", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 50).Value = OriginBranch;

                var dt = new DataTable();
                con.Open();
                using (var da = new SqlDataAdapter(cmd))
                    da.Fill(dt);

                // ValueMember is the composite LookupKey ("Product||ShipmentNo||ReferenceCode")
                // the SP builds -- ProductCode alone isn't unique per row (one product can
                // have several batches in stock at once).
                slueFifoProduct.Properties.View.Columns.Clear();
                slueFifoProduct.Properties.DataSource = null;
                slueFifoProduct.Properties.DataSource = dt;
                slueFifoProduct.Properties.DisplayMember = "DisplayText";
                slueFifoProduct.Properties.ValueMember = "LookupKey";
            }
        }

        void UpdateSourceMethodVisibility()
        {
            bool barcode = IsBarcodeMethod;

            labelControl7.Visible = barcode;
            txtScanBarcode.Visible = barcode;
            btnAddScan.Visible = barcode;

            labelControlFifoType.Visible = !barcode;
            radioGroupFifoType.Visible = !barcode;
            labelControlFifoProduct.Visible = !barcode;
            slueFifoProduct.Visible = !barcode;
            labelControlFifoQty.Visible = !barcode;
            txtFifoQty.Visible = !barcode;
            btnAddFifo.Visible = !barcode;
        }

        private void radioGroupSourceMethod_EditValueChanged(object sender, EventArgs e)
        {
            if (_suppressSourceMethodChanged) return;
            UpdateSourceMethodVisibility();
            if (IsBarcodeMethod) txtScanBarcode.Focus(); else slueFifoProduct.Focus();
        }

        private void radioGroupFifoType_EditValueChanged(object sender, EventArgs e)
        {
            if (_suppressFifoTypeChanged) return;
            slueFifoProduct.EditValue = null;
            txtFifoQty.Value = 0;
            LoadFifoProductDropdown();
            slueFifoProduct.Focus();
        }

        void BuildSourceGridShape()
        {
            tableSource = new DataTable();
            tableSource.Columns.Add("SeqNo", typeof(int));
            tableSource.Columns.Add("InventorySeqNo", typeof(int));
            tableSource.Columns.Add("Barcode", typeof(string));
            tableSource.Columns.Add("ProductCode", typeof(string));
            tableSource.Columns.Add("Description", typeof(string));
            tableSource.Columns.Add("Qty", typeof(decimal));
            tableSource.Columns.Add("Cost", typeof(decimal));
            tableSource.Columns.Add("Amount", typeof(decimal));
            gridControlSource.DataSource = tableSource;

            gridViewSource.PopulateColumns();
            gridViewSource.Columns["SeqNo"].Visible = false;
            gridViewSource.Columns["InventorySeqNo"].Visible = false;
            gridViewSource.Columns["ProductCode"].Caption = "Product Code";
            gridViewSource.Columns["Cost"].Caption = "Unit Cost";
            gridViewSource.BestFitColumns();
        }

        void RecalculateTotals()
        {
            decimal totalQty = 0m, totalCost = 0m;
            foreach (DataRow r in tableSource.Rows)
            {
                totalQty += Convert.ToDecimal(r["Qty"]);
                totalCost += Convert.ToDecimal(r["Amount"]);
            }
            txtTotalSourceQty.Text = totalQty.ToString("N3");
            txtTotalSourceCost.Text = totalCost.ToString("N2");

            gridViewSource.BestFitColumns();
        }

        // ------------------------------------------------------------------
        // Scanning
        // ------------------------------------------------------------------
        private void txtScanBarcode_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
                btnAddScan.PerformClick();
        }

        private void btnAddScan_Click(object sender, EventArgs e)
        {
            ScanBarcode();
        }

        void ScanBarcode()
        {
            if (!RequirePONumber()) return;

            string barcode = txtScanBarcode.Text.Trim();
            if (string.IsNullOrEmpty(barcode))
            {
                txtScanBarcode.Focus();
                return;
            }

            if (tableSource.Select($"Barcode = '{barcode.Replace("'", "''")}'").Length > 0)
            {
                BigAlert.Show("ALREADY SCANNED", "This barcode is already in the Dispatch list.", MessageBoxIcon.Warning);
                txtScanBarcode.Text = "";
                txtScanBarcode.Focus();
                return;
            }

            DataRow found = LookupInventoryByBarcode(barcode);
            if (found == null)
            {
                BigAlert.Show("NOT FOUND", "No available inventory found for this barcode at your branch.", MessageBoxIcon.Warning);
                txtScanBarcode.Text = "";
                txtScanBarcode.Focus();
                return;
            }

            decimal qty = Convert.ToDecimal(found["Available"]);
            decimal cost = Convert.ToDecimal(found["Cost"]);

            DataRow row = tableSource.NewRow();
            row["SeqNo"] = tableSource.Rows.Count + 1;
            row["InventorySeqNo"] = Convert.ToInt32(found["SequenceNumber"]);
            row["Barcode"] = found["Barcode"].ToString();
            row["ProductCode"] = found["ProductCode"].ToString();
            row["Description"] = found["Description"].ToString();
            row["Qty"] = qty;
            row["Cost"] = cost;
            row["Amount"] = qty * cost;
            tableSource.Rows.Add(row);

            RecalculateTotals();
            txtScanBarcode.Text = "";
            txtScanBarcode.Focus();
        }

        DataRow LookupInventoryByBarcode(string barcode)
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.sp_GetInventoryByBarcodeForDispatch", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@Barcode", SqlDbType.VarChar, 100).Value = barcode;
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 50).Value = OriginBranch;

                var dt = new DataTable();
                con.Open();
                using (var da = new SqlDataAdapter(cmd))
                    da.Fill(dt);

                return dt.Rows.Count > 0 ? dt.Rows[0] : null;
            }
        }

        private void mnuRemoveSourceLine_Click(object sender, EventArgs e)
        {
            if (gridViewSource.FocusedRowHandle < 0) return;
            gridViewSource.DeleteSelectedRows();
            RecalculateTotals();
        }

        // ------------------------------------------------------------------
        // Select Product (FIFO)
        // ------------------------------------------------------------------
        private void btnAddFifo_Click(object sender, EventArgs e)
        {
            AddFifoProduct();
        }

        void AddFifoProduct()
        {
            if (!RequirePONumber()) return;

            if (slueFifoProduct.EditValue == null || string.IsNullOrEmpty(slueFifoProduct.EditValue.ToString()))
            {
                BigAlert.Show("NO PRODUCT", "Please select a product first.", MessageBoxIcon.Warning);
                return;
            }

            string productCode;
            string shipmentNo = null;
            string referenceCode = null;

            if (IsManualFifo)
            {
                string[] parts = slueFifoProduct.EditValue.ToString().Split(new[] { "||" }, StringSplitOptions.None);
                if (parts.Length != 3)
                {
                    BigAlert.Show("SELECTION ERROR", "Could not resolve the selected product/shipment. Please reselect.", MessageBoxIcon.Warning);
                    return;
                }
                productCode = parts[0];
                shipmentNo = parts[1];
                referenceCode = parts[2];
            }
            else
            {
                productCode = slueFifoProduct.EditValue.ToString();
            }

            decimal qty = txtFifoQty.Value;
            if (qty <= 0)
            {
                BigAlert.Show("INVALID QTY", "Please enter a valid quantity greater than zero.", MessageBoxIcon.Warning);
                txtFifoQty.Focus();
                return;
            }

            DataTable breakdown = IsManualFifo
                ? GetFifoBreakdownByShipment(productCode, shipmentNo, referenceCode, qty)
                : GetFifoBreakdown(productCode, qty);
            decimal totalReturned = breakdown.Rows.Count == 0 ? 0m : breakdown.AsEnumerable().Sum(r => Convert.ToDecimal(r["Qty"]));

            if (totalReturned < qty)
            {
                BigAlert.Show(
                    "INSUFFICIENT STOCK",
                    $"Only {totalReturned:N3} available for this product{(IsManualFifo ? " in the selected shipment" : "")} (requested {qty:N3}).",
                    MessageBoxIcon.Warning);
                return;
            }

            foreach (DataRow r in breakdown.Rows)
            {
                int invSeqNo = Convert.ToInt32(r["SequenceNumber"]);
                if (tableSource.Select($"InventorySeqNo = {invSeqNo}").Length > 0)
                {
                    BigAlert.Show(
                        "LOT ALREADY STAGED",
                        "One of the FIFO lots for this product is already in the Dispatch list from an earlier pick. Remove it first, or enter a smaller quantity.",
                        MessageBoxIcon.Warning);
                    return;
                }
            }

            foreach (DataRow r in breakdown.Rows)
            {
                decimal lineQty = Convert.ToDecimal(r["Qty"]);
                decimal lineCost = Convert.ToDecimal(r["Cost"]);

                DataRow row = tableSource.NewRow();
                row["SeqNo"] = tableSource.Rows.Count + 1;
                row["InventorySeqNo"] = Convert.ToInt32(r["SequenceNumber"]);
                row["Barcode"] = r["Barcode"].ToString();
                row["ProductCode"] = r["ProductCode"].ToString();
                row["Description"] = r["Description"].ToString();
                row["Qty"] = lineQty;
                row["Cost"] = lineCost;
                row["Amount"] = lineQty * lineCost;
                tableSource.Rows.Add(row);
            }

            RecalculateTotals();
            slueFifoProduct.EditValue = null;
            txtFifoQty.Value = 0;
            slueFifoProduct.Focus();
        }

        DataTable GetFifoBreakdown(string productCode, decimal requestedQty)
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.sp_GetDispatchFIFOBreakdown", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@ProductCode", SqlDbType.VarChar, 50).Value = productCode;
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 50).Value = OriginBranch;
                cmd.Parameters.Add("@RequestedQty", SqlDbType.Decimal).Value = requestedQty;
                cmd.Parameters["@RequestedQty"].Precision = 18;
                cmd.Parameters["@RequestedQty"].Scale = 3;

                var pStaged = cmd.Parameters.AddWithValue("@AlreadyStaged", BuildStagedLotsTVP());
                pStaged.SqlDbType = SqlDbType.Structured;
                pStaged.TypeName = "dbo.tt_STSDispatchStagedLots";

                var dt = new DataTable();
                con.Open();
                using (var da = new SqlDataAdapter(cmd))
                    da.Fill(dt);

                return dt;
            }
        }

        DataTable GetFifoBreakdownByShipment(string productCode, string shipmentNo, string referenceCode, decimal requestedQty)
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.sp_GetDispatchFIFOBreakdownByShipment", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@ProductCode", SqlDbType.VarChar, 50).Value = productCode;
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 50).Value = OriginBranch;
                cmd.Parameters.Add("@ShipmentNo", SqlDbType.VarChar, 10).Value = shipmentNo;
                cmd.Parameters.Add("@ReferenceCode", SqlDbType.VarChar, 50).Value = string.IsNullOrEmpty(referenceCode) ? (object)DBNull.Value : referenceCode;
                cmd.Parameters.Add("@RequestedQty", SqlDbType.Decimal).Value = requestedQty;
                cmd.Parameters["@RequestedQty"].Precision = 18;
                cmd.Parameters["@RequestedQty"].Scale = 3;

                var pStaged = cmd.Parameters.AddWithValue("@AlreadyStaged", BuildStagedLotsTVP());
                pStaged.SqlDbType = SqlDbType.Structured;
                pStaged.TypeName = "dbo.tt_STSDispatchStagedLots";

                var dt = new DataTable();
                con.Open();
                using (var da = new SqlDataAdapter(cmd))
                    da.Fill(dt);

                return dt;
            }
        }

        DataTable BuildStagedLotsTVP()
        {
            var dt = new DataTable();
            dt.Columns.Add("InventorySeqNo", typeof(int));
            dt.Columns.Add("Qty", typeof(decimal));

            foreach (DataRow r in tableSource.Rows)
            {
                dt.Rows.Add(Convert.ToInt32(r["InventorySeqNo"]), Convert.ToDecimal(r["Qty"]));
            }
            return dt;
        }

        bool RequirePONumber()
        {
            if (slkPONumber.EditValue == null || string.IsNullOrEmpty(slkPONumber.EditValue.ToString()))
            {
                BigAlert.Show("NO PO NUMBER", "Please select an approved PO Number first.", MessageBoxIcon.Warning);
                return false;
            }
            return true;
        }

        // ------------------------------------------------------------------
        // Submit / Post
        // ------------------------------------------------------------------
        private void btnSubmit_Click(object sender, EventArgs e)
        {
            if (!ValidateForSubmit())
                return;

            gridViewSource.CloseEditor();

            DataTable lines = BuildLinesTVP();

            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.spu_PostSTSDispatch", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.CommandTimeout = 180;
                cmd.Parameters.Add("@DeliveryNo", SqlDbType.VarChar, 20).Value = txtRefNo.Text;
                cmd.Parameters.Add("@ReferenceNo", SqlDbType.VarChar, 10).Value = txtRefNo.Text;
                cmd.Parameters.Add("@PONumber", SqlDbType.VarChar, 10).Value = slkPONumber.EditValue.ToString();
                cmd.Parameters.Add("@OriginBranch", SqlDbType.VarChar, 10).Value = OriginBranch;
                cmd.Parameters.Add("@DestinationBranch", SqlDbType.VarChar, 10).Value = txtDestinationBranch.Text;
                cmd.Parameters.Add("@DispatchedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;

                var pLines = cmd.Parameters.AddWithValue("@Lines", lines);
                pLines.SqlDbType = SqlDbType.Structured;
                pLines.TypeName = "dbo.tt_STSDispatchLines";

                try
                {
                    con.Open();
                    cmd.ExecuteNonQuery();
                    BigAlert.Show("SUCCESS", "Dispatch posted successfully.", MessageBoxIcon.Information);
                    _ = ResetUIAsync();
                    LoadPostedGrid();
                }
                catch (SqlException ex)
                {
                    BigAlert.Show("POST FAILED", ex.Message, MessageBoxIcon.Error);
                }
            }
        }

        bool ValidateForSubmit()
        {
            if (!RequirePONumber())
                return false;

            if (tableSource.Rows.Count == 0)
            {
                BigAlert.Show("NO ITEMS", "Please add at least one item to dispatch (scan a barcode or select a product).", MessageBoxIcon.Warning);
                return false;
            }

            if (string.IsNullOrEmpty(txtRefNo.Text))
            {
                BigAlert.Show("NO DELIVERY NO", "Delivery No could not be resolved for this PO. Please reselect the PO Number.", MessageBoxIcon.Warning);
                return false;
            }

            return true;
        }

        DataTable BuildLinesTVP()
        {
            var dt = new DataTable();
            dt.Columns.Add("InventorySeqNo", typeof(int));
            dt.Columns.Add("Barcode", typeof(string));
            dt.Columns.Add("ProductCode", typeof(string));
            dt.Columns.Add("Description", typeof(string));
            dt.Columns.Add("Qty", typeof(decimal));
            dt.Columns.Add("Cost", typeof(decimal));

            foreach (DataRow r in tableSource.Rows)
            {
                dt.Rows.Add(
                    Convert.ToInt32(r["InventorySeqNo"]),
                    r["Barcode"].ToString(),
                    r["ProductCode"].ToString(),
                    r["Description"].ToString(),
                    Convert.ToDecimal(r["Qty"]),
                    Convert.ToDecimal(r["Cost"]));
            }
            return dt;
        }

        private void btnClearAll_Click(object sender, EventArgs e)
        {
            if (tableSource.Rows.Count == 0) return;

            if (XtraMessageBox.Show("Clear all items staged for this dispatch?",
                    "Clear", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;

            tableSource.Rows.Clear();
            RecalculateTotals();
        }

        private void btnResetEntry_Click(object sender, EventArgs e)
        {
            if (tableSource.Rows.Count > 0)
            {
                if (XtraMessageBox.Show("Start a brand new Dispatch? Unsaved items will be lost.",
                        "New Entry", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                    return;
            }
            _ = ResetUIAsync();
        }

        // ------------------------------------------------------------------
        // Posted tab
        // ------------------------------------------------------------------
        // No "Copy to New Entry" action here (unlike ConversionPerBarcode) --
        // a dispatch is always tied to one specific APPROVED PO Number, so
        // there's nothing reusable to copy forward into a new entry.
        void LoadPostedGrid()
        {
            Database.display(
                "SELECT DeliveryNo, PONumber, ReferenceNumber, DestinationBranch, TotalItem, TotalQtyDelivered, " +
                "Status, EffectivityDate, DateAdded, PreparedBy " +
                "FROM dbo.vw_STSDispatchSummary WITH (NOLOCK) " +
                "ORDER BY DateAdded DESC",
                gridControlPosted, gridViewPosted);
            gridViewPosted.BestFitColumns();
        }

        private void btnRefreshPosted_Click(object sender, EventArgs e)
        {
            LoadPostedGrid();
        }

        string GetFocusedPostedDeliveryNo()
        {
            if (gridViewPosted.FocusedRowHandle < 0) return null;
            var val = gridViewPosted.GetRowCellValue(gridViewPosted.FocusedRowHandle, "DeliveryNo");
            return val == null ? null : val.ToString();
        }

        private void mnuViewDetails_Click(object sender, EventArgs e)
        {
            string deliveryNo = GetFocusedPostedDeliveryNo();
            if (string.IsNullOrEmpty(deliveryNo)) return;

            string ponumber = gridViewPosted.GetRowCellValue(gridViewPosted.FocusedRowHandle, "PONumber").ToString();

            Database.display(
                "SELECT dd.SeqNo, dd.ProductNo, dd.ProductName, dd.BarcodeNo, dd.QtyDelivered, dd.ActualQty, dd.Cost, " +
                "dd.SellingPrice, dd.[Status], dd.DeliveryNo, dd.PONumber, dd.ReferenceNumber, dd.OriginBranch, " +
                "ds.BranchCode AS DestinationBranch " +
                "FROM dbo.DeliveryDetails dd WITH (NOLOCK) " +
                "LEFT JOIN dbo.DeliverySummary ds WITH (NOLOCK) ON ds.DeliveryNo = dd.DeliveryNo AND ds.PONumber = dd.PONumber " +
                "WHERE dd.DeliveryNo = '" + deliveryNo.Replace("'", "''") + "' AND dd.PONumber = '" + ponumber.Replace("'", "''") + "' " +
                "AND dd.isReturned = 0 AND dd.isCancelled = 0 ORDER BY dd.SeqNo",
                gridControlPosted, gridViewPosted);
        }

        // Reverses one delivered line at a time via the same, already-fixed
        // sp_ReverseSTSInventoryTransfer ReceivedSTSBatchMode.cs uses for
        // undelivered-item returns -- restores stock at the ORIGINAL origin
        // branch (not necessarily the current user's own branch -- origin is
        // per-dispatch now, not always HO) and, once nothing is left for this
        // dispatch, corrects DeliverySummary.Status to RETURNED. Operates on
        // whichever row is focused in the Posted grid; after "View Details"
        // drills into DeliveryDetails lines, focus a line there and Reverse
        // to undo just that line.
        //
        // Parameter mapping mirrors ReceivedSTSBatchMode.ReturnUnreceivedItems:
        // @parmbranchcode is the branch CURRENTLY holding the stock (being
        // reversed FROM) = this dispatch's DestinationBranch; @parmorigin is
        // the branch stock gets RESTORED back TO = this dispatch's own
        // OriginBranch (read back from the DeliveryDetails row, since the
        // person clicking Reverse may not be at the same branch that
        // originally dispatched it).
        private void mnuReversePosted_Click(object sender, EventArgs e)
        {
            if (gridViewPosted.FocusedRowHandle < 0) return;

            object seqNoObj = gridViewPosted.GetRowCellValue(gridViewPosted.FocusedRowHandle, "SeqNo");
            if (seqNoObj == null)
            {
                BigAlert.Show("SELECT A LINE", "Open View Details first, then focus the specific delivered line you want to reverse.", MessageBoxIcon.Warning);
                return;
            }

            string deliveryNo = gridViewPosted.GetRowCellValue(gridViewPosted.FocusedRowHandle, "DeliveryNo") is DBNull
                ? null : Convert.ToString(gridViewPosted.GetRowCellValue(gridViewPosted.FocusedRowHandle, "DeliveryNo"));

            if (string.IsNullOrEmpty(deliveryNo))
            {
                BigAlert.Show("MISSING DELIVERY NO", "Could not resolve the Delivery No for the focused line.", MessageBoxIcon.Warning);
                return;
            }

            string lineOriginBranch = gridViewPosted.GetRowCellValue(gridViewPosted.FocusedRowHandle, "OriginBranch")?.ToString();
            string lineDestBranch = gridViewPosted.GetRowCellValue(gridViewPosted.FocusedRowHandle, "DestinationBranch")?.ToString();

            if (string.IsNullOrEmpty(lineOriginBranch) || string.IsNullOrEmpty(lineDestBranch))
            {
                BigAlert.Show("MISSING BRANCH INFO", "Could not resolve the origin/destination branch for this line -- it may predate this column. Please verify manually before reversing.", MessageBoxIcon.Warning);
                return;
            }

            if (XtraMessageBox.Show($"Reverse this dispatched line? This restores stock at Branch {lineOriginBranch} and, if nothing else remains, marks the delivery RETURNED.",
                    "Reverse Dispatch Line", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;

            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.sp_ReverseSTSInventoryTransfer", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.CommandTimeout = 120;
                cmd.Parameters.AddWithValue("@parmdevno", deliveryNo);
                cmd.Parameters.AddWithValue("@parmrefno", gridViewPosted.GetRowCellValue(gridViewPosted.FocusedRowHandle, "ReferenceNumber")?.ToString() ?? "");
                cmd.Parameters.AddWithValue("@parmpono", gridViewPosted.GetRowCellValue(gridViewPosted.FocusedRowHandle, "PONumber")?.ToString() ?? "");
                cmd.Parameters.AddWithValue("@parmprodno", gridViewPosted.GetRowCellValue(gridViewPosted.FocusedRowHandle, "ProductNo")?.ToString() ?? "");
                cmd.Parameters.AddWithValue("@parmqty", Convert.ToDecimal(gridViewPosted.GetRowCellValue(gridViewPosted.FocusedRowHandle, "ActualQty")));
                cmd.Parameters.AddWithValue("@parmbranchcode", lineDestBranch);
                cmd.Parameters.AddWithValue("@parmorigin", lineOriginBranch);
                cmd.Parameters.AddWithValue("@preparedby", Login.Fullname);
                cmd.Parameters.AddWithValue("@parmdevseqno", Convert.ToInt32(seqNoObj));

                try
                {
                    con.Open();
                    cmd.ExecuteNonQuery();
                    BigAlert.Show("REVERSED", "Dispatch line reversed successfully.", MessageBoxIcon.Information);
                    LoadPostedGrid();
                }
                catch (SqlException ex)
                {
                    BigAlert.Show("REVERSE FAILED", ex.Message, MessageBoxIcon.Error);
                }
            }
        }
    }
}
