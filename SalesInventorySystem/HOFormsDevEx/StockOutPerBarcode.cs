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
    // Standard inventory-out module design (see CLAUDE.md): Barcode scan +
    // FIFO Auto selection + FIFO Manual (by shipment/batch) selection, staged
    // in a grid and posted atomically. Structurally mirrors
    // ConversionPerBarcode.cs's source-only deduction shape (no
    // destination/output side, no GL posting, no approval workflow) --
    // unlike DispatchPerBarcode.cs, a stock-out is a pure write-off, not a
    // branch-to-branch transfer.
    public partial class StockOutPerBarcode : DevExpress.XtraEditors.XtraForm, IResettableForm
    {
        private DataTable tableSource;
        private bool _dataLoaded;
        private bool _suppressSourceMethodChanged;
        private bool _suppressFifoTypeChanged;

        bool IsBarcodeMethod => Convert.ToString(radioGroupSourceMethod.EditValue) == "Barcode";
        bool IsManualFifo => Convert.ToString(radioGroupFifoType.EditValue) == "Manual";
        string SelectedBranch => Convert.ToString(slkBranch.EditValue);

        public StockOutPerBarcode()
        {
            InitializeComponent();
        }

        private void StockOutPerBarcode_Load(object sender, EventArgs e)
        {
            if (!_dataLoaded)
                LoadData();
        }

        public void LoadData()
        {
            if (_dataLoaded)
                return;

            LoadBranchDropdown();
            LoadCategoryDropdown();
            BuildSourceGridShape();
            FetchNewReferenceNumber();
            UpdateSourceMethodVisibility();
            LoadPostedGrid();
            EnableEntryControls(false);

            _dataLoaded = true;
        }

        // ------------------------------------------------------------------
        // Branch / Category (header)
        // ------------------------------------------------------------------
        void LoadBranchDropdown()
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand(
                "SELECT BranchCode, CONCAT(BranchCode, ' - ', BranchName) AS DisplayText FROM dbo.Branches ORDER BY BranchCode", con))
            {
                var dt = new DataTable();
                con.Open();
                using (var da = new SqlDataAdapter(cmd))
                    da.Fill(dt);

                slkBranch.Properties.View.Columns.Clear();
                slkBranch.Properties.DataSource = dt;
                slkBranch.Properties.DisplayMember = "DisplayText";
                slkBranch.Properties.ValueMember = "BranchCode";
            }
        }

        void LoadCategoryDropdown()
        {
            Database.displayComboBoxItems("SELECT Description FROM dbo.StockOutCategory ORDER BY Description", "Description", cboCategory);
        }

        private void slkBranch_EditValueChanged(object sender, EventArgs e)
        {
            if (tableSource != null && tableSource.Rows.Count > 0)
            {
                if (XtraMessageBox.Show(
                        "Switching the Branch will clear the items already staged for stock-out. Continue?",
                        "Change Branch", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                {
                    return;
                }
                tableSource.Rows.Clear();
                RecalculateTotals();
            }

            // A product/shipment picked under the previous branch is meaningless once the
            // branch changes (ProductCode alone doesn't guarantee it exists/means the same
            // thing at the new branch, and a Manual-mode LookupKey is tied to the old
            // branch's shipment/reference data entirely) -- clear it before reloading the
            // dropdown for the new branch, same as radioGroupFifoType_EditValueChanged does
            // on a FIFO Type switch.
            slueFifoProduct.EditValue = null;
            txtFifoQty.Value = 0;

            bool hasBranch = !string.IsNullOrEmpty(SelectedBranch);
            EnableEntryControls(hasBranch);

            if (hasBranch)
                LoadFifoProductDropdown();
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

        bool RequireBranch()
        {
            if (string.IsNullOrEmpty(SelectedBranch))
            {
                BigAlert.Show("NO BRANCH", "Please select a Branch first.", MessageBoxIcon.Warning);
                return false;
            }
            return true;
        }

        void FetchNewReferenceNumber()
        {
            txtRefNo.Text = IDGenerator.getIDNumberSP("sp_GetStockOutBarcodeNumber", "RefNo");
        }

        public async Task ResetUIAsync()
        {
            try
            {
                UseWaitCursor = true;
                // Only the DB call runs in the background -- assigning txtRefNo.Text must
                // happen back on the UI thread after the await resumes (cross-thread UI
                // access bug found and fixed today in DispatchPerBarcode.cs/ConversionPerBarcode.cs;
                // this form is built to avoid it from the start).
                string refNo = await Task.Run(() => IDGenerator.getIDNumberSP("sp_GetStockOutBarcodeNumber", "RefNo"));
                txtRefNo.Text = refNo;
                ClearEntryOnly();
            }
            finally
            {
                UseWaitCursor = false;
            }
        }

        void ClearEntryOnly()
        {
            if (tableSource == null)
                return;

            // Deliberately does NOT clear slkBranch, unlike Dispatch's ClearEntryOnly clearing
            // slkPONumber -- Branch has no dependent stale fields the way Dispatch's PO Number
            // does (Destination Branch/Effectivity Date), so staying on the same branch across
            // consecutive stock-outs is the more useful default, not an oversight.
            tableSource.Rows.Clear();
            slueFifoProduct.EditValue = null;
            txtFifoQty.Value = 0;
            txtScanBarcode.Text = "";
            cboCategory.EditValue = null;
            txtRemarks.Text = "";

            _suppressSourceMethodChanged = true;
            radioGroupSourceMethod.EditValue = "Barcode";
            _suppressSourceMethodChanged = false;

            _suppressFifoTypeChanged = true;
            radioGroupFifoType.EditValue = "Auto";
            _suppressFifoTypeChanged = false;
            if (!string.IsNullOrEmpty(SelectedBranch))
                LoadFifoProductDropdown();

            UpdateSourceMethodVisibility();
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
            using (var cmd = new SqlCommand("dbo.sp_GetInventoryForStockOutDropdown", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 50).Value = SelectedBranch;

                var dt = new DataTable();
                con.Open();
                using (var da = new SqlDataAdapter(cmd))
                    da.Fill(dt);

                slueFifoProduct.Properties.View.Columns.Clear();
                slueFifoProduct.Properties.DataSource = dt;
                slueFifoProduct.Properties.DisplayMember = "DisplayText";
                slueFifoProduct.Properties.ValueMember = "ProductCode";
            }
        }

        void LoadFifoProductDropdownManual()
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.sp_GetInventoryForStockOutManualDropdown", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 50).Value = SelectedBranch;

                var dt = new DataTable();
                con.Open();
                using (var da = new SqlDataAdapter(cmd))
                    da.Fill(dt);

                // ValueMember is the composite LookupKey ("Product||ShipmentNo||ReferenceCode")
                // the SP builds -- ProductCode alone isn't unique per row (one product can
                // have several batches in stock at once).
                slueFifoProduct.Properties.View.Columns.Clear();
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
            if (!RequireBranch()) return;

            string barcode = txtScanBarcode.Text.Trim();
            if (string.IsNullOrEmpty(barcode))
            {
                txtScanBarcode.Focus();
                return;
            }

            if (tableSource.Select($"Barcode = '{barcode.Replace("'", "''")}'").Length > 0)
            {
                BigAlert.Show("ALREADY SCANNED", "This barcode is already in the Stock-Out list.", MessageBoxIcon.Warning);
                txtScanBarcode.Text = "";
                txtScanBarcode.Focus();
                return;
            }

            DataRow found = LookupInventoryByBarcode(barcode);
            if (found == null)
            {
                BigAlert.Show("NOT FOUND", "No available inventory found for this barcode at the selected branch.", MessageBoxIcon.Warning);
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
            using (var cmd = new SqlCommand("dbo.sp_GetInventoryByBarcodeForStockOut", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@Barcode", SqlDbType.VarChar, 100).Value = barcode;
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 50).Value = SelectedBranch;

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
            if (!RequireBranch()) return;

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
                        "One of the FIFO lots for this product is already in the Stock-Out list from an earlier pick. Remove it first, or enter a smaller quantity.",
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
            using (var cmd = new SqlCommand("dbo.sp_GetStockOutFIFOBreakdown", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@ProductCode", SqlDbType.VarChar, 50).Value = productCode;
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 50).Value = SelectedBranch;
                cmd.Parameters.Add("@RequestedQty", SqlDbType.Decimal).Value = requestedQty;
                cmd.Parameters["@RequestedQty"].Precision = 18;
                cmd.Parameters["@RequestedQty"].Scale = 3;

                var pStaged = cmd.Parameters.AddWithValue("@AlreadyStaged", BuildStagedLotsTVP());
                pStaged.SqlDbType = SqlDbType.Structured;
                pStaged.TypeName = "dbo.tt_StockOutStagedLots";

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
            using (var cmd = new SqlCommand("dbo.sp_GetStockOutFIFOBreakdownByShipment", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@ProductCode", SqlDbType.VarChar, 50).Value = productCode;
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 50).Value = SelectedBranch;
                cmd.Parameters.Add("@ShipmentNo", SqlDbType.VarChar, 10).Value = shipmentNo;
                cmd.Parameters.Add("@ReferenceCode", SqlDbType.VarChar, 50).Value = string.IsNullOrEmpty(referenceCode) ? (object)DBNull.Value : referenceCode;
                cmd.Parameters.Add("@RequestedQty", SqlDbType.Decimal).Value = requestedQty;
                cmd.Parameters["@RequestedQty"].Precision = 18;
                cmd.Parameters["@RequestedQty"].Scale = 3;

                var pStaged = cmd.Parameters.AddWithValue("@AlreadyStaged", BuildStagedLotsTVP());
                pStaged.SqlDbType = SqlDbType.Structured;
                pStaged.TypeName = "dbo.tt_StockOutStagedLots";

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
            using (var cmd = new SqlCommand("dbo.spu_PostStockOutBarcode", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.CommandTimeout = 180;
                cmd.Parameters.Add("@RefNo", SqlDbType.VarChar, 20).Value = txtRefNo.Text;
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 50).Value = SelectedBranch;
                cmd.Parameters.Add("@Category", SqlDbType.VarChar, 100).Value = cboCategory.Text;
                cmd.Parameters.Add("@Remarks", SqlDbType.VarChar, 259).Value =
                    string.IsNullOrEmpty(txtRemarks.Text) ? (object)DBNull.Value : txtRemarks.Text;
                cmd.Parameters.Add("@PreparedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;

                var pLines = cmd.Parameters.AddWithValue("@Lines", lines);
                pLines.SqlDbType = SqlDbType.Structured;
                pLines.TypeName = "dbo.tt_StockOutBarcodeLines";

                try
                {
                    con.Open();
                    cmd.ExecuteNonQuery();
                    BigAlert.Show("SUCCESS", "Stock-out posted successfully.", MessageBoxIcon.Information);
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
            if (!RequireBranch())
                return false;

            if (string.IsNullOrEmpty(cboCategory.Text))
            {
                BigAlert.Show("NO CATEGORY", "Please select a Stock-Out Category.", MessageBoxIcon.Warning);
                return false;
            }

            if (tableSource.Rows.Count == 0)
            {
                BigAlert.Show("NO ITEMS", "Please add at least one item to stock out (scan a barcode or select a product).", MessageBoxIcon.Warning);
                return false;
            }

            if (string.IsNullOrEmpty(txtRefNo.Text))
            {
                BigAlert.Show("NO REFERENCE NUMBER", "Reference number could not be resolved. Please reopen this screen.", MessageBoxIcon.Warning);
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

            if (XtraMessageBox.Show("Clear all items staged for this Stock-Out?",
                    "Clear", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;

            tableSource.Rows.Clear();
            RecalculateTotals();
        }

        private void btnResetEntry_Click(object sender, EventArgs e)
        {
            if (tableSource.Rows.Count > 0)
            {
                if (XtraMessageBox.Show("Start a brand new Stock-Out? Unsaved items will be lost.",
                        "New Entry", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                    return;
            }
            _ = ResetUIAsync();
        }

        // ------------------------------------------------------------------
        // Posted tab
        // ------------------------------------------------------------------
        void LoadPostedGrid()
        {
            Database.display(
                "SELECT RefNo, BranchCode, Category, Remarks, TotalQty, TotalCost, Status, DateAdded, PreparedBy, " +
                "ReversedBy, DateReversed " +
                "FROM dbo.vw_StockOutBarcodeSummary WITH (NOLOCK) " +
                "ORDER BY DateAdded DESC",
                gridControlPosted, gridViewPosted);
            gridViewPosted.BestFitColumns();
        }

        private void btnRefreshPosted_Click(object sender, EventArgs e)
        {
            LoadPostedGrid();
        }

        string GetFocusedPostedRefNo()
        {
            if (gridViewPosted.FocusedRowHandle < 0) return null;
            var val = gridViewPosted.GetRowCellValue(gridViewPosted.FocusedRowHandle, "RefNo");
            return val == null ? null : val.ToString();
        }

        private void mnuViewDetails_Click(object sender, EventArgs e)
        {
            string refNo = GetFocusedPostedRefNo();
            if (string.IsNullOrEmpty(refNo)) return;

            StockOutPerBarcodeDetails details = new StockOutPerBarcodeDetails(refNo);
            details.ShowDialog();
        }

        private void mnuReversePosted_Click(object sender, EventArgs e)
        {
            string refNo = GetFocusedPostedRefNo();
            if (string.IsNullOrEmpty(refNo)) return;

            string status = gridViewPosted.GetRowCellValue(gridViewPosted.FocusedRowHandle, "Status").ToString();
            if (status != "POSTED")
            {
                BigAlert.Show("NOT POSTED", "This Stock-Out is not in POSTED status.", MessageBoxIcon.Warning);
                return;
            }

            if (XtraMessageBox.Show($"Reverse Stock-Out {refNo}? This restores the deducted stock.",
                    "Reverse Stock-Out", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;

            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.spu_ReverseStockOutBarcode", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@RefNo", SqlDbType.VarChar, 20).Value = refNo;
                cmd.Parameters.Add("@ReversedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;

                try
                {
                    con.Open();
                    cmd.ExecuteNonQuery();
                    BigAlert.Show("REVERSED", "Stock-out reversed successfully.", MessageBoxIcon.Information);
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
