using System;
using System.Security.Cryptography;
using System.Text;

namespace SalesInventorySystem.Classes
{
    // Protects secrets (connection strings, passwords) written to the registry using
    // Windows DPAPI, scoped to the current Windows user profile (DataProtectionScope.
    // CurrentUser) -- the encrypted bytes can only be decrypted by that same Windows
    // account on that same machine, so a dumped registry value (regedit, reg query, an
    // admin loading someone else's profile hive) is useless outside that context. This
    // does NOT protect against someone already logged in as that Windows account --
    // that's the same access the app itself needs to run.
    public static class RegistryProtection
    {
        // Ties the ciphertext to this specific use (connection settings), so a DPAPI
        // blob written for a different purpose on the same machine can't be swapped in.
        static readonly byte[] Entropy = Encoding.UTF8.GetBytes("CORECS-ConnSettings-v1");

        public static string Protect(string plaintext)
        {
            if (string.IsNullOrEmpty(plaintext))
                return plaintext;

            byte[] data = Encoding.UTF8.GetBytes(plaintext);
            byte[] protectedData = ProtectedData.Protect(data, Entropy, DataProtectionScope.CurrentUser);
            return Convert.ToBase64String(protectedData);
        }

        // Defensive: if the stored value isn't valid DPAPI-protected data -- legacy
        // plaintext from before this change, or a registry path this was never applied
        // to -- return it unchanged instead of throwing, so anything not yet migrated
        // keeps working exactly as before.
        public static string Unprotect(string stored)
        {
            if (string.IsNullOrEmpty(stored))
                return stored;

            try
            {
                byte[] protectedData = Convert.FromBase64String(stored);
                byte[] data = ProtectedData.Unprotect(protectedData, Entropy, DataProtectionScope.CurrentUser);
                return Encoding.UTF8.GetString(data);
            }
            catch
            {
                return stored;
            }
        }
    }
}
