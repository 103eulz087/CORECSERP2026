using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json;

namespace SalesInventorySystem.Classes
{
    // Minimal WebSocket relay for the credit-limit remote-approval flow. Runs on ONE
    // designated PC per branch (see ApprovalRelaySession -- HKCU\AAITCRE\ApprovalRelaySettings,
    // IsRelayHost=1). Cashier and Supervisor terminals on the same LAN both connect to it as
    // clients; it does no business logic of its own, it only routes messages:
    //   - "request"  from a Cashier  -> broadcast to every connected Supervisor on the same branch
    //     (and always to Head Office, "888")
    //   - "response" from a Supervisor -> routed back to the exact connection that sent the
    //     matching "request" (tracked by RequestId, see pendingRequests below) -- NOT broadcast
    //     by role. A user who is both placing orders AND registered as a Supervisor (isApprover=1
    //     on their own login, e.g. an HO user, or "sa" during testing) would never receive a
    //     response under a Role=="Cashier" broadcast filter, since their own connection is
    //     registered as "Supervisor".
    //
    // IMPORTANT (one-time setup on the host machine): HttpListener binding to "+" (all
    // interfaces) requires either running elevated or a prior URL ACL reservation, e.g.:
    //   netsh http add urlacl url=http://+:7995/relay/ user=Everyone
    // Without one of those, Start() will throw HttpListenerException (Access is denied).
    public class ApprovalRelayServer
    {
        private HttpListener listener;
        private CancellationTokenSource cts;
        private readonly List<ConnectedClient> clients = new List<ConnectedClient>();
        private readonly Dictionary<string, ConnectedClient> pendingRequests = new Dictionary<string, ConnectedClient>();
        private readonly object clientsLock = new object();

        private class ConnectedClient
        {
            public WebSocket Socket;
            public string Role;
            public string Branch;
            public string UserID;
        }

        public bool IsRunning => listener != null && listener.IsListening;

        public void Start(int port)
        {
            if (IsRunning) return;

            listener = new HttpListener();
            listener.Prefixes.Add($"http://+:{port}/relay/");
            listener.Start();

            cts = new CancellationTokenSource();
            _ = AcceptLoopAsync(cts.Token);
        }

        public void Stop()
        {
            try { cts?.Cancel(); } catch { }
            try { listener?.Stop(); } catch { }
            listener = null;
        }

        private async Task AcceptLoopAsync(CancellationToken token)
        {
            while (!token.IsCancellationRequested && listener != null && listener.IsListening)
            {
                HttpListenerContext ctx;
                try
                {
                    ctx = await listener.GetContextAsync().ConfigureAwait(false);
                }
                catch
                {
                    break; // listener stopped
                }

                if (ctx.Request.IsWebSocketRequest)
                {
                    _ = HandleClientAsync(ctx, token);
                }
                else
                {
                    ctx.Response.StatusCode = 400;
                    ctx.Response.Close();
                }
            }
        }

        private async Task HandleClientAsync(HttpListenerContext ctx, CancellationToken token)
        {
            WebSocketContext wsCtx;
            try
            {
                wsCtx = await ctx.AcceptWebSocketAsync(null).ConfigureAwait(false);
            }
            catch
            {
                return;
            }

            var client = new ConnectedClient { Socket = wsCtx.WebSocket };
            var buffer = new byte[8192];

            try
            {
                while (client.Socket.State == WebSocketState.Open && !token.IsCancellationRequested)
                {
                    var result = await client.Socket.ReceiveAsync(new ArraySegment<byte>(buffer), token).ConfigureAwait(false);
                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        await client.Socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "", token).ConfigureAwait(false);
                        break;
                    }

                    string json = Encoding.UTF8.GetString(buffer, 0, result.Count);
                    RelayEnvelope envelope;
                    try { envelope = JsonConvert.DeserializeObject<RelayEnvelope>(json); }
                    catch { continue; } // malformed frame -- drop it, keep the connection alive

                    if (envelope == null) continue;

                    if (envelope.Type == "hello")
                    {
                        var hello = JsonConvert.DeserializeObject<RelayHello>(envelope.Payload);
                        client.Role = hello.Role;
                        client.Branch = hello.Branch;
                        client.UserID = hello.UserID;
                        lock (clientsLock) { clients.Add(client); }
                    }
                    else if (envelope.Type == "request")
                    {
                        var req = JsonConvert.DeserializeObject<ApprovalRequest>(envelope.Payload);
                        // Route to Supervisors at the requester's own branch (if that branch has
                        // any -- most don't) AND always to Head Office ("888", the fixed HO branch
                        // code used throughout this codebase -- see e.g. sp_CreditMemo, sp_
                        // ConfirmOrder). HO acts as the catch-all approver pool for branches that
                        // only have sales agents/coordinators and no local supervisor.
                        //
                        // Also excludes the sender's own connection -- a user who is both a
                        // Cashier placing this order AND a registered Supervisor (e.g. testing
                        // with "sa", or an HO user placing their own order) would otherwise get
                        // their own request bounced straight back to them.
                        lock (clientsLock) { pendingRequests[req.RequestId] = client; }
                        await BroadcastAsync(envelope, c => c.Role == "Supervisor" && (c.Branch == req.Branch || c.Branch == "888") && c.Socket != client.Socket, token).ConfigureAwait(false);
                    }
                    else if (envelope.Type == "response")
                    {
                        var resp = JsonConvert.DeserializeObject<ApprovalResponse>(envelope.Payload);
                        ConnectedClient origin;
                        lock (clientsLock)
                        {
                            pendingRequests.TryGetValue(resp.RequestId, out origin);
                            if (origin != null) pendingRequests.Remove(resp.RequestId);
                        }

                        if (origin != null)
                            await BroadcastAsync(envelope, c => ReferenceEquals(c, origin), token).ConfigureAwait(false);
                        // origin == null -> the requester's connection already dropped (or the
                        // request expired/was never tracked) -- nothing to deliver to.
                    }
                }
            }
            catch
            {
                // connection dropped -- nothing to do, cleaned up below
            }
            finally
            {
                lock (clientsLock)
                {
                    clients.Remove(client);
                    foreach (var key in pendingRequests.Where(kv => ReferenceEquals(kv.Value, client)).Select(kv => kv.Key).ToList())
                        pendingRequests.Remove(key);
                }
            }
        }

        private async Task BroadcastAsync(RelayEnvelope envelope, Func<ConnectedClient, bool> filter, CancellationToken token)
        {
            List<ConnectedClient> targets;
            lock (clientsLock)
            {
                targets = clients.Where(c => c.Socket.State == WebSocketState.Open && filter(c)).ToList();
            }

            string json = JsonConvert.SerializeObject(envelope);
            byte[] bytes = Encoding.UTF8.GetBytes(json);

            foreach (var t in targets)
            {
                try
                {
                    await t.Socket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, token).ConfigureAwait(false);
                }
                catch
                {
                    // one dead peer shouldn't stop delivery to the rest
                }
            }
        }
    }
}
