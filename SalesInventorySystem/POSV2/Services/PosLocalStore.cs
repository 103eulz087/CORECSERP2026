using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Linq;
using SalesInventorySystem.POSV2.Models;

namespace SalesInventorySystem.POSV2.Services
{
    // All access to the terminal's local database. A sale is saved in ONE local transaction (header, lines,
    // discounts, payments, its OR number and its outbox row), so a crash or power cut never leaves half a sale.
    // A void is also one local transaction (the sale marked VOIDED + a VOID outbox row behind the sale's own
    // SALE row, so the server always gets the sale first). Thread safe: every call opens its own connection
    // (the UI and the sync worker both use it).
    public sealed class PosLocalStore
    {
        private readonly string _cs;

        public PosLocalStore()
        {
            _cs = PosV2Config.LocalConnectionString();
        }

        private SqlConnection Open()
        {
            var con = new SqlConnection(_cs);
            con.Open();
            return con;
        }

        // Creates the local database and its tables when missing (first run on a terminal); adds new columns.
        public void EnsureDatabase()
        {
            using (var con = new SqlConnection(PosV2Config.LocalMasterConnectionString()))
            using (var cmd = new SqlCommand(PosLocalSchema.CreateDatabase, con))
            {
                cmd.Parameters.Add("@db", SqlDbType.NVarChar, 128).Value = PosV2Config.LocalCatalog;
                con.Open();
                cmd.ExecuteNonQuery();
            }
            using (var con = Open())
            using (var cmd = new SqlCommand(PosLocalSchema.Tables, con) { CommandTimeout = 120 })
                cmd.ExecuteNonQuery();
        }

        // ── terminal ───────────────────────────────────────────────────
        public PosTerminalInfo GetTerminal()
        {
            using (var con = Open())
            using (var cmd = new SqlCommand("SELECT TerminalID, BranchCode, TerminalCode, ORPrefix, NextORSeq, NextZNo, NextReturnSeq FROM dbo.PosTerminal WHERE Id = 1", con))
            using (var r = cmd.ExecuteReader())
            {
                if (!r.Read()) return null;
                return new PosTerminalInfo
                {
                    TerminalID = r.GetInt32(0), BranchCode = r.GetString(1), TerminalCode = r.GetString(2),
                    ORPrefix = r.GetString(3), NextORSeq = r.GetInt64(4), NextZNo = r.GetInt32(5), NextReturnSeq = r.GetInt64(6)
                };
            }
        }

        // The server's registration. The OR series and the Z counter never go back: next = max(local next, server's last + 1).
        public void SaveTerminal(int terminalId, string branch, string terminalCode, string prefix, long serverLastSeq, int serverLastZ, long serverLastReturn, decimal serverAccumulated)
        {
            const string sql = @"
IF EXISTS (SELECT 1 FROM dbo.PosTerminal WHERE Id = 1)
    UPDATE dbo.PosTerminal
    SET TerminalID = @id, BranchCode = @b, TerminalCode = @t, ORPrefix = @p,
        -- the same terminal: counters only move up; another terminal ID (branch changed): its own counters (UI review S2)
        NextORSeq = CASE WHEN TerminalID = @id AND NextORSeq > @last + 1 THEN NextORSeq ELSE @last + 1 END,
        NextZNo = CASE WHEN TerminalID = @id AND NextZNo > @lastz + 1 THEN NextZNo ELSE @lastz + 1 END,
        NextReturnSeq = CASE WHEN TerminalID = @id AND NextReturnSeq > @lastr + 1 THEN NextReturnSeq ELSE @lastr + 1 END,
        AccumulatedTotal = CASE WHEN TerminalID = @id AND AccumulatedTotal > @acc THEN AccumulatedTotal ELSE @acc END
    WHERE Id = 1;
ELSE
    INSERT INTO dbo.PosTerminal (Id, TerminalID, BranchCode, TerminalCode, ORPrefix, NextORSeq, NextZNo, NextReturnSeq, AccumulatedTotal)
    VALUES (1, @id, @b, @t, @p, @last + 1, @lastz + 1, @lastr + 1, @acc);";
            using (var con = Open())
            using (var cmd = new SqlCommand(sql, con))
            {
                cmd.Parameters.Add("@id", SqlDbType.Int).Value = terminalId;
                cmd.Parameters.Add("@b", SqlDbType.VarChar, 10).Value = branch;
                cmd.Parameters.Add("@t", SqlDbType.VarChar, 50).Value = terminalCode;
                cmd.Parameters.Add("@p", SqlDbType.VarChar, 12).Value = prefix;
                cmd.Parameters.Add("@last", SqlDbType.BigInt).Value = serverLastSeq;
                cmd.Parameters.Add("@lastz", SqlDbType.Int).Value = serverLastZ;
                cmd.Parameters.Add("@lastr", SqlDbType.BigInt).Value = serverLastReturn;
                AddMoney(cmd, "@acc", serverAccumulated);
                cmd.ExecuteNonQuery();
            }
        }

        // ── master data ────────────────────────────────────────────────
        // Replaces the local copy in one transaction, so the screen never sees a half-loaded list.
        public void ReplaceTable(string table, DataTable rows)
        {
            if (table != "PosProduct" && table != "PosStock" && table != "PosDiscountType" && table != "PosSupervisor" && table != "PosCustomer") throw new ArgumentException("table");
            using (var con = Open())
            using (var tx = con.BeginTransaction())
            {
                using (var del = new SqlCommand("DELETE FROM dbo." + table, con, tx)) del.ExecuteNonQuery();
                using (var bulk = new SqlBulkCopy(con, SqlBulkCopyOptions.Default, tx) { DestinationTableName = "dbo." + table, BulkCopyTimeout = 120 })
                {
                    foreach (DataColumn c in rows.Columns) bulk.ColumnMappings.Add(c.ColumnName, c.ColumnName);
                    bulk.WriteToServer(rows);
                }
                tx.Commit();
            }
        }

        public List<PosProduct> LoadProducts()
        {
            var list = new List<PosProduct>();
            using (var con = Open())
            using (var cmd = new SqlCommand("SELECT ProductCode, Description, Barcode, SellingPrice, Price1, Price2, Price3, Price4, IsVat FROM dbo.PosProduct ORDER BY Description", con))
            using (var r = cmd.ExecuteReader())
                while (r.Read())
                    list.Add(new PosProduct
                    {
                        ProductCode = r.GetString(0), Description = r.IsDBNull(1) ? "" : r.GetString(1), Barcode = r.IsDBNull(2) ? "" : r.GetString(2),
                        SellingPrice = r.GetDecimal(3), Price1 = r.GetDecimal(4), Price2 = r.GetDecimal(5), Price3 = r.GetDecimal(6), Price4 = r.GetDecimal(7),
                        IsVat = r.GetBoolean(8)
                    });
            return list;
        }

        public List<PosDiscountType> LoadDiscountTypes()
        {
            var list = new List<PosDiscountType>();
            using (var con = Open())
            using (var cmd = new SqlCommand("SELECT DiscountCode, Name, Kind, [Percent], VatExempt, RequiresID, RequiresApproval FROM dbo.PosDiscountType ORDER BY SortOrder, DiscountCode", con))
            using (var r = cmd.ExecuteReader())
                while (r.Read())
                    list.Add(new PosDiscountType
                    {
                        DiscountCode = r.GetString(0), Name = r.GetString(1), Kind = r.GetString(2), Percent = r.GetDecimal(3),
                        VatExempt = r.GetBoolean(4), RequiresID = r.GetBoolean(5), RequiresApproval = r.GetBoolean(6)
                    });
            return list;
        }

        public List<PosSupervisor> LoadSupervisors()
        {
            var list = new List<PosSupervisor>();
            using (var con = Open())
            using (var cmd = new SqlCommand("SELECT UserID, FullName, PinHash, PinSalt, PinIterations FROM dbo.PosSupervisor", con))
            using (var r = cmd.ExecuteReader())
                while (r.Read())
                    list.Add(new PosSupervisor
                    {
                        UserID = r.GetString(0), FullName = r.IsDBNull(1) ? r.GetString(0) : r.GetString(1),
                        PinHash = (byte[])r[2], PinSalt = (byte[])r[3], PinIterations = r.GetInt32(4)
                    });
            return list;
        }

        public Dictionary<string, decimal> LoadStock()
        {
            var d = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase);
            using (var con = Open())
            using (var cmd = new SqlCommand("SELECT ProductCode, Available FROM dbo.PosStock", con))
            using (var r = cmd.ExecuteReader())
                while (r.Read()) d[r.GetString(0)] = r.GetDecimal(1);
            return d;
        }

        // phase 5: the BIR registration the server sent at the last registration (meta BIR.*)
        public Devices.PosBirInfo LoadBirInfo()
        {
            var m = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            using (var con = Open())
            using (var cmd = new SqlCommand("SELECT Name, Value FROM dbo.PosMeta WHERE Name LIKE 'BIR.%'", con))
            using (var r = cmd.ExecuteReader())
                while (r.Read()) m[r.GetString(0).Substring(4)] = r.IsDBNull(1) ? null : r.GetString(1);
            Func<string, string> g = k => { string v; return m.TryGetValue(k, out v) ? v : null; };
            return new Devices.PosBirInfo
            {
                BusinessName = g("BusinessName"), BusinessAddress = g("BusinessAddress"), TIN = g("TINNo"), MIN = g("MINNo"), SerialNo = g("SerialNo"),
                AccreditationNo = g("AccreditationNo"), DateIssued = g("DateIssued"), PermitNumber = g("PermitNumber"),
                PermitStart = g("DatePermitStart"), PermitEnd = g("DatePermitEnd")
            };
        }

        public string GetMeta(string name)
        {
            using (var con = Open())
            using (var cmd = new SqlCommand("SELECT Value FROM dbo.PosMeta WHERE Name = @n", con))
            {
                cmd.Parameters.Add("@n", SqlDbType.VarChar, 50).Value = name;
                return cmd.ExecuteScalar() as string;
            }
        }

