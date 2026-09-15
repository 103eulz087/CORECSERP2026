-- 2026-09-13: AddPurchaseOrder.cs (HOFormsDevEx) ShipmentNo peek-vs-consume fix
--
-- Same root cause as the AddOrder.cs PO/SO numbering fix: sp_GetShipmentNo is an ATOMIC,
-- CONSUMING counter (transaction reads dbo.ShipmentNo's CURRENT value -- which IS the next
-- number to hand out -- returns it, then advances the stored value by 1 for the next caller),
-- correct for preventing duplicates in principle, but AddPurchaseOrder.cs's btnnew_Click called
-- it just to populate the on-screen preview, permanently burning a real number even when the
-- draft PO is never saved.
--
-- sp_GetShipmentNo is shared by several other forms (AddPODevEx.cs, AddNonTradeOrdersDevEx.cs,
-- ADDPO.cs, AddNewShipment.cs) -- this script does NOT alter it, only adds a non-consuming peek
-- companion. AddPurchaseOrder.cs is changed to call the peek on "New" and the real atomic proc
-- once, at Save time (see the matching AddPurchaseOrder.cs change).
--
-- NOTE (not changed here, flagging per "surface, don't silently fix"): sp_GetShipmentNo has the
-- same locking gap as sp_GetPurchaseOrderNumber -- `WITH (TABLOCK, HOLDLOCK)` with no UPDLOCK,
-- so two near-simultaneous callers can deadlock instead of queueing; the swallowed SqlException
-- in IDGenerator.getIDNumberSP would then hand back an empty ShipmentNo. Given how many forms
-- share this proc, fixing it is a separate, wider-blast-radius change -- say the word if you
-- want it done (with the SP-backup-rename convention, since it's a live, shared proc).
IF OBJECT_ID('dbo.sp_PeekShipmentNo', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_PeekShipmentNo
GO
-- Read-only preview of what sp_GetShipmentNo would currently return. Mirrors its rollover (the
-- real proc resets to 0/1 once the stored value exceeds 99999) so the preview never diverges
-- from Get at the wraparound boundary. Not authoritative -- another session's Save between this
-- peek and this session's Save can move it forward.
CREATE PROCEDURE dbo.sp_PeekShipmentNo
AS
BEGIN
    SET NOCOUNT ON
    SELECT TOP (1) CONVERT(VARCHAR(10), CASE WHEN ShipmentNo > 99999 THEN 0 ELSE ShipmentNo END) AS ShipmentNo
    FROM dbo.ShipmentNo
END
GO
