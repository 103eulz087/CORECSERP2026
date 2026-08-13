using System;
using System.Drawing;
using System.Collections;
using System.ComponentModel;
using DevExpress.XtraReports.UI;

namespace SalesInventorySystem.DevExReportTemplate
{
    public partial class SalesInvoiceJFC : DevExpress.XtraReports.UI.XtraReport
    {
        public SalesInvoiceJFC()
        {
            InitializeComponent();
        }

        private void xrdeliveredby_BeforePrint(object sender, CancelEventArgs e)
        {

        }
    }
}
