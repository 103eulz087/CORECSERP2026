using System;
using System.Data;
using System.Data.SqlClient;
using System.Threading;
using System.Threading.Tasks;
using SalesInventorySystem.POSV2.Models;

namespace SalesInventorySystem.POSV2.Services
{
    // The background worker of POS V2. Every few seconds (or at once when nudged after a sale):
    //   1. checks the server is reachable (short connect timeout); if not, the terminal is "offline" and
    //      sales simply wait in the local outbox;
    //   2. registers the terminal on the server (gets its ID and OR series) when it isn't yet;
    //   3. refreshes the product / price list and the branch's stock copy every 30 minutes (or on request);
    //   4. sends the outbox in order: SHIFTOPEN / SALE / VOID / SHIFTCLOSE (spu_POSV2_OpenShift / PostSale / VoidSale /
    //      CloseShift; phase 3 also downloads the supervisors and retries a shift GL the server could not book yet).
    //      The server is idempotent by sale / shift GUID, so a
    //      sale whose reply was lost is reported DUPLICATE on the retry and marked posted.
    // A server refusal (errors 61010-61099: bad totals, OR outside the series, a discount not by its rule, a close whose counts
    // differ from the server's, ...) is permanent:
    // that sale is set aside as "needs attention" and the next ones go on. Any other error (network, timeout,
    // a lock) leaves it pending and stops this round, so sales stay in order.
    // Runs on a background thread and NEVER touches a control (Known Bug Pattern #8): status goes back to
    // the screen through the SynchronizationContext given to the constructor.
    public sealed class PosSyncService : IDisposable
    {
        private readonly PosLocalStore _store;
        private readonly SynchronizationContext _ui;
        private readonly AutoResetEvent _wake = new AutoResetEvent(false);
        private volatile bool _stop;
        private volatile bool _refreshRequested;
        private Task _loop;
        private DateTime _lastMasterRefresh = DateTime.MinValue;
        private DateTime? _lastPostedAt;

        public event EventHandler<PosSyncStatus> StatusChanged;   // raised on the UI thread
        public event EventHandler MasterDataRefreshed;           // raised on the UI thread

        public volatile bool IsOnline;

        public PosSyncService(PosLocalStore store, SynchronizationContext uiContext)
        {
            _store = store;
            _ui = uiContext;
        }

        public void Start()
        {
            if (_loop != null) return;
            _loop = Task.Run(() => Loop());
        }

        public void Nudge() => _wake.Set();

        public void RequestMasterRefresh()
        {
            _refreshRequested = true;
            _wake.Set();
        }

        private void Loop()
        {
            while (!_stop)
            {
                PosSyncStatus st;
                try { st = RunOnce(); }
                catch (Exception ex) { st = Status(false, "Sync error: " + ex.Message); }
                Raise(st);
                _wake.WaitOne(TimeSpan.FromSeconds(PosV2Config.SyncSeconds));
            }
        }

        private PosSyncStatus RunOnce()
        {
            string serverCs = PosV2Config.ServerConnectionString();
            using (var con = new SqlConnection(serverCs))
            {
                try { con.Open(); }
                catch (Exception ex)
                {
                    IsOnline = false;
                    return Status(false, "Offline: " + ex.Message);
                }
                IsOnline = true;

                // 2. registration
                var term = _store.GetTerminal();
                if (term == null || term.BranchCode != PosV2Config.BranchCode)
                {
                    Register(con);
                    term = _store.GetTerminal();
                }

                // 3. master data
                if (_refreshRequested || (DateTime.Now - _lastMasterRefresh).TotalMinutes >= 30 || _store.GetMeta("ProductsRefreshedAt") == null)
                {
                    // phase 5: keeps the BIR registration and the counters current (idempotent); a failure here must not stop the
                    // uploads below (UI review S1): the next refresh tries again
                    try { Register(con); } catch (Exception) { }
                    term = _store.GetTerminal();
                    RefreshMasterData(con, term.BranchCode);
                    _refreshRequested = false;
                    _lastMasterRefresh = DateTime.Now;
                    Post(() => MasterDataRefreshed?.Invoke(this, EventArgs.Empty));
                }

                // 4. outbox, oldest first
                string note = null;
                foreach (var item in _store.GetPendingOutbox(50))
                {
                    if (_stop) break;
                    try
                    {
                        string result, message; int shortLines;
                        if (item.Item3 == "RETURN")
                        {
                            var rt = _store.LoadReturn(item.Item2);
                            if (rt == null) { _store.MarkFailed(item.Item1, item.Item2, "The return is missing from the local database."); continue; }
                            PostReturn(con, term.TerminalID, rt, out result, out message);
                            _store.MarkReturnSent(item.Item1, item.Item2, "RETURN " + result + ": " + message);
                            _lastPostedAt = DateTime.Now;
                            if (message.Contains("Needs review")) note = "Return " + rt.ReturnNo + ": " + message;
                            continue;
                        }
                        if (item.Item3 == "SHIFTOPEN" || item.Item3 == "SHIFTCLOSE")
                        {
                            if (item.Item3 == "SHIFTOPEN") OpenShift(con, term.TerminalID, item.Item2, out result, out message);
                            else CloseShift(con, term.TerminalID, item.Item2, out result, out message);
                            _store.MarkShiftSent(item.Item1, item.Item2, item.Item3 + " " + result + ": " + message);
                            _lastPostedAt = DateTime.Now;
                            if (item.Item3 == "SHIFTCLOSE") note = message;
                            continue;
                        }
                        var sale = _store.LoadSale(item.Item2);
                        if (sale == null) { _store.MarkFailed(item.Item1, item.Item2, "The sale is missing from the local database."); continue; }
                        if (item.Item3 == "VOID")
                        {
                            VoidSale(con, term.TerminalID, sale, out result, out message);
                            _store.MarkVoidSent(item.Item1, item.Item2, "VOID " + result + ": " + message);
                            _lastPostedAt = DateTime.Now;
                            continue;
                        }
                        PostSale(con, term.TerminalID, sale, out result, out shortLines, out message);
                        _store.MarkPosted(item.Item1, item.Item2, shortLines, result + ": " + message);
                        _lastPostedAt = DateTime.Now;
                        if (shortLines > 0) note = "OR " + sale.ORNo + ": " + message;
                    }
                    catch (SqlException ex) when (ex.Number >= 61010 && ex.Number <= 61099)
                    {
                        _store.MarkFailed(item.Item1, item.Item2, ex.Message);
                        note = (item.Item3.StartsWith("SHIFT") ? "A shift event" : item.Item3 == "RETURN" ? "A return" : "A sale") + " was refused by the server: " + ex.Message;
                    }
                    catch (Exception ex)
                    {
                        _store.MarkAttempt(item.Item1, ex.Message);
                        return Status(true, "Upload interrupted, will retry: " + ex.Message);
                    }
                }
                return Status(true, note);
            }
        }

