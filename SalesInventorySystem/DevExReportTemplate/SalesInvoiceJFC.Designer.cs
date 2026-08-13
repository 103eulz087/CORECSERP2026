namespace SalesInventorySystem.DevExReportTemplate
{
    partial class SalesInvoiceJFC
    {
        /// <summary>
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary> 
        /// Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Designer generated code

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            DevExpress.XtraReports.UI.XRWatermark xrWatermark1 = new DevExpress.XtraReports.UI.XRWatermark();
            this.Detail = new DevExpress.XtraReports.UI.DetailBand();
            this.TopMargin = new DevExpress.XtraReports.UI.TopMarginBand();
            this.BottomMargin = new DevExpress.XtraReports.UI.BottomMarginBand();
            this.xrpreparedby = new DevExpress.XtraReports.UI.XRLabel();
            this.xrdeliveredby = new DevExpress.XtraReports.UI.XRLabel();
            this.ReportHeader = new DevExpress.XtraReports.UI.ReportHeaderBand();
            this.xrcontrolno = new DevExpress.XtraReports.UI.XRLabel();
            this.xrterms = new DevExpress.XtraReports.UI.XRLabel();
            this.xrbusinessstyle = new DevExpress.XtraReports.UI.XRLabel();
            this.xrdate = new DevExpress.XtraReports.UI.XRLabel();
            this.xrcustname = new DevExpress.XtraReports.UI.XRLabel();
            this.xrtin = new DevExpress.XtraReports.UI.XRLabel();
            this.xraddress = new DevExpress.XtraReports.UI.XRLabel();
            this.PageFooter = new DevExpress.XtraReports.UI.PageFooterBand();
            this.xrlblinvoicenum = new DevExpress.XtraReports.UI.XRLabel();
            this.xrlabeltotalcount = new DevExpress.XtraReports.UI.XRLabel();
            this.xrlbladdvat = new DevExpress.XtraReports.UI.XRLabel();
            this.xrlblLessWithholdingTax = new DevExpress.XtraReports.UI.XRLabel();
            this.xrlblTotal = new DevExpress.XtraReports.UI.XRLabel();
            this.xrlblVatableSales = new DevExpress.XtraReports.UI.XRLabel();
            this.xrlblamountdue = new DevExpress.XtraReports.UI.XRLabel();
            this.xrlbltotalamountdue = new DevExpress.XtraReports.UI.XRLabel();
            this.xrlblVatExemptSales = new DevExpress.XtraReports.UI.XRLabel();
            this.xrlblVatAmount = new DevExpress.XtraReports.UI.XRLabel();
            this.xrlblZeroRatedSales = new DevExpress.XtraReports.UI.XRLabel();
            this.xrlblAmountNetofVat = new DevExpress.XtraReports.UI.XRLabel();
            this.xrlblLessDiscount = new DevExpress.XtraReports.UI.XRLabel();
            this.xrlblLessVat = new DevExpress.XtraReports.UI.XRLabel();
            this.xrlblTotalSalesVatInc = new DevExpress.XtraReports.UI.XRLabel();
            ((System.ComponentModel.ISupportInitialize)(this)).BeginInit();
            // 
            // Detail
            // 
            this.Detail.HeightF = 354.9999F;
            this.Detail.Name = "Detail";
            this.Detail.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.Detail.TextAlignment = DevExpress.XtraPrinting.TextAlignment.TopLeft;
            // 
            // TopMargin
            // 
            this.TopMargin.Name = "TopMargin";
            this.TopMargin.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.TopMargin.TextAlignment = DevExpress.XtraPrinting.TextAlignment.TopLeft;
            // 
            // BottomMargin
            // 
            this.BottomMargin.Controls.AddRange(new DevExpress.XtraReports.UI.XRControl[] {
            this.xrpreparedby,
            this.xrdeliveredby});
            this.BottomMargin.HeightF = 65.83328F;
            this.BottomMargin.Name = "BottomMargin";
            this.BottomMargin.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.BottomMargin.TextAlignment = DevExpress.XtraPrinting.TextAlignment.TopLeft;
            // 
            // xrpreparedby
            // 
            this.xrpreparedby.Font = new DevExpress.Drawing.DXFont("Calibri", 11.25F, DevExpress.Drawing.DXFontStyle.Regular, DevExpress.Drawing.DXGraphicsUnit.Point, new DevExpress.Drawing.DXFontAdditionalProperty[] {
            new DevExpress.Drawing.DXFontAdditionalProperty("GdiCharSet", ((byte)(0)))});
            this.xrpreparedby.LocationFloat = new DevExpress.Utils.PointFloat(21.54617F, 10F);
            this.xrpreparedby.Name = "xrpreparedby";
            this.xrpreparedby.Padding = new DevExpress.XtraPrinting.PaddingInfo(2F, 2F, 0F, 0F, 100F);
            this.xrpreparedby.SizeF = new System.Drawing.SizeF(199.1667F, 18F);
            this.xrpreparedby.StylePriority.UseFont = false;
            this.xrpreparedby.Text = "EULZ AVANCENA";
            // 
            // xrdeliveredby
            // 
            this.xrdeliveredby.Font = new DevExpress.Drawing.DXFont("Century Gothic", 10.2F, DevExpress.Drawing.DXFontStyle.Regular, DevExpress.Drawing.DXGraphicsUnit.Point, new DevExpress.Drawing.DXFontAdditionalProperty[] {
            new DevExpress.Drawing.DXFontAdditionalProperty("GdiCharSet", ((byte)(0)))});
            this.xrdeliveredby.LocationFloat = new DevExpress.Utils.PointFloat(293.878F, 10F);
            this.xrdeliveredby.Name = "xrdeliveredby";
            this.xrdeliveredby.Padding = new DevExpress.XtraPrinting.PaddingInfo(2F, 2F, 0F, 0F, 100F);
            this.xrdeliveredby.SizeF = new System.Drawing.SizeF(128.3334F, 18F);
            this.xrdeliveredby.StylePriority.UseFont = false;
            this.xrdeliveredby.BeforePrint += new DevExpress.XtraReports.UI.BeforePrintEventHandler(this.xrdeliveredby_BeforePrint);
            // 
            // ReportHeader
            // 
            this.ReportHeader.Controls.AddRange(new DevExpress.XtraReports.UI.XRControl[] {
            this.xrcontrolno,
            this.xrterms,
            this.xrbusinessstyle,
            this.xrdate,
            this.xrcustname,
            this.xrtin,
            this.xraddress});
            this.ReportHeader.HeightF = 101.6667F;
            this.ReportHeader.Name = "ReportHeader";
            // 
            // xrcontrolno
            // 
            this.xrcontrolno.Font = new DevExpress.Drawing.DXFont("Century Gothic", 9.2F);
            this.xrcontrolno.LocationFloat = new DevExpress.Utils.PointFloat(650.7635F, 36.00001F);
            this.xrcontrolno.Name = "xrcontrolno";
            this.xrcontrolno.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.xrcontrolno.SizeF = new System.Drawing.SizeF(147.4931F, 18F);
            this.xrcontrolno.StylePriority.UseFont = false;
            this.xrcontrolno.StylePriority.UsePadding = false;
            // 
            // xrterms
            // 
            this.xrterms.Font = new DevExpress.Drawing.DXFont("Century Gothic", 9.2F);
            this.xrterms.LocationFloat = new DevExpress.Utils.PointFloat(650.7635F, 18.00003F);
            this.xrterms.Name = "xrterms";
            this.xrterms.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.xrterms.SizeF = new System.Drawing.SizeF(147.4931F, 18F);
            this.xrterms.StylePriority.UseFont = false;
            this.xrterms.StylePriority.UsePadding = false;
            this.xrterms.Text = "15 days";
            // 
            // xrbusinessstyle
            // 
            this.xrbusinessstyle.Font = new DevExpress.Drawing.DXFont("Century Gothic", 10.2F, DevExpress.Drawing.DXFontStyle.Regular, DevExpress.Drawing.DXGraphicsUnit.Point, new DevExpress.Drawing.DXFontAdditionalProperty[] {
            new DevExpress.Drawing.DXFontAdditionalProperty("GdiCharSet", ((byte)(0)))});
            this.xrbusinessstyle.LocationFloat = new DevExpress.Utils.PointFloat(50.18808F, 54.00001F);
            this.xrbusinessstyle.Name = "xrbusinessstyle";
            this.xrbusinessstyle.Padding = new DevExpress.XtraPrinting.PaddingInfo(2F, 2F, 0F, 0F, 100F);
            this.xrbusinessstyle.SizeF = new System.Drawing.SizeF(401.6667F, 18F);
            this.xrbusinessstyle.StylePriority.UseFont = false;
            // 
            // xrdate
            // 
            this.xrdate.Font = new DevExpress.Drawing.DXFont("Tahoma", 9.75F, DevExpress.Drawing.DXFontStyle.Regular, DevExpress.Drawing.DXGraphicsUnit.Point, new DevExpress.Drawing.DXFontAdditionalProperty[] {
            new DevExpress.Drawing.DXFontAdditionalProperty("GdiCharSet", ((byte)(0)))});
            this.xrdate.LocationFloat = new DevExpress.Utils.PointFloat(650.7635F, 0F);
            this.xrdate.Name = "xrdate";
            this.xrdate.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.xrdate.SizeF = new System.Drawing.SizeF(147.4931F, 18F);
            this.xrdate.StylePriority.UseFont = false;
            this.xrdate.StylePriority.UsePadding = false;
            this.xrdate.Text = "January 21 2018";
            // 
            // xrcustname
            // 
            this.xrcustname.Font = new DevExpress.Drawing.DXFont("Calibri", 12F, DevExpress.Drawing.DXFontStyle.Bold, DevExpress.Drawing.DXGraphicsUnit.Point, new DevExpress.Drawing.DXFontAdditionalProperty[] {
            new DevExpress.Drawing.DXFontAdditionalProperty("GdiCharSet", ((byte)(0)))});
            this.xrcustname.LocationFloat = new DevExpress.Utils.PointFloat(50.18808F, 0F);
            this.xrcustname.Name = "xrcustname";
            this.xrcustname.Padding = new DevExpress.XtraPrinting.PaddingInfo(2F, 2F, 0F, 0F, 100F);
            this.xrcustname.SizeF = new System.Drawing.SizeF(401.6667F, 18F);
            this.xrcustname.StylePriority.UseFont = false;
            this.xrcustname.Text = "EULZ AVANCENA";
            // 
            // xrtin
            // 
            this.xrtin.Font = new DevExpress.Drawing.DXFont("Century Gothic", 9.2F);
            this.xrtin.LocationFloat = new DevExpress.Utils.PointFloat(50.18808F, 18.00001F);
            this.xrtin.Name = "xrtin";
            this.xrtin.Padding = new DevExpress.XtraPrinting.PaddingInfo(2F, 2F, 0F, 0F, 100F);
            this.xrtin.SizeF = new System.Drawing.SizeF(401.6667F, 14.66667F);
            this.xrtin.StylePriority.UseFont = false;
            // 
            // xraddress
            // 
            this.xraddress.Font = new DevExpress.Drawing.DXFont("Calibri", 9F, DevExpress.Drawing.DXFontStyle.Regular, DevExpress.Drawing.DXGraphicsUnit.Point, new DevExpress.Drawing.DXFontAdditionalProperty[] {
            new DevExpress.Drawing.DXFontAdditionalProperty("GdiCharSet", ((byte)(0)))});
            this.xraddress.LocationFloat = new DevExpress.Utils.PointFloat(50.18808F, 32.66668F);
            this.xraddress.Name = "xraddress";
            this.xraddress.Padding = new DevExpress.XtraPrinting.PaddingInfo(2F, 2F, 0F, 0F, 100F);
            this.xraddress.SizeF = new System.Drawing.SizeF(325.625F, 13F);
            this.xraddress.StylePriority.UseFont = false;
            this.xraddress.Text = "UNITOP SHOPPING MALL LLC BR., MANGUBAT ST. LAPULAPU";
            // 
            // PageFooter
            // 
            this.PageFooter.Controls.AddRange(new DevExpress.XtraReports.UI.XRControl[] {
            this.xrlblinvoicenum,
            this.xrlabeltotalcount,
            this.xrlbladdvat,
            this.xrlblLessWithholdingTax,
            this.xrlblTotal,
            this.xrlblVatableSales,
            this.xrlblamountdue,
            this.xrlbltotalamountdue,
            this.xrlblVatExemptSales,
            this.xrlblVatAmount,
            this.xrlblZeroRatedSales,
            this.xrlblAmountNetofVat,
            this.xrlblLessDiscount,
            this.xrlblLessVat,
            this.xrlblTotalSalesVatInc});
            this.PageFooter.HeightF = 237.0142F;
            this.PageFooter.Name = "PageFooter";
            // 
            // xrlblinvoicenum
            // 
            this.xrlblinvoicenum.Font = new DevExpress.Drawing.DXFont("Calibri", 10.25F, DevExpress.Drawing.DXFontStyle.Bold);
            this.xrlblinvoicenum.LocationFloat = new DevExpress.Utils.PointFloat(21.54617F, 34.13791F);
            this.xrlblinvoicenum.Name = "xrlblinvoicenum";
            this.xrlblinvoicenum.Padding = new DevExpress.XtraPrinting.PaddingInfo(2F, 2F, 0F, 0F, 100F);
            this.xrlblinvoicenum.SizeF = new System.Drawing.SizeF(141.6092F, 18F);
            this.xrlblinvoicenum.StylePriority.UseFont = false;
            this.xrlblinvoicenum.Text = "100";
            // 
            // xrlabeltotalcount
            // 
            this.xrlabeltotalcount.Font = new DevExpress.Drawing.DXFont("Calibri", 11.25F, DevExpress.Drawing.DXFontStyle.Bold);
            this.xrlabeltotalcount.LocationFloat = new DevExpress.Utils.PointFloat(21.54617F, 0F);
            this.xrlabeltotalcount.Name = "xrlabeltotalcount";
            this.xrlabeltotalcount.Padding = new DevExpress.XtraPrinting.PaddingInfo(2F, 2F, 0F, 0F, 100F);
            this.xrlabeltotalcount.SizeF = new System.Drawing.SizeF(43.33334F, 18F);
            this.xrlabeltotalcount.StylePriority.UseFont = false;
            this.xrlabeltotalcount.Text = "100";
            // 
            // xrlbladdvat
            // 
            this.xrlbladdvat.CanGrow = false;
            this.xrlbladdvat.Font = new DevExpress.Drawing.DXFont("Times New Roman", 7.8F);
            this.xrlbladdvat.LocationFloat = new DevExpress.Utils.PointFloat(619.6673F, 211.0299F);
            this.xrlbladdvat.Name = "xrlbladdvat";
            this.xrlbladdvat.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.xrlbladdvat.SizeF = new System.Drawing.SizeF(103.33F, 12.9921F);
            this.xrlbladdvat.StylePriority.UseFont = false;
            this.xrlbladdvat.StylePriority.UsePadding = false;
            this.xrlbladdvat.StylePriority.UseTextAlignment = false;
            this.xrlbladdvat.Text = "99,99,999.00";
            this.xrlbladdvat.TextAlignment = DevExpress.XtraPrinting.TextAlignment.MiddleRight;
            // 
            // xrlblLessWithholdingTax
            // 
            this.xrlblLessWithholdingTax.CanGrow = false;
            this.xrlblLessWithholdingTax.Font = new DevExpress.Drawing.DXFont("Times New Roman", 7.8F);
            this.xrlblLessWithholdingTax.LocationFloat = new DevExpress.Utils.PointFloat(619.6673F, 185.0457F);
            this.xrlblLessWithholdingTax.Name = "xrlblLessWithholdingTax";
            this.xrlblLessWithholdingTax.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.xrlblLessWithholdingTax.SizeF = new System.Drawing.SizeF(103.33F, 12.9921F);
            this.xrlblLessWithholdingTax.StylePriority.UseFont = false;
            this.xrlblLessWithholdingTax.StylePriority.UsePadding = false;
            this.xrlblLessWithholdingTax.StylePriority.UseTextAlignment = false;
            this.xrlblLessWithholdingTax.Text = "0.00";
            this.xrlblLessWithholdingTax.TextAlignment = DevExpress.XtraPrinting.TextAlignment.MiddleRight;
            // 
            // xrlblTotal
            // 
            this.xrlblTotal.CanGrow = false;
            this.xrlblTotal.Font = new DevExpress.Drawing.DXFont("Times New Roman", 7.8F);
            this.xrlblTotal.LocationFloat = new DevExpress.Utils.PointFloat(619.681F, 172.0536F);
            this.xrlblTotal.Name = "xrlblTotal";
            this.xrlblTotal.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.xrlblTotal.SizeF = new System.Drawing.SizeF(103.33F, 12.9921F);
            this.xrlblTotal.StylePriority.UseFont = false;
            this.xrlblTotal.StylePriority.UsePadding = false;
            this.xrlblTotal.StylePriority.UseTextAlignment = false;
            this.xrlblTotal.Text = "0.00";
            this.xrlblTotal.TextAlignment = DevExpress.XtraPrinting.TextAlignment.MiddleRight;
            // 
            // xrlblVatableSales
            // 
            this.xrlblVatableSales.CanGrow = false;
            this.xrlblVatableSales.Font = new DevExpress.Drawing.DXFont("Times New Roman", 7.8F);
            this.xrlblVatableSales.LocationFloat = new DevExpress.Utils.PointFloat(619.6673F, 68.11686F);
            this.xrlblVatableSales.Name = "xrlblVatableSales";
            this.xrlblVatableSales.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.xrlblVatableSales.SizeF = new System.Drawing.SizeF(103.33F, 12.9921F);
            this.xrlblVatableSales.StylePriority.UseFont = false;
            this.xrlblVatableSales.StylePriority.UsePadding = false;
            this.xrlblVatableSales.StylePriority.UseTextAlignment = false;
            this.xrlblVatableSales.Text = "99,99,999.00";
            this.xrlblVatableSales.TextAlignment = DevExpress.XtraPrinting.TextAlignment.MiddleRight;
            // 
            // xrlblamountdue
            // 
            this.xrlblamountdue.CanGrow = false;
            this.xrlblamountdue.Font = new DevExpress.Drawing.DXFont("Times New Roman", 7.8F);
            this.xrlblamountdue.LocationFloat = new DevExpress.Utils.PointFloat(619.6673F, 198.0378F);
            this.xrlblamountdue.Name = "xrlblamountdue";
            this.xrlblamountdue.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.xrlblamountdue.SizeF = new System.Drawing.SizeF(103.33F, 12.9921F);
            this.xrlblamountdue.StylePriority.UseFont = false;
            this.xrlblamountdue.StylePriority.UsePadding = false;
            this.xrlblamountdue.StylePriority.UseTextAlignment = false;
            this.xrlblamountdue.Text = "99,99,999.00";
            this.xrlblamountdue.TextAlignment = DevExpress.XtraPrinting.TextAlignment.MiddleRight;
            // 
            // xrlbltotalamountdue
            // 
            this.xrlbltotalamountdue.CanGrow = false;
            this.xrlbltotalamountdue.Font = new DevExpress.Drawing.DXFont("Times New Roman", 12.2F, DevExpress.Drawing.DXFontStyle.Bold);
            this.xrlbltotalamountdue.LocationFloat = new DevExpress.Utils.PointFloat(579.21F, 224.022F);
            this.xrlbltotalamountdue.Name = "xrlbltotalamountdue";
            this.xrlbltotalamountdue.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.xrlbltotalamountdue.SizeF = new System.Drawing.SizeF(143.7873F, 12.99213F);
            this.xrlbltotalamountdue.StylePriority.UseFont = false;
            this.xrlbltotalamountdue.StylePriority.UsePadding = false;
            this.xrlbltotalamountdue.StylePriority.UseTextAlignment = false;
            this.xrlbltotalamountdue.Text = "99,99,999.00";
            this.xrlbltotalamountdue.TextAlignment = DevExpress.XtraPrinting.TextAlignment.MiddleRight;
            // 
            // xrlblVatExemptSales
            // 
            this.xrlblVatExemptSales.CanGrow = false;
            this.xrlblVatExemptSales.Font = new DevExpress.Drawing.DXFont("Times New Roman", 7.8F);
            this.xrlblVatExemptSales.LocationFloat = new DevExpress.Utils.PointFloat(619.671F, 81.10899F);
            this.xrlblVatExemptSales.Name = "xrlblVatExemptSales";
            this.xrlblVatExemptSales.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.xrlblVatExemptSales.SizeF = new System.Drawing.SizeF(103.33F, 12.9921F);
            this.xrlblVatExemptSales.StylePriority.UseFont = false;
            this.xrlblVatExemptSales.StylePriority.UsePadding = false;
            this.xrlblVatExemptSales.StylePriority.UseTextAlignment = false;
            this.xrlblVatExemptSales.Text = "99,99,999.00";
            this.xrlblVatExemptSales.TextAlignment = DevExpress.XtraPrinting.TextAlignment.MiddleRight;
            // 
            // xrlblVatAmount
            // 
            this.xrlblVatAmount.CanGrow = false;
            this.xrlblVatAmount.Font = new DevExpress.Drawing.DXFont("Times New Roman", 7.8F);
            this.xrlblVatAmount.LocationFloat = new DevExpress.Utils.PointFloat(619.681F, 107.0931F);
            this.xrlblVatAmount.Name = "xrlblVatAmount";
            this.xrlblVatAmount.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.xrlblVatAmount.SizeF = new System.Drawing.SizeF(103.33F, 12.9921F);
            this.xrlblVatAmount.StylePriority.UseFont = false;
            this.xrlblVatAmount.StylePriority.UsePadding = false;
            this.xrlblVatAmount.StylePriority.UseTextAlignment = false;
            this.xrlblVatAmount.Text = "99,99,999.00";
            this.xrlblVatAmount.TextAlignment = DevExpress.XtraPrinting.TextAlignment.MiddleRight;
            // 
            // xrlblZeroRatedSales
            // 
            this.xrlblZeroRatedSales.CanGrow = false;
            this.xrlblZeroRatedSales.Font = new DevExpress.Drawing.DXFont("Times New Roman", 7.8F);
            this.xrlblZeroRatedSales.LocationFloat = new DevExpress.Utils.PointFloat(619.6776F, 94.10103F);
            this.xrlblZeroRatedSales.Name = "xrlblZeroRatedSales";
            this.xrlblZeroRatedSales.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.xrlblZeroRatedSales.SizeF = new System.Drawing.SizeF(103.33F, 12.9921F);
            this.xrlblZeroRatedSales.StylePriority.UseFont = false;
            this.xrlblZeroRatedSales.StylePriority.UsePadding = false;
            this.xrlblZeroRatedSales.StylePriority.UseTextAlignment = false;
            this.xrlblZeroRatedSales.Text = "0.00";
            this.xrlblZeroRatedSales.TextAlignment = DevExpress.XtraPrinting.TextAlignment.MiddleRight;
            // 
            // xrlblAmountNetofVat
            // 
            this.xrlblAmountNetofVat.CanGrow = false;
            this.xrlblAmountNetofVat.Font = new DevExpress.Drawing.DXFont("Times New Roman", 7.8F);
            this.xrlblAmountNetofVat.LocationFloat = new DevExpress.Utils.PointFloat(619.681F, 146.0694F);
            this.xrlblAmountNetofVat.Name = "xrlblAmountNetofVat";
            this.xrlblAmountNetofVat.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.xrlblAmountNetofVat.SizeF = new System.Drawing.SizeF(103.33F, 12.9921F);
            this.xrlblAmountNetofVat.StylePriority.UseFont = false;
            this.xrlblAmountNetofVat.StylePriority.UsePadding = false;
            this.xrlblAmountNetofVat.StylePriority.UseTextAlignment = false;
            this.xrlblAmountNetofVat.Text = "99,99,999.00";
            this.xrlblAmountNetofVat.TextAlignment = DevExpress.XtraPrinting.TextAlignment.MiddleRight;
            // 
            // xrlblLessDiscount
            // 
            this.xrlblLessDiscount.CanGrow = false;
            this.xrlblLessDiscount.Font = new DevExpress.Drawing.DXFont("Times New Roman", 7.8F);
            this.xrlblLessDiscount.LocationFloat = new DevExpress.Utils.PointFloat(619.6673F, 159.0615F);
            this.xrlblLessDiscount.Name = "xrlblLessDiscount";
            this.xrlblLessDiscount.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.xrlblLessDiscount.SizeF = new System.Drawing.SizeF(103.33F, 12.9921F);
            this.xrlblLessDiscount.StylePriority.UseFont = false;
            this.xrlblLessDiscount.StylePriority.UsePadding = false;
            this.xrlblLessDiscount.StylePriority.UseTextAlignment = false;
            this.xrlblLessDiscount.Text = "0.00";
            this.xrlblLessDiscount.TextAlignment = DevExpress.XtraPrinting.TextAlignment.MiddleRight;
            // 
            // xrlblLessVat
            // 
            this.xrlblLessVat.CanGrow = false;
            this.xrlblLessVat.Font = new DevExpress.Drawing.DXFont("Times New Roman", 7.8F);
            this.xrlblLessVat.LocationFloat = new DevExpress.Utils.PointFloat(619.6673F, 133.0773F);
            this.xrlblLessVat.Name = "xrlblLessVat";
            this.xrlblLessVat.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.xrlblLessVat.SizeF = new System.Drawing.SizeF(103.33F, 12.9921F);
            this.xrlblLessVat.StylePriority.UseFont = false;
            this.xrlblLessVat.StylePriority.UsePadding = false;
            this.xrlblLessVat.StylePriority.UseTextAlignment = false;
            this.xrlblLessVat.Text = "99,99,999.00";
            this.xrlblLessVat.TextAlignment = DevExpress.XtraPrinting.TextAlignment.MiddleRight;
            // 
            // xrlblTotalSalesVatInc
            // 
            this.xrlblTotalSalesVatInc.CanGrow = false;
            this.xrlblTotalSalesVatInc.Font = new DevExpress.Drawing.DXFont("Times New Roman", 7.8F);
            this.xrlblTotalSalesVatInc.LocationFloat = new DevExpress.Utils.PointFloat(619.681F, 120.0852F);
            this.xrlblTotalSalesVatInc.Name = "xrlblTotalSalesVatInc";
            this.xrlblTotalSalesVatInc.Padding = new DevExpress.XtraPrinting.PaddingInfo(0F, 0F, 0F, 0F, 100F);
            this.xrlblTotalSalesVatInc.SizeF = new System.Drawing.SizeF(103.33F, 12.9921F);
            this.xrlblTotalSalesVatInc.StylePriority.UseFont = false;
            this.xrlblTotalSalesVatInc.StylePriority.UsePadding = false;
            this.xrlblTotalSalesVatInc.StylePriority.UseTextAlignment = false;
            this.xrlblTotalSalesVatInc.Text = "99,99,999.00";
            this.xrlblTotalSalesVatInc.TextAlignment = DevExpress.XtraPrinting.TextAlignment.MiddleRight;
            // 
            // SalesInvoiceJFC
            // 
            this.Bands.AddRange(new DevExpress.XtraReports.UI.Band[] {
            this.Detail,
            this.TopMargin,
            this.BottomMargin,
            this.ReportHeader,
            this.PageFooter});
            this.Margins = new DevExpress.Drawing.DXMargins(70.87F, 30F, 100F, 65.83328F);
            this.PageHeightF = 750F;
            this.PageWidthF = 950F;
            this.PaperKind = DevExpress.Drawing.Printing.DXPaperKind.Custom;
            this.ShowPreviewMarginLines = false;
            this.ShowPrintMarginsWarning = false;
            this.Version = "26.1";
            xrWatermark1.Id = "Watermark1";
            this.Watermarks.AddRange(new DevExpress.XtraPrinting.Drawing.Watermark[] {
            xrWatermark1});
            ((System.ComponentModel.ISupportInitialize)(this)).EndInit();

        }

        #endregion

        private DevExpress.XtraReports.UI.DetailBand Detail;
        private DevExpress.XtraReports.UI.TopMarginBand TopMargin;
        private DevExpress.XtraReports.UI.BottomMarginBand BottomMargin;
        private DevExpress.XtraReports.UI.ReportHeaderBand ReportHeader;
        private DevExpress.XtraReports.UI.PageFooterBand PageFooter;
        public DevExpress.XtraReports.UI.XRLabel xrlbltotalamountdue;
        public DevExpress.XtraReports.UI.XRLabel xrlblamountdue;
        public DevExpress.XtraReports.UI.XRLabel xrlbladdvat;
        public DevExpress.XtraReports.UI.XRLabel xrlblVatExemptSales;
        public DevExpress.XtraReports.UI.XRLabel xrlblVatAmount;
        public DevExpress.XtraReports.UI.XRLabel xrlblZeroRatedSales;
        public DevExpress.XtraReports.UI.XRLabel xrlblAmountNetofVat;
        public DevExpress.XtraReports.UI.XRLabel xrlblLessDiscount;
        public DevExpress.XtraReports.UI.XRLabel xrlblLessVat;
        public DevExpress.XtraReports.UI.XRLabel xrlblTotalSalesVatInc;
        public DevExpress.XtraReports.UI.XRLabel xrlblVatableSales;
        public DevExpress.XtraReports.UI.XRLabel xrpreparedby;
        public DevExpress.XtraReports.UI.XRLabel xrdeliveredby;
        public DevExpress.XtraReports.UI.XRLabel xrcustname;
        public DevExpress.XtraReports.UI.XRLabel xrtin;
        public DevExpress.XtraReports.UI.XRLabel xraddress;
        public DevExpress.XtraReports.UI.XRLabel xrbusinessstyle;
        public DevExpress.XtraReports.UI.XRLabel xrdate;
        public DevExpress.XtraReports.UI.XRLabel xrterms;
        public DevExpress.XtraReports.UI.XRLabel xrcontrolno;
        public DevExpress.XtraReports.UI.XRLabel xrlblLessWithholdingTax;
        public DevExpress.XtraReports.UI.XRLabel xrlblTotal;
        public DevExpress.XtraReports.UI.XRLabel xrlabeltotalcount;
        public DevExpress.XtraReports.UI.XRLabel xrlblinvoicenum;
    }
}
