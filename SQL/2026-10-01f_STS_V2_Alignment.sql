/* ================================================================
   2026-10-01f: STS V2 (FIFO engine) aligned to the 10-01 STS rules
   ================================================================
   User decision (2026-10-01): Orders/AddBranchOrderSTSV2 replaces
   AddBranchOrderSTS; Dispatch Per Barcode is not adopted (see
   docs/reviews/2026-10-01_DispatchPerBarcode_Review.md). The two V2
   procs were written 09-29, before the 10-01 STS redesign.

   Needs: 2026-09-29b (engine), 2026-09-29c (STS V2), 2026-10-01b (STS
   lifecycle) and 2026-10-01e (all VAT-exempt) already applied.

   Every STS writer now takes the same per-PO lock, STSTRANSIT:<PO>,
   before touching any row: V2 scan, V2 return, Save, both receive
   screens, returns and spu_STS_SyncInTransit.

   Patches the live text (each anchor must match exactly once, or
   nothing changes -- same method as 2026-10-01e):

     spu_PostSTSLineV2
       - lock STSTRANSIT:<PO> (was STSV2_<delivery>_<po>)
       - refuses once the branch has received the transfer or started
         receiving it (59834): the FIFO receive screen writes
         ReceivedOrderDetails in its first call and marks the delivery
         DELIVERED only in its third
       - refuses once the transfer is saved (59835): Save posts the In
         Transit, and the V2 form closes after Save, so only a stale
         second screen could still add lines
       - refuses a second delivery number for the same transfer (59836):
         Save and the receipt work per PO
       - InventoryDeliveryFIFO.isVat and the line's isVat come from the
         product's VAT flag at the origin, the lot flag only as a
         fallback (as 2026-10-01b did for the old proc)

     spu_ReverseSTSLineV2
       - the same lock and the same received guard (59834)
       - In Transit through spu_STS_SyncInTransit, dated today, instead of
         its own ITR-HO-VAT / ITR-HO-VATEX tickets at the request date

     sp_ConfirmBranchOrderSTS (Save; the old form uses it too)
       - takes the lock first. It took it last (inside the sync), after
         updating DeliveryDetails, so it could deadlock with the V2 procs.

     spu_PostSTSReceiveFromFIFO (FIFO receive screen, first call)
       - locks STSTRANSIT:<PO> instead of the bare PO number, so a V2
         return or scan can't run while the branch is receiving.

   No parameter changes, so no exe change. Backups end in
   _OLD_10012026230000. A second run stops at the "already applied" check.
   Then run 2026-10-01f_STS_V2_Alignment_Test.sql (rolled back) and the
   Exception Center.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;   -- the procedures created below keep these settings
SET ANSI_NULLS ON;

PRINT 'Database: ' + DB_NAME();

IF OBJECT_ID('dbo.spu_PostSTSLineV2', 'P') IS NULL OR OBJECT_ID('dbo.spu_ReverseSTSLineV2', 'P') IS NULL
   OR OBJECT_ID('dbo.spu_STS_SyncInTransit', 'P') IS NULL OR OBJECT_ID('dbo.sp_ConfirmBranchOrderSTS', 'P') IS NULL
   OR OBJECT_ID('dbo.spu_PostSTSReceiveFromFIFO', 'P') IS NULL
    THROW 59750, 'Run 2026-09-29b, 2026-09-29c, 2026-10-01b and 2026-10-01e first.', 1;

IF CHARINDEX(N'2026-10-01: the GL is all VAT-exempt', OBJECT_DEFINITION(OBJECT_ID('dbo.spu_STS_SyncInTransit'))) = 0
    THROW 59750, 'spu_STS_SyncInTransit has no 2026-10-01e note: run 2026-10-01e_GL_AllVatExempt.sql first.', 1;

IF OBJECT_ID('tempdb..#P') IS NOT NULL DROP TABLE #P;
CREATE TABLE #P (Id INT IDENTITY PRIMARY KEY, ProcName SYSNAME, OldText NVARCHAR(MAX), NewText NVARCHAR(MAX));

------------------------------------------------------------------
-- spu_PostSTSLineV2
------------------------------------------------------------------
INSERT #P (ProcName, OldText, NewText) VALUES
('spu_PostSTSLineV2',
 N'Caller: Orders/AddBranchOrderSTSV2.cs.',
 N'Caller: Orders/AddBranchOrderSTSV2.cs.
    2026-10-01f: takes the STSTRANSIT:<PO> lock every STS writer shares; refuses once the
    branch has received or started receiving (59834), once the transfer is saved (59835)
    and when the PO already has another delivery (59836); FIFO and line isVat = the
    product''s VAT flag at the origin.'),

('spu_PostSTSLineV2',
 N'DECLARE @LockRes NVARCHAR(255) = N''STSV2_'' + @DeliveryNo + N''_'' + @PONumber, @rc INT;',
 N'DECLARE @LockRes NVARCHAR(255) = N''STSTRANSIT:'' + @PONumber, @rc INT;   -- 2026-10-01f: the per-PO lock every STS writer shares'),

('spu_PostSTSLineV2',
 N'THROW 59829, ''Another user is adding to this delivery right now. Please try again.'', 1;',
 N'THROW 59829, ''Another user is changing this transfer right now (scan, save, return or receive). Please try again.'', 1;

        -- 2026-10-01f: nothing can be added once the branch has received the transfer, or
        -- started receiving it (receive writes ReceivedOrderDetails before DELIVERED is set)
        IF EXISTS (SELECT 1 FROM dbo.DeliverySummary WHERE PONumber = @PONumber AND Status = ''DELIVERED'')
           OR EXISTS (SELECT 1 FROM dbo.ReceivedOrderDetails WHERE PONumber = @PONumber)
            THROW 59834, ''The branch has already received this transfer (or started receiving it); nothing can be added to it.'', 1;

        -- 2026-10-01f: a saved transfer takes no new lines (Save posted its In Transit;
        -- the form closes after Save, so this is a stale second screen)
        IF EXISTS (SELECT 1 FROM dbo.TransferOrderSummary WHERE PONumber = @PONumber AND ISNULL(isProcess, 0) = 1)
            THROW 59835, ''This transfer has already been saved; lines can no longer be added. Cancel lines instead, or start a new transfer.'', 1;

        -- 2026-10-01f: one delivery per transfer (Save and the receipt work per PO)
        DECLARE @OtherDelivery VARCHAR(20) =
            (SELECT TOP (1) x.DeliveryNo
             FROM (SELECT DeliveryNo FROM dbo.DeliverySummary WHERE PONumber = @PONumber
                   UNION ALL
                   SELECT DeliveryNo FROM dbo.DeliveryDetails
                   WHERE PONumber = @PONumber AND ISNULL(isCancelled, 0) = 0 AND ISNULL(isReturned, 0) = 0) AS x
             WHERE x.DeliveryNo <> @DeliveryNo
             ORDER BY x.DeliveryNo);
        IF @OtherDelivery IS NOT NULL
        BEGIN
            SET @msg = N''Transfer '' + @PONumber + N'' already has delivery '' + @OtherDelivery
                     + N''. Close this screen and open the transfer again.'';
            THROW 59836, @msg, 1;
        END'),

('spu_PostSTSLineV2',
 N'a.InventorySeqNo, a.IsVat, 0, ISNULL(sp.SellingPrice, 0), a.Qty * ISNULL(sp.SellingPrice, 0)',
 N'a.InventorySeqNo, CAST(COALESCE(pv.isVat, a.IsVat, 0) AS BIT) /* 2026-10-01f: product VAT flag */, 0, ISNULL(sp.SellingPrice, 0), a.Qty * ISNULL(sp.SellingPrice, 0)'),

