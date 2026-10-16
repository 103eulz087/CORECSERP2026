using System;
using System.Threading.Tasks;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraSplashScreen;

namespace SalesInventorySystem
{
    public partial class StartupForm : XtraForm
    {
        private readonly SingleInstanceApp _app;

        // IMPORTANT: constructor should be internal (or make SingleInstanceApp public)
        internal StartupForm(SingleInstanceApp app)
        {
            InitializeComponent();
            _app = app;

            ShowInTaskbar = false;
            Opacity = 0;
            WindowState = FormWindowState.Minimized;
        }

        protected override async void OnShown(EventArgs e)
        {
            base.OnShown(e);

            try
            {
                // 2026-10-15: the "please wait" window shown since Program.Main (Classes.StartupSplash) carries the
                // status now; it was the DevExpress WaitForm1 here, which only appeared after the slow part.
                Classes.StartupSplash.SetStatus("Loading config...");

                await Task.Run(() =>
                {
                    string filepath = Application.StartupPath + "\\checkVersion.txt";
                    GlobalConfig.Load(filepath);
                });

                Classes.StartupSplash.SetStatus("Opening login...");

                var login = new Login();

                // switch main form safely via wrapper method
                _app.SwitchMainForm(login);

                login.Show();
                Close();
            }
            catch (Exception ex)
            {
                Classes.StartupSplash.Close();
                XtraMessageBox.Show(ex.ToString(), "Startup error");
                Application.Exit();
            }
        }
    }
}