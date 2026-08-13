using System;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;

namespace SalesInventorySystem.Classes
{
    // Session-wide holder for the credit-limit remote-approval relay. Call Initialize() once,
    // right after login (Login.cs, right after Main is shown -- Login.assignedBranch/
    // isglobalApprover/isglobalUserID/Fullname must already be populated).
    //
    // Configuration lives in the registry, per machine, matching the existing convention used
    // for DB connection settings (see Classes/Database.cs, Connection.cs):
    //   HKCU\AAITCRE\ApprovalRelaySettings
    //     RelayHost   (String) -- hostname or IP of the ONE PC per branch hosting the relay
    //     RelayPort   (DWORD)  -- e.g. 7995
    //     IsRelayHost (DWORD)  -- 1 on that one PC only; 0 or absent everywhere else
    //
    // If this key is missing (not yet configured for a branch), Initialize() simply leaves
    // Client null -- callers (AddOrder.cs) already treat that the same as "not connected" and
    // fall back to the existing local AuthorizedConfirmationFrm flow. Remote approval is
    // opt-in per branch, not a hard requirement.
    public static class ApprovalRelaySession
    {
        public static ApprovalRelayServer Server { get; private set; }
        public static ApprovalRelayClient Client { get; private set; }

        // Plain-text log so connection failures are diagnosable on a deployed machine without a
        // debugger attached -- check %TEMP%\ApprovalRelay.log on both the host and the requesting
        // machine after a failed test.
        private static readonly string LogPath = Path.Combine(Path.GetTempPath(), "ApprovalRelay.log");

        // Public so callers outside this class (e.g. AddOrder.cs, on the requesting side) can
        // write to the same log for a single, correlatable trail of one approval round-trip.
        public static void Log(string message)
        {
            try
            {
                File.AppendAllText(LogPath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} [{Environment.MachineName}] {message}{Environment.NewLine}");
            }
            catch
            {
                // logging must never be the reason the app breaks
            }
        }

        public static void Initialize()
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(@"AAITCRE\ApprovalRelaySettings"))
                {
                    if (key == null)
                    {
                        Log("No HKCU\\AAITCRE\\ApprovalRelaySettings key found -- remote approval disabled on this machine.");
                        return;
                    }

                    string host = key.GetValue("RelayHost") as string;
                    object portObj = key.GetValue("RelayPort");
                    object hostFlagObj = key.GetValue("IsRelayHost");

                    if (string.IsNullOrWhiteSpace(host) || portObj == null)
                    {
                        Log($"RelayHost/RelayPort missing or empty (RelayHost='{host}', RelayPort='{portObj}') -- remote approval disabled.");
                        return;
                    }

                    int port = Convert.ToInt32(portObj);
                    bool isHost = hostFlagObj != null && Convert.ToInt32(hostFlagObj) == 1;
                    string role = Convert.ToBoolean(Login.isglobalApprover) ? "Supervisor" : "Cashier";

                    Log($"Config: RelayHost={host} RelayPort={port} IsRelayHost={isHost} Role={role} Branch={Login.assignedBranch} User={Login.isglobalUserID}");

                    if (isHost)
                    {
                        Server = new ApprovalRelayServer();
                        try
                        {
                            Server.Start(port);
                            Log($"Relay SERVER started, listening on http://+:{port}/relay/");
                        }
                        catch (Exception ex)
                        {
                            // Most likely cause: no URL ACL reservation / not running elevated,
                            // or the port is already in use. Don't block login over this -- log
                            // and continue without hosting; this machine can still act as a
                            // Cashier/Supervisor client below.
                            Server = null;
                            Log("Relay SERVER FAILED to start: " + ex.Message);
                        }
                    }

                    Client = new ApprovalRelayClient(host, port, role, Login.assignedBranch, Login.isglobalUserID, Login.Fullname);

                    if (role == "Supervisor")
                        Client.OnApprovalRequested += HandleIncomingApprovalRequest;

                    // Fire-and-forget, but log the outcome -- ConnectAsync itself already has a
                    // 5s internal timeout, so this always resolves quickly either way.
                    _ = Task.Run(async () =>
                    {
                        bool ok = await Client.ConnectAsync(TimeSpan.FromSeconds(5));
                        Log(ok
                            ? $"Relay CLIENT connected to {Client.ServerUri} as {role}."
                            : $"Relay CLIENT FAILED to connect to {Client.ServerUri} : {Client.LastError}");
                    });
                }
            }
            catch (Exception ex)
            {
                Log("ApprovalRelaySession.Initialize crashed: " + ex.Message);
            }
        }

        // Fired from ApprovalRelayClient's receive loop -- a background thread, not the UI
        // thread -- so every WinForms call below has to be marshalled first.
        private static void HandleIncomingApprovalRequest(ApprovalRequest req)
        {
            Log($"Incoming approval request {req.RequestId} from {req.RequestingUserName} (Branch {req.Branch}), amount {req.OrderAmount:N2}.");
            if (Application.OpenForms.Count == 0) return;
            Form target = Application.OpenForms[0];
            if (target.InvokeRequired)
                target.Invoke((MethodInvoker)(() => ShowApprovalPrompt(req)));
            else
                ShowApprovalPrompt(req);
        }

        private static void ShowApprovalPrompt(ApprovalRequest req)
        {
            string msg =
                $"{req.RequestingUserName} (Branch {req.Branch}) is requesting override approval.\n\n" +
                $"Customer: {req.CustomerName}\n" +
                $"Order Amount: {req.OrderAmount:N2}\n" +
                $"Credit Limit: {req.CreditLimit:N2}\n" +
                $"Reason: {req.Reason}\n\n" +
                "Click OK to enter your credentials and approve or decline.";

            BigAlert.Show("SUPERVISOR APPROVAL REQUESTED", msg, MessageBoxIcon.Warning);

            var authfrm = new AuthorizedConfirmationFrm();
            authfrm.ShowDialog();

            var response = new ApprovalResponse
            {
                RequestId = req.RequestId,
                Approved = AuthorizedConfirmationFrm.isconfirmedLogin,
                ApproverUserID = AuthorizedConfirmationFrm.isglobalUserID,
                ApproverName = Login.Fullname,
                Message = AuthorizedConfirmationFrm.isconfirmedLogin ? "Approved" : "Declined"
            };

            AuthorizedConfirmationFrm.isconfirmedLogin = false;
            authfrm.Dispose();

            Log($"Responding to request {req.RequestId}: {response.Message} by {response.ApproverUserID}.");
            _ = Client?.RespondAsync(response);
        }
    }
}
