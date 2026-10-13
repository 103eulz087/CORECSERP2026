using System;
using System.Linq;
using System.Runtime.InteropServices;

namespace SalesInventorySystem.POSV2.Devices
{
    // Cash drawer wired to the receipt printer's drawer port (the usual setup): opened by sending the ESC/POS
    // "pulse" bytes straight to the printer through the Windows spooler (RAW, so the driver doesn't print them).
    // PosV2Config.DrawerKick = 1 enables it; DrawerPrinter (blank = ReceiptPrinter, then the Windows default) and
    // DrawerCode (default 27,112,0,25,250 = ESC p 0 25 250, pin 2) cover other wiring.
    public static class PosCashDrawer
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private class DocInfo
        {
            [MarshalAs(UnmanagedType.LPWStr)] public string DocName;
            [MarshalAs(UnmanagedType.LPWStr)] public string OutputFile;
            [MarshalAs(UnmanagedType.LPWStr)] public string DataType;
        }

        [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool OpenPrinter(string name, out IntPtr handle, IntPtr defaults);
        [DllImport("winspool.drv", SetLastError = true)] private static extern bool ClosePrinter(IntPtr handle);
        [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool StartDocPrinter(IntPtr handle, int level, [In] DocInfo doc);
        [DllImport("winspool.drv", SetLastError = true)] private static extern bool EndDocPrinter(IntPtr handle);
        [DllImport("winspool.drv", SetLastError = true)] private static extern bool StartPagePrinter(IntPtr handle);
        [DllImport("winspool.drv", SetLastError = true)] private static extern bool EndPagePrinter(IntPtr handle);
        [DllImport("winspool.drv", SetLastError = true)] private static extern bool WritePrinter(IntPtr handle, byte[] bytes, int count, out int written);

        public static bool Enabled => PosV2Config.DrawerKick;

        // Opens the drawer; does nothing when it isn't enabled. Throws when the printer can't be reached (the caller shows it).
        public static void Open()
        {
            if (!Enabled) return;
            string printer = PosV2Config.DrawerPrinter;
            if (string.IsNullOrWhiteSpace(printer)) printer = new System.Drawing.Printing.PrinterSettings().PrinterName;   // the Windows default
            byte[] code = ParseCode(PosV2Config.DrawerCode);

            IntPtr h;
            if (!OpenPrinter(printer, out h, IntPtr.Zero)) throw new InvalidOperationException("Cash drawer: can't open printer '" + printer + "' (" + Marshal.GetLastWin32Error() + ").");
            try
            {
                if (!StartDocPrinter(h, 1, new DocInfo { DocName = "Cash drawer", DataType = "RAW" })) throw new InvalidOperationException("Cash drawer: the printer refused the job (" + Marshal.GetLastWin32Error() + ").");
                try
                {
                    StartPagePrinter(h);
                    int written;
                    WritePrinter(h, code, code.Length, out written);
                    EndPagePrinter(h);
                }
                finally { EndDocPrinter(h); }
            }
            finally { ClosePrinter(h); }
        }

        private static byte[] ParseCode(string s)
        {
            try
            {
                var bytes = (s ?? "").Split(new[] { ',', ' ' }, StringSplitOptions.RemoveEmptyEntries).Select(x => byte.Parse(x.Trim())).ToArray();
                if (bytes.Length > 0) return bytes;
            }
            catch (Exception) { }
            return new byte[] { 27, 112, 0, 25, 250 };
        }
    }
}
