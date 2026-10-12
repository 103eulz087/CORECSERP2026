/* ================================================================
   2026-10-08d: stamp the clearing month of items ticked before 2026-10-08c
   ================================================================
   Data only. Run AFTER 2026-10-08c, and only where items of an earlier period
   were ticked while a later period was on screen BEFORE the new exe was in use
   (the old screen sent no month, so 08c's back-fill put them in their own period).
   Case it was written for: PRODUCTION, BDO PESO 1, the accountant ticks the
   August statement (July Peachtree items included) on the Aug 31 screen with the
   old exe, from 2026-10-09.

   Set the four values below. The script changes only rows that:
     * belong to that branch + account and to a period BEFORE @ClearedIn,
     * were cleared by hand (ResolvedReason 'CLEARED') on or after @TickedFrom
       and before @TickedTo,
     * still carry their own period as the clearing month (08c's back-fill),
   and moves their clearing month to @ClearedIn. It refuses if a locked period
   would change, and lists what it changed. One transaction.
   ================================================================ */

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Branch     CHAR(3)     = '888';
DECLARE @Account    VARCHAR(20) = '101020101';    -- BDO PESO 1
DECLARE @ClearedIn  DATE        = '2026-08-31';   -- the period that was on screen
DECLARE @TickedFrom DATETIME    = '2026-10-09';   -- when the ticking on that screen started
DECLARE @TickedTo   DATETIME    = '2026-10-10';   -- and ended (exclusive)

IF COL_LENGTH('dbo.BankStatementRecon', 'ClearedPeriodEnd') IS NULL
    THROW 93501, 'Run 2026-10-08c_BankRecon_ClearedPeriod.sql first.', 1;

BEGIN TRANSACTION;

    SELECT b.ReconID, b.ItemType, b.ReferenceNo, b.Amount, h.PeriodEnd AS OwnPeriod, b.ResolvedBy, b.ResolvedDate
    INTO #Move
    FROM dbo.BankStatementRecon AS b WITH (UPDLOCK)
    INNER JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
    WHERE h.BranchCode = @Branch AND h.AccountCode = @Account
      AND h.PeriodEnd < @ClearedIn
      AND ISNULL(b.IsResolved, 0) = 1 AND b.ResolvedReason = 'CLEARED'
      AND b.ResolvedDate >= @TickedFrom AND b.ResolvedDate < @TickedTo
      AND b.ClearedPeriodEnd = h.PeriodEnd;

    -- the periods that change: from the own period up to (not including) @ClearedIn
    IF EXISTS (SELECT 1 FROM #Move AS m
               INNER JOIN dbo.BankReconHeader AS h WITH (HOLDLOCK)
                       ON h.BranchCode = @Branch AND h.AccountCode = @Account AND h.Status = 'LOCKED'
                      AND h.PeriodEnd >= m.OwnPeriod AND h.PeriodEnd < @ClearedIn)
        THROW 93502, 'A locked period would change; nothing changed.', 1;

    UPDATE b
    SET    ClearedPeriodEnd = @ClearedIn
    FROM   dbo.BankStatementRecon AS b
    INNER JOIN #Move AS m ON m.ReconID = b.ReconID;

COMMIT TRANSACTION;

SELECT m.ReconID, m.ItemType, m.ReferenceNo, m.Amount, CONVERT(VARCHAR(10), m.OwnPeriod, 120) AS OwnPeriod,
       CONVERT(VARCHAR(10), @ClearedIn, 120) AS ClearedIn, m.ResolvedBy, m.ResolvedDate
FROM #Move AS m ORDER BY m.OwnPeriod, m.ItemType, m.ReconID;

SELECT CONVERT(VARCHAR(10), h.PeriodEnd, 120) AS PeriodEnd, f.OpenDIT, f.OpenOC, f.Difference
FROM dbo.BankReconHeader AS h CROSS APPLY dbo.fn_BankRecon_Figures(h.HeaderID) AS f
WHERE h.BranchCode = @Branch AND h.AccountCode = @Account
ORDER BY h.PeriodEnd;