        private void Register(SqlConnection con)
        {
            using (var cmd = new SqlCommand("dbo.spu_POSV2_RegisterTerminal", con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 60 })
            {
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 10).Value = PosV2Config.BranchCode;
                cmd.Parameters.Add("@TerminalCode", SqlDbType.VarChar, 50).Value = PosV2Config.TerminalCode;
                cmd.Parameters.Add("@User", SqlDbType.VarChar, 60).Value = Login.isglobalUserID ?? "";
                cmd.Parameters.Add("@BIRMachine", SqlDbType.VarChar, 50).Value = string.IsNullOrWhiteSpace(PosV2Config.BIRMachine) ? (object)DBNull.Value : PosV2Config.BIRMachine;
                using (var r = cmd.ExecuteReader())
                {
                    if (!r.Read()) throw new InvalidOperationException("The server did not register this terminal.");
                    if (!r.GetBoolean(r.GetOrdinal("IsActive"))) throw new InvalidOperationException("This terminal is deactivated on the server.");
                    _store.SaveTerminal(r.GetInt32(r.GetOrdinal("TerminalID")), r.GetString(r.GetOrdinal("BranchCode")),
                                        r.GetString(r.GetOrdinal("TerminalCode")), r.GetString(r.GetOrdinal("ORPrefix")),
                                        r.GetInt64(r.GetOrdinal("LastORSeq")), r.GetInt32(r.GetOrdinal("LastZNo")), r.GetInt64(r.GetOrdinal("LastReturnSeq")),
                                        r.GetDecimal(r.GetOrdinal("LastAccumulated")));
                    // phase 5: the BIR registration printed on receipts / Z-readings (blank when the machine isn't linked yet)
                    foreach (var f in new[] { "BIRMachine", "BusinessName", "BusinessAddress", "TINNo", "MINNo", "SerialNo", "AccreditationNo", "PermitNumber" })
                    {
                        int i = r.GetOrdinal(f);
                        _store.SetMeta("BIR." + f, r.IsDBNull(i) ? null : Convert.ToString(r.GetValue(i)).Trim());
                    }
                    foreach (var f in new[] { "DateIssued", "DatePermitStart", "DatePermitEnd" })
                    {
                        int i = r.GetOrdinal(f);
                        _store.SetMeta("BIR." + f, r.IsDBNull(i) ? null : r.GetDateTime(i).ToString("yyyy-MM-dd"));
                    }
                }
            }
        }

        private void RefreshMasterData(SqlConnection con, string branch)
        {
            _store.ReplaceTable("PosProduct", Fetch(con, "dbo.sp_POSV2_GetProducts", branch));
            _store.ReplaceTable("PosStock", Fetch(con, "dbo.sp_POSV2_GetStock", branch));
            _store.ReplaceTable("PosDiscountType", Fetch(con, "dbo.sp_POSV2_GetDiscountTypes", null));
            _store.ReplaceTable("PosSupervisor", Fetch(con, "dbo.sp_POSV2_GetSupervisors", branch));   // phase 3: approvals work offline
            string customersAsOf = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");   // before the fetch: a charge posted meanwhile counts as unsent
            _store.ReplaceTable("PosCustomer", Fetch(con, "dbo.sp_POSV2_GetCustomers", branch));       // phase 4: charge sales + credit limit offline
            _store.SetMeta("CustomersRefreshedAt", customersAsOf);
            RetryShiftGL(con);
            _store.SetMeta("ProductsRefreshedAt", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
            using (var cmd = new SqlCommand("SELECT BranchName FROM dbo.Branches WHERE BranchCode = @b", con))
            {
                cmd.Parameters.Add("@b", SqlDbType.VarChar, 10).Value = branch;
                _store.SetMeta("BranchName", cmd.ExecuteScalar() as string);
            }
        }

        private static DataTable Fetch(SqlConnection con, string proc, string branch)
        {
            var dt = new DataTable();
            using (var cmd = new SqlCommand(proc, con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 120 })
            {
                if (branch != null) cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 10).Value = branch;
                new SqlDataAdapter(cmd).Fill(dt);
            }
            return dt;
        }

        // phase 3: the GL of this terminal's closed shifts that the server couldn't book yet (e.g. a closed month, reopened since)
        private void RetryShiftGL(SqlConnection con)
        {
            var term = _store.GetTerminal();
            if (term == null) return;
            try
            {
                using (var cmd = new SqlCommand("dbo.spu_POSV2_PostPendingShiftGL", con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 120 })
                {
                    cmd.Parameters.Add("@TerminalID", SqlDbType.Int).Value = term.TerminalID;
                    cmd.Parameters.Add("@User", SqlDbType.VarChar, 60).Value = Login.isglobalUserID ?? "";
                    using (var r = cmd.ExecuteReader())
                        while (r.Read())
                        {
                            var g = r.GetGuid(0);
                            string st = r.GetString(2);
                            _store.SetShiftMessage(g, "GL " + st + (r.IsDBNull(3) ? "" : ": ticket " + r.GetString(3)) + (r.IsDBNull(4) ? "" : " " + r.GetString(4)));
                        }
                }
            }
            catch (SqlException) { /* tried again at the next refresh */ }
        }

