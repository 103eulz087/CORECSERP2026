using DevExpress.XtraBars.FluentDesignSystem;
using DevExpress.XtraBars.Navigation;
using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Windows.Forms;

namespace SalesInventorySystem.AccountingDevEx
{
    // Base class changed from XtraForm -> FluentDesignForm. Still behaves like a
    // normal form (Show/ShowDialog/MDI child) — nothing about how it's opened
    // elsewhere in the app needs to change.
    public partial class AccountingBoard : FluentDesignForm
    {
        public AccountingBoard()
        {
            InitializeComponent();
            if (!DesignMode)
                BuildFluentLayout();
        }

        // ---------------------------------------------------------------
        // Page keys — visible to Designer.cs too (same partial class), so
        // the Tag you set on each AccordionControlElement there and the key
        // you use in ContentFactories below always match up.
        // ---------------------------------------------------------------

        private const string PageMasterlist = "navMasterlist";
        private const string PageVoucherPosting = "navVoucherPosting";
        private const string PageVoucherPostingManual = "navVoucherPostingManual";
        private const string PageVoucherPaymentList = "navVoucherPaymentList";
        private const string PageExpenseSingle = "navExpenseSingle";
        private const string PageExpenseBatch = "navExpenseBatch";
        private const string PageManualTicket = "navManualTicket";
        private const string PageBankRecon = "navBankRecon";
        private const string PageReports = "navReports";
        private const string PageGLTicketEntries = "navGLTicketEntries";

        // ---------------------------------------------------------------
        // Content loading — the ONE place to touch (besides the Designer)
        // when you add a new menu item: one dictionary entry, same key as
        // the Tag you set on the new AccordionControlElement.
        // ---------------------------------------------------------------

        private Dictionary<string, Func<Control>> BuildContentFactories() => new Dictionary<string, Func<Control>>
        {
            [PageMasterlist] = () =>
            {
                _accountMasterList = new HOFormsDevEx.AccountMasterListDevEx();
                _accountMasterList.LoadData();
                return _accountMasterList;
            },
            [PageVoucherPosting] = () =>
            {
                _supplierPayment = new SupplierPaymentDevEx();
                _supplierPayment.LoadData();
                return _supplierPayment;
            },
            [PageVoucherPostingManual] = () =>
            {
                _voucheringManual = new VoucheringManualFrm();
                _voucheringManual.LoadData();
                return _voucheringManual;
            },
            [PageVoucherPaymentList] = () =>
            {
                //_paymentList = new ViewCheckVoucherDevEx();
                _paymentList = new SupplierVoucherReversalFrm();
                return _paymentList;
            },
            [PageExpenseSingle] = () =>
            {
                _addExpenseSingleMode = new AccountingDevEx.AddExpenseDevExFrm();//new HOFormsDevEx.AddExpenseDevExFrm();
                _addExpenseSingleMode.LoadData();
                return _addExpenseSingleMode;
            },
            [PageExpenseBatch] = () =>
            {
                _addExpenseBatchMode = new AccountingDevEx.ExpenseManualMultiBranchFrm();//HOFormsDevEx.PostExpenseDevExFrm();
                _addExpenseBatchMode.LoadData();
                return _addExpenseBatchMode;
            },
            [PageManualTicket] = () =>
            {
                _manualVoucherMultiBranch = new HOFormsDevEx.ManualJournalVoucherMultiBranchFrm();
                _manualVoucherMultiBranch.LoadData();
                return _manualVoucherMultiBranch;
            },
            [PageBankRecon] = () =>
            {
                _bankRecon = new BankReconFormV2();
                return _bankRecon;
            },
            [PageReports] = () =>
            {
                _accountingReports = new HOFormsDevEx.AccountingReportsForm();
                _accountingReports.LoadData();
                return _accountingReports;
            },
            [PageGLTicketEntries] = () =>
            {
                _accountingTicketReports = new AccountingDevEx.TicketInquiryFrm();
                //_accountingTicketReports = new Reporting.ViewTicketDevExRep();
                _accountingTicketReports.LoadData();
                return _accountingTicketReports;
            },
        };

        // ---------------------------------------------------------------
        // Navigation wiring — generic; discovers whatever elements Designer.cs
        // built rather than assuming a fixed list, so reordering/adding items
        // in the Designer just works without touching this method.
        // ---------------------------------------------------------------

        private NavigationFrame navFrameMain;
        private Dictionary<string, Func<Control>> _contentFactories;
        private readonly HashSet<string> _loadedPages = new HashSet<string>();
        private readonly Dictionary<string, NavigationPage> _pagesByKey = new Dictionary<string, NavigationPage>();

        // Per-user Accounting Board access (UserAccountingBoardAccess). Empty/null set
        // means "no restriction recorded for this user" -- everything stays accessible;
        // rows only ever narrow access, never widen it. See UserAccessDevEx.cs for the
        // admin screen that manages these rows (same UI pattern as UserMenuAccess).
        private string _defaultKey = PageMasterlist;
        private readonly HashSet<string> _allowedKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        private void LoadMenuAccess()
        {
            using (SqlConnection con = Database.getConnection())
            {
                con.Open();
                SqlCommand com = new SqlCommand("SELECT MenuKey FROM UserAccountingBoardAccess WHERE UserID=@UserID", con);
                com.Parameters.AddWithValue("@UserID", Login.isglobalUserID);
                using (SqlDataReader reader = com.ExecuteReader())
                {
                    while (reader.Read())
                        _allowedKeys.Add(reader["MenuKey"].ToString());
                }
            }
        }

