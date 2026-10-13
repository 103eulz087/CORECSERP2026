using System;
using System.Data.SqlClient;
using Microsoft.Win32;

namespace SalesInventorySystem.POSV2
{
    // POS V2 (docs/plans/2026-10-12_POS_V2_Hybrid_Plan.md): per-machine settings under HKCU\AAITCRE\POSV2.
    // No credentials are stored here: the connection strings come from the existing DPAPI-protected
    // ConnSettings* keys (Database.getConnectionString); this only names which key / catalog to use.
    //   Enabled        1 = Main's POS menu opens POS V2 on this machine (else the old POS)
    //   ServerConnKey  key of the server (shared) database   default AAITCRE\ConnSettingsMain
    //   ServerCatalog  optional catalog override for the server key
    //   LocalConnKey   key of this terminal's local SQL Server default AAITCRE\ConnSettingsLocal
    //   LocalCatalog   POS V2's own local database          default CORECS_POSV2 (created on first run)
    //   BranchCode     default: the logged-in user's branch
    //   TerminalCode   default: the machine name
    //   ReceiptPrinter blank = Windows default printer;  ScalePort  blank = no scale (e.g. COM3)
    //   SyncSeconds    how often the sync worker checks the server, default 3
    //   phase 3:
    //   DrawerKick     1 = open the cash drawer through the receipt printer on a cash sale / no-sale
    //   DrawerPrinter  blank = ReceiptPrinter (then the Windows default);  DrawerCode  default 27,112,0,25,250
    //   PolePort       customer display pole, blank = none (e.g. COM4);  PoleBaud  default 9600
    //   phase 5:
    //   BIRMachine     this machine's POSInfoDetails.MachineUsed on its branch (its BIR registration: TIN, MIN, serial no.,
    //                  accreditation, permit), printed on receipts and Z-readings; blank = keep what the server has
    public static class PosV2Config
    {
        private const string KeyPath = @"AAITCRE\POSV2";

        private static string Get(string name, string fallback)
        {
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(KeyPath, false))
                {
                    var v = k?.GetValue(name) as string;
                    return string.IsNullOrWhiteSpace(v) ? fallback : v.Trim();
                }
            }
            catch (Exception) { return fallback; }
        }

        public static bool IsEnabledOnThisMachine => Get("Enabled", "0") == "1";
        public static string ServerConnKey => Get("ServerConnKey", @"AAITCRE\ConnSettingsMain");
        public static string ServerCatalog => Get("ServerCatalog", "");
        public static string LocalConnKey => Get("LocalConnKey", @"AAITCRE\ConnSettingsLocal");
        public static string LocalCatalog => Get("LocalCatalog", "CORECS_POSV2");
        public static string BranchCode => Get("BranchCode", Login.assignedBranch ?? "");
        public static string TerminalCode => Get("TerminalCode", Environment.MachineName);
        public static string ReceiptPrinter => Get("ReceiptPrinter", "");
        public static string ScalePort => Get("ScalePort", "");
        public static int SyncSeconds
        {
            get { int s; return int.TryParse(Get("SyncSeconds", "3"), out s) && s > 0 ? s : 3; }
        }
        public static bool DrawerKick => Get("DrawerKick", "0") == "1";
        public static string DrawerPrinter => Get("DrawerPrinter", ReceiptPrinter);
        public static string DrawerCode => Get("DrawerCode", "27,112,0,25,250");
        public static string PolePort => Get("PolePort", "");
        public static string BIRMachine => Get("BIRMachine", "");
        public static int PoleBaud
        {
            get { int b; return int.TryParse(Get("PoleBaud", "9600"), out b) && b > 0 ? b : 9600; }
        }

        // short connect timeout: the sync worker must notice "offline" quickly
        public static string ServerConnectionString() => Build(ServerConnKey, ServerCatalog, 5);

        public static string LocalConnectionString() => Build(LocalConnKey, LocalCatalog, 10);

        public static string LocalMasterConnectionString() => Build(LocalConnKey, "master", 10);

        private static string Build(string key, string catalog, int connectTimeout)
        {
            string cs = Database.getConnectionString(key);
            if (string.IsNullOrWhiteSpace(cs))
                throw new InvalidOperationException("POS V2: the connection setting " + key + " is not configured on this machine.");
            var b = new SqlConnectionStringBuilder(cs);
            if (!string.IsNullOrWhiteSpace(catalog)) b.InitialCatalog = catalog;
            b.ConnectTimeout = connectTimeout;
            return b.ConnectionString;
        }
    }
}
