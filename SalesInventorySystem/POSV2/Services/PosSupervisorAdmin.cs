using System;
using System.Data;
using System.Data.SqlClient;

namespace SalesInventorySystem.POSV2.Services
{
    // Server calls of the supervisor admin screen (phase 3). Online only: they go straight to the server.
    // The PIN is hashed here (PasswordHasher, PBKDF2) and only the hash is sent; the server checks the caller is an admin.
    public static class PosSupervisorAdmin
    {
        public const int MinPinLength = 6;

        public static DataTable List()
        {
            var dt = new DataTable();
            using (var con = new SqlConnection(PosV2Config.ServerConnectionString()))
            using (var cmd = new SqlCommand("dbo.sp_POSV2_ListSupervisors", con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 60 })
                new SqlDataAdapter(cmd).Fill(dt);
            return dt;
        }

        // pin == null keeps the current PIN; branch null / "" = every branch.
        public static void Set(string userId, string branch, string pin, bool active)
        {
            if (pin != null && (pin.Length < MinPinLength || !IsDigits(pin)))
                throw new InvalidOperationException("The PIN must be at least " + MinPinLength + " digits.");
            using (var con = new SqlConnection(PosV2Config.ServerConnectionString()))
            using (var cmd = new SqlCommand("dbo.spu_POSV2_SetSupervisor", con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 60 })
            {
                cmd.Parameters.Add("@UserID", SqlDbType.VarChar, 50).Value = userId;
                cmd.Parameters.Add("@BranchCode", SqlDbType.VarChar, 10).Value = string.IsNullOrWhiteSpace(branch) ? (object)DBNull.Value : branch.Trim();
                if (pin != null)
                {
                    var h = PasswordHasher.HashPassword(pin);
                    cmd.Parameters.Add("@PinHash", SqlDbType.VarBinary, 32).Value = h.Hash;
                    cmd.Parameters.Add("@PinSalt", SqlDbType.VarBinary, 16).Value = h.Salt;
                    cmd.Parameters.Add("@PinIterations", SqlDbType.Int).Value = h.Iterations;
                }
                cmd.Parameters.Add("@IsActive", SqlDbType.Bit).Value = active;
                cmd.Parameters.Add("@User", SqlDbType.VarChar, 60).Value = Login.isglobalUserID ?? "";
                con.Open();
                cmd.ExecuteNonQuery();
            }
        }

        private static bool IsDigits(string s)
        {
            foreach (char c in s) if (c < '0' || c > '9') return false;
            return true;
        }
    }
}
