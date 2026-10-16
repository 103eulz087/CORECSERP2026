using System;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Windows.Forms;

namespace SalesInventorySystem.Classes
{
    /// <summary>
    /// 2026-10-15: "please wait" window for the dead time of a cold start, above all after an update.
    /// exeUpdater closes itself and starts the new exe from a hidden batch file; until the Login screen shows
    /// (Program.Main's DB work, StartupForm, Login_Load's update check) nothing was on screen, and Windows
    /// won't let a newly started process take the foreground once the user has clicked another window, so
    /// the Login opened behind other windows and the restart looked stopped.
    ///
    /// Plain WinForms (no DevExpress, so it shows before the heavy assemblies load), on its own STA thread
    /// with its own message loop (stays painted while the main thread is busy), TopMost (a click elsewhere
    /// can't hide it). Show() is the first thing in Program.Main; Close() runs when the Login is shown, and
    /// before any startup dialog (a TopMost window would cover it). Every call is safe from any thread and
    /// more than once.
    /// </summary>
    public static class StartupSplash
    {
        // Login.tryCheckUpdate writes this file before handing over to exeUpdater; the next start says
        // "Finishing the update" instead of "Starting", then deletes it.
        public const string UpdateMarkerFile = "update_pending.flag";

        private static readonly object _gate = new object();
        private static SplashForm _form;
        private static Thread _thread;
        private static bool _closed;

        public static string UpdateMarkerPath => Path.Combine(Application.StartupPath, UpdateMarkerFile);

        public static void Show()
        {
            ManualResetEventSlim shown;
            lock (_gate)
            {
                if (_thread != null || _closed) return;

                bool afterUpdate = false;
                try { afterUpdate = File.Exists(UpdateMarkerPath); } catch { }

                var ready = new ManualResetEventSlim(false);
                _thread = new Thread(() =>
                {
                    try
                    {
                        var f = new SplashForm(afterUpdate);
                        f.HandleCreated += (s, e) => ready.Set();
                        lock (_gate)
                        {
                            if (_closed) { f.Dispose(); return; }   // Close() came first: never show it
                            _form = f;
                        }
                        Application.Run(f);
                    }
                    catch { }
                    finally { ready.Set(); }
                })
                {
                    IsBackground = true,
                    Name = "StartupSplash"
                };
                _thread.SetApartmentState(ApartmentState.STA);
                _thread.Start();
                shown = ready;
            }
            shown.Wait(3000);   // outside the lock (the splash thread takes it): shown before Main goes on, never blocks long
        }

        /// <summary>Changes the line under the title ("Loading config...", "Checking for updates...").</summary>
        public static void SetStatus(string text)
        {
            SplashForm f;
            lock (_gate) { f = _form; }
            if (f == null) return;
            try
            {
                if (f.IsHandleCreated && !f.IsDisposed)
                    f.BeginInvoke((Action)(() => f.SetStatus(text)));
            }
            catch { }
        }

        public static void Close()
        {
            SplashForm f;
            lock (_gate)
            {
                if (_closed) return;
                _closed = true;
                f = _form;
                _form = null;
            }

            try { if (File.Exists(UpdateMarkerPath)) File.Delete(UpdateMarkerPath); } catch { }

            if (f == null) return;
            try
            {
                if (f.IsHandleCreated && !f.IsDisposed)
                    f.Invoke((Action)(() => f.Close()));   // ends the splash thread's message loop
            }
            catch { }
        }

        /// <summary>Brings a window to the front even when Windows would only flash it in the taskbar.</summary>
        public static void BringToFront(Form form)
        {
            if (form == null || form.IsDisposed) return;
            try
            {
                if (form.WindowState == FormWindowState.Minimized) form.WindowState = FormWindowState.Normal;
                form.TopMost = true;    // a TopMost toggle puts it above other windows without the foreground right
                form.BringToFront();
                form.Activate();
                form.TopMost = false;
            }
            catch { }
        }

        private sealed class SplashForm : Form
        {
            private readonly Label _status;

            public SplashForm(bool afterUpdate)
            {
                FormBorderStyle = FormBorderStyle.None;
                StartPosition = FormStartPosition.CenterScreen;
                ShowInTaskbar = true;
                TopMost = true;
                ControlBox = false;
                Text = "CORE-X ERP";
                Size = new Size(440, 150);
                BackColor = Color.FromArgb(32, 45, 64);
                ForeColor = Color.White;
                Padding = new Padding(1);

                var title = new Label
                {
                    Text = afterUpdate ? "Finishing the update..." : "Starting CORE-X ERP...",
                    Font = new Font("Segoe UI", 13F, FontStyle.Bold),
                    ForeColor = Color.White,
                    AutoSize = false,
                    Location = new Point(24, 20),
                    Size = new Size(392, 30)
                };
                var note = new Label
                {
                    Text = afterUpdate
                        ? "The new version is opening. Please wait and don't start the program again."
                        : "Please wait.",
                    Font = new Font("Segoe UI", 9F),
                    ForeColor = Color.FromArgb(210, 220, 235),
                    AutoSize = false,
                    Location = new Point(24, 52),
                    Size = new Size(392, 34)
                };
                var bar = new ProgressBar
                {
                    Style = ProgressBarStyle.Marquee,
                    MarqueeAnimationSpeed = 30,
                    Location = new Point(24, 92),
                    Size = new Size(392, 14)
                };
                _status = new Label
                {
                    Text = "",
                    Font = new Font("Segoe UI", 8.25F),
                    ForeColor = Color.FromArgb(170, 185, 205),
                    AutoSize = false,
                    Location = new Point(24, 112),
                    Size = new Size(392, 20)
                };
                Controls.Add(title);
                Controls.Add(note);
                Controls.Add(bar);
                Controls.Add(_status);
            }

            public void SetStatus(string text) => _status.Text = text ?? "";

            // shows without taking the focus away from whatever the user is doing
            protected override bool ShowWithoutActivation => true;

            protected override CreateParams CreateParams
            {
                get
                {
                    const int WS_EX_TOPMOST = 0x00000008;
                    var cp = base.CreateParams;
                    cp.ExStyle |= WS_EX_TOPMOST;
                    return cp;
                }
            }

            protected override void OnPaint(PaintEventArgs e)
            {
                base.OnPaint(e);
                using (var pen = new Pen(Color.FromArgb(70, 95, 130)))
                    e.Graphics.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
            }
        }
    }
}