        private void OpenShift(SqlConnection con, int terminalId, Guid shiftGuid, out string result, out string message)
        {
            var sh = _store.LoadShift(shiftGuid);
            if (sh == null) throw new InvalidOperationException("The shift is missing from the local database.");
            using (var cmd = new SqlCommand("dbo.spu_POSV2_OpenShift", con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 60 })
            {
                cmd.Parameters.Add("@ShiftGUID", SqlDbType.UniqueIdentifier).Value = sh.ShiftGuid;
                cmd.Parameters.Add("@TerminalID", SqlDbType.Int).Value = terminalId;
                cmd.Parameters.Add("@ZNo", SqlDbType.Int).Value = sh.ZNo;
                cmd.Parameters.Add("@CashierUserID", SqlDbType.VarChar, 50).Value = sh.CashierUserID;
                cmd.Parameters.Add("@CashierName", SqlDbType.VarChar, 100).Value = (object)sh.CashierName ?? DBNull.Value;
                cmd.Parameters.Add("@OpenedAt", SqlDbType.DateTime2).Value = sh.OpenedAt;
                Money(cmd, "@BeginningCash", sh.BeginningCash);
                cmd.Parameters.Add("@User", SqlDbType.VarChar, 60).Value = sh.CashierUserID;
                using (var r = cmd.ExecuteReader())
                {
                    if (!r.Read()) throw new InvalidOperationException("The server gave no result for the shift.");
                    result = r.GetString(0); message = r.GetString(1);
                }
            }
        }

        private void CloseShift(SqlConnection con, int terminalId, Guid shiftGuid, out string result, out string message)
        {
            var rd = _store.ComputeReading(shiftGuid);
            if (rd == null) throw new InvalidOperationException("The shift is missing from the local database.");
            using (var cmd = new SqlCommand("dbo.spu_POSV2_CloseShift", con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 120 })
            {
                cmd.Parameters.Add("@ShiftGUID", SqlDbType.UniqueIdentifier).Value = shiftGuid;
                cmd.Parameters.Add("@TerminalID", SqlDbType.Int).Value = terminalId;
                cmd.Parameters.Add("@ClosedAt", SqlDbType.DateTime2).Value = (object)rd.Shift.ClosedAt ?? DateTime.Now;
                Money(cmd, "@CountedCash", rd.Shift.CountedCash ?? 0m);
                cmd.Parameters.Add("@SaleCount", SqlDbType.Int).Value = rd.SaleCount;
                cmd.Parameters.Add("@VoidCount", SqlDbType.Int).Value = rd.VoidCount;
                Money(cmd, "@NetAmount", rd.NetAmount);
                cmd.Parameters.Add("@ClearedSaleCount", SqlDbType.Int).Value = rd.ClearedSaleCount;
                Money(cmd, "@ClearedSaleAmount", rd.ClearedSaleAmount);
                cmd.Parameters.Add("@DrawerOpenCount", SqlDbType.Int).Value = rd.DrawerOpenCount;
                cmd.Parameters.Add("@ClearedLineCount", SqlDbType.Int).Value = rd.ClearedLineCount;
                Money(cmd, "@ClearedLineAmount", rd.ClearedLineAmount);
                cmd.Parameters.Add("@ReturnCount", SqlDbType.Int).Value = rd.ReturnCount;
                Money(cmd, "@ReturnNet", rd.ReturnNet);
                // the grand total printed on this Z-reading: the server stores it and lists a difference from its own
                var acc = cmd.Parameters.Add("@TerminalAccumulatedAfter", SqlDbType.Decimal);
                acc.Precision = 18; acc.Scale = 2;
                acc.Value = (object)rd.Shift.AccumulatedAfter ?? DBNull.Value;
                cmd.Parameters.Add("@ClosedBy", SqlDbType.VarChar, 60).Value = rd.Shift.ClosedBy ?? "";
                cmd.Parameters.Add("@ApprovedBy", SqlDbType.VarChar, 60).Value = (object)rd.Shift.CloseApprovedBy ?? DBNull.Value;
                cmd.Parameters.Add("@User", SqlDbType.VarChar, 60).Value = rd.Shift.ClosedBy ?? "";
                using (var r = cmd.ExecuteReader())
                {
                    if (!r.Read()) throw new InvalidOperationException("The server gave no result for the close.");
                    result = r.GetString(0);
                    message = r.GetString(r.GetOrdinal("Message"));
                }
            }
        }