('spu_PostSTSLineV2',
 N'FROM #InvAlloc AS a',
 N'FROM #InvAlloc AS a
        OUTER APPLY (SELECT TOP (1) p.isVat
                     FROM dbo.Products AS p
                     WHERE p.BranchCode = @OriginBranch AND p.ProductCode = a.ProductCode) AS pv'),

('spu_PostSTSLineV2',
 N'''PENDING'', COALESCE(CASE WHEN @Method = ''SCAN'' THEN @LotIsVat END, @ProdIsVat, 0),',
 N'''PENDING'', COALESCE(@ProdIsVat, @LotIsVat, 0),   -- 2026-10-01f: product VAT flag first (SCAN used the lot flag)');

------------------------------------------------------------------
-- spu_ReverseSTSLineV2 (its GL block is replaced further down)
------------------------------------------------------------------
INSERT #P (ProcName, OldText, NewText) VALUES
('spu_ReverseSTSLineV2',
 N'posts the same ITR-HO-VAT / ITR-HO-VATEX reversal tickets as',
 N'runs spu_STS_SyncInTransit (2026-10-01f; it used to post its own ITR-HO tickets), like'),

('spu_ReverseSTSLineV2',
 N'DECLARE @LockRes NVARCHAR(255) = N''STSV2_'' + @DeliveryNo + N''_'' + @PONumber, @rc INT;',
 N'DECLARE @LockRes NVARCHAR(255) = N''STSTRANSIT:'' + @PONumber, @rc INT;   -- 2026-10-01f: the per-PO lock every STS writer shares'),

('spu_ReverseSTSLineV2',
 N'THROW 59829, ''Another user is changing this delivery right now. Please try again.'', 1;',
 N'THROW 59829, ''Another user is changing this transfer right now (scan, save, return or receive). Please try again.'', 1;

        -- 2026-10-01f: a transfer the branch has received, or started receiving, can''t be changed here
        IF EXISTS (SELECT 1 FROM dbo.DeliverySummary WHERE PONumber = @PONumber AND Status = ''DELIVERED'')
           OR EXISTS (SELECT 1 FROM dbo.ReceivedOrderDetails WHERE PONumber = @PONumber)
            THROW 59834, ''The branch has already received this transfer (or started receiving it); a line can no longer be returned here.'', 1;');

------------------------------------------------------------------
-- sp_ConfirmBranchOrderSTS (Save): lock first
------------------------------------------------------------------
INSERT #P (ProcName, OldText, NewText) VALUES
('sp_ConfirmBranchOrderSTS',
 N'SELECT @username = dbo.func_getUsername(@preparedby);',
 N'SELECT @username = dbo.func_getUsername(@preparedby);

        -- 2026-10-01f: take the per-PO lock before touching any row. spu_STS_SyncInTransit
        -- below takes it again (allowed: same transaction). The V2 procs take it first,
        -- so taking it only at the end could deadlock with them.
        DECLARE @SaveLockRes NVARCHAR(255) = N''STSTRANSIT:'' + @parmpono, @SaveLock INT;
        EXEC @SaveLock = sp_getapplock @Resource = @SaveLockRes, @LockMode = ''Exclusive'', @LockOwner = ''Transaction'', @LockTimeout = 15000;
        IF @SaveLock < 0
            THROW 58164, ''Another user is changing this transfer right now (scan, save, return or receive). Please try again.'', 1;');

------------------------------------------------------------------
-- spu_PostSTSReceiveFromFIFO: the shared lock instead of the bare PO number
------------------------------------------------------------------
INSERT #P (ProcName, OldText, NewText) VALUES
('spu_PostSTSReceiveFromFIFO',
 N'DECLARE @LockResult INT;',
 N'DECLARE @LockResult INT, @RcvLockRes NVARCHAR(255) = N''STSTRANSIT:'' + @PONumber;   -- 2026-10-01f: the per-PO lock every STS writer shares (was the bare PO number)'),

('spu_PostSTSReceiveFromFIFO',
 N'@Resource = @PONumber, @LockMode = ''Exclusive'', @LockOwner = ''Transaction'', @LockTimeout = 30000;',
 N'@Resource = @RcvLockRes, @LockMode = ''Exclusive'', @LockOwner = ''Transaction'', @LockTimeout = 30000;');

------------------------------------------------------------------
-- spu_ReverseSTSLineV2: the GL block, from its banner line up to the
-- "Header totals" banner line (whitespace inside the block doesn't matter)
------------------------------------------------------------------
DECLARE @BlockStart NVARCHAR(200) = N'-- GL reversal -- same as sp_ReverseSTSInventoryTransfer',
        @BlockEnd   NVARCHAR(200) = N'-- Header totals + status (scoped to this delivery)',
        @BlockNew   NVARCHAR(MAX) = N'-- GL (2026-10-01f), same rule as sp_ReverseSTSInventoryTransfer: once the
        -- transfer is saved (isProcess = 1), head office''s In Transit must equal the
        -- cost of the PO''s live lots, so only the difference is posted (dated today).
        -- Before Save nothing was posted, so there is nothing to reverse.
        ------------------------------------------------------------------
        IF EXISTS (SELECT 1 FROM dbo.TransferOrderSummary WHERE PONumber = @PONumber AND ISNULL(isProcess, 0) = 1)
        BEGIN
            DECLARE @Today DATE = CAST(GETDATE() AS DATE);
            EXEC dbo.spu_STS_SyncInTransit
                @PONumber = @PONumber, @DeliveryNo = @DeliveryNo, @DestBranch = @DestinationBranch,
                @User = @PreparedBy, @TicketDate = @Today;
        END

        ------------------------------------------------------------------
        ';

------------------------------------------------------------------
-- Build every new definition first; nothing changes unless all patches fit
------------------------------------------------------------------
UPDATE #P SET OldText = REPLACE(OldText, NCHAR(13) + NCHAR(10), NCHAR(10)),
              NewText = REPLACE(NewText, NCHAR(13) + NCHAR(10), NCHAR(10));
SET @BlockNew = REPLACE(@BlockNew, NCHAR(13) + NCHAR(10), NCHAR(10));

IF OBJECT_ID('tempdb..#Def') IS NOT NULL DROP TABLE #Def;
SELECT DISTINCT p.ProcName,
       REPLACE(OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + p.ProcName)), NCHAR(13) + NCHAR(10), NCHAR(10)) AS Def
INTO #Def
FROM #P AS p;

IF EXISTS (SELECT 1 FROM #Def WHERE Def IS NULL)
    THROW 59751, 'A procedure to patch is missing or its text can''t be read.', 1;

IF EXISTS (SELECT 1 FROM #Def WHERE CHARINDEX(N'2026-10-01f', Def) > 0)
    THROW 59752, 'Already applied (a procedure carries the 2026-10-01f note).', 1;

IF EXISTS (SELECT 1 FROM #Def WHERE OBJECT_ID(N'dbo.' + ProcName + N'_OLD_10012026230000') IS NOT NULL)
    THROW 59753, 'A backup named <proc>_OLD_10012026230000 already exists.', 1;

-- for information: the settings the live procedures were created with (the new ones get ON / ON)
SELECT d.ProcName,
       OBJECTPROPERTY(OBJECT_ID(N'dbo.' + d.ProcName), 'ExecIsQuotedIdentOn') AS QuotedIdentOn,
       OBJECTPROPERTY(OBJECT_ID(N'dbo.' + d.ProcName), 'ExecIsAnsiNullsOn')   AS AnsiNullsOn
FROM #Def AS d;

-- object-level permissions stay with the renamed backups; the new procedures start without them
IF EXISTS (SELECT 1 FROM sys.database_permissions AS p INNER JOIN #Def AS d ON p.major_id = OBJECT_ID(N'dbo.' + d.ProcName))
BEGIN
    PRINT 'WARNING: these procedures have object-level permissions; grant them again on the new versions:';
    SELECT d.ProcName, p.permission_name, p.state_desc, USER_NAME(p.grantee_principal_id) AS Grantee
    FROM sys.database_permissions AS p
    INNER JOIN #Def AS d ON p.major_id = OBJECT_ID(N'dbo.' + d.ProcName);
END

-- apply in order; each anchor must occur exactly once in the text as patched so far
DECLARE @Fail TABLE (ProcName SYSNAME, Anchor NVARCHAR(400), Matches INT);
DECLARE @id INT, @name SYSNAME, @old NVARCHAR(MAX), @new NVARCHAR(MAX), @def NVARCHAR(MAX), @n INT;
DECLARE pc CURSOR LOCAL FAST_FORWARD FOR SELECT Id, ProcName, OldText, NewText FROM #P ORDER BY Id;
OPEN pc; FETCH NEXT FROM pc INTO @id, @name, @old, @new;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @def = Def FROM #Def WHERE ProcName = @name;
    SET @n = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @old, N''))) / DATALENGTH(@old);
    IF @n = 1
        UPDATE #Def SET Def = REPLACE(Def, @old, @new) WHERE ProcName = @name;
    ELSE
        INSERT @Fail (ProcName, Anchor, Matches) VALUES (@name, LEFT(@old, 400), @n);
    FETCH NEXT FROM pc INTO @id, @name, @old, @new;
END
CLOSE pc; DEALLOCATE pc;

-- the GL block of spu_ReverseSTSLineV2
DECLARE @rev NVARCHAR(MAX) = (SELECT Def FROM #Def WHERE ProcName = N'spu_ReverseSTSLineV2');
DECLARE @nStart INT = (DATALENGTH(@rev) - DATALENGTH(REPLACE(@rev, @BlockStart, N''))) / DATALENGTH(@BlockStart),
        @nEnd   INT = (DATALENGTH(@rev) - DATALENGTH(REPLACE(@rev, @BlockEnd, N''))) / DATALENGTH(@BlockEnd);
DECLARE @s INT = CHARINDEX(@BlockStart, @rev), @e INT = CHARINDEX(@BlockEnd, @rev);
IF @nStart <> 1 OR @nEnd <> 1 OR @e <= @s
    INSERT @Fail (ProcName, Anchor, Matches) VALUES (N'spu_ReverseSTSLineV2', N'GL block banners', CASE WHEN @nStart <> 1 THEN @nStart ELSE @nEnd END);
ELSE IF CHARINDEX(N'ITR-HO-VATEX', SUBSTRING(@rev, @s, @e - @s)) = 0 OR CHARINDEX(N'@wasProcessed', SUBSTRING(@rev, @s, @e - @s)) = 0
    INSERT @Fail (ProcName, Anchor, Matches) VALUES (N'spu_ReverseSTSLineV2', N'GL block content (expected the ITR-HO posting)', 0);
ELSE
    UPDATE #Def SET Def = STUFF(@rev, @s, @e - @s, @BlockNew) WHERE ProcName = N'spu_ReverseSTSLineV2';

IF EXISTS (SELECT 1 FROM @Fail)
BEGIN
    SELECT ProcName, Anchor, Matches FROM @Fail;
    THROW 59754, 'A procedure''s text differs from the version this script was written for; nothing changed.', 1;
END

-- sanity: every new text carries the note; the return no longer posts its own ITR
IF EXISTS (SELECT 1 FROM #Def WHERE CHARINDEX(N'2026-10-01f', Def) = 0)
   OR EXISTS (SELECT 1 FROM #Def WHERE ProcName = N'spu_ReverseSTSLineV2' AND CHARINDEX(N'ITR-HO-VAT', Def) > 0)
    THROW 59755, 'Patched text failed its own check; nothing changed.', 1;

------------------------------------------------------------------
-- Rename the live procedures to backups and create the new versions,
-- all or nothing
------------------------------------------------------------------
BEGIN TRY
    BEGIN TRANSACTION;

        DECLARE @bak NVARCHAR(300), @newName SYSNAME;
        DECLARE dc CURSOR LOCAL FAST_FORWARD FOR SELECT ProcName, Def FROM #Def ORDER BY ProcName;
        OPEN dc; FETCH NEXT FROM dc INTO @name, @def;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @bak = N'dbo.' + @name;
            SET @newName = @name + N'_OLD_10012026230000';
            EXEC sp_rename @bak, @newName;
            EXEC (@def);
            PRINT 'patched ' + @name;
            FETCH NEXT FROM dc INTO @name, @def;
        END
        CLOSE dc; DEALLOCATE dc;

        -- every procedure must exist again, next to its backup, before anything is committed
        IF EXISTS (SELECT 1 FROM #Def
                   WHERE OBJECT_ID(N'dbo.' + ProcName, 'P') IS NULL
                      OR OBJECT_ID(N'dbo.' + ProcName + N'_OLD_10012026230000', 'P') IS NULL
                      OR CHARINDEX(N'2026-10-01f', OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + ProcName))) = 0)
            THROW 59756, 'Post-check failed (a procedure was renamed but not recreated); rolled back.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH

SELECT o.name, CONVERT(VARCHAR(19), o.modify_date, 120) AS modified,
       CASE WHEN CHARINDEX(N'STSTRANSIT:', OBJECT_DEFINITION(o.object_id)) > 0 THEN 'yes' ELSE 'no' END AS HasPOLock
FROM sys.objects AS o
INNER JOIN #Def AS d ON o.name IN (d.ProcName, d.ProcName + N'_OLD_10012026230000')
ORDER BY o.name;
