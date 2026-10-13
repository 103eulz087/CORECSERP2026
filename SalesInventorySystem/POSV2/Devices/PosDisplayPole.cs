using System;
using System.IO.Ports;
using System.Text;

namespace SalesInventorySystem.POSV2.Devices
{
    // Customer display pole (2 lines x 20 characters, VFD / LCD) on a serial port: PosV2Config.PolePort (e.g. COM4;
    // blank = no pole), PoleBaud (default 9600). Uses the common command set: 0x0C clears, then 40 characters fill
    // both lines. A pole that is missing or unplugged never stops a sale: every write failure is swallowed and the
    // pole is simply dropped until the next start.
    public sealed class PosDisplayPole : IDisposable
    {
        private const int Width = 20;
        private SerialPort _port;
        private readonly object _gate = new object();

        public bool IsOpen => _port != null && _port.IsOpen;

        public void Open(string portName, int baud)
        {
            if (string.IsNullOrWhiteSpace(portName)) return;
            _port = new SerialPort(portName, baud > 0 ? baud : 9600, Parity.None, 8, StopBits.One) { WriteTimeout = 300, Encoding = Encoding.ASCII };
            _port.Open();
        }

        // Two lines: the left one is cut / padded to 20 characters; numbers on the right (e.g. "TOTAL", "1,234.50").
        public void Show(string line1, string line2)
        {
            if (!IsOpen) return;
            lock (_gate)
            {
                try
                {
                    _port.Write(new byte[] { 0x0C }, 0, 1);
                    _port.Write(Fit(line1) + Fit(line2));
                }
                catch (Exception) { try { _port.Close(); } catch (Exception) { } }
            }
        }

        public void ShowLeftRight(string left1, string right1, string left2, string right2) =>
            Show(LeftRight(left1, right1), LeftRight(left2, right2));

        public void Welcome(string branch) => Show(Center("WELCOME"), Center(branch ?? ""));

        private static string Ascii(string s)
        {
            var sb = new StringBuilder();
            foreach (char c in s ?? "") sb.Append(c >= 32 && c < 127 ? c : (c == 'Ñ' ? 'N' : c == 'ñ' ? 'n' : '?'));
            return sb.ToString();
        }

        private static string Fit(string s)
        {
            s = Ascii(s);
            return s.Length >= Width ? s.Substring(0, Width) : s.PadRight(Width);
        }

        private static string Center(string s)
        {
            s = Ascii(s);
            if (s.Length >= Width) return s.Substring(0, Width);
            return new string(' ', (Width - s.Length) / 2) + s;
        }

        private static string LeftRight(string left, string right)
        {
            left = Ascii(left); right = Ascii(right ?? "");
            if (right.Length >= Width) return right.Substring(0, Width);
            int room = Width - right.Length - 1;
            if (left.Length > room) left = left.Substring(0, Math.Max(0, room));
            return left + new string(' ', Width - left.Length - right.Length) + right;
        }

        public void Dispose()
        {
            lock (_gate)
            {
                try { if (IsOpen) { _port.Write(new byte[] { 0x0C }, 0, 1); _port.Close(); } } catch (Exception) { }
                _port?.Dispose();
                _port = null;
            }
        }
    }
}
