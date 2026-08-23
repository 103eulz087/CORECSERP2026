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
    public partial class ConversionPerBarcode : DevExpress.XtraEditors.XtraForm, IResettableForm
    {
        private DataTable tableSource;
        private DataTable tableOutput;
        private bool _dataLoaded;
        private bool _suppressRadioChanged;
        private string _lastConversionType = "OneToMany";
        private bool _suppressSourceMethodChanged;

        bool IsOneToMany => Convert.ToString(radioGroupType.EditValue) == "OneToMany";
        bool IsBarcodeMethod => Convert.ToString(radioGroupSourceMethod.EditValue) == "Barcode";

        public ConversionPerBarcode()
        {
            InitializeComponent();
        }

        private void ConversionPerBarcode_Load(object sender, EventArgs e)
        {
            if (!_dataLoaded)
                LoadData();
        }

        public void LoadData()
        {
            if (_dataLoaded)
                return;

            txtBranch.Text = Login.assignedBranch;
            BuildSourceGridShape();
            BuildOutputGridShape();
            FetchNewReferenceNumber();
            LoadFifoProductDropdown();
            UpdateSourceMethodVisibility();
            LoadPostedGrid();

            _dataLoaded = true;
        }

        void LoadFifoProductDropdown()
        {
            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.sp_GetInventoryForConversionDropdown", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 50).Value = Login.assignedBranch;

                var dt = new DataTable();
                con.Open();
                using (var da = new SqlDataAdapter(cmd))
                    da.Fill(dt);

                // DisplayText (from the SP) is "Code - Description" (Code-Name display
                // convention); ValueMember stays ProductCode -- the popup grid itself
                // still shows ProductCode/Description/Available as separate columns.
                slueFifoProduct.Properties.View.Columns.Clear();
                slueFifoProduct.Properties.DataSource = null;
                slueFifoProduct.Properties.DataSource = dt;
                slueFifoProduct.Properties.DisplayMember = "DisplayText";
                slueFifoProduct.Properties.ValueMember = "ProductCode";
            }
        }

        void UpdateSourceMethodVisibility()
        {
            bool barcode = IsBarcodeMethod;

            labelControl7.Visible = barcode;
            txtScanBarcode.Visible = barcode;
            btnAddScan.Visible = barcode;

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

        public async Task ResetUIAsync()
        {
            try
            {
                UseWaitCursor = true;
                await Task.Run(() => FetchNewReferenceNumber());
                ClearEntryOnly(resetConversionType: true);
            }
            finally
            {
                UseWaitCursor = false;
            }
        }

        void FetchNewReferenceNumber()
        {
            txtRefNo.Text = IDGenerator.getIDNumberSP("sp_GetConversionBarcodeNumber", "ConversionRefNo");
        }

        void ClearEntryOnly(bool resetConversionType)
        {
            tableSource.Rows.Clear();
            tableOutput.Rows.Clear();
            txtCharge.Value = 0;
            txtOutputProductCode.Text = "";
            txtOutputProductDesc.Text = "";
            txtOutputQty.Value = 0;
            chkDriploss.Checked = false;
            slueFifoProduct.EditValue = null;
            txtFifoQty.Value = 0;

            if (resetConversionType)
            {
                _suppressRadioChanged = true;
                radioGroupType.EditValue = "OneToMany";
                _suppressRadioChanged = false;
                _lastConversionType = "OneToMany";

                _suppressSourceMethodChanged = true;
                radioGroupSourceMethod.EditValue = "Barcode";
                _suppressSourceMethodChanged = false;
                UpdateSourceMethodVisibility();
            }

            RecalculateTotals();
            txtScanBarcode.Text = "";
            if (IsBarcodeMethod) txtScanBarcode.Focus(); else slueFifoProduct.Focus();
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

        void BuildOutputGridShape()
        {
            tableOutput = new DataTable();
            tableOutput.Columns.Add("SeqNo", typeof(int));
            tableOutput.Columns.Add("ProductCode", typeof(string));
            tableOutput.Columns.Add("Description", typeof(string));
            tableOutput.Columns.Add("Qty", typeof(decimal));
            tableOutput.Columns.Add("IsDriploss", typeof(bool));
            gridControlOutput.DataSource = tableOutput;

            gridViewOutput.PopulateColumns();
            gridViewOutput.Columns["SeqNo"].Visible = false;
            gridViewOutput.Columns["ProductCode"].Caption = "Product Code";
            gridViewOutput.Columns["IsDriploss"].Caption = "Driploss";
            gridViewOutput.BestFitColumns();
        }

        void RecalculateTotals()
        {
            decimal totalSourceQty = 0m, totalSourceCost = 0m, totalOutputQty = 0m;
            foreach (DataRow r in tableSource.Rows)
            {
                totalSourceQty += Convert.ToDecimal(r["Qty"]);
                totalSourceCost += Convert.ToDecimal(r["Amount"]);
            }
            foreach (DataRow r in tableOutput.Rows)
            {
                totalOutputQty += Convert.ToDecimal(r["Qty"]);
            }
            txtTotalSourceQty.Text = totalSourceQty.ToString("N3");
            txtTotalSourceCost.Text = totalSourceCost.ToString("N2");
            txtTotalOutputQty.Text = totalOutputQty.ToString("N3");

            gridViewSource.BestFitColumns();
            gridViewOutput.BestFitColumns();
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
            string barcode = txtScanBarcode.Text.Trim();
            if (string.IsNullOrEmpty(barcode))
            {
                txtScanBarcode.Focus();
                return;
            }

            if (tableSource.Select($"Barcode = '{barcode.Replace("'", "''")}'").Length > 0)
            {
                BigAlert.Show("ALREADY SCANNED", "This barcode is already in the Source list.", MessageBoxIcon.Warning);
                txtScanBarcode.Text = "";
                txtScanBarcode.Focus();
                return;
            }

            DataRow found = LookupInventoryByBarcode(barcode);
            if (found == null)
            {
                BigAlert.Show("NOT FOUND", "No available inventory found for this barcode on your branch.", MessageBoxIcon.Warning);
                txtScanBarcode.Text = "";
                txtScanBarcode.Focus();
                return;
            }

            string scannedProduct = found["ProductCode"].ToString();

            if (!ValidateSameProductForOneToMany(scannedProduct, out string existingScanProduct))
            {
                BigAlert.Show(
                    "DIFFERENT PRODUCT",
                    "One To Many conversion requires all source items to be the same product. Expected " + existingScanProduct + " but scanned " + scannedProduct + ".",
                    MessageBoxIcon.Warning);
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
            row["ProductCode"] = scannedProduct;
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
            using (var cmd = new SqlCommand("dbo.sp_GetInventoryByBarcode", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@Barcode", SqlDbType.VarChar, 100).Value = barcode;
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 50).Value = Login.assignedBranch;

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

        bool ValidateSameProductForOneToMany(string productCode, out string existingProduct)
        {
            existingProduct = null;
            if (!IsOneToMany || tableSource.Rows.Count == 0) return true;
            existingProduct = tableSource.Rows[0]["ProductCode"].ToString();
            return existingProduct == productCode;
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
            if (slueFifoProduct.EditValue == null || string.IsNullOrEmpty(slueFifoProduct.EditValue.ToString()))
            {
                BigAlert.Show("NO PRODUCT", "Please select a product first.", MessageBoxIcon.Warning);
                return;
            }
            string productCode = slueFifoProduct.EditValue.ToString();

            decimal qty = txtFifoQty.Value;
            if (qty <= 0)
            {
                BigAlert.Show("INVALID QTY", "Please enter a valid quantity greater than zero.", MessageBoxIcon.Warning);
                txtFifoQty.Focus();
                return;
            }

            if (!ValidateSameProductForOneToMany(productCode, out string existingProduct))
            {
                BigAlert.Show(
                    "DIFFERENT PRODUCT",
                    "One To Many conversion requires all source items to be the same product. Expected " + existingProduct + ".",
                    MessageBoxIcon.Warning);
                return;
            }

            DataTable breakdown = GetFifoBreakdown(productCode, qty);
            decimal totalReturned = breakdown.Rows.Count == 0 ? 0m : breakdown.AsEnumerable().Sum(r => Convert.ToDecimal(r["Qty"]));

            if (totalReturned < qty)
            {
                BigAlert.Show(
                    "INSUFFICIENT STOCK",
                    $"Only {totalReturned:N3} available for this product (requested {qty:N3}).",
                    MessageBoxIcon.Warning);
                return;
            }

            // A lot already staged from an earlier pick (this method or barcode scan) can't be
            // walked into twice -- sp_GetInventoryFIFOBreakdown already nets out staged qty per
            // lot, but a fully-exhausted lot could still resurface as a fresh 0-qty edge case;
            // this is the same-InventorySeqNo guard mirroring spu_PostConversionBarcode's own.
            foreach (DataRow r in breakdown.Rows)
            {
                int invSeqNo = Convert.ToInt32(r["SequenceNumber"]);
                if (tableSource.Select($"InventorySeqNo = {invSeqNo}").Length > 0)
                {
                    BigAlert.Show(
                        "LOT ALREADY STAGED",
                        "One of the FIFO lots for this product is already in the Source list from an earlier pick. Remove it first, or enter a smaller quantity.",
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
            using (var cmd = new SqlCommand("dbo.sp_GetInventoryFIFOBreakdown", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@ProductCode", SqlDbType.VarChar, 50).Value = productCode;
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 50).Value = Login.assignedBranch;
                cmd.Parameters.Add("@RequestedQty", SqlDbType.Decimal).Value = requestedQty;
                cmd.Parameters["@RequestedQty"].Precision = 18;
                cmd.Parameters["@RequestedQty"].Scale = 3;

                var pStaged = cmd.Parameters.AddWithValue("@AlreadyStaged", BuildStagedLotsTVP());
                pStaged.SqlDbType = SqlDbType.Structured;
                pStaged.TypeName = "dbo.tt_ConversionStagedLots";

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
        // Destination / output items
        // ------------------------------------------------------------------
        private void btnSearchProduct_Click(object sender, EventArgs e)
        {
            HOForms.SearchProducts.isdone = false;
            HOForms.SearchProducts searchProd = new HOForms.SearchProducts();
            searchProd.FormClosed += SearchProd_FormClosed;
            searchProd.Show();
        }

        void SearchProd_FormClosed(object sender, FormClosedEventArgs e)
        {
            if (!HOForms.SearchProducts.isdone)
                return;

            txtOutputProductCode.Text = HOForms.SearchProducts.prodcode;
            txtOutputProductDesc.Text = HOForms.SearchProducts.prodname;
            txtOutputQty.Focus();
        }

        private void btnAddOutput_Click(object sender, EventArgs e)
        {
            if (string.IsNullOrEmpty(txtOutputProductCode.Text))
            {
                BigAlert.Show("NO PRODUCT", "Please select a destination product first.", MessageBoxIcon.Warning);
                return;
            }

            decimal qty = txtOutputQty.Value;
            if (qty <= 0)
            {
                BigAlert.Show("INVALID QTY", "Please enter a valid quantity greater than zero.", MessageBoxIcon.Warning);
                txtOutputQty.Focus();
                return;
            }

            bool isDriploss = chkDriploss.Checked;

            if (!IsOneToMany && !isDriploss &&
                tableOutput.Select("IsDriploss = false").Length > 0)
            {
                BigAlert.Show(
                    "ONE DESTINATION ONLY",
                    "Many To One conversion only allows one non-driploss destination product.",
                    MessageBoxIcon.Warning);
                return;
            }

            if (tableOutput.Select($"ProductCode = '{txtOutputProductCode.Text.Replace("'", "''")}' AND IsDriploss = {(isDriploss ? "true" : "false")}").Length > 0)
            {
                BigAlert.Show("ALREADY ADDED", "This product/driploss line is already in the Destination list.", MessageBoxIcon.Warning);
                return;
            }

            DataRow row = tableOutput.NewRow();
            row["SeqNo"] = tableOutput.Rows.Count + 1;
            row["ProductCode"] = txtOutputProductCode.Text;
            row["Description"] = txtOutputProductDesc.Text;
            row["Qty"] = qty;
            row["IsDriploss"] = isDriploss;
            tableOutput.Rows.Add(row);

            RecalculateTotals();

            txtOutputProductCode.Text = "";
            txtOutputProductDesc.Text = "";
            txtOutputQty.Value = 0;
            chkDriploss.Checked = false;
            txtScanBarcode.Focus();
        }

        private void mnuRemoveOutputLine_Click(object sender, EventArgs e)
        {
            if (gridViewOutput.FocusedRowHandle < 0) return;
            gridViewOutput.DeleteSelectedRows();
            RecalculateTotals();
        }

        private void radioGroupType_EditValueChanged(object sender, EventArgs e)
        {
            if (_suppressRadioChanged) return;

            string newType = Convert.ToString(radioGroupType.EditValue);

            if (tableSource != null && tableOutput != null &&
                (tableSource.Rows.Count > 0 || tableOutput.Rows.Count > 0))
            {
                if (XtraMessageBox.Show(
                        "Changing the conversion type will clear the Source and Destination items already entered. Continue?",
                        "Change Conversion Type", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                {
                    _suppressRadioChanged = true;
                    radioGroupType.EditValue = _lastConversionType;
                    _suppressRadioChanged = false;
                    return;
                }

                tableSource.Rows.Clear();
                tableOutput.Rows.Clear();
                RecalculateTotals();
            }

            _lastConversionType = newType;
        }

        // ------------------------------------------------------------------
        // Submit / Post
        // ------------------------------------------------------------------
        private void btnSubmit_Click(object sender, EventArgs e)
        {
            if (!ValidateForSubmit(out decimal charge))
                return;

            gridViewSource.CloseEditor();
            gridViewOutput.CloseEditor();

            DataTable sourceTvp = BuildSourceTVP();
            DataTable outputTvp = BuildOutputTVP();

            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.spu_PostConversionBarcode", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.CommandTimeout = 180;
                cmd.Parameters.Add("@ConversionRefNo", SqlDbType.VarChar, 20).Value = txtRefNo.Text;
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 50).Value = Login.assignedBranch;
                cmd.Parameters.Add("@ConversionType", SqlDbType.VarChar, 20).Value = IsOneToMany ? "OneToMany" : "ManyToOne";
                cmd.Parameters.Add("@CuttingCharge", SqlDbType.Decimal).Value = charge;
                cmd.Parameters["@CuttingCharge"].Precision = 18;
                cmd.Parameters["@CuttingCharge"].Scale = 2;
                cmd.Parameters.Add("@ConvertedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;

                var pSource = cmd.Parameters.AddWithValue("@SourceLines", sourceTvp);
                pSource.SqlDbType = SqlDbType.Structured;
                pSource.TypeName = "dbo.tt_ConversionBarcodeSourceLines";

                var pOutput = cmd.Parameters.AddWithValue("@OutputLines", outputTvp);
                pOutput.SqlDbType = SqlDbType.Structured;
                pOutput.TypeName = "dbo.tt_ConversionBarcodeOutputLines";

                try
                {
                    con.Open();
                    cmd.ExecuteNonQuery();
                    BigAlert.Show("SUCCESS", "Conversion posted successfully.", MessageBoxIcon.Information);
                    _ = ResetUIAsync();
                    LoadPostedGrid();
                }
                catch (SqlException ex)
                {
                    BigAlert.Show("POST FAILED", ex.Message, MessageBoxIcon.Error);
                }
            }
        }

        bool ValidateForSubmit(out decimal charge)
        {
            charge = 0m;

            if (tableSource.Rows.Count == 0)
            {
                BigAlert.Show("NO SOURCE ITEMS", "Please add at least one source item (scan a barcode or select a product).", MessageBoxIcon.Warning);
                return false;
            }
            if (tableOutput.Rows.Count == 0)
            {
                BigAlert.Show("NO DESTINATION ITEMS", "Please add at least one destination item.", MessageBoxIcon.Warning);
                return false;
            }
            charge = txtCharge.Value;
            if (charge < 0)
            {
                BigAlert.Show("INVALID CHARGE", "Please enter a valid Cutting Charge (0 or more).", MessageBoxIcon.Warning);
                return false;
            }

            if (IsOneToMany)
            {
                int distinctProducts = tableSource.AsEnumerable()
                    .Select(r => r["ProductCode"].ToString()).Distinct().Count();
                if (distinctProducts != 1)
                {
                    BigAlert.Show("INVALID SOURCE", "One To Many conversion requires all source items to be the same product.", MessageBoxIcon.Warning);
                    return false;
                }
            }
            else
            {
                int nonDriplossLines = tableOutput.Select("IsDriploss = false").Length;
                if (nonDriplossLines != 1)
                {
                    BigAlert.Show("INVALID DESTINATION", "Many To One conversion requires exactly one non-driploss destination product.", MessageBoxIcon.Warning);
                    return false;
                }
            }

            decimal totalSourceQty = tableSource.AsEnumerable().Sum(r => Convert.ToDecimal(r["Qty"]));
            decimal totalDriploss = tableOutput.Select("IsDriploss = true").Sum(r => Convert.ToDecimal(r["Qty"]));
            decimal totalNonDriploss = tableOutput.Select("IsDriploss = false").Sum(r => Convert.ToDecimal(r["Qty"]));

            if (Math.Abs((totalNonDriploss + totalDriploss) - totalSourceQty) > 0.001m)
            {
                BigAlert.Show(
                    "QUANTITY MISMATCH",
                    $"Destination quantity (including driploss) must equal total source quantity.\nSource: {totalSourceQty:N3}  Destination: {(totalNonDriploss + totalDriploss):N3}",
                    MessageBoxIcon.Warning);
                return false;
            }

            return true;
        }

        DataTable BuildSourceTVP()
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

        DataTable BuildOutputTVP()
        {
            var dt = new DataTable();
            dt.Columns.Add("ProductCode", typeof(string));
            dt.Columns.Add("Description", typeof(string));
            dt.Columns.Add("Qty", typeof(decimal));
            dt.Columns.Add("IsDriploss", typeof(bool));

            foreach (DataRow r in tableOutput.Rows)
            {
                dt.Rows.Add(
                    r["ProductCode"].ToString(),
                    r["Description"].ToString(),
                    Convert.ToDecimal(r["Qty"]),
                    Convert.ToBoolean(r["IsDriploss"]));
            }
            return dt;
        }

        private void btnClearAll_Click(object sender, EventArgs e)
        {
            if (tableSource.Rows.Count == 0 && tableOutput.Rows.Count == 0) return;

            if (XtraMessageBox.Show("Clear all source and destination items for this Conversion Ref No?",
                    "Clear", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;

            ClearEntryOnly(resetConversionType: false);
        }

        private void btnResetEntry_Click(object sender, EventArgs e)
        {
            if (tableSource.Rows.Count > 0 || tableOutput.Rows.Count > 0)
            {
                if (XtraMessageBox.Show("Start a brand new Conversion? Unsaved items will be lost.",
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
                "SELECT ConversionRefNo, ConversionType, TotalSourceQty, TotalSourceCost, CuttingCharge, " +
                "TotalDriplossQty, MaterialRatePerUnit, ChargeRatePerLine, Status, DateConverted, ConvertedBy, " +
                "ReversedBy, DateReversed " +
                "FROM dbo.vw_ConversionBarcodeSummary WITH (NOLOCK) " +
                "WHERE BranchCode = '" + Login.assignedBranch.Replace("'", "''") + "' " +
                "ORDER BY DateConverted DESC",
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
            var val = gridViewPosted.GetRowCellValue(gridViewPosted.FocusedRowHandle, "ConversionRefNo");
            return val == null ? null : val.ToString();
        }

        private void mnuViewDetails_Click(object sender, EventArgs e)
        {
            string refNo = GetFocusedPostedRefNo();
            if (string.IsNullOrEmpty(refNo)) return;

            ConversionPerBarcodeDetails details = new ConversionPerBarcodeDetails(refNo);
            details.ShowDialog();
        }

        private void mnuCopyToNewEntry_Click(object sender, EventArgs e)
        {
            if (gridViewPosted.FocusedRowHandle < 0) return;

            string conversionType = gridViewPosted.GetRowCellValue(gridViewPosted.FocusedRowHandle, "ConversionType").ToString();
            string charge = gridViewPosted.GetRowCellValue(gridViewPosted.FocusedRowHandle, "CuttingCharge").ToString();

            xtraTabControl1.SelectedTabPage = xtraTabPageNewEntry;
            _ = ResetUIAsyncThenApply(conversionType, charge);
        }

        async Task ResetUIAsyncThenApply(string conversionType, string charge)
        {
            await ResetUIAsync();
            _suppressRadioChanged = true;
            radioGroupType.EditValue = conversionType == "OneToMany" ? "OneToMany" : "ManyToOne";
            _suppressRadioChanged = false;
            _lastConversionType = Convert.ToString(radioGroupType.EditValue);
            txtCharge.Value = decimal.TryParse(charge, out decimal chargeValue) ? chargeValue : 0;
        }

        private void mnuReversePosted_Click(object sender, EventArgs e)
        {
            string refNo = GetFocusedPostedRefNo();
            if (string.IsNullOrEmpty(refNo)) return;

            string status = gridViewPosted.GetRowCellValue(gridViewPosted.FocusedRowHandle, "Status").ToString();
            if (status != "POSTED")
            {
                BigAlert.Show("NOT POSTED", "This Conversion is not in POSTED status.", MessageBoxIcon.Warning);
                return;
            }

            if (XtraMessageBox.Show($"Reverse Conversion {refNo}? This restores source stock and zeroes out the converted stock (only allowed if it hasn't been moved yet).",
                    "Reverse Conversion", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;

            using (var con = Database.getConnection())
            using (var cmd = new SqlCommand("dbo.spu_ReverseConversionBarcode", con))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@ConversionRefNo", SqlDbType.VarChar, 20).Value = refNo;
                cmd.Parameters.Add("@ReversedBy", SqlDbType.VarChar, 50).Value = Login.Fullname;

                try
                {
                    con.Open();
                    cmd.ExecuteNonQuery();
                    BigAlert.Show("REVERSED", "Conversion reversed successfully.", MessageBoxIcon.Information);
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
