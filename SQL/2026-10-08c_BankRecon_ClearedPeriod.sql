/* ================================================================
   2026-10-08c: Bank Recon remembers the month an item was cleared in
   ================================================================
   Problem: an item was only "cleared" or "not cleared". Every period used
   that one flag, so a July item ticked while reconciling August also left
   July (July went out of balance by the item), and a locked month's figures
   still moved when its items were cleared later. The clear procedures
   checked the lock of the item's OWN period, so once July was locked its
   outstanding items could never be cleared in August.

   Rule (user, 2026-10-08):
     * BankStatementRecon.ClearedPeriodEnd = the period end of the month the
       item was cleared in (the Period End on the screen when it was ticked).
     * An item is open for period P when it belongs to a period <= P, is not
       reversed / voided, and is not cleared OR was cleared in a month after P.
     * A clear / unclear is refused when it would change the figures of a
       LOCKED period: the locked periods checked are the ones between the old
       and the new clearing month. Clearing a July item in August is allowed
       after July is locked (July's figures don't change).
     * An item can't be cleared in a month before its own period, and can be
       marked uncleared only from the month it was cleared in.
     * A cleared row without ClearedPeriodEnd (older writers) counts as cleared
       in its own period, which is how it behaved before. Existing cleared rows
       are back-filled that way, so every period's figures stay the same; the
       script checks this and rolls back otherwise.

   Objects (backups _OLD_10082026180000):
     table      BankStatementRecon + ClearedPeriodEnd DATE NULL
     patched    fn_BankRecon_Figures, sp_BankRecon_GetPeriod (rows show
                "cleared as of this period" + ClearedPeriodEnd),
                sp_BankRecon_GetPeriodSummary, sp_rpt_BankReconciliationRealTime,
                sp_BankRecon_AutoMatch (records the month; skips locked months)
     recreated  sp_BankRecon_ResolveItem, sp_BankRecon_BulkResolveItems,
                sp_BankRecon_ResolveAutoDebitItem: new optional @PeriodEnd.
                The current exe doesn't send it: the item is then cleared in
                its own period, as before. The new exe sends the screen's
                Period End.
   One transaction; it commits only if every period's figures are unchanged.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
BEGIN TRANSACTION;
CREATE TABLE #Patch (Id INT IDENTITY PRIMARY KEY, Obj SYSNAME NOT NULL, OldText NVARCHAR(MAX) NOT NULL, NewText NVARCHAR(MAX) NOT NULL);
-- every period's figures before the change
SELECT h.HeaderID, f.OpenDIT, f.OpenOC, f.OpenBCM, f.OpenBankDebits, f.Difference
INTO #Before
FROM dbo.BankReconHeader AS h CROSS APPLY dbo.fn_BankRecon_Figures(h.HeaderID) AS f;
GO

CREATE PROCEDURE #ApplyPatch @Obj SYSNAME
AS
BEGIN
    DECLARE @def NVARCHAR(MAX) = REPLACE(OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + @Obj)), NCHAR(13) + NCHAR(10), NCHAR(10));
    DECLARE @msg NVARCHAR(400);
    IF @def IS NULL
    BEGIN
        SET @msg = N'Cannot read the definition of ' + @Obj + N'; nothing changed.';
        THROW 59960, @msg, 1;
    END
    IF EXISTS (SELECT 1 FROM #Patch WHERE Obj = @Obj
               AND (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, OldText, N''))) / DATALENGTH(OldText) <> 1)
    BEGIN
        SET @msg = @Obj + N' text differs from the expected version (an anchor is missing or repeated); nothing changed.';
        THROW 59961, @msg, 1;
    END
    DECLARE @o NVARCHAR(MAX), @n NVARCHAR(MAX);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT OldText, NewText FROM #Patch WHERE Obj = @Obj ORDER BY Id;
    OPEN c; FETCH NEXT FROM c INTO @o, @n;
    WHILE @@FETCH_STATUS = 0 BEGIN SET @def = REPLACE(@def, @o, @n); FETCH NEXT FROM c INTO @o, @n; END
    CLOSE c; DEALLOCATE c;
    DECLARE @old SYSNAME = @Obj + N'_OLD_10082026180000', @full NVARCHAR(300) = N'dbo.' + @Obj;
    EXEC sp_rename @full, @old;
    EXEC (@def);
    IF OBJECT_ID(@full) IS NULL
    BEGIN
        SET @msg = @Obj + N' was not recreated.';
        THROW 59962, @msg, 1;
    END
END
GO

------------------------------------------------------------------
-- 1. column + back-fill (cleared rows: their own period, as before)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
IF COL_LENGTH('dbo.BankStatementRecon', 'ClearedPeriodEnd') IS NOT NULL
BEGIN
    RAISERROR('BankStatementRecon.ClearedPeriodEnd already exists: this script has been run here before.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
ALTER TABLE dbo.BankStatementRecon ADD ClearedPeriodEnd DATE NULL;
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
UPDATE b
SET    ClearedPeriodEnd = h.PeriodEnd
FROM   dbo.BankStatementRecon AS b
INNER JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
WHERE  ISNULL(b.IsResolved, 0) = 1 AND b.ClearedPeriodEnd IS NULL;
GO

------------------------------------------------------------------
-- 2. the open-item rule
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
INSERT INTO #Patch (Obj, OldText, NewText) VALUES
(N'fn_BankRecon_Figures',
 N'                   AND ISNULL(B.IsResolved, 0) = 0',
 N'                   AND (ISNULL(B.IsResolved, 0) = 0 OR COALESCE(B.ClearedPeriodEnd, HX.PeriodEnd) > H.PeriodEnd)   -- 2026-10-08c: cleared in a later month = still open here'),

(N'sp_BankRecon_GetPeriod',
 N'        BSR.Amount,
        BSR.IsResolved,
        BSR.ResolvedReason,',
 N'        BSR.Amount,
        CAST(CASE WHEN ISNULL(BSR.IsResolved, 0) = 1 AND COALESCE(BSR.ClearedPeriodEnd, H.PeriodEnd) <= @PeriodEnd THEN 1 ELSE 0 END AS BIT) AS IsResolved,   -- 2026-10-08c: cleared as of this period
        BSR.ClearedPeriodEnd,
        BSR.ResolvedReason,'),
(N'sp_BankRecon_GetPeriod',
 N'        BSR.Amount,
        BSR.IsResolved,
        NULLIF(LTRIM(RTRIM(COALESCE(',
 N'        BSR.Amount,
        CAST(CASE WHEN ISNULL(BSR.IsResolved, 0) = 1 AND COALESCE(BSR.ClearedPeriodEnd, H.PeriodEnd) <= @PeriodEnd THEN 1 ELSE 0 END AS BIT) AS IsResolved,   -- 2026-10-08c
        BSR.ClearedPeriodEnd,
        NULLIF(LTRIM(RTRIM(COALESCE('),
(N'sp_BankRecon_GetPeriod',
 N'BSR.Amount, BSR.IsResolved, BSR.ResolvedDate, BSR.ResolvedReason,',
 N'BSR.Amount, CAST(CASE WHEN ISNULL(BSR.IsResolved, 0) = 1 AND COALESCE(BSR.ClearedPeriodEnd, H.PeriodEnd) <= @PeriodEnd THEN 1 ELSE 0 END AS BIT) AS IsResolved,   -- 2026-10-08c
           BSR.ResolvedDate, BSR.ResolvedReason, BSR.ClearedPeriodEnd,'),

(N'sp_BankRecon_GetPeriodSummary',
 N'            BSR.Amount,
            BSR.IsResolved
        FROM',
 N'            BSR.Amount,
            CAST(CASE WHEN ISNULL(BSR.IsResolved, 0) = 1 AND COALESCE(BSR.ClearedPeriodEnd, H.PeriodEnd) <= @PeriodEnd THEN 1 ELSE 0 END AS BIT) AS IsResolved   -- 2026-10-08c: cleared as of this period
        FROM'),
(N'sp_BankRecon_GetPeriodSummary',
 N'            BSR.Amount,
            BSR.IsResolved,',
 N'            BSR.Amount,
            CAST(CASE WHEN ISNULL(BSR.IsResolved, 0) = 1 AND COALESCE(BSR.ClearedPeriodEnd, H.PeriodEnd) <= @PeriodEnd THEN 1 ELSE 0 END AS BIT) AS IsResolved,   -- 2026-10-08c'),

(N'sp_rpt_BankReconciliationRealTime',
 N'           b.SourceModule, b.SourceRef, b.IsResolved
    INTO #Open',
 N'           b.SourceModule, b.SourceRef, CAST(0 AS BIT) AS IsResolved   -- open as of @DateTo (2026-10-08c)
    INTO #Open'),
(N'sp_rpt_BankReconciliationRealTime',
 N'      AND ISNULL(b.IsResolved, 0) = 0',
 N'      AND (ISNULL(b.IsResolved, 0) = 0 OR COALESCE(b.ClearedPeriodEnd, h.PeriodEnd) > @DateTo)   -- 2026-10-08c: cleared in a later month = still open'),

(N'sp_BankRecon_AutoMatch',
 N'           ResolvedDate    = @PeriodEnd,',
 N'           ResolvedDate    = @PeriodEnd,
           ClearedPeriodEnd = EOMONTH(@PeriodEnd),   -- 2026-10-08c'),
(N'sp_BankRecon_AutoMatch',
 N'      AND  bsr.IsResolved  = 0',
 N'      AND  bsr.IsResolved  = 0
      AND  NOT EXISTS (SELECT 1 FROM dbo.BankReconHeader AS lh   -- 2026-10-08c: never changes a locked month
                       WHERE lh.BranchCode = bsr.BranchCode AND lh.AccountCode = bsr.AccountCode
                         AND lh.Status = ''LOCKED'' AND lh.PeriodEnd >= EOMONTH(@PeriodEnd))');
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'fn_BankRecon_Figures';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'sp_BankRecon_GetPeriod';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'sp_BankRecon_GetPeriodSummary';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'sp_rpt_BankReconciliationRealTime';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC #ApplyPatch N'sp_BankRecon_AutoMatch';
GO

------------------------------------------------------------------
-- 3. clear / unclear procedures (rename + recreate; new optional @PeriodEnd)
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
EXEC sp_rename 'dbo.sp_BankRecon_ResolveItem', 'sp_BankRecon_ResolveItem_OLD_10082026180000';
EXEC sp_rename 'dbo.sp_BankRecon_BulkResolveItems', 'sp_BankRecon_BulkResolveItems_OLD_10082026180000';
EXEC sp_rename 'dbo.sp_BankRecon_ResolveAutoDebitItem', 'sp_BankRecon_ResolveAutoDebitItem_OLD_10082026180000';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE PROCEDURE dbo.sp_BankRecon_ResolveItem
    @ReconID    INT,
    @IsResolved BIT,
    @ResolvedBy VARCHAR(50),
    @PeriodEnd  DATE = NULL     -- 2026-10-08c: the period being reconciled; NULL (older exe) = the item's own period
AS
/*
    Marks one item cleared (@IsResolved = 1) or uncleared (0) in the month @PeriodEnd.
    Rules (2026-10-08c): never before the item's own period; uncleared only from the
    month it was cleared in; refused when a locked period's figures would change.
    Errors: 93002 locked, 93003 reversed, 93010 not found, 93011 earlier month,
    93012 cleared in another month.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Branch CHAR(3), @Account VARCHAR(20), @OwnPeriod DATE, @WasResolved BIT, @Cleared DATE,
            @Reason VARCHAR(500), @msg NVARCHAR(400);

    BEGIN TRANSACTION;

    SELECT @Branch      = H.BranchCode,
           @Account     = H.AccountCode,
           @OwnPeriod   = H.PeriodEnd,
           @WasResolved = ISNULL(B.IsResolved, 0),
           @Cleared     = COALESCE(B.ClearedPeriodEnd, H.PeriodEnd),
           @Reason      = ISNULL(B.ResolvedReason, '')
    FROM dbo.BankStatementRecon AS B WITH (UPDLOCK)
    INNER JOIN dbo.BankReconHeader AS H ON H.HeaderID = B.HeaderID
    WHERE B.ReconID = @ReconID;

    IF @OwnPeriod IS NULL
        THROW 93010, 'Bank recon item not found.', 1;

    -- auto-inserted items resolved by a payment reversal are not cleared by hand
    IF @IsResolved = 1 AND @Reason = 'REVERSED'
        THROW 93003, 'This item was already resolved by a payment reversal.', 1;

    DECLARE @P DATE = EOMONTH(ISNULL(@PeriodEnd, @OwnPeriod));

    IF @P < @OwnPeriod
    BEGIN
        SET @msg = N'This item belongs to the ' + CONVERT(NVARCHAR(10), @OwnPeriod, 120) + N' period; it cannot be cleared in an earlier month.';
        THROW 93011, @msg, 1;
    END

    -- nothing to do: already cleared as of this month, or already open
    IF (@IsResolved = 1 AND @WasResolved = 1 AND @Cleared <= @P) OR (@IsResolved = 0 AND @WasResolved = 0)
    BEGIN
        COMMIT TRANSACTION;
        RETURN;
    END

    IF @IsResolved = 0 AND @PeriodEnd IS NOT NULL AND @Cleared <> @P
    BEGIN
        SET @msg = N'This item was cleared in the ' + CONVERT(NVARCHAR(10), @Cleared, 120) + N' period. Open that period to mark it uncleared.';
        THROW 93012, @msg, 1;
    END

    -- the periods whose figures change lie between the old and the new clearing month
    DECLARE @Old DATE = CASE WHEN @WasResolved = 1 THEN @Cleared ELSE '9999-12-31' END;
    DECLARE @New DATE = CASE WHEN @IsResolved = 1 THEN @P ELSE '9999-12-31' END;
    IF EXISTS (SELECT 1 FROM dbo.BankReconHeader WITH (HOLDLOCK)
               WHERE BranchCode = @Branch AND AccountCode = @Account AND Status = 'LOCKED'
                 AND PeriodEnd >= CASE WHEN @Old < @New THEN @Old ELSE @New END
                 AND PeriodEnd <  CASE WHEN @Old < @New THEN @New ELSE @Old END)
        THROW 93002, 'Cannot modify items in a locked period.', 1;

    UPDATE dbo.BankStatementRecon
    SET IsResolved       = @IsResolved,
        ResolvedDate     = CASE WHEN @IsResolved = 1 THEN GETDATE() ELSE NULL END,
        ResolvedBy       = CASE WHEN @IsResolved = 1 THEN @ResolvedBy ELSE NULL END,
        ResolvedReason   = CASE WHEN @IsResolved = 1 THEN 'CLEARED' ELSE NULL END,
        ClearedPeriodEnd = CASE WHEN @IsResolved = 1 THEN @P ELSE NULL END
    WHERE ReconID = @ReconID;

    COMMIT TRANSACTION;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE PROCEDURE dbo.sp_BankRecon_BulkResolveItems
    @ReconIDs   dbo.tt_BankReconIDList READONLY,
    @ResolvedBy VARCHAR(50),
    @ItemType   VARCHAR(5) = 'DIT',   -- 2026-10-02e: optional, so an exe older than the 09-12 form (which sent no @ItemType) still resolves DITs as before
    @PeriodEnd  DATE = NULL           -- 2026-10-08c: the period being reconciled; NULL (older exe) = each item's own period
AS
/*
    Marks the given items cleared by the bank in the month @PeriodEnd. Serves the DIT grid
    (Bulk Resolve, Resolve group by Control No), the OC grid (Bulk Resolve) and the
    summary view of BankReconFormV2. Only rows of @ItemType that are open as of that
    month are touched (an item cleared in a later month moves to this month).
    Errors: 93101 nothing selected, 93102 locked, 93103 reversed, 93104 type, 93105 earlier month.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM @ReconIDs)
        THROW 93101, 'No items were selected to resolve.', 1;

    IF @ItemType NOT IN ('OC', 'DIT', 'BCM', 'BDM', 'BC', 'NSF')
        THROW 93104, 'Invalid ItemType. Use: OC, DIT, BCM, BDM, BC, NSF', 1;

    BEGIN TRY
        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM dbo.BankStatementRecon AS BSR
                   INNER JOIN @ReconIDs AS R ON R.ReconID = BSR.ReconID
                   WHERE BSR.ResolvedReason = 'REVERSED')
            THROW 93103, 'One or more selected items were already resolved by a payment reversal.', 1;

        SELECT BSR.ReconID, H.BranchCode, H.AccountCode, H.PeriodEnd AS OwnPeriod,
               EOMONTH(ISNULL(@PeriodEnd, H.PeriodEnd)) AS P,
               CASE WHEN ISNULL(BSR.IsResolved, 0) = 1 THEN COALESCE(BSR.ClearedPeriodEnd, H.PeriodEnd) ELSE '9999-12-31' END AS OldCleared
        INTO #Sel
        FROM dbo.BankStatementRecon AS BSR WITH (UPDLOCK)
        INNER JOIN dbo.BankReconHeader AS H ON H.HeaderID = BSR.HeaderID
        INNER JOIN @ReconIDs AS R ON R.ReconID = BSR.ReconID
        WHERE BSR.ItemType = @ItemType;

        DELETE FROM #Sel WHERE OldCleared <= P;   -- already cleared as of that month: nothing to do

        IF EXISTS (SELECT 1 FROM #Sel WHERE P < OwnPeriod)
            THROW 93105, 'One or more selected items belong to a later period; they cannot be cleared in an earlier month.', 1;

        IF EXISTS (SELECT 1 FROM #Sel AS s
                   INNER JOIN dbo.BankReconHeader AS H WITH (HOLDLOCK)
                           ON H.BranchCode = s.BranchCode AND H.AccountCode = s.AccountCode AND H.Status = 'LOCKED'
                          AND H.PeriodEnd >= s.P AND H.PeriodEnd < s.OldCleared)
            THROW 93102, 'Cannot resolve items in a locked period.', 1;

        UPDATE BSR
        SET IsResolved       = 1,
            ResolvedDate     = GETDATE(),
            ResolvedBy       = @ResolvedBy,
            ResolvedReason   = 'CLEARED',
            ClearedPeriodEnd = s.P
        FROM dbo.BankStatementRecon AS BSR
        INNER JOIN #Sel AS s ON s.ReconID = BSR.ReconID;

        DECLARE @Resolved INT = @@ROWCOUNT;

        COMMIT TRAN;

        SELECT @Resolved AS ResolvedCount;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE PROCEDURE dbo.sp_BankRecon_ResolveAutoDebitItem
    @ReconID              INT,
    @SupplierID            VARCHAR(50),
    @BatchReferenceID      BIGINT,
    @InvoiceNo             VARCHAR(150),
    @ReferenceNo           VARCHAR(10),
    @VoucherID             VARCHAR(10),
    @User                  VARCHAR(50),
    @PeriodEnd             DATE = NULL   -- 2026-10-08c: the period being reconciled; NULL (older exe) = the item's own period
AS
/*
    Called AFTER C# has posted the payment via sp_AddPaymentSupplierCompound: marks the
    auto-debit row cleared (in the month @PeriodEnd) and records which invoice and which
    generated reference + voucher settled it.
    Errors: 60011 locked, 60012 already resolved, 60013 earlier month.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Branch CHAR(3), @Account VARCHAR(20), @OwnPeriod DATE, @msg NVARCHAR(400);

    BEGIN TRANSACTION;

    SELECT @Branch = h.BranchCode, @Account = h.AccountCode, @OwnPeriod = h.PeriodEnd
    FROM dbo.BankStatementRecon AS bsr WITH (UPDLOCK)
    INNER JOIN dbo.BankReconHeader AS h ON h.HeaderID = bsr.HeaderID
    WHERE bsr.ReconID = @ReconID;

    DECLARE @P DATE = EOMONTH(ISNULL(@PeriodEnd, @OwnPeriod));

    IF @OwnPeriod IS NOT NULL AND @P < @OwnPeriod
    BEGIN
        SET @msg = N'This item belongs to the ' + CONVERT(NVARCHAR(10), @OwnPeriod, 120) + N' period; it cannot be cleared in an earlier month.';
        THROW 60013, @msg, 1;
    END

    IF EXISTS (SELECT 1 FROM dbo.BankReconHeader WITH (HOLDLOCK)
               WHERE BranchCode = @Branch AND AccountCode = @Account AND Status = 'LOCKED' AND PeriodEnd >= @P)
        THROW 60011, 'Cannot resolve - this reconciliation period is locked.', 1;

    IF EXISTS (SELECT 1 FROM dbo.BankStatementRecon WHERE ReconID = @ReconID AND IsResolved = 1)
        THROW 60012, 'This item is already resolved.', 1;

    UPDATE dbo.BankStatementRecon
    SET IsResolved              = 1,
        ResolvedDate            = GETDATE(),
        ResolvedBy              = @User,
        ResolvedReason          = 'AUTO-DEBIT POSTED',
        ClearedPeriodEnd        = @P,
        MatchedSupplierID       = @SupplierID,
        MatchedBatchReferenceID = @BatchReferenceID,
        MatchedInvoiceNo        = @InvoiceNo,
        PostedReferenceNo       = @ReferenceNo,
        PostedVoucherID         = @VoucherID,
        SourceModule            = 'PAYMENT',
        SourceRef               = @ReferenceNo,
        UpdatedBy               = @User,
        DateTimeUpdated         = GETDATE()
    WHERE ReconID = @ReconID;

    COMMIT TRANSACTION;

    SELECT 'OK' AS Result, 'Item resolved.' AS Message;
END
GO

------------------------------------------------------------------
-- 4. post-check: every period's figures unchanged, every object in place
------------------------------------------------------------------
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
DECLARE @bad INT = (SELECT COUNT(*)
                    FROM #Before AS b
                    CROSS APPLY dbo.fn_BankRecon_Figures(b.HeaderID) AS f
                    WHERE f.OpenDIT <> b.OpenDIT OR f.OpenOC <> b.OpenOC OR f.OpenBCM <> b.OpenBCM
                       OR f.OpenBankDebits <> b.OpenBankDebits OR f.Difference <> b.Difference);
IF @bad > 0
   OR (SELECT COUNT(*) FROM #Before) <> (SELECT COUNT(*) FROM dbo.BankReconHeader)
   OR OBJECT_ID('dbo.sp_BankRecon_ResolveItem', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_BankRecon_BulkResolveItems', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_BankRecon_ResolveAutoDebitItem', 'P') IS NULL
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.fn_BankRecon_Figures')) NOT LIKE '%ClearedPeriodEnd%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_BankRecon_GetPeriod')) NOT LIKE '%ClearedPeriodEnd%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_BankRecon_GetPeriodSummary')) NOT LIKE '%ClearedPeriodEnd%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_rpt_BankReconciliationRealTime')) NOT LIKE '%ClearedPeriodEnd%'
   OR OBJECT_DEFINITION(OBJECT_ID('dbo.sp_BankRecon_AutoMatch')) NOT LIKE '%ClearedPeriodEnd%'
BEGIN
    RAISERROR('Post-check failed (a period''s figures changed, or an object is missing); rolled back.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
COMMIT TRANSACTION;
PRINT 'Bank Recon cleared-period change applied (backups _OLD_10082026180000).';
GO
SET NOEXEC OFF;
GO