        private static void PostReturn(SqlConnection con, int terminalId, PosReturn rt, out string result, out string message)
        {
            var lines = new DataTable();
            lines.Columns.Add("LineNo", typeof(int)); lines.Columns.Add("OrigLineNo", typeof(int)); lines.Columns.Add("Qty", typeof(decimal));
            lines.Columns.Add("GrossAmount", typeof(decimal)); lines.Columns.Add("DiscountAmount", typeof(decimal)); lines.Columns.Add("VatExemptAmount", typeof(decimal));
            lines.Columns.Add("NetAmount", typeof(decimal)); lines.Columns.Add("VatAmount", typeof(decimal));
            foreach (var l in rt.Lines)
                lines.Rows.Add(l.LineNo, l.OrigLineNo, l.Qty, l.GrossAmount, l.DiscountAmount, l.VatExemptAmount, l.NetAmount, l.VatAmount);
            using (var cmd = new SqlCommand("dbo.spu_POSV2_PostReturn", con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 120 })
            {
                cmd.Parameters.Add("@ReturnGUID", SqlDbType.UniqueIdentifier).Value = rt.ReturnGuid;
                cmd.Parameters.Add("@TerminalID", SqlDbType.Int).Value = terminalId;
                cmd.Parameters.Add("@ShiftGUID", SqlDbType.UniqueIdentifier).Value = rt.ShiftGuid;
                cmd.Parameters.Add("@ReturnNo", SqlDbType.VarChar, 30).Value = rt.ReturnNo;
                cmd.Parameters.Add("@OrigSaleGUID", SqlDbType.UniqueIdentifier).Value = rt.OrigSaleGuid;
                cmd.Parameters.Add("@ReturnDateTime", SqlDbType.DateTime2).Value = rt.ReturnDateTime;
                cmd.Parameters.Add("@CashierUserID", SqlDbType.VarChar, 50).Value = rt.CashierUserID ?? "";
                cmd.Parameters.Add("@CashierName", SqlDbType.VarChar, 100).Value = (object)rt.CashierName ?? DBNull.Value;
                cmd.Parameters.Add("@ApprovedBy", SqlDbType.VarChar, 60).Value = rt.ApprovedBy ?? "";
                cmd.Parameters.Add("@Reason", SqlDbType.VarChar, 300).Value = rt.Reason ?? "";
                Money(cmd, "@CashRefund", rt.CashRefund); Money(cmd, "@CardRefund", rt.CardRefund); Money(cmd, "@ChargeRefund", rt.ChargeRefund);
                cmd.Parameters.Add("@TerminalSavedAt", SqlDbType.DateTime2).Value = rt.SavedAt;
                var pl = cmd.Parameters.Add("@Lines", SqlDbType.Structured); pl.TypeName = "dbo.tt_POSV2_ReturnLine"; pl.Value = lines;
                cmd.Parameters.Add("@User", SqlDbType.VarChar, 60).Value = rt.CashierUserID ?? "";
                using (var r = cmd.ExecuteReader())
                {
                    if (!r.Read()) throw new InvalidOperationException("The server gave no result for the return.");
                    result = r.GetString(0); message = r.GetString(1);
                }
            }
        }

