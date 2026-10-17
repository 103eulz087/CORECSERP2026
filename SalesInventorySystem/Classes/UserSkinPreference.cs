using System;
using System.Data;
using System.Data.SqlClient;
using System.Threading.Tasks;
using DevExpress.LookAndFeel;

namespace SalesInventorySystem
{
    // ================================================================
    // 2026-10-16 (user, script [100]): each user's DevExpress skin, saved on their account
    // (dbo.UserUIPreference, one row per UserID in each database) and applied at login, so a pick from
    // the ribbon's skin gallery survives logging out and works on any PC. A user with nothing saved gets
    // the app's default: WXI Compact on PRODUCTION, Black on any other database.
    // Saved only when the user clicks a skin in the ribbon gallery (Main): several report screens switch
    // the app's skin in code, and those switches must not become the user's choice.
    // A skin is never worth a failed login or a lost posting, so nothing here throws.
    // ================================================================
    public static class UserSkinPreference
    {
        public const string ProductionDatabase = "PRODJFC_COREX";

        // the app's default (also Program.cs at start-up, before anyone is logged in): Black = NOT production,
        // same value as Main's dbname label (registry "dbname" under ConnSettingsMain)
        public static void ApplyDefault()
        {
            string dbName = "";
            try { dbName = (Database.getConnectionServerName("dbname") ?? "").Trim(); } catch { }
            UserLookAndFeel.Default.SetSkinStyle(string.Equals(dbName, ProductionDatabase, StringComparison.OrdinalIgnoreCase)
                ? SkinStyle.WXICompact : SkinStyle.Black);
        }

        // after a successful login: the user's saved skin (and palette), else the default
        public static void ApplyForUser(string userId)
        {
            string skin = null, palette = null;
            try
            {
                using (var con = Database.getConnection())
                using (var cmd = new SqlCommand("sp_UserUIPreference_Get", con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 15 })
                {
                    cmd.Parameters.Add("@UserID", SqlDbType.VarChar, 50).Value = (userId ?? "").Trim();
                    con.Open();
                    using (var rd = cmd.ExecuteReader())
                        if (rd.Read())
                        {
                            skin = Convert.ToString(rd["SkinName"]);
                            palette = Convert.ToString(rd["PaletteName"]);
                        }
                }
            }
            catch (Exception ex)
            {
                // e.g. a database without [100] yet (2812): keep the default
                System.Diagnostics.Debug.WriteLine("UserSkinPreference.ApplyForUser: " + ex.Message);
            }

            if (string.IsNullOrWhiteSpace(skin) || DevExpress.Skins.SkinManager.Default.Skins[skin] == null)
            {
                ApplyDefault();
                return;
            }
            try
            {
                if (string.IsNullOrWhiteSpace(palette)) UserLookAndFeel.Default.SetSkinStyle(skin);
                else UserLookAndFeel.Default.SetSkinStyle(skin, palette);
            }
            catch
            {
                try { UserLookAndFeel.Default.SetSkinStyle(skin); } catch { ApplyDefault(); }
            }
        }

        // the skin on screen now becomes the user's saved skin. Reads the skin on the calling (UI) thread,
        // writes on a worker thread (database only, Known Bug #8). The task is returned for a harness.
        public static Task SaveCurrent(string userId)
        {
            string uid = (userId ?? "").Trim();
            string skin = UserLookAndFeel.Default.ActiveSkinName;
            string palette = UserLookAndFeel.Default.ActiveSvgPaletteName;
            if (uid.Length == 0 || string.IsNullOrWhiteSpace(skin)) return Task.FromResult(0);

            return Task.Run(() =>
            {
                try
                {
                    using (var con = Database.getConnection())
                    using (var cmd = new SqlCommand("spu_UserUIPreference_Save", con) { CommandType = CommandType.StoredProcedure, CommandTimeout = 15 })
                    {
                        cmd.Parameters.Add("@UserID", SqlDbType.VarChar, 50).Value = uid;
                        cmd.Parameters.Add("@SkinName", SqlDbType.VarChar, 100).Value = skin;
                        cmd.Parameters.Add("@PaletteName", SqlDbType.VarChar, 100).Value =
                            string.IsNullOrWhiteSpace(palette) ? (object)DBNull.Value : palette;
                        con.Open();
                        cmd.ExecuteNonQuery();
                    }
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine("UserSkinPreference.SaveCurrent: " + ex.Message);
                }
            });
        }
    }
}
