using System;
using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json;

namespace SalesInventorySystem.Classes
{
    // One persistent connection per running app instance -- see ApprovalRelaySession, which
    // owns the single shared Client for the session and wires OnApprovalRequested for
    // Supervisor-role users.
    //
    // Every await in here uses ConfigureAwait(false) on purpose: RequestApprovalAsync is called
    // from AddOrder.cs via .GetAwaiter().GetResult() on the UI thread (matching the existing
    // synchronous-blocking-with-SplashScreenManager pattern already used elsewhere in this
    // codebase, e.g. HelperFunction.ShowWaitAndDisplayNonAsync). Without ConfigureAwait(false),
    // the continuations here would try to resume on the UI thread's SynchronizationContext,
    // which is blocked on GetResult() -- a deadlock.
    public class ApprovalRelayClient
    {
        private ClientWebSocket ws;
        private readonly string serverUri;
        private readonly string role;
        private readonly string branch;
        private readonly string userId;
        private readonly string fullName;
        private readonly ConcurrentDictionary<string, TaskCompletionSource<ApprovalResponse>> pending =
            new ConcurrentDictionary<string, TaskCompletionSource<ApprovalResponse>>();

        public event Action<ApprovalRequest> OnApprovalRequested;

        public bool IsConnected => ws != null && ws.State == WebSocketState.Open;

        // Set whenever ConnectAsync returns false -- ApprovalRelaySession logs this so a failed
        // connection attempt is diagnosable without a debugger attached.
        public string LastError { get; private set; }

        public string ServerUri => serverUri;

        public ApprovalRelayClient(string host, int port, string role, string branch, string userId, string fullName)
        {
            serverUri = $"ws://{host}:{port}/relay/";
            this.role = role;
            this.branch = branch;
            this.userId = userId;
            this.fullName = fullName;
        }

        public async Task<bool> ConnectAsync(TimeSpan timeout)
        {
            try
            {
                ws = new ClientWebSocket();
                using (var timeoutCts = new CancellationTokenSource(timeout))
                {
                    await ws.ConnectAsync(new Uri(serverUri), timeoutCts.Token).ConfigureAwait(false);
                }

                _ = ListenAsync();

                await SendEnvelopeAsync("hello", new RelayHello { Role = role, Branch = branch, UserID = userId, FullName = fullName })
                    .ConfigureAwait(false);

                LastError = null;
                return true;
            }
            catch (Exception ex)
            {
                ws = null;
                LastError = ex.Message;
                return false;
            }
        }

        private async Task ListenAsync()
        {
            var buffer = new byte[8192];
            try
            {
                while (ws != null && ws.State == WebSocketState.Open)
                {
                    var result = await ws.ReceiveAsync(new ArraySegment<byte>(buffer), CancellationToken.None).ConfigureAwait(false);
                    if (result.MessageType == WebSocketMessageType.Close) break;

                    string json = Encoding.UTF8.GetString(buffer, 0, result.Count);
                    RelayEnvelope envelope;
                    try { envelope = JsonConvert.DeserializeObject<RelayEnvelope>(json); }
                    catch { continue; }

                    if (envelope == null) continue;

                    if (envelope.Type == "request")
                    {
                        var req = JsonConvert.DeserializeObject<ApprovalRequest>(envelope.Payload);
                        OnApprovalRequested?.Invoke(req);
                    }
                    else if (envelope.Type == "response")
                    {
                        var resp = JsonConvert.DeserializeObject<ApprovalResponse>(envelope.Payload);
                        if (resp != null && pending.TryRemove(resp.RequestId, out var tcs))
                            tcs.TrySetResult(resp);
                    }
                }
            }
            catch
            {
                // connection dropped -- any still-pending request simply times out on the
                // caller's side rather than throwing here
            }
        }

        // Returns null on timeout (no response received in time) or if not connected --
        // callers treat null as "fall back to local approval", NOT as an error.
        public async Task<ApprovalResponse> RequestApprovalAsync(ApprovalRequest request, TimeSpan timeout)
        {
            if (!IsConnected) return null;

            var tcs = new TaskCompletionSource<ApprovalResponse>();
            pending[request.RequestId] = tcs;

            try
            {
                await SendEnvelopeAsync("request", request).ConfigureAwait(false);
            }
            catch
            {
                pending.TryRemove(request.RequestId, out _);
                return null;
            }

            var completed = await Task.WhenAny(tcs.Task, Task.Delay(timeout)).ConfigureAwait(false);
            pending.TryRemove(request.RequestId, out _);

            return completed == tcs.Task ? tcs.Task.Result : null;
        }

        public Task RespondAsync(ApprovalResponse response)
        {
            return SendEnvelopeAsync("response", response);
        }

        private async Task SendEnvelopeAsync<T>(string type, T payload)
        {
            if (ws == null || ws.State != WebSocketState.Open)
                throw new InvalidOperationException("Relay client is not connected.");

            var envelope = new RelayEnvelope { Type = type, Payload = JsonConvert.SerializeObject(payload) };
            string json = JsonConvert.SerializeObject(envelope);
            byte[] bytes = Encoding.UTF8.GetBytes(json);
            await ws.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, CancellationToken.None).ConfigureAwait(false);
        }

        public async Task DisconnectAsync()
        {
            if (ws != null && ws.State == WebSocketState.Open)
            {
                try { await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "", CancellationToken.None).ConfigureAwait(false); }
                catch { }
            }
        }
    }
}
