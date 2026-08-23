using DevExpress.XtraBars.FluentDesignSystem;
using DevExpress.XtraBars.Navigation;
using DevExpress.XtraBars;

namespace SalesInventorySystem.AccountingDevEx
{
    partial class AccountingBoard
    {
        private System.ComponentModel.IContainer components = null;

        private FluentDesignFormContainer fluentDesignFormContainer1;
        private FluentDesignFormControl fluentDesignFormControl1;
        private AccordionControl accordionControl1;

        // Menu items are declared here (not built in a runtime loop) specifically
        // so they render in the Form Designer and the Accordion's collection
        // editor — you can rename captions, reorder, add icons, etc. visually.
        // Each item's Tag holds the page key that AccountingBoard.cs uses to look
        // up which control to load (see ContentFactories there) — that's the one
        // other spot to touch when you add a brand-new item here.
        private AccordionControlElement menuMasterList;

        private AccordionControlElement groupVouchering;
        private AccordionControlElement menuVoucherPostingCashCheck;
        private AccordionControlElement menuVoucherPostingTelegraphic;
        private AccordionControlElement menuPaymentList;

        private AccordionControlElement groupAccountReceivable;
        private AccordionControlElement menuPostClientPayment;

        private AccordionControlElement groupExpense;
        private AccordionControlElement menuExpenseSingle;
        private AccordionControlElement menuExpenseBatch;

        private AccordionControlElement menuManualTicket;
        private AccordionControlElement menuBankRecon;
        private AccordionControlElement menuReports;
        private AccordionControlElement menuGLTicketEntries;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
                components.Dispose();

            base.Dispose(disposing);
        }

