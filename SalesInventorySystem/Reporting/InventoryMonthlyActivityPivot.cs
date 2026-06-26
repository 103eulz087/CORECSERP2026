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
using DevExpress.LookAndFeel;
using DevExpress.XtraPivotGrid;
using System.Globalization;
using DevExpress.XtraEditors.Controls;
using SalesInventorySystem.Classes;

namespace SalesInventorySystem.Reporting
{
    public partial class InventoryMonthlyActivityPivot : DevExpress.XtraEditors.XtraForm
    {
        object objbrcode = null;
        string globalbrcode;
        public InventoryMonthlyActivityPivot()
        {
            InitializeComponent();
            loadComboBoxValues();
        }


        void loadComboBoxValues()
        {
            // 1. Populate Months (January - December)
            cmbFromMonth.Properties.Items.Clear();
            cmbToMonth.Properties.Items.Clear();
            for (int i = 1; i <= 12; i++)
            {
                // This gets the localized month name (e.g., "March")
                string monthName = CultureInfo.CurrentCulture.DateTimeFormat.GetMonthName(i);
                cmbFromMonth.Properties.Items.Add(new ImageComboBoxItem(monthName, i));
                cmbToMonth.Properties.Items.Add(new ImageComboBoxItem(monthName, i));
            }

            // 2. Populate Years (Dynamic range: 5 years back, 1 year forward)
            int currentYear = DateTime.Now.Year; // It's 2026!
            cmbFromYear.Properties.Items.Clear();
            cmbToYear.Properties.Items.Clear();
            for (int y = currentYear - 5; y <= currentYear + 1; y++)
            {
                cmbFromYear.Properties.Items.Add(y);
                cmbToYear.Properties.Items.Add(y);
            }

            // 3. Set Defaults to the CURRENT Month and Year
            // (Because users usually want to see the most recent data first)
            cmbFromMonth.SelectedIndex = DateTime.Now.Month - 1;
            cmbToMonth.SelectedIndex = DateTime.Now.Month - 1;
            cmbFromYear.EditValue = currentYear;
            cmbToYear.EditValue = currentYear;
        }
        // 1. Made the method ASYNC so the UI never freezes
        private async Task ExecuteAsync()
        {
            // Prevent the user from clicking the button twice while it's loading
            // Assuming you call this from a button named btnExecute
            // btnExecute.Enabled = false; 

            DataTable table = new DataTable();

            try
            {
                // 2. OFFLOAD DATABASE WORK TO A BACKGROUND THREAD
                // This keeps the UI perfectly smooth while SQL Server thinks
                await Task.Run(() =>
                {
                    using (SqlConnection con = Database.getConnection())
                    using (SqlCommand com = new SqlCommand("sp_GenerateInventoryMonthlyReport", con))
                    {
                        com.CommandType = CommandType.StoredProcedure;
                        com.Parameters.AddWithValue("@parmbrcode", globalbrcode);
                        com.Parameters.AddWithValue("@datefrom", datefrom.DateTime.Date); // Ensure you pass valid Dates, not strings
                        com.Parameters.AddWithValue("@dateto", dateto.DateTime.Date);

                        using (SqlDataAdapter adapter = new SqlDataAdapter(com))
                        {
                            adapter.Fill(table);
                        }
                    }
                });

                // 3. UI PERFORMANCE LOCKS
                // Lock the PivotGrid so it doesn't recalculate math while we build it
                pivotGridControl1.BeginUpdate();

                pivotGridControl1.Fields.Clear();
                pivotGridControl1.DataSource = table;

                // 4. BUILD THE FIELDS
                PivotGridField fielddescription = new PivotGridField("Category", PivotArea.RowArea) { AreaIndex = 0 };
                PivotGridField fieldprodname = new PivotGridField("Description", PivotArea.RowArea) { Caption = "PRODUCT NAME", AreaIndex = 1 };

                PivotGridField fieldtransdate = new PivotGridField("TransactionDate", PivotArea.ColumnArea) { Caption = "TRANSACTION DATE" };

                // Define Data Fields with formatting
                PivotGridField fldbeginning = CreateDataField("BeginningQty");
                PivotGridField fldpurchases = CreateDataField("Purchases");
                PivotGridField fldsts = CreateDataField("STS");
                PivotGridField fldstsavariance = CreateDataField("STSVariance");
                PivotGridField fldreturn = CreateDataField("ReturnTransfer");
                PivotGridField fldconvin = CreateDataField("ConversionIn");
                PivotGridField fldconvout = CreateDataField("ConversionOut");
                PivotGridField fldcost = CreateDataField("CostOfSales");
                PivotGridField fldreturnedsupp = CreateDataField("ReturnedToSupplier");
                PivotGridField fldbo = CreateDataField("BadOrder");
                PivotGridField fldending = CreateDataField("EndingQty");

                // Add all fields at once
                pivotGridControl1.Fields.AddRange(new PivotGridField[] {
            fielddescription, fieldprodname, fieldtransdate,
            fldbeginning,fldpurchases, fldsts,fldstsavariance, fldreturn, fldconvin,fldconvout,
            fldcost, fldreturnedsupp, fldbo, fldending
        });
                pivotGridControl1.OptionsView.ShowColumnGrandTotals = false;
                pivotGridControl1.OptionsView.ShowRowGrandTotals = false;

                //pivotGridControl1.CustomAppearance += (s, e) =>
                //{
                //    if (e.DataField != null)
                //    {
                //        // Highlight TOTALIN, TOTALOUT, EndingQty columns
                //        if (e.DataField.FieldName == "TOTALIN" ||
                //            e.DataField.FieldName == "TOTALOUT" ||
                //            e.DataField.FieldName == "EndingQty")
                //        {
                //            e.Appearance.BackColor = Color.LightYellow;
                //            e.Appearance.Font = new Font(e.Appearance.Font, FontStyle.Bold);
                //        }

                //        // Highlight ConversionOut and SalesOut values in red if not zero
                //        if ((e.DataField.FieldName == "ConversionOut" ||
                //             e.DataField.FieldName == "SalesOut") &&
                //            e.Value != null && e.Value is decimal val && val != 0)
                //        {
                //            e.Appearance.ForeColor = Color.Red;
                //            e.Appearance.Font = new Font(e.Appearance.Font, FontStyle.Bold);
                //        }
                //    }
                //};

                pivotGridControl1.CustomAppearance += (s, e) =>
                {
                    if (e.DataField != null)
                    {
                        // 1. Highlight TOTALIN, TOTALOUT, EndingQty columns (Your existing logic)
                        //if (e.DataField.FieldName == "TOTALIN" ||
                        //    e.DataField.FieldName == "TOTALOUT" )
                        //{
                        //    e.Appearance.BackColor = Color.LightYellow;
                        //    e.Appearance.Font = new Font(e.Appearance.Font, FontStyle.Bold);
                        //}

                        if (e.DataField.FieldName == "EndingQty")
                        {
                            e.Appearance.BackColor = Color.Yellow;
                            e.Appearance.Font = new Font(e.Appearance.Font, FontStyle.Bold);
                        }

                        // 2. Highlight ConversionOut and SalesOut values in red if not zero (Your existing logic)
                        //if ((e.DataField.FieldName == "ConversionOut" || e.DataField.FieldName == "ReturnOUT" ||
                        //     e.DataField.FieldName == "SalesOut") &&
                        //    e.Value != null)
                        //{
                        //    // Safely convert to decimal regardless of underlying type
                        //    decimal val = Convert.ToDecimal(e.Value);
                        //    if (val != 0)
                        //    {
                        //        e.Appearance.ForeColor = Color.Red;
                        //        e.Appearance.Font = new Font(e.Appearance.Font, FontStyle.Bold);
                        //    }
                        //}

                        // =================================================================================
                        // 3. NEW: THE ANOMALY DETECTOR (Ending Qty vs Next Day's Beginning Qty)
                        // =================================================================================

                        // We only want to run this check when we are painting the "Beginning" cell
                        if (e.DataField.FieldName == "BeginningQty")
                        {
                            int currentColumnIndex = e.ColumnIndex;

                            // We can't check yesterday if today is the very first day in the grid
                            if (currentColumnIndex > 0)
                            {
                                // LOOK BACK IN TIME: Just subtract 1 from the column index!
                                // Because "EndingQty" is your last field and "Beginning" is your first field,
                                // the column immediately to the left (-1) is ALWAYS yesterday's EndingQty.
                                object yesterdayEndingObj = pivotGridControl1.GetCellValue(currentColumnIndex - 1, e.RowIndex);

                                object todayBeginningObj = e.Value;

                                // Safely convert both to decimals to avoid type mismatch crashes
                                decimal yesterdayEnding = yesterdayEndingObj == null ? 0 : Convert.ToDecimal(yesterdayEndingObj);
                                decimal todayBeginning = todayBeginningObj == null ? 0 : Convert.ToDecimal(todayBeginningObj);

                                // TRIGGER THE ANOMALY HIGHLIGHT!
                                if (yesterdayEnding != todayBeginning)
                                {
                                    // Paint the Beginning Qty cell RED with WHITE text to make it scream "ERROR"
                                    e.Appearance.BackColor = Color.Firebrick;
                                    e.Appearance.ForeColor = Color.White;
                                    e.Appearance.Font = new Font(e.Appearance.Font, FontStyle.Bold);
                                }
                            }
                        }
                    }
                };

                // --- FONT OPTIMIZATION FOR REPORTING ---

                // 1. Data Cells: Clean, readable, standard size
                pivotGridControl1.Appearance.Cell.Font = new Font("Segoe UI", 9f, FontStyle.Regular);

                // 2. Column and Row Headers (The gray areas): Slightly larger and Bold
                pivotGridControl1.Appearance.HeaderArea.Font = new Font("Segoe UI", 8.75f, FontStyle.Bold);
                pivotGridControl1.Appearance.FieldValue.Font = new Font("Segoe UI", 8.75f, FontStyle.Bold);

                // 3. Grand Totals: Keep the same size as data, but make them Bold
                pivotGridControl1.Appearance.GrandTotalCell.Font = new Font("Segoe UI", 9f, FontStyle.Bold);
                pivotGridControl1.Appearance.TotalCell.Font = new Font("Segoe UI", 9f, FontStyle.Bold);

                // Optional but highly recommended: Center the column headers for a cleaner look
                pivotGridControl1.Appearance.HeaderArea.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Center;
                // 5. SKINNING
                UserLookAndFeel.Default.Style = LookAndFeelStyle.Skin;
                UserLookAndFeel.Default.SkinName = "Office 2019 Colorful";
            }
            catch (SqlException ee)
            {
                XtraMessageBox.Show("Database Error: " + ee.Message, "Error", System.Windows.Forms.MessageBoxButtons.OK, System.Windows.Forms.MessageBoxIcon.Error);
            }
            catch (Exception ex)
            {
                XtraMessageBox.Show("Application Error: " + ex.Message, "Error", System.Windows.Forms.MessageBoxButtons.OK, System.Windows.Forms.MessageBoxIcon.Error);
            }
            finally
            {
                // 6. UNLOCK THE PIVOT GRID
                // This forces exactly ONE single redraw, making it lightning fast.
                pivotGridControl1.EndUpdate();
                pivotGridControl1.BestFit(pivotGridControl1.Fields["Description"]);

                // btnExecute.Enabled = true;
            }
        }

      
        // Helper method to keep your code clean
        private PivotGridField CreateDataField(string fieldName)
        {
            PivotGridField field = new PivotGridField(fieldName, PivotArea.DataArea);
            field.CellFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
            field.CellFormat.FormatString = "n2";
            return field;
        }
        