        // phase 4: a sale of the branch for the return screen, straight from the server (another terminal's sale, or the
        // live state: earlier returns anywhere, the charge invoice's open balance). Null when the OR no. is unknown.
        // Called off the UI thread by the screen (Known Bug #8); short timeouts, so an unreachable server fails fast.
        public static PosReturnSource FetchReturnSource(string branch, string orNo)
        {
            using (var con = new SqlConnection(PosV2Config.ServerConnectionString()))
            using (var cmd = new SqlCommand("dbo.sp_POSV2_GetSaleForReturn", con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 20 })
            {
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 10).Value = branch;
                cmd.Parameters.Add("@ORNo", SqlDbType.VarChar, 30).Value = orNo;
                con.Open();
                using (var r = cmd.ExecuteReader())
                {
                    if (!r.Read()) return null;
                    var src = new PosReturnSource
                    {
                        FromServer = true, SaleGuid = r.GetGuid(0), ORNo = r.GetString(1), SaleDateTime = r.GetDateTime(2),
                        CustomerKey = r.IsDBNull(5) ? null : r.GetString(5), CustomerName = r.IsDBNull(6) ? null : r.GetString(6), Status = r.GetString(7),
                        ChargeBalance = r.IsDBNull(11) ? (decimal?)null : r.GetDecimal(11)
                    };
                    r.NextResult();
                    while (r.Read())
                        src.Lines.Add(new PosReturnSourceLine
                        {
                            LineNo = r.GetInt32(0), ProductCode = r.GetString(1), Description = r.IsDBNull(3) ? "" : r.GetString(3), Qty = r.GetDecimal(4),
                            UnitPrice = r.GetDecimal(6), Gross = PosPricingService.R2(r.GetDecimal(4) * r.GetDecimal(6)), LineTotal = r.GetDecimal(8),
                            IsVat = r.GetBoolean(9), VatAmount = r.GetDecimal(10), DiscountAmount = r.GetDecimal(13), VatExemptAmount = r.GetDecimal(14),
                            ReturnedQty = r.GetDecimal(15), ReturnedGross = r.GetDecimal(16), ReturnedDiscount = r.GetDecimal(17),
                            ReturnedVatExempt = r.GetDecimal(18), ReturnedNet = r.GetDecimal(19), ReturnedVat = r.GetDecimal(20)
                        });
                    r.NextResult();
                    while (r.Read())
                    {
                        string t = r.GetString(0); decimal paid = r.GetDecimal(1), refunded = r.GetDecimal(2), change = r.GetDecimal(3);
                        if (t == "CASH") { src.PaidCash = paid - change; src.RefundedCash = refunded; }
                        else if (t == "CARD") { src.PaidCard = paid; src.RefundedCard = refunded; }
                        else if (t == "CHARGE") { src.PaidCharge = paid; src.RefundedCharge = refunded; }
                    }
                    return src;
                }
            }
        }

        private static void VoidSale(SqlConnection con, int terminalId, PosSale s, out string result, out string message)
        {
            using (var cmd = new SqlCommand("dbo.spu_POSV2_VoidSale", con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 120 })
            {
                cmd.Parameters.Add("@SaleGUID", SqlDbType.UniqueIdentifier).Value = s.SaleGuid;
                cmd.Parameters.Add("@TerminalID", SqlDbType.Int).Value = terminalId;
                cmd.Parameters.Add("@Reason", SqlDbType.VarChar, 300).Value = s.VoidReason ?? "";
                cmd.Parameters.Add("@VoidedAt", SqlDbType.DateTime2).Value = (object)s.VoidedAt ?? DateTime.Now;
                cmd.Parameters.Add("@User", SqlDbType.VarChar, 60).Value = s.VoidedBy ?? s.CashierUserID ?? "";
                cmd.Parameters.Add("@ApprovedBy", SqlDbType.VarChar, 60).Value = (object)s.VoidApprovedBy ?? DBNull.Value;
                using (var r = cmd.ExecuteReader())
                {
                    if (!r.Read()) throw new InvalidOperationException("The server gave no result for the void.");
                    result = r.GetString(0);
                    message = r.GetString(1);
                }
            }
        }

        private static void PostSale(SqlConnection con, int terminalId, PosSale s, out string result, out int shortLines, out string message)
        {
            var lines = new DataTable();
            lines.Columns.Add("LineNo", typeof(int)); lines.Columns.Add("ProductCode", typeof(string)); lines.Columns.Add("Barcode", typeof(string));
            lines.Columns.Add("Description", typeof(string)); lines.Columns.Add("Qty", typeof(decimal)); lines.Columns.Add("PriceLevel", typeof(string));
            lines.Columns.Add("UnitPrice", typeof(decimal)); lines.Columns.Add("LineDiscount", typeof(decimal)); lines.Columns.Add("LineTotal", typeof(decimal));
            lines.Columns.Add("IsVat", typeof(bool)); lines.Columns.Add("VatAmount", typeof(decimal));
            lines.Columns.Add("DiscNo", typeof(int)); lines.Columns.Add("DiscountCode", typeof(string));
            lines.Columns.Add("DiscountAmount", typeof(decimal)); lines.Columns.Add("VatExemptAmount", typeof(decimal));
            foreach (var l in s.Lines)
                lines.Rows.Add(l.LineNo, l.ProductCode, (object)l.Barcode ?? DBNull.Value, (object)l.Description ?? DBNull.Value, l.Qty, l.PriceLevel,
                               l.UnitPrice, l.LineDiscount, l.LineTotal, l.IsVat, l.VatAmount,
                               (object)l.DiscNo ?? DBNull.Value, (object)l.DiscountCode ?? DBNull.Value, l.DiscountAmount, l.VatExemptAmount);

            var discs = new DataTable();
            discs.Columns.Add("DiscNo", typeof(int)); discs.Columns.Add("DiscountCode", typeof(string)); discs.Columns.Add("Percent", typeof(decimal));
            discs.Columns.Add("Amount", typeof(decimal)); discs.Columns.Add("VatExemptAmount", typeof(decimal)); discs.Columns.Add("CustomerName", typeof(string));
            discs.Columns.Add("IDNo", typeof(string)); discs.Columns.Add("TIN", typeof(string)); discs.Columns.Add("Remarks", typeof(string));
            foreach (var d in s.Discounts)
                discs.Rows.Add(d.DiscNo, d.DiscountCode, d.Percent, d.Amount, d.VatExemptAmount, (object)d.CustomerName ?? DBNull.Value,
                               (object)d.IDNo ?? DBNull.Value, (object)d.TIN ?? DBNull.Value, (object)d.Remarks ?? DBNull.Value);

            var pays = new DataTable();
            pays.Columns.Add("PayNo", typeof(int)); pays.Columns.Add("PaymentType", typeof(string));
            pays.Columns.Add("Amount", typeof(decimal)); pays.Columns.Add("Reference", typeof(string));
            foreach (var p in s.Payments) pays.Rows.Add(p.PayNo, p.PaymentType, p.Amount, (object)p.Reference ?? DBNull.Value);

            using (var cmd = new SqlCommand("dbo.spu_POSV2_PostSale", con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 120 })
            {
                cmd.Parameters.Add("@SaleGUID", SqlDbType.UniqueIdentifier).Value = s.SaleGuid;
                cmd.Parameters.Add("@TerminalID", SqlDbType.Int).Value = terminalId;
                cmd.Parameters.Add("@ORNo", SqlDbType.VarChar, 30).Value = s.ORNo;
                cmd.Parameters.Add("@SaleDateTime", SqlDbType.DateTime2).Value = s.SaleDateTime;
                cmd.Parameters.Add("@CashierUserID", SqlDbType.VarChar, 50).Value = s.CashierUserID ?? "";
                cmd.Parameters.Add("@CashierName", SqlDbType.VarChar, 100).Value = (object)s.CashierName ?? DBNull.Value;
                cmd.Parameters.Add("@CustomerKey", SqlDbType.VarChar, 20).Value = (object)s.CustomerKey ?? DBNull.Value;
                Money(cmd, "@GrossAmount", s.GrossAmount); Money(cmd, "@DiscountAmount", s.DiscountAmount); Money(cmd, "@NetAmount", s.NetAmount);
                Money(cmd, "@VatableSales", s.VatableSales); Money(cmd, "@VatAmount", s.VatAmount); Money(cmd, "@VatExemptSales", s.VatExemptSales);
                Money(cmd, "@ZeroRatedSales", s.ZeroRatedSales); Money(cmd, "@AmountTendered", s.AmountTendered); Money(cmd, "@ChangeAmount", s.ChangeAmount);
                cmd.Parameters.Add("@WasOffline", SqlDbType.Bit).Value = s.WasOffline;
                cmd.Parameters.Add("@TerminalSavedAt", SqlDbType.DateTime2).Value = s.SavedAt;
                var pl = cmd.Parameters.Add("@Lines", SqlDbType.Structured); pl.TypeName = "dbo.tt_POSV2_SaleLine"; pl.Value = lines;
                var pp = cmd.Parameters.Add("@Payments", SqlDbType.Structured); pp.TypeName = "dbo.tt_POSV2_Payment"; pp.Value = pays;
                cmd.Parameters.Add("@User", SqlDbType.VarChar, 60).Value = s.CashierUserID ?? "";
                var pd = cmd.Parameters.Add("@Discounts", SqlDbType.Structured); pd.TypeName = "dbo.tt_POSV2_SaleDiscount"; pd.Value = discs;
                cmd.Parameters.Add("@CancelledLineCount", SqlDbType.Int).Value = s.CancelledLineCount;
                Money(cmd, "@CancelledLineAmount", s.CancelledLineAmount);
                cmd.Parameters.Add("@ShiftGUID", SqlDbType.UniqueIdentifier).Value = s.ShiftGuid == Guid.Empty ? (object)DBNull.Value : s.ShiftGuid;
                cmd.Parameters.Add("@DiscountApprovedBy", SqlDbType.VarChar, 60).Value = (object)s.DiscountApprovedBy ?? DBNull.Value;
                cmd.Parameters.Add("@CreditApprovedBy", SqlDbType.VarChar, 60).Value = (object)s.CreditApprovedBy ?? DBNull.Value;
                using (var r = cmd.ExecuteReader())
                {
                    if (!r.Read()) throw new InvalidOperationException("The server gave no result for the sale.");
                    result = r.GetString(0);
                    shortLines = r.GetInt32(1);
                    message = r.GetString(2);
                }
            }
        }

        private static void Money(SqlCommand cmd, string name, decimal v)
        {
            var p = cmd.Parameters.Add(name, SqlDbType.Decimal); p.Precision = 18; p.Scale = 2; p.Value = v;
        }

        private PosSyncStatus Status(bool online, string message)
        {
            int pending = 0, failed = 0;
            try { _store.Counts(out pending, out failed); } catch (Exception) { }
            DateTime? refreshed = null;
            try { DateTime d; if (DateTime.TryParse(_store.GetMeta("ProductsRefreshedAt"), out d)) refreshed = d; } catch (Exception) { }
            bool registered = false;
            try { registered = _store.GetTerminal() != null; } catch (Exception) { }
            return new PosSyncStatus { Online = online, Registered = registered, Pending = pending, Failed = failed,
                                       LastPostedAt = _lastPostedAt, ProductsRefreshedAt = refreshed, Message = message };
        }

        private void Raise(PosSyncStatus st) => Post(() => StatusChanged?.Invoke(this, st));

        private void Post(Action a)
        {
            if (_stop) return;
            if (_ui != null) _ui.Post(_ => { if (!_stop) a(); }, null);
            else a();
        }

        // Stops the worker; an upload in progress finishes first (up to the given time).
        public void Dispose()
        {
            _stop = true;
            _wake.Set();
            try { _loop?.Wait(TimeSpan.FromSeconds(30)); } catch (Exception) { }
            _wake.Dispose();
        }
    }
}