        private void InitializeComponent()
        {
            this.components = new System.ComponentModel.Container();
            this.fluentDesignFormContainer1 = new DevExpress.XtraBars.FluentDesignSystem.FluentDesignFormContainer();
            this.fluentDesignFormControl1 = new DevExpress.XtraBars.FluentDesignSystem.FluentDesignFormControl();
            this.accordionControl1 = new DevExpress.XtraBars.Navigation.AccordionControl();
            this.menuMasterList = new DevExpress.XtraBars.Navigation.AccordionControlElement();
            this.groupVouchering = new DevExpress.XtraBars.Navigation.AccordionControlElement();
            this.menuVoucherPostingCashCheck = new DevExpress.XtraBars.Navigation.AccordionControlElement();
            this.menuVoucherPostingTelegraphic = new DevExpress.XtraBars.Navigation.AccordionControlElement();
            this.menuPaymentList = new DevExpress.XtraBars.Navigation.AccordionControlElement();
            this.groupAccountReceivable = new DevExpress.XtraBars.Navigation.AccordionControlElement();
            this.menuPostClientPayment = new DevExpress.XtraBars.Navigation.AccordionControlElement();
            this.groupExpense = new DevExpress.XtraBars.Navigation.AccordionControlElement();
            this.menuExpenseSingle = new DevExpress.XtraBars.Navigation.AccordionControlElement();
            this.menuExpenseBatch = new DevExpress.XtraBars.Navigation.AccordionControlElement();
            this.menuManualTicket = new DevExpress.XtraBars.Navigation.AccordionControlElement();
            this.menuBankRecon = new DevExpress.XtraBars.Navigation.AccordionControlElement();
            this.menuReports = new DevExpress.XtraBars.Navigation.AccordionControlElement();
            this.menuGLTicketEntries = new DevExpress.XtraBars.Navigation.AccordionControlElement();
            ((System.ComponentModel.ISupportInitialize)(this.fluentDesignFormControl1)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.accordionControl1)).BeginInit();
            this.SuspendLayout();
            // 
            // fluentDesignFormContainer1
            // 
            this.fluentDesignFormContainer1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.fluentDesignFormContainer1.Location = new System.Drawing.Point(260, 39);
            this.fluentDesignFormContainer1.Name = "fluentDesignFormContainer1";
            this.fluentDesignFormContainer1.Size = new System.Drawing.Size(1227, 723);
            this.fluentDesignFormContainer1.TabIndex = 0;
            // 
            // fluentDesignFormControl1
            // 
            this.fluentDesignFormControl1.FluentDesignForm = this;
            this.fluentDesignFormControl1.Location = new System.Drawing.Point(0, 0);
            this.fluentDesignFormControl1.Name = "fluentDesignFormControl1";
            this.fluentDesignFormControl1.Size = new System.Drawing.Size(1487, 39);
            this.fluentDesignFormControl1.TabIndex = 2;
            this.fluentDesignFormControl1.TabStop = false;
            // 
            // accordionControl1
            // 
            this.accordionControl1.Dock = System.Windows.Forms.DockStyle.Left;
            this.accordionControl1.Elements.AddRange(new DevExpress.XtraBars.Navigation.AccordionControlElement[] {
            this.menuMasterList,
            this.groupVouchering,
            this.groupAccountReceivable,
            this.groupExpense,
            this.menuManualTicket,
            this.menuBankRecon,
            this.menuReports,
            this.menuGLTicketEntries});
            this.accordionControl1.Location = new System.Drawing.Point(0, 39);
            this.accordionControl1.Name = "accordionControl1";
            this.accordionControl1.Size = new System.Drawing.Size(260, 723);
            this.accordionControl1.TabIndex = 1;
            this.accordionControl1.ViewType = DevExpress.XtraBars.Navigation.AccordionControlViewType.HamburgerMenu;
            this.accordionControl1.ElementClick += new DevExpress.XtraBars.Navigation.ElementClickEventHandler(this.AccordionMain_ElementClick);
            // 
            // menuMasterList
            // 
            this.menuMasterList.Name = "menuMasterList";
            this.menuMasterList.Style = DevExpress.XtraBars.Navigation.ElementStyle.Item;
            this.menuMasterList.Tag = "navMasterlist";
            this.menuMasterList.Text = "Masterlist";
            // 
            // groupVouchering
            // 
            this.groupVouchering.Elements.AddRange(new DevExpress.XtraBars.Navigation.AccordionControlElement[] {
            this.menuVoucherPostingCashCheck,
            this.menuVoucherPostingTelegraphic,
            this.menuPaymentList});
            this.groupVouchering.Name = "groupVouchering";
            this.groupVouchering.Text = "Vouchering";
            // 
            // menuVoucherPostingCashCheck
            // 
            this.menuVoucherPostingCashCheck.Name = "menuVoucherPostingCashCheck";
            this.menuVoucherPostingCashCheck.Style = DevExpress.XtraBars.Navigation.ElementStyle.Item;
            this.menuVoucherPostingCashCheck.Tag = "navVoucherPosting";
            this.menuVoucherPostingCashCheck.Text = "Posting Cash/Check";
            // 
            // menuVoucherPostingTelegraphic
            // 
            this.menuVoucherPostingTelegraphic.Name = "menuVoucherPostingTelegraphic";
            this.menuVoucherPostingTelegraphic.Style = DevExpress.XtraBars.Navigation.ElementStyle.Item;
            this.menuVoucherPostingTelegraphic.Tag = "navVoucherPostingManual";
            this.menuVoucherPostingTelegraphic.Text = "Posting Telegraphic";
            // 
            // menuPaymentList
            // 
            this.menuPaymentList.Name = "menuPaymentList";
            this.menuPaymentList.Style = DevExpress.XtraBars.Navigation.ElementStyle.Item;
            this.menuPaymentList.Tag = "navVoucherPaymentList";
            this.menuPaymentList.Text = "Payment List";
            this.menuPaymentList.Click += new System.EventHandler(this.menuPaymentList_Click);
            // 
            // groupAccountReceivable
            // 
            this.groupAccountReceivable.Elements.AddRange(new DevExpress.XtraBars.Navigation.AccordionControlElement[] {
            this.menuPostClientPayment});
            this.groupAccountReceivable.Expanded = true;
            this.groupAccountReceivable.Name = "groupAccountReceivable";
            this.groupAccountReceivable.Text = "Account Receivable";
            // 
            // menuPostClientPayment
            // 
            this.menuPostClientPayment.Name = "menuPostClientPayment";
            this.menuPostClientPayment.Style = DevExpress.XtraBars.Navigation.ElementStyle.Item;
            this.menuPostClientPayment.Tag = "navPostClientPayment";
            this.menuPostClientPayment.Text = "Post Client Payment";
            // 
            // groupExpense
            // 
            this.groupExpense.Elements.AddRange(new DevExpress.XtraBars.Navigation.AccordionControlElement[] {
            this.menuExpenseSingle,
            this.menuExpenseBatch});
            this.groupExpense.Name = "groupExpense";
            this.groupExpense.Text = "Post Expense";
            // 
            // menuExpenseSingle
            // 
            this.menuExpenseSingle.Name = "menuExpenseSingle";
            this.menuExpenseSingle.Style = DevExpress.XtraBars.Navigation.ElementStyle.Item;
            this.menuExpenseSingle.Tag = "navExpenseSingle";
            this.menuExpenseSingle.Text = "Single Mode";
            // 
            // menuExpenseBatch
            // 
            this.menuExpenseBatch.Name = "menuExpenseBatch";
            this.menuExpenseBatch.Style = DevExpress.XtraBars.Navigation.ElementStyle.Item;
            this.menuExpenseBatch.Tag = "navExpenseBatch";
            this.menuExpenseBatch.Text = "Batch Mode";
            // 
            // menuManualTicket
            // 
            this.menuManualTicket.Name = "menuManualTicket";
            this.menuManualTicket.Style = DevExpress.XtraBars.Navigation.ElementStyle.Item;
            this.menuManualTicket.Tag = "navManualTicket";
            this.menuManualTicket.Text = "Manual Ticket";
            this.menuManualTicket.Click += new System.EventHandler(this.menuManualTicket_Click);
            // 
            // menuBankRecon
            // 
            this.menuBankRecon.Name = "menuBankRecon";
            this.menuBankRecon.Style = DevExpress.XtraBars.Navigation.ElementStyle.Item;
            this.menuBankRecon.Tag = "navBankRecon";
            this.menuBankRecon.Text = "Bank Recon";
            this.menuBankRecon.Click += new System.EventHandler(this.menuBankRecon_Click);
            // 
            // menuReports
            // 
            this.menuReports.Name = "menuReports";
            this.menuReports.Style = DevExpress.XtraBars.Navigation.ElementStyle.Item;
            this.menuReports.Tag = "navReports";
            this.menuReports.Text = "Reports";
            // 
            // menuGLTicketEntries
            // 
            this.menuGLTicketEntries.Name = "menuGLTicketEntries";
            this.menuGLTicketEntries.Style = DevExpress.XtraBars.Navigation.ElementStyle.Item;
            this.menuGLTicketEntries.Tag = "navGLTicketEntries";
            this.menuGLTicketEntries.Text = "GL Ticket Entries";
            // 
            // AccountingBoard
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(7F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1487, 762);
            this.ControlContainer = this.fluentDesignFormContainer1;
            this.Controls.Add(this.fluentDesignFormContainer1);
            this.Controls.Add(this.accordionControl1);
            this.Controls.Add(this.fluentDesignFormControl1);
            this.FluentDesignFormControl = this.fluentDesignFormControl1;
            this.Name = "AccountingBoard";
            this.NavigationControl = this.accordionControl1;
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "Accounting";
            this.WindowState = System.Windows.Forms.FormWindowState.Maximized;
            this.Load += new System.EventHandler(this.AccountingBoard_Load);
            this.Shown += new System.EventHandler(this.AccountingBoard_Shown);
            ((System.ComponentModel.ISupportInitialize)(this.fluentDesignFormControl1)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.accordionControl1)).EndInit();
            this.ResumeLayout(false);

        }
    }
}