        private async void simpleButton1_Click(object sender, EventArgs e)
        {
            if ((Login.assignedBranch == "888" && String.IsNullOrEmpty(txtbranch.Text) ) || String.IsNullOrEmpty(datefrom.Text) || String.IsNullOrEmpty(dateto.Text))
            {
                XtraMessageBox.Show("Field must not Empty");
                return;
            }
            else
            {
                simpleButton1.Enabled = false;
                Cursor = Cursors.WaitCursor;
                await ExecuteAsync();
                Cursor = Cursors.Default;
                simpleButton1.Enabled = true;
            }
        }

        private void InventoryDailyActivityPivot_Load(object sender, EventArgs e)
        {
            //xtraTabPage2.PageVisible = false;
            if (Login.assignedBranch == "888")
            {
                Database.displaySearchlookupEdit("SELECT BranchCode,BranchName FROM dbo.Branches order by BranchCode", txtbranch, "BranchName", "BranchName");
                //Database.displaySearchlookupEdit("SELECT BranchCode,BranchName FROM dbo.Branches order by BranchCode", txtbranchmonthly, "BranchName", "BranchName");
            }
            else
            {
                labelbranch.Visible = false;
                txtbranch.Visible = false;
                
                globalbrcode = Login.assignedBranch;
            }
         }

        private void txtbranch_EditValueChanged(object sender, EventArgs e)
        {
            objbrcode = SearchLookUpClass.getSingleValue(txtbranch, "BranchCode");
            globalbrcode = objbrcode.ToString();
        }

        

        private void txtbranchmonthly_EditValueChanged(object sender, EventArgs e)
        {
            objbrcode = SearchLookUpClass.getSingleValue(txtbranchmonthly, "BranchCode");
            globalbrcode = objbrcode.ToString();
        }
    }
}