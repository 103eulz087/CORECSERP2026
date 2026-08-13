using System;

namespace SalesInventorySystem.Classes
{
    // Wire format for every message sent over the relay socket. Payload is a nested
    // JSON string (rather than a polymorphic object) so the envelope itself never needs
    // to change shape as new message types are added.
    public class RelayEnvelope
    {
        public string Type { get; set; } // "hello" | "request" | "response"
        public string Payload { get; set; }
    }

    // Sent once, immediately after connecting, so the server knows how to route
    // "request"/"response" messages for this connection.
    public class RelayHello
    {
        public string Role { get; set; } // "Cashier" | "Supervisor"
        public string Branch { get; set; }
        public string UserID { get; set; }
        public string FullName { get; set; }
    }

    public class ApprovalRequest
    {
        public string RequestId { get; set; }
        public string Branch { get; set; }
        public string RequestingUserID { get; set; }
        public string RequestingUserName { get; set; }
        public string MachineName { get; set; }
        public string CustomerName { get; set; }
        public decimal OrderAmount { get; set; }
        public decimal CreditLimit { get; set; }
        public string Reason { get; set; }
        public DateTime RequestedAtUtc { get; set; }
    }

    public class ApprovalResponse
    {
        public string RequestId { get; set; }
        public bool Approved { get; set; }
        public string ApproverUserID { get; set; }
        public string ApproverName { get; set; }
        public string Message { get; set; }
    }
}
