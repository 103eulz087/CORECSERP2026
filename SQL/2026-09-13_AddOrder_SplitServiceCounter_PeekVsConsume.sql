-- 2026-09-13: AddOrder.cs PO/Service order numbering fix
--
-- Root cause: sp_GetPurchaseOrderNumber is an ATOMIC, CONSUMING counter (a transaction that
-- reads the singleton counter row's CURRENT value -- which IS the next number to hand out --
-- returns it, then advances the stored value by 1 for whoever calls next), which is correct
-- for preventing duplicate numbers under concurrency in principle, but AddOrder.cs was calling
-- it on every form Load AND every "New" click, for BOTH the Products tab and the Services tab,
-- sharing the SAME ponumber row. That permanently advances the counter even when the draft is
-- never saved, and collapses two independent document types onto one shared sequence.
--
-- Fix: give Services its own counter table/proc, and split each pair into a non-consuming
-- PEEK (for on-screen display on Load/New -- shows the raw stored value, since that IS the
-- next number Get will hand out) and the existing atomic Get proc (called once, at actual
-- Save time, in saveAll()/saveAllServices() -- see the matching AddOrder.cs change).
--
-- NOTE ON sp_GetPurchaseOrderNumber (existing, NOT modified by this script): its locking hint
-- is `WITH (TABLOCK, HOLDLOCK)` with no UPDLOCK. TABLOCK on a bare SELECT takes a Shared table
-- lock; two concurrent callers can both hold Shared, then both block promoting to Exclusive for
-- the subsequent UPDATE -- a lock-escalation deadlock, not a clean queue. It also has no
-- TRY/CATCH, so a deadlock victim's error surfaces raw (IDGenerator.getIDNumberSP swallows the
-- SqlException and returns "", so the textbox would just come back blank). This is a real,
-- pre-existing risk under concurrent Save clicks -- flagging per the "surface, don't silently
-- fix" convention rather than altering a live proc without confirmation. The new
-- sp_GetServiceOrderNumber below is built correctly (UPDLOCK + TRY/CATCH) since it's new code;
-- ask if you'd like sp_GetPurchaseOrderNumber patched to match (would need the SP-backup-rename
-- convention since it's altering an existing/live proc).

-- 1) Dedicated counter table for Service Orders (previously shared ponumber with Products)
IF OBJECT_ID('dbo.sonumber', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.sonumber
    (
        SONumber INT NOT NULL
    );
    INSERT INTO dbo.sonumber (SONumber) VALUES (1);
END
GO

-- 2) Atomic, consuming allocator for Service Orders -- mirrors sp_GetPurchaseOrderNumber's
--    intent (return-current-then-advance), but with UPDLOCK added (avoids the Shared-lock
--    deadlock noted above) and proper TRY/CATCH/XACT_ABORT since this is new code.
--    NOTE: the rollover threshold below uses a value that actually fits in an INT (unlike
--    sp_GetPurchaseOrderNumber's existing `> 99999999999`, which can never be true for an INT
--    and is effectively dead code there -- left that proc untouched, flagging in case you want
--    it corrected too).
IF OBJECT_ID('dbo.sp_GetServiceOrderNumber', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetServiceOrderNumber
GO
-- Atomically returns the next Service Order number and advances dbo.sonumber for the next
-- caller. Single-row counter table, locked UPDLOCK+HOLDLOCK+TABLOCK for the whole transaction
-- so concurrent callers queue instead of deadlocking or racing to the same number.
CREATE PROCEDURE dbo.sp_GetServiceOrderNumber
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    DECLARE @NextNumber INT

    BEGIN TRY
        BEGIN TRANSACTION
            SELECT @NextNumber = SONumber FROM dbo.sonumber WITH (TABLOCK, HOLDLOCK, UPDLOCK)
            IF @NextNumber > 999999999
            BEGIN
                SET @NextNumber = 1
                UPDATE dbo.sonumber SET SONumber = 2
            END
            ELSE
                UPDATE dbo.sonumber SET SONumber = SONumber + 1
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH

    SELECT CONVERT(VARCHAR(10), @NextNumber) AS SONumber
END
GO

-- 3) Non-consuming PEEK procs for on-screen display only (Load / New). No transaction, no
--    lock, no UPDATE. IMPORTANT: the stored counter value IS already "the next number that
--    will be issued" (Get returns it as-is, then advances the stored value for the call after
--    that) -- so these must return the raw stored value, NOT value+1.
IF OBJECT_ID('dbo.sp_PeekPurchaseOrderNumber', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_PeekPurchaseOrderNumber
GO
-- Read-only preview of what sp_GetPurchaseOrderNumber would currently return. Not authoritative
-- -- another session's Save between this peek and this session's Save can move it forward.
CREATE PROCEDURE dbo.sp_PeekPurchaseOrderNumber
AS
BEGIN
    SET NOCOUNT ON
    SELECT CONVERT(VARCHAR(10), PONumber) AS PONumber FROM dbo.ponumber
END
GO

IF OBJECT_ID('dbo.sp_PeekServiceOrderNumber', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_PeekServiceOrderNumber
GO
-- Read-only preview of what sp_GetServiceOrderNumber would currently return. Mirrors that
-- proc's rollover so the preview doesn't diverge from it right at the wraparound boundary.
CREATE PROCEDURE dbo.sp_PeekServiceOrderNumber
AS
BEGIN
    SET NOCOUNT ON
    SELECT CONVERT(VARCHAR(10), CASE WHEN SONumber > 999999999 THEN 1 ELSE SONumber END) AS SONumber
    FROM dbo.sonumber
END
GO