        private bool IsKeyAllowed(string key)
        {
            return _allowedKeys.Count == 0 || _allowedKeys.Contains(key);
        }

        private void BuildFluentLayout()
        {
            navFrameMain = new NavigationFrame { Name = "navFrameMain", Dock = DockStyle.Fill };
            fluentDesignFormContainer1.Controls.Add(navFrameMain);

            _contentFactories = BuildContentFactories();
            LoadMenuAccess();

            foreach (var element in EnumerateLeafElements(accordionControl1.Elements))
            {
                string key = element.Tag as string;
                if (string.IsNullOrEmpty(key))
                    continue;

                if (!IsKeyAllowed(key))
                {
                    element.Visible = false;
                    continue;
                }

                var page = new NavigationPage { Name = key };
                navFrameMain.Pages.Add(page);
                _pagesByKey[key] = page;
            }

            // If the usual default (Masterlist) got restricted for this user, fall back
            // to the first accordion item they're still allowed to see.
            if (!_pagesByKey.ContainsKey(_defaultKey))
            {
                foreach (var element in EnumerateLeafElements(accordionControl1.Elements))
                {
                    string key = element.Tag as string;
                    if (!string.IsNullOrEmpty(key) && _pagesByKey.ContainsKey(key))
                    {
                        _defaultKey = key;
                        break;
                    }
                }
            }

            // Highlight the default page here, but don't load its content yet —
            // the form doesn't have a real handle / fully parented control tree
            // inside the constructor. The actual first load happens in Shown,
            // same timing your original tab-based code used.
            accordionControl1.SelectedElement = FindElementByKey(_defaultKey);
            if (_pagesByKey.TryGetValue(_defaultKey, out var defaultPage))
                navFrameMain.SelectedPage = defaultPage;
        }

        private static IEnumerable<AccordionControlElement> EnumerateLeafElements(System.Collections.IEnumerable elements)
        {
            foreach (AccordionControlElement el in elements)
            {
                bool hasChildren = false;
                foreach (var _ in el.Elements)
                {
                    hasChildren = true;
                    break;
                }

                if (hasChildren)
                {
                    foreach (var child in EnumerateLeafElements(el.Elements))
                        yield return child;
                }
                else
                {
                    yield return el;
                }
            }
        }

        private AccordionControlElement FindElementByKey(string key)
        {
            foreach (var el in EnumerateLeafElements(accordionControl1.Elements))
                if ((string)el.Tag == key)
                    return el;
            return null;
        }

        private void AccordionMain_ElementClick(object sender, ElementClickEventArgs e)
        {
            string key = e.Element?.Tag as string;
            if (!string.IsNullOrEmpty(key))
                SelectAndLoad(key);
        }

        private void SelectAndLoad(string key)
        {
            if (!IsKeyAllowed(key))
                return;

            if (!_pagesByKey.TryGetValue(key, out var page))
                return;

            navFrameMain.SelectedPage = page;

            if (_loadedPages.Contains(key))
                return;
            _loadedPages.Add(key);

            if (!_contentFactories.TryGetValue(key, out var factory))
                return;

            var content = factory();
            if (content == null)
                return;

            content.Dock = DockStyle.Fill;
            page.Controls.Add(content);
        }

        // ---------------------------------------------------------------
        // Module instances — kept as fields in case other code in the form
        // needs to reach into a loaded module directly (e.g. refreshing the
        // Payment List after posting a voucher elsewhere).
        // ---------------------------------------------------------------

        private SupplierPaymentDevEx _supplierPayment;
        private VoucheringManualFrm _voucheringManual;
        //private ViewCheckVoucherDevEx _paymentList;
        private SupplierVoucherReversalFrm _paymentList;
        private HOFormsDevEx.AccountMasterListDevEx _accountMasterList;
        private HOFormsDevEx.ManualJournalVoucherMultiBranchFrm _manualVoucherMultiBranch;
        private HOFormsDevEx.AccountingReportsForm _accountingReports;
        private AccountingDevEx.TicketInquiryFrm _accountingTicketReports;
        //private Reporting.ViewTicketDevExRep _accountingTicketReports;
        //private HOFormsDevEx.AddExpenseDevExFrm _addExpenseSingleMode;
        private AccountingDevEx.AddExpenseDevExFrm _addExpenseSingleMode;
        //private HOFormsDevEx.PostExpenseDevExFrm _addExpenseBatchMode;
        private AccountingDevEx.ExpenseManualMultiBranchFrm _addExpenseBatchMode;
        private BankReconFormV2 _bankRecon;

        // ---------------------------------------------------------------
        // Form events
        // ---------------------------------------------------------------

        private void AccountingBoard_Load(object sender, EventArgs e)
        {
        }

        private void AccountingBoard_Shown(object sender, EventArgs e)
        {
            SelectAndLoad(_defaultKey);
        }

        private void menuManualTicket_Click(object sender, EventArgs e)
        {

        }

        private void menuBankRecon_Click(object sender, EventArgs e)
        {

        }

        private void menuPaymentList_Click(object sender, EventArgs e)
        {

        }
    }
}