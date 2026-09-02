
using System;
using System.Windows.Forms;
using DevExpress.LookAndFeel;
using DevExpress.Skins;

namespace SalesInventorySystem
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            //DevExpress.ExpressApp.FrameworkSettings.DefaultSettingsCompatibilityMode = DevExpress.ExpressApp.FrameworkSettingsCompatibilityMode.v20_1;
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            DevExpress.UserSkins.BonusSkins.Register();
            //UserLookAndFeel.Default.SetSkinStyle(SkinStyle.);
            UserLookAndFeel.Default.SetSkinStyle(SkinStyle.WXICompact);

            // 1. Load your global cache first!
            GlobalCache.InitializeCompanyData();

            var app = new SingleInstanceApp();
            app.Run(args);
        }
    }
}
