
using DevExpress.LookAndFeel;
using DevExpress.Skins;
using System;
using System.Drawing;
using System.IO;
using System.Text;
using System.Windows.Forms;

namespace SalesInventorySystem
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            // Wired first, before anything else runs -- a machine-specific crash was being
            // masked by a second, unrelated crash inside .NET's own default ThreadExceptionDialog
            // (System.BadImageFormatException thrown while building the exception's display
            // text), so the real root-cause exception was never visible anywhere. These handlers
            // log the real exception to a text file before .NET's own dialog machinery gets a
            // chance to run and potentially fail the same way.

            //Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
            //Application.ThreadException += (s, e) => HandleFatalException(e.Exception, "UI Thread");
            //AppDomain.CurrentDomain.UnhandledException += (s, e) => HandleFatalException(e.ExceptionObject as Exception, "Background Thread");

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

        // Deliberately avoids ex.ToString()/ex.StackTrace -- both internally rely on
        // System.Diagnostics.StackTrace's reflection-based frame formatting
        // (RuntimeMethodInfo.GetParameters), which is exactly what threw
        // System.BadImageFormatException on a deployed machine, crashing the process a
        // second time before the real exception could ever be seen. Exception type +
        // Message + the InnerException chain needs no such reflection and is enough to
        // identify most root causes (missing/mismatched assembly, SQL error, etc.).
        private static void HandleFatalException(Exception ex, string source)
        {
            try
            {
                var sb = new StringBuilder();
                sb.AppendLine("==== " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " [" + source + "] ====");

                Exception cur = ex;
                int depth = 0;
                while (cur != null && depth < 10)
                {
                    sb.AppendLine(new string(' ', depth * 2) + cur.GetType().FullName + ": " + cur.Message);
                    cur = cur.InnerException;
                    depth++;
                }
                sb.AppendLine();

                string text = sb.ToString();
                string primaryPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "crash_log.txt");
                try
                {
                    File.AppendAllText(primaryPath, text);
                }
                catch
                {
                    // The app folder may be read-only on some machines -- fall back to Temp.
                    File.AppendAllText(Path.Combine(Path.GetTempPath(), "SalesInventorySystem_crash_log.txt"), text);
                }

                MessageBox.Show(
                    "An unexpected error occurred and has been logged to crash_log.txt next to the application (or in your Temp folder).\n\nPlease send this file for troubleshooting.\n\n" + ex?.GetType().FullName + ": " + ex?.Message,
                    "Unexpected Error",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            catch
            {
                // Logging/display must never itself throw -- this is the last line of defense.
            }
            finally
            {
                Environment.Exit(1);
            }
        }
    }
}
