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
using DevExpress.XtraReports.UI;

namespace SalesInventorySystem.Reporting
{
    public partial class SalesInvoiceDexEx : DevExpress.XtraEditors.XtraForm
    {
        public SalesInvoiceDexEx()
        {
            InitializeComponent();
            //this.gridView4.Columns["Quantity"].Width = 125;
            //this.gridView4.Columns["Unit"].Width = 75;
            //this.gridView4.Columns["ProductName"].Width = 300;
            //this.gridView4.Columns["Price"].Width = 150;
            //this.gridView4.Columns["Amount"].Width = 150;
        }

        private void SalesInvoiceDexEx_Load(object sender, EventArgs e)
        {

        }

        void print()
        {
            //string vatablesales, vatexemptsales, vatamount, addvat;
            bool isZeroRatedSale = Database.checkifExist($"SELECT TOP(1) 1 FROM dbo.BatchSalesSummary WHERE BranchCode='{Login.assignedBranch}' and ReferenceNo='{txtpono.Text}' AND ZeroRatedSale > 0");
            string remarks = Database.getSingleQuery($"SELECT TOP(1) Remarks FROM dbo.TransactionChargeSales WHERE ReferenceNo='{txtpono.Text}' AND BranchCode='{Login.assignedBranch}'","Remarks");
            bool isOnetimeDiscount = Database.checkifExist($"SELECT TOP(1) 1 FROM dbo.SalesDiscount WHERE OrderNo='{txtpono.Text}' and isErrorCorrect=0 and BranchCode='{Login.assignedBranch}'");
            string controlno = "";
            if (isOnetimeDiscount==true)
            {
                controlno = Database.getSingleQuery($"SELECT TOP(1) DiscIDNo FROM dbo.SalesDiscount WHERE OrderNo='{txtpono.Text}' AND BranchCode='{Login.assignedBranch}'", "DiscIDNo");
            }
            this.gridView4.Columns["isVat"].Visible = false;


            if (GlobalCache.CompanyName == "JFC")
            {
                DevExReportTemplate.SalesInvoiceJFC xct = new DevExReportTemplate.SalesInvoiceJFC();

                // Column widths measured directly off the physical Epson LQ310 sales invoice
                // form: Quantity=3.5cm, Unit=1.6cm, Articles=7.7cm, UnitPrice=4.2cm, Amount=3.8cm,
                // table inset 1.8cm from each paper edge (paper is 9.5in wide -- see
                // DevExReportTemplate/SalesInvoiceJFC.Designer.cs Margins, set to match).
                // HelperFunction.CopyGridControl() renders this GridControl into the report via a
                // WinControlContainer that reuses grid.Size (WinForms pixels) as report units
                // (hundredths of an inch) -- so 1 column-width unit here = 0.01in, and
                // cm-to-unit is a straight cm/2.54*100 conversion:
                //   Quantity  3.5cm -> 138
                //   Unit      1.6cm ->  63
                //   Articles  7.7cm -> 303
                //   UnitPrice 4.2cm -> 165
                //   Amount    3.8cm -> 150
                //this.gridView4.Columns["Cnt"].Visible = false; // not one of the 5 printed columns on the paper form
                this.gridView4.Columns["Cnt"].Width = 10; // not one of the 5 printed columns on the paper form
                this.gridView4.Columns["Quantity"].Width = 50;
                this.gridView4.Columns["Unit"].Width = 73;
                this.gridView4.Columns["ProductName"].Width = 303;
                this.gridView4.Columns["Price"].Width = 165;
                this.gridView4.Columns["Amount"].Width = 155;

                this.gridView4.Columns["Quantity"].AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Center;
                this.gridView4.Columns["Unit"].AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Center;
                this.gridView4.Columns["Price"].AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Default;
                this.gridView4.Columns["Amount"].AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Default;

                //this.gridView4.Columns["Cost"].Visible = false;

                double count = 0.0;
                for (int i = 0; i < gridView4.RowCount; i++)
                {
                    count += Convert.ToDouble(gridView4.GetRowCellValue(i, "Cnt"));
                }

                xct.xrcustname.Text = txtcustname.Text;
                xct.xrcontrolno.Text = controlno;
                xct.xraddress.Text = txtcustaddress.Text;
                xct.xrbusinessstyle.Text = remarks;
                xct.xrtin.Text = txtcusttin.Text;
                xct.xrlabeltotalcount.Text = count.ToString();

                string term = "", trm = "";
                term = txtterm.Text;
                if (term == "0")
                {
                    trm = "C.O.D";
                }
                else
                {
                    trm = term + " days";
                }
                xct.xrterms.Text = trm;
                xct.xrpreparedby.Text = Login.Fullname;
                //xct.xrdate.Text = String.Format(DateTime.Now.ToShortDateString();
                double zeroratedsales = 0.0;


                xct.xrdate.Text = String.Format("{0:MMMM dd yyyy}", DateTime.Now);

                xct.xrlblinvoicenum.Text = txtinvoiceno.Text;

                xct.xrlblVatableSales.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txtvatablesale.Text)); //VATABLE SALE
                xct.xrlblVatExemptSales.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txtvatexemptsale.Text)); // VAT EXEMPT SALE                                                                                             //zero rated
                xct.xrlblZeroRatedSales.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txtzeroratedsale.Text)); //ZERO RATED SALE
                xct.xrlblVatAmount.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txtvatamount.Text)); //VAT AMOUNT
                xct.xrlblTotalSalesVatInc.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txttotalsales.Text));// TOTAL SALES
                xct.xrlblLessVat.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txtlessvat.Text)); //LESS VAT
                xct.xrlblAmountNetofVat.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txtamountnetofvat.Text)); // NET OF VAT
                xct.xrlblLessDiscount.Text= String.Format("{0:0,0.00}", Convert.ToDouble(txtdiscount.Text)); // NET OF VAT
                xct.xrlblamountdue.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txtamountdue.Text)); // AMOUNT DUE
                xct.xrlbladdvat.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txtaddvat.Text)); //ADD VAT
                xct.xrlbltotalamountdue.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txttotalamountdue.Text)); //TOTAL AMOUNT DUE

                if (isZeroRatedSale)
                {
                    zeroratedsales = Convert.ToDouble(txttotalamountdue.Text) / 1.12;

                    xct.xrlblVatableSales.Text = "0";
                    xct.xrlblVatExemptSales.Text = "0";

                    xct.xrlblZeroRatedSales.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txttotalamountdue.Text));
                    xct.xrlblVatAmount.Text = "0";
                    xct.xrlblTotalSalesVatInc.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txttotalamountdue.Text));
                    xct.xrlblLessVat.Text = "0";
                    xct.xrlblAmountNetofVat.Text = "0";
                    xct.xrlblLessDiscount.Text = "0";
                    xct.xrlblamountdue.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txttotalamountdue.Text));
                    xct.xrlbladdvat.Text = "0";
                    xct.xrlbltotalamountdue.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txttotalamountdue.Text) / 1.12);
                }

                xct.Bands[BandKind.Detail].Controls.Add(HelperFunction.CopyGridControl(this.gridControl4));
                xct.Bands[BandKind.Detail].Font = new System.Drawing.Font("Tahoma", 10);
                ReportPrintTool report = new ReportPrintTool(xct);
                report.ShowRibbonPreviewDialog();
            }
            else
            {

                DevExReportTemplate.SalesInvoice xct = new DevExReportTemplate.SalesInvoice();
                this.gridView4.Columns["Quantity"].Width = 100;
                //this.gridView4.Columns["Quantity"].Width = 125; //ORIG
                this.gridView4.Columns["Unit"].Width = 78;
                this.gridView4.Columns["ProductName"].Width = 300;
                this.gridView4.Columns["Price"].Width = 110;
                this.gridView4.Columns["Amount"].Width = 155;

                this.gridView4.Columns["Unit"].AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Center;

                //this.gridView4.Columns["Cost"].Visible = false;

                double count = 0.0;
                for (int i = 0; i < gridView4.RowCount; i++)
                {
                    count += Convert.ToDouble(gridView4.GetRowCellValue(i, "Cnt"));
                }

                xct.xrcustname.Text = txtcustname.Text;
                xct.xrcontrolno.Text = controlno;
                xct.xraddress.Text = txtcustaddress.Text;
                xct.xrbusinessstyle.Text = remarks;
                xct.xrtin.Text = txtcusttin.Text;
                xct.xrlabeltotalcount.Text = count.ToString();

                string term = "", trm = "";
                term = txtterm.Text;
                if (term == "0")
                {
                    trm = "C.O.D";
                }
                else
                {
                    trm = term + " days";
                }
                xct.xrterms.Text = trm;
                xct.xrpreparedby.Text = Login.Fullname;
                //xct.xrdate.Text = String.Format(DateTime.Now.ToShortDateString();
                double zeroratedsales = 0.0;


                xct.xrdate.Text = String.Format("{0:MMMM dd yyyy}", DateTime.Now);

                xct.xrlblvatablesales.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txtvatablesale.Text)); //VATABLE SALE
                xct.xrlblvatexemptsales.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txtvatexemptsale.Text)); // VAT EXEMPT SALE
                                                                                                                     //zero rated
                xct.xrlblzeroratedsales.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txtzeroratedsale.Text)); //ZERO RATED SALE
                xct.xrlblvatamount.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txtvatamount.Text)); //VAT AMOUNT
                xct.xrlbltotalsales.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txttotalsales.Text));// TOTAL SALES
                xct.xrlbllessvat.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txtlessvat.Text)); //LESS VAT
                xct.xrlblnetofvat.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txtamountnetofvat.Text)); // NET OF VAT
                xct.xrlblamountdue.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txtamountdue.Text)); // AMOUNT DUE
                xct.xrlbladdvat.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txtaddvat.Text)); //ADD VAT
                xct.xrlbltotalamountdue.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txttotalamountdue.Text)); //TOTAL AMOUNT DUE

                if (isZeroRatedSale)
                {
                    zeroratedsales = Convert.ToDouble(txttotalamountdue.Text) / 1.12;

                    xct.xrlblvatablesales.Text = "0";
                    xct.xrlblvatexemptsales.Text = "0";

                    xct.xrlblzeroratedsales.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txttotalamountdue.Text));
                    xct.xrlblvatamount.Text = "0";
                    xct.xrlbltotalsales.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txttotalamountdue.Text));
                    xct.xrlbllessvat.Text = "0";
                    xct.xrlblnetofvat.Text = "0";
                    xct.xrlblamountdue.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txttotalamountdue.Text));
                    xct.xrlbladdvat.Text = "0";
                    xct.xrlbltotalamountdue.Text = String.Format("{0:0,0.00}", Convert.ToDouble(txttotalamountdue.Text) / 1.12);
                }

                xct.Bands[BandKind.Detail].Controls.Add(HelperFunction.CopyGridControl(this.gridControl4));
                xct.Bands[BandKind.Detail].Font = new System.Drawing.Font("Tahoma", 10);
                ReportPrintTool report = new ReportPrintTool(xct);
                report.ShowRibbonPreviewDialog();
            }

           
           
           
            

          
        }
     
        private void groupBox1_Enter(object sender, EventArgs e)
        {

        }

        private void simpleButton1_Click(object sender, EventArgs e)
        {
            print();
        }

        private void gridControl4_Click(object sender, EventArgs e)
        {

        }
    }
}