        public void SetMeta(string name, string value)
        {
            using (var con = Open())
            using (var cmd = new SqlCommand(@"
IF EXISTS (SELECT 1 FROM dbo.PosMeta WHERE Name = @n) UPDATE dbo.PosMeta SET Value = @v WHERE Name = @n;
ELSE INSERT INTO dbo.PosMeta (Name, Value) VALUES (@n, @v);", con))
            {
                cmd.Parameters.Add("@n", SqlDbType.VarChar, 50).Value = name;
                cmd.Parameters.Add("@v", SqlDbType.NVarChar, 400).Value = (object)value ?? DBNull.Value;
                cmd.ExecuteNonQuery();
            }
        }

        // ── sales ──────────────────────────────────────────────────────
        // Saves the sale with the terminal's next OR number and an outbox row, all or nothing; returns the OR no.
        // The local stock copy goes down too, so the next warning reflects this sale.
        public string SaveSale(PosSale s)
        {
            // last local sanity check (UI review): the payments pay the sale exactly, change only out of cash, a charge has its customer
            decimal paid = s.Payments.Sum(p => p.Amount), cash = s.Payments.Where(p => p.PaymentType == "CASH").Sum(p => p.Amount);
            if (paid - s.ChangeAmount != s.NetAmount || paid != s.AmountTendered || s.ChangeAmount < 0 || s.ChangeAmount > cash)
                throw new InvalidOperationException("The payments don't add up to the sale (paid " + paid.ToString("N2") + ", change " + s.ChangeAmount.ToString("N2") + ", due " + s.NetAmount.ToString("N2") + ").");
            if (s.Payments.Any(p => p.PaymentType == "CHARGE") && string.IsNullOrWhiteSpace(s.CustomerKey))
                throw new InvalidOperationException("A charge needs the customer.");
            using (var con = Open())
            using (var tx = con.BeginTransaction(IsolationLevel.Serializable))
            {
                string prefix; long seq;
                using (var cmd = new SqlCommand("SELECT ORPrefix, NextORSeq FROM dbo.PosTerminal WITH (UPDLOCK, HOLDLOCK) WHERE Id = 1", con, tx))
                using (var r = cmd.ExecuteReader())
                {
                    if (!r.Read()) throw new InvalidOperationException("This terminal is not registered yet; connect it to the server once first.");
                    prefix = r.GetString(0); seq = r.GetInt64(1);
                }
                // phase 3: the sale's shift must be this terminal's open shift (the Z-reading closes it for good), and the cashier's own
                using (var cmd = new SqlCommand("SELECT Status, CashierUserID FROM dbo.PosShift WITH (UPDLOCK, HOLDLOCK) WHERE ShiftGUID = @s", con, tx))
                {
                    cmd.Parameters.Add("@s", SqlDbType.UniqueIdentifier).Value = s.ShiftGuid;
                    using (var r = cmd.ExecuteReader())
                    {
                        if (!r.Read() || r.GetString(0) != "OPEN") throw new InvalidOperationException("The shift is not open: open a shift (cash beginning) first.");
                        if (!string.Equals(r.GetString(1), s.CashierUserID, StringComparison.OrdinalIgnoreCase))
                            throw new InvalidOperationException("The open shift is another cashier's: close it (Z-reading) first.");
                    }
                }
                // last local check: a discount whose type needs approval (or isn't in this terminal's list) must carry the approver
                if (string.IsNullOrWhiteSpace(s.DiscountApprovedBy) && s.Discounts.Count > 0)
                    using (var cmd = new SqlCommand("SELECT COUNT(*) FROM dbo.PosDiscountType WHERE DiscountCode = @c AND RequiresApproval = 0", con, tx))
                    {
                        var p = cmd.Parameters.Add("@c", SqlDbType.VarChar, 10);
                        foreach (var d in s.Discounts)
                        {
                            p.Value = d.DiscountCode;
                            if ((int)cmd.ExecuteScalar() == 0) throw new InvalidOperationException("The discount " + d.DiscountCode + " needs a supervisor's approval.");
                        }
                    }
                s.ORNo = prefix + "-" + seq.ToString("D10");
                s.Status = "PAID";

                using (var cmd = new SqlCommand("UPDATE dbo.PosTerminal SET NextORSeq = NextORSeq + 1 WHERE Id = 1", con, tx)) cmd.ExecuteNonQuery();

                using (var cmd = new SqlCommand(@"
INSERT INTO dbo.PosSale (SaleGUID, ORNo, SaleDateTime, CashierUserID, CashierName, CustomerKey, GrossAmount, DiscountAmount, NetAmount,
    VatableSales, VatAmount, VatExemptSales, ZeroRatedSales, AmountTendered, ChangeAmount, WasOffline, SavedAt,
    CancelledLineCount, CancelledLineAmount, Status, ShiftGUID, DiscountApprovedBy, CreditApprovedBy, CustomerName)
VALUES (@g, @or, @dt, @cu, @cn, @ck, @gross, @disc, @net, @vatable, @vat, @exempt, @zero, @tend, @chg, @off, @saved, @clc, @cla, 'PAID', @sh, @dab, @cab, @cnm);", con, tx))
                {
                    cmd.Parameters.Add("@sh", SqlDbType.UniqueIdentifier).Value = s.ShiftGuid;
                    cmd.Parameters.Add("@dab", SqlDbType.VarChar, 60).Value = (object)s.DiscountApprovedBy ?? DBNull.Value;
                    cmd.Parameters.Add("@cab", SqlDbType.VarChar, 60).Value = (object)s.CreditApprovedBy ?? DBNull.Value;
                    cmd.Parameters.Add("@cnm", SqlDbType.VarChar, 150).Value = (object)s.CustomerName ?? DBNull.Value;
                    cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = s.SaleGuid;
                    cmd.Parameters.Add("@or", SqlDbType.VarChar, 30).Value = s.ORNo;
                    cmd.Parameters.Add("@dt", SqlDbType.DateTime).Value = s.SaleDateTime;
                    cmd.Parameters.Add("@cu", SqlDbType.VarChar, 50).Value = s.CashierUserID ?? "";
                    cmd.Parameters.Add("@cn", SqlDbType.VarChar, 100).Value = (object)s.CashierName ?? DBNull.Value;
                    cmd.Parameters.Add("@ck", SqlDbType.VarChar, 20).Value = (object)s.CustomerKey ?? DBNull.Value;
                    AddMoney(cmd, "@gross", s.GrossAmount); AddMoney(cmd, "@disc", s.DiscountAmount); AddMoney(cmd, "@net", s.NetAmount);
                    AddMoney(cmd, "@vatable", s.VatableSales); AddMoney(cmd, "@vat", s.VatAmount); AddMoney(cmd, "@exempt", s.VatExemptSales);
                    AddMoney(cmd, "@zero", s.ZeroRatedSales); AddMoney(cmd, "@tend", s.AmountTendered); AddMoney(cmd, "@chg", s.ChangeAmount);
                    cmd.Parameters.Add("@off", SqlDbType.Bit).Value = s.WasOffline;
                    cmd.Parameters.Add("@saved", SqlDbType.DateTime).Value = s.SavedAt;
                    cmd.Parameters.Add("@clc", SqlDbType.Int).Value = s.CancelledLineCount;
                    AddMoney(cmd, "@cla", s.CancelledLineAmount);
                    cmd.ExecuteNonQuery();
                }

                foreach (var l in s.Lines)
                    using (var cmd = new SqlCommand(@"
INSERT INTO dbo.PosSaleLine (SaleGUID, [LineNo], ProductCode, Barcode, Description, Qty, PriceLevel, UnitPrice, LineDiscount, LineTotal, IsVat, VatAmount,
    IsVatItem, DiscNo, DiscountCode, DiscountAmount, VatExemptAmount)
VALUES (@g, @n, @p, @bc, @d, @q, @lvl, @up, @ld, @lt, @iv, @va, @ivi, @dn, @dc, @da, @vea);
UPDATE dbo.PosStock SET Available = CASE WHEN Available > @q THEN Available - @q ELSE 0 END WHERE ProductCode = @p;", con, tx))
                    {
                        cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = s.SaleGuid;
                        AddLineParams(cmd, l);
                        cmd.ExecuteNonQuery();
                    }

                foreach (var d in s.Discounts)
                    using (var cmd = new SqlCommand(@"
INSERT INTO dbo.PosSaleDiscount (SaleGUID, DiscNo, DiscountCode, Name, [Percent], Amount, VatExemptAmount, CustomerName, IDNo, TIN, Remarks)
VALUES (@g, @dn, @dc, @nm, @pct, @amt, @vea, @cn, @id, @tin, @rm);", con, tx))
                    {
                        cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = s.SaleGuid;
                        AddDiscountParams(cmd, d);
                        AddMoney(cmd, "@amt", d.Amount);
                        AddMoney(cmd, "@vea", d.VatExemptAmount);
                        cmd.ExecuteNonQuery();
                    }

                foreach (var p in s.Payments)
                    using (var cmd = new SqlCommand("INSERT INTO dbo.PosPayment (SaleGUID, PayNo, PaymentType, Amount, Reference) VALUES (@g, @n, @t, @a, @r);", con, tx))
                    {
                        cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = s.SaleGuid;
                        cmd.Parameters.Add("@n", SqlDbType.Int).Value = p.PayNo;
                        cmd.Parameters.Add("@t", SqlDbType.VarChar, 20).Value = p.PaymentType;
                        AddMoney(cmd, "@a", p.Amount);
                        cmd.Parameters.Add("@r", SqlDbType.VarChar, 100).Value = (object)p.Reference ?? DBNull.Value;
                        cmd.ExecuteNonQuery();
                    }

                using (var cmd = new SqlCommand("INSERT INTO dbo.PosOutbox (SaleGUID, EventType) VALUES (@g, 'SALE');", con, tx))
                {
                    cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = s.SaleGuid;
                    cmd.ExecuteNonQuery();
                }

                tx.Commit();
                return s.ORNo;
            }
        }

        private static void AddLineParams(SqlCommand cmd, PosCartLine l)
        {
            cmd.Parameters.Add("@n", SqlDbType.Int).Value = l.LineNo;
            cmd.Parameters.Add("@p", SqlDbType.VarChar, 50).Value = l.ProductCode;
            cmd.Parameters.Add("@bc", SqlDbType.VarChar, 150).Value = (object)l.Barcode ?? DBNull.Value;
            cmd.Parameters.Add("@d", SqlDbType.VarChar, 300).Value = (object)l.Description ?? DBNull.Value;
            var q = cmd.Parameters.Add("@q", SqlDbType.Decimal); q.Precision = 18; q.Scale = 3; q.Value = l.Qty;
            cmd.Parameters.Add("@lvl", SqlDbType.VarChar, 10).Value = l.PriceLevel;
            AddMoney(cmd, "@up", l.UnitPrice); AddMoney(cmd, "@ld", l.LineDiscount); AddMoney(cmd, "@lt", l.LineTotal);
            cmd.Parameters.Add("@iv", SqlDbType.Bit).Value = l.IsVat;
            AddMoney(cmd, "@va", l.VatAmount);
            cmd.Parameters.Add("@ivi", SqlDbType.Bit).Value = l.IsVatItem;
            cmd.Parameters.Add("@dn", SqlDbType.Int).Value = (object)l.DiscNo ?? DBNull.Value;
            cmd.Parameters.Add("@dc", SqlDbType.VarChar, 10).Value = (object)l.DiscountCode ?? DBNull.Value;
            AddMoney(cmd, "@da", l.DiscountAmount); AddMoney(cmd, "@vea", l.VatExemptAmount);
        }

        private static void AddDiscountParams(SqlCommand cmd, PosSaleDiscount d)
        {
            cmd.Parameters.Add("@dn", SqlDbType.Int).Value = d.DiscNo;
            cmd.Parameters.Add("@dc", SqlDbType.VarChar, 10).Value = d.DiscountCode;
            cmd.Parameters.Add("@nm", SqlDbType.VarChar, 100).Value = (object)d.Name ?? DBNull.Value;
            var pct = cmd.Parameters.Add("@pct", SqlDbType.Decimal); pct.Precision = 9; pct.Scale = 4; pct.Value = d.Percent;
            cmd.Parameters.Add("@cn", SqlDbType.VarChar, 150).Value = (object)d.CustomerName ?? DBNull.Value;
            cmd.Parameters.Add("@id", SqlDbType.VarChar, 50).Value = (object)d.IDNo ?? DBNull.Value;
            cmd.Parameters.Add("@tin", SqlDbType.VarChar, 30).Value = (object)d.TIN ?? DBNull.Value;
            cmd.Parameters.Add("@rm", SqlDbType.VarChar, 300).Value = (object)d.Remarks ?? DBNull.Value;
        }

        private static void AddMoney(SqlCommand cmd, string name, decimal value)
        {
            var p = cmd.Parameters.Add(name, SqlDbType.Decimal);
            p.Precision = 18; p.Scale = 2; p.Value = value;
        }

        // Voids a paid sale on this terminal: marks it VOIDED and queues a VOID behind its SALE (one transaction).
        // Phase 3: only a sale of the shift still open (after the Z-reading its GL is booked), with a supervisor's approval.
        public void VoidSale(Guid saleGuid, string reason, string user, string approvedBy)
        {
            if (string.IsNullOrWhiteSpace(approvedBy)) throw new InvalidOperationException("A void needs a supervisor's approval.");
            using (var con = Open())
            using (var tx = con.BeginTransaction(IsolationLevel.Serializable))
            {
                string status, shiftStatus, sync;
                using (var cmd = new SqlCommand(@"SELECT s.Status, sh.Status, s.SyncStatus FROM dbo.PosSale s WITH (UPDLOCK, HOLDLOCK)
    LEFT JOIN dbo.PosShift sh WITH (UPDLOCK, HOLDLOCK) ON sh.ShiftGUID = s.ShiftGUID WHERE s.SaleGUID = @g", con, tx))
                {
                    cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = saleGuid;
                    using (var r = cmd.ExecuteReader())
                    {
                        if (!r.Read()) throw new InvalidOperationException("Sale not found on this terminal.");
                        status = r.GetString(0); shiftStatus = r.IsDBNull(1) ? null : r.GetString(1); sync = r.GetString(2);
                    }
                }
                if (status == "VOIDED") throw new InvalidOperationException("This sale is already voided.");
                // the server would refuse a void of a sale it never got: fix the sale first (F12)
                if (sync == "FAILED") throw new InvalidOperationException("This sale was refused by the server (needs attention); it can't be voided until it is posted.");
                if (shiftStatus != "OPEN") throw new InvalidOperationException("The sale's shift is already closed (Z-read); it can't be voided any more.");
                // phase 4 (UI review B1): a sale with a return can't be voided as well: money and stock would go back twice
                using (var cmd = new SqlCommand("SELECT COUNT(*) FROM dbo.PosReturn WITH (UPDLOCK, HOLDLOCK) WHERE OrigSaleGUID = @g", con, tx))
                {
                    cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = saleGuid;
                    if ((int)cmd.ExecuteScalar() > 0) throw new InvalidOperationException("Part of this sale was already returned: it can't be voided (return the rest instead).");
                }

                using (var cmd = new SqlCommand(@"
UPDATE dbo.PosSale SET Status = 'VOIDED', VoidedAt = GETDATE(), VoidReason = @r, VoidedBy = @u, VoidApprovedBy = @a WHERE SaleGUID = @g;
INSERT INTO dbo.PosOutbox (SaleGUID, EventType) VALUES (@g, 'VOID');
UPDATE st SET Available = st.Available + l.Qty
FROM dbo.PosStock st INNER JOIN (SELECT ProductCode, SUM(Qty) AS Qty FROM dbo.PosSaleLine WHERE SaleGUID = @g GROUP BY ProductCode) l ON l.ProductCode = st.ProductCode;", con, tx))
                {
                    cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = saleGuid;
                    cmd.Parameters.Add("@r", SqlDbType.NVarChar, 300).Value = reason;
                    cmd.Parameters.Add("@u", SqlDbType.VarChar, 60).Value = user ?? "";
                    cmd.Parameters.Add("@a", SqlDbType.VarChar, 60).Value = approvedBy;
                    cmd.ExecuteNonQuery();
                }
                tx.Commit();
            }
        }

        // ── phase 3: shifts ────────────────────────────────────────────
        // The terminal's open shift, or null.
        public PosShift GetOpenShift()
        {
            using (var con = Open())
            using (var cmd = new SqlCommand("SELECT TOP 1 ShiftGUID FROM dbo.PosShift WHERE Status = 'OPEN' ORDER BY ZNo DESC", con))
            {
                var o = cmd.ExecuteScalar();
                return o == null || o == DBNull.Value ? null : LoadShift((Guid)o);
            }
        }

        public PosShift LoadShift(Guid shiftGuid)
        {
            using (var con = Open())
            using (var cmd = new SqlCommand(@"SELECT ZNo, CashierUserID, CashierName, OpenedAt, BeginningCash, Status, ClosedAt, CountedCash, ClosedBy, CloseApprovedBy,
    AccumulatedBefore, AccumulatedAfter
    FROM dbo.PosShift WHERE ShiftGUID = @s", con))
            {
                cmd.Parameters.Add("@s", SqlDbType.UniqueIdentifier).Value = shiftGuid;
                using (var r = cmd.ExecuteReader())
                {
                    if (!r.Read()) return null;
                    return new PosShift
                    {
                        ShiftGuid = shiftGuid, ZNo = r.GetInt32(0), CashierUserID = r.GetString(1), CashierName = r.IsDBNull(2) ? null : r.GetString(2),
                        OpenedAt = r.GetDateTime(3), BeginningCash = r.GetDecimal(4), Status = r.GetString(5),
                        ClosedAt = r.IsDBNull(6) ? (DateTime?)null : r.GetDateTime(6), CountedCash = r.IsDBNull(7) ? (decimal?)null : r.GetDecimal(7),
                        ClosedBy = r.IsDBNull(8) ? null : r.GetString(8), CloseApprovedBy = r.IsDBNull(9) ? null : r.GetString(9),
                        AccumulatedBefore = r.IsDBNull(10) ? (decimal?)null : r.GetDecimal(10), AccumulatedAfter = r.IsDBNull(11) ? (decimal?)null : r.GetDecimal(11)
                    };
                }
            }
        }

        // The last closed shifts, newest first (reprint a Z-reading).
        public List<PosShift> RecentClosedShifts(int max)
        {
            var ids = new List<Guid>();
            using (var con = Open())
            using (var cmd = new SqlCommand("SELECT TOP (@m) ShiftGUID FROM dbo.PosShift WHERE Status = 'CLOSED' ORDER BY ZNo DESC", con))
            {
                cmd.Parameters.Add("@m", SqlDbType.Int).Value = max;
                using (var r = cmd.ExecuteReader()) while (r.Read()) ids.Add(r.GetGuid(0));
            }
            return ids.ConvertAll(LoadShift);
        }

        // Opens a shift with the next Z no. and queues SHIFTOPEN (works offline). One open shift at a time.
        public PosShift OpenShift(string cashier, string cashierName, decimal beginningCash)
        {
            if (beginningCash < 0) throw new InvalidOperationException("The beginning cash can't be negative.");
            using (var con = Open())
            using (var tx = con.BeginTransaction(IsolationLevel.Serializable))
            {
                int z;
                using (var cmd = new SqlCommand("SELECT NextZNo FROM dbo.PosTerminal WITH (UPDLOCK, HOLDLOCK) WHERE Id = 1", con, tx))
                {
                    var o = cmd.ExecuteScalar();
                    if (o == null) throw new InvalidOperationException("This terminal is not registered yet; connect it to the server once first.");
                    z = (int)o;
                }
                using (var cmd = new SqlCommand("SELECT COUNT(*) FROM dbo.PosShift WITH (UPDLOCK, HOLDLOCK) WHERE Status = 'OPEN'", con, tx))
                    if ((int)cmd.ExecuteScalar() > 0) throw new InvalidOperationException("A shift is already open on this terminal.");

                var sh = new PosShift { ShiftGuid = Guid.NewGuid(), ZNo = z, CashierUserID = cashier ?? "", CashierName = cashierName,
                                        OpenedAt = DateTime.Now, BeginningCash = Math.Round(beginningCash, 2, MidpointRounding.AwayFromZero), Status = "OPEN" };
                using (var cmd = new SqlCommand(@"
UPDATE dbo.PosTerminal SET NextZNo = NextZNo + 1 WHERE Id = 1;
INSERT INTO dbo.PosShift (ShiftGUID, ZNo, CashierUserID, CashierName, OpenedAt, BeginningCash, Status) VALUES (@s, @z, @u, @n, @o, @b, 'OPEN');
INSERT INTO dbo.PosOutbox (SaleGUID, EventType) VALUES (@s, 'SHIFTOPEN');", con, tx))
                {
                    cmd.Parameters.Add("@s", SqlDbType.UniqueIdentifier).Value = sh.ShiftGuid;
                    cmd.Parameters.Add("@z", SqlDbType.Int).Value = z;
                    cmd.Parameters.Add("@u", SqlDbType.VarChar, 50).Value = sh.CashierUserID;
                    cmd.Parameters.Add("@n", SqlDbType.VarChar, 100).Value = (object)cashierName ?? DBNull.Value;
                    cmd.Parameters.Add("@o", SqlDbType.DateTime).Value = sh.OpenedAt;
                    AddMoney(cmd, "@b", sh.BeginningCash);
                    cmd.ExecuteNonQuery();
                }
                tx.Commit();
                return sh;
            }
        }

        // The Z-reading: closes the open shift with the cash counted and queues SHIFTCLOSE behind the shift's own events.
        public PosShiftReading CloseShift(Guid shiftGuid, decimal countedCash, string closedBy, string approvedBy)
        {
            if (countedCash < 0) throw new InvalidOperationException("The cash counted can't be negative.");
            using (var con = Open())
            using (var tx = con.BeginTransaction(IsolationLevel.Serializable))
            {
                string status, cashier;
                using (var cmd = new SqlCommand("SELECT Status, CashierUserID FROM dbo.PosShift WITH (UPDLOCK, HOLDLOCK) WHERE ShiftGUID = @s", con, tx))
                {
                    cmd.Parameters.Add("@s", SqlDbType.UniqueIdentifier).Value = shiftGuid;
                    using (var r = cmd.ExecuteReader())
                    {
                        if (!r.Read()) throw new InvalidOperationException("Shift not found on this terminal.");
                        status = r.GetString(0); cashier = r.GetString(1);
                    }
                }
                if (status != "OPEN") throw new InvalidOperationException("This shift is already closed.");
                if (!string.Equals(cashier, closedBy, StringComparison.OrdinalIgnoreCase) && string.IsNullOrWhiteSpace(approvedBy))
                    throw new InvalidOperationException("Closing another cashier's shift needs a supervisor's approval.");
                using (var cmd = new SqlCommand(@"
DECLARE @net DECIMAL(18,2) = ISNULL((SELECT SUM(NetAmount) FROM dbo.PosSale WHERE ShiftGUID = @s AND Status <> 'VOIDED'), 0);
DECLARE @acc DECIMAL(18,2) = (SELECT AccumulatedTotal FROM dbo.PosTerminal WITH (UPDLOCK, HOLDLOCK) WHERE Id = 1);   -- phase 5 (BIR) grand total
UPDATE dbo.PosShift SET Status = 'CLOSED', ClosedAt = GETDATE(), CountedCash = @c, ClosedBy = @u, CloseApprovedBy = @a,
    AccumulatedBefore = @acc, AccumulatedAfter = @acc + @net WHERE ShiftGUID = @s;
UPDATE dbo.PosTerminal SET AccumulatedTotal = @acc + @net WHERE Id = 1;
INSERT INTO dbo.PosOutbox (SaleGUID, EventType) VALUES (@s, 'SHIFTCLOSE');", con, tx))
                {
                    cmd.Parameters.Add("@s", SqlDbType.UniqueIdentifier).Value = shiftGuid;
                    AddMoney(cmd, "@c", Math.Round(countedCash, 2, MidpointRounding.AwayFromZero));
                    cmd.Parameters.Add("@u", SqlDbType.VarChar, 60).Value = closedBy ?? "";
                    cmd.Parameters.Add("@a", SqlDbType.VarChar, 60).Value = (object)NullIfBlank(approvedBy) ?? DBNull.Value;
                    cmd.ExecuteNonQuery();
                }
                tx.Commit();
            }
            return ComputeReading(shiftGuid);
        }

        // A whole sale cleared before payment (CLEARED) or a no-sale drawer opening (DRAWER), for the Z-reading.
        // removedLines / removedAmount: lines taken off (Del) a sale that was then cleared, so the Z-reading still counts them.
        public void AddShiftEvent(Guid shiftGuid, string eventType, int lines, decimal amount, string user, string approvedBy, string reason,
                                  int removedLines = 0, decimal removedAmount = 0m)
        {
            if (eventType != "CLEARED" && eventType != "DRAWER") throw new ArgumentException("eventType");
            using (var con = Open())
            using (var cmd = new SqlCommand(@"INSERT INTO dbo.PosShiftEvent (ShiftGUID, EventType, Lines, Amount, UserID, ApprovedBy, Reason, RemovedLines, RemovedAmount)
    VALUES (@s, @t, @l, @a, @u, @ap, @r, @rl, @ra);", con))
            {
                cmd.Parameters.Add("@s", SqlDbType.UniqueIdentifier).Value = shiftGuid;
                cmd.Parameters.Add("@t", SqlDbType.VarChar, 10).Value = eventType;
                cmd.Parameters.Add("@l", SqlDbType.Int).Value = lines;
                AddMoney(cmd, "@a", amount);
                cmd.Parameters.Add("@u", SqlDbType.VarChar, 50).Value = (object)user ?? DBNull.Value;
                cmd.Parameters.Add("@ap", SqlDbType.VarChar, 60).Value = (object)NullIfBlank(approvedBy) ?? DBNull.Value;
                cmd.Parameters.Add("@r", SqlDbType.NVarChar, 300).Value = (object)NullIfBlank(reason) ?? DBNull.Value;
                cmd.Parameters.Add("@rl", SqlDbType.Int).Value = removedLines;
                AddMoney(cmd, "@ra", removedAmount);
                cmd.ExecuteNonQuery();
            }
        }

        // The X / Z reading of a shift from this terminal's own rows (the server re-derives the same figures at close).
        public PosShiftReading ComputeReading(Guid shiftGuid)
        {
            var rd = new PosShiftReading { Shift = LoadShift(shiftGuid) };
            if (rd.Shift == null) return null;
            using (var con = Open())
            {
                using (var cmd = new SqlCommand(@"
SELECT COUNT(*),
       ISNULL(SUM(CASE WHEN Status = 'VOIDED' THEN 1 ELSE 0 END), 0),
       ISNULL(SUM(CASE WHEN Status = 'VOIDED' THEN NetAmount ELSE 0 END), 0),
       ISNULL(SUM(CASE WHEN Status <> 'VOIDED' THEN GrossAmount ELSE 0 END), 0),
       ISNULL(SUM(CASE WHEN Status <> 'VOIDED' THEN NetAmount ELSE 0 END), 0),
       ISNULL(SUM(CASE WHEN Status <> 'VOIDED' THEN VatableSales ELSE 0 END), 0),
       ISNULL(SUM(CASE WHEN Status <> 'VOIDED' THEN VatAmount ELSE 0 END), 0),
       ISNULL(SUM(CASE WHEN Status <> 'VOIDED' THEN VatExemptSales ELSE 0 END), 0),
       ISNULL(SUM(CASE WHEN Status <> 'VOIDED' THEN ZeroRatedSales ELSE 0 END), 0),
       ISNULL(SUM(CASE WHEN Status <> 'VOIDED' THEN -ChangeAmount ELSE 0 END), 0),   -- change given; the cash payments are added below
       ISNULL(SUM(CancelledLineCount), 0), ISNULL(SUM(CancelledLineAmount), 0), ISNULL(SUM(ReprintCount), 0),
       MIN(ORNo), MAX(ORNo)
FROM dbo.PosSale WHERE ShiftGUID = @s;
SELECT ISNULL(SUM(l.DiscountAmount), 0), ISNULL(SUM(l.VatExemptAmount), 0)
FROM dbo.PosSaleLine l INNER JOIN dbo.PosSale s ON s.SaleGUID = l.SaleGUID WHERE s.ShiftGUID = @s AND s.Status <> 'VOIDED';
SELECT d.DiscountCode, COUNT(DISTINCT d.SaleGUID), SUM(d.Amount + d.VatExemptAmount)
FROM dbo.PosSaleDiscount d INNER JOIN dbo.PosSale s ON s.SaleGUID = d.SaleGUID WHERE s.ShiftGUID = @s AND s.Status <> 'VOIDED'
GROUP BY d.DiscountCode ORDER BY d.DiscountCode;
SELECT ISNULL(SUM(CASE WHEN EventType = 'CLEARED' THEN 1 ELSE 0 END), 0), ISNULL(SUM(CASE WHEN EventType = 'CLEARED' THEN Amount ELSE 0 END), 0),
       ISNULL(SUM(CASE WHEN EventType = 'DRAWER' THEN 1 ELSE 0 END), 0), ISNULL(SUM(RemovedLines), 0), ISNULL(SUM(RemovedAmount), 0)
FROM dbo.PosShiftEvent WHERE ShiftGUID = @s;
SELECT ISNULL(SUM(CASE WHEN p.PaymentType = 'CARD' THEN p.Amount END), 0), ISNULL(SUM(CASE WHEN p.PaymentType = 'CHARGE' THEN p.Amount END), 0),
       ISNULL(SUM(CASE WHEN p.PaymentType = 'CASH' THEN p.Amount END), 0)
FROM dbo.PosPayment p INNER JOIN dbo.PosSale s ON s.SaleGUID = p.SaleGUID WHERE s.ShiftGUID = @s AND s.Status <> 'VOIDED';
SELECT COUNT(DISTINCT r.ReturnGUID), ISNULL(SUM(l.GrossAmount), 0), ISNULL(SUM(l.DiscountAmount + l.VatExemptAmount), 0), ISNULL(SUM(l.NetAmount), 0)
FROM dbo.PosReturn r INNER JOIN dbo.PosReturnLine l ON l.ReturnGUID = r.ReturnGUID WHERE r.ShiftGUID = @s;
SELECT ISNULL(SUM(CashRefund), 0), ISNULL(SUM(CardRefund), 0), ISNULL(SUM(ChargeRefund), 0) FROM dbo.PosReturn WHERE ShiftGUID = @s;", con))
                {
                    cmd.Parameters.Add("@s", SqlDbType.UniqueIdentifier).Value = shiftGuid;
                    using (var r = cmd.ExecuteReader())
                    {
                        r.Read();
                        rd.SaleCount = r.GetInt32(0); rd.VoidCount = r.GetInt32(1); rd.VoidAmount = r.GetDecimal(2);
                        rd.GrossAmount = r.GetDecimal(3); rd.NetAmount = r.GetDecimal(4); rd.VatableSales = r.GetDecimal(5); rd.VatAmount = r.GetDecimal(6);
                        rd.VatExemptSales = r.GetDecimal(7); rd.ZeroRatedSales = r.GetDecimal(8); rd.CashSales = r.GetDecimal(9);
                        rd.CancelledLineCount = r.GetInt32(10); rd.CancelledLineAmount = r.GetDecimal(11); rd.ReprintCount = r.GetInt32(12);
                        rd.FirstORNo = r.IsDBNull(13) ? null : r.GetString(13); rd.LastORNo = r.IsDBNull(14) ? null : r.GetString(14);
                        r.NextResult(); r.Read();
                        rd.DiscountAmount = r.GetDecimal(0); rd.VatExemptAmount = r.GetDecimal(1);
                        r.NextResult();
                        while (r.Read()) rd.DiscountsByType.Add(Tuple.Create(r.GetString(0), r.GetInt32(1), r.GetDecimal(2)));
                        r.NextResult(); r.Read();
                        rd.ClearedSaleCount = r.GetInt32(0); rd.ClearedSaleAmount = r.GetDecimal(1); rd.DrawerOpenCount = r.GetInt32(2);
                        rd.ClearedLineCount = r.GetInt32(3); rd.ClearedLineAmount = r.GetDecimal(4);
                        r.NextResult(); r.Read();
                        rd.CardSales = r.GetDecimal(0); rd.ChargeSales = r.GetDecimal(1); rd.CashSales += r.GetDecimal(2);   // cash received less change
                        r.NextResult(); r.Read();
                        rd.ReturnCount = r.GetInt32(0); rd.ReturnGross = r.GetDecimal(1); rd.ReturnDiscount = r.GetDecimal(2); rd.ReturnNet = r.GetDecimal(3);
                        r.NextResult(); r.Read();
                        rd.CashRefunds = r.GetDecimal(0); rd.CardRefunds = r.GetDecimal(1); rd.ChargeRefunds = r.GetDecimal(2);
                    }
                }
            }
            return rd;
        }

        // the server's answer to a SHIFTOPEN / SHIFTCLOSE
        public void MarkShiftSent(int outboxId, Guid shiftGuid, string message)
        {
            using (var con = Open())
            using (var cmd = new SqlCommand(@"
UPDATE dbo.PosOutbox SET Status = 'SENT', SentAt = GETDATE(), LastAttemptAt = GETDATE(), Attempts = Attempts + 1, LastError = NULL WHERE OutboxID = @o;
UPDATE dbo.PosShift SET SyncMessage = @m WHERE ShiftGUID = @g;", con))
            {
                cmd.Parameters.Add("@o", SqlDbType.Int).Value = outboxId;
                cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = shiftGuid;
                cmd.Parameters.Add("@m", SqlDbType.NVarChar, 1000).Value = Trim(message, 1000);
                cmd.ExecuteNonQuery();
            }
        }

        public void SetShiftMessage(Guid shiftGuid, string message)
        {
            using (var con = Open())
            using (var cmd = new SqlCommand("UPDATE dbo.PosShift SET SyncMessage = @m WHERE ShiftGUID = @g;", con))
            {
                cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = shiftGuid;
                cmd.Parameters.Add("@m", SqlDbType.NVarChar, 1000).Value = Trim(message, 1000);
                cmd.ExecuteNonQuery();
            }
        }

        private static string NullIfBlank(string s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

        // The outbox entries still to send, oldest first: (OutboxID, SaleGUID, EventType SALE / VOID).
        public List<Tuple<int, Guid, string>> GetPendingOutbox(int max)
        {
            var list = new List<Tuple<int, Guid, string>>();
            using (var con = Open())
            using (var cmd = new SqlCommand("SELECT TOP (@max) OutboxID, SaleGUID, EventType FROM dbo.PosOutbox WHERE Status = 'PENDING' ORDER BY OutboxID", con))
            {
                cmd.Parameters.Add("@max", SqlDbType.Int).Value = max;
                using (var r = cmd.ExecuteReader())
                    while (r.Read()) list.Add(Tuple.Create(r.GetInt32(0), r.GetGuid(1), r.GetString(2)));
            }
            return list;
        }

        public PosSale LoadSale(Guid saleGuid)
        {
            PosSale s = null;
            using (var con = Open())
            {
                using (var cmd = new SqlCommand(@"SELECT ORNo, SaleDateTime, CashierUserID, CashierName, CustomerKey, GrossAmount, DiscountAmount, NetAmount,
    VatableSales, VatAmount, VatExemptSales, ZeroRatedSales, AmountTendered, ChangeAmount, WasOffline, SavedAt,
    CancelledLineCount, CancelledLineAmount, Status, VoidedAt, VoidReason, VoidedBy, ShiftGUID, DiscountApprovedBy, VoidApprovedBy,
    CreditApprovedBy, CustomerName FROM dbo.PosSale WHERE SaleGUID = @g", con))
                {
                    cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = saleGuid;
                    using (var r = cmd.ExecuteReader())
                        if (r.Read())
                            s = new PosSale
                            {
                                SaleGuid = saleGuid, ORNo = r.GetString(0), SaleDateTime = r.GetDateTime(1), CashierUserID = r.GetString(2),
                                CashierName = r.IsDBNull(3) ? null : r.GetString(3), CustomerKey = r.IsDBNull(4) ? null : r.GetString(4),
                                GrossAmount = r.GetDecimal(5), DiscountAmount = r.GetDecimal(6), NetAmount = r.GetDecimal(7), VatableSales = r.GetDecimal(8),
                                VatAmount = r.GetDecimal(9), VatExemptSales = r.GetDecimal(10), ZeroRatedSales = r.GetDecimal(11),
                                AmountTendered = r.GetDecimal(12), ChangeAmount = r.GetDecimal(13), WasOffline = r.GetBoolean(14), SavedAt = r.GetDateTime(15),
                                CancelledLineCount = r.GetInt32(16), CancelledLineAmount = r.GetDecimal(17), Status = r.GetString(18),
                                VoidedAt = r.IsDBNull(19) ? (DateTime?)null : r.GetDateTime(19), VoidReason = r.IsDBNull(20) ? null : r.GetString(20),
                                VoidedBy = r.IsDBNull(21) ? null : r.GetString(21), ShiftGuid = r.IsDBNull(22) ? Guid.Empty : r.GetGuid(22),
                                DiscountApprovedBy = r.IsDBNull(23) ? null : r.GetString(23), VoidApprovedBy = r.IsDBNull(24) ? null : r.GetString(24),
                                CreditApprovedBy = r.IsDBNull(25) ? null : r.GetString(25), CustomerName = r.IsDBNull(26) ? null : r.GetString(26)
                            };
                }
                if (s == null) return null;
                using (var cmd = new SqlCommand(@"SELECT [LineNo], ProductCode, Barcode, Description, Qty, PriceLevel, UnitPrice, LineDiscount, LineTotal, IsVat, VatAmount,
    IsVatItem, DiscNo, DiscountCode, DiscountAmount, VatExemptAmount FROM dbo.PosSaleLine WHERE SaleGUID = @g ORDER BY [LineNo]", con))
                {
                    cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = saleGuid;
                    using (var r = cmd.ExecuteReader())
                        while (r.Read())
                            s.Lines.Add(new PosCartLine
                            {
                                LineNo = r.GetInt32(0), ProductCode = r.GetString(1), Barcode = r.IsDBNull(2) ? null : r.GetString(2),
                                Description = r.IsDBNull(3) ? null : r.GetString(3), Qty = r.GetDecimal(4), PriceLevel = r.GetString(5),
                                UnitPrice = r.GetDecimal(6), LineDiscount = r.GetDecimal(7), LineTotal = r.GetDecimal(8), IsVat = r.GetBoolean(9), VatAmount = r.GetDecimal(10),
                                IsVatItem = r.GetBoolean(11), DiscNo = r.IsDBNull(12) ? (int?)null : r.GetInt32(12), DiscountCode = r.IsDBNull(13) ? null : r.GetString(13),
                                DiscountAmount = r.GetDecimal(14), VatExemptAmount = r.GetDecimal(15)
                            });
                }
                using (var cmd = new SqlCommand(@"SELECT DiscNo, DiscountCode, Name, [Percent], Amount, VatExemptAmount, CustomerName, IDNo, TIN, Remarks
    FROM dbo.PosSaleDiscount WHERE SaleGUID = @g ORDER BY DiscNo", con))
                {
                    cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = saleGuid;
                    using (var r = cmd.ExecuteReader())
                        while (r.Read())
                            s.Discounts.Add(new PosSaleDiscount
                            {
                                DiscNo = r.GetInt32(0), DiscountCode = r.GetString(1), Name = r.IsDBNull(2) ? null : r.GetString(2), Percent = r.GetDecimal(3),
                                Amount = r.GetDecimal(4), VatExemptAmount = r.GetDecimal(5), CustomerName = r.IsDBNull(6) ? null : r.GetString(6),
                                IDNo = r.IsDBNull(7) ? null : r.GetString(7), TIN = r.IsDBNull(8) ? null : r.GetString(8), Remarks = r.IsDBNull(9) ? null : r.GetString(9)
                            });
                }
                using (var cmd = new SqlCommand("SELECT PayNo, PaymentType, Amount, Reference FROM dbo.PosPayment WHERE SaleGUID = @g ORDER BY PayNo", con))
                {
                    cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = saleGuid;
                    using (var r = cmd.ExecuteReader())
                        while (r.Read())
                            s.Payments.Add(new PosPayment { PayNo = r.GetInt32(0), PaymentType = r.GetString(1), Amount = r.GetDecimal(2), Reference = r.IsDBNull(3) ? null : r.GetString(3) });
                }
            }
            return s;
        }

        // The terminal's sales of one day, newest first (void / reprint pickers).
        public List<PosSaleSummary> RecentSales(DateTime day)
        {
            var list = new List<PosSaleSummary>();
            using (var con = Open())
            using (var cmd = new SqlCommand(@"SELECT SaleGUID, ORNo, SaleDateTime, NetAmount, Status, SyncStatus, CashierUserID FROM dbo.PosSale
    WHERE SaleDateTime >= @d AND SaleDateTime < DATEADD(DAY, 1, @d) ORDER BY SaleDateTime DESC, ORNo DESC", con))
            {
                cmd.Parameters.Add("@d", SqlDbType.DateTime).Value = day.Date;
                using (var r = cmd.ExecuteReader())
                    while (r.Read())
                        list.Add(new PosSaleSummary
                        {
                            SaleGuid = r.GetGuid(0), ORNo = r.GetString(1), SaleDateTime = r.GetDateTime(2), NetAmount = r.GetDecimal(3),
                            Status = r.GetString(4), SyncStatus = r.GetString(5), CashierUserID = r.GetString(6)
                        });
            }
            return list;
        }

        // phase 3: one shift's sales, newest first (the void picker)
        public List<PosSaleSummary> ShiftSales(Guid shiftGuid)
        {
            var list = new List<PosSaleSummary>();
            using (var con = Open())
            using (var cmd = new SqlCommand(@"SELECT SaleGUID, ORNo, SaleDateTime, NetAmount, Status, SyncStatus, CashierUserID FROM dbo.PosSale
    WHERE ShiftGUID = @s ORDER BY SaleDateTime DESC, ORNo DESC", con))
            {
                cmd.Parameters.Add("@s", SqlDbType.UniqueIdentifier).Value = shiftGuid;
                using (var r = cmd.ExecuteReader())
                    while (r.Read())
                        list.Add(new PosSaleSummary
                        {
                            SaleGuid = r.GetGuid(0), ORNo = r.GetString(1), SaleDateTime = r.GetDateTime(2), NetAmount = r.GetDecimal(3),
                            Status = r.GetString(4), SyncStatus = r.GetString(5), CashierUserID = r.GetString(6)
                        });
            }
            return list;
        }

        public Guid? GetLastSaleGuid()
        {
            using (var con = Open())
            using (var cmd = new SqlCommand("SELECT TOP 1 SaleGUID FROM dbo.PosSale ORDER BY SavedAt DESC, ORNo DESC", con))
            {
                var o = cmd.ExecuteScalar();
                return o == null || o == DBNull.Value ? (Guid?)null : (Guid)o;
            }
        }

        public void AddReprint(Guid saleGuid)
        {
            using (var con = Open())
            using (var cmd = new SqlCommand("UPDATE dbo.PosSale SET ReprintCount = ReprintCount + 1 WHERE SaleGUID = @g", con))
            {
                cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = saleGuid;
                cmd.ExecuteNonQuery();
            }
        }

        // ── held sales (this terminal only) ─────────────────────────────
        public int SaveHold(string name, string user, string priceLevel, IList<PosCartLine> lines, IList<PosSaleDiscount> discounts, int cancelledCount, decimal cancelledAmount)
        {
            using (var con = Open())
            using (var tx = con.BeginTransaction())
            {
                int id;
                using (var cmd = new SqlCommand(@"INSERT INTO dbo.PosHold (Name, CashierUserID, PriceLevel, CancelledLineCount, CancelledLineAmount)
    VALUES (@n, @u, @l, @cc, @ca); SELECT CAST(SCOPE_IDENTITY() AS INT);", con, tx))
                {
                    cmd.Parameters.Add("@n", SqlDbType.NVarChar, 100).Value = (object)name ?? DBNull.Value;
                    cmd.Parameters.Add("@u", SqlDbType.VarChar, 50).Value = (object)user ?? DBNull.Value;
                    cmd.Parameters.Add("@l", SqlDbType.VarChar, 10).Value = priceLevel ?? "MAIN";
                    cmd.Parameters.Add("@cc", SqlDbType.Int).Value = cancelledCount;
                    AddMoney(cmd, "@ca", cancelledAmount);
                    id = (int)cmd.ExecuteScalar();
                }
                foreach (var l in lines)
                    using (var cmd = new SqlCommand(@"INSERT INTO dbo.PosHoldLine (HoldID, [LineNo], ProductCode, Barcode, Description, Qty, PriceLevel, UnitPrice,
    IsVatItem, DiscNo, DiscountCode, DiscountAmount, VatExemptAmount) VALUES (@h, @n, @p, @bc, @d, @q, @lvl, @up, @ivi, @dn, @dc, @da, @vea);", con, tx))
                    {
                        cmd.Parameters.Add("@h", SqlDbType.Int).Value = id;
                        AddLineParams(cmd, l);
                        cmd.ExecuteNonQuery();
                    }
                foreach (var d in discounts)
                    using (var cmd = new SqlCommand(@"INSERT INTO dbo.PosHoldDiscount (HoldID, DiscNo, DiscountCode, Name, [Percent], CustomerName, IDNo, TIN, Remarks)
    VALUES (@h, @dn, @dc, @nm, @pct, @cn, @id, @tin, @rm);", con, tx))
                    {
                        cmd.Parameters.Add("@h", SqlDbType.Int).Value = id;
                        AddDiscountParams(cmd, d);
                        cmd.ExecuteNonQuery();
                    }
                tx.Commit();
                return id;
            }
        }

        public List<PosHeldSale> ListHolds()
        {
            var list = new List<PosHeldSale>();
            using (var con = Open())
            using (var cmd = new SqlCommand(@"SELECT h.HoldID, h.Name, h.CreatedAt,
    (SELECT COUNT(*) FROM dbo.PosHoldLine l WHERE l.HoldID = h.HoldID),
    (SELECT ISNULL(SUM(ROUND(l.Qty * l.UnitPrice, 2) - l.DiscountAmount - l.VatExemptAmount), 0) FROM dbo.PosHoldLine l WHERE l.HoldID = h.HoldID)
    FROM dbo.PosHold h ORDER BY h.CreatedAt", con))
            using (var r = cmd.ExecuteReader())
                while (r.Read())
                    list.Add(new PosHeldSale { HoldID = r.GetInt32(0), Name = r.IsDBNull(1) ? "" : r.GetString(1), CreatedAt = r.GetDateTime(2), Lines = r.GetInt32(3), Total = r.GetDecimal(4) });
            return list;
        }

        // Takes a held sale back (and deletes the hold): its lines, discounts, price level and cancelled-line counts.
        public bool TakeHold(int holdId, List<PosCartLine> lines, List<PosSaleDiscount> discounts, out string priceLevel, out int cancelledCount, out decimal cancelledAmount)
        {
            priceLevel = "MAIN"; cancelledCount = 0; cancelledAmount = 0m;
            using (var con = Open())
            using (var tx = con.BeginTransaction(IsolationLevel.Serializable))
            {
                using (var cmd = new SqlCommand("SELECT PriceLevel, CancelledLineCount, CancelledLineAmount FROM dbo.PosHold WITH (UPDLOCK, HOLDLOCK) WHERE HoldID = @h", con, tx))
                {
                    cmd.Parameters.Add("@h", SqlDbType.Int).Value = holdId;
                    using (var r = cmd.ExecuteReader())
                    {
                        if (!r.Read()) return false;
                        priceLevel = r.GetString(0); cancelledCount = r.GetInt32(1); cancelledAmount = r.GetDecimal(2);
                    }
                }
                using (var cmd = new SqlCommand(@"SELECT [LineNo], ProductCode, Barcode, Description, Qty, PriceLevel, UnitPrice, IsVatItem, DiscNo, DiscountCode,
    DiscountAmount, VatExemptAmount FROM dbo.PosHoldLine WHERE HoldID = @h ORDER BY [LineNo]", con, tx))
                {
                    cmd.Parameters.Add("@h", SqlDbType.Int).Value = holdId;
                    using (var r = cmd.ExecuteReader())
                        while (r.Read())
                            lines.Add(new PosCartLine
                            {
                                LineNo = r.GetInt32(0), ProductCode = r.GetString(1), Barcode = r.IsDBNull(2) ? null : r.GetString(2),
                                Description = r.IsDBNull(3) ? null : r.GetString(3), Qty = r.GetDecimal(4), PriceLevel = r.GetString(5), UnitPrice = r.GetDecimal(6),
                                IsVatItem = r.GetBoolean(7), DiscNo = r.IsDBNull(8) ? (int?)null : r.GetInt32(8), DiscountCode = r.IsDBNull(9) ? null : r.GetString(9),
                                DiscountAmount = r.GetDecimal(10), VatExemptAmount = r.GetDecimal(11)
                            });
                }
                using (var cmd = new SqlCommand("SELECT DiscNo, DiscountCode, Name, [Percent], CustomerName, IDNo, TIN, Remarks FROM dbo.PosHoldDiscount WHERE HoldID = @h ORDER BY DiscNo", con, tx))
                {
                    cmd.Parameters.Add("@h", SqlDbType.Int).Value = holdId;
                    using (var r = cmd.ExecuteReader())
                        while (r.Read())
                            discounts.Add(new PosSaleDiscount
                            {
                                DiscNo = r.GetInt32(0), DiscountCode = r.GetString(1), Name = r.IsDBNull(2) ? null : r.GetString(2), Percent = r.GetDecimal(3),
                                CustomerName = r.IsDBNull(4) ? null : r.GetString(4), IDNo = r.IsDBNull(5) ? null : r.GetString(5),
                                TIN = r.IsDBNull(6) ? null : r.GetString(6), Remarks = r.IsDBNull(7) ? null : r.GetString(7)
                            });
                }
                using (var cmd = new SqlCommand("DELETE FROM dbo.PosHoldDiscount WHERE HoldID = @h; DELETE FROM dbo.PosHoldLine WHERE HoldID = @h; DELETE FROM dbo.PosHold WHERE HoldID = @h;", con, tx))
                {
                    cmd.Parameters.Add("@h", SqlDbType.Int).Value = holdId;
                    cmd.ExecuteNonQuery();
                }
                tx.Commit();
                return true;
            }
        }

        // ── phase 4: charge customers ──────────────────────────────────
        public List<PosCustomer> LoadCustomers()
        {
            var list = new List<PosCustomer>();
            using (var con = Open())
            using (var cmd = new SqlCommand("SELECT CustomerKey, CustomerName, BranchCode, CreditLimit, Balance FROM dbo.PosCustomer ORDER BY CustomerName", con))
            using (var r = cmd.ExecuteReader())
                while (r.Read())
                    list.Add(new PosCustomer
                    {
                        CustomerKey = r.GetString(0), CustomerName = r.IsDBNull(1) ? "" : r.GetString(1), BranchCode = r.IsDBNull(2) ? "" : r.GetString(2),
                        CreditLimit = r.GetDecimal(3), Balance = r.GetDecimal(4)
                    });
            return list;
        }

        // What this terminal charged to the customer that the downloaded balance doesn't include: not sent yet, or posted
        // after the customer list was downloaded (UI review B3).
        public decimal UnsentCharges(string customerKey)
        {
            using (var con = Open())
            using (var cmd = new SqlCommand(@"SELECT ISNULL(SUM(p.Amount), 0) FROM dbo.PosPayment p INNER JOIN dbo.PosSale s ON s.SaleGUID = p.SaleGUID
    WHERE p.PaymentType = 'CHARGE' AND s.CustomerKey = @k AND s.Status <> 'VOIDED'
      AND (s.SyncStatus <> 'POSTED' OR @since IS NULL OR s.PostedAt >= @since)", con))
            {
                cmd.Parameters.Add("@k", SqlDbType.VarChar, 20).Value = customerKey;
                DateTime since;
                cmd.Parameters.Add("@since", SqlDbType.DateTime).Value = DateTime.TryParse(GetMeta("CustomersRefreshedAt"), out since) ? (object)since : DBNull.Value;
                return (decimal)cmd.ExecuteScalar();
            }
        }

        // ── phase 4: returns ───────────────────────────────────────────
        // UI review B2: this terminal's returns of a sale that the server doesn't have yet, laid over the server's view of
        // the sale (per line: qty and amounts; per kind: refunds), so a second return before the upload can't refund twice.
        public void AddUnsentReturns(PosReturnSource src)
        {
            using (var con = Open())
            using (var cmd = new SqlCommand(@"
SELECT rl.OrigLineNo, SUM(rl.Qty), SUM(rl.GrossAmount), SUM(rl.DiscountAmount), SUM(rl.VatExemptAmount), SUM(rl.NetAmount), SUM(rl.VatAmount)
FROM dbo.PosReturnLine rl INNER JOIN dbo.PosReturn r ON r.ReturnGUID = rl.ReturnGUID
WHERE r.OrigSaleGUID = @g AND r.SyncStatus <> 'POSTED' GROUP BY rl.OrigLineNo;
SELECT ISNULL(SUM(CashRefund), 0), ISNULL(SUM(CardRefund), 0), ISNULL(SUM(ChargeRefund), 0) FROM dbo.PosReturn WHERE OrigSaleGUID = @g AND SyncStatus <> 'POSTED';", con))
            {
                cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = src.SaleGuid;
                using (var r = cmd.ExecuteReader())
                {
                    while (r.Read())
                    {
                        var l = src.Lines.FirstOrDefault(x => x.LineNo == r.GetInt32(0));
                        if (l == null) continue;
                        l.ReturnedQty += r.GetDecimal(1); l.ReturnedGross += r.GetDecimal(2); l.ReturnedDiscount += r.GetDecimal(3);
                        l.ReturnedVatExempt += r.GetDecimal(4); l.ReturnedNet += r.GetDecimal(5); l.ReturnedVat += r.GetDecimal(6);
                    }
                    r.NextResult(); r.Read();
                    src.RefundedCash += r.GetDecimal(0); src.RefundedCard += r.GetDecimal(1); src.RefundedCharge += r.GetDecimal(2);
                    if (src.ChargeBalance.HasValue) src.ChargeBalance = Math.Max(0m, src.ChargeBalance.Value - r.GetDecimal(2));
                }
            }
        }

        // UI review B1: true when this terminal voided the sale (sent or not): the server may not know yet.
        public bool IsVoidedHere(Guid saleGuid)
        {
            using (var con = Open())
            using (var cmd = new SqlCommand("SELECT COUNT(*) FROM dbo.PosSale WHERE SaleGUID = @g AND Status = 'VOIDED'", con))
            {
                cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = saleGuid;
                return (int)cmd.ExecuteScalar() > 0;
            }
        }
        // This terminal's own sale by OR no., with what its own returns already took back (null when not on this terminal).
        // Paid / refunded per kind: cash is net of change.
        public PosReturnSource LocalReturnSource(string orNo)
        {
            using (var con = Open())
            {
                PosReturnSource src = null;
                using (var cmd = new SqlCommand(@"SELECT SaleGUID, ORNo, SaleDateTime, Status, CustomerKey, CustomerName, ChangeAmount FROM dbo.PosSale WHERE ORNo = @o", con))
                {
                    cmd.Parameters.Add("@o", SqlDbType.VarChar, 30).Value = orNo;
                    decimal change = 0m;
                    using (var r = cmd.ExecuteReader())
                        if (r.Read())
                        {
                            src = new PosReturnSource
                            {
                                SaleGuid = r.GetGuid(0), ORNo = r.GetString(1), SaleDateTime = r.GetDateTime(2), Status = r.GetString(3),
                                CustomerKey = r.IsDBNull(4) ? null : r.GetString(4), CustomerName = r.IsDBNull(5) ? null : r.GetString(5)
                            };
                            change = r.GetDecimal(6);
                        }
                    if (src == null) return null;
                    src.PaidCash = -change;
                }
                using (var cmd = new SqlCommand(@"
SELECT PaymentType, SUM(Amount) FROM dbo.PosPayment WHERE SaleGUID = @g GROUP BY PaymentType;
SELECT ISNULL(SUM(CashRefund), 0), ISNULL(SUM(CardRefund), 0), ISNULL(SUM(ChargeRefund), 0) FROM dbo.PosReturn WHERE OrigSaleGUID = @g;
SELECT l.[LineNo], l.ProductCode, l.Description, l.Qty, l.UnitPrice, l.DiscountAmount, l.VatExemptAmount, l.LineTotal, l.VatAmount, l.IsVat,
       ISNULL(x.Qty, 0), ISNULL(x.Gross, 0), ISNULL(x.Disc, 0), ISNULL(x.VatEx, 0), ISNULL(x.Net, 0), ISNULL(x.Vat, 0)
FROM dbo.PosSaleLine l
OUTER APPLY (SELECT SUM(rl.Qty) Qty, SUM(rl.GrossAmount) Gross, SUM(rl.DiscountAmount) Disc, SUM(rl.VatExemptAmount) VatEx, SUM(rl.NetAmount) Net, SUM(rl.VatAmount) Vat
             FROM dbo.PosReturnLine rl INNER JOIN dbo.PosReturn r ON r.ReturnGUID = rl.ReturnGUID
             WHERE r.OrigSaleGUID = l.SaleGUID AND rl.OrigLineNo = l.[LineNo]) x
WHERE l.SaleGUID = @g ORDER BY l.[LineNo];", con))
                {
                    cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = src.SaleGuid;
                    using (var r = cmd.ExecuteReader())
                    {
                        while (r.Read())
                        {
                            string t = r.GetString(0); decimal a = r.GetDecimal(1);
                            if (t == "CASH") src.PaidCash += a; else if (t == "CARD") src.PaidCard += a; else if (t == "CHARGE") src.PaidCharge += a;
                        }
                        r.NextResult(); r.Read();
                        src.RefundedCash = r.GetDecimal(0); src.RefundedCard = r.GetDecimal(1); src.RefundedCharge = r.GetDecimal(2);
                        r.NextResult();
                        while (r.Read())
                            src.Lines.Add(new PosReturnSourceLine
                            {
                                LineNo = r.GetInt32(0), ProductCode = r.GetString(1), Description = r.IsDBNull(2) ? "" : r.GetString(2), Qty = r.GetDecimal(3),
                                UnitPrice = r.GetDecimal(4), Gross = PosPricingService.R2(r.GetDecimal(3) * r.GetDecimal(4)), DiscountAmount = r.GetDecimal(5),
                                VatExemptAmount = r.GetDecimal(6), LineTotal = r.GetDecimal(7), VatAmount = r.GetDecimal(8), IsVat = r.GetBoolean(9),
                                ReturnedQty = r.GetDecimal(10), ReturnedGross = r.GetDecimal(11), ReturnedDiscount = r.GetDecimal(12),
                                ReturnedVatExempt = r.GetDecimal(13), ReturnedNet = r.GetDecimal(14), ReturnedVat = r.GetDecimal(15)
                            });
                    }
                }
                return src;
            }
        }

        // Saves a return with the terminal's next return no. and a RETURN outbox row (behind its sale's SALE row when the
        // sale is from this terminal), all or nothing; the local stock copy goes back up. Returns the return no.
        public string SaveReturn(PosReturn rt)
        {
            if (string.IsNullOrWhiteSpace(rt.ApprovedBy)) throw new InvalidOperationException("A return needs a supervisor's approval.");
            if (rt.Lines.Count == 0) throw new InvalidOperationException("Nothing to return.");
            if (rt.CashRefund + rt.CardRefund + rt.ChargeRefund != rt.NetAmount) throw new InvalidOperationException("The refunds don't add up to the returned amount.");
            using (var con = Open())
            using (var tx = con.BeginTransaction(IsolationLevel.Serializable))
            {
                using (var cmd = new SqlCommand("SELECT Status, CashierUserID FROM dbo.PosShift WITH (UPDLOCK, HOLDLOCK) WHERE ShiftGUID = @s", con, tx))
                {
                    cmd.Parameters.Add("@s", SqlDbType.UniqueIdentifier).Value = rt.ShiftGuid;
                    using (var r = cmd.ExecuteReader())
                        if (!r.Read() || r.GetString(0) != "OPEN" || !string.Equals(r.GetString(1), rt.CashierUserID, StringComparison.OrdinalIgnoreCase))
                            throw new InvalidOperationException("Open your own shift first.");
                }
                string prefix; long seq;
                using (var cmd = new SqlCommand("SELECT ORPrefix, NextReturnSeq FROM dbo.PosTerminal WITH (UPDLOCK, HOLDLOCK) WHERE Id = 1", con, tx))
                using (var r = cmd.ExecuteReader())
                {
                    if (!r.Read()) throw new InvalidOperationException("This terminal is not registered yet.");
                    prefix = r.GetString(0); seq = r.GetInt64(1);
                }
                // UI review B1 / B2: re-checked under lock against this terminal's own data. Its own sale: not voided, and
                // no line returned beyond what was sold (with every return this terminal made of it, sent or not)
                using (var cmd = new SqlCommand(@"
SELECT TOP 1 1 FROM dbo.PosSale WITH (UPDLOCK, HOLDLOCK) WHERE SaleGUID = @g AND Status = 'VOIDED';
SELECT l.[LineNo], l.Qty, l.LineTotal, ISNULL(x.Qty, 0), ISNULL(x.Net, 0)
FROM dbo.PosSaleLine l
OUTER APPLY (SELECT SUM(rl.Qty) Qty, SUM(rl.NetAmount) Net FROM dbo.PosReturnLine rl WITH (UPDLOCK, HOLDLOCK)
             INNER JOIN dbo.PosReturn r WITH (UPDLOCK, HOLDLOCK) ON r.ReturnGUID = rl.ReturnGUID
             WHERE r.OrigSaleGUID = l.SaleGUID AND rl.OrigLineNo = l.[LineNo]) x
WHERE l.SaleGUID = @g;", con, tx))
                {
                    cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = rt.OrigSaleGuid;
                    using (var r = cmd.ExecuteReader())
                    {
                        if (r.Read()) throw new InvalidOperationException("This sale was voided: nothing to return.");
                        r.NextResult();
                        while (r.Read())
                        {
                            int lineNo = r.GetInt32(0);
                            var mine = rt.Lines.FirstOrDefault(x => x.OrigLineNo == lineNo);
                            if (mine == null) continue;
                            if (mine.Qty + r.GetDecimal(3) > r.GetDecimal(1) || mine.NetAmount + r.GetDecimal(4) > r.GetDecimal(2))
                                throw new InvalidOperationException("Line " + lineNo + " would be returned beyond what was sold (another return of it was just made?). Look the sale up again.");
                        }
                    }
                }
                rt.ReturnNo = prefix + "-R" + seq.ToString("D8");
                using (var cmd = new SqlCommand(@"
UPDATE dbo.PosTerminal SET NextReturnSeq = NextReturnSeq + 1 WHERE Id = 1;
INSERT INTO dbo.PosReturn (ReturnGUID, ReturnNo, ShiftGUID, OrigSaleGUID, OrigORNo, ReturnDateTime, CashierUserID, CashierName, ApprovedBy, Reason,
    CustomerKey, CustomerName, CashRefund, CardRefund, ChargeRefund, SavedAt)
VALUES (@g, @no, @sh, @og, @oor, @dt, @cu, @cn, @ap, @rs, @ck, @ckn, @cash, @card, @chg, @saved);
INSERT INTO dbo.PosOutbox (SaleGUID, EventType) VALUES (@g, 'RETURN');", con, tx))
                {
                    cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = rt.ReturnGuid;
                    cmd.Parameters.Add("@no", SqlDbType.VarChar, 30).Value = rt.ReturnNo;
                    cmd.Parameters.Add("@sh", SqlDbType.UniqueIdentifier).Value = rt.ShiftGuid;
                    cmd.Parameters.Add("@og", SqlDbType.UniqueIdentifier).Value = rt.OrigSaleGuid;
                    cmd.Parameters.Add("@oor", SqlDbType.VarChar, 30).Value = rt.OrigORNo;
                    cmd.Parameters.Add("@dt", SqlDbType.DateTime).Value = rt.ReturnDateTime;
                    cmd.Parameters.Add("@cu", SqlDbType.VarChar, 50).Value = rt.CashierUserID ?? "";
                    cmd.Parameters.Add("@cn", SqlDbType.VarChar, 100).Value = (object)rt.CashierName ?? DBNull.Value;
                    cmd.Parameters.Add("@ap", SqlDbType.VarChar, 60).Value = rt.ApprovedBy;
                    cmd.Parameters.Add("@rs", SqlDbType.NVarChar, 300).Value = rt.Reason ?? "";
                    cmd.Parameters.Add("@ck", SqlDbType.VarChar, 20).Value = (object)rt.CustomerKey ?? DBNull.Value;
                    cmd.Parameters.Add("@ckn", SqlDbType.VarChar, 150).Value = (object)rt.CustomerName ?? DBNull.Value;
                    AddMoney(cmd, "@cash", rt.CashRefund); AddMoney(cmd, "@card", rt.CardRefund); AddMoney(cmd, "@chg", rt.ChargeRefund);
                    cmd.Parameters.Add("@saved", SqlDbType.DateTime).Value = rt.SavedAt;
                    cmd.ExecuteNonQuery();
                }
                foreach (var l in rt.Lines)
                    using (var cmd = new SqlCommand(@"
INSERT INTO dbo.PosReturnLine (ReturnGUID, [LineNo], OrigLineNo, ProductCode, Description, Qty, GrossAmount, DiscountAmount, VatExemptAmount, NetAmount, VatAmount)
VALUES (@g, @n, @on, @p, @d, @q, @gr, @di, @ve, @ne, @va);
UPDATE dbo.PosStock SET Available = Available + @q WHERE ProductCode = @p;", con, tx))
                    {
                        cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = rt.ReturnGuid;
                        cmd.Parameters.Add("@n", SqlDbType.Int).Value = l.LineNo;
                        cmd.Parameters.Add("@on", SqlDbType.Int).Value = l.OrigLineNo;
                        cmd.Parameters.Add("@p", SqlDbType.VarChar, 50).Value = l.ProductCode;
                        cmd.Parameters.Add("@d", SqlDbType.VarChar, 300).Value = (object)l.Description ?? DBNull.Value;
                        var q = cmd.Parameters.Add("@q", SqlDbType.Decimal); q.Precision = 18; q.Scale = 3; q.Value = l.Qty;
                        AddMoney(cmd, "@gr", l.GrossAmount); AddMoney(cmd, "@di", l.DiscountAmount); AddMoney(cmd, "@ve", l.VatExemptAmount);
                        AddMoney(cmd, "@ne", l.NetAmount); AddMoney(cmd, "@va", l.VatAmount);
                        cmd.ExecuteNonQuery();
                    }
                tx.Commit();
                return rt.ReturnNo;
            }
        }

        public PosReturn LoadReturn(Guid returnGuid)
        {
            PosReturn rt = null;
            using (var con = Open())
            {
                using (var cmd = new SqlCommand(@"SELECT ReturnNo, ShiftGUID, OrigSaleGUID, OrigORNo, ReturnDateTime, CashierUserID, CashierName, ApprovedBy, Reason,
    CustomerKey, CustomerName, CashRefund, CardRefund, ChargeRefund, SavedAt FROM dbo.PosReturn WHERE ReturnGUID = @g", con))
                {
                    cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = returnGuid;
                    using (var r = cmd.ExecuteReader())
                        if (r.Read())
                            rt = new PosReturn
                            {
                                ReturnGuid = returnGuid, ReturnNo = r.GetString(0), ShiftGuid = r.GetGuid(1), OrigSaleGuid = r.GetGuid(2), OrigORNo = r.GetString(3),
                                ReturnDateTime = r.GetDateTime(4), CashierUserID = r.GetString(5), CashierName = r.IsDBNull(6) ? null : r.GetString(6),
                                ApprovedBy = r.GetString(7), Reason = r.GetString(8), CustomerKey = r.IsDBNull(9) ? null : r.GetString(9),
                                CustomerName = r.IsDBNull(10) ? null : r.GetString(10), CashRefund = r.GetDecimal(11), CardRefund = r.GetDecimal(12),
                                ChargeRefund = r.GetDecimal(13), SavedAt = r.GetDateTime(14)
                            };
                }
                if (rt == null) return null;
                using (var cmd = new SqlCommand(@"SELECT [LineNo], OrigLineNo, ProductCode, Description, Qty, GrossAmount, DiscountAmount, VatExemptAmount, NetAmount, VatAmount
    FROM dbo.PosReturnLine WHERE ReturnGUID = @g ORDER BY [LineNo]", con))
                {
                    cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = returnGuid;
                    using (var r = cmd.ExecuteReader())
                        while (r.Read())
                            rt.Lines.Add(new PosReturnLine
                            {
                                LineNo = r.GetInt32(0), OrigLineNo = r.GetInt32(1), ProductCode = r.GetString(2), Description = r.IsDBNull(3) ? null : r.GetString(3),
                                Qty = r.GetDecimal(4), GrossAmount = r.GetDecimal(5), DiscountAmount = r.GetDecimal(6), VatExemptAmount = r.GetDecimal(7),
                                NetAmount = r.GetDecimal(8), VatAmount = r.GetDecimal(9)
                            });
                }
            }
            return rt;
        }

        // the server's answer to a RETURN
        public void MarkReturnSent(int outboxId, Guid returnGuid, string message)
        {
            using (var con = Open())
            using (var cmd = new SqlCommand(@"
UPDATE dbo.PosOutbox SET Status = 'SENT', SentAt = GETDATE(), LastAttemptAt = GETDATE(), Attempts = Attempts + 1, LastError = NULL WHERE OutboxID = @o;
UPDATE dbo.PosReturn SET SyncStatus = 'POSTED', SyncMessage = @m WHERE ReturnGUID = @g;", con))
            {
                cmd.Parameters.Add("@o", SqlDbType.Int).Value = outboxId;
                cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = returnGuid;
                cmd.Parameters.Add("@m", SqlDbType.NVarChar, 1000).Value = Trim(message, 1000);
                cmd.ExecuteNonQuery();
            }
        }

        // ── outbox results ─────────────────────────────────────────────
        // posted (or already on the server): the outbox entry is done
        public void MarkPosted(int outboxId, Guid saleGuid, int shortLines, string message)
        {
            using (var con = Open())
            using (var cmd = new SqlCommand(@"
UPDATE dbo.PosOutbox SET Status = 'SENT', SentAt = GETDATE(), LastAttemptAt = GETDATE(), Attempts = Attempts + 1, LastError = NULL WHERE OutboxID = @o;
UPDATE dbo.PosSale SET SyncStatus = 'POSTED', PostedAt = GETDATE(), ShortLines = @s, SyncMessage = @m WHERE SaleGUID = @g;", con))
            {
                cmd.Parameters.Add("@o", SqlDbType.Int).Value = outboxId;
                cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = saleGuid;
                cmd.Parameters.Add("@s", SqlDbType.Int).Value = shortLines;
                cmd.Parameters.Add("@m", SqlDbType.NVarChar, 1000).Value = (object)message ?? DBNull.Value;
                cmd.ExecuteNonQuery();
            }
        }

        // a VOID accepted (or already voided) by the server
        public void MarkVoidSent(int outboxId, Guid saleGuid, string message)
        {
            using (var con = Open())
            using (var cmd = new SqlCommand(@"
UPDATE dbo.PosOutbox SET Status = 'SENT', SentAt = GETDATE(), LastAttemptAt = GETDATE(), Attempts = Attempts + 1, LastError = NULL WHERE OutboxID = @o;
UPDATE dbo.PosSale SET SyncMessage = @m WHERE SaleGUID = @g;", con))
            {
                cmd.Parameters.Add("@o", SqlDbType.Int).Value = outboxId;
                cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = saleGuid;
                cmd.Parameters.Add("@m", SqlDbType.NVarChar, 1000).Value = (object)message ?? DBNull.Value;
                cmd.ExecuteNonQuery();
            }
        }

        // refused by the server for good (validation): kept for review, not retried
        public void MarkFailed(int outboxId, Guid saleGuid, string error)
        {
            using (var con = Open())
            using (var cmd = new SqlCommand(@"
UPDATE dbo.PosOutbox SET Status = 'FAILED', LastAttemptAt = GETDATE(), Attempts = Attempts + 1, LastError = @e WHERE OutboxID = @o;
UPDATE dbo.PosSale SET SyncStatus = 'FAILED', SyncMessage = @e WHERE SaleGUID = @g;
UPDATE dbo.PosShift SET SyncMessage = @e WHERE ShiftGUID = @g;
UPDATE dbo.PosReturn SET SyncStatus = 'FAILED', SyncMessage = @e WHERE ReturnGUID = @g;", con))
            {
                cmd.Parameters.Add("@o", SqlDbType.Int).Value = outboxId;
                cmd.Parameters.Add("@g", SqlDbType.UniqueIdentifier).Value = saleGuid;
                cmd.Parameters.Add("@e", SqlDbType.NVarChar, 1000).Value = Trim(error, 1000);
                cmd.ExecuteNonQuery();
            }
        }

        // a network / server problem: stays PENDING, tried again later
        public void MarkAttempt(int outboxId, string error)
        {
            using (var con = Open())
            using (var cmd = new SqlCommand("UPDATE dbo.PosOutbox SET LastAttemptAt = GETDATE(), Attempts = Attempts + 1, LastError = @e WHERE OutboxID = @o;", con))
            {
                cmd.Parameters.Add("@o", SqlDbType.Int).Value = outboxId;
                cmd.Parameters.Add("@e", SqlDbType.NVarChar, 1000).Value = Trim(error, 1000);
                cmd.ExecuteNonQuery();
            }
        }

        // "needs attention" back to the queue (after the cause was fixed on the server)
        public int RetryFailed()
        {
            using (var con = Open())
            using (var cmd = new SqlCommand(@"
UPDATE dbo.PosSale SET SyncStatus = 'PENDING' WHERE SaleGUID IN (SELECT SaleGUID FROM dbo.PosOutbox WHERE Status = 'FAILED' AND EventType = 'SALE');
UPDATE dbo.PosReturn SET SyncStatus = 'PENDING' WHERE ReturnGUID IN (SELECT SaleGUID FROM dbo.PosOutbox WHERE Status = 'FAILED' AND EventType = 'RETURN');
UPDATE dbo.PosOutbox SET Status = 'PENDING' WHERE Status = 'FAILED';
SELECT @@ROWCOUNT;", con))
                return (int)cmd.ExecuteScalar();   // the outbox entries re-queued (sales, voids and shift events)
        }

        public void Counts(out int pending, out int failed)
        {
            using (var con = Open())
            using (var cmd = new SqlCommand("SELECT SUM(CASE WHEN Status = 'PENDING' THEN 1 ELSE 0 END), SUM(CASE WHEN Status = 'FAILED' THEN 1 ELSE 0 END) FROM dbo.PosOutbox", con))
            using (var r = cmd.ExecuteReader())
            {
                r.Read();
                pending = r.IsDBNull(0) ? 0 : r.GetInt32(0);
                failed = r.IsDBNull(1) ? 0 : r.GetInt32(1);
            }
        }

        private static string Trim(string s, int max) => string.IsNullOrEmpty(s) ? "" : (s.Length <= max ? s : s.Substring(0, max));
    }
}
