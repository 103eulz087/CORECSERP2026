using System;
using System.Globalization;
using System.IO.Ports;
using System.Text.RegularExpressions;

namespace SalesInventorySystem.POSV2.Devices
{
    // Optional weighing scale on a serial port (PosV2Config.ScalePort, e.g. COM3; blank = no scale).
    // Most counter scales stream lines such as "ST,GS,+  1.250kg"; the last number on a line is taken as
    // the weight. WeightChanged is raised on the serial port's thread: the form must marshal it to the
    // UI thread (BeginInvoke) before touching a control (Known Bug Pattern #8).
    public sealed class PosScale : IDisposable
    {
        private static readonly Regex Number = new Regex(@"[-+]?\d+(\.\d+)?", RegexOptions.Compiled);
        private SerialPort _port;

        public event Action<decimal> WeightChanged;
        public bool IsOpen => _port != null && _port.IsOpen;

        public void Open(string portName)
        {
            if (string.IsNullOrWhiteSpace(portName)) return;
            _port = new SerialPort(portName, 9600, Parity.None, 8, StopBits.One) { ReadTimeout = 500, NewLine = "\r" };
            _port.DataReceived += (s, e) =>
            {
                try
                {
                    string data = _port.ReadExisting();
                    var matches = Number.Matches(data);
                    if (matches.Count == 0) return;
                    decimal w;
                    if (decimal.TryParse(matches[matches.Count - 1].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out w) && w >= 0)
                        WeightChanged?.Invoke(Math.Round(w, 3));
                }
                catch (Exception) { /* a garbled reading is ignored; the cashier can type the weight */ }
            };
            _port.Open();
        }

        public void Dispose()
        {
            try { if (_port != null && _port.IsOpen) _port.Close(); } catch (Exception) { }
            _port?.Dispose();
            _port = null;
        }
    }
}
