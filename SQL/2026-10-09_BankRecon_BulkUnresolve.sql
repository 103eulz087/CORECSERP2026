/* ================================================================
   2026-10-09: Bank Recon - mark many items uncleared at once
   ================================================================
   New procedure dbo.sp_BankRecon_BulkUnresolveItems, the mirror of
   sp_BankRecon_BulkResolveItems. User request: an accidental "Clear Entire
   Batch" / "Bulk Resolve" / group tick must be undoable in one step; until
   now only one item at a time could be marked uncleared (sp_BankRecon_ResolveItem).

   Rules (same as the single-item unclear, 2026-10-08c / 08e):
     * only items cleared by hand ('CLEARED', or blank = the old Auto-Match /
       old screens) in the month @PeriodEnd (the period on screen) are undone;
     * skipped and counted: items cleared in another month (open that month),
       items not cleared, and items closed by the system (REVERSED, VOIDED%,
       'AUTO-DEBIT POSTED': their payment is posted, so they are not "ticks");
     * refused as a whole (93113) when a locked period's figures would change
       (any LOCKED period of the account from the clearing month on).
   One transaction: all eligible items are undone, or none.
   Returns: UnclearedCount, SkippedOtherMonth, SkippedNotCleared, SkippedSystem.
   New object only; nothing existing changes. Works only with the new exe
   (the current exe doesn't call it).
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;

IF OBJECT_ID('dbo.sp_BankRecon_BulkUnresolveItems', 'P') IS NOT NULL
    THROW 93110, 'dbo.sp_BankRecon_BulkUnresolveItems already exists: this script has been run here before.', 1;
IF COL_LENGTH('dbo.BankStatementRecon', 'ClearedPeriodEnd') IS NULL
    THROW 93110, 'Run 2026-10-08c_BankRecon_ClearedPeriod.sql first.', 1;
GO

CREATE PROCEDURE dbo.sp_BankRecon_BulkUnresolveItems
    @ReconIDs   dbo.tt_BankReconIDList READONLY,
    @ResolvedBy VARCHAR(50),
    @PeriodEnd  DATE              -- the period on screen; only items cleared in this month are undone
AS
/*
    Marks the given items uncleared (the opposite of sp_BankRecon_BulkResolveItems).
    Callers: BankReconFormV2 "Unclear Entire Batch" (detailed and summary views) and
    "Bulk Unclear". Errors: 93111 nothing selected, 93112 no period, 93113 locked.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM @ReconIDs)
        THROW 93111, 'No items were selected to mark uncleared.', 1;
    IF @PeriodEnd IS NULL
        THROW 93112, 'The period on screen is required to mark items uncleared.', 1;

    DECLARE @P DATE = EOMONTH(@PeriodEnd);

    BEGIN TRY
        BEGIN TRAN;

        SELECT  b.ReconID, h.BranchCode, h.AccountCode,
                CAST(ISNULL(b.IsResolved, 0) AS INT)        AS WasResolved,
                LTRIM(RTRIM(ISNULL(b.ResolvedReason, '')))   AS Reason,
                COALESCE(b.ClearedPeriodEnd, h.PeriodEnd)    AS ClearedIn
        INTO #Sel
        FROM dbo.BankStatementRecon AS b WITH (UPDLOCK)
        INNER JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
        INNER JOIN @ReconIDs AS r ON r.ReconID = b.ReconID;

        DECLARE @NotCleared INT = (SELECT COUNT(*) FROM #Sel WHERE WasResolved = 0);
        DECLARE @System     INT = (SELECT COUNT(*) FROM #Sel WHERE WasResolved = 1 AND Reason NOT IN ('CLEARED', ''));
        DECLARE @OtherMonth INT = (SELECT COUNT(*) FROM #Sel WHERE WasResolved = 1 AND Reason IN ('CLEARED', '') AND ClearedIn <> @P);

        DELETE FROM #Sel WHERE NOT (WasResolved = 1 AND Reason IN ('CLEARED', '') AND ClearedIn = @P);

        -- unclearing changes every period from the clearing month on
        IF EXISTS (SELECT 1 FROM #Sel AS s
                   INNER JOIN dbo.BankReconHeader AS h WITH (HOLDLOCK)
                           ON h.BranchCode = s.BranchCode AND h.AccountCode = s.AccountCode
                          AND h.Status = 'LOCKED' AND h.PeriodEnd >= s.ClearedIn)
            THROW 93113, 'Cannot mark these items uncleared: a locked period would change.', 1;

        UPDATE b
        SET IsResolved       = 0,
            ResolvedDate     = NULL,
            ResolvedBy       = NULL,
            ResolvedReason   = NULL,
            ClearedPeriodEnd = NULL,
            UpdatedBy        = @ResolvedBy,
            DateTimeUpdated  = GETDATE()
        FROM dbo.BankStatementRecon AS b
        INNER JOIN #Sel AS s ON s.ReconID = b.ReconID;

        DECLARE @Done INT = @@ROWCOUNT;

        COMMIT TRAN;

        SELECT @Done AS UnclearedCount, @OtherMonth AS SkippedOtherMonth,
               @NotCleared AS SkippedNotCleared, @System AS SkippedSystem;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